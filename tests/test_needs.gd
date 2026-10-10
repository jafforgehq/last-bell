extends "res://tests/case.gd"
## PH10, HER NEEDS (food and water for Ruth in the One House): the clocks that were already in the colony are hers too; the stores serve her only at the base, a meal missed outside is owed, out in the
## town she eats and drinks from her pack (one unit, the belt's keys), the first toast, the morning card's line, the needs board of the HUD (the stage table's `needs` row), the belt that works for
## food and drink, the saved keys, and the games that have no pack are fed as ever. (scripts/town/inv.gd, scripts/sim/supplies.gd, scripts/ui/needs_board.gd, assets/data/items.json `needs`.)

const Helpers := preload("res://tests/helpers.gd")
const Inventory := preload("res://scripts/sim/inventory.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const Supplies := preload("res://scripts/sim/supplies.gd")
const DawnTally := preload("res://scripts/ui/dawn_tally.gd")
const HudStage := preload("res://scripts/ui/hud_stage.gd")
const Prefs := preload("res://scripts/prefs.gd")


func _begin() -> void:
	Prefs.path = "user://prefs_test.cfg"
	Prefs.reset()


func _p(sim):
	return sim.avatar.player()


func _at(sim, v: Vector2) -> void:
	var p = _p(sim)
	p.x = v.x
	p.y = v.y
	p.moving = false
	p.path = []


func _events(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e.get("type", "")) == type:
			out.append(e)
	return out


## A town game with the data's start pack and stores, Ruth in the start house (not the base: nothing is claimed), the dead asleep.
func _pack_game() -> Dictionary:
	var g := Helpers.town_game(1, {"home": true})
	var sim = g.sim
	sim.field.pause_wake = true
	var start: Dictionary = OneHouse.data().start
	for k in start.stock:
		sim.stock[String(k)] = float(start.stock[k])
	sim.inv.begin(start.pack)
	sim.events.clear()
	return g


func _mid(d: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	for t in d.tiles:
		sum += Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
	return sum / float(d.tiles.size())


func _floor_near(sim, h: int, at: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for r in sim.houses.rooms_of(h):
		var rect: Rect2i = sim.houses.room(r).rect
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := Vector2(float(x) + 0.5, float(y) + 0.5)
				if c.distance_to(at) < best_d:
					best_d = c.distance_to(at)
					best = c
	return best


## The start house cleared, looked into, claimed; the pack on; Ruth at the claim spot (inside the base).
func _claimed_game() -> Dictionary:
	var g := Helpers.town_game(1, {"home": true})
	var sim = g.sim
	sim.field.pause_wake = true
	var h: int = sim.houses.start_house()
	for d in sim.houses.doors_of(h):
		_at(sim, _mid(d))
		Helpers.run(sim, 0.3)
	var f = sim.field
	for r in sim.houses.rooms_of(h):
		for i in f.n:
			if f.status[i] == f.DORMANT and sim.houses.room_at(f.xs[i], f.ys[i]) == r:
				f.status[i] = f.KILLED
	_at(sim, _floor_near(sim, h, sim.base.claim_spot()))
	Helpers.run(sim, 0.3)
	check(bool(sim.base.claim(h).ok), "the start house is claimed")
	var start: Dictionary = OneHouse.data().start
	sim.inv.begin(start.pack)
	sim.events.clear()
	g["house"] = h
	return g


## A spot well outside the base's compound (open ground of the town, whatever it is: only `at_base` matters), found by going away from the base.
func _far_from_base(sim) -> Vector2:
	var c: Vector2 = sim.base.center()
	for step in [40.0, 55.0, 70.0, 30.0]:
		for a in [0.0, 1.57, 3.14, 4.71]:
			var v: Vector2 = c + Vector2(cos(a), sin(a)) * step
			if v.x > 2.0 and v.y > 2.0 and not sim.base.at_base(v):
				return v
	return c + Vector2(45.0, 0.0)


# --------------------------------------------------------------------------- the data --

func test_a_bottle_is_one_cell_and_the_items_that_feed_are_whole() -> void:
	eq(Inventory.size_of("water_bottle"), Vector2i(1, 1), "a bottle is one cell (it was two)")
	eq(Inventory.size_of("water_jug"), Vector2i(2, 2), "a jug is four cells for four units")
	eq(Inventory.size_of("ration_pack"), Vector2i(1, 2), "a ration pack is two cells for three units")
	for id in ["canned_food", "ration_pack"]:
		eq(String(Inventory.item(id).use), "eat", "%s is eaten" % id)
	for id in ["water_bottle", "water_jug"]:
		eq(String(Inventory.item(id).use), "drink", "%s is drunk" % id)
	var needs: Dictionary = Inventory.config().get("needs", {})
	check(float(needs.get("eat_min_h", 0.0)) > 0.0 and float(needs.get("eat_min_h", 99.0)) < Supplies.HUNGRY_H, "she may eat from a few hours on, well before she is hungry")
	check(float(needs.get("drink_min_h", 0.0)) > 0.0 and float(needs.get("drink_min_h", 99.0)) < Supplies.THIRSTY_H, "and drink")
	var pk := Inventory.make_pack()
	var start: Dictionary = OneHouse.data().start
	for id in start.pack:
		Inventory.auto_add(pk, String(id), int(start.pack[id]))
	check(Inventory.free_cells(pk) >= 18, "the start pack leaves room: %d of 32 cells free" % Inventory.free_cells(pk))


# ----------------------------------------------------------------------- using the pack --

func test_a_meal_from_the_pack_is_one_unit_and_starts_the_clock_again() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	var c0: Dictionary = sim.inv.carried_totals()
	me.hunger_h = 20.0
	var r: Dictionary = sim.inv.use_item(sim.inv.first_use("eat"))
	check(bool(r.ok), "a tin is eaten (%s)" % str(r))
	near(me.hunger_h, 0.0, 0.0001, "the hunger clock starts again")
	var c1: Dictionary = sim.inv.carried_totals()
	eq(int(c1.food), int(c0.food) - 1, "one unit of food is gone")
	eq(int(c1.water), int(c0.water), "and nothing else")
	check(String(r.line).begins_with("Ate"), "it says what she did: %s" % String(r.line))
	eq(_events(sim, "ate").size(), 1, "the sim tells it")
	eq(int(sim.inv.stats.ate), 1, "and counts it")
	me.thirst_h = 16.0
	var d: Dictionary = sim.inv.use_item(sim.inv.first_use("drink"))
	check(bool(d.ok), "a bottle is drunk (%s)" % str(d))
	near(me.thirst_h, 0.0, 0.0001, "the thirst clock starts again")
	eq(int(sim.inv.carried_totals().water), int(c0.water) - 1, "one unit of water is gone")
	g.world.free()


func test_she_is_not_made_to_waste_food_when_she_is_not_hungry() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	var before: Dictionary = Inventory.to_dict(sim.inv.pack)
	me.hunger_h = 2.0
	me.thirst_h = 1.0
	var r: Dictionary = sim.inv.use_item(sim.inv.first_use("eat"))
	check(not bool(r.ok) and String(r.why).contains("not hungry"), "a few hours after a meal she is not hungry yet: %s" % str(r))
	var d: Dictionary = sim.inv.use_item(sim.inv.first_use("drink"))
	check(not bool(d.ok) and String(d.why).contains("not thirsty"), "nor thirsty: %s" % str(d))
	eq(Inventory.to_dict(sim.inv.pack), before, "and the pack is as it was")
	near(me.hunger_h, 2.0, 0.0001, "so is the clock")
	me.downed = true
	me.hunger_h = 20.0
	check(not bool(sim.inv.use_item(sim.inv.first_use("eat")).ok), "a person who is down does not eat")
	g.world.free()


func test_a_ration_pack_and_a_jug_are_broken_not_eaten_whole() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	sim.inv.pack = Inventory.make_pack()
	Inventory.auto_add(sim.inv.pack, "ration_pack", 1)
	Inventory.auto_add(sim.inv.pack, "water_jug", 1)
	me.hunger_h = 20.0
	me.thirst_h = 20.0
	eq(Inventory.units(sim.inv.pack, "food"), 3, "a ration pack is three units")
	check(bool(sim.inv.use_item(sim.inv.first_use("eat")).ok), "she eats from it")
	eq(Inventory.units(sim.inv.pack, "food"), 2, "two units are left")
	eq(Inventory.count_of(sim.inv.pack, "ration_pack"), 0, "the pack is gone")
	eq(Inventory.count_of(sim.inv.pack, "canned_food"), 2, "as two tins")
	check(bool(sim.inv.use_item(sim.inv.first_use("drink")).ok), "she drinks from the jug")
	eq(Inventory.units(sim.inv.pack, "water"), 3, "three units are left")
	eq(Inventory.count_of(sim.inv.pack, "water_jug"), 0, "the jug is gone")
	eq(Inventory.count_of(sim.inv.pack, "water_bottle"), 3, "as three bottles")
	eq(sim.inv.ground.size(), 0, "nothing was dropped: the room it left was the room they need")
	# the smallest item goes first: a tin before a ration pack
	Inventory.auto_add(sim.inv.pack, "ration_pack", 1)
	me.hunger_h = 20.0
	var first: int = sim.inv.first_use("eat")
	eq(String(sim.inv.pack.cells[first].item), "canned_food", "a tin is eaten before a ration pack")
	g.world.free()


func test_the_pieces_of_a_broken_jug_fit_where_the_jug_was() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	# a pack that is only the jug's four cells: the three bottles that are left take the room it gave up
	sim.inv.pack = Inventory.make_grid(2, 2)
	Inventory.place(sim.inv.pack, "water_jug", 1, 0, 0)
	me.thirst_h = 20.0
	check(bool(sim.inv.use_item(0).ok), "she drinks")
	eq(Inventory.units(sim.inv.pack, "water"), 3, "three units are in the pack")
	eq(sim.inv.ground.size(), 0, "none of them on the ground")
	g.world.free()


# ------------------------------------------------------------------------ the base serves --

func test_the_stores_do_not_follow_her_out_of_the_base() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	me.hunger_h = 7.0
	me.thirst_h = 7.0
	var food0: float = sim.stock.food
	var water0: float = sim.stock.water
	Helpers.run_to_hour(sim, 13.2)
	check(me.hunger_h > 7.0 and me.thirst_h > 7.0, "she is out: the noon meal did not reach her (hunger %.1f, thirst %.1f)" % [me.hunger_h, me.thirst_h])
	near(float(sim.stock.food), food0, 0.0001, "and the stores' food was not touched")
	near(float(sim.stock.water), water0, 0.0001, "nor the water")
	check(sim.inv.owed_meal, "the meal is owed")
	g.world.free()


func test_at_the_base_she_eats_at_the_table_like_the_crew() -> void:
	var g := _claimed_game()
	var sim = g.sim
	var me = _p(sim)
	check(sim.base.at_base(me), "she is in the base")
	me.hunger_h = 9.0
	me.thirst_h = 9.0
	sim.stock.food = 4.0
	sim.stock.water = 6.0
	Helpers.run_to_hour(sim, 13.2)
	check(me.hunger_h < 1.0 and me.thirst_h < 1.0, "the noon meal fed her at home (hunger %.2f, thirst %.2f)" % [me.hunger_h, me.thirst_h])
	near(float(sim.stock.food), 4.0 - Supplies.FOOD_PER_MEAL, 0.02, "a third of a ration from the stores")
	near(float(sim.stock.water), 6.0 - Supplies.WATER_PER_MEAL, 0.02, "and half a bottle")
	check(not sim.inv.owed_meal, "nothing is owed")
	g.world.free()


func test_a_meal_that_came_up_outside_is_served_at_the_door() -> void:
	var g := _claimed_game()
	var sim = g.sim
	var me = _p(sim)
	sim.stock.food = 4.0
	sim.stock.water = 6.0
	me.hunger_h = 10.0
	me.thirst_h = 10.0
	Helpers.run_to_hour(sim, 12.8)
	_at(sim, _far_from_base(sim))
	check(not sim.base.at_base(me), "she is away from the base")
	Helpers.run_to_hour(sim, 15.0)
	check(sim.inv.owed_meal and me.hunger_h > 12.0, "the noon meal passed her by (owed, hunger %.1f)" % me.hunger_h)
	near(float(sim.stock.food), 4.0, 0.0001, "nothing was taken from the stores")
	_at(sim, _floor_near(sim, g.house, sim.base.claim_spot()))
	Helpers.run(sim, 0.5)
	check(not sim.inv.owed_meal, "at the door the base serves it")
	check(me.hunger_h < 0.5 and me.thirst_h < 0.5, "she is fed (hunger %.2f, thirst %.2f)" % [me.hunger_h, me.thirst_h])
	near(float(sim.stock.food), 4.0 - Supplies.FOOD_PER_MEAL, 0.02, "one share, not one for each meal she missed")
	g.world.free()


func test_when_the_stores_are_empty_the_table_is_set_from_her_pack() -> void:
	var g := _claimed_game()
	var sim = g.sim
	var me = _p(sim)
	sim.stock.food = 0.0
	sim.stock.water = 0.0
	me.hunger_h = 12.0
	me.thirst_h = 12.0
	var c0: Dictionary = sim.inv.carried_totals()
	Helpers.run_to_hour(sim, 13.2)
	check(me.hunger_h < 1.0 and me.thirst_h < 1.0, "at home with empty stores she is fed from her pack")
	var c1: Dictionary = sim.inv.carried_totals()
	check(int(c0.food) - int(c1.food) <= 1 and int(c0.water) - int(c1.water) <= 1, "at most a unit each: a meal is a third of a ration and half a bottle")
	g.world.free()


# ---------------------------------------------------------------------------- what it costs --

func test_day_one_is_mild_and_the_penalties_are_the_old_clocks() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	near(me.hunger_h, 0.0, 0.0001, "the run begins fed (the worst case follows: an avatar that is never at the base and never eats)")
	var hp0: float = me.hp
	Helpers.run_to_hour(sim, 20.9)
	check(sim.supplies.perf(me) >= 0.999, "at 20:54, 14 hours on, she shoots as well as ever (perf %.2f)" % sim.supplies.perf(me))
	check(float(me.thirst_h) < Supplies.THIRSTY_H, "not thirsty yet (%.1f hours)" % float(me.thirst_h))
	Helpers.run_to_hour(sim, 21.4)
	check(float(me.thirst_h) >= Supplies.THIRSTY_H and sim.supplies.perf(me) < 1.0, "past 21:00 she is thirsty and a fifth weaker (%.2f)" % sim.supplies.perf(me))
	near(float(me.hp), hp0, 0.001, "but loses no health")
	check(float(me.hunger_h) < Supplies.HUNGRY_H, "and is not hungry (%.1f hours): the first day cannot starve her" % float(me.hunger_h))
	var st: Array = sim.supplies.status_of(me)
	check(st.size() == 1 and String(st[0].tip) == "Thirsty", "the card says thirsty only")
	Helpers.run_to_hour(sim, 8.0)
	check(float(me.thirst_h) >= Supplies.PARCHED_H, "an hour after the next dawn she is parched (%.1f hours)" % float(me.thirst_h))
	check(float(me.hp) < hp0 and float(me.hp) > hp0 - 3.0, "and has lost only an hour of health or so: %.1f of %.1f" % [float(me.hp), hp0])
	g.world.free()


func test_the_arithmetic_of_the_first_attack_night_for_an_avatar_that_does_nothing() -> void:
	# the lines, from the constants (the lab's idle avatar is at home at its meals: this is the worst case, never at home and never eating)
	var from_start := 7.0    # (the run begins at 07:00 on day 1)
	var thirsty_at := from_start + Supplies.THIRSTY_H
	var hungry_at := from_start + Supplies.HUNGRY_H
	var parched_at := from_start + Supplies.PARCHED_H
	var starving_at := from_start + Supplies.STARVING_H
	check(thirsty_at >= 19.0, "thirst begins at %.0f:00 on day 1, after the first dusk's bell at 19:00 at the earliest" % thirsty_at)
	check(hungry_at - 24.0 >= 0.0 and hungry_at > 24.0, "hunger begins on the night of day 1 to 2, at %.0f:00" % (hungry_at - 24.0))
	check(parched_at >= 31.0 and starving_at >= 43.0, "health is lost from day 2's morning (%.0f:00) at the earliest" % (parched_at - 24.0))
	var health_hours := 100.0 / Supplies.STARVE_LOSS_PER_H
	check(parched_at + health_hours > 24.0 * 5.0, "and it takes %.0f hours of it to kill her: not before day 5" % health_hours)


# -------------------------------------------------------------------------- the toast --

func test_the_first_hungry_and_the_first_thirsty_are_told_once_with_the_key() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	me.hunger_h = Supplies.HUNGRY_H + 0.1
	Helpers.run(sim, 0.2)
	var t: Array = _events(sim, "inv_toast")
	eq(t.size(), 1, "one toast")
	if t.size() == 1:
		var text := String(t[0].text)
		check(text.begins_with("Hungry") and text.contains("press 2") and text.contains("eat"), "it names the belt key of the tin: %s" % text)
		eq(String(t[0].level), "warn", "a warning")
	Helpers.run(sim, 2.0)
	eq(_events(sim, "inv_toast").size(), 1, "and it is not repeated")
	me.thirst_h = Supplies.THIRSTY_H + 0.1
	Helpers.run(sim, 0.2)
	t = _events(sim, "inv_toast")
	eq(t.size(), 2, "thirst has its own, once")
	if t.size() == 2:
		check(String(t[1].text).begins_with("Thirsty") and String(t[1].text).contains("press 3"), "naming the bottle's key: %s" % String(t[1].text))
	# without food in the pack it says what to do instead
	var h := _pack_game()
	var s2 = h.sim
	s2.inv.pack = Inventory.make_pack()
	_p(s2).hunger_h = Supplies.HUNGRY_H + 0.1
	Helpers.run(s2, 0.2)
	var t2: Array = _events(s2, "inv_toast")
	check(t2.size() == 1 and String(t2[0].text).contains("nothing to eat"), "with nothing to eat it says so and where food is: %s" % (String(t2[0].text) if t2.size() > 0 else "no toast"))
	h.world.free()
	g.world.free()


func test_what_she_went_without_is_kept_for_the_morning_card() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	var w0: Dictionary = sim.inv.take_went()
	check(not bool(w0.hungry) and not bool(w0.thirsty), "a fed run went without nothing")
	eq(DawnTally.went_text(w0), "", "and the card has no line")
	me.hunger_h = Supplies.HUNGRY_H + 1.0
	Helpers.run(sim, 0.2)
	var w1: Dictionary = sim.inv.take_went()
	check(bool(w1.hungry) and not bool(w1.thirsty), "she went hungry")
	eq(DawnTally.went_text(w1), "You went hungry yesterday.", "the card's line")
	check(not bool(sim.inv.take_went().hungry), "and it is forgotten once told")
	eq(DawnTally.went_text({"hungry": true, "thirsty": true}), "You went hungry and thirsty yesterday.", "both")
	check(DawnTally.went_text({"thirsty": true, "parched": true}).contains("cost you health"), "and when it cost health, it says so")
	g.world.free()


# ---------------------------------------------------------------------------------- saves --

func test_the_needs_are_saved_with_the_run_and_an_old_save_loads_without_them() -> void:
	var g := _pack_game()
	var sim = g.sim
	var me = _p(sim)
	me.hunger_h = 19.0
	Helpers.run(sim, 0.2)
	sim.inv.on_meal_missed()
	check(bool(sim.inv.told.hungry) and bool(sim.inv.went.hungry), "she was told and went hungry")
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	check(data.modules.inv.has("needs"), "the module has the needs")
	var f := Helpers.town_game(1, {"home": true})
	check(SaveGame.apply(f.sim, data), "the save is read")
	var inv2 = f.sim.inv
	check(inv2.owed_meal and bool(inv2.told.hungry) and bool(inv2.went.hungry), "what was owed, told and gone without is back")
	near(float(_p(f.sim).hunger_h), float(me.hunger_h), 0.01, "so is her hunger clock")
	# a save from before the needs: no key; it loads, nothing is owed, nothing told
	var old: Dictionary = JSON.parse_string(JSON.stringify(data))
	(old.modules.inv as Dictionary).erase("needs")
	var h := Helpers.town_game(1, {"home": true})
	check(SaveGame.apply(h.sim, old), "a save without the needs is read")
	check(not h.sim.inv.owed_meal and not bool(h.sim.inv.told.hungry), "nothing owed, nothing told")
	eq(SaveGame.town_compat(data), "", "no version bump: the town of the save is this build's")
	h.world.free()
	f.world.free()
	g.world.free()


func test_no_other_game_changes_how_it_feeds() -> void:
	# a bare town game (no pack): the stores serve her wherever she is, as they always did
	var g := Helpers.town_game(1, {"home": true})
	var sim = g.sim
	var me = _p(sim)
	check(not sim.inv.active(), "no pack")
	sim.field.pause_wake = true
	sim.stock.food = 5.0
	sim.stock.water = 5.0
	me.hunger_h = 12.0
	me.thirst_h = 12.0
	Helpers.run_to_hour(sim, 13.2)
	check(me.hunger_h < 1.0 and me.thirst_h < 1.0, "fed at noon, anywhere")
	var n: Dictionary = sim.inv.needs()
	eq(String(n.hunger.state), "fed", "the needs of a run with no pack are fed, always")
	g.world.free()
	var school := Helpers.make(3, 1)
	var s = school.sim
	s.stock.food = 20.0
	s.stock.water = 20.0
	s.people[0].hunger_h = 12.0
	Helpers.run_to_hour(s, 13.2)
	check(s.people[0].hunger_h < 1.0, "the school's crew are fed as ever")
	school.world.free()


# --------------------------------------------------------------------- the stage table row --

func test_the_needs_row_of_the_stage_table() -> void:
	check(HudStage.PARTS.has("needs"), "the board is a part of the stage")
	for phase in HudStage.PHASES:
		eq(HudStage.form_of("needs", phase, false), "when", "%s: only when she is hungry or thirsty" % phase)
		eq(HudStage.form_of("needs", phase, true), "off", "%s: not in a fight" % phase)
		eq(HudStage.form_of("needs", phase, false, false, true), "full", "%s: the full HUD has the meters always" % phase)
		eq(HudStage.form_of("needs", phase, false, true, false), "off", "%s: H puts it away" % phase)
	check(HudStage.OWNED.has("needs") and HudStage.RETURN.has("needs"), "it has its place in the return after a fight")


# ------------------------------------------------------------------------ a real run: the HUD --

const Hud := preload("res://scripts/ui/hud.gd")


func _boot(width: int = 1280, height: int = 720, reduce_motion: bool = false) -> Dictionary:
	var win: Window = Engine.get_main_loop().root
	var saved := {"size": win.size, "position": win.position, "mode": win.content_scale_mode, "aspect": win.content_scale_aspect, "scale_size": win.content_scale_size}
	win.size = Vector2i(width, height)
	Prefs.reset()
	if reduce_motion:
		Prefs.set_value("ui", "reduce_motion", true)
	Engine.set_meta("run", {"difficulty": 1, "seed": 7, "town": true, "avatar": true, "town_opts": {"blocks": 2}})
	var main = load("res://scenes/main.tscn").instantiate()
	win.add_child(main)
	main.set_process(false)
	main.sim.zombies.clear()
	if main.sim.get("field") != null:
		main.sim.field.pause_wake = true    # (the dead of the street stay asleep: a fight would put the boards away)
	return {"main": main, "win": win, "saved": saved, "stage": HudStage.of(main), "hud": main.hud}


func _end(g: Dictionary) -> void:
	g.main.queue_free()
	await Engine.get_main_loop().process_frame
	var win: Window = g.win
	win.content_scale_mode = g.saved.mode
	win.content_scale_aspect = g.saved.aspect
	win.content_scale_size = g.saved.scale_size
	win.size = g.saved.size
	win.position = g.saved.position
	Prefs.reset()


func _step(g: Dictionary, n: int, dt: float = 0.1) -> void:
	for i in n:
		g.main._process(dt)
		g.hud.update_hud(g.main.sim, g.main.speed, true, 0)


func test_the_board_is_there_only_while_she_is_hungry_or_thirsty() -> void:
	var g := _boot()
	var hud = g.hud
	var sim = g.main.sim
	g.main.speed = 0
	_step(g, 6)
	check(hud.needs_panel != null, "the town's HUD has the board")
	check(sim.inv.active(), "the run has a pack")
	check(not hud.needs_panel.visible, "fed: nothing on the screen")
	var me = sim.avatar.player()
	me.hunger_h = Supplies.HUNGRY_H + 1.0
	_step(g, 6)
	check(hud.needs_panel.visible and hud.needs_panel.modulate.a > 0.99, "hungry: the board is there, whole")
	var row = hud.get("_needs_board").rows
	check((row.hunger.box as Control).visible and not (row.thirst.box as Control).visible, "with the hunger line only")
	eq((row.hunger.word as Label).text, "Hungry", "which says hungry")
	check((row.hunger.hint as Label).text.begins_with("2"), "and the key to press: %s" % (row.hunger.hint as Label).text)
	me.thirst_h = Supplies.PARCHED_H + 1.0
	_step(g, 6)
	check((row.thirst.box as Control).visible and (row.thirst.word as Label).text == "Parched", "parched has its line")
	check(String(hud.needs_panel.tooltip_text).contains("costing you health"), "and its tooltip says what it costs")
	me.hunger_h = 0.0
	me.thirst_h = 0.0
	_step(g, 8)
	check(not hud.needs_panel.visible, "fed again: the board goes")
	await _end(g)


func test_the_board_has_a_shape_as_well_as_a_colour_and_the_full_hud_shows_both_meters() -> void:
	var g := _boot()
	var hud = g.hud
	var sim = g.main.sim
	g.main.speed = 0
	Prefs.set_value("ui", "colour_blind", true)
	var me = sim.avatar.player()
	me.hunger_h = Supplies.HUNGRY_H + 1.0
	me.thirst_h = Supplies.PARCHED_H + 1.0
	_step(g, 8)
	var rows = hud.get("_needs_board").rows
	check(rows.hunger.mark.visible and rows.hunger.mark.kind == "triangle", "hungry is a triangle")
	check(rows.thirst.mark.visible and rows.thirst.mark.kind == "diamond", "parched is a diamond")
	Prefs.set_value("ui", "colour_blind", false)
	_step(g, 8)
	check(not rows.hunger.mark.visible, "no shapes with the setting off: the word and the icon carry it")
	me.hunger_h = 0.0
	me.thirst_h = 0.0
	HudStage.set_mode("full")
	_step(g, 12)
	check(hud.needs_panel.visible, "the Full HUD has the board while she is fed")
	check((rows.hunger.box as Control).visible and (rows.thirst.box as Control).visible, "with both meters")
	eq((rows.hunger.word as Label).text, "Hunger", "named, not 'fed'")
	await _end(g)


func test_the_belt_keys_eat_and_drink_and_the_slot_is_marked_when_she_needs_it() -> void:
	var g := _boot()
	var sim = g.main.sim
	var me = sim.avatar.player()
	g.main.speed = 0
	_step(g, 4)
	var ui = g.main.town.part("inv_ui")
	check(ui != null, "the town has the inventory controller")
	if ui == null:
		await _end(g)
		return
	ui.open_pack()
	_step(g, 4)
	var doll = ui.pack_win.doll
	check(String(doll.quick[1].state) == "ready" and not bool(doll.quick[1].due), "the tin's slot is lit, not marked: she is fed")
	me.hunger_h = Supplies.HUNGRY_H + 2.0
	_step(g, 6)
	check(bool(doll.quick[1].due) and not bool(doll.quick[2].due), "hungry: the tin's slot is marked, the bottle's is not")
	check(doll.quick_tip(1).contains("You need it now"), "and its tooltip says so")
	var cans: int = Inventory.count_of(sim.inv.pack, "canned_food")
	var ev := InputEventKey.new()
	ev.keycode = KEY_2
	ev.physical_keycode = KEY_2
	ev.pressed = true
	check(ui.on_key(ev), "the key 2 is the belt's")
	eq(Inventory.count_of(sim.inv.pack, "canned_food"), cans - 1, "a tin was eaten")
	near(float(me.hunger_h), 0.0, 0.001, "she is fed")
	_step(g, 6)
	check(not bool(doll.quick[1].due), "the mark is gone")
	await _end(g)


func test_the_morning_card_says_she_went_hungry() -> void:
	var g := _boot()
	var main = g.main
	var sim = main.sim
	var dt = main.town.part("dawn_tally")
	check(dt != null, "the town has the morning card")
	if dt == null:
		await _end(g)
		return
	main.speed = 0
	var me = sim.avatar.player()
	me.hunger_h = Supplies.HUNGRY_H + 3.0
	Helpers.run(sim, 0.3)    # (the rules step: the game is paused, and it is the rules that keep the record)
	var t: Dictionary = dt._make_tally(2, true)
	check(bool((t.went as Dictionary).get("hungry", false)), "the tally has it")
	var rows: Array = dt.rows_for(t, true)
	var found := false
	for r in rows:
		if String(r[1]) == "You went hungry yesterday.":
			found = true
	check(found, "the compact card has the line: %s" % str(rows))
	var t2: Dictionary = dt._make_tally(3, true)
	var rows2: Array = dt.rows_for(t2, false)
	for r in rows2:
		check(not String(r[1]).begins_with("You went"), "and the next morning, fed, it does not")
	await _end(g)


func test_reduce_motion_leaves_out_the_pulse_and_makes_the_board_come_at_once() -> void:
	Prefs.reset()
	var g := _boot()
	var hud = g.hud
	var sim = g.main.sim
	g.main.speed = 0
	var board = hud.get("_needs_board")
	var me = sim.avatar.player()
	me.hunger_h = Supplies.HUNGRY_H + 1.0
	_step(g, 3)
	check(board._pulse != null, "with motion, a need that begins pulses the board once")
	await _end(g)
	var h := _boot(1280, 720, true)
	var hud2 = h.hud
	h.main.speed = 0
	var board2 = hud2.get("_needs_board")
	h.main.sim.avatar.player().hunger_h = Supplies.HUNGRY_H + 1.0
	_step(h, 2)
	check(board2._pulse == null, "under Reduce motion there is no pulse at all")
	check(hud2.needs_panel.visible and hud2.needs_panel.modulate.a > 0.99, "and the board is whole at once, with no fade in")
	await _end(h)
	Prefs.reset()
