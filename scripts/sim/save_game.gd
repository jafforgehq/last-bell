## Saving and loading a run: the rules' whole state as versioned JSON.
## A save can only be applied to a freshly built Sim (same map data); main.gd
## reloads the scene and applies it.
##
## Format, version 1: plain data (numbers, text, booleans, arrays, dictionaries).
##   the clock       day, minutes, clock_min, t, phase, bell_rung, spawn_t, kills, weather, over
##   the run         difficulty, permadeath, run_seed, rng_seed, rng_state (the 64-bit
##                   ones as text: a JSON number cannot hold them)
##   stock           {"ammo": n, ...}
##   people          by id: every variable of the Person, vectors as [x, y] or [x, y, z],
##                   path as a list of [x, y], "repair" as a wall section id or null,
##                   "target" as an index into zombies or null, "away" as null,
##                   {"party": index into sim.scavenge.parties} or {"record": {...}}
##   zombies         in order: every variable of the Zombie, "slot" as
##                   [wall section id, slot index] or null
##   segments        by id: hp, max_hp, state
##   modules         each module's save() under its name
##   alerts          the alerts by id, "at" as [x, y] or null
## The variables of Person and Zombie are read by reflection, so a field added to
## those classes is saved and loaded without a change here (a new kind of value
## in an untyped field may need a line in _person_in).
##
## On disk it is JSON (to_text and from_text). Godot's own JSON reader is not
## exact to the last digit (about 1e-13 of a float is lost), and a game loaded
## with such a hair's difference can tip a timer over a step too soon and play
## on differently. So a float that the reader would not give back exactly is
## written as {"$f": "<its 64 bits as a whole number>"} and every other float as
## the plain number it reads back as: a saved game reloads bit for bit.
extends RefCounted

const Sim := preload("res://scripts/sim/sim.gd")

const VERSION := 1
const QUICK_PATH := "user://quicksave.json"
const AUTO_PATH := "user://autosave.json"

## The rule modules, in the order the rules step them.
const MODULES := ["scenario", "supplies", "medical", "scavenge"]
const PHASES := ["day", "dusk", "night", "dawn"]
## Variables that come from the map data, not from play.
const FIXED := ["def", "look", "gun", "name", "first", "id"]
## Variables with their own handling (references to other objects and lists of points).
const PERSON_OWN := ["target", "order", "repair", "resting_bed", "away", "path"]
const ZOMBIE_OWN := ["slot", "path"]


# ------------------------------------------------------------------ writing --

## The state of `sim` as plain data (numbers, strings, arrays, dictionaries).
static func to_dict(sim) -> Dictionary:
	var index := {}
	for i in sim.zombies.size():
		index[sim.zombies[i]] = i
	var people: Array = []
	for p in sim.people:
		people.append(_person_out(sim, p, index))
	var zombies: Array = []
	for z in sim.zombies:
		zombies.append(_zombie_out(z))
	var segments: Array = []
	for s in sim.segments:
		segments.append({"id": s.id, "hp": s.hp, "max_hp": s.max_hp, "state": s.state})
	var modules := {}
	for name in MODULES:
		var saved = sim.get(name).save()
		modules[name] = _plain(saved) if typeof(saved) == TYPE_DICTIONARY else {}
	var alerts := {}
	for id in sim.alerts:
		alerts[str(id)] = _plain(sim.alerts[id])
	return {
		"version": VERSION,
		"day": sim.day,
		"minutes": sim.minutes,
		"clock_min": sim.clock_min,
		"t": sim.t,
		"phase": sim.phase,
		"bell_rung": sim.bell_rung,
		"spawn_t": sim.spawn_t,
		"kills": sim.kills,
		"weather": sim.weather,
		"over": sim.over,
		"difficulty": sim.difficulty,
		"permadeath": sim.permadeath,
		"run_seed": str(sim.run_seed),
		"rng_seed": str(sim.rng.seed),
		"rng_state": str(sim.rng.state),
		"stock": _plain(sim.stock),
		"people": people,
		"zombies": zombies,
		"segments": segments,
		"modules": modules,
		"alerts": alerts,
	}


## `value` as plain data: vectors become lists of numbers, dictionaries and
## lists are copied, anything else that is not plain becomes null.
static func _plain(value):
	match typeof(value):
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_ARRAY:
			var list: Array = []
			for e in value:
				list.append(_plain(e))
			return list
		TYPE_DICTIONARY:
			var dict := {}
			for k in value:
				dict[str(k)] = _plain(value[k])
			return dict
		TYPE_OBJECT:
			return null
	return value


static func _vars(obj) -> Array:
	var names: Array = []
	for prop in obj.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(prop)
	return names


static func _person_out(sim, p, zombie_index: Dictionary) -> Dictionary:
	var out := {"id": p.id}
	for prop in _vars(p):
		var n: String = prop.name
		if n in FIXED:
			continue
		out[n] = _plain(p.get(n))
	out["target"] = zombie_index.get(p.target) if p.target != null else null
	out["repair"] = p.repair.id if p.repair != null else null
	out["away"] = _away_out(sim, p.away)
	return out


## How a person's `away` is saved: a party is the module's own dictionary, so it
## is named by its place in sim.scavenge.parties and linked again on load.
static func _away_out(sim, away):
	if away == null:
		return null
	var parties = sim.scavenge.get("parties")
	if typeof(parties) == TYPE_ARRAY:
		for i in parties.size():
			if is_same(parties[i], away):
				return {"party": i}
	return {"record": _plain(away)}


static func _zombie_out(z) -> Dictionary:
	var out := {}
	for prop in _vars(z):
		var n: String = prop.name
		if n in FIXED:
			continue
		out[n] = _plain(z.get(n))
	out["slot"] = null
	if z.slot != null:
		out["slot"] = [z.slot.seg.id, z.slot.seg.slots.find(z.slot)]
	return out


## The text of saved data (see to_dict) as JSON: every float that Godot's reader
## would not give back exactly is written as {"$f": "<its bits>"}, so that
## from_text returns the very same numbers.
static func to_text(data: Dictionary) -> String:
	return JSON.stringify(_exact(data, JSON.new()), "", true, true)


## The data in `text` as to_text wrote it, or an empty dictionary if it is not
## JSON or not a dictionary. (Numbers that were whole come back as floats.)
static func from_text(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return _unwrap(json.data)


static func _exact(value, json: JSON):
	match typeof(value):
		TYPE_FLOAT:
			if is_finite(value):
				if value == floorf(value) and absf(value) < 1.0e15 and (value != 0.0 or _bits(value) == 0):
					return value
				if json.parse(JSON.stringify(value, "", true, true)) == OK and json.data == value:
					return value
			return {"$f": str(_bits(value))}
		TYPE_ARRAY:
			var list: Array = []
			for e in value:
				list.append(_exact(e, json))
			return list
		TYPE_DICTIONARY:
			var dict := {}
			for k in value:
				dict[k] = _exact(value[k], json)
			return dict
	return value


static func _unwrap(value):
	match typeof(value):
		TYPE_DICTIONARY:
			if value.size() == 1 and typeof(value.get("$f")) == TYPE_STRING and String(value["$f"]).is_valid_int():
				return _from_bits(String(value["$f"]).to_int())
			var dict := {}
			for k in value:
				dict[k] = _unwrap(value[k])
			return dict
		TYPE_ARRAY:
			var list: Array = []
			for e in value:
				list.append(_unwrap(e))
			return list
	return value


static func _bits(x: float) -> int:
	return PackedFloat64Array([x]).to_byte_array().decode_s64(0)


static func _from_bits(bits: int) -> float:
	var buffer := PackedByteArray()
	buffer.resize(8)
	buffer.encode_s64(0, bits)
	return buffer.decode_double(0)


## Writes the state of `sim` to `path`; false if it cannot (or the state is not
## one that could be loaded back). The file is written beside it first and moved
## into place, so a crash half way never leaves a broken save.
static func write(sim, path: String) -> bool:
	var text := to_text(to_dict(sim))
	# never replace a good save with one that could not be loaded back (a bad
	# number in the game would not survive the text)
	if _parse(sim, from_text(text)) == null:
		return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	var failed := f.get_error() != OK
	f.close()
	if failed:
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, path) == OK:
		return true
	DirAccess.remove_absolute(tmp)
	var direct := FileAccess.open(path, FileAccess.WRITE)
	if direct == null:
		return false
	direct.store_string(text)
	return direct.get_error() == OK


## The saved data at `path`, or an empty dictionary if there is none or it does
## not parse.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return from_text(FileAccess.get_file_as_string(path))


## Whether the file at `path` is a save this version can load (right version and
## the right sections), without a game to check it against. Use it before
## throwing the current game away for a load.
static func is_loadable(path: String) -> bool:
	return _top_ok(read(path))


# ------------------------------------------------------------------ reading --

static func _top_ok(data: Dictionary) -> bool:
	var v = data.get("version")
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return false
	if float(v) != float(VERSION):
		return false
	for key in ["people", "zombies", "segments"]:
		if typeof(data.get(key)) != TYPE_ARRAY:
			return false
	for key in ["stock", "modules", "alerts"]:
		if typeof(data.get(key)) != TYPE_DICTIONARY:
			return false
	return true


## Checks and converts saved values; `ok` turns false at the first thing that is
## missing or of the wrong kind.
class Reader:
	extends RefCounted
	var ok := true

	func number(v) -> float:
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			var f := float(v)
			if is_finite(f):
				return f
		ok = false
		return 0.0

	func whole(v) -> int:
		var f := number(v)
		if ok and f == floorf(f) and absf(f) < 9.0e15:
			return int(f)
		ok = false
		return 0

	## A 64-bit whole number kept as text (or, from older hands, as a number).
	func int64(v) -> int:
		if typeof(v) == TYPE_STRING and v.length() <= 20 and v.is_valid_int():
			return v.to_int()
		return whole(v)

	func text(v) -> String:
		if typeof(v) == TYPE_STRING:
			return v
		ok = false
		return ""

	func flag(v) -> bool:
		if typeof(v) == TYPE_BOOL:
			return v
		ok = false
		return false

	func vec2(v) -> Vector2:
		if typeof(v) == TYPE_ARRAY and v.size() == 2:
			return Vector2(number(v[0]), number(v[1]))
		ok = false
		return Vector2.ZERO

	func vec3(v) -> Vector3:
		if typeof(v) == TYPE_ARRAY and v.size() == 3:
			return Vector3(number(v[0]), number(v[1]), number(v[2]))
		ok = false
		return Vector3.ZERO

	## A list of [x, y] points.
	func points(v) -> Array:
		var out: Array = []
		if typeof(v) != TYPE_ARRAY:
			ok = false
			return out
		for pt in v:
			out.append(vec2(pt))
		return out

	## The values of `saved` for the script variables of `obj` (except `skip`),
	## converted to the variable's kind. A variable missing from an older save
	## is left out, so it keeps its default.
	func fields(obj, saved: Dictionary, skip: Array) -> Dictionary:
		var out := {}
		for prop in obj.get_property_list():
			if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var n: String = prop.name
			if n in skip or not saved.has(n):
				continue
			var v = saved[n]
			match prop.type:
				TYPE_FLOAT:
					out[n] = number(v)
				TYPE_INT:
					out[n] = whole(v)
				TYPE_BOOL:
					out[n] = flag(v)
				TYPE_STRING:
					out[n] = text(v)
				TYPE_VECTOR2:
					out[n] = vec2(v)
				TYPE_VECTOR3:
					out[n] = vec3(v)
				_:
					out[n] = v.duplicate(true) if (typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY) else v
		return out


## Applies saved data to a freshly built `sim`. Returns false (and leaves the
## sim alone) if the data is missing, from another version or damaged.
static func apply(sim, data: Dictionary) -> bool:
	var plan = _parse(sim, data)
	if plan == null:
		return false
	_commit(sim, plan)
	return true


## Reads and checks all of `data` against `sim` without changing anything.
## Returns the plan for _commit, or null if anything is wrong.
static func _parse(sim, data: Dictionary):
	if not _top_ok(data):
		return null
	var r := Reader.new()
	var plan := {}

	# the clock and the run
	plan["day"] = r.whole(data.get("day"))
	plan["minutes"] = r.number(data.get("minutes"))
	plan["clock_min"] = r.number(data.get("clock_min"))
	plan["t"] = r.number(data.get("t"))
	plan["phase"] = r.text(data.get("phase"))
	plan["bell_rung"] = r.flag(data.get("bell_rung"))
	plan["spawn_t"] = r.number(data.get("spawn_t"))
	plan["kills"] = r.whole(data.get("kills"))
	plan["weather"] = r.text(data.get("weather"))
	plan["over"] = r.text(data.get("over"))
	plan["difficulty"] = r.whole(data.get("difficulty"))
	plan["permadeath"] = r.flag(data.get("permadeath"))
	plan["run_seed"] = r.int64(data.get("run_seed"))
	plan["rng_seed"] = r.int64(data.get("rng_seed"))
	plan["rng_state"] = r.int64(data.get("rng_state"))
	if not r.ok:
		return null
	if plan.day < 1 or plan.kills < 0 or plan.t < 0.0:
		return null
	if plan.minutes < 0.0 or plan.minutes >= 24.0 * 60.0:
		return null
	if not plan.phase in PHASES or plan.difficulty < 0 or plan.difficulty > 2:
		return null

	# stock: every stock the sim has, never below zero; extra ones are kept
	var stock := {}
	var saved_stock: Dictionary = data.stock
	for k in sim.stock:
		if not saved_stock.has(k):
			return null
	for k in saved_stock:
		var amount := r.number(saved_stock[k])
		if amount < 0.0:
			return null
		stock[str(k)] = amount
	plan["stock"] = stock

	# wall sections by id
	var by_seg := {}
	for s in sim.segments:
		by_seg[s.id] = s
	var walls: Array = []
	var seen_walls := {}
	for sd in data.segments:
		if typeof(sd) != TYPE_DICTIONARY:
			return null
		var id := r.whole(sd.get("id"))
		var s = by_seg.get(id)
		if s == null or seen_walls.has(id):
			return null
		seen_walls[id] = true
		var max_hp: float = s.max_hp
		if sd.has("max_hp"):
			max_hp = r.number(sd.max_hp)
		var hp := r.number(sd.get("hp"))
		var state := r.whole(sd.get("state"))
		if not r.ok or max_hp <= 0.0 or hp < 0.0 or hp > max_hp + 0.001 or state < 0 or state > 3:
			return null
		walls.append({"seg": s, "hp": hp, "max_hp": max_hp, "state": state})
	if seen_walls.size() != sim.segments.size():
		return null
	plan["segments"] = walls

	# walkers
	var zombies: Array = []
	var claimed := {}
	for zd in data.zombies:
		if typeof(zd) != TYPE_DICTIONARY:
			return null
		var z = _zombie_in(sim, r, zd, by_seg, claimed)
		if z == null or not r.ok:
			return null
		zombies.append(z)
	plan["zombies"] = zombies

	# people, by id
	var by_id := {}
	for p in sim.people:
		by_id[p.id] = p
	var people: Array = []
	var seen := {}
	for pd in data.people:
		if typeof(pd) != TYPE_DICTIONARY:
			return null
		var id := r.text(pd.get("id"))
		var p = by_id.get(id)
		if p == null or seen.has(id):
			return null
		seen[id] = true
		var entry = _person_in(sim, r, p, pd, by_seg, zombies.size())
		if entry == null or not r.ok:
			return null
		people.append(entry)
	if seen.size() != sim.people.size():
		return null
	plan["people"] = people

	# alerts: one that is damaged is dropped rather than refusing the save
	var alerts := {}
	for id in data.alerts:
		var a = data.alerts[id]
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ar := Reader.new()
		var alert := {
			"id": ar.text(a.get("id")),
			"level": ar.text(a.get("level")),
			"text": ar.text(a.get("text")),
			"sub": ar.text(a.get("sub")),
			"at": null,
			"t": ar.number(a.get("t")),
			"ttl": ar.number(a.get("ttl")),
			"born": ar.number(a.get("born")),
		}
		if a.get("at") != null:
			alert["at"] = ar.vec2(a.at)
		if ar.ok:
			alerts[str(id)] = alert
	plan["alerts"] = alerts

	# the modules' own data
	var modules := {}
	for name in MODULES:
		var md = data.modules.get(name, {})
		if typeof(md) != TYPE_DICTIONARY:
			return null
		modules[name] = md.duplicate(true)
	plan["modules"] = modules
	return plan if r.ok else null


static func _zombie_in(sim, r: Reader, zd: Dictionary, by_seg: Dictionary, claimed: Dictionary):
	for key in ["x", "y", "hp", "state"]:
		if not zd.has(key):
			return null
	var z = Sim.Zombie.new()
	var f := r.fields(z, zd, FIXED + ZOMBIE_OWN)
	if not r.ok:
		return null
	for k in f:
		z.set(k, f[k])
	if z.state == "" or z.look_index < 0 or z.look_index >= sim.looks.size():
		return null
	z.look = sim.looks[z.look_index]
	z.path = r.points(zd.get("path", []))
	var slot = zd.get("slot")
	z.slot = null
	if slot != null:
		if typeof(slot) != TYPE_ARRAY or slot.size() != 2:
			return null
		var seg = by_seg.get(r.whole(slot[0]))
		var i := r.whole(slot[1])
		if seg == null or not r.ok or i < 0 or i >= seg.slots.size() or claimed.has(seg.slots[i]):
			return null
		z.slot = seg.slots[i]
		claimed[z.slot] = true
	if z.state == "attack" and z.slot == null:
		return null
	return z


## Everything to set on one person, read and checked; null if damaged.
static func _person_in(sim, r: Reader, p, pd: Dictionary, by_seg: Dictionary, zombie_count: int):
	for key in ["x", "y", "hp"]:
		if not pd.has(key):
			return null
	var f := r.fields(p, pd, FIXED + PERSON_OWN)
	var weapon: String = f.get("weapon", p.weapon)
	if not sim.weapons.has(weapon):
		return null
	var e := {"p": p, "fields": f, "weapon": weapon}
	e["path"] = r.points(pd.get("path", []))
	var order = pd.get("order")
	e["order"] = null if order == null else r.vec3(order)
	var bed = pd.get("resting_bed")
	e["bed"] = null if bed == null else r.vec2(bed)
	var repair = pd.get("repair")
	e["repair"] = null
	if repair != null:
		e["repair"] = by_seg.get(r.whole(repair))
		if e.repair == null:
			return null
	var target = pd.get("target")
	e["target"] = -1
	if target != null:
		e["target"] = r.whole(target)
		if e.target < 0 or e.target >= zombie_count:
			return null
	var away = pd.get("away")
	e["away"] = null
	if away != null:
		if typeof(away) != TYPE_DICTIONARY:
			return null
		if away.has("party"):
			e["away"] = {"party": r.whole(away.party)}
		elif away.get("record") is Dictionary:
			e["away"] = {"record": away.record.duplicate(true)}
		else:
			return null
	return e


# ------------------------------------------------------------------ applying --

## Puts a checked plan into `sim`. Nothing here can fail.
static func _commit(sim, plan: Dictionary) -> void:
	sim.day = plan.day
	sim.minutes = plan.minutes
	sim.clock_min = plan.clock_min
	sim.t = plan.t
	sim.phase = plan.phase
	sim.bell_rung = plan.bell_rung
	sim.spawn_t = plan.spawn_t
	sim.kills = plan.kills
	sim.weather = plan.weather
	sim.over = plan.over
	sim.difficulty = plan.difficulty
	sim.permadeath = plan.permadeath
	sim.run_seed = plan.run_seed
	sim.stock.clear()
	for k in plan.stock:
		sim.stock[k] = plan.stock[k]
	sim.events.clear()

	# the wall: sections that are down are open ground again, and the drawing
	# is told about every section whose state changed
	for w in plan.segments:
		var s = w.seg
		var was_open: bool = s.state == 3
		var now_open: bool = w.state == 3
		if was_open != now_open:
			sim.world.set_walkable(s.tiles, now_open)
			for i in s.tiles:
				sim.path_z.set_solid(int(i), not now_open)
				sim.path_p.set_solid(int(i), not now_open)
		var changed: bool = s.state != w.state
		s.hp = w.hp
		s.max_hp = w.max_hp
		s.state = w.state
		if changed and sim.on_segment_change.is_valid():
			sim.on_segment_change.call(s)

	# walkers, and the wall slots they hold
	for s in sim.segments:
		for sl in s.slots:
			sl.who = null
	sim.zombies.clear()
	sim.zombies.append_array(plan.zombies)
	for z in sim.zombies:
		if z.slot != null:
			z.slot.who = z

	# people
	for e in plan.people:
		var p = e.p
		for k in e.fields:
			p.set(k, e.fields[k])
		p.weapon = e.weapon
		p.gun = sim.weapons[e.weapon]
		p.path = e.path
		p.order = e.order
		p.resting_bed = e.bed
		p.repair = e.repair
		p.target = sim.zombies[e.target] if e.target >= 0 else null
		p.away = null
		if e.away != null:
			p.away = e.away.get("record", e.away)

	sim.alerts.clear()
	for id in plan.alerts:
		sim.alerts[id] = plan.alerts[id]

	for name in MODULES:
		sim.get(name).load_state(plan.modules[name])

	# a party member's `away` is the party itself, which the scavenging module
	# has just rebuilt: link them unless the module already did
	var parties = sim.scavenge.get("parties")
	for e in plan.people:
		if e.away != null and e.away.has("party") and is_same(e.p.away, e.away):
			var i: int = e.away.party
			if typeof(parties) == TYPE_ARRAY and i >= 0 and i < parties.size() and typeof(parties[i]) == TYPE_DICTIONARY:
				e.p.away = parties[i]

	# last, so nothing above can have moved it
	sim.rng.seed = plan.rng_seed
	sim.rng.state = plan.rng_state
