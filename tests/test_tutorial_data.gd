extends "res://tests/case.gd"
## The lessons' files are data, not code: each has to be valid, every step has what the coach reads, every
## condition and beat and anchor it names exists, and the cards are short. There are two: the avatar's
## (assets/data/tutorial.json, tests/test_tutorial_avatar_data.gd looks at what is its own) and the old yard's
## (assets/data/tutorial_classic.json, what `--noavatar` plays): the checks of the first kind run on both.

const Coach := preload("res://scripts/ui/coach.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")

## The order buttons' ids, and the orders and intents a step's allow list may name.
const GIZMOS := ["draft", "post", "repair", "focus", "job_builders", "job_bench", "treat", "sendout", "scavenge", "lure"]
const INTENTS := ["select", "gizmo", "move", "fields", "save", "load", "camera", "speed", "jobs", "build", "alarm"]
## What the HUD's anchor_rect understands (the part before a ":" or a "."), and the world anchors.
const HUD_ANCHORS := ["stores", "stores.ammo", "stores.scrap", "stores.food", "stores.water", "stores.meds", "bar", "clock", "clock.time", "clock.forecast", "alerts", "inspect", "inspect.weapon", "speed", "fields", "help", "sound", "jobs", "legend", "toast", "banner", "dialog.send", "dialog.cancel", "dialog.party", "dialog.close", "ammo", "town", "build", "news", "news.panel", "alarm", "radio", "call"]
## The verbs of the radio (the anchors `radio.<verb>` and `radio.insist`).
const RADIO_PARTS := ["come", "hold", "cover", "search", "back", "post", "insist"]
## The beats of each lesson's scenario.
const CLASSIC_BEATS := ["dusk", "more", "scratch", "fever"]
const AVATAR_BEATS := ["dusk", "more", "scratch", "fever", "stray", "spent", "assault", "home"]
const OPTIONAL_KEYS := ["goal", "goals", "anchor", "allow", "pause", "pause_until", "start", "wait_title", "wait_text", "wait_anchor", "wait_allow", "fire", "focus", "follow", "clear_selection", "needs", "place", "dim", "jump", "type", "skipped_title", "skipped_text", "dialog_text", "move_inside", "move_radius", "move_min", "run_speed"]
const JUMP_KEYS := ["hour", "day", "bus", "stock", "drafted", "post", "fired", "select", "at", "mag"]
## The parts of the Duty roster's page (while it is open) that an anchor may name, and the stations a card is for.
const JOBS_PARTS := ["screen", "auto", "clear", "close", "list"]
const STATIONS := ["bench", "builders", "garden", "infirmary", "radio", "watch"]


## The old yard's lesson (what `_steps()` has always been).
func _steps() -> Array:
	return Coach.load_steps(Coach.CLASSIC_PATH)


## Both lessons: [[path, steps, the beats the scenario has]].
func _lessons() -> Array:
	return [[Coach.CLASSIC_PATH, Coach.load_steps(Coach.CLASSIC_PATH), CLASSIC_BEATS], [Coach.STEPS_PATH, Coach.load_steps(Coach.STEPS_PATH), AVATAR_BEATS]]


func test_the_file_is_valid_and_has_the_steps() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Coach.CLASSIC_PATH))
	check(typeof(parsed) == TYPE_DICTIONARY, "it is a JSON object")
	check(typeof(parsed.get("steps")) == TYPE_ARRAY, "with a list of steps")
	var steps := _steps()
	check(steps.size() >= 14 and steps.size() <= 18, "about fourteen steps, not %d" % steps.size())
	eq(String(steps[0].id), "look", "the first lesson is looking around")
	eq(String(steps[steps.size() - 1].id), "wrap", "the last card is the wrap-up")
	eq(String(steps[steps.size() - 1].get("type", "")), "wrap", "and it says so")


func test_every_step_has_what_the_coach_reads() -> void:
	for lesson in _lessons():
		_every_step_has_what_the_coach_reads(lesson[1], String(lesson[0]))


func _every_step_has_what_the_coach_reads(steps: Array, label: String) -> void:
	var ids := {}
	for s in steps:
		var id := String(s.get("id", ""))
		check(id != "" and id == id.to_lower() and not id.contains(" "), "%s: a step has a plain lower-case id: '%s'" % [label, id])
		check(not ids.has(id), "%s: ids are unique: %s" % [label, id])
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
	for lesson in _lessons():
		_the_cards_are_short(lesson[1])


func _the_cards_are_short(steps: Array) -> void:
	for s in steps:
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
			if g.has("line"):
				check(Coach.words(String(g.line)) <= 10, "%s: the line '%s' is one short line over a page" % [s.id, g.line])
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
	for lesson in _lessons():
		_every_condition_the_data_names_exists(lesson[1])


func _every_condition_the_data_names_exists(steps: Array) -> void:
	var table := Conditions.registry()
	for s in steps:
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
	for lesson in _lessons():
		_anchor_names_are_the_ones_the_hud_and_the_world_know(lesson[1])


func _anchor_names_are_the_ones_the_hud_and_the_world_know(steps: Array) -> void:
	var people := ["ruth", "dez", "ana", "marcus", "walt", "hector"]
	for name in Coach.anchor_names(steps):
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
		elif n.begins_with("jobs."):
			var part := n.trim_prefix("jobs.")
			var kind := part.get_slice(":", 0)
			var which := part.get_slice(":", 1)
			if JOBS_PARTS.has(part):
				pass
			elif kind == "row" or kind == "job" or kind == "post":
				check(people.has(which), "%s names someone in the crew" % n)
			elif kind == "station":
				check(STATIONS.has(which), "%s names a station" % n)
			else:
				check(kind == "item" and which != "", "%s is a part of the Duty roster's page" % n)
		elif n.begins_with("radio."):
			check(RADIO_PARTS.has(n.trim_prefix("radio.")), "%s names a verb of the radio (or Insist)" % n)
		elif n == "bench" or n == "zombie:near" or n.begins_with("spot:"):
			pass
		else:
			check(HUD_ANCHORS.has(n), "%s is a part of the HUD" % n)


func test_the_jump_blocks_only_ask_for_what_the_scenario_can_do() -> void:
	for lesson in _lessons():
		for s in lesson[1]:
			var jump = s.get("jump", {})
			check(typeof(jump) == TYPE_DICTIONARY, "%s: jump is a block" % s.id)
			for key in jump:
				check(JUMP_KEYS.has(key), "%s: '%s' is something jump can do" % [s.id, key])
			for id in jump.get("fired", []):
				check((lesson[2] as Array).has(String(id)), "%s: '%s' is a beat" % [s.id, id])


## Round 5's Duty roster (key J) is taught after the worktable, which gives a person the Workbench job, and
## before the wrap-up, which lists what the player now knows.
func test_the_duty_roster_lesson_comes_after_the_worktable_and_before_the_wrap_up() -> void:
	var steps := _steps()
	var ids: Array = []
	for s in steps:
		ids.append(String(s.id))
	var at := ids.find("jobs")
	check(at > 0, "there is a lesson on the duty roster")
	if at <= 0:
		return
	eq(ids.slice(at - 1, at + 2), ["workshop", "jobs", "wrap"], "right after the worktable and right before the wrap-up")
	var s: Dictionary = steps[at]
	eq(String(s.title), "The duty roster", "its title")
	eq(s.get("allow"), ["jobs"], "it allows the Jobs screen and nothing else (the clicks inside the page are the page's own)")
	check(bool(s.get("pause", false)), "the game waits while it is taught (the page pauses the rules anyway)")
	var lines: Array = []
	for g in s.get("goals", []):
		if g.has("line"):
			lines.append(String(g.line))
	eq(lines.size(), 2, "each part of the page stage has its own short line for the card over the page")
	for line in lines:
		check(Coach.words(line) >= 3 and Coach.words(line) <= 10, "'%s' is one short line" % line)
	check(String(s.get("goal", "")).contains("J") and String(s.goal).contains("Duty roster"), "its goal says what to press and what opens: %s" % s.get("goal", ""))
	# the lit part is the toolbar's button until the page is up, then the page's own buttons
	var anchors: Array = s.get("anchor", [])
	check(not anchors.is_empty() and String(anchors[anchors.size() - 1]) == "jobs", "the toolbar's Jobs button is what it points at to begin with (the last of the choices)")
	var names: Array = []
	for entry in anchors:
		names.append(String(entry.name) if typeof(entry) == TYPE_DICTIONARY else String(entry))
	check(names.has("jobs.auto") and names.has("jobs.close"), "then Auto-assign, and Close once a job is given: %s" % str(names))
	# the wrap-up lists it among the things the player can now do
	var wrap: Dictionary = steps[ids.find("wrap")]
	check(String(wrap.text).to_lower().contains("duty roster"), "the wrap-up names the duty roster")
	# the jump block for starting there (--tutorial=N): a calm morning of day two. The night's beats are not brought
	# (the walkers, the alerts, the wound and the fever would all be there, as the night's work has been done)
	var jump: Dictionary = s.get("jump", {})
	eq(int(jump.get("day", 0)), 2, "it starts on the morning of day two")
	check(float(jump.get("hour", 0.0)) >= 6.5 and float(jump.get("hour", 0.0)) <= 10.0, "in the morning")
	check(not jump.has("fired") or (jump.fired as Array).is_empty(), "with no beat of the night brought into it")


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
