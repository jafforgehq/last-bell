## The shell around the game: the title screen, the pause menu and the screens they
## open (settings, new game, load, credits, a confirmation, the first-launch card).
## main.gd builds one, in a canvas layer above the HUD, and talks to it; the screens
## talk to the game through `main` (start_run, load_run, show_title, quick_save,
## start_tutorial, quit_game, apply_settings, resume), so a test can stand in a fake
## `main` and watch what is asked of it.
##
## The title is the base layer (it is never closed: a game starts by reloading the
## scene); the screens go on a stack above it, and only the top one is shown, hears
## Tab and the arrows, and answers Esc.
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")
const Kit := preload("res://scripts/ui/menu_kit.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Demo := preload("res://scripts/demo.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const TitleMenu := preload("res://scripts/ui/title_menu.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")
const NewGameMenu := preload("res://scripts/ui/new_game_menu.gd")
const LoadMenu := preload("res://scripts/ui/load_menu.gd")
const CreditsScreen := preload("res://scripts/ui/credits.gd")
const ConfirmMenu := preload("res://scripts/ui/confirm_menu.gd")
const OrientationCard := preload("res://scripts/ui/orientation_card.gd")

## How long a toast stays up, in real seconds.
const TOAST_SECONDS := 2.5

var main
var hud
## The title screen while it is the base layer, else null.
var title = null
## The open screens, the top one last.
var stack: Array = []
## Where the saves are: [{"path", "name", "note"}], the autosave and the quick save. (A test
## points them at files of its own.)
var slots: Array = [
	{"path": SaveGame.AUTO_PATH, "name": "Autosave", "note": "Written at each dawn"},
	{"path": SaveGame.QUICK_PATH, "name": "Quick save", "note": "F5 saves, F9 loads"},
]
## The game runs in a browser: there is no Quit and no fullscreen switch. (A test sets it.)
var web := OS.has_feature("web")
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var toast_seconds := TOAST_SECONDS


func setup(main_node, hud_node) -> void:
	main = main_node
	hud = hud_node
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# tooltips and the like come out the way the HUD's do
	if hud.theme != null:
		theme = hud.theme
	_build_toast()


# --------------------------------------------------------------- state --

func is_open() -> bool:
	return not stack.is_empty()


## The screen on top, or null.
func top():
	return stack.back() if not stack.is_empty() else null


## The open screens' kinds, bottom first ("pause", "settings"...), for the tests.
func kinds() -> Array:
	var out: Array = []
	for s in stack:
		out.append(s.kind)
	return out


func on_web() -> bool:
	return web


func reduce_motion() -> bool:
	return Prefs.on("ui", "reduce_motion")


## "Day 7, 14:20" for the game being played (the pause menu's caption), or "".
func run_line() -> String:
	if main == null or main.get("sim") == null:
		return ""
	var sim = main.sim
	return "Day %d, %s" % [int(sim.day), Kit.clock_text(float(sim.hour))]


# ------------------------------------------------------------ building --

## A button of the HUD's kind that the keyboard can reach: the HUD's own buttons never take
## focus, a menu's must. The focus ring is cream on a gold button and gold on the rest.
func button(text: String, primary: bool = false, paper: bool = false) -> Button:
	var b: Button = hud._button(text, primary, paper)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("focus", Kit.focus_box(hud.INK if primary else hud.ACCENT))
	b.pressed.connect(play.bind("ui_click"))
	b.set_meta("primary", primary)
	return b


## A big line of a menu: a title, a second line in smaller type, and a key chip at the right
## edge. The whole line is the button. Its labels are in the metas "title" and "sub" (no "sub"
## when there is no second line).
func menu_item(title_text: String, sub: String = "", primary: bool = false, key: String = "") -> Button:
	var b := button("", primary)
	b.custom_minimum_size = Vector2(0, 54 if sub != "" else 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	var row: HBoxContainer = hud._hbox(10)
	var col: VBoxContainer = hud._vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var ink: Color = hud.ACCENT_INK if primary else hud.INK
	var t: Label = hud._label(title_text, Fonts.cond(700, 1), 20, ink)
	col.add_child(t)
	var s: Label = null
	if sub != "":
		s = hud._label(sub, Fonts.sans(400), 13, Color(ink, 0.86) if primary else hud.INK2)
		col.add_child(s)
	row.add_child(col)
	if not primary:
		# the word lights up (gold) under the mouse and under the keyboard
		var paint := func(lit: bool): t.add_theme_color_override("font_color", hud.ACCENT if lit else ink)
		b.mouse_entered.connect(func(): if not b.disabled: paint.call(true))
		b.mouse_exited.connect(func(): paint.call(b.has_focus()))
		b.focus_entered.connect(func(): paint.call(true))
		b.focus_exited.connect(func(): paint.call(b.is_hovered()))
	if key != "":
		var chip: PanelContainer = hud._kbd(key, primary)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
	margin.add_child(row)
	b.add_child(margin)
	b.set_meta("title", t)
	if s != null:
		b.set_meta("sub", s)
	return b


## Greys a menu line out (or brings it back).
func set_item_enabled(b: Button, on: bool) -> void:
	b.disabled = not on
	b.modulate = Color.WHITE if on else Color(1, 1, 1, 0.5)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW


## Gives a button the look of the main (gold) choice, or of the others: a card that stays
## pressed, or a switch that is on, lights up this way.
func restyle(b: Button, primary: bool) -> void:
	var ref: Button = hud._button("", primary)
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, ref.get_theme_stylebox(state))
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(color_name, ref.get_theme_color(color_name))
	b.add_theme_stylebox_override("focus", Kit.focus_box(hud.INK if primary else hud.ACCENT))
	ref.free()


func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = hud._label("", Fonts.sans(600), 14, hud.INK)
	toast_panel.add_child(toast_label)
	toast_panel.visible = false
	add_child(toast_panel)
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.anchor_top = 1.0
	toast_panel.anchor_bottom = 1.0
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast_panel.offset_bottom = -36


## A line at the bottom of the window, above the screens: up for `toast_seconds`, then gone.
## `level` is "info", "warn" or "danger", like the HUD's.
func toast(text: String, level: String = "info") -> void:
	if toast_panel == null or text.strip_edges() == "":
		return
	var edge: Color = {"danger": hud.DANGER, "warn": hud.WARN}.get(level, hud.INFO)
	var word: Color = {"danger": hud.DANGER_TEXT, "warn": hud.WARN}.get(level, hud.INK)
	var st: StyleBox = hud._style(hud.PANEL, 6, edge, true, "toast")
	toast_panel.add_theme_stylebox_override("panel", st)
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", word)
	if toast_tween != null:
		toast_tween.kill()
	toast_panel.modulate.a = 1.0
	toast_panel.visible = true
	move_child(toast_panel, -1)
	if not is_inside_tree():
		return
	toast_tween = create_tween()
	toast_tween.tween_interval(maxf(0.0, toast_seconds - 0.4))
	if reduce_motion():
		toast_tween.tween_callback(func(): toast_panel.visible = false)
	else:
		toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.4)
		toast_tween.tween_callback(func(): toast_panel.visible = false)


## A menu sound, through the game's sound node (a stand-in without one is fine).
func play(sound_name: String) -> void:
	if main == null:
		return
	var s = main.get("sound")
	if s != null and s.has_method("ui"):
		s.ui(sound_name)


# --------------------------------------------------------------- stack --

## Puts a screen on top of what is open: the one below is covered (hidden, and out of the
## way of Tab), and the new one takes the keyboard.
func _open_screen(screen, screen_title: String, caption: String = "") -> Control:
	if not stack.is_empty():
		var below = stack.back()
		below.remember_focus()
		below.set_active(false)
		below.visible = false
	elif title != null:
		title.remember_focus()
		title.set_active(false)
	if title != null and screen.hides_title:
		title.set_covered(true)
	stack.append(screen)
	add_child(screen)
	screen.setup(self, screen_title, caption)
	screen.closed.connect(_on_screen_closed.bind(screen))
	move_child(toast_panel, -1)
	play("ui_open")
	screen.focus_default.call_deferred()
	return screen


func _on_screen_closed(screen) -> void:
	var was_top: bool = not stack.is_empty() and stack.back() == screen
	stack.erase(screen)
	if screen.get_parent() == self:
		remove_child(screen)
	screen.queue_free()
	if screen.close_sound != "":
		play(screen.close_sound)
	if was_top:
		if not stack.is_empty():
			var below = stack.back()
			below.visible = true
			below.set_active(true)
			below.focus_default.call_deferred()
		elif title != null:
			title.set_covered(false)
			title.set_active(true)
			title.focus_default.call_deferred()
	if screen.kind == "pause" and main != null and main.has_method("resume"):
		main.resume(bool(screen.get("keep_paused")))


## A setting changed: the parts of the shell that show it (the bell on the title stops
## swaying when the settings ask for less motion).
func on_settings_changed() -> void:
	if title != null:
		title.bell.sway = not reduce_motion()


## Closes whatever is open, the top one first.
func close_all() -> void:
	while not stack.is_empty():
		var s = stack.back()
		s.close_sound = ""
		s.close()
		if not stack.is_empty() and stack.back() == s:
			# one that was already closing: do not wait for it
			stack.erase(s)


## The shell hears Esc before anything else: it closes the top screen. And an arrow or Tab
## with nothing focused puts the keyboard on the screen's first control.
func _input(ev: InputEvent) -> void:
	if stack.is_empty() or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var top_screen = stack.back()
	if ev.keycode == KEY_ESCAPE:
		top_screen.on_escape()
		get_viewport().set_input_as_handled()
	elif ev.keycode in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and get_viewport().gui_get_focus_owner() == null:
		top_screen.focus_default()
		get_viewport().set_input_as_handled()


# -------------------------------------------------------------- screens --

func show_title(offer: bool = true) -> void:
	if title != null:
		return
	title = TitleMenu.new()
	add_child(title)
	move_child(title, 0)
	title.setup(self)
	title.focus_default.call_deferred()
	if offer and not Prefs.flag("tutorial_offered"):
		offer_orientation()


func open_pause() -> Control:
	return _open_screen(PauseMenu.new(), "Paused", run_line())


func open_settings() -> Control:
	return _open_screen(SettingsMenu.new(), "Settings", "Changes apply at once")


func open_new_game() -> Control:
	# (round 26: the demo has one game, its three nights: New game begins it, with no choice to make)
	if Demo.on():
		start_game(1, Demo.run_seed(), Demo.crew())
		return null
	return _open_screen(NewGameMenu.new(), "New game", "Choose the nights, the crew, the length and the seed")


## The saves, to load one. `replaces_game` is true from the pause menu, where a load throws
## away the game being played (and the screen says so).
func open_load(replaces_game: bool = false) -> Control:
	var s := LoadMenu.new()
	s.replaces_game = replaces_game
	return _open_screen(s, "Load a game", "")


func open_credits() -> Control:
	return _open_screen(CreditsScreen.new(), "Credits", "")


## "Are you sure?": `on_ok` runs if the answer is yes; the safe answer is the first
## button and has the keyboard.
func confirm(question: String, detail: String, ok_text: String, on_ok: Callable, stay_text: String = "Stay") -> Control:
	var c := ConfirmMenu.new()
	c.detail = detail
	c.ok_text = ok_text
	c.stay_text = stay_text
	c.on_ok = on_ok
	return _open_screen(c, question, "")


## The little card of a first launch: Orientation Day teaches the basics. Shown once (the
## flag `tutorial_offered` is set the moment it is).
func offer_orientation() -> Control:
	Prefs.set_flag("tutorial_offered")
	return _open_screen(OrientationCard.new(), "First time here?", "")


## `--menu=` for the screenshots and the tests: opens one screen by name.
func open_named(screen_name: String) -> Control:
	match screen_name:
		"pause":
			return open_pause()
		"settings":
			return open_settings()
		"new":
			return open_new_game()
		"load":
			return open_load(false)
		"credits":
			return open_credits()
		"confirm":
			return confirm("Leave this game?", "Anything since your last save is lost.", "Main menu", func(): pass)
		"orientation":
			return offer_orientation()
	return null


# ---------------------------------------------------------------- saves --

## What each slot holds: [{"slot": {...}, "info": SaveGame.peek's answer}].
func peeks() -> Array:
	var out: Array = []
	for s in slots:
		out.append({"slot": s, "info": SaveGame.peek(String(s.path))})
	return out


## The save to continue from: {"slot", "info"} for the newest one that can be loaded, else {}.
func newest_save() -> Dictionary:
	var all := peeks()
	if Demo.on():
		all = all.filter(func(p): return bool(p.info.get("demo", false)))    # (round 26: Continue in the demo is the demo's own save, never a full game's)
	var infos: Array = []
	for p in all:
		infos.append(p.info)
	var i := Kit.newest_index(infos)
	return all[i] if i >= 0 else {}


## Continue: loads the newest save, or says there is none.
func continue_game() -> bool:
	var best := newest_save()
	if best.is_empty():
		play("ui_error")
		toast("There is no saved game yet", "warn")
		return false
	return load_slot(String(best.slot.path))


## Loads the save at `path` if it can be; if not it says why (a damaged or foreign save is
## never loaded, and the game that is running goes on).
func load_slot(path: String) -> bool:
	var info := SaveGame.peek(path)
	if not bool(info.get("ok", false)):
		play("ui_error")
		toast("That save cannot be loaded: %s" % String(info.get("reason", "damaged")).to_lower(), "danger")
		return false
	if Demo.on() and not bool(info.get("demo", false)):
		play("ui_error")
		toast("That save is from the full game", "warn")    # (round 26: the demo plays its own three nights only)
		return false
	if main == null or not main.has_method("load_run") or not main.load_run(path):
		play("ui_error")
		toast("That save cannot be loaded", "danger")
		return false
	play("ui_confirm")
	return true


## Why the pause menu's Save is off now ("" when it is on): the game keeps no state while a trip is played in a place.
func save_blocked() -> String:
	if main != null and main.has_method("raid_open") and (main.raid_open() or (main.has_method("trip_report_up") and main.trip_report_up())):
		return "Not while you are out"
	return ""


## The pause menu's Save: the quick save, and a toast to say how it went.
func save_game() -> bool:
	if main == null or not main.has_method("quick_save"):
		return false
	var blocked := save_blocked()
	if blocked != "":
		play("ui_error")
		toast(blocked, "warn")
		return false
	var ok: bool = main.quick_save()
	if ok:
		play("ui_confirm")
		toast("Game saved (F9 loads it)")
	else:
		play("ui_error")
		toast("Could not save", "danger")
	return ok


## A new run: the choice goes to the game, which reloads the scene with it. `crew` is how many people it begins
## with (3 or 6; 0 is no choice, which is six). `campaign` is the long game of four seasons (round 10); Autumn's
## thirty nights are asked for as they always were.
func start_game(difficulty: int, seed_value: int, crew: int = 0, campaign: bool = false) -> void:
	play("ui_confirm")
	if main != null and main.has_method("start_run"):
		if campaign:
			main.start_run(difficulty, seed_value, crew, true)
		else:
			main.start_run(difficulty, seed_value, crew)


## Orientation Day, if the game has it yet.
func start_orientation() -> void:
	if main != null and main.has_method("start_tutorial"):
		play("ui_confirm")
		main.start_tutorial()
	else:
		play("ui_error")
		toast("Orientation Day is coming soon")


func quit_game() -> void:
	if main != null and main.has_method("quit_game"):
		main.quit_game()


## The pause menu's How to play: the HUD's controls panel.
func show_help() -> void:
	var help = hud.get("help")
	if help is Control:
		help.visible = true
