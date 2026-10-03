## What the radio's views share (round 17, slice 1): the small buttons, the colours of the news by kind and the seconds a
## call has left. The views are `radio_verbs.gd` (the verbs for a contact), `call_view.gd` and `call_card.gd` (a call that
## waits for an answer), `news_panel.gd` (the log); the game HUD mounts them, and so can the raid HUD. Everything here is a
## static function: nothing keeps state.
##
## The views borrow the game HUD's looks the way the radio card and the raid HUD do: each is given the HUD (`host`) and asks
## it for its colours (`host.INK`), its frames and its helpers (`host._panel()`, `host._label()`...). They never load hud.gd
## themselves (the HUD loads them).
##
## What the views ask of a radio (scripts/sim/radio.gd is the real one; a test's or a place's stand-in has to have these):
##   VERBS, verb_name(verb), willingness(contact, verb), request(contact, verb, args), trust_of(p), tone_of(p), trust_why(p),
##   news (the log), open_calls(), answer(id, option_id), latest_id(), alarm(on), alarm_on, leader() and `sim` (with `clock_min`
##   and `min_per_sec`: the time left on a call is (due - clock_min) / min_per_sec seconds).
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")

## What a kind of news is called (the small capitals over a line of the log).
const KIND_NAME := {
	"attack": "Attack", "succession": "Lost", "sick": "Fever", "alarm": "Alarm", "recruit": "Arrival", "story": "Radio", "stranger": "At the gate",
}


## The colour of a kind of news (a word, readable on the panel): the dead at the wall and a death are red, a fever and the
## alarm amber, a new face green, a card of the storyteller blue, a stranger gold; anything else the dim chalk.
static func kind_color(host, kind: String) -> Color:
	match kind:
		"attack", "succession":
			return host.DANGER_TEXT
		"sick", "alarm":
			return host.WARN
		"recruit":
			return host.OK
		"story":
			return host.INFO
		"stranger":
			return host.ACCENT
	return host.INK2


static func kind_name(kind: String) -> String:
	return String(KIND_NAME.get(kind, kind.capitalize()))


## "14:05" from an hour of the day (a float).
static func clock_text(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


## The entry of the radio's log with this id ({} when there is none).
static func entry_of(radio, id: int) -> Dictionary:
	if radio == null:
		return {}
	for e in radio.news:
		if int(e.id) == id:
			return e
	return {}


## The label of an option of an entry ("" when there is no such option).
static func option_label(e: Dictionary, option_id: String) -> String:
	for o in e.get("options", []):
		if String(o.id) == option_id:
			return String(o.label)
	return ""


## The game's rate of time (game minutes a second): never 0, so that a division by it is safe.
static func rate(radio) -> float:
	var s = radio.get("sim")
	if s == null:
		return 3.0
	return maxf(float(s.min_per_sec), 0.001)


## How many seconds of the radio's own time a call has left (0 when it is over): (due - clock_min) / min_per_sec. `speed` (1, 2
## or 3) turns it into the seconds of the player's clock; at 0 (paused) it counts as 1, so the figure does not jump.
static func left_seconds(radio, e: Dictionary, speed: int = 1) -> float:
	var s = radio.get("sim")
	if s == null:
		return 0.0
	return maxf(0.0, (float(e.due) - float(s.clock_min)) / rate(radio) / float(maxi(speed, 1)))


## The whole wait of a call, in the same seconds (from the minute it was raised to the minute its default is taken).
static func total_seconds(radio, e: Dictionary, speed: int = 1) -> float:
	return maxf(0.001, (float(e.due) - float(e.t)) / rate(radio) / float(maxi(speed, 1)))


## A small button for a card: the HUD's own look (frame or flat), a word in the condensed bold, 12 px or more, never focused.
static func small_button(host, text: String, height: float = 28.0, size_px: int = 13) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_override("font", Fonts.cond(700, 0))
	b.add_theme_font_size_override("font_size", maxi(size_px, Fonts.MIN_PX))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, host.INK)
	b.add_theme_color_override("font_disabled_color", host.INK3)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var st: StyleBox = host._button_style(state, false, false, false)
		st.content_margin_top = 0
		st.content_margin_bottom = 0
		st.content_margin_left = 6
		st.content_margin_right = 6
		b.add_theme_stylebox_override(state, st)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b
