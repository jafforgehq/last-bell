## Shared by the HUD tests (tests/test_hud_*.gd; this file has no test_ prefix
## so the runner skips it): builds a HUD inside a holder Control over a headless
## game, and fake modules so a test sets by hand what the HUD reads (the real
## modules are filled in by other builders; the HUD only needs their contract).
extends RefCounted

const Helpers := preload("res://tests/helpers.gd")
const Hud := preload("res://scripts/ui/hud.gd")


## Each fake extends the real module, so every hook the rules call still
## exists; only what the HUD reads is table-driven.
class FakeSupplies:
	extends "res://scripts/sim/supplies.gd"
	var days := {"food": 10.0, "water": 10.0}
	var marks := {}

	func days_left(kind: String) -> float:
		return float(days.get(kind, 99.0))

	func status_of(p) -> Array:
		return marks.get(p.id, [])


class FakeMedical:
	extends "res://scripts/sim/medical.gd"
	var treat := {}
	var sendout := {}
	var stage := {}
	var marks := {}

	func can_treat(p) -> bool:
		return bool(treat.get(p.id, false))

	func can_send_out(p) -> bool:
		return bool(sendout.get(p.id, false))

	func infection_stage(p) -> String:
		return String(stage.get(p.id, ""))

	func status_of(p) -> Array:
		return marks.get(p.id, [])


class FakeScavenge:
	extends "res://scripts/sim/scavenge.gd"
	var can := false
	var reason := ""
	var list: Array = []
	var sent: Array = []
	var send_ok := true
	var marks := {}

	func can_send() -> bool:
		return can

	func why_not() -> String:
		return reason

	func available_sites() -> Array:
		return list

	func send(people: Array, site_id: String) -> bool:
		var ids: Array = []
		for p in people:
			ids.append(p.id)
		sent.append({"ids": ids, "site": site_id})
		return send_ok

	func status_of(p) -> Array:
		return marks.get(p.id, [])


class FakeScenario:
	extends "res://scripts/sim/scenario.gd"
	var today := 7
	var total := 30

	func day() -> int:
		return today

	func total_days() -> int:
		return total


## The night tools' module (tactics.gd): the alarm, auto-repair, the guns' coverage and the
## lookout's forecast. What the HUD reads of it is table-driven, so a test sets by hand
## what it says; the module's own clock-driven work (updating, starting a run) is switched off.
class FakeTactics:
	extends "res://scripts/sim/tactics.gd"
	## What forecast() says: {"given": false} until a test sets it (see Kit.forecast).
	var told := {"given": false}
	## How many guns reach each wall section, by the section's id (absent: none).
	var cover := {}
	## Who has auto-repair on, by person id.
	var autos := {}
	## The section the alarm rings at (-1: none) and the minutes it has left.
	var ringing := -1
	var left_min := 0.0
	## Why the alarm cannot be set on any section ("" when it can) and where it was set.
	var why := ""
	var set_on: Array = []

	func start() -> void:
		pass

	func update(_dt: float) -> void:
		pass

	func forecast() -> Dictionary:
		return told

	func coverage_of(seg) -> int:
		return int(cover.get(seg.id, 0))

	func lure_seg():
		for s in sim.segments:
			if s.id == ringing:
				return s
		return null

	func lure_left_min() -> float:
		return left_min if ringing >= 0 else 0.0

	func why_not_lure(_seg) -> String:
		return why

	func order_lure(seg) -> bool:
		set_on.append(seg.id)
		return why == ""

	func auto_repair(p) -> bool:
		return bool(autos.get(p.id, false))

	func toggle_auto(p) -> void:
		autos[p.id] = not auto_repair(p)


## The worktable's module (workshop.gd): who is at the bench and why nobody else can be
## sent. What the HUD reads of it is table-driven, so a test sets by hand what it says; the
## module's own clock-driven work (updating, starting a run) is switched off. The rates
## (AMMO_PER_SCRAP, scrap_per_hour) are the real module's.
class FakeWorkshop:
	extends "res://scripts/sim/workshop.gd"
	## Who is at the bench, by person id.
	var at_bench := {}
	## Why nobody can be sent to the bench ("" when they can), and who was sent.
	var why := ""
	var ordered: Array = []

	func start() -> void:
		pass

	func update(_dt: float) -> void:
		pass

	func crafting(p) -> bool:
		return bool(at_bench.get(p.id, false))

	func why_not_craft(_p) -> String:
		return why

	func order_craft(p) -> bool:
		ordered.append(p.id)
		if why != "":
			return false
		at_bench[p.id] = true
		return true

	func stop(p) -> void:
		at_bench.erase(p.id)

	func status_of(p) -> Array:
		if not crafting(p):
			return []
		return [{"icon": "ammo", "color": Color("#f0c24a"), "tip": "Making ammo at the worktable"}]


## Round 4, the people. Like the others, each fake extends the real module (so every hook the rules
## call still exists) and answers what the HUD reads of it from tables a test fills in. The defaults are
## rich on purpose (two traits each, a bond or two, a mood with its reasons, a skill that has gained),
## so the panel is tested at its fullest without the real modules.

## Who has which traits, and what they say (the wording of the real ones is the rules' own).
class FakeTraits:
	extends "res://scripts/sim/traits.gd"
	const NAMES := {
		"steady": ["Steady", "Keeps a level head. The dead at the wall shake them half as much."],
		"nervous": ["Nervous", "Jumpy. The dead at the wall shake them half again as much, and their aim suffers when many are close."],
		"tinkerer": ["Tinkerer", "Good with their hands. Mends walls 30% faster and makes ammo 20% faster."],
		"triage": ["Triage", "Knows what to do first. Bandages 30% faster."],
		"sharp_eyed": ["Sharp-eyed", "Picks a target and hits it. Shots land 8% more often."],
		"steady_hands": ["Steady hands", "Reloads without fumbling, in three quarters of the time."],
		"tough": ["Tough", "Shrugs it off. A claw or a bite is a quarter less likely to leave a wound."],
		"optimist": ["Optimist", "Bounces back. Their spirits recover half again as fast."],
		"loyal": ["Loyal", "Stands by their people. Aims better beside a friend, and takes a loss harder."],
		"quick_learner": ["Quick learner", "Picks things up. Skills grow half as fast again."],
	}
	const DEFAULT := {
		"ruth": ["steady", "loyal"], "dez": ["tinkerer", "tough"], "ana": ["triage", "optimist"],
		"marcus": ["nervous", "quick_learner"], "walt": ["steady_hands", "sharp_eyed"], "hector": ["tough", "steady"],
	}
	## Person id -> the ids of their traits (what a test sets; the default is DEFAULT).
	var table := {}

	func start() -> void:
		pass

	func of(p) -> Array:
		var out: Array = []
		for id in table.get(p.id, DEFAULT.get(p.id, [])):
			var n: Array = NAMES.get(id, [String(id).capitalize(), ""])
			out.append({"id": id, "name": n[0], "blurb": n[1]})
		return out


## How they are holding up: a value, a word, the reasons, whether they are in a breakdown, and the
## marks for the cards (by default the ones the real module gives: one while Shaken or Breaking).
class FakeMorale:
	extends "res://scripts/sim/morale.gd"
	## Person id -> 0 to 100 (default 70), the word (default: from the value), the lines explain()
	## gives (default: three) and whether they are in a breakdown.
	var values := {}
	var moods := {}
	var reasons := {}
	var broke := {}
	## How well morale lets them work (default 1.0).
	var perfs := {}
	## Marks by person id; when a person has none here, the marks follow their mood.
	var marks := {}

	func start() -> void:
		pass

	func update(_dt: float) -> void:
		pass

	func value(p) -> float:
		return float(values.get(p.id, 70.0))

	func mood(p) -> String:
		if moods.has(p.id):
			return String(moods[p.id])
		var v := value(p)
		return "Inspired" if v >= 80.0 else ("Steady" if v >= 40.0 else ("Shaken" if v >= 20.0 else "Breaking"))

	func explain(p) -> Array:
		return reasons.get(p.id, [{"label": "fed and watered", "value": 5.0}, {"label": "near Marcus", "value": 5.0}, {"label": "the dead at the wall", "value": -8.0}])

	func breakdown(p) -> bool:
		return bool(broke.get(p.id, false))

	func perf(p) -> float:
		return float(perfs.get(p.id, 1.0))

	## Where it is settling: 60 and the reasons.
	func target(p) -> float:
		var t := 60.0
		for r in explain(p):
			t += float(r.value)
		return t

	func status_of(p) -> Array:
		if marks.has(p.id):
			return marks[p.id]
		match mood(p):
			"Shaken":
				return [{"icon": "mood", "color": Color("#e8953a"), "tip": "Shaken: aims and works a little worse"}]
			"Breaking":
				return [{"icon": "mood", "color": Color("#e0584a"), "tip": "Breaking: close to a breakdown"}]
		return []


## Who is close to whom: person id -> [[the other's id, kind, what the other is to them], ...] (what a test
## sets; the third is the kind when left out; the default is the crew's own: Ruth and Marcus family, Walt
## mentors Marcus, Dez and Hector, Ana and Ruth friends).
class FakeBonds:
	extends "res://scripts/sim/bonds.gd"
	const DEFAULT := {
		"ruth": [["marcus", "family"], ["ana", "friend"]], "marcus": [["ruth", "family"], ["walt", "mentor"]],
		"walt": [["marcus", "mentor", "student"]], "dez": [["hector", "friend"]], "hector": [["dez", "friend"]], "ana": [["ruth", "friend"]],
	}
	var table := {}
	## What aim_bonus gives (0 for nobody near).
	var aim := {}

	func start() -> void:
		pass

	func of(p) -> Array:
		var out: Array = []
		for pair in table.get(p.id, DEFAULT.get(p.id, [])):
			for q in sim.people:
				if q.id == pair[0]:
					out.append({"who": q, "kind": pair[1], "role": pair[2] if pair.size() > 2 else pair[1]})
		return out

	func aim_bonus(p) -> float:
		return float(aim.get(p.id, 0.0))


## What each person has gained: person id -> {skill: points} (default: Marcus a point of Shooting
## and Dez two of Building).
class FakeSkills:
	extends "res://scripts/sim/skills.gd"
	const DEFAULT := {"marcus": {"Shooting": 1}, "dez": {"Building": 2}}
	var table := {}

	func start() -> void:
		pass

	func gained(p) -> Dictionary:
		return table.get(p.id, DEFAULT.get(p.id, {}))


## What is said about the dead: person id -> the line (default: one for anyone).
class FakeBarks:
	extends "res://scripts/sim/barks.gd"
	var epitaphs := {}

	func start() -> void:
		pass

	func update(_dt: float) -> void:
		pass

	func epitaph(p) -> String:
		return String(epitaphs.get(p.id, "%s kept the wall standing." % p.first))


## A forecast as tactics.forecast() gives one, given: tonight about 55 from the north east.
## `with` overrides any of its fields.
static func forecast(with: Dictionary = {}) -> Dictionary:
	var f := {"given": true, "total": 55, "low": 47, "high": 63, "heading": "north east", "spawns": [Vector2(75.5, 0.5)], "runners": false, "brutes": 0, "big": false, "who": "Marcus"}
	f.merge(with, true)
	return f


## Three sites shaped like the ones the scavenging module returns.
## The sites of a sim whose scavenging module offers them; `with_scrapyard` adds the fourth
## place of round 3 (the owner's data has its own: this one stands in for it).
static func sample_sites(with_scrapyard: bool = false) -> Array:
	var sites := [
		{"id": "pharmacy", "name": "The pharmacy", "blurb": "Shelves stripped, but the back room was locked.", "danger": 2, "loot": {"meds": [3, 6]}, "extra": {"food": [0.4, 2]}, "image": "res://assets/ui/sites/pharmacy.png", "available": true, "note": ""},
		{"id": "hardware", "name": "The hardware store", "blurb": "Crowbars, nails, boxes of shells.", "danger": 2, "loot": {"scrap": [10, 20], "ammo": [20, 60]}, "extra": {}, "image": "res://assets/ui/sites/hardware.png", "available": false, "note": "Picked over"},
		{"id": "houses", "name": "Neighbourhood houses", "blurb": "Somebody's pantry is somebody's pantry.", "danger": 1, "loot": {"food": [8, 14], "water": [10, 20]}, "extra": {"meds": [0.3, 1]}, "image": "res://assets/ui/sites/houses.png", "available": true, "note": ""},
	]
	if with_scrapyard:
		sites.append({"id": "scrapyard", "name": "The scrapyard", "blurb": "Stacks of cars and a dog that is not a dog any more. Plenty of scrap, for anyone who can carry it.", "danger": 3, "loot": {"scrap": [35, 60]}, "extra": {"food": [0.3, 2]}, "image": "res://assets/ui/sites/scrapyard.png", "available": true, "note": ""})
	return sites


## {"g", "sim", "holder", "hud", "pressed": ids of gizmo presses, "speeds",
## "selected"}: a new run on day 1 with fake modules and the HUD set up. With `real_people` the game's own
## traits, morale, bonds, skills and barks stay (the other modules are still the fakes).
static func build(width: int = 1280, height: int = 800, seed_value: int = 1, real_people: bool = false) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.supplies = FakeSupplies.new()
	sim.medical = FakeMedical.new()
	sim.scavenge = FakeScavenge.new()
	sim.scenario = FakeScenario.new()
	sim.tactics = FakeTactics.new()
	var modules: Array = [sim.supplies, sim.medical, sim.scavenge, sim.scenario, sim.tactics]
	# the worktable (a sim from before the workshop has none: the HUD copes with that too)
	if sim.get("workshop") != null:
		sim.workshop = FakeWorkshop.new()
		modules.append(sim.workshop)
	# the people (a sim from before round 4 has none of these: the HUD copes with that too)
	if sim.get("traits") != null and not real_people:
		sim.traits = FakeTraits.new()
		sim.morale = FakeMorale.new()
		sim.bonds = FakeBonds.new()
		sim.skills = FakeSkills.new()
		sim.barks = FakeBarks.new()
		modules.append_array([sim.traits, sim.morale, sim.bonds, sim.skills, sim.barks])
	for m in modules:
		m.setup(sim)
	var ctx := {"g": g, "sim": sim, "pressed": [], "speeds": [], "selected": []}
	var holder := Control.new()
	holder.size = Vector2(width, height)
	Engine.get_main_loop().root.add_child(holder)
	var hud := Hud.new()
	holder.add_child(hud)
	hud.on_select = func(s): ctx.selected.append(s)
	hud.on_focus = func(_p): pass
	hud.on_speed = func(s): ctx.speeds.append(s)
	hud.on_gizmo = func(id): ctx.pressed.append(id)
	hud.on_alert = func(_id): pass
	hud.on_sound = func(): pass
	hud.setup(g.data, sim.people)
	ctx["holder"] = holder
	ctx["hud"] = hud
	return ctx


static func free_all(ctx: Dictionary) -> void:
	ctx.holder.free()
	ctx.g.world.free()


## One HUD update, as main.gd does every tenth of a second.
static func update(ctx: Dictionary, speed: int = 1) -> void:
	ctx.hud.update_hud(ctx.sim, speed, true, 4)


## Lets containers sort themselves (minimum sizes settle a frame late).
static func settle() -> void:
	var tree := Engine.get_main_loop()
	await tree.process_frame
	await tree.process_frame


static func resize(ctx: Dictionary, width: int, height: int) -> void:
	ctx.holder.size = Vector2(width, height)


static func person(ctx: Dictionary, id: String):
	for p in ctx.sim.people:
		if p.id == id:
			return p
	return null


static func select(ctx: Dictionary, p) -> void:
	ctx.hud.select({"kind": "person", "ref": p})


## The card dictionary (see hud.cards) for a person.
static func card(ctx: Dictionary, p) -> Dictionary:
	for c in ctx.hud.cards:
		if c.p == p:
			return c
	return {}


## Every Label text under `node`, visible or not.
static func texts(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append(node.text)
	for c in node.get_children():
		texts(c, out)
	return out


## The ids of the gizmo buttons now in the dock, in order.
static func gizmo_ids(ctx: Dictionary) -> Array:
	var ids: Array = []
	for b in ctx.hud.gizmos.get_children():
		if b is Button and b.has_meta("id"):
			ids.append(b.get_meta("id"))
	return ids


static func gizmo(ctx: Dictionary, id: String) -> Button:
	for b in ctx.hud.gizmos.get_children():
		if b is Button and b.has_meta("id") and b.get_meta("id") == id:
			return b
	return null


## The picture of a frame style box and the part of it inside its margins (the part text sits
## on), as {"image", "inner"}, or {} when its pixels cannot be had. A frame made by Hud.frame is
## read from its PNG on disk (a headless renderer keeps no pixels of an imported texture), any
## other texture from the texture itself.
static func _frame_pixels(sb: StyleBoxTexture) -> Dictionary:
	var name := String(sb.get_meta("frame", ""))
	if name != "":
		var frames = load("res://scripts/ui/frames.gd")
		var info: Dictionary = frames.info(name)
		if not info.is_empty() and info.has("file") and info.has("margin"):
			# read from the file on disk (the project path, so that no warning about export is logged)
			var img := Image.load_from_file(ProjectSettings.globalize_path(String(info.file)))
			if img != null and not img.is_empty():
				var m: Array = info.margin
				var inner := Rect2(float(m[0]), float(m[1]), img.get_width() - float(m[0]) - float(m[2]), img.get_height() - float(m[1]) - float(m[3]))
				if inner.size.x < 2.0 or inner.size.y < 2.0:
					inner = Rect2(Vector2.ZERO, Vector2(img.get_size()))
				return {"image": img, "inner": inner}
	var img2: Image = sb.texture.get_image()
	if img2 == null or img2.is_empty():
		return {}
	if img2.is_compressed():
		img2.decompress()
	var whole := Rect2(Vector2.ZERO, Vector2(img2.get_size()))
	var r: Rect2 = sb.region_rect if sb.region_rect.size != Vector2.ZERO else whole
	var inner2 := Rect2(r.position + Vector2(sb.texture_margin_left, sb.texture_margin_top), r.size - Vector2(sb.texture_margin_left + sb.texture_margin_right, sb.texture_margin_top + sb.texture_margin_bottom))
	if inner2.size.x < 2.0 or inner2.size.y < 2.0:
		inner2 = r
	return {"image": img2, "inner": inner2}


## What a style box looks like behind text, as [darkest, lightest] colours (each may be
## translucent): a flat box is its colour; a frame is the darkest and the lightest of the
## picture's middle (the part inside its margins, where text sits) as the box tints it. A box
## with nothing to say (none, or a picture that cannot be read) is [transparent, transparent].
static func fills(sb) -> Array:
	var none := Color(0, 0, 0, 0)
	if sb is StyleBoxFlat:
		return [sb.bg_color, sb.bg_color]
	if sb is StyleBoxTexture and sb.texture != null:
		var px := _frame_pixels(sb)
		if px.is_empty():
			return [none, none]
		var img: Image = px.image
		var inner: Rect2 = px.inner
		var samples: Array = []
		var n := 14
		for iy in n:
			for ix in n:
				var at := inner.position + Vector2(inner.size.x * (ix + 0.5) / n, inner.size.y * (iy + 0.5) / n)
				var c := img.get_pixel(clampi(int(at.x), 0, img.get_width() - 1), clampi(int(at.y), 0, img.get_height() - 1))
				samples.append(Color(c.r * sb.modulate_color.r, c.g * sb.modulate_color.g, c.b * sb.modulate_color.b, c.a * sb.modulate_color.a))
		samples.sort_custom(func(a, b): return a.get_luminance() < b.get_luminance())
		var lo: Color = samples[int(samples.size() * 0.05)]
		var hi: Color = samples[mini(samples.size() - 1, int(samples.size() * 0.95))]
		return [lo, hi]
	return [none, none]


## The on-screen rectangle of a control, or an empty one if it is hidden.
static func rect(c: Control) -> Rect2:
	if c == null or not c.is_visible_in_tree():
		return Rect2()
	return c.get_global_rect()


## Names of the pairs of rectangles that overlap by more than `slack` pixels.
static func overlaps(named: Dictionary, slack: float = 0.5) -> Array:
	var out: Array = []
	var keys: Array = named.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = named[keys[i]]
			var b: Rect2 = named[keys[j]]
			if a.size == Vector2.ZERO or b.size == Vector2.ZERO:
				continue
			var inter := a.intersection(b)
			if inter.size.x > slack and inter.size.y > slack:
				out.append("%s overlaps %s by %.0fx%.0f" % [keys[i], keys[j], inter.size.x, inter.size.y])
	return out


## A left click at `at` (canvas coordinates: the headless window is tiny and scaled,
## so the event goes in as already local to the viewport).
static func click(at: Vector2) -> void:
	var root: Window = Engine.get_main_loop().root
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev, true)


## A click in the middle of a control.
static func click_on(c: Control) -> void:
	click(c.get_global_rect().get_center())
