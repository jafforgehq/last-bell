extends "res://tests/case.gd"
## The avatar mends a wall by hand (round 19, slice 3, scripts/sim/nights.gd `wall_candidates`, `mend_wall`, `stop_mend`, `after_people`;
## docs/superpowers/plans/2026-10-03-round-19.md, S3.2): the E candidate of kind "wall" ("Mend the Red container (35%)") within `mend.reach` tiles
## of the section's mending place, and the session like the bench's: `mend.seconds` of rules time at the rate of any repairer, through the
## scrap, with the section's state following (a fallen one shuts again above 40%), Building and morale credited, under fire allowed; it ends
## on walking, the trigger, a wound, a fall, a whole wall, no scrap or the seconds up; refused with a reason. (round 18's Interact, where the
## key is read, is another branch: the candidates here have its dictionary shape and the merge adds them to its list.)

const Helpers := preload("res://tests/helpers.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const DT := 1.0 / 30.0
const PALLETS := 1
const CONTAINER := 0
const DOOR := 14


func _seg(sim, id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


## A night game with the avatar (Ruth) standing at the mending place of the section `seg_id`, which is at `share` of its health; nobody
## shoots, nobody works, the dead are away, 40 scrap in store. Returns {"g", "sim", "me", "seg", "spot"}.
func _game(seg_id: int = PALLETS, share: float = 0.35) -> Dictionary:
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, 3, 22.0)
	for p in sim.people:
		p.reloading = 1.0e6
	var seg = _seg(sim, seg_id)
	seg.hp = seg.max_hp * share
	sim._segment_state(seg)
	var me = sim.avatar.player()
	var spot: Vector2 = sim.repair_spot(seg)
	me.x = spot.x
	me.y = spot.y
	me.path = []
	sim.stock.scrap = 40.0
	sim.events.clear()
	return {"g": g, "sim": sim, "me": me, "seg": seg, "spot": spot}


func _free(m: Dictionary) -> void:
	m.g.world.queue_free()


func _steps(sim, n: int) -> void:
	for i in n:
		sim.update(DT)


## The events of this type from `sim.events` since the last `_events` of it (events are cleared by the sim's own views, not here).
func _events(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if e.get("type", "") == type:
			out.append(e)
	return out


# ------------------------------------------------------------------------------- candidates --

func test_a_worn_wall_within_reach_is_a_candidate_with_its_share_in_the_label() -> void:
	var m := _game(CONTAINER, 0.35)
	var list: Array = m.sim.nights.wall_candidates()
	eq(list.size(), 1, "one section in reach")
	if list.size() == 1:
		var c: Dictionary = list[0]
		eq(c.kind, "wall", "of kind wall")
		eq(c.id, str(CONTAINER), "named by the section's id")
		eq(c.label, "Mend the Red container (35%)", "the label")
		check(c.ok and c.why == "", "it can be used")
		check(c.pos.is_equal_approx(m.spot), "at the mending place")
	_free(m)


func test_a_sound_wall_and_a_far_one_are_not() -> void:
	var m := _game(PALLETS, 0.96)
	check(m.sim.nights.wall_candidates().is_empty(), "96%: sound")
	m.seg.hp = m.seg.max_hp * 0.94
	eq(m.sim.nights.wall_candidates().size(), 1, "94%: worth a hammer")
	var reach: float = NightData.num("mend.reach")
	m.me.x = m.spot.x + reach - 0.1
	eq(m.sim.nights.wall_candidates().size(), 1, "within reach")
	m.me.x = m.spot.x + reach + 0.1
	check(m.sim.nights.wall_candidates().is_empty(), "past reach")
	near(reach, 1.6, 1.0e-9, "the plan's 1.6 tiles")
	_free(m)


func test_a_fallen_section_is_a_candidate() -> void:
	var m := _game(PALLETS, 0.0)
	eq(int(m.seg.state), 3, "it is down")
	var list: Array = m.sim.nights.wall_candidates()
	eq(list.size(), 1, "listed")
	if list.size() == 1:
		eq(list[0].label, "Mend the Pallet barricade (0%)", "the label")
	_free(m)


func test_a_door_is_a_candidate_too() -> void:
	var m := _game(DOOR, 0.5)
	var list: Array = m.sim.nights.wall_candidates()
	eq(list.size(), 1, "listed")
	if list.size() == 1:
		eq(list[0].id, str(DOOR), "the door")
	_free(m)


func test_nothing_to_mend_while_the_avatar_cannot() -> void:
	var m := _game()
	check(not m.sim.nights.wall_candidates().is_empty(), "to begin with")
	m.me.downed = true
	check(m.sim.nights.wall_candidates().is_empty(), "down")
	m.me.downed = false
	m.me.away = {"party": true}
	check(m.sim.nights.wall_candidates().is_empty(), "away")
	m.me.away = null
	m.me.turned = true
	check(m.sim.nights.wall_candidates().is_empty(), "turned")
	m.me.turned = false
	check(m.sim.avatar.set_player(null), "no avatar")
	check(m.sim.nights.wall_candidates().is_empty(), "no avatar")
	_free(m)


func test_a_hand_on_the_keys_or_no_scrap_is_a_reason_not_a_silence() -> void:
	var m := _game()
	m.sim.avatar.set_input(Vector2(1.0, 0.0), m.spot + Vector2(3.0, 0.0), false)
	var moving: Array = m.sim.nights.wall_candidates()
	check(moving.size() == 1 and not moving[0].ok and moving[0].why != "", "walking: listed with its reason")
	m.sim.avatar.set_input(Vector2.ZERO, m.spot + Vector2(3.0, 0.0), false)
	m.sim.stock.scrap = 0.0
	var dry: Array = m.sim.nights.wall_candidates()
	check(dry.size() == 1 and not dry[0].ok and dry[0].why == "There is no scrap to spare", "no scrap: %s" % str(dry))
	_free(m)


# ------------------------------------------------------------------------------ the session --

func test_mending_starts_a_session_of_the_plans_length() -> void:
	var m := _game()
	var r: Dictionary = m.sim.nights.mend_wall(PALLETS)
	check(bool(r.ok), "it starts: %s" % str(r))
	eq(m.sim.nights.working, "wall", "working")
	eq(m.sim.nights.mend_seg, PALLETS, "at the pallets")
	near(float(r.seconds), NightData.num("mend.seconds"), 1.0e-9, "for the plan's seconds")
	check(NightData.num("mend.seconds") > 0.0, "a session has a length")
	var on: Array = _events(m.sim, "wall_work")
	check(on.size() == 1 and on[0].on == true and on[0].seg == PALLETS, "an event says it began: %s" % str(on))
	check(m.sim.nights.wall_candidates()[0].label.begins_with("Stop mending"), "and the candidate now offers to stop")
	_free(m)


func test_the_avatar_mends_at_the_rate_of_any_repairer_and_pays_in_scrap() -> void:
	var m := _game(CONTAINER, 0.1)
	var sim = m.sim
	var rate: float = (sim.REPAIR_BASE + float(m.me.skills.Building)) * sim.perf(m.me) * sim.traits.mult(m.me, "repair")
	var hp0: float = m.seg.hp
	var scrap0: float = sim.stock.scrap
	var mended0: float = float(m.me.stats.mended)
	check(bool(sim.nights.mend_wall(CONTAINER).ok), "it starts")
	_steps(sim, 30)
	var gained: float = m.seg.hp - hp0
	check(absf(gained - rate) < rate * 0.05, "a second mends about %.1f hp (%.2f)" % [rate, gained])
	near(scrap0 - float(sim.stock.scrap), gained / 10.0, 0.01, "at ten hit points a scrap")
	near(float(m.me.stats.mended) - mended0, gained, 0.01, "Building is credited with it")
	eq(m.me.work, "mend", "the pose shows the work")
	check(String(m.me.activity).begins_with("Mending"), "and the activity: %s" % m.me.activity)
	_free(m)


func test_the_session_ends_after_its_seconds_and_tells_what_it_mended() -> void:
	var m := _game(CONTAINER, 0.1)
	var sim = m.sim
	check(bool(sim.nights.mend_wall(CONTAINER).ok), "it starts")
	_steps(sim, int(NightData.num("mend.seconds") * 30.0) + 5)
	eq(sim.nights.working, "", "over")
	var off: Array = _events(sim, "wall_work").filter(func(e): return e.on == false)
	check(off.size() == 1, "one event says it ended: %s" % str(off))
	if off.size() == 1:
		eq(off[0].why, "done", "because the seconds ran out")
		check(float(off[0].hp) > 30.0, "and says what it mended (%.1f)" % float(off[0].hp))
	eq(m.me.work, "", "the pose is dropped")
	_free(m)


func _ended_by(m: Dictionary) -> String:
	var off: Array = _events(m.sim, "wall_work").filter(func(e): return e.on == false)
	return String(off[off.size() - 1].why) if not off.is_empty() else ""


func test_walking_ends_it() -> void:
	var m := _game(CONTAINER, 0.3)
	check(bool(m.sim.nights.mend_wall(CONTAINER).ok), "it starts")
	_steps(m.sim, 10)
	eq(m.sim.nights.working, "wall", "still going")
	m.sim.avatar.set_input(Vector2(0.0, 1.0), m.spot + Vector2(0.0, 5.0), false)
	_steps(m.sim, 1)
	eq(m.sim.nights.working, "", "walking ended it")
	eq(_ended_by(m), "moved", "why")
	_free(m)


func test_the_trigger_ends_it() -> void:
	var m := _game(CONTAINER, 0.3)
	check(bool(m.sim.nights.mend_wall(CONTAINER).ok), "it starts")
	m.sim.avatar.set_input(Vector2.ZERO, m.spot + Vector2(5.0, 0.0), true)
	_steps(m.sim, 1)
	eq(m.sim.nights.working, "", "the trigger ended it")
	eq(_ended_by(m), "fired", "why")
	_free(m)


func test_a_wound_ends_it() -> void:
	var m := _game(CONTAINER, 0.3)
	check(bool(m.sim.nights.mend_wall(CONTAINER).ok), "it starts")
	_steps(m.sim, 5)
	m.me.hp -= 6.0
	_steps(m.sim, 1)
	eq(m.sim.nights.working, "", "a wound ended it")
	eq(_ended_by(m), "hurt", "why")
	_free(m)


func test_a_fall_ends_it() -> void:
	var m := _game(CONTAINER, 0.3)
	check(bool(m.sim.nights.mend_wall(CONTAINER).ok), "it starts")
	m.me.downed = true
	_steps(m.sim, 1)
	eq(m.sim.nights.working, "", "a fall ended it")
	eq(_ended_by(m), "You are down", "why")
	_free(m)


func test_a_whole_wall_ends_it_and_cheers_the_mender() -> void:
	var m := _game(PALLETS, 0.97)
	m.seg.hp = m.seg.max_hp - 0.5
	m.seg.state = 0
	var mood0: float = m.sim.morale.value(m.me)
	m.seg.hp = m.seg.max_hp * 0.9
	check(bool(m.sim.nights.mend_wall(PALLETS).ok), "it starts")
	_steps(m.sim, 60)
	check(m.seg.hp >= m.seg.max_hp - 1.0e-6, "the wall is whole")
	eq(m.sim.nights.working, "", "it ended")
	eq(_ended_by(m), "whole", "why")
	check(m.sim.morale.value(m.me) > mood0, "finishing a repair lifts the mood (%.2f then, %.2f now)" % [mood0, m.sim.morale.value(m.me)])
	_free(m)


func test_no_scrap_ends_it() -> void:
	var m := _game(CONTAINER, 0.3)
	check(bool(m.sim.nights.mend_wall(CONTAINER).ok), "it starts")
	_steps(m.sim, 5)
	m.sim.stock.scrap = 0.0
	_steps(m.sim, 2)
	eq(m.sim.nights.working, "", "no scrap ended it")
	eq(_ended_by(m), "no scrap", "why")
	_free(m)


func test_stopping_by_hand_says_so() -> void:
	var m := _game(CONTAINER, 0.3)
	check(bool(m.sim.nights.mend_wall(CONTAINER).ok), "it starts")
	_steps(m.sim, 3)
	m.sim.nights.stop_mend("stopped")
	eq(m.sim.nights.working, "", "stopped")
	eq(_ended_by(m), "stopped", "why")
	m.sim.nights.stop_mend("again")
	eq(_events(m.sim, "wall_work").size(), 2, "and nothing more is said when it is already over")
	_free(m)


# ------------------------------------------------------------------------------- refusals --

func test_it_is_refused_with_the_reason() -> void:
	var m := _game(CONTAINER, 0.3)
	var sim = m.sim
	sim.stock.scrap = 0.0
	var dry: Dictionary = sim.nights.mend_wall(CONTAINER)
	check(not bool(dry.ok) and dry.why == "There is no scrap to spare", "no scrap: %s" % str(dry))
	sim.stock.scrap = 40.0
	m.me.x = m.spot.x + 4.0
	var far: Dictionary = sim.nights.mend_wall(CONTAINER)
	check(not bool(far.ok) and far.why == "Too far from the wall", "far: %s" % str(far))
	m.me.x = m.spot.x
	m.seg.hp = m.seg.max_hp
	sim._segment_state(m.seg)
	var sound: Dictionary = sim.nights.mend_wall(CONTAINER)
	check(not bool(sound.ok) and String(sound.why).ends_with("is sound"), "a sound wall: %s" % str(sound))
	var none: Dictionary = sim.nights.mend_wall(999)
	check(not bool(none.ok) and none.why == "There is no such wall", "no such wall: %s" % str(none))
	var lots: Dictionary = sim.nights.mend_wall(100)
	check(not bool(lots.ok), "a wall of the lots is not the compound's")
	m.seg.hp = m.seg.max_hp * 0.3
	sim.avatar.set_input(Vector2(1.0, 0.0), m.spot + Vector2(3.0, 0.0), false)
	var keys: Dictionary = sim.nights.mend_wall(CONTAINER)
	check(not bool(keys.ok) and keys.why == "Stand still to mend", "a hand on the keys: %s" % str(keys))
	sim.avatar.set_input(Vector2.ZERO, m.spot + Vector2(3.0, 0.0), false)
	m.me.downed = true
	var down: Dictionary = sim.nights.mend_wall(CONTAINER)
	check(not bool(down.ok) and down.why == "You are down", "down: %s" % str(down))
	eq(sim.nights.working, "", "and nothing began")
	check(_events(sim, "wall_work").is_empty(), "and no event")
	_free(m)


func test_it_is_refused_without_an_avatar_or_in_a_place() -> void:
	var m := _game(CONTAINER, 0.3)
	m.sim.nights_on = false
	check(not bool(m.sim.nights.mend_wall(CONTAINER).ok), "in a place's sim")
	m.sim.nights_on = true
	check(m.sim.avatar.set_player(null), "no avatar")
	check(not bool(m.sim.nights.mend_wall(CONTAINER).ok), "with no avatar")
	_free(m)


func test_giving_up_the_avatar_ends_a_session() -> void:
	var m := _game(CONTAINER, 0.3)
	check(bool(m.sim.nights.mend_wall(CONTAINER).ok), "it starts")
	_steps(m.sim, 3)
	check(m.sim.avatar.set_player(null), "the avatar is given up")
	_steps(m.sim, 1)
	eq(m.sim.nights.working, "", "the session ended")
	_free(m)


# ----------------------------------------------------------------------------------- fire --

func test_mending_goes_on_under_fire_and_shuts_a_breach_above_forty_percent() -> void:
	var m := _game(PALLETS, 0.0)
	var sim = m.sim
	eq(int(m.seg.state), 3, "the pallets are down")
	for i in 3:
		var z = sim.spawn(m.seg.center.x + float(i) * 0.5, m.seg.center.y - 3.0, "wander")
		z.state = "breach"
		z.hp = 1.0e9
		z.stagger = 1.0e9
	check(sim.nights.breach_hot(m.seg), "it is a hot breach")
	check(bool(sim.nights.mend_wall(PALLETS).ok), "the avatar may mend it: under fire is allowed")
	var shut_at := -1.0
	for i in 400:
		sim.update(DT)
		if shut_at < 0.0 and int(m.seg.state) < 3:
			shut_at = float(i) / 30.0
		if sim.nights.working == "":
			break
	check(shut_at > 0.0, "the breach shut again")
	check(m.seg.hp >= m.seg.max_hp * 0.4 - 1.0e-6, "above 40%% (%.0f%%)" % (100.0 * m.seg.hp / m.seg.max_hp))
	check(float(sim.world.solid_p[int(m.seg.tiles[0])]) != 0.0, "and its ground is shut to walkers again")
	_free(m)


func test_a_big_breach_takes_more_than_one_session() -> void:
	var m := _game(CONTAINER, 0.0)
	var sim = m.sim
	eq(int(m.seg.state), 3, "the container is down")
	var sessions := 0
	while int(m.seg.state) == 3 and sessions < 6:
		sim.avatar.set_input(Vector2.ZERO, m.spot + Vector2(3.0, 0.0), false)
		check(bool(sim.nights.mend_wall(CONTAINER).ok), "session %d starts" % (sessions + 1))
		sessions += 1
		_steps(sim, int(NightData.num("mend.seconds") * 30.0) + 5)
	check(sessions >= 2 and sessions <= 4, "it took %d sessions" % sessions)
	check(int(m.seg.state) < 3, "and it stands again")
	_free(m)
