## The screen over the game when the run is over (sim.over is "defeat" or
## "victory"): a dimmed window, a title, the run's numbers, how each survivor
## ended, and the choice to start again or pick up the last save. Built once by
## the HUD when it first sees sim.over set; it borrows the HUD's styles.
extends Control

const GD := preload("res://scripts/game_data.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

const TITLES := {"defeat": "Everyone is gone", "victory": "Rescued"}
const SUBTITLES := {"defeat": "Nobody is left to ring the bell.", "victory": "The rescue came at dawn. You held the wall."}
const MAX_W := 560.0

var hud
var sim
var panel: PanelContainer
var title_label: Label
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
	dim.color = Color(0.03, 0.025, 0.02, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var style: StyleBoxFlat = hud._style(Color(hud.PANEL, 0.97), 8, hud.LINE2)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel = hud._panel(style)
	center.add_child(panel)
	var col: VBoxContainer = hud._vbox(14)
	panel.add_child(col)

	var result := String(sim.over)
	title_label = hud._label(TITLES.get(result, "The run is over"), Fonts.cond(700), 38, hud.INK)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title_label)
	var sub: Label = hud._label(SUBTITLES.get(result, ""), Fonts.sans(400), 15, hud.INK2)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	col.add_child(_line())

	var stats: HBoxContainer = hud._hbox(14)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	var died := 0
	for p in sim.people:
		if _fate(p) == "Died" or _fate(p) == "Turned":
			died += 1
	var numbers := [
		["days", str(_days_survived()), "Days survived"],
		["kills", str(int(sim.kills)), "Walkers put down"],
		["lost", "%d of %d" % [died, sim.people.size()], "Died or turned"],
	]
	for n in numbers:
		var block: VBoxContainer = hud._vbox(2)
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value: Label = hud._label(n[1], Fonts.cond(700), 34, hud.INK)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		block.add_child(value)
		var cap: Label = hud._caps(n[2])
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		block.add_child(cap)
		stats.add_child(block)
		stat_values[n[0]] = value
	col.add_child(stats)
	col.add_child(_line())

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
	var again: Button = hud._button("New game", true)
	again.pressed.connect(_new_game)
	buttons.add_child(again)
	var save: String = hud.last_save()
	if save != "":
		var load_button: Button = hud._button("Load last save", false)
		load_button.pressed.connect(_load_save.bind(save))
		buttons.add_child(load_button)
	col.add_child(buttons)


func _line() -> Control:
	var line := ColorRect.new()
	line.color = hud.LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## One survivor: their picture (dim if they are gone), name and how they ended.
func _survivor(p) -> Control:
	var fate := _fate(p)
	var col: VBoxContainer = hud._vbox(3)
	var pic := TextureRect.new()
	pic.texture = GD.tex(hud.data.portraits[p.id])
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
	var color: Color = hud.OK if fate == "Alive" else (hud.DANGER if fate == "Turned" else hud.INK2)
	var fate_label: Label = hud._label(fate, Fonts.sans(600), 12, color)
	fate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(fate_label)
	return col


## "Alive", "Died", "Turned" or "Left" (sent out through the gate).
func _fate(p) -> String:
	if p.turned:
		return "Turned"
	if p.dead:
		return "Left" if p.away is Dictionary and String(p.away.get("kind", "")) == "exile" else "Died"
	return "Alive"


## A day counts as survived once it has reached the night; a rescue is the whole run.
func _days_survived() -> int:
	var total: int = sim.scenario.total_days()
	if sim.over == "victory":
		return total
	var day: int = sim.scenario.day()
	return clampi(day - 1 if sim.phase == "day" else day, 0, total)


func _new_game() -> void:
	hud.start_run({"difficulty": int(sim.difficulty), "seed": randi()})


func _load_save(path: String) -> void:
	hud.start_run({"load": path})


func _layout() -> void:
	if panel != null:
		panel.custom_minimum_size = Vector2(minf(size.x - 32.0, MAX_W), 0)
