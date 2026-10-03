extends "res://tests/case.gd"
## The radio panel (round 18, slice 2, V2.1 PANEL-SHELL): in avatar mode one NON-MODAL board on the right of the window with four pages,
## Jobs, Build, Map and News (scripts/ui/radio_panel.gd). The pages open from the keys T, J, N, G and the toolbar, the last page is
## remembered, the same key shuts it, Shift+J, N, G are the modal full pages, Esc closes the talk card, then the panel, then the selection,
## else the pause menu. It never pauses the game or takes the hands off the avatar, fits and touches neither the clock, the gun's readout nor
## the toolbar at the five window sizes, keeps the avatar in view (`hud.free_view()`, the camera), keeps the oldest call in view as a slim strip
## under the tabs, and its News page is round 17's News (tests/test_radio_ui.gd has those). The pages' own tests are theirs: here the pages are
## the stubs or the real ones, and fakes where the panel's own work is tested (lazy building, refreshing only the open page, focus, fitting).

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const RadioPanel := preload("res://scripts/ui/radio_panel.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const TextTests := preload("res://tests/test_hud_text.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]
const DT := 1.0 / 30.0


# ---------------------------------------------------------------- helpers --

## A HUD over a quiet game in avatar mode (Ruth the player; `crew` 3 is a settlement game, which has the Map page, 6 the classic start).
func _ctx(width: int = 1280, height: int = 800, crew: int = 3, player: String = "ruth") -> Dictionary:
	var ctx := Kit.build(width, height, 1, false, crew)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	if player != "":
		check(sim.avatar.set_player(player), "%s is the player" % player)
	Kit.update(ctx)
	return ctx


func _attack_call(radio) -> int:
	return radio.raise_call("attack", "North wall under attack", "3 of the dead at it, 80% intact", [
		{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send reinforcements"}, {"id": "fall_back", "label": "Fall back to the school"},
	], "hold", 30.0, {"seg": 1}, Vector2(40, 10))


func _fever_call(radio) -> int:
	return radio.raise_call("sick", "Hector has a fever", "Treat them, or keep them apart", [
		{"id": "treat", "label": "Treat them"}, {"id": "apart", "label": "Keep them apart"},
	], "treat", 60.0, {"who": "hector"}, Vector2(30, 30))


## The real game scene as an avatar's run: `crew` 3 is a settlement game (a small start), 6 the classic one. Not the tutorial.
func _main(crew: int = 3, width: int = 1280, height: int = 800) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": crew, "avatar": true}, width, height)
	main.sim.waves.enabled = false
	main.sim.zombies.clear()
	main.hud.update_hud(main.sim, 1, true, 0)
	return main


func _press(main: Node, code: Key, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	ev.shift_pressed = shift
	main._unhandled_input(ev)


func _frames(main: Node, n: int) -> void:
	for i in n:
		main._process(DT)
		main.hud.update_hud(main.sim, main.speed, true, 0)


func _hold(codes: Array, down: bool) -> void:
	for code in codes:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _person(main: Node, id: String):
	for p in main.sim.people:
		if p.id == id:
			return p
	return null


## The words on screen in a part of the HUD (a hidden label says nothing).
func _texts_of(node: Node) -> String:
	var out: Array = []
	_collect(node, out)
	return " | ".join(out)


func _collect(node: Node, out: Array) -> void:
	if node is Control and not node.visible:
		return
	if node is Label and node.text != "":
		out.append(node.text)
	for c in node.get_children():
		_collect(c, out)


## A page the stub of the orchestrator is (a lone label): the contrast and size checks of the panel leave it to its builder's own tests.
func _is_stub(node: Node) -> bool:
	return node.get_child_count() == 1 and node.get_child(0) is Label and not node.get_child(0).has_theme_font_size_override("font_size")


## A page that counts what the panel asks of it.
class FakePage:
	extends VBoxContainer
	var setups := 0
	var refreshes := 0
	var focused: Array = []
	var fulls := 0
	var options := {}

	func setup(_host, _sim_getter, opts: Dictionary = {}) -> void:
		setups += 1
		options = opts

	func refresh() -> void:
		refreshes += 1

	func focus_on(id: String) -> void:
		focused.append(id)

	func full_page() -> void:
		fulls += 1


## A panel of its own in a holder, with fake pages in place of the real ones (the News page is the real one).
func _bare(ctx: Dictionary) -> Dictionary:
	var panel = RadioPanel.new()
	ctx.holder.add_child(panel)
	panel.setup(ctx.hud, func(): return ctx.sim)
	var fakes := {}
	for page in ["jobs", "build", "map"]:
		var f := FakePage.new()
		panel.scroll.add_child(f)
		f.visible = false
		f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.pages[page] = f
		fakes[page] = f
	return {"panel": panel, "fakes": fakes}


# ---------------------------------------------------------------- the pages --

func test_the_pages_open_and_the_last_one_is_remembered() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	check(not h.radio_open() and h.radio_page() == "", "shut at first")
	h.open_radio()
	eq(h.radio_page(), "news", "the first time it is News")
	h.open_radio("jobs")
	eq(h.radio_page(), "jobs", "a page's key moves to it")
	eq(h.radio_panel.last_page, "jobs", "and it is the last page now")
	h.close_radio()
	check(not h.radio_open(), "shut")
	h.open_radio()
	eq(h.radio_page(), "jobs", "T opens it on the page it was left on")
	h.toggle_radio("jobs")
	check(not h.radio_open(), "the same key shuts it")
	h.toggle_radio("build")
	eq(h.radio_page(), "build", "another key opens its page")
	h.toggle_radio("map")
	eq(h.radio_page(), "map", "and a third moves to it")
	h.toggle_radio("")
	check(not h.radio_open(), "the panel's own key shuts it")
	h.toggle_radio("")
	eq(h.radio_page(), "map", "and opens it where it was")
	for page in ["jobs", "build", "map", "news"]:
		h.open_radio(page)
		eq(h.radio_page(), page, "%s opens" % page)
		check(h.radio_panel.page_node(page).visible, "its page is up")
		for other in ["jobs", "build", "map", "news"]:
			if other != page:
				check(not h.radio_panel.page_node(other).visible, "(and %s is not)" % other)
	Kit.free_all(ctx)


func test_the_tabs_move_between_the_pages() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	h.open_radio("news")
	h.radio_panel.tab_button("build").pressed.emit()
	eq(h.radio_page(), "build", "a tab opens its page")
	h.radio_panel.tab_button("build").pressed.emit()
	eq(h.radio_page(), "build", "and pressed again it stays (the key is what shuts it)")
	h.radio_panel.close_button.pressed.emit()
	check(not h.radio_open(), "the close button shuts it")
	var names: Array = []
	for page in RadioPanel.PAGES:
		names.append(h.radio_panel.tab_button(page).text)
	eq(names, ["Jobs", "Build", "Map", "News"], "the tabs are named for the pages")
	Kit.free_all(ctx)


func test_the_map_page_is_for_a_settlement_game() -> void:
	var classic := _ctx(1280, 800, 6)
	var h = classic.hud
	check(not classic.sim.town.on, "(the classic start has no town)")
	check(not h.radio_panel.tab_button("map").visible, "no Map tab in the classic start")
	h.open_radio("map")
	check(not h.radio_open(), "and the Map cannot be opened")
	h.open_radio("jobs")
	eq(h.radio_page(), "jobs", "the others can")
	h.open_radio("map")
	eq(h.radio_page(), "jobs", "(and a try at the Map leaves it as it is)")
	Kit.free_all(classic)
	var town := _ctx(1280, 800, 3)
	check(town.sim.town.on, "(a small start is a settlement game)")
	town.hud.open_radio("map")
	check(town.hud.radio_panel.tab_button("map").visible, "the Map tab is there in a settlement game")
	eq(town.hud.radio_page(), "map", "and opens")
	Kit.free_all(town)


func test_there_is_no_panel_without_an_avatar() -> void:
	var ctx := _ctx(1280, 800, 3, "")
	var h = ctx.hud
	h.open_radio("jobs")
	check(not h.radio_open(), "no avatar: it cannot be opened")
	h.toggle_radio("news")
	check(not h.radio_open(), "by any key")
	h.toggle_news()
	check(not h.news_open(), "nor as the News")
	eq(h.free_view(), Rect2(Vector2.ZERO, h.size), "and the free view is the window")
	ctx.sim.avatar.set_player("ruth")
	Kit.update(ctx)
	h.open_radio("news")
	check(h.radio_open(), "an avatar that comes later has it")
	ctx.sim.avatar.set_player("")
	h.set_avatar(false)
	check(not h.radio_open(), "and it is put away when the avatar goes")
	Kit.free_all(ctx)


func test_the_panel_is_not_a_modal_and_takes_no_focus() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	for page in ["jobs", "build", "map", "news"]:
		h.open_radio(page)
		Kit.update(ctx)
		check(not h.modal_open(), "%s: it is not a modal" % page)
	eq(ctx.speeds, [], "nothing asked the game to pause")
	var bad: Array = []
	var nodes: Array = [h.radio_panel]
	nodes.append_array(h.radio_panel.find_children("*", "Control", true, false))
	for c in nodes:
		if c is Control and c.focus_mode != Control.FOCUS_NONE:
			bad.append("%s %s" % [c.get_class(), c.name])
	eq(bad, [], "no control of the panel can take the keyboard")
	Kit.free_all(ctx)


func test_the_panel_builds_its_pages_when_first_asked_and_refreshes_only_the_open_one() -> void:
	var ctx := _ctx()
	var bare := _bare(ctx)
	var panel = bare.panel
	var fakes: Dictionary = bare.fakes
	check(panel.pages.has("jobs") and not panel.pages.has("news"), "(the fakes are in; the News page is not built yet)")
	panel.refresh()
	check(panel.pages.has("news"), "the News page is built as soon as the tab has to know what is unread")
	eq(fakes.jobs.refreshes + fakes.build.refreshes + fakes.map.refreshes, 0, "a shut panel refreshes no page")
	panel.open("jobs")
	var before: int = fakes.jobs.refreshes
	check(before >= 1, "an open page is refreshed")
	panel.refresh()
	panel.refresh()
	eq(fakes.jobs.refreshes, before + 2, "each time")
	eq(fakes.build.refreshes + fakes.map.refreshes, 0, "and no other page is")
	panel.open("build")
	panel.refresh()
	var jobs_then: int = fakes.jobs.refreshes
	panel.refresh()
	eq(fakes.jobs.refreshes, jobs_then, "a page that is not up does nothing")
	check(fakes.build.refreshes >= 2, "the one that is up does")
	eq(fakes.jobs.setups, 0, "(the fakes were set up by nobody: the panel did not build them again)")
	panel.free()
	Kit.free_all(ctx)


func test_a_page_is_handed_the_focus_and_the_full_page_goes_through() -> void:
	var ctx := _ctx()
	var bare := _bare(ctx)
	var panel = bare.panel
	var fakes: Dictionary = bare.fakes
	panel.open("jobs", {"focus": "dez"})
	eq(fakes.jobs.focused, ["dez"], "opts.focus goes to the page's focus_on")
	panel.open("build", {"focus": "workshop"})
	eq(fakes.build.focused, ["workshop"], "to the page that was asked for")
	eq(fakes.jobs.focused, ["dez"], "and to no other")
	panel.open("build")
	eq(fakes.build.focused, ["workshop"], "a plain open asks nothing of it")
	panel.open("jobs")
	panel.full_page()
	eq(fakes.jobs.fulls, 1, "full_page asks the open page for its modal version")
	eq(fakes.build.fulls, 0, "and only that one")
	panel.close()
	panel.full_page()
	eq(fakes.jobs.fulls, 2, "(shut, it is the last page's)")
	panel.free()
	Kit.free_all(ctx)


func test_every_page_has_the_four_functions_and_lies_in_the_panels_scroll() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	for page in ["jobs", "build", "map", "news"]:
		h.open_radio(page)
		var node = h.radio_panel.page_node(page)
		check(node != null and node.has_method("refresh") and node.has_method("focus_on") and node.has_method("full_page"), "%s has the page's four functions" % page)
		check(node.get_parent() == h.radio_panel.scroll, "%s lies in the panel's scroll" % page)
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the keys --

func test_the_keys_open_the_pages_and_the_same_key_shuts_them() -> void:
	var main := _main()
	var h = main.hud
	_press(main, KEY_T)
	eq(h.radio_page(), "news", "T opens the panel on News, the first time")
	_press(main, KEY_T)
	check(not h.radio_open(), "and shuts it")
	_press(main, KEY_J)
	eq(h.radio_page(), "jobs", "J opens Jobs")
	_press(main, KEY_N)
	eq(h.radio_page(), "build", "N moves to Build")
	_press(main, KEY_G)
	eq(h.radio_page(), "map", "G to the Map")
	_press(main, KEY_G)
	check(not h.radio_open(), "the same key again shuts it")
	_press(main, KEY_T)
	eq(h.radio_page(), "map", "T opens it where it was left")
	_press(main, KEY_N)
	_press(main, KEY_N)
	check(not h.radio_open(), "N twice")
	check(h.jobs_screen == null and h.build_screen == null and h.scavenge_dialog == null, "(no modal page opened by the way)")
	await TutorialKit.leave(main)


func test_the_toolbar_buttons_open_the_pages() -> void:
	var main := _main()
	var h = main.hud
	h.jobs_button.pressed.emit()
	eq(h.radio_page(), "jobs", "the Jobs button")
	h.build_button.pressed.emit()
	eq(h.radio_page(), "build", "the Build button")
	h.town_button.pressed.emit()
	eq(h.radio_page(), "map", "the Town Board button (a settlement game)")
	h.news_button.pressed.emit()
	eq(h.radio_page(), "news", "the News button")
	h.news_button.pressed.emit()
	check(not h.radio_open(), "and the same button shuts it")
	check(h.jobs_screen == null and h.build_screen == null and h.scavenge_dialog == null, "(no modal page)")
	h.jobs_button.pressed.emit()
	var lit: Color = h.jobs_button.get_meta("icon").modulate
	eq(lit, Hud.ACCENT, "the button of the page that is up is lit")
	h.build_button.pressed.emit()
	check(h.jobs_button.get_meta("icon").modulate != Hud.ACCENT and h.build_button.get_meta("icon").modulate == Hud.ACCENT, "and moves with the page")
	await TutorialKit.leave(main)


func test_shift_j_n_g_are_the_modal_full_pages() -> void:
	var main := _main()
	var h = main.hud
	_press(main, KEY_J, true)
	check(h.jobs_screen != null, "Shift+J opens the Duty roster")
	check(not h.radio_open(), "and not the panel")
	main.toggle_jobs()
	check(h.jobs_screen == null, "(shut)")
	_press(main, KEY_N, true)
	check(h.build_screen != null, "Shift+N opens the Build screen")
	check(not h.radio_open(), "and not the panel")
	main.toggle_build()
	_press(main, KEY_G, true)
	check(h.town_board_open(), "Shift+G opens the Town Board")
	check(not h.radio_open(), "and not the panel")
	h.scavenge_dialog.close()
	# with the panel up the Shift form is still the modal page
	_press(main, KEY_J)
	check(h.radio_open(), "(the panel is up)")
	_press(main, KEY_J, true)
	check(h.jobs_screen != null, "Shift+J still opens the modal page")
	main.toggle_jobs()
	await TutorialKit.leave(main)


func test_in_the_classic_start_g_is_the_old_dialog() -> void:
	var main := _main(6)
	var h = main.hud
	check(not main.sim.town.on, "(a classic start)")
	_press(main, KEY_G)
	check(h.scavenge_dialog != null and not h.radio_open(), "G opens the old dialog: there is no Map page")
	h.scavenge_dialog.close()
	_press(main, KEY_G, true)
	check(h.scavenge_dialog != null and not h.radio_open(), "and so does Shift+G")
	h.scavenge_dialog.close()
	_press(main, KEY_J)
	eq(h.radio_page(), "jobs", "(J is the panel as ever)")
	await TutorialKit.leave(main)


func test_the_old_yard_and_the_tutorial_keep_the_modal_pages_on_the_plain_keys() -> void:
	# no avatar: the old yard
	var meta := {"difficulty": 1, "seed": 7, "crew": 3}
	var main = TutorialKit.start(meta)
	main.hud.update_hud(main.sim, 1, true, 0)
	check(not main.avatar_mode, "(the old yard)")
	_press(main, KEY_J)
	check(main.hud.jobs_screen != null and not main.hud.radio_open(), "J is the Duty roster")
	main.toggle_jobs()
	_press(main, KEY_N)
	check(main.hud.build_screen != null, "N is the Build screen")
	main.toggle_build()
	_press(main, KEY_T)
	check(not main.hud.radio_open(), "T is the treat order, not the radio")
	await TutorialKit.leave(main)
	# Orientation Day, avatar: its lessons teach the modal pages
	var lesson = TutorialKit.avatar_game(0)
	lesson.coach.queue_free()
	lesson.coach = null
	lesson.hud.update_hud(lesson.sim, 1, true, 0)
	check(lesson.avatar_mode and lesson.tutorial, "(Orientation Day, with the avatar)")
	_press(lesson, KEY_J)
	check(lesson.hud.jobs_screen != null and not lesson.hud.radio_open(), "J is the Duty roster there")
	lesson.toggle_jobs()
	_press(lesson, KEY_T)
	eq(lesson.hud.radio_page(), "news", "T is the News, which is the lesson")
	await TutorialKit.leave(lesson)


func test_esc_closes_the_talk_card_then_the_panel_then_the_selection_then_it_is_the_menu() -> void:
	var main := _main()
	var h = main.hud
	var dez = _person(main, "dez")
	main._try_select({"kind": "person", "ref": dez})
	_press(main, KEY_J)
	check(h.radio_open() and main.selection != null, "(the panel is up and Dez is picked)")
	if h.has_method("show_talk"):
		var ruth = main.sim.avatar.player()
		dez.x = ruth.x + 1.0
		dez.y = ruth.y
		h.show_talk(dez, {})
		check(h.talk_open(), "(and the talk card is up)")
		_press(main, KEY_ESCAPE)
		check(not h.talk_open(), "Esc closes the talk card first")
		check(h.radio_open() and main.selection != null, "and nothing else")
	_press(main, KEY_ESCAPE)
	check(not h.radio_open(), "then the panel")
	check(main.selection != null, "and not the selection")
	check(not main.shell.is_open(), "nor the menu")
	_press(main, KEY_ESCAPE)
	check(main.selection == null, "then the selection")
	check(not main.shell.is_open(), "and not the menu yet")
	_press(main, KEY_ESCAPE)
	check(main.shell.is_open(), "then the pause menu")
	main.shell.close_all()
	await TutorialKit.leave(main)


func test_the_panel_does_not_pause_or_take_the_avatars_hands() -> void:
	var main := _main()
	var h = main.hud
	_press(main, KEY_J)
	check(h.radio_open(), "(the panel is up)")
	eq(main.speed, 1, "the game goes on")
	check(not h.modal_open(), "it is not a modal")
	check(not main.menu_open, "nor a menu")
	check(not main.avatar_hands_off(), "the avatar's hands are free")
	var me = main.sim.avatar.player()
	var x0: float = me.x
	_hold([KEY_D], true)
	_frames(main, 10)
	_hold([KEY_D], false)
	check(me.x > x0 + 0.3, "W A S D still walks (%.2f to %.2f)" % [x0, me.x])
	var t0: float = main.sim.t
	_frames(main, 6)
	check(main.sim.t > t0, "and the rules step")
	await TutorialKit.leave(main)


func test_a_click_in_the_panel_never_fires_the_gun() -> void:
	var main := _main()
	var h = main.hud
	_press(main, KEY_J)
	_frames(main, 4)
	await Kit.settle()
	var tab: Button = h.radio_panel.tab_button("build")
	Kit.click_on(tab)
	eq(h.radio_page(), "build", "a click on a tab goes to the panel")
	check(not main.firing, "and does not reach the yard as a trigger")
	var inside := Kit.rect(h.radio_panel)
	Kit.click(inside.get_center())
	check(not main.firing, "nor does a click anywhere else in the panel")
	await TutorialKit.leave(main)


func test_the_yard_marks_the_plots_while_the_build_page_is_up() -> void:
	var main := _main()
	check(not main.build_open, "no plots marked with the panel shut")
	_press(main, KEY_N)
	check(main.build_open, "the Build page is up: the yard draws the plots' signs")
	_press(main, KEY_J)
	check(not main.build_open, "not on another page")
	_press(main, KEY_N)
	_press(main, KEY_N)
	check(not main.build_open, "nor once it is shut")
	main.toggle_build()
	check(main.build_open, "(and the modal Build screen counts as ever)")
	main.toggle_build()
	await TutorialKit.leave(main)


func test_the_screenshot_flag_opens_a_page() -> void:
	var main := _main()
	main.hud.open_radio("jobs")
	eq(main.hud.radio_page(), "jobs", "(the staging the flag does: open_radio on the HUD)")
	check(main.hud.anchor_rect("panel").size.x > 100.0, "the panel has a place")
	await TutorialKit.leave(main)


func test_leaving_a_page_lets_go_of_what_it_marked_in_the_yard() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	h.open_radio("jobs")
	h.set_jobs_hover({"station": "bench", "post": "", "person": ""})
	check(not h.jobs_hover.is_empty(), "(the Jobs page marks a station)")
	h.open_radio("build")
	eq(h.jobs_hover, {}, "going to another page lets go of it")
	h.set_build_hover({"plot": "workshop"})
	h.close_radio()
	eq(h.build_hover, {}, "and shutting the panel lets go of a plot")
	Kit.free_all(ctx)


func test_the_job_tag_of_a_person_opens_the_jobs_page_on_them() -> void:
	var main := _main()
	var h = main.hud
	var fake := FakePage.new()
	var old = h.radio_panel.page_node("jobs")
	h.radio_panel.scroll.add_child(fake)
	fake.visible = false
	h.radio_panel.pages["jobs"] = fake
	old.free()
	main._try_select({"kind": "person", "ref": _person(main, "dez")})
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	h._on_job_tag_input(click)
	eq(h.radio_page(), "jobs", "the tag opens the radio panel on Jobs")
	eq(fake.focused, ["dez"], "at Dez's row")
	check(h.jobs_screen == null, "and not the modal page")
	await TutorialKit.leave(main)


# ----------------------------------------------------------- the free view --

func test_the_free_view_is_the_window_less_the_panel() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	await Kit.settle()
	eq(h.free_view(), Rect2(Vector2.ZERO, h.size), "shut: the whole window")
	h.open_radio("jobs")
	Kit.update(ctx)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	var panel := Kit.rect(h.radio_panel)
	var fv: Rect2 = h.free_view()
	check(fv.size.x > 200.0 and fv.size.y > 200.0, "up: a view with a size: %s" % str(fv))
	check(fv.end.x <= panel.position.x, "it stops before the panel: %s, %s" % [str(fv), str(panel)])
	check(panel.position.x - fv.end.x < 24.0, "close to it")
	check(Rect2(Vector2.ZERO, h.size).encloses(fv), "inside the window")
	h.close_radio()
	eq(h.free_view(), Rect2(Vector2.ZERO, h.size), "shut again: the whole window")
	Kit.free_all(ctx)


func test_the_camera_keeps_the_avatar_in_the_middle_of_the_free_view() -> void:
	var main := _main(3, 1280, 800)
	var h = main.hud
	var me = main.sim.avatar.player()
	main.zoom_px = 40.0
	me.x = 41.5
	me.y = 30.5
	me.path = []
	main.mouse_screen = main._vp() / 2.0
	main.cam_center = Vector2(me.x, me.y)
	main.cam_hold = 0.0
	_frames(main, 90)
	var shut: Vector2 = main._tile_to_screen(main.view_pos(me))
	check(shut.distance_to(main._vp() / 2.0) < 2.0, "shut: the avatar is in the middle of the window (%s)" % str(shut))
	_press(main, KEY_J)
	await Kit.settle()
	_frames(main, 60)
	await Kit.settle()
	_frames(main, 90)
	var fv: Rect2 = h.free_view()
	check(fv.size.x > 200.0 and fv.size.x < main._vp().x - 200.0, "(the panel is up: %s)" % str(fv))
	var at: Vector2 = main._tile_to_screen(main.view_pos(me))
	check(absf(at.x - fv.get_center().x) < 2.0, "up: the avatar is in the middle of what is left (%.1f, the middle %.1f)" % [at.x, fv.get_center().x])
	check(at.x < Kit.rect(h.radio_panel).position.x - 40.0, "well clear of the panel: %.1f of %.1f" % [at.x, Kit.rect(h.radio_panel).position.x])
	_press(main, KEY_J)
	await Kit.settle()
	_frames(main, 120)
	at = main._tile_to_screen(main.view_pos(me))
	check(at.distance_to(main._vp() / 2.0) < 2.0, "shut again: back in the middle (%s)" % str(at))
	await TutorialKit.leave(main)


func test_at_the_east_wall_the_avatar_is_still_not_under_the_panel() -> void:
	var main := _main(3, 1280, 800)
	var h = main.hud
	var me = main.sim.avatar.player()
	main.zoom_px = 40.0
	me.x = float(main.world.W) - 3.0
	me.y = 30.5
	me.path = []
	main.mouse_screen = main._vp() / 2.0
	main.cam_hold = 0.0
	_press(main, KEY_J)
	await Kit.settle()
	_frames(main, 60)
	await Kit.settle()
	_frames(main, 120)
	var at: Vector2 = main._tile_to_screen(main.view_pos(me))
	var panel := Kit.rect(h.radio_panel)
	check(at.x < panel.position.x - 20.0, "the camera may go past the map's edge for it: the avatar at %.1f, the panel from %.1f" % [at.x, panel.position.x])
	await TutorialKit.leave(main)


# ------------------------------------------------------------------ the calls --

func test_the_oldest_call_stays_in_view_as_a_strip_under_the_tabs() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	var radio = ctx.sim.radio
	var first := _attack_call(radio)
	_fever_call(radio)
	Kit.update(ctx)
	check(h.call_card.visible, "(shut: the HUD's card is up)")
	h.open_radio("jobs")
	Kit.update(ctx)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	var strip = h.radio_panel.call_strip
	check(strip.visible and strip.shown_id == first, "Jobs: the oldest call is a strip under the tabs")
	check(not h.call_card.visible, "and the HUD's card steps aside")
	var panel := Kit.rect(h.radio_panel)
	var s := Kit.rect(strip)
	var tab := Kit.rect(h.radio_panel.tab_button("jobs"))
	check(panel.encloses(s), "the strip is inside the panel: %s in %s" % [str(s), str(panel)])
	check(s.position.y >= tab.end.y - 0.5, "under the tabs: %s, %s" % [str(s), str(tab)])
	var page := Kit.rect(h.radio_panel.page_node("jobs"))
	check(page.size.x <= 0.0 or page.position.y >= s.end.y - 0.5, "and over the page: %s, %s" % [str(s), str(page)])
	eq(strip.view.buttons.keys(), ["hold", "reinforce", "fall_back"], "a button for each way to answer")
	check(strip.view.buttons["hold"].get_theme_font_size("font_size") >= 12, "(12 px or more)")
	near(strip.view.seconds_left(), 10.0, 0.01, "its countdown")
	ctx.sim.clock_min += 15.0
	Kit.update(ctx)
	near(strip.view.seconds_left(), 5.0, 0.01, "counts down")
	for page_id in ["build", "map"]:
		h.open_radio(page_id)
		Kit.update(ctx)
		check(strip.visible and strip.shown_id == first, "%s: the strip is there too" % page_id)
	strip.view.buttons["reinforce"].pressed.emit()
	eq(String(RadioKit.entry_of(radio, first).answered), "reinforce", "answering through the strip answers the call")
	Kit.update(ctx)
	check(strip.shown_id != first, "and the next call comes up (or the result shows)")
	Kit.free_all(ctx)


func test_on_the_news_page_the_pages_own_list_has_the_calls_and_no_strip() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	var id := _attack_call(ctx.sim.radio)
	h.open_radio("news")
	Kit.update(ctx)
	await Kit.settle()
	check(not h.radio_panel.call_strip.visible, "no strip over the News (the list has the call)")
	eq(h.news_panel.call_ids(), [id], "the News page has it, with its buttons")
	check(not h.call_card.visible, "and the card of the HUD is not shown twice")
	h.close_radio()
	Kit.update(ctx)
	check(h.call_card.visible, "shut: the card is back")
	Kit.free_all(ctx)


func test_the_news_tab_wears_a_dot_for_what_is_unread_and_a_bang_for_a_call() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	var p = h.radio_panel
	eq(p.tab_marks("news"), {"dot": false, "bang": false}, "nothing at first")
	ctx.sim.radio.log_news("story", "Supply drop")
	h.open_radio("jobs")
	Kit.update(ctx)
	eq(p.tab_marks("news"), {"dot": true, "bang": false}, "a line unread: the dot, while another page is up")
	check(h.news_dot.visible, "(and the toolbar's dot)")
	h.open_radio("news")
	Kit.update(ctx)
	eq(p.tab_marks("news"), {"dot": false, "bang": false}, "on News it is being read")
	h.open_radio("jobs")
	Kit.update(ctx)
	eq(p.tab_marks("news"), {"dot": false, "bang": false}, "and read when it is left")
	_attack_call(ctx.sim.radio)
	Kit.update(ctx)
	eq(p.tab_marks("news"), {"dot": true, "bang": true}, "a call that waits: the bang (and what it says is unread)")
	check(p.tab_button("news").tooltip_text.to_lower().contains("call waits"), "the tooltip says why: %s" % p.tab_button("news").tooltip_text)
	check(p.tab_marks("jobs") == {"dot": false, "bang": false}, "the other tabs wear none")
	h.close_radio()
	Kit.update(ctx)
	eq(p.tab_marks("news").bang, true, "shut: the tab still knows (the toolbar and the card say it)")
	Kit.free_all(ctx)


func test_the_news_is_read_when_the_page_is_left_or_the_panel_shut() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	ctx.sim.radio.log_news("story", "A voice on the radio")
	ctx.sim.radio.log_news("recruit", "Hector has joined the crew")
	h.open_radio("news")
	Kit.update(ctx)
	eq(h.news_panel.unread_ids().size(), 2, "open on News: the lines show as unread")
	h.open_radio("build")
	eq(h.news_panel.unread_ids(), [], "going to another page reads them")
	ctx.sim.radio.log_news("alarm", "Call to arms")
	h.open_radio("news")
	h.close_radio()
	eq(h.news_panel.unread_ids(), [], "shutting it from News reads them")
	Kit.free_all(ctx)


func test_the_hint_and_the_help_give_way_to_the_panel() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	h.help.visible = true
	h.open_radio("jobs")
	check(not h.help.visible, "opening the panel puts the controls help away")
	h.help_button.pressed.emit()
	check(h.help.visible and not h.radio_open(), "and the help takes its place when asked for")
	Kit.free_all(ctx)


func test_the_news_has_kinds_for_errands_and_buildings() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	eq(RadioKit.kind_name("errand"), "Errand", "an errand is called so")
	eq(RadioKit.kind_name("build"), "Built", "and a building that went up is Built")
	eq(RadioKit.kind_color(h, "errand"), Hud.INFO, "the errand's word is blue")
	eq(RadioKit.kind_color(h, "build"), Hud.OK, "the building's green")
	ctx.sim.radio.log_news("errand", "Dez and Ana set off for the pharmacy", "They will find less without you.")
	ctx.sim.radio.log_news("build", "The workshop is built", "")
	h.open_radio("news")
	Kit.update(ctx)
	eq(h.news_panel.row_kinds(), ["build", "errand"], "both are lines of the log")
	var all := _texts_of(h.news_panel)
	check(all.contains("ERRAND") and all.contains("BUILT") and all.contains("They will find less without you."), "with their words: %s" % all)
	Kit.free_all(ctx)


func test_the_toast_keeps_clear_of_the_panel_and_the_dock_when_there_is_room_between() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1], "jobs")
		var h = ctx.hud
		h.toast("Dez: bleeding, can't come", "warn")
		await Kit.settle()
		var toast := Kit.rect(h.toast_panel)
		var panel := Kit.rect(h.radio_panel)
		var dock := Kit.rect(h.inspect).merge(Kit.rect(h.radio_box))
		var win := Rect2(0, 0, size[0], size[1])
		check(win.encloses(toast.grow(-0.5)), "%s: the toast is in the window: %s" % [str(size), str(toast)])
		var low := dock.end.x + 8.0 if dock.end.y > toast.position.y else 0.0
		var band := panel.position.x - 8.0 - low
		if toast.size.x <= band:
			check(toast.end.x <= panel.position.x - 7.5, "%s: the toast ends before the panel: %s, %s" % [str(size), str(toast), str(panel)])
			check(toast.position.x >= low - 0.5, "%s: and starts after the dock: %s, %s" % [str(size), str(toast), str(dock)])
		Kit.free_all(ctx)


# ------------------------------------------------------------------ the layout --

## An avatar game with everything that shares the screen with the panel: alerts, a call, a log, the fields legend, a forecast, and a contact
## picked with a refusal showing.
func _busy(width: int, height: int, page: String) -> Dictionary:
	var ctx := _ctx(width, height)
	var h = ctx.hud
	var radio = ctx.sim.radio
	Kit.person(ctx, "dez").bleeding = 3.0
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Dez", null, 600.0)
	ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 600.0)
	ctx.sim.alert("a3", "info", "The bell has rung", "Everyone is heading to their posts", null, 600.0)
	radio.log_news("story", "A voice on the radio", "A call on the radio")
	radio.log_news("recruit", "Hector has joined the crew", "Medic")
	radio.log_news("attack", "East wall under attack", "3 of the dead at it")
	_attack_call(radio)
	_fever_call(radio)
	h.set_fields(true)
	ctx.sim.tactics.told = Kit.forecast({"brutes": 2, "heading": "north and west"})
	Kit.select(ctx, Kit.person(ctx, "dez"))
	Kit.update(ctx)
	h.radio_verbs.buttons["come"].pressed.emit()
	for i in 2:
		Kit.update(ctx)
		await Kit.settle()
	# (what already overlapped before the panel was opened is not the panel's: the toolbar of a settlement game at 700 px runs 2 px into the
	# selection's board)
	ctx["before"] = Kit.overlaps(_rects(ctx))
	if page != "":
		h.open_radio(page)
	for i in 2:
		Kit.update(ctx)
		await Kit.settle()
	return ctx


func _rects(ctx: Dictionary) -> Dictionary:
	var h = ctx.hud
	return {
		"stores": Kit.rect(h.res_panel), "legend": Kit.rect(h.fields_legend), "cards": Kit.rect(h.bar), "clock": Kit.rect(h.clock),
		"ammo": Kit.rect(h.ammo_panel), "alerts": Kit.rect(h.alerts_box), "call": Kit.rect(h.call_card), "selection": Kit.rect(h.inspect),
		"radio": Kit.rect(h.radio_box), "panel": Kit.rect(h.radio_panel), "speed": Kit.rect(h.speed_panel),
	}


func test_the_panel_fits_and_touches_nothing_at_the_five_sizes_on_every_page() -> void:
	for size in SIZES:
		for page in ["jobs", "build", "map", "news"]:
			var ctx: Dictionary = await _busy(size[0], size[1], page)
			var h = ctx.hud
			var where := "%d x %d, %s" % [size[0], size[1], page]
			var rects := _rects(ctx)
			var panel: Rect2 = rects.panel
			check(panel.size.x >= 200.0 and panel.size.y >= 150.0, "%s: the panel has a size: %s" % [where, str(panel)])
			check(panel.size.x <= RadioPanel.WIDTH + 0.5, "%s: and is no wider than its form: %s" % [where, str(panel)])
			if size[0] < 980:
				check(panel.size.x <= RadioPanel.WIDTH_COMPACT + 0.5, "%s: the narrow form in a narrow window: %s" % [where, str(panel)])
			var now: Array = Kit.overlaps(rects)
			var added: Array = []
			for line in now:
				if not ctx.before.has(line):
					added.append(line)
			eq(added, [], where)
			for line in now:
				check(String(line).begins_with("selection overlaps speed") or String(line).begins_with("speed overlaps selection") or not String(line).contains("panel"), "%s: the panel overlaps nothing: %s" % [where, line])
			var win := Rect2(0, 0, size[0], size[1])
			for name in rects:
				var r: Rect2 = rects[name]
				if r.size.x > 1.0 and r.size.y > 1.0:
					check(win.encloses(r.grow(-0.5)), "%s: %s is in the window: %s" % [where, name, str(r)])
			check(panel.end.y <= rects.speed.position.y + 0.5, "%s: it ends over the toolbar: %s, %s" % [where, str(panel), str(rects.speed)])
			check(panel.position.y >= rects.ammo.end.y - 0.5 and panel.position.y >= rects.clock.end.y - 0.5, "%s: it starts under the clock and the gun's readout" % where)
			eq(rects.call, Rect2(), "%s: the HUD's call card steps aside" % where)
			var room: float = rects.speed.position.y - 8.0 - rects.ammo.end.y
			if room >= RadioPanel.MIN_H + 30.0:
				check(panel.size.y >= RadioPanel.MIN_H - 1.0, "%s: at least %d px tall when the room allows: %s" % [where, int(RadioPanel.MIN_H), str(panel)])
			var free: Rect2 = h.free_view()
			check(free.end.x <= panel.position.x + 0.5 and free.size.x > 200.0, "%s: the free view is left of the panel: %s" % [where, str(free)])
			Kit.free_all(ctx)


func test_the_panel_has_no_small_text_and_every_word_of_it_reads() -> void:
	# (nothing of the panel or its pages is under 12 px; the words of the shell, its tabs, its strip and the News read at 4.5:1: the other
	# pages' colours are their builders' tests)
	var tt := TextTests.new()
	for size in [[1280, 800], [700, 560]]:
		for page in ["jobs", "build", "map", "news"]:
			var ctx: Dictionary = await _busy(size[0], size[1], page)
			var h = ctx.hud
			var node = h.radio_panel.page_node(page)
			var where := "%d x %d, %s" % [size[0], size[1], page]
			if not _is_stub(node):
				eq(tt._small_text(node), [], "%s: nothing under 12 px in the page" % where)
			var mine: Array = [h.radio_panel.call_strip, h.radio_panel.close_button]
			for t in h.radio_panel.tabs.values():
				mine.append(t)
			if page == "news":
				mine.append(node)
			for part in mine:
				eq(tt._small_text(part), [], "%s: nothing under 12 px in %s" % [where, part.name])
				eq(tt._hard_to_read(part, Color.WHITE), [], "%s: every word in %s reads at 4.5:1" % [where, part.name])
			Kit.free_all(ctx)


func test_a_resize_to_a_narrow_window_makes_the_narrow_panel_and_back() -> void:
	var ctx: Dictionary = await _busy(1280, 800, "jobs")
	var h = ctx.hud
	var wide := Kit.rect(h.radio_panel)
	check(wide.size.x >= RadioPanel.WIDTH - 0.5 and not h.radio_panel.is_compact(), "wide: the whole width: %s" % str(wide))
	Kit.resize(ctx, 700, 700)
	for i in 2:
		Kit.update(ctx)
		await Kit.settle()
	var narrow := Kit.rect(h.radio_panel)
	check(h.radio_panel.is_compact() and narrow.size.x <= RadioPanel.WIDTH_COMPACT + 0.5, "narrow: %s" % str(narrow))
	check(Rect2(0, 0, 700, 700).encloses(narrow.grow(-0.5)), "and in the window")
	Kit.resize(ctx, 1280, 800)
	for i in 2:
		Kit.update(ctx)
		await Kit.settle()
	check(Kit.rect(h.radio_panel).size.x >= RadioPanel.WIDTH - 0.5, "and wide again")
	Kit.free_all(ctx)


func test_the_panel_is_as_tall_as_its_page_wants_and_scrolls_past_the_room() -> void:
	var ctx := _ctx()
	var bare := _bare(ctx)
	var panel = bare.panel
	var fakes: Dictionary = bare.fakes
	panel.position = Vector2(300, 60)
	panel.open("jobs")
	panel.fit(600.0)
	panel.reset_size()
	await Kit.settle()
	check(absf(panel.size.y - RadioPanel.MIN_H) < 1.0, "a short page: the least height (%.0f)" % panel.size.y)
	fakes.jobs.custom_minimum_size.y = 900.0
	panel.fit(600.0)
	panel.reset_size()
	await Kit.settle()
	check(panel.size.y <= 600.5 and panel.size.y >= 590.0, "a tall page: the room there is, no more (%.0f)" % panel.size.y)
	check(panel.scroll.get_v_scroll_bar().max_value > panel.scroll.get_v_scroll_bar().page, "and it scrolls")
	panel.fit(400.0)
	panel.reset_size()
	await Kit.settle()
	check(panel.size.y <= 400.5, "a smaller room: smaller (%.0f)" % panel.size.y)
	fakes.jobs.custom_minimum_size.y = 350.0
	panel.fit(600.0)
	panel.reset_size()
	await Kit.settle()
	var chrome: float = panel.size.y - panel.scroll.size.y
	check(absf(panel.scroll.size.y - 350.0) < 1.0 and panel.size.y > RadioPanel.MIN_H, "a page of 350 px: the panel is that and its chrome (%.0f + %.0f)" % [panel.scroll.size.y, chrome])
	check(absf(panel.size.x - RadioPanel.WIDTH) < 1.0, "the wide form: %.0f" % panel.size.x)
	panel.set_compact(true)
	panel.fit(600.0, 1000.0)
	panel.reset_size()
	await Kit.settle()
	check(absf(panel.size.x - RadioPanel.WIDTH_COMPACT) < 1.0, "the narrow form: %.0f" % panel.size.x)
	panel.set_compact(false)
	panel.fit(600.0, 340.0)
	panel.reset_size()
	await Kit.settle()
	check(panel.size.x <= 340.5 and panel.size.x >= 316.0, "and never wider than the room: %.0f" % panel.size.x)
	panel.free()
	Kit.free_all(ctx)


# --------------------------------------------------------------------- anchors --

func test_the_panel_has_anchors_for_the_coach_and_the_tests() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	eq(h.anchor_rect("panel"), Rect2(), "shut: no panel")
	eq(h.anchor_rect("panel.page"), Rect2(), "and no page")
	h.open_radio("build")
	Kit.update(ctx)
	await Kit.settle()
	check(h.anchor_rect("panel").size.x > 100.0, "up: the panel")
	check(h.anchor_rect("panel.page").size.x > 50.0, "its page")
	for page in ["jobs", "build", "map", "news"]:
		check(h.anchor_rect("panel.tab:%s" % page).size.x > 20.0, "the %s tab" % page)
	check(h.anchor_rect("panel").encloses(h.anchor_rect("panel.page")), "the page is inside the panel")
	eq(h.anchor_rect("news.panel"), Rect2(), "(the news page is not what is up)")
	h.open_radio("news")
	Kit.update(ctx)
	await Kit.settle()
	check(h.anchor_rect("news.panel").size.x > 50.0, "(and when it is, the old name for it finds it)")
	Kit.free_all(ctx)
