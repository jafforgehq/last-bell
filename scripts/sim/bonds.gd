## Bonds: who is close to whom (friend, family, mentor), from map.json (`bonds`: a list of
## {"a": id, "b": id, "kind"}; for a mentor, `a` is the mentor of `b`). A person with a
## bonded person within AIM_TILES tiles aims AIM_BONUS better (the Loyal trait adds to it),
## being near one steadies them (morale.gd), and losing one hurts (morale.gd). In an avatar game of the
## settlement start the friends and the partner people make in play (relations.gd, round 20) are bonds too:
## `of` lists them after the roster's and `bonded` counts them, so all of the above follows with no more edits;
## without an avatar they are not there and this is the roster alone.
extends RefCounted

const KINDS := ["friend", "family", "mentor"]
## A bonded person this close (tiles) makes a person aim this much better.
const AIM_TILES := 6.0
const AIM_BONUS := 0.08

var sim
## [{"a": id, "b": id, "kind": String}]
var list: Array = []


func setup(s) -> void:
	sim = s
	_from_roster()


func start() -> void:
	_from_roster()


## Someone joined the crew: the roster's bonds that now have both their people count.
func person_added(_p) -> void:
	_from_roster()


func _from_roster() -> void:
	list = _clean(sim.d.get("bonds", []))


## The entries that make sense: both people exist and are not the same, the kind is one we
## know, and nobody is bonded to the same person twice.
func _clean(raw) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	var seen := {}
	for e in raw:
		if not e is Dictionary:
			continue
		var a := String(e.get("a", ""))
		var b := String(e.get("b", ""))
		var kind := String(e.get("kind", ""))
		if a == b or _person(a) == null or _person(b) == null or not KINDS.has(kind):
			continue
		var key := "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
		if seen.has(key):
			continue
		seen[key] = true
		out.append({"a": a, "b": b, "kind": kind})
	return out


## This person's bonds: [{"who": Person, "kind": String, "role": String}]. `role` is what
## the other is to them: "friend", "family", "mentor" (they are the student) or "student"
## (they are the mentor).
func of(p) -> Array:
	var out: Array = []
	if p == null:
		return out
	for e in list:
		var other = null
		var role: String = e.kind
		if e.a == p.id:
			other = _person(e.b)
			if e.kind == "mentor":
				role = "student"
		elif e.b == p.id:
			other = _person(e.a)
		if other != null:
			out.append({"who": other, "kind": e.kind, "role": role})
	# (round 20: the friends and the partner made in play, in an avatar game; nothing without one)
	out.append_array(sim.relations.circle(p))
	return out


## Whether these two are bonded.
func bonded(p, q) -> bool:
	if p == null or q == null:
		return false
	for e in list:
		if (e.a == p.id and e.b == q.id) or (e.a == q.id and e.b == p.id):
			return true
	return sim.relations.is_close(p, q)    # (round 20: friends made in play; false without an avatar)


## Whether a bonded person (alive, up and on the map) is within `tiles` of this one.
func near(p, tiles: float) -> bool:
	for b in of(p):
		var q = b.who
		if q.dead or q.downed or q.away != null:
			continue
		if Vector2(q.x - p.x, q.y - p.y).length() <= tiles:
			return true
	return false


## How much better this person aims right now for having a friend close by: 0.0, or the
## bond bonus plus what their traits add (the Loyal trait).
func aim_bonus(p) -> float:
	if p.dead or not near(p, AIM_TILES):
		return 0.0
	return AIM_BONUS + sim.traits.add(p, "bond")


# ---------------------------------------------------------------------- save --

func save() -> Dictionary:
	var rows: Array = []
	for e in list:
		rows.append(e.duplicate())
	return {"list": rows}


## Restores the bonds. A save from before bonds has none: the roster's stand.
func load_state(d: Dictionary) -> void:
	_from_roster()
	var saved = d.get("list")
	if saved is Array:
		list = _clean(saved)


func _person(id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null
