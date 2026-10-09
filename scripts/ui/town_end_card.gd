## The end of One House (WP7): a card of notebook paper over the dimmed game when the first night's attack is held (`sim.over` is "victory" in a town run). Built on the
## demo's end card (scripts/ui/demo_end_card.gd: the dimmed window, the sheet, the scroll, the layout, the way back to the title), with the town's words and numbers:
##
##   caps       "ONE HOUSE" (`end_card().caps` when it has one)
##   title      the verdict, "The house held" (`end_card().title`)
##   line       one sentence under it (`end_card().line`)
##   stats row  a number and its name for each of `end_card().stats` = [[label, value], ...]: nights held, people, houses cleared, the dead put down, places built
##   thanks     `end_card().thanks` when there is one
##   full       `end_card().full` when there is one: a quiet line under the thanks (what the full game has; no button, no link)
##   buttons    Play again (a new town run), Back to title; Esc is Back to title
##
## Built once by the HUD when it first sees the run is over (`hud.game_over` holds it, so every "a modal is up" check of the HUD treats it as the report card). The scenario
## (`sim.scenario.end_card()`, plan 2.2) says all of it; a scenario that does not (a test's fake) gets the plain words below. A defeat is not this card: it is the ordinary
## game over (scripts/ui/game_over.gd).
extends "res://scripts/ui/demo_end_card.gd"

const DEFAULT_TITLE := "The house held"
const DEFAULT_LINE := "The dead came, and the dawn found you standing."
const TILE_W := 108.0
## The card is a little wider than the demo's, for a row of five numbers.
const CARD_MAX_W := 640.0

## The words the card was made from (what `end_card()` said): the tests read it.
var content := {}
## The stats row: one tile for each of `stats`.
var stats_row: HFlowContainer
var thanks_label: Label
var caps_label: Label
## The numbers by their names ("Nights held" -> the Label with its value).
var stat_by_name := {}


## What the scenario says the card should show (see the header), with plain words for what it does not say.
func end_card() -> Dictionary:
	var d := {}
	if sim != null and sim.get("scenario") != null and sim.scenario.has_method("end_card"):
		var got = sim.scenario.end_card()
		if got is Dictionary:
			d = got.duplicate()
	if String(d.get("title", "")) == "":
		d["title"] = DEFAULT_TITLE
	if String(d.get("line", "")) == "":
		d["line"] = DEFAULT_LINE
	if not d.has("stats") or not (d.stats is Array):
		d["stats"] = []
	return d


func _build() -> void:
	content = end_card()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.035, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var style: StyleBox = hud._paper_style()
	if style is StyleBoxFlat:
		style.content_margin_left = 28
		style.content_margin_right = 28
		style.content_margin_top = 22
		style.content_margin_bottom = 24
	panel = hud._panel(style)
	center.add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(scroll)
	col = hud._vbox(12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	caps_label = hud._label(String(content.get("caps", "One House")).to_upper(), Fonts.cond(600, 1), 14, hud.PAPER_INK3)
	caps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(caps_label)
	title_label = hud._label(String(content.title), Fonts.cond(700), 34, hud.PAPER_INK)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.x = 200
	col.add_child(title_label)
	sub_label = hud._label(String(content.line), Fonts.sans(400), 16, hud.PAPER_INK2)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.custom_minimum_size.x = 200
	col.add_child(sub_label)

	# what the run came to: one row of numbers between two rules of the notebook
	col.add_child(_line(hud.PAPER_INK))
	stats_row = HFlowContainer.new()
	stats_row.alignment = FlowContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("h_separation", 6)
	stats_row.add_theme_constant_override("v_separation", 8)
	stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair in content.stats:
		if pair is Array and pair.size() >= 2:
			stats_row.add_child(_stat_tile(String(pair[0]), str(pair[1])))
	col.add_child(stats_row)
	col.add_child(_line(hud.PAPER_INK))

	var thanks := String(content.get("thanks", ""))
	thanks_label = hud._label(thanks, Fonts.sans(600), 15, hud.PAPER_INK)
	thanks_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thanks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	thanks_label.custom_minimum_size.x = 200
	thanks_label.visible = thanks != ""
	col.add_child(thanks_label)
	# (a quiet line under the thanks, `end_card().full`: what the full game has; no button and no link, the page and the name are not decided)
	var full := String(content.get("full", ""))
	full_label = hud._label(full, Fonts.sans(400), 13, hud.PAPER_INK3)
	full_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	full_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	full_label.custom_minimum_size.x = 200
	full_label.visible = full != ""
	col.add_child(full_label)

	var buttons: HFlowContainer = HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 8)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	again_button = hud._button("Play again", true, true)
	again_button.pressed.connect(_play_again)
	buttons.add_child(again_button)
	title_button = hud._button("Back to title", false, true)
	title_button.pressed.connect(_quit_to_title)
	buttons.add_child(title_button)
	col.add_child(buttons)


## One number of the row: the number big, its name under it in small capitals.
func _stat_tile(caption: String, value: String) -> Control:
	var tile: VBoxContainer = hud._vbox(0)
	tile.custom_minimum_size.x = TILE_W
	var number: Label = hud._label(value, Fonts.cond(700), 30, hud.PAPER_INK)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.add_child(number)
	var name_label: Label = hud._label(caption.to_upper(), Fonts.cond(600, 1), 14, hud.PAPER_INK2)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = TILE_W - 8.0
	tile.add_child(name_label)
	stat_by_name[caption] = number
	return tile


## The demo card's layout with this card's width.
func _layout() -> void:
	if panel == null:
		return
	panel.custom_minimum_size = Vector2(minf(size.x - 32.0, CARD_MAX_W), 0)
	var room := maxf(160.0, size.y - 32.0 - 46.0)
	scroll.custom_minimum_size.y = minf(col.get_combined_minimum_size().y, room)
	_relayout.call_deferred()


## A new town run: the same town, from the start (CLEAR3: the town is named in the meta, so that a run played on `--town=N` comes back to that town and not to the town of its dice).
func _play_again() -> void:
	var seed_value := int(sim.get("run_seed")) if sim != null and sim.get("run_seed") != null else 1
	var meta := {"difficulty": 1, "seed": seed_value, "town": true}
	var town_data = sim.get("town_data") if sim != null else null
	if typeof(town_data) == TYPE_DICTIONARY and (town_data as Dictionary).has("seed"):
		meta["town"] = int(town_data.seed)
	hud.start_run(meta)


## Esc is the way back to the title (the pause menu is not there under the card).
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		_quit_to_title()
