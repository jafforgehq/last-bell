## Fonts: Barlow and Barlow Condensed, bundled in assets/fonts (SIL Open Font
## Licence, see OFL.txt) so the game looks the same on every platform,
## including the web build.
extends RefCounted

const SANS := {400: "res://assets/fonts/Barlow-Regular.ttf", 500: "res://assets/fonts/Barlow-Medium.ttf", 600: "res://assets/fonts/Barlow-SemiBold.ttf"}
const COND := {600: "res://assets/fonts/BarlowCondensed-SemiBold.ttf", 700: "res://assets/fonts/BarlowCondensed-Bold.ttf"}

static var _cache := {}


static func cond(weight: int = 600, spacing: int = 0) -> Font:
	return _make(COND, weight, spacing)


static func sans(weight: int = 400, spacing: int = 0) -> Font:
	return _make(SANS, weight, spacing)


static func _make(family: Dictionary, weight: int, spacing: int) -> Font:
	# nearest available weight
	var best: int = family.keys()[0]
	for w in family:
		if absi(w - weight) < absi(best - weight):
			best = w
	var key := "%s-%d" % [family[best], spacing]
	if _cache.has(key):
		return _cache[key]
	var out: Font = load(family[best])
	if spacing != 0:
		var v := FontVariation.new()
		v.base_font = out
		v.spacing_glyph = spacing
		out = v
	_cache[key] = out
	return out
