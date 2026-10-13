## ROUND 11 (prison only): the baked animation frames of the dead (tools/make_zombie_anim.py). One atlas per look and kind (assets/pawns/zan/<kind><look>.png) and one JSON index
## (zan/index.json: {kind: {look: {"view/pose/k": [x, y, w, h, ox, oy]}}}, in half-size canvas pixels; the canvas is 184 x 164 and covers the same box as the Round 10 pictures).
## `frame(set, pose, phase, view)` is all PawnNode needs: it returns {tex, src, off} (or {} when there is none) and PawnNode draws the region. Nothing here is read by the rules.
class_name RimzFrames
extends RefCounted

const DIR := "res://assets/pawns/zan/"
const HALF := Vector2(184.0, 164.0)
const RUNNERS := [1, 4, 8, 12, 17, 21]
const BRUTES := [2, 9, 13, 20]
const CRAWLERS := [3, 10, 15, 22]
## Poses that run once (the phase is how far along, 0 to 1) against those that loop (walk, idle).
const LOOPING := ["walk", "idle"]
## The decal and gib sheet: 8 cells across, 48 px each (tools/make_zombie_anim.py `--fx`).
const FX_CELL := 48
const FX_COLS := 8
const FX_WOUND := 0       # 0 to 3
const FX_SPRAY := 4       # 4 left, 5 right
const FX_STUMP := 6
const FX_BITE := 7
const FX_GIB := 8         # 8 to 11
const FX_DRIP := 12       # 12 to 13

static var _index := {}
static var _loaded := false
static var _tex := {}
static var _counts := {}
static var fx_tex: Texture2D
## The ground blood a wounded one leaves (set by the prison: x, y in tiles, size in tiles); null elsewhere.
static var blood_cb := Callable()


static func _load_index() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(DIR + "index.json", FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_index = d
	fx_tex = load(DIR + "fx.png") if ResourceLoader.exists(DIR + "fx.png") else null


## The set a figure of this kind and look wears ("walker3", "brute9", ...) or "" when none is drawn. A walker that limps may be a crawler (one in four of them, by look).
static func set_of(kind: String, look: int, limp: bool) -> String:
	_load_index()
	if _index.is_empty():
		return ""
	var key := ""
	var id := 0
	if kind == "walker" and limp and look % 4 == 0 and _index.has("crawler"):
		key = "crawler"
		id = CRAWLERS[(look / 4) % CRAWLERS.size()]
	elif kind == "runner":
		key = "runner"
		id = RUNNERS[look % RUNNERS.size()]
	elif kind == "brute":
		key = "brute"
		id = BRUTES[look % BRUTES.size()]
	else:
		key = "walker"
		id = look % 24
	if not (_index.has(key) and (_index[key] as Dictionary).has(str(id))):
		return ""
	return key + str(id)


static func kind_of_set(s: String) -> String:
	return s.rstrip("0123456789")


static func _atlas(s: String) -> Texture2D:
	if not _tex.has(s):
		_tex[s] = load(DIR + s + ".png")
	return _tex[s]


## How many frames a pose has in this set and view (0 when the pose is not drawn).
static func count(s: String, pose: String, view: String) -> int:
	var key := s + "/" + view + "/" + pose
	if _counts.has(key):
		return _counts[key]
	var k := kind_of_set(s)
	var tab: Dictionary = (_index[k] as Dictionary)[s.substr(k.length())]
	var n := 0
	while tab.has("%s/%s/%d" % [view, pose, n]):
		n += 1
	_counts[key] = n
	return n


static func has_pose(s: String, pose: String, view: String) -> bool:
	return count(s, pose, view) > 0


## One frame: `phase` 0 to 1 (a loop's turn, or how far a one-way pose has gone). {} when the pose is missing (the caller draws its Round 10 picture instead).
static func frame(s: String, pose: String, phase: float, view: String) -> Dictionary:
	var n := count(s, pose, view)
	if n == 0:
		return {}
	var i := 0
	if pose in LOOPING:
		i = int(floorf(fposmod(phase, 1.0) * n)) % n
	else:
		i = clampi(int(floorf(clampf(phase, 0.0, 1.0) * n)), 0, n - 1)
	var k := kind_of_set(s)
	var r: Array = ((_index[k] as Dictionary)[s.substr(k.length())] as Dictionary)["%s/%s/%d" % [view, pose, i]]
	return {"tex": _atlas(s), "src": Rect2(r[0], r[1], r[2], r[3]), "off": Vector2(r[4], r[5])}


## The decal picture's region for a cell.
static func fx_src(cell: int) -> Rect2:
	return Rect2((cell % FX_COLS) * FX_CELL, (cell / FX_COLS) * FX_CELL, FX_CELL, FX_CELL)


## The soft ground shadow: one radial gradient shared by every figure.
static var _shadow: GradientTexture2D


static func shadow_tex() -> Texture2D:
	if _shadow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.62), Color(0, 0, 0, 0.34), Color(0, 0, 0, 0.0)])
		_shadow = GradientTexture2D.new()
		_shadow.gradient = g
		_shadow.fill = GradientTexture2D.FILL_RADIAL
		_shadow.fill_from = Vector2(0.5, 0.5)
		_shadow.fill_to = Vector2(1.0, 0.5)
		_shadow.width = 64
		_shadow.height = 32
	return _shadow
