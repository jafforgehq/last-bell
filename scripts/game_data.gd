## Loads the baked map, roster and asset list (assets/data/map.json) and caches
## textures. Everything in the game is measured in tiles; one tile is TILE
## pixels in the world.
extends RefCounted

const TILE := 64.0
const DATA_PATH := "res://assets/data/map.json"

static var data: Dictionary = {}
static var _textures: Dictionary = {}


static func load_all() -> Dictionary:
	if data.is_empty():
		var text := FileAccess.get_file_as_string(DATA_PATH)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Could not read %s" % DATA_PATH)
			return {}
		data = parsed
	return data


static func tex(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


## The size in pixels of a prop's picture, without loading it when the table has it (assets/data/prop_sizes.json, made by tools/make_prop_sizes.gd): the town generator measures every thing it
## puts on a lot, and the pictures of the art kit are up to 1000 x 1700 pixels (about 5 ms each to load on a desktop). A path the table does not know is measured by loading it.
## Vector2.ZERO when the picture is not there.
const PROP_SIZES_PATH := "res://assets/data/prop_sizes.json"
static var _prop_sizes: Dictionary = {}
static var _prop_sizes_read := false


static func tex_size(path: String) -> Vector2:
	var s := table_size(path)
	if s.x > 0.0:
		return s
	var t := tex(path)
	return Vector2(float(t.get_width()), float(t.get_height())) if t != null else Vector2.ZERO


## The size the table has for a picture, or Vector2.ZERO when it has none (the loader checks the pictures it loads against it).
static func table_size(path: String) -> Vector2:
	if not _prop_sizes_read:
		_prop_sizes_read = true
		if FileAccess.file_exists(PROP_SIZES_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(PROP_SIZES_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_prop_sizes = parsed
	var s = _prop_sizes.get(path)
	return Vector2(float(s[0]), float(s[1])) if s != null else Vector2.ZERO


static func col(hex: String, a: float = 1.0) -> Color:
	var c := Color.html(hex)
	c.a = a
	return c


## Canvas-style shade: k < 0 darkens toward black, k > 0 lightens toward white.
static func shade(c: Color, k: float) -> Color:
	return c.darkened(-k) if k < 0.0 else c.lightened(k)
