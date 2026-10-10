## HER NEEDS ON THE SCREEN (PH10): the small board under the gun's readout in the right column that says Ruth is hungry or thirsty. A VIEW only: it reads `sim.inv.needs()` and the belt and
## writes nothing of the rules.
##
## The Minimal HUD (the default) has it ONLY while she is hungry or thirsty (`hud_stage.gd`'s `needs` row of the stage table decides when it may be on at all; this board decides whether it has
## anything to say): one line for each need that has begun, a fork and knife or a glass, the word (Hungry, Starving, Thirsty, Parched), a short bar and what to do (the belt key that uses food or
## drink from the pack, or "none in the pack"). Nothing is there while she is fed. The Full HUD shows both meters always, fed or not.
##
## Colour is never alone: the amber and the red of the word, the bar and the icon are also a SHAPE (a triangle for hungry or thirsty, a diamond for starving or parched, as the crew's marks are)
## when Colour-blind markers is on, and always the WORD itself, and a longer bar as it gets worse. Reduce motion: the board comes and goes by the stage part's fade (which Reduce motion makes
## instant) and its one small pulse when a need begins is not made at all.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const Access := preload("res://scripts/access.gd")
const CbShapes := preload("res://scripts/ui/cb_shapes.gd")
const Prefs := preload("res://scripts/prefs.gd")
const InvApi := preload("res://scripts/ui/inv_api.gd")

const KINDS := ["hunger", "thirst"]
const ICONS := {"hunger": "hungry", "thirst": "thirsty"}
const WORDS := {"hungry": "Hungry", "starving": "Starving", "thirsty": "Thirsty", "parched": "Parched", "fed": "Fed"}
const TITLES := {"hunger": "Hunger", "thirst": "Thirst"}
## What the belt key does for each need.
const VERBS := {"hunger": "eat", "thirst": "drink"}
const PULSE_S := 0.9

var hud
var panel: PanelContainer
## kind -> {"box", "icon", "word", "bar", "hint", "mark"}
var rows := {}
## "when": only the needs that have begun; "full": both, always (the Full HUD).
var form := "when"
## At least one need has begun: what the stage part asks before it lets the board show.
var active := false
## The run has a pack (and so has needs of its own to show): false in every other game.
var live := false
## Set by the stage part (scripts/ui/hud_stage.gd), which then shows and hides the board; without one (a bare HUD) the board does it itself.
var managed := false
var _sig := ""
var _states := {"hunger": "fed", "thirst": "fed"}
var _pulse: Tween


func _init(hud_node) -> void:
	hud = hud_node
	_build()


func _build() -> void:
	panel = hud._panel(hud._style(hud.PANEL, 6, hud.LINE, true, "panel_slim"))
	panel.name = "NeedsBoard"
	panel.size_flags_horizontal = Control.SIZE_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var v: VBoxContainer = hud._vbox(3)
	for kind in KINDS:
		var box: HBoxContainer = hud._hbox(6)
		var icon: TextureRect = hud._icon(String(ICONS[kind]), 16, hud.INK2)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		var mark := CbShapes.Mark.new("triangle", hud.WARN, 4.0)
		mark.visible = false
		box.add_child(mark)
		var word: Label = hud._label("", Fonts.cond(700, 1), 14, hud.INK)
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(word)
		var bar = hud.Bar.new()
		bar.custom_minimum_size = Vector2(36, 5)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(bar)
		var hint: Label = hud._label("", Fonts.cond(600, 0), 12, hud.INK3)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(hint)
		v.add_child(box)
		rows[kind] = {"box": box, "icon": icon, "word": word, "bar": bar, "hint": hint, "mark": mark}
	panel.add_child(v)
	panel.visible = false
	hud.right_col.add_child(panel)
	# under the gun's readout (the clock, the readout, then this)
	var at := 2
	if hud.ammo_panel != null and hud.ammo_panel.get_parent() == hud.right_col:
		at = hud.ammo_panel.get_index() + 1
	hud.right_col.move_child(panel, at)


## Whether the board may be on the screen now: the run has a pack and she is hungry or thirsty (or the form is the Full HUD's).
func wants() -> bool:
	return live and (active or form == "full")


## Whether a row is on the screen in this form: a need that has begun (always, in the Full HUD's form).
func _row_on(kind: String, state: String) -> bool:
	return form == "full" or state != "fed"


## Every HUD update (ten a second): the numbers and the words. `sim` is the run.
func update(sim) -> void:
	if panel == null:
		return
	var inv = InvApi.inv(sim)
	var n: Dictionary = inv.needs() if inv != null and inv.has_method("needs") and InvApi.active(sim) else {}
	live = not n.is_empty()
	if n.is_empty():
		active = false
		if panel.visible and not managed:
			panel.visible = false
		return
	var markers := Access.markers()
	var text_k := Access.text_k()
	var sig := "%s|%s|%s|%s|%s|%d" % [form, n.hunger.state, n.thirst.state, str(snappedf(float(n.hunger.level), 0.02)), str(snappedf(float(n.thirst.level), 0.02)), int(markers) * 4 + int(text_k * 10.0)]
	var belt := "%d|%d|%s|%s" % [inv.slot_for("eat"), inv.slot_for("drink"), str(inv.has_use("eat")), str(inv.has_use("drink"))]
	sig += "|" + belt
	if sig == _sig:
		return
	_sig = sig
	var any := false
	var worse := false
	var tips: Array = []
	for kind in KINDS:
		var d: Dictionary = n[kind]
		var state := String(d.state)
		var row: Dictionary = rows[kind]
		var on := _row_on(kind, state)
		(row.box as Control).visible = on
		if on and state != "fed":
			any = true
		if state != String(_states[kind]) and state != "fed":
			worse = true
		_states[kind] = state
		if not on:
			continue
		var severe := state == "starving" or state == "parched"
		var col: Color = hud.DANGER_TEXT if severe else (hud.WARN if state != "fed" else hud.INK)
		var word := String(WORDS.get(state, state)) if state != "fed" else String(TITLES[kind])
		var lbl := row.word as Label
		lbl.text = word
		lbl.add_theme_color_override("font_color", col)
		lbl.add_theme_font_size_override("font_size", Access.scaled(14))
		(row.icon as TextureRect).modulate = col if state != "fed" else hud.INK2
		var bar = row.bar
		bar.value = float(d.level)
		bar.color = hud.DANGER if severe else (hud.WARN if state != "fed" else hud.OK)
		bar.queue_redraw()
		var mark = row.mark
		mark.visible = markers and state != "fed"
		if mark.visible:
			mark.set_kind("diamond" if severe else "triangle", hud.DANGER if severe else hud.WARN)
		(row.hint as Label).text = _hint(inv, kind, state)
		(row.hint as Label).add_theme_font_size_override("font_size", Access.scaled(12))
		tips.append(_tip(inv, kind, d))
	panel.tooltip_text = "\n\n".join(tips)
	active = any
	if not managed:
		panel.visible = wants()
	if worse and wants() and not Prefs.on("ui", "reduce_motion") and not Access.reduce_flashes():
		_pulse_once()


## "2: eat" when a belt key does it, "in the pack" when the pack has something but not on the belt, "none" when there is nothing to use.
func _hint(inv, kind: String, state: String) -> String:
	if state == "fed":
		return "Fed"
	var use := String(VERBS[kind])
	var slot: int = inv.slot_for(use)
	if slot >= 0:
		return "%d: %s" % [slot + 1, use]
	if inv.has_use(use):
		return "Tab: pack"
	return "none"


func _tip(inv, kind: String, d: Dictionary) -> String:
	var hours := int(float(d.h))
	var state := String(d.state)
	var thing := "meal" if kind == "hunger" else "drink"
	var lines: Array = []
	if state == "fed":
		lines.append("%s: fine. %d hours since the last proper %s." % [TITLES[kind], hours, thing])
	elif state == "starving" or state == "parched":
		lines.append("%s: it is costing you health. %d hours since the last proper %s." % [WORDS[state], hours, thing])
	else:
		lines.append("%s: you shoot and work worse. %d hours since the last proper %s." % [WORDS[state], hours, thing])
	var use := String(VERBS[kind])
	var slot: int = inv.slot_for(use)
	if slot >= 0:
		lines.append("Press %d to %s from your pack." % [slot + 1, use])
	elif inv.has_use(use):
		lines.append("Open the pack (Tab): right-click %s, then %s." % ["food" if kind == "hunger" else "a drink", "Eat" if kind == "hunger" else "Drink"])
	else:
		lines.append("Nothing to %s in the pack. Search the kitchens, or go home: the base serves a meal at 07:00, 13:00 and 19:00." % use)
	return "\n".join(lines)


## A short pulse of the board when a need begins or gets worse (not at all under Reduce motion or Reduce flashes).
func _pulse_once() -> void:
	if panel == null or not panel.is_inside_tree():
		return
	if _pulse != null:
		_pulse.kill()
	_pulse = panel.create_tween()
	for i in 2:
		_pulse.tween_property(panel, "self_modulate:a", 0.55, PULSE_S * 0.25)
		_pulse.tween_property(panel, "self_modulate:a", 1.0, PULSE_S * 0.25)
