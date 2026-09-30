## The HUD, laid out the way colony games do it: people across the top, stores
## top left, clock and alerts top right, the selection bottom left, time
## controls bottom right. Mirrors the web version's HUD.
extends Control

const GD := preload("res://scripts/game_data.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Dialog := preload("res://scripts/ui/scavenge_dialog.gd")
const GameOver := preload("res://scripts/ui/game_over.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const INK := Color("#ece6d8")
const INK2 := Color("#b7af9e")
const INK3 := Color("#7c7565")
const PANEL := Color(21 / 255.0, 20 / 255.0, 17 / 255.0, 0.86)
const PANEL_HI := Color(36 / 255.0, 34 / 255.0, 30 / 255.0, 0.94)
const LINE := Color(1.0, 238 / 255.0, 205 / 255.0, 0.09)
const LINE2 := Color(1.0, 238 / 255.0, 205 / 255.0, 0.18)
const ACCENT := Color("#f0c24a")
const ACCENT_INK := Color("#1a1508")
const DANGER := Color("#e0584a")
const WARN := Color("#e8953a")
const OK := Color("#8fb85a")
const INFO := Color("#7fa6c9")
const DAWN := Color("#e2a3b6")

const PHASE_ICON := {"day": "sun", "dusk": "sun", "night": "moon", "dawn": "sun"}
const PHASE_COLOR := {"day": ACCENT, "dusk": WARN, "night": INFO, "dawn": DAWN}
const LEVEL_ICON := {"danger": "warn", "warn": "walker", "info": "bell"}
const LEVEL_COLOR := {"danger": DANGER, "warn": WARN, "info": INFO}
const SIDE := {"N": "North wall", "W": "West wall", "E": "East wall"}
const MATERIAL := {"container": "shipping container", "bus": "school bus", "car": "wrecked car", "pallets": "pallets and stakes", "gate": "steel gate", "chainlink": "fence and wire", "blocks": "cinderblock"}
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
var alerts_box: VBoxContainer
var alert_sig := ""
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
var help: PanelContainer
var hint: PanelContainer
var last_speed := -1


func setup(game_data: Dictionary, crew: Array) -> void:
	data = game_data
	people = crew
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	resized.connect(_on_resized)
	_on_resized()


# ---------------------------------------------------------------- helpers --

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


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _caps(text: String) -> Label:
	return _label(text.to_upper(), Fonts.cond(600, 1), 11, INK3)


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


func _kbd(text: String) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.08)
	s.border_color = LINE2
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
	p.add_child(_label(text, Fonts.cond(600), 11, INK))
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
	add_child(res_panel)
	_corner(res_panel, false, false, 12, 12)


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
		c.name.add_theme_font_size_override("font_size", 13 if w >= 56 else 11)
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


func _build_clock() -> void:
	clock = _panel(_style())
	var v := _vbox(6)
	var r1 := _hbox(8)
	day_label = _caps("Day 3")
	r1.add_child(day_label)
	r1.add_child(_spacer())
	phase_chip = PanelContainer.new()
	phase_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := _hbox(5)
	phase_icon = _icon("sun", 12)
	phase_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(phase_icon)
	phase_label = _label("DAY", Fonts.cond(700, 1), 11, ACCENT)
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
	clock.add_child(v)
	clock.custom_minimum_size.x = 226
	add_child(clock)
	_corner(clock, true, false, 12, 12)


# ----------------------------------------------------------------- alerts --

func _build_alerts() -> void:
	alerts_box = _vbox(6)
	alerts_box.custom_minimum_size.x = 226
	add_child(alerts_box)
	_corner(alerts_box, true, false, 12, 150)


func _alert_panel(a: Dictionary) -> PanelContainer:
	var s := _style(PANEL, 6, LINE, true)
	s.border_width_left = 3
	s.border_color = LINE
	var level_col: Color = LEVEL_COLOR.get(a.level, WARN)
	s.content_margin_left = 9
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.content_margin_right = 10
	var p := _panel(s)
	var edge := ColorRect.new()
	edge.color = level_col
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := _hbox(9)
	var ic := _icon(LEVEL_ICON.get(a.level, "warn"), 16, level_col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ic)
	var col := _vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label(a.text, Fonts.sans(600), 13, INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	col.add_child(_label(a.sub, Fonts.sans(400), 12, INK2))
	row.add_child(col)
	p.add_child(row)
	p.gui_input.connect(_on_alert_input.bind(String(a.id)))
	p.mouse_entered.connect(func(): s.bg_color = PANEL_HI)
	p.mouse_exited.connect(func(): s.bg_color = PANEL)
	# a coloured bar down the left edge
	p.draw.connect(func(): p.draw_rect(Rect2(0, 3, 3, p.size.y - 6), level_col))
	return p


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
	if dock == null or speed_panel == null or help == null or res_panel == null:
		return
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
		var room := size.y - 12.0 - (12.0 + res_panel.get_combined_minimum_size().y + 8.0)
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
		return
	inspect.visible = true
	if hint != null:
		hint.visible = false
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
	elif sel.kind == "zombie":
		var z = sel.ref
		head.add_child(_pic(GD.tex(data.portraits["z%d" % z.look_index])))
		titles.add_child(_label("Walker", Fonts.cond(700), 21, INK))
		titles.add_child(_label("One of the dead", Fonts.sans(400), 13, INK2))
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
		titles.add_child(_label("%s · %s" % [SIDE[s.side], MATERIAL[s.kind]], Fonts.sans(400), 13, INK2))
		var m := _meter()
		_row(grid, "Integrity", m[0])
		inspect_refs.hp = m[1]
		inspect_refs.hpv = m[2]
		var doing := _label("", Fonts.sans(400), 13, INK)
		_row(grid, "Status", doing)
		inspect_refs.doing = doing
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(titles)
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
	var ic := _icon(id, 20 if gizmo_mini else 22, col)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(ic)
	if gizmo_mini:
		b.tooltip_text = "%s (%s)" % [text, key]
	else:
		var l := _label(text.to_upper(), Fonts.cond(600, 1), 11, col)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(l)
	b.add_child(inner)
	if not gizmo_mini:
		var k := _label(key, Fonts.cond(600), 10, Color(ACCENT_INK, 0.55) if on else INK3)
		k.position = Vector2(52, 3)
		b.add_child(k)
	b.pressed.connect(func(): on_gizmo.call(id))
	return b


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
			if sim_ref != null and sim_ref.medical.can_treat(p):
				gizmos.add_child(_gizmo("treat", "Treat", "T", false))
			if sim_ref != null and sim_ref.medical.can_send_out(p):
				gizmos.add_child(_gizmo("sendout", "Send out", "X", false))
			if _can_scavenge(p):
				gizmos.add_child(_gizmo("scavenge", "Scavenge", "G", false))
	elif selection.kind == "segment":
		gizmos.add_child(_gizmo("repair", "Repair", "F", false))
		gizmos.add_child(_gizmo("focus", "Focus", "C", false))
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
		sig += "|%s|%s|%s" % [sim_ref.medical.can_treat(p), sim_ref.medical.can_send_out(p), _can_scavenge(p)]
	return sig


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
	var tips := ["Pause (Space)", "Normal speed (1)", "Fast (2)", "Fastest (3)"]
	var names := ["pause", "play", "ff", "fff"]
	for i in 4:
		var b := _speed_button(names[i], tips[i])
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
	sound_button = _speed_button("soundOn", "Sound")
	sound_button.pressed.connect(func(): on_sound.call())
	row.add_child(sound_button)
	var hb := _speed_button("help", "Controls")
	hb.pressed.connect(func(): help.visible = not help.visible)
	row.add_child(hb)
	panel.add_child(row)
	add_child(panel)
	_corner(panel, true, true, 12, 12)


func _spacer_fixed(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _build_help() -> void:
	help = _panel(_style())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair in [["Click", "Select a person, walker or wall piece"], ["Right-click", "Send the selected person there"], ["Drag", "Pan the map (or W A S D)"], ["Scroll", "Zoom"], ["R", "Draft or release"], ["T", "Treat the wounded or infected"], ["X", "Send an infected person out"], ["G", "Send a scavenging party"], ["Space", "Pause"], ["Tab", "Next person"]]:
		grid.add_child(_kbd(pair[0]))
		var l := _label(pair[1], Fonts.sans(400), 12, INK2)
		grid.add_child(l)
	help.add_child(grid)
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
	b.add_theme_color_override("font_disabled_color", Color(ink, 0.5))
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
		clock.custom_minimum_size.x = 164 if compact else 226
		alerts_box.custom_minimum_size.x = 164 if compact else 226
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
		c.word.add_theme_color_override("font_color", DANGER if word == "Turned" else (INFO if word == "Away" else INK2))
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
		dl.add_theme_color_override("font_color", DANGER if days < 1.0 else (WARN if days < 3.0 else INK3))
	for c in cards:
		_update_card(c, sim)
	# clock
	var m := int(sim.minutes)
	var h: float = sim.hour
	day_label.text = ("DAY %d/%d" if compact else "DAY %d OF %d") % [sim.scenario.day(), sim.scenario.total_days()]
	var pc: Color = PHASE_COLOR[sim.phase]
	phase_chip.add_theme_stylebox_override("panel", _chip_style(pc))
	phase_icon.texture = icons[PHASE_ICON[sim.phase]]
	phase_icon.modulate = pc
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
	temp_icon.texture = icons[PHASE_ICON[sim.phase]]
	temp_label.text = "%d°C, %s" % [temp, sim.weather]
	walkers_label.text = "%d walkers" % walkers
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
	# alerts
	var list: Array = sim.alerts.values()
	list.sort_custom(func(a, b): return _rank(a) > _rank(b) or (_rank(a) == _rank(b) and a.born > b.born))
	list = list.slice(0, 3 if compact else 5)
	var sig := ""
	for a in list:
		sig += "%s:%s:%s|" % [a.id, a.text, a.sub]
	if sig != alert_sig:
		alert_sig = sig
		for c in alerts_box.get_children():
			c.queue_free()
		for a in list:
			alerts_box.add_child(_alert_panel(a))
	_refresh_selection()


func _rank(a: Dictionary) -> int:
	return 3 if a.level == "danger" else (2 if a.level == "warn" else 1)


func _doing_zombie(z) -> String:
	match z.state:
		"dead", "dying":
			return "Dead for good"
		"attack":
			return "Clawing at the %s" % String(z.slot.seg.name).to_lower()
		"approach":
			return "Shambling toward the wall"
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
		# resting in bed or stabilised: the medical module says what; else still bleeding
		return p.activity if (p.stabilised or p.resting_bed != null) and p.activity != "" else "Down and bleeding"
	if p.reloading > 0.0:
		return "Reloading"
	if p.target != null:
		return "Shooting at a walker"
	return p.activity


## "Away at the pharmacy" for someone out with a scavenging party.
func _away_text(p) -> String:
	if p.away is Dictionary and sim_ref != null:
		var id := String(p.away.get("site", ""))
		for site in sim_ref.scavenge.sites:
			if String(site.get("id", "")) == id:
				return "Away at %s" % String(site.get("name", "")).to_lower()
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
	return [text, DANGER if severe else WARN]


## [text, colour] for the Wounds row.
func _wounds_of(p) -> Array:
	if p.dead:
		return ["–", INK3]
	if p.wounds > 0:
		return ["%d wound%s, bleeding" % [p.wounds, "" if p.wounds == 1 else "s"], DANGER]
	if p.bleeding > 0.0:
		return ["Bleeding", DANGER]
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
		f = maxf(0.0, z.hp) / 5.0
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
