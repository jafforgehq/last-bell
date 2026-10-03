extends "res://tests/case.gd"
## Round 18, the Jobs page of the radio panel (scripts/ui/jobs_page.gd, V2.2 JOBSUI): a compact two-line row for each person (the
## player first), a day job and a night post that are ASKED for over the radio (`radio.request_job` / `request_post`: a refusal is
## written under the row with its reason, a soft one with Insist), the lists of stations and posts inline under the row, the station
## settings, Fill empty seats and the way to the full roster. The words of every refusal are the sim's (`radio.job_willingness`,
## `post_willingness`, `fill_willingness`): the tests compare the page's text with them and never with a string of their own.
##
## The sim's side is scripts/sim/radio.gd (round 18 S2.1: ASKING FOR WORK) and `jobs.fill_empty`: the tests run against the real ones.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const JobsPage := preload("res://scripts/ui/jobs_page.gd")
const TextTests := preload("res://tests/test_hud_text.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]
const BLANK := {"station": "", "post": "", "person": ""}


# ------------------------------------------------------------------ helpers --

## A HUD over a quiet game in avatar mode (Ruth, or `player`).
func _ctx(width: int = 1280, height: int = 800, player: String = "ruth", crew: int = 6) -> Dictionary:
	_park_the_mouse()    # (a pointer over a button of an earlier test would bring its tooltip up in this one: a window of its own with words on it)
	var ctx := Kit.build(width, height, 1, true, crew)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player(player), "%s is the player" % player)
	Kit.update(ctx)
	return ctx


## The page, in a panel `width` wide and `height` tall, in a scroll (as the radio panel mounts it), set up on the game.
func _mount(ctx: Dictionary, width: float = 416.0, height: float = 620.0) -> Control:
	var panel := PanelContainer.new()
	panel.name = "panel"
	panel.add_theme_stylebox_override("panel", ctx.hud._style(Hud.PANEL, 6, Hud.LINE, true, "panel"))
	ctx.holder.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var page := JobsPage.new()
	scroll.add_child(page)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.setup(ctx.hud, func(): return ctx.sim)
	panel.size = Vector2(width, height)
	ctx["panel"] = panel
	ctx["scroll"] = scroll
	return page


func _person(ctx: Dictionary, id: String):
	return Kit.person(ctx, id)


## Nobody has a job; Dez the bench, Walt the Builders (a known start for a test of a seat).
func _bare(ctx: Dictionary) -> void:
	ctx.sim.jobs.clear()
	ctx.sim.jobs.assign(_person(ctx, "dez"), "bench")
	ctx.sim.jobs.assign(_person(ctx, "walt"), "builders")


func _texts_of(node: Node) -> Array:
	var out: Array = []
	_collect(node, out)
	return out


func _collect(node: Node, out: Array) -> void:
	if node is Control and not node.visible:
		return
	if node is Label and node.text != "":
		out.append(node.text)
	if node is Button and node.text != "":
		out.append(node.text)
	for c in node.get_children():
		_collect(c, out)


func _all_text(node: Node) -> String:
	return " | ".join(_texts_of(node))


func _radio(ctx: Dictionary):
	return ctx.sim.radio


func _order(page: Control) -> Array:
	var out: Array = []
	for c in page.rows_box.get_children():
		for id in page.rows:
			if page.rows[id].row == c:
				out.append(id)
	return out


func _buttons(node: Node) -> Array:
	return node.find_children("*", "Button", true, false)


func _park_the_mouse() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(1, 1)
	ev.global_position = Vector2(1, 1)
	Engine.get_main_loop().root.push_input(ev, true)


# ---------------------------------------------------------------------- rows --

func test_a_two_line_row_for_each_person_the_player_first() -> void:
	var ctx := _ctx()
	var page := _mount(ctx)
	await Kit.settle()
	eq(page.rows.keys().size(), 6, "a row for each of the six")
	eq(_order(page)[0], "ruth", "the player first")
	var rest := _order(page).slice(1)
	eq(rest, ["dez", "ana", "marcus", "walt", "hector"], "then the crew in its own order")
	for id in page.rows:
		var r: Dictionary = page.rows[id]
		check(r.pic.texture != null or id == "", "%s has a picture slot" % id)
		eq(r.pic.custom_minimum_size, Vector2(28, 28), "%s: the portrait is 28 px" % id)
		check(r.name.text == String(_person(ctx, id).first), "%s: first name" % id)
	ctx.sim.avatar.set_player("dez")
	Kit.update(ctx)
	page.refresh()
	eq(_order(page)[0], "dez", "if Dez is the player, he is first")
	Kit.free_all(ctx)


func test_the_player_has_no_seat_and_says_so() -> void:
	var ctx := _ctx()
	var page := _mount(ctx)
	var r: Dictionary = page.rows.ruth
	var said: String = String(_radio(ctx).job_willingness(_person(ctx, "ruth"), "").why)
	eq(said, "You: no seat, you are the player", "the sim says it")
	check(_all_text(r.row).contains(said), "the player's row says it in the sim's words: %s" % _all_text(r.row))
	check(not r.job.is_visible_in_tree() and not r.post.is_visible_in_tree(), "and has no buttons to press")
	check(r.job.tooltip_text != "" and r.post.tooltip_text != "", "(with a tooltip anyway)")
	Kit.free_all(ctx)


func test_a_row_shows_the_job_the_post_the_mood_and_what_they_are_doing() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var dez = _person(ctx, "dez")
	dez.activity = "At the workbench"
	var page := _mount(ctx)
	page.refresh()
	var r: Dictionary = page.rows.dez
	eq(r.job.text, "Day: Workbench", "the day job")
	eq(r.post.text, "Night: %s" % String(ctx.sim.jobs.post_of(dez).name), "the night post")
	eq(r.doing.text, "At the workbench", "what they are doing")
	check(r.mood.text != "", "a word for the mood: '%s'" % r.mood.text)
	eq(page.rows.ana.job.text, "Day: no job", "and with no job it says so")
	dez.activity = "Carrying scrap"
	ctx.sim.morale.set_value(dez, 10.0)
	ctx.sim.jobs.assign(_person(ctx, "ana"), "infirmary")
	Kit.update(ctx)
	page.refresh()
	eq(r.doing.text, "Carrying scrap", "it follows the game: what they do next")
	eq(r.mood.text, "Breaking", "their mood")
	eq(page.rows.ana.job.text, "Day: Infirmary", "a job given somewhere else")
	check(r.doing.tooltip_text == "Carrying scrap", "the full words are in the tooltip")
	Kit.free_all(ctx)


func test_the_dead_and_the_away_are_greyed_with_their_word_and_cannot_be_asked() -> void:
	var ctx := _ctx()
	var walt = _person(ctx, "walt")
	var marcus = _person(ctx, "marcus")
	walt.dead = true
	marcus.away = {"kind": "trip", "site": "pharmacy"}
	var page := _mount(ctx)
	page.refresh()
	eq(page.rows.walt.mood.text, "In memory", "the dead have their word")
	eq(page.rows.marcus.mood.text, "Away", "and the away theirs")
	check(page.rows.marcus.doing.text.begins_with("Away") or page.rows.marcus.doing.text.contains("cavenging"), "what they are doing says so: %s" % page.rows.marcus.doing.text)
	check(page.rows.marcus.job.disabled and page.rows.marcus.post.disabled, "the away cannot be given anything")
	check(page.rows.marcus.job.tooltip_text.contains("Marcus"), "and the tooltip says why: %s" % page.rows.marcus.job.tooltip_text)
	check(not page.rows.walt.job.visible or page.rows.walt.job.disabled, "nor the dead")
	var dead_color: Color = page.rows.walt.name.get_theme_color("font_color")
	check(dead_color != page.rows.dez.name.get_theme_color("font_color"), "the dead's name is greyed")
	var order := _order(page)
	eq(order[order.size() - 1], "walt", "the dead go to the foot of the list")
	Kit.free_all(ctx)


func test_a_new_face_gets_a_row_and_the_page_stays_cheap_when_nothing_changes() -> void:
	var ctx := _ctx()
	var page := _mount(ctx)
	var dez_row = page.rows.dez.row
	var nodes := page.find_children("*", "", true, false).size()
	page.refresh()
	page.refresh()
	eq(page.find_children("*", "", true, false).size(), nodes, "nothing is rebuilt when nothing changed")
	check(page.rows.dez.row == dez_row, "the same row")
	# a recruit arrives (the page learns of it at its next refresh)
	var sim = ctx.sim
	var newcomer = sim.add_person(sim.recruits.make_def(0))
	page.refresh()
	check(page.rows.has(String(newcomer.id)), "the newcomer has a row")
	eq(_order(page).size(), sim.people.size(), "and every row is in the list")
	eq(page.rows[String(newcomer.id)].name.text, String(newcomer.first), "with their name")
	Kit.free_all(ctx)


# --------------------------------------------------------------------- lists --

func test_the_day_job_list_shows_every_station_with_its_seats_and_the_sims_own_reasons() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var radio = _radio(ctx)
	var ana = _person(ctx, "ana")
	var page := _mount(ctx)
	page.open_job_list(ana)
	await Kit.settle()
	check(page.list != null and page.list_kind == "job" and page.list_for == ana, "the list is open for Ana")
	var ids := ["bench", "builders", "garden", "infirmary", "radio", "watch", "salvage", ""]
	var have: Array = page.list_items.keys()
	have.sort()
	var want := ids.duplicate()
	want.sort()
	eq(have, want, "every station (built or not) and No job")
	check(page.list.get_parent() == page.rows_box, "it is inline, under the row (never a popup)")
	eq(page.rows_box.get_child(page.rows.ana.row.get_index() + 1), page.list, "right under Ana's row")
	for id in ids:
		if id == "":
			continue
		var w: Dictionary = radio.job_willingness(ana, id)
		var item: Button = page.list_items[id]
		var reason = page.list_reasons.get(id)
		if bool(w.ok):
			check(reason == null or not reason.visible, "%s: nothing amber for an open seat" % id)
			check(not item.disabled, "%s: can be pressed" % id)
		else:
			check(reason != null and reason.visible, "%s: its reason is written" % id)
			eq(reason.text if reason != null else "", String(w.why), "%s: in the sim's words, none of the page's own" % id)
			eq(reason.get_theme_color("font_color"), Hud.WARN, "%s: in amber" % id)
			eq(item.disabled, bool(w.hard), "%s: a hard refusal is off, a soft one can be asked" % id)
			eq(page.reason_for(ana, id), String(w.why), "%s: reason_for is the sim's" % id)
	check(String(page.list_reasons["salvage"].text).contains("not built"), "the salvage bench: '%s'" % page.list_reasons["salvage"].text)
	var bench_reason := String(page.list_reasons.get("radio").text) if page.list_reasons.get("radio") != null else ""
	for q in ctx.sim.jobs.crew_of("radio"):
		check(bench_reason.contains(String(q.first)), "a full station names its crew: '%s'" % bench_reason)
	check(page.list_items["builders"].get_meta("note", "") != "" or _all_text(page.list_items["builders"]).contains("left"), "seats left are shown: %s" % _all_text(page.list_items["builders"]))
	eq(page.reason_for(ana, "infirmary"), "", "no reason for what can be had")
	page.close_list()
	check(page.list == null and page.list_items.is_empty(), "closed")
	Kit.free_all(ctx)


func test_a_reason_that_holds_for_every_line_is_said_once_at_the_top() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var radio = _radio(ctx)
	var ana = _person(ctx, "ana")
	ana.bleeding = 1.0
	var page := _mount(ctx)
	page.open_job_list(ana)
	await Kit.settle()
	var w: Dictionary = radio.job_willingness(ana, "garden")
	check(not bool(w.ok) and not bool(w.hard), "bleeding is soft for every station: %s" % str(w))
	check(page.list_shared != null and page.list_shared.visible, "the reason is on top of the list")
	eq(page.list_shared.text, String(w.why), "in the sim's words")
	eq(page.list_shared.get_theme_color("font_color"), Hud.WARN, "in amber")
	check(not page.list_reasons.has("garden") and not page.list_reasons.has("infirmary"), "and not on every line")
	check(not page.list_items["garden"].disabled, "a soft refusal can still be asked (and insisted on)")
	check(page.list_items["garden"].tooltip_text.contains(String(w.why)), "the tooltip of a line has it too")
	# what is different about a line (a full seat, an unbuilt station) is still written on its own line
	for id in page.list_items:
		var wl: Dictionary = radio.job_willingness(ana, String(id))
		if not bool(wl.ok) and String(wl.why) != String(w.why):
			check(page.list_reasons.has(id) and String(page.list_reasons[id].text) == String(wl.why), "%s keeps its own reason: '%s'" % [id, wl.why])
	page.close_list()
	check(page.list_shared == null, "gone with the list")
	Kit.free_all(ctx)


func test_the_night_post_list_shows_who_holds_each_post() -> void:
	var ctx := _ctx()
	var radio = _radio(ctx)
	var hector = _person(ctx, "hector")
	var dez = _person(ctx, "dez")
	var page := _mount(ctx)
	page.open_post_list(hector)
	await Kit.settle()
	check(page.list_kind == "post" and page.list_for == hector, "the post list is open for Hector")
	var posts: Array = ctx.sim.jobs.posts()
	eq(page.list_items.size(), posts.size(), "a line for every post on the wall")
	var held: String = String(ctx.sim.jobs.post_of(dez).id)
	var mine: String = String(ctx.sim.jobs.post_of(hector).id)
	var w: Dictionary = radio.post_willingness(hector, held)
	check(not bool(w.ok) and bool(w.hard), "a post held by someone else is a hard refusal")
	check(page.list_items[held].disabled, "so its line is off")
	eq(page.list_reasons[held].text, String(w.why), "with the sim's words: '%s'" % w.why)
	check(String(w.why).contains("Dez"), "naming the holder")
	check(page.list_items[held].tooltip_text != "", "and a tooltip")
	check(page.list_items[mine].disabled and _all_text(page.list_items[mine]).contains("current"), "their own post is marked current")
	var free_id := ""
	for po in posts:
		if radio.post_willingness(hector, String(po.id)).ok and String(po.id) != mine:
			free_id = String(po.id)
			break
	check(free_id != "", "there is a free post")
	check(not page.list_items[free_id].disabled, "a free post can be chosen")
	var headers := 0
	for c in page.list.find_children("*", "Label", true, false):
		if c.has_meta("header"):
			headers += 1
	check(headers >= 2, "the posts are grouped by part of the wall (%d headings)" % headers)
	page.close_list()
	Kit.free_all(ctx)


func test_one_list_at_a_time_and_a_second_press_on_the_button_closes_it() -> void:
	var ctx := _ctx()
	var page := _mount(ctx)
	page.rows.dez.job.pressed.emit()
	check(page.list != null and page.list_for == _person(ctx, "dez") and page.list_kind == "job", "the button opens the day list")
	page.rows.ana.post.pressed.emit()
	check(page.list_for == _person(ctx, "ana") and page.list_kind == "post", "another button replaces it")
	var lists := 0
	for c in page.rows_box.get_children():
		if c == page.list:
			lists += 1
	eq(lists, 1, "only one list is in the page")
	page.rows.ana.post.pressed.emit()
	check(page.list == null, "the same button again closes it")
	Kit.free_all(ctx)


func test_a_list_follows_the_game_while_it_is_open() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var ana = _person(ctx, "ana")
	var page := _mount(ctx)
	page.open_job_list(ana)
	var list = page.list
	page.refresh()
	check(page.list == list, "an unchanged list is the same node")
	# the infirmary fills elsewhere: the line for it changes
	var before: String = String(page.list_items["radio"].tooltip_text)
	ctx.sim.jobs.assign(_person(ctx, "hector"), "radio")
	page.refresh()
	var reason = page.list_reasons.get("radio")
	check(reason != null and reason.visible and String(reason.text).contains("Hector"), "the radio desk is full now and says who holds it: %s" % (reason.text if reason != null else "-"))
	check(page.list_items["radio"].tooltip_text != before or page.list_items["radio"].disabled, "its line changed")
	Kit.free_all(ctx)


# ------------------------------------------------------------------- choosing --

func test_choosing_a_job_asks_the_radio_and_the_answer_stays_under_the_row_for_six_seconds() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var hector = _person(ctx, "hector")
	var page := _mount(ctx)
	var ans: Dictionary = page.choose_job(hector, "bench")
	check(bool(ans.ok), "the bench has a seat: %s" % str(ans))
	eq(ctx.sim.jobs.job_of(hector), "bench", "the job is his")
	var r: Dictionary = page.rows.hector
	check(r.answer.visible and r.answer.text.begins_with("Hector: "), "his words are under the row: '%s'" % r.answer.text)
	check(r.answer.text.contains(String(ans.line)), "the radio's own line: '%s'" % ans.line)
	eq(r.answer.get_theme_color("font_color"), Hud.OK, "green when he is willing (trust %.0f)" % hector.trust)
	check(not r.insist.visible, "no Insist for a yes")
	eq(r.job.text, "Day: Workbench", "the button follows")
	page.skip_ahead(5.0)
	page.refresh()
	check(r.answer.visible, "five seconds on it is still there")
	page.skip_ahead(1.5)
	page.refresh()
	check(not r.answer.visible, "and gone after six")
	# a grudging answer is plain, not green
	hector.trust = 40.0
	page.choose_job(hector, "garden")
	check(r.answer.visible, "asked again")
	eq(r.answer.get_theme_color("font_color"), Hud.INK, "plain when it is grudging")
	Kit.free_all(ctx)


func test_taking_someone_off_a_job_is_asked_the_same_way() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var dez = _person(ctx, "dez")
	var page := _mount(ctx)
	var ans: Dictionary = page.choose_job(dez, "")
	check(bool(ans.ok), "No job is asked: %s" % str(ans))
	eq(ctx.sim.jobs.job_of(dez), "", "and he has none")
	eq(page.rows.dez.job.text, "Day: no job", "the button says so")
	Kit.free_all(ctx)


func test_a_soft_refusal_is_amber_and_can_be_insisted_on_at_a_cost() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var radio = _radio(ctx)
	var ana = _person(ctx, "ana")
	ana.bleeding = 1.0
	var page := _mount(ctx)
	var w: Dictionary = radio.job_willingness(ana, "garden")
	check(not bool(w.ok) and not bool(w.hard), "bleeding is a soft refusal for a job: %s" % str(w))
	var ans: Dictionary = page.choose_job(ana, "garden")
	check(not bool(ans.ok) and not bool(ans.hard), "refused softly")
	eq(ctx.sim.jobs.job_of(ana), "", "nothing changed")
	var r: Dictionary = page.rows.ana
	eq(r.answer.text, String(ans.why), "the reason is written under the row, in the sim's words")
	eq(r.answer.get_theme_color("font_color"), Hud.WARN, "in amber")
	check(r.insist.visible and not r.insist.disabled, "with an Insist button")
	var tip: String = r.insist.tooltip_text
	check(tip.contains(str(int(radio.INSIST_COST))) and tip.to_lower().contains("trust") and tip.to_lower().contains("mood") and tip.contains(str(int(absf(radio.INSIST_MORALE)))), "its cost is in the tooltip: %s" % tip)
	var trust: float = ana.trust
	r.insist.pressed.emit()
	eq(ctx.sim.jobs.job_of(ana), "garden", "insisting gives her the job")
	near(ana.trust, trust - float(radio.INSIST_COST), 0.01, "at the cost of trust")
	check(r.answer.visible and r.answer.get_theme_color("font_color") != Hud.WARN, "and the answer is no longer a refusal: '%s'" % r.answer.text)
	check(not r.insist.visible, "Insist is gone")
	Kit.free_all(ctx)


func test_a_hard_refusal_has_no_insist_and_the_buttons_are_off() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var dez = _person(ctx, "dez")
	dez.downed = true
	var page := _mount(ctx)
	page.refresh()
	var r: Dictionary = page.rows.dez
	check(r.job.disabled and r.post.disabled, "someone who is down cannot be given anything")
	check(r.job.tooltip_text.contains("down") and r.post.tooltip_text.contains("down"), "the tooltip says so: %s" % r.job.tooltip_text)
	var ans: Dictionary = page.choose_job(dez, "garden")
	check(not bool(ans.ok) and bool(ans.hard), "asked anyway it is refused hard")
	check(r.answer.visible and r.answer.get_theme_color("font_color") == Hud.WARN, "the reason is amber under the row: %s" % r.answer.text)
	check(not r.insist.visible, "and nobody can be pushed")
	eq(ctx.sim.jobs.job_of(dez), "bench", "his job is as it was")
	Kit.free_all(ctx)


func test_a_full_seat_is_refused_with_its_crew_named() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var hector = _person(ctx, "hector")
	ctx.sim.jobs.assign(_person(ctx, "ana"), "radio")
	var page := _mount(ctx)
	var ans: Dictionary = page.choose_job(hector, "radio")
	check(not bool(ans.ok) and bool(ans.hard), "the radio desk has one seat: %s" % str(ans))
	check(String(ans.why).contains("Ana"), "it names who holds it: %s" % ans.why)
	eq(page.rows.hector.answer.text, String(ans.why), "and the page writes it")
	check(not page.rows.hector.insist.visible, "no Insist for a full seat")
	Kit.free_all(ctx)


func test_choosing_a_post_asks_the_radio_and_a_held_post_is_refused_naming_the_holder() -> void:
	var ctx := _ctx()
	var radio = _radio(ctx)
	var hector = _person(ctx, "hector")
	var dez = _person(ctx, "dez")
	var page := _mount(ctx)
	var held: String = String(ctx.sim.jobs.post_of(dez).id)
	var ans: Dictionary = page.choose_post(hector, held)
	check(not bool(ans.ok) and bool(ans.hard), "Dez holds it: %s" % str(ans))
	check(String(ans.why).contains("Dez"), "and it says so")
	eq(page.rows.hector.answer.text, String(ans.why), "the page writes the sim's words")
	check(String(ctx.sim.jobs.post_of(hector).id) != held, "the post did not move")
	var free_id := ""
	for po in ctx.sim.jobs.posts():
		if radio.post_willingness(hector, String(po.id)).ok and String(po.id) != String(ctx.sim.jobs.post_of(hector).id):
			free_id = String(po.id)
			break
	var ok: Dictionary = page.choose_post(hector, free_id)
	check(bool(ok.ok), "a free post is his: %s" % str(ok))
	eq(String(ctx.sim.jobs.post_of(hector).id), free_id, "the post is his")
	check(page.rows.hector.post.text.contains(String(ctx.sim.jobs.post_of(hector).name)), "the button follows: %s" % page.rows.hector.post.text)
	check(page.rows.hector.answer.text.begins_with("Hector: "), "his words: %s" % page.rows.hector.answer.text)
	Kit.free_all(ctx)


func test_the_buttons_of_a_list_do_what_choose_does() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var hector = _person(ctx, "hector")
	var page := _mount(ctx)
	page.open_job_list(hector)
	page.list_items["bench"].pressed.emit()
	eq(ctx.sim.jobs.job_of(hector), "bench", "a line pressed is a job asked for")
	check(page.list == null, "and the list closes")
	page.open_post_list(hector)
	var free_id := ""
	for id in page.list_items:
		if not page.list_items[id].disabled:
			free_id = String(id)
			break
	page.list_items[free_id].pressed.emit()
	eq(String(ctx.sim.jobs.post_of(hector).id), free_id, "a post line pressed is a post asked for")
	Kit.free_all(ctx)


# ------------------------------------------------------------------------ fill --

func test_fill_empty_seats_gives_the_open_seats_to_people_with_no_job_and_takes_nobody_off_one() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var radio = _radio(ctx)
	var page := _mount(ctx)
	page.refresh()
	var fw: Dictionary = radio.fill_willingness()
	check(not fw.seats.is_empty() and not fw.free.is_empty(), "there are seats and people: %s" % str(fw))
	check(not page.fill_button.disabled, "the button is on")
	var tip: String = page.fill_button.tooltip_text
	for id in fw.free:
		check(tip.contains(String(_person(ctx, id).first)), "the tooltip names %s, who has no job: %s" % [id, tip])
	check(tip.contains("Workbench"), "and an open seat: %s" % tip)
	var r: Dictionary = page.fill()
	check(bool(r.ok), "it filled seats: %s" % str(r))
	eq(ctx.sim.jobs.job_of(_person(ctx, "dez")), "bench", "Dez is where he was")
	eq(ctx.sim.jobs.job_of(_person(ctx, "walt")), "builders", "and Walt")
	for id in ["ana", "marcus", "hector"]:
		check(ctx.sim.jobs.job_of(_person(ctx, id)) != "", "%s has a seat now" % id)
	eq(ctx.sim.jobs.job_of(_person(ctx, "ruth")), "", "the player is never given one")
	check(_all_text(page).contains(String(r.line)), "the answer line is on the page: '%s'" % r.line)
	check(page.rows.ana.job.text != "Day: no job", "the rows follow")
	Kit.free_all(ctx)


func test_fill_names_each_person_who_could_not_and_why() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var hector = _person(ctx, "hector")
	hector.downed = true
	var page := _mount(ctx)
	page.refresh()
	var r: Dictionary = page.fill()
	check(not r.stuck.is_empty(), "Hector could not: %s" % str(r))
	for s in r.stuck:
		check(_all_text(page.fill_box).contains(String(s.why)), "a line says why %s could not: '%s' in %s" % [s.name, s.why, _all_text(page.fill_box)])
	check(page.fill_box.visible, "the lines are showing")
	page.skip_ahead(20.0)
	page.refresh()
	check(not page.fill_box.visible, "and go after a while")
	Kit.free_all(ctx)


func test_fill_is_off_with_its_reason_when_there_is_nothing_to_fill() -> void:
	var ctx := _ctx()
	ctx.sim.jobs.auto_assign()    # everybody (but the player) has a seat
	var page := _mount(ctx)
	page.refresh()
	var fw: Dictionary = _radio(ctx).fill_willingness()
	check(fw.free.is_empty(), "nobody is without a job: %s" % str(fw))
	check(page.fill_button.disabled, "the button is off")
	check(page.fill_button.tooltip_text != "", "with a tooltip: %s" % page.fill_button.tooltip_text)
	# seats full, people free
	ctx.sim.jobs.clear()
	for id in ["dez", "ana", "marcus", "walt", "hector"]:
		ctx.sim.jobs.assign(_person(ctx, id), "builders" if id in ["walt", "hector", "marcus"] else ("bench" if id == "dez" else "infirmary"))
	Kit.free_all(ctx)


func test_fill_says_for_each_free_person_who_cannot_have_a_seat_that_none_is_open() -> void:
	var ctx := _ctx()
	ctx.sim.jobs.auto_assign()    # every seat that can be filled is
	var radio = _radio(ctx)
	# somebody has no job and every seat they could take is full: put the whole crew on the single-seat desks and the bench
	var free = _person(ctx, "hector")
	ctx.sim.jobs.unassign(free)
	var n := 0
	for st in ctx.sim.jobs.stations():
		while ctx.sim.jobs.seats_left(String(st.id)) > 0:
			var filler = ctx.sim.add_person(ctx.sim.recruits.make_def(n))
			n += 1
			if not ctx.sim.jobs.assign(filler, String(st.id)):
				break
	var page := _mount(ctx)
	page.refresh()
	var fw: Dictionary = radio.fill_willingness()
	check(fw.seats.is_empty() and fw.free.has("hector"), "Hector has no job and there is no seat: %s" % str(fw))
	check(page.fill_button.disabled and page.fill_button.tooltip_text != "", "the button is off, with its reason: %s" % page.fill_button.tooltip_text)
	check(page.fill_button.tooltip_text.contains("seat"), "which says it is the seats: %s" % page.fill_button.tooltip_text)
	var r: Dictionary = page.fill()
	check(not bool(r.ok), "pressing it anyway fills nothing: %s" % str(r))
	check(_all_text(page.fill_box).contains(String(r.line)), "and the page says why: '%s'" % r.line)
	Kit.free_all(ctx)


func test_the_page_works_in_a_small_start_with_the_lots_and_their_posts() -> void:
	var ctx := _ctx(1280, 800, "ruth", 3)
	var page := _mount(ctx)
	await Kit.settle()
	eq(page.rows.size(), ctx.sim.people.size(), "a row for each of the crew")
	for p in ctx.sim.people:
		page.open_job_list(p)
		check(page.list != null and page.list_items.size() >= 2, "%s: a day list" % p.first)
		page.open_post_list(p)
		check(page.list != null and page.list_items.size() == ctx.sim.jobs.posts().size(), "%s: a line for every post of the wall and the lots (%d)" % [p.first, ctx.sim.jobs.posts().size()])
	page.close_list()
	var tt := TextTests.new()
	eq(tt._small_text(page), [], "nothing under 12 px")
	Kit.free_all(ctx)


func test_the_full_roster_button_opens_the_modal_page_through_the_hud() -> void:
	var ctx := _ctx()
	var page := _mount(ctx)
	check(ctx.hud.jobs_screen == null, "no modal page yet")
	check(page.full_button.tooltip_text != "", "the button has a tooltip")
	page.full_button.pressed.emit()
	check(ctx.hud.jobs_screen != null, "the HUD opened the Duty roster")
	ctx.hud.close_jobs()
	page.full_page()
	check(ctx.hud.jobs_screen != null, "full_page() does the same")
	ctx.hud.close_jobs()
	Kit.free_all(ctx)


# --------------------------------------------------------------------- marks --

func test_hovering_a_row_a_station_or_a_post_marks_its_place() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var page := _mount(ctx)
	await Kit.settle()
	page.refresh()
	eq(ctx.hud.jobs_hover, BLANK, "the page is up: every station is marked faintly")
	var dez = _person(ctx, "dez")
	page.rows.dez.row.mouse_entered.emit()
	eq(ctx.hud.jobs_hover, {"station": "bench", "post": String(ctx.sim.jobs.post_of(dez).id), "person": "dez"}, "a row marks the person, their station and their post")
	page.rows.dez.row.mouse_exited.emit()
	eq(ctx.hud.jobs_hover, BLANK, "and lets go")
	var hector = _person(ctx, "hector")
	page.open_job_list(hector)
	page.list_items["builders"].mouse_entered.emit()
	eq(ctx.hud.jobs_hover, {"station": "builders", "post": "", "person": "hector"}, "a station in the list marks its place")
	page.open_post_list(hector)
	var some := String(page.list_items.keys()[0])
	page.list_items[some].mouse_entered.emit()
	eq(ctx.hud.jobs_hover, {"station": "", "post": some, "person": "hector"}, "a post marks the post")
	page.close_list()
	eq(ctx.hud.jobs_hover, BLANK, "closing the list lets go")
	page.hide()
	eq(ctx.hud.jobs_hover, {}, "a page that is not shown marks nothing")
	page.show()
	eq(ctx.hud.jobs_hover, BLANK, "and when it is shown again, the stations are faint again")
	Kit.free_all(ctx)


# ------------------------------------------------------------------ stations --

func test_the_marks_come_back_when_the_full_roster_that_took_them_is_closed() -> void:
	var ctx := _ctx()
	var page := _mount(ctx)
	page.refresh()
	eq(ctx.hud.jobs_hover, BLANK, "the page's faint stations")
	page.full_page()
	check(ctx.hud.jobs_screen != null, "the full roster is open")
	ctx.hud.close_jobs()
	eq(ctx.hud.jobs_hover, {}, "its closing took the marks away")
	page.refresh()
	eq(ctx.hud.jobs_hover, BLANK, "and the page, still shown, puts its own back")
	Kit.free_all(ctx)


func test_the_station_settings_are_in_a_collapsed_group_and_the_sliders_set_them() -> void:
	var ctx := _ctx()
	var page := _mount(ctx)
	await Kit.settle()
	check(not page.stations_box.visible, "the Stations group is collapsed")
	check(page.stations_toggle.tooltip_text != "", "its button has a tooltip")
	page.stations_toggle.pressed.emit()
	check(page.stations_box.visible, "the button opens it")
	var jobs = ctx.sim.jobs
	eq(page.sliders.keys().size() >= 2, true, "sliders for the stations that have settings")
	check(page.sliders.has("bench") and page.sliders.bench.has("ammo_target") and page.sliders.bench.has("scrap_reserve"), "the bench: ammo target and scrap reserve")
	check(page.sliders.has("builders") and page.sliders.builders.has("repair_below"), "the wall crew's threshold")
	var s: HSlider = page.sliders.bench.ammo_target
	check(s.focus_mode == Control.FOCUS_NONE, "a slider takes no focus")
	s.value = 150.0
	near(float(jobs.setting("bench", "ammo_target")), 150.0, 0.01, "moving the slider sets the station")
	jobs.set_setting("bench", "ammo_target", 90.0)
	page.refresh()
	near(s.value, float(jobs.setting("bench", "ammo_target")), 0.01, "and a setting changed elsewhere moves the slider")
	check(_all_text(page.stations_box).to_lower().contains("workbench") and _all_text(page.stations_box).to_lower().contains("builders"), "each group is named")
	Kit.free_all(ctx)


# --------------------------------------------------------------------- focus --

func test_focus_on_a_person_lights_their_row_and_a_person_with_no_job_gets_the_list() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var page := _mount(ctx)
	await Kit.settle()
	page.focus_on("ana")
	check(page.rows.ana.row.get_theme_stylebox("panel") != page.rows.dez.row.get_theme_stylebox("panel"), "Ana's row is lit")
	check(page.list != null and page.list_for == _person(ctx, "ana") and page.list_kind == "job", "she has no job: the list of jobs is open for her")
	page.close_list()
	page.focus_on("dez")
	check(page.list == null, "Dez has a job: just his row is lit")
	page.focus_on("nobody_here")
	check(true, "an unknown id does nothing and does not fail")
	Kit.free_all(ctx)


func test_focus_on_a_station_says_who_holds_it_and_how_many_seats_are_open() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var page := _mount(ctx)
	page.focus_on("builders")
	check(page.focus_note.visible, "a note is up")
	var note: String = page.focus_note.text
	check(note.contains("Builders") and note.contains("Walt"), "it names the station and its crew: %s" % note)
	check(note.contains("2"), "and the open seats: %s" % note)
	eq(ctx.hud.jobs_hover.get("station", ""), "builders", "the station is marked in the yard")
	page.skip_ahead(30.0)
	page.refresh()
	check(not page.focus_note.visible, "the note goes after a while")
	page.focus_on("nowhere_station")
	Kit.free_all(ctx)


# ------------------------------------------------------------------- the look --

func test_every_disabled_control_has_a_tooltip_for_every_person_station_and_post() -> void:
	var ctx := _ctx()
	_bare(ctx)
	ctx.sim.jobs.assign(_person(ctx, "ana"), "infirmary")
	var marcus = _person(ctx, "marcus")
	var hector = _person(ctx, "hector")
	marcus.away = {"kind": "trip", "site": "pharmacy"}
	hector.downed = true
	_person(ctx, "walt").dead = true
	var page := _mount(ctx)
	await Kit.settle()
	var bad: Array = []
	for p in ctx.sim.people:
		page.open_job_list(p)
		_sweep(page, bad, "%s day list" % p.first)
		page.open_post_list(p)
		_sweep(page, bad, "%s post list" % p.first)
		page.close_list()
	_sweep(page, bad, "the page")
	# the answers and the fill report too
	page.choose_job(hector, "garden")
	page.choose_job(_person(ctx, "dez"), "radio")
	page.fill()
	_sweep(page, bad, "with answers")
	eq(bad, [], "a disabled control with no tooltip")
	Kit.free_all(ctx)


func _sweep(page: Control, bad: Array, where: String) -> void:
	for b in _buttons(page):
		if b.disabled and String(b.tooltip_text) == "":
			bad.append("%s: '%s' is off with no tooltip" % [where, b.text])
		if not b.disabled and b.is_visible_in_tree() and String(b.tooltip_text) == "" and String(b.text) != "":
			bad.append("%s: '%s' has no tooltip" % [where, b.text])


func test_nothing_of_the_page_takes_the_keyboard() -> void:
	var ctx := _ctx()
	var page := _mount(ctx)
	page.open_job_list(_person(ctx, "ana"))
	page.stations_toggle.pressed.emit()
	var bad: Array = []
	for c in page.find_children("*", "Control", true, false):
		if c.focus_mode != Control.FOCUS_NONE:
			bad.append("%s %s" % [c.get_class(), c.name])
	eq(bad, [], "every control is FOCUS_NONE: the keys are for walking")
	eq(page.focus_mode, Control.FOCUS_NONE, "the page too")
	Kit.free_all(ctx)


func test_no_text_is_under_12_px_and_every_word_reads() -> void:
	var ctx := _ctx()
	_bare(ctx)
	var ana = _person(ctx, "ana")
	ana.bleeding = 1.0
	_person(ctx, "marcus").away = {"kind": "trip", "site": "pharmacy"}
	_person(ctx, "walt").dead = true
	var page := _mount(ctx)
	page.choose_job(ana, "garden")
	page.open_job_list(_person(ctx, "hector"))
	page.fill()
	page.stations_toggle.pressed.emit()
	await Kit.settle()
	var tt := TextTests.new()
	eq(tt._small_text(page), [], "nothing under 12 px")
	eq(tt._hard_to_read(page, Color.WHITE), [], "every label reads at 4.5:1, even over a bright world")
	# the words on the buttons, on the style they have
	var weak: Array = []
	for b in _buttons(page):
		if String(b.text) == "":
			continue
		var state := "disabled" if b.disabled else "normal"
		var box = b.get_theme_stylebox(state)
		var ink: Color = b.get_theme_color("font_disabled_color" if b.disabled else "font_color")
		var worst := 99.0
		var behind := tt._backdrops(b, Color.WHITE)
		var fills: Array = Kit.fills(box)
		for i in 2:
			var bg: Color = TextTests.over(fills[i], behind[i])
			worst = minf(worst, TextTests.contrast(TextTests.over(ink, bg), bg))
		if worst < TextTests.AA:
			weak.append("'%s' (%s) is %.2f:1" % [b.text, state, worst])
	eq(weak, [], "the words on the buttons read")
	Kit.free_all(ctx)


## Everything the page can show at once, in the longest words.
func _busy(ctx: Dictionary) -> void:
	_bare(ctx)
	ctx.sim.jobs.assign(_person(ctx, "ana"), "infirmary")
	_person(ctx, "marcus").activity = "Carrying a very long load of scrap and timber across the whole of the yard"
	_person(ctx, "hector").downed = true
	_person(ctx, "walt").away = {"kind": "trip", "site": "pharmacy"}
	var ana = _person(ctx, "ana")
	ana.bleeding = 1.0


func test_it_fits_the_panel_widths_at_five_window_sizes() -> void:
	for size in SIZES:
		var panel_w := 316.0 if size[0] < 980 else 440.0
		for w in [panel_w, panel_w - 24.0]:
			var ctx := _ctx(size[0], size[1])
			_busy(ctx)
			var h := float(size[1]) - 160.0
			var page := _mount(ctx, w, h)
			var where := "%d x %d, %.0f wide" % [size[0], size[1], w]
			page.choose_job(_person(ctx, "ana"), "garden")
			page.choose_post(_person(ctx, "dez"), String(ctx.sim.jobs.post_of(_person(ctx, "hector")).id))
			page.fill()
			page.stations_toggle.pressed.emit()
			page.open_post_list(_person(ctx, "marcus"))
			await Kit.settle()
			page.refresh()
			await Kit.settle()
			check(ctx.panel.get_combined_minimum_size().x <= w + 0.5, "%s: the page wants %.0f px" % [where, ctx.panel.get_combined_minimum_size().x])
			var rect: Rect2 = page.get_global_rect()
			var out: Array = []
			for c in page.find_children("*", "Control", true, false):
				if not c.is_visible_in_tree() or c.get_viewport() != page.get_viewport():
					continue    # (a tooltip is a window of its own, a child of the control it is for)
				var r: Rect2 = c.get_global_rect()
				if r.size.x > 0.0 and (r.position.x < rect.position.x - 0.5 or r.end.x > rect.end.x + 0.5):
					out.append("%s %s %s" % [c.get_class(), c.name, str(r)])
			eq(out.slice(0, 5), [], "%s: nothing leaves the page sideways" % where)
			# the rows do not overlap
			var rows: Array = []
			for id in page.rows:
				if page.rows[id].row.is_visible_in_tree():
					rows.append(page.rows[id].row.get_global_rect())
			for i in rows.size():
				for j in range(i + 1, rows.size()):
					var inter: Rect2 = rows[i].intersection(rows[j])
					check(inter.size.x < 1.0 or inter.size.y < 1.0, "%s: rows %d and %d overlap" % [where, i, j])
			check(ctx.scroll.size.y > 0.0, "%s: the scroll has a height" % where)
			ctx.scroll.ensure_control_visible(page.fill_button)
			await Kit.settle()
			var sr: Rect2 = ctx.scroll.get_global_rect()
			var fr: Rect2 = page.fill_button.get_global_rect()
			check(fr.position.y >= sr.position.y - 0.5 and fr.end.y <= sr.end.y + 0.5, "%s: the foot can be scrolled to: %s in %s" % [where, str(fr), str(sr)])
			var tt := TextTests.new()
			eq(tt._small_text(page), [], "%s: nothing under 12 px" % where)
			Kit.free_all(ctx)


func test_the_page_asks_for_its_whole_height_and_the_panels_scroll_does_the_rest() -> void:
	var ctx := _ctx(700, 560)
	var page := _mount(ctx, 316.0, 260.0)
	await Kit.settle()
	var want: float = page.wanted_height()
	check(want > 300.0, "six rows and a foot want a good deal of room: %.0f" % want)
	eq(want, page.get_combined_minimum_size().y, "wanted_height is the page's own minimum height")
	check(page.get_child(0) != null and not (page.get_children().any(func(c): return c is ScrollContainer)), "the page has no scroll of its own")
	# a short panel: the page is taller than the scroll, which scrolls; the foot is reached by scrolling
	check(ctx.scroll.get_v_scroll_bar().max_value > ctx.scroll.size.y, "the panel's scroll has something to scroll")
	ctx.scroll.scroll_vertical = 100000
	await Kit.settle()
	var fr: Rect2 = page.fill_button.get_global_rect()
	var sr: Rect2 = ctx.scroll.get_global_rect()
	check(fr.position.y >= sr.position.y - 0.5 and fr.end.y <= sr.end.y + 0.5 and fr.size.y > 10.0, "scrolled to the end the foot is in view: %s in %s" % [str(fr), str(sr)])
	# focus on a person scrolls them into view
	ctx.scroll.scroll_vertical = 0
	page.focus_on("hector")
	await Kit.settle()
	await Kit.settle()
	var hr: Rect2 = page.rows.hector.row.get_global_rect()
	check(hr.position.y >= sr.position.y - 0.5 and hr.end.y <= sr.end.y + 0.5, "focus_on brings the person's row into view: %s in %s" % [str(hr), str(sr)])
	Kit.free_all(ctx)


# --------------------------------------------------------------------- the seam --

func test_the_four_functions_of_every_page_and_a_page_with_no_radio_asks_nobody() -> void:
	var ctx := _ctx()
	var page := _mount(ctx)
	for f in ["setup", "refresh", "focus_on", "full_page"]:
		check(page.has_method(f), "has %s" % f)
	# a game with no radio contract: the page is there, nothing can be asked, and every button says why
	var plain = ctx.sim.radio
	ctx.sim.radio = null
	page.refresh()
	check(page.rows.dez.job.disabled and page.rows.dez.job.tooltip_text != "", "with no radio the buttons are off and say why")
	var ans: Dictionary = page.choose_job(_person(ctx, "dez"), "garden")
	check(not bool(ans.get("ok", false)), "nothing is asked: %s" % str(ans))
	ctx.sim.radio = plain
	page.refresh()
	check(not page.rows.dez.job.disabled, "the radio is back and so are the buttons")
	Kit.free_all(ctx)
