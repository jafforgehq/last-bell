## CREW POSTS (steam audit M16): named places on the ground of the compound where a person can be posted (assets/data/prison_posts.json). A posted person is an armed guard like a tower guard
## (`def.stand` is the post id, so `armed_count`, `_covered` and the guards' shooting loop count them), but they shoot only the dead in the post's field of fire, take a bite less often in cover, aim
## better or worse by their traits, and a coward on an exposed post can break in a fight (stops shooting until dawn). The source of truth is the crew: `def.stand` is a post id.
extends RefCounted

const PATH := "res://assets/data/prison_posts.json"
static var cfg := {}

var game


static func load_cfg() -> void:
	if not cfg.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	cfg = parsed if parsed is Dictionary else {"posts": [], "break": {}}


static func get_post(id: String) -> Dictionary:
	load_cfg()
	for p in cfg.posts:
		if String(p.id) == id:
			return p
	return {}


static func spot(id: String) -> Vector2:
	var p := get_post(id)
	return Vector2(float(p.pos[0]), float(p.pos[1])) if not p.is_empty() else Vector2(23.0, 47.0)


func _init(g) -> void:
	game = g
	load_cfg()


## The member standing on this post, or {}.
func holder(id: String) -> Dictionary:
	for m in game.crew.members:
		if String(m.def.get("stand", "")) == id:
			return m
	return {}


## The post a member stands on, or {} for a tower or none.
func of(m: Dictionary) -> Dictionary:
	return get_post(String(m.def.get("stand", "")))


## True when the dead one is where this guard may shoot (towers shoot all round).
func in_field(m: Dictionary, z) -> bool:
	var p := of(m)
	if p.is_empty():
		return true
	var d := Vector2(z.x, z.y) - spot(String(p.id))
	if d.length() > float(p.range):
		return false
	return absf(angle_difference(deg_to_rad(float(p.face)), d.angle())) <= deg_to_rad(float(p.arc))


## Aim multiplier of the post for this person's traits (1.0 on a tower).
func aim_mult(m: Dictionary) -> float:
	var p := of(m)
	if p.is_empty():
		return 1.0
	var r := 1.0
	for t in p.fit:
		if game.run.sim.traits.has_trait(m.p, String(t)):
			r *= float(p.fit[t])
	return r


## How wide a bite reaches on this person: shrunk by the cover of the post.
func bite_r(m: Dictionary, r: float) -> float:
	var p := of(m)
	return r if p.is_empty() else r * (1.0 - float(p.cover))


## One second step of the nerve of the people on exposed posts during an attack: a coward with two or more dead close by may break.
func nerve(dt: float) -> void:
	var b: Dictionary = cfg.get("break", {})
	if b.is_empty() or not game.siege.attacking:
		return
	for m in game.crew.members:
		if m.has("broke") or m.has("down"):
			continue
		var p := of(m)
		if p.is_empty() or not bool(p.exposed) or not game.run.sim.traits.has_trait(m.p, "coward"):
			continue
		var n := 0
		for z in game.run.sim.zombies:
			if game.siege._alive(z) and Vector2(z.x, z.y).distance_to(spot(String(p.id))) < float(b.dead_within):
				n += 1
		if n >= int(b.dead_min) and randf() < float(b.chance_per_s) * dt:
			m["broke"] = true
			m.say = "I can't!"
			game._say("%s broke and ran from the %s!" % [String(m.def.name), String(p.name).to_lower()], 5.0)


func dawn() -> void:
	for m in game.crew.members:
		m.erase("broke")


## What the post board shows about a post for a person (or the post alone): fit and unfit traits in words.
func fit_text(p: Dictionary) -> String:
	var good: Array = []
	var bad: Array = []
	for t in p.fit:
		var nm := String(t).replace("_", " ")
		if float(p.fit[t]) > 1.0:
			good.append(nm)
		elif float(p.fit[t]) < 1.0:
			bad.append(nm)
	var s := "Suits: " + (", ".join(good) if not good.is_empty() else "anyone")
	if not bad.is_empty():
		s += ".  Poor fit: " + ", ".join(bad)
	return s


var assign := {}    # person id -> post id; kept by the crew's `put_on_post` and role changes so that a rebuilt crew (a raid return, a load) goes back to its posts


func to_dict() -> Dictionary:
	return assign.duplicate()


func from_dict(d: Dictionary) -> void:
	assign = d.duplicate()


## After the crew is rebuilt: everybody who had a post goes to it.
func reapply() -> void:
	for id in assign.keys():
		var m: Dictionary = game.crew.member_of(String(id))
		if m.is_empty():
			assign.erase(id)
		elif String(m.def.get("stand", "")) != String(assign[id]) and holder(String(assign[id])).is_empty():
			game.crew.put_on_post(m, String(assign[id]), true)
