extends "res://tests/case.gd"
## Plated brutes (round 19, slice 3, scripts/sim/nights.gd `damage_to`, `weak_hit`, `npc_weak`; avatar.gd `trace`, `_shoot`, `_strike`;
## docs/superpowers/plans/2026-10-03-round-19.md, S3.2): a brute of a Big Night is armoured but for its head. A body hit does `plated.armour`
## of its damage, a hit on the head `plated.weak_mult` times; the avatar aims, so he finds the head (`weak_hit`: the pellet's ray passes
## within `plated.weak_r` x size of the head's centre), a defender's carbine finds it by luck (`npc_weak`, one die per shot at a plated
## brute and none for anything else). A plain brute or a walker is not changed, and nothing of it applies with no avatar or in a place's
## sim. "Needs the player" means a brute is not unkillable for the community: it draws the guns for several times as long.

const Helpers := preload("res://tests/helpers.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const DT := 1.0 / 30.0
const ARENA := Rect2i(26, 20, 24, 10)


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## A night game with an avatar (Ruth) and the dead cleared away; `sim.waves` off so that nothing else comes.
func _game() -> Dictionary:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, 3, 22.0)
	return g


## A brute standing still at (x, y), `plated` or not, with its hit points set.
func _brute(sim, x: float, y: float, plated: bool, hp: float = 26.0):
	var z = sim.spawn(x, y, "wander", "brute")
	z.hp = hp
	z.plated = plated
	z.stagger = 1.0e9
	return z


func _head_of(z) -> Vector2:
	return Vector2(z.x, z.y - NightData.num("plated.head") * float(z.size))


# ------------------------------------------------------------------------- damage_to --

func test_a_plated_brute_takes_a_fifth_on_the_body_and_triple_on_the_head() -> void:
	var g := _game()
	var sim = g.sim
	var z = _brute(sim, 40.0, 30.0, true)
	near(sim.nights.damage_to(z, 2.0, false), 2.0 * NightData.num("plated.armour"), 1.0e-9, "a body hit")
	near(sim.nights.damage_to(z, 2.0, true), 2.0 * NightData.num("plated.weak_mult"), 1.0e-9, "a head hit")
	near(NightData.num("plated.armour"), 0.2, 1.0e-9, "the plan's armour")
	near(NightData.num("plated.weak_mult"), 3.0, 1.0e-9, "the plan's weak point")
	g.world.queue_free()


func test_a_plain_brute_and_a_walker_are_not_changed() -> void:
	var g := _game()
	var sim = g.sim
	var plain = _brute(sim, 40.0, 30.0, false)
	var walker = sim.spawn(41.0, 30.0, "wander")
	for weak in [false, true]:
		near(sim.nights.damage_to(plain, 2.0, weak), 2.0, 1.0e-9, "a plain brute (weak %s)" % str(weak))
		near(sim.nights.damage_to(walker, 2.0, weak), 2.0, 1.0e-9, "a walker (weak %s)" % str(weak))
	g.world.queue_free()


func test_plating_needs_an_avatar_and_a_base() -> void:
	var g := _game()
	var sim = g.sim
	var z = _brute(sim, 40.0, 30.0, true)
	sim.nights_on = false
	near(sim.nights.damage_to(z, 2.0, false), 2.0, 1.0e-9, "in a place's sim: not plated")
	near(sim.nights.damage_to(z, 2.0, true), 2.0, 1.0e-9, "in a place's sim: no weak point either")
	sim.nights_on = true
	check(sim.avatar.set_player(null), "no avatar")
	near(sim.nights.damage_to(z, 2.0, false), 2.0, 1.0e-9, "with no avatar: not plated")
	check(not sim.nights.weak_hit(z, Vector2(45.0, z.y), Vector2.LEFT), "with no avatar: no weak point")
	check(not sim.nights.npc_weak(z), "with no avatar: no weak shot")
	g.world.queue_free()


# --------------------------------------------------------------------------- weak_hit --

func test_weak_hit_is_a_ray_through_the_head_disc() -> void:
	var g := _game()
	var sim = g.sim
	var z = _brute(sim, 40.0, 30.0, true)
	var head := _head_of(z)
	var r: float = NightData.num("plated.weak_r") * float(z.size)
	# from the east, level with the head
	check(sim.nights.weak_hit(z, Vector2(46.0, head.y), Vector2.LEFT), "from the east, through the head")
	check(sim.nights.weak_hit(z, Vector2(46.0, head.y + r * 0.8), Vector2.LEFT), "from the east, near the edge inside")
	check(not sim.nights.weak_hit(z, Vector2(46.0, head.y + r * 1.3), Vector2.LEFT), "from the east, just past the edge")
	check(not sim.nights.weak_hit(z, Vector2(46.0, z.y - 0.3), Vector2.LEFT), "from the east, at the belly")
	# from the south, going north
	check(sim.nights.weak_hit(z, Vector2(z.x, 36.0), Vector2.UP), "from the south, through the head")
	check(sim.nights.weak_hit(z, Vector2(z.x + r * 0.8, 36.0), Vector2.UP), "from the south, off the middle but inside the disc")
	check(not sim.nights.weak_hit(z, Vector2(z.x + r * 1.3, 36.0), Vector2.UP), "from the south, beside the head")
	# a ray going the other way, away from the head
	check(not sim.nights.weak_hit(z, Vector2(46.0, head.y), Vector2.RIGHT), "a ray that points away")
	# a slanting one: from the south-east at the head's centre, and the same with a long direction vector
	var from := Vector2(44.0, 34.0)
	check(sim.nights.weak_hit(z, from, (head - from) * 3.0), "slanting, through the head (any length of direction)")
	g.world.queue_free()


func test_only_a_plated_brute_has_a_weak_point() -> void:
	var g := _game()
	var sim = g.sim
	var plain = _brute(sim, 40.0, 30.0, false)
	var walker = sim.spawn(44.0, 30.0, "wander")
	check(not sim.nights.weak_hit(plain, Vector2(46.0, _head_of(plain).y), Vector2.LEFT), "a plain brute")
	check(not sim.nights.weak_hit(walker, Vector2(48.0, walker.y - NightData.num("plated.head")), Vector2.LEFT), "a walker")
	g.world.queue_free()


func test_trace_says_whether_the_ray_found_the_head() -> void:
	var g := _game()
	var sim = g.sim
	var z = _brute(sim, 40.0, 30.0, true)
	var head := _head_of(z)
	var level: Dictionary = sim.avatar.trace(Vector2(46.0, head.y), PI, 10.0)
	check(level.z == z and level.weak, "a ray level with the head: the brute, weak")
	var belly: Dictionary = sim.avatar.trace(Vector2(46.0, z.y - 0.3), PI, 10.0)
	check(belly.z == z and not belly.weak, "a ray at the belly: the brute, not weak")
	var miss: Dictionary = sim.avatar.trace(Vector2(46.0, 20.0), PI, 10.0)
	check(miss.z == null and not miss.weak, "nothing hit: not weak")
	var plain = _brute(sim, 40.0, 25.0, false)
	var ray: Dictionary = sim.avatar.trace(Vector2(46.0, _head_of(plain).y), PI, 10.0)
	check(ray.z == plain and not ray.weak, "a plain brute has no weak point")
	g.world.queue_free()


# ---------------------------------------------------------------------------- npc_weak --

func test_a_defenders_weak_shot_is_one_die_in_a_dozen_and_only_for_a_plated_brute() -> void:
	var g := _game()
	var sim = g.sim
	var z = _brute(sim, 40.0, 30.0, true)
	sim.rng.seed = 77
	var weak := 0
	for i in 400:
		if sim.nights.npc_weak(z):
			weak += 1
	check(weak >= 16 and weak <= 48, "%d of 400 shots found the head (about %d expected)" % [weak, int(400.0 * NightData.num("plated.npc_weak"))])
	# no die for anything else
	var plain = _brute(sim, 41.0, 30.0, false)
	var walker = sim.spawn(42.0, 30.0, "wander")
	sim.rng.seed = 5
	var state: int = sim.rng.state
	for i in 20:
		check(not sim.nights.npc_weak(plain), "a plain brute: never")
		check(not sim.nights.npc_weak(walker), "a walker: never")
	eq(sim.rng.state, state, "no die was thrown for them")
	# and none when the rules do not apply
	sim.nights_on = false
	check(not sim.nights.npc_weak(z), "in a place's sim: never")
	eq(sim.rng.state, state, "and no die")
	g.world.queue_free()


# ------------------------------------------------------------------------ the avatar's hands --

## The arena of test_avatar: open ground in the yard, so that a line is clear.
func _carve(g: Dictionary) -> void:
	for ty in range(ARENA.position.y, ARENA.end.y):
		for tx in range(ARENA.position.x, ARENA.end.x):
			g.world.solid_p[ty * g.world.W + tx] = 0
			g.world.solid_z[ty * g.world.W + tx] = 0


## Ruth at (30.5, 25.5) with a gun of her own making that never spreads, one pellet of `dmg`, aimed at the point `at`.
func _aimed(g: Dictionary, at: Vector2, dmg: float = 2.0, pellets: int = 1) -> Dictionary:
	_carve(g)
	var sim = g.sim
	var p = sim.avatar.player()
	p.x = 30.5
	p.y = 25.5
	p.facing = "E"
	var gun := {"name": "Test gun", "range": 30.0, "cooldown": 0.2, "mag": 50.0, "reload": 1.0, "dmg": dmg, "pellets": float(pellets), "spread": 0.0, "acc": 1.0, "sound": "rifle"}
	p.gun = gun
	p.mag = 50
	p.cooldown = 0.0
	p.reloading = 0.0
	sim.stock.ammo = 1000.0
	p.aim = (at - sim.avatar.shoulder(p)).angle()
	return {"gun": gun, "p": p}


func test_the_avatars_aimed_pellet_does_triple_on_the_head_and_a_fifth_on_the_body() -> void:
	var g := _game()
	var sim = g.sim
	var z = _brute(sim, 40.5, 25.5, true, 100.0)
	var a := _aimed(g, _head_of(z))
	sim.avatar._shoot(a.p, a.gun)
	near(100.0 - z.hp, 2.0 * NightData.num("plated.weak_mult"), 1.0e-6, "a pellet at the head")
	var b := _aimed(g, Vector2(z.x, z.y - 0.3))
	var before: float = z.hp
	sim.avatar._shoot(b.p, b.gun)
	near(before - z.hp, 2.0 * NightData.num("plated.armour"), 1.0e-6, "a pellet at the body")
	g.world.queue_free()


func test_a_plain_brute_takes_the_whole_pellet_wherever_it_lands() -> void:
	var g := _game()
	var sim = g.sim
	var z = _brute(sim, 40.5, 25.5, false, 100.0)
	var a := _aimed(g, _head_of(z))
	sim.avatar._shoot(a.p, a.gun)
	near(100.0 - z.hp, 2.0, 1.0e-6, "at the head")
	var before: float = z.hp
	var b := _aimed(g, Vector2(z.x, z.y - 0.3))
	sim.avatar._shoot(b.p, b.gun)
	near(before - z.hp, 2.0, 1.0e-6, "at the body")
	g.world.queue_free()


func test_each_pellet_of_a_shell_counts_by_where_it_went() -> void:
	# five pellets at the head, one volley: five times the head's damage
	var g := _game()
	var sim = g.sim
	var z = _brute(sim, 40.5, 25.5, true, 100.0)
	var a := _aimed(g, _head_of(z), 1.0, 5)
	sim.avatar._shoot(a.p, a.gun)
	near(100.0 - z.hp, 5.0 * NightData.num("plated.weak_mult"), 1.0e-6, "five pellets at the head")
	g.world.queue_free()


func test_a_blow_in_melee_meets_the_armour() -> void:
	var g := _game()
	var sim = g.sim
	var p = sim.avatar.player()
	p.x = 40.5
	p.y = 25.5
	p.aim = 0.0
	var z = _brute(sim, 41.5, 25.5, true, 100.0)
	var hits: int = sim.avatar._strike(p, 1.5, PI / 2.0, 5.0)
	eq(hits, 1, "it struck the brute")
	near(100.0 - z.hp, 5.0 * NightData.num("plated.armour"), 1.0e-6, "a blow does the armoured share")
	var plain = _brute(sim, 40.5, 24.5, false, 100.0)
	p.aim = -PI / 2.0
	sim.avatar._strike(p, 1.5, PI / 8.0, 5.0)
	near(100.0 - plain.hp, 5.0, 1.0e-6, "a plain one takes the whole blow")
	g.world.queue_free()


# --------------------------------------------------------------------------- the defenders --

## A defender's carbine fired many times at a brute, plated or plain: the hit points it took off.
func _volley(plated: bool, seed_value: int, shots: int = 1200) -> float:
	var g := _game()
	var sim = g.sim
	var dez = _p(sim, "dez")
	dez.x = 40.5
	dez.y = 30.5
	var z = _brute(sim, 45.5, 30.5, plated, 1.0e9)
	sim.stock.ammo = 1.0e6
	sim.rng.seed = seed_value
	for i in shots:
		dez.mag = 20
		dez.cooldown = 0.0
		sim._fire(dez, z, 0.0)
	var taken := 1.0e9 - float(z.hp)
	g.world.queue_free()
	return taken


func test_a_defenders_carbine_does_about_two_fifths_against_a_plated_brute() -> void:
	var plain := _volley(false, 11)
	var plated := _volley(true, 11)
	var ratio := plated / plain
	var armour: float = NightData.num("plated.armour")
	var weak: float = NightData.num("plated.weak_mult")
	var p_weak: float = NightData.num("plated.npc_weak")
	var expect := (1.0 - p_weak) * armour + p_weak * weak
	check(absf(ratio - expect) < 0.08, "plated/plain damage %.3f, about %.3f expected" % [ratio, expect])
	check(ratio < 0.6, "a plated brute takes well under the plain share (%.2f)" % ratio)


# --------------------------------------------------------------------------------- the duel --

## Three defenders on the north wall against one brute clawing at the barricade (a plated one or a plain one), the section made too strong
## to fall: the seconds until the brute is down (cut off at `limit`).
func _duel(plated: bool, seed_value: int, limit: float = 90.0) -> float:
	var g := _game()
	var sim = g.sim
	sim.rng.seed = seed_value
	var z = Helpers.plated_brute(sim, 1)
	for s in sim.segments:
		if s.id == 1:
			s.max_hp = 1.0e7
			s.hp = 1.0e7
	z.hp = 26.0
	z.plated = plated
	var posts := {"dez": "gate", "walt": "barricade", "marcus": "north_west", "ana": "west_south"}
	for id in posts:
		var p = _p(sim, id)
		sim.jobs.post_ids[id] = posts[id]
		var at: Vector2 = sim.jobs.post(posts[id]).pos
		p.x = at.x
		p.y = at.y
		p.goal_key = ""
		p.path = []
		p.mag = int(p.gun.mag)
	var me = sim.avatar.player()
	me.x = 60.5
	me.y = 46.6
	var t := 0.0
	while t < limit and z.state != "dying" and z.state != "dead":
		sim.update(DT)
		t += DT
	g.world.queue_free()
	return t


func test_a_lone_plated_brute_lives_several_times_as_long_under_the_communitys_fire() -> void:
	# one duel is a handful of chunky hits (a hunting rifle's head hit is half the brute): the mean of sixteen is the number
	var plain := 0.0
	var plated := 0.0
	var n := 16
	for s in range(1, n + 1):
		plain += _duel(false, s)
		plated += _duel(true, s)
	check(plain > 0.0 and plated >= 2.5 * plain, "plated lives %.1f s against %.1f s for a plain one (x%.2f)" % [plated / float(n), plain / float(n), plated / maxf(plain, 0.001)])


## The avatar alone, aiming at the head of a plated brute `dist` tiles away (26 hit points: the middle of its range): the seconds until it is
## down, the aim a hair off by the gun's own scatter.
func _head_shots(seed_value: int, weapon: String, dist: float) -> float:
	var g := _game()
	var sim = g.sim
	_carve(g)
	sim.rng.seed = seed_value
	var p = sim.avatar.player()
	p.weapon = weapon
	p.gun = sim.weapons[weapon]
	p.mag = int(p.gun.mag)
	p.x = 30.5
	p.y = 25.5
	sim.stock.ammo = 1000.0
	var z = _brute(sim, p.x + dist, 25.5, true, 26.0)
	var t := 0.0
	while t < 30.0 and z.state != "dying":
		sim.avatar.set_input(Vector2.ZERO, _head_of(z), true)
		sim.avatar.update(p, DT)
		t += DT
	g.world.queue_free()
	return t


func test_the_avatars_head_hits_put_a_plated_brute_down_in_eight_seconds() -> void:
	for pair in [["rifle", 6.0], ["shotgun", 4.0]]:
		var total := 0.0
		var n := 6
		for s in range(1, n + 1):
			total += _head_shots(s, String(pair[0]), float(pair[1]))
		check(total / float(n) <= 8.0, "the %s at %.0f tiles: down in %.1f s on average" % [pair[0], pair[1], total / float(n)])
