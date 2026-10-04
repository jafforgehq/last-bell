extends "res://tests/case.gd"
## The scene of a played trip (round 14, R14.3; round 17, S1.6b: scripts/raid/raid_scene.gd, raid_hud.gd, raid_overlay.gd and
## main.gd's `open_raid`): it builds from a site and a squad, hides the colony and gives it back exactly, the hands of the
## avatar (WASD, the mouse, the trigger, R, F, E, Space, the wheel) reach the person you lead and the old controls (box select,
## left-click select, right-click orders, A, Tab, 1 to 6, H, panning) do nothing, the squad is asked over the radio (the
## panel's verbs reach `run.request` for those with you and the colony's radio for those at the base), the base's clock and
## state, the ammunition, the news, the call card and the alarm are there, the leader's fall hands the lead on, the way out
## ends the place, the report gives the result once, and nothing overlaps or is under 12 px at any width.
## The flow end to end (the road there, the colony running behind the place, the road home) is tests/test_place_flow.gd's; the
## rules of a run are tests/test_raid_run.gd's and tests/test_raid_avatar.gd's; the sites are tests/test_site_gen.gd's.

const GD := preload("res://scripts/game_data.gd")
const Kit := preload("res://tests/hud_kit.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const HudText := preload("res://tests/test_hud_text.gd")
const RaidScene := preload("res://scripts/raid/raid_scene.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")
const RaidHud := preload("res://scripts/raid/raid_hud.gd")
const RaidOverlay := preload("res://scripts/raid/raid_overlay.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const AimMode := preload("res://scripts/aim_mode.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

const W := 30
const H := 16
const WIDTHS := [700, 980, 1280, 1920]
const STEP := 1.0 / 30.0


## A site 30 x 16 of our own: open ground, a house (x 14 to 24, y 3 to 12) walled all round but a door at (14, 8), three
## things to search, the entry on the left and the exit round it, a vehicle's spot by the entry.
func _site(dead: Array = []) -> Dictionary:
	var data: Dictionary = GD.load_all().duplicate(true)
	var terrain: Array = []
	var solid: Array = []
	for y in H:
		for x in W:
			terrain.append(1)
			var wall := (x >= 14 and x <= 24 and y >= 3 and y <= 12) and (x == 14 or x == 24 or y == 3 or y == 12) and not (x == 14 and y == 8)
			solid.append(1 if wall else 0)
	data["W"] = W
	data["H"] = H
	data["terrain"] = terrain
	data["solidZ"] = solid.duplicate()
	data["solidP"] = solid.duplicate()
	for k in ["objects", "walls", "marks", "lights", "trees", "segments", "people", "spawns"]:
		data[k] = []
	return {
		"name": "The test house", "kind": "houses", "danger": 2, "size": Vector2i(W, H), "data": data,
		"entry": Vector2(3.5, 8.5), "exit": Rect2(1.0, 6.5, 5.0, 4.0), "vehicle_spot": Vector2(3.5, 12.5),
		"containers": [
			{"id": "c1", "pos": Vector2(16.5, 6.5), "at": Vector2(16.5, 5.5), "kind": "cabinet", "loot": {"food": 10, "meds": 4}, "search_s": 4.0, "room": "hall"},
			{"id": "c2", "pos": Vector2(21.5, 9.5), "at": Vector2(21.5, 10.5), "kind": "shelf", "loot": {"scrap": 25, "ammo": 60}, "search_s": 6.0, "room": "back"},
			{"id": "c3", "pos": Vector2(10.5, 3.5), "at": Vector2(10.5, 2.5), "kind": "crate", "loot": {"water": 12}, "search_s": 3.0, "room": "yard"},
		],
		"dead": dead, "rooms": [{"name": "hall", "rect": Rect2(15, 4, 9, 8)}], "seed": 1,
	}


## The real game (a small start: Ruth, Dez and Marcus) in a window of this size, with its own frames off. Ruth is the avatar
## (the real game's new run has her), unless `avatar` is false: then it is the old game.
func _game(width: int = 1280, height: int = 800, crew: int = 3, avatar: bool = true) -> Node:
	PlaceFlow.live_enabled = false    # (round 21: these trips keep the overlay's road; the live drive is tests/test_road_flow.gd's)
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew, "avatar": avatar}, width, height)
	AimMode.set_mode("always")    # (round 22: these tests are of the controls as they were: the mouse aims by itself and the left button fires; the default is tests/test_r22c_*.gd's)
	return main


## A place opened over `main` with the first `n` of the crew; its own frames are off (the tests tick it by hand). With `trip`
## the colony's flow is round it (the party is away, the road there is driven first: `_to_place` gets to the place).
func _open(main: Node, n: int = 3, dead: Array = [], vehicle: String = "", survivor: bool = false, trip: bool = false) -> Node:
	var party: Array = []
	for i in n:
		party.append(main.sim.people[i])
	var scene := RaidScene.new()
	main.add_child(scene)
	scene.set_process(false)
	scene.setup(main, main.hud, main.data, _site(dead), party, 300.0, vehicle, 1.0, survivor)
	if trip:
		var flow = PlaceFlow.new(main.sim)
		check(flow.begin(party, "houses", ""), "the trip begins: %s" % flow.error)
		scene.begin_trip(flow)
		_to_place(scene)
	return scene


## Drives the road there to its end.
func _to_place(scene: Node) -> void:
	var guard := 0
	while scene.phase == "road_there" and guard < 4000:
		scene.tick(1.0 / 60.0)
		guard += 1


func _play(scene: Node, seconds: float) -> void:
	for i in int(seconds * 30.0):
		scene.tick(STEP)


func _leave(main: Node) -> void:
	PlaceFlow.live_enabled = true    # (this file turns the live road off for its trips: the next file starts from it on)
	await TutorialKit.leave(main)


## A key pressed into the scene as the window hands it (`_input`: it keeps the keys held and takes the press).
func _press(scene: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	scene._input(ev)


func _release(scene: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = false
	scene._input(ev)


## A mouse button event as the viewport hands it to `_unhandled_input`.
func _button(scene: Node, at: Vector2, button: MouseButton, pressed: bool = true, shift: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = at
	ev.pressed = pressed
	ev.shift_pressed = shift
	scene._unhandled_input(ev)


func _click(scene: Node, at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	_button(scene, at, button, true, shift)
	_button(scene, at, button, false, shift)


func _motion(scene: Node, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	scene._unhandled_input(ev)


func _ids(list: Array) -> Array:
	var out: Array = []
	for p in list:
		out.append(String(p.id))
	return out


func _leader(scene: Node):
	return scene.leader()


func _put(p, x: float, y: float) -> void:
	p.x = x
	p.y = y
	p.path = []
	p.moving = false


# ----------------------------------------------------------------- building --

func test_the_scene_builds_from_a_site_and_a_squad() -> void:
	var main := _game()
	var scene := _open(main)
	eq(scene.world.W, W, "the world is the site's")
	eq(scene.world.H, H, "and its height")
	eq(scene.run.squad.size(), 3, "three people in the squad")
	for p in scene.run.squad:
		check(scene.pawn_nodes.has(p), "%s has a pawn" % p.first)
		check(scene.pawn_nodes[p].get_parent() == scene.entities, "sorted among the others")
	check(scene.camera.is_current(), "the raid's camera is the current one")
	eq(scene.hud_layer.cards.size(), 3, "a card each")
	check(scene.vehicle_node == null, "no vehicle on foot")
	check(not scene.done and not scene.ended, "not over")
	eq(scene.phase, "place", "a place with no flow is only the place")
	check(scene.get_parent() == main, "a child of the game")
	await _leave(main)


func test_the_colonys_avatar_leads_in_the_place_and_the_squad_follows() -> void:
	var main := _game()
	eq(main.sim.player_id, "ruth", "(the real game's new run has Ruth as the avatar)")
	var scene := _open(main)
	var lead = scene.leader()
	check(lead != null and String(lead.id) == "ruth", "Ruth leads")
	check(lead.player and scene.run.sim.player_id == "ruth", "the place's own Sim knows it")
	for p in scene.run.squad:
		if p != lead:
			eq(String(p.stance), "follow", "%s follows" % p.first)
	var others: Array = scene.squad_contacts()
	eq(others.size(), 2, "two to be asked over the radio")
	check(not others.has(lead), "not the one you lead")
	await _leave(main)


func test_with_no_avatar_the_first_of_the_squad_leads() -> void:
	var main := _game(1280, 800, 3, false)
	eq(main.sim.player_id, "", "(the old game has none)")
	var scene := _open(main)
	check(scene.leader() == scene.run.squad[0], "the first leads")
	await _leave(main)


func test_the_squad_has_the_colonys_trust_in_the_player() -> void:
	var main := _game()
	main.sim.people[1].trust = 71.0
	var scene := _open(main)
	near(scene.run.squad[1].trust, 71.0, 1e-6, "Dez trusts as at the base")
	await _leave(main)


func test_the_dead_of_the_site_get_pawns_and_a_corpse_leaves_the_crowd() -> void:
	var main := _game()
	var scene := _open(main, 3, [{"pos": Vector2(9.5, 8.5), "kind": "walker", "state": "still"}, {"pos": Vector2(20.5, 14.5), "kind": "brute", "state": "still"}])
	var zs: Array = scene.run.sim.zombies
	eq(zs.size(), 2, "two of the dead")
	for z in zs:
		check(scene.pawn_nodes.has(z), "a pawn each")
		check(scene.pawn_nodes[z].zombie, "drawn as the dead")
	zs[0].state = "dying"
	scene.tick(STEP)
	check(scene.pawn_nodes[zs[0]].get_parent() == scene.corpses, "one that falls lies on the ground, under the living")
	var gone = zs[0]
	scene.run.sim.zombies.erase(gone)
	scene.tick(STEP)
	check(not scene.pawn_nodes.has(gone), "and is forgotten when the rules let it go")
	await _leave(main)


func test_a_recruit_is_drawn_on_the_body_most_like_their_look() -> void:
	var main := _game()
	var def: Dictionary = main.sim.recruits.make_def(0)
	def["bitten"] = false
	var recruit = main.sim.add_person(def)
	var scene := RaidScene.new()
	main.add_child(scene)
	scene.set_process(false)
	scene.setup(main, main.hud, main.data, _site(), [recruit, main.sim.people[0]], 100.0)
	var n = scene.pawn_nodes[scene.run.squad[0]]
	check(n != null and n.tex.has("S"), "the recruit has a body")
	check(not main.data.pawn.files.has(recruit.id), "that is not one of the baked six")
	await _leave(main)


func test_a_vehicle_is_drawn_at_its_spot_and_the_bags_are_bigger() -> void:
	var main := _game()
	var scene := _open(main, 2, [], "van")
	check(scene.vehicle_node != null, "the van stands by the entry")
	var look := RaidScene.vehicle_look("van")
	check(not look.is_empty(), "vehicles.json knows the van")
	var spot: Vector2 = scene.site.vehicle_spot
	near(scene.vehicle_node.position.x, spot.x * GD.TILE, 0.01, "at the spot, across")
	near(scene.vehicle_node.position.y, (spot.y + float(look.h) / 2.0) * GD.TILE, 0.01, "its foot half its length below the spot's middle")
	near(scene.vehicle_node.texture.get_width() * scene.vehicle_node.scale.x, float(look.w) * GD.TILE, 0.01, "as wide as the data says")
	eq(scene.run.capacity(), 2 * RaidRun.CARRY + roundi(float(RaidRun.VEHICLE_CARRY) * 1.5), "and the van's room (by its cargo) is in the bags")
	check(scene.vehicle_node.get_parent() == scene.entities, "sorted by its foot among the people")
	await _leave(main)


func test_vehicle_look_reads_each_kind_of_the_data_and_nothing_for_none() -> void:
	for kind in ["sedan", "pickup", "van", "bus"]:
		var look := RaidScene.vehicle_look(kind)
		check(look.has("art") and float(look.w) > 0.0 and float(look.h) > 0.0, "%s has a picture and a size" % kind)
		check(ResourceLoader.exists("res://assets/objects/%s.png" % String(look.get("art", "none"))), "%s's picture is there" % kind)
	check(RaidScene.vehicle_look("hovercraft").is_empty(), "no such kind")


# ------------------------------------------------------------- the colony --

func test_the_colony_is_hidden_while_the_raid_runs_and_restored_exactly() -> void:
	var main := _game()
	main.cam_center = Vector2(37.5, 22.0)
	main.zoom_px = 44.0
	main.speed = 2
	main.follow = main.sim.people[1]
	main._select({"kind": "person", "ref": main.sim.people[2]})
	main.follow = main.sim.people[1]
	var chosen = main.selection
	var before: Dictionary = {"world": main.world.visible, "overlay": main.overlay.visible, "glow": main.glow.visible, "snow": main.snow.visible, "hud": main.hud.visible}
	var scene := _open(main)
	check(not main.world.visible and not main.hud.visible and not main.overlay.visible and not main.glow.visible and not main.snow.visible, "the colony's world, pawns and HUD are hidden")
	eq(main.speed, 2, "the speed is not touched: the scene steps the colony, the game's frames do not")
	check(main.menu_open and main.raid == scene and main.raid_open(), "the game counts the raid as a menu")
	var t0: float = main.sim.t
	for i in 30:
		main._process(STEP)
	near(main.sim.t, t0, 0.0001, "the game's own frames do not step the colony while the raid is up")
	_play(scene, 3.0)
	scene.run.retreat()
	_play(scene, 30.0)
	check(scene.ended, "the place ends")
	var seen: Array = []
	scene.finished.connect(func(r): seen.append(r))
	scene.go_home()
	eq(seen.size(), 1, "finished is sent once")
	check(main.world.visible == before.world and main.overlay.visible == before.overlay and main.glow.visible == before.glow and main.snow.visible == before.snow and main.hud.visible == before.hud, "everything shown again as it was")
	eq(main.speed, 2, "the speed is as it was")
	eq(main.cam_center, Vector2(37.5, 22.0), "the yard's camera is where it was")
	near(main.zoom_px, 44.0, 0.0001, "and its zoom")
	check(main.selection == chosen, "the selection too")
	check(main.follow == main.sim.people[1], "and who the camera followed")
	check(main.raid == null and not main.menu_open and not main.raid_open(), "the raid is no menu any more")
	check(main.camera.is_current(), "the yard's camera is current again")
	await TutorialKit.frames(main, 3)
	check(not is_instance_valid(scene), "the scene is gone")
	await _leave(main)


func test_the_colonys_keys_and_clicks_do_not_reach_the_yard_while_the_raid_is_up() -> void:
	var main := _game()
	var scene := _open(main)
	var sel = main.selection
	main._key(KEY_V)
	check(not main.fields, "V does not turn the fields view on")
	var speed: int = main.speed
	main._key(KEY_SPACE)
	eq(main.speed, speed, "and Space does not change the yard's clock")
	main._click(Vector2(400, 300), MOUSE_BUTTON_LEFT)
	check(main.selection == sel, "a click does not select in the yard")
	main.hud.on_speed.call(0)
	check(not main.hud.visible, "and the yard's HUD is out of the way")
	await _leave(main)


func test_every_key_belongs_to_the_raid_first_even_the_towns_boards_escape() -> void:
	var main := _game()
	# the Town Board is open (the button that opens a raid is on it) and stays open, hidden, under the raid
	main.hud.update_hud(main.sim, 1, true, 0)
	main.hud.last_speed = 1
	main.hud.open_scavenge(null)
	check(main.hud.town_board_open(), "the board is up")
	var scene := _open(main)
	for code in [KEY_G, KEY_TAB, KEY_J]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.pressed = true
		Engine.get_main_loop().root.push_input(ev)
	check(main.hud.town_board_open(), "G, Tab and J were the raid's, not the board's")
	check(scene.hud_layer.news_open == false and not main.hud.jobs_screen, "and opened nothing")
	await _leave(main)


func test_esc_opens_the_games_menu_and_the_place_waits_while_it_is_open() -> void:
	var main := _game()
	var scene := _open(main, 3, [], "", false, true)
	check(main.shell != null, "the game has its menu")
	_press(scene, KEY_ESCAPE)
	check(main.shell.is_open() and main.shell.kinds().has("pause"), "Esc opens the pause menu: %s" % str(main.shell.kinds()))
	var t: float = scene.run.elapsed
	var colony_t: float = main.sim.t
	_play(scene, 2.0)
	near(scene.run.elapsed, t, 0.0001, "the place waits while the menu is open")
	near(main.sim.t, colony_t, 0.0001, "and so does the base")
	var ev := InputEventKey.new()
	ev.keycode = KEY_DOWN
	ev.pressed = true
	scene._input(ev)
	check(not scene.held.has(KEY_DOWN), "the keys are the menu's while it is open")
	main.shell.close_all()
	main.resume()
	_play(scene, 1.0)
	check(scene.run.elapsed > t + 0.5, "and the place goes on when it is shut")
	await _leave(main)


# ------------------------------------------------------------------ the hands --

func test_wasd_walks_the_one_you_lead_and_nothing_else_moves_by_it() -> void:
	var main := _game()
	var scene := _open(main)
	var lead = scene.leader()
	var others: Array = []
	for p in scene.run.squad:
		if p != lead:
			others.append(Vector2(p.x, p.y))
	var x0: float = lead.x
	_press(scene, KEY_D)
	_play(scene, 1.0)
	eq(lead.input_move, Vector2(1, 0), "D asks for a step to the right")
	check(lead.x > x0 + 2.5, "and they walked about 3 tiles: %.2f" % (lead.x - x0))
	_press(scene, KEY_W)
	_play(scene, 0.1)
	eq(lead.input_move, Vector2(1, -1), "D and W together are the diagonal (the avatar normalises it)")
	_release(scene, KEY_D)
	_release(scene, KEY_W)
	_play(scene, 0.1)
	eq(lead.input_move, Vector2.ZERO, "and nothing when they are let go")
	var y0: float = lead.y
	_press(scene, KEY_S)
	_play(scene, 0.5)
	check(lead.y > y0 + 1.0, "S walks down")
	_release(scene, KEY_S)
	_press(scene, KEY_A)
	var x1: float = lead.x
	_play(scene, 0.5)
	check(lead.x < x1 - 1.0, "A walks left")
	await _leave(main)


func test_the_mouse_aims_the_avatar_at_the_tile_under_it() -> void:
	var main := _game()
	var scene := _open(main)
	var lead = scene.leader()
	_put(lead, 14.5, 8.5)
	scene.cam_center = Vector2(14.5, 8.5)
	_play(scene, 2.0)
	var at: Vector2 = scene.to_screen(Vector2(9.5, 4.5))
	var tile: Vector2 = scene.to_tile(at)
	_motion(scene, at)
	scene.tick(STEP)
	check(lead.input_aim.distance_to(tile) < 0.05, "the aim is the world point the pointer is over: %s" % str(lead.input_aim))
	var at2: Vector2 = scene.to_screen(Vector2(12.5, 9.5))
	var tile2: Vector2 = scene.to_tile(at2)
	_motion(scene, at2)
	scene.tick(STEP)
	check(lead.input_aim.distance_to(tile2) < 0.05, "and follows it: %s" % str(lead.input_aim))
	check(lead.input_aim.distance_to(Vector2(12.5, 9.5)) < 0.5, "(about where it was put)")
	await _leave(main)


func test_the_left_button_held_fires_and_let_go_stops() -> void:
	var main := _game()
	var scene := _open(main, 3, [{"pos": Vector2(9.5, 8.5), "kind": "walker", "state": "still"}])
	var lead = scene.leader()
	_put(lead, 5.5, 8.5)
	for p in scene.run.squad:
		if p != lead:
			_put(p, 2.5, 6.5)
			p.drafted = false
			p.stance = "hold"
			p.stance_at = Vector2(p.x, p.y)
	var mag0: int = lead.mag
	_motion(scene, scene.to_screen(Vector2(9.5, 8.4)))
	_button(scene, scene.to_screen(Vector2(9.5, 8.4)), MOUSE_BUTTON_LEFT, true)
	_play(scene, 0.2)
	check(lead.input_fire, "the trigger is held")
	_play(scene, 1.0)
	check(lead.mag < mag0 or lead.reloading > 0.0, "rounds left the gun: %d of %d" % [lead.mag, mag0])
	_button(scene, scene.to_screen(Vector2(9.5, 8.4)), MOUSE_BUTTON_LEFT, false)
	_play(scene, 0.1)
	check(not lead.input_fire, "let go, it stops")
	await _leave(main)


func test_a_release_over_the_hud_still_lets_the_trigger_go() -> void:
	var main := _game()
	var scene := _open(main)
	_button(scene, scene.to_screen(Vector2(9.5, 8.4)), MOUSE_BUTTON_LEFT, true)
	check(scene.fire_held, "held")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = Vector2(1200, 100)
	scene._input(ev)    # (the viewport shows the event to `_input` first, whoever takes it after)
	check(not scene.fire_held, "the release is seen wherever it was")
	await _leave(main)


func test_r_reloads_and_f_swings_and_neither_is_a_retreat_or_a_follow() -> void:
	var main := _game()
	var scene := _open(main, 3, [{"pos": Vector2(5.5, 7.4), "kind": "walker", "state": "still"}])
	var lead = scene.leader()
	_put(lead, 4.5, 8.0)
	lead.mag = 1
	_press(scene, KEY_R)
	_play(scene, 0.1)
	check(lead.reloading > 0.0, "R reloads")
	eq(scene.run.phase, "play", "and is no retreat")
	_motion(scene, scene.to_screen(Vector2(5.5, 7.4)))
	var z = scene.run.sim.zombies[0]
	var hp0: float = z.hp
	_press(scene, KEY_F)
	_play(scene, 0.2)
	check(lead.melee_t > 0.0 or z.hp < hp0, "F swings")
	await _leave(main)


func test_e_searches_the_container_in_reach_and_e_again_stops() -> void:
	var main := _game()
	var scene := _open(main, 3)
	var lead = scene.leader()
	for p in scene.run.squad:
		if p != lead:
			_put(p, 2.5, 6.5)
	_put(lead, 16.5, 6.5)
	_play(scene, 0.2)
	check(not scene.reach_container.is_empty() and String(scene.reach_container.id) == "c1", "the cabinet is in reach")
	_press(scene, KEY_E)
	eq(scene.run.searching_of(lead), "c1", "E begins the search")
	_play(scene, 1.5)
	check(float(scene.run.container("c1").progress) > 1.0, "it goes on while they stand: %.1f" % float(scene.run.container("c1").progress))
	_press(scene, KEY_E)
	eq(scene.run.searching_of(lead), "", "E again stops it")
	check(not scene.run.container("c1").looted, "with the cabinet not yet searched")
	_press(scene, KEY_E)
	_play(scene, 4.5)
	check(scene.run.container("c1").looted, "searched to the end")
	eq(int(scene.run.carried.get("food", 0)), 10, "and the food is in the bags")
	await _leave(main)


func test_e_far_from_everything_says_so_and_walking_or_firing_refuses_it() -> void:
	var main := _game()
	var scene := _open(main, 3)
	var lead = scene.leader()
	_press(scene, KEY_E)
	eq(scene.run.searching_of(lead), "", "nothing to search at the entry")
	check(scene.hud_layer.toast_panel.visible and scene.hud_layer.toast_label.text.begins_with("Nothing in reach"), "it says so: %s" % scene.hud_layer.toast_label.text)
	_put(lead, 16.5, 6.5)
	_press(scene, KEY_W)
	_press(scene, KEY_E)
	eq(scene.run.searching_of(lead), "", "not while walking")
	check(scene.hud_layer.toast_label.text.begins_with("Stand still"), "it says so: %s" % scene.hud_layer.toast_label.text)
	await _leave(main)


func test_e_beside_a_friend_who_is_down_gets_them_up_and_e_again_stops() -> void:
	var main := _game()
	var scene := _open(main, 3)
	var lead = scene.leader()
	var dez = scene.run.squad[1]
	_put(lead, 8.5, 8.5)
	_put(dez, 9.5, 8.5)
	_put(scene.run.squad[2], 3.5, 6.5)
	dez.downed = true
	dez.hp = 0.0
	_play(scene, 0.2)
	check(scene.reach_friend == dez, "Dez is within reach")
	check(scene.hint_line().contains("%s is down" % dez.first) and scene.hint_line().contains("press E"), "the line says what to do: %s" % scene.hint_line())
	_press(scene, KEY_E)
	check(scene.run.helping_of(lead) == dez, "E begins to get him up")
	_play(scene, 1.5)
	_press(scene, KEY_E)
	check(scene.run.helping_of(lead) == null, "E again stops")
	check(dez.downed, "he is still down")
	_press(scene, KEY_E)
	_play(scene, RaidRun.HELP_S + 1.0)
	check(not dez.downed, "stood beside him long enough, he is up")
	await _leave(main)


func test_e_far_from_a_friend_who_is_down_does_not_help_and_walking_cancels() -> void:
	var main := _game()
	var scene := _open(main, 3)
	var lead = scene.leader()
	var dez = scene.run.squad[1]
	_put(lead, 4.5, 8.5)
	_put(dez, 12.5, 8.5)
	_put(scene.run.squad[2], 3.5, 6.5)
	dez.downed = true
	_play(scene, 0.2)
	check(scene.reach_friend == null, "too far to reach")
	_press(scene, KEY_E)
	check(scene.run.helping_of(lead) == null, "nothing to help")
	_put(lead, 11.5, 8.5)
	_play(scene, 0.2)
	_press(scene, KEY_E)
	check(scene.run.helping_of(lead) == dez, "beside him it begins")
	_press(scene, KEY_D)
	_play(scene, 0.3)
	check(scene.run.helping_of(lead) == null, "walking off ends it")
	await _leave(main)


func test_the_container_under_the_pointer_wins_when_it_is_in_reach() -> void:
	var main := _game()
	var scene := _open(main, 3)
	var lead = scene.leader()
	_put(lead, 16.5, 6.5)
	_motion(scene, scene.to_screen(Vector2(16.5, 5.5)))
	_play(scene, 0.1)
	eq(String(scene.reach_container.get("id", "")), "c1", "the pointer on the cabinet: the cabinet")
	check(scene.hover != null and scene.hover.kind == "container", "and it is what the pointer is over")
	await _leave(main)


func test_space_pauses_the_place_and_the_base_both() -> void:
	var main := _game()
	var scene := _open(main, 3, [], "", false, true)
	_press(scene, KEY_SPACE)
	check(scene.paused, "paused")
	check(scene.hud_layer.paused_chip.visible, "the HUD says PAUSED")
	var t: float = scene.run.elapsed
	var colony_t: float = main.sim.t
	_press(scene, KEY_D)
	_play(scene, 2.0)
	near(scene.run.elapsed, t, 0.0001, "the place does not move while paused")
	near(main.sim.t, colony_t, 0.0001, "and nor does the base")
	eq(scene.leader().input_move, Vector2.ZERO, "and the hands are let go of")
	_press(scene, KEY_SPACE)
	_play(scene, 2.0)
	check(scene.run.elapsed > t + 1.5, "the place runs when it is not")
	check(main.sim.t > colony_t + 0.1, "and the base with it")
	check(not scene.paused, "unpaused")
	await _leave(main)


func test_the_wheel_zooms_about_the_pointer_and_stays_inside_its_limits() -> void:
	var main := _game()
	var scene := _open(main)
	var z0: float = scene.zoom_px
	var at := Vector2(900, 300)
	var tile_before: Vector2 = scene.to_tile(at)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 1.0
	wheel.position = at
	scene._unhandled_input(wheel)
	check(scene.zoom_px > z0, "the wheel up zooms in: %.1f to %.1f" % [z0, scene.zoom_px])
	check(scene.to_tile(at).distance_to(tile_before) < 0.4, "about the pointer (unless the edge of the map stops it)")
	for i in 40:
		scene._unhandled_input(wheel)
	near(scene.zoom_px, RaidScene.MAX_ZOOM, 0.001, "never past the limit")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for i in 60:
		scene._unhandled_input(wheel)
	near(scene.zoom_px, scene._min_zoom(), 0.001, "nor under the map's whole")
	check(scene.view_rect().size.x >= 0.0, "the view is real")
	await _leave(main)


func test_the_camera_follows_the_one_you_lead_and_leans_toward_the_pointer() -> void:
	var main := _game()
	var scene := _open(main)
	var lead = scene.leader()
	scene.zoom_px = 50.0
	scene.cam_center = Vector2(4, 8)
	_put(lead, 16.5, 8.5)
	_motion(scene, scene._vp() / 2.0)
	_play(scene, 2.0)
	check(scene.cam_center.distance_to(Vector2(16.5, 8.5)) < 0.5, "the camera is on them: %s" % str(scene.cam_center))
	_motion(scene, scene._vp() / 2.0 + Vector2(300, 0))
	_play(scene, 2.0)
	check(scene.cam_center.x > 16.5 + 0.5 and scene.cam_center.x <= 16.5 + RaidScene.CAM_LEAD + 0.1, "and leans toward the pointer, never far: %.2f" % scene.cam_center.x)
	await _leave(main)


func test_what_was_removed_does_nothing_box_select_clicks_orders_panning_and_the_old_keys() -> void:
	var main := _game()
	var scene := _open(main)
	var squad: Array = scene.run.squad
	var lead = scene.leader()
	squad[1].x = 8.5
	squad[1].y = 8.5
	squad[2].x = 8.5
	squad[2].y = 9.5
	var stances: Array = []
	for p in squad:
		stances.append(String(p.stance))
	# a box
	var from: Vector2 = scene.to_screen(Vector2(7.0, 7.0))
	var to: Vector2 = scene.to_screen(Vector2(10.0, 11.0))
	_button(scene, from, MOUSE_BUTTON_LEFT, true)
	_motion(scene, to)
	_button(scene, to, MOUSE_BUTTON_LEFT, false)
	check(not scene.is_selected(squad[1]) and scene.contact.is_empty(), "a box selects nobody")
	# a click on a person, and a right-click anywhere
	_click(scene, scene.to_screen(Vector2(8.5, 8.2)))
	check(scene.contact.is_empty(), "a click on a person asks nobody")
	_click(scene, scene.to_screen(Vector2(12.5, 4.5)), MOUSE_BUTTON_RIGHT)
	for p in squad:
		check(p.order == null, "%s has no order from a right-click" % p.first)
	# the keys
	var c0: Vector2 = scene.cam_center
	for code in [KEY_A, KEY_TAB, KEY_1, KEY_2, KEY_3, KEY_H, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		_press(scene, code)
		_release(scene, code)
	_play(scene, 0.3)
	check(scene.contact.is_empty(), "A, Tab and the numbers select nobody")
	eq(scene.run.phase, "play", "nothing retreats")
	for i in squad.size():
		eq(String(squad[i].stance), stances[i], "%s's stance is as it was" % squad[i].first)
	# a middle-mouse drag
	_button(scene, Vector2(600, 400), MOUSE_BUTTON_MIDDLE, true)
	_motion(scene, Vector2(300, 400))
	_button(scene, Vector2(300, 400), MOUSE_BUTTON_MIDDLE, false)
	_play(scene, 0.2)
	check(scene.cam_center.distance_to(c0) < 0.5, "the middle mouse does not pan: the camera is where it was (%s from %s)" % [str(scene.cam_center), str(c0)])
	await _leave(main)


# ------------------------------------------------------------------ the radio --

func test_a_card_is_a_contact_and_the_verbs_follow_it() -> void:
	var main := _game()
	var scene := _open(main, 3, [], "", false, true)
	var h = scene.hud_layer
	var dez = scene.run.squad[1]
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	h.cards[1].panel.gui_input.emit(ev)
	eq(scene.contact.get("kind", ""), "squad", "a click on Dez's card picks him")
	check(scene.contact.get("p") == dez, "")
	check(h.radio_verbs.contact == dez and h.radio_verbs.visible, "the verbs are for him")
	check(h.cards[1].selected, "his card is lit")
	eq(h.radio_verbs.buttons.size(), 6, "one button for each of the radio's six verbs")
	h.cards[0].panel.gui_input.emit(ev)
	check(scene.contact.get("p") == dez, "the card of the one you lead picks nobody")
	check(h.cards[0].you.visible and not h.cards[1].you.visible, "'YOU' is on their card only")
	await _leave(main)


func test_the_verbs_for_the_squad_go_through_the_place_hold_here_at_the_leader_search_that_at_the_pointer() -> void:
	var main := _game()
	var scene := _open(main, 3, [], "", false, true)
	var h = scene.hud_layer
	var lead = scene.leader()
	var dez = scene.run.squad[1]
	var ana = scene.run.squad[2]
	_put(lead, 9.5, 8.5)
	scene.select_contact("squad", dez)
	var r: Dictionary = h.radio_verbs.press("hold")
	check(bool(r.ok), "Dez agrees to hold: %s" % str(r))
	var asked: Dictionary = {}
	for e in scene.run.sim.radio.pending:
		if String(e.who) == String(dez.id):
			asked = e
	eq(String(asked.get("verb", "")), "hold", "the request is in the place's own radio")
	check(Vector2(asked.at).distance_to(Vector2(9.5, 8.5)) < 0.05, "hold here is where the leader stands: %s" % str(asked.at))
	_play(scene, 6.0)
	eq(String(dez.stance), "hold", "and after his delay he holds")
	# search that: the pointer is on the shelf
	_put(lead, 15.5, 8.5)
	_motion(scene, scene.to_screen(Vector2(21.5, 10.5)))
	_play(scene, 0.1)
	scene.select_contact("squad", ana)
	r = h.radio_verbs.press("search")
	check(bool(r.ok), "Ana agrees to search what the pointer is on: %s" % str(r))
	_play(scene, 5.0)
	eq(String(ana.stance), "search", "she has the stance")
	_play(scene, 25.0)
	check(scene.run.container("c2").looted, "and searched the shelf")
	await _leave(main)


func test_search_that_with_nothing_under_the_pointer_says_so() -> void:
	var main := _game()
	var scene := _open(main, 3, [], "", false, true)
	var h = scene.hud_layer
	var dez = scene.run.squad[1]
	_put(scene.leader(), 3.5, 12.5)
	_motion(scene, scene.to_screen(Vector2(2.5, 13.5)))
	_play(scene, 0.1)
	scene.select_contact("squad", dez)
	var r: Dictionary = h.radio_verbs.press("search")
	check(not bool(r.ok) and String(r.why) != "", "refused with a reason: %s" % str(r))
	check(h.toast_panel.visible and h.toast_label.text == String(r.why), "and the toast says it: %s" % h.toast_label.text)
	await _leave(main)


func test_go_back_sends_a_squad_member_to_the_exit_and_all_back_sends_everyone() -> void:
	var main := _game()
	var scene := _open(main, 3, [], "", false, true)
	var h = scene.hud_layer
	var dez = scene.run.squad[1]
	var ana = scene.run.squad[2]
	_put(scene.leader(), 20.5, 9.5)
	_put(dez, 18.5, 9.5)
	_put(ana, 19.5, 5.5)
	scene.select_contact("squad", dez)
	var r: Dictionary = h.radio_verbs.press("back")
	check(bool(r.ok), "Dez agrees to go back")
	_play(scene, 20.0)
	check(scene.in_exit(Vector2(dez.x, dez.y)), "he walked to the exit: %.1f, %.1f" % [dez.x, dez.y])
	check(not scene.in_exit(Vector2(ana.x, ana.y)), "and Ana was not asked")
	h.back_button.pressed.emit()
	_play(scene, 20.0)
	check(scene.in_exit(Vector2(ana.x, ana.y)), "'All back' sent her too")
	await _leave(main)


func test_a_person_with_you_who_cannot_come_says_why_in_the_panel() -> void:
	var main := _game()
	var scene := _open(main, 3, [], "", false, true)
	var h = scene.hud_layer
	var dez = scene.run.squad[1]
	dez.bleeding = 2.0
	scene.select_contact("squad", dez)
	var r: Dictionary = h.radio_verbs.press("cover")
	check(not bool(r.ok), "Dez, bleeding, will not")
	check(String(r.why).begins_with("Dez"), "and says why: %s" % r.why)
	check(h.radio_verbs.reply.text.contains("bleeding"), "the panel shows it: '%s'" % h.radio_verbs.reply.text)
	await _leave(main)


func test_to_the_walls_makes_no_sense_in_a_place_and_is_off() -> void:
	var main := _game()
	var scene := _open(main, 3, [], "", false, true)
	var h = scene.hud_layer
	scene.select_contact("squad", scene.run.squad[1])
	var st: Dictionary = h.radio_verbs.verb_state("post")
	check(not st.enabled and String(st.why).contains("No walls"), "off, with its reason: %s" % str(st))
	check(h.radio_verbs.buttons["post"].disabled, "the button is disabled")
	await _leave(main)


func test_the_people_at_the_base_are_contacts_too_and_only_back_and_the_walls_make_sense() -> void:
	var main := _game()
	var scene := _open(main, 2, [], "", false, true)
	var h = scene.hud_layer
	h.refresh()
	var marcus = main.sim.people[2]
	var base: Array = scene.base_contacts()
	check(base.has(marcus), "Marcus is at the base: %s" % str(_ids(base)))
	check(not base.has(main.sim.people[0]) and not base.has(main.sim.people[1]), "Ruth and Dez are away with the party")
	check(h.base_chips.has("marcus") and h.base_chips["marcus"].visible, "a chip for him")
	h.base_chips["marcus"].pressed.emit()
	eq(scene.contact.get("kind", ""), "base", "a click on the chip picks him")
	check(h.radio_verbs.contact == marcus, "the verbs are for him")
	for verb in ["come", "hold", "cover", "search"]:
		var st: Dictionary = h.radio_verbs.verb_state(verb)
		check(not st.enabled and String(st.why).contains("too far to follow"), "%s is off: '%s'" % [verb, st.why])
	for verb in ["back", "post"]:
		check(h.radio_verbs.verb_state(verb).enabled, "%s is on" % verb)
	var r: Dictionary = h.radio_verbs.press("post")
	check(bool(r.ok), "Marcus agrees to go to the walls: %s" % str(r))
	var asked := false
	for e in main.sim.radio.pending:
		asked = asked or (String(e.who) == "marcus" and String(e.verb) == "post")
	check(asked, "the request is in the BASE's radio, not the place's")
	for e in scene.run.sim.radio.pending:
		check(String(e.who) != "marcus", "(and not the place's)")
	await _leave(main)


func test_the_news_button_opens_the_log_and_the_calls_are_in_it() -> void:
	var main := _game()
	var scene := _open(main, 2, [], "", false, true)
	var h = scene.hud_layer
	var id: int = main.sim.radio.raise_call("attack", "The east wall is under attack", "Three of the dead are at it", [{"id": "hold", "label": "Hold"}, {"id": "help", "label": "Send help"}], "hold", 30.0)
	h.refresh()
	check(h.news_dot.visible, "something unread: the dot is on the button")
	h.news_button.pressed.emit()
	check(h.news_open and h.news_panel.visible, "the log is open")
	check(not h.news_dot.visible, "and it is read")
	check(h.news_panel.call_ids().has(id), "the call is in it")
	check(" ".join(Kit.texts(h.news_panel)).contains("east wall"), "with its words")
	_press(scene, KEY_T)
	check(not h.news_open and not h.news_panel.visible, "T shuts it")
	_press(scene, KEY_T)
	check(h.news_open, "and opens it")
	await _leave(main)


func test_a_call_that_waits_is_a_card_that_never_pauses_and_answering_settles_it() -> void:
	var main := _game()
	var scene := _open(main, 2, [], "", false, true)
	var h = scene.hud_layer
	check(not h.call_card.visible, "no card without a call")
	var id: int = main.sim.radio.raise_call("sick", "Marcus has a fever", "Keep him apart?", [{"id": "treat", "label": "Treat him"}, {"id": "apart", "label": "Keep him apart"}], "treat", 60.0)
	h.refresh()
	check(h.call_card.visible and h.call_card.shown_id == id, "the oldest open call is on the card")
	var t: float = scene.run.elapsed
	_play(scene, 1.0)
	check(scene.run.elapsed > t + 0.5, "the place goes on while it waits")
	check(not scene.paused, "nothing is paused")
	h.call_card.view.buttons["treat"].pressed.emit()
	eq(String(main.sim.radio._entry(id).answered), "treat", "the answer reaches the base's radio")
	await _leave(main)


func test_the_alarm_button_calls_everyone_at_the_base_to_arms_and_stands_them_down() -> void:
	var main := _game()
	var scene := _open(main, 2, [], "", false, true)
	var h = scene.hud_layer
	check(not main.sim.radio.alarm_on and h.alarm_button.text == "Alarm", "quiet")
	h.alarm_button.pressed.emit()
	check(main.sim.radio.alarm_on, "the alarm is up at the base")
	h.refresh()
	eq(h.alarm_button.text, "Stand down", "the button says what it does now")
	h.refresh()
	eq(String(PlaceFlow.base_state(main.sim).key), "alarm", "and the base's line says so")
	check(h.base_label.text.contains("alarm"), "in the HUD: '%s'" % h.base_label.text)
	h.alarm_button.pressed.emit()
	check(not main.sim.radio.alarm_on, "stood down")
	await _leave(main)


func test_the_hud_shows_the_ammunition_the_bases_clock_and_how_the_base_stands() -> void:
	var main := _game()
	var scene := _open(main, 3, [], "", false, true)
	var h = scene.hud_layer
	var lead = scene.leader()
	h.refresh()
	check(h.weapon_label.text.begins_with(String(lead.gun.name)), "the weapon: '%s'" % h.weapon_label.text)
	check(h.weapon_label.text.ends_with("%d / %d" % [lead.mag, int(lead.gun.mag)]), "with the magazine: '%s'" % h.weapon_label.text)
	check(h.stock_label.text.contains("%d" % int(scene.run.sim.stock.ammo)), "and the stock: '%s'" % h.stock_label.text)
	lead.mag = 3
	h.refresh()
	check(h.weapon_label.text.ends_with("3 / %d" % int(lead.gun.mag)), "the magazine follows: '%s'" % h.weapon_label.text)
	near(h.mag_bar.value, 3.0 / float(lead.gun.mag), 0.001, "the bar is the magazine")
	lead.reloading = float(lead.gun.reload) * 0.5
	h.refresh()
	check(h.stock_label.text.begins_with("Reloading"), "reloading says so: '%s'" % h.stock_label.text)
	near(h.mag_bar.value, 0.5, 0.05, "the bar is the reload")
	check(h.clock_label.text.begins_with("Day %d, " % int(main.sim.day)), "the base's day and hour: '%s'" % h.clock_label.text)
	check(h.base_label.text.begins_with("Base: ") and h.base_label.text.contains("walls"), "the base's state: '%s'" % h.base_label.text)
	main.sim.minutes = 22.0 * 60.0
	main.sim.phase = "night"
	h.refresh()
	eq(h.mood_label.text, "NIGHT", "the mood is night")
	check(h.clock_label.text.contains("22:"), "'%s'" % h.clock_label.text)
	var z = main.sim.spawn(30.0, 20.0, "wander")
	z.state = "attack"
	h.refresh()
	check(h.base_label.text.contains("attack"), "the dead at the wall: '%s'" % h.base_label.text)
	await _leave(main)


func test_the_place_is_lit_by_the_colonys_hour() -> void:
	var main := _game()
	var scene := _open(main, 2)
	main.sim.minutes = 12.0 * 60.0
	scene._update_tint()
	var noon: Color = scene.tint.color
	main.sim.minutes = 23.0 * 60.0
	scene._update_tint()
	var night: Color = scene.tint.color
	check(night.r + night.g + night.b < noon.r + noon.g + noon.b - 0.4, "a night is darker than noon: %s against %s" % [str(night), str(noon)])
	check(night.b > night.r, "and bluer")
	check(night.r + night.g + night.b > 1.4, "but never so dark that it cannot be played: %s" % str(night))
	await _leave(main)


# -------------------------------------------------------------- succession --

func test_when_the_leader_falls_the_next_leads_the_camera_goes_there_and_the_base_is_told_when_the_trip_ends() -> void:
	var main := _game()
	var scene := _open(main, 3, [], "", false, true)
	var h = scene.hud_layer
	var ruth = scene.leader()
	var dez = scene.run.squad[1]
	var ana = scene.run.squad[2]
	dez.trust = 80.0
	ana.trust = 60.0
	_put(ruth, 13.5, 8.5)
	_put(dez, 18.5, 8.5)
	_put(ana, 13.5, 6.5)
	var cs = main.sim
	var trust0: float = cs.people[2].trust
	scene.zoom_px = 50.0
	scene.cam_center = Vector2(13.5, 8.5)
	_motion(scene, scene._vp() / 2.0)
	ruth.hp = 0.0
	ruth.downed = true
	_play(scene, 0.1)
	check(scene.leader() == dez, "Dez, the most trusted, leads now")
	eq(h.banner_title.text, "DEZ LEADS NOW", "the banner says so")
	check(h.banner_sub.text.contains("Ruth"), "and who fell: %s" % h.banner_sub.text)
	# (she is only down: she may be got up and come home, so the base is told when the trip is over and she is lost, not before)
	eq(cs.player_id, "ruth", "the base's player is still Ruth")
	near(cs.people[2].trust, trust0, 0.01, "nobody trusts the player less yet")
	_play(scene, 2.5)
	check(scene.cam_center.x > 17.0, "the camera glided to him (as far as the map lets it): %s" % str(scene.cam_center))
	check(h.cards[1].you.visible and not h.cards[0].you.visible, "'YOU' moved to his card")
	var dx: float = dez.x
	_press(scene, KEY_S)
	_play(scene, 0.5)
	check(dez.y > 9.5, "and the keys walk him now: %.2f" % dez.y)
	check(absf(dez.x - dx) < 0.5, "")
	_release(scene, KEY_S)
	var heard := false
	for e in cs.radio.news:
		heard = heard or String(e.kind) == "succession"
	check(not heard, "the base's radio has no news of a loss yet")
	# the trip ends with her among the lost: now the base is told, once, with the place's heir
	_walk_out(scene)
	check(scene.final_result.lost.has("ruth"), "Ruth is lost in the result")
	eq(cs.player_id, "dez", "the base's player is the one who led at the end")
	check(cs.people[1].player and not cs.people[0].player, "the flag moved there too")
	check(cs.people[2].trust < trust0, "the base trusts the player less: %.1f from %.1f" % [cs.people[2].trust, trust0])
	cs.update(STEP)
	for e in cs.radio.news:
		heard = heard or String(e.kind) == "succession"
	check(heard, "the base's radio has the news")
	await _leave(main)


func test_a_lone_leader_who_falls_ends_the_trip_and_the_report_says_so() -> void:
	var main := _game()
	var scene := _open(main, 1)
	var h = scene.hud_layer
	var ruth = scene.leader()
	ruth.downed = true
	ruth.hp = 0.0
	_play(scene, 0.2)
	check(scene.ended, "nobody can stand: the trip is over")
	eq(h.end_title.text, "Nobody came back", "the card says so")
	check(h.end_sub.text.contains("lost"), h.end_sub.text)
	await _leave(main)


# ------------------------------------------------------------------ the way out --

func test_the_squad_begins_in_the_exit_and_that_is_not_the_way_out() -> void:
	var main := _game()
	var scene := _open(main)
	_play(scene, 1.0)
	check(scene.in_exit(Vector2(scene.leader().x, scene.leader().y)), "(they start in the exit)")
	eq(scene.run.phase, "play", "and the place does not end by it")
	check(not scene.ended, "")
	await _leave(main)


func test_the_leader_in_the_exit_with_everyone_alive_ends_the_place() -> void:
	var main := _game()
	var scene := _open(main)
	var squad: Array = scene.run.squad
	_put(squad[0], 12.5, 8.5)
	_put(squad[1], 12.0, 9.0)
	_put(squad[2], 12.0, 8.0)
	_play(scene, 0.2)
	check(scene._was_out, "they have been out")
	# the leader walks back; the others follow into the exit
	_put(squad[0], 3.5, 8.5)
	_put(squad[1], 4.5, 8.0)
	_put(squad[2], 8.5, 8.0)
	_play(scene, 0.1)
	check(not scene.waiting_names().is_empty(), "Ana is still out there: %s" % str(scene.waiting_names()))
	check(scene.hint_line().begins_with("Waiting for"), scene.hint_line())
	check(not scene.ended, "so it does not end")
	_put(squad[2], 4.0, 9.0)
	_play(scene, 0.5)
	check(scene.ended, "everyone in the exit: the place is over")
	eq(scene.phase, "report", "(no flow: the report is up at once)")
	await _leave(main)


func test_someone_down_does_not_keep_the_place_from_ending_and_is_lost() -> void:
	var main := _game()
	var scene := _open(main)
	var squad: Array = scene.run.squad
	_put(squad[0], 12.5, 8.5)
	_play(scene, 0.1)
	squad[2].downed = true
	squad[2].hp = 0.0
	_put(squad[2], 12.0, 8.0)
	_put(squad[0], 3.5, 8.5)
	_put(squad[1], 4.0, 9.0)
	_play(scene, 0.5)
	check(scene.ended, "over")
	check(scene.final_result.lost.has(String(squad[2].id)), "the one who was down is lost")
	await _leave(main)


# ----------------------------------------------------------------- the HUD --

func test_the_cards_follow_the_squad_health_weapon_and_what_they_do() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	var squad: Array = scene.run.squad
	h.refresh()
	for i in 3:
		var c: Dictionary = h.cards[i]
		eq(c.name.text, squad[i].first, "the card says whose it is")
		check(String(c.weapon.text).begins_with(String(squad[i].gun.name)), "and what they carry: %s" % c.weapon.text)
		check(String(c.weapon.text).ends_with("%d/%d" % [squad[i].mag, int(squad[i].gun.mag)]), "with the magazine: %s" % c.weapon.text)
		near(c.hp.anchor_right, 1.0, 0.001, "a full bar")
		check(c.pic.texture != null, "a face")
	eq(h.cards[0].status.text, "You", "the one you lead")
	eq(h.cards[1].status.text, "Following", "the others follow, by default")
	squad[1].hp = 30.0
	squad[1].mag = 2
	h.refresh()
	near(h.cards[1].hp.anchor_right, 0.3, 0.001, "the bar follows their health")
	check(String(h.cards[1].weapon.text).ends_with("2/%d" % int(squad[1].gun.mag)), "and the magazine: %s" % h.cards[1].weapon.text)
	squad[1].stance = "hold"
	squad[2].stance = "cover"
	h.refresh()
	eq(h.cards[1].status.text, "Holding", "a stance reads on the card")
	eq(h.cards[2].status.text, "Covering", "")
	squad[2].downed = true
	h.refresh()
	eq(h.cards[2].status.text, "Down", "a person who is down says so")
	squad[1].dead = true
	h.refresh()
	eq(h.cards[1].status.text, "Lost", "and one who is gone")
	await _leave(main)


func test_the_tally_shows_what_is_in_the_bags_by_stock_and_how_full_they_are() -> void:
	var main := _game()
	var scene := _open(main, 2)
	var h = scene.hud_layer
	var lead = scene.leader()
	_put(lead, 16.5, 6.5)
	h.refresh()
	eq(h.bags_label.text, "0 of %d" % (2 * RaidRun.CARRY), "empty bags")
	check(h.empty_label.visible, "'Nothing yet'")
	for stock in h.chips:
		check(not h.chips[stock].box.visible, "no %s yet" % stock)
	_press(scene, KEY_E)
	_play(scene, 5.0)
	h.refresh()
	eq(h.bags_label.text, "14 of %d" % (2 * RaidRun.CARRY), "ten food and four meds make fourteen")
	check(h.chips.food.box.visible and h.chips.food.num.text == "10", "ten food")
	check(h.chips.meds.box.visible and h.chips.meds.num.text == "4", "four meds")
	check(not h.chips.scrap.box.visible and not h.empty_label.visible, "nothing else, and no 'Nothing yet'")
	near(h.bag_fill.anchor_right, 14.0 / float(2 * RaidRun.CARRY), 0.001, "the bar is a share of the room")
	scene.run.carried["fuel"] = 6
	h.refresh()
	check(h.chips.fuel.box.visible and h.chips.fuel.num.text == "6", "a stock with no icon still shows")
	await _leave(main)


func test_the_log_shows_the_last_four_lines_and_they_fade() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	h.refresh()
	check(not h.log_panel.visible, "no log while nothing has happened")
	for i in 6:
		scene.run.log.append("Line %d" % i)
	h.refresh()
	check(h.log_panel.visible, "the log shows")
	var shown: Array = []
	for l in h.log_labels:
		if l.visible:
			shown.append(l.text)
	eq(shown, ["Line 2", "Line 3", "Line 4", "Line 5"], "the last four")
	scene.clock += RaidHud.LOG_HOLD + RaidHud.LOG_FADE * 0.5
	h.refresh()
	var a: float = h.log_labels[0].modulate.a
	check(a > 0.2 and a < 0.8, "halfway through the fade: %.2f" % a)
	scene.clock += RaidHud.LOG_FADE
	h.refresh()
	check(not h.log_panel.visible, "and gone")
	await _leave(main)


func test_the_legend_shows_at_first_fades_and_has_the_new_keys() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	check(h.legend_panel.visible and h.legend_panel.modulate.a > 0.99, "at first")
	var words: Array = Kit.texts(h.legend_panel)
	var joined := " ".join(words)
	for want in ["W", "A", "S", "D", "Click", "R", "F", "E", "Space", "Scroll", "walk", "shoot", "reload", "melee", "search", "pause", "zoom"]:
		check(words.has(want) or joined.contains(want), "the legend has '%s': %s" % [want, str(words)])
	for gone in ["Right-click", "Tab", "retreat", "select", "follow", "Drag"]:
		check(not words.has(gone) and not joined.contains(" %s " % gone), "and not the old '%s': %s" % [gone, str(words)])
	_play(scene, RaidHud.LEGEND_HOLD + 1.0)
	h.refresh()
	check(not h.legend_panel.visible, "it fades away")
	await _leave(main)


func test_the_place_panel_names_the_place_and_says_what_to_do() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	eq(h.place_label.text, "The test house", "the place's name")
	check(h.line_label.text.contains("press E"), "at first it says how to search: %s" % h.line_label.text)
	scene.run.squad[1].downed = true
	check(scene.hint_line().contains("%s is down" % scene.run.squad[1].first), "a friend down: %s" % scene.hint_line())
	scene.run.squad[1].downed = false
	for c in scene.run.containers:
		c.looted = true
	check(scene.hint_line().begins_with("Everything is searched"), "all searched: %s" % scene.hint_line())
	await _leave(main)


func test_the_bags_are_full_says_so() -> void:
	var main := _game()
	var scene := _open(main, 1)
	scene.run.carried = {"scrap": RaidRun.CARRY}
	check(scene.hint_line().begins_with("The bags are full"), scene.hint_line())
	scene.hud_layer.refresh()
	eq(scene.hud_layer.bag_fill.color, Hud.DANGER, "and the bar is red")
	await _leave(main)


func test_a_banner_for_the_dead_who_hear_and_one_for_a_friend_who_falls() -> void:
	var main := _game()
	var scene := _open(main, 3, [{"pos": Vector2(14.5, 14.5), "kind": "walker", "state": "still"}])
	var h = scene.hud_layer
	_play(scene, 0.2)
	# the scene is put back to where the test means it to be: asleep, 11 tiles from the shot, nobody hunting yet and no banner
	# shown (the wake-up of a dead man who stands about and the banner's own clock depend on what the earlier tests drew at
	# random, so the state is not left to chance)
	for z in scene.run.sim.zombies:
		z.state = "still"
		z.x = 14.5
		z.y = 14.5
		z.stagger = 1.0e6
	scene._hunters = 0
	scene._heard = false
	scene._banner_t = -99.0
	scene.run._noise(Vector2(5.5, 8.5))
	scene.run.events.append({"type": "shot", "weapon": "rifle", "x": 5.5, "y": 8.5})
	scene.tick(STEP)
	eq(h.banner_title.text, "THEY HEARD THAT", "a shot wakes the dead")
	check(h.banner_sub.text != "" and h.banner.visible, "the banner is up")
	check(scene.run.events.is_empty(), "the events were taken")
	scene.clock += 10.0
	scene.run.squad[2].downed = true
	scene.tick(STEP)
	eq(h.banner_title.text, "%s IS DOWN" % String(scene.run.squad[2].first).to_upper(), "a friend down")
	check(String(h.banner_sub.text).contains("press E"), "and what to do: %s" % h.banner_sub.text)
	scene.clock += 0.5
	scene.run.squad[1].downed = true
	scene.tick(STEP)
	check(not h.banner_title.text.begins_with(String(scene.run.squad[1].first).to_upper()), "banners are not a flood: one at a time")
	await _leave(main)


func test_hunters_are_marked_over_their_heads() -> void:
	var main := _game()
	var scene := _open(main, 3, [{"pos": Vector2(9.5, 8.5), "kind": "walker", "state": "still"}])
	scene.run._noise(Vector2(5.5, 8.5))
	scene.tick(STEP)
	await TutorialKit.settle()
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	check(scene.overlay.drawn_hunters >= 1, "a red mark over the one that hunts")
	await _leave(main)


func test_the_overlay_draws_the_crosshair_the_aim_line_the_prompt_and_the_reload_ring() -> void:
	var main := _game()
	var scene := _open(main)
	var lead = scene.leader()
	_put(lead, 16.5, 6.5)
	_motion(scene, scene.to_screen(Vector2(19.5, 8.5)))
	scene.over_hud = false
	_play(scene, 0.2)
	await TutorialKit.settle()
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	check(scene.overlay.drawn_crosshair, "the crosshair is at the pointer")
	check(scene.overlay.drawn_aim_line, "and the aim line leaves the muzzle")
	check(scene.overlay.drawn_prompt.begins_with("E  Search the cabinet"), "the prompt on the cabinet: '%s'" % scene.overlay.drawn_prompt)
	lead.mag = 0
	_press(scene, KEY_R)
	_play(scene, 0.1)
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	check(scene.overlay.drawn_reload_ring, "a reload ring about them")
	scene.over_hud = true
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	check(not scene.overlay.drawn_crosshair, "none over the HUD")
	await _leave(main)


func test_the_aim_line_in_a_place_stops_where_the_shot_stops() -> void:
	var main := _game()
	var scene := _open(main)
	var lead = scene.leader()
	var reach: float = float(scene.run.sim.reach_of(lead.gun, lead))
	check(reach > 4.0, "(the gun reaches past the wall: %.1f tiles)" % reach)
	# the pointer is on the far side of the house's west wall (x 14, no door at this height): the line stops at the wall
	_put(lead, 11.5, 5.5)
	_motion(scene, scene.to_screen(Vector2(20.5, 5.5)))
	scene.over_hud = false
	_play(scene, 0.2)
	await TutorialKit.settle()
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	check(scene.overlay.drawn_aim_line, "the aim line is drawn")
	check(scene.overlay.aim_end.x > 12.5 and scene.overlay.aim_end.x < 14.2, "and ends at the wall, not at the pointer or the reach: %s" % str(scene.overlay.aim_end))
	# the same line at the door's height goes through it, as far as the gun reaches or the pointer is
	_put(lead, 11.5, 8.5)
	_motion(scene, scene.to_screen(Vector2(20.5, 8.5)))
	scene.over_hud = false
	_play(scene, 0.2)
	await TutorialKit.settle()
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	check(scene.overlay.aim_end.x > 15.0, "through the door it goes on: %s" % str(scene.overlay.aim_end))
	# and it stops at the first of the dead it would hit
	scene.run.sim.zombies.clear()
	var z = scene.run.sim.spawn(13.0, 8.5, "still")
	_play(scene, 0.1)
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	check(scene.overlay.aim_end.x > 12.5 and scene.overlay.aim_end.x < 13.6, "a body in the way: the line ends on it: %s" % str(scene.overlay.aim_end))
	await _leave(main)


func test_the_sounds_of_the_run_are_played_and_the_events_taken() -> void:
	var main := _game()
	var scene := _open(main)
	check(main.sound != null, "the game has its sound")
	scene.run.events.append({"type": "shot", "weapon": "rifle", "x": 5.0, "y": 8.0})
	scene.run.events.append({"type": "bite", "x": 5.0, "y": 8.0})
	scene.run.events.append({"type": "searched", "id": "c1"})
	scene.run.events.append({"type": "groan", "x": 9.0, "y": 8.0, "kind": "brute"})
	scene.run.events.append({"type": "no_such_event"})
	scene.tick(STEP)
	check(scene.run.events.is_empty(), "all of them taken, known or not")
	await _leave(main)


# ------------------------------------------------------------------ the end --

## Plays the place to its end: the leader walks into the exit with everyone (after the place has been left once).
func _walk_out(scene: Node) -> void:
	scene._was_out = true
	var spot: Vector2 = scene.site.exit.get_center()
	for p in scene.run.squad:
		if not p.dead and not p.downed:
			_put(p, spot.x + randf_range(-0.8, 0.8), spot.y + randf_range(-0.6, 0.6))
	_play(scene, 1.0)


func test_the_end_card_shows_the_result_and_go_home_sends_it_once() -> void:
	var main := _game()
	var scene := _open(main, 3)
	var h = scene.hud_layer
	var lead = scene.leader()
	_put(lead, 16.5, 6.5)
	_press(scene, KEY_E)
	_play(scene, 5.0)
	scene.run.squad[1].hp = 40.0
	scene.run._bitten[String(scene.run.squad[1].id)] = true
	_walk_out(scene)
	check(scene.ended and h.end_card != null and h.end_card.visible, "the end card is up")
	var title: String = h.end_title.text
	eq(title, "Back from the test house", "'Back from' the place")
	check(String(h.end_sub.text).contains(scene.run.squad[1].first), "and who came back hurt: %s" % h.end_sub.text)
	var texts := Kit.texts(h.end_card)
	check(texts.has("10") and texts.has("4"), "what came home, by stock: %s" % str(texts))
	check(texts.has(scene.run.squad[1].first), "who is hurt")
	check(texts.has("Nobody"), "and nobody is lost")
	check(texts.has("The dead still hold it") or texts.has("Cleared of the dead"), "the place: %s" % str(texts))
	check(h.end_rows.has("ammo"), "the ammo used")
	check(not h.radio_panel.visible and not h.legend_panel.visible and not h.weapon_panel.visible, "the rest of the HUD makes room")
	var got: Array = []
	scene.finished.connect(func(r): got.append(r))
	var expect: Dictionary = scene.run.result()
	h.end_button.pressed.emit()
	scene.go_home()
	_press(scene, KEY_ENTER)
	eq(got.size(), 1, "finished is emitted once however it is asked")
	eq(got[0].loot, expect.loot, "with the run's loot")
	eq(got[0].hurt, expect.hurt, "its hurt")
	eq(got[0].lost, expect.lost, "its lost")
	check(got[0].has("clear") == expect.has("clear") and got[0].has("ammo_used") and got[0].has("beats"), "and the rest of the trip's format")
	await TutorialKit.frames(main, 2)
	check(not is_instance_valid(scene), "the scene frees itself")
	await _leave(main)


func test_enter_dismisses_the_end_card_and_nothing_else_does() -> void:
	var main := _game()
	var scene := _open(main, 1)
	_walk_out(scene)
	check(scene.ended, "over")
	var got: Array = []
	scene.finished.connect(func(r): got.append(r))
	for code in [KEY_SPACE, KEY_R, KEY_ESCAPE, KEY_TAB, KEY_A]:
		scene.key_pressed(code)
	eq(got.size(), 0, "no other key sends them home")
	_press(scene, KEY_ENTER)
	eq(got.size(), 1, "Enter does")
	await _leave(main)


func test_when_everyone_is_lost_the_card_says_nobody_came_back() -> void:
	var main := _game()
	var scene := _open(main, 2)
	scene.run.carried = {"food": 5}
	for p in scene.run.squad:
		p.downed = true
	_play(scene, 1.0)
	check(scene.ended, "nobody can go on")
	eq(scene.hud_layer.end_title.text, "Nobody came back", "the title")
	check(scene.hud_layer.end_sub.text.contains("lost"), scene.hud_layer.end_sub.text)
	check(Kit.texts(scene.hud_layer.end_card).has("Nothing"), "and nothing came home")
	await _leave(main)


func test_a_rescue_and_a_cleared_place_are_on_the_card() -> void:
	var main := _game()
	var scene := _open(main, 1, [], "", true)
	var lead = scene.leader()
	var spot: Vector2 = scene.run.container("survivor").pos
	_put(lead, spot.x, spot.y)
	_play(scene, 0.2)
	_press(scene, KEY_E)
	_play(scene, 8.0)
	check(scene.run.container("survivor").looted, "the survivor is found")
	_walk_out(scene)
	check(scene.ended, "over")
	var texts := Kit.texts(scene.hud_layer.end_card)
	check(texts.has("Found, and coming home with you"), "someone was found: %s" % str(texts))
	check(texts.has("Cleared of the dead"), "no dead were there: %s" % str(texts))
	await _leave(main)


func test_ending_costs_no_nodes_and_no_stray_state() -> void:
	var main := _game()
	await TutorialKit.frames(main, 3)
	var before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var scene := _open(main, 3, [{"pos": Vector2(9.5, 8.5), "kind": "walker", "state": "still"}, {"pos": Vector2(20.5, 10.5), "kind": "runner", "state": "still"}], "van")
	_play(scene, 5.0)
	scene.run._noise(Vector2(5.5, 8.5))
	_play(scene, 10.0)
	_walk_out(scene)
	_play(scene, 5.0)
	scene.go_home()
	await TutorialKit.frames(main, 4)
	eq(Performance.get_monitor(Performance.OBJECT_NODE_COUNT), before, "the same number of nodes as before the raid")
	check(main.get_children().filter(func(c): return c is RaidScene).is_empty(), "no raid scene is left")
	await _leave(main)


func test_a_scene_freed_without_going_home_still_gives_the_colony_back() -> void:
	var main := _game()
	main.speed = 1
	var scene := _open(main)
	check(not main.world.visible, "held")
	scene.free()
	eq(main.speed, 1, "the speed is as it was")
	check(main.world.visible and main.hud.visible and main.raid == null, "and the yard shows")
	await _leave(main)


# --------------------------------------------------------------- open_raid --

func test_two_raids_cannot_be_open_at_once() -> void:
	var main := _game()
	main.raid_stub = true
	var done: Array = []
	var scene = main.open_raid([main.sim.people[1]], main.sim.town.place("houses"), "", 1.0, func(r): done.append(r))
	check(scene != null and main.raid == scene, "the first opens")
	check(main.open_raid([main.sim.people[2]], main.sim.town.place("houses"), "", 1.0, Callable()) == null, "a second does not")
	_abandon(main, scene)
	var lone = main.open_raid([], main.sim.town.place("houses"), "", 1.0, Callable())
	check(lone != null and lone.run.squad.size() == 1 and String(lone.leader().id) == "ruth", "with nobody picked the player goes alone")
	_abandon(main, lone)
	await _leave(main)


func test_open_raid_asks_begins_and_puts_the_road_first() -> void:
	var main := _game()
	main.raid_stub = true
	var place: Dictionary = main.sim.town.place("houses")
	var done: Array = []
	var scene = main.open_raid([main.sim.people[1]], place, "", 1.0, func(r): done.append(r))
	check(scene != null and main.raid_open(), "the raid is open")
	eq(scene.phase, "road_there", "on the road first")
	eq(scene.run.squad.size(), 2, "with Ruth, the avatar, and Dez, who was asked")
	eq(String(scene.leader().id), "ruth", "she leads")
	eq(String(scene.site.name), String(place.name), "at the place")
	check(main.sim.people[0].away != null and main.sim.people[1].away != null, "both are gone from the base")
	check(scene.hud_layer.road_panel.visible, "the road's overlay is up")
	check(scene.hud_layer.road_title_label.text.begins_with("Walking to "), "'%s'" % scene.hud_layer.road_title_label.text)
	check(not main.menu_open or main.raid_open(), "")
	scene.free()
	await _leave(main)


func test_open_raid_leaves_out_who_the_radio_says_cannot_come_and_says_why() -> void:
	var main := _game()
	main.raid_stub = true
	var dez = main.sim.people[1]
	dez.bleeding = 2.0
	var scene = main.open_raid([dez, main.sim.people[2]], main.sim.town.place("houses"), "", 1.0, Callable())
	check(scene != null, "the trip opens")
	eq(_ids(scene.run.squad), ["ruth", "marcus"], "without Dez")
	check(dez.away == null, "who is still at the base")
	# (the colony's HUD is hidden once the trip is up, so a toast there is never seen: the reason is on the road's overlay, and in
	# the report; tests/test_round17_views.gd has the whole of it)
	eq(scene.flow.refusals.size(), 1, "the flow keeps why")
	check(String(scene.flow.refusals[0]).begins_with("Dez"), "it names him: '%s'" % str(scene.flow.refusals))
	check(scene.hud_layer.road_panel.visible and scene.hud_layer.road_refusals == scene.flow.refusals, "and the road's overlay shows it: %s" % str(scene.hud_layer.road_refusals))
	scene.free()
	await _leave(main)


func test_open_raid_refused_by_the_rules_says_why_and_nobody_goes() -> void:
	var main := _game()
	main.raid_stub = true
	main.sim.minutes = 21.0 * 60.0
	main.sim.phase = main.sim.phase_at(main.sim.minutes)
	var scene = main.open_raid([main.sim.people[1]], main.sim.town.place("houses"), "", 1.0, Callable())
	check(scene == null and not main.raid_open(), "no trip after dark")
	check(main.hud.toast_label.text != "" and main.hud.toast_label.text.contains("dark"), "the toast says why: '%s'" % main.hud.toast_label.text)
	eq(main.sim.scavenge.parties.size(), 0, "nobody is away")
	await _leave(main)


func test_the_same_place_and_run_make_the_same_site_and_a_seed_can_be_given() -> void:
	var main := _game()
	main.raid_stub = true
	var place: Dictionary = main.sim.town.place("houses")
	var a = main.open_raid([main.sim.people[1]], place, "", 1.0, Callable())
	var seed_a: int = int(a.site.seed)
	_abandon(main, a)
	var b = main.open_raid([main.sim.people[1]], place, "", 1.0, Callable())
	eq(int(b.site.seed), seed_a, "the same place, run and day: the same seed")
	_abandon(main, b)
	main._stage_raid("houses,77")
	eq(int(main.raid.site.seed), 77, "--raid=houses,77 fixes it")
	_abandon(main, main.raid)
	main._stage_raid("pharmacy")
	eq(String(main.raid.site.kind), "pharmacy", "a place by its id")
	_abandon(main, main.raid)
	await _leave(main)


## Frees a trip's scene and gives its party back to the base (a test that opens more than one).
func _abandon(main: Node, scene: Node) -> void:
	var party: Dictionary = main.sim.scavenge.party_in_place()
	scene.free()
	if not party.is_empty():
		main.sim.scavenge.finish_played(party, {})
		for p in main.sim.people:
			p.away = null
		main.sim.scavenge.parties.clear()


func test_stage_raid_takes_a_kind_and_the_first_three_people() -> void:
	var main := _game()
	main.raid_stub = true
	main._stage_raid("bakery")
	check(main.raid_open(), "open")
	eq(String(main.raid.site.kind), "bakery", "the first place of that kind")
	eq(main.raid.run.squad.size(), 3, "the three of the small start")
	main.raid.stage("go+wait:1+pause")
	check(main.raid.paused and main.raid.phase == "place", "the staging's steps are run")
	_abandon(main, main.raid)
	await _leave(main)


func test_a_place_with_someone_hiding_in_it_has_a_survivor_to_find() -> void:
	var main := _game()
	main.raid_stub = true
	var place: Dictionary = main.sim.town.place("church")
	check(bool(place.get("survivor", false)), "the church has someone in it")
	var scene = main.open_raid([main.sim.people[1]], place, "", 1.0, Callable())
	check(scene != null and scene.has_survivor and not scene.run.container("survivor").is_empty(), "so the run has a spot to find them")
	_abandon(main, scene)
	main.sim.town.state["church"]["rescued"] = true
	var again = main.open_raid([main.sim.people[1]], place, "", 1.0, Callable())
	check(not again.has_survivor, "not once they are home")
	_abandon(main, again)
	var plain = main.open_raid([main.sim.people[1]], main.sim.town.place("houses"), "", 1.0, Callable())
	check(not plain.has_survivor, "and a place with nobody has nobody")
	_abandon(main, plain)
	await _leave(main)


func test_stage_raid_can_go_in_a_vehicle() -> void:
	var main := _game()
	main.raid_stub = true
	main._stage_raid("houses,9,van")
	check(main.raid_open() and main.raid.vehicle_node != null, "the van is drawn")
	eq(main.raid.run.vehicle_kind, "van", "and the run knows it")
	check(main.raid.hud_layer.road_title_label.text.begins_with("Driving to "), "'%s'" % main.raid.hud_layer.road_title_label.text)
	_abandon(main, main.raid)
	await _leave(main)


# ------------------------------------------------------- the real pointer --

## A mouse button pushed into the window as the real pointer's would be: the HUD sees it first, then the world.
func _push(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = at
	ev.global_position = at
	ev.pressed = pressed
	Engine.get_main_loop().root.push_input(ev)


func test_real_clicks_reach_the_world_through_the_hud_and_the_cards_get_theirs() -> void:
	var main := _game()
	var scene := _open(main)
	await TutorialKit.settle()
	scene.hud_layer.refresh()
	await TutorialKit.settle()
	var world_at := Vector2(scene._vp().x * 0.45, scene._vp().y * 0.6)
	_push(world_at, MOUSE_BUTTON_LEFT, true)
	check(scene.fire_held, "a press in the world holds the trigger")
	_push(world_at, MOUSE_BUTTON_LEFT, false)
	check(not scene.fire_held, "and the release lets it go")
	var card: Rect2 = scene.hud_layer.cards[1].panel.get_global_rect()
	_push(card.get_center(), MOUSE_BUTTON_LEFT, true)
	_push(card.get_center(), MOUSE_BUTTON_LEFT, false)
	eq(String(scene.contact.get("p", scene.leader()).id), String(scene.run.squad[1].id), "a click on a card asks that person")
	check(not scene.fire_held, "and does not fire")
	await _leave(main)


# ---------------------------------------------------- the classic game as ever --

func test_without_a_raid_the_game_is_not_in_a_menu() -> void:
	var main := _game()
	check(main.raid == null and not main.raid_open() and not main.menu_open, "no raid, no menu")
	await _leave(main)


func test_a_game_with_no_avatar_opens_a_trip_as_the_old_one_did_with_nobody_asked() -> void:
	var main := _game(1280, 800, 3, false)
	main.raid_stub = true
	var dez = main.sim.people[1]
	dez.bleeding = 2.0
	var scene = main.open_raid([dez, main.sim.people[0]], main.sim.town.place("houses"), "", 1.0, Callable())
	check(scene != null, "it opens")
	eq(_ids(scene.run.squad), ["dez", "ruth"], "as picked, bleeding or not (nobody is asked without an avatar)")
	check(scene.leader() == scene.run.squad[0], "and the first leads")
	_abandon(main, scene)
	check(main.open_raid([], main.sim.town.place("houses"), "", 1.0, Callable()) == null, "(and with no avatar nobody picked is nobody going)")
	await _leave(main)


# --------------------------------------------------------- layout and text --

func _hud_rects(h) -> Dictionary:
	var out := {
		"place": Kit.rect(h.place_panel), "loot": Kit.rect(h.loot_panel), "cards": Kit.rect(h.cards_grid), "radio": Kit.rect(h.radio_panel),
		"log": Kit.rect(h.log_panel), "legend": Kit.rect(h.legend_panel), "weapon": Kit.rect(h.weapon_panel), "base": Kit.rect(h.base_panel),
		"banner": Kit.rect(h.banner), "toast": Kit.rect(h.toast_panel),
	}
	if h.call_card.visible:
		out["call"] = Kit.rect(h.call_card)
	if h.news_panel.visible:
		out["news"] = Kit.rect(h.news_panel)
	return out


## Everything the HUD can show at once: cards, bags with stocks, a log, the legend, a banner, a toast, a contact's verbs and a call.
func _busy(width: int, height: int, n: int = 3, news: bool = false) -> Dictionary:
	var main := _game(width, height)
	var scene := _open(main, n, [], "", false, true)
	scene.select_contact("squad", scene.run.squad[1])
	scene.run.carried = {"food": 10, "water": 12, "scrap": 25, "ammo": 6, "meds": 4, "fuel": 3}
	for line in ["Dez searched the cabinet: 10 food, 4 meds.", "Ruth took 6 water from the crate; the bags are full, some is left.", "Marcus was bitten.", "Ruth got Dez back on their feet."]:
		scene.run.log.append(line)
	main.sim.radio.raise_call("attack", "The east wall is under attack", "Three of the dead are at it", [{"id": "hold", "label": "Hold"}, {"id": "help", "label": "Send help"}], "hold", 30.0)
	scene.hud_layer.show_banner("They heard that", "The dead nearby are coming")
	scene.hud_layer.toast("Aim at a shelf or a crate first")
	scene.paused = true
	if news:
		scene.hud_layer.open_news(true)
	scene.hud_layer.refresh()
	await TutorialKit.settle()
	scene.hud_layer.refresh()
	await TutorialKit.settle()
	scene.hud_layer.refresh()
	return {"main": main, "scene": scene}


func test_nothing_in_the_raid_hud_overlaps_at_any_width() -> void:
	for w in WIDTHS:
		var height := 560 if w == 700 else 800
		var ctx: Dictionary = await _busy(w, height)
		var h = ctx.scene.hud_layer
		var rects := _hud_rects(h)
		# (a narrow window has one column at the left: the log and the legend are left out while there is no room for them)
		for k in ["place", "loot", "cards", "radio", "weapon", "base", "banner", "toast", "call"] + (["log", "legend"] if w >= RaidHud.WIDE_W else []):
			check(rects.has(k) and rects[k].size != Vector2.ZERO, "%d wide: the %s shows" % [w, k])
		eq(Kit.overlaps(rects), [], "%d wide" % w)
		var win := Rect2(0, 0, w, height)
		for k in rects:
			if rects[k].size == Vector2.ZERO:
				continue
			check(win.encloses(rects[k].grow(-0.5)), "%d wide: the %s is inside the window: %s" % [w, k, str(rects[k])])
		await _leave(ctx.main)


func test_nothing_overlaps_with_the_news_open_either() -> void:
	for w in WIDTHS:
		var height := 560 if w == 700 else 800
		var ctx: Dictionary = await _busy(w, height, 3, true)
		var h = ctx.scene.hud_layer
		var rects := _hud_rects(h)
		check(rects.has("news") and rects.news.size != Vector2.ZERO, "%d wide: the news is up" % w)
		if w < RaidHud.WIDE_W:
			# a narrow window: the log is in the verbs' place, so the verbs go while it is up
			rects.erase("radio_verbs")
		rects["radio_head"] = Rect2(rects.radio.position, Vector2(rects.radio.size.x, minf(rects.radio.size.y, 44.0)))
		rects.erase("radio")
		eq(Kit.overlaps(rects), [], "%d wide, with the news" % w)
		var win := Rect2(0, 0, w, height)
		for k in rects:
			if rects[k].size == Vector2.ZERO:
				continue
			check(win.encloses(rects[k].grow(-0.5)), "%d wide: the %s is inside the window: %s" % [w, k, str(rects[k])])
		await _leave(ctx.main)


func test_a_squad_of_six_in_a_bus_fits_too() -> void:
	for w in WIDTHS:
		var main := _game(w, 600 if w == 700 else 800, 6)
		var scene := _open(main, 6)
		scene.hud_layer.refresh()
		await TutorialKit.settle()
		scene.hud_layer.refresh()
		await TutorialKit.settle()
		var rects := _hud_rects(scene.hud_layer)
		eq(Kit.overlaps(rects), [], "%d wide, six cards" % w)
		eq(scene.hud_layer.cards.size(), 6, "six cards")
		var win := Rect2(0, 0, w, 600 if w == 700 else 800)
		check(win.encloses(rects.cards.grow(-0.5)), "%d wide: the cards are inside: %s" % [w, str(rects.cards)])
		await _leave(main)


func _small_text(node: Node, out: Array = []) -> Array:
	if node is Label or node is Button:
		var size: int = node.get_theme_font_size("font_size")
		if size < Fonts.MIN_PX:
			out.append("%s '%s' is %d px" % [node.get_class(), str(node.get("text")), size])
	for c in node.get_children():
		_small_text(c, out)
	return out


func test_no_text_is_under_twelve_pixels_at_any_width_in_play_on_the_road_or_on_the_report() -> void:
	for w in WIDTHS:
		var height := 560 if w == 700 else 800
		var ctx: Dictionary = await _busy(w, height, 3, true)
		var scene = ctx.scene
		eq(_small_text(scene.hud_layer), [], "%d wide, playing" % w)
		scene.hud_layer.show_end({"loot": {"food": 10, "meds": 4}, "hurt": {String(scene.run.squad[0].id): "bite"}, "lost": [String(scene.run.squad[1].id)], "clear": true, "ammo_used": 3.4, "beats": []}, ["Night 2: Hold the wall until dawn", "Dez is back"])
		await TutorialKit.settle()
		eq(_small_text(scene.hud_layer), [], "%d wide, the report" % w)
		var card: Rect2 = Kit.rect(scene.hud_layer.end_panel)
		check(Rect2(0, 0, w, height).encloses(card.grow(-0.5)), "%d wide: the card is inside the window: %s" % [w, str(card)])
		check(card.size.y > 200.0, "and it has a body")
		await _leave(ctx.main)
	check(RaidOverlay.NAME_PX >= Fonts.MIN_PX, "the names drawn over the world are %d px" % RaidOverlay.NAME_PX)


func test_the_words_read_on_the_boards_and_on_the_paper() -> void:
	var ctx: Dictionary = await _busy(1280, 800, 3, true)
	var scene = ctx.scene
	scene.hud_layer.show_end({"loot": {"food": 10}, "hurt": {}, "lost": [], "clear": false, "ammo_used": 0.0, "beats": []})
	await TutorialKit.settle()
	var text_check = HudText.new()
	var worst := 99.0
	var worst_what := ""
	var labels: Array = []
	_labels_under(scene.hud_layer, labels)
	for l in labels:
		if not l.is_visible_in_tree() or String(l.text) == "":
			continue
		var color: Color = l.get_theme_color("font_color")
		var ratio: float = text_check._worst_contrast(l, color, Color.WHITE)
		if ratio < worst:
			worst = ratio
			worst_what = "'%s'" % l.text
	check(worst >= HudText.AA, "the faintest word, %s, reads at %.2f:1" % [worst_what, worst])
	await _leave(ctx.main)


func _labels_under(node: Node, out: Array) -> void:
	if node is Label:
		out.append(node)
	for c in node.get_children():
		_labels_under(c, out)


func test_resizing_the_window_lays_the_hud_out_again() -> void:
	var ctx: Dictionary = await _busy(1280, 800)
	var h = ctx.scene.hud_layer
	var wide := _hud_rects(h)
	check(wide.cards.position.y < 30.0, "wide: the cards are in the top row, between the place and the bags: %s" % str(wide.cards))
	TutorialKit.resize(700, 600)
	await TutorialKit.settle()
	h.refresh()
	await TutorialKit.settle()
	h.refresh()
	var narrow := _hud_rects(h)
	check(narrow.cards.position.y > narrow.place.end.y, "narrow: the cards drop under the place and the bags: %s under %s" % [str(narrow.cards), str(narrow.place)])
	eq(Kit.overlaps(narrow), [], "and nothing overlaps")
	TutorialKit.resize(1280, 800)
	await TutorialKit.settle()
	h.refresh()
	await TutorialKit.settle()
	h.refresh()
	check(_hud_rects(h).cards.position.y < 30.0, "wide again: back to one row")
	await _leave(ctx.main)


func test_the_cards_plan_is_one_row_when_it_fits_and_more_when_it_does_not() -> void:
	var one: Dictionary = RaidHud.plan_cards(3, 700.0)
	check(one.fits and one.rows == 1 and one.w <= RaidHud.CARD_MAX_W and one.w >= RaidHud.CARD_MIN_W, "three in 700: %s" % str(one))
	var squeezed: Dictionary = RaidHud.plan_cards(3, 400.0)
	check(not squeezed.fits and squeezed.rows >= 2, "three in 400 take two rows: %s" % str(squeezed))
	var six: Dictionary = RaidHud.plan_cards(6, 640.0)
	check(not six.fits and six.rows == 2 and six.per_row == 3, "six in 640: two rows of three: %s" % str(six))
	for n in range(1, 9):
		for room in [300.0, 520.0, 680.0, 940.0, 1400.0]:
			var p: Dictionary = RaidHud.plan_cards(n, room)
			check(int(p.per_row) * int(p.rows) >= n, "%d cards in %d px: room for all: %s" % [n, int(room), str(p)])
			check(float(p.per_row) * float(p.w) + float(p.per_row - 1) * (RaidHud.GAP - 4.0) <= room + 0.5 or float(p.w) <= RaidHud.CARD_MIN_W, "%d cards in %d px: the row fits: %s" % [n, int(room), str(p)])
