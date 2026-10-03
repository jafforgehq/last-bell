## The paper map of the Town Board (round 8): the board of the town drawn in code on a sheet of noticeboard paper.
## A few streets and blocks and some trees are only decoration (the data has none: they are laid out the same way
## every time, off the roads and the places); what matters is on top of that:
##   - the roads between the known places and the school, inked solid; a road that runs from a known place to one
##     that is not known is a faint dashed stub (there is more that way); roads between two unknown places are
##     not drawn at all;
##   - the school, and a pin (a button: a mouse can click it and the keyboard can Tab and arrow between them) for
##     each KNOWN place, with an icon for what kind of place it is and small marks for how things stand: a tick
##     (cleared), a flag (an outpost of yours), a red disc with a number (a nest and its strength), a small figure
##     (someone is hiding there), a shield (a garrison holds it); the chosen pin has a gold ring, the one with the
##     keyboard a dark ring;
##   - a faint "?" for each place that is not known yet, near where it is (not on it);
##   - the parties that are out, a blue disc with the number of people on the route between the school and the
##     place by how much of the trip is gone (a party that went by vehicle is a blue plate with a small car on it);
##   - round 13: the board is 160 tiles wide and the city is across the river, so the sheet shows what is known, not the
##     whole board: the school, the known places and the unknown ones within NEAR_KNOWN tiles of a known place (a place
##     a scouting trip could show next), with a margin (`view`), and it grows as places are found; once the bridge is
##     known the river is drawn through it and the road over it is a bridge, and until a place across the river is known
##     a chip at the east edge says "Across the river"; a place that can only be reached by vehicle has a blue ring;
##   - the names of the places (a caption under or beside a pin when there is room; the hovered, chosen and focused
##     pins always have theirs) and the points of the compass (north is up).
##
## The page (town_board.gd) gives it the picture with `set_data` and listens for `place_chosen` (a pin pressed:
## by the mouse, or Enter or Space with the keyboard on it) and `place_hovered`. It borrows the HUD's colours (the
## `hud` it is given): the ink is the HUD's PAPER_INK family.
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")
## (The script itself, for the small classes at the foot, which cannot reach its static functions by name.)
const Self := preload("res://scripts/ui/town_map.gd")

## A pin was pressed (its place's id); the pointer or the keyboard came to a pin, or left them all ("").
signal place_chosen(id: String)
signal place_hovered(id: String)

## The room kept round the board, a pin's disc and the square a click or the keyboard has on it, in pixels.
const PAD := 20.0
const PIN_R := 14.0
const HIT := 36.0
## Captions are drawn this size (the floor for any text of the game) and only when the map is this wide.
const CAPTION_PX := 12
const CAPTION_MIN_W := 440.0
## The sheet of the map, a little darker than the page it is pinned on; the colours of what is drawn on it.
const SHEET := Color("#e7dcbc")
const SHEET_EDGE := Color(0.16, 0.14, 0.1, 0.55)
const ROAD_EDGE := Color(0.2, 0.17, 0.1, 0.5)
const ROAD_FILL := Color("#f4eed7")
const STUB := Color(0.2, 0.17, 0.1, 0.4)
const BLOCK_FILL := Color(0.45, 0.38, 0.25, 0.13)
const BLOCK_EDGE := Color(0.35, 0.29, 0.18, 0.24)
const TREE_FILL := Color(0.33, 0.45, 0.25, 0.26)
## The faint "?": ink at 70% on the sheet is a little over 3 to 1, which a mark that is not words has to be.
const UNKNOWN_INK := Color(0.34, 0.33, 0.26, 0.7)
const CARD := Color("#f8f4e8")
const CLEARED_FILL := Color("#e2ebcd")
const CLAIMED_FILL := Color("#fbecb8")
const GOLD_EDGE := Color("#946c0c")
const RED := Color("#a8301f")
const GREEN := Color("#2e6b34")
const BLUE := Color("#2a6488")
## The wash of a place only a vehicle reaches.
const VEHICLE_FILL := Color("#d6e4ea")
const OAK_DARK := Color("#56391f")
## The decoration is laid out from this (the same in every game and every window).
const DECOR_SEED := 20261002
## The unknown places' "?" sit this many tiles off the place itself, at most.
const UNKNOWN_SHIFT := 2.2
## What the sheet shows (round 13): the known places and the unknown ones this near to a known place (tiles), with this
## margin (tiles), in a shape whose height over its width is kept between ASPECT_MIN and ASPECT_MAX, and at least this big.
const NEAR_KNOWN := 25.0
const VIEW_MARGIN := 3.0
const ASPECT_MIN := 0.4
const ASPECT_MAX := 0.8
const VIEW_MIN := Vector2(30.0, 20.0)
## Two pins are asked to be at least this far apart (pixels, centre to centre): the page gives the map the width for it.
const CLEAR_PX := PIN_R * 2.0 + 4.0
## The river that the bridge crosses, as wide as this (tiles); a bridge's deck reaches this far from its pin on each side.
const RIVER_W := 5.0
const DECK_REACH := 3.8
const CHIP_TEXT := "ACROSS THE RIVER"

## kind (or part of one) -> glyph, the first match wins.
const GLYPHS := [
	["fire", "flame"], ["police", "shield"], ["pharm", "cross"], ["clinic", "cross"], ["hospital", "cross"], ["church", "church"],
	["farm", "barn"], ["radio", "mast"], ["bakery", "loaf"], ["bunker", "dome"], ["water", "drop"], ["library", "book"],
	["hardware", "tool"], ["garage", "car"], ["gas", "pump"], ["fuel", "pump"], ["bus", "bus"], ["scrap", "gear"],
	["supermarket", "cart"], ["market", "cart"], ["warehouse", "box"], ["school", "school"], ["house", "house"], ["home", "house"],
	# round 13: the city across the river
	["bridge", "arch"], ["checkpoint", "barrier"], ["cold", "snow"], ["universit", "cap"], ["power", "bolt"], ["rail", "rails"],
]

var hud
var board := Vector2(100.0, 70.0)
var home := Vector2(50.0, 35.0)
## The known places as the board offers them (town.gd's `known_places` shape: id, name, kind, pos (a Vector2), state,
## nest, survivor, garrison, hours...).
var places: Array = []
## The roads to draw: {"a": Vector2, "b": Vector2, "stub": bool} in board tiles.
var roads: Array = []
## The places not known yet: {"id", "pos"} (where the "?" goes: not the place's own spot).
var unknown: Array = []
## Every street, for the decoration to keep off: [[Vector2, Vector2], ...].
var streets: Array = []
## The parties that are out: {"n", "count", "path" (Vector2s in board tiles, from the school), "at" (0 to 1 along it),
## "mode" ("out", "search" or "back"), "text"}.
var parties: Array = []
## What the sheet shows, in board tiles (see `_fit_view`).
var view := Rect2(0.0, 0.0, 100.0, 70.0)
## The chip at the east edge that says there is more across the river (pixels; empty when it is not there).
var river_chip := Rect2()
## The pin that is chosen, the one under the pointer, the one with the keyboard ("" for none).
var chosen := ""
var hovered := ""
var focused := ""
## place id -> its pin (a Button)
var pins := {}
## Round 18 (optional): the focus mode the pins are given. The Town Board keeps them focusable (the keyboard walks the pins); the
## radio panel's Map page sets FOCUS_NONE (`set_pin_focus`) so that WASD and E never go into a button.
var pin_focus: int = Control.FOCUS_ALL
var home_marker: Control
var _over: Control
var _scale := 1.0
var _origin := Vector2.ZERO
var _blocks: Array = []
var _trees: Array = []
var _decor_key := ""
var _caption_ids: Array = []


func setup(h) -> void:
	hud = h
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	_over = Over.new()
	_over.map = self
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_over)
	home_marker = HomeMarker.new()
	home_marker.map = self
	home_marker.size = Vector2(HIT, HIT)
	home_marker.mouse_filter = Control.MOUSE_FILTER_PASS
	home_marker.tooltip_text = "The school: where the parties leave from and come back to"
	add_child(home_marker)
	home_marker.set_meta("caption", _make_caption("The school"))
	resized.connect(_layout)


## Hands the map its picture: the board as `d` ({"board", "home", "places", "roads", "unknown", "streets", "parties",
## "chosen"}); the pins are made, moved or taken away to match, and everything is drawn again.
func set_data(d: Dictionary) -> void:
	board = d.get("board", board)
	home = d.get("home", home)
	places = d.get("places", [])
	roads = d.get("roads", [])
	unknown = d.get("unknown", [])
	streets = d.get("streets", [])
	parties = d.get("parties", [])
	chosen = String(d.get("chosen", ""))
	_fit_view()
	_sync_pins()
	_decorate()
	_layout()
	queue_redraw()
	_over.queue_redraw()


## Sets how the pins take focus (Control.FOCUS_NONE for a map that must not take the keyboard), for the pins there are and for
## those made later. Round 18, optional: a map that never calls it is as it was.
func set_pin_focus(mode: int) -> void:
	pin_focus = mode
	for pin in pins.values():
		pin.focus_mode = mode as Control.FocusMode


## The pins of the places that are known now.
func _sync_pins() -> void:
	var keep := {}
	for p in places:
		var id := String(p.id)
		keep[id] = true
		var pin = pins.get(id)
		if pin == null:
			pin = Pin.new()
			pin.map = self
			pin.id = id
			pin.size = Vector2(HIT, HIT)
			pin.pressed.connect(func(): place_chosen.emit(id))
			pin.mouse_entered.connect(func(): _point_at(id, true))
			pin.mouse_exited.connect(func(): _point_at(id, false))
			pin.focus_entered.connect(func(): _focus_on(id, true))
			pin.focus_exited.connect(func(): _focus_on(id, false))
			pin.set_meta("caption", _make_caption(String(p.name)))
			pin.focus_mode = pin_focus as Control.FocusMode
			pins[id] = pin
			add_child(pin)
		pin.place = p
		pin.tooltip_text = _tip(p)
		pin.get_meta("caption").text = String(p.name)
		pin.queue_redraw()
	for id in pins.keys():
		if not keep.has(id):
			var gone: Control = pins[id]
			if hovered == id:
				hovered = ""
			if focused == id:
				focused = ""
			gone.get_meta("caption").queue_free()
			gone.queue_free()
			pins.erase(id)
	# the overlay (the parties) stays on top, the captions above the pins
	for id in pins:
		move_child(pins[id].get_meta("caption"), -1)
	move_child(home_marker.get_meta("caption"), -1)
	move_child(_over, -1)


func _tip(p: Dictionary) -> String:
	var hours := float(p.get("hours", 0.0))
	var words := "%s: %s from the school" % [String(p.name), hours_text(hours)]
	match String(p.state):
		"cleared":
			words += ", cleared"
		"claimed":
			words += ", your outpost"
	if bool(p.get("needs_vehicle", false)):
		words += ". By vehicle only"
	return words


## "about an hour", "about 2 hours", "about 3.5 hours".
static func hours_text(hours: float) -> String:
	var h := snappedf(hours, 0.5)
	if h <= 0.5:
		return "under an hour"
	if is_equal_approx(h, 1.0):
		return "about an hour"
	if is_equal_approx(h, roundf(h)):
		return "about %d hours" % int(h)
	return "about %.1f hours" % h


func _make_caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.cond(700))
	l.add_theme_font_size_override("font_size", CAPTION_PX)
	l.add_theme_color_override("font_color", hud.PAPER_INK)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(hud.PAPER, 0.92)
	s.border_color = Color(hud.PAPER_INK, 0.35)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 0
	s.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", s)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	add_child(l)
	return l


func _point_at(id: String, on: bool) -> void:
	if on:
		hovered = id
	elif hovered == id:
		hovered = ""
	else:
		return
	place_hovered.emit(hovered)
	_place_captions()
	_over.queue_redraw()


func _focus_on(id: String, on: bool) -> void:
	if on:
		focused = id
	elif focused == id:
		focused = ""
	else:
		return
	place_hovered.emit(focused if focused != "" else hovered)
	_place_captions()
	for pin in pins.values():
		pin.queue_redraw()


# ----------------------------------------------------------------------- layout --

## Where a point of the board (tiles) is on the map (pixels).
func to_px(at: Vector2) -> Vector2:
	return _origin + at * _scale


## Pixels to a tile of the board.
func to_tile(px: Vector2) -> Vector2:
	return (px - _origin) / maxf(_scale, 0.0001)


## Pixels in a tile.
func scale_px() -> float:
	return _scale


func _layout() -> void:
	var room := size - Vector2(PAD, PAD) * 2.0
	if room.x <= 0.0 or room.y <= 0.0 or view.size.x <= 0.0 or view.size.y <= 0.0:
		return
	_scale = minf(room.x / view.size.x, room.y / view.size.y)
	_origin = (size - view.size * _scale) / 2.0 - view.position * _scale
	for id in pins:
		var pin: Control = pins[id]
		pin.size = Vector2(HIT, HIT)
		pin.position = to_px(pin.place.pos) - pin.size / 2.0
	home_marker.size = Vector2(HIT, HIT)
	home_marker.position = to_px(home) - home_marker.size / 2.0
	_fit_chip()
	_place_captions()
	queue_redraw()
	_over.queue_redraw()


## What the sheet shows (see the header): the school, the known places and the unknown places near a known one, with
## a margin, in a shape that is neither a thin strip nor a tall slab, inside the board.
func _fit_view() -> void:
	var known: Array = [home]
	for p in places:
		known.append(Vector2(p.pos))
	var box := Rect2(home, Vector2.ZERO)
	for k in known:
		box = box.expand(k)
	for u in unknown:
		var at := Vector2(u.pos)
		for k in known:
			if at.distance_to(k) <= NEAR_KNOWN:
				box = box.expand(at)
				break
	box = box.grow(VIEW_MARGIN)
	var w := maxf(box.size.x, VIEW_MIN.x)
	var h := maxf(box.size.y, VIEW_MIN.y)
	if h / w > ASPECT_MAX:
		w = h / ASPECT_MAX
	elif h / w < ASPECT_MIN:
		h = w * ASPECT_MIN
	w = minf(w, board.x)
	h = minf(h, board.y)
	var c := box.get_center()
	view = Rect2(Vector2(clampf(c.x - w / 2.0, 0.0, maxf(board.x - w, 0.0)), clampf(c.y - h / 2.0, 0.0, maxf(board.y - h, 0.0))), Vector2(w, h))


## Height over width of what the sheet shows: the page makes the map this shape.
func view_aspect() -> float:
	return view.size.y / maxf(view.size.x, 0.0001)


## The height a map of this width needs, and the width a map of this height needs, for the sheet to be filled
## (the pixels round the pins are not part of the shape).
func height_for_width(w: float) -> float:
	return maxf(w - PAD * 2.0, 1.0) * view_aspect() + PAD * 2.0


func width_for_height(h: float) -> float:
	return maxf(h - PAD * 2.0, 1.0) / view_aspect() + PAD * 2.0


## The width at which the closest two pins (the school too) are CLEAR_PX apart, so that none touches another.
func width_for_clear_pins() -> float:
	var spots: Array = [home]
	for p in places:
		spots.append(Vector2(p.pos))
	var nearest := INF
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			nearest = minf(nearest, Vector2(spots[i]).distance_to(spots[j]))
	if nearest == INF or nearest < 0.01:
		return 0.0
	return view.size.x * CLEAR_PX / nearest + PAD * 2.0


## The bridge of the board that is known (its place), or {}: the river is drawn through it.
func _bridge() -> Dictionary:
	for p in places:
		if String(p.get("kind", "")).to_lower().contains("bridge"):
			return p
	return {}


## Whether the chip "Across the river" shows: the bridge is known and no place across the river is.
func wants_chip() -> bool:
	if _bridge().is_empty():
		return false
	for p in places:
		if bool(p.get("needs_vehicle", false)):
			return false
	return true


## Where the chip goes: at the east edge, level with the bridge if that is free, else the nearest free height.
func _fit_chip() -> void:
	river_chip = Rect2()
	if not wants_chip() or size.x <= 0.0 or size.y <= 0.0:
		return
	var font := Fonts.cond(700)
	var w := font.get_string_size(CHIP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_PX).x + 12.0 + 14.0
	var h := 20.0
	var bridge_y := to_px(Vector2(_bridge().pos)).y
	var heights: Array = [bridge_y]
	for f in [0.5, 0.3, 0.7, 0.2, 0.8]:
		heights.append(size.y * float(f))
	var busy: Array = []
	for id in pins:
		var c := pin_center(id)
		busy.append(Rect2(c - Vector2(PIN_R, PIN_R) - Vector2(4, 4), Vector2(PIN_R, PIN_R) * 2.0 + Vector2(8, 8)))
	busy.append(Rect2(to_px(home) - Vector2(PIN_R, PIN_R) - Vector2(4, 4), Vector2(PIN_R, PIN_R) * 2.0 + Vector2(8, 8)))
	for u in unknown:
		var at := to_px(Vector2(u.pos))
		busy.append(Rect2(at - Vector2(10, 14), Vector2(20, 26)))
	busy.append(Rect2(size.x - 52.0, 2.0, 50.0, 62.0))
	var best := Rect2(size.x - w - 6.0, size.y - h - 6.0, w, h)
	for y in heights:
		var r := Rect2(size.x - w - 6.0, clampf(float(y) - h / 2.0, 4.0, size.y - h - 4.0), w, h)
		var free := true
		for b in busy:
			if b.intersects(r):
				free = false
				break
		if free:
			best = r
			break
	river_chip = best


## The centre of a pin on the map (pixels); the school's for "home".
func pin_center(id: String) -> Vector2:
	if id == "home":
		return to_px(home)
	return to_px(pins[id].place.pos) if pins.has(id) else Vector2.ZERO


## The captions that are showing, by place id (and "home").
func captions() -> Array:
	return _caption_ids.duplicate()


## Puts each name beside its pin where it fits: below, above, to the right, to the left, in that order of
## choice; a name that fits nowhere is left out unless the pin is hovered, chosen or has the keyboard. The pins
## nearest the school have their say first.
func _place_captions() -> void:
	_caption_ids.clear()
	for pin in pins.values():
		pin.get_meta("caption").visible = false
	home_marker.get_meta("caption").visible = false
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var many := size.x >= CAPTION_MIN_W
	var taken: Array = []
	if river_chip.size != Vector2.ZERO:
		taken.append(river_chip)
	# (the compass is not covered by a name)
	taken.append(Rect2(size.x - 44.0, 2.0, 42.0, 58.0))
	var discs: Dictionary = {"home": Rect2(to_px(home) - Vector2(PIN_R, PIN_R) - Vector2(3, 3), Vector2(PIN_R, PIN_R) * 2.0 + Vector2(6, 6))}
	for id in pins:
		var c := pin_center(id)
		discs[id] = Rect2(c - Vector2(PIN_R, PIN_R) - Vector2(3, 3), Vector2(PIN_R, PIN_R) * 2.0 + Vector2(6, 6))
	var order: Array = ["home"]
	var rest: Array = pins.keys()
	rest.sort_custom(func(a, b): return float(pins[a].place.get("hours", 0.0)) < float(pins[b].place.get("hours", 0.0)))
	for id in [chosen, hovered, focused]:
		if id != "" and pins.has(id) and not order.has(id):
			order.push_front(id)
	for id in rest:
		if not order.has(id):
			order.append(id)
	var always := [chosen, hovered, focused]
	for id in order:
		if id != "home" and not pins.has(id):
			continue
		var label: Label = home_marker.get_meta("caption") if id == "home" else pins[id].get_meta("caption")
		var must: bool = id != "home" and always.has(id)
		if not many and not must:
			continue
		var sz := label.get_combined_minimum_size()
		label.size = sz
		var c := pin_center(id)
		var gap := PIN_R + 4.0
		var tries := [
			Rect2(c + Vector2(-sz.x / 2.0, gap), sz),
			Rect2(c + Vector2(-sz.x / 2.0, -gap - sz.y), sz),
			Rect2(c + Vector2(gap, -sz.y / 2.0), sz),
			Rect2(c + Vector2(-gap - sz.x, -sz.y / 2.0), sz),
		]
		var inside := Rect2(Vector2.ZERO, size).grow(-2.0)
		var at := Rect2()
		var found := false
		for r in tries:
			if not inside.encloses(r):
				continue
			var clash := false
			for t in taken:
				if t.intersects(r):
					clash = true
					break
			if not clash:
				for other in discs:
					if other != id and discs[other].intersects(r):
						clash = true
						break
			if not clash:
				at = r
				found = true
				break
		if not found:
			if not must:
				continue
			# the pin the player is on gets its name wherever it fits on the sheet
			at = tries[0]
			for r in tries:
				if inside.encloses(r):
					at = r
					break
			at.position.x = clampf(at.position.x, 2.0, maxf(2.0, size.x - sz.x - 2.0))
			at.position.y = clampf(at.position.y, 2.0, maxf(2.0, size.y - sz.y - 2.0))
		label.position = at.position
		label.visible = true
		taken.append(at)
		_caption_ids.append(id)


# --------------------------------------------------------------------- decoration --

## Blocks and trees, laid out from a fixed seed, off the streets and the places: the same on every map. (It is
## done again only when the streets or the places change.)
func _decorate() -> void:
	var key := "%s|%s|%d|%d" % [str(board), str(home), streets.size(), places.size() + unknown.size()]
	if key == _decor_key:
		return
	_decor_key = key
	_blocks = []
	_trees = []
	var rng := RandomNumberGenerator.new()
	rng.seed = DECOR_SEED
	var spots: Array = [home]
	for p in places:
		spots.append(Vector2(p.pos))
	for u in unknown:
		spots.append(Vector2(u.pos))
	var cell_w := 9.0
	var cell_h := 8.0
	var gy := 0.0
	while gy + cell_h <= board.y + 0.01:
		var gx := 0.0
		while gx + cell_w <= board.x + 0.01:
			var n := rng.randi_range(1, 3)
			for i in n:
				var sz := Vector2(rng.randf_range(2.2, 4.6), rng.randf_range(1.8, 3.4))
				var at := Vector2(gx, gy) + Vector2(rng.randf_range(0.6, cell_w - sz.x - 0.6), rng.randf_range(0.6, cell_h - sz.y - 0.6))
				var r := Rect2(at, sz)
				if _free_of_things(r, spots, 1.5, 4.8) and not _touches(r.grow(0.5), _blocks):
					_blocks.append(r)
			gx += cell_w
		gy += cell_h
	# woods: a few clusters of trees, and the odd tree
	for k in 7:
		var centre := Vector2(rng.randf_range(3.0, board.x - 3.0), rng.randf_range(3.0, board.y - 3.0))
		for i in rng.randi_range(6, 11):
			var t := centre + Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-3.5, 3.5))
			var radius := rng.randf_range(0.7, 1.3)
			var tree_box := Rect2(t - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
			if t.x > 1.0 and t.y > 1.0 and t.x < board.x - 1.0 and t.y < board.y - 1.0 and _free_of_things(tree_box, spots, 1.2, 3.2) and not _touches(tree_box, _blocks):
				_trees.append({"at": t, "r": radius})
	for i in 40:
		var t := Vector2(rng.randf_range(1.5, board.x - 1.5), rng.randf_range(1.5, board.y - 1.5))
		var radius := rng.randf_range(0.6, 1.0)
		var lone_box := Rect2(t - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		if _free_of_things(lone_box, spots, 1.2, 3.2) and not _touches(lone_box, _blocks):
			_trees.append({"at": t, "r": radius})


## Whether a rectangle touches any of the others.
func _touches(r: Rect2, others: Array) -> bool:
	for o in others:
		if r.intersects(o):
			return true
	return false


## Whether a rectangle (tiles) is off every street by `road_gap` and off every spot (the school, the places) by
## `spot_gap` of its centre.
func _free_of_things(r: Rect2, spots: Array, road_gap: float, spot_gap: float) -> bool:
	var centre := r.get_center()
	for s in spots:
		if centre.distance_to(s) < spot_gap:
			return false
	var probes := [centre, r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]
	for seg in streets:
		for pt in probes:
			var nearest := Geometry2D.get_closest_point_to_segment(pt, seg[0], seg[1])
			if pt.distance_to(nearest) < road_gap:
				return false
	return true


# ------------------------------------------------------------------------ drawing --

func _draw() -> void:
	if hud == null:
		return
	var sheet := Rect2(Vector2.ZERO, size)
	draw_rect(sheet, SHEET)
	var field := Rect2(to_px(Vector2.ZERO), board * _scale)
	var bridge := _bridge()
	var river_x := float(bridge.pos.x) if not bridge.is_empty() else -1000.0
	# the town: blocks and trees (not in the river)
	for t in _trees:
		if absf(float(t.at.x) - river_x) < RIVER_W * 0.5 + float(t.r):
			continue
		draw_circle(to_px(t.at), float(t.r) * _scale, TREE_FILL)
	for b in _blocks:
		if absf(b.get_center().x - river_x) < RIVER_W * 0.5 + b.size.x * 0.5:
			continue
		var r := Rect2(to_px(b.position), b.size * _scale)
		draw_rect(r, BLOCK_FILL)
		draw_rect(r, BLOCK_EDGE, false, 1.0)
	# the border of the board, as a pencilled frame
	draw_rect(field.grow(2.0), Color(hud.PAPER_INK, 0.28), false, 1.0)
	if not bridge.is_empty():
		_draw_river(river_x)
	# the roads
	for r in roads:
		var a := to_px(r.a)
		var b := to_px(r.b)
		if bool(r.get("stub", false)):
			draw_dashed_line(a, b, STUB, 2.5, 6.0, true, true)
		else:
			draw_line(a, b, ROAD_EDGE, 7.0, true)
	for r in roads:
		if not bool(r.get("stub", false)):
			draw_line(to_px(r.a), to_px(r.b), ROAD_FILL, 4.2, true)
	if not bridge.is_empty():
		_draw_deck(Vector2(bridge.pos))
	# the places not known yet: a faint question mark
	var font := Fonts.cond(700)
	for u in unknown:
		var at := to_px(Vector2(u.pos))
		if at.x < -12.0 or at.y < -12.0 or at.x > size.x + 12.0 or at.y > size.y + 12.0:
			continue
		var sz := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
		draw_string(font, at + Vector2(-sz.x / 2.0, sz.y * 0.32), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UNKNOWN_INK)
	# the way to the city: the chip at the east edge
	if river_chip.size != Vector2.ZERO:
		_draw_chip(font)
	# the compass: north is up
	var rose := Vector2(size.x - 24.0, 36.0)
	draw_line(rose + Vector2(0, 14), rose + Vector2(0, -8), Color(hud.PAPER_INK, 0.6), 1.5, true)
	draw_colored_polygon(PackedVector2Array([rose + Vector2(0, -13), rose + Vector2(-4, -5), rose + Vector2(4, -5)]), Color(hud.PAPER_INK, 0.6))
	var nsz := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, rose + Vector2(-nsz.x / 2.0, -16.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hud.PAPER_INK2)
	draw_rect(Rect2(Vector2.ZERO, size), SHEET_EDGE, false, 1.5)


## The river through the bridge: a wavering band down the sheet, running north to south, with a bank on each side.
func _draw_river(x: float) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var mid := PackedVector2Array()
	var y := view.position.y - 1.0
	var end := view.position.y + view.size.y + 1.0
	while y <= end:
		var bend := sin(y * 0.28) * 0.7
		mid.append(to_px(Vector2(x + bend, y)))
		left.append(to_px(Vector2(x + bend - RIVER_W * 0.5, y)))
		right.append(to_px(Vector2(x + bend + RIVER_W * 0.5, y)))
		y += 1.0
	if mid.size() < 2:
		return
	draw_polyline(mid, Color(BLUE, 0.2), RIVER_W * _scale, true)
	draw_polyline(left, Color(BLUE, 0.45), 1.2, true)
	draw_polyline(right, Color(BLUE, 0.45), 1.2, true)


## The road over the river, drawn as a deck: on each bank the road that runs most nearly across the river, a wider, paler way
## between two dark rails.
func _draw_deck(at: Vector2) -> void:
	var best := {-1: Vector2.ZERO, 1: Vector2.ZERO}
	var reach := {-1: 0.0, 1: 0.0}
	for r in roads:
		var other := Vector2.INF
		if Vector2(r.a).distance_to(at) < 0.01:
			other = r.b
		elif Vector2(r.b).distance_to(at) < 0.01:
			other = r.a
		if other == Vector2.INF:
			continue
		var dir := (other - at).normalized()
		var side_of := 1 if dir.x >= 0.0 else -1
		if absf(dir.x) > absf(Vector2(best[side_of]).x):
			best[side_of] = dir
			reach[side_of] = minf(DECK_REACH, at.distance_to(other) * 0.5)
	for k in [-1, 1]:
		var dir: Vector2 = best[k]
		if dir == Vector2.ZERO:
			continue
		var a := to_px(at)
		var b := to_px(at + dir * float(reach[k]))
		var side := Vector2(-dir.y, dir.x)
		draw_line(a, b, OAK_DARK, 10.0, true)
		draw_line(a, b, ROAD_FILL, 6.4, true)
		draw_line(a + side * 4.2, b + side * 4.2, OAK_DARK, 1.4, true)
		draw_line(a - side * 4.2, b - side * 4.2, OAK_DARK, 1.4, true)


## "Across the river" with an arrow, on a small plate (ink on paper: 4.5 to 1 and more).
func _draw_chip(font: Font) -> void:
	var r := river_chip
	var style := StyleBoxFlat.new()
	style.bg_color = Color(hud.PAPER, 0.95)
	style.border_color = Color(BLUE, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	draw_style_box(style, r)
	var base := r.position.y + r.size.y / 2.0 + (font.get_ascent(CAPTION_PX) - font.get_descent(CAPTION_PX)) * 0.5
	draw_string(font, Vector2(r.position.x + 7.0, base), CHIP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_PX, hud.PAPER_INK)
	var tip := Vector2(r.end.x - 4.0, r.position.y + r.size.y / 2.0)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-6, -4.5), tip + Vector2(-6, 4.5)]), BLUE)


## The school, drawn on the pin's own square (HomeMarker).
func _paint_home(c: Control) -> void:
	var at := c.size / 2.0
	c.draw_circle(at + Vector2(0, 1.5), PIN_R + 1.0, Color(0, 0, 0, 0.2))
	c.draw_circle(at, PIN_R, hud.OAK)
	c.draw_arc(at, PIN_R, 0.0, TAU, 40, OAK_DARK, 1.6, true)
	draw_glyph(c, "school", at, PIN_R * 0.62, Color("#f6efd8"), hud.OAK)


## A pin: the disc (paler or greener or gold by how it stands), the icon of the kind of place, the marks, and a
## ring when it is chosen (gold) or has the keyboard (dark).
func _paint_pin(pin: Control) -> void:
	var p: Dictionary = pin.place
	var at := pin.size / 2.0
	var state := String(p.get("state", "known"))
	var ink: Color = hud.PAPER_INK
	var fill := CARD
	if state == "cleared":
		fill = CLEARED_FILL
	elif state == "claimed":
		fill = CLAIMED_FILL
	var is_chosen: bool = chosen == String(pin.id)
	# a place that only a vehicle can reach: a blue wash, and a blue ring of dashes round the dark one
	var by_vehicle := bool(p.get("needs_vehicle", false))
	if by_vehicle:
		fill = fill.lerp(VEHICLE_FILL, 0.8)
	if is_chosen:
		fill = fill.lerp(CLAIMED_FILL, 0.55)
	pin.draw_circle(at + Vector2(0, 1.5), PIN_R + 1.0, Color(0, 0, 0, 0.2))
	pin.draw_circle(at, PIN_R, fill)
	pin.draw_arc(at, PIN_R, 0.0, TAU, 40, Color(ink, 0.85), 1.6, true)
	if by_vehicle:
		draw_vehicle_ring(pin, at, PIN_R + 2.6)
	draw_glyph(pin, glyph_of(String(p.get("kind", ""))), at, PIN_R * 0.6, ink, fill)
	if is_chosen:
		pin.draw_arc(at, PIN_R + 4.0, 0.0, TAU, 48, GOLD_EDGE, 3.0, true)
	if pin.is_hovered() and not is_chosen:
		pin.draw_arc(at, PIN_R + 3.0, 0.0, TAU, 48, Color(ink, 0.45), 2.0, true)
	if pin.has_focus():
		pin.draw_arc(at, PIN_R + 7.0, 0.0, TAU, 48, ink, 2.0, true)
	# the marks sit over the rings
	var strength := int(p.get("nest", {}).get("strength", 0)) if p.get("nest", {}) is Dictionary else 0
	if strength > 0 and state != "cleared" and state != "claimed":
		_badge_nest(pin, at + Vector2(PIN_R * 0.82, -PIN_R * 0.82), strength)
	if state == "claimed":
		draw_badge(pin, "flag", at + Vector2(-PIN_R * 0.82, -PIN_R * 0.82), 7.0)
	if state == "cleared":
		draw_badge(pin, "tick", at + Vector2(PIN_R * 0.82, PIN_R * 0.82), 7.0)
	if (p.get("garrison", []) as Array).size() > 0:
		draw_badge(pin, "shield", at + Vector2(-PIN_R * 0.82, PIN_R * 0.82), 7.0)
	elif bool(p.get("survivor", false)):
		draw_badge(pin, "figure", at + Vector2(-PIN_R * 0.82, PIN_R * 0.82), 7.0)


func _badge_nest(c: CanvasItem, at: Vector2, strength: int) -> void:
	c.draw_circle(at, 8.5, RED)
	c.draw_arc(at, 8.5, 0.0, TAU, 24, Color("#f8f4e8"), 1.2, true)
	var font := Fonts.sans(600)
	var px := 12
	var text := str(strength)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var base := at.y + (font.get_ascent(px) - font.get_descent(px)) * 0.5
	c.draw_string(font, Vector2(at.x - w / 2.0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color("#ffffff"))


## The parties out, over everything else: the route they are on (dashed) and a blue disc with the number of people
## on it, a small arrow for the way they are going (none while they search the place).
func _paint_over(c: Control) -> void:
	for party in parties:
		var path: Array = party.path
		if path.size() < 2:
			continue
		var pts: Array = []
		for pt in path:
			pts.append(to_px(pt))
		for i in pts.size() - 1:
			c.draw_dashed_line(pts[i], pts[i + 1], Color(BLUE, 0.75), 2.5, 6.0, true, true)
		var at := _along(pts, float(party.at))
		var mode := String(party.mode)
		var font := Fonts.sans(600)
		var text := str(int(party.count))
		var kind := String(party.get("vehicle", ""))
		var reach := 17.0
		if kind != "":
			# by vehicle: a blue plate with a small car on it and the number of people beside it
			var plate := Rect2(at - Vector2(PLATE.x, PLATE.y) / 2.0, PLATE)
			c.draw_style_box(_plate_style(Color(0, 0, 0, 0.22)), Rect2(plate.position + Vector2(0, 1.5), plate.size))
			c.draw_style_box(_plate_style(BLUE), plate)
			draw_glyph(c, "bus" if kind.to_lower().contains("bus") else "car", plate.position + Vector2(13.0, PLATE.y / 2.0 - 0.5), 6.0, Color("#ffffff"), BLUE)
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var tbase := at.y + (font.get_ascent(12) - font.get_descent(12)) * 0.5
			c.draw_string(font, Vector2(plate.end.x - 7.0 - tw, tbase), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffffff"))
			reach = PLATE.x / 2.0 + 7.0
		else:
			c.draw_circle(at + Vector2(0, 1.5), 10.5, Color(0, 0, 0, 0.22))
			c.draw_circle(at, 10.0, BLUE)
			c.draw_arc(at, 10.0, 0.0, TAU, 28, Color("#ffffff"), 2.0, true)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var base := at.y + (font.get_ascent(12) - font.get_descent(12)) * 0.5
			c.draw_string(font, Vector2(at.x - w / 2.0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffffff"))
		if mode != "search":
			var ahead := _along(pts, clampf(float(party.at) + (0.04 if mode == "out" else -0.04), 0.0, 1.0))
			var dir := (ahead - at).normalized() if ahead.distance_to(at) > 0.01 else Vector2.RIGHT
			var tip := at + dir * reach
			var side := Vector2(-dir.y, dir.x)
			c.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 6.0 + side * 4.5, tip - dir * 6.0 - side * 4.5]), BLUE)
		elif kind != "":
			c.draw_style_box(_ring_style(), Rect2(at - Vector2(PLATE.x, PLATE.y) / 2.0 - Vector2(4, 4), PLATE + Vector2(8, 8)))
		else:
			c.draw_arc(at, 14.0, 0.0, TAU, 28, Color(BLUE, 0.8), 1.5, true)


## A party by vehicle: the plate on the road (pixels).
const PLATE := Vector2(42.0, 22.0)


static func _plate_style(color: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(8)
	if color.a >= 0.9:
		st.border_color = Color("#ffffff")
		st.set_border_width_all(2)
	return st


static func _ring_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.border_color = Color(BLUE, 0.8)
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	return st


## The point a fraction of the way along a polyline (by its length).
static func _along(pts: Array, frac: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	if pts.size() == 1:
		return pts[0]
	var total := 0.0
	for i in pts.size() - 1:
		total += Vector2(pts[i]).distance_to(pts[i + 1])
	var want := clampf(frac, 0.0, 1.0) * total
	for i in pts.size() - 1:
		var seg := Vector2(pts[i]).distance_to(pts[i + 1])
		if want <= seg or i == pts.size() - 2:
			return Vector2(pts[i]).lerp(pts[i + 1], clampf(want / maxf(seg, 0.0001), 0.0, 1.0))
		want -= seg
	return pts[pts.size() - 1]


## Where a party is on its route now, in pixels (for the tests and the page).
func party_position(n: int) -> Vector2:
	for party in parties:
		if int(party.n) == n:
			var pts: Array = []
			for pt in party.path:
				pts.append(to_px(pt))
			return _along(pts, float(party.at))
	return Vector2(-1, -1)


# ------------------------------------------------------------------------- icons --

static func glyph_of(kind: String) -> String:
	var k := kind.to_lower()
	for pair in GLYPHS:
		if k.contains(pair[0]):
			return pair[1]
	return "generic"


## The ring of dashes of a place that only a vehicle reaches (on the pin, and in the legend's key).
static func draw_vehicle_ring(c: CanvasItem, at: Vector2, radius: float) -> void:
	var n := 14
	for i in n:
		var a0 := TAU * float(i) / float(n)
		c.draw_arc(at, radius, a0, a0 + TAU / float(n) * 0.58, 4, BLUE, 2.2, true)


## A small mark on a pin (or in the legend): "tick", "flag", "figure" or "shield", on a round card of its own.
static func draw_badge(c: CanvasItem, mark: String, at: Vector2, r: float) -> void:
	match mark:
		"tick":
			c.draw_circle(at, r, GREEN)
			c.draw_arc(at, r, 0.0, TAU, 20, Color("#f8f4e8"), 1.2, true)
			c.draw_polyline(PackedVector2Array([at + Vector2(-0.5, 0.05) * r, at + Vector2(-0.12, 0.45) * r, at + Vector2(0.55, -0.4) * r]), Color("#ffffff"), 1.8, true)
		"flag":
			c.draw_circle(at, r, Color("#f8f4e8"))
			c.draw_arc(at, r, 0.0, TAU, 20, GOLD_EDGE, 1.4, true)
			c.draw_line(at + Vector2(-0.35, 0.65) * r, at + Vector2(-0.35, -0.65) * r, GOLD_EDGE, 1.6, true)
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-0.35, -0.65) * r, at + Vector2(0.55, -0.35) * r, at + Vector2(-0.35, -0.05) * r]), GOLD_EDGE)
		"figure":
			c.draw_circle(at, r, Color("#f8f4e8"))
			c.draw_arc(at, r, 0.0, TAU, 20, BLUE, 1.4, true)
			c.draw_circle(at + Vector2(0, -0.38) * r, r * 0.24, BLUE)
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-0.45, 0.62) * r, at + Vector2(0, -0.05) * r, at + Vector2(0.45, 0.62) * r]), BLUE)
		"shield":
			c.draw_circle(at, r, Color("#f8f4e8"))
			c.draw_arc(at, r, 0.0, TAU, 20, OAK_DARK, 1.4, true)
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-0.45, -0.5) * r, at + Vector2(0.45, -0.5) * r, at + Vector2(0.45, 0.1) * r, at + Vector2(0, 0.62) * r, at + Vector2(-0.45, 0.1) * r]), OAK_DARK)
		"nest":
			c.draw_circle(at, r, RED)
			c.draw_arc(at, r, 0.0, TAU, 20, Color("#f8f4e8"), 1.2, true)
		"party":
			c.draw_circle(at, r, BLUE)
			c.draw_arc(at, r, 0.0, TAU, 20, Color("#ffffff"), 1.6, true)


## A silhouette for a kind of place, in `ink`, with `paper` for the details cut out of it; `s` is its half size.
static func draw_glyph(c: CanvasItem, glyph: String, p: Vector2, s: float, ink: Color, paper: Color) -> void:
	var w := maxf(1.4, s * 0.17)
	match glyph:
		"house", "school":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-1.0, -0.05) * s, p + Vector2(0, -0.95) * s, p + Vector2(1.0, -0.05) * s]), ink)
			c.draw_rect(Rect2(p + Vector2(-0.7, -0.05) * s, Vector2(1.4, 0.95) * s), ink)
			c.draw_rect(Rect2(p + Vector2(-0.17, 0.35) * s, Vector2(0.34, 0.55) * s), paper)
			if glyph == "school":
				c.draw_circle(p + Vector2(0, -0.38) * s, s * 0.17, paper)
		"cross":
			c.draw_rect(Rect2(p + Vector2(-0.3, -0.95) * s, Vector2(0.6, 1.9) * s), ink)
			c.draw_rect(Rect2(p + Vector2(-0.95, -0.3) * s, Vector2(1.9, 0.6) * s), ink)
		"tool":
			c.draw_rect(Rect2(p + Vector2(-0.14, -0.4) * s, Vector2(0.28, 1.35) * s), ink)
			c.draw_rect(Rect2(p + Vector2(-0.85, -0.95) * s, Vector2(1.7, 0.62) * s), ink)
		"gear":
			for i in 8:
				var a := TAU * float(i) / 8.0
				c.draw_line(p + Vector2.from_angle(a) * 0.55 * s, p + Vector2.from_angle(a) * 1.0 * s, ink, s * 0.42, false)
			c.draw_circle(p, 0.7 * s, ink)
			c.draw_circle(p, 0.28 * s, paper)
		"church":
			c.draw_rect(Rect2(p + Vector2(-0.6, -0.05) * s, Vector2(1.2, 0.95) * s), ink)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.6, -0.05) * s, p + Vector2(0, -0.72) * s, p + Vector2(0.6, -0.05) * s]), ink)
			c.draw_rect(Rect2(p + Vector2(-0.07, -1.05) * s, Vector2(0.14, 0.45) * s), ink)
			c.draw_rect(Rect2(p + Vector2(-0.24, -0.93) * s, Vector2(0.48, 0.13) * s), ink)
			c.draw_rect(Rect2(p + Vector2(-0.16, 0.38) * s, Vector2(0.32, 0.52) * s), paper)
		"barn":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.95, 0.85) * s, p + Vector2(-0.95, -0.2) * s, p + Vector2(0, -0.95) * s, p + Vector2(0.95, -0.2) * s, p + Vector2(0.95, 0.85) * s]), ink)
			c.draw_rect(Rect2(p + Vector2(-0.3, 0.15) * s, Vector2(0.6, 0.7) * s), paper)
			c.draw_line(p + Vector2(-0.3, 0.15) * s, p + Vector2(0.3, 0.85) * s, ink, maxf(1.0, w * 0.6), true)
			c.draw_line(p + Vector2(0.3, 0.15) * s, p + Vector2(-0.3, 0.85) * s, ink, maxf(1.0, w * 0.6), true)
		"shield":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.8, -0.85) * s, p + Vector2(0.8, -0.85) * s, p + Vector2(0.8, 0.1) * s, p + Vector2(0, 1.0) * s, p + Vector2(-0.8, 0.1) * s]), ink)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -0.5) * s, p + Vector2(0.28, -0.05) * s, p + Vector2(0, 0.4) * s, p + Vector2(-0.28, -0.05) * s]), paper)
		"flame":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0.05, -1.0) * s, p + Vector2(0.6, -0.25) * s, p + Vector2(0.78, 0.35) * s, p + Vector2(0.4, 0.92) * s, p + Vector2(-0.4, 0.92) * s, p + Vector2(-0.78, 0.35) * s, p + Vector2(-0.45, -0.25) * s, p + Vector2(-0.12, 0.05) * s]), ink)
			c.draw_circle(p + Vector2(0, 0.45) * s, 0.28 * s, paper)
		"book":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-1.0, -0.6) * s, p + Vector2(-0.05, -0.4) * s, p + Vector2(-0.05, 0.8) * s, p + Vector2(-1.0, 0.6) * s]), ink)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(1.0, -0.6) * s, p + Vector2(0.05, -0.4) * s, p + Vector2(0.05, 0.8) * s, p + Vector2(1.0, 0.6) * s]), ink)
		"pump":
			c.draw_rect(Rect2(p + Vector2(-0.6, -0.9) * s, Vector2(1.0, 1.8) * s), ink)
			c.draw_rect(Rect2(p + Vector2(-0.4, -0.65) * s, Vector2(0.6, 0.55) * s), paper)
			c.draw_polyline(PackedVector2Array([p + Vector2(0.4, -0.4) * s, p + Vector2(0.8, -0.2) * s, p + Vector2(0.8, 0.55) * s]), ink, w, true)
		"car":
			c.draw_rect(Rect2(p + Vector2(-1.0, -0.05) * s, Vector2(2.0, 0.65) * s), ink)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.55, -0.05) * s, p + Vector2(-0.3, -0.62) * s, p + Vector2(0.4, -0.62) * s, p + Vector2(0.7, -0.05) * s]), ink)
			c.draw_circle(p + Vector2(-0.55, 0.65) * s, 0.27 * s, ink)
			c.draw_circle(p + Vector2(0.55, 0.65) * s, 0.27 * s, ink)
			c.draw_circle(p + Vector2(-0.55, 0.65) * s, 0.1 * s, paper)
			c.draw_circle(p + Vector2(0.55, 0.65) * s, 0.1 * s, paper)
		"bus":
			c.draw_rect(Rect2(p + Vector2(-1.0, -0.55) * s, Vector2(2.0, 1.05) * s), ink)
			for i in 3:
				c.draw_rect(Rect2(p + Vector2(-0.82 + 0.58 * float(i), -0.38) * s, Vector2(0.46, 0.38) * s), paper)
			c.draw_circle(p + Vector2(-0.55, 0.55) * s, 0.25 * s, ink)
			c.draw_circle(p + Vector2(0.55, 0.55) * s, 0.25 * s, ink)
			c.draw_circle(p + Vector2(-0.55, 0.55) * s, 0.09 * s, paper)
			c.draw_circle(p + Vector2(0.55, 0.55) * s, 0.09 * s, paper)
		"box":
			c.draw_rect(Rect2(p + Vector2(-0.95, -0.4) * s, Vector2(1.9, 1.3) * s), ink)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-1.0, -0.35) * s, p + Vector2(0, -0.95) * s, p + Vector2(1.0, -0.35) * s]), ink)
			c.draw_rect(Rect2(p + Vector2(-0.4, 0.2) * s, Vector2(0.8, 0.7) * s), paper)
		"cart":
			c.draw_polyline(PackedVector2Array([p + Vector2(-1.0, -0.8) * s, p + Vector2(-0.6, -0.8) * s, p + Vector2(-0.3, 0.35) * s, p + Vector2(0.8, 0.35) * s]), ink, w, true)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.52, -0.5) * s, p + Vector2(0.9, -0.5) * s, p + Vector2(0.75, 0.2) * s, p + Vector2(-0.3, 0.2) * s]), ink)
			c.draw_circle(p + Vector2(-0.15, 0.78) * s, 0.2 * s, ink)
			c.draw_circle(p + Vector2(0.6, 0.78) * s, 0.2 * s, ink)
		"mast":
			c.draw_line(p + Vector2(0, -0.45) * s, p + Vector2(-0.55, 0.95) * s, ink, w, true)
			c.draw_line(p + Vector2(0, -0.45) * s, p + Vector2(0.55, 0.95) * s, ink, w, true)
			c.draw_line(p + Vector2(-0.3, 0.3) * s, p + Vector2(0.3, 0.3) * s, ink, maxf(1.0, w * 0.7), true)
			c.draw_circle(p + Vector2(0, -0.55) * s, 0.16 * s, ink)
			c.draw_arc(p + Vector2(0, -0.55) * s, 0.55 * s, PI * 1.2, PI * 1.8, 10, ink, maxf(1.0, w * 0.7), true)
			c.draw_arc(p + Vector2(0, -0.55) * s, 0.95 * s, PI * 1.2, PI * 1.8, 12, ink, maxf(1.0, w * 0.7), true)
		"dome":
			var pts: Array = [p + Vector2(-1.0, 0.7) * s]
			for i in 13:
				var a := PI + PI * float(i) / 12.0
				pts.append(p + Vector2(cos(a), sin(a) * 1.15 + 0.7) * s)
			pts.append(p + Vector2(1.0, 0.7) * s)
			c.draw_colored_polygon(PackedVector2Array(pts), ink)
			c.draw_rect(Rect2(p + Vector2(-0.25, 0.15) * s, Vector2(0.5, 0.55) * s), paper)
			c.draw_rect(Rect2(p + Vector2(-1.0, 0.7) * s, Vector2(2.0, 0.2) * s), ink)
		"drop":
			var pts2: Array = [p + Vector2(0, -1.0) * s]
			for i in 17:
				var a := deg_to_rad(-40.0 + 260.0 * float(i) / 16.0)
				pts2.append(p + (Vector2(0, 0.28) + Vector2.from_angle(a) * 0.68) * s)
			c.draw_colored_polygon(PackedVector2Array(pts2), ink)
			c.draw_circle(p + Vector2(-0.2, 0.4) * s, 0.14 * s, paper)
		"loaf":
			var pts3: Array = []
			for i in 24:
				var a := TAU * float(i) / 24.0
				pts3.append(p + Vector2(cos(a) * 1.0, sin(a) * 0.62 + 0.1) * s)
			c.draw_colored_polygon(PackedVector2Array(pts3), ink)
			for i in 3:
				var x := -0.45 + 0.45 * float(i)
				c.draw_line(p + Vector2(x - 0.12, 0.28) * s, p + Vector2(x + 0.12, -0.12) * s, paper, maxf(1.0, w * 0.7), true)
		"arch":
			# a bridge: the deck, the arch under it and the two piers
			c.draw_rect(Rect2(p + Vector2(-1.0, -0.45) * s, Vector2(2.0, 0.3) * s), ink)
			c.draw_arc(p + Vector2(0, 0.85) * s, 0.78 * s, PI, TAU, 16, ink, maxf(1.6, s * 0.3), true)
			c.draw_rect(Rect2(p + Vector2(-0.95, -0.2) * s, Vector2(0.24, 1.1) * s), ink)
			c.draw_rect(Rect2(p + Vector2(0.71, -0.2) * s, Vector2(0.24, 1.1) * s), ink)
			c.draw_line(p + Vector2(-0.8, -0.95) * s, p + Vector2(-0.8, -0.45) * s, ink, maxf(1.0, w * 0.7), true)
			c.draw_line(p + Vector2(0.8, -0.95) * s, p + Vector2(0.8, -0.45) * s, ink, maxf(1.0, w * 0.7), true)
		"barrier":
			# a checkpoint: the guard post, and the boom raised over the road, striped
			c.draw_rect(Rect2(p + Vector2(-1.0, -0.4) * s, Vector2(0.62, 1.35) * s), ink)
			c.draw_rect(Rect2(p + Vector2(-0.85, -0.05) * s, Vector2(0.32, 0.3) * s), paper)
			var root := p + Vector2(-0.45, -0.3) * s
			var tip := p + Vector2(1.0, -0.85) * s
			var half := Vector2(0, 0.22) * s
			for i in 5:
				var q0 := root.lerp(tip, float(i) / 5.0)
				var q1 := root.lerp(tip, float(i + 1) / 5.0)
				c.draw_colored_polygon(PackedVector2Array([q0 - half, q1 - half, q1 + half, q0 + half]), ink if i % 2 == 0 else paper)
			c.draw_polyline(PackedVector2Array([root - half, tip - half, tip + half, root + half, root - half]), ink, maxf(1.0, w * 0.6), true)
			c.draw_line(p + Vector2(0.35, 0.95) * s, p + Vector2(0.35, 0.3) * s, ink, maxf(1.2, w * 0.9), true)
		"snow":
			# a cold store: a plain box with a snowflake in it
			c.draw_rect(Rect2(p + Vector2(-0.95, -0.85) * s, Vector2(1.9, 1.75) * s), ink)
			for i in 3:
				var a := PI * float(i) / 3.0 + PI / 6.0
				c.draw_line(p + Vector2(0, 0.02) * s + Vector2.from_angle(a) * 0.62 * s, p + Vector2(0, 0.02) * s - Vector2.from_angle(a) * 0.62 * s, paper, maxf(1.2, w * 0.8), true)
		"cap":
			# a university: a mortarboard with its tassel
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -0.8) * s, p + Vector2(1.05, -0.3) * s, p + Vector2(0, 0.2) * s, p + Vector2(-1.05, -0.3) * s]), ink)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-0.58, 0.0) * s, p + Vector2(0, 0.28) * s, p + Vector2(0.58, 0.0) * s, p + Vector2(0.58, 0.6) * s, p + Vector2(0, 0.88) * s, p + Vector2(-0.58, 0.6) * s]), ink)
			c.draw_line(p + Vector2(0.85, -0.2) * s, p + Vector2(0.85, 0.5) * s, ink, maxf(1.0, w * 0.7), true)
			c.draw_circle(p + Vector2(0.85, 0.58) * s, 0.14 * s, ink)
		"bolt":
			# a power station: a bolt of lightning
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0.2, -1.0) * s, p + Vector2(-0.62, 0.12) * s, p + Vector2(-0.04, 0.12) * s, p + Vector2(-0.3, 1.0) * s, p + Vector2(0.65, -0.24) * s, p + Vector2(0.04, -0.24) * s]), ink)
		"rails":
			# a rail yard: two rails running off, the sleepers across them
			for i in 5:
				var t := float(i) / 4.0
				var y := 0.85 - 1.7 * t
				var half := lerpf(0.62, 0.22, t)
				c.draw_line(p + Vector2(-half - 0.18, y) * s, p + Vector2(half + 0.18, y) * s, ink, maxf(1.2, w * 0.8), true)
			c.draw_line(p + Vector2(-0.62, 0.95) * s, p + Vector2(-0.22, -0.95) * s, ink, maxf(1.5, w * 1.1), true)
			c.draw_line(p + Vector2(0.62, 0.95) * s, p + Vector2(0.22, -0.95) * s, ink, maxf(1.5, w * 1.1), true)
		_:
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -0.95) * s, p + Vector2(0.8, 0) * s, p + Vector2(0, 0.95) * s, p + Vector2(-0.8, 0) * s]), ink)
			c.draw_circle(p, 0.25 * s, paper)


# ------------------------------------------------------------------- the parts --

## A pin: a button on the map that the mouse or the keyboard can press. It draws itself through the map.
class Pin:
	extends Button
	var map
	var id := ""
	var place := {}

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(36, 36)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())

	func _draw() -> void:
		if map != null:
			map._paint_pin(self)


## The school's pin: not pressed, but it has a tooltip.
class HomeMarker:
	extends Control
	var map

	func _init() -> void:
		mouse_default_cursor_shape = Control.CURSOR_ARROW

	func _draw() -> void:
		if map != null:
			map._paint_home(self)


## The layer over the pins: the parties on their routes.
class Over:
	extends Control
	var map

	func _draw() -> void:
		if map != null:
			map._paint_over(self)


## A small glyph for the legend under the map: a mark, a kind of pin, or the "?".
class Glyph:
	extends Control
	var mark := ""
	var hud

	func _init(m: String = "", h = null) -> void:
		mark = m
		hud = h
		custom_minimum_size = Vector2(22, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var at := size / 2.0
		match mark:
			"unknown":
				var font := Fonts.cond(700)
				var sz := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
				draw_string(font, at + Vector2(-sz.x / 2.0, sz.y * 0.3), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UNKNOWN_INK)
			"nest":
				draw_circle(at, 8.5, RED)
				draw_arc(at, 8.5, 0.0, TAU, 24, Color("#f8f4e8"), 1.2, true)
				var f := Fonts.sans(600)
				var w := f.get_string_size("2", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				draw_string(f, Vector2(at.x - w / 2.0, at.y + (f.get_ascent(12) - f.get_descent(12)) * 0.5), "2", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffffff"))
			"road":
				draw_line(Vector2(1, size.y - 4), Vector2(size.x - 1, 4), ROAD_EDGE, 6.0, true)
				draw_line(Vector2(1, size.y - 4), Vector2(size.x - 1, 4), ROAD_FILL, 3.4, true)
			"vehicle":
				# a place only a vehicle reaches: the blue wash and the ring of dashes
				draw_circle(at, 8.0, VEHICLE_FILL)
				draw_arc(at, 8.0, 0.0, TAU, 24, Color(0.2, 0.17, 0.1, 0.85), 1.4, true)
				Self.draw_vehicle_ring(self, at, 10.0)
			"car":
				# a party in a vehicle: the plate with the small car
				var plate := Rect2(at - Vector2(10.0, 7.0), Vector2(20.0, 14.0))
				draw_style_box(Self._plate_style(BLUE), plate)
				Self.draw_glyph(self, "car", plate.get_center() + Vector2(0, -0.5), 4.6, Color("#ffffff"), BLUE)
			_:
				Self.draw_badge(self, mark, at, 8.0)


## The key of the map for the foot of the page: what the marks mean, in a wrapping row.
static func make_legend(h, color: Color) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 0)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in [["tick", "Cleared"], ["flag", "Your outpost"], ["nest", "Nest (strength)"], ["figure", "Someone hiding"], ["shield", "Garrison"], ["party", "Party out"], ["car", "Party in a vehicle"], ["vehicle", "By vehicle only"], ["unknown", "Unexplored"]]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 3)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := Glyph.new(entry[0], h)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(g)
		item.add_child(h._label(entry[1], Fonts.sans(400), 12, color))
		flow.add_child(item)
	return flow
