extends "res://tests/case.gd"
## Round 13, the view of vehicles and fuel (R13.3): everything the player sees and clicks about them. The rules are
## tests/test_vehicles.gd's (the core's); here are
##   - the Town Board's party picker with a vehicle (scripts/ui/town_board.gd): the row of "On foot" and the parked vehicles,
##     the party's size and the trip's hours that follow the one chosen, Go, Scout and Clear sending with its id, the reasons,
##     the tag of a place that only a vehicle reaches and the line of one that holds a vehicle;
##   - the map (scripts/ui/town_map.gd): fitted to what is known, widening when the bridge and the city are found, the
##     chip across the river, the picture of every kind of place of the city;
##   - the Fuel line of the stores (scripts/ui/hud.gd), the alerts of a vehicle found or lost;
##   - the vehicles in the motor pool (scripts/render/parking_node.gd) and a click on one;
##   - the tip, once.
## The picker is looked at on a small town of its own (FIX); the map on the real one.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const TownBoard := preload("res://scripts/ui/town_board.gd")
const TownMap := preload("res://scripts/ui/town_map.gd")
const Dialog := preload("res://scripts/ui/scavenge_dialog.gd")
const BoardTests := preload("res://tests/test_town_board.gd")
const TextTests := preload("res://tests/test_hud_text.gd")
const ParkingNode := preload("res://scripts/render/parking_node.gd")
const Hints := preload("res://scripts/ui/hints.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Tut := preload("res://tests/tutorial_kit.gd")

const FIXTURE := "user://test_vehicles_view.json"
const SIZES := [[700, 700], [980, 700], [1280, 800], [1920, 1080]]

## Home is at (50, 35). The houses are near; the garage holds a pickup; the gas station has fuel; the hospital is across
## the river: far, and a place that only a vehicle reaches.
const FIX := {
	"board": {"w": 160, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "Neighbourhood houses", "kind": "houses", "pos": [58, 35], "blurb": "Somebody's pantry is somebody's pantry.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {}},
		{"id": "garage", "name": "Dunne's garage", "kind": "garage", "pos": [41, 35], "blurb": "Grease, and a pickup on blocks.", "danger": 2, "known": true,
			"loot": {"scrap": [10, 20]}, "extra": {}, "vehicle": "pickup"},
		{"id": "gas", "name": "The fuel stop", "kind": "gas_station", "pos": [50, 44], "blurb": "Pumps, and a tank under the forecourt.", "danger": 1, "known": true,
			"loot": {"fuel": [20, 30]}, "extra": {}},
		{"id": "hospital", "name": "St. Bride's hospital", "kind": "hospital", "pos": [140, 35], "blurb": "Across the river.", "danger": 3, "known": true,
			"loot": {"meds": [20, 30]}, "extra": {}, "needs_vehicle": true},
	],
	"roads": [["home", "houses"], ["home", "garage"], ["home", "gas"], ["home", "hospital"]],
	"beats": [],
}


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## A settlement game on the little town, at `hour` of day 3, plenty of everything, a quiet world, nobody out.
func _game(hour: float = 7.0, seed_value: int = 13) -> Dictionary:
	_write(FIXTURE, FIX)
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


func _park_the_mouse() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(1, 1)
	ev.global_position = Vector2(1, 1)
	Engine.get_main_loop().root.push_input(ev, true)


## The HUD over a game, as main.gd's frames give it (the real modules).
func _ctx_of(g: Dictionary, width: int, height: int) -> Dictionary:
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
	Kit.update(ctx, 1)
	return ctx


func _ctx(width: int = 1280, height: int = 800) -> Dictionary:
	return _ctx_of(_game(), width, height)


## ... with the board open.
func _open(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := _ctx(width, height)
	ctx.hud.open_scavenge(null)
	_park_the_mouse()    # (after the page exists: a hover's tooltip on the Close button would be on it otherwise)
	return ctx


func _board(ctx: Dictionary):
	return ctx.hud.scavenge_dialog


func _settle3() -> void:
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()


## A vehicle of that kind brought home: its id.
func _add(ctx: Dictionary, kind: String) -> String:
	return String(ctx.sim.vehicles.add(kind).id)


func _tag_words(board) -> Array:
	var words: Array = []
	for c in board.tag_flow.get_children():
		for l in c.find_children("*", "Label", true, false):
			words.append(String(l.text))
	return words


func _trip(board) -> String:
	return String(board.facts.trip.label.text)


func _until_back(sim, limit: int = 2000) -> void:
	var n := 0
	while not sim.scavenge.parties.is_empty() and n < limit:
		Helpers.run(sim, 1.0)
		n += 1


# ------------------------------------------------------------------- the picker --

func test_the_picker_is_there_only_while_a_vehicle_is_parked_and_offers_those_that_are() -> void:
	var ctx := _open()
	var board = _board(ctx)
	check(not board.ride_box.visible, "no vehicle: no row")
	eq(board.vehicle_id, "", "on foot")
	var sedan := _add(ctx, "sedan")
	var bus := _add(ctx, "bus")
	ctx.sim.vehicles.fuel = 40.0
	board.refresh(true)
	check(board.ride_box.visible, "two parked: the row")
	var ids: Array = board.ride_chips.keys()
	ids.sort()
	var want: Array = ["", sedan, bus]
	want.sort()
	eq(ids, want, "On foot and the two vehicles, nothing else")
	# one goes out: it is not on offer
	ctx.sim.vehicles.vehicle(sedan)["state"] = "out"
	board.refresh(true)
	check(not board.ride_chips.has(sedan) and board.ride_chips.has(bus), "a vehicle that is out is not offered")
	ctx.sim.vehicles.vehicle(sedan)["state"] = "parked"
	board.refresh(true)
	check(board.ride_chips.has(sedan), "and is, parked again")
	# lost: gone from the fleet
	ctx.sim.vehicles.fleet.erase(ctx.sim.vehicles.vehicle(bus))
	board.refresh(true)
	check(not board.ride_chips.has(bus), "a vehicle that is lost is not offered")
	ctx.sim.vehicles.fleet.erase(ctx.sim.vehicles.vehicle(sedan))
	board.refresh(true)
	check(not board.ride_box.visible, "nothing parked: the row is gone again")
	Kit.free_all(ctx)


func test_each_chip_shows_the_seats_the_fuel_the_trip_needs_and_its_hours() -> void:
	var ctx := _open()
	var board = _board(ctx)
	var sedan := _add(ctx, "sedan")
	var bus := _add(ctx, "bus")
	ctx.sim.vehicles.fuel = 40.0
	board.refresh(true)
	# with no place chosen: the seats and what it burns
	eq(board.ride_chips[sedan].name.text, "Sedan", "the name")
	check(String(board.ride_chips[sedan].l2.text).contains("3 seats"), "the seats: %s" % board.ride_chips[sedan].l2.text)
	check(String(board.ride_chips[bus].l2.text).contains("6 seats"), "a bus's: %s" % board.ride_chips[bus].l2.text)
	check(String(board.ride_chips[sedan].l3.text).contains("burns 3"), "what it burns an hour: %s" % board.ride_chips[sedan].l3.text)
	# with the houses chosen: the fuel for that trip and the hours by it
	board.select_place("houses")
	for vid in [sedan, bus]:
		var need: float = ctx.sim.vehicles.fuel_for("houses", vid)
		var e: Dictionary = board.ride_chips[vid]
		check(String(e.l2.text).contains("fuel %s" % TownBoard._num(need)), "%s: the fuel of the trip, %s: %s" % [vid, TownBoard._num(need), e.l2.text])
		eq(String(e.l3.text), TownMap.hours_text(ctx.sim.scavenge.action_hours("houses", "loot", vid)), "%s: the hours by it" % vid)
	eq(String(board.ride_chips[""].l3.text), TownMap.hours_text(ctx.sim.town.trip_hours("houses")), "On foot: the hours on foot")
	check(float(ctx.sim.scavenge.action_hours("houses", "loot", sedan)) < float(ctx.sim.town.trip_hours("houses")), "(the vehicle is quicker)")
	# the tank is told
	check(String(board.ride_tip.text).contains("40"), "the tank has 40: %s" % board.ride_tip.text)
	# a place farther off needs more
	board.select_place("hospital")
	var far_need: float = ctx.sim.vehicles.fuel_for("hospital", sedan)
	check(far_need > ctx.sim.vehicles.fuel_for("houses", sedan), "(the hospital burns more)")
	check(String(board.ride_chips[sedan].l2.text).contains(TownBoard._num(far_need)), "the chip follows the place: %s" % board.ride_chips[sedan].l2.text)
	eq(String(board.ride_chips[""].l3.text), "Too far to walk", "On foot says it cannot be done there")
	Kit.free_all(ctx)


func test_choosing_a_vehicle_changes_the_trips_hours_and_the_size_of_the_party() -> void:
	var ctx := _open()
	var board = _board(ctx)
	var sedan := _add(ctx, "sedan")
	var pickup := _add(ctx, "pickup")
	var bus := _add(ctx, "bus")
	ctx.sim.vehicles.fuel = 60.0
	board.select_place("houses")
	var on_foot := _trip(board)
	check(on_foot.contains("there and back.") and not on_foot.contains(" by the "), "on foot: %s" % on_foot)
	eq(board.party_limit(), 3, "three on foot")
	check(board.choose_vehicle(sedan), "the sedan is chosen")
	eq(board.vehicle_id, sedan, "(it is the one)")
	var by_sedan := _trip(board)
	check(by_sedan.contains("by the sedan") and by_sedan != on_foot, "the trip is told by it: %s" % by_sedan)
	var hours := TownMap.hours_text(ctx.sim.scavenge.action_hours("houses", "loot", sedan))
	check(by_sedan.to_lower().begins_with(hours), "with its hours (%s): %s" % [hours, by_sedan])
	check(by_sedan.contains(TownBoard._num(ctx.sim.vehicles.fuel_for("houses", sedan))), "and its fuel: %s" % by_sedan)
	eq(board.party_limit(), 3, "the sedan seats three")
	board.choose_vehicle(pickup)
	eq(board.party_limit(), 2, "the pickup two")
	board.choose_vehicle(bus)
	eq(board.party_limit(), 6, "the bus six")
	# the tool tips of the buttons say the hours by the vehicle
	check(String(board.buttons.loot.tooltip_text).contains(TownMap.hours_text(ctx.sim.scavenge.action_hours("houses", "loot", bus))), "Go's tip: %s" % board.buttons.loot.tooltip_text)
	# On foot again
	board.choose_vehicle("")
	eq(board.vehicle_id, "", "on foot again")
	eq(_trip(board), on_foot, "and the trip is as it was")
	check(not board.choose_vehicle("v99"), "a vehicle that is not there cannot be chosen")
	eq(board.vehicle_id, "", "(nothing changed)")
	Kit.free_all(ctx)


func test_the_party_is_as_big_as_the_seats_and_the_page_refuses_with_the_rules_words() -> void:
	var ctx := _open()
	var board = _board(ctx)
	ctx.sim.add_person(ctx.sim.recruits.queue.pop_front())    # (the radio's first caller is in: a fourth person)
	var pickup := _add(ctx, "pickup")
	var bus := _add(ctx, "bus")
	ctx.sim.vehicles.fuel = 70.0
	board.select_place("houses")
	board.refresh(true)
	var people: Array = ctx.sim.scavenge.free_survivors()
	check(people.size() >= 4, "(four are free: %d)" % people.size())
	for p in people:
		if not board.party.has(p) and board.party.size() < 3:
			board.toggle_member(p)
	eq(board.party.size(), 3, "three are in the party")
	var fourth = null
	for p in people:
		if not board.party.has(p):
			fourth = p
	check(fourth != null, "(one is left at home)")
	check(not board.toggle_member(fourth), "on foot: a fourth is refused")
	eq(board.error_label.text, "Three is the most.", "with the old words")
	board.choose_vehicle(bus)
	check(board.toggle_member(fourth), "in the bus: a fourth goes")
	eq(board.party.size(), 4, "four")
	eq(board.reason_for("loot"), "", "and the page has nothing against Go")
	# a smaller vehicle: the party is too big for it, and the buttons say so with the rules' words
	board.choose_vehicle(pickup)
	var why: String = board.reason_for("loot")
	eq(why, ctx.sim.scavenge.why_not_action(board.party, "houses", "loot", pickup), "the rules' own words")
	check(why.contains("seats 2"), "the pickup seats two: %s" % why)
	check(board.buttons.loot.disabled and board.buttons.scout.disabled, "Go and Scout are off")
	eq(board.why_line_for("loot"), "Go, Scout and Clear: %s" % why, "and the line under them says it")
	check(not board.act("loot"), "Go does nothing")
	eq(ctx.sim.scavenge.parties.size(), 0, "(nobody left)")
	# on foot with the four: the page says so too
	board.choose_vehicle("")
	check(board.reason_for("loot") != "" and board.buttons.loot.disabled, "on foot with four: off, with a reason: %s" % board.reason_for("loot"))
	# the people over the seats are refused with the rules' words
	board.choose_vehicle(pickup)
	board.toggle_member(fourth)
	eq(board.party.size(), 3, "(one steps down)")
	check(not board.toggle_member(fourth), "a person beyond the seats is refused")
	check(String(board.error_label.text).contains("The pickup seats 2."), "with the core's reason: %s" % board.error_label.text)
	Kit.free_all(ctx)


func test_go_scout_and_clear_send_the_party_with_the_vehicle() -> void:
	var by_action := {"loot": "houses", "scout": "houses", "clear": "houses"}
	for action in by_action:
		var ctx := _open()
		var board = _board(ctx)
		var sedan := _add(ctx, "sedan")
		ctx.sim.vehicles.fuel = 40.0
		board.select_place("houses")
		board.choose_vehicle(sedan)
		var fuel_before: float = ctx.sim.vehicles.fuel
		var need: float = ctx.sim.vehicles.fuel_for("houses", sedan)
		check(board.act(action), "%s goes" % action)
		eq(ctx.sim.scavenge.parties.size(), 1, "%s: a party is out" % action)
		var party: Dictionary = ctx.sim.scavenge.parties[0]
		eq(String(party.get("vehicle", "")), sedan, "%s: it took the sedan" % action)
		eq(String(party.action), action, "(the errand)")
		eq(String(ctx.sim.vehicles.vehicle(sedan).state), "out", "%s: the sedan is out" % action)
		near(ctx.sim.vehicles.fuel, fuel_before - need, 0.001, "%s: the fuel is burnt" % action)
		near(float(party.return_at) - float(party.depart), ctx.sim.scavenge.action_hours("houses", action, sedan) * 60.0, 1.5, "%s: the hours are the sedan's" % action)
		check(ctx.hud.toast_label.text.contains("in the sedan"), "%s: the toast says it: %s" % [action, ctx.hud.toast_label.text])
		check(not ctx.hud.town_board_open(), "%s: the page is gone" % action)
		Kit.free_all(ctx)


func test_the_foot_and_the_map_say_a_party_is_out_in_a_vehicle() -> void:
	var ctx := _open()
	var board = _board(ctx)
	var van := _add(ctx, "van")
	ctx.sim.vehicles.fuel = 40.0
	board.select_place("houses")
	board.choose_vehicle(van)
	check(board.act("loot"), "sent")
	ctx.hud.open_scavenge(null)
	board = _board(ctx)
	await _settle3()
	check(board != null and board.is_open(), "the board is open again")
	var slips: Array = []
	for c in board.out_box.get_children():
		for l in c.find_children("*", "Label", true, false):
			slips.append(String(l.text))
	var said := " ".join(slips)
	check(said.contains("looting Neighbourhood houses in the van"), "the foot says 'in the van': %s" % said)
	check(said.contains("back about") or said.contains("back tomorrow"), "and when: %s" % said)
	eq(board.map.parties.size(), 1, "the map has the party")
	eq(String(board.map.parties[0].vehicle), "Van", "marked as a vehicle's: %s" % str(board.map.parties[0]))
	var rect_before: Vector2 = board.map.party_position(int(board.map.parties[0].n))
	check(rect_before.x >= 0.0, "and it is on its road")
	# the trip's length is the van's: the road there takes less than on foot
	var route_h: float = ctx.sim.vehicles.drive_hours("houses", van) / 2.0
	check(route_h < ctx.sim.town.hours_to("houses"), "(the van is quicker)")
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the reasons --

func test_not_enough_fuel_is_told_on_the_buttons() -> void:
	var ctx := _open()
	var board = _board(ctx)
	var sedan := _add(ctx, "sedan")
	ctx.sim.vehicles.fuel = 0.5
	board.select_place("houses")
	board.choose_vehicle(sedan)
	var why: String = board.reason_for("loot")
	check(why.begins_with("It needs") and why.contains("fuel"), "the rules' words: %s" % why)
	check(board.buttons.loot.disabled and board.buttons.scout.disabled and board.buttons.clear.disabled, "Go, Scout and Clear are off")
	eq(board.why_line_for("loot"), "Go, Scout and Clear: %s" % why, "the line under the buttons")
	eq(String(board.buttons.loot.tooltip_text), why, "and Go's tip")
	check(not board.act("loot"), "Go does nothing")
	check(board.error_label.visible and board.error_label.text == why, "and says why")
	eq(ctx.sim.vehicles.vehicle(sedan).state, "parked", "(the sedan is where it was)")
	# fuel comes: the buttons are on
	ctx.sim.vehicles.fuel = 20.0
	board.refresh(true)
	eq(board.reason_for("loot"), "", "with fuel, nothing against it")
	check(not board.buttons.loot.disabled, "Go is on")
	Kit.free_all(ctx)


func test_a_place_that_needs_a_vehicle_has_a_tag_and_is_refused_on_foot() -> void:
	var ctx := _open()
	var board = _board(ctx)
	board.select_place("houses")
	check(not _tag_words(board).has("BY VEHICLE ONLY"), "an ordinary place has no tag")
	board.select_place("hospital")
	check(_tag_words(board).has("BY VEHICLE ONLY"), "the hospital has: %s" % str(_tag_words(board)))
	var why: String = board.reason_for("loot")
	eq(why, "Too far to go on foot: take a vehicle.", "on foot: the rules' words")
	eq(board.reason_for("scout"), why, "Scout too")
	check(board.buttons.loot.disabled and board.buttons.scout.disabled, "the buttons are off")
	eq(board.why_line_for("loot"), "Go, Scout and Clear: %s" % why, "with the line")
	check(_trip(board).contains("vehicle"), "the trip says it takes a vehicle: %s" % _trip(board))
	# the pin is not a plain one
	check(bool(board.map.pins["hospital"].place.get("needs_vehicle", false)) and not bool(board.map.pins["houses"].place.get("needs_vehicle", false)), "the map knows which pins are by vehicle")
	check(String(board.map.pins["hospital"].tooltip_text).contains("By vehicle only"), "and the pin's tip says so: %s" % board.map.pins["hospital"].tooltip_text)
	# with a vehicle it can go
	var sedan := _add(ctx, "sedan")
	ctx.sim.vehicles.fuel = 60.0
	board.refresh(true)
	board.choose_vehicle(sedan)
	eq(board.reason_for("loot"), "", "in the sedan there is nothing against it")
	check(_trip(board).contains("by the sedan") and not _trip(board).contains("Too far"), "and the trip is told: %s" % _trip(board))
	check(board.act("loot"), "it goes")
	eq(String(ctx.sim.scavenge.parties[0].site), "hospital", "to the hospital")
	Kit.free_all(ctx)


func test_a_place_that_holds_a_vehicle_says_so() -> void:
	var ctx := _open()
	var board = _board(ctx)
	board.select_place("garage")
	var f: Dictionary = board.facts.vehicle
	check(f.value.visible and f.cap.visible, "the garage says so")
	eq(String(f.label.text), "A pickup stands here: loot it to try to get it running.", "in these words")
	board.select_place("houses")
	check(not f.value.visible, "the houses do not")
	board.select_place("garage")
	ctx.sim.town.state["garage"]["vehicle_taken"] = true
	board.refresh(true)
	check(not f.value.visible, "a vehicle that has been taken is not there")
	Kit.free_all(ctx)


func test_the_fuel_a_place_gives_has_its_chip() -> void:
	var ctx := _open()
	var board = _board(ctx)
	board.select_place("gas")
	var found := false
	for c in board.chips_box.get_children():
		for l in c.find_children("*", "Label", true, false):
			if String(l.text) == "20–30":
				found = true
	check(found, "the fuel stop shows 20-30 (with the pump)")
	Kit.free_all(ctx)


# ----------------------------------------------------------------------- the map --

## The real town's board over a settlement game, `places` of it known (ids).
func _real_board(width: int, height: int, known: Array = []) -> Dictionary:
	var g := Helpers.make(7, 1, 3)
	var ctx := _ctx_of(g, width, height)
	for id in known:
		if id == "all":
			for k in g.sim.town.state:
				g.sim.town.state[k].known = true
		else:
			g.sim.town.state[id].known = true
	ctx.hud.open_scavenge(null)
	return ctx


func _pins_apart(board) -> Array:
	var bad: Array = []
	var ids: Array = board.map.pins.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d: float = board.map.pin_center(ids[i]).distance_to(board.map.pin_center(ids[j]))
			if d < TownMap.PIN_R * 2.0:
				bad.append("%s and %s are %.0f px apart" % [ids[i], ids[j], d])
	return bad


func test_the_map_fits_what_is_known_and_widens_with_the_bridge_and_the_city() -> void:
	var ctx := _real_board(1280, 800)
	var board = _board(ctx)
	var sim = ctx.sim
	var map = board.map
	check(map.view.size.x < float(sim.town.board.w) * 0.7, "at the start the sheet shows the town, not the 160 tiles: %s" % str(map.view))
	check(map.view.end.x < 98.0, "the bridge is not in view: it ends at %.0f" % map.view.end.x)
	check(map.view.has_point(sim.town.home), "the school is in view")
	for id in map.pins:
		check(map.view.has_point(Vector2(map.pins[id].place.pos)), "%s is in view" % id)
	check(map.view_aspect() <= TownMap.ASPECT_MAX + 0.001 and map.view_aspect() >= TownMap.ASPECT_MIN - 0.001, "the sheet keeps a shape: %.2f" % map.view_aspect())
	check(not map.wants_chip() and map.river_chip.size == Vector2.ZERO, "no chip yet")
	var start_end: float = map.view.end.x
	# the bridge is found: the sheet widens, the river runs through it, and the chip points across
	sim.town.reveal("river_bridge")
	sim.town.reveal("bus_depot")
	board.refresh(true)
	check(map.view.end.x > 110.0 and map.view.end.x > start_end, "with the bridge known the sheet reaches over the river: %.0f" % map.view.end.x)
	check(not map._bridge().is_empty(), "the bridge is on the map")
	check(map.wants_chip() and map.river_chip.size.x > 40.0, "'Across the river' is at the edge: %s" % str(map.river_chip))
	check(Rect2(Vector2.ZERO, map.size).encloses(map.river_chip), "inside the sheet")
	for id in map.pins:
		var c: Vector2 = map.pin_center(id)
		check(not map.river_chip.intersects(Rect2(c - Vector2(TownMap.PIN_R, TownMap.PIN_R), Vector2(TownMap.PIN_R, TownMap.PIN_R) * 2.0)), "the chip is off the pin of %s" % id)
	check(map.river_chip.end.x > map.size.x - 12.0, "and at the east edge")
	# a place across the river is known: the chip is not needed
	sim.town.reveal("checkpoint")
	board.refresh(true)
	check(not map.wants_chip() and map.river_chip.size == Vector2.ZERO, "the city is found: no chip")
	# everything is known: the whole of what there is
	for k in sim.town.state:
		sim.town.state[k].known = true
	board.refresh(true)
	check(map.view.end.x >= 133.0 and map.view.position.x <= 8.0, "all known: the sheet reaches both ends: %s" % str(map.view))
	check(map.view.size.x <= float(sim.town.board.w) and map.view.size.y <= float(sim.town.board.h), "(and not past the board)")
	Kit.free_all(ctx)


func test_no_two_pins_overlap_at_any_width_with_only_the_start_known_the_bridge_known_or_everything() -> void:
	var bt := BoardTests.new()
	for state in ["start", "bridge", "all"]:
		for size in SIZES:
			var known: Array = []
			if state == "bridge":
				known = ["river_bridge", "bus_depot", "gas_station"]
			elif state == "all":
				known = ["all"]
			var ctx := _real_board(size[0], size[1], known)
			await _settle3()
			await Kit.settle()
			_park_the_mouse()
			var board = _board(ctx)
			eq(_pins_apart(board), [], "%s, %d x %d: the pins keep apart" % [state, size[0], size[1]])
			for id in ["", "river_bridge" if state != "start" else "police"]:
				if id == "":
					board.site_id = ""
					board.refresh(true)
				elif board.sites.has(id):
					board.select_place(id)
				await Kit.settle()
				eq(bt._misfits(ctx, size), [], "%s, %d x %d, %s: the page fits" % [state, size[0], size[1], id if id != "" else "nothing chosen"])
				failures.append_array(bt.failures)
				bt.failures.clear()
			Kit.free_all(ctx)


func test_every_kind_of_the_city_has_its_own_picture() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/town.json"))
	var kinds := {}
	for p in raw.places:
		kinds[String(p.kind)] = true
	var glyphs := {}
	for kind in ["bridge", "checkpoint", "cold_store", "university", "power_station", "rail_yard"]:
		check(kinds.has(kind), "(%s is a kind of the real town)" % kind)
		var g := TownMap.glyph_of(kind)
		check(g != "generic", "%s has a glyph of its own: %s" % [kind, g])
		check(not glyphs.has(g), "and not another's: %s" % g)
		glyphs[g] = kind
	for kind in kinds:
		check(TownMap.glyph_of(kind) != "generic", "'%s' has an icon" % kind)
	check(TownMap.glyph_of("fuel_depot") == "pump" and TownMap.glyph_of("hospital") == "cross", "the old ones are as they were")


func test_the_map_draws_the_city_the_river_and_a_party_in_a_vehicle_without_error() -> void:
	var ctx := _real_board(1280, 800, ["all"])
	var board = _board(ctx)
	var sim = ctx.sim
	var van := _add(ctx, "bus")
	sim.vehicles.fuel = 80.0
	board.refresh(true)
	board.select_place("hospital")
	board.choose_vehicle(van)
	check(board.act("loot") or true, "(a trip may or may not be on: only the drawing is looked at)")
	ctx.hud.open_scavenge(null)
	await _settle3()
	var b2 = _board(ctx)
	if b2 != null:
		b2.map.queue_redraw()
		b2.map._over.queue_redraw()
		for pin in b2.map.pins.values():
			pin.queue_redraw()
	await _settle3()
	check(true, "drawn")
	Kit.free_all(ctx)


# ------------------------------------------------------------------ the fuel line --

func _stores_ctx(width: int = 1280, height: int = 800, crew: int = 3) -> Dictionary:
	return Kit.build(width, height, 1, false, crew)


func test_the_fuel_line_is_there_only_in_a_settlement_game_with_a_vehicle_or_some_fuel() -> void:
	var ctx := _stores_ctx()
	var h = ctx.hud
	var sim = ctx.sim
	check(sim.town.on, "(a settlement game)")
	Kit.update(ctx)
	check(not h.fuel_cells[2].visible and not h.fuel_cells[0].visible and not h.fuel_cells[1].visible, "no vehicle and no fuel: no line")
	sim.vehicles.fuel = 34.0
	Kit.update(ctx)
	check(h.fuel_cells[0].visible and h.fuel_cells[1].visible and h.fuel_cells[2].visible, "some fuel: the line")
	eq(h.res_values.fuel.text, "34", "Fuel 34")
	eq(h.fuel_cells[1].text, "Fuel", "named")
	check(h.fuel_cells[0].texture == h.icons.fuel and h.icons.has("fuel"), "with the pump")
	sim.vehicles.fuel = 0.0
	Kit.update(ctx)
	check(not h.fuel_cells[2].visible, "the tank is empty and there is no vehicle: no line again")
	_add({"sim": sim}, "sedan")
	Kit.update(ctx)
	check(h.fuel_cells[2].visible and h.res_values.fuel.text == "0", "a vehicle and an empty tank: the line, at 0")
	Kit.free_all(ctx)
	# the classic start has none, whatever the rules hold
	var classic := _stores_ctx(1280, 800, 6)
	check(not classic.sim.town.on, "(the classic start)")
	classic.sim.vehicles.fuel = 50.0
	classic.sim.vehicles.add("sedan")
	Kit.update(classic)
	check(not classic.hud.fuel_cells[2].visible, "the classic start never shows fuel")
	Kit.free_all(classic)


func test_the_fuel_is_amber_when_it_is_low_and_there_is_a_vehicle_to_burn_it() -> void:
	var ctx := _stores_ctx()
	var h = ctx.hud
	var sim = ctx.sim
	sim.vehicles.fuel = 4.0
	Kit.update(ctx)
	eq(h.res_values.fuel.get_theme_color("font_color"), Hud.INK, "low fuel and no vehicle: nothing to worry about")
	sim.vehicles.add("pickup")
	for case in [[4.0, Hud.WARN], [9.6, Hud.WARN], [9.0, Hud.WARN], [10.0, Hud.INK], [34.0, Hud.INK], [0.0, Hud.WARN]]:
		sim.vehicles.fuel = float(case[0])
		Kit.update(ctx)
		eq(h.res_values.fuel.get_theme_color("font_color"), case[1], "%s fuel with a vehicle" % str(case[0]))
	Kit.free_all(ctx)


func test_the_stores_panel_is_as_it_was_without_the_fuel_line_and_taller_by_a_row_with_it() -> void:
	var classic := _stores_ctx(1280, 800, 6)
	var settled := _stores_ctx(1280, 800, 3)
	Kit.update(classic)
	Kit.update(settled)
	await Kit.settle()
	await Kit.settle()
	var shown := 0
	for c in classic.hud.res_grid.get_children():
		if c.visible:
			shown += 1
	eq(shown, 15, "classic: five rows of three cells")
	eq(Kit.rect(classic.hud.res_panel).size, Kit.rect(settled.hud.res_panel).size, "a settlement game without fuel has the same panel")
	settled.sim.vehicles.fuel = 20.0
	Kit.update(settled)
	await Kit.settle()
	await Kit.settle()
	var taller: float = Kit.rect(settled.hud.res_panel).size.y - Kit.rect(classic.hud.res_panel).size.y
	check(taller > 14.0 and taller < 40.0, "with the line, one row taller: %.0f px" % taller)
	check(absf(Kit.rect(settled.hud.res_panel).size.x - Kit.rect(classic.hud.res_panel).size.x) < 1.0, "and not wider")
	Kit.free_all(classic)
	Kit.free_all(settled)


func test_the_fuel_line_holds_at_every_width_and_in_short_windows() -> void:
	for size in [[1920, 1080], [1280, 800], [980, 700], [700, 700], [700, 560], [1280, 600]]:
		var ctx := _stores_ctx(size[0], size[1], 3)
		var h = ctx.hud
		ctx.sim.vehicles.fuel = 34.0
		ctx.sim.vehicles.add("sedan")
		var ruth = Kit.person(ctx, "ruth")
		Kit.select(ctx, ruth)
		h.set_fields(true)
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var win := Rect2(0, 0, size[0], size[1])
		var rects := {
			"stores": Kit.rect(h.res_panel), "legend": Kit.rect(h.fields_legend), "cards": Kit.rect(h.bar), "clock": Kit.rect(h.clock),
			"alerts": Kit.rect(h.alerts_box), "selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos), "speed": Kit.rect(h.speed_panel),
		}
		eq(Kit.overlaps(rects), [], "%d x %d: nothing overlaps the stores" % [size[0], size[1]])
		for name in rects:
			if rects[name].size.x > 1.0 and rects[name].size.y > 1.0:
				check(win.encloses(rects[name].grow(-0.5)), "%d x %d: %s is in the window: %s" % [size[0], size[1], name, str(rects[name])])
		var fuel_row: Rect2 = Kit.rect(h.fuel_cells[2]).merge(Kit.rect(h.fuel_cells[0]))
		check(Kit.rect(h.res_panel).encloses(fuel_row.grow(-0.5)), "%d x %d: the fuel row is in the panel" % [size[0], size[1]])
		var compact: bool = size[0] < 980
		eq(h.fuel_cells[1].is_visible_in_tree(), not compact, "%d wide: the name is there only where the others' are" % size[0])
		eq(TextTests.new()._small_text(h.res_panel), [], "%d wide: nothing under 12 px in the stores" % size[0])
		Kit.free_all(ctx)


func test_the_stores_anchor_names_the_fuel_row() -> void:
	var ctx := _stores_ctx()
	ctx.sim.vehicles.fuel = 20.0
	Kit.update(ctx)
	await Kit.settle()
	await Kit.settle()
	var r: Rect2 = ctx.hud.anchor_rect("stores.fuel")
	check(r.size.x > 0.0 and r.size.y > 0.0, "a tip can light the fuel row: %s" % str(r))
	ctx.sim.vehicles.fuel = 0.0
	ctx.sim.vehicles.fleet.clear()
	Kit.update(ctx)
	await Kit.settle()
	check(ctx.hud.anchor_rect("stores.fuel").size == Vector2.ZERO or not ctx.hud.fuel_cells[2].visible, "and nothing without it")
	Kit.free_all(ctx)


# ----------------------------------------------------------------------- alerts --

func test_a_vehicle_that_is_lost_or_found_shows_in_the_alerts_with_an_icon() -> void:
	var ctx := _open(1280, 800)
	var sim = ctx.sim
	ctx.hud.scavenge_dialog.close()
	await Kit.settle()
	# found: a party loots the garage and gets the pickup running (the dice's answer is put in by hand, as the core's tests do)
	var crew: Array = []
	for id in ["dez", "marcus"]:
		crew.append(Kit.person(ctx, id))
	check(sim.scavenge.send(crew, "garage", "loot"), "to the garage")
	sim.scavenge.parties[0].result["vehicle"] = "pickup"
	sim.scavenge.parties[0].result.hurt.clear()
	sim.scavenge.parties[0].result.lost.clear()
	_until_back(sim)
	eq(sim.vehicles.fleet.size(), 1, "a pickup is home")
	check(sim.alerts.has("vehicle-found-garage"), "the rules raised the alert: %s" % str(sim.alerts.keys()))
	eq(String(sim.alerts["vehicle-found-garage"].text), "A pickup is home", "in these words")
	Kit.update(ctx)
	await Kit.settle()
	check(ctx.hud.alert_items.has("vehicle-found-garage"), "the HUD lists it")
	eq(ctx.hud._alert_icon_name(ctx.hud.alert_items["vehicle-found-garage"]), "car", "with the car")
	# lost: the sedan does not come back
	var sedan := _add(ctx, "sedan")
	sim.vehicles.vehicle(sedan)["state"] = "out"
	sim.vehicles.come_home(sedan, 2, 1, true)
	eq(sim.vehicles.fleet.size(), 1, "the sedan is gone from the fleet")
	check(sim.alerts.has("vehicle-%s" % sedan), "the rules raised the alert")
	eq(String(sim.alerts["vehicle-%s" % sedan].text), "The sedan is lost", "in these words")
	Kit.update(ctx)
	await Kit.settle()
	check(ctx.hud.alert_items.has("vehicle-%s" % sedan), "the HUD lists it too")
	eq(ctx.hud._alert_icon_name(ctx.hud.alert_items["vehicle-%s" % sedan]), "car", "with the car")
	check(ctx.hud.icons.has("car") and ctx.hud.icons.car != null, "(the picture is there)")
	Kit.free_all(ctx)


# ------------------------------------------------------------ the vehicles in the motor pool --
# (round 15: the street parking is gone; the vehicles stand in the motor pool, inside the main gate, and drive in and
# out of it. Their poses, doors, gate and sounds are tests/test_vehicle_actor.gd's; here is what the Town Board's click
# and the settlement game's rules see of them.)

## The motor pool's apron as the file says it (x, y, w, h in tiles).
func _apron() -> Rect2:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/motor_pool.json"))
	var a: Array = raw.apron
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


func _node_of(sim) -> Node2D:
	var node := ParkingNode.new()
	Engine.get_main_loop().root.add_child(node)
	node.setup(sim)
	return node


func test_the_motor_pool_draws_the_parked_vehicles_only_in_a_settlement_game() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node_of(sim)
	eq(node.drawn_ids(), [], "no fleet, nothing drawn")
	var sedan := String(sim.vehicles.add("sedan").id)
	var pickup := String(sim.vehicles.add("pickup").id)
	node.update()
	var ids: Array = node.drawn_ids()
	ids.sort()
	var want: Array = [sedan, pickup]
	want.sort()
	eq(ids, want, "the two parked are drawn")
	check(node.spot_of(sedan) >= 0 and node.spot_of(pickup) >= 0 and node.spot_of(sedan) != node.spot_of(pickup), "each on a place of its own")
	var apron := _apron()
	for id in ids:
		var r: Rect2 = node.rect_of(id)
		check(apron.encloses(r), "%s is on the apron %s: %s" % [id, str(apron), str(r)])
	# each in the picture of its kind, at its size
	for id in ids:
		var k: Dictionary = sim.vehicles.kind_of(id)
		var s: Sprite2D = node.sprite_of(id)
		check(s != null and String(s.texture.resource_path).ends_with("%s.png" % String(k.art)), "%s is drawn as its kind: %s" % [id, k.art])
		var r: Rect2 = node.rect_of(id)
		near(r.size.y, float(k.h), 0.01, "%s is as long as the data says" % id)
		near(r.size.x, float(k.w), 0.01, "%s is as wide" % id)
	# one goes out with a party: not drawn; home again: it is where it was
	var place: int = node.spot_of(sedan)
	sim.vehicles.vehicle(sedan)["state"] = "out"
	node.update()
	check(not node.drawn_ids().has(sedan) and node.drawn_ids().has(pickup), "a vehicle that is out is not drawn")
	sim.vehicles.vehicle(pickup)["state"] = "out"
	node.update()
	eq(node.drawn_ids(), [], "none while both are out")
	sim.vehicles.vehicle(sedan)["state"] = "parked"
	node.update()
	eq(node.spot_of(sedan), place, "the sedan is back on its place")
	# lost: gone
	sim.vehicles.fleet.erase(sim.vehicles.vehicle(sedan))
	node.update()
	check(not node.drawn_ids().has(sedan), "a vehicle that is lost is gone")
	# more vehicles than places (a debug start: the game has no more than the pool holds): the rules give each a place of the pool
	# (they share), so each is drawn on a place that exists
	for kind in ["sedan", "van", "bus", "pickup", "sedan"]:
		sim.vehicles.add(kind)
	sim.vehicles.vehicle(pickup)["state"] = "parked"
	node.update()
	var cv = load("res://scripts/sim/convoy.gd")
	for id in node.drawn_ids():
		var where: int = node.spot_of(id)
		check(where >= 0 and where < int(cv.spots()), "%s is on a place of the pool: %d" % [id, where])
	node.free()
	g.world.free()
	# the classic start has none, whatever the fleet
	var classic := Helpers.make(7, 1)
	classic.sim.vehicles.add("sedan")
	var node2 := _node_of(classic.sim)
	node2.update()
	eq(node2.drawn_ids(), [], "the classic start draws no vehicles")
	node2.free()
	classic.world.free()


func test_a_click_finds_a_parked_vehicle_by_its_box_in_the_motor_pool() -> void:
	var g := _game()
	var sim = g.sim
	var node := _node_of(sim)
	var id := String(sim.vehicles.add("van").id)
	node.update()
	var r: Rect2 = node.rect_of(id)
	check(r.size.x > 1.0 and r.size.y > 1.0, "the van has a box: %s" % str(r))
	eq(node.vehicle_at(r.get_center()), id, "the middle of it is the vehicle")
	eq(node.vehicle_at(r.position + Vector2(0.1, 0.1)), id, "and its corner")
	eq(node.vehicle_at(r.position - Vector2(0.5, 0.5)), "", "beside it is not")
	eq(node.vehicle_at(Vector2(60.0, 9.0)), "", "the street elsewhere is not")
	node.free()
	g.world.free()


func test_a_click_on_a_parked_vehicle_opens_the_town_board_and_the_street_does_not() -> void:
	var main = Tut.start({"difficulty": 1, "seed": 7, "crew": 3}, 1280, 800)
	await Tut.frames(main, 3)
	check(main.sim.town.on, "(a settlement game)")
	var sedan := String(main.sim.vehicles.add("sedan").id)
	var bus := String(main.sim.vehicles.add("bus").id)
	await Tut.frames(main, 3)
	eq(main.parking_view.drawn_ids().size(), 2, "both are parked in the motor pool")
	var r: Rect2 = main.parking_view.rect_of(sedan)
	main._focus(r.get_center())
	main._apply_camera()
	# the street beside them: nothing
	main._click(main._tile_to_screen(Vector2(60.0, 9.0)), MOUSE_BUTTON_LEFT)
	await Tut.frames(main, 2)
	check(not main.hud.town_board_open(), "a click on the street opens nothing")
	main._click(main._tile_to_screen(r.get_center()), MOUSE_BUTTON_LEFT)
	await Tut.frames(main, 2)
	check(main.hud.town_board_open(), "a click on the sedan opens the Town Board")
	main.hud.scavenge_dialog.close()
	await Tut.frames(main, 2)
	check(not main.hud.town_board_open(), "(closed)")
	var rb: Rect2 = main.parking_view.rect_of(bus)
	main._focus(rb.get_center())
	main._apply_camera()
	main._click(main._tile_to_screen(rb.get_center()), MOUSE_BUTTON_LEFT)
	await Tut.frames(main, 2)
	check(main.hud.town_board_open(), "and on the bus")
	await Tut.leave(main)


func test_the_main_scene_has_the_parking_and_the_staging_options() -> void:
	var main = Tut.start({"difficulty": 1, "seed": 7, "crew": 3}, 1280, 800)
	await Tut.frames(main, 2)
	check(main.parking_view != null and main.parking_view.is_inside_tree(), "the motor pool's view is in the world")
	eq(main.sim.vehicles.fleet.size(), 0, "(no fleet at the start)")
	await Tut.leave(main)


# ------------------------------------------------------------------------ the tip --

func test_the_tip_for_a_vehicle_comes_once_the_colony_has_one() -> void:
	var tip := {}
	var ids: Array = []
	for h in Hints.load_hints():
		ids.append(String(h.id))
		if String(h.id) == "vehicle":
			tip = h
	check(not tip.is_empty(), "there is a tip about a vehicle")
	eq(tip.get("anchor", []), ["town"], "it points at the Town Board's button")
	eq(tip.get("start", {}).get("cond", ""), "has_vehicle", "and comes when the colony has a vehicle")
	check(String(tip.text).contains("half the time") and String(tip.text).contains("fuel") and String(tip.text).contains("gas stations") and String(tip.text).contains("Town Board"), "and says what a vehicle is: %s" % tip.text)
	check(ids[ids.size() - 1] == "build" and ids.find("vehicle") < ids.size() - 1, "it comes before the build tip (which stays last)")
	var settlement := _game()
	check(not Conditions.check(tip.start, settlement.sim, {}), "a settlement game with no vehicle: no tip")
	settlement.sim.vehicles.add("sedan")
	check(Conditions.check(tip.start, settlement.sim, {}), "with one: the tip")
	settlement.world.free()
	var classic := Helpers.make(5, 1)
	classic.sim.vehicles.add("sedan")
	check(not Conditions.check(tip.start, classic.sim, {}), "the classic start: never")
	classic.world.free()
	# on the real scene, the tips armed (the Town Board's own tip first: it is already seen)
	var main = Tut.start({"difficulty": 1, "seed": 7, "crew": 3}, 1280, 800)
	await Tut.frames(main, 3)
	Prefs.set_flag("hint_town", true)
	main.hints.armed = true
	main.sim.t = 60.0
	await Tut.frames(main, 40)
	eq(main.hints.shown_id(), "", "no vehicle, no tip")
	main.sim.vehicles.add("sedan")
	await Tut.frames(main, 40)
	eq(main.hints.shown_id(), "vehicle", "a vehicle is home: the tip is up")
	check(Prefs.flag("hint_vehicle"), "and is marked as shown")
	check(main.hints.target_rect.size.x > 0.0 and main.hints.target_rect == main.hud.anchor_rect("town"), "with the Town Board's button lit: %s" % str(main.hints.target_rect))
	main.hints.ok_button.pressed.emit()
	await Tut.frames(main, 4)
	main.sim.vehicles.add("van")
	await Tut.frames(main, 40 + 45 * 30)
	eq(main.hints.shown_id(), "", "once is all")
	Prefs.set_flag("hint_town", false)
	Prefs.set_flag("hint_vehicle", false)
	await Tut.leave(main)


func test_the_help_tells_what_the_town_board_is_for() -> void:
	var main = Tut.start({"difficulty": 1, "seed": 7, "crew": 3}, 1280, 800)
	await Tut.frames(main, 3)
	check(String(main.hud.help_g.tooltip_text).contains("vehicle") and String(main.hud.help_g.tooltip_text).contains("fuel"), "the help's G says what a vehicle is for: %s" % main.hud.help_g.tooltip_text)
	await Tut.leave(main)
	var classic = Tut.start({"difficulty": 1, "seed": 7}, 1280, 800)
	await Tut.frames(classic, 3)
	eq(String(classic.hud.help_g.tooltip_text), "", "the classic start says nothing of it")
	await Tut.leave(classic)


# ----------------------------------------------------------------- the page's look --

## The page with a vehicle chosen, a party out in another, the hospital picked: as full as it gets.
func _full(ctx: Dictionary) -> void:
	var sim = ctx.sim
	var sedan := _add(ctx, "sedan")
	var bus := _add(ctx, "bus")
	var van := _add(ctx, "van")
	sim.vehicles.fuel = 70.0
	sim.town.reveal("garage")
	var board = _board(ctx)
	board.select_place("hospital")
	board.choose_vehicle(bus)
	board.refresh(true)


func test_the_page_with_a_vehicle_fits_overlaps_nothing_and_has_no_small_words() -> void:
	var bt := BoardTests.new()
	var tt := TextTests.new()
	for size in SIZES:
		var ctx := _open(size[0], size[1])
		await _settle3()
		_full(ctx)
		for view in ["hospital", "garage", "houses", ""]:
			var board = _board(ctx)
			if view == "":
				board.site_id = ""
				board.refresh(true)
			else:
				board.select_place(view)
			await _settle3()
			eq(bt._misfits(ctx, size), [], "%d x %d, %s: the page fits" % [size[0], size[1], view if view != "" else "nothing chosen"])
			failures.append_array(bt.failures)
			bt.failures.clear()
			# the ride chips: inside the column, not on one another, whole words
			var parts := {}
			var col := Kit.rect(board.ride_box.get_parent())
			for id in board.ride_chips:
				var cr := Kit.rect(board.ride_chips[id].chip)
				parts["ride " + String(id)] = cr
				check(cr.size.x >= 100.0 and cr.size.y >= 50.0, "%d x %d: a ride chip has its size: %s" % [size[0], size[1], str(cr.size)])
				if cr.size != Vector2.ZERO:
					check(cr.position.x >= col.position.x - 0.5 and cr.end.x <= col.end.x + 0.5, "%d x %d: the ride chip %s is in the column %s" % [size[0], size[1], str(cr), str(col)])
			for id in board.chips:
				parts["person " + String(id)] = Kit.rect(board.chips[id].chip)
			eq(Kit.overlaps(parts), [], "%d x %d, %s: chips do not overlap" % [size[0], size[1], view])
			eq(tt._small_text(board), [], "%d x %d, %s: nothing under 12 px" % [size[0], size[1], view])
		Kit.free_all(ctx)


func test_the_ride_row_is_under_the_maps_key_on_a_wide_page_and_in_view_without_scrolling() -> void:
	# wide: under the key, in the column that has the room; the window is the real town's, everything known, a far place chosen
	var ctx := _real_board(1280, 800, ["all"])
	await _settle3()
	var board = _board(ctx)
	_add(ctx, "sedan")
	_add(ctx, "pickup")
	_add(ctx, "bus")
	ctx.sim.vehicles.fuel = 60.0
	board.select_place("hospital")
	await _settle3()
	await Kit.settle()
	eq(board.ride_box.get_parent(), board.map_col, "wide: the ride is in the map's column")
	check(board.map_col.get_children().find(board.ride_box) > board.map_col.get_children().find(board.legend), "under the key")
	var view := Kit.rect(board.scroll)
	for id in board.ride_chips:
		var r := Kit.rect(board.ride_chips[id].chip)
		check(r.size != Vector2.ZERO and view.grow(1.0).encloses(r), "1280 x 800: the chip of '%s' is in view without scrolling: %s in %s" % [id, str(r), str(view)])
	# narrow: under the people, in the party's box
	Kit.resize(ctx, 700, 700)
	await _settle3()
	await Kit.settle()
	eq(board.ride_box.get_parent(), board.party_box, "narrow: the ride is under the people")
	check(board.party_box.get_children().find(board.ride_box) > board.party_box.get_children().find(board.chip_flow), "after the people's chips")
	# and wide again
	Kit.resize(ctx, 1280, 800)
	await _settle3()
	eq(board.ride_box.get_parent(), board.map_col, "wide again: back under the key")
	Kit.free_all(ctx)


func test_every_word_of_the_ride_reads_on_its_chip_in_either_look() -> void:
	var tt := TextTests.new()
	for frames in [true, false]:
		Hud.use_frames = frames
		for size in [[1280, 800], [700, 700]]:
			var ctx := _open(size[0], size[1])
			await _settle3()
			_full(ctx)
			var board = _board(ctx)
			board.select_place("hospital")
			await _settle3()
			eq(tt._hard_to_read(board, Color.WHITE), [], "%s, %d: the page reads" % ["frames" if frames else "flat", size[0]])
			# the words of a chip are on a card or a gold card: dark enough on both
			for ink in [Hud.PAPER_INK, Hud.PAPER_INK2, TownBoard.WHY_INK]:
				for card in [Dialog.CARD, Dialog.CARD_CHOSEN]:
					check(tt.contrast(ink, card) >= tt.AA, "%s on %s: %.2f:1" % [str(ink), str(card), tt.contrast(ink, card)])
			Kit.free_all(ctx)
	Hud.use_frames = true


func test_random_play_with_vehicles_never_breaks_the_page() -> void:
	for seed_value in [1, 2, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var ctx := _open(1280, 800)
		var board = _board(ctx)
		var sim = ctx.sim
		_add(ctx, "sedan")
		_add(ctx, "pickup")
		_add(ctx, "bus")
		sim.vehicles.fuel = 50.0
		var places: Array = ["houses", "garage", "gas", "hospital", ""]
		for i in 60:
			if board == null or not board.is_open():
				break
			match rng.randi_range(0, 5):
				0:
					var id: String = places[rng.randi_range(0, places.size() - 1)]
					if id != "":
						board.select_place(id)
				1:
					var parked: Array = sim.vehicles.parked()
					board.choose_vehicle("" if parked.is_empty() or rng.randf() < 0.3 else String(parked[rng.randi_range(0, parked.size() - 1)].id))
				2:
					var free: Array = sim.scavenge.free_survivors()
					if not free.is_empty():
						board.toggle_member(free[rng.randi_range(0, free.size() - 1)])
				3:
					sim.vehicles.fuel = float(rng.randi_range(0, 70))
					board.refresh(true)
				4:
					if rng.randf() < 0.2 and not sim.vehicles.fleet.is_empty():
						sim.vehicles.fleet.erase(sim.vehicles.fleet[rng.randi_range(0, sim.vehicles.fleet.size() - 1)])
					board.refresh(true)
				5:
					var action: String = ["loot", "scout", "clear"][rng.randi_range(0, 2)]
					if rng.randf() < 0.3:
						board.act(action)
						if not board.is_open():
							ctx.hud.open_scavenge(null)
							board = _board(ctx)
			await Kit.settle()
		check(true, "seed %d: still standing" % seed_value)
		Kit.free_all(ctx)
