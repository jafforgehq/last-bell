## `sim.houses`: the town's houses, rooms, doors and containers as the rules read them (the generator's data, scripts/town/town_gen.gd; it is made from the seed
## again on a load, so nothing is saved). Plan 2.2 of docs/superpowers/plans/2026-10-04-one-house-plan.md has the signatures; they are frozen.
##
## Everything is in tiles. A house is {id, kind, address, rect (the outer walls = the footprint), lot, front, fenced, door, doors, rooms (room indexes), containers
## (ids), dead (record indexes at the start)}; a room {id "h17:kitchen", house, name, rect (the floor)}; a door {tiles, exterior, side, out, in}; a container {id, house,
## room, pos (where to stand), at (the furniture), kind, loot, search_s}. "Not in any house" and "on a wall or in a doorway" are -1.
extends RefCounted

const TownGen := preload("res://scripts/town/town_gen.gd")

var sim
var town: Dictionary = {}
## Container ids to the container (made once).
var _by_id := {}
var enabled := true


func setup(s) -> void:
	sim = s


## The generated town the rules play on (`TownGen.make` result).
func use_town(t: Dictionary) -> void:
	town = t
	_by_id.clear()
	for c in town.get("containers", []):
		_by_id[String(c.id)] = c


func start() -> void:
	pass


func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass


## The house whose walls hold the point (the doorways included), or -1.
func house_at(x: float, y: float) -> int:
	return TownGen.house_at(town, x, y) if not town.is_empty() else -1


## The room whose floor holds the point, or -1 (a wall, a doorway, outside).
func room_at(x: float, y: float) -> int:
	return TownGen.room_at(town, x, y) if not town.is_empty() else -1


func count() -> int:
	return town.houses.size() if not town.is_empty() else 0


func house(id: int) -> Dictionary:
	if town.is_empty() or id < 0 or id >= town.houses.size():
		return {}
	return town.houses[id]


func room(i: int) -> Dictionary:
	if town.is_empty() or i < 0 or i >= town.rooms.size():
		return {}
	return town.rooms[i]


## The room indexes of a house.
func rooms_of(house_id: int) -> Array:
	return house(house_id).get("rooms", [])


func doors_of(house_id: int) -> Array:
	return house(house_id).get("doors", [])


## The containers of a house, the dictionaries (not the ids).
func containers_of(house_id: int) -> Array:
	var out: Array = []
	for id in house(house_id).get("containers", []):
		out.append(_by_id[String(id)])
	return out


func container(id: String) -> Dictionary:
	return _by_id.get(id, {})


func start_house() -> int:
	return int(town.start.house) if not town.is_empty() else -1


## The house whose middle is nearest `at` (and for which `only.call(id)` is true when a filter is given), or -1.
func nearest_house(at: Vector2, only: Callable = Callable()) -> int:
	var best := -1
	var best_d := INF
	for h in town.get("houses", []):
		if only.is_valid() and not bool(only.call(int(h.id))):
			continue
		var d := Vector2(Rect2i(h.rect).get_center()).distance_to(at)
		if d < best_d:
			best_d = d
			best = int(h.id)
	return best


## How many dead are in a room now, not killed, awake or dormant, by where they are, not where they began.
func dead_in_room(room_index: int) -> int:
	var f = sim.get("field")
	return int(f.dead_in_room(room_index).left) if f != null else 0


func dead_in_house(id: int) -> int:
	var f = sim.get("field")
	return int(f.dead_in_house(id).left) if f != null else 0
