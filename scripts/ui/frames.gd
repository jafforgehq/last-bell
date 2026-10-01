## The frames of the HUD and the menus: slate chalkboards in oak trim, a brass-rimmed
## clock, hall-pass badges for the crew, paper slips for the alerts, notebook paper for the
## modals, buttons, chips and bars. The pictures are made by tools/make_ui_theme.py (see
## the top of that script) and listed in assets/ui/theme/frames.json:
##
##     const Frames := preload("res://scripts/ui/frames.gd")
##     panel.add_theme_stylebox_override("panel", Frames.box("panel"))
##     var slip := Frames.box("slip", Color("#e0584a"))   # a tinted frame
##
## Frames.box(name, tint) is a StyleBoxTexture, or null when there is no frame of that name
## or its picture is not there (not imported yet): the caller keeps the flat style it has.
## A missing frame is never an error. Each call makes a new style box (so a caller may change
## its content margins or tint) that shares the texture, which is made once.
##
## The pictures are drawn at twice the size they are shown at, so they are sharp on a screen
## with twice the pixels: a texture made from one reports half its size (set_size_override),
## which makes a nine-patch drawn from it half as big, and the margins here are in the units
## of the HUD ("logical" pixels), half the margins in the picture. The tiled middles are
## made seamless, and the texture has no mipmaps, which would show a seam where a tile ends.
##
## Frame names: panel (the HUD's board), panel_slim (a board with a thin trim, for a toolbar),
## panel_inset (a block set into a board), card and card_selected (the crew's hall passes),
## slip (a pinned alert, tinted by the caller), paper (a modal, ruled notebook paper), tooltip,
## toast, chip (a key), button, button_hover, button_pressed, button_off, button_primary,
## button_primary_hover, button_primary_pressed, bar_track (the groove of a meter), bar_fill (what
## fills it, tinted by the caller), pill (a stamp, tinted by the caller), clock (the brass-rimmed
## time panel), banner (a sign).
## `Frames.avg(name)` is the average colour of a frame's middle and `Frames.ink(name)` the text
## colour that reads on it; `Frames.info(name)` has the rest of what frames.json says.
extends RefCounted

const DEFAULT_PATH := "res://assets/ui/theme/frames.json"
## The pictures are made at twice the size they are shown at.
const SCALE := 0.5
const MODES := {
	"stretch": StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH,
	"tile": StyleBoxTexture.AXIS_STRETCH_MODE_TILE,
	"tile_fit": StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT,
}

## Where frames.json is; a test points it somewhere else (then calls forget).
static var path := DEFAULT_PATH
static var _table = null          # Dictionary, name -> entry of frames.json; null until read
static var _textures := {}        # name -> Texture2D, null for one that is not there (tried once)


## Whether there is a frame of this name with its picture.
static func has(name: String) -> bool:
	return _texture(name) != null


## The frame as a StyleBoxTexture, tinted (the picture multiplied by `tint`), or null.
static func box(name: String, tint: Color = Color.WHITE) -> StyleBox:
	var tex := _texture(name)
	if tex == null:
		return null
	var e: Dictionary = _entries()[name]
	var margin := _quad(e.get("margin"), 0.0)
	var content := _quad(e.get("content"), -1.0)
	var expand := _quad(e.get("expand"), 0.0)
	var stretch: Array = e.get("stretch", ["tile_fit", "tile_fit"])
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin[0] * SCALE
	sb.texture_margin_top = margin[1] * SCALE
	sb.texture_margin_right = margin[2] * SCALE
	sb.texture_margin_bottom = margin[3] * SCALE
	sb.expand_margin_left = expand[0]
	sb.expand_margin_top = expand[1]
	sb.expand_margin_right = expand[2]
	sb.expand_margin_bottom = expand[3]
	sb.content_margin_left = content[0]
	sb.content_margin_top = content[1]
	sb.content_margin_right = content[2]
	sb.content_margin_bottom = content[3]
	sb.axis_stretch_horizontal = MODES.get(String(stretch[0]), StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT)
	sb.axis_stretch_vertical = MODES.get(String(stretch[1]), StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT)
	sb.modulate_color = tint
	return sb


## What frames.json says about a frame (a copy; empty for a name that is not listed): "file",
## "margin" (in the pixels of the picture), "content" and "expand" (in logical pixels),
## "stretch", "avg" (the average colour of the middle, "#rrggbb") and "ink" (the text colour
## that reads on it at 4.5:1 or better).
static func info(name: String) -> Dictionary:
	var e = _entries().get(name)
	return (e as Dictionary).duplicate(true) if typeof(e) == TYPE_DICTIONARY else {}


## The average colour of the middle of a frame (what the text on it is read against), or a
## transparent black for a name that is not listed.
static func avg(name: String) -> Color:
	var e = _entries().get(name)
	if typeof(e) == TYPE_DICTIONARY and e.has("avg"):
		return Color.html(String(e.avg))
	return Color(0, 0, 0, 0)


## The text colour that reads on a frame at 4.5:1 or better (the HUD's ink on the dark ones, a dark
## ink on the pale ones), or white for a name that is not listed.
static func ink(name: String) -> Color:
	var e = _entries().get(name)
	if typeof(e) == TYPE_DICTIONARY and e.has("ink"):
		return Color.html(String(e.ink))
	return Color.WHITE


## The names frames.json lists.
static func names() -> Array:
	var out: Array = _entries().keys()
	out.sort()
	return out


## Drops what was read, so the next call reads frames.json and the pictures again. (Not called
## `reload`: that is the name of a method every script has, and it would win; see Prefs.forget.)
static func forget() -> void:
	_table = null
	_textures = {}


static func _entries() -> Dictionary:
	if _table == null:
		_table = {}
		if FileAccess.file_exists(path):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(path)) == OK and typeof(json.data) == TYPE_DICTIONARY:
				_table = json.data
	return _table


static func _texture(name: String) -> Texture2D:
	if _textures.has(name):
		return _textures[name]
	var tex: Texture2D = null
	var e = _entries().get(name)
	if typeof(e) == TYPE_DICTIONARY and e.has("file") and e.has("margin"):
		tex = _load(String(e.file))
	_textures[name] = tex
	return tex


## The picture as a texture that reports half its size. Null when it is not there (or not
## imported: ResourceLoader.exists is false until it is).
static func _load(file: String) -> Texture2D:
	if not ResourceLoader.exists(file):
		return null
	var src = load(file)
	if not (src is Texture2D):
		return null
	var img: Image = (src as Texture2D).get_image()
	if img == null or img.is_empty():
		return src as Texture2D        # a renderer that keeps no pixels (the tests run headless)
	if img.has_mipmaps():
		img.clear_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(int(img.get_width() * SCALE), int(img.get_height() * SCALE)))
	return tex


## Four numbers of an entry (a missing or malformed list gives `fallback` four times).
static func _quad(v, fallback: float) -> Array:
	var out := [fallback, fallback, fallback, fallback]
	if typeof(v) == TYPE_ARRAY and v.size() >= 4:
		for i in 4:
			out[i] = float(v[i])
	return out
