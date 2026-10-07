## The arrows at the edge of the screen (One House, navigation): where the houses to claim are, and later where home is, when they are off the screen. A VIEW PART of the town's
## facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`); it only reads the rules, never writes them.
##
##   - WHILE NO HOUSE IS CLAIMED: one arrow for EACH house that may be claimed and is off the screen: a chevron on the rim of the window pointing at the front door, and a plate beside it
##     with the tier's icon (a gold star for the best house, a green circle for a fair one, a grey square for a poor one: scripts/ui/tier_marks.gd, the same marks as the pennants
##     and the maps) and the words "Family home 38 m". The nearest house keeps the objective card's arrow as well (scripts/ui/town_hud.gd): this adds the others, so the player can weigh them.
##   - AFTER THE CLAIM: one arrow for the base ("Home 52 m") while it is off the screen and the avatar is more than BASE_FAR tiles from it (it helps coming back from a rescue); and,
##     while the objective is to find survivors, a small blue chevron with the distance for each survivor known of (seen, not yet home), the three nearest.
##   - an arrow fades in as its house leaves the screen and out as it comes back (a house on the screen has its pennant: scripts/render/candidate_marks.gd), and none is drawn while she sleeps.
##
## THE LAYOUT. An arrow is on the rim at the point where the line from the middle of the window to its house leaves the window (INSET pixels in). Arrows that would lie on one another, or
## on a panel of the HUD (the stores, the clock, the crew's cards, the toolbar, the minimap, the lesson), are slid along the edge to the nearest free place, the nearest house first.
##
## WHAT IT COSTS. A pool of MAX_ITEMS items made once; the rules are read ten times a second into it; a frame projects at most a handful of points, slides at most a few, and draws a
## few quads and strings on one Control: no array or dictionary is made in a frame (the strings are made when a rounded distance changes).
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const Arrival := preload("res://scripts/town/arrival.gd")
const TierMarks := preload("res://scripts/ui/tier_marks.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const Access := preload("res://scripts/access.gd")
const HudFree := preload("res://scripts/ui/hud_free.gd")

const REFRESH_S := 0.2
const OBSTACLES_S := 0.25
## How far in from the window's edge the chevron stands, and how big it is (a survivor's is the small one).
const INSET := 26.0
const CHEV := 11.0
const CHEV_SMALL := 7.0
const PLATE_H := 26.0
const PLATE_GAP := 14.0
const PLATE_PAD := 9.0
const ICON_R := 7.0
## The room a tier's letter takes in the plate under the colour-blind setting.
const LETTER_W := 16.0
const FONT_SIZE := 15
## How many pixels beyond the window's edge a house is when its arrow is at full strength (it fades in over that much).
const FADE_PX := 70.0
## The slide along the edge: one try every STEP pixels, TRIES of them at most.
const STEP := 12.0
const TRIES := 70
## The pennants' own numbers (scripts/render/candidate_marks.gd): they fade in over PENNANT_FADE tiles within `arrival.mark_r`, and are drawn while their foot is within PENNANT_REACH pixels of the screen.
const PENNANT_FADE := 3.0
const PENNANT_REACH := 60.0
const PENNANT_SHOWN := 40.0
## The base's arrow shows only from this many tiles away.
const BASE_FAR := 25.0
const MAX_ITEMS := 10
const MAX_RESCUE := 3
const MAX_OBSTACLES := 40
const TILE_WORD := "m"
const BASE_COLOR := Color("#f0c24a")
const KNOWN_COLOR := Color("#7fa6c9")
const DARK := Color(0.04, 0.08, 0.07)

const KIND_HOUSE := 0
const KIND_BASE := 1
const KIND_SURVIVOR := 2
const SIDE_LEFT := 0
const SIDE_RIGHT := 1
const SIDE_TOP := 2
const SIDE_BOTTOM := 3


## One arrow (the pool's): what it points at, the words, and where it is drawn this frame.
class Item:
	extends RefCounted
	var kind := 0
	var tier := ""
	var title := ""
	var tile := Vector2.ZERO
	var dist := -1
	var dist_text := ""
	var title_w := 0.0
	var dist_w := 0.0
	var plate_w := 0.0
	var alpha := 0.0
	var live := false
	var pos := Vector2.ZERO
	var angle := 0.0
	var side := 0
	var plate := Rect2()
	var box := Rect2()
	## A house's walls (tiles) and where its pennant stands, to give way to the pennant.
	var rect := Rect2()
	var foot := Vector2.ZERO


var main
var hud
var layer: Control
## The pool, how many of it the rules ask for now (nearest first), and how many are on the screen at this frame.
var items: Array = []
var count := 0
var live_count := 0
## The CPU time of this part, microseconds, for a look at what it costs (see `cost_us`, summed from on_frame).
var cost_us := 0.0
var cost_frames := 0

var _mark_r := 14.0
var _map_open := false
var _cost := false
var _letters := false
## The size of the plates' words (the text size setting), and what grows with it: the plate's height and the icon.
var _fs := FONT_SIZE
var _k := 1.0
var _ph := PLATE_H
var _ir := ICON_R
var _t := REFRESH_S
var _t_obst := OBSTACLES_S
var _was_live := false
var _plate := StyleBoxFlat.new()
var _obst := PackedFloat32Array()
var _obst_n := 0
## The shapes drawn, kept so that a frame makes no array (a `_line` is its shape closed, for the outline).
var _chev := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _chev_line := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _dia := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _dia_line := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _home := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _home_line := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	_plate.set_corner_radius_all(5)
	_plate.set_border_width_all(1)
	_mark_r = float(OneHouse.data().get("arrival", {}).get("mark_r", 14.0))
	_cost = OS.get_cmdline_user_args().has("--hudb-cost")
	_obst.resize(MAX_OBSTACLES * 4)
	for i in MAX_ITEMS:
		items.append(Item.new())
	layer = Control.new()
	layer.name = "EdgeArrows"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.draw.connect(_draw_layer)
	hud.add_child(layer)
	# (under the HUD's own boards, as the pennants and the objective's arrow are: a mark in the world is never over a panel)
	hud.move_child(layer, 0)


func on_frame(dt: float) -> void:
	if layer == null:
		return
	var t0 := Time.get_ticks_usec()
	_t += dt
	if _t >= REFRESH_S:
		_t = 0.0
		_refresh()
	_t_obst += dt
	if _t_obst >= OBSTACLES_S:
		_t_obst = 0.0
		_collect_obstacles()
	live_count = 0
	if count > 0:
		_layout()
	if live_count > 0 or _was_live:
		layer.queue_redraw()
	_was_live = live_count > 0
	cost_us += float(Time.get_ticks_usec() - t0)
	cost_frames += 1
	if _cost:
		_cost_report()


## `--hudb-cost` (a screenshot run): frames 60 on are measured, and the line is printed two frames before the shot, as crew_marks.gd does for the other parts of the HUD.
func _cost_report() -> void:
	if String(main.get("shot_path")) == "":
		return
	var frame := int(main.get("frame_count"))
	if frame == 60:
		cost_us = 0.0
		cost_frames = 0
	if frame == int(main.get("shot_frames")) - 2 and cost_frames > 0:
		print("edge_arrows cost per frame (microseconds, CPU, GDScript): %.1f  (%d arrows drawn)" % [cost_us / float(cost_frames), live_count])


# ---------------------------------------------------------------------------- the rules --

func _player():
	var sim = main.get("sim")
	if sim == null or sim.get("avatar") == null or String(sim.get("player_id")) == "":
		return null
	return sim.avatar.player()


func _sleeping(sim) -> bool:
	var sl = sim.get("sleep")
	return sl != null and sl.has_method("active") and bool(sl.active())


## What the rules say now (ten times a second), into the pool: the houses to claim, or the base and the survivors known of; the nearest first.
func _refresh() -> void:
	count = 0
	var sim = main.get("sim")
	if sim == null or sim.get("houses") == null or sim.get("avatar") == null:
		return
	var me = _player()
	if me == null or _sleeping(sim):
		return
	var town = sim.houses.get("town")
	if typeof(town) != TYPE_DICTIONARY or (town as Dictionary).is_empty() or not (town as Dictionary).has("start"):
		return
	var here := Vector2(me.x, me.y)
	_map_open = hud.has_method("radio_page") and String(hud.radio_page()) == "map"
	var letters := TierMarks.letters_on()
	var fs := Access.scaled(FONT_SIZE)    # (the plates draw their own words: the text size setting, scripts/access.gd)
	if letters != _letters or fs != _fs:
		_letters = letters
		_fs = fs
		_k = float(fs) / float(FONT_SIZE)
		_ph = PLATE_H * _k
		_ir = ICON_R * _k
		for it in items:
			(it as Item).dist = -1    # (the words are made again, for the width of the letter and of the text)
	var base = sim.get("base")
	if base != null and bool(base.get("claimed")):
		_add(KIND_BASE, "", "Home", base.center(), here)
		var sc = sim.get("scenario")
		var stage := String(sc.stage()) if sc != null and sc.has_method("stage") else ""
		var rescue = sim.get("rescue")
		if (stage == "claimed" or stage == "growing") and rescue != null and rescue.has_method("list"):
			var first := count
			for rec in rescue.list():
				var state := String(rec.get("state", ""))
				if (state == "wary" or state == "spoken") and rec.get("pos") is Vector2:
					_add(KIND_SURVIVOR, "", "", rec.pos, here)
			_keep_nearest(first, MAX_RESCUE)
	else:
		var inside: int = sim.houses.house_at(me.x, me.y)
		for c in Arrival.candidates(town):
			var h := int(c.house)
			if h == inside:
				continue
			var label := String(c.get("label", ""))
			var cut := label.find(". ")
			var it := _add(KIND_HOUSE, String(c.get("tier", "ok")), label.substr(0, cut) if cut > 0 else label, Arrival.door_of(town, h), here)
			if it != null:
				it.rect = Rect2(Rect2i(town.houses[h].rect))
				it.foot = Vector2(it.rect.get_center().x, it.rect.position.y)    # (where its pennant stands: scripts/render/candidate_marks.gd)


## A new item at the end of the pool's live part (null when the pool is full).
func _add(kind: int, tier: String, title: String, tile: Vector2, here: Vector2) -> Item:
	if count >= MAX_ITEMS:
		return null
	var it: Item = items[count]
	count += 1
	it.kind = kind
	it.tier = tier
	if it.title != title:
		it.title = title
		it.dist = -1    # (the words are made again)
	it.tile = tile
	it.live = false
	it.alpha = 0.0
	# (nearest first: this one is put in its place among the ones before it)
	var i := count - 1
	while i > 0 and here.distance_squared_to((items[i - 1] as Item).tile) > here.distance_squared_to(it.tile) and (items[i - 1] as Item).kind == kind:
		items[i] = items[i - 1]
		i -= 1
	items[i] = it
	return it


## Of the items from `first` on, only the `n` nearest are kept (they are in order of distance).
func _keep_nearest(first: int, n: int) -> void:
	count = mini(count, first + n)


func _collect_obstacles() -> void:
	_obst_n = 0
	if hud == null or layer == null:
		return
	var origin := layer.get_global_rect().position
	for ctl in HudFree.controls(main, hud):    # (the HUD's boards: scripts/ui/hud_free.gd, the same list the pennants and the objective's arrow keep clear of)
		if ctl is Control and (ctl as Control).is_visible_in_tree() and _obst_n < MAX_OBSTACLES:
			var r := (ctl as Control).get_global_rect()
			var k := _obst_n * 4
			_obst[k] = r.position.x - origin.x - 4.0
			_obst[k + 1] = r.position.y - origin.y - 4.0
			_obst[k + 2] = r.size.x + 8.0
			_obst[k + 3] = r.size.y + 8.0
			_obst_n += 1


# ---------------------------------------------------------------------------- the layout --

## World tile -> HUD pixel (the camera is main's: centre tile and pixels per tile).
func screen_of(tile: Vector2) -> Vector2:
	var vp := layer.size
	var cam: Vector2 = main.get("cam_center") if main.get("cam_center") is Vector2 else Vector2.ZERO
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	return (tile - cam) * z + vp * 0.5


## Every frame: which items are off the screen, where on the rim each stands and where its plate goes, slid clear of the panels and of each other.
func _layout() -> void:
	var vp := layer.size
	var c := vp * 0.5
	var me = _player()
	if me == null:
		return
	var here := Vector2(me.x, me.y)
	var hw := c.x - INSET
	var hh := c.y - INSET
	if hw <= 10.0 or hh <= 10.0:
		return
	for i in count:
		var it: Item = items[i]
		it.live = false
		var d := here.distance_to(it.tile)
		if it.kind == KIND_BASE and d <= BASE_FAR:
			continue
		var sp := screen_of(it.tile)
		var out := maxf(maxf(maxf(-sp.x, sp.x - vp.x), maxf(-sp.y, sp.y - vp.y)), 0.0)
		it.alpha = clampf(out / FADE_PX, 0.0, 1.0) * (1.0 - _pennant(it, here, vp))
		if it.alpha <= 0.02:
			continue
		var di := roundi(d)
		if di != it.dist:
			_set_words(it, di)
		var dir := sp - c
		var ax := absf(dir.x)
		var ay := absf(dir.y)
		var s := minf(hw / maxf(ax, 0.001), hh / maxf(ay, 0.001))
		var p := c + dir * s
		it.angle = dir.angle()
		it.side = (SIDE_LEFT if dir.x < 0.0 else SIDE_RIGHT) if hw * ay <= hh * ax else (SIDE_TOP if dir.y < 0.0 else SIDE_BOTTOM)
		_place(it, i, p, vp)
		it.live = true
		live_count += 1


## How much of a house's pennant is showing on the screen (0 to 1: as scripts/render/candidate_marks.gd has it, near the avatar or with the Map page open, and its foot on the screen): the arrow gives way
## to it, so that the two are never both there.
func _pennant(it: Item, here: Vector2, vp: Vector2) -> float:
	if it.kind != KIND_HOUSE:
		return 0.0
	var strength := 1.0
	if not _map_open:
		var r := it.rect
		var near := Vector2(clampf(here.x, r.position.x, r.end.x), clampf(here.y, r.position.y, r.end.y))
		strength = clampf((_mark_r - here.distance_to(near)) / PENNANT_FADE, 0.0, 1.0)
	if strength <= 0.01:
		return 0.0
	var fp := screen_of(it.foot)
	if fp.x < -PENNANT_REACH or fp.y < -PENNANT_REACH or fp.x > vp.x + PENNANT_REACH or fp.y > vp.y + PENNANT_REACH:
		# (the foot is off the screen: the pennant stands on the part of the house that is in view, when there is enough of it: `visible_foot` of candidate_marks.gd)
		var a := screen_of(it.rect.position)
		var b := screen_of(it.rect.end)
		var vis := Rect2(a, b - a).intersection(Rect2(Vector2.ZERO, vp).grow(-8.0))
		if vis.size.x < PENNANT_SHOWN or vis.size.y < PENNANT_SHOWN:
			return 0.0
	return strength


## Sets the item's box at the point `p` of the rim and, if that is on a panel or on another arrow, slides it along the edge to the nearest free place.
func _place(it: Item, index: int, p: Vector2, vp: Vector2) -> void:
	var along := Vector2(0.0, 1.0) if it.side == SIDE_LEFT or it.side == SIDE_RIGHT else Vector2(1.0, 0.0)
	for k in TRIES:
		var s := 0.0 if k == 0 else float((k + 1) >> 1) * STEP * (1.0 if (k & 1) == 1 else -1.0)
		var q := p + along * s
		if q.x < INSET or q.y < INSET or q.x > vp.x - INSET or q.y > vp.y - INSET:
			continue
		_fit(it, q, vp)
		if _free(it, index):
			return
	# (no free place along the edge, as in a small window with the boards close together: the chevron stays on the rim where it points, and the plate goes to the nearest free place on
	# the screen, scripts/ui/hud_free.gd; with no such place either, where the arrow is, as it always was)
	_fit(it, p, vp)
	var blocked: Array = []
	for k in _obst_n:
		var j := k * 4
		blocked.append(Rect2(_obst[j], _obst[j + 1], _obst[j + 2], _obst[j + 3]))
	var others: Array = []
	for i in index:
		var other: Item = items[i]
		if other.live:
			others.append(other.box)
	var spot := HudFree.nearest_free(it.plate, Rect2(Vector2(6.0, 6.0), vp - Vector2(12.0, 12.0)), blocked, others)
	if spot != it.plate:
		var r := (CHEV_SMALL if it.kind == KIND_SURVIVOR else CHEV) + 3.0
		it.plate = spot
		it.box = spot.merge(Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0)).grow(3.0)


## Where the chevron, the plate and the whole box of the item are with its chevron at `q`.
func _fit(it: Item, q: Vector2, vp: Vector2) -> void:
	it.pos = q
	var r := (CHEV_SMALL if it.kind == KIND_SURVIVOR else CHEV) + 3.0
	var w := it.plate_w
	var h := _ph if it.kind != KIND_SURVIVOR else _ph * 0.77
	var pl: Rect2
	match it.side:
		SIDE_LEFT:
			pl = Rect2(q.x + PLATE_GAP, q.y - h * 0.5, w, h)
		SIDE_RIGHT:
			pl = Rect2(q.x - PLATE_GAP - w, q.y - h * 0.5, w, h)
		SIDE_TOP:
			pl = Rect2(q.x - w * 0.5, q.y + PLATE_GAP, w, h)
		_:
			pl = Rect2(q.x - w * 0.5, q.y - PLATE_GAP - h, w, h)
	pl.position.x = clampf(pl.position.x, 6.0, maxf(vp.x - w - 6.0, 6.0))
	pl.position.y = clampf(pl.position.y, 6.0, maxf(vp.y - h - 6.0, 6.0))
	it.plate = pl
	it.box = pl.merge(Rect2(q.x - r, q.y - r, r * 2.0, r * 2.0)).grow(3.0)


## Whether the item's box is clear of every panel and of the arrows placed before it.
func _free(it: Item, index: int) -> bool:
	for k in _obst_n:
		var j := k * 4
		if it.box.intersects(Rect2(_obst[j], _obst[j + 1], _obst[j + 2], _obst[j + 3])):
			return false
	for i in index:
		var other: Item = items[i]
		if other.live and it.box.intersects(other.box):
			return false
	return true


## The words of an item for the rounded distance `di` (tiles), and the widths they are drawn at.
func _set_words(it: Item, di: int) -> void:
	it.dist = di
	it.dist_text = "%d %s" % [di, TILE_WORD]
	var font := Fonts.cond(700)
	if it.kind == KIND_SURVIVOR:
		it.title_w = 0.0
		it.dist_w = font.get_string_size(it.dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 1).x
		it.plate_w = it.dist_w + 22.0 * _k
		return
	it.title_w = font.get_string_size(it.title, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	it.dist_w = font.get_string_size(it.dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	it.plate_w = PLATE_PAD + _ir * 2.0 + 7.0 + (LETTER_W * _k if _letters and it.kind == KIND_HOUSE else 0.0) + it.title_w + 7.0 + it.dist_w + PLATE_PAD


# ---------------------------------------------------------------------------- drawing --

func _draw_layer() -> void:
	if hud == null:
		return
	for i in count:
		var it: Item = items[i]
		if it.live:
			_draw_item(it)


func _draw_item(it: Item) -> void:
	var a := it.alpha
	var color: Color
	match it.kind:
		KIND_BASE:
			color = BASE_COLOR
		KIND_SURVIVOR:
			color = KNOWN_COLOR
		_:
			color = TierMarks.color(it.tier)
	_draw_chevron(it.pos, it.angle, CHEV_SMALL if it.kind == KIND_SURVIVOR else CHEV, Color(color, a), Color(DARK, 0.88 * a))
	var font := Fonts.cond(700)
	if it.kind == KIND_SURVIVOR:
		# a small blue diamond (the maps' "someone waits") and the distance, with no plate: a survivor's arrow is the quiet one
		var at := it.plate.position + Vector2(8.0 * _k, it.plate.size.y * 0.5)
		_draw_diamond(at, 4.6 * _k, Color(color, a))
		var tp := it.plate.position + Vector2(18.0 * _k, (it.plate.size.y + float(_fs - 1) * 0.62) * 0.5)
		layer.draw_string_outline(font, tp, it.dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 1, 4, Color(0, 0, 0, 0.9 * a))
		layer.draw_string(font, tp, it.dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 1, Color(color, a))
		return
	_plate.bg_color = Color(DARK, 0.86 * a)
	_plate.border_color = Color(color, 0.8 * a)
	layer.draw_style_box(_plate, it.plate)
	var mid := it.plate.position + Vector2(PLATE_PAD + _ir, it.plate.size.y * 0.5)
	if it.kind == KIND_BASE:
		_draw_home(mid, _ir, Color(color, a))
	else:
		TierMarks.draw_icon(layer, it.tier, mid, _ir, a)
	var x := it.plate.position.x + PLATE_PAD + _ir * 2.0 + 7.0
	var y := it.plate.position.y + (it.plate.size.y + float(_fs) * 0.62) * 0.5
	if _letters and it.kind == KIND_HOUSE:
		# (the colour-blind setting: the tier's letter too, B best, F fair, P poor)
		layer.draw_string(font, Vector2(x, y), TierMarks.letter(it.tier), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, Color(color, a))
		x += LETTER_W * _k
	layer.draw_string(font, Vector2(x, y), it.title, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, Color(hud.INK, a))
	layer.draw_string(font, Vector2(x + it.title_w + 7.0, y), it.dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, Color(color, a))


## A pointing triangle at `at`, turned to `angle` (0 is east): the tip leads, a notch at the back, with a dark rim so it reads on any ground (the objective card's, in its own arrays).
func _draw_chevron(at: Vector2, angle: float, size_px: float, color: Color, rim: Color) -> void:
	var f := Vector2.from_angle(angle)
	var s := Vector2(-f.y, f.x)
	_chev[0] = at + f * size_px
	_chev[1] = at - f * size_px * 0.7 + s * size_px * 0.78
	_chev[2] = at - f * size_px * 0.3
	_chev[3] = at - f * size_px * 0.7 - s * size_px * 0.78
	for j in 4:
		_chev_line[j] = _chev[j]
	_chev_line[4] = _chev[0]
	layer.draw_colored_polygon(_chev, color)
	layer.draw_polyline(_chev_line, rim, 1.8, true)


func _draw_diamond(at: Vector2, r: float, color: Color) -> void:
	_dia[0] = at + Vector2(0.0, -r)
	_dia[1] = at + Vector2(r * 0.85, 0.0)
	_dia[2] = at + Vector2(0.0, r)
	_dia[3] = at + Vector2(-r * 0.85, 0.0)
	for j in 4:
		_dia_line[j] = _dia[j]
	_dia_line[4] = _dia[0]
	layer.draw_colored_polygon(_dia, color)
	layer.draw_polyline(_dia_line, Color(0, 0, 0, 0.75 * color.a), 1.2)


## A small house: a box with a roof, in `color`, with the dark rim.
func _draw_home(at: Vector2, r: float, color: Color) -> void:
	_home[0] = at + Vector2(-r, -r * 0.05)
	_home[1] = at + Vector2(0.0, -r)
	_home[2] = at + Vector2(r, -r * 0.05)
	_home[3] = at + Vector2(r * 0.72, r * 0.9)
	_home[4] = at + Vector2(-r * 0.72, r * 0.9)
	for j in 5:
		_home_line[j] = _home[j]
	_home_line[5] = _home[0]
	layer.draw_colored_polygon(_home, color)
	layer.draw_polyline(_home_line, Color(DARK, 0.9 * color.a), 1.4, true)
