extends "res://tests/case.gd"
## One House, WP7: the HUD, the pages and the sound of the town (scripts/ui/town_hud.gd, slot_page.gd, slot_plan.gd, district_map.gd, sleep_fade.gd,
## town_end_card.gd, scripts/audio/town_audio.gd). The modules they read (the scenario, the perimeter, the E uses, the clearing, the base, the rescue
## list) are FAKES with the signatures of plan 2.2, so these tests do not wait for the packages that make the real ones. The HUD is the real one.

const Kit := preload("res://tests/hud_kit.gd")
const Helpers := preload("res://tests/helpers.gd")
const TownHud := preload("res://scripts/ui/town_hud.gd")
const SlotPage := preload("res://scripts/ui/slot_page.gd")
const DistrictMap := preload("res://scripts/ui/district_map.gd")
const SleepFade := preload("res://scripts/ui/sleep_fade.gd")
const TownEndCard := preload("res://scripts/ui/town_end_card.gd")
const TownAudio := preload("res://scripts/audio/town_audio.gd")


# ----------------------------------------------------------------------- the fakes --

## The scenario (OneHouse) as the HUD's clock and the parts read it.
class FakeOH:
	extends "res://scripts/sim/scenario.gd"
	var obj := {"id": "clear", "text": "Clear the house", "sub": "2 of 3 rooms clear", "at": Vector2(40, 20), "step": 2, "of": 3}
	var lesson := {"id": "aim", "text": "Hold the aim button and fire at the dead", "goal": "Put down one of the dead", "done": false}
	var end := {"title": "The house held", "line": "The dead came and the dawn found you standing.", "stats": [["Nights held", "1"], ["People", "4"], ["Houses cleared", "3"], ["The dead put down", "41"], ["Places built", "6"]], "thanks": "Thank you for playing."}
	var attacks := false
	var crew := 1

	func day() -> int:
		return 2

	func total_days() -> int:
		return 4

	func objective() -> Dictionary:
		return obj

	func guide() -> Dictionary:
		return lesson

	func end_card() -> Dictionary:
		return end

	func attacks_on() -> bool:
		return attacks

	func crew_count() -> int:
		return crew


class FakePerimeter:
	extends RefCounted
	var list := [
		{"id": "s_front", "kind": "fence", "name": "Front fence", "rect": Rect2i(10, 14, 8, 1), "state": "open", "kit": "", "hp": 0, "max_hp": 0, "unlock": {"crew": 1}, "why_not": "", "plot": "slot_front", "project": "front"},
		{"id": "s_gate", "kind": "gate", "name": "The gate", "rect": Rect2i(13, 14, 2, 1), "state": "locked", "kit": "", "hp": 0, "max_hp": 0, "unlock": {"crew": 3}, "why_not": "Opens when 3 people are here", "plot": "slot_gate", "project": "gate"},
		{"id": "s_tower", "kind": "tower", "name": "North tower", "rect": Rect2i(9, 4, 2, 2), "state": "built", "kit": "tower_small", "kit_name": "Small tower", "hp": 50, "max_hp": 100, "unlock": {"crew": 3}, "why_not": "", "plot": "slot_tower", "project": "tower"},
		{"id": "s_light", "kind": "floodlight", "name": "Floodlight", "rect": Rect2i(20, 6, 1, 1), "state": "ordered", "kit": "floodlights", "hp": 0, "max_hp": 0, "unlock": {"crew": 4}, "why_not": "", "plot": "slot_light", "project": "lights"},
	]
	var ordered: Array = []
	var cancelled: Array = []
	var demolished: Array = []
	## The page is of PROJECTS (scripts/town/perimeter.gd `projects()`): the front fence, the gate, a tower, the lights; what the page asks of them is written down here.
	var plist := [
		_project("front", "Front fence", "the front fence", "fence", "ready", {"n": 4, "open": 4, "scrap": 21, "work": 13.0, "first_scrap": 5, "can_n": 4, "minutes": 130.0, "time": "2 hours", "recommended": true, "slots": ["s_front"], "gives": "Keeps the dead off the house"}),
		_project("gate", "The gate", "the gate", "gate", "locked", {"n": 1, "open": 1, "scrap": 30, "work": 10.0, "need_crew": 3, "can_n": 0, "why": "Opens when 3 people are here", "slots": ["s_gate"]}),
		_project("tower", "Watchtower", "a watchtower", "tower", "building", {"n": 2, "built": 1, "going": 1, "open": 1, "scrap": 12, "work": 6.0, "minutes": 40.0, "time": "40 minutes", "progress": 0.5, "slots": ["s_tower"]}),
		_project("lights", "Floodlights", "the floodlights", "floodlight", "done", {"n": 1, "built": 1, "open": 0, "scrap": 0, "work": 0.0, "slots": ["s_light"]}),
	]
	var projects_ordered: Array = []
	var projects_cancelled: Array = []
	var affordable_calls := 0

	static func _project(id: String, nm: String, noun: String, icon: String, state: String, over: Dictionary) -> Dictionary:
		var p := {"id": id, "name": nm, "noun": noun, "button": "Build %s" % noun, "icon": icon, "gives": "A fence", "unit": "section", "state": state, "n": 1, "built": 0, "going": 0, "open": 1,
			"fallen": 0, "scrap": 5, "work": 3.0, "first_scrap": 0, "can_n": 1, "pay": 5, "time": "", "minutes": 30.0, "builders": 2, "builders_text": "two builders", "why": "", "recommended": false,
			"progress": 0.0, "slots": [], "need_crew": 1, "hands_minutes": 1.0, "spills": false}
		for k in over:
			p[k] = over[k]
		return p

	func projects() -> Array:
		return plist

	func order_project(id: String) -> Dictionary:
		projects_ordered.append(id)
		return {"ok": true, "line": "Ordered: %s." % id}

	func cancel_project(id: String) -> Dictionary:
		projects_cancelled.append(id)
		return {"ok": true, "line": "Order taken back: %s." % id}

	func order_affordable() -> Dictionary:
		affordable_calls += 1
		return {"ok": true, "line": "Ordered what the scrap pays for."}

	func slots() -> Array:
		return list

	func kits_for(_slot_id: String) -> Array:
		return [
			{"id": "fence", "name": "Fence", "blurb": "Cheap and weak", "scrap": 5, "work": 3, "hp": 120, "ok": true, "why": ""},
			{"id": "fence_strong", "name": "Strong fence", "blurb": "", "scrap": 12, "work": 7, "hp": 260, "ok": false, "why": "It needs 12 scrap"},
		]

	func order(slot_id: String, kit: String) -> bool:
		ordered.append([slot_id, kit])
		return true

	func cancel(slot_id: String) -> bool:
		cancelled.append(slot_id)
		return true

	func demolish(slot_id: String) -> bool:
		demolished.append(slot_id)
		return true


class FakeUses:
	extends RefCounted
	var cur := {"label": "", "t": 0.0, "of": 0.0}

	func progress() -> Dictionary:
		return cur


class FakeBase:
	extends RefCounted
	var claimed := true
	var house := 0
	var layout := {"plot": Rect2i(7, 3, 16, 14), "front": "S", "posts": [{"pos": [9, 13]}]}


class FakeHouses:
	extends RefCounted
	var town := {
		"size": Vector2i(192, 192), "streets": {"pitch": 32, "block": 28, "road": 4},
		"houses": [
			{"id": 0, "address": "14 Elm Street", "rect": Rect2i(10, 6, 8, 7)},
			{"id": 1, "address": "16 Elm Street", "rect": Rect2i(30, 6, 8, 7)},
			{"id": 2, "address": "20 Oak Street", "rect": Rect2i(70, 40, 10, 8)},
		],
	}

	func house(id: int) -> Dictionary:
		return town.houses[id]


class FakeClearing:
	extends RefCounted

	func explored() -> Array:
		return [1]


class FakeRescue:
	extends RefCounted

	func list() -> Array:
		return [
			{"id": "r0", "house": 2, "pos": Vector2(74, 44), "state": "wary", "def": {"name": "Dana Cole"}},
			{"id": "r1", "house": 1, "pos": Vector2(34, 10), "state": "hiding", "def": {"name": "Hidden Person"}},
		]


class FakeScape:
	extends RefCounted
	var rung: Array = []
	var later: Array = []

	func ring(kind: String, level := 1.0) -> void:
		rung.append([kind, level])

	func schedule(seconds: float, what: Callable) -> void:
		later.append([seconds, what])


class FakeSound:
	extends RefCounted
	var streams := {"town_thud": [1], "town_rummage": [1], "town_door_open": [1], "town_door_close": [1]}
	var scape := FakeScape.new()
	var plays: Array = []
	var uis: Array = []

	func play(name: String, level := 1.0, _pv := 0.04, _ps := 1.0) -> void:
		plays.append([name, level])

	func ui(name: String, level := 1.0, _pv := 0.02) -> void:
		uis.append([name, level])


class FakeMusic:
	extends RefCounted
	var notified: Array = []

	func notify(kind: String) -> void:
		notified.append(kind)


## What the facade gives a part as `main`: the HUD, the sim, the camera, the sound and the music, and the page keys.
class FakeMain:
	extends RefCounted
	var hud
	var sim
	var cam_center := Vector2(10, 10)
	var zoom_px := 32.0
	var sound
	var music
	var paged: Array = []

	func view_pos(e) -> Vector2:
		return Vector2(e.x, e.y)

	func page_key(page: String, full: bool = false) -> void:
		paged.append([page, full])


## The real HUD over a quiet game of three, with a OneHouse fake as its scenario and a fake main for the parts.
func _ctx() -> Dictionary:
	var ctx := Kit.build(1280, 800, 1, false, 3)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player("ruth"), "ruth is the player")
	var oh := FakeOH.new()
	sim.scenario = oh
	oh.setup(sim)
	var me = sim.avatar.player()
	me.x = 10.0
	me.y = 10.0
	var main := FakeMain.new()
	main.hud = ctx.hud
	main.sim = sim
	ctx["oh"] = oh
	ctx["main"] = main
	ctx["me"] = me
	return ctx


## Every word of every Label under a node.
func _texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)
	return out


## The first button in a row with this text (any button for ""), null when there is none.
func _button_in(row: Node, text: String) -> Button:
	for c in row.get_children():
		if c is Button and (text == "" or (c as Button).text == text):
			return c
	return null


func _has_text(n: Node, part: String) -> bool:
	for t in _texts(n):
		if String(t).contains(part):
			return true
	return false


# ------------------------------------------------------------------------- the tests --

## The objective line shows the text of objective() with its step and bearing, follows it when the house is cleared, and the banner "The house is clear" is
## said once; a room clear and a search are toasts; the HUD is in the town's calm profile.
func test_objective_line_and_banner() -> void:
	var ctx := _ctx()
	var hud = ctx.hud
	var oh = ctx.oh
	var part := TownHud.new()
	part.on_ready(ctx.main)
	check(hud.profile == "one_house", "the part puts the HUD in the town's profile")
	check(not hud.town_button.visible, "no Town Board button in the town")
	part.refresh()
	check(part.obj_card.visible, "the objective card is up")
	eq(part.obj_text.text, "Clear the house", "the objective's text")
	eq(part.obj_sub.text, "2 of 3 rooms clear", "and what is under it")
	eq(part.obj_step.text, "2 of 3", "and its step")
	check(part.distance > 25.0 and part.distance < 40.0, "the objective is 31 tiles from the avatar")
	check(part.obj_arrow.visible, "the arrow shows for a far place")
	near(part.bearing, Vector2(30, 10).angle(), 0.01, "the arrow points at it")
	# near the place the arrow goes
	ctx.me.x = 38.0
	ctx.me.y = 19.0
	part.refresh()
	check(not part.obj_arrow.visible, "no arrow when the place is at hand")
	# the house is cleared: the objective moves on, the banner comes once
	oh.obj = {"id": "claim", "text": "Claim the house", "sub": "Stand by the front door and press E", "at": Vector2(12, 12), "step": 3, "of": 3}
	part.on_event({"type": "house_clear", "house": 3})
	part.on_frame(0.0)
	eq(part.obj_text.text, "Claim the house", "the line follows the objective at the house_clear")
	eq(part.banner_count, 1, "the banner is said once")
	eq(hud.banner_title.text, "THE HOUSE IS CLEAR", "the banner's words")
	eq(hud.banner_sub.text, "Claim the house", "and what comes next")
	part.on_event({"type": "house_clear", "house": 3})
	eq(part.banner_count, 1, "not twice for the same house")
	part.on_event({"type": "house_clear", "house": 4})
	eq(part.banner_count, 2, "another house is another banner")
	part.on_event({"type": "room_clear", "room": 2, "house": 3, "name": "kitchen"})
	eq(hud.toast_label.text, "The kitchen is clear", "a room clear is a toast")
	part.on_event({"type": "searched", "container": "c1", "house": 3, "loot": {"scrap": 3.0, "food": 2.0}})
	eq(hud.toast_label.text, "Found: 3 scrap, 2 food", "a search is a toast with the loot")
	# the lesson card and its skip
	part.refresh()
	check(part.lesson_card.visible, "the lesson card is up")
	eq(part.lesson_goal.text, "Put down one of the dead", "with its goal")
	part.skip_lesson()
	part.refresh()
	check(not part.lesson_card.visible, "a skipped lesson stays away")
	oh.lesson = {"id": "door", "text": "Open a door and go in", "goal": "", "done": false}
	part.refresh()
	check(part.lesson_card.visible, "the next lesson comes")
	check(part.on_key(_key(KEY_M)) == false, "M is not the part's in a game that is not the town")
	ctx.hud.set_profile("")
	Kit.free_all(ctx)


func _key(code: Key, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	ev.shift_pressed = shift
	return ev


## The Build page is of PROJECTS (the NEXT card, a card for each, the whole plan, the plan of the lot, Advanced: the sections on their own): a locked project says why, Build calls
## perimeter.order_project, Cancel cancel_project, Build everything order_affordable; Advanced asks for the plainest kit, and takes a section down at the second press. The district map
## counts the houses and knows who waits.
func test_slot_page_and_district_map() -> void:
	var ctx := _ctx()
	var hud = ctx.hud
	var sim = ctx.sim
	var per := FakePerimeter.new()
	var fake := FakeSimView.new()
	fake.perimeter = per
	fake.scenario = ctx.oh
	fake.base = FakeBase.new()
	fake.houses = FakeHouses.new()
	fake.clearing = FakeClearing.new()
	fake.rescue = FakeRescue.new()
	fake.avatar = sim.avatar
	var page := SlotPage.new()
	ctx.holder.add_child(page)
	page.setup(hud, func(): return fake)
	# a card for every project, the recommended one over them all as NEXT
	eq(page.cards.keys(), ["front", "gate", "tower", "lights"], "a card for every project")
	eq(page.next_id, "front", "the front fence is the one to do next")
	eq(page.next_card.name.text, "Front fence", "the NEXT card names it")
	eq(page.next_card.caption.text, "NEXT", "as the next thing")
	check(page.next_card.action.visible and not page.next_card.action.disabled, "with its button")
	eq(page.next_card.action.text, "Build the front fence", "which says the whole of the job")
	eq(page.next_card.chip.text, "READY", "ready")
	check(String(page.next_card.stats.text).contains("21 scrap") and String(page.next_card.stats.text).contains("13 builder-hours"), "and its price: %s" % page.next_card.stats.text)
	check(String(page.next_card.time.text).begins_with("Takes 2 hours with two builders"), "and how long it takes: %s" % page.next_card.time.text)
	# (the plan is the front fence, 21 scrap, and the tower going up, 12: 33 scrap)
	check(page.plan_box.visible and String(page.plan_line.text).contains("33 scrap") and page.plan_chip_label.text != "", "the whole plan is summed over the card: %s / %s" % [page.plan_line.text, page.plan_chip_label.text])
	# the list: a locked project says why and has no button, a going one a meter and Cancel, a done one goes last
	var gate: Dictionary = page.cards["gate"]
	eq(gate.chip.text, "LOCKED", "a locked project says so")
	eq(gate.why.text, "Opens when 3 people are here", "and why")
	check(not gate.action.visible and not gate.cancel.visible, "and has nothing to press")
	var tower: Dictionary = page.cards["tower"]
	eq(tower.chip.text, "BUILDING 1 OF 2", "a going one says how far")
	check(tower.cancel.visible and tower.meter.visible and not tower.action.visible, "and has Cancel and a meter")
	eq(page.cards["lights"].chip.text, "DONE", "a finished one says so")
	eq(page.list_box.get_child(page.list_box.get_child_count() - 1), page.cards["lights"].panel, "and is listed last")
	eq(page.plan.slots.size(), 4, "the plan has every section")
	eq(page.plan.lot, Rect2(7, 3, 16, 14), "and the lot")
	eq(page.people_label.text, "1 in the house", "the foot says who is in the house")
	eq(page.stock_label.text, "40 scrap", "and the scrap")
	# the buttons ask the perimeter
	page.next_card.action.pressed.emit()
	eq(per.projects_ordered, ["front"], "Build calls perimeter.order_project(project)")
	eq(page.answer_label.text, "Ordered: front.", "and the page says what it answered")
	page.all_button.pressed.emit()
	eq(per.affordable_calls, 1, "Build everything I can afford calls order_affordable")
	tower.cancel.pressed.emit()
	eq(per.projects_cancelled, ["tower"], "Cancel calls perimeter.cancel_project")
	# a click picks a project, which the yard marks; the same click puts it away
	page.select("tower")
	eq(page.selected, "tower", "a project is picked")
	eq(page.marked_project(), ["tower", false], "and marked in the yard")
	page.select("tower")
	eq(page.marked_project(), ["front", true], "put away, the next one is marked, softly")
	page.focus_on("s_gate")
	eq(page.selected, "gate", "a section of the plan picks its project")
	# the words
	var p: Dictionary = per.plist[0]
	eq(page.stats_of(p), "4 sections, 21 scrap, 13 builder-hours", "the price line")
	eq(SlotPage.plural("section", 1), "section", "one")
	eq(SlotPage.plural("section", 2), "sections", "and more")
	var part: Dictionary = p.duplicate()
	part["can_n"] = 2
	eq(page.action_text(part, true), "Build 2 of 4 sections", "a part payment says how far it goes")
	part["can_n"] = 0
	check(page.action_text(part, false) == "Build", "(a small button just says Build)")
	var fallen: Dictionary = p.duplicate()
	fallen["fallen"] = 4
	eq(page.action_text(fallen, true), "Rebuild the front fence", "a fallen project is rebuilt")
	# Advanced: every section on its own, shut at first; Build asks for the first kit that can be had, a built one is taken down at the second press
	check(not page.adv_box.visible, "Advanced is shut")
	page.open_advanced()
	eq(page.adv_rows.keys(), ["s_front", "s_gate", "s_tower", "s_light"], "a row for every section")
	_button_in(page.adv_rows["s_front"].row, "Build").pressed.emit()
	eq(per.ordered, [["s_front", "fence"]], "Build calls perimeter.order(section, the first kit that can be had)")
	check(_button_in(page.adv_rows["s_gate"].row, "") == null, "a locked section has nothing to press")
	_button_in(page.adv_rows["s_light"].row, "Cancel").pressed.emit()
	eq(per.cancelled, ["s_light"], "Cancel calls perimeter.cancel")
	_button_in(page.adv_rows["s_tower"].row, "Take down").pressed.emit()
	eq(per.demolished.size(), 0, "the first press only arms Take down")
	_button_in(page.adv_rows["s_tower"].row, "Press again").pressed.emit()
	eq(per.demolished, ["s_tower"], "the second press takes it down")
	# no perimeter: nothing to build yet
	var bare := FakeSimView.new()
	var page2 := SlotPage.new()
	ctx.holder.add_child(page2)
	page2.setup(hud, func(): return bare)
	check(page2.empty_label.visible and not page2.plan.visible, "no perimeter: the page says nothing is to be built yet")
	# the district map
	var map := DistrictMap.new()
	ctx.holder.add_child(map)
	map.setup(hud, func(): return fake)
	eq(map.count_label.text, "1 of 3 houses looked in", "the map counts the houses looked in")
	eq(map.base_house(), 0, "the base is the claimed house")
	check(map.base_label.text.contains("14 Elm Street"), "the base's address")
	eq(map.known().size(), 1, "only the survivor who has been seen is known")
	eq(String(map.known()[0].name), "Someone", "who is not named until they have spoken")
	check(_has_text(map.people_box, "waits in 20 Oak Street"), "and where they wait")
	Kit.free_all(ctx)


## What the page reads of a sim, as a plain object (a game with no perimeter has none of these).
class FakeSimView:
	extends RefCounted
	var perimeter
	var scenario
	var base
	var houses
	var clearing
	var rescue
	var avatar
	var stock := {"scrap": 40.0}
	var people: Array = []
	## (the whole plan's clock reads the hour and the day)
	var hour := 9.0
	var day := 1


## The ring follows uses.progress(); the radio line says nobody is on it while the avatar is alone; the sleep fade goes dark, holds its words and comes back.
func test_progress_ring_radio_line_and_sleep_fade() -> void:
	var ctx := _ctx()
	var hud = ctx.hud
	var sim = ctx.sim
	var uses := FakeUses.new()
	# (the school's sim has no `uses` variable: the part reads it through the main's sim, so the fake sits on a view of the real one)
	ctx.main.sim = ViewWithUses.new(sim, uses)
	var part := TownHud.new()
	part.on_ready(ctx.main)
	part.refresh()
	eq(part.ring_label, "", "no session: no ring")
	uses.cur = {"label": "Searching", "t": 2.0, "of": 4.0}
	part.refresh()
	near(part.ring_t, 0.5, 0.001, "half way")
	eq(part.ring_label, "Searching 2s", "the words of the session and the seconds left")
	uses.cur = {"label": "Claiming", "t": 1.9, "of": 2.0}
	part.refresh()
	check(part.ring_t > 0.9, "nearly done")
	uses.cur = {"label": "", "t": 0.0, "of": 0.0}
	part.refresh()
	eq(part.ring_label, "", "the ring goes with the session")
	# the radio line
	check(not part.nobody_on_radio(), "three people: somebody is on the radio")
	for p in sim.people:
		if p != ctx.me:
			p.dead = true
	part.refresh()
	check(part.nobody_on_radio(), "alone: nobody is on the radio")
	check(not part.radio_card.visible, "(the line waits until the player has opened the radio: before that it is only a button in the toolbar)")
	# (this HUD kit has no radio panel to open: the part remembers that the player has opened it, which is what the line waits for)
	part._radio_opened = true
	part.refresh()
	check(part.radio_card.visible, "once the radio has been opened the line says so")
	eq(part.radio_label.text, TownHud.NOBODY_TEXT, "in its words")
	# the sleep fade
	var fade := SleepFade.new()
	fade.on_ready(ctx.main)
	check(not fade.modal(), "awake: the hands are free")
	fade.on_event({"type": "sleep", "on": true, "why": ""})
	fade.on_frame(1.0)
	near(fade.alpha, 1.0, 0.001, "black after the fade-in")
	check(fade.modal(), "asleep: the hands are off")
	fade.on_event({"type": "sleep", "on": false, "why": ""})
	eq(fade.title.text, "YOU SLEPT UNTIL DAWN", "the words on waking")
	fade.on_frame(0.5)
	near(fade.alpha, 1.0, 0.001, "the black holds under the words")
	fade.on_frame(1.0)
	fade.on_frame(0.65)
	check(fade.alpha < 0.6 and fade.alpha > 0.0, "then it fades back")
	fade.on_frame(2.0)
	check(not fade.active(), "and is gone")
	fade.on_event({"type": "sleep", "on": true, "why": ""})
	fade.on_event({"type": "sleep", "on": false, "why": "A noise woke you"})
	eq(fade.title.text, "A NOISE WOKE YOU", "a woken sleeper says why")
	Kit.free_all(ctx)


## A sim seen through a plain object: the real one for what it has and `uses` for the one thing it has not in the school.
class ViewWithUses:
	extends RefCounted
	var inner
	var uses

	func _init(s, u) -> void:
		inner = s
		uses = u

	func _get(property: StringName):
		return inner.get(property)


## The end card shows what scenario.end_card() says: the verdict, the stats row, Play again and Back to title; the HUD makes it when the night is held.
func test_end_card() -> void:
	var ctx := _ctx()
	var hud = ctx.hud
	var sim = ctx.sim
	sim.over = "victory"
	Kit.update(ctx)
	check(hud.game_over != null and hud.game_over.get_script() == TownEndCard, "the HUD ends a held town night on the town's card")
	var card = hud.game_over
	eq(card.title_label.text, "The house held", "the verdict")
	eq(card.sub_label.text, "The dead came and the dawn found you standing.", "and its line")
	eq(card.stats_row.get_child_count(), 5, "one tile for each stat")
	eq((card.stat_by_name["The dead put down"] as Label).text, "41", "the numbers are the scenario's")
	eq((card.stat_by_name["People"] as Label).text, "4")
	check(_has_text(card.stats_row, "NIGHTS HELD"), "and their names")
	check(card.thanks_label.visible and card.thanks_label.text == "Thank you for playing.", "the thanks line")
	eq(card.again_button.text, "Play again")
	eq(card.title_button.text, "Back to title")
	var got := {"meta": {}, "title": false}
	hud.restart = func(meta): got.meta = meta
	hud.on_menu = func(): got.title = true
	card.again_button.pressed.emit()
	check(bool(got.meta.get("town", false)), "Play again starts a town run")
	card.title_button.pressed.emit()
	check(bool(got.title), "Back to title goes to the title")
	# a scenario that says nothing gets plain words
	sim.scenario = Kit.FakeScenario.new()
	var plain := TownEndCard.new()
	ctx.holder.add_child(plain)
	plain.setup(hud, sim)
	eq(plain.title_label.text, TownEndCard.DEFAULT_TITLE, "no end_card(): the plain verdict")
	Kit.free_all(ctx)


## The music is told the town's truth: indoors in a house, and the fortress only while the attacks are on and it is dusk or night; the claim, the clear and the rescue
## have their sounds.
func test_music_context_and_sounds() -> void:
	var g := Helpers.town_game(1, {"blocks": 2})
	var sim = g.sim
	var oh := FakeOH.new()
	sim.scenario = oh
	oh.setup(sim)
	var main := FakeMain.new()
	main.sim = sim
	main.sound = FakeSound.new()
	main.music = FakeMusic.new()
	var part := TownAudio.new()
	part.on_ready(main)
	var me = sim.avatar.player()
	var start: Vector2 = g.town.start.pos
	me.x = start.x
	me.y = start.y
	var ctx := part.music_context({"phase": "day"})
	check(bool(ctx.indoors), "in the start house: indoors")
	check(not bool(ctx.fortress), "by day, no attacks: no fortress")
	me.x = 1.5
	me.y = 1.5
	check(not bool(part.music_context({"phase": "day"}).indoors), "out in the street: not indoors")
	oh.attacks = false
	check(not bool(part.music_context({"phase": "night", "fortress": true}).fortress), "at night with no attacks on: no fortress, whatever the school's test says")
	oh.attacks = true
	check(bool(part.music_context({"phase": "night"}).fortress), "attacks on and night: the fortress")
	check(bool(part.music_context({"phase": "dusk"}).fortress), "and at dusk")
	check(not bool(part.music_context({"phase": "day"}).fortress), "attacks on but the day: no fortress")
	check(not bool(part.music_context({"phase": "dawn"}).fortress), "and not at dawn")
	# the sounds
	part.on_event({"type": "claimed", "house": 0})
	check(main.sound.uis.has(["ui_confirm", 0.9]), "the claim has its confirm")
	check(main.sound.scape.rung.size() >= 1 and main.sound.scape.later.size() == 2, "and two chimes and the thud of the bars")
	part.on_event({"type": "rescue_joined", "id": "r0", "who": "x", "count": 1})
	check(main.music.notified == ["rescue"], "a rescue is the music's stinger")
	part.on_event({"type": "searched", "container": "c", "house": 0, "loot": {}})
	check(main.sound.plays.has(["town_rummage", 0.7]), "a search is a rummage")
	part.on_event({"type": "entered", "house": 0, "first": true})
	check(main.sound.plays.has(["town_door_open", 0.55]), "going in is a door")
	g.world.free()
