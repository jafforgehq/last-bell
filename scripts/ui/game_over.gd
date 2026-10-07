## The screen over the game when the run is over (sim.over is "defeat" or
## "victory"): a dimmed window and, on notebook paper, the REPORT CARD: the verdict, the
## run's numbers as ruled lines, how each survivor ended (a hall-pass badge each), and the
## choice to start again, pick up the last save or go back to the main menu. Built once by
## the HUD when it first sees sim.over set; it borrows the HUD's styles.
extends Control

const GD := preload("res://scripts/game_data.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")

## (The school's words; the town's are the data's `words.defeat`, see `_town_defeat`.)
const TITLES := {"defeat": "Everyone is gone"}
const SUBTITLES := {"defeat": "Nobody is left to ring the bell.", "victory": "A convoy is on the road at dawn. You held."}
const MAX_W := 560.0
## The numbers a run's length is spoken in: "The thirty days are over".
const ONES := ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
const TENS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
## The green of "Alive" on paper (the board's green is too pale for it).
const ALIVE_INK := Color("#3b6a1e")

var hud
var sim
var panel: PanelContainer
var title_label: Label
## The line under the verdict (round 10: a campaign says which season a defeat came in).
var sub_label: Label
## "days", "kills" and "lost" -> the Label with that number.
var stat_values := {}


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
	var col: VBoxContainer = hud._vbox(12)
	panel.add_child(col)

	# the head of the form, then the verdict
	var header: Label = hud._caps("The record" if _town() else "Report card", hud.PAPER_INK3)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(header)
	var result := String(sim.over)
	title_label = hud._label(_title(result), Fonts.cond(700), 38, hud.PAPER_INK)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title_label)
	var sub: Label = hud._label(_subtitle(result), Fonts.sans(400), 15, hud.PAPER_INK2)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label = sub
	col.add_child(sub)

	# the numbers, as the ruled lines of the card
	var died := 0
	for p in sim.people:
		if _fate(p) == "Died" or _fate(p) == "Turned":
			died += 1
	var numbers := [
		["days", str(_days_survived()), "Days survived"],
		["kills", str(int(sim.kills)), "The dead put down" if _town() else "Walkers put down"],
		["lost", "%d of %d" % [died, sim.people.size()], "Died or turned"],
	]
	var lines: VBoxContainer = hud._vbox(0)
	lines.add_child(_line(hud.PAPER_INK))
	for n in numbers:
		lines.add_child(_stat_line(n[0], n[1], n[2]))
	col.add_child(lines)

	# how each of them ended
	var crew := HFlowContainer.new()
	crew.alignment = FlowContainer.ALIGNMENT_CENTER
	crew.add_theme_constant_override("h_separation", 10)
	crew.add_theme_constant_override("v_separation", 8)
	crew.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in sim.people:
		crew.add_child(_survivor(p))
	col.add_child(crew)

	var buttons: HBoxContainer = hud._hbox(10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var again: Button = hud._button("New game", true, true)
	again.pressed.connect(_new_game)
	buttons.add_child(again)
	var save: String = hud.last_save()
	if save != "":
		var load_button: Button = hud._button("Load last save", false, true)
		load_button.pressed.connect(_load_save.bind(save))
		buttons.add_child(load_button)
	var menu_button: Button = hud._button("Main menu", false, true)
	menu_button.pressed.connect(_main_menu)
	buttons.add_child(menu_button)
	col.add_child(buttons)


## A ruled line across the card (the notebook's), in the paper's ink.
func _line(color: Color = Color(0, 0, 0, 0)) -> Control:
	var line := ColorRect.new()
	line.color = color if color.a > 0.0 else hud.PAPER_LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## One line of the card: the name of the number at the left, the number at the right, a rule
## under it. The number's Label is kept in stat_values[key].
func _stat_line(key: String, value: String, caption: String) -> Control:
	var box: VBoxContainer = hud._vbox(0)
	var row: HBoxContainer = hud._hbox(10)
	var cap: Label = hud._caps(caption, hud.PAPER_INK2)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	row.add_child(hud._spacer())
	var number: Label = hud._label(value, Fonts.cond(700), 32, hud.PAPER_INK)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(number)
	box.add_child(row)
	box.add_child(_line())
	stat_values[key] = number
	return box


## One survivor on a hall-pass badge: their picture (dim if they are gone), name and how they ended.
func _survivor(p) -> Control:
	var fate := _fate(p)
	var badge: PanelContainer = hud._panel(_badge_style(hud._card_inset()))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: VBoxContainer = hud._vbox(3)
	var pic := TextureRect.new()
	pic.texture = hud.portrait_of(p)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(54, 54)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fate != "Alive":
		pic.modulate = Color(0.4, 0.4, 0.4)
	col.add_child(pic)
	var name_label: Label = hud._label(p.first, Fonts.cond(600), 13, hud.INK if fate == "Alive" else hud.INK3)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	var color: Color = hud.OK if fate == "Alive" else (hud.DANGER_TEXT if fate == "Turned" else hud.INK2)
	var fate_label: Label = hud._label(fate, Fonts.sans(600), 12, color)
	fate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(fate_label)
	badge.add_child(col)
	return badge


## The badge's style with room round its contents: the rim of the frame, or a few pixels flat.
func _badge_style(inset: Vector4) -> StyleBox:
	var s: StyleBox = hud._card_style(false)
	s.content_margin_left = maxf(inset.x, 4.0) + 2.0
	s.content_margin_right = maxf(inset.z, 4.0) + 2.0
	s.content_margin_top = maxf(inset.y, 4.0) + 2.0
	s.content_margin_bottom = maxf(inset.w, 4.0) + 3.0
	return s


## "Alive", "Died", "Turned" or "Left" (sent out through the gate).
func _fate(p) -> String:
	if p.turned:
		return "Turned"
	if p.dead:
		return "Left" if p.away is Dictionary and String(p.away.get("kind", "")) == "exile" else "Died"
	return "Alive"


## The headline for how the run ended. A win names the length of the run ("The
## thirty days are over"), which is the scenario's, not a fixed number.
func _title(result: String) -> String:
	if _town() and result == "defeat":
		return _town_defeat()[0]
	if result == "victory":
		if _campaign():
			return "The seasons are over"
		return "The %s days are over" % _number_word(int(sim.scenario.total_days()))
	return String(TITLES.get(result, "The run is over"))


## Whether the run is the One House town's.
func _town() -> bool:
	return sim.has_method("is_one_house") and sim.is_one_house()


## The town's defeat, [headline, line] from the data (`words.defeat`: "The house is empty", "Nobody is left to hold it").
func _town_defeat() -> Array:
	# (before the claim there is no house to be empty: the scenario says "Ruth did not make it", `words.defeat_no_base`)
	if sim.scenario != null and sim.scenario.has_method("defeat_words"):
		return sim.scenario.defeat_words()
	var words = OneHouse.data().get("words", {}).get("defeat", [])
	if words is Array and words.size() >= 2:
		return [String(words[0]), String(words[1])]
	return ["The house is empty", "Nobody is left to hold it"]


## Whether the run was the campaign of four seasons (round 10).
func _campaign() -> bool:
	return sim.get("seasons") != null and sim.seasons.campaign


## The line under the verdict. The thirty-night game keeps its old words; a campaign's victory says it held through
## the seasons, and its defeat says which season it came in and on which day of the game ("You fell in Winter, on
## day 41").
func _subtitle(result: String) -> String:
	var line := String(SUBTITLES.get(result, ""))
	if _town() and result == "defeat":
		if sim.scenario != null and sim.scenario.has_method("has_base") and not sim.scenario.has_base():
			return "%s." % _town_defeat()[1]    # (no house yet: the line already says it)
		return "%s. The dead are still out there." % _town_defeat()[1]    # (One House: there is no bell to ring)
	if not _campaign():
		return line
	if result == "victory":
		return "A convoy is on the road at dawn. You held through all four seasons."
	if result == "defeat":
		return "You fell in %s, on day %d. %s" % [String(sim.seasons.current().name), int(sim.scenario.day()), line]
	return line


## 30 -> "thirty", 21 -> "twenty-one"; a number past 99 stays in digits.
func _number_word(n: int) -> String:
	if n < 1 or n > 99:
		return str(n)
	if n < 20:
		return ONES[n]
	var word: String = TENS[floori(n / 10.0)]
	return word if n % 10 == 0 else "%s-%s" % [word, ONES[n % 10]]


## A day counts as survived once it has reached the night; a win is the whole run.
func _days_survived() -> int:
	var total: int = sim.scenario.total_days()
	if sim.over == "victory":
		return total
	var day: int = sim.scenario.day()
	return clampi(day - 1 if sim.phase == "day" else day, 0, total)


func _new_game() -> void:
	var meta := {"difficulty": int(sim.difficulty), "seed": randi()}
	# a town run (One House) begins as a town run again, alone
	if sim.has_method("is_one_house") and sim.is_one_house():
		meta["town"] = true
		hud.start_run(meta)
		return
	# a run that began with a small crew (recruits.gd) begins that way again
	if sim.get("recruits") != null and sim.recruits.small:
		meta["crew"] = 3
	# and one that was the campaign of four seasons begins as that again
	if _campaign():
		meta["campaign"] = true
	hud.start_run(meta)


func _load_save(path: String) -> void:
	hud.start_run({"load": path})


## Back to the title screen: the shell's business (it sets hud.on_menu); with nobody
## listening the button does nothing.
func _main_menu() -> void:
	if hud.on_menu.is_valid():
		hud.on_menu.call()


func _layout() -> void:
	if panel != null:
		panel.custom_minimum_size = Vector2(minf(size.x - 32.0, MAX_W), 0)
