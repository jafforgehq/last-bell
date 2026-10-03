extends "res://tests/case.gd"
## Round 6, the Build screen; round 15 made it a short list of buildings: the page where the buildings of the compound (eleven
## slips: the bunk house, the tents and the watchtower have two homes each, numbered) are listed with what each costs, why it cannot be
## had now, how far along it is or that it stands, and, for the one that is chosen, what it gives, costs and where it goes (its
## home's name and why), and the reason it cannot be ordered now (not enough scrap, the most there may be, a building it
## needs first, the first of two not ordered yet) with its Build button off; a site shows how far along it is, who builds it
## and for how long yet (and can be cancelled), and a building shows what it gives (and can be demolished, in two clicks).
## Nobody picks a plot: Build puts the site at the building's home. Opened by N, the hammer in the toolbar or a click on a
## sign in the yard; the rules wait while it is open; the chosen building's home (and the one a slip is pointed at) is marked
## in the world; a small map of the yard shows its pin. The rules behind it are tests/test_build.gd and tests/test_build_homes.gd
## (the core's): here the game is the HUD kit's, whose buildings module and jobs module are the real ones. The key N, the click
## on a sign and the tutorial's lock on the real scene are at the end of this file; the marks drawn in the yard are the view's.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const TextTests := preload("res://tests/test_hud_text.gd")
const Build := preload("res://scripts/sim/build.gd")

const SIZES := [[700, 700], [980, 700], [1280, 800], [1920, 1080]]
const SHORT := [[700, 480], [1280, 500], [980, 420]]    # (eleven slips are 450 px tall: a window this short has to scroll them)


## The mouse put in a corner where no control is (a pointer left over a button by an earlier test would let its
## tooltip come up in this one, and a tooltip is a window of its own with words on it).
func _park_the_mouse() -> void:
	var root: Window = Engine.get_main_loop().root
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(1, 1)
	ev.global_position = Vector2(1, 1)
	root.push_input(ev, true)


## The HUD has seen the game (as main.gd's frames give it) and the screen is open, on `plot` (the default one when
## it is ""). The stores are given enough scrap for most of the catalogue.
func _open(width: int = 1280, height: int = 800, speed: int = 1, plot: String = "", scrap: float = 100.0) -> Dictionary:
	_park_the_mouse()
	var ctx := Kit.build(width, height)
	ctx.sim.stock.scrap = scrap
	Kit.update(ctx, speed)
	ctx.hud.open_build(plot)
	return ctx


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev


## A key as the engine hears it: through the whole input path (the screen's own handler first, then the controls).
func _press(code: Key) -> void:
	var root: Window = Engine.get_main_loop().root
	var down := _key(code)
	root.push_input(down, false)
	var up := _key(code)
	up.pressed = false
	root.push_input(up, false)


func _focus_owner() -> Control:
	return Engine.get_main_loop().root.gui_get_focus_owner()


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
		ids.append(String(pl.id))
	return ids


# ------------------------------------------------------------------ the page --

func test_the_screen_has_a_slip_for_each_building_and_its_words() -> void:
	var ctx := _open()
	var s = ctx.hud.build_screen
	check(s != null, "it opens")
	eq(s.rows.keys(), _plot_ids(ctx), "a slip for each building (each home of a building that has two), in the order of the data")
	eq(s.rows.size(), 11, "eleven: the eight buildings, the bunk house, the tents and the watchtower twice")
	var all := Kit.texts(s)
	for t in ["Build", "BUILDINGS", "Salvage bench", "Greenhouse beds", "Bunk house 1 of 2", "Bunk house 2 of 2", "Tents 1 of 2", "Tents 2 of 2", "Watchtower 2 of 2", "Radio mast"]:
		check(all.has(t), "shows '%s'" % t)
	for id in s.rows:
		check(not s.rows[id].tag.get_parent().visible, "%s: no tag for a kind of lot: nobody picks a plot" % id)
	eq(s.close_button.text, "Close", "and the button at the foot")
	check(ctx.hud.modal_open(), "the HUD calls it a modal")
	eq(ctx.hud.build_hover, {"plot": "salvage_bench_home"}, "the chosen building's home is marked in the world from the start")
	Kit.free_all(ctx)


func test_the_tents_are_on_the_list_with_their_words_and_their_price() -> void:
	var ctx := _open()
	var s = ctx.hud.build_screen
	check(s.rows.has("tents_home_1") and s.rows.has("tents_home_2"), "a slip for each of the two tents")
	eq(Kit.texts(s.rows.tents_home_1.status), ["8 scrap, 6 builder-hours"], "the first tent: what it costs")
	check(not Kit.texts(s.rows.tents_home_2.status).is_empty() and String(Kit.texts(s.rows.tents_home_2.status)[0]) != "Built", "the second says what it needs: %s" % str(Kit.texts(s.rows.tents_home_2.status)))
	s.select_plot("tents_home_1")
	var all := Kit.texts(s)
	check(all.has("Two beds. Cheap, and cold in winter."), "the blurb is the plain one: %s" % str(all.filter(func(t): return String(t).contains("beds"))))
	_stand(ctx, "tents_home_1", "tents")
	Kit.update(ctx)
	eq(Kit.texts(s.housing_label), ["Beds for 8 people"], "a tent adds two beds to the count")
	Kit.free_all(ctx)


func test_the_first_building_not_built_is_chosen_unless_one_is_asked_for_or_going_up() -> void:
	var ctx := _open()
	var s = ctx.hud.build_screen
	eq(s.selected, "salvage_bench_home", "the first building")
	ctx.hud.close_build()
	_stand(ctx, "salvage_bench_home", "salvage_bench")
	ctx.hud.open_build()
	eq(ctx.hud.build_screen.selected, "greenhouse_home", "the first one that is not built when the first is")
	ctx.hud.close_build()
	ctx.sim.build.order("workshop_home", "workshop")
	ctx.hud.open_build()
	eq(ctx.hud.build_screen.selected, "workshop_home", "the building that is going up, when there is one")
	ctx.hud.close_build()
	ctx.hud.open_build("watchtower_home_1")
	eq(ctx.hud.build_screen.selected, "watchtower_home_1", "or the one asked for")
	ctx.hud.close_build()
	ctx.hud.open_build("nowhere")
	eq(ctx.hud.build_screen.selected, "workshop_home", "a home that is not there is not asked for")
	Kit.free_all(ctx)


func test_a_slip_shows_what_it_costs_what_is_going_up_and_what_stands() -> void:
	var ctx := _open()
	var s = ctx.hud.build_screen
	eq(Kit.texts(s.rows.salvage_bench_home.status), ["18 scrap, 14 builder-hours"], "a building not built says what it costs")
	check(not s.rows.salvage_bench_home.meter.visible, "with no meter")
	_site(ctx, "workshop_home", "workshop", 10.8)
	_stand(ctx, "bunk_house_home_1", "bunk_house")
	s.refresh()
	eq(Kit.texts(s.rows.workshop_home.status), ["Going up: 45%"], "a site says how far it is (10.8 of 24 hours)")
	check(s.rows.workshop_home.meter.visible and absf(s.rows.workshop_home.meter.value - 0.45) < 0.001, "with a meter of it")
	eq(Kit.texts(s.rows.bunk_house_home_1.status), ["Built"], "a building says so")
	check(not s.rows.bunk_house_home_1.meter.visible, "with no meter")
	eq(Kit.texts(s.rows.bunk_house_home_2.status), ["24 scrap, 24 builder-hours"], "the second bunk house is ordered now the first is")
	check(not s.rows.salvage_bench_home.meter.visible and Kit.texts(s.rows.salvage_bench_home.status) == ["18 scrap, 14 builder-hours"], "the rest are as they were")
	ctx.sim.build.plot("workshop_home").site.progress = 23.9
	s.refresh()
	eq(Kit.texts(s.rows.workshop_home.status), ["Going up: 99%"], "and it never says a hundred before it is done")
	Kit.free_all(ctx)


func test_the_page_follows_the_game_each_time_the_hud_is_updated() -> void:
	var ctx := _open()
	var s = ctx.hud.build_screen
	eq(Kit.texts(s.stock_label), ["Scrap in the stores: 100"], "the stores")
	ctx.sim.stock.scrap = 63.0
	Kit.update(ctx)
	eq(Kit.texts(s.stock_label), ["Scrap in the stores: 63"], "follow the stores")
	_site(ctx, "salvage_bench_home", "salvage_bench", 7.0)
	Kit.update(ctx)
	eq(Kit.texts(s.rows.salvage_bench_home.status), ["Going up: 50%"], "a site that was put up somewhere else")
	ctx.sim.build.plot("salvage_bench_home").site.progress = 14.0 - 0.1
	_stand(ctx, "bunk_house_home_1", "bunk_house")
	Kit.update(ctx)
	eq(Kit.texts(s.rows.bunk_house_home_1.status), ["Built"], "and a building that was finished")
	eq(Kit.texts(s.housing_label), ["Beds for 10 people"], "with the beds it gives")
	Kit.free_all(ctx)


func test_opening_it_twice_does_not_stack_pages() -> void:
	var ctx := _open()
	var first = ctx.hud.build_screen
	ctx.hud.open_build()
	eq(ctx.hud.build_screen, first, "the same page")
	ctx.hud.open_build("workshop_home")
	eq(first.selected, "workshop_home", "asked for another building, it is that one that is chosen")
	var pages := 0
	for c in ctx.hud.get_children():
		if c.get_script() == first.get_script():
			pages += 1
	eq(pages, 1, "only one in the tree")
	Kit.free_all(ctx)


func test_nothing_opens_while_another_page_is_up_or_in_a_game_without_buildings() -> void:
	var ctx := Kit.build()
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.list = Kit.sample_sites()
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx)
	ctx.hud.open_scavenge(ctx.hud.selection)
	ctx.hud.open_build()
	check(ctx.hud.build_screen == null, "not over the scavenging dialog")
	ctx.hud.scavenge_dialog.cancel()
	ctx.hud.open_jobs()
	ctx.hud.open_build()
	check(ctx.hud.build_screen == null and ctx.hud.jobs_screen != null, "nor over the Jobs screen")
	ctx.hud.open_jobs()
	ctx.hud.close_jobs()
	ctx.hud.open_build()
	check(ctx.hud.build_screen != null, "but once they are shut it opens")
	ctx.hud.open_jobs()
	check(ctx.hud.jobs_screen == null, "and the Jobs screen does not open over it")
	ctx.hud.close_build()
	# an older game with no buildings module
	var real = ctx.hud.sim_ref
	ctx.hud.sim_ref = {"stock": ctx.sim.stock}
	ctx.hud.open_build()
	check(ctx.hud.build_screen == null, "and not in a game with no buildings")
	ctx.hud.sim_ref = real
	Kit.free_all(ctx)


func test_the_page_closes_when_the_run_ends() -> void:
	var ctx := _open()
	ctx.hud.save_paths = []
	ctx.sim.over = "defeat"
	Kit.update(ctx, 0)
	check(ctx.hud.build_screen == null and ctx.hud.game_over != null, "the report card takes its place")
	Kit.free_all(ctx)


# ----------------------------------------------------------- a building not built --

func _shown(s) -> Array:
	var ids: Array = []
	for b in s.build.catalogue():
		if s.entries[b.id].card.visible:
			ids.append(String(b.id))
	return ids


## Chooses a building by its (first free) home, as a player clicks its slip.
func _pick(s, building_id: String) -> void:
	s.select_plot(String(s.build.homes_of(building_id)[0].id))


func test_a_building_not_built_shows_what_it_gives_costs_and_where_it_goes() -> void:
	var ctx := _open()
	var s = ctx.hud.build_screen
	check(s.empty_view.visible and not s.site_view.visible and not s.built_view.visible, "a building not built is offered")
	eq(_shown(s), ["salvage_bench"], "and only that building (the catalogue is the list at the left)")
	for id in ["salvage_bench", "greenhouse", "workshop", "bunk_house", "floodlights", "watchtower", "radio_mast"]:
		_pick(s, id)
		eq(_shown(s), [id], "%s: it is the one shown" % id)
		var b: Dictionary = ctx.sim.build.building(id)
		var words := Kit.texts(s.entries[id].card)
		check(words.has(String(b.blurb)), "%s: what it gives" % id)
		check(words.has("%d scrap" % int(b.scrap)), "%s: its scrap" % id)
		check(words.has("%d builder-hours" % int(b.work)), "%s: its builder-hours" % id)
		eq(s.entries[id].order.text, "Build", "%s: and its Build button" % id)
		var home: Dictionary = ctx.sim.build.homes_of(id)[0]
		eq(Kit.texts(s.plot_title), [ctx.sim.build.title_of(String(home.id))], "%s: the building is named over them" % id)
		var where: String = Kit.texts(s.plot_sub)[0]
		check(where.contains(String(home.name)) and where.contains(String(home.why)), "%s: where it goes, and why: '%s'" % [id, where])
		check(not s.plot_tag.get_parent().visible, "%s: no tag for a kind of lot" % id)
	Kit.free_all(ctx)


func test_what_cannot_be_ordered_now_is_shown_with_its_reason_and_an_off_button() -> void:
	var ctx := _open(1280, 800, 1, "", 20.0)
	var s = ctx.hud.build_screen
	for id in ["salvage_bench", "greenhouse"]:
		_pick(s, id)
		var e: Dictionary = s.entries[id]
		check(not e.order.disabled and not e.why.visible, "%s: twenty scrap pay for it, nothing against it" % id)
		check(e.order.focus_mode == Control.FOCUS_ALL, "%s: and the keyboard can have the button" % id)
	for id in ["workshop", "bunk_house", "floodlights", "radio_mast"]:
		_pick(s, id)
		var e: Dictionary = s.entries[id]
		var cost := int(ctx.sim.build.building(id).scrap)
		check(e.order.disabled, "%s: it is off" % id)
		eq(e.order.tooltip_text, "It needs %d scrap." % cost, "%s: the reason is its tooltip" % id)
		check(e.why.visible and e.why.text == "It needs %d scrap." % cost, "%s: and a line under it: '%s'" % [id, e.why.text])
		eq(e.order.focus_mode, Control.FOCUS_NONE, "%s: the keyboard passes it by" % id)
		check(e.card.visible, "%s: and it is shown all the same" % id)
		var home := String(ctx.sim.build.homes_of(id)[0].id)
		eq(Kit.texts(s.rows[home].status), ["Can't: needs %d scrap" % cost], "%s: and its slip says it in the list" % id)
	# scrap comes in: the reasons go
	ctx.sim.stock.scrap = 100.0
	Kit.update(ctx)
	for id in ["salvage_bench", "greenhouse", "workshop", "bunk_house", "floodlights", "radio_mast"]:
		_pick(s, id)
		check(not s.entries[id].order.disabled and not s.entries[id].why.visible, "%s: with 100 scrap it can be ordered" % id)
	# the most there may be
	_stand(ctx, "workshop_home", "workshop")
	_stand(ctx, "bunk_house_home_1", "bunk_house")
	_stand(ctx, "bunk_house_home_2", "bunk_house")
	Kit.update(ctx)
	eq(Kit.texts(s.rows.workshop_home.status), ["Built"], "a workshop that stands is built, and there is no second")
	eq(Kit.texts(s.rows.bunk_house_home_2.status), ["Built"], "nor a third bunk house")
	eq(ctx.sim.build.why_not_build("workshop"), "there is already one", "one workshop is all there is")
	eq(ctx.sim.build.why_not_build("bunk_house"), "there is already the most (2)", "and two bunk houses")
	_pick(s, "greenhouse")
	check(not s.entries.greenhouse.order.disabled, "the rest are not off")
	Kit.free_all(ctx)


## A game whose catalogue has the workshop needing the salvage bench first (the data has no such building yet).
func _needs_game() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Build.BUILDINGS_PATH))
	for b in parsed.buildings:
		if b.id == "workshop":
			b["requires"] = "salvage_bench"
	var path := "user://test_build_screen_buildings.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(parsed))
	f.close()
	Build.buildings_path = path
	var ctx := _open()
	Build.buildings_path = Build.BUILDINGS_PATH
	return ctx


func test_a_building_that_needs_another_says_so_until_it_stands() -> void:
	var ctx := _needs_game()
	var s = ctx.hud.build_screen
	_pick(s, "workshop")
	eq(s.entries.workshop.why.text, "It needs the salvage bench first.", "the workshop waits for the bench")
	check(s.entries.workshop.order.disabled, "its button is off")
	eq(Kit.texts(s.rows.workshop_home.status), ["Can't: needs the salvage bench first"], "and its slip says so")
	_stand(ctx, "salvage_bench_home", "salvage_bench")
	Kit.update(ctx)
	check(not s.entries.workshop.order.disabled and not s.entries.workshop.why.visible, "the bench stands: the workshop can be ordered")
	Kit.free_all(ctx)


func test_ordering_pays_the_scrap_puts_a_site_up_at_the_home_and_the_detail_shows_it() -> void:
	var ctx := _open()
	var s = ctx.hud.build_screen
	var heard: Array = []
	ctx.hud.on_ui_sound = func(sound_name, _level): heard.append(sound_name)
	_pick(s, "workshop")
	s.entries.workshop.order.pressed.emit()
	near(float(ctx.sim.stock.scrap), 70.0, 1e-9, "thirty scrap are paid")
	eq(ctx.sim.build.plot("workshop_home").site.building, "workshop", "a site stands at the workshop's home")
	check(s.site_view.visible and not s.empty_view.visible and not s.built_view.visible, "the detail shows a site now")
	eq(Kit.texts(s.rows.workshop_home.status), ["Going up: 0%"], "the slip says so")
	eq(Kit.texts(s.stock_label), ["Scrap in the stores: 70"], "and the foot")
	check(not s.error_label.visible, "with nothing said against it")
	eq(heard, ["ui_confirm"], "and the page confirms with its sound")
	eq(s.selected, "workshop_home", "the same building stays chosen")
	Kit.free_all(ctx)


func test_an_order_that_gets_through_for_what_cannot_be_ordered_is_refused_and_says_why() -> void:
	var ctx := _open(1280, 800, 1, "", 5.0)
	var s = ctx.hud.build_screen
	var heard: Array = []
	ctx.hud.on_ui_sound = func(sound_name, _level): heard.append(sound_name)
	_pick(s, "workshop")
	s.entries.workshop.order.pressed.emit()
	check(not s.order("workshop"), "ordering what cannot be")
	near(float(ctx.sim.stock.scrap), 5.0, 1e-9, "nothing is paid")
	check(ctx.sim.build.plot("workshop_home").site.is_empty(), "and no site stands")
	check(s.error_label.visible and s.error_label.text == "It needs 30 scrap.", "a line at the foot says why: '%s'" % s.error_label.text)
	eq(heard, ["ui_error", "ui_error"], "with the error sound each time")
	ctx.sim.stock.scrap = 100.0
	check(s.order("salvage_bench"), "an order that can be placed")
	check(not s.error_label.visible, "and the line goes")
	check(not ctx.sim.build.plot("salvage_bench_home").site.is_empty(), "it went to the salvage bench's own home, whichever building was chosen")
	Kit.free_all(ctx)


func test_the_second_of_two_waits_for_the_first_and_nobody_picks_which() -> void:
	var ctx := _open(1280, 800, 1, "watchtower_home_2")
	var s = ctx.hud.build_screen
	eq(s.selected, "watchtower_home_2", "the second tower is the one chosen")
	eq(Kit.texts(s.plot_title), ["Watchtower 2 of 2"], "numbered")
	check(s.entries.watchtower.card.visible and not s.entries.workshop.card.visible, "the tower is offered, the workshop is not")
	check(s.entries.watchtower.order.disabled, "its Build is off")
	eq(s.entries.watchtower.why.text, "Order the first watchtower first.", "and says why")
	eq(Kit.texts(s.rows.watchtower_home_2.status), ["Can't: after the first one"], "so does its slip")
	_pick(s, "watchtower")
	check(not s.entries.watchtower.order.disabled, "the first can be ordered")
	s.entries.watchtower.order.pressed.emit()
	eq(ctx.sim.build.plot("watchtower_home_1").site.building, "watchtower", "it goes to its first home")
	near(float(ctx.sim.stock.scrap), 64.0, 1e-9, "for its 36 scrap")
	s.select_plot("watchtower_home_2")
	check(not s.entries.watchtower.order.disabled, "and then the second is open")
	Kit.free_all(ctx)


# ------------------------------------------------------------------------ a site --

## The first number in a line of words ("about 1.4 days at the present pace" -> 1.4).
func _number_in(text: String) -> float:
	var rx := RegEx.new()
	rx.compile("[0-9]+(\\.[0-9]+)?")
	var m := rx.search(text)
	return float(m.get_string()) if m != null else -1.0


## What a line like "Walt: about 1.4 days at the present pace." says, in hours of work (a day is twelve).
func _hours_in(text: String) -> float:
	if text.contains("less than an hour"):
		return 0.5
	var n := _number_in(text)
	return n * 12.0 if text.contains("day") else n


func test_a_site_shows_how_far_along_it_is_and_what_it_will_give() -> void:
	var ctx := _open(1280, 800, 1, "workshop_home")
	_site(ctx, "workshop_home", "workshop", 6.0)
	var s = ctx.hud.build_screen
	s.refresh()
	check(s.site_view.visible and not s.empty_view.visible and not s.built_view.visible, "the detail is the site's")
	eq(Kit.texts(s.plot_title), ["Workshop"], "the building")
	eq(Kit.texts(s.site_title), ["Workshop: going up"], "what is going up")
	eq(Kit.texts(s.site_percent), ["25%"], "how far along (6 of 24)")
	near(s.site_meter.value, 0.25, 1e-6, "as a meter too")
	eq(Kit.texts(s.site_done), ["6 of 24 builder-hours done."], "in hours")
	eq(Kit.texts(s.site_gives), [String(ctx.sim.build.building("workshop").blurb)], "and what it will give")
	check(Kit.texts(s.site_view).has("WHAT IT WILL GIVE"), "under its heading")
	ctx.sim.build.plot("workshop_home").site.progress = 10.8
	s.refresh()
	eq(Kit.texts(s.site_done), ["10.8 of 24 builder-hours done."], "a part of an hour shows")
	Kit.free_all(ctx)


func test_a_site_says_who_is_building_it_and_about_how_long_it_will_take_at_their_pace() -> void:
	var ctx := _open(1280, 800, 1, "workshop_home")
	var sim = ctx.sim
	_site(ctx, "workshop_home", "workshop", 6.0)
	var s = ctx.hud.build_screen
	s.refresh()
	var walt = Kit.person(ctx, "walt")
	var hector = Kit.person(ctx, "hector")
	eq(sim.jobs.job_of(walt), "builders", "(Walt is on the Builders job)")
	var rate: float = sim.build.rate(walt)
	var line: String = Kit.texts(s.site_crew)[0]
	check(line.begins_with("Walt: about ") and line.ends_with(" at the present pace."), "Walt, and a time: '%s'" % line)
	check(line.contains("days"), "in days: '%s'" % line)
	near(_number_in(line), snappedf(18.0 / rate / 12.0, 0.1), 0.06, "from the work left (18 hours) and his rate (%.2f an hour)" % rate)
	check(not s.jobs_button.visible, "no button for the Jobs screen: someone is on the job")
	# two builders get through it sooner, and are both named
	check(sim.jobs.assign(hector, "builders"), "Hector joins")
	s.refresh()
	var both: String = Kit.texts(s.site_crew)[0]
	check(both.begins_with("Walt and Hector: about "), "both are named: '%s'" % both)
	check(_hours_in(both) < _hours_in(line), "and it takes less time: '%s' against '%s'" % [both, line])
	near(_hours_in(both), 18.0 / (rate + float(sim.build.rate(hector))), 0.6, "by the sum of their rates")
	# a better builder is quicker
	walt.skills["Building"] = 12
	hector.skills["Building"] = 12
	s.refresh()
	check(_hours_in(Kit.texts(s.site_crew)[0]) < _hours_in(both), "a skilled crew is quicker still: '%s'" % Kit.texts(s.site_crew)[0])
	Kit.free_all(ctx)


func test_a_short_wait_is_told_in_hours_and_a_very_short_one_in_a_word() -> void:
	var ctx := _open(1280, 800, 1, "workshop_home")
	var sim = ctx.sim
	_site(ctx, "workshop_home", "workshop", 0.0)
	var s = ctx.hud.build_screen
	var walt = Kit.person(ctx, "walt")
	var rate: float = sim.build.rate(walt)
	sim.build.plot("workshop_home").site.progress = 24.0 - rate * 5.0
	s.refresh()
	eq(Kit.texts(s.site_crew), ["Walt: about 5 hours at the present pace."], "five hours of work is five hours")
	sim.build.plot("workshop_home").site.progress = 24.0 - rate * 1.2
	s.refresh()
	eq(Kit.texts(s.site_crew), ["Walt: about 1 hour at the present pace."], "an hour and a bit is one hour")
	sim.build.plot("workshop_home").site.progress = 24.0 - rate * 0.4
	s.refresh()
	eq(Kit.texts(s.site_crew), ["Walt: less than an hour at the present pace."], "less is less than an hour")
	sim.build.plot("workshop_home").site.progress = 24.0 - rate * 24.0
	s.refresh()
	check(Kit.texts(s.site_crew)[0].contains("days"), "a day's work is told in days: '%s'" % Kit.texts(s.site_crew)[0])
	Kit.free_all(ctx)


func test_with_nobody_on_the_builders_job_the_site_says_so_and_offers_the_jobs_screen() -> void:
	var ctx := _open(1280, 800, 1, "workshop_home")
	var sim = ctx.sim
	_site(ctx, "workshop_home", "workshop", 6.0)
	var s = ctx.hud.build_screen
	sim.jobs.unassign(Kit.person(ctx, "walt"))
	s.refresh()
	eq(Kit.texts(s.site_crew), ["Nobody is on the Builders job, so nothing will go up."], "nobody is on it")
	check(s.jobs_button.visible, "and a button leads to the Jobs screen")
	eq(s.jobs_button.text, "Open the Jobs screen", "named for what it does")
	# someone on the job but away: they cannot work
	sim.jobs.assign(Kit.person(ctx, "walt"), "builders")
	Kit.person(ctx, "walt").away = {"kind": "party", "site": "pharmacy"}
	s.refresh()
	eq(Kit.texts(s.site_crew), ["Walt cannot build just now (away or hurt)."], "the one on the job is away")
	check(not s.jobs_button.visible, "the job is not empty: no button")
	Kit.person(ctx, "walt").away = null
	Kit.person(ctx, "walt").downed = true
	s.refresh()
	eq(Kit.texts(s.site_crew), ["Walt cannot build just now (away or hurt)."], "or hurt")
	Kit.free_all(ctx)


func test_a_site_that_waits_its_turn_says_which_comes_first() -> void:
	var ctx := _open()
	_site(ctx, "salvage_bench_home", "salvage_bench", 3.0)
	_site(ctx, "workshop_home", "workshop", 0.0)
	var s = ctx.hud.build_screen
	s.select_plot("workshop_home")
	var line: String = Kit.texts(s.site_crew)[0]
	check(line.begins_with("Waiting its turn: the Builders ") and line.contains("salvage bench") and line.contains("By the junk pile"), "the second order waits for the first: '%s'" % line)
	s.select_plot("salvage_bench_home")
	check(Kit.texts(s.site_crew)[0].begins_with("Walt: about "), "and the first has the crew: '%s'" % Kit.texts(s.site_crew)[0])
	Kit.free_all(ctx)


func test_the_night_note_says_the_site_waits_for_the_morning() -> void:
	var ctx := _open(1280, 800, 1, "workshop_home")
	_site(ctx, "workshop_home", "workshop", 6.0)
	var s = ctx.hud.build_screen
	s.refresh(true)
	check(Kit.texts(s.site_note)[0].begins_with("The Builders work by day."), "by day: '%s'" % Kit.texts(s.site_note)[0])
	ctx.sim.minutes = 22.0 * 60.0
	ctx.sim.phase = ctx.sim.phase_at(ctx.sim.minutes)
	ctx.sim.bell_rung = true
	Kit.update(ctx)
	check(Kit.texts(s.site_note)[0].begins_with("It is night:"), "at night: '%s'" % Kit.texts(s.site_note)[0])
	Kit.free_all(ctx)


# ---------------------------------------------------------------- cancel and demolish --

func test_cancel_shows_the_refund_on_the_button_all_of_it_before_any_work_and_half_after() -> void:
	var ctx := _open(1280, 800, 1, "workshop_home")
	var heard: Array = []
	_site(ctx, "workshop_home", "workshop", 0.0)
	var s = ctx.hud.build_screen
	s.refresh()
	eq(s.cancel_button.text, "Cancel the order (+30 scrap)", "no work done: all thirty scrap")
	ctx.sim.build.plot("workshop_home").site.progress = 4.0
	s.refresh()
	eq(s.cancel_button.text, "Cancel the order (+15 scrap)", "work done: half")
	ctx.hud.on_ui_sound = func(sound_name, _level): heard.append(sound_name)
	s.cancel_button.pressed.emit()
	near(float(ctx.sim.stock.scrap), 85.0, 1e-9, "the half comes back (70 + 15)")
	check(ctx.sim.build.plot("workshop_home").site.is_empty(), "the plot is free")
	check(s.empty_view.visible and not s.site_view.visible, "and offers the building again")
	eq(Kit.texts(s.rows.workshop_home.status), ["30 scrap, 24 builder-hours"], "its slip says what it costs again")
	eq(Kit.texts(s.stock_label), ["Scrap in the stores: 85"], "and the foot")
	eq(heard, ["ui_click"], "with a click")
	_site(ctx, "radio_mast_home", "radio_mast", 0.0)
	s.select_plot("radio_mast_home")
	s.cancel_button.pressed.emit()
	near(float(ctx.sim.stock.scrap), 85.0, 1e-9, "a site with no work done gives all back (55 + 30)")
	check(not s.cancel(), "a building with no site has nothing to cancel")
	check(s.error_label.visible, "and says so")
	Kit.free_all(ctx)


func test_a_building_shows_what_it_gives_and_can_be_demolished_in_two_clicks() -> void:
	var ctx := _open(1280, 800, 1, "workshop_home")
	var heard: Array = []
	_stand(ctx, "workshop_home", "workshop")
	var s = ctx.hud.build_screen
	s.refresh(true)
	check(s.built_view.visible and not s.empty_view.visible and not s.site_view.visible, "the detail is the building's")
	eq(Kit.texts(s.built_title), ["Workshop"], "what it is")
	eq(Kit.texts(s.built_blurb), [String(ctx.sim.build.building("workshop").blurb)], "and what it gives")
	eq(s.demolish_button.text, "Demolish (+15 scrap)", "half of its thirty scrap comes back")
	ctx.hud.on_ui_sound = func(sound_name, _level): heard.append(sound_name)
	s.demolish_button.pressed.emit()
	check(s.armed, "the first click arms the button")
	eq(s.demolish_button.text, "Click again to demolish (+15 scrap)", "and the button says so")
	check(ctx.sim.build.built("workshop"), "nothing is taken down yet")
	near(float(ctx.sim.stock.scrap), 100.0, 1e-9, "and nothing is paid")
	s.demolish_button.pressed.emit()
	check(not ctx.sim.build.built("workshop"), "the second takes it down")
	near(float(ctx.sim.stock.scrap), 115.0, 1e-9, "and half of the scrap comes back")
	check(not s.armed and s.empty_view.visible, "the building is offered again")
	eq(Kit.texts(s.rows.workshop_home.status), ["30 scrap, 24 builder-hours"], "its slip says what it costs again")
	eq(heard, ["ui_click", "ui_confirm"], "a click, then the confirmation")
	Kit.free_all(ctx)


func test_the_second_click_must_come_soon_and_choosing_another_plot_puts_the_first_away() -> void:
	var ctx := _open(1280, 800, 1, "workshop_home")
	_stand(ctx, "workshop_home", "workshop")
	_stand(ctx, "greenhouse_home", "greenhouse")
	var s = ctx.hud.build_screen
	s.refresh(true)
	s.demolish_button.pressed.emit()
	check(s.armed, "armed")
	s._process(2.0)
	check(s.armed and s.demolish_button.text.begins_with("Click again"), "two seconds on, it still waits")
	s._process(1.5)
	check(not s.armed, "past the few seconds it is as it was")
	eq(s.demolish_button.text, "Demolish (+15 scrap)", "and says Demolish again")
	s.demolish_button.pressed.emit()
	check(ctx.sim.build.built("workshop") and s.armed, "a click after that only arms it again")
	s.select_plot("greenhouse_home")
	check(not s.armed, "another plot chosen puts it away")
	s.select_plot("workshop_home")
	eq(s.demolish_button.text, "Demolish (+15 scrap)", "so that a click on another building's button is never the second click of this one")
	check(ctx.sim.build.built("workshop") and ctx.sim.build.built("greenhouse"), "both stand")
	# Esc puts it away first and closes second
	s.demolish_button.pressed.emit()
	check(s.armed, "armed again")
	s._input(_key(KEY_ESCAPE))
	check(not s.armed and ctx.hud.build_screen == s, "the first Esc puts it away and leaves the page")
	s._input(_key(KEY_ESCAPE))
	check(ctx.hud.build_screen == null, "the second closes the page")
	Kit.free_all(ctx)


func test_a_building_that_another_needs_cannot_be_demolished_and_says_why() -> void:
	var ctx := _needs_game()
	_stand(ctx, "salvage_bench_home", "salvage_bench")
	_stand(ctx, "workshop_home", "workshop")
	var s = ctx.hud.build_screen
	s.select_plot("salvage_bench_home")
	check(s.demolish_button.disabled, "the bench is needed by the workshop: Demolish is off")
	eq(s.demolish_button.tooltip_text, "The workshop needs it.", "with the reason as its tooltip")
	check(s.demolish_why.visible and s.demolish_why.text == "The workshop needs it.", "and under it: '%s'" % s.demolish_why.text)
	check(not s.demolish(), "pressing it anyway does nothing")
	check(ctx.sim.build.built("salvage_bench") and not s.armed, "the bench stands, nothing is armed")
	s.select_plot("workshop_home")
	check(not s.demolish_button.disabled and not s.demolish_why.visible, "the workshop itself can come down")
	Kit.free_all(ctx)


func test_the_foot_says_how_much_scrap_is_in_the_stores_and_how_many_the_beds_are_for() -> void:
	var ctx := _open()
	var s = ctx.hud.build_screen
	eq(Kit.texts(s.stock_label), ["Scrap in the stores: 100"], "the stores")
	eq(Kit.texts(s.housing_label), ["Beds for 6 people"], "the school's own six")
	_stand(ctx, "bunk_house_home_1", "bunk_house")
	_stand(ctx, "bunk_house_home_2", "bunk_house")
	Kit.update(ctx)
	eq(Kit.texts(s.housing_label), ["Beds for 14 people"], "and four more for each bunk house")
	ctx.sim.stock.scrap = 12.7
	Kit.update(ctx)
	eq(Kit.texts(s.stock_label), ["Scrap in the stores: 12"], "whole scrap")
	Kit.free_all(ctx)


# ------------------------------------------------------------- closing and the speed --

func test_the_page_pauses_the_game_and_gives_the_speed_back() -> void:
	var ctx := Kit.build()
	Kit.update(ctx, 2)
	ctx.hud.open_build()
	eq(ctx.speeds, [0], "paused on open")
	ctx.hud.build_screen.close_button.pressed.emit()
	eq(ctx.speeds, [0, 2], "and back to the old speed on Close")
	check(ctx.hud.build_screen == null and not ctx.hud.modal_open(), "the page is gone")
	ctx.speeds.clear()
	ctx.hud.open_build()
	ctx.hud.build_screen._input(_key(KEY_ESCAPE))
	eq(ctx.speeds, [0, 2], "Esc closes it the same way")
	ctx.speeds.clear()
	ctx.hud.open_build()
	ctx.hud.build_screen._input(_key(KEY_N))
	eq(ctx.speeds, [0, 2], "so does N")
	ctx.speeds.clear()
	ctx.hud.toggle_build()
	check(ctx.hud.build_screen != null, "toggle opens it")
	ctx.hud.toggle_build()
	check(ctx.hud.build_screen == null, "and shuts it")
	eq(ctx.speeds, [0, 2], "with the same pauses")
	ctx.speeds.clear()
	Kit.update(ctx, 0)
	ctx.hud.open_build()
	ctx.hud.close_build()
	eq(ctx.speeds, [], "a game that was paused stays paused")
	Kit.free_all(ctx)


func test_the_page_plays_the_menu_sounds() -> void:
	var ctx := Kit.build()
	ctx.sim.stock.scrap = 100.0
	Kit.update(ctx)
	var heard: Array = []
	ctx.hud.on_ui_sound = func(sound_name, _level): heard.append(sound_name)
	ctx.hud.open_build()
	eq(heard, ["ui_open"], "opening it")
	var s = ctx.hud.build_screen
	heard.clear()
	s.rows.greenhouse_home.row.pressed.emit()
	eq(heard, ["ui_click"], "choosing a building")
	heard.clear()
	s.rows.greenhouse_home.row.focus_entered.emit()
	eq(heard, [], "the keyboard arriving on a slip is quiet: a press that follows is the click")
	s.rows.greenhouse_home.row.pressed.emit()
	eq(heard, ["ui_click"], "(a click puts the keyboard on the slip first, then presses it)")
	heard.clear()
	s.order("greenhouse")
	eq(heard, ["ui_confirm"], "an order")
	heard.clear()
	s.cancel_button.pressed.emit()
	eq(heard, ["ui_click"], "a cancel")
	heard.clear()
	ctx.sim.stock.scrap = 1.0
	s.order("greenhouse")
	eq(heard, ["ui_error"], "an order that is refused")
	heard.clear()
	s.close_button.pressed.emit()
	eq(heard, ["ui_close"], "closing it")
	# nothing listening: nothing breaks
	ctx.hud.on_ui_sound = Callable()
	ctx.hud.open_build()
	ctx.hud.close_build()
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the marks --

func test_hovering_a_slip_marks_its_home_in_the_world_and_leaving_goes_back_to_the_chosen_one() -> void:
	var ctx := Kit.build()
	Kit.update(ctx)
	var marks: Array = []
	ctx.hud.on_build_hover = func(d): marks.append(d.duplicate())
	ctx.hud.open_build()
	var s = ctx.hud.build_screen
	eq(ctx.hud.build_hover, {"plot": "salvage_bench_home"}, "open: the chosen building's home is marked, the first building's")
	s.rows.bunk_house_home_1.row.mouse_entered.emit()
	eq(marks.back(), {"plot": "bunk_house_home_1"}, "the pointer on a slip marks its home")
	eq(ctx.hud.build_hover, {"plot": "bunk_house_home_1"}, "and the HUD remembers it")
	eq(s.marks(), {"plot": "bunk_house_home_1"}, "and the page says so")
	s.rows.bunk_house_home_1.row.mouse_exited.emit()
	eq(marks.back(), {"plot": "salvage_bench_home"}, "the pointer leaving marks the chosen building's home again")
	s.rows.workshop_home.row.focus_entered.emit()
	eq(marks.back(), {"plot": "workshop_home"}, "the keyboard on a slip marks it too")
	eq(s.selected, "workshop_home", "and chooses it")
	s.rows.workshop_home.row.focus_exited.emit()
	eq(marks.back(), {"plot": "workshop_home"}, "and when it leaves, the chosen one stays marked")
	# the pointer moves from one slip to the next: the first lets go, then the second marks
	s.rows.watchtower_home_1.row.mouse_entered.emit()
	s.rows.floodlights_home.row.mouse_entered.emit()
	s.rows.watchtower_home_1.row.mouse_exited.emit()
	eq(ctx.hud.build_hover, {"plot": "floodlights_home"}, "a slip that is left after another was entered does not let go of the other")
	# choosing a building (the map, a sign in the yard) marks its home though no slip is pointed at
	s.select_plot("radio_mast_home")
	eq(ctx.hud.build_hover, {"plot": "radio_mast_home"}, "a building chosen another way is marked")
	ctx.hud.close_build()
	eq(marks.back(), {}, "closed: nothing is marked")
	eq(ctx.hud.build_hover, {}, "and the HUD remembers it")
	# the controls that are freed with the page may still say they lost the pointer or the keyboard
	s.rows.floodlights_home.row.mouse_exited.emit()
	s.rows.salvage_bench_home.row.focus_exited.emit()
	s.rows.salvage_bench_home.row.mouse_entered.emit()
	s.show_mark("workshop_home")
	eq(ctx.hud.build_hover, {}, "and it stays so")
	Kit.free_all(ctx)


# ------------------------------------------------------------------- the keyboard --

func test_every_control_can_have_the_keyboard_unless_it_is_off() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	var buttons := 0
	for c in s.find_children("*", "Button", true, false):
		if c.disabled:
			eq(c.focus_mode, Control.FOCUS_NONE, "a button that is off is passed by: '%s'" % c.text)
		else:
			buttons += 1
			eq(c.focus_mode, Control.FOCUS_ALL, "the button '%s' can have the keyboard" % c.text)
	check(buttons >= _plot_ids(ctx).size() + 1, "the slips, the Orders that can be placed and Close: %d" % buttons)
	check(_focus_owner() == null, "nothing has the keyboard when the page opens")
	_press(KEY_TAB)
	check(_focus_owner() == s.rows.salvage_bench_home.row, "the first Tab puts it on the building that is chosen")
	Kit.free_all(ctx)


func test_the_arrows_choose_a_building_and_the_detail_follows() -> void:
	var ctx := _open()
	await Kit.settle()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_press(KEY_DOWN)
	eq(_focus_owner(), s.rows.salvage_bench_home.row, "an arrow with nothing focused puts it on the chosen building")
	_press(KEY_DOWN)
	eq(_focus_owner(), s.rows.greenhouse_home.row, "the next arrow goes down the buildings")
	eq(s.selected, "greenhouse_home", "and the building it lands on is the one chosen")
	eq(Kit.texts(s.plot_title), ["Greenhouse beds"], "with the detail showing it")
	_press(KEY_TAB)
	eq(_focus_owner(), s.rows.workshop_home.row, "Tab goes on to the next building")
	eq(s.selected, "workshop_home", "and chooses it")
	_press(KEY_UP)
	eq(_focus_owner(), s.rows.greenhouse_home.row, "an arrow up goes back")
	eq(ctx.hud.build_hover, {"plot": "greenhouse_home"}, "and the home of the building under the keyboard is marked in the world")
	Kit.free_all(ctx)


func test_enter_or_right_goes_to_the_buttons_of_the_detail_and_enter_there_builds() -> void:
	var ctx := _open()
	await Kit.settle()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_press(KEY_TAB)
	eq(_focus_owner(), s.rows.salvage_bench_home.row, "on the first building")
	_press(KEY_RIGHT)
	eq(_focus_owner(), s.entries.salvage_bench.order, "Right goes to its Build button")
	_press(KEY_LEFT)
	eq(_focus_owner(), s.rows.salvage_bench_home.row, "Left comes back to the building's slip")
	_press(KEY_ENTER)
	eq(_focus_owner(), s.entries.salvage_bench.order, "Enter on a slip goes to the button too")
	_press(KEY_ENTER)
	await Kit.settle()
	eq(ctx.sim.build.plot("salvage_bench_home").site.building, "salvage_bench", "Enter on Build orders it, at its home")
	near(float(ctx.sim.stock.scrap), 82.0, 1e-9, "for its scrap")
	eq(_focus_owner(), s.rows.salvage_bench_home.row, "and the keyboard is back on the slip, which says Going up")
	eq(Kit.texts(s.rows.salvage_bench_home.status), ["Going up: 0%"], "the slip's words")
	# a site's buttons are for the keyboard too: Walt is on the Builders job, so the first is Cancel
	_press(KEY_RIGHT)
	eq(_focus_owner(), s.cancel_button, "Right goes to the site's Cancel")
	_press(KEY_ENTER)
	await Kit.settle()
	check(ctx.sim.build.plot("salvage_bench_home").site.is_empty(), "Enter on Cancel cancels")
	near(float(ctx.sim.stock.scrap), 100.0, 1e-9, "and no work was done: all the scrap is back")
	eq(_focus_owner(), s.rows.salvage_bench_home.row, "with the keyboard on the slip again")
	Kit.free_all(ctx)


func test_a_building_with_nothing_to_press_keeps_the_keyboard_on_its_slip() -> void:
	var ctx := _open(1280, 800, 1, "", 1.0)
	await Kit.settle()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_press(KEY_TAB)
	_press(KEY_RIGHT)
	eq(_focus_owner(), s.rows.salvage_bench_home.row, "with a single scrap nothing can be ordered: Right has nowhere to go")
	_press(KEY_ENTER)
	eq(_focus_owner(), s.rows.salvage_bench_home.row, "nor does Enter")
	Kit.free_all(ctx)


## Where main.gd's _unhandled_input would be: it writes down the keys that reach it.
class Listener:
	extends Node
	var heard: Array = []

	func _unhandled_input(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed:
			heard.append(ev.keycode)


func test_escape_and_n_close_the_page_and_a_held_key_shuts_one_thing_not_two() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_press(KEY_TAB)
	_press(KEY_ESCAPE)
	check(ctx.hud.build_screen == null, "Esc shuts the page")
	ctx.hud.open_build()
	s = ctx.hud.build_screen
	var echo := _key(KEY_ESCAPE)
	echo.echo = true
	s._input(echo)
	check(ctx.hud.build_screen == s, "the key repeating does nothing")
	var n_echo := _key(KEY_N)
	n_echo.echo = true
	s._input(n_echo)
	check(ctx.hud.build_screen == s, "nor does a repeating N")
	var with_ctrl := _key(KEY_N)
	with_ctrl.ctrl_pressed = true
	s._input(with_ctrl)
	check(ctx.hud.build_screen == s, "and Ctrl+N is not N")
	s._input(_key(KEY_N))
	check(ctx.hud.build_screen == null, "N shuts it")
	Kit.free_all(ctx)


func test_the_game_does_not_hear_the_keys_while_the_page_is_up() -> void:
	var ctx := _open()
	await Kit.settle()
	var listener := Listener.new()
	Engine.get_main_loop().root.add_child(listener)
	_press(KEY_R)
	_press(KEY_M)
	_press(KEY_B)
	eq(listener.heard.filter(func(k): return k == KEY_R or k == KEY_M or k == KEY_B), [], "R, M and B are the page's, not the game's")
	_press(KEY_N)
	eq(listener.heard.filter(func(k): return k == KEY_N), [], "nor is the N that closes it")
	await Kit.settle()
	check(ctx.hud.build_screen == null, "(it is shut)")
	_press(KEY_R)
	eq(listener.heard.filter(func(k): return k == KEY_R), [KEY_R], "once the page is gone the keys reach the game again")
	listener.free()
	Kit.free_all(ctx)


# ---------------------------------------------------------------------- the mouse --

func test_the_mouse_chooses_a_building_builds_and_closes() -> void:
	var ctx := _open()
	await Kit.settle()
	await Kit.settle()
	var s = ctx.hud.build_screen
	Kit.click_on(s.rows.workshop_home.row)
	await Kit.settle()
	eq(s.selected, "workshop_home", "a click on a slip chooses the building")
	eq(Kit.texts(s.plot_title), ["Workshop"], "and the detail follows")
	await Kit.settle()
	Kit.click_on(s.entries.workshop.order)
	await Kit.settle()
	eq(ctx.sim.build.plot("workshop_home").site.building, "workshop", "a click on Build orders, at its home")
	check(s.site_view.visible, "and the detail is the site's")
	await Kit.settle()
	Kit.click_on(s.cancel_button)
	await Kit.settle()
	check(ctx.sim.build.plot("workshop_home").site.is_empty(), "a click on Cancel cancels")
	Kit.click_on(s.close_button)
	check(ctx.hud.build_screen == null, "a click on Close closes")
	Kit.free_all(ctx)


func test_clicks_do_not_reach_the_game_behind_the_page() -> void:
	var ctx := _open()
	Kit.select(ctx, Kit.person(ctx, "ana"))
	await Kit.settle()
	var behind: Button = Kit.gizmo(ctx, "draft")
	Kit.click_on(behind)
	eq(ctx.pressed, [], "the Draft button under the page does not fire")
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the Jobs screen --

func test_the_jobs_button_gives_way_to_the_jobs_screen_with_the_builders_marked_and_the_pause_kept() -> void:
	var ctx := Kit.build()
	ctx.sim.stock.scrap = 100.0
	Kit.update(ctx, 2)
	_site(ctx, "workshop_home", "workshop", 3.0)
	ctx.sim.jobs.unassign(Kit.person(ctx, "walt"))
	ctx.hud.open_build()
	var s = ctx.hud.build_screen
	eq(ctx.speeds, [0], "paused by the Build screen")
	check(s.jobs_button.visible, "nobody is on the Builders job: there is the button")
	s.jobs_button.pressed.emit()
	check(ctx.hud.build_screen == null and ctx.hud.jobs_screen != null, "the Jobs screen has taken its place")
	eq(ctx.speeds, [0], "the rules never ran in between: no speed was given back")
	eq(ctx.hud.jobs_screen.marks().station, "builders", "the Builders' station is marked in the yard")
	ctx.hud.close_jobs()
	eq(ctx.speeds, [0, 2], "closing the Jobs screen gives the speed back")
	Kit.free_all(ctx)


func test_if_the_jobs_screen_will_not_open_the_speed_comes_back() -> void:
	var ctx := Kit.build()
	ctx.sim.stock.scrap = 100.0
	Kit.update(ctx, 3)
	_site(ctx, "workshop_home", "workshop", 3.0)
	ctx.sim.jobs.unassign(Kit.person(ctx, "walt"))
	ctx.hud.on_jobs = func(): pass
	ctx.hud.open_build()
	ctx.hud.build_screen.jobs_button.pressed.emit()
	check(ctx.hud.build_screen == null and ctx.hud.jobs_screen == null, "the lock said no: neither page is up")
	eq(ctx.speeds, [0, 3], "and the game runs on as it did")
	Kit.free_all(ctx)


# ------------------------------------------------------------------ the toolbar --

func test_the_toolbar_has_a_hammer_after_the_clipboard_that_says_what_it_is() -> void:
	var ctx := Kit.build()
	var h = ctx.hud
	check(h.build_button != null, "there is a Build button")
	var row: Node = h.build_button.get_parent()
	eq(h.jobs_button.get_parent(), row, "in the toolbar's row, with the Jobs key")
	eq(h.build_button.get_index(), h.jobs_button.get_index() + 1, "right after it")
	eq(h.menu_button.get_index(), h.build_button.get_index() + 1, "the menu stays last")
	eq(h.build_button.tooltip_text, Hud.BUILD_TIP, "named, with its key")
	check(h.build_button.tooltip_text.contains("pick a building") and not h.build_button.tooltip_text.contains("plot"), "in words about buildings, not plots")
	eq(h.build_button.get_meta("icon").texture, h.icons["build"], "wearing the hammer")
	eq(h.build_button.custom_minimum_size, h.help_button.custom_minimum_size, "as big as its neighbours")
	eq(h.build_button.focus_mode, Control.FOCUS_NONE, "and, like them, not a stop for the keyboard")
	Kit.update(ctx)
	h.build_button.pressed.emit()
	check(h.build_screen != null, "with nobody listening a press opens the screen")
	h.build_button.pressed.emit()
	check(h.build_screen == null, "and the next shuts it")
	var asked: Array = []
	h.on_build = func(): asked.append(true)
	h.build_button.pressed.emit()
	eq(asked.size(), 1, "main.gd is asked when it listens")
	check(h.build_screen == null, "and the HUD leaves it to main.gd")
	Kit.free_all(ctx)


func test_the_hammer_is_white_on_clear_and_64_pixels_like_the_other_icons() -> void:
	var path: String = Hud.EXTRA_ICONS["build"]
	check(ResourceLoader.exists(path), "the picture is imported: %s" % path)
	var tex: Texture2D = load(path)
	check(tex != null, "it loads")
	if tex == null:
		return
	eq(tex.get_size(), Vector2(64, 64), "64 by 64, as every icon is")
	var img: Image = tex.get_image()
	var opaque := 0
	var tinted := 0
	var left := 64
	var right := 0
	var top := 64
	var bottom := 0
	for y in 64:
		for x in 64:
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				opaque += 1
			if c.a > 0.02:
				left = mini(left, x)
				right = maxi(right, x)
				top = mini(top, y)
				bottom = maxi(bottom, y)
			if c.a > 0.02 and (c.r < 0.98 or c.g < 0.98 or c.b < 0.98):
				tinted += 1
	check(opaque > 300 and opaque < 2400, "a sensible amount of ink: %d px" % opaque)
	eq(tinted, 0, "pure white with alpha: the HUD tints it")
	check(left >= 3 and top >= 3 and right <= 60 and bottom <= 60, "inside the margin of three: x %d to %d, y %d to %d" % [left, right, top, bottom])
	var repair: Image = load("res://assets/ui/icons/repair.png").get_image()
	var same := 0
	for y in 64:
		for x in 64:
			if (img.get_pixel(x, y).a > 0.5) == (repair.get_pixel(x, y).a > 0.5):
				same += 1
	check(same < 3600, "and not the Repair order's mallet (the two pictures differ in %d pixels)" % (4096 - same))


func test_the_tutorials_lock_ghosts_the_build_button_unless_the_step_teaches_it() -> void:
	var ctx := Kit.build()
	var b: Button = ctx.hud.build_button
	check(b.modulate.a > 0.99, "bright with no lock")
	ctx.hud.set_locked(func(kind: String, _arg): return kind == "build")
	check(b.modulate.a > 0.9, "bright while the step teaches it")
	ctx.hud.set_locked(func(_kind: String, _arg): return false)
	check(b.modulate.a < 0.5, "a ghost while it does not")
	eq(b.mouse_default_cursor_shape, Control.CURSOR_FORBIDDEN, "with a cursor that says no")
	check(not b.disabled, "but it can still be pressed: the game refuses and says why")
	ctx.hud.set_locked(Callable())
	check(b.modulate.a > 0.99 and b.mouse_default_cursor_shape == Control.CURSOR_ARROW, "and as it was once the lock is lifted")
	Kit.free_all(ctx)


func test_the_parts_of_the_page_can_be_pointed_at_by_name() -> void:
	var ctx := _open()
	await Kit.settle()
	await Kit.settle()
	var h = ctx.hud
	var s = h.build_screen
	for pair in [["build", h.build_button], ["build.screen", s.panel], ["build.close", s.close_button], ["build.detail", s.detail],
			["build.row:salvage_bench_home", s.rows.salvage_bench_home.row], ["build.row:watchtower_home_1", s.rows.watchtower_home_1.row], ["build.order:salvage_bench", s.entries.salvage_bench.order]]:
		var r: Rect2 = h.anchor_rect(pair[0])
		check(r.size != Vector2.ZERO and r == Kit.rect(pair[1]), "%s is found: %s" % [pair[0], str(r)])
	eq(h.anchor_rect("build.cancel"), Rect2(), "no site, no Cancel")
	eq(h.anchor_rect("build.demolish"), Rect2(), "no building, no Demolish")
	eq(h.anchor_rect("build.order:watchtower"), Rect2(), "a building that is not the chosen one is not shown")
	eq(h.anchor_rect("build.row:nowhere"), Rect2(), "a building that is not there")
	eq(h.anchor_rect("build.order:castle"), Rect2(), "a building that is not")
	s.order("salvage_bench")
	await Kit.settle()
	check(h.anchor_rect("build.cancel").size != Vector2.ZERO, "a site has its Cancel")
	eq(h.anchor_rect("build.jobs"), Rect2(), "and no button for the Jobs screen while someone is on the Builders job")
	ctx.sim.jobs.unassign(Kit.person(ctx, "walt"))
	s.refresh()
	await Kit.settle()
	check(h.anchor_rect("build.jobs").size != Vector2.ZERO, "with nobody on it there is one")
	_stand(ctx, "greenhouse_home", "greenhouse")
	s.select_plot("greenhouse_home")
	await Kit.settle()
	check(h.anchor_rect("build.demolish").size != Vector2.ZERO and h.anchor_rect("build.cancel") == Rect2(), "a building has its Demolish, and no Cancel")
	h.close_build()
	eq(h.anchor_rect("build.close"), Rect2(), "and nothing once the page is shut")
	check(h.anchor_rect("build").size != Vector2.ZERO, "(the toolbar's own key stays)")
	Kit.free_all(ctx)


# ------------------------------------------------------------- the page fits --

## Everything that is wrong with how the page sits in a window of this size, as words (none: it fits).
func _misfits(ctx: Dictionary, size: Array) -> Array:
	var bad: Array = []
	var s = ctx.hud.build_screen
	var win := Rect2(0, 0, size[0], size[1])
	var panel := Kit.rect(s.panel)
	if panel.size == Vector2.ZERO or not win.encloses(panel.grow(-0.5)):
		bad.append("the page %s is not inside the window" % str(panel))
	var columns := {"plots": Kit.rect(s.list_scroll), "detail": Kit.rect(s.detail_scroll)}
	for name in columns:
		if columns[name].size == Vector2.ZERO or not panel.encloses(columns[name]):
			bad.append("the %s column %s is not inside the page %s" % [name, str(columns[name]), str(panel)])
	bad.append_array(Kit.overlaps(columns))
	var foot := {"close": Kit.rect(s.close_button), "stock": Kit.rect(s.stock_label), "beds": Kit.rect(s.housing_label), "hint": Kit.rect(s.hint_label)}
	for name in foot:
		if foot[name].size == Vector2.ZERO or not panel.encloses(foot[name]):
			bad.append("the %s at the foot is not in the page: %s" % [name, str(foot[name])])
	bad.append_array(Kit.overlaps(foot))
	for name in columns:
		if columns[name].end.y > Kit.rect(s.close_button).position.y + 0.5 and columns[name].end.x > Kit.rect(s.close_button).position.x:
			bad.append("the %s column runs into the buttons at the foot" % name)
	# nothing is wider than the room it is given
	for sc in [s.list_scroll, s.detail_scroll]:
		var box: Control = s.list_box if sc == s.list_scroll else s.detail_box
		if box.get_combined_minimum_size().x > sc.size.x + 0.5:
			bad.append("a column asks for %.0f px and has %.0f" % [box.get_combined_minimum_size().x, sc.size.x])
	# a slip: its name and its tag apart and inside it, as wide as the column
	var plots: Rect2 = columns.plots
	for id in s.rows:
		var r: Dictionary = s.rows[id]
		var slip := Kit.rect(r.row)
		if slip.size == Vector2.ZERO:
			continue
		if slip.position.x < plots.position.x - 0.5 or slip.end.x > plots.end.x + 0.5:
			bad.append("the slip of %s %s is not inside its column %s" % [id, str(slip), str(plots)])
		var parts := {"name": Kit.rect(r.name), "tag": Kit.rect(r.tag.get_parent()), "status": Kit.rect(r.status)}
		for name in parts:
			if parts[name].size != Vector2.ZERO and not slip.encloses(parts[name].grow(-0.5)):
				bad.append("the %s of %s's slip %s is not in the slip %s" % [name, id, str(parts[name]), str(slip)])
		for hit in Kit.overlaps({"name": parts.name, "tag": parts.tag}):
			bad.append("%s's slip: %s" % [id, hit])
	# every word is whole: a line that does not wrap has the room for all of its letters (nothing collapsed beside
	# another control, nothing cut to an ellipsis), and a line that wraps has room for a few words and a line
	for l in s.find_children("*", "Label", true, false):
		if String(l.text) == "" or not l.is_visible_in_tree():
			continue
		var box := Kit.rect(l)
		var font: Font = l.get_theme_font("font")
		var px: int = l.get_theme_font_size("font_size")
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var want: float = font.get_string_size(String(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			if box.size.x < want - 1.0:
				bad.append("'%s' has %.0f px of the %.0f it needs" % [String(l.text).left(30), box.size.x, want])
		elif box.size.x < 60.0 or box.size.y < float(px):
			bad.append("the wrapped '%s' is squeezed to %s" % [String(l.text).left(30), str(box.size)])
	# the detail: everything in it is inside its card, side to side
	var card := Kit.rect(s.detail)
	var detail_col: Rect2 = columns.detail
	if card.size != Vector2.ZERO and (card.position.x < detail_col.position.x - 0.5 or card.end.x > detail_col.end.x + 0.5):
		bad.append("the card %s is not inside its column %s" % [str(card), str(detail_col)])
	for c in s.detail.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree():
			continue
		var r2 := Kit.rect(c)
		if r2.size == Vector2.ZERO:
			continue
		if r2.position.x < card.position.x - 0.5 or r2.end.x > card.end.x + 0.5:
			bad.append("a %s '%s' %s is outside the card %s" % [c.get_class(), str(c.get("text")).left(24), str(r2), str(card)])
	return bad


func _settled(width: int, height: int, plot: String = "") -> Dictionary:
	var ctx := _open(width, height, 1, plot)
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()
	# (once the page is laid out: before that every button is at the corner, and the engine takes the pointer there
	# to be on the one on top until it moves)
	_park_the_mouse()
	await Kit.settle()
	return ctx


## The detail in each of its views: a building not built, a second home that waits for the first, a site, a building, a site
## that waits its turn.
func _in_each_view(_ctx: Dictionary) -> Array:
	return [["a building not built", "greenhouse_home"], ["a second home that waits", "watchtower_home_2"], ["a site", "bunk_house_home_1"], ["a building", "workshop_home"], ["a site that waits", "salvage_bench_home"]]


## A site for the first bunk house (9 hours in), a workshop that stands, a second site waiting for the salvage bench and
## nobody on the Builders job; the stores are as they were.
func _stage(ctx: Dictionary) -> void:
	var scrap: float = ctx.sim.stock.scrap
	ctx.sim.stock.scrap = 500.0
	_site(ctx, "bunk_house_home_1", "bunk_house", 9.0)
	_stand(ctx, "workshop_home", "workshop")
	_site(ctx, "salvage_bench_home", "salvage_bench", 2.0)
	ctx.sim.jobs.unassign(Kit.person(ctx, "walt"))
	ctx.sim.stock.scrap = scrap


func test_the_page_fits_and_overlaps_nothing_at_700_980_1280_and_1920() -> void:
	for size in SIZES:
		var ctx: Dictionary = await _settled(size[0], size[1])
		_stage(ctx)
		var s = ctx.hud.build_screen
		for view in _in_each_view(ctx):
			s.select_plot(view[1])
			await Kit.settle()
			await Kit.settle()
			eq(_misfits(ctx, size), [], "%d x %d, %s" % [size[0], size[1], view[0]])
		Kit.free_all(ctx)


func test_the_page_fits_a_short_window_and_the_columns_scroll() -> void:
	for size in SHORT:
		var ctx: Dictionary = await _settled(size[0], size[1])
		_stage(ctx)
		var s = ctx.hud.build_screen
		for view in _in_each_view(ctx):
			s.select_plot(view[1])
			await Kit.settle()
			await Kit.settle()
			eq(_misfits(ctx, size), [], "%d x %d, %s" % [size[0], size[1], view[0]])
		s.select_plot("salvage_bench_home")
		await Kit.settle()
		await Kit.settle()
		var room: float = s.list_scroll.size.y
		check(s.list_box.get_combined_minimum_size().y > room, "%d x %d: too short for all the slips, so the list scrolls (%.0f in %.0f)" % [size[0], size[1], s.list_box.get_combined_minimum_size().y, room])
		# scrolled to the end, the last slip is there
		s.list_scroll.scroll_vertical = int(s.list_scroll.get_v_scroll_bar().max_value)
		await Kit.settle()
		var last := Kit.rect(s.rows.radio_mast_home.row)
		var view_rect := Kit.rect(s.list_scroll)
		check(view_rect.grow(1.0).encloses(last.grow(-0.5)), "%d x %d: the last slip is in view at the end of the scroll: %s in %s" % [size[0], size[1], str(last), str(view_rect)])
		# the detail scrolls to the map under it too
		s.detail_scroll.scroll_vertical = int(s.detail_scroll.get_v_scroll_bar().max_value)
		await Kit.settle()
		var last_card := Kit.rect(s.map_card)
		var detail_view := Kit.rect(s.detail_scroll)
		check(detail_view.grow(1.0).encloses(last_card.grow(-0.5)), "%d x %d: the map is in view at the end of the scroll: %s in %s" % [size[0], size[1], str(last_card), str(detail_view)])
		Kit.free_all(ctx)


func test_the_whole_page_is_in_view_without_scrolling_in_a_window_800_tall() -> void:
	for size in [[1280, 800], [1920, 1080]]:
		var ctx: Dictionary = await _settled(size[0], size[1])
		var s = ctx.hud.build_screen
		check(s.list_box.get_combined_minimum_size().y <= s.list_scroll.size.y + 0.5, "%d x %d: the plots fit (%.0f in %.0f)" % [size[0], size[1], s.list_box.get_combined_minimum_size().y, s.list_scroll.size.y])
		var view := Kit.rect(s.list_scroll)
		for id in s.rows:
			check(view.grow(1.0).encloses(Kit.rect(s.rows[id].row).grow(-0.5)), "%d x %d: the slip of %s is in view" % [size[0], size[1], id])
		Kit.free_all(ctx)


func test_the_page_is_laid_out_again_when_the_window_changes() -> void:
	var ctx: Dictionary = await _settled(1280, 800)
	var s = ctx.hud.build_screen
	var wide := Kit.rect(s.panel).size.x
	Kit.resize(ctx, 700, 700)
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()
	eq(_misfits(ctx, [700, 700]), [], "shrunk to 700")
	check(Kit.rect(s.panel).size.x < wide, "the page is narrower: %.0f against %.0f" % [Kit.rect(s.panel).size.x, wide])
	Kit.resize(ctx, 1280, 800)
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()
	eq(_misfits(ctx, [1280, 800]), [], "grown back")
	Kit.free_all(ctx)


# ------------------------------------------------------------------------- the text --

func test_nothing_on_the_page_is_under_twelve_pixels_at_any_size() -> void:
	var tt := TextTests.new()
	for size in [[1920, 1080], [1280, 800], [980, 700], [700, 700], [700, 560]]:
		var ctx: Dictionary = await _settled(size[0], size[1])
		_stage(ctx)
		var s = ctx.hud.build_screen
		for view in _in_each_view(ctx):
			s.select_plot(view[1])
			await Kit.settle()
			eq(tt._small_text(s), [], "%d x %d, %s" % [size[0], size[1], view[0]])
		s.select_plot("salvage_bench_home")
		s.order("workshop")
		s.order("workshop")
		eq(tt._small_text(s), [], "%d x %d, with the line at the foot" % [size[0], size[1]])
		Kit.free_all(ctx)


## Whether the words of the buttons of the page read on the buttons: the ink of each, as the button is drawn normally
## and while it is off, against the darkest and the lightest of its picture over the page.
func _buttons_that_are_hard_to_read(s, tt) -> Array:
	var bad: Array = []
	for b in s.find_children("*", "Button", true, false):
		if String(b.text) == "" or not b.is_visible_in_tree():
			continue
		var state := "disabled" if b.disabled else "normal"
		var ink: Color = b.get_theme_color("font_disabled_color" if b.disabled else "font_color")
		var behind: Array = tt._backdrops(b, Color.WHITE)
		var fills: Array = Kit.fills(b.get_theme_stylebox(state))
		for i in 2:
			var bg: Color = tt.over(fills[i], behind[i])
			var ratio: float = tt.contrast(tt.over(ink, bg), bg)
			if ratio < tt.AA:
				bad.append("'%s' (%s) is %.2f:1" % [b.text, state, ratio])
				break
	return bad


func test_every_word_on_the_page_reads_on_the_paper_in_either_look() -> void:
	var tt := TextTests.new()
	for frames in [true, false]:
		Hud.use_frames = frames
		var look := "frames" if frames else "flat"
		for size in [[1920, 1080], [1280, 800], [980, 700], [700, 700]]:
			_park_the_mouse()
			var ctx := _open(size[0], size[1], 1, "", 22.0)
			_stage(ctx)
			var s = ctx.hud.build_screen
			await Kit.settle()
			await Kit.settle()
			_park_the_mouse()
			await Kit.settle()
			for view in _in_each_view(ctx):
				s.select_plot(view[1])
				await Kit.settle()
				eq(tt._hard_to_read(s, Color.WHITE), [], "%s, %d: %s" % [look, size[0], view[0]])
				eq(_buttons_that_are_hard_to_read(s, tt), [], "%s, %d: the buttons of %s" % [look, size[0], view[0]])
				eq(tt._dark_red_words(s), [], "%s, %d: no word in the dark red (%s)" % [look, size[0], view[0]])
			# with the reasons (22 scrap pay for little), an armed Demolish and the line at the foot
			s.select_plot("radio_mast_home")
			await Kit.settle()
			check(s.entries.radio_mast.why.visible, "(the reasons are showing)")
			eq(tt._hard_to_read(s, Color.WHITE), [], "%s, %d: with the reasons" % [look, size[0]])
			s.order("workshop")
			eq(tt._hard_to_read(s, Color.WHITE), [], "%s, %d: with the line at the foot" % [look, size[0]])
			s.select_plot("workshop_home")
			s.demolish_button.pressed.emit()
			await Kit.settle()
			eq(_buttons_that_are_hard_to_read(s, tt), [], "%s, %d: with Demolish armed" % [look, size[0]])
			Kit.free_all(ctx)
	Hud.use_frames = true


func test_the_page_is_dark_ink_on_light_paper_and_the_buttons_are_the_dialogs() -> void:
	var ctx := _open()
	var s = ctx.hud.build_screen
	var fills: Array = Kit.fills(s.panel.get_theme_stylebox("panel"))
	check(fills[0].v > 0.7 and fills[1].v > 0.7, "the page is pale: %s" % str(fills))
	for l in s.find_children("*", "Label", true, false):
		var ink: Color = l.get_theme_color("font_color")
		if l.text != "" and ink.v > 0.5:
			failures.append("'%s' is set in a pale ink (%s) on a pale page" % [l.text, str(ink)])
	var dialog_ref: Button = ctx.hud._button("Close", true, true)
	eq(s.close_button.get_theme_color("font_color"), dialog_ref.get_theme_color("font_color"), "Close is the main choice, in the dialogs' gold")
	eq(s.entries.workshop.order.get_theme_color("font_color"), dialog_ref.get_theme_color("font_color"), "and so is Order")
	dialog_ref.free()
	Kit.free_all(ctx)


# ----------------------------------------------------------- the real game scene --
# (main.gd: the key N, the toolbar's hammer, a click on a plot's sign, the marks handed to the yard, the lock)

const Tut := preload("res://tests/tutorial_kit.gd")
const Coach := preload("res://scripts/ui/coach.gd")


## A normal run on the real scene, its HUD brought up (its frames are what the game gives it).
func _game(width: int = 1280, height: int = 800) -> Node:
	var main = Tut.start({"difficulty": 1, "seed": 7}, width, height)
	return main


func _toast(main) -> String:
	return main.hud.toast_label.text if main.hud.toast_panel.visible else ""


## What main.gd asks of the tutorial's coach: the gate, and what the player did.
class FakeCoach:
	extends Node
	var open := false
	var asked: Array = []
	var did: Array = []

	func allows(kind: String, arg = null) -> bool:
		asked.append([kind, arg])
		return open

	func would_allow(kind: String, arg = null) -> bool:
		return open

	func on_did(kind: String, arg = null) -> void:
		did.append([kind, arg])


func test_n_opens_the_build_screen_and_the_rules_wait() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	check(main.hud.build_screen == null and not main.menu_open and not main.build_open and main.build_hover.is_empty(), "shut at the start")
	main._key(KEY_N)
	check(main.hud.build_screen != null, "N opens the Build screen")
	eq(main.speed, 0, "the rules wait while it is open")
	check(main.menu_open and main.build_open, "it has the keys: the game's own are not heard, and the yard is told")
	eq(main.build_hover, {"plot": "salvage_bench_home"}, "the chosen building's home is marked from the start")
	await Tut.leave(main)


func test_the_page_marks_the_plot_it_is_pointed_at_for_the_yard() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	main._key(KEY_N)
	var s = main.hud.build_screen
	eq(main.build_hover, {"plot": "salvage_bench_home"}, "the chosen building's home is the one the yard has to draw from the start")
	s.rows.bunk_house_home_1.row.mouse_entered.emit()
	eq(main.build_hover, {"plot": "bunk_house_home_1"}, "pointing at another building: main.gd has its home for the yard to draw")
	s.rows.bunk_house_home_1.row.mouse_exited.emit()
	eq(main.build_hover, {"plot": "salvage_bench_home"}, "and the chosen one's again once the pointer leaves")
	s.rows.watchtower_home_1.row.mouse_entered.emit()
	main.hud.close_build()
	eq(main.build_hover, {}, "closed: nothing")
	check(not main.build_open, "and the yard is told it is shut")
	await Tut.leave(main)


func test_the_yard_has_no_sign_on_it_until_the_screen_opens_or_the_pointer_comes_near() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	var sim = main.sim
	var view = main.build_view
	var far := Vector2(-40.0, -40.0)
	view.pointer = far
	await Tut.frames(main, 2)
	eq(view.drawn_signs, 0, "in the plain yard, with the pointer far from every plot, there is no sign")
	eq(view.drawn_outlines, 0, "and no outline")
	var plots: Array = sim.build.plots()
	view.pointer = Vector2(plots[0].pos)
	await Tut.frames(main, 2)
	eq(view.drawn_signs, 1, "the pointer on a plot: its sign")
	eq(view.drawn_outlines, 1, "and its outline, and no other plot's")
	# the sign under the pointer opens the screen as before
	var sign_at: Vector2 = sim.build.sign_pos(String(plots[0].id))
	main._click(_screen_of(main, sign_at), MOUSE_BUTTON_LEFT)
	check(main.hud.build_screen != null and main.hud.build_screen.selected == String(plots[0].id), "a click on the sign opens the screen on that plot")
	await Tut.frames(main, 2)
	eq(view.drawn_signs, plots.size(), "with the screen open every plot has its sign")
	eq(view.drawn_outlines, plots.size(), "and its outline")
	main.hud.close_build()
	await Tut.frames(main, 2)
	eq(view.drawn_signs, 1, "closed, the pointer's own sign is all that is left")
	view.pointer = far
	await Tut.frames(main, 2)
	eq(view.drawn_signs, 0, "and with the pointer gone, none")
	await Tut.leave(main)


func test_n_again_esc_close_and_the_toolbar_give_the_speed_back() -> void:
	for how in ["n", "esc", "close", "toolbar", "toggle"]:
		var main = _game()
		main.speed = 2
		await Tut.frames(main, 3)
		main._key(KEY_N)
		check(main.hud.build_screen != null and main.speed == 0, "%s: open and paused" % how)
		var screen = main.hud.build_screen
		match how:
			"n":
				# with the page up N reaches the page itself (the game's own handler is not asked)
				screen._input(_key(KEY_N))
			"esc":
				screen._input(_key(KEY_ESCAPE))
			"close":
				screen.close_button.pressed.emit()
			"toolbar":
				main.hud.build_button.pressed.emit()
			"toggle":
				main.toggle_build()
		check(main.hud.build_screen == null, "%s: shut" % how)
		eq(main.speed, 2, "%s: and the speed is back" % how)
		eq(main.build_hover, {}, "%s: nothing is marked any more" % how)
		await Tut.leave(main)


func test_the_toolbar_button_opens_the_screen_too() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	main.hud.build_button.pressed.emit()
	check(main.hud.build_screen != null, "the hammer in the toolbar opens it")
	await Tut.leave(main)


func test_n_is_not_there_in_the_title_over_a_menu_or_another_page() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	main.open_pause()
	main._key(KEY_N)
	check(main.hud.build_screen == null, "not over the pause menu")
	main.shell.close_all()
	main.resume()
	# another page: the radio card (a modal)
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	main.hud.add_child(page)
	main._key(KEY_N)
	check(main.hud.build_screen == null, "nor over a page that covers the game")
	page.free()
	# the Jobs screen has the keys while it is up
	main.toggle_jobs()
	check(main.hud.jobs_screen != null, "(the Jobs screen is open)")
	main.toggle_build()
	check(main.hud.build_screen == null, "nor over the Jobs screen")
	main.hud.close_jobs()
	main.title_mode = true
	main._key(KEY_N)
	main.toggle_build()
	check(main.hud.build_screen == null, "nor on the title")
	main.title_mode = false
	main._key(KEY_N)
	check(main.hud.build_screen != null, "but it opens once nothing is in the way")
	main.toggle_jobs()
	check(main.hud.jobs_screen == null, "and the Jobs screen does not open over it")
	await Tut.leave(main)


func test_the_tutorials_lock_may_refuse_the_build_screen() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	# a coach that allows nothing but says so (the real one is below)
	var coach := FakeCoach.new()
	main.coach = coach
	main._key(KEY_N)
	check(main.hud.build_screen == null, "the lock refuses it")
	eq(coach.asked, [["build", null]], "having asked the gate about 'build'")
	main.hud.build_button.pressed.emit()
	check(main.hud.build_screen == null and coach.asked.size() == 2, "the toolbar's button asks the same gate")
	coach.open = true
	main._key(KEY_N)
	check(main.hud.build_screen != null, "an open gate lets it through")
	check(coach.did.has(["build", null]), "and the coach is told the player did it: %s" % str(coach.did))
	main.hud.close_build()
	main.coach = null
	coach.free()
	await Tut.leave(main)


func test_orientation_day_refuses_n_until_it_is_over_and_ghosts_the_hammer() -> void:
	var main = Tut.game(0)
	await Tut.frames(main, 12)
	var coach = main.coach
	check(main.hud.build_button.modulate.a < 0.5, "the hammer is a ghost in the first lesson")
	main._key(KEY_N)
	check(main.hud.build_screen == null, "N does not open the page")
	eq(_toast(main), "Not yet: first pan and zoom the view.", "and says what comes first")
	eq(float(coach.state.did.get("build", 0.0)), 0.0, "and the coach was not told it was opened")
	main.hud.toast_panel.visible = false
	main.hud.toast_label.text = ""
	coach._toast_text = ""
	main.hud.build_button.pressed.emit()
	check(main.hud.build_screen == null, "the toolbar's button asks the same gate")
	check(_toast(main).begins_with("Not yet"), "with the same toast")
	# no lesson teaches it: the gate is shut at every step but the last card, which allows everything
	for i in coach.steps.size() - 1:
		coach.step = coach.steps[i]
		coach.phase = "active"
		check(not coach.would_allow("build"), "%s: not taught here" % String(coach.steps[i].id))
	await Tut.leave(main)


# ---------------------------------------------------------- a click on a plot's sign --

## A point of open ground in the yard: not in any lot and nowhere near a plot's sign (the lots may be moved).
func _open_ground(sim) -> Vector2:
	for at in [Vector2(40.0, 33.0), Vector2(45.0, 30.0), Vector2(38.0, 36.0), Vector2(46.0, 34.0), Vector2(36.0, 29.0), Vector2(44.0, 38.0)]:
		if sim.build.plot_at(at) == "" and sim.build.sign_at(at) == "":
			return at
	failures.append("(no open ground found in the yard)")
	return Vector2(40.0, 33.0)


## The camera on `at`, and the screen position that is `at` (a click there is a click on that spot of the yard).
func _screen_of(main, at: Vector2) -> Vector2:
	main._focus(at)
	main._apply_camera()
	return main._tile_to_screen(at)


func test_a_click_on_a_buildings_sign_opens_the_screen_on_that_building() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	var sim = main.sim
	sim.zombies.clear()
	var sign_at: Vector2 = sim.build.sign_pos("workshop_home")
	check(main._pick(sign_at) == null, "(nobody is standing on the sign)")
	main._click(_screen_of(main, sign_at), MOUSE_BUTTON_LEFT)
	check(main.hud.build_screen != null, "a click on the sign opens the Build screen")
	eq(main.hud.build_screen.selected, "workshop_home", "on the building whose home it is")
	eq(main.speed, 0, "and the rules wait")
	check(main.selection == null, "the selection was not touched")
	main.hud.close_build()
	# a click near it counts too
	main._click(_screen_of(main, sign_at + Vector2(0.5, 0.3)), MOUSE_BUTTON_LEFT)
	check(main.hud.build_screen != null and main.hud.build_screen.selected == "workshop_home", "near the sign too")
	main.hud.close_build()
	# a click in the middle of the lot, away from the sign, does not
	var middle: Vector2 = sim.build.plot("workshop_home").pos
	main._click(_screen_of(main, middle), MOUSE_BUTTON_LEFT)
	check(main.hud.build_screen == null, "a click in the middle of a lot opens nothing")
	main._click(_screen_of(main, _open_ground(sim)), MOUSE_BUTTON_LEFT)
	check(main.hud.build_screen == null, "nor does one on the open ground")
	await Tut.leave(main)


func test_a_person_standing_on_a_sign_is_selected_not_the_plot() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	var sim = main.sim
	var ruth = sim.people[0]
	var sign_at: Vector2 = sim.build.sign_pos("greenhouse_home")
	ruth.x = sign_at.x
	ruth.y = sign_at.y + 0.3
	main._click(_screen_of(main, sign_at), MOUSE_BUTTON_LEFT)
	check(main.hud.build_screen == null, "a click that hits a person is theirs")
	check(main.selection != null and main.selection.kind == "person" and main.selection.ref == ruth, "Ruth is selected")
	await Tut.leave(main)


func test_a_click_on_a_sign_is_an_ordinary_click_while_the_lock_refuses_the_screen() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	var sim = main.sim
	var coach := FakeCoach.new()
	main.coach = coach
	main._select({"kind": "person", "ref": sim.people[0]})
	var sign_at: Vector2 = sim.build.sign_pos("greenhouse_home")
	main._click(_screen_of(main, sign_at), MOUSE_BUTTON_LEFT)
	check(main.hud.build_screen == null, "the lock keeps the page shut")
	eq(coach.asked.filter(func(a): return a[0] == "build"), [], "and no gate is asked about it (so no toast about it)")
	main.coach = null
	coach.free()
	await Tut.leave(main)


func test_the_pointer_over_a_sign_is_a_hand() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	var sim = main.sim
	var sign_at: Vector2 = sim.build.sign_pos("workshop_home")
	eq(main._cursor_for(null, sign_at), Input.CURSOR_POINTING_HAND, "a hand over a sign")
	eq(main._cursor_for(null, sign_at + Vector2(0.4, 0.2)), Input.CURSOR_POINTING_HAND, "and near it")
	eq(main._cursor_for(null, _open_ground(sim)), Input.CURSOR_ARROW, "an arrow over open ground")
	eq(main._cursor_for(null, sim.build.plot("workshop_home").pos), Input.CURSOR_ARROW, "and in the middle of a lot")
	eq(main._cursor_for({"kind": "person", "ref": sim.people[0]}, _open_ground(sim)), Input.CURSOR_POINTING_HAND, "a hand over a person, as it was")
	await Tut.leave(main)


# --------------------------------------------------------------------- the wheel --

## One turn of the mouse wheel at `at`, as the engine hears it.
func _wheel(at: Vector2, down: bool = true) -> void:
	var root: Window = Engine.get_main_loop().root
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.factor = 1.0
	ev.position = at
	ev.global_position = at
	root.push_input(ev, true)


func test_the_wheel_scrolls_the_list_over_a_slip_and_the_detail_over_a_button() -> void:
	var ctx: Dictionary = await _settled(700, 480)
	var s = ctx.hud.build_screen
	eq(s.list_scroll.scroll_vertical, 0, "the list starts at the top")
	_wheel(Kit.rect(s.rows.workshop_home.row).get_center())
	await Kit.settle()
	check(s.list_scroll.scroll_vertical > 0, "a turn of the wheel over a slip scrolls the list: %d" % s.list_scroll.scroll_vertical)
	eq(s.detail_scroll.scroll_vertical, 0, "and not the detail")
	eq(s.selected, "salvage_bench_home", "nor does it choose a plot")
	_wheel(Kit.rect(s.entries.salvage_bench.order).get_center())
	await Kit.settle()
	check(s.detail_scroll.scroll_vertical > 0, "over an Order button it scrolls the detail: %d" % s.detail_scroll.scroll_vertical)
	check(ctx.sim.build.plot("salvage_bench_home").site.is_empty(), "and orders nothing")
	Kit.free_all(ctx)


func test_a_building_chosen_far_down_the_list_is_scrolled_into_view() -> void:
	for size in [[700, 480], [1280, 500]]:
		var ctx: Dictionary = await _settled(size[0], size[1], "radio_mast_home")
		var s = ctx.hud.build_screen
		eq(s.selected, "radio_mast_home", "the building asked for is chosen")
		var slip := Kit.rect(s.rows.radio_mast_home.row)
		var view := Kit.rect(s.list_scroll)
		check(view.grow(1.0).encloses(slip.grow(-0.5)), "%d x %d: and its slip is in view: %s in %s" % [size[0], size[1], str(slip), str(view)])
		s.select_plot("salvage_bench_home")
		await Kit.settle()
		await Kit.settle()
		s.select_plot("watchtower_home_2")
		await Kit.settle()
		await Kit.settle()
		var again := Kit.rect(s.rows.watchtower_home_2.row)
		check(view.grow(1.0).encloses(again.grow(-0.5)), "%d x %d: and so is the one chosen next: %s in %s" % [size[0], size[1], str(again), str(view)])
		Kit.free_all(ctx)


# ----------------------------------------------------------- the screenshots' staging --

func test_the_staging_arguments_put_sites_and_buildings_up_without_paying() -> void:
	var main = _game()
	await Tut.frames(main, 3)
	var sim = main.sim
	var scrap: float = sim.stock.scrap
	main._stage_build("bunk_house_home_1:bunk_house,greenhouse_home:greenhouse", true)
	check(sim.build.built("bunk_house") and sim.build.built("greenhouse"), "buildings stand")
	main._stage_build("workshop_home:workshop:0.5,salvage_bench_home:salvage_bench", false)
	near(float(sim.build.plot("workshop_home").site.progress), 12.0, 1e-6, "a site with half the work done")
	near(float(sim.build.plot("salvage_bench_home").site.progress), 0.0, 1e-6, "and one with none")
	near(float(sim.stock.scrap), scrap, 1e-9, "no scrap was paid")
	check(not sim.alerts.has("built-bunk_house_home_1") and sim.events.is_empty(), "and nothing is announced")
	main._stage_build("nowhere:castle,workshop_home:workshop", false)
	check(sim.build.plot("workshop_home").site.progress == 12.0, "an order that cannot be placed is left out")
	main._stage_build("watchtower_home_1:workshop", false)
	check(sim.build.plot("watchtower_home_1").site.is_empty(), "so is a building on a home that is another building's")
	await Tut.leave(main)


# --------------------------------------------------------------------------- fuzz --

## What the page says about every building against what the game says: a list of what does not match.
func _page_matches_the_game(ctx: Dictionary) -> Array:
	var bad: Array = []
	var s = ctx.hud.build_screen
	var build = ctx.sim.build
	for pl in build.plots():
		var r: Dictionary = s.rows[pl.id]
		var want := ""
		if pl.building != "":
			want = "Built"
		elif not pl.site.is_empty():
			want = "Going up: %d%%" % mini(99, floori(build.progress_of(String(pl.id)) * 100.0))
		else:
			var home: Dictionary = build.building(String(pl.home))
			var because: String = build.why_not(String(pl.id), String(home.id))
			want = "%s scrap, %s builder-hours" % [s._num(float(home.scrap)), s._num(float(home.work))] if because == "" else "Can't: %s" % s._short_why(because)
		if Kit.texts(r.status) != [want]:
			bad.append("%s's slip reads %s, not '%s'" % [pl.id, str(Kit.texts(r.status)), want])
		if r.meter.visible != (pl.building == "" and not pl.site.is_empty()):
			bad.append("%s's meter is %s" % [pl.id, r.meter.visible])
	var sel: Dictionary = build.plot(s.selected)
	if s.empty_view.visible != (sel.building == "" and sel.site.is_empty()):
		bad.append("the catalogue is %s for %s" % [s.empty_view.visible, s.selected])
	if s.site_view.visible != (sel.building == "" and not sel.site.is_empty()):
		bad.append("the site view is %s for %s" % [s.site_view.visible, s.selected])
	if s.built_view.visible != (sel.building != ""):
		bad.append("the building view is %s for %s" % [s.built_view.visible, s.selected])
	if s.empty_view.visible:
		for b in build.catalogue():
			var e: Dictionary = s.entries[b.id]
			var why: String = build.why_not(s.selected, String(b.id))
			if e.card.visible != (String(sel.home) == String(b.id)):
				bad.append("%s is %s at the home of %s" % [b.id, e.card.visible, sel.home])
			elif e.card.visible and e.order.disabled != (why != ""):
				bad.append("%s's Build is %s with why_not '%s'" % [b.id, e.order.disabled, why])
	var scrap_line := "Scrap in the stores: %d" % int(float(ctx.sim.stock.scrap))
	if Kit.texts(s.stock_label) != [scrap_line]:
		bad.append("the foot reads %s, not '%s'" % [str(Kit.texts(s.stock_label)), scrap_line])
	return bad


func test_random_games_and_random_clicks_never_break_the_page() -> void:
	for seed_value in [51, 7, 2024]:
		await _fuzz(seed_value)


func _fuzz(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sizes := [[700, 700], [980, 700], [1280, 800], [1920, 1080], [700, 560], [1280, 600]]
	var bad: Array = []
	for round in 8:
		var size: Array = sizes[rng.randi() % sizes.size()]
		_park_the_mouse()
		var ctx := Kit.build(size[0], size[1])
		var sim = ctx.sim
		var build = sim.build
		sim.stock.scrap = rng.randf() * 160.0
		var plot_ids := _plot_ids(ctx)
		var building_ids: Array = []
		for b in build.catalogue():
			building_ids.append(String(b.id))
		Kit.update(ctx, rng.randi() % 4)
		ctx.hud.open_build(plot_ids[rng.randi() % plot_ids.size()] if rng.randf() < 0.5 else "")
		var s = ctx.hud.build_screen
		if s == null:
			bad.append("round %d: the page did not open" % round)
			Kit.free_all(ctx)
			continue
		await Kit.settle()
		for step in 24:
			var what := rng.randi() % 12
			var plot_id: String = plot_ids[rng.randi() % plot_ids.size()]
			match what:
				0, 1:
					s.select_plot(plot_id)
				2:
					s.order(building_ids[rng.randi() % building_ids.size()] if rng.randf() < 0.9 else "castle")
				3:
					s.cancel()
				4, 5:
					s.demolish()
				6:
					s._input(_key(KEY_ESCAPE) if rng.randf() < 0.3 else _key(KEY_R))
				7:
					size = sizes[rng.randi() % sizes.size()]
					Kit.resize(ctx, size[0], size[1])
					await Kit.settle()
				8:
					s.rows[plot_id].row.mouse_entered.emit()
				9:
					# the game moves on under the page: scrap comes and goes, a site makes headway, a building stands
					sim.stock.scrap = rng.randf() * 160.0
					var site: Dictionary = build.plot(plot_id)
					if not site.site.is_empty():
						site.site.progress = float(site.site.work) * rng.randf() * 0.98
					Kit.update(ctx, 0)
				10:
					# Walt goes off to scavenge, comes back, is hurt; someone else takes the Builders job
					var who = sim.people[rng.randi() % sim.people.size()]
					who.away = null if rng.randf() < 0.5 else {"kind": "party", "site": "houses"}
					who.downed = rng.randf() < 0.2
					sim.jobs.assign(who, "builders" if rng.randf() < 0.5 else "")
					Kit.update(ctx, 0)
				11:
					if rng.randf() < 0.5:
						s.cancel_button.pressed.emit()
					else:
						s.entries[building_ids[rng.randi() % building_ids.size()]].order.pressed.emit()
			if ctx.hud.build_screen == null:
				# (Esc shut it: the player opens it again)
				ctx.hud.open_build()
				s = ctx.hud.build_screen
				if s == null:
					bad.append("round %d step %d: it would not open again" % [round, step])
					break
				await Kit.settle()
			s.refresh()
			for line in _page_matches_the_game(ctx):
				bad.append("round %d step %d (%d): %s" % [round, step, what, line])
		if ctx.hud.build_screen == null:
			ctx.hud.open_build()
			s = ctx.hud.build_screen
		await Kit.settle()
		await Kit.settle()
		for line in _misfits(ctx, size):
			bad.append("round %d at %d x %d: %s" % [round, size[0], size[1], line])
		Kit.free_all(ctx)
	eq(bad, [], "a random game under the page (seed %d)" % seed_value)


# ------------------------------------------------------------- the page and the real rules --

const Helpers := preload("res://tests/helpers.gd")


## A quiet real game at `hour` with the HUD (no fake modules) over it and the screen open on `plot`.
func _real_game(plot: String, hour: float = 8.0) -> Dictionary:
	var g := Helpers.make(71, 1)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.minutes = hour * 60.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.stock.scrap = 100.0
	Helpers.idle_stores(sim)
	var holder := Control.new()
	holder.size = Vector2(1280, 800)
	Engine.get_main_loop().root.add_child(holder)
	var hud := Hud.new()
	holder.add_child(hud)
	hud.on_speed = func(_s): pass
	hud.setup(g.data, sim.people)
	hud.update_hud(sim, 1, true, 0)
	hud.open_build(plot)
	return {"g": g, "sim": sim, "holder": holder, "hud": hud, "world": g.world}


func _free_real(ctx: Dictionary) -> void:
	ctx.holder.free()
	ctx.world.free()


func test_an_order_the_builders_work_it_and_the_page_shows_it_built() -> void:
	var ctx := _real_game("salvage_bench_home")
	var sim = ctx.sim
	var hud = ctx.hud
	var s = hud.build_screen
	check(s.order("salvage_bench"), "the bench is ordered from the page")
	near(float(sim.stock.scrap), 82.0, 1e-9, "eighteen scrap are paid")
	var first_line: String = Kit.texts(s.site_crew)[0]
	check(first_line.begins_with("Walt: about "), "the page names Walt and a time: '%s'" % first_line)
	eq(Kit.texts(s.site_percent), ["0%"], "no work done")
	# the rules go on (the page is shut, as it would be: the rules wait while it is open)
	hud.close_build()
	Helpers.run(sim, 120.0)
	hud.open_build("salvage_bench_home")
	s = hud.build_screen
	var done: float = sim.build.progress_of("salvage_bench_home")
	check(done > 0.1 and done < 1.0, "the Builders have made headway: %.2f" % done)
	eq(Kit.texts(s.site_percent), ["%d%%" % floori(done * 100.0)], "the page shows how far")
	check(_hours_in(Kit.texts(s.site_crew)[0]) < _hours_in(first_line), "and the time that is left is shorter: '%s' after '%s'" % [Kit.texts(s.site_crew)[0], first_line])
	# on to the end: the page, left open, follows the rules by itself when it is told the HUD was updated
	var guard := 0
	while not sim.build.built("salvage_bench") and guard < 900:
		Helpers.run(sim, 1.0)
		guard += 1
		if guard % 5 == 0:
			hud.update_hud(sim, 1, true, 0)
	hud.update_hud(sim, 1, true, 0)
	check(sim.build.built("salvage_bench"), "it is built after %d seconds" % guard)
	eq(Kit.texts(s.rows.salvage_bench_home.status), ["Built"], "the slip says it stands")
	check(s.built_view.visible and Kit.texts(s.built_title) == ["Salvage bench"], "and the detail is the building's")
	eq(s.demolish_button.text, "Demolish (+9 scrap)", "with half of its eighteen scrap to come back")
	eq(sim.jobs.stations().size(), 7, "(the bench opened the Salvage station)")
	_free_real(ctx)


func test_the_page_follows_a_site_the_rules_finish_under_it_and_a_demolished_building() -> void:
	var ctx := _real_game("greenhouse_home")
	var sim = ctx.sim
	var hud = ctx.hud
	var s = hud.build_screen
	s.order("greenhouse")
	sim.build.plot("greenhouse_home").site.progress = float(sim.build.plot("greenhouse_home").site.work) - 0.001
	var guard := 0
	while not sim.build.built("greenhouse") and guard < 120:
		Helpers.run(sim, 1.0)    # (Walt walks to the site first)
		guard += 1
	hud.update_hud(sim, 1, true, 0)
	check(sim.build.built("greenhouse"), "the rules finished it with the page up (after %d seconds)" % guard)
	check(s.built_view.visible and not s.site_view.visible, "the page shows the building")
	check(sim.alerts.has("built-greenhouse_home"), "(and the game told the crew)")
	s.demolish()
	s.demolish()
	check(not sim.build.built("greenhouse") and s.empty_view.visible, "demolished from the page: the home is free again")
	near(float(sim.stock.scrap), 100.0 - 14.0 + 7.0, 1e-6, "for half of its scrap back")
	_free_real(ctx)


func test_on_the_last_card_of_orientation_day_the_screen_may_be_opened() -> void:
	var main = Tut.game(Coach.load_steps().size() - 1)
	await Tut.frames(main, 12)
	var coach = main.coach
	eq(coach.step_id(), "wrap", "the last card is up")
	check(main._allows("build"), "the last card allows everything, the Build screen too")
	main._key(KEY_N)
	check(main.hud.build_screen != null, "N opens it")
	await Tut.frames(main, 6)
	main.hud.close_build()
	await Tut.frames(main, 4)
	check(main.hud.build_screen == null, "and it shuts again")
	await Tut.leave(main)
