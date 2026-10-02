## The Lots page of the Build screen (round 9): what the lots are for, how many of the ten streets are open and what that costs, and a
## card for each lot of the ring: its name and blurb, what it costs (scrap, a day, places cleared on the town board: each condition
## on a line of its own, the ones that are not met in the page's warning ink), a Claim button (always there; with the reason it
## cannot be pressed written under it and as its tooltip). Once it is claimed the card is the lot's **standing order** (round 11, the
## cut): one switch, "Wall the streets as the scrap allows" (the module orders the next open street's wall by itself, one after
## another: `lots.set_auto_walling`), the street that is next and what its wall costs ("Next: the west alley, 11 scrap", "Waiting
## for scrap", "Every street has its wall"), how many of its walls stand and whether it is sealed. There is no kit to pick
## here or anywhere: a street's own card (its pin on the map) has the one wall the order would put there, for the player who
## would not wait. Pointing at a card (or putting the keyboard on its button or switch) marks the lot in the world and on the map.
##
## Everything is read from the lots module (`sim.lots`) and changed through it. The Build screen owns this page (it is one of the
## things the detail column can show) and hands it the HUD's styles and the screen's helpers.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const Kit := preload("res://scripts/ui/menu_kit.gd")

## What the switch says.
const SWITCH_WORDS := "Wall the streets as the scrap allows"
## The switch's size (pixels), and the green it turns when it is on.
const SWITCH_W := 46.0
const SWITCH_H := 26.0
const SWITCH_ON := Color("#4f7330")
const KNOB := Color("#fbf7ea")

var screen
var hud
var sim
var lots
var root: VBoxContainer
var risk: Label
## lot id -> {"card", "name", "blurb", "state" (the chip "Claimed"), "price", "terms" (the box of condition lines), "claim" (a
## Button), "why", "order_row" (the standing order's line: shown once the lot is claimed), "switch" (a toggle Button), "switch_label",
## "next" (the street that is next), "walls", "sealed"}
var cards := {}


func setup(s) -> void:
	screen = s
	hud = s.hud
	sim = s.sim
	lots = sim.lots
	_build()
	refresh()


func _build() -> void:
	root = hud._vbox(8)
	risk = screen._para(14, hud.PAPER_INK, 600)
	root.add_child(risk)
	for l in lots.lots():
		root.add_child(_build_card(l))


func _build_card(l: Dictionary) -> Control:
	var id := String(l.id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", screen._card_style(false))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_entered.connect(screen.show_lot_mark.bind(id))
	card.mouse_exited.connect(screen.show_lot_mark.bind(""))
	var col: VBoxContainer = hud._vbox(5)
	var head: HBoxContainer = hud._hbox(8)
	var name_label: Label = hud._label(String(l.name), Fonts.cond(700), 21, hud.PAPER_INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = 80
	head.add_child(name_label)
	var chip: PanelContainer = screen._tag("Claimed")
	chip.visible = false
	head.add_child(chip)
	col.add_child(head)
	var blurb: Label = screen._para(13, hud.PAPER_INK2)
	blurb.text = String(l.get("blurb", ""))
	col.add_child(blurb)
	# what a claim asks: a day, places cleared on the town board, scrap (each a small pill, in the warning ink while it is not met)
	var terms := HFlowContainer.new()
	terms.add_theme_constant_override("h_separation", 6)
	terms.add_theme_constant_override("v_separation", 4)
	terms.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pills: Array = []
	for kind in ["day", "cleared", "scrap"]:
		var pill := PanelContainer.new()
		pill.mouse_filter = Control.MOUSE_FILTER_PASS
		var label: Label = hud._label("", Fonts.sans(600), 13, hud.PAPER_INK)
		pill.add_child(label)
		terms.add_child(pill)
		pills.append({"kind": kind, "pill": pill, "label": label})
	col.add_child(terms)
	# the reason it cannot be claimed yet, and the button (the reason is its tooltip too)
	var foot: HBoxContainer = hud._hbox(10)
	var why: Label = screen._para(13, hud.SLIP_MARK.warn, 600)
	why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	why.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(why)
	var claim: Button = screen._button("Claim", true)
	claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claim.custom_minimum_size = Vector2(112, screen.BUTTON_H)
	claim.pressed.connect(screen.claim_lot.bind(id))
	claim.focus_entered.connect(screen.show_lot_mark.bind(id))
	claim.focus_exited.connect(screen.show_lot_mark.bind(""))
	foot.add_child(claim)
	col.add_child(foot)
	# the standing order (a claimed lot): the switch with its words, and which street is next
	var order_row: HBoxContainer = hud._hbox(10)
	var sw := _switch()
	sw.toggled.connect(_on_switch.bind(id))
	sw.focus_entered.connect(screen.show_lot_mark.bind(id))
	sw.focus_exited.connect(screen.show_lot_mark.bind(""))
	order_row.add_child(sw)
	var words: Label = screen._para(14, hud.PAPER_INK, 600)
	words.text = SWITCH_WORDS
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_STOP
	words.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	words.gui_input.connect(_on_words_input.bind(id))
	order_row.add_child(words)
	order_row.visible = false
	col.add_child(order_row)
	var next: Label = screen._para(14, hud.PAPER_INK)
	next.visible = false
	col.add_child(next)
	var walls: Label = screen._para(14, hud.PAPER_INK, 600)
	col.add_child(walls)
	var sealed: Label = screen._para(13, hud.PAPER_INK2)
	col.add_child(sealed)
	card.add_child(col)
	cards[id] = {"card": card, "name": name_label, "blurb": blurb, "state": chip, "terms": terms, "pills": pills, "foot": foot, "claim": claim, "why": why,
		"order_row": order_row, "switch": sw, "switch_label": words, "next": next, "walls": walls, "sealed": sealed}
	return card


## The switch: a toggle button the keyboard and the mouse can have, with a pill and a knob drawn over it (the knob is at the right
## and the pill green when it is on).
func _switch() -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(SWITCH_W + 6.0, SWITCH_H + 6.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var none := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, none)
	b.add_theme_stylebox_override("focus", Kit.focus_box(hud.ACCENT, int(SWITCH_H / 2.0) + 3))
	var pill := Pill.new()
	pill.ink = hud.PAPER_INK
	pill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	b.add_child(pill)
	b.set_meta("pill", pill)
	b.toggled.connect(func(_on: bool): pill.queue_redraw())
	b.mouse_entered.connect(pill.queue_redraw)
	b.mouse_exited.connect(pill.queue_redraw)
	return b


## The picture of a switch: a pill (green when the button is down, an ink wash when it is up) with a round knob.
class Pill:
	extends Control
	var ink := Color(0.1, 0.1, 0.1)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var button := get_parent() as Button
		var on: bool = button != null and button.button_pressed
		var r := size.y / 2.0
		var track := StyleBoxFlat.new()
		track.bg_color = SWITCH_ON if on else Color(ink, 0.3)
		track.border_color = Color(ink, 0.7)
		track.set_border_width_all(1)
		track.set_corner_radius_all(int(r))
		track.anti_aliasing = true
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var x := size.x - r if on else r
		var hot: bool = button != null and button.is_hovered()
		draw_circle(Vector2(x, r), r - 3.0, KNOB if hot else KNOB.darkened(0.04))
		draw_arc(Vector2(x, r), r - 3.0, 0.0, TAU, 20, Color(ink, 0.55), 1.0, true)


## The switch was turned (by the mouse, the keyboard or a test): the module's standing order follows, and the page.
func _on_switch(on: bool, lot_id: String) -> void:
	if lots.auto_walling(lot_id) == on:
		return
	if lots.set_auto_walling(lot_id, on):
		hud.ui_sound("ui_click")
		screen.refresh(true)
	elif cards.has(lot_id):
		(cards[lot_id].switch as Button).set_pressed_no_signal(false)


## A click on the words turns the switch, as it does on a check box's.
func _on_words_input(ev: InputEvent, lot_id: String) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var sw: Button = cards[lot_id].switch
		if sw.is_visible_in_tree():
			sw.button_pressed = not sw.button_pressed


## The page follows the game: the streets that are open, and every card.
func refresh() -> void:
	var open: int = lots.open_streets()
	var all: int = lots.streets()
	risk.text = "Shut every street and nothing in the ring is raided; each street left open is a share of the risk (%d of %d open: %s%% a night for each building out here)." % [open, all, screen._num(lots.raid_risk() * 100.0)]
	for l in lots.lots():
		_refresh_card(l)


func _refresh_card(l: Dictionary) -> void:
	var id := String(l.id)
	var c: Dictionary = cards[id]
	var claimed: bool = lots.claimed(id)
	c.card.add_theme_stylebox_override("panel", screen._card_style(claimed))
	c.state.visible = claimed
	c.blurb.visible = not claimed    # (what the lot is was for choosing it: a lot that is yours has its switch and its walls)
	c.terms.visible = not claimed
	c.foot.visible = not claimed
	c.order_row.visible = claimed
	c.next.visible = claimed
	c.walls.visible = claimed
	c.sealed.visible = claimed
	if claimed:
		var sw: Button = c.switch
		sw.set_pressed_no_signal(lots.auto_walling(id))
		sw.tooltip_text = "%s: %s\nWhen nothing is going up and the stores have the scrap (and %d to spare), the Builders are given the next open street's wall, the sturdiest kit for its price, one street after another.\nTo wall one street yourself, point at its pin on the map." % [SWITCH_WORDS, "on" if sw.button_pressed else "off", int(lots.AUTO_KEEP)]
		(sw.get_meta("pill") as Control).queue_redraw()
		c.next.text = _next_line(id)
		var mouths: int = lots.mouths_of(id).size()
		c.walls.text = "%d of %d walls stand" % [lots.standing_walls(id), mouths]
		if lots.sealed(id):
			c.sealed.text = "Its streets are shut. The ring is one open space: buildings out here are raided at the bell only while some street of the block stays open (%d of %d do)." % [lots.open_streets(), lots.streets()]
		else:
			c.sealed.text = "Its streets are not all shut. A building out here may be raided at the bell, the less the more of the block's streets are shut."
		return
	var terms: Dictionary = l.claim
	_refresh_pills(c.pills, terms)
	var why := String(lots.why_not_claim(id))
	c.claim.disabled = why != ""
	c.claim.focus_mode = Control.FOCUS_NONE if why != "" else Control.FOCUS_ALL
	c.claim.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if why != "" else Control.CURSOR_POINTING_HAND
	c.why.text = screen._sentence(why)
	c.why.visible = why != ""
	c.claim.tooltip_text = screen._sentence(why) if why != "" else "Claim %s: %d scrap now, then its plots and mouths are yours to build on" % [String(l.name), int(terms.get("scrap", 0))]


## What the standing order has in front of it: the street that is next and its price, and whether the stores are short of it
## (the order keeps a little back; a street walled by hand needs the price only), or that every street has its wall.
func _next_line(lot_id: String) -> String:
	var street: String = lots.next_street(lot_id)
	if street == "":
		var down: int = lots.mouths_of(lot_id).size() - lots.standing_walls(lot_id)
		if down > 0:
			return "%d wall%s down: the crew mends %s" % [down, "" if down == 1 else "s", "it" if down == 1 else "them"]
		return "Every street has its wall"
	var price: int = lots.next_price(lot_id)
	var text := "Next: %s, %d scrap" % [String(lots.mouth(street).name), price]
	var need: float = float(price) + (float(lots.AUTO_KEEP) if lots.auto_walling(lot_id) else 0.0)
	if float(sim.stock.scrap) + 1.0e-9 < need:
		text += ". Waiting for scrap"
	return text


## The conditions of a claim as pills: in the page's ink when they hold, in the warning ink with "Not before", "Needs" when not.
func _refresh_pills(pills: Array, terms: Dictionary) -> void:
	var day := int(terms.get("day", 0))
	var need := int(terms.get("cleared", 0))
	var scrap := int(terms.get("scrap", 0))
	var have := int(sim.town.cleared_count())
	var stock := int(float(sim.stock.scrap))
	for p in pills:
		var met := true
		var text := ""
		var shown := true
		match String(p.kind):
			"day":
				met = sim.day >= day
				shown = day > 0
				text = "From day %d" % day if met else "Not before day %d (it is day %d)" % [day, sim.day]
			"cleared":
				met = have >= need
				shown = need > 0
				text = "%d place%s cleared on the board" % [need, "" if need == 1 else "s"] if met else "Needs %d place%s cleared on the board (%d so far)" % [need, "" if need == 1 else "s", have]
			_:
				met = float(sim.stock.scrap) + 1.0e-9 >= float(scrap)
				shown = scrap > 0
				text = "%d scrap" % scrap if met else "Needs %d scrap (%d in the stores)" % [scrap, stock]
		var pill: PanelContainer = p.pill
		pill.visible = shown
		(p.label as Label).text = text
		(p.label as Label).add_theme_color_override("font_color", hud.PAPER_INK if met else hud.SLIP_MARK.warn)
		pill.add_theme_stylebox_override("panel", _pill_style(met))
		pill.tooltip_text = "This holds" if met else "This does not hold yet"


func _pill_style(met: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(hud.PAPER_INK, 0.07) if met else Color(hud.SLIP_MARK.warn, 0.06)
	sb.border_color = Color(hud.PAPER_INK, 0.3) if met else Color(hud.SLIP_MARK.warn, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	return sb


## The first control of a card that the keyboard can have: the Claim button of a lot that can be claimed, the switch of one that is.
func controls() -> Array:
	var out: Array = []
	for l in lots.lots():
		var c: Dictionary = cards[String(l.id)]
		if c.foot.visible:
			out.append(c.claim)
		elif c.order_row.visible:
			out.append(c.switch)
	return out
