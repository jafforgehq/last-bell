## The map on the Build screen (round 9, the lots; round 15: the classic start has it too, the yard only): the yard, or the whole
## block (84 by 64 tiles: the compound in its ring of streets), drawn from the world's own ground (a small picture of the terrain
## made when the screen opens), the compound's walls, the ten places where the dead come in, and the plots as pins (round 15: a
## plot of the yard or the ring is the home of a building, and the chosen building's is the one that is lit):
##   - a plot of the yard or of the ring: a lot drawn at its size, faint while empty, gold with a bar along its foot while a site is
##     going up (the share done), oak when a building stands;
##   - a mouth (a wall across a street, in the lot's streets): a line across the street, amber and dashed while it is open, gold
##     (filled as far as the work has come) while a wall goes up, green, amber or red by the health of the wall that stands, and
##     red and dashed once it is down;
##   - a lot that is not claimed yet: its plots and mouths faint and dashed, not to be pointed at (they are the shape of what a
##     claim would bring); the lot the Build screen points at is lit.
## The plot that is chosen has a gold edge; the one the pointer or the keyboard is on is lit and marked in the world; and for a
## mouth the spawn point of the dead who come to it is ringed in red.
##
## Every pin is a control the mouse and the keyboard can have (Tab goes through them; Enter or Space chooses one), its tooltip says
## what it is. `picked(id)` is sent when one is chosen, `pointed(id)` when the pointer or the keyboard comes to one ("" when it
## leaves). A view only: nothing here changes the rules.
extends Control

const Kit := preload("res://scripts/ui/menu_kit.gd")

signal picked(plot_id: String)
signal pointed(plot_id: String)

## The block and the yard (tiles): what the two zoom levels show.
const BLOCK := Rect2(0.0, 0.0, 84.0, 64.0)
const YARD := Rect2(18.0, 16.0, 48.0, 31.0)
## The map is at least this tall and at most this tall (pixels); its width follows the shape of what it shows.
const MIN_H := 170.0
const MAX_H := 320.0
## A pin is at least this big for the pointer (pixels).
const PIN_MIN := 18.0
## The colours: the slate behind, the gold of the chosen, the amber of an open street, the red of a wall that is down, the green
## of a wall that stands.
const BACK := Color("#161c1a")
const GOLD := Color("#f0c24a")
const AMBER := Color("#e8953a")
const RED := Color("#e0584a")
const GREEN := Color("#9cc46a")
const PAPER := Color("#eeeadd")
const OAK := Color("#b07a44")
const WALL := Color("#ece3cc")
## The ground, by terrain id (assets/data/map.json terrainTypes): asphalt, sidewalk, yard, grass, soil, lino, terrazzo, wood, roof,
## roof light, kitchen, concrete, dirt. A tile of no terrain is the dark of the map's edge.
const GROUND := {
	1: Color("#4a5057"), 2: Color("#7d7e78"), 3: Color("#5d5f5f"), 4: Color("#566f46"), 5: Color("#5a4b38"), 6: Color("#8f8570"),
	7: Color("#9a9684"), 8: Color("#8c6f48"), 9: Color("#68645c"), 10: Color("#78746a"), 11: Color("#9a9684"), 12: Color("#6f706c"),
	13: Color("#6e5d44"),
}
## How strongly the things drawn on the ground show: the plots that cannot be had yet, and the ones that are open.
const FAINT := 0.38

var screen
var sim
var build
## Whether the whole block is shown (else the yard).
var whole := false
## How tall the map may be now (the screen gives it a share of the room the columns have).
var max_h := MAX_H
## The plot that is chosen, the one the pointer or the keyboard is on, and the lot the page points at ("" for none of them).
var selected := ""
var hover := ""
var lit_lot := ""
## plot id -> the pin (a flat Button over the plot, for the pointer and the keyboard).
var pins := {}
var _ground: ImageTexture
var _view := BLOCK
var _scale := 1.0
var _origin := Vector2.ZERO
var _spawns: Array = []


## `s` is the Build screen, `rules` the game.
func setup(s, rules) -> void:
	screen = s
	sim = rules
	build = sim.build
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_PASS
	_ground = _make_ground()
	var raw = sim.world.d.get("spawns", []) if sim.world != null and sim.world.d != null else []
	_spawns = raw if raw is Array else []
	for id in _all_plot_ids():
		_make_pin(String(id))
	resized.connect(_place)
	set_whole(false)


## The picture of the ground: a pixel for each tile of the world.
func _make_ground() -> ImageTexture:
	var w: int = int(sim.world.W)
	var h: int = int(sim.world.H)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.08, 0.07))
	for y in h:
		for x in w:
			var t: int = int(sim.world.terrain[y * w + x])
			if GROUND.has(t):
				img.set_pixel(x, y, GROUND[t])
	return ImageTexture.create_from_image(img)


## The ids of every plot there is, the lots' too (the ones of a lot that is not claimed are known but not open).
func _all_plot_ids() -> Array:
	var out: Array = []
	for pl in build.plots():
		if String(pl.get("lot", "")) == "":
			out.append(String(pl.id))
	for l in sim.lots.lots():
		for id in l.get("plots", []):
			out.append(String(id))
		for id in l.get("mouths", []):
			out.append(String(id))
	return out


func _make_pin(id: String) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.set_meta("pin", id)
	var none := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, none)
	b.add_theme_stylebox_override("focus", Kit.focus_box(GOLD, 4))
	b.pressed.connect(func(): picked.emit(id))
	b.mouse_entered.connect(_on_pin_point.bind(id, true))
	b.mouse_exited.connect(_on_pin_point.bind(id, false))
	b.focus_entered.connect(_on_pin_point.bind(id, true))
	b.focus_exited.connect(_on_pin_point.bind(id, false))
	add_child(b)
	pins[id] = b


func _on_pin_point(id: String, on: bool) -> void:
	if on:
		hover = id
		pointed.emit(id)
	elif hover == id:
		hover = ""
		pointed.emit("")
	queue_redraw()


# ------------------------------------------------------------------ the view --

## Zooms to the whole block (true) or the yard (false).
func set_whole(on: bool) -> void:
	whole = on
	_view = BLOCK if on else YARD
	custom_minimum_size.y = height_for(size.x if size.x > 1.0 else 420.0)
	_place()
	queue_redraw()


## How tall the map is for a width: the shape of what it shows, kept between MIN_H and MAX_H.
func height_for(width: float) -> float:
	return clampf(width * _view.size.y / _view.size.x, MIN_H, maxf(MIN_H, max_h))


func _place() -> void:
	if size.x < 1.0:
		return
	var want := height_for(size.x)
	if absf(custom_minimum_size.y - want) > 0.5:
		custom_minimum_size.y = want
	if size.y < 1.0:
		return
	_scale = minf(size.x / _view.size.x, size.y / _view.size.y)
	_origin = (size - _view.size * _scale) / 2.0
	for id in pins:
		var pin: Button = pins[id]
		var pl: Dictionary = build.plot(String(id))
		var open := _is_open(pl)
		pin.visible = open and _in_view(pl)
		if not pin.visible:
			continue
		var r := pin_rect(String(id))
		pin.position = r.position
		pin.size = r.size
		pin.tooltip_text = tooltip_of(String(id))
	queue_redraw()


func _in_view(pl: Dictionary) -> bool:
	if pl.is_empty():
		return false
	if whole:
		return true
	return String(pl.get("lot", "")) == "" and _view.grow(2.0).has_point(Vector2(pl.pos))


## Whether the plot is open to use (the yard's, or a lot's that is claimed).
func _is_open(pl: Dictionary) -> bool:
	return not pl.is_empty() and sim.lots.plot_open(pl)


func to_local_tile(t: Vector2) -> Vector2:
	return _origin + (t - _view.position) * _scale


## The rectangle of a plot on the map (a mouth is drawn along its street): at least PIN_MIN each way for the pointer.
func pin_rect(id: String) -> Rect2:
	var pl: Dictionary = build.plot(id)
	if pl.is_empty():
		return Rect2()
	var half := Vector2(pl.size) / 2.0
	var a := to_local_tile(Vector2(pl.pos) - half)
	var b := to_local_tile(Vector2(pl.pos) + half)
	var r := Rect2(a, b - a)
	var grow := Vector2(maxf(0.0, PIN_MIN - r.size.x), maxf(0.0, PIN_MIN - r.size.y)) / 2.0
	return r.grow_individual(grow.x, grow.y, grow.x, grow.y)


# ------------------------------------------------------------------- the state --

## What a plot is now: "empty", "site", "built" (a plot with a building), "open" (a mouth with no wall and no site), "wall" (a
## mouth with a wall that stands), "down" (a mouth whose wall has fallen), "locked" (a plot of a lot that is not claimed).
func state_of(id: String) -> String:
	var pl: Dictionary = build.plot(id)
	if pl.is_empty():
		return ""
	if not _is_open(pl):
		return "locked"
	var mouth: bool = String(pl.kind) == "mouth"
	if not pl.site.is_empty():
		return "site"
	if String(pl.building) != "":
		if mouth:
			var seg = sim.lots.segment_at(id)
			return "down" if seg != null and int(seg.state) == 3 else "wall"
		return "built"
	return "open" if mouth else "empty"


## The health of the wall at a mouth, 0 to 1 (1 when there is none).
func health_of(id: String) -> float:
	var seg = sim.lots.segment_at(id)
	return 1.0 if seg == null else clampf(float(seg.hp) / maxf(1.0, float(seg.max_hp)), 0.0, 1.0)


## The words of a plot's tooltip: for a building's home, the building and where it goes, and what is on it.
func tooltip_of(id: String) -> String:
	var pl: Dictionary = build.plot(id)
	var what := ""
	match state_of(id):
		"empty":
			what = "not built yet"
		"open":
			what = "open street"
		"site":
			what = "%s going up, %d%%" % [String(build.building(String(pl.site.building)).name).to_lower(), mini(99, floori(build.progress_of(id) * 100.0))]
		"built":
			what = String(build.building(String(pl.building)).name).to_lower()
		"wall":
			what = "%s, %d%% health" % [String(build.building(String(pl.building)).name).to_lower(), roundi(health_of(id) * 100.0)]
		"down":
			what = "wall down: the street is open"
		_:
			what = "not claimed yet"
	if String(pl.get("home", "")) != "":
		return "%s, %s: %s" % [String(build.title_of(id)), String(pl.name), what]
	return "%s: %s" % [String(pl.name), what]


## The plots drawn as pins now (those that are in view and open): for the tests.
func visible_pins() -> Array:
	var out: Array = []
	for id in pins:
		if pins[id].visible:
			out.append(String(id))
	return out


## The colour a mouth's line is drawn in now.
func mouth_color(id: String) -> Color:
	match state_of(id):
		"open":
			return AMBER
		"site":
			return GOLD
		"down":
			return RED
		"wall":
			var h := health_of(id)
			return RED if h < 0.34 else (AMBER if h < 0.67 else GREEN)
	return Color(PAPER, FAINT)


# ------------------------------------------------------------------- drawing --

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	if _ground == null or _scale <= 0.0:
		return
	var dest := Rect2(_origin, _view.size * _scale)
	draw_texture_rect_region(_ground, dest, _view.intersection(BLOCK))
	_draw_walls()
	for id in _all_plot_ids():
		var pl: Dictionary = build.plot(String(id))
		if not _in_view(pl):
			continue
		if String(pl.kind) == "mouth":
			_draw_mouth(String(id), pl)
		else:
			_draw_plot(String(id), pl)
	_draw_spawns()


## The compound's own wall sections: dark while they stand, amber or red as they wear, red and hollow when they are down.
func _draw_walls() -> void:
	for s in sim.segments:
		if int(s.id) >= 100:
			continue    # (the walls of the lots are drawn with their mouths)
		var o: Dictionary = s.obj
		var hw: float = absf(cos(o.a)) * o.w / 2.0 + absf(sin(o.a)) * o.h / 2.0
		var hh: float = absf(sin(o.a)) * o.w / 2.0 + absf(cos(o.a)) * o.h / 2.0
		var a := to_local_tile(Vector2(o.cx - hw, o.cy - hh))
		var b := to_local_tile(Vector2(o.cx + hw, o.cy + hh))
		var r := Rect2(a, b - a)
		if int(s.state) == 3:
			draw_rect(r, Color(RED, 0.9), false, 1.5)
			continue
		var f: float = float(s.hp) / maxf(1.0, float(s.max_hp))
		draw_rect(r, WALL if f >= 0.67 else (AMBER if f >= 0.34 else RED))
		draw_rect(r, Color(BACK, 0.7), false, 1.0)


## A plot of the yard or the ring.
func _draw_plot(id: String, pl: Dictionary) -> void:
	var r := _rect_of(pl)
	var st := state_of(id)
	var lit: bool = id == hover or id == selected or (lit_lot != "" and String(pl.get("lot", "")) == lit_lot)
	if st == "locked":
		_dashed_rect(r, Color(PAPER, 0.9 if lit_lot == String(pl.get("lot", "")) and lit_lot != "" else FAINT), 1.0)
		return
	match st:
		"empty":
			draw_rect(r, Color(PAPER, 0.16))
			_dashed_rect(r, Color(PAPER, 0.85), 1.0)
		"site":
			draw_rect(r, Color(GOLD, 0.3))
			draw_rect(r, Color(GOLD, 0.95), false, 1.0)
			var share: float = build.progress_of(id)
			draw_rect(Rect2(r.position.x, r.end.y - 4.0, r.size.x * share, 4.0), GOLD)
		"built":
			draw_rect(r, Color(OAK, 0.95))
			draw_rect(r, Color(BACK, 0.9), false, 1.0)
	if lit:
		draw_rect(r.grow(2.0), Color(GOLD, 0.95 if id == selected else 0.7), false, 2.0)


## A mouth: the line across its street (a wall's thickness, drawn thinner), filled as the work goes on.
func _draw_mouth(id: String, pl: Dictionary) -> void:
	var st := state_of(id)
	var horizontal: bool = String(pl.get("dir", "h")) == "h"
	var c := Vector2(pl.pos)
	var half := Vector2(pl.size) / 2.0
	var a := to_local_tile(c - (Vector2(half.x, 0.0) if horizontal else Vector2(0.0, half.y)))
	var b := to_local_tile(c + (Vector2(half.x, 0.0) if horizontal else Vector2(0.0, half.y)))
	var lit: bool = id == hover or id == selected or (lit_lot != "" and String(pl.get("lot", "")) == lit_lot)
	var col := mouth_color(id)
	var width := 5.0
	if st == "locked":
		col = Color(PAPER, 0.9 if lit_lot == String(pl.get("lot", "")) and lit_lot != "" else FAINT)
		_dashed_line(a, b, col, 3.0)
		return
	if lit:
		var back := Rect2(minf(a.x, b.x), minf(a.y, b.y), absf(b.x - a.x), absf(b.y - a.y)).grow(5.0)
		draw_rect(back, Color(GOLD, 0.95 if id == selected else 0.6), false, 2.0)
	match st:
		"open", "down":
			_dashed_line(a, b, col, width)
		"site":
			draw_line(a, b, Color(GOLD, 0.35), width)
			draw_line(a, a.lerp(b, build.progress_of(id)), GOLD, width)
		"wall":
			draw_line(a, b, col, width + 1.0)
			draw_line(a, b, Color(BACK, 0.55), 1.0)


func _rect_of(pl: Dictionary) -> Rect2:
	var half := Vector2(pl.size) / 2.0
	var a := to_local_tile(Vector2(pl.pos) - half)
	var b := to_local_tile(Vector2(pl.pos) + half)
	return Rect2(a, b - a)


func _dashed_rect(r: Rect2, col: Color, width: float) -> void:
	var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		_dashed_line(p[i], p[(i + 1) % 4], col, width)


func _dashed_line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var dist := a.distance_to(b)
	if dist < 0.5:
		return
	var dir := (b - a) / dist
	var t := 0.0
	var dash := maxf(3.0, 2.0 * width)
	while t < dist:
		var t1 := minf(dist, t + dash)
		draw_line(a + dir * t, a + dir * t1, col, width)
		t += dash * 1.8


## The ten places the dead come in at (whole block only): a small red wedge; the one that comes to the chosen mouth is ringed.
func _draw_spawns() -> void:
	if not whole:
		return
	var chosen := -1
	var pl: Dictionary = build.plot(selected)
	if not pl.is_empty() and String(pl.kind) == "mouth":
		chosen = int(sim.lots.mouth(selected).get("spawn", -1))
	for i in _spawns.size():
		var at := to_local_tile(Vector2(float(_spawns[i][0]), float(_spawns[i][1])))
		draw_circle(at, 3.0, Color(RED, 0.95))
		if i == chosen:
			draw_arc(at, 8.0, 0.0, TAU, 24, Color(RED, 0.95), 2.0, true)
			draw_arc(at, 11.0, 0.0, TAU, 24, Color(RED, 0.5), 1.0, true)


## The pins and the picture follow the game (called when the screen is refreshed).
func refresh() -> void:
	_place()
