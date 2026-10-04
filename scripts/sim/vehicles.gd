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
##
## THE MOTOR POOL (round 15): each vehicle of the fleet has a `spot`, a place of the motor pool (scripts/sim/convoy.gd, the
## apron just inside the main gate). It gets the lowest free one when it is added and keeps it, out or home; a vehicle that
## comes home to find its place taken (an old save, two in one) is given the lowest that is free. With every place taken (the
## game has four vehicles and the pool four places, but a test or a debug start may have more) a vehicle shares the place
## held by the fewest, so `spot` is always a place of the pool. A vehicle's seats go to doors: `seat_door(kind, seat)` is
## the door of that seat (from the `doors` of vehicles.json, when the kind has them: {id, side, seats}; else the side rule:
## "L1", "R1", "L2", "R2" in the order of the seats, a bus's one door "F"), `door_ids(kind)` all of them.
extends RefCounted

const Convoy := preload("res://scripts/sim/convoy.gd")

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
## [{"id", "kind", "hp", "state": "parked" | "out", "spot": a place of the motor pool}]
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


## The doors of a kind without doors in the data, in the order the seats take them.
const SIDE_DOORS := ["L1", "R1", "L2", "R2"]


## How many people the kind seats (0 for a kind that does not exist).
func seats(kind_id: String) -> int:
	return int(kind(kind_id).get("seats", 0))


## The ids of a kind's doors: the data's, or the usual ones (two for a seat or two, four for a car or a van, "F" for a bus).
func door_ids(kind_id: String) -> Array:
	var doors = kind(kind_id).get("doors")
	if doors is Array and not doors.is_empty():
		var ids: Array = []
		for d in doors:
			if d is Dictionary and String(d.get("id", "")) != "":
				ids.append(String(d.id))
		if not ids.is_empty():
			return ids
	var n := seats(kind_id)
	if kind_id == "bus" or n > 4:
		return ["F"]
	if n >= 1 and n <= 2:
		return SIDE_DOORS.slice(0, 2)
	return SIDE_DOORS.duplicate()


## The door a person in seat `seat` (0, 1, 2 ... in the order the party goes) uses. With `spot` (the place of the pool the
## car stands on) it is one of the doors on the aisle side of the bay (a car in the west bay: the right-hand doors; in the
## east bay: the left-hand), the seats taking them in turn: nobody walks through the car to a door on its far side. A car
## with one door on that side (a pickup, a van) has its people go in one after another.
func seat_door(kind_id: String, seat: int, spot: int = -1) -> String:
	var door := _data_door(kind_id, seat)
	var want := Convoy.aisle_side(spot) if spot >= 0 else ""
	if want == "" or door == "":
		return door
	# the doors on the aisle side, one after another by seat (a bay car's far doors are never used)
	var near_doors: Array = []
	for id in door_ids(kind_id):
		if String(id).begins_with(want):
			near_doors.append(String(id))
	return door if near_doors.is_empty() else String(near_doors[maxi(seat, 0) % near_doors.size()])


## The door the data (or the side rule) gives a seat. The `seats` lists are compared as whole numbers: they come out of JSON
## as floats, and in GDScript 4.7 a list [2.0] does not "have" 2.
func _data_door(kind_id: String, seat: int) -> String:
	var doors = kind(kind_id).get("doors")
	if doors is Array:
		for d in doors:
			if d is Dictionary and d.get("seats") is Array:
				for listed in d.seats:
					if int(listed) == seat:
						return String(d.get("id", ""))
	var ids := door_ids(kind_id)
	return String(ids[maxi(seat, 0) % ids.size()])


## The vehicles on the apron: the ones that are parked.
func parked() -> Array:
	var out: Array = []
	for v in fleet:
		if String(v.state) == "parked":
			out.append(v)
	return out


## The place of the motor pool that is free: the lowest that no vehicle holds (`except` is not counted: the one that is
## looking), or, when all are held, the one held by the fewest.
func free_spot(except: Dictionary = {}, kind_id: String = "") -> int:
	var long_spot := Convoy.long_spot()
	# a vehicle too long for a bay (the bus) has the long place, whoever stands on it
	if kind_id != "" and long_spot >= 0 and Convoy.is_long(kind(kind_id)):
		return long_spot
	var held := {}
	var long_in_fleet := false
	for v in fleet:
		if not except.is_empty() and is_same(v, except):
			continue
		var at := int(v.get("spot", -1))
		held[at] = int(held.get(at, 0)) + 1
		if Convoy.is_long(kind(String(v.kind))):
			long_in_fleet = true
	# nobody else takes the long place while there is a bus to come home to it
	var best := -1
	var fewest := 1 << 30
	for i in maxi(Convoy.spots(), 1):
		if i == long_spot and long_in_fleet:
			continue
		var n := int(held.get(i, 0))
		if n == 0:
			return i
		if n < fewest:
			fewest = n
			best = i
	return maxi(best, 0)


## Makes sure the vehicle has a place of the pool to itself (or, if there is none, one that is a place at all); returns it.
func ensure_spot(v: Dictionary) -> int:
	var spot := int(v.get("spot", -1))
	var shared := false
	for other in fleet:
		if not is_same(other, v) and int(other.get("spot", -1)) == spot:
			shared = true
	var long_spot := Convoy.long_spot()
	if long_spot >= 0 and Convoy.is_long(kind(String(v.kind))):
		v["spot"] = long_spot
		for other in fleet:
			if not is_same(other, v) and int(other.get("spot", -1)) == long_spot:
				other["spot"] = free_spot(other, String(other.kind))    # (it is moved off the bus's place)
		return long_spot
	if long_spot >= 0 and spot == long_spot and _fleet_has_long(v):
		v["spot"] = free_spot(v, String(v.kind))
		return int(v.spot)
	if spot < 0 or spot >= maxi(Convoy.spots(), 1) or shared:
		v["spot"] = free_spot(v, String(v.kind))
	return int(v.spot)


## Whether the fleet has a vehicle too long for a bay (other than `except`).
func _fleet_has_long(except: Dictionary = {}) -> bool:
	for v in fleet:
		if not is_same(v, except) and Convoy.is_long(kind(String(v.kind))):
			return true
	return false


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


## The fuel one leg of the road burns (round 21, the live drive): half of the trip's, `burn` x the road's hours. A drive there and
## back with nothing in the way burns exactly `fuel_for`; the live drive shows this tank draining by distance.
func fuel_per_leg(place_id: String, vehicle_id: String) -> float:
	return fuel_for(place_id, vehicle_id) / 2.0


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
	ensure_spot(v)    # (its place may have been taken while it was out)
	if WEAR_PER_DANGER * float(danger) + WEAR_PER_WOUND * float(hurt) > 0.0:
		sim.events.append({"type": "vehicle", "id": String(v.id), "what": "damaged"})


func _lose(v: Dictionary) -> void:
	fleet.erase(v)
	sim.events.append({"type": "vehicle", "id": String(v.id), "what": "lost"})
	sim.alert("vehicle-%s" % String(v.id), "danger", "The %s is lost" % String(kind(String(v.kind)).get("name", "vehicle")).to_lower(), "It will not be coming back", null, 20.0)


# ------------------------------------------------------------------- the live road (round 21) --

## The road wears the vehicle (the live drive's crashes and events): `hp_lost` is taken off, and its hp never goes below 1. False when
## it was at 1 already (nothing is left to wear: the caller `wreck`s it); a knock that takes it down to 1 is true, it limps on. Nothing
## lost, nothing changes; a vehicle that is not in the fleet is nothing to wreck (true).
func road_wear(vehicle_id: String, hp_lost: float) -> bool:
	var v := vehicle(vehicle_id)
	if v.is_empty() or hp_lost <= 0.0 or not is_finite(hp_lost):
		return true
	var was := float(v.hp)
	v["hp"] = maxf(1.0, was - hp_lost)
	return was > 1.0


## The vehicle is lost on the road (a wreck the party leaves behind): off the fleet, with an alert that says where ("The pickup is
## lost: left on the road to the pharmacy"). The party it carried goes on without a car: it is a party on foot from now on (its
## way home is the whole way, and nothing drives in at the gate). A vehicle that is not there is left alone.
func wreck(vehicle_id: String, why: String) -> void:
	var v := vehicle(vehicle_id)
	if v.is_empty():
		return
	var name := String(kind(String(v.kind)).get("name", "vehicle")).to_lower()
	fleet.erase(v)
	sim.events.append({"type": "vehicle", "id": String(v.id), "what": "lost"})
	sim.alert("vehicle-%s" % String(v.id), "danger", ("The %s is lost: %s" % [name, why]) if why != "" else ("The %s is lost" % name), "It will not be coming back", null, 20.0)
	for party in sim.scavenge.parties:
		if String(party.get("vehicle", "")) == String(v.id):
			party["vehicle"] = ""
			for key in ["seats", "doors", "drive_t", "drive_len", "aboard", "unload", "unload_wait"]:
				party.erase(key)
			if ["driving_out", "driving_in", "unloading"].has(String(party.state)):
				party["state"] = "away"


# ------------------------------------------------------------------ a parked car is in the way --

## How far (tiles) the ground a car shuts is drawn in from its body, so that the place beside a door (just outside the body)
## is always open and people can stand there; a tile is shut when its middle is inside the shrunk body.
const FOOT_SHRINK := 0.2

## The walking ground this module has shut (tile index -> true): the bodies of the cars that stand in their bays.
var _shut := {}


## The tiles a vehicle's body covers where it stands in its bay (indices into the walking grids), by the tiles' middles.
func footprint_tiles(v: Dictionary) -> Array:
	var out: Array = []
	var at := Convoy.bay(int(v.get("spot", -1)))
	if at == Convoy.NOWHERE or sim.world == null:
		return out
	var k := kind(String(v.get("kind", "")))
	var w := float(k.get("w", Convoy.DEFAULT_W))
	var h := float(k.get("h", Convoy.DEFAULT_H))
	var x0 := at.x - w / 2.0 + FOOT_SHRINK
	var x1 := at.x + w / 2.0 - FOOT_SHRINK
	var y0 := at.y - h / 2.0 + FOOT_SHRINK
	var y1 := at.y + h / 2.0 - FOOT_SHRINK
	for ty in range(floori(y0), floori(y1) + 1):
		for tx in range(floori(x0), floori(x1) + 1):
			var mx := float(tx) + 0.5
			var my := float(ty) + 0.5
			if mx >= x0 - 0.01 and mx <= x1 + 0.01 and my >= y0 - 0.01 and my <= y1 + 0.01 and tx >= 0 and ty >= 0 and tx < sim.world.W and ty < sim.world.H:
				out.append(ty * sim.world.W + tx)
	return out


## Whether the vehicle's body is in its bay right now: parked, or with its party walking to it, boarding it or getting out.
func _standing(v: Dictionary) -> bool:
	if String(v.get("state", "parked")) == "parked":
		return true
	for party in sim.scavenge.parties:
		if String(party.get("vehicle", "")) == String(v.get("id", "-")):
			var state := String(party.get("state", ""))
			return state == "out" or state == "unloading"
	return false


## Keeps the walking ground under the cars that stand in their bays shut, and gives it back when they drive off (people walk
## round a parked car instead of across its roof). Only open ground is shut, so a wall or a prop stays what it was; the rules
## call this every step (scavenge.update): with no vehicles it does nothing.
func sync_blocks() -> void:
	if fleet.is_empty() and _shut.is_empty():
		return
	var want := {}
	for v in fleet:
		if _standing(v):
			for i in footprint_tiles(v):
				want[int(i)] = true
	var close: Array = []
	for i in want:
		if not _shut.has(i) and int(sim.world.solid_p[i]) == 0:
			close.append(i)
	var open: Array = []
	for i in _shut:
		if not want.has(i):
			open.append(i)
	if not close.is_empty():
		sim.block_tiles(close, true)
		for i in close:
			_shut[i] = true
	if not open.is_empty():
		sim.block_tiles(open, false)
		for i in open:
			_shut.erase(i)


## Gives back every tile this module has shut (a load starts again).
func _release_blocks() -> void:
	if _shut.is_empty():
		return
	sim.block_tiles(_shut.keys(), false)
	_shut.clear()


## A vehicle of this kind is brought home (parked in the motor pool); returns it, or {} for a kind that does not exist.
func add(kind_id: String) -> Dictionary:
	var k := kind(kind_id)
	if k.is_empty():
		return {}
	var v := {"id": "v%d" % _next, "kind": kind_id, "hp": float(k.hp), "state": "parked", "spot": free_spot({}, kind_id)}
	_next += 1
	fleet.append(v)
	ensure_spot(v)    # (a bus moves whoever stands on its place)
	sim.events.append({"type": "vehicle", "id": String(v.id), "what": "found"})
	return v


## ROUND 24, "a car to begin with": a new game of the avatar (settlement) game begins with ONE pickup, parked in the first bay of the motor pool
## and in good repair (its full hp), with fuel for `START_TRIPS` trips to the farthest place the Map shows on the first morning, so that the
## Map's Take control and the live drive can use it from day 1. Called by main.gd for a new run of the real game only (never for a load: an
## older save has no starting car and is not given one, never for the no-avatar game, the tests' games or Orientation Day). Returns the
## vehicle, or {} when nothing was given (a fleet that is not empty, no avatar, no town). A News line says so.
const START_KIND := "pickup"
const START_TRIPS := 2.0


func give_starting_car() -> Dictionary:
	if not fleet.is_empty() or String(sim.player_id) == "" or not bool(sim.town.on):
		return {}
	var v := add(START_KIND)
	if v.is_empty():
		return {}
	sim.events.pop_back()    # (`add` told the rules a vehicle was found: it was not found, it was always here)
	fuel = minf(FUEL_CAP, starting_fuel(String(v.id)))
	sim.radio.log_news("road", "The %s is fuelled" % name_of(String(v.id)).to_lower(), "Take control on the Map (G) to drive it")
	return v


## The fuel the starting car gets: START_TRIPS times what the farthest of the places known at the start costs there and back, rounded up
## (the pickup: 4.95 to the church, so 10).
func starting_fuel(vehicle_id: String) -> float:
	var worst := 0.0
	for p in sim.town.places:
		if sim.town.is_known(String(p.id)):
			worst = maxf(worst, fuel_for(String(p.id), vehicle_id))
	return ceilf(START_TRIPS * worst)


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
	_release_blocks()
	fuel = clampf(float(d.get("fuel", 0.0)), 0.0, FUEL_CAP)
	fleet.clear()
	var f = d.get("fleet", [])
	if f is Array:
		for e in f:
			if e is Dictionary and _kinds.has(String(e.get("kind", ""))):
				fleet.append({"id": String(e.get("id", "v%d" % (fleet.size() + 1))), "kind": String(e.kind), "hp": float(e.get("hp", 80.0)), "state": "parked" if String(e.get("state", "parked")) != "out" else "out", "spot": int(e.get("spot", -1))})
	_next = maxi(int(d.get("next", fleet.size() + 1)), fleet.size() + 1)
	# a save from before the motor pool has no places, and a damaged one may hold two vehicles in one: the first keeps its
	# place, the others are given the lowest that is free
	var taken := {}
	var homeless: Array = []
	for v in fleet:
		var at := int(v.spot)
		if at < 0 or at >= maxi(Convoy.spots(), 1) or taken.has(at):
			v["spot"] = -1
			homeless.append(v)
		else:
			taken[at] = true
	for v in homeless:
		v["spot"] = free_spot(v)
