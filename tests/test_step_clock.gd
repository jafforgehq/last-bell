extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const StepClock := preload("res://scripts/sim/step_clock.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")

## A stretch of uneven frames, from a hitch to a very quick one, in seconds.
const UNEVEN := [0.004, 0.031, 0.012, 0.045, 0.017, 0.002, 0.026, 0.09]


## Feeds the clock frames of the given lengths (taken in turn) until `seconds` of
## real time have passed, the last one cut short so the total is exact. Returns
## the steps handed out, and fails if alpha ever leaves [0, 1).
func _drive(clock, frames: Array, seconds: float, speed: float) -> int:
	var steps := 0
	var t := 0.0
	var i := 0
	while t < seconds - 1e-9:
		var ft := minf(float(frames[i % frames.size()]), seconds - t)
		i += 1
		t += ft
		steps += clock.advance(ft, speed)
		var a: float = clock.alpha()
		if not (a >= 0.0 and a < 1.0):
			failures.append("alpha left [0, 1): %s after a frame of %s" % [str(a), str(ft)])
	return steps


func test_ten_seconds_of_frames_are_three_hundred_steps_at_any_frame_rate() -> void:
	for frames in [[1.0 / 30.0], [1.0 / 60.0], [1.0 / 144.0], [1.0 / 240.0], UNEVEN]:
		var n := _drive(StepClock.new(), frames, 10.0, 1.0)
		check(absi(n - 300) <= 1, "frames %s: %d steps in 10 s" % [str(frames.slice(0, 3)), n])


func test_a_long_run_does_not_drift() -> void:
	# a quarter of an hour at an awkward frame time: still 30 steps a second
	var n := _drive(StepClock.new(), [1.0 / 59.94], 900.0, 1.0)
	check(absi(n - 27000) <= 1, "27000 steps in 15 minutes, got %d" % n)


func test_alpha_is_how_far_the_time_has_run_into_the_next_step() -> void:
	var c := StepClock.new()
	near(c.alpha(), 0.0, 1e-9, "a new clock")
	eq(c.advance(0.02, 1.0), 0, "0.6 of a step is not a step")
	near(c.alpha(), 0.6, 1e-6, "but it is 0.6 of the way")
	eq(c.advance(0.02, 1.0), 1, "1.2 steps: one now")
	near(c.alpha(), 0.2, 1e-6, "and 0.2 left")
	eq(c.advance(StepClock.STEP, 1.0), 1, "an exact step")
	near(c.alpha(), 0.2, 1e-6, "leaves the leftover as it was")
	c.reset()
	near(c.alpha(), 0.0, 1e-9, "reset forgets the leftover")
	eq(c.advance(0.02, 1.0), 0, "and starts again")


func test_a_frame_counts_for_at_most_a_tenth_of_a_second() -> void:
	var c := StepClock.new()
	eq(c.advance(5.0, 1.0), 3, "a five second stall is a tenth of a second: three steps")
	eq(c.advance(-1.0, 1.0), 0, "time does not run backwards")
	eq(c.advance(0.0, 1.0), 0, "an empty frame takes none")


func test_the_rounding_of_a_sum_does_not_cost_a_frame() -> void:
	# nine frames of 1/270 s add up to 0.9999999999999998 of a step in floating point
	var c := StepClock.new()
	var n := 0
	for i in 9:
		n += c.advance(StepClock.STEP / 9.0, 1.0)
	eq(n, 1, "one step, not one frame late")
	near(c.alpha(), 0.0, 1e-6, "with nothing left over")


func test_speeds_two_and_three_take_two_and_three_times_the_steps() -> void:
	for ft in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0]:
		var two := _drive(StepClock.new(), [ft], 10.0, 2.0)
		var three := _drive(StepClock.new(), [ft], 10.0, 3.0)
		check(absi(two - 600) <= 1, "speed 2 at frames of %.4f: %d steps" % [ft, two])
		check(absi(three - 900) <= 1, "speed 3 at frames of %.4f: %d steps" % [ft, three])


func test_the_cap_drops_the_leftover_instead_of_falling_behind() -> void:
	var c := StepClock.new()
	eq(c.advance(StepClock.MAX_FRAME, 100.0), StepClock.MAX_STEPS, "ten seconds' worth of steps in one frame: the cap")
	near(c.alpha(), 0.0, 1e-9, "and the rest of that time is gone")
	eq(c.advance(0.0, 100.0), 0, "nothing is owed on the next frame")
	eq(c.advance(StepClock.STEP, 1.0), 1, "the game carries on at its normal pace")
	# a frame worth 12.45 steps is under the cap: nothing is dropped
	var d := StepClock.new()
	eq(d.advance(StepClock.MAX_FRAME, 4.15), StepClock.MAX_STEPS, "twelve steps")
	near(d.alpha(), 0.45, 1e-6, "and the rest is kept")
	# one worth 13.5 steps is over it: twelve, and the rest is dropped
	eq(d.advance(StepClock.MAX_FRAME, 4.5), StepClock.MAX_STEPS, "twelve again")
	near(d.alpha(), 0.0, 1e-9, "with nothing kept")


func test_speed_zero_takes_no_steps_and_leaves_the_clock_alone() -> void:
	var c := StepClock.new()
	c.advance(0.02, 1.0)
	var before := c.alpha()
	for i in 100:
		eq(c.advance(1.0 / 60.0, 0.0), 0, "paused")
	eq(c.alpha(), before, "the picture does not move while paused")
	# a pause in the middle of a run neither gains nor loses time
	var straight := _drive(StepClock.new(), [1.0 / 60.0], 3.0, 1.0)
	var paused := StepClock.new()
	var n := 0
	for i in 90:
		n += paused.advance(1.0 / 60.0, 1.0)
	for i in 500:
		n += paused.advance(1.0 / 60.0, 0.0)
	for i in 90:
		n += paused.advance(1.0 / 60.0, 1.0)
	eq(n, straight, "the same steps as three seconds without the pause")
	eq(StepClock.new().advance(1.0, -1.0), 0, "a negative speed is a pause too")


## Everything the rules decided that a player could tell apart, as text.
func _fingerprint(sim) -> String:
	var out := "kills=%d day=%d minutes=%.6f;" % [sim.kills, sim.day, sim.minutes]
	var keys: Array = sim.stock.keys()
	keys.sort()
	for k in keys:
		out += "%s=%s;" % [k, str(sim.stock[k])]
	for p in sim.people:
		out += "%s@%.6f,%.6f hp%.6f;" % [p.id, p.x, p.y, p.hp]
	for z in sim.zombies:
		out += "z@%.6f,%.6f %s hp%.3f;" % [z.x, z.y, z.state, z.hp]
	return out


## A game from dusk on day 1, driven by the clock with the given frame times
## until it has taken exactly `target` steps; the rules only ever see STEP.
func _play(frames: Array, target: int) -> Dictionary:
	var g := Helpers.make(7, 1)
	var sim = g.sim
	sim.minutes = 19.0 * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	var clock := StepClock.new()
	var done := 0
	var i := 0
	while done < target:
		var n := clock.advance(float(frames[i % frames.size()]), 1.0)
		i += 1
		for k in n:
			if done < target:
				sim.update(StepClock.STEP)
				done += 1
	var fp := _fingerprint(sim)
	var kills: int = sim.kills
	var walkers: int = sim.zombies.size()
	g.world.free()
	return {"fp": fp, "kills": kills, "walkers": walkers, "frames": i}


func test_the_same_seed_plays_the_same_game_at_any_frame_rate() -> void:
	var steps := 2400 # 80 s: the dusk and the first of the night
	var at_60 := _play([1.0 / 60.0], steps)
	var at_144 := _play([1.0 / 144.0], steps)
	var jittery := _play([1.0 / 20.0, 1.0 / 200.0], steps)
	check(at_60.kills > 0 and at_60.walkers > 4, "the game was not empty: %d kills, %d walkers" % [at_60.kills, at_60.walkers])
	check(at_60.frames != at_144.frames and at_60.frames != jittery.frames and at_144.frames != jittery.frames, "the runs really had different frame counts: %d, %d, %d" % [at_60.frames, at_144.frames, jittery.frames])
	eq(at_144.fp, at_60.fp, "144 fps plays the game of 60 fps")
	eq(jittery.fp, at_60.fp, "so do uneven frames")
	# and the check can tell: the rules stepped at another rate play another game
	var g := Helpers.make(7, 1)
	g.sim.minutes = 19.0 * 60.0
	g.sim.phase = g.sim.phase_at(g.sim.minutes)
	for i in steps * 2:
		g.sim.update(StepClock.STEP / 2.0)
	check(_fingerprint(g.sim) != at_60.fp, "a different step size is a different game")
	g.world.free()


# ------------------------------------------------------- main.gd's own loop --

## The real game scene, driven by hand: frames of the given lengths (taken in
## turn) at `speed` until `seconds` of the rules' time have passed, the last frame
## cut short. Returns the steps the rules took and what they decided.
func _play_main(frames: Array, seconds: float, speed: int) -> Dictionary:
	Engine.set_meta("run", {"difficulty": 1, "seed": 7})
	var main = load("res://scenes/main.tscn").instantiate()
	var tree := Engine.get_main_loop()
	tree.root.add_child(main)
	main.sim.minutes = 19.0 * 60.0
	main.sim.phase = main.sim.phase_at(main.sim.minutes)
	main.speed = speed
	var real := seconds / float(speed)
	var t := 0.0
	var i := 0
	while t < real - 1e-9:
		var ft := minf(float(frames[i % frames.size()]), real - t)
		i += 1
		t += ft
		main._process(ft)
	var out := {"fp": _fingerprint(main.sim), "steps": main.sim_steps, "frames": i}
	# paused: the rules stand still, however many frames go by
	main.speed = 0
	for k in 30:
		main._process(1.0 / 60.0)
	out["paused_steps"] = main.sim_steps
	out["paused_fp"] = _fingerprint(main.sim)
	main.queue_free()
	await tree.process_frame
	return out


func test_main_gd_plays_the_same_game_at_any_frame_rate_and_speed() -> void:
	var at_60 := await _play_main([1.0 / 60.0], 10.0, 1)
	var at_144 := await _play_main([1.0 / 144.0], 10.0, 1)
	var jittery := await _play_main([1.0 / 20.0, 1.0 / 200.0], 10.0, 1)
	var fast := await _play_main([1.0 / 60.0], 10.0, 3)
	for run in [at_60, at_144, jittery, fast]:
		eq(run.steps, 300, "ten seconds of the rules are 300 steps")
		eq(run.paused_steps, run.steps, "and a paused game takes none")
		eq(run.paused_fp, run.fp, "and changes nothing")
	check(at_60.frames != at_144.frames and at_60.frames != jittery.frames and at_60.frames != fast.frames, "the runs really had different frame counts: %d, %d, %d, %d" % [at_60.frames, at_144.frames, jittery.frames, fast.frames])
	eq(at_144.fp, at_60.fp, "144 fps plays the game of 60 fps")
	eq(jittery.fp, at_60.fp, "so do uneven frames")
	eq(fast.fp, at_60.fp, "and so does the top speed")


# ------------------------------------------------- drawing between the steps --

## A walker's node, drawn the way main.gd does it, with the walker at (x, y).
func _node(g: Dictionary, x: float, y: float):
	var z = g.sim.zombies[0]
	z.x = x
	z.y = y
	var n = PawnNode.new()
	n.setup(z, true, g.data, "z%d" % z.look_index)
	return n


func test_a_walker_is_drawn_smoothly_between_the_steps() -> void:
	var g := Helpers.make(7, 1)
	for ft in [1.0 / 60.0, 1.0 / 144.0, 1.0 / 240.0]:
		var n = _node(g, 30.0, 30.0)
		var z = n.entity
		var clock := StepClock.new()
		var steps := 0
		var last: float = n.tile_pos().x
		var worst := 0.0
		for frame in int(4.0 / ft):
			for s in clock.advance(ft, 1.0):
				z.x += 0.1 # the rules move someone at 3 tiles a second, 0.1 a step
				steps += 1
			n.sync(false, steps, clock.alpha())
			var x: float = n.tile_pos().x
			if x < last - 1e-4:
				failures.append("frame %d at %.4f s: drawn backwards, %.4f after %.4f" % [frame, ft, x, last])
			worst = maxf(worst, x - last)
			last = x
			if x > z.x + 1e-4 or x < z.x - 0.1 - 1e-4:
				failures.append("frame %d at %.4f s: drawn at %.4f, the rules have them at %.4f" % [frame, ft, x, z.x])
		# drawn at the frame rate, not the step rate: a frame moves them its share of a
		# step (a drawing that followed the rules would jump a whole 0.1 on a step frame)
		check(worst <= 0.1 * ft / StepClock.STEP * 1.1 + 1e-4, "at %.4f s the biggest move in one frame was %.4f" % [ft, worst])
		near(last, z.x - 0.1 * (1.0 - clock.alpha()), 1e-3, "at the end they are drawn between their last two steps")
		n.free()
	g.world.free()


func test_a_node_starts_where_the_walker_stands() -> void:
	var g := Helpers.make(7, 1)
	var n = _node(g, 21.25, 33.5)
	near(n.tile_pos().x, 21.25, 1e-4, "x")
	near(n.tile_pos().y, 33.5, 1e-4, "y")
	n.free()
	g.world.free()


func test_a_node_is_drawn_where_the_walker_is_when_synced_without_steps() -> void:
	var g := Helpers.make(7, 1)
	var n = _node(g, 30.0, 30.0)
	var z = n.entity
	for i in 5:
		z.x += 0.1
		n.sync(false)
		near(n.tile_pos().x, z.x, 1e-4, "step %d: drawn where the walker is" % i)
	n.free()
	g.world.free()


func test_the_first_look_at_a_walker_who_has_moved_is_not_a_slide() -> void:
	var g := Helpers.make(7, 1)
	var n = _node(g, 30.0, 30.0)
	var z = n.entity
	z.x = 32.0 # two tiles on, before main.gd ever syncs it with the steps
	n.sync(false, 5, 0.3)
	near(n.tile_pos().x, 32.0, 1e-4, "drawn where it is")
	z.x = 32.1
	n.sync(false, 6, 0.0)
	near(n.tile_pos().x, 32.0, 1e-4, "from then on it is drawn between its steps")
	n.free()
	g.world.free()


func test_a_jump_is_drawn_where_they_land_and_a_walk_is_not() -> void:
	var g := Helpers.make(7, 1)
	var n = _node(g, 30.0, 30.0)
	var z = n.entity
	z.x = 40.0 # back from a trip, say: ten tiles in one step
	n.sync(false, 1, 0.0)
	near(n.tile_pos().x, 40.0, 1e-4, "no slide across the map")
	z.x = 42.9 # 2.9 tiles: a long step, still a walk
	n.sync(false, 2, 0.0)
	near(n.tile_pos().x, 40.0, 1e-4, "a walk starts from where they were")
	n.sync(false, 2, 0.5)
	near(n.tile_pos().x, 41.45, 1e-4, "and gets there by degrees")
	z.x = 46.0 # 3.1 tiles from the last step: a jump
	n.sync(false, 3, 0.0)
	near(n.tile_pos().x, 46.0, 1e-4, "more than three tiles is a jump")
	n.free()
	g.world.free()


func test_a_walker_who_was_out_of_sight_is_not_slid_in() -> void:
	var g := Helpers.make(7, 1)
	var n = _node(g, 30.0, 30.0)
	var z = n.entity
	n.sync(false, 0, 0.0)
	# two frames in which main.gd did not sync it: it was off screen
	var tree := Engine.get_main_loop()
	var start := Engine.get_process_frames()
	for k in 10:
		if Engine.get_process_frames() >= start + 2:
			break
		await tree.process_frame
	check(Engine.get_process_frames() >= start + 2, "two frames went by")
	z.x = 32.0 # two tiles from where it was last seen
	n.sync(false, 60, 0.4)
	near(n.tile_pos().x, 32.0, 1e-4, "drawn where it is, not on its way from where it was")
	n.free()
	g.world.free()


func test_a_paused_game_draws_the_same_picture() -> void:
	var g := Helpers.make(7, 1)
	var n = _node(g, 30.0, 30.0)
	var z = n.entity
	var clock := StepClock.new()
	var steps := 0
	for i in 20:
		for s in clock.advance(1.0 / 144.0, 1.0):
			z.x += 0.1
			steps += 1
		n.sync(false, steps, clock.alpha())
	var before: Vector2 = n.tile_pos()
	for i in 50:
		for s in clock.advance(1.0 / 144.0, 0.0):
			steps += 1
		n.sync(false, steps, clock.alpha())
		if n.tile_pos() != before:
			failures.append("moved while paused, frame %d: %s -> %s" % [i, str(before), str(n.tile_pos())])
			break
	n.free()
	g.world.free()
