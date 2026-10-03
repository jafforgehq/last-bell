## The raid's HUD (round 14, R14.3; the radio, round 17, S1.6b): its own CanvasLayer over the raid scene (raid_scene.gd), in
## the noticeboard style of the rest of the game. It borrows the game HUD's helpers (`_style`, `_panel`, `_label`, `_button`,
## `_kbd`, `_icon`, the paper page...) so that it looks like it and changes with the theme.
##
##   top        the place's name and a line about what to do (left), the squad's cards (middle: portrait, name, health, weapon
##              and magazine, what they are doing: a stance word; "YOU" on the one you lead; a click asks them over the radio),
##              the bags (right: what is in them by stock, "n of m") - in a narrow window the cards drop to a row of their own
##   right      the radio: the contacts (the squad above; the people at the base: chips), News and Alarm and "All back", and
##              for the selected contact the verbs of radio_verbs.gd. The News log (news_panel.gd) takes the verbs' place in a
##              narrow window, and stands beside the radio in a wide one
##   bottom     the log of what happened (the last four lines, fading), the legend of the controls (fades), the ammunition
##              (the magazine and the stock, a reload bar), the call card (call_card.gd: the oldest call of the base that waits
##              for an answer: it never pauses anything) and the base's clock (its day and hour, dusk and night) and how it
##              stands (walls holding, under attack, alarm)
##   over all   a banner ("They heard that", "Dez leads now"), a toast for an order that cannot be given, the road's overlay
##              ("Driving to the pharmacy...": the progress, the clock of the base and the news as it comes) and the report
##              (a paper page: what came home, who is hurt or lost, the place, the ammo used, the news, and one button)
##
## Everything is laid out in `_layout`, from the panels' own sizes, so that nothing overlaps at any width from 700 up.
## Nothing is set under Fonts.MIN_PX (the label factory raises it).
extends CanvasLayer

const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioVerbs := preload("res://scripts/ui/radio_verbs.gd")
const NewsPanel := preload("res://scripts/ui/news_panel.gd")
const CallCard := preload("res://scripts/ui/call_card.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")

const PAD := 12.0
const GAP := 10.0
const CARD_MIN_W := 156.0
const CARD_MAX_W := 196.0
const CARD_H := 66.0
const PORTRAIT := 46.0
const LOG_LINES := 4
const LOG_W := 380.0
const LOG_W_NARROW := 250.0
const LOG_HOLD := 12.0
const LOG_FADE := 3.0
## How long the legend shows when the raid begins, and how long it takes to fade.
const LEGEND_HOLD := 14.0
const LEGEND_FADE := 2.0
const BANNER_HOLD := 3.0
const BANNER_FADE := 0.5
const TOAST_HOLD := 2.4
const TOAST_FADE := 0.4
const PLACE_W := 290.0
const END_W := 540.0
## The radio's column: the panel is this wide, the News log as wide beside it (a wide window) or in its place (a narrow one).
const RADIO_W := 280.0
const WIDE_W := 1000.0
## A window shorter than this has the radio in its compact form (the verbs in one row, the people at the base behind a button).
const COMPACT_H := 680.0
const WEAPON_W := 230.0
const CALL_W := 300.0
const CALL_W_MIN := 230.0
const BASE_W := 250.0
const ROAD_W := 460.0
## Amber for the report's paper (the chalk amber is for the dark panels): 5.7 to 1 on the paper.
const PAPER_AMBER := Color("#8a4a00")
const MAX_CHIPS := 14
const STOCK_ORDER := ["food", "water", "scrap", "ammo", "meds", "fuel"]
const STOCK_NAMES := {"food": "Food", "water": "Water", "scrap": "Scrap", "ammo": "Ammo", "meds": "Medicine", "fuel": "Fuel"}
const LEGEND := [
	[["W", "A", "S", "D"], "walk"], [["Click"], "shoot"], [["R"], "reload"], [["F"], "melee"], [["E"], "search"],
	[["Space"], "pause"], [["T"], "news"], [["Scroll"], "zoom"],
]
const STATUS_COLOR := {
	"Down": Hud.DANGER_TEXT, "Lost": Hud.DANGER_TEXT, "Searching": Hud.ACCENT, "Helping": Hud.INFO, "Going to search": Hud.INK2,
	"Going to help": Hud.INK2, "Reloading": Hud.WARN, "Fighting": Hud.WARN, "You": Hud.ACCENT, "Following": Hud.INK2, "Holding": Hud.INFO,
	"Covering": Hud.INFO, "Heading back": Hud.OK,
}
## How the base reads, by the key `PlaceFlow.base_state` gives.
const BASE_COLOR := {"ok": Hud.OK, "night": Hud.INFO, "attack": Hud.DANGER_TEXT, "alarm": Hud.WARN, "fallen": Hud.DANGER_TEXT}

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
var cards: Array = []    # {"p", "panel", "pic", "name", "you", "hp", "weapon", "status"}
var card_w := CARD_MIN_W

## The radio: its panel, the buttons of its header, the people at the base (chips), the contact asked and the verbs.
var radio_panel: PanelContainer
var news_button: Button
var news_dot: Control
var alarm_button: Button
var back_button: Button
var base_flow: HFlowContainer
var base_caption: Label
var base_button: Button
var base_open := false
var radio_caps: Label
var chips_box_radio: VBoxContainer
var contact_box: VBoxContainer
var base_chips: Dictionary = {}    # person id -> Button
var contact_label: Label
var contact_hint: Label
var radio_verbs
var news_panel
var news_open := false
var call_card

## The foot: the log and the legend (left), the ammunition (middle), the base (right).
var log_panel: PanelContainer
var log_labels: Array = []
var legend_panel: PanelContainer
var weapon_panel: PanelContainer
var weapon_label: Label
var stock_label: Label
var mag_bar
var base_panel: PanelContainer
var sky_dot: Control
var clock_label: Label
var mood_label: Label
var base_label: Label

var banner: PanelContainer
var banner_title: Label
var banner_sub: Label
var banner_tween: Tween
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var end_card: Control
var end_button: Button
var end_panel: PanelContainer
var end_title: Label
var end_sub: Label
var end_rows := {}       # "loot", "hurt", "lost", "place", "rescue", "ammo", "news" -> the value's Control

## The road's overlay.
var road_panel: Control
var road_title_label: Label
var road_sub_label: Label
var road_bar
var road_clock_label: Label
var road_mood_label: Label
var road_news_box: VBoxContainer
var road_news: Array = []
var road_hint_label: Label
## Who stayed behind and why: one amber line each, under the progress bar (the flow's `refusals`).
var road_refusal_box: VBoxContainer
var road_refusals: Array = []

## What the refresh wants shown of the two things that may be left out for want of room (the layout decides if they fit).
var _log_wanted := false
var _legend_wanted := false
var _compact := false
var _log_seen := 0
var _log: Array = []     # [{"text", "t"}]
var _sig := ""
var _layout_w := -1.0
var _news_unread_seen := 0


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
	_build_radio()
	_build_log()
	_build_legend()
	_build_weapon()
	_build_base()
	_build_call_card()
	_build_banner()
	_build_toast()
	_build_road()
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


func _make_card(p, _index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(card_w, CARD_H)
	panel.add_theme_stylebox_override("panel", _card_box(false))
	panel.tooltip_text = "%s, %s. Click to ask them something over the radio" % [p.name, String(p.def.role).to_lower()]
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
	var you: PanelContainer = _you_chip()
	you.visible = false
	head.add_child(you)
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
	return {"p": p, "panel": panel, "pic": pic, "name": nm, "you": you, "hp": fill, "weapon": weapon, "status": status, "selected": false}


## A small gold stamp that says YOU (on the card of the one you lead).
func _you_chip() -> PanelContainer:
	var f := StyleBoxFlat.new()
	f.bg_color = Hud.ACCENT
	f.set_corner_radius_all(4)
	f.content_margin_left = 5
	f.content_margin_right = 5
	f.content_margin_top = 0
	f.content_margin_bottom = 1
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", f)
	var l: Label = hud._label("YOU", Fonts.cond(700, 1), 12, Hud.ACCENT_INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(l)
	return chip


## A click on a card asks that person (the radio's verbs for them); the one you lead has nothing to be asked.
func _on_card_input(ev: InputEvent, p) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if scene.phase != "place" or scene.ended or p == scene.leader() or p.dead:
			return
		pick_contact("squad", p)


## Selects a contact (the News log makes room for the verbs).
func pick_contact(kind: String, p) -> void:
	if news_open and not _news_beside():
		open_news(false)
	scene.select_contact(kind, p)


# ----------------------------------------------------------------- radio --

func _build_radio() -> void:
	radio_panel = hud._panel()
	var col: VBoxContainer = hud._vbox(6)
	var head: HBoxContainer = hud._hbox(5)
	radio_caps = hud._caps("Radio")
	head.add_child(radio_caps)
	head.add_child(hud._spacer())
	news_button = RadioKit.small_button(hud, "News", 26.0, 13)
	news_button.tooltip_text = "News: what the radio heard, and the calls that wait for your answer\nKey: T"
	news_button.pressed.connect(func(): open_news(not news_open))
	news_dot = Control.new()
	news_dot.custom_minimum_size = Vector2(9, 9)
	news_dot.size = Vector2(9, 9)
	news_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	news_dot.draw.connect(func(): news_dot.draw_circle(Vector2(4.5, 4.5), 4.0, Hud.ACCENT))
	news_dot.visible = false
	news_button.add_child(news_dot)
	head.add_child(news_button)
	alarm_button = RadioKit.small_button(hud, "Alarm", 26.0, 13)
	alarm_button.pressed.connect(func(): scene.toggle_alarm())
	head.add_child(alarm_button)
	back_button = RadioKit.small_button(hud, "All back", 26.0, 13)
	back_button.tooltip_text = "Ask everyone with you to go back to the exit"
	back_button.pressed.connect(call_all_back)
	head.add_child(back_button)
	base_button = RadioKit.small_button(hud, "Base", 26.0, 13)
	base_button.tooltip_text = "The people at the base: ask them to go back to what they were doing, or to the walls"
	base_button.pressed.connect(func(): open_base(not base_open))
	base_button.visible = false
	head.add_child(base_button)
	col.add_child(head)
	chips_box_radio = hud._vbox(4)
	base_caption = hud._caps("At the base")
	chips_box_radio.add_child(base_caption)
	base_flow = HFlowContainer.new()
	base_flow.add_theme_constant_override("h_separation", 4)
	base_flow.add_theme_constant_override("v_separation", 4)
	base_flow.custom_minimum_size.x = RADIO_W - 24.0
	base_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips_box_radio.add_child(base_flow)
	col.add_child(chips_box_radio)
	contact_box = hud._vbox(4)
	contact_label = hud._label("", Fonts.cond(700), 16, Hud.INK)
	contact_label.clip_text = true
	contact_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	contact_box.add_child(contact_label)
	contact_hint = hud._label("Click a card or a name to ask them something", Fonts.sans(400), 12, Hud.INK3)
	contact_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contact_hint.custom_minimum_size.x = RADIO_W - 24.0
	contact_box.add_child(contact_hint)
	radio_verbs = RadioVerbs.new()
	contact_box.add_child(radio_verbs)
	col.add_child(contact_box)
	radio_verbs.setup(hud, func(): return scene.radio_of(String(scene.contact.get("kind", "squad"))), {
		"place": true,
		"search_at": func():
			var c: Dictionary = scene.search_target()
			return Vector2(c.pos) if not c.is_empty() else null,
		"hold_at": func():
			var lead = scene.leader()
			return Vector2(lead.x, lead.y) if lead != null else null,
		"is_you": func(p): return p == scene.leader(),
	})
	radio_verbs.set_form(3, false)
	radio_verbs.requested.connect(_on_requested)
	radio_panel.add_child(col)
	radio_panel.custom_minimum_size.x = RADIO_W
	_put(radio_panel)
	news_panel = NewsPanel.new()
	_put(news_panel)
	news_panel.setup(hud, func(): return scene.colony_radio(), {"speed_getter": func(): return PlaceFlow.PLACE_PACE})
	news_panel.visible = false


func _on_requested(_who, verb: String, result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		return
	# (a refusal's reason is in the panel's answer line; the squad's "search that" that found nothing to search says so here)
	if verb == "search" and String(result.get("why", "")) != "" and scene.contact.get("kind", "") == "squad":
		toast(String(result.why), "warn")
	refresh()


## Everyone with you is asked to go back to the exit.
func call_all_back() -> void:
	var asked := 0
	var yes := 0
	for p in scene.squad_contacts():
		if p.downed:
			continue
		asked += 1
		if bool(scene.squad_request(p, "back").get("ok", false)):
			yes += 1
	if asked == 0:
		toast("Nobody is with you", "warn")
	elif yes == asked:
		toast("Everyone is heading back to the exit")
	else:
		toast("%d of %d are heading back to the exit" % [yes, asked], "warn")
	refresh()


## Opens or shuts the News log (T).
func open_news(on: bool) -> void:
	news_open = on
	news_panel.visible = on
	if on:
		news_panel.refresh()
	else:
		news_panel.mark_read()
	refresh()
	_layout()


func toggle_news() -> void:
	open_news(not news_open)


## In the compact radio the people at the base are behind the "Base" button.
func open_base(on: bool) -> void:
	base_open = on
	refresh()
	_layout()


## The radio's form for this window: compact (a short window) keeps the verbs in one row of short names and the people at the
## base behind a button; the full form lists them and has the verbs in two rows.
func _apply_modes(h: float) -> void:
	var compact: bool = h < COMPACT_H
	if compact == _compact and radio_verbs.columns == (6 if compact else 3):
		return
	_compact = compact
	radio_verbs.set_form(6 if compact else 3, compact)
	radio_caps.visible = not compact
	base_button.visible = compact


## Whether the News log takes the verbs' place (a narrow window) rather than standing beside the radio.
func _news_replaces() -> bool:
	return news_open and not _news_beside()


## What a contact said (the staging and the tests use it: the verbs panel keeps the last answer for the person asked).
func say(who, verb: String, result: Dictionary) -> void:
	if radio_verbs.contact == who:
		radio_verbs.last = {"who": String(who.id), "verb": verb, "ok": bool(result.get("ok", false)), "line": String(result.get("line", "")), "why": String(result.get("why", "")), "hard": false, "tone": String(result.get("tone", ""))}
		radio_verbs.refresh()


## Whether the News log stands beside the radio (a wide window) rather than in the verbs' place.
func _news_beside() -> bool:
	return root != null and root.size.x >= WIDE_W


func _refresh_radio() -> void:
	var alarm_on: bool = bool(scene.colony_radio().alarm_on) if scene.colony_radio() != null else false
	alarm_button.text = "Stand down" if alarm_on else "Alarm"
	alarm_button.tooltip_text = "Stand down: end the call to arms and send everyone back to work" if alarm_on else "Call to arms: everyone at the base to their posts now, by day too, until you stand down or the dawn comes"
	alarm_button.disabled = scene.colony_radio() == null or scene.phase != "place"
	back_button.disabled = scene.phase != "place" or scene.ended
	news_button.disabled = scene.colony_radio() == null
	# the people at the base are chips: one for each who is not away (made when they are first seen, the rest hidden)
	var people: Array = scene.base_contacts()
	var seen := {}
	for p in people:
		seen[String(p.id)] = true
		if not base_chips.has(String(p.id)):
			var b: Button = RadioKit.small_button(hud, String(p.first), 26.0, 13)
			b.pressed.connect(func(): pick_contact("base", p))
			base_flow.add_child(b)
			base_chips[String(p.id)] = b
	var shown := 0
	for id in base_chips:
		var b2: Button = base_chips[id]
		var show: bool = seen.has(id) and shown < MAX_CHIPS
		b2.visible = show
		if show:
			shown += 1
			var p2 = _colony_of(id)
			var chosen: bool = p2 != null and scene.is_selected(p2) and scene.contact.get("kind", "") == "base"
			b2.modulate = Color(1.0, 0.92, 0.6) if chosen else Color.WHITE
	var chips_on: bool = shown > 0 and (not _compact or base_open) and not _news_replaces()
	chips_box_radio.visible = chips_on
	contact_box.visible = not _news_replaces()
	base_button.modulate = Color(1.0, 0.92, 0.6) if base_open else Color.WHITE
	var c: Dictionary = scene.contact
	if c.is_empty() or c.p == null or c.p.dead:
		contact_label.text = ""
		contact_label.visible = false
		contact_hint.visible = scene.phase == "place" and not scene.ended
		radio_verbs.set_contact(null)
	else:
		var p3 = c.p
		contact_label.visible = true
		contact_hint.visible = false
		var where := "with you" if String(c.kind) == "squad" else "at the base"
		contact_label.text = "%s, %s" % [String(p3.first), where]
		radio_verbs.set_contact(p3)
		radio_verbs.refresh()
	# the News log's dot: something the player has not seen since it was last shut
	var unread: int = news_panel.unread() if not news_open else 0
	news_dot.visible = unread > 0
	news_dot.position = Vector2(news_button.size.x - 11.0, 2.0)
	if news_open:
		news_panel.refresh()
		news_panel.mark_read()


func _colony_of(id: String):
	return scene.colony_person(id)


# ------------------------------------------------------------------ the foot --

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


## The ammunition of the one you lead: the weapon, the magazine and what is in the stores, and a bar that is the magazine, or
## the reload while it goes.
func _build_weapon() -> void:
	weapon_panel = hud._panel()
	weapon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: VBoxContainer = hud._vbox(3)
	weapon_label = hud._label("", Fonts.cond(700), 20, Hud.INK)
	col.add_child(weapon_label)
	mag_bar = hud.Bar.new()
	mag_bar.custom_minimum_size = Vector2(WEAPON_W - 28.0, 6)
	mag_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mag_bar.groove = hud.frame("bar_track")
	col.add_child(mag_bar)
	stock_label = hud._label("", Fonts.sans(400), 13, Hud.INK2)
	col.add_child(stock_label)
	weapon_panel.add_child(col)
	_put(weapon_panel)


## The base's clock and how it stands, bottom right: the day and the hour of the colony (the place is lit by it), its mood
## (day, dusk, night, dawn) and "Base: walls holding".
func _build_base() -> void:
	base_panel = hud._panel()
	base_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: VBoxContainer = hud._vbox(3)
	var head: HBoxContainer = hud._hbox(8)
	sky_dot = Control.new()
	sky_dot.custom_minimum_size = Vector2(16, 16)
	sky_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sky_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_dot.draw.connect(_draw_sky)
	head.add_child(sky_dot)
	clock_label = hud._label("", Fonts.cond(700), 20, Hud.INK)
	head.add_child(clock_label)
	head.add_child(hud._spacer())
	mood_label = hud._caps("", Hud.INK2)
	head.add_child(mood_label)
	col.add_child(head)
	base_label = hud._label("", Fonts.sans(600), 13, Hud.INK)
	base_label.custom_minimum_size.x = BASE_W - 28.0
	base_label.clip_text = true
	base_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(base_label)
	base_panel.add_child(col)
	base_panel.custom_minimum_size.x = BASE_W
	_put(base_panel)


## The sun or the moon of the base's hour.
func _draw_sky() -> void:
	var dark: float = float(scene.light_now().dark)
	var c := Vector2(8, 8)
	if dark > 0.3:
		sky_dot.draw_circle(c, 6.5, Color("#cfd8e8"))
		sky_dot.draw_circle(c + Vector2(3, -2), 5.5, Color("#16221f"))
	else:
		sky_dot.draw_circle(c, 6.0, Color("#f0c24a"))


func _build_call_card() -> void:
	call_card = CallCard.new()
	_put(call_card)
	call_card.setup(hud, func(): return scene.colony_radio(), {"speed_getter": func(): return PlaceFlow.PLACE_PACE})
	call_card.custom_minimum_size.x = CALL_W


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
	banner.visible = false
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


# ------------------------------------------------------------------- the road --

## The overlay of the road: a full window, the title, how far the road is, the clock of the base and the news as it comes. It
## takes no input (nothing skips it) and stays until the road is done.
func _build_road() -> void:
	road_panel = Control.new()
	road_panel.name = "Road"
	road_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(road_panel)
	road_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color("#0b1411")
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	road_panel.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	road_panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col: VBoxContainer = hud._vbox(10)
	col.custom_minimum_size.x = ROAD_W
	center.add_child(col)
	var caps: Label = hud._caps("On the road", Hud.INK3)
	caps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(caps)
	road_title_label = hud._label("", Fonts.cond(700, 2), 40, Hud.INK)
	road_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	road_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(road_title_label)
	road_sub_label = hud._label("", Fonts.sans(400), 14, Hud.INK2)
	road_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	road_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(road_sub_label)
	road_bar = hud.Bar.new()
	road_bar.custom_minimum_size = Vector2(ROAD_W, 8)
	road_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	road_bar.groove = hud.frame("bar_track")
	road_bar.color = Hud.ACCENT
	col.add_child(road_bar)
	road_refusal_box = hud._vbox(2)
	road_refusal_box.custom_minimum_size.x = ROAD_W
	col.add_child(road_refusal_box)
	var clock_row: HBoxContainer = hud._hbox(10)
	clock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	road_clock_label = hud._label("", Fonts.cond(700), 26, Hud.INK)
	clock_row.add_child(road_clock_label)
	road_mood_label = hud._caps("", Hud.INK2)
	clock_row.add_child(road_mood_label)
	col.add_child(clock_row)
	road_news_box = hud._vbox(3)
	road_news_box.custom_minimum_size = Vector2(ROAD_W, 96)
	col.add_child(road_news_box)
	road_hint_label = hud._label("The base goes on without you.", Fonts.sans(400), 13, Hud.INK3)
	road_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(road_hint_label)
	road_panel.visible = false


## The road's overlay comes up with `title` ("Driving to The pharmacy...") for the flow `flow` (place_flow.gd).
func show_road(title: String, flow) -> void:
	road_news = []
	for c in road_news_box.get_children():
		c.queue_free()
	road_title_label.text = title
	var names: Array = []
	for p in flow.going:
		names.append(String(p.first))
	road_sub_label.text = ", ".join(names) if not names.is_empty() else ""
	_show_refusals(flow.refusals)
	road_panel.visible = true
	for c in [place_panel, loot_panel, cards_grid, radio_panel, news_panel, log_panel, legend_panel, weapon_panel, base_panel, call_card, banner, toast_panel]:
		c.visible = false
	update_road(flow)


func hide_road() -> void:
	road_panel.visible = false
	refresh()


## The people who were asked and stayed (or did not fit), one line each under the bar, in amber: a refusal is never left unseen.
func _show_refusals(lines: Array) -> void:
	road_refusals = []
	for c in road_refusal_box.get_children():
		road_refusal_box.remove_child(c)
		c.queue_free()
	for line in lines:
		road_refusals.append(String(line))
		var l: Label = hud._label(String(line), Fonts.sans(600), 14, Hud.WARN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = ROAD_W
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		road_refusal_box.add_child(l)


## One frame of the road: the bar, the base's clock and the news that has come in since the trip began (the last few lines).
func update_road(flow) -> void:
	road_bar.value = flow.road_progress()
	road_bar.queue_redraw()
	var cs = scene.colony()
	if cs != null:
		road_clock_label.text = PlaceFlow.clock_text(cs)
		road_mood_label.text = _mood_word(cs).to_upper()
	for line in flow.news_lines(PlaceFlow.MAX_NEWS_LINES):
		_add_road_line(String(line))


## A line of news on the road (one that is already there is not added again).
func road_note(text: String) -> void:
	_add_road_line(text)


func _add_road_line(text: String) -> void:
	if road_news.has(text):
		return
	road_news.append(text)
	var l: Label = hud._label(text, Fonts.sans(600), 14, Hud.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = ROAD_W
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	road_news_box.add_child(l)
	while road_news_box.get_child_count() > PlaceFlow.MAX_NEWS_LINES:
		road_news_box.get_child(0).queue_free()
		road_news_box.remove_child(road_news_box.get_child(0))


static func _mood_word(cs) -> String:
	match String(cs.phase):
		"dusk":
			return "Dusk"
		"night":
			return "Night"
		"dawn":
			return "Dawn"
	return "Day"


# ----------------------------------------------------------------- layout --

## Where everything goes, from the panels' own sizes. The squad's cards sit between the place and the bags when all of them
## fit there at their narrowest, and otherwise in a row (or rows) of their own under both. The radio is a column at the right
## under them (the News log beside it in a wide window, in the verbs' place in a narrow one) and the base's clock is at the
## foot of that column. A WIDE window (WIDE_W) keeps the log and the legend at the bottom left, the ammunition in the middle
## of the foot with the call card above it, the banner at the top of the middle and the toast over the call card; a narrow
## one has one column at the left (the ammunition at the foot, the call card above it, then the log and the legend, whichever
## of those two fit under the banner and the toast, which hang from the cards' row while they are up). Nothing overlaps.
func _layout() -> void:
	if root == null or place_panel == null:
		return
	var w: float = root.size.x
	var h: float = root.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var wide := w >= WIDE_W
	_apply_modes(h)
	var ps := place_panel.get_combined_minimum_size()
	var ls := loot_panel.get_combined_minimum_size()
	_place(place_panel, Vector2(PAD, PAD))
	_place(loot_panel, Vector2(w - PAD - ls.x, PAD))
	var n := cards.size()
	var between := w - 2.0 * PAD - ps.x - ls.x - 2.0 * GAP
	var plan := plan_cards(n, between)
	var top_end := PAD + maxf(ps.y, ls.y)
	var right_top := PAD + ls.y + 8.0
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
		right_top = top_end + 8.0
	# the right column: the radio under the bags (or the cards), the base's clock at the foot
	var bas := base_panel.get_combined_minimum_size()
	var base_at := Vector2(w - PAD - bas.x, h - PAD - bas.y)
	_place(base_panel, base_at)
	var rs := radio_panel.get_combined_minimum_size()
	var radio_x := w - PAD - maxf(rs.x, RADIO_W)
	_place(radio_panel, Vector2(radio_x, right_top))
	var room_below := maxf(0.0, base_at.y - 8.0 - right_top)
	var news_left := radio_x    # (what the middle of the window has to keep clear of at the top)
	if news_panel.visible:
		news_panel.custom_minimum_size.x = RADIO_W
		if wide:
			news_panel.fit(minf(room_below, 420.0))
			var nss: Vector2 = news_panel.get_combined_minimum_size()
			_place(news_panel, Vector2(radio_x - GAP - nss.x, right_top))
			news_left = radio_x - GAP - nss.x
		else:
			# it stands in the verbs' place: under the radio's header, down to the base's clock
			var head_h := radio_panel.get_combined_minimum_size().y
			var below := right_top + head_h + 6.0
			news_panel.fit(maxf(120.0, base_at.y - 8.0 - below))
			_place(news_panel, Vector2(radio_x, below))
	_fit_banner((news_left - GAP - PAD) if wide else maxf(160.0, radio_x - GAP - PAD))
	_fit_toast((news_left - GAP - PAD) if wide else maxf(160.0, radio_x - GAP - PAD))
	var bs := banner.get_combined_minimum_size()
	var ts := toast_panel.get_combined_minimum_size()
	var wes := weapon_panel.get_combined_minimum_size()
	var cc: Vector2 = call_card.get_combined_minimum_size()
	if wide:
		# the left column: the log at the foot, the legend over it (both as wide as the log)
		var left_w := LOG_W
		for l in log_labels:
			l.custom_minimum_size.x = left_w
		legend_panel.custom_minimum_size.x = left_w
		var foot := h - PAD
		log_panel.visible = _log_wanted
		if log_panel.visible:
			var logs := log_panel.get_combined_minimum_size()
			_place(log_panel, Vector2(PAD, foot - logs.y))
			foot -= logs.y + 6.0
		legend_panel.visible = _legend_wanted
		if legend_panel.visible:
			var legs := legend_panel.get_combined_minimum_size()
			_place(legend_panel, Vector2(PAD, foot - legs.y))
		# the middle of the foot: the ammunition, the call card over it, the toast over that
		var mid_l := PAD + left_w + GAP
		var mid_r := base_at.x - GAP
		var mid_c := (mid_l + mid_r) / 2.0
		_place(weapon_panel, Vector2(mid_c - wes.x / 2.0, h - PAD - wes.y))
		var up := h - PAD - wes.y - 6.0
		call_card.custom_minimum_size.x = minf(CALL_W, mid_r - mid_l)
		cc = call_card.get_combined_minimum_size()
		if call_card.visible:
			_place(call_card, Vector2(mid_c - cc.x / 2.0, up - cc.y))
			up -= cc.y + 6.0
		_place(toast_panel, Vector2(mid_c - ts.x / 2.0, up - ts.y))
		# the banner: the top of the middle, clear of the radio and of the News log
		var top_l := PAD
		var top_c := (top_l + news_left - GAP) / 2.0
		_place(banner, Vector2(top_c - bs.x / 2.0, top_end + 8.0))
	else:
		# one column at the left, as wide as the room between it and the radio's
		var left_end := radio_x - GAP
		var left_w2 := maxf(120.0, left_end - PAD)
		var foot := h - PAD
		_place(weapon_panel, Vector2(PAD, foot - wes.y))
		foot -= wes.y + 6.0
		call_card.custom_minimum_size.x = clampf(left_w2, CALL_W_MIN, CALL_W)
		cc = call_card.get_combined_minimum_size()
		if call_card.visible:
			_place(call_card, Vector2(PAD, foot - cc.y))
			foot -= cc.y + 6.0
		# the banner and the toast hang from the cards' row while they are up: the log and the legend need the room under them
		var ceiling := top_end + 8.0
		if banner.visible:
			_place(banner, Vector2(PAD, ceiling))
			ceiling += bs.y + 6.0
		if toast_panel.visible:
			_place(toast_panel, Vector2(PAD, ceiling))
			ceiling += ts.y + 6.0
		log_panel.visible = false
		legend_panel.visible = false
		var log_w := minf(LOG_W, left_w2)
		for l in log_labels:
			l.custom_minimum_size.x = log_w
		log_panel.custom_minimum_size.x = 0.0
		if _log_wanted:
			var logs2 := log_panel.get_combined_minimum_size()
			if foot - logs2.y >= ceiling:
				log_panel.visible = true
				_place(log_panel, Vector2(PAD, foot - logs2.y))
				foot -= logs2.y + 6.0
		if _legend_wanted:
			legend_panel.custom_minimum_size.x = left_w2
			var legs2 := legend_panel.get_combined_minimum_size()
			if foot - legs2.y >= ceiling:
				legend_panel.visible = true
				_place(legend_panel, Vector2(PAD, foot - legs2.y))
	_layout_w = w
	_sig = _signature()


## The banner is as wide as its words, but never wider than the room: its lines wrap.
func _fit_banner(max_w: float) -> void:
	var room := maxf(80.0, max_w - 52.0)
	for l in [banner_title, banner_sub]:
		var f: Font = l.get_theme_font("font")
		var size: int = l.get_theme_font_size("font_size")
		var natural := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 4.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = minf(natural, room)


## The toast likewise.
func _fit_toast(max_w: float) -> void:
	var f: Font = toast_label.get_theme_font("font")
	var size: int = toast_label.get_theme_font_size("font_size")
	var natural := f.get_string_size(toast_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 4.0
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.custom_minimum_size.x = minf(natural, maxf(80.0, max_w - 26.0))


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
		weapon_panel.get_combined_minimum_size(), base_panel.get_combined_minimum_size(), banner.get_combined_minimum_size(),
		toast_panel.get_combined_minimum_size(), radio_panel.get_combined_minimum_size(), news_panel.visible, news_panel.get_combined_minimum_size(),
		call_card.visible, call_card.get_combined_minimum_size(), banner.visible, toast_panel.visible, _log_wanted, _legend_wanted]
	return str(parts)


# ---------------------------------------------------------------- refresh --

## Brings every part up to date with the run (called a few times a second, and when a state changes).
func refresh() -> void:
	if scene == null or scene.run == null:
		return
	var run = scene.run
	var in_place: bool = scene.phase == "place"
	var live: bool = in_place and not scene.ended
	if in_place or scene.phase == "report":
		_refresh_place(run)
		_refresh_loot(run)
		_refresh_cards(run)
		_refresh_log(run)
		_refresh_weapon(run)
		_refresh_base()
		_refresh_radio()
		call_card.refresh()
	for c in [place_panel, loot_panel, cards_grid, radio_panel, weapon_panel, base_panel]:
		c.visible = live
	news_panel.visible = live and news_open
	if not live or scene.phase != "place":
		call_card.visible = false
	_legend_wanted = live and scene.legend_t > 0.0
	legend_panel.modulate.a = clampf(scene.legend_t / LEGEND_FADE, 0.0, 1.0)
	if not live:
		_log_wanted = false
		log_panel.visible = false
		legend_panel.visible = false
	if end_card != null:
		end_card.visible = scene.phase == "report"
	if _signature() != _sig or root.size.x != _layout_w:
		_layout()


func _refresh_place(_run) -> void:
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


func _refresh_cards(_run) -> void:
	var lead = scene.leader()
	for c in cards:
		var p = c.p
		var selected: bool = scene.is_selected(p) and scene.contact.get("kind", "") == "squad"
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
		c.you.visible = p == lead and not p.dead
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
	_log_wanted = any


## The magazine and the stock of the one you lead, and how far the reload has got.
func _refresh_weapon(run) -> void:
	var lead = scene.leader()
	if lead == null:
		weapon_label.text = ""
		stock_label.text = ""
		mag_bar.value = 0.0
		return
	var gun: Dictionary = lead.gun
	var name := String(gun.get("name", lead.weapon))
	if gun.get("melee", false):
		weapon_label.text = name
		stock_label.text = "No ammunition needed"
		mag_bar.value = 1.0
		mag_bar.color = Hud.INK2
	else:
		weapon_label.text = "%s  %d / %d" % [name, int(lead.mag), int(gun.mag)]
		var stock := int(run.sim.stock.ammo)
		if lead.reloading > 0.0:
			var total := maxf(float(gun.get("reload", 1.0)), 0.1)
			mag_bar.value = clampf(1.0 - float(lead.reloading) / total, 0.0, 1.0)
			mag_bar.color = Hud.WARN
			stock_label.text = "Reloading..."
		else:
			mag_bar.value = clampf(float(lead.mag) / maxf(float(gun.mag), 1.0), 0.0, 1.0)
			mag_bar.color = Hud.DANGER if lead.mag <= 0 else Hud.OK
			stock_label.text = "%d rounds in the stores" % stock if stock > 0 else "No ammunition in the stores"
	mag_bar.queue_redraw()


## The base's clock, its mood and how it stands.
func _refresh_base() -> void:
	var cs = scene.colony()
	if cs == null:
		return
	clock_label.text = PlaceFlow.clock_text(cs)
	mood_label.text = _mood_word(cs).to_upper()
	var state: Dictionary = PlaceFlow.base_state(cs)
	base_label.text = "Base: %s" % String(state.text)
	base_label.add_theme_color_override("font_color", BASE_COLOR.get(String(state.key), Hud.INK))
	sky_dot.queue_redraw()


# ------------------------------------------------------------- banner etc --

func show_banner(title: String, sub: String) -> void:
	banner_title.text = title.to_upper()
	banner_sub.text = sub
	banner_sub.visible = sub != ""
	banner.visible = true
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
		banner_tween.tween_callback(_banner_gone)
		return
	banner.modulate.a = 0.0
	banner_tween.tween_property(banner, "modulate:a", 1.0, BANNER_FADE)
	banner_tween.tween_interval(BANNER_HOLD)
	banner_tween.tween_property(banner, "modulate:a", 0.0, BANNER_FADE)
	banner_tween.tween_callback(_banner_gone)


func _banner_gone() -> void:
	banner.modulate.a = 0.0
	banner.visible = false
	_layout()


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
	toast_tween.tween_callback(func():
		toast_panel.visible = false
		_layout())


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
	if scene.flow != null and not scene.flow.refusals.is_empty():
		sub = "Everyone who went came home."
	if not lost.is_empty():
		sub = "%s did not come back." % _names_of(lost)
	elif not result.get("hurt", {}).is_empty():
		sub = "%s came back hurt." % _names_of(result.hurt.keys())
	return ["Back from %s" % place_phrase(), sub]


## The report: what came home, who is hurt or lost, the place, the rescue, the ammunition used and (after a trip with a road)
## the news that came in while you were out. `news` is a list of lines.
func show_end(result: Dictionary, news: Array = []) -> void:
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
	var head: Label = hud._caps("Trip report", Hud.PAPER_INK3)
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
	if scene.flow != null and not scene.flow.refusals.is_empty():
		var stayed: Label = _text_value("\n".join(PackedStringArray(scene.flow.refusals)))
		stayed.add_theme_color_override("font_color", PAPER_AMBER)
		lines.add_child(_end_row("stayed", "Stayed behind", stayed))
	if not news.is_empty():
		var items: Array = []
		for line in news:
			items.append(String(line))
		var l: Label = _text_value("\n".join(items))
		l.add_theme_font_override("font", Fonts.sans(600))
		l.add_theme_font_size_override("font_size", 14)
		lines.add_child(_end_row("news", "News meanwhile", l))
	col.add_child(lines)
	var buttons: HBoxContainer = hud._hbox(8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	end_button = hud._button("Go home" if scene.flow == null else "Back to the base", true, true)
	end_button.pressed.connect(func(): scene.go_home())
	buttons.add_child(end_button)
	var key: PanelContainer = hud._kbd("Enter")
	buttons.add_child(key)
	col.add_child(buttons)
	for c in [banner, toast_panel, legend_panel, radio_panel, news_panel, call_card, weapon_panel, base_panel, log_panel]:
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
