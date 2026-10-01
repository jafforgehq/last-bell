extends "res://tests/case.gd"
## assets/data/tutorial.json is data, not code: it has to be valid, every step has what the coach
## reads, every condition and beat and anchor it names exists, and the cards are short.

const Coach := preload("res://scripts/ui/coach.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")

## The order buttons' ids, and the orders and intents a step's allow list may name.
const GIZMOS := ["draft", "post", "repair", "focus", "auto", "treat", "sendout", "scavenge", "lure", "craft"]
const INTENTS := ["select", "gizmo", "move", "fields", "save", "load", "camera", "speed"]
## What the HUD's anchor_rect understands (the part before a ":" or a "."), and the world anchors.
const HUD_ANCHORS := ["stores", "stores.ammo", "stores.scrap", "stores.food", "stores.water", "stores.meds", "bar", "clock", "clock.time", "clock.forecast", "alerts", "inspect", "inspect.weapon", "speed", "fields", "help", "sound", "legend", "toast", "banner", "dialog.send", "dialog.cancel", "dialog.party"]
const OPTIONAL_KEYS := ["goal", "goals", "anchor", "allow", "pause", "pause_until", "start", "wait_title", "wait_text", "wait_anchor", "wait_allow", "fire", "focus", "follow", "clear_selection", "needs", "place", "dim", "jump", "type", "skipped_title", "skipped_text", "dialog_text", "move_inside", "move_radius", "move_min", "run_speed"]
const JUMP_KEYS := ["hour", "day", "bus", "stock", "drafted", "post", "fired", "select"]


func _steps() -> Array:
	return Coach.load_steps()


func test_the_file_is_valid_and_has_the_steps() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Coach.STEPS_PATH))
	check(typeof(parsed) == TYPE_DICTIONARY, "it is a JSON object")
	check(typeof(parsed.get("steps")) == TYPE_ARRAY, "with a list of steps")
	var steps := _steps()
	check(steps.size() >= 14 and steps.size() <= 18, "about fourteen steps, not %d" % steps.size())
	eq(String(steps[0].id), "look", "the first lesson is looking around")
	eq(String(steps[steps.size() - 1].id), "wrap", "the last card is the wrap-up")
	eq(String(steps[steps.size() - 1].get("type", "")), "wrap", "and it says so")


func test_every_step_has_what_the_coach_reads() -> void:
	var ids := {}
	for s in _steps():
		var id := String(s.get("id", ""))
		check(id != "" and id == id.to_lower() and not id.contains(" "), "a step has a plain lower-case id: '%s'" % id)
		check(not ids.has(id), "ids are unique: %s" % id)
		ids[id] = true
		for key in s:
			check(["id", "title", "text", "done"].has(key) or OPTIONAL_KEYS.has(key), "%s: '%s' is a key the coach knows" % [id, key])
		check(String(s.get("title", "")) != "" and String(s.title).length() <= 32, "%s has a short title" % id)
		check(String(s.get("text", "")) != "", "%s has its words" % id)
		check(typeof(s.get("done")) == TYPE_DICTIONARY and s.done.has("cond"), "%s says when it is done" % id)
		var allow = s.get("allow", [])
		check(typeof(allow) == TYPE_ARRAY, "%s: allow is a list" % id)
		for pattern in allow:
			var head := String(pattern).split(":")[0]
			check(String(pattern) == "*" or INTENTS.has(head), "%s: '%s' is an intent the gate knows" % [id, pattern])
			if head == "gizmo":
				var which := String(pattern).split(":")[1] if String(pattern).contains(":") else "*"
				check(which == "*" or GIZMOS.has(which), "%s: '%s' is an order the HUD has" % [id, pattern])
		if String(s.get("type", "")) != "wrap":
			check(String(s.get("goal", "")) != "" or s.get("done").cond == "next", "%s has a goal for the toast and the card (or is read and done)" % id)


func test_the_cards_are_short() -> void:
	for s in _steps():
		for key in ["text", "wait_text", "skipped_text", "dialog_text"]:
			if s.has(key):
				var n := Coach.words(String(s[key]))
				check(n <= Coach.MAX_WORDS, "%s.%s has %d words (the most is %d)" % [s.id, key, n, Coach.MAX_WORDS])
				check(n >= 6, "%s.%s says something" % [s.id, key])
		var goals: Array = []
		if s.has("goal"):
			goals.append(String(s.goal))
		for g in s.get("goals", []):
			goals.append(String(g.get("text", "")))
			check(String(g.get("when", "")) != "", "%s: a goal says when it is the one" % s.id)
		for g in goals:
			check(Coach.words(g) <= 12 and Coach.words(g) >= 2, "%s's goal '%s' is a few words" % [s.id, g])
			check(g.substr(0, 1) == g.substr(0, 1).to_lower(), "%s's goal '%s' starts in lower case (it follows 'first')" % [s.id, g])


func _conds_in(spec, out: Array) -> void:
	if typeof(spec) != TYPE_DICTIONARY or spec.is_empty():
		return
	out.append(String(spec.get("cond", "")))
	var params = spec.get("params", {})
	if typeof(params) == TYPE_DICTIONARY:
		var inner = params.get("of")
		if typeof(inner) == TYPE_ARRAY:
			for e in inner:
				_conds_in(e, out)
		elif typeof(inner) == TYPE_DICTIONARY:
			_conds_in(inner, out)


func test_every_condition_the_data_names_exists() -> void:
	var table := Conditions.registry()
	for s in _steps():
		var names: Array = []
		for key in ["done", "start", "pause_until"]:
			_conds_in(s.get(key, {}), names)
		for key in ["anchor", "wait_anchor"]:
			for entry in s.get(key, []):
				if typeof(entry) == TYPE_DICTIONARY and entry.has("when"):
					names.append(String(entry.when))
		for g in s.get("goals", []):
			names.append(String(g.get("when", "")))
		for n in names:
			check(table.has(n), "%s: the condition '%s' is in the registry" % [s.id, n])
	for n in table:
		check(table[n] is Callable and table[n].is_valid(), "%s is a Callable" % n)


func test_every_beat_a_step_fires_exists_and_each_beat_is_fired_by_a_step() -> void:
	var beats: Array = ["dusk", "more", "scratch", "fever"]
	var ids: Array = []
	for b in Orientation.BEATS:
		ids.append(String(b.id))
	eq(ids, beats, "the scenario's beats")
	var fired := {}
	for s in _steps():
		for id in s.get("fire", []):
			check(ids.has(String(id)), "%s fires '%s', which is a beat" % [s.id, id])
			fired[String(id)] = true
	for id in ids:
		check(fired.has(id), "the beat '%s' is fired by a lesson" % id)


func test_anchor_names_are_the_ones_the_hud_and_the_world_know() -> void:
	var people := ["ruth", "dez", "ana", "marcus", "walt", "hector"]
	for name in Coach.anchor_names(_steps()):
		var n := String(name)
		if n.begins_with("person:") or n.begins_with("card:"):
			check(people.has(n.split(":")[1]), "%s names someone in the crew" % n)
		elif n.begins_with("wall:"):
			check(int(n.split(":")[1]) >= 0 and int(n.split(":")[1]) <= 15, "%s names a wall section" % n)
		elif n.begins_with("gizmo:"):
			check(GIZMOS.has(n.split(":")[1]), "%s names an order button" % n)
		elif n.begins_with("speed."):
			check(int(n.split(".")[1]) >= 0 and int(n.split(".")[1]) <= 3, "%s is a speed" % n)
		elif n.begins_with("dialog.site:"):
			check(["pharmacy", "hardware", "houses", "scrapyard"].has(n.split(":")[1]), "%s names a place" % n)
		elif n == "bench" or n.begins_with("spot:"):
			pass
		else:
			check(HUD_ANCHORS.has(n), "%s is a part of the HUD" % n)


func test_the_jump_blocks_only_ask_for_what_the_scenario_can_do() -> void:
	for s in _steps():
		var jump = s.get("jump", {})
		check(typeof(jump) == TYPE_DICTIONARY, "%s: jump is a block" % s.id)
		for key in jump:
			check(JUMP_KEYS.has(key), "%s: '%s' is something jump can do" % [s.id, key])
		for id in jump.get("fired", []):
			check(["dusk", "more", "scratch", "fever"].has(String(id)), "%s: '%s' is a beat" % [s.id, id])


func test_the_helpers_of_the_gate_match_what_the_data_means() -> void:
	check(Coach.covers("select:*", "select:person:ruth"), "select:* covers a person")
	check(Coach.covers("select:person:ruth", "select:person:ruth"), "an exact key")
	check(not Coach.covers("select:person:ruth", "select:person:dez"), "not another person")
	check(not Coach.covers("select:person:ruth", "select:segment:3"), "nor a wall piece")
	check(Coach.covers("select:person:*", "select:person:dez"), "a star in the middle of a path is the last word")
	check(not Coach.covers("select:person:*", "select:segment:3"), "but not another kind")
	check(Coach.covers("gizmo:*", "gizmo:post"), "gizmo:* covers an order")
	check(not Coach.covers("gizmo:post", "gizmo:repair"), "an exact order only")
	check(Coach.covers("move", "move"), "a bare intent")
	check(not Coach.covers("move", "move:x"), "and only that")
	check(Coach.covers("*", "anything:at:all"), "a lone star is everything")
	check(not Coach.covers("select:*", "select"), "select:* wants something after it")
	eq(Coach.words("one two  three"), 3, "words are counted by spaces, doubled spaces ignored")
