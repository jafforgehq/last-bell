## A headless bot that plays Orientation Day through the real handlers (input events, the crew
## cards, the keys, the radio's buttons, the pages and the coach's own buttons), for the tests
## (tests/test_tutorial*.gd; this file has no test_ prefix so the runner skips it). It plays
## whichever lesson the game is: the avatar's (`act_avatar`: the keys W A S D held down as the engine
## has them, the mouse moved, its right button held to aim and its left button to shoot (round 22; its left button alone with the setting
## "Always aim at the mouse"), R and F, a click on a crew card, the radio's
## verb buttons and the call's, T, G and L, J) or the old yard's (`act_classic`: right-clicks and the
## order keys).
extends RefCounted

const AimMode := preload("res://scripts/aim_mode.gd")

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


## What a person does to look around: scroll the wheel three times and drag the ground with the middle button held (a
## left-drag is no pan; Alt and the left button, or W A S D, pan too).
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
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(vp.x * 0.7, vp.y * 0.5)
	main._unhandled_input(press)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(vp.x * 0.2, vp.y * 0.3)
	main._unhandled_input(move)
	press.pressed = false
	press.position = move.position
	main._unhandled_input(press)


## What the bot does on one frame of step `id` (the avatar's lesson or the old yard's: see `act_avatar`
## and `act_classic`). `bot` holds its cool-down.
static func act(main, id: String, bot: Dictionary) -> void:
	if main.avatar_mode:
		act_avatar(main, id, bot)
	else:
		act_classic(main, id, bot)


## What the bot does on one frame of step `id` of the old yard's lesson. It looks at the game, not at what it did before: the
## first thing the step still needs is done (at most once every few frames, so the game can answer),
## so it picks up after anything a player left half done.
static func act_classic(main, id: String, bot: Dictionary) -> void:
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
			# M gives him the bench job (and takes it away again), so it is pressed until he has it
			if sim.jobs.job_of(person(main, "dez")) == "bench":
				did = false
			elif not selected(main, "dez"):
				card_click(main, "dez")
			else:
				main._key(KEY_M)
		"jobs":
			# J opens the Duty roster; a job is given with the page's own buttons (Hector's Day job, then the
			# Builders line of the list that opens); Close shuts the page again
			var page = main.hud.jobs_screen
			var given: bool = float(coach.state.events.get("assigned:job", 0.0)) > 0.0
			if page == null:
				if given:
					did = false
				else:
					main._key(KEY_J)
			elif given:
				page.close_button.pressed.emit()
			elif page.list != null and page.list_kind == "job":
				page.list_items["builders"].pressed.emit()
			elif page.list != null:
				page.close_list()
			else:
				page.rows["hector"].job.pressed.emit()
		"wrap":
			coach.stay_button.pressed.emit()
		_:
			did = false
	bot["cool"] = 12 if did else 0


# ----------------------------------------------------------- the avatar's hands --

## The foot of the ladder to the walkway at the bus wall (the lesson's marked one), and a spot on the walkway.
const LADDER := Vector2(48.5, 20.4)
const DECK_AT := Vector2(48.5, 18.5)

## The keys the bot holds down now (keycode to true), as the engine's input state has them.
static var _held := {}


## Holds exactly these keys down, as the engine's input state has them (the avatar's walk reads them every frame), and lets go of
## the others.
static func hold(codes: Array) -> void:
	for code in _held.keys():
		if not codes.has(code):
			_key_event(code, false)
			_held.erase(code)
	for code in codes:
		if not _held.has(code):
			_key_event(code, true)
			_held[code] = true


static func release_keys() -> void:
	hold([])


static func _key_event(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## The mouse over a tile of the yard (the aim is the tile under it).
static func point_at(main, tile: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = main._tile_to_screen(tile)
	main._unhandled_input(ev)


## The right button down or up (the aim, "Right button aims"), where the mouse is: a press the HUD did not take reaches the world, a release
## is seen by `_input` whoever took it.
static func aim_button(main, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = down
	ev.position = main.mouse_screen
	if down:
		main._input(ev)
	main._unhandled_input(ev)
	if not down:
		main._input(ev)


## The left button down or up (the trigger), where the mouse is.
static func trigger(main, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = main.mouse_screen
	main._unhandled_input(ev)
	if not down:
		main._input(ev)


## Holds the keys that take the player towards `to` (both ways at once, each as near as its own tolerance), and says whether
## they are there.
static func walk_to(main, to: Vector2, tol_x: float = 0.3, tol_y: float = 0.3) -> bool:
	var me = main.sim.avatar.player()
	var d := to - Vector2(me.x, me.y)
	var keys: Array = []
	if d.x > tol_x:
		keys.append(KEY_D)
	elif d.x < -tol_x:
		keys.append(KEY_A)
	if d.y > tol_y:
		keys.append(KEY_S)
	elif d.y < -tol_y:
		keys.append(KEY_W)
	hold(keys)
	return keys.is_empty()


## The way from `from` to `to` over the walking grid of the people (the rail and the face of a walkway are shut but at a ladder), as
## the centres of the tiles to walk to one after the other and `to` last; [] when there is none. (A player sees the way; the bot
## looks it up.)
static func route(main, from: Vector2, to: Vector2) -> Array:
	var w: int = main.world.W
	var h: int = main.world.H
	var solid: PackedByteArray = main.world.solid_p
	var start := floori(from.y) * w + floori(from.x)
	var goal := floori(to.y) * w + floori(to.x)
	if start == goal:
		return [to]
	var came := {start: start}
	var queue: Array = [start]
	var head := 0
	while head < queue.size() and not came.has(goal):
		var cur: int = queue[head]
		head += 1
		var cx := cur % w
		var cy := cur / w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni := ny * w + nx
			if came.has(ni) or solid[ni] != 0:
				continue
			came[ni] = cur
			queue.append(ni)
	if not came.has(goal):
		return []
	var way: Array = []
	var at := goal
	while at != start:
		way.push_front(Vector2(float(at % w) + 0.5, float(at / w) + 0.5))
		at = came[at]
	way[way.size() - 1] = to
	return way


## Holds the keys that take the player one step along the way to `to`; true when they are there.
static func goto(main, to: Vector2, tol: float = 0.3) -> bool:
	var me = main.sim.avatar.player()
	var here := Vector2(me.x, me.y)
	if here.distance_to(to) <= tol:
		hold([])
		return true
	var way := route(main, here, to)
	if way.is_empty():
		hold([])
		return false
	# the next tile of the way that is not the one underfoot (a tile's centre is reached to within a few hundredths)
	var next: Vector2 = way[0]
	if way.size() > 1 and here.distance_to(next) < 0.3:
		next = way[1]
	# (the avatar is 0.6 wide: in a way one tile wide, a corridor or a ladder, it has to keep to the middle of it)
	walk_to(main, next, 0.1, 0.1)
	return false


## The nearest of the dead that is coming for the compound (or at its wall), or null.
static func nearest_dead(main):
	var me = main.sim.avatar.player()
	var best = null
	var best_d := INF
	for z in main.sim.zombies:
		if z.state != "approach" and z.state != "attack" and z.state != "hunt" and z.state != "breach":
			continue
		var d := Vector2(z.x, z.y).distance_to(Vector2(me.x, me.y))
		if d < best_d:
			best_d = d
			best = z
	return best


## The button of an option of the call that waits (on the card, or in the News panel), or null.
static func call_button(main, option: String):
	var hud = main.hud
	var views: Array = []
	if hud.news_panel != null and hud.news_panel.visible:
		views.append_array(hud.news_panel.call_views)
	if hud.call_card != null and hud.call_card.visible:
		views.append(hud.call_card.view)
	for v in views:
		var b = v.buttons.get(option)
		if b != null and is_instance_valid(b) and b.is_visible_in_tree():
			return b
	return null


## What the bot does on one frame of step `id` of the avatar's lesson, with real hands: it walks with the keys held down, aims with
## the mouse, holds the left button, presses R, F, T, G, L and J, clicks the crew's pictures and the buttons of the radio and the
## pages, as a player does. `bot` holds its cool-down (for the things done once) and what it is in the middle of.
static func act_avatar(main, id: String, bot: Dictionary) -> void:
	var coach = main.coach
	var sim = main.sim
	var me = sim.avatar.player()
	var cool: int = int(bot.get("cool", 0))
	if cool > 0:
		bot["cool"] = cool - 1
		return
	var did := true
	match id:
		"you", "wrap":
			if id == "wrap":
				coach.stay_button.pressed.emit()
			elif coach.next_button.visible and coach.phase == "active":
				coach.next_button.pressed.emit()
			else:
				did = false
		"walk":
			hold([KEY_D])
			did = false
		"shoot":
			did = false
			if not sim.world.on_deck(me.x, me.y):
				trigger(main, false)
				aim_button(main, false)
				# the way to the walkway is the ladder's
				goto(main, DECK_AT, 0.15)
			else:
				hold([])
				var z = nearest_dead(main)
				if z != null and Vector2(z.x, z.y).distance_to(Vector2(me.x, me.y)) < 6.0:
					point_at(main, Vector2(z.x, z.y - 0.3))
					# (hold the right button to aim, then the left to shoot; with "Always aim at the mouse" the left button alone)
					if not AimMode.always() and not main.aim_held:
						aim_button(main, true)
					if main.firing != true:
						trigger(main, true)
				else:
					trigger(main, false)
					aim_button(main, false)
		"reload":
			hold([])
			if float(coach.state.did.get("reload", 0.0)) <= 0.0:
				main._key(KEY_R)
			elif me.reloading > 0.0 or int(me.mag) < int(me.gun.mag):
				did = false
			else:
				main._key(KEY_F)
		"crew":
			if not selected(main, "dez"):
				card_click(main, "dez")
			else:
				did = false
		"come":
			if not selected(main, "dez"):
				card_click(main, "dez")
			elif String(person(main, "dez").stance) == "follow" or not sim.radio.pending.is_empty():
				did = false
			else:
				main.hud.radio_verbs.buttons["come"].pressed.emit()
		"refusal":
			if not selected(main, "ana"):
				card_click(main, "ana")
			elif float(sim.radio.trust_of(person(main, "ana"))) >= float(sim.radio.TRUST_START) - 0.01:
				# (ask her to come; once she has refused, the Insist button is there: press it)
				if main.hud.radio_verbs.insist_button.visible:
					main.hud.radio_verbs.insist_button.pressed.emit()
				else:
					main.hud.radio_verbs.buttons["come"].pressed.emit()
			else:
				did = false
		"news":
			if not bool(coach.state.get("news_seen", false)) and not main.hud.news_open():
				main._key(KEY_T)
			else:
				var b = call_button(main, "reinforce")
				if b != null:
					b.pressed.emit()
				else:
					did = false
		"map":
			var board = main.hud.scavenge_dialog
			if board == null or not is_instance_valid(board):
				if bool(coach.state.get("board_site", false)):
					did = false
				else:
					main._key(KEY_G)
			elif String(board.site_id) == "":
				var known: Array = board.sites.keys()
				board.select_place(String(known[0]))
			else:
				board.close()
		"alarm":
			hold([])
			if not sim.radio.alarm_on:
				if bool(coach.state.get("alarm_seen", false)):
					did = false
				else:
					main._key(KEY_L)
			else:
				bot["on_for"] = int(bot.get("on_for", 0)) + 1
				if int(bot["on_for"]) > 20:
					main._key(KEY_L)
				did = false
		"dusk":
			did = false
		"jobs":
			# J opens the Duty roster; a job is given with the page's own buttons; Close shuts the page again
			var page = main.hud.jobs_screen
			var given: bool = float(coach.state.events.get("assigned:job", 0.0)) > 0.0
			if page == null:
				if given:
					did = false
				else:
					main._key(KEY_J)
			elif given:
				page.close_button.pressed.emit()
			elif page.list != null and page.list_kind == "job":
				page.list_items["builders"].pressed.emit()
			elif page.list != null:
				page.close_list()
			else:
				page.rows["hector"].job.pressed.emit()
		_:
			did = false
	bot["cool"] = 12 if did else 0


## Whether the coach has seen the player ask `who` (for `verb`, if one is named) anything over the radio (a refusal or a yes).
static func asked_of(coach, who: String, verb: String = "") -> bool:
	var prefix := "radio_line:%s:%s" % [who, verb]
	for key in coach.state.events:
		if String(key).begins_with(prefix):
			return true
	return false


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
			if main.avatar_mode:
				release_keys()
				trigger(main, false)
				aim_button(main, false)
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
			if main.avatar_mode and (id == "walk" or id == "shoot"):
				# (the walk and the climb are done at normal speed: a tile is the room a ladder leaves)
				if not coach.held and main.speed != 1:
					main._key(KEY_1)
			elif not coach.held and main.speed < 3 and id != "scavenge" and id != "wrap":
				main._key(KEY_3)
			act(main, id, bot)
		main._process(1.0 / 30.0)
		if guard % 4 == 0:
			await tree.process_frame
		if sim.over != "":
			stuck = "over at %s" % id
			break
	if main.avatar_mode:
		release_keys()
		trigger(main, false)
		aim_button(main, false)
	return {"seen": seen, "stuck": stuck, "frames": guard}
