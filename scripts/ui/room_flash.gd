## Clearing a house, felt (One House, WORLD): a VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`, `on_event(e)`). It reads the
## rules' events (`room_clear`, `house_clear`) and state (`sim.clearing.is_clear`, `house_clear`; `sim.houses.rooms_of`, `room`, `house`) and writes nothing in them.
##
##   - `room_clear`: the room's outline flashes gold for FLASH_S (0.8 s): a soft, short pulse along the floor's edge with a faint gold wash, and a small CHIP under the objective card for
##     CHIP_S (3 s): "Kitchen clear: 3 of 8 rooms". (The town HUD's toast of the same news stays quiet while this part is there.)
##   - `house_clear`: a bigger gold SWEEP across the whole footprint, left to right, SWEEP_S (1.1 s), over a gold outline of the walls. The banner "The house is clear" is the town HUD's and
##     stays: the sweep adds no words.
##   - the faint GOLD CORNERS of each room that is clear, drawn while the avatar is inside that house and the house is not clear yet, so that a glance says which rooms remain. Once the
##     house is clear (and when it is the base) they are gone.
## REDUCE MOTION (Settings `ui/reduce_motion`) and REDUCE FLASHES (`ui/reduce_flashes`): nothing moves or fades. A room's flash is a still gold outline held for the same time and then gone; the
## sweep is a still outline of the footprint (no band); the chip appears and goes without fading; the corners are as they are.
## COST. One Node2D in the overlay's canvas layer (one more canvas item: a few draw calls); the flashes are a pool of six made once, the sweep's two quads reuse their arrays, the corners
## are drawn with `draw_line` (nothing is allocated in a frame), and the node is redrawn only while a flash is up or there are corners to show. The chip is a panel in the objective's column,
## shown for three seconds. `--worldfx-cost` (search_marks.gd) prints the time. `--roomclear=N` stages the pictures (scripts/ui/world_stage.gd).
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const SearchMarks := preload("res://scripts/ui/search_marks.gd")

const FLASH_S := 0.8
const SWEEP_S := 1.1
const CHIP_S := 3.0
const CHIP_FADE_IN := 0.15
const CHIP_FADE_OUT := 0.4
const POOL := 6
## The faint corners: the arm's length in pixels (by the zoom, between these) and their strength.
const CORNER_MIN := 8.0
const CORNER_MAX := 22.0
const CORNER_ALPHA := 0.55
const CORNER_W := 2.5
const GOLD := Color(0.941, 0.761, 0.29)

var main
var hud
var sim
var layer: Node2D
var chip: PanelContainer
var chip_label: Label
## What the chip says now ("" while it is not up) and for how many more seconds.
var chip_text := ""
var chip_left := 0.0
## The flashes (a pool) and how many are up; how many room corners were drawn at the last frame.
var flashes: Array = []
var drawn_corners := 0
var cost_us := 0.0
var cost_frames := 0

var _house := -2
var _rooms: Array = []
var _calm := false
var _quad_pts := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _quad_cols := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
var _cost := false


class Flash:
	var alive := false
	var rect := Rect2()
	var age := 0.0
	var house := false


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	sim = main.get("sim")
	for i in POOL:
		flashes.append(Flash.new())
	var off := false
	for arg in OS.get_cmdline_user_args():
		if String(arg) == "--worldfx-cost":
			_cost = true
		elif String(arg) == "--noworldfx" or String(arg) == "--noworldfx=flash":
			off = true    # (see search_marks.gd)
	if hud == null or off:
		return
	# the flash is drawn in the overlay's canvas layer, just under the overlay (so that an E prompt is never under a gold line) and over the world; the chip is a panel of the HUD
	var overlay = main.get("overlay")
	if overlay == null or overlay.get_parent() == null:
		return
	layer = Node2D.new()
	layer.name = "RoomFlash"
	layer.draw.connect(_draw_layer)
	overlay.get_parent().add_child(layer)
	overlay.get_parent().move_child(layer, overlay.get_index())
	_build_chip()


## The chip is a slim panel in the objective's column, right under the objective's card (it is put there while it is up, and the cards under it go down by its height).
func _build_chip() -> void:
	var st: StyleBox = hud._style(hud.PANEL, 6, Color(GOLD, 0.75), true, "panel_slim")
	if st is StyleBoxFlat:
		st.content_margin_left = 12
		st.content_margin_right = 12
		st.content_margin_top = 6
		st.content_margin_bottom = 7
	chip = hud._panel(st)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.visible = false
	chip_label = hud._label("", Fonts.sans(600), 15, hud.INK)
	chip.add_child(chip_label)
	var at := 1
	var tower = main.town.part("town_hud") if main.get("town") != null else null
	if tower != null and tower.get("obj_card") != null:
		at = int(tower.obj_card.get_index()) + 1
	hud.left_col.add_child(chip)
	hud.left_col.move_child(chip, mini(at, hud.left_col.get_child_count() - 1))


# ----------------------------------------------------------------------------- frames --

func on_frame(dt: float) -> void:
	if layer == null:
		return
	var t0 := Time.get_ticks_usec() if _cost else 0
	_calm = SearchMarks.calm()
	_track_house()
	var live := _age_flashes(dt)
	_step_chip(dt)
	if live or _corners_on():
		layer.queue_redraw()
	elif drawn_corners > 0:
		layer.queue_redraw()    # (once more, so that the last of them is wiped)
	if _cost:
		cost_us += float(Time.get_ticks_usec() - t0)
		cost_frames += 1


func _me():
	if sim == null or sim.get("avatar") == null or String(sim.get("player_id")) == "":
		return null
	return sim.avatar.player()


func _track_house() -> void:
	var me = _me()
	var houses = sim.get("houses") if sim != null else null
	var h := int(houses.house_at(me.x, me.y)) if me != null and houses != null else -1
	if h == _house:
		return
	_house = h
	_rooms = []
	if h < 0:
		return
	for r in houses.rooms_of(h):
		_rooms.append({"id": int(r), "rect": Rect2(Rect2i(houses.room(int(r)).get("rect", Rect2i())))})


## The corners are shown in a house that is not clear yet, once a room of it is.
func _corners_on() -> bool:
	var clearing = sim.get("clearing") if sim != null else null
	if _house < 0 or clearing == null or _rooms.is_empty() or clearing.house_clear(_house):
		return false
	for rm in _rooms:
		if clearing.is_clear(int(rm.id)):
			return true
	return false


func _age_flashes(dt: float) -> bool:
	var live := false
	for f in flashes:
		if not f.alive:
			continue
		f.age += dt
		if f.age >= (SWEEP_S if f.house else FLASH_S):
			f.alive = false
			continue
		live = true
	return live


func _step_chip(dt: float) -> void:
	if chip == null or chip_left <= 0.0:
		return
	chip_left -= dt
	if chip_left <= 0.0:
		chip_left = 0.0
		chip_text = ""
		chip.visible = false
		return
	if _calm:
		chip.modulate.a = 1.0
	else:
		var age := CHIP_S - chip_left
		chip.modulate.a = clampf(minf(age / CHIP_FADE_IN, chip_left / CHIP_FADE_OUT), 0.0, 1.0)


# ------------------------------------------------------------------------------ events --

func on_event(e: Dictionary) -> void:
	if layer == null or sim == null or sim.get("houses") == null:
		return
	match String(e.get("type", "")):
		"room_clear":
			var rect := Rect2(Rect2i(sim.houses.room(int(e.get("room", -1))).get("rect", Rect2i())))
			if rect.has_area():
				_spawn(rect, false)
			_say_chip(int(e.get("house", -1)), String(e.get("name", "")))
		"house_clear":
			var rect2 := Rect2(Rect2i(sim.houses.house(int(e.get("house", -1))).get("rect", Rect2i())))
			if rect2.has_area():
				_spawn(rect2, true)


func _spawn(rect: Rect2, is_house: bool) -> void:
	var f: Flash = null
	for q in flashes:
		if not q.alive:
			f = q
			break
	if f == null:
		f = flashes[0]
	f.alive = true
	f.rect = rect
	f.age = 0.0
	f.house = is_house


## "Kitchen clear: 3 of 8 rooms" (the counts as they stand when the news is told).
func _say_chip(h: int, room_name: String) -> void:
	if chip == null:
		return
	var rooms: Array = sim.houses.rooms_of(h)
	var clearing = sim.get("clearing")
	var done := 0
	if clearing != null:
		for r in rooms:
			if clearing.is_clear(int(r)):
				done += 1
	var nm := room_name.strip_edges()
	nm = (nm.substr(0, 1).to_upper() + nm.substr(1)) if nm != "" else "Room"
	chip_text = "%s clear: %d of %d rooms" % [nm, done, rooms.size()]
	chip_label.text = chip_text
	chip_left = CHIP_S
	chip.visible = true
	chip.modulate.a = 1.0 if _calm else 0.0


# ----------------------------------------------------------------------------- drawing --

## World tile -> HUD pixel (the camera is main's: centre tile and pixels per tile).
func screen_of(tile: Vector2) -> Vector2:
	var vp := layer.get_viewport_rect().size if layer != null else Vector2(1280, 800)
	var cam: Vector2 = main.get("cam_center") if main.get("cam_center") is Vector2 else Vector2.ZERO
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	return (tile - cam) * z + vp * 0.5


func _screen_rect(r: Rect2) -> Rect2:
	var a := screen_of(r.position)
	return Rect2(a, screen_of(r.end) - a)


func _draw_layer() -> void:
	drawn_corners = 0
	if hud == null or main == null:
		return
	var view := Rect2(Vector2.ZERO, layer.get_viewport_rect().size).grow(40.0)
	for f in flashes:
		if not f.alive:
			continue
		var sr := _screen_rect(f.rect)
		if not view.intersects(sr):
			continue
		if f.house:
			_draw_sweep(sr, f.age)
		else:
			_draw_room_flash(sr, f.age)
	_draw_corners(view)


## The room's outline: a rise and a slow fall (a still outline for the same time under Reduce motion), a wide faint halo, the bright edge, and a faint wash inside.
func _draw_room_flash(sr: Rect2, age: float) -> void:
	var k := clampf(age / FLASH_S, 0.0, 1.0)
	if _calm:
		layer.draw_rect(sr, Color(GOLD, 0.07), true)
		layer.draw_rect(sr, Color(GOLD, 0.7), false, 3.0)
		return
	var e := k / 0.18 if k < 0.18 else 1.0 - (k - 0.18) / 0.82
	e = e * e * (3.0 - 2.0 * e)
	layer.draw_rect(sr, Color(GOLD, 0.12 * e), true)
	layer.draw_rect(sr.grow(2.0 + 6.0 * k), Color(GOLD, 0.2 * e), false, 7.0)
	layer.draw_rect(sr, Color(GOLD, 0.9 * e), false, 3.0)


## The whole footprint: a gold outline of the walls and a band of light that goes across it left to right.
func _draw_sweep(sr: Rect2, age: float) -> void:
	var k := clampf(age / SWEEP_S, 0.0, 1.0)
	if _calm:
		layer.draw_rect(sr, Color(GOLD, 0.06), true)
		layer.draw_rect(sr, Color(GOLD, 0.7), false, 4.0)
		return
	var env := minf(k / 0.12, 1.0) * (1.0 - smoothstep(0.8, 1.0, k))
	layer.draw_rect(sr, Color(GOLD, 0.85 * env), false, 4.0)
	layer.draw_rect(sr.grow(3.0 + 8.0 * k), Color(GOLD, 0.18 * env), false, 8.0)
	var bw := maxf(70.0, sr.size.x * 0.28)
	var xc := sr.position.x - bw + (sr.size.x + 2.0 * bw) * (k * k * (3.0 - 2.0 * k))
	_band(sr, xc - bw, xc, 0.0, 0.34 * env)
	_band(sr, xc, xc + bw, 0.34 * env, 0.0)


## One quad of the band from x0 to x1, its strength going from a0 to a1, cut to the footprint (the strengths at the cut ends worked out, not guessed).
func _band(sr: Rect2, x0: float, x1: float, a0: float, a1: float) -> void:
	var l := maxf(x0, sr.position.x)
	var r := minf(x1, sr.end.x)
	if r - l < 0.5 or x1 - x0 < 0.001:
		return
	var t_l := (l - x0) / (x1 - x0)
	var t_r := (r - x0) / (x1 - x0)
	var al := lerpf(a0, a1, t_l)
	var ar := lerpf(a0, a1, t_r)
	_quad_pts[0] = Vector2(l, sr.position.y)
	_quad_pts[1] = Vector2(r, sr.position.y)
	_quad_pts[2] = Vector2(r, sr.end.y)
	_quad_pts[3] = Vector2(l, sr.end.y)
	_quad_cols[0] = Color(GOLD, al)
	_quad_cols[1] = Color(GOLD, ar)
	_quad_cols[2] = Color(GOLD, ar)
	_quad_cols[3] = Color(GOLD, al)
	layer.draw_polygon(_quad_pts, _quad_cols)


## The faint corners of the rooms that are clear (while the avatar is in this house and it is not clear yet).
func _draw_corners(view: Rect2) -> void:
	if not _corners_on():
		return
	var clearing = sim.get("clearing")
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	var arm := clampf(0.4 * z, CORNER_MIN, CORNER_MAX)
	var col := Color(GOLD, CORNER_ALPHA)
	for rm in _rooms:
		if not clearing.is_clear(int(rm.id)):
			continue
		var sr := _screen_rect(rm.rect).grow(-4.0)
		if not view.intersects(sr):
			continue
		# (each arm starts half a line's width out, so that the two of a corner meet without a notch)
		var h := CORNER_W * 0.5
		var x0 := sr.position.x
		var y0 := sr.position.y
		var x1 := sr.end.x
		var y1 := sr.end.y
		layer.draw_line(Vector2(x0 - h, y0), Vector2(x0 + arm, y0), col, CORNER_W)
		layer.draw_line(Vector2(x0, y0 - h), Vector2(x0, y0 + arm), col, CORNER_W)
		layer.draw_line(Vector2(x1 + h, y0), Vector2(x1 - arm, y0), col, CORNER_W)
		layer.draw_line(Vector2(x1, y0 - h), Vector2(x1, y0 + arm), col, CORNER_W)
		layer.draw_line(Vector2(x0 - h, y1), Vector2(x0 + arm, y1), col, CORNER_W)
		layer.draw_line(Vector2(x0, y1 + h), Vector2(x0, y1 - arm), col, CORNER_W)
		layer.draw_line(Vector2(x1 + h, y1), Vector2(x1 - arm, y1), col, CORNER_W)
		layer.draw_line(Vector2(x1, y1 + h), Vector2(x1, y1 - arm), col, CORNER_W)
		drawn_corners += 4
