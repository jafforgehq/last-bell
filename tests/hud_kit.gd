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


## Three sites shaped like the ones the scavenging module returns.
static func sample_sites() -> Array:
	return [
		{"id": "pharmacy", "name": "The pharmacy", "blurb": "Shelves stripped, but the back room was locked.", "danger": 2, "loot": {"meds": [3, 6]}, "extra": {"food": [0.4, 2]}, "image": "res://assets/ui/sites/pharmacy.png", "available": true, "note": ""},
		{"id": "hardware", "name": "The hardware store", "blurb": "Crowbars, nails, boxes of shells.", "danger": 2, "loot": {"scrap": [10, 20], "ammo": [20, 60]}, "extra": {}, "image": "res://assets/ui/sites/hardware.png", "available": false, "note": "Picked over"},
		{"id": "houses", "name": "Neighbourhood houses", "blurb": "Somebody's pantry is somebody's pantry.", "danger": 1, "loot": {"food": [8, 14], "water": [10, 20]}, "extra": {"meds": [0.3, 1]}, "image": "res://assets/ui/sites/houses.png", "available": true, "note": ""},
	]


## {"g", "sim", "holder", "hud", "pressed": ids of gizmo presses, "speeds",
## "selected"}: a new run on day 1 with fake modules and the HUD set up.
static func build(width: int = 1280, height: int = 800, seed_value: int = 1) -> Dictionary:
	var g := Helpers.make(seed_value, 1)
	var sim = g.sim
	sim.supplies = FakeSupplies.new()
	sim.medical = FakeMedical.new()
	sim.scavenge = FakeScavenge.new()
	sim.scenario = FakeScenario.new()
	for m in [sim.supplies, sim.medical, sim.scavenge, sim.scenario]:
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
