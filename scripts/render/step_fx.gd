## FEEL: footstep dust. A foot that lands on earth, grass or a road kicks up a small puff (a run or a heavy dead one, more of it); in rain the foot splashes instead; a wooden floor shows a
## faint one only for a hard step, and a floor indoors none. Render only: pawn_node.gd tells `PawnMotion.step_cb` where a step landed (combat_fx.gd hands it here), the rules never read any of it.
##
## COST. Puffs live in fixed arrays (a ring: the oldest goes when it is full), are drawn from the one soft puff picture in `draw` (they join the ground's other bits, one batch), rings and drops
## of a splash are untextured polylines and circles; a frame makes at most BUDGET new ones, and a step with the pool busy is thinned. Nothing is allocated after the first step.
extends RefCounted

const TILE := 64.0
const MAX_PUFFS := 48
const MAX_SPLASH := 20
const BUDGET := 7
## What is under a foot, by the terrain's NAME (map data's terrainTypes: the same words the soundscape reads).
const S_NONE := 0
const S_DIRT := 1
const S_HARD := 2
const S_WOOD := 3
const DIRT_WORDS := ["GRASS", "SOIL", "DIRT", "YARD", "MUD", "SAND", "LAWN", "FIELD", "GARDEN", "LEAF", "FOREST"]
const HARD_WORDS := ["ASPHALT", "SIDEWALK", "CONCRETE", "GRAVEL", "ROAD"]
const WOOD_WORDS := ["WOOD", "PLANK", "DECK", "PARQUET", "BOARD"]
## The colour of the dust on each surface (alpha is the puff's start strength).
## (The soft puff picture is a mid grey, about 0.6, so these are brighter than the dust they stand for.)
const COL_DIRT := Color(1.20, 1.04, 0.80, 0.55)
const COL_HARD := Color(1.25, 1.25, 1.20, 0.42)
const COL_WOOD := Color(1.20, 1.08, 0.90, 0.26)
const COL_WET := Color(1.30, 1.42, 1.55, 0.55)

var puff_tex: Texture2D
var world
## A Callable that says how wet the ground is now (0 to 1; main.gd gives the rain's): above WET_FROM a step splashes.
var wet_cb := Callable()
const WET_FROM := 0.35
## "Reduce motion" (combat_fx.gd `calm`): fewer, smaller, shorter puffs.
var calm := false

var _surf := PackedByteArray()
var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _life := PackedFloat32Array()
var _max := PackedFloat32Array()
var _size := PackedFloat32Array()
var _grow := PackedFloat32Array()
var _col := PackedColorArray()
var _head := 0
var _live := 0
var _sp_x := PackedFloat32Array()
var _sp_y := PackedFloat32Array()
var _sp_life := PackedFloat32Array()
var _sp_size := PackedFloat32Array()
var _sp_head := 0
var _sp_live := 0
var _budget := BUDGET
var _rng := RandomNumberGenerator.new()
## What it made, for a probe: puffs and splashes begun, the most puffs alive at once.
var made := 0
var splashed := 0
var peak := 0
var drawn := 0


func _init() -> void:
	_rng.seed = 8675
	_px.resize(MAX_PUFFS)
	_py.resize(MAX_PUFFS)
	_vx.resize(MAX_PUFFS)
	_vy.resize(MAX_PUFFS)
	_life.resize(MAX_PUFFS)
	_max.resize(MAX_PUFFS)
	_size.resize(MAX_PUFFS)
	_grow.resize(MAX_PUFFS)
	_col.resize(MAX_PUFFS)
	_sp_x.resize(MAX_SPLASH)
	_sp_y.resize(MAX_SPLASH)
	_sp_life.resize(MAX_SPLASH)
	_sp_size.resize(MAX_SPLASH)


## Reads the ground's names from the map data (`data.terrainTypes`) and the tiles from `w` (a world: `terrain` bytes, `W`, `H`).
func setup(w, data: Dictionary, puff: Texture2D) -> void:
	world = w
	puff_tex = puff
	_surf.resize(256)
	_surf.fill(S_NONE)
	var types = data.get("terrainTypes", {})
	if types is Dictionary:
		for tname in types:
			var id := int(types[tname].get("id", -1))
			if id < 0 or id > 255:
				continue
			var up := String(tname).to_upper()
			var s := S_NONE
			if _has(up, DIRT_WORDS):
				s = S_DIRT
			elif _has(up, HARD_WORDS):
				s = S_HARD
			elif _has(up, WOOD_WORDS):
				s = S_WOOD
			_surf[id] = s


static func _has(up: String, words: Array) -> bool:
	for w in words:
		if up.contains(String(w)):
			return true
	return false


## What is under a place (tiles): S_NONE (an indoor floor, nothing known), S_DIRT, S_HARD or S_WOOD.
func surface_at(x: float, y: float) -> int:
	if world == null or _surf.is_empty():
		return S_DIRT
	var cx := int(floor(x))
	var cy := int(floor(y))
	if cx < 0 or cy < 0 or cx >= int(world.W) or cy >= int(world.H):
		return S_NONE
	return _surf[int(world.terrain[cy * int(world.W) + cx]) & 255]


func clear() -> void:
	for i in MAX_PUFFS:
		_life[i] = 0.0
	for i in MAX_SPLASH:
		_sp_life[i] = 0.0
	_live = 0
	_sp_live = 0


func live_count() -> int:
	return _live + _sp_live


## A foot lands at (x, y) tiles (the figure's feet), the figure going `dir` (a unit vector, or zero); `power` 0.4 for a slow walker to 1.0 for a run, 1.4 for a brute.
func step(x: float, y: float, dir: Vector2, power: float) -> void:
	if _budget <= 0:
		return
	var sf := surface_at(x, y)
	if sf == S_NONE or (sf == S_WOOD and power < 0.95):
		return
	if calm:
		power *= 0.6
	var wet := 0.0
	if wet_cb.is_valid():
		wet = float(wet_cb.call())
	if wet > WET_FROM and sf != S_WOOD:
		_budget -= 1
		_splash(x, y + 0.27, power)
		return
	var col := COL_DIRT if sf == S_DIRT else (COL_HARD if sf == S_HARD else COL_WOOD)
	var n := 1 if power < 0.95 else 2
	_budget -= 1
	for i in n:
		var back := -dir * _rng.randf_range(0.30, 0.65) * power
		var c := col
		c.a *= clampf(power, 0.5, 1.3) * _rng.randf_range(0.85, 1.1)
		_add(x + _rng.randf_range(-0.05, 0.05), y + 0.27 + _rng.randf_range(0.0, 0.04), back.x + _rng.randf_range(-0.08, 0.08), back.y - 0.10 + _rng.randf_range(-0.05, 0.03),
			_rng.randf_range(0.42, 0.62) * (0.7 if calm else 1.0) * clampf(power, 0.7, 1.3), 0.08 * (0.7 + 0.5 * power), 0.40 * (0.6 + 0.6 * power), c)


func _add(x: float, y: float, vx: float, vy: float, life: float, size: float, grow: float, col: Color) -> void:
	var i := _head
	_head = (_head + 1) % MAX_PUFFS
	if _life[i] <= 0.0:
		_live += 1
	_px[i] = x
	_py[i] = y
	_vx[i] = vx
	_vy[i] = vy
	_life[i] = life
	_max[i] = life
	_size[i] = size
	_grow[i] = grow
	_col[i] = col
	made += 1
	if _live > peak:
		peak = _live


## A step in the rain: a small ring opens on the ground and two or three drops jump.
func _splash(x: float, y: float, power: float) -> void:
	var i := _sp_head
	_sp_head = (_sp_head + 1) % MAX_SPLASH
	if _sp_life[i] <= 0.0:
		_sp_live += 1
	_sp_x[i] = x
	_sp_y[i] = y
	_sp_life[i] = 0.30
	_sp_size[i] = 0.07 * clampf(power, 0.6, 1.4)
	splashed += 1
	# (the drops are a pair of fine puffs thrown up and out: drawn as the dust is, in the splash's colour)
	for k in 2:
		_add(x + _rng.randf_range(-0.04, 0.04), y, _rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.7, -0.35), 0.22, 0.02, 0.02, Color(COL_WET.r, COL_WET.g, COL_WET.b, 0.55))


func update(dt: float) -> void:
	_budget = BUDGET
	if _live > 0:
		for i in MAX_PUFFS:
			var l := _life[i]
			if l <= 0.0:
				continue
			l -= dt
			if l <= 0.0:
				_life[i] = 0.0
				_live -= 1
				continue
			_life[i] = l
			_px[i] += _vx[i] * dt
			_py[i] += _vy[i] * dt
			var drag := 1.0 - minf(1.0, 3.0 * dt)
			_vx[i] *= drag
			_vy[i] *= drag
			_size[i] += _grow[i] * dt
	if _sp_live > 0:
		for i in MAX_SPLASH:
			var l2 := _sp_life[i]
			if l2 <= 0.0:
				continue
			l2 -= dt
			if l2 <= 0.0:
				_sp_life[i] = 0.0
				_sp_live -= 1
			else:
				_sp_life[i] = l2


## Painted in tile units over the ground (under the people): the puffs (one batch of the soft picture), then the splashes' rings.
func draw(ci: CanvasItem) -> void:
	if _live <= 0 and _sp_live <= 0:
		return
	drawn += 1
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	if _live > 0 and puff_tex != null:
		for i in MAX_PUFFS:
			var l := _life[i]
			if l <= 0.0:
				continue
			var f := l / _max[i]
			var c: Color = _col[i]
			c.a *= minf(1.0, f * 2.2) * minf(1.0, (1.0 - f) * 9.0 + 0.35)
			var r := _size[i]
			ci.draw_texture_rect(puff_tex, Rect2(_px[i] - r, _py[i] - r * 0.8, r * 2.0, r * 1.6), false, c)
	if _sp_live > 0:
		for i in MAX_SPLASH:
			var l2 := _sp_life[i]
			if l2 <= 0.0:
				continue
			var u := 1.0 - l2 / 0.30
			var r2 := _sp_size[i] * (1.0 + 2.2 * u)
			var c2 := COL_WET
			c2.a *= (1.0 - u) * 0.9
			var pts := PackedVector2Array()
			for k in 11:
				var a := TAU * float(k) / 10.0
				pts.append(Vector2(_sp_x[i] + cos(a) * r2, _sp_y[i] + sin(a) * r2 * 0.55))
			ci.draw_polyline(pts, c2, 0.018, true)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
