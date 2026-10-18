extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")
const TownWorld := preload("res://scripts/town/town_world.gd")
const TownRun := preload("res://scripts/town/town_run.gd")
const TownRoofs := preload("res://scripts/town/town_roofs.gd")
const Pathfinder := preload("res://scripts/sim/pathfinder.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const PrisonArms := preload("res://scripts/prison/prison_arms.gd")
const PrisonMeta := preload("res://scripts/prison/prison_meta.gd")
const PrisonNoise := preload("res://scripts/prison/prison_noise.gd")
const Inventory := preload("res://scripts/sim/inventory.gd")

var _town: Dictionary = {}


func _make() -> Dictionary:
	if _town.is_empty():
		_town = TownGen.make(1)
	return _town


## How many of the town's dead stand in the rooms of the start house.
func _start_dead(t: Dictionary) -> int:
	var n := 0
	for r in t.dead:
		if int(r.house) == int(t.start.house) and int(r.room) >= 0:
			n += 1
	return n


func test_the_same_seed_makes_the_same_town_and_its_data_is_whole() -> void:
	var t := _make()
	var again := TownGen.make(1)
	eq(TownGen.digest(again), TownGen.digest(t), "the same seed, the same town")
	check(TownGen.digest(TownGen.make(2)) != TownGen.digest(t), "another seed, another town")
	# (a town has about 85 houses since the fields of fire were cleared round the candidates (CLEAR3: 74 to 100, none under 60: tools/town_probe.gd MIN_HOUSES))
	check(t.houses.size() >= 60 and t.houses.size() <= 250, "60 to 250 houses: %d" % t.houses.size())
	check(t.dead.size() >= 850 and t.dead.size() <= 1050, "850 to 1050 dead (700 and the street's 60 percent more, DEAD1): %d" % t.dead.size())
	var start_dead := _start_dead(t)
	check(start_dead >= 3 and start_dead <= 5, "three to five dead to clear in the (roomy) start house: %d" % start_dead)
	eq(t.rescue.size(), 12, "twelve rescue houses")
	# (a guard of two to four is what the generator tries for; a tiny cottage or shed of the town's varied buildings may have room for one: it is a guard still)
	var thin := 0
	for r in t.rescue:
		var guards: int = t.houses[int(r.house)].dead.size()
		check(guards >= 1, "a guard in rescue house %d" % int(r.house))
		if guards < 2:
			thin += 1
	check(thin <= 2, "a guard of one only in a tiny house or two: %d" % thin)
	for r in t.rescue:
		eq(TownGen.house_at(t, r.pos.x, r.pos.y), int(r.house), "the survivor is in the house")
		check(TownGen.room_at(t, r.pos.x, r.pos.y) >= 0, "and in a room")
	for h in t.houses:
		check(h.rooms.size() >= 2, "house %d has rooms" % int(h.id))
		var exterior := 0
		for d in h.doors:
			if bool(d.exterior):
				exterior += 1
			for tile in d.tiles:
				eq(int(t.data.solidZ[tile.y * 192 + tile.x]), 0, "a doorway is open")
		check(exterior >= 1, "house %d has a door to the street" % int(h.id))
	for r in t.dead:
		if int(r.room) >= 0:
			eq(TownGen.room_at(t, r.pos.x, r.pos.y), int(r.room), "a dead one's room is the room it stands in")


func test_the_doors_the_containers_and_the_survivors_can_be_walked_to_from_the_start() -> void:
	var t := _make()
	var path := Pathfinder.new(192, 192, PackedByteArray(t.data.solidP))
	var solid := PackedByteArray(t.data.solidP)
	var start: Vector2 = t.start.pos
	var lost := 0
	for h in t.houses:
		if path.find(solid, start.x, start.y, float(h.door.x) + 0.5, float(h.door.y) + 0.5).is_empty():
			lost += 1
	eq(lost, 0, "every front door has a way from the start")
	var unreachable := 0
	for c in t.containers:
		if path.find(solid, start.x, start.y, c.pos.x, c.pos.y).is_empty():
			unreachable += 1
	eq(unreachable, 0, "every container can be stood at")
	for r in t.rescue:
		check(not path.find(solid, start.x, start.y, r.pos.x, r.pos.y).is_empty(), "a way to the survivor of house %d" % int(r.house))


func test_dormant_dead_wake_near_the_avatar_sleep_far_from_it_and_a_house_can_be_cleared() -> void:
	var t := _make()
	var world = TownWorld.new()
	world.build(t.data)
	var run = TownRun.new(t, world, FxNull.new(), 30, true, true)
	var field = run.field
	var sim = run.sim
	# (a run begins at the town's entry since the arrival; this is about the dead of the start house, so she is put among them: its rooms are far apart, and only those within ten tiles wake)
	Helpers.put_among_the_dead_of_the_start_house(sim, t)
	eq(field.counts().dormant, t.dead.size(), "every one dormant at the start")
	eq(field.counts().active, 0, "and none awake")
	for i in 40:
		run.update(1.0 / 30.0)
	var c: Dictionary = field.counts()
	check(c.active >= 3 and c.active <= 30, "those near wake, never over the cap: %d" % c.active)
	var tracked := 0
	for z in sim.zombies:
		if field.rec_of.has(z):
			tracked += 1
	eq(tracked, int(c.active), "each one awake is a Sim.Zombie the field knows")
	# the dead of the start house, shot dead: the house is cleared
	var house := int(t.start.house)
	var in_house := _start_dead(t)
	check(int(field.dead_in_house(house).left) == in_house, "%d left in the start house" % in_house)
	field.wake_house(house)    # (the roomy house is wider than the wake radius: a shout wakes the rest of it, as a shot does)
	for z in sim.zombies.duplicate():
		if TownGen.house_at(t, z.x, z.y) == house:
			sim._hurt_zombie(z, 1000.0, 0.0, run.avatar_p)
	run.update(1.0 / 30.0)
	for i in 10:
		run.update(1.0 / 30.0)
	check(field.house_cleared(house), "no dead left in the start house once they are shot")
	eq(sim.kills, in_house, "and they were counted")
	# the avatar goes far away: the awake that are not after anybody go back to sleep, the killed ones stay killed
	# (the start is calm now: only those of the start house are awake, and they are killed. A far house is woken as a shout would, so that some are left behind)
	check(field.wake_house(int(t.rescue[0].house)) > 0, "a house far from the start is woken")
	run.avatar_p.x = 170.0
	run.avatar_p.y = 170.0
	for z in sim.zombies:
		if z.state == "chase":
			z.state = "wander"
	for i in 20:
		run.update(1.0 / 30.0)
	check(field.counts().killed == in_house, "the killed stay killed")
	check(field.slept_total > 0, "those left behind went to sleep")
	# the save: the same records come back
	var saved: Dictionary = field.save()
	var before: Dictionary = field.counts()
	field.sleep_all()
	field.load_state(JSON.parse_string(JSON.stringify(saved)))
	eq(field.counts().killed, before.killed, "the killed come back killed")
	world.free()


func test_the_roof_of_the_house_the_avatar_is_in_opens_and_the_others_stay_shut() -> void:
	var t := _make()
	var roofs = TownRoofs.new()
	roofs.setup(t, t.data, "house")
	roofs.update(5, 1.0)
	eq(roofs.shown, t.houses.size() - 1, "one roof open")
	check(not roofs._nodes[5].visible, "that roof is not drawn")
	check(roofs._nodes[6].visible, "the next one is")
	roofs.update(-1, 1.0)
	eq(roofs.shown, t.houses.size(), "out again, all shut")
	roofs.free()


func test_the_prison_knife_takes_two_or_three_stabs_half_a_second_apart_and_no_ammo() -> void:
	var t := _make()
	var world = TownWorld.new()
	world.build(t.data)
	var run = TownRun.new(t, world, FxNull.new(), 30, true, true)
	var sim = run.sim
	var rules = sim.avatar.melee_rules
	PrisonArms.apply_knife(rules)
	near(float(rules.cfg.cycle_s), 0.5, 0.0001, "a stab takes half a second")
	check(float(rules.cfg.noise_hit) < 6.0, "and is quiet beside a shot")
	var me = run.avatar_p
	me.mag = 0
	sim.stock.ammo = 0.0
	for hp in [4.0, 6.0]:
		var z = sim.spawn(me.x + 1.0, me.y, "wander", "walker")
		z.hp = hp
		z.limp = false
		var stabs := 0
		for k in 5:
			if z.state == "dying" or z.state == "dead":
				break
			sim.avatar.set_input(Vector2.ZERO, Vector2(me.x + 5.0, me.y), false)
			sim.avatar.melee()
			stabs += 1
			for i in 15:
				sim.update(1.0 / 30.0)
			z.x = me.x + 1.0
			z.y = me.y
		check(z.state == "dying" or z.state == "dead" or z.hp <= 0.0, "a walker of %d hp is dead" % int(hp))
		check(stabs >= 2 and stabs <= 3, "in 2 or 3 stabs (%d)" % stabs)
	world.free()


func test_the_prison_meta_files_follow_the_savefile_and_the_daily_seed_is_a_function_of_the_date() -> void:
	PrisonMeta.sf_override = "test_meta_%d" % OS.get_process_id()
	eq(PrisonMeta.path(PrisonMeta.LEGACY), "user://%s.legacy.json" % PrisonMeta.sf_override, "a named savefile has its own legacy file")
	eq(PrisonMeta.path(PrisonMeta.MILES), "user://%s.milestones.json" % PrisonMeta.sf_override, "and its own milestones")
	check(PrisonMeta.legacy().is_empty() and PrisonMeta.unlocked().is_empty(), "no files, no legacy and no milestones")
	PrisonMeta.sf_override = ""
	eq(PrisonMeta.path(PrisonMeta.LEGACY), "user://prison_legacy.json", "no savefile, the real file")
	eq(PrisonMeta.LIST.size(), 12, "twelve milestones")
	var a := PrisonMeta.daily(1760486400)
	eq(a.date, "2025-10-15", "the date is the UTC day")
	eq(PrisonMeta.daily(1760486400 + 3600).seed, a.seed, "the same day is the same seed")
	check(PrisonMeta.daily(1760486400 + 86400).seed != a.seed, "the next day is another seed")
	check(int(a.seed) >= 100000 and int(a.seed) <= 999999, "a six-digit seed")


class _SquadSim:
	func clear_shot(_a: Vector2, _b: Vector2, _r: float = 0.12) -> bool:
		return true


class _SquadGame:
	var run := {"avatar_p": {"x": 10.0, "y": 10.0, "input_aim": Vector2(16, 10)}, "sim": _SquadSim.new()}
	var world := {"W": 20, "H": 20, "solid_p": PackedByteArray()}


## Y3 (companions act weird): the spot a companion keeps beside Ruth is out of her line of fire, apart from the other one and kept while she moves a little (a deadzone); a companion holds a shot
## that would pass Ruth or the other one, and fires when the line is clear.
func test_a_companion_keeps_a_spot_out_of_ruths_fire_and_holds_a_shot_past_a_friend() -> void:
	var g := _SquadGame.new()
	var open := PackedByteArray()
	open.resize(400)
	g.world["solid_p"] = open
	var sq = load("res://scripts/prison/prison_squad.gd").new(g)
	var a := {"p": {"x": 9.0, "y": 11.0}, "state": "up", "anchor": Vector2.INF, "anchor_eff": "", "anchor_chk": 0.0}
	var b := {"p": {"x": 9.0, "y": 9.0}, "state": "up", "anchor": Vector2.INF, "anchor_eff": "", "anchor_chk": 0.0}
	sq.members = [a, b]
	var me := Vector2(10, 10)
	var sa: Vector2 = sq._slot(a, me, 0, 2.2, Vector2.ZERO, "follow", 0.016)
	var sb: Vector2 = sq._slot(b, me, 1, 2.2, Vector2.ZERO, "follow", 0.016)
	check(not sq._in_fire(me, sa, 0.6) and not sq._in_fire(me, sb, 0.6), "both spots are out of the line of fire (%s %s)" % [sa, sb])
	check(sa.distance_to(sb) >= 1.3, "the two spots are apart (%s %s)" % [sa, sb])
	check(sa.distance_to(me) > 0.8 and sa.distance_to(me) < 4.0, "beside Ruth, not on her (%s)" % sa)
	eq(sq._slot(a, me + Vector2(0.5, 0.0), 0, 2.2, Vector2.ZERO, "follow", 0.016), sa, "Ruth steps half a tile: the spot is kept")
	check(not sq._friend_in_line(a, Vector2(12, 10), Vector2(16, 10), me), "Ruth behind the shooter: the shot is clear")
	b.p = {"x": 14.0, "y": 10.2}
	check(sq._friend_in_line(a, Vector2(12, 10), Vector2(16, 10), me), "the other companion on the line: the shot is held")
	check(sq._in_fire(me, Vector2(14, 10.5), 0.35), "a spot where Ruth aims is in her line of fire")


## LEASH (playtest: Ike "attacked 3 breachers on his own"): a companion beside Ruth lets a dead one beyond the leash go (it is in their shoot range but not within the leash), and a pike
## never steps out to one that is not on Ruth (the old rule charged anything within 5 tiles of her).
func test_a_companion_does_not_chase_a_dead_one_beyond_the_leash() -> void:
	var g := _SquadGame.new()
	var sq = load("res://scripts/prison/prison_squad.gd").new(g)
	var me := Vector2(10, 10)
	var at := Vector2(12, 10)
	check(Vector2(19, 10).distance_to(at) < float(sq.cfg.shoot_r), "the far one is within their shoot range")
	check(not sq._may_engage(at, me, me, Vector2(19, 10), false), "9 tiles from Ruth, beyond the leash: let go")
	check(sq._may_engage(at, me, me, Vector2(14, 12), false), "within the leash: shot")
	check(sq._may_engage(Vector2(30, 10), me, me, Vector2(32, 10), false), "one that is on them, far off: shot (it threatens them)")
	check(not sq._may_charge(at, me, Vector2(14.5, 10), false), "a pike does not walk out to one 4.5 tiles from Ruth")
	check(sq._may_charge(at, me, Vector2(12, 11), false), "it steps up to one that is on Ruth")
	check(not sq._may_charge(Vector2(20, 10), me, Vector2(12, 11), false), "not from beyond the leash")
	var hold := Vector2(30, 30)
	check(sq._may_engage(Vector2(30, 31), hold, me, Vector2(33, 30), false), "a hold keeps its leash round its own spot")
	check(not sq._may_engage(Vector2(30, 31), hold, me, Vector2(38, 30), false), "and lets go of one beyond it")


## LEASH: a special infected in sight is called out once ("Breacher!") and is never charged; it may be shot while they fall back.
func test_a_companion_calls_out_a_special_and_never_charges_it() -> void:
	var g := _SquadGame.new()
	var sq = load("res://scripts/prison/prison_squad.gd").new(g)
	var m := {"p": {"x": 11.0, "y": 10.0}, "bark": "", "bark_t": 0.0}
	var z := {"x": 12.0, "y": 10.5}
	check(sq._call_special(m, z, "breacher"), "the first sight is called out")
	eq(m.bark, "Breacher!", "the bark names it")
	eq(sq.floaters.size(), 1, "and floats over their head")
	check(not sq._call_special(m, z, "breacher"), "the same one is called only once")
	check(not sq._may_charge(Vector2(11, 10), Vector2(10, 10), Vector2(12, 10.5), true), "a special on Ruth is not charged")
	check(sq._may_engage(Vector2(11, 10), Vector2(10, 10), Vector2(10, 10), Vector2(18, 10), true), "it is shot at while in range")
	eq(sq._eff_of("hold", false, true, false, false), "follow", "a special in sight sends even a hold back to Ruth")


## LEASH: below `retreat_hp` or with `swarm_n` dead on them, every order falls back to Ruth (a hold too); a recall leaves a hold where it is.
func test_a_hurt_companion_falls_back_whatever_the_order() -> void:
	var g := _SquadGame.new()
	var sq = load("res://scripts/prison/prison_squad.gd").new(g)
	for cmd in ["follow", "hold", "scavenge", "spread"]:
		eq(sq._eff_of(cmd, true, false, false, false), "follow", "hurt on %s: back to Ruth" % cmd)
		eq(sq._eff_of(cmd, false, true, false, false), "follow", "swarmed on %s: back to Ruth" % cmd)
	eq(sq._eff_of("hold", false, false, true, false), "hold", "a recall does not move a hold")
	eq(sq._eff_of("hold", false, false, false, false), "hold", "a calm hold holds")
	eq(sq._eff_of("scavenge", false, false, true, false), "follow", "a recalled scavenger comes back")
	check(float(sq.cfg.retreat_hp) >= 0.39 and float(sq.cfg.retreat_hp) <= 0.41, "the line is about 40 percent")


func test_the_prison_zones_look_is_saved_and_an_old_save_loads_half_clean() -> void:
	var Clean = load("res://scripts/prison/prison_clean.gd")
	var a = Clean.new(null)
	a.zc = [0.1, 0.2, 0.3, 0.4, 0.5, 1.0]
	a.kept = [0, 0, 0, 0, 1, 3]
	var b = Clean.new(null)
	b.from_dict(a.to_dict())
	eq(b.zc, a.zc, "the zones' look comes back")
	eq(b.kept, a.kept, "and the days each was kept clean")
	var old = Clean.new(null)
	old.from_dict({"spots": [], "tag": 0})
	eq(old.zc, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5], "a save from before the look loads half clean")
	eq(old.kept, [0, 0, 0, 0, 0, 0], "with no clean days")


## UI POLISH (scripts/prison/prison_ui.gd): the windows' shared look. A framed button sinks a pixel and darkens while held and comes back on release; with no display there is no motion, so a
## counter shows its new value at once and a window opened headless is whole (no fade, no slide) the frame it opens.
func test_the_prison_windows_share_one_button_and_motion_is_free_headless() -> void:
	var UI = load("res://scripts/prison/prison_ui.gd")
	check(UI.frame_box(14) != null, "the window frame exists (the chalkboard, or the flat stand-in)")
	var b: Button = UI.button("Close")
	eq(b.get_theme_font_size("font_size"), UI.BUTTON_PX, "one button size for every window")
	check(b.has_meta("ui_fb") and b.offset_transform_enabled, "the press feedback is on the button")
	b.button_down.emit()
	eq(b.offset_transform_position, Vector2(0, 1), "held: it sinks a pixel")
	check(b.self_modulate.r < 1.0, "held: it darkens")
	b.button_up.emit()
	eq(b.offset_transform_position, Vector2.ZERO, "released: back in place")
	eq(b.self_modulate, Color.WHITE, "released: its own colour")
	b.free()
	eq(UI.tick("test.count", 5.0), 5.0, "a new counter shows its value")
	eq(UI.tick("test.count", 12.0), 12.0, "headless, a changed counter shows the new value at once")
	check(not UI.ticking(), "and nothing is left counting")
	var p := PanelContainer.new()
	UI.open_fx(p)
	eq(p.modulate.a, 1.0, "a window opened with no display is not faded")
	p.free()


# ------------------------------------------------------------------ raid heat (docs/raid-heat-spec.md) --

class _HeatPeople:
	var banners: Array = []
	func banner(t: String, _c = null, _s = 0.0) -> void:
		banners.append(t)


class _HeatGame:
	var mode := "raid"
	var args := {}
	var busy := false
	var clock := 0.0
	var people := _HeatPeople.new()
	var run := {"avatar_p": {"x": 10.0, "y": 10.0}}


class _HeatNoise extends "res://scripts/prison/prison_noise.gd":
	var edge_calls: Array = []
	func _edge_horde(n: int, _to: Vector2, _speed: float) -> Dictionary:
		edge_calls.append(n)
		return {"name": "east"}
	func _loudest() -> Vector2:
		return Vector2(10, 10)
	func sting(_name: String, _at := Vector2.INF) -> void:
		pass


func _heat() -> _HeatNoise:
	var n := _HeatNoise.new(null)
	n.game = _HeatGame.new()
	return n


func test_the_raid_heat_stages_start_at_30_60_and_90() -> void:
	PrisonNoise.load_cfg()
	eq(PrisonNoise.stage_of(0.0), 0, "0 is Quiet")
	eq(PrisonNoise.stage_of(29.9), 0, "29.9 is still Quiet")
	eq(PrisonNoise.stage_of(30.0), 1, "30 is Stirring")
	eq(PrisonNoise.stage_of(60.0), 2, "60 is Hunted")
	eq(PrisonNoise.stage_of(89.9), 2, "89.9 is still Hunted")
	eq(PrisonNoise.stage_of(90.0), 3, "90 is Overrun")
	check(PrisonNoise.raid_add("shot", 16.0) > PrisonNoise.raid_add("shot", 12.0), "a shotgun adds more than a pistol")
	check(PrisonNoise.raid_add("melee", 3.0) < 0.2, "a knife blow adds almost nothing")
	var n := _heat()
	n.add_heat(35.0)
	eq(n.rstage, 1, "35 points of noise: Stirring")
	eq(n.game.people.banners, ["They're stirring"], "the banner comes once")
	n.add_heat(1.0)
	eq(n.game.people.banners.size(), 1, "and not again inside the stage")
	n.game.mode = "base"
	n.add_heat(50.0)
	eq(n.rstage, 1, "heat is a raid thing: a noise at the base adds none")


func test_raid_heat_cools_slowly_and_never_below_the_stage_reached() -> void:
	var n := _heat()
	n.add_heat(45.0)
	eq(n.rstage, 1, "Stirring")
	for i in 600:
		n._raid_heat(1.0)
	check(n.rheat < 45.0, "after ten quiet minutes it has cooled (%s)" % n.rheat)
	check(n.rheat >= 30.0, "but not below the start of Stirring (%s)" % n.rheat)
	eq(n.rstage, 1, "the stage is kept")
	var t := _heat()
	for i in 1740:
		t._raid_heat(1.0)
	eq(t.rstage, 0, "29 quiet minutes: still Quiet")
	for i in 120:
		t._raid_heat(1.0)
	eq(t.rstage, 1, "a silent raid reaches Stirring after about half an hour: the time trickle")


func test_overrun_sends_waves_until_the_party_leaves_and_hunted_sends_one_horde() -> void:
	var n := _heat()
	n.add_heat(65.0)
	eq(n.rstage, 2, "Hunted")
	eq(n.edge_calls.size(), 1, "one horde from an edge")
	n._raid_heat(1.0)
	eq(n.edge_calls.size(), 1, "and no second one while Hunted")
	n.add_heat(30.0)
	eq(n.rstage, 3, "Overrun")
	for i in 200:
		n._raid_heat(1.0)
	check(n.waves_n >= 5, "waves keep coming (%d)" % n.waves_n)
	check(n.rheat >= 90.0 and n.rstage == 3, "and it does not cool out of Overrun")
	var w: int = n.waves_n
	for i in 300:
		n._raid_heat(1.0)
	check(n.waves_n > w, "still coming until the party leaves")
	n.game.mode = "base"
	var w2: int = n.waves_n
	for i in 100:
		n._raid_heat(1.0)
	eq(n.waves_n, w2, "the waves stop when the raid is over")


class _TruckSearch:
	var looted := {}
	func is_looted(id: String) -> bool:
		return looted.has(id)


class _TruckInv:
	var searched := {}
	var version := 0
	var grids := {}
	func grid_of(id: String) -> Dictionary:
		return grids.get(id, {"cells": []})


class _TruckHouses:
	var conts := {}
	func container(id: String) -> Dictionary:
		return conts.get(id, {})


class _TruckSim:
	var stock := {"scrap": 0.0, "fuel": 0.0, "ammo": 0.0}
	var houses := _TruckHouses.new()
	var inv := _TruckInv.new()
	var search := _TruckSearch.new()


class _TruckGame:
	var args := {}
	var noise = null
	var town := {"containers": []}
	var run := {"sim": _TruckSim.new()}


func test_companions_loot_only_when_no_awake_dead_are_near_and_not_when_hunted() -> void:
	var sq = load("res://scripts/prison/prison_squad.gd").new(_TruckGame.new())
	var at := Vector2(20, 20)
	var me := Vector2(24, 20)
	check(sq.loot_clear(at, me, [], 0), "nobody about: they may search")
	check(sq.loot_clear(at, me, [], 1), "Stirring still allows it")
	check(not sq.loot_clear(at, me, [], 2), "Hunted: they stay with Ruth")
	check(not sq.loot_clear(at, me, [], 3), "Overrun: the same")
	check(not sq.loot_clear(at, me, [{"x": 20.0, "y": 29.0}], 0), "an awake dead one 9 tiles from the companion stops it")
	check(not sq.loot_clear(at, me, [{"x": 24.0, "y": 14.0}], 0), "an awake dead one 6 tiles from Ruth stops it")
	check(sq.loot_clear(at, me, [{"x": 40.0, "y": 40.0}], 0), "one far from both does not")


func test_companions_pick_only_containers_near_ruth_in_rooms_she_has_entered() -> void:
	var g := _TruckGame.new()
	g.town = {"containers": [
		{"id": "a", "house": 1, "room": 2, "pos": Vector2(12, 10), "loot": {"scrap": 3}},
		{"id": "b", "house": 1, "room": 3, "pos": Vector2(11, 10), "loot": {"scrap": 3}},
		{"id": "c", "house": 1, "room": 2, "pos": Vector2(19, 10), "loot": {"scrap": 3}}]}
	var sq = load("res://scripts/prison/prison_squad.gd").new(g)
	var m := {"skip": {}, "al": {}}
	sq.members = [m]
	var me := Vector2(10, 10)
	check(sq.loot_pick(m, me, me).is_empty(), "Ruth has not entered a room yet: nothing to search")
	sq.rooms_seen["1:2"] = true
	eq(String(sq.loot_pick(m, me, me).id), "a", "the container in her room within 5 tiles; not the other room's, not the far one")


func test_what_a_companion_finds_goes_to_the_truck_not_the_bag() -> void:
	var g := _TruckGame.new()
	var sim: _TruckSim = g.run.sim
	sim.houses.conts["c1"] = {"loot": {"scrap": 4}}
	sim.inv.grids["c1"] = {"cells": [{"item": "fuel_can", "count": 2}, {"item": "unknownthing", "count": 1}]}
	var sq = load("res://scripts/prison/prison_squad.gd").new(g)
	var m := {"name": "Ike", "p": {"x": 1.0, "y": 1.0}, "loose": {}, "bag": Inventory.make_grid(4, 2)}
	sq._take(m, "c1", true)
	eq(sim.stock.scrap, 4.0, "the scrap is in the raid's stock")
	eq(sim.stock.fuel, 2.0, "so is the fuel")
	check((m.bag.cells as Array).is_empty() and m.loose.is_empty(), "nothing went into their own bag")
	eq(sq.truck, {"scrap": 4, "fuel": 2}, "the truck's tally")
	eq((sim.inv.grids["c1"].cells as Array).size(), 1, "what the stock does not count stays in the container for Ruth")
	check(sim.search.looted.has("c1") or sim.inv.searched.has("c1"), "and it is marked as searched")
	eq(String(sq.floaters[0].text), "Ike: 4 scrap, 2 fuel", "the floater names who found what")
