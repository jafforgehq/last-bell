## The pieces of the base's perimeter that are built, going up or fallen, drawn from the art kit (One House, art pass): the fence (wooden or reinforced: the cells of its line by the sides that
## connect), the gate (shut or open), the corner towers and the floodlights. It reads `sim.perimeter` (scripts/town/perimeter.gd: `slots()` for what stands and what is going up,
## `sections()` for how damaged a fence or gate is, `gate_open()`) four times a second and redraws only when what it shows has changed; nothing here is per frame.
##   built   the kit's `built` look; a fence or gate that has taken damage (state 2) the `damaged` look, one that is down (state 3) the damaged look faded; ordered and building slots
##           are drawn see-through (a plan);
##   sorting the pieces are drawn row by row from the north, the tall ones (tower, floodlight) after the lines, so that a pole's foot is over the fence it stands behind.
## The barred doors of a claimed house are not drawn here (a barred door stays a door that people walk through: the house view's door picture is its picture).
## `TownWorld` makes it when the run's sim has a perimeter (so no hook in the facade is needed): `bind(sim)`.
extends Node2D

const TownArt := preload("res://scripts/town/town_art.gd")
const TILE := 64.0
const EVERY := 0.25
## Where in the stack of the world it draws: with the tall things (the world's layer 4), under the people.
const Z := 4

var sim
var _t := 0.0
var _sig := 0
var _slots: Array = []
var _damage := {}
var _gate_open := false


func bind(the_sim) -> void:
	sim = the_sim
	z_index = Z
	_t = 0.0


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or sim == null:
		return
	_t = EVERY
	refresh()


## Reads the perimeter; redraws when it differs from what was drawn. Returns how many pieces are shown.
func refresh() -> int:
	var per = sim.get("perimeter") if sim != null else null
	if per == null or not per.has_method("slots"):
		return 0
	var slots: Array = per.slots()
	var damage := {}
	if per.has_method("sections"):
		for sc in per.sections():
			damage[String(sc.slot)] = int(sc.state)
	var open: bool = bool(per.gate_open()) if per.has_method("gate_open") else false
	var sig := int(open)
	var shown: Array = []
	for s in slots:
		var st := String(s.state)
		if st == "built" or st == "broken" or st == "ordered" or st == "building":
			shown.append(s)
			sig = sig * 31 + hash(String(s.id) + st + String(s.kit) + str(damage.get(String(s.id), 0)))
	if sig == _sig and shown.size() == _slots.size():
		return _slots.size()
	_sig = sig
	_slots = shown
	_damage = damage
	_gate_open = open
	queue_redraw()
	return _slots.size()


## What is shown now: the slots (a test reads it).
func shown() -> Array:
	return _slots


func _draw() -> void:
	# the cells of every line that stands or is planned, to know what each cell is connected to
	var cells := {}
	for s in _slots:
		var kind := String(s.kind)
		if kind != "fence" and kind != "gate":
			continue
		var r: Rect2i = s.rect
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cells[Vector2i(x, y)] = s
	var tall: Array = []
	# the lines, from the north: a row at a time
	var order: Array = cells.keys()
	order.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for c in order:
		var s: Dictionary = cells[c]
		if String(s.kind) == "gate":
			continue
		var mask := 0
		if cells.has(c + Vector2i(0, -1)):
			mask |= 1
		if cells.has(c + Vector2i(1, 0)):
			mask |= 2
		if cells.has(c + Vector2i(0, 1)):
			mask |= 4
		if cells.has(c + Vector2i(-1, 0)):
			mask |= 8
		var dmg := int(_damage.get(String(s.id), 0))
		var look := TownArt.fort_cell(String(s.kit) if String(s.kit) != "" else "fence", "built" if dmg < 2 else "damaged", mask)
		_piece(look, Vector2(c) * TILE, _alpha(s, dmg))
	for s in _slots:
		var kind := String(s.kind)
		var dmg := int(_damage.get(String(s.id), 0))
		var r: Rect2i = s.rect
		match kind:
			"gate":
				var horiz := r.size.x >= r.size.y
				var look := TownArt.look("fort_gate", "h" if horiz else "v", "open" if _gate_open else "closed", 0 if dmg < 2 else 1)
				if not look.is_empty():
					var sc := Vector2(float(r.size.x) / look.fp.x, float(r.size.y) / look.fp.y)
					draw_texture_rect_region(look.tex, Rect2(Vector2(r.position) * TILE + look.off * sc, look.size * sc), look.src, Color(1, 1, 1, _alpha(s, dmg)))
			"tower", "floodlight":
				tall.append(s)
	tall.sort_custom(func(a, b): return a.rect.position.y < b.rect.position.y)
	for s in tall:
		var dmg := int(_damage.get(String(s.id), 0))
		var r: Rect2i = s.rect
		var look := TownArt.look("fort_tower" if String(s.kind) == "tower" else "floodlight", "", "", 0 if dmg < 2 else 1)
		_piece(look, Vector2(r.position) * TILE, _alpha(s, dmg))


func _alpha(s: Dictionary, dmg: int) -> float:
	var st := String(s.state)
	if st == "ordered" or st == "building":
		return 0.45
	return 0.5 if (dmg >= 3 or st == "broken") else 1.0


func _piece(look: Dictionary, at: Vector2, alpha: float) -> void:
	if look.is_empty():
		return
	draw_texture_rect_region(look.tex, Rect2(at + look.off, look.size), look.src, Color(1, 1, 1, alpha))
