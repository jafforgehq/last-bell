## The HUD, laid out the way colony games do it: people across the top, stores
## top left, clock and alerts top right, the selection bottom left, time
## controls bottom right. Mirrors the web version's HUD.
extends Control

const GD := preload("res://scripts/game_data.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Dialog := preload("res://scripts/ui/scavenge_dialog.gd")
const GameOver := preload("res://scripts/ui/game_over.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Tactics := preload("res://scripts/sim/tactics.gd")
const Kinds := preload("res://scripts/sim/kinds.gd")

## The text colours all read at 4.5:1 or better on the panel, even over the
## brightest ground (tests/test_hud_text.gd computes it). DANGER is for bars,
## dots and icons; words in red use DANGER_TEXT.
const INK := Color("#ece6d8")
const INK2 := Color("#b7af9e")
const INK3 := Color("#9a937f")
const PANEL := Color(21 / 255.0, 20 / 255.0, 17 / 255.0, 0.94)
const PANEL_HI := Color(36 / 255.0, 34 / 255.0, 30 / 255.0, 0.94)
const LINE := Color(1.0, 238 / 255.0, 205 / 255.0, 0.09)
const LINE2 := Color(1.0, 238 / 255.0, 205 / 255.0, 0.18)
const ACCENT := Color("#f0c24a")
const ACCENT_INK := Color("#1a1508")
const DANGER := Color("#e0584a")
const DANGER_TEXT := Color("#ef6c5d")
const WARN := Color("#e8953a")
const OK := Color("#8fb85a")
const INFO := Color("#7fa6c9")
const DAWN := Color("#e2a3b6")

const PHASE_ICON := {"day": "sun", "dusk": "sun", "night": "moon", "dawn": "sun"}
const PHASE_COLOR := {"day": ACCENT, "dusk": WARN, "night": INFO, "dawn": DAWN}
## The icon of an alert nothing more specific is known about: by its level.
const LEVEL_ICON := {"danger": "warn", "warn": "warn", "info": "bell"}
const LEVEL_COLOR := {"danger": DANGER, "warn": WARN, "info": INFO}
## The icon an alert gets for what it is about, by the start of its id (the first
## match wins; sim.gd and the modules raise `seg-3`, `fever-ana`, `scav-out-2`,
## `low-food`...). An id that matches none of these and names a store gets that
## store's icon (`no-ammo`); anything else gets the level's icon.
const ALERT_ICONS := [
	["seg-", "wall"], ["breach-", "wall"], ["fever-", "fever"], ["scav-", "scavenge"], ["hurt-", "wound"],
	["scratch-", "wound"], ["down-", "down"], ["turned-", "turned"], ["treated-", "treat"], ["nohealer-", "treat"],
	["exile-", "sendout"], ["bell", "bell"], ["horde", "walker"], ["rain", "water"],
	# round 2: a brute and runners are the dead; the alarm, the forecast and the last night ring a bell
	["brute", "walker"], ["runners", "walker"], ["lure", "bell"], ["forecast", "bell"], ["bignight", "bell"],
]
## The order buttons with no icon of their own wear one that is already there: the alarm a
## bell, auto-repair the wall (the hammer is Repair's own, and in the small size, where only the
## icons show, two hammers side by side could not be told apart).
const GIZMO_ICON := {"lure": "bell", "auto": "wall"}
const STORE_ICONS := ["ammo", "scrap", "food", "water", "meds"]
## The panel of one of the dead by its kind: [title, second line]; and what it does on its way in.
const ZOMBIE_NAMES := {"walker": ["Walker", "One of the dead"], "runner": ["Runner", "Fast and frail"], "brute": ["Brute", "Slow, huge, tears walls down"]}
const ZOMBIE_VERBS := {"walker": "Shambling toward the wall", "runner": "Running toward the wall", "brute": "Lumbering toward the wall"}
## Walls and doors, by side and by what they are made of. A piece the HUD has no
## name for (a new kind of wall or door) shows its own words instead of failing.
const SIDE := {"N": "North wall", "W": "West wall", "E": "East wall", "S": "School"}
const MATERIAL := {"container": "shipping container", "bus": "school bus", "car": "wrecked car", "pallets": "pallets and stakes", "gate": "steel gate", "chainlink": "fence and wire", "blocks": "cinderblock", "door": "boarded door"}
const STORES := [["ammo", "Ammo"], ["scrap", "Scrap"], ["food", "Food"], ["water", "Water"], ["meds", "Medicine"]]
## The stores that also show how many days of them are left.
const DAYS_STORES := ["food", "water"]
## Only the skills that do something in version 1 are listed in the person panel.
const SKILLS_SHOWN := ["Shooting", "Building", "Medicine"]
## Game hours without a meal or a drink at which a person is called hungry,
## starving, thirsty and parched (the supplies module penalises at these).
const HUNGRY_H := 18.0
const STARVING_H := 36.0
const THIRSTY_H := 14.0
const PARCHED_H := 24.0
## The selection panel's width and the gizmo buttons' size and gap.
const INSPECT_W := 300
const GIZMO_W := 66
const GIZMO_GAP := 6
## In a window too short for two rows of buttons above the selection panel they
## shrink to a single row of icons (the name and key are in the tooltip).
const GIZMO_MINI := 44
## The clock's width (and the alert feed's under it): wide enough for "DAY 30 OF 30",
## the longest phase and the PAUSED pill in one row, so pausing never moves it.
const CLOCK_W := 248
const CLOCK_W_COMPACT := 164
## Every alert panel stays up at least this many real milliseconds from when it
## first appeared, even if the rules drop the alert sooner: they count an alert's
## life in game seconds, so at 3x speed a five-second alert would last under two.
const ALERT_HOLD_MS := 6000
## The most alerts shown at once (fewer in a narrow window).
const ALERTS_MAX := 5
const ALERTS_MAX_COMPACT := 3
## A toast is up this many real seconds, fading over the last TOAST_FADE of them.
const TOAST_SECONDS := 2.5
const TOAST_FADE := 0.4
const TOAST_COLOR := {"danger": DANGER_TEXT, "warn": WARN, "info": INK}
## The window must be this tall for the fields-of-fire legend to show: in a shorter one the
## stores, the legend and the smallest selection dock would not all fit down the left side.
const LEGEND_MIN_H := 600.0
## The tooltip of the fields-of-fire button.
const FIELDS_TIP := "Fields of fire: which wall pieces your guns reach at night\nKey: V"
## What the speed buttons do and their keys, for the tooltips: [words, key].
const SPEED_TIPS := [["Pause the game", "Space"], ["Play at normal speed", "1"], ["Play twice as fast", "2"], ["Play three times as fast", "3"]]
## The controls panel: [caption, entries to a row, [[keys, what it does], ...]]. `keys` is
## one entry's chips, one chip for each word ("W A S D" is four). Every key and mouse
## button main.gd's _unhandled_input answers to is here.
const HELP := [
	["Orders for the selection", 2, [["R", "Draft or release"], ["P", "To post"], ["F", "Repair"], ["C", "Follow"], ["T", "Treat"], ["X", "Send out"], ["G", "Scavenge"], ["B", "Auto-repair"], ["L", "Lure the dead"]]],
	["Mouse", 2, [["Click", "Select"], ["Right-click", "Move there"], ["Drag", "Pan"], ["Scroll", "Zoom"]]],
	["Keyboard", 2, [["W A S D", "Pan"], ["Arrows", "Pan"], ["Space", "Pause"], ["1 2 3", "Speed"], ["Tab", "Next person"], ["Esc", "Deselect"], ["V", "Fields of fire"], ["F5", "Save"], ["F9", "Load"]]],
]
## The legend of the fields-of-fire view: the tint of a wall section by how many guns
## reach it, [colour, words] (the overlay tints with the same colours).
const FIELDS_LEGEND := [[DANGER, "Red: no gun reaches it"], [WARN, "Amber: one gun"], [OK, "Green: two or more"]]


## A rounded meter: background track and a coloured fill.
class Bar:
	extends Control
	var value := 1.0
	var color := Color("#8fb85a")
	var track := Color(1, 1, 1, 0.08)

	func _draw() -> void:
		var r := size.y * 0.5
		_rr(Rect2(Vector2.ZERO, size), r, track)
		if value > 0.0:
			_rr(Rect2(0, 0, maxf(size.y, size.x * clampf(value, 0.0, 1.0)), size.y), r, color)

	func _rr(rect: Rect2, r: float, c: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(int(r))
		sb.anti_aliasing = true
		draw_style_box(sb, rect)


## The 24-hour strip in the clock: night, dawn, day, dusk, with a marker.
class Strip:
	extends Control
	var hour := 0.0
	var gradient: Gradient

	func _init() -> void:
		gradient = Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.21, 0.245, 0.28, 0.5, 0.76, 0.805, 0.85, 0.9, 1.0])
		gradient.colors = PackedColorArray([Color("#28304c"), Color("#28304c"), Color("#8a6a7c"), Color("#d8c9a4"), Color("#e9dfc3"), Color("#e2b67e"), Color("#b8684a"), Color("#45405e"), Color("#28304c"), Color("#28304c")])

	func _draw() -> void:
		var y := size.y * 0.5 - 3.0
		var n := 64
		for i in n:
			var x0 := size.x * i / n
			var x1 := size.x * (i + 1) / n
			draw_rect(Rect2(x0, y, x1 - x0 + 0.5, 6), gradient.sample((i + 0.5) / n))
		var mx := size.x * hour / 24.0
		draw_rect(Rect2(mx - 2.5, y - 4, 5, 14), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(mx - 1.5, y - 3, 3, 12), Color("#ece6d8"))


var data: Dictionary
var icons := {}
var people: Array = []
var selection = null
var compact := false

var on_select: Callable
var on_focus: Callable
var on_speed: Callable
var on_gizmo: Callable
var on_alert: Callable
var on_sound: Callable
## The fields-of-fire button was pressed (main.gd flips the view and calls set_fields).
var on_fields: Callable
## Starting a new run or loading a save takes a scene reload, which is the
## game's business: by default the choice is put in Engine meta ("run") for
## main.gd and the scene is reloaded; a test sets this to see the choice instead.
var restart: Callable
## Where the game's saves are (the newest one is offered when a run is lost).
var save_paths: Array = [SaveGame.AUTO_PATH, SaveGame.QUICK_PATH]
## The open scavenging dialog and the game-over overlay, or null.
var scavenge_dialog = null
var game_over = null
var _paused_for_dialog := false
var _speed_before_dialog := 0

## The column at the top left: the stores, and under them the fields-of-fire legend
## while that view is on.
var left_col: VBoxContainer
var res_panel: PanelContainer
var res_grid: GridContainer
var res_values := {}
var res_days := {}
var res_labels: Array = []
var bar: HBoxContainer
var cards: Array = []
## The size of the status marks on a card and how many fit (set with the card size).
var mark_px := 0
var mark_max := 4
## The last sim the HUD was updated from (for the things it opens itself).
var sim_ref = null
## The column at the top right: the clock, and under it the alerts.
var right_col: VBoxContainer
var clock: PanelContainer
var day_label: Label
var phase_chip: PanelContainer
var phase_icon: TextureRect
var phase_label: Label
var time_label: Label
var until_label: Label
var strip: Strip
var temp_icon: TextureRect
var temp_label: Label
var walkers_label: Label
## The lookout's forecast of tonight, in the clock from 17:00 until dawn (hidden before).
var forecast_label: Label
var alerts_box: VBoxContainer
## The order the feed shows its alerts in ("id:level|..."): the panels are moved only when it changes.
var alert_sig := ""
## What the feed knows, by alert id: {"id", "level", "text", "sub", "born", "seq", "live" (the
## rules still hold it), "seen" and "first_ms" (whether its panel has appeared, and when it
## first did, in Time.get_ticks_msec() terms), "panel" (null while it is not shown), and the
## parts of the panel: "icon", "title", "subl", "col"}.
var alert_items := {}
## How long a panel stays after the rules drop its alert (a test shortens it).
var alert_hold_ms := ALERT_HOLD_MS
var alert_seq := 0
## The "PAUSED" pill in the clock, shown while the game is paused.
var paused_pill: PanelContainer
var paused_label: Label
var banner: VBoxContainer
var banner_title: Label
var banner_sub: Label
var banner_tween: Tween
var dock: BoxContainer
var inspect: PanelContainer
var inspect_refs := {}
var gizmos: GridContainer
## How many buttons are in the dock now (children being freed still count in the tree).
var gizmo_count := 0
## Whether the buttons are the small icon-only kind (see GIZMO_MINI).
var gizmo_mini := false
var speed_panel: PanelContainer
var speed_buttons: Array = []
var sound_button: Button
## The fields-of-fire view's button (lit while the view is on) and its legend.
var fields_button: Button
var fields_on := false
var fields_legend: PanelContainer
var help_button: Button
var help: PanelContainer
var hint: PanelContainer
## The one-line message near the bottom centre (see toast()).
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var toast_seconds := TOAST_SECONDS
var last_speed := -1


func setup(game_data: Dictionary, crew: Array) -> void:
	data = game_data
	people = crew
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _tooltip_theme()
	for key in data.icons:
		icons[key] = GD.tex(data.icons[key])
	_build_stores()
	_build_bar()
	_build_clock()
	_build_alerts()
	_build_banner()
	_build_dock()
	_build_speed()
	_build_help()
	_build_hint()
	_build_toast()
	resized.connect(_on_resized)
	_on_resized()


# ---------------------------------------------------------------- helpers --

## The look of a tooltip: the HUD's dark panel, ink and font. Only the two
## tooltip types are set (the controls under the HUD find them through their
## parents; the rest of the look is still set control by control).
func _tooltip_theme() -> Theme:
	var t := Theme.new()
	var sb := _style(Color(PANEL_HI, 0.98), 6, LINE2, false)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	t.set_stylebox("panel", "TooltipPanel", sb)
	t.set_font("font", "TooltipLabel", Fonts.sans(400))
	t.set_font_size("font_size", "TooltipLabel", 13)
	t.set_color("font_color", "TooltipLabel", INK)
	return t


func _style(bg: Color = PANEL, radius: int = 6, border: Color = LINE, shadow: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.38)
		s.shadow_size = 12
		s.shadow_offset = Vector2(0, 5)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _panel(style: StyleBox = null) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style if style != null else _style())
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


## A label. Nothing is set under Fonts.MIN_PX: a smaller size is raised to it.
func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", maxi(size, Fonts.MIN_PX))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _caps(text: String) -> Label:
	return _label(text.to_upper(), Fonts.cond(600, 1), 12, INK3)


func _icon(name: String, size: int, color: Color = Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icons.get(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _hbox(sep: int) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _vbox(sep: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A key chip: the key's name (a letter, "Tab", "Right-click") in a small
## rounded box, 12 px. `on_gold` is for a chip on a gold button.
func _kbd(text: String, on_gold: bool = false) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(ACCENT_INK, 0.12) if on_gold else Color(1, 1, 1, 0.08)
	s.border_color = Color(ACCENT_INK, 0.35) if on_gold else LINE2
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 0
	s.content_margin_bottom = 1
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := _label(text, Fonts.cond(600), 12, ACCENT_INK if on_gold else INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _corner(c: Control, right: bool, bottom: bool, x: float, y: float) -> void:
	c.anchor_left = 1.0 if right else 0.0
	c.anchor_right = c.anchor_left
	c.anchor_top = 1.0 if bottom else 0.0
	c.anchor_bottom = c.anchor_top
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	if right:
		c.offset_right = -x
	else:
		c.offset_left = x
	if bottom:
		c.offset_bottom = -y
	else:
		c.offset_top = y


func _center_top(c: Control, y: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.offset_top = y


# ----------------------------------------------------------------- stores --

func _build_stores() -> void:
	res_panel = _panel(_style())
	var grid := GridContainer.new()
	res_grid = grid
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in STORES:
		var ic := _icon(s[0], 14, INK3)
		var k := _label(s[1], Fonts.sans(400), 13, INK2)
		var v := _label("0", Fonts.cond(600), 15, INK)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size.x = 34
		res_values[s[0]] = v
		if s[0] in DAYS_STORES:
			# the days left sit under the number; the icon and name stay level with it
			var d := _label("", Fonts.cond(600), 12, INK3)
			d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			res_days[s[0]] = d
			var cell := _vbox(0)
			cell.add_child(v)
			cell.add_child(d)
			var line_h := v.get_minimum_size().y
			grid.add_child(_padded(ic, int((line_h - 14.0) * 0.5)))
			var kp := _padded(k, int((line_h - k.get_minimum_size().y) * 0.5))
			res_labels.append(kp)
			grid.add_child(kp)
			grid.add_child(cell)
		else:
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(ic)
			res_labels.append(k)
			grid.add_child(k)
			grid.add_child(v)
	res_panel.add_child(grid)
	res_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left_col = _vbox(8)
	left_col.add_child(res_panel)
	left_col.add_child(_build_legend())
	add_child(left_col)
	_corner(left_col, false, false, 12, 12)


## The legend of the fields-of-fire view: a swatch for each tint and what it means.
## Hidden until the view is on (see set_fields).
func _build_legend() -> PanelContainer:
	fields_legend = _panel(_style())
	fields_legend.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# a legend is read, not pressed: clicks pass through it to the world
	fields_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := _vbox(5)
	col.add_child(_caps("Fields of fire"))
	for entry in FIELDS_LEGEND:
		var row := _hbox(8)
		var swatch := Panel.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(entry[0], 0.55)
		st.border_color = entry[0]
		st.set_border_width_all(1)
		st.set_corner_radius_all(3)
		swatch.add_theme_stylebox_override("panel", st)
		swatch.custom_minimum_size = Vector2(16, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		row.add_child(_label(String(entry[1]), Fonts.sans(400), 12, INK2))
		col.add_child(row)
	fields_legend.add_child(col)
	fields_legend.visible = false
	return fields_legend


## `c` with `top` pixels of space above it, so it can sit level with a taller neighbour.
func _padded(c: Control, top: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_top", maxi(0, top))
	m.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	m.add_child(c)
	return m


# ---------------------------------------------------------- colonist bar --

func _card_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#1c1a17")
	s.border_color = ACCENT if selected else LINE
	s.set_border_width_all(2 if selected else 1)
	s.set_corner_radius_all(5)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 4)
	s.anti_aliasing = true
	return s


func _build_bar() -> void:
	bar = _hbox(6)
	add_child(bar)
	for p in people:
		var card := Panel.new()
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.tooltip_text = "%s, %s" % [p.name, String(p.def.role).to_lower()]
		card.add_theme_stylebox_override("panel", _card_style(false))
		card.clip_contents = true
		var pic := TextureRect.new()
		pic.texture = GD.tex(data.portraits[p.id])
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(pic)
		# a dark veil and a word over the picture of someone who is gone or away
		var veil := ColorRect.new()
		veil.color = Color(0.06, 0.05, 0.05, 0.62)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		veil.visible = false
		card.add_child(veil)
		var word := _label("", Fonts.cond(700, 1), 12, INK2)
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# it sits on a picture: a dark edge keeps it readable over any face
		word.add_theme_color_override("font_outline_color", Color(0.03, 0.025, 0.02, 0.9))
		word.add_theme_constant_override("outline_size", 3)
		card.add_child(word)
		var nm := _label(p.first, Fonts.cond(600), 13, INK)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(nm)
		var hp_bg := ColorRect.new()
		hp_bg.color = Color(0, 0, 0, 0.55)
		hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hp_bg)
		var hp := ColorRect.new()
		hp.color = OK
		hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hp)
		var badge := Panel.new()
		var bs := StyleBoxFlat.new()
		bs.bg_color = ACCENT
		bs.set_corner_radius_all(9)
		bs.anti_aliasing = true
		badge.add_theme_stylebox_override("panel", bs)
		badge.size = Vector2(17, 17)
		badge.position = Vector2(3, 3)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bi := _icon("draft", 11, ACCENT_INK)
		bi.position = Vector2(3, 3)
		bi.size = Vector2(11, 11)
		badge.add_child(bi)
		badge.visible = false
		card.add_child(badge)
		var fight := Panel.new()
		var fs := StyleBoxFlat.new()
		fs.bg_color = DANGER
		fs.set_corner_radius_all(4)
		fs.anti_aliasing = true
		fight.add_theme_stylebox_override("panel", fs)
		fight.size = Vector2(7, 7)
		fight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fight.visible = false
		card.add_child(fight)
		# the status marks (hungry, bleeding, feverish...) along the foot of the picture
		var marks_box := PanelContainer.new()
		var ms := StyleBoxFlat.new()
		ms.bg_color = Color(0.06, 0.05, 0.05, 0.72)
		ms.set_corner_radius_all(7)
		ms.content_margin_left = 2
		ms.content_margin_right = 2
		ms.content_margin_top = 2
		ms.content_margin_bottom = 2
		ms.anti_aliasing = true
		marks_box.add_theme_stylebox_override("panel", ms)
		marks_box.mouse_filter = Control.MOUSE_FILTER_PASS
		marks_box.visible = false
		var marks := _hbox(0)
		marks_box.add_child(marks)
		card.add_child(marks_box)
		card.gui_input.connect(_on_card_input.bind(p))
		bar.add_child(card)
		cards.append({"card": card, "p": p, "pic": pic, "name": nm, "hp_bg": hp_bg, "hp": hp, "badge": badge, "fight": fight, "sel": false, "veil": veil, "word": word, "marks_box": marks_box, "marks": marks, "marks_sig": "", "marks_data": [], "state": ""})
	_size_cards(60)


func _size_cards(w: int) -> void:
	var h := w + 20
	var was := mark_px
	mark_px = 12 if w >= 56 else 11
	mark_max = 4 if w >= 56 else 3
	for c in cards:
		c.card.custom_minimum_size = Vector2(w, h)
		c.pic.position = Vector2(1, 1)
		c.pic.size = Vector2(w - 2, w - 2)
		c.veil.position = c.pic.position
		c.veil.size = c.pic.size
		c.word.position = c.pic.position
		c.word.size = c.pic.size
		c.name.position = Vector2(0, w - 1)
		c.name.size = Vector2(w, 18)
		c.name.add_theme_font_size_override("font_size", 13 if w >= 56 else 12)
		c.hp_bg.position = Vector2(1, h - 4)
		c.hp_bg.size = Vector2(w - 2, 3)
		c.hp.position = c.hp_bg.position
		c.fight.position = Vector2(w - 12, 5)
		c.marks_box.position = Vector2(3, w - 2 - mark_px - 4)
		if was != mark_px:
			_fill_marks(c, c.marks_data)


func _on_card_input(ev: InputEvent, p) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.double_click:
			on_focus.call(p)
		else:
			on_select.call({"kind": "person", "ref": p})
		accept_event()


# ------------------------------------------------------------------ clock --

func _chip_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(c, 0.17)
	s.set_corner_radius_all(3)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 2
	s.content_margin_bottom = 3
	return s


## The "PAUSED" stamp in the clock's top row, beside the phase chip: a pale pill
## with a pause mark and the word, shown while the game is paused (update_hud).
func _build_paused_pill() -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = INK
	s.set_corner_radius_all(9)
	s.anti_aliasing = true
	s.content_margin_left = 6
	s.content_margin_right = 7
	s.content_margin_top = 1
	s.content_margin_bottom = 2
	paused_pill = PanelContainer.new()
	paused_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paused_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paused_pill.add_theme_stylebox_override("panel", s)
	var row := _hbox(3)
	var ic := _icon("pause", 11, ACCENT_INK)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	paused_label = _label("PAUSED", Fonts.cond(700, 1), 12, ACCENT_INK)
	row.add_child(paused_label)
	paused_pill.add_child(row)
	paused_pill.visible = false
	return paused_pill


func _build_clock() -> void:
	clock = _panel(_style())
	var v := _vbox(6)
	var r1 := _hbox(8)
	day_label = _caps("Day 3")
	r1.add_child(day_label)
	r1.add_child(_spacer())
	r1.add_child(_build_paused_pill())
	phase_chip = PanelContainer.new()
	phase_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := _hbox(5)
	phase_icon = _icon("sun", 12)
	phase_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(phase_icon)
	phase_label = _label("DAY", Fonts.cond(700, 1), 12, ACCENT)
	chip.add_child(phase_label)
	phase_chip.add_child(chip)
	r1.add_child(phase_chip)
	v.add_child(r1)
	var r2 := _hbox(8)
	time_label = _label("18:46", Fonts.cond(600), 30, INK)
	r2.add_child(time_label)
	r2.add_child(_spacer())
	until_label = _label("", Fonts.sans(400), 12, INK2)
	until_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	until_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r2.add_child(until_label)
	v.add_child(r2)
	strip = Strip.new()
	strip.custom_minimum_size = Vector2(0, 16)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(strip)
	var r4 := _hbox(5)
	temp_icon = _icon("sun", 13, INK3)
	temp_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r4.add_child(temp_icon)
	temp_label = _label("", Fonts.sans(400), 12, INK2)
	r4.add_child(temp_label)
	r4.add_child(_spacer())
	var wi := _icon("walker", 13, INK3)
	wi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r4.add_child(wi)
	walkers_label = _label("", Fonts.sans(400), 12, INK2)
	r4.add_child(walkers_label)
	v.add_child(r4)
	# the lookout's forecast, once it is given (see update_hud); a long one wraps
	forecast_label = _label("", Fonts.sans(400), 12, INK2)
	forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forecast_label.visible = false
	v.add_child(forecast_label)
	clock.add_child(v)
	clock.custom_minimum_size.x = CLOCK_W
	# the alerts hang from the clock, so a taller clock pushes them down
	right_col = _vbox(13)
	right_col.add_child(clock)
	add_child(right_col)
	_corner(right_col, true, false, 12, 12)


# ----------------------------------------------------------------- alerts --

func _build_alerts() -> void:
	alerts_box = _vbox(6)
	alerts_box.custom_minimum_size.x = CLOCK_W
	right_col.add_child(alerts_box)


## The icon an alert gets: for what it is about (ALERT_ICONS, then a store named in
## its id), else its level's.
func _alert_icon_name(it: Dictionary) -> String:
	var id := String(it.id)
	for pair in ALERT_ICONS:
		if id.begins_with(pair[0]) and icons.has(pair[1]):
			return pair[1]
	for part in id.split("-"):
		if part in STORE_ICONS and icons.has(part):
			return part
	return String(LEVEL_ICON.get(it.level, "warn"))


## Whether alert `a` goes above alert `b` in the feed: the more urgent first, then
## the newer (by the rules' clock, then by when the HUD first saw it).
func _alert_before(a: Dictionary, b: Dictionary) -> bool:
	var ra := _rank(a)
	var rb := _rank(b)
	if ra != rb:
		return ra > rb
	if a.born != b.born:
		return a.born > b.born
	return a.seq > b.seq


## Makes the panel for an alert and puts it at the end of the feed (see
## _sync_alerts): the level's colour down the left edge, the icon of what it is
## about, a headline and a second line. Both lines wrap, so a long one makes the
## panel taller, not wider. Click it to look at the place.
func _make_alert_panel(it: Dictionary) -> void:
	var s := _style(PANEL, 6, LINE, true)
	s.border_width_left = 3
	s.content_margin_left = 9
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.content_margin_right = 10
	var p := _panel(s)
	var row := _hbox(9)
	var ic := _icon("warn", 16, WARN)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ic)
	var col := _vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label("", Fonts.sans(600), 13, INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var subl := _label("", Fonts.sans(400), 12, INK2)
	subl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(subl)
	row.add_child(col)
	p.add_child(row)
	p.set_meta("id", String(it.id))
	p.gui_input.connect(_on_alert_input.bind(String(it.id)))
	p.mouse_entered.connect(func(): s.bg_color = PANEL_HI)
	p.mouse_exited.connect(func(): s.bg_color = PANEL)
	# a coloured bar down the left edge
	p.draw.connect(func(): p.draw_rect(Rect2(0, 3, 3, p.size.y - 6), it.col))
	it.panel = p
	it.icon = ic
	it.title = title
	it.subl = subl
	it.shown_level = ""
	it.col = WARN
	alerts_box.add_child(p)
	_update_alert_panel(it)


## Brings a shown panel in line with its alert: new words go into the labels it
## already has, and a new level re-colours the edge and the icon. Nothing is rebuilt
## (a wall's "86% intact" changes with every claw).
func _update_alert_panel(it: Dictionary) -> void:
	var title: Label = it.title
	if title.text != it.text:
		title.text = it.text
	var subl: Label = it.subl
	if subl.text != it.sub:
		subl.text = it.sub
	subl.visible = it.sub != ""
	if it.shown_level != it.level:
		it.shown_level = it.level
		it.col = LEVEL_COLOR.get(it.level, WARN)
		var ic: TextureRect = it.icon
		ic.texture = icons.get(_alert_icon_name(it))
		ic.modulate = it.col
		var p: Control = it.panel
		p.set_meta("level", String(it.level))
		p.queue_redraw()


## Takes the panel of an alert out of the feed and frees it; the alert's record stays.
func _free_alert_panel(it: Dictionary) -> void:
	var p = it.panel
	it.panel = null
	if p != null and is_instance_valid(p):
		if p.get_parent() != null:
			p.get_parent().remove_child(p)
		p.queue_free()


func _drop_alert(id: String) -> void:
	if alert_items.has(id):
		_free_alert_panel(alert_items[id])
		alert_items.erase(id)


## The feed follows the rules' alerts without being rebuilt: a panel is made when
## an alert first makes the top of the list and kept (its words and colour updated
## in place) until the alert leaves it; the panels are moved only when the order
## changes. An alert the rules drop (they count its life in game seconds, so at 3x
## speed it can go in under two real ones) stays for alert_hold_ms real time after
## its panel first appeared. At most ALERTS_MAX are shown (fewer in a narrow window).
func _sync_alerts(sim) -> void:
	var now := Time.get_ticks_msec()
	for id in sim.alerts:
		var a: Dictionary = sim.alerts[id]
		var it: Dictionary = alert_items.get(id, {})
		if it.is_empty():
			alert_seq += 1
			it = {"id": String(id), "seq": alert_seq, "seen": false, "first_ms": 0, "panel": null}
			alert_items[id] = it
		it.live = true
		it.level = String(a.level)
		it.text = String(a.text)
		it.sub = String(a.sub)
		it.born = float(a.born)
	for id in alert_items.keys():
		if sim.alerts.has(id):
			continue
		var gone: Dictionary = alert_items[id]
		gone.live = false
		# a panel that was up stays until it has had its time; an alert never shown goes at once
		if not gone.seen or now - int(gone.first_ms) >= alert_hold_ms:
			_drop_alert(id)
	var list: Array = alert_items.values()
	list.sort_custom(_alert_before)
	list = list.slice(0, ALERTS_MAX_COMPACT if compact else ALERTS_MAX)
	var shown := {}
	for it in list:
		shown[it.id] = true
	for id in alert_items:
		if not shown.has(id) and alert_items[id].panel != null:
			_free_alert_panel(alert_items[id])
	var sig := ""
	for it in list:
		if it.panel == null:
			if not it.seen:
				it.seen = true
				it.first_ms = now
			_make_alert_panel(it)
		else:
			_update_alert_panel(it)
		sig += "%s:%s|" % [it.id, it.level]
	if sig != alert_sig:
		alert_sig = sig
		for i in list.size():
			alerts_box.move_child(list[i].panel, i)


func _on_alert_input(ev: InputEvent, id: String) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		on_alert.call(id)
		accept_event()


# ----------------------------------------------------------------- banner --

func _build_banner() -> void:
	banner = _vbox(2)
	banner_title = _label("", Fonts.cond(700, 5), 34, INK)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	banner_title.add_theme_constant_override("shadow_offset_y", 2)
	banner_title.add_theme_constant_override("shadow_outline_size", 10)
	banner.add_child(banner_title)
	banner_sub = _label("", Fonts.sans(400), 14, INK2)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	banner_sub.add_theme_constant_override("shadow_outline_size", 8)
	banner.add_child(banner_sub)
	banner.modulate.a = 0.0
	add_child(banner)
	_center_top(banner, 118)


func show_banner(text: String, sub: String) -> void:
	banner_title.text = text.to_upper()
	banner_sub.text = sub
	if banner_tween != null:
		banner_tween.kill()
	banner_tween = create_tween()
	banner_tween.tween_property(banner, "modulate:a", 1.0, 0.7)
	banner_tween.tween_interval(3.0)
	banner_tween.tween_property(banner, "modulate:a", 0.0, 0.7)


# ------------------------------------------------------------ dock / inspect --

func _build_dock() -> void:
	# a row (the buttons beside the selection panel) or a column (the buttons
	# above it) depending on the room: see _layout_dock
	dock = BoxContainer.new()
	dock.add_theme_constant_override("separation", 8)
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dock)
	_corner(dock, false, true, 12, 12)
	inspect = _panel(_style())
	inspect.custom_minimum_size.x = INSPECT_W
	inspect.size_flags_vertical = Control.SIZE_SHRINK_END
	inspect.visible = false
	dock.add_child(inspect)
	gizmos = GridContainer.new()
	gizmos.add_theme_constant_override("h_separation", GIZMO_GAP)
	gizmos.add_theme_constant_override("v_separation", GIZMO_GAP)
	gizmos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gizmos.size_flags_vertical = Control.SIZE_SHRINK_END
	dock.add_child(gizmos)


## The buttons go to the right of the selection panel when that leaves room
## clear of the speed controls and the help panel; else in rows above the panel,
## and if that would run into the stores panel, as one row of small buttons.
func _layout_dock() -> void:
	if dock == null or speed_panel == null or help == null or left_col == null:
		return
	# the legend takes room down the left side (it gives way in a short window)
	fields_legend.visible = fields_on and size.y >= LEGEND_MIN_H
	var n := gizmo_count
	var panel_w := maxf(float(INSPECT_W), inspect.get_combined_minimum_size().x)
	var beside := float(n * GIZMO_W + maxi(0, n - 1) * GIZMO_GAP)
	var reserve := maxf(speed_panel.get_combined_minimum_size().x, help.get_combined_minimum_size().x) + 8.0
	var fits := n == 0 or panel_w + 8.0 + beside <= size.x - 24.0 - reserve
	dock.vertical = not fits
	var mini := false
	if not fits:
		var per_row := maxi(1, int((panel_w + GIZMO_GAP) / (GIZMO_W + GIZMO_GAP)))
		var rows := ceili(float(n) / float(per_row))
		var tall := float(rows * GIZMO_W + (rows - 1) * GIZMO_GAP) + 8.0 + inspect.get_combined_minimum_size().y
		# measured with a little to spare: a font can make a panel a few pixels taller than its minimum;
		# the column at the top left is the stores and, while the fields-of-fire view is on, its legend
		var room := size.y - 12.0 - (12.0 + left_col.get_combined_minimum_size().y + 24.0)
		mini = tall > room
	if mini != gizmo_mini:
		gizmo_mini = mini
		_build_gizmos()
		return
	if fits:
		dock.move_child(inspect, 0)
		gizmos.columns = maxi(1, n)
		gizmos.size_flags_vertical = Control.SIZE_SHRINK_END
	else:
		dock.move_child(gizmos, 0)
		# big buttons stack as wide as the panel; small ones take the room there is
		var across := (size.x - 24.0 - reserve) if gizmo_mini else panel_w
		var side := GIZMO_MINI if gizmo_mini else GIZMO_W
		gizmos.columns = maxi(1, int((across + GIZMO_GAP) / (side + GIZMO_GAP)))
		gizmos.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _meter() -> Array:
	var row := _hbox(8)
	var b := Bar.new()
	b.custom_minimum_size = Vector2(60, 6)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(b)
	var v := _label("100%", Fonts.cond(600), 13, INK)
	v.custom_minimum_size.x = 36
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return [row, b, v]


func select(sel) -> void:
	selection = sel
	for c in inspect.get_children():
		inspect.remove_child(c)
		c.queue_free()
	_clear_gizmos()
	inspect_refs = {}
	if sel == null:
		inspect.visible = false
		_layout_dock()
		_layout_toast()
		return
	inspect.visible = true
	if hint != null:
		hint.visible = false
	_layout_toast()
	var v := _vbox(10)
	var head := _hbox(11)
	var titles := _vbox(1)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sel.kind == "person":
		var p = sel.ref
		head.add_child(_pic(GD.tex(data.portraits[p.id])))
		titles.add_child(_label(p.name, Fonts.cond(700), 21, INK))
		titles.add_child(_label("%s · %d" % [p.def.role, int(p.def.age)], Fonts.sans(400), 13, INK2))
		var m := _meter()
		_row(grid, "Health", m[0])
		inspect_refs.hp = m[1]
		inspect_refs.hpv = m[2]
		var wrow := _hbox(6)
		wrow.add_child(_label(p.gun.name, Fonts.sans(400), 13, INK))
		var pips := _hbox(2)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not p.gun.get("melee", false):
			for i in mini(int(p.gun.mag), 20):
				var pip := ColorRect.new()
				pip.custom_minimum_size = Vector2(3, 10)
				pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pips.add_child(pip)
		wrow.add_child(pips)
		inspect_refs.pips = pips
		_row(grid, "Weapon", wrow)
		var doing := _label("", Fonts.sans(400), 13, INK)
		doing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		doing.custom_minimum_size.x = 200
		_row(grid, "Doing", doing)
		inspect_refs.doing = doing
		var needs := _label("Fed", Fonts.sans(400), 13, INK)
		_row(grid, "Needs", needs)
		inspect_refs.needs = needs
		var wounds := _label("None", Fonts.sans(400), 13, INK2)
		_row(grid, "Wounds", wounds)
		inspect_refs.wounds = wounds
		# only a fever shows: the row is there but hidden until the medical module names a stage
		var infection := _label("", Fonts.sans(400), 13, WARN)
		var infection_head := _row(grid, "Infection", infection)
		infection.visible = false
		infection_head.visible = false
		inspect_refs.infection = infection
		inspect_refs.infection_head = infection_head
		# the standing order auto-repair shows as a gold tag at the right of the header while it is on
		inspect_refs.auto_tag = _auto_tag()
	elif sel.kind == "zombie":
		var z = sel.ref
		head.add_child(_pic(GD.tex(data.portraits["z%d" % z.look_index])))
		var names: Array = ZOMBIE_NAMES.get(String(z.kind), ZOMBIE_NAMES.walker)
		titles.add_child(_label(String(names[0]), Fonts.cond(700), 21, INK))
		titles.add_child(_label(String(names[1]), Fonts.sans(400), 13, INK2))
		var m := _meter()
		_row(grid, "Health", m[0])
		inspect_refs.hp = m[1]
		inspect_refs.hpv = m[2]
		var doing := _label("", Fonts.sans(400), 13, INK)
		_row(grid, "Doing", doing)
		inspect_refs.doing = doing
	else:
		var s = sel.ref
		var box := Panel.new()
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color("#2a2723")
		bs.set_corner_radius_all(4)
		box.add_theme_stylebox_override("panel", bs)
		box.custom_minimum_size = Vector2(46, 46)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wi := _icon("wall", 20, INK2)
		wi.position = Vector2(13, 13)
		wi.size = Vector2(20, 20)
		box.add_child(wi)
		head.add_child(box)
		titles.add_child(_label(s.name, Fonts.cond(700), 21, INK))
		titles.add_child(_label("%s · %s" % [SIDE.get(s.side, "Wall"), MATERIAL.get(s.kind, String(s.kind))], Fonts.sans(400), 13, INK2))
		var m := _meter()
		_row(grid, "Integrity", m[0])
		inspect_refs.hp = m[1]
		inspect_refs.hpv = m[2]
		var doing := _label("", Fonts.sans(400), 13, INK)
		_row(grid, "Status", doing)
		inspect_refs.doing = doing
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(titles)
	if inspect_refs.has("auto_tag"):
		head.add_child(_spacer())
		head.add_child(inspect_refs.auto_tag)
	v.add_child(head)
	v.add_child(grid)
	if sel.kind == "person":
		var line := ColorRect.new()
		line.color = LINE
		line.custom_minimum_size = Vector2(0, 1)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(line)
		var sk := GridContainer.new()
		sk.columns = 2
		sk.add_theme_constant_override("h_separation", 14)
		sk.add_theme_constant_override("v_separation", 5)
		sk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for skill_name in SKILLS_SHOWN:
			var val := int(sel.ref.def.skills.get(skill_name, 0))
			var row := _hbox(6)
			var n := _label(skill_name, Fonts.sans(400), 12, INK2)
			n.custom_minimum_size.x = 58
			row.add_child(n)
			var b := Bar.new()
			b.custom_minimum_size = Vector2(44, 4)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.value = val / 10.0
			b.color = Color("#b3a57f")
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(b)
			var num := _label(str(val), Fonts.cond(600), 12, INK)
			num.custom_minimum_size.x = 14
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(num)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sk.add_child(row)
		v.add_child(sk)
	inspect.add_child(v)
	_build_gizmos()
	_refresh_selection()


## The tag "Auto-repair: on" in the person panel's header: a small gold pill, shown while
## the standing order is on (see _refresh_selection).
func _auto_tag() -> PanelContainer:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(ACCENT, 0.14)
	st.border_color = Color(ACCENT, 0.55)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 1
	st.content_margin_bottom = 2
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", st)
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.tooltip_text = "Auto-repair is on: by day they mend worn walls on their own (key B turns it off)"
	tag.add_child(_label("Auto-repair: on", Fonts.cond(700, 1), 12, ACCENT))
	tag.visible = false
	return tag


func _pic(t: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.custom_minimum_size = Vector2(46, 46)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _row(grid: GridContainer, label: String, value: Control) -> Label:
	var l := _caps(label)
	l.custom_minimum_size.x = 58
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value)
	return l


func _gizmo(id: String, text: String, key: String, on: bool) -> Button:
	var b := Button.new()
	var side := GIZMO_MINI if gizmo_mini else GIZMO_W
	b.custom_minimum_size = Vector2(side, side)
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("id", id)
	b.set_meta("label", text)
	b.set_meta("key", key)
	b.set_meta("on", on)
	var normal := _style(ACCENT if on else PANEL, 6, ACCENT if on else LINE)
	normal.set_content_margin_all(0)
	var hover := _style(ACCENT if on else PANEL_HI, 6, ACCENT if on else LINE2)
	hover.set_content_margin_all(0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var col := ACCENT_INK if on else INK
	var inner := _vbox(7)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := _icon(String(GIZMO_ICON.get(id, id)), 20 if gizmo_mini else 22, col)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(ic)
	if not gizmo_mini:
		var l := _label(text.to_upper(), Fonts.cond(600, 1), 12, col)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(l)
	b.add_child(inner)
	if not gizmo_mini:
		# the key in a small chip at the top right of the button
		var chip := _kbd(key, on)
		b.add_child(chip)
		_corner(chip, true, false, 4, 4)
	_update_gizmo_tip(b)
	b.pressed.connect(func(): on_gizmo.call(id))
	return b


## What an order does, in plain words: the first line of its tooltip. `label` is the
## button's name (Draft or Release); the kind of selection picks the words for
## Repair and Follow.
func _order_words(id: String, label: String) -> String:
	var kind: String = String(selection.kind) if selection != null else ""
	match id:
		"draft":
			if label == "Release":
				return "Release: back to their usual routine"
			return "Draft: take control, they hold their place"
		"post":
			return "To post: go to their post on the wall and hold it"
		"repair":
			if kind == "segment":
				return "Repair: a builder fixes this wall piece (costs scrap)"
			return "Repair: fix the most damaged wall piece (costs scrap)"
		"focus":
			if kind == "segment":
				return "Focus: centre the view on this wall piece"
			if kind == "zombie":
				return "Focus: keep the view on this walker"
			return "Follow: keep the view on this person"
		"treat":
			return "Treat: bandage or cure them (uses medicine)"
		"sendout":
			return "Send out: they leave through the gate for good"
		"scavenge":
			return "Scavenge: send a party out for supplies"
		"lure":
			return "Alarm: draws the dead to this wall for %d hours\nCosts %d scrap. One at a time." % [int(Tactics.LURE_HOURS), int(Tactics.LURE_COST)]
		"auto":
			return "Auto-repair: by day, mends the most worn wall under %d%%\nwhile scrap is %d or more." % [roundi(Tactics.AUTO_BELOW * 100.0), int(Tactics.AUTO_MIN_SCRAP)]
	return label


## Why the order would do nothing right now, in a few words ("nothing is damaged"),
## or "" when it is fine or the HUD cannot tell. Only what the HUD can see: the
## person's state, the walls and the stores. (The buttons for treating, sending out
## and scavenging only show when the modules offer them.)
func _order_blocker(id: String) -> String:
	if sim_ref == null or selection == null:
		return ""
	if selection.kind == "person":
		var p = selection.ref
		if p.dead or p.away != null:
			return ""
		match id:
			"post":
				if p.downed:
					return "%s is down" % p.first
			"repair":
				if p.downed:
					return "%s is down" % p.first
				if not _any_wall_damaged():
					return "nothing is damaged"
				if float(sim_ref.stock.scrap) <= 0.0:
					return "no scrap left"
			"treat":
				var need := _meds_needed(p)
				var have := float(sim_ref.stock.meds)
				if have < need:
					return "not enough medicine (needs %d, have %d)" % [int(need), int(have)]
	elif selection.kind == "segment" and id == "repair":
		var seg = selection.ref
		if seg.hp >= seg.max_hp:
			return "this wall piece is not damaged"
		if not _someone_free_to_work():
			return "nobody is free to repair it"
		if float(sim_ref.stock.scrap) <= 0.0:
			return "no scrap left"
	elif selection.kind == "segment" and id == "lure":
		# the rules say why (a door, a section that is down, an alarm already ringing, too little scrap)
		return String(sim_ref.tactics.why_not_lure(selection.ref))
	return ""


## Why the order `id` would do nothing right now ("" when it is fine or the HUD
## cannot tell): what the tooltips say, for the game to say when a key is pressed.
func why_not(id: String) -> String:
	return _order_blocker(id)


func _any_wall_damaged() -> bool:
	for s in sim_ref.segments:
		if s.hp < s.max_hp:
			return true
	return false


func _someone_free_to_work() -> bool:
	for p in people:
		if not p.downed and not p.dead and p.away == null:
			return true
	return false


## The medicine treating `p` takes: a bandage first if they need one, else the cure.
func _meds_needed(p) -> float:
	var bandage: bool = (p.downed and not p.stabilised) or p.bleeding > 0.0
	return float(sim_ref.medical.BANDAGE_MEDS if bandage else sim_ref.medical.CURE_MEDS)


## "what it does\nKey: R" and, when the HUD knows the order would do nothing now, a
## third line "Not now: why."
func _gizmo_tip(id: String, label: String, key: String, why: String) -> String:
	var tip := "%s\nKey: %s" % [_order_words(id, label), key]
	if why != "":
		tip += "\nNot now: %s." % why
	return tip


## Sets a button's tooltip, and ghosts it (still pressable: the order is the game's to
## refuse) while the HUD knows it would do nothing.
func _update_gizmo_tip(b: Button) -> void:
	var id: String = b.get_meta("id")
	var why := _order_blocker(id)
	var tip := _gizmo_tip(id, String(b.get_meta("label")), String(b.get_meta("key")), why)
	if b.tooltip_text != tip:
		b.tooltip_text = tip
	b.modulate.a = 0.55 if why != "" else 1.0


## The buttons follow the game: what is damaged, the stores, who is down.
func _refresh_gizmo_tips() -> void:
	for b in gizmos.get_children():
		if b is Button and b.has_meta("id"):
			_update_gizmo_tip(b)


func _clear_gizmos() -> void:
	for c in gizmos.get_children():
		gizmos.remove_child(c)
		c.queue_free()
	gizmo_count = 0


## The buttons for the selection: the usual ones, and for a person Treat, Send
## out and Scavenge when the modules offer them.
func _build_gizmos() -> void:
	_clear_gizmos()
	if selection == null:
		_layout_dock()
		return
	if selection.kind == "person":
		var p = selection.ref
		if p.away != null:
			pass # off the map: nothing to order
		elif p.dead:
			gizmos.add_child(_gizmo("focus", "Follow", "C", false))
		else:
			gizmos.add_child(_gizmo("draft", "Release" if p.drafted else "Draft", "R", p.drafted))
			gizmos.add_child(_gizmo("post", "To post", "P", false))
			gizmos.add_child(_gizmo("repair", "Repair", "F", false))
			gizmos.add_child(_gizmo("focus", "Follow", "C", false))
			# a standing order, lit while it is on
			gizmos.add_child(_gizmo("auto", "Auto", "B", _auto_on(p)))
			if sim_ref != null and sim_ref.medical.can_treat(p):
				gizmos.add_child(_gizmo("treat", "Treat", "T", false))
			if sim_ref != null and sim_ref.medical.can_send_out(p):
				gizmos.add_child(_gizmo("sendout", "Send out", "X", false))
			if _can_scavenge(p):
				gizmos.add_child(_gizmo("scavenge", "Scavenge", "G", false))
	elif selection.kind == "segment":
		gizmos.add_child(_gizmo("repair", "Repair", "F", false))
		gizmos.add_child(_gizmo("focus", "Focus", "C", false))
		gizmos.add_child(_gizmo("lure", "Lure", "L", false))
	else:
		gizmos.add_child(_gizmo("focus", "Focus", "C", false))
	gizmo_count = gizmos.get_child_count()
	inspect_refs.gizmo_sig = _gizmo_sig()
	_layout_dock()


## What decides which buttons the selection gets: when it changes they are rebuilt.
func _gizmo_sig() -> String:
	if selection == null or selection.kind != "person":
		return "" if selection == null else String(selection.kind)
	var p = selection.ref
	var sig := "%s|%s|%s" % [p.drafted, p.dead, p.away != null]
	if sim_ref != null and not p.dead and p.away == null:
		sig += "|%s|%s|%s|%s" % [sim_ref.medical.can_treat(p), sim_ref.medical.can_send_out(p), _can_scavenge(p), _auto_on(p)]
	return sig


## Whether `p` has the standing order auto-repair on.
func _auto_on(p) -> bool:
	return sim_ref != null and sim_ref.tactics.auto_repair(p)


## Whether `p` could be sent scavenging now: on the map, on their feet, not held
## by an order and not too ill to travel. (The scavenging module has the last say.)
func is_free_to_go(p) -> bool:
	if sim_ref != null and sim_ref.scavenge.has_method("can_go"):
		return sim_ref.scavenge.can_go(p)
	if p.dead or p.downed or p.away != null:
		return false
	if p.drafted and p.order != null:
		return false
	return sim_ref == null or sim_ref.medical.infection_stage(p) != "delirious"


## Whether the Scavenge button is offered for `p`.
func _can_scavenge(p) -> bool:
	return sim_ref != null and sim_ref.scavenge.can_send() and is_free_to_go(p)


# ------------------------------------------------------------ time controls --

func _speed_button(icon_name: String, tip: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(34, 30)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0, 0, 0, 0)
	n.set_corner_radius_all(4)
	var h := StyleBoxFlat.new()
	h.bg_color = Color(1, 1, 1, 0.07)
	h.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ic := _icon(icon_name, 16, INK2)
	ic.position = Vector2(9, 7)
	ic.size = Vector2(16, 16)
	b.add_child(ic)
	b.set_meta("icon", ic)
	return b


func _build_speed() -> void:
	var s := _style()
	s.set_content_margin_all(4)
	var panel := _panel(s)
	speed_panel = panel
	var row := _hbox(2)
	var names := ["pause", "play", "ff", "fff"]
	for i in 4:
		var b := _speed_button(names[i], "%s\nKey: %s" % SPEED_TIPS[i])
		b.pressed.connect(func(): on_speed.call(i))
		row.add_child(b)
		speed_buttons.append(b)
	var sep := ColorRect.new()
	sep.color = LINE2
	sep.custom_minimum_size = Vector2(1, 20)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_spacer_fixed(3))
	row.add_child(sep)
	row.add_child(_spacer_fixed(3))
	fields_button = _speed_button("draft", FIELDS_TIP)
	fields_button.pressed.connect(func(): if on_fields.is_valid(): on_fields.call())
	row.add_child(fields_button)
	sound_button = _speed_button("soundOn", "Turn the sound off")
	sound_button.pressed.connect(func(): on_sound.call())
	row.add_child(sound_button)
	help_button = _speed_button("help", "Show or hide the controls: every key and mouse button")
	help_button.pressed.connect(func(): help.visible = not help.visible)
	row.add_child(help_button)
	panel.add_child(row)
	add_child(panel)
	_corner(panel, true, true, 12, 12)


## The fields-of-fire view lit or dark: its button by the speed controls and its legend.
## (main.gd flips the view; the overlay draws it.)
func set_fields(on: bool) -> void:
	fields_on = on
	if fields_button != null:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(ACCENT, 0.16) if on else Color(0, 0, 0, 0)
		st.set_corner_radius_all(4)
		fields_button.add_theme_stylebox_override("normal", st)
		fields_button.get_meta("icon").modulate = ACCENT if on else INK2
	_layout_dock()


func _spacer_fixed(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## The controls, in groups, two entries to a row: every key and mouse button the
## game answers to. In a group of single keys the chips of a column are all as wide
## as its widest, like a row of keycaps.
func _build_help() -> void:
	help = _panel(_style())
	var col := _vbox(10)
	for group in HELP:
		var g := _vbox(4)
		g.add_child(_caps(String(group[0])))
		var per_row: int = group[1]
		var uniform := true
		for entry in group[2]:
			if String(entry[0]).contains(" "):
				uniform = false
		var grid := GridContainer.new()
		grid.columns = per_row * 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 4)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := 0
		for entry in group[2]:
			var keys := _hbox(2)
			keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			for word in String(entry[0]).split(" "):
				var chip := _kbd(word)
				if uniform:
					chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				keys.add_child(chip)
			var cell: Control = keys
			if n % per_row > 0:
				# the second entry in a row: a little room before its key
				var pad := MarginContainer.new()
				pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pad.add_theme_constant_override("margin_left", 12)
				pad.add_child(keys)
				cell = pad
			grid.add_child(cell)
			var what := _label(String(entry[1]), Fonts.sans(400), 12, INK2)
			what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(what)
			n += 1
		g.add_child(grid)
		col.add_child(g)
	help.add_child(col)
	help.visible = false
	add_child(help)
	_corner(help, true, true, 12, 58)


func _build_hint() -> void:
	hint = _panel(_style())
	var row := _hbox(5)
	row.add_child(_label("Click someone in the yard", Fonts.sans(400), 13, INK2))
	for part in [["Right-click", "to move them"], ["Drag", "to pan"], ["Scroll", "to zoom"], ["Space", "to pause"]]:
		row.add_child(_kbd(part[0]))
		row.add_child(_label(part[1], Fonts.sans(400), 13, INK2))
	hint.add_child(row)
	add_child(hint)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -96


# ------------------------------------------------------------------ toast --

func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = _label("", Fonts.sans(600), 14, INK)
	toast_panel.add_child(toast_label)
	toast_panel.visible = false
	add_child(toast_panel)
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.anchor_top = 1.0
	toast_panel.anchor_bottom = 1.0
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_layout_toast()


## A short message near the bottom centre for something that did not happen
## ("Nothing is damaged"): one line, up for toast_seconds of real time with a fade
## at the end, replaced by the next one. `level` is "info" (the default), "warn"
## or "danger".
func toast(text: String, level: String = "info") -> void:
	if toast_panel == null or text.strip_edges() == "":
		return
	var st := _style(PANEL, 6, LEVEL_COLOR.get(level, INFO), true)
	st.border_width_left = 3
	st.content_margin_left = 12
	st.content_margin_right = 14
	st.content_margin_top = 7
	st.content_margin_bottom = 8
	toast_panel.add_theme_stylebox_override("panel", st)
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", TOAST_COLOR.get(level, INK))
	if toast_tween != null:
		toast_tween.kill()
	toast_panel.modulate.a = 1.0
	toast_panel.visible = true
	_layout_toast()
	toast_tween = create_tween()
	toast_tween.tween_interval(maxf(0.0, toast_seconds - TOAST_FADE))
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, minf(TOAST_FADE, toast_seconds))
	toast_tween.tween_callback(func(): toast_panel.visible = false)


## The toast sits at the bottom centre above the order buttons, above the hint while
## that shows, and is moved clear of the selection panel in a window too narrow to
## have both side by side.
func _layout_toast() -> void:
	if toast_panel == null:
		return
	var lift := 96.0
	if hint != null and hint.visible:
		lift += hint.get_combined_minimum_size().y + 8.0
	toast_panel.offset_bottom = -lift
	var shift := 0.0
	if inspect != null and inspect.visible:
		var half := toast_panel.get_combined_minimum_size().x * 0.5
		shift = maxf(0.0, 12.0 + INSPECT_W + 8.0 + half - size.x * 0.5)
		shift = minf(shift, maxf(0.0, size.x * 0.5 - 12.0 - half))
	toast_panel.offset_left = shift
	toast_panel.offset_right = shift


# ----------------------------------------------- dialog and game over --

## Opens the "Send a scavenging party" dialog for the selection (a person, or
## nothing: then the first free survivor leads). The game is paused meanwhile.
func open_scavenge(sel) -> void:
	if scavenge_dialog != null or game_over != null or sim_ref == null:
		return
	var who = sel.ref if sel != null and sel.kind == "person" else null
	var d := Dialog.new()
	scavenge_dialog = d
	add_child(d)
	d.closed.connect(_on_dialog_closed)
	d.setup(self, sim_ref, who)
	_speed_before_dialog = last_speed
	_paused_for_dialog = last_speed > 0
	if _paused_for_dialog and on_speed.is_valid():
		on_speed.call(0)


func _on_dialog_closed() -> void:
	scavenge_dialog = null
	if _paused_for_dialog and on_speed.is_valid():
		on_speed.call(_speed_before_dialog)
	_paused_for_dialog = false


func _show_game_over(sim) -> void:
	if scavenge_dialog != null:
		scavenge_dialog.close()
	hint.visible = false
	game_over = GameOver.new()
	add_child(game_over)
	game_over.setup(self, sim)


## Begins a new run or loads a save: `meta` is what main.gd reads from Engine
## meta "run" ({"difficulty", "seed"} or {"load": path}) when the scene reloads.
func start_run(meta: Dictionary) -> void:
	if restart.is_valid():
		restart.call(meta)
		return
	Engine.set_meta("run", meta)
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		tree.reload_current_scene()


## The newest save that exists, or "".
func last_save() -> String:
	var best := ""
	var best_time := -1
	for path in save_paths:
		if FileAccess.file_exists(path):
			var t := FileAccess.get_modified_time(path)
			if t > best_time:
				best_time = t
				best = path
	return best


## A button in the game's style for the dialog and the game-over screen: the main
## choice in gold, the others dark.
func _button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(112, 40)
	b.add_theme_font_override("font", Fonts.cond(700, 1))
	b.add_theme_font_size_override("font_size", 15)
	var ink := ACCENT_INK if primary else INK
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, ink)
	# a disabled button's word still reads (gold on the dimmed gold, cream on the dark): it is the main choice
	b.add_theme_color_override("font_disabled_color", Color(ACCENT, 0.9) if primary else Color(ink, 0.6))
	var looks := {
		"normal": ACCENT if primary else PANEL,
		"hover": ACCENT.lightened(0.14) if primary else PANEL_HI,
		"pressed": ACCENT.darkened(0.08) if primary else PANEL_HI,
		"disabled": Color(ACCENT, 0.28) if primary else PANEL,
	}
	for state in looks:
		var st := _style(looks[state], 6, ACCENT if primary else (LINE2 if state == "hover" else LINE), false)
		st.set_content_margin_all(0)
		st.content_margin_left = 16
		st.content_margin_right = 16
		b.add_theme_stylebox_override(state, st)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


# ------------------------------------------------------------------ layout --

func _on_resized() -> void:
	var w := size.x
	var was := compact
	compact = w < 980.0
	var bottom_bar := w < 640.0
	if compact != was or cards.size() > 0:
		_size_cards(48 if compact else 60)
		for l in res_labels:
			l.visible = not compact
		res_grid.columns = 2 if compact else 3
		clock.custom_minimum_size.x = CLOCK_W_COMPACT if compact else CLOCK_W
		alerts_box.custom_minimum_size.x = CLOCK_W_COMPACT if compact else CLOCK_W
		time_label.add_theme_font_size_override("font_size", 24 if compact else 30)
		hint.visible = hint.visible and not compact
	if bottom_bar:
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
		bar.offset_top = 0
		bar.offset_bottom = -56
		alerts_box.visible = false
	else:
		bar.anchor_top = 0.0
		bar.anchor_bottom = 0.0
		bar.grow_vertical = Control.GROW_DIRECTION_END
		bar.offset_top = 10
		bar.offset_bottom = 10
		alerts_box.visible = true
	_center_h(bar)
	_layout_dock()
	_layout_toast()


func _center_h(c: Control) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.offset_left = 0
	c.offset_right = 0


# ------------------------------------------------------------------ update --

func _hp_color(f: float) -> Color:
	return DANGER if f < 0.34 else (WARN if f < 0.67 else OK)


## "6 d": whole days left, rounded down, and "<1 d" under a day.
func _days_text(days: float) -> String:
	if not is_finite(days) or days >= 99.0:
		return "99+ d"
	if days < 1.0:
		return "<1 d"
	return "%d d" % int(days)


## The word over the card of someone who is gone or away, or "".
func _card_word(p) -> String:
	if p.turned:
		return "Turned"
	if p.dead:
		return "Left" if p.away is Dictionary and String(p.away.get("kind", "")) == "exile" else "Died"
	if p.away != null:
		return "Away"
	return ""


func _update_card(c: Dictionary, sim) -> void:
	var p = c.p
	var sel: bool = selection != null and selection.ref == p
	if sel != c.sel:
		c.sel = sel
		c.card.add_theme_stylebox_override("panel", _card_style(sel))
	var word := _card_word(p)
	var state := "%s|%s" % [word, p.downed]
	if state != c.state:
		c.state = state
		c.veil.visible = word != ""
		c.veil.color.a = 0.66 if p.dead else 0.48
		c.word.text = word
		c.word.add_theme_color_override("font_color", DANGER_TEXT if word == "Turned" else (INFO if word == "Away" else INK2))
		c.name.add_theme_color_override("font_color", INK3 if p.dead else INK)
		var dim := 0.4 if p.dead else (0.7 if p.away != null else (0.45 if p.downed else 1.0))
		c.pic.modulate = Color(dim, dim, dim)
	var f: float = clampf(p.hp / 100.0, 0.0, 1.0)
	c.hp.size = Vector2(c.hp_bg.size.x * f, 3)
	c.hp.color = _hp_color(f)
	var present: bool = not p.dead and p.away == null
	c.badge.visible = p.drafted and present
	c.fight.visible = p.target != null and not p.downed and present
	if c.fight.visible:
		c.fight.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
	var marks: Array = [] if p.dead else sim.status_of(p)
	var sig := ""
	for m in marks:
		sig += "%s|%s|%s;" % [m.get("icon", ""), Color(m.get("color", INK2)).to_html(), m.get("tip", "")]
	if sig != c.marks_sig:
		c.marks_sig = sig
		c.marks_data = marks
		_fill_marks(c, marks)


## The little row of status icons on a card: what the modules say is wrong with
## the person (hungry, bleeding, feverish...), each with its tip as a tooltip.
func _fill_marks(c: Dictionary, marks: Array) -> void:
	var row: HBoxContainer = c.marks
	for ch in row.get_children():
		row.remove_child(ch)
		ch.queue_free()
	var shown := mini(marks.size(), mark_max)
	for i in shown:
		var m: Dictionary = marks[i]
		var t := TextureRect.new()
		t.texture = icons.get(String(m.get("icon", "")), icons.get("help"))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(mark_px, mark_px)
		t.modulate = Color(m.get("color", INK2))
		t.tooltip_text = String(m.get("tip", ""))
		t.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(t)
	c.marks_box.visible = shown > 0


func update_hud(sim, speed: int, sound_on: bool, walkers: int) -> void:
	sim_ref = sim
	if sim.over != "" and game_over == null:
		_show_game_over(sim)
	for s in STORES:
		var v := roundi(float(sim.stock[s[0]]))
		var lbl: Label = res_values[s[0]]
		lbl.text = str(v)
		var low: bool = (s[0] == "ammo" and v < 60) or (s[0] == "meds" and v < 3)
		lbl.add_theme_color_override("font_color", WARN if low else INK)
	for kind in res_days:
		var days: float = sim.supplies.days_left(kind)
		var dl: Label = res_days[kind]
		dl.text = _days_text(days)
		dl.add_theme_color_override("font_color", DANGER_TEXT if days < 1.0 else (WARN if days < 3.0 else INK3))
	for c in cards:
		_update_card(c, sim)
	# clock
	var m := int(sim.minutes)
	var h: float = sim.hour
	day_label.text = ("DAY %d/%d" if compact else "DAY %d OF %d") % [sim.scenario.day(), sim.scenario.total_days()]
	var pc: Color = PHASE_COLOR.get(sim.phase, ACCENT)
	phase_chip.add_theme_stylebox_override("panel", _chip_style(pc))
	phase_icon.texture = icons[PHASE_ICON.get(sim.phase, "sun")]
	phase_icon.modulate = pc
	paused_pill.visible = speed == 0
	# in a narrow window the clock has no room for the day as well as the pill: the pill takes its place
	day_label.visible = not (speed == 0 and compact)
	phase_label.text = String(sim.phase).to_upper()
	phase_label.add_theme_color_override("font_color", pc)
	time_label.text = "%02d:%02d" % [m / 60, m % 60]
	var to_dawn := fposmod(6.5 - h, 24.0)
	var to_dusk := fposmod(19.0 - h, 24.0)
	var next_name := "Dusk" if sim.phase == "day" else "Dawn"
	var next_h := to_dusk if sim.phase == "day" else to_dawn
	until_label.text = "%s in %dh %02dm" % [next_name, int(next_h), int(fmod(next_h, 1.0) * 60.0)]
	strip.hour = h
	strip.queue_redraw()
	var temp := roundi(9.0 + 8.0 * maxf(0.0, sin((h - 8.0) / 24.0 * TAU)))
	temp_icon.texture = icons[PHASE_ICON.get(sim.phase, "sun")]
	temp_label.text = "%d°C, %s" % [temp, sim.weather]
	walkers_label.text = "%d walkers" % walkers
	_update_forecast(sim)
	# speed and sound
	if speed != last_speed:
		last_speed = speed
		for i in speed_buttons.size():
			var b: Button = speed_buttons[i]
			var on := i == speed
			var st := StyleBoxFlat.new()
			st.bg_color = Color(ACCENT, 0.16) if on else Color(0, 0, 0, 0)
			st.set_corner_radius_all(4)
			b.add_theme_stylebox_override("normal", st)
			b.get_meta("icon").modulate = ACCENT if on else INK2
	sound_button.get_meta("icon").texture = icons["soundOn" if sound_on else "soundOff"]
	var sound_tip := "Turn the sound off" if sound_on else "Turn the sound on"
	if sound_button.tooltip_text != sound_tip:
		sound_button.tooltip_text = sound_tip
	_sync_alerts(sim)
	_refresh_selection()


## The lookout's forecast under the clock: from the hour he tells it (17:00) until dawn,
## and only while he can tell it; at other times the line is not there.
func _update_forecast(sim) -> void:
	var f: Dictionary = sim.tactics.forecast()
	var text := ""
	if bool(f.get("given", false)) and sim.phase != "dawn":
		text = _forecast_text(f)
	if forecast_label.text != text:
		forecast_label.text = text
	forecast_label.visible = text != ""


## "Tonight: about 55 from the north east, a brute"; "..., runners"; on the last night
## "The last night: about 120, from everywhere".
func _forecast_text(f: Dictionary) -> String:
	if bool(f.get("big", false)):
		return "The last night: about %d, from everywhere" % int(f.get("total", 0))
	var text := "Tonight: about %d" % int(f.get("total", 0))
	var heading := String(f.get("heading", ""))
	if heading != "":
		text += " from the %s" % heading
	var brutes := int(f.get("brutes", 0))
	if brutes > 0:
		text += ", a brute" if brutes == 1 else ", %d brutes" % brutes
	elif bool(f.get("runners", false)):
		text += ", runners"
	return text


func _rank(a: Dictionary) -> int:
	return 3 if a.level == "danger" else (2 if a.level == "warn" else 1)


## About how much health a fresh one of this kind has, for the meter: a walker's is
## five, the others the middle of their range (see kinds.gd).
func _zombie_hp(z) -> float:
	var k: Dictionary = Kinds.KINDS.get(String(z.kind), Kinds.KINDS.walker)
	if z.kind == Kinds.WALKER:
		return 5.0
	return maxf(1.0, (float(k.hp[0]) + float(k.hp[1])) / 2.0)


func _doing_zombie(z) -> String:
	match z.state:
		"dead", "dying":
			return "Dead for good"
		"attack":
			return "Clawing at the %s" % String(z.slot.seg.name).to_lower()
		"approach":
			return String(ZOMBIE_VERBS.get(String(z.kind), ZOMBIE_VERBS.walker))
		"breach":
			return "Inside the yard, hunting"
		"retreat":
			return "Drifting back into the city"
	return "Wandering the street"


## What a person is doing, or why they are not.
func _doing_person(p) -> String:
	if p.dead:
		if p.turned:
			return "Turned into one of the dead"
		return "Left through the gate" if p.away is Dictionary and String(p.away.get("kind", "")) == "exile" else "Dead"
	if p.away != null:
		return _away_text(p)
	if p.downed:
		# the medical module says what ("Down and bleeding", "Collapsed from hunger", "Resting in the infirmary")
		return p.activity if p.activity != "" else "Down and bleeding"
	if p.reloading > 0.0:
		return "Reloading"
	if p.target != null:
		return "Shooting at a walker"
	return p.activity


## "Scavenging at the pharmacy" for someone out with a scavenging party.
func _away_text(p) -> String:
	if p.away is Dictionary and sim_ref != null:
		var id := String(p.away.get("site", ""))
		for site in sim_ref.scavenge.sites:
			if String(site.get("id", "")) == id:
				return "Scavenging at %s" % String(site.get("where", String(site.get("name", "")).to_lower()))
	return "Away scavenging"


## [text, colour] for the Needs row, from the game hours since a meal and a drink.
func _needs_of(p) -> Array:
	if p.dead:
		return ["–", INK3]
	var bits: Array = []
	var severe := false
	if p.hunger_h >= STARVING_H:
		bits.append("Starving")
		severe = true
	elif p.hunger_h >= HUNGRY_H:
		bits.append("Hungry")
	if p.thirst_h >= PARCHED_H:
		bits.append("Parched")
		severe = true
	elif p.thirst_h >= THIRSTY_H:
		bits.append("Thirsty")
	if bits.is_empty():
		return ["Fed", INK]
	var text: String = bits[0]
	for i in range(1, bits.size()):
		text += ", " + String(bits[i]).to_lower()
	return [text, DANGER_TEXT if severe else WARN]


## [text, colour] for the Wounds row.
func _wounds_of(p) -> Array:
	if p.dead:
		return ["–", INK3]
	if p.wounds > 0:
		return ["%d wound%s, bleeding" % [p.wounds, "" if p.wounds == 1 else "s"], DANGER_TEXT]
	if p.bleeding > 0.0:
		return ["Bleeding", DANGER_TEXT]
	return ["None", INK2]


func _set_text(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _refresh_selection() -> void:
	if selection == null or inspect_refs.is_empty():
		return
	var f := 1.0
	var doing := ""
	if selection.kind == "person":
		var p = selection.ref
		f = p.hp / 100.0
		doing = _doing_person(p)
		var need := _needs_of(p)
		_set_text(inspect_refs.needs, need[0], need[1])
		var wound := _wounds_of(p)
		_set_text(inspect_refs.wounds, wound[0], wound[1])
		var stage: String = sim_ref.medical.infection_stage(p) if sim_ref != null else ""
		inspect_refs.infection.visible = stage != ""
		inspect_refs.infection_head.visible = stage != ""
		_set_text(inspect_refs.infection, stage.capitalize(), WARN)
		inspect_refs.auto_tag.visible = not p.dead and _auto_on(p)
		var pips: HBoxContainer = inspect_refs.pips
		var n := pips.get_child_count()
		if n > 0:
			var full := roundi(float(p.mag) / float(p.gun.mag) * n)
			for i in n:
				var pip: ColorRect = pips.get_child(i)
				pip.color = ACCENT if i < full else Color(1, 1, 1, 0.14)
		if inspect_refs.get("gizmo_sig") != _gizmo_sig():
			_build_gizmos()
	elif selection.kind == "zombie":
		var z = selection.ref
		f = maxf(0.0, z.hp) / _zombie_hp(z)
		doing = _doing_zombie(z)
	else:
		var s = selection.ref
		f = s.hp / s.max_hp
		var n := 0
		for sl in s.slots:
			if sl.who != null:
				n += 1
		if s.state == 3:
			doing = "Breached"
		elif n > 0:
			doing = "%d walker%s clawing at it" % [n, "s" if n > 1 else ""]
		elif f < 1.0:
			doing = "Damaged"
		else:
			doing = "Holding"
	var b: Bar = inspect_refs.hp
	b.value = clampf(f, 0.0, 1.0)
	b.color = _hp_color(f)
	b.queue_redraw()
	inspect_refs.hpv.text = "%d%%" % roundi(clampf(f, 0.0, 1.0) * 100.0)
	if inspect_refs.doing.text != doing:
		inspect_refs.doing.text = doing
	_refresh_gizmo_tips()
