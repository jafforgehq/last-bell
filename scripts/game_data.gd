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


static func col(hex: String, a: float = 1.0) -> Color:
	var c := Color.html(hex)
	c.a = a
	return c


## Canvas-style shade: k < 0 darkens toward black, k > 0 lightens toward white.
static func shade(c: Color, k: float) -> Color:
	return c.darkened(-k) if k < 0.0 else c.lightened(k)
