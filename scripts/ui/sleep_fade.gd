## The fade of the night's sleep (One House, WP7): when the avatar goes to bed (the event `{"type": "sleep", "on": true}`, scripts/town/sleep.gd) the screen fades to black
## while the rules run ahead to dawn a frame at a time; when they wake (`{"type": "sleep", "on": false, "why": ""}`) the words "You slept until dawn" (or the reason they
## were woken: "Something is near") are held a moment on the black and it fades back to the morning. The black is under the HUD's boards, so the clock and the stores stay
## readable as the hours go by.
##
## A VIEW PART of the town's facade (`on_ready(main)`, `on_frame(dt)`, `on_event(e)`, `modal()`): `modal()` is true while the screen is black, so the avatar's hands are off
## (WP1's `avatar_hands_off` asks it). With reduced motion on there is no fade: the black is simply there and gone.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")

## Seconds to go dark, to hold the words once awake, and to come back.
const FADE_IN_S := 0.9
const HOLD_S := 1.1
const FADE_OUT_S := 1.3
const DARK := Color(0.015, 0.02, 0.03, 1.0)
const DEFAULT_WORDS := "You slept until dawn"

var main
var hud
var cover: ColorRect
var title: Label
var sub: Label
## 0 (clear) to 1 (black), where the fade is now and where it is going.
var alpha := 0.0
var target := 0.0
var sleeping := false
var hold_left := 0.0
var words := ""


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	cover = ColorRect.new()
	cover.color = DARK
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.modulate.a = 0.0
	cover.visible = false
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	title = hud._label("", Fonts.cond(700, 4), 36, hud.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	sub = hud._label("", Fonts.sans(400), 16, hud.INK2)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	cover.add_child(col)
	hud.add_child(cover)
	# (under the HUD's boards, over the world)
	hud.move_child(cover, 0)


func on_event(e: Dictionary) -> void:
	if cover == null or String(e.get("type", "")) != "sleep":
		return
	if bool(e.get("on", false)):
		sleeping = true
		hold_left = 0.0
		target = 1.0
		words = ""
		title.text = "SLEEPING"
		sub.text = ""
		cover.visible = true
	elif sleeping or alpha > 0.05:
		sleeping = false
		words = words_for(String(e.get("why", "")))
		title.text = words.to_upper()
		var hours := roundi(float(e.get("hours", 0.0)))
		sub.text = ("%d hours" % hours) if hours >= 2 and words != "" else ""
		hold_left = HOLD_S
		target = 0.0
		cover.visible = true
		# (the black is whole while the words are held, even when the sleep was short)
		alpha = maxf(alpha, 0.9)
		_apply()


## What to say on waking, from the module's reason ("dawn", "woken", "down", "over", or a sentence such as "Something is near").
static func words_for(why: String) -> String:
	match why.strip_edges():
		"", "dawn":
			return DEFAULT_WORDS
		"woken":
			return "You woke"
		"down":
			return "You are hurt"
		"over":
			return ""
		_:
			return why.strip_edges()


func on_frame(dt: float) -> void:
	if cover == null:
		return
	var calm: bool = hud.has_method("_calm") and bool(hud._calm())
	if hold_left > 0.0 and not sleeping:
		hold_left = maxf(0.0, hold_left - dt)
		alpha = 1.0
	elif target > alpha:
		alpha = 1.0 if calm else minf(1.0, alpha + dt / FADE_IN_S)
	elif target < alpha:
		alpha = 0.0 if calm else maxf(0.0, alpha - dt / FADE_OUT_S)
	_apply()


func _apply() -> void:
	cover.modulate.a = alpha
	if alpha <= 0.0 and not sleeping and hold_left <= 0.0:
		cover.visible = false


## True while the screen is black enough to hide the game (the avatar's hands are off).
func modal() -> bool:
	return sleeping or (alpha > 0.5 and target < alpha and hold_left > 0.0)


## Whether the screen is dark or going dark or holding the words (for the tests and the camera).
func active() -> bool:
	return sleeping or alpha > 0.0 or hold_left > 0.0
