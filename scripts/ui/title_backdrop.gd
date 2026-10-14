## The title's picture: the prison gate at night (assets/title/prison_night.png, a clean frame of the real prison base scene taken with
## `--prison --managed --hour=22 --nohud --cam=48,52`: the fence, two towers with a guard each, the dead at the wire). It pans slowly and two layers of
## fog drift over it; "reduce motion" holds all of it. It covers the old town behind the title, so the menu on top reads against a prison, not a street.
extends Control

const PICTURE := "res://assets/title/prison_night.png"
const ZOOM := 1.10
const PAN_S := 90.0

var _pic: TextureRect
var _fog: Array = []
var _t := 0.0
var _still := false


func setup(still: bool) -> void:
	_still = still
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_pic = TextureRect.new()
	_pic.texture = load(PICTURE)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_SCALE
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pic)
	for i in 2:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.004 + 0.003 * i
		n.seed = 11 + i * 7
		var tex := NoiseTexture2D.new()
		tex.noise = n
		tex.width = 512
		tex.height = 256
		tex.seamless = true
		tex.color_ramp = _ramp()
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_TILE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.modulate.a = 0.55 - 0.15 * i
		add_child(r)
		_fog.append(r)
	resized.connect(_layout)
	_layout()


static func _ramp() -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.55, 0.62, 0.78, 0.0), Color(0.55, 0.62, 0.78, 0.30)])
	g.offsets = PackedFloat32Array([0.35, 0.9])
	return g


func _layout() -> void:
	_place()


func _process(dt: float) -> void:
	if not _still:
		_t += dt
	_place()


func _place() -> void:
	var v := size
	if v.x < 1.0:
		return
	var sc := maxf(v.x / 1920.0, v.y / 1080.0) * ZOOM
	var sz := Vector2(1920.0, 1080.0) * sc
	var room := sz - v
	var k := 0.5 - 0.5 * cos(_t * TAU / PAN_S)    # 0..1..0: a slow there-and-back
	_pic.size = sz
	_pic.position = Vector2(-room.x * (0.15 + 0.7 * k), -room.y * (0.8 - 0.5 * k))
	for i in _fog.size():
		var r: TextureRect = _fog[i]
		r.size = v * 1.0
		r.position = Vector2.ZERO
		# the tile is slid under the rect by its texture-less trick: move the rect, wider than the view, and wrap it
		var w := 1024.0 * (1 + i)
		r.size = v + Vector2(w, 0)
		r.position = Vector2(-fposmod(_t * (14.0 + 9.0 * i), w), 0)
