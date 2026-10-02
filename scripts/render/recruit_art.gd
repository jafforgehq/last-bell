## Bodies for people who have no baked sprite. The six survivors' bodies (assets/pawns/<id>_S/E/N.png) were baked from
## the web version's drawing of a look; the recruits who come over the radio (scripts/sim/recruits.gd) are generated, so
## their bodies are made when they arrive: the baked person whose look is most like theirs is taken and the colours of
## that body (skin, hair, hat, beard, top, outer) are swapped for the colours of the recruit's look, keeping the shading
## and the dark outline. The legs and the hands are drawn live from the look as they are for anyone (pawn_art.gd).
## Pure functions of the data and the look: the same look makes the same body.
##
## A body's hair that is as dark as the outline (three of the six) cannot be told from it by colour, so it is left as it
## is; `base_for` takes that into account and lends a dark-haired body to a dark-haired look.
extends RefCounted

## What a baked body is made of: [the part, the look key that holds its colour, what a look without that key uses].
const PARTS := [
	["skin", "skin", ""],
	["hair", "hairColor", ""],
	["top", "top", ""],
	["outer", "outer", "top"],
	["hat", "hatColor", "outer"],
	["beard", "beardColor", "hairColor"],
]
## The dark line round every figure, and how near to it (in RGB, squared) a part's own colour may be before it is
## taken for the line and left alone.
const INK := Vector3(26.0, 20.0, 15.0)
const INK_NEAR_SQ := 1600.0
## A pixel this far (in RGB, squared) from every colour of the body is left alone (a highlight, a badge).
const REACH_SQ := 3600.0
const VIEWS := ["S", "E", "N"]
## Hair under this lightness (0 to 255) is dark.
const DARK_HAIR := 70.0


static func _rgb(hex: String) -> Vector3:
	var c := Color.html(hex)
	return Vector3(c.r * 255.0, c.g * 255.0, c.b * 255.0)


static func _lightness(hex: String) -> float:
	var c := _rgb(hex)
	return 0.299 * c.x + 0.587 * c.y + 0.114 * c.z


## The look of a baked person, by id (the roster's), or {}.
static func _look_of(data: Dictionary, id: String) -> Dictionary:
	for person in data.get("people", []):
		if String(person.get("id", "")) == id:
			return person.get("look", {})
	return {}


## The baked person whose body is most like what `look` describes: a hat for a hat, a beard for a beard, dark hair for
## dark hair, the same hair, top and outer styles, glasses; among those equally near, one the look's seed picks.
## "ruth" with no data.
static func base_for(data: Dictionary, look: Dictionary) -> String:
	var best := "ruth"
	var best_score := -1.0
	var files: Dictionary = data.get("pawn", {}).get("files", {})
	var dark: bool = _lightness(String(look.get("hairColor", "#3a2a20"))) < DARK_HAIR
	var i := 0
	for person in data.get("people", []):
		var id := String(person.get("id", ""))
		var bl: Dictionary = person.get("look", {})
		if not files.has(id):
			continue
		var score := 0.0
		score += 8.0 if bl.has("hat") == look.has("hat") else 0.0
		score += 2.0 if bl.has("beard") == look.has("beard") else 0.0
		score += 3.0 if (_lightness(String(bl.get("hairColor", "#000000"))) < DARK_HAIR) == dark else 0.0
		score += 3.0 if String(bl.get("hair", "")) == String(look.get("hair", "-")) else 0.0
		score += 2.0 if String(bl.get("topStyle", "")) == String(look.get("topStyle", "-")) else 0.0
		score += 2.0 if String(bl.get("outerStyle", "")) == String(look.get("outerStyle", "-")) else 0.0
		score += 1.0 if bool(bl.get("glasses", false)) == bool(look.get("glasses", false)) else 0.0
		score += float((int(look.get("seed", 0)) + i * 7) % 11) * 0.01
		if score > best_score:
			best_score = score
			best = id
		i += 1
	return best


## The three views of a recruit's body ({"S": Texture2D, "E": ..., "N": ...}): the body of `base` (one of the baked
## people; `base_for` says which) with its colours changed to the look's. A view that cannot be read is left out.
static func bodies(data: Dictionary, look: Dictionary, base: String) -> Dictionary:
	var out := {}
	var swaps := swaps_for(_look_of(data, base), look)
	for view in VIEWS:
		var path := String(data.get("pawn", {}).get("files", {}).get(base, {}).get(view, ""))
		var img := _image(path)
		if img != null:
			out[view] = ImageTexture.create_from_image(recolour(img, swaps))
	return out


## [{"from": Vector3, "to": Vector3}]: for each part of the baked body the look has a colour for, the colour it has
## and the one it is to have. A part as dark as the outline is not among them.
static func swaps_for(base_look: Dictionary, look: Dictionary) -> Array:
	var swaps: Array = []
	for part in PARTS:
		var base_key := String(part[1])
		if not base_look.has(base_key):
			continue
		var target := String(look.get(base_key, ""))
		if target == "" and String(part[2]) != "":
			target = String(look.get(String(part[2]), ""))
		if target == "":
			continue
		var from := _rgb(String(base_look[base_key]))
		if from.distance_squared_to(INK) < INK_NEAR_SQ:
			continue
		swaps.append({"from": from, "to": _rgb(target)})
	return swaps


static func _image(path: String) -> Image:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if not tex is Texture2D:
		return null
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


## `img` with each pixel that belongs to a part of the body moved from that part's colour to the new one (the same
## step away from it as before, so the shading and the highlights stay); transparent pixels and the outline are
## untouched.
static func recolour(img: Image, swaps: Array) -> Image:
	var used := img.get_used_rect()
	var w := img.get_width()
	var data := img.get_data()
	var memo := {}
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var i := (y * w + x) * 4
			if data[i + 3] < 8:
				continue
			var key: int = (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
			if not memo.has(key):
				memo[key] = _swapped(Vector3(data[i], data[i + 1], data[i + 2]), swaps)
			var c: Vector3 = memo[key]
			data[i] = int(c.x)
			data[i + 1] = int(c.y)
			data[i + 2] = int(c.z)
	return Image.create_from_data(w, img.get_height(), false, Image.FORMAT_RGBA8, data)


static func _swapped(c: Vector3, swaps: Array) -> Vector3:
	# the part this colour is nearest to (the outline counts as a part that does not change)
	var best_d := c.distance_squared_to(INK)
	var best = null
	for s in swaps:
		var d := c.distance_squared_to(s.from)
		if d < best_d and d < REACH_SQ:
			best_d = d
			best = s
	if best == null:
		return c
	var moved: Vector3 = best.to + (c - best.from)
	return Vector3(clampf(moved.x, 0.0, 255.0), clampf(moved.y, 0.0, 255.0), clampf(moved.z, 0.0, 255.0))
