extends "res://tests/case.gd"
## The scene of a played trip (round 14, R14.3: scripts/raid/raid_scene.gd, raid_hud.gd, raid_overlay.gd and main.gd's
## `open_raid`): it builds from a site and a squad, hides and holds the colony and gives it back exactly, the mouse and
## the keys give the orders (select, box, move, search, help, retreat, pause, zoom, follow), the HUD follows the run
## (cards, tally, log, banners), the end card gives the result once, and nothing overlaps or is under 12 px at any width.
## The rules of a run are tests/test_raid_run.gd's; the sites are tests/test_site_gen.gd's.

const GD := preload("res://scripts/game_data.gd")
const Kit := preload("res://tests/hud_kit.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const HudText := preload("res://tests/test_hud_text.gd")
const RaidScene := preload("res://scripts/raid/raid_scene.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")
const RaidHud := preload("res://scripts/raid/raid_hud.gd")
const RaidOverlay := preload("res://scripts/raid/raid_overlay.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

const W := 30
const H := 16
const WIDTHS := [700, 980, 1280, 1920]


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


## The real game (a small start: Ruth, Dez and Marcus) in a window of this size, with its own frames off.
func _game(width: int = 1280, height: int = 800, crew: int = 3) -> Node:
	return TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew}, width, height)


## A raid opened over `main` with the first `n` of the crew; its own frames are off (the tests tick it by hand).
func _open(main: Node, n: int = 3, dead: Array = [], vehicle: String = "", survivor: bool = false) -> Node:
	var party: Array = []
	for i in n:
		party.append(main.sim.people[i])
	var scene := RaidScene.new()
	main.add_child(scene)
	scene.set_process(false)
	scene.setup(main, main.hud, main.data, _site(dead), party, 300.0, vehicle, 1.0, survivor)
	return scene


func _play(scene: Node, seconds: float) -> void:
	for i in int(seconds * 30.0):
		scene.tick(1.0 / 30.0)


func _leave(main: Node) -> void:
	await TutorialKit.leave(main)


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


## Where a person's body is on the screen (their middle).
func _at(scene: Node, p) -> Vector2:
	return scene.to_screen(Vector2(p.x, p.y - 0.3))


func _ids(list: Array) -> Array:
	var out: Array = []
	for p in list:
		out.append(String(p.id))
	return out


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
	check(scene.get_parent() == main, "a child of the game")
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
	scene.tick(1.0 / 30.0)
	check(scene.pawn_nodes[zs[0]].get_parent() == scene.corpses, "one that falls lies on the ground, under the living")
	var gone = zs[0]
	scene.run.sim.zombies.erase(gone)
	scene.tick(1.0 / 30.0)
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


# -------------------------------------------------------- the colony waits --

func test_the_colony_is_hidden_and_held_while_the_raid_runs_and_restored_exactly() -> void:
	var main := _game()
	main.cam_center = Vector2(37.5, 22.0)
	main.zoom_px = 44.0
	main.speed = 2
	main.follow = main.sim.people[1]
	main._select({"kind": "person", "ref": main.sim.people[2]})
	main.follow = main.sim.people[1]
	var chosen = main.selection
	var before: Dictionary = {"world": main.world.visible, "overlay": main.overlay.visible, "glow": main.glow.visible, "snow": main.snow.visible, "hud": main.hud.visible}
	var t0: float = main.sim.t
	var scene := _open(main)
	check(not main.world.visible and not main.hud.visible and not main.overlay.visible and not main.glow.visible and not main.snow.visible, "the colony's world, pawns and HUD are hidden")
	eq(main.speed, 0, "its rules are held")
	check(main.menu_open and main.raid == scene and main.raid_open(), "the game counts the raid as a menu")
	for i in 30:
		main._process(1.0 / 30.0)
	near(main.sim.t, t0, 0.0001, "no time passes in the colony while the raid is up")
	_play(scene, 3.0)
	scene.select_all()
	scene.retreat()
	_play(scene, 30.0)
	check(scene.ended, "the run ends")
	var seen: Array = []
	scene.finished.connect(func(r): seen.append(r))
	scene.go_home()
	eq(seen.size(), 1, "finished is sent once")
	check(main.world.visible == before.world and main.overlay.visible == before.overlay and main.glow.visible == before.glow and main.snow.visible == before.snow and main.hud.visible == before.hud, "everything shown again as it was")
	eq(main.speed, 2, "the speed is given back")
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
	main._key(KEY_SPACE)
	eq(main.speed, 0, "and Space does not start the yard's clock")
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
	for code in [KEY_G, KEY_TAB, KEY_ESCAPE]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.pressed = true
		Engine.get_main_loop().root.push_input(ev)
	check(main.hud.town_board_open(), "Esc and G were the raid's, not the board's")
	check(scene.asking, "Esc asked 'Retreat?'")
	await _leave(main)


# ---------------------------------------------------------------- selecting --

func test_clicking_a_person_selects_them_and_clicking_the_ground_lets_go() -> void:
	var main := _game()
	var scene := _open(main)
	var a = scene.run.squad[0]
	var b = scene.run.squad[1]
	a.x = 5.5
	a.y = 8.5
	b.x = 8.5
	b.y = 8.5
	_play(scene, 0.1)
	_click(scene, _at(scene, a))
	eq(_ids(scene.selection), [String(a.id)], "a click selects them")
	_click(scene, _at(scene, b), MOUSE_BUTTON_LEFT, true)
	eq(_ids(scene.selection), [String(a.id), String(b.id)], "shift adds")
	_click(scene, _at(scene, b), MOUSE_BUTTON_LEFT, true)
	eq(_ids(scene.selection), [String(a.id)], "and takes away")
	_click(scene, scene.to_screen(Vector2(12.5, 14.5)))
	check(scene.selection.is_empty(), "a click on nothing lets go")
	await _leave(main)


func test_dragging_a_box_selects_whoever_is_in_it() -> void:
	var main := _game()
	var scene := _open(main)
	var squad: Array = scene.run.squad
	squad[0].x = 5.5
	squad[0].y = 8.5
	squad[1].x = 7.5
	squad[1].y = 8.5
	squad[2].x = 12.5
	squad[2].y = 13.5
	_play(scene, 0.1)
	var from: Vector2 = scene.to_screen(Vector2(4.0, 7.0))
	var to: Vector2 = scene.to_screen(Vector2(9.0, 10.0))
	_button(scene, from, MOUSE_BUTTON_LEFT, true)
	_motion(scene, from.lerp(to, 0.5))
	_motion(scene, to)
	check(scene.drag != null and scene.drag.moved, "past a few pixels it is a box")
	check(scene.drag.box.size.x > 10.0, "with a size")
	_button(scene, to, MOUSE_BUTTON_LEFT, false)
	eq(_ids(scene.selection), [String(squad[0].id), String(squad[1].id)], "the two inside are selected")
	check(scene.drag == null, "the drag is over")
	await _leave(main)


func test_the_keys_pick_cycle_and_select_all() -> void:
	var main := _game()
	var scene := _open(main)
	var squad: Array = scene.run.squad
	scene.key_pressed(KEY_2)
	eq(_ids(scene.selection), [String(squad[1].id)], "2 picks the second")
	scene.key_pressed(KEY_TAB)
	eq(_ids(scene.selection), [String(squad[2].id)], "Tab goes to the next")
	scene.key_pressed(KEY_TAB)
	eq(_ids(scene.selection), [String(squad[0].id)], "and round")
	scene.key_pressed(KEY_A)
	eq(scene.selection.size(), 3, "A selects everyone")
	scene.key_pressed(KEY_1, true)
	eq(scene.selection.size(), 2, "shift and a number takes one away")
	squad[1].dead = true
	scene.key_pressed(KEY_2)
	scene.tick(1.0 / 30.0)
	check(not scene.selection.has(squad[1]), "someone who is lost is not selected any more")
	scene.key_pressed(KEY_TAB)
	check(not scene.selection.has(squad[1]), "and Tab skips them")
	await _leave(main)


func test_a_downed_person_can_be_picked_where_they_lie() -> void:
	var main := _game()
	var scene := _open(main)
	var p = scene.run.squad[0]
	p.x = 6.5
	p.y = 8.5
	p.downed = true
	scene.tick(1.0 / 30.0)
	_click(scene, scene.to_screen(Vector2(6.5, 8.4)))
	eq(_ids(scene.selection), [String(p.id)], "a click on the body selects it (their card shows how they are)")
	await _leave(main)


# ------------------------------------------------------------------- orders --

func test_right_click_on_open_ground_walks_the_selection_there_spread_a_little() -> void:
	var main := _game()
	var scene := _open(main)
	scene.select_all()
	var goal := Vector2(8.5, 8.5)
	_click(scene, scene.to_screen(goal), MOUSE_BUTTON_RIGHT)
	var spots: Array = []
	for p in scene.run.squad:
		check(p.order != null, "%s has an order" % p.first)
		var at := Vector2(p.order.x, p.order.y)
		check(at.distance_to(goal) <= RaidScene.SPREAD + 0.01, "within the spread of the click: %s" % str(at))
		spots.append(at)
	check(spots[0].distance_to(spots[1]) > 0.3 and spots[1].distance_to(spots[2]) > 0.3, "and not on top of each other")
	check(scene.marks.size() == 1 and scene.marks[0].kind == "move", "the order leaves a mark")
	_play(scene, 6.0)
	for p in scene.run.squad:
		check(Vector2(p.x, p.y).distance_to(goal) < 1.2, "%s got there" % p.first)
	await _leave(main)


func test_right_click_without_a_selection_or_on_a_wall_says_why() -> void:
	var main := _game()
	var scene := _open(main)
	_click(scene, scene.to_screen(Vector2(8.5, 8.5)), MOUSE_BUTTON_RIGHT)
	check(scene.hud_layer.toast_panel.visible and scene.hud_layer.toast_label.text.begins_with("Click someone first"), "no one selected: %s" % scene.hud_layer.toast_label.text)
	scene.select_one(scene.run.squad[0])
	_click(scene, scene.to_screen(Vector2(14.5, 5.5)), MOUSE_BUTTON_RIGHT)
	eq(scene.hud_layer.toast_label.text, "Nobody can stand there", "a wall")
	check(scene.run.squad[0].order == null, "no order was given")
	await _leave(main)


func test_right_click_on_a_container_sends_the_nearest_to_search_it() -> void:
	var main := _game()
	var scene := _open(main)
	var squad: Array = scene.run.squad
	squad[0].x = 12.5
	squad[0].y = 4.5
	scene.select_all()
	_click(scene, scene.to_screen(Vector2(10.5, 2.5)), MOUSE_BUTTON_RIGHT)
	var searching: Dictionary = scene.run._searching
	eq(searching.size(), 1, "one person goes")
	eq(String(searching.get(String(squad[0].id), "")), "c3", "the nearest, to the crate")
	check(scene.marks.size() == 1 and scene.marks[0].kind == "search", "marked")
	_play(scene, 1.0)
	check(scene.status_of(squad[0]) in ["Going to search", "Searching"], "their card says so: %s" % scene.status_of(squad[0]))
	check(scene.status_of(squad[1]) == "Ready", "the others stand ready: %s" % scene.status_of(squad[1]))
	_play(scene, 8.0)
	check(scene.run.container("c3").looted, "the crate is searched")
	eq(int(scene.run.carried.get("water", 0)), 12, "its water is in the bags")
	_click(scene, scene.to_screen(Vector2(10.5, 2.5)), MOUSE_BUTTON_RIGHT)
	eq(scene.hud_layer.toast_label.text, "Nothing left in that", "a searched one is not searched again")
	await _leave(main)


func test_a_search_shows_its_progress_while_it_goes_and_a_tick_when_it_is_done() -> void:
	var main := _game()
	var scene := _open(main, 1)
	scene.select_all()
	scene.order_search("c1")
	var c: Dictionary = scene.run.container("c1")
	_play(scene, 5.0)
	check(float(c.progress) > 0.0 and not bool(c.looted), "in progress: %.1f of %.1f" % [float(c.progress), float(c.search_s)])
	eq(scene.status_of(scene.run.squad[0]), "Searching", "the card says Searching")
	await TutorialKit.settle()
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	check(scene.overlay.drawn_containers >= 1, "the overlay marks the containers in view")
	_play(scene, 5.0)
	check(bool(c.looted), "done")
	eq(scene.status_of(scene.run.squad[0]), "Ready", "and they are free again")
	await _leave(main)


func test_right_click_on_a_downed_friend_sends_the_nearest_other_to_help() -> void:
	var main := _game()
	var scene := _open(main)
	var squad: Array = scene.run.squad
	squad[0].x = 8.5
	squad[0].y = 8.5
	squad[0].downed = true
	squad[0].hp = 0.0
	squad[1].x = 9.5
	squad[1].y = 8.5
	squad[2].x = 4.5
	squad[2].y = 8.5
	scene.select([squad[1], squad[2]])
	_click(scene, scene.to_screen(Vector2(8.5, 8.4)), MOUSE_BUTTON_RIGHT)
	eq(scene.run._helping.size(), 1, "one goes")
	check(scene.run._helping.has(String(squad[1].id)), "the nearer one")
	_play(scene, 1.0)
	_play(scene, RaidRun.HELP_S + 1.0)
	check(not squad[0].downed, "and gets them up")
	await _leave(main)


func test_helping_needs_someone_else_selected() -> void:
	var main := _game()
	var scene := _open(main)
	var squad: Array = scene.run.squad
	squad[0].downed = true
	scene.select([squad[0]])
	_click(scene, scene.to_screen(Vector2(squad[0].x, squad[0].y - 0.2)), MOUSE_BUTTON_RIGHT)
	check(scene.run._helping.is_empty(), "nobody can help themselves")
	scene.select([])
	scene.right_click(scene.to_screen(Vector2(squad[0].x, squad[0].y - 0.2)))
	check(scene.hud_layer.toast_label.text.begins_with("Select someone else"), "it says so: %s" % scene.hud_layer.toast_label.text)
	await _leave(main)


# --------------------------------------------------------- retreat and pause --

func test_r_and_the_button_send_everyone_back() -> void:
	var main := _game()
	var scene := _open(main)
	scene.key_pressed(KEY_R)
	eq(scene.run.phase, "retreat", "R retreats at once")
	check(scene.hud_layer.retreat_button.disabled and scene.hud_layer.retreat_button.text == "Retreating", "the button says so")
	await _leave(main)
	var main2 := _game()
	var scene2 := _open(main2)
	scene2.hud_layer.retreat_button.pressed.emit()
	eq(scene2.run.phase, "retreat", "the button retreats too")
	await _leave(main2)


func test_esc_asks_first_and_esc_or_enter_says_yes_any_other_key_says_no() -> void:
	var main := _game()
	var scene := _open(main)
	scene.key_pressed(KEY_ESCAPE)
	check(scene.asking and scene.hud_layer.ask_panel.visible, "Esc asks")
	eq(scene.run.phase, "play", "and nothing has happened yet")
	var before: float = scene.run.elapsed
	_play(scene, 1.0)
	near(scene.run.elapsed, before, 0.0001, "the raid waits while it is asked")
	scene.key_pressed(KEY_ESCAPE)
	eq(scene.run.phase, "retreat", "Esc again says yes")
	check(not scene.asking and not scene.hud_layer.ask_panel.visible, "the question is gone")
	await _leave(main)
	var main2 := _game()
	var scene2 := _open(main2)
	scene2.key_pressed(KEY_ESCAPE)
	scene2.key_pressed(KEY_ENTER)
	eq(scene2.run.phase, "retreat", "Enter says yes")
	await _leave(main2)
	var main3 := _game()
	var scene3 := _open(main3)
	scene3.key_pressed(KEY_ESCAPE)
	scene3.key_pressed(KEY_X)
	check(not scene3.asking and scene3.run.phase == "play", "any other key says no")
	scene3.key_pressed(KEY_ESCAPE)
	scene3.hud_layer.ask_no.pressed.emit()
	check(not scene3.asking and scene3.run.phase == "play", "so does the button")
	scene3.key_pressed(KEY_ESCAPE)
	scene3.hud_layer.ask_yes.pressed.emit()
	eq(scene3.run.phase, "retreat", "and the other button says yes")
	await _leave(main3)


func test_space_pauses_and_orders_can_be_given_while_it_is() -> void:
	var main := _game()
	var scene := _open(main)
	scene.key_pressed(KEY_SPACE)
	check(scene.paused, "paused")
	check(scene.hud_layer.paused_chip.visible, "the HUD says PAUSED")
	var t: float = scene.run.elapsed
	scene.select_all()
	scene.order_move(Vector2(9.5, 8.5))
	_play(scene, 2.0)
	near(scene.run.elapsed, t, 0.0001, "the run does not move while paused")
	check(scene.run.squad[0].order != null, "but the order was taken")
	scene.key_pressed(KEY_SPACE)
	_play(scene, 2.0)
	check(scene.run.elapsed > t + 1.5, "and runs when it is not")
	check(not scene.paused, "unpaused")
	await _leave(main)


# ---------------------------------------------------------------- the camera --

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


func test_the_middle_mouse_pans_and_so_do_the_arrow_keys_and_a_pan_lets_go_of_follow() -> void:
	var main := _game()
	var scene := _open(main)
	scene.zoom_px = 50.0
	scene.cam_center = Vector2(15, 8)
	scene._clamp_camera()
	var c0: Vector2 = scene.cam_center
	_button(scene, Vector2(600, 400), MOUSE_BUTTON_MIDDLE, true)
	_motion(scene, Vector2(500, 400))
	_button(scene, Vector2(500, 400), MOUSE_BUTTON_MIDDLE, false)
	check(scene.cam_center.x > c0.x + 1.0, "dragging the world left moves the view right: %s to %s" % [str(c0), str(scene.cam_center)])
	scene.follow = true
	var c1: Vector2 = scene.cam_center
	scene.pan(Vector2(-1.0, 0.0))
	check(scene.cam_center.x < c1.x and not scene.follow, "a pan moves the view and lets go of follow")
	await _leave(main)


func test_f_follows_the_selection_and_the_camera_catches_up() -> void:
	var main := _game()
	var scene := _open(main)
	scene.zoom_px = 50.0
	scene.cam_center = Vector2(4, 8)
	scene.select_one(scene.run.squad[0])
	scene.run.squad[0].x = 16.5
	scene.run.squad[0].y = 8.5
	scene.key_pressed(KEY_F)
	check(scene.follow, "F follows")
	_play(scene, 2.0)
	check(scene.cam_center.distance_to(Vector2(16.5, 8.5)) < 1.5, "the camera is on them: %s" % str(scene.cam_center))
	scene.key_pressed(KEY_F)
	check(not scene.follow, "F again lets go")
	scene.key_pressed(KEY_F)
	scene.key_pressed(KEY_H)
	check(scene.follow, "other keys leave it alone")
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
		eq(c.status.text, "Ready", "standing ready")
		near(c.hp.anchor_right, 1.0, 0.001, "a full bar")
		check(c.pic.texture != null, "a face")
	squad[1].hp = 30.0
	squad[1].mag = 2
	h.refresh()
	near(h.cards[1].hp.anchor_right, 0.3, 0.001, "the bar follows their health")
	check(String(h.cards[1].weapon.text).ends_with("2/%d" % int(squad[1].gun.mag)), "and the magazine: %s" % h.cards[1].weapon.text)
	squad[2].downed = true
	h.refresh()
	eq(h.cards[2].status.text, "Down", "a person who is down says so")
	squad[0].dead = true
	h.refresh()
	eq(h.cards[0].status.text, "Lost", "and one who is gone")
	scene.select([squad[1]])
	check(h.cards[1].selected and not h.cards[2].selected, "the selected card is lit")
	await _leave(main)


func test_clicking_a_card_selects_that_person() -> void:
	var main := _game()
	var scene := _open(main)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	scene.hud_layer.cards[1].panel.gui_input.emit(ev)
	eq(_ids(scene.selection), [String(scene.run.squad[1].id)], "the second card")
	ev.shift_pressed = true
	scene.hud_layer.cards[0].panel.gui_input.emit(ev)
	eq(scene.selection.size(), 2, "shift adds")
	await _leave(main)


func test_the_tally_shows_what_is_in_the_bags_by_stock_and_how_full_they_are() -> void:
	var main := _game()
	var scene := _open(main, 2)
	var h = scene.hud_layer
	h.refresh()
	eq(h.bags_label.text, "0 of %d" % (2 * RaidRun.CARRY), "empty bags")
	check(h.empty_label.visible, "'Nothing yet'")
	for stock in h.chips:
		check(not h.chips[stock].box.visible, "no %s yet" % stock)
	scene.select_all()
	scene.order_search("c1")
	_play(scene, 14.0)
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


func test_the_legend_shows_at_first_fades_and_h_brings_it_back() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	check(h.legend_panel.visible and h.legend_panel.modulate.a > 0.99, "at first")
	_play(scene, RaidHud.LEGEND_HOLD + 1.0)
	h.refresh()
	check(not h.legend_panel.visible, "it fades away")
	scene.key_pressed(KEY_H)
	check(h.legend_panel.visible, "H brings it back")
	var words: Array = Kit.texts(h.legend_panel)
	for want in ["Right-click", "Space", "R", "Tab", "F", "Scroll", "select", "pause", "retreat", "follow", "zoom"]:
		check(words.has(want) or " ".join(words).contains(want), "the legend has '%s': %s" % [want, str(words)])
	await _leave(main)


func test_the_place_panel_names_the_place_and_says_what_to_do() -> void:
	var main := _game()
	var scene := _open(main)
	var h = scene.hud_layer
	eq(h.place_label.text, "The test house", "the place's name")
	check(h.line_label.text.contains("search"), "at first it says to search: %s" % h.line_label.text)
	scene.run.squad[1].downed = true
	check(scene.hint_line().contains("%s is down" % scene.run.squad[1].first), "a friend down: %s" % scene.hint_line())
	scene.run.squad[1].downed = false
	for c in scene.run.containers:
		c.looted = true
	check(scene.hint_line().begins_with("Everything is searched"), "all searched: %s" % scene.hint_line())
	scene.run.retreat()
	eq(scene.hint_line(), "Heading back to the road.", "retreating")
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
	# shown. This test failed now and then in a whole run (never alone): the wake-up of a dead man who stands about and the
	# banner's own clock depend on what the earlier tests drew at random, so the state is not left to chance.
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
	scene.tick(1.0 / 30.0)
	eq(h.banner_title.text, "THEY HEARD THAT", "a shot wakes the dead")
	check(h.banner_sub.text != "" and h.banner.visible, "the banner is up")
	check(scene.run.events.is_empty(), "the events were taken")
	scene.clock += 10.0
	scene.run.squad[2].downed = true
	scene.tick(1.0 / 30.0)
	eq(h.banner_title.text, "%s IS DOWN" % String(scene.run.squad[2].first).to_upper(), "a friend down")
	check(String(h.banner_sub.text).contains("Right-click"), "and what to do: %s" % h.banner_sub.text)
	scene.clock += 0.5
	scene.run.squad[1].downed = true
	scene.tick(1.0 / 30.0)
	check(not h.banner_title.text.begins_with(String(scene.run.squad[1].first).to_upper()), "banners are not a flood: one at a time")
	await _leave(main)


func test_hunters_are_marked_over_their_heads() -> void:
	var main := _game()
	var scene := _open(main, 3, [{"pos": Vector2(9.5, 8.5), "kind": "walker", "state": "still"}])
	scene.run._noise(Vector2(5.5, 8.5))
	scene.tick(1.0 / 30.0)
	await TutorialKit.settle()
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	check(scene.overlay.drawn_hunters >= 1, "a red mark over the one that hunts")
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
	scene.tick(1.0 / 30.0)
	check(scene.run.events.is_empty(), "all of them taken, known or not")
	await _leave(main)


# ------------------------------------------------------------------ the end --

func test_the_end_card_shows_the_result_and_go_home_sends_it_once() -> void:
	var main := _game()
	var scene := _open(main, 3)
	var h = scene.hud_layer
	scene.select_all()
	scene.order_search("c1")
	_play(scene, 14.0)
	scene.run.squad[1].hp = 40.0
	scene.run._bitten[String(scene.run.squad[1].id)] = true
	scene.retreat()
	_play(scene, 40.0)
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
	check(not scene.hud_layer.retreat_panel.visible and not scene.hud_layer.legend_panel.visible, "the rest of the HUD makes room")
	var got: Array = []
	scene.finished.connect(func(r): got.append(r))
	var expect: Dictionary = scene.run.result()
	h.end_button.pressed.emit()
	scene.go_home()
	scene.key_pressed(KEY_ENTER)
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
	scene.retreat()
	_play(scene, 30.0)
	check(scene.ended, "over")
	var got: Array = []
	scene.finished.connect(func(r): got.append(r))
	for code in [KEY_SPACE, KEY_R, KEY_ESCAPE, KEY_TAB, KEY_A]:
		scene.key_pressed(code)
	eq(got.size(), 0, "no other key sends them home")
	scene.key_pressed(KEY_ENTER)
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
	scene.select_all()
	scene.order_search("survivor")
	_play(scene, 25.0)
	scene.retreat()
	_play(scene, 30.0)
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
	scene.select_all()
	scene.order_search("c1")
	_play(scene, 10.0)
	scene.run._noise(Vector2(5.5, 8.5))
	_play(scene, 10.0)
	scene.retreat()
	_play(scene, 40.0)
	scene.go_home()
	await TutorialKit.frames(main, 4)
	eq(Performance.get_monitor(Performance.OBJECT_NODE_COUNT), before, "the same number of nodes as before the raid")
	check(main.get_children().filter(func(c): return c is RaidScene).is_empty(), "no raid scene is left")
	await _leave(main)


func test_a_scene_freed_without_going_home_still_gives_the_colony_back() -> void:
	var main := _game()
	main.speed = 1
	var scene := _open(main)
	check(main.speed == 0 and not main.world.visible, "held")
	scene.free()
	eq(main.speed, 1, "the speed is back")
	check(main.world.visible and main.hud.visible and main.raid == null, "and the yard shows")
	await _leave(main)


func test_two_raids_cannot_be_open_at_once() -> void:
	var main := _game()
	main.raid_stub = true
	var done: Array = []
	var scene = main.open_raid([main.sim.people[0]], main.sim.town.place("houses"), "", 1.0, func(r): done.append(r))
	check(scene != null and main.raid == scene, "the first opens")
	check(main.open_raid([main.sim.people[1]], main.sim.town.place("houses"), "", 1.0, Callable()) == null, "a second does not")
	scene.free()
	check(main.open_raid([], main.sim.town.place("houses"), "", 1.0, Callable()) == null, "and nobody cannot go")
	await _leave(main)


# --------------------------------------------------------------- open_raid --

func test_open_raid_builds_the_site_opens_the_scene_and_calls_back_with_the_result() -> void:
	var main := _game()
	main.raid_stub = true
	var place: Dictionary = main.sim.town.place("houses")
	var done: Array = []
	var party: Array = [main.sim.people[0], main.sim.people[1]]
	var scene = main.open_raid(party, place, "", 1.0, func(r): done.append(r))
	check(scene != null and main.raid_open(), "the raid is open")
	eq(scene.run.squad.size(), 2, "with the two who went")
	eq(String(scene.site.name), String(place.name), "at the place")
	scene.retreat()
	_play(scene, 30.0)
	check(scene.ended, "played to its end")
	scene.go_home()
	eq(done.size(), 1, "on_done is called")
	for k in ["loot", "hurt", "lost", "ammo_used", "beats"]:
		check(done[0].has(k), "with %s" % k)
	check(not main.raid_open(), "the raid is closed")
	await _leave(main)


func test_the_same_place_and_run_make_the_same_site_and_a_seed_can_be_given() -> void:
	var main := _game()
	main.raid_stub = true
	var place: Dictionary = main.sim.town.place("houses")
	var a = main.open_raid([main.sim.people[0]], place, "", 1.0, Callable())
	var seed_a: int = int(a.site.seed)
	a.free()
	var b = main.open_raid([main.sim.people[0]], place, "", 1.0, Callable())
	eq(int(b.site.seed), seed_a, "the same place, run and day: the same seed")
	b.free()
	main._stage_raid("houses,77")
	eq(int(main.raid.site.seed), 77, "--raid=houses,77 fixes it")
	main.raid.free()
	main._stage_raid("pharmacy")
	eq(String(main.raid.site.kind), "pharmacy", "a place by its id")
	main.raid.free()
	await _leave(main)


func test_stage_raid_takes_a_kind_and_the_first_three_people() -> void:
	var main := _game()
	main.raid_stub = true
	main._stage_raid("bakery")
	check(main.raid_open(), "open")
	eq(String(main.raid.site.kind), "bakery", "the first place of that kind")
	eq(main.raid.run.squad.size(), 3, "the three of the small start")
	main.raid.stage("all+search:0+wait:1+pause")
	check(main.raid.paused, "the staging's steps are run")
	main.raid.free()
	await _leave(main)


func test_a_place_with_someone_hiding_in_it_has_a_survivor_to_find() -> void:
	var main := _game()
	main.raid_stub = true
	var place: Dictionary = main.sim.town.place("church")
	check(bool(place.get("survivor", false)), "the church has someone in it")
	var scene = main.open_raid([main.sim.people[0]], place, "", 1.0, Callable())
	check(scene.has_survivor and not scene.run.container("survivor").is_empty(), "so the run has a spot to find them")
	scene.free()
	main.sim.town.state["church"]["rescued"] = true
	var again = main.open_raid([main.sim.people[0]], place, "", 1.0, Callable())
	check(not again.has_survivor, "not once they are home")
	again.free()
	var plain = main.open_raid([main.sim.people[0]], main.sim.town.place("houses"), "", 1.0, Callable())
	check(not plain.has_survivor, "and a place with nobody has nobody")
	plain.free()
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


func test_real_clicks_reach_the_world_through_the_hud_and_the_buttons_get_theirs() -> void:
	var main := _game()
	var scene := _open(main)
	await TutorialKit.settle()
	var p = scene.run.squad[0]
	p.x = 8.5
	p.y = 10.5
	_play(scene, 0.1)
	var at := _at(scene, p)
	_push(at, MOUSE_BUTTON_LEFT, true)
	_push(at, MOUSE_BUTTON_LEFT, false)
	eq(_ids(scene.selection), [String(p.id)], "a click in the world selects")
	_push(scene.to_screen(Vector2(10.5, 10.5)), MOUSE_BUTTON_RIGHT, true)
	check(p.order != null and Vector2(p.order.x, p.order.y).distance_to(Vector2(10.5, 10.5)) < 0.1, "a right-click orders")
	var card: Rect2 = scene.hud_layer.cards[1].panel.get_global_rect()
	_push(card.get_center(), MOUSE_BUTTON_LEFT, true)
	_push(card.get_center(), MOUSE_BUTTON_LEFT, false)
	eq(_ids(scene.selection), [String(scene.run.squad[1].id)], "a click on a card selects that person, and does not clear it as a click on the ground would")
	var button: Rect2 = scene.hud_layer.retreat_button.get_global_rect()
	_push(button.get_center(), MOUSE_BUTTON_LEFT, true)
	_push(button.get_center(), MOUSE_BUTTON_LEFT, false)
	eq(scene.run.phase, "retreat", "the Retreat button is pressed by a click")
	await _leave(main)


func test_the_pointer_at_the_edge_pans_only_when_it_is_really_there() -> void:
	var main := _game()
	var scene := _open(main)
	scene.zoom_px = 50.0
	scene.cam_center = Vector2(15, 8)
	scene._clamp_camera()
	eq(scene.edge_pan(), Vector2.ZERO, "no pointer seen: no edge scrolling (a screenshot run, a headless one)")
	var vp: Vector2 = scene._vp()
	_motion(scene, Vector2(vp.x - 1.0, vp.y / 2.0))
	if scene.get_window().has_focus():
		eq(scene.edge_pan(), Vector2(1, 0), "the right edge pans right")
	scene._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	eq(scene.edge_pan(), Vector2.ZERO, "and leaving the window stops it")
	_motion(scene, vp / 2.0)
	eq(scene.edge_pan(), Vector2.ZERO, "the middle of the window never does")
	await _leave(main)


func test_the_question_warns_about_someone_who_would_be_left_behind() -> void:
	var main := _game()
	var scene := _open(main)
	scene.key_pressed(KEY_ESCAPE)
	check(not scene.hud_layer.ask_warn.visible, "nobody is down: no warning")
	scene.cancel_ask()
	scene.run.squad[1].downed = true
	scene.key_pressed(KEY_ESCAPE)
	check(scene.hud_layer.ask_warn.visible and scene.hud_layer.ask_warn.text == "%s is down and will be left behind." % scene.run.squad[1].first, "a friend down: %s" % scene.hud_layer.ask_warn.text)
	await _leave(main)


func test_stage_raid_can_go_in_a_vehicle() -> void:
	var main := _game()
	main.raid_stub = true
	main._stage_raid("houses,9,van")
	check(main.raid_open() and main.raid.vehicle_node != null, "the van is drawn")
	eq(main.raid.run.vehicle_kind, "van", "and the run knows it")
	main.raid.free()
	await _leave(main)


func test_a_generated_site_is_played_to_its_end_card_in_the_scene() -> void:
	# the SITES builder's generator, through open_raid as the game calls it (no stand-in): a scripted squad searches the
	# nearest thing and retreats; the card comes up and the result is a trip's
	for kind in ["houses", "pharmacy", "gas_station", "scrapyard"]:
		var main := _game()
		var place := {}
		for pl in main.sim.town.all_places():
			if String(pl.kind) == kind:
				place = pl
				break
		check(not place.is_empty(), "the town has a %s" % kind)
		var done: Array = []
		var scene = main.open_raid([main.sim.people[0], main.sim.people[1], main.sim.people[2]], place, "", 1.0, func(r): done.append(r))
		check(scene != null and scene.run.containers.size() > 0, "%s: a site with things to search" % kind)
		eq(String(scene.site.kind), kind, "%s: the place's kind" % kind)
		scene.stage("all+search:near+wait:12+end")
		check(scene.ended, "%s: it ends" % kind)
		check(scene.hud_layer.end_card != null and scene.hud_layer.end_card.visible, "%s: with its card" % kind)
		scene.key_pressed(KEY_ENTER)
		eq(done.size(), 1, "%s: and the result is given once" % kind)
		for k in ["loot", "hurt", "lost", "ammo_used", "beats"]:
			check(done[0].has(k), "%s: the result has %s" % [kind, k])
		await _leave(main)


# ---------------------------------------------------- the classic game as ever --

func _fingerprint(main: Node) -> String:
	return TutorialKit.fingerprint(main.sim)


func _drive(main: Node, frames: int) -> void:
	for i in frames:
		main._process(1.0 / 30.0)


func test_a_game_that_opened_a_raid_goes_on_as_one_that_did_not_settlement_and_classic() -> void:
	for crew in [3, 6]:
		var a := _game(1280, 800, crew)
		a.sim.waves.enabled = false
		_drive(a, 150)
		var fp_a := _fingerprint(a)
		await _leave(a)
		var b := _game(1280, 800, crew)
		b.sim.waves.enabled = false
		_drive(b, 50)
		var scene := _open(b)
		scene.select_all()
		scene.order_search("c1")
		_play(scene, 5.0)
		_drive(b, 40)
		scene.retreat()
		_play(scene, 40.0)
		scene.go_home()
		await TutorialKit.frames(b, 1, 1.0 / 30.0, 1)
		_drive(b, 99)
		var fp_b := _fingerprint(b)
		eq(fp_b, fp_a, "crew of %d: the colony's rules ran the same steps" % crew)
		await _leave(b)


func test_without_a_raid_the_game_is_not_in_a_menu() -> void:
	var main := _game()
	check(main.raid == null and not main.raid_open() and not main.menu_open, "no raid, no menu")
	main._key(KEY_V)
	check(main.fields, "the yard's keys work")
	await _leave(main)


# --------------------------------------------------------- layout and text --

func _hud_rects(h) -> Dictionary:
	return {
		"place": Kit.rect(h.place_panel), "loot": Kit.rect(h.loot_panel), "cards": Kit.rect(h.cards_grid),
		"retreat": Kit.rect(h.retreat_panel), "log": Kit.rect(h.log_panel), "legend": Kit.rect(h.legend_panel),
		"banner": Kit.rect(h.banner), "toast": Kit.rect(h.toast_panel),
	}


## Everything the HUD can show at once: cards, bags with stocks, a log, the legend, a banner and a toast.
func _busy(width: int, height: int, n: int = 3) -> Dictionary:
	var main := _game(width, height)
	var scene := _open(main, n)
	scene.select_one(scene.run.squad[0])
	scene.run.carried = {"food": 10, "water": 12, "scrap": 25, "ammo": 6, "meds": 4, "fuel": 3}
	for line in ["Dez searched the cabinet: 10 food, 4 meds.", "Ruth took 6 water from the crate; the bags are full, some is left.", "Marcus was bitten.", "Ruth got Dez back on their feet."]:
		scene.run.log.append(line)
	scene.hud_layer.show_banner("They heard that", "The dead nearby are coming")
	scene.hud_layer.toast("Click someone first, then right-click where they should go")
	scene.paused = true
	scene.hud_layer.refresh()
	await TutorialKit.settle()
	scene.hud_layer.refresh()
	await TutorialKit.settle()
	scene.hud_layer.refresh()
	return {"main": main, "scene": scene}


func test_nothing_in_the_raid_hud_overlaps_at_any_width() -> void:
	for w in WIDTHS:
		var ctx: Dictionary = await _busy(w, 560 if w == 700 else 800)
		var h = ctx.scene.hud_layer
		var rects := _hud_rects(h)
		for k in ["place", "loot", "cards", "retreat", "log", "legend", "banner", "toast"]:
			check(rects[k].size != Vector2.ZERO, "%d wide: the %s shows" % [w, k])
		eq(Kit.overlaps(rects), [], "%d wide" % w)
		var win := Rect2(0, 0, w, 560 if w == 700 else 800)
		for k in rects:
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


func test_no_text_is_under_twelve_pixels_at_any_width_in_play_or_on_the_end_card() -> void:
	for w in WIDTHS:
		var ctx: Dictionary = await _busy(w, 560 if w == 700 else 800)
		var scene = ctx.scene
		eq(_small_text(scene.hud_layer), [], "%d wide, playing" % w)
		scene.hud_layer.show_end({"loot": {"food": 10, "meds": 4}, "hurt": {String(scene.run.squad[0].id): "bite"}, "lost": [String(scene.run.squad[1].id)], "clear": true, "ammo_used": 3.4, "beats": []})
		await TutorialKit.settle()
		eq(_small_text(scene.hud_layer), [], "%d wide, the end card" % w)
		var card: Rect2 = Kit.rect(scene.hud_layer.end_panel)
		check(Rect2(0, 0, w, 560 if w == 700 else 800).encloses(card.grow(-0.5)), "%d wide: the card is inside the window: %s" % [w, str(card)])
		check(card.size.y > 200.0, "and it has a body")
		await _leave(ctx.main)
	check(RaidOverlay.NAME_PX >= Fonts.MIN_PX, "the names drawn over the world are %d px" % RaidOverlay.NAME_PX)


func test_the_words_read_on_the_boards_and_on_the_paper() -> void:
	var ctx: Dictionary = await _busy(1280, 800)
	var scene = ctx.scene
	scene.hud_layer.show_end({"loot": {"food": 10}, "hurt": {}, "lost": [], "clear": false, "ammo_used": 0.0, "beats": []})
	await TutorialKit.settle()
	var text_check = HudText.new()
	var worst := 99.0
	var worst_what := ""
	var labels: Array = []
	_labels_under(scene.hud_layer, labels)
	for l in labels:
		if not l.visible or String(l.text) == "":
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
