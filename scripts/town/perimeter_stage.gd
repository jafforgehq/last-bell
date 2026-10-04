## Staging of the base's perimeter for a screenshot (One House, PV): `--town --stage=fourth --slots=<what>` puts things up at once instead of waiting for builders. Give it after
## `--stage=` (the base must be claimed, and four people unlock every slot) and before `--advance`/`--hour` if those matter. `what`:
##   built     every slot that is open is ordered, paid for and finished at once (the wooden fence on the front and the sides, the reinforced one at the back, the gate, the towers, the
##             floodlights, the plank kit on the front door), every section whole
##   damaged   as built, then the sections are worn down: 100%, 80%, 50%, 20% in turn and one fallen (a breach), the gate and a door among them
##   sites     a few slots ordered and part built (a fence, the gate, a tower), the rest open: the ghosts and rings of a base going up
##   stress    as built, and forty made-up sections of four tiles drawn round the base by the view as well (all four states, both kits, gates): not in the rules, only to count draw calls
##   open      opens the gate (after built)
##   mend      1.75 seconds in, every section is mended to full (after damaged): the view flashes the repairs
##   claw      six of the dead come up to the fence and claw at it (after built)
##   all       a mix: the back and the sides built, the front part built and worn, the gate ordered half way, a tower ordered, a section down
## Not used by the game or the tests: a debugging aid in the same spirit as `--stage=`. It reaches into `sim.build` (`_finish`) to finish an order without the builders.
extends RefCounted


## Applies `what` (one word, or several with commas: "built,open") to the sim's base. False when there is no base (not a town run, or not claimed yet).
static func apply(sim, what: String, main = null) -> bool:
	var per = sim.get("perimeter") if sim != null else null
	if per == null or per.layout.is_empty():
		print("--slots=%s: no base yet (give --town --stage=claimed or fourth first)" % what)
		return false
	sim.stock["scrap"] = 9999.0
	var ok := true
	for word in what.split(",", false):
		match word:
			"built":
				_build_all(sim, per, "", "")
			"damaged":
				_build_all(sim, per, "", "")
				_wear(sim, per, [1.0, 0.8, 0.5, 0.2], true)
			"stress":
				_build_all(sim, per, "", "")
				var view = main.town.part("perimeter_view") if main != null and main.get("town") != null else null
				if view == null:
					ok = false
				else:
					view.stress = 40
			"claw":
				_dead_at_the_fence(sim, per)
			"mend":
				if main != null:
					main.get_tree().create_timer(1.75).timeout.connect(func(): _mend_all(sim, per))
			"open":
				per.toggle_gate()    # (the gate must be built: `built` first)
			"sites":
				_sites(sim, per, [["slot_front_2", 0.5], ["slot_gate", 0.3], ["slot_tower_1", 0.7], ["slot_front_3", 0.0]])
			"all":
				_build_all(sim, per, "back,side", "")
				_build_all(sim, per, "front", "")
				_wear(sim, per, [1.0, 0.8, 0.5, 0.2], false)
				_sites(sim, per, [["slot_light_1", 0.4], ["slot_light_2", 0.0]])
			_:
				print("--slots=%s: built, damaged, sites, stress, open or all" % word)
				ok = false
	sim.events.clear()
	return ok


## A few of the dead come up to the fence on the outer side of the front and the west side and claw at it (the view shakes the section and puffs dust: `--slots=built,claw`).
static func _dead_at_the_fence(sim, per) -> void:
	var lot: Rect2i = per.layout.plot
	var front_south: bool = String(per.layout.front) == "S"
	for i in 6:
		var at := Vector2(float(lot.position.x) + 2.5 + float(i) * 1.8, float(lot.end.y) + 3.0) if i < 4 else Vector2(float(lot.position.x) - 3.0, float(lot.position.y) + 4.0 + float(i - 4) * 3.0)
		if not front_south:
			at.y = float(lot.position.y) - 3.0 if i < 4 else at.y
		sim.spawn(at.x, at.y, "approach")


## Every section back to full hit points (what the crew's mending comes to): the view shows the repair.
static func _mend_all(sim, per) -> void:
	for s in per.sections():
		for g in sim.segments:
			if int(g.id) == int(s.id):
				g.hp = float(g.max_hp)
				sim._segment_state(g)


## Orders and finishes every open slot whose id contains one of the words in `only` (a comma list; "" is all).
static func _build_all(sim, per, only: String, _unused: String) -> void:
	var words := only.split(",", false)
	for sl in per.slots():
		if String(sl.state) != "open":
			continue
		if not words.is_empty():
			var hit := false
			for w in words:
				if String(sl.id).contains(w):
					hit = true
			if not hit:
				continue
		var kit := _kit_for(sl)
		if kit != "" and per.order(String(sl.id), kit):
			_finish(sim, String(sl.plot))


static func _kit_for(sl: Dictionary) -> String:
	match String(sl.kind):
		"fence":
			return "fence_strong" if String(sl.id).contains("back") or String(sl.id).contains("eside") else "fence"
		"gate":
			return "gate"
		"tower":
			return "tower"
		"floodlight":
			return "floodlight"
		"door":
			return "door_plank" if String(sl.id).contains("front") else ""
	return ""


## Pays the last of the work and lets the colony finish the building as if the builders had.
static func _finish(sim, plot_id: String) -> void:
	var pl: Dictionary = sim.build.plot(plot_id)
	if pl.is_empty() or pl.site.is_empty():
		return
	pl.site.progress = float(pl.site.work)
	sim.build._finish(pl)


## Orders [slot id, share of the work done] and leaves them as sites.
static func _sites(sim, per, list: Array) -> void:
	for e in list:
		var sl := _slot(per, String(e[0]))
		if sl.is_empty() or String(sl.state) != "open":
			continue
		var kit := _kit_for(sl)
		if kit == "" or not per.order(String(sl.id), kit):
			continue
		var pl: Dictionary = sim.build.plot(String(sl.plot))
		pl.site.progress = float(pl.site.work) * float(e[1]) * 0.999


static func _slot(per, id: String) -> Dictionary:
	for sl in per.slots():
		if String(sl.id) == id:
			return sl
	return {}


## Wears the sections down: each takes the next share of its hit points in `shares`; with `breach` one fence section is brought down.
static func _wear(sim, per, shares: Array, breach: bool) -> void:
	var i := 0
	var breached := not breach
	for s in per.sections():
		var seg = null
		for g in sim.segments:
			if int(g.id) == int(s.id):
				seg = g
		if seg == null:
			continue
		if not breached and String(s.kind) == "fence" and i == 3:
			seg.hp = 0.0
			breached = true
		else:
			seg.hp = float(seg.max_hp) * float(shares[i % shares.size()])
		sim._segment_state(seg)
		i += 1
