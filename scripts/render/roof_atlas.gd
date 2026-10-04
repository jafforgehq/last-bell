## The pictures of one roof kit in ONE texture (One House, WP9): a roof of the art kit is a grid of 128 px cells in four fill pictures (lit and shade, two variants each), a ridge
## cap and an eave sheet: seven pictures, so a roof drawn from the files is five or six draw batches, and thirty roofs in view are 160 draw calls. From one atlas they are one batch
## each (the cells of a roof are all the same texture), so a roof is one draw call.
##
## Layout (pixels): the eave sheet as it is at (0, 0); to the right of it the 128 px pieces (the fills and the ridge caps), each in a cell with PAD pixels all round that are the
## piece's own opposite edge (the fills are seamless, so a linear or mipmap sample at a seam sees the same picture and nothing bleeds in from the next piece).
## `for_tiles(tiles)` (the `tiles` of `TownArt.roof`) gives {"tex": ImageTexture, "place": {part key: the piece's top left in the atlas}} or null when a picture will not load;
## `rect_for(set, d, src)` turns a source rectangle of the descriptor's own picture into the atlas'. Made once for each kit, on the first ask.
extends RefCounted

const TownArt := preload("res://scripts/town/town_art.gd")

const PAD := 8

var _sets := {}


## The atlas of the roof kit `tiles` belongs to (null when it cannot be made: the caller then draws from the files).
func for_tiles(tiles: Dictionary):
	var lit: Array = tiles.get("lit", [])
	if lit.is_empty():
		return null
	var key := String(lit[0].get("file", ""))
	if key == "":
		return null
	if not _sets.has(key):
		_sets[key] = _build(tiles)
	return _sets[key]


static func part_key(d: Dictionary) -> String:
	return "%s|%s" % [String(d.get("file", "")), str(d.get("rect", Rect2()))]


## `src` (a rectangle of the picture `d` names) in the atlas' pixels.
static func rect_for(set: Dictionary, d: Dictionary, src: Rect2) -> Rect2:
	var origin: Vector2 = set.place[part_key(d)]
	return Rect2(origin + (src.position - Rect2(d.get("rect", Rect2())).position), src.size)


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
	return {"tex": ImageTexture.create_from_image(atlas), "place": place, "size": Vector2i(w, h)}


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
