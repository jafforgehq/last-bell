extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")

const SAVE := "user://hud_test_save.json"
const SIZES := [[1280, 800], [980, 700], [700, 700]]


## A game on the night of day 7 with 42 kills, not over yet.
func _game(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := Kit.build(width, height)
	ctx["restarts"] = []
	ctx.hud.save_paths = [SAVE]
	ctx.hud.restart = func(meta): ctx.restarts.append(meta)
	ctx.sim.day = 7
	ctx.sim.kills = 42
	ctx.sim.scenario.today = 7
	ctx.sim.phase = "night"
	return ctx


## The run ends; the HUD notices at its next update.
func _end(ctx: Dictionary, result: String) -> void:
	ctx.sim.over = result
	Kit.update(ctx)


func _remove_save() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _button(ctx: Dictionary, text: String) -> Button:
	for b in ctx.hud.game_over.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func test_no_overlay_while_the_run_goes_on() -> void:
	var ctx := _game()
	Kit.update(ctx)
	check(ctx.hud.game_over == null, "nothing shown")
	Kit.free_all(ctx)


func test_defeat_says_everyone_is_gone_and_shows_the_numbers() -> void:
	_remove_save()
	var ctx := _game()
	for p in ctx.sim.people:
		p.dead = true
	Kit.person(ctx, "walt").turned = true
	Kit.person(ctx, "hector").away = {"kind": "exile"}
	_end(ctx, "defeat")
	check(ctx.hud.game_over != null, "the overlay is up")
	var all := Kit.texts(ctx.hud.game_over)
	check(all.has("Everyone is gone"), "the title")
	eq(ctx.hud.game_over.stat_values.days.text, "7", "days survived: it was night on day 7")
	eq(ctx.hud.game_over.stat_values.kills.text, "42", "walkers put down")
	eq(ctx.hud.game_over.stat_values.lost.text, "5 of 6", "five died or turned, one was sent out")
	for fate in ["Died", "Turned", "Left"]:
		check(all.has(fate), "a survivor who %s is listed" % fate.to_lower())
	Kit.free_all(ctx)


func test_days_survived_counts_only_days_that_reached_the_night() -> void:
	var ctx := _game()
	ctx.sim.phase = "day"
	_end(ctx, "defeat")
	eq(ctx.hud.game_over.stat_values.days.text, "6", "lost in the morning of day 7: six days survived")
	Kit.free_all(ctx)


func test_victory_says_the_thirty_days_are_over() -> void:
	var ctx := _game()
	_end(ctx, "victory")
	var all := Kit.texts(ctx.hud.game_over)
	check(all.has("The thirty days are over"), "the title: %s" % str(all))
	check(all.has("A convoy is on the road at dawn. You held."), "and a plain line under it")
	check(not all.has("Rescued"), "the old title is gone")
	check(not all.has("Everyone is gone"), "and it is not the defeat screen")
	eq(ctx.hud.game_over.stat_values.days.text, "30", "the whole run counts as survived")
	Kit.free_all(ctx)


func test_victory_still_shows_the_days_the_kills_and_the_fates() -> void:
	_remove_save()
	var ctx := _game()
	# the dawn that starts day 31, with four of the six alive
	ctx.sim.scenario.today = 31
	ctx.sim.phase = "day"
	Kit.person(ctx, "dez").dead = true
	Kit.person(ctx, "walt").dead = true
	Kit.person(ctx, "walt").turned = true
	Kit.person(ctx, "hector").away = {"kind": "exile"}
	Kit.person(ctx, "hector").dead = true
	_end(ctx, "victory")
	var go = ctx.hud.game_over
	eq(go.stat_values.days.text, "30", "days survived")
	eq(go.stat_values.kills.text, "42", "walkers put down")
	eq(go.stat_values.lost.text, "2 of 6", "two died or turned, one was sent out")
	var all := Kit.texts(go)
	for fate in ["Alive", "Died", "Turned", "Left"]:
		check(all.has(fate), "a survivor who is %s is listed" % fate.to_lower())
	var b := _button(ctx, "New game")
	check(b != null, "there is still a New game button")
	b.pressed.emit()
	eq(ctx.restarts.size(), 1, "and it works")
	Kit.free_all(ctx)


func test_the_victory_title_follows_the_length_of_the_run() -> void:
	var cases := {7: "The seven days are over", 10: "The ten days are over", 21: "The twenty-one days are over", 30: "The thirty days are over", 45: "The forty-five days are over", 100: "The 100 days are over"}
	for total in cases:
		var ctx := _game()
		ctx.sim.scenario.total = total
		_end(ctx, "victory")
		check(Kit.texts(ctx.hud.game_over).has(cases[total]), "%d days: %s" % [total, cases[total]])
		Kit.free_all(ctx)


func test_the_victory_screen_fits_the_window_at_every_width() -> void:
	_remove_save()
	for size in SIZES:
		var ctx := _game(size[0], size[1])
		_end(ctx, "victory")
		await Kit.settle()
		await Kit.settle()
		var win := Rect2(0, 0, size[0], size[1])
		var r := Kit.rect(ctx.hud.game_over.panel)
		check(r.size != Vector2.ZERO and win.encloses(r.grow(-0.5)), "the panel is inside the %d px window: %s" % [size[0], str(r)])
		var b := _button(ctx, "New game")
		check(win.encloses(Kit.rect(b).grow(-0.5)) and r.encloses(Kit.rect(b)), "the button is inside it at %d px" % size[0])
		Kit.free_all(ctx)


func test_the_overlay_shows_once() -> void:
	var ctx := _game()
	_end(ctx, "defeat")
	var first = ctx.hud.game_over
	Kit.update(ctx)
	Kit.update(ctx)
	eq(ctx.hud.game_over, first, "the same overlay")
	var n := 0
	for c in ctx.hud.get_children():
		if c == first:
			n += 1
	eq(n, 1, "added once")
	Kit.free_all(ctx)


func test_new_game_starts_a_run_with_the_same_difficulty_and_a_new_seed() -> void:
	_remove_save()
	var ctx := _game()
	ctx.sim.difficulty = 2
	_end(ctx, "defeat")
	var b := _button(ctx, "New game")
	check(b != null, "there is a New game button")
	b.pressed.emit()
	eq(ctx.restarts.size(), 1, "it asks for a new run once")
	eq(int(ctx.restarts[0].difficulty), 2, "on the same difficulty")
	check(ctx.restarts[0].has("seed"), "with a seed")
	check(not ctx.restarts[0].has("load"), "and no save")
	Kit.free_all(ctx)


func test_load_last_save_shows_only_when_there_is_a_save() -> void:
	_remove_save()
	var ctx := _game()
	_end(ctx, "defeat")
	check(_button(ctx, "Load last save") == null, "no save, no button")
	Kit.free_all(ctx)
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	ctx = _game()
	_end(ctx, "defeat")
	var b := _button(ctx, "Load last save")
	check(b != null, "a save: the button is there")
	if b != null:
		b.pressed.emit()
		eq(ctx.restarts, [{"load": SAVE}], "it loads that save")
	Kit.free_all(ctx)
	_remove_save()


func test_the_overlay_blocks_the_hud_behind_it() -> void:
	var ctx := _game()
	_end(ctx, "defeat")
	eq(ctx.hud.game_over.mouse_filter, Control.MOUSE_FILTER_STOP, "clicks stop at the overlay")
	check(ctx.hud.game_over.get_index() == ctx.hud.get_child_count() - 1, "it is on top")
	Kit.free_all(ctx)


func test_the_overlay_fits_the_window_at_every_width() -> void:
	_remove_save()
	for size in SIZES:
		var ctx := _game(size[0], size[1])
		_end(ctx, "defeat")
		await Kit.settle()
		await Kit.settle()
		var win := Rect2(0, 0, size[0], size[1])
		var go = ctx.hud.game_over
		var r := Kit.rect(go.panel)
		check(r.size != Vector2.ZERO and win.encloses(r.grow(-0.5)), "the panel is inside the %d px window: %s" % [size[0], str(r)])
		var b := _button(ctx, "New game")
		check(win.encloses(Kit.rect(b).grow(-0.5)) and r.encloses(Kit.rect(b)), "the button is inside it at %d px" % size[0])
		Kit.free_all(ctx)


func test_the_new_game_button_works_with_the_mouse() -> void:
	_remove_save()
	var ctx := _game()
	_end(ctx, "defeat")
	await Kit.settle()
	await Kit.settle()
	Kit.click_on(_button(ctx, "New game"))
	eq(ctx.restarts.size(), 1, "a real click starts a new run")
	Kit.free_all(ctx)
