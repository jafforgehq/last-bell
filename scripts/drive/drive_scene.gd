## The live drive (round 21, V21.1): a trip the player leads is a drive, a place, a drive. This is the scene of it: a SUBCLASS of the
## place's scene (scripts/raid/raid_scene.gd, which nobody edits this round), so that the road is "a place with a car": `phase` stays
## "place" for the whole trip and every gate, the hands, the camera, the HUD, the call card and the News, the alarm, the sounds and
## the colony stepping (`flow.leg_step`, one colony step in three scene steps at the pace of the leg: place_flow.gd) are the base's.
## What it overrides is the list of `drive_scene` below and nothing else but a few small views (`hint_line`, `status_of`).
##
##   leg     "there" | "place" | "home": the stage on screen. A leg is a ROAD (scripts/drive/road_gen.gd makes it: one strip 30 wide, the
##           same ground both ways) with the events its plan (scripts/drive/road_events.gd) puts on it; the place is the place's own
##           site, played by the base's own code (every override falls through to it).
##   mode    "drive" (all aboard, pinned to the car by the windows), "stopped" (a card is open, the car stands), "out" (the squad is out
##           working a stop: `work_left` seconds), "foot" (no car: a foot trip, a wrecked car).
##
## THE CAR is a CarSim (scripts/drive/car_sim.gd: arcade physics, a fixed step of 1/30) that the scene steps with the player's W S A D (or
## the Autopilot's: Tab) over this stage's own grid (`_probe`); a CarNode (car_node.gd) draws it. The aboard people are pinned to
## their seats by `run.sim.squad_goal` returning their own spot (no path search for them, ever) and shoot out of the windows what
## the base's own `_find_target` sees, but not above FIRE_SLOW tiles a second (a speeding car is not a rifle range); the player's
## own fire from the driver's window spreads x1.6 while the car moves. The dead are held outside the body (people aboard cannot be
## bitten): above RUN_OVER_SPEED they are run over, below FIRE_SLOW they claw the car.
##
## THE EVENTS are the plan's entries (kind "dead", "stop", "block", "forced"): the dead are spawned ahead of the car as it comes, a
## stop shows its figure from the start and its card opens on E (`press_stop`), a roadblock's wrecks are solid in the grid until
## the car rams them (they slide aside) or the squad clears them, a forced one (the puncture) cuts the throttle. A card nobody
## answers takes its auto option after `ttl_s`; nothing pauses for a card, the base least of all.
##
## THE STAGES. `_swap_stage` frees the world, the run and the pawns and builds the next from a site (a one-frame card hides the hitch);
## `_end_leg` hands the leg's result to the flow (`flow.end_leg(leg_result())`) and goes on to the place, the home road or the report.
extends "res://scripts/raid/raid_scene.gd"

const CarNode := preload("res://scripts/drive/car_node.gd")
const AvatarRules := preload("res://scripts/sim/avatar.gd")

## The modules the scene drives, loaded when needed (a test puts a stand-in in `stand_ins` first).
const PATHS := {
	"road_gen": "res://scripts/drive/road_gen.gd",
	"road_events": "res://scripts/drive/road_events.gd",
	"car_sim": "res://scripts/drive/car_sim.gd",
	"autopilot": "res://scripts/drive/autopilot.gd",
	"drive_hud": "res://scripts/drive/drive_hud.gd",
}
static var stand_ins := {}

## Where the dead of an event are spawned: this far ahead of the car (tiles) when it comes to them; and how far the streets' own
## dead are kept awake round the car (ahead, behind) and dropped behind it.
const SPAWN_AHEAD := 40.0
const AWAKE_AHEAD := 60.0
const AWAKE_BEHIND := 28.0
const DROP_BEHIND := 46.0
## A stop shows its pill from this far (tiles) and opens its card within STOP_REACH of it (a roadblock's within BLOCK_REACH) at no
## more than STOP_SLOW tiles a second. One passed by this far is missed.
const STOP_SEEN := 40.0
const STOP_REACH := 14.0
const BLOCK_REACH := 25.0
const STOP_SLOW := 3.0
const MISSED_BEHIND := 8.0
## How near the car the squad must be to board (tiles), how long a card waits for an answer (seconds, the def's `ttl_s` overrides),
## how long a car may stand with nothing the matter before the squad pushes it clear.
const BOARD_R := 6.0
const CARD_TTL := 8.0
## The autopilot answers a card this soon (it is the squad's own driver: the safe option, at once enough to be seen).
const AUTO_ANSWER_S := 2.5
const STUCK_S := 20.0
## Passengers do not fire above this speed (tiles a second); the player's own fire is wider by this much while the car moves.
const FIRE_SLOW := 2.0
const MOVE_BLOOM := 0.6
## The camera leads the car by its heading times its speed times CAM_LEAD_SPEED, at most CAM_LEAD_MAX tiles; how many tiles tall the
## window shows in the car and on foot.
const CAM_LEAD_SPEED := 0.9
const CAM_LEAD_MAX := 9.0
const CAM_LEAD_BASE := 2.5
const CAR_VIEW_TILES := 36.0
const FOOT_VIEW_TILES := 24.0
## The night's headlights: how bright the beam is by the darkness of the sky (0 day to 1 black).
const BEAM_FROM_DARK := 0.18
## How often the streets' dead are woken and dropped (steps).
const STREAM_EVERY := 8
## Seats: a seat's place in the car's frame, from the front, two across (a sixth of the car's length from its nose for the first row).
const SEAT_ACROSS := 0.42
const SEAT_ROW := 0.95
## The word of a stage that the HUD and the staging read.
const LEG_WORDS := {"there": "Driving there", "place": "At the place", "home": "Driving home"}

var leg := ""
var mode := "drive"
var car = null
var car_node = null
var plan: Array = []
var road: Dictionary = {}
var autopilot := false
var work_left := 0.0
## The entry whose card is open ("" none), and the seconds it has left before its auto option is taken.
var open_uid := ""
var card_left := 0.0
## The road's own minutes (game, the abstract leg) and the real seconds it takes at cruise.
var road_min := 0.0
var leg_s := 0.0
## The place's own site (made when the leg there is over).
var place: Dictionary = {}
var vehicle_kind := ""
var vehicle_kind_data: Dictionary = {}
## A staged scene has no events (`--noevents`); a test sets it too.
var no_events := false
## The pill: the stop the E key would take (the entry), or {}.
var near_entry: Dictionary = {}
## The last stop or block the player met (what the HUD's ticks show): uids of the entries that are open, done or missed.
var met: Array = []

var _make_place_site: Callable
var _going: Array = []
var _ammo0 := 0.0
var _loot_mult := 1.0
var _survivor := false
var _trip_seed := 0
var _roster: Array = []
var _place_result: Dictionary = {}
var _forced: Array = []
var _throttle := 0.0
var _steer := 0.0
var _braking := false
var _prev := {}
var _dormant: Array = []
var _dyn_nodes := {}
var _dyn_tile := {}
var _dyn_ram := {}
var _wounds := {}
var _clearing: Array = []
var _work_total := 1.0
var _steer_now := 0.0
var _ground_names := {}
var _figures := {}
var _brute_hit := {}
var _leg_clock := 0.0
var _leg_steps := 0
var _progress := 0.0
var _stuck_t := 0.0
var _stopping_for := ""
var _coasting := ""
var _stream_t := 0
var _car_hp_start := 0.0
var _event_wear := 0.0
var _wrecked := false
var _hp_seen := 0.0
var _dust_t := 0.0
var _scrape_t := 0.0
var _out_spots := {}
var _hitch_layer: CanvasLayer
var _hitch_label: Label
var _pending: Callable
var _probe_c := Callable()
var _orig_goal := Callable()
var _backdrop: Sprite2D
var _skids: Node2D
var _beam_dark := 0.0
var _started := false


## The module `name` (see PATHS): a stand-in a test put in, else the script, or null while it is not there.
static func module(name: String):
	if stand_ins.has(name):
		return stand_ins[name]
	var path := String(PATHS.get(name, ""))
	return load(path) if path != "" and ResourceLoader.exists(path) else null


# ---------------------------------------------------------------------- the trip --

## Plans the events, makes the road, and builds the scene on it (`setup` of the place's scene, on the ROAD site): `the_flow` is the trip's
## (place_flow.gd, begun), `the_place` the town's place, `make_place_site.call(squad_size, by_vehicle)` makes the place's own site when
## the leg there is over (the place is made after the road: the squad is as the road left it), `going` the people who go (the avatar
## first), `ammo` what they may shoot, `vehicle_kind_id` the id of the kind they drive ("" on foot), `loot_mult` and `survivor` the place's.
func setup_trip(game, game_hud, base_data: Dictionary, the_flow, the_place: Dictionary, the_maker: Callable, going: Array, ammo: float, vehicle_kind_id: String, loot_mult: float, survivor: bool) -> void:
	flow = the_flow
	place = the_place
	_make_place_site = the_maker
	_going = going.duplicate()
	_ammo0 = ammo
	_loot_mult = loot_mult
	_survivor = survivor
	vehicle_kind = vehicle_kind_id
	no_events = no_events or PlaceFlow.no_events
	main = game
	var cs = game.get("sim")
	vehicle_kind_data = cs.vehicles.kind(vehicle_kind_id) if cs != null and vehicle_kind_id != "" else {}
	_trip_seed = _seed_of(game, the_place, cs)
	leg = "there"
	var road_site := _make_road("there")
	# (the road's own run has no survivor to find and no loot to count)
	setup(game, game_hud, base_data, road_site, going, ammo, vehicle_kind_id, 1.0, false)
	_roster = run.squad.duplicate()
	_mount_parts()
	_install_stage()
	name = "DriveScene"


## The trip begins: the leg there is on (the flow counts it), the car stands on the start line with its nose north and the squad aboard,
## no overlay.
func begin_trip(the_flow) -> void:
	flow = the_flow
	if flow.has_method("begin_leg"):
		flow.begin_leg("there")
	leg = "there"
	_begin_leg_view()
	_started = true


## The seed the trip's road and plan are made from (a screenshot's `--drive=place,<seed>` is the site's, else the run's own).
func _seed_of(game, the_place: Dictionary, cs) -> int:
	var rs = game.get("raid_seed")
	if rs != null and int(rs) >= 0:
		return int(rs)
	if cs == null:
		return String(the_place.get("id", "")).hash()
	return int(cs.run_seed) * 1000003 + String(the_place.get("id", "")).hash() + int(cs.day) * 7919


## The HUD of the drive, the overlay of the drive and the card of the hitch replace the place's own (the place's are made by `setup`).
func _mount_parts() -> void:
	var hud_script = module("drive_hud")
	if hud_script != null and hud_script.can_instantiate():
		var old = hud_layer
		remove_child(old)
		old.queue_free()
		hud_layer = hud_script.new()
		hud_layer.layer = 4
		add_child(hud_layer)
		hud_layer.setup(hud, self)
	overlay_layer.remove_child(overlay)
	overlay.queue_free()
	overlay = DriveOverlay.new()
	overlay.scene = self
	overlay_layer.add_child(overlay)
	_hitch_layer = CanvasLayer.new()
	_hitch_layer.layer = 6
	_hitch_layer.visible = false
	add_child(_hitch_layer)
	var back := ColorRect.new()
	back.color = Color("#0b1411")
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hitch_layer.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hitch_label = Label.new()
	_hitch_label.add_theme_font_size_override("font_size", 30)
	_hitch_label.add_theme_color_override("font_color", Color("#eeeadd"))
	_hitch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitch_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hitch_layer.add_child(_hitch_label)
	_hitch_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ---------------------------------------------------------------------- making --

func _is_road() -> bool:
	return leg == "there" or leg == "home"


## Whether the car is alive and the party drives it now (a foot trip or a wrecked car is on foot).
func _by_vehicle() -> bool:
	if vehicle_kind == "" or vehicle_kind_data.is_empty() or _wrecked:
		return false
	if flow != null and flow.get("vehicle_alive") != null and not bool(flow.vehicle_alive):
		return false
	return true


func _kind_now() -> Dictionary:
	return vehicle_kind_data if _by_vehicle() else {}


func _vehicle_id() -> String:
	return String(flow.get("vehicle_id")) if flow != null and flow.get("vehicle_id") != null else ""


## The road's abstract minutes for the leg now: by the vehicle while it runs, on foot otherwise (the flow says; a bare scene asks the
## colony).
func _road_minutes_now() -> float:
	if flow != null and flow.has_method("leg_road_minutes"):
		return float(flow.leg_road_minutes())
	var cs = colony()
	if cs == null:
		return 60.0
	return float(cs.scavenge.road_minutes(String(place.get("id", "")), _vehicle_id() if _by_vehicle() else ""))


## The context the events' plan and cards are made from: the events' own (`RoadEvents.make_ctx`, from the flow), else a bare one.
func _plan_ctx(which: String) -> Dictionary:
	var events = module("road_events")
	if flow != null and events != null and events.has_method("make_ctx"):
		return events.make_ctx(flow, which)
	var cs = colony()
	return {"leg": which, "danger": int(place.get("danger", 1)), "by_vehicle": not _kind_now().is_empty(), "seats_free": 0, "road_min": road_min,
		"leg_s": leg_s, "hour": float(cs.hour) if cs != null else 12.0, "dusk": 19.0, "dawn": 6.0, "bed": false, "hp_share": 1.0}


## Plans the events of a leg and makes its road: the site of a road (road_gen.gd's shape), with `plan` and `road` set.
func _make_road(which: String, forced: Array = []) -> Dictionary:
	var kind := _kind_now()
	var cruise := PlaceFlow.cruise_of(kind)
	road_min = _road_minutes_now()
	leg_s = PlaceFlow.leg_seconds(road_min)
	var strip := PlaceFlow.strip_len(road_min, cruise)
	var ctx := _plan_ctx(which)
	var events = module("road_events")
	plan = []
	if not forced.is_empty():
		plan = forced.duplicate(true)
	elif events != null and not no_events:
		plan = events.plan(_trip_seed, ctx)
	var gen_ctx := ctx.duplicate()
	gen_ctx["kind"] = vehicle_kind if not kind.is_empty() else ""
	gen_ctx["cruise"] = cruise
	gen_ctx["len"] = strip
	gen_ctx["plan"] = plan
	var made: Dictionary = module("road_gen").make(place, _trip_seed, which, gen_ctx)
	road = made.get("road", {})
	return made


# ----------------------------------------------------------------------- stages --

## What a stage needs of the nodes and the state after its world, run and pawns are built (the base's `setup` lines, or `_swap_stage`'s).
func _install_stage() -> void:
	_dormant = []
	_dyn_nodes = {}
	_dyn_tile = {}
	_dyn_ram = {}
	_wounds = {}
	_clearing = []
	_figures = {}
	_brute_hit = {}
	_ground_names = {}
	_out_spots = {}
	_prev = {}
	_progress = 0.0
	_stuck_t = 0.0
	_stopping_for = ""
	_coasting = ""
	open_uid = ""
	card_left = 0.0
	near_entry = {}
	met = []
	work_left = 0.0
	_leg_clock = 0.0
	_leg_steps = 0
	_event_wear = 0.0
	_stream_t = 0
	car = null
	car_node = null
	_probe_c = Callable(self, "_probe")
	_orig_goal = run.sim.squad_goal
	run.sim.squad_goal = Callable(self, "_squad_goal")
	if not _is_road():
		return
	var types: Dictionary = site.data.get("terrainTypes", {})
	for tname in types:
		_ground_names[int(types[tname].id)] = String(tname)
	_add_backdrop()
	_add_trees()
	_add_dyn()
	_add_figures()
	_sleep_the_dead()
	run.sim.region_at(1.0, 1.0)    # (the dead's connected ground is worked out now, behind the card, not in the middle of a drive)
	var kind := _kind_now()
	mode = "foot"
	if not kind.is_empty():
		var sim_car = module("car_sim")
		car = sim_car.new()
		var hp := 100.0
		var cs = colony()
		if cs != null and _vehicle_id() != "":
			var v: Dictionary = cs.vehicles.vehicle(_vehicle_id())
			hp = float(v.get("hp", hp))
		car.setup(kind, Vector2(road.start), -PI / 2.0 if int(road.get("dir", -1)) < 0 else PI / 2.0, hp)
		_car_hp_start = hp
		_hp_seen = hp
		car_node = CarNode.new()
		car_node.name = "Car"
		if car_node.setup(vehicle_kind, kind):
			entities.add_child(car_node)
		else:
			car_node.free()
			car_node = null
		mode = "drive"
		_pose_car(true)
		# (the road's centre line and the autopilot's path are read once now, behind the card, not in the first step of the drive)
		_progress = maxf(_progress, _progress_now())
		var ap = module("autopilot")
		if ap != null:
			ap.drive(car, road, 0.0, {"probe": _probe_c})
	_skids = SkidNode.new()
	_skids.name = "Skids"
	_skids.z_index = 4
	world.add_child(_skids)
	_apply_ambient()
	_seat_everyone()


## Grass beyond the strip's edges, so that a window wider than the road is not a void.
func _add_backdrop() -> void:
	var types: Dictionary = site.data.get("terrainTypes", {})
	if not types.has("GRASS"):
		return
	var tex: Texture2D = GD.tex(String(types.GRASS.file))
	if tex == null:
		return
	_backdrop = Sprite2D.new()
	_backdrop.name = "Backdrop"
	_backdrop.texture = tex
	_backdrop.centered = false
	_backdrop.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_backdrop.region_enabled = true
	var pad := 60.0
	var span := Vector2(float(world.W) + 2.0 * pad, float(world.H) + 2.0 * pad)
	# (the atlas is four tiles of 128 pixels drawn at half size: a world tile is 128 of its pixels, and its pattern keeps its phase
	# at every fourth tile, which the backdrop's corner is)
	_backdrop.region_rect = Rect2(Vector2.ZERO, span * TILE / 0.5)
	_backdrop.scale = Vector2(0.5, 0.5)
	_backdrop.position = Vector2(-pad, -pad) * TILE
	_backdrop.z_index = -10
	root.add_child(_backdrop)


## The trees of the strip (the place's own scene does not draw its own: a road is lined with them).
func _add_trees() -> void:
	var trees: Array = site.data.get("trees", [])
	if trees.is_empty():
		return
	var box: Array = data.tree.box
	var dens := float(data.tree.density)
	for tr in trees:
		var tex: Texture2D = GD.tex(String(tr.file))
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.offset = Vector2(box[0], box[1]) * dens
		s.scale = Vector2.ONE * (TILE / dens)
		s.position = Vector2(tr.x, tr.y) * TILE
		entities.add_child(s)


## The roadblock's wrecks: a picture each (a body that can be knocked aside) and the tiles it shuts, listed by tile.
func _add_dyn() -> void:
	for d in road.get("dyn", []):
		for i in d.get("tiles", []):
			_dyn_tile[int(i)] = String(d.id)
		_dyn_ram[String(d.id)] = float(d.get("ram_hp", -1.0))
		var path := String(d.get("file", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = GD.tex(path)
		var s := Sprite2D.new()
		s.name = "Wreck_%s" % String(d.id)
		s.texture = tex
		var size: Vector2 = d.get("size", Vector2(2.2, 4.4))
		s.scale = Vector2(size.x * TILE / float(tex.get_width()), size.y * TILE / float(tex.get_height()))
		s.rotation = float(d.get("rot", 0.0))
		s.position = Vector2(d.pos) * TILE
		entities.add_child(s)
		_dyn_nodes[String(d.id)] = s


## The people at the verge: a stop's figures (a survivor, the checkpoint's guards) wait there from the start, drawn as people (the next
## recruit of the radio is the survivor: whoever you take in is who you saw).
func _add_figures() -> void:
	var cs = colony()
	if cs == null:
		return
	var k := 0
	for slot in road.get("slots", []):
		var e := _entry(String(slot.get("uid", "")))
		if e.is_empty() or String(e.kind) != "stop":
			continue
		var list: Array = slot.get("figures", [])
		if list.is_empty() and slot.get("figure", null) != null:
			list = [slot.figure]
		var made: Array = []
		for j in list.size():
			var def: Dictionary = {}
			if String(e.id) == "survivor" and j == 0:
				def = cs.recruits.current_caller()
			if def.is_empty():
				def = cs.recruits.make_def(40 + k)
			k += 1
			if def.is_empty():
				continue
			var p = run.sim.make_person(def.duplicate(true))
			var at: Vector2 = list[j]
			p.x = at.x
			p.y = at.y
			p.facing = "E" if at.x < float(world.W) / 2.0 else "W"
			p.hp = 100.0
			_add_person_pawn(p)
			made.append({"p": p, "go": null})
		if not made.is_empty():
			_figures[String(e.uid)] = made


## The dead of the strip lie down in a list of their own and are woken (made part of the run) as the car comes: the rules' own
## crowd pass (`_separate`) is a square of how many there are, and a strip holds hundreds.
func _sleep_the_dead() -> void:
	_dormant = run.sim.zombies.duplicate()
	run.sim.zombies.clear()


## The night road (road.ambient: headlights, more of the dead, a few runners among them).
func _apply_ambient() -> void:
	for a in road.get("ambient", []):
		var mult := float(a.get("dead_mult", 1.0))
		if mult <= 1.0 or _dormant.is_empty():
			continue
		var extra := roundi(float(_dormant.size()) * (mult - 1.0))
		var rng := RandomNumberGenerator.new()
		rng.seed = _trip_seed + 77
		for i in extra:
			var at := _road_point(rng.randf_range(0.18, 0.95), rng.randf_range(-6.0, 6.0))
			if at == Vector2.ZERO:
				continue
			var kind := "runner" if rng.randf() < float(a.get("runner_share", 0.0)) else "walker"
			var z = run.sim.spawn(at.x, at.y, "wander", kind)
			run.sim.zombies.erase(z)
			_dormant.append(z)
			if rng.randf() < 0.7:
				run._sleeping[z] = true


## A point of the road at `t` (0 the start, 1 the end) `across` tiles off its middle, open ground; Vector2.ZERO when there is none.
func _road_point(t: float, across: float) -> Vector2:
	var line: PackedVector2Array = road.get("centerline", PackedVector2Array())
	if line.size() < 2:
		return Vector2.ZERO
	var a := Vector2(road.start)
	var b := Vector2(road["end"])
	var y := lerpf(a.y, b.y, t)
	var best := line[0]
	var bd := INF
	for p in line:
		var d := absf(p.y - y)
		if d < bd:
			bd = d
			best = p
	for k in 6:
		var at := Vector2(best.x + across * (1.0 - float(k) * 0.15), y)
		if not world.is_solid(world.solid_z, at.x, at.y):
			return at
	return Vector2.ZERO


## Frees the stage's world, run and pawns (the HUD, the overlay and the camera of the scene stay).
func _teardown_stage() -> void:
	for n in pawn_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	pawn_nodes = {}
	if root != null and is_instance_valid(root):
		remove_child(root)
		root.queue_free()
	if camera != null and is_instance_valid(camera):
		remove_child(camera)
		camera.queue_free()
	vehicle_node = null
	car_node = null
	car = null
	run = null
	world = null
	fx = null
	entities = null
	corpses = null
	decals = null
	_backdrop = null
	_skids = null
	hover = null
	reach_container = {}
	reach_friend = null
	contact = {}
	marks = []
	_downed = {}
	_hunters = 0
	_heard = false
	_was_out = false
	fire_held = false


## The next stage from `next_site` and `members` (colony people, or the squad's own dicts `{"def", "hp", "skills", "trust"}`): the world, the
## run and the pawns are built as the base's `setup` does, then the camera, the tint and the HUD. `leg` is set by the caller.
func _swap_stage(next_site: Dictionary, members: Array, kind_id: String, lead_id: String = "") -> void:
	_teardown_stage()
	site = next_site
	has_survivor = _survivor and not _is_road()
	vehicle_kind = kind_id if kind_id != "" else vehicle_kind
	_build_world()
	var ammo := maxf(0.0, float(colony().stock.ammo)) if colony() != null else _ammo0
	var defs: Array = []
	for m in members:
		defs.append(m if m is Dictionary else RaidRun.squad_of([m])[0])
	var by_car := kind_id != "" and _is_road()
	run = RaidRun.new(site, world, fx, defs, ammo, kind_id, _loot_mult, has_survivor)
	run.sim.jobs.clear()
	run.sim.tactics.chores = false
	_bring_trust()
	var lead = run.person(lead_id) if lead_id != "" else null
	if lead == null or lead.dead or lead.downed:
		lead = _choose_leader()
	if lead != null:
		run.set_player(lead)
		_leader_id = String(lead.id)
	for p in run.squad:
		_add_person_pawn(p)
	if not _is_road() and kind_id != "" and Vector2(site.get("vehicle_spot", Vector2(-1, -1))).x >= 0.0:
		_add_vehicle(kind_id)
	for p in run.squad:
		for i in _roster.size():
			if String(_roster[i].id) == String(p.id):
				_roster[i] = p
	_mirror_colony()
	_install_stage()
	_frame_start()
	_zoom_for_mode()
	_clamp_camera()
	_apply_camera()
	camera.make_current()
	_update_tint()
	legend_t = RaidHud.LEGEND_HOLD
	ended = false
	_on_stage_hud()
	hud_layer.refresh()
	_sync_views(true)
	if by_car:
		_seat_everyone()


func _on_stage_hud() -> void:
	if hud_layer.has_method("on_stage"):
		hud_layer.on_stage(leg, site)
	else:
		# (the place's HUD has the cards of the squad it was built with: they are made again for this stage's)
		for c in hud_layer.cards:
			c.panel.queue_free()
		hud_layer.cards.clear()
		var i := 0
		for p in run.squad:
			hud_layer.cards.append(hud_layer._make_card(p, i))
			hud_layer.cards_grid.add_child(hud_layer.cards[i].panel)
			i += 1
		hud_layer.place_label.text = String(site.get("name", "The place"))


func _begin_leg_view() -> void:
	_frame_start()
	_zoom_for_mode()
	_clamp_camera()
	_apply_camera()
	autopilot = not _live() and car != null
	var sound = main.get("sound")
	if sound != null and car != null:
		sound.play("car_engine_start", 0.9, 0.0)
	var where := String(place.get("name", "the place"))
	where = "the " + where.trim_prefix("The ") if where.begins_with("The ") else where
	if leg == "home":
		clock_banner("Driving home" if car != null else "Walking home", "The same road, new dead")
	else:
		clock_banner(("Driving to %s" if car != null else "Walking to %s") % where, "Tab: let the squad drive")
	hud_layer.refresh()


func _zoom_for_mode() -> void:
	if not _is_road():
		return
	var tiles := CAR_VIEW_TILES if car != null and (mode == "drive" or mode == "stopped") else FOOT_VIEW_TILES
	zoom_px = clampf(_vp().y / tiles, 14.0, 52.0)
	if car != null:
		cam_center = Vector2(car.pos)


# --------------------------------------------------------------------- the queries --

func in_car() -> bool:
	return car != null and (mode == "drive" or mode == "stopped")


## The people pinned in the car now, the one you lead first.
func aboard() -> Array:
	if not in_car() or run == null:
		return []
	var out: Array = []
	var lead = leader()
	if lead != null and not lead.dead and not lead.downed:
		out.append(lead)
	for p in run.squad:
		if p != lead and not p.dead and not p.downed:
			out.append(p)
	return out


func _is_aboard(p) -> bool:
	return in_car() and not p.dead and not p.downed


## How far along the road the party is (0 to 1): the car's, or on foot the one you lead's by their row.
func road_progress() -> float:
	return _progress


func _progress_now() -> float:
	if not _is_road() or road.is_empty():
		return 0.0
	if car != null and mode != "foot":
		return clampf(float(car.progress(road)), 0.0, 1.0)
	var lead = leader()
	if lead == null:
		return _progress
	var a := Vector2(road.start)
	var b := Vector2(road["end"])
	if absf(b.y - a.y) < 0.01:
		return 1.0
	return clampf((lead.y - a.y) / (b.y - a.y), 0.0, 1.0)


func speed_now() -> float:
	if car != null and in_car():
		return absf(float(car.speed))
	var lead = leader()
	return AvatarRules.WALK_SPEED if lead != null and lead.moving else 0.0


func pace() -> float:
	return float(flow.leg_pace) if flow != null and flow.get("leg_pace") != null else 1.0


## Ahead of the clock (positive game minutes) or behind it now: the minutes the progress is worth less the minutes taken.
func ahead_min() -> float:
	if flow != null and flow.has_method("delta_min"):
		return float(flow.delta_min(_progress))
	return 0.0


## What the HUD of the drive reads (see drive_hud.gd): the open card, its options and seconds, the events' context, the road's minutes.
func open_event() -> Dictionary:
	return open_entry()


func event_options(uid: String) -> Array:
	return card_options() if uid == open_uid else []


func event_left(uid: String) -> float:
	return card_left if uid == open_uid else -1.0


func road_ctx() -> Dictionary:
	return event_ctx()


func road_minutes() -> float:
	return road_min


## The plan's entry with this uid, or {}.
func _entry(uid: String) -> Dictionary:
	for e in plan:
		if String(e.uid) == uid:
			return e
	return {}


func _slot_of(uid: String) -> Dictionary:
	for s in road.get("slots", []):
		if String(s.get("uid", "")) == uid:
			return s
	return {}


## How many tiles ahead of the party an entry is (negative once passed), along the road.
func _ahead_of(e: Dictionary) -> float:
	var slot := _slot_of(String(e.uid))
	var here := Vector2(car.pos) if car != null and mode != "foot" else _leader_at()
	var dir := float(road.get("dir", -1))
	if slot.is_empty():
		return (float(e.at) - _progress) * float(road.get("len", 100.0))
	return (float(slot.y) - here.y) * dir


func _leader_at() -> Vector2:
	var lead = leader()
	return Vector2(lead.x, lead.y) if lead != null else Vector2(road.get("start", Vector2.ZERO))


## The entry that is open (its card is up), or {}.
func open_entry() -> Dictionary:
	return _entry(open_uid) if open_uid != "" else {}


## What the events' options are asked with now: the plan's context, fresh (the stores and the seats change on the way).
func event_ctx() -> Dictionary:
	return _plan_ctx(leg if _is_road() else "there")


func _alive_party() -> Array:
	var out: Array = []
	if run == null:
		return out
	for p in run.squad:
		if not p.dead and not p.downed:
			out.append(p)
	return out


## The options of the open card (RoadEvents.options): [{"id", "label", "ok", "why", "auto"}], or [].
func card_options() -> Array:
	var e := open_entry()
	var events = module("road_events")
	if e.is_empty() or events == null:
		return []
	return events.options(e, event_ctx())


## The stop the E key would take: the nearest not yet met within STOP_SEEN ahead (on foot a roadblock has no card).
func _next_stop() -> Dictionary:
	var best := {}
	var best_d := INF
	for e in plan:
		if String(e.state) != "pending":
			continue
		var k := String(e.kind)
		if k != "stop" and not (k == "block" and _by_vehicle()):
			continue
		var d := _ahead_of(e)
		if d < -2.0 or d > STOP_SEEN:
			continue
		if d < best_d:
			best_d = d
			best = e
	return best


# ---------------------------------------------------------------------- the hands --

func _wasd_down() -> bool:
	return _key_down(KEY_W) or _key_down(KEY_A) or _key_down(KEY_S) or _key_down(KEY_D)


func _hands() -> void:
	if not _is_road() or not in_car():
		super()
		if _is_road() and car == null and work_left > 0.0 and leader() != null:
			leader().input_move = Vector2.ZERO    # (a stop worked on foot is worked standing)
		return
	var lead = leader()
	if lead == null:
		return
	var still := _held_still() or phase != "place"
	if _wasd_down() and autopilot and not still:
		autopilot = false
		hud_layer.toast("You have the wheel", "info")
	_throttle = float(int(_key_down(KEY_W)) - int(_key_down(KEY_S)))
	_steer = float(int(_key_down(KEY_D)) - int(_key_down(KEY_A)))
	if _live() and (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
		_throttle = 0.0
		_steer = 0.0
	var fire := fire_held
	if _live():
		if not _staged_aim:
			_mouse = get_viewport().get_mouse_position()
		if not _staged_fire:
			fire = fire and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _mouse.x < 0.0:
		aim_tile = Vector2(lead.x, lead.y) + Vector2.from_angle(float(car.heading)) * 4.0
	else:
		aim_tile = to_tile(_mouse)
	if still:
		_throttle = 0.0
		_steer = 0.0
		fire = false
	# (the player's trigger is from the window: wider while the car moves, the bloom the gun's own spread reads)
	if fire and speed_now() > FIRE_SLOW:
		lead.bloom = maxf(lead.bloom, MOVE_BLOOM + 1.5 * StepClock.STEP + 0.001)
	run.sim.avatar.set_input(Vector2.ZERO, aim_tile, fire)
	lead.moving = speed_now() > 0.2


func _held_still() -> bool:
	return super() or _pending.is_valid()


# ------------------------------------------------------------------------- keys --

func key_pressed(code: Key, shift: bool = false) -> void:
	if phase == "place" and not ended and _is_road():
		match code:
			KEY_TAB:
				toggle_autopilot()
				return
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				_press_card_key(int(code) - int(KEY_1))
				return
	super(code, shift)


## 1 2 3 ...: the options of an open card, as many as it has (a checkpoint's are four); the digit is the option's place on the card.
func _press_card_key(i: int) -> void:
	var opts := card_options()
	if i < 0 or i >= opts.size():
		return
	var r := choose(open_uid, String(opts[i].id))
	if not bool(r.get("ok", false)) and String(r.get("why", "")) != "":
		hud_layer.toast(String(r.why), "warn")


## E: the stop ahead, or back into the car; a friend who is down is got up as in a place.
func search_key() -> bool:
	if not _is_road():
		return super()
	if in_car():
		return bool(press_stop().get("ok", false))
	if car != null and not _wrecked and (mode == "out" or mode == "foot"):
		if work_left > 0.0:
			hud_layer.toast("They are still at it", "info")
			return false
		if _squad_near_car():
			return bool(press_stop().get("ok", false))
	if find_help_target() != null or car != null:
		return super()
	if not _next_stop().is_empty():
		return bool(press_stop().get("ok", false))
	return super()


func toggle_autopilot() -> void:
	if car == null or not in_car():
		hud_layer.toast("There is no car to hand over", "warn")
		return
	autopilot = not autopilot
	hud_layer.toast("The squad drives: any of W A S D takes the wheel back" if autopilot else "You have the wheel", "info")
	hud_layer.refresh()


## E: near an open stop and slow, its card opens; fast, the car brakes for it; after a stop with the squad near the car, back aboard.
func press_stop() -> Dictionary:
	if not _is_road() or ended:
		return {"ok": false, "what": "none"}
	if car != null and (mode == "out" or mode == "foot") and not _wrecked:
		if work_left > 0.0:
			hud_layer.toast("They are still at it", "info")
			return {"ok": false, "what": "working"}
		if _squad_near_car():
			_board()
			return {"ok": true, "what": "boarded"}
		hud_layer.toast("Get everyone back to the car first", "warn")
		return {"ok": false, "what": "far"}
	if mode == "stopped":
		return {"ok": false, "what": "open"}
	var e := _next_stop()
	if e.is_empty():
		hud_layer.toast("Nothing ahead to stop for", "info")
		return {"ok": false, "what": "none"}
	var reach := BLOCK_REACH if String(e.kind) == "block" else STOP_REACH
	if car == null:
		if _ahead_of(e) > reach:
			hud_layer.toast("Walk up to it first", "info")
			return {"ok": false, "what": "far"}
		_open_card(e)
		return {"ok": true, "what": "card", "uid": String(e.uid)}
	if speed_now() <= STOP_SLOW and _ahead_of(e) <= reach:
		_open_card(e)
		return {"ok": true, "what": "card", "uid": String(e.uid)}
	_stopping_for = String(e.uid)
	hud_layer.toast("Braking for it", "info")
	return {"ok": true, "what": "braking", "uid": String(e.uid)}


func _can_board_now() -> bool:
	return car != null and not _wrecked and (mode == "out" or mode == "foot") and work_left <= 0.0 and _squad_near_car()


func _squad_near_car() -> bool:
	if car == null:
		return false
	var at := Vector2(car.pos)
	for p in run.squad:
		if p.dead:
			continue
		if p.downed:
			continue
		if Vector2(p.x, p.y).distance_to(at) > BOARD_R:
			return false
	return true


# --------------------------------------------------------------------- the cards --

func _open_card(e: Dictionary) -> void:
	e["state"] = "open"
	open_uid = String(e.uid)
	var def: Dictionary = e.get("def", {})
	card_left = float(def.get("ttl_s", CARD_TTL))
	if autopilot:
		card_left = minf(card_left, AUTO_ANSWER_S)
	if car != null:
		mode = "stopped"
	_stopping_for = ""
	if not met.has(open_uid):
		met.append(open_uid)
	var sound = main.get("sound")
	if sound != null:
		sound.ui("ui_open", 0.7)
	hud_layer.refresh()


func _close_card() -> void:
	open_uid = ""
	card_left = 0.0
	if mode == "stopped":
		mode = "drive"


func _card_step(dt: float) -> void:
	if open_uid == "":
		return
	card_left -= dt
	if card_left > 0.0:
		return
	var e := open_entry()
	if e.is_empty():
		_close_card()
		return
	var def: Dictionary = e.get("def", {})
	# (a card that only closes leaves the stop where it was, E opens it again; the autopilot answers for the player all the same)
	if String(def.get("timeout", "auto")) == "close" and not autopilot:
		e["state"] = "pending"
		_close_card()
		return
	var auto := ""
	for o in card_options():
		if bool(o.get("auto", false)) and bool(o.get("ok", true)):
			auto = String(o.id)
			break
	if auto == "" and autopilot:
		auto = String(def.get("auto", ""))
	var r := choose(open_uid, auto) if auto != "" else {"ok": false}
	if not bool(r.get("ok", false)):
		# (the auto option itself was refused: the card is let go, nothing happens)
		e["state"] = "missed"
		_close_card()


## Takes an option of an entry: the events' own rules resolve it (`RoadEvents.resolve`) and apply it once (`apply`). A refused option
## says why and the card stays. A stop that takes time puts the squad out around the car.
func choose(uid: String, option_id: String) -> Dictionary:
	var e := _entry(uid)
	var events = module("road_events")
	if e.is_empty() or events == null or String(e.state) == "done":
		return {"ok": false, "why": "Nothing to choose"}
	var r: Dictionary = events.resolve(e, option_id, event_ctx())
	if not bool(r.get("ok", false)):
		return r
	var effects: Dictionary = r.get("effects", {})
	e["state"] = "done"
	if flow != null:
		events.apply(effects, flow)
	_feel(effects)
	var sp = r.get("spawn", {})
	if not (sp is Dictionary and not sp.is_empty()):
		sp = effects.get("dead", {})
	if sp is Dictionary and not sp.is_empty():
		_spawn_dead(sp, int(e.get("seed", 0)))
	if String(e.kind) == "block" or bool(effects.get("block_cleared", false)):
		_clear_block(uid)
	var log: Dictionary = r.get("log", {})
	var radio = colony_radio()
	if radio != null and not log.is_empty() and radio.has_method("log_news"):
		radio.log_news("road", String(log.get("text", "")), String(log.get("sub", "")))
	for l in r.get("lines", []):
		_log_line(String(l))
	var figs: Array = _figures.get(uid, [])
	if not figs.is_empty() and int(effects.get("survivor", 0)) > 0:
		figs[0]["go"] = Vector2(car.pos) if car != null else _leader_at()
	if _coasting == uid:
		_coasting = ""
	var stop_s := float(r.get("stop_s", 0.0))
	open_uid = ""
	card_left = 0.0
	if stop_s > 0.0 and car != null and not _wrecked:
		_go_out(stop_s)
	else:
		if stop_s > 0.0:
			work_left = stop_s
		if mode == "stopped":
			mode = "drive"
	hud_layer.refresh()
	return r


## What an event's effects do to the people and the car of the scene (the events' own `apply` did the stores, the fuel, the fleet's hp,
## the trust and the survivor through the flow; the run's people, their wounds and the car in the scene feel the rest, so that what the
## leg's result says is what happened). A knock is a negative number. `hurt` is a scratch or a bite for the one `effects.pick` points at
## among those on their feet; it is reported as that wound (the run's own `_bitten` is only for the bites of the dead).
func _feel(effects: Dictionary) -> void:
	var vhp := float(effects.get("vehicle_hp", 0.0))
	if car != null and vhp != 0.0:
		car.hp = clampf(float(car.hp) + vhp, 1.0, maxf(float(vehicle_kind_data.get("hp", 100.0)), float(car.hp)))
		if vhp < 0.0:
			_event_wear += -vhp
	var hit := float(effects.get("hp_all", 0.0))
	if hit != 0.0:
		for p in run.squad:
			if not p.dead and not p.downed:
				p.hp = clampf(p.hp + hit, 1.0, 100.0)
	var wound := String(effects.get("hurt", ""))
	var alive := _alive_party()
	if wound != "" and not alive.is_empty():
		var who = alive[int(effects.get("pick", 0)) % alive.size()]
		var id := String(who.id)
		_wounds[id] = "bite" if wound == "bite" or String(_wounds.get(id, "")) == "bite" else "scratch"


func _log_line(text: String) -> void:
	if text != "":
		run.log.append(text)


## The wrecks of a roadblock (the ones round its slot) that the squad's work takes off the road when it is done.
func _clear_block(uid: String) -> void:
	var slot := _slot_of(uid)
	for d in road.get("dyn", []):
		var mine := String(d.id).begins_with(uid + "_")
		if not mine and not slot.is_empty():
			mine = absf(Vector2(d.pos).y - float(slot.y)) < 9.0
		if mine and not _clearing.has(String(d.id)):
			_clearing.append(String(d.id))


## A wreck of the roadblock goes: its tiles are open ground (the grid and both path grids), its picture slides off to the side.
func _open_dyn(id: String, slide: bool, push: Vector2 = Vector2.ZERO) -> void:
	for d in road.get("dyn", []):
		if String(d.id) != id:
			continue
		var tiles: Array = []
		for i in d.get("tiles", []):
			tiles.append(int(i))
			_dyn_tile.erase(int(i))
		run.sim.block_tiles(tiles, false)
		var node = _dyn_nodes.get(id)
		if node != null and is_instance_valid(node):
			var to: Vector2 = node.position + (push if push != Vector2.ZERO else Vector2(0.0, 0.0)) * TILE
			if slide and is_inside_tree():
				var tw := create_tween()
				tw.tween_property(node, "position", to, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.parallel().tween_property(node, "rotation", node.rotation + (0.5 if push.x >= 0.0 else -0.5), 0.45)
			elif slide:
				node.position = to
			else:
				node.modulate.a = 0.0
		d["tiles"] = []


# -------------------------------------------------------------------- going out --

## The squad steps out round the car for `seconds`: it works (they stand at their spots and shoot what comes), then comes back.
func _go_out(seconds: float) -> void:
	if car == null:
		return
	mode = "out"
	work_left = seconds
	_out_spots = {}
	var people := _alive_party()
	var at := Vector2(car.pos)
	var dir := Vector2.from_angle(float(car.heading))
	var side := dir.rotated(PI / 2.0)
	var half_w := float(vehicle_kind_data.get("w", 2.2)) / 2.0 + 1.1
	var half_l := float(vehicle_kind_data.get("h", 4.4)) / 2.0
	_work_total = seconds
	var i := 0
	for p in people:
		var s := -1.0 if i % 2 == 0 else 1.0
		var f := (float(i / 2) - 0.5) * 1.6
		var spot := at + side * s * half_w + dir * f * (half_l * 0.5)
		if world.is_solid(world.solid_p, spot.x, spot.y):
			spot = at - side * s * half_w + dir * f * (half_l * 0.5)
		if world.is_solid(world.solid_p, spot.x, spot.y):
			spot = run.squad_ai._open_near(spot)
		_out_spots[String(p.id)] = spot
		p.x = spot.x
		p.y = spot.y
		p.path = []
		p.moving = false
		i += 1
	var lead = leader()
	if lead != null:
		clock_banner("Out of the car", "E: back in when they are done")
	_zoom_for_mode()


func _board() -> void:
	if car == null:
		return
	mode = "drive"
	work_left = 0.0
	_out_spots = {}
	_seat_everyone()
	_zoom_for_mode()
	hud_layer.refresh()


func _work_step(dt: float) -> void:
	if car == null and work_left > 0.0:
		work_left = maxf(0.0, work_left - dt)    # (on foot the stop is worked where they stand)
		return
	if mode != "out":
		return
	if work_left > 0.0:
		work_left = maxf(0.0, work_left - dt)
		if work_left <= 0.0:
			for id in _clearing:
				_open_dyn(String(id), true, Vector2(0.0, 0.0))
			_clearing = []
		return
	if _squad_near_car() and not _wrecked:
		_board()


## The place of everyone aboard in the car's frame, then in the world: the leader at the wheel.
func _seat_world(i: int) -> Vector2:
	var l := float(vehicle_kind_data.get("h", 4.4))
	var row := i / 2
	var col := i % 2
	var fwd := l * 0.22 - float(row) * SEAT_ROW
	var across := (-SEAT_ACROSS if col == 0 else SEAT_ACROSS)
	var dir := Vector2.from_angle(float(car.heading))
	return Vector2(car.pos) + dir * fwd + dir.rotated(PI / 2.0) * across


func _seat_everyone() -> void:
	if car == null or not in_car():
		return
	var i := 0
	for p in aboard():
		var at := _seat_world(i)
		p.x = at.x
		p.y = at.y
		p.path = []
		p.moving = false
		p.target = null
		i += 1


func _pin_aboard() -> void:
	if car == null or not in_car():
		return
	var i := 0
	var fast := speed_now() > FIRE_SLOW
	for p in aboard():
		var at := _seat_world(i)
		p.x = at.x
		p.y = at.y
		p.path = []
		p.moving = false
		if fast and not p.player:
			p.cooldown = maxf(p.cooldown, StepClock.STEP * 1.5)    # (not a rifle range: no shot until the car slows)
		elif fast:
			p.bloom = maxf(p.bloom, MOVE_BLOOM + 1.5 * StepClock.STEP + 0.001)    # (the player's own: wider from a moving car)
		i += 1


## What the rules' squad goal says of a person: the people in the car stay where they are (no path is ever searched for them), the ones
## out at a stop stand at their spots, the rest are the squad's own (follow, hold, cover) as on foot in a place.
func _squad_goal(p):
	if _is_road():
		if _is_aboard(p):
			return {"x": p.x, "y": p.y, "face": "", "what": "In the car"}
		if mode == "out" and _out_spots.has(String(p.id)) and not p.player and not p.downed and not p.dead:
			if run.squad_ai.active() and run.squad_ai.engaged(p):
				return {"x": p.x, "y": p.y, "face": "", "what": "Shooting"}
			var at: Vector2 = _out_spots[String(p.id)] if work_left > 0.0 else Vector2(car.pos)
			return {"x": at.x, "y": at.y, "face": "", "what": "Working" if work_left > 0.0 else "Back to the car"}
	if _orig_goal.is_valid():
		return _orig_goal.call(p)
	return null


# ------------------------------------------------------------------- the steps --

func _place_step() -> void:
	if not _is_road():
		super()
		return
	_drive_step()


func _drive_step() -> void:
	var dt := StepClock.STEP
	_leg_steps += 1
	_leg_clock += dt
	if car != null and in_car():
		_prev = {"pos": Vector2(car.pos), "heading": float(car.heading)}
		_car_step(dt)
	_car_vs_dead(dt)
	_pin_aboard()
	run.update(dt)
	sim_steps += 1
	_progress = maxf(_progress, _progress_now())
	_stream_dead()
	_events_step(dt)
	_card_step(dt)
	_work_step(dt)
	_stuck_check(dt)
	_effects_step(dt)
	if flow != null and flow.has_method("leg_step"):
		if flow.leg_step(run.sim) > 0:
			_colony_events()
	if car != null and car.wrecked and not _wrecked and mode != "foot":
		_wreck_car()
	if car != null and mode == "drive" and _progress >= 1.0 and not ended:
		_end_leg()


## The car's own step: the hands (or the autopilot's) and the forced events decide the throttle.
func _car_step(dt: float) -> void:
	var throttle := _throttle
	var steer := _steer
	if autopilot:
		var d := _pilot(dt)
		throttle = float(d.get("throttle", 0.0))
		steer = float(d.get("steer", 0.0))
	if mode == "stopped":
		throttle = _brake_to_zero()
		steer = 0.0
	elif _stopping_for != "":
		throttle = _brake_to_zero()
		if _wasd_down() and not autopilot:
			_stopping_for = ""
		elif absf(float(car.speed)) < 0.3:
			var e := _entry(_stopping_for)
			if not e.is_empty() and String(e.state) == "pending":
				_open_card(e)
			else:
				_stopping_for = ""
	elif _coasting != "":
		throttle = 0.0
		if absf(float(car.speed)) < 0.3:
			var f := _entry(_coasting)
			if not f.is_empty() and String(f.state) == "pending":
				_open_card(f)
	_braking = (throttle < 0.0 and float(car.speed) > 0.2) or mode == "stopped"
	_steer_now = steer
	var res: Dictionary = car.step(dt, throttle, steer, _probe_c)
	_after_car(res, dt)


func _brake_to_zero() -> float:
	var v := float(car.speed)
	if absf(v) < 0.3:
		return 0.0
	return -1.0 if v > 0.0 else 1.0


## What the step of the car did: sounds, sparks, the wrecks it knocked aside.
func _after_car(res: Dictionary, dt: float) -> void:
	var sound = main.get("sound")
	var hit := float(res.get("hit", 0.0))
	if hit > 0.0:
		if sound != null:
			sound.play("crash", clampf(hit / 9.0, 0.35, 1.0), 0.05)
		var front := Vector2(car.pos) + Vector2.from_angle(float(car.heading)) * float(vehicle_kind_data.get("h", 4.4)) * 0.5
		fx.hit_material(front.x, front.y, "metal")
		fx.smoke(front.x, front.y, 0.4, true)
	if bool(res.get("scrape", false)):
		_scrape_t -= dt
		if _scrape_t <= 0.0:
			_scrape_t = 0.4
			if sound != null:
				sound.play("scrape_metal", 0.5, 0.1)
	for id in res.get("ram", []):
		var push := Vector2.from_angle(float(car.heading)) * 2.4
		_open_dyn(String(id), true, push)
		if sound != null:
			sound.play("crash", 0.8, 0.05, 0.8)
	if bool(res.get("wrecked", false)):
		_wreck_car()


## The stage's grid, asked by the car: {"solid", "ground", "dyn"} for a point of the world (tiles); a wreck of the road says what it
## costs to ram it.
func _probe(at: Vector2) -> Dictionary:
	var tx := floori(at.x)
	var ty := floori(at.y)
	if tx < 0 or ty < 0 or tx >= world.W or ty >= world.H:
		return {"solid": true, "ground": "", "dyn": ""}
	var i: int = ty * int(world.W) + tx
	var id := String(_dyn_tile.get(i, ""))
	var out := {"solid": world.solid_p[i] != 0, "ground": String(_ground_names.get(int(world.terrain[i]), "ASPHALT")), "dyn": id}
	if id != "" and float(_dyn_ram.get(id, -1.0)) >= 0.0:
		out["ram_hp"] = float(_dyn_ram[id])
	return out


## What the autopilot is told (autopilot.gd: the probe, the dead near the road, whether to stand still, what to stop short of) and what
## it answers ({"throttle", "steer"}).
func _pilot(dt: float) -> Dictionary:
	var ap = module("autopilot")
	if ap == null:
		return {"throttle": 0.0, "steer": 0.0}
	var near: Array = []
	var here := Vector2(car.pos)
	for z in run.sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		if absf(z.y - here.y) < 24.0 and absf(z.x - here.x) < 12.0:
			near.append(Vector2(z.x, z.y))
	var halt := mode == "stopped" or _coasting != "" or open_uid != "" or _stopping_for != ""
	var aware := {"probe": _probe_c, "dead": near, "halt": halt}
	var e := _next_stop()
	if not e.is_empty() and String(e.kind) == "stop" and not halt:
		aware["stop_at"] = maxf(_ahead_of(e), 0.0)
	return ap.drive(car, road, dt, aware)


## The car is done: it stops, the squad steps out, the rest of the road is on foot.
func _wreck_car() -> void:
	if _wrecked:
		return
	_wrecked = true
	car.speed = 0.0
	if open_uid != "":
		_close_card()
	var was_aboard := aboard()
	mode = "foot"
	autopilot = false
	_stopping_for = ""
	_coasting = ""
	var at := Vector2(car.pos)
	var i := 0
	for p in was_aboard:
		var spot := at + Vector2.from_angle(float(car.heading) + PI / 2.0) * (1.9 if i % 2 == 0 else -1.9) + Vector2.from_angle(float(car.heading)) * float(i / 2) * 1.2
		if world.is_solid(world.solid_p, spot.x, spot.y):
			spot = run.squad_ai._open_near(spot)
		p.x = spot.x
		p.y = spot.y
		p.path = []
		i += 1
	var sound = main.get("sound")
	if sound != null:
		sound.play("crash", 1.0, 0.0, 0.7)
	clock_banner("The car is done", "Everyone out: the rest of the road is on foot")
	_zoom_for_mode()
	hud_layer.refresh()


# ----------------------------------------------------------------- dead and car --

## The dead against the car: one inside its body (grown by a little) is pushed out; above RUN_OVER_SPEED it is run over (a brute is not:
## it costs the car and its speed), below CLAW_BELOW the ones in contact claw it (the car's own rules: `run_over`, `claws`).
func _car_vs_dead(dt: float) -> void:
	if car == null or not in_car():
		return
	var sim = run.sim
	var heading := float(car.heading)
	var dir := Vector2.from_angle(heading)
	var side := dir.rotated(PI / 2.0)
	var hx := float(vehicle_kind_data.get("h", 4.4)) / 2.0 + 0.35
	var hy := float(vehicle_kind_data.get("w", 2.2)) / 2.0 + 0.35
	var at := Vector2(car.pos)
	var speed := absf(float(car.speed))
	var claws := 0
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var d := Vector2(z.x, z.y) - at
		var lx := d.dot(dir)
		var ly := d.dot(side)
		if absf(lx) > hx or absf(ly) > hy:
			continue
		if speed >= float(car.RUN_OVER_SPEED):
			if z.kind == "brute":
				if float(_brute_hit.get(z, -9.0)) < _leg_clock - 1.0:
					_brute_hit[z] = _leg_clock
					car.run_over(true)
					z.stagger = 0.6
					run.events.append({"type": "crash", "x": z.x, "y": z.y})
			else:
				car.run_over(false)
				sim._hurt_zombie(z, 99.0, heading, null)
				_push_out(z, lx, ly, hx, hy, dir, side, at)
			continue
		claws += 1
		_push_out(z, lx, ly, hx, hy, dir, side, at)
	if claws > 0:
		car.claws(claws, dt)
	if car.wrecked:
		_wreck_car()


func _push_out(z, lx: float, ly: float, hx: float, hy: float, dir: Vector2, side: Vector2, at: Vector2) -> void:
	var out_x := hx - absf(lx)
	var out_y := hy - absf(ly)
	var nx := lx
	var ny := ly
	if out_x < out_y:
		nx = (hx + 0.03) * (1.0 if lx >= 0.0 else -1.0)
	else:
		ny = (hy + 0.03) * (1.0 if ly >= 0.0 else -1.0)
	var to := at + dir * nx + side * ny
	if not world.is_solid(world.solid_z, to.x, to.y):
		z.x = to.x
		z.y = to.y


## The dead of the strip: woken (made part of the run) as the car comes to them, dropped when they are far behind it.
func _stream_dead() -> void:
	_stream_t += 1
	if _stream_t % STREAM_EVERY != 0:
		return
	var here := _leader_at() if car == null or mode == "foot" else Vector2(car.pos)
	var dir := float(road.get("dir", -1))
	var i := _dormant.size() - 1
	while i >= 0:
		var z = _dormant[i]
		var ahead: float = (z.y - here.y) * dir
		if ahead < AWAKE_AHEAD and ahead > -AWAKE_BEHIND:
			_dormant.remove_at(i)
			run.sim.zombies.append(z)
		i -= 1
	var kept: Array = []
	for z in run.sim.zombies:
		var behind: float = (here.y - z.y) * dir
		if behind > DROP_BEHIND and z.state != "dying":
			z.remove = true
			run._sleeping.erase(z)
		kept.append(z)
	run.sim.zombies = kept


## Dead of an event, spawned round `anchor` (or the party): `spec` is the events' own words ({walker, runner, brute: counts, where, state}).
func _spawn_dead(spec: Dictionary, seed_value: int, anchor = null) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 913
	var where := String(spec.get("where", "ahead"))
	var state := String(spec.get("state", "hunt"))
	var here := _leader_at() if car == null else Vector2(car.pos)
	var centre: Vector2 = Vector2(anchor) if anchor != null else here
	var dir := float(road.get("dir", -1))
	var made := 0
	var lead = leader()
	for k in ["walker", "runner", "brute"]:
		var count := int(spec.get(k, 0))
		for n in count:
			var at := Vector2.ZERO
			for tries in 12:
				var cand := centre
				match where:
					"around":
						cand = here + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 10.0)
					"verges":
						var side := -1.0 if rng.randf() < 0.5 else 1.0
						cand = Vector2(centre.x + side * rng.randf_range(5.0, 9.0), centre.y + rng.randf_range(-8.0, 8.0))
					_:
						cand = centre + Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-10.0, 10.0))
				if cand.x > 1.0 and cand.x < float(world.W) - 1.0 and cand.y > 1.0 and cand.y < float(world.H) - 1.0 and not world.is_solid(world.solid_z, cand.x, cand.y):
					at = cand
					break
			if at == Vector2.ZERO:
				continue
			var z = run.sim.spawn(at.x, at.y, "wander", k)
			if state == "hunt" and lead != null:
				z.state = "hunt"
				z.hunt_id = String(lead.id)
				z.repath = rng.randf() * 0.8    # (their first path searches are spread over the next moments, not all in one step)
			elif state == "still":
				run._sleeping[z] = true
			made += 1
	if dir == 0.0:
		return made
	return made


# --------------------------------------------------------------------- the events --

func _events_step(dt: float) -> void:
	near_entry = _next_stop()
	for e in plan:
		var st := String(e.state)
		if st == "done" or st == "missed":
			continue
		var d := _ahead_of(e)
		match String(e.kind):
			"dead":
				if st == "pending" and d <= SPAWN_AHEAD:
					e["state"] = "open"
					_trigger_dead(e)
				elif st == "open" and d < -4.0:
					e["state"] = "done"
			"stop", "block":
				if st == "pending" and d < -MISSED_BEHIND:
					# (on foot a roadblock is climbed: nothing was asked, nothing was missed)
					e["state"] = "done" if String(e.kind) == "block" and not _by_vehicle() else "missed"
					if not met.has(String(e.uid)):
						met.append(String(e.uid))
			"forced":
				if st == "pending" and _progress >= float(e.at) and _coasting != String(e.uid):
					_trigger_forced(e)
	# the autopilot does what a hand would: it stands at what is ahead and asks
	if autopilot and mode == "drive" and car != null and not near_entry.is_empty() and open_uid == "" and absf(float(car.speed)) < 0.3:
		var reach := BLOCK_REACH if String(near_entry.kind) == "block" else STOP_REACH
		if _ahead_of(near_entry) <= reach:
			_open_card(near_entry)


## An ambush or a herd: the dead are put on the road ahead (the events' own words: `resolve` with the entry's auto), a banner says so.
func _trigger_dead(e: Dictionary) -> void:
	var events = module("road_events")
	var def: Dictionary = e.get("def", {})
	var r: Dictionary = events.resolve(e, String(def.get("auto", "")), event_ctx()) if events != null else {}
	var sp = r.get("spawn", {})
	if not (sp is Dictionary and not sp.is_empty()):
		sp = r.get("effects", {}).get("dead", {})
	if sp is Dictionary and not sp.is_empty():
		var slot := _slot_of(String(e.uid))
		_spawn_dead(sp, int(e.get("seed", 0)), slot.get("spawn", null))
	if not met.has(String(e.uid)):
		met.append(String(e.uid))
	var log: Dictionary = r.get("log", {})
	var radio = colony_radio()
	if radio != null and not log.is_empty() and String(log.get("text", "")) != "" and radio.has_method("log_news"):
		radio.log_news("road", String(log.get("text", "")), String(log.get("sub", "")))
	_banner(String(def.get("title", "The dead ahead")), String(def.get("text", "")))


## The puncture: the throttle is cut and the car coasts; when it stands the card opens.
func _trigger_forced(e: Dictionary) -> void:
	if car == null:
		e["state"] = "missed"
		return
	_coasting = String(e.uid)
	_banner(String(e.get("def", {}).get("title", "A puncture")), String(e.get("def", {}).get("text", "")))
	if not met.has(String(e.uid)):
		met.append(String(e.uid))


## A car that has stood with nothing the matter is pushed back to its road.
func _stuck_check(dt: float) -> void:
	if car == null or mode != "drive" or absf(float(car.speed)) > 0.4 or _stopping_for != "" or _coasting != "":
		_stuck_t = 0.0
		return
	_stuck_t += dt
	if _stuck_t < STUCK_S:
		return
	# (a car that stands among the dead is not stuck: its people are at the windows, fighting)
	var here0 := Vector2(car.pos)
	for z in run.sim.zombies:
		if z.state != "dying" and z.state != "dead" and Vector2(z.x, z.y).distance_to(here0) < 10.0:
			_stuck_t = STUCK_S * 0.5
			return
	_stuck_t = 0.0
	var path: PackedVector2Array = road.get("path", PackedVector2Array())
	if path.size() < 2:
		return
	var here := Vector2(car.pos)
	var best := 0
	var bd := INF
	for i in path.size():
		var d := here.distance_to(path[i])
		if d < bd:
			bd = d
			best = i
	var to := path[mini(best + 3, path.size() - 1)]
	car.pos = to
	car.speed = 0.0
	car.heading = (path[mini(best + 4, path.size() - 1)] - to).angle()
	_prev = {}
	_seat_everyone()
	hud_layer.toast("The squad pushes the car back onto the road", "info")
	_log_line("The squad pushed the car clear.")


## Dust on the verge, smoke from a hurt engine, skid marks.
func _effects_step(dt: float) -> void:
	if car == null or fx == null:
		return
	var here := Vector2(car.pos)
	var dir := Vector2.from_angle(float(car.heading))
	var tail := here - dir * float(vehicle_kind_data.get("h", 4.4)) * 0.5
	var speed := absf(float(car.speed))
	_dust_t -= dt
	if _dust_t <= 0.0:
		_dust_t = 0.12
		var g := String(_probe(here).ground)
		if speed > 2.0 and (g == "GRASS" or g == "DIRT" or g == "SOIL") and mode != "foot":
			fx.smoke(tail.x, tail.y, 0.35, false)
		var share := clampf(float(car.hp) / maxf(float(vehicle_kind_data.get("hp", 100.0)), 1.0), 0.0, 1.0)
		if share < 0.3 and not _wrecked:
			fx.smoke(here.x + dir.x * 1.2, here.y + dir.y * 1.2, 0.4, true)
		elif _wrecked and randf() < 0.5:
			fx.smoke(here.x, here.y, 0.5, true)
	if _skids != null and mode == "drive" and speed > 3.0 and (_braking or absf(_steer) > 0.5 and speed > 5.0):
		_skids.add_marks(here, dir, float(vehicle_kind_data.get("w", 2.2)))


# ------------------------------------------------------------------------ the views --

func view_pos(e) -> Vector2:
	if _is_road() and car != null and in_car() and e == leader():
		var p := _car_pose()
		# (a little ahead even at rest: the HUD's boards cover the top of the window, the road ahead must show above the car)
		var lead := CAM_LEAD_BASE + clampf(speed_now() * CAM_LEAD_SPEED, 0.0, CAM_LEAD_MAX)
		return p.pos + Vector2.from_angle(p.heading) * lead * (1.0 if float(car.speed) >= -0.2 else 0.3)
	return super(e)


## The car as drawn this frame: between its last two steps by how far the clock is into the next.
func _car_pose() -> Dictionary:
	var pos := Vector2(car.pos)
	var heading := float(car.heading)
	if not _prev.is_empty() and mode != "foot":
		var a := step_clock.alpha()
		pos = Vector2(_prev.pos).lerp(pos, a)
		heading = lerp_angle(float(_prev.heading), heading, a)
	return {"pos": pos, "heading": heading}


func _pose_car(first: bool) -> void:
	if car_node == null or car == null:
		return
	var p := _car_pose()
	var share := clampf(float(car.hp) / maxf(float(vehicle_kind_data.get("hp", 100.0)), 1.0), 0.0, 1.0)
	var lights := 0.0
	var dark: float = light_now().dark
	if _has_headlights() or dark > 0.3:
		lights = clampf((dark - 0.12) * 2.2, 0.0, 1.0)
		if _has_headlights():
			lights = maxf(lights, 0.45)
	if _wrecked:
		lights = 0.0
	car_node.apply(p.pos, p.heading, _steer_now, _braking, share, lights)


func _has_headlights() -> bool:
	for a in road.get("ambient", []):
		if bool(a.get("headlights", false)):
			return true
	return false


func _sync_views(first: bool) -> void:
	super(first)
	if not _is_road():
		return
	for p in run.squad:
		var n = pawn_nodes.get(p)
		if n != null and _is_aboard(p):
			n.visible = false
	_pose_car(first)
	_sync_figures()


## The people at the verge: seen when they are in view; one who is taken in walks to the car and is gone.
func _sync_figures() -> void:
	if _figures.is_empty():
		return
	var view := view_rect().grow(3.0)
	var alpha := step_clock.alpha()
	for uid in _figures:
		for f in _figures[uid]:
			var p = f.p
			var n = pawn_nodes.get(p)
			if n == null:
				continue
			if f.go != null:
				var to: Vector2 = f.go
				var here := Vector2(p.x, p.y)
				if here.distance_to(to) < 1.2:
					n.visible = false
					f["go"] = null
					f["gone"] = true
					continue
				var step := to - here
				var d := minf(3.2 / 30.0, step.length())
				p.x += step.normalized().x * d
				p.y += step.normalized().y * d
				p.moving = true
				p.walk_phase += d * 3.4
				p.facing = run.sim.facing_of(step.x, step.y, p.facing)
			if bool(f.get("gone", false)):
				n.visible = false
				continue
			n.anim_t = clock
			n.visible = view.has_point(Vector2(p.x, p.y))
			if n.visible:
				n.sync(true, sim_steps, alpha)


func _check_way_out() -> void:
	# (a car is driven to the end of the road: `_end_leg` at its progress; on foot the base's own rule waits for everyone)
	if _is_road() and in_car():
		return
	super()


func hint_line() -> String:
	if not _is_road():
		return super()
	if _wrecked:
		return "The car is done. Walk to the end of the road."
	if mode == "out":
		return "Out of the car: E when they are done." if work_left <= 0.0 else "They are working (%d s). The dead come to the noise." % int(ceilf(work_left))
	if mode == "stopped":
		return "1 2 3 choose; the first option is taken in %d s." % int(ceilf(card_left))
	if mode == "foot":
		return "Walk to the end of the road."
	return "W S A D drive; E stop at what is ahead; Tab hands the wheel to the squad."


func status_of(p) -> String:
	if _is_road() and _is_aboard(p) and p != leader():
		return "Fighting" if p.target != null else "Aboard"
	if _is_road() and _is_aboard(p):
		return "Driving"
	return super(p)


# ------------------------------------------------------------------------ the legs --

## The leg is over: `flow.end_leg(leg_result())`, then the place (after the way there), the report (after the way home or when nobody is
## left or the base has fallen), the home road (after the place: `_on_place_over`).
func _end_leg() -> void:
	if ended:
		return
	ended = true
	fire_held = false
	_stopping_for = ""
	if run.sim.avatar != null and leader() != null:
		run.sim.avatar.set_input(Vector2.ZERO, aim_tile, false)
	var r := leg_result()
	if flow != null and flow.has_method("end_leg"):
		flow.end_leg(r)
	var base_fell: bool = colony() != null and String(colony().over) != ""
	if bool(r.get("failed", false)) or base_fell or leg == "home":
		_to_report()
		return
	_hitch("At %s" % String(place.get("name", "the place")), Callable(self, "_arrive_place").bind(r))


func leg_result() -> Dictionary:
	var played: Dictionary = run.result()
	var wear := maxf(0.0, _car_hp_start - float(car.hp) - _event_wear) if car != null else 0.0
	var hurt: Dictionary = (played.get("hurt", {}) as Dictionary).duplicate()
	for id in _wounds:
		hurt[id] = "bite" if String(_wounds[id]) == "bite" or String(hurt.get(id, "")) == "bite" else "scratch"
	var out := {"leg": leg, "hp": played.get("hp", {}), "lost": played.get("lost", []), "hurt": hurt,
		"ammo_used": float(played.get("ammo_used", 0.0)), "vehicle_hp_lost": wear, "wrecked": _wrecked,
		"failed": run.living().is_empty() or (played.get("lost", []) as Array).size() >= run.squad.size(), "progress": _progress}
	if played.has("leader"):
		out["leader"] = String(played.leader)
	return out


## One frame of a card over the window while the stage is built (the build is the one hitch of a leg).
func _hitch(words: String, then: Callable) -> void:
	_hitch_label.text = words
	_hitch_layer.visible = true
	_pending = then


func _begin_pending() -> void:
	if not _pending.is_valid():
		return
	var then := _pending
	_pending = Callable()
	then.call()
	_hitch_layer.visible = false


## The way there is done: the place is made now (the squad is as the road left it) and played from here.
func _arrive_place(r: Dictionary) -> void:
	var people: Array = flow.going if flow != null else _going
	var by_car := _by_vehicle()
	var squad_size := people.size()
	var place_site: Dictionary = _make_place_site.call(squad_size, by_car)
	leg = "place"
	mode = "foot"
	autopilot = false
	if flow != null and flow.has_method("arrive"):
		flow.arrive()
	_swap_stage(place_site, people, vehicle_kind if by_car else "", String(r.get("leader", "")))
	var where := String(place_site.get("name", "the place"))
	clock_banner("At %s" % where, "Get what you can and get out")


## The place is over (everyone alive is at the exit, or nobody can stand, or the base has fallen): on a road leg, the leg ends here; in the
## place, the hand-off: the road's findings join the place's result, the flow finishes it and the way home is the same road.
func _on_place_over() -> void:
	if _is_road():
		_end_leg()
		return
	ended = true
	fire_held = false
	hover = null
	reach_container = {}
	reach_friend = null
	_update_pointer()
	if run.sim.avatar != null and leader() != null:
		run.sim.avatar.set_input(Vector2.ZERO, aim_tile, false)
	_place_result = run.result()
	final_result = flow.merge_road(_place_result) if flow != null and flow.has_method("merge_road") else _place_result
	if flow != null:
		flow.finish(final_result)
	var coming := _coming_home()
	var base_fell: bool = colony() != null and String(colony().over) != ""
	if coming.is_empty() or base_fell:
		_to_report()
		return
	_hitch("Driving home" if _by_vehicle() else "Walking home", Callable(self, "_begin_home").bind(coming))


## Who comes home from the place (the ones not lost), with the health the place left them.
func _coming_home() -> Array:
	var out: Array = []
	var lost: Array = final_result.get("lost", [])
	var hp: Dictionary = final_result.get("hp", {})
	for cp in (flow.going if flow != null else _going):
		var id := String(cp.id)
		if lost.has(id) or cp.dead:
			continue
		var d: Dictionary = RaidRun.squad_of([cp])[0]
		if hp.has(id):
			d["hp"] = float(hp[id])
		out.append(d)
	return out


func _begin_home(members: Array) -> void:
	leg = "home"
	mode = "foot"
	var lead_id := String(final_result.get("leader", ""))
	if flow != null and flow.has_method("begin_leg"):
		flow.begin_leg("home")
	var home_site := _make_road("home")
	_swap_stage(home_site, members, vehicle_kind if _by_vehicle() else "", lead_id)
	_begin_leg_view()


## The trip is over: the report over the colony's view (the base's own `_come_home`), with the whole party on its cards.
func _to_report() -> void:
	ended = true
	if flow != null and flow.get("result") is Dictionary and not (flow.result as Dictionary).is_empty():
		final_result = flow.result
	elif final_result.is_empty():
		final_result = run.result()
	if not _roster.is_empty():
		run.squad = _roster.duplicate()
	_hitch_layer.visible = false
	_pending = Callable()
	_come_home()


func tick(delta: float) -> void:
	if _pending.is_valid() and not done:
		_begin_pending()
	super(delta)


# ----------------------------------------------------------------------- staging --

## The staging of a screenshot (main.gd's `--drive-do=`), steps joined by "+": at:<share> (the car put there), speed:<share of cruise>,
## event:<id>@<share> (the plan is that one event), hour:<h>, wait:<seconds>, aim:<x>:<y>, fire:<seconds>, autopilot, crash, stop, leg:home
## (skips the place), end (the leg's end), and the base's own `news`, `alarm`, `down`, `cam`, `pause`, `sel`, `ask`...
func stage(script: String) -> void:
	for step in script.split("+", false):
		var f := step.split(":")
		var head := String(f[0])
		match head:
			"at":
				_stage_at(float(f[1]) if f.size() > 1 else 0.0)
			"speed":
				if car != null:
					car.speed = float(car.cruise) * float(f[1]) if f.size() > 1 else float(car.cruise)
			"event":
				_stage_event(String(step.trim_prefix("event:")))
			"autopilot":
				autopilot = true
			"crash":
				if car != null and in_car():
					car.hp = 0.0
					_wreck_car()
			"stop":
				var e := _next_stop()
				if not e.is_empty():
					if car != null:
						car.speed = 0.0
					_open_card(e)
			"leg":
				if f.size() > 1 and String(f[1]) == "home":
					_stage_home()
			"end", "go", "road":
				_stage_end()
			"wait":
				for i in int(float(f[1]) * 30.0):
					tick(1.0 / 30.0)
			"choose":
				if open_uid != "" and f.size() > 1:
					choose(open_uid, String(f[1]))
			"hour":
				super.stage(step)
				if car != null:
					_pose_car(true)
			"noevents":
				no_events = true
			_:
				super.stage(step)
	_pose_car(true)
	hud_layer.refresh()
	overlay.queue_redraw()


## Puts the car at `share` of the road (the squad with it), at cruise.
func _stage_at(share: float) -> void:
	var a := Vector2(road.start)
	var b := Vector2(road["end"])
	var y := lerpf(a.y, b.y, clampf(share, 0.0, 1.0))
	var line: PackedVector2Array = road.get("path", PackedVector2Array())
	var at := Vector2(a.x, y)
	var best := INF
	var along := 0.0
	for i in line.size():
		var d := absf(line[i].y - y)
		if d < best:
			best = d
			at = line[i]
			along = (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]).angle()
	if car != null:
		car.pos = at
		car.heading = along
		car.speed = 0.0
		_prev = {}
		_seat_everyone()
		cam_center = at
	else:
		for p in run.squad:
			p.x = at.x
			p.y = at.y
			p.path = []
	_progress = _progress_now()
	_stream_dead()
	for i in 4:
		_stream_t = STREAM_EVERY - 1
		_stream_dead()
	_clamp_camera()
	_apply_camera()


## The plan is the one event `id@share` (the road is made again for it).
func _stage_event(spec: String) -> void:
	var f := spec.split("@")
	var id := String(f[0])
	var at := float(f[1]) if f.size() > 1 else 0.5
	var events = module("road_events")
	if events == null:
		return
	var deck: Dictionary = events.deck()
	if not deck.has(id):
		return
	var def: Dictionary = deck[id]
	var entry := {"uid": "e1", "id": id, "kind": String(def.kind), "at": at, "seed": _trip_seed, "night": false, "state": "pending", "def": def}
	_forced = [entry]
	var made := _make_road(leg, _forced)
	var members: Array = []
	for p in run.squad:
		members.append(RaidRun.squad_of([colony_person(String(p.id)) if colony_person(String(p.id)) != null else p])[0])
	_swap_stage(made, members, vehicle_kind if _by_vehicle() else "", _leader_id)
	_begin_leg_view()


func _stage_home() -> void:
	if leg != "there":
		return
	var r := leg_result()
	if flow != null and flow.has_method("end_leg"):
		flow.end_leg(r)
	var people: Array = flow.going if flow != null else _going
	var by_car := _by_vehicle()
	var place_site: Dictionary = _make_place_site.call(people.size(), by_car)
	leg = "place"
	if flow != null and flow.has_method("arrive"):
		flow.arrive()
	_swap_stage(place_site, people, vehicle_kind if by_car else "", String(r.get("leader", "")))
	_place_result = {"loot": {}, "hurt": {}, "lost": [], "hp": {}, "leader": _leader_id, "ammo_used": 0.0, "beats": []}
	final_result = flow.merge_road(_place_result) if flow != null and flow.has_method("merge_road") else _place_result
	if flow != null:
		flow.finish(final_result)
	_begin_home(_coming_home())


## Drives (or walks) the leg to its end: the autopilot takes the wheel.
func _stage_end() -> void:
	if not _is_road():
		return
	autopilot = car != null
	var guard := 0
	var start := leg
	while leg == start and not ended and guard < 60000:
		tick(1.0 / 30.0)
		guard += 1
	if _pending.is_valid():
		tick(1.0 / 30.0)


# ----------------------------------------------------------------------- the overlay --

## The overlay of the drive: the place's own in the place and on foot, its own over the road: the crosshair and the aim line from the
## window, the dead who hunt, the stops waiting at the verge, the ring of the squad's work.
class DriveOverlay:
	extends "res://scripts/raid/raid_overlay.gd"

	func _draw() -> void:
		if scene == null or scene.run == null or scene.phase != "place":
			return
		var by_car: bool = scene._is_road() and scene.in_car()
		if not by_car:
			super()
		else:
			_draw_car()
		if scene._is_road():
			_draw_road()

	func _draw_car() -> void:
		var run = scene.run
		var z: float = scene.zoom_px
		var vp := get_viewport_rect().size
		var screen := Rect2(Vector2(-60, -60), vp + Vector2(120, 120))
		var font := Fonts.cond(600)
		var lead = scene.leader()
		drawn_containers = 0
		drawn_names = 0
		drawn_hunters = 0
		drawn_crosshair = false
		drawn_aim_line = false
		drawn_reload_ring = false
		drawn_prompt = ""
		for zb in run.sim.zombies:
			if zb.state != "hunt":
				continue
			var head: Vector2 = scene.to_screen(scene.view_pos(zb) + Vector2(0.0, -1.15 * maxf(1.0, float(zb.size))))
			if not screen.has_point(head):
				continue
			drawn_hunters += 1
			draw_circle(head, 8.0, Color(DANGER, 0.92))
			draw_string(font, Vector2(head.x - 3.0, head.y + 5.0), "!", HORIZONTAL_ALIGNMENT_CENTER, 6.0, NAME_PX, Color("#fff4ee"))
		if lead != null:
			var roof: Rect2 = scene.car_node.rect() if scene.car_node != null else Rect2(Vector2(lead.x, lead.y), Vector2.ZERO)
			var at: Vector2 = scene.to_screen(Vector2(roof.get_center().x, roof.position.y - 0.7))
			if screen.has_point(at) and not lead.downed:
				_tag(at, "YOU", font, Color("#1a1508"), Color(ACCENT, 0.95))
			if lead.reloading > 0.0:
				var total := maxf(float(lead.gun.get("reload", 1.0)), 0.1)
				var k := clampf(1.0 - float(lead.reloading) / total, 0.0, 1.0)
				var rc: Vector2 = scene.to_screen(Vector2(lead.x, lead.y))
				draw_arc(rc, 0.9 * z, 0, TAU, 32, Color(PILL, 0.7), 4.0, true)
				draw_arc(rc, 0.9 * z, -PI / 2.0, -PI / 2.0 + k * TAU, 32, WARN, 3.0, true)
				drawn_reload_ring = true
		if lead != null and not lead.downed and scene.crosshair_shown():
			var shoulder: Vector2 = run.sim.avatar.shoulder(lead)
			var muzzle_at: Vector2 = run.sim.muzzle(lead, lead.aim)
			var shot: Dictionary = run.sim.avatar.trace(shoulder, lead.aim, float(run.sim.reach_of(lead.gun, lead)))
			aim_end = shot.end
			_dashed_line(scene.to_screen(muzzle_at), scene.to_screen(shot.end), Color(ACCENT, 0.4), 1.5)
			drawn_aim_line = true
		if scene.crosshair_shown() and not (lead != null and lead.downed):
			var m2: Vector2 = scene._mouse
			var bloom: float = float(lead.bloom) if lead != null else 0.0
			var ring := RING_MIN + minf(bloom, 2.0) * 10.0 + (3.0 if scene.speed_now() > 2.0 else 0.0)
			var cc := Color(ACCENT, 0.95)
			draw_arc(m2, ring, 0, TAU, 28, Color(0, 0, 0, 0.45), 3.0, true)
			draw_arc(m2, ring, 0, TAU, 28, cc, 1.5, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(m2 + d * (ring + CROSS_GAP - 4.0), m2 + d * (ring + CROSS_GAP + CROSS_ARM), Color(0, 0, 0, 0.45), 3.0, true)
				draw_line(m2 + d * (ring + CROSS_GAP - 4.0), m2 + d * (ring + CROSS_GAP + CROSS_ARM), cc, 1.5, true)
			draw_circle(m2, 1.6, cc)
			drawn_crosshair = true

	## What is the road's alone: the stop that is near (a ring where it waits), the ring of the work at the car.
	func _draw_road() -> void:
		var z: float = scene.zoom_px
		var font := Fonts.cond(600)
		var e: Dictionary = scene.near_entry
		if not e.is_empty() and scene.open_uid == "":
			var slot: Dictionary = scene._slot_of(String(e.uid))
			var anchor = slot.get("figure", slot.get("anchor", null))
			if anchor != null:
				var at: Vector2 = scene.to_screen(Vector2(anchor))
				_dashed_circle(at, clampf(0.8 * z, 12.0, 40.0), Color(ACCENT, 0.9), 2.0)
		if scene.mode == "out" and scene.car != null:
			var c: Vector2 = scene.to_screen(Vector2(scene.car.pos))
			var r := 3.0 * z
			draw_arc(c, r, 0, TAU, 40, Color(PILL, 0.8), 6.0, true)
			var total := maxf(1.0, scene.work_left + 0.001) if scene.work_left > 0.0 else 1.0
			var k: float = 1.0 if scene.work_left <= 0.0 else clampf(1.0 - scene.work_left / maxf(scene._work_total, 0.1), 0.0, 1.0)
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + k * TAU, 40, ACCENT if scene.work_left > 0.0 else OK, 4.0, true)
			var words := "%d s" % int(ceilf(scene.work_left)) if scene.work_left > 0.0 else "E  Back in the car"
			_tag(c + Vector2(0.0, r + 16.0), words, font, ACCENT if scene.work_left > 0.0 else INK)
			if total < 0.0:
				return


## The skid marks the car leaves: short dark strokes at its wheels, the last few dozen.
class SkidNode:
	extends Node2D

	const KEEP := 160
	var marks: Array = []

	func add_marks(at: Vector2, dir: Vector2, width: float) -> void:
		var side := dir.rotated(PI / 2.0) * (width * 0.4)
		var back := at - dir * 1.4
		marks.append([(back + side) * TILE, (back + side - dir * 0.6) * TILE])
		marks.append([(back - side) * TILE, (back - side - dir * 0.6) * TILE])
		while marks.size() > KEEP:
			marks.pop_front()
		queue_redraw()

	func _draw() -> void:
		for m in marks:
			draw_line(m[0], m[1], Color(0.05, 0.05, 0.05, 0.35), 3.0)
