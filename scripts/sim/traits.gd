## Traits: two small, visible quirks for each person (Steady, Nervous, Tinkerer...) that
## nudge how they shoot, work and feel. The data is assets/data/traits.json (each trait:
## {"id", "name", "blurb", "effects": {key: number}}, and for a quirk that only shows in a
## certain situation "crowded": {"dead", "tiles", "effects"}: the effects apply while that
## many of the dead are within that many tiles); who has which is in map.json
## (`people[].traits`).
##
## The rules ask for a number through `mult(p, key)` (the product of every trait's
## multiplier for the key, 1.0 when none) or `add(p, key)` (the sum, 0.0 when none), and
## each key has one place it is used:
##   aim            shooting accuracy (sim.aim_factor)         reload       reload time (sim._fire)
##   repair         mending a wall (sim._update_person)        craft        scrap an hour at the bench (workshop.gd)
##   bandage        bandaging speed (medical.gd)               wound        chance a claw or bite wounds them (medical.gd)
##   dead_morale    what the dead at the wall do to morale     morale_recover  how fast morale comes back up
##   grief          how hard a friend's death hits             xp           how fast skills grow (skills.gd)
##   cure   (added) the chance a cure takes (medical.gd)       bond (added) a friend's aim bonus (bonds.gd)
## The prison's own traits (coward, hothead, scrounger, thief, veteran, pacifist: "only": "prison" in the file) use keys the prison's code asks for (prison_events.gd); the colony ignores them.
## Everything is saved, so a crew drawn some other way keeps its traits.
extends RefCounted

const DATA_PATH := "res://assets/data/traits.json"

var sim
## Every trait by id, and the ids in the order of the file.
var defs := {}
var order: Array = []
## Person id -> the ids of their traits.
var assigned := {}


func setup(s) -> void:
	sim = s
	_load()
	_from_roster()


func start() -> void:
	_from_roster()


func _load() -> void:
	defs = {}
	order = []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var list = parsed.get("traits", []) if parsed is Dictionary else []
	if not list is Array or list.is_empty():
		push_error("Could not read the traits from %s" % DATA_PATH)
		return
	for raw in list:
		var id := String(raw.get("id", ""))
		if id == "" or defs.has(id):
			continue
		var t := {
			"id": id,
			"name": String(raw.get("name", id)),
			"blurb": String(raw.get("blurb", "")),
			"effects": _numbers(raw.get("effects", {})),
		}
		var crowd = raw.get("crowded")
		if crowd is Dictionary:
			t["crowded"] = {"dead": int(crowd.get("dead", 1)), "tiles": float(crowd.get("tiles", 10.0)), "effects": _numbers(crowd.get("effects", {}))}
		defs[id] = t
		if String(raw.get("only", "")) == "":    # ("only": "prison" traits are given by hand there and never dealt to a colony recruit: `order` is what recruits draw from)
			order.append(id)


static func _numbers(raw) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for k in raw:
			if typeof(raw[k]) == TYPE_INT or typeof(raw[k]) == TYPE_FLOAT:
				out[String(k)] = float(raw[k])
	return out


## Everyone gets the traits the roster gives them.
## Someone joined the crew: their traits (from their def) are given.
func person_added(p) -> void:
	var ids = p.def.get("traits", [])
	give(p, ids if ids is Array else [])


func _from_roster() -> void:
	assigned = {}
	for p in sim.people:
		var ids = p.def.get("traits", [])
		give(p, ids if ids is Array else [])


## Every trait there is: [{"id", "name", "blurb", "effects"}].
func all() -> Array:
	var out: Array = []
	for id in order:
		out.append(defs[id].duplicate(true))
	return out


## This person's traits: [{"id", "name", "blurb"}], in the order they were given.
func of(p) -> Array:
	var out: Array = []
	if p == null:
		return out
	for id in assigned.get(p.id, []):
		var t: Dictionary = defs[id]
		out.append({"id": t.id, "name": t.name, "blurb": t.blurb})
	return out


## Sets this person's traits to these (ids that are not traits are left out, and a trait is
## had once). The roster's own list is not touched.
func give(p, ids: Array) -> void:
	var list: Array = []
	for id in ids:
		if defs.has(String(id)) and not list.has(String(id)):
			list.append(String(id))
	assigned[p.id] = list


func has_trait(p, id: String) -> bool:
	return p != null and assigned.get(p.id, []).has(id)


## The names of this person's traits that carry `key` (for the reasons morale lists).
func names_for(p, key: String) -> Array:
	var out: Array = []
	if p == null:
		return out
	for id in assigned.get(p.id, []):
		var t: Dictionary = defs[id]
		if t.effects.has(key) or (t.has("crowded") and t.crowded.effects.has(key)):
			out.append(t.name)
	return out


## The product of the traits' multipliers for `key` (1.0 when none apply). Keys: aim,
## reload, repair, craft, bandage, wound, dead_morale, morale_recover, grief, xp.
func mult(p, key: String) -> float:
	var m := 1.0
	if p == null:
		return m
	for id in assigned.get(p.id, []):
		var t: Dictionary = defs[id]
		if t.effects.has(key):
			m *= float(t.effects[key])
		if t.has("crowded") and t.crowded.effects.has(key) and _crowded(p, t.crowded):
			m *= float(t.crowded.effects[key])
	if sim.specialists.active():    # (round 20: a title's bonus on its own work; exactly nothing changes without an avatar)
		m *= sim.specialists.mult(p, key)
	return m * sim.policies.work_mult(p, key)    # (round 25: overtime makes more of the craft, the mending and the garden; 1.0 inactive)


## The sum of the traits' additive effects for `key` (0.0 when none apply). Keys: cure, bond.
func add(p, key: String) -> float:
	var sum := 0.0
	if p == null:
		return sum
	for id in assigned.get(p.id, []):
		var t: Dictionary = defs[id]
		if t.effects.has(key):
			sum += float(t.effects[key])
	if sim.specialists.active():
		sum += sim.specialists.add(p, key)
	return sum


## Whether enough of the dead (standing, not going down) are close to `p`.
func _crowded(p, rule: Dictionary) -> bool:
	var need: int = rule.dead
	var reach2: float = float(rule.tiles) * float(rule.tiles)
	var n := 0
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var dx: float = z.x - p.x
		var dy: float = z.y - p.y
		if dx * dx + dy * dy <= reach2:
			n += 1
			if n >= need:
				return true
	return false


# ---------------------------------------------------------------------- save --

func save() -> Dictionary:
	var rows := {}
	for id in assigned:
		rows[id] = assigned[id].duplicate()
	return {"assigned": rows}


## Restores who has what. A person the data does not mention keeps the roster's traits, and
## trait ids that do not exist are dropped.
func load_state(d: Dictionary) -> void:
	_from_roster()
	var saved = d.get("assigned", {})
	if not saved is Dictionary:
		return
	for p in sim.people:
		var ids = saved.get(p.id)
		if ids is Array:
			give(p, ids)
