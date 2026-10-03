## Shared by the whole-trip tests of the live drive (tests/test_road_flow.gd, tests/test_round21_integration.gd; this file has no test_
## prefix so the runner skips it): a trip opened as the Town Board opens it (`main.open_raid`, the real flow, the real scene, the real
## road generator and events), played by hand with the autopilot driving, its cards answered by a policy, the place stood in for by a few
## numbers (loot found, ammo shot), and the books of the colony before and after so that a test can reconcile them: the fuel, the
## vehicle's hp, the stores, the ammunition, the people and the clock.
extends RefCounted

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")
const DriveScene := preload("res://scripts/drive/drive_scene.gd")
const RoadEvents := preload("res://scripts/drive/road_events.gd")

const STEP := 1.0 / 30.0
const STOCKS := ["food", "water", "scrap", "meds", "ammo"]

## What a card's answer is when a test says nothing: the useful option of each event, else the first one that is allowed.
const POLICY := ["search", "take", "siphon", "toll", "check", "plough", "fix", "through", "pass"]


## The module of the scene's events with a ledger: it does what road_events.gd does (the scene's `stand_ins` take it in its place) and
## keeps what each `apply` changed in the colony's tank, the vehicle's hp and the stores, so that the books can be reconciled by what the
## events did and nothing else.
class Recorder:
	extends RefCounted
	var sim
	var vehicle_id := ""
	var fuel := 0.0
	var hp := 0.0
	var stock := {}
	var applied: Array = []
	var planned: Array = []

	func plan(seed_value, ctx):
		var out: Array = RoadEvents.plan(seed_value, ctx)
		planned.append(out.map(func(e): return "%s@%.2f" % [e.id, e.at]))
		return out

	func make_ctx(flow, leg := "there"):
		return RoadEvents.make_ctx(flow, leg)

	func ambient_for(ctx):
		return RoadEvents.ambient_for(ctx)

	func night_at(hour, dusk, dawn):
		return RoadEvents.night_at(hour, dusk, dawn)

	func options(entry, ctx):
		return RoadEvents.options(entry, ctx)

	func resolve(entry, choice_id, ctx):
		return RoadEvents.resolve(entry, choice_id, ctx)

	func deck():
		return RoadEvents.deck()

	func apply(effects, flow):
		var tank0: float = sim.vehicles.fuel
		var hp0 := float(sim.vehicles.vehicle(vehicle_id).get("hp", 0.0))
		var stock0 := {}
		for k in STOCKS:
			stock0[k] = float(sim.stock.get(k, 0.0))
		var told = RoadEvents.apply(effects, flow)
		fuel += float(sim.vehicles.fuel) - tank0
		hp += float(sim.vehicles.vehicle(vehicle_id).get("hp", 0.0)) - hp0
		for k in STOCKS:
			stock[k] = float(stock.get(k, 0.0)) + float(sim.stock.get(k, 0.0)) - float(stock0[k])
		applied.append(effects.duplicate(true))
		return told


## A trip of the crew after Ruth (`n` of them, in a vehicle of `kind`, "" on foot) to `place_id`, opened by `main.open_raid`. The scene's
## own frames are off (the test ticks it). {"scene", "flow", "sim", "main", "vehicle", "rec", "before", "answered"}.
static func open(main: Node, place_id: String, kind: String, n: int = 2, seed_value: int = -1, events: bool = true, fuel: float = 50.0) -> Dictionary:
	PlaceFlow.live_enabled = true
	PlaceFlow.fast_road = false
	PlaceFlow.no_events = not events
	var sim = main.sim
	sim.waves.enabled = false
	sim.town.reveal(place_id)
	sim.vehicles.fuel = fuel
	var vehicle := String(sim.vehicles.add(kind).id) if kind != "" else ""
	if seed_value >= 0:
		main.raid_seed = seed_value
	var rec := Recorder.new()
	rec.sim = sim
	rec.vehicle_id = vehicle
	DriveScene.stand_ins = {"road_events": rec}
	var crew: Array = []
	for i in n:
		crew.append(sim.people[i + 1])
	var before := books(sim, vehicle)
	var scene = main.open_raid(crew, sim.town.place(place_id), vehicle, 1.0, Callable())
	if scene != null:
		scene.set_process(false)
	return {"scene": scene, "flow": scene.flow if scene != null else null, "sim": sim, "main": main, "vehicle": vehicle, "rec": rec,
		"before": before, "answered": [], "place_id": place_id, "crew": crew}


## The colony's books now: the tank, the vehicle's hp (-1 when it is not in the fleet), the stores, the clock, the people at home.
static func books(sim, vehicle: String) -> Dictionary:
	var stock := {}
	for k in STOCKS:
		stock[k] = float(sim.stock.get(k, 0.0))
	return {"fuel": float(sim.vehicles.fuel), "hp": float(sim.vehicles.vehicle(vehicle).get("hp", -1.0)) if vehicle != "" and not sim.vehicles.vehicle(vehicle).is_empty() else -1.0,
		"stock": stock, "clock": float(sim.clock_min), "people": sim.people.size()}


## The id of the option a card is answered with: `choices` (a dictionary event id -> option id) first, else the first allowed of POLICY, else the
## first allowed one.
static func pick(scene: Node, choices: Dictionary = {}) -> String:
	var e: Dictionary = scene.open_entry()
	var opts: Array = scene.card_options()
	var want := String(choices.get(String(e.get("id", "")), ""))
	for o in opts:
		if want != "" and String(o.id) == want and bool(o.get("ok", true)):
			return want
	for id in POLICY:
		for o in opts:
			if String(o.id) == id and bool(o.get("ok", true)):
				return id
	for o in opts:
		if bool(o.get("ok", true)):
			return String(o.id)
	return ""


## Plays the trip until `done.call(scene)` or the report: the autopilot drives, every card that opens is answered at once (`choices`), the
## place is stood in for when the squad arrives (`at_place.call(scene)` puts what the place did into the run, then the squad is at the exit).
## Returns the scene's steps. `t.answered` lists "id:option".
static func play(t: Dictionary, choices: Dictionary = {}, at_place: Callable = Callable(), limit: int = 60000, done: Callable = Callable()) -> int:
	var scene: Node = t.scene
	var n := 0
	var placed := false
	while scene.phase != "report" and n < limit:
		if done.is_valid() and bool(done.call(scene)):
			break
		scene.tick(STEP)
		n += 1
		if scene.open_uid != "":
			var e: Dictionary = scene.open_entry()
			var option := pick(scene, choices)
			if option != "":
				t.answered.append("%s:%s" % [e.id, option])
				scene.choose(scene.open_uid, option)
		if scene.leg == "place" and not placed:
			placed = true
			if at_place.is_valid():
				at_place.call(scene)
			scene.stage("exit")
	return n


## What a place did, as numbers: the loot in the bags and the rounds shot (the place's own play is the base's and has its tests).
static func place_gave(loot: Dictionary, shot: float) -> Callable:
	return func(scene: Node) -> void:
		for k in loot:
			scene.run.carried[k] = int(loot[k])
		scene.run.sim.stock.ammo = float(scene.run.sim.stock.ammo) - shot


## The colony's steps until the party is home (and the unloading is done): the count.
static func settle(sim, limit: int = 120000) -> int:
	var steps := 0
	while not sim.scavenge.parties.is_empty() and steps < limit:
		sim.update(STEP)
		steps += 1
	return steps


## What the books of a finished, settled trip must say, from what the trip itself recorded: {"name": [expected, actual]}. The tank is what
## it was less the abstract trip's fuel (burnt once, at the gate) plus what the events and the loot put in; the vehicle is its hp less the
## legs' wear, less what the events did, less the place's danger and the wounded at the gate; each store is what it was plus what the events
## paid (negative) and the loot that came home, less the rounds shot (the road's and the place's: `ammo_used`).
static func reconcile(t: Dictionary, danger: int) -> Dictionary:
	var sim = t.sim
	var flow = t.flow
	var res: Dictionary = flow.result
	var before: Dictionary = t.before
	var after := books(sim, t.vehicle)
	var rec = t.rec
	var out := {}
	var need: float = sim.vehicles.fuel_for(t.place_id, t.vehicle) if t.vehicle != "" else 0.0
	var cap: float = float(sim.vehicles.FUEL_CAP)
	out["fuel"] = [minf(cap, float(before.fuel) - need + float(rec.fuel) + float(res.get("loot", {}).get("fuel", 0))), after.fuel]
	if t.vehicle != "":
		var wear := 0.0
		for leg in flow.legs:
			wear += float(leg.vehicle_hp_lost)
		var wounded: int = (res.get("hurt", {}) as Dictionary).size()
		var came: bool = (res.get("lost", []) as Array).size() < t.crew.size() + 1
		out["hp"] = [float(before.hp) - wear + float(rec.hp) - (5.0 * float(danger) + 3.0 * float(wounded) if came else 0.0), after.hp]
	for k in STOCKS:
		var shot: float = float(res.get("ammo_used", 0.0)) if k == "ammo" else 0.0
		out[k] = [float(before.stock[k]) + float(rec.stock.get(k, 0.0)) + float(res.get("loot", {}).get(k, 0)) - shot, after.stock[k]]
	return out
