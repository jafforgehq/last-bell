## What E can use in the town beyond the colony's own kinds (One House, WP3, plan 1.13): one list of the candidates of the town's modules, one use()
## to send a pressed E to the module that owns the kind, and the one SESSION in hand (a search of 4 s, the claim of 2 s) with its progress for the ring.
##
## PROVIDERS. Each is a sim module with `candidates(p) -> Array` (the shape of `Interact.candidates`: {kind, id, label, pos, dist, ok, why}, plus
## `session: true` when the use begins a session) and `use(c) -> Dictionary` ({ok, line, why, ...}). They are found by name on the sim every call, so a
## package that has not landed is skipped and the order of landing does not matter: clearing (kind "door"), search ("container"), base ("claim",
## "stash"), sleep ("bed"), rescue ("rescue"), perimeter ("slot", "gate_base"). `register(provider)` adds one more. A provider's `use(c)` must return {}
## for a kind that is not its own and change nothing (the candidates are tagged `by`, the provider's place in the list, so the right one is asked first;
## a candidate that comes without the tag is offered to each in turn).
##
## SELF-CARE. One survivor has nobody to bandage them (the colony's medical module sends another person, never the patient): while the avatar bleeds E offers "Bandage the wound"
## (a session of BANDAGE_S, one medicine) and while it is infected "Treat the infection" (CURE_S, two medicine, the chance of the avatar's own skill). Without it a bite would be the end of
## a lone survivor, and no search or claim could be done while a wound bleeds.
##
## A SESSION is the avatar's hands at one thing, as the bench and the wall are: `begin_session` takes the avatar's feet to one spot, `update` runs it
## down, and it ends, undone, when the avatar walks, fires, swings, is hurt (a new wound: the bleeding of an old one is not), falls, goes out of reach, or the bench or the wall is taken in hand. It
## ends done at `of` seconds and then calls the provider's `done`. `progress()` is what the progress ring reads.
extends RefCounted

const HANDS_ON := 0.25
const EPS := 1.0e-6
## The seconds of the avatar's own bandage and treatment, and how far "away" their prompt sits (so that a door or a shelf within reach has the E before it).
const BANDAGE_S := 4.0
const CURE_S := 7.0
const SELF_DIST := 1.9
## A drop of health in one step bigger than this is a blow (a bite), not the slow loss of a wound that bleeds.
const HURT_DROP := 0.4
const PROVIDERS := ["clearing", "search", "base", "sleep", "rescue", "perimeter"]

var sim
var enabled := true
## Providers added by `register` (the named ones above are found on the sim).
var extra: Array = []
## The session in hand: {kind, id, label, t, of, at, reach, done}, {} for none.
var _s := {}
var _who := ""
var _hp_last := 0.0


func setup(s) -> void:
	sim = s


func start() -> void:
	_s = {}
	_who = ""
	_hp_last = 0.0


func register(provider) -> void:
	if provider != null and not extra.has(provider):
		extra.append(provider)


func _providers() -> Array:
	var out: Array = []
	for n in PROVIDERS:
		var m = sim.get(n)
		if m != null and typeof(m) == TYPE_OBJECT and m.has_method("candidates"):
			out.append(m)
	for m in extra:
		if not out.has(m):
			out.append(m)
	return out


func _lead():
	if String(sim.player_id) == "":
		return null
	return sim.avatar.player()


## What E could use from where the avatar stands, from every provider (Interact orders them with its own).
func candidates(p) -> Array:
	var out: Array = []
	if p == null or not enabled:
		return out
	var list := _providers()
	for i in list.size():
		var got = list[i].candidates(p)
		if typeof(got) != TYPE_ARRAY:
			continue
		for c in got:
			c["by"] = i
			out.append(c)
	out.append_array(_selfcare(p))
	return out


## E at a candidate: the provider's own answer, {} turned into "Nothing here to use".
func use(c: Dictionary) -> Dictionary:
	if String(c.get("kind", "")) == "selfcare":
		return _use_selfcare(String(c.get("id", "")))
	var list := _providers()
	var by := int(c.get("by", -1))
	if by >= 0 and by < list.size():
		var r = list[by].use(c)
		if typeof(r) == TYPE_DICTIONARY and not r.is_empty():
			return r
	for i in list.size():
		if i == by or not list[i].has_method("use"):
			continue
		var r = list[i].use(c)
		if typeof(r) == TYPE_DICTIONARY and not r.is_empty():
			return r
	return {"ok": false, "line": "", "why": "Nothing here to use"}


# ------------------------------------------------------------------------ self-care --

func _meds() -> float:
	return float(sim.stock.get("meds", 0.0))


## "Bandage the wound" while the avatar bleeds, "Treat the infection" while it is infected (each refused, with its reason, when the stores are short).
func _selfcare(p) -> Array:
	var out: Array = []
	if p.dead or p.turned or p.downed or p.away != null or sim.medical == null:
		return out
	var here := Vector2(p.x, p.y)
	if float(p.bleeding) > 0.0:
		var stop := in_session("selfcare", "bandage")
		var have: bool = _meds() + EPS >= float(sim.medical.BANDAGE_MEDS)
		out.append({"kind": "selfcare", "id": "bandage", "label": "Stop" if stop else "Bandage the wound", "pos": here, "dist": SELF_DIST, "ok": stop or have,
				"why": "" if (stop or have) else "You have no medicine", "session": true, "by": -1})
	if float(p.infected_at) >= 0.0:
		var stop2 := in_session("selfcare", "cure")
		var have2: bool = _meds() + EPS >= float(sim.medical.CURE_MEDS)
		out.append({"kind": "selfcare", "id": "cure", "label": "Stop" if stop2 else "Treat the infection", "pos": here, "dist": SELF_DIST + 0.1, "ok": stop2 or have2,
				"why": "" if (stop2 or have2) else "It takes 2 medicine", "session": true, "by": -1})
	return out


func _use_selfcare(id: String) -> Dictionary:
	var p = _lead()
	if p == null:
		return {"ok": false, "line": "", "why": "You are not here", "session": true}
	if in_session("selfcare", id):
		cancel("stopped")
		return {"ok": true, "line": "Stopped.", "why": "", "session": true, "stopped": true}
	var here := Vector2(p.x, p.y)
	var r: Dictionary = {}
	if id == "bandage":
		if float(p.bleeding) <= 0.0:
			return {"ok": false, "line": "", "why": "You are not bleeding", "session": true}
		if _meds() + EPS < float(sim.medical.BANDAGE_MEDS):
			return {"ok": false, "line": "", "why": "You have no medicine", "session": true}
		r = begin_session("selfcare", id, "Bandaging", BANDAGE_S, here, 0.6, Callable(self, "_bandaged"))
		if bool(r.get("ok", false)):
			return {"ok": true, "line": "Bandaging the wound", "why": "", "session": true, "seconds": BANDAGE_S}
	elif id == "cure":
		if float(p.infected_at) < 0.0:
			return {"ok": false, "line": "", "why": "You are not infected", "session": true}
		if _meds() + EPS < float(sim.medical.CURE_MEDS):
			return {"ok": false, "line": "", "why": "It takes 2 medicine", "session": true}
		r = begin_session("selfcare", id, "Treating", CURE_S, here, 0.6, Callable(self, "_cured"))
		if bool(r.get("ok", false)):
			return {"ok": true, "line": "Treating the infection", "why": "", "session": true, "seconds": CURE_S}
	else:
		return {"ok": false, "line": "", "why": "Nothing here to use", "session": true}
	return {"ok": false, "line": "", "why": String(r.get("why", "")), "session": true}


func _bandaged() -> void:
	var p = _lead()
	if p == null or float(p.bleeding) <= 0.0 or _meds() + EPS < float(sim.medical.BANDAGE_MEDS):
		return
	sim.medical._use_meds(float(sim.medical.BANDAGE_MEDS))
	p.bleeding = 0.0
	p.wounds = 0
	sim.alert("self-bandage", "info", "Wound bandaged", "The bleeding has stopped. One medicine used", null, 8.0)


func _cured() -> void:
	var p = _lead()
	if p == null or float(p.infected_at) < 0.0 or _meds() + EPS < float(sim.medical.CURE_MEDS):
		return
	if sim.medical.try_cure(p, p):
		sim.alert("self-cure", "info", "The infection is gone", "The treatment worked", null, 10.0)
	else:
		sim.alert("self-cure", "warn", "The treatment did not take", "Still infected. Try again (2 medicine)", null, 10.0)


# ------------------------------------------------------------------- the session --

## Begins the session: {"ok", "why"}. Refused with a hand on the keys or the trigger, and when the avatar cannot act. Whatever the hands had (the
## bench, a wall being mended, an earlier session) is let go first.
func begin_session(kind: String, id: String, label: String, seconds: float, at: Vector2, reach: float, done: Callable) -> Dictionary:
	var p = _lead()
	if p == null:
		return {"ok": false, "why": "You are not here"}
	if p.dead or p.turned or p.downed or p.away != null:
		return {"ok": false, "why": "You cannot do that now"}
	if p.input_move.length() > HANDS_ON or p.input_fire or p.input_melee:
		return {"ok": false, "why": "Stand still first"}
	if sim.interact.working != "":
		sim.interact.stop_work("stopped")
	if sim.nights != null and String(sim.nights.working) == "wall":
		sim.nights.stop_mend("stopped")
	_s = {"kind": kind, "id": id, "label": label, "t": 0.0, "of": maxf(seconds, 0.1), "at": at, "reach": reach, "done": done}
	_who = String(p.id)
	_hp_last = float(p.hp)
	return {"ok": true, "why": ""}


## Whether this very thing is the session in hand (its candidate then offers to stop it).
func in_session(kind: String, id: String) -> bool:
	return not _s.is_empty() and String(_s.kind) == kind and String(_s.id) == id


func busy() -> bool:
	return not _s.is_empty()


## Ends the session undone (E again, or the hands, the wound, the reach).
func cancel(_why: String = "") -> void:
	if _s.is_empty():
		return
	var p = _lead()
	if p != null and String(p.activity) == String(_s.label):
		p.activity = ""
	_s = {}


## {"label": "Searching", "t": seconds so far, "of": seconds in all}; the label is "" with no session.
func progress() -> Dictionary:
	if _s.is_empty():
		return {"label": "", "t": 0.0, "of": 0.0}
	return {"label": String(_s.label), "t": float(_s.t), "of": float(_s.of)}


func update(dt: float) -> void:
	if _s.is_empty():
		return
	var p = _lead()
	var why := ""
	if p == null:
		why = "gone"
	elif String(p.id) != _who:
		why = "another player"
	elif p.dead or p.turned or p.downed or p.away != null:
		why = "down"
	elif p.input_move.length() > HANDS_ON:
		why = "moved"
	elif p.input_fire or p.input_melee:
		why = "fired"
	elif float(p.hp) < _hp_last - HURT_DROP:
		why = "hurt"
	elif Vector2(p.x, p.y).distance_to(Vector2(_s.at)) > float(_s.reach):
		why = "moved"
	elif sim.interact.working != "" or (sim.nights != null and String(sim.nights.working) == "wall"):
		why = "other hands"
	if why != "":
		cancel(why)
		return
	_hp_last = float(p.hp)
	_s.t = float(_s.t) + dt
	p.activity = String(_s.label)
	if float(_s.t) >= float(_s.of) - EPS:
		var done: Callable = _s.done
		_s = {}
		p.activity = ""
		if done.is_valid():
			done.call()


# -------------------------------------------------------------------------- save --

## Nothing is saved: a session is never resumed (the bench's rule).
func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	start()
