## The colony's vehicles in the yard (round 13, "vehicles and fuel"; round 15, "the yard in motion"): the manager of the
## fleet's actors (scripts/render/vehicle_actor.gd). Each vehicle of the fleet (`sim.vehicles.fleet`) has one actor, made when
## it joins and freed when it is lost. An actor draws its vehicle by the saved state alone: parked on its place of the motor pool
## (the apron inside the main gate, assets/data/motor_pool.json through scripts/sim/convoy.gd), the doors swinging while people
## get in and out, driving the route out through the gate and in again, or not at all while it is away.
##
## - Only in a settlement game (`sim.town.on`): the classic start, the tutorial and the title's yard have none of it. (The
##   rules say it is a settlement game only after the node is built, so `update()` asks every frame, as the dressing does.)
## - Each actor is a small node at its feet in the y-sorted node the people are in (main.gd's `entities`), so a person walks
##   behind one and in front of another by where their feet are. Nothing here is solid and nothing touches the rules.
## - A click on a vehicle opens the Town Board (main.gd asks `vehicle_at`).
## - `gate_demand()` is what the gate's leaves follow (1 while a car or a person of a party on foot is about to pass it): see
##   scripts/render/gate_node.gd. The sounds (doors, engine, the gate's motor) play by distance to the camera.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const Actor := preload("res://scripts/render/vehicle_actor.gd")

const TILE := GD.TILE
const CONVOY_PATH := "res://scripts/sim/convoy.gd"
## How many places the motor pool has when there is no convoy to ask.
const MAX_SPOTS := 4
## A party on foot this close to the gate (tiles) wants it open.
const FOOT_REACH := 3.0
## Where the gate's motor is heard from (tiles), and how loud each sound is before the distance.
const GATE_AT := Vector2(39.0, 17.0)
const GAIN := {"car_door_open": 0.8, "car_door_close": 0.8, "car_engine_start": 0.9, "car_gate_motor": 0.7}

var sim
## The module of the routes (scripts/sim/convoy.gd): the real one unless a test hands another in.
var convoy
## The effects (main.gd's `fx`: dust), the sounds (main.gd's `sound`) and the volume by distance to the camera: all optional.
var fx
var sound
var vol_at: Callable = Callable()
## The gate's node (scripts/render/gate_node.gd), when there is one: it is told the demand every frame.
var gate
## The y-sorted node the people are in (main.gd's `entities`), or one of the node's own when there is none.
var _tall: Node2D
var _own_tall: Node2D
var _shown := false
## vehicle id -> VehicleActor
var _actors := {}
## vehicle id -> the place it last stood on (for a vehicle the fleet gives no place)
var _spot_of := {}
var _demand_before := -1.0
## How many nodes were made, for the tests.
var makes := 0


## `rules` is the sim (`town.on`, `vehicles` and `scavenge` are read), `stand_in` the y-sorted node the people are in.
func setup(rules, stand_in: Node2D = null) -> void:
	sim = rules
	if stand_in != null:
		_tall = stand_in
	else:
		_own_tall = Node2D.new()
		_own_tall.name = "Tall"
		_own_tall.z_index = 6
		_own_tall.y_sort_enabled = true
		add_child(_own_tall)
		_tall = _own_tall
	update()


## The effects, the sounds and the volume by distance (a Callable of x and y in tiles), as main.gd has them.
func wire(effects, sounds, volume_at: Callable) -> void:
	fx = effects
	sound = sounds
	vol_at = volume_at


func _exit_tree() -> void:
	_forget()


## Whether the rules are of a settlement game.
func is_on() -> bool:
	if sim == null:
		return false
	var town = sim.get("town")
	return town != null and bool(town.on) and sim.get("vehicles") != null


func _convoy():
	if convoy == null and ResourceLoader.exists(CONVOY_PATH):
		convoy = load(CONVOY_PATH)
	return convoy


## Called every frame by main.gd: puts every vehicle where the state says, makes the actors of vehicles that joined and frees
## those of vehicles that were lost, and drives the gate. `dt` is the real seconds of the frame (for the dust and the gate);
## -1: ask the engine.
func update(dt: float = -1.0) -> void:
	if dt < 0.0:
		dt = get_process_delta_time() if is_inside_tree() else 1.0 / 60.0
	if not is_on():
		if _shown:
			_shown = false
			_forget()
		_drive_gate(dt)    # (a party on foot opens the gate in any game)
		return
	_shown = true
	var fleet: Array = sim.vehicles.fleet
	var by_id := {}
	for v in fleet:
		by_id[String(v.id)] = v
	for id in _actors.keys():
		if not by_id.has(id) or String(_actors[id].kind.get("id", "")) != String(by_id[id].kind):
			_remove(String(id))    # (lost; or a new run's first vehicle may have an old one's id)
	_assign_spots(fleet)
	var cv = _convoy()
	for v in fleet:
		var id := String(v.id)
		if not _actors.has(id):
			_make(v)
		if not _actors.has(id):
			continue
		var actor = _actors[id]
		actor.fx = fx
		var p: Dictionary = Actor.pose_for(v, _party_of(id), int(_spot_of.get(id, 0)), cv)
		actor.apply(p, _share(v), cv, dt)
	_drive_gate(dt)


## The party that holds a vehicle, or {}.
func _party_of(vehicle_id: String) -> Dictionary:
	for party in sim.scavenge.parties:
		if String(party.get("vehicle", "")) == vehicle_id:
			return party
	return {}


## The place of each vehicle: the fleet's (`spot`), else the one it last had when no other holds it, else the first that is free.
func _assign_spots(fleet: Array) -> void:
	var used := {}
	var ids := {}
	for v in fleet:
		ids[String(v.id)] = true
		if int(v.get("spot", -1)) >= 0:
			_spot_of[String(v.id)] = int(v.spot)
			used[int(v.spot)] = String(v.id)
	for id in _spot_of.keys():
		if not ids.has(id):
			_spot_of.erase(id)
	for v in fleet:
		var id := String(v.id)
		if int(v.get("spot", -1)) >= 0:
			continue
		var spot := int(_spot_of.get(id, -1))
		if spot >= 0 and (not used.has(spot) or used[spot] == id):
			used[spot] = id
			continue
		_spot_of[id] = -1
	for v in fleet:
		var id := String(v.id)
		if int(_spot_of.get(id, -1)) >= 0:
			continue
		var places := _places()
		var taken := -1
		for spot in places:
			if not used.has(spot):
				taken = spot
				break
		_spot_of[id] = taken    # (-1: the pool is full; a vehicle with no place is not drawn)
		if taken >= 0:
			used[taken] = id


## How many places the motor pool has.
func _places() -> int:
	var cv = _convoy()
	return maxi(1, int(cv.spots())) if cv != null else MAX_SPOTS


## How much of its condition a vehicle has left (0 to 1).
func _share(v: Dictionary) -> float:
	var k: Dictionary = sim.vehicles.kind(String(v.kind))
	return clampf(float(v.hp) / maxf(float(k.get("hp", 100.0)), 1.0), 0.0, 1.0)


func _make(v: Dictionary) -> void:
	var id := String(v.id)
	var k: Dictionary = sim.vehicles.kind(String(v.kind))
	if k.is_empty():
		return
	var actor := Actor.new()
	if not actor.setup(id, k):
		actor.free()
		return
	makes += 1
	actor.name = "Car_%s" % id
	actor.made_sound.connect(_on_sound)
	_tall.add_child(actor)
	_actors[id] = actor


func _remove(id: String) -> void:
	var actor = _actors.get(id)
	if actor != null and is_instance_valid(actor):
		actor.queue_free()
	_actors.erase(id)


func _forget() -> void:
	for id in _actors.keys():
		_remove(String(id))
	_actors.clear()
	_spot_of.clear()
	_demand_before = -1.0


# ---------------------------------------------------------------------- the gate --

## 1.0 while a car is about to pass the gate (or has not yet cleared it), or a person of a party on foot is near it; else 0.0.
## The gate node eases to it (scripts/render/gate_node.gd `follow`).
func gate_demand() -> float:
	if sim == null:
		return 0.0
	if is_on():
		var cv = _convoy()
		for id in _actors:
			if _actors[id].wants_gate(cv):
				return 1.0
	return 1.0 if _foot_party_at_gate() else 0.0


## A member of a party on foot, on its way out, close to the gate.
func _foot_party_at_gate() -> bool:
	var scavenge = sim.get("scavenge")
	if scavenge == null:
		return false
	var gate_at: Vector2 = scavenge.gate_center()
	for party in scavenge.parties:
		if String(party.get("state", "")) != "out" or String(party.get("vehicle", "")) != "":
			continue
		for p in sim.people:
			if party.members.has(p.id) and p.away == null and Vector2(p.x, p.y).distance_to(gate_at) <= FOOT_REACH:
				return true
	return false


## The gate's motor as the demand rises, and the gate node (when there is one) following the demand. In avatar mode the gate's rules are in
## charge (round 22, scripts/sim/gate.gd): the node follows `sim.gate.open` whatever the demand, and the sounds are the rules' events
## (main.gd's `gate` event, `gate_sound`), so the demand makes no sound of its own there.
func _drive_gate(dt: float) -> void:
	var demand := gate_demand()
	var ruled: bool = gate != null and is_instance_valid(gate) and gate.has_method("ruled") and gate.ruled()
	if not ruled and _demand_before >= 0.0 and demand > _demand_before and _demand_before < 0.5:
		_on_sound("car_gate_motor", GATE_AT)
	_demand_before = demand
	if gate != null and is_instance_valid(gate):
		gate.follow(demand, dt)


## The sound of a step of the rules' gate (the `gate` event: "opening", "open", "closing", "shut"): the motor as the leaves begin to move, a
## latch as they close, and nothing as they open all the way (the motor has done it). Heard by distance to the camera, like the cars'.
func gate_sound(state: String) -> void:
	match state:
		"opening", "closing":
			_on_sound("car_gate_motor", GATE_AT)
		"shut":
			_on_sound("car_door_close", GATE_AT)


# ---------------------------------------------------------------------- sounds --

func _on_sound(sound_name: String, at: Vector2) -> void:
	if sound == null:
		return
	var streams = sound.get("streams")
	if not streams is Dictionary or not streams.has(sound_name) or streams[sound_name].is_empty():
		return    # (the sound is not in this build)
	var level := float(GAIN.get(sound_name, 1.0))
	if vol_at.is_valid():
		level *= float(vol_at.call(at.x, at.y))
	sound.play(sound_name, level)


# ------------------------------------------------------------------- looking up --

## The ids of the vehicles that are drawn now.
func drawn_ids() -> Array:
	var out: Array = []
	for id in _actors:
		if _actors[id].shown:
			out.append(id)
	return out


## The ids of every vehicle that has an actor (drawn or away).
func actor_ids() -> Array:
	return _actors.keys()


## The actor of a vehicle, or null.
func actor_of(id: String):
	return _actors.get(id)


## The place of the motor pool (0 to MAX_SPOTS - 1) a vehicle parks on, or -1 for one that has no actor.
func spot_of(id: String) -> int:
	return int(_spot_of.get(id, -1)) if _actors.has(id) else -1


## The box a drawn vehicle takes in the world (tiles) where it is now, or an empty one.
func rect_of(id: String) -> Rect2:
	return _actors[id].rect() if _actors.has(id) else Rect2()


## The vehicle drawn under a point of the world (tiles): its id, or "".
func vehicle_at(w: Vector2) -> String:
	for id in _actors:
		if _actors[id].rect().has_point(w):
			return String(id)
	return ""


## The body's sprite of a drawn vehicle (for the tests), or null.
func sprite_of(id: String) -> Sprite2D:
	return _actors[id].body_sprite if _actors.has(id) else null


## Whether a drawn vehicle has the spanner over it.
func has_spanner(id: String) -> bool:
	return _actors.has(id) and _actors[id].shown and bool(_actors[id].mark.visible)
