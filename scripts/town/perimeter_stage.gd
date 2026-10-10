## Staging of the base's perimeter for a screenshot (One House, PV): `--town --stage=fourth --slots=<what>` puts things up at once instead of waiting for builders. Give it after
## `--stage=` (the base must be claimed, and four people unlock every slot) and before `--advance`/`--hour` if those matter. `what`:
##   built     every slot that is open is ordered, paid for and finished at once (the wooden fence on the front and the sides, the reinforced one at the back, the gate, the towers, the
##             floodlights, the plank kit on the front door), every section whole
##   damaged   as built, then the sections are worn down: 100%, 80%, 50%, 20% in turn and one fallen (a breach), the gate and a door among them
##   sites     a few projects ordered and part built (the front fence, the gate, a tower), the rest open: the ghosts and rings of a base going up
##   ring      the front fence, the side fences and the gate built, the back fence and a tower going up (a ring half built), the rest not ordered
##   stress    as built, and forty made-up sections of four tiles drawn round the base by the view as well (all four states, both kits, gates): not in the rules, only to count draw calls
##   open      opens the gate (after built)
##   mend      1.75 seconds in, every section is mended to full (after damaged): the view flashes the repairs
##   claw      six of the dead come up to the fence and claw at it (after built); `claw:70` that many from all round it (a night at its cap of 70)
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
	for word_in in what.split(",", false):
		var word: String = String(word_in).get_slice(":", 0)
		var arg: String = String(word_in).get_slice(":", 1) if String(word_in).contains(":") else ""
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
				_dead_at_the_fence(sim, per, int(arg) if arg.is_valid_int() else 6)
			"mend":
				if main != null:
					main.get_tree().create_timer(1.75).timeout.connect(func(): _mend_all(sim, per))
			"open":
				per.toggle_gate()    # (the gate must be built: `built` first)
			"sites":
				_project_sites(sim, per, [["front", [0.8, 0.35]], ["gate", [0.3]], ["tower", [0.7]]])
			"ring":
				for id in ["front", "sides", "gate"]:
					_project_built(sim, per, id)
				_project_sites(sim, per, [["back", [0.7, 0.3]], ["tower", [0.5]]])
			"all":
				_build_all(sim, per, "back,side", "")
				_build_all(sim, per, "front", "")
				_wear(sim, per, [1.0, 0.8, 0.5, 0.2], false)
				_project_sites(sim, per, [["lights", [0.4, 0.0]]])
			_:
				print("--slots=%s: built, damaged, sites, ring, stress, open, mend, claw or all" % word)
				ok = false
	sim.events.clear()
	return ok


## A few of the dead come up to the fence on the outer side of the front and the west side and claw at it (the view shakes the section and puffs dust: `--slots=built,claw`).
static func _dead_at_the_fence(sim, per, count: int = 6) -> void:
	var lot: Rect2i = per.layout.plot
	var front_south: bool = String(per.layout.front) == "S"
	if count != 6:
		# (DEAD1: `claw:70`, a night at its cap: that many of the dead make for the base from all round it, 3 to 12 tiles outside the lot, and take a place at the fence or muster in the street)
		var rng := RandomNumberGenerator.new()
		rng.seed = 70
		var made := 0
		var tries := 0
		var middle := Vector2(lot.get_center())
		while made < count and tries < count * 60:
			tries += 1
			var at := middle + Vector2.from_angle(rng.randf() * TAU) * (float(maxi(lot.size.x, lot.size.y)) * 0.5 + rng.randf_range(3.0, 12.0))
			if sim.world.is_solid(sim.world.solid_z, at.x, at.y):
				continue
			sim.spawn(at.x, at.y, "approach", "walker" if rng.randf() < 0.9 else "runner")
			made += 1
		return
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


## Orders each project [id, [share of the work done, for each of its sections in turn]] and leaves them as sites.
static func _project_sites(sim, per, list: Array) -> void:
	for e in list:
		var r: Dictionary = per.order_project(String(e[0]))
		if not bool(r.get("ok", false)):
			continue
		var ids: Array = per.project_slot_ids(String(e[0]))
		for i in ids.size():
			var sl := _slot(per, String(ids[i]))
			var pl: Dictionary = sim.build.plot(String(sl.plot)) if not sl.is_empty() else {}
			if pl.is_empty() or pl.site.is_empty():
				continue
			var shares: Array = e[1]
			pl.site.progress = float(pl.site.work) * float(shares[mini(i, shares.size() - 1)] if i < shares.size() else 0.0) * 0.999


## Orders a project and finishes every one of its sections at once.
static func _project_built(sim, per, id: String) -> void:
	per.order_project(id)
	for sid in per.project_slot_ids(id):
		var sl := _slot(per, String(sid))
		if not sl.is_empty():
			_finish(sim, String(sl.plot))


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
