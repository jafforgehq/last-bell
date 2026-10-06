## Searching the whole room, seen and pressed (One House, LOOT): a VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`, `on_event(e)`,
## `on_key(ev)`). The rules are scripts/town/room_search.gd (`sim.room_search`: the offer, `begin()`, the walk, the stops); this part is the key, the words and the marks:
##
##   - THE SECOND PROMPT LINE. In a revealed room with two or more containers not searched, a pill under the normal E prompt (or beside her feet when there is none): "Hold E: search the whole
##     room (4 containers, about 21 s)". With dead in the room it is the grey pill with the reason under it in amber: "There are dead in this room".
##   - THE HOLD. E pressed with the offer up: whatever the normal prompt does happens at once (a tap of E begins the search of the container at her feet, as ever); E held for HOLD_S (0.6 s)
##     begins the room's search (the one in hand is taken over: its seconds count). With no normal prompt at all (she stands in the middle of the room) the press is this part's: let go before
##     HOLD_S it says "Hold E to search the whole room". A ring on the pill fills while the key is held.
##   - THE SESSION. A ring round her body that fills over the whole job, with the words "Searching: 3 of 7" on its left, and a ring on the container she is walking to. E at the container
##     in hand ("Stop searching"), a walking key, the trigger or the swing stops it. The loot pops of each container are the search marks' own (scripts/ui/search_marks.gd).
##   - THE END. A chip under the objective card for CHIP_S seconds: "Room searched: +9 scrap, +4 food" (the sum of the pops), or "Room search stopped: +3 scrap" with what was found; a
##     stop that the player did not make says why in a toast (hurt, the dead awake nearby, the dead in the room).
## REDUCE MOTION / REDUCE FLASHES: the chip does not fade; the ring on the target does not pulse.
## COST. One Node2D in the overlay's canvas layer, over the overlay (a few arcs and two pills, drawn only while the offer is up or a session runs). `--roomsearch=MODE[:ARG][:mid]` stages
## the pictures (see `_read_flags`).
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const Access := preload("res://scripts/access.gd")
const S := preload("res://scripts/render/shapes.gd")
const RoomSearch := preload("res://scripts/town/room_search.gd")
const SearchMarks := preload("res://scripts/ui/search_marks.gd")

const TILE_PX := 64.0
const HOLD_S := RoomSearch.HOLD_S
const CHIP_S := 4.0
const CHIP_FADE_IN := 0.15
const CHIP_FADE_OUT := 0.4
const FS := 13
const GAP := 5.0
const MAX_W := 460.0
const BACK := Color(0.043, 0.078, 0.067, 0.93)
const TRACK := Color(0.02, 0.04, 0.035, 0.6)
const GOLD := Color(0.941, 0.761, 0.29)
## The words of what a stop that the player did not make says (the others, the keys' own, say nothing).
const STOP_WORDS := {
	"hurt": ["Search stopped: you are hurt", "warn"],
	"woke": ["Search stopped: the dead are awake nearby", "warn"],
	"dead": ["Search stopped: there are dead in the room", "warn"],
	"stuck": ["Search stopped: there is no way to the next one", "warn"],
}

var main
var hud
var sim
var layer: Node2D
var chip: PanelContainer
var chip_label: Label
## What the chip says now ("" while it is not up) and for how many more seconds.
var chip_text := ""
var chip_left := 0.0
## What was drawn at the last frame: the second line's words ("" for none), the session's tag, and whether the target ring was.
var line_text := ""
var tag_text := ""
var drew_target := false
## The seconds the key has been held at the offer.
var hold := 0.0
var cost_us := 0.0
var cost_frames := 0

var _down := false
var _swallowed := false
var _fired := false
var _frozen := false
var _drawn := false
var _calm := false
var _clock := 0.0
var _frames := 0
var _stage_mode := ""
var _stage_arg := -1.0
var _stage_mid := false
var _stage_done := false
var _release_at := -1.0
var _off := false
var _boxes := {}
var _markers := {}


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	sim = main.get("sim")
	_read_flags()
	if "--noroomsearch" in OS.get_cmdline_user_args():
		_off = true    # (a shot or a measurement without this part's drawing and chip: the picture the game had before it)
	if _off or hud == null or sim == null or sim.get("room_search") == null:
		return
	var overlay = main.get("overlay")
	if overlay != null and overlay.get_parent() != null:
		layer = Node2D.new()
		layer.name = "RoomSearch"
		layer.draw.connect(_draw_layer)
		overlay.get_parent().add_child(layer)
		overlay.get_parent().move_child(layer, overlay.get_index() + 1)    # (over the overlay: the pill sits under the overlay's own E prompt, in the place the overlay left)
	_build_chip()
	_marker(true)    # (the pictures are made while the town loads, not by the first frame that shows the line)
	_marker(false)


func _me():
	if sim == null or sim.get("avatar") == null or String(sim.get("player_id")) == "":
		return null
	return sim.avatar.player()


func _rs():
	return sim.get("room_search") if sim != null else null


## The chip: a slim panel in the objective's column under its card, as scripts/ui/room_flash.gd's is (the two are never up together for long).
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


# ------------------------------------------------------------------------------- keys --

func _allowed() -> bool:
	if main == null or main.get("avatar_mode") != true or main.avatar_hands_off() or main.raid_open():
		return false
	return main._allows("interact")


## E down. With the offer up the part starts counting the hold; when the normal prompt has nothing for the press (no container within reach) the press is the part's, and nothing else
## sees it (the leave-the-base offer and "Nothing here to use" are for a press that is not at a room).
func on_key(ev: InputEvent) -> bool:
	if not (ev is InputEventKey) or int(ev.keycode) != KEY_E or ev.ctrl_pressed or ev.meta_pressed or ev.alt_pressed or not ev.pressed:
		return false
	if ev.echo:
		return _swallowed
	_down = false
	_swallowed = false
	_fired = false
	hold = 0.0
	var rs = _rs()
	if _off or rs == null or not _allowed() or rs.active():
		return false
	if rs.offer().is_empty():
		return false
	_down = true
	var overlay = main.get("overlay")
	if overlay != null and overlay.prompt_candidate().is_empty():
		_swallowed = true
		return true
	return false


# ----------------------------------------------------------------------------- frames --

func on_frame(dt: float) -> void:
	_frames += 1
	var t0 := Time.get_ticks_usec()
	_calm = Access.calm_flashes()
	_clock += dt
	_stage(dt)
	_step_chip(dt)
	_step_hold(dt)
	if layer != null:
		var rs = _rs()
		var live: bool = rs != null and (rs.active() or not rs.offer().is_empty())
		if live or _drawn:
			layer.queue_redraw()
	cost_us += float(Time.get_ticks_usec() - t0)
	cost_frames += 1


func _step_hold(dt: float) -> void:
	if not _down:
		return
	var rs = _rs()
	if _frozen:
		return
	if not Input.is_key_pressed(KEY_E):
		# let go: a press that was this part's and was short says what the key is for
		if _swallowed and not _fired and hold < HOLD_S and rs != null and not rs.active() and hud != null:
			hud.toast("Hold E to search the whole room", "info")
		_down = false
		_swallowed = false
		hold = 0.0
		return
	if _fired:
		return
	hold += dt
	if hold >= HOLD_S:
		_fire()


## The key has been held long enough: the rules begin the room's search, or say why not.
func _fire() -> void:
	_fired = true
	var rs = _rs()
	if rs == null or not _allowed():
		return
	var r: Dictionary = rs.begin()
	if _stage_mode != "":
		print("--roomsearch: E held %.2f s: begin -> %s" % [hold, r])
	if bool(r.get("ok", false)):
		hud.toast(String(r.get("line", "Searching the room")), "info")
	else:
		hud.toast(String(r.get("why", "Nothing to search here")), "warn")


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


# ---------------------------------------------------------------------------- events --

## "+9 scrap, +4 food": the loot of a session, the most first (a kind of the stores that the pops know by name; the others by their key).
static func loot_words(loot: Dictionary) -> String:
	var kinds: Array = []
	for k in loot:
		if int(loot[k]) > 0:
			kinds.append(String(k))
	kinds.sort_custom(func(a, b):
		var da := int(loot[a])
		var db := int(loot[b])
		return da > db or (da == db and SearchMarks.KINDS.find(a) < SearchMarks.KINDS.find(b)))
	var parts: Array = []
	for k in kinds:
		parts.append("+%d %s" % [int(loot[k]), String(SearchMarks.WORDS.get(k, k))])
	return ", ".join(parts)


func on_event(e: Dictionary) -> void:
	if String(e.get("type", "")) != "room_searched" or chip == null:
		return
	var why := String(e.get("why", ""))
	var words := loot_words(e.get("loot", {}))
	var found := int(e.get("n", 0))
	if _stage_mode != "":
		print("--roomsearch: told: %s" % [e])
	if why == "done":
		chip_text = "Room searched: %s" % (words if words != "" else "nothing found")
	elif found > 0:
		chip_text = "Room search stopped: %s" % (words if words != "" else "nothing found")
	else:
		chip_text = ""
	if chip_text != "":
		chip_label.text = chip_text
		chip_left = CHIP_S
		chip.visible = true
		chip.modulate.a = 1.0 if _calm else 0.0
	if STOP_WORDS.has(why) and hud != null:
		hud.toast(String(STOP_WORDS[why][0]), String(STOP_WORDS[why][1]))


# ------------------------------------------------------------------------------ drawing --

func _screen(tile: Vector2) -> Vector2:
	return layer.get_viewport().get_canvas_transform() * (tile * TILE_PX)


func _draw_layer() -> void:
	line_text = ""
	tag_text = ""
	drew_target = false
	_drawn = false
	var rs = _rs()
	var me = _me()
	if layer == null or rs == null or me == null or me.dead or me.turned or me.away != null or not _allowed():
		return
	var pr: Dictionary = rs.progress()
	if bool(pr.get("active", false)):
		_draw_session(me, pr)
		return
	var off: Dictionary = rs.offer()
	if not off.is_empty():
		_draw_offer(me, off)


## The pill under the E prompt.
func _draw_offer(me, off: Dictionary) -> void:
	var ok := bool(off.get("ok", true))
	var label := "Hold E: search the whole room (%d containers, about %d s)" % [int(off.n), maxi(1, roundi(float(off.secs)))]
	var why := String(off.get("why", ""))
	var font := Fonts.sans(600)
	var lw := minf(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x, MAX_W - 44.0)
	var ww := minf(font.get_string_size(why, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x, MAX_W - 44.0) if why != "" else 0.0
	var w := 8.0 + 26.0 + 6.0 + maxf(lw, ww) + 14.0
	var one := 30.0
	var h := 48.0 if why != "" else one
	var vp := layer.get_viewport_rect().size
	var view := Rect2(4.0, 4.0, vp.x - 8.0, vp.y - 8.0)
	var overlay = main.get("overlay")
	var covered: Array = overlay._covered_by_hud() if overlay != null and overlay.has_method("_covered_by_hud") else []
	var spots: Array = []
	if overlay != null and bool(overlay.drew_prompt) and (overlay.prompt_rect as Rect2).size != Vector2.ZERO:
		var pr: Rect2 = overlay.prompt_rect
		spots.append(Vector2(pr.position.x, pr.end.y + GAP))
		spots.append(Vector2(pr.position.x, pr.position.y - h - GAP))
	else:
		var pp: Vector2 = main.view_pos(me)
		var feet := _screen(pp)
		var z := float(main.get("zoom_px"))
		var rx := clampf(z * 0.5, 14.0, 70.0)
		spots.append(Vector2(feet.x + rx + 10.0, feet.y - 0.4 * h - 6.0))
		spots.append(Vector2(feet.x - rx - 10.0 - w, feet.y - 0.4 * h - 6.0))
		spots.append(Vector2(feet.x - w * 0.5, feet.y + rx * 0.5 + 24.0))
	var rect := Rect2()
	var found := false
	for at in spots:
		var r := Rect2(at, Vector2(w, h))
		if view.encloses(r) and not _under(r, covered):
			rect = r
			found = true
			break
	if not found:
		return
	# (the pill is one style box and the ring's marker one picture, so that the whole line is a handful of draw calls: the shapes first, the words last)
	layer.draw_style_box(_box("offer_ok" if ok else "offer_grey", minf(14.0, rect.size.y * 0.5), GOLD if ok else hud.INK3, 0.8), rect)
	var c := Vector2(rect.position.x + 8.0 + 13.0, rect.position.y + one * 0.5)
	var t := clampf(hold / HOLD_S, 0.0, 1.0) if _down else 0.0
	layer.draw_texture_rect(_marker(ok), Rect2(c - Vector2(13.0, 13.0), Vector2(26.0, 26.0)), false)
	if t > 0.004:
		layer.draw_arc(c, 9.0, -PI / 2.0, -PI / 2.0 + t * TAU, 28, GOLD, 4.0, true)
	var tx := rect.position.x + 8.0 + 26.0 + 6.0
	layer.draw_string(font, Vector2(tx, rect.position.y + one * 0.5 + FS * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, MAX_W - 44.0, FS, hud.INK if ok else hud.INK2)
	if why != "":
		layer.draw_string(font, Vector2(tx, rect.position.y + one + FS * 0.85), why, HORIZONTAL_ALIGNMENT_LEFT, MAX_W - 44.0, FS, hud.WARN)
	line_text = label if why == "" else "%s  [%s]" % [label, why]
	_drawn = true


## A pill's look (the slate, a rim in `edge` at `alpha`, round to `radius`), made once for each `key`.
func _box(key: String, radius: float, edge: Color, alpha: float) -> StyleBoxFlat:
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null or int(sb.corner_radius_top_left) != int(radius):
		sb = StyleBoxFlat.new()
		sb.bg_color = BACK
		sb.border_color = Color(edge, alpha)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(radius))
		sb.anti_aliasing = true
		_boxes[key] = sb
	return sb


## The ring that stands for the key's hold on the second line: a dark track, the thin pale ring and a dot (gold, or grey for a line that is refused), twice the size, made once.
func _marker(ok: bool) -> ImageTexture:
	var key := "ok" if ok else "grey"
	if _markers.has(key):
		return _markers[key]
	var n := 52
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(26.0, 26.0)
	var dot: Color = GOLD if ok else Color(0.66, 0.68, 0.62)
	var pale := Color(0.93, 0.96, 0.89)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a_track := clampf(4.5 + 0.5 - absf(d - 18.0), 0.0, 1.0) * TRACK.a
			var a_thin := clampf(1.7 + 0.5 - absf(d - 18.0), 0.0, 1.0) * (0.55 if ok else 0.35)
			var a_dot := clampf(6.4 + 0.5 - d, 0.0, 1.0)
			var out := Color(0, 0, 0, 0)
			out = _over(out, Color(TRACK, a_track))
			out = _over(out, Color(pale, a_thin))
			out = _over(out, Color(dot, a_dot))
			img.set_pixel(x, y, out)
	var tex := ImageTexture.create_from_image(img)
	_markers[key] = tex
	return tex


## `top` over `bottom`, both straight (not premultiplied) colours.
static func _over(bottom: Color, top: Color) -> Color:
	var a := top.a + bottom.a * (1.0 - top.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	return Color((top.r * top.a + bottom.r * bottom.a * (1.0 - top.a)) / a, (top.g * top.a + bottom.g * bottom.a * (1.0 - top.a)) / a, (top.b * top.a + bottom.b * bottom.a * (1.0 - top.a)) / a, a)


func _under(rect: Rect2, covered: Array) -> bool:
	for r in covered:
		if (r as Rect2).intersects(rect):
			return true
	return false


## The ring round her body that fills over the whole job, the words on its left and the ring on the container she is on her way to.
func _draw_session(me, pr: Dictionary) -> void:
	var z := float(main.get("zoom_px"))
	var pp: Vector2 = main.view_pos(me)
	var body := _screen(Vector2(pp.x, pp.y - 0.45))
	var r := maxf(18.0, 0.55 * z)
	layer.draw_arc(body, r, 0.0, TAU, 48, TRACK, 5.0, true)
	var t := float(pr.t)
	if t > 0.004:
		layer.draw_arc(body, r, -PI / 2.0, -PI / 2.0 + t * TAU, 48, GOLD, 3.5, true)
	var font := Fonts.cond(700)
	var text := String(pr.label)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x + 12.0
	var box := Rect2(body.x - r - 8.0 - tw, body.y - 9.0, tw, 18.0)
	layer.draw_style_box(_box("tag", 9.0, GOLD, 0.7), box)
	layer.draw_string(font, Vector2(box.position.x + 6.0, body.y + FS * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, tw, FS, hud.ACCENT)
	tag_text = text
	# the container she is on her way to (or at): a ring on the floor under it
	var at := Vector2(pr.get("at", Vector2.ZERO))
	if at != Vector2.ZERO:
		var spot := _screen(at)
		var rx := clampf(z * 0.6, 14.0, 60.0)
		var pulse := 0.5 if _calm else 0.5 + 0.5 * sin(_clock * 5.0)
		layer.draw_set_transform(spot, 0.0, Vector2(1.0, 0.5))
		layer.draw_arc(Vector2.ZERO, rx, 0.0, TAU, 36, Color(0.043, 0.078, 0.067, 0.7), 4.5, true)
		layer.draw_arc(Vector2.ZERO, rx, 0.0, TAU, 36, Color(GOLD, 0.55 + 0.45 * pulse), 2.5, true)
		layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		drew_target = true
	_drawn = true


# ------------------------------------------------------------------------------ staging --

## `--roomsearch=MODE[:ARG][:mid]`: a screenshot has no player. The avatar is put in the room (of every house of the town) that has the most containers not searched, the room is looked into
## and its dead taken out (their records closed, as `--stage=cleared` does), and
##   idle           the clock stops: the shimmer on every container, the second prompt line (standing at the nearest container, so that the normal E prompt is above it)
##   hold[:F]       the same with the key held F (0.5) of the 0.6 s: the ring filling on the line
##   go             the room's search begins at once and the game runs (give `--speed=3 --frames=N`: at 60 frames a second a frame is a twentieth of a second of the game at speed 3)
##   press[:S]      the real key: E goes down through the engine's input and is let go S (1.5) seconds later (0.3: a tap), the game running (`--speed=3 --frames=N`)
##   done           the whole job is run at once and the clock stops: the chip "Room searched: ..." (give `--frames=90`: it is up for 4 s)
##   dead           a dead one stands in the room (not closed): the grey pill with the amber reason, the grey red shimmer
## `:mid` stands her in the middle of the room, away from every container (the line with no normal prompt over it).
func _read_flags() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if not a.begins_with("--roomsearch"):
			continue
		var bits := a.trim_prefix("--roomsearch").trim_prefix("=").split(":")
		_stage_mode = bits[0] if bits[0] != "" else "idle"
		for i in range(1, bits.size()):
			if bits[i] == "mid":
				_stage_mid = true
			elif bits[i].is_valid_float():
				_stage_arg = float(bits[i])


## E down or up through the engine's own input (the staging's stand-in for a finger).
func _press(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.physical_keycode = KEY_E
	ev.pressed = down
	Input.parse_input_event(ev)


func _stage(_dt: float) -> void:
	if _release_at > 0.0 and _clock >= _release_at:
		_release_at = -1.0
		_press(false)
	if _stage_mode == "" or _stage_done or sim == null or _me() == null:
		return
	var shot := String(main.get("shot_path")) != ""
	var now: int = int(main.get("frame_count")) if shot else _frames
	if now < 6:
		return
	_stage_done = true
	var rs = _rs()
	if rs == null:
		print("--roomsearch: no room_search module")
		return
	var room := _stage_pick()
	if room < 0:
		print("--roomsearch: no room with containers to search")
		return
	var me = _me()
	var hs = sim.houses
	var rm: Dictionary = hs.room(room)
	var h := int(rm.get("house", -1))
	var rect := Rect2i(rm.get("rect", Rect2i()))
	var centre := Vector2(rect.get_center()) + Vector2(0.5, 0.5)
	var list: Array = RoomSearch.unsearched(sim, h, room)
	# the dead of the room taken out (all of them near it: a woken one would stop the session), unless the picture is of a room with the dead in it
	var field = sim.get("field")
	var closed := 0
	if field != null:
		for i in field.n:
			if int(field.status[i]) != 0:
				continue
			var at_i := Vector2(field.xs[i], field.ys[i])
			if _stage_mode == "dead" and rect.grow(1).has_point(Vector2i(floori(at_i.x), floori(at_i.y))):
				continue    # (the dead of this room stay: the picture is of a room that has them)
			if at_i.distance_to(centre) <= 26.0:
				field.remove_record(i)
				closed += 1
	var stand := centre
	if _stage_mid:
		stand = _free_spot(centre, list)
	else:
		var best := INF
		for c in list:
			var d := Vector2(c.pos).distance_to(centre)
			if d < best:
				best = d
				stand = Vector2(c.pos)
	me.x = stand.x
	me.y = stand.y
	me.path = []
	me.moving = false
	me.input_move = Vector2.ZERO
	if sim.get("clearing") != null:
		sim.clearing.reveal(room, "stage")
	if _stage_mode == "dead" and field != null:
		field.add_record(centre + Vector2(1.5, 0.5), "walker", true)
	if sim.get("clearing") != null:
		sim.clearing.scan()
	print("--roomsearch=%s: house %d, %s (room %d) with %d containers, %d dead records closed; she stands at (%.1f, %.1f)" % [_stage_mode, h, String(rm.get("name", "")), room, list.size(), closed, stand.x, stand.y])
	match _stage_mode:
		"hold":
			_down = true
			_frozen = true
			_swallowed = false
			hold = HOLD_S * (_stage_arg if _stage_arg >= 0.0 else 0.5)
			main.speed = 0
		"go":
			var r: Dictionary = rs.begin()
			print("--roomsearch: begin: ", r)
		"press":
			# (the real key: E goes down through the engine's input, as the player's does, and is let go ARG (1.5) seconds later; give `--speed=3 --frames=N`)
			_press(true)
			_release_at = _clock + (_stage_arg if _stage_arg >= 0.0 else 1.5)
		"done":
			# (the whole job run at once, the rules' own steps: the pops of every container rise together, and the chip says the sum; give `--frames=90`)
			var r2: Dictionary = rs.begin()
			print("--roomsearch: begin: ", r2)
			var steps := 0
			while rs.active() and steps < 8000:
				sim.update(1.0 / 30.0)
				steps += 1
			print("--roomsearch: done after %.1f s of the game: %s" % [float(steps) / 30.0, rs.last])
			main.speed = 0
		_:
			main.speed = 0


## The room of the town with the most containers not searched (two or more), the nearest to her when two have as many.
func _stage_pick() -> int:
	var me = _me()
	var hs = sim.houses
	var best := -1
	var best_n := 1
	var best_d := INF
	for h in hs.count():
		var per := {}
		for c in RoomSearch.unsearched(sim, h, -1):
			var r := int(c.get("room", -1))
			if r >= 0:
				per[r] = int(per.get(r, 0)) + 1
		for r in per:
			var rect := Rect2i(hs.room(int(r)).get("rect", Rect2i()))
			var d := Vector2(rect.get_center()).distance_to(Vector2(me.x, me.y))
			if int(per[r]) > best_n or (int(per[r]) == best_n and best >= 0 and d < best_d):
				best = int(r)
				best_n = int(per[r])
				best_d = d
	return best


## A free tile near `centre`, at least 1.5 tiles from the container spots of `list`.
func _free_spot(centre: Vector2, list: Array) -> Vector2:
	for ring in range(0, 6):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var p := Vector2(floorf(centre.x) + float(dx) + 0.5, floorf(centre.y) + float(dy) + 0.5)
				if sim.houses.room_at(p.x, p.y) < 0 or sim.world.is_solid(sim.world.solid_p, p.x, p.y):
					continue
				var far := true
				for c in list:
					if p.distance_to(Vector2(c.pos)) < 1.5 or p.distance_to(Vector2(c.at)) < 1.3:
						far = false
				if far:
					return p
	return centre
