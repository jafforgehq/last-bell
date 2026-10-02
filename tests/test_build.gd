extends "res://tests/case.gd"
## Buildings (round 6): the plots and the catalogue, ordering and cancelling, the builders working a
## site, what a standing building changes (the stations and their seats, the salvage station's scrap,
## the numbers the other modules read), footprints, demolishing, saves. What each building's effect
## does to the other modules is tested in test_building_effects.gd.

const Helpers := preload("res://tests/helpers.gd")
const Build := preload("res://scripts/sim/build.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _person(sim, first: String):
	for p in sim.people:
		if p.first == first:
			return p
	return null


## A quiet game at `hour` with plenty of scrap and the bench and the beds idle.
func _game(hour: float = 8.0, seed_value: int = 71) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.stock.scrap = 100.0
	Helpers.idle_stores(sim)
	sim.events.clear()
	return g


## Puts a building on a plot at once, as if it had been built.
func _stand(sim, plot_id: String, building_id: String) -> void:
	var pl: Dictionary = sim.build.plot(plot_id)
	pl.building = building_id
	sim.build.version += 1


func _wear(sim, id: int, share: float):
	for s in sim.segments:
		if s.id == id:
			s.hp = s.max_hp * share
			sim._segment_state(s)
			return s
	return null


# ------------------------------------------------------------------- the data --

func test_the_plots_and_the_catalogue_are_sound() -> void:
	var g := _game()
	var sim = g.sim
	var ids := {}
	eq(sim.build.plots().size(), 12, "twelve plots")
	for pl in sim.build.plots():
		check(not ids.has(pl.id), "plot ids are unique: %s" % pl.id)
		ids[pl.id] = true
		check(pl.kind in ["yard", "wall"], "%s has a kind" % pl.id)
		check(pl.size.x > 0.0 and pl.size.y > 0.0, "%s has a size" % pl.id)
		eq(pl.building, "", "%s starts empty" % pl.id)
		check(pl.site.is_empty(), "and with no site")
	eq(sim.build.catalogue().size(), 7, "seven buildings")
	var seen := {}
	for b in sim.build.catalogue():
		check(not seen.has(b.id), "building ids are unique: %s" % b.id)
		seen[b.id] = true
		check(b.scrap > 0 and b.work > 0.0 and b.max >= 1, "%s has a cost, a work and a count" % b.id)
		for k in b.plots:
			check(k in ["yard", "wall"], "%s names real plot kinds" % b.id)
		check(String(b.name) != "" and String(b.blurb) != "", "%s has words" % b.id)
	for b in sim.build.catalogue():
		var r := String(b.requires)
		check(r == "" or seen.has(r), "%s requires a building that exists" % b.id)
	for st in sim.jobs.stations():
		var r2 := String(st.get("requires", ""))
		check(r2 == "" or seen.has(r2), "%s needs a building that exists" % st.id)
	g.world.free()


func test_plot_at_finds_the_lot_a_point_is_in() -> void:
	var g := _game()
	var sim = g.sim
	for pl in sim.build.plots():
		var half: Vector2 = Vector2(pl.size) / 2.0
		eq(sim.build.plot_at(Vector2(pl.pos)), String(pl.id), "the middle of %s" % pl.id)
		eq(sim.build.plot_at(Vector2(pl.pos) + half - Vector2(0.1, 0.1)), String(pl.id), "near its corner")
	eq(sim.build.plot_at(Vector2(1.0, 1.0)), "", "outside every lot")
	g.world.free()


# ------------------------------------------------------------------- ordering --

func test_ordering_pays_the_scrap_and_puts_a_site_on_the_plot() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.build.order("court_north", "workshop"), "it is ordered")
	near(float(sim.stock.scrap), 70.0, 1e-9, "thirty scrap are paid")
	var pl: Dictionary = sim.build.plot("court_north")
	eq(pl.site.building, "workshop", "a site stands on the plot")
	eq(pl.building, "", "and no building yet")
	near(sim.build.progress_of("court_north"), 0.0, 1e-9, "no work done")
	eq(sim.build.active_site().id, "court_north", "it is the one being built")
	var said := false
	for e in sim.events:
		said = said or (e.type == "site" and e.plot == "court_north" and e.building == "workshop")
	check(said, "and the crew is told")
	g.world.free()


func test_an_order_never_leaves_the_scrap_below_nothing() -> void:
	var g := _game()
	var sim = g.sim
	sim.stock.scrap = 18.0 - 1.0e-12    # a hair short through float noise: close enough to pay
	check(sim.build.order("junk_corner", "salvage_bench"), "it is ordered")
	check(float(sim.stock.scrap) >= 0.0, "and the stock is not left below nothing: %s" % str(sim.stock.scrap))
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var other := _game(8.0, 99)
	check(SaveGame.apply(other.sim, d), "so the game still saves and loads")
	g.world.free()
	other.world.free()


func test_what_cannot_be_ordered_says_why() -> void:
	var g := _game()
	var sim = g.sim
	eq(sim.build.why_not("nowhere", "workshop"), "there is no such plot", "no such plot")
	eq(sim.build.why_not("court_north", "castle"), "there is no such building", "no such building")
	eq(sim.build.why_not("court_north", "workshop"), "", "a workshop can go on the court")
	eq(sim.build.why_not("court_north", "watchtower"), "it cannot stand on the yard", "a watchtower is for the wall")
	eq(sim.build.why_not("west_wall", "workshop"), "it cannot stand on the wall", "and a workshop is not")
	eq(sim.build.why_not("west_wall", "floodlights"), "", "floodlights can go on either")
	sim.stock.scrap = 5.0
	eq(sim.build.why_not("court_north", "workshop"), "it needs 30 scrap", "and the scrap must be there")
	check(not sim.build.order("court_north", "workshop"), "so it is not ordered")
	near(float(sim.stock.scrap), 5.0, 1e-9, "and nothing is paid")
	sim.stock.scrap = 200.0
	check(sim.build.order("court_north", "workshop"), "with the scrap it is")
	eq(sim.build.why_not("court_north", "greenhouse"), "something is already going up here", "a plot holds one thing")
	eq(sim.build.why_not("court_south", "workshop"), "there is already one", "one workshop is all there is")
	check(sim.build.order("court_south", "bunk_house"), "a bunk house")
	check(sim.build.order("east_lot", "bunk_house"), "and a second")
	eq(sim.build.why_not("south_lot", "bunk_house"), "there is already the most (2)", "and no third")
	g.world.free()


# ---------------------------------------------------------------- construction --

func test_the_builders_walk_to_the_site_and_build_it_by_day() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.build.order("junk_corner", "salvage_bench"), "the salvage bench is ordered")
	var walt = _person(sim, "Walt")
	eq(sim.jobs.job_of(walt), "builders", "Walt is on the Builders job")
	Helpers.run(sim, 30.0)
	var spot: Vector2 = sim.jobs.seat_pos(walt)
	check(Vector2(walt.x, walt.y).distance_to(spot) < 0.7, "he stands at the site: (%.1f, %.1f) for (%.1f, %.1f)" % [walt.x, walt.y, spot.x, spot.y])
	check(Vector2(spot).distance_to(sim.build.plot("junk_corner").work) < 0.01, "the site's work spot is where the lot says")
	check(sim.build.progress_of("junk_corner") > 0.0, "and the work has begun: %.2f" % sim.build.progress_of("junk_corner"))
	eq(String(walt.activity), "Building the salvage bench", "he says what he is doing")
	var guard := 0
	while not sim.build.built("salvage_bench") and guard < 400:
		Helpers.run(sim, 1.0)
		guard += 1
	check(sim.build.built("salvage_bench"), "it is built (after %d seconds)" % guard)
	var pl: Dictionary = sim.build.plot("junk_corner")
	eq(pl.building, "salvage_bench", "on the plot")
	check(pl.site.is_empty(), "and the site is gone")
	check(sim.alerts.has("built-junk_corner"), "the crew is told")
	var said := false
	for e in sim.events:
		said = said or (e.type == "built" and e.plot == "junk_corner")
	check(said, "with an event")
	g.world.free()


func test_the_hammer_rings_while_the_site_is_worked() -> void:
	var g := _game()
	var sim = g.sim
	sim.build.order("junk_corner", "salvage_bench")
	Helpers.run(sim, 30.0)
	sim.events.clear()
	Helpers.run(sim, 6.0)
	var rings := 0
	for e in sim.events:
		if e.type == "hammer":
			rings += 1
			check(Vector2(e.x, e.y).distance_to(sim.build.plot("junk_corner").work) < 2.5, "at the site")
	check(rings >= 5, "about every 0.6 seconds: %d rings in six seconds" % rings)
	g.world.free()


func test_the_work_goes_by_the_hours_and_the_hands() -> void:
	var one := _game()
	var two := _game()
	one.sim.build.order("junk_corner", "salvage_bench")
	two.sim.build.order("junk_corner", "salvage_bench")
	check(two.sim.jobs.assign(_person(two.sim, "Hector"), "builders"), "Hector joins the crew in the second game")
	Helpers.run(one.sim, 60.0)
	Helpers.run(two.sim, 60.0)
	var a: float = one.sim.build.plot("junk_corner").site.progress
	var b: float = two.sim.build.plot("junk_corner").site.progress
	check(a > 0.0 and b > a * 1.5, "two builders do much more than one: %.2f against %.2f" % [b, a])
	one.world.free()
	two.world.free()


func test_a_better_builder_is_worth_more() -> void:
	var g := _game()
	var sim = g.sim
	var dez = _person(sim, "Dez")
	var walt = _person(sim, "Walt")
	var dez_rate: float = sim.build.rate(dez)
	var walt_rate: float = sim.build.rate(walt)
	check(dez_rate > walt_rate * 1.5, "Dez (Building %d) builds %.2f an hour and Walt (%d) %.2f" % [dez.skills.Building, dez_rate, walt.skills.Building, walt_rate])
	near(walt_rate, (1.0 + 0.12 * float(walt.skills.Building)) * sim.perf(walt) * sim.traits.mult(walt, "repair"), 1e-9, "the rate is the base plus a bit for each point, with how well they are")
	g.world.free()


func test_nothing_is_built_at_night() -> void:
	var g := _game(21.0)
	var sim = g.sim
	sim.build.order("junk_corner", "salvage_bench")
	Helpers.run(sim, 60.0)
	near(sim.build.progress_of("junk_corner"), 0.0, 1e-9, "the crew holds the posts and the site waits")
	g.world.free()


func test_a_badly_worn_wall_comes_before_the_site() -> void:
	var g := _game()
	var sim = g.sim
	_wear(sim, 4, 0.3)
	sim.build.order("junk_corner", "salvage_bench")
	var walt = _person(sim, "Walt")
	Helpers.run(sim, 2.0)
	check(walt.repair != null, "Walt is sent to mend the wall first")
	near(sim.build.progress_of("junk_corner"), 0.0, 1e-9, "and the site waits for him")
	Helpers.run(sim, 90.0)
	check(sim.build.progress_of("junk_corner") > 0.0 or sim.build.built("salvage_bench"), "once the wall is mended he builds")
	g.world.free()


func test_sites_are_built_in_the_order_they_were_ordered() -> void:
	var g := _game()
	var sim = g.sim
	sim.build.order("junk_corner", "salvage_bench")
	sim.build.order("court_north", "greenhouse")
	eq(sim.build.active_site().id, "junk_corner", "the first order is the one being built")
	sim.build.cancel("junk_corner")
	eq(sim.build.active_site().id, "court_north", "and when it goes the next one is")
	sim.build.cancel("court_north")
	eq(sim.build.active_site(), {}, "with none left there is no active site")
	g.world.free()


# ----------------------------------------------------------- cancel and demolish --

func test_a_cancelled_site_gives_back_what_it_can() -> void:
	var g := _game()
	var sim = g.sim
	sim.build.order("court_north", "workshop")
	check(sim.build.cancel("court_north"), "it is cancelled")
	near(float(sim.stock.scrap), 100.0, 1e-9, "with no work done all the scrap is back")
	check(sim.build.plot("court_north").site.is_empty(), "and the plot is free")
	sim.build.order("court_north", "workshop")
	sim.build.plot("court_north").site.progress = 4.0
	sim.build.cancel("court_north")
	near(float(sim.stock.scrap), 85.0, 1e-9, "with work done half comes back (70 + 15)")
	check(not sim.build.cancel("court_north"), "and a plot with no site cannot be cancelled")
	g.world.free()


func test_a_demolished_building_gives_back_half_and_its_effects_end() -> void:
	var g := _game()
	var sim = g.sim
	_stand(sim, "court_north", "workshop")
	near(sim.build.factor("craft_mult"), 1.25, 1e-9, "the workshop stands")
	var v: int = sim.build.version
	check(sim.build.demolish("court_north"), "it comes down")
	near(float(sim.stock.scrap), 115.0, 1e-9, "half of its thirty comes back")
	near(sim.build.factor("craft_mult"), 1.0, 1e-9, "its effects are gone")
	check(not sim.build.built("workshop"), "nothing stands")
	check(sim.build.version > v, "and the jobs are told by the version")
	check(not sim.build.demolish("court_north"), "an empty plot has nothing to demolish")
	g.world.free()


func test_a_plots_sign_is_in_its_corner_and_a_click_near_it_finds_the_plot() -> void:
	var g := _game()
	var sim = g.sim
	var pl: Dictionary = sim.build.plot("court_north")
	var corner: Vector2 = sim.build.sign_pos("court_north")
	near(corner.x, pl.pos.x - pl.size.x / 2.0 + 0.6, 1e-4, "the sign is inside the top-left corner (x)")
	near(corner.y, pl.pos.y - pl.size.y / 2.0 + 0.6, 1e-4, "(y)")
	eq(sim.build.sign_at(corner), "court_north", "a click on it finds the plot")
	eq(sim.build.sign_at(corner + Vector2(0.5, 0.3)), "court_north", "and one close to it")
	eq(sim.build.sign_at(Vector2(pl.pos)), "", "the middle of the lot is not the sign")
	eq(sim.build.sign_pos("nowhere"), Vector2.ZERO, "no plot, no sign")
	g.world.free()


func test_the_bunk_house_gives_four_beds_round_its_plot_and_the_tower_a_reach_bonus() -> void:
	var g := _game()
	var sim = g.sim
	eq(sim.build.bed_spots().size(), 0, "no bunk house, no beds")
	_stand(sim, "court_north", "bunk_house")
	var beds: Array = sim.build.bed_spots()
	eq(beds.size(), 4, "four beds")
	for b in beds:
		check(Vector2(b).distance_to(sim.build.plot("court_north").pos) < 2.0, "each is on the plot: %s" % str(b))
	var seen := {}
	for b in beds:
		seen[str(b)] = true
	eq(seen.size(), 4, "and no two are the same spot")
	_stand(sim, "court_south", "bunk_house")
	eq(sim.build.bed_spots().size(), 8, "a second bunk house has four more")
	near(sim.build.reach_bonus_at(Vector2(24.0, 28.0)), 0.0, 1e-9, "no tower, no bonus")
	_stand(sim, "west_wall", "watchtower")
	near(sim.build.reach_bonus_at(Vector2(22.0, 29.0)), 3.0, 1e-9, "near the west tower the guns reach three tiles further")
	near(sim.build.reach_bonus_at(Vector2(40.0, 30.0)), 0.0, 1e-9, "and far from it not")
	_stand(sim, "court_north", "watchtower")    # (the data would not allow it here: this is only to put two towers close together)
	near(sim.build.reach_bonus_at(Vector2(26.0, 27.5)), 3.0, 1e-9, "two towers near do not add up")
	g.world.free()


# ------------------------------------------------------- what standing buildings do --

func test_the_effects_of_the_standing_buildings_add_and_multiply() -> void:
	var g := _game()
	var sim = g.sim
	near(sim.build.bonus("housing"), 0.0, 1e-9, "no bunk house, no extra housing")
	eq(sim.build.housing(), 6, "the school houses six")
	_stand(sim, "court_north", "bunk_house")
	_stand(sim, "court_south", "bunk_house")
	near(sim.build.bonus("beds"), 8.0, 1e-9, "two bunk houses have eight beds")
	eq(sim.build.housing(), 14, "and house eight more")
	_stand(sim, "east_lot", "workshop")
	near(sim.build.factor("craft_mult"), 1.25, 1e-9, "the workshop's multiplier")
	_stand(sim, "south_lot", "radio_mast")
	_stand(sim, "north_east_lot", "floodlights")
	near(sim.build.factor("boon_mult"), 1.3, 1e-9, "the mast's boons")
	near(sim.build.factor("threat_mult"), 0.85, 1e-9, "and its threats")
	eq(sim.build.radio_range(), 1, "and its range")
	near(sim.build.factor("night_reach_mult"), 1.12, 1e-9, "the floodlights' reach")
	near(sim.build.factor("nothing_at_all"), 1.0, 1e-9, "an effect nobody has is 1")
	near(sim.build.bonus("nothing_at_all"), 0.0, 1e-9, "or 0")
	g.world.free()


func test_the_stations_follow_the_buildings() -> void:
	var g := _game()
	var sim = g.sim
	eq(sim.jobs.stations().size(), 6, "six stations to begin with")
	check(sim.jobs.station("salvage").locked, "the salvage station is known but locked")
	eq(sim.jobs.seats_of("salvage"), 0, "with no seats")
	var hector = _person(sim, "Hector")
	check(not sim.jobs.assign(hector, "salvage"), "nobody can be put on it")
	check(String(sim.jobs.why_not(hector, "salvage")).contains("not built yet"), "and it says why: %s" % sim.jobs.why_not(hector, "salvage"))
	eq(sim.jobs.seats_of("garden"), 2, "the beds have two seats")
	_stand(sim, "junk_corner", "salvage_bench")
	_stand(sim, "court_north", "greenhouse")
	eq(sim.jobs.stations().size(), 7, "seven once the salvage bench stands")
	eq(sim.jobs.seats_of("salvage"), 2, "with two seats")
	eq(sim.jobs.station("salvage").seats, 2, "which the station says too")
	eq(sim.jobs.station("salvage").pos, sim.build.plot("junk_corner").work, "it is worked at the bench's plot")
	eq(sim.jobs.seats_of("garden"), 4, "and the greenhouse gives the beds two more seats")
	check(sim.jobs.assign(hector, "salvage"), "now Hector can go to the salvage bench")
	_stand(sim, "south_lot", "workshop")
	eq(sim.jobs.seats_of("bench"), 3, "and the workshop a third seat at the bench")
	g.world.free()


func test_a_station_that_loses_its_building_lets_its_people_go() -> void:
	var g := _game()
	var sim = g.sim
	_stand(sim, "junk_corner", "salvage_bench")
	_stand(sim, "court_north", "greenhouse")
	var marcus = _person(sim, "Marcus")
	check(sim.jobs.assign(marcus, "salvage"), "Marcus is at the salvage bench")
	for first in ["Dez", "Ruth", "Walt"]:
		check(sim.jobs.assign(_person(sim, first), "garden"), "%s is in the beds" % first)
	eq(sim.jobs.crew_of("garden").size(), 3, "three in the beds, which have four seats with the greenhouse")
	sim.build.demolish("junk_corner")
	eq(sim.jobs.job_of(marcus), "", "Marcus has no job when the bench comes down")
	eq(sim.jobs.crew_of("garden").size(), 3, "the beds keep their three while the greenhouse stands")
	sim.build.demolish("court_north")
	eq(sim.jobs.crew_of("garden").size(), 2, "and one is let go when it comes down: the beds have two seats again")
	g.world.free()


func test_a_station_that_shrinks_lets_go_the_people_who_came_last() -> void:
	var g := _game()
	var sim = g.sim
	_stand(sim, "court_north", "workshop")
	var ruth = _person(sim, "Ruth")
	var dez = _person(sim, "Dez")
	var marcus = _person(sim, "Marcus")
	check(sim.jobs.assign(ruth, "bench") and sim.jobs.assign(dez, "bench") and sim.jobs.assign(marcus, "bench"), "three at the bench, which has three seats with the workshop")
	sim.build.demolish("court_north")
	eq(sim.jobs.job_of(ruth), "bench", "the first two keep their seats (Ruth has the bench's own spot)")
	eq(sim.jobs.job_of(dez), "bench", "Dez too")
	eq(sim.jobs.job_of(marcus), "", "and Marcus, the last to sit down, is the one let go")
	g.world.free()


func test_every_seat_of_every_station_is_on_open_ground() -> void:
	var g := _game()
	var sim = g.sim
	for b in sim.build.catalogue():
		var plot_id := ""
		for pl in sim.build.plots():
			if pl.building == "" and String(pl.kind) in b.plots:
				plot_id = String(pl.id)
				break
		if plot_id != "" and sim.build.count(String(b.id)) < int(b.max):
			_stand(sim, plot_id, String(b.id))
	for st in sim.jobs.stations():
		var id := String(st.id)
		var seats: int = sim.jobs.seats_of(id)
		for i in seats:
			var at: Vector2 = Vector2(st.pos) + Vector2(sim.jobs.SEAT_OFFSETS[mini(i, sim.jobs.SEAT_OFFSETS.size() - 1)])
			check(not sim.world.is_solid(sim.world.solid_p, at.x, at.y), "seat %d of %s at (%.1f, %.1f) is on open ground" % [i, id, at.x, at.y])
	g.world.free()


func test_the_salvage_station_makes_scrap_by_the_hour() -> void:
	var g := _game()
	var sim = g.sim
	_stand(sim, "junk_corner", "salvage_bench")
	var hector = _person(sim, "Hector")
	var dez = _person(sim, "Dez")
	check(Helpers.seat(sim, hector, "salvage"), "Hector is at the bench")
	var scrap: float = sim.stock.scrap
	Helpers.run(sim, 20.0)    # one game hour
	near(float(sim.stock.scrap) - scrap, Build.SALVAGE_PER_HOUR, 0.02, "an hour of one person sorts %.1f scrap" % Build.SALVAGE_PER_HOUR)
	check(Helpers.seat(sim, dez, "salvage"), "Dez joins him")
	Helpers.seat(sim, hector)
	scrap = sim.stock.scrap
	Helpers.run(sim, 20.0)
	near(float(sim.stock.scrap) - scrap, 2.0 * Build.SALVAGE_PER_HOUR, 0.03, "two make twice as much")
	g.world.free()


# ----------------------------------------------------------------- footprints --

func test_a_standing_building_shuts_its_footprint_and_demolishing_opens_it() -> void:
	var path := "user://test_building_art.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"buildings": {"workshop": {"solid": [-1.5, -1.0, 1.5, 1.0]}}}')
	f.close()
	Build.art_path = path
	var g := _game()
	var sim = g.sim
	var tiles: Array = []
	sim.build.order("court_north", "workshop")
	var pl: Dictionary = sim.build.plot("court_north")
	sim.build._finish(pl)
	tiles = sim.build.footprint_tiles("court_north")
	var centre: Vector2 = pl.pos
	var wanted := 0
	for ty in range(floori(centre.y - 1.0), floori(centre.y + 1.0 - 0.001) + 1):
		for tx in range(floori(centre.x - 1.5), floori(centre.x + 1.5 - 0.001) + 1):
			wanted += 1
	eq(tiles.size(), wanted, "the tiles under the rectangle: %d" % wanted)
	for i in tiles:
		eq(sim.world.solid_p[int(i)], 1, "tile %d is shut for people" % int(i))
		eq(sim.world.solid_z[int(i)], 1, "and for the dead")
		check(sim.path_p.grid.is_point_solid(Vector2i(int(i) % sim.world.W, int(i) / sim.world.W)), "and in the path grid")
	check(sim.build.demolish("court_north"), "it comes down")
	for i in tiles:
		eq(sim.world.solid_p[int(i)], 0, "tile %d is open again" % int(i))
		check(not sim.path_p.grid.is_point_solid(Vector2i(int(i) % sim.world.W, int(i) / sim.world.W)), "in the path grid too")
	g.world.free()
	Build.art_path = Build.ART_PATH


# ----------------------------------------------------------------------- saves --

func test_a_save_keeps_the_sites_the_buildings_and_the_order() -> void:
	var a := _game()
	var sim_a = a.sim
	_stand(sim_a, "court_south", "greenhouse")
	sim_a.build.order("junk_corner", "salvage_bench")
	sim_a.build.order("court_north", "workshop")
	sim_a.build.plot("junk_corner").site.progress = 6.5
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim_a)))
	var b := _game(8.0, 99)
	check(SaveGame.apply(b.sim, d), "the save loads")
	eq(b.sim.build.plot("court_south").building, "greenhouse", "the greenhouse stands")
	eq(b.sim.build.plot("junk_corner").site.building, "salvage_bench", "the first site")
	near(float(b.sim.build.plot("junk_corner").site.progress), 6.5, 1e-9, "with its work done")
	eq(b.sim.build.plot("court_north").site.building, "workshop", "the second")
	eq(b.sim.build.active_site().id, "junk_corner", "the first order is still the active one")
	near(b.sim.build.progress_of("junk_corner"), 6.5 / 14.0, 1e-9, "and the progress is the same share")
	eq(b.sim.jobs.seats_of("garden"), 4, "the jobs see the greenhouse")
	a.world.free()
	b.world.free()


func test_a_save_from_before_buildings_loads_with_nothing_built() -> void:
	var a := _game()
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	d.modules.erase("build")
	var b := _game(8.0, 99)
	_stand(b.sim, "court_north", "workshop")
	check(SaveGame.apply(b.sim, d), "an old save loads")
	check(not b.sim.build.built("workshop"), "with nothing built")
	for pl in b.sim.build.plots():
		check(pl.building == "" and pl.site.is_empty(), "%s is empty" % pl.id)
	a.world.free()
	b.world.free()


func test_a_new_run_starts_with_nothing_built() -> void:
	var g := _game()
	var sim = g.sim
	_stand(sim, "court_north", "workshop")
	sim.build.order("junk_corner", "salvage_bench")
	sim.start_run(1, 5)
	check(not sim.build.built("workshop"), "a new run has no buildings")
	eq(sim.build.active_site(), {}, "and no sites")
	g.world.free()
