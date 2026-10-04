extends VBoxContainer
## The Map page of the radio panel in the town (One House, WP7; key M): the town as a map of its streets and houses, for the player to see where they have
## been and what is left. The school's town_map.gd (the Town Board's map of the places on the road) is not touched; this is its own page.
##
## What it draws (all tiles of the 192 x 192 town, scaled to fit): the roads, every house as a faint block, the houses the player has been in (`clearing.explored()`
## house ids) as warm blocks, the BASE house in gold, the people the player knows of (`rescue.list()` records that are `wary` or `spoken`: seen, not yet home) as
## blue diamonds, the objective's place (`scenario.objective().at`) as a gold ring, and the player as an arrow. Under it a few lines: how many houses are looked
## in, the base's address, and the people known of with the house they are in. The pointer over a house says its address.
##
## It reads only (`sim.houses.town`, `sim.clearing`, `sim.base`, `sim.rescue`, `sim.scenario`, the avatar), all through `sim.get(...)`, so a module that is not there
## just means less on the map. One of the radio panel's pages: `setup(host, sim_getter, options)`, `refresh()`, `focus_on(id)`, `full_page()`, `set_compact(on)`.

const Fonts := preload("res://scripts/ui/fonts.gd")

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
	for item in [[HOUSE_SEEN, "Looked in"], [BASE_FILL, "Your base"], [KNOWN, "Someone waits"], [host.ACCENT, "You"]]:
		var one: HBoxContainer = host._hbox(5)
		var dot := ColorRect.new()
		dot.color = item[0]
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		one.add_child(dot)
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
	var sig := "%d|%d|%d|%d|%s" % [t.get("houses", []).size(), ex.size(), base_h, people.size(), str(player_at())]
	view.queue_redraw()
	if sig == _sig:
		return
	_sig = sig
	var total: int = t.get("houses", []).size()
	count_label.text = "%d of %d houses looked in" % [ex.size(), total] if total > 0 else "No map yet"
	base_label.text = ("Your base: %s" % address_of(base_h)) if base_h >= 0 else "You have no base yet. Clear a house and claim it."
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
			elif seen.has(id):
				draw_rect(r, HOUSE_SEEN)
				draw_rect(r, HOUSE_EDGE, false, 1.0)
			else:
				draw_rect(r, HOUSE_DIM)
		var target = page.objective_at()
		if target is Vector2:
			var c := _px(target)
			draw_arc(c, 8.0, 0.0, TAU, 24, Color(host.ACCENT, 0.9), 2.0, true)
			draw_arc(c, 12.0, 0.0, TAU, 24, Color(host.ACCENT, 0.4), 1.5, true)
		for p in page.known():
			var c2 := _px(p.pos)
			var d := PackedVector2Array([c2 + Vector2(0, -7), c2 + Vector2(6, 0), c2 + Vector2(0, 7), c2 + Vector2(-6, 0)])
			draw_colored_polygon(d, KNOWN)
			var closed := PackedVector2Array(d)
			closed.append(d[0])
			draw_polyline(closed, Color(0, 0, 0, 0.7), 1.5, true)
		var me = page.player_at()
		if me is Vector2:
			var c3 := _px(me)
			draw_circle(c3, 6.0, Color(0, 0, 0, 0.55))
			draw_colored_polygon(PackedVector2Array([c3 + Vector2(0, -6), c3 + Vector2(5, 5), c3 + Vector2(0, 2), c3 + Vector2(-5, 5)]), host.ACCENT)
		draw_rect(_rect, Color(host.INK, 0.25), false, 1.0)
		draw_string(Fonts.cond(700), _rect.position + Vector2(_rect.size.x - 20.0, 18.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(host.INK3, 0.9))

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
			if tip != tooltip_text:
				tooltip_text = tip

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
