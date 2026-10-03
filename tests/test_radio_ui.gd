extends "res://tests/case.gd"
## The radio's views (round 17, slice 1, S1.5): in avatar mode (`sim.player_id != ""`) the dock's order buttons give way to the
## radio verbs of the selected contact (scripts/ui/radio_verbs.gd: Come with me, Hold here, Cover me, Search that, Go back, To the
## walls; the answer, the refusal and its reason, Insist), the person panel shows how far the contact trusts you (a bar, a word,
## the reasons in a tooltip), the toolbar has a News button (an unread dot; the log of scripts/ui/news_panel.gd and the calls that
## wait for an answer, with their options and a countdown) and an Alarm button (the call to arms), and the oldest open call is a
## small card under the alerts (scripts/ui/call_card.gd) that never pauses the game. Without an avatar nothing of it is there and the
## dock is as it was. The three components take a radio and a host (the HUD) and nothing else, so the raid's HUD can mount them: the
## last tests use a stand-in radio.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const RadioVerbs := preload("res://scripts/ui/radio_verbs.gd")
const CallCard := preload("res://scripts/ui/call_card.gd")
const NewsPanel := preload("res://scripts/ui/news_panel.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const RadioPanel := preload("res://scripts/ui/radio_panel.gd")
const TextTests := preload("res://tests/test_hud_text.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]
const VERBS := ["come", "hold", "cover", "search", "back", "post"]
const NAMES := ["Come with me", "Hold here", "Cover me", "Search that", "Go back", "To the walls"]


# ---------------------------------------------------------------- helpers --

## A HUD over a quiet game in avatar mode: Ruth is the player (`player` "" for no avatar), the HUD has seen it once.
func _ctx(width: int = 1280, height: int = 800, player: String = "ruth") -> Dictionary:
	var ctx := Kit.build(width, height)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	if player != "":
		check(sim.avatar.set_player(player), "%s is the player" % player)
	Kit.update(ctx)
	return ctx


func _select(ctx: Dictionary, id: String) -> void:
	Kit.select(ctx, Kit.person(ctx, id))
	Kit.update(ctx)


func _attack_call(radio, n: int = 1) -> int:
	return radio.raise_call("attack", "North wall under attack", "%d of the dead at it, 80%% intact" % n, [
		{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send reinforcements"}, {"id": "fall_back", "label": "Fall back to the school"},
	], "hold", 30.0, {"seg": 1}, Vector2(40, 10))


func _fever_call(radio) -> int:
	return radio.raise_call("sick", "Hector has a fever", "Treat them, or keep them apart", [
		{"id": "treat", "label": "Treat them"}, {"id": "apart", "label": "Keep them apart"},
	], "treat", 60.0, {"who": "hector"}, Vector2(30, 30))


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


func _rects(ctx: Dictionary) -> Dictionary:
	var h = ctx.hud
	return {
		"stores": Kit.rect(h.res_panel), "legend": Kit.rect(h.fields_legend), "cards": Kit.rect(h.bar), "clock": Kit.rect(h.clock),
		"alerts": Kit.rect(h.alerts_box), "call": Kit.rect(h.call_card), "selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos),
		"radio": Kit.rect(h.radio_box), "news": Kit.rect(h.news_panel), "speed": Kit.rect(h.speed_panel),
	}


# ------------------------------------------------------------------ the verbs --

func test_a_contact_gets_the_six_verbs_in_place_of_the_order_buttons() -> void:
	var ctx := _ctx()
	_select(ctx, "dez")
	await Kit.settle()
	var h = ctx.hud
	eq(Kit.gizmo_ids(ctx), [], "none of the old order buttons")
	check(h.radio_box.visible and h.radio_box.is_visible_in_tree(), "the verbs are up")
	var v = h.radio_verbs
	eq(v.verbs_shown(), VERBS, "the six verbs of the radio, in order")
	for i in VERBS.size():
		var b: Button = v.buttons[VERBS[i]]
		eq(b.text, NAMES[i], "%s is called %s" % [VERBS[i], NAMES[i]])
		check(b.focus_mode == Control.FOCUS_NONE, "%s takes no focus" % VERBS[i])
		check(b.get_theme_font_size("font_size") >= 12, "%s is 12 px or more" % VERBS[i])
		if VERBS[i] != "search":
			check(not b.disabled, "%s is on" % VERBS[i])
	Kit.free_all(ctx)


func test_search_that_is_for_a_place_so_in_the_yard_it_is_off_with_its_reason() -> void:
	var ctx := _ctx()
	_select(ctx, "dez")
	var b: Button = ctx.hud.radio_verbs.buttons["search"]
	check(b.disabled, "Search that is off in the yard")
	check(b.tooltip_text.to_lower().contains("place"), "and the tooltip says why: %s" % b.tooltip_text)
	# in a place (a raid HUD's) it is on
	var v := RadioVerbs.new()
	ctx.holder.add_child(v)
	v.setup(ctx.hud, func(): return ctx.sim.radio, {"place": true})
	v.set_contact(Kit.person(ctx, "dez"))
	check(not v.buttons["search"].disabled, "in a place Search that is on")
	var spot := Vector2(44.5, 12.5)
	v.setup(ctx.hud, func(): return ctx.sim.radio, {"place": true, "search_at": func(): return spot})
	v.set_contact(Kit.person(ctx, "dez"))
	v.buttons["search"].pressed.emit()
	eq(ctx.sim.radio.pending.size(), 1, "asking goes to the radio")
	eq(ctx.sim.radio.pending[0].verb, "search", "to search")
	eq(ctx.sim.radio.pending[0].at, spot, "the place the host gave")
	Kit.free_all(ctx)


func test_a_verb_that_cannot_be_given_is_off_with_the_reason_in_the_dock() -> void:
	var ctx := _ctx()
	var dez = Kit.person(ctx, "dez")
	dez.downed = true
	_select(ctx, "dez")
	var v = ctx.hud.radio_verbs
	for verb in VERBS:
		check(v.buttons[verb].disabled, "%s is off for someone who is down" % verb)
	eq(v.reply.text, "Dez is down", "the reason shows")
	eq(v.reply.get_theme_color("font_color"), Hud.WARN, "in amber")
	check(not v.insist_button.visible, "and nobody can be pushed who is down")
	dez.downed = false
	dez.away = {"kind": "trip"}
	Kit.update(ctx)
	check(v.buttons["come"].disabled and v.reply.text == "Dez is away", "away: off too, 'Dez is away': %s" % v.reply.text)
	dez.away = null
	ctx.sim.medical.sendouts[dez.id] = {}
	Kit.update(ctx)
	check(v.buttons["come"].disabled, "leaving through the gate: nobody can argue with that")
	check(v.reply.text.contains("gate"), "and says so: %s" % v.reply.text)
	Kit.free_all(ctx)


func test_the_player_cannot_be_asked() -> void:
	var ctx := _ctx()
	_select(ctx, "ruth")
	var v = ctx.hud.radio_verbs
	for verb in VERBS:
		check(v.buttons[verb].disabled, "%s is off for you" % verb)
	eq(v.reply.text, "That is you", "and it says who")
	check(not ctx.hud.inspect_refs.trust_head.visible, "nobody has a trust mark for themselves")
	Kit.free_all(ctx)


func test_a_request_goes_to_the_radio_and_the_answer_is_shown_and_toasted() -> void:
	var ctx := _ctx()
	_select(ctx, "dez")
	var v = ctx.hud.radio_verbs
	var seen: Array = []
	v.requested.connect(func(c, verb, res): seen.append([c.id, verb, bool(res.ok)]))
	v.buttons["come"].pressed.emit()
	eq(ctx.sim.radio.pending.size(), 1, "the radio has the request")
	eq(String(ctx.sim.radio.pending[0].who) + "|" + String(ctx.sim.radio.pending[0].verb), "dez|come", "Dez, to come")
	eq(seen, [["dez", "come", true]], "and the component said so")
	eq(v.reply.text, "Dez: On my way.", "the line shows in the dock")
	eq(ctx.hud.toast_label.text, "Dez: On my way.", "and in a toast")
	var said := false
	for e in ctx.sim.events:
		if e.type == "radio_line" and e.who == "dez" and e.line == "On my way.":
			said = true
	check(said, "and the radio's event for the bark over Dez is there")
	Kit.free_all(ctx)


func test_a_doubtful_contact_answers_in_a_doubtful_voice() -> void:
	var ctx := _ctx()
	var dez = Kit.person(ctx, "dez")
	dez.trust = 10.0
	_select(ctx, "dez")
	ctx.hud.radio_verbs.buttons["cover"].pressed.emit()
	eq(ctx.hud.radio_verbs.reply.text, "Dez: ...if you say so.", "low trust, a doubtful line")
	Kit.free_all(ctx)


func test_hold_here_holds_where_the_player_stands() -> void:
	var ctx := _ctx()
	var ruth = Kit.person(ctx, "ruth")
	ruth.x = 36.5
	ruth.y = 33.5
	_select(ctx, "dez")
	ctx.hud.radio_verbs.buttons["hold"].pressed.emit()
	eq(ctx.sim.radio.pending[0].verb, "hold", "to hold")
	eq(ctx.sim.radio.pending[0].at, Vector2(36.5, 33.5), "where the player stands")
	Kit.free_all(ctx)


func test_every_verb_of_the_radio_can_be_pressed() -> void:
	var ctx := _ctx()
	_select(ctx, "dez")
	var v = ctx.hud.radio_verbs
	for verb in ["come", "hold", "cover", "back", "post"]:
		var r: Dictionary = v.press(verb)
		check(bool(r.ok), "%s is agreed to: %s" % [verb, str(r)])
	eq(ctx.sim.radio.pending.size(), 1, "and a later request replaces the one waiting")
	eq(ctx.sim.radio.pending[0].verb, "post", "the last one stands")
	Kit.free_all(ctx)


func test_a_refusal_shows_its_reason_in_amber_and_offers_insist() -> void:
	var ctx := _ctx()
	var dez = Kit.person(ctx, "dez")
	dez.bleeding = 4.0
	_select(ctx, "dez")
	var v = ctx.hud.radio_verbs
	check(not v.buttons["come"].disabled, "a soft refusal can still be asked: the dock shows what they say")
	check(not v.insist_button.visible, "no Insist before there is a refusal")
	v.buttons["come"].pressed.emit()
	eq(ctx.sim.radio.pending.size(), 0, "nothing is set going")
	eq(v.reply.text, "Dez: bleeding, can't come", "the reason shows")
	eq(v.reply.get_theme_color("font_color"), Hud.WARN, "in amber")
	check(v.insist_button.visible, "and Insist is offered")
	eq(ctx.hud.toast_label.text, "Dez: bleeding, can't come", "the toast says it too")
	eq(ctx.hud.toast_col, Hud.WARN, "in the amber of a warning")
	eq(ctx.sim.radio.trust_of(dez), 55.0, "asking costs nothing")
	Kit.free_all(ctx)


func test_insisting_costs_trust_and_applies() -> void:
	var ctx := _ctx()
	var dez = Kit.person(ctx, "dez")
	dez.bleeding = 4.0
	_select(ctx, "dez")
	var v = ctx.hud.radio_verbs
	v.buttons["come"].pressed.emit()
	v.insist_button.pressed.emit()
	eq(ctx.sim.radio.pending.size(), 1, "pushed, they go")
	near(ctx.sim.radio.trust_of(dez), 55.0 - ctx.sim.radio.INSIST_COST, 0.001, "it cost trust")
	eq(v.reply.text, "Dez: ...if you say so.", "they say so grudgingly")
	check(not v.insist_button.visible, "and Insist is gone")
	Kit.update(ctx)
	check(ctx.hud.inspect_refs.trust_word.text != "", "the mark follows")
	Kit.free_all(ctx)


func test_the_answer_goes_when_another_contact_is_picked() -> void:
	var ctx := _ctx()
	var dez = Kit.person(ctx, "dez")
	dez.bleeding = 4.0
	_select(ctx, "dez")
	ctx.hud.radio_verbs.buttons["come"].pressed.emit()
	_select(ctx, "ana")
	eq(ctx.hud.radio_verbs.reply.text, "", "Ana's dock does not carry Dez's answer")
	check(not ctx.hud.radio_verbs.insist_button.visible, "nor his Insist")
	Kit.free_all(ctx)


func test_a_busy_nurse_is_refused_with_the_reason_and_can_be_insisted_on() -> void:
	var ctx := _ctx()
	var ana = Kit.person(ctx, "ana")
	var marcus = Kit.person(ctx, "marcus")
	marcus.downed = true
	ctx.sim.medical.jobs.append({"patient": marcus, "healer": ana})
	_select(ctx, "ana")
	var v = ctx.hud.radio_verbs
	v.buttons["come"].pressed.emit()
	eq(v.reply.text, "Ana: tending a patient, can't come", "the reason of the acceptance")
	check(v.insist_button.visible, "she can be pushed")
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the trust mark --

func test_the_trust_mark_is_a_bar_a_word_and_the_reasons() -> void:
	var ctx := _ctx()
	var dez = Kit.person(ctx, "dez")
	_select(ctx, "dez")
	var r = ctx.hud.inspect_refs
	check(r.trust_head.visible and r.trust_bar.visible and r.trust_word.visible, "the mark is there")
	eq(r.trust_word.text, "willing", "at the start of the run (55)")
	near(r.trust_bar.value, 0.55, 0.001, "and the bar is as full as the trust")
	dez.trust = 40.0
	Kit.update(ctx)
	eq(r.trust_word.text, "grudging", "40")
	dez.trust = 10.0
	Kit.update(ctx)
	eq(r.trust_word.text, "doubtful", "10")
	near(r.trust_bar.value, 0.10, 0.001, "a thin bar")
	ctx.sim.radio.add_trust(dez, 2.0, "Came back safe from a trip you led")
	ctx.sim.radio.add_trust(dez, -6.0, "You pushed them to go when they could not")
	Kit.update(ctx)
	var tip: String = r.trust_word.tooltip_text
	check(tip.contains("Came back safe from a trip you led") and tip.contains("+2"), "the tooltip lists the good: %s" % tip)
	check(tip.contains("You pushed them to go when they could not") and tip.contains("-6"), "and the bad: %s" % tip)
	check(tip.contains("willing") or tip.contains("grudging") or tip.contains("doubtful"), "and says what it is now: %s" % tip)
	eq(r.trust_bar.tooltip_text, tip, "on the bar too")
	Kit.free_all(ctx)


func test_the_trust_row_has_no_reasons_to_list_at_first() -> void:
	var ctx := _ctx()
	_select(ctx, "hector")
	var tip: String = ctx.hud.inspect_refs.trust_word.tooltip_text
	check(tip.contains("55") or tip.to_lower().contains("trust"), "it still explains itself: %s" % tip)
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the old dock --

func test_without_an_avatar_the_dock_is_as_it_was() -> void:
	var ctx := _ctx(1280, 800, "")
	var ana = Kit.person(ctx, "ana")
	ctx.sim.medical.treat[ana.id] = true
	ctx.sim.medical.sendout[ana.id] = true
	ctx.sim.scavenge.can = true
	Kit.select(ctx, ana)
	Kit.update(ctx)
	await Kit.settle()
	var h = ctx.hud
	eq(Kit.gizmo_ids(ctx).size(), 9, "all nine order buttons")
	check(not h.radio_box.visible, "no verbs")
	check(not h.news_button.visible and not h.alarm_button.visible, "no News or Alarm in the toolbar")
	check(not h.inspect_refs.trust_head.visible, "no trust mark")
	_attack_call(ctx.sim.radio)
	Kit.update(ctx)
	check(not h.call_card.visible, "no call card (the calls of the radio belong to avatar mode)")
	check(not h.news_open(), "no News")
	h.toggle_news()
	check(not h.news_open(), "and it cannot be opened")
	Kit.free_all(ctx)


func test_in_avatar_mode_a_wall_and_the_dead_keep_their_buttons() -> void:
	var ctx := _ctx()
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[0]})
	Kit.update(ctx)
	check(Kit.gizmo_ids(ctx).has("repair") and Kit.gizmo_ids(ctx).has("lure"), "a wall piece: Repair and the Lure as before")
	check(not ctx.hud.radio_box.visible, "no verbs for a wall")
	Kit.free_all(ctx)


func test_the_mode_is_read_each_update_so_an_avatar_that_comes_later_changes_the_dock() -> void:
	var ctx := _ctx(1280, 800, "")
	_select(ctx, "dez")
	check(Kit.gizmo_ids(ctx).size() > 0 and not ctx.hud.radio_box.visible, "no avatar: the old buttons")
	ctx.sim.avatar.set_player("ruth")
	Kit.update(ctx)
	eq(Kit.gizmo_ids(ctx), [], "the avatar comes: no order buttons")
	check(ctx.hud.radio_box.visible and ctx.hud.news_button.visible and ctx.hud.alarm_button.visible, "the verbs, News and the Alarm are there")
	Kit.free_all(ctx)


# -------------------------------------------------------------------------- news --

func test_the_news_lists_newest_first_with_kinds_and_unread_marks() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	radio.log_news("story", "Supply drop", "A call on the radio")
	radio.log_news("attack", "North wall under attack", "3 of the dead at it")
	radio.log_news("recruit", "Hector has joined the crew", "Medic")
	var h = ctx.hud
	h.toggle_news()
	Kit.update(ctx)
	await Kit.settle()
	var p = h.news_panel
	check(p.visible and h.news_open(), "the panel is up")
	check(not h.modal_open(), "and it is not a modal: the game goes on")
	eq(p.row_ids(), [3, 2, 1], "newest first")
	eq(p.row_kinds(), ["recruit", "attack", "story"], "each with its kind")
	eq(p.unread_ids(), [3, 2, 1], "all unread")
	var all := _texts_of(p)
	check(all.contains("Hector has joined the crew") and all.contains("North wall under attack") and all.contains("Supply drop"), "the words are there: %s" % all)
	# the colours by kind
	var by_kind := {}
	for k in ["attack", "recruit", "story", "sick", "alarm", "succession"]:
		by_kind[k] = RadioKit.kind_color(h, k)
	check(by_kind["attack"] != by_kind["recruit"] and by_kind["recruit"] != by_kind["story"] and by_kind["sick"] != by_kind["attack"], "the kinds have their own colours")
	eq(p.row_colors()[1], by_kind["attack"], "the attack row is red")
	h.toggle_news()
	eq(p.unread_ids(), [], "closing it reads them all")
	radio.log_news("alarm", "Call to arms", "Everyone to their posts")
	Kit.update(ctx)
	eq(p.unread_ids(), [4], "and a new one is unread")
	Kit.free_all(ctx)


func test_the_news_button_has_a_dot_while_there_is_something_unread() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	check(h.news_button.visible, "the button is in the toolbar")
	check(not h.news_dot.visible, "no dot with nothing new")
	ctx.sim.radio.log_news("story", "Supply drop")
	Kit.update(ctx)
	check(h.news_dot.visible, "a dot for the news")
	h.news_button.pressed.emit()
	check(h.news_open(), "the button opens the news")
	Kit.update(ctx)
	check(not h.news_dot.visible, "no dot while it is open")
	h.news_button.pressed.emit()
	check(not h.news_open(), "and shuts it")
	Kit.update(ctx)
	check(not h.news_dot.visible, "all read")
	ctx.sim.radio.log_news("story", "Another")
	Kit.update(ctx)
	check(h.news_dot.visible, "a new one lights it again")
	Kit.free_all(ctx)


func test_the_news_shows_the_open_calls_first_with_their_options_and_a_countdown() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	radio.log_news("story", "Supply drop")
	var id := _attack_call(radio)
	radio.log_news("recruit", "Hector has joined the crew")
	var h = ctx.hud
	h.toggle_news()
	Kit.update(ctx)
	await Kit.settle()
	var p = h.news_panel
	eq(p.call_ids(), [id], "the open call is at the top")
	eq(p.row_ids(), [3, 1], "and is not among the log's lines")
	var view = p.call_views[0]
	eq(view.buttons.keys(), ["hold", "reinforce", "fall_back"], "its three options")
	near(view.seconds_left(), 10.0, 0.01, "thirty game minutes at three a second: ten seconds")
	ctx.sim.clock_min += 15.0
	Kit.update(ctx)
	near(view.seconds_left(), 5.0, 0.01, "and it counts down")
	near(view.bar.value, 0.5, 0.01, "the bar is half empty")
	view.buttons["reinforce"].pressed.emit()
	check(String(RadioKit.entry_of(radio, id).answered) == "reinforce", "answering through the panel answers the call")
	Kit.update(ctx)
	eq(p.call_ids(), [], "it leaves the top")
	check(p.row_ids().has(id), "and joins the log, with what came of it")
	check(_texts_of(p).contains("Reinforcements sent"), "its result: %s" % _texts_of(p))
	Kit.free_all(ctx)


func test_the_log_shows_what_a_default_took() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	var id := _attack_call(radio)
	ctx.sim.clock_min += 40.0
	radio.update(0.0)
	check(String(RadioKit.entry_of(radio, id).answered) == "hold" and bool(RadioKit.entry_of(radio, id).by_default), "the sim took the default")
	ctx.hud.toggle_news()
	Kit.update(ctx)
	var all := _texts_of(ctx.hud.news_panel)
	check(all.contains("Holding") and all.to_lower().contains("by default"), "the log says: %s" % all)
	Kit.free_all(ctx)


# ----------------------------------------------------------------------- call card --

func test_the_oldest_open_call_is_a_card_under_the_alerts() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	var h = ctx.hud
	check(not h.call_card.visible, "no card with no call")
	var first := _attack_call(radio)
	var second := _fever_call(radio)
	ctx.sim.alert("a1", "warn", "Food is running out", "about 2 days left", null, 600.0)
	Kit.update(ctx)
	await Kit.settle()
	check(h.call_card.visible, "a call: a card")
	eq(h.call_card.shown_id, first, "the oldest")
	var view = h.call_card.view
	eq(view.title_label.text, "North wall under attack", "its title")
	check(view.sub_label.text.contains("80%"), "and its second line: %s" % view.sub_label.text)
	eq(view.buttons.keys(), ["hold", "reinforce", "fall_back"], "a button for each way to answer")
	check(Kit.rect(h.call_card).position.y >= Kit.rect(h.alerts_box).end.y - 0.5, "it hangs under the alerts")
	check(h.call_card.get_parent() == h.alerts_box.get_parent(), "in the same column")
	view.buttons["hold"].pressed.emit()
	eq(String(RadioKit.entry_of(radio, first).answered), "hold", "answering applies the option")
	Kit.update(ctx)
	eq(h.call_card.shown_id, second, "and the next call comes up")
	Kit.free_all(ctx)


func test_the_card_counts_down_and_never_pauses_the_game() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	var h = ctx.hud
	_attack_call(radio)
	Kit.update(ctx)
	var view = h.call_card.view
	near(view.seconds_left(), 10.0, 0.01, "ten seconds")
	check(view.count_label.text.contains("10"), "the countdown shows: %s" % view.count_label.text)
	check(view.count_label.text.contains("Hold"), "and what is taken when it runs out: %s" % view.count_label.text)
	ctx.sim.clock_min += 24.0
	Kit.update(ctx)
	near(view.seconds_left(), 2.0, 0.01, "two seconds")
	near(view.bar.value, 0.2, 0.01, "a fifth of the bar")
	eq(ctx.speeds, [], "nothing asked the game to pause")
	check(not h.modal_open(), "and the card is not a modal")
	Kit.free_all(ctx)


func test_a_default_taken_shows_its_result_for_a_moment_then_the_card_goes() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	var h = ctx.hud
	h.call_card.result_ms = 400
	var id := _attack_call(radio)
	Kit.update(ctx)
	check(h.call_card.visible, "the card is up")
	ctx.sim.clock_min += 40.0
	radio.update(0.0)
	Kit.update(ctx)
	check(h.call_card.visible and h.call_card.is_showing_result(), "the time is up: the card shows what the sim did")
	var all := _texts_of(h.call_card)
	check(all.contains("Holding"), "the result: %s" % all)
	check(all.to_lower().contains("by default"), "and that nobody answered: %s" % all)
	for b in h.call_card.view.buttons.values():
		check(not b.is_visible_in_tree(), "with no buttons left to press")
	await Engine.get_main_loop().create_timer(0.55).timeout
	Kit.update(ctx)
	check(not h.call_card.visible, "and a moment later it is gone")
	eq(h.call_card.shown_id, 0, "with nothing shown")
	check(id > 0, "(the call had an id)")
	Kit.free_all(ctx)


func test_an_answer_shows_its_result_too() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	h.call_card.result_ms = 400
	_attack_call(ctx.sim.radio)
	Kit.update(ctx)
	h.call_card.view.buttons["fall_back"].pressed.emit()
	Kit.update(ctx)
	check(h.call_card.visible and h.call_card.is_showing_result(), "the answer's result shows")
	check(_texts_of(h.call_card).contains("Falling back"), "'%s'" % _texts_of(h.call_card))
	check(not _texts_of(h.call_card).to_lower().contains("by default"), "not as a default")
	await Engine.get_main_loop().create_timer(0.55).timeout
	Kit.update(ctx)
	check(not h.call_card.visible, "then it goes")
	Kit.free_all(ctx)


func test_a_new_call_cuts_the_result_short() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	h.call_card.result_ms = 5000
	var first := _attack_call(ctx.sim.radio)
	Kit.update(ctx)
	h.call_card.view.buttons["hold"].pressed.emit()
	Kit.update(ctx)
	check(h.call_card.is_showing_result(), "the result is up")
	var second := _fever_call(ctx.sim.radio)
	Kit.update(ctx)
	eq(h.call_card.shown_id, second, "a decision is never hidden behind a result")
	check(not h.call_card.is_showing_result(), "the result gives way")
	check(first != second, "(two calls)")
	Kit.free_all(ctx)


func test_the_card_steps_aside_while_the_news_is_up_and_comes_back() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	var id := _attack_call(ctx.sim.radio)
	Kit.update(ctx)
	check(h.call_card.visible, "the card is up")
	h.toggle_news()
	Kit.update(ctx)
	check(not h.call_card.visible, "the news is up: it has the call at its top, so the card steps aside")
	eq(h.news_panel.call_ids(), [id], "with its buttons")
	h.toggle_news()
	Kit.update(ctx)
	check(h.call_card.visible, "and the card is back when the news is shut")
	Kit.free_all(ctx)


# ---------------------------------------------------------------------------- alarm --

func test_the_alarm_button_toggles_the_call_to_arms() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	var radio = ctx.sim.radio
	check(h.alarm_button.visible, "the Alarm is in the toolbar")
	check(h.alarm_button.tooltip_text.contains("Call to arms"), "its tooltip names it: %s" % h.alarm_button.tooltip_text)
	check(not radio.alarm_on, "off")
	check(h.alarm_button.get_meta("icon").modulate != Hud.ACCENT, "dark")
	h.alarm_button.pressed.emit()
	check(radio.alarm_on, "the button rings the alarm")
	Kit.update(ctx)
	eq(h.alarm_button.get_meta("icon").modulate, Hud.ACCENT, "and is lit while it rings")
	check(h.alarm_button.tooltip_text.to_lower().contains("stand down"), "its tooltip says how to end it: %s" % h.alarm_button.tooltip_text)
	h.alarm_button.pressed.emit()
	check(not radio.alarm_on, "pressed again it stands down")
	Kit.update(ctx)
	check(h.alarm_button.get_meta("icon").modulate != Hud.ACCENT, "and goes dark")
	radio.alarm(true)
	Kit.update(ctx)
	eq(h.alarm_button.get_meta("icon").modulate, Hud.ACCENT, "lit when the alarm is rung by anything else too")
	Kit.free_all(ctx)


func test_the_l_key_lure_is_still_there() -> void:
	var ctx := _ctx()
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[0]})
	Kit.update(ctx)
	var b := Kit.gizmo(ctx, "lure")
	check(b != null and b.get_meta("key") == "L", "the lure button keeps its key")
	Kit.free_all(ctx)


# ------------------------------------------------- the components, with a stand-in radio --

class FakeSim:
	extends RefCounted
	var clock_min := 100.0
	var min_per_sec := 3.0


class FakeRadio:
	extends RefCounted
	const VERBS := ["come", "hold", "cover", "search", "back", "post"]
	var sim := FakeSim.new()
	var news: Array = []
	var asked: Array = []
	var answers: Array = []
	var refuse := ""
	var alarm_on := false

	func verb_name(verb: String) -> String:
		return "V-" + verb

	func willingness(contact, verb: String) -> Dictionary:
		if refuse != "":
			return {"ok": false, "why": refuse, "line": "", "delay_s": 0.0, "tone": "refused", "hard": false}
		return {"ok": true, "why": "", "line": "Right.", "delay_s": 0.5, "tone": "willing", "hard": false}

	func request(contact, verb: String, args: Dictionary = {}) -> Dictionary:
		asked.append([contact.id, verb, args.duplicate()])
		if refuse != "" and not bool(args.get("insist", false)):
			return {"ok": false, "line": "", "why": refuse, "delay_s": 0.0, "tone": "refused", "insisted": false}
		return {"ok": true, "line": "Right.", "why": "", "delay_s": 0.5, "tone": "willing", "insisted": bool(args.get("insist", false))}

	func trust_of(_p) -> float:
		return 60.0

	func tone_of(_p) -> String:
		return "willing"

	func trust_why(_p) -> Array:
		return []

	func leader():
		return null

	func latest_id() -> int:
		return int(news[news.size() - 1].id) if not news.is_empty() else 0

	func open_calls() -> Array:
		var out: Array = []
		for e in news:
			if not e.options.is_empty() and String(e.answered) == "":
				out.append(e)
		return out

	func answer(id: int, option_id: String) -> bool:
		for e in news:
			if int(e.id) == id and String(e.answered) == "":
				e.answered = option_id
				e.result = "Done: " + option_id
				answers.append([id, option_id])
				return true
		return false

	func alarm(on: bool, _at_dawn: bool = false) -> void:
		alarm_on = on

	func add(kind: String, text: String, options: Array = [], default_id: String = "", ttl_min: float = 30.0) -> int:
		var id := news.size() + 1
		news.append({"id": id, "t": sim.clock_min, "day": 2, "hour": 14.5, "kind": kind, "text": text, "sub": "", "options": options, "default": default_id,
			"due": sim.clock_min + ttl_min, "answered": "", "by_default": false, "result": "", "at": null, "data": {}})
		return id


func test_the_verbs_work_with_a_stand_in_radio_and_other_people() -> void:
	var ctx := _ctx(1280, 800, "")
	var fake := FakeRadio.new()
	var v := RadioVerbs.new()
	ctx.holder.add_child(v)
	v.setup(ctx.hud, func(): return fake)
	var seen: Array = []
	v.requested.connect(func(c, verb, res): seen.append([c.id, verb, res.ok]))
	var walt = Kit.person(ctx, "walt")
	v.set_contact(walt)
	eq(v.verbs_shown(), VERBS, "the verbs come from the radio's list")
	eq(v.buttons["come"].text, "V-come", "and their names from the radio's names")
	v.buttons["hold"].pressed.emit()
	eq(fake.asked.size(), 1, "the stand-in was asked")
	eq(String(fake.asked[0][0]) + "|" + String(fake.asked[0][1]), "walt|hold", "Walt, to hold")
	eq(seen, [["walt", "hold", true]], "and the signal went out")
	check(v.reply.text.contains("Right."), "the answer shows: %s" % v.reply.text)
	fake.refuse = "Walt: on watch, can't hold"
	v.refresh()
	v.buttons["come"].pressed.emit()
	eq(v.reply.text, "Walt: on watch, can't hold", "a refusal shows its reason")
	check(v.insist_button.visible, "with Insist")
	v.insist_button.pressed.emit()
	check(bool(fake.asked[fake.asked.size() - 1][2].get("insist", false)), "which asks again with insist")
	v.set_contact(null)
	check(not v.visible or v.buttons["come"].disabled, "with no contact there is nothing to press")
	Kit.free_all(ctx)


func test_the_card_and_the_news_work_with_a_stand_in_radio() -> void:
	var ctx := _ctx(1280, 800, "")
	var fake := FakeRadio.new()
	var card := CallCard.new()
	ctx.holder.add_child(card)
	card.setup(ctx.hud, func(): return fake)
	var news := NewsPanel.new()
	ctx.holder.add_child(news)
	news.setup(ctx.hud, func(): return fake)
	card.refresh()
	news.refresh()
	check(not card.visible, "no card with no call")
	fake.add("story", "A voice on the radio")
	var id := fake.add("attack", "The fence", [{"id": "a", "label": "Hold the line"}, {"id": "b", "label": "Run"}], "a", 30.0)
	card.refresh()
	news.refresh()
	check(card.visible and card.shown_id == id, "the card shows the call")
	eq(news.call_ids(), [id], "the news has it at the top")
	eq(news.row_ids(), [1], "and the log has the other")
	card.view.buttons["b"].pressed.emit()
	eq(fake.answers, [[id, "b"]], "an answer goes to the stand-in")
	card.refresh()
	check(card.is_showing_result() and _texts_of(card).contains("Done: b"), "and its result shows")
	Kit.free_all(ctx)


# --------------------------------------------------------------------------- the bark --

func test_a_radio_line_is_a_bark_over_the_contact_and_t_opens_the_news() -> void:
	var win: Window = Engine.get_main_loop().root
	var saved := {"size": win.size, "position": win.position, "mode": win.content_scale_mode, "aspect": win.content_scale_aspect, "scale_size": win.content_scale_size}
	Engine.set_meta("run", {"difficulty": 1, "seed": 7})
	var main = load("res://scenes/main.tscn").instantiate()
	win.add_child(main)
	main.set_process(false)
	main.sim.avatar.set_player("ruth")
	var dez = null
	for p in main.sim.people:
		if p.id == "dez":
			dez = p
	main.sim.events.clear()
	var r: Dictionary = main.sim.radio.request(dez, "come")
	check(bool(r.ok), "Dez agrees")
	main._handle_events()
	var said := ""
	for b in main.overlay.bubbles:
		if b.p == dez:
			said = String(b.text)
	eq(said, "On my way.", "the line is a bubble over Dez")
	main.hud.update_hud(main.sim, 1, true, 0)
	check(not main.hud.news_open(), "the news is shut")
	main._key(KEY_T)
	check(main.hud.news_open(), "T opens the news in avatar mode")
	main._key(KEY_T)
	check(not main.hud.news_open(), "and shuts it")
	main.queue_free()
	await Engine.get_main_loop().process_frame
	win.content_scale_mode = saved.mode
	win.content_scale_aspect = saved.aspect
	win.content_scale_size = saved.scale_size
	win.size = saved.size
	win.position = saved.position


# -------------------------------------------------------------------------- layout --

## An avatar game with everything the radio can put on the screen: a contact with the verbs, a refusal showing, alerts, an open call,
## a log of news, the fields legend and the forecast.
func _busy(width: int, height: int, news_open: bool, help_open: bool = false) -> Dictionary:
	var ctx := _ctx(width, height)
	var h = ctx.hud
	var radio = ctx.sim.radio
	Kit.person(ctx, "ana").bleeding = 3.0
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 600.0)
	ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 600.0)
	ctx.sim.alert("a3", "info", "The bell has rung", "Everyone is heading to their posts", null, 600.0)
	radio.log_news("story", "A voice on the radio", "A call on the radio")
	radio.log_news("recruit", "Hector has joined the crew", "Medic")
	radio.log_news("attack", "East wall under attack", "3 of the dead at it")
	radio.log_news("alarm", "Call to arms", "Everyone to their posts")
	_attack_call(radio)
	_fever_call(radio)
	h.set_fields(true)
	ctx.sim.tactics.told = Kit.forecast({"brutes": 2, "heading": "north and west"})
	_select(ctx, "ana")
	h.radio_verbs.buttons["come"].pressed.emit()    # a refusal on show: the longest thing the dock says
	if help_open:
		h.help.visible = true
	if news_open:
		h.toggle_news()
	Kit.update(ctx)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	return ctx


func test_nothing_overlaps_or_leaves_the_window_with_the_radio_up() -> void:
	for size in SIZES:
		for news_open in [false, true]:
			var ctx: Dictionary = await _busy(size[0], size[1], news_open)
			var h = ctx.hud
			var where := "%d x %d, news %s" % [size[0], size[1], news_open]
			var rects := _rects(ctx)
			check(rects.radio.size.x > 60.0 and rects.radio.size.y > 20.0, "%s: the verbs have a size: %s" % [where, str(rects.radio)])
			if news_open:
				check(h.call_card.suppressed and h.news_panel.call_views.size() == 2, "%s: the card steps aside for the news, which holds the two calls" % where)
			else:
				check(rects.call.size.x > 60.0, "%s: the call card is up: %s" % [where, str(rects.call)])
			if news_open:
				check(rects.news.size.x > 60.0 and rects.news.size.y > 40.0, "%s: the news panel has a size: %s" % [where, str(rects.news)])
			else:
				eq(rects.news, Rect2(), "%s: and none when it is shut" % where)
			eq(Kit.overlaps(rects), [], where)
			var win := Rect2(0, 0, size[0], size[1])
			for name in rects:
				var r: Rect2 = rects[name]
				if r.size.x > 1.0 and r.size.y > 1.0:
					check(win.encloses(r.grow(-0.5)), "%s: %s is in the window: %s" % [where, name, str(r)])
			Kit.free_all(ctx)


func test_the_news_gives_way_to_the_help_and_the_help_to_the_news() -> void:
	var ctx: Dictionary = await _busy(1280, 800, true)
	var h = ctx.hud
	check(h.news_open() and not h.help.visible, "the news is up, the help is shut")
	h.help_button.pressed.emit()
	check(h.help.visible and not h.news_open(), "the help opens over where the news was")
	h.toggle_news()
	check(h.news_open() and not h.help.visible, "and the news takes it back")
	Kit.free_all(ctx)


func test_the_help_open_with_the_radio_up_overlaps_nothing_but_the_alerts() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1], false, true)
		var rects := _rects(ctx)
		rects["help"] = Kit.rect(ctx.hud.help)
		rects.erase("alerts")
		rects.erase("cards")
		rects.erase("call")
		eq(Kit.overlaps(rects), [], "%d x %d with the help" % [size[0], size[1]])
		Kit.free_all(ctx)


func test_nothing_overlaps_at_any_width_with_the_radio_up() -> void:
	var ctx: Dictionary = await _busy(1280, 760, false)
	var h = ctx.hud
	var bad: Array = []
	for width in range(700, 1401, 70):
		for news_open in [false, true]:
			if h.news_open() != news_open:
				h.toggle_news()
			Kit.resize(ctx, width, 760)
			Kit.update(ctx)
			await Kit.settle()
			Kit.update(ctx)
			await Kit.settle()
			var rects := _rects(ctx)
			var found := Kit.overlaps(rects)
			if not found.is_empty():
				bad.append("%d px, news %s: %s" % [width, news_open, found])
			var win := Rect2(0, 0, width, 760)
			for name in rects:
				var r: Rect2 = rects[name]
				if r.size.x > 1.0 and r.size.y > 1.0 and not win.encloses(r.grow(-0.5)):
					bad.append("%d px: %s leaves the window: %s" % [width, name, str(r)])
	eq(bad, [], "overlaps found")
	Kit.free_all(ctx)


func test_the_radio_dock_keeps_clear_of_the_toolbar_and_the_toast() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _busy(size[0], size[1], false)
		var h = ctx.hud
		h.toast("Ana: bleeding, can't come", "warn")
		await Kit.settle()
		var rects := {"radio": Kit.rect(h.radio_box), "selection": Kit.rect(h.inspect), "toast": Kit.rect(h.toast_panel), "speed": Kit.rect(h.speed_panel), "stores": Kit.rect(h.res_panel), "cards": Kit.rect(h.bar)}
		eq(Kit.overlaps(rects), [], "%d x %d with a toast up" % [size[0], size[1]])
		Kit.free_all(ctx)


func test_the_radio_has_no_small_text_and_every_word_reads() -> void:
	for size in [[1280, 800], [700, 560]]:
		var ctx: Dictionary = await _busy(size[0], size[1], true)
		var h = ctx.hud
		var tt := TextTests.new()
		for part in [h.radio_box, h.call_card, h.news_panel, h.inspect, h.speed_panel]:
			eq(tt._small_text(part), [], "%d x %d: nothing under 12 px in %s" % [size[0], size[1], part.name])
			eq(tt._hard_to_read(part, Color.WHITE), [], "%d x %d: every word in %s reads at 4.5:1" % [size[0], size[1], part.name])
		Kit.free_all(ctx)


func test_every_control_of_the_radio_takes_no_focus() -> void:
	var ctx: Dictionary = await _busy(1280, 800, true)
	var h = ctx.hud
	var bad: Array = []
	for part in [h.radio_box, h.call_card, h.news_panel, h.news_button, h.alarm_button]:
		var nodes: Array = [part]
		nodes.append_array(part.find_children("*", "Control", true, false))
		for c in nodes:
			if c is Control and c.focus_mode != Control.FOCUS_NONE:
				bad.append("%s %s" % [c.get_class(), c.name])
	eq(bad, [], "no control of the radio can take the keyboard")
	Kit.free_all(ctx)


func test_the_small_window_has_the_narrow_panel_with_the_news_in_it_that_scrolls() -> void:
	# (round 18: the News is a page of the radio panel, which is 316 px wide in a narrow window and 440 in a wide one)
	var ctx: Dictionary = await _busy(700, 560, true)
	var h = ctx.hud
	var r := Kit.rect(h.radio_panel)
	check(r.size.x <= RadioPanel.WIDTH_COMPACT + 0.5 and r.size.x >= 300.0, "narrow: %s" % str(r))
	check(r.size.y >= 200.0, "and tall enough to read: %s" % str(r))
	var page := Kit.rect(h.news_panel)
	check(page.size.y >= 80.0 and r.encloses(page), "the News page has its room in it: %s" % str(page))
	check(h.news_panel.is_compact(), "it knows it is the narrow one")
	Kit.resize(ctx, 1280, 800)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	check(Kit.rect(h.radio_panel).size.x >= RadioPanel.WIDTH - 0.5 and not h.news_panel.is_compact(), "and wide again in a wide window: %s" % str(Kit.rect(h.radio_panel)))
	Kit.free_all(ctx)
