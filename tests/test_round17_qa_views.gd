extends "res://tests/case.gd"
## Round 17, the QA player's findings that are VIEWS (the numbers are the QA report's): in a place the call card is parked in the right
## column under the radio (I1) and the squad is kept off the foot HUD (M7, and M1 in the yard); the first screen says what the radio is
## (I4); the Town Board knows the player is the one who leads (I6); the ammo readout shows rounds that can be fired (I7); the crew cards
## spell the stance (M3), the speech bubbles keep out from under the HUD (M2), the camera glides (M4), the pointer leaving the window
## takes the crosshair (M5), the place's light follows the base's clock (M6), no crosshair on the downed (M9), a staged aim is honoured in a
## windowed shot run (M10), no Search that in the yard (M11), the fever tip points at the call card (M12). The rules are the other
## tests' (test_avatar, test_radio, test_raid_run); the Town Board's own are at the end of test_town_board.gd.

const AimMode := preload("res://scripts/aim_mode.gd")
const GD := preload("res://scripts/game_data.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const RaidScene := preload("res://scripts/raid/raid_scene.gd")
const RaidHud := preload("res://scripts/raid/raid_hud.gd")
const RaidOverlay := preload("res://scripts/raid/raid_overlay.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const Hints := preload("res://scripts/ui/hints.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")

const STEP := 1.0 / 30.0
const W := 30
const SIZES := [[1280, 800], [980, 700], [700, 560]]


# ------------------------------------------------------------------ helpers --

## A site `w` x `h` of our own: open ground, the entry on the left and the exit round it (as test_raid_scene.gd's, but as tall as
## the test asks, so that the camera has a bottom edge to be clamped at).
func _site(h: int = 16, dead: Array = []) -> Dictionary:
	var data: Dictionary = GD.load_all().duplicate(true)
	var terrain: Array = []
	var solid: Array = []
	for y in h:
		for x in W:
			terrain.append(1)
			solid.append(0)
	data["W"] = W
	data["H"] = h
	data["terrain"] = terrain
	data["solidZ"] = solid.duplicate()
	data["solidP"] = solid.duplicate()
	for k in ["objects", "walls", "marks", "lights", "trees", "segments", "people", "spawns"]:
		data[k] = []
	return {
		"name": "The test field", "kind": "houses", "danger": 2, "size": Vector2i(W, h), "data": data,
		"entry": Vector2(3.5, 8.5), "exit": Rect2(1.0, 6.5, 5.0, 4.0), "vehicle_spot": Vector2(3.5, 12.5),
		"containers": [{"id": "c1", "pos": Vector2(16.5, 6.5), "at": Vector2(16.5, 5.5), "kind": "cabinet", "loot": {"food": 10}, "search_s": 4.0, "room": "hall"}],
		"dead": dead, "rooms": [{"name": "hall", "rect": Rect2(15, 4, 9, 8)}], "seed": 1,
	}


## The real game (a small start: Ruth the avatar, Dez and Marcus) in a window of this size, its own frames off.
func _main(width: int = 1280, height: int = 800, crew: int = 3) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew, "avatar": true}, width, height)
	AimMode.set_mode("always")    # (round 22: these tests are of the controls as they were: the mouse aims by itself and the left button fires; the default is tests/test_r22c_*.gd's)
	main.raid_stub = true
	main.sim.waves.enabled = false
	main.sim.zombies.clear()
	return main


func _open(main: Node, h: int = 16, n: int = 3) -> Node:
	var party: Array = []
	for i in n:
		party.append(main.sim.people[i])
	var scene := RaidScene.new()
	main.add_child(scene)
	scene.set_process(false)
	scene.setup(main, main.hud, main.data, _site(h), party, 300.0, "", 1.0, false)
	return scene


func _play(scene: Node, seconds: float) -> void:
	for i in int(seconds * 30.0):
		scene.tick(STEP)


func _settle(scene: Node) -> void:
	scene.hud_layer.refresh()
	await TutorialKit.settle()
	scene.hud_layer.refresh()
	await TutorialKit.settle()
	scene.hud_layer.refresh()


## A call of the base's, of the kind that waits (three buttons).
func _attack(main: Node) -> int:
	return main.sim.radio.raise_call("attack", "The east wall is under attack", "Three of the dead are at the boards", [{"id": "hold", "label": "Hold the wall"}, {"id": "help", "label": "Send help"}, {"id": "back", "label": "Fall back to the school"}], "hold", 30.0)


## The rectangles of the raid HUD's panels that are up (the parts a person or a gun could be hidden under).
func _panels(h) -> Dictionary:
	var out := {}
	for k in ["place_panel", "loot_panel", "cards_grid", "radio_panel", "news_panel", "log_panel", "legend_panel", "weapon_panel", "base_panel", "call_card", "banner", "toast_panel"]:
		var c = h.get(k)
		if c != null and c is Control and c.is_visible_in_tree():
			out[k] = c.get_global_rect()
	return out


## Where a person's body is on the screen (a rectangle round the figure: a third of a tile to each side, a tile above the foot).
func _body(scene: Node, p) -> Rect2:
	var a: Vector2 = scene.to_screen(Vector2(p.x - 0.35, p.y - 1.0))
	var b: Vector2 = scene.to_screen(Vector2(p.x + 0.35, p.y + 0.4))
	return Rect2(a, b - a)


# ------------------------------------------------------- I1: the call card in a place --

func test_in_a_place_the_call_card_is_in_the_right_column_under_the_radio_and_covers_nobody() -> void:
	for size in SIZES:
		var main := _main(size[0], size[1])
		var scene := _open(main)
		scene.select_contact("squad", scene.run.squad[1])
		_attack(main)
		# (the pointer is at the window's left edge: the camera leans that way, which puts the squad toward the right column)
		scene._mouse = Vector2(0.0, size[1] / 2.0)
		scene.over_hud = false
		_play(scene, 2.5)
		await _settle(scene)
		var h = scene.hud_layer
		check(h.call_card.visible, "%s: the call card is up" % str(size))
		var panels := _panels(h)
		var card: Rect2 = panels.get("call_card", Rect2())
		var radio: Rect2 = panels.get("radio_panel", Rect2())
		check(card.size != Vector2.ZERO and radio.size != Vector2.ZERO, "%s: both are shown" % str(size))
		check(card.position.x >= radio.position.x - 0.5, "%s: the card is in the radio's column: %s, the radio %s" % [str(size), str(card), str(radio)])
		check(card.position.y >= radio.end.y - 0.5, "%s: and under the radio: %s, the radio %s" % [str(size), str(card), str(radio)])
		eq(Kit.overlaps(panels), [], "%s: nothing overlaps" % str(size))
		var win := Rect2(0, 0, size[0], size[1])
		check(win.encloses(card.grow(-0.5)), "%s: inside the window: %s" % [str(size), str(card)])
		check(card.size.y <= 230.0, "%s: its height is capped (three short buttons): %.0f" % [str(size), card.size.y])
		for b in h.call_card.view.buttons.values():
			check(b.is_visible_in_tree() and b.get_global_rect().size.y >= 22.0, "%s: every button is there" % str(size))
		# nobody of the squad is under it, or under any other panel
		for p in scene.run.squad:
			for k in panels:
				check(not panels[k].intersects(_body(scene, p).grow(-4.0)), "%s: %s is not under the %s" % [str(size), p.first, k])
		await TutorialKit.leave(main)


func test_the_call_card_steps_aside_for_the_news_in_a_place() -> void:
	for size in SIZES:
		var main := _main(size[0], size[1])
		var scene := _open(main)
		_attack(main)
		await _settle(scene)
		var h = scene.hud_layer
		check(h.call_card.visible, "%s: a call: a card" % str(size))
		h.open_news(true)
		await _settle(scene)
		check(not h.call_card.visible, "%s: the News is up and has the call itself, so the card is not shown twice" % str(size))
		check(h.news_panel.visible and h.news_panel.call_views.size() == 1, "%s: the News holds it" % str(size))
		h.open_news(false)
		await _settle(scene)
		check(h.call_card.visible, "%s: and the card is back when the News is shut" % str(size))
		await TutorialKit.leave(main)


# ------------------------------------------------ M7: the squad off the foot HUD --

func test_at_the_maps_foot_the_squad_is_still_above_the_foot_hud() -> void:
	for size in SIZES:
		var main := _main(size[0], size[1])
		var scene := _open(main, 40)
		var foot_y: float = scene.site.size.y
		for p in scene.run.squad:
			p.x = 6.0 + float(scene.run.squad.find(p)) * 1.2
			p.y = foot_y - 0.9
			p.path = []
		scene.legend_t = 0.0    # (the legend and the log fade by themselves: they are not the camera's business)
		_play(scene, 3.0)
		await _settle(scene)
		var h = scene.hud_layer
		var panels := _panels(h)
		for p in scene.run.squad:
			if p.dead:
				continue
			var body := _body(scene, p)
			check(Rect2(0, 0, size[0], size[1]).encloses(body), "%s: %s is on the screen: %s" % [str(size), p.first, str(body)])
			for k in ["weapon_panel", "base_panel"]:
				if panels.has(k):
					check(not panels[k].intersects(body), "%s: %s is not under the %s: %s, the panel %s" % [str(size), p.first, k, str(body), str(panels[k])])
		await TutorialKit.leave(main)


# --------------------------------------------------------- M6: the light follows the clock --

func _lum(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0


func test_the_places_light_follows_the_base_clock_in_a_clear_ramp() -> void:
	var main := _main()
	var scene := _open(main)
	var lum := {}
	for hour in [12.0, 17.5, 18.0, 18.6, 19.0, 19.67, 20.0, 20.5, 21.0, 23.0, 3.0]:
		main.sim.minutes = hour * 60.0
		lum[hour] = _lum(scene.light_now().color)
	check(lum[12.0] >= 0.97, "noon is day: %.2f" % lum[12.0])
	check(lum[17.5] >= lum[18.6] and lum[18.6] > lum[19.0] and lum[19.0] > lum[19.67] and lum[19.67] > lum[20.5], "it dims through the dusk, hour after hour: %s" % str(lum))
	check(lum[19.67] <= 0.66 * lum[12.0], "twenty to eight is clearly evening: %.2f against %.2f at noon" % [lum[19.67], lum[12.0]])
	check(lum[23.0] <= lum[19.67] - 0.09, "and the night is darker than the evening by more than a shade: %.2f against %.2f" % [lum[23.0], lum[19.67]])
	check(lum[23.0] >= 0.42, "but a place can still be played at night: %.2f" % lum[23.0])
	near(lum[3.0], lum[23.0], 0.01, "the deep night is the same either side of midnight")
	await TutorialKit.leave(main)


# ------------------------------------------------ M9: no crosshair on the downed --

func test_a_downed_leader_has_no_crosshair_in_a_place() -> void:
	var main := _main()
	var scene := _open(main)
	scene._mouse = Vector2(400, 300)
	scene.over_hud = false
	_play(scene, 0.2)
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	var lead = scene.leader()
	check(scene.overlay.drawn_crosshair, "(a crosshair while she stands)")
	lead.downed = true
	scene.overlay.queue_redraw()
	await TutorialKit.settle()
	check(not scene.overlay.drawn_crosshair, "none once the leader is down")
	await TutorialKit.leave(main)


# ---------------------------------------------- M10: a staged aim in a windowed run --

func test_a_staged_aim_and_fire_are_not_overridden_by_the_real_pointer() -> void:
	var main := _main()
	var scene := _open(main)
	scene.live_for_tests = true    # (a windowed run reads the real pointer and the real button; a headless one cannot)
	var lead = scene.leader()
	var aim := Vector2(lead.x + 5.0, lead.y)
	scene.stage("aim:%f:%f" % [aim.x, aim.y])
	scene.tick(STEP)
	near(scene.aim_tile.x, aim.x, 0.2, "the staged aim holds through a frame: %s" % str(scene.aim_tile))
	var shots := int(lead.stats.shots)
	scene.stage("fire:1.5")
	check(int(lead.stats.shots) > shots, "and the staged trigger fires (%d shots)" % (int(lead.stats.shots) - shots))
	# a real move of the pointer takes the aim back
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(100, 100)
	scene._unhandled_input(ev)
	near(scene._mouse.x, 100.0, 0.5, "a real pointer move is the player's")
	await TutorialKit.leave(main)


# ================================================================== the yard ==

const SPOT := Vector2(41.5, 30.5)
const ZOOM := 40.0
const ARENA := Rect2i(32, 24, 24, 16)


## The real game (a classic start, six people, Ruth the avatar) in a window of this size, a clear arena round her.
func _yard(width: int = 1280, height: int = 800) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 6, "avatar": true}, width, height)
	AimMode.set_mode("always")    # (round 22: these tests are of the controls as they were: the mouse aims by itself and the left button fires; the default is tests/test_r22c_*.gd's)
	for ty in range(ARENA.position.y, ARENA.end.y):
		for tx in range(ARENA.position.x, ARENA.end.x):
			main.world.solid_p[ty * main.world.W + tx] = 0
			main.world.solid_z[ty * main.world.W + tx] = 0
	var sim = main.sim
	sim.zombies.clear()
	sim.jobs.clear()
	sim.tactics.chores = false
	sim.waves.enabled = false
	var me = sim.avatar.player()
	_stand(main, me, SPOT)
	main.cam_center = SPOT
	main.zoom_px = ZOOM
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()
	return main


func _person(main: Node, id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


func _stand(main: Node, p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.moving = false
	p.path = []
	p.order = null
	main._sync_views()


func _frames(main: Node, n: int, dt: float = STEP) -> void:
	for i in n:
		main._process(dt)


func _draw_once(main: Node) -> void:
	main.overlay.queue_redraw()
	await TutorialKit.settle()


func _press(main: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	main._unhandled_input(ev)


func _texts(c: Node) -> String:
	var out: Array = []
	for l in c.find_children("*", "Label", true, false):
		if l.is_visible_in_tree():
			out.append(l.text)
	return " | ".join(out)


## What of the HUD a person could be hidden under, in the yard.
func _hud_rects(h) -> Dictionary:
	var out := {}
	for k in ["res_panel", "clock", "ammo_panel", "speed_panel", "inspect", "radio_box", "gizmos", "help", "news_panel", "call_card"]:
		var c = h.get(k)
		if c != null and c is Control and c.is_visible_in_tree():
			out[k] = c.get_global_rect()
	for c in h.cards:
		out["card_%s" % c.p.id] = c.card.get_global_rect()
	return out


func _screen_body(main: Node, p) -> Rect2:
	var pos: Vector2 = main.view_pos(p)
	var a: Vector2 = main._tile_to_screen(Vector2(pos.x - 0.35, pos.y - 1.0))
	var b: Vector2 = main._tile_to_screen(Vector2(pos.x + 0.35, pos.y + 0.4))
	return Rect2(a, b - a)


# ----------------------------------------------------- M1: the camera and the dock --

func test_with_a_contact_selected_the_avatar_is_not_under_the_dock() -> void:
	for size in SIZES:
		var main := _yard(size[0], size[1])
		var dez = _person(main, "dez")
		_stand(main, dez, SPOT + Vector2(-3.0, 1.0))
		main._try_select({"kind": "person", "ref": dez})
		await TutorialKit.frames(main, 60)
		var me = main.sim.avatar.player()
		var body := _screen_body(main, me)
		var rects := _hud_rects(main.hud)
		check(rects.has("inspect"), "%s: the dock is up" % str(size))
		for k in rects:
			check(not rects[k].intersects(body.grow(-3.0)), "%s: the avatar is not under the %s: %s, %s" % [str(size), k, str(body), str(rects[k])])
		check(Rect2(0, 0, size[0], size[1]).encloses(body), "%s: and on the screen: %s" % [str(size), str(body)])
		# without a selection the camera is on her again, in the middle
		main._select(null)
		await TutorialKit.frames(main, 60)
		var centre: Vector2 = main._tile_to_screen(main.view_pos(me))
		check(centre.distance_to(main._vp() / 2.0) < 6.0, "%s: nothing selected, she is in the middle again: %s" % [str(size), str(centre)])
		await TutorialKit.leave(main)


func test_where_the_dock_is_not_under_her_the_camera_does_not_move_for_it() -> void:
	var main := _yard(1600, 1000)
	var dez = _person(main, "dez")
	_stand(main, dez, SPOT + Vector2(-3.0, 1.0))
	main._try_select({"kind": "person", "ref": dez})
	await TutorialKit.frames(main, 60)
	var me = main.sim.avatar.player()
	var centre: Vector2 = main._tile_to_screen(main.view_pos(me))
	check(centre.distance_to(main._vp() / 2.0) < 6.0, "a wide window has the room beside the dock: she stays in the middle: %s" % str(centre))
	await TutorialKit.leave(main)


# --------------------------------------------------------------- M4: the camera glides --

func test_a_succession_glides_the_camera_to_the_new_player() -> void:
	var main := _yard()
	var sim = main.sim
	for q in sim.people:
		q.trust = 40.0
	var ana = _person(main, "ana")
	ana.trust = 95.0
	var there := Vector2(SPOT.x + 9.0, SPOT.y + 5.0)
	_stand(main, ana, there)
	var from: Vector2 = main.cam_center
	var dist := from.distance_to(there)
	sim.medical.kill(_person(main, "ruth"), "bled out")
	_frames(main, 1)
	eq(sim.player_id, "ana", "Ana leads")
	check(main.cam_center.distance_to(from) < 0.25 * dist, "one frame later the camera has not jumped: %.1f of %.1f tiles" % [main.cam_center.distance_to(from), dist])
	_frames(main, 8)
	var mid: float = main.cam_center.distance_to(from)
	check(mid > 0.1 * dist and mid < 0.9 * dist, "a third of a second in it is on its way: %.1f of %.1f tiles" % [mid, dist])
	_frames(main, 30)
	check(main.cam_center.distance_to(Vector2(ana.x, ana.y)) < 1.0, "and a second later it is on her: %s" % str(main.cam_center))
	eq(main.hud.banner_title.text.to_lower(), "ana leads now", "the banner says it")
	await TutorialKit.leave(main)


func test_a_focus_glides_and_holds_and_comes_back() -> void:
	var main := _yard()
	var ruth = main.sim.avatar.player()
	var far := Vector2(SPOT.x + 5.0, SPOT.y + 3.0)
	var from: Vector2 = main.cam_center
	main._focus(far)
	check(main.cam_center.distance_to(from) < 0.2 * from.distance_to(far), "the jump is not a cut: %s" % str(main.cam_center))
	check(main.cam_hold > 1.0, "and the camera is held there a while")
	_frames(main, 25)
	check(main.cam_center.distance_to(far) < 0.5, "it is there in under a second: %s" % str(main.cam_center))
	_frames(main, 90)
	check(main.cam_center.distance_to(Vector2(ruth.x, ruth.y)) < 0.5, "and eases back to the avatar")
	await TutorialKit.leave(main)


# ---------------------------------------------------------------- M5: pointer and Tab --

func test_the_pointer_leaving_the_window_takes_the_crosshair_and_the_lean() -> void:
	var main := _yard()
	var ev := InputEventMouseMotion.new()
	ev.position = main._vp() - Vector2(3, 3)
	main._input(ev)
	main._unhandled_input(ev)
	_frames(main, 3)
	await _draw_once(main)
	check(main.overlay.drew_crosshair, "(a crosshair near the edge)")
	main._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	_frames(main, 3)
	await _draw_once(main)
	check(not main.overlay.drew_crosshair, "none once the pointer has left the window")
	check(main.pointer_mode() == Input.MOUSE_MODE_VISIBLE, "and the system's arrow is not hidden")
	var ruth = main.sim.avatar.player()
	_frames(main, 60)
	check(main.cam_center.distance_to(Vector2(ruth.x, ruth.y)) < 0.3, "the camera does not lean toward a pointer that is not there: %s" % str(main.cam_center))
	await TutorialKit.leave(main)


func test_the_first_tab_does_something_you_can_see_or_nothing() -> void:
	var main := _yard()
	main._select(null)
	_press(main, KEY_TAB)
	_frames(main, 2)
	var me = main.sim.avatar.player()
	check(main.selection == null or main.selection.ref != me, "Tab does not 'select' the one you are: it picks somebody you can ask")
	check(main.selection != null, "there is somebody: a card is lit")
	await TutorialKit.leave(main)


# ------------------------------------------------------------------ M9: no crosshair down --

func test_a_downed_avatar_has_no_crosshair_in_the_yard() -> void:
	var main := _yard()
	var me = main.sim.avatar.player()
	_frames(main, 2)
	await _draw_once(main)
	check(main.overlay.drew_crosshair, "(a crosshair while she stands)")
	me.downed = true
	await _draw_once(main)
	check(not main.overlay.drew_crosshair, "none once she is down")
	await TutorialKit.leave(main)


# ---------------------------------------------- I5: the crosshair that cannot fire --

func test_the_crosshair_is_greyed_with_a_ladder_hint_while_the_shot_would_hit_a_walkways_face() -> void:
	var main := _yard()
	var me = main.sim.avatar.player()
	if not main.sim.avatar.has_method("fire_blocked"):
		return
	_stand(main, me, Vector2(40.0, 21.3))
	main.cam_center = Vector2(40.0, 21.3)
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._tile_to_screen(Vector2(40.0, 12.0))
	_frames(main, 2)
	check(main.sim.avatar.fire_blocked(me), "(the wall's face is in the way)")
	await _draw_once(main)
	check(main.overlay.drew_crosshair and main.overlay.crosshair_blocked, "the crosshair says it cannot fire")
	check(main.overlay.drew_blocked_hint, "with a hint near it: climb a ladder")
	main.mouse_screen = main._tile_to_screen(Vector2(40.0, 30.0))
	_frames(main, 2)
	await _draw_once(main)
	check(main.overlay.drew_crosshair and not main.overlay.crosshair_blocked and not main.overlay.drew_blocked_hint, "aimed into the yard it is the ordinary one")
	await TutorialKit.leave(main)


# ------------------------------------------------------ M2: bubbles keep out of the dock --

func test_a_bubble_that_would_be_under_the_dock_is_not_drawn() -> void:
	var main := _yard(700, 560)
	var dez = _person(main, "dez")
	_stand(main, dez, SPOT + Vector2(-4.0, 3.0))
	main._try_select({"kind": "person", "ref": dez})
	await TutorialKit.frames(main, 40)
	var vp: Vector2 = main._vp()
	main.overlay.bubbles.clear()
	main.overlay.add_bark({"who": "dez", "text": "On my way.", "context": "radio"})
	var plan: Array = main.overlay.bubble_plan(vp)
	var covered: Array = main.hud.covered_rects()
	check(not covered.is_empty(), "(the HUD tells what it covers)")
	for b in plan:
		for r in covered:
			check(not r.intersects(b.rect), "a bubble that is drawn is clear of every panel: %s, %s" % [str(b.rect), str(r)])
	# Dez stands where the dock is: no bubble
	var spot := Vector2(main.hud.inspect.get_global_rect().get_center())
	var tile: Vector2 = main._screen_to_tile(spot)
	_stand(main, dez, tile)
	main.overlay.bubbles.clear()
	main.overlay.add_bark({"who": "dez", "text": "On my way.", "context": "radio"})
	eq(main.overlay.bubble_plan(vp).size(), 0, "a speaker under the dock has no bubble (the dock, a toast and the card say it already)")
	# and one in the clear still has
	_stand(main, dez, main._screen_to_tile(Vector2(vp.x * 0.62, vp.y * 0.5)))
	main.overlay.bubbles.clear()
	main.overlay.add_bark({"who": "dez", "text": "On my way.", "context": "radio"})
	eq(main.overlay.bubble_plan(vp).size(), 1, "one in the open does")
	await TutorialKit.leave(main)


# ------------------------------------------------------- M3: the stance on a crew card --

func test_a_crew_card_spells_the_stance_of_the_one_it_is_for() -> void:
	for size in [[1280, 800], [700, 560]]:
		var main := _yard(size[0], size[1])
		var dez = _person(main, "dez")
		var card: Dictionary = {}
		for c in main.hud.cards:
			if c.p == dez:
				card = c
		# (a card 56 px wide or more has the whole word; a narrow one, in a small window, the short one: the same word's stem)
		for pair in [["follow", "Following", "Follow"], ["hold", "Holding", "Hold"], ["cover", "Covering", "Cover"], ["search", "Searching", "Search"]]:
			main.sim.radio.set_stance(dez, pair[0], Vector2(dez.x, dez.y))
			main.hud.update_hud(main.sim, 1, true, 0)
			await TutorialKit.settle()
			var want: String = pair[1] if card.card.custom_minimum_size.x >= 56.0 else pair[2]
			if size[0] >= 1280:
				eq(want, pair[1], "(a card in a wide window is wide: %d)" % int(card.card.custom_minimum_size.x))
			check(card.stance_box.visible and card.stance.text == want, "%s: %s reads '%s': '%s'" % [str(size), pair[0], want, card.stance.text])
			check(card.stance.get_theme_font_size("font_size") >= 12, "%s: 12 px or more" % str(size))
			var inside: bool = card.card.get_global_rect().grow(1.0).encloses(card.stance_box.get_global_rect())
			check(inside, "%s: '%s' is inside the card: %s in %s" % [str(size), pair[1], str(card.stance_box.get_global_rect()), str(card.card.get_global_rect())])
		main.sim.radio.clear_stance(dez)
		main.hud.update_hud(main.sim, 1, true, 0)
		check(not card.stance_box.visible, "%s: no stance, no word" % str(size))
		await TutorialKit.leave(main)


# ------------------------------------------------------------------ I7: the ammo readout --

func test_the_gun_readout_shows_only_rounds_that_can_be_fired() -> void:
	var main := _yard()
	var me = main.sim.avatar.player()
	var h = main.hud
	var cap := int(me.gun.mag)
	me.mag = cap
	main.sim.stock.ammo = 400.0
	h.update_hud(main.sim, 1, true, 0)
	eq(h.ammo_label.text, "%d / 400" % cap, "plenty in the stores: the magazine as it is")
	eq(h.ammo_label.get_theme_color("font_color"), Hud.INK, "in the ordinary ink")
	main.sim.stock.ammo = 1.0
	h.update_hud(main.sim, 1, true, 0)
	eq(h.ammo_label.text, "1 / 1", "one round in the stores: one round to fire, not a full magazine")
	eq(h.ammo_label.get_theme_color("font_color"), Hud.WARN, "in amber: the stores cannot fill the magazine")
	main.sim.stock.ammo = 2.7
	h.update_hud(main.sim, 1, true, 0)
	eq(h.ammo_label.text, "2 / 2", "two and a bit: two")
	main.sim.stock.ammo = 0.0
	h.update_hud(main.sim, 1, true, 0)
	eq(h.ammo_label.text, "0 / 0", "none: the magazine part is nothing too")
	eq(h.ammo_label.get_theme_color("font_color"), Hud.DANGER_TEXT, "in red")
	check(h.ammo_panel.tooltip_text.to_lower().contains("rounds come from the stores"), "the tooltip says where rounds come from: %s" % h.ammo_panel.tooltip_text)
	await TutorialKit.leave(main)


# ============================================================ I4: the first screen ==

func test_the_first_screen_says_what_the_radio_is_and_where_the_map_and_the_news_are() -> void:
	var main := _yard()
	main.hud.update_hud(main.sim, 1, true, 0)
	check(main.hud.hint.visible, "the hint is up")
	var words := _texts(main.hud.hint).to_lower()
	for want in ["crew card", "radio", "map", "news", "move", "aim", "fire", "reload"]:
		check(words.contains(want), "the hint says '%s': %s" % [want, words])
	var keys: Array = []
	for l in main.hud.hint.find_children("*", "Label", true, false):
		keys.append(l.text)
	check(keys.has("G") and keys.has("T"), "with the keys G and T: %s" % str(keys))
	await TutorialKit.leave(main)


func test_the_hint_stays_until_somebody_has_been_asked_for_something() -> void:
	var main := _yard()
	var h = main.hud
	var me = main.sim.avatar.player()
	me.stats.shots = 5
	h.update_hud(main.sim, 1, true, 0)
	check(h.hint.visible, "three shots (or five) do not spend it")
	# a click on a crew card: the dock is up and the hint waits (it would be under it), but it is not spent
	main._try_select({"kind": "person", "ref": _person(main, "dez")})
	h.update_hud(main.sim, 1, true, 0)
	check(not h.hint_spent, "a card click does not spend it")
	check(not h.hint.visible, "it gives way to the dock while it is up")
	main._select(null)
	h.update_hud(main.sim, 1, true, 0)
	check(h.hint.visible, "and is back when the dock goes")
	# somebody is asked: that is what it was for
	main._try_select({"kind": "person", "ref": _person(main, "dez")})
	h.update_hud(main.sim, 1, true, 0)
	h.radio_verbs.press("come")
	check(h.hint_spent, "asking Dez to come spends it")
	main._select(null)
	h.update_hud(main.sim, 1, true, 0)
	check(not h.hint.visible, "and it does not come back")
	await TutorialKit.leave(main)


func test_the_hint_fits_and_covers_nothing_in_the_smallest_window() -> void:
	for size in SIZES:
		var main := _yard(size[0], size[1])
		main.hud.update_hud(main.sim, 1, true, 0)
		await TutorialKit.frames(main, 6)
		var hint: Rect2 = main.hud.hint.get_global_rect()
		check(main.hud.hint.visible, "%s: the hint is shown (a small window keeps it too)" % str(size))
		check(Rect2(0, 0, size[0], size[1]).grow(0.5).encloses(hint), "%s: it fits the window: %s" % [str(size), str(hint)])
		var rects := _hud_rects(main.hud)
		for k in rects:
			check(not rects[k].intersects(hint.grow(-1.0)), "%s: it is clear of the %s: %s, %s" % [str(size), k, str(hint), str(rects[k])])
		await TutorialKit.leave(main)


func test_the_hint_gives_way_to_the_help_and_the_news_while_they_are_open() -> void:
	var main := _yard(700, 560)
	var h = main.hud
	h.update_hud(main.sim, 1, true, 0)
	check(h.hint.visible, "(up)")
	h._press_help()
	check(not h.hint.visible, "the help is open: the hint is not over it")
	h._press_help()
	check(h.hint.visible and not h.hint_spent, "and it is back when the help is shut")
	h.set_news(true)
	check(not h.hint.visible, "the same for the News")
	h.set_news(false)
	check(h.hint.visible, "and back")
	await TutorialKit.leave(main)


func test_the_old_yards_hint_is_as_it_was_and_a_narrow_window_still_spends_it() -> void:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 6}, 700, 560)
	main.hud.update_hud(main.sim, 1, true, 0)
	check(main.hud.hint_spent and not main.hud.hint.visible, "classic, narrow: no hint, as ever")
	await TutorialKit.leave(main)


func test_the_help_lists_the_radio_verbs_and_the_radio_button_says_what_it_is() -> void:
	var main := _yard()
	main.hud.help.visible = true
	var help := _texts(main.hud.help).to_lower()
	for want in ["radio", "come", "hold", "cover", "search", "back"]:
		check(help.contains(want), "the help says '%s': %s" % [want, help])
	check(main.hud.news_button.tooltip_text.to_lower().contains("radio"), "the radio's toolbar button says so: %s" % main.hud.news_button.tooltip_text)
	check(main.hud.news_button.tooltip_text.contains("crew card"), "and how to use it: %s" % main.hud.news_button.tooltip_text)
	await TutorialKit.leave(main)


func test_the_first_dusk_tip_has_the_radio_and_the_ladder_and_the_fever_tip_the_call_card() -> void:
	var all := Hints.load_hints()
	var dusk := {}
	var fever := {}
	for t in all:
		if String(t.id) == "dusk":
			dusk = t
		if String(t.id) == "fever":
			fever = t
	var d := String(dusk.get("text_avatar", ""))
	check(d.contains("Climb a ladder to shoot over the wall"), "the dusk tip tells of the ladder: %s" % d)
	check(d.to_lower().contains("radio") and d.to_lower().contains("crew card"), "and the radio: %s" % d)
	var f := String(fever.get("text_avatar", ""))
	check(f.to_lower().contains("sick call") and f.to_lower().contains("treat") and f.to_lower().contains("keep apart") and f.to_lower().contains("send out"), "the fever tip points at the call card: %s" % f)
	for t in [dusk, fever]:
		var n: int = Coach.words(String(t.get("text_avatar", "")))
		check(n >= 8 and n <= Coach.MAX_WORDS, "%s: %d words" % [t.id, n])


# ============================================================ M11: no Search that in the yard ==

func test_search_that_is_not_offered_in_the_yard_but_is_in_a_place() -> void:
	var main := _yard()
	main._try_select({"kind": "person", "ref": _person(main, "dez")})
	main.hud.update_hud(main.sim, 1, true, 0)
	await TutorialKit.settle()
	var v = main.hud.radio_verbs
	check(not v.buttons["search"].visible, "no Search that in the yard: there is nothing to search")
	for verb in ["come", "hold", "cover", "back", "post"]:
		check(v.buttons[verb].visible, "%s is still there" % verb)
	var scene := _open(main)
	scene.select_contact("squad", scene.run.squad[1])
	scene.hud_layer.refresh()
	await TutorialKit.settle()
	check(scene.hud_layer.radio_verbs.buttons["search"].visible, "in a place it is")
	await TutorialKit.leave(main)
