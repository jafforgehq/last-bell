## The colony's parked vehicles at the main gate (round 13, "vehicles and fuel"): each vehicle of the fleet that is parked
## (`sim.vehicles.parked()`) stands in the north street by the gate, in the picture of its kind (assets/data/vehicles.json:
## `art`, and `w` and `h` in tiles, drawn upright, nose to the north), on one of MAX_SPOTS places in a row across AREA (the
## ground that the streets' dresser keeps clear: tools/make_dressing.py `GATE_PARKING`). A vehicle that is out with a party
## is not drawn; one that comes home takes its place again (the one it had, when that is free). One that is badly worn is
## darker, and one that is nearly done has a small spanner over it.
##
## - Only in a settlement game (`sim.town.on`): the classic start, the tutorial and the title's yard have none of it. (The
##   rules say it is a settlement game only after the node is built, so `update()` asks every frame, as the dressing does.)
## - Each vehicle is a small node at its feet in the y-sorted node the people are in (main.gd's `entities`), so a person walks
##   behind one and in front of another by where their feet are. Nothing here is solid and nothing touches the rules.
## - A click on a parked vehicle opens the Town Board (main.gd asks `vehicle_at`).
extends Node2D

const GD := preload("res://scripts/game_data.gd")

const TILE := GD.TILE
const OBJECTS := "res://assets/objects/"
## The ground the vehicles park on (tiles): x 33.5 to 44.5, y 6 to 15 in the north street by the gate.
const AREA := Rect2(33.5, 6.0, 11.0, 9.0)
## How many places in the row; the vehicles' feet are on this line (tiles).
const MAX_SPOTS := 4
const FEET_Y := 14.3
## A vehicle in less than this share of its hp is darker (the more, the worse), and in less than SPANNER_BELOW has a spanner.
const WORN_BELOW := 0.5
const SPANNER_BELOW := 0.3
const WORN_TINT := Color(0.5, 0.46, 0.44)

var sim
## The y-sorted node the people are in (main.gd's `entities`), or one of the node's own when there is none.
var _tall: Node2D
var _own_tall: Node2D
var _shown := false
## vehicle id -> {"node": Node2D (at its feet), "sprite": Sprite2D, "mark": Node2D, "spot": int, "kind": String, "sig": String}
var _drawn := {}
## vehicle id -> the place it last stood on (it comes back to it when it is free)
var _spot_of := {}
## How many nodes were made, for the tests.
var makes := 0


## `rules` is the sim (`town.on` and `vehicles` are read), `stand_in` the y-sorted node the people are in.
func setup(rules, stand_in: Node2D = null) -> void:
	sim = rules
	if stand_in != null:
		_tall = stand_in
	else:
		_own_tall = Node2D.new()
		_own_tall.name = "Tall"
		_own_tall.z_index = 6
		_own_tall.y_sort_enabled = true
		add_child(_own_tall)
		_tall = _own_tall
	update()


func _exit_tree() -> void:
	_forget()


## Whether the rules are of a settlement game.
func is_on() -> bool:
	if sim == null:
		return false
	var town = sim.get("town")
	return town != null and bool(town.on) and sim.get("vehicles") != null


## Called every frame by main.gd: shows the parked vehicles of the fleet, takes away those that went out or were lost.
func update() -> void:
	var on := is_on()
	if not on:
		if _shown:
			_shown = false
			_forget()
		return
	_shown = true
	var want := _wanted()
	for id in _drawn.keys():
		if not want.has(id):
			_remove(String(id))
	for id in want:
		var v: Dictionary = want[id]
		var sig := _sig(v)
		if _drawn.has(id) and String(_drawn[id].kind) != String(v.kind):
			_remove(String(id))    # (a new run's first vehicle may have an old one's id)
		if not _drawn.has(id):
			_make(v)
		elif String(_drawn[id].sig) != sig:
			_style(_drawn[id], v)
			_drawn[id].sig = sig


## The vehicles that are drawn now, id -> the vehicle (the parked ones, as many as there are places: the places they stood on
## are theirs again, the rest go to the first that are free).
func _wanted() -> Dictionary:
	var parked: Array = sim.vehicles.parked()
	var taken := {}
	var out := {}
	for v in parked:
		var spot := int(_spot_of.get(String(v.id), -1))
		if spot >= 0 and spot < MAX_SPOTS and not taken.has(spot):
			taken[spot] = String(v.id)
			out[String(v.id)] = v
	for v in parked:
		if out.has(String(v.id)):
			continue
		for spot in MAX_SPOTS:
			if not taken.has(spot):
				taken[spot] = String(v.id)
				_spot_of[String(v.id)] = spot
				out[String(v.id)] = v
				break
	return out


func _sig(v: Dictionary) -> String:
	return "%s:%d" % [String(v.kind), int(roundf(_share(v) * 20.0))]


## How much of its condition a vehicle has left (0 to 1).
func _share(v: Dictionary) -> float:
	var k: Dictionary = sim.vehicles.kind(String(v.kind))
	return clampf(float(v.hp) / maxf(float(k.get("hp", 100.0)), 1.0), 0.0, 1.0)


## The feet of the place `spot` of the row, in tiles.
static func spot_at(spot: int) -> Vector2:
	return Vector2(AREA.position.x + (float(spot) + 0.5) * AREA.size.x / float(MAX_SPOTS), FEET_Y)


func _make(v: Dictionary) -> void:
	var id := String(v.id)
	var k: Dictionary = sim.vehicles.kind(String(v.kind))
	var path := OBJECTS + String(k.get("art", "")) + ".png"
	if k.is_empty() or not ResourceLoader.exists(path):
		return
	makes += 1
	var spot := int(_spot_of.get(id, 0))
	var at := Node2D.new()
	at.name = "Parked_%s" % id
	at.position = spot_at(spot) * TILE
	var s := Sprite2D.new()
	var tex := GD.tex(path)
	s.texture = tex
	var w := float(k.get("w", 2.0))
	var h := float(k.get("h", 4.5))
	# the picture is upright (nose up) in the data's w x h; a picture drawn lying down is turned to stand
	if (tex.get_width() > tex.get_height()) == (h >= w):
		s.rotation = -PI / 2.0
		s.scale = Vector2(h * TILE / float(tex.get_width()), w * TILE / float(tex.get_height()))
	else:
		s.scale = Vector2(w * TILE / float(tex.get_width()), h * TILE / float(tex.get_height()))
	s.position = Vector2(0.0, -h * TILE / 2.0)
	at.add_child(s)
	var mark := Mark.new()
	mark.position = Vector2(0.0, -h * TILE - 12.0)
	mark.visible = false
	at.add_child(mark)
	_tall.add_child(at)
	var entry := {"node": at, "sprite": s, "mark": mark, "spot": spot, "kind": String(v.kind), "sig": _sig(v), "w": w, "h": h}
	_drawn[id] = entry
	_style(entry, v)


## The look of a vehicle by its condition.
func _style(entry: Dictionary, v: Dictionary) -> void:
	var share := _share(v)
	var worn := clampf((WORN_BELOW - share) / WORN_BELOW, 0.0, 1.0)
	entry.sprite.modulate = Color.WHITE.lerp(WORN_TINT, worn)
	entry.mark.visible = share < SPANNER_BELOW


func _remove(id: String) -> void:
	var entry: Dictionary = _drawn.get(id, {})
	if not entry.is_empty() and is_instance_valid(entry.node):
		entry.node.queue_free()
	_drawn.erase(id)


func _forget() -> void:
	for id in _drawn.keys():
		_remove(String(id))
	_drawn.clear()


## The ids of the vehicles that are drawn now.
func drawn_ids() -> Array:
	return _drawn.keys()


## The place of the row (0 to MAX_SPOTS - 1) a drawn vehicle stands on, or -1.
func spot_of(id: String) -> int:
	return int(_drawn[id].spot) if _drawn.has(id) else -1


## The box a drawn vehicle takes in the world (tiles), or an empty one.
func rect_of(id: String) -> Rect2:
	if not _drawn.has(id):
		return Rect2()
	var e: Dictionary = _drawn[id]
	var feet := spot_at(int(e.spot))
	return Rect2(feet.x - float(e.w) / 2.0, feet.y - float(e.h), float(e.w), float(e.h))


## The parked vehicle under a point of the world (tiles): its id, or "".
func vehicle_at(w: Vector2) -> String:
	for id in _drawn:
		if rect_of(String(id)).has_point(w):
			return String(id)
	return ""


## The sprite of a drawn vehicle (for the tests), or null.
func sprite_of(id: String) -> Sprite2D:
	return _drawn[id].sprite if _drawn.has(id) else null


## Whether a drawn vehicle has the spanner over it.
func has_spanner(id: String) -> bool:
	return _drawn.has(id) and bool(_drawn[id].mark.visible)


## A small spanner in an amber plate over a vehicle that is nearly worn out.
class Mark:
	extends Node2D

	func _draw() -> void:
		var plate := Color("#f1c24a")
		var ink := Color("#2b2113")
		draw_circle(Vector2.ZERO, 11.5, ink)
		draw_circle(Vector2.ZERO, 9.8, plate)
		# the spanner: a handle at an angle, the open jaw at the top
		var dir := Vector2(1, -1).normalized()
		draw_line(-dir * 6.2, dir * 3.8, ink, 3.2, true)
		draw_arc(dir * 5.4, 3.3, 0.0, TAU, 12, ink, 2.6, true)
		draw_line(dir * 5.4, dir * 7.8, plate, 3.0, true)
