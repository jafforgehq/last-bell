extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")

const ICONS := ["hungry", "thirsty", "starving", "wound", "fever", "down", "resting", "away", "nonsense"]
const STAGES := ["", "feverish", "delirious"]


## Random states for the people, the modules and the selection, over and over:
## the HUD must never log an error, and what it shows must follow the state.
func test_random_states_never_break_the_hud() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var ctx := Kit.build(1000, 720)
	var sim = ctx.sim
	var hud = ctx.hud
	sim.scavenge.list = Kit.sample_sites()
	for round in 150:
		for p in sim.people:
			p.dead = rng.randf() < 0.1
			p.turned = p.dead and rng.randf() < 0.4
			p.downed = rng.randf() < 0.15
			p.drafted = rng.randf() < 0.2
			p.order = Vector3(p.x, p.y, 0) if p.drafted and rng.randf() < 0.8 else null
			p.stabilised = rng.randf() < 0.3
			p.resting_bed = Vector2(47.0, 56.9) if rng.randf() < 0.2 else null
			p.away = ({"kind": "exile"} if rng.randf() < 0.5 else {"kind": "party", "site": "pharmacy"}) if rng.randf() < 0.15 else null
			p.hunger_h = rng.randf() * 50.0
			p.thirst_h = rng.randf() * 40.0
			p.hp = rng.randf() * 110.0 - 5.0
			p.wounds = rng.randi() % 4
			p.bleeding = float(p.wounds) * 2.0 * float(rng.randi() % 2)
			p.activity = ["", "Sorting medicine", "Resting in the infirmary"][rng.randi() % 3]
			p.target = sim.zombies[0] if rng.randf() < 0.2 else null
			p.reloading = rng.randf() if rng.randf() < 0.1 else 0.0
			var marks: Array = []
			for i in rng.randi() % 6:
				marks.append({"icon": ICONS[rng.randi() % ICONS.size()], "color": Color(rng.randf(), rng.randf(), rng.randf()), "tip": "tip %d" % i})
			sim.medical.marks[p.id] = marks
			sim.medical.treat[p.id] = rng.randf() < 0.3
			sim.medical.sendout[p.id] = rng.randf() < 0.3
			sim.medical.stage[p.id] = STAGES[rng.randi() % 3]
		# the night tools: the forecast, who has auto-repair, whether the alarm can be set, the view
		sim.tactics.told = Kit.forecast({"total": rng.randi() % 200, "brutes": rng.randi() % 3, "runners": rng.randf() < 0.5, "big": rng.randf() < 0.1, "heading": ["north", "south east", "north and west"][rng.randi() % 3]}) if rng.randf() < 0.6 else {"given": false}
		for p in sim.people:
			sim.tactics.autos[p.id] = rng.randf() < 0.5
		sim.tactics.why = ["", "an alarm is already ringing", "it takes 3 scrap"][rng.randi() % 3]
		sim.tactics.ringing = rng.randi() % 16 if rng.randf() < 0.3 else -1
		sim.tactics.left_min = rng.randf() * 180.0
		sim.phase = ["day", "dusk", "night", "dawn"][rng.randi() % 4]
		hud.set_fields(rng.randf() < 0.5)
		sim.scavenge.can = rng.randf() < 0.5
		sim.scavenge.reason = "because %d" % round
		sim.supplies.days = {"food": rng.randf() * 120.0, "water": rng.randf() * 120.0}
		sim.weather = "rain" if rng.randf() < 0.3 else "clear"
		for k in sim.stock:
			sim.stock[k] = rng.randf() * 100.0
		match rng.randi() % 4:
			0:
				hud.select({"kind": "person", "ref": sim.people[rng.randi() % 6]})
			1:
				hud.select({"kind": "zombie", "ref": sim.zombies[rng.randi() % sim.zombies.size()]})
			2:
				hud.select({"kind": "segment", "ref": sim.segments[rng.randi() % sim.segments.size()]})
			3:
				hud.select(null)
		if rng.randf() < 0.3:
			Kit.resize(ctx, 640 + rng.randi() % 700, 500 + rng.randi() % 400)
		# the toast, the controls help and the alerts take part too
		if rng.randf() < 0.2:
			hud.toast("Toast %d" % round, ["info", "warn", "danger", "no-such-level"][rng.randi() % 4])
		if rng.randf() < 0.1:
			hud.help.visible = not hud.help.visible
		if rng.randf() < 0.3:
			sim.alert("fz%d" % (rng.randi() % 8), ["danger", "warn", "info"][rng.randi() % 3], "Alert %d" % round, "line %d" % round, null, 60.0)
		Kit.update(ctx, rng.randi() % 4)
		_check_what_is_shown(ctx, round)
		if round % 10 == 0:
			await Kit.settle()
		if rng.randf() < 0.1:
			hud.open_scavenge(hud.selection)
			if hud.scavenge_dialog != null:
				var d = hud.scavenge_dialog
				if not d.site_cards.is_empty():
					d.choose_site(d.site_cards.keys()[rng.randi() % d.site_cards.size()])
				if not d.candidates.is_empty():
					d.toggle_second(d.candidates.values()[0].person)
				d.cancel()
	check(true, "it got through")
	Kit.free_all(ctx)


## What the HUD shows follows the state, whatever the state is.
func _check_what_is_shown(ctx: Dictionary, round: int) -> void:
	var hud = ctx.hud
	for c in hud.cards:
		var p = c.p
		var word: String = hud._card_word(p)
		if c.veil.visible != (word != "") or c.word.text != word:
			failures.append("round %d: %s's card says '%s' with the veil %s" % [round, p.id, c.word.text, c.veil.visible])
		var n: int = c.marks.get_child_count()
		if n > hud.mark_max or c.marks_box.visible != (n > 0):
			failures.append("round %d: %s has %d marks, box visible %s" % [round, p.id, n, c.marks_box.visible])
		if p.dead and n > 0:
			failures.append("round %d: the dead %s has marks" % [round, p.id])
		if (p.dead or p.away != null) and (c.badge.visible or c.fight.visible):
			failures.append("round %d: %s is gone but has a badge" % [round, p.id])
	# the line under the clock follows the forecast, until dawn
	var told: Dictionary = ctx.sim.tactics.told
	var want_line: bool = bool(told.get("given", false)) and ctx.sim.phase != "dawn"
	if hud.forecast_label.visible != want_line or (want_line and not hud.forecast_label.text.begins_with("T") and not hud.forecast_label.text.begins_with("The last night")):
		failures.append("round %d: the forecast line is '%s' (visible %s), the forecast %s in the %s" % [round, hud.forecast_label.text, hud.forecast_label.visible, told.get("given"), ctx.sim.phase])
	# the legend is up with the view, in a window tall enough
	if hud.fields_legend.visible != (hud.fields_on and hud.size.y >= hud.LEGEND_MIN_H):
		failures.append("round %d: the legend is %s with the view %s in a window %d tall" % [round, hud.fields_legend.visible, hud.fields_on, int(hud.size.y)])
	var sel = hud.selection
	if sel != null and sel.kind == "segment":
		var ids_w := Kit.gizmo_ids(ctx)
		if ids_w != ["repair", "focus", "lure"]:
			failures.append("round %d: a wall section has the buttons %s" % [round, str(ids_w)])
		else:
			var lure: Button = Kit.gizmo(ctx, "lure")
			var why: String = ctx.sim.tactics.why
			if (lure.modulate.a < 0.9) != (why != "") or lure.tooltip_text.contains("Not now: %s." % why) != (why != ""):
				failures.append("round %d: the Lure button is '%s' with the rules saying '%s'" % [round, lure.tooltip_text, why])
	if sel != null and sel.kind == "person":
		var p = sel.ref
		var ids := Kit.gizmo_ids(ctx)
		if p.away == null and not p.dead:
			var auto: bool = ctx.sim.tactics.auto_repair(p)
			if not ids.has("auto") or Kit.gizmo(ctx, "auto").get_meta("on") != auto:
				failures.append("round %d: %s's Auto button %s does not follow auto-repair %s" % [round, p.id, str(ids), auto])
			if hud.inspect_refs.auto_tag.visible != auto:
				failures.append("round %d: %s's tag is %s with auto-repair %s" % [round, p.id, hud.inspect_refs.auto_tag.visible, auto])
		elif p.away == null and p.dead and hud.inspect_refs.auto_tag.visible:
			failures.append("round %d: a tag for the dead %s" % [round, p.id])
		if p.away != null and not ids.is_empty():
			failures.append("round %d: buttons for someone who is away: %s" % [round, str(ids)])
		elif p.away == null and p.dead and ids != ["focus"]:
			failures.append("round %d: buttons for someone dead: %s" % [round, str(ids)])
		elif p.away == null and not p.dead:
			if ids.has("treat") != ctx.sim.medical.can_treat(p) or ids.has("sendout") != ctx.sim.medical.can_send_out(p):
				failures.append("round %d: the buttons %s do not follow the modules" % [round, str(ids)])
			if ids.has("scavenge") != (ctx.sim.scavenge.can_send() and hud.is_free_to_go(p)):
				failures.append("round %d: Scavenge is %s but should not be" % [round, ids.has("scavenge")])
		if ids.size() > 0 and hud.gizmo_count != ids.size():
			failures.append("round %d: gizmo_count %d but %d buttons" % [round, hud.gizmo_count, ids.size()])
