## The veil over one room of the house the avatar is in (One House, WP2), until the room is revealed: a dark room you cannot see well (the look is the shader's, scripts/render/
## room_veil.gdshader: deep blue black, soft edges, dust, the light of the open doors). One quad and one material for the room, nothing allocated in a frame.
##
## `setup(room, house, rect, revealed)` (rect: the room's floor, a Rect2i in tiles), `bind_doors(doors, lit_check)` (the DoorNode objects that open into this room; `lit_check.call(room)`
## says whether the room on their other side is lit, -1 being the outside), `set_night(0..1)`, `set_revealed(on)` and `tick(dt)` each frame. A reveal takes the veil away over FADE seconds
## with a flash of light at the doorways; a veil made for a room that is revealed already is not drawn.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const SHADER := preload("res://scripts/render/room_veil.gdshader")

const TILE := GD.TILE
const FADE := 0.3
const FLASH_S := 0.3
## The quad reaches this far (tiles) past the floor: the feathered edge, the wall and the doorway.
const MARGIN := 1.0
const MAX_DOORS := 4

var room := -1
var house := -1
var rect_t := Rect2()
var revealed := false
var lit_check := Callable()

var _mat: ShaderMaterial
var _fade := 1.0
var _flash := 0.0
var _night := -1.0
var _doors: Array = []
var _other: Array = []
var _door_data := PackedVector4Array()
var _door_dir := PackedVector2Array()


func setup(room_idx: int, house_id: int, rect: Rect2i, is_revealed: bool) -> void:
	room = room_idx
	house = house_id
	rect_t = Rect2(rect)
	revealed = is_revealed
	position = rect_t.position * TILE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("room_size", rect_t.size)
	_mat.set_shader_parameter("seed", float(room_idx % 97))
	_door_data.resize(MAX_DOORS)
	_door_dir.resize(MAX_DOORS)
	for i in MAX_DOORS:
		_door_data[i] = Vector4.ZERO
		_door_dir[i] = Vector2.DOWN
	_mat.set_shader_parameter("doors", _door_data)
	_mat.set_shader_parameter("dirs", _door_dir)
	material = _mat
	_fade = 0.0 if revealed else 1.0
	_mat.set_shader_parameter("fade", _fade)
	visible = not revealed
	queue_redraw()


## The doors that open into this room (at most MAX_DOORS): their place and the way their light goes are fixed here, how open they are is read every frame.
func bind_doors(doors: Array, lit: Callable) -> void:
	lit_check = lit
	_doors.clear()
	_other.clear()
	var centre := rect_t.get_center()
	for d in doors:
		if _doors.size() >= MAX_DOORS:
			break
		var i := _doors.size()
		var ns: bool = d.passage_ns()
		var at: Vector2 = d.center - rect_t.position
		var dir := Vector2(0.0, signf(centre.y - d.center.y)) if ns else Vector2(signf(centre.x - d.center.x), 0.0)
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN if ns else Vector2.RIGHT
		var half: float = (d.rect_t.size.x if ns else d.rect_t.size.y) * 0.5
		_door_data[i] = Vector4(at.x, at.y, 0.0, half)
		_door_dir[i] = dir
		_doors.append(d)
		_other.append(d.room_b if d.room_a == room else d.room_a)
	_mat.set_shader_parameter("doors", _door_data)
	_mat.set_shader_parameter("dirs", _door_dir)


## 0 (day) to 1 (night): the veil is a little darker and the light of a door cold.
func set_night(n: float) -> void:
	if absf(n - _night) < 0.01:
		return
	_night = n
	_mat.set_shader_parameter("night", n)


func set_revealed(on: bool) -> void:
	if on and not revealed and _fade > 0.5:
		_flash = 1.0
		_mat.set_shader_parameter("flash", _flash)
	revealed = on


func tick(dt: float) -> void:
	var want := 0.0 if revealed else 1.0
	if _fade != want:
		_fade = move_toward(_fade, want, dt / FADE)
		_mat.set_shader_parameter("fade", _fade)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt / FLASH_S)
		_mat.set_shader_parameter("flash", _flash)
	visible = _fade > 0.01 or _flash > 0.0
	if not visible:
		return
	var changed := false
	for i in _doors.size():
		var d = _doors[i]
		var z := 0.0
		if is_instance_valid(d) and d.open_t > 0.0 and (not lit_check.is_valid() or lit_check.call(_other[i])):
			z = d.open_t
		if z != _door_data[i].z:
			var v := _door_data[i]
			_door_data[i] = Vector4(v.x, v.y, z, v.w)
			changed = true
	if changed:
		_mat.set_shader_parameter("doors", _door_data)


func _draw() -> void:
	var m := MARGIN * TILE
	draw_rect(Rect2(Vector2(-m, -m), rect_t.size * TILE + Vector2(m, m) * 2.0), Color.WHITE)
