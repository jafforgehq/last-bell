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


## Reads a manifest (default: the game's). A missing or broken file leaves an empty table: every descriptor is then a placeholder.
## The pictures are looked for in the folder `town` beside the manifest's own folder (assets/data/town_art.json -> assets/town/).
static func load_manifest(path: String = MANIFEST) -> void:
	_man = {}
	_tex = {}
	_folder = path.get_base_dir().get_base_dir().path_join("town") + "/"
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed.get("items") is Array):
		return
	for it in parsed.items:
		if it is Dictionary and it.has("id"):
			_man[String(it.id)] = it


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


## A piece of the fortification of the base (WP5 asks): `kit` "fence", "fence_strong", "gate", "door_plank", "tower", "floodlight"; `state` "built", "ghost"
## (a plan not yet built, drawn see-through) or "broken".
static func fence(kit: String, state: String = "built") -> Dictionary:
	var item := _find(["fence_" + kit, kit, "fence"])
	var d := _describe(item, "", "ghost" if state == "ghost" else state, 0, _color_of(kit), Vector2(1, 1))
	if state == "ghost":
		d.color = Color(d.color.r, d.color.g, d.color.b, 0.45)
	return d


## A piece of furniture or a marker by its kind ("bed", "stash", "radio", "bench", a container's kind...): `state` "" or "open" (a looted container),
## `facing` "s", "w", "n", "e".
static func prop(kind: String, state: String = "", facing: String = "s") -> Dictionary:
	var size: Vector2 = SIZES.get(kind, Vector2(1, 1))
	var ids: Array = [kind]
	ids.append_array(PROP_ALIAS.get(kind, []))
	return _describe(_find(ids), facing, state, 0, _color_of(kind), size)


# --------------------------------------------------------------------- drawing --

## The picture of a descriptor, or null for a placeholder or a picture that will not load.
static func texture(d: Dictionary) -> Texture2D:
	var file := String(d.get("file", ""))
	if file == "":
		return null
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
