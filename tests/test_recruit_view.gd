extends "res://tests/case.gd"
## Round 7, what the player sees of the small start and of arrivals: a person who joins after the HUD and the
## yard were built (a recruit, scripts/sim/recruits.gd) gets a card, a panel, a Jobs row and a pawn; fourteen cards
## fit at every width; the arrival has a cue; the new-game menu's crew choice reaches the rules (`--crew`, the run
## meta). The rules behind it are tests/test_recruits.gd (the owner's).

const Kit := preload("res://tests/hud_kit.gd")
const Helpers := preload("res://tests/helpers.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const GD := preload("res://scripts/game_data.gd")
const RecruitArt := preload("res://scripts/render/recruit_art.gd")
const MenuFakes := preload("res://tests/menu_fakes.gd")
const Main := preload("res://scripts/main.gd")
const RadioCard := preload("res://scripts/ui/radio_card.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const NewGameMenu := preload("res://scripts/ui/new_game_menu.gd")
const Prefs := preload("res://scripts/prefs.gd")

const WIDTHS := [700, 980, 1280, 1920]
const PORTRAIT := "res://assets/portraits/walt.png"


## Someone arrives at the gate: a generated survivor (not bitten, with a picture of the roster's lent to them), added
## to the crew the way `sim.recruits` does it.
func _recruit(ctx: Dictionary, i: int = 0, portrait: String = PORTRAIT):
	var def: Dictionary = ctx.sim.recruits.make_def(i)
	def["bitten"] = false
	if portrait != "":
		def["portrait"] = portrait
	else:
		def.erase("portrait")
	return ctx.sim.add_person(def)


func _crew_of(ctx: Dictionary, n: int) -> void:
	while ctx.sim.people.size() < n:
		_recruit(ctx, ctx.sim.people.size())


func _settled(width: int, height: int, n: int, real_people: bool = false) -> Dictionary:
	var ctx := Kit.build(width, height, 1, real_people)
	_crew_of(ctx, n)
	Kit.update(ctx)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	return ctx


# ------------------------------------------------------------------- the cards --

func test_a_person_who_joins_later_gets_a_card() -> void:
	var ctx := Kit.build()
	Kit.update(ctx)
	eq(ctx.hud.cards.size(), 6, "the six at the start")
	var p = _recruit(ctx, 0)
	eq(ctx.hud.cards.size(), 6, "the HUD has not looked yet")
	Kit.update(ctx)
	eq(ctx.hud.cards.size(), 7, "the next update gives the newcomer a card")
	var c := Kit.card(ctx, p)
	check(not c.is_empty(), "it is theirs")
	eq(c.name.text, p.first, "with their first name")
	eq(c.pic.texture, GD.tex(PORTRAIT), "and the picture their def names")
	eq(c.card.tooltip_text, "%s, %s" % [p.name, String(p.def.role).to_lower()], "and the name and the role in the tooltip")
	Kit.update(ctx)
	eq(ctx.hud.cards.size(), 7, "and only the one")
	check(c.card.get_parent() == ctx.hud.bar, "in the crew's row")
	Kit.free_all(ctx)


func test_the_hud_can_be_told_and_does_not_make_a_card_twice() -> void:
	var ctx := Kit.build()
	var p = _recruit(ctx, 0)
	ctx.hud.add_person(p)
	eq(ctx.hud.cards.size(), 7, "told: a card at once")
	ctx.hud.add_person(p)
	Kit.update(ctx)
	eq(ctx.hud.cards.size(), 7, "told twice, or seen after being told: still one")
	Kit.free_all(ctx)


func test_a_card_flashes_when_someone_arrives() -> void:
	var ctx := Kit.build()
	var p = _recruit(ctx, 0)
	ctx.hud.add_person(p)
	ctx.hud.flash_card(p)
	var c := Kit.card(ctx, p)
	check(c.card.modulate != Color.WHITE, "lit for a moment")
	Kit.update(ctx)
	check(Kit.card(ctx, Kit.person(ctx, "ruth")).card.modulate == Color.WHITE, "nobody else's is")
	Kit.free_all(ctx)


func test_a_recruit_with_no_picture_still_gets_a_card_and_a_panel() -> void:
	var ctx := Kit.build(1280, 800, 1, true)
	var p = _recruit(ctx, 3, "")
	Kit.update(ctx)
	var c := Kit.card(ctx, p)
	check(not c.is_empty(), "a card")
	check(c.pic.texture == null, "with the dark window and the name, no face to lend")
	Kit.select(ctx, p)
	Kit.update(ctx)
	eq(ctx.hud.inspect_refs.name.text, p.name, "and the panel says who it is")
	Kit.free_all(ctx)


func test_fourteen_cards_fit_at_every_width() -> void:
	for w in WIDTHS:
		var ctx: Dictionary = await _settled(w, 700, 14)
		var h = ctx.hud
		eq(h.cards.size(), 14, "%d wide: fourteen cards" % w)
		var win := Rect2(0, 0, w, 700)
		var bar := Kit.rect(h.bar)
		check(win.encloses(bar.grow(-0.5)), "%d wide: the row is inside the window: %s" % [w, str(bar)])
		var others := {"stores": Kit.rect(h.left_col), "clock": Kit.rect(h.clock), "alerts": Kit.rect(h.alerts_box), "cards": bar}
		eq(Kit.overlaps(others), [], "%d wide: the cards keep clear of the stores and the clock" % w)
		var rects: Array = []
		for c in h.cards:
			var r := Kit.rect(c.card)
			check(bar.encloses(r.grow(-0.5)), "%d wide: %s's card is in the row" % [w, c.p.first])
			check(r.size.x >= 44.0 - 0.01, "%d wide: a card is at least 44 wide: %s" % [w, str(r.size)])
			check(c.name.get_theme_font_size("font_size") >= 12, "%d wide: names are 12 px or more" % w)
			for q in rects:
				check(not q.intersects(r.grow(-0.5)), "%d wide: cards do not overlap" % w)
			rects.append(r)
		Kit.free_all(ctx)


func test_the_card_row_follows_the_crew_as_it_grows() -> void:
	for w in WIDTHS:
		var ctx := Kit.build(w, 700)
		var last_h := 0.0
		for n in range(6, 15):
			_crew_of(ctx, n)
			Kit.update(ctx)
			await Kit.settle()
			await Kit.settle()
			var bar := Kit.rect(ctx.hud.bar)
			var others := {"stores": Kit.rect(ctx.hud.left_col), "clock": Kit.rect(ctx.hud.clock), "alerts": Kit.rect(ctx.hud.alerts_box), "cards": bar}
			eq(Kit.overlaps(others), [], "%d wide, %d people: clear of the stores and the clock" % [w, n])
			check(Rect2(0, 0, w, 700).encloses(bar.grow(-0.5)), "%d wide, %d people: inside the window" % [w, n])
			last_h = bar.size.y
		check(last_h > 0.0, "%d wide: a row" % w)
		Kit.free_all(ctx)


func test_the_cards_are_laid_out_again_when_the_window_changes_size() -> void:
	var ctx: Dictionary = await _settled(1920, 800, 14)
	var rows_wide: int = ctx.hud.bar_plan.rows
	for w in [700, 980, 1280, 700, 1920]:
		Kit.resize(ctx, w, 800)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var bar := Kit.rect(ctx.hud.bar)
		var others := {"stores": Kit.rect(ctx.hud.left_col), "clock": Kit.rect(ctx.hud.clock), "alerts": Kit.rect(ctx.hud.alerts_box), "cards": bar}
		eq(Kit.overlaps(others), [], "resized to %d: the cards keep clear of the stores and the clock" % w)
		check(Rect2(0, 0, w, 800).encloses(bar.grow(-0.5)), "resized to %d: inside the window: %s" % [w, str(bar)])
		eq(ctx.hud.cards.size(), 14, "resized to %d: still fourteen" % w)
	eq(ctx.hud.bar_plan.rows, rows_wide, "and back at the wide size, the wide layout")
	Kit.free_all(ctx)


func test_the_banner_hangs_below_the_cards_however_many_rows_they_take() -> void:
	for w in WIDTHS:
		var ctx: Dictionary = await _settled(w, 700, 14)
		var bar := Kit.rect(ctx.hud.bar)
		var banner := Kit.rect(ctx.hud.banner)
		check(banner.position.y >= bar.end.y - 0.5, "%d wide: the banner (%s) is not over the cards (%s)" % [w, str(banner), str(bar)])
		Kit.free_all(ctx)


func test_the_classic_six_are_laid_out_as_they_always_were() -> void:
	for w in WIDTHS:
		var ctx: Dictionary = await _settled(w, 700, 6)
		var h = ctx.hud
		var std := 48 if w < 980 else 60
		var bar := Kit.rect(h.bar)
		near(bar.size.x, float(6 * std + 5 * 6), 0.5, "%d wide: six cards of %d and five gaps of six" % [w, std])
		near(bar.position.x + bar.size.x * 0.5, w * 0.5, 0.6, "%d wide: centred on the window" % w)
		near(bar.position.y, 10.0, 0.5, "%d wide: ten from the top" % w)
		var ys := {}
		for c in h.cards:
			var r := Kit.rect(c.card)
			near(r.size.x, float(std), 0.01, "%d wide: %s's card is %d wide" % [w, c.p.first, std])
			ys[snappedf(r.position.y, 0.5)] = true
		eq(ys.size(), 1, "%d wide: all in one row" % w)
		near(Kit.rect(h.banner).position.y, 118.0, 0.5, "%d wide: the banner where it was" % w)
		Kit.free_all(ctx)


func test_three_people_have_three_cards_of_the_usual_size() -> void:
	# a small start has three people: the HUD is made for what the sim has
	var g := Helpers.make(7, 1, 3)
	var holder := Control.new()
	holder.size = Vector2(1280, 800)
	Engine.get_main_loop().root.add_child(holder)
	var hud := Hud.new()
	holder.add_child(hud)
	hud.setup(g.data, g.sim.people)
	hud.update_hud(g.sim, 1, true, 0)
	await Kit.settle()
	eq(hud.cards.size(), 3, "three cards")
	near(Kit.rect(hud.bar).size.x, 3.0 * 60.0 + 2.0 * 6.0, 0.5, "of sixty, six apart")
	holder.free()
	g.world.free()


# ----------------------------------------------------------- selection and panel --

func test_clicking_the_card_of_a_recruit_selects_them() -> void:
	var ctx: Dictionary = await _settled(1280, 800, 8)
	var p = ctx.sim.people[7]
	Kit.click_on(Kit.card(ctx, p).card)
	check(not ctx.selected.is_empty(), "the HUD asked for a selection")
	var sel: Dictionary = ctx.selected.back()
	check(sel.kind == "person" and sel.ref == p, "and it is the recruit")
	Kit.free_all(ctx)


func test_the_panel_of_a_recruit_is_a_full_panel() -> void:
	var ctx: Dictionary = await _settled(1280, 800, 8, true)
	var p = ctx.sim.people[7]
	Kit.select(ctx, p)
	Kit.update(ctx)
	await Kit.settle()
	var refs: Dictionary = ctx.hud.inspect_refs
	eq(refs.name.text, p.name, "the name")
	check(refs.mood_word.text != "", "a mood word: '%s'" % refs.mood_word.text)
	check(String(refs.mood_head.tooltip_text) != "" or String(refs.mood_row.tooltip_text) != "" or String(refs.mood_word.tooltip_text) != "", "and the reasons in a tooltip")
	eq(String(refs.job_tag.get_child(0).text), "Job: none", "the job tag: no day job yet")
	eq(refs.traits_box.get_child_count(), 2, "two traits as chips")
	check(refs.name.tooltip_text != "", "the record on the name")
	Kit.free_all(ctx)


func test_a_selection_stands_when_someone_arrives() -> void:
	var ctx: Dictionary = await _settled(1280, 800, 6, true)
	var ana = Kit.person(ctx, "ana")
	Kit.select(ctx, ana)
	Kit.update(ctx)
	var panel_before: Control = ctx.hud.inspect.get_child(0)
	_recruit(ctx, 0)
	Kit.update(ctx)
	await Kit.settle()
	check(ctx.hud.selection != null and ctx.hud.selection.ref == ana, "Ana is still selected")
	check(ctx.hud.inspect.visible and ctx.hud.inspect.get_child(0) == panel_before, "her panel was not rebuilt")
	check(Kit.card(ctx, ana).sel, "and her card is still the lit one")
	Kit.free_all(ctx)


func test_the_jobs_screen_has_a_row_for_a_recruit() -> void:
	var ctx := Kit.build(1280, 800, 1, true)
	var p = _recruit(ctx, 2)
	Kit.update(ctx)
	ctx.hud.open_jobs(ctx.sim)
	await Kit.settle()
	var screen = ctx.hud.jobs_screen
	check(screen != null, "the screen is up")
	check(screen.rows.has(p.id), "with a row for the newcomer")
	screen.close()
	Kit.free_all(ctx)


func test_the_pictures_of_a_recruit_are_found_wherever_they_are_asked_for() -> void:
	var ctx := Kit.build(1280, 800, 1, true)
	var p = _recruit(ctx, 1)
	eq(ctx.hud.portrait_of(p), GD.tex(PORTRAIT), "the def's own")
	eq(ctx.hud.portrait_of(Kit.person(ctx, "ana")), GD.tex(ctx.g.data.portraits["ana"]), "the roster's for the six")
	var q = _recruit(ctx, 2, "")
	check(ctx.hud.portrait_of(q) == null, "none for one who has none")
	var r = _recruit(ctx, 3, "res://assets/portraits/no_such_face.png")
	check(ctx.hud.portrait_of(r) == null, "and none, with no error, for a picture that is not there")
	Kit.free_all(ctx)


# ----------------------------------------------------------------------- the bodies --

func _look(extra: Dictionary = {}) -> Dictionary:
	var look := {"seed": 7, "skin": "#f0c8a8", "hair": "short", "hairColor": "#c8a060", "browColor": "#c8a060", "top": "#c0392b", "topStyle": "tee",
		"outer": "#2e7d6b", "outerStyle": "jacket", "pants": "#383843", "shoes": "#2b2521"}
	look.merge(extra, true)
	return look


## A texture's picture as plain RGBA8 with no mipmaps, so that two can be compared.
func _plain(tex: Texture2D) -> Image:
	var img := tex.get_image()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _labels(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append(node)
	for c in node.get_children():
		_labels(c, out)
	return out


func _count_near(img: Image, hex: String, reach: float) -> int:
	var want := Color.html(hex)
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.9 and absf(c.r - want.r) + absf(c.g - want.g) + absf(c.b - want.b) < reach:
				n += 1
	return n


func test_a_recruit_is_drawn_on_the_body_of_the_baked_person_most_like_them() -> void:
	var data := GD.load_all()
	check(["ruth", "ana", "marcus"].has(RecruitArt.base_for(data, _look())), "no hat: a body with no hat")
	check(["dez", "walt", "hector"].has(RecruitArt.base_for(data, _look({"hat": "cap", "hatColor": "#335577"}))), "a hat: a body with one")
	var dark := RecruitArt.base_for(data, _look({"hairColor": "#1a1210"}))
	check(["ana", "marcus"].has(dark), "dark hair on dark hair: %s" % dark)
	eq(RecruitArt.base_for(data, _look()), RecruitArt.base_for(data, _look()), "the same look, the same body")
	eq(RecruitArt.base_for({}, _look()), "ruth", "and with no data a body that is there")


func test_a_recruits_body_is_the_baked_one_in_the_colours_of_their_look() -> void:
	var data := GD.load_all()
	var look := _look({"skin": "#e8b890", "top": "#3a62c8", "outer": "#c85a1e", "hairColor": "#d8c070"})
	var base := RecruitArt.base_for(data, look)
	var bodies := RecruitArt.bodies(data, look, base)
	eq(bodies.keys().size(), 3, "three views")
	for view in ["S", "E", "N"]:
		var baked: Image = _plain(GD.tex(String(data.pawn.files[base][view])))
		var made: Image = _plain(bodies[view])
		eq(made.get_size(), baked.get_size(), "%s: the same size" % view)
	var s: Image = _plain(bodies["S"])
	var baked_s: Image = _plain(GD.tex(String(data.pawn.files[base]["S"])))
	check(s.get_data() != baked_s.get_data(), "it is not the baked person's own colours")
	var same_alpha := true
	for y in range(0, s.get_height(), 3):
		for x in range(0, s.get_width(), 3):
			if absf(s.get_pixel(x, y).a - baked_s.get_pixel(x, y).a) > 0.01:
				same_alpha = false
	check(same_alpha, "but the same shape")
	check(_count_near(s, "#e8b890", 0.25) > 60, "there is skin of their colour in it")
	check(_count_near(s, "#3a62c8", 0.3) + _count_near(s, "#c85a1e", 0.3) > 200, "and clothes of theirs")
	check(_count_near(baked_s, "#e8b890", 0.25) < _count_near(s, "#e8b890", 0.25), "which the baked body did not have")


func test_a_body_is_made_the_same_way_every_time_and_another_look_makes_another() -> void:
	var data := GD.load_all()
	var a := _look()
	var base := RecruitArt.base_for(data, a)
	var one: Image = _plain(RecruitArt.bodies(data, a, base)["S"])
	var two: Image = _plain(RecruitArt.bodies(data, a, base)["S"])
	check(one.get_data() == two.get_data(), "the same look, the same pixels")
	var other: Image = _plain(RecruitArt.bodies(data, _look({"skin": "#4a2f20", "top": "#6a4a8a"}), base)["S"])
	check(one.get_data() != other.get_data(), "another look, other pixels")
	eq(RecruitArt.bodies(data, a, "nobody"), {}, "and no body for a person who is not baked")


# ----------------------------------------------------------------- the game scene --

## The small start's first caller walks in at the gate: the queue's first person is on the way and the rules let them in.
func _let_in_the_first_caller(main) -> Dictionary:
	var sim = main.sim
	var def: Dictionary = sim.recruits.queue.pop_front()
	sim.recruits.incoming.append({"def": def, "day": sim.day})
	sim.minutes = 7.2 * 60.0
	sim.phase = "day"
	sim.recruits.update(0.0)
	return def


func test_a_small_start_has_three_pawns_and_three_cards() -> void:
	var g := MenuFakes.game({"difficulty": 1, "seed": 7, "crew": 3})
	var main = g.main
	eq(main.sim.people.size(), 3, "three people")
	check(main.sim.recruits.small, "a small start")
	eq(main.hud.cards.size(), 3, "three cards")
	var pawns := 0
	for p in main.sim.people:
		pawns += 1 if main.pawn_nodes.has(p) else 0
	eq(pawns, 3, "and three pawns")
	await MenuFakes.leave(g)


func test_a_run_with_no_crew_in_its_meta_is_the_classic_six() -> void:
	var g := MenuFakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	eq(main.sim.people.size(), 6, "six people")
	check(not main.sim.recruits.small, "no recruits")
	eq(main.hud.cards.size(), 6, "six cards")
	await MenuFakes.leave(g)
	var h := MenuFakes.game({"difficulty": 1, "seed": 7, "crew": 6})
	eq(h.main.sim.people.size(), 6, "a full crew is six too")
	await MenuFakes.leave(h)


func test_someone_who_arrives_at_the_gate_gets_a_pawn_a_card_and_a_cue() -> void:
	var g := MenuFakes.game({"difficulty": 1, "seed": 7, "crew": 3})
	var main = g.main
	var sound = MenuFakes.FakeSound.new()
	main.add_child(sound)
	main.sound.queue_free()
	main.sound = sound
	var def := _let_in_the_first_caller(main)
	eq(main.sim.people.size(), 4, "the newcomer is in the crew")
	var p = main.sim.people[3]
	eq(String(p.id), String(def.id), "it is the caller")
	main._handle_events()
	check(sound.played.has("bell"), "a bell for the arrival: %s" % str(sound.played))
	check(sound.ui_played.has("ui_confirm"), "and the chime: %s" % str(sound.ui_played))
	eq(main.hud.cards.size(), 4, "a card at once")
	check(main.hud.banner_title.text.contains("GATE"), "the banner says so: '%s'" % main.hud.banner_title.text)
	check(main.hud.cards[3].card.modulate != Color.WHITE, "and the card is lit")
	main._sync_views()
	check(main.pawn_nodes.has(p), "the yard draws them")
	check(main.pawn_nodes[p].visible or not main.view_rect().has_point(Vector2(p.x, p.y)), "where they stand")
	eq(main.pawn_nodes[p].tex.keys().size(), 3, "with a body in three views")
	await MenuFakes.leave(g)


func test_a_pawn_is_made_for_anyone_the_sync_finds_without_one() -> void:
	# an arrival the events did not mention (the save was loaded with recruits in it, a test added them): still drawn
	var g := MenuFakes.game({"difficulty": 1, "seed": 7, "crew": 3})
	var main = g.main
	var def: Dictionary = main.sim.recruits.make_def(0)
	def["bitten"] = false
	var p = main.sim.add_person(def)
	main._sync_views()
	check(main.pawn_nodes.has(p), "a pawn")
	main.hud.update_hud(main.sim, 1, true, 0)
	eq(main.hud.cards.size(), 4, "and a card")
	await MenuFakes.leave(g)


func test_tab_goes_round_the_recruits_too_and_a_click_picks_them() -> void:
	var g := MenuFakes.game({"difficulty": 1, "seed": 7, "crew": 3})
	var main = g.main
	_let_in_the_first_caller(main)
	main._handle_events()
	main._sync_views()
	var seen := {}
	for i in 4:
		main._key(KEY_TAB)
		seen[String(main.selection.ref.id)] = true
	eq(seen.size(), 4, "four Tabs reach four people: %s" % str(seen.keys()))
	check(seen.has("ana"), "Ana among them")
	main._select(null)
	var ana = main.sim.people[3]
	var at: Vector2 = Vector2(ana.x, ana.y - 0.3)
	var hit = main._pick(at)
	check(hit != null and hit.kind == "person" and hit.ref == ana, "a click on the yard finds her")
	await MenuFakes.leave(g)


func test_the_crew_comes_from_the_command_line() -> void:
	eq(Main.crew_from_args([]), 0, "no flag: no choice (the classic start)")
	eq(Main.crew_from_args(["--shot=a.png", "--new=1", "--seed=4"]), 0, "--new and --seed alone keep the classic start")
	eq(Main.crew_from_args(["--crew=3"]), 3, "--crew=3")
	eq(Main.crew_from_args(["--crew=6"]), 6, "--crew=6")
	eq(Main.crew_from_args(["--crew=small"]), 3, "small is three")
	eq(Main.crew_from_args(["--crew=full"]), 6, "full is six")
	eq(Main.crew_from_args(["--crew=2"]), 3, "fewer than three is three")
	eq(Main.crew_from_args(["--crew=4"]), 4, "four is four")
	eq(Main.crew_from_args(["--crew=5"]), 5, "five is five")
	eq(Main.crew_from_args(["--crew=9"]), 6, "more than six is six")
	eq(Main.crew_from_args(["--crew=lots"]), 0, "words that are not a crew are no choice")


func test_a_new_run_asked_for_with_a_crew_leaves_it_in_the_meta() -> void:
	var g := MenuFakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	var got: Array = []
	main.restart = func(meta): got.append(meta)
	main.start_run(2, 4242)
	eq(got.back(), {"difficulty": 2, "seed": 4242}, "no crew asked for: none in it (it is six)")
	main.start_run(2, 4242, 3)
	eq(got.back(), {"difficulty": 2, "seed": 4242, "crew": 3}, "a small crew")
	main.start_run(1, 5, 6)
	eq(got.back(), {"difficulty": 1, "seed": 5, "crew": 6}, "a full one")
	main.start_run(1, 5, 4)
	eq(got.back().crew, 4, "four is four")
	main.start_run(1, 5, 5)
	eq(got.back().crew, 5, "five is five")
	main.start_run(1, 5, 9)
	eq(got.back().crew, 6, "more than six is the full crew")
	await MenuFakes.leave(g)


# ----------------------------------------------------------------- the new-game menu --

func _menu(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := MenuFakes.build(width, height)
	ctx["screen"] = ctx.shell.open_new_game()
	await Kit.settle()
	return ctx


func test_the_new_game_menu_offers_two_crews_and_begins_on_five() -> void:
	var ctx: Dictionary = await _menu()
	var screen = ctx.screen
	eq(screen.crew, 5, "a crew of five is the one chosen to begin with (three felt too few to do everything)")
	eq(screen.crew_cards.size(), 2, "two crews to choose from (round 26: the old full crew of six is gone)")
	check(screen.crew_cards[1].button_pressed and not screen.crew_cards[0].button_pressed, "the crew of five's card is the one pressed")
	var small := Kit.texts(screen.crew_cards[0])
	var five := Kit.texts(screen.crew_cards[1])
	check(small.has("Small crew (3)"), "named: %s" % str(small))
	check(five.has("Crew of five"), "and the other: %s" % str(five))
	check(small.size() == 2 and five.size() == 2 and String(small[1]) != "" and String(five[1]) != "", "each with a line of its own")
	check(String(small[1]).to_lower().contains("radio") and String(five[1]).to_lower().contains("radio"), "the small crews say the others call in: '%s' '%s'" % [small[1], five[1]])
	MenuFakes.free_all(ctx)


func test_the_crew_chosen_is_what_the_game_is_asked_for() -> void:
	var ctx: Dictionary = await _menu()
	var screen = ctx.screen
	screen.seed_edit.text = "4242"
	screen.seed_edit.text_changed.emit("4242")
	Kit.click_on(screen.start_button)
	eq(ctx.main.last("start_run"), ["start_run", 1, 4242, 5], "Start with what it showed: a crew of five")
	ctx.main.calls.clear()
	var again = ctx.shell.open_new_game()
	await Kit.settle()
	Kit.click_on(again.crew_cards[0])
	eq(again.crew, 3, "a click on the small crew")
	check(again.crew_cards[0].button_pressed and not again.crew_cards[1].button_pressed, "lights its card and no other")
	again.seed_edit.text = "17"
	again.seed_edit.text_changed.emit("17")
	Kit.click_on(again.start_button)
	eq(ctx.main.last("start_run"), ["start_run", 1, 17, 3], "and asks for three")
	MenuFakes.free_all(ctx)


func test_the_crew_can_be_chosen_with_the_keyboard() -> void:
	var ctx: Dictionary = await _menu()
	var screen = ctx.screen
	screen.crew_cards[0].grab_focus()
	MenuFakes.key(KEY_ENTER)
	eq(screen.crew, 3, "Enter on the small crew's card picks it")
	screen.crew_cards[1].grab_focus()
	MenuFakes.key(KEY_SPACE)
	eq(screen.crew, 5, "Space on the crew of five picks that")
	var focus_order: Array = []
	var f: Control = screen.crew_cards[0]
	for i in 4:
		focus_order.append(f)
		f = f.find_next_valid_focus()
	check(focus_order.has(screen.crew_cards[1]), "Tab reaches every card")
	MenuFakes.free_all(ctx)


func test_the_last_crew_chosen_is_remembered_like_the_difficulty() -> void:
	var ctx: Dictionary = await _menu()
	ctx.screen.crew_cards[0].pressed.emit()
	ctx.screen.start_button.pressed.emit()
	eq(int(Prefs.get_value("ui", "crew", 5)), 3, "it was kept")
	var again = ctx.shell.open_new_game()
	await Kit.settle()
	eq(again.crew, 3, "and is the one chosen next time")
	check(again.crew_cards[0].button_pressed, "with its card pressed")
	Prefs.set_value("ui", "crew", 17)
	var odd = ctx.shell.open_new_game()
	await Kit.settle()
	eq(odd.crew, 5, "a stored crew that is not one of the choices is the usual five")
	Prefs.set_value("ui", "crew", 6)
	var old = ctx.shell.open_new_game()
	await Kit.settle()
	eq(old.crew, 5, "and so is a stored six, from the days of the full crew")
	MenuFakes.free_all(ctx)


func test_the_new_game_menu_fits_a_narrow_window() -> void:
	for wh in [[700, 560], [700, 700], [1280, 800]]:
		var ctx: Dictionary = await _menu(wh[0], wh[1])
		var screen = ctx.screen
		var win := Rect2(0, 0, wh[0], wh[1])
		var r := Kit.rect(screen.panel)
		check(win.encloses(r.grow(-0.5)), "%s: the panel is in the window: %s" % [str(wh), str(r)])
		# the body scrolls when it must: both crew cards are reachable, and each is as wide as a card should be
		var small: Rect2 = Kit.rect(screen.crew_cards[0])
		var full: Rect2 = Kit.rect(screen.crew_cards[1])
		check(small.size.x >= 120.0 and full.size.x >= 120.0, "%s: the cards are wide enough to read: %s %s" % [str(wh), str(small.size), str(full.size)])
		for card in screen.crew_cards:
			for l in _labels(card):
				check(l.get_theme_font_size("font_size") >= 12, "%s: '%s' is 12 px or more" % [str(wh), l.text])
		MenuFakes.free_all(ctx)


# ----------------------------------------------------------- new games from other places --

func test_a_new_game_after_a_defeat_keeps_the_crew_the_run_began_with() -> void:
	for small in [false, true]:
		var ctx := Kit.build()
		var meta: Array = []
		ctx.hud.restart = func(m): meta.append(m)
		ctx.sim.recruits.small = small
		ctx.sim.over = "defeat"
		Kit.update(ctx)
		var again: Button = null
		for b in ctx.hud.game_over.find_children("*", "Button", true, false):
			if b.text == "New game":
				again = b
		check(again != null, "a New game button")
		again.pressed.emit()
		eq(meta.size(), 1, "one run asked for")
		eq(int(meta[0].get("crew", 6)), 3 if small else 6, "small=%s: the same kind of start" % str(small))
		check(small == meta[0].has("crew"), "a small crew is named in the choice and a classic one is not")
		Kit.free_all(ctx)


## The arrival that `--recruit` puts on the screen: the first caller in the queue, or the one named, comes in at once.
func test_recruit_flag_lets_the_named_caller_in_at_once() -> void:
	var g := MenuFakes.game({"difficulty": 1, "seed": 7, "crew": 3})
	var main = g.main
	check(main.stage_recruit("walt"), "Walt can be let in")
	eq(main.sim.people.size(), 4, "he is here")
	eq(String(main.sim.people[3].id), "walt", "he is the fourth")
	check(main.sim.hour >= 7.0 and main.sim.phase == "day", "at the gate hour, by day")
	check(not main.stage_recruit("nobody"), "someone who is not waiting is not")
	check(main.stage_recruit(""), "no name: the next in the queue")
	eq(main.sim.people.size(), 5, "he is here")
	check(String(main.sim.people[4].id) == "ana", "it is Ana")
	await MenuFakes.leave(g)
	var h := MenuFakes.game({"difficulty": 1, "seed": 7})
	check(not h.main.stage_recruit("ana"), "a classic start has nobody waiting")
	await MenuFakes.leave(h)


# ----------------------------------------------------------------------- the call card --

func test_the_call_card_reads_well_and_says_why_the_way_in_is_off_when_there_is_no_bed() -> void:
	for beds_left in [true, false]:
		var ctx := Kit.build(1280, 800, 1, true)
		var sim = ctx.sim
		sim.recruits.small = true
		if beds_left:
			# a small crew: three of them have gone (the beds are six)
			sim.people.resize(3)
		sim.storyteller.force("survivor_call")
		var card = RadioCard.new()
		ctx.holder.add_child(card)
		card.setup(ctx.hud, sim)
		await Kit.settle()
		var words := Kit.texts(card)
		check(words.has("A voice on the radio"), "the title: %s" % str(words))
		eq(card.choice_buttons.size(), 2, "two answers")
		eq(card.choice_buttons[0].text, "Tell them the way in", "the way in")
		eq(card.choice_buttons[1].text, "Not yet", "and not yet")
		check(card.choice_buttons[1].disabled == false, "not yet can always be said")
		eq(card.choice_buttons[0].disabled, not beds_left, "beds left=%s: the way in is %s" % [str(beds_left), "on" if beds_left else "off"])
		eq(words.has("No bed for them"), not beds_left, "and the page says why when it is off: %s" % str(words))
		for l in _labels(card):
			check(l.get_theme_font_size("font_size") >= 12, "'%s' is 12 px or more" % l.text)
		card.put_away()
		Kit.free_all(ctx)


# ------------------------------------------------------------------------ a loaded game --

func test_a_saved_small_start_with_recruits_in_it_is_loaded_as_it_was_saved() -> void:
	var path := "user://test_recruit_view_%d.json" % OS.get_process_id()
	var a := Helpers.make(7, 1, 3)
	var def: Dictionary = a.sim.recruits.make_def(0)
	def["bitten"] = false
	def["portrait"] = PORTRAIT
	a.sim.add_person(def)
	a.sim.recruits.arrived.append(def)
	check(SaveGame.write(a.sim, path), "the save is written")
	var saved_ids: Array = []
	for p in a.sim.people:
		saved_ids.append(String(p.id))
	a.world.free()
	var g := MenuFakes.game({"load": path})
	var main = g.main
	var ids: Array = []
	for p in main.sim.people:
		ids.append(String(p.id))
	eq(ids, saved_ids, "the same people, in the same order")
	eq(main.hud.cards.size(), ids.size(), "a card each")
	var recruit = main.sim.people[ids.size() - 1]
	check(main.pawn_nodes.has(recruit), "and a pawn each")
	eq(main.pawn_nodes[recruit].tex.keys().size(), 3, "the recruit's with a body of three views")
	eq(main.hud.cards[ids.size() - 1].pic.texture, GD.tex(PORTRAIT), "and the recruit's card has the picture the def names")
	check(main.sim.recruits.small, "still a small start")
	await MenuFakes.leave(g)
	MenuFakes.clean([path])


func test_a_picture_that_the_editor_has_not_imported_yet_is_read_from_its_file() -> void:
	var path := "user://test_recruit_face_%d.png" % OS.get_process_id()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.4, 0.2))
	img.save_png(path)
	var ctx := Kit.build(1280, 800, 1, true)
	var p = _recruit(ctx, 0, path)
	var tex: Texture2D = ctx.hud.portrait_of(p)
	check(tex != null and tex.get_width() == 8, "the picture is there")
	Kit.update(ctx)
	check(Kit.card(ctx, p).pic.texture == tex, "on the card")
	Kit.free_all(ctx)
	MenuFakes.clean([path])
