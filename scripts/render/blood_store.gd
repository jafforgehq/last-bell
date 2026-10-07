## FEEL: the blood that stays on the ground in the town. A hit's drops leave specks and a kill leaves a pool; both fade over a minute or so (a speck about 50 s, a pool about 80) and
## darken as they dry. EVERYTHING HERE IS RENDER ONLY (combat_fx.gd tells it where blood fell; the rules never read it).
##
## COST. One MultiMeshInstance2D draws every mark at once (ONE draw call, whatever the number): the six blood pictures are packed into one atlas, and an instance picks its cell by its
## custom data (a tiny shader moves the UVs). At most CAP marks live at once (CAP_POOLS pools and CAP_SPECKS specks: the oldest of a kind goes when its pool is full); a mark's colour
## is touched about four times a second (fifteen while one is growing), nothing is made or freed after the first mark.
extends RefCounted

const TILE := 64.0
const CAP_POOLS := 30
const CAP_SPECKS := 30
const CAP := CAP_POOLS + CAP_SPECKS
## How long a pool or a speck stays at full strength and how long it takes to fade after that (seconds of the game's time), how long it takes to grow to its size, and to dry.
const POOL_HOLD := 45.0
const POOL_FADE := 35.0
const SPECK_HOLD := 25.0
const SPECK_FADE := 25.0
const GROW_S := 2.5
const DRY_S := 25.0
## What blood looks like once it has dried (multiplied into the picture's own red), and how much of a mark's size a kill's pool has against a plain splat's.
const DRIED := Color(0.62, 0.50, 0.50)
const POOL_BOOST := 3.0
const SHADER := "shader_type canvas_item;\nuniform vec2 cells = vec2(3.0, 2.0);\nvoid vertex() {\n\tUV = (UV + INSTANCE_CUSTOM.xy) / cells;\n}\n"

var node: MultiMeshInstance2D
var multi: MultiMesh
var _atlas: Texture2D
var _cells := Vector2i(3, 2)
var _n_tex := 0
var _marks: Array = []        # {slot, born, kind, a, size, grow, pos, rot, hold, fade}
var _free: Array = []
var _used := 0
var _pools := 0
var _specks := 0
var _acc := 0.0
var _rng := RandomNumberGenerator.new()
## "Reduce flashes" and the dark look do not touch it; the town's grade darkens it with everything else.
var calm := false


## Builds the node under `parent` from the blood pictures (a list of Texture2D).
func setup(parent: Node2D, textures: Array) -> bool:
	if textures.is_empty() or parent == null:
		return false
	_rng.seed = 5150
	_n_tex = textures.size()
	var first: Image = textures[0].get_image()
	if first == null:
		return false
	var cw := first.get_width()
	var ch := first.get_height()
	_cells = Vector2i(3, int(ceil(float(_n_tex) / 3.0)))
	var img := Image.create(cw * _cells.x, ch * _cells.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in _n_tex:
		var im: Image = textures[i].get_image()
		if im == null:
			continue
		if im.is_compressed():
			im.decompress()
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		if im.get_width() != cw or im.get_height() != ch:
			im.resize(cw, ch)
		img.blit_rect(im, Rect2i(0, 0, cw, ch), Vector2i((i % _cells.x) * cw, (i / _cells.x) * ch))
	_atlas = ImageTexture.create_from_image(img)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multi = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = quad
	multi.instance_count = CAP
	node = MultiMeshInstance2D.new()
	node.name = "BloodMarks"
	node.multimesh = multi
	node.texture = _atlas
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("cells", Vector2(_cells))
	node.material = mat
	parent.add_child(node)
	multi.visible_instance_count = 0
	for i in CAP:
		multi.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))
		multi.set_instance_color(i, Color(1, 1, 1, 0))
		_free.append(CAP - 1 - i)
	return true


func count() -> int:
	return _marks.size()


func pools() -> int:
	return _pools


func specks() -> int:
	return _specks


func clear() -> void:
	if multi == null:
		return
	for m in _marks:
		_release(m)
	_marks.clear()
	_pools = 0
	_specks = 0


## A mark at (x, y) tiles: `size` is the width of the picture it is made from in tiles (a splat's own, a pool's is boosted), `pool` is a kill's, else a speck, `alpha` its strength, `grow` how
## much bigger than its first size a pool gets (a share).
func add(x: float, y: float, size: float, alpha: float, pool: bool, grow: float = 0.0) -> void:
	if multi == null:
		return
	if pool:
		if _pools >= CAP_POOLS:
			_evict(1)
	elif _specks >= CAP_SPECKS:
		_evict(0)
	if _free.is_empty():
		return
	var slot: int = _free.pop_back()
	var m := {"slot": slot, "born": 0.0, "kind": 1 if pool else 0, "a": alpha, "size": size * (POOL_BOOST if pool else 1.0), "grow": grow, "pos": Vector2(x, y) * TILE, "rot": _rng.randf() * TAU,
		"hold": POOL_HOLD if pool else SPECK_HOLD, "fade": POOL_FADE if pool else SPECK_FADE}
	_marks.append(m)
	if pool:
		_pools += 1
	else:
		_specks += 1
	var cell := _rng.randi() % _n_tex
	multi.set_instance_custom_data(slot, Color(float(cell % _cells.x), float(cell / _cells.x), 0.0, 0.0))
	if slot + 1 > _used:
		_used = slot + 1
		multi.visible_instance_count = _used
	_paint(m)
	_acc = 1.0    # (the next update looks at the young ones)


func _evict(kind: int) -> void:
	for i in _marks.size():
		if int(_marks[i].kind) == kind:
			_release(_marks[i])
			_marks.remove_at(i)
			return


func _release(m: Dictionary) -> void:
	var slot: int = m.slot
	multi.set_instance_transform_2d(slot, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))
	multi.set_instance_color(slot, Color(1, 1, 1, 0))
	_free.append(slot)
	if int(m.kind) == 1:
		_pools -= 1
	else:
		_specks -= 1


## Where a mark is in its life: strength 0 to 1 and the dried colour.
func _paint(m: Dictionary) -> void:
	var age: float = m.born
	var slot: int = m.slot
	var k := 1.0
	if age > float(m.hold):
		var f := clampf((age - float(m.hold)) / float(m.fade), 0.0, 1.0)
		k = 1.0 - f * f * (3.0 - 2.0 * f)
	var dry := clampf(age / DRY_S, 0.0, 1.0)
	var c := Color(1, 1, 1).lerp(DRIED, dry)
	c.a = float(m.a) * k
	multi.set_instance_color(slot, c)
	var sz: float = float(m.size) * TILE
	var g := float(m.grow)
	if g > 0.0 or age < GROW_S:
		# (a pool spreads: it starts at 60 percent of its width and reaches it, then a little more, over a few seconds)
		var u := clampf(age / GROW_S, 0.0, 1.0)
		sz *= lerpf(0.6, 1.0, 1.0 - (1.0 - u) * (1.0 - u)) * (1.0 + g * u * 0.25)
	multi.set_instance_transform_2d(slot, Transform2D(float(m.rot), Vector2(sz, sz), 0.0, m.pos))


## `dt` seconds of the game's time: the marks age, dry and fade.
func update(dt: float) -> void:
	if _marks.is_empty():
		return
	_acc += dt
	var young := false
	for m in _marks:
		m.born += dt
		if float(m.born) < GROW_S:
			young = true
	if _acc < (0.066 if young else 0.25):
		return
	_acc = 0.0
	var gone := false
	for m in _marks:
		_paint(m)
		if float(m.born) >= float(m.hold) + float(m.fade):
			gone = true
	if gone:
		var keep: Array = []
		for m in _marks:
			if float(m.born) >= float(m.hold) + float(m.fade):
				_release(m)
			else:
				keep.append(m)
		_marks = keep
