## The minimap (One House, HUDB): a small round window on the streets round the avatar, in the corner of the screen that has the least in it (the bottom right, above the toolbar).
## North is up; the avatar is the gold arrow in the middle, turned to where she aims. A VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`,
## `on_frame(dt)`); one of the Settings' switches ("Minimap", `ui/minimap`, on) puts it away. A click on it opens the Map page (the same as M).
##
## WHAT IT SHOWS (about 40 tiles each way): the roads dark, the sidewalks and yards, the houses as lighter blocks (the ones looked in warm, the BASE in gold, and while there is no base
## the houses that may be claimed in the colour of their tier: gold the best, green a fair one, grey a poor one); the base's house as a gold mark, and its direction on the rim when it is out of the window; the survivors known of and not yet home
## (blue diamonds, as the Map page's); and, within DEAD_R tiles, the dead that are awake (small red squares).
##
## WHAT IT COSTS. The ground is drawn by ONE quad with a shader (scripts/ui/minimap.gdshader) from three textures made once when the town begins (a pixel for each tile: the
## town's own `terrain` and `tile_house` arrays read as pixels, no loop), so a frame moves two uniforms. The rules are read at REFRESH_S (ten times a second) into arrays that are
## reused; what is drawn over the ground (the dead, the pins, the arrow) is one small `_draw` that runs when something moved. It never writes the rules.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Access := preload("res://scripts/access.gd")
const CbShapes := preload("res://scripts/ui/cb_shapes.gd")
const Arrival := preload("res://scripts/town/arrival.gd")
const SHADER := preload("res://scripts/ui/minimap.gdshader")
const TierMarks := preload("res://scripts/ui/tier_marks.gd")

## Tiles across the window (so 40 each way), and the radius in tiles inside which an awake dead one is shown.
const SPAN_TILES := 80.0
const DEAD_R := 20.0
const MAX_DEAD := 32
const REFRESH_S := 0.1
const FLAGS_S := 0.5
const SIZE_MIN := 112.0
const SIZE_MAX := 150.0
const MARGIN := 12.0
const DEAD_COLOR := Color(0.93, 0.25, 0.2, 1.0)
const KNOWN_COLOR := Color("#7fa6c9")
const SEARCH_COLOR := Color("#d9a0e0")    # (the radio's search colour, scripts/render/stance_marks.gd)
const BASE_COLOR := Color("#f0c24a")
const CAND_COLOR := Color("#8fb85a")
## The avatar is pale, not the gold of the Map page's arrow: the base's block is gold and she is often on it.
const ME_COLOR := Color(0.98, 0.97, 0.91, 1.0)
const HOUSE_DARK := Color(0.14, 0.09, 0.04, 1.0)
const TIP := "The streets round you, north at the top. The dead that are awake show red. Click for the map (M)"
## With "Colour-blind markers": the same marks, told by their shapes (see `_draw_marks`).
const TIP_CB := "The streets round you, north at the top. Triangles are the dead that are awake, circles are survivors you know of, a flag with a plus is a house you could claim. Click for the map (M)"

var main
var hud
var root: Control
var quad: ColorRect
var marks: Control
var mat: ShaderMaterial
var size_px := 136.0
## True when the town has the data the window needs.
var ready_ok := false
## What the window shows now: the avatar's tile and aim, the awake dead within DEAD_R (tiles), the survivors known of, the houses that may be claimed, the base (tile; (-1, -1) none).
var me := Vector2.ZERO
var aim := 0.0
var dead := PackedVector2Array()
var known := PackedVector2Array()
## The crew on a search of a house (at most four): purple dots.
var searchers := PackedVector2Array()
var cands := PackedVector2Array()
## The colour of each of them by its tier (scripts/ui/tier_marks.gd: gold the best, green a fair one, grey a poor one), as the pennants and the edge arrows have it.
var cand_cols := PackedColorArray()
var cand_tiers := PackedStringArray()
## The colour-blind setting: each pin of a house to claim carries its tier's letter (B, F, P).
var _letters := false
var base_at := Vector2(-1.0, -1.0)
## The CPU time of this part, microseconds, for `--hudb-cost` (see crew_marks.gd).
var cost_us := 0.0
var cost_frames := 0

var _flag_tex: ImageTexture
var _flags := PackedByteArray()
var _t := REFRESH_S
var _t_flags := FLAGS_S
var _drawn_at := Vector2(-1.0e9, -1.0e9)
var _drawn_aim := 0.0
var _dirty := true
var _world_w := 192
var _world_h := 192
var _enabled := true
## "Colour-blind markers" was on at the last look.
var _cb := false
## Shapes drawn over the ground, kept so that a frame makes no array (a `_line` is its shape closed, for the outline).
var _tri := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _tri_line := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _dia := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _dia_line := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _roof := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _flag := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _arrow := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _arrow_line := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	var sim = main.get("sim")
	var world = main.get("world")
	if sim == null or world == null or sim.get("houses") == null or not (sim.houses.town.get("tile_house") is PackedInt32Array):
		return
	var th: PackedInt32Array = sim.houses.town.tile_house
	_world_w = int(world.W)
	_world_h = int(world.H)
	if world.terrain.size() != _world_w * _world_h or th.size() != _world_w * _world_h:
		return
	_build(world.terrain, th)
	ready_ok = true


func _build(terrain: PackedByteArray, tile_house: PackedInt32Array) -> void:
	var terrain_tex := ImageTexture.create_from_image(Image.create_from_data(_world_w, _world_h, false, Image.FORMAT_L8, terrain))
	var house_tex := ImageTexture.create_from_image(Image.create_from_data(_world_w, _world_h, false, Image.FORMAT_RGBA8, tile_house.to_byte_array()))
	_flags.resize(256)
	_flags.fill(0)
	_flag_tex = ImageTexture.create_from_image(Image.create_from_data(256, 1, false, Image.FORMAT_L8, _flags))
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("terrain_tex", terrain_tex)
	mat.set_shader_parameter("house_tex", house_tex)
	mat.set_shader_parameter("flag_tex", _flag_tex)
	mat.set_shader_parameter("world_size", Vector2(_world_w, _world_h))
	mat.set_shader_parameter("span", SPAN_TILES)
	root = Control.new()
	root.name = "Minimap"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	root.tooltip_text = TIP
	root.visible = false
	root.gui_input.connect(_on_input)
	root.mouse_entered.connect(_hot.bind(1.0))
	root.mouse_exited.connect(_hot.bind(0.0))
	quad = ColorRect.new()
	quad.color = Color.WHITE
	quad.material = mat
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(quad)
	marks = Control.new()
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.draw.connect(_draw_marks)
	root.add_child(marks)
	hud.add_child(root)
	# (over what is drawn in the world on the HUD's own layer and over the sleep fade, under every board: the radio panel, the help and the alerts cover it as they cover the world)
	hud.move_child(root, _first_board_index())
	hud.resized.connect(_place)
	_place()


## The index of the first of the HUD's own boards among its children (what is before it is a layer of marks over the world).
func _first_board_index() -> int:
	var board = hud.get("left_col")
	var n: Node = board
	while n != null and n.get_parent() != hud:
		n = n.get_parent()
	return n.get_index() if n != null else 0


func _hot(v: float) -> void:
	if mat != null:
		mat.set_shader_parameter("hot", v)


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var sim = main.get("sim")
		if sim != null and sim.has_method("is_one_house") and sim.is_one_house() and main.has_method("page_key"):
			main.page_key("map", false)
		root.accept_event()


# ---------------------------------------------------------------------------- frames --

func on_frame(dt: float) -> void:
	if not ready_ok:
		return
	var t0 := Time.get_ticks_usec()
	_frame(dt)
	cost_us += float(Time.get_ticks_usec() - t0)
	cost_frames += 1


func _frame(dt: float) -> void:
	if _t + dt >= REFRESH_S:
		_enabled = Prefs.on("ui", "minimap") and hud.size.x >= 640.0
		var markers := Access.markers()
		if markers != _cb:
			_cb = markers    # (Colour-blind markers went on or off: the marks are drawn again, and the tooltip says what the shapes are)
			root.tooltip_text = TIP_CB if markers else TIP
			_dirty = true
	var on := _enabled
	if root.visible != on:
		root.visible = on
		_dirty = true
	if not on:
		return
	var p = _player()
	if p == null:
		return
	# (the pawn's drawn place, between its last two steps: the camera follows that, and so does the window)
	var at := Vector2(p.x, p.y)
	if main.has_method("view_pos"):
		at = main.view_pos(p)
	me = at
	aim = float(p.aim)
	_t += dt
	if _t >= REFRESH_S:
		_t = 0.0
		_refresh(p)
		_dirty = true
	_t_flags += dt
	if _t_flags >= FLAGS_S:
		_t_flags = 0.0
		_refresh_flags()
		_place()
	if _dirty or at.distance_squared_to(_drawn_at) > 0.01 or absf(aim - _drawn_aim) > 0.02:
		_dirty = false
		_drawn_at = at
		_drawn_aim = aim
		mat.set_shader_parameter("center", at)
		marks.queue_redraw()


func _player():
	var sim = main.get("sim")
	if sim == null or sim.get("avatar") == null or String(sim.get("player_id")) == "":
		return null
	return sim.avatar.player()


## The window's size and corner: the bottom right, over the toolbar (kept clear of it as it grows with the window).
func _place() -> void:
	var s := clampf(hud.size.y * 0.17, SIZE_MIN, SIZE_MAX)
	var bottom: float = hud.size.y - MARGIN
	var tools = hud.get("speed_panel")
	if tools != null and tools is Control and tools.is_visible_in_tree():
		bottom = minf(bottom, (tools as Control).get_global_rect().position.y - 8.0)
	else:
		bottom -= 56.0
	if not is_equal_approx(s, size_px):
		size_px = s
		mat.set_shader_parameter("px", s)
	root.size = Vector2(s, s)
	quad.size = root.size
	marks.size = root.size
	root.position = Vector2(hud.size.x - MARGIN - s, bottom - s)


## What the rules say now, into the arrays below (reused: no new ones).
func _refresh(p) -> void:
	var sim = main.get("sim")
	var here := Vector2(p.x, p.y)
	var n := 0
	var r2 := DEAD_R * DEAD_R
	for z in sim.zombies:
		if n >= MAX_DEAD:
			break
		if z.state == "dead" or z.state == "dying":
			continue
		var dx: float = z.x - here.x
		var dy: float = z.y - here.y
		if dx * dx + dy * dy <= r2:
			if dead.size() <= n:
				dead.resize(n + 1)
			dead[n] = Vector2(z.x, z.y)
			n += 1
	if dead.size() != n:
		dead.resize(n)
	# the crew out searching a house (CREW: scripts/town/crew_search.gd): where they are, as a purple dot
	var cs = sim.get("crew_search")
	var m := 0
	if cs != null:
		for q in sim.people:
			if m < 4 and not q.dead and q.away == null and cs.is_out(q):
				if searchers.size() <= m:
					searchers.resize(m + 1)
				searchers[m] = Vector2(q.x, q.y)
				m += 1
	if searchers.size() != m:
		searchers.resize(m)


## The slow things: the houses looked in, the base, the houses that may be claimed, the survivors known of (twice a second).
func _refresh_flags() -> void:
	var sim = main.get("sim")
	var town: Dictionary = sim.houses.town
	var houses: Array = town.get("houses", [])
	var next := PackedByteArray()
	next.resize(256)
	next.fill(0)
	var clearing = sim.get("clearing")
	if clearing != null and clearing.has_method("explored"):
		for h in clearing.explored():
			if int(h) >= 0 and int(h) < 256:
				next[int(h)] = 1
	var base = sim.get("base")
	var base_h := -1
	if base != null and base.get("claimed") == true and base.get("house") != null:
		base_h = int(base.house)
	base_at = Vector2(-1.0, -1.0)
	cands.resize(0)
	cand_cols.resize(0)
	cand_tiers.resize(0)
	_letters = TierMarks.letters_on()
	if base_h >= 0 and base_h < houses.size():
		base_at = Vector2(Rect2i(houses[base_h].rect).get_center())
		if base_h < 256:
			next[base_h] = 2
	elif town.has("start"):
		for c in Arrival.candidates(town):
			var h := int(c.house)
			if h >= 0 and h < houses.size():
				var tier := String(c.get("tier", "ok"))
				if h < 256:
					next[h] = TierMarks.flag_of(tier)
				cands.append(Vector2(Rect2i(houses[h].rect).get_center()))
				cand_cols.append(TierMarks.color(tier))
				cand_tiers.append(tier)
	known.resize(0)
	var rescue = sim.get("rescue")
	if rescue != null and rescue.has_method("list"):
		for rec in rescue.list():
			var state := String(rec.get("state", ""))
			if state == "wary" or state == "spoken":
				known.append(rec.get("pos", Vector2.ZERO))
	if next != _flags:
		_flags = next
		_flag_tex.update(Image.create_from_data(256, 1, false, Image.FORMAT_L8, _flags))
	_dirty = true


# --------------------------------------------------------------------------- drawing --

func _draw_marks() -> void:
	var t0 := Time.get_ticks_usec()
	var s := size_px
	var c := Vector2(s, s) * 0.5
	var ppt := s / SPAN_TILES
	var reach := s * 0.5 - 6.0
	# the dead awake: small squares
	for i in dead.size():
		var d := (dead[i] - me) * ppt
		if d.length_squared() <= reach * reach:
			if _cb:
				CbShapes.mark(marks, "triangle", c + d, 3.3, DEAD_COLOR)    # (Colour-blind markers: the dead are triangles)
			else:
				marks.draw_rect(Rect2(c + d - Vector2(1.8, 1.8), Vector2(3.6, 3.6)), DEAD_COLOR)
	# the survivors known of: blue diamonds
	for i in known.size():
		var d2 := (known[i] - me) * ppt
		if d2.length() <= reach and _cb:
			CbShapes.mark(marks, "circle", c + d2, 3.6, KNOWN_COLOR)    # (Colour-blind markers: survivors are circles)
		elif d2.length() <= reach:
			var q := c + d2
			_dia[0] = q + Vector2(0, -4.5)
			_dia[1] = q + Vector2(3.8, 0)
			_dia[2] = q + Vector2(0, 4.5)
			_dia[3] = q + Vector2(-3.8, 0)
			for j in 4:
				_dia_line[j] = _dia[j]
			_dia_line[4] = _dia[0]
			marks.draw_colored_polygon(_dia, KNOWN_COLOR)
			marks.draw_polyline(_dia_line, Color(0, 0, 0, 0.75), 1.2)
	# the crew out searching: a purple dot (a ring too with Colour-blind markers) while they are inside the window
	for i in searchers.size():
		var d3 := (searchers[i] - me) * ppt
		if d3.length() <= reach:
			marks.draw_circle(c + d3, 3.4, Color(0.04, 0.08, 0.07, 0.9))
			marks.draw_circle(c + d3, 2.4, SEARCH_COLOR)
			if _cb:
				CbShapes.mark(marks, "circle", c + d3, 4.4, SEARCH_COLOR)
	# the houses that may be claimed (before a base): a green pennant on the house, or its direction on the rim
	for i in cands.size():
		var pin_d := (cands[i] - me) * ppt
		_pin_or_arrow(c, pin_d, reach, cand_cols[i] if i < cand_cols.size() else CAND_COLOR, false)
		if _letters and i < cand_tiers.size() and pin_d.length() <= reach:
			marks.draw_string(Fonts.cond(700), c + pin_d + Vector2(5.0, -1.0), TierMarks.letter(cand_tiers[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cand_cols[i])
	# the base: a gold house, or its direction on the rim
	if base_at.x >= 0.0:
		_pin_or_arrow(c, (base_at - me) * ppt, reach, BASE_COLOR, true)
	# the avatar: an arrow turned to where she aims
	var f := Vector2.from_angle(aim)
	var sd := Vector2(-f.y, f.x)
	_tri[0] = c + f * 7.0
	_tri[1] = c - f * 4.6 + sd * 4.6
	_tri[2] = c - f * 2.2
	_tri[3] = c - f * 4.6 - sd * 4.6
	for j in 4:
		_tri_line[j] = _tri[j]
	_tri_line[4] = _tri[0]
	marks.draw_polyline(_tri_line, Color(0, 0, 0, 0.85), 3.0, true)
	marks.draw_colored_polygon(_tri, ME_COLOR)
	marks.draw_string(Fonts.cond(700), Vector2(c.x - 3.5, 13.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(hud.INK, 0.78))
	cost_us += float(Time.get_ticks_usec() - t0)


## A mark at `d` pixels from the middle when it is inside the window; else a small arrow on the rim, pointing at it.
func _pin_or_arrow(c: Vector2, d: Vector2, reach: float, color: Color, house: bool) -> void:
	if d.length() <= reach:
		var q := c + d
		if house:
			_roof[0] = q + Vector2(-5.2, -0.5)
			_roof[1] = q + Vector2(0, -5.6)
			_roof[2] = q + Vector2(5.2, -0.5)
			# (a dark house on the base's gold block: the avatar, when she is home, is the pale arrow over it)
			marks.draw_rect(Rect2(q + Vector2(-3.8, -0.5), Vector2(7.6, 5.5)), HOUSE_DARK)
			marks.draw_colored_polygon(_roof, HOUSE_DARK)
			if _cb:
				# (Colour-blind markers: the base's house has a pale rim, a square body under a point, whatever it stands on)
				marks.draw_rect(Rect2(q + Vector2(-4.6, -0.9), Vector2(9.2, 6.4)), CbShapes.RIM, false, 1.2)
		else:
			_flag[0] = q + Vector2(0, -8.0)
			_flag[1] = q + Vector2(6.0, -5.6)
			_flag[2] = q + Vector2(0, -3.2)
			marks.draw_line(q, q + Vector2(0, -8.0), Color(0, 0, 0, 0.75), 3.0)
			marks.draw_line(q, q + Vector2(0, -8.0), color, 1.4)
			marks.draw_colored_polygon(_flag, color)
			if _cb:
				CbShapes.mark(marks, "plus", q + Vector2(9.5, -3.0), 2.6, color)    # (Colour-blind markers: a house to claim has a plus)
		return
	var dir := d.normalized()
	var tip := c + dir * (reach + 3.0)
	var sd := Vector2(-dir.y, dir.x)
	_arrow[0] = tip + dir * 3.0
	_arrow[1] = tip - dir * 4.0 + sd * 4.0
	_arrow[2] = tip - dir * 4.0 - sd * 4.0
	for j in 3:
		_arrow_line[j] = _arrow[j]
	_arrow_line[3] = _arrow[0]
	marks.draw_colored_polygon(_arrow, color)
	marks.draw_polyline(_arrow_line, Color(0, 0, 0, 0.8), 1.2, true)
