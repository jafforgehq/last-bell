extends "res://tests/case.gd"
## Round 8, the Town Board (scripts/ui/town_board.gd and its map, town_map.gd): the page the settlement game sends its
## parties from, in place of the old four-site dialog (which the classic start keeps). A map with a pin for each
## known place and a faint "?" for each place nobody has seen, the card of the chosen place, the party picker, Go,
## Scout, Clear, Claim, Garrison and Recall (each with the reason when it cannot be pressed), and the parties that are out.
## The rules behind it are tests/test_town.gd's (the core's): here the game is a settlement game on a small town of
## its own (FIX), so that what the page says can be checked exactly; the real town is looked at at the end. The key G,
## the toolbar's bag, the tutorial's lock and the hint are on the real scene at the end of this file.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const TownBoard := preload("res://scripts/ui/town_board.gd")
const TownMap := preload("res://scripts/ui/town_map.gd")
const Dialog := preload("res://scripts/ui/scavenge_dialog.gd")
const TextTests := preload("res://tests/test_hud_text.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

const FIXTURE := "user://test_town_board.json"
const SIZES := [[700, 700], [980, 700], [1280, 800], [1920, 1080]]
const SHORT := [[700, 560], [1280, 600]]

## Home is at (50, 35). Known at the start: the houses, the pharmacy, the depot (a nest of 2, someone hiding, an
## outpost to claim) and the chapel (quiet: nothing to clear). Not known: the farm, the water works, the clinic.
const FIX := {
	"board": {"w": 100, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "Neighbourhood houses", "kind": "houses", "pos": [58, 35], "blurb": "Somebody's pantry is somebody's pantry.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {"meds": [0.3, 1]}, "image": "res://assets/ui/sites/houses.png"},
		{"id": "pharmacy", "name": "The pharmacy", "kind": "pharmacy", "pos": [64, 27], "blurb": "Shelves stripped, but the back room was locked.", "danger": 2, "known": true,
			"loot": {"meds": [6, 11]}, "extra": {}, "image": "res://assets/ui/sites/pharmacy.png"},
		{"id": "depot", "name": "The bus depot", "kind": "bus_depot", "pos": [42, 26], "blurb": "Buses, nose to tail.", "danger": 2, "known": true,
			"loot": {"scrap": [10, 20]}, "extra": {}, "nest": {"strength": 2}, "survivor": true, "outpost": {"yield": {"scrap": 3}, "cost": 20}},
		{"id": "chapel", "name": "St. Aidan's chapel", "kind": "church", "pos": [50, 20], "blurb": "Quiet. Too quiet, or just a chapel.", "danger": 0, "known": true,
			"loot": {"food": [2, 4]}, "extra": {}},
		{"id": "farm", "name": "Hollis farm", "kind": "farm", "pos": [34, 18], "blurb": "A long way out.", "danger": 1,
			"loot": {"food": [10, 18]}, "extra": {}, "outpost": {"yield": {"food": 4, "water": 2}, "cost": 30}},
		{"id": "works", "name": "The water works", "kind": "water_works", "pos": [90, 60], "blurb": "Very far.", "danger": 1,
			"loot": {"water": [20, 30]}, "extra": {}},
		{"id": "clinic", "name": "Eastgate clinic", "kind": "clinic", "pos": [96, 66], "blurb": "Beyond the works.", "danger": 2,
			"loot": {"meds": [5, 9]}, "extra": {}},
	],
	"roads": [["home", "houses"], ["houses", "pharmacy"], ["home", "depot"], ["depot", "farm"], ["home", "works"], ["works", "clinic"], ["home", "chapel"]],
	"beats": [],
}

const KEYS := {"tab": KEY_TAB, "enter": KEY_ENTER, "esc": KEY_ESCAPE, "g": KEY_G, "right": KEY_RIGHT, "left": KEY_LEFT, "down": KEY_DOWN, "up": KEY_UP, "space": KEY_SPACE}


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## A settlement game on the little town, at `hour` of day 3, plenty of everything, a quiet world.
func _game(hour: float = 7.0, seed_value: int = 13) -> Dictionary:
	_write(FIX)
	Town.data_path = FIXTURE
	var g := Helpers.make(seed_value, 1, 3)
	Town.data_path = Town.DATA_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 3
	sim.minutes = hour * 60.0
	sim.clock_min = 2.0 * 1440.0 + hour * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.supplies.sources_day = 3
	sim.supplies.meal_day = 3
	sim.supplies.meals_done = 1
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	sim.events.clear()
	return g


## The HUD over that game, as main.gd's frames give it (the real modules: nothing is faked).
## One of the radio's callers comes in at once (a fourth person).
func _bring_one(ctx: Dictionary) -> void:
	var sim = ctx.sim
	var def: Dictionary = sim.recruits.queue.pop_front()
	sim.add_person(def)


func _ctx(width: int = 1280, height: int = 800, hour: float = 7.0, speed: int = 1) -> Dictionary:
	_park_the_mouse()
	var g := _game(hour)
	var sim = g.sim
	var ctx := {"g": g, "sim": sim, "pressed": [], "speeds": [], "selected": []}
	var holder := Control.new()
	holder.size = Vector2(width, height)
	Engine.get_main_loop().root.add_child(holder)
	var hud := Hud.new()
	holder.add_child(hud)
	hud.on_select = func(s): ctx.selected.append(s)
	hud.on_focus = func(_p): pass
	hud.on_speed = func(s): ctx.speeds.append(s)
	hud.on_gizmo = func(id): ctx.pressed.append(id)
	hud.on_alert = func(_id): pass
	hud.on_sound = func(): pass
	hud.setup(g.data, sim.people)
	ctx["holder"] = holder
	ctx["hud"] = hud
	Kit.update(ctx, speed)
	return ctx


## ... with the board open (for the person `who`, an id, or nobody).
func _open(width: int = 1280, height: int = 800, hour: float = 7.0, speed: int = 1, who: String = "") -> Dictionary:
	var ctx := _ctx(width, height, hour, speed)
	var sel = null
	if who != "":
		sel = {"kind": "person", "ref": _person(ctx, who)}
	ctx.hud.open_scavenge(sel)
	return ctx


func _settled(width: int, height: int, hour: float = 7.0) -> Dictionary:
	var ctx := _open(width, height, hour)
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()
	_park_the_mouse()
	await Kit.settle()
	return ctx


func _board(ctx: Dictionary):
	return ctx.hud.scavenge_dialog


func _person(ctx: Dictionary, id: String):
	return Kit.person(ctx, id)


func _park_the_mouse() -> void:
	var root: Window = Engine.get_main_loop().root
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(1, 1)
	ev.global_position = Vector2(1, 1)
	root.push_input(ev, true)


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev


## A key as the engine hears it: through the whole input path (the page's own handler first, then the controls).
func _press(code: Key) -> void:
	var root: Window = Engine.get_main_loop().root
	var down := _key(code)
	root.push_input(down, false)
	var up := _key(code)
	up.pressed = false
	root.push_input(up, false)


func _focus_owner() -> Control:
	return Engine.get_main_loop().root.gui_get_focus_owner()


func _texts(ctx: Dictionary) -> Array:
	return Kit.texts(_board(ctx))


func _has_text(ctx: Dictionary, part: String) -> bool:
	for t in _texts(ctx):
		if String(t).contains(part):
			return true
	return false


## Everything but the clock stays; the clock is moved to `hour` of today.
func _at(ctx: Dictionary, hour: float) -> void:
	var sim = ctx.sim
	sim.minutes = hour * 60.0
	sim.clock_min = 2.0 * 1440.0 + hour * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	Kit.update(ctx, 1)


# ----------------------------------------------------------------- what opens it --

func test_the_settlement_game_opens_the_board_and_the_classic_start_the_old_dialog() -> void:
	var ctx := _open()
	check(_board(ctx) != null and _board(ctx).get_script() == TownBoard, "a settlement game: the Town Board")
	check(ctx.hud.town_board_open() and ctx.hud.modal_open(), "the HUD knows it, and takes it for a page over the game")
	Kit.free_all(ctx)
	var classic := Kit.build()
	Kit.update(classic)
	classic.hud.open_scavenge(null)
	check(classic.hud.scavenge_dialog != null and classic.hud.scavenge_dialog.get_script() == Dialog, "the classic start: the old dialog, as it was")
	check(not classic.hud.town_board_open(), "and no board")
	Kit.free_all(classic)


func test_the_toolbar_has_the_boards_button_only_in_a_settlement_game() -> void:
	var ctx := _ctx()
	check(ctx.hud.town_button.visible, "a settlement game has the button")
	eq(ctx.hud.help_g.text, "Town Board", "and the help says what G does there")
	check(ctx.hud.town_button.tooltip_text.contains("Key: G"), "the tooltip names the key")
	Kit.free_all(ctx)
	var classic := Kit.build()
	Kit.update(classic)
	check(not classic.hud.town_button.visible, "the classic start has none")
	eq(classic.hud.help_g.text, "Scavenge", "and G is Scavenge in the help")
	Kit.free_all(classic)


func test_the_selected_person_leads_and_a_person_who_cannot_go_is_replaced() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "dez")
	eq(_board(ctx).party, [_person(ctx, "dez")], "the person selected leads, alone")
	Kit.free_all(ctx)
	ctx = _open()
	eq(_board(ctx).party, [ctx.sim.scavenge.free_survivors()[0]], "with nobody selected the first who is free leads")
	Kit.free_all(ctx)
	# a selected person who is drafted cannot go: the first who can leads, and the page says so
	ctx = _ctx()
	var marcus = _person(ctx, "marcus")
	marcus.drafted = true
	marcus.order = {"x": 30.0, "y": 30.0}
	ctx.hud.open_scavenge({"kind": "person", "ref": marcus})
	var board = _board(ctx)
	check(not board.party.has(marcus) and board.party.size() == 1, "somebody else leads")
	check(_has_text(ctx, "Marcus can't go out now."), "and the page says why not him")
	Kit.free_all(ctx)


func test_it_pauses_the_game_and_gives_the_speed_back() -> void:
	var ctx := _open(1280, 800, 7.0, 2)
	eq(ctx.speeds, [0], "the rules wait while it is up")
	_board(ctx).close()
	eq(ctx.speeds, [0, 2], "and the speed comes back when it is closed")
	check(ctx.hud.scavenge_dialog == null and not ctx.hud.town_board_open(), "nothing is left open")
	Kit.free_all(ctx)
	# paused already: nothing is changed, nothing is given back
	ctx = _open(1280, 800, 7.0, 0)
	_board(ctx).close()
	eq(ctx.speeds, [], "a game that was paused stays paused")
	Kit.free_all(ctx)


func test_it_does_not_stack_nor_open_over_another_page() -> void:
	var ctx := _open()
	var first = _board(ctx)
	ctx.hud.open_scavenge(null)
	check(_board(ctx) == first, "a second open does nothing")
	first.close()
	# a page that covers the game (the radio card is one)
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	ctx.hud.add_child(page)
	ctx.hud.open_scavenge(null)
	check(ctx.hud.scavenge_dialog == null, "not over a page that covers the game")
	page.free()
	# the Jobs screen has the game while it is up
	ctx.hud.open_jobs(ctx.sim)
	check(ctx.hud.jobs_screen != null, "(the Jobs screen is open)")
	ctx.hud.open_scavenge(null)
	check(ctx.hud.scavenge_dialog == null, "nor over the Jobs screen")
	ctx.hud.close_jobs()
	ctx.hud.open_scavenge(null)
	check(ctx.hud.town_board_open(), "but it opens once nothing is in the way")
	ctx.hud.open_jobs(ctx.sim)
	check(ctx.hud.jobs_screen == null, "and the Jobs screen does not open over it")
	Kit.free_all(ctx)


func test_it_is_gone_when_the_run_ends() -> void:
	var ctx := _open()
	ctx.sim.over = "lost"
	Kit.update(ctx)
	check(ctx.hud.scavenge_dialog == null and ctx.hud.game_over != null, "the end screen takes the page's place")
	Kit.free_all(ctx)


# ------------------------------------------------------------------------ the map --

func test_the_map_has_a_pin_for_each_known_place_and_a_faint_question_mark_for_each_other() -> void:
	var ctx := _open()
	var map = _board(ctx).map
	var ids: Array = map.pins.keys()
	ids.sort()
	eq(ids, ["chapel", "depot", "houses", "pharmacy"], "a pin for each place that is known")
	var guesses: Array = []
	for u in map.unknown:
		guesses.append(String(u.id))
	guesses.sort()
	eq(guesses, ["clinic", "farm", "works"], "a question mark for each that is not")
	for u in map.unknown:
		var real: Vector2 = Vector2(ctx.sim.town.place(String(u.id)).pos)
		var off: float = Vector2(u.pos).distance_to(real)
		check(off <= TownMap.UNKNOWN_SHIFT * 1.5 + 0.01, "%s: the mark is near the place (%.2f tiles off)" % [u.id, off])
	for id in ids:
		check(map.pins[id] is Button and map.pins[id].tooltip_text.begins_with(String(ctx.sim.town.place(id).name)), "%s: a button with the place's name for a tooltip: '%s'" % [id, map.pins[id].tooltip_text])
	Kit.free_all(ctx)


func test_the_roads_are_inked_between_known_places_and_a_stub_leads_on_to_the_unknown() -> void:
	var ctx := _open()
	var map = _board(ctx).map
	var solid := 0
	var stubs := 0
	for r in map.roads:
		if bool(r.stub):
			stubs += 1
		else:
			solid += 1
	# known: houses, pharmacy, depot, chapel (and the school): home-houses, houses-pharmacy, home-depot, home-chapel
	eq(solid, 4, "four roads between places that are known")
	# depot-farm (the farm is not known) and home-works lead on; works-clinic and the others are not drawn at all
	eq(stubs, 2, "two stubs lead on to places that are not")
	eq(map.streets.size(), 7, "every street keeps the decoration off")
	ctx.sim.town.reveal("works")
	_board(ctx).refresh()
	solid = 0
	stubs = 0
	for r in map.roads:
		if bool(r.stub):
			stubs += 1
		else:
			solid += 1
	eq(solid, 5, "a revealed place gets its road")
	eq(stubs, 2, "and the stub of the next one on (the clinic) appears")
	Kit.free_all(ctx)


func test_a_place_revealed_while_the_page_is_open_gets_its_pin() -> void:
	var ctx := _open()
	var board = _board(ctx)
	check(not board.map.pins.has("farm"), "(the farm is not there)")
	ctx.sim.town.reveal("farm")
	Kit.update(ctx)
	check(board.map.pins.has("farm"), "the HUD's update brings the pin")
	var guesses: Array = []
	for u in board.map.unknown:
		guesses.append(String(u.id))
	check(not guesses.has("farm") and guesses.size() == 2, "and takes its question mark away")
	# the place chosen is revealed away: the card goes back to nothing chosen (this cannot happen in the rules, but is safe)
	board.select_place("farm")
	eq(board.site_id, "farm", "(the farm is chosen)")
	ctx.sim.town.state["farm"].known = false
	board.refresh(true)
	eq(board.site_id, "", "a place that is not known is not chosen")
	check(board.empty_label.visible and not board.place_view.visible, "and the card says nothing is chosen")
	Kit.free_all(ctx)


func test_a_person_who_becomes_free_while_the_page_is_open_is_offered() -> void:
	var ctx := _open()
	var board = _board(ctx)
	# somebody is busy at the start, and then is not
	var marcus = _person(ctx, "marcus")
	marcus.drafted = true
	marcus.order = {"x": 30.0, "y": 30.0}
	board.refresh()
	check(not board.chips.has("marcus"), "Marcus is busy: not offered")
	marcus.drafted = false
	marcus.order = null
	board.refresh()
	check(board.chips.has("marcus"), "free: offered")
	# the leader goes out of reach: somebody else leads
	var lead = board.party[0]
	lead.drafted = true
	lead.order = {"x": 30.0, "y": 30.0}
	board.refresh()
	check(board.party.size() == 1 and board.party[0] != lead, "a leader who can no longer go is replaced")
	Kit.free_all(ctx)


func test_hovering_a_pin_shows_its_name_and_a_pin_chosen_is_ringed() -> void:
	var ctx := await _settled(1280, 800)
	var map = _board(ctx).map
	var pin = map.pins["pharmacy"]
	check(not pin.get_meta("caption").visible or map.captions().has("pharmacy"), "(captions are only where there is room)")
	pin.mouse_entered.emit()
	eq(map.hovered, "pharmacy", "the pointer on a pin")
	check(pin.get_meta("caption").visible and pin.get_meta("caption").text == "The pharmacy", "its name is on the map")
	pin.mouse_exited.emit()
	eq(map.hovered, "", "and gone with the pointer")
	# at a narrow width only the pins that are hovered or chosen have their names
	Kit.free_all(ctx)
	ctx = await _settled(700, 700)
	map = _board(ctx).map
	pin = map.pins["pharmacy"]
	check(map.size.x < TownMap.CAPTION_MIN_W + 100.0, "(the map is narrow: %.0f)" % map.size.x)
	pin.mouse_entered.emit()
	check(pin.get_meta("caption").visible, "hovered: it has its name")
	pin.mouse_exited.emit()
	_board(ctx).select_place("pharmacy")
	check(pin.get_meta("caption").visible, "chosen: it has its name")
	eq(map.chosen, "pharmacy", "the map knows which is chosen")
	Kit.free_all(ctx)


func test_every_place_has_a_caption_where_there_is_room_and_they_never_cover_each_other() -> void:
	var ctx := await _settled(1920, 1080)
	var map = _board(ctx).map
	var rects: Dictionary = {}
	for id in map.captions():
		var label: Label = map.home_marker.get_meta("caption") if id == "home" else map.pins[id].get_meta("caption")
		rects[id] = Rect2(label.position, label.size)
	check(rects.size() >= 4, "the places have their names on a big map: %s" % str(map.captions()))
	eq(Kit.overlaps(rects, 0.5), [], "no two names overlap")
	for id in rects:
		check(Rect2(Vector2.ZERO, map.size).encloses(rects[id]), "%s: the name is on the map" % id)
	Kit.free_all(ctx)


func test_the_unknown_marks_and_the_other_drawings_come_out_without_error_at_every_size() -> void:
	# the map draws itself on the engine's own frames; a script error in a drawing would show in the log of the run
	for size in SIZES:
		var ctx := await _settled(size[0], size[1])
		var board = _board(ctx)
		board.select_place("depot")
		await Kit.settle()
		ctx.sim.town.state["depot"].cleared = true
		ctx.sim.town.state["depot"].claimed = true
		ctx.sim.town.set_garrison("depot", ["dez"])
		ctx.sim.town.reveal("farm")
		board.refresh(true)
		await Kit.settle()
		check(board.map.is_visible_in_tree() and board.map.size.x > 0.0, "%d: the map is on the page" % size[0])
		Kit.free_all(ctx)


# ------------------------------------------------------------------------ the card --

func test_choosing_a_place_fills_the_card() -> void:
	var ctx := _open()
	var board = _board(ctx)
	check(board.empty_label.visible and not board.place_view.visible, "nothing is chosen: the card says so")
	check(board.select_place("pharmacy"), "the pharmacy is chosen")
	check(board.place_view.visible and not board.empty_label.visible, "the card shows a place")
	eq(board.name_label.text, "The pharmacy", "its name")
	var all := _texts(ctx)
	check(all.has("Shelves stripped, but the back room was locked."), "its blurb")
	check(all.has("The dead are thick here"), "how dangerous it is, in words")
	check(_has_text(ctx, "there and back"), "how long the trip takes")
	check(all.has("Meds"), "and what it is likely to give (the hint)")
	check(all.has("6–11"), "with its amounts")
	check(not board.facts.nest.cap.visible and not board.facts.hiding.cap.visible and not board.facts.outpost.cap.visible and not board.facts.held.cap.visible, "no nest, nobody hiding, no outpost, no garrison: none of them is on the card")
	check(board.thumb.visible and board.thumb.texture != null, "the picture of the pharmacy")
	eq(board.map.chosen, "pharmacy", "and the pin is the chosen one")
	check(not select_unknown(board), "a place that is not known cannot be chosen")
	Kit.free_all(ctx)


func select_unknown(board) -> bool:
	return board.select_place("farm") or board.select_place("nowhere")


func test_the_card_tells_of_the_nest_the_one_hiding_and_the_outpost() -> void:
	var ctx := _open()
	var board = _board(ctx)
	board.select_place("depot")
	check(board.facts.nest.cap.visible and String(board.facts.nest.label.text).begins_with("Strength 2"), "the nest and its strength: '%s'" % board.facts.nest.label.text)
	check(String(board.facts.nest.label.text).contains("The nights lean to the "), "and which way the nights lean")
	check(board.facts.hiding.cap.visible and String(board.facts.hiding.label.text).begins_with("Someone is hiding here"), "someone is hiding there")
	var outpost: String = board.facts.outpost.label.text
	check(board.facts.outpost.cap.visible and outpost.contains("3 scrap a day") and outpost.contains("20 scrap"), "what an outpost would yield and cost: '%s'" % outpost)
	check(Kit.texts(board.tag_flow).has("NEST 2"), "a tag for the nest")
	check(not board.facts.held.cap.visible, "nobody holds it: not an outpost yet")
	# cleared: the nest is gone and the danger with it
	ctx.sim.town.state["depot"].cleared = true
	board.refresh(true)
	check(String(board.facts.nest.label.text).begins_with("Gone"), "cleared, the nest is gone: '%s'" % board.facts.nest.label.text)
	check(String(board.facts.danger.label.text).begins_with("None left"), "and so is the danger: '%s'" % board.facts.danger.label.text)
	check(Kit.texts(board.tag_flow).has("CLEARED"), "the card says cleared")
	check(String(board.facts.outpost.label.text).begins_with("Can be claimed"), "and that it could be claimed: '%s'" % board.facts.outpost.label.text)
	# claimed, and held
	ctx.sim.town.state["depot"].claimed = true
	ctx.sim.town.set_garrison("depot", ["dez", "marcus"])
	board.refresh(true)
	check(Kit.texts(board.tag_flow).has("YOUR OUTPOST"), "an outpost of yours")
	check(board.facts.held.cap.visible and board.facts.held.label.text == "Dez and Marcus", "and who holds it: '%s'" % board.facts.held.label.text)
	ctx.sim.town.set_garrison("depot", [])
	board.refresh(true)
	check(String(board.facts.held.label.text).begins_with("Nobody"), "or nobody")
	Kit.free_all(ctx)


func test_a_place_picked_over_or_raided_says_so() -> void:
	var ctx := _open()
	var board = _board(ctx)
	ctx.sim.scavenge.raids["houses"] = [3]
	board.refresh(true)
	board.select_place("houses")
	check(board.facts.note.cap.visible and String(board.facts.note.label.text).begins_with("Picked over. Ready again on day 6"), "picked over: '%s'" % board.facts.note.label.text)
	ctx.sim.scavenge.raids["houses"] = [1]
	ctx.sim.day = 4
	board.refresh(true)
	check(board.facts.note.cap.visible and String(board.facts.note.label.text).begins_with("Raided on day 1"), "raided: '%s'" % board.facts.note.label.text)
	ctx.sim.scavenge.raids.erase("houses")
	board.refresh(true)
	check(not board.facts.note.cap.visible, "nothing done to it: no line")
	Kit.free_all(ctx)


func test_the_trip_says_when_the_party_will_be_back_and_when_it_is_a_night_out() -> void:
	var ctx := _open()
	var board = _board(ctx)
	board.select_place("houses")
	var hours: float = ctx.sim.town.trip_hours("houses")
	var line: String = board.facts.trip.label.text
	check(line.contains("there and back") and line.contains("Back about"), "the near place is back the same day: '%s'" % line)
	var want: String = TownBoard._clock(7.0 + hours)
	check(line.contains(want), "at about %s (7 o'clock and the trip's %.1f hours): '%s'" % [want, hours, line])
	# a far place: past dusk
	ctx.sim.town.reveal("works")
	ctx.sim.town.reveal("clinic")
	board.refresh(true)
	board.select_place("clinic")
	line = board.facts.trip.label.text
	check(ctx.sim.town.trip_hours("clinic") > 12.0, "(the clinic is more than twelve hours there and back: %.1f)" % ctx.sim.town.trip_hours("clinic"))
	check(line.contains("Back tomorrow") and line.contains("night out"), "a long trip is back tomorrow, a night out: '%s'" % line)
	# at night nobody can go: the trip is told as if it left at first light
	_at(ctx, 21.0)
	board.select_place("houses")
	check(String(board.facts.trip.label.text).contains(TownBoard._clock(7.0 + hours)), "at night the page counts from first light: '%s'" % board.facts.trip.label.text)
	Kit.free_all(ctx)


func test_the_clock_is_told_to_the_quarter_hour() -> void:
	eq(TownBoard._clock(14.5), "14:30", "half past two")
	eq(TownBoard._clock(7.0), "07:00", "seven")
	eq(TownBoard._clock(9.8), "09:45", "to the nearest quarter")
	eq(TownBoard._clock(23.99), "00:00", "and midnight when it rounds up to it")
	eq(TownMap.hours_text(0.3), "under an hour", "short")
	eq(TownMap.hours_text(1.0), "about an hour", "one")
	eq(TownMap.hours_text(3.0), "about 3 hours", "three")
	eq(TownMap.hours_text(4.4), "about 4.5 hours", "four and a half")


# --------------------------------------------------------------------- the party --

func test_the_picker_offers_the_free_people_with_their_shooting_and_the_leader_first() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "dez")
	var board = _board(ctx)
	var ids: Array = board.chips.keys()
	ids.sort()
	eq(ids, ["dez", "marcus", "ruth"], "the three who are free")
	var dez_chip: Button = board.chips.dez.chip
	check(Kit.texts(dez_chip).has("Shooting 6") and Kit.texts(dez_chip).has("Leading 2"), "Dez's skills: %s" % str(Kit.texts(dez_chip)))
	check(board.chips.dez.lead.visible and not board.chips.ruth.lead.visible, "Dez leads: the star is on his chip")
	check(board._tip_label.text.begins_with("Dez leads."), "and the line over the chips says so: '%s'" % board._tip_label.text)
	check(dez_chip.get_child(0).get_child(0).get_child(0) is TextureRect, "a chip has a portrait")
	# someone who is away is not offered
	_person(ctx, "marcus").away = {"kind": "lost", "site": "houses"}
	board.refresh(true)
	check(not board.chips.has("marcus"), "a person who is away is not offered")
	Kit.free_all(ctx)


func test_the_party_is_one_to_three_and_the_leader_is_the_first() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	# a fourth person for the test
	_bring_one(ctx)
	board.refresh(true)
	var ruth = _person(ctx, "ruth")
	var dez = _person(ctx, "dez")
	var marcus = _person(ctx, "marcus")
	eq(board.party, [ruth], "Ruth alone to begin with")
	check(not board.toggle_member(ruth), "the only one cannot be taken out: nobody would go")
	check(board.toggle_member(dez) and board.toggle_member(marcus), "two more can come")
	eq(board.party, [ruth, dez, marcus], "in the order they were asked")
	var extra = ctx.sim.people[ctx.sim.people.size() - 1]
	check(extra.id != "ruth" and not board.toggle_member(extra) and board.party.size() == 3, "a fourth cannot: three is the most")
	check(String(board.error_label.text) == "Three is the most." and board.error_label.visible, "and the page says so")
	check(board.toggle_member(ruth), "the leader can step out")
	eq(board.party, [dez, marcus], "and the next one leads")
	check(board.chips.dez.lead.visible and not board.chips.marcus.lead.visible, "the star follows")
	Kit.free_all(ctx)


func test_the_page_says_what_the_party_will_be_like_on_the_road() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "dez")
	var board = _board(ctx)
	check(board._effect_label.visible and board._effect_label.text.begins_with("A lone scavenger brings back less."), "alone: '%s'" % board._effect_label.text)
	board.toggle_member(_person(ctx, "marcus"))
	check(not board._effect_label.visible, "two with no leader: nothing to say")
	board.toggle_member(_person(ctx, "ruth"))
	check(board._effect_label.visible and board._effect_label.text.contains("Ruth leads well"), "Ruth leads well (Leading 9): '%s'" % board._effect_label.text)
	Kit.free_all(ctx)


func test_when_nobody_is_free_the_page_says_so_and_nothing_can_be_sent() -> void:
	var ctx := _ctx()
	for p in ctx.sim.people:
		p.drafted = true
		p.order = {"x": 30.0, "y": 30.0}
	ctx.hud.open_scavenge(null)
	var board = _board(ctx)
	check(board != null, "the page still opens: the map is for planning")
	eq(board.party, [], "nobody is going")
	board.select_place("houses")
	check(board._tip_label.text == "Nobody is free to go.", "it says so: '%s'" % board._tip_label.text)
	for action in ["loot", "scout", "clear"]:
		eq(board.reason_for(action), "Nobody is free to go.", "%s: the rules' own words" % action)
		check(board.buttons[action].disabled, "%s is off" % action)
	Kit.free_all(ctx)


# ----------------------------------------------------------------------- buttons --

func _button_state(board, action: String) -> Dictionary:
	var b: Button = board.buttons[action]
	return {"shown": b.visible, "off": b.disabled, "why": board.why_line_for(action), "tip": b.tooltip_text}


func test_before_a_place_is_chosen_every_button_is_off_and_says_why() -> void:
	var ctx := _open()
	var board = _board(ctx)
	for action in ["loot", "scout", "clear", "claim", "garrison", "recall"]:
		var st := _button_state(board, action)
		check(st.off, "%s: off" % action)
		eq(board.reason_for(action), "Pick a place on the map first.", "%s: the reason" % action)
		eq(st.tip, "Pick a place on the map first.", "%s: the tooltip says it" % action)
	var lines := 0
	for l in board.why_lines:
		if l.visible:
			lines += 1
	eq(lines, 1, "one line under the buttons says it for all of them")
	check(board.why_line_for("loot") == "Go, Scout, Clear, Claim, Garrison and Recall: Pick a place on the map first.", "'%s'" % board.why_line_for("loot"))
	Kit.free_all(ctx)


func test_go_scout_and_clear_for_a_place_with_the_dead_about() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	board.select_place("houses")
	for action in ["loot", "scout", "clear"]:
		var st := _button_state(board, action)
		check(st.shown and not st.off and st.why == "", "%s: can be pressed, and has no reason" % action)
		check(st.tip != "", "%s: and a tooltip says what it does: '%s'" % [action, st.tip])
	check(String(board.buttons.clear.tooltip_text).contains("a risk"), "Clear: Ruth alone against danger 1 is a risk (the chance in words): '%s'" % board.buttons.clear.tooltip_text)
	var st2 := _button_state(board, "claim")
	check(not st2.shown, "no outpost to claim: Claim is not offered")
	check(not _button_state(board, "garrison").shown and not _button_state(board, "recall").shown, "and Garrison and Recall are for an outpost")
	eq(board.buttons.loot.text, "Go", "Go is the first")
	check(board.buttons.loot.get_theme_color("font_color") == board._button("x", true).get_theme_color("font_color"), "and the main choice, in the dialogs' gold")
	Kit.free_all(ctx)


func test_a_nest_takes_two_and_a_quiet_place_has_nothing_to_clear() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	board.select_place("depot")
	var st := _button_state(board, "clear")
	check(st.off and st.why == "Clear: A nest takes at least two." and st.tip == "A nest takes at least two.", "alone: '%s' / '%s'" % [st.why, st.tip])
	var claim := _button_state(board, "claim")
	check(claim.shown and claim.off and claim.why.begins_with("Claim: Clear it first"), "Claim is shown, off, and says to clear it first: '%s'" % claim.why)
	board.toggle_member(_person(ctx, "dez"))
	st = _button_state(board, "clear")
	check(not st.off and st.why == "", "with a second person Clear can be pressed")
	check(String(board.buttons.clear.tooltip_text).contains("likely"), "Ruth and Dez against a nest of 2 at danger 2: likely: '%s'" % board.buttons.clear.tooltip_text)
	board.select_place("chapel")
	st = _button_state(board, "clear")
	check(st.off and st.why == "Clear: There is nothing to clear.", "a quiet chapel: '%s'" % st.why)
	check(not _button_state(board, "claim").shown, "(the chapel has no outpost)")
	Kit.free_all(ctx)


func test_the_clear_chance_is_told_in_words_from_the_rules_own_sum() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	var ruth = _person(ctx, "ruth")
	var dez = _person(ctx, "dez")
	var marcus = _person(ctx, "marcus")
	near(board.clear_chance([ruth], "houses"), 0.35 + 0.08 * 5.0 - 0.12 * 1.0, 1e-9, "Ruth at the houses")
	near(board.clear_chance([ruth, dez], "depot"), 0.35 + 0.08 * 11.0 - 0.12 * 4.0, 1e-9, "Ruth and Dez at a nest of 2 in danger 2")
	near(board.clear_chance([marcus, dez, ruth], "chapel"), 0.95, 1e-9, "the best is kept to 0.95")
	ctx.sim.town.place("works").danger = 3
	near(board.clear_chance([ruth], "works"), 0.35 + 0.4 - 0.36, 1e-9, "a hard place for one")
	near(board.clear_chance([], "works"), 0.1, 1e-9, "and the least is 0.1")
	eq(TownBoard.chance_words(0.9), "likely", "words: likely")
	eq(TownBoard.chance_words(0.65), "likely", "(at 0.65)")
	eq(TownBoard.chance_words(0.5), "a risk", "words: a risk")
	eq(TownBoard.chance_words(0.4), "a risk", "(at 0.4)")
	eq(TownBoard.chance_words(0.2), "unlikely", "words: unlikely")
	# a cleared place has no danger and no nest left
	ctx.sim.town.state["depot"].cleared = true
	near(board.clear_chance([ruth], "depot"), 0.35 + 0.4, 1e-9, "a cleared place is as easy as it gets")
	Kit.free_all(ctx)


func test_the_words_follow_the_rules_throws_of_the_dice() -> void:
	# the page's chance is the one `_decide_town` rolls against: over many throws the party clears about that often
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	var sim = ctx.sim
	for case in [[["ruth"], "houses"], [["ruth", "dez"], "depot"], [["dez"], "pharmacy"]]:
		var people: Array = []
		var ids: Array = []
		for id in case[0]:
			people.append(_person(ctx, id))
			ids.append(id)
		var want: float = board.clear_chance(people, case[1])
		var wins := 0
		var n := 700
		for i in n:
			var result: Dictionary = sim.scavenge._decide({"site": case[1], "action": "clear", "members": ids})
			if bool(result.get("clear", false)):
				wins += 1
		var got := float(wins) / float(n)
		check(absf(got - want) < 0.07, "%s at %s: the page says %.2f, the dice give %.2f" % [str(case[0]), case[1], want, got])
	Kit.free_all(ctx)


func test_no_party_can_go_at_night_in_the_morning_rush_or_with_both_out() -> void:
	var ctx := _open(1280, 800, 21.0, 1, "ruth")
	var board = _board(ctx)
	board.select_place("houses")
	for action in ["loot", "scout", "clear"]:
		eq(board.reason_for(action), "Nobody goes out after dark.", "%s at night" % action)
		check(board.buttons[action].disabled and board.why_line_for(action) == "Go, Scout and Clear: Nobody goes out after dark.", "%s: off, with one line under the buttons for the three: '%s'" % [action, board.why_line_for(action)])
	_at(ctx, 6.0)
	eq(board.reason_for("loot"), "Too early: wait for daylight (06:30).", "at dawn")
	_at(ctx, 11.0)
	eq(board.reason_for("loot"), "Too late: parties leave between 06:30 and 10:00.", "after ten")
	_at(ctx, 7.0)
	eq(board.reason_for("loot"), "", "at seven it can go")
	# the dead at the gate
	var gate: Vector2 = ctx.sim.scavenge.gate_center()
	for i in 4:
		ctx.sim.spawn(gate.x + float(i), gate.y - 3.0, "approach")
	eq(board.reason_for("loot"), "Too many of the dead at the gate.", "the dead at the gate")
	ctx.sim.zombies.clear()
	# two parties out
	check(ctx.sim.scavenge.send([_person(ctx, "dez")], "houses", "loot"), "(one party goes)")
	check(ctx.sim.scavenge.send([_person(ctx, "marcus")], "pharmacy", "loot"), "(and another)")
	board.refresh(true)
	eq(board.reason_for("loot"), "Both parties are out.", "the rules' words for two out")
	eq(board.reason_for("scout"), "Both parties are out.", "for all three")
	Kit.free_all(ctx)


func test_a_place_picked_over_cannot_be_looted_and_says_when_it_opens() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	ctx.sim.scavenge.raids["houses"] = [3]
	board.refresh(true)
	board.select_place("houses")
	var why: String = board.reason_for("loot")
	check(why.begins_with("Picked over. Ready again on day 6"), "'%s'" % why)
	check(board.buttons.loot.disabled and board.buttons.loot.tooltip_text == why, "the button is off and the tooltip says it")
	check(not board.buttons.scout.disabled, "but a place picked over can still be scouted")
	Kit.free_all(ctx)


func test_claim_garrison_and_recall_have_their_own_reasons() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	var town = ctx.sim.town
	board.select_place("depot")
	eq(board.reason_for("garrison"), "Only your own outpost can be held.", "not an outpost: Garrison")
	eq(board.reason_for("recall"), "Nobody is stationed there.", "and Recall")
	town.state["depot"].cleared = true
	ctx.sim.stock.scrap = 12.0
	board.refresh(true)
	eq(board.reason_for("claim"), "It takes 20 scrap and the stores have 12.", "cleared, but the scrap is short")
	check(board.buttons.claim.disabled and board.buttons.claim.tooltip_text == "It takes 20 scrap and the stores have 12.", "off, and the tooltip says it")
	ctx.sim.stock.scrap = 20.0
	board.refresh(true)
	eq(board.reason_for("claim"), "", "with the scrap it can be pressed")
	check(not board.buttons.claim.disabled and String(board.buttons.claim.tooltip_text).contains("20 scrap now"), "and says what it costs")
	town.state["depot"].claimed = true
	board.refresh(true)
	eq(board.reason_for("claim"), "It is already your outpost.", "once claimed")
	check(board.buttons.garrison.visible and board.buttons.recall.visible, "an outpost has Garrison and Recall")
	eq(board.reason_for("garrison"), "", "the party can stay")
	eq(board.reason_for("loot"), "It is your outpost: garrison it or leave it be.", "an outpost is not looted (the rules' words)")
	_at(ctx, 21.0)
	eq(board.reason_for("garrison"), "Nobody goes out after dark.", "not at night")
	_at(ctx, 7.0)
	town.set_garrison("depot", ["dez"])
	board.refresh(true)
	eq(board.reason_for("recall"), "", "with someone there, Recall can be pressed")
	Kit.free_all(ctx)


# ------------------------------------------------------------------------- sending --

func test_go_sends_the_party_to_loot_the_place_and_closes_the_page() -> void:
	var ctx := _open(1280, 800, 7.0, 2, "ruth")
	var board = _board(ctx)
	board.toggle_member(_person(ctx, "dez"))
	board.select_place("pharmacy")
	board.buttons.loot.pressed.emit()
	check(ctx.hud.scavenge_dialog == null, "the page closes")
	var parties: Array = ctx.sim.scavenge.parties
	eq(parties.size(), 1, "a party is out")
	eq([parties[0].site, parties[0].action, parties[0].members], ["pharmacy", "loot", ["ruth", "dez"]], "to the pharmacy to loot, Ruth leading, with Dez")
	near(float(parties[0].return_at) - float(ctx.sim.clock_min), ctx.sim.scavenge.action_hours("pharmacy", "loot") * 60.0, 1.0, "due back after the trip's hours")
	eq(ctx.speeds, [0, 2], "the speed comes back")
	check(ctx.hud.toast_panel.visible and ctx.hud.toast_label.text.begins_with("Ruth and Dez set off for The pharmacy."), "a toast says who went: '%s'" % ctx.hud.toast_label.text)
	check(ctx.hud.toast_label.text.contains("Back about"), "and when they will be back: '%s'" % ctx.hud.toast_label.text)
	Kit.free_all(ctx)


func test_scout_goes_for_a_shorter_trip_and_clear_for_a_longer_one() -> void:
	var results := {}
	for action in ["scout", "loot", "clear"]:
		var ctx := _open(1280, 800, 7.0, 1, "ruth")
		var board = _board(ctx)
		board.toggle_member(_person(ctx, "dez"))
		board.select_place("depot")
		board.act(action)
		var party: Dictionary = ctx.sim.scavenge.parties[0]
		eq([party.site, party.action], ["depot", action], "%s: the place and the action reach the rules" % action)
		results[action] = float(party.return_at) - float(ctx.sim.clock_min)
		Kit.free_all(ctx)
	check(results.scout < results.loot and results.loot < results.clear, "scouting is the shortest and clearing the longest: %s" % str(results))


func test_a_party_of_three_goes_and_a_refused_send_keeps_the_page_open_and_says_why() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	board.toggle_member(_person(ctx, "dez"))
	board.toggle_member(_person(ctx, "marcus"))
	board.select_place("houses")
	_at(ctx, 21.0)
	check(not board.act("loot"), "at night the send is refused")
	check(ctx.hud.town_board_open(), "the page stays")
	check(board.error_label.visible and board.error_label.text == "Nobody goes out after dark.", "and says why: '%s'" % board.error_label.text)
	eq(ctx.sim.scavenge.parties.size(), 0, "nobody went")
	_at(ctx, 7.0)
	check(board.act("loot"), "in the morning the three go")
	eq(ctx.sim.scavenge.parties[0].members, ["ruth", "dez", "marcus"], "all three")
	Kit.free_all(ctx)


func test_a_send_the_rules_refuse_after_the_page_agreed_is_told() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	board.select_place("houses")
	# somebody takes Ruth off the road between the page's last look and the press
	_person(ctx, "ruth").drafted = true
	_person(ctx, "ruth").order = {"x": 30.0, "y": 30.0}
	check(not board.act("loot"), "refused")
	check(ctx.hud.town_board_open() and board.error_label.visible, "the page stays and says something: '%s'" % board.error_label.text)
	Kit.free_all(ctx)


func test_claim_takes_the_scrap_and_the_page_says_so_and_stays() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	ctx.sim.town.state["depot"].cleared = true
	board.refresh(true)
	board.select_place("depot")
	var scrap_before: float = ctx.sim.stock.scrap
	board.buttons.claim.pressed.emit()
	eq(ctx.sim.town.state_of("depot"), "claimed", "the depot is an outpost")
	near(ctx.sim.stock.scrap, scrap_before - 20.0, 0.001, "for the scrap it costs")
	check(ctx.hud.town_board_open(), "the page stays")
	check(board.error_label.visible and board.error_label.text == "The bus depot is yours now.", "and says what was done: '%s'" % board.error_label.text)
	check(Kit.texts(board.tag_flow).has("YOUR OUTPOST") and board.buttons.garrison.visible and not board.buttons.claim.disabled == false, "the card and the buttons follow: Garrison is there, Claim is off")
	Kit.free_all(ctx)


func test_garrison_leaves_the_party_at_the_outpost_and_recall_brings_it_home() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	var town = ctx.sim.town
	town.state["depot"].cleared = true
	town.state["depot"].claimed = true
	board.refresh(true)
	board.select_place("depot")
	board.toggle_member(_person(ctx, "dez"))
	board.buttons.garrison.pressed.emit()
	eq(town.garrison_of("depot"), ["ruth", "dez"], "Ruth and Dez hold the depot")
	check(_person(ctx, "ruth").away is Dictionary and _person(ctx, "ruth").away.kind == "garrison", "they are off the map")
	check(ctx.hud.town_board_open(), "the page stays")
	check(board.error_label.text.begins_with("Ruth and Dez stay at The bus depot"), "and says so: '%s'" % board.error_label.text)
	eq(board.party, [_person(ctx, "marcus")], "the party is whoever is still free")
	check(not board.chips.has("ruth") and not board.chips.has("dez"), "those who stay are no longer offered")
	eq(board.facts.held.label.text, "Ruth and Dez", "the card says who holds it")
	check(Kit.texts(board.out_box).any(func(t): return String(t).contains("Ruth and Dez holding The bus depot")), "and the foot lists them: %s" % str(Kit.texts(board.out_box)))
	check(board.buttons.recall.visible and not board.buttons.recall.disabled, "Recall can be pressed")
	board.buttons.recall.pressed.emit()
	eq(town.garrison_of("depot"), [], "recalled: nobody holds it")
	check(_person(ctx, "ruth").away == null and _person(ctx, "dez").away == null, "they are back on the map")
	check(board.chips.has("ruth") and board.chips.has("dez"), "and offered again")
	check(board.error_label.text.contains("on the way home"), "'%s'" % board.error_label.text)
	Kit.free_all(ctx)


# ------------------------------------------------------------------ parties out --

func test_a_party_out_is_listed_at_the_foot_with_where_and_when() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	check(Kit.texts(board.out_box).has("Nobody is out."), "nobody out: it says so")
	check(ctx.sim.scavenge.send([_person(ctx, "ruth"), _person(ctx, "dez")], "pharmacy", "loot"), "(Ruth and Dez go to the pharmacy)")
	check(ctx.sim.scavenge.send([_person(ctx, "marcus")], "depot", "scout"), "(Marcus scouts the depot)")
	board.refresh(true)
	var all := Kit.texts(board.out_box)
	check(all.any(func(t): return String(t).begins_with("Ruth and Dez, looting The pharmacy: back about")), "the first party: %s" % str(all))
	check(all.any(func(t): return String(t).begins_with("Marcus, scouting The bus depot: back about")), "the second: %s" % str(all))
	check(not all.has("Nobody is out."), "and nobody-is-out is gone")
	eq(board.out_box.get_child_count(), 2, "a slip for each")
	Kit.free_all(ctx)


func test_the_foot_says_back_tomorrow_when_the_party_is_due_after_dusk_or_in_days() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	var sim = ctx.sim
	var now: float = sim.clock_min
	eq(board._due_text({"return_at": now + 3.0 * 60.0}), "back about 10:00", "three hours from seven: ten")
	eq(board._due_text({"return_at": now + 11.5 * 60.0}), "back about 18:30", "before dusk: that day")
	eq(board._due_text({"return_at": now + 12.5 * 60.0}), "back tomorrow", "after dusk: tomorrow (a party comes in by day)")
	eq(board._due_text({"return_at": now + 20.0 * 60.0}), "back tomorrow", "the small hours of tomorrow: in at first light, tomorrow")
	eq(board._due_text({"return_at": now + 30.0 * 60.0}), "back tomorrow", "tomorrow afternoon")
	eq(board._due_text({"return_at": now + 52.0 * 60.0}), "back in 2 days", "the day after tomorrow")
	eq(board._due_text({"return_at": now + 76.0 * 60.0}), "back in 3 days", "far off")
	eq(board._due_text({}), "", "nothing")
	# the small hours of today (a party out overnight, the game now at 02:00): in at first light, today
	sim.clock_min = 2.0 * 1440.0 + 2.0 * 60.0 - 420.0 + 1440.0
	eq(board._due_text({"return_at": sim.clock_min + 2.0 * 60.0}), "back about 06:30", "the small hours, today: first light")
	Kit.free_all(ctx)


func test_the_map_marks_a_party_on_its_road_by_how_much_of_the_trip_is_gone() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	var sim = ctx.sim
	check(sim.scavenge.send([_person(ctx, "ruth"), _person(ctx, "dez")], "pharmacy", "loot"), "(a party goes to the pharmacy)")
	var party: Dictionary = sim.scavenge.parties[0]
	var one_way: float = sim.town.hours_to("pharmacy")
	var trip: float = sim.scavenge.action_hours("pharmacy", "loot")
	# still at the gate: the marker is at the school
	board.refresh(true)
	var m: Dictionary = board.map.parties[0]
	eq([m.n, m.count, m.mode], [int(party.n), 2, "out"], "the marker: this party, two people, going out")
	near(float(m.at), 0.0, 1e-6, "at the school to begin with")
	eq(m.path[0], sim.town.home, "its route starts at the school")
	eq(m.path[m.path.size() - 1], Vector2(64, 27), "and ends at the pharmacy")
	eq(m.path.size(), 3, "by the houses (the road, not the crow)")
	# they are through the gate and some of the way
	party.state = "away"
	sim.clock_min = float(party.return_at) - (trip - 0.5 * one_way) * 60.0
	board.refresh(true)
	m = board.map.parties[0]
	near(float(m.at), 0.5, 0.02, "half way there")
	eq(m.mode, "out", "going")
	# searching
	sim.clock_min = float(party.return_at) - (trip - one_way - 0.5) * 60.0
	board.refresh(true)
	m = board.map.parties[0]
	eq([m.mode, float(m.at)], ["search", 1.0], "at the pharmacy, searching")
	# on the way back, a quarter of it gone
	sim.clock_min = float(party.return_at) - 0.75 * one_way * 60.0
	board.refresh(true)
	m = board.map.parties[0]
	eq(m.mode, "back", "coming back")
	near(float(m.at), 0.75, 0.02, "three quarters of the way home still to go")
	var pos: Vector2 = board.map.party_position(int(party.n))
	check(pos.x >= 0.0 and Rect2(Vector2.ZERO, board.map.size).has_point(pos), "and the marker is drawn on the map: %s" % str(pos))
	Kit.free_all(ctx)


func test_a_party_the_road_held_up_is_shown_by_the_hour_it_set_off_not_by_the_trips_length() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	var sim = ctx.sim
	board.select_place("pharmacy")
	board.act("loot")
	check(ctx.hud.scavenge_dialog == null, "(the party went and the page closed)")
	var party: Dictionary = sim.scavenge.parties[0]
	var set_off: float = sim.clock_min
	# the road held them up two hours (the rules add it to the hour they are due)
	party.return_at = float(party.return_at) + 120.0
	party.state = "away"
	ctx.hud.open_scavenge(null)
	board = _board(ctx)
	# the new page has not seen them go: it takes them to have set off a trip's length before they are due, a little late
	var trip: float = sim.scavenge.action_hours("pharmacy", "loot")
	var span := float(party.return_at) - set_off
	# a page that watched them go (and so knows the hour) shows them by the real span: halfway through the span is the middle
	# of the search, as the shares of the trip go
	board._departures[int(party.n)] = set_off
	sim.clock_min = set_off + span * 0.5
	board.refresh(true)
	var m: Dictionary = board.map.parties[0]
	var one_way: float = sim.town.hours_to("pharmacy")
	var there := one_way / trip
	var searched := (one_way + (trip - 2.0 * one_way)) / trip
	check(0.5 > there and 0.5 < searched, "(half way through is within the search: %.2f to %.2f)" % [there, searched])
	eq(m.mode, "search", "half way through the span they are searching")
	# a quarter of the span: still on the way there, at the share of it that a quarter is
	sim.clock_min = set_off + span * 0.2
	board.refresh(true)
	m = board.map.parties[0]
	eq(m.mode, "out", "at a fifth of the span they are still going out")
	near(float(m.at), 0.2 / there, 0.02, "by the span, not by the trip's own length")
	# a party that is seen still walking to the gate has only just been sent
	Kit.free_all(ctx)
	ctx = _open(1280, 800, 7.0, 1, "ruth")
	board = _board(ctx)
	board.close()
	ctx.sim.scavenge.send([_person(ctx, "dez")], "houses", "loot")
	ctx.sim.scavenge.parties[0].return_at = float(ctx.sim.scavenge.parties[0].return_at) + 180.0
	ctx.hud.open_scavenge(null)
	board = _board(ctx)
	check(board._departures.has(int(ctx.sim.scavenge.parties[0].n)) and absf(float(board._departures[int(ctx.sim.scavenge.parties[0].n)]) - float(ctx.sim.clock_min)) < 0.01, "first seen on its way to the gate: it set off just now (not a delay before it is due)")
	# and a party that has the hour in it (the rules may one day keep it) is shown by that
	var p2: Dictionary = ctx.sim.scavenge.parties[0]
	p2["depart"] = float(ctx.sim.clock_min) - 60.0
	board._departures.clear()
	board.refresh(true)
	eq(float(board._departures[int(p2.n)]), float(p2.depart), "the rules' own hour wins when there is one")
	Kit.free_all(ctx)


func test_the_route_follows_the_roads_and_a_place_without_a_road_is_a_straight_line() -> void:
	var ctx := _open()
	var board = _board(ctx)
	eq(board.route_to("clinic"), [Vector2(50, 35), Vector2(90, 60), Vector2(96, 66)], "home, the works, the clinic")
	eq(board.route_to("depot"), [Vector2(50, 35), Vector2(42, 26)], "a place on the first road")
	eq(board.route_to("farm"), [Vector2(50, 35), Vector2(42, 26), Vector2(34, 18)], "past the depot")
	ctx.sim.town.roads = []
	board._routes.clear()
	eq(board.route_to("houses"), [Vector2(50, 35), Vector2(58, 35)], "no road: straight")
	eq(board.route_to("nowhere"), [], "and no such place: no route")
	Kit.free_all(ctx)


# ----------------------------------------------------------------------- keyboard --

func test_tab_and_the_arrows_go_between_the_pins_and_enter_picks_one() -> void:
	var ctx := await _settled(1280, 800)
	var board = _board(ctx)
	check(_focus_owner() == null, "nothing has the keyboard to begin with")
	_press(KEY_TAB)
	await Kit.settle()
	var first := _focus_owner()
	check(first != null and first is Button and board.map.pins.values().has(first), "Tab puts the keyboard on a pin")
	eq(first.id, "houses", "the nearest place first")
	_press(KEY_RIGHT)
	await Kit.settle()
	var moved := _focus_owner()
	check(moved != null and moved != first and board.map.pins.values().has(moved), "an arrow goes to another pin: %s" % str(moved.get("id")))
	eq(board.map.focused, String(moved.id), "the map knows which has the keyboard")
	check(moved.get_meta("caption").visible, "and it has its name")
	# Enter picks it
	check(board.site_id == "", "(nothing is chosen)")
	_press(KEY_ENTER)
	await Kit.settle()
	eq(board.site_id, String(moved.id), "Enter picks the pin that has the keyboard")
	check(board.place_view.visible and board.name_label.text == String(ctx.sim.town.place(board.site_id).name), "and the card shows it")
	# Space does the same
	var other = null
	for pin in board.map.pins.values():
		if pin != moved:
			other = pin
	other.grab_focus()
	_press(KEY_SPACE)
	await Kit.settle()
	eq(board.site_id, String(other.id), "Space too")
	# Tab goes on to the next control: eventually off the pins
	var seen := {}
	for i in 14:
		_press(KEY_TAB)
		await Kit.settle()
		var f := _focus_owner()
		if f != null:
			seen[f.get_class() + ":" + String(f.get("id") if f.get("id") != null else f.get("text"))] = true
	check(seen.size() > 4, "Tab goes on past the pins to the other controls: %d stops" % seen.size())
	Kit.free_all(ctx)


func test_escape_and_g_close_the_page_and_the_other_keys_are_not_the_games() -> void:
	for how in ["esc", "g", "button"]:
		var ctx := await _settled(1280, 800)
		var seen: Array = []
		ctx.hud.on_gizmo = func(id): seen.append(id)
		match how:
			"esc":
				_press(KEY_ESCAPE)
			"g":
				_press(KEY_G)
			"button":
				_board(ctx).close_button.pressed.emit()
		await Kit.settle()
		check(ctx.hud.scavenge_dialog == null, "%s: it closes" % how)
		eq(ctx.speeds, [0, 1], "%s: and the speed is back" % how)
		Kit.free_all(ctx)
	var ctx2 := await _settled(1280, 800)
	var board = _board(ctx2)
	for code in [KEY_R, KEY_P, KEY_F, KEY_J, KEY_N, KEY_V, KEY_1, KEY_X]:
		var ev := _key(code)
		board._input(ev)
		check(ctx2.hud.town_board_open(), "key %s does not close it" % OS.get_keycode_string(code))
	check(ctx2.pressed == [], "and no order was pressed behind it")
	# a key held down shuts one thing, not the page and then what is under it
	var held := _key(KEY_ESCAPE)
	held.echo = true
	board._input(held)
	check(ctx2.hud.town_board_open(), "an echo of Esc does not close it")
	Kit.free_all(ctx2)


## A click on a button, through the engine's own routing of the mouse when the button is the control under the pointer
## (it is, in a run of this file by itself); when something else covers the window (a game scene that an earlier failing
## test of another file left in the tree, with its pages in layers over this one), the press is handed to the button.
## True when the engine did it.
func _click_button(c: Button) -> bool:
	var root: Window = Engine.get_main_loop().root
	var at: Vector2 = c.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	var under = root.gui_get_hovered_control()
	if under != null and (under == c or c.is_ancestor_of(under)):
		Kit.click(at)
		return true
	c.pressed.emit()
	return false


func test_a_click_on_a_pin_chooses_it_and_a_click_on_the_veil_does_nothing() -> void:
	var ctx := _open(1280, 800)
	await Kit.settle()
	await Kit.settle()
	var board = _board(ctx)
	var pin: Button = board.map.pins["houses"]
	check(pin.mouse_filter != Control.MOUSE_FILTER_IGNORE and pin.focus_mode == Control.FOCUS_ALL and pin.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "a pin takes the mouse and the keyboard, and shows a hand")
	_click_button(pin)
	eq(board.site_id, "houses", "a click on a pin chooses the place")
	_click_button(board.chips.dez.chip)
	check(board.party.size() == 2 and board.party.has(_person(ctx, "dez")), "a click on a person's chip brings them along")
	_click_button(board.chips.dez.chip)
	check(board.party.size() == 1, "and a second takes them out again")
	# the veil over the game stops the mouse, so a click on it is not a click on the yard, and the page does not take it
	var veil = board.get_child(0)
	check(veil is ColorRect and veil.mouse_filter == Control.MOUSE_FILTER_STOP, "the veil stops the mouse")
	eq(board.mouse_filter, Control.MOUSE_FILTER_STOP, "and so does the page")
	var before: String = board.site_id
	Kit.click(Vector2(3, 3))
	check(ctx.hud.town_board_open() and board.site_id == before, "a click on the veil changes nothing")
	Kit.free_all(ctx)


# ------------------------------------------------------------------------- layout --

## Whatever does not fit or overlaps, as sentences (nothing when the page is as it should be).
func _misfits(ctx: Dictionary, size: Array) -> Array:
	var bad: Array = []
	var board = _board(ctx)
	if board == null:
		return ["the page is not open"]
	var window := Rect2(0, 0, size[0], size[1])
	var panel := Kit.rect(board.panel)
	if not window.grow(1.0).encloses(panel):
		bad.append("the page %s is not inside the window %s" % [str(panel), str(window)])
	var blocks := {"head": Kit.rect(board._head), "scroll": Kit.rect(board.scroll), "foot": Kit.rect(board._foot)}
	for name in blocks:
		if blocks[name].size == Vector2.ZERO or not panel.grow(0.5).encloses(blocks[name]):
			bad.append("the %s %s is not in the page %s" % [name, str(blocks[name]), str(panel)])
	bad.append_array(Kit.overlaps(blocks))
	# the two columns of the body, side by side or one over the other
	var columns := {"map": Kit.rect(board.map_col), "card": Kit.rect(board.detail_col)}
	bad.append_array(Kit.overlaps(columns))
	for name in columns:
		if columns[name].size == Vector2.ZERO:
			bad.append("the %s column has no size" % name)
	if board.body.vertical == false:
		if columns.card.position.x < columns.map.end.x - 0.5:
			bad.append("beside the map the card begins at %.0f and the map ends at %.0f" % [columns.card.position.x, columns.map.end.x])
	# the map: the pins inside it, apart from one another, and the names
	var map_rect := Kit.rect(board.map)
	var centres := {}
	for id in board.map.pins:
		var pin: Control = board.map.pins[id]
		var r := Kit.rect(pin)
		if not map_rect.grow(0.5).encloses(r):
			bad.append("the pin of %s %s is not on the map %s" % [id, str(r), str(map_rect)])
		centres[id] = r.get_center()
	for a in centres:
		for b in centres:
			if String(a) < String(b) and Vector2(centres[a]).distance_to(centres[b]) < TownMap.PIN_R * 2.0:
				bad.append("the pins of %s and %s overlap (%.0f px apart)" % [a, b, Vector2(centres[a]).distance_to(centres[b])])
	for id in board.map.captions():
		var label: Label = board.map.home_marker.get_meta("caption") if id == "home" else board.map.pins[id].get_meta("caption")
		if not map_rect.grow(0.5).encloses(Kit.rect(label)):
			bad.append("the name of %s is not on the map" % id)
	# the map keeps the board's shape
	check(absf(map_rect.size.y / map_rect.size.x - 0.7) < 0.01, "(the map is 100 by 70: %s)" % str(map_rect.size))
	# the card: everything in it is inside it
	var card := Kit.rect(board.card)
	var col := Kit.rect(board.detail_col)
	if card.size != Vector2.ZERO and (card.position.x < col.position.x - 0.5 or card.end.x > col.end.x + 0.5):
		bad.append("the card %s is not inside its column %s" % [str(card), str(col)])
	for c in board.card.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree():
			continue
		var r := Kit.rect(c)
		if r.size == Vector2.ZERO:
			continue
		if r.position.x < card.position.x - 0.5 or r.end.x > card.end.x + 0.5:
			bad.append("a %s '%s' %s is outside the card %s" % [c.get_class(), str(c.get("text")).left(24), str(r), str(card)])
	# the chips are inside the column and do not overlap
	var parts := {}
	for id in board.chips:
		parts["chip " + id] = Kit.rect(board.chips[id].chip)
	bad.append_array(Kit.overlaps(parts))
	for name in parts:
		if parts[name].size != Vector2.ZERO and (parts[name].position.x < col.position.x - 0.5 or parts[name].end.x > col.end.x + 0.5):
			bad.append("%s %s is not inside the column %s" % [name, str(parts[name]), str(col)])
	# the buttons and the lines under them: in the foot (which never scrolls), under the card when it is beside the map; the
	# parties out under the map, or at the end of the body
	var foot := Kit.rect(board._foot)
	var block := Kit.rect(board.actions_block)
	if block.size == Vector2.ZERO or not foot.grow(0.5).encloses(block):
		bad.append("the buttons %s are not in the foot %s" % [str(block), str(foot)])
	if board.body.vertical == false and (block.position.x < col.position.x - 1.0 or block.end.x > col.end.x + float(TownBoard.GUTTER) + 1.0):
		bad.append("the buttons %s are not under the card %s" % [str(block), str(col)])
	if board.body.vertical == false:
		bad.append_array(Kit.overlaps({"parties out and keys": Kit.rect(board.foot_left), "buttons": Kit.rect(board.foot_right)}))
	var buttons := {}
	for action in board.buttons:
		if board.buttons[action].visible:
			buttons["button " + action] = Kit.rect(board.buttons[action])
	bad.append_array(Kit.overlaps(buttons))
	for name in buttons:
		if buttons[name].size == Vector2.ZERO or not block.grow(0.5).encloses(buttons[name]):
			bad.append("%s %s is not in the buttons' block %s" % [name, str(buttons[name]), str(block)])
	var close := Kit.rect(board.close_button)
	if close.size == Vector2.ZERO or not panel.encloses(close) or not foot.grow(0.5).encloses(close):
		bad.append("Close %s is not in the foot %s" % [str(close), str(foot)])
	bad.append_array(Kit.overlaps({"buttons": block, "close": close, "hint": Kit.rect(board.hint_label)}))
	for l in board.why_lines:
		var r := Kit.rect(l)
		if r.size != Vector2.ZERO and not block.grow(0.5).encloses(r):
			bad.append("a line of reasons %s is not in the buttons' block %s" % [str(r), str(block)])
	var out := Kit.rect(board.out_section)
	for c in board.out_box.get_children():
		var r := Kit.rect(c)
		if not out.grow(0.5).encloses(r):
			bad.append("a slip %s is not in the parties' section %s" % [str(r), str(out)])
	if board.body.vertical == false and not foot.grow(0.5).encloses(out):
		bad.append("the parties' section %s is not in the foot %s" % [str(out), str(foot)])
	# every word is whole: a line that does not wrap has the room for all of its letters, and a line that wraps has room
	# for a few words and a line
	for l in board.find_children("*", "Label", true, false):
		if String(l.text) == "" or not l.is_visible_in_tree():
			continue
		var box := Kit.rect(l)
		var font: Font = l.get_theme_font("font")
		var px: int = l.get_theme_font_size("font_size")
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var want: float = font.get_string_size(String(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			if box.size.x < want - 1.0:
				bad.append("'%s' has %.0f px of the %.0f it needs" % [String(l.text).left(30), box.size.x, want])
		elif box.size.x < 60.0 or box.size.y < float(px):
			bad.append("the wrapped '%s' is squeezed to %s" % [String(l.text).left(30), str(box.size)])
	return bad


## The page with a place chosen, a claimed outpost with a garrison, a party out, a nest and someone hiding: as full as
## it gets.
func _stage(ctx: Dictionary) -> void:
	var sim = ctx.sim
	sim.town.reveal("farm")
	sim.town.state["houses"].cleared = true
	sim.town.state["chapel"].cleared = true
	sim.town.state["chapel"].claimed = true
	sim.scavenge.send([_person(ctx, "marcus")], "pharmacy", "loot")
	_board(ctx).refresh(true)


func test_the_page_fits_and_overlaps_nothing_at_700_980_1280_and_1920() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _settled(size[0], size[1])
		_stage(ctx)
		for view in ["depot", "houses", "pharmacy", "farm", ""]:
			if view == "":
				_board(ctx).site_id = ""
				_board(ctx).refresh(true)
			else:
				_board(ctx).select_place(view)
			await Kit.settle()
			await Kit.settle()
			eq(_misfits(ctx, size), [], "%d x %d, %s" % [size[0], size[1], view if view != "" else "nothing chosen"])
		Kit.free_all(ctx)


func test_the_page_fits_a_short_window_and_the_body_scrolls() -> void:
	for size in SHORT:
		var ctx: Dictionary = await _settled(size[0], size[1])
		_stage(ctx)
		_board(ctx).select_place("depot")
		await Kit.settle()
		await Kit.settle()
		eq(_misfits(ctx, size), [], "%d x %d" % [size[0], size[1]])
		var board = _board(ctx)
		check(board.body.get_combined_minimum_size().y > board.scroll.size.y, "%d x %d: too short for everything, so the body scrolls (%.0f in %.0f)" % [size[0], size[1], board.body.get_combined_minimum_size().y, board.scroll.size.y])
		# the buttons are in the foot, which never scrolls: they are in the window whatever the body is doing
		var window := Rect2(0, 0, size[0], size[1])
		check(window.encloses(Kit.rect(board.buttons.loot)) and window.encloses(Kit.rect(board.close_button)), "%d x %d: Go and Close are in the window: %s, %s" % [size[0], size[1], str(Kit.rect(board.buttons.loot)), str(Kit.rect(board.close_button))])
		# scrolled to the end, the last of the party is in view
		board.scroll.scroll_vertical = int(board.scroll.get_v_scroll_bar().max_value)
		await Kit.settle()
		var view := Kit.rect(board.scroll)
		var last: Rect2 = Kit.rect(board.party_box)
		check(view.grow(1.0).encloses(last.grow(-0.5)), "%d x %d: the party is in view at the end of the scroll: %s in %s" % [size[0], size[1], str(last), str(view)])
		Kit.free_all(ctx)


func test_a_window_that_changes_size_lays_the_page_out_again() -> void:
	var ctx: Dictionary = await _settled(1280, 800)
	var board = _board(ctx)
	check(not board.body.vertical, "wide: the card is beside the map")
	var wide := Kit.rect(board.map).size.x
	Kit.resize(ctx, 700, 700)
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()
	check(board.body.vertical, "narrow: the card is under the map")
	eq(_misfits(ctx, [700, 700]), [], "shrunk to 700")
	check(Kit.rect(board.map).size.x < wide, "the map is smaller: %.0f against %.0f" % [Kit.rect(board.map).size.x, wide])
	Kit.resize(ctx, 1280, 800)
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()
	eq(_misfits(ctx, [1280, 800]), [], "grown back")
	Kit.free_all(ctx)


func test_choosing_a_pin_in_a_narrow_window_brings_the_card_into_view() -> void:
	var ctx: Dictionary = await _settled(700, 700)
	var board = _board(ctx)
	_stage(ctx)
	await Kit.settle()
	board.map.pins["depot"].pressed.emit()
	await Kit.settle()
	await Kit.settle()
	var view := Kit.rect(board.scroll)
	var name_box := Kit.rect(board.name_label)
	check(view.grow(1.0).intersects(name_box) and name_box.position.y >= view.position.y - 1.0, "the card's name is in view after the pin is chosen: %s in %s" % [str(name_box), str(view)])
	Kit.free_all(ctx)


func test_nothing_on_the_page_is_under_twelve_pixels_at_any_size() -> void:
	var tt := TextTests.new()
	for size in [[1920, 1080], [1280, 800], [980, 700], [700, 700], [700, 560]]:
		var ctx: Dictionary = await _settled(size[0], size[1])
		_stage(ctx)
		for view in ["depot", "farm", "houses"]:
			_board(ctx).select_place(view)
			await Kit.settle()
			eq(tt._small_text(_board(ctx)), [], "%d x %d, %s" % [size[0], size[1], view])
		# with the line at the foot
		_board(ctx).act("claim")
		eq(tt._small_text(_board(ctx)), [], "%d x %d, with the line at the foot" % [size[0], size[1]])
		Kit.free_all(ctx)
	check(TownMap.CAPTION_PX >= Fonts.MIN_PX, "the names on the map are drawn at %d px" % TownMap.CAPTION_PX)


func test_every_word_on_the_page_reads_on_the_paper_in_either_look() -> void:
	var tt := TextTests.new()
	for frames in [true, false]:
		Hud.use_frames = frames
		var look := "frames" if frames else "flat"
		for size in [[1920, 1080], [1280, 800], [700, 700]]:
			var ctx: Dictionary = await _settled(size[0], size[1])
			_stage(ctx)
			await Kit.settle()
			_park_the_mouse()
			for view in ["depot", "farm", "chapel", "pharmacy"]:
				_board(ctx).select_place(view)
				await Kit.settle()
				eq(tt._hard_to_read(_board(ctx), Color.WHITE), [], "%s, %d: %s" % [look, size[0], view])
				var bad: Array = []
				for b in _board(ctx).find_children("*", "Button", true, false):
					if String(b.text) == "" or not b.is_visible_in_tree():
						continue
					var state := "disabled" if b.disabled else "normal"
					var ink: Color = b.get_theme_color("font_disabled_color" if b.disabled else "font_color")
					var behind: Array = tt._backdrops(b, Color.WHITE)
					var fills: Array = Kit.fills(b.get_theme_stylebox(state))
					for i in 2:
						var bg: Color = tt.over(fills[i], behind[i])
						var ratio: float = tt.contrast(tt.over(ink, bg), bg)
						if ratio < tt.AA:
							bad.append("'%s' (%s) is %.2f:1" % [b.text, state, ratio])
							break
				eq(bad, [], "%s, %d: the buttons of %s" % [look, size[0], view])
				eq(tt._dark_red_words(_board(ctx)), [], "%s, %d: no word in the dark red (%s)" % [look, size[0], view])
			Kit.free_all(ctx)
	Hud.use_frames = true


func test_the_marks_on_the_map_are_dark_enough_on_the_sheet() -> void:
	var tt := TextTests.new()
	var sheet := TownMap.SHEET
	# the faint question mark is a mark, not words: 3 to 1
	var unknown := tt.over(TownMap.UNKNOWN_INK, sheet)
	check(tt.contrast(unknown, sheet) >= 3.0, "the '?' reads at %.2f:1 on the sheet" % tt.contrast(unknown, sheet))
	# the number in a nest's disc and the count on a party's disc are words: white on the red and the blue
	check(tt.contrast(Color("#ffffff"), TownMap.RED) >= tt.AA, "white on the nest's red: %.2f:1" % tt.contrast(Color("#ffffff"), TownMap.RED))
	check(tt.contrast(Color("#ffffff"), TownMap.BLUE) >= tt.AA, "white on a party's blue: %.2f:1" % tt.contrast(Color("#ffffff"), TownMap.BLUE))
	# a name on its small paper
	var ink := Color("#26241c")
	check(tt.contrast(ink, Color("#efe9d6")) >= tt.AA, "the names are dark ink on paper")


# --------------------------------------------------------------- the glyph of a kind --

func test_every_kind_of_place_in_the_real_town_has_a_picture_of_its_own() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/town.json"))
	var kinds := {}
	for p in raw.places:
		kinds[String(p.kind)] = true
	for kind in kinds:
		check(TownMap.glyph_of(kind) != "generic", "'%s' has an icon of its own: %s" % [kind, TownMap.glyph_of(kind)])
	eq(TownMap.glyph_of("something new"), "generic", "a kind the map has not heard of gets a plain mark")
	eq(TownMap.glyph_of("Fire_Station"), "flame", "the match does not care about case")


func test_the_real_town_opens_with_a_pin_for_every_place_it_shows() -> void:
	var g := Helpers.make(7, 1, 3)
	var sim = g.sim
	var ctx := {"g": g, "sim": sim, "pressed": [], "speeds": [], "selected": []}
	var holder := Control.new()
	holder.size = Vector2(1280, 800)
	Engine.get_main_loop().root.add_child(holder)
	var hud := Hud.new()
	holder.add_child(hud)
	hud.on_speed = func(s): ctx.speeds.append(s)
	hud.on_select = func(_s): pass
	hud.on_focus = func(_p): pass
	hud.on_gizmo = func(_id): pass
	hud.on_alert = func(_id): pass
	hud.on_sound = func(): pass
	hud.setup(g.data, sim.people)
	ctx["holder"] = holder
	ctx["hud"] = hud
	Kit.update(ctx)
	hud.open_scavenge(null)
	var board = _board(ctx)
	check(board != null, "it opens on the real town")
	var known := 0
	for e in sim.town.all_places():
		if e.state != "unknown":
			known += 1
	eq(board.map.pins.size(), known, "a pin for each place the town shows")
	eq(board.map.unknown.size(), sim.town.places.size() - known, "and a question mark for each other one")
	check(known >= 3 and board.map.unknown.size() >= 10, "(a few are known at the start, most are not: %d known, %d not)" % [known, board.map.unknown.size()])
	await Kit.settle()
	await Kit.settle()
	for id in board.map.pins:
		board.select_place(id)
	check(board.place_view.visible, "every place can be chosen")
	# late in the game: every place is known, some cleared and claimed, someone holds one; at every size nothing overlaps
	var n := 0
	for id in sim.town.state:
		sim.town.state[id].known = true
		if n % 3 == 0 and sim.town.place(id).has("outpost"):
			sim.town.state[id].cleared = true
			sim.town.state[id].claimed = true
		n += 1
	board.refresh(true)
	eq(board.map.pins.size(), sim.town.places.size(), "every place has its pin")
	eq(board.map.unknown.size(), 0, "and no question marks are left")
	for size in SIZES:
		Kit.resize(ctx, size[0], size[1])
		await Kit.settle()
		await Kit.settle()
		await Kit.settle()
		_park_the_mouse()
		await Kit.settle()
		for id in (sim.town.state.keys() if size[0] >= 1280 else ["police", "bunker", ""]) + [""]:
			if id == "":
				board.site_id = ""
				board.refresh(true)
			else:
				board.select_place(id)
			await Kit.settle()
			eq(_misfits(ctx, size), [], "the real town, every place known, %d x %d, %s" % [size[0], size[1], id if id != "" else "nothing chosen"])
	Kit.free_all(ctx)


# ---------------------------------------------------------------------- random play --

func test_random_play_on_the_page_never_breaks_it() -> void:
	for seed_value in [1, 2, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var ctx: Dictionary = await _settled(1280, 800)
		var board = _board(ctx)
		var ids: Array = ["houses", "pharmacy", "depot", "chapel", "farm", "works", "clinic", "nowhere"]
		var people: Array = []
		for p in ctx.sim.people:
			people.append(p)
		for step in 60:
			match rng.randi() % 9:
				0, 1:
					board.select_place(ids[rng.randi() % ids.size()])
				2, 3:
					board.toggle_member(people[rng.randi() % people.size()])
				4:
					board.act(["scout", "clear", "claim", "garrison", "recall"][rng.randi() % 5])
				5:
					# the world moves on under the page
					var town = ctx.sim.town
					var id: String = ids[rng.randi() % (ids.size() - 1)]
					town.state[id].known = true
					if rng.randf() < 0.3:
						town.state[id].cleared = true
					if rng.randf() < 0.2:
						town.state[id].claimed = town.state[id].cleared
				6:
					_at(ctx, [5.0, 7.0, 9.0, 11.0, 21.0][rng.randi() % 5])
				7:
					var p = people[rng.randi() % people.size()]
					p.drafted = rng.randf() < 0.5
					p.order = {"x": 30.0, "y": 30.0} if p.drafted else null
				8:
					Kit.update(ctx)
			board.refresh()
			if rng.randf() < 0.3:
				await Kit.settle()
			if not ctx.hud.town_board_open():
				break
		check(true, "seed %d: it did not break" % seed_value)
		Kit.free_all(ctx)


# ------------------------------------------------------------- the real game scene --
# (main.gd: the key G, the toolbar's bag, the person's Scavenge button, the tutorial's lock, the hint)

const Tut := preload("res://tests/tutorial_kit.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Hints := preload("res://scripts/ui/hints.gd")
const Prefs := preload("res://scripts/prefs.gd")


## A settlement game on the real scene (the real town), its HUD brought up.
func _scene(width: int = 1280, height: int = 800, crew: int = 3) -> Node:
	return Tut.start({"difficulty": 1, "seed": 7, "crew": crew}, width, height)


func _toast(main) -> String:
	return main.hud.toast_label.text if main.hud.toast_panel.visible else ""


## What main.gd asks of the tutorial's coach: the gate, and what the player did.
class FakeCoach:
	extends Node
	var open := false
	var asked: Array = []
	var did: Array = []

	func allows(kind: String, arg = null) -> bool:
		asked.append([kind, arg])
		return open

	func would_allow(_kind: String, _arg = null) -> bool:
		return open

	func on_did(kind: String, arg = null) -> void:
		did.append([kind, arg])


func test_g_opens_the_board_in_a_settlement_game_and_the_old_dialog_in_the_classic_start() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	check(main.sim.town.on, "(a settlement game)")
	check(main.hud.scavenge_dialog == null and not main.menu_open, "shut at the start")
	main._key(KEY_G)
	check(main.hud.town_board_open(), "G opens the Town Board")
	eq(main.speed, 0, "the rules wait while it is open")
	check(main.menu_open, "it has the keys: the camera's are not heard")
	await Tut.leave(main)
	var classic = _scene(1280, 800, 6)
	await Tut.frames(classic, 3)
	check(not classic.sim.town.on, "(the classic start)")
	classic._key(KEY_G)
	check(classic.hud.scavenge_dialog != null and classic.hud.scavenge_dialog.get_script() == Dialog and not classic.hud.town_board_open(), "G opens the old dialog there")
	await Tut.leave(classic)


func test_g_esc_the_button_and_the_toolbar_give_the_speed_back() -> void:
	for how in ["g", "esc", "close", "toolbar", "toggle"]:
		var main = _scene()
		main.speed = 2
		await Tut.frames(main, 3)
		main._key(KEY_G)
		check(main.hud.town_board_open() and main.speed == 0, "%s: open and paused" % how)
		var board = main.hud.scavenge_dialog
		match how:
			"g":
				# with the page up G reaches the page itself (the game's own handler is not asked)
				board._input(_key(KEY_G))
			"esc":
				board._input(_key(KEY_ESCAPE))
			"close":
				board.close_button.pressed.emit()
			"toolbar":
				main.hud.town_button.pressed.emit()
			"toggle":
				main.toggle_town()
		check(main.hud.scavenge_dialog == null, "%s: shut" % how)
		eq(main.speed, 2, "%s: and the speed is back" % how)
		check(not main.menu_open, "%s: and the keys are the game's again" % how)
		await Tut.leave(main)


func test_the_toolbars_bag_opens_the_board_too() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	check(main.hud.town_button.visible, "the button is there")
	main.hud.town_button.pressed.emit()
	check(main.hud.town_board_open(), "the bag in the toolbar opens it")
	await Tut.leave(main)


func test_the_person_panels_scavenge_button_opens_the_board_with_them_leading() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	var dez = null
	for p in main.sim.people:
		if p.id == "dez":
			dez = p
	main._select({"kind": "person", "ref": dez})
	main.sim.minutes = 7.0 * 60.0
	await Tut.frames(main, 2)
	main._gizmo("scavenge")
	check(main.hud.town_board_open(), "the order opens the board")
	eq(main.hud.scavenge_dialog.party, [dez], "with Dez leading")
	await Tut.leave(main)


func test_g_is_not_there_over_a_menu_another_page_or_the_title() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	main.open_pause()
	main._key(KEY_G)
	check(main.hud.scavenge_dialog == null, "not over the pause menu")
	main.toggle_town()
	check(main.hud.scavenge_dialog == null, "nor from the toolbar")
	main.shell.close_all()
	main.resume()
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	main.hud.add_child(page)
	main._key(KEY_G)
	check(main.hud.scavenge_dialog == null, "nor over a page that covers the game")
	page.free()
	main.toggle_jobs()
	check(main.hud.jobs_screen != null, "(the Jobs screen is open)")
	main.toggle_town()
	check(main.hud.scavenge_dialog == null, "nor over the Jobs screen")
	main.hud.close_jobs()
	main.title_mode = true
	main.toggle_town()
	check(main.hud.scavenge_dialog == null, "nor on the title")
	main.title_mode = false
	main._key(KEY_G)
	check(main.hud.town_board_open(), "but it opens once nothing is in the way")
	main.toggle_jobs()
	check(main.hud.jobs_screen == null, "and the Jobs screen does not open over it")
	main.toggle_build()
	check(main.hud.build_screen == null, "nor the Build screen")
	await Tut.leave(main)


func test_the_tutorials_lock_may_refuse_the_board() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	var coach := FakeCoach.new()
	main.coach = coach
	main._key(KEY_G)
	check(not main.hud.town_board_open(), "the lock refuses it")
	eq(coach.asked, [["gizmo", "scavenge"]], "having asked the gate about the order")
	main.hud.town_button.pressed.emit()
	check(not main.hud.town_board_open() and coach.asked.size() == 2, "the toolbar's button asks the same gate")
	coach.open = true
	main._key(KEY_G)
	check(main.hud.town_board_open(), "an open gate lets it through")
	check(coach.did.has(["gizmo", "scavenge"]), "and the coach is told the player did it: %s" % str(coach.did))
	main.hud.scavenge_dialog.close()
	main.coach = null
	coach.free()
	await Tut.leave(main)


func test_the_hint_comes_once_in_a_settlement_game_and_points_at_the_bag() -> void:
	var tip := {}
	for h in Hints.load_hints():
		if String(h.id) == "town":
			tip = h
	check(not tip.is_empty(), "there is a tip for the Town Board")
	eq(tip.get("anchor", []), ["town"], "it points at the toolbar's bag")
	eq(tip.get("start", {}).get("cond", ""), "town_on", "and comes when a game has a board")
	check(String(tip.text).contains("night out") and String(tip.text).contains("Scout") and String(tip.text).contains("nest"), "and says the three things: %s" % tip.get("text", ""))
	var list := Hints.load_hints()
	var ids: Array = []
	for h in list:
		ids.append(String(h.id))
	check(ids[ids.size() - 1] == "build" and ids.find("town") >= 0 and ids.find("town") < ids.size() - 1, "it comes before the build tip (which stays last) so that it never hides a warning: %s" % str(ids))
	# the condition: a settlement game, not the classic start
	var classic := Helpers.make(5, 1)
	check(not Conditions.check(tip.start, classic.sim, {}), "the classic start has no board: no tip")
	classic.world.free()
	var settlement := _game()
	check(Conditions.check(tip.start, settlement.sim, {}), "a settlement game has: the tip")
	settlement.world.free()
	# on the real scene, with the tips armed
	var main = _scene()
	await Tut.frames(main, 3)
	main.hints.armed = true
	main.sim.t = 60.0
	await Tut.frames(main, 40)
	eq(main.hints.shown_id(), "town", "the tip is up")
	check(Prefs.flag("hint_town"), "and is marked as shown the moment it was")
	check(main.hints.target_rect.size.x > 0.0 and main.hints.target_rect == main.hud.anchor_rect("town"), "with the toolbar's bag lit: %s" % str(main.hints.target_rect))
	var card: Rect2 = main.hints.card.get_global_rect()
	check(Rect2(Vector2.ZERO, main._vp()).grow(1.0).encloses(card) and not card.intersects(main.hints.target_rect), "inside the window and off what it lights")
	main.hints.ok_button.pressed.emit()
	await Tut.frames(main, 4)
	await Tut.frames(main, 40 + 45 * 30)
	eq(main.hints.shown_id(), "", "once is all")
	await Tut.leave(main)


func test_the_help_says_what_g_does_in_each_start() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	eq(main.hud.help_g.text, "Town Board", "a settlement game: the Town Board")
	var all := Kit.texts(main.hud.help)
	check(all.has("G") and all.has("Town Board"), "listed with its key")
	await Tut.leave(main)
	var classic = _scene(1280, 800, 6)
	await Tut.frames(classic, 3)
	eq(classic.hud.help_g.text, "Scavenge", "the classic start: Scavenge")
	await Tut.leave(classic)


func test_the_toolbar_with_the_bag_still_leaves_room_for_the_orders() -> void:
	# a full row of order buttons must still sit beside the selection panel in a 1280 window, with the bag in the toolbar
	var main = _scene()
	await Tut.frames(main, 3)
	var ruth = main.sim.people[0]
	main._select({"kind": "person", "ref": ruth})
	await Tut.frames(main, 6)
	var speed_rect: Rect2 = main.hud.anchor_rect("speed")
	check(speed_rect.size.x > 0.0, "(the toolbar is there)")
	var inspect: Rect2 = main.hud.anchor_rect("inspect")
	var overlap := speed_rect.intersection(inspect)
	check(overlap.size.x < 1.0 or overlap.size.y < 1.0, "the toolbar %s and the person's panel %s do not overlap" % [str(speed_rect), str(inspect)])
	for b in main.hud.gizmos.get_children():
		if b is Button and b.visible:
			var r: Rect2 = b.get_global_rect()
			var hit := r.intersection(speed_rect)
			check(hit.size.x < 1.0 or hit.size.y < 1.0, "the order '%s' %s is clear of the toolbar %s" % [b.get_meta("id", ""), str(r), str(speed_rect)])
	check(Rect2(Vector2.ZERO, main._vp()).grow(1.0).encloses(speed_rect), "and the toolbar is inside the window")
	await Tut.leave(main)


func test_the_foot_follows_the_seasons_dusk() -> void:
	var ctx := _open(1280, 800, 7.0, 1, "ruth")
	var board = _board(ctx)
	var sim = ctx.sim
	var now: float = sim.clock_min
	eq(board._due_text({"return_at": now + 10.5 * 60.0}), "back about 17:30", "Autumn: half past five is before dusk")
	sim.seasons.campaign = true
	sim.seasons._dusk = 16.5
	eq(board._due_text({"return_at": now + 10.5 * 60.0}), "back tomorrow", "Winter: dusk is at half past four, a party due then is in at first light")
	sim.seasons._dusk = 21.0
	eq(board._due_text({"return_at": now + 13.0 * 60.0}), "back about 20:00", "Summer: eight in the evening is before dusk")
	Kit.free_all(ctx)
