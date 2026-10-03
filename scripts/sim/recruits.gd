## Recruits. A new game starts with three people (Ruth, Dez and Marcus); the others join over the
## radio. At the radio hour (12:00), when the compound has a free bed and someone is at the radio desk, a call can come: a
## survivor asks the way in (round 16: the first callers, the authored survivors, are heard even with the desk empty, see
## `call_guaranteed`; a stranger needs someone there). The card `survivor_call` puts it to the player: tell
## them the way in (they reach the gate at 07:00 the next morning and join the crew) or not yet. The
## callers are, first, the three authored survivors who did not start (Ana, Walt, Hector, in story
## order) and then generated ones (name, role, look, skills, two traits, a weapon, a portrait: made
## from assets/data/recruits.json with this module's own generator, so a run is repeatable).
##
## The compound's housing (build.gd: the school's six beds, the bunk houses and the tents) is the cap: no call
## comes when everyone here, and everyone on the way, already has a bed. A newcomer is sometimes bitten
## (`bitten` in their def), and then the infection rules take over.
##
## Night size follows the crew in the small start (`crew_scale`, read by waves.gd); in the classic start
## (six people, no recruits: what the tests and Orientation Day use) this module does nothing at all.
##
## Events: {"type": "arrived", "who": id}, {"type": "call_taken", "who": id}. Alerts: none of its own.
extends RefCounted

const NightData := preload("res://scripts/sim/night_data.gd")
const DATA_PATH := "res://assets/data/recruits.json"
## Where the data is read from (tests may point it at another file).
static var data_path := DATA_PATH
static var _cache := {}

## The people a small start begins with, the first day a call may come, and the days between calls: after
## an arrival (less the radio range of a mast, at least one) and after a refusal.
## The survivors in story order: a run begins with the first `crew_start` of them (three, four or five), the rest call in.
const STORY := ["ruth", "dez", "marcus", "ana", "walt", "hector"]
const FIRST_CALL_DAY := 2
const GAP_DAYS := 3
const REFUSE_DAYS := 2
## Generated callers in a run, at most.
const MAX_GENERATED := 8
## Arrivals come at this hour, to this spot inside the gate.
const ARRIVAL_HOUR := 7.0
const GATE_SPOT := Vector2(39.0, 22.2)
## The crew's mood lifts by this when someone arrives.
const ARRIVAL_MORALE := 4.0
## Night size in a small start: 0.2 + 0.8 * the living crew / 6, kept between these.
const SCALE_BASE := 0.2
const SCALE_PER_SIX := 0.8
const SCALE_MIN := 0.5
const SCALE_MAX := 1.6
## What a generated survivor is when the data file has nothing better (a test or a broken file).
const FALLBACK_FIRST := ["Mia", "Tomas", "Nia", "Owen", "Lena", "Karim", "June", "Pavel"]
const FALLBACK_LAST := ["Hale", "Ortiz", "Brandt", "Nakamura", "Costa", "Adeyemi", "Fisher", "Novak"]
const SKILLS := ["Shooting", "Melee", "Building", "Medicine", "Leading"]

var sim
## Whether this run is a small start (recruits come, nights follow the crew).
var small := false
## The callers still to come (defs shaped like a roster entry), who is on the way ({"def", "day"}: the
## day they arrive), the defs of those who have arrived (a save needs them), and the counters.
var queue: Array = []
var incoming: Array = []
var arrived: Array = []
var next_call_day := 0
var generated := 0
var _rng := RandomNumberGenerator.new()


func setup(s) -> void:
	sim = s


func start() -> void:
	small = false
	queue.clear()
	incoming.clear()
	arrived.clear()
	next_call_day = 0
	generated = 0
	_rng.seed = _seed_for(int(sim.run_seed))


func _seed_for(run_seed: int) -> int:
	return (run_seed * 2654435761 + 7919) & 0x7fffffff


## Called once a run has been set up (after every module's start): in a small start the people who do not
## start go to the queue, in story order, and the modules that read the whole roster are told again.
func begin() -> void:
	if int(sim.crew_start) >= sim.people.size():
		return
	small = true
	var starters: Array = STORY.slice(0, clampi(int(sim.crew_start), 3, STORY.size()))
	var keep: Array = []
	for p in sim.people:
		if starters.has(String(p.id)):
			keep.append(p)
		else:
			var def: Dictionary = p.def.duplicate(true)
			var told: Dictionary = _data().get("authored", {}).get(String(p.id), {})
			if told.has("line"):
				def["line"] = String(told.line)
			queue.append(def)
	sim.people = keep
	sim.morale.start()
	sim.traits.start()
	sim.bonds.start()
	sim.jobs.start()
	sim.skills.start()
	sim.supplies.start()


# ------------------------------------------------------------------- housing --

## The people here (alive, on the map or on a trip).
func crew_size() -> int:
	var n := 0
	for p in sim.people:
		if not p.dead and not p.turned:
			n += 1
	return n


## Beds not yet taken by someone here or someone on the way.
func housing_free() -> int:
	return int(sim.build.housing()) - crew_size() - incoming.size()


## Night size by crew (small start only). In avatar mode (round 19) the avatar counts as `ordinary.avatar_weight` of a defender
## (nights.json: the community's guns hold an ordinary night, the player is a boon, not a gun it needs); `crew_size()` itself, the
## housing's count, is not touched.
func crew_scale() -> float:
	if not small:
		return 1.0
	var n := float(crew_size())
	if sim.nights_on and sim.player_id != "" and _avatar_counted():
		n = n - 1.0 + NightData.num("ordinary.avatar_weight", 0.5)
	return clampf(SCALE_BASE + SCALE_PER_SIX * n / 6.0, SCALE_MIN, SCALE_MAX)


## Whether the player is among the people `crew_size()` counts (alive, not turned): one who died is not taken off it again.
func _avatar_counted() -> bool:
	for p in sim.people:
		if String(p.id) == sim.player_id:
			return not p.dead and not p.turned
	return false


func gap_days() -> int:
	return maxi(1, GAP_DAYS - int(sim.build.radio_range()))


# --------------------------------------------------------------------- calls --

## Whether a call comes at this radio hour (the storyteller asks): see the header.
func call_due() -> bool:
	if not small or incoming.size() > 0 or sim.day < FIRST_CALL_DAY or sim.day < next_call_day:
		return false
	if sim.day >= sim.scenario.total_days():
		return false    # (the rescue comes at dawn of day 31: nobody could arrive in time)
	if queue.is_empty() and generated >= MAX_GENERATED:
		return false
	return housing_free() >= 1


## Whether the next caller is heard even with nobody at the Radio desk (round 16: the radio trap). The authored survivors
## who did not start (Ana, Walt, Hector, whichever are still waiting) call in whatever the desk; a stranger, and the radio's
## ordinary news, need someone sitting there. Said of the front of the queue only: the authored ones are always in front.
func call_guaranteed() -> bool:
	if not small or queue.is_empty():
		return false
	return STORY.has(String(queue[0].get("id", "")))


## The words that open the card when the call came in with nobody at the desk ("" when someone took it).
const EMPTY_DESK_INTRO := "The desk was empty, but the set had been left on, and a voice came through the static. "


## The caller on the table: the first of the queue (made now if the queue is empty), or {}.
func current_caller() -> Dictionary:
	if not small:
		return {}
	if queue.is_empty():
		if generated >= MAX_GENERATED:
			return {}
		queue.append(make_def(generated))
		generated += 1
	return queue[0]


## "Tell them the way in": the caller will reach the gate at 07:00 tomorrow. False if there is no caller or no bed.
func accept() -> bool:
	var def := current_caller()
	if def.is_empty() or housing_free() < 1:
		return false
	queue.pop_front()
	incoming.append({"def": def, "day": sim.day + 1})
	next_call_day = sim.day + gap_days()
	sim.events.append({"type": "call_taken", "who": String(def.id)})
	return true


## "Not yet": they will call again in a couple of days.
func refuse() -> void:
	next_call_day = sim.day + REFUSE_DAYS


## A survivor found at a place comes home with the party: the next caller joins the crew now, if there is a
## bed (else they wait where they are, for a later trip). True if they came.
func rescue_home(place_id: String) -> bool:
	if not small:
		return false
	if sim.town.state.has(place_id) and bool(sim.town.state[place_id].get("rescued", false)):
		return false
	var def := current_caller()
	if def.is_empty() or housing_free() < 1:
		sim.alert("no-bed-rescue", "warn", "A survivor is waiting at %s" % String(sim.town.place(place_id).get("name", "the place")), "There is no bed for them yet", null, 20.0)
		return false
	queue.pop_front()
	if sim.town.state.has(place_id):
		sim.town.state[place_id].rescued = true
	_arrive(def)
	return true


# ------------------------------------------------------------------- arrivals --

func update(_dt: float) -> void:
	if incoming.is_empty() or sim.phase != "day" or sim.hour < ARRIVAL_HOUR:
		return
	for entry in incoming.duplicate():
		if sim.day >= int(entry.day):
			incoming.erase(entry)
			_arrive(entry.def)


func _arrive(def: Dictionary) -> void:
	var p = sim.add_person(def)
	# whoever they were, they come in at the gate
	var spot := GATE_SPOT + Vector2(float(arrived.size() % 3) * 0.9 - 0.9, 0.0)
	p.x = spot.x
	p.y = spot.y
	p.goal_key = ""
	arrived.append(def)
	sim.events.append({"type": "arrived", "who": p.id})
	sim.events.append({"type": "banner", "text": "%s has reached the gate" % p.first, "sub": String(def.get("role", "A survivor")) + ", through the gate"})
	sim.alert("arrived-%s" % p.id, "info", "%s has joined the crew" % p.name, String(def.get("role", "")), Vector2(p.x, p.y), 14.0)
	sim.morale.shock(null, ARRIVAL_MORALE, "A new face")
	for b in sim.bonds.of(p):    # the ones who know them are lifted more
		sim.morale.shock(b.who, ARRIVAL_MORALE, "%s is here" % p.first)
	if bool(def.get("bitten", false)):
		sim.medical.add_wound(p, "bite")


# --------------------------------------------------------------- generating --

static func _data() -> Dictionary:
	if not _cache.has(data_path):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		_cache[data_path] = raw if raw is Dictionary else {}
	return _cache[data_path]


func _pick(list: Array):
	return list[_rng.randi() % list.size()]


## A new survivor (a def shaped like a roster entry of map.json), drawn from the data with this module's
## generator: the same run makes the same people in the same order.
func make_def(index: int) -> Dictionary:
	var data := _data()
	var firsts: Array = data.get("first", FALLBACK_FIRST)
	var lasts: Array = data.get("last", FALLBACK_LAST)
	var taken := _names_taken()
	var first := String(_pick(firsts))
	for _try in 24:
		if not taken.has(first):
			break
		first = String(_pick(firsts))
	var last := String(_pick(lasts))
	var roles: Array = data.get("roles", [])
	var role := {"role": "Survivor", "weapon": "pistol", "skills": {}}
	if not roles.is_empty():
		role = _pick_role(roles)
	var skills := {}
	for k in SKILLS:
		var range_ = role.skills.get(k, [1, 4])
		var lo := int(range_[0])
		var hi := maxi(lo, int(range_[1]))
		skills[k] = lo + _rng.randi() % (hi - lo + 1)
	var def := {
		"id": "r%d_%s" % [index + 1, first.to_lower()],
		"name": "%s %s" % [first, last],
		"role": String(role.role),
		"age": 18 + _rng.randi() % 50,
		"station": "",
		"traits": _pick_traits(role),
		"weapon": String(role.weapon),
		"tint": "#3a3a46",
		"skills": skills,
		"look": {},
		"job": {"x": GATE_SPOT.x, "y": GATE_SPOT.y, "what": "Just arrived"},
		"post": {"x": GATE_SPOT.x, "y": 18.8, "what": "Holding the wall"},
		"line": String(role.get("line", "")),
		"line_in": String(role.get("line_in", "")),
		"bitten": _rng.randf() < float(data.get("bitten_chance", 0.08)),
	}
	var portraits: Array = data.get("portraits", [])
	var plooks: Array = data.get("portrait_looks", [])
	if not portraits.is_empty():
		var pi := _pick_portrait(portraits)
		def["portrait"] = String(portraits[pi])
		if pi < plooks.size() and plooks[pi] is Dictionary and plooks[pi].get("look") is Dictionary:
			# the pawn looks like the face on the card
			def["look"] = plooks[pi].look.duplicate(true)
			def["tint"] = String(plooks[pi].get("tint", def.tint))
	if def.look.is_empty():
		def["look"] = _make_look(data)
	return def


## The first names of everyone here, waiting, on the way or arrived.
func _names_taken() -> Dictionary:
	var out := {}
	for p in sim.people:
		out[String(p.first)] = true
	for list in [queue, arrived]:
		for def in list:
			out[String(def.name).split(" ")[0]] = true
	for e in incoming:
		out[String(e.def.name).split(" ")[0]] = true
	return out


## A portrait nobody here, waiting or on the way has (any, once they are all used).
func _pick_portrait(portraits: Array) -> int:
	var used := {}
	for list in [queue, arrived]:
		for def in list:
			used[String(def.get("portrait", ""))] = true
	for e in incoming:
		used[String(e.def.get("portrait", ""))] = true
	var free: Array = []
	for i in portraits.size():
		if not used.has(String(portraits[i])):
			free.append(i)
	if free.is_empty():
		return _rng.randi() % portraits.size()
	return int(free[_rng.randi() % free.size()])


func _pick_role(roles: Array) -> Dictionary:
	var total := 0.0
	for r in roles:
		total += float(r.get("weight", 1.0))
	var roll := _rng.randf() * total
	for r in roles:
		roll -= float(r.get("weight", 1.0))
		if roll <= 0.0:
			return r
	return roles[roles.size() - 1]


func _pick_traits(role: Dictionary) -> Array:
	var ids: Array = sim.traits.order.duplicate()
	var out: Array = []
	var bias: Array = role.get("traits_bias", [])
	if not bias.is_empty() and _rng.randf() < 0.6:
		out.append(String(_pick(bias)))
	while out.size() < 2 and not ids.is_empty():
		var t := String(_pick(ids))
		if not out.has(t):
			out.append(t)
	return out


## A look drawn from the data's palettes and styles; without them, a plain one.
func _make_look(data: Dictionary) -> Dictionary:
	var looks: Dictionary = data.get("looks", {})
	var look := {"seed": 1000 + _rng.randi() % 100000, "skin": "#8a5a3c", "hair": "short", "hairColor": "#3a2a20", "browColor": "#2a2018",
		"top": "#c8c0b0", "topStyle": "tee", "outer": "#4a5a6a", "outerStyle": "jacket", "pants": "#383843", "shoes": "#2b2521"}
	if looks.is_empty():
		return look
	look["skin"] = String(_pick(looks.get("skin", [look.skin])))
	var hair: Dictionary = _pick(looks.get("hair", [{"style": "short", "colors": [look.hairColor]}]))
	look["hair"] = String(hair.style)
	look["hairColor"] = String(_pick(hair.colors))
	look["browColor"] = look.hairColor
	var top: Dictionary = _pick(looks.get("tops", [{"style": "tee", "colors": [look.top]}]))
	look["topStyle"] = String(top.style)
	look["top"] = String(_pick(top.colors))
	var outer: Dictionary = _pick(looks.get("outers", [{"style": "jacket", "colors": [look.outer]}]))
	look["outerStyle"] = String(outer.style)
	look["outer"] = String(_pick(outer.colors))
	look["pants"] = String(_pick(looks.get("pants", [look.pants])))
	look["shoes"] = String(_pick(looks.get("shoes", [look.shoes])))
	var extras: Dictionary = looks.get("extras", {})
	for k in extras:
		if _rng.randf() < float(extras[k]):
			look[k] = true
	return look


# ----------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {
		"small": small, "queue": queue.duplicate(true), "incoming": incoming.duplicate(true), "arrived": arrived.duplicate(true),
		"next_call_day": next_call_day, "generated": generated, "rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
	}


func load_state(d: Dictionary) -> void:
	start()
	small = bool(d.get("small", false))
	for key in ["queue", "arrived"]:
		var list = d.get(key, [])
		if list is Array:
			for def in list:
				if def is Dictionary:
					(queue if key == "queue" else arrived).append(def.duplicate(true))
	var inc = d.get("incoming", [])
	if inc is Array:
		for e in inc:
			if e is Dictionary and e.get("def") is Dictionary:
				incoming.append({"def": e.def.duplicate(true), "day": int(e.get("day", sim.day + 1))})
	next_call_day = int(d.get("next_call_day", 0))
	generated = int(d.get("generated", 0))
	if d.has("rng_seed"):
		_rng.seed = int(String(d.rng_seed))
		_rng.state = int(String(d.get("rng_state", str(_rng.state))))


## Whether a saved def has what a person is made of (a damaged save is refused, not built).
func _def_ok(def: Dictionary) -> bool:
	for key in ["id", "name", "weapon"]:
		if typeof(def.get(key)) != TYPE_STRING or String(def[key]) == "":
			return false
	if not sim.weapons.has(String(def.weapon)):
		return false
	var job = def.get("job")
	if not job is Dictionary or typeof(job.get("what")) != TYPE_STRING:
		return false
	for k in ["x", "y"]:
		if typeof(job.get(k)) != TYPE_FLOAT and typeof(job.get(k)) != TYPE_INT:
			return false
	if not def.get("look") is Dictionary or not def.get("skills") is Dictionary:
		return false
	for k in SKILLS:
		if typeof(def.skills.get(k)) != TYPE_FLOAT and typeof(def.skills.get(k)) != TYPE_INT:
			return false
	return true


## Before a save is read: `sim.people` is made to be the people the save lists (the roster people it
## does not have are taken out, the recruits who had arrived are made from their saved defs), in the
## saved order. Returns the people as they were, so a save that then turns out to be unusable can be undone.
func prepare_load(data: Dictionary) -> Array:
	var before: Array = sim.people.duplicate()
	var saved = data.get("people", [])
	if not saved is Array:
		return before
	var defs := {}
	for p in before:
		defs[String(p.id)] = p
	var arrived_defs := {}
	var modules = data.get("modules", {})
	var mod = modules.get("recruits", {}) if modules is Dictionary else {}
	# only a small start's save has a crew that differs from the roster's: any other is read as it is
	if not (mod is Dictionary and bool(mod.get("small", false))):
		return before
	if mod is Dictionary and mod.get("arrived") is Array:
		for def in mod.arrived:
			if def is Dictionary:
				arrived_defs[String(def.get("id", ""))] = def
	var people: Array = []
	for pd in saved:
		if not pd is Dictionary:
			continue
		var id := String(pd.get("id", ""))
		if defs.has(id):
			people.append(defs[id])
		elif arrived_defs.has(id) and _def_ok(arrived_defs[id]):
			people.append(sim.make_person(arrived_defs[id].duplicate(true)))
	if people.size() == saved.size():
		sim.people = people
	return before
