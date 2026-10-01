extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")


func _open(ctx: Dictionary, id: String):
	var p = Kit.person(ctx, id)
	Kit.select(ctx, p)
	Kit.update(ctx)
	return p


func test_a_person_gets_the_four_usual_buttons_and_the_two_jobs_the_keys_give() -> void:
	var ctx := Kit.build()
	_open(ctx, "ruth")
	eq(Kit.gizmo_ids(ctx), ["draft", "post", "repair", "focus", "job_builders", "job_bench"], "the usual four in their old order, then the wall crew (B) and the workbench (M)")
	Kit.free_all(ctx)


func test_treat_shows_only_while_the_medical_module_offers_it() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "marcus")
	check(Kit.gizmo(ctx, "treat") == null, "nothing to treat")
	ctx.sim.medical.treat[p.id] = true
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "treat") != null, "treat appears")
	ctx.sim.medical.treat[p.id] = false
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "treat") == null, "and goes")
	Kit.free_all(ctx)


func test_send_out_shows_only_for_someone_who_can_be_sent() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "walt")
	check(Kit.gizmo(ctx, "sendout") == null, "not infected")
	ctx.sim.medical.sendout[p.id] = true
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "sendout") != null, "send out appears")
	Kit.free_all(ctx)


func test_scavenge_shows_when_a_party_can_go_and_this_person_is_free() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "dez")
	check(Kit.gizmo(ctx, "scavenge") == null, "not in the window for going out")
	ctx.sim.scavenge.can = true
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "scavenge") != null, "scavenge appears")
	p.downed = true
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "scavenge") == null, "not for someone who is down")
	p.downed = false
	p.drafted = true
	p.order = Vector3(p.x, p.y, 0)
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "scavenge") == null, "not for someone held by an order")
	p.drafted = false
	p.order = null
	ctx.sim.medical.stage[p.id] = "delirious"
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "scavenge") == null, "not for someone delirious")
	ctx.sim.medical.stage[p.id] = "feverish"
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "scavenge") != null, "a fever alone does not stop them")
	ctx.sim.scavenge.can = false
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "scavenge") == null, "and it goes when the window closes")
	Kit.free_all(ctx)


func test_the_modules_buttons_follow_the_usual_ones() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "ana")
	ctx.sim.medical.treat[p.id] = true
	ctx.sim.medical.sendout[p.id] = true
	ctx.sim.scavenge.can = true
	Kit.update(ctx)
	eq(Kit.gizmo_ids(ctx), ["draft", "post", "repair", "focus", "job_builders", "job_bench", "treat", "sendout", "scavenge"], "all nine")
	Kit.free_all(ctx)


func test_each_button_calls_on_gizmo_with_its_id() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "ana")
	ctx.sim.medical.treat[p.id] = true
	ctx.sim.medical.sendout[p.id] = true
	ctx.sim.scavenge.can = true
	Kit.update(ctx)
	for id in Kit.gizmo_ids(ctx):
		Kit.gizmo(ctx, id).pressed.emit()
	eq(ctx.pressed, ["draft", "post", "repair", "focus", "job_builders", "job_bench", "treat", "sendout", "scavenge"], "every press reaches main.gd")
	Kit.free_all(ctx)


func test_the_new_buttons_show_their_keys() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "ana")
	ctx.sim.medical.treat[p.id] = true
	ctx.sim.medical.sendout[p.id] = true
	ctx.sim.scavenge.can = true
	Kit.update(ctx)
	var keys := {"treat": "T", "sendout": "X", "scavenge": "G"}
	for id in keys:
		var t := Kit.texts(Kit.gizmo(ctx, id))
		check(t.has(keys[id]), "%s shows its key %s" % [id, keys[id]])
	check(Kit.texts(Kit.gizmo(ctx, "treat")).has("TREAT"), "and its name")
	check(Kit.texts(Kit.gizmo(ctx, "sendout")).has("SEND OUT"), "send out is named")
	check(Kit.texts(Kit.gizmo(ctx, "scavenge")).has("SCAVENGE"), "scavenge is named")
	Kit.free_all(ctx)


func test_the_draft_button_still_flips_with_the_draft() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "ruth")
	check(Kit.texts(Kit.gizmo(ctx, "draft")).has("DRAFT"), "draft first")
	p.drafted = true
	Kit.update(ctx)
	check(Kit.texts(Kit.gizmo(ctx, "draft")).has("RELEASE"), "then release")
	Kit.free_all(ctx)


func test_the_dead_get_only_follow_and_the_away_get_nothing() -> void:
	var ctx := Kit.build()
	var p = _open(ctx, "hector")
	p.dead = true
	Kit.update(ctx)
	eq(Kit.gizmo_ids(ctx), ["focus"], "a body can be followed")
	p.dead = false
	p.away = {"kind": "party", "site": "houses"}
	Kit.update(ctx)
	eq(Kit.gizmo_ids(ctx), [], "someone off the map has no buttons")
	Kit.free_all(ctx)


func test_walls_and_walkers_keep_their_buttons() -> void:
	var ctx := Kit.build()
	ctx.sim.scavenge.can = true
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
	Kit.update(ctx)
	eq(Kit.gizmo_ids(ctx), ["repair", "focus", "lure"], "a wall piece: repair, focus and the alarm")
	ctx.hud.select({"kind": "zombie", "ref": ctx.sim.zombies[0]})
	Kit.update(ctx)
	eq(Kit.gizmo_ids(ctx), ["focus"], "a walker")
	ctx.hud.select(null)
	Kit.update(ctx)
	eq(Kit.gizmo_ids(ctx), [], "nothing selected")
	Kit.free_all(ctx)


func test_a_mouse_click_on_a_button_reaches_on_gizmo() -> void:
	var ctx := Kit.build()
	var p = Kit.person(ctx, "ana")
	ctx.sim.medical.treat[p.id] = true
	Kit.select(ctx, p)
	Kit.update(ctx)
	await Kit.settle()
	await Kit.settle()
	Kit.click_on(Kit.gizmo(ctx, "treat"))
	eq(ctx.pressed, ["treat"], "a real click on Treat")
	Kit.click_on(Kit.gizmo(ctx, "draft"))
	eq(ctx.pressed, ["treat", "draft"], "and on Draft")
	Kit.free_all(ctx)
