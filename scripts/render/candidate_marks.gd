## The marks of the houses the player may choose (One House, the arrival: scripts/town/arrival.gd), a view part of the town facade (scripts/town/town_game.gd `VIEW_PARTS`).
##
## While there is no base, each CANDIDATE house gets a small pennant over its roof in its tier's colour and icon (gold star, green circle, grey square: scripts/ui/tier_marks.gd, the same as the maps' pins
## and the arrows at the screen's edge: scripts/ui/edge_arrows.gd) and a plate with the one honest line the generator gives it ("Family home. 8 rooms, big yard."), drawn
## on the HUD's own layer (under its panels, so the type stays one size whatever the zoom) at the house's top edge. The mark FADES with the distance of the avatar from the house: nothing
## beyond `arrival.mark_r` (14 tiles, the data's), full strength within three tiles of that, and fully lit for every candidate while the Map page of the radio panel is open. None is drawn for the house
## the avatar is in, and none once there is a base. It only reads the rules (`sim.houses.town`, `sim.base`, the avatar) and the HUD's colors: a game with none of them draws nothing.
##
## THE PLATE IS KEPT IN THE FREE PART OF THE SCREEN (UI polish): a plate that would lie under a board of the HUD (the stores, the objective card, a crew card, the clock, the weapon panel, the keys'
## legend, the toolbar, the minimap) or off the window is slid to the nearest place that is clear of them and of the other plates (scripts/ui/hud_free.gd, ten times a second), and a thin line
## from the plate to the flag says which house it is.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const HudFree := preload("res://scripts/ui/hud_free.gd")
const Arrival := preload("res://scripts/town/arrival.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const Access := preload("res://scripts/access.gd")
const CbShapes := preload("res://scripts/ui/cb_shapes.gd")
const TierMarks := preload("res://scripts/ui/tier_marks.gd")

## Tiles over which a mark fades in as the avatar comes within `arrival.mark_r`.
const FADE_TILES := 3.0
const POLE_PX := 34.0
const FLAG_PX := Vector2(15.0, 10.0)
const PLATE_GAP_PX := 7.0
const EDGE_PX := 8.0
## A house with its top off the screen gets its pole on the part in view if at least this much of it (pixels each way) is, with this much room above the pole for the plate.
const MIN_SHOWN_PX := 40.0
const PLATE_ROOM_PX := 96.0
## The room the tier's icon takes at the left of the plate.
const TIER_PAD := 19.0
const TIER_LETTER_PAD := 15.0
const TITLE_SIZE := 15
const SUB_SIZE := 14
## How often (seconds) the plates are put in the free part of the screen again; between times each keeps its slide from the place it was wanted at.
const PLACE_S := 0.1

var main
var hud
var layer: Control
## What is drawn now (the tests read it): [{"house", "label", "alpha", "at": the pennant's foot on the screen}].
var marks: Array = []
## How far each plate (by house id) is slid from the place over its pole, and the screen rectangles of the plates as they are drawn (the tests read them).
var slide := {}
var plates: Array = []

var _radius := 14.0
var _plate := StyleBoxFlat.new()
var _place_t := PLACE_S


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	_radius = float(OneHouse.data().get("arrival", {}).get("mark_r", 14.0))
	_plate.set_corner_radius_all(5)
	_plate.set_border_width_all(1)
	layer = Control.new()
	layer.name = "CandidateMarks"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.draw.connect(_draw_layer)
	hud.add_child(layer)
	# (under the HUD's own boards, as the objective's arrow and the ring are: a mark in the world is never over a panel)
	hud.move_child(layer, 0)


func on_frame(dt: float) -> void:
	if layer == null:
		return
	var had := not marks.is_empty()
	_refresh()
	_place_t += dt
	if marks.is_empty():
		slide.clear()
		plates.clear()
	elif _place_t >= PLACE_S:
		_place_t = 0.0
		_replace()
	if had or not marks.is_empty():
		layer.queue_redraw()


## The marks to draw now, with their strength (0 to 1).
func _refresh() -> void:
	marks = []
	var sim = main.get("sim")
	if sim == null or sim.get("houses") == null or sim.get("avatar") == null or String(sim.player_id) == "":
		return
	var base = sim.get("base")
	if base != null and bool(base.get("claimed")):
		return
	var town = sim.houses.get("town")
	if typeof(town) != TYPE_DICTIONARY or (town as Dictionary).is_empty() or not (town as Dictionary).has("start"):
		return
	var me = sim.avatar.player()
	if me == null:
		return
	var here := Vector2(me.x, me.y)
	var inside: int = sim.houses.house_at(me.x, me.y)
	var map_open: bool = hud.has_method("radio_page") and String(hud.radio_page()) == "map"
	for c in Arrival.candidates(town):
		var h := int(c.house)
		if h == inside:
			continue
		var d := Arrival.distance_to_house(town, h, here)
		var alpha := 1.0 if map_open else clampf((_radius - d) / FADE_TILES, 0.0, 1.0)
		if alpha <= 0.01:
			continue
		var rect := Rect2(Rect2i(town.houses[h].rect))
		var foot := screen_of(Vector2(rect.get_center().x, rect.position.y))
		marks.append({"house": h, "label": String(c.get("label", "")), "alpha": alpha, "at": foot, "tier": String(c.get("tier", "ok")), "rect": rect})


## World tile -> HUD pixel (the camera is main's: centre tile and pixels per tile).
func screen_of(tile: Vector2) -> Vector2:
	var vp := layer.size if layer != null else Vector2(1280, 800)
	var cam: Vector2 = main.get("cam_center") if main.get("cam_center") is Vector2 else Vector2.ZERO
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	return (tile - cam) * z + vp * 0.5


func _draw_layer() -> void:
	if hud == null:
		return
	var bounds := Rect2(Vector2.ZERO, layer.size)
	plates.clear()
	for m in marks:
		var foot := _foot_of(m, bounds)
		if foot.x < -1.0e8:
			continue
		var g := _geometry(foot, String(m.label), String(m.get("tier", "ok")), bounds)
		# (the plate is where the free part of the screen put it: `_replace`; the house it belongs to is where the pole stands, and the line says so when the two are apart)
		var pos: Vector2 = HudFree.fit_inside(Rect2(g.want + Vector2(slide.get(int(m.house), Vector2.ZERO)), g.size), bounds.grow(-EDGE_PX)).position
		plates.append(Rect2(pos, g.size))
		_draw_mark(foot, pos, g, float(m.alpha), String(m.get("tier", "ok")))


## Where the pole of a mark stands: the foot of its pennant, or the part of the house that is on the screen when the top of it is not; (-1e9, -1e9) when there is none.
func _foot_of(m: Dictionary, bounds: Rect2) -> Vector2:
	var foot: Vector2 = m.at
	if not bounds.grow(60.0).has_point(foot):
		# (the top of a big house is off the screen but the house is not: the pole stands on the part that is, so that a house in view is never without its mark)
		foot = visible_foot(m.get("rect", Rect2()), foot, bounds)
	return foot


## The sizes and the first-choice place of a mark's plate: over the flag, in the window's edge margin.
func _geometry(foot: Vector2, label: String, tier: String, bounds: Rect2) -> Dictionary:
	var top := foot + Vector2(0.0, -POLE_PX)
	var title := label
	var sub := ""
	var cut := label.find(". ")
	if cut > 0:
		title = label.substr(0, cut)
		sub = label.substr(cut + 2).trim_suffix(".")
	var f_title := Fonts.cond(700)
	var f_sub := Fonts.sans(400)
	var w := maxf(f_title.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x, f_sub.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, SUB_SIZE).x if sub != "" else 0.0)
	var letters := TierMarks.letters_on()    # (the colour-blind setting: the tier's letter after its icon)
	var pad := TIER_PAD + (TIER_LETTER_PAD if letters else 0.0)
	var size := Vector2(w + 22.0 + pad, 24.0 + (19.0 if sub != "" else 0.0))
	var want := Vector2(foot.x - size.x * 0.5, top.y - PLATE_GAP_PX - size.y)
	want = HudFree.fit_inside(Rect2(want, size), bounds.grow(-EDGE_PX)).position
	return {"top": top, "title": title, "sub": sub, "size": size, "want": want, "pad": pad, "letters": letters}


## Every PLACE_S: each plate's slide from its first-choice place to the nearest place in the free part of the screen (clear of the HUD's boards and of the plates before it).
func _replace() -> void:
	var bounds := Rect2(Vector2.ZERO, layer.size)
	var blocked := HudFree.rects(main, hud, layer)
	var placed: Array = []
	var next := {}
	for m in marks:
		var foot := _foot_of(m, bounds)
		if foot.x < -1.0e8:
			continue
		var g := _geometry(foot, String(m.label), String(m.get("tier", "ok")), bounds)
		var box := Rect2(g.want, g.size)
		var spot := HudFree.nearest_free(box, bounds.grow(-EDGE_PX), blocked, placed)
		placed.append(spot.grow(3.0))
		next[int(m.house)] = spot.position - Vector2(g.want)
	slide = next


## Where the pole of a house whose top edge is off the screen stands: on the part of the house that is on the screen, with room above it for the plate; (-1e9, -1e9) when too little of the house is.
func visible_foot(rect: Rect2, foot: Vector2, bounds: Rect2) -> Vector2:
	if rect.size == Vector2.ZERO:
		return Vector2(-1.0e9, -1.0e9)
	var a := screen_of(rect.position)
	var b := screen_of(rect.end)
	var vis := Rect2(a, b - a).intersection(bounds.grow(-EDGE_PX))
	if vis.size.x < MIN_SHOWN_PX or vis.size.y < MIN_SHOWN_PX:
		return Vector2(-1.0e9, -1.0e9)
	var x := clampf(foot.x, vis.position.x, vis.end.x)
	var y := minf(maxf(clampf(foot.y, vis.position.y, vis.end.y), bounds.position.y + PLATE_ROOM_PX), vis.end.y)
	return Vector2(x, y)


## A pole from the house's top edge with a pennant, and above it the plate: the kind of house in bold, what it has under it.
func _draw_mark(foot: Vector2, pos: Vector2, g: Dictionary, alpha: float, tier: String = "ok") -> void:
	var accent: Color = TierMarks.color(tier)    # (the tier's colour and icon: the edge arrows and the maps say the same: scripts/ui/tier_marks.gd)
	var ink: Color = hud.INK
	var ink2: Color = hud.INK2
	var dark := Color(0.04, 0.08, 0.07)
	var top: Vector2 = g.top
	var size: Vector2 = g.size
	var pad: float = g.pad
	var title: String = g.title
	var sub: String = g.sub
	var letters: bool = g.letters
	var f_title := Fonts.cond(700)
	var f_sub := Fonts.sans(400)
	# the line from the plate to the flag when the plate has been moved off its pole
	var hook := Vector2(clampf(top.x, pos.x, pos.x + size.x), clampf(top.y, pos.y, pos.y + size.y))
	if hook.distance_to(top) > 12.0:
		layer.draw_line(hook, top, Color(dark, 0.7 * alpha), 3.5, true)
		layer.draw_line(hook, top, Color(accent, 0.8 * alpha), 1.6, true)
	# the pole, with a dark rim so it reads on any roof, and the flag
	layer.draw_line(foot, top, Color(dark, 0.8 * alpha), 4.0, true)
	layer.draw_line(foot, top, Color(accent, alpha), 2.0, true)
	var flag := PackedVector2Array([top, top + Vector2(FLAG_PX.x, FLAG_PX.y * 0.5), top + Vector2(0.0, FLAG_PX.y)])
	layer.draw_colored_polygon(flag, Color(accent, alpha))
	var rim := PackedVector2Array(flag)
	rim.append(flag[0])
	layer.draw_polyline(rim, Color(dark, 0.85 * alpha), 1.5, true)
	layer.draw_circle(foot, 3.0, Color(accent, alpha))
	if Access.markers():
		# (Colour-blind markers: a pale rim on the pole and a plus beside the flag, "a house to claim", so that the green is not all that says it)
		layer.draw_circle(foot, 5.0, Color(CbShapes.RIM, 0.9 * alpha), false, 1.4)
		CbShapes.mark(layer, "plus", top + Vector2(FLAG_PX.x + 9.0, FLAG_PX.y * 0.5), 3.8, Color(accent, alpha), Color(CbShapes.RIM, alpha))
	# the plate
	_plate.bg_color = Color(dark, 0.84 * alpha)
	_plate.border_color = Color(accent, 0.75 * alpha)
	layer.draw_style_box(_plate, Rect2(pos, size))
	TierMarks.draw_icon(layer, tier, pos + Vector2(11.0 + 6.0, 12.5), 6.0, alpha)
	if letters:
		layer.draw_string(f_title, pos + Vector2(11.0 + TIER_PAD, 18.0), TierMarks.letter(tier), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Color(accent, alpha))
	layer.draw_string(f_title, pos + Vector2(11.0 + pad, 18.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Color(ink, alpha))
	if sub != "":
		layer.draw_string(f_sub, pos + Vector2(11.0 + pad, 36.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, SUB_SIZE, Color(ink2, alpha))
