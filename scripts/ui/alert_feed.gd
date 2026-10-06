## The town's calm alert feed (HUDA, the "clutter" pass): what the right column shows of the rules' alerts in the One House.
##
## The rules (`sim.alerts`, id -> {id, level, text, sub, at, ttl, born}) keep an alert for its own time, which is long (12 to 14 rules seconds for "The gate is up"),
## and the HUD used to show up to five of them with up to four lines of small print each. The town's feed is made calmer here, between the rules and the cards:
##
##   - an INFO card fades after `INFO_LIFE_MS` (6 s of real time) and is gone; a warning or a danger stays until the rules drop it (until it is dealt with), and so does
##     the call on the radio (`STICKY`)
##   - SIBLINGS merge: the cards of one kind that come within `MERGE_MS` (4 s) of each other become one ("Three things built": "gate, front fence, watchtower", the
##     latest first; "Two have joined the crew": "Ana, Ben"), which goes to the top as the newest, and lives `INFO_LIFE_MS` from its latest member
##   - the stack shows `SHOWN_MAX` cards (the HUD's `_alert_cap`); the rest fold into a small "+2 more" pill, which a click expands (and "Show fewer" folds again)
##
## `feed(alerts, now_ms)` returns the dictionary the HUD's `_sync_alerts` reads in place of `sim.alerts`: the same shape plus `fade` (1.0, or less while a card is
## going), with a merged card under an id of its own (`g:project:1`); `target(id)` is the alert a click on a card means (the latest of a merged one).
## A view only: it never writes the rules.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")

const INFO_LIFE_MS := 6000
const FADE_MS := 600
const MERGE_MS := 4000
## How many cards the stack shows folded and unfolded, and how many names a merged card spells out.
const SHOWN_MAX := 3
const SHOWN_MAX_OPEN := 7
const NAMES_MAX := 3
## Alerts that wait for an answer and do not fade: the call on the radio, the call to arms.
const STICKY := ["story", "alarm"]
const NUMBER_WORDS := ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]

## The kinds of alert that merge, by the start of their id.
const KINDS := {
	"project-": "built",
	"arrived-": "joined",
}

var hud
## Whether the stack is unfolded (a click on the pill).
var expanded := false
var pill: PanelContainer
var pill_label: Label

var _seen := {}            # id -> when the HUD first saw it (ms), for the ids the rules hold now
var _expired := {}         # id -> true: an info card that has had its time, until the rules drop the alert
var _group_of := {}        # id -> group id
var _groups := {}          # group id -> {"kind", "last_ms", "ids": [...]}
var _group_n := 0
var _click := {}           # a shown id -> the real alert id that a click on it means
var _last_pill := ""


func _init(hud_node = null) -> void:
	hud = hud_node


## The kind of an alert that merges ("built", "joined"), or "".
static func kind_of(id: String) -> String:
	for prefix in KINDS:
		if id.begins_with(prefix):
			return String(KINDS[prefix])
	return ""


static func is_sticky(id: String) -> bool:
	for s in STICKY:
		if id == s or id.begins_with(s + "-"):
			return true
	return false


## "Three" for 3, "12" for 12.
static func count_word(n: int) -> String:
	return NUMBER_WORDS[n] if n >= 0 and n < NUMBER_WORDS.size() else str(n)


## What a finished project's line names: "The front fence is up" -> "front fence", "Both side fences are up" -> "side fences", "The doors are planked" -> "doors".
static func thing_of(line: String) -> String:
	var s := line.strip_edges()
	for lead in ["The ", "Both ", "the ", "both "]:
		if s.begins_with(lead):
			s = s.substr(lead.length())
			break
	var re := RegEx.new()
	re.compile("\\s+(is|are)\\s+\\w+$")
	var m := re.search(s)
	if m != null:
		s = s.substr(0, m.get_start())
	return s


## The name in "Ana Reyes has joined the crew".
static func who_of(line: String) -> String:
	return line.trim_suffix(" has joined the crew").strip_edges()


## The alerts as the stack shows them now (see the header): same shape as `sim.alerts`, plus `fade`.
func feed(alerts: Dictionary, now: int) -> Dictionary:
	_forget(alerts)
	for id in alerts:
		if not _seen.has(id):
			_seen[id] = now
	_assign_groups(alerts)
	var out := {}
	_click = {}
	for id in alerts:
		var gid := String(_group_of.get(id, ""))
		if gid != "":
			continue
		var a: Dictionary = alerts[id]
		var fade := _fade_of(String(id), String(a.level), int(_seen[id]), now)
		if fade < 0.0:
			continue
		var shown: Dictionary = a.duplicate()
		shown["fade"] = fade
		out[id] = shown
		_click[String(id)] = String(id)
	for gid in _groups:
		var g: Dictionary = _groups[gid]
		var live: Array = []
		for id in g.ids:
			if alerts.has(id):
				live.append(id)
		if live.is_empty():
			continue
		var fade := _fade_of(String(gid), "info", int(g.last_ms), now)
		if fade < 0.0:
			continue
		var newest := _newest(live, alerts)
		var card: Dictionary = (alerts[newest] as Dictionary).duplicate()
		card["id"] = String(gid)
		card["fade"] = fade
		if live.size() > 1:
			var names: Array = []
			for i in range(live.size() - 1, -1, -1):
				names.append(_name_in(String(g.kind), alerts[live[i]]))
			card["text"] = _title_of(String(g.kind), live.size())
			# (the latest first; three names are what two lines hold, the rest are counted)
			if names.size() > NAMES_MAX:
				var more := names.size() - NAMES_MAX
				names = names.slice(0, NAMES_MAX)
				card["sub"] = "%s and %d more" % [", ".join(names), more]
			else:
				card["sub"] = ", ".join(names)
			card["born"] = float(alerts[newest].born)
		out[gid] = card
		_click[String(gid)] = String(newest)
	return out


## The alert id a click on the card `id` means (the card's own id, unless it is a merged one).
func target(id: String) -> String:
	return String(_click.get(id, id))


## Whether the card `id` (an alert's or a merged card's) has had its time and is gone for good, though the rules still hold the alert.
func is_spent(id: String) -> bool:
	return _expired.has(id)


## 1.0 while an info card is young, falling to 0 over its last `FADE_MS`; -1 once it has had its time. A warning or a danger is always 1.0.
func _fade_of(id: String, level: String, since: int, now: int) -> float:
	if level != "info" or is_sticky(id):
		return 1.0
	if _expired.has(id):
		return -1.0
	var age := now - since
	if age >= INFO_LIFE_MS:
		_expired[id] = true
		return -1.0
	var left := INFO_LIFE_MS - age
	return 1.0 if left >= FADE_MS else clampf(float(left) / float(FADE_MS), 0.0, 1.0)


## What the feed remembers of alerts the rules have dropped goes.
func _forget(alerts: Dictionary) -> void:
	for id in _seen.keys():
		if not alerts.has(id):
			_seen.erase(id)
			_expired.erase(id)
			_group_of.erase(id)
			for gid in _groups:
				(_groups[gid].ids as Array).erase(id)    # (an alert the rules raise again later is a new one)
	for gid in _groups.keys():
		var any := false
		for id in _groups[gid].ids:
			if alerts.has(id):
				any = true
		if not any:
			_groups.erase(gid)
			_expired.erase(gid)


## Puts each alert of a merging kind into a group: the open group of its kind that the previous one joined within MERGE_MS, else a new group.
func _assign_groups(alerts: Dictionary) -> void:
	var fresh: Array = []
	for id in alerts:
		if kind_of(String(id)) != "" and not _group_of.has(id):
			fresh.append(String(id))
	fresh.sort_custom(func(a, b): return int(_seen[a]) < int(_seen[b]))
	for id in fresh:
		var kind := kind_of(id)
		var when := int(_seen[id])
		var joined := ""
		for gid in _groups:
			var g: Dictionary = _groups[gid]
			if String(g.kind) == kind and when - int(g.last_ms) <= MERGE_MS and not _expired.has(gid):
				joined = String(gid)
		if joined == "":
			_group_n += 1
			joined = "g:%s:%d" % [kind, _group_n]
			_groups[joined] = {"kind": kind, "last_ms": when, "ids": []}
		var grp: Dictionary = _groups[joined]
		grp.ids.append(id)
		grp.last_ms = maxi(int(grp.last_ms), when)
		_group_of[id] = joined


## The member that came last (the rules' own clock, then the order they were seen in).
func _newest(live: Array, alerts: Dictionary) -> String:
	var best := String(live[0])
	for id in live:
		if float(alerts[id].born) >= float(alerts[best].born):
			best = String(id)
	return best


func _title_of(kind: String, n: int) -> String:
	match kind:
		"built":
			return "%s things built" % count_word(n)
		"joined":
			return "%s have joined the crew" % count_word(n)
	return "%s new" % count_word(n)


func _name_in(kind: String, a: Dictionary) -> String:
	match kind:
		"built":
			return thing_of(String(a.text))
		"joined":
			return who_of(String(a.text))
	return String(a.text)


# ------------------------------------------------------------------ a screenshot's helper --

## `--alerts=3|many` on the command line (a screenshot's staging, like `--lure`): puts sample alerts up in the rules' feed, of the kinds the town raises, so that the
## stack, the merge and the pill can be looked at without playing to them. Nothing for a player.
static func stage(sim, spec: String) -> void:
	if sim == null or spec == "":
		return
	sim.alert("project-front", "info", "The front fence is up", "", null, 14.0)
	sim.alert("project-gate", "info", "The gate is up", "", null, 14.0)
	sim.alert("gate-base", "warn", "The gate is open", "The dead can walk in", null, 30.0)
	if spec == "many":
		sim.alert("project-tower", "info", "The watchtower is up", "", null, 14.0)
		sim.alert("arrived-r1", "info", "Abe Tanner has joined the crew", "Carpenter", null, 14.0)
		sim.alert("slots-open", "info", "The base can grow", "Open the Build page (N)", null, 12.0)
		sim.alert("self-bandage", "info", "Wound bandaged", "The bleeding has stopped. One medicine used", null, 8.0)
		sim.alert("low-food", "warn", "Food is running out", "About 3 days left", null, 30.0)


# ----------------------------------------------------------------------- the pill --

## The small "+2 more" pill under the stack (made once, put in the right column after the alerts); a click unfolds the stack.
func make_pill(column: Control, after: Control) -> void:
	if pill != null:
		return
	pill = PanelContainer.new()
	var st: StyleBoxFlat = hud._flat(Color(hud.PANEL, 0.88), 10, hud.LINE2, false)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 2
	st.content_margin_bottom = 3
	pill.add_theme_stylebox_override("panel", st)
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	pill.visible = false
	pill_label = hud._label("", Fonts.sans(600), 12, hud.INK2)
	pill.add_child(pill_label)
	pill.gui_input.connect(_on_pill_input)
	column.add_child(pill)
	column.move_child(pill, after.get_index() + 1)


## Brings the pill up to date: `hidden` is how many alerts the stack folds away, `total` how many there are.
func sync_pill(hidden: int, total: int) -> void:
	if pill == null:
		return
	if total <= SHOWN_MAX:
		expanded = false
	var words := ""
	if expanded and total > SHOWN_MAX:
		words = "Show fewer"
	elif hidden > 0:
		words = "+%d more" % hidden
	if words != _last_pill:
		_last_pill = words
		pill_label.text = words
	pill.visible = words != ""
	pill.tooltip_text = "Show every alert" if hidden > 0 else "Fold the older alerts away"


func _on_pill_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		expanded = not expanded
		pill.accept_event()
		hud.refresh_alerts()


## How many cards the stack shows.
func cap() -> int:
	return SHOWN_MAX_OPEN if expanded else SHOWN_MAX
