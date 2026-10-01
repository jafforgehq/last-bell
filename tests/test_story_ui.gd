extends "res://tests/case.gd"
## The storyteller's cards in the view: the radio card (a paper modal: the speaker, the words, the ways
## to answer with their risk, keys 1 to 3, the rules held still while it is up and the speed put back
## after) and the dawn assembly (a paper card that does not pause anything: 15 seconds, a click or a
## key puts it away, Esc too, the alert brings it back). Both at four window widths, with no overlap
## and with text that reads.

const Kit := preload("res://tests/hud_kit.gd")
const HudText := preload("res://tests/test_hud_text.gd")
const Helpers := preload("res://tests/helpers.gd")
const MenuFakes := preload("res://tests/menu_fakes.gd")
const RadioCard := preload("res://scripts/ui/radio_card.gd")
const DawnCard := preload("res://scripts/ui/dawn_card.gd")
const StoryUi := preload("res://scripts/ui/story_ui.gd")

const SIZES := [[700, 560], [980, 700], [1280, 800], [1920, 1080]]


# ----------------------------------------------------------------- helpers --

## A HUD over a game at midday of day 8, the storyteller on, the radio hour held.
func _ctx(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := Kit.build(width, height)
	var sim = ctx.sim
	sim.storyteller.enabled = true
	sim.day = 8
	sim.minutes = 12.0 * 60.0
	sim.clock_min = 7.0 * 1440.0 + 300.0
	sim.phase = "day"
	sim.storyteller.radio_day = 8
	sim.events.clear()
	Kit.update(ctx, 1)
	return ctx


## The card up, and the page built over the HUD (not through the controller).
func _page(ctx: Dictionary, id: String) -> RadioCard:
	var forced: bool = ctx.sim.storyteller.force(id)
	check(forced, "the card %s is put up" % id)
	var card := RadioCard.new()
	ctx.hud.add_child(card)
	card.setup(ctx.hud, ctx.sim)
	return card


func _key(code: Key, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.shift_pressed = shift
	return ev


func _texts(node: Node) -> Array:
	return Kit.texts(node)


## Every visible label, button and picture under `root`.
func _leaves(root: Node, out: Array = []) -> Array:
	if root is Control and root.is_visible_in_tree() and (root is Label or root is Button or root is TextureRect):
		out.append(root)
	for c in root.get_children():
		_leaves(c, out)
	return out


## The pairs of leaves (neither inside the other) that overlap.
func _overlaps(root: Node) -> Array:
	var leaves := _leaves(root)
	var out: Array = []
	for i in leaves.size():
		for j in range(i + 1, leaves.size()):
			var a: Control = leaves[i]
			var b: Control = leaves[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var ra := _visible_rect(a)
			var rb := _visible_rect(b)
			if ra.size == Vector2.ZERO or rb.size == Vector2.ZERO:
				continue
			var inter := ra.intersection(rb)
			if inter.size.x > 1.0 and inter.size.y > 1.0:
				out.append("%s overlaps %s" % [_name_of(a), _name_of(b)])
	return out


## A control's rectangle as far as it is seen: what is scrolled out of a scroll box is not.
func _visible_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			r = r.intersection(p.get_global_rect())
		p = p.get_parent()
	return r


func _name_of(c: Control) -> String:
	if c is Label:
		return "'%s'" % String(c.text).left(24)
	if c is Button:
		return "button '%s'" % String(c.text).left(24)
	return c.get_class()


# --------------------------------------------------------------- radio card --

func test_the_radio_card_shows_the_speaker_the_words_and_each_way_to_answer() -> void:
	var ctx := _ctx()
	var card := _page(ctx, "radio_trade")
	await Kit.settle()
	var up: Dictionary = ctx.sim.storyteller.pending()
	var all := _texts(card)
	check(all.has("Trade on the radio"), "the title: %s" % str(all))
	check(all.has(up.text), "what came in")
	check(all.has("Ruth Okafor"), "who is at the radio")
	eq(card.choice_buttons.size(), 2, "a button for each way to answer")
	eq(card.choice_buttons[0].text, "Make the trade", "the first")
	eq(card.choice_buttons[1].text, "Not today", "the second")
	check(all.has("Costs 5 medicine and brings 60 ammo."), "the cost is written under it")
	check(all.has("Nothing changes."), "so is the other")
	check(all.has("1") and all.has("2"), "with their keys")
	check(card.later_button != null and card.later_button.text == "Decide later", "and a way to put it off")
	check(String(card.later_button.tooltip_text).contains("Esc"), "which says its key")
	var note := ""
	for t in all:
		if String(t).begins_with("If nobody answers"):
			note = String(t)
	eq(note, "If nobody answers by 14:00: Not today.", "and what happens if nobody does")
	var head_icon: TextureRect = null
	for n in _leaves(card):
		if n is TextureRect and n.texture != null and n.custom_minimum_size.x == 30.0:
			head_icon = n
	check(head_icon != null, "the little radio is in the head")
	card.put_away()
	Kit.free_all(ctx)


func test_a_card_with_no_choice_has_one_button_and_shows_what_it_did() -> void:
	var ctx := _ctx()
	var card := _page(ctx, "heavy_rain")
	await Kit.settle()
	var all := _texts(card)
	eq(card.choice_buttons.size(), 0, "no choices")
	check(card.done_button != null and card.done_button.text == "Understood", "one button: Understood")
	check(card.later_button == null, "and nothing to put off")
	check(all.has("Water +20"), "what it did, exactly: %s" % str(all))
	check(all.has("The barrels are full."), "and how it went")
	card.done_button.pressed.emit()
	check(not card.is_open(), "it is read and gone")
	check(ctx.sim.storyteller.pending().is_empty(), "and the storyteller has put it away")
	Kit.free_all(ctx)


func test_a_choice_that_cannot_be_made_is_greyed_with_its_reason() -> void:
	var ctx := _ctx()
	ctx.sim.stock.meds = 7.0
	var card := _page(ctx, "radio_trade")
	ctx.sim.stock.meds = 3.0
	card.put_away()
	var again := RadioCard.new()
	ctx.hud.add_child(again)
	again.setup(ctx.hud, ctx.sim)
	await Kit.settle()
	check(again.choice_buttons[0].disabled, "with 3 medicine the trade is off")
	check(not again.choice_buttons[1].disabled, "the other is on")
	check(_texts(again).has("Needs 5 medicine"), "and the page says why")
	again._input(_key(KEY_1))
	check(again.is_open(), "its key does nothing")
	check(ctx.sim.storyteller.pending().get("id", "") == "radio_trade", "and the card is still waiting")
	again._input(_key(KEY_2))
	check(not again.is_open(), "the other answers it")
	Kit.free_all(ctx)


func test_the_keys_answer_and_put_off_and_move_between_the_answers() -> void:
	var ctx := _ctx()
	var card := _page(ctx, "stranger")
	await Kit.settle()
	var meds: float = ctx.sim.stock.meds
	var ammo: float = ctx.sim.stock.ammo
	card._input(_key(KEY_2))
	check(not card.is_open(), "2 answers with the second choice")
	near(float(ctx.sim.stock.ammo), ammo - 15.0, 0.001, "which is the trade: 15 ammo go")
	near(float(ctx.sim.stock.meds), meds + 3.0, 0.001, "3 medicine come")
	# a number past the choices does nothing
	var ctx2 := _ctx()
	var card2 := _page(ctx2, "radio_trade")
	await Kit.settle()
	card2._input(_key(KEY_3))
	check(card2.is_open() and not ctx2.sim.storyteller.pending().is_empty(), "3 has no answer on a card with two")
	# Tab goes round the answers, Enter takes the one that has the keyboard
	card2._input(_key(KEY_TAB))
	eq(card2.get_viewport().gui_get_focus_owner(), card2.choice_buttons[0], "Tab goes to the first answer")
	card2._input(_key(KEY_TAB))
	eq(card2.get_viewport().gui_get_focus_owner(), card2.choice_buttons[1], "then the second")
	card2._input(_key(KEY_TAB))
	eq(card2.get_viewport().gui_get_focus_owner(), card2.later_button, "then Decide later")
	card2._input(_key(KEY_TAB))
	eq(card2.get_viewport().gui_get_focus_owner(), card2.choice_buttons[0], "and round again")
	card2._input(_key(KEY_TAB, true))
	eq(card2.get_viewport().gui_get_focus_owner(), card2.later_button, "Shift+Tab goes back")
	card2.choice_buttons[1].grab_focus()
	var ammo2: float = ctx2.sim.stock.ammo
	card2._input(_key(KEY_ENTER))
	check(not card2.is_open(), "Enter takes the answer that has the keyboard")
	near(float(ctx2.sim.stock.ammo), ammo2, 0.001, "Not today: nothing changed")
	Kit.free_all(ctx)
	Kit.free_all(ctx2)


func test_escape_puts_it_off_and_the_card_stays_pending() -> void:
	var ctx := _ctx()
	var card := _page(ctx, "stranger")
	await Kit.settle()
	var closed: Array = []
	card.closed.connect(func(answered): closed.append(answered))
	card._input(_key(KEY_ESCAPE))
	check(not card.is_open(), "Esc puts the page away")
	eq(closed, [false], "and says it was not answered")
	eq(ctx.sim.storyteller.pending().get("id", ""), "stranger", "the card is still pending")
	check(ctx.sim.alerts.has("story"), "with its alert up, to open it again")
	Kit.free_all(ctx)


func test_escape_on_a_card_that_has_happened_reads_it() -> void:
	var ctx := _ctx()
	var card := _page(ctx, "quiet_day")
	await Kit.settle()
	var closed: Array = []
	card.closed.connect(func(answered): closed.append(answered))
	card._input(_key(KEY_ESCAPE))
	eq(closed, [true], "it is simply read")
	check(ctx.sim.storyteller.pending().is_empty(), "and put away")
	Kit.free_all(ctx)


func test_enter_on_a_card_with_no_choice_reads_it_and_one_does_too() -> void:
	var ctx := _ctx()
	var card := _page(ctx, "fog")
	await Kit.settle()
	card._input(_key(KEY_ENTER))
	check(not card.is_open(), "Enter reads it")
	var ctx2 := _ctx()
	var card2 := _page(ctx2, "mould")
	await Kit.settle()
	card2._input(_key(KEY_1))
	check(not card2.is_open(), "so does 1")
	Kit.free_all(ctx)
	Kit.free_all(ctx2)


func test_the_page_closes_when_the_card_is_settled_from_outside() -> void:
	var ctx := _ctx()
	var card := _page(ctx, "stranger")
	await Kit.settle()
	ctx.sim.storyteller.choose(2)
	card._process(0.1)
	check(not card.is_open(), "a page for a card that is gone goes too")
	Kit.free_all(ctx)


func test_the_radio_page_at_four_widths_has_no_overlap_and_text_that_reads() -> void:
	var reader := HudText.new()
	for size in SIZES:
		for id in ["stranger", "radio_trade", "heavy_rain", "supply_drop"]:
			var ctx := _ctx(size[0], size[1])
			var card := _page(ctx, id)
			await Kit.settle()
			await Kit.settle()
			var label := "%s at %dx%d" % [id, size[0], size[1]]
			var view := Rect2(Vector2.ZERO, Vector2(size[0], size[1]))
			var rect: Rect2 = card.panel.get_global_rect()
			check(view.encloses(rect), "%s: the page is inside the window: %s" % [label, str(rect)])
			check(rect.size.x >= 280.0, "%s: and is wide enough to read: %.0f" % [label, rect.size.x])
			var clashes := _overlaps(card)
			check(clashes.is_empty(), "%s: nothing overlaps: %s" % [label, str(clashes)])
			var faint: Array = reader._hard_to_read(card, Color.WHITE)
			check(faint.is_empty(), "%s: all the text reads at 4.5:1: %s" % [label, str(faint)])
			var foot_button: Button = card.done_button if card.done_button != null else card.later_button
			check(view.encloses(foot_button.get_global_rect()), "%s: the foot's button is on screen: %s" % [label, str(foot_button.get_global_rect())])
			# a short window scrolls the body; a tall one does not need to
			var bar: ScrollBar = card.scroll.get_v_scroll_bar()
			var scrolls: bool = bar.max_value > bar.page + 1.0
			if size[1] >= 800:
				check(not scrolls, "%s: nothing needs scrolling" % label)
			card.put_away()
			Kit.free_all(ctx)


func test_a_very_short_window_scrolls_the_body_and_keeps_the_buttons() -> void:
	var ctx := _ctx(700, 420)
	var card := _page(ctx, "stranger")
	await Kit.settle()
	await Kit.settle()
	var view := Rect2(Vector2.ZERO, Vector2(700, 420))
	check(view.encloses(card.panel.get_global_rect()), "the page fits a 700x420 window: %s" % str(card.panel.get_global_rect()))
	var bar: ScrollBar = card.scroll.get_v_scroll_bar()
	check(bar.max_value > bar.page + 1.0, "the body scrolls")
	check(view.encloses(card.later_button.get_global_rect()), "and Decide later is still on screen")
	card.put_away()
	Kit.free_all(ctx)


# --------------------------------------------------------------- the controller --

func _controller(ctx: Dictionary) -> StoryUi:
	var ui := StoryUi.new()
	ctx.hud.add_child(ui)
	ui.setup(ctx.hud, ctx.sim)
	return ui


func test_the_radio_card_holds_the_game_still_and_gives_the_speed_back() -> void:
	var ctx := _ctx()
	var ui := _controller(ctx)
	Kit.update(ctx, 2)
	check(ctx.sim.storyteller.force("stranger"), "a card is up")
	ui.on_story_card()
	await Kit.settle()
	check(ui.radio != null and ui.radio.is_open(), "the radio card is open")
	eq(ctx.speeds, [0], "the rules were paused")
	ui.radio._input(_key(KEY_2))
	check(ui.radio == null, "answered, the page is gone")
	eq(ctx.speeds, [0, 2], "and the speed they had is back")
	Kit.free_all(ctx)


func test_the_cards_make_the_menu_sounds_when_they_come_and_go() -> void:
	var ctx := _ctx()
	var ui := _controller(ctx)
	var heard: Array = []
	ui.ui_sound = func(sound_name, level): heard.append([sound_name, level])
	ctx.sim.storyteller.force("stranger")
	ui.on_story_card()
	await Kit.settle()
	eq(heard, [["ui_open", 1.0]], "the page opens with the opening sound")
	ui.radio._input(_key(KEY_2))
	eq(heard[heard.size() - 1], ["ui_confirm", 1.0], "an answer confirms")
	ctx.sim.storyteller.force("fog")
	ui.on_story_card()
	await Kit.settle()
	ui.radio._input(_key(KEY_ESCAPE))
	eq(heard[heard.size() - 1], ["ui_confirm", 1.0], "a card that is only read confirms too")
	ctx.sim.storyteller.force("stranger")
	ui.on_story_card()
	await Kit.settle()
	ui.radio._input(_key(KEY_ESCAPE))
	eq(heard[heard.size() - 1], ["ui_close", 1.0], "a card put off closes")
	Kit.free_all(ctx)


func test_a_game_that_was_paused_stays_paused_after_the_card() -> void:
	var ctx := _ctx()
	var ui := _controller(ctx)
	Kit.update(ctx, 0)
	ctx.sim.storyteller.force("stranger")
	ui.on_story_card()
	await Kit.settle()
	ui.radio._input(_key(KEY_2))
	eq(ctx.speeds, [], "nothing was changed: the game was paused already")
	Kit.free_all(ctx)


func test_putting_it_off_gives_the_speed_back_and_the_alert_brings_the_card_again() -> void:
	var ctx := _ctx()
	var ui := _controller(ctx)
	Kit.update(ctx, 3)
	ctx.sim.storyteller.force("stranger")
	ui.on_story_card()
	await Kit.settle()
	ui.radio._input(_key(KEY_ESCAPE))
	eq(ctx.speeds, [0, 3], "the rules go on at their speed")
	check(ui.radio == null, "the page is away")
	check(ui.on_alert("story"), "the alert is the radio's")
	await Kit.settle()
	check(ui.radio != null and ui.radio.is_open(), "and it opens the card again")
	eq(ctx.speeds, [0, 3, 0], "pausing once more")
	ui.radio._input(_key(KEY_1))
	eq(ctx.speeds[ctx.speeds.size() - 1], 3, "and answering gives the speed back")
	check(not ui.on_alert("story-stranger"), "an alert of an outcome is no business of the cards")
	Kit.free_all(ctx)


func test_a_card_waits_while_another_dialog_is_open_and_then_opens() -> void:
	var ctx := _ctx()
	var ui := _controller(ctx)
	var state := {"busy": true}
	ui.blocked = func(): return state.busy
	Kit.update(ctx, 1)
	ctx.sim.storyteller.force("stranger")
	ui.on_story_card()
	check(ui.radio == null, "a menu has the screen: the card waits")
	eq(ctx.speeds, [], "and the game is not touched")
	state.busy = false
	ui._process(0.1)
	await Kit.settle()
	check(ui.radio != null, "the menu is gone: the card opens")
	ui.radio.put_away()
	Kit.free_all(ctx)


func test_a_card_left_pending_by_a_save_is_opened_at_the_start() -> void:
	var ctx := _ctx()
	ctx.sim.storyteller.force("stranger")
	var ui := _controller(ctx)
	ui._process(0.1)
	await Kit.settle()
	check(ui.radio != null and ui.radio.is_open(), "the card that was waiting is up again")
	ui.radio.put_away()
	Kit.free_all(ctx)


func test_the_end_of_the_run_takes_the_page_away() -> void:
	var ctx := _ctx()
	var ui := _controller(ctx)
	Kit.update(ctx, 1)
	ctx.sim.storyteller.force("stranger")
	ui.on_story_card()
	await Kit.settle()
	ctx.sim.over = "defeat"
	ui._process(0.1)
	check(ui.radio == null, "the page is gone with the run")
	Kit.free_all(ctx)


# ----------------------------------------------------------------- dawn card --

func _report() -> Dictionary:
	return {
		"day": 8, "night": 7, "kills": 41, "mvp": {"who": "Walt", "kills": 12}, "wall_lost": 310, "wall_mended": 180, "breaches": 1,
		"lost": [{"who": "Ana", "epitaph": "She would have wanted the lamp left on.", "how": "died"}],
		"hurt": ["Marcus"], "skill_ups": [{"who": "Dez", "skill": "Building", "value": 10}],
		"events": ["Heavy rain: The barrels are full."], "mood": "Mostly steady; Marcus is shaken.", "alive": 5,
	}


func _dawn(ctx: Dictionary, report: Dictionary = {}) -> DawnCard:
	var card := DawnCard.new()
	ctx.hud.add_child(card)
	card.setup(ctx.hud, report if not report.is_empty() else _report())
	return card


func test_the_dawn_card_tells_the_night_in_ruled_lines() -> void:
	var ctx := _ctx()
	var card := _dawn(ctx)
	await Kit.settle()
	var all := _texts(card)
	check(all.has("Night 7 is over"), "the night: %s" % str(all))
	check(all.has("41 put down, most by Walt (12)"), "the kills and who led")
	check(all.has("Wall: 310 health lost, 180 mended (a breach)"), "the wall")
	check(all.has("Ana is gone. “She would have wanted the lamp left on.”"), "who was lost, and what is said of them")
	check(all.has("Hurt in the night: Marcus"), "who was hurt")
	check(all.has("Learned: Dez Building 10"), "what was learned")
	check(all.has("Heavy rain: The barrels are full."), "the day's news")
	check(all.has("Mostly steady; Marcus is shaken."), "the mood")
	eq(card.row_kinds, ["kills", "wall", "lost", "hurt", "skills", "event", "mood", "tip"], "the rows, in order")
	eq(ctx.speeds, [], "and it does not touch the speed")
	card.close()
	Kit.free_all(ctx)


func test_a_quiet_night_is_told_quietly() -> void:
	var ctx := _ctx()
	var card := _dawn(ctx, {"day": 3, "night": 2, "kills": 0, "mvp": {}, "wall_lost": 0, "wall_mended": 0, "breaches": 0, "lost": [], "hurt": [], "skill_ups": [], "events": [], "mood": "Everyone is steady.", "alive": 6})
	await Kit.settle()
	var all := _texts(card)
	check(all.has("Nobody put down: a quiet night"), "no kills: %s" % str(all))
	check(all.has("The wall held: nothing lost"), "the wall held")
	eq(card.row_kinds, ["kills", "wall", "mood", "tip"], "and only what there is to say")
	card.close()
	Kit.free_all(ctx)


func test_the_dawn_card_stays_fifteen_seconds_and_fades_out() -> void:
	var ctx := _ctx()
	var card := _dawn(ctx)
	await Kit.settle()
	card._process(14.0)
	check(card.is_open(), "still up at 14 seconds")
	check(card.modulate.a > 0.99, "and not faded")
	card._process(0.7)
	check(card.is_open() and card.modulate.a < 0.9, "fading at 14.7")
	card._process(0.4)
	check(not card.is_open(), "gone after 15")
	Kit.free_all(ctx)


func test_a_click_or_any_key_puts_the_dawn_card_away() -> void:
	var ctx := _ctx()
	var card := _dawn(ctx)
	await Kit.settle()
	card._input(_key(KEY_W))
	check(not card.is_open(), "any key puts it away")
	var other := _dawn(ctx)
	await Kit.settle()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	other._on_panel_input(click)
	check(not other.is_open(), "so does a click on it")
	var third := _dawn(ctx)
	await Kit.settle()
	third._input(_key(KEY_ESCAPE))
	check(not third.is_open(), "and Esc")
	Kit.free_all(ctx)


func test_the_dawn_card_does_not_block_the_mouse_outside_itself() -> void:
	var ctx := _ctx()
	var card := _dawn(ctx)
	await Kit.settle()
	eq(card.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the layer lets every click through")
	eq(card.panel.mouse_filter, Control.MOUSE_FILTER_STOP, "only the card itself takes one")
	card.close()
	Kit.free_all(ctx)


func test_the_alert_brings_the_dawn_card_back() -> void:
	var ctx := _ctx()
	var ui := _controller(ctx)
	check(not ui.on_alert("dawn") or ui.dawn == null, "with no assembly there is nothing to show")
	ctx.sim.storyteller._report = {"day": 8, "night": 7, "kills": 3, "mvp": {}, "wall_lost": 0, "wall_mended": 0, "breaches": 0, "lost": [], "hurt": [], "skill_ups": [], "events": [], "mood": "Everyone is steady.", "alive": 6}
	check(ui.on_alert("dawn"), "the dawn alert is the assembly's")
	await Kit.settle()
	check(ui.dawn != null and ui.dawn.is_open(), "the card is up again")
	ui.dawn.close()
	check(ui.dawn == null, "and goes when it is put away")
	Kit.free_all(ctx)


func test_the_dawn_card_comes_after_the_banner_and_at_once_from_the_alert() -> void:
	var ctx := _ctx()
	var ui := _controller(ctx)
	ctx.sim.storyteller._report = {"day": 8, "night": 7, "kills": 3, "mvp": {}, "wall_lost": 0, "wall_mended": 0, "breaches": 0, "lost": [], "hurt": [], "skill_ups": [], "events": [], "mood": "Everyone is steady.", "alive": 6}
	ui.on_dawn_report()
	check(ui.dawn == null, "not while the banner of the new day is up")
	ui._process(2.0)
	check(ui.dawn == null, "not two seconds in")
	ui._process(3.0)
	await Kit.settle()
	check(ui.dawn != null, "after the banner it is shown")
	ui.dawn.close()
	check(ui.on_alert("dawn"), "from the alert it comes at once")
	check(ui.dawn != null, "with no wait")
	ui.dawn.close()
	Kit.free_all(ctx)


func test_the_dawn_card_waits_for_the_radio_card_and_for_menus() -> void:
	var ctx := _ctx()
	var ui := _controller(ctx)
	ctx.sim.storyteller._report = {"day": 8, "night": 7, "kills": 3, "mvp": {}, "wall_lost": 0, "wall_mended": 0, "breaches": 0, "lost": [], "hurt": [], "skill_ups": [], "events": [], "mood": "Everyone is steady.", "alive": 6}
	var state := {"busy": true}
	ui.blocked = func(): return state.busy
	ui.on_dawn_report()
	ui._process(5.0)
	check(ui.dawn == null, "a menu has the screen: it waits")
	state.busy = false
	ui._process(0.1)
	await Kit.settle()
	check(ui.dawn != null, "then it is shown")
	ui.dawn.close()
	Kit.free_all(ctx)


func test_the_dawn_card_at_four_widths_has_no_overlap_and_text_that_reads() -> void:
	var reader := HudText.new()
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		Kit.update(ctx, 1)
		var card := _dawn(ctx)
		await Kit.settle()
		await Kit.settle()
		var label := "%dx%d" % [size[0], size[1]]
		var view := Rect2(Vector2.ZERO, Vector2(size[0], size[1]))
		var rect: Rect2 = card.panel.get_global_rect()
		check(view.encloses(rect), "%s: the card is inside the window: %s" % [label, str(rect)])
		check(rect.size.x >= 240.0, "%s: wide enough: %.0f" % [label, rect.size.x])
		var clashes := _overlaps(card)
		check(clashes.is_empty(), "%s: nothing in it overlaps: %s" % [label, str(clashes)])
		var faint: Array = reader._hard_to_read(card, Color.WHITE)
		check(faint.is_empty(), "%s: all the text reads at 4.5:1: %s" % [label, str(faint)])
		# it keeps off the HUD's own parts
		var parts := {"crew": Kit.rect(ctx.hud.bar), "clock": Kit.rect(ctx.hud.clock), "stores": Kit.rect(ctx.hud.res_panel), "speed": Kit.rect(ctx.hud.speed_panel)}
		parts["card"] = rect
		var hits: Array = []
		for k in Kit.overlaps(parts):
			if String(k).contains("card"):
				hits.append(k)
		check(hits.is_empty(), "%s: the card is clear of the HUD: %s" % [label, str(hits)])
		card.close()
		Kit.free_all(ctx)


func test_the_dawn_card_keeps_clear_of_the_selection_dock() -> void:
	for size in [[980, 700], [1280, 800], [1920, 1080]]:
		var ctx := _ctx(size[0], size[1])
		Kit.select(ctx, Kit.person(ctx, "ana"))
		Kit.update(ctx, 1)
		var card := _dawn(ctx)
		await Kit.settle()
		await Kit.settle()
		var rect: Rect2 = card.panel.get_global_rect()
		var dock: Rect2 = Kit.rect(ctx.hud.dock)
		var label := "%dx%d" % [size[0], size[1]]
		check(dock.size != Vector2.ZERO, "%s: the dock is up" % label)
		check(not rect.intersects(dock.grow(-1.0)), "%s: the card does not cover it: card %s, dock %s" % [label, str(rect), str(dock)])
		check(Rect2(Vector2.ZERO, Vector2(size[0], size[1])).encloses(rect), "%s: and is inside the window" % label)
		card.close()
		Kit.free_all(ctx)


func test_in_a_small_window_with_someone_selected_the_dawn_card_squeezes_above_the_dock() -> void:
	var ctx := _ctx(700, 700)
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx, 1)
	var card := _dawn(ctx)
	await Kit.settle()
	await Kit.settle()
	var rect: Rect2 = card.panel.get_global_rect()
	var dock: Rect2 = Kit.rect(ctx.hud.dock)
	check(dock.size != Vector2.ZERO, "the dock is up")
	check(not rect.intersects(dock.grow(-1.0)), "the card keeps off the order buttons: card %s, dock %s" % [str(rect), str(dock)])
	check(card.row_kinds.has("kills") and card.row_kinds.has("wall") and card.row_kinds.has("lost") and card.row_kinds.has("mood"), "with the main lines: %s" % str(card.row_kinds))
	card.close()
	Kit.free_all(ctx)


func test_in_a_cramped_window_the_dawn_card_gives_up_rows_and_stays_on_screen() -> void:
	var ctx := _ctx(700, 700)
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx, 1)
	var long := _report()
	long["lost"] = [{"who": "Ana", "epitaph": "She would have wanted the lamp left on.", "how": "died"}, {"who": "Walt", "epitaph": "He kept the north wall to the end and never said a word about it.", "how": "died"}]
	long["events"] = ["One thing happened and it was a long thing to say about it.", "Another thing happened.", "And a third thing, which is the last of them."]
	long["skill_ups"] = [{"who": "Dez", "skill": "Building", "value": 10}, {"who": "Walt", "skill": "Shooting", "value": 8}, {"who": "Hector", "skill": "Melee", "value": 9}]
	var card := _dawn(ctx, long)
	await Kit.settle()
	await Kit.settle()
	var kinds: Array = card.row_kinds
	check(kinds.has("kills") and kinds.has("wall") and kinds.has("mood") and kinds.has("lost"), "what matters most stays: %s" % str(kinds))
	check(not kinds.has("event") and not kinds.has("skills"), "the news and what was learned went first: %s" % str(kinds))
	var rect: Rect2 = card.panel.get_global_rect()
	check(Rect2(Vector2.ZERO, Vector2(700, 700)).encloses(rect), "the card is inside the window: %s" % str(rect))
	var parts := {"crew": Kit.rect(ctx.hud.bar), "clock": Kit.rect(ctx.hud.clock), "stores": Kit.rect(ctx.hud.res_panel), "card": rect}
	var hits: Array = []
	for k in Kit.overlaps(parts):
		if String(k).contains("card"):
			hits.append(k)
	check(hits.is_empty(), "and still clear of the crew, the clock and the stores: %s" % str(hits))
	card.close()
	Kit.free_all(ctx)


# ----------------------------------------------------------- the game itself --

func test_the_game_opens_the_radio_card_on_the_event_and_the_dawn_card_on_its_event() -> void:
	var g: Dictionary = MenuFakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	var sim = main.sim
	check(main.story_ui != null, "the game has the cards' controller")
	sim.storyteller.enabled = true
	sim.day = 8
	sim.minutes = 12.0 * 60.0
	sim.phase = "day"
	main.speed = 2
	main.hud.update_hud(sim, main.speed, true, 0)
	sim.storyteller.force("stranger")
	main._handle_events()
	await Engine.get_main_loop().process_frame
	check(main.story_ui.radio != null and main.story_ui.radio.is_open(), "the story_card event opens the radio card")
	eq(main.speed, 0, "and the game stands still")
	main.story_ui.radio._input(_key(KEY_2))
	eq(main.speed, 2, "answered, it runs again at the speed it had")
	# the dawn
	sim.storyteller._report = {"day": 8, "night": 7, "kills": 3, "mvp": {}, "wall_lost": 0, "wall_mended": 0, "breaches": 0, "lost": [], "hurt": [], "skill_ups": [], "events": [], "mood": "Everyone is steady.", "alive": 6}
	sim.events.append({"type": "dawn_report"})
	main._handle_events()
	check(main.story_ui.dawn == null, "it waits for the dawn's banner to go by")
	main.story_ui._process(5.0)
	await Engine.get_main_loop().process_frame
	check(main.story_ui.dawn != null and main.story_ui.dawn.is_open(), "the dawn_report event opens the assembly")
	eq(main.speed, 2, "which does not stop the game")
	main.story_ui.dawn.close()
	# the alert on the feed
	main._on_alert("dawn")
	await Engine.get_main_loop().process_frame
	check(main.story_ui.dawn != null, "and the dawn alert opens it again")
	main.story_ui.dawn.close()
	await MenuFakes.leave(g)
