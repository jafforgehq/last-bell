## Tooltips for the parts of the town's HUD and pages that explain nothing yet (One House, HELP). A VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`:
## `on_ready(main)`, `on_frame(dt)`).
##
## THE STYLE. A tooltip is the HUD's own: the noticeboard's panel, the sans font and the cream ink are the HUD's Theme (`hud._tooltip_theme()`: its `TooltipPanel` and `TooltipLabel`),
## which every control under the HUD finds through its parents, and it comes up after 0.4 seconds (the project's `gui/timers/tooltip_delay_sec`). Nothing here makes a grey default
## tooltip: a control only needs `tooltip_text` and a mouse filter that is not Ignore. The words are one line, terse, a little dry, and say "the dead".
##
## WHAT IT DOES. The HUD and the town's parts make most of their tips themselves (the toolbar, the stores, the crew's chips, the radio panel's tabs...). The rest were bare, and an
## audit (`--tooltips-audit`, below) found them: the clock's rows, the objective card, the lesson card, the legend of keys, the controls help, the rescue card, and on the radio panel the
## Jobs rows, the Build page's project cards, the News log and the map's legend. `targets()` lists each with its words; `apply()` gives a control its tip (and lets the mouse reach it) only
## while it has none of its own, every half second (a page is made when first opened, a card when someone joins), so a tip a view writes itself is never overwritten. The few tips that
## follow a state (a project's state chip) are updated while they are this part's own (`META`).
##
## STAGING (a screenshot has no pointer): `--tooltip=<key>` (a key of `targets()`, or a node path under the HUD) puts the pointer on that control after a few frames and takes the shot
## when the tooltip is up; `--tooltips-audit` prints, a moment into the run (give `--frames=60`), every visible word, picture and button of the HUD whose place under the pointer shows
## no tooltip, with the control that would answer.
extends RefCounted

const EVERY_S := 0.5
## Frames after which the staged tooltip's pointer is put on its control, and how many more frames the shot waits for the tooltip to come up (it needs real time).
const HOVER_FRAME := 20
const SHOT_AFTER_FRAMES := 80
## The meta that marks a tip as this part's own.
const META := "help_tip"

# ---- the words (one line each; the HUD's own voice: terse, human, a little dry) ----
const CLOCK_TIP := "The clock. The bell rings at dusk, and the dead come after it"
const DAY_TIP := "The day you are on"
const PHASE_TIP := "The light: dawn, day, dusk or night"
const TIME_TIP := "The time, on a 24-hour clock"
const UNTIL_TIP := "How long until the light changes: dusk by day, dawn by night"
const STRIP_TIP := "The day in colours: night, dawn, day, dusk. The pale mark is now"
const WEATHER_TIP := "The weather outside"
const DEAD_TIP := "The dead awake near you. The rest are asleep where they stand"
const PAUSED_TIP := "Paused. Space, or the play key, goes on"
const STORES_TIP := "Your stores: ammo, food, water and medicine. Point at a number to read it"
const TOOLBAR_TIP := "Time, fields of fire, sound, the radio, the call to arms, help, jobs, build and the menu: point at a key"
const OBJECTIVE_TIP := "What to do next. The arrow round your feet points the way"
const LESSON_TIP := "The guide's lesson. Do what it says and the next one comes"
const LEGEND_TIP := "The keys for the first minute. Esc, then Controls, has every one"
const HELP_TIP := "Every key and mouse button, the same list as Esc, then Controls"
const RESCUE_TIP := "Somebody hiding. 1, 2 and 3 answer them. E or Esc puts the card away"
const JOBS_ROW_TIP := "Day is where they work, Night is where they hold the wall. Click one to ask for another"
const NEWS_TIP := "The radio's log, newest first. A call that waits for an answer is at the top"
const BUILD_CARD_TIP := "A project for the house. Click it to see where it goes in the yard"
const BUILD_STATS_TIP := "What it costs: the scrap is paid when it is ordered, and the builders' hours are the wait"
const BUILD_TIME_TIP := "About how long it takes with the builders you have"
const BUILD_METER_TIP := "How far along it is"
const BUILD_ORDER_TIP := "Order it: the scrap is paid now, and the builders raise it"
## The map's legend: the words of each mark, by its label.
const MAP_LEGEND := {
	"Looked in": "Houses you have been inside",
	"Your base": "The house you claimed",
	"House to claim": "A house you could make your base",
	"Someone waits": "A survivor you know of, and not yet home",
	"You": "Where you are",
}

var main
var hud
var _t := 0.0
var _frames := 0
var _stage := ""
var _stage_done := false
var _audit := false
var _audit_done := false


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--tooltip="):
			_stage = a.trim_prefix("--tooltip=")
		elif a == "--tooltips-audit":
			_audit = true
	_t = EVERY_S


func on_frame(dt: float) -> void:
	if hud == null:
		return
	_frames += 1
	_t += dt
	if _t >= EVERY_S:
		_t = 0.0
		apply()
	if _audit and not _audit_done and _frames >= 40:
		_audit_done = true
		print(audit_text())
	if _stage != "" and not _stage_done and _frames >= HOVER_FRAME:
		_stage_done = true
		_hover(_stage)


# ----------------------------------------------------------------------------- the tips --

## The controls that want a tip, by key: {key: [control, words]} (a control that is not there, or not made yet, is left out).
func targets() -> Dictionary:
	var t := {}
	_put(t, "clock", hud.get("clock"), CLOCK_TIP)
	_put(t, "day", hud.get("day_label"), DAY_TIP)
	_put(t, "phase", hud.get("phase_chip"), PHASE_TIP)
	_put(t, "time", hud.get("time_label"), TIME_TIP)
	_put(t, "until", hud.get("until_label"), UNTIL_TIP)
	_put(t, "strip", hud.get("strip"), STRIP_TIP)
	_put(t, "weather_icon", hud.get("temp_icon"), WEATHER_TIP)
	_put(t, "weather", hud.get("temp_label"), WEATHER_TIP)
	var dead_label = hud.get("walkers_label")
	if dead_label is Control:
		_put(t, "dead", dead_label, DEAD_TIP)
		var row: Node = (dead_label as Control).get_parent()
		var at: int = (dead_label as Control).get_index() - 1
		if row != null and at >= 0:
			_put(t, "dead_icon", row.get_child(at), DEAD_TIP)
	_put(t, "paused", hud.get("paused_pill"), PAUSED_TIP)
	_put(t, "stores", hud.get("res_panel"), STORES_TIP)
	_put(t, "toolbar", hud.get("speed_panel"), TOOLBAR_TIP)
	_put(t, "help", hud.get("help"), HELP_TIP)
	var town_hud = _part("town_hud")
	if town_hud != null:
		_put(t, "objective", town_hud.get("obj_card"), OBJECTIVE_TIP)
		_put(t, "lesson", town_hud.get("lesson_card"), LESSON_TIP)
		_put(t, "legend", town_hud.get("legend"), LEGEND_TIP)
	var rescue = _part("rescue_card")
	if rescue != null:
		_put(t, "rescue", rescue.get("panel"), RESCUE_TIP)
	_pages(t)
	return t


## The radio panel's pages that are made so far: the Jobs rows, the Build page's cards, the News log and the map's legend.
func _pages(t: Dictionary) -> void:
	var rp = hud.get("radio_panel")
	if rp == null or not (rp.get("pages") is Dictionary):
		return
	var pages: Dictionary = rp.pages
	var jobs = pages.get("jobs")
	if jobs != null and jobs.get("rows") is Dictionary:
		for id in jobs.rows:
			var r = jobs.rows[id]
			if r is Dictionary:
				_put(t, "jobs_row/%s" % id, r.get("row"), JOBS_ROW_TIP)
	var news = pages.get("news")
	if news != null:
		_put(t, "news", news, NEWS_TIP)
	var build = pages.get("build")
	if build != null:
		var cards: Array = []
		if build.get("next_card") is Dictionary:
			cards.append(build.next_card)
		if build.get("cards") is Dictionary:
			for id in build.cards:
				cards.append(build.cards[id])
		var n := 0
		for c in cards:
			if not (c is Dictionary):
				continue
			n += 1
			_put(t, "build_card/%d" % n, c.get("panel"), BUILD_CARD_TIP)
			_put(t, "build_chip/%d" % n, c.get("chip"), _chip_tip(c.get("chip")))
			_put(t, "build_stats/%d" % n, c.get("stats"), BUILD_STATS_TIP)
			_put(t, "build_time/%d" % n, c.get("time"), BUILD_TIME_TIP)
			_put(t, "build_meter/%d" % n, c.get("meter"), BUILD_METER_TIP)
			_put(t, "build_order/%d" % n, c.get("action"), BUILD_ORDER_TIP)
	var map = pages.get("map")
	if map != null:
		for k in map.get_children():
			if k is HFlowContainer:
				for one in k.get_children():
					for part in one.get_children():
						if part is Label and MAP_LEGEND.has((part as Label).text):
							_put(t, "map_legend/%s" % (part as Label).text, one, String(MAP_LEGEND[(part as Label).text]))


## What a project's state chip says, from its word ("READY", "LOCKED", "BUILDING 1 OF 3", "DONE", "2 FALLEN", "1 OF 3 UP").
static func chip_tip_for(word: String) -> String:
	var w := word.to_upper()
	if w.begins_with("LOCKED"):
		return "Not yet. The line under it says what opens it"
	if w.begins_with("BUILDING"):
		return "Going up: the builders are at it"
	if w.begins_with("DONE"):
		return "Finished"
	if w.contains("FALLEN"):
		return "Fallen in a night. Order it again"
	if w.contains(" UP"):
		return "Some of it is up. The rest is waiting on scrap or on you"
	return "Ready to order. Scrap and builders are the only wait"


func _chip_tip(chip) -> String:
	return chip_tip_for((chip as Label).text) if chip is Label else ""


func _part(name: String):
	var town = main.get("town")
	return town.part(name) if town != null else null


func _put(t: Dictionary, key: String, c, words: String) -> void:
	if c is Control and is_instance_valid(c) and words != "":
		t[key] = [c, words]


## Gives every bare control of `targets()` its tip. Returns how many it set.
func apply() -> int:
	var n := 0
	var t := targets()
	for key in t:
		var c: Control = t[key][0]
		var words: String = t[key][1]
		var own: bool = c.has_meta(META) and String(c.get_meta(META)) == c.tooltip_text
		if c.tooltip_text == "" or own:
			if c.tooltip_text != words:
				c.tooltip_text = words
				n += 1
			c.set_meta(META, words)
			if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				c.mouse_filter = Control.MOUSE_FILTER_PASS
	return n


# ------------------------------------------------------------------------------- audit --

## What a visible control would show under the pointer: the tooltip of the first control that takes the mouse at or above it, going up while that one is Pass and says nothing (the
## engine's own rule: a Stop control ends the search). "" when the pointer there would show none.
static func effective_tip(c: Control) -> String:
	var n: Control = c
	while n != null and n.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		n = n.get_parent_control()
	while n != null:
		if n.tooltip_text != "":
			return n.tooltip_text
		if n.mouse_filter == Control.MOUSE_FILTER_STOP:
			return ""
		n = n.get_parent_control()
	return ""


## Every visible word, picture and button of the HUD whose place under the pointer shows no tooltip, with the control that would answer (the audit's list).
func audit_text() -> String:
	var lines: Array = ["--tooltips-audit: visible words, pictures and buttons with no tooltip under the pointer"]
	var seen := {}
	_audit_walk(hud, lines, seen)
	return "\n".join(lines)


func _audit_walk(n: Node, lines: Array, seen: Dictionary) -> void:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		var what := ""
		if c is Label and (c as Label).text.strip_edges() != "":
			what = "\"%s\"" % (c as Label).text.left(28)
		elif c is Button:
			what = "(button) \"%s\"" % (c as Button).text.left(28)
		elif c is TextureRect and (c as TextureRect).texture != null:
			what = "(picture)"
		elif c is PanelContainer or c is Panel:
			what = "(panel)"
		if what != "" and c.get_global_rect().size.x > 2.0 and effective_tip(c) == "":
			var key := str(hud.get_path_to(c))
			if not seen.has(key):
				seen[key] = true
				var owner_ctl: Control = c
				while owner_ctl != null and owner_ctl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
					owner_ctl = owner_ctl.get_parent_control()
				lines.append("  %s %s  at %s  under %s" % [c.get_class(), what, str(Rect2i(c.get_global_rect())), str(hud.get_path_to(owner_ctl)) if owner_ctl != null else "nothing"])
	for k in n.get_children():
		_audit_walk(k, lines, seen)


## The pointer goes onto the control `key` names, so that its tooltip is up in the screenshot; the shot waits for it.
func _hover(key: String) -> void:
	var c = null
	var t := targets()
	if t.has(key):
		c = t[key][0]
	else:
		c = _named(key)
	if not (c is Control):
		print("--tooltip: no control %s (keys: %s)" % [key, ", ".join(t.keys())])
		return
	var ctl := c as Control
	# (the event comes in window pixels: the engine takes the stretch off it again, so the HUD's own point is put through it first)
	var at: Vector2 = main.get_viewport().get_final_transform() * ctl.get_global_rect().get_center()
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)
	if String(main.get("shot_path")) != "":
		main.shot_frames = int(main.frame_count) + SHOT_AFTER_FRAMES


## A control by name: a HUD member ("alarm_button", "holster_button"...), or a node path under the HUD.
func _named(key: String):
	var m = hud.get(key)
	if m is Control:
		return m
	return hud.get_node_or_null(key)
