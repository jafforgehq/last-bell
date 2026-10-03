extends "res://tests/case.gd"
## Round 18, the Map page of the radio panel (scripts/ui/map_page.gd, its data scripts/ui/map_data.gd, the Town Board's map widget
## town_map.gd with its one new option): the Town Board in the panel's compact, non-modal form. The map on top, the card of the place
## that is chosen, the people as chips (who to ask: "willing", or the radio's own refusal in amber), the vehicles that are parked, and two
## ways to go: Take control (the player plays the trip, through the HUD's `on_raid`, as the Town Board does) and Ask <names> to go (an
## ERRAND, through `radio.request_errand`, with what it costs written out); Claim and Recall; the parties out; Full page.
##
## The page stands in a panel of its own here (the radio panel's shell is another builder's): a PanelContainer 440 or 316 wide over the
## real HUD and a real settlement game on a small town of its own (FIX), so that what the page says can be checked exactly. The sim's
## contracts it asks (`radio.errand_willingness`, `request_errand`, `errand_wait`, `scavenge.why_not_errand`) are the ERRANDS builder's, the
## real ones: nothing is faked.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const TownBoard := preload("res://scripts/ui/town_board.gd")
const TownMap := preload("res://scripts/ui/town_map.gd")
const MapPage := preload("res://scripts/ui/map_page.gd")
const MapData := preload("res://scripts/ui/map_data.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const NightKit := preload("res://scripts/ui/night_kit.gd")
const TextTests := preload("res://tests/test_hud_text.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

const FIXTURE := "user://test_r18_map_town.json"
## The panel's two widths, and five sizes (width, height) the page is fuzzed at.
const WIDTHS := [440, 316]
const FUZZ := [[440, 760], [440, 480], [316, 700], [316, 420], [380, 560]]

## Home is at (50, 35). Known at the start: the houses, the pharmacy, the depot (a nest of 2, someone hiding, an outpost to claim) and the
## chapel (quiet: nothing to clear). Not known: the farm (needs a vehicle), the water works, the clinic.
const FIX := {
	"board": {"w": 100, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "Neighbourhood houses", "kind": "houses", "pos": [58, 35], "blurb": "Somebody's pantry is somebody's pantry.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {"meds": [0.3, 1]}},
		{"id": "pharmacy", "name": "The pharmacy", "kind": "pharmacy", "pos": [64, 27], "blurb": "Shelves stripped, but the back room was locked.", "danger": 2, "known": true,
			"loot": {"meds": [6, 11]}, "extra": {}},
		{"id": "depot", "name": "The bus depot", "kind": "bus_depot", "pos": [42, 26], "blurb": "Buses, nose to tail.", "danger": 2, "known": true,
			"loot": {"scrap": [10, 20]}, "extra": {}, "nest": {"strength": 2}, "survivor": true, "outpost": {"yield": {"scrap": 3}, "cost": 20}},
		{"id": "chapel", "name": "St. Aidan's chapel", "kind": "church", "pos": [50, 20], "blurb": "Quiet. Too quiet, or just a chapel.", "danger": 0, "known": true,
			"loot": {"food": [2, 4]}, "extra": {}},
		{"id": "farm", "name": "Hollis farm", "kind": "farm", "pos": [34, 18], "blurb": "A long way out.", "danger": 1, "needs_vehicle": true,
			"loot": {"food": [10, 18]}, "extra": {}, "outpost": {"yield": {"food": 4, "water": 2}, "cost": 30}},
		{"id": "works", "name": "The water works", "kind": "water_works", "pos": [90, 60], "blurb": "Very far.", "danger": 1,
			"loot": {"water": [20, 30]}, "extra": {}},
		{"id": "clinic", "name": "Eastgate clinic", "kind": "clinic", "pos": [96, 66], "blurb": "Beyond the works.", "danger": 2,
			"loot": {"meds": [5, 9]}, "extra": {}},
	],
	"roads": [["home", "houses"], ["houses", "pharmacy"], ["home", "depot"], ["depot", "farm"], ["home", "works"], ["works", "clinic"], ["home", "chapel"]],
	"beats": [],
}


# --------------------------------------------------------------------- helpers --

func _write(data: Dictionary) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _park_the_mouse() -> void:
	var root: Window = Engine.get_main_loop().root
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(1, 1)
	ev.global_position = Vector2(1, 1)
	root.push_input(ev, true)


## A settlement game on the little town, at `hour` of day 3, plenty of everything, a quiet world, Ruth the player and five people at the base.
func _game(hour: float = 7.0, seed_value: int = 13, real_town: bool = false) -> Dictionary:
	_write(FIX)
	Town.data_path = Town.DATA_PATH if real_town else FIXTURE
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
	for i in 2:
		sim.add_person(sim.recruits.queue.pop_front())
	sim.avatar.set_player("ruth")
	return g


## {"g", "sim", "holder", "hud", "panel", "page"}: the HUD over that game and the page in a panel `width` by `height`, set up and settled.
func _ctx(width: int = 440, height: int = 760, hour: float = 7.0, real_town: bool = false) -> Dictionary:
	_park_the_mouse()
	var g := _game(hour, 13, real_town)
	var sim = g.sim
	var ctx := {"g": g, "sim": sim, "toasts": [], "raids": [], "sounds": []}
	var holder := Control.new()
	holder.size = Vector2(1280, 900)
	Engine.get_main_loop().root.add_child(holder)
	var hud := Hud.new()
	holder.add_child(hud)
	hud.on_select = func(_s): pass
	hud.on_focus = func(_p): pass
	hud.on_speed = func(_s): pass
	hud.on_gizmo = func(_id): pass
	hud.on_alert = func(_id): pass
	hud.on_sound = func(): pass
	hud.setup(g.data, sim.people)
	ctx["holder"] = holder
	ctx["hud"] = hud
	hud.on_raid = func(people, place, vehicle, penalty, done):
		ctx.raids.append({"people": people, "place": place, "vehicle": vehicle, "penalty": penalty, "done": done})
		return ctx.get("scene", Node.new())
	Kit.update(ctx, 1)
	# the radio panel's shell, as it holds a page: a panel, its tabs' row, and a scroll (no sideways scroll) that has the page in it
	var panel: PanelContainer = hud._panel(hud._style(Hud.PANEL, 6, Hud.LINE, true, "panel"))
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(width, height)
	panel.size = Vector2(width, height)
	holder.add_child(panel)
	var col: VBoxContainer = hud._vbox(6)
	panel.add_child(col)
	col.add_child(hud._caps("Jobs   Build   Map   News"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	col.add_child(scroll)
	var page := MapPage.new()
	scroll.add_child(page)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.setup(hud, func(): return sim, {"panel": panel})
	ctx["scroll"] = scroll
	ctx["panel"] = panel
	ctx["page"] = page
	return ctx


func _settled(width: int = 440, height: int = 760, hour: float = 7.0, real_town: bool = false) -> Dictionary:
	var ctx := _ctx(width, height, hour, real_town)
	await Kit.settle()
	await Kit.settle()
	ctx.page.refresh(true)
	await Kit.settle()
	_park_the_mouse()
	return ctx


func _free(ctx: Dictionary) -> void:
	Kit.free_all(ctx)


func _person(ctx: Dictionary, id: String):
	return Kit.person(ctx, id)


## The clock moved to `hour` of today.
func _at(ctx: Dictionary, hour: float) -> void:
	var sim = ctx.sim
	sim.minutes = hour * 60.0
	sim.clock_min = 2.0 * 1440.0 + hour * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	ctx.page.refresh(true)


## All the words in a part of the page that is showing.
func _words(node: Node, out: Array = []) -> Array:
	if node is Control and not node.visible:
		return out
	if node is Label and node.text != "":
		out.append(String(node.text))
	if node is Button and String(node.text) != "":
		out.append(String(node.text))
	for c in node.get_children():
		_words(c, out)
	return out


func _says(ctx: Dictionary, part: String) -> bool:
	for w in _words(ctx.page):
		if String(w).contains(part):
			return true
	return false


func _chip(ctx: Dictionary, id: String) -> Button:
	return ctx.page.chips[id].chip


## The status line under a person's name.
func _status(ctx: Dictionary, id: String) -> String:
	return String(ctx.page.chips[id].status.text)


func _free_people(ctx: Dictionary) -> Array:
	var out: Array = []
	for p in ctx.sim.people:
		if String(p.id) != "ruth":
			out.append(p)
	return out


# ----------------------------------------------------------------- the data --

func test_the_map_data_is_the_town_boards_own_picture() -> void:
	var ctx := await _settled()
	var sim = ctx.sim
	var data := MapData.build(sim, "depot")
	# the Town Board over the same game
	ctx.hud.open_scavenge(null)
	await Kit.settle()
	var board = ctx.hud.scavenge_dialog
	check(board != null and board.get_script() == TownBoard, "the Town Board is open")
	board.select_place("depot")
	var m = board.map
	eq(data.board, m.board, "the board")
	eq(data.home, m.home, "the school")
	eq(data.places.size(), m.places.size(), "the known places")
	for i in data.places.size():
		eq(String(data.places[i].id), String(m.places[i].id), "place %d" % i)
		eq(String(data.places[i].state), String(m.places[i].state), "state of %d" % i)
		eq(bool(data.places[i].survivor), bool(m.places[i].survivor), "someone hiding at %d" % i)
	eq(data.roads, m.roads, "the roads, solid and stub")
	eq(data.unknown, m.unknown, "the question marks")
	eq(data.streets, m.streets, "the streets")
	eq(String(data.chosen), "depot", "the chosen place")
	for id in ["houses", "pharmacy", "depot", "chapel", "farm", "works", "clinic"]:
		eq(MapData.route_to(sim, id), board.route_to(id), "the route to %s" % id)
	board.close()
	_free(ctx)


func test_the_parties_out_are_marked_as_the_board_marks_them() -> void:
	var ctx := await _settled()
	var sim = ctx.sim
	check(sim.scavenge.send([_person(ctx, "dez"), _person(ctx, "ana")], "houses", "loot"), "a party goes")
	sim.clock_min += 40.0
	var departures := {}
	var mine := MapData.party_markers(sim, departures)
	ctx.hud.open_scavenge(null)
	await Kit.settle()
	var board = ctx.hud.scavenge_dialog
	var theirs: Array = board._party_markers()
	eq(mine.size(), 1, "one party on the map")
	eq(mine.size(), theirs.size(), "as many as the board's")
	if mine.size() == 1 and theirs.size() == 1:
		eq(int(mine[0].n), int(theirs[0].n), "the party's number")
		eq(int(mine[0].count), 2, "two people")
		eq(mine[0].path, theirs[0].path, "the same route")
		near(float(mine[0].at), float(theirs[0].at), 1e-6, "how far along")
		eq(String(mine[0].mode), String(theirs[0].mode), "which way")
	eq(departures.size(), 1, "the departure is remembered in the dictionary the page keeps")
	board.close()
	_free(ctx)


func test_the_unknown_places_stay_unknown_until_a_scout_shows_them() -> void:
	var ctx := await _settled()
	var data := MapData.build(ctx.sim, "")
	var ids: Array = []
	for p in data.places:
		ids.append(String(p.id))
	ids.sort()
	eq(ids, ["chapel", "depot", "houses", "pharmacy"], "only the places that are known")
	eq(data.unknown.size(), 3, "a faint '?' for each other place")
	ctx.sim.town.reveal("works")
	var again := MapData.build(ctx.sim, "")
	eq(again.places.size(), 5, "the water works is on the map once it is known")
	eq(again.unknown.size(), 2, "and no longer a '?'")
	_free(ctx)


# ----------------------------------------------------------------- the map --

func test_the_map_has_a_pin_for_each_known_place_and_none_takes_focus() -> void:
	var ctx := await _settled()
	var page = ctx.page
	eq(page.map.pins.size(), 4, "four known places, four pins")
	for id in ["houses", "pharmacy", "depot", "chapel"]:
		check(page.map.pins.has(id), "a pin for %s" % id)
	for id in page.map.pins:
		eq(page.map.pins[id].focus_mode, Control.FOCUS_NONE, "the pin of %s takes no focus (WASD and E keep working)" % id)
	eq(page.map.unknown.size(), 3, "and a '?' for each of the others")
	# a place that becomes known later gets its pin, and it takes no focus either
	ctx.sim.town.reveal("works")
	page.refresh()
	eq(page.map.pins.size(), 5, "the water works has its pin")
	eq(page.map.pins["works"].focus_mode, Control.FOCUS_NONE, "and it takes no focus")
	_free(ctx)


func test_the_town_boards_pins_still_take_focus() -> void:
	# the new option of town_map.gd is optional: a map that does not ask is as it was
	var ctx := await _settled()
	ctx.hud.open_scavenge(null)
	await Kit.settle()
	var board = ctx.hud.scavenge_dialog
	for id in board.map.pins:
		eq(board.map.pins[id].focus_mode, Control.FOCUS_ALL, "the board's pin of %s" % id)
	board.close()
	_free(ctx)


func test_clicking_a_pin_chooses_the_place_and_rings_it() -> void:
	var ctx := await _settled()
	var page = ctx.page
	eq(page.chosen(), "", "nothing is chosen at first")
	page.map.pins["depot"].pressed.emit()
	eq(page.chosen(), "depot", "the pin chose the depot")
	eq(page.map.chosen, "depot", "and the map rings it")
	check(not page.select_place("farm"), "a place nobody knows cannot be chosen")
	eq(page.chosen(), "depot", "and the choice stays")
	page.focus_on("houses")
	eq(page.chosen(), "houses", "focus_on chooses a place (what another page's link does)")
	page.focus_on("nowhere")
	eq(page.chosen(), "houses", "an unknown id is ignored")
	_free(ctx)


func test_a_place_that_is_chosen_and_then_not_there_is_let_go() -> void:
	var ctx := await _settled()
	var page = ctx.page
	page.select_place("houses")
	ctx.sim.town.state["houses"].known = false
	page.refresh(true)
	eq(page.chosen(), "", "the page does not hold a place the map does not show")
	_free(ctx)


# ----------------------------------------------------------------- the card --

func test_choosing_a_place_fills_the_card() -> void:
	var ctx := await _settled()
	var page = ctx.page
	check(page.empty_label.visible and not page.place_view.visible, "before a choice the card says what to do")
	page.select_place("houses")
	check(not page.empty_label.visible and page.place_view.visible, "the card shows the place")
	eq(String(page.name_label.text), "Neighbourhood houses", "the name")
	eq(String(page.kind_label.text), "HOUSES", "and the kind, in capitals")
	eq(String(page.facts.danger.label.text), MapData.DANGER_WORDS[1], "the danger in words")
	check(String(page.facts.trip.label.text).contains("On foot: about"), "the trip on foot: '%s'" % page.facts.trip.label.text)
	check(String(page.facts.trip.label.text).contains("Back about"), "and when they would be back: '%s'" % page.facts.trip.label.text)
	check(String(page.facts.loot.label.text) != "", "what it is likely to give, in the rules' words")
	var chip_words := _words(page.loot_chips)
	check(chip_words.has("8–14") and chip_words.has("10–20") and chip_words.has("sometimes"), "the loot chips: %s" % str(chip_words))
	eq(String(page.name_label.tooltip_text), "Somebody's pantry is somebody's pantry.", "the blurb is the name's tooltip")
	page.select_place("depot")
	eq(String(page.kind_label.text), "BUS DEPOT", "an underscore is a space")
	_free(ctx)


func test_the_card_tells_of_the_nest_the_one_hiding_and_the_outpost() -> void:
	var ctx := await _settled()
	var page = ctx.page
	page.select_place("depot")
	var tags := _words(page.tag_flow)
	check(tags.has("NEST 2"), "a nest tag: %s" % str(tags))
	check(tags.has("SOMEONE HIDING"), "someone hiding: %s" % str(tags))
	check(String(page.facts.nest.label.text).begins_with("Strength 2."), "the nest's strength: '%s'" % page.facts.nest.label.text)
	check(String(page.facts.nest.label.text).contains("The nights lean to the"), "and where the nights lean: '%s'" % page.facts.nest.label.text)
	check(String(page.facts.outpost.label.text).begins_with("Once cleared: 3 scrap a day, for 20 scrap."), "the outpost to be: '%s'" % page.facts.outpost.label.text)
	page.select_place("chapel")
	check(not page.facts.nest.value.visible and not page.facts.outpost.value.visible, "a quiet chapel has none of them")
	check(not _words(page.tag_flow).has("SOMEONE HIDING"), "nor anyone hiding")
	eq(String(page.facts.danger.label.text), MapData.DANGER_WORDS[0], "and is quiet")
	# cleared and claimed
	ctx.sim.town.mark_cleared("depot")
	page.select_place("depot")
	check(_words(page.tag_flow).has("CLEARED"), "a cleared tag")
	check(String(page.facts.outpost.label.text).begins_with("Can be claimed: 3 scrap a day, for 20 scrap."), "the outpost can be claimed: '%s'" % page.facts.outpost.label.text)
	check(not _words(page.tag_flow).has("NEST 2"), "the nest tag is gone with the nest")
	check(String(page.facts.nest.label.text).begins_with("Gone"), "the nest line says it is gone")
	_free(ctx)


func test_a_place_picked_over_says_until_when() -> void:
	var ctx := await _settled()
	var page = ctx.page
	ctx.sim.scavenge._record_raid("houses")
	page.select_place("houses")
	var note := String(page.facts.note.label.text)
	check(note.begins_with("Picked over. Ready again on day"), "the rules' own note: '%s'" % note)
	var day := MapData.picked_over_until(note)
	check(day > 0, "a day is read from it")
	check(_words(page.tag_flow).has("PICKED OVER UNTIL DAY %d" % day), "and a tag says it: %s" % str(_words(page.tag_flow)))
	_free(ctx)


func test_the_trip_says_the_hours_by_the_vehicle_and_a_night_out() -> void:
	var ctx := await _settled()
	var page = ctx.page
	ctx.sim.vehicles.fleet.append({"id": "rig", "kind": "pickup", "hp": 80.0, "state": "parked"})
	ctx.sim.vehicles.fuel = 30.0
	page.refresh(true)
	page.select_place("houses")
	var on_foot := String(page.facts.trip.label.text)
	check(not on_foot.contains("By the pickup"), "on foot, nothing of the pickup: '%s'" % on_foot)
	check(page.choose_vehicle("rig"), "the pickup is chosen")
	var text := String(page.facts.trip.label.text)
	check(text.contains("On foot: about") and text.contains("By the pickup: about") and text.contains("fuel"), "both ways in one card: '%s'" % text)
	var hours: float = ctx.sim.scavenge.action_hours("houses", "loot", "rig")
	check(text.contains(TownMap.hours_text(hours)), "the pickup's hours are the rules': '%s' for %.2f" % [text, hours])
	# a place only a vehicle reaches
	ctx.sim.town.reveal("farm")
	page.refresh(true)
	page.choose_vehicle("")
	page.select_place("farm")
	check(String(page.facts.trip.label.text).begins_with("On foot: too far to walk"), "the farm: '%s'" % page.facts.trip.label.text)
	check(_words(page.tag_flow).has("BY VEHICLE ONLY"), "with its tag")
	_at(ctx, 9.5)
	page.select_place("houses")
	_at(ctx, 9.9)
	check(String(page.facts.trip.label.text).contains("Back "), "the hour is told")
	_free(ctx)


# --------------------------------------------------------------------- the people --

func test_everyone_at_the_base_but_the_player_has_a_chip_that_says_willing() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var ids: Array = []
	for p in _free_people(ctx):
		ids.append(String(p.id))
	ids.sort()
	var have: Array = page.chips.keys()
	have.sort()
	eq(have, ids, "a chip for each person but Ruth, who plays")
	for id in ids:
		eq(_status(ctx, id), "willing", "%s is willing" % id)
		check(not _chip(ctx, id).disabled, "%s's chip can be pressed" % id)
		eq(_chip(ctx, id).focus_mode, Control.FOCUS_NONE, "and takes no focus")
	check(page.chips["dez"].pic.texture != null, "Dez has a face")
	check(_says(ctx, "Dez") and _says(ctx, "Marcus") and _says(ctx, "Ana") and _says(ctx, "Walt"), "the first names are on the chips")
	_free(ctx)


func test_a_person_who_cannot_go_says_why_in_the_radios_own_words() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var radio = ctx.sim.radio
	var ana = _person(ctx, "ana")
	var dez = _person(ctx, "dez")
	ana.bleeding = 3.0
	dez.downed = true
	page.refresh()
	var soft: Dictionary = radio.reason_not(ana, "go")
	var hard: Dictionary = radio.reason_not(dez, "go")
	check(not bool(soft.ok) and not bool(soft.hard), "Ana is a soft refusal: %s" % str(soft))
	check(not bool(hard.ok) and bool(hard.hard), "Dez is a hard one: %s" % str(hard))
	check(String(soft.why).begins_with("Ana: "), "Ana: '%s'" % soft.why)
	check(String(_chip(ctx, "ana").tooltip_text).contains(String(soft.why)), "the whole refusal is Ana's tooltip: '%s'" % _chip(ctx, "ana").tooltip_text)
	check(String(soft.why).ends_with(_status(ctx, "ana")), "the word under the name is the end of it: '%s' of '%s'" % [_status(ctx, "ana"), soft.why])
	check(not _chip(ctx, "ana").disabled, "a soft refusal can still be asked (and pushed)")
	check(_chip(ctx, "dez").disabled, "a hard one cannot")
	eq(String(_chip(ctx, "dez").tooltip_text), String(hard.why), "and the tooltip is the reason, in the radio's words")
	check(String(hard.why).ends_with(_status(ctx, "dez")) or _status(ctx, "dez") != "", "Dez has a word under his name: '%s'" % _status(ctx, "dez"))
	# the page's amber is the soft one's
	eq(page.chips["ana"].status.get_theme_color("font_color"), ctx.hud.WARN, "a refusal is amber")
	eq(page.chips["marcus"].status.get_theme_color("font_color"), ctx.hud.OK, "willing is green")
	_free(ctx)


func test_the_chips_follow_the_game_while_the_page_is_open() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var chip_before: Button = _chip(ctx, "marcus")
	var pin_before = page.map.pins["houses"]
	for i in 5:
		page.refresh()
	check(_chip(ctx, "marcus") == chip_before, "a refresh keeps the chips it has")
	check(page.map.pins["houses"] == pin_before, "and the pins")
	_person(ctx, "marcus").bleeding = 2.0
	page.refresh()
	check(_status(ctx, "marcus") != "willing", "Marcus starts bleeding: the chip says so at once")
	_person(ctx, "marcus").bleeding = 0.0
	page.refresh()
	eq(_status(ctx, "marcus"), "willing", "and says willing again when he is better")
	# a new arrival is a new chip
	ctx.sim.add_person(ctx.sim.recruits.queue.pop_front())
	page.refresh()
	eq(page.chips.size(), 5, "a fifth person has a chip")
	_free(ctx)


func test_ticking_a_person_brings_or_asks_them_and_unticking_lets_them_go() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var dez = _person(ctx, "dez")
	check(page.toggle_person(dez), "Dez is ticked")
	eq(page.ticks, ["dez"], "in the list")
	check(page.chips["dez"].tick.visible, "with a tick on his chip")
	check(page.toggle_person(_person(ctx, "ana")), "Ana too")
	eq(page.ticks, ["dez", "ana"], "in the order they were ticked")
	check(page.toggle_person(dez), "Dez is unticked")
	eq(page.ticks, ["ana"], "and Ana stays")
	check(not page.chips["dez"].tick.visible, "the tick is gone")
	check(not page.toggle_person(_person(ctx, "ruth")), "the player is not a choice")
	_chip(ctx, "ana").pressed.emit()
	eq(page.ticks, [], "a press on the chip does the same")
	_free(ctx)


func test_three_is_the_most_on_foot_and_the_seats_in_a_vehicle() -> void:
	var ctx := await _settled()
	var page = ctx.page
	for id in ["dez", "marcus", "ana"]:
		check(page.toggle_person(_person(ctx, id)), "%s is ticked" % id)
	check(not page.toggle_person(_person(ctx, "walt")), "a fourth cannot be")
	eq(page.ticks.size(), 3, "three are ticked")
	check(page.feedback_label.visible and String(page.feedback_label.text) == "Three is the most on foot.", "the page says so: '%s'" % page.feedback_label.text)
	# a vehicle that seats two lets the last of them go
	ctx.sim.vehicles.fleet.append({"id": "rig", "kind": "sedan", "hp": 80.0, "state": "parked"})
	ctx.sim.vehicles.fuel = 30.0
	page.refresh(true)
	var seats := int(ctx.sim.vehicles.kind_of("rig").get("seats", 0))
	check(page.choose_vehicle("rig"), "the sedan is chosen")
	eq(page.ticks.size(), mini(3, seats), "the party never holds more than the %d seats" % seats)
	eq(page.party_limit(), seats, "the limit is the seats")
	_free(ctx)


func test_a_person_who_goes_down_while_ticked_is_let_go() -> void:
	var ctx := await _settled()
	var page = ctx.page
	page.toggle_person(_person(ctx, "dez"))
	page.toggle_person(_person(ctx, "ana"))
	_person(ctx, "dez").downed = true
	page.refresh()
	eq(page.ticks, ["ana"], "Dez cannot go now: his tick is let go")
	check(not page.toggle_person(_person(ctx, "dez")), "and he cannot be ticked")
	check(page.feedback_label.visible and String(page.feedback_label.text).contains("Dez"), "the page says why: '%s'" % page.feedback_label.text)
	_free(ctx)


# ------------------------------------------------------------------ the vehicles --

func test_a_parked_vehicle_has_a_chip_with_its_fuel_and_hours_and_on_foot_is_the_other() -> void:
	var ctx := await _settled()
	var page = ctx.page
	check(not page.ride_box.visible, "no vehicle, no row")
	ctx.sim.vehicles.fleet.append({"id": "rig", "kind": "pickup", "hp": 80.0, "state": "parked"})
	ctx.sim.vehicles.fuel = 30.0
	page.refresh()
	check(page.ride_box.visible, "a parked pickup: the row is there")
	eq(page.ride_chips.keys().size(), 2, "On foot and the pickup")
	page.select_place("houses")
	var need: float = ctx.sim.vehicles.fuel_for("houses", "rig")
	var words := _words(page.ride_chips["rig"].chip)
	var joined := " | ".join(words)
	check(joined.contains("Pickup") and joined.contains("fuel %s" % MapData.num(need)), "the pickup's chip: %s" % joined)
	check(joined.contains(TownMap.hours_text(ctx.sim.scavenge.action_hours("houses", "loot", "rig"))), "with its hours: %s" % joined)
	check(not page.choose_vehicle("nope"), "a vehicle that is not there cannot be chosen")
	check(page.feedback_label.visible, "and the page says so")
	check(page.choose_vehicle("rig"), "the pickup")
	eq(page.vehicle_id, "rig", "is chosen")
	check(String(page.ride_chips["rig"].chip.tooltip_text).contains("Going this way."), "its tooltip says so")
	check(page.choose_vehicle(""), "and on foot again")
	eq(page.vehicle_id, "", "walking")
	# the vehicle goes out: the row loses it, and a choice of it is let go
	page.choose_vehicle("rig")
	ctx.sim.vehicles.fleet[0].state = "out"
	page.refresh()
	eq(page.vehicle_id, "", "a vehicle that left is not the way any more")
	check(not page.ride_box.visible, "and the row is gone")
	_free(ctx)


# ----------------------------------------------------------------- the reasons --

func test_the_reasons_for_take_control_are_the_rules() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	eq(page.reason_for("go"), "Pick a place on the map first.", "nothing chosen")
	page.select_place("houses")
	eq(page.reason_for("go"), "", "a place, the day, Ruth: she may go alone")
	check(not page.buttons.go.disabled, "the button is on")
	_at(ctx, 21.0)
	var who: Array = page.picked().going
	var rules: String = sim.scavenge.why_not_played(who, "houses", "loot", "")
	check(rules != "", "the rules refuse after dark: '%s'" % rules)
	eq(page.reason_for("go"), rules, "and the page says it in their words")
	check(page.buttons.go.disabled and String(page.buttons.go.tooltip_text) == rules, "the button is off and its tooltip is the reason")
	check(page.go_note.visible and String(page.go_note.text) == rules, "and the line under it")
	_at(ctx, 7.0)
	ctx.hud.on_raid = Callable()
	page.refresh(true)
	eq(page.reason_for("go"), "Not in this game.", "no way to open a raid: the board's own words")
	check(page.buttons.go.disabled and String(page.buttons.go.tooltip_text) != "", "off, with a tooltip")
	_free(ctx)


func test_the_reasons_for_the_errand_are_the_radios() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	eq(page.reason_for("errand"), "Pick a place on the map first.", "nothing chosen")
	page.select_place("houses")
	check(page.reason_for("errand") != "", "nobody ticked: it says what to do: '%s'" % page.reason_for("errand"))
	check(page.buttons.errand.disabled and String(page.buttons.errand.tooltip_text) == page.reason_for("errand"), "the button is off and says it")
	page.toggle_person(_person(ctx, "dez"))
	eq(page.reason_for("errand"), "", "Dez is ticked: the errand can be asked")
	check(not page.buttons.errand.disabled, "the button is on")
	eq(String(page.buttons.errand.text), "Ask Dez to go", "and names him")
	page.toggle_person(_person(ctx, "ana"))
	eq(String(page.buttons.errand.text), "Ask Dez and Ana to go", "two names")
	page.toggle_person(_person(ctx, "marcus"))
	eq(String(page.buttons.errand.text), "Ask Dez, Ana and Marcus to go", "three")
	_at(ctx, 21.0)
	var w: Dictionary = sim.radio.errand_willingness(page.ticked_people(), "houses", "loot", "")
	check(not bool(w.ok), "after dark nobody goes: '%s'" % w.why)
	eq(page.reason_for("errand"), String(w.why), "the page's reason is the radio's")
	check(page.buttons.errand.disabled and String(page.buttons.errand.tooltip_text).begins_with(String(w.why)), "on the button's tooltip")
	_free(ctx)


func test_the_card_of_an_errand_names_its_terms() -> void:
	var ctx := await _settled()
	var page = ctx.page
	page.select_place("houses")
	page.toggle_person(_person(ctx, "dez"))
	var w: Dictionary = ctx.sim.radio.errand_willingness([_person(ctx, "dez")], "houses", "loot", "")
	check(String(w.get("loot_note", "")) != "", "the radio has a note on what an errand costs: %s" % str(w.keys()))
	check(page.terms_note.visible and String(page.terms_note.text) == String(w.loot_note), "the page shows it as it is: '%s'" % page.terms_note.text)
	check(String(page.terms_note.text).contains("60%"), "about 60% of the loot")
	_free(ctx)


func test_loot_scout_and_clear_are_a_switch_for_the_errand() -> void:
	var ctx := await _settled()
	var page = ctx.page
	page.select_place("houses")
	eq(page.errand_action, "loot", "loot is what a place with loot starts at")
	check(page.set_errand_action("scout"), "scout")
	eq(page.errand_action, "scout", "is chosen")
	check(not page.set_errand_action("garrison"), "nothing else is an errand")
	eq(page.errand_action, "scout", "and the choice stays")
	page.set_errand_action("clear")
	eq(page.errand_action, "clear", "clear")
	for a in ["loot", "scout", "clear"]:
		check(String(page.segments[a].tooltip_text) != "", "%s says what it is" % a)
		eq(page.segments[a].focus_mode, Control.FOCUS_NONE, "and takes no focus")
	# choosing another place starts from what makes sense there
	page.select_place("chapel")
	eq(page.errand_action, "loot", "a new place: loot again")
	# Take control does not follow the switch: it plays what there is to play
	page.set_errand_action("scout")
	eq(page.played_action(), "loot", "Take control plays loot where there is some")
	_free(ctx)


func test_an_errand_to_clear_a_nest_says_it_takes_two() -> void:
	var ctx := await _settled()
	var page = ctx.page
	page.select_place("depot")
	page.set_errand_action("clear")
	page.toggle_person(_person(ctx, "dez"))
	var rules: String = ctx.sim.scavenge.why_not_action([_person(ctx, "dez")], "depot", "clear", "")
	eq(rules, "A nest takes at least two.", "the rules")
	eq(page.reason_for("errand"), rules, "the page says the same")
	page.toggle_person(_person(ctx, "ana"))
	eq(page.reason_for("errand"), "", "two can")
	_free(ctx)


# ------------------------------------------------------------------- Take control --

func test_take_control_opens_the_raid_exactly_as_the_town_board_does() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	# a place that was raided three days ago: open again, with less in it
	sim.scavenge.raids["houses"] = [int(sim.day) - 3]
	page.refresh(true)
	page.select_place("houses")
	page.toggle_person(_person(ctx, "dez"))
	var res: Dictionary = page.act("go")
	check(bool(res.ok), "taking control works: %s" % str(res))
	eq(ctx.raids.size(), 1, "the raid was asked for once")
	var mine: Dictionary = ctx.raids[0]
	eq(mine.people.size(), 1, "with Dez (the player goes and leads: the colony adds her)")
	eq(String(mine.people[0].id), "dez", "Dez")
	eq(String(mine.place.id), "houses", "at the houses")
	eq(mine.vehicle, "", "on foot")
	near(float(mine.penalty), 0.75, 1e-9, "a raided place's loot is multiplied by what the rules say")
	near(float(mine.penalty), sim.scavenge.raid_penalty("houses"), 1e-9, "(the rules' own number)")
	check(mine.done.is_valid(), "and a callback that does nothing is given")
	eq(sim.scavenge.parties.size(), 0, "the colony's party is made by the raid, not by the page")
	eq(page.ticks, [], "the people ticked have gone: no ticks left")
	# the same through the Town Board
	ctx.hud.open_scavenge(null)
	await Kit.settle()
	var board = ctx.hud.scavenge_dialog
	board.select_place("houses")
	if not _person(ctx, "dez") in board.party:
		board.toggle_member(_person(ctx, "dez"))
	for p in board.party.duplicate():
		if String(p.id) != "dez":
			board.toggle_member(p)
	check(board.act("play"), "the board's Take control")
	eq(ctx.raids.size(), 2, "the board asked too")
	var theirs: Dictionary = ctx.raids[1]
	eq(theirs.place, mine.place, "the same place dictionary")
	eq(theirs.vehicle, mine.vehicle, "the same vehicle")
	near(float(theirs.penalty), float(mine.penalty), 1e-9, "the same penalty")
	_free(ctx)


func test_take_control_by_vehicle_and_of_a_cleared_place() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	sim.vehicles.fleet.append({"id": "rig", "kind": "pickup", "hp": 80.0, "state": "parked"})
	sim.vehicles.fuel = 30.0
	sim.town.mark_cleared("depot")
	page.refresh(true)
	page.select_place("depot")
	page.choose_vehicle("rig")
	check(bool(page.act("go").ok), "by the pickup to a cleared place")
	var raid: Dictionary = ctx.raids[0]
	eq(raid.vehicle, "rig", "in the pickup")
	check(bool(raid.place.get("cleared", false)), "a cleared place is told as one (the dice zero its danger)")
	_free(ctx)


func test_take_control_that_the_raid_cannot_open_says_so_and_keeps_the_page() -> void:
	var ctx := await _settled()
	var page = ctx.page
	ctx.hud.on_raid = func(_p, _pl, _v, _m, _d): return null
	page.select_place("houses")
	page.toggle_person(_person(ctx, "dez"))
	var res: Dictionary = page.act("go")
	check(not bool(res.ok), "the raid did not open")
	check(page.feedback_label.visible and String(page.feedback_label.text) != "", "the page says so: '%s'" % page.feedback_label.text)
	eq(page.ticks, ["dez"], "Dez is still ticked: nothing happened")
	eq(ctx.sim.scavenge.parties.size(), 0, "nobody went")
	_free(ctx)


func test_take_control_refused_by_the_rules_does_nothing() -> void:
	var ctx := await _settled()
	var page = ctx.page
	page.select_place("houses")
	_at(ctx, 21.0)
	var res: Dictionary = page.act("go")
	check(not bool(res.ok), "after dark")
	eq(String(res.why), "Nobody goes out after dark.", "the rules' words")
	eq(ctx.raids.size(), 0, "no raid")
	_free(ctx)


func test_who_would_stay_behind_is_told_under_take_control() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var ana = _person(ctx, "ana")
	ana.bleeding = 3.0
	page.refresh()
	page.select_place("houses")
	page.toggle_person(ana)
	page.toggle_person(_person(ctx, "dez"))
	var picked: Dictionary = page.picked()
	eq((picked.refused as Array).size(), 1, "the colony will leave Ana out")
	check(page.stay_note.visible, "the page says who stays")
	var why := String(picked.refused[0].why)
	check(String(page.stay_note.text).contains(why.trim_suffix(".")), "in the colony's own words: '%s' for '%s'" % [page.stay_note.text, why])
	check(String(page.stay_note.text).contains("stays behind"), "and that she stays")
	var going: Array = []
	for p in picked.going:
		going.append(String(p.id))
	eq(going, ["ruth", "dez"], "Ruth and Dez go")
	_free(ctx)


# ----------------------------------------------------------------- tonight (round 19) --

## The clock at `hour` of `day` (the page refreshed): the settlement game's own clock, as `_at` has it for day 3.
func _on_day(ctx: Dictionary, day: int, hour: float) -> void:
	var sim = ctx.sim
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + hour * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.supplies.sources_day = day
	sim.supplies.meal_day = day
	ctx.page.refresh(true)


func test_tonight_is_told_under_take_control_in_the_scavenging_modules_own_words() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	check(page.night_note != null and not page.night_note.visible, "no place chosen: no note")
	_on_day(ctx, 10, 7.0)
	page.select_place("houses")
	var want: Dictionary = sim.scavenge.night_warning("houses", "", float(sim.town.SEARCH_H))
	check(bool(want.big), "day 10 of a game with an avatar is a Big Night")
	check(page.night_note.visible, "the note is there")
	eq(page.night_note.text, String(want.text), "its words are the scavenging module's")
	check(String(page.night_note.text).begins_with("Big Night tonight: leave the place by"), "it says when to leave: '%s'" % page.night_note.text)
	eq(page.night_note.get_theme_color("font_color"), ctx.hud.INK2, "calm while the party makes it")
	var go: Button = page.buttons.go
	var after = page.night_note.get_parent()
	check(after != null and after == go.get_parent(), "it sits with Take control")
	check(page.night_note.get_index() > go.get_index(), "under the button")
	_free(ctx)


func test_the_note_is_the_same_the_town_boards_row_shows_and_it_follows_the_vehicle() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	sim.vehicles.fleet.append({"id": "rig", "kind": "pickup", "hp": 80.0, "state": "parked"})
	sim.vehicles.fuel = 30.0
	_on_day(ctx, 10, 7.0)
	page.select_place("houses")
	var on_foot := String(page.night_note.text)
	var line: Dictionary = NightKit.warning_line(sim, "houses", "", float(sim.town.SEARCH_H))
	eq(on_foot, String(line.text), "the board's line, for a trip on foot")
	check(page.choose_vehicle("rig"), "the pickup")
	var by_car := String(page.night_note.text)
	eq(by_car, String(NightKit.warning_line(sim, "houses", "rig", float(sim.town.SEARCH_H)).text), "and for the trip by the pickup")
	check(by_car != on_foot, "the road home is not the same length: '%s' and '%s'" % [on_foot, by_car])
	_free(ctx)


func test_the_note_is_amber_when_the_trip_cannot_be_home_in_time_and_gone_when_there_is_nothing_to_say() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	_on_day(ctx, 10, 16.5)
	page.select_place("houses")
	var line: Dictionary = NightKit.warning_line(sim, "houses", "", float(sim.town.SEARCH_H))
	check(not line.is_empty() and line.tone == "warn" and line.big, "late on a Big Night the board says it will not make it: %s" % str(line))
	check(page.night_note.visible, "so does the page")
	eq(page.night_note.text, String(line.text), "in the same words")
	eq(page.night_note.get_theme_color("font_color"), ctx.hud.WARN, "in amber")
	_on_day(ctx, 3, 7.0)
	var quiet: Dictionary = NightKit.warning_line(sim, "houses", "", float(sim.town.SEARCH_H))
	check(quiet.is_empty(), "an ordinary morning has nothing to say")
	check(not page.night_note.visible, "and the note is hidden")
	_on_day(ctx, 10, 7.0)
	check(page.night_note.visible, "and back on a Big Night")
	sim.player_id = ""
	page.refresh(true)
	check(not page.night_note.visible, "with no avatar there is no note")
	_free(ctx)


# ----------------------------------------------------------------------- the errand --

func test_asking_for_an_errand_queues_the_people_and_they_set_off_after_the_delay() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	page.select_place("houses")
	page.toggle_person(_person(ctx, "dez"))
	page.toggle_person(_person(ctx, "ana"))
	var res: Dictionary = page.act("errand")
	check(bool(res.ok), "the errand is asked: %s" % str(res))
	check(String(res.line) != "", "somebody said something: '%s'" % res.line)
	var wait: Array = sim.radio.errand_wait
	eq(wait.size(), 1, "the radio holds the errand for its delay")
	if wait.size() == 1:
		var ids: Array = (wait[0].ids as Array).duplicate()
		ids.sort()
		eq(ids, ["ana", "dez"], "Dez and Ana")
		eq(String(wait[0].place), "houses", "to the houses")
		eq(String(wait[0].action), "loot", "to loot")
	eq(sim.scavenge.parties.size(), 0, "nobody has set off yet: the delay is the radio's")
	eq(page.ticks, [], "the people who agreed are no longer ticked")
	eq(_status(ctx, "dez"), "setting off", "Dez's chip says so")
	check(_chip(ctx, "dez").disabled and String(_chip(ctx, "dez").tooltip_text) != "", "and is off, with a tooltip")
	check(page.answer_label.visible and String(page.answer_label.text).contains("Dez"), "the answer is under the button: '%s'" % page.answer_label.text)
	check(String(page.answer_label.text).contains("set off in about"), "with when they set off: '%s'" % page.answer_label.text)
	# the foot knows of the errand that waits
	check(_says(ctx, "setting off to loot Neighbourhood houses"), "the foot lists it: %s" % str(_words(page.out_box)))
	# after the delay they are a party, out
	Helpers.run(sim, 6.0)
	eq(sim.scavenge.parties.size(), 1, "after the delay the party is made")
	if sim.scavenge.parties.size() == 1:
		var party: Dictionary = sim.scavenge.parties[0]
		var members: Array = (party.members as Array).duplicate()
		members.sort()
		eq(members, ["ana", "dez"], "Dez and Ana")
		eq(String(party.site), "houses", "at the houses")
	page.refresh()
	check(_says(ctx, "looting Neighbourhood houses"), "the foot says where they are: %s" % str(_words(page.out_box)))
	eq(sim.radio.errand_wait.size(), 0, "nothing waits")
	check(sim.scavenge.is_errand(sim.scavenge.parties[0]), "the colony takes it for an errand: they go without the player")
	Helpers.run(sim, 40.0)    # (they walk to the gate and out: the News tells it as they leave)
	var told := false
	for e in sim.radio.news:
		if String(e.kind) == "errand" and String(e.text).contains("set off"):
			told = true
	check(told, "and the News says so")
	_free(ctx)


func test_an_errand_that_cannot_start_when_its_delay_is_up_is_told_and_nobody_is_left_waiting() -> void:
	var ctx := await _settled(440, 760, 9.96)
	var page = ctx.page
	var sim = ctx.sim
	page.select_place("houses")
	page.toggle_person(_person(ctx, "dez"))
	check(bool(page.act("errand").ok), "asked a minute before the last hour of leaving")
	Helpers.run(sim, 40.0)
	page.refresh()
	eq(sim.scavenge.parties.size(), 0, "the hour passed: nobody went")
	eq(sim.radio.errand_wait.size(), 0, "and nothing waits")
	var told := ""
	for e in sim.radio.news:
		if String(e.kind) == "errand":
			told = String(e.text)
	check(told.begins_with("The errand could not start"), "the News says so: '%s'" % told)
	eq(_status(ctx, "dez"), "willing", "Dez is free again on his chip")
	check(_says(ctx, "Nobody is out."), "and the foot is empty")
	_free(ctx)


func test_the_errand_goes_as_a_scout_or_a_clear_when_the_switch_says_so() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	page.select_place("depot")
	page.set_errand_action("clear")
	page.toggle_person(_person(ctx, "dez"))
	page.toggle_person(_person(ctx, "ana"))
	check(bool(page.act("errand").ok), "a clearing errand")
	eq(String(sim.radio.errand_wait[0].action), "clear", "to clear")
	_free(ctx)
	var ctx2 := await _settled()
	var page2 = ctx2.page
	page2.select_place("pharmacy")
	page2.set_errand_action("scout")
	page2.toggle_person(_person(ctx2, "marcus"))
	check(bool(page2.act("errand").ok), "a scouting errand")
	eq(String(ctx2.sim.radio.errand_wait[0].action), "scout", "to scout")
	_free(ctx2)


func test_the_errand_with_a_vehicle_takes_it() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	sim.vehicles.fleet.append({"id": "rig", "kind": "pickup", "hp": 80.0, "state": "parked"})
	sim.vehicles.fuel = 30.0
	page.refresh(true)
	page.select_place("houses")
	page.choose_vehicle("rig")
	page.toggle_person(_person(ctx, "dez"))
	check(bool(page.act("errand").ok), "asked")
	eq(String(sim.radio.errand_wait[0].vehicle), "rig", "in the pickup")
	_free(ctx)


func test_an_errand_the_trip_refuses_is_not_asked() -> void:
	var ctx := await _settled()
	var page = ctx.page
	page.select_place("houses")
	page.toggle_person(_person(ctx, "dez"))
	_at(ctx, 21.0)
	var res: Dictionary = page.act("errand")
	check(not bool(res.ok), "after dark")
	eq(ctx.sim.radio.errand_wait.size(), 0, "nothing was asked")
	check(page.feedback_label.visible and String(page.feedback_label.text) == String(res.why), "the page says why: '%s'" % page.feedback_label.text)
	_free(ctx)


# ------------------------------------------------------------------------- Insist --

func test_a_soft_refusal_is_listed_and_can_be_pushed_at_a_cost_of_trust() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	var ana = _person(ctx, "ana")
	ana.bleeding = 3.0
	page.refresh()
	page.select_place("houses")
	page.toggle_person(ana)
	page.toggle_person(_person(ctx, "dez"))
	var soft: Dictionary = sim.radio.reason_not(ana, "go")
	check(not bool(soft.ok), "Ana refuses: %s" % str(soft))
	check(page.buttons.insist.visible, "Insist is offered")
	check(_says(ctx, String(soft.why)), "her refusal is written under the button, in the radio's words: %s" % str(_words(page.refusal_box)))
	eq(String(page.buttons.errand.text), "Ask Dez to go", "the button asks Dez only")
	check(not page.buttons.errand.disabled, "(Dez would go)")
	check(String(page.buttons.insist.tooltip_text).contains(str(int(sim.radio.INSIST_COST))), "the tooltip gives the cost in trust: '%s'" % page.buttons.insist.tooltip_text)
	# not pushing: Dez goes, Ana stays
	var res: Dictionary = page.act("errand")
	check(bool(res.ok), "asked without a push")
	var ids: Array = sim.radio.errand_wait[0].ids
	eq(ids, ["dez"], "only Dez goes")
	eq(page.ticks, ["ana"], "Ana is still ticked: she was not asked to go")
	_free(ctx)


func test_insisting_sends_the_one_who_refuses_and_costs_their_trust() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	var ana = _person(ctx, "ana")
	ana.bleeding = 3.0
	page.refresh()
	page.select_place("houses")
	page.toggle_person(ana)
	page.toggle_person(_person(ctx, "dez"))
	page.set_insist(true)
	eq(String(page.buttons.errand.text), "Ask Dez and Ana to go", "pushing: both are named")
	check(page.buttons.insist.button_pressed and String(page.buttons.insist.text) == "Insisting", "Insist shows it is on")
	var before: float = ana.trust
	var res: Dictionary = page.act("errand", {"insist": page.insist_on})
	check(bool(res.ok), "asked, pushing")
	var ids: Array = (sim.radio.errand_wait[0].ids as Array).duplicate()
	ids.sort()
	eq(ids, ["ana", "dez"], "both go")
	near(before - ana.trust, sim.radio.INSIST_COST, 1e-6, "Ana's trust fell by the radio's INSIST_COST")
	check(not page.insist_on, "the push is spent")
	_free(ctx)


func test_when_everybody_asked_refuses_softly_the_button_is_off_until_they_are_pushed() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	var ana = _person(ctx, "ana")
	ana.bleeding = 3.0
	page.refresh()
	page.select_place("houses")
	page.toggle_person(ana)
	var w: Dictionary = sim.radio.errand_willingness([ana], "houses", "loot", "")
	check(not bool(w.ok), "nobody would go: '%s'" % w.why)
	check(page.buttons.errand.disabled and String(page.buttons.errand.tooltip_text).begins_with(String(w.why)), "the button is off and says the radio's reason")
	check(String(page.buttons.errand.tooltip_text).contains("Insist"), "and where the way round is: '%s'" % page.buttons.errand.tooltip_text)
	check(page.buttons.insist.visible, "Insist is there")
	page.set_insist(true)
	check(not page.buttons.errand.disabled, "pushing, the button is on")
	eq(String(page.buttons.errand.text), "Ask Ana to go", "for Ana")
	var res: Dictionary = page.act("errand", {"insist": true})
	check(bool(res.ok), "she goes, grudgingly")
	_free(ctx)


func test_a_person_who_is_gone_cannot_be_pushed() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var dez = _person(ctx, "dez")
	page.toggle_person(dez)
	dez.downed = true
	page.refresh()
	check(not page.buttons.insist.visible, "a hard refusal has no Insist")
	check(not page.toggle_person(dez), "and cannot be ticked")
	_free(ctx)


# ------------------------------------------------------------- Claim and Recall --

func test_claim_and_recall_have_the_boards_reasons_and_the_boards_effects() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	ctx.hud.open_scavenge(null)
	await Kit.settle()
	var board = ctx.hud.scavenge_dialog
	# the places, one by one: the page's words are the board's
	for id in ["depot", "chapel", "houses"]:
		page.select_place(id)
		board.select_place(id)
		eq(page.reason_for("claim"), board.reason_for("claim"), "claim at %s" % id)
	page.select_place("depot")
	eq(page.reason_for("claim"), "Clear it first: the dead have to be gone.", "the dead are there")
	check(page.buttons.claim.visible and page.buttons.claim.disabled, "Claim is shown for a place with an outpost, and off")
	eq(String(page.buttons.claim.tooltip_text), "Clear it first: the dead have to be gone.", "its tooltip is the reason")
	check(page.feedback_label.visible and String(page.feedback_label.text) == "Clear it first: the dead have to be gone.", "and the page says it in words")
	eq(String(page.buttons.claim.text), "Claim for 20 scrap", "the price is on the button")
	page.select_place("chapel")
	check(not page.buttons.claim.visible, "a place with no outpost has no Claim")
	# cleared, but not enough scrap
	sim.town.mark_cleared("depot")
	sim.stock.scrap = 5.0
	page.select_place("depot")
	board.select_place("depot")
	page.refresh(true)
	eq(page.reason_for("claim"), "It takes 20 scrap and the stores have 5.", "too poor")
	eq(page.reason_for("claim"), board.reason_for("claim"), "as the board says it")
	sim.stock.scrap = 60.0
	page.refresh(true)
	eq(page.reason_for("claim"), "", "with the scrap it can be done")
	check(not page.buttons.claim.disabled, "the button is on")
	var res: Dictionary = page.act("claim")
	check(bool(res.ok), "claimed")
	eq(sim.town.state_of("depot"), "claimed", "the depot is an outpost")
	near(float(sim.stock.scrap), 40.0, 1e-6, "for 20 scrap")
	check(page.feedback_label.visible and String(page.feedback_label.text).contains("is yours now"), "the page says so: '%s'" % page.feedback_label.text)
	check(not page.buttons.claim.visible, "the button is gone")
	check(_words(page.tag_flow).has("YOUR OUTPOST"), "and the card says it is yours")
	board.close()
	_free(ctx)


func test_recall_brings_a_garrison_home_by_day_and_says_why_not_in_the_dark() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	sim.town.mark_cleared("depot")
	check(sim.town.claim("depot"), "the depot is claimed")
	page.select_place("depot")
	check(not page.buttons.recall.visible, "nobody is there: no Recall")
	check(sim.town.garrison_send("depot", [_person(ctx, "dez")]), "Dez holds it")
	page.refresh(true)
	check(page.buttons.recall.visible and not page.buttons.recall.disabled, "someone holds it: Recall is on by day")
	eq(String(page.facts.held.label.text), "Dez", "the card says who")
	_at(ctx, 21.0)
	eq(page.reason_for("recall"), sim.town.why_not_recall("depot"), "in the dark: the rules' words")
	check(page.buttons.recall.disabled and String(page.buttons.recall.tooltip_text) == sim.town.why_not_recall("depot"), "on the button")
	_at(ctx, 8.0)
	var res: Dictionary = page.act("recall")
	check(bool(res.ok), "recalled")
	eq(String(res.line), "Dez is on the way home from The bus depot.", "in words")
	eq(sim.town.garrison_of("depot"), [], "nobody is stationed there")
	_free(ctx)


# --------------------------------------------------------------------- the foot --

func test_the_foot_lists_the_parties_out_as_the_board_does() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	check(_says(ctx, "Nobody is out."), "nobody out: it says so")
	check(sim.scavenge.send([_person(ctx, "dez"), _person(ctx, "ana")], "houses", "loot"), "a party goes")
	page.refresh()
	var mine := _words(page.out_box)
	eq(mine.size(), 1, "one line")
	ctx.hud.open_scavenge(null)
	await Kit.settle()
	var board = ctx.hud.scavenge_dialog
	board._refresh_out()
	var theirs := Kit.texts(board.out_box)
	check(theirs.size() == 1 and mine.size() == 1 and String(mine[0]) == String(theirs[0]), "the same words as the board's slip: '%s' and '%s'" % [str(mine), str(theirs)])
	check(String(mine[0]).contains("Dez and Ana, looting Neighbourhood houses"), "who, what, where: '%s'" % mine[0])
	check(String(mine[0]).contains("back about") or String(mine[0]).contains("back tomorrow"), "and when: '%s'" % mine[0])
	board.close()
	# the map marks them too
	check(page.map.parties.size() == 1, "a party marker is on the map")
	_free(ctx)


# ---------------------------------------------------------------- the full page --

func test_full_page_opens_the_town_board_through_the_hud() -> void:
	var ctx := await _settled()
	var page = ctx.page
	check(not ctx.hud.town_board_open(), "no board yet")
	page.buttons.full.pressed.emit()
	await Kit.settle()
	check(ctx.hud.town_board_open(), "the Full page button opens the Town Board")
	ctx.hud.scavenge_dialog.close()
	page.full_page()
	await Kit.settle()
	check(ctx.hud.town_board_open(), "and so does full_page()")
	ctx.hud.scavenge_dialog.close()
	_free(ctx)


# ----------------------------------------------------------------- nothing to map --

func test_without_a_board_the_page_says_so_and_does_nothing() -> void:
	var classic := Kit.build()
	Kit.update(classic)
	var panel: PanelContainer = classic.hud._panel(classic.hud._style(Hud.PANEL, 6, Hud.LINE, true, "panel"))
	panel.custom_minimum_size = Vector2(440, 500)
	classic.holder.add_child(panel)
	var page := MapPage.new()
	panel.add_child(page)
	page.setup(classic.hud, func(): return classic.sim)
	await Kit.settle()
	page.refresh()
	check(page.message_label.visible, "a message says there is no map")
	check(not page.body.visible, "and nothing else is shown")
	check(page.reason_for("go") != "" and page.reason_for("errand") != "", "every action says why it is off")
	check(not page.select_place("houses"), "no place can be chosen")
	page.refresh(true)
	page.full_page()
	Kit.free_all(classic)


# ----------------------------------------------------- every control that is off says why --

## Every button of the page that is showing and off, with the reason it gives: the words of its tooltip. Empty when all are on or say why.
func _silent_buttons(page) -> Array:
	var out: Array = []
	for b in page.find_children("*", "Button", true, false):
		if not b.is_visible_in_tree():
			continue
		if b.disabled and String(b.tooltip_text).strip_edges() == "":
			out.append("'%s' is off and says nothing" % String(b.text))
	return out


func test_every_button_that_is_off_has_a_tooltip_for_every_place_person_and_action() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	for id in ["farm", "works", "clinic"]:
		sim.town.reveal(id)
	sim.vehicles.fleet.append({"id": "rig", "kind": "pickup", "hp": 80.0, "state": "parked"})
	sim.vehicles.fuel = 1.0
	sim.town.mark_cleared("depot")
	page.refresh(true)
	eq(_silent_buttons(page), [], "nothing chosen")
	var states := ["day", "dusk", "hurt", "fuel", "no_scrap"]
	for state in states:
		match state:
			"day":
				_at(ctx, 7.0)
			"dusk":
				_at(ctx, 21.0)
			"hurt":
				_at(ctx, 7.0)
				_person(ctx, "ana").bleeding = 3.0
				_person(ctx, "dez").downed = true
			"fuel":
				_person(ctx, "ana").bleeding = 0.0
				_person(ctx, "dez").downed = false
				_at(ctx, 7.0)
			"no_scrap":
				sim.stock.scrap = 0.0
		for id in page.sites.keys():
			page.select_place(String(id))
			for action in ["loot", "scout", "clear"]:
				page.set_errand_action(action)
				for ride in ["", "rig"]:
					page.choose_vehicle(ride)
					# nobody, one, two, all four
					page.ticks.clear()
					page.refresh(true)
					eq(_silent_buttons(page), [], "%s, %s, %s by %s, nobody ticked" % [state, id, action, ride if ride != "" else "foot"])
					var order: Array = []
					for p in _free_people(ctx):
						order.append(p)
					for i in order.size():
						page.toggle_person(order[i])
						eq(_silent_buttons(page), [], "%s, %s, %s by %s, %d ticked" % [state, id, action, ride if ride != "" else "foot", page.ticks.size()])
					for p in page.chips:
						if page.chips[p].chip.disabled:
							check(String(page.chips[p].chip.tooltip_text) != "", "%s's chip is off and says why (%s)" % [p, state])
					# the reason for each action is a sentence when it is off
					for a in ["go", "errand", "claim", "recall"]:
						var why: String = page.reason_for(a)
						check(why == "" or why.length() > 3, "the reason for %s is words: '%s'" % [a, why])
	_free(ctx)


func test_nothing_on_the_page_takes_focus() -> void:
	var ctx := await _settled()
	var page = ctx.page
	ctx.sim.vehicles.fleet.append({"id": "rig", "kind": "pickup", "hp": 80.0, "state": "parked"})
	ctx.sim.vehicles.fuel = 30.0
	ctx.sim.town.mark_cleared("depot")
	page.refresh(true)
	page.select_place("depot")
	page.toggle_person(_person(ctx, "dez"))
	page.set_insist(true)
	await Kit.settle()
	var n := 0
	for c in page.find_children("*", "Control", true, false):
		if c.focus_mode != Control.FOCUS_NONE:
			check(false, "%s '%s' takes focus" % [c.get_class(), c.get("text") if c.get("text") != null else ""])
		n += 1
	check(n > 30, "the walk saw the page's controls: %d" % n)
	_free(ctx)


func test_the_page_asks_for_no_key() -> void:
	# a key goes to the game, never to the page: no shortcut, no handler for keys
	var ctx := await _settled()
	check(not ctx.page.has_method("_unhandled_key_input") and not ctx.page.has_method("_input") and not ctx.page.has_method("_unhandled_input"), "the page has no key handler of its own")
	for b in ctx.page.find_children("*", "Button", true, false):
		check(b.shortcut == null, "no button of the page has a shortcut")
	_free(ctx)


# ----------------------------------------------------------------------- the layout --

## The page in the state `state`: "none" (no place), "depot" (the depot, two people ticked, one refusing), "answer" (an errand asked),
## "vehicle" (a pickup chosen, a cleared place), "night" (after dark, a refusal on every button), "party" (a party out).
func _stage(ctx: Dictionary, state: String) -> void:
	var page = ctx.page
	var sim = ctx.sim
	match state:
		"depot":
			sim.town.reveal("works")
			sim.town.reveal("farm")
			_person(ctx, "ana").bleeding = 3.0
			page.refresh(true)
			page.select_place("depot")
			page.toggle_person(_person(ctx, "ana"))
			page.toggle_person(_person(ctx, "dez"))
			page.set_insist(true)
		"answer":
			page.select_place("houses")
			page.toggle_person(_person(ctx, "dez"))
			page.toggle_person(_person(ctx, "marcus"))
			page.act("errand")
		"vehicle":
			sim.vehicles.fleet.append({"id": "rig", "kind": "pickup", "hp": 80.0, "state": "parked"})
			sim.vehicles.fleet.append({"id": "rig2", "kind": "bus", "hp": 60.0, "state": "parked"})
			sim.vehicles.fuel = 30.0
			sim.town.reveal("farm")
			sim.town.mark_cleared("depot")
			page.refresh(true)
			page.select_place("depot")
			page.choose_vehicle("rig")
			page.toggle_person(_person(ctx, "dez"))
			page.toggle_person(_person(ctx, "walt"))
		"night":
			_at(ctx, 21.0)
			page.select_place("houses")
			page.toggle_person(_person(ctx, "dez"))
		"bignight":
			# (round 19: the note under Take control, on a Big Night with the trip too late to be home in time)
			_on_day(ctx, 10, 16.5)
			page.select_place("houses")
			page.toggle_person(_person(ctx, "dez"))
			check(page.night_note.visible, "the note is up in this state")
		"party":
			sim.scavenge.send([_person(ctx, "dez"), _person(ctx, "ana")], "houses", "loot")
			sim.clock_min += 50.0
			page.refresh(true)
			page.select_place("pharmacy")
	page.refresh(true)


## What is wrong with the page's layout in its panel: a control wider than the page, a chip on a chip, the page wider than the panel or
## shorter than its content, the foot outside the page. Empty when nothing is.
func _misfits(ctx: Dictionary, width: float, _height: float) -> Array:
	var out: Array = []
	var page = ctx.page
	var box := Kit.rect(page)
	var shown := Kit.rect(ctx.scroll)
	if page.get_combined_minimum_size().x > width:
		out.append("the page asks for %.0f px of a panel %.0f wide" % [page.get_combined_minimum_size().x, width])
	if box.size.x > shown.size.x + 0.5 or box.position.x < shown.position.x - 0.5:
		out.append("the page %s is wider than the panel's scroll %s" % [str(box), str(shown)])
	if box.size.y + 0.5 < page.get_combined_minimum_size().y:
		out.append("the page is %.0f tall and wants %.0f" % [box.size.y, page.get_combined_minimum_size().y])
	for c in page.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree() or page.map_scroll.is_ancestor_of(c) or c == page.map:
			continue
		var r := Kit.rect(c)
		if r.size == Vector2.ZERO:
			continue
		if r.end.x > box.end.x + 0.5 or r.position.x < box.position.x - 0.5:
			out.append("%s '%s' sticks out sideways: %s in %s" % [c.get_class(), str(c.get("text")) if c.get("text") != null else "", str(r), str(box)])
	# the chips, the vehicles' chips and the buttons that sit side by side do not overlap
	for group in [page.chip_flow, page.ride_flow, page.claim_row]:
		var named := {}
		for c in group.get_children():
			if c.visible:
				named[str(c.get_instance_id())] = Kit.rect(c)
		out.append_array(Kit.overlaps(named))
	var foot := Kit.rect(page.foot)
	if foot.size != Vector2.ZERO and not box.grow(1.0).encloses(foot):
		out.append("the foot %s is not in the page %s" % [str(foot), str(box)])
	var map_box := Kit.rect(page.map_scroll)
	if map_box.size.x > 0.0 and map_box.size.x > box.size.x + 0.5:
		out.append("the map frame %s is wider than the page %s" % [str(map_box), str(box)])
	return out


func test_the_page_fits_the_panel_at_440_and_316_in_every_state() -> void:
	for width in WIDTHS:
		var ctx := await _settled(width, 760)
		for state in ["none", "depot", "answer", "vehicle", "night", "party", "bignight"]:
			_stage(ctx, state)
			await Kit.settle()
			await Kit.settle()
			eq(_misfits(ctx, width, 760), [], "%d wide, %s" % [width, state])
		_free(ctx)


func test_the_page_fits_five_sizes_of_panel() -> void:
	for size in FUZZ:
		var ctx := await _settled(size[0], size[1])
		for state in ["none", "depot", "vehicle", "answer"]:
			_stage(ctx, state)
			await Kit.settle()
			await Kit.settle()
			eq(_misfits(ctx, size[0], size[1]), [], "%d x %d, %s" % [size[0], size[1], state])
		# a panel too short for the page scrolls: at the end of the scroll the foot is in view
		var scroll: ScrollContainer = ctx.scroll
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await Kit.settle()
		var foot := Kit.rect(ctx.page.foot)
		var shown := Kit.rect(scroll)
		check(shown.grow(1.5).encloses(foot), "%d x %d: scrolled to the end, the foot is in view: %s in %s" % [size[0], size[1], str(foot), str(shown)])
		_free(ctx)


func test_the_page_is_as_tall_as_its_content_so_the_panel_can_fit_to_it() -> void:
	var ctx := await _settled(440, 1500)
	var page = ctx.page
	_stage(ctx, "depot")
	await Kit.settle()
	await Kit.settle()
	var want: float = page.get_combined_minimum_size().y
	var foot := Kit.rect(page.foot)
	var top := Kit.rect(page).position.y
	check(want >= foot.end.y - top - 1.0, "the page's minimum height %.0f holds its foot (which ends %.0f down)" % [want, foot.end.y - top])
	check(want > 500.0, "a page with a map, a card, the people and the buttons is not small: %.0f" % want)
	# a page with no place chosen is shorter
	page.select_place("houses")
	_stage(ctx, "none")
	var shorter: float = page.get_combined_minimum_size().y
	page.select_place("depot")
	await Kit.settle()
	check(page.get_combined_minimum_size().y >= shorter - 0.5, "choosing a place does not make it shorter")
	_free(ctx)


func test_a_window_that_changes_the_panels_width_lays_the_page_out_again() -> void:
	var ctx := await _settled(440, 700)
	_stage(ctx, "depot")
	await Kit.settle()
	var wide: float = ctx.page.map_size().x
	ctx.panel.custom_minimum_size = Vector2(316, 700)
	ctx.panel.size = Vector2(316, 700)
	await Kit.settle()
	await Kit.settle()
	check(ctx.page.map_size().x < wide, "the map is narrower: %.0f against %.0f" % [ctx.page.map_size().x, wide])
	eq(_misfits(ctx, 316, 700), [], "shrunk to 316")
	ctx.panel.custom_minimum_size = Vector2(440, 700)
	ctx.panel.size = Vector2(440, 700)
	await Kit.settle()
	await Kit.settle()
	eq(_misfits(ctx, 440, 700), [], "grown back")
	_free(ctx)


func test_the_map_is_a_compact_sheet_whose_height_comes_from_its_width() -> void:
	for width in WIDTHS:
		var ctx := await _settled(width, 760)
		var page = ctx.page
		var size: Vector2 = page.map_size()
		var avail: float = page.size.x
		check(avail > float(width) - 60.0, "%d: the page has the panel's width: %.0f" % [width, avail])
		check(size.x >= avail - 1.0 and size.x <= avail + 1.0, "%d: the sheet is as wide as the page: %.0f of %.0f" % [width, size.x, avail])
		check(size.y <= maxf(MapPage.MAP_MIN_H, size.x * MapPage.MAP_ASPECT) + 1.0, "%d: and not taller than its share: %.0f" % [width, size.y])
		check(size.y >= 100.0, "%d: but not a strip: %.0f" % [width, size.y])
		_free(ctx)


func test_a_wide_town_gets_a_sheet_that_scrolls_sideways_and_the_pins_keep_apart() -> void:
	var ctx := await _settled(316, 760)
	var page = ctx.page
	# a town that has grown: everything is known (the real one is much wider than the little one)
	for p in ctx.sim.town.places:
		ctx.sim.town.reveal(String(p.id))
	page.refresh(true)
	await Kit.settle()
	var need: float = page.map.width_for_clear_pins()
	var size: Vector2 = page.map_size()
	check(size.x >= minf(need, MapPage.MAP_MAX_W) - 1.0, "the sheet has the width the pins need: %.0f for %.0f" % [size.x, need])
	check(size.x <= MapPage.MAP_MAX_W + 1.0, "but no more than the most: %.0f" % size.x)
	var frame := Kit.rect(page.map_scroll)
	check(frame.size.x <= Kit.rect(page).size.x, "the frame is inside the page")
	eq(_misfits(ctx, 316, 760), [], "and the page still fits")
	# the frame opens on the school, and a place chosen far along the sheet is brought into view
	await Kit.settle()
	await Kit.settle()
	var school: float = page._sheet_x(float(page.map.home.x))
	var left := float(page.map_scroll.scroll_horizontal)
	check(school >= left and school <= left + frame.size.x, "the school (%.0f) is in the frame (%.0f to %.0f)" % [school, left, left + frame.size.x])
	var far := ""
	var far_x := 0.0
	for id in page.sites:
		var x: float = page._sheet_x(float(page.sites[id].pos.x))
		if absf(x - school) > absf(far_x - school):
			far = String(id)
			far_x = x
	page.select_place(far)
	await Kit.settle()
	await Kit.settle()
	left = float(page.map_scroll.scroll_horizontal)
	check(far_x >= left - 1.0 and far_x <= left + frame.size.x + 1.0, "%s (%.0f) is in the frame after it is chosen (%.0f to %.0f)" % [far, far_x, left, left + frame.size.x])
	_free(ctx)


# --------------------------------------------------------------- the words' size and ink --

func test_nothing_on_the_page_is_under_twelve_pixels() -> void:
	var tt := TextTests.new()
	for size in FUZZ:
		var ctx := await _settled(size[0], size[1])
		for state in ["none", "depot", "vehicle", "answer"]:
			_stage(ctx, state)
			await Kit.settle()
			eq(tt._small_text(ctx.page), [], "%d x %d, %s" % [size[0], size[1], state])
		_free(ctx)
	check(Fonts.MIN_PX >= 12, "the floor is 12")


## The words of the page that are on the panel (the map and its key are on paper, and are looked at on their own).
func _hard_to_read_on_the_panel(tt, page, ground: Color) -> Array:
	var out: Array = []
	for l in page.find_children("*", "Label", true, false):
		if page.map_scroll.is_ancestor_of(l) or page.key_panel.is_ancestor_of(l) or String(l.text) == "":
			continue
		var ratio: float = tt._worst_contrast(l, l.get_theme_color("font_color"), ground)
		if ratio < tt.AA:
			out.append("'%s' is %.2f:1" % [String(l.text).left(30), ratio])
	for b in page.find_children("*", "Button", true, false):
		if String(b.text) == "" or not b.is_visible_in_tree():
			continue
		var state := "disabled" if b.disabled else "normal"
		var ink: Color = b.get_theme_color("font_disabled_color" if b.disabled else "font_color")
		var behind: Array = tt._backdrops(b, ground)
		var fills: Array = Kit.fills(b.get_theme_stylebox(state))
		for i in 2:
			var bg: Color = tt.over(fills[i], behind[i])
			var ratio: float = tt.contrast(tt.over(ink, bg), bg)
			if ratio < tt.AA:
				out.append("button '%s' (%s) is %.2f:1" % [b.text, state, ratio])
				break
	return out


func test_every_word_on_the_page_reads_on_the_panel_in_either_look() -> void:
	var tt := TextTests.new()
	for frames in [true, false]:
		Hud.use_frames = frames
		var look := "frames" if frames else "flat"
		for width in WIDTHS:
			var ctx := await _settled(width, 900)
			for state in ["none", "depot", "answer", "vehicle", "night", "party"]:
				_stage(ctx, state)
				await Kit.settle()
				_park_the_mouse()
				eq(_hard_to_read_on_the_panel(tt, ctx.page, Color.WHITE), [], "%s, %d wide, %s" % [look, width, state])
				eq(tt._dark_red_words(ctx.page), [], "%s, %d wide, %s: no word in the dark red" % [look, width, state])
			_free(ctx)
	Hud.use_frames = true


func test_the_key_reads_on_its_paper() -> void:
	var tt := TextTests.new()
	var ctx := await _settled()
	var page = ctx.page
	page.key_button.button_pressed = true
	await Kit.settle()
	check(page.key_panel.visible, "the key opens")
	var words := _words(page.key_panel)
	check(words.has("Cleared") and words.has("Nest (strength)") and words.has("Unexplored"), "it names the marks: %s" % str(words))
	for l in page.key_panel.find_children("*", "Label", true, false):
		var ratio: float = tt.contrast(l.get_theme_color("font_color"), TownMap.SHEET)
		check(ratio >= tt.AA, "'%s' on the sheet is %.2f:1" % [l.text, ratio])
	page.key_button.button_pressed = false
	check(not page.key_panel.visible, "and closes")
	_free(ctx)


# --------------------------------------------------------------------- play at random --

func test_random_play_on_the_page_never_breaks_it() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var sim = ctx.sim
	for id in ["farm", "works", "clinic"]:
		sim.town.reveal(id)
	sim.vehicles.fleet.append({"id": "rig", "kind": "pickup", "hp": 80.0, "state": "parked"})
	sim.vehicles.fuel = 20.0
	page.refresh(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	var places: Array = page.sites.keys()
	var people: Array = _free_people(ctx)
	for step in 240:
		match rng.randi_range(0, 11):
			0, 1:
				page.select_place(String(places[rng.randi_range(0, places.size() - 1)]))
			2, 3, 4:
				page.toggle_person(people[rng.randi_range(0, people.size() - 1)])
			5:
				page.choose_vehicle("rig" if rng.randf() < 0.5 else "")
			6:
				page.set_errand_action(["loot", "scout", "clear"][rng.randi_range(0, 2)])
			7:
				page.set_insist(rng.randf() < 0.5)
			8:
				page.act(["errand", "go", "claim", "recall"][rng.randi_range(0, 3)], {"insist": page.insist_on})
			9:
				_person(ctx, "ana").bleeding = 3.0 if rng.randf() < 0.5 else 0.0
				_person(ctx, "dez").downed = rng.randf() < 0.2
			10:
				Helpers.run(sim, rng.randf_range(0.5, 4.0))
				if rng.randf() < 0.3:
					_at(ctx, [7.0, 9.0, 21.0][rng.randi_range(0, 2)])
			11:
				page.refresh()
		page.refresh()
		if step % 30 == 0:
			await Kit.settle()
			eq(_silent_buttons(page), [], "step %d: every button that is off says why" % step)
		for id in page.ticks:
			check(page.chips.has(String(id)), "step %d: a tick of someone who has no chip" % step)
		check(page.ticks.size() <= page.party_limit() or page.ticks.is_empty(), "step %d: more ticked than the seats: %d of %d" % [step, page.ticks.size(), page.party_limit()])
		if page.chosen() != "":
			check(page.sites.has(page.chosen()), "step %d: a place that is not on the board is chosen" % step)
	await Kit.settle()
	eq(_misfits(ctx, 440, 760), [], "and the page still fits")
	_free(ctx)


func test_the_real_town_at_the_start_and_when_it_is_all_known() -> void:
	for width in WIDTHS:
		var ctx := await _settled(width, 760, 7.0, true)
		var page = ctx.page
		eq(page.map.pins.size(), 5, "%d: the five places the real town begins with" % width)
		eq(_misfits(ctx, width, 760), [], "%d: the page fits" % width)
		for p in ctx.sim.town.places:
			ctx.sim.town.reveal(String(p.id))
		page.refresh(true)
		await Kit.settle()
		await Kit.settle()
		check(page.map.pins.size() > 30, "%d: every place has a pin: %d" % [width, page.map.pins.size()])
		eq(_misfits(ctx, width, 760), [], "%d: the page fits with the whole town on the sheet" % width)
		# no two pins touch (the sheet is as wide as the pins need; it scrolls sideways)
		var ids: Array = page.map.pins.keys()
		var worst := 1.0e9
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				worst = minf(worst, page.map.pins[ids[i]].position.distance_to(page.map.pins[ids[j]].position))
		check(worst >= TownMap.PIN_R * 2.0 - 0.5 or page.map_size().x >= MapPage.MAP_MAX_W - 1.0, "%d: the nearest two pins are %.0f px apart on a sheet %.0f wide" % [width, worst, page.map_size().x])
		# a place across the river is chosen: the sheet brings it into view
		page.select_place("hospital")
		check(page.chosen() == "hospital", "%d: the hospital can be chosen" % width)
		await Kit.settle()
		await Kit.settle()
		var x: float = page._sheet_x(float(ctx.sim.town.place("hospital").pos.x))
		var left := float(page.map_scroll.scroll_horizontal)
		check(x >= left - 1.0 and x <= left + page.map_scroll.size.x + 1.0, "%d: the hospital (%.0f) is in the frame (%.0f to %.0f)" % [width, x, left, left + page.map_scroll.size.x])
		_free(ctx)


# ------------------------------------------------------------- in the radio panel itself --

func test_the_page_in_the_real_radio_panel_opens_focuses_and_closes_it_when_a_trip_begins() -> void:
	var ctx := await _settled()
	var hud = ctx.hud
	# (the HUD of this game has its own panel, which builds the real page when the Map is first asked for)
	Kit.update(ctx, 1)
	hud.open_radio("map", {"focus": "depot"})
	await Kit.settle()
	check(hud.radio_open() and hud.radio_page() == "map", "the Map page of the panel is up")
	var node = hud.radio_panel.page_node("map")
	check(node != null and node.get_script() == MapPage, "and it is this page")
	eq(node.chosen(), "depot", "opts.focus chose the place")
	check(not hud.modal_open(), "the panel is not a modal")
	check(node.map.pins.size() == 4 and node.map.pins["houses"].focus_mode == Control.FOCUS_NONE, "its pins take no focus")
	# the tab says what it is
	var tab: Button = hud.radio_panel.tab_button("map")
	check(tab.visible and String(tab.tooltip_text) != "", "the Map tab is there and has a tooltip")
	# a trip begun from the page shuts the panel (the raid hides the yard's HUD)
	node.select_place("houses")
	node.toggle_person(_person(ctx, "dez"))
	var res: Dictionary = node.act("go")
	check(bool(res.ok), "Take control: %s" % str(res))
	check(not hud.radio_open(), "the panel is shut when the trip begins")
	eq(ctx.raids.size(), 1, "and the raid was asked for")
	# an errand does not shut it
	hud.open_radio("map")
	node.select_place("houses")
	node.toggle_person(_person(ctx, "marcus"))
	check(bool(node.act("errand").ok), "an errand is asked")
	check(hud.radio_open() and hud.radio_page() == "map", "the panel stays open for it")
	# the Full page button goes through the HUD
	node.buttons.full.pressed.emit()
	await Kit.settle()
	check(hud.town_board_open(), "Full page opens the Town Board")
	hud.scavenge_dialog.close()
	_free(ctx)


func test_hovering_a_pin_names_it() -> void:
	var ctx := await _settled()
	var page = ctx.page
	var pin = page.map.pins["pharmacy"]
	pin.mouse_entered.emit()
	eq(page.map.hovered, "pharmacy", "the map knows the pointer is on the pharmacy")
	check(page.map.captions().has("pharmacy"), "and writes its name beside it")
	check(String(pin.tooltip_text).begins_with("The pharmacy: "), "the tooltip says how far: '%s'" % pin.tooltip_text)
	pin.mouse_exited.emit()
	eq(page.map.hovered, "", "and lets it go")
	_free(ctx)
