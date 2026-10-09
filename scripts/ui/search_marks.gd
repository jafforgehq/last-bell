## What the avatar has searched, shown in the house (One House, WORLD): a VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`,
## `on_event(e)`). It reads the rules (`sim.search.is_looted`, `sim.houses.containers_of`, `sim.uses.progress`, the `searched` event) and writes nothing in them.
##
##   - a small TICK (a check mark in a round badge) on each container of the avatar's house that is looted, drawn in the overlay's canvas layer under the overlay (an E prompt is never
##     under one). Only while the avatar is in that house; full within TICK_NEAR tiles of the avatar and gone from TICK_FAR on (so the far end of a big house is not covered in marks).
##     SCAV3: outside every house the same tick sits on each searched car or wreck of the street (scripts/town/car_loot.gd), so that nobody searches it twice; the pop says "Empty" for one with nothing in it.
##   - the "Searched" stand-in of the E prompt: with no real prompt and the avatar at a looted container, `searched_near()` says where, and the overlay (scripts/render/
##     overlay_node.gd `_draw_searched_stand_in`) draws a grey pill with a check mark: the rules offer nothing to press there, and the player is told so.
##   - the LOOT POP: when a search finishes, a small "+3 food" for each kind found rises from the container for a moment and then flies toward that store in the stores panel (and fades
##     as it gets there), 1.5 s in all; it is drawn on the HUD, over its boards, so that it can be seen going into the stores. A container with nothing in it gives a grey "Empty". The toast "Found: ..." of the town HUD stays quiet while this part is there (the pops say it).
##   - a tiny TICK SOUND (`sound.ui("ui_hover")`) when a timed session (a search, the claim, a bandage) runs its course.
## REDUCE MOTION (Settings `ui/reduce_motion`) and REDUCE FLASHES (`ui/reduce_flashes`): the pop does not fly or fade; it stands above the container, still, for the same 1.5 s.
## COST. One Control under the HUD's boards, redrawn only while a tick or a pop is up (a few lines and circles: no allocation in a frame, the pops are a fixed pool of eight made once).
## `--worldfx-cost` prints the CPU time of this part and room_flash.gd per frame near the shot. `--search=...` and `--looted=N` stage the pictures (scripts/ui/world_stage.gd).
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const Prefs := preload("res://scripts/prefs.gd")
const WorldStage := preload("res://scripts/ui/world_stage.gd")
const PromptKit := preload("res://scripts/render/prompt_kit.gd")
const CarLoot := preload("res://scripts/town/car_loot.gd")

## Tiles from the avatar at which a tick is full strength, and gone.
const TICK_NEAR := 4.0
const TICK_FAR := 9.0
const TICK_R := 9.0
const POP_S := 1.5
const POP_COUNT := 8
## How far a pop rises first (pixels), the moment (seconds) it begins to fly to the stores, and the size of its type.
const POP_RISE := 28.0
const POP_FLY_AT := 0.75
const POP_PX := 17
## How near the avatar's feet a looted container's standing spot must be for the "Searched" stand-in (the search reach and a little).
const STAND_REACH := 1.05
## The loot's kinds in the order they are told, with their words and the colour of the pop.
const KINDS := ["food", "water", "ammo", "scrap", "meds"]
const WORDS := {"food": "food", "water": "water", "ammo": "ammo", "scrap": "scrap", "meds": "medicine"}

var main
var hud
## The layer of the ticks (a Node2D in the overlay's canvas layer, under the overlay) and of the pops (a Control on the HUD).
var layer: Node2D
var pop_layer: Control
var sim
## The containers of the avatar's house that are looted: [{"id", "at": Vector2 (the furniture), "pos": Vector2 (where to stand)}].
var looted: Array = []
## What was drawn at the last frame (the screenshots' log reads them): ticks, pops.
var drawn_ticks := 0
var drawn_pops := 0
var pops: Array = []
## The CPU time of this part and its fellow, microseconds (see `--worldfx-cost`).
var cost_us := 0.0
var cost_frames := 0

var _badge: ImageTexture
var _house := -2
var _looted_n := -1
var _near := {}
var _now := 0.0
var _frames := 0
var _cost := false
var _cost_done := false
var _last_label := ""
var _last_t := 0.0
var _last_of := 0.0
var _calm := false


class Pop:
	var alive := false
	var text := ""
	var color := Color.WHITE
	var at := Vector2.ZERO
	var dx := 0.0
	var age := 0.0
	var delay := 0.0
	var target := Vector2.ZERO
	var flies := true


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	sim = main.get("sim")
	for i in POP_COUNT:
		pops.append(Pop.new())
	var off := false
	for arg in OS.get_cmdline_user_args():
		if String(arg) == "--worldfx-cost":
			_cost = true
		elif String(arg) == "--noworldfx" or String(arg) == "--noworldfx=marks":
			off = true    # (a shot or a measurement without this part's and room_flash.gd's drawing: the picture the game had before them; `=marks` leaves out this part only, `=flash` the other)
	if hud == null or off:
		return
	PromptKit.warm()    # (the E prompt's cap and ring pictures: made while the town loads)
	# the ticks are drawn in the overlay's own canvas layer, just under the overlay (so that an E prompt is never under a mark) and over the world; the pops on the HUD's, over its boards
	# (the one thing here that goes on to a panel: it flies into the stores)
	var overlay = main.get("overlay")
	if overlay != null and overlay.get_parent() != null:
		layer = Node2D.new()
		layer.name = "SearchMarks"
		layer.draw.connect(_draw_layer)
		overlay.get_parent().add_child(layer)
		overlay.get_parent().move_child(layer, overlay.get_index())
	pop_layer = Control.new()
	pop_layer.name = "LootPops"
	pop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pop_layer.draw.connect(_draw_pops)
	hud.add_child(pop_layer)
	_badge = _make_badge()


func _me():
	if sim == null or sim.get("avatar") == null or String(sim.get("player_id")) == "":
		return null
	return sim.avatar.player()


## The setting that stills the motion: Reduce motion, or Reduce flashes when the game has that switch.
static func calm() -> bool:
	return Prefs.on("ui", "reduce_motion") or Prefs.on("ui", "reduce_flashes")


# ----------------------------------------------------------------------------- frames --

func on_frame(dt: float) -> void:
	_frames += 1
	WorldStage.on_frame(main, _frames)
	if pop_layer == null:
		return
	var t0 := Time.get_ticks_usec() if _cost else 0
	_now += dt
	_calm = calm()
	_track_house()
	_track_session()
	var live := _step_pops(dt)
	var me = _me()
	_near = {}
	if me != null and not looted.is_empty():
		var here := Vector2(me.x, me.y)
		var best := STAND_REACH
		for c in looted:
			var d: float = CarLoot.rect_dist(here, c.rect) if c.has("rect") else here.distance_to(c.pos)
			if d <= best:
				best = d
				_near = c
	if layer != null and (not looted.is_empty() or drawn_ticks > 0):
		layer.queue_redraw()
	if live or drawn_pops > 0:
		pop_layer.queue_redraw()
	if _cost:
		cost_us += float(Time.get_ticks_usec() - t0)
		cost_frames += 1
		_cost_report()


## The looted containers of the avatar's house, made again when the house changes or the number of the looted does.
func _track_house() -> void:
	var me = _me()
	var search = sim.get("search") if sim != null else null
	var houses = sim.get("houses") if sim != null else null
	var h := -1
	if me != null and houses != null:
		h = int(houses.house_at(me.x, me.y))
	var n: int = search.looted.size() if search != null else 0
	if h == _house and n == _looted_n:
		return
	_house = h
	_looted_n = n
	looted = []
	if search == null or houses == null:
		return
	if h < 0:
		# (SCAV3: outside every house, the cars and wrecks of the street that are searched: the tick over a car says nobody needs to open it again; `rect` is the car's footprint)
		var cars = houses.get("cars")
		if cars is Array:
			for c in cars:
				if search.is_looted(String(c.id)):
					looted.append({"id": String(c.id), "at": Vector2(c.at), "pos": Vector2(c.pos), "rect": c.rect})
		return
	for c in houses.containers_of(h):
		if search.is_looted(String(c.id)):
			looted.append({"id": String(c.id), "at": Vector2(c.at), "pos": Vector2(c.pos)})


## The looted container the avatar stands at ({"id", "at", "pos"}), or {} (the overlay's "Searched" stand-in).
func searched_near() -> Dictionary:
	return _near


## A tick on the sound when a timed session ends at its full length (not one that was stopped, or that the avatar walked out of).
func _track_session() -> void:
	var uses = sim.get("uses") if sim != null else null
	if uses == null or not uses.has_method("progress"):
		return
	var pr: Dictionary = uses.progress()
	var label := String(pr.get("label", ""))
	if label == "" and _last_label != "" and _last_of > 0.0 and _last_t >= _last_of - 0.25:
		var sound = main.get("sound")
		if sound != null and sound.has_method("ui"):
			sound.ui("ui_hover", 0.75, 0.03)
	_last_label = label
	_last_t = float(pr.get("t", 0.0))
	_last_of = float(pr.get("of", 0.0))


# ------------------------------------------------------------------------------ events --

func on_event(e: Dictionary) -> void:
	if pop_layer == null or String(e.get("type", "")) != "searched" or sim == null or sim.get("houses") == null:
		return
	var cont: Dictionary = sim.houses.container(String(e.get("container", "")))
	var at := Vector2(cont.at) if cont.has("at") else Vector2.ZERO
	if at == Vector2.ZERO:
		var me = _me()
		if me != null:
			at = Vector2(me.x, me.y)
	var loot = e.get("loot", {})
	var i := 0
	if loot is Dictionary:
		for k in KINDS:
			var n := roundi(float(loot.get(k, 0.0)))
			if n > 0:
				_spawn("+%d %s" % [n, WORDS[k]], _color_of(k), at, i, String(k))
				i += 1
	if i == 0:
		_spawn("Empty", hud.INK3 if hud != null else Color.GRAY, at, 0, "")


func _color_of(kind: String) -> Color:
	if hud == null:
		return Color.WHITE
	match kind:
		"food":
			return hud.OK
		"water":
			return hud.INFO
		"ammo":
			return hud.INK
		"scrap":
			return hud.ACCENT
		"meds":
			return hud.DANGER_TEXT
	return hud.INK


func _spawn(text: String, col: Color, at: Vector2, index: int, kind: String) -> void:
	var p: Pop = null
	for q in pops:
		if not q.alive:
			p = q
			break
	if p == null:
		p = pops[0]    # (the oldest is the first: a ninth pop in a second and a half takes its place)
	p.alive = true
	p.text = text
	p.color = col
	p.at = at
	p.age = 0.0
	p.delay = 0.14 * float(index)
	p.dx = (-1.0 if index % 2 == 0 else 1.0) * 10.0 * float(index)
	p.flies = kind != ""
	p.target = Vector2(-1000.0, -1000.0)
	if p.flies and hud != null and hud.has_method("anchor_rect"):
		var r: Rect2 = hud.anchor_rect("stores." + kind)
		if r.size == Vector2.ZERO:
			r = hud.anchor_rect("stores")
		if r.size != Vector2.ZERO:
			p.target = r.get_center()
		else:
			p.flies = false


## Ages the pops; true while any is up.
func _step_pops(dt: float) -> bool:
	var live := false
	for p in pops:
		if not p.alive:
			continue
		if p.delay > 0.0:
			p.delay -= dt
			live = true
			continue
		p.age += dt
		if p.age >= POP_S:
			p.alive = false
			continue
		live = true
	return live


# ----------------------------------------------------------------------------- drawing --

## World tile -> window pixel (the camera is main's: centre tile and pixels per tile).
func screen_of(tile: Vector2) -> Vector2:
	var vp := pop_layer.size if pop_layer != null else Vector2(1280, 800)
	var cam: Vector2 = main.get("cam_center") if main.get("cam_center") is Vector2 else Vector2.ZERO
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	return (tile - cam) * z + vp * 0.5


## The ticks (on the layer under the overlay).
func _draw_layer() -> void:
	drawn_ticks = 0
	if hud == null or main == null or layer == null:
		return
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	var me = _me()
	var bounds := Rect2(Vector2.ZERO, pop_layer.size).grow(30.0)
	if me != null and not looted.is_empty():
		var here := Vector2(me.x, me.y)
		for c in looted:
			var a := clampf((TICK_FAR - here.distance_to(c.at)) / (TICK_FAR - TICK_NEAR), 0.0, 1.0)
			if a <= 0.02:
				continue
			# (on the furniture's upper left: the YOU tag over the avatar's head, where she stands at it, is on the right)
			var at := screen_of(c.at) + Vector2(-minf(0.3 * z, 24.0), -minf(0.2 * z, 16.0))
			if not bounds.has_point(at):
				continue
			_draw_tick(at, a)
			drawn_ticks += 1


## The pops (on the HUD's layer, over its boards).
func _draw_pops() -> void:
	drawn_pops = 0
	if hud == null or main == null:
		return
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	for p in pops:
		if p.alive and p.delay <= 0.0:
			_draw_pop(p, z)
			drawn_pops += 1


## A round badge with a check mark: dark slate, the HUD's green ring and tick. One picture made at the start (twice the size, from distance fields), drawn as a rectangle so that
## every tick in view is one draw call together; it fades by its colour's alpha.
func _draw_tick(at: Vector2, a: float) -> void:
	layer.draw_texture_rect(_badge, Rect2(at - Vector2(TICK_R, TICK_R), Vector2(TICK_R * 2.0, TICK_R * 2.0)), false, Color(1.0, 1.0, 1.0, a))


## The badge's picture: a dark disc, a green ring and a green check mark.
func _make_badge() -> ImageTexture:
	var n := int(TICK_R * 4.0)
	var c := float(n) * 0.5
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var green: Color = hud.OK if hud != null else Color("#8fb85a")
	var dark := Color(0.04, 0.08, 0.07, 0.9)
	var r := c - 1.0
	var pa := Vector2(c * 0.56, c * 1.05)
	var pb := Vector2(c * 0.88, c * 1.36)
	var pc := Vector2(c * 1.45, c * 0.66)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(Vector2(c, c))
			var a_disc := clampf(r + 0.5 - d, 0.0, 1.0)
			var a_ring := clampf(1.6 + 0.5 - absf(d - (r - 1.6)), 0.0, 1.0) * a_disc
			var d_check := minf(_seg_dist(p, pa, pb), _seg_dist(p, pb, pc))
			var a_check := clampf(2.1 + 0.5 - d_check, 0.0, 1.0)
			var a_g := maxf(a_ring, a_check) * a_disc
			var out_a := a_g + a_disc * dark.a * (1.0 - a_g)
			var col := Color(0, 0, 0, 0)
			if out_a > 0.0:
				var k := a_g / out_a
				col = Color(green.r * k + dark.r * (1.0 - k), green.g * k + dark.g * (1.0 - k), green.b * k + dark.b * (1.0 - k), out_a)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _draw_pop(p: Pop, z: float) -> void:
	var start := screen_of(p.at) + Vector2(p.dx, -minf(0.3 * z, 24.0))
	var pos: Vector2
	var alpha := 1.0
	var px := POP_PX
	if _calm or not p.flies:
		# (still: it stands above the container for the whole time, and goes; a pop with nowhere to go rises and fades)
		var rise := POP_RISE if _calm else POP_RISE * (1.0 - pow(1.0 - clampf(p.age / 0.5, 0.0, 1.0), 2.0))
		pos = start + Vector2(0.0, -rise)
		if not _calm:
			alpha = clampf((POP_S - p.age) / 0.4, 0.0, 1.0)
	else:
		var rise2 := POP_RISE * (1.0 - pow(1.0 - clampf(p.age / 0.5, 0.0, 1.0), 2.0))
		pos = start + Vector2(0.0, -rise2)
		var f := clampf((p.age - POP_FLY_AT) / (POP_S - POP_FLY_AT), 0.0, 1.0)
		if f > 0.0:
			pos = pos.lerp(p.target, f * f)
			px = maxi(12, roundi(float(POP_PX) * (1.0 - 0.3 * f)))
			alpha = 1.0 - smoothstep(0.65, 1.0, f)
		alpha *= clampf(p.age / 0.1, 0.0, 1.0)
	var font := Fonts.cond(700)
	var w := font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var at := pos - Vector2(w * 0.5, 0.0)
	pop_layer.draw_string_outline(font, at, p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 5, Color(0.0, 0.0, 0.0, 0.85 * alpha))
	pop_layer.draw_string(font, at, p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(p.color, alpha))


# -------------------------------------------------------------------------------- cost --

## `--worldfx-cost`: the last 60 frames before the shot are measured (the first ones load things); one line, printed two frames before the screenshot, with room_flash.gd's.
func _cost_report() -> void:
	if _cost_done or String(main.get("shot_path")) == "":
		return
	if int(main.get("frame_count")) == maxi(int(main.get("shot_frames")) - 60, 60):
		cost_us = 0.0
		cost_frames = 0
		var flash = main.town.part("room_flash") if main.get("town") != null else null
		if flash != null:
			flash.cost_us = 0.0
			flash.cost_frames = 0
	var left := int(main.get("shot_frames")) - int(main.get("frame_count"))
	if left <= 2 and cost_frames > 0:
		_cost_done = true
		var flash2 = main.town.part("room_flash") if main.get("town") != null else null
		var fl_us: float = float(flash2.cost_us) / maxf(float(flash2.cost_frames), 1.0) if flash2 != null else 0.0
		print("worldfx cost per frame: search_marks %.1f us, room_flash %.1f us (%d frames)" % [cost_us / float(cost_frames), fl_us, cost_frames])
