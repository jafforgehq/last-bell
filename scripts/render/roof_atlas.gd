## The pictures of the town's roofs in ONE texture (One House, WP9; WORLD3 made it one for all three roof kits and added the extras): a roof of the art kit is a grid of 128 px cells in four fill pictures
## (lit and shade, two variants each), a ridge cap and an eave sheet: seven pictures a kit. Drawn from the files, thirty roofs in view were 160 draw calls; from one atlas the cells of a roof are one batch,
## and since WORLD3 every roof is: the three kits, the eave sheet they share, the kit's chimneys and the ROOF EXTRAS (tools/make_roof_extras.py: the fills of flat, glass, metal, charred and
## collapsed roofs, tarps, the parapet of a flat roof, the things that stand on a roof, the awnings, porches and canopies of a front, the signs) are all in this one picture, so a street of roofs
## of any kit, style and colour is one batch.
##
## Layout (pixels, 2048 wide): the eave sheet at (0, 0), the pieces of the three kits under it in shelves, each in a cell with PAD pixels all round that are the piece's own opposite edge (the fills are
## seamless, so a linear or mipmap sample at a seam sees the same picture and nothing bleeds in from the next piece); the extras' sheet on the right (it carries its own padding); the chimneys.
## `for_tiles(tiles)` (the `tiles` of `TownArt.roof`) gives {"tex": ImageTexture, "place": {part key: the piece's top left in the atlas}, "extra": {name: Rect2 in the atlas}, "etiles": {name: Vector2
## (its size in tiles)}} or null when a picture will not load; `rect_for(set, d, src)` turns a source rectangle of the descriptor's own picture into the atlas'; `extra(set, name)` the rectangle of an
## extra. Made once, on the first ask.
extends RefCounted

const TownArt := preload("res://scripts/town/town_art.gd")

const PAD := 8
const WIDTH := 2048
const EXTRAS_PNG := "res://assets/town/roof/roof_extras.png"
const EXTRAS_JSON := "res://assets/data/roof_extras.json"

var _all = null
var _tried := false
var _pre: Dictionary = {}
var _sets := {}


## The atlas of the roof kit `tiles` belongs to (null when it cannot be made: the caller then draws from the files).
func for_tiles(tiles: Dictionary):
	var lit: Array = tiles.get("lit", [])
	if lit.is_empty():
		return null
	var key := String(lit[0].get("file", ""))
	if key == "":
		return null
	if not _tried:
		_tried = true
		_all = _build_all()
	if _all != null and _all.place.has(part_key(lit[0])):
		return _all
	# (a kit that is not one of the game's three: its own atlas, as before)
	if not _sets.has(key):
		_sets[key] = _build(tiles)
	return _sets[key]


static func part_key(d: Dictionary) -> String:
	return "%s|%s" % [String(d.get("file", "")), str(d.get("rect", Rect2()))]


## `src` (a rectangle of the picture `d` names) in the atlas' pixels.
static func rect_for(set: Dictionary, d: Dictionary, src: Rect2) -> Rect2:
	var origin: Vector2 = set.place[part_key(d)]
	return Rect2(origin + (src.position - Rect2(d.get("rect", Rect2())).position), src.size)


## The rectangle of an extra in the atlas (an empty Rect2 when the atlas has none by that name).
static func extra(set: Dictionary, name: String) -> Rect2:
	var e: Dictionary = set.get("extra", {})
	return e.get(name, Rect2())


## Whether the atlas has extras (a roof of a style that needs them is a gable when it has none).
static func has_extras(set: Dictionary) -> bool:
	return not (set.get("extra", {}) as Dictionary).is_empty()


func _image_of(d: Dictionary) -> Image:
	var tex := TownArt.texture(d)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## The one atlas: the three kits of `TownArt.roof("", 0..2)`, their shared eave sheet, the chimneys and the extras.
## The atlas in two steps (the loading card makes them in two frames, scripts/render/roof_warm.gd): `prepare()` the pictures of the kits (about 20 ms), and the first ask of `for_tiles` the rest
## (the extras' sheet, the chimneys, the sheet itself: about 20 ms). Asked for with no `prepare()`, `for_tiles` does both.
func prepare() -> void:
	if _pre.is_empty() and not _tried:
		_pre = _kit_pictures()


## The first step: the three kits' pieces cut out of their pictures, and the eave sheet ({} when a picture will not load).
func _kit_pictures() -> Dictionary:
	var kits: Array = []
	for i in 3:
		var t = TownArt.roof("", i).get("tiles")
		if not (t is Dictionary) or (t.get("lit", []) as Array).is_empty() or (t.get("edge", {}) as Dictionary).is_empty():
			return {}
		kits.append(t)
	# the pieces of every kit, each once
	var parts: Array = []
	var seen := {}
	for t in kits:
		for d in [t.lit[0], t.lit[1], t.shade[0], t.shade[1]] + t.get("ridge", {}).values():
			if not seen.has(part_key(d)):
				seen[part_key(d)] = true
				parts.append(d)
	var sources := {}
	var images: Array = []
	for d in parts:
		var file := String(d.file)
		if not sources.has(file):
			sources[file] = _image_of(d)
		if sources[file] == null:
			return {}
		images.append((sources[file] as Image).get_region(Rect2i(Rect2(d.rect))))
	# (the eave sheet of the first kit stands for all three: they differ by a shade of the fascia)
	var edge: Dictionary = kits[1].edge
	var edge_img: Image = _image_of(edge)
	if edge_img == null:
		return {}
	return {"kits": kits, "parts": parts, "images": images, "edge": edge, "edge_img": edge_img, "edge_size": Vector2i(Rect2(edge.rect).size)}


func _build_all():
	var pre: Dictionary = _pre if not _pre.is_empty() else _kit_pictures()
	_pre = {}
	if pre.is_empty():
		return null
	var kits: Array = pre.kits
	var parts: Array = pre.parts
	var images: Array = pre.images
	var edge: Dictionary = pre.edge
	var edge_img: Image = pre.edge_img
	var edge_size: Vector2i = pre.edge_size
	var extras_img: Image = null
	var extras_meta: Dictionary = {}
	if ResourceLoader.exists(EXTRAS_PNG) and FileAccess.file_exists(EXTRAS_JSON):
		var tex := load(EXTRAS_PNG) as Texture2D
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(EXTRAS_JSON))
		if tex != null and parsed is Dictionary:
			extras_img = tex.get_image()
			if extras_img != null and not extras_img.is_empty():
				if extras_img.is_compressed():
					extras_img.decompress()
				if extras_img.get_format() != Image.FORMAT_RGBA8:
					extras_img.convert(Image.FORMAT_RGBA8)
				extras_meta = parsed.get("pieces", {})
			else:
				extras_img = null
	# the shelves under the eave sheet
	var top := edge_size.x + PAD
	var x := 0
	var y := top
	var row_h := 0
	var spots: Array = []
	var left_w := WIDTH - (extras_img.get_width() if extras_img != null else 0)
	for im in images:
		var w := (im as Image).get_width() + 2 * PAD
		var h := (im as Image).get_height() + 2 * PAD
		if x + w > left_w:
			x = 0
			y += row_h
			row_h = 0
		spots.append(Vector2i(x, y))
		x += w
		row_h = maxi(row_h, h)
	var chim_at := Vector2i(0, y + row_h)
	var chimneys: Array = []
	for v in 2:
		var look: Dictionary = TownArt.look("chimney", "", "", v)
		if look.is_empty():
			continue
		var ctex: Texture2D = look.tex
		var full := ctex.get_image()
		if full == null or full.is_empty():
			continue
		if full.is_compressed():
			full.decompress()
		if full.get_format() != Image.FORMAT_RGBA8:
			full.convert(Image.FORMAT_RGBA8)
		var sr := Rect2i(Rect2(look.src))
		chimneys.append({"img": full.get_region(sr), "tiles": Vector2(look.size) / 64.0, "v": v})
	var cx := chim_at.x
	var chim_spots: Array = []
	var chim_h := 0
	for c in chimneys:
		var ci: Image = c.img
		chim_spots.append(Vector2i(cx, chim_at.y))
		cx += ci.get_width() + 2 * PAD
		chim_h = maxi(chim_h, ci.get_height() + 2 * PAD)
	var h_all := maxi(chim_at.y + chim_h, extras_img.get_height() if extras_img != null else 0)
	var atlas := Image.create_empty(WIDTH, h_all, false, Image.FORMAT_RGBA8)
	var place := {}
	atlas.blit_rect(edge_img, Rect2i(Rect2(edge.rect)), Vector2i.ZERO)
	for t in kits:
		place[part_key(t.edge)] = Vector2.ZERO
	for i in parts.size():
		_blit_padded(atlas, images[i], spots[i])
		place[part_key(parts[i])] = Vector2(spots[i] + Vector2i(PAD, PAD))
	var extra := {}
	var etiles := {}
	for i in chimneys.size():
		_blit_padded(atlas, chimneys[i].img, chim_spots[i])
		var cimg2: Image = chimneys[i].img
		extra["chimney_%d" % int(chimneys[i].v)] = Rect2(Vector2(chim_spots[i] + Vector2i(PAD, PAD)), Vector2(cimg2.get_size()))
		etiles["chimney_%d" % int(chimneys[i].v)] = chimneys[i].tiles
	if extras_img != null:
		var ox := WIDTH - extras_img.get_width()
		atlas.blit_rect(extras_img, Rect2i(0, 0, extras_img.get_width(), extras_img.get_height()), Vector2i(ox, 0))
		for name in extras_meta:
			var m: Dictionary = extras_meta[name]
			var r: Array = m.rect
			extra[String(name)] = Rect2(float(r[0] + ox), float(r[1]), float(r[2]), float(r[3]))
			var tl: Array = m.tiles
			etiles[String(name)] = Vector2(float(tl[0]), float(tl[1]))
	atlas.generate_mipmaps()
	return {"tex": ImageTexture.create_from_image(atlas), "place": place, "size": Vector2i(WIDTH, h_all), "extra": extra, "etiles": etiles}


## One kit on its own (a fixture of a test, a kit that is not the game's): the pieces in a grid, the eave sheet to the left of them, no extras.
func _build(tiles: Dictionary):
	var edge: Dictionary = tiles.get("edge", {})
	var parts: Array = []
	var seen := {}
	for d in [tiles.lit[0], tiles.lit[1], tiles.shade[0], tiles.shade[1]] + tiles.get("ridge", {}).values():
		if not seen.has(part_key(d)):
			seen[part_key(d)] = true
			parts.append(d)
	var sources := {}
	var edge_size := Vector2i.ZERO
	var edge_img: Image = null
	if not edge.is_empty():
		edge_img = _image_of(edge)
		if edge_img == null:
			return null
		edge_size = Vector2i(Rect2(edge.rect).size)
	var cell := 0
	for d in parts:
		var file := String(d.file)
		if not sources.has(file):
			sources[file] = _image_of(d)
		if sources[file] == null:
			return null
		cell = maxi(cell, int(Rect2(d.rect).size.x))
		cell = maxi(cell, int(Rect2(d.rect).size.y))
	var slot := cell + 2 * PAD
	var cols := 2
	var rows := ceili(float(parts.size()) / float(cols))
	var w := edge_size.x + cols * slot
	var h := maxi(edge_size.y, rows * slot)
	var atlas := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var place := {}
	if edge_img != null:
		atlas.blit_rect(edge_img, Rect2i(Rect2(edge.rect)), Vector2i.ZERO)
		place[part_key(edge)] = Vector2.ZERO
	for i in parts.size():
		var d: Dictionary = parts[i]
		var r := Rect2i(Rect2(d.rect))
		var piece: Image = (sources[String(d.file)] as Image).get_region(r)
		var at := Vector2i(edge_size.x + (i % cols) * slot, floori(float(i) / float(cols)) * slot)
		_blit_padded(atlas, piece, at)
		place[part_key(d)] = Vector2(at + Vector2i(PAD, PAD))
	atlas.generate_mipmaps()
	return {"tex": ImageTexture.create_from_image(atlas), "place": place, "size": Vector2i(w, h), "extra": {}, "etiles": {}}


## The piece at `at + (PAD, PAD)` with its own opposite edges round it.
func _blit_padded(atlas: Image, piece: Image, at: Vector2i) -> void:
	var pw := piece.get_width()
	var ph := piece.get_height()
	var p := mini(PAD, mini(pw, ph))
	atlas.blit_rect(piece, Rect2i(0, 0, pw, ph), at + Vector2i(PAD, PAD))
	atlas.blit_rect(piece, Rect2i(0, ph - p, pw, p), at + Vector2i(PAD, PAD - p))
	atlas.blit_rect(piece, Rect2i(0, 0, pw, p), at + Vector2i(PAD, PAD + ph))
	atlas.blit_rect(piece, Rect2i(pw - p, 0, p, ph), at + Vector2i(PAD - p, PAD))
	atlas.blit_rect(piece, Rect2i(0, 0, p, ph), at + Vector2i(PAD + pw, PAD))
	atlas.blit_rect(piece, Rect2i(pw - p, ph - p, p, p), at + Vector2i(PAD - p, PAD - p))
	atlas.blit_rect(piece, Rect2i(0, ph - p, p, p), at + Vector2i(PAD + pw, PAD - p))
	atlas.blit_rect(piece, Rect2i(pw - p, 0, p, p), at + Vector2i(PAD - p, PAD + ph))
	atlas.blit_rect(piece, Rect2i(0, 0, p, p), at + Vector2i(PAD + pw, PAD + ph))
