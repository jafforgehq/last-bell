## The 16-direction bodies of the prison's key looks (assets/pawns16, made by tools/make_pawn_dirs_blender.py and tools/pack_pawn_dirs.py). One atlas for each look: a column for each
## heading (0 east, 4 south, 8 west, 12 north: the angle of `PawnNode._ori`), a row for each frame of the stride (6 frames, frame 0 and 3 are the legs together). A sprite is the whole
## body (head, trunk, legs; a walker's arms too) without the ground shadow and, for a person, without arms or gun: those stay live. Nothing here is read by the rules.
extends RefCounted

const INDEX := "res://assets/pawns16/index.json"
static var _sets := {}
static var _index = null


## The look `name`'s atlas as {tex, cell: Vector2, origin: Vector2, gutter, dirs, frames, dens}, or null when there is none.
static func get_set(name: String):
	if name == "":
		return null
	if _sets.has(name):
		return _sets[name]
	if _index == null:
		_index = {}
		if FileAccess.file_exists(INDEX):
			var j = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
			if j is Dictionary:
				_index = j.get("sets", {})
	var d = null
	if _index.has(name):
		var m: Dictionary = _index[name]
		var tex = load(String(m.file))
		if tex != null:
			d = {"tex": tex, "cell": Vector2(m.cell[0], m.cell[1]), "origin": Vector2(m.origin[0], m.origin[1]), "gutter": int(m.gutter), "dirs": int(m.dirs), "frames": int(m.frames), "dens": float(m.density)}
	_sets[name] = d
	return d


## Draws the picture for heading `ori` (radians) and stride phase `ph` in the node's current frame (tiles): the sprite's origin is the node's origin.
static func blit(pen, s: Dictionary, ori: float, ph: float, col: Color = Color.WHITE) -> void:
	var di := posmod(int(roundf(ori / (TAU / float(s.dirs)))), int(s.dirs))
	var fi := posmod(int(roundf(ph / TAU * float(s.frames))), int(s.frames))
	var g: int = s.gutter
	var cell: Vector2 = s.cell
	var src := Rect2(float(di) * (cell.x + 2.0 * g) + g, float(fi) * (cell.y + 2.0 * g) + g, cell.x, cell.y)
	var dens: float = s.dens
	pen.draw_texture_rect_region(s.tex, Rect2(-(s.origin as Vector2) / dens, cell / dens), src, col)


## Round 11: the same picture as `blit` but as [dst Rect2 (tiles), src Rect2], so a caller can cut the head from the body.
static func rect_of(s: Dictionary, ori: float, ph: float) -> Array:
	var di := posmod(int(roundf(ori / (TAU / float(s.dirs)))), int(s.dirs))
	var fi := posmod(int(roundf(ph / TAU * float(s.frames))), int(s.frames))
	var g: int = s.gutter
	var cell: Vector2 = s.cell
	var dens: float = s.dens
	return [Rect2(-(s.origin as Vector2) / dens, cell / dens), Rect2(float(di) * (cell.x + 2.0 * g) + g, float(fi) * (cell.y + 2.0 * g) + g, cell.x, cell.y)]


# ==================================================================================================================== ROUND 8: the zombie art set
## assets/zombies16 (tools/make_zombie_dirs_blender.py, tools/pack_zombie_dirs.py): for each kind (walker, runner, brute, crawler) several looks, one atlas for each look. An atlas is a stack of
## pose regions (walk, idle, attack, hurt, deathf, deathb), each a grid with a column for each heading and a row for each frame. Prison only, like the rest of this file.
##
##   PawnDirs.zombie_frame(kind, look, pose, phase, heading) -> {tex, src: Rect2, dst: Rect2}   (the picture to draw, `dst` in tiles from the figure's origin; {} when there is none)
##   PawnDirs.zombie_look_of(kind, key) -> look   (a stable look for a zombie: pass its look_index or a hash of its id)
##   PawnDirs.zombie_heading(ori) -> 0..15        (the heading index of PawnNode._ori: 0 east, 4 south, 8 west, 12 north)
##   PawnDirs.zombie_blit(pen, zs, pose, phase, heading, col)   (the same, drawn: `zs` from zombie_set(kind, look))
##
## `pose`: "walk" and "idle" loop and `phase` is an angle in radians (one turn is one whole cycle: the walk is two steps); "attack", "hurt", "deathf" (forward fall), "deathb" (backward fall),
## "wake" (the rise from the ground: the forward fall played backwards) are one-shots and `phase` is the progress 0..1 (the frame is the nearest of the set's frames, so an attack of 3 frames
## is rear back below 0.33, strike below 0.66, recover after); "corpse" and "corpseb" are the last frame of the two falls. `heading` is an index 0..15 whatever the pose: a pose that has 8
## headings (idle, attack, hurt, deaths) takes the nearest. A pose a set does not have falls back (POSE_FALLBACK) so that a look with fewer poses still draws.
## The sprite is baked at the kind's own size (BAKE_SIZE): the node scales it by (the rules' size) / BAKE_SIZE only.
const ZINDEX := "res://assets/zombies16/index.json"
const BAKE_SIZE := {"walker": 1.0, "runner": 0.94, "brute": 1.4, "crawler": 1.0}
const POSE_FALLBACK := {"idle": "walk", "attack": "walk", "hurt": "idle", "deathb": "deathf", "deathf": "walk", "wake": "deathf", "corpse": "deathf", "corpseb": "deathb"}
const LOOPING := ["walk", "idle"]
static var _zsets := {}
static var _zindex = null
static var _zcount := {}


static func _zload() -> void:
	if _zindex != null:
		return
	_zindex = {}
	if FileAccess.file_exists(ZINDEX):
		var j = JSON.parse_string(FileAccess.get_file_as_string(ZINDEX))
		if j is Dictionary:
			_zindex = j.get("sets", {})
	for n in _zindex:
		var k := String(n).rsplit("_", true, 1)[0]
		_zcount[k] = int(_zcount.get(k, 0)) + 1


## How many looks of a kind there are (0: none, the old art is used).
static func zombie_looks(kind: String) -> int:
	_zload()
	return int(_zcount.get(kind, 0))


## A stable look of this kind for `key` (a zombie's look_index, or a hash of its id): the same zombie always gets the same one.
static func zombie_look_of(kind: String, key: int) -> int:
	var n := zombie_looks(kind)
	if n <= 0:
		return -1
	return posmod(int(key) * 7 + int(key >> 3) * 3 + 1, n)


static func zombie_heading(ori: float) -> int:
	return posmod(int(roundf(ori / (TAU / 16.0))), 16)


## The atlas of look `look` of `kind` as {tex, gutter, dens, poses: {pose: {y, cell: Vector2, origin: Vector2, dirs, frames}}, kind}, or null.
static func zombie_set(kind: String, look: int):
	_zload()
	var name := "%s_%d" % [kind, look]
	if _zsets.has(name):
		return _zsets[name]
	var d = null
	if _zindex.has(name):
		var m: Dictionary = _zindex[name]
		var tex = load(String(m.file))
		if tex != null:
			var ps := {}
			for p in m.poses:
				var q: Dictionary = m.poses[p]
				ps[p] = {"y": int(q.y), "cell": Vector2(q.cell[0], q.cell[1]), "origin": Vector2(q.origin[0], q.origin[1]), "dirs": int(q.dirs), "frames": int(q.frames)}
			d = {"tex": tex, "gutter": int(m.gutter), "dens": float(m.density), "poses": ps, "kind": kind}
	_zsets[name] = d
	return d


static func zombie_frame(kind: String, look: int, pose: String, phase: float, heading: int) -> Dictionary:
	var zs = zombie_set(kind, look)
	return {} if zs == null else zombie_pick(zs, pose, phase, heading)


## The picture of set `zs` for a pose, phase and heading (see the header above): {tex, src, dst}.
static func zombie_pick(zs: Dictionary, pose: String, phase: float, heading: int) -> Dictionary:
	var ps: Dictionary = zs.poses
	var rev := false
	var last := false
	var name := pose
	if name == "wake":
		rev = true
		name = "deathf"
	elif name == "corpse" or name == "corpseb":
		last = true
		name = "deathf" if name == "corpse" else "deathb"
	var guard := 0
	while not ps.has(name) and guard < 4:
		name = String(POSE_FALLBACK.get(name, "walk"))
		guard += 1
	if not ps.has(name):
		return {}
	var p: Dictionary = ps[name]
	var nf: int = p.frames
	var fi := 0
	if last:
		fi = nf - 1
	elif LOOPING.has(pose) and ps.has(pose):
		fi = posmod(int(roundf(phase / TAU * float(nf))), nf)
	elif name == "walk" and pose != "walk":
		fi = 0    # (a fallback to the walk stands in the first picture of it)
	else:
		fi = clampi(int(phase * float(nf)), 0, nf - 1)
		if rev:
			fi = nf - 1 - fi
	var dirs: int = p.dirs
	var di := posmod(int(roundf(float(heading) * float(dirs) / 16.0)), dirs)
	var g: int = zs.gutter
	var cell: Vector2 = p.cell
	var src := Rect2(float(di) * (cell.x + 2.0 * g) + g, float(p.y) + float(fi) * (cell.y + 2.0 * g) + g, cell.x, cell.y)
	var dens: float = zs.dens
	return {"tex": zs.tex, "src": src, "dst": Rect2(-(p.origin as Vector2) / dens, cell / dens)}


static func zombie_blit(pen, zs: Dictionary, pose: String, phase: float, heading: int, col: Color = Color.WHITE) -> void:
	var f := zombie_pick(zs, pose, phase, heading)
	if not f.is_empty():
		pen.draw_texture_rect_region(f.tex, f.dst, f.src, col)
