## The "Send a scavenging party" dialog: a modal page of notebook paper over the game (a
## trip is a permission slip). The selected person leads, one other free survivor may come,
## and the player picks one of the places the scavenging module offers (any number of them:
## side by side while each card keeps its width, else two by two, else one above the other);
## Send hands the party to it. Opened by hud.open_scavenge, which also pauses the game while
## it is open.
##
## It borrows the HUD's styles, colours and icons (the `hud` it is given) so it
## looks like the rest, and reads everything else from the scavenging module:
## can_send(), why_not(), available_sites(), free_survivors() and send(). The ink on the page
## is the HUD's PAPER_INK family (the chalk colours are for the boards).
extends Control

const GD := preload("res://scripts/game_data.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## Emitted once, when the dialog is gone (sent or cancelled).
signal closed

## When a party is back (the scavenging module's RETURN_H; spec 4.1).
const BACK_AROUND := "16:00"
## The panel is at most this wide; from WIDE_W the party sits beside the sites, below it
## above them.
const MAX_W := 1040.0
const WIDE_W := 900.0
const PARTY_W := 264.0
## A site card is never narrower than this, and sites go side by side only while each card
## would be at least COL_W wide (else two by two, else one above the other).
const CARD_MIN_W := 150.0
const COL_W := 170.0
const SITE_GAP := 10.0
const STOCK_ORDER := ["food", "water", "scrap", "ammo", "meds"]
const STOCK_NAME := {"food": "Food", "water": "Water", "scrap": "Scrap", "ammo": "Ammo", "meds": "Medicine"}
## The cards on the page: a sheet a little lighter than the paper, with a thin ink edge; the
## chosen one gets a gold wash and a heavy edge of dark gold.
const CARD := Color("#f8f4e8")
const CARD_CHOSEN := Color("#fbecb8")
const GOLD_EDGE := Color("#946c0c")
## The dark gold of a word on the gold wash ("Leads"): 4.5:1 or better on it.
const GOLD_INK := Color("#7a5809")

var hud
var sim
## The leader, and the one who may come along (Person objects or null).
var first = null
var second = null
## The chosen place ("" until one is).
var site_id := ""
## person id -> {"row": the clickable row, "person": Person}
var candidates := {}
## site id -> {"card", "image", "placeholder", "pips", "available", "site", "holder"}
var site_cards := {}

var panel: PanelContainer
var scroll: ScrollContainer
var body: BoxContainer
var party_box: VBoxContainer
var sites_box: GridContainer
var send_button: Button
var cancel_button: Button
var error_label: Label
var hint_label: Label
var _header: Control
var _footer: Control
var _first_card: PanelContainer
var _note := ""
var _open := true


## `sel` is the selected Person, or null: the dialog picks who leads if they cannot go.
func setup(h, s, sel) -> void:
	hud = h
	sim = s
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var free_people := _free_survivors()
	if sel != null and free_people.has(sel):
		first = sel
	elif not free_people.is_empty():
		first = free_people[0]
		if sel != null:
			_note = "%s can't go out now." % sel.first
	_build(free_people)
	resized.connect(_layout)
	_layout()
	_refresh()
	# wrapped text only knows its height once it has a width: lay out again a frame on
	_layout.call_deferred()


## The survivors who can go out now: the scavenging module's own list, else the
## HUD's best guess.
func _free_survivors() -> Array:
	if sim.scavenge.has_method("free_survivors"):
		return sim.scavenge.free_survivors()
	var out: Array = []
	for p in sim.people:
		if hud.is_free_to_go(p):
			out.append(p)
	return out


# ------------------------------------------------------------------- build --

func _build(free_people: Array) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.035, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var style: StyleBox = hud._paper_style()
	if style is StyleBoxFlat:
		style.content_margin_left = 20
		style.content_margin_right = 20
		style.content_margin_top = 18
		style.content_margin_bottom = 18
	panel = hud._panel(style)
	center.add_child(panel)
	var col: VBoxContainer = hud._vbox(12)
	panel.add_child(col)

	var head: VBoxContainer = hud._vbox(2)
	head.add_child(hud._label("Send a scavenging party", Fonts.cond(700), 24, hud.PAPER_INK))
	head.add_child(hud._caps("Out through the gate this morning, back before dusk", hud.PAPER_INK2))
	_header = head
	col.add_child(head)

	var can_go: bool = first != null and sim.scavenge.can_send()
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_scrollbar(scroll)
	col.add_child(scroll)
	body = BoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(body)
	if can_go:
		_build_party(free_people)
		_build_sites()
	else:
		var why: String = sim.scavenge.why_not()
		if why == "":
			why = "Nobody can go out now."
		var msg: Label = hud._label(why, Fonts.sans(400), 15, hud.PAPER_INK)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		msg.custom_minimum_size.x = 240
		body.add_child(msg)

	var foot: VBoxContainer = hud._vbox(8)
	error_label = hud._label("", Fonts.sans(600), 13, hud.SLIP_MARK.danger)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	foot.add_child(error_label)
	var row: HBoxContainer = hud._hbox(10)
	hint_label = hud._label("", Fonts.sans(400), 13, hud.PAPER_INK2)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_label.custom_minimum_size.x = 120
	row.add_child(hint_label)
	cancel_button = hud._button("Cancel", false, true)
	cancel_button.pressed.connect(cancel)
	row.add_child(cancel_button)
	send_button = hud._button("Send", true, true)
	send_button.pressed.connect(send)
	send_button.visible = can_go
	row.add_child(send_button)
	foot.add_child(row)
	_footer = foot
	col.add_child(foot)


## The page's scroll bar in the page's colours: a pencil-line track and an oak knob.
func _style_scrollbar(box: ScrollContainer) -> void:
	var bar := box.get_v_scroll_bar()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(hud.PAPER_INK, 0.1)
	track.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll", track)
	var knobs := {"grabber": hud.OAK, "grabber_highlight": hud.OAK.lightened(0.15), "grabber_pressed": hud.OAK_DARK}
	for name in knobs:
		var knob := StyleBoxFlat.new()
		knob.bg_color = knobs[name]
		knob.set_corner_radius_all(4)
		bar.add_theme_stylebox_override(name, knob)
	bar.custom_minimum_size.x = 9


## The leader first, then the others who could come, in one flowing list.
func _build_party(free_people: Array) -> void:
	party_box = hud._vbox(8)
	party_box.add_child(hud._caps("Party", hud.PAPER_INK2))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_first_card = _person_card(first, true)
	flow.add_child(_first_card)
	var others := 0
	for p in free_people:
		if p == first:
			continue
		var card := _person_card(p, false)
		card.gui_input.connect(_on_candidate_input.bind(p))
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		candidates[p.id] = {"row": card, "person": p}
		flow.add_child(card)
		others += 1
	party_box.add_child(flow)
	if _note != "":
		var n: Label = hud._label(_note, Fonts.sans(400), 13, hud.SLIP_MARK.warn)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		party_box.add_child(n)
	var tip: Label = hud._label("Click someone to bring them along, or go alone. Two is the most." if others > 0 else "Nobody else is free to go with them.", Fonts.sans(400), 12, hud.PAPER_INK3)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	party_box.add_child(tip)
	body.add_child(party_box)


## A portrait, a name and the skills that matter for a trip.
func _person_card(p, leader: bool) -> PanelContainer:
	var card: PanelContainer = hud._panel(_card_style(leader))
	card.custom_minimum_size.x = 200
	var row: HBoxContainer = hud._hbox(10)
	var pic := TextureRect.new()
	pic.texture = GD.tex(hud.data.portraits[p.id])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(40, 40)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var text: VBoxContainer = hud._vbox(1)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top: HBoxContainer = hud._hbox(6)
	top.add_child(hud._label(p.name, Fonts.cond(700), 17, hud.PAPER_INK))
	if leader:
		var tag: Label = hud._caps("Leads", GOLD_INK)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(tag)
	text.add_child(top)
	text.add_child(hud._label("Shooting %d · Leading %d" % [int(p.def.skills.get("Shooting", 0)), int(p.def.skills.get("Leading", 0))], Fonts.sans(400), 12, hud.PAPER_INK2))
	row.add_child(text)
	card.add_child(row)
	return card


## A card of the page: a lighter sheet with a thin ink edge; chosen, a gold wash and a heavy
## edge of dark gold.
func _card_style(chosen: bool) -> StyleBox:
	var s: StyleBoxFlat = hud._flat(CARD_CHOSEN if chosen else CARD, 4, GOLD_EDGE if chosen else Color(hud.PAPER_INK, 0.3), false)
	s.set_border_width_all(3 if chosen else 1)
	s.content_margin_left = 8
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _build_sites() -> void:
	sites_box = GridContainer.new()
	sites_box.columns = 3
	sites_box.add_theme_constant_override("h_separation", int(SITE_GAP))
	sites_box.add_theme_constant_override("v_separation", int(SITE_GAP))
	sites_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sites_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for site in sim.scavenge.available_sites():
		sites_box.add_child(_site_card(site))
	body.add_child(sites_box)


func _site_card(site: Dictionary) -> PanelContainer:
	var id := String(site.get("id", ""))
	var available: bool = bool(site.get("available", true))
	var card: PanelContainer = hud._panel(_site_style(false))
	card.custom_minimum_size.x = CARD_MIN_W
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_FILL
	card.clip_contents = true
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if available else Control.CURSOR_FORBIDDEN
	card.gui_input.connect(_on_site_input.bind(id))
	var col: VBoxContainer = hud._vbox(0)
	# the picture, or a plain placeholder when the file is not there
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 104)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var image := TextureRect.new()
	image.texture = _site_texture(String(site.get("image", "")))
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.modulate = Color.WHITE if available else Color(0.42, 0.42, 0.42)
	holder.add_child(image)
	var placeholder := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#243833")
	placeholder.add_theme_stylebox_override("panel", ps)
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph: TextureRect = hud._icon("scavenge", 30, hud.INK3)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	glyph.offset_left = -15
	glyph.offset_right = 15
	glyph.offset_top = -15
	glyph.offset_bottom = 15
	placeholder.add_child(glyph)
	placeholder.visible = image.texture == null
	holder.add_child(placeholder)
	col.add_child(holder)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 12)
	var text: VBoxContainer = hud._vbox(6)
	var name_label: Label = hud._label(String(site.get("name", id)), Fonts.cond(700), 19, hud.PAPER_INK if available else hud.PAPER_INK3)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(name_label)
	var danger := clampi(int(site.get("danger", 1)), 0, 3)
	text.add_child(_danger_row(danger))
	var blurb: Label = hud._label(String(site.get("blurb", "")), Fonts.sans(400), 13, hud.PAPER_INK2 if available else hud.PAPER_INK3)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(blurb)
	text.add_child(_loot_row(site))
	var note := String(site.get("note", ""))
	if note != "":
		var n: Label = hud._label(note, Fonts.sans(600), 12, hud.SLIP_MARK.warn)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(n)
	pad.add_child(text)
	col.add_child(pad)
	card.add_child(col)
	site_cards[id] = {"card": card, "image": image, "placeholder": placeholder, "pips": danger, "available": available, "site": site, "holder": holder}
	return card


func _site_style(chosen: bool) -> StyleBox:
	var s: StyleBoxFlat = hud._flat(CARD_CHOSEN if chosen else CARD, 4, GOLD_EDGE if chosen else Color(hud.PAPER_INK, 0.3), false)
	s.set_border_width_all(3 if chosen else 1)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	return s


## "DANGER" and three pips, filled to the site's danger (the dark colours of the slips: the
## number of pips filled says it as well as the colour).
func _danger_row(danger: int) -> Control:
	var row: HBoxContainer = hud._hbox(5)
	row.add_child(hud._caps("Danger", hud.PAPER_INK2))
	for i in 3:
		var pip := Panel.new()
		var st := StyleBoxFlat.new()
		st.bg_color = (hud.SLIP_MARK.danger if danger >= 3 else hud.SLIP_MARK.warn) if i < danger else Color(hud.PAPER_INK, 0.18)
		st.set_corner_radius_all(5)
		st.anti_aliasing = true
		pip.add_theme_stylebox_override("panel", st)
		pip.custom_minimum_size = Vector2(10, 10)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
	return row


## What the place is good for: an icon and an amount for each stock it gives,
## then the ones that come now and then. Falls back to the module's own hint.
func _loot_row(site: Dictionary) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 3)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var loot = site.get("loot", {})
	var extra = site.get("extra", {})
	if loot is Dictionary and not loot.is_empty():
		for k in STOCK_ORDER:
			if loot.has(k):
				flow.add_child(_chip(k, _range_text(loot[k]), hud.PAPER_INK))
		if extra is Dictionary:
			for k in STOCK_ORDER:
				if extra.has(k):
					flow.add_child(_chip(k, "sometimes", hud.PAPER_INK3))
	else:
		flow.add_child(hud._label(String(site.get("loot_hint", "")), Fonts.sans(400), 13, hud.PAPER_INK))
	return flow


func _chip(stock: String, text: String, color: Color) -> Control:
	var row: HBoxContainer = hud._hbox(4)
	var ic: TextureRect = hud._icon(stock, 14, hud.PAPER_INK2)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	row.add_child(hud._label(text, Fonts.cond(600), 14, color))
	row.tooltip_text = STOCK_NAME.get(stock, stock)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


func _range_text(r) -> String:
	if r is Array and r.size() >= 2:
		var lo := int(r[0])
		var hi := int(r[1])
		return "%d" % lo if lo == hi else "%d–%d" % [lo, hi]
	return str(r)


## The site's picture if the file is there (imported, or a plain PNG in a
## checkout that has not been imported yet), else null.
func _site_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


# ------------------------------------------------------------------ layout --

## How many site cards go side by side on a row `inner` wide: all of them while each card
## keeps at least COL_W; failing that the largest even split of them that does (four go two
## by two), else one above the other.
static func columns_for(count: int, inner: float) -> int:
	if count <= 1:
		return 1
	for cols in range(count, 1, -1):
		if count % cols == 0 and (inner - SITE_GAP * float(cols - 1)) / float(cols) >= COL_W:
			return cols
	return 1


func _layout() -> void:
	if panel == null or not is_inside_tree():
		return
	var pw := minf(size.x - 32.0, MAX_W)
	panel.custom_minimum_size.x = pw
	var wide := pw >= WIDE_W
	if body != null:
		body.vertical = not wide
	if party_box != null:
		party_box.custom_minimum_size.x = PARTY_W if wide else 0.0
		party_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if wide else Control.SIZE_EXPAND_FILL
	if sites_box != null:
		# the room the cards share: the page less its margins and, beside them, the party
		var sb := panel.get_theme_stylebox("panel")
		var inner := pw - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT) - (PARTY_W + 18.0 if wide else 0.0)
		var cols := columns_for(site_cards.size(), inner)
		sites_box.columns = cols
		# the pictures keep their 16:9 shape, within reason
		var card_w := (inner - SITE_GAP * float(cols - 1)) / float(cols)
		# with more than one row the pictures are shorter, so that two rows still fit a short window
		var rows := ceili(float(site_cards.size()) / float(cols))
		var img_h := clampf(card_w * 9.0 / 16.0, 72.0, 140.0 if rows <= 1 else 100.0) if cols > 1 else 110.0
		for id in site_cards:
			site_cards[id].holder.custom_minimum_size = Vector2(0, img_h)
	# the body scrolls when the window is too short for everything
	var chrome: float = _header.get_combined_minimum_size().y + _footer.get_combined_minimum_size().y + 24.0 + 32.0
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, maxf(120.0, size.y - 32.0 - chrome))


# ------------------------------------------------------------------ choices --

func choose_site(id: String) -> void:
	if not site_cards.has(id) or not site_cards[id].available:
		return
	site_id = id
	error_label.visible = false
	_refresh()


## Puts `p` in the party as the second member; asking for the one already there
## takes them out, and asking for another replaces them (two is the most).
func toggle_second(p) -> void:
	if not candidates.has(p.id):
		return
	second = null if second == p else p
	_refresh()


func _on_site_input(ev: InputEvent, id: String) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		choose_site(id)
		accept_event()


func _on_candidate_input(ev: InputEvent, p) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		toggle_second(p)
		accept_event()


## Borders, the Send button and the line of text at the foot follow the choices.
func _refresh() -> void:
	for id in site_cards:
		site_cards[id].card.add_theme_stylebox_override("panel", _site_style(id == site_id))
	for id in candidates:
		candidates[id].row.add_theme_stylebox_override("panel", _card_style(second != null and second.id == id))
	if first == null or sites_box == null:
		hint_label.text = ""
		return
	send_button.disabled = site_id == ""
	if site_id == "":
		hint_label.text = "Choose where %s go%s." % [_who(), "" if second != null else "es"]
		return
	var where: String = site_cards[site_id].site.get("where", String(site_cards[site_id].site.get("name", "")).to_lower())
	var text := "%s %s to %s and back around %s." % [_who(), "go" if second != null else "goes", where, BACK_AROUND]
	if second == null:
		text += " A lone scavenger brings back less."
	hint_label.text = text


func _who() -> String:
	return first.first if second == null else "%s and %s" % [first.first, second.first]


# ------------------------------------------------------------------ closing --

func send() -> void:
	if first == null or site_id == "" or not _open:
		return
	var party: Array = [first]
	if second != null:
		party.append(second)
	if sim.scavenge.send(party, site_id):
		close()
		return
	var why: String = sim.scavenge.why_not()
	error_label.text = why if why != "" else "They could not go out just now."
	error_label.visible = true


func cancel() -> void:
	close()


func close() -> void:
	if not _open:
		return
	_open = false
	set_process_input(false)
	hide()
	closed.emit()
	queue_free()


## While it is open every key belongs to the dialog: Esc cancels, Enter sends.
func _input(ev: InputEvent) -> void:
	if not _open or not (ev is InputEventKey) or not ev.pressed:
		return
	if ev.keycode == KEY_ESCAPE:
		cancel()
	elif ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER:
		if send_button != null and send_button.visible and not send_button.disabled:
			send()
	if is_inside_tree():
		get_viewport().set_input_as_handled()
