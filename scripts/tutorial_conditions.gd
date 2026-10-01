## The conditions of Orientation Day: what a step waits for before it is done (`done`), what
## a step waits for before it begins (`start`, `pause_until`) and what decides where the
## coach points (`when` on an anchor). assets/data/tutorial.json names them as
## {"cond": name, "params": {...}}; the coach (scripts/ui/coach.gd) evaluates them.
##
## Each is a Callable(sim, params, state) -> bool in the registry below. `sim` is the
## game's rules, `params` the step's own numbers and names, and `state` what the coach
## keeps for the step it is on (plain data, saved with the run):
##   "t"          real seconds since the step began
##   "pan"        tiles the view has been panned since it began
##   "zoom"       how far the view has been zoomed since it began (the size of the log
##                of each factor, added up)
##   "did"        what the player did since it began, counted: "select:person:ruth",
##                "gizmo:draft", "move", "speed:3", "save", "fields"...
##   "events"     the rules' events since it began, counted by type: "shot", "bell"... (an "assigned"
##                event that names a station, a job given, also counts as "assigned:job": one that
##                takes a job away does not)
##   "next"       the card's Got it was pressed
##   "base"       the world as the step began: {"ammo": n, "kills": n, "pos": {person id: [x, y]}}
##   "selection"  {"kind": "person", "id": "ruth"}, {"kind": "segment", "id": 3} or {}
##   "speed"      the game's speed (0 to 3), "fields": the fields-of-fire view is on
##   "dialog"     {"open": bool, "site": the place chosen in the scavenging dialog or ""}
##   "jobs"       {"open": bool}: the Duty roster's page (key J) is open
## A condition may note something in `state` (a wound seen, say), but never reads the
## screen: anything it needs the coach has put in `state`, so the tests can drive it.
extends RefCounted

## name -> Callable(sim, params, state), filled once.
static var _table := {}


static func registry() -> Dictionary:
	if _table.is_empty():
		_table = {
			"always": _always,
			"never": _never,
			"next": _next,
			"elapsed": _elapsed,
			"did": _did,
			"event": _event,
			"look_around": _look_around,
			"selected": _selected,
			"ordered": _ordered,
			"arrived": _arrived,
			"released": _released,
			"post_ordered": _post_ordered,
			"posted": _posted,
			"repair_ordered": _repair_ordered,
			"wall_mended": _wall_mended,
			"dialog_open": _dialog_open,
			"site_chosen": _site_chosen,
			"party_out": _party_out,
			"speed_pressed": _speed_pressed,
			"forecast_given": _forecast_given,
			"bell_rung": _bell_rung,
			"ammo_spent": _ammo_spent,
			"kills": _kills,
			"ammo_gained": _ammo_gained,
			"fields_on": _fields_on,
			"lure_set": _lure_set,
			"healed": _healed,
			"treat_ordered": _treat_ordered,
			"cured": _cured,
			"saved": _saved,
			"day_started": _day_started,
			"crafting": _crafting,
			"jobs_open": _jobs_open,
			"jobs_given": _jobs_given,
			"low_stores": _low_stores,
			"low_ammo": _low_ammo,
			"wounded": _wounded,
			"feverish": _feverish,
			"breached": _breached,
			"kind_alive": _kind_alive,
			"all": _all,
			"any": _any,
			"not": _not,
		}
	return _table


## Whether `name` is a condition.
static func has(name: String) -> bool:
	return registry().has(name)


## Evaluates `spec` ({"cond": name, "params": {...}}, or an empty one, which holds).
## A condition that is not in the registry does not hold.
static func check(spec: Dictionary, sim, state: Dictionary) -> bool:
	if spec.is_empty():
		return true
	var name := String(spec.get("cond", ""))
	var table := registry()
	if not table.has(name):
		return false
	var params = spec.get("params", {})
	return bool(table[name].call(sim, params if typeof(params) == TYPE_DICTIONARY else {}, state))


# ------------------------------------------------------------------ helpers --

static func _person(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


static func _wall(sim, id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


static func _counted(table, key: String) -> float:
	return float(table.get(key, 0.0)) if typeof(table) == TYPE_DICTIONARY else 0.0


# ---------------------------------------------------------------- the basics --

static func _always(_sim, _p, _st) -> bool:
	return true


static func _never(_sim, _p, _st) -> bool:
	return false


## The card's Got it button was pressed.
static func _next(_sim, _p, st) -> bool:
	return bool(st.get("next", false))


## {"seconds": s}: the step has been up this long.
static func _elapsed(_sim, p, st) -> bool:
	return float(st.get("t", 0.0)) >= float(p.get("seconds", 0.0))


## {"what": "gizmo:draft"}: the player did that (see main.gd's _did) at least once.
static func _did(_sim, p, st) -> bool:
	return _counted(st.get("did", {}), String(p.get("what", ""))) > 0.0


## {"type": "shot", "min": 3}: the rules produced that many events of that type since the step began.
static func _event(_sim, p, st) -> bool:
	return _counted(st.get("events", {}), String(p.get("type", ""))) >= float(p.get("min", 1.0))


## {"pan": tiles, "zoom": amount}: the view was panned and zoomed this much.
static func _look_around(_sim, p, st) -> bool:
	return float(st.get("pan", 0.0)) >= float(p.get("pan", 6.0)) and float(st.get("zoom", 0.0)) >= float(p.get("zoom", 0.15))


## {"who": person id} or {"wall": section id}: that one is selected.
static func _selected(_sim, p, st) -> bool:
	var sel = st.get("selection", {})
	if typeof(sel) != TYPE_DICTIONARY or sel.is_empty():
		return false
	if p.has("who"):
		return sel.get("kind", "") == "person" and String(sel.get("id", "")) == String(p.who)
	if p.has("wall"):
		return sel.get("kind", "") == "segment" and int(sel.get("id", -1)) == int(p.wall)
	return true


# ------------------------------------------------------------------- orders --

## {"who": id, "min_dist": tiles}: sent somewhere (an order to walk, not a post), at least
## min_dist tiles from where they stood when the step began.
static func _ordered(sim, p, st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	if who == null or who.order == null or who.order.z > 0.5:
		return false
	var start = st.get("base", {}).get("pos", {}).get(who.id)
	if typeof(start) == TYPE_ARRAY and start.size() == 2:
		var target := Vector2(who.order.x, who.order.y)
		return Vector2(float(start[0]), float(start[1])).distance_to(target) >= float(p.get("min_dist", 0.0))
	return true


## Like `ordered`, and they have got there.
static func _arrived(sim, p, st) -> bool:
	if not _ordered(sim, p, st):
		return false
	var who = _person(sim, String(p.get("who", "")))
	return Vector2(who.x, who.y).distance_to(Vector2(who.order.x, who.order.y)) < float(p.get("radius", 0.8))


## {"who": id}: back to their routine (no order, not drafted).
static func _released(sim, p, _st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	return who != null and not who.drafted and who.order == null


## {"who": id}: told to go to their post.
static func _post_ordered(sim, p, _st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	return who != null and who.order != null and who.order.z > 0.5


## Told to go to their post, and they are standing at it.
static func _posted(sim, p, st) -> bool:
	if not _post_ordered(sim, p, st):
		return false
	var who = _person(sim, String(p.get("who", "")))
	return Vector2(who.x, who.y).distance_to(Vector2(who.order.x, who.order.y)) < float(p.get("radius", 0.8))


## {"wall": id}: somebody has been told to mend that wall piece.
static func _repair_ordered(sim, p, _st) -> bool:
	for who in sim.people:
		if who.repair != null and who.repair.id == int(p.get("wall", -1)):
			return true
	return false


## {"wall": id, "frac": share}: that wall piece is at least this whole.
static func _wall_mended(sim, p, _st) -> bool:
	var seg = _wall(sim, int(p.get("wall", -1)))
	return seg != null and seg.hp >= seg.max_hp * float(p.get("frac", 0.99)) - 0.001


## The scavenging dialog is open, and a place has been chosen in it.
static func _dialog_open(_sim, _p, st) -> bool:
	return bool(st.get("dialog", {}).get("open", false))


static func _site_chosen(_sim, _p, st) -> bool:
	var d = st.get("dialog", {})
	return bool(d.get("open", false)) and String(d.get("site", "")) != ""


## A party has been sent out.
static func _party_out(sim, _p, _st) -> bool:
	return not sim.scavenge.parties.is_empty()


## {"n": speed}: the player pressed that speed.
static func _speed_pressed(_sim, p, st) -> bool:
	return _counted(st.get("did", {}), "speed:%d" % int(p.get("n", 3))) > 0.0


# ---------------------------------------------------------------- the world --

## The lookout has given tonight's forecast.
static func _forecast_given(sim, _p, _st) -> bool:
	return bool(sim.tactics.forecast().get("given", false))


## The dusk bell has rung (and it is not yet dawn).
static func _bell_rung(sim, _p, _st) -> bool:
	return sim.bell_rung and sim.phase != "day"


## {"min": n}: that much ammo has gone since the step began.
static func _ammo_spent(sim, p, st) -> bool:
	return float(st.get("base", {}).get("ammo", sim.stock.ammo)) - float(sim.stock.ammo) >= float(p.get("min", 1.0))


## {"min": n}: that many of the dead have been shot since the step began.
static func _kills(sim, p, st) -> bool:
	return float(sim.kills) - float(st.get("base", {}).get("kills", sim.kills)) >= float(p.get("min", 3.0))


## {"min": n}: that much ammo has been made since the step began.
static func _ammo_gained(sim, p, st) -> bool:
	return float(sim.stock.ammo) - float(st.get("base", {}).get("ammo", sim.stock.ammo)) >= float(p.get("min", 8.0))


static func _fields_on(_sim, _p, st) -> bool:
	return bool(st.get("fields", false))


static func _lure_set(sim, _p, _st) -> bool:
	return sim.tactics.lure_id >= 0


## {"who": id}: their wound has been bandaged (and was seen bleeding first; if it
## never shows, the step does not wait for it).
static func _healed(sim, p, st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	if who == null:
		return true
	if who.bleeding > 0.0:
		st["seen"] = true
	if bool(st.get("seen", false)):
		return who.bleeding <= 0.0
	return float(st.get("t", 0.0)) > 3.0


## {"who": id}: told to be treated (or already cured).
static func _treat_ordered(sim, p, _st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	return who == null or who.infected_at < 0.0 or sim.medical.treat_orders.has(who.id)


## {"who": id}: their fever is gone (and was seen first, as for `healed`).
static func _cured(sim, p, st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	if who == null:
		return true
	if who.infected_at >= 0.0:
		st["seen"] = true
	if bool(st.get("seen", false)):
		return who.infected_at < 0.0
	return float(st.get("t", 0.0)) > 3.0


static func _saved(_sim, _p, st) -> bool:
	return _counted(st.get("did", {}), "save") > 0.0


## {"day": n}: day n has begun (the dawn after the night has come).
static func _day_started(sim, p, _st) -> bool:
	return sim.day >= int(p.get("day", 2)) and sim.phase == "day"


## Somebody (or {"who": id}) has the worktable's job (the Workbench: the key M gives it). It is the
## job that counts, not the work: a lesson that waits for it holds the game still, and nobody
## walks to the bench while it does. Without a workshop it never is.
static func _crafting(sim, p, _st) -> bool:
	var shop = sim.get("workshop")
	if shop == null:
		return false
	var has_it := func(who) -> bool:
		return sim.jobs.job_of(who) == "bench" if sim.get("jobs") != null else bool(shop.crafting(who))
	if p.has("who"):
		var who = _person(sim, String(p.who))
		return who != null and has_it.call(who)
	for who in sim.people:
		if has_it.call(who):
			return true
	return false


# ----------------------------------------------------------- the duty roster --

## The Duty roster's page (key J) is open.
static func _jobs_open(_sim, _p, st) -> bool:
	return bool(st.get("jobs", {}).get("open", false))


## Somebody was given a job since the step began (the coach counts those as "assigned:job").
static func _jobs_given(_sim, _p, st) -> bool:
	return _counted(st.get("events", {}), "assigned:job") >= 1.0


# -------------------------------------------- the hints' triggers (normal runs) --

## {"days": n}: food or water is down to fewer days than that for the crew.
static func _low_stores(sim, p, _st) -> bool:
	var days := float(p.get("days", 2.0))
	return sim.supplies.days_left("food") < days or sim.supplies.days_left("water") < days


## {"below": n}: less ammo than that is left (and some, or the alarm for none says it).
static func _low_ammo(sim, p, _st) -> bool:
	return float(sim.stock.ammo) < float(p.get("below", 60.0))


## Somebody alive is bleeding.
static func _wounded(sim, _p, _st) -> bool:
	for who in sim.people:
		if not who.dead and who.away == null and who.bleeding > 0.0:
			return true
	return false


## Somebody alive has a fever.
static func _feverish(sim, _p, _st) -> bool:
	for who in sim.people:
		if not who.dead and sim.medical.infection_stage(who) != "":
			return true
	return false


## A wall section of the yard is down.
static func _breached(sim, _p, _st) -> bool:
	for s in sim.segments:
		if s.state == 3:
			return true
	return false


## {"kind": "brute"}: one of the dead of that kind is about.
static func _kind_alive(sim, p, _st) -> bool:
	var kind := String(p.get("kind", "walker"))
	for z in sim.zombies:
		if z.kind == kind and z.state != "dead" and z.state != "dying" and z.state != "retreat":
			return true
	return false


# ------------------------------------------------------------- combinators --

## {"of": [{"cond", "params"}, ...]}: every one holds.
static func _all(sim, p, st) -> bool:
	for spec in p.get("of", []):
		if not check(spec, sim, st):
			return false
	return true


## {"of": [...]}: at least one holds.
static func _any(sim, p, st) -> bool:
	for spec in p.get("of", []):
		if check(spec, sim, st):
			return true
	return false


## {"of": {"cond", "params"}}: that one does not hold.
static func _not(sim, p, st) -> bool:
	var spec = p.get("of", {})
	return typeof(spec) == TYPE_DICTIONARY and not check(spec, sim, st)
