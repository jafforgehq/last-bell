extends VBoxContainer
## The Map page of the radio panel in the town (One House, WP7; key M): the town as a map of its streets and houses, for the player to see where they have
## been and what is left. The school's town_map.gd (the Town Board's map of the places on the road) is not touched; this is its own page.
##
## What it draws (all tiles of the 192 x 192 town, scaled to fit): the roads, every house as a faint block, the houses the player has been in (`clearing.explored()`
## house ids) as warm blocks, the BASE house in gold, the people the player knows of (`rescue.list()` records that are `wary` or `spoken`: seen, not yet home) as
## blue diamonds, the objective's place (`scenario.objective().at`) as a gold ring, and the player as an arrow. Under it a few lines: how many houses are looked
## in, the base's address, and the people known of with the house they are in. The pointer over a house says its address.
##
## BEFORE A CLAIM (the arrival, scripts/town/arrival.gd) the houses the player may choose (the candidates) are pinned with a flag and their kind, the way in (the entry) has a small arrow, and above
## the map each candidate has its line ("Family home. 8 rooms, big yard.") with how far it is. Once there is a base they are gone.
##
## It reads only (`sim.houses.town`, `sim.clearing`, `sim.base`, `sim.rescue`, `sim.scenario`, the avatar), all through `sim.get(...)`, so a module that is not there
## just means less on the map. One of the radio panel's pages: `setup(host, sim_getter, options)`, `refresh()`, `focus_on(id)`, `full_page()`, `set_compact(on)`.

const Fonts := preload("res://scripts/ui/fonts.gd")
const Arrival := preload("res://scripts/town/arrival.gd")
const TierMarks := preload("res://scripts/ui/tier_marks.gd")
const MapMarks := preload("res://scripts/ui/map_marks.gd")

## The key's mark for a tier of house: its icon (a star, a circle or a square) in its colour.
class TierDot:
	extends Control
	const Marks := preload("res://scripts/ui/tier_marks.gd")
	var tier := "ok"

	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Marks.draw_icon(self, tier, size * 0.5, 6.0)


## The key's mark for everything else on the map, drawn with the same shapes the map draws them with (scripts/ui/map_marks.gd): so that the key shows the shape of each mark, not only its colour.
class KeyMark:
	extends Control
	const Marks := preload("res://scripts/ui/map_marks.gd")
	var kind := "seen"
	var accent := Color.WHITE

	func _init(p_kind: String = "seen", p_accent: Color = Color.WHITE) -> void:
		kind = p_kind
		accent = p_accent
		custom_minimum_size = Vector2(20, 16)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		match kind:
			"seen":
				Marks.seen(self, c)
			"base":
				Marks.base(self, c)
			"known":
				Marks.known(self, c, 0.85)
			"me":
				Marks.me(self, c, accent, 1.1)
			"goal":
				Marks.goal(self, c, accent, 0.7)
			"entry":
				Marks.entry(self, c, -PI / 2.0, Color(0.93, 0.95, 0.88, 0.85), 1.1)
			"dead":
				Marks.dead(self, c, 5.0)

const GROUND := Color(0.105, 0.17, 0.14, 1.0)
const ROAD := Color(0.07, 0.1, 0.09, 1.0)
const ROAD_LINE := Color(0.93, 0.96, 0.89, 0.07)
const HOUSE_DIM := Color(0.66, 0.68, 0.62, 0.26)
const HOUSE_SEEN := Color("#8a6238")
const HOUSE_EDGE := Color("#d2a94e")
const BASE_FILL := Color("#f0c24a")
const KNOWN := Color("#7fa6c9")
const MAP_H := 300.0

var host
var sim_getter: Callable
var options := {}
var view
var count_label: Label
var base_label: Label
var cand_box: VBoxContainer
var people_box: VBoxContainer
var _sig := ""
var _built := false


func setup(p_host, p_sim_getter: Callable, p_options: Dictionary = {}) -> void:
	host = p_host
	sim_getter = p_sim_getter
	options = p_options
	if _built:
		return
	_built = true
	_build()
	refresh()


func _sim():
	return sim_getter.call() if sim_getter.is_valid() else null


func _module(name: String):
	var s = _sim()
	return s.get(name) if s != null else null


func _build() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(host._label("THE TOWN", Fonts.cond(600, 1), 14, host.INK3))
	# (before a claim the houses to choose from are listed first: what each is, and how far, is what the player needs before the map)
	cand_box = host._vbox(2)
	add_child(cand_box)
	view = MapView.new()
	view.page = self
	view.custom_minimum_size = Vector2(0, MAP_H)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(view)
	count_label = host._label("", Fonts.cond(700), 15, host.INK)
	add_child(count_label)
	base_label = host._label("", Fonts.sans(400), 14, host.INK2)
	base_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	base_label.custom_minimum_size.x = 80
	add_child(base_label)
	people_box = host._vbox(2)
	add_child(people_box)
	_legend()


## A key under the map: what each mark is.
func _legend() -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# (every mark is drawn in the shape the map has for it, so the key tells shapes and not only colours. The houses to claim, by tier: a star, a circle, a square, as the pennants, the minimap and the
	# arrows at the screen's edge show them: scripts/ui/tier_marks.gd. The strings are the tiers; the rest are `KeyMark` kinds)
	for item in [["best", "Best house to claim"], ["ok", "Fair house"], ["poor", "Poor house"], ["seen", "Looked in"], ["base", "Your base"], ["known", "Someone waits"],
			["me", "You"], ["goal", "Goal"], ["entry", "Way in"], ["dead", "Dead awake (minimap)"]]:
		var one: HBoxContainer = host._hbox(5)
		var kind := String(item[0])
		if kind == "best" or kind == "ok" or kind == "poor":
			var mark := TierDot.new()
			mark.tier = kind
			one.add_child(mark)
		else:
			one.add_child(KeyMark.new(kind, host.ACCENT))
		one.add_child(host._label(String(item[1]), Fonts.sans(400), 14, host.INK2))
		row.add_child(one)
	add_child(row)


# ------------------------------------------------------------------------ the data --

func town() -> Dictionary:
	var houses = _module("houses")
	if houses == null or houses.get("town") == null:
		return {}
	return houses.town


## The ids of the houses the player has been in.
func explored() -> Array:
	var c = _module("clearing")
	if c != null and c.has_method("explored"):
		var got = c.explored()
		if got is Array:
			return got
	return []


func base_house() -> int:
	var b = _module("base")
	if b != null and b.get("claimed") == true and b.get("house") != null:
		return int(b.house)
	return -1


## The houses the player may still choose, before a claim: [{"house", "label", "dist", "tier", "pos": the middle of the house}] (nothing once there is a base, or in a town with no arrival).
func candidates() -> Array:
	var out: Array = []
	var t := town()
	if base_house() >= 0 or t.is_empty() or not t.has("start"):
		return out
	var me = player_at()
	for c in Arrival.candidates(t):
		var h := int(c.house)
		var mid := Vector2(Rect2i(t.houses[h].rect).get_center())
		out.append({"house": h, "label": String(c.get("label", "")), "tier": String(c.get("tier", "")), "pos": mid, "dist": (mid.distance_to(me) if me is Vector2 else float(c.get("dist", 0.0)))})
	return out


## Where the run began (a Vector2 and the way in), or null with no arrival: the small arrow on the map.
func entry_mark():
	var t := town()
	if t.is_empty() or not t.has("start") or base_house() >= 0:
		return null
	var road: Rect2i = Arrival.entry(t).get("road", Rect2i())
	if road.size == Vector2i.ZERO:
		return null    # (a town with no road in: the run began in a house)
	return Arrival.spawn(t)


## The survivors the player has seen and not brought home: [{"id", "house", "pos": Vector2, "name", "state"}].
func known() -> Array:
	var out: Array = []
	var r = _module("rescue")
	if r == null or not r.has_method("list"):
		return out
	for rec in r.list():
		var state := String(rec.get("state", ""))
		if state != "wary" and state != "spoken":
			continue
		var def = rec.get("def", {})
		var nm := String(def.get("name", "")) if def is Dictionary and state == "spoken" else ""
		out.append({"id": String(rec.get("id", "")), "house": int(rec.get("house", -1)), "pos": rec.get("pos", Vector2.ZERO), "name": nm if nm != "" else "Someone", "state": state})
	return out


func address_of(h: int) -> String:
	var houses = _module("houses")
	if houses != null and houses.has_method("house"):
		var hh = houses.house(h)
		if hh is Dictionary and not hh.is_empty():
			return String(hh.get("address", "House %d" % h))
	return "House %d" % h


func objective_at():
	var sc = _module("scenario")
	if sc != null and sc.has_method("objective"):
		var o = sc.objective()
		if o is Dictionary and o.get("at") is Vector2:
			return o.at
	return null


func player_at():
	var sim = _sim()
	if sim == null or sim.get("avatar") == null:
		return null
	var me = sim.avatar.player()
	return Vector2(me.x, me.y) if me != null else null


# ---------------------------------------------------------------------------- page --

func refresh() -> void:
	if host == null or not _built:
		return
	var t := town()
	var ex := explored()
	var base_h := base_house()
	var people := known()
	var cands := candidates()
	var sig := "%d|%d|%d|%d|%d|%s" % [t.get("houses", []).size(), ex.size(), base_h, people.size(), cands.size(), str(player_at())]
	view.queue_redraw()
	if sig == _sig:
		return
	_sig = sig
	var total: int = t.get("houses", []).size()
	count_label.text = "%d of %d houses looked in" % [ex.size(), total] if total > 0 else "No map yet"
	base_label.text = ("Your base: %s" % address_of(base_h)) if base_h >= 0 else ("Houses to choose from. Clear one and claim it." if not cands.is_empty() else "You have no base yet. Clear a house and claim it.")
	for c in cand_box.get_children():
		cand_box.remove_child(c)
		c.queue_free()
	for c in cands:
		var line: Label = host._label("%s  %d m" % [String(c.label), roundi(float(c.dist))], Fonts.sans(600), 14, TierMarks.color(String(c.tier)))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 80
		cand_box.add_child(line)
	for c in people_box.get_children():
		people_box.remove_child(c)
		c.queue_free()
	if people.is_empty():
		var none: Label = host._label("Nobody known of yet. Look in the houses.", Fonts.sans(400), 14, host.INK3)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size.x = 80
		people_box.add_child(none)
	for p in people:
		var l: Label = host._label("%s waits in %s" % [String(p.name), address_of(int(p.house))], Fonts.sans(600), 14, host.INFO)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 80
		people_box.add_child(l)


## The camera does not follow a house id here: the map only shows. (The page has no place to go to.)
func focus_on(_id: String) -> void:
	pass


func full_page() -> void:
	pass


func set_compact(_on: bool) -> void:
	pass


## The house whose block is under a point of the map control (the pointer), or -1.
func house_at_point(p: Vector2) -> int:
	return view.house_at_point(p) if view != null else -1


# ----------------------------------------------------------------------- the drawing --

class MapView:
	extends Control

	var page
	## The map's square on the control, and the size of the town in tiles (for the pointer's tile).
	var _rect := Rect2()
	var _size_tiles := 192.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _fit() -> void:
		var t: Dictionary = page.town()
		var sz = t.get("size", Vector2i(192, 192))
		_size_tiles = float(maxi(int(sz.x), 1))
		var side := minf(size.x, size.y)
		_rect = Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))

	func _px(tile: Vector2) -> Vector2:
		return _rect.position + tile / _size_tiles * _rect.size.x

	func _tile(px: Vector2) -> Vector2:
		return (px - _rect.position) / _rect.size.x * _size_tiles

	func _draw() -> void:
		if page == null or page.host == null:
			return
		var host = page.host
		_fit()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.18))
		draw_rect(_rect, GROUND)
		var t: Dictionary = page.town()
		if t.is_empty():
			draw_string(Fonts.sans(400), _rect.position + Vector2(12, 28), "No map yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, host.INK3)
			return
		var st: Dictionary = t.get("streets", {})
		var pitch := int(st.get("pitch", 32))
		var road := int(st.get("road", 4))
		var k := 0
		while 28 + pitch * k < int(_size_tiles):
			var a := 28 + pitch * k
			draw_rect(Rect2(_px(Vector2(a, 0)), Vector2(road, _size_tiles) / _size_tiles * _rect.size.x), ROAD)
			draw_rect(Rect2(_px(Vector2(0, a)), Vector2(_size_tiles, road) / _size_tiles * _rect.size.x), ROAD)
			draw_line(_px(Vector2(a + road * 0.5, 0)), _px(Vector2(a + road * 0.5, _size_tiles)), ROAD_LINE, 1.0)
			draw_line(_px(Vector2(0, a + road * 0.5)), _px(Vector2(_size_tiles, a + road * 0.5)), ROAD_LINE, 1.0)
			k += 1
		var seen := {}
		for h in page.explored():
			seen[int(h)] = true
		var base_h: int = page.base_house()
		for h in t.get("houses", []):
			var id := int(h.id)
			var r := Rect2(_px(Vector2(Rect2i(h.rect).position)), Vector2(Rect2i(h.rect).size) / _size_tiles * _rect.size.x)
			# a house is at least a few pixels across on a small map
			if r.size.x < 4.0:
				r = Rect2(r.get_center() - Vector2(2, 2), Vector2(4, 4))
			if id == base_h:
				draw_rect(r.grow(1.5), BASE_FILL)
				draw_rect(r.grow(1.5), Color(0, 0, 0, 0.6), false, 1.0)
				MapMarks.house(self, r.get_center(), clampf(minf(r.size.x, r.size.y) * 0.4, 3.0, 7.0))    # (a house on the gold block: the base is a shape too)
			elif seen.has(id):
				draw_rect(r, HOUSE_SEEN)
				draw_rect(r, HOUSE_EDGE, false, 1.0)
			else:
				draw_rect(r, HOUSE_DIM)
		var target = page.objective_at()
		if target is Vector2:
			MapMarks.goal(self, _px(target), host.ACCENT)
		_draw_arrival(host)
		for p in page.known():
			MapMarks.known(self, _px(p.pos))
		var me = page.player_at()
		if me is Vector2:
			MapMarks.me(self, _px(me), host.ACCENT)
		draw_rect(_rect, Color(host.INK, 0.25), false, 1.0)
		draw_string(Fonts.cond(700), _rect.position + Vector2(_rect.size.x - 20.0, 18.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(host.INK3, 0.9))

	## Before a claim: the way in (a small arrow where the run began) and a flag on each house that may be chosen, with its kind beside it.
	func _draw_arrival(host) -> void:
		var entry = page.entry_mark()
		if entry is Dictionary:
			MapMarks.entry(self, _px(entry.pos), float(entry.angle), Color(host.INK, 0.85))
		var font := Fonts.cond(700)
		var placed: Array = []    # (the rectangles of the names drawn: the houses of a row are near each other, and a name goes where it covers no other)
		for c in page.candidates():
			var foot := _px(c.pos)
			var top := foot + Vector2(0, -13)
			var tier_col := TierMarks.color(String(c.tier))
			draw_line(foot, top, Color(0, 0, 0, 0.7), 3.5, true)
			draw_line(foot, top, tier_col, 1.5, true)
			var flag := PackedVector2Array([top, top + Vector2(9, 3.5), top + Vector2(0, 7)])
			draw_colored_polygon(flag, tier_col)
			var rim2 := PackedVector2Array(flag)
			rim2.append(flag[0])
			draw_polyline(rim2, Color(0, 0, 0, 0.8), 1.2, true)
			var name := String(c.label).get_slice(". ", 0)
			# (the tier's icon before the name, and under the colour-blind setting its letter too)
			var lead := 12.0 + (10.0 if TierMarks.letters_on() else 0.0)
			var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + lead
			var spots := [Vector2(foot.x - w * 0.5, top.y - 4.0), Vector2(foot.x - w * 0.5, foot.y + 14.0), Vector2(foot.x + 12.0, top.y + 8.0), Vector2(foot.x - w - 6.0, top.y + 8.0), Vector2(foot.x - w * 0.5, top.y - 18.0), Vector2(foot.x - w * 0.5, foot.y + 28.0)]
			var at2: Vector2 = spots[0]
			for s in spots:
				var p := Vector2(clampf(s.x, _rect.position.x + 2.0, _rect.end.x - w - 2.0), s.y)
				var box := Rect2(p.x - 1.0, p.y - 11.0, w + 2.0, 14.0)
				var free := true
				for other in placed:
					if box.intersects(other):
						free = false
				if free:
					at2 = p
					break
			placed.append(Rect2(at2.x - 1.0, at2.y - 11.0, w + 2.0, 14.0))
			var name_at := at2 + Vector2(lead, 0.0)
			TierMarks.draw_icon(self, String(c.tier), at2 + Vector2(5.5, -4.0), 4.6)
			if TierMarks.letters_on():
				draw_string_outline(font, at2 + Vector2(12.0, 0.0), TierMarks.letter(String(c.tier)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
				draw_string(font, at2 + Vector2(12.0, 0.0), TierMarks.letter(String(c.tier)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tier_col)
			draw_string_outline(font, name_at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
			draw_string(font, name_at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, host.INK)

	## The house whose footprint (a little grown) holds the control's point, or -1.
	func house_at_point(p: Vector2) -> int:
		_fit()
		if not _rect.has_point(p):
			return -1
		var tile := _tile(p)
		var t: Dictionary = page.town()
		for h in t.get("houses", []):
			if Rect2(Rect2i(h.rect)).grow(1.5).has_point(tile):
				return int(h.id)
		return -1

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			var h := house_at_point((ev as InputEventMouseMotion).position)
			var tip := ""
			if h >= 0:
				tip = page.address_of(h)
				if h == page.base_house():
					tip += ": your base"
				elif page.explored().has(h):
					tip += ": looked in"
				for c in page.candidates():
					if int(c.house) == h:
						tip += ": " + String(c.label)
			if tip != tooltip_text:
				tooltip_text = tip

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
