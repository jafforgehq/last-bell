## The survivors found in the houses, on the screen (One House, WP4): a view part of the town's facade (scripts/town/town_game.gd).
##
## A survivor who has not joined is not a Person of the sim; `sim.rescue.bystander(id)` hands out one to draw (weapon lowered, turned to the avatar), and only
## while their room has been opened (`wary` or `spoken`: a `hiding` survivor has no figure, the dark room hides them). Each gets a `PawnNode`, made as main.gd
## makes a recruit's, in the y-sorted layer of the people; the node goes when the survivor says yes (then the crew's own node takes over) or is lost.
##
## The part's calls (all optional, the facade asks each part): `on_ready(main)`, `on_sync_views(view)` (tiles), `on_event(e)`. Nothing here changes the rules.
extends RefCounted

const PawnNode := preload("res://scripts/render/pawn_node.gd")
const RecruitArt := preload("res://scripts/render/recruit_art.gd")

var main
## Survivor id -> its node.
var nodes := {}


func on_ready(m) -> void:
	main = m


func _rescue():
	var sim = main.get("sim") if main != null else null
	return sim.get("rescue") if sim != null else null


## Whether a survivor is drawn now: their room is open and they have not joined.
func drawn(id: String) -> bool:
	var r = _rescue()
	return r != null and r.bystander(id) != null


func on_sync_views(view: Rect2) -> void:
	var r = _rescue()
	if r == null:
		return
	var keep := {}
	for rec in r.list():
		var id := String(rec.id)
		var p = r.bystander(id)
		if p == null:
			continue
		keep[id] = true
		var n = nodes.get(id)
		if n == null:
			n = _make(p)
			if n == null:
				continue
			nodes[id] = n
		n.visible = view.size == Vector2.ZERO or view.has_point(Vector2(p.x, p.y))
		if n.visible:
			n.anim_t = float(main.get("clock"))
			var clock = main.get("step_clock")
			n.sync(true, int(main.get("sim_steps")), clock.alpha() if clock != null else 1.0)
	for id in nodes.keys():
		if not keep.has(id):
			_free(id)


func on_event(e: Dictionary) -> void:
	var t := String(e.get("type", ""))
	if t == "rescue_joined" or t == "rescue_lost":
		_free(String(e.get("id", "")))


## A node as main.gd makes a recruit's: on the baked body most like their look, in the colours of their look.
func _make(p):
	var layer = main.get("entities") if main != null else null
	var data = main.get("data") if main != null else null
	if layer == null or not data is Dictionary:
		return null
	var base: String = RecruitArt.base_for(data, p.look)
	var n := PawnNode.new()
	n.setup(p, false, data, base)
	var bodies: Dictionary = RecruitArt.bodies(data, p.look, base)
	for view in bodies:
		n.tex[view] = bodies[view]
	layer.add_child(n)
	return n


func _free(id: String) -> void:
	var n = nodes.get(id)
	nodes.erase(id)
	if n != null and is_instance_valid(n):
		n.queue_free()
