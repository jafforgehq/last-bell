extends "res://tests/case.gd"
## The harness's avatar (round 19, slice 3, docs/superpowers/plans/2026-10-03-round-19.md, H3.1): the policy stops treating the
## avatar as a worker; `--avatar=none|idle|bot` (`Balance.avatar_mode`); `NightStats`, one row for each night; and the bot that plays
## the avatar (tools/avatar_bot.gd). The rules of the nights (`sim.nights`, BREACH-SIM) may not have landed when this runs: the bot's
## tests swap in a `FakeNights` (the real class, with the threat numbers set by hand), as the plan allows.

const Helpers := preload("res://tests/helpers.gd")
const Balance := preload("res://tools/balance.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const RealNights := preload("res://scripts/sim/nights.gd")


## The nights' rules with the numbers that this file's scenes need set by hand: `threat` (segment id to threat; the one number that
## `section_threat` answers), `stand` (segment id to where a gunner covers it).
class FakeNights:
	extends "res://scripts/sim/nights.gd"
	var threat := {}
	var stand := {}

	func section_threat(seg) -> float:
		return float(threat.get(seg.id, 0.0))

	func contested() -> Dictionary:
		var best = null
		var top := 0.0
		for s in sim.segments:
			var t := section_threat(s)
			if t > top:
				top = t
				best = s
		return {"seg": best if top >= 2.0 else null, "threat": top if top >= 2.0 else 0.0}

	func stand_for(seg, gun: Dictionary) -> Vector2:
		return stand.get(seg.id, sim.repair_spot(seg))


## A fake of the avatar's E key: one "wall" candidate for `seg` (while the avatar is within `reach` tiles of `spot`), and what `use` was asked.
class FakeInteract:
	extends RefCounted
	var sim
	var seg_id := -1
	var spot := Vector2.ZERO
	var reach := 1.6
	var used: Array = []
	var working := ""

	func candidates() -> Array:
		var me = sim.avatar.player()
		if me == null or seg_id < 0 or Vector2(me.x, me.y).distance_to(spot) > reach:
			return []
		return [{"kind": "wall", "id": str(seg_id), "label": "Mend", "ok": true, "why": ""}]

	func use(cand: Dictionary = {}) -> Dictionary:
		used.append(cand)
		working = "wall"
		return {"ok": true, "kind": "wall", "id": str(seg_id)}


func _step(sim, bot, seconds: float, hz: float = 15.0) -> void:
	var dt := 1.0 / hz
	for i in int(seconds * hz):
		if bot != null:
			bot.step(dt)
		sim.update(dt)


func _compound(sim) -> Array:
	var out: Array = []
	for s in sim.segments:
		if s.kind != sim.DOOR_KIND and s.id < 100:
			out.append(s)
	return out


# ------------------------------------------------------------------ the policy --

func test_the_policy_never_gives_the_player_a_seat_an_errand_or_a_post() -> void:
	var g := Helpers.avatar_game(4, 5)
	var sim = g.sim
	var me = sim.avatar.player()
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	policy.builds = true
	check(not policy._free(me), "the player is not free to be given anything")
	# a morning of jobs and trips (food and meds are short, so a party is wanted), then the evening's placing and the alarm
	Helpers.at(sim, 2, 7.0)
	sim.waves.enabled = false
	sim.stock.food = 4.0
	sim.stock.meds = 1.0
	for i in 60 * 15:
		sim.update(1.0 / 15.0)
		if i % 15 == 0:
			policy.tick()
		if sim.jobs.job_of(me) != "":
			failures.append("the player was given a seat: %s (step %d)" % [sim.jobs.job_of(me), i])
			break
		if me.order != null or me.drafted or me.away != null or me.repair != null:
			failures.append("the player was given an order, a post, an errand or a repair (step %d)" % i)
			break
	for party in sim.scavenge.parties:
		for who in party.get("people", []):
			check(who != me, "the player is in no party")
	# the party of the morning comes home at four (round 22: the keeper opens the gate for them a few seconds before they are due, so the
	# clock is not jumped past their hour: a party that is due at once waits for the gate to open)
	Helpers.at(sim, 2, 15.8)
	for i in 8 * 15:
		sim.update(1.0 / 15.0)
		if i % 15 == 0:
			policy.tick()
	Helpers.at(sim, 2, 18.2)
	for i in 120 * 15:
		sim.update(1.0 / 15.0)
		if i % 15 == 0:
			policy.tick()
	check(not policy._placed.has(me.id), "the player is not placed on a deck with the crew")
	check(me.order == null and not me.drafted, "and has no order at dusk")
	var placed := 0
	for p in sim.people:
		if p != me and p.drafted and p.order != null:
			placed += 1
	check(placed >= 3, "the others are placed (%d)" % placed)
	g.world.free()


func test_the_jobs_are_set_without_the_player_in_the_count() -> void:
	var g := Helpers.avatar_game(5, 5)
	var sim = g.sim
	var me = sim.avatar.player()
	var policy = Balance.Policy.new(sim)
	policy.informed = true
	Helpers.at(sim, 3, 7.0)
	sim.waves.enabled = false
	for i in 20 * 15:
		sim.update(1.0 / 15.0)
		if i % 15 == 0:
			policy.tick()
	eq(sim.jobs.job_of(me), "", "no job for the player")
	for p in sim.people:
		if p != me and not (p.dead or p.turned):
			check(sim.jobs.job_of(p) != "", "%s is on a job" % p.first)
	g.world.free()


# ----------------------------------------------------------------- the flag --

func test_the_harness_with_the_idle_avatar_leaves_her_where_she_was_put_and_returns_the_nights() -> void:
	var seen := {}
	var was: String = Balance.avatar_mode
	var was_crew: int = Balance.crew_start
	Balance.avatar_mode = "idle"
	Balance.crew_start = 5
	var r: Dictionary = Balance.play(8, 1, 1, 15.0, true, func(sim): seen["sim"] = sim, false, true, true)
	Balance.avatar_mode = was
	Balance.crew_start = was_crew
	var sim = seen.sim
	var me = sim.avatar.player()
	check(me != null and String(me.id) == "ruth", "Ruth is the player")
	var spot: Vector2 = Balance.Policy.KEEP_SPOTS[5]
	check(Vector2(me.x, me.y).distance_to(spot) < 0.01, "and she is where she was put: the school gym (%.1f, %.1f)" % [me.x, me.y])
	check(r.has("nights"), "the game has its night rows")
	eq(r.nights.size(), 1, "one night was played")
	if r.nights.size() == 1:
		var row: Dictionary = r.nights[0]
		eq(int(row.day), 1, "the night of day 1")
		eq(String(row.mode), "idle", "played in the mode")
		check(float(row.avatar.present) == 0.0, "an idle avatar is never present")
		eq(int(row.avatar.shots), 0, "and fires nothing")
	check(not r.has("nights") or r.get("avatar", "") == "idle", "the game says which avatar played")


func test_without_the_flag_the_game_has_no_night_rows_and_no_player() -> void:
	eq(Balance.avatar_mode, "none", "the default is no avatar")
	var seen := {}
	var r: Dictionary = Balance.play(8, 1, 1, 15.0, true, func(sim): seen["sim"] = sim, false, true, true)
	check(not r.has("nights"), "no night rows: the output is the old one")
	check(not r.has("avatar"), "and no avatar key")
	eq(seen.sim.player_id, "", "nobody is the player")


# --------------------------------------------------------------- the night rows --

func test_night_stats_count_a_scripted_night() -> void:
	var g := Helpers.avatar_game(6, 5)
	var sim = g.sim
	sim.waves.enabled = false
	var fake := FakeNights.new()
	fake.setup(sim)
	sim.nights = fake
	var me = sim.avatar.player()
	me.x = 30.5
	me.y = 55.5
	var stats = BotLib.NightStats.new(sim, "idle")
	Helpers.at(sim, 2, 18.5)
	stats.observe(0.1)
	eq(stats.rows.size(), 0, "no row before dusk")
	var segs := _compound(sim)
	var a = segs[0]
	var b = segs[1]
	var c = segs[2]
	sim._damage_segment(c, c.hp)    # (a wall that fell in an earlier night and is still down: not a fall of this one)
	Helpers.at(sim, 2, 19.0)
	stats.observe(0.1)
	# a wall takes ten hit points; another falls; one is bitten; someone goes down; someone dies
	a.hp -= 10.0
	var b_hp: float = b.hp
	sim._damage_segment(b, b.hp)
	check(b.state == 3, "the scripted wall is down")
	stats.observe(0.1)
	Helpers.at(sim, 2, 21.0)
	fake.threat = {a.id: 4.0}
	for i in 4:
		stats.observe(0.5)
	var others: Array = []
	for p in sim.people:
		if p != me:
			others.append(p)
	sim.events.append({"type": "bite", "x": 1.0, "y": 1.0, "who": String(others[0].id)})
	others[0].downed = true
	stats.observe(0.1)
	others[1].dead = true
	stats.observe(0.1)
	# dawn comes: the first step of the next day
	sim.day = 3
	sim.phase = "day"
	sim.minutes = 7.0 * 60.0
	stats.observe(0.1)
	eq(stats.rows.size(), 1, "one row for the night")
	var row: Dictionary = stats.rows[0]
	eq(int(row.day), 2, "the night of day 2")
	eq(String(row.mode), "idle", "the mode")
	eq(String(row.kind), "ordinary", "an ordinary night")
	eq(int(row.sections_fell), 1, "one section fell")
	eq(row.fell.size(), 1, "and it is listed")
	if row.fell.size() == 1:
		eq(int(row.fell[0].seg), int(b.id), "which one")
		near(float(row.fell[0].at_hour), 19.0, 0.2, "and when")
	near(float(row.hp_lost), 10.0 + b_hp, 0.01, "the hit points the dead took (the wall that was down already took none), repairs not counted")
	eq(int(row.down_at_dusk), 1, "one section was down at dusk")
	eq(int(row.down_at_dawn), 2, "and two are at dawn")
	near(float(row.min_wall), 0.0, 0.001, "the lowest wall reached nothing")
	eq(int(row.died), 1, "one died")
	eq(int(row.downed), 1, "one went down")
	eq(int(row.bites), 1, "one bite")
	check(not bool(row.held), "so the night was not held")
	check(float(row.avatar.present) == 0.0, "the idle avatar was never within the rally of the hard-pressed wall")
	check(int(row.avatar.threat_steps) >= 4, "though it was pressed for %d samples" % int(row.avatar.threat_steps))
	eq(int(row.avatar.shots), 0, "no shots")
	check(row.has("calls") and row.has("brute_s") and row.has("ready") and row.has("size"), "every key of the row is there")
	g.world.free()


func test_a_night_with_no_fall_and_no_death_is_held_and_the_presence_follows_the_avatar() -> void:
	var g := Helpers.avatar_game(6, 5)
	var sim = g.sim
	sim.waves.enabled = false
	var fake := FakeNights.new()
	fake.setup(sim)
	sim.nights = fake
	var me = sim.avatar.player()
	var a = _compound(sim)[0]
	fake.threat = {a.id: 5.0}
	var stats = BotLib.NightStats.new(sim, "bot")
	Helpers.at(sim, 3, 19.0)
	stats.observe(0.1)
	me.x = a.center.x
	me.y = a.center.y + 3.0
	Helpers.at(sim, 3, 22.0)
	for i in 6:
		stats.observe(0.5)
	me.x = 30.5
	me.y = 55.5
	for i in 2:
		stats.observe(0.5)
	sim.day = 4
	sim.phase = "day"
	stats.observe(0.1)
	var row: Dictionary = stats.rows[0]
	check(bool(row.held), "nothing fell and nobody died: held")
	near(float(row.avatar.present), 6.0 / 8.0, 0.13, "the avatar was near the pressed wall for three quarters of the samples")
	g.world.free()


# ------------------------------------------------------------------------ the bot --

## A night, the bell rung, Ruth on the bus post of the north wall, the nights' rules faked: {"g", "sim", "me", "bot", "fake", "seg"}.
func _scene(mode := "bot") -> Dictionary:
	var g := Helpers.avatar_game(11, 5)
	var sim = g.sim
	sim.waves.enabled = false
	Helpers.at(sim, 3, 22.0)
	var fake := FakeNights.new()
	fake.setup(sim)
	sim.nights = fake
	var me = sim.avatar.player()
	var post: Dictionary = sim.jobs.post("bus")
	me.x = float(post.pos.x)
	me.y = float(post.pos.y)
	me.facing = "N"
	me.mag = int(me.gun.mag)
	var seg = _seg(sim, 3)
	fake.stand[3] = Vector2(post.pos)
	var bot = BotLib.AvatarBot.new(sim, mode)
	bot.station = {"seg": 3, "at": Vector2(post.pos), "why": "threat"}
	return {"g": g, "sim": sim, "me": me, "bot": bot, "fake": fake, "seg": seg}


func _seg(sim, id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


func _steps(bot, n: int, hz := 15.0) -> void:
	for i in n:
		bot.step(1.0 / hz)


func test_an_idle_avatar_has_no_hands_and_stays_in_the_gym() -> void:
	var g := Helpers.avatar_game(11, 5)
	var sim = g.sim
	var me = sim.avatar.player()
	var bot = BotLib.AvatarBot.new(sim, "idle")
	var spot: Vector2 = Balance.Policy.KEEP_SPOTS[5]
	check(BotLib.SAFE_SPOT.distance_to(spot) < 0.001, "the safe spot is the harness's own gym spot")
	check(Vector2(me.x, me.y).distance_to(spot) < 0.001, "she is put there")
	Helpers.at(sim, 3, 22.0)
	sim.waves.enabled = false
	for i in 90:
		bot.step(1.0 / 15.0)
		sim.update(1.0 / 15.0)
	eq(me.input_move, Vector2.ZERO, "no stick")
	check(not me.input_fire, "no trigger")
	check(Vector2(me.x, me.y).distance_to(spot) < 0.001, "and she has not moved")
	g.world.free()


func test_the_bot_stands_at_the_gate_post_by_day_and_goes_to_the_forecast_wall_from_17() -> void:
	var g := Helpers.avatar_game(12, 5)
	var sim = g.sim
	sim.waves.enabled = false
	var fake := FakeNights.new()
	fake.setup(sim)
	sim.nights = fake
	var bot = BotLib.AvatarBot.new(sim, "bot")
	Helpers.at(sim, 5, 10.0)
	_steps(bot, 20)
	eq(String(bot.station.why), "home", "by day: home")
	var gate: Vector2 = Vector2(sim.jobs.post("gate").pos)
	check(Vector2(bot.station.at).distance_to(gate) < 0.5, "at the gate post")
	# the lookout gives the forecast at 17:00
	var watch = null
	for p in sim.people:
		if p != sim.avatar.player():
			watch = p
	Helpers.at(sim, 5, 17.1)
	sim.tactics.forecast_day = 5
	sim.tactics.forecast_who = String(watch.id)
	_steps(bot, 20)
	eq(String(bot.station.why), "forecast", "from the forecast: the wall the night will break on")
	var ids: Array = []
	for s in _compound(sim):
		ids.append(s.id)
	check(ids.has(int(bot.station.seg)), "a section of the compound (%s)" % str(bot.station.seg))
	check(Vector2(bot.station.at).distance_to(fake.stand_for(_seg(sim, int(bot.station.seg)), sim.avatar.player().gun)) < 0.01, "standing where `stand_for` puts a gunner")
	# the next morning: home again
	Helpers.at(sim, 6, 9.0)
	_steps(bot, 20)
	eq(String(bot.station.why), "home", "by day again: home")
	g.world.free()


func test_the_bot_goes_to_the_most_threatened_wall_and_keeps_its_station_unless_beaten_by_the_switch_gain() -> void:
	var s := _scene()
	var sim = s.sim
	var bot = s.bot
	var fake = s.fake
	var north = _seg(sim, 3)
	var west = _seg(sim, 6)
	fake.stand[6] = Vector2(20.8, 24.0)
	fake.threat = {3: 6.0}
	_steps(bot, 10)
	eq(int(bot.station.seg), 3, "the pressed wall is the station")
	fake.threat = {3: 6.0, 6: 8.0}
	_steps(bot, 10)
	eq(int(bot.station.seg), 3, "8 does not beat 6 x %.1f + 1: it stays" % bot.SWITCH_GAIN)
	fake.threat = {3: 6.0, 6: 6.0 * bot.SWITCH_GAIN + 1.5}
	_steps(bot, 10)
	eq(int(bot.station.seg), 6, "more than that: it switches")
	eq(String(bot.station.why), "threat", "for the threat")
	check(Vector2(bot.station.at).distance_to(Vector2(20.8, 24.0)) < 0.01, "and stands where a gunner covers the west wall")
	s.g.world.free()


func test_the_bot_aims_at_a_plated_brutes_head_and_at_a_plain_ones_body_and_waits_to_react() -> void:
	var s := _scene()
	var sim = s.sim
	var me = s.me
	var bot = s.bot
	var z = Helpers.plated_brute(sim, 3)
	z.plated = true
	var head := Vector2(z.x, z.y - NightData.num("plated.head", 0.62) * float(z.size))
	var body := Vector2(z.x, z.y - 0.3)
	_steps(bot, 2)
	check(not me.input_fire, "it does not fire the moment it sees a target (%.2f s to react)" % bot.REACT_S)
	var sum := Vector2.ZERO
	var n := 0
	var fired := 0
	for i in 60:
		_steps(bot, 1)
		if me.input_fire:
			fired += 1
			sum += me.input_aim
			n += 1
			eq(me.input_move, Vector2.ZERO, "it stands still to shoot")
	check(fired > 20, "then it fires (%d of 60 steps)" % fired)
	var mean: Vector2 = sum / float(maxi(n, 1))
	check(mean.distance_to(head) < 0.3, "the aim is the head of a plated brute: %s against %s (the body is %s)" % [str(mean), str(head), str(body)])
	# a plain brute: the body
	sim.zombies.erase(z)
	z.slot.who = null
	var plain = Helpers.plated_brute(sim, 3)
	plain.plated = false
	var body2 := Vector2(plain.x, plain.y - 0.3)
	_steps(bot, 20)
	sum = Vector2.ZERO
	n = 0
	for i in 60:
		_steps(bot, 1)
		if me.input_fire:
			sum += me.input_aim
			n += 1
	check(n > 20, "it fires at a plain brute too")
	var mean2: Vector2 = sum / float(maxi(n, 1))
	check(mean2.distance_to(body2) < 0.3, "the aim is the body of a plain brute: %s against %s" % [str(mean2), str(body2)])
	s.g.world.free()


func test_the_bot_picks_a_brute_before_a_walker_and_a_breacher_near_a_person_before_a_clawer() -> void:
	var s := _scene()
	var sim = s.sim
	var bot = s.bot
	var clawers := Helpers.attack(sim, 3, 3)
	var brute = Helpers.plated_brute(sim, 3)
	brute.plated = false
	_steps(bot, 30)
	check(bot.target() == brute, "a brute first, though it is the farthest")
	sim.zombies.erase(brute)
	brute.slot.who = null
	_steps(bot, 30)
	check(clawers.has(bot.target()), "then the dead at its wall")
	# one of the dead inside the compound, near a person, beats one at the wall
	var inside = sim.spawn(44.5, 22.5, "breach")
	var near_person = null
	for p in sim.people:
		if p != s.me:
			near_person = p
	near_person.x = 45.0
	near_person.y = 22.0
	s.me.x = 47.5
	s.me.y = 18.8
	_steps(bot, 60)
	check(bot.target() == inside, "a breacher within %.0f tiles of a person comes before one at the wall" % bot.BREACH_R)
	s.g.world.free()


func test_the_bot_fires_only_with_a_line_to_a_body() -> void:
	var s := _scene()
	var sim = s.sim
	var me = s.me
	var bot = s.bot
	# Ruth in the school, one of the dead in the yard on the other side of the school's wall (a building's wall stops a shot)
	me.x = 42.5
	me.y = 46.5
	me.facing = "N"
	bot.station = {"seg": -1, "at": Vector2(42.5, 46.5), "why": "home"}
	var z = sim.spawn(42.5, 41.5, "attack")
	var fired := 0
	for i in 60:
		_steps(bot, 1)
		if me.input_fire:
			fired += 1
	check(bot.target() == z, "it has the dead one for its target (it is %.1f tiles off)" % Vector2(me.x, me.y).distance_to(Vector2(z.x, z.y)))
	eq(fired, 0, "but no shot into a wall")
	# in the yard, with the line clear, it shoots
	me.x = 42.5
	me.y = 36.5
	bot.station = {"seg": -1, "at": Vector2(42.5, 36.5), "why": "home"}
	for i in 60:
		_steps(bot, 1)
		if me.input_fire:
			fired += 1
	check(fired > 20, "with the line clear it shoots (%d)" % fired)
	s.g.world.free()


func test_the_bot_holds_its_fire_while_it_is_on_its_way() -> void:
	var s := _scene()
	var sim = s.sim
	var me = s.me
	var bot = s.bot
	Helpers.attack(sim, 3, 2)
	bot.station = {"seg": 3, "at": Vector2(sim.jobs.post("barricade").pos), "why": "call"}
	_steps(bot, 15)
	var d := Vector2(me.x, me.y).distance_to(Vector2(bot.station.at))
	check(d > bot.TRAVEL_R, "(the station is %.1f tiles away)" % d)
	check(not me.input_fire, "no shot on the way")
	check(me.input_move.length() > 0.5, "it walks")
	check(bot.destination.distance_to(Vector2(bot.station.at)) < 0.6, "to its station")
	s.g.world.free()


func test_the_bot_swings_at_a_dead_one_within_reach_and_reloads_only_in_a_lull() -> void:
	var s := _scene()
	var sim = s.sim
	var me = s.me
	var bot = s.bot
	me.mag = 2
	_steps(bot, 3)
	check(me.input_reload, "a nearly empty magazine and nothing near: it reloads")
	me.input_reload = false
	# the dead at the wall within the lull radius: it does not stop to reload
	Helpers.attack(sim, 3, 2)
	me.mag = 2
	me.input_reload = false
	_steps(bot, 3)
	check(not me.input_reload, "with the dead within %.0f tiles it keeps the gun up" % bot.LULL_R)
	# one in arm's reach: the butt
	var near = sim.spawn(me.x + 0.5, me.y + 0.6, "breach")
	me.input_melee = false
	_steps(bot, 2)
	check(me.input_melee, "a dead one within %.1f tiles is struck" % bot.MELEE_R)
	check(near != null, "(it is there)")
	s.g.world.free()


func test_the_bot_goes_to_a_bed_when_it_bleeds_and_comes_back_when_the_bleeding_stops() -> void:
	# (round 19 fix: the retreat used to wait for a health that never comes back, nothing heals a person who stands: it now lasts while the wound
	# bleeds, the medic bandages a bleeding person, and is bounded; tests/test_fix19_bot.gd plays it with the real medic)
	var s := _scene()
	var sim = s.sim
	var me = s.me
	var bot = s.bot
	Helpers.attack(sim, 3, 2)
	me.hp = bot.SAFE_HP - 10.0
	me.bleeding = 3.0
	_steps(bot, 20)
	var bed: Vector2 = Vector2.ZERO
	var bd := INF
	for b in sim.medical.beds:
		var d: float = Vector2(b.pos).distance_to(Vector2(me.x, me.y))
		if d < bd:
			bd = d
			bed = Vector2(b.pos)
	check(bot.destination.distance_to(bed) < 0.6, "the nearest bed: %s against %s" % [str(bot.destination), str(bed)])
	check(not me.input_fire, "and it fires nothing on the way")
	me.hp = bot.HURT_HP - 5.0
	_steps(bot, 20)
	check(bot.destination.distance_to(bed) < 0.6, "still bleeding at %.0f: it stays at the bed" % me.hp)
	me.bleeding = 0.0
	_steps(bot, 20)
	check(bot.destination.distance_to(Vector2(bot.station.at)) < 0.6, "the bleeding has stopped (the medic's bandage): back to its station, at %.0f health" % me.hp)
	me.hp = bot.HURT_HP - 5.0
	_steps(bot, 40)
	check(bot.destination.distance_to(Vector2(bot.station.at)) < 0.6, "a low health that does not bleed is no reason to lie down: nothing would heal it")
	me.hp = bot.SAFE_HP + 5.0
	me.bleeding = 3.0
	_steps(bot, 5)
	check(bot.destination.distance_to(Vector2(bot.station.at)) < 0.6, "(bleeding but whole: it stays on the wall)")
	s.g.world.free()


func test_the_bot_mends_a_section_that_is_down_when_no_dead_is_near_and_not_otherwise() -> void:
	var s := _scene()
	var sim = s.sim
	var me = s.me
	var bot = s.bot
	var seg = s.seg
	var it := FakeInteract.new()
	it.sim = sim
	it.seg_id = seg.id
	it.spot = sim.repair_spot(seg)
	bot.interact_override = it
	sim._damage_segment(seg, seg.hp)
	check(seg.state == 3, "the bus wall is down")
	bot.station = {"seg": 3, "at": Vector2(sim.jobs.post("bus").pos), "why": "call"}
	_steps(bot, 20)
	check(bot.destination.distance_to(it.spot) < 0.6, "it goes to where a wall is mended: %s against %s" % [str(bot.destination), str(it.spot)])
	eq(it.used.size(), 0, "not there yet: no key")
	me.x = it.spot.x
	me.y = it.spot.y + 0.3
	_steps(bot, 5)
	eq(it.used.size(), 1, "there: E, once")
	if it.used.size() == 1:
		eq(String(it.used[0].kind), "wall", "on the wall")
	_steps(bot, 30)
	eq(it.used.size(), 1, "and it does not press again while it works")
	eq(me.input_move, Vector2.ZERO, "standing still")
	# with the dead near the spot it fights instead
	it.working = ""
	it.used.clear()
	var z = sim.spawn(it.spot.x + 1.5, it.spot.y - 0.5, "breach")
	_steps(bot, 10)
	eq(it.used.size(), 0, "a dead one within %.0f tiles: no mending" % bot.MEND_CLEAR)
	sim.zombies.erase(z)
	# a wall that the dead are at is held with the gun
	var claw = Helpers.attack(sim, 3, 1)[0]
	_steps(bot, 10)
	eq(it.used.size(), 0, "nor a wall that is being clawed (the dead at its places)")
	sim.zombies.erase(claw)
	claw.slot.who = null
	# a wall that is whole is not mended
	seg.hp = seg.max_hp
	sim._repair_segment(seg, 0.0)
	_steps(bot, 10)
	eq(it.used.size(), 0, "nor a wall that stands whole")
	# and a wall under half is
	seg.hp = seg.max_hp * (bot.MEND_BELOW - 0.1)
	sim._segment_state(seg)
	it.working = ""
	me.x = it.spot.x
	me.y = it.spot.y + 0.3
	_steps(bot, 10)
	check(it.used.size() >= 1, "a wall under %.0f%% is mended" % (100.0 * bot.MEND_BELOW))
	s.g.world.free()


func test_the_bot_answers_each_call_the_way_the_plan_says() -> void:
	var s := _scene()
	var sim = s.sim
	var bot = s.bot
	var radio = sim.radio
	var seg3 = _seg(sim, 3)
	var ids := {}
	ids["going"] = radio.raise_call("going", "The north wall is going", "", [{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send two"}, {"id": "coming", "label": "I'm on my way"}, {"id": "fall_back", "label": "Fall back"}], "hold", 20.0, {"seg": 3}, seg3.center)
	ids["brute_plated"] = radio.raise_call("brute", "A plated brute at the gate", "", [{"id": "watch", "label": "Keep the guns on it"}, {"id": "coming", "label": "I'll take it"}], "watch", 45.0, {"seg": 3, "plated": true}, seg3.center)
	ids["brute_plain"] = radio.raise_call("brute", "A brute at the gate", "", [{"id": "watch", "label": "Keep the guns on it"}, {"id": "coming", "label": "I'll take it"}], "watch", 45.0, {"seg": 3, "plated": false}, seg3.center)
	ids["breach"] = radio.raise_call("breach", "The north wall is down", "", [{"id": "hold", "label": "Hold the line"}, {"id": "close", "label": "Close it"}, {"id": "coming", "label": "I'm on my way"}], "hold", 20.0, {"seg": 3}, seg3.center)
	ids["attack"] = radio.raise_call("attack", "Pallet barricade under attack", "", [{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send reinforcements"}, {"id": "fall_back", "label": "Fall back"}], "hold", 30.0, {"seg": 3}, seg3.center)
	ids["night"] = radio.raise_call("night", "The Siege", "", [{"id": "hold", "label": "Understood"}, {"id": "arms", "label": "Call to arms now"}], "hold", 600.0, {}, null)
	ids["sick"] = radio.raise_call("sick", "Dez has a fever", "", [{"id": "treat", "label": "Treat"}, {"id": "apart", "label": "Apart"}], "treat", 60.0, {"who": "dez"}, null)
	_steps(bot, 10)
	for k in ids:
		check(String(radio._entry(int(ids[k])).answered) == "", "%s: it reads the call before it answers (%.1f s)" % [k, bot.ANSWER_S])
	_steps(bot, 30)
	var want := {"going": "coming", "brute_plated": "coming", "brute_plain": "watch", "breach": "close", "attack": "hold", "night": "hold"}
	for k in want:
		var e: Dictionary = radio._entry(int(ids[k]))
		eq(String(e.answered), String(want[k]), "%s is answered `%s`" % [k, want[k]])
		check(not bool(e.by_default), "%s: by the player, not by its clock" % k)
	eq(String(radio._entry(int(ids["sick"])).answered), "", "a fever is left to the colony's own default")
	check(bot.answered >= 6, "the bot counts its answers (%d)" % bot.answered)
	# a `going` while the avatar is away has no `coming`: it reinforces
	var id2: int = radio.raise_call("going", "The east wall is going", "", [{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send two"}], "hold", 20.0, {"seg": 10}, null)
	_steps(bot, 30)
	eq(String(radio._entry(id2).answered), "reinforce", "a call with no `coming` in it (the avatar is away): reinforcements")
	s.g.world.free()


func test_the_bot_goes_to_the_wall_it_said_it_was_coming_to() -> void:
	var s := _scene()
	var sim = s.sim
	var bot = s.bot
	var fake = s.fake
	fake.stand[6] = Vector2(20.8, 24.0)
	var west = _seg(sim, 6)
	sim.radio.raise_call("going", "The west wall is going", "", [{"id": "hold", "label": "Hold"}, {"id": "coming", "label": "I'm on my way"}], "hold", 20.0, {"seg": 6}, west.center)
	fake.threat = {6: 3.0, 3: 3.0}
	_steps(bot, 50)
	eq(int(bot.station.seg), 6, "the called wall (3 + 3 for the call beats 3 by the gain)")
	eq(String(bot.station.why), "call", "for the call")
	s.g.world.free()


func test_the_bot_never_throws_the_rules_dice_and_has_its_own() -> void:
	var s := _scene()
	var sim = s.sim
	var bot = s.bot
	Helpers.attack(sim, 3, 3)
	Helpers.plated_brute(sim, 3)
	s.fake.threat = {3: 7.0}
	var before = sim.rng.state
	var own_before = bot._rng.state
	_steps(bot, 200)
	eq(sim.rng.state, before, "the rules' random state is the one it was: not one die of the game's was thrown")
	check(bot._rng.state != own_before, "the bot's own random source was used")
	s.g.world.free()


func test_the_bot_has_no_hands_while_the_avatar_is_down_or_away() -> void:
	var s := _scene()
	var sim = s.sim
	var me = s.me
	var bot = s.bot
	Helpers.attack(sim, 3, 2)
	_steps(bot, 20)
	me.downed = true
	me.input_fire = true
	me.input_move = Vector2.RIGHT
	_steps(bot, 5)
	check(not me.input_fire and me.input_move == Vector2.ZERO, "a person on the ground holds nothing")
	me.downed = false
	me.away = {"kind": "party"}
	me.input_fire = false
	me.input_move = Vector2.ZERO
	_steps(bot, 5)
	check(not me.input_fire and me.input_move == Vector2.ZERO, "and one on a trip is not played")
	me.away = null
	s.g.world.free()


func test_a_game_with_the_bot_plays_a_day_and_returns_its_night_row() -> void:
	var was: String = Balance.avatar_mode
	var was_crew: int = Balance.crew_start
	Balance.avatar_mode = "bot"
	Balance.crew_start = 5
	var r: Dictionary = Balance.play(8, 1, 1, 15.0, true, Callable(), false, true, true)
	Balance.avatar_mode = was
	Balance.crew_start = was_crew
	eq(String(r.get("avatar", "")), "bot", "the bot played")
	eq(r.nights.size(), 1, "one night")
	if r.nights.size() == 1:
		eq(String(r.nights[0].mode), "bot", "its row")
		check(r.nights[0].has("avatar") and r.nights[0].avatar.has("present"), "with the avatar's block: %s" % str(r.nights[0].avatar))


func test_the_summary_carries_the_nights_only_when_the_games_have_them() -> void:
	var g := Helpers.make(5, 1, 5)
	var row: Dictionary = Balance._row(g.sim)
	var plain := {"outcome": "survived", "day": 1, "rows": [row]}
	var with_nights := {"outcome": "survived", "day": 1, "rows": [row], "nights": [{"day": 1, "kind": "ordinary", "mode": "idle", "held": true}]}
	var a: Dictionary = Balance.summarise([plain])
	check(not a.has("games_nights"), "no avatar: the summary is the old one, key for key")
	var b: Dictionary = Balance.summarise([plain, with_nights])
	check(b.has("games_nights"), "with night rows: the summary has them")
	eq(b.games_nights.size(), 1, "one game's")
	g.world.free()
