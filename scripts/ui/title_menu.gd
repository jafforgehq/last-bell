## The title screen: the town at dusk behind it (scripts/town/title_scene.gd holds the clock, the lamps, the dead and the camera; the HUD is hidden; with `--school`, the demo or a
## test's stand-in scene it is the old schoolyard), the logo, and a menu on the left:
## Continue (the newest save, with its day), New game, Orientation Day (the school's: gold until it has
## been done), Load, Settings, Credits and Quit (not on the web). The edges are darkened so
## the picture stays readable and the words stay clear, and they darken a little more at each stroke of the dusk bell (`on_toll`).
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")
const Kit := preload("res://scripts/ui/menu_kit.gd")
const Prefs := preload("res://scripts/prefs.gd")
const BellGlyph := preload("res://scripts/ui/bell_glyph.gd")
const Demo := preload("res://scripts/demo.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const PrisonSave := preload("res://scripts/prison/prison_save.gd")    # the prison's save: Continue

const TAGLINE := "Hold the schoolyard for thirty nights."
## The small tag of the demo's title (round 26).
const DEMO_TAG := "DEMO: THE FIRST THREE NIGHTS"
## What the Orientation Day line says under its name: it teaches the game as it is played (the survivor you walk and shoot with,
## and the crew you ask over the radio), not the old yard's orders.
const ORIENTATION_BLURB := "Walk, shoot, radio the crew: eight minutes"
## The column's width, and the windows below which the small logo and the tighter menu are used.
const COLUMN_W := 340.0
const COLUMN_MIN_W := 280.0
const TALL_H := 720.0

var shell
var hud
## The menu lines by name: continue, new, orientation, load, settings, credits, quit.
var items := {}
var board: PanelContainer
var logo: Control
var bell: Control
var name_labels: Array = []
var tagline: Label
## The demo's tag under the tagline (null in the full game).
var demo_tag: Label
var hint: Label
var vignette: TextureRect
## The edges again, darker, that come up at each stroke of the dusk bell and go down over a second or two (the screen's breath), and how far up they are now (0 to 1).
var pulse: TextureRect
var _pulse_k := 0.0
var shade: TextureRect
var scroll: ScrollContainer
var column: VBoxContainer
var _last_focus: Control = null
## The bell tolls once, the first time the title is shown in a run of the program.
static var _tolled := false


func setup(shell_node) -> void:
	shell = shell_node
	hud = shell.hud
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette = _backdrop(Kit.vignette_texture())
	pulse = _backdrop(Kit.vignette_texture(0.95))
	pulse.modulate.a = 0.0
	shade = _backdrop(Kit.shade_texture())
	_build_column()
	hint = hud._label("Arrow keys and Enter, or the mouse", Fonts.sans(400), 12, hud.INK3)
	hint.add_theme_constant_override("outline_size", 4)
	hint.add_theme_color_override("font_outline_color", Color(0.03, 0.025, 0.02, 0.8))
	add_child(hint)
	resized.connect(_layout)
	_layout()
	refresh()
	_layout.call_deferred()
	# (the town's title rings its own bell, every twenty to thirty seconds: scripts/town/title_scene.gd; the school's rings once)
	if not _tolled and (shell.main == null or shell.main.get("title_scene") == null):
		_tolled = true
		get_tree().create_timer(0.8).timeout.connect(_toll)


func _backdrop(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _build_column() -> void:
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)
	column = hud._vbox(16)
	scroll.add_child(column)
	logo = _build_logo()
	column.add_child(logo)
	board = hud._panel()
	var wrap := MarginContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		wrap.add_theme_constant_override("margin_" + side, 6)
	var list: VBoxContainer = hud._vbox(6)
	wrap.add_child(list)
	board.add_child(wrap)
	column.add_child(board)
	var orientation_done := Prefs.flag("tutorial_done")
	_add(list, "continue", shell.menu_item("Continue", "No saved game yet"), _continue)
	_add(list, "new", shell.menu_item("New game"), shell.open_new_game)
	if not OneHouse.town_start(shell.main):    # (the town's lessons are in its first house; Orientation Day is the school's: `--school`)
		_add(list, "orientation", shell.menu_item("Orientation Day", ORIENTATION_BLURB, not orientation_done), shell.start_orientation)
	_add(list, "load", shell.menu_item("Load"), shell.open_load.bind(false))
	_add(list, "settings", shell.menu_item("Settings"), shell.open_settings)
	_add(list, "credits", shell.menu_item("Credits"), shell.open_credits)
	if not shell.on_web():
		_add(list, "quit", shell.menu_item("Quit"), shell.quit_game)


## Continue: the prison's save when there is one (a bad file says why and loads nothing), else the old games' newest.
func _continue() -> void:
	var prison: Dictionary = PrisonSave.peek()
	if prison.is_empty() or shell.main == null or not shell.main.has_method("continue_prison"):
		shell.continue_game()
	elif bool(prison.ok):
		shell.play("ui_confirm")
		shell.main.continue_prison()
	else:
		shell.play("ui_error")
		shell.toast(String(prison.why), "danger")


func _add(list: Control, key: String, b: Button, action: Callable) -> void:
	b.pressed.connect(action)
	list.add_child(b)
	items[key] = b


## The mark: a brass bell, and LAST BELL in big condensed capitals (BELL in gold) with the
## tagline under it. In a short window the words and the bell are smaller (see _layout).
func _build_logo() -> Control:
	var box: VBoxContainer = hud._vbox(6)
	var top: HBoxContainer = hud._hbox(14)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	bell = BellGlyph.new()
	bell.sway = not shell.reduce_motion()
	top.add_child(bell)
	var words: VBoxContainer = hud._vbox(-16)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for pair in [["LAST", hud.INK], ["BELL", hud.ACCENT]]:
		var l: Label = hud._label(String(pair[0]), Fonts.cond(700, 3), 72, pair[1])
		l.add_theme_constant_override("outline_size", 9)
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.032, 0.025, 0.92))
		words.add_child(l)
		name_labels.append(l)
	top.add_child(words)
	box.add_child(top)
	# (One House: the real game starts in the town, and its line says so; a test's stand-in for the game keeps the school's)
	var line := OneHouse.text("words.tagline", TAGLINE) if OneHouse.town_start(shell.main) else TAGLINE
	tagline = hud._label(line, Fonts.sans(500), 16, hud.INK)
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.custom_minimum_size.x = 200
	tagline.add_theme_constant_override("outline_size", 5)
	tagline.add_theme_color_override("font_outline_color", Color(0.03, 0.025, 0.02, 0.85))
	box.add_child(tagline)
	# (round 26: the demo's title says so: a small gold tag under the tagline)
	if Demo.on():
		demo_tag = hud._label(DEMO_TAG, Fonts.cond(700, 3), 15, hud.ACCENT)
		demo_tag.add_theme_constant_override("outline_size", 5)
		demo_tag.add_theme_color_override("font_outline_color", Color(0.03, 0.025, 0.02, 0.85))
		demo_tag.tooltip_text = "The first three nights of the full game: thirty nights, a convoy at the last bell"
		box.add_child(demo_tag)
	return box


## Brings what the menu says up to date: the Continue line (the newest save and its day), and
## the lines that depend on the settings.
func refresh() -> void:
	# The prison game hides Continue and Load until it has a save: its main node answers `prison_save_exists()` (no such method yet = none).
	var prison_title: bool = OneHouse.town_start(shell.main) and not (shell.main.has_method("prison_save_exists") and shell.main.prison_save_exists())
	items["continue"].visible = not prison_title
	items["load"].visible = not prison_title
	var best: Dictionary = shell.newest_save()
	var c: Button = items["continue"]
	var sub: Label = c.get_meta("sub")
	var prison: Dictionary = PrisonSave.peek()    # (the prison's save comes first: it is the game now; a file that cannot be used says why, on the button and when it is pressed)
	if not prison.is_empty():
		sub.text = String(prison.line)
		c.tooltip_text = ""
		shell.set_item_enabled(c, true)
		return
	if best.is_empty():
		# (SAVE4: a save of an older version is never continued; the line says so rather than "no saved game")
		var older: bool = shell.has_method("has_incompatible_save") and shell.has_incompatible_save()
		sub.text = "Older saves cannot be continued" if older else "No saved game yet"
		c.tooltip_text = ""
		shell.set_item_enabled(c, false)
	else:
		sub.text = Kit.save_line(best.info)
		c.tooltip_text = "%s: %s" % [String(best.slot.name), Kit.ago_text(int(best.info.modified), int(Time.get_unix_time_from_system()))]
		shell.set_item_enabled(c, true)


func _process(dt: float) -> void:
	if _pulse_k > 0.0:
		_pulse_k = maxf(0.0, _pulse_k - dt * 0.55)
		pulse.modulate.a = _pulse_k


## A stroke of the dusk bell (the town's title calls it, `strength` 0 to 1, the first of four is 1): the bell on the menu swings at the first, and the edges of the picture close in
## a little at each. Nothing moves under "reduce motion".
func on_toll(strength: float) -> void:
	if shell.reduce_motion():
		return
	if strength >= 0.99:
		bell.toll()
	_pulse_k = maxf(_pulse_k, 0.5 * strength)


## The bell on the title is struck: it swings, and the game's bell sounds once, softly.
func _toll() -> void:
	if not is_inside_tree():
		return
	bell.toll()
	# (not in a run that is only taking a screenshot)
	if shell.main != null and String(shell.main.get("shot_path")) != "":
		return
	var s = shell.main.get("sound") if shell.main != null else null
	if s != null and s.has_method("play"):
		s.play("bell", 0.5, 0.0)


# ---------------------------------------------------------------- layout --

func _layout() -> void:
	if scroll == null or not is_inside_tree():
		return
	var tall := size.y >= TALL_H
	var col_w := clampf(size.x * 0.34, COLUMN_MIN_W, COLUMN_W)
	var left := clampf(size.x * 0.05, 16.0, 72.0)
	# the logo: stacked big words and a big bell in a tall window, one line and a small bell in a short one
	var px := 72 if tall else 40
	for i in name_labels.size():
		var l: Label = name_labels[i]
		l.add_theme_font_size_override("font_size", px)
	bell.custom_minimum_size = Vector2(76, 92) if tall else Vector2(40, 48)
	var words: Control = name_labels[0].get_parent()
	words.add_theme_constant_override("separation", -16 if tall else -9)
	for item_key in items:
		var b: Button = items[item_key]
		var has_sub: bool = b.has_meta("sub")
		b.custom_minimum_size.y = (54 if has_sub else 46) if tall else (48 if has_sub else 40)
	column.add_theme_constant_override("separation", 16 if tall else 10)
	column.custom_minimum_size.x = col_w
	tagline.custom_minimum_size.x = col_w - 4.0
	# the height the column has with the menu showing, whether it shows or has stepped aside for a
	# screen (so the logo does not move when one opens)
	var content_h := logo.get_combined_minimum_size().y + float(column.get_theme_constant("separation")) + board.get_combined_minimum_size().y
	var room := size.y - 44.0
	var top := clampf((room - content_h) * 0.42, 14.0, 96.0)
	scroll.position = Vector2(left, top)
	scroll.size = Vector2(col_w + 8.0, maxf(120.0, room - top))
	hint.position = Vector2(left, size.y - 30.0)


# ----------------------------------------------------------------- focus --

func default_focus() -> Control:
	var c: Button = items["continue"]
	return c if not c.disabled else items["new"]


func focus_default() -> void:
	if not is_inside_tree():
		return
	var c: Control = _last_focus if _last_focus != null and is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree() else default_focus()
	if c != null and c.focus_mode != Control.FOCUS_NONE:
		c.grab_focus()


func remember_focus() -> void:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	_last_focus = f if f != null and is_ancestor_of(f) else null


## A screen is on top of the title (false), or has gone (true).
func set_active(on: bool) -> void:
	Kit.set_focusable(self, on)


## A big screen is over the title: the menu and its hint step out of the way (the logo and the yard stay).
func set_covered(on: bool) -> void:
	board.visible = not on
	hint.visible = not on
