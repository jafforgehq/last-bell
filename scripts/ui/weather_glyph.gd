## The small weather icon (RAIN): a cloud, with drops under it while it rains and a bolt in a storm, made in code (no art file). One sits in the clock's temperature row, in the place of the
## sun or moon while the sky is overcast or wet, and one on the rim of the minimap (`badge`: on a small dark disc). It has a tooltip that says what the weather does (`skies.tip()`).
## Made and fed by scripts/render/rain_view.gd.
##
## It is a TextureRect, not a `_draw`: a cloud of three circles, a base and some drops is eight draw commands, which is eight draw calls in the HUD; the picture is made ONCE for each word
## (24 by 24, supersampled twice over each way, a few milliseconds in GDScript: `prewarm_next` makes one every fifth of a second from a half second into the run, so no first rain is a
## stall) and the icon then costs one call.
extends TextureRect

const CLOUD := Color(0.80, 0.86, 0.94)
const CLOUD_DARK := Color(0.58, 0.64, 0.74)
const DROP := Color(0.58, 0.78, 1.0)
const BOLT := Color(1.0, 0.88, 0.35)
const DISC := Color(0.06, 0.07, 0.09, 0.86)
const RIM := Color(0.94, 0.76, 0.29, 0.85)
const WORDS := ["overcast", "drizzle", "rain", "storm"]
const PX := 24
const SS := 2
const BOLT_POLY := [Vector2(0.54, 0.62), Vector2(0.38, 0.84), Vector2(0.49, 0.84), Vector2(0.42, 1.0), Vector2(0.65, 0.76), Vector2(0.53, 0.76)]
const DROPS := {
	"drizzle": [[Vector2(0.34, 0.74), Vector2(0.30, 0.88)], [Vector2(0.60, 0.74), Vector2(0.56, 0.88)]],
	"rain": [[Vector2(0.28, 0.72), Vector2(0.23, 0.90)], [Vector2(0.48, 0.72), Vector2(0.43, 0.90)], [Vector2(0.68, 0.72), Vector2(0.63, 0.90)]],
	"storm": [[Vector2(0.24, 0.72), Vector2(0.20, 0.86)], [Vector2(0.78, 0.72), Vector2(0.74, 0.86)]],
}

static var _cache := {}

## "clear" (shows nothing), "overcast", "drizzle", "rain" or "storm".
var word := "clear"
var badge := false


func _init(px: float = 16.0, on_disc: bool = false) -> void:
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	badge = on_disc
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false


func set_word(w: String, tip: String) -> void:
	if w != word:
		word = w
		texture = texture_for(w, badge) if w != "clear" else null
	if tooltip_text != tip:
		tooltip_text = tip


## The picture for a word, made when it is first asked for.
static func texture_for(w: String, on_disc: bool) -> ImageTexture:
	var key := "%s%d" % [w, 1 if on_disc else 0]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_raster(w, on_disc))
	return _cache[key]


## Makes the next picture that is not made yet (one call, one picture); false when they all are.
static func prewarm_next() -> bool:
	for on_disc in [false, true]:
		for w in WORDS:
			if not _cache.has("%s%d" % [w, 1 if on_disc else 0]):
				texture_for(w, on_disc)
				return true
	return false


# ------------------------------------------------------------------------------ the picture --

static func _near_segment(p: Vector2, a: Vector2, b: Vector2, half: float) -> bool:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t) <= half


static func _in_poly(p: Vector2, poly: Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside


## The colour at a point of the unit square (alpha 0: nothing there). The top layer wins: bolt, drops, cloud, then the disc of a badge.
static func _sample(p: Vector2, w: String, disc: bool) -> Color:
	var q := p
	if disc:
		var d := p.distance_to(Vector2(0.5, 0.5))
		if d > 0.5:
			return Color(0, 0, 0, 0)
		q = (p - Vector2(0.13, 0.13)) / 0.74
	if w == "storm" and _in_poly(q, BOLT_POLY):
		return BOLT
	if DROPS.has(w):
		for seg in DROPS[w]:
			if _near_segment(q, seg[0], seg[1], 0.045):
				return DROP
	if q.distance_to(Vector2(0.30, 0.46)) <= 0.18 or q.distance_to(Vector2(0.50, 0.36)) <= 0.24 or q.distance_to(Vector2(0.71, 0.47)) <= 0.17 or (q.x >= 0.22 and q.x <= 0.80 and q.y >= 0.46 and q.y <= 0.62):
		return CLOUD_DARK if w == "storm" else CLOUD
	if disc:
		return RIM if p.distance_to(Vector2(0.5, 0.5)) >= 0.455 else DISC
	return Color(0, 0, 0, 0)


static func _raster(w: String, disc: bool) -> Image:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGBA8)
	var n := float(SS * SS)
	for py in PX:
		for px in PX:
			var r := 0.0
			var g := 0.0
			var b := 0.0
			var a := 0.0
			for sy in SS:
				for sx in SS:
					var c := _sample(Vector2((float(px) + (float(sx) + 0.5) / float(SS)) / float(PX), (float(py) + (float(sy) + 0.5) / float(SS)) / float(PX)), w, disc)
					r += c.r * c.a
					g += c.g * c.a
					b += c.b * c.a
					a += c.a
			if a > 0.0:
				img.set_pixel(px, py, Color(r / a, g / a, b / a, a / n))
	return img
