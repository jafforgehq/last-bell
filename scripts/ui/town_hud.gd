## The town's part of the HUD (One House, WP7): what the player reads in the town that is not the stores, the clock or the crew bar.
##
##   - the OBJECTIVE card (top left, under the stores): the text of `sim.scenario.objective()` with what is under it, "2 of 3", and a bearing arrow
##     to where it is ("at") with the distance in tiles; the same arrow is drawn round the avatar's feet while the place is far
##   - the banner "The house is clear" the first time each house is cleared, and a toast for each room that is cleared, each container searched,
##     each fence section lost (a project finished is an alert card: "The front fence is up")
##   - the RING of the session in hand (a search, the claim, a mend: `sim.uses.progress()` = {"label", "t", "of"}), round the avatar's body
##   - the guide's LESSON card (bottom left, small, skippable): `sim.scenario.guide()` = {"id", "text", "goal", "done"}
##   - the line "Nobody is on the radio yet" while the avatar is alone
##   - the keys the town adds: M opens the Map page; Shift+N and Shift+G open the panel's pages (the modal school pages are not the town's)
##
## It is a VIEW PART of the town's facade (scripts/town/town_game.gd calls `on_ready(main)`, `on_frame(dt)`, `on_event(e)`, `modal()`, `on_key(ev)`).
## It reads the rules through `sim.get(...)` and `has_method`, so a game without a module just has less on the screen, and it never writes the rules.
## It also puts the HUD in the town's calm profile (`hud.set_profile("one_house")`: no Town Board, Scavenge or car).
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Arrival := preload("res://scripts/town/arrival.gd")
const KeyLegend := preload("res://scripts/ui/key_legend.gd")
const AlertFeed := preload("res://scripts/ui/alert_feed.gd")

## The setting (a flag in the player's own file) that puts the lessons of the first house away for good.
const LESSONS_OFF_FLAG := "oh_lessons_off"

const CARD_W := 292.0
const CARD_W_COMPACT := 236.0
## How often (seconds) the cards are read again; the ring and the arrow are redrawn every frame while they are up.
const REFRESH_S := 0.1
## The arrow round the avatar shows from this many tiles away; and how far from the avatar it sits (pixels, at least).
const ARROW_FAR := 7.0
const ARROW_RING_MIN := 58.0
const RING_MIN_R := 18.0
const TILE_WORD := "m"
## How long (seconds) the first view of the entry (or of the start house) is held before the camera comes to the avatar.
## (TEMPO, 2026-10-07: it was 5.0)
const OPENING_HOLD_S := 3.0
## The opening view of an arrival: tiles across the window, and how many tiles ahead of the avatar (the way in) the camera looks.
const ENTRY_VIEW_TILES := 40.0
const ENTRY_AHEAD := 7.0
## How long (rules seconds) the legend of the keys stays at the foot of the window, and how long it takes to fade at the end.
const LEGEND_S := 45.0
const LEGEND_FADE_S := 1.0
const NOBODY_TEXT := "Nobody is on the radio yet"

var main
var hud
var layer: Control
var obj_card: PanelContainer
var obj_caps: Label
var obj_step: Label
var obj_text: Label
var obj_sub: Label
var obj_arrow: Control
var obj_dist: Label
var lesson_card: PanelContainer
var lesson_step: Label
var lesson_text: Label
var lesson_goal: Label
var lesson_done: Label
var lesson_skip: Button
var lesson_off: Button
var radio_card: PanelContainer
var radio_label: Label
## HUDA: the legend of the keys (scripts/ui/key_legend.gd) and whether the player has opened the radio (the pill under the objective waits for a reason).
var legend: PanelContainer
var _radio_opened := false
var _alerts_staged := false

## What the cards say now (the tests read them).
var objective := {}
var lesson := {}
## The banners shown (house ids) and how many: "The house is clear" is said once for each house.
var banners_shown: Array = []
var banner_count := 0
## The ring of the session in hand: its fraction (0 to 1) and words, "" while there is none.
var ring_t := 0.0
var ring_label := ""
## The bearing of the objective from the avatar, radians on the screen (0 is east), and the distance in tiles; -1 when there is none.
var bearing := 0.0
var distance := -1.0
## Lesson ids that were skipped.
var skipped := {}

var _t := 0.0
var _dirty := true
var _arrow_on := false
var _last_obj_sig := ""
var _last_lesson_sig := ""


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	if hud.has_method("set_profile"):
		hud.set_profile("one_house")
	_build()
	var sim = _sim()
	if sim != null and float(sim.t) > 5.0:
		hud.hint_spent = true    # (a run that is loaded and on its way has seen the legend of the keys)


## The camera of a new run (the facade asks once, as the camera is first put): the start house, whole, and the street in front of its lot, held there a few seconds before the
## camera goes to the avatar and follows. Nothing for a run that is already on its way (a loaded save).
func on_opening_view(main_node) -> void:
	var sim = main_node.get("sim")
	if sim == null or sim.get("houses") == null or sim.scenario == null or not sim.scenario.has_method("stage"):
		return
	var stage := String(sim.scenario.stage())
	if float(sim.t) > 2.0 or int(sim.day) != 1 or (stage != "alone" and stage != "arrive"):
		return
	if stage == "arrive":
		_opening_at_entry(main_node, sim)
		return
	var h: Dictionary = sim.houses.house(sim.houses.start_house())
	if h.is_empty():
		return
	var rect := Rect2(Rect2i(h.get("rect", Rect2i())))
	var lot := Rect2(Rect2i(h.get("lot", Rect2i())))
	var north := String(h.get("front", "S")) == "N"
	var top := (lot.position.y - 3.0) if north else (rect.position.y - 3.0)
	var bottom := (rect.end.y + 3.0) if north else (lot.end.y + 3.0)
	var vp: Vector2 = main_node._vp()
	main_node.zoom_px = clampf(vp.y / maxf(bottom - top, 8.0), 30.0, 52.0)
	main_node.cam_center = Vector2(rect.get_center().x, (top + bottom) * 0.5)
	main_node.cam_hold = OPENING_HOLD_S


## The first view of an arrival: the road in front of her, the trees behind and the first houses ahead, wide (about `ENTRY_VIEW_TILES` tiles across), the camera a little ahead of her
## (she is in the lower part of the picture, facing in), held there a few seconds before it comes to the avatar and follows.
func _opening_at_entry(main_node, sim) -> void:
	var spawn: Dictionary = Arrival.spawn(sim.houses.town)
	var vp: Vector2 = main_node._vp()
	main_node.zoom_px = clampf(vp.x / ENTRY_VIEW_TILES, 24.0, 44.0)
	main_node.cam_center = Vector2(spawn.pos) + Vector2.from_angle(float(spawn.angle)) * ENTRY_AHEAD
	main_node.cam_hold = OPENING_HOLD_S


# ------------------------------------------------------------------------ the sim --

func _sim():
	return main.get("sim") if main != null else null


func _module(name: String):
	var s = _sim()
	return s.get(name) if s != null else null


func _scenario():
	return _module("scenario")


# --------------------------------------------------------------------------- build --

func _build() -> void:
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.draw.connect(_draw_layer)
	hud.add_child(layer)
	# (under the HUD's own boards: a ring and an arrow in the world are never over a panel)
	hud.move_child(layer, 0)
	_build_objective()
	_build_lesson()
	_build_radio_line()
	_build_legend()


func _style(slim: bool = true) -> StyleBox:
	var st: StyleBox = hud._style(hud.PANEL, 6, hud.LINE2, true, "panel_slim" if slim else "panel")
	if st is StyleBoxFlat:
		st.content_margin_left = 12
		st.content_margin_right = 12
		st.content_margin_top = 8
		st.content_margin_bottom = 9
	return st


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l: Label = hud._label(text, font, maxi(size, 14), color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 40
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _build_objective() -> void:
	obj_card = hud._panel(_style())
	obj_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	obj_card.custom_minimum_size.x = CARD_W
	obj_card.visible = false
	var col: VBoxContainer = hud._vbox(3)
	obj_card.add_child(col)
	var head: HBoxContainer = hud._hbox(8)
	obj_caps = hud._label("OBJECTIVE", Fonts.cond(700, 1), 14, hud.ACCENT)
	head.add_child(obj_caps)
	head.add_child(hud._spacer())
	obj_dist = hud._label("", Fonts.cond(700), 14, hud.ACCENT)
	head.add_child(obj_dist)
	obj_step = hud._label("", Fonts.cond(700), 14, hud.INK2)
	head.add_child(obj_step)
	col.add_child(head)
	var body: HBoxContainer = hud._hbox(8)
	obj_arrow = Control.new()
	obj_arrow.custom_minimum_size = Vector2(26, 26)
	obj_arrow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	obj_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_arrow.draw.connect(_draw_pill_arrow)
	obj_arrow.visible = false
	body.add_child(obj_arrow)
	obj_text = _label("", Fonts.sans(600), 15, hud.INK)
	body.add_child(obj_text)
	col.add_child(body)
	obj_sub = _label("", Fonts.sans(400), 14, hud.INK2)
	col.add_child(obj_sub)
	# under the stores, in the left column (the HUD lays it out and keeps the dock clear of it)
	hud.left_col.add_child(obj_card)
	hud.left_col.move_child(obj_card, mini(1, hud.left_col.get_child_count() - 1))


func _build_lesson() -> void:
	lesson_card = hud._panel(_style())
	lesson_card.visible = false
	lesson_card.custom_minimum_size.x = CARD_W
	var col: VBoxContainer = hud._vbox(2)
	lesson_card.add_child(col)
	var head: HBoxContainer = hud._hbox(8)
	# (TUTOR: the card is a small chip, "STEP 2 OF 8" and the verb in one line; the lesson is taught by a cue in the world, scripts/ui/tutor_cues.gd, and its words are the chip's tooltip)
	lesson_step = hud._label("STEP", Fonts.cond(700, 1), 14, hud.INFO)
	head.add_child(lesson_step)
	lesson_done = hud._label("Done", Fonts.cond(700), 14, hud.OK)
	lesson_done.visible = false
	head.add_child(lesson_done)
	head.add_child(hud._spacer())
	lesson_off = RadioKit.small_button(hud, "No lessons", 24.0, 14)
	lesson_off.tooltip_text = "Put all the lessons away, in this game and the next"
	lesson_off.pressed.connect(skip_all_lessons)
	head.add_child(lesson_off)
	lesson_skip = RadioKit.small_button(hud, "Skip", 24.0, 14)
	lesson_skip.tooltip_text = "Put this lesson away. The next one comes when you have done more"
	lesson_skip.pressed.connect(skip_lesson)
	head.add_child(lesson_skip)
	col.add_child(head)
	lesson_text = _label("", Fonts.sans(400), 14, hud.INK)    # (the lesson's words: kept for whoever reads them, shown as the card's tooltip, not on the card)
	lesson_text.visible = false
	col.add_child(lesson_text)
	lesson_goal = _label("", Fonts.sans(600), 15, hud.ACCENT)
	col.add_child(lesson_goal)
	lesson_card.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(lesson_card)


func _build_radio_line() -> void:
	radio_card = hud._panel(_style())
	radio_card.mouse_filter = Control.MOUSE_FILTER_PASS
	radio_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	radio_card.tooltip_text = "The radio is how you will hear from the people you find, and how you ask things of them. Open it with T"
	radio_card.visible = false
	var row: HBoxContainer = hud._hbox(8)
	row.add_child(hud._icon("radio", 16, hud.INK3))
	radio_label = hud._label(NOBODY_TEXT, Fonts.sans(400), 14, hud.INK2)
	row.add_child(radio_label)
	radio_card.add_child(row)
	hud.left_col.add_child(radio_card)
	hud.left_col.move_child(radio_card, mini(2, hud.left_col.get_child_count() - 1))


## The legend of the keys: bottom left, above the lesson card (`_place_lesson` puts it). The HUD's old bar at the bottom centre never shows in the town.
func _build_legend() -> void:
	legend = KeyLegend.new()
	layer.add_child(legend)
	legend.setup(hud)


# -------------------------------------------------------------------------- frames --

func on_frame(dt: float) -> void:
	if hud == null or main == null:
		return
	_t += dt
	if not _alerts_staged and Engine.get_frames_drawn() > 30:
		_alerts_staged = true    # (a screenshot's `--alerts=3|many`: sample alerts for the stack, see AlertFeed.stage)
		for arg in OS.get_cmdline_user_args():
			if String(arg).begins_with("--legend-did=") and legend != null:
				for id in String(arg).trim_prefix("--legend-did=").split(","):
					legend.mark(String(id))    # (a screenshot's `--legend-did=move,fire`: those hints as if done)
			if String(arg).begins_with("--alerts="):
				var spec := String(arg).trim_prefix("--alerts=")
				AlertFeed.stage(_sim(), spec.trim_suffix("-open"))
				if spec.ends_with("-open") and hud._alert_feed != null:
					hud._alert_feed.expanded = true    # (the stack as the pill's click unfolds it)
	if _t >= REFRESH_S or _dirty:
		_t = 0.0
		_dirty = false
		refresh()
		# (the legend of the keys at the foot of the window is the first minute's: with nobody to ask for anything it would stay up for ever, over the house)
		var sim = _sim()
		if not hud.hint_spent and sim != null and float(sim.t) > LEGEND_S:
			hud.hint_spent = true
			hud._refresh_hint()
	# the ring and the arrow follow the avatar: redrawn each frame while either is up
	if ring_label != "" or _arrow_on:
		layer.queue_redraw()
		if _arrow_on:
			obj_arrow.queue_redraw()
	_place_lesson()


## Reads the rules and brings the cards up to date (every REFRESH_S, and at once after an event).
func refresh() -> void:
	if hud == null:
		return
	_refresh_objective()
	_refresh_lesson()
	_refresh_radio()
	_refresh_ring()


func _player():
	var sim = _sim()
	if sim == null or sim.get("avatar") == null:
		return null
	return sim.avatar.player()


func _refresh_objective() -> void:
	var sc = _scenario()
	var o := {}
	if sc != null and sc.has_method("objective"):
		var got = sc.objective()
		if got is Dictionary:
			o = got
	objective = o
	var text := String(o.get("text", ""))
	var at = o.get("at")
	var me = _player()
	distance = -1.0
	_arrow_on = false
	if at is Vector2 and me != null:
		var d: Vector2 = (at as Vector2) - Vector2(me.x, me.y)
		distance = d.length()
		bearing = d.angle()
		_arrow_on = distance > ARROW_FAR and not _sleeping()
	var of := int(o.get("of", 0))
	var step := int(o.get("step", 0))
	var dist_text := ""
	if distance >= 0.0 and distance > ARROW_FAR:
		dist_text = "%d %s" % [roundi(distance), TILE_WORD]
	var sig := "%s|%s|%d|%d|%s" % [text, String(o.get("sub", "")), step, of, dist_text]
	obj_arrow.visible = _arrow_on
	if sig == _last_obj_sig:
		return
	_last_obj_sig = sig
	obj_card.visible = text != ""
	obj_text.text = text
	obj_sub.text = String(o.get("sub", ""))
	obj_sub.visible = obj_sub.text != ""
	obj_step.text = ("%d of %d" % [step, of]) if of > 1 else ""
	obj_dist.text = dist_text
	obj_dist.visible = dist_text != ""
	obj_card.tooltip_text = ""


func _refresh_lesson() -> void:
	var sc = _scenario()
	var g := {}
	if sc != null and sc.has_method("guide"):
		var got = sc.guide()
		if got is Dictionary:
			g = got
	lesson = g
	var id := String(g.get("id", ""))
	var shown := not g.is_empty() and String(g.get("text", "")) != "" and not skipped.has(id) and not Prefs.flag(LESSONS_OFF_FLAG)
	# (TUTOR: one short line: the verb, and for a lesson that counts the count: "Clear the house: 2 of 5 rooms clear")
	var verb := String(g.get("verb", g.get("goal", "")))
	var progress := String(g.get("progress", ""))
	if progress != "" and not bool(g.get("done", false)):
		verb = "%s: %s" % [verb, progress]
	var step := ("STEP %d OF %d" % [int(g.get("n", 0)), int(g.get("of", 0))]) if int(g.get("of", 0)) > 0 else "STEP"
	if bool(g.get("hint", false)):
		step = "HINT"    # (EARLY: the hint of a player who is stuck in the house: no step, one line)
	var sig := "%s|%s|%s|%s|%s" % [id, String(g.get("text", "")), verb, step, str(bool(g.get("done", false)))]
	lesson_card.visible = shown
	if sig == _last_lesson_sig:
		return
	_last_lesson_sig = sig
	lesson_text.text = String(g.get("text", ""))
	lesson_card.tooltip_text = lesson_text.text
	lesson_step.text = step
	lesson_goal.text = verb
	lesson_goal.visible = lesson_goal.text != ""
	lesson_done.visible = bool(g.get("done", false))


## The line under the objective is there once it has something to say (HUDA): a survivor has been rescued ("3 on the radio"), or the player has opened the radio
## and should be told that nobody is on it yet. Before that the radio is a button in the toolbar and the line would only be one more thing to read.
func _refresh_radio() -> void:
	if hud.radio_open():
		_radio_opened = true
	var n := on_the_radio()
	radio_card.visible = n > 0 or (_radio_opened and nobody_on_radio())
	var words := ("%d on the radio" % n) if n > 0 else NOBODY_TEXT
	if radio_label.text != words:
		radio_label.text = words


## How many people other than the avatar are alive: the ones the radio reaches.
func on_the_radio() -> int:
	var sim = _sim()
	if sim == null or sim.get("people") == null:
		return 0
	var pid := String(sim.get("player_id")) if sim.get("player_id") != null else ""
	if pid == "":
		return 0
	var n := 0
	for p in sim.people:
		if String(p.id) != pid and not p.dead and not p.turned:
			n += 1
	return n


## True while the avatar is the only person alive: the radio has nobody on it.
func nobody_on_radio() -> bool:
	var sim = _sim()
	if sim == null or sim.get("people") == null:
		return false
	var pid := String(sim.get("player_id")) if sim.get("player_id") != null else ""
	if pid == "":
		return false
	return on_the_radio() == 0


## Whether the avatar is asleep (the screen is black: no ring or arrow over it).
func _sleeping() -> bool:
	var sl = _module("sleep")
	return sl != null and sl.has_method("active") and bool(sl.active())


func _refresh_ring() -> void:
	ring_t = 0.0
	ring_label = ""
	if _sleeping():
		return
	var uses = _module("uses")
	if uses == null or not uses.has_method("progress"):
		return
	var pr = uses.progress()
	if not (pr is Dictionary) or String(pr.get("label", "")) == "":
		return
	var total := float(pr.get("of", 0.0))
	var t := float(pr.get("t", 0.0))
	ring_t = clampf(t / total if total > 0.0 else t, 0.0, 1.0)
	var left := ceili(maxf(total - t, 0.0)) if total > 1.0 else 0
	ring_label = String(pr.label) if left <= 0 else "%s %ds" % [String(pr.label), left]


## Puts every lesson away, for this game and for the ones after it (a flag in the player's file).
func skip_all_lessons() -> void:
	Prefs.set_flag(LESSONS_OFF_FLAG)
	lesson_card.visible = false


## Puts the current lesson away (the next one is shown when it comes).
func skip_lesson() -> void:
	var id := String(lesson.get("id", ""))
	if id != "":
		skipped[id] = true
	lesson_card.visible = false


## TUTOR (the Esc menu's Lessons): whether the lessons are on (their card and their cues in the world), and the switch. Putting them on again brings back the ones skipped in this game.
func lessons_are_on() -> bool:
	return not Prefs.flag(LESSONS_OFF_FLAG)


func set_lessons(on: bool) -> void:
	Prefs.set_flag(LESSONS_OFF_FLAG, not on)
	if on:
		skipped.clear()
	_last_lesson_sig = ""
	_dirty = true


## Every lesson again from the first (the lessons go on if they were off): the rules begin their list over (`replay_lessons`), the skipped ones come back.
func replay_lessons() -> void:
	set_lessons(true)
	var sc = _scenario()
	if sc != null and sc.has_method("replay_lessons"):
		sc.replay_lessons()
	_dirty = true


## The cards' widths (their words wrap at them, so that the cards are as tall as the words need) and the lesson card's place: the bottom left, clear of the
## selection panel and the verbs of the dock.
func _place_lesson() -> void:
	var w := CARD_W_COMPACT if bool(hud.get("compact")) else CARD_W
	obj_card.custom_minimum_size.x = w
	RadioKit.wrap_at(obj_text, w - 24.0 - (34.0 if _arrow_on else 0.0))
	RadioKit.wrap_at(obj_sub, w - 24.0)
	lesson_card.custom_minimum_size.x = w
	RadioKit.wrap_at(lesson_text, w - 24.0)
	RadioKit.wrap_at(lesson_goal, w - 24.0)
	var lift := 12.0
	var dock = hud.get("dock")
	if dock != null and dock is Control and ((hud.inspect != null and hud.inspect.visible) or (hud.radio_box != null and hud.radio_box.visible)):
		lift = hud.size.y - dock.position.y + 8.0
	var top: float = hud.size.y - lift    # (what the legend stands on: the lesson card's top, or the foot of the window)
	if lesson_card.visible:
		lesson_card.size = lesson_card.get_combined_minimum_size()
		lesson_card.position = Vector2(12.0, hud.size.y - lift - lesson_card.size.y)
		top = lesson_card.position.y - 6.0
	_place_legend(top)


## The legend of the keys stands in the bottom left on the lesson card (or on the foot of the window), for the first LEGEND_S seconds of the run, fading in the
## last second; it gives way (is hidden) while the HUD says the first screen is over (a call, the radio, the help, a selection) and while it would touch any part
## of the HUD (the stores and the objective above it, the crew's cards, the clock and the alerts, the toolbar and the dock).
func _place_legend(top: float) -> void:
	if legend == null:
		return
	var sim = _sim()
	var t := float(sim.t) if sim != null else 0.0
	var wanted: bool = bool(hud.legend_wanted) and not legend.finished and t <= LEGEND_S
	if not wanted:
		legend.visible = false
		return
	legend.controls_changed()
	var obstacles: Array = [hud.left_col, hud.right_col, hud.bar, hud.speed_panel, hud.dock, hud.inspect, hud.radio_box, hud.help, hud.radio_panel]
	legend.place(Vector2(12.0, top), obstacles, clampf((LEGEND_S - t) / LEGEND_FADE_S, 0.0, 1.0))


# -------------------------------------------------------------------------- events --

func on_event(e: Dictionary) -> void:
	if hud == null:
		return
	match String(e.get("type", "")):
		"house_clear":
			_dirty = true
			_house_clear(int(e.get("house", -1)))
		"room_clear":
			_dirty = true
			var name := String(e.get("name", "")).strip_edges()
			# (WORLD: the chip under the objective says it, with the count: scripts/ui/room_flash.gd)
			if not _has_part("room_flash"):
				hud.toast(("The %s is clear" % name) if name != "" else "This room is clear", "info")
		"searched":
			_dirty = true
			var loot := loot_text(e.get("loot", {}))
			# (WORLD: the pops over the container say what was found, and fly to the stores: scripts/ui/search_marks.gd. A crew member's search names them: scripts/town/crew_search.gd)
			var by := String(e.get("name", ""))
			if loot == "" or not _has_part("search_marks"):
				hud.toast(("%s: %s" % [(by + " found") if by != "" else "Found", loot]) if loot != "" else "Nothing here", "info")
		"crew_search":
			# (One House, CREW: a crew member's search ended, or did not begin: in the town's words, in the colour of how it went)
			_dirty = true
			hud.toast(String(e.get("text", "")), String(e.get("level", "info")))
		"claimed", "fourth", "attacks_on", "held", "rescue_joined", "rescue_talk", "entered", "left", "sleep":
			_dirty = true
		"slot_built":
			_dirty = true    # (a section is not news: the project is, below)
		"project_done":
			_dirty = true    # (the alert card in the right column says it: "The front fence is up")
		"slot_lost":
			_dirty = true
			hud.toast("%s has fallen" % _slot_name(String(e.get("slot", ""))), "danger")


## Whether the town's facade has the view part `name` (WORLD: a news that a part says better is not said twice).
func _has_part(part_name: String) -> bool:
	var town = main.get("town") if main != null else null
	var p = town.part(part_name) if town != null and town.has_method("part") else null
	return p != null and (p.get("layer") != null or p.get("pop_layer") != null)    # (a part that has made its drawing: `--noworldfx` leaves it out)


func _house_clear(h: int) -> void:
	if banners_shown.has(h):
		return
	banners_shown.append(h)
	banner_count += 1
	var sub := ""
	var sc = _scenario()
	if sc != null and sc.has_method("objective"):
		var o = sc.objective()
		if o is Dictionary:
			sub = String(o.get("text", ""))
	hud.show_banner("The house is clear", sub if sub != "" else "Claim it from the front door")


## "3 scrap, 2 food" from a loot dictionary ({"scrap": 3, "food": 2}).
static func loot_text(loot) -> String:
	if not (loot is Dictionary):
		return ""
	var parts: Array = []
	for k in ["ammo", "scrap", "food", "water", "meds"]:
		var n := roundi(float(loot.get(k, 0.0)))
		if n > 0:
			parts.append("%d %s" % [n, "medicine" if k == "meds" else k])
	return ", ".join(parts)


func _slot_name(id: String) -> String:
	var per = _module("perimeter")
	if per != null and per.has_method("slots"):
		for s in per.slots():
			if String(s.get("id", "")) == id:
				return String(s.get("name", "The fence"))
	return "The fence"


# ----------------------------------------------------------------------------- keys --

## The keys the town adds (the facade asks first): M the Map page; Shift+N and Shift+G the panel's pages, not the school's modal ones.
func on_key(ev: InputEvent) -> bool:
	if main == null or hud == null or not (ev is InputEventKey):
		return false
	var k := ev as InputEventKey
	if not k.pressed or k.echo or k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return false
	var code: Key = k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	var page := ""
	if code == KEY_M and not k.shift_pressed:
		page = "map"
	elif code == KEY_N and k.shift_pressed:
		page = "build"
	elif code == KEY_G and k.shift_pressed:
		page = "map"
	if page == "" or not main.has_method("page_key"):
		return false
	var sim = _sim()
	if sim == null or not sim.has_method("is_one_house") or not sim.is_one_house():
		return false
	main.page_key(page, false)
	return true


func modal() -> bool:
	return false


# ---------------------------------------------------------------------------- drawing --

## World tile -> HUD pixel (the camera is main's: centre tile and pixels per tile).
func screen_of(tile: Vector2) -> Vector2:
	var vp := layer.size if layer != null else Vector2(1280, 800)
	var cam: Vector2 = main.get("cam_center") if main.get("cam_center") is Vector2 else Vector2.ZERO
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	return (tile - cam) * z + vp * 0.5


func _avatar_body() -> Vector2:
	var me = _player()
	if me == null:
		return Vector2(-100, -100)
	var at := Vector2(me.x, me.y)
	if main.has_method("view_pos"):
		at = main.view_pos(me)
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	return screen_of(at) + Vector2(0, -0.45 * z)


func _draw_layer() -> void:
	if hud == null or main == null:
		return
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	var body := _avatar_body()
	if ring_label != "":
		var r := maxf(RING_MIN_R, 0.55 * z)
		layer.draw_arc(body, r, 0.0, TAU, 48, Color(0.04, 0.08, 0.07, 0.8), 6.0, true)
		layer.draw_arc(body, r, -PI / 2.0, -PI / 2.0 + ring_t * TAU, 48, hud.ACCENT, 4.0, true)
		var font := Fonts.cond(700)
		var w := font.get_string_size(ring_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var rect := Rect2(body + Vector2(-w * 0.5 - 8.0, r + 8.0), Vector2(w + 16.0, 22.0))
		layer.draw_rect(rect, Color(0.04, 0.08, 0.07, 0.82))
		layer.draw_rect(rect, Color(hud.ACCENT, 0.7), false, 1.5)
		layer.draw_string(font, rect.position + Vector2(8.0, 16.0), ring_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hud.INK)
	if _arrow_on:
		var dir := Vector2.from_angle(bearing)
		var ring_r := maxf(ARROW_RING_MIN, 1.7 * z)
		var tip := body + dir * ring_r
		_draw_chevron(layer, tip, bearing, 11.0, hud.ACCENT, Color(0.04, 0.08, 0.07, 0.85))
		var font2 := Fonts.cond(700)
		var label := "%d %s" % [roundi(distance), TILE_WORD]
		var w2 := font2.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var at := tip + dir * 20.0 - Vector2(w2 * 0.5, -5.0)
		layer.draw_string_outline(font2, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
		layer.draw_string(font2, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hud.ACCENT)


func _draw_pill_arrow() -> void:
	if not _arrow_on:
		return
	_draw_chevron(obj_arrow, obj_arrow.size * 0.5, bearing, 9.0, hud.ACCENT, Color(0.04, 0.08, 0.07, 0.6))


## A pointing triangle at `at`, turned to `angle` (0 is east): the tip leads, a notch at the back, with a dark rim so it reads on any ground.
static func _draw_chevron(ci: CanvasItem, at: Vector2, angle: float, size_px: float, color: Color, rim: Color) -> void:
	var f := Vector2.from_angle(angle)
	var s := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([
		at + f * size_px,
		at - f * size_px * 0.7 + s * size_px * 0.78,
		at - f * size_px * 0.3,
		at - f * size_px * 0.7 - s * size_px * 0.78,
	])
	var rim_pts := PackedVector2Array(pts)
	rim_pts.append(pts[0])
	ci.draw_colored_polygon(pts, color)
	ci.draw_polyline(rim_pts, rim, 2.0, true)
