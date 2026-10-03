extends "res://tests/case.gd"
## Breaches and the threat of a section (round 19, slice 3, scripts/sim/nights.gd `breach_hot`, `repair_mult`, `section_threat`,
## `contested`, `stand_for`, `update`; docs/superpowers/plans/2026-10-03-round-19.md, S3.2): a section that has fallen is "hot" while two of
## the dead are at it; a defender sent to mend a hot breach drops the order (and an alert says why) unless the avatar rallies them; and
## one number says how hard a section is pressed. Plus the saves (the module's marks, `Zombie.plated`), and that with no avatar every
## hook is neutral and throws no die.

const Helpers := preload("res://tests/helpers.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const DT := 1.0 / 30.0
## The pallet barricade on the north wall (3 places, 130 hp), the main gate, the red container (13 places) and the west school door.
const PALLETS := 1
const GATE := 2
const CONTAINER := 0
const DOOR := 14


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _seg(sim, id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


## A night game with an avatar (Ruth, far off at the south-east corner), the dead cleared away, no work and no waves.
func _game() -> Dictionary:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, 3, 22.0)
	return g


## The section has fallen: no health, state 3.
func _fall(sim, seg) -> void:
	sim._damage_segment(seg, float(seg.hp))
	check(seg.state == 3, "the %s fell" % seg.name)


## `n` of the dead standing still in `state` `d` tiles north (or, for the west wall, west) of the middle of the section.
func _dead_near(sim, seg, n: int, state: String = "breach", d: float = 3.0) -> Array:
	var out: Array = []
	for i in n:
		var z = sim.spawn(seg.center.x + float(i) * 0.4, seg.center.y - d, "wander")
		z.state = state
		z.hp = 1.0e9
		z.stagger = 1.0e9
		out.append(z)
	return out


## `n` of the dead approaching the section, each with a place there, `d` tiles from its middle.
func _approaching(sim, seg, n: int, d: float, kind: String = "walker") -> Array:
	var out: Array = []
	for i in mini(n, seg.slots.size()):
		var z = sim.spawn(seg.center.x, seg.center.y - d, "approach", kind)
		z.slot = seg.slots[i]
		seg.slots[i].who = z
		z.stagger = 1.0e9
		out.append(z)
	return out


## Nobody shoots (so nobody wakes the dead that stand still), and everyone is told to stay where they are.
func _hands_off(sim) -> void:
	for p in sim.people:
		p.reloading = 1.0e6


# ------------------------------------------------------------------------------ hot breaches --

func test_a_fallen_section_with_two_of_the_dead_at_it_is_hot() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	_fall(sim, seg)
	check(not sim.nights.breach_hot(seg), "nobody at it: cold")
	_dead_near(sim, seg, 1)
	check(not sim.nights.breach_hot(seg), "one of the dead: still cold")
	_dead_near(sim, seg, 1)
	check(sim.nights.breach_hot(seg), "two: hot")
	eq(int(NightData.num("breach.hot_n")), 2, "the plan's two")
	g.world.queue_free()


func test_a_standing_section_is_never_hot() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	_dead_near(sim, seg, 4, "attack")
	check(not sim.nights.breach_hot(seg), "it stands")
	g.world.queue_free()


func test_hot_counts_the_dead_that_are_coming_clawing_or_inside_and_within_seven_tiles() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	_fall(sim, seg)
	var near_ones := _dead_near(sim, seg, 2, "breach", 3.0)
	check(sim.nights.breach_hot(seg), "two within 3 tiles")
	var r: float = NightData.num("breach.hot_r")
	near_ones[0].y = seg.center.y - (r - 0.5)
	check(sim.nights.breach_hot(seg), "one at %.1f tiles, one at 3: still hot" % (r - 0.5))
	near_ones[0].y = seg.center.y - (r + 0.5)
	check(not sim.nights.breach_hot(seg), "one of them past %.1f tiles: cold" % r)
	near_ones[0].y = seg.center.y - 3.0
	for state in ["approach", "attack", "breach"]:
		for z in near_ones:
			z.state = state
		check(sim.nights.breach_hot(seg), "two of them in %s" % state)
	for state in ["wander", "retreat", "dying", "dead", "hunt"]:
		for z in near_ones:
			z.state = state
		check(not sim.nights.breach_hot(seg), "two of them in %s do not count" % state)
	g.world.queue_free()


func test_a_breach_is_cold_again_when_the_dead_go_back_at_dawn() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	_fall(sim, seg)
	var dead := _dead_near(sim, seg, 3)
	check(sim.nights.breach_hot(seg), "hot")
	for z in dead:
		sim.retreat(z)
	check(not sim.nights.breach_hot(seg), "they are going back: cold")
	g.world.queue_free()


func test_nothing_is_hot_without_an_avatar_or_in_a_place() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	_fall(sim, seg)
	_dead_near(sim, seg, 3)
	check(sim.nights.breach_hot(seg), "hot to begin with")
	sim.nights_on = false
	check(not sim.nights.breach_hot(seg), "not in a place's sim")
	sim.nights_on = true
	check(sim.avatar.set_player(null), "no avatar")
	check(not sim.nights.breach_hot(seg), "not without an avatar")
	g.world.queue_free()


func test_a_hot_breach_is_announced_once_a_day() -> void:
	var g := _game()
	var sim = g.sim
	_hands_off(sim)
	var seg = _seg(sim, PALLETS)
	_fall(sim, seg)
	_dead_near(sim, seg, 2)
	for i in 40:
		sim.update(DT)
	var id := "hot-%d" % PALLETS
	check(sim.alerts.has(id), "an alert says the dead are at it")
	eq(int(sim.nights.hot_marks.get(PALLETS, 0)), int(sim.day), "marked for the day")
	sim.alerts.erase(id)
	for i in 40:
		sim.update(DT)
	check(not sim.alerts.has(id), "not told again the same day")
	g.world.queue_free()


# ---------------------------------------------------------------------------------- menders --

## Dez has been sent to mend the section and stands at his place for it; nobody shoots; the avatar is wherever `lead_at` says.
func _mender(g: Dictionary, seg, lead_at: Vector2) -> Dictionary:
	var sim = g.sim
	_hands_off(sim)
	var dez = _p(sim, "dez")
	sim.order_repair(dez, seg)
	var spot: Vector2 = sim.repair_spot(seg)
	dez.x = spot.x
	dez.y = spot.y
	dez.path = []
	dez.moving = false
	dez.goal_key = ""
	var lead = sim.avatar.player()
	lead.x = lead_at.x
	lead.y = lead_at.y
	sim.stock.scrap = 40.0
	return {"dez": dez, "lead": lead, "spot": spot}


func test_a_mender_at_a_hot_breach_gives_it_up_and_says_why() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	_fall(sim, seg)
	_dead_near(sim, seg, 2)
	var m := _mender(g, seg, Vector2(60.5, 46.6))
	var scrap0: float = sim.stock.scrap
	for i in 60:
		sim.update(DT)
	check(m.dez.repair == null, "Dez dropped the order")
	near(float(seg.hp), 0.0, 1.0e-9, "nothing was mended")
	near(float(sim.stock.scrap), scrap0, 1.0e-9, "and no scrap was spent")
	var id := "nomend-%d" % PALLETS
	check(sim.alerts.has(id), "an alert says why")
	if sim.alerts.has(id):
		check(String(sim.alerts[id].text).contains("under fire"), "it says under fire: %s" % sim.alerts[id].text)
		check(String(sim.alerts[id].text).to_lower().contains(String(seg.name).to_lower()), "and which section")
		check(String(sim.alerts[id].sub).to_lower().contains("come to it"), "and what to do: %s" % sim.alerts[id].sub)
	g.world.queue_free()


func test_a_mender_works_at_a_hot_breach_while_the_avatar_rallies_them() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	_fall(sim, seg)
	_dead_near(sim, seg, 2)
	var spot: Vector2 = sim.repair_spot(seg)
	var m := _mender(g, seg, spot + Vector2(0.0, 3.0))
	var scrap0: float = sim.stock.scrap
	for i in 60:
		sim.update(DT)
	check(m.dez.repair != null, "Dez is still at it")
	check(float(seg.hp) > 5.0, "the section is being mended (%.1f hp)" % seg.hp)
	check(float(sim.stock.scrap) < scrap0, "the scrap is spent")
	check(not sim.alerts.has("nomend-%d" % PALLETS), "nobody was told that nobody will mend")
	g.world.queue_free()


func test_a_mender_works_at_a_breach_that_is_not_hot() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	_fall(sim, seg)
	_dead_near(sim, seg, 1)
	var m := _mender(g, seg, Vector2(60.5, 46.6))
	for i in 60:
		sim.update(DT)
	check(m.dez.repair != null, "Dez is still at it")
	check(float(seg.hp) > 5.0, "the section is being mended (%.1f hp)" % seg.hp)
	g.world.queue_free()


func test_repair_mult_is_nought_only_for_an_unrallied_person_at_a_hot_breach() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	var dez = _p(sim, "dez")
	var lead = sim.avatar.player()
	lead.x = 60.5
	lead.y = 46.6
	dez.x = 34.3
	dez.y = 22.0
	near(sim.nights.repair_mult(dez, seg), 1.0, 1.0e-9, "a standing wall")
	_fall(sim, seg)
	near(sim.nights.repair_mult(dez, seg), 1.0, 1.0e-9, "a breach with nobody at it")
	_dead_near(sim, seg, 2)
	lead.x = 34.3
	lead.y = 26.0
	near(sim.nights.repair_mult(dez, seg), 1.0, 1.0e-9, "the avatar rallies him")
	near(sim.nights.repair_mult(lead, seg), 1.0, 1.0e-9, "the avatar himself is not stopped")
	lead.x = 60.5
	lead.y = 46.6
	near(sim.nights.repair_mult(lead, seg), 1.0, 1.0e-9, "nor when he is far")
	dez.repair = seg
	near(sim.nights.repair_mult(dez, seg), 0.0, 1.0e-9, "nobody rallies him")
	check(dez.repair == null, "and the order is dropped")
	sim.nights_on = false
	near(sim.nights.repair_mult(dez, seg), 1.0, 1.0e-9, "in a place's sim")
	g.world.queue_free()


# ---------------------------------------------------------------------------- the threat score --

func test_a_quiet_wall_scores_nothing_and_a_door_never_scores() -> void:
	var g := _game()
	var sim = g.sim
	near(sim.nights.section_threat(_seg(sim, GATE)), 0.0, 1.0e-9, "a quiet wall")
	Helpers.attack(sim, DOOR, 5)
	near(sim.nights.section_threat(_seg(sim, DOOR)), 0.0, 1.0e-9, "a door with five of the dead at it")
	g.world.queue_free()


func test_the_threat_of_a_section_is_the_sum_of_what_presses_it() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, CONTAINER)
	Helpers.attack(sim, CONTAINER, 3)
	near(sim.nights.section_threat(seg), 3.0, 1.0e-9, "three clawing")
	_approaching(sim, seg, 2, 12.0)
	near(sim.nights.section_threat(seg), 3.0 + 2.0 * 0.35, 1.0e-9, "and two coming from 12 tiles")
	for z in sim.zombies:
		if z.state == "approach":
			z.y = seg.center.y - 30.0
	near(sim.nights.section_threat(seg), 3.0, 1.0e-9, "those past 25 tiles are not counted")
	seg.hp = seg.max_hp * 0.5
	near(sim.nights.section_threat(seg), 3.0 + 6.0 * 0.5, 1.0e-9, "half its health gone")
	seg.hp = seg.max_hp
	_dead_near(sim, seg, 2, "breach", 8.0)
	near(sim.nights.section_threat(seg), 3.0 + 2.0 * 0.8, 1.0e-9, "and two of the dead inside, within 10 tiles")
	g.world.queue_free()


func test_a_brute_weighs_five_more_whether_it_claws_or_comes() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, CONTAINER)
	Helpers.plated_brute(sim, CONTAINER)
	near(sim.nights.section_threat(seg), 1.0 + 5.0, 1.0e-9, "a brute clawing: one attacker and five")
	_approaching(sim, seg, 1, 12.0, "brute")
	near(sim.nights.section_threat(seg), 1.0 + 5.0 + 0.35 + 5.0, 1.0e-9, "and one coming")
	g.world.queue_free()


func test_a_hot_breach_adds_four() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	_fall(sim, seg)
	_dead_near(sim, seg, 2)
	# no health (6) + two of the dead inside (1.6) + hot (4)
	near(sim.nights.section_threat(seg), 6.0 + 2.0 * 0.8 + 4.0, 1.0e-9, "a hot breach")
	g.world.queue_free()


func test_a_brute_at_forty_percent_outweighs_a_quiet_wall_and_a_busy_one() -> void:
	var g := _game()
	var sim = g.sim
	var worn = _seg(sim, CONTAINER)
	worn.hp = worn.max_hp * 0.4
	Helpers.attack(sim, CONTAINER, 2)
	Helpers.plated_brute(sim, CONTAINER)
	var busy = _seg(sim, 3)
	Helpers.attack(sim, 3, 4)
	var quiet = _seg(sim, GATE)
	var a: float = sim.nights.section_threat(worn)
	var b: float = sim.nights.section_threat(busy)
	var c: float = sim.nights.section_threat(quiet)
	check(a > b and b > c, "the worn wall with the brute (%.2f) over the busy one (%.2f) over the quiet one (%.2f)" % [a, b, c])
	g.world.queue_free()


func test_the_threat_is_nought_without_an_avatar_or_in_a_place() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, CONTAINER)
	Helpers.attack(sim, CONTAINER, 3)
	check(sim.nights.section_threat(seg) > 0.0, "a threat to begin with")
	sim.nights_on = false
	near(sim.nights.section_threat(seg), 0.0, 1.0e-9, "none in a place's sim")
	check(sim.nights.contested().seg == null, "nothing contested there")
	sim.nights_on = true
	check(sim.avatar.set_player(null), "no avatar")
	near(sim.nights.section_threat(seg), 0.0, 1.0e-9, "none without an avatar")
	check(sim.nights.contested().seg == null, "nothing contested")
	g.world.queue_free()


# --------------------------------------------------------------------------------- contested --

func test_contested_is_the_most_threatened_compound_wall_or_nothing() -> void:
	var g := _game()
	var sim = g.sim
	var none: Dictionary = sim.nights.contested()
	check(none.seg == null and none.threat == 0.0, "a quiet night: nothing")
	Helpers.attack(sim, GATE, 1)
	var one: Dictionary = sim.nights.contested()
	check(one.seg == null and none.threat == 0.0, "one clawing is below 2.0: nothing")
	Helpers.attack(sim, CONTAINER, 3)
	var c: Dictionary = sim.nights.contested()
	check(c.seg != null and c.seg.id == CONTAINER, "three at the container")
	near(float(c.threat), 3.0, 1.0e-9, "its score")
	Helpers.attack(sim, 3, 6)
	var d: Dictionary = sim.nights.contested()
	check(d.seg != null and d.seg.id == 3, "six at the bus beat it")
	Helpers.attack(sim, DOOR, 9)
	var e: Dictionary = sim.nights.contested()
	check(e.seg != null and e.seg.id == 3, "a door is never contested however many are at it")
	g.world.queue_free()


# ---------------------------------------------------------------------------------- stand_for --

func test_stand_for_is_the_post_that_reaches_half_the_places_nearest_the_middle() -> void:
	var g := _game()
	var sim = g.sim
	var gun: Dictionary = sim.weapons["rifle"]
	for seg in sim.segments:
		if seg.id >= 100:
			continue
		var at: Vector2 = sim.nights.stand_for(seg, gun)
		var posts: Array = []
		for po in sim.jobs.posts():
			var pos := Vector2(po.pos)
			var reach: float = sim.reach_at(gun, pos, true)
			var within := 0
			for sl in seg.slots:
				if pos.distance_to(Vector2(sl.x, sl.y)) <= reach:
					within += 1
			if within * 2 >= seg.slots.size():
				posts.append(pos)
		if posts.is_empty():
			check(at.is_equal_approx(sim.repair_spot(seg)), "%s: no post reaches it, so the mending place" % seg.name)
			continue
		var nearest: Vector2 = posts[0]
		for pos in posts:
			if pos.distance_to(seg.center) < nearest.distance_to(seg.center):
				nearest = pos
		check(at.is_equal_approx(nearest), "%s: %s, expected %s" % [seg.name, str(at), str(nearest)])
	g.world.queue_free()


func test_stand_for_falls_back_to_the_mending_place_when_no_post_reaches() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, CONTAINER)
	var stub := {"name": "Nothing", "range": 0.5, "cooldown": 1.0, "mag": 1.0, "reload": 1.0, "dmg": 1.0, "acc": 1.0, "sound": "rifle"}
	check(sim.nights.stand_for(seg, stub).is_equal_approx(sim.repair_spot(seg)), "the mending place")
	g.world.queue_free()


# --------------------------------------------------------------------------------------- saves --

func test_the_modules_marks_and_the_plating_survive_a_save() -> void:
	var a := _game()
	var b := Helpers.avatar_game(2, 5)
	var sim = a.sim
	sim.nights.warned[PALLETS] = 3
	sim.nights.hot_marks[CONTAINER] = 3
	var z = Helpers.plated_brute(sim, GATE)
	z.hp = 24.0
	var plain = Helpers.attack(sim, CONTAINER, 1)[0]
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	check(SaveGame.apply(b.sim, d), "it applies")
	eq(b.sim.nights.warned.get(PALLETS), 3, "the warned mark")
	eq(b.sim.nights.hot_marks.get(CONTAINER), 3, "the hot mark")
	var plated := 0
	var plain_n := 0
	for q in b.sim.zombies:
		if q.kind == "brute" and q.plated:
			plated += 1
		elif q.kind == "walker" and not q.plated:
			plain_n += 1
	eq(plated, 1, "the plated brute is plated again")
	eq(plain_n, 1, "and the walker is not")
	check(plain != null, "(the walker was made)")
	a.world.queue_free()
	b.world.queue_free()


func test_a_save_from_before_loads_with_no_plating_and_no_marks() -> void:
	var a := _game()
	var b := Helpers.avatar_game(2, 5)
	Helpers.plated_brute(a.sim, GATE)
	a.sim.nights.warned[PALLETS] = 3
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(a.sim)))
	for zd in d.zombies:
		zd.erase("plated")
	d.modules.erase("nights")
	check(SaveGame.apply(b.sim, d), "a save that has neither applies")
	for q in b.sim.zombies:
		check(not q.plated, "nobody is plated")
	check(b.sim.nights.warned.is_empty() and b.sim.nights.hot_marks.is_empty(), "no marks")
	a.world.queue_free()
	b.world.queue_free()


func test_a_session_of_mending_is_not_resumed_by_a_load() -> void:
	var a := _game()
	var b := Helpers.avatar_game(2, 5)
	var sim = a.sim
	var seg = _seg(sim, PALLETS)
	seg.hp = seg.max_hp * 0.3
	var me = sim.avatar.player()
	var spot: Vector2 = sim.repair_spot(seg)
	me.x = spot.x
	me.y = spot.y
	check(bool(sim.nights.mend_wall(PALLETS).ok), "the avatar starts mending")
	eq(sim.nights.working, "wall", "it is going on")
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	check(SaveGame.apply(b.sim, d), "it applies")
	eq(b.sim.nights.working, "", "it loads as none")
	a.world.queue_free()
	b.world.queue_free()


# ------------------------------------------------------------------------------ no avatar --

func test_with_no_avatar_every_hook_is_neutral_and_throws_no_die() -> void:
	var g := _game()
	var sim = g.sim
	var seg = _seg(sim, PALLETS)
	_fall(sim, seg)
	_dead_near(sim, seg, 3)
	var z = Helpers.plated_brute(sim, GATE)
	var dez = _p(sim, "dez")
	check(sim.avatar.set_player(null), "no avatar")
	sim.rng.seed = 123
	var state: int = sim.rng.state
	check(not sim.nights.active(), "nothing applies")
	check(not sim.nights.rallied(dez), "no rally")
	near(sim.nights.aim_mult(dez), 1.0, 0.0, "aim")
	near(sim.nights.fire_mult(dez), 1.0, 0.0, "fire")
	near(sim.nights.damage_to(z, 3.7, true), 3.7, 0.0, "damage, a head hit")
	near(sim.nights.damage_to(z, 3.7, false), 3.7, 0.0, "damage, a body hit")
	check(not sim.nights.weak_hit(z, Vector2(z.x + 5.0, z.y), Vector2.LEFT), "no weak point")
	check(not sim.nights.npc_weak(z), "no weak shot")
	check(not sim.nights.breach_hot(seg), "no hot breach")
	near(sim.nights.repair_mult(dez, seg), 1.0, 0.0, "mending is as ever")
	near(sim.nights.section_threat(seg), 0.0, 0.0, "no threat")
	check(sim.nights.contested().seg == null, "nothing contested")
	check(sim.nights.wall_candidates().is_empty(), "nothing to mend by hand")
	check(not bool(sim.nights.mend_wall(PALLETS).ok), "and no mending")
	eq(sim.rng.state, state, "no die was thrown")
	for i in 40:
		sim.update(DT)
	check(sim.alerts.get("hot-%d" % PALLETS) == null, "no alert of a hot breach")
	g.world.queue_free()
