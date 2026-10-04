extends "res://tests/case.gd"
## Fixes of the review of round 19, the weak point and the harness's bot (F6, F5).
##   F6  the plated brute's weak point: the head's disc sticks out of the body's disc (the body's is 0.42 x size round the middle of the body, the
##       head's 0.2 x size round a point 0.62 x size above the feet): a ray through the top of the head used to MISS the brute altogether and the
##       ring lit for it. `Avatar.trace` now takes a plated brute's head as part of it (`Nights.weak_along`), and the ring says "on" exactly when
##       `trace` says the pellet lands on the head: one function, not two.
##   F5  the bot's "hurt" state never ended (a standing person does not heal): it now goes to a bed only while it bleeds (the medic comes to a
##       bleeding person and bandages them), for at most `HURT_REST_S`, and does not go again for `HURT_PAUSE_S`; a low health that does not bleed
##       is fought on with, as a person who cannot heal would.
## Real rules throughout (the nights' module, the medic, the waves are off).

const AimMode := preload("res://scripts/aim_mode.gd")
const Helpers := preload("res://tests/helpers.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const NightData := preload("res://scripts/sim/night_data.gd")

const BUS := 3
const DT := 1.0 / 30.0


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _seg(sim, id: int):
	for s in sim.segments:
		if int(s.id) == id:
			return s
	return null


# ===================================================================== F6 ==

func _arena() -> Dictionary:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, 3, 22.0)
	return g


func _brute(sim, x: float, y: float) -> Variant:
	var z = sim.spawn(x, y, "wander", "brute")
	z.hp = 26.0
	z.plated = true
	z.stagger = 1.0e9
	return z


func _head_of(z) -> Vector2:
	return Vector2(z.x, z.y - NightData.num("plated.head") * float(z.size))


## A horizontal ray from the east, `dy` tiles above (up is negative y) the head's middle.
func _from_east(z, dy: float) -> Dictionary:
	var head := _head_of(z)
	return {"from": Vector2(head.x + 8.0, head.y - dy), "ang": PI}


func test_a_ray_through_the_top_of_the_head_hits_the_brute_and_the_head() -> void:
	var g := _arena()
	var sim = g.sim
	var z = _brute(sim, 36.0, 30.0)
	var r: float = NightData.num("plated.weak_r") * float(z.size)
	var body_r: float = sim.avatar.HIT_R * float(z.size)
	var head_off: float = float(z.size) * NightData.num("plated.head") - sim.avatar.BODY    # (the head's middle is this far above the body's)
	check(head_off + r > body_r + 0.05, "(the premise: the top of the head's disc is outside the body's: %.2f against %.2f)" % [head_off + r, body_r])
	# a ray 0.8 of a head radius above the head's middle: outside the body's disc, inside the head's
	var up := _from_east(z, r * 0.8)
	var hit: Dictionary = sim.avatar.trace(up.from, up.ang, 12.0)
	check(hit.z == z, "the pellet that passes through the top of the head lands on the brute (it used to go on past it)")
	check(bool(hit.weak), "and it is a head hit")
	# a ray past the head's disc and outside the body's: nothing
	var past := _from_east(z, r * 1.2 + 0.4)
	var miss: Dictionary = sim.avatar.trace(past.from, past.ang, 12.0)
	check(miss.z == null or (miss.z == z and not bool(miss.weak)), "past the head's edge it is no head hit")
	var far := _from_east(z, head_off + body_r + 0.6)
	check(sim.avatar.trace(far.from, far.ang, 12.0).z == null, "and well above the brute: no hit at all")
	# the belly: the body's disc, not the head
	var belly: Dictionary = sim.avatar.trace(Vector2(z.x + 8.0, z.y - sim.avatar.BODY), PI, 12.0)
	check(belly.z == z and not bool(belly.weak), "at the belly: a body hit")
	g.world.queue_free()


func test_a_plain_brute_has_no_head_to_hit_outside_its_body() -> void:
	var g := _arena()
	var sim = g.sim
	var z = _brute(sim, 36.0, 30.0)
	z.plated = false
	var head := _head_of(z)
	var r: float = NightData.num("plated.weak_r") * float(z.size)
	var up: Dictionary = sim.avatar.trace(Vector2(head.x + 8.0, head.y - r * 0.8), PI, 12.0)
	check(up.z == null, "a plain brute: the same ray goes past it (no head disc)")
	g.world.queue_free()


func test_the_traces_head_hit_is_the_weak_hit_of_the_rules_for_any_ray() -> void:
	var g := _arena()
	var sim = g.sim
	var z = _brute(sim, 36.0, 30.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var disagree := 0
	var heads := 0
	for i in 400:
		var from := Vector2(z.x + rng.randf_range(3.0, 9.0), z.y + rng.randf_range(-3.0, 3.0))
		var ang := (Vector2(z.x, z.y - 0.6) - from).angle() + rng.randf_range(-0.35, 0.35)
		var res: Dictionary = sim.avatar.trace(from, ang, 14.0)
		var rules: bool = sim.nights.weak_hit(z, from, Vector2.from_angle(ang))
		if bool(res.weak) != (res.z == z and rules):
			disagree += 1
		if bool(res.weak):
			heads += 1
			check(res.z == z, "a head hit is a hit on the brute")
	eq(disagree, 0, "trace and the rules agree on every ray")
	check(heads > 20, "(the rays do hit the head now and then: %d)" % heads)
	g.world.queue_free()


func test_the_ring_is_on_exactly_when_the_shot_would_land_on_the_head() -> void:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true}, 1280, 800)
	AimMode.set_mode("always")    # (round 22: the ring lights only while the player aims; with "always" the mouse aims by itself, as this test sets the aim by hand)
	var sim = main.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, 3, 22.0)
	sim.stock.ammo = 100.0
	var me = sim.avatar.player()
	var brute = _brute(sim, 40.0, 30.0)
	var size := float(brute.size)
	var r: float = NightData.num("plated.weak_r") * size
	var head := _head_of(brute)
	# the avatar stands east of it at the height of its head, the gun up, as one shoots a brute at a wall from the yard (the body's disc and the
	# head's do not line up from the side: a shot from the south hides the hole)
	me.x = 46.0
	me.y = head.y + 0.5
	me.path = []
	me.moving = false
	me.facing = "W"
	me.mag = int(me.gun.mag)
	main.cam_center = Vector2(43.0, 30.0)
	main.zoom_px = 40.0
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()
	var mismatches := 0
	var lit := 0
	var asked := 0
	var outside := 0    # aims in the head's disc that are outside the body's: they used to light the ring and miss
	var head_off: float = size * NightData.num("plated.head") - sim.avatar.BODY
	# aims on a column above and below the head's middle (the top of the head's disc is outside the body's disc)
	for k in range(-14, 15):
		var at := Vector2(head.x, head.y + float(k) * r / 7.0)
		me.aim = (at - sim.avatar.shoulder(me)).angle()
		main.overlay.forget_night()
		main.overlay.queue_redraw()
		await TutorialKit.settle()
		var res: Dictionary = sim.avatar.trace(sim.avatar.shoulder(me), float(me.aim), sim.reach_of(sim.gun_of(me), me))
		var truth: bool = res.z == brute and bool(res.weak)
		if main.overlay.weak_marks.is_empty():
			continue
		asked += 1
		var ring: Dictionary = main.overlay.weak_marks[0]
		if bool(ring.on) != truth:
			mismatches += 1
		lit += 1 if bool(ring.on) else 0
		if truth and absf(float(k) * r / 7.0) > 0.0 and (head_off + absf(float(k) * r / 7.0) > sim.avatar.HIT_R * size):
			outside += 1
	check(asked >= 20, "(the ring was drawn for the aims: %d)" % asked)
	eq(mismatches, 0, "the ring is full exactly when the trace says the pellet lands on the head")
	check(lit >= 4, "(and it is full for some of them: %d)" % lit)
	check(outside >= 1, "(and for some that only the head's disc, not the body's, covers: %d)" % outside)
	# a melee weapon has no weak point: the butt strikes the body
	sim.stock.ammo = 0.0
	main.overlay.forget_night()
	main.overlay.queue_redraw()
	await TutorialKit.settle()
	check(main.overlay.weak_marks.is_empty() or not bool(main.overlay.weak_marks[0].on), "with no ammunition (the butt) the ring is never full")
	await TutorialKit.leave(main)


# ===================================================================== F5 ==

## A real night at the bus with the bot in Ruth's hands: the nights' module, the medic and the beds are the game's own.
func _night() -> Dictionary:
	var g := Helpers.avatar_game(11, 5)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, 3, 22.0)
	var me = sim.avatar.player()
	var post: Dictionary = sim.jobs.post("bus")
	me.x = float(post.pos.x)
	me.y = float(post.pos.y)
	me.path = []
	me.facing = "N"
	me.mag = int(me.gun.mag)
	sim.stock.ammo = 200.0
	var bot = BotLib.AvatarBot.new(sim, "bot")
	bot.station = {"seg": BUS, "at": Vector2(post.pos), "why": "threat"}
	return {"g": g, "sim": sim, "me": me, "bot": bot, "post": Vector2(post.pos)}


func _play(m: Dictionary, seconds: float, hz: float = 15.0) -> void:
	for i in int(seconds * hz):
		m.bot.step(1.0 / hz)
		m.sim.update(1.0 / hz)


func _bed_of(sim, me) -> Vector2:
	var bed := Vector2.ZERO
	var best := INF
	for b in sim.medical.beds:
		var d: float = Vector2(b.pos).distance_to(Vector2(me.x, me.y))
		if d < best:
			best = d
			bed = Vector2(b.pos)
	return bed


func test_a_standing_wound_that_does_not_bleed_does_not_send_the_bot_to_a_bed_forever() -> void:
	var m := _night()
	var sim = m.sim
	var me = m.me
	var bot = m.bot
	Helpers.attack(sim, BUS, 3)
	me.hp = bot.HURT_HP - 3.0
	me.bleeding = 0.0
	var shots: int = int(me.stats.shots)
	_play(m, 12.0)
	check(bot.destination.distance_to(m.post) < 1.0, "42 health, no bleeding: it is at its wall (%s, wall %s)" % [str(bot.destination), str(m.post)])
	check(int(me.stats.shots) > shots, "and it fires: %d shots" % (int(me.stats.shots) - shots))
	near(me.hp, bot.HURT_HP - 3.0, 0.01, "(nothing heals a person who stands: the health is what it was)")
	m.g.world.free()


func test_a_bleeding_bot_goes_to_a_bed_the_medic_bandages_it_and_it_goes_back() -> void:
	var m := _night()
	var sim = m.sim
	var me = m.me
	var bot = m.bot
	sim.stock.meds = 10.0
	sim.medical.add_wound(me, "bite")
	me.hp = bot.SAFE_HP - 15.0
	check(float(me.bleeding) > 0.0, "it bleeds")
	_play(m, 2.0)
	var bed := _bed_of(sim, me)
	check(bot.destination.distance_to(bed) < 0.7, "bleeding below %.0f: the nearest bed (%s against %s)" % [bot.SAFE_HP, str(bot.destination), str(bed)])
	var t := 0.0
	while float(me.bleeding) > 0.0 and t < bot.HURT_REST_S:
		_play(m, 1.0)
		t += 1.0
	check(float(me.bleeding) <= 0.0, "the medic has bandaged it within %.0f seconds (it took %.0f)" % [bot.HURT_REST_S, t])
	_play(m, 3.0)
	check(bot.destination.distance_to(m.post) < 1.0, "and it is back at its wall, not waiting for health that does not come: %s" % str(bot.destination))
	check(float(me.hp) < bot.SAFE_HP, "(its health is not back: %.0f)" % float(me.hp))
	m.g.world.free()


func test_a_bot_that_nobody_bandages_goes_back_after_a_bounded_rest_and_does_not_go_at_once_again() -> void:
	var m := _night()
	var sim = m.sim
	var me = m.me
	var bot = m.bot
	sim.stock.meds = 0.0    # (nothing to bandage with)
	sim.medical.add_wound(me, "bite")
	me.hp = bot.SAFE_HP - 10.0
	me.bleeding = 0.5
	_play(m, 2.0)
	var bed := _bed_of(sim, me)
	check(bot.destination.distance_to(bed) < 0.7, "it goes to the bed")
	_play(m, bot.HURT_REST_S + 2.0)
	check(bot.destination.distance_to(m.post) < 1.0, "after %.0f seconds it is back at its wall, bleeding or not: %s" % [bot.HURT_REST_S, str(bot.destination)])
	_play(m, 4.0)
	check(bot.destination.distance_to(m.post) < 1.0, "and it does not go again at once")
	m.g.world.free()


func test_the_retreat_is_counted_in_the_nights_row_as_hurt_seconds() -> void:
	var m := _night()
	var sim = m.sim
	var me = m.me
	var stats = BotLib.NightStats.new(sim, "bot")
	Helpers.at(sim, 3, 19.2)    # (the bell has rung: a night's row is open)
	sim.bell_rung = true
	var steps := 0
	me.hp = 30.0    # (below the hurt line, not bleeding)
	for i in 120:
		m.bot.step(1.0 / 15.0)
		sim.update(1.0 / 15.0)
		stats.observe(1.0 / 15.0)
		steps += 1
	var row: Dictionary = stats.row()
	var av: Dictionary = row.get("avatar", {})
	check(float(av.get("hurt_s", -1.0)) > 5.0, "the row says how long it was played hurt: %s" % str(av.get("hurt_s")))
	var cell: Dictionary = BotLib.aggregate([row])
	check(float(cell.get("av_hurt", -1.0)) >= 0.0, "and the cell has the share of nights played hurt: %s" % str(cell.get("av_hurt")))
	check(BotLib.table_header().contains("hurt"), "which the table prints")
	check(steps == 120, "(steps)")
	m.g.world.free()
