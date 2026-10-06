## The look of the key in an E prompt (One House, WORLD): the rounded KEY CAP with the letter, and for a thing that takes time (a search, the claim, a bandage) the RING round the cap
## that fills while the session runs, with what is left of the time as a thin arc and the seconds beside the words. The pill itself (its slate, its place, its words) is the overlay's
## (scripts/render/overlay_node.gd `_draw_prompt_pill`); this is the part of it that is the key. It reads the rules (`sim.uses.progress()`, `in_session`) and writes nothing.
##
## THE RING. A candidate with `session: true` begins a session of the rules' own length when E is pressed. Before it: a thin pale circle round the cap (this takes time). While it runs:
## the part done is a gold arc as thick as the cap's lip, the part left is a thin pale arc, clockwise from the top, and the pill says the seconds left. Nothing animates but the numbers
## the rules give, so Reduce motion leaves it as it is.
## THE CAP. A square with rounded corners in the HUD's yellow and a darker lip under it (so it reads as a key you press); grey when the thing may not be used now. A `glyph` other than
## "E" is for the stand-in of a thing already done (a check mark on a searched container: no key to press).
## COST. The cap and the ring's track are two small pictures made once from distance fields (no file), drawn as rectangles, so a prompt is the pill, one gold arc and the words.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const S := preload("res://scripts/render/shapes.gd")

const CAP := 24.0
const LIP := 2.0
const RING_R := 18.5
## The width of the pill's key area: the cap alone, or the cap and its ring.
const AREA := 30.0
const AREA_RING := 47.0
const GOLD := Color(0.941, 0.761, 0.29)
const GOLD_INK := Color("#1a1508")
const GREY := Color("#a8ae9d")
const PALE := Color(0.93, 0.96, 0.89)
const TRACK := Color(0.02, 0.04, 0.035, 0.55)

## The pictures, made at the first prompt: "gold" and "grey" caps (28 x 28 logical pixels) and the ring's track and thin arc (46 x 46), all at twice the size.
static var _tex := {}


## What the candidate's session has done: {"t": 0 to 1, "left": seconds left} while it is the session in hand, {} when it is not (or has none).
static func session_ring(sim, c: Dictionary) -> Dictionary:
	if sim == null or c.is_empty() or not bool(c.get("session", false)):
		return {}
	var uses = sim.get("uses")
	if uses == null or not uses.has_method("in_session") or not uses.in_session(String(c.get("kind", "")), String(c.get("id", ""))):
		return {}
	var pr: Dictionary = uses.progress()
	var total := maxf(float(pr.get("of", 0.0)), 0.001)
	var t := clampf(float(pr.get("t", 0.0)) / total, 0.0, 1.0)
	return {"t": t, "left": maxf(total - float(pr.get("t", 0.0)), 0.0)}


## The cap, centred on `at`. `ring` is {} (no ring), or {"t", "left"} (see `session_ring`); `timed` draws the pale track when the session has not begun. `ok` is false for a thing
## that may not be used now (grey).
static func draw_cap(ci: CanvasItem, at: Vector2, ok: bool, glyph: String, fs: int, timed: bool, ring: Dictionary) -> void:
	_make()
	ci.draw_texture_rect(_tex["gold" if ok else "grey"], Rect2(at - Vector2(14.0, 14.5), Vector2(28.0, 28.0)), false)
	if glyph == "check":
		# a tick, drawn (the font has no good one)
		var c := at + Vector2(0.0, -1.0)
		ci.draw_line(c + Vector2(-5.5, 0.5), c + Vector2(-1.8, 4.2), GOLD_INK, 2.6)
		ci.draw_line(c + Vector2(-1.8, 4.2), c + Vector2(5.8, -4.6), GOLD_INK, 2.6)
	else:
		var f := Fonts.cond(700, 1)
		ci.draw_string(f, Vector2(at.x - CAP * 0.5, at.y + float(fs) * 0.34 - 1.0), glyph, HORIZONTAL_ALIGNMENT_CENTER, CAP, fs + 2, GOLD_INK)
	if not ring.is_empty():
		var t := float(ring.get("t", 0.0))
		# (the track and the thin arc of what is left are one picture; the gold arc is drawn over it, as thick, so the thin one shows only where the time is not yet gone)
		ci.draw_texture_rect(_tex["ring"], Rect2(at - Vector2(23.0, 23.0), Vector2(46.0, 46.0)), false)
		if t > 0.004:
			ci.draw_arc(at, RING_R, -PI / 2.0, -PI / 2.0 + t * TAU, 40, GOLD, 3.6, true)
	elif timed and ok:
		ci.draw_texture_rect(_tex["ring"], Rect2(at - Vector2(23.0, 23.0), Vector2(46.0, 46.0)), false, Color(1, 1, 1, 0.45))


# ------------------------------------------------------------------------ the pictures --

## Makes the pictures now (the town's loading does it, so that the first prompt is not the frame that pays for them).
static func warm() -> void:
	_make()


static func _make() -> void:
	if not _tex.is_empty():
		return
	_tex["gold"] = _cap_image(GOLD)
	_tex["grey"] = _cap_image(GREY)
	_tex["ring"] = _ring_image()


## Signed distance to a rounded rectangle (negative inside).
static func _sd_rrect(p: Vector2, centre: Vector2, half: Vector2, r: float) -> float:
	var q := (p - centre).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


## The cap at twice the size: the lip (darker, two pixels lower) and the face over it with a pale edge.
static func _cap_image(face: Color) -> ImageTexture:
	var n := 56
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var lip_col := face.darkened(0.5)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var d_face := _sd_rrect(p, Vector2(28.0, 26.0), Vector2(24.0, 22.0), 12.0)
			var d_lip := _sd_rrect(p, Vector2(28.0, 30.0), Vector2(24.0, 22.0), 12.0)
			var a_lip := clampf(0.5 - d_lip, 0.0, 1.0)
			var a_face := clampf(0.5 - d_face, 0.0, 1.0)
			var edge := clampf(1.0 - absf(d_face + 1.2), 0.0, 1.0) * 0.28
			var face_col := face.lerp(Color(1, 1, 1), edge)
			var col := Color(lip_col, a_lip)
			col = Color(col.r * (1.0 - a_face) + face_col.r * a_face, col.g * (1.0 - a_face) + face_col.g * a_face, col.b * (1.0 - a_face) + face_col.b * a_face, a_face + a_lip * (1.0 - a_face))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## The ring's track (dark, 5 pixels) with the thin pale ring (about 1.8 pixels) on it, at twice the size.
static func _ring_image() -> ImageTexture:
	var n := 92
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var r := RING_R * 2.0
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(46.0, 46.0))
			var a_track := clampf(5.0 + 0.5 - absf(d - r), 0.0, 1.0) * TRACK.a
			var a_thin := clampf(1.8 + 0.5 - absf(d - r), 0.0, 1.0) * 0.85
			var out_a := a_thin + a_track * (1.0 - a_thin)
			var out_c := Color(0, 0, 0, 0)
			if out_a > 0.0:
				var cr := (PALE.r * a_thin + TRACK.r * a_track * (1.0 - a_thin)) / out_a
				var cg := (PALE.g * a_thin + TRACK.g * a_track * (1.0 - a_thin)) / out_a
				var cb := (PALE.b * a_thin + TRACK.b * a_track * (1.0 - a_thin)) / out_a
				out_c = Color(cr, cg, cb, out_a)
			img.set_pixel(x, y, out_c)
	return ImageTexture.create_from_image(img)
