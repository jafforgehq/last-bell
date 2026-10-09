## TownArt (One House, WP2): the ONLY reader of the town art kit's manifest, assets/data/town_art.json (the pictures are under assets/town/). Everything that draws a
## roof, a door, a fence or a piece of furniture of the town asks here and gets a DESCRIPTOR:
##
##   {"item": manifest id or "", "file": path of the picture or "" (a placeholder), "rect": Rect2 (the part of the picture to draw, in its own pixels), "nine": [] or
##    [left, top, right, bottom] pixels (a nine patch), "size": Vector2 (the picture's size in tiles), "anchor": Vector2 (tiles: where the picture's top left sits
##    relative to the footprint's top left), "color": Color (the flat colour of the placeholder, and of a picture that would not load), "placeholder": bool}
##
## so a caller never names a file and never fails when the kit is late: a missing manifest, a missing item or a picture that will not load all give a flat
## colour descriptor, and nothing is logged. `draw` puts a descriptor on a CanvasItem. The manifest schema (read once, here): {"items": [{"id", "category", "kind",
## "footprint": [w, h] tiles, "anchor": [x, y] tiles, "variants": n, "facings": [...], "states": [...], "sprites": [{"file" (under assets/town), "px": [w, h],
## "fp": [w, h] tiles, "facing" or "orient", "state", "variant"}]}]}; a sprite names its picture by "file" (under assets/town) and the part of it by "rect": [x, y, w, h]
## pixels (a sheet holds many) or, in the first version of the kit, "px": [w, h] (the whole file). Ids asked for: the roof kits roof_terracotta, roof_slate and roof_shingle
## (tiles: a lit and a shade slope, a ridge cap, an eave overlay in `edges`) or roof_<house kind>; door_front, door_interior, door_garage; fence_<kit> or fence (gate,
## tower, floodlight, door_plank...); the furniture, fortify and marker items by their own id (bed_single, stash_chest, radio_set, workbench...: see PROP_ALIAS).
##
## State: `_man` (id -> item) and `_tex` (file -> texture) are lazy caches (null until first used); `load_manifest(path)` re-reads them (a test points it at a fixture and back).
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const MANIFEST := "res://assets/data/town_art.json"
const TILE := GD.TILE

## House kinds in the order of the roof colours, and the roofs' flat colours (a variant lightens or darkens them).
const ROOF_KINDS := ["small", "medium", "terrace", "shop"]
const ROOF_COLORS := [Color("8e5744"), Color("5f6e7a"), Color("78634f"), Color("56715f")]
## Flat colours of everything else, by item id (the first part of an id before a "_" is tried when the whole is not there).
const COLORS := {
	"door_front": Color("7d3e2f"), "door_interior": Color("8b6b47"), "door_garage": Color("80878d"), "door": Color("85633f"),
	"fence": Color("8c7050"), "fence_strong": Color("6e727a"), "gate": Color("5c7088"), "door_plank": Color("7a5a3a"), "tower": Color("6b6355"),
	"floodlight": Color("c8b46a"), "bed": Color("5d6d90"), "stash": Color("7d5d3b"), "radio": Color("40503f"), "bench": Color("8c6c42"),
	"container": Color("2a2118"), "cabinet": Color("2a2118"), "crate": Color("2a2118"), "fridge": Color("2a2118"), "shelf": Color("2a2118"),
}
## The footprints (tiles) of the placeholders, by item id.
const SIZES := {
	"bed": Vector2(1, 2), "stash": Vector2(1, 1), "radio": Vector2(1, 1), "bench": Vector2(2, 1), "door_garage": Vector2(3, 1),
	"container": Vector2(1, 1), "cabinet": Vector2(1, 1), "crate": Vector2(1, 1), "fridge": Vector2(1, 1), "shelf": Vector2(1, 1),
}
const FALLBACK_COLOR := Color("888078")
## The kit's roofs, in the order houses of a kind take them; and the kit's names for the base's props (the layout says bed, stash, radio, bench).
const ROOF_ITEMS := ["roof_terracotta", "roof_slate", "roof_shingle"]
const PROP_ALIAS := {"bed": ["bed_single", "bed_double"], "stash": ["stash_chest"], "radio": ["radio_set"], "bench": ["workbench"]}
## States the kit may spell either way.
const STATE_ALIAS := {"open": "opened", "opened": "open"}

static var _man = null
static var _tex = null
static var _folder := ""
static var _tile_px := 128.0
## The looks the world's painters ask for (`look`, `cell`): key -> {"tex", "src", "off", "size", "fp", "item"}; a miss is {} (kept, so it is asked once).
static var _looks = {}
## The ground atlases (`ground`): item id -> Array of Texture2D, one for each variant.
static var _grounds = {}


## Reads a manifest (default: the game's). A missing or broken file leaves an empty table: every descriptor is then a placeholder.
## The pictures are looked for in the folder `town` beside the manifest's own folder (assets/data/town_art.json -> assets/town/).
static func load_manifest(path: String = MANIFEST) -> void:
	_man = {}
	_tex = {}
	_looks = {}
	_grounds = {}
	_tile_px = 128.0
	_folder = path.get_base_dir().get_base_dir().path_join("town") + "/"
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed.get("items") is Array):
		return
	_tile_px = float(parsed.get("tile_px", 128.0))
	for it in parsed.items:
		if it is Dictionary and it.has("id"):
			_man[String(it.id)] = it
	# WORLD3: the street, yard and room props of tools/make_town_life.py (assets/data/town_art_life.json: the schema of this manifest, 64 px to the tile, and `append` for an item the kit has)
	var life_path := path.get_base_dir().path_join("town_art_life.json")
	if FileAccess.file_exists(life_path):
		var life = JSON.parse_string(FileAccess.get_file_as_string(life_path))
		if life is Dictionary:
			for it in life.get("items", []):
				if it is Dictionary and it.has("id"):
					_man[String(it.id)] = it
			for ap in life.get("append", []):
				if ap is Dictionary and _man.has(String(ap.get("id", ""))):
					var base: Dictionary = _man[String(ap.id)]
					var sps: Array = (base.get("sprites", []) as Array).duplicate()
					sps.append_array(ap.get("append_sprites", []))
					base["sprites"] = sps
					base["variants"] = int(ap.get("variants", base.get("variants", 1)))


## True when the manifest has this item (a test, and the caller that wants to know whether art exists).
static func has_item(id: String) -> bool:
	return _items().has(id)


static func _items() -> Dictionary:
	if _man == null:
		load_manifest()
	return _man


# ----------------------------------------------------------------- the lookups --

## The roof of a house of `kind` ("small", "medium", "terrace", "shop"); `variant` picks one of the kit's roofs (and shifts the placeholder's colour).
static func roof(kind: String, variant: int = 0) -> Dictionary:
	var k := maxi(0, ROOF_KINDS.find(kind))
	var item := _find(["roof_" + kind, "roof"])
	if item.is_empty():
		item = _find([ROOF_ITEMS[(k + variant) % 3], ROOF_ITEMS[(k + variant + 1) % 3], ROOF_ITEMS[(k + variant + 2) % 3]])
	var base: Color = ROOF_COLORS[k]
	var shift := float((variant % 3) - 1) * 0.07
	var col := base.lightened(shift) if shift >= 0.0 else base.darkened(-shift)
	var d := _describe(item, "", "", variant, col, Vector2(1, 1))
	if not d.placeholder and item.has("slopes"):
		d["tiles"] = _roof_tiles(item, col)
	return d


## A door: `kind` "front", "interior" or "garage"; `facing` the side the outside is on ("s", "w", "n", "e"); `state` "closed", "open" or "broken".
static func door(kind: String, facing: String = "s", state: String = "closed", variant: int = 0) -> Dictionary:
	var id := "door_" + kind
	var size: Vector2 = SIZES.get(id, Vector2(1, 1))
	return _describe(_find([id]), facing, state, variant, _color_of(id), size)


## A piece of the fortification of the base (WP5 asks): `kit` "fence", "fence_strong" (one cell of the line, straight along x), "sandbags", "gate", "door_plank", "tower", "floodlight"; `state` "built",
## "ghost" (a plan not yet built, drawn see-through) or "damaged" ("broken" is the same). Whole lines are drawn by `fort_cell` (the cell for each mask of connected sides); the built pieces of the base are
## drawn by scripts/render/perimeter_view.gd.
static func fence(kit: String, state: String = "built") -> Dictionary:
	var damaged := state == "damaged" or state == "broken"
	var color := _color_of(kit)
	var d: Dictionary
	if FORT_LINES.has(kit):
		d = _cell_desc(String(FORT_LINES[kit]) + ("damaged" if damaged else "built"), "10", color)
	else:
		var id := String({"gate": "fort_gate", "tower": "fort_tower", "floodlight": "floodlight", "door_plank": "barricade_door"}.get(kit, "fence_" + kit))
		d = _describe(_find([id, "fence_" + kit, kit]), "h", "closed" if kit == "gate" else "", 1 if damaged else 0, color, Vector2(1, 1))
	if state == "ghost":
		d.color = Color(d.color.r, d.color.g, d.color.b, 0.45)
	return d


## The descriptor (the older shape, see the header) of one cell of an atlas item: its picture, the cell's rectangle, a footprint of one tile.
static func _cell_desc(id: String, key: String, color: Color) -> Dictionary:
	var item := _find([id])
	if item.is_empty() or not item.get("cells", {}).has(key) or item.sprites.is_empty():
		return _flat(color, Vector2(1, 1))
	var sp: Dictionary = item.sprites[0]
	var cp: Array = item.get("cell_px", [_tile_px, _tile_px])
	var c: Array = item.cells[key]
	var r: Array = sp.get("rect", [0, 0, 0, 0])
	var d := _flat(color, Vector2(1, 1))
	d.item = id
	d.file = _folder + String(sp.file)
	d.rect = Rect2(float(r[0]) + float(c[0]) * float(cp[0]), float(r[1]) + float(c[1]) * float(cp[1]), float(cp[0]), float(cp[1]))
	d.anchor = Vector2(float((item.get("anchor", [0, 0]) as Array)[0]), float((item.get("anchor", [0, 0]) as Array)[1]))
	d.placeholder = false
	return d


## One sprite of a kit item by its manifest id (the perimeter view's: "fort_gate", "fort_tower", "floodlight", "barricade_door"...): `orient` "h" or "v" (or a facing),
## `state` "closed", "open" or "", `variant` 0 built, 1 damaged. A missing item is a flat colour of `size` tiles.
static func piece(id: String, orient: String = "", state: String = "", variant: int = 0, size: Vector2 = Vector2(1, 1)) -> Dictionary:
	return _describe(_find([id]), orient, state, variant, _color_of(id), size)


## An autotile atlas of the kit (a fence, sandbags...) by its manifest id: {"item", "file", "cell": Vector2 (px), "cols", "placeholder", "color"}; a missing item is a
## placeholder. `atlas_rect(d, mask)` is the part of the picture for a mask of the CONNECTED sides (N 1, E 2, S 4, W 8).
static func atlas(id: String) -> Dictionary:
	var item := _find([id])
	var d := {"item": "", "file": "", "cell": Vector2(128, 128), "cols": 4, "cells": {}, "placeholder": true, "color": _color_of(id)}
	if item.is_empty() or item.get("sprites", []).is_empty():
		return d
	var cell: Array = item.get("cell_px", [128, 128])
	d.item = id
	d.file = _folder + String(item.sprites[0].file)
	d.cell = Vector2(float(cell[0]), float(cell[1]))
	d.cols = int(item.get("grid", [4, 4])[0])
	d.cells = item.get("cells", {})
	d.placeholder = false
	return d


static func atlas_rect(d: Dictionary, mask: int) -> Rect2:
	var cell: Vector2 = d.cell
	var at = d.cells.get(str(mask))
	var col: int = int(at[0]) if at is Array else mask % int(d.cols)
	var row: int = int(at[1]) if at is Array else mask / int(d.cols)
	return Rect2(float(col) * cell.x, float(row) * cell.y, cell.x, cell.y)


## A piece of furniture or a marker by its kind ("bed", "stash", "radio", "bench", a container's kind...): `state` "" or "open" (a looted container),
## `facing` "s", "w", "n", "e".
static func prop(kind: String, state: String = "", facing: String = "s") -> Dictionary:
	var size: Vector2 = SIZES.get(kind, Vector2(1, 1))
	# (the base's props go by the kit's names first: the layout's "bench" is the kit's workbench, not the garden bench)
	var ids: Array = []
	ids.append_array(PROP_ALIAS.get(kind, []))
	ids.append(kind)
	if KIND_ALIAS.has(kind):
		ids.append(KIND_ALIAS[kind])
	return _describe(_find(ids), facing, state, 0, _color_of(kind), size)


# --------------------------------------------------------------------- drawing --

## The picture of a descriptor, or null for a placeholder or a picture that will not load.
static func texture(d: Dictionary) -> Texture2D:
	var file := String(d.get("file", ""))
	if file == "":
		return null
	return _load(file)


## A picture by its path (cached; a path that will not load is null, and is not tried again).
static func _load(file: String) -> Texture2D:
	if _tex == null:
		_tex = {}
	if _tex.has(file):
		return _tex[file]
	var tex: Texture2D = null
	if ResourceLoader.exists(file):
		tex = load(file) as Texture2D
	elif FileAccess.file_exists(file):
		var img := Image.load_from_file(file)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_tex[file] = tex
	return tex


## Draws a descriptor into `rect` (pixels of the canvas item). Returns true when a picture was drawn, false when it was only the flat colour.
static func draw(ci: CanvasItem, d: Dictionary, rect: Rect2, tint: Color = Color.WHITE) -> bool:
	var tex := texture(d)
	var src: Rect2 = d.get("rect", Rect2())
	if tex == null:
		ci.draw_rect(rect, Color(d.color) * tint)
		return false
	if src.size.x <= 0.0:
		src = Rect2(Vector2.ZERO, tex.get_size())
	# a picture with an anchor (the soft shadow and the rim of a prop lie outside its footprint): `rect` is the footprint, the picture is laid round it
	var anchor: Vector2 = d.get("anchor", Vector2.ZERO)
	var fp: Vector2 = d.get("size", Vector2.ZERO)
	if anchor != Vector2.ZERO and fp.x > 0.0 and fp.y > 0.0:
		var u := Vector2(rect.size.x / fp.x, rect.size.y / fp.y)
		rect = Rect2(rect.position - anchor * u, (src.size / _tile_px) * u)
	var nine: Array = d.get("nine", [])
	if nine.size() == 4:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.region_rect = src
		sb.texture_margin_left = float(nine[0])
		sb.texture_margin_top = float(nine[1])
		sb.texture_margin_right = float(nine[2])
		sb.texture_margin_bottom = float(nine[3])
		sb.modulate_color = tint
		ci.draw_style_box(sb, rect)
		return true
	ci.draw_texture_rect_region(tex, rect, src, tint)
	return true


# ------------------------------------------------------------ the world's lookups --
# The painters of the town's ground, walls and things (scripts/town/town_world.gd, town_chunk_paint.gd) draw by the thousand and ask here once for each look: the answer is
# a cached Dictionary {"tex": Texture2D, "src": Rect2 (the part of the picture, in its pixels), "off": Vector2 (screen pixels: where the picture's top left lies relative to
# the top left of the thing's footprint, so the anchor), "size": Vector2 (the picture's size on the screen, in pixels at the game's tile), "fp": Vector2 (the footprint in
# tiles), "item": the item's id}; a missing item or a picture that will not load is {} (the caller then draws nothing or its own flat shape).

## Items whose picture is centred on the middle of the footprint instead of laid by the anchor (a wreck lies at an angle across its footprint).
const CENTERED := ["car_wreck"]
## The kit's ground atlases the world's ground is made of, in the order of the codes the generator writes in `data.kit.ground` (code = index + 1; 0 means "by the terrain"),
## the materials of the wall tops (`data.kit.wall`, code = index; 0 none) and the lines of fence and hedge (`data.kit.line`).
const GROUNDS := ["lawn", "asphalt", "sidewalk", "dirt_path", "gravel", "floor_wood", "floor_hall", "floor_kitchen", "floor_carpet", "floor_bath", "floor_runner_h", "floor_runner_v"]
const WALL_MATS := ["", "wall_brick", "wall_white", "wall_blue", "wall_stucco", "wall_sage", "wall_timber", "wall_plaster"]
const LINES := ["", "fence_picket_white", "fence_picket_brown", "fence_chainlink", "wall_low_brick", "hedge", "fence_wire", "fence_privacy", "fence_rail", "hedge_wild", "wall_stone"]
## The floor of a room by its name (the kit's ground ids), and the floors of the shop and of the doorways.
const FLOOR_OF_ROOM := {
	"living room": "floor_wood", "front room": "floor_wood", "bedroom": "floor_carpet", "side": "floor_wood", "kitchen": "floor_kitchen", "bathroom": "floor_bath",
	"shop floor": "floor_kitchen", "storeroom": "floor_hall", "hall": "floor_hall",
}
## The kit's fortification lines: the base kit's art id ("fence", "fence_strong", "sandbags") and a look ("built", "damaged") to the item that holds the cells.
const FORT_LINES := {"fence": "fort_fence_wood_", "fence_strong": "fort_fence_reinforced_", "sandbags": "sandbags_"}
## What a container's kind (the generator's, for the sim: "fridge", "kitchen counter" as "kitchen_counter") is drawn as when the kit has no item of that name.
const KIND_ALIAS := {"cabinet": "cupboard", "shelf": "shelf_tins", "counter": "kitchen_counter", "trunk": "crate", "locker": "wardrobe"}


## The look of a thing of the kit: `id` the item, `facing` ("s", "w", "n", "e" or an orient "h", "v"), `state`, `variant` (taken modulo the item's variants).
static func look(id: String, facing: String = "", state: String = "", variant: int = 0) -> Dictionary:
	if _looks == null:
		_looks = {}
	var key := "%s|%s|%s|%d" % [id, facing, state, variant]
	if _looks.has(key):
		return _looks[key]
	var out := {}
	var item := _find([id])
	if not item.is_empty():
		var sp := _pick(item, facing, state, variant)
		if not sp.is_empty():
			out = _look_of(item, sp)
	_looks[key] = out
	return out


## The look of one cell of an atlas item (an autotile set or a set of overlays): `key` is the name of the cell (the manifest's `cells`: "0".."15", "n", "double_h"...).
static func cell(id: String, key: String) -> Dictionary:
	if _looks == null:
		_looks = {}
	var ck := "%s#%s" % [id, key]
	if _looks.has(ck):
		return _looks[ck]
	var out := {}
	var item := _find([id])
	if not item.is_empty() and item.get("cells", {}).has(key) and not item.sprites.is_empty():
		var sp: Dictionary = item.sprites[0]
		var cp: Array = item.get("cell_px", [_tile_px, _tile_px])
		var c: Array = item.cells[key]
		var r: Array = sp.get("rect", [0, 0, 0, 0])
		var tex := _load(_folder + String(sp.file))
		if tex != null:
			var anchor: Array = item.get("anchor", [0, 0])
			var k := float(GD.TILE) / _tile_px
			out = {"tex": tex, "src": Rect2(float(r[0]) + float(c[0]) * float(cp[0]), float(r[1]) + float(c[1]) * float(cp[1]), float(cp[0]), float(cp[1])),
				"off": -Vector2(float(anchor[0]), float(anchor[1])) * float(GD.TILE), "size": Vector2(float(cp[0]), float(cp[1])) * k, "fp": Vector2.ONE, "item": id}
	_looks[ck] = out
	return out


## The pictures of a ground item (an atlas of 4 x 4 pieces, one picture for each variant), in the order of its variants; [] when the kit has no such item.
static func ground(id: String) -> Array:
	if _grounds == null:
		_grounds = {}
	if _grounds.has(id):
		return _grounds[id]
	var out: Array = []
	var item := _find([id])
	for sp in item.get("sprites", []):
		var tex := _load(_folder + String(sp.file))
		if tex == null:
			out.clear()
			break
		out.append(tex)
	_grounds[id] = out
	return out


## The look of a sprite of an item with its picture loaded: see the header of this section.
static func _look_of(item: Dictionary, sp: Dictionary) -> Dictionary:
	var tex := _load(_folder + String(sp.file))
	if tex == null:
		return {}
	var r: Array = sp.get("rect", [0, 0, tex.get_width(), tex.get_height()])
	var src := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var fp: Array = sp.get("fp", item.get("footprint", [1, 1]))
	var anchor: Array = item.get("anchor", [0, 0])
	# (WORLD3: the life items are drawn at 64 px to the tile, an item or a sprite says so)
	var k := float(GD.TILE) / float(sp.get("tile_px", item.get("tile_px", _tile_px)))
	var size := src.size * k
	var off := -Vector2(float(anchor[0]), float(anchor[1])) * float(GD.TILE)
	if String(item.id) in CENTERED:
		off = (Vector2(float(fp[0]), float(fp[1])) * float(GD.TILE) - size) * 0.5
	return {"tex": tex, "src": src, "off": off, "size": size, "fp": Vector2(float(fp[0]), float(fp[1])), "item": String(item.id)}


## The number of variants of an item (1 when it has none or is not in the kit).
static func variants_of(id: String) -> int:
	return maxi(1, int(_find([id]).get("variants", 1)))


## The kit item a container's kind stands for: the kind itself ("fridge", "kitchen_counter" for "kitchen counter"), else its alias; "" when the kit has none.
static func item_of_kind(kind: String) -> String:
	var id := kind.replace(" ", "_")
	if _items().has(id):
		return id
	var alias := String(KIND_ALIAS.get(id, ""))
	return alias if _items().has(alias) else ""


## One cell of a fortification line of the base's kit (`kit` "fence", "fence_strong", "sandbags"; `look` "built" or "damaged"; `mask` the connected sides N 1, E 2, S 4, W 8).
static func fort_cell(kit: String, look_name: String, mask: int) -> Dictionary:
	return cell(String(FORT_LINES.get(kit, "fort_fence_wood_")) + ("damaged" if look_name != "built" else "built"), str(mask))


# ------------------------------------------------------------------- internals --

static func _find(ids: Array) -> Dictionary:
	var items := _items()
	for id in ids:
		if items.has(id):
			return items[id]
	return {}


static func _color_of(id: String) -> Color:
	if COLORS.has(id):
		return COLORS[id]
	var head := id.get_slice("_", 0)
	return COLORS.get(head, FALLBACK_COLOR)


static func _describe(item: Dictionary, facing: String, state: String, variant: int, color: Color, size: Vector2) -> Dictionary:
	if item.is_empty():
		return _flat(color, size)
	var sp := _pick(item, facing, state, variant)
	if sp.is_empty():
		return _flat(color, size)
	return _of_sprite(item, sp, color, size)


static func _flat(color: Color, size: Vector2) -> Dictionary:
	return {"item": "", "file": "", "rect": Rect2(), "nine": [], "size": size, "anchor": Vector2.ZERO, "color": color, "placeholder": true}


## The descriptor of one sprite of an item (its picture, the part of it, its size and anchor in tiles).
static func _of_sprite(item: Dictionary, sp: Dictionary, color: Color, size: Vector2) -> Dictionary:
	var d := _flat(color, size)
	var fp: Array = sp.get("fp", item.get("footprint", [size.x, size.y]))
	var anchor: Array = item.get("anchor", [0, 0])
	d.item = String(item.id)
	d.file = _folder + String(sp.file)
	if sp.has("rect"):
		var r: Array = sp.rect
		d.rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	else:
		var px: Array = sp.get("px", [0, 0])
		d.rect = Rect2(0.0, 0.0, float(px[0]), float(px[1]))
	d.nine = sp.get("nine", [])
	d.size = Vector2(float(fp[0]), float(fp[1]))
	d.anchor = Vector2(float(anchor[0]), float(anchor[1]))
	d.placeholder = false
	return d


## The tiles of a roof kit: {"lit": [a, b], "shade": [a, b], "ridge": {"h": d, "v": d}, "edge": {a descriptor of the whole eave sheet, "cell": Vector2 px, "cols": n}}.
static func _roof_tiles(item: Dictionary, color: Color) -> Dictionary:
	var out := {"lit": [], "shade": [], "ridge": {}, "edge": {}}
	var one := Vector2(1, 1)
	for slope in ["lit", "shade"]:
		for v in 2:
			var best: Dictionary = {}
			for sp in item.sprites:
				if String(sp.get("slope", "")) == slope and int(sp.get("variant", 0)) == v:
					best = sp
			if best.is_empty():
				for sp in item.sprites:
					if String(sp.get("slope", "")) == slope:
						best = sp
						break
			out[slope].append(_of_sprite(item, best, color, one) if not best.is_empty() else _flat(color, one))
	for sp in item.get("ridge", []):
		out.ridge[String(sp.get("orient", "h"))] = _of_sprite(item, sp, color, one)
	var edge := _find([String(item.get("edges", ""))])
	if not edge.is_empty() and not edge.sprites.is_empty():
		var e := _of_sprite(edge, edge.sprites[0], color, one)
		var cell: Array = edge.get("cell_px", [224, 224])
		e["cell"] = Vector2(float(cell[0]), float(cell[1]))
		e["cols"] = int(edge.get("grid", [4, 4])[0])
		out.edge = e
	return out


## The sprite of an item that fits best: the facing, the state and the variant asked for count in that order (a sprite that names none of them fits any).
static func _pick(item: Dictionary, facing: String, state: String, variant: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	var want_v := variant % maxi(1, int(item.get("variants", 1)))
	var state_b := String(STATE_ALIAS.get(state, ""))
	for sp in item.get("sprites", []):
		var score := 0.0
		var f := String(sp.get("facing", sp.get("orient", "")))
		if f == facing and facing != "":
			score += 4.0
		elif f == "":
			score += 1.0
		var st := String(sp.get("state", ""))
		if state != "" and (st == state or st == state_b):
			score += 2.0
		elif st == "":
			score += 0.5
		if sp.has("variant"):
			if int(sp.variant) == want_v:
				score += 1.0
		else:
			score += 0.5
		if score > best_score:
			best_score = score
			best = sp
	return best
