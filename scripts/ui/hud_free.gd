## The free area of the screen (One House, UI polish): where a label that stands over the world may go without being covered by a board of the HUD.
##
## The marks in the world (the pennants of the houses to claim, the objective's arrow and its distance, the arrows at the edge) are drawn on the HUD's own layer UNDER its boards, so a label
## that lands on the stores, the objective card, a crew card, the clock, the weapon panel, the toolbar, the minimap, the key legend or the lesson is half hidden. `controls` lists those boards,
## `rects` gives the ones that are showing as rectangles in the coordinates of a Control of the HUD, and `nearest_free` moves a box to the nearest place inside a rectangle of the screen that none
## of them covers (and none of the boxes placed before it). Static functions only; nothing here makes a node or reads the rules.
extends RefCounted

## How far a board's rectangle is grown, so that a label is not set hard against it.
const PAD := 4.0
## The offsets a box is tried at, in pixels from where it was wanted: every STEP pixels up to REACH, the nearest first (made once).
const STEP := 12.0
const REACH := 330.0

static var _offsets := PackedVector2Array()


## The HUD's boards that a label must keep clear of (some are null or hidden: `rects` leaves them out).
static func controls(main, hud) -> Array:
	var watch: Array = [hud.get("left_col"), hud.get("right_col"), hud.get("speed_panel"), hud.get("dock"), hud.get("inspect"), hud.get("radio_box"), hud.get("radio_panel"),
		hud.get("banner"), hud.get("help")]
	var town = main.get("town") if main != null else null
	var hud_part = town.part("town_hud") if town != null else null
	if hud_part != null:
		watch.append(hud_part.get("lesson_card"))
		watch.append(hud_part.get("legend"))
		watch.append(hud_part.get("radio_card"))
	var mini_part = town.part("minimap") if town != null else null
	if mini_part != null:
		watch.append(mini_part.get("root"))
	var bar = hud.get("bar")
	if bar is Control:
		for card in (bar as Control).get_children():
			watch.append(card)
	return watch


## The rectangles of the boards that are showing, in the coordinates of `ci` (a Control that fills the HUD), each grown by `PAD`.
static func rects(main, hud, ci: Control) -> Array:
	var out: Array = []
	var origin := ci.get_global_rect().position
	for ctl in controls(main, hud):
		if ctl is Control and (ctl as Control).is_visible_in_tree():
			var r := (ctl as Control).get_global_rect()
			if r.size.x > 1.0 and r.size.y > 1.0:
				out.append(Rect2(r.position - origin, r.size).grow(PAD))
	return out


## `box` moved the least distance (by its top left) to where it is inside `bounds` and clear of every rectangle in `blocked` and in `others`; the box itself if it is there already, and
## the box pushed into `bounds` when there is no such place.
static func nearest_free(box: Rect2, bounds: Rect2, blocked: Array, others: Array = []) -> Rect2:
	var home := fit_inside(box, bounds)
	if _clear(home, blocked, others):
		return home
	for off in _ring():
		var c := fit_inside(Rect2(home.position + off, home.size), bounds)
		if _clear(c, blocked, others):
			return c
	return home


## `box` slid, if need be, to lie inside `bounds` (a box bigger than the bounds sits at their top left).
static func fit_inside(box: Rect2, bounds: Rect2) -> Rect2:
	var p := box.position
	p.x = clampf(p.x, bounds.position.x, maxf(bounds.end.x - box.size.x, bounds.position.x))
	p.y = clampf(p.y, bounds.position.y, maxf(bounds.end.y - box.size.y, bounds.position.y))
	return Rect2(p, box.size)


static func _clear(box: Rect2, blocked: Array, others: Array) -> bool:
	for r in blocked:
		if box.intersects(r):
			return false
	for r in others:
		if box.intersects(r):
			return false
	return true


static func _ring() -> PackedVector2Array:
	if _offsets.is_empty():
		var list: Array = []
		var n := int(REACH / STEP)
		for iy in range(-n, n + 1):
			for ix in range(-n, n + 1):
				var v := Vector2(float(ix), float(iy)) * STEP
				if v != Vector2.ZERO and v.length() <= REACH:
					list.append(v)
		# (nearest first; a tie goes to the one that moves sideways, so a label slides along a row rather than jumping over it)
		list.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			var la := a.length_squared()
			var lb := b.length_squared()
			if absf(la - lb) < 0.01:
				return absf(a.y) < absf(b.y)
			return la < lb)
		_offsets = PackedVector2Array(list)
	return _offsets
