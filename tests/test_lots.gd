extends "res://tests/case.gd"
## The lots (round 9): claiming a part of the ring, the Main gate opening to people only, ring plots and
## mouths on the Build screen's side of things, a wall built across a street becoming a wall section,
## the dead's choice of places, the night's raids on an unsealed lot, saves. The real data is
## assets/data/lots.json (tested in test_lots_data.gd); these tests use two alleys of the north row,
## which are real, open and two tiles wide in the map. The classic start has no lots.

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Lots := preload("res://scripts/sim/lots.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const FIXTURE := "user://test_lots.json"

## The north row's two alleys (x 28-29 and x 54-55, y 0-3). A wall of three tiles shuts one (rect is the
## tiles it shuts, both ends included). The spawn points (29, 0.5) and (55, 0.5) are at their mouths.
const LOTS := {
	"version": 1,
	"passage": 2,
	"lots": [
		{"id": "north", "name": "The north row", "blurb": "The alleys.", "claim": {"scrap": 40, "cleared": 1, "day": 3},
			"mouths": ["alley_w", "alley_e"], "plots": ["ring_a"]},
		{"id": "later", "name": "A later lot", "blurb": "Not yet.", "claim": {"scrap": 90, "cleared": 3, "day": 9},
			"mouths": [], "plots": []},
	],
	"mouths": [
		{"id": "alley_w", "name": "West alley", "lot": "north", "spawn": 6, "dir": "h", "rect": [28, 1, 29, 3], "center": [29.0, 2.5],
			"length": 2.0, "kits": ["pallets_h", "container_h"],
			"slots": [{"x": 28.5, "y": 0.6, "ax": 28.5, "ay": 0.3, "face": "S"}, {"x": 29.5, "y": 0.6, "ax": 29.5, "ay": 0.3, "face": "S"}],
			"post": {"pos": [28.5, 5.0], "what": "Holding the west alley"}, "outside": [28, 0], "inside": [28, 4]},
		{"id": "alley_e", "name": "East alley", "lot": "north", "spawn": 7, "dir": "h", "rect": [54, 1, 55, 3], "center": [55.0, 2.5],
			"length": 2.0, "kits": ["pallets_h"],
			"slots": [{"x": 54.5, "y": 0.6, "ax": 54.5, "ay": 0.3, "face": "S"}, {"x": 55.5, "y": 0.6, "ax": 55.5, "ay": 0.3, "face": "S"}],
			"post": {"pos": [54.5, 5.0], "what": "Holding the east alley"}, "outside": [54, 0], "inside": [54, 4]},
	],
	"plots": [
		{"id": "ring_a", "name": "The north sidewalk", "kind": "ring", "lot": "north", "pos": [45.5, 13.5], "size": [3, 3], "work": [45.5, 15.0]},
	],
	"kits": {
		"pallets_h": {"name": "Pallet barricade", "dir": "h", "length": 3.4, "hp": 130, "scrap": 9, "work": 4, "template": 1, "thick": 1.3, "stand": 1.9},
		"container_h": {"name": "Container", "dir": "h", "length": 12.0, "hp": 420, "scrap": 30, "work": 6, "template": 0, "thick": 2.44, "stand": 2.74},
	},
}


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## A settlement game with the two alleys as its lots, by day, rich, with the world quiet.
func _game(small: bool = true) -> Dictionary:
	_write(LOTS)
	Lots.data_path = FIXTURE
	var g := Helpers.make(21, 1, 3 if small else 6)
	Lots.data_path = Lots.DATA_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 4
	sim.minutes = 8.0 * 60.0
	sim.clock_min = 3.0 * 1440.0 + 8.0 * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.stock = {"ammo": 300.0, "scrap": 200.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	sim.events.clear()
	return g


func _clear_places(sim, n: int) -> void:
	var i := 0
	for id in sim.town.state:
		if i >= n:
			return
		sim.town.state[id].cleared = true
		i += 1


## Claims the north lot (clears a place first), then orders and finishes a wall at the mouth.
func _wall(sim, mouth_id: String, kit_id: String) -> bool:
	if not sim.lots.claimed("north"):
		_clear_places(sim, 1)
		if not sim.lots.claim("north"):
			return false
	if not sim.build.order(mouth_id, "wall_%s" % kit_id):
		return false
	var pl: Dictionary = sim.build.plot(mouth_id)
	pl.site.progress = float(pl.site.work)
	sim.build._finish(pl)
	return true


func _has_event(sim, type: String, key: String, value) -> bool:
	for e in sim.events:
		if e.get("type", "") == type and e.get(key, null) == value:
			return true
	return false


func test_the_classic_start_has_no_lots() -> void:
	var g := _game(false)
	var sim = g.sim
	check(not sim.lots.on, "no lots in the classic start")
	eq(sim.build.plots().size(), 12, "the yard's plots only (nine in the yard, three on the wall)")
	eq(sim.build.catalogue().size(), 7, "the seven buildings, no wall kits")
	check(sim.lots.why_not_claim("north") != "", "nothing to claim")
	check(sim.build.why_not("alley_w", "wall_pallets_h") != "", "no wall can be ordered")
	eq(sim.jobs.posts().size(), sim.jobs._base_posts.size(), "no extra posts")
	g.world.free()


func test_the_settlement_game_has_lots_that_are_not_open_yet() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.lots.on, "lots in the settlement game")
	eq(sim.lots.lots().size(), 2, "two lots")
	eq(sim.build.plots().size(), 12, "no lot's plots are seen before it is claimed")
	check(sim.build.plot("ring_a").size() > 0 and sim.build.plot("alley_w").size() > 0, "but they are known to the module")
	check(sim.build.why_not("ring_a", "greenhouse") != "", "a ring plot cannot be built on before the claim")
	check(sim.build.why_not("alley_w", "wall_pallets_h").contains("claim"), "nor a wall: %s" % sim.build.why_not("alley_w", "wall_pallets_h"))
	eq(sim.build.catalogue().size(), 7 + 3 + 2, "the ring's three buildings and the kits are in the catalogue of a lots game")
	g.world.free()


func test_a_claim_needs_the_day_the_scrap_and_cleared_places() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.lots.why_not_claim("north").contains("clear 1 place"), "a place must be cleared: %s" % sim.lots.why_not_claim("north"))
	_clear_places(sim, 1)
	eq(sim.lots.why_not_claim("north"), "", "the first lot can be claimed")
	sim.stock.scrap = 10.0
	check(sim.lots.why_not_claim("north").contains("40 scrap"), "scrap: %s" % sim.lots.why_not_claim("north"))
	sim.stock.scrap = 200.0
	sim.day = 2
	check(sim.lots.why_not_claim("north").contains("day 3"), "the day: %s" % sim.lots.why_not_claim("north"))
	sim.day = 4
	check(sim.lots.why_not_claim("later") != "", "the later lot has harder terms")
	check(not sim.lots.claim("later"), "so it cannot be claimed")
	eq(float(sim.stock.scrap), 200.0, "a refused claim costs nothing")
	g.world.free()


func test_a_claim_pays_and_opens_the_lots_plots_and_the_gate_to_people() -> void:
	var g := _game()
	var sim = g.sim
	_clear_places(sim, 1)
	var gate_tile: int = 17 * sim.W + 38
	eq(int(sim.world.solid_p[gate_tile]), 1, "the Main gate is shut to people")
	# (people can already get out the long way round, over the corner towers: the gate is the short way)
	var way_before: Array = sim.path_p.find(sim.world.solid_p, 39.0, 24.0, 39.0, 13.0)
	check(sim.lots.claim("north"), "the claim goes through")
	eq(float(sim.stock.scrap), 160.0, "it cost 40 scrap")
	check(sim.lots.claimed("north"), "claimed")
	eq(sim.build.plots().size(), 12 + 1 + 2, "the lot's ring plot and two mouths are seen")
	eq(int(sim.world.solid_p[gate_tile]), 0, "the gate is open to people")
	eq(int(sim.world.solid_z[gate_tile]), 1, "and shut to the dead")
	var way_after: Array = sim.path_p.find(sim.world.solid_p, 39.0, 24.0, 39.0, 13.0)
	check(way_after.size() < way_before.size(), "people can walk out through the gate: the way is shorter (%d against %d turns)" % [way_after.size(), way_before.size()])
	check(sim.path_z.find(sim.world.solid_z, 39.0, 13.0, 39.0, 24.0).is_empty(), "the dead cannot walk in")
	check(_has_event(sim, "lot", "what", "claimed"), "an event says so")
	check(sim.build.why_not("ring_a", "greenhouse") == "" or sim.build.why_not("ring_a", "greenhouse").contains("scrap") == false, "a ring plot takes a building now: %s" % sim.build.why_not("ring_a", "greenhouse"))
	check(not sim.lots.claim("north"), "it cannot be claimed twice")
	g.world.free()


func test_the_claimed_lots_posts_join_the_night_posts() -> void:
	var g := _game()
	var sim = g.sim
	var before: int = sim.jobs.posts().size()
	_clear_places(sim, 1)
	sim.lots.claim("north")
	eq(sim.jobs.posts().size(), before + 2, "a post for each mouth")
	var po: Dictionary = sim.jobs.post("post_alley_w")
	check(not po.is_empty(), "the west alley's post")
	eq(String(po.face), "N", "it faces the street outside")
	check(Vector2(po.pos).is_equal_approx(Vector2(28.5, 5.0)), "where the data puts it")
	check(sim.jobs.post("north_west").size() > 0, "the wall's own posts are still there")
	g.world.free()


func test_a_mouth_takes_a_wall_kit_and_nothing_else() -> void:
	var g := _game()
	var sim = g.sim
	_clear_places(sim, 1)
	sim.lots.claim("north")
	check(sim.build.why_not("alley_e", "wall_container_h").contains("fit"), "the east alley does not take the container: %s" % sim.build.why_not("alley_e", "wall_container_h"))
	check(sim.build.why_not("alley_w", "greenhouse").contains("wall"), "a building does not go across a street: %s" % sim.build.why_not("alley_w", "greenhouse"))
	check(sim.build.why_not("ring_a", "wall_pallets_h").contains("fit"), "nor a wall on a plot: %s" % sim.build.why_not("ring_a", "wall_pallets_h"))
	eq(sim.build.why_not("alley_w", "wall_pallets_h"), "", "the pallets fit the west alley")
	var before: float = sim.stock.scrap
	check(sim.build.order("alley_w", "wall_pallets_h"), "ordered")
	eq(float(sim.stock.scrap), before - 9.0, "9 scrap")
	check(sim.lots.wall_at("alley_w").is_empty(), "nothing stands until it is built")
	eq(sim.build.why_not_demolish("alley_w"), "nothing stands there", "nothing to pull down yet")
	g.world.free()


func test_a_finished_wall_is_a_section_that_shuts_the_street() -> void:
	var g := _game()
	var sim = g.sim
	var n: int = sim.segments.size()
	check(not sim.path_z.find(sim.world.solid_z, 28.5, 0.5, 28.5, 6.5).is_empty(), "the dead can come in by the alley")
	check(_wall(sim, "alley_w", "pallets_h"), "the wall is built")
	eq(sim.segments.size(), n + 1, "a section was added")
	var s = sim.lots.segment_at("alley_w")
	check(s != null, "the section stands at the mouth")
	eq(int(s.id), Lots.FIRST_SEGMENT_ID + 0, "its id")
	near(float(s.hp), 130.0, 0.001, "the kit's health")
	eq(s.side, "N", "it faces north")
	eq(s.slots.size(), 2, "two places for the dead")
	check(s.art.size() == 4 and s.art[0].size() > 0, "four states of pictures")
	for ty in range(1, 4):
		for tx in range(28, 30):
			eq(int(sim.world.solid_z[ty * sim.W + tx]), 1, "tile %d,%d is shut to the dead" % [tx, ty])
			eq(int(sim.world.solid_p[ty * sim.W + tx]), 1, "and to people")
	check(sim.path_z.find(sim.world.solid_z, 28.5, 0.5, 28.5, 6.5).is_empty(), "the dead cannot come in by the alley any more")
	check(not sim.path_z.find(sim.world.solid_z, 54.5, 0.5, 54.5, 6.5).is_empty(), "the other alley is still open")
	check(_has_event(sim, "wall", "mouth", "alley_w"), "an event says it is finished")
	eq(sim.build.why_not_demolish("alley_w").contains("not pulled down"), true, "a wall is not pulled down")
	g.world.free()


func test_a_lot_is_sealed_when_all_its_walls_stand() -> void:
	var g := _game()
	var sim = g.sim
	check(not sim.lots.sealed("north"), "not claimed, not sealed")
	_wall(sim, "alley_w", "pallets_h")
	check(not sim.lots.sealed("north"), "one wall of two")
	_wall(sim, "alley_e", "pallets_h")
	check(sim.lots.sealed("north"), "both walls: sealed")
	sim.events.clear()
	sim.update(1.0 / 30.0)
	check(_has_event(sim, "lot", "what", "sealed"), "the sealing is reported")
	sim.events.clear()
	sim.update(1.0 / 30.0)
	check(not _has_event(sim, "lot", "what", "sealed"), "once")
	# a wall that falls unseals it
	var s = sim.lots.segment_at("alley_e")
	sim._damage_segment(s, 1000.0)
	check(int(s.state) == 3, "the wall is down")
	check(not sim.lots.sealed("north"), "a fallen wall does not seal")
	check(not sim.path_z.find(sim.world.solid_z, 54.5, 0.5, 54.5, 6.5).is_empty(), "the street is open again")
	g.world.free()


func test_the_dead_choose_among_places_they_can_reach() -> void:
	var g := _game()
	var sim = g.sim
	_wall(sim, "alley_w", "pallets_h")
	# outside the wall: the new wall's places are right there
	var out = sim.spawn(28.5, 0.6, "approach")
	check(sim.assign_slot(out, null), "a place is found")
	eq(int(out.slot.seg.id), Lots.FIRST_SEGMENT_ID, "the dead at the alley go for its wall")
	# inside the ring, the shut alley's outer places cannot be reached
	var inside = sim.spawn(40.0, 7.0, "approach")
	check(sim.assign_slot(inside, null), "a place is found")
	check(int(inside.slot.seg.id) < Lots.FIRST_SEGMENT_ID, "one inside the ring goes for a wall of the compound")
	g.world.free()


func test_a_wall_down_in_the_lots_does_not_open_the_school() -> void:
	var g := _game()
	var sim = g.sim
	_wall(sim, "alley_w", "pallets_h")
	var s = sim.lots.segment_at("alley_w")
	sim._damage_segment(s, 1000.0)
	check(not sim.yard_open(), "the compound's own walls stand: the yard is not open")
	g.world.free()


func test_the_dead_standing_where_a_wall_goes_up_are_gone() -> void:
	var g := _game()
	var sim = g.sim
	_clear_places(sim, 1)
	sim.lots.claim("north")
	var z = sim.spawn(28.5, 2.5, "wander")
	sim.build.order("alley_w", "wall_pallets_h")
	var pl: Dictionary = sim.build.plot("alley_w")
	pl.site.progress = float(pl.site.work)
	sim.build._finish(pl)
	check(z.state == "dying" or z.state == "dead", "the one in the way is gone: %s" % z.state)
	g.world.free()


func test_an_unsealed_lots_buildings_may_be_ruined_at_the_bell() -> void:
	var g := _game()
	var sim = g.sim
	_clear_places(sim, 1)
	sim.lots.claim("north")
	var pl: Dictionary = sim.build.plot("ring_a")
	var ruined := false
	for i in 300:
		pl.building = "greenhouse"
		sim.lots._raid()
		if pl.building == "":
			ruined = true
			break
	check(ruined, "an unsealed lot's building is sometimes ruined (a raid happened in 300 nights)")
	check(_has_event(sim, "ruined", "plot", "ring_a"), "an event says so")
	# yard buildings are never touched
	var yard_plot: Dictionary = sim.build.plots()[0]
	yard_plot.building = "workshop"
	for i in 300:
		sim.lots._raid()
	eq(String(yard_plot.building), "workshop", "the yard is not raided")
	g.world.free()


func test_a_sealed_lots_buildings_are_not_raided() -> void:
	var g := _game()
	var sim = g.sim
	_wall(sim, "alley_w", "pallets_h")
	_wall(sim, "alley_e", "pallets_h")
	var pl: Dictionary = sim.build.plot("ring_a")
	pl.building = "greenhouse"
	for i in 300:
		sim.lots._raid()
	eq(String(pl.building), "greenhouse", "a sealed lot is safe")
	g.world.free()


func test_a_raid_happens_once_a_night_at_the_bell() -> void:
	var g := _game()
	var sim = g.sim
	_clear_places(sim, 1)
	sim.lots.claim("north")
	var pl: Dictionary = sim.build.plot("ring_a")
	pl.building = "greenhouse"
	sim.bell_rung = true
	sim.lots._raid_day = sim.day
	for i in 400:
		sim.lots.update(1.0 / 30.0)
	eq(String(pl.building), "greenhouse", "no second raid on the same night")
	g.world.free()


func test_a_lot_gives_room_for_more_of_a_building() -> void:
	var g := _game()
	var sim = g.sim
	var b: Dictionary = sim.build.building("bunk_house")
	eq(sim.build._max_of(b), int(b.max), "no lot, no extra room")
	var extra := b.duplicate()
	extra["lot_max"] = 1
	eq(sim.build._max_of(extra), int(b.max), "no lot claimed yet")
	_clear_places(sim, 1)
	sim.lots.claim("north")
	eq(sim.build._max_of(extra), int(b.max) + 1, "a claimed lot allows one more")
	g.world.free()


func test_saves_keep_the_claim_and_the_walls() -> void:
	var g := _game()
	var sim = g.sim
	_wall(sim, "alley_w", "pallets_h")
	var s = sim.lots.segment_at("alley_w")
	sim._damage_segment(s, 50.0)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var b := _game()
	var sim_b = b.sim
	check(SaveGame.apply(sim_b, d), "the save loads")
	check(sim_b.lots.claimed("north"), "the claim is kept")
	check(not sim_b.lots.wall_at("alley_w").is_empty(), "the wall is kept")
	var s2 = sim_b.lots.segment_at("alley_w")
	check(s2 != null, "its section is there")
	near(float(s2.hp), 80.0, 0.01, "its health is as it was")
	eq(int(sim_b.world.solid_p[2 * sim_b.W + 28]), 1, "its tiles are shut")
	eq(int(sim_b.world.solid_p[17 * sim_b.W + 38]), 0, "the gate is open to people")
	check(not sim_b.jobs.post("post_alley_w").is_empty(), "the post is there")
	eq(sim_b.build.plots().size(), 15, "the lot's plots are seen")
	check(String(sim_b.build.plot("alley_w").building) != "", "the plot knows its wall")
	g.world.free()
	b.world.free()


func test_a_save_without_the_wall_takes_it_away() -> void:
	var a := _game()
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	var b := _game()
	_wall(b.sim, "alley_w", "pallets_h")
	check(not b.sim.lots.wall_at("alley_w").is_empty(), "a wall stands")
	check(SaveGame.apply(b.sim, d), "the save loads")
	check(b.sim.lots.wall_at("alley_w").is_empty(), "the save had none")
	check(b.sim.lots.segment_at("alley_w") == null, "no section")
	eq(int(b.sim.world.solid_p[2 * b.sim.W + 28]), 0, "the tiles are open again")
	a.world.free()
	b.world.free()


func test_a_bad_save_leaves_the_walls_as_they_were() -> void:
	var a := _game()
	_wall(a.sim, "alley_w", "pallets_h")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	d["day"] = -5
	var b := _game()
	check(not SaveGame.apply(b.sim, d), "the broken save is refused")
	check(b.sim.lots.wall_at("alley_w").is_empty(), "no wall appeared")
	check(b.sim.lots.segment_at("alley_w") == null, "no section")
	eq(int(b.sim.world.solid_p[2 * b.sim.W + 28]), 0, "the street is open")
	a.world.free()
	b.world.free()


func test_a_new_run_clears_the_lots() -> void:
	var g := _game()
	var sim = g.sim
	_wall(sim, "alley_w", "pallets_h")
	sim.start_run(1, 5)
	check(not sim.lots.claimed("north"), "nothing is claimed in a new run")
	check(sim.lots.segment_at("alley_w") == null, "no wall")
	eq(sim.segments.size(), 16, "the compound's sixteen sections only")
	eq(int(sim.world.solid_p[2 * sim.W + 28]), 0, "the street is open")
	g.world.free()


func test_the_town_counts_the_places_cleared() -> void:
	var g := _game()
	var sim = g.sim
	eq(sim.town.cleared_count(), 0, "none at the start")
	_clear_places(sim, 2)
	eq(sim.town.cleared_count(), 2, "two")
	g.world.free()


## The real ring (assets/data/lots.json): every lot claimed, every street walled with its first kit.
func _real_ring() -> Dictionary:
	var g := Helpers.make(3, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 12
	sim.stock.scrap = 2000.0
	_clear_places(sim, 4)
	return g


func _wall_all(sim) -> void:
	for l in sim.lots.lots():
		sim.lots.claim(String(l.id))
	for m in sim.lots.mouths():
		var kits: Array = sim.lots.kits_for(String(m.id))
		if kits.is_empty() or not sim.build.order(String(m.id), String(kits[0])):
			continue
		var pl: Dictionary = sim.build.plot(String(m.id))
		pl.site.progress = float(pl.site.work)
		sim.build._finish(pl)


func test_the_real_ring_is_open_until_every_street_is_walled() -> void:
	var g := _real_ring()
	var sim = g.sim
	check(sim.lots.on, "the real data is there")
	eq(sim.lots.streets(), 10, "ten streets")
	eq(sim.lots.open_streets(), 10, "all open at first")
	near(sim.lots.raid_risk(), Lots.RAID_RISK, 0.0001, "the full raid risk")
	var gate: int = sim.region_at(39.0, 13.0)
	var open_spawns := 0
	for sp in sim.spawns:
		if sim.region_at(sp.x, sp.y) == gate:
			open_spawns += 1
	eq(open_spawns, 10, "every spawn point reaches the street outside the gate")
	_wall_all(sim)
	eq(sim.lots.open_streets(), 0, "all ten walls stand")
	near(sim.lots.raid_risk(), 0.0, 0.0, "no raids on a sealed ring")
	for sp in sim.spawns:
		check(sim.region_at(sp.x, sp.y) != sim.region_at(39.0, 13.0), "the spawn point at %s no longer reaches the ring" % str(sp))
	for l in sim.lots.lots():
		check(sim.lots.sealed(String(l.id)), "%s is sealed" % l.id)
	g.world.free()


func test_each_wall_of_the_real_ring_draws_the_dead_to_it() -> void:
	var g := _real_ring()
	var sim = g.sim
	_wall_all(sim)
	var checked := 0
	for m in sim.lots.mouths():
		var seg = sim.lots.segment_at(String(m.id))
		check(seg != null, "%s has its wall" % m.id)
		if seg == null:
			continue
		var sl: Dictionary = m.slots[0]
		var z = sim.spawn(float(sl.ax), float(sl.ay), "approach")
		if sim.assign_slot(z, null):
			# a street with two walls end to end: either of them (the same spawn point's)
			var got: Dictionary = sim.lots.mouths()[int(z.slot.seg.id) - Lots.FIRST_SEGMENT_ID] if int(z.slot.seg.id) >= Lots.FIRST_SEGMENT_ID else {}
			check(not got.is_empty() and int(got.spawn) == int(m.spawn), "the dead at %s go for a wall of their street (not %s)" % [m.id, z.slot.seg.name])
			checked += 1
		z.state = "dead"
		z.remove = true
	eq(checked, sim.lots.mouths().size(), "every wall was reached from outside")
	g.world.free()


func test_one_street_left_open_lets_the_dead_reach_the_whole_ring() -> void:
	var g := _real_ring()
	var sim = g.sim
	_wall_all(sim)
	var seg = sim.lots.segment_at("west_alley")
	sim._damage_segment(seg, 100000.0)
	eq(sim.lots.open_streets(), 1, "one street is open: its wall is down")
	near(sim.lots.raid_risk(), Lots.RAID_RISK * 0.1, 0.0001, "a tenth of the risk")
	check(sim.region_at(0.5, 37.0) == sim.region_at(39.0, 13.0), "the dead from that alley reach the ring")
	g.world.free()


func test_the_rings_buildings_stand_only_on_the_ring_and_pay_at_dawn() -> void:
	var g := _game()
	var sim = g.sim
	_clear_places(sim, 1)
	sim.lots.claim("north")
	for id in ["orchard", "cistern", "scrap_yard"]:
		eq(sim.build.why_not("ring_a", id), "", "the %s can be ordered on a ring plot" % id)
		check(sim.build.why_not(String(sim.build.plots()[0].id), id) != "", "but not on a yard plot (%s)" % id)
	# a building of the yard may stand on the ring
	eq(sim.build.why_not("ring_a", "greenhouse"), "", "the greenhouse may stand on the ring")
	var plot: Dictionary = sim.build.plot("ring_a")
	Helpers.idle_stores(sim)
	sim.supplies.sources_on = true
	var base_food: float = sim.stock.food
	var base_water: float = sim.stock.water
	var base_scrap: float = sim.stock.scrap
	plot.building = "orchard"
	sim.weather = "clear"
	sim.supplies.roll_dawn()
	var food_with: float = sim.stock.food - base_food
	plot.building = ""
	sim.stock.food = base_food
	sim.supplies.roll_dawn()
	near(food_with - (sim.stock.food - base_food), 1.5, 0.0001, "an orchard gives a food and a half a dawn")
	plot.building = "scrap_yard"
	sim.stock.scrap = base_scrap
	sim.supplies.roll_dawn()
	near(sim.stock.scrap - base_scrap, 3.0, 0.0001, "a scrap yard gives 3 scrap a dawn")
	plot.building = "cistern"
	var w0: float = sim.stock.water
	sim.supplies.roll_dawn()
	var with_c: float = sim.stock.water - w0
	plot.building = ""
	var w1: float = sim.stock.water
	sim.supplies.roll_dawn()
	var without_c: float = sim.stock.water - w1
	near(with_c - without_c, 3.0 if sim.weather == "clear" else 6.0, 0.0001, "a cistern gives its water a dawn (twice that in the rain)")
	g.world.free()


func test_the_rings_buildings_are_not_in_the_classic_game() -> void:
	var g := _game(false)
	var ids: Array = []
	for b in g.sim.build.catalogue():
		ids.append(String(b.id))
	check(not ids.has("orchard") and not ids.has("cistern") and not ids.has("scrap_yard"), "no ring buildings in the classic catalogue")
	g.world.free()


# ---------------------------------------------------------------- review fixes --

## A sim as the real game loads one: made, never started, then given the save.
func _fresh_sim() -> Dictionary:
	_write(LOTS)
	Lots.data_path = FIXTURE
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	Lots.data_path = Lots.DATA_PATH
	return {"sim": sim, "world": world}


func test_a_save_with_a_wall_loads_into_a_sim_that_was_never_started() -> void:
	var a := _game()
	_wall(a.sim, "alley_w", "pallets_h")
	a.sim._damage_segment(a.sim.lots.segment_at("alley_w"), 50.0)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	var b := _fresh_sim()
	check(SaveGame.apply(b.sim, d), "the save loads as the game loads it")
	check(b.sim.lots.on, "lots are on")
	check(b.sim.lots.segment_at("alley_w") != null, "the wall is there")
	near(float(b.sim.lots.segment_at("alley_w").hp), 80.0, 0.01, "as damaged as it was")
	check(not b.sim.jobs.post("post_alley_w").is_empty(), "and its post")
	a.world.free()
	b.world.free()


func test_the_posts_of_the_mouths_are_kept_through_a_save() -> void:
	var a := _game()
	var sim = a.sim
	_clear_places(sim, 1)
	sim.lots.claim("north")
	var dez = sim.people[1]
	check(sim.jobs.set_post(dez, "post_alley_e"), "Dez takes the east alley's post")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var b := _fresh_sim()
	check(SaveGame.apply(b.sim, d), "it loads")
	var dez2 = null
	for p in b.sim.people:
		if p.id == dez.id:
			dez2 = p
	eq(String(b.sim.jobs.post_of(dez2).get("id", "")), "post_alley_e", "he is still at the east alley's post")
	a.world.free()
	b.world.free()


func test_a_fallen_street_wall_does_not_send_the_whole_horde_into_the_breach_state() -> void:
	var g := _game()
	var sim = g.sim
	_wall(sim, "alley_w", "pallets_h")
	sim._damage_segment(sim.lots.segment_at("alley_w"), 100000.0)
	check(not sim._breached(), "the compound's walls stand: the yard is not breached")
	g.world.free()


func test_the_dead_crowding_a_spawn_pocket_on_their_way_out_are_all_gone() -> void:
	var g := _game()
	var sim = g.sim
	var crowd: Array = []
	for x in [28.3, 28.7, 29.3, 29.7]:
		var z = sim.spawn(x, 0.7, "approach")
		sim.retreat(z)
		crowd.append(z)
	for i in 400:
		sim.update(1.0 / 30.0)
	var left := 0
	for z in sim.zombies:
		if z.state == "retreat":
			left += 1
	eq(left, 0, "none of the four is left pushing the others about the spawn point")
	g.world.free()


func test_a_zombie_wiped_by_a_new_wall_gives_up_its_slot() -> void:
	var g := _game()
	var sim = g.sim
	_clear_places(sim, 1)
	sim.lots.claim("north")
	var z = sim.spawn(28.5, 2.5, "approach")
	var slot = sim.segments[0].slots[0]
	slot.who = z
	z.slot = slot
	sim.build.order("alley_w", "wall_pallets_h")
	var pl: Dictionary = sim.build.plot("alley_w")
	pl.site.progress = float(pl.site.work)
	sim.build._finish(pl)
	check(slot.who == null, "the slot is free again")
	check(z.slot == null, "and the dead one holds none")
	g.world.free()


func test_a_load_does_not_raid_a_second_time_on_the_same_night() -> void:
	var a := _game()
	var sim = a.sim
	_clear_places(sim, 1)
	sim.lots.claim("north")
	sim.bell_rung = true
	sim.lots._raid_day = sim.day
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var b := _fresh_sim()
	check(SaveGame.apply(b.sim, d), "it loads")
	eq(b.sim.lots._raid_day, sim.day, "the night's raid is remembered")
	a.world.free()
	b.world.free()


func test_the_slots_of_a_thin_wall_are_where_the_dead_stand_against_it() -> void:
	var g := _game()
	var sim = g.sim
	_wall(sim, "alley_w", "pallets_h")
	var seg = sim.lots.segment_at("alley_w")
	var mouth: Dictionary = sim.lots.mouth("alley_w")
	var raw: Dictionary = mouth.slots[0]
	# the data's slots are for a container (the dead 2.74 in front of the inner face): pallets are thinner (1.9)
	var shift: float = seg.slots[0].y - float(raw.y)
	near(shift, Lots.SLOT_STAND - 1.9, 0.001, "a thin wall draws its dead closer to the ring side by the difference")
	g.world.free()


func test_a_refused_load_leaves_the_walls_as_they_were() -> void:
	var a := _game()
	_wall(a.sim, "alley_w", "pallets_h")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	d["day"] = -5
	var seg = a.sim.lots.segment_at("alley_w")
	a.sim._damage_segment(seg, 100.0)
	var hp: float = seg.hp
	var z = a.sim.spawn(28.5, 0.6, "approach")
	check(a.sim.assign_slot(z, null), "a dead one has a place at the wall")
	z.state = "attack"
	check(not SaveGame.apply(a.sim, d), "the broken save is refused")
	var seg2 = a.sim.lots.segment_at("alley_w")
	check(seg2 != null, "the wall is still there")
	near(float(seg2.hp), hp, 0.001, "as damaged as it was")
	a.sim.update(1.0 / 30.0)    # (nothing may throw)
	a.world.free()


func test_a_new_run_forgets_the_lots_posts_and_plots() -> void:
	var g := _game()
	var sim = g.sim
	_clear_places(sim, 1)
	sim.lots.claim("north")
	check(sim.build.plots().size() > 12, "plots are open")
	var base: int = sim.jobs._base_posts.size()
	sim.start_run(1, 9)
	eq(sim.build.plots().size(), 12, "a new run has only the yard's plots")
	eq(sim.jobs.posts().size(), base, "and only the wall's posts")
	g.world.free()
