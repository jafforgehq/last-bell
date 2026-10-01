## A headless bot that plays Orientation Day through the real handlers (input events, the crew
## cards, the order keys, the scavenging dialog and the coach's own buttons), for the tests
## (tests/test_tutorial*.gd; this file has no test_ prefix so the runner skips it).
extends RefCounted

## The most frames the bot gives one step before it calls it stuck.
const STEP_FRAMES := 9000


static func person(main, id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


## A click on the crew card of `id`: what a click on the picture at the top does.
static func card_click(main, id: String) -> void:
	for c in main.hud.cards:
		if c.p.id == id:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			c.card.gui_input.emit(ev)
			return


static func selected(main, id: String) -> bool:
	return main.selection != null and main.selection.kind == "person" and main.selection.ref.id == id


static func segment(main, id: int):
	for s in main.sim.segments:
		if s.id == id:
			return s
	return null


## A spot of open ground `reach` tiles from `p`, where an order to walk can be given.
static func spot_near(main, p, reach: float) -> Vector2:
	for k in 12:
		var a := TAU * float(k) / 12.0
		var at := Vector2(p.x, p.y) + Vector2(cos(a), sin(a)) * reach
		if not main.world.is_solid(main.world.solid_p, at.x, at.y):
			return at
	return Vector2(p.x, p.y)


## What a person does to look around: scroll the wheel three times and drag the ground.
static func pan_and_zoom(main) -> void:
	var vp: Vector2 = main._vp()
	for i in 3:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.factor = 1.0
		wheel.position = vp / 2.0
		main._unhandled_input(wheel)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(vp.x * 0.7, vp.y * 0.5)
	main._unhandled_input(press)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(vp.x * 0.2, vp.y * 0.3)
	main._unhandled_input(move)
	press.pressed = false
	press.position = move.position
	main._unhandled_input(press)


## What the bot does on one frame of step `id`. It looks at the game, not at what it did before: the
## first thing the step still needs is done (at most once every few frames, so the game can answer),
## so it picks up after anything a player left half done. `bot` holds its cool-down.
static func act(main, id: String, bot: Dictionary) -> void:
	var coach = main.coach
	var sim = main.sim
	var cool: int = int(bot.get("cool", 0))
	if cool > 0:
		bot["cool"] = cool - 1
		return
	var did := true
	match id:
		"look":
			pan_and_zoom(main)
		"send":
			var ruth = person(main, "ruth")
			if not selected(main, "ruth"):
				card_click(main, "ruth")
			elif ruth.order == null:
				main._focus(Vector2(ruth.x, ruth.y))
				main._apply_camera()
				main._click(main._tile_to_screen(spot_near(main, ruth, 4.0)), MOUSE_BUTTON_RIGHT)
			else:
				did = false
		"release":
			if not selected(main, "ruth"):
				card_click(main, "ruth")
			else:
				main._key(KEY_R)
		"post":
			var hector = person(main, "hector")
			if hector.order != null and hector.order.z > 0.5:
				did = false
			elif not selected(main, "hector"):
				card_click(main, "hector")
			else:
				main._key(KEY_P)
		"repair":
			var repairing := false
			for p in sim.people:
				if p.repair != null and p.repair.id == 3:
					repairing = true
			if repairing:
				did = false
			elif main.selection == null or main.selection.kind != "segment" or main.selection.ref.id != 3:
				main._try_select({"kind": "segment", "ref": segment(main, 3)})
			else:
				main._key(KEY_F)
		"stores", "report":
			if coach.next_button.visible and coach.phase == "active":
				coach.next_button.pressed.emit()
			else:
				did = false
		"scavenge":
			if main.hud.scavenge_dialog != null:
				var d = main.hud.scavenge_dialog
				if d.site_id == "":
					d.choose_site("houses")
				else:
					d.send()
			elif not selected(main, "ana"):
				card_click(main, "ana")
			else:
				main._key(KEY_G)
		"shoot":
			if not selected(main, "marcus"):
				card_click(main, "marcus")
			else:
				did = false
		"fields":
			if not main.fields:
				main._key(KEY_V)
			else:
				did = false
		"alarm":
			if sim.tactics.lure_id >= 0:
				did = false
			elif main.selection == null or main.selection.kind != "segment" or main.selection.ref.id != 2:
				main._try_select({"kind": "segment", "ref": segment(main, 2)})
			else:
				main._key(KEY_L)
		"fever":
			var hec = person(main, "hector")
			if sim.medical.treat_orders.has("hector") or hec.infected_at < 0.0:
				did = false
			elif not selected(main, "hector"):
				card_click(main, "hector")
			else:
				main._key(KEY_T)
		"save":
			main._key(KEY_F5)
		"workshop":
			if sim.workshop.crafting(person(main, "dez")):
				did = false
			elif not selected(main, "dez"):
				card_click(main, "dez")
			else:
				main._key(KEY_M)
		"wrap":
			coach.stay_button.pressed.emit()
		_:
			did = false
	bot["cool"] = 12 if did else 0


## Plays the game from where it is: each frame the bot does what the present step asks and the
## game takes a frame (the speed it likes: the fastest the coach lets it). It stops when the coach
## is at step `stop_at` (it has just begun: waiting for its moment does not count unless `any_phase`),
## or gone, or after `max_frames` frames, and returns {"seen": the ids of the steps it
## met in order, "stuck": the id of a step it could not finish or "", "frames": how many frames}.
static func play(main, stop_at: String = "", max_frames: int = 400000, any_phase: bool = false) -> Dictionary:
	var tree := Engine.get_main_loop()
	var sim = main.sim
	var seen: Array = []
	var bot := {}
	var in_step := 0
	var last := ""
	var guard := 0
	var stuck := ""
	while main.coach != null and guard < max_frames:
		var coach = main.coach
		var id: String = coach.step_id()
		if id != last:
			seen.append(id)
			bot = {}
			in_step = 0
			last = id
		if stop_at != "" and id == stop_at and (any_phase or coach.phase != "wait"):
			break
		guard += 1
		in_step += 1
		if in_step > STEP_FRAMES:
			stuck = id
			break
		if coach.phase == "wait":
			if main.speed != 3:
				main._key(KEY_3)
		elif coach.phase == "active" or coach.phase == "wrap":
			if not coach.held and main.speed < 3 and id != "scavenge" and id != "wrap":
				main._key(KEY_3)
			act(main, id, bot)
		main._process(1.0 / 30.0)
		if guard % 4 == 0:
			await tree.process_frame
		if sim.over != "":
			stuck = "over at %s" % id
			break
	return {"seen": seen, "stuck": stuck, "frames": guard}
