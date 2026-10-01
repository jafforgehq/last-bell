extends "res://tests/case.gd"
## A player who mashes every key and click at random, on every step, cannot break Orientation Day or
## trap it: nothing logs an error, nobody dies or turns or leaves, the run is never over, and the
## bot can still play the lesson to the end afterwards.

const Tut := preload("res://tests/tutorial_kit.gd")
const Bot := preload("res://tests/tutorial_bot.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const Prefs := preload("res://scripts/prefs.gd")

## Every key the game answers to, but F9 (which would load the scene again) and Esc (which opens
## the pause menu when nothing is selected: it is added below, only with a selection).
const KEYS := [KEY_R, KEY_P, KEY_F, KEY_C, KEY_T, KEY_X, KEY_G, KEY_L, KEY_B, KEY_M, KEY_V, KEY_TAB, KEY_1, KEY_2, KEY_3, KEY_SPACE, KEY_F5, KEY_W, KEY_A, KEY_S, KEY_D]


func _random_point(main, rng: RandomNumberGenerator) -> Vector2:
	var vp: Vector2 = main._vp()
	return Vector2(rng.randf_range(0.0, vp.x), rng.randf_range(0.0, vp.y))


## One thing a player might do, at random.
func _random_input(main, rng: RandomNumberGenerator) -> void:
	var roll := rng.randf()
	var coach = main.coach
	if roll < 0.30:
		main._key(KEYS[rng.randi() % KEYS.size()])
	elif roll < 0.40:
		main._click(_random_point(main, rng), MOUSE_BUTTON_LEFT)
	elif roll < 0.48:
		main._click(_random_point(main, rng), MOUSE_BUTTON_RIGHT)
	elif roll < 0.62:
		Bot.card_click(main, main.sim.people[rng.randi() % main.sim.people.size()].id)
	elif roll < 0.67:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP if rng.randf() < 0.5 else MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.factor = 1.0
		wheel.position = _random_point(main, rng)
		main._unhandled_input(wheel)
	elif roll < 0.72:
		Bot.pan_and_zoom(main)
	elif roll < 0.80:
		var buttons: Array = []
		for b in main.hud.gizmos.get_children():
			if b is Button and b.has_meta("id") and not b.is_queued_for_deletion():
				buttons.append(b)
		if not buttons.is_empty():
			buttons[rng.randi() % buttons.size()].pressed.emit()
	elif roll < 0.86:
		if coach != null:
			var wanted: Array = []
			for b in [coach.next_button, coach.speed_button, coach.show_button]:
				if b.is_visible_in_tree():
					wanted.append(b)
			if not wanted.is_empty():
				wanted[rng.randi() % wanted.size()].pressed.emit()
	elif roll < 0.95:
		var d = main.hud.scavenge_dialog
		if d != null and is_instance_valid(d):
			var pick := rng.randf()
			if pick < 0.4 and not d.site_cards.is_empty():
				d.choose_site(d.site_cards.keys()[rng.randi() % d.site_cards.size()])
			elif pick < 0.6 and not d.candidates.is_empty():
				d.toggle_second(d.candidates[d.candidates.keys()[rng.randi() % d.candidates.size()]].person)
			elif pick < 0.85:
				d.send()
			else:
				d.cancel()
	elif main.selection != null:
		main._key(KEY_ESCAPE)


## Nothing the player does may end the lesson badly.
func _check_world(main, label: String) -> void:
	var sim = main.sim
	eq(sim.over, "", "%s: not over" % label)
	for p in sim.people:
		check(not p.dead and not p.turned, "%s: %s is neither dead nor turned" % [label, p.first])
		check(p.away == null or (p.away is Dictionary and p.away.get("kind", "") == "party"), "%s: %s is not sent away for good" % [label, p.first])
	for s in sim.segments:
		check(s.hp >= s.max_hp * 0.2 - 0.001 and s.state != 3, "%s: %s is standing" % [label, s.name])


func _mash(main, rng: RandomNumberGenerator, frames: int, label: String) -> void:
	var tree := Engine.get_main_loop()
	for i in frames:
		if main.coach == null:
			return
		if rng.randf() < 0.25:
			_random_input(main, rng)
		main._process(1.0 / 30.0)
		if i % 5 == 0:
			await tree.process_frame
		if i % 30 == 0:
			_check_world(main, "%s frame %d" % [label, i])


func test_a_player_who_mashes_buttons_cannot_break_or_trap_the_lesson() -> void:
	var main = Tut.game()
	await Tut.frames(main, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	var refused_total := 0
	var ids: Array = []
	for s in main.coach.steps:
		if String(s.id) != "wrap":
			ids.append(String(s.id))
	for id in ids:
		var r: Dictionary = await Bot.play(main, id)
		eq(r.stuck, "", "the bot got to %s" % id)
		if main.coach == null or r.stuck != "":
			break
		var before: int = int(main.coach.refused)
		await _mash(main, rng, 240, id)
		if main.coach != null:
			refused_total += int(main.coach.refused) - before
	check(refused_total >= 100, "the mashing ran into the lock a good many times (%d)" % refused_total)
	var finish: Dictionary = await Bot.play(main)
	eq(finish.stuck, "", "after all that the bot could still finish (at %s)" % finish.stuck)
	check(main.coach == null, "the lesson ended")
	check(Prefs.flag("tutorial_done"), "with the flag set")
	_check_world(main, "the end")
	await Tut.leave(main)
