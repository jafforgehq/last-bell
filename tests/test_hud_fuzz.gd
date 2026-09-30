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
	var sel = hud.selection
	if sel != null and sel.kind == "person":
		var p = sel.ref
		var ids := Kit.gizmo_ids(ctx)
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
