extends "res://tests/case.gd"
## assets/data/tutorial.json, the avatar's Orientation Day, as data: the steps it has and in what order, that no word of any card
## names a control the avatar does not have (right-click, middle-drag, a box, a drag, picking in the world, the order keys P X C M B),
## that the keys it does name are keys the avatar has, which steps hold the game still and which need it to run, and that it
## never moves the camera (the camera is the avatar's). The checks that hold for both lessons are in tests/test_tutorial_data.gd.

const Coach := preload("res://scripts/ui/coach.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")

const IDS := ["you", "walk", "shoot", "reload", "crew", "come", "refusal", "news", "map", "alarm", "dusk", "jobs", "wrap"]
## What no card of this lesson may say: the old yard's controls, which the avatar's game does not have.
const REMOVED_WORDS := ["right-click", "right click", "middle-drag", "middle drag", "alt-drag", "alt and drag", "box", "drag", "select", "draft", "release", "send out", "repair", "lure", "pan "]
## The keys of single letters an avatar's game has (and the arrows): the only ones a card may name.
const KEYS := ["W", "S", "D", "R", "F", "T", "G", "L", "J", "V", "N"]
## The keys of the old yard's orders, which are gone.
const GONE_KEYS := ["P", "X", "C", "M", "B"]


func _steps() -> Array:
	return Coach.load_steps(Coach.STEPS_PATH)


## Every word the cards say, one string each: a step's title, text, goals and lines, what it says while it waits, over a page and
## when it is skipped.
func _words_of(s: Dictionary) -> Array:
	var out: Array = []
	for key in ["title", "text", "goal", "wait_title", "wait_text", "skipped_title", "skipped_text", "dialog_text"]:
		if s.has(key):
			out.append(String(s[key]))
	for g in s.get("goals", []):
		out.append(String(g.get("text", "")))
		if g.has("line"):
			out.append(String(g.line))
	return out


func test_it_is_the_avatars_lesson_in_order() -> void:
	var steps := _steps()
	var ids: Array = []
	for s in steps:
		ids.append(String(s.id))
	eq(ids, IDS, "the steps")
	check(steps.size() >= 12 and steps.size() <= 14, "about a dozen steps, not %d" % steps.size())
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


func test_the_keys_the_cards_name_are_named_for_what_they_do_now() -> void:
	var said := {}
	for s in _steps():
		for words in _words_of(s):
			said[String(s.id) + "|" + String(words)] = true
	var all := ""
	for k in said:
		all += " " + String(k)
	for needle in ["W A S D", "R reloads", "F swings", "T opens News", "G opens the Town Board", "L, or the Alarm button", "press J"]:
		check(all.contains(needle), "a card says '%s'" % needle)


func test_the_steps_that_need_the_world_to_move_do_not_hold_it_and_are_kept_at_normal_speed() -> void:
	for s in _steps():
		var id := String(s.id)
		if ["walk", "shoot", "reload", "dusk"].has(id):
			check(not bool(s.get("pause", false)) and not s.has("pause_until"), "%s: the game runs (the avatar walks and shoots in its time)" % id)
			eq(int(s.get("run_speed", 0)), 1, "%s: at normal speed to begin with" % id)
		if ["you", "crew", "news", "map", "jobs", "wrap"].has(id):
			check(bool(s.get("pause", false)), "%s: the game waits while it is read" % id)
		if ["come", "refusal", "alarm"].has(id):
			check(s.has("pause_until"), "%s: the game waits until the player has asked" % id)


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
		for id in s.get("jump", {}).get("fired", []):
			check(ids.has(String(id)), "%s: '%s' (in its jump) is a beat" % [s.id, id])
	for id in ["stray", "spent", "assault", "home", "scratch", "dusk"]:
		check(fired.has(id), "the beat '%s' is fired by a lesson" % id)
	for id in Orientation.AVATAR_BEATS:
		check(ids.has(id), "the scenario's beat '%s' is known to this test" % id)


func test_the_lesson_teaches_what_the_wrap_up_says_it_did() -> void:
	var steps := _steps()
	var wrap: Dictionary = steps[steps.size() - 1]
	var text := String(wrap.text).to_lower()
	for word in ["walk", "shoot", "radio", "news", "map", "alarm", "roster"]:
		check(text.contains(word), "the wrap-up names '%s'" % word)
	check(String(wrap.get("skipped_text", "")) != "" and String(wrap.get("skipped_title", "")) != "", "and it has its words for a skip")


func test_the_steps_that_wait_for_their_moment_say_what_the_wait_is() -> void:
	for s in _steps():
		if s.has("start"):
			check(String(s.get("wait_title", "")) != "" and String(s.get("wait_text", "")) != "", "%s: a card that waits has its own words" % s.id)
			check(s.has("wait_anchor"), "%s: and something to point at while it does" % s.id)
	var by_id := {}
	for s in _steps():
		by_id[String(s.id)] = s
	eq(String(by_id.dusk.start.cond), "bell_rung", "Dusk begins when the bell has rung")
	eq(String(by_id.jobs.start.cond), "day_started", "the duty roster on the morning after")


func test_the_conditions_the_steps_wait_for_are_the_ones_that_check_what_they_teach() -> void:
	var by_id := {}
	for s in _steps():
		by_id[String(s.id)] = s
	eq(String(by_id.walk.done.cond), "walked", "Walk: the player walked")
	eq(String(by_id.shoot.done.cond), "player_kills", "Aim and shoot: the player's own kill")
	eq(String(by_id.crew.done.cond), "selected", "Who is who: a crew card was clicked")
	eq(String(by_id.come.done.cond), "has_stance", "Ask, do not order: Dez does what was asked")
	eq(String(by_id.refusal.done.cond), "has_stance", "A refusal: Ana does it after the push")
	eq(String(by_id.alarm.done.cond), "alarm_cycled", "The alarm: rung and stood down")
	eq(String(by_id.map.done.cond), "board_read", "The map: the board was read and shut")
	var names: Array = []
	for c in by_id.news.done.params.of:
		names.append(String(c.cond))
	check(names.has("news_seen") and names.has("call_answered"), "News and calls: the panel was opened and the call answered")
	var reload_names: Array = []
	for c in by_id.reload.done.params.of:
		reload_names.append(String(c.cond))
	check(reload_names.has("reloaded") and reload_names.has("did"), "Reload and swing: R and F")
