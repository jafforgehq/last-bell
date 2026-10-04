extends "res://tests/case.gd"
## The Base page and the briefing card (round 25, V25.1 BASE-VIEW): the morning briefing's card (the concerns ranked, six priority chips, Use these, Details,
## Fine carry on), the Base page of the radio panel (the concerns, the priorities with what the base will do, the four dials, the facilities) and the News
## kinds of the base. The views are tested against FAKES that extend the real modules and answer the contract (canned `concerns()` and `facilities()`, a
## `toggle` that keeps the order, a `set_dial` that records and may refuse), so they hold whatever the real bodies are; the rules are the sim builders' tests.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const RadioPanel := preload("res://scripts/ui/radio_panel.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const BriefingCard := preload("res://scripts/ui/briefing_card.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const TextTests := preload("res://tests/test_hud_text.gd")

const DT := 1.0 / 30.0


# ---------------------------------------------------------------- the fakes --

class FakeBriefing:
	extends "res://scripts/sim/briefing.gd"
	var lines: Array = []
	var facs: Array = []

	func active() -> bool:
		return true

	func concerns() -> Array:
		return lines

	func facilities() -> Array:
		return facs


class FakePriorities:
	extends "res://scripts/sim/priorities.gd"
	var sugg: Array = []
	var plan := {}
	var pinned_ids: Array = []
	var released := 0
	var wall_shift := 0.0
	var ammo_shift := 0.0

	func active() -> bool:
		return true

	func toggle(id) -> Dictionary:
		var key := str(id)
		if order.has(key):
			order.erase(key)
			return {"ok": true, "why": ""}
		if order.size() >= MAX_SET:
			return {"ok": false, "why": "Four at most: tap one to drop it"}
		order.append(key)
		return {"ok": true, "why": ""}

	func set_order(ids: Array) -> Dictionary:
		order = []
		for id in ids:
			order.append(str(id))
		return {"ok": true, "why": ""}

	func rank_of(id) -> int:
		return order.find(str(id)) + 1

	func suggested() -> Array:
		return sugg

	func seat_plan() -> Dictionary:
		return plan if not order.is_empty() else {}

	func pinned() -> Array:
		return pinned_ids

	func release_pins() -> void:
		released += 1
		pinned_ids = []

	func wall_line_shift() -> float:
		return wall_shift

	func ammo_target_shift() -> float:
		return ammo_shift


class FakePolicies:
	extends "res://scripts/sim/policies.gd"
	var calls: Array = []
	var refuse := ""

	func active() -> bool:
		return true

	func set_dial(dial, option) -> Dictionary:
		calls.append([str(dial), str(option)])
		if refuse != "":
			return {"ok": false, "line": "", "why": refuse}
		current[str(dial)] = str(option)
		return {"ok": true, "line": "%s: %s. Said by the fake." % [str(dial).capitalize(), str(option)], "why": ""}

	func describe(dial, option) -> Dictionary:
		var o := str(option)
		return {"name": o.replace("_", " ").capitalize(), "blurb": "Blurb of %s." % o, "pros": ["Good of %s" % o], "cons": ["Cost of %s" % o], "title": str(dial).capitalize()}


class FakeProblems:
	extends "res://scripts/sim/problems.gd"
	var listed: Array = []

	func open() -> Array:
		return listed


## A HUD over a quiet game in avatar mode (Ruth the player; `crew` 3 is the small start, a settlement game, 6 the classic one).
func _ctx(width: int = 1280, height: int = 800, crew: int = 3, player: String = "ruth") -> Dictionary:
	var ctx := Kit.build(width, height, 1, false, crew)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	if player != "":
		check(sim.avatar.set_player(player), "%s is the player" % player)
	Kit.update(ctx)
	return ctx


func _fakes_on(sim) -> Dictionary:
	var f := {"briefing": FakeBriefing.new(), "priorities": FakePriorities.new(), "policies": FakePolicies.new(), "problems": FakeProblems.new()}
	for key in f:
		f[key].setup(sim)
		sim.set(key, f[key])
	return f


func _concerns() -> Array:
	return [
		{"id": "wall_east", "level": "alarm", "text": "East wall at 54%", "sub": "Mend it before the dead come", "page": "jobs", "focus": "builders", "score": 60.0},
		{"id": "water", "level": "warn", "text": "Water: 3 days left", "sub": "", "page": "map", "focus": "", "score": 40.0},
		{"id": "radio", "level": "info", "text": "Nobody at the radio desk: no forecast", "sub": "", "page": "jobs", "focus": "radio", "score": 20.0},
		{"id": "food", "level": "warn", "text": "Food: 3 days left", "sub": "", "page": "", "focus": "", "score": 19.0},
		{"id": "ammo", "level": "ok", "text": "Ammo is fine", "sub": "", "page": "", "focus": "", "score": 1.0},
	]


func _texts_of(node: Node) -> String:
	var out: Array = []
	_collect(node, out)
	return " | ".join(out)


func _collect(node: Node, out: Array) -> void:
	if node is Control and not node.visible:
		return
	if node is Label and node.text != "":
		out.append(node.text)
	for c in node.get_children():
		_collect(c, out)


func _main(width: int = 1280, height: int = 800) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 3, "avatar": true}, width, height)
	main.sim.waves.enabled = false
	main.sim.zombies.clear()
	main.hud.update_hud(main.sim, 1, true, 0)
	return main


func _press(main: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	main._unhandled_input(ev)


# -------------------------------------------------------------------- the card --

func test_the_briefing_card_shows_the_concerns_and_a_tap_sets_the_priorities() -> void:
	var ctx := _ctx()
	var f := _fakes_on(ctx.sim)
	f.briefing.lines = _concerns()
	f.priorities.sugg = ["water", "defence"]
	var h = ctx.hud
	check(h.show_briefing({"day": 4, "lines": _concerns(), "order": [], "suggested": ["water", "defence"]}), "the card is shown")
	check(h.briefing_open(), "and it is up")
	var card = h.briefing_card
	eq(card.title_label.text, "Morning, day 4", "it says the day")
	eq(card.line_texts(), ["East wall at 54%", "Water: 3 days left", "Nobody at the radio desk: no forecast"], "the top three concerns, as ranked")
	eq(card.chips.keys().size(), 6, "six chips")
	# a tap is the sim's toggle: the tap order is the rank, and the chip says it
	card.chips.water.pressed.emit()
	eq(f.priorities.order, ["water"], "a tap ranks it")
	eq(card.chips.water.text, "1  Water", "the rank is on the chip")
	card.chips.food.pressed.emit()
	eq(f.priorities.order, ["water", "food"], "the second tap is the second rank")
	card.chips.water.pressed.emit()
	eq(f.priorities.order, ["food"], "a tap on a ranked one drops it")
	check(card.seconds_left() <= BriefingCard.CHIP_GRACE + 0.01, "a tap leaves a few seconds for the next")
	# a fifth is refused in the sim's words and the card stays
	f.priorities.order = ["water", "food", "defence", "rest"]
	card.tap("rebuild")
	eq(card.feedback_label.text, "Four at most: tap one to drop it", "the sim's words for a fifth")
	check(h.briefing_open() and card.feedback_label.visible, "the card stays, and says it")
	# it never pauses or takes a key
	eq(ctx.speeds, [], "the game was never asked to pause")
	var loose: Array = []
	for c in card.find_children("*", "Control", true, false):
		if c.focus_mode != Control.FOCUS_NONE:
			loose.append(c.get_class())
	eq(loose, [], "no control of the card takes the keyboard")
	# Use these sets the two the concerns point at
	f.priorities.order = []
	card._sync()
	card.use_button.pressed.emit()
	eq(f.priorities.order, ["water", "defence"], "Use these sets the suggested two")
	check(not h.briefing_open(), "and the card goes")
	# its time: 25 seconds, the clock waits while the pointer is on it
	h.show_briefing({"day": 4, "lines": _concerns()})
	card = h.briefing_card
	card.tick(24.0)
	check(h.briefing_open(), "up at 24 s")
	card.tick(2.0)
	check(not h.briefing_open(), "gone at 25 s")
	h.show_briefing({"day": 4, "lines": _concerns()})
	card = h.briefing_card
	card.dismiss_button.pressed.emit()
	check(not h.briefing_open(), "Fine, carry on puts it away")
	eq(f.priorities.order, ["water", "defence"], "and changes nothing")
	Kit.free_all(ctx)


func test_the_event_brings_the_card_b_opens_the_page_and_esc_closes_the_card_first() -> void:
	var main := _main()
	var f := _fakes_on(main.sim)
	f.briefing.lines = _concerns()
	var h = main.hud
	_press(main, KEY_B)
	eq(h.radio_page(), "base", "B opens the Base page")
	_press(main, KEY_B)
	check(not h.radio_open(), "and shuts it")
	# the event: the card comes (nothing is in the way), and the game goes on
	var speed_before: int = main.speed
	main.sim.events.append({"type": "briefing", "day": 2})
	main._handle_events()
	h.update_hud(main.sim, main.speed, true, 0)
	check(h.briefing_open(), "the briefing event brings the card")
	eq(main.speed, speed_before, "and does not touch the speed")
	_press(main, KEY_T)
	check(h.radio_open(), "the panel is open too")
	_press(main, KEY_ESCAPE)
	check(not h.briefing_open() and h.radio_open(), "Esc closes the card before the panel")
	_press(main, KEY_ESCAPE)
	check(not h.radio_open(), "the next Esc closes the panel")
	# Details opens the Base page
	main.sim.events.append({"type": "briefing", "day": 3})
	main._handle_events()
	h.update_hud(main.sim, main.speed, true, 0)
	h.briefing_card.details_button.pressed.emit()
	check(not h.briefing_open() and h.radio_page() == "base", "Details opens the Base page")
	await TutorialKit.leave(main)


# --------------------------------------------------------------------- the page --

func test_the_page_shows_the_concerns_the_plan_the_pins_and_the_facilities() -> void:
	var ctx := _ctx()
	var f := _fakes_on(ctx.sim)
	f.briefing.lines = _concerns()
	f.briefing.facs = [
		{"id": "bench", "name": "Workshop", "pos": Vector2(44, 27), "ok": false, "bottleneck": "waiting on scrap", "line": "Workshop: waiting on scrap", "fix": {"page": "jobs", "focus": "bench"}},
		{"id": "garden", "name": "Garden", "pos": Vector2(30, 40), "ok": true, "bottleneck": "", "line": "Garden: tended", "fix": {"page": "jobs", "focus": "garden"}},
	]
	f.priorities.order = ["food", "defence"]
	f.priorities.plan = {"garden": 2, "bench": 1, "builders": 1}
	f.priorities.wall_shift = 0.15
	f.priorities.ammo_shift = 100.0
	f.priorities.pinned_ids = ["dez"]
	f.problems.listed = [{"id": "p1", "stage": 2}]
	f.briefing.current = {"day": ctx.sim.day, "lines": _concerns()}
	var h = ctx.hud
	Kit.update(ctx)
	eq(h.radio_panel.tab_marks("base"), {"dot": true, "bang": true}, "the Base tab: a '!' for a problem at stage 2 and a dot for a briefing nobody looked at")
	h.open_radio("base")
	Kit.update(ctx)
	var page = h.radio_panel.pages.base
	page.refresh_now()
	eq(h.radio_panel.tab_marks("base"), {"dot": false, "bang": false}, "opened: the marks go")
	# Today: the ranked concerns, the fine ones folded into a line
	var ids: Array = []
	for e in page.today_rows:
		ids.append(e.id)
	eq(ids, ["wall_east", "water", "radio", "food"], "the concerns that need something, as ranked")
	var words := _texts_of(page)
	check(words.contains("East wall at 54%") and words.contains("Water: 3 days left"), "their words are on the page")
	check(words.contains("Fine: Ammo is fine"), "the fine ones are one line")
	# a concern's button goes where it is handled
	page.today_rows[0].button.pressed.emit()
	eq(h.radio_page(), "jobs", "the button opens the page that handles it")
	h.open_radio("base")
	# Priorities: the chips, the plan, the shifts, the pins
	eq(page.chips.food.text, "1  Food", "the chips follow the sim's ranks")
	eq(page.plan_label.text, "What the base will do today: garden 2, bench 1, builders 1", "the plan is the sim's seat_plan")
	check(page.shift_label.text.contains("Wall line 70% + 15 = 85%"), "the wall line, with its base number: %s" % page.shift_label.text)
	check(page.shift_label.text.contains("Bench ammo target 300 + 100 = 400"), "and the bench's target: %s" % page.shift_label.text)
	check(page.pins_row.visible and page.pins_label.text.contains("Dez"), "who the player moved: %s" % page.pins_label.text)
	var r: Dictionary = page.tap("rest")
	check(bool(r.ok) and f.priorities.order == ["food", "defence", "rest"], "a chip tap reaches toggle")
	eq(page.chips.rest.text, "3  Rest", "and the chip says its rank")
	page.tap("water")
	var fifth: Dictionary = page.tap("rebuild")
	check(not bool(fifth.ok) and page.answer_label.visible and page.answer_label.text == "Four at most: tap one to drop it", "a fifth shows the sim's refusal")
	page.release_button.pressed.emit()
	eq(f.priorities.released, 1, "Let the base decide releases the pins")
	check(not page.pins_row.visible, "and the row goes")
	# Facilities: the line is the sim's, the working ones are folded
	eq(page.facility_lines().bench, "Workshop: waiting on scrap", "the bottleneck is the facility's own line")
	check(not page.facility_rows.garden.row.is_visible_in_tree(), "a working station is folded away")
	page.ok_toggle.pressed.emit()
	check(page.facility_rows.garden.row.is_visible_in_tree(), "until asked for")
	page.facility_rows.bench.button.pressed.emit()
	eq(h.radio_page(), "jobs", "the facility's button opens the page that fixes it")
	Kit.free_all(ctx)


func test_a_dial_press_calls_the_policy_and_a_refusal_shows_the_sims_reason() -> void:
	var ctx := _ctx()
	var f := _fakes_on(ctx.sim)
	var h = ctx.hud
	h.open_radio("base")
	Kit.update(ctx)
	var page = h.radio_panel.pages.base
	var d = page.dials
	eq(d.buttons.rations.keys(), ["full", "half", "hungry"], "rations has three options")
	eq(d.buttons.hours.keys(), ["normal", "overtime"], "hours two")
	eq(d.buttons.boldness.keys().size() + d.buttons.strangers.keys().size(), 6, "boldness and strangers three each")
	check(d.buttons.rations.full.get_meta("lit") and not d.buttons.rations.half.get_meta("lit"), "the option that is set is filled")
	check(d.consequence_text("rations").contains("Blurb of full.") and d.consequence_text("rations").contains("+ Good of full") and d.consequence_text("rations").contains("- Cost of full"), "its blurb, gain and cost are printed")
	d.buttons.rations.hungry.mouse_entered.emit()
	check(d.consequence_text("rations").contains("Blurb of hungry."), "pointing at another option shows its words")
	d.buttons.rations.hungry.mouse_exited.emit()
	# a press is set_dial
	d.buttons.rations.half.pressed.emit()
	eq(f.policies.calls, [["rations", "half"]], "a press calls the policy")
	check(d.buttons.rations.half.get_meta("lit") and not d.buttons.rations.full.get_meta("lit"), "the new option is filled")
	check(d.answer_of("rations").get("ok", false) and String(d.answer_of("rations").get("text", "")).contains("Said by the fake"), "the sim's line is shown under the dial")
	# a refusal: the sim's reason, in amber, and nothing changed
	f.policies.refuse = "Changed today: again tomorrow"
	var r: Dictionary = page.choose("hours", "overtime")
	check(not bool(r.ok), "refused")
	eq(f.policies.calls.back(), ["hours", "overtime"], "it was the sim that refused")
	eq(d.answers.hours.text, "Changed today: again tomorrow", "the reason is the sim's own")
	check(d.answers.hours.visible and d.answers.hours.get_theme_color("font_color") == Hud.WARN, "shown in amber")
	eq(f.policies.current.hours, "normal", "and the dial did not move")
	d.skip_ahead(7000)
	d.refresh()
	check(not d.answers.hours.visible, "the answer goes after a few seconds")
	f.policies.changed_day["rations"] = int(ctx.sim.day)
	d.refresh()
	check(d.tags.rations.visible and d.tags.rations.text.contains("Changed today"), "a dial changed today says so")
	Kit.free_all(ctx)


# ----------------------------------------------------------------------- the news --

func test_the_news_rows_of_the_base_show_their_lines_and_wear_their_colours() -> void:
	var ctx := _ctx()
	_fakes_on(ctx.sim)
	var radio = ctx.sim.radio
	radio.log_news("briefing", "Morning, day 3", "Top: first sub", {"data": {"lines": [{"text": "Old line one", "level": "warn"}]}})
	radio.log_news("debrief", "Evening: 1 done, 1 slipped", "", {"data": {"done": ["Food held"], "slipped": ["East wall still at 62%"]}})
	radio.log_news("briefing", "Morning, day 4", "", {"data": {"lines": [{"text": "New line one", "level": "alarm"}, {"text": "New line two", "level": "info"}]}})
	radio.log_news("policy", "Rations: half. Everyone eats a quarter less.", "")
	radio.log_news("problem", "Trouble: the rain barrels are leaking", "")
	radio.log_news("dilemma", "Fever in the camp", "")
	var h = ctx.hud
	h.open_radio("news")
	Kit.update(ctx)
	var news = h.news_panel
	news.refresh()
	eq(news.row_kinds(), ["dilemma", "problem", "policy", "briefing", "debrief", "briefing"], "newest first")
	eq(RadioKit.kind_name("briefing") + RadioKit.kind_name("debrief") + RadioKit.kind_name("policy") + RadioKit.kind_name("problem") + RadioKit.kind_name("dilemma"), "BriefingEveningPolicyTroubleChoice", "the kinds are named")
	var colors: Array = news.row_colors()
	eq(colors, [Hud.WARN, Hud.WARN, Hud.ACCENT, Hud.INFO, Hud.INFO, Hud.INFO], "briefing and evening blue, policy gold, trouble and the choice amber")
	var newest := _texts_of(news.rows[3].box)
	check(newest.contains("New line one") and newest.contains("New line two"), "the latest briefing shows its lines: %s" % newest)
	check(not _texts_of(news.rows[5].box).contains("Old line one"), "the older one is only its head")
	var evening := _texts_of(news.rows[4].box)
	check(evening.contains("Food held") and evening.contains("East wall still at 62%"), "the latest debrief shows what got done and what slipped: %s" % evening)
	Kit.free_all(ctx)


# ------------------------------------------------------------ the real modules --

func test_the_page_works_on_the_real_modules() -> void:
	# (no fakes: the game's own briefing, priorities and policies, in the real scene)
	var main := _main()
	var sim = main.sim
	var h = main.hud
	_press(main, KEY_B)
	eq(h.radio_page(), "base", "B opens the page")
	var page = h.radio_panel.pages.base
	page.refresh_now()
	check(not page.today_rows.is_empty(), "the real briefing has concerns to show")
	check(page.facility_rows.size() > 0, "and the real facilities")
	page.tap("water")
	page.tap("defence")
	eq(sim.priorities.order, ["water", "defence"], "a chip tap is the real toggle")
	eq(page.chips.defence.text, "2  Defence", "and the chip says its rank")
	page.refresh_now()
	check(page.plan_label.text.begins_with("What the base will do today"), "the plan is the real seat_plan: %s" % page.plan_label.text)
	var r: Dictionary = page.choose("rations", "half")
	check(bool(r.ok) and sim.policies.current.rations == "half", "a dial press is the real set_dial")
	var again: Dictionary = page.choose("rations", "hungry")
	check(not bool(again.ok) and String(page.dials.answer_of("rations").get("text", "")) != "", "a second change the same day is refused in the sim's words: %s" % str(again))
	check(page.dials.tags.rations.visible, "and the dial says it was changed today")
	check(h.radio_panel.pages.base.get_combined_minimum_size().y > 200.0, "(the page has a body)")
	await TutorialKit.leave(main)


# ----------------------------------------------------------------- without it --

func test_nothing_without_an_avatar_or_outside_the_small_start() -> void:
	var ctx := _ctx(1280, 800, 3, "")
	var h = ctx.hud
	_fakes_on(ctx.sim)
	check(not h.show_briefing({"day": 2, "lines": _concerns()}), "no card without an avatar")
	h.queue_briefing()
	Kit.update(ctx)
	check(not h.briefing_open() and not h.briefing_wanted, "and none is waiting")
	h.open_radio("base")
	check(not h.radio_open(), "no Base page")
	Kit.free_all(ctx)
	var classic := _ctx(1280, 800, 6)
	_fakes_on(classic.sim)
	classic.hud.open_radio("base")
	check(not classic.hud.radio_open() and not classic.hud.radio_panel.tab_button("base").visible, "the classic start has no Base page either")
	Kit.free_all(classic)
	var quiet := _ctx()
	quiet.hud.open_radio("base")
	check(quiet.hud.radio_open(), "(a small start with an avatar has it)")
	quiet.sim.priorities.enabled = false
	Kit.update(quiet)
	eq(quiet.hud.radio_page(), "news", "and the panel moves off it when the module goes (Orientation Day, the harness)")
	check(not quiet.hud.radio_panel.tab_button("base").visible, "with its tab")
	Kit.free_all(quiet)


# ------------------------------------------------------------------- the narrowest --

func test_the_page_and_the_card_fit_the_narrow_window_and_read() -> void:
	var ctx := _ctx(700, 560)
	var f := _fakes_on(ctx.sim)
	f.briefing.lines = _concerns()
	f.briefing.facs = [{"id": "bench", "name": "Workshop", "pos": Vector2(44, 27), "ok": false, "bottleneck": "waiting on scrap", "line": "Workshop: waiting on scrap", "fix": {"page": "jobs", "focus": "bench"}}]
	f.priorities.order = ["food", "defence"]
	f.priorities.plan = {"garden": 2, "bench": 1}
	f.priorities.wall_shift = 0.15
	f.priorities.pinned_ids = ["dez"]
	f.policies.changed_day["rations"] = int(ctx.sim.day)
	var h = ctx.hud
	h.open_radio("base")
	h.show_briefing({"day": 3, "lines": _concerns(), "order": [], "suggested": ["water", "defence"]})
	for i in 3:
		Kit.update(ctx)
		await Kit.settle()
	var panel = h.radio_panel
	var page = panel.pages.base
	var pr := Kit.rect(panel)
	check(h.compact and panel.is_compact(), "(the narrow form)")
	check(pr.size.x <= RadioPanel.WIDTH_COMPACT + 0.5, "the panel is no wider than its narrow form: %s" % str(pr))
	for id in RadioPanel.PAGES:
		var tab := Kit.rect(panel.tab_button(id))
		check(tab.size.x > 20.0 and pr.encloses(tab.grow(-0.5)), "the %s tab is inside the panel: %s in %s" % [id, str(tab), str(pr)])
	var card = h.briefing_card
	var cr := Kit.rect(card.panel)
	check(Rect2(0, 0, 700, 560).encloses(cr.grow(-0.5)), "the card is in the window: %s" % str(cr))
	var others := {"stores": h.res_panel, "clock": h.clock, "ammo": h.ammo_panel, "panel": panel}
	for name in others:
		check(not cr.intersects(Kit.rect(others[name])), "the card is clear of the %s: %s and %s" % [name, str(cr), str(Kit.rect(others[name]))])
	eq(card.line_texts().size(), 2, "two concerns in a small window")
	var tt := TextTests.new()
	for part in [page, card.panel]:
		eq(tt._small_text(part), [], "nothing under 12 px in %s" % part.name)
		eq(tt._hard_to_read(part, Color.WHITE), [], "every word of %s reads at 4.5:1" % part.name)
	var loose: Array = []
	var nodes: Array = page.find_children("*", "Control", true, false)
	for c in nodes:
		if c.focus_mode != Control.FOCUS_NONE:
			loose.append("%s %s" % [c.get_class(), c.name])
		if c is Button and c.disabled and c.tooltip_text.strip_edges() == "":
			loose.append("disabled without a tooltip: %s" % c.text)
	eq(loose, [], "no control of the page takes focus, every disabled one says why")
	var wide: float = page.get_combined_minimum_size().x
	check(wide <= pr.size.x, "the page needs no more width than the panel has: %.0f of %.0f" % [wide, pr.size.x])
	Kit.free_all(ctx)
