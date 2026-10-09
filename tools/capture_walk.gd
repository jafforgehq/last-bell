extends "res://tools/capture_tap.gd"
## `--capture=walk`: a MORNING WALK of the claimed start house for a movie run (docs/audio-capture.md): through the hall (tile), the living room (wood), the kitchen (tile) and a
## bedroom (carpet), out of the front door, over the lawn (grass), the sidewalk and the road (paving, run and walk), and back. Meant for `--stage=claimed` of town 1 (the base house is
## the hall at 149.5,87.5); the legs are tiles of that house, found from its rooms, so any seed's start house works. The keys are W A S D and X as a player's hand would press them.

var _legs: Array = []
var _leg := 0
var _leg_t := 0.0
var _wait_t := 0.0


func _make_legs() -> void:
	var sim = main.sim
	var h: Dictionary = sim.houses.house(int(sim.base.house))
	var door: Vector2 = Vector2(h.door) + Vector2(0.5, 0.5)    # (the front door's tile, on the front side)
	var rooms := {}
	for r in h.rooms:
		var room: Dictionary = sim.houses.room(int(r))
		var rc: Rect2 = Rect2(room.rect)
		var key_name := String(room.name)
		if not rooms.has(key_name):
			rooms[key_name] = rc.get_center()
	_legs = []
	var hall: Vector2 = rooms.get("hall", door)
	if String(opts.get("route", "morning")) == "storm":
		# a storm night at the base: stand in the yard in the rain (the Ruth of the stage), then in at the door and wait under the roof, out once more and in
		_legs.append({"wait": 16.0})
		_legs.append({"to": door + Vector2(0, -1.5)})
		_legs.append({"to": hall + Vector2(0, -4.0)})
		_legs.append({"wait": 12.0})
		_legs.append({"to": door + Vector2(0, 3.0)})
		_legs.append({"wait": 12.0})
		return
	_legs.append({"to": hall + Vector2(0, -3.0)})
	for nm in ["living room", "kitchen", "bedroom"]:
		if rooms.has(nm):
			_legs.append({"to": rooms[nm]})
	_legs.append({"to": door + Vector2(0, -1.5)})
	_legs.append({"to": door + Vector2(0, 2.5)})                      # the porch and the lawn
	_legs.append({"to": door + Vector2(-5.0, 3.5)})                   # the lawn
	_legs.append({"to": door + Vector2(0, 5.5)})                      # the sidewalk
	_legs.append({"to": door + Vector2(0, 8.5), "run": true})         # the road
	_legs.append({"to": door + Vector2(11.0, 8.5), "run": true})
	_legs.append({"to": door + Vector2(-6.0, 8.5)})                   # back along the road at a walk
	_legs.append({"to": door + Vector2(-6.0, 3.0)})                   # up over the sidewalk and the lawn
	_legs.append({"to": door + Vector2(0, 1.0)})
	_legs.append({"to": door + Vector2(0, -2.0)})                     # in at the door again
	_legs.append({"to": hall + Vector2(0, -2.0)})                     # and a second lap: out, east over the lawn, the sidewalk, the road at a run, back at a walk
	_legs.append({"to": door + Vector2(8.0, 3.0)})
	_legs.append({"to": door + Vector2(8.0, 5.5)})
	_legs.append({"to": door + Vector2(-2.0, 8.5), "run": true})
	_legs.append({"to": door + Vector2(-10.0, 8.5)})
	_legs.append({"to": door + Vector2(-1.0, 2.0)})
	_legs.append({"to": door + Vector2(0, -2.0)})
	_legs.append({"wait": 3.0})


func _hands(dt: float) -> void:
	if _legs.is_empty():
		_make_legs()
	if engage(dt, 9.0):
		walk_keys(Vector2.ZERO, false)    # (one of the dead is at her: she stops and deals with it, then the walk goes on)
		_path = []
		return
	if _leg >= _legs.size():
		walk_keys(Vector2.ZERO, false)
		return
	var leg: Dictionary = _legs[_leg]
	if leg.has("wait"):
		walk_keys(Vector2.ZERO, false)
		_wait_t += dt
		if _wait_t >= float(leg.wait):
			_leg += 1
		return
	_leg_t += dt
	var d := walk_toward(Vector2(leg.to), 0.7)
	if d == Vector2.ZERO or _leg_t > 14.0:
		print("CAPTURE leg %d done at frame %d (%.1f s)" % [_leg, frame, _leg_t])
		_leg += 1
		_leg_t = 0.0
		_path = []
		return
	walk_keys(d, bool(leg.get("run", false)))
