## The look of the three tiers of a house that may be claimed ("best", "ok", "poor": scripts/town/arrival.gd), in one place so that the pennants in the street, the pins of the Map page
## and of the minimap, and the arrows at the edge of the screen (scripts/ui/edge_arrows.gd) all say the same thing: a colour AND a shape, so that the tier is not told by colour alone.
##
##   best  gold   a star
##   ok    green  a circle
##   poor  grey   a square
##
## Static functions only. `draw_icon` draws with the canvas item's transform and a few constant arrays: it makes nothing, so it may be called every frame.
extends RefCounted

const Access := preload("res://scripts/access.gd")

const BEST := Color("#f0c24a")
const OK := Color("#8fb85a")
const POOR := Color("#a8ae9d")
const RIM := Color(0.04, 0.08, 0.07, 0.9)

## The words of the tiers, as the Map page's key says them.
const WORDS := {"best": "Best", "ok": "Fair", "poor": "Poor"}
## One letter for each, for the markers that carry a letter as well as a shape (the colour-blind setting).
const LETTERS := {"best": "B", "ok": "F", "poor": "P"}

## A five-pointed star in a circle of radius 1 (the points up), and the same closed for the outline.
static var STAR := PackedVector2Array([
	Vector2(0.0, -1.0), Vector2(0.2645, -0.3641), Vector2(0.9511, -0.3090), Vector2(0.4280, 0.1391), Vector2(0.5878, 0.8090),
	Vector2(0.0, 0.45), Vector2(-0.5878, 0.8090), Vector2(-0.4280, 0.1391), Vector2(-0.9511, -0.3090), Vector2(-0.2645, -0.3641),
])
static var STAR_LINE := PackedVector2Array([
	Vector2(0.0, -1.0), Vector2(0.2645, -0.3641), Vector2(0.9511, -0.3090), Vector2(0.4280, 0.1391), Vector2(0.5878, 0.8090),
	Vector2(0.0, 0.45), Vector2(-0.5878, 0.8090), Vector2(-0.4280, 0.1391), Vector2(-0.9511, -0.3090), Vector2(-0.2645, -0.3641), Vector2(0.0, -1.0),
])


## Whether the marks carry a letter as well as a shape and a colour: the Settings' "Colour-blind markers" (scripts/access.gd).
static func letters_on() -> bool:
	return Access.markers()


static func letter(tier: String) -> String:
	return String(LETTERS.get(tier, "F"))


static func color(tier: String) -> Color:
	match tier:
		"best":
			return BEST
		"poor":
			return POOR
	return OK


static func word(tier: String) -> String:
	return String(WORDS.get(tier, "House"))


## The tier as a number for the minimap's flag texture: 3 fair (green), 4 best (gold), 5 poor (grey); 0 for anything else.
static func flag_of(tier: String) -> int:
	match tier:
		"ok":
			return 3
		"best":
			return 4
		"poor":
			return 5
	return 3


## The tier's icon at `at`, `r` pixels from its middle to its points: a star, a circle or a square in the tier's colour, with a dark rim.
static func draw_icon(ci: CanvasItem, tier: String, at: Vector2, r: float, alpha: float = 1.0) -> void:
	var col := Color(color(tier), alpha)
	var rim := Color(RIM, RIM.a * alpha)
	match tier:
		"best":
			ci.draw_set_transform(at, 0.0, Vector2(r * 1.15, r * 1.15))
			ci.draw_colored_polygon(STAR, col)
			ci.draw_polyline(STAR_LINE, rim, 1.4 / (r * 1.15), true)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"poor":
			var box := Rect2(at - Vector2(r, r) * 0.82, Vector2(r, r) * 1.64)
			ci.draw_rect(box, col)
			ci.draw_rect(box, rim, false, 1.4)
		_:
			ci.draw_circle(at, r * 0.92, col)
			ci.draw_arc(at, r * 0.92, 0.0, TAU, 20, rim, 1.4, true)
