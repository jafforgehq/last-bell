## The end of the demo (round 26): a card of notebook paper over the dimmed game when the three nights are held (`sim.over` is "victory" in a demo run).
## "Thanks for playing the Thirty Bells demo", what the run came to (nights held, who is alive and who is lost, the dead put down, trips, buildings), a
## line about the full game, and three buttons: Wishlist (the store page of `Demo.wishlist_url()`: not there while that is empty), Play again (the same three
## nights again) and Quit to title. A defeat is not this card: it is the ordinary game over (scripts/ui/game_over.gd).
##
## Built once by the HUD when it first sees the run is over (`hud.game_over` holds it, so every "a modal is up" check of the HUD treats it as the report
## card); it borrows the HUD's styles as the report card does. The numbers are the scenario's `report()`; the words are the data's (`Demo.copy`).
extends Control

const Fonts := preload("res://scripts/ui/fonts.gd")
const Demo := preload("res://scripts/demo.gd")

const MAX_W := 560.0

var hud
var sim
var panel: PanelContainer
var scroll: ScrollContainer
var col: VBoxContainer
var title_label: Label
var sub_label: Label
var full_label: Label
## "nights", "people", "kills", "trips" and "built" -> the Label with that number.
var stat_values := {}
var wishlist_button: Button
var again_button: Button
var title_button: Button


func setup(h, s) -> void:
	hud = h
	sim = s
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_layout)
	_layout()


func _build() -> void:
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
	col = hud._vbox(10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	var header: Label = hud._caps(Demo.copy("caps"), hud.PAPER_INK3)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(header)
	title_label = hud._label(Demo.copy("title"), Fonts.cond(700), 32, hud.PAPER_INK)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.x = 200
	col.add_child(title_label)
	sub_label = hud._label(Demo.copy("line"), Fonts.sans(400), 15, hud.PAPER_INK2)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.custom_minimum_size.x = 200
	col.add_child(sub_label)

	# what the run came to, as the ruled lines of the card
	var r: Dictionary = report()
	var lines: VBoxContainer = hud._vbox(0)
	lines.add_child(_line(hud.PAPER_INK))
	lines.add_child(_stat_line("nights", "%d of %d" % [int(r.nights), int(r.of)], "Nights held"))
	lines.add_child(_stat_line("people", _people_text(r), "People"))
	lines.add_child(_stat_line("kills", str(int(r.kills)), "The dead put down"))
	lines.add_child(_stat_line("trips", str(int(r.trips)), "Trips"))
	lines.add_child(_stat_line("built", str(int(r.built)), "Buildings built"))
	col.add_child(lines)

	full_label = hud._label(Demo.copy("full"), Fonts.sans(600), 15, hud.PAPER_INK)
	full_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	full_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	full_label.custom_minimum_size.x = 200
	col.add_child(full_label)

	var buttons: HFlowContainer = HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 8)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Demo.wishlist_url() != "":
		wishlist_button = hud._button("Wishlist", true, true)
		wishlist_button.tooltip_text = Demo.wishlist_url()
		wishlist_button.pressed.connect(_wishlist)
		buttons.add_child(wishlist_button)
	again_button = hud._button("Play again", wishlist_button == null, true)
	again_button.pressed.connect(_play_again)
	buttons.add_child(again_button)
	title_button = hud._button("Quit to title", false, true)
	title_button.pressed.connect(_quit_to_title)
	buttons.add_child(title_button)
	col.add_child(buttons)


## The run's numbers: the scenario's own report, or the same worked out here when the sim has none (a test's fake).
func report() -> Dictionary:
	if sim != null and sim.scenario != null and sim.scenario.has_method("report"):
		return sim.scenario.report()
	var alive := 0
	var lost := 0
	for p in sim.people:
		if p.dead or p.turned:
			lost += 1
		else:
			alive += 1
	return {"nights": 3, "of": 3, "alive": alive, "lost": lost, "kills": int(sim.kills), "trips": 0, "built": 0}


## "5 alive" or "5 alive, 1 lost".
static func _people_text(r: Dictionary) -> String:
	var text := "%d alive" % int(r.alive)
	if int(r.lost) > 0:
		text += ", %d lost" % int(r.lost)
	return text


## A ruled line across the card (the notebook's), in the paper's ink.
func _line(color: Color = Color(0, 0, 0, 0)) -> Control:
	var line := ColorRect.new()
	line.color = color if color.a > 0.0 else hud.PAPER_LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## One line of the card: the name of the number at the left, the number at the right, a rule under it. The number's Label is kept in stat_values[key].
func _stat_line(key: String, value: String, caption: String) -> Control:
	var box: VBoxContainer = hud._vbox(0)
	var row: HBoxContainer = hud._hbox(10)
	var cap: Label = hud._caps(caption, hud.PAPER_INK2)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	row.add_child(hud._spacer())
	var number: Label = hud._label(value, Fonts.cond(700), 24, hud.PAPER_INK)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(number)
	box.add_child(row)
	box.add_child(_line())
	stat_values[key] = number
	return box


# --------------------------------------------------------------------- buttons --

func _wishlist() -> void:
	var url := Demo.wishlist_url()
	if url != "":
		OS.shell_open(url)


## The same three nights again: the choice goes to the game, which reloads the scene on it (the demo is always its own seed and crew).
func _play_again() -> void:
	hud.start_run({"difficulty": 1, "seed": Demo.run_seed(), "crew": Demo.crew(), "demo": true})


## Back to the title screen: the shell's business (it sets hud.on_menu); with nobody listening the button does nothing.
func _quit_to_title() -> void:
	if hud.on_menu.is_valid():
		hud.on_menu.call()


func _layout() -> void:
	if panel == null:
		return
	panel.custom_minimum_size = Vector2(minf(size.x - 32.0, MAX_W), 0)
	# (the card scrolls when the window is too short for it)
	var room := maxf(160.0, size.y - 32.0 - 46.0)
	scroll.custom_minimum_size.y = minf(col.get_combined_minimum_size().y, room)
	_relayout.call_deferred()


## The wrapped words only know their height once they have a width: one more look a frame later.
func _relayout() -> void:
	if panel == null or not is_inside_tree():
		return
	var room := maxf(160.0, size.y - 32.0 - 46.0)
	var want := minf(col.get_combined_minimum_size().y, room)
	if not is_equal_approx(scroll.custom_minimum_size.y, want):
		scroll.custom_minimum_size.y = want
