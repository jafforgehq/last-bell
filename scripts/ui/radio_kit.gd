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
	"errand": "Errand", "build": "Built",
	"road": "Road",
	# round 20, the community: an idea someone brings, a friendship or a couple, a falling out, a title earned
	"idea": "Idea", "bond": "People", "rift": "Falling out", "title": "Known for",
	# round 19, the nights: a wall that is going, a plated brute coming, a breach, the night itself (the forecast's call), the notice of a
	# Big Night a day ahead, the road home of a trip that is out at dusk
	"going": "Wall", "brute": "Brute", "breach": "Breach", "night": "Night", "forecast": "Forecast", "night_road": "Road",
}


## Makes a wrapping control measure as it will be laid out at width `w`, laid out or not (a hidden one never is, and a label that has no
## width measures as tall as the words can be, one to a line): its width first, then its least width (a control that has already been given a
## height keeps it when only the least is set).
static func wrap_at(c: Control, w: float) -> void:
	if not is_equal_approx(c.size.x, w):
		c.size = Vector2(w, c.size.y)
	if not is_equal_approx(c.custom_minimum_size.x, w):
		c.custom_minimum_size.x = w


## The colour of a kind of news (a word, readable on the panel): the dead at the wall (a wall going, a brute, a breach) and a death are
## red, a fever, the alarm and a falling out amber, a new face, a friendship and a building that went up green, a card of the
## storyteller, an idea, an errand and the night's notices (the forecast, the night, the road) blue, a stranger and a title earned
## gold; anything else the dim chalk.
static func kind_color(host, kind: String) -> Color:
	match kind:
		"attack", "succession", "going", "brute", "breach":
			return host.DANGER_TEXT
		"sick", "alarm", "rift":
			return host.WARN
		"recruit", "build", "bond":
			return host.OK
		"story", "errand", "road", "idea", "night", "forecast", "night_road":
			return host.INFO
		"stranger", "title":
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


## What the voice of the community thinks of an open call (round 20): the initiative module's `voice_opinion(e)`, as it gives it
## ({"who", "first", "title", "option", "line"}), or {} when there is no such module, it is switched off (no avatar, Orientation
## Day), it has no opinion, or `radio` is null. The radio's own `sim` is where the module is; a stand-in radio with no `sim` has none.
static func opinion_of(radio, e: Dictionary) -> Dictionary:
	if radio == null:
		return {}
	return opinion_for(radio.get("sim"), e)


## The words of an opinion ("Ana, the medic: treat them."), or "" when it has none (an answer whose line is not text is none).
static func line_of(opinion: Dictionary) -> String:
	var line = opinion.get("line", "")
	return String(line).strip_edges() if line is String else ""


## The words of the voice's opinion of an open call ("" when there is none).
static func opinion_text(radio, e: Dictionary) -> String:
	return line_of(opinion_of(radio, e))


## The same, asked of the sim itself.
static func opinion_for(sim, e: Dictionary) -> Dictionary:
	if sim == null or e.is_empty():
		return {}
	var m = sim.get("initiative")
	if m == null or not m.has_method("voice_opinion"):
		return {}
	if m.has_method("active") and not bool(m.active()):
		return {}
	var got = m.voice_opinion(e)
	return got if got is Dictionary else {}


## How urgent a kind of call is, lower first (round 19, the card shows the most urgent open call and not the oldest): 0 a wall that is down
## or going, 1 a brute on its way and the old call of a wall under attack, 2 anything else (a fever, the night's call, an idea).
const URGENCY := {"breach": 0, "going": 0, "brute": 1, "attack": 1}


static func urgency_of(kind: String) -> int:
	return int(URGENCY.get(kind, 2))


## The call of a list of open calls (the radio's `open_calls()`, oldest first) that waits for an answer most urgently: the lowest urgency
## of its kind, then the least time left (`due`), then the oldest. {} for none.
static func most_urgent(calls: Array) -> Dictionary:
	var best := {}
	for e in calls:
		if best.is_empty():
			best = e
			continue
		var ua := urgency_of(String(e.get("kind", "")))
		var ub := urgency_of(String(best.get("kind", "")))
		if ua < ub or (ua == ub and float(e.get("due", 0.0)) < float(best.get("due", 0.0)) - 1.0e-9):
			best = e
	return best


## The open calls in the order of `most_urgent`, the most urgent first (the News lists them so, and the card is the first of them).
static func by_urgency(calls: Array) -> Array:
	var rest: Array = calls.duplicate()
	var out: Array = []
	while not rest.is_empty():
		var best := most_urgent(rest)
		out.append(best)
		rest.erase(best)
	return out


## The game's rate of time (game minutes a second): never 0, so that a division by it is safe.
static func rate(radio) -> float:
	var s = radio.get("sim")
	if s == null:
		return 3.0
	return maxf(float(s.min_per_sec), 0.001)


## How many seconds of the radio's own time a call has left (0 when it is over): (due - clock_min) / min_per_sec. `speed` is
## how many times the game's normal pace the player's clock runs at: 1, 2 or 3 in the yard, a THIRD in a place (the base runs at
## one game minute a second there, `PlaceFlow.PLACE_PACE`); it turns the radio's time into the seconds of the player's clock. At
## 0 or less (paused) it counts as 1, so the figure does not jump.
static func left_seconds(radio, e: Dictionary, speed: float = 1.0) -> float:
	var s = radio.get("sim")
	if s == null:
		return 0.0
	return maxf(0.0, (float(e.due) - float(s.clock_min)) / rate(radio) / _pace(speed))


## The whole wait of a call, in the same seconds (from the minute it was raised to the minute its default is taken).
static func total_seconds(radio, e: Dictionary, speed: float = 1.0) -> float:
	return maxf(0.001, (float(e.due) - float(e.t)) / rate(radio) / _pace(speed))


static func _pace(speed: float) -> float:
	return speed if speed > 0.0 else 1.0


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
