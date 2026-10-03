extends "res://tests/case.gd"
## Round 18, the Build page of the radio panel (scripts/ui/build_page.gd): the Build screen's list of buildings in a form that sits beside
## the yard and does not pause the game. A slip for each building (each home of one that may stand twice: "Bunk house 1 of 2"), one state
## line each (what it costs; or why it cannot be ordered now, in amber, in the simulation's own words; or the site and how far along; or
## Built); a slip that is pressed opens under itself with what it gives, where it goes, the crew note, Order (the radio is asked, the
## answer is the lead builder's), Cancel with the refund, Demolish in two presses. Hover marks, the foot (stores, beds, Full page, Streets
## and map...), every disabled control has its reason as its tooltip, nothing under twelve pixels, the panel's two widths at five window
## sizes. The page is mounted here in a panel of its own over a HUD kit's game; until the radio has `build_willingness` and
## `request_build` (round 18's ERRANDS) a stand-in radio has them (`FakeRadio`: the contract of docs/superpowers/plans/2026-10-03-round-18.md).

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const BuildPage := preload("res://scripts/ui/build_page.gd")
const BuildScreen := preload("res://scripts/ui/build_screen.gd")
const Build := preload("res://scripts/sim/build.gd")
const TextTests := preload("res://tests/test_hud_text.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]
const WIDTH := 440.0
const WIDTH_COMPACT := 316.0
const NOTE_NOBODY := "Nobody is on the Builders job: give it to someone on the Jobs page, or the site waits"


## The two asks of round 18's radio, as its plan words them, for a game whose radio does not have them yet.
class FakeRadio:
	extends "res://scripts/sim/radio.gd"

	func build_willingness(building_id: String) -> Dictionary:
		var b = sim.build
		var why := String(b.why_not_build(building_id))
		var note := ""
		if sim.jobs.crew_of("builders").is_empty():
			note = "Nobody is on the Builders job: give it to someone on the Jobs page, or the site waits"
		return {"ok": why == "", "why": why, "plot": b.home_for(building_id), "cost": int(b.building(building_id).get("scrap", 0)), "note": note}

	func request_build(building_id: String, _args: Dictionary = {}) -> Dictionary:
		var w := build_willingness(building_id)
		if not bool(w.ok):
			return {"ok": false, "line": "", "why": w.why, "plot": w.plot}
		sim.build.order(String(w.plot), building_id)
		var lead = sim.jobs.crew_of("builders")[0] if not sim.jobs.crew_of("builders").is_empty() else null
		var line := "On it."
		log_news("build", "The %s is ordered" % String(sim.build.building(building_id).name).to_lower(), "")
		return {"ok": true, "line": line, "why": "", "plot": w.plot, "who": String(lead.id) if lead != null else ""}


# ---------------------------------------------------------------- helpers --

## The mouse put in a corner where no control is (a pointer left over a button would let its tooltip come up in this test).
func _park_the_mouse() -> void:
	var root: Window = Engine.get_main_loop().root
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(1, 1)
	ev.global_position = Vector2(1, 1)
	root.push_input(ev, true)


## A HUD over a quiet game in avatar mode (Ruth plays), the stores with 100 scrap, and the page mounted in a panel of its own, `width` wide.
func _ctx(width: float = WIDTH, height: float = 620.0, crew: int = 6, scrap: float = 100.0, buildings_path: String = "") -> Dictionary:
	_park_the_mouse()
	if buildings_path != "":
		Build.buildings_path = buildings_path
	var ctx := Kit.build(1280, 800, 1, false, crew)
	Build.buildings_path = Build.BUILDINGS_PATH
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	if not sim.radio.has_method("build_willingness"):
		var fake := FakeRadio.new()
		fake.setup(sim)
		sim.radio = fake
		ctx["fake_radio"] = true
	sim.stock.scrap = scrap
	Kit.update(ctx)
	_mount(ctx, width, height)
	return ctx


func _mount(ctx: Dictionary, width: float, height: float, options: Dictionary = {}) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ctx.hud._style(Hud.PANEL, 6, Hud.LINE, true, "panel"))
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(width, height)
	panel.size = Vector2(width, height)
	ctx.holder.add_child(panel)
	var page = BuildPage.new()
	panel.add_child(page)
	page.setup(ctx.hud, func(): return ctx.sim, options)
	ctx["panel"] = panel
	ctx["page"] = page
	ctx["width"] = width


func _free(ctx: Dictionary) -> void:
	Kit.free_all(ctx)


## Puts a building on a plot at once, as if it had been built.
func _stand(ctx: Dictionary, plot_id: String, building_id: String) -> void:
	ctx.sim.build.plot(plot_id).building = building_id
	ctx.sim.build.version += 1


## Orders a building on a plot and leaves `progress` builder-hours done on it.
func _site(ctx: Dictionary, plot_id: String, building_id: String, progress: float = 0.0) -> void:
	var ordered: bool = ctx.sim.build.order(plot_id, building_id)
	check(ordered, "(%s is ordered on %s)" % [building_id, plot_id])
	if ordered:
		ctx.sim.build.plot(plot_id).site.progress = progress


func _plot_ids(ctx: Dictionary) -> Array:
	var ids: Array = []
	for pl in ctx.sim.build.plots():
		if String(pl.kind) != "mouth":
			ids.append(String(pl.id))
	return ids


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


func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button:
		out.append(node)
	for c in node.get_children():
		_buttons(c, out)
	return out


## The people on the Builders job are taken off it.
func _nobody_builds(ctx: Dictionary) -> void:
	for p in ctx.sim.jobs.crew_of("builders"):
		ctx.sim.jobs.unassign(p)


func _someone_builds(ctx: Dictionary) -> void:
	var dez = Kit.person(ctx, "dez")
	ctx.sim.jobs.unassign(dez)
	check(ctx.sim.jobs.assign(dez, "builders"), "Dez takes the Builders job")


## A game whose catalogue has the workshop needing the salvage bench first (the data has no such building yet).
func _needs_path() -> String:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Build.BUILDINGS_PATH))
	for b in parsed.buildings:
		if b.id == "workshop":
			b["requires"] = "salvage_bench"
	var path := "user://test_r18_build_buildings.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(parsed))
	f.close()
	return path


## A settlement game (the small start has the lots of the ring), the lots claimed.
func _town_ctx(claim: Array) -> Dictionary:
	var ctx := _ctx(WIDTH, 620.0, 3)
	var sim = ctx.sim
	sim.day = 99
	for id in sim.town.state:
		sim.town.reveal(id)
		sim.town.state[id].cleared = true
	for l in claim:
		sim.stock.scrap = 1000.0
		sim.lots.claim(String(l))
	sim.stock.scrap = 200.0
	ctx.page.refresh()
	return ctx


# ------------------------------------------------------------------ the list --

func test_a_slip_for_each_building_and_each_home_of_one_that_may_stand_twice() -> void:
	var ctx := _ctx()
	var page = ctx.page
	eq(page.rows.keys(), _plot_ids(ctx), "a slip for each home, in the order of the data")
	eq(page.rows.size(), 11, "eleven: the eight buildings, the bunk house, the tents and the watchtower twice")
	var all := _texts_of(page)
	for t in ["BUILDINGS", "Salvage bench", "Greenhouse beds", "Bunk house 1 of 2", "Bunk house 2 of 2", "Tents 1 of 2", "Tents 2 of 2", "Watchtower 2 of 2", "Radio mast", "Workshop"]:
		check(all.contains(t), "shows '%s'" % t)
	for id in page.rows:
		eq(page.rows[id].name.text, String(ctx.sim.build.title_of(id)), "%s: the building's name, numbered when it has two homes" % id)
	eq(page.slips_of("bunk_house"), ["bunk_house_home_1", "bunk_house_home_2"], "a building's slips")
	check(not ctx.sim.build.catalogue().is_empty() and not page.rows.has("scrap_yard_home_1"), "no lot's plot in the classic start")
	_free(ctx)


func test_a_slip_says_what_it_costs_or_why_it_cannot_be_ordered_in_the_sims_words() -> void:
	var ctx := _ctx(WIDTH, 620.0, 6, 20.0)
	var page = ctx.page
	var sim = ctx.sim
	var radio = sim.radio
	eq(page.rows.salvage_bench_home.state.text, "18 scrap, 14 builder-hours", "twenty scrap pay for the bench: its price")
	eq(page.rows.salvage_bench_home.state.get_theme_color("font_color"), Hud.INK2, "in the plain ink")
	for id in ["workshop", "bunk_house", "floodlights", "radio_mast", "watchtower"]:
		var why: String = radio.build_willingness(id).why
		check(why != "", "%s: the radio has a reason (%s)" % [id, why])
		var home: String = String(sim.build.home_for(id))
		eq(page.rows[home].state.text.to_lower(), why.to_lower(), "%s: the slip says the radio's words" % id)
		eq(page.rows[home].state.get_theme_color("font_color"), Hud.WARN, "%s: in amber" % id)
		eq(page.reason_for(id), why, "%s: reason_for is the radio's" % id)
		eq(page.reason_for(home), why, "%s: and so for its home" % id)
	eq(page.rows.workshop_home.state.text, "It needs 30 scrap", "the first letter is a capital, no full stop on a slip")
	# the second of two waits for the first: the buildings module's words
	var second: String = sim.build.why_not("bunk_house_home_2", "bunk_house")
	check(second.begins_with("order the first"), "(the module says: %s)" % second)
	eq(page.rows.bunk_house_home_2.state.text.to_lower(), second.to_lower(), "the second bunk house waits for the first")
	eq(page.reason_for("bunk_house_home_2"), second, "and reason_for says so too")
	# scrap comes in: the reasons go
	sim.stock.scrap = 100.0
	page.refresh()
	for id in ["salvage_bench_home", "workshop_home", "bunk_house_home_1", "floodlights_home", "radio_mast_home"]:
		eq(page.rows[id].state.get_theme_color("font_color"), Hud.INK2, "%s: with 100 scrap nothing is against it" % id)
		eq(page.reason_for(id), "", "%s: no reason" % id)
	eq(page.rows.workshop_home.state.text, "30 scrap, 24 builder-hours", "a price in scrap and in builder-hours")
	_free(ctx)


func test_a_building_that_needs_another_says_so_until_it_stands() -> void:
	var ctx := _ctx(WIDTH, 620.0, 6, 100.0, _needs_path())
	var page = ctx.page
	eq(page.rows.workshop_home.state.text, "It needs the salvage bench first", "the workshop waits for the bench")
	eq(page.reason_for("workshop"), "it needs the salvage bench first", "the sim's words")
	_stand(ctx, "salvage_bench_home", "salvage_bench")
	page.refresh()
	eq(page.rows.workshop_home.state.text, "30 scrap, 24 builder-hours", "the bench stands: the workshop has a price again")
	_free(ctx)


func test_a_site_shows_how_far_along_it_is_and_a_building_that_stands_says_so() -> void:
	var ctx := _ctx()
	var page = ctx.page
	_site(ctx, "workshop_home", "workshop", 10.8)
	_stand(ctx, "bunk_house_home_1", "bunk_house")
	page.refresh()
	eq(page.rows.workshop_home.state.text, "Going up: 45%", "a site says how far it is (10.8 of 24 hours)")
	check(page.rows.workshop_home.meter.visible and absf(page.rows.workshop_home.meter.value - 0.45) < 0.001, "with a meter of it")
	eq(page.rows.bunk_house_home_1.state.text, "Built", "a building says so")
	eq(page.rows.bunk_house_home_1.state.get_theme_color("font_color"), Hud.OK, "in green")
	check(not page.rows.bunk_house_home_1.meter.visible, "with no meter")
	eq(page.rows.bunk_house_home_2.state.text, "24 scrap, 24 builder-hours", "the second bunk house is ordered now the first is")
	ctx.sim.build.plot("workshop_home").site.progress = 23.9
	page.refresh()
	eq(page.rows.workshop_home.state.text, "Going up: 99%", "and it never says a hundred before it is done")
	_free(ctx)


func test_the_page_follows_the_game_and_redraws_only_what_changed() -> void:
	var ctx := _ctx()
	var page = ctx.page
	eq(page.stock_label.text, "Scrap in the stores: 100", "the stores")
	eq(page.housing_label.text, "Beds for 6 people", "the beds")
	var slip_before = page.rows.workshop_home.item
	ctx.sim.stock.scrap = 63.0
	page.refresh()
	eq(page.stock_label.text, "Scrap in the stores: 63", "follows the stores")
	_stand(ctx, "bunk_house_home_1", "bunk_house")
	page.refresh()
	eq(page.housing_label.text, "Beds for 10 people", "and the beds a building gives")
	var sig: String = page._sig
	page.refresh()
	eq(page._sig, sig, "a refresh of what has not changed changes nothing")
	check(page.rows.workshop_home.item == slip_before, "the slips are the same nodes: nothing was rebuilt")
	ctx.sim.stock.scrap = 10.0
	page.refresh()
	eq(page.rows.workshop_home.state.text, "It needs 30 scrap", "a reason that came with the stores")
	_free(ctx)


# --------------------------------------------------------------- the detail --

func test_a_slip_that_is_pressed_opens_under_itself_and_shuts_when_pressed_again() -> void:
	var ctx := _ctx()
	var page = ctx.page
	eq(page.selected, "", "nothing is open to begin with")
	check(not page.detail.is_inside_tree() or not page.detail.visible, "so no detail shows")
	page.rows.workshop_home.button.pressed.emit()
	eq(page.selected, "workshop_home", "the slip is chosen")
	check(page.detail.get_parent() == page.rows.workshop_home.item and page.detail.visible, "and its detail opens under it")
	var all := _texts_of(page.detail)
	check(all.contains("A proper workshop"), "what it gives: %s" % all)
	var pl: Dictionary = ctx.sim.build.plot("workshop_home")
	check(all.contains("Where it goes: %s." % String(pl.name)), "where it goes: %s" % all)
	if String(pl.get("why", "")) != "":
		check(all.contains(String(pl.why)), "and why")
	check(all.contains("30 scrap") and all.contains("24 builder-hours"), "its price")
	page.rows.greenhouse_home.button.pressed.emit()
	eq(page.selected, "greenhouse_home", "another slip: the detail moves")
	check(page.detail.get_parent() == page.rows.greenhouse_home.item, "under it")
	page.rows.greenhouse_home.button.pressed.emit()
	eq(page.selected, "", "pressed again, it shuts")
	check(page.detail.get_parent() == null or not page.detail.visible, "and the detail is gone")
	_free(ctx)


func test_a_building_is_chosen_by_its_id_or_its_homes_and_brought_into_view() -> void:
	var ctx := _ctx()
	var page = ctx.page
	check(page.select_building("workshop"), "a building's id")
	eq(page.selected, "workshop_home", "its home's slip opens")
	check(page.select_building("tents_home_2"), "a home's id")
	eq(page.selected, "tents_home_2", "that slip opens")
	check(not page.select_building("castle"), "no such building: nothing")
	eq(page.selected, "tents_home_2", "and nothing moved")
	# a building with two homes: the next to be ordered, or the one that is going up
	page.select_building("bunk_house")
	eq(page.selected, "bunk_house_home_1", "the first home is the next to be ordered")
	_site(ctx, "bunk_house_home_1", "bunk_house")
	_stand(ctx, "tents_home_1", "tents")
	page.refresh()
	page.select_building("bunk_house")
	eq(page.selected, "bunk_house_home_1", "the site that is going up")
	page.focus_on("tents")
	eq(page.selected, "tents_home_2", "focus_on: the home that can be ordered next")
	page.focus_on("greenhouse_home")
	eq(page.selected, "greenhouse_home", "focus_on takes a home's id too")
	page.focus_on("nothing")
	eq(page.selected, "greenhouse_home", "and a stranger's changes nothing")
	_free(ctx)


func test_the_crew_note_is_advisory_and_a_button_goes_to_the_jobs_page_when_nobody_builds() -> void:
	var ctx := _ctx()
	var page = ctx.page
	var asked: Array = []
	page.options["open_radio"] = func(p, o): asked.append([p, o])
	_nobody_builds(ctx)
	page.refresh()
	page.select_building("salvage_bench")
	var w: Dictionary = ctx.sim.radio.build_willingness("salvage_bench")
	check(String(w.note) != "", "the radio has a note: '%s'" % w.note)
	eq(page.note_label.text, String(w.note), "the page shows the radio's note")
	eq(page.note_label.get_theme_color("font_color"), Hud.INFO, "in blue-grey: advice, not a refusal")
	check(page.note_label.visible and page.jobs_button.visible, "and a button for the Jobs page")
	check(not page.order_button.disabled, "the order is not held up by it")
	page.jobs_button.pressed.emit()
	eq(asked, [["jobs", {"focus": "builders"}]], "it opens the Jobs page on the Builders")
	_someone_builds(ctx)
	page.refresh()
	check(not page.jobs_button.visible, "with a builder on the job there is no button")
	check(not page.order_button.disabled, "and the order stands")
	_free(ctx)


func test_without_a_panel_the_jobs_button_opens_the_old_jobs_screen() -> void:
	var ctx := _ctx()
	var page = ctx.page
	_nobody_builds(ctx)
	page.refresh()
	page.select_building("salvage_bench")
	if ctx.hud.has_method("open_radio"):
		# (the panel is in: the page goes through it; the HUD's own answer is the panel's)
		check(true)
	else:
		page.jobs_button.pressed.emit()
		check(ctx.hud.jobs_screen != null, "the Jobs screen opens when there is no panel")
	_free(ctx)


# ------------------------------------------------------------------- ordering --

func test_ordering_asks_the_radio_pays_the_scrap_and_puts_a_site_up_at_the_home() -> void:
	var ctx := _ctx()
	var page = ctx.page
	var sim = ctx.sim
	_someone_builds(ctx)
	page.refresh()
	page.select_building("salvage_bench")
	var news_before: int = sim.radio.news.size()
	check(not page.order_button.disabled and page.order_button.visible, "Order is on")
	page.order_button.pressed.emit()
	eq(float(sim.stock.scrap), 82.0, "the scrap is paid (18)")
	eq(String(sim.build.plot("salvage_bench_home").site.get("building", "")), "salvage_bench", "a site goes up at its home")
	eq(page.rows.salvage_bench_home.state.text, "Going up: 0%", "the slip says so")
	check(page.answer_label.visible and page.answer_label.text != "", "the answer shows under it: '%s'" % page.answer_label.text)
	check(page.answer_label.text.begins_with("Dez"), "it is the lead builder's: '%s'" % page.answer_label.text)
	eq(page.answer_label.get_theme_color("font_color"), Hud.OK, "willing, in green")
	check(page.cancel_button.visible and not page.order_button.visible, "the detail is a site's now: Cancel, no Order")
	check(sim.radio.news.size() > news_before and String(sim.radio.news[sim.radio.news.size() - 1].kind) == "build", "the radio's log has a 'build' line")
	_free(ctx)


func test_the_answer_goes_after_six_seconds() -> void:
	var ctx := _ctx()
	var page = ctx.page
	page.select_building("salvage_bench")
	page.order("salvage_bench")
	check(page.answer_label.visible, "the answer is up")
	page._process(BuildPage.ANSWER_S - 0.5)
	check(page.answer_label.visible, "still up before the six seconds")
	page._process(1.0)
	check(not page.answer_label.visible and page.answer.is_empty(), "gone after them")
	check(not page.is_processing(), "and the page stops asking for frames")
	_free(ctx)


func test_an_order_for_what_cannot_be_ordered_is_refused_in_amber_and_costs_nothing() -> void:
	var ctx := _ctx(WIDTH, 620.0, 6, 20.0)
	var page = ctx.page
	var sim = ctx.sim
	page.select_building("workshop")
	check(page.order_button.disabled, "the button is off")
	eq(page.order_button.tooltip_text, "It needs 30 scrap.", "with the reason as its tooltip")
	var res: Dictionary = page.order("workshop")
	check(not bool(res.ok), "the radio says no")
	eq(String(res.why), "it needs 30 scrap", "in the buildings module's words")
	eq(float(sim.stock.scrap), 20.0, "nothing was paid")
	check(sim.build.plot("workshop_home").site.is_empty(), "and nothing went up")
	check(page.answer_label.visible and page.answer_label.text == "It needs 30 scrap.", "the answer says why: '%s'" % page.answer_label.text)
	eq(page.answer_label.get_theme_color("font_color"), Hud.WARN, "in amber")
	var none: Dictionary = page.order("castle")
	check(not bool(none.ok) and String(none.why) != "", "a building that is not there is refused too: '%s'" % none.why)
	_free(ctx)


func test_the_second_of_two_waits_for_the_first_and_nobody_picks_which() -> void:
	var ctx := _ctx()
	var page = ctx.page
	var sim = ctx.sim
	page.select_building("bunk_house_home_2")
	check(page.order_button.disabled, "the second bunk house is off")
	eq(page.order_button.tooltip_text, BuildScreen._sentence(sim.build.why_not("bunk_house_home_2", "bunk_house")), "with the module's words")
	page.select_building("bunk_house_home_1")
	check(not page.order_button.disabled, "the first is on")
	page.order_button.pressed.emit()
	check(not sim.build.plot("bunk_house_home_1").site.is_empty() and sim.build.plot("bunk_house_home_2").site.is_empty(), "the first home got the site")
	page.refresh()
	eq(page.rows.bunk_house_home_2.state.text, "24 scrap, 24 builder-hours", "now the second has a price")
	page.select_building("bunk_house_home_2")
	check(not page.order_button.disabled, "and can be ordered")
	page.order_button.pressed.emit()
	check(not sim.build.plot("bunk_house_home_2").site.is_empty(), "it goes on the second home")
	_free(ctx)


func test_a_site_says_who_builds_it_and_for_how_long_and_waits_for_nobody() -> void:
	var ctx := _ctx()
	var page = ctx.page
	_nobody_builds(ctx)
	_site(ctx, "salvage_bench_home", "salvage_bench", 2.0)
	page.refresh()
	page.select_building("salvage_bench_home")
	eq(page.site_percent.text, "14%", "how far (2 of 14 hours)")
	eq(page.site_done.text, "2 of 14 builder-hours done.", "in hours")
	eq(page.site_crew.text, "Nobody is on the Builders job, so nothing will go up.", "nobody builds")
	check(page.jobs_button.visible, "and the way to the Jobs page")
	_someone_builds(ctx)
	page.refresh()
	check(page.site_crew.text.begins_with("Dez: about "), "with Dez on the job: '%s'" % page.site_crew.text)
	check(page.site_crew.text.ends_with("at the present pace."), "at the present pace")
	check(not page.jobs_button.visible, "no button now")
	# a second site waits its turn
	_site(ctx, "greenhouse_home", "greenhouse", 0.0)
	page.refresh()
	page.select_building("greenhouse_home")
	check(page.site_crew.text.begins_with("Waiting its turn"), "the second site waits: '%s'" % page.site_crew.text)
	_free(ctx)


func test_cancel_shows_the_refund_on_the_button_all_of_it_before_any_work_and_half_after() -> void:
	var ctx := _ctx()
	var page = ctx.page
	var sim = ctx.sim
	_site(ctx, "workshop_home", "workshop", 0.0)
	page.refresh()
	page.select_building("workshop_home")
	check(page.cancel_button.visible, "a site has Cancel")
	eq(page.cancel_button.text, "Cancel the order (+30 scrap)", "no work done: all of it on the button")
	check(page.cancel_button.tooltip_text.begins_with("No work has been done"), "and in its tooltip")
	sim.build.plot("workshop_home").site.progress = 1.0
	page.refresh()
	eq(page.cancel_button.text, "Cancel the order (+15 scrap)", "work done: half")
	var before := float(sim.stock.scrap)
	check(page.cancel(), "cancelling works")
	eq(float(sim.stock.scrap), before + 15.0, "half the scrap comes back")
	check(sim.build.plot("workshop_home").site.is_empty(), "the site is gone")
	eq(page.rows.workshop_home.state.text, "30 scrap, 24 builder-hours", "the slip has its price again")
	check(page.answer_label.visible and page.answer_label.text == "Cancelled: 15 scrap back.", "and says what happened: '%s'" % page.answer_label.text)
	check(not page.cancel(), "nothing to cancel any more")
	_free(ctx)


func test_a_building_that_stands_can_be_demolished_in_two_presses() -> void:
	var ctx := _ctx()
	var page = ctx.page
	var sim = ctx.sim
	_stand(ctx, "salvage_bench_home", "salvage_bench")
	page.refresh()
	page.select_building("salvage_bench_home")
	check(page.demolish_button.visible and not page.cancel_button.visible and not page.order_button.visible, "a building has Demolish only")
	eq(page.demolish_button.text, "Demolish (+9 scrap)", "half its scrap on the button")
	check(not page.armed, "not armed")
	page.demolish_button.pressed.emit()
	check(page.armed, "the first press arms it")
	check(sim.build.built("salvage_bench"), "nothing came down")
	check(page.demolish_button.text.begins_with("Press again"), "the button says so: '%s'" % page.demolish_button.text)
	var before := float(sim.stock.scrap)
	page.demolish_button.pressed.emit()
	check(not sim.build.built("salvage_bench") and not page.armed, "the second takes it down")
	eq(float(sim.stock.scrap), before + 9.0, "half the scrap comes back")
	check(page.answer_label.visible and page.answer_label.text == "Taken down: 9 scrap back.", "and says: '%s'" % page.answer_label.text)
	eq(page.rows.salvage_bench_home.state.text, "18 scrap, 14 builder-hours", "the slip is a free home again")
	_free(ctx)


func test_the_second_press_must_come_soon_and_choosing_another_slip_puts_the_first_away() -> void:
	var ctx := _ctx()
	var page = ctx.page
	_stand(ctx, "salvage_bench_home", "salvage_bench")
	_stand(ctx, "greenhouse_home", "greenhouse")
	page.refresh()
	page.select_building("salvage_bench_home")
	page.demolish()
	check(page.armed and page.is_processing(), "armed, and the page counts real time")
	page._process(BuildPage.CONFIRM_S - 0.5)
	check(page.armed, "still armed within the time")
	page._process(1.0)
	check(not page.armed, "too late: disarmed")
	check(page.demolish_button.text.begins_with("Demolish"), "the button is as it was")
	check(ctx.sim.build.built("salvage_bench"), "and nothing came down")
	page.demolish()
	page.select_building("greenhouse_home")
	check(not page.armed, "another slip puts it away")
	page.select_building("salvage_bench_home")
	page.demolish()
	page.rows.salvage_bench_home.button.pressed.emit()
	check(not page.armed, "closing the slip puts it away too")
	check(ctx.sim.build.built("salvage_bench") and ctx.sim.build.built("greenhouse"), "nothing was taken down")
	_free(ctx)


func test_a_building_that_another_needs_cannot_be_demolished_and_says_why() -> void:
	var ctx := _ctx(WIDTH, 620.0, 6, 100.0, _needs_path())
	var page = ctx.page
	_stand(ctx, "salvage_bench_home", "salvage_bench")
	_stand(ctx, "workshop_home", "workshop")
	page.refresh()
	page.select_building("salvage_bench_home")
	check(page.demolish_button.disabled, "the bench is needed by the workshop: Demolish is off")
	eq(page.demolish_button.tooltip_text, "The workshop needs it.", "with the reason as its tooltip")
	check(page.why_label.visible and page.why_label.text == "The workshop needs it.", "and under it: '%s'" % page.why_label.text)
	check(not page.demolish(), "pressing it anyway does nothing")
	check(ctx.sim.build.built("salvage_bench") and not page.armed, "the bench stands, nothing is armed")
	page.select_building("workshop_home")
	check(not page.demolish_button.disabled and not page.why_label.visible, "the workshop itself can come down")
	_free(ctx)


# ------------------------------------------------------------------- the foot --

func test_the_foot_says_how_much_scrap_is_in_the_stores_and_has_the_full_page() -> void:
	var ctx := _ctx()
	var page = ctx.page
	eq(page.stock_label.text, "Scrap in the stores: 100", "the stores")
	check(page.full_button.visible and page.full_button.text == "Full page", "a Full page button")
	check(not page.streets_button.visible, "no 'Streets and map...' in the classic start")
	check(ctx.hud.build_screen == null, "the screen is not up")
	page.full_button.pressed.emit()
	check(ctx.hud.build_screen != null, "Full page opens the modal screen through the HUD")
	check(ctx.hud.modal_open(), "which is the modal one")
	ctx.hud.close_build()
	check(ctx.hud.build_screen == null, "(shut)")
	page.full_page()
	check(ctx.hud.build_screen != null, "full_page() does the same")
	ctx.hud.close_build()
	_free(ctx)


func test_in_a_settlement_game_there_is_a_way_to_the_streets() -> void:
	var ctx := _town_ctx([])
	var page = ctx.page
	check(page.lots_on, "the small start has the lots")
	check(page.streets_button.visible, "'Streets and map...' shows")
	eq(page.streets_button.text, "Streets and map...", "by that name")
	page.streets_button.pressed.emit()
	check(ctx.hud.build_screen != null and ctx.hud.build_screen.selected == BuildScreen.LOTS_PAGE, "it opens the screen on its Lots page")
	ctx.hud.close_build()
	_free(ctx)


func test_the_ring_plots_of_a_claimed_lot_get_slips_under_the_lots_name() -> void:
	var ctx := _town_ctx([])
	var page = ctx.page
	check(not page.rows.has("scrap_yard_home_1"), "a lot that is not claimed has no slips")
	var sim = ctx.sim
	sim.stock.scrap = 500.0
	check(sim.lots.claim("north"), "the north street is claimed")
	page.refresh()
	check(page.rows.has("scrap_yard_home_1"), "its scrap yard has a slip now")
	check(not page.rows.has("scrap_yard_home_2"), "the west road's has not")
	eq(page.rows.scrap_yard_home_1.name.text, String(sim.build.title_of("scrap_yard_home_1")), "named as the module names it")
	check(_texts_of(page.list_box).contains("THE NORTH STREET") or _texts_of(page.list_box).to_lower().contains(String(sim.lots.lot("north").name).to_lower()), "under the lot's name")
	for pl in sim.build.plots():
		if String(pl.kind) == "mouth":
			check(not page.rows.has(String(pl.id)), "no slip for a wall across a street (%s)" % pl.id)
	page.select_building("scrap_yard")
	check(page.selected.begins_with("scrap_yard_home"), "and it can be chosen")
	_free(ctx)


# ---------------------------------------------------------------------- hovers --

func test_hovering_or_choosing_a_slip_marks_its_home_in_the_yard() -> void:
	var ctx := _ctx()
	var page = ctx.page
	await Kit.settle()
	var hud = ctx.hud
	eq(hud.build_hover, {}, "nothing is marked to begin with")
	page.rows.workshop_home.button.mouse_entered.emit()
	eq(hud.build_hover, {"plot": "workshop_home"}, "the pointer on a slip marks its home")
	page.rows.workshop_home.button.mouse_exited.emit()
	eq(hud.build_hover, {}, "and leaving it takes the mark away (nothing is chosen)")
	page.rows.greenhouse_home.button.pressed.emit()
	eq(hud.build_hover, {"plot": "greenhouse_home"}, "choosing a slip marks its home")
	page.rows.workshop_home.button.mouse_entered.emit()
	eq(hud.build_hover, {"plot": "workshop_home"}, "another slip under the pointer: its home")
	page.rows.workshop_home.button.mouse_exited.emit()
	eq(hud.build_hover, {"plot": "greenhouse_home"}, "the chosen one's again when the pointer has left")
	eq(page.marks(), {"plot": "greenhouse_home"}, "the page says what it marks")
	page.rows.greenhouse_home.button.pressed.emit()
	eq(hud.build_hover, {}, "closing the slip clears it")
	_free(ctx)


func test_a_page_that_is_not_shown_marks_nothing_and_marks_again_when_it_is() -> void:
	var ctx := _ctx()
	var page = ctx.page
	page.select_building("workshop")
	eq(ctx.hud.build_hover, {"plot": "workshop_home"}, "the chosen slip is marked")
	page.visible = false
	eq(ctx.hud.build_hover, {}, "hidden: nothing is marked")
	page.rows.workshop_home.button.mouse_entered.emit()
	eq(ctx.hud.build_hover, {}, "and a pointer over a hidden page does not mark")
	page.visible = true
	eq(ctx.hud.build_hover, {"plot": "workshop_home"}, "shown again: the chosen slip is marked")
	ctx.panel.visible = false
	eq(ctx.hud.build_hover, {}, "the panel hidden over it: nothing")
	ctx.panel.visible = true
	eq(ctx.hud.build_hover, {"plot": "workshop_home"}, "and back")
	_free(ctx)


func test_the_modal_screen_closing_does_not_leave_the_yard_unmarked() -> void:
	var ctx := _ctx()
	var page = ctx.page
	page.select_building("workshop")
	ctx.hud.open_build()
	check(ctx.hud.build_screen != null, "the full page is up")
	ctx.hud.close_build()
	eq(ctx.hud.build_hover, {}, "it clears the world's mark as it goes")
	page.refresh()
	eq(ctx.hud.build_hover, {"plot": "workshop_home"}, "the page's own mark comes back at its next refresh")
	_free(ctx)


# ------------------------------------------------------ one truth, no traps --

func test_every_slips_reason_is_the_sims_and_the_radios_order_reaches_the_rules() -> void:
	var ctx := _ctx(WIDTH, 620.0, 6, 0.0)
	var page = ctx.page
	var sim = ctx.sim
	for step in 3:
		for pid in page.rows:
			var bid: String = page.rows[pid].bid
			var m: String = String(page.rows[pid].state.text)
			var home: String = String(sim.build.home_for(bid))
			var pl: Dictionary = sim.build.plot(pid)
			if String(pl.building) != "" or not pl.site.is_empty():
				continue
			var why: String = sim.radio.build_willingness(bid).why if home == pid else sim.build.why_not(pid, bid)
			if why == "":
				check(m.contains("scrap"), "%s: no reason: its price: '%s'" % [pid, m])
			else:
				eq(m.to_lower(), why.to_lower(), "%s: the sim's words" % pid)
		sim.stock.scrap += 40.0
		page.refresh()
	_free(ctx)


func test_every_control_that_is_off_has_its_reason_for_a_tooltip() -> void:
	var ctx := _ctx(WIDTH, 620.0, 6, 25.0, _needs_path())
	var page = ctx.page
	var sim = ctx.sim
	_stand(ctx, "salvage_bench_home", "salvage_bench")
	_site(ctx, "greenhouse_home", "greenhouse", 3.0)
	_stand(ctx, "tents_home_1", "tents")
	page.refresh()
	var seen_off := 0
	for scrap in [0.0, 25.0, 500.0]:
		sim.stock.scrap = scrap
		for builders in [false, true]:
			if builders:
				_someone_builds(ctx)
			else:
				_nobody_builds(ctx)
			for id in page.rows.keys():
				page.select_building(id)
				page.refresh(true)
				for b in _buttons(page):
					if b.disabled:
						seen_off += 1
						check(b.tooltip_text != "", "%s (%.0f scrap): '%s' is off with no tooltip" % [id, scrap, b.text])
	check(seen_off > 10, "the sweep met off controls (%d)" % seen_off)
	# the tooltip of an off Order is the reason, to the letter
	sim.stock.scrap = 5.0
	page.select_building("workshop")
	page.refresh(true)
	eq(page.order_button.tooltip_text, BuildScreen._sentence(page.reason_for("workshop")), "the reason, to the letter")
	_free(ctx)


func test_no_control_of_the_page_takes_the_keyboard() -> void:
	var ctx := _ctx()
	var page = ctx.page
	_site(ctx, "workshop_home", "workshop", 2.0)
	_stand(ctx, "salvage_bench_home", "salvage_bench")
	_nobody_builds(ctx)
	page.refresh()
	for id in page.rows.keys():
		page.select_building(id)
		page.refresh(true)
		for b in _buttons(page):
			eq(b.focus_mode, Control.FOCUS_NONE, "%s: '%s' takes no focus" % [id, b.text])
	eq(page.list_scroll.focus_mode, Control.FOCUS_NONE, "nor does the list")
	_free(ctx)


func test_the_page_never_pauses_the_game_or_makes_a_modal() -> void:
	var ctx := _ctx()
	var page = ctx.page
	ctx.hud.last_speed = 1
	page.select_building("workshop")
	page.order("workshop")
	page.full_button.visible = true
	check(not ctx.hud.modal_open(), "the page is not a modal")
	var speeds: Array = ctx.speeds.duplicate()
	page.refresh(true)
	eq(ctx.speeds, speeds, "and asked for no change of speed")
	_free(ctx)


func test_a_page_with_no_game_yet_does_nothing() -> void:
	var ctx := _ctx()
	var page2 := BuildPage.new()
	ctx.holder.add_child(page2)
	page2.setup(ctx.hud, func(): return null)
	page2.refresh()
	eq(page2.rows.size(), 0, "no slips without a game")
	check(not page2.select_building("workshop"), "nothing to choose")
	eq(page2.order("workshop").get("ok", true), false, "nothing to order")
	check(not page2.cancel() and not page2.demolish(), "nothing to cancel or demolish")
	page2.queue_free()
	_free(ctx)


# ------------------------------------------------------------- looks and size --

func _busy(width: float, height: float, frames: bool = true) -> Dictionary:
	Hud.use_frames = frames
	var ctx := _ctx(width, height, 6, 100.0, _needs_path())
	Hud.use_frames = frames
	var page = ctx.page
	var sim = ctx.sim
	_stand(ctx, "salvage_bench_home", "salvage_bench")
	_site(ctx, "greenhouse_home", "greenhouse", 3.0)
	_nobody_builds(ctx)
	sim.stock.scrap = 25.0
	page.refresh(true)
	return ctx


func test_nothing_on_the_page_is_under_twelve_pixels() -> void:
	var tt := TextTests.new()
	for width in [WIDTH, WIDTH_COMPACT]:
		var ctx := _busy(width, 620.0)
		var page = ctx.page
		for id in page.rows.keys():
			page.select_building(id)
			page.order(String(page.rows[id].bid))
			page.refresh(true)
			eq(tt._small_text(ctx.panel), [], "%.0f px wide, %s chosen" % [width, id])
		_free(ctx)
	check(tt.failures.is_empty(), "(the text check itself)")


func test_every_word_reads_on_the_board_in_either_look() -> void:
	var tt := TextTests.new()
	for frames in [true, false]:
		var ctx := _busy(WIDTH, 700.0, frames)
		var page = ctx.page
		for id in ["salvage_bench_home", "greenhouse_home", "workshop_home", "bunk_house_home_2", "tents_home_1"]:
			page.select_building(id)
			page.order(String(page.rows[id].bid))
			page.refresh(true)
			eq(tt._hard_to_read(ctx.panel, Color.WHITE), [], "%s chosen, %s" % [id, "frames" if frames else "flat"])
		page.select_building("salvage_bench_home")
		page.demolish()
		page.refresh(true)
		eq(tt._hard_to_read(ctx.panel, Color.WHITE), [], "armed, %s" % ("frames" if frames else "flat"))
		_free(ctx)
	Hud.use_frames = true


func _inside(ctx: Dictionary, label: String) -> void:
	var panel: Control = ctx.panel
	var page: Control = ctx.page
	var width: float = ctx.width
	# (a panel grows to what its page asks: the width it was given is the one that counts)
	var frame: StyleBox = panel.get_theme_stylebox("panel")
	var room_w := width - frame.get_margin(SIDE_LEFT) - frame.get_margin(SIDE_RIGHT)
	check(panel.size.x <= width + 0.5, "%s: the panel stayed %.0f wide (it is %.0f)" % [label, width, panel.size.x])
	check(page.get_combined_minimum_size().x <= room_w + 0.5, "%s: the page asks for %.0f of %.0f" % [label, page.get_combined_minimum_size().x, room_w])
	var left: float = panel.get_global_rect().position.x + frame.get_margin(SIDE_LEFT)
	var room := Rect2(left, -100000.0, room_w, 200000.0)
	var bad: Array = []
	_overflow(page, room, bad)
	eq(bad.slice(0, 5), [], "%s: nothing sticks out of the panel's sides (%d do)" % [label, bad.size()])


func _overflow(node: Node, room: Rect2, out: Array) -> void:
	if node is Control and node.is_visible_in_tree():
		var r: Rect2 = node.get_global_rect()
		# (what the list scrolls out of view is clipped: only what is in the viewport counts)
		if r.size.x > 0.0 and (r.position.x < room.position.x - 0.5 or r.end.x > room.end.x + 0.5):
			if not (node is ScrollContainer):
				out.append("%s '%s' at %s" % [node.get_class(), str(node.get("text")).left(24), str(r)])
	for c in node.get_children():
		_overflow(c, room, out)


func test_the_page_fits_the_panels_two_widths() -> void:
	for width in [WIDTH, WIDTH_COMPACT]:
		var ctx := _busy(width, 560.0)
		var page = ctx.page
		await Kit.settle()
		_inside(ctx, "%.0f closed" % width)
		for id in ["salvage_bench_home", "greenhouse_home", "workshop_home", "bunk_house_home_2", "tents_home_1"]:
			page.select_building(id)
			page.order(String(page.rows[id].bid))
			await Kit.settle()
			_inside(ctx, "%.0f %s" % [width, id])
		page.select_building("salvage_bench_home")
		page.demolish()
		await Kit.settle()
		_inside(ctx, "%.0f armed" % width)
		var list_h: float = page.list_scroll.size.y
		check(list_h >= BuildPage.MIN_LIST_H - 1.0, "%.0f: the list has room (%.0f)" % [width, list_h])
		_free(ctx)


func test_the_foot_stays_in_the_panel_and_the_list_scrolls() -> void:
	var ctx := _busy(WIDTH_COMPACT, 420.0)
	var page = ctx.page
	await Kit.settle()
	var room: Rect2 = ctx.panel.get_global_rect()
	var foot: Rect2 = page.full_button.get_global_rect()
	check(room.encloses(foot), "the Full page button is in the panel: %s in %s" % [str(foot), str(room)])
	var bar: ScrollBar = page.list_scroll.get_v_scroll_bar()
	check(bar.max_value > bar.page + 1.0, "eleven slips do not fit 420 px: the list scrolls (%.0f of %.0f)" % [bar.page, bar.max_value])
	page.select_building("tents_home_2")
	await Kit.settle()
	page._reveal()
	await Kit.settle()
	var vis: Rect2 = page.list_scroll.get_global_rect()
	var item: Rect2 = page.rows.tents_home_2.slip.get_global_rect()
	check(vis.intersects(item), "a slip that was chosen far down is scrolled into view")
	_free(ctx)


## The HUD's own radio panel (round 18's radio_panel.gd) with the page in it: the game of `_ctx`, but no panel of ours.
func _panel_ctx(width: int, height: int) -> Dictionary:
	_park_the_mouse()
	var ctx := Kit.build(width, height)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	if not sim.radio.has_method("build_willingness"):
		var fake := FakeRadio.new()
		fake.setup(sim)
		sim.radio = fake
	sim.stock.scrap = 100.0
	Kit.update(ctx)
	return ctx


func test_in_the_radio_panel_the_page_keeps_its_foot_in_view_and_its_list_scrolls() -> void:
	for size in SIZES:
		var ctx := _panel_ctx(size[0], size[1])
		var hud = ctx.hud
		hud.open_radio("build")
		Kit.update(ctx)
		await Kit.settle()
		var label := "%dx%d" % [size[0], size[1]]
		eq(hud.radio_page(), "build", "%s: the Build page is up" % label)
		var page = hud.radio_panel.page_node("build")
		check(page != null and page.has_method("select_building"), "%s: it is ours" % label)
		if page == null or not page.has_method("select_building"):
			_free(ctx)
			continue
		check(not hud.modal_open(), "%s: not a modal" % label)
		for id in ["workshop", "salvage_bench"]:
			page.select_building(id)
			Kit.update(ctx)
			await Kit.settle()
			await Kit.settle()
			var room: Rect2 = hud.radio_panel.get_global_rect()
			var foot: Rect2 = page.full_button.get_global_rect()
			var visible_part: Rect2 = hud.radio_panel.scroll.get_global_rect()
			check(visible_part.encloses(foot), "%s %s: the Full page button is in view: %s in %s" % [label, id, str(foot), str(visible_part)])
			check(room.size.x <= size[0] and room.end.y <= size[1] + 0.5, "%s: the panel is in the window" % label)
			check(page.get_combined_minimum_size().x <= hud.radio_panel.scroll.size.x + 0.5, "%s: the page is not wider than the panel" % label)
		hud.close_radio()
		eq(hud.build_hover, {}, "%s: shut, nothing is marked in the yard" % label)
		_free(ctx)


func test_random_games_and_random_presses_never_break_the_page() -> void:
	for seed_value in [51, 7, 2024]:
		await _fuzz(seed_value)


func _fuzz(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bad: Array = []
	var tt := TextTests.new()
	for round in 6:
		var size: Array = SIZES[rng.randi() % SIZES.size()]
		var width: float = WIDTH_COMPACT if size[0] < 980 else WIDTH
		var ctx := _ctx(width, minf(float(size[1]) - 120.0, 640.0), 6 if rng.randf() < 0.7 else 3, rng.randf() * 160.0, _needs_path() if rng.randf() < 0.3 else "")
		var page = ctx.page
		var sim = ctx.sim
		sim.waves.enabled = false
		var ids: Array = page.rows.keys()
		var buildings: Array = []
		for b in sim.build.catalogue():
			buildings.append(String(b.id))
		await Kit.settle()
		for step in 28:
			var what := rng.randi() % 14
			var id: String = ids[rng.randi() % ids.size()]
			match what:
				0, 1:
					page.rows[id].button.pressed.emit()
				2:
					page.order(buildings[rng.randi() % buildings.size()] if rng.randf() < 0.9 else "castle")
				3:
					page.order_button.pressed.emit()
				4:
					page.cancel()
				5, 6:
					page.demolish()
				7:
					sim.stock.scrap = rng.randf() * 160.0
				8:
					if rng.randf() < 0.5:
						_nobody_builds(ctx)
					else:
						_someone_builds(ctx)
				9:
					var pl: Dictionary = sim.build.plot(id)
					if pl.building == "" and pl.site.is_empty() and sim.build.why_not(id, String(pl.home)) == "":
						sim.build.order(id, String(pl.home))
				10:
					page._process(rng.randf() * 4.0)
				11:
					page.rows[id].button.mouse_entered.emit()
				12:
					for i in 40:
						sim.update(1.0 / 30.0)
					Kit.update(ctx)
				13:
					page.visible = rng.randf() < 0.7
			page.refresh()
			if page.selected != "" and not page.rows.has(page.selected):
				bad.append("round %d step %d: a chosen slip that is not there (%s)" % [round, step, page.selected])
			var open := 0
			for pid in page.rows:
				if page.rows[pid].item.get_child_count() > 1:
					open += 1
			if open > 1:
				bad.append("round %d step %d: %d details open" % [round, step, open])
			if page.visible:
				var tiny: Array = tt._small_text(ctx.panel)
				if not tiny.is_empty():
					bad.append("round %d step %d: %s" % [round, step, str(tiny)])
				for b in _buttons(page):
					if b.disabled and b.tooltip_text == "":
						bad.append("round %d step %d: '%s' is off with no tooltip" % [round, step, b.text])
					if b.focus_mode != Control.FOCUS_NONE:
						bad.append("round %d step %d: '%s' takes the keyboard" % [round, step, b.text])
		page.visible = true
		await Kit.settle()
		_inside(ctx, "fuzz %d round %d at %dx%d" % [seed_value, round, size[0], size[1]])
		_free(ctx)
	eq(bad, [], "fuzz %d" % seed_value)
