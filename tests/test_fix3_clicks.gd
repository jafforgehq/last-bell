extends "res://tests/case.gd"
## Fix round 3: "I can't click on dialog options when talking with people". The talk card (scripts/ui/talk_card.gd) hid itself and showed itself again
## in every frame to leave itself out of the HUD's list of boards, and a button forgets a press that is going on when it is hidden: the press of a real
## click was gone before the release came, and no verb, Insist or the close button ever fired. These tests click with real mouse events (a press, a few
## frames, a release, through the viewport as the engine does) on a verb of the talk card in each aiming mode (Right button aims, Always aim, the weapon
## put away) and on the options of the call card and of the News page.

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const AimMode := preload("res://scripts/aim_mode.gd")

const HOLD_FRAMES := 4


func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	# (in the viewport's own coordinates, which a control's global rect is in: the game stretches its window by the interface size, so a position given as window
	# pixels, the default of `push_input`, would land on another place)
	Engine.get_main_loop().root.push_input(ev, true)


## A real click at `pos`: the pointer arrives, the button goes down, a few frames pass, the button comes up.
func _click(pos: Vector2) -> void:
	var tree := Engine.get_main_loop()
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	tree.root.push_input(move, true)
	await tree.process_frame
	_mouse(pos, true)
	for i in HOLD_FRAMES:
		await tree.process_frame
	_mouse(pos, false)
	await tree.process_frame


func _game(mode: String, holstered: bool) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 3, "crew": 5, "avatar": true}, 1600, 1000)
	AimMode.set_mode(mode)
	AimMode.set_holstered(holstered)
	await TutorialKit.settle()
	main.sim.waves.enabled = false
	main.sim.zombies.clear()
	return main


func _talk_to_dez(main: Node):
	var dez = null
	for p in main.sim.people:
		if p.id == "dez":
			dez = p
	check(main._stage_talk("dez", ""), "the talk card is opened beside Dez")
	await TutorialKit.settle()
	return dez


func test_a_talk_card_verb_and_the_close_button_take_a_real_click_in_every_aiming_mode() -> void:
	for setup in [["right", false], ["always", false], ["right", true]]:
		var label := "%s%s" % [setup[0], ", weapon put away" if setup[1] else ""]
		var main = await _game(setup[0], setup[1])
		await _talk_to_dez(main)
		var card = main.hud.talk_card
		check(main.hud.talk_open(), "%s: the card is up" % label)
		var asked := [0]
		var verb: Button = card.verbs.buttons["hold"]
		verb.pressed.connect(func(): asked[0] += 1)
		await _click(verb.get_global_rect().get_center())
		eq(asked[0], 1, "%s: one click on Hold is one press" % label)
		eq(String(card.verbs.last.get("verb", "")), "hold", "%s: and the radio was asked it" % label)
		check(main.hud.talk_open(), "%s: the card stays for the next verb" % label)
		await _click(card.close_button.get_global_rect().get_center())
		check(not main.hud.talk_open(), "%s: the x closes it" % label)
		AimMode.set_holstered(false)
		await TutorialKit.leave(main)


func test_insist_after_a_refusal_takes_a_real_click() -> void:
	var main = await _game("right", false)
	var dez = _dez(main)
	dez.bleeding = 2.0    # (a soft refusal: "Bleeding, can't come", with Insist)
	await _talk_to_dez(main)
	var card = main.hud.talk_card
	await _click(card.verbs.buttons["come"].get_global_rect().get_center())
	check(not bool(card.verbs.last.get("ok", true)), "Come with me is refused for a bleeding Dez")
	check(card.verbs.insist_button.is_visible_in_tree(), "and Insist is offered")
	var insisted := [0]
	card.verbs.insist_button.pressed.connect(func(): insisted[0] += 1)
	await _click(card.verbs.insist_button.get_global_rect().get_center())
	eq(insisted[0], 1, "a click on Insist is one press")
	await TutorialKit.leave(main)


func _dez(main: Node):
	for p in main.sim.people:
		if p.id == "dez":
			return p
	return null


func test_a_call_card_option_and_a_news_page_option_take_a_real_click() -> void:
	var main = await _game("right", false)
	var sim = main.sim
	var first: int = sim.radio.raise_call("fever", "A call", "", [{"id": "yes", "label": "Yes"}, {"id": "no", "label": "No"}], "no", 30.0, {}, Vector2(40, 10))
	main.hud.update_hud(sim, 1, true, 0)
	await TutorialKit.settle()
	var card = main.hud.call_card
	check(card.visible and card.view.buttons.has("yes"), "the call card shows its options")
	await _click(card.view.buttons["yes"].get_global_rect().get_center())
	eq(String(_entry(sim, first).get("answered", "")), "yes", "a click on Yes answers the call")
	var second: int = sim.radio.raise_call("fever", "Another call", "", [{"id": "a", "label": "Option A"}, {"id": "b", "label": "Option B"}], "b", 30.0, {}, Vector2(40, 10))
	main.hud.open_radio("news")
	main.hud.update_hud(sim, 1, true, 0)
	await TutorialKit.settle()
	check(not main.hud.news_panel.call_views.is_empty(), "the News page lists the call")
	var button: Button = main.hud.news_panel.call_views[0].buttons["a"]
	await _click(button.get_global_rect().get_center())
	eq(String(_entry(sim, second).get("answered", "")), "a", "a click on an option of the News page answers it")
	await TutorialKit.leave(main)


func _entry(sim, id: int) -> Dictionary:
	for e in sim.radio.news:
		if int(e.id) == id:
			return e
	return {}
