## The radio verbs for one contact (round 17, slice 1): the player asks, they do not command. A button for each verb of the radio
## (Come with me, Hold here, Cover me, Search that, Go back, To the walls), the contact's last answer (what they say, or why they
## cannot) and, after a refusal that is not a hard one, an Insist button. It is a reusable piece: the game HUD's dock mounts it for the
## person selected in the yard, and the raid HUD for the squad and the people at the base.
##
##   var v := RadioVerbs.new(); parent.add_child(v)
##   v.setup(host, radio_getter, options)    # host: the HUD (lends its looks, see radio_kit.gd); radio_getter: Callable -> the radio or null
##   v.set_contact(person)                   # whom to ask (null: nobody); the buttons and the reason follow the radio's `willingness`
##   v.refresh()                             # brings the buttons in line with the game (the HUD does it with every update)
##   v.requested.connect(func(contact, verb, result): ...)   # a request went to the radio; `result` is what `radio.request` said
##
## `options` (all optional): "place" (true in a place: Search that is on; false in the yard, where there is nothing to search and it is
## off with its reason), "search_at" (a Callable -> a Vector2, or null: the container the host means by Search that), "hold_at" (the same
## for Hold here; without it the radio holds them where the player stands), "is_you" (a Callable(contact) -> bool: the contact is the
## player; the default reads `contact.player`).
##
## A verb is OFF (disabled, with the reason in the tooltip and shown in the answer line) when nobody can argue with it: the contact is
## down, gone, away, in a breakdown, leaving through the gate, or is the player. A SOFT refusal (bleeding, a fever, busy with a patient)
## is not off: the button can be pressed, the contact says why they cannot, in amber, and Insist asks again at a cost of trust.
## The box is the same height whatever it says (the answer line keeps its room), so the dock does not jump.
extends VBoxContainer

const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## A request went to the radio: `result` is `radio.request`'s answer, with "verb" added.
signal requested(contact, verb: String, result: Dictionary)

## The short names of the verbs, for the narrowest form (one row of six).
const SHORT := {"come": "Come", "hold": "Hold", "cover": "Cover", "search": "Search", "back": "Back", "post": "Walls"}
## The stance each verb puts a person in, once it has taken effect ("back" and "post" end a stance: none to watch).
const STANCE_OF := {"come": "follow", "hold": "hold", "cover": "cover", "search": "search"}
## What each verb does, for the tooltip ("%s" is the contact's first name).
const WORDS := {
	"come": "Come with me: %s follows you",
	"hold": "Hold here: %s stays where you stand now",
	"cover": "Cover me: %s stands behind you, watching your back",
	"search": "Search that: %s goes and searches what you point at",
	"back": "Go back: %s goes back to what they were doing",
	"post": "To the walls: %s goes to their post on the wall",
}

var host
var options := {}
var contact = null
## Verb to its button, in the radio's order.
var buttons := {}
var grid: GridContainer
var reply: Label
var insist_button: Button
## The last answer to the contact: {"who", "verb", "ok", "line", "why", "hard"}; {} when they have not been asked since they were picked.
var last := {}
var columns := 3
var short := false
var _radio_getter: Callable
var _built := false
var _reply_row: HBoxContainer


func setup(host_hud: Object, radio_getter: Callable, opts: Dictionary = {}) -> void:
	host = host_hud
	_radio_getter = radio_getter
	options = opts
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid = GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid)
	_reply_row = host._hbox(6)
	_reply_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reply = host._label("", Fonts.sans(600), 13, host.INK)
	reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reply.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	reply.custom_minimum_size.x = 90
	reply.mouse_filter = Control.MOUSE_FILTER_PASS
	_reply_row.add_child(reply)
	insist_button = RadioKit.small_button(host, "Insist", 26.0, 13)
	insist_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	insist_button.tooltip_text = "Insist: push them to do it anyway. It costs their trust and their mood, and they will do it grudgingly"
	insist_button.visible = false
	insist_button.pressed.connect(insist)
	_reply_row.add_child(insist_button)
	add_child(_reply_row)
	_apply_form()


func _radio():
	return _radio_getter.call() if _radio_getter.is_valid() else null


## The verbs the buttons are for, in order.
func verbs_shown() -> Array:
	return buttons.keys()


## Makes the buttons the first time there is a radio to say what the verbs are.
func _ensure_buttons() -> void:
	if not buttons.is_empty():
		return
	var radio = _radio()
	if radio == null:
		return
	for verb in radio.VERBS:
		var b: Button = RadioKit.small_button(host, "", 30.0, 13)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(press.bind(String(verb)))
		grid.add_child(b)
		buttons[String(verb)] = b
	_apply_form()


## The shape of the box: how many buttons to a row, and whether they say their short names ("Come") or their whole ones ("Come with
## me") and the answer is one line. The dock picks the form the room allows.
func set_form(cols: int, use_short: bool) -> void:
	if cols == columns and use_short == short:
		return
	columns = cols
	short = use_short
	_apply_form()


func _apply_form() -> void:
	if grid == null:
		return
	grid.columns = maxi(1, columns)
	var radio = _radio()
	for verb in buttons:
		var b: Button = buttons[verb]
		var full: String = String(radio.verb_name(verb)) if radio != null else String(verb)
		b.text = String(SHORT.get(verb, full.get_slice(" ", 0))) if short else full
		b.custom_minimum_size.x = 46.0 if short else (100.0 if columns <= 2 else 90.0)
	# the answer line keeps its room: three lines beside the panel, two above it, one in the narrowest form
	var line_h := 16.0
	var f: Font = reply.get_theme_font("font")
	if f != null:
		line_h = ceilf(f.get_height(reply.get_theme_font_size("font_size")))
	var lines := 1 if short else (3 if columns <= 2 else 2)
	reply.custom_minimum_size.y = line_h * float(lines)
	reply.autowrap_mode = TextServer.AUTOWRAP_OFF if short else TextServer.AUTOWRAP_WORD_SMART
	reply.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if short else TextServer.OVERRUN_NO_TRIMMING
	reply.clip_text = short


## Whom the buttons ask. A different person starts with no answer; the same one keeps theirs.
func set_contact(p) -> void:
	if p != contact:
		contact = p
		last = {}
	_ensure_buttons()
	refresh()


func _is_you(p) -> bool:
	var g = options.get("is_you")
	if g is Callable and g.is_valid():
		return bool(g.call(p))
	return p != null and bool(p.get("player"))


## What a verb is now for the contact: {"enabled", "why", "soft" (a refusal that insisting can override), "w" (the radio's willingness)}.
func verb_state(verb: String) -> Dictionary:
	var out := {"enabled": true, "why": "", "soft": false, "w": {}}
	var radio = _radio()
	if contact == null or radio == null:
		out.enabled = false
		return out
	if _is_you(contact):
		out.enabled = false
		out.why = "That is you"
		return out
	var w: Dictionary = radio.willingness(contact, verb)
	out.w = w
	if not bool(w.ok):
		out.why = String(w.why)
		if bool(w.hard):
			out.enabled = false
		else:
			out.soft = true
	if out.enabled and verb == "search" and not bool(options.get("place", false)):
		out.enabled = false
		out.why = "Nothing to search here: Search that is for a place, when you are out on a trip"
	return out


func _secs(s: float) -> String:
	return "%d s" % int(s) if absf(s - roundf(s)) < 0.05 else "%.1f s" % s


## The buttons, their tooltips and the answer line follow the contact and the game.
func refresh() -> void:
	var radio = _radio()
	_ensure_buttons()
	visible = contact != null and radio != null
	if not visible:
		return
	var first := String(contact.first)
	var reason := ""
	var all_off := true
	for verb in buttons:
		var b: Button = buttons[verb]
		var st := verb_state(verb)
		# (Search that is for a place: in the yard there is nothing to search, so it is not offered; it stays off, with its reason)
		b.visible = verb != "search" or bool(options.get("place", false))
		b.disabled = not st.enabled
		var tip := String(WORDS.get(verb, String(verb))).replace("%s", first)
		if not st.enabled:
			tip += "\nNot now: %s" % st.why
			if reason == "" and verb != "search":
				reason = String(st.why)
		elif st.soft:
			tip += "\n%s\nAsk, and they will say so. Insist overrides it, at a cost of trust" % st.why
			all_off = false
		else:
			tip += "\nAnswers in about %s (%s)" % [_secs(float(st.w.get("delay_s", 0.0))), String(st.w.get("tone", ""))] if not st.w.is_empty() else ""
			all_off = false
		if b.tooltip_text != tip:
			b.tooltip_text = tip
	# an answer they gave is kept while they are the contact and it still holds; with none, a reason that stops every verb shows by itself
	if not last.is_empty() and _stale(radio):
		last = {}
	var text := ""
	var color: Color = host.INK
	var show_insist := false
	if not last.is_empty() and String(last.who) == String(contact.id):
		if bool(last.ok):
			text = "%s: %s" % [first, String(last.line)]
			color = host.OK if String(last.get("tone", "")) == "willing" else host.INK
		else:
			text = String(last.why)
			color = host.WARN
			show_insist = not bool(last.hard) and buttons.has(String(last.verb)) and not buttons[String(last.verb)].disabled
	elif _is_you(contact) or (all_off and reason != ""):
		text = "That is you" if _is_you(contact) else reason
		color = host.INK2 if _is_you(contact) else host.WARN
	if reply.text != text:
		reply.text = text
		reply.tooltip_text = text if short else ""
	reply.add_theme_color_override("font_color", color)
	insist_button.visible = show_insist


## Whether the last answer no longer says anything true about the contact: they cannot be asked at all now (down, away, leaving, in a
## breakdown: a refusal nobody can argue with, unless it is the same one the answer gave) or, having done what they were asked, they
## no longer do (their stance ended: they went back to their work, were sent elsewhere). While the request waits for its delay the
## stance is not yet there: the answer stays until it has been seen.
func _stale(radio) -> bool:
	if _is_you(contact):
		return true
	var verb := String(last.verb)
	var w: Dictionary = radio.willingness(contact, verb)
	if bool(w.get("hard", false)) and (bool(last.ok) or String(w.get("why", "")) != String(last.get("why", ""))):
		return true
	if bool(last.ok) and STANCE_OF.has(verb):
		var now = contact.get("stance")
		if String(now if now != null else "") == String(STANCE_OF[verb]):
			last["held"] = true
		elif bool(last.get("held", false)):
			return true
	return false


## Asks the contact to do what `verb` says (what a click on its button does). Returns `radio.request`'s answer with "verb" added ({}
## with nobody to ask).
func press(verb: String) -> Dictionary:
	return _ask(verb, false)


## Asks again, pushing: the refusal that was not a hard one is overridden, at a cost of trust. (A click order asks again for the same spot.)
func insist() -> Dictionary:
	if last.is_empty() or bool(last.ok):
		return {}
	return _ask(String(last.verb), true, last.get("extra", {}))


## A click order (round 23, scripts/aim_mode.gd): the same ask as the verb's button, but with what the click points at in place of what the
## button means. `extra`: "at" (a Vector2: the spot of "hold", the container of "search") or "post" (a night post's id, for "to the walls": the
## post becomes theirs, asked of the radio like the roster does, and they go to it). The answer, the dock's reply line and the Insist button
## are the button's own.
func order(verb: String, extra: Dictionary = {}) -> Dictionary:
	return _ask(verb, false, extra)


func _ask(verb: String, push: bool, extra: Dictionary = {}) -> Dictionary:
	var radio = _radio()
	if contact == null or radio == null:
		return {}
	var args := {}
	if verb == "hold":
		var at = extra.get("at")
		if typeof(at) != TYPE_VECTOR2:
			at = _point("hold_at")
		if at == null and radio.has_method("leader"):
			var lead = radio.leader()
			if lead != null:
				at = Vector2(lead.x, lead.y)
		if at != null:
			args["at"] = at
	elif verb == "search":
		var at = extra.get("at")
		if typeof(at) != TYPE_VECTOR2:
			at = _point("search_at")
		if at != null:
			args["at"] = at
	if push:
		args["insist"] = true
	var result: Dictionary
	var post_id := String(extra.get("post", ""))
	if verb == "post" and post_id != "" and radio.has_method("request_post") and not _holds_post(radio, post_id):
		# (to a post that is not theirs: it is asked first, as the roster asks, with its own reasons; and then they go)
		result = radio.request_post(contact, post_id, {"insist": true} if push else {}).duplicate()
		if bool(result.get("ok", false)):
			result = radio.request(contact, "post", {}).duplicate()
			result["insisted"] = push
	else:
		result = radio.request(contact, verb, args).duplicate()
	result["verb"] = verb
	# whether insisting could change the refusal is the ANSWER's word (a place refuses some things before the radio is asked at all:
	# "Already searched", "can't get there"); an answer that does not say is judged by the radio's willingness as it always was
	var hard: bool
	if result.has("hard"):
		hard = bool(result.hard)
	else:
		hard = bool(radio.willingness(contact, verb).get("hard", false))
	last = {"who": String(contact.id), "verb": verb, "ok": bool(result.ok), "line": String(result.get("line", "")), "why": String(result.get("why", "")),
		"hard": hard, "tone": String(result.get("tone", "")), "extra": extra.duplicate()}
	refresh()
	requested.emit(contact, verb, result)
	return result


## Whether the contact already holds this night post.
func _holds_post(radio, post_id: String) -> bool:
	var sim = radio.get("sim")
	var jobs = sim.get("jobs") if sim != null else null
	return jobs != null and String(jobs.post_ids.get(String(contact.id), "")) == post_id


func _point(key: String):
	var g = options.get(key)
	if g is Callable and g.is_valid():
		var v = g.call()
		if typeof(v) == TYPE_VECTOR2:
			return Vector2(v)
	return null
