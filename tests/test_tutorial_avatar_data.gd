extends "res://tests/case.gd"
## assets/data/tutorial.json, the avatar's Orientation Day, as data: the eight steps it has (round 26: cut down for the demo) and in what
## order, that no word of any card names a control the avatar does not have (right-click, middle-drag, a box, a drag, picking in the
## world, the order keys P X M B), that the keys it does name are keys the avatar has, which steps hold the game still and which need it
## to run, that it names nothing the demo hides (the duty roster, building, policies) and that it never moves the camera (the camera is the
## avatar's). The checks that hold for both lessons are in tests/test_tutorial_data.gd.

const Coach := preload("res://scripts/ui/coach.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")

const IDS := ["you", "walk", "shoot", "reload", "ask", "wheel", "dusk", "wrap"]
## What no card of this lesson may say: the old yard's controls, which the avatar's game does not have.
const REMOVED_WORDS := ["right-click", "right click", "middle-drag", "middle drag", "alt-drag", "alt and drag", "box", "drag", "select", "draft", "release", "send out", "repair", "lure", "pan "]
## What no card may name because the demo hides it (a lesson that taught it would teach a thing that is not there): the duty roster and its
## jobs table, building, the policies, the problems and the dilemmas, the relations and the specialists, the lots.
const DEMO_HIDES := ["roster", "jobs", "build", "polic", "dials", "dial ", "problems", "dilemma", "relation", "specialist", "lot "]
## The keys of single letters an avatar's game has (and the arrows): the only ones a card may name.
const KEYS := ["W", "S", "D", "R", "F", "T", "G", "L", "J", "V", "N", "Q", "E", "C"]    # (Q: round 23, the weapon put away; C and E: the wheel and the lever)
## The keys of the old yard's orders, which are gone (C was one, the wheel has it since round 24).
const GONE_KEYS := ["P", "X", "M", "B"]


func _steps() -> Array:
	return Coach.load_steps(Coach.STEPS_PATH)


## Every word the cards say, one string each: a step's title, text, goals and lines, what it says while it waits, over a page and
## when it is skipped.
func _words_of(s: Dictionary) -> Array:
	var out: Array = []
	for key in ["title", "text", "text_always", "goal", "wait_title", "wait_text", "skipped_title", "skipped_text", "dialog_text"]:
		if s.has(key):
			out.append(String(s[key]))
	for g in s.get("goals", []) + s.get("goals_always", []):
		out.append(String(g.get("text", "")))
		if g.has("line"):
			out.append(String(g.line))
	return out


func _by_id() -> Dictionary:
	var by_id := {}
	for s in _steps():
		by_id[String(s.id)] = s
	return by_id


func test_it_is_the_avatars_lesson_in_order() -> void:
	var steps := _steps()
	var ids: Array = []
	for s in steps:
		ids.append(String(s.id))
	eq(ids, IDS, "the steps")
	eq(steps.size(), 8, "eight steps, for a lesson of about eight minutes (the demo's)")
	eq(String(steps[0].id), "you", "it begins with who you are")
	eq(String(steps[steps.size() - 1].get("type", "")), "wrap", "and ends with the wrap-up")
	check(Coach.words(String(steps[steps.size() - 1].text)) <= Coach.MAX_WORDS, "which is short too")


func test_no_card_names_a_control_the_avatar_does_not_have() -> void:
	for s in _steps():
		for words in _words_of(s):
			var low := String(words).to_lower()
			for bad in REMOVED_WORDS:
				var at := low.find(bad)
				# (a word, not a part of one: "toolbox", "orders" in "borders")
				while at >= 0:
					var before := low[at - 1] if at > 0 else " "
					var after := low[at + bad.length()] if at + bad.length() < low.length() else " "
					check(not (before in " ,.:;(\"'" and after in " ,.:;)\"'s"), "%s: '%s' names '%s' (%s)" % [s.id, words, bad, "the old yard's"])
					at = low.find(bad, at + 1)
			# the letters that are keys: every single capital that stands alone
			for raw in String(words).replace(",", " ").replace(".", " ").replace(":", " ").replace(";", " ").replace("?", " ").split(" ", false):
				if raw.length() == 1 and raw == raw.to_upper() and raw != raw.to_lower():
					check(not GONE_KEYS.has(raw), "%s: '%s' names the key %s, which is gone" % [s.id, words, raw])
					check(raw == "A" or raw == "I" or KEYS.has(raw), "%s: '%s' names the key %s, which the avatar does not have" % [s.id, words, raw])


func test_no_card_names_a_system_the_demo_hides() -> void:
	for s in _steps():
		for words in _words_of(s):
			var low := " " + String(words).to_lower() + " "
			for hidden in DEMO_HIDES:
				check(not low.contains(hidden), "%s: '%s' names '%s', which the demo hides" % [s.id, words, hidden.strip_edges()])


func test_the_scan_catches_what_it_is_meant_to() -> void:
	# (the scan above, on cards that say the old things)
	var fake := {"id": "old", "title": "Order", "text": "Click the bus, then press F. Right-click the ground, and press P to post. Draw a box. Press M for the bench.", "goal": "select Hector, then press X"}
	var found := 0
	for words in _words_of(fake):
		var low := String(words).to_lower()
		for bad in REMOVED_WORDS:
			if low.contains(bad):
				found += 1
		for raw in String(words).replace(",", " ").replace(".", " ").split(" ", false):
			if raw.length() == 1 and GONE_KEYS.has(raw):
				found += 1
	check(found >= 6, "it finds right-click, a box, select, P, M and X in an old card (%d)" % found)
	# (and what the demo hides)
	var hidden := 0
	for words in _words_of({"id": "x", "title": "The duty roster", "text": "Open the Jobs page, set a policy dial and build a shed."}):
		var low := " " + String(words).to_lower() + " "
		for h in DEMO_HIDES:
			if low.contains(h):
				hidden += 1
	check(hidden >= 4, "it finds the roster, jobs, a policy, a dial and build in a card that names them (%d)" % hidden)


func test_the_keys_the_cards_name_are_named_for_what_they_do_now() -> void:
	var said := {}
	for s in _steps():
		for words in _words_of(s):
			said[String(s.id) + "|" + String(words)] = true
	var all := ""
	for k in said:
		all += " " + String(k)
	for needle in ["W A S D", "R reloads", "Q puts the weapon away", "hold C", "press E", "T for the News", "G for the map", "pickup trip", "briefing card"]:
		check(all.contains(needle), "a card says '%s'" % needle)


func test_the_steps_that_need_the_world_to_move_do_not_hold_it_and_are_kept_at_normal_speed() -> void:
	for s in _steps():
		var id := String(s.id)
		if ["walk", "shoot", "reload", "wheel", "dusk"].has(id):
			check(not bool(s.get("pause", false)) and not s.has("pause_until"), "%s: the game runs (the avatar walks, shoots and works the gate in its time)" % id)
			eq(int(s.get("run_speed", 0)), 1, "%s: at normal speed to begin with" % id)
		if ["you", "wrap"].has(id):
			check(bool(s.get("pause", false)), "%s: the game waits while it is read" % id)
	# asking is done with the game held until the push (Ana's refusal would not wait to be read otherwise)
	check(_by_id().ask.has("pause_until"), "ask: the game waits until the player has asked, been refused and pushed")
	eq(String(_by_id().ask.pause_until.cond), "insisted", "(it is let go when Ana has been pushed)")


func test_the_camera_is_the_avatars_so_no_step_moves_it() -> void:
	for s in _steps():
		check(not s.has("focus") and not s.has("follow"), "%s: it does not move or hold the camera" % s.id)
		check(not s.has("move_inside") and not s.has("move_radius") and not s.has("move_min"), "%s: it does not send anyone anywhere" % s.id)


func test_every_beat_a_step_fires_is_a_beat_of_the_avatars_lesson() -> void:
	var ids: Array = ["dusk", "more", "scratch", "fever", "stray", "spent", "assault", "home"]
	var fired := {}
	for s in _steps():
		for id in s.get("fire", []):
			check(ids.has(String(id)), "%s fires '%s', which is a beat" % [s.id, id])
			fired[String(id)] = true
		var when = s.get("fire_when")
		if typeof(when) == TYPE_DICTIONARY:
			for id in when.get("beats", []):
				check(ids.has(String(id)), "%s fires '%s' when its moment comes, and that is a beat" % [s.id, id])
				fired[String(id)] = true
		for id in s.get("jump", {}).get("fired", []):
			check(ids.has(String(id)), "%s: '%s' (in its jump) is a beat" % [s.id, id])
	for id in ["stray", "spent", "scratch", "home", "dusk", "more"]:
		check(fired.has(id), "the beat '%s' is fired by a lesson" % id)
	for id in Orientation.AVATAR_BEATS:
		check(ids.has(id), "the scenario's beat '%s' is known to this test" % id)


func test_the_lesson_teaches_what_the_wrap_up_says_it_does_next() -> void:
	var steps := _steps()
	var wrap: Dictionary = steps[steps.size() - 1]
	var text := String(wrap.text).to_lower()
	for word in ["briefing", "news", "map", "pickup", "wall"]:
		check(text.contains(word), "the wrap-up names '%s'" % word)
	check(String(wrap.get("skipped_text", "")) != "" and String(wrap.get("skipped_title", "")) != "", "and it has its words for a skip")


func test_the_gate_and_the_bell_bring_their_afternoon_and_their_dead_when_the_bell_rings() -> void:
	var dusk: Dictionary = _by_id().dusk
	check(bool(dusk.get("warp", false)), "the step brings its own time of day as it begins (the hours between are not played)")
	var jump: Dictionary = dusk.jump
	check(float(jump.hour) >= 15.0 and float(jump.hour) < 19.0, "late afternoon: %s" % str(jump.hour))
	eq(String(jump.get("gate", "")), "open", "with the gate open for the player to shut")
	eq(String(dusk.fire_when.cond), "bell_rung", "the dead of the dusk come when the bell rings")
	eq(dusk.fire_when.beats, ["dusk", "more"], "both groups")
	check(dusk.allow.has("interact"), "E is allowed (the lever)")
	check(String(dusk.anchor[dusk.anchor.size() - 1]).begins_with("spot:"), "and the card points at the lever (a place in the yard)")
	var goals: Array = dusk.goals
	check(goals.size() == 1 and bool(goals[0].get("speed", false)), "once the gate is shut the card offers Speed up for the wait for the bell")


func test_the_conditions_the_steps_wait_for_are_the_ones_that_check_what_they_teach() -> void:
	var by_id := _by_id()
	eq(String(by_id.walk.done.cond), "walked", "Walk: the player walked")
	eq(String(by_id.shoot.done.cond), "player_kills", "Aim and shoot: the player's own kill")
	var reload_names: Array = []
	for c in by_id.reload.done.params.of:
		reload_names.append(String(c.cond))
	check(reload_names.has("reloaded") and reload_names.has("did") and reload_names.has("not"), "Reload and put away: R, Q, and the weapon drawn again")
	var ask_names: Array = []
	for c in by_id.ask.done.params.of:
		ask_names.append(String(c.cond))
	check(ask_names.count("has_stance") == 2 and ask_names.has("insisted"), "Ask, do not order: Dez comes, Ana is pushed, and she comes")
	var wheel_names: Array = []
	for c in by_id.wheel.done.params.of:
		wheel_names.append(String(c.cond) + ":" + String(c.params.get("what", c.params.get("stance", ""))))
	check(wheel_names.has("did:wheel") and wheel_names.has("has_stance:hold"), "The radio wheel: the ring was used and Dez holds the spot")
	var dusk_names: Array = []
	for c in by_id.dusk.done.params.of:
		dusk_names.append(String(c.cond))
	check(dusk_names.has("bell_rung") and dusk_names.has("gate_shut"), "The gate and the bell: the bell rang and the gate is shut")
	check(by_id.wheel.allow.has("wheel"), "the wheel is allowed in its lesson")
