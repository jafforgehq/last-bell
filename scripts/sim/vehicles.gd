## Vehicles and fuel (round 13, the settlement game's Town Board). The fleet (cars the party has got running and
## brought home) and the fuel they burn. Fuel is a store of its own (`fuel`, capped at FUEL_CAP), found as loot and
## spent by trips; a vehicle is "parked" at the gate, "out" with a party, or gone (lost: it is taken off the fleet).
## A trip by vehicle (`scavenge.send(.., vehicle_id)`) takes the road's hours divided by the vehicle's speed, burns
## `burn` fuel for each hour driven, may carry as many as its seats and multiplies the loot by its `cargo`.
##
## A place of the town may hold a vehicle (`vehicle` in town.json): looting or clearing it, a party that comes home
## has a chance (BASE_CHANCE plus PER_BUILDING for each point of Building in it, at most MAX_CHANCE) to have got it
## running and driven it home.
##
## Events: {"type": "vehicle", "id": id, "what": "found"|"lost"|"damaged"}.
extends RefCounted

const DATA_PATH := "res://assets/data/vehicles.json"
## Where the data is read from (tests may point it at another file).
static var data_path := DATA_PATH
static var _cache := {}

const FUEL_CAP := 80.0
const BASE_CHANCE := 0.5
const PER_BUILDING := 0.05
const MAX_CHANCE := 0.95
## A trip wears a vehicle: this much for each point of the place's danger, and for each of the party who came home hurt.
const WEAR_PER_DANGER := 5.0
const WEAR_PER_WOUND := 3.0

var sim
var fuel := 0.0
## [{"id", "kind", "hp", "state": "parked" | "out"}]
var fleet: Array = []
var _next := 1


func setup(s) -> void:
	sim = s
	_load()


func _load() -> void:
	if not _cache.has(data_path):
		var out := {}
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		if raw is Dictionary and raw.get("kinds") is Dictionary:
			for k in raw.kinds:
				var d: Dictionary = raw.kinds[k].duplicate(true)
				d["id"] = String(k)
				d["seats"] = int(d.get("seats", 2))
				d["speed"] = float(d.get("speed", 2.0))
				d["burn"] = float(d.get("burn", 3.0))
				d["cargo"] = float(d.get("cargo", 1.0))
				d["hp"] = float(d.get("hp", 80.0))
				out[String(k)] = d
		_cache[data_path] = out
	_kinds = _cache[data_path]


var _kinds := {}


func start() -> void:
	fuel = 0.0
	fleet.clear()
	_next = 1


# ----------------------------------------------------------------------- data --

func kinds() -> Dictionary:
	return _kinds


func kind(id: String) -> Dictionary:
	return _kinds.get(id, {})


## The kind of a vehicle of the fleet by its id, or {}.
func kind_of(vehicle_id: String) -> Dictionary:
	return kind(String(vehicle(vehicle_id).get("kind", "")))


# ---------------------------------------------------------------------- fleet --

func vehicle(id: String) -> Dictionary:
	for v in fleet:
		if String(v.id) == id:
			return v
	return {}


func parked() -> Array:
	var out: Array = []
	for v in fleet:
		if String(v.state) == "parked":
			out.append(v)
	return out


func name_of(vehicle_id: String) -> String:
	return String(kind_of(vehicle_id).get("name", "vehicle"))


## Fuel is put in the tank (up to the cap); returns how much went in.
func add_fuel(amount: float) -> float:
	var room := maxf(0.0, FUEL_CAP - fuel)
	var put := minf(room, maxf(0.0, amount))
	fuel += put
	return put


## The fuel a trip of this action to this place by this vehicle burns: `burn` for each hour driven (there and back).
func fuel_for(place_id: String, vehicle_id: String) -> float:
	var k := kind_of(vehicle_id)
	if k.is_empty():
		return 0.0
	return float(k.burn) * 2.0 * sim.town.hours_to(place_id) / float(k.speed)


## The hours the road takes (there and back, without the search) by this vehicle.
func drive_hours(place_id: String, vehicle_id: String) -> float:
	var k := kind_of(vehicle_id)
	if k.is_empty():
		return 2.0 * sim.town.hours_to(place_id)
	return 2.0 * sim.town.hours_to(place_id) / float(k.speed)


## Why this vehicle cannot take a party of `count` to this place ("" when it can).
func why_not_use(vehicle_id: String, count: int, place_id: String) -> String:
	var v := vehicle(vehicle_id)
	if v.is_empty():
		return "There is no such vehicle."
	if String(v.state) != "parked":
		return "The %s is out." % name_of(vehicle_id).to_lower()
	var k := kind_of(vehicle_id)
	if count > int(k.seats):
		return "The %s seats %d." % [name_of(vehicle_id).to_lower(), int(k.seats)]
	var need := fuel_for(place_id, vehicle_id)
	if fuel + 1.0e-9 < need:
		return "It needs %s fuel and the tank has %s." % [_num(need), _num(fuel)]
	return ""


## Takes the vehicle out with a party: the fuel is burnt, the vehicle is out.
func take(vehicle_id: String, place_id: String) -> void:
	var v := vehicle(vehicle_id)
	if v.is_empty():
		return
	fuel = maxf(0.0, fuel - fuel_for(place_id, vehicle_id))
	v["state"] = "out"


## The vehicle is home from a trip: parked again, worn by the place's danger and the hurt, or lost.
func come_home(vehicle_id: String, danger: int, hurt: int, party_lost: bool) -> void:
	var v := vehicle(vehicle_id)
	if v.is_empty():
		return
	if party_lost:
		_lose(v)
		return
	v["hp"] = float(v.hp) - WEAR_PER_DANGER * float(danger) - WEAR_PER_WOUND * float(hurt)
	if float(v.hp) <= 0.0:
		_lose(v)
		return
	v["state"] = "parked"
	if WEAR_PER_DANGER * float(danger) + WEAR_PER_WOUND * float(hurt) > 0.0:
		sim.events.append({"type": "vehicle", "id": String(v.id), "what": "damaged"})


func _lose(v: Dictionary) -> void:
	fleet.erase(v)
	sim.events.append({"type": "vehicle", "id": String(v.id), "what": "lost"})
	sim.alert("vehicle-%s" % String(v.id), "danger", "The %s is lost" % String(kind(String(v.kind)).get("name", "vehicle")).to_lower(), "It will not be coming back", null, 20.0)


## A vehicle of this kind is brought home (parked at the gate); returns it, or {} for a kind that does not exist.
func add(kind_id: String) -> Dictionary:
	var k := kind(kind_id)
	if k.is_empty():
		return {}
	var v := {"id": "v%d" % _next, "kind": kind_id, "hp": float(k.hp), "state": "parked"}
	_next += 1
	fleet.append(v)
	sim.events.append({"type": "vehicle", "id": String(v.id), "what": "found"})
	return v


## What a vehicle kind's cargo multiplier is (1 for none or an unknown kind), for what has no module at hand.
static func cargo_of(kind_id: String) -> float:
	var out := 1.0
	var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
	if raw is Dictionary and raw.get("kinds") is Dictionary and raw.kinds.has(kind_id):
		out = float(raw.kinds[kind_id].get("cargo", 1.0))
	return out


## A trip that never left (called off at the gate): the vehicle is parked again and the fuel is given back.
func cancel(vehicle_id: String, place_id: String) -> void:
	var v := vehicle(vehicle_id)
	if v.is_empty() or String(v.state) != "out":
		return
	add_fuel(fuel_for(place_id, vehicle_id))
	v["state"] = "parked"


## The chance a party with this much Building has of getting a found vehicle running.
static func start_chance(building_total: float) -> float:
	return minf(MAX_CHANCE, BASE_CHANCE + PER_BUILDING * building_total)


static func _num(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")


# ----------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {"fuel": fuel, "fleet": fleet.duplicate(true), "next": _next}


func load_state(d: Dictionary) -> void:
	fuel = clampf(float(d.get("fuel", 0.0)), 0.0, FUEL_CAP)
	fleet.clear()
	var f = d.get("fleet", [])
	if f is Array:
		for e in f:
			if e is Dictionary and _kinds.has(String(e.get("kind", ""))):
				fleet.append({"id": String(e.get("id", "v%d" % (fleet.size() + 1))), "kind": String(e.kind), "hp": float(e.get("hp", 80.0)), "state": "parked" if String(e.get("state", "parked")) != "out" else "out"})
	_next = maxi(int(d.get("next", fleet.size() + 1)), fleet.size() + 1)
