extends "res://tests/case.gd"
## The HUD's side of the tutorial (the block at the end of scripts/ui/hud.gd): `anchor_rect`
## finds the named parts the coach points at, and `set_locked` ghosts the buttons a step does
## not allow.

const Kit := preload("res://tests/hud_kit.gd")
const Tut := preload("res://tests/tutorial_kit.gd")

const STEPS := "res://assets/data/tutorial.json"
## Anchors that are in the world, not the HUD: the coach resolves those itself.
const WORLD := ["person:", "wall:", "spot:", "bench"]


## Every anchor name the lessons use, from the data: the target of a step, the one it points
## at while it waits, and the ones an anchor chooses between.
func _anchor_names() -> Array:
	var names: Array = []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STEPS))
	for step in parsed.steps:
		for key in ["anchor", "wait_anchor"]:
			for entry in step.get(key, []):
				var name: String = String(entry.name) if typeof(entry) == TYPE_DICTIONARY else String(entry)
				if not names.has(name):
					names.append(name)
	return names


func _is_world(name: String) -> bool:
	for prefix in WORLD:
		if name.begins_with(prefix):
			return true
	return false


## A HUD with fake modules, the dialog's places there, everyone free to go, and Hector able to be
## treated, so every button the lessons point at can exist.
func _hud(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := Kit.build(width, height)
	var sim = ctx.sim
	sim.scavenge.can = true
	sim.scavenge.list = Kit.sample_sites()
	sim.medical.treat["hector"] = true
	Kit.update(ctx)
	await Kit.settle()
	return ctx


func _found(ctx: Dictionary, names: Array, into: Dictionary) -> void:
	for name in names:
		var r: Rect2 = ctx.hud.anchor_rect(name)
		if r.size.x > 0.0 and r.size.y > 0.0:
			into[name] = r


func test_every_hud_part_the_lessons_point_at_can_be_found() -> void:
	for size in [Vector2i(1280, 800), Vector2i(980, 700), Vector2i(1920, 1080), Vector2i(900, 640)]:
		var ctx: Dictionary = await _hud(size.x, size.y)
		var hud = ctx.hud
		var names: Array = []
		for name in _anchor_names():
			if not _is_world(name):
				names.append(name)
		var found := {}
		# nothing selected: the stores, the crew, the clock and the speed controls
		_found(ctx, names, found)
		# a person selected: their orders and their weapon row
		for id in ["hector", "ana", "dez", "marcus", "ruth"]:
			Kit.select(ctx, Kit.person(ctx, id))
			await Kit.settle()
			Kit.update(ctx)
			_found(ctx, names, found)
		# a wall piece selected
		ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
		await Kit.settle()
		Kit.update(ctx)
		_found(ctx, names, found)
		# the scavenging dialog open
		Kit.select(ctx, Kit.person(ctx, "ana"))
		hud.open_scavenge(hud.selection)
		await Kit.settle()
		_found(ctx, names, found)
		var where := "at %dx%d" % [size.x, size.y]
		for name in names:
			check(found.has(name), "%s resolves %s" % [name, where])
		var screen := Rect2(0, 0, size.x, size.y).grow(2.0)
		for name in found:
			check(screen.encloses(found[name]), "%s is inside the window %s: %s" % [name, where, str(found[name])])
		Kit.free_all(ctx)


func test_the_stores_can_be_found_one_by_one() -> void:
	var ctx: Dictionary = await _hud()
	var hud = ctx.hud
	var panel: Rect2 = hud.anchor_rect("stores")
	check(panel.size.x > 0.0, "the stores panel")
	var seen: Array = []
	for kind in ["ammo", "scrap", "food", "water", "meds"]:
		var r: Rect2 = hud.anchor_rect("stores." + kind)
		check(r.size.x > 0.0 and r.size.y > 0.0, "%s has a row" % kind)
		check(panel.grow(1.0).encloses(r), "%s is inside the panel" % kind)
		seen.append(r)
	for i in seen.size() - 1:
		check(seen[i].position.y < seen[i + 1].position.y, "the rows go down the panel in order")
	check(hud.anchor_rect("stores.nonsense").size == Vector2.ZERO, "a store there is not")
	Kit.free_all(ctx)


func test_parts_that_are_not_there_have_no_rectangle() -> void:
	var ctx: Dictionary = await _hud()
	var hud = ctx.hud
	var none := Rect2()
	eq(hud.anchor_rect("nonsense"), none, "a name nobody knows")
	eq(hud.anchor_rect("card:nobody"), none, "a card nobody has")
	eq(hud.anchor_rect("gizmo:post"), none, "an order button with nothing selected")
	eq(hud.anchor_rect("inspect"), none, "the selection panel with nothing selected")
	eq(hud.anchor_rect("inspect.weapon"), none, "its weapon row too")
	eq(hud.anchor_rect("dialog.send"), none, "the dialog's Send button with no dialog")
	eq(hud.anchor_rect("dialog.site:houses"), none, "or its places")
	eq(hud.anchor_rect("speed.9"), none, "a speed that is not there")
	eq(hud.anchor_rect("speed.-1"), none, "or one below zero")
	Kit.select(ctx, Kit.person(ctx, "ruth"))
	await Kit.settle()
	eq(hud.anchor_rect("gizmo:lure"), none, "no Lure button for a person")
	eq(hud.anchor_rect("gizmo:post").size.x > 0.0, true, "but a To post button")
	eq(hud.anchor_rect("dialog.site:nowhere"), none, "a place that is not on offer")
	hud.select(null)
	await Kit.settle()
	eq(hud.anchor_rect("gizmo:post"), none, "and none again once nothing is selected")
	Kit.free_all(ctx)


func test_the_forecast_line_and_the_alerts_have_a_place_even_when_empty() -> void:
	var ctx: Dictionary = await _hud()
	var hud = ctx.hud
	var alerts: Rect2 = hud.anchor_rect("alerts")
	check(alerts.size.x > 0.0 and alerts.size.y > 0.0, "the alerts have somewhere to point at with none up")
	var clock: Rect2 = hud.anchor_rect("clock")
	check(alerts.position.y >= clock.end.y, "under the clock: %s %s" % [str(alerts), str(clock)])
	eq(hud.anchor_rect("clock.forecast"), Rect2(), "no forecast line before the lookout speaks")
	ctx.sim.tactics.told = Kit.forecast()
	Kit.update(ctx)
	await Kit.settle()
	check(hud.anchor_rect("clock.forecast").size.x > 0.0, "and one once he has")
	Kit.free_all(ctx)


# --------------------------------------------------------------------- lock --

func _button(ctx: Dictionary, id: String) -> Button:
	return Kit.gizmo(ctx, id)


func test_the_lock_ghosts_the_orders_a_step_does_not_allow() -> void:
	var ctx: Dictionary = await _hud()
	var hud = ctx.hud
	Kit.select(ctx, Kit.person(ctx, "hector"))
	await Kit.settle()
	Kit.update(ctx)
	var draft := _button(ctx, "draft")
	var post := _button(ctx, "post")
	var normal_before: StyleBox = post.get_theme_stylebox("hover")
	hud.set_locked(func(kind: String, arg): return kind == "gizmo" and arg == "post")
	check(post.modulate.a > 0.9, "the order the step asks for stays bright")
	check(draft.modulate.a < 0.5, "the others are ghosts")
	eq(draft.mouse_default_cursor_shape, Control.CURSOR_FORBIDDEN, "with a cursor that says no")
	check(draft.get_theme_stylebox("hover") == draft.get_theme_stylebox("normal"), "and no hover look")
	check(draft.get_theme_stylebox("pressed") == draft.get_theme_stylebox("normal"), "or pressed look")
	check(not draft.disabled, "they can still be pressed: the game refuses and says why")
	# the speed controls and the fields button follow the same rule
	for b in hud.speed_buttons:
		check(b.modulate.a < 0.5, "a speed button is a ghost")
	check(hud.fields_button.modulate.a < 0.5, "so is the fields button")
	# the HUD brightens an order every tenth of a second: the next frame puts the ghost back
	Kit.update(ctx)
	hud.apply_lock()
	check(draft.modulate.a < 0.5, "a refresh of the HUD does not undo the lock once it is applied again")
	# a new selection rebuilds the buttons: the lock is on them from the next frame
	Kit.select(ctx, Kit.person(ctx, "ruth"))
	await Kit.settle()
	hud.apply_lock()
	check(_button(ctx, "draft").modulate.a < 0.5 and _button(ctx, "post").modulate.a > 0.9, "the rebuilt buttons are locked the same way")
	# lifting the lock gives everything back
	hud.set_locked(Callable())
	for id in Kit.gizmo_ids(ctx):
		var b := _button(ctx, id)
		check(b.modulate.a > 0.5, "%s is bright again" % id)
		eq(b.mouse_default_cursor_shape, Control.CURSOR_ARROW, "%s has its cursor back" % id)
	for b in hud.speed_buttons:
		check(b.modulate.a > 0.9, "a speed button is bright again")
	check(hud.fields_button.modulate.a > 0.9, "and the fields button")
	var again := _button(ctx, "post")
	check(again.get_theme_stylebox("hover") != again.get_theme_stylebox("normal"), "the hover look came back")
	check(normal_before != null, "(the hover look was there before the lock)")
	Kit.free_all(ctx)


func test_a_lock_that_allows_everything_ghosts_nothing() -> void:
	var ctx: Dictionary = await _hud()
	var hud = ctx.hud
	Kit.select(ctx, Kit.person(ctx, "dez"))
	await Kit.settle()
	hud.set_locked(func(_kind: String, _arg): return true)
	for id in Kit.gizmo_ids(ctx):
		check(_button(ctx, id).modulate.a > 0.5, "%s is not a ghost" % id)
	for b in hud.speed_buttons:
		check(b.modulate.a > 0.9, "nor a speed button")
	hud.set_locked(Callable())
	Kit.free_all(ctx)
