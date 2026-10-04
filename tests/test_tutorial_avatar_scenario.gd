extends "res://tests/case.gd"
## Orientation Day as the avatar's lesson, the rules' side (scripts/sim/orientation.gd, `avatar`): how it starts (Ruth is the
## player, the board is on, the old yard's worn bus is not), the beats it adds (a lone walker at the bus wall, a gun left low,
## everyone sent home), what the scratch and the fever bring (Ana at a bed and a refusal, the radio's call), `jump`'s two new
## words, that it is saved with the run, and that the classic Orientation Day is as it was.

const Kit := preload("res://tests/tutorial_kit.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


func _ruth(sim):
	return sim.avatar.player()


## The dead that are coming for a wall or at it.
func _coming(sim) -> Array:
	var out: Array = []
	for z in sim.zombies:
		if z.state == "approach" or z.state == "attack":
			out.append(z)
	return out


# ------------------------------------------------------------------- start --

func test_the_avatars_orientation_day_starts_with_ruth_and_the_board() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	check(g.scenario.avatar, "it is the avatar's lesson")
	check(Orientation.is_orientation(sim.scenario), "and Orientation Day")
	eq(sim.player_id, "ruth", "Ruth is the player")
	eq(sim.difficulty, 0, "Story")
	eq(sim.run_seed, Orientation.SEED, "the fixed seed")
	near(sim.hour, 7.0, 0.001, "at 07:00")
	eq(sim.people.size(), 6, "the whole crew")
	check(sim.town.on, "the town is on: G opens the board, as in a real run")
	check(not sim.streets.enabled, "and the dead of the streets are not about")
	check(not sim.waves.enabled and not sim.permadeath, "it still cannot be lost and the nights are the script's")
	for s in sim.segments:
		near(s.hp, s.max_hp, 0.001, "%s is whole: nothing here is the old yard's repair lesson" % s.name)
	eq(sim.player_id, _ruth(sim).id, "the player is a person of the crew")
	g.world.free()


func test_the_classic_orientation_day_is_as_it_was() -> void:
	var g := Kit.make()
	var sim = g.sim
	check(not g.scenario.avatar, "the classic lesson is not the avatar's")
	eq(sim.player_id, "", "no avatar")
	check(not sim.town.on, "no town")
	check(sim.streets.enabled, "(the streets' switch is on, and the town is off, so they do nothing)")
	near(sim.segments[Orientation.BUS_ID].hp / sim.segments[Orientation.BUS_ID].max_hp, Orientation.BUS_START, 0.001, "the bus is worn")
	eq(g.scenario.beat_ids(), ["dusk", "more", "scratch", "fever"], "four beats")
	check(not g.scenario.fire("stray"), "the avatar's beats are not there")
	check(not g.scenario.fire("spent") and not g.scenario.fire("home") and not g.scenario.fire("assault"), "any of them")
	check(g.scenario.fired.is_empty(), "so nothing was brought")
	g.world.free()


func test_the_avatars_lesson_has_four_beats_more_and_the_clock_never_brings_them() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	eq(g.scenario.beat_ids(), ["dusk", "more", "scratch", "fever", "stray", "spent", "assault", "home"], "the four and the avatar's four")
	check(not g.scenario.coached, "no coach")
	Kit.run_to_clock(sim, 120.0)
	for id in Orientation.AVATAR_BEATS:
		check(not g.scenario.has_fired(id), "two hours on, '%s' did not come by itself" % id)
	check(_coming(sim).is_empty(), "no walker came")
	g.world.free()


# --------------------------------------------------------------- the stray --

func test_a_lone_walker_comes_to_the_bus_wall() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	Kit.run(sim, 0.1)
	check(g.scenario.fire("stray"), "the beat is brought")
	check(not g.scenario.fire("stray"), "once")
	eq(_coming(sim).size(), 1, "one walker is coming")
	var z = _coming(sim)[0]
	check(z.slot != null, "it has a place at a wall")
	check(sim.alerts.has("stray"), "and there is an alert for it")
	Kit.run(sim, 40.0)
	check(not _coming(sim).is_empty(), "alive after forty seconds: nobody shoots it by day")
	var z2 = _coming(sim)[0]
	check(z2.y > 12.0 and absf(z2.x - 47.5) < 8.0, "and it has come to the wall in front of the bus (%.1f, %.1f)" % [z2.x, z2.y])
	g.world.free()


func test_a_walker_taken_by_something_else_is_put_again_but_not_after_the_players_own_kill() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	Kit.run(sim, 0.1)
	g.scenario.fire("stray")
	# something else takes it
	for z in _coming(sim):
		sim._hurt_zombie(z, 100.0, 0.0)
	Kit.run(sim, 0.2)
	eq(_coming(sim).size(), 1, "another one is there")
	eq(g.scenario.stray_tries, 1, "(the first time it was put again)")
	# the player's shot closes the lesson
	var me = _ruth(sim)
	for z in _coming(sim):
		sim._hurt_zombie(z, 100.0, 0.0, me)
	check(int(me.stats.kills) >= 1, "the kill is the player's")
	Kit.run(sim, 0.2)
	check(_coming(sim).is_empty(), "and nothing is put again")
	check(not g.scenario.stray_open, "the lesson is closed")
	g.world.free()


func test_the_walker_is_put_again_a_few_times_at_most() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	Kit.run(sim, 0.1)
	g.scenario.fire("stray")
	for i in 8:
		for z in _coming(sim):
			sim._hurt_zombie(z, 100.0, 0.0)
		Kit.run(sim, 0.2)
	eq(g.scenario.stray_tries, Orientation.STRAY_TRIES, "no more than %d times" % Orientation.STRAY_TRIES)
	g.world.free()


# ------------------------------------------------------------ the gun, home --

func test_the_magazine_is_left_low_so_that_r_has_something_to_do() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	var me = _ruth(sim)
	var full := int(me.gun.mag)
	eq(int(me.mag), full, "a full magazine to begin with")
	me.reloading = 1.5
	check(g.scenario.fire("spent"), "the beat")
	check(int(me.mag) >= 1 and int(me.mag) < full, "left low but not empty: %d of %d" % [me.mag, full])
	near(me.reloading, 0.0, 0.0001, "and no reload is going on")
	check(sim.avatar.reload(), "R is taken")
	Kit.run(sim, float(me.gun.reload) + 0.5)
	eq(int(me.mag), full, "and the magazine is full again")
	g.world.free()


func test_home_ends_the_stances_and_takes_the_defaults_of_the_calls() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	var dez = Kit.person(sim, "dez")
	sim.radio.set_stance(dez, "follow")
	sim.radio.request(Kit.person(sim, "marcus"), "come")
	var id: int = sim.radio.raise_call("test", "A call", "", [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}], "b", 60.0)
	eq(sim.radio.open_calls().size(), 1, "a call waits")
	check(g.scenario.fire("home"), "the beat")
	eq(dez.stance, "", "nobody holds a stance")
	check(sim.radio.pending.is_empty(), "and nobody is about to")
	check(sim.radio.open_calls().is_empty(), "the call was answered")
	var entry: Dictionary = sim.radio._entry(id)
	eq(entry.answered, "b", "by its default")
	g.world.free()


# ------------------------------------------------- the scratch and the fever --

func test_the_scratch_puts_ana_at_walts_side_at_once_and_the_radio_refuses_her() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	var ana = Kit.person(sim, "ana")
	var walt = Kit.person(sim, "walt")
	check(g.scenario.fire("scratch"), "the beat")
	check(walt.bleeding > 0.0, "Walt bleeds")
	var tending := false
	for j in sim.medical.jobs:
		tending = tending or (j.healer == ana and j.patient == walt)
	check(tending, "Ana has him to tend, before the rules have taken a step")
	var w: Dictionary = sim.radio.willingness(ana, "come")
	check(not w.ok and not w.hard, "asked to come, she cannot, and the push could change it")
	eq(w.why, "Ana: tending a patient, can't come", "with her reason")
	g.world.free()


func test_two_of_the_dead_at_a_wall_bring_the_radios_call_at_once_and_it_can_be_answered() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	check(g.scenario.fire("assault"), "the beat")
	var at_wall := 0
	for z in sim.zombies:
		if z.state == "attack":
			at_wall += 1
	eq(at_wall, Orientation.ASSAULT_N, "two of the dead are clawing at the wall")
	var calls: Array = sim.radio.open_calls()
	eq(calls.size(), 1, "one call waits, before a step")
	eq(String(calls[0].kind), "attack", "it is the attack call")
	eq(int(calls[0].data.seg), Orientation.ASSAULT_WALL, "about that wall")
	check(String(calls[0].text).contains("under attack"), "in the radio's own words: %s" % calls[0].text)
	eq(calls[0].options.size(), 3, "with three answers")
	check(sim.radio.answer(int(calls[0].id), "reinforce"), "Send reinforcements is taken")
	check(sim.radio.open_calls().is_empty(), "and the call is settled")
	g.world.free()


# --------------------------------------------------------------------- jump --

func test_jump_stands_the_player_somewhere_and_sets_their_magazine() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	g.scenario.jump({"hour": 7.5, "at": [48.5, 18.6], "mag": 2})
	var me = _ruth(sim)
	near(me.x, 48.5, 0.001, "where they were put")
	near(me.y, 18.6, 0.001, "both ways")
	eq(int(me.mag), 2, "two rounds in the gun")
	check(sim.world.on_deck(me.x, me.y), "on the walkway")
	near(sim.hour, 7.5, 0.001, "at the hour")
	g.world.free()


# --------------------------------------------------------------------- save --

func test_it_is_saved_with_the_run_and_stays_the_avatars_lesson() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	Kit.run(sim, 0.1)
	g.scenario.fire("stray")
	var path := "user://tutorial_avatar_scenario_test.json"
	check(SaveGame.write(sim, path), "saved")
	var again := Kit.make()
	var saved := SaveGame.read(path)
	check(Orientation.is_save(saved), "it reads as an Orientation Day save")
	check(SaveGame.apply(again.sim, saved), "and loads")
	check(again.sim.scenario.avatar, "still the avatar's lesson")
	eq(again.sim.player_id, "ruth", "with Ruth the player")
	check(again.sim.town.on, "the town on")
	check(not again.sim.streets.enabled, "and the streets off")
	check(again.sim.scenario.stray_open and again.sim.scenario.has_fired("stray"), "the walker's lesson is as it was")
	again.world.free()
	g.world.free()
	OS.move_to_trash(ProjectSettings.globalize_path(path))


# --------------------------------------------------------------- the gate (round 26) --

func test_the_real_gate_is_switched_on_by_the_lesson_that_teaches_it_and_stays_on() -> void:
	var g := Kit.make_avatar()
	var sim = g.sim
	check(not sim.gate.enabled and not g.scenario.gate_on, "the lesson begins with the gate the way it was: a shut wall section")
	check(not sim.gate.active(), "(no real gate)")
	g.scenario.jump({"hour": 17.0, "gate": "open"})
	near(sim.hour, 17.0, 0.001, "jump brings the hour")
	check(g.scenario.gate_on and sim.gate.enabled and sim.gate.active(), "and the real rules")
	eq(sim.gate.held, "open", "with the gate open (held, as the day's traffic leaves it)")
	Kit.run(sim, 3.0)
	check(sim.gate.open >= 0.999, "and it opens")
	# the bell shuts a gate that was left open
	g.scenario.set_time(18.98, 1)
	Kit.run(sim, 1.0)
	check(sim.bell_rung, "the bell rang")
	Kit.run(sim, 3.0)
	near(sim.gate.open, 0.0, 0.001, "and the keeper shut it")
	eq(sim.gate.held, "", "(nobody's hand: it is not locked)")
	# a save keeps the switch (the gate module's own switch is the harness's, and is not saved)
	var path := "user://tutorial_avatar_gate_test.json"
	check(SaveGame.write(sim, path), "saved")
	var again := Kit.make()
	check(SaveGame.apply(again.sim, SaveGame.read(path)), "and loads")
	check(again.sim.scenario.gate_on and again.sim.gate.enabled and again.sim.gate.active(), "the gate's rules are still on")
	again.world.free()
	g.world.free()
	OS.move_to_trash(ProjectSettings.globalize_path(path))


func test_the_lessons_end_leaves_the_gate_on_and_only_for_the_avatars_lesson() -> void:
	var g := Kit.make_avatar()
	g.scenario.finish()
	check(g.scenario.gate_on and g.sim.gate.enabled and g.sim.gate.active(), "the avatar's lesson, finished: the real gate")
	g.world.free()
	var plain := Kit.make()
	plain.scenario.finish()
	check(not plain.scenario.gate_on and not plain.sim.gate.enabled, "the classic lesson, finished: nothing of the gate")
	plain.scenario.set_gate("open")
	check(not plain.sim.gate.enabled, "(and set_gate is not for it)")
	plain.world.free()
