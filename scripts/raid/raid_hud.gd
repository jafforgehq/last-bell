## The raid's HUD (round 14, R14.3): its own CanvasLayer over the raid scene (raid_scene.gd), in the noticeboard style of
## the rest of the game. It borrows the game HUD's helpers (`_style`, `_panel`, `_label`, `_button`, `_kbd`, `_icon`,
## the paper page...) so that it looks like it and changes with the theme.
##
##   top        the place's name and a line about what to do (left), the squad's cards (middle: portrait, name, health,
##              weapon and magazine, what they are doing), the bags (right: what is in them by stock, "n of m")
##              - in a narrow window the cards drop to a row of their own under the other two
##   bottom     the log of what happened (the last four lines, fading), the legend of the controls (fades; H brings it
##              back) and the Retreat button with its key
##   over all   a banner ("They heard that", "Marcus is down"), a toast for an order that cannot be given, the "Retreat?"
##              question, and, when the run is over, the end card (a paper page: what came home, who is hurt or lost,
##              the place, the ammo used, and one button: Go home)
##
## Everything is laid out in `_layout`, from the panels' own sizes, so that nothing overlaps at any width from 700 up.
## Nothing is set under Fonts.MIN_PX (the label factory raises it).
extends CanvasLayer

const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

const PAD := 12.0
const GAP := 10.0
const CARD_MIN_W := 156.0
const CARD_MAX_W := 196.0
const CARD_H := 66.0
const PORTRAIT := 46.0
const LOG_LINES := 4
const LOG_W := 380.0
const LOG_HOLD := 12.0
const LOG_FADE := 3.0
## How long the legend shows when the raid begins (and after H), and how long it takes to fade.
const LEGEND_HOLD := 14.0
const LEGEND_FADE := 2.0
const BANNER_HOLD := 3.0
const BANNER_FADE := 0.5
const TOAST_HOLD := 2.4
const TOAST_FADE := 0.4
const PLACE_W := 290.0
const END_W := 540.0
const STOCK_ORDER := ["food", "water", "scrap", "ammo", "meds", "fuel"]
const STOCK_NAMES := {"food": "Food", "water": "Water", "scrap": "Scrap", "ammo": "Ammo", "meds": "Medicine", "fuel": "Fuel"}
const LEGEND := [
	[["Click", "Drag"], "select"], [["Right-click"], "move, search, help"], [["Space"], "pause"], [["R"], "retreat"],
	[["Tab"], "next"], [["F"], "follow"], [["Scroll"], "zoom"],
]
const STATUS_COLOR := {"Down": Hud.DANGER_TEXT, "Lost": Hud.DANGER_TEXT, "Searching": Hud.ACCENT, "Helping": Hud.INFO, "Going to search": Hud.INK2, "Going to help": Hud.INK2, "Reloading": Hud.WARN, "Fighting": Hud.WARN}

var hud
var scene
var root: Control

var place_panel: PanelContainer
var place_label: Label
var line_label: Label
var paused_chip: PanelContainer

var loot_panel: PanelContainer
var bags_label: Label
var bag_fill: ColorRect
var bag_track: Control
var chips_box: HBoxContainer
var chips := {}          # stock -> {"box": HBoxContainer, "num": Label}
var empty_label: Label

var cards_grid: GridContainer
var cards: Array = []    # {"p", "panel", "pic", "name", "hp", "weapon", "status"}
var card_w := CARD_MIN_W

var log_panel: PanelContainer
var log_labels: Array = []
var legend_panel: PanelContainer
var retreat_panel: PanelContainer
var retreat_button: Button
var retreat_key: Control

var banner: PanelContainer
var banner_title: Label
var banner_sub: Label
var banner_tween: Tween
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var ask_panel: PanelContainer
var ask_yes: Button
var ask_warn: Label
var ask_no: Button
var end_card: Control
var end_button: Button
var end_panel: PanelContainer
var end_title: Label
var end_sub: Label
var end_rows := {}       # "loot", "hurt", "lost", "place", "rescue", "ammo" -> the value's Control

var _log_seen := 0
var _log: Array = []     # [{"text", "t"}]
var _sig := ""
var _layout_w := -1.0


func setup(game_hud, the_scene) -> void:
	hud = game_hud
	scene = the_scene
	name = "RaidHud"
	root = Control.new()
	root.name = "Root"
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = hud.theme
	_build_place()
	_build_loot()
	_build_cards()
	_build_log()
	_build_legend()
	_build_retreat()
	_build_banner()
	_build_toast()
	_build_ask()
	root.resized.connect(_layout)
	_layout()


# ------------------------------------------------------------------ parts --

func _put(c: Control) -> void:
	root.add_child(c)
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)


func _build_place() -> void:
	place_panel = hud._panel()
	place_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: VBoxContainer = hud._vbox(3)
	var head: HBoxContainer = hud._hbox(8)
	place_label = hud._label(String(scene.site.get("name", "The place")), Fonts.cond(700), 22, Hud.INK)
	place_label.clip_text = true
	place_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	place_label.custom_minimum_size.x = 120.0
	place_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(place_label)
	paused_chip = _pill_chip("PAUSED", "pause")
	paused_chip.visible = false
	head.add_child(paused_chip)
	col.add_child(head)
	line_label = hud._label("", Fonts.sans(400), 13, Hud.INK2)
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size.x = PLACE_W
	col.add_child(line_label)
	place_panel.add_child(col)
	_put(place_panel)


## A small pale stamp with an icon and a word (PAUSED).
func _pill_chip(text: String, icon_name: String) -> PanelContainer:
	var s: StyleBox = hud.frame("pill")
	if s == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Hud.INK
		f.set_corner_radius_all(9)
		f.anti_aliasing = true
		f.content_margin_left = 6
		f.content_margin_right = 7
		f.content_margin_top = 1
		f.content_margin_bottom = 2
		s = f
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", s)
	var row: HBoxContainer = hud._hbox(3)
	var ic: TextureRect = hud._icon(icon_name, 11, Hud.ACCENT_INK)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	row.add_child(hud._label(text, Fonts.cond(700, 1), 12, Hud.ACCENT_INK))
	chip.add_child(row)
	return chip


func _build_loot() -> void:
	loot_panel = hud._panel()
	loot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: VBoxContainer = hud._vbox(5)
	var head: HBoxContainer = hud._hbox(8)
	head.add_child(hud._caps("In the bags"))
	head.add_child(hud._spacer())
	bags_label = hud._label("0 of 0", Fonts.cond(700), 15, Hud.INK)
	head.add_child(bags_label)
	col.add_child(head)
	bag_track = Control.new()
	bag_track.custom_minimum_size = Vector2(200, 6)
	bag_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := ColorRect.new()
	track.color = Color(0, 0.03, 0.02, 0.55)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_track.add_child(track)
	bag_fill = ColorRect.new()
	bag_fill.color = Hud.OK
	bag_fill.anchor_right = 0.0
	bag_fill.anchor_bottom = 1.0
	bag_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_track.add_child(bag_fill)
	col.add_child(bag_track)
	chips_box = hud._hbox(10)
	chips_box.custom_minimum_size.y = 22.0
	for stock in STOCK_ORDER:
		_make_chip(stock)
	empty_label = hud._label("Nothing yet", Fonts.sans(400), 13, Hud.INK3)
	chips_box.add_child(empty_label)
	col.add_child(chips_box)
	loot_panel.add_child(col)
	_put(loot_panel)


func _make_chip(stock: String) -> Dictionary:
	if chips.has(stock):
		return chips[stock]
	var box: HBoxContainer = hud._hbox(4)
	if hud.icons.has(stock):
		var ic: TextureRect = hud._icon(stock, 18, Hud.INK)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(ic)
	else:
		box.add_child(hud._label(String(STOCK_NAMES.get(stock, stock.capitalize())), Fonts.sans(400), 12, Hud.INK3))
	var num: Label = hud._label("0", Fonts.cond(700), 16, Hud.INK)
	box.add_child(num)
	box.visible = false
	box.tooltip_text = String(STOCK_NAMES.get(stock, stock.capitalize()))
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	chips_box.add_child(box)
	if empty_label != null:
		chips_box.move_child(empty_label, chips_box.get_child_count() - 1)
	chips[stock] = {"box": box, "num": num}
	return chips[stock]


func _build_cards() -> void:
	cards_grid = GridContainer.new()
	cards_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_grid.add_theme_constant_override("h_separation", int(GAP) - 4)
	cards_grid.add_theme_constant_override("v_separation", 4)
	_put(cards_grid)
	var i := 0
	for p in scene.run.squad:
		cards.append(_make_card(p, i))
		cards_grid.add_child(cards[i].panel)
		i += 1


func _card_box(selected: bool) -> StyleBox:
	var tint := Color(1.0, 0.92, 0.6) if selected else Color.WHITE
	var s: StyleBox = hud._style(Hud.PANEL, 6, Hud.ACCENT if selected else Hud.LINE2, true, "panel_slim", tint)
	if s is StyleBoxFlat:
		s.content_margin_left = 6
		s.content_margin_right = 8
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		s.set_border_width_all(2 if selected else 1)
	return s


func _make_card(p, index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(card_w, CARD_H)
	panel.add_theme_stylebox_override("panel", _card_box(false))
	panel.tooltip_text = "%s, %s. Click to select (key %d)" % [p.name, String(p.def.role).to_lower(), index + 1]
	var row: HBoxContainer = hud._hbox(7)
	# the portrait in a small window with a thin edge
	var win := PanelContainer.new()
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ws := StyleBoxFlat.new()
	ws.bg_color = Color("#16221f")
	ws.border_color = Color(0.82, 0.78, 0.64, 0.5)
	ws.set_border_width_all(1)
	ws.set_corner_radius_all(4)
	ws.set_content_margin_all(1)
	win.add_theme_stylebox_override("panel", ws)
	var pic := TextureRect.new()
	pic.texture = hud.portrait_of(p)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(pic)
	row.add_child(win)
	var col: VBoxContainer = hud._vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var head: HBoxContainer = hud._hbox(4)
	var nm: Label = hud._label(p.first, Fonts.cond(700), 15, Hud.INK)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	head.add_child(hud._kbd(str(index + 1)))
	col.add_child(head)
	var track := Control.new()
	track.custom_minimum_size = Vector2(60, 6)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := ColorRect.new()
	back.color = Color(0, 0.03, 0.02, 0.6)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(back)
	var fill := ColorRect.new()
	fill.color = Hud.OK
	fill.anchor_bottom = 1.0
	fill.anchor_right = 1.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	col.add_child(track)
	var weapon: Label = hud._label("", Fonts.sans(400), 12, Hud.INK2)
	weapon.clip_text = true
	weapon.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(weapon)
	var status: Label = hud._label("", Fonts.sans(600), 12, Hud.INK2)
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(status)
	row.add_child(col)
	panel.add_child(row)
	panel.gui_input.connect(_on_card_input.bind(p))
	return {"p": p, "panel": panel, "pic": pic, "name": nm, "hp": fill, "weapon": weapon, "status": status, "selected": false}


func _on_card_input(ev: InputEvent, p) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if scene.ended or scene.asking:
			return
		if ev.shift_pressed:
			var more: Array = scene.selection.duplicate()
			if more.has(p):
				more.erase(p)
			else:
				more.append(p)
			scene.select(more)
		else:
			scene.select_one(p)


func _build_log() -> void:
	log_panel = hud._panel(hud._style(Color(Hud.PANEL, 0.82), 6, Hud.LINE, false))
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: VBoxContainer = hud._vbox(2)
	for i in LOG_LINES:
		var l: Label = hud._label("", Fonts.sans(400), 13, Hud.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = LOG_W
		l.visible = false
		col.add_child(l)
		log_labels.append(l)
	log_panel.add_child(col)
	log_panel.visible = false
	_put(log_panel)


func _build_legend() -> void:
	legend_panel = hud._panel()
	legend_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 4)
	for entry in LEGEND:
		var item: HBoxContainer = hud._hbox(3)
		for key in entry[0]:
			item.add_child(hud._kbd(String(key)))
		var what: Label = hud._label(String(entry[1]), Fonts.sans(400), 12, Hud.INK2)
		what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(what)
		flow.add_child(item)
	legend_panel.add_child(flow)
	legend_panel.visible = false
	_put(legend_panel)


func _build_retreat() -> void:
	retreat_panel = hud._panel()
	var row: HBoxContainer = hud._hbox(8)
	retreat_button = hud._button("Retreat")
	retreat_button.custom_minimum_size = Vector2(112, 38)
	retreat_button.tooltip_text = "Everyone walks back to the road and the trip ends. What is in the bags comes home."
	retreat_button.pressed.connect(func(): scene.retreat())
	row.add_child(retreat_button)
	retreat_key = hud._kbd("R")
	row.add_child(retreat_key)
	retreat_panel.add_child(row)
	_put(retreat_panel)


func _build_banner() -> void:
	banner = PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sign_box: StyleBox = hud._style(Hud.PANEL, 6, Hud.LINE2, true, "banner")
	if sign_box is StyleBoxFlat:
		sign_box.content_margin_left = 26
		sign_box.content_margin_right = 26
		sign_box.content_margin_top = 8
		sign_box.content_margin_bottom = 10
	banner.add_theme_stylebox_override("panel", sign_box)
	var words: VBoxContainer = hud._vbox(1)
	banner_title = hud._label("", Fonts.cond(700, 3), 28, Hud.INK)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	banner_title.add_theme_constant_override("shadow_offset_y", 2)
	words.add_child(banner_title)
	banner_sub = hud._label("", Fonts.sans(400), 14, Hud.INK2)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(banner_sub)
	banner.add_child(words)
	banner.modulate.a = 0.0
	_put(banner)


func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = hud._label("", Fonts.sans(600), 14, Hud.INK)
	toast_panel.add_child(toast_label)
	toast_panel.visible = false
	var st: StyleBox = hud._style(Hud.PANEL, 6, Hud.INFO, true, "toast")
	if st is StyleBoxFlat:
		st.content_margin_left = 12
		st.content_margin_right = 14
		st.content_margin_top = 7
		st.content_margin_bottom = 8
	toast_panel.add_theme_stylebox_override("panel", st)
	_put(toast_panel)


func _build_ask() -> void:
	ask_panel = hud._panel()
	var col: VBoxContainer = hud._vbox(8)
	var title: Label = hud._label("Retreat?", Fonts.cond(700), 28, Hud.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var what: Label = hud._label("Everyone walks back to the road and the trip ends. What is in the bags comes home.", Fonts.sans(400), 14, Hud.INK2)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size.x = 330.0
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(what)
	ask_warn = hud._label("", Fonts.sans(600), 14, Hud.WARN)
	ask_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ask_warn.custom_minimum_size.x = 330.0
	ask_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ask_warn.visible = false
	col.add_child(ask_warn)
	var buttons: HBoxContainer = hud._hbox(10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	ask_yes = hud._button("Retreat", true)
	ask_yes.pressed.connect(func(): scene.retreat())
	buttons.add_child(ask_yes)
	buttons.add_child(hud._kbd("Enter"))
	ask_no = hud._button("Keep going")
	ask_no.pressed.connect(func(): scene.cancel_ask())
	buttons.add_child(ask_no)
	buttons.add_child(hud._kbd("Any key"))
	col.add_child(buttons)
	ask_panel.add_child(col)
	ask_panel.visible = false
	_put(ask_panel)


# ----------------------------------------------------------------- layout --

## Where everything goes, from the panels' own sizes. The squad's cards sit between the place and the bags when all
## of them fit there at their narrowest, and otherwise in a row (or rows) of their own under both.
func _layout() -> void:
	if root == null or place_panel == null:
		return
	var w: float = root.size.x
	var h: float = root.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var ps := place_panel.get_combined_minimum_size()
	var ls := loot_panel.get_combined_minimum_size()
	_place(place_panel, Vector2(PAD, PAD))
	_place(loot_panel, Vector2(w - PAD - ls.x, PAD))
	var n := cards.size()
	var between := w - 2.0 * PAD - ps.x - ls.x - 2.0 * GAP
	var plan := plan_cards(n, between)
	var top_end := PAD + maxf(ps.y, ls.y)
	if plan.fits:
		_size_cards(plan)
		var cs := cards_grid.get_combined_minimum_size()
		var x := clampf(w / 2.0 - cs.x / 2.0, PAD + ps.x + GAP, w - PAD - ls.x - GAP - cs.x)
		_place(cards_grid, Vector2(x, PAD))
		top_end = maxf(top_end, PAD + cs.y)
	else:
		plan = plan_cards(n, w - 2.0 * PAD)
		_size_cards(plan)
		var cs2 := cards_grid.get_combined_minimum_size()
		_place(cards_grid, Vector2(maxf(PAD, w / 2.0 - cs2.x / 2.0), top_end + 6.0))
		top_end = top_end + 6.0 + cs2.y
	var bs := banner.get_combined_minimum_size()
	_place(banner, Vector2(w / 2.0 - bs.x / 2.0, top_end + 8.0))
	# the foot: the Retreat button at the right, the log at the left with the legend over it
	var rs := retreat_panel.get_combined_minimum_size()
	_place(retreat_panel, Vector2(w - PAD - rs.x, h - PAD - rs.y))
	var stack_top := h - PAD
	if log_panel.visible:
		var logs := log_panel.get_combined_minimum_size()
		_place(log_panel, Vector2(PAD, h - PAD - logs.y))
		stack_top = h - PAD - logs.y - 6.0
	legend_panel.custom_minimum_size.x = minf(660.0, w - 2.0 * PAD - rs.x - GAP)
	var ls2 := legend_panel.get_combined_minimum_size()
	_place(legend_panel, Vector2(PAD, stack_top - ls2.y))
	stack_top = minf(stack_top - (ls2.y + 6.0 if legend_panel.visible else 0.0), h - PAD - rs.y - 6.0)
	var ts := toast_panel.get_combined_minimum_size()
	_place(toast_panel, Vector2(w / 2.0 - ts.x / 2.0, stack_top - ts.y - 4.0))
	var asks := ask_panel.get_combined_minimum_size()
	_place(ask_panel, Vector2(w / 2.0 - asks.x / 2.0, h / 2.0 - asks.y / 2.0))
	_layout_w = w
	_sig = _signature()


func _place(c: Control, at: Vector2) -> void:
	c.position = at.round()
	c.size = c.get_combined_minimum_size()


## How the squad's cards are laid out in `room` pixels: {"w": a card's width, "per_row", "rows", "fits": whether they all
## fit in one row of at least CARD_MIN_W each}.
static func plan_cards(n: int, room: float) -> Dictionary:
	var gap := GAP - 4.0
	var count := maxi(n, 1)
	if float(count) * CARD_MIN_W + float(count - 1) * gap <= room:
		var wide := minf(CARD_MAX_W, (room - float(count - 1) * gap) / float(count))
		return {"w": wide, "per_row": count, "rows": 1, "fits": true}
	var per := maxi(1, int((room + gap) / (CARD_MIN_W + gap)))
	var rows := ceili(float(count) / float(per))
	per = ceili(float(count) / float(rows))
	var wide2 := clampf((room - float(per - 1) * gap) / float(per), CARD_MIN_W * 0.8, CARD_MAX_W)
	return {"w": wide2, "per_row": per, "rows": rows, "fits": false}


func _size_cards(plan: Dictionary) -> void:
	card_w = float(plan.w)
	cards_grid.columns = int(plan.per_row)
	for c in cards:
		c.panel.custom_minimum_size = Vector2(card_w, CARD_H)


func _signature() -> String:
	var parts: Array = [root.size, place_panel.get_combined_minimum_size(), loot_panel.get_combined_minimum_size(), cards.size(), card_w,
		log_panel.visible, log_panel.get_combined_minimum_size(), legend_panel.visible, legend_panel.get_combined_minimum_size(),
		retreat_panel.get_combined_minimum_size(), banner.get_combined_minimum_size(), toast_panel.get_combined_minimum_size(), ask_panel.get_combined_minimum_size()]
	return str(parts)


# ---------------------------------------------------------------- refresh --

## Brings every part up to date with the run (called a few times a second, and when the selection or a state changes).
func refresh() -> void:
	if scene == null or scene.run == null:
		return
	var run = scene.run
	_refresh_place(run)
	_refresh_loot(run)
	_refresh_cards(run)
	_refresh_log(run)
	var live: bool = not scene.ended
	legend_panel.visible = live and scene.legend_t > 0.0
	legend_panel.modulate.a = clampf(scene.legend_t / LEGEND_FADE, 0.0, 1.0)
	retreat_panel.visible = live
	var going: bool = run.phase != "play"
	retreat_button.disabled = going
	retreat_button.text = "Retreating" if going else "Retreat"
	retreat_key.visible = not going
	ask_panel.visible = live and scene.asking
	var left: Array = []
	for p in run.squad:
		if p.downed and not p.dead:
			left.append(p.first)
	ask_warn.visible = not left.is_empty()
	ask_warn.text = "%s %s down and will be left behind." % [", ".join(left), "is" if left.size() == 1 else "are"]
	if end_card != null:
		end_card.visible = scene.ended
	if _signature() != _sig or root.size.x != _layout_w:
		_layout()


func _refresh_place(run) -> void:
	paused_chip.visible = scene.paused and not scene.ended
	line_label.text = scene.hint_line() if not scene.ended else "The trip is over."


func _refresh_loot(run) -> void:
	var cap: int = run.capacity()
	var total: int = run.carried_total()
	bags_label.text = "%d of %d" % [total, cap]
	var ratio := clampf(float(total) / maxf(float(cap), 1.0), 0.0, 1.0)
	bag_fill.anchor_right = ratio
	bag_fill.offset_right = 0.0
	bag_fill.color = Hud.DANGER if ratio >= 0.999 else (Hud.WARN if ratio >= 0.8 else Hud.OK)
	var any := false
	var seen := {}
	for stock in STOCK_ORDER:
		seen[stock] = true
	for k in run.carried:
		if not seen.has(String(k)):
			_make_chip(String(k))
	for stock in chips:
		var n: int = int(run.carried.get(stock, 0))
		var chip: Dictionary = chips[stock]
		chip.box.visible = n > 0
		chip.num.text = str(n)
		any = any or n > 0
	empty_label.visible = not any


func _refresh_cards(run) -> void:
	for c in cards:
		var p = c.p
		var selected: bool = scene.is_selected(p)
		if selected != bool(c.selected):
			c.selected = selected
			c.panel.add_theme_stylebox_override("panel", _card_box(selected))
		var f := clampf(p.hp / 100.0, 0.0, 1.0)
		c.hp.anchor_right = f
		c.hp.offset_right = 0.0
		c.hp.color = Hud.DANGER if (p.downed or p.dead) else hud._hp_color(f)
		var gun: Dictionary = p.gun
		var mag := "" if gun.get("melee", false) else "  %d/%d" % [p.mag, int(gun.mag)]
		c.weapon.text = "%s%s" % [String(gun.get("name", p.weapon)), mag]
		var status: String = scene.status_of(p)
		c.status.text = status
		c.status.add_theme_color_override("font_color", STATUS_COLOR.get(status, Hud.INK2))
		c.panel.modulate = Color(1, 1, 1, 0.55) if p.dead else Color.WHITE


func _refresh_log(run) -> void:
	while _log_seen < run.log.size():
		_log.append({"text": String(run.log[_log_seen]), "t": scene.clock})
		_log_seen += 1
	if _log.size() > LOG_LINES:
		_log = _log.slice(_log.size() - LOG_LINES)
	var any := false
	for i in LOG_LINES:
		var l: Label = log_labels[i]
		if i < _log.size():
			var age: float = scene.clock - float(_log[i].t)
			var a := clampf(1.0 - (age - LOG_HOLD) / LOG_FADE, 0.0, 1.0)
			l.text = String(_log[i].text)
			l.modulate.a = a
			l.visible = a > 0.0
			any = any or a > 0.0
		else:
			l.visible = false
	log_panel.visible = any


# ------------------------------------------------------------- banner etc --

func show_banner(title: String, sub: String) -> void:
	banner_title.text = title.to_upper()
	banner_sub.text = sub
	banner_sub.visible = sub != ""
	_layout()
	if banner_tween != null:
		banner_tween.kill()
	banner_tween = create_tween() if is_inside_tree() else null
	if banner_tween == null:
		banner.modulate.a = 1.0
		return
	if hud._calm():
		banner.modulate.a = 1.0
		banner_tween.tween_interval(BANNER_HOLD + BANNER_FADE)
		banner_tween.tween_callback(func(): banner.modulate.a = 0.0)
		return
	banner.modulate.a = 0.0
	banner_tween.tween_property(banner, "modulate:a", 1.0, BANNER_FADE)
	banner_tween.tween_interval(BANNER_HOLD)
	banner_tween.tween_property(banner, "modulate:a", 0.0, BANNER_FADE)


func toast(text: String, level: String = "info") -> void:
	if text.strip_edges() == "":
		return
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", Hud.TOAST_COLOR.get(level, Hud.INK))
	toast_panel.visible = true
	toast_panel.modulate.a = 1.0
	_layout()
	if toast_tween != null:
		toast_tween.kill()
	toast_tween = create_tween() if is_inside_tree() else null
	if toast_tween == null:
		return
	toast_tween.tween_interval(TOAST_HOLD - TOAST_FADE)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, TOAST_FADE)
	toast_tween.tween_callback(func(): toast_panel.visible = false)


# --------------------------------------------------------------- end card --

## Names of the squad for a list of ids, "Dez, Marcus", or "Nobody".
func _names_of(ids: Array) -> String:
	var out: Array = []
	for id in ids:
		for p in scene.run.squad:
			if String(p.id) == String(id):
				out.append(p.first)
	return ", ".join(out) if not out.is_empty() else "Nobody"


## The place's name as it reads in a sentence: "The pharmacy" is "the pharmacy", "Pell's bakery" stays.
func place_phrase() -> String:
	var place := String(scene.site.get("name", "the place"))
	return "the " + place.trim_prefix("The ") if place.begins_with("The ") else place


## The card's title and the line under it for a result.
func end_words(result: Dictionary) -> Array:
	var lost: Array = result.get("lost", [])
	if lost.size() >= scene.run.squad.size():
		return ["Nobody came back", "The squad was lost at %s." % place_phrase()]
	var sub := "Everyone came home."
	if not lost.is_empty():
		sub = "%s did not come back." % _names_of(lost)
	elif not result.get("hurt", {}).is_empty():
		sub = "%s came back hurt." % _names_of(result.hurt.keys())
	return ["Back from %s" % place_phrase(), sub]


func show_end(result: Dictionary) -> void:
	if end_card != null:
		end_card.queue_free()
	end_card = Control.new()
	end_card.name = "EndCard"
	end_card.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(end_card)
	end_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_card.set_meta("modal", true)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.035, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	end_card.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_card.add_child(center)
	var style: StyleBox = hud._paper_style()
	if style is StyleBoxFlat:
		style.content_margin_left = 28
		style.content_margin_right = 28
		style.content_margin_top = 22
		style.content_margin_bottom = 24
	end_panel = hud._panel(style)
	center.add_child(end_panel)
	var col: VBoxContainer = hud._vbox(10)
	end_panel.add_child(col)
	var head: Label = hud._caps("Raid report", Hud.PAPER_INK3)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var words := end_words(result)
	end_title = hud._label(String(words[0]), Fonts.cond(700), 36, Hud.PAPER_INK)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_title.custom_minimum_size.x = minf(END_W, maxf(280.0, root.size.x - 80.0))
	col.add_child(end_title)
	end_sub = hud._label(String(words[1]), Fonts.sans(400), 15, Hud.PAPER_INK2)
	end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(end_sub)
	var lines: VBoxContainer = hud._vbox(0)
	lines.add_child(_rule(Hud.PAPER_INK))
	lines.add_child(_end_row("loot", "Brought home", _loot_value(result)))
	lines.add_child(_end_row("hurt", "Hurt (bitten)", _text_value(_names_of(result.get("hurt", {}).keys()) if not result.get("hurt", {}).is_empty() else "Nobody")))
	lines.add_child(_end_row("lost", "Lost", _text_value(_names_of(result.get("lost", [])) if not result.get("lost", []).is_empty() else "Nobody")))
	lines.add_child(_end_row("place", "The place", _text_value("Cleared of the dead" if bool(result.get("clear", false)) else "The dead still hold it")))
	if scene.has_survivor or bool(result.get("rescue", false)):
		lines.add_child(_end_row("rescue", "Someone alive", _text_value("Found, and coming home with you" if bool(result.get("rescue", false)) else "Not found")))
	lines.add_child(_end_row("ammo", "Ammo used", _text_value(_ammo_text(float(result.get("ammo_used", 0.0))))))
	col.add_child(lines)
	var buttons: HBoxContainer = hud._hbox(8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	end_button = hud._button("Go home", true, true)
	end_button.pressed.connect(func(): scene.go_home())
	buttons.add_child(end_button)
	var key: PanelContainer = hud._kbd("Enter")
	buttons.add_child(key)
	col.add_child(buttons)
	for c in [banner, toast_panel, legend_panel, retreat_panel, ask_panel]:
		c.visible = false


func _ammo_text(used: float) -> String:
	if used <= 0.0:
		return "None"
	return "%d" % maxi(1, roundi(used))


func _rule(color: Color = Color(0, 0, 0, 0)) -> Control:
	var line := ColorRect.new()
	line.color = color if color.a > 0.0 else Hud.PAPER_LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _text_value(text: String) -> Label:
	var l: Label = hud._label(text, Fonts.cond(700), 19, Hud.PAPER_INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 230.0
	return l


func _loot_value(result: Dictionary) -> Control:
	var loot: Dictionary = result.get("loot", {})
	if loot.is_empty():
		return _text_value("Nothing")
	var row: HBoxContainer = hud._hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	var stocks: Array = []
	for s in STOCK_ORDER:
		if loot.has(s):
			stocks.append(s)
	for s in loot:
		if not stocks.has(String(s)):
			stocks.append(String(s))
	for s in stocks:
		var item: HBoxContainer = hud._hbox(4)
		if hud.icons.has(s):
			var ic: TextureRect = hud._icon(String(s), 20, Hud.PAPER_INK)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			item.add_child(ic)
		else:
			item.add_child(hud._label(String(STOCK_NAMES.get(s, String(s).capitalize())), Fonts.sans(600), 13, Hud.PAPER_INK2))
		item.add_child(hud._label(str(int(loot[s])), Fonts.cond(700), 22, Hud.PAPER_INK))
		item.tooltip_text = String(STOCK_NAMES.get(s, String(s).capitalize()))
		row.add_child(item)
	return row


func _end_row(key: String, caption: String, value: Control) -> Control:
	var box: VBoxContainer = hud._vbox(0)
	var row: HBoxContainer = hud._hbox(10)
	row.custom_minimum_size.y = 34.0
	var cap: Label = hud._caps(caption, Hud.PAPER_INK2)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.custom_minimum_size.x = 130.0
	row.add_child(cap)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	box.add_child(row)
	box.add_child(_rule())
	end_rows[key] = value
	return box
