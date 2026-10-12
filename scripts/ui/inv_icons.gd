## The pictures of the inventory (INV2): one PNG atlas (assets/ui/inv/inv_icons.png, made by tools/make_item_icons.py) holds every item, the weapon, the swing, the pack's badge, the quick slots'
## frames, a soft glow and Ruth's outline; assets/ui/inv/inv_icons.json says where each one sits. Each item's picture is drawn at 128 px for each cell of its footprint (a bottle is 128 x 256), so it
## is shown at the cell's own size, 32 to 72 px, with mipmaps (a window's grids and the doll ask for them: `prepare`). Each kind is told by its SHAPE as well as its colour (a red tube on a brass
## base, a tin with a label, a green wrapped pack, a bottle with a cap, a jug with a handle, a round roll, a white case with a red cross, a box).
##
## `draw_item(ci, id, rect, rot, cell, count)` paints an item into `rect` (its footprint in pixels, already turned by `rot`: a turned item is the picture turned a quarter). `draw_region` paints any
## named picture into a rectangle (kept in its own proportions when asked). Pure drawing: nothing here reads the game but the item table.
extends RefCounted

const InvApi := preload("res://scripts/ui/inv_api.gd")

const ATLAS := "res://assets/ui/inv/inv_icons.png"
const TABLE := "res://assets/ui/inv/inv_icons.json"

## The items that have a picture of their own (a test says so when items.json has one more); any other is drawn as a box with a question mark.
const KNOWN := ["shells", "shell_box", "canned_food", "ration_pack", "water_bottle", "water_jug", "bandage", "medkit"]
## A stack of loose shells is told by its size: one shell, a few, a box's worth.
const SHELL_FEW := 2
const SHELL_BOX := 12

const OUT := Color("#0e1a15")
const BRASS := Color("#d2a94e")
const CREAM := Color("#ece4cd")
const GREY := Color("#7d857e")

## The colour a store is told by (a faint wash behind its items, the stores panel's rows).
const RES_COLOR := {"ammo": Color("#d2a94e"), "food": Color("#e09040"), "water": Color("#4f9fd0"), "meds": Color("#e0584a"), "scrap": Color("#9aa39c"), "parts": Color("#7ad0ff"), "fuel": Color("#e8c040")}

static var _tex: Texture2D = null
static var _regions := {}
static var _tried := false


static func res_color(res: String) -> Color:
	return RES_COLOR.get(res, Color("#b3a57f"))


## Reads the atlas and its table (once). A tree that has no atlas yet draws boxes with a "?".
static func _load() -> void:
	if _tried:
		return
	_tried = true
	if ResourceLoader.exists(ATLAS):
		_tex = load(ATLAS) as Texture2D
	if FileAccess.file_exists(TABLE):
		var f := FileAccess.open(TABLE, FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text()) if f != null else null
		if j is Dictionary and (j as Dictionary).get("regions") is Dictionary:
			for k in j.regions:
				var a: Array = j.regions[k]
				_regions[String(k)] = Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


static func texture() -> Texture2D:
	_load()
	return _tex


## Forgets what was read (a test that changes the files).
static func reset() -> void:
	_tex = null
	_regions = {}
	_tried = false


static func has_region(name: String) -> bool:
	_load()
	return _regions.has(name)


## The pixels of a picture in the atlas ((0, 0, 0, 0) for one that is none).
static func region(name: String) -> Rect2:
	_load()
	return _regions.get(name, Rect2())


## The names of the pictures in the atlas.
static func region_names() -> Array:
	_load()
	return _regions.keys()


## Mipmapped, linear: a picture of 128 px a cell is shown at 32 to 72 (a canvas item draws with this filter once `prepare` has set it).
static func prepare(ci: CanvasItem) -> void:
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## The picture an item shows for a count: loose shells are one shell, a few or a box by how many there are; every other item has its own.
static func picture_of(id: String, count: int = 1) -> String:
	if id == "shells":
		if count >= SHELL_BOX:
			return "shell_box"
		return "shell" if count < SHELL_FEW else "shells"
	return id if has_region(id) else "unknown"


## `name` painted into `dest` (stretched); `tint` multiplies it.
static func draw_region(ci: CanvasItem, name: String, dest: Rect2, tint: Color = Color.WHITE) -> void:
	var t := texture()
	var r := region(name)
	if t == null or r.size.x <= 0.0:
		ci.draw_rect(dest.grow(-2.0), Color(CREAM, 0.25))
		ci.draw_rect(dest.grow(-2.0), OUT, false, 1.5)
		return
	ci.draw_texture_rect_region(t, dest, r, tint)


## `name` painted as large as fits in `box`, in its own proportions, centred.
static func draw_fit(ci: CanvasItem, name: String, box: Rect2, tint: Color = Color.WHITE) -> void:
	var r := region(name)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		draw_region(ci, name, box, tint)
		return
	var k := minf(box.size.x / r.size.x, box.size.y / r.size.y)
	var sz := r.size * k
	draw_region(ci, name, Rect2(box.position + (box.size - sz) * 0.5, sz), tint)


## `id` painted in `rect` (the footprint on screen, turned by `rot`), at `cell` pixels a cell: a quarter turn turns the picture.
static func draw_item(ci: CanvasItem, id: String, rect: Rect2, rot: int, cell: float, count: int = 1) -> void:
	var d: Dictionary = InvApi.item(id)
	var pic := picture_of(id, count)
	var own := Rect2(Vector2.ZERO, Vector2(float(d.w), float(d.h)) * cell)
	if rot == 1:
		ci.draw_set_transform(rect.position + Vector2(float(d.h) * cell, 0.0), PI / 2.0, Vector2.ONE)
	else:
		ci.draw_set_transform(rect.position, 0.0, Vector2.ONE)
	draw_region(ci, pic, own)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ----------------------------------------------------------------------------- equipment --

## The pump shotgun, side on, in `rect` (kept in its own proportions).
static func draw_gun(ci: CanvasItem, rect: Rect2, tint: Color = Color.WHITE) -> void:
	draw_fit(ci, "pump_shotgun", rect, tint)


## The swing of a blow, in `rect`: a bat and the swish of the arc, no item.
static func draw_melee(ci: CanvasItem, rect: Rect2, tint: Color = Color.WHITE) -> void:
	draw_fit(ci, "melee", rect, tint)


## A small backpack for the chip and the window's head, in `rect`; `warn` tints it amber (the pack is nearly full).
static func draw_pack(ci: CanvasItem, rect: Rect2, warn: bool = false) -> void:
	draw_fit(ci, "pack", rect, Color("#ffb070") if warn else Color.WHITE)
