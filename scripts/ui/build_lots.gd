## The Lots page of the Build screen (round 9): what the lots are for, how many of the ten streets are open and what that costs, and a
## card for each lot of the ring: its name and blurb, what it costs (scrap, a day, places cleared on the town board: each condition
## on a line of its own, the ones that are not met in the page's warning ink), a Claim button (always there; with the reason it
## cannot be pressed written under it and as its tooltip) and, once it is claimed, how many of its walls stand and whether it is
## sealed. Pointing at a card (or putting the keyboard on its button) marks the lot in the world and on the map.
##
## Everything is read from the lots module (`sim.lots`) and changed through it. The Build screen owns this page (it is one of the
## things the detail column can show) and hands it the HUD's styles and the screen's helpers.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")

var screen
var hud
var sim
var lots
var root: VBoxContainer
var risk: Label
## lot id -> {"card", "name", "blurb", "state" (the chip "Claimed"), "price", "terms" (the box of condition lines), "claim" (a
## Button), "why", "walls", "sealed"}
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
	var walls: Label = screen._para(14, hud.PAPER_INK, 600)
	col.add_child(walls)
	var sealed: Label = screen._para(13, hud.PAPER_INK2)
	col.add_child(sealed)
	card.add_child(col)
	cards[id] = {"card": card, "name": name_label, "blurb": blurb, "state": chip, "terms": terms, "pills": pills, "foot": foot, "claim": claim, "why": why, "walls": walls, "sealed": sealed}
	return card


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
	c.terms.visible = not claimed
	c.foot.visible = not claimed
	c.walls.visible = claimed
	c.sealed.visible = claimed
	if claimed:
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


## The first control of a card that the keyboard can have: the Claim button, when it can be pressed.
func controls() -> Array:
	var out: Array = []
	for l in lots.lots():
		var c: Dictionary = cards[String(l.id)]
		if c.foot.visible:
			out.append(c.claim)
	return out
