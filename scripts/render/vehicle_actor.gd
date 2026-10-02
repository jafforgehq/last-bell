## One vehicle of the colony's fleet as a living thing (round 15, "the yard in motion"): a small node at the vehicle's feet in
## the y-sorted node the people are in (main.gd's `entities`), made and kept by scripts/render/parking_node.gd.
##
## What is drawn is a pure function of the saved state (`pose_for`): the vehicle's record (`state`, `spot`) and the party that
## holds it (`state`, `drive_t` of `drive_len`, `doors`), over the motor pool's routes (scripts/sim/convoy.gd). So a game that
## is saved and loaded in the middle of a trip draws the same, and nothing here touches the rules.
##
##   - parked, or a party "out" (walking to the doors) or "unloading": standing on its spot, nose to the north; the doors of
##     the party's `doors` entries swing: open in the first third of the entry's time (an ease), open while the person steps in
##     or out, shut in the last third;
##   - "driving_out" / "driving_in": the pose of Convoy.pose(route, drive_t / drive_len): the place, the nose's heading, and
##     whether it is backing (the nose keeps its heading while the car goes the other way);
##   - "away" (or out with no party): not drawn.
##
## The picture is the vehicle's own (vehicles.json: `art`, `w` and `h` in tiles, `nose` the way the picture's nose points when it
## is drawn upright), turned so that its nose is along the heading. With all its doors shut it is drawn as it is. While a door
## moves, the body is `<art>_open.png` (the doors' panels replaced by the dark cabin) and each panel `<art>_door_<id>.png` (the
## same canvas, transparent but for the panel) is drawn over it, turned about its `hinge` by `open_deg` times how far it is open,
## with its soft shadow `<art>_door_<id>_shadow.png` under the body.
## A kind with no doors data, or no such pictures, stays as drawn.
##
## In the gate's zone (`GateNode.ZONE`) the car is on `GateNode.Z_CAR`, under the catwalk's bridge and over the ground, and
## on the people's layer everywhere else. A badly worn vehicle is darker, and one nearly done has a small spanner over it.
## Brake lights at the tail (brighter backing and in a bend), a little dust when it pulls away, and the sounds of the doors
## and the engine (as signals: the manager plays them by distance to the camera).
extends Node2D

const GD := preload("res://scripts/game_data.gd")

const TILE := GD.TILE
const OBJECTS := "res://assets/objects/"
const GATE_PATH := "res://scripts/render/gate_node.gd"

## The heading of a vehicle that is parked: its nose to the north (radians, 0 = east, y grows downward).
const NORTH := -PI / 2.0
## The layer of the people (main.gd's `entities`) and the plan's own numbers for the gate until the gate node says its own.
const Z_PEOPLE := 6
const FALLBACK_ZONE := Rect2(35.5, 14.0, 7.0, 7.5)
const FALLBACK_Z_CAR := 3
## The line of the gate (tiles: y) and how far from it a car wants the gate open, ahead of it and behind it.
const GATE_LINE_Y := 17.0
const DEMAND_REACH := 12.0
const CLEAR_BEHIND := 1.5
## A door is open between these shares of its time (the first and last third).
const OPEN_BY := 1.0 / 3.0
const SHUT_FROM := 2.0 / 3.0
## A vehicle in less than this share of its hp is darker (the more, the worse), and in less than SPANNER_BELOW has a spanner.
const WORN_BELOW := 0.5
const SPANNER_BELOW := 0.3
const WORN_TINT := Color(0.5, 0.46, 0.44)
## Dust: a puff this often (seconds) while the car is in the first DUST_TILES of its way out.
const DUST_EVERY := 0.12
const DUST_TILES := 5.0

## A sound the vehicle makes: its name and where (tiles).
signal made_sound(sound_name: String, at: Vector2)

## The kind's record (vehicles.json) and the vehicle's id.
var kind: Dictionary = {}
var vehicle_id := ""
## Whether it is drawn now, and the pose it was given last (see `pose_for`).
var shown := false
var pose: Dictionary = {}
## The frame that is turned and scaled (children are in the picture's pixels, from its middle), the body's sprite in it.
var body: Node2D
var body_sprite: Sprite2D
var mark: Node2D
var fx

var _original: Texture2D
var _open: Texture2D
var _nose := "N"
var _tail: Node2D
## door id -> {"pivot": Node2D at the hinge, "sprite": Sprite2D, "deg": open_deg, "amount": 0 to 1}
var _doors := {}
var _door_order: Array = []
var _seen := false
var _last_state := ""
var _last_pos := Vector2.ZERO
var _dust_timer := DUST_EVERY
var _size := Vector2.ONE
var _gate_zone := FALLBACK_ZONE
var _gate_z := FALLBACK_Z_CAR


## Makes the nodes of a vehicle of `kind_data` (its record); false when its picture is not there (nothing is drawn then).
func setup(id: String, kind_data: Dictionary) -> bool:
	vehicle_id = id
	kind = kind_data
	var art := String(kind.get("art", ""))
	var path := OBJECTS + art + ".png"
	if art == "" or not ResourceLoader.exists(path):
		return false
	_original = GD.tex(path)
	_size = Vector2(_original.get_width(), _original.get_height())
	var open_path := OBJECTS + art + "_open.png"
	var doors: Array = kind.get("doors", [])
	if not doors.is_empty() and ResourceLoader.exists(open_path):
		_open = GD.tex(open_path)
	_nose = String(kind.get("nose", ""))
	if not _nose in ["N", "S", "E", "W"]:
		# no `nose` in the data: a picture that lies down faces east, one that stands, north
		_nose = "E" if (_size.x > _size.y) == (float(kind.get("h", 4.0)) >= float(kind.get("w", 2.0))) else "N"
	z_as_relative = false
	z_index = Z_PEOPLE
	visible = false
	body = Node2D.new()
	body.name = "Body"
	var w := float(kind.get("w", 2.0))
	var h := float(kind.get("h", 4.5))
	if _nose == "E" or _nose == "W":
		body.scale = Vector2(h * TILE / _size.x, w * TILE / _size.y)
	else:
		body.scale = Vector2(w * TILE / _size.x, h * TILE / _size.y)
	add_child(body)
	body_sprite = Sprite2D.new()
	body_sprite.texture = _original
	body.add_child(body_sprite)
	for d in doors:
		_add_door(art, d)
	_tail = Tail.new()
	_tail.setup(_nose_unit(), _size, body.scale)
	body.add_child(_tail)
	mark = Mark.new()
	mark.visible = false
	add_child(mark)
	var zone := _gate_consts()
	_gate_zone = zone.get("ZONE", FALLBACK_ZONE)
	_gate_z = int(zone.get("Z_CAR", FALLBACK_Z_CAR))
	return true


func _add_door(art: String, d: Dictionary) -> void:
	var id := String(d.get("id", ""))
	if id == "" or _doors.has(id):
		return
	var hinge := Vector2(float(d.get("hinge", [0, 0])[0]), float(d.get("hinge", [0, 0])[1]))
	var pivot := Node2D.new()
	pivot.name = "Door_%s" % id
	pivot.position = hinge - _size / 2.0
	pivot.visible = false
	var s := Sprite2D.new()
	s.centered = false
	s.offset = -hinge
	var path := "%s%s_door_%s.png" % [OBJECTS, art, id]
	if ResourceLoader.exists(path):
		s.texture = GD.tex(path)
	pivot.add_child(s)
	body.add_child(pivot)
	# the door's soft shadow on the ground (the same canvas and hinge), under the body
	var shadow_pivot: Node2D = null
	var shadow_path := "%s%s_door_%s_shadow.png" % [OBJECTS, art, id]
	if ResourceLoader.exists(shadow_path):
		shadow_pivot = Node2D.new()
		shadow_pivot.name = "Shadow_%s" % id
		shadow_pivot.position = pivot.position
		shadow_pivot.visible = false
		var ss := Sprite2D.new()
		ss.centered = false
		ss.offset = -hinge
		ss.texture = GD.tex(shadow_path)
		shadow_pivot.add_child(ss)
		body.add_child(shadow_pivot)
		body.move_child(shadow_pivot, 0)
	_doors[id] = {"pivot": pivot, "sprite": s, "shadow": shadow_pivot, "deg": float(d.get("open_deg", 60.0)), "amount": 0.0}
	_door_order.append(id)


## The unit vector the picture's nose points along in the picture's own pixels (y grows down).
func _nose_unit() -> Vector2:
	match _nose:
		"S":
			return Vector2(0, 1)
		"E":
			return Vector2(1, 0)
		"W":
			return Vector2(-1, 0)
	return Vector2(0, -1)


# ----------------------------------------------------------------------- the gate --

static var _gate_cache := {}


## The constants of the gate's node (`ZONE`, `Z_CAR`), or {} while there is none.
static func _gate_consts() -> Dictionary:
	if _gate_cache.is_empty() and ResourceLoader.exists(GATE_PATH):
		var script = load(GATE_PATH)
		if script != null:
			_gate_cache = script.get_script_constant_map()
	return _gate_cache


## The gate's zone (tiles) where a car is drawn under the bridge.
static func gate_zone() -> Rect2:
	return _gate_consts().get("ZONE", FALLBACK_ZONE)


## The layer a car in the gate's zone is drawn on.
static func gate_z() -> int:
	return int(_gate_consts().get("Z_CAR", FALLBACK_Z_CAR))


# ------------------------------------------------------------------- the pure part --

## How far a door is open (0 to 1) `t` minutes into an entry of `dur` minutes: it opens in the first third (an ease), stays open,
## and shuts in the last third.
static func door_amount(t: float, dur: float) -> float:
	if dur <= 0.0:
		return 0.0
	var u := clampf(t / dur, 0.0, 1.0)
	return minf(smoothstep(0.0, OPEN_BY, u), 1.0 - smoothstep(SHUT_FROM, 1.0, u))


## The pose of a vehicle by the saved state alone: `vehicle` is its record of the fleet, `party` the party that holds it ({} for
## none), `spot` the place of the motor pool it parks on, `convoy` the route's module. {"shown", "state", "pos" (the car's
## middle, tiles), "heading" (the nose, radians), "reverse", "doors" (door id -> how far open), "driving", and for a car on the
## road "route", "progress" (0 to 1) and "length" (tiles)}.
static func pose_for(vehicle: Dictionary, party: Dictionary, spot: int, convoy) -> Dictionary:
	var out := {"shown": false, "state": "", "pos": Vector2.ZERO, "heading": NORTH, "reverse": false, "doors": {}, "driving": false,
		"route": [], "progress": 0.0, "length": 0.0}
	if convoy == null or vehicle.is_empty():
		return out
	var state := "parked"
	if party.is_empty():
		if String(vehicle.get("state", "parked")) != "parked":
			return out
	else:
		state = String(party.get("state", ""))
	match state:
		"parked", "out", "unloading":
			var route: Array = convoy.route(spot, "out")
			if route.size() < 2:
				return out
			out.shown = true
			out.state = state
			out.pos = convoy.bay(spot)
			if state != "parked":
				for entry in party.get("doors", []):
					var id := String(entry.get("door", ""))
					var amount := door_amount(float(entry.get("t", 0.0)), float(entry.get("dur", 0.0)))
					out.doors[id] = maxf(float(out.doors.get(id, 0.0)), amount)
		"driving_out", "driving_in":
			var route: Array = convoy.route(spot, "out" if state == "driving_out" else "in")
			if route.size() < 2:
				return out
			var span := float(party.get("drive_len", 0.0))
			var progress := 0.0 if span <= 0.0 else clampf(float(party.get("drive_t", 0.0)) / span, 0.0, 1.0)
			var at: Dictionary = convoy.pose(route, progress)
			out.shown = true
			out.state = state
			out.driving = true
			out.pos = at.pos
			out.heading = float(at.heading)
			out.reverse = bool(at.get("reverse", false))
			out.route = route
			out.progress = progress
			out.length = float(convoy.length(route))
	return out


## Whether this car wants the gate open: the middle of the car crosses the gate's line within DEMAND_REACH tiles (and the car's
## half length) ahead of it, or did so within the car's half length and CLEAR_BEHIND tiles behind it.
func wants_gate(convoy) -> bool:
	if not shown or not bool(pose.get("driving", false)) or convoy == null:
		return false
	var length := float(pose.length)
	if length <= 0.0:
		return false
	var half := float(kind.get("h", 4.0)) / 2.0
	var progress := float(pose.progress)
	var y_now: float = pose.pos.y - GATE_LINE_Y
	var y_ahead: float = float(convoy.pose(pose.route, clampf(progress + (DEMAND_REACH + half) / length, 0.0, 1.0)).pos.y) - GATE_LINE_Y
	var y_behind: float = float(convoy.pose(pose.route, clampf(progress - (CLEAR_BEHIND + half) / length, 0.0, 1.0)).pos.y) - GATE_LINE_Y
	return y_now * y_ahead <= 0.0 or y_behind * y_now <= 0.0


# ---------------------------------------------------------------------- applying --

## Puts the vehicle as `p` (a `pose_for`) says; `share` is its condition (0 to 1), `convoy` the route's module, `dt` the real seconds.
func apply(p: Dictionary, share: float, convoy, dt: float) -> void:
	var was_state := _last_state
	pose = p
	shown = bool(p.get("shown", false))
	visible = shown
	if not shown:
		_last_state = ""
		_seen = false
		_set_doors({})
		return
	var pos: Vector2 = p.pos
	var heading := float(p.heading)
	var dir := Vector2.from_angle(heading)
	var ext := _half_extent(dir)
	position = Vector2(pos.x, pos.y + ext.y) * TILE
	body.position = Vector2(0.0, -ext.y * TILE)
	body.rotation = heading - _nose_unit().angle()
	mark.position = Vector2(0.0, -ext.y * 2.0 * TILE - 12.0)
	# under the bridge as soon as any part of the body is in the gate's zone (its nose, then its tail), not by its middle
	z_index = _gate_z if Rect2(pos - ext, ext * 2.0).intersects(_gate_zone) else Z_PEOPLE
	_tint(share)
	_set_doors(p.doors)
	# the sounds: none for a state that is only found (a game just loaded)
	if _seen and was_state != "driving_out" and String(p.state) == "driving_out":
		made_sound.emit("car_engine_start", pos)
	_light_tail(p, convoy)
	_dust(p, dt)
	_last_state = String(p.state)
	_last_pos = pos
	_seen = true


## Half the box the car takes on the ground (tiles) at that heading.
func _half_extent(dir: Vector2) -> Vector2:
	var a := float(kind.get("h", 4.5)) / 2.0
	var b := float(kind.get("w", 2.0)) / 2.0
	return Vector2(absf(dir.x) * a + absf(dir.y) * b, absf(dir.y) * a + absf(dir.x) * b)


## The box the vehicle takes in the world (tiles) where it is now; empty while it is not drawn.
func rect() -> Rect2:
	if not shown:
		return Rect2()
	var ext := _half_extent(Vector2.from_angle(float(pose.heading)))
	return Rect2(pose.pos - ext, ext * 2.0)


func _tint(share: float) -> void:
	var worn := clampf((WORN_BELOW - share) / WORN_BELOW, 0.0, 1.0)
	var c := Color.WHITE.lerp(WORN_TINT, worn)
	if body_sprite.modulate != c:
		body_sprite.modulate = c
		for id in _door_order:
			_doors[id].sprite.modulate = c
	mark.visible = share < SPANNER_BELOW


## Sets how far each door is open (id -> 0 to 1; the doors that are not named are shut) and draws the body and the panels that go with it.
func _set_doors(amounts: Dictionary) -> void:
	var any := false
	for id in _door_order:
		var d: Dictionary = _doors[id]
		var amount := clampf(float(amounts.get(id, 0.0)), 0.0, 1.0)
		var before := float(d.amount)
		if _seen and before <= 0.0 and amount > 0.0:
			made_sound.emit("car_door_open", pose.get("pos", Vector2.ZERO))
		elif _seen and before > 0.0 and amount <= 0.0:
			made_sound.emit("car_door_close", pose.get("pos", Vector2.ZERO))
		d.amount = amount
		d.pivot.rotation = deg_to_rad(float(d.deg)) * amount
		if d.shadow != null:
			d.shadow.rotation = d.pivot.rotation
		any = any or amount > 0.0
	var use_open: bool = any and _open != null
	body_sprite.texture = _open if use_open else _original
	for id in _door_order:
		var d: Dictionary = _doors[id]
		# on the open body every panel is drawn (the shut ones at angle 0 give the picture back); the shadow only the open ones
		d.pivot.visible = use_open and d.sprite.texture != null
		if d.shadow != null:
			d.shadow.visible = d.pivot.visible and float(d.amount) > 0.0


## Brake lights: dim at the tail while it drives, bright backing and in a bend.
func _light_tail(p: Dictionary, convoy) -> void:
	if not bool(p.get("driving", false)):
		_tail.level = 0.0
		_tail.queue_redraw()
		return
	var level := 0.45
	if bool(p.reverse):
		level = 1.0
	elif convoy != null and float(p.length) > 0.0:
		var ahead: Dictionary = convoy.pose(p.route, clampf(float(p.progress) + 1.5 / float(p.length), 0.0, 1.0))
		if absf(wrapf(float(ahead.heading) - float(p.heading), -PI, PI)) > 0.05:
			level = 1.0
	if not is_equal_approx(level, _tail.level):
		_tail.level = level
		_tail.queue_redraw()


## A little dust at the tail as the car pulls away (the first DUST_TILES of the way out, while it moves).
func _dust(p: Dictionary, dt: float) -> void:
	if fx == null or String(p.state) != "driving_out" or float(p.progress) * float(p.length) > DUST_TILES:
		_dust_timer = DUST_EVERY
		return
	if p.pos.distance_to(_last_pos) < 0.0001:
		return
	_dust_timer += dt
	if _dust_timer >= DUST_EVERY:
		_dust_timer = 0.0
		var tail: Vector2 = p.pos - Vector2.from_angle(float(p.heading)) * float(kind.get("h", 4.0)) * 0.5
		fx.smoke(tail.x, tail.y, 0.3, false)


# ----------------------------------------------------------------- for the tests --

## The ids of the doors the kind has, in the data's order.
func door_ids() -> Array:
	return _door_order.duplicate()


## How far a door is turned now (radians, about its hinge); 0 for one that is not there.
func door_angle(id: String) -> float:
	return float(_doors[id].pivot.rotation) if _doors.has(id) else 0.0


## The nodes of a door ({"pivot", "sprite"}), or {}.
func door_parts(id: String) -> Dictionary:
	return _doors.get(id, {})


## Whether the body is drawn with the picture as it is (every door shut).
func showing_original() -> bool:
	return body_sprite != null and body_sprite.texture == _original


## How bright the brake lights are now (0 off).
func tail_level() -> float:
	return float(_tail.level) if _tail != null else 0.0


## Two small lights at the tail of the car: dim red while it drives, brighter when it backs or bends.
class Tail:
	extends Node2D

	var level := 0.0
	var _at := Vector2.ZERO
	var _across := Vector2.ZERO
	var _radius := 4.0

	## `nose` is the picture's nose as a unit vector, `size` the picture's pixels, `scale` the body's scale.
	func setup(nose: Vector2, size: Vector2, scale_of_body: Vector2) -> void:
		var along: float = (absf(nose.x) * size.x + absf(nose.y) * size.y) / 2.0
		var wide: float = (absf(nose.y) * size.x + absf(nose.x) * size.y) / 2.0
		_at = -nose * along * 0.94
		_across = Vector2(-nose.y, nose.x) * wide * 0.6
		_radius = 4.5 / maxf(minf(scale_of_body.x, scale_of_body.y), 0.01)

	func _draw() -> void:
		if level <= 0.0:
			return
		var lamp := Color(0.95, 0.12, 0.08, 0.5 + 0.5 * level)
		var glow := Color(1.0, 0.2, 0.12, 0.28 * level)
		for side in [-1.0, 1.0]:
			var c: Vector2 = _at + _across * side
			draw_circle(c, _radius * 2.4, glow)
			draw_circle(c, _radius, lamp)


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
