extends "res://tests/case.gd"
## The workbench in the HUD (rounds 3 and 5): the Workbench job button (key M) for a person, lit while they have the job,
## its tooltip (what it does, what it is set to, what the person at it would make, the key, why not), the "Making
## ammo" tag in the person panel and the ammo mark on the card while the workshop says someone is at it, the help
## table's M and the alert's icon. The jobs are the jobs module's (tests/test_jobs.gd; here it is the real one); the
## workshop's rules are in tests/test_workshop.gd and the Jobs screen in tests/test_jobs_screen.gd. Here the workshop
## is Kit.FakeWorkshop, a table-driven stand-in with the real rates, and in one test the real module.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Workshop := preload("res://scripts/sim/workshop.gd")


func _lines(b: Button) -> PackedStringArray:
	return b.tooltip_text.split("\n")


## A person selected and the HUD updated.
func _person(ctx: Dictionary, id: String):
	var p = Kit.person(ctx, id)
	Kit.select(ctx, p)
	Kit.update(ctx)
	return p


func test_a_person_gets_a_workbench_button_with_its_name_key_and_icon() -> void:
	var ctx := Kit.build()
	_person(ctx, "ana")
	var b: Button = Kit.gizmo(ctx, "job_bench")
	check(b != null, "the button is there")
	check(Kit.texts(b).has("WORKBENCH"), "named: %s" % str(Kit.texts(b)))
	check(Kit.texts(b).has("M"), "with its key")
	eq(b.get_meta("key"), "M", "the key is M")
	var icons: Array = b.find_children("*", "TextureRect", true, false)
	check(not icons.is_empty() and icons[0].texture == ctx.hud.icons["ammo"], "wearing the ammo store's icon")
	eq(Hud.GIZMO_ICON.get("job_bench"), "ammo", "by the icon table")
	Kit.free_all(ctx)


func test_it_comes_after_the_wall_crew_and_before_the_modules_buttons() -> void:
	var ctx := Kit.build()
	var p = _person(ctx, "ana")
	ctx.sim.medical.treat[p.id] = true
	ctx.sim.medical.sendout[p.id] = true
	ctx.sim.scavenge.can = true
	Kit.update(ctx)
	var ids := Kit.gizmo_ids(ctx)
	eq(ids.slice(0, 6), ["draft", "post", "repair", "focus", "job_builders", "job_bench"], "the always-there buttons keep their places")
	eq(ids.slice(6), ["treat", "sendout", "scavenge"], "the ones that come and go are after them")
	Kit.free_all(ctx)


func test_the_tooltip_says_what_it_does_what_it_is_set_to_what_it_makes_and_its_key() -> void:
	var ctx := Kit.build()
	var p = _person(ctx, "ana")
	var lines := _lines(Kit.gizmo(ctx, "job_bench"))
	eq(lines.size(), 4, "four lines when nothing is against it: '%s'" % Kit.gizmo(ctx, "job_bench").tooltip_text)
	eq(lines[0], "Workbench: makes ammo from scrap by day while the stock is under the target", "what it does, and until when")
	eq(lines[1], "The target is %d (set on the Jobs screen)" % int(ctx.sim.jobs.setting("bench", "ammo_target")), "the target the Jobs screen sets")
	var per: float = ctx.sim.workshop.AMMO_PER_SCRAP
	var hourly := int(roundf(ctx.sim.workshop.scrap_per_hour(p) * ctx.sim.perf(p) * per))
	eq(lines[2], "1 scrap makes %d ammo. Ana makes about %d ammo an hour." % [int(per), hourly], "the rate, from the workshop's own numbers")
	eq(lines[3], "Key: M", "the key")
	ctx.sim.jobs.set_setting("bench", "ammo_target", 450)
	Kit.update(ctx)
	eq(_lines(Kit.gizmo(ctx, "job_bench"))[1], "The target is 450 (set on the Jobs screen)", "the words follow the setting")
	Kit.free_all(ctx)


func test_the_rate_follows_who_is_selected_and_how_well_they_are() -> void:
	var ctx := Kit.build()
	# (Dez is on the bench to begin with, and the button then tells him how to leave: he is taken off it first)
	var dez = _person(ctx, "dez")
	ctx.sim.jobs.unassign(dez)
	Kit.update(ctx)
	var fast := _lines(Kit.gizmo(ctx, "job_bench"))[2]
	_person(ctx, "hector")
	var slow := _lines(Kit.gizmo(ctx, "job_bench"))[2]
	var per := int(ctx.sim.workshop.AMMO_PER_SCRAP)
	check(fast.begins_with("1 scrap makes %d ammo. Dez makes about " % per) and slow.begins_with("1 scrap makes %d ammo. Hector makes about " % per), "named: '%s' / '%s'" % [fast, slow])
	check(fast != slow.replace("Hector", "Dez"), "Dez the builder makes more than Hector: '%s' / '%s'" % [fast, slow])
	# hunger slows them: the words follow the rules' own factor
	_person(ctx, "dez")
	var before := _lines(Kit.gizmo(ctx, "job_bench"))[2]
	dez.hunger_h = 40.0
	Kit.update(ctx)
	var after := _lines(Kit.gizmo(ctx, "job_bench"))[2]
	check(after != before, "a starving Dez makes less: '%s' then '%s'" % [before, after])
	Kit.free_all(ctx)


func test_it_says_why_not_and_is_ghosted_but_still_pressable() -> void:
	var ctx := Kit.build()
	ctx.sim.jobs.assign(Kit.person(ctx, "hector"), "bench")
	eq(ctx.sim.jobs.seats_left("bench"), 0, "Dez and Hector fill the two seats")
	_person(ctx, "ruth")
	var b: Button = Kit.gizmo(ctx, "job_bench")
	check(b.modulate.a < 0.9, "ghosted")
	var lines := _lines(b)
	eq(lines.size(), 5, "a fifth line when there is no seat: '%s'" % b.tooltip_text)
	eq(lines[3], "Key: M", "the key stays where it was")
	eq(lines[4], "Not now: no free seat at the Workbench.", "and the reason is the jobs module's own")
	check(not b.disabled, "but not disabled: the order goes through and the game says why")
	ctx.sim.jobs.unassign(Kit.person(ctx, "hector"))
	Kit.update(ctx)
	b = Kit.gizmo(ctx, "job_bench")
	check(b.modulate.a > 0.99 and _lines(b).size() == 4, "and bright again when a seat comes free")
	Kit.free_all(ctx)


func test_it_lights_while_they_have_the_job_and_they_can_always_be_taken_off_it() -> void:
	var ctx := Kit.build()
	_person(ctx, "ana")
	var b: Button = Kit.gizmo(ctx, "job_bench")
	eq(b.get_meta("on"), false, "dark for the nurse")
	var off_box: StyleBox = b.get_theme_stylebox("normal")
	if off_box is StyleBoxFlat:
		eq(off_box.bg_color, Hud.PANEL, "like the others")
	var dez = _person(ctx, "dez")
	b = Kit.gizmo(ctx, "job_bench")
	eq(b.get_meta("on"), true, "lit for Dez, who is on the bench")
	var on_box: StyleBox = b.get_theme_stylebox("normal")
	if on_box is StyleBoxFlat:
		eq(on_box.bg_color, Hud.ACCENT, "gold, like Builders when it is on")
	# the bench is full and he is on it: pressing it takes him off, so the button says nothing against it
	ctx.sim.jobs.assign(Kit.person(ctx, "hector"), "bench")
	Kit.update(ctx)
	b = Kit.gizmo(ctx, "job_bench")
	check(b.modulate.a > 0.99, "not ghosted: pressing it takes him off")
	var lines := _lines(b)
	eq(lines[0], "Workbench: Dez is on it. Press again to take them off", "the first line says how")
	check(not b.tooltip_text.contains("Not now"), "and has no objection: '%s'" % b.tooltip_text)
	ctx.sim.jobs.unassign(dez)
	Kit.update(ctx)
	eq(Kit.gizmo(ctx, "job_bench").get_meta("on"), false, "dark again when he is taken off")
	Kit.free_all(ctx)


func test_pressing_it_reaches_main_and_a_real_click_does_too() -> void:
	var ctx := Kit.build()
	_person(ctx, "hector")
	Kit.gizmo(ctx, "job_bench").pressed.emit()
	eq(ctx.pressed, ["job_bench"], "a press reaches main.gd by its id")
	await Kit.settle()
	await Kit.settle()
	Kit.click_on(Kit.gizmo(ctx, "job_bench"))
	eq(ctx.pressed, ["job_bench", "job_bench"], "and a mouse click does")
	Kit.free_all(ctx)


func test_the_game_gives_and_takes_the_job_the_way_the_key_does() -> void:
	var ctx := Kit.build()
	var ana = _person(ctx, "ana")
	check(ctx.sim.handle_gizmo("job_bench", ctx.hud.selection), "the module takes the order")
	eq(ctx.sim.jobs.job_of(ana), "bench", "she is on the bench")
	Kit.update(ctx)
	eq(Kit.gizmo(ctx, "job_bench").get_meta("on"), true, "the button is lit")
	eq(Kit.texts(ctx.hud.inspect_refs.job_tag), ["Job: Workbench"], "and the tag says so")
	check(ctx.sim.handle_gizmo("job_bench", ctx.hud.selection), "again")
	Kit.update(ctx)
	eq(ctx.sim.jobs.job_of(ana), "", "she is off it")
	eq(Kit.gizmo(ctx, "job_bench").get_meta("on"), false, "and the button is dark")
	Kit.free_all(ctx)


func test_only_a_person_has_it_and_only_one_who_is_here() -> void:
	var ctx := Kit.build()
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "job_bench") == null and Kit.gizmo(ctx, "job_builders") == null, "not for a wall piece")
	ctx.hud.select({"kind": "zombie", "ref": ctx.sim.zombies[0]})
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "job_bench") == null, "nor for a walker")
	var walt = _person(ctx, "walt")
	walt.dead = true
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "job_bench") == null, "nor for the dead")
	walt.dead = false
	walt.away = {"kind": "party", "site": "houses"}
	Kit.update(ctx)
	check(Kit.gizmo(ctx, "job_bench") == null, "nor for someone away")
	Kit.free_all(ctx)


func test_the_why_for_a_wall_nobody_the_gone_and_the_full_is_plain() -> void:
	var ctx := Kit.build()
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
	Kit.update(ctx)
	eq(ctx.hud.why_not("job_bench"), "pick one of the crew first", "a wall piece has no job")
	_person(ctx, "ana")
	eq(ctx.hud.why_not("job_bench"), "", "a person who can: nothing against it")
	ctx.sim.jobs.assign(Kit.person(ctx, "hector"), "bench")
	eq(ctx.hud.why_not("job_bench"), "no free seat at the Workbench", "and when there is no seat, the jobs module says why")
	var dez = _person(ctx, "dez")
	eq(ctx.hud.why_not("job_bench"), "", "someone who is on it can always leave")
	dez.dead = true
	eq(ctx.hud.why_not("job_bench"), "Dez is gone", "the gone are given nothing")
	dez.dead = false
	dez.away = {"kind": "party", "site": "houses"}
	eq(ctx.hud.why_not("job_bench"), "Dez is away", "nor the away")
	Kit.free_all(ctx)


func test_a_game_with_no_jobs_has_no_job_buttons_and_nothing_breaks() -> void:
	# an older stand-in for the sim, with the other modules but no `jobs` (a plain Dictionary
	# answers `sim.get("jobs")` with null, as an object with no such property does)
	var ctx := Kit.build()
	var ana = _person(ctx, "ana")
	var real_sim = ctx.hud.sim_ref
	ctx.hud.sim_ref = {"medical": ctx.sim.medical, "scavenge": ctx.sim.scavenge, "tactics": ctx.sim.tactics, "stock": ctx.sim.stock, "segments": ctx.sim.segments}
	check(ctx.hud._jobs() == null, "the HUD finds no module")
	ctx.hud._build_gizmos()
	check(Kit.gizmo(ctx, "job_bench") == null and Kit.gizmo(ctx, "job_builders") == null, "no buttons without jobs")
	eq(Kit.gizmo_ids(ctx), ["draft", "post", "repair", "focus"], "the usual buttons only")
	eq(ctx.hud.why_not("job_bench"), "", "nothing to say about it")
	eq(ctx.hud._job_of(ana), "", "nobody has a job that is not there")
	check(ctx.hud._gizmo_sig() != "", "the buttons' signature still works")
	ctx.hud._refresh_job_tag(ana)
	check(not ctx.hud.inspect_refs.job_tag.visible, "and there is no job tag")
	ctx.hud.open_jobs()
	check(ctx.hud.jobs_screen == null, "nor a Jobs screen")
	ctx.hud.sim_ref = real_sim
	Kit.free_all(ctx)


# ------------------------------------------------------------------ the tag --

func test_the_person_panel_tags_making_ammo_while_the_workshop_mark_is_on_them() -> void:
	var ctx := Kit.build()
	var dez = _person(ctx, "dez")
	var tag: PanelContainer = ctx.hud.inspect_refs.craft_tag
	check(not tag.visible, "no tag while they are not at it")
	ctx.sim.workshop.at_bench[dez.id] = true
	Kit.update(ctx)
	tag = ctx.hud.inspect_refs.craft_tag
	check(tag.visible, "the tag shows with the mark")
	check(Kit.texts(tag).has("Making ammo"), "and says so: %s" % str(Kit.texts(tag)))
	eq(tag.tooltip_text, "Making ammo at the worktable", "with the mark's own tip")
	dez.dead = true
	Kit.update(ctx)
	check(not ctx.hud.inspect_refs.craft_tag.visible, "not for someone who is gone")
	Kit.free_all(ctx)


func test_the_card_shows_the_ammo_mark_too() -> void:
	var ctx := Kit.build()
	var dez = Kit.person(ctx, "dez")
	ctx.sim.workshop.at_bench[dez.id] = true
	Kit.update(ctx)
	var c := Kit.card(ctx, dez)
	var found := false
	for m in c.marks.get_children():
		if m.texture == ctx.hud.icons["ammo"]:
			found = true
			eq(m.tooltip_text, "Making ammo at the worktable", "with the tip")
	check(found, "an ammo icon among the marks on the card")
	Kit.free_all(ctx)


func test_both_tags_fit_beside_every_name() -> void:
	var ctx := Kit.build()
	for p in ctx.sim.people:
		ctx.sim.workshop.at_bench[p.id] = true
	for p in ctx.sim.people:
		Kit.select(ctx, p)
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var panel: Rect2 = Kit.rect(ctx.hud.inspect)
		var job: Rect2 = Kit.rect(ctx.hud.inspect_refs.job_tag)
		var craft: Rect2 = Kit.rect(ctx.hud.inspect_refs.craft_tag)
		check(job.size != Vector2.ZERO and craft.size != Vector2.ZERO, "%s: both tags show" % p.first)
		check(panel.encloses(job) and panel.encloses(craft), "%s: both are inside the panel (%s %s in %s)" % [p.first, str(job), str(craft), str(panel)])
		eq(Kit.overlaps({"job": job, "craft": craft}), [], "%s: and do not overlap" % p.first)
		for l in ctx.hud.inspect.find_children("*", "Label", true, false):
			if l.text == p.name or l.text.begins_with(p.def.role):
				var r := Kit.rect(l)
				check(r.end.x <= minf(job.position.x, craft.position.x) + 0.5, "%s: the tags clear '%s' (%s)" % [p.first, l.text, str(r)])
		eq(panel.size.x, float(Hud.INSPECT_W), "%s: and do not widen the panel" % p.first)
	Kit.free_all(ctx)


# ------------------------------------------------------------ help and alerts --

func test_the_help_table_lists_m_j_b_and_n_by_the_names_of_the_jobs_and_the_page() -> void:
	var ctx := Kit.build()
	var found := {}
	for group in Hud.HELP:
		for entry in group[2]:
			if ["M", "B", "J", "N"].has(entry[0]):
				found[entry[0]] = entry[1]
	eq(found, {"M": "Workbench", "B": "Builders", "J": "Jobs", "N": "Build"}, "what M, B, J and N do")
	for t in ["Workbench", "Builders", "Jobs", "Build"]:
		check(Kit.texts(ctx.hud.help).has(t), "'%s' is on the panel" % t)
	Kit.free_all(ctx)


func test_the_idle_worktable_alert_wears_the_ammo_icon() -> void:
	var ctx := Kit.build()
	eq(ctx.hud._alert_icon_name({"id": "workshop-idle", "level": "info"}), "ammo", "by its id")
	ctx.sim.alert("workshop-idle", "info", "The worktable is idle", "Only 3 scrap is left; it is kept for the walls", null, 60.0)
	Kit.update(ctx)
	var it: Dictionary = ctx.hud.alert_items.get("workshop-idle", {})
	check(not it.is_empty() and it.panel != null, "it is in the feed")
	if not it.is_empty() and it.panel != null:
		eq((it.icon as TextureRect).texture, ctx.hud.icons["ammo"], "with the ammo icon")
	Kit.free_all(ctx)


# ----------------------------------------------------------- the real module --

func test_with_the_real_workshop_the_button_and_the_tag_follow_the_jobs() -> void:
	var ctx := Kit.build()
	var real = Workshop.new()
	real.setup(ctx.sim)
	ctx.sim.workshop = real
	var ana = _person(ctx, "ana")
	var b: Button = Kit.gizmo(ctx, "job_bench")
	check(b != null and b.get_meta("on") == false, "dark for the nurse with scrap in the stock")
	eq(_lines(b).size(), 4, "and nothing against it: '%s'" % b.tooltip_text)
	check(_lines(b)[2].begins_with("1 scrap makes %d ammo." % int(real.AMMO_PER_SCRAP)), "the real rate: '%s'" % _lines(b)[2])
	# the order, as main sends it
	check(ctx.sim.handle_gizmo("job_bench", ctx.hud.selection), "the module takes the order")
	Kit.update(ctx)
	eq(ctx.sim.jobs.job_of(ana), "bench", "she is on the bench")
	b = Kit.gizmo(ctx, "job_bench")
	eq(b.get_meta("on"), true, "the button is lit")
	eq(Kit.texts(ctx.hud.inspect_refs.job_tag), ["Job: Workbench"], "the tag says so")
	# the rates are the workshop's: a builder makes more
	check(real.scrap_per_hour(Kit.person(ctx, "dez")) > real.scrap_per_hour(Kit.person(ctx, "hector")), "(Dez is the better builder)")
	Kit.free_all(ctx)
