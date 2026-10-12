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
