## The command wheel's controller (round 24): what the keys and the mouse do to it, whom it asks and how, for the yard (scripts/main.gd) and a place
## (scripts/raid/raid_scene.gd) alike. The view is scripts/ui/command_wheel.gd; the asking is the dock's own (`RadioVerbs.order`, so the answer line, the
## refusal in amber, Insist, the flag and the toast are exactly what a right click's order has); the rules are scripts/sim/radio.gd.
##
## KEYS. Hold C (or the middle button) and the wheel opens at the pointer; release over a slice, or click it, and the person it is for is asked; release
## in the centre (after more than TAP_S), outside it, press Esc or the right button, and nothing is asked. A tap of the key (let go within TAP_S, the
## pointer not on a slice) leaves the wheel up until a click picks a slice. While it is up Shift (or a click on its centre) is the second ring: the same
## verbs for everyone within NEAR_ALL tiles, one `radio.request` each, their answers in one line. 1 to 5 pick the crew by card order, Z asks the person picked
## (else the one under the pointer, else the nearest) what the last order was (a hold or a search to the same point).
##
## WHOM. The person picked; with nobody picked the one under the pointer; with nobody there the nearest within NEAR_ONE tiles of the avatar. Named in the
## wheel's centre. A slice is greyed when `radio.willingness` says it is a refusal nobody can argue with, and marked "Insist" when it is one a push could
## override (it is asked, and refused in amber, and the dock's Insist button is there: choosing it never pushes by itself).
##
## THE HOST (main.gd or raid_scene.gd) answers these, so that nothing here knows which of the two it is in:
##   wheel_view() -> the CommandWheel node          wheel_ok() -> whether the wheel and the keys may act now (an avatar, no menu, no page)
##   wheel_allowed() -> Orientation Day's lock      wheel_pointer() -> the pointer in screen pixels      wheel_over_hud() -> a control has the pointer
##   wheel_me() -> the survivor played              wheel_crew() -> the people who can be asked, in card order (not you)
##   wheel_selected() -> the person picked or null  wheel_pick(p)    wheel_hovered(tile) -> the person under a point, or null
##   wheel_tile(screen) -> a screen point as a tile wheel_radio(p) -> the radio that answers p            wheel_place() -> in a place
##   wheel_verbs() -> the HUD's RadioVerbs          wheel_extra(verb, tile) -> {"at"} / {"post"} / {"error"} / {}   wheel_ask(p, verb, extra) -> the answer
##   wheel_flag(verb, extra)  wheel_solid(pos) -> bool  wheel_toast(text, level)  wheel_crew_keys() -> whether 1 to 5 pick people here
extends RefCounted

const Radio := preload("res://scripts/sim/radio.gd")
const RadioVerbs := preload("res://scripts/ui/radio_verbs.gd")

## How near (tiles, from the avatar) the person is whom the wheel asks when nobody is picked or pointed at, and how near the second ring reaches.
const NEAR_ONE := 6.0
const NEAR_ALL := 8.0
## The keys 1 to this pick a person of the crew.
const KEYS := 5
## A key or a button let go within this many seconds is a tap: the wheel stays up for a click.
const TAP_S := 0.25
## The ring the people of a group hold a spot on, round it, in tiles.
const SPREAD_R := 0.95
## At most this many names in a line of the group's answers (then "and 2 more").
const MAX_NAMES := 3
const TIPS := {
	"come": "Come with me: %s follows you",
	"hold": "Hold here: %s stays at the spot you opened the wheel on",
	"cover": "Cover me: %s stands behind you, watching your back",
	"search": "Search that: %s goes and searches what you opened the wheel on",
	"back": "Go back: %s goes back to what they were doing",
	"post": "To the walls: %s goes to their post on the wall",
}
const HINT_ONE := "Release on a slice. Shift: everyone near you. Esc: cancel"
const HINT_GROUP := "Everyone within 8 tiles. Shift again: just one. Esc: cancel"

var host
var wheel
## The last order given, for Z: {"verb", "at" (a Vector2 or null), "post" (a night post's id or "")}; {} before the first.
var last_order := {}
## While the wheel is up: {"who", "tile", "extras" (a verb to what `wheel_extra` said of it), "group", "members"}.
var info := {}
var _src := ""
var _open_ms := 0


func _init(the_host = null) -> void:
	host = the_host


## Gives the controller its view (the host's CommandWheel node) and listens for every order the dock's verbs give (a button, a right click, the wheel's own),
## so that Z can repeat any of them.
func attach(verbs) -> void:
	wheel = host.wheel_view()
	if verbs != null and not verbs.requested.is_connected(on_requested):
		verbs.requested.connect(on_requested)


func is_open() -> bool:
	return wheel != null and wheel.active and not info.is_empty()


## The person the wheel is up for (null in the group's ring with nobody single to ask).
func target():
	return info.get("who") if is_open() else null


# ------------------------------------------------------------------ whom --

## The people who can be asked, in card order: not lost, not turned, not away on a trip, not the one the player plays. The keys 1 to 5 are the first five.
static func crew_of(people: Array) -> Array:
	var out: Array = []
	for p in people:
		if not p.dead and not p.turned and p.away == null and not p.player:
			out.append(p)
	return out


## The people of `people` within `radius` tiles of `from`, nearest first.
static func within(people: Array, from: Vector2, radius: float) -> Array:
	var out: Array = []
	for p in people:
		var d := Vector2(p.x, p.y).distance_to(from)
		if d <= radius:
			out.append([d, p])
	out.sort_custom(func(a, b): return a[0] < b[0])
	var ps: Array = []
	for e in out:
		ps.append(e[1])
	return ps


## The person the wheel (and Z) is for: the one picked, else the one at `tile` (the pointer), else the nearest crew within NEAR_ONE of the avatar.
func target_for(tile: Vector2):
	var sel = host.wheel_selected()
	if sel != null:
		return sel
	var hov = host.wheel_hovered(tile)
	if hov != null:
		return hov
	var me = host.wheel_me()
	if me == null:
		return null
	var near := within(_on_their_feet(host.wheel_crew()), Vector2(me.x, me.y), NEAR_ONE)
	return near[0] if not near.is_empty() else null


## Everyone the second ring reaches: the crew within NEAR_ALL tiles of the avatar.
func group_now() -> Array:
	var me = host.wheel_me()
	if me == null:
		return []
	return within(_on_their_feet(host.wheel_crew()), Vector2(me.x, me.y), NEAR_ALL)


## Those of `people` who are up (a person who is down is asked only when they are picked or pointed at: nearest and everyone near leave them out).
static func _on_their_feet(people: Array) -> Array:
	var out: Array = []
	for p in people:
		if not p.downed:
			out.append(p)
	return out


# ----------------------------------------------------------------- opening --

## Opens the wheel at `screen`. False when it cannot (not now, locked, nobody to ask).
func open(screen: Vector2, src: String = "key") -> bool:
	if is_open() or wheel == null or not host.wheel_ok() or not host.wheel_allowed():
		return false
	if host.wheel_me() == null:
		return false
	var tile: Vector2 = host.wheel_tile(screen)
	var who = target_for(tile)
	var members := group_now()
	if who == null and members.is_empty():
		host.wheel_toast("Nobody is near enough to ask: pick someone first (their card, or 1 to 5)", "info")
		return false
	info = {"who": who, "tile": tile, "extras": {}, "group": who == null, "members": members}
	for verb in Radio.VERBS:
		info.extras[verb] = host.wheel_extra(String(verb), tile)
	_src = src
	_open_ms = Time.get_ticks_msec()
	wheel.open_at(screen, _words())
	return true


## What the wheel says now: its centre, its slices and the line under it.
func _words() -> Dictionary:
	var group: bool = bool(info.group)
	var who = info.get("who")
	var members: Array = info.get("members", [])
	var slices: Array = []
	for verb in Radio.VERBS:
		slices.append(_slice(String(verb), group, who, members))
	var title := "Everyone" if group else String(who.first)
	var caption := "%d near you" % members.size() if group else ("Shift: all near" if members.size() > 1 else "")
	return {"title": title, "caption": caption, "slices": slices, "group": group, "hint": HINT_GROUP if group else HINT_ONE}


## One slice: {"verb", "name", "enabled", "soft", "tip"} for the verb, asked of one person or of the group.
func _slice(verb: String, group: bool, who, members: Array) -> Dictionary:
	var radio_name := String(Radio.VERB_NAMES.get(verb, verb))
	var s := {"verb": verb, "name": radio_name, "enabled": true, "soft": false, "tip": ""}
	var place: bool = host.wheel_place()
	var extra: Dictionary = info.extras.get(verb, {})
	if group:
		var ok := 0
		var why: Array = []
		for p in members:
			var st := RadioVerbs.state_for(host.wheel_radio(p), p, verb, false, place)
			if st.enabled and not st.soft:
				ok += 1
			elif String(st.why) != "":
				why.append(String(st.why))
		var err := String(extra.get("error", ""))
		if err != "":
			s.enabled = false
			s.tip = err
		elif ok == 0:
			s.enabled = false
			s.tip = "None of them can: %s" % ("; ".join(why.slice(0, 2)) if not why.is_empty() else "nobody is near")
		else:
			s.tip = String(TIPS[verb]).replace("%s", "everyone near you (%d)" % ok if ok > 1 else "the one person near you")
			if not why.is_empty():
				s.tip += "\nNot: %s" % "; ".join(why.slice(0, 2))
		return s
	var st := RadioVerbs.state_for(host.wheel_radio(who), who, verb, false, place)
	var err2 := String(extra.get("error", ""))
	if err2 != "":
		s.enabled = false
		s.tip = err2
	elif not st.enabled:
		s.enabled = false
		s.tip = String(st.why)
	elif st.soft:
		s.soft = true
		s.tip = "%s. Release to ask: they will say so, and Insist pushes them (it costs trust)" % String(st.why)
	else:
		s.tip = String(TIPS[verb]).replace("%s", String(who.first))
		var delay := float(st.w.get("delay_s", 0.0)) if not st.w.is_empty() else 0.0
		if delay > 0.0:
			s.tip += " (answers in about %s)" % ("%d s" % int(delay) if absf(delay - roundf(delay)) < 0.05 else "%.1f s" % delay)
	return s


## The second ring on or off (Shift, or a click on the centre).
func toggle_group() -> void:
	if not is_open():
		return
	if not bool(info.group):
		info.members = group_now()
		if info.members.is_empty():
			host.wheel_toast("Nobody else is near enough", "info")
			return
		info.group = true
	elif info.get("who") != null:
		info.group = false
	else:
		return    # (nobody to ask alone)
	wheel.set_info(_words())


func cancel() -> void:
	if wheel != null:
		wheel.close()
	info = {}
	_src = ""


# ------------------------------------------------------------- choosing --

## The key or the button that opened the wheel was let go after `held_s` seconds (-1: as long as it has been). What it did: {"asked": answer}, {"latched": true}
## (a tap: the wheel stays up for a click), {"refused": reason} or {"cancelled": true}; {} when the wheel is not up.
func release(held_s: float = -1.0) -> Dictionary:
	if not is_open() or wheel.latched:
		return {}
	if held_s < 0.0:
		held_s = float(Time.get_ticks_msec() - _open_ms) / 1000.0
	var c: Dictionary = wheel.choice_now()
	if String(c.zone) == "slice":
		return _choose(int(c.index))
	if held_s < TAP_S and String(c.zone) != "out":
		wheel.latched = true
		wheel.set_info({"hint": "Click a slice. Shift: everyone near you. Esc: cancel"})
		return {"latched": true}
	cancel()
	return {"cancelled": true}


## A left click at `pos` while the wheel is up: a slice asks, the centre is the second ring, outside cancels. True (the click is the wheel's).
func click(pos: Vector2) -> Dictionary:
	if not is_open():
		return {}
	var c: Dictionary = wheel.choice_at(pos)
	match String(c.zone):
		"slice":
			return _choose(int(c.index), true)
		"centre":
			toggle_group()
			return {"toggled": true}
	cancel()
	return {"cancelled": true}


## Slice `i` was picked. A greyed one says why and closes the wheel (a click keeps it up: the person may pick another).
func _choose(i: int, keep_if_refused: bool = false) -> Dictionary:
	var s: Dictionary = wheel.slices[i]
	var verb := String(s.verb)
	if not bool(s.enabled):
		var why := String(s.tip)
		if keep_if_refused:
			host.wheel_toast(why, "warn")
			return {"refused": why}
		cancel()
		host.wheel_toast(why, "warn")
		return {"refused": why}
	var was := info
	wheel.close()
	info = {}
	_src = ""
	var extra: Dictionary = was.extras.get(verb, {})
	if bool(was.group):
		return {"asked": ask_group(verb, extra, was.members)}
	return {"asked": ask_one(was.who, verb, extra)}


## Asks one person for `verb` through the dock's own path: they are picked (their dock opens, with the answer line and Insist), the radio's verbs
## ask them (`RadioVerbs.order`), the HUD says the answer in a toast. A verb nobody can argue with (the dock would have it off) is not asked.
func ask_one(p, verb: String, extra: Dictionary = {}) -> Dictionary:
	var verbs = host.wheel_verbs()
	if p == null or verbs == null:
		return {}
	var st := RadioVerbs.state_for(host.wheel_radio(p), p, verb, false, host.wheel_place())
	if not st.enabled:
		host.wheel_toast(String(st.why), "warn")
		return {"ok": false, "line": "", "why": String(st.why), "hard": true, "verb": verb}
	if host.wheel_selected() != p:
		host.wheel_pick(p)
	if verbs.contact != p:
		verbs.set_contact(p)
	var ex := extra.duplicate()
	ex.erase("error")
	var r: Dictionary = verbs.order(verb, ex)
	if host.has_method("wheel_said"):
		host.wheel_said(p, r)    # (a place has no toast of its own for an answer)
	return r


## Asks everyone in `members` for `verb`, one `radio.request` each (a hold or a search to one point; a hold is spread round it), and says what came of it in
## one line. Returns {"results": [{"p", "ok", "line", "why"}], "text", "ok" (how many agreed), "refused"}.
func ask_group(verb: String, extra: Dictionary, members: Array) -> Dictionary:
	var ex := extra.duplicate()
	ex.erase("error")
	var place: bool = host.wheel_place()
	var takers := 0
	for p in members:
		var st := RadioVerbs.state_for(host.wheel_radio(p), p, verb, false, place)
		if st.enabled and not st.soft:
			takers += 1
	var results: Array = []
	var k := 0
	for p in members:
		var st := RadioVerbs.state_for(host.wheel_radio(p), p, verb, false, place)
		var taking: bool = st.enabled and not st.soft
		var args := ex.duplicate()
		if taking and verb == "hold" and args.has("at"):
			args["at"] = spread(Vector2(args.at), k, takers, host)
		var r: Dictionary
		if not st.enabled:
			r = {"ok": false, "line": "", "why": String(st.why)}
		else:
			r = host.wheel_ask(p, verb, args)
		if bool(r.get("ok", false)):
			k += 1
		results.append({"p": p, "ok": bool(r.get("ok", false)), "line": String(r.get("line", "")), "why": String(r.get("why", ""))})
	var sum := summarize(results)
	host.wheel_toast(String(sum.text), "warn" if int(sum.refused) > 0 else "info")
	if int(sum.ok) > 0:
		host.wheel_flag(verb, ex)
	_remember(verb, ex)
	sum["results"] = results
	return sum


## The place of the k-th of n people who hold a spot together: the first on it, the others on a ring round it (a spot that is solid is theirs too).
static func spread(spot: Vector2, k: int, n: int, the_host) -> Vector2:
	if n <= 1 or k <= 0:
		return spot
	var a := TAU * float(k - 1) / float(maxi(1, n - 1))
	var at := spot + Vector2(cos(a), sin(a)) * SPREAD_R
	if the_host != null and the_host.wheel_solid(at):
		return spot
	return at


## "Dez and Ana: on my way; Marcus: tending a patient, can't come": who agreed (grouped by what they said), then each refusal in the radio's own words.
## `results`: [{"p", "ok", "line", "why"}]. Returns {"text", "ok", "refused"}.
static func summarize(results: Array) -> Dictionary:
	var said := {}
	var order: Array = []
	var no: Array = []
	var ok := 0
	for r in results:
		if bool(r.ok):
			ok += 1
			var line := plain(String(r.line))
			if not said.has(line):
				said[line] = []
				order.append(line)
			said[line].append(String(r.p.first))
		else:
			no.append(String(r.why) if String(r.why) != "" else "%s can't" % String(r.p.first))
	var parts: Array = []
	for line in order:
		parts.append("%s: %s" % [join_names(said[line]), line] if line != "" else join_names(said[line]))
	if no.size() > MAX_NAMES:
		parts.append_array(no.slice(0, MAX_NAMES))
		parts.append("and %d more can't" % (no.size() - MAX_NAMES))
	else:
		parts.append_array(no)
	return {"text": "; ".join(parts), "ok": ok, "refused": no.size()}


## "On my way." as a line of a group's answers: "on my way".
static func plain(line: String) -> String:
	return line.strip_edges().trim_suffix(".").replace(". ", ", ").to_lower()


## "Dez", "Dez and Ana", "Dez, Ana and Marcus", "Dez, Ana and 2 more".
static func join_names(names: Array) -> String:
	if names.size() <= 1:
		return String(names[0]) if names.size() == 1 else ""
	if names.size() == 2:
		return "%s and %s" % [names[0], names[1]]
	if names.size() <= MAX_NAMES:
		return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]
	return "%s, %s and %d more" % [names[0], names[1], names.size() - 2]


# ------------------------------------------------------------ the last order --

## Every order the dock's verbs give (a button, a right click, the wheel's own, Z's): what Z repeats.
func on_requested(_contact, verb: String, _result: Dictionary) -> void:
	var verbs = host.wheel_verbs()
	var ex: Dictionary = verbs.last.get("extra", {}) if verbs != null else {}
	var at = ex.get("at")
	if verb == "hold" and typeof(at) != TYPE_VECTOR2:
		var me = host.wheel_me()
		at = Vector2(me.x, me.y) if me != null else null
	_remember_at(verb, at if typeof(at) == TYPE_VECTOR2 else null, String(ex.get("post", "")))


func _remember(verb: String, extra: Dictionary) -> void:
	var at = extra.get("at")
	_remember_at(verb, at if typeof(at) == TYPE_VECTOR2 else null, String(extra.get("post", "")))


func _remember_at(verb: String, at, post: String) -> void:
	last_order = {"verb": verb, "at": at, "post": post}


## Z: the last order again, for the person picked (else the one under the pointer, else the nearest). Returns the answer ({} when nothing was asked).
func repeat() -> Dictionary:
	if not host.wheel_ok() or not host.wheel_allowed():
		return {}
	if last_order.is_empty():
		host.wheel_toast("No order to repeat yet: give one first (hold C for the wheel)", "info")
		return {}
	var who = target_for(host.wheel_tile(host.wheel_pointer()))
	if who == null:
		host.wheel_toast("Pick someone first (their card, or 1 to 5)", "info")
		return {}
	var extra := {}
	if typeof(last_order.at) == TYPE_VECTOR2:
		extra["at"] = last_order.at
	if String(last_order.post) != "":
		extra["post"] = last_order.post
	var r := ask_one(who, String(last_order.verb), extra)
	if bool(r.get("ok", false)):
		var line := plain(String(r.get("line", "")))
		host.wheel_toast("%s: %s (again)" % [String(who.first), line] if line != "" else "%s (again)" % String(who.first))
	return r


## 1 to 5: picks that person of the crew, by card order (the first card that is not you is 1).
func pick_number(n: int) -> bool:
	var crew: Array = host.wheel_crew()
	if n < 1 or n > crew.size():
		host.wheel_toast("Nobody is number %d" % n, "info")
		return true
	host.wheel_pick(crew[n - 1])
	return true


# ----------------------------------------------------------------- the input --

## A key went down (not an echo): the wheel's, or the crew's keys', or not. True when it was taken.
func key_down(code: int, shift: bool = false, command: bool = false) -> bool:
	if command:
		return false    # (Ctrl or Cmd with a letter is a command, not the wheel's)
	if is_open():
		if code == KEY_ESCAPE or code == KEY_C:
			cancel()
			return true
		if code == KEY_SHIFT:
			toggle_group()
			return true
		# (the keys that would pick someone else, ask again or go round the crew leave the wheel as it is; the rest is the game's: W A S D walk)
		return (code >= KEY_1 and code <= KEY_5) or code == KEY_Z or code == KEY_TAB
	if not host.wheel_ok():
		return false
	if code == KEY_C:
		return open(host.wheel_pointer(), "key")
	if code >= KEY_1 and code <= KEY_5 and host.wheel_crew_keys():
		if shift and code <= KEY_3:
			return false    # (Shift and 1 2 3 are the speeds)
		return pick_number(int(code) - int(KEY_1) + 1)
	if code == KEY_Z:
		repeat()
		return true
	return false


## A key went up: the wheel it opened is released.
func key_up(code: int) -> bool:
	if code == KEY_C and is_open() and _src == "key":
		release()
		return true
	return false


## A mouse button: the middle one opens the wheel (on a press that no control took) and releases it; with it up, the left button clicks it and the right
## one cancels it. True when the event was the wheel's.
func mouse(ev: InputEventMouseButton) -> bool:
	if ev.button_index == MOUSE_BUTTON_MIDDLE:
		if ev.pressed:
			if is_open() or host.wheel_over_hud() or not host.wheel_ok():
				return false
			return open(ev.position, "mouse")
		if is_open() and _src == "mouse":
			release()
			return true
		return false
	if not is_open() or not ev.pressed:
		return false
	if ev.button_index == MOUSE_BUTTON_LEFT:
		click(ev.position)
		return true
	if ev.button_index == MOUSE_BUTTON_RIGHT:
		cancel()
		return true
	return false


## The pointer moved.
func motion(pos: Vector2) -> void:
	if is_open():
		wheel.move_pointer(pos)
