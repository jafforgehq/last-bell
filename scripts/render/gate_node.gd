## The vehicle gate in the north wall (round 15, "the yard in motion"): the Main gate (wall segment 2) as two gate posts that
## stand and two leaves that slide apart, out of the way behind the neighbouring wall pieces, so that a car can drive through
## (the motor pool, assets/data/motor_pool.json). Only the picture moves: the segment's rules do not change (the dead still
## attack it, it stays shut to the dead and has its hp; assets/data/map.json `segments`).
##
## - The picture of each damage state of the segment (`165_gate_s0..s2.png`) is cut in four by tools/edit_gate.py: `_pl` the left
##   post, `_l` the left leaf, `_r` the right leaf, `_pr` the right post (the columns CUTS of the 729 px). The wreck (state 3)
##   is one piece and has no leaves. `world.set_segment_state` hands the state to `set_state` (`world.segment_painters`).
## - The leaves are drawn in a node of their own just before the pallets' piece in the big layer, so that they slide in behind
##   the pallets and the school bus; the posts are in the segment's own holder (where the whole picture was drawn) over the
##   pallets' end, and over the leaves.
## - `follow(open_target, dt)` eases `open` to 0 (shut) or 1 (open) in OPEN_TIME seconds; the vehicle view (ACTOR) calls it every
##   frame with its demand (1 while a car, or a person on a trip, is within 6 tiles of the gate and going through it).
## - ROUND 22, "a proper gate": in avatar mode (`sim.gate.active()`, scripts/sim/gate.gd) the gate has rules of its own (the avatar opens and
##   shuts it with E at the lever, the dusk keeper shuts it, a car or a party that has to pass asks it open), and `sim.gate.open` is the REAL
##   state: `follow` then ignores the demand it is given and eases the leaves to that (a little quicker than OPEN_TIME so that they never
##   lag the rules: the rules' clock is the game's, so `dt` is the view's own time scaled by `Main.gate_rate`, and the leaves keep the rules'
##   pace at any game speed). With no avatar (the classic game, the tests, Orientation Day) the demand rules exactly as before.
## - The control point's picture (`Lever`): a steel post with a panel box at `sim.gate.control_spot()` and a lamp on it that is green while the
##   gate is open, red while it is shut and amber, blinking, while the leaves are on the move (with reduced motion: steady). Only in avatar mode.
## - ZONE is the ground the gate rules over (tiles): the mouth, the passage under the catwalk bridge and the street's end of
##   it; Z_CAR is the z a car is drawn in: over the ground and its paint (z 1 and 2), under the wall pieces and the bridge (z 4).
## - Started with `--gate-debug` the node also draws the motor pool's routes, the cars' bodies along them and the zones, over
##   everything, for a screenshot of the geometry; with `--gate-open=<0 to 1>` the leaves stand that far open and `follow` does
##   nothing (a screenshot of the open gate); with `--gate-cars=<spot>:<in|out>:<0 to 1>[,...]` a still sedan stands on the
##   motor pool's route at that share of its length, in z Z_CAR (a screenshot of what is over and under what).
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const GateKit := preload("res://scripts/ui/gate_kit.gd")
const Prefs := preload("res://scripts/prefs.gd")
const TILE := GD.TILE

## The wall segment this is the picture of (the Main gate).
const SEGMENT := 2
const ZONE := Rect2(35.5, 14.0, 7.0, 7.5)
const Z_CAR := 3
## The lever's z: over the ground's bits (5), under the people (6).
const LEVER_Z := 5
## How long the leaves take to go from shut to open or back, in seconds.
const OPEN_TIME := 0.8
## In avatar mode the leaves catch up with the rules' `open` this many times quicker than OPEN_TIME (so that they never lag the rules).
const CHASE := 2.0
## How far each leaf slides (tiles): out of the opening between the posts, in behind the post and the wall piece beside it.
const TRAVEL := 2.6
## Where the gate's picture is cut (pixels of its 729 px width): the left post ends, the leaves meet, the right post starts.
const CUTS := [75, 343, 612]
const SRC_W := 729.0
## Damage states 0 to LEAF_STATES - 1 have leaves; the last is the heap of the broken gate.
const LEAF_STATES := 3

## 0 shut to 1 open (the leaves' travel is eased: see `ease_of`).
var open := 0.0
var state := 0
var world
## The node that holds the leaves, and the sprites of the two leaves with where they stand when the gate is shut (pixels).
var leaves: Node2D
var _leaf_l: Sprite2D
var _leaf_r: Sprite2D
var _base_l := Vector2.ZERO
var _base_r := Vector2.ZERO
var _holder: Node2D
var _debug := false
var _pool := {}
## A screenshot's open gate: `follow` leaves `open` as it is.
var _held := false
## The sim (the gate's rules, `sim.gate`), when `setup` was given it, and the lever's picture.
var _sim
var lever: Node2D
## Which way the leaves were last seen to move (+1 opening, -1 closing, 0 still).
var _dir := 0


## `w` is the world (its segment holders and `segment_painters`), `rules` the sim (the segment's state now, optional).
func setup(w, rules = null) -> void:
	world = w
	_sim = rules
	_make_lever()
	_holder = w.segment_holders.get(SEGMENT)
	if _holder == null:
		return
	leaves = Node2D.new()
	leaves.name = "GateLeaves"
	var layer: Node = _holder.get_parent()
	layer.add_child(leaves)
	# behind the pieces beside the gate (the pallets before it, the school bus after it) so that the leaves slide in under them
	var at := _holder.get_index()
	for id in [SEGMENT - 1, SEGMENT + 1]:
		var other: Node2D = w.segment_holders.get(id)
		if other != null and other.get_parent() == layer:
			at = mini(at, other.get_index())
	layer.move_child(leaves, at)
	w.segment_painters[SEGMENT] = Callable(self, "set_state")
	var now := 0
	if rules != null:
		for s in rules.segments:
			if int(s.id) == SEGMENT:
				now = int(s.state)
	set_state(now)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--gate-open="):
			stage_open(float(String(a).trim_prefix("--gate-open=")))
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--gate-cars="):
			_demo_cars(String(a).trim_prefix("--gate-cars="))
	_debug = OS.get_cmdline_user_args().has("--gate-debug")
	if _debug:
		_pool = _read_pool()
		z_index = 20
		queue_redraw()


func _exit_tree() -> void:
	if world != null and is_instance_valid(world) and world.segment_painters.get(SEGMENT) == Callable(self, "set_state"):
		world.segment_painters.erase(SEGMENT)


## The segment's damage picture changed: the posts and the leaves are made again from that state's picture.
func set_state(new_state: int) -> void:
	state = new_state
	if _holder == null or world == null:
		return
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	for c in leaves.get_children():
		leaves.remove_child(c)
		c.queue_free()
	_leaf_l = null
	_leaf_r = null
	var states: Array = world.segment_states.get(SEGMENT, [])
	if new_state < 0 or new_state >= states.size():
		return
	var pieces: Array = states[new_state]
	if new_state >= LEAF_STATES:
		# the broken gate: a heap, one piece, nothing to open
		for p in pieces:
			var heap := _sprite(String(p.file), float(p.x), float(p.y), float(p.w), float(p.h))
			heap.name = "Heap"
			_holder.add_child(heap)
		return
	for p in pieces:
		var base := String(p.file).trim_suffix(".png")
		var scale := float(p.w) / SRC_W        # tiles to a pixel of the picture
		var x0 := [0, CUTS[0], CUTS[1], CUTS[2]]
		var x1 := [CUTS[0], CUTS[1], CUTS[2], int(SRC_W)]
		var names := ["_pl", "_l", "_r", "_pr"]
		for i in 4:
			var s := _sprite(base + String(names[i]) + ".png", float(p.x) + float(x0[i]) * scale, float(p.y), (float(x1[i]) - float(x0[i])) * scale, float(p.h))
			s.name = String(["PostL", "LeafL", "LeafR", "PostR"][i])
			match i:
				0, 3:
					_holder.add_child(s)
				1:
					leaves.add_child(s)
					_leaf_l = s
					_base_l = s.position
				2:
					leaves.add_child(s)
					_leaf_r = s
					_base_r = s.position
	_apply()


func _sprite(file: String, x: float, y: float, w: float, h: float) -> Sprite2D:
	var t := GD.tex(file)
	var s := Sprite2D.new()
	s.texture = t
	s.centered = false
	s.position = Vector2(x, y) * TILE
	s.scale = Vector2(w * TILE / float(t.get_width()), h * TILE / float(t.get_height()))
	return s


## Moves `open` towards `open_target` (0 shut, 1 open) at the speed that takes OPEN_TIME seconds from one end to the other. In avatar mode
## (`sim.gate.active()`) the target is the rules' own `sim.gate.open` instead, whatever is asked (the demand of the vehicle view is the
## rules' business there: `sim.gate.demand`), and the leaves follow it CHASE times as fast. The lever's lamp follows the leaves.
func follow(open_target: float, dt: float) -> void:
	var rules = GateKit.active_gate(_sim)
	_sync_lever(rules)
	if _held:
		return
	var goal := clampf(open_target, 0.0, 1.0)
	var rate := 1.0
	if rules != null:
		goal = GateKit.open_of(rules)
		rate = CHASE
	var next := move_toward(open, goal, maxf(dt, 0.0) * rate / OPEN_TIME)
	if is_equal_approx(next, open):
		return
	_dir = 1 if next > open else -1
	open = next
	_apply()
	_sync_lever(rules)


## A screenshot's gate: the leaves stand `value` open (0 to 1) and `follow` leaves them there (`--gate-open=`, and `--gate=` when the rules
## are not in charge).
func stage_open(value: float) -> void:
	open = clampf(value, 0.0, 1.0)
	_held = true
	_apply()
	_sync_lever(GateKit.active_gate(_sim))


## The leaves stand `value` open at once (0 to 1) and go on following (a screenshot's `--gate=` with the rules in charge).
func snap(value: float) -> void:
	open = clampf(value, 0.0, 1.0)
	_held = false
	_dir = 0
	_apply()
	_sync_lever(GateKit.active_gate(_sim))


## Whether the leaves follow the rules' own state now (avatar mode), not the vehicles' demand.
func ruled() -> bool:
	return GateKit.is_active(_sim)


## The leaves' travel at `o` (0 to 1): slow at the ends, quick in the middle.
static func ease_of(o: float) -> float:
	var t := clampf(o, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## How far (tiles) each leaf has slid from shut.
func leaf_offset() -> float:
	return ease_of(open) * TRAVEL


## Whether the leaves are all the way open / all the way shut.
func is_open() -> bool:
	return open >= 1.0 - 0.0001


func is_shut() -> bool:
	return open <= 0.0001


func _apply() -> void:
	var d := leaf_offset() * TILE
	if _leaf_l != null:
		_leaf_l.position = _base_l + Vector2(-d, 0.0)
	if _leaf_r != null:
		_leaf_r.position = _base_r + Vector2(d, 0.0)


# ---------------------------------------------------------------------------- the lever --

## The control point's picture, made once (it is only shown in avatar mode).
func _make_lever() -> void:
	if lever != null:
		return
	lever = Lever.new()
	lever.name = "Lever"
	lever.z_index = LEVER_Z
	lever.visible = false
	add_child(lever)


## Puts the lever where the rules say (`control_spot()`), shows it in avatar mode only, and sets its lamp to what the leaves are doing: the
## state the picture shows is the picture's own (`open`: a leaf that is still moving is amber), so that the lamp never says what the leaves do not.
func _sync_lever(rules) -> void:
	if lever == null:
		return
	var spot := GateKit.spot_of(rules) if rules != null else Vector2.INF
	var on: bool = rules != null and spot != Vector2.INF and state >= 0 and state < LEAF_STATES
	if lever.visible != on:
		lever.visible = on
	if not on:
		return
	var at := spot * TILE
	if not lever.position.is_equal_approx(at):
		lever.position = at
	lever.set_state(GateKit.state_of(open, _dir), GateKit.held_of(rules))


## The state of the lever's lamp now: "shut", "open", "opening" or "closing" ("" while the lever is not shown).
func lamp_state() -> String:
	return lever.lamp_state if lever != null and lever.visible else ""


## What the lever looks like: a steel post with a box on it, a handle that is up while the gate is open and down while it is shut, and a
## lamp. The foot of the picture is the node's own position (the control spot). It is a few pixels of drawing and nothing else.
class Lever:
	extends Node2D

	const GateKit := preload("res://scripts/ui/gate_kit.gd")
	const Prefs := preload("res://scripts/prefs.gd")
	const STEEL := Color("#8f9aa3")
	const STEEL_DARK := Color("#3d474f")
	const EDGE := Color(0.04, 0.06, 0.07, 0.95)
	const PANEL := Color("#1d2529")
	const YELLOW := Color("#e7b93e")
	## The size of the picture in pixels of the world (64 to a tile): the box, the post and the lamp's radius.
	const BOX := Vector2(30.0, 38.0)
	const POST_H := 20.0
	const LAMP_R := 6.0
	var lamp_state := GateKit.SHUT
	var held := ""
	## How many times it has been drawn (for the tests).
	var draws := 0
	var _blink := 0.0

	func _ready() -> void:
		set_process(false)

	func set_state(new_state: String, new_held: String) -> void:
		if new_state == lamp_state and new_held == held:
			return
		lamp_state = new_state
		held = new_held
		set_process(_moving())
		queue_redraw()

	func _moving() -> bool:
		return lamp_state == GateKit.OPENING or lamp_state == GateKit.CLOSING

	func _process(delta: float) -> void:
		# the lamp blinks while the leaves are on the move (steady with reduced motion)
		if Prefs.on("ui", "reduce_motion"):
			return
		var before := _lit()
		_blink += delta
		if _lit() != before:
			queue_redraw()

	func _lit() -> bool:
		return not _moving() or fmod(_blink, 0.5) < 0.3

	## The lamp's colour now (dark for the off beat of a blink).
	func lamp_color() -> Color:
		return GateKit.lamp_color(lamp_state) if _lit() else GateKit.LAMP_OFF

	func _draw() -> void:
		draws += 1
		# the foot: a small shadow and a plate
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2(0.0, 2.0), 17.0, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(-10.0, -4.0, 20.0, 6.0), EDGE)
		draw_rect(Rect2(-9.0, -3.5, 18.0, 4.0), STEEL_DARK)
		# the post
		draw_rect(Rect2(-4.5, -4.0 - POST_H, 9.0, POST_H), EDGE)
		draw_rect(Rect2(-3.5, -3.5 - POST_H, 7.0, POST_H - 0.5), STEEL)
		# the box on it: a dark panel in a steel frame
		var top := -4.0 - POST_H - BOX.y + 6.0
		var box := Rect2(-BOX.x / 2.0, top, BOX.x, BOX.y)
		draw_rect(box.grow(1.5), EDGE)
		draw_rect(box, STEEL)
		draw_rect(box.grow(-3.0), PANEL)
		# the lamp, with its halo: the gate's state in a colour (the word is the HUD's)
		var lamp := Vector2(0.0, top + 10.0)
		var col := lamp_color()
		draw_circle(lamp, LAMP_R + 3.5, Color(col, 0.22))
		draw_circle(lamp, LAMP_R + 1.0, EDGE)
		draw_circle(lamp, LAMP_R, col)
		draw_circle(lamp + Vector2(-1.8, -1.8), 1.8, Color(1, 1, 1, 0.55))
		# the lever: a knob in a slot, up while the gate is open, down while it is shut, half way on the move
		var slot_top := top + 20.0
		var slot_bottom := top + BOX.y - 5.0
		draw_line(Vector2(0.0, slot_top), Vector2(0.0, slot_bottom), EDGE, 6.0)
		draw_line(Vector2(0.0, slot_top), Vector2(0.0, slot_bottom), Color("#0b1012"), 4.0)
		var mid := (slot_top + slot_bottom) / 2.0
		var reach := (slot_bottom - slot_top) / 2.0 - 2.5
		var tilt := -1.0 if lamp_state == GateKit.OPEN else (1.0 if lamp_state == GateKit.SHUT else 0.0)
		var knob := Vector2(0.0, mid + reach * tilt)
		draw_line(Vector2(0.0, mid), knob, YELLOW, 3.0, true)
		draw_circle(knob, 4.0, EDGE)
		draw_circle(knob, 3.0, YELLOW)
		# a held gate wears a small pin: a bar across the slot
		if held != "":
			draw_rect(Rect2(-8.0, slot_bottom + 1.0, 16.0, 2.0), GateKit.LAMP_MOVING)


# ---------------------------------------------------------------------- the debug picture --

## `--gate-cars=`: still sedans on the routes (a screenshot of the layers: the cars under the bridge and the wall pieces).
func _demo_cars(spec: String) -> void:
	var pool := _read_pool()
	for entry in spec.split(","):
		var f := String(entry).split(":")
		if f.size() < 3 or pool.is_empty():
			continue
		var spots: Array = pool.get("spots", [])
		var spot := int(f[0])
		if spot < 0 or spot >= spots.size():
			continue
		var route: Array = spots[spot]["%s_route" % f[1]]
		var total := 0.0
		for i in range(1, route.size()):
			total += Vector2(float(route[i].x), float(route[i].y)).distance_to(Vector2(float(route[i - 1].x), float(route[i - 1].y)))
		var want := clampf(float(f[2]), 0.0, 1.0) * total
		var run := 0.0
		for i in range(1, route.size()):
			var a := Vector2(float(route[i - 1].x), float(route[i - 1].y))
			var b := Vector2(float(route[i].x), float(route[i].y))
			var seg := a.distance_to(b)
			if want <= run + seg or i == route.size() - 1:
				var t := 0.0 if seg <= 0.0 else clampf((want - run) / seg, 0.0, 1.0)
				var h := (b - a).angle() + (PI if bool(route[i].get("rev", false)) else 0.0)
				if route[i - 1].has("h") and route[i].has("h"):
					var h0 := float(route[i - 1].h)
					h = deg_to_rad(h0 + wrapf(float(route[i].h) - h0, -180.0, 180.0) * t)
				var car := Sprite2D.new()
				car.texture = GD.tex("res://assets/objects/174_car_s0.png")
				car.centered = true
				car.scale = Vector2(2.2 * TILE / float(car.texture.get_width()), 4.4 * TILE / float(car.texture.get_height()))
				car.position = a.lerp(b, t) * TILE
				car.rotation = h + PI / 2.0
				car.z_index = Z_CAR
				world.add_child(car)
				break
			run += seg


func _read_pool() -> Dictionary:
	var path := "res://assets/data/motor_pool.json"
	if not FileAccess.file_exists(path):
		return {}
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if raw is Dictionary else {}


func _draw() -> void:
	if not _debug or _pool.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	var zones: Dictionary = _pool.get("zones", {})
	for k in zones:
		var z: Array = zones[k]
		draw_rect(Rect2(float(z[0]), float(z[1]), float(z[2]) - float(z[0]), float(z[3]) - float(z[1])), Color(1, 1, 1, 0.5), false, 0.04)
	var which := 0
	for spot in _pool.get("spots", []):
		var at: Array = spot.at
		draw_set_transform(Vector2(float(at[0]), float(at[1])) * TILE, -PI / 2.0, Vector2(TILE, TILE))
		draw_rect(Rect2(-2.2, -1.1, 4.4, 2.2), Color(0.3, 0.6, 1.0, 0.8), false, 0.05)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
		for key in ["in_route", "out_route"]:
			var pts := PackedVector2Array()
			var col := Color(1.0, 0.45, 0.85) if key == "in_route" else Color(0.4, 1.0, 0.5)
			for p in spot[key]:
				pts.append(Vector2(float(p.x), float(p.y)))
			draw_polyline(pts, col, 0.06)
			var every := 6
			for i in range(0, spot[key].size(), every):
				var p: Dictionary = spot[key][i]
				if not p.has("h"):
					continue
				var h := deg_to_rad(float(p.h))
				draw_set_transform(Vector2(float(p.x), float(p.y)) * TILE, h, Vector2(TILE, TILE))
				draw_rect(Rect2(-2.2, -1.1, 4.4, 2.2), Color(1, 0.85, 0.3, 0.55) if bool(p.get("rev", false)) else Color(1, 1, 1, 0.45), false, 0.03)
				draw_line(Vector2.ZERO, Vector2(2.2, 0.0), Color(1, 0.3, 0.3, 0.8), 0.05)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
		which += 1
