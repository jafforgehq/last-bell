## A played trip, as a scene (round 14, R14.3; the one survivor and the radio, round 17, S1.6b). The player is one survivor
## and takes a squad of the people who agreed to come to a place: this is the place as a small map of its own, over the game,
## and the roads to it and from it. It builds the world of the site (scripts/raid/site_gen.gd makes it, scripts/raid/raid_run.gd
## and squad_ai.gd play it), the pawns of the squad and of the dead, a camera of its own, the hands of the avatar, the sounds,
## and (raid_hud.gd, raid_overlay.gd) the squad's cards, the radio, the clock of the base, the bags' tally, the log, the banners
## and the report. It is a modal view: the colony's world, pawns and HUD are hidden while it runs and put back exactly as they
## were when it ends (the yard's camera and zoom, the selection, the speed), and none of the colony's input reaches the raid
## (main.gd's `menu_open` counts a raid as a menu) or the other way about (every key is taken here first, but for the pause
## menu's, which has its own).
##
## THE FLOW (scripts/raid/place_flow.gd holds its rules; `main.open_raid` begins it and `begin_trip` hands it here): the road
## THERE ("Driving to the pharmacy...": a full-screen overlay while the colony runs ahead `road_minutes`), the PLACE (played
## by hand, the colony running behind it at one step in three: a second of the place is a minute of the day), the road HOME
## (the same overlay) and the REPORT over the colony's view (loot, who is hurt, who is lost, the news that came in). `phase` is
## "road_there", "place", "road_home" or "report". Without a flow (`setup` alone: the tests, a screenshot) the scene is only the
## place, the colony is held as it was, and the end card comes when the place is over.
##
## CONTROLS. WASD walk, the mouse aims, the left button held fires (not through the HUD), R reloads, F swings the melee, E
## searches the container in reach or gets a friend who is down up (E again stops), Space pauses (the place AND the base: nothing moves), the wheel zooms, the
## camera follows the one you lead, Esc is the game's menu. There is no selecting, no box, no right-click order, no panning: the
## squad is asked over the radio (the HUD's panel: `contact`, `ask`; the verbs of `radio_verbs.gd` through `squad_radio` and
## `base_radio`, which stand in for the radio they ask). When the one you lead falls the next of the squad leads (the camera
## glides, a banner says who; the base is told when the trip ends, and only if she is lost: see `_watch_leader`).
extends Node

signal finished(result: Dictionary)

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const FX := preload("res://scripts/render/fx.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const RecruitArt := preload("res://scripts/render/recruit_art.gd")
const DrawNode := preload("res://scripts/render/draw_node.gd")
const Lighting := preload("res://scripts/render/lighting.gd")
const StepClock := preload("res://scripts/sim/step_clock.gd")
const Radio := preload("res://scripts/sim/radio.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")
const RaidHud := preload("res://scripts/raid/raid_hud.gd")
const RaidOverlay := preload("res://scripts/raid/raid_overlay.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")

const TILE := GD.TILE
const MAX_ZOOM := 84.0
const VEHICLES_PATH := "res://assets/data/vehicles.json"
## The parts of the colony's view that are hidden while a raid runs (main.gd's names for them).
const HIDDEN := ["world", "overlay", "glow", "snow", "hints"]
## What of the colony's state the raid keeps and gives back (main.gd's names), and which of it may be null.
const COLONY_KEYS := ["cam_center", "zoom_px", "selection", "follow", "speed", "hover", "order_mark"]
const COLONY_NULLABLE := ["selection", "follow", "hover", "order_mark"]
## How near (tiles) the pointer must be to a container's prop (`at`) or to its spot (`pos`) to mean it.
const PICK_R := 0.95
## How far (tiles) from a container's spot the one you lead must be to search it with E (the run's own REACH), and how far
## from the pointer "search that" looks for one.
const E_REACH := RaidRun.REACH
const POINT_REACH := 3.0
## How close the one you lead must be to a friend who is down to get them up with E (the run's own reach for it).
const HELP_REACH := RaidRun.REACH + 0.6
## The banners are not repeated more often than this (real seconds).
const BANNER_GAP := 4.0
## The camera catches up with the one you lead at this rate (e-folds a second), and leans toward the pointer by this share of
## how far it is from the middle of the window, never by more than CAM_LEAD tiles (the yard's camera does the same).
const CAMERA_EASE := 8.0
const CAM_LEAD_K := 0.3
const CAM_LEAD := 2.0
## The place's light keeps this much of day in the darkest night (the colony's own lighting is darker: a place has to be playable).
const NIGHT_FLOOR := 0.24
## How the squad's stances read on a card.
const STANCE_WORDS := {"follow": "Following", "hold": "Holding", "cover": "Covering", "search": "Searching", "back": "Heading back"}

var main
var hud
var data: Dictionary
var site: Dictionary
var run
var world
var fx
var root: Node2D
var entities: Node2D
var corpses: Node2D
var decals: Node2D
var camera: Camera2D
var tint: CanvasModulate
var overlay
var overlay_layer: CanvasLayer
var hud_layer
var pawn_nodes := {}
var vehicle_node = null
var step_clock := StepClock.new()
var sim_steps := 0

var cam_center := Vector2(20, 14)
var zoom_px := 40.0
var paused := false
## The flow of the trip (place_flow.gd), or null: the scene is only the place.
var flow = null
## "road_there", "place", "road_home" or "report".
var phase := "place"
## The people of the colony who came (what `setup` was given): the squad's own are `run.squad`.
var party: Array = []
## Who is selected on the radio: {"kind": "squad" | "base", "p": the person} or {}.
var contact: Dictionary = {}
## What the pointer is over: {"kind": "container", "ref": container} or null.
var hover = null
## The hands: the keys held (code to true), the left button, and where the pointer was last seen (-1, -1: nowhere).
var held := {}
var fire_held := false
var _mouse := Vector2(-1.0, -1.0)
## A HUD control has the pointer now (no crosshair, the system's arrow): `_input` sees every pointer event first and says the
## HUD has it, `_unhandled_input` only the ones the HUD let through and says it has not.
var over_hud := false
## The point of the world (tiles) the avatar aims at now.
var aim_tile := Vector2.ZERO
## A test says so to have the scene read the real pointer and the real button as a windowed run does (a headless one cannot).
var live_for_tests := false
## A staged aim (`aim:x:y`) and trigger (`fire:s`) of a screenshot run: they stand until the player moves the pointer.
var _staged_aim := false
var _staged_fire := false
## The container in reach of E now ({} when none), and the friend who is down within reach of it (null when none), for the prompts.
var reach_container: Dictionary = {}
var reach_friend = null
## The marks the radio leaves (where someone was told to hold or to search): [{"x", "y", "t", "kind"}].
var marks: Array = []
## The place is over (the end card is up, or the road home is being driven) / everything is over and `finished` was sent.
var ended := false
var done := false
var final_result: Dictionary = {}
var clock := 0.0
var legend_t := 0.0
## What the colony looked like when the raid began (see `_hide_colony`).
var _saved := {}
var _speed_after := 0
var _hunters := 0
var _downed := {}
var _banner_t := -99.0
var _hud_t := 0.0
var _heard := false
var _leader_id := ""
## The one you lead has been outside the exit since the place began (the squad starts in it: leaving needs a way back to it).
var _was_out := false
var _tint_t := 0.0
var _sound_t := 0.0
var has_survivor := false
## The stand-ins for the radio that the verbs ask: the squad's (through the place) and the base's (at a distance).
var squad_radio
var base_radio


## Builds the place and the squad and takes the screen. `members_people` are the colony's people who go (their skills, weapon
## and health now), `ammo` what the colony lets them shoot, `vehicle_kind` the id of the vehicle they came in ("" on foot: a
## kind of assets/data/vehicles.json), `loot_mult` what the party's loot is multiplied by (a good leader, a lone scavenger),
## `has_survivor` whether someone is to be found in the place. The colony's avatar (if there is one among them, else the first)
## leads. This is the place only: `begin_trip` puts the roads and the colony's running round it.
func setup(game, game_hud, base_data: Dictionary, the_site: Dictionary, members_people: Array, ammo: float, vehicle_kind: String = "", loot_mult: float = 1.0, survivor: bool = false) -> void:
	main = game
	hud = game_hud
	data = base_data
	site = the_site
	has_survivor = survivor
	party = members_people.duplicate()
	name = "RaidScene"
	_hide_colony()
	_build_world()
	run = RaidRun.new(site, world, fx, RaidRun.squad_of(members_people), ammo, vehicle_kind, loot_mult, survivor)
	# the run's own Sim gives each person the colony job their def names (a seat in the yard); nobody here works one
	run.sim.jobs.clear()
	run.sim.tactics.chores = false
	_bring_trust()
	var lead = _choose_leader()
	if lead != null:
		run.set_player(lead)
		_leader_id = String(lead.id)
	for p in run.squad:
		_add_person_pawn(p)
	if vehicle_kind != "" and Vector2(site.get("vehicle_spot", Vector2(-1, -1))).x >= 0.0:
		_add_vehicle(vehicle_kind)
	squad_radio = SquadRadio.new(self)
	base_radio = BaseRadio.new(self)
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 2
	add_child(overlay_layer)
	overlay = RaidOverlay.new()
	overlay.scene = self
	overlay_layer.add_child(overlay)
	hud_layer = RaidHud.new()
	hud_layer.layer = 4
	add_child(hud_layer)
	hud_layer.setup(hud, self)
	_mirror_colony()
	_frame_start()
	_clamp_camera()
	_apply_camera()
	camera.make_current()
	legend_t = RaidHud.LEGEND_HOLD
	_update_tint()
	hud_layer.refresh()
	_sync_views(true)


## The trip's flow (place_flow.gd, begun: the party is away, the road there is set) round the place: the scene shows the road
## there first, then the place with the colony running behind it, the road home and the report.
func begin_trip(the_flow) -> void:
	flow = the_flow
	phase = "road_there"
	root.visible = false
	overlay_layer.visible = false
	hud_layer.show_road(road_title(), flow)
	hud_layer.refresh()


## "Driving to The pharmacy..." (or "Walking to ..." on foot, "Driving home..." on the way back).
func road_title() -> String:
	var place := String(site.get("name", "the place"))
	if place.begins_with("The "):
		place = "the " + place.trim_prefix("The ")
	var by_vehicle: bool = flow != null and String(flow.vehicle_id) != ""
	if phase == "road_home":
		return "Driving home..." if by_vehicle else "Walking home..."
	return ("Driving to %s..." if by_vehicle else "Walking to %s...") % place


# ------------------------------------------------------------ the colony --

## The colony's own Sim (the base), or null in a game that has none (a fake in a test).
func colony():
	return main.get("sim") if main != null else null


## Hides what the colony shows, remembering what was as it was. A part the game does not have (a fake in a test) is left
## alone. The colony's speed is not touched: the scene steps the colony itself (`_place_step`), the game's frames do not.
func _hide_colony() -> void:
	_saved = {"visible": {}}
	for key in COLONY_KEYS:
		var value = main.get(key)
		# (a list is kept as a copy: the colony's own frames go on and may change theirs)
		_saved[key] = value.duplicate() if value is Array else value
	for part in HIDDEN:
		var node = main.get(part)
		if node != null and is_instance_valid(node) and "visible" in node:
			_saved.visible[part] = node.visible
			node.visible = false
	_saved["hud"] = hud.visible
	hud.visible = false
	main.set("follow", null)
	main.set("hover", null)
	main.set("raid", self)


## Puts the colony back exactly as it was. `hold` keeps its rules waiting (the speed 0) until the report is dismissed.
func _restore_colony(hold: bool = false) -> void:
	if _saved.is_empty() or not is_instance_valid(main):
		return
	main.set("raid", null)
	for part in _saved.visible:
		var node = main.get(part)
		if node != null and is_instance_valid(node):
			node.visible = _saved.visible[part]
	if is_instance_valid(hud):
		hud.visible = bool(_saved.get("hud", true))
	for key in COLONY_KEYS:
		# (a part the game has not got reads as null and is left as it is, but for the ones that may be null themselves)
		if _saved[key] != null or key in COLONY_NULLABLE:
			main.set(key, _saved[key])
	if hold and main.get("speed") != null:
		_speed_after = int(_saved.get("speed", 0))
		main.set("speed", 0)
	# the report is up over the colony's view: it counts as a page (the storyteller's cards wait, the pointer is the arrow)
	main.set("trip_report", self if hold else null)
	var cam = main.get("camera")
	if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
		cam.make_current()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if _live():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_saved = {}


func _exit_tree() -> void:
	# freed without being sent home (the game was left, a test): the colony is put back all the same, no `finished`
	if not done:
		_restore_colony()
	if is_instance_valid(main) and main.get("trip_report") == self:
		main.set("trip_report", null)


## The colony's person with this id, or null.
func colony_person(id: String):
	var cs = colony()
	if cs == null:
		return null
	for p in cs.people:
		if String(p.id) == id:
			return p
	return null


## The squad's trust in the player is the colony's (the place's own radio asks it).
func _bring_trust() -> void:
	for p in run.squad:
		var c = colony_person(String(p.id))
		if c != null:
			p.trust = float(c.trust)


## Who leads in the place: the colony's avatar if they came, else the first of the squad (the old game has no avatar).
func _choose_leader():
	var cs = colony()
	if cs != null and String(cs.player_id) != "":
		var mine = run.person(String(cs.player_id))
		if mine != null:
			return mine
	return run.squad[0] if not run.squad.is_empty() else null


## The one you lead now (the run's own word), or null.
func leader():
	return run.avatar() if run != null else null


## The colony's Sim is given to the place's (the day, the hour, the dusk).
func _mirror_colony() -> void:
	var cs = colony()
	if cs != null and run != null:
		run.sim.mirror(cs)


# ----------------------------------------------------------------- build --

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 800)


func _build_world() -> void:
	root = Node2D.new()
	root.name = "RaidWorld"
	add_child(root)
	world = World.new()
	world.name = "World"
	root.add_child(world)
	world.build(site.data)
	# the light of the colony's hour (a place is dark at night too, but never so dark that it cannot be played)
	tint = CanvasModulate.new()
	tint.name = "Tint"
	root.add_child(tint)
	decals = Node2D.new()
	decals.name = "Decals"
	decals.z_index = 5
	world.add_child(decals)
	fx = FX.new()
	fx.setup(data, decals, _radial_texture())
	var ground_bits := DrawNode.new()
	ground_bits.name = "GroundBits"
	ground_bits.z_index = 5
	ground_bits.painter = fx.draw_ground_bits
	world.add_child(ground_bits)
	corpses = Node2D.new()
	corpses.name = "Corpses"
	corpses.z_index = 5
	world.add_child(corpses)
	entities = Node2D.new()
	entities.name = "Entities"
	entities.z_index = 6
	entities.y_sort_enabled = true
	world.add_child(entities)
	var air := DrawNode.new()
	air.name = "Air"
	air.z_index = 8
	air.painter = fx.draw_air
	world.add_child(air)
	# muzzle flashes, tracers, sparks: added to what is under them
	var glow := DrawNode.new()
	glow.name = "Glow"
	glow.z_index = 9
	glow.painter = fx.draw_add
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = mat
	world.add_child(glow)
	camera = Camera2D.new()
	camera.name = "RaidCamera"
	add_child(camera)


func _radial_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


## The colour the place is lit with now: the colony's sky at its hour (a campaign's seasons map the hour as the yard's do),
## lifted toward day so that the night is dim and blue but readable. `dark` (0 day, 1 black) is what the ambience follows.
func light_now() -> Dictionary:
	var cs = colony()
	var hour := 12.0 if cs == null else float(cs.hour)
	var sky_hour := hour
	if cs != null and cs.seasons != null and cs.seasons.campaign:
		sky_hour = cs.seasons.light_hour(hour)
	var sky: Color = Lighting.sky_at(sky_hour)
	var dark := 1.0 - (sky.r + sky.g + sky.b) / 3.0
	return {"color": sky.lerp(Color.WHITE, NIGHT_FLOOR * dark / 0.7), "dark": dark}


func _update_tint() -> void:
	tint.color = light_now().color


func _add_pawn(e, is_zombie: bool, key: String) -> void:
	var n := PawnNode.new()
	n.work_poses = false    # (a trip played by hand: the base's work words are not its rules')
	n.setup(e, is_zombie, data, key)
	entities.add_child(n)
	pawn_nodes[e] = n


## The node of a person of the squad: the six survivors have baked bodies, a recruit is drawn on the body most like their
## look (as main.gd's `_add_person_pawn` does).
func _add_person_pawn(p) -> void:
	if data.pawn.files.has(p.id):
		_add_pawn(p, false, p.id)
		return
	var base: String = RecruitArt.base_for(data, p.look)
	_add_pawn(p, false, base)
	var bodies: Dictionary = RecruitArt.bodies(data, p.look, base)
	for view in bodies:
		pawn_nodes[p].tex[view] = bodies[view]


## What a vehicle kind looks like ({"art", "w", "h"} of assets/data/vehicles.json), or {}.
static func vehicle_look(kind: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(VEHICLES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed.get("kinds", {}).get(kind, {})


## The vehicle the squad came in, parked at the site's `vehicle_spot` (its middle), sorted among the people by its foot.
func _add_vehicle(kind: String) -> void:
	var look := vehicle_look(kind)
	if look.is_empty():
		return
	var path := "res://assets/objects/%s.png" % String(look.art)
	if not ResourceLoader.exists(path):
		return
	var spot: Vector2 = site.vehicle_spot
	var w := float(look.w)
	var h := float(look.h)
	var s := Sprite2D.new()
	s.name = "Vehicle"
	s.texture = GD.tex(path)
	s.centered = false
	s.scale = Vector2(w * TILE / s.texture.get_width(), h * TILE / s.texture.get_height())
	s.offset = Vector2(-s.texture.get_width() / 2.0, -s.texture.get_height())
	s.position = Vector2(spot.x, spot.y + h / 2.0) * TILE
	entities.add_child(s)
	vehicle_node = s


# ---------------------------------------------------------------- camera --

func _min_zoom() -> float:
	var vp := _vp()
	return maxf(10.0, minf(vp.x / (float(world.W) + 2.0), vp.y / (float(world.H) + 2.0)))


func _clamp_camera() -> void:
	zoom_px = clampf(zoom_px, _min_zoom(), MAX_ZOOM)
	var vp := _vp()
	var hw := vp.x / 2.0 / zoom_px
	var hh := vp.y / 2.0 / zoom_px
	var m := 1.0
	var ww: float = world.W
	var wh: float = world.H
	# (the map's foot may come up above the HUD's boards at the foot of the window, so that the squad is never under them)
	var pad: float = hud_layer.foot_reserve() / zoom_px if hud_layer != null and phase == "place" else 0.0
	var pad_x: float = maxf(0.0, vp.x / 2.0 - hud_layer.right_limit()) / zoom_px if hud_layer != null and phase == "place" else 0.0
	cam_center.x = ww / 2.0 if hw * 2.0 >= ww + 2.0 * m else clampf(cam_center.x, hw - m, ww - hw + m + pad_x)
	cam_center.y = wh / 2.0 if hh * 2.0 >= wh + 2.0 * m else clampf(cam_center.y, hh - m, wh - hh + m + pad)


func _apply_camera() -> void:
	camera.position = cam_center * TILE
	camera.zoom = Vector2.ONE * (zoom_px / TILE)


func to_tile(screen: Vector2) -> Vector2:
	return cam_center + (screen - _vp() / 2.0) / zoom_px


func to_screen(tile: Vector2) -> Vector2:
	return (tile - cam_center) * zoom_px + _vp() / 2.0


func view_rect() -> Rect2:
	var vp := _vp()
	return Rect2(cam_center - vp / 2.0 / zoom_px, vp / zoom_px)


func zoom_at(factor: float, screen: Vector2) -> void:
	var before := to_tile(screen)
	zoom_px = clampf(zoom_px * factor, _min_zoom(), MAX_ZOOM)
	var after := to_tile(screen)
	cam_center += before - after
	_clamp_camera()


## The first view: the one you lead in the middle, at a size worth playing at.
func _frame_start() -> void:
	var lead = leader()
	zoom_px = clampf(minf(_vp().x / 30.0, _vp().y / 17.0), 28.0, 52.0)
	cam_center = Vector2(lead.x, lead.y) if lead != null else _squad_centre()


func _squad_centre() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for p in run.squad:
		if p.dead:
			continue
		sum += Vector2(p.x, p.y)
		n += 1
	if n == 0:
		return cam_center
	return sum / float(n)


# --------------------------------------------------------------- contacts --

func living_squad() -> Array:
	var out: Array = []
	for p in run.squad:
		if not p.dead:
			out.append(p)
	return out


## The people of the squad the player can ask over the radio: everyone but the one they lead, who has not been lost.
func squad_contacts() -> Array:
	var lead = leader()
	var out: Array = []
	for p in run.squad:
		if p != lead and not p.dead:
			out.append(p)
	return out


## The people at the base the player can ask: not lost, not turned, not away with the party (the base's own people).
func base_contacts() -> Array:
	var cs = colony()
	var out: Array = []
	if cs == null:
		return out
	for p in cs.people:
		if not p.dead and not p.turned and p.away == null and not p.player:
			out.append(p)
	return out


## Selects a contact on the radio: kind "squad" (a person of `run.squad`) or "base" (a person of the colony).
func select_contact(kind: String, p) -> void:
	contact = {"kind": kind, "p": p} if p != null else {}
	hud_layer.refresh()


func clear_contact() -> void:
	contact = {}
	hud_layer.refresh()


func is_selected(p) -> bool:
	return not contact.is_empty() and contact.p == p


## The stand-in for the radio that asks this kind of contact.
func radio_of(kind: String):
	return squad_radio if kind == "squad" else base_radio


## The colony's radio (the news, the calls, the alarm), or null.
func colony_radio():
	var cs = colony()
	return cs.radio if cs != null else null


# ----------------------------------------------------------------- asking --

## Asks the selected contact (or `who`, a person) for `verb` through the right radio: the squad's goes through the place
## (`RaidRun.request`), the base's through the colony's radio. Returns the radio's answer ({"ok", "line", "why", ...}).
func ask(verb: String, who = null, insist: bool = false) -> Dictionary:
	var kind := String(contact.get("kind", "squad"))
	var p = who if who != null else contact.get("p")
	if who != null:
		kind = "squad" if run.squad.has(who) else "base"
	if p == null:
		return {"ok": false, "line": "", "why": "Pick someone to ask", "delay_s": 0.0, "tone": "refused", "insisted": false}
	var args := {"insist": true} if insist else {}
	return radio_of(kind).request(p, verb, args)


## What a request to the squad needs that the player's hands know: "hold here" is where the leader stands, "search that" the
## container under the pointer (else the nearest in reach). Goes through the place's rules. Marks where it was told.
func squad_request(p, verb: String, args: Dictionary = {}) -> Dictionary:
	var a := args.duplicate()
	var lead = leader()
	var at_c := {}
	match verb:
		"hold":
			if not a.has("at") and lead != null:
				a["at"] = Vector2(lead.x, lead.y)
		"search":
			if not a.has("at"):
				at_c = search_target()
				if at_c.is_empty():
					return {"ok": false, "line": "", "why": "Aim at a shelf or a crate first", "delay_s": 0.0, "tone": "refused", "insisted": false, "hard": true}
				a["at"] = Vector2(at_c.pos)
	var r: Dictionary = run.request(p, verb, a)
	if bool(r.get("ok", false)):
		if verb == "hold" and a.has("at"):
			_mark("hold", Vector2(a.at))
		elif verb == "search" and a.has("at"):
			_mark("search", Vector2(a.at))
		elif verb == "back":
			_mark("exit", Vector2(site.exit.get_center()))
	return r


## The container "search that" means: the one under the pointer (not searched yet), else the nearest to the leader in reach,
## else the nearest to the pointer within a few tiles; {} when there is none.
func search_target() -> Dictionary:
	var c: Dictionary = run.container_at(aim_tile)
	if not c.is_empty() and not bool(c.get("looted", false)):
		return c
	var lead = leader()
	if lead != null:
		var near_lead: Array = run.containers_near(Vector2(lead.x, lead.y), E_REACH)
		if not near_lead.is_empty():
			return near_lead[0]
	var near_aim: Array = run.containers_near(aim_tile, POINT_REACH)
	if not near_aim.is_empty():
		return near_aim[0]
	return {}


## The alarm (the call to arms): raised if it is down, stood down if it is up. Returns whether it is up now.
func toggle_alarm() -> bool:
	var radio = colony_radio()
	if radio == null:
		return false
	var on: bool = not bool(radio.alarm_on)
	radio.alarm(on)
	hud_layer.toast("Alarm: everyone to the posts" if on else "Stood down: back to work", "warn" if on else "info")
	hud_layer.refresh()
	return on


func _mark(kind: String, at: Vector2) -> void:
	marks.append({"x": at.x, "y": at.y, "t": clock, "kind": kind})


func set_paused(on: bool) -> void:
	paused = on
	hud_layer.refresh()


# ---------------------------------------------------------------- picking --

## The container (of the run's own list, looted or not) whose prop or whose standing spot is near the point.
func pick_container(w: Vector2) -> Dictionary:
	return run.container_at(w)


## The container the leader would search with E now: the one under the pointer when it is in reach, else the nearest in reach.
func find_reach_container() -> Dictionary:
	var lead = leader()
	if lead == null or lead.downed or lead.dead:
		return {}
	var here := Vector2(lead.x, lead.y)
	var under: Dictionary = run.container_at(aim_tile)
	if not under.is_empty() and not bool(under.get("looted", false)) and here.distance_to(Vector2(under.pos)) <= E_REACH:
		return under
	var list: Array = run.containers_near(here, E_REACH)
	for c in list:
		if not bool(c.get("looted", false)):
			return c
	return {}


## The friend who is down nearest to the one you lead, within reach of getting them up (null when none).
func find_help_target():
	var lead = leader()
	if lead == null or lead.downed or lead.dead:
		return null
	var here := Vector2(lead.x, lead.y)
	var best = null
	var best_d := HELP_REACH
	for p in run.squad:
		if p == lead or p.dead or not p.downed:
			continue
		var d := here.distance_to(Vector2(p.x, p.y))
		if d <= best_d:
			best_d = d
			best = p
	return best


## E: gets a friend who is down up (they must be within reach), or starts searching the container in reach; E again stops what
## is going on. True if a search or a help is going on after it.
func search_key() -> bool:
	var lead = leader()
	if lead == null or phase != "place" or ended:
		return false
	if run.helping_of(lead) != null:
		run.stop_help(lead)
		hud_layer.toast("Stopped helping")
		return false
	if run.searching_of(lead) != "":
		run.stop_search(lead)
		hud_layer.toast("Stopped searching")
		return false
	var friend = find_help_target()
	if friend != null:
		if _hands_busy():
			hud_layer.toast("Stand still to help them up", "warn")
			return false
		if run.begin_help(lead, friend):
			return true
		hud_layer.toast("You can't help them now", "warn")
		return false
	var c := find_reach_container()
	if c.is_empty():
		hud_layer.toast("Nothing in reach to search: step up to a shelf or a crate", "warn")
		return false
	if _hands_busy():
		hud_layer.toast("Stand still to search", "warn")
		return false
	if run.begin_search(lead, String(c.id)):
		_mark("search", Vector2(c.at))
		return true
	hud_layer.toast("You can't search that now", "warn")
	return false


## Whether the hands are walking or firing (a search is not begun, and goes on only while they are still).
func _hands_busy() -> bool:
	return fire_held or _key_down(KEY_W) or _key_down(KEY_A) or _key_down(KEY_S) or _key_down(KEY_D)


## What a person is doing, for their card: Down, Lost, Reloading, Searching, Fighting, or what they were asked to do.
func status_of(p) -> String:
	if p.dead:
		return "Lost"
	if p.downed:
		return "Down"
	if p == leader():
		if run.searching_of(p) != "":
			return "Searching"
		return "Reloading" if p.reloading > 0.0 else "You"
	var friend = run.helping_of(p)
	if friend != null and friend.downed:
		return "Going to help" if p.moving or Vector2(p.x, p.y).distance_to(Vector2(friend.x, friend.y)) > RaidRun.REACH + 0.6 else "Helping"
	var searching: String = run.searching_of(p)
	if searching != "":
		var c: Dictionary = run.container(searching)
		if not c.is_empty() and not bool(c.looted):
			return "Going to search" if p.moving or Vector2(p.x, p.y).distance_to(Vector2(c.pos)) > RaidRun.REACH else "Searching"
	if p.reloading > 0.0:
		return "Reloading"
	if p.target != null:
		return "Fighting"
	return String(STANCE_WORDS.get(String(p.stance), "Walking" if p.moving else "Ready"))


## Whether a point (tiles) is in the exit (with the run's slack).
func in_exit(at: Vector2) -> bool:
	return Rect2(site.exit).grow(RaidRun.OUT_SLACK).has_point(at)


## The first names of those standing who are not in the exit while the one you lead is (they are waited for), else [].
func waiting_names() -> Array:
	var lead = leader()
	if lead == null or lead.downed or not _was_out or not in_exit(Vector2(lead.x, lead.y)):
		return []
	var out: Array = []
	for p in run.living():
		if not in_exit(Vector2(p.x, p.y)):
			out.append(String(p.first))
	return out


## The way out: the one you lead walks into the exit and everyone alive is in it (the squad follows them: "all back" calls the
## ones who are elsewhere), after the place has been left once (the squad begins in the exit). The place turns back
## (`RaidRun.retreat`, which has nobody to send: they are all there) and ends at the next step.
func _check_way_out() -> void:
	if ended or run.phase != "play":
		return
	var lead = leader()
	if lead == null or lead.downed or lead.dead:
		return
	if not in_exit(Vector2(lead.x, lead.y)):
		_was_out = true
		return
	if _was_out and waiting_names().is_empty():
		run.retreat()


## The short line under the place's name: what to do next.
func hint_line() -> String:
	if phase != "place":
		return ""
	var lead = leader()
	var down := ""
	for p in run.squad:
		if p.downed and not p.dead and p != lead:
			down = p.first
	var waiting := waiting_names()
	if not waiting.is_empty():
		return "Waiting for %s to reach the exit." % " and ".join(waiting)
	if down != "":
		return "%s is down. Stand beside them and press E to get them up, or they are lost." % down
	var left := 0
	for c in run.containers:
		if not bool(c.looted) and String(c.kind) != "survivor":
			left += 1
	if run.carried_total() >= run.capacity() and run.capacity() > 0:
		return "The bags are full. Walk everyone into the exit."
	if left == 0:
		return "Everything is searched. Walk everyone into the exit."
	if run.carried_total() == 0 and run.elapsed < 45.0:
		return "Step up to a shelf or a crate and press E to search it."
	return "%d place%s left to search. Everyone in the exit leaves." % [left, "" if left == 1 else "s"]


# ------------------------------------------------------------------ input --

## Every key belongs to the raid while it is up (the Town Board under it would take Esc, the yard its letters): but while the
## game's own menu is open (Esc opens it) the keys are the menu's.
func _input(ev: InputEvent) -> void:
	if done:
		return
	if ev is InputEventMouseMotion:
		_mouse = ev.position
		_staged_aim = false
		over_hud = true
		return
	if ev is InputEventMouseButton:
		_mouse = ev.position
		# the trigger is let go whenever the button is, wherever the pointer was (a release over a HUD control goes to the
		# control and never reaches `_unhandled_input`)
		if ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			fire_held = false
		return
	if not (ev is InputEventKey):
		return
	if _menu_up():
		held.clear()
		return
	get_viewport().set_input_as_handled()
	if not ev.pressed:
		held.erase(ev.keycode)
		return
	if ev.echo:
		return
	held[ev.keycode] = true
	key_pressed(ev.keycode, ev.shift_pressed)


## Whether the game's menu (the pause menu) is open over the raid.
func _menu_up() -> bool:
	var shell = main.get("shell") if main != null else null
	return shell != null and is_instance_valid(shell) and shell.is_open()


## A key, as the raid takes it (the tests press them through this).
func key_pressed(code: Key, _shift: bool = false) -> void:
	if phase == "report" or (ended and flow == null):
		if code == KEY_ENTER or code == KEY_KP_ENTER:
			go_home()
		return
	if phase != "place" or ended:
		return
	match code:
		KEY_SPACE:
			set_paused(not paused)
		KEY_ESCAPE:
			if main.has_method("open_pause"):
				main.open_pause()
		KEY_R:
			if not _held_still():
				run.sim.avatar.reload()
		KEY_F:
			if not _held_still():
				run.sim.avatar.melee()
		KEY_E:
			if not _held_still():
				search_key()
		KEY_T:
			hud_layer.toggle_news()


## A key let go (the tests, and `_input`).
func key_released(code: Key) -> void:
	held.erase(code)


func _unhandled_input(ev: InputEvent) -> void:
	if done:
		return
	if ev is InputEventMouseButton:
		mouse_button(ev)
	elif ev is InputEventMouseMotion:
		mouse_motion(ev)
	elif ev is InputEventMagnifyGesture:
		if phase == "place":
			zoom_at(ev.factor, ev.position)
	elif ev is InputEventPanGesture:
		if phase == "place":
			zoom_at(exp(-ev.delta.y * 0.06), ev.position)


func mouse_button(mb: InputEventMouseButton) -> void:
	if phase != "place" or ended:
		return
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				zoom_at(exp(0.2 * maxf(mb.factor, 0.2)), mb.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				zoom_at(exp(-0.2 * maxf(mb.factor, 0.2)), mb.position)
		MOUSE_BUTTON_LEFT:
			fire_held = mb.pressed
			_mouse = mb.position


func mouse_motion(mm: InputEventMouseMotion) -> void:
	_mouse = mm.position
	_staged_aim = false
	over_hud = false


## The hands, every frame: the walk, the aim and the trigger go to the avatar (they are nothing while the place is held, over, or
## not the screen).
func _hands() -> void:
	var lead = leader()
	if lead == null:
		return
	var still := _held_still() or phase != "place"
	var move := Vector2(int(_key_down(KEY_D)) - int(_key_down(KEY_A)), int(_key_down(KEY_S)) - int(_key_down(KEY_W)))
	# (Ctrl or Cmd with a letter is a command, not a step)
	if _live() and (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
		move = Vector2.ZERO
	var fire := fire_held
	if _live():
		# (a staged aim or trigger, a screenshot run's, is the hands' until the player's own pointer moves: the real pointer does not
		# override it, nor does the real button, which nobody is pressing)
		if not _staged_aim:
			_mouse = get_viewport().get_mouse_position()
		if not _staged_fire:
			fire = fire and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _mouse.x < 0.0:
		aim_tile = Vector2(lead.x, lead.y) + Vector2(1.0, 0.0)
	else:
		aim_tile = to_tile(_mouse)
	if still:
		move = Vector2.ZERO
		fire = false
	run.sim.avatar.set_input(move, aim_tile, fire)


## A key is down by what it says or by where it is (W A S D are the keys at the W A S D places on any layout); the events the
## scene has seen count too (a test presses keys that way).
func _key_down(code: Key) -> bool:
	if held.has(code):
		return true
	return _live() and (Input.is_physical_key_pressed(code) or Input.is_key_pressed(code))


## Whether there is a real window and pointer to ask (not a headless test).
func _live() -> bool:
	return is_inside_tree() and (live_for_tests or DisplayServer.get_name() != "headless")


## The pointer over the bare world is the crosshair that the overlay draws, not the system's arrow; over the HUD or off the
## window, or when the place is not the screen, it is the arrow as ever.
func _update_pointer() -> void:
	if not _live():
		return
	var want := Input.MOUSE_MODE_VISIBLE
	if phase == "place" and not ended and not _menu_up() and not over_hud and Rect2(Vector2.ZERO, _vp()).has_point(_mouse):
		want = Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != want:
		Input.mouse_mode = want


## Whether the overlay draws the crosshair now.
func crosshair_shown() -> bool:
	return phase == "place" and not ended and not paused and not _menu_up() and not over_hud and _mouse.x >= 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and _live():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_mouse = Vector2(-1.0, -1.0)
		_staged_aim = false
		if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			held.clear()
			fire_held = false


# ------------------------------------------------------------------- loop --

func _process(delta: float) -> void:
	tick(delta)


## Whether the rules of the place (and, with them, the base's) stand still: Space, the game's menu, or the place is over.
func _held_still() -> bool:
	return paused or ended or _menu_up()


## One frame of `delta` real seconds: the road runs the colony ahead, or the place takes whole steps of the rules' clock
## (the colony behind it) unless it is paused; then the view follows.
func tick(delta: float) -> void:
	if done:
		return
	var dt := clampf(delta, 0.0, StepClock.MAX_FRAME)
	clock += dt
	match phase:
		"road_there", "road_home":
			_tick_road(dt)
		"place":
			_tick_place(dt)
		"report":
			pass
	_hud_t -= dt
	if _hud_t <= 0.0:
		_hud_t = 0.1
		hud_layer.refresh()
	if phase == "place":
		overlay.queue_redraw()


func _tick_road(dt: float) -> void:
	var arrived: bool = flow.road_step(dt)
	_colony_events()
	hud_layer.update_road(flow)
	if arrived:
		if phase == "road_there":
			_arrive()
		else:
			_come_home()


func _tick_place(dt: float) -> void:
	legend_t = maxf(0.0, legend_t - dt)
	_hands()
	if not _held_still():
		for i in step_clock.advance(dt, 1.0):
			_place_step()
		fx.update(dt)
	elif run.finished():
		fx.update(dt)
	_handle_events()
	_watch_leader()
	_check_way_out()
	_sound_t -= dt
	if _sound_t <= 0.0:
		_sound_t = 0.25
		_ambience()
	_update_pointer()
	_tint_t -= dt
	if _tint_t <= 0.0:
		_tint_t = 0.1
		_update_tint()
	var lead = leader()
	if lead != null:
		var lean := Vector2.ZERO
		if _mouse.x >= 0.0:
			lean = (_mouse - _vp() / 2.0) / zoom_px * CAM_LEAD_K
			if lean.length() > CAM_LEAD:
				lean = lean.normalized() * CAM_LEAD
		var at: Vector2 = view_pos(lead)
		var goal: Vector2 = at + lean
		# (the squad is kept out from under the radio's column: in a narrow window it takes half the screen)
		var limit: float = hud_layer.right_limit()
		var seen_x: float = _vp().x / 2.0 + (at.x - goal.x) * zoom_px
		if seen_x > limit:
			goal.x += (seen_x - limit) / zoom_px
		cam_center += (goal - cam_center) * (1.0 - exp(-CAMERA_EASE * dt))
	_clamp_camera()
	_apply_camera()
	reach_container = find_reach_container() if not ended else {}
	reach_friend = find_help_target() if not ended else null
	hover = {"kind": "container", "ref": reach_container} if not reach_container.is_empty() else null
	marks = marks.filter(func(m): return clock - float(m.t) < 4.0)
	_sync_views(false)
	var base_over: bool = flow != null and String(colony().over) != ""
	if (run.finished() or base_over) and not ended:
		_on_place_over()


## One step of the place, and the colony's steps that are owed for it.
func _place_step() -> void:
	run.update(StepClock.STEP)    # (it ticks the place's radio too: the requests' delays and the stances are the run's)
	sim_steps += 1
	if flow != null:
		if flow.place_step(run.sim) > 0:
			_colony_events()


## The colony's events while the scene has the screen: its banners (the bell, a night, a dawn) are shown, the storyteller's
## cards wait for the game to come back, the rest is the yard's own sound and picture and is dropped.
func _colony_events() -> void:
	var cs = colony()
	if cs == null:
		return
	for e in cs.events:
		match String(e.get("type", "")):
			"banner":
				if phase == "place":
					hud_layer.show_banner(String(e.text), String(e.sub))
				else:
					hud_layer.road_note(String(e.text) + (": " + String(e.sub) if String(e.get("sub", "")) != "" else ""))
			"story_card":
				var su = main.get("story_ui")
				if su != null:
					su.on_story_card()
			"dawn_report":
				var su2 = main.get("story_ui")
				if su2 != null:
					su2.on_dawn_report()
			"bell":
				var sound = main.get("sound")
				if sound != null:
					sound.play("bell", 0.35, 0.0)
	cs.events.clear()


## The ambience and the music follow the place and the colony's hour.
func _ambience() -> void:
	var sound = main.get("sound")
	var music = main.get("music")
	var dark: float = float(light_now().dark)
	var near := 0
	for z in run.sim.zombies:
		if z.state == "hunt" and Vector2(z.x, z.y).distance_to(cam_center) < 30.0:
			near += 1
	var horde := minf(1.0, near / 14.0)
	if sound != null:
		sound.set_ambience(dark, horde, 0.25)
	if music != null:
		music.follow(true, true, dark, horde, 0.25)


func view_pos(e) -> Vector2:
	var n = pawn_nodes.get(e)
	return n.tile_pos() if n != null and n.visible else Vector2(e.x, e.y)


## Makes, moves and retires the nodes of the people and of the dead (as main.gd's `_sync_views` does for the yard).
func _sync_views(first: bool) -> void:
	var view := view_rect().grow(3.0)
	var frame := Engine.get_process_frames()
	var alpha := step_clock.alpha()
	var alive := {}
	var i := 0
	for z in run.sim.zombies:
		i += 1
		alive[z] = true
		var dead: bool = z.state == "dead" or z.state == "dying"
		if not pawn_nodes.has(z):
			_add_pawn(z, true, "z%d" % z.look_index)
		var n = pawn_nodes[z]
		if dead and n.get_parent() == entities:
			n.reparent(corpses)
		n.anim_t = clock
		n.visible = first or view.has_point(Vector2(z.x, z.y))
		if not n.visible:
			continue
		var redraw := true
		if z.state == "dead":
			redraw = z.dead_t < 0.2 or (z.dead_t > 55.0 and frame % 3 == 0)
		n.sync(redraw, sim_steps, alpha)
	for e in pawn_nodes.keys():
		if pawn_nodes[e].zombie and not alive.has(e):
			pawn_nodes[e].queue_free()
			pawn_nodes.erase(e)
	for p in run.squad:
		var n = pawn_nodes[p]
		n.anim_t = clock
		n.visible = first or view.has_point(Vector2(p.x, p.y))
		if n.visible:
			n.sync(true, sim_steps, alpha)
	# a friend who falls is a banner; the dead who wake are another
	var lead = leader()
	for p in run.squad:
		var was: bool = bool(_downed.get(p.id, false))
		if p.downed and not was and not p.dead and p != lead and String(p.id) != _leader_id:
			_banner("%s is down" % p.first, "Stand beside them and press E to get them up")
		_downed[p.id] = p.downed
	var hunting := 0
	for z in run.sim.zombies:
		if z.state == "hunt":
			hunting += 1
	if hunting > _hunters:
		if _heard:
			_banner("They heard that", "The dead nearby are coming")
		else:
			_banner("They saw you", "The dead nearby are coming")
	_hunters = hunting
	_heard = false


## One banner at a time, and not a flood of them.
func _banner(title: String, sub: String) -> void:
	if clock - _banner_t < BANNER_GAP:
		return
	_banner_t = clock
	hud_layer.show_banner(title, sub)


# ------------------------------------------------------------- succession --

## When the one you lead falls the run hands the lead to the next of the squad (its own rules: raid_run.gd); the scene notices, the
## camera glides there (it follows whoever leads), a banner says who leads. The BASE is not told now: the one who fell is only down
## (she may be got up and come home), and the loss, with its setback, is told when the trip ends and she is among the lost
## (`PlaceFlow.finish`, which also makes the last leader the base's player when she lived).
func _watch_leader() -> void:
	var lead = leader()
	var id := String(lead.id) if lead != null else ""
	if id == _leader_id:
		return
	var from := _leader_id
	_leader_id = id
	if from == "":
		return
	var old = run.person(from)
	if lead != null:
		if contact.get("p") == lead:
			contact = {}
		clock_banner("%s leads now" % lead.first, "%s is down" % (old.first if old != null else "Your leader"))
		hud_layer.refresh()


## A banner that is shown at once (a succession must not wait for the gap).
func clock_banner(title: String, sub: String) -> void:
	_banner_t = clock
	hud_layer.show_banner(title, sub)


# ----------------------------------------------------------------- events --

func _vol_at(x: float, y: float) -> float:
	return clampf(1.0 - Vector2(x, y).distance_to(cam_center) / 50.0, 0.12, 1.0)


## The run's events, as sounds (the same ones the yard plays); then the list is emptied.
func _handle_events() -> void:
	var sound = main.get("sound")
	for e in run.events:
		var t := String(e.get("type", ""))
		if t == "shot":
			_heard = true
		if sound == null:
			continue
		match t:
			"shot":
				sound.play("shot_%s" % e.weapon, _vol_at(e.x, e.y) * 0.8)
			"groan":
				if randf() < 0.6:
					var d := Vector2(e.x, e.y).distance_to(cam_center)
					var kind: String = String(e.get("kind", "walker"))
					var pitch := 0.72 if kind == "brute" else (1.3 if kind == "runner" else 1.0)
					var loud := 1.3 if kind == "brute" else 1.0
					sound.play("groan", minf(1.0, 10.0 / (d + 12.0) / 0.3) * loud, 0.12, pitch)
			"claw":
				if randf() < 0.35:
					sound.play("scrape_%s" % e.material, _vol_at(e.x, e.y))
			"crash":
				sound.play("crash")
			"bite":
				sound.play("bite")
			"reload":
				sound.play("reload", 0.8)
			"stab":
				sound.play("stab")
			"blocked_shot":
				sound.ui("ui_click", 0.45)    # (the trigger against the face of a walkway: a dry click)
			"thud":
				sound.play("thud", _vol_at(e.x, e.y))
			"searched":
				sound.ui("ui_confirm", 0.7)
			"survivor":
				sound.play("bell", 0.4, 0.02, 1.35)
				sound.ui("ui_confirm", 0.9)
	run.events.clear()


# ---------------------------------------------------------------- the end --

## The road there is done: the place is played from now.
func _arrive() -> void:
	flow.arrive()
	phase = "place"
	root.visible = true
	overlay_layer.visible = true
	_mirror_colony()
	_update_tint()
	hud_layer.hide_road()
	_frame_start()
	_clamp_camera()
	_apply_camera()
	legend_t = RaidHud.LEGEND_HOLD
	clock_banner("At %s" % String(site.get("name", "the place")), "Get what you can and get out")
	hud_layer.refresh()


## The place is over (everyone alive is at the exit, or nobody can stand, or the base has fallen): the end of the trip. With a
## flow the colony is told (the party is on the road home) and the road home is driven; without one the end card is up.
func _on_place_over() -> void:
	ended = true
	fire_held = false
	hover = null
	reach_container = {}
	reach_friend = null
	_update_pointer()    # (the road home's overlay is a page: the arrow, not the crosshair's hidden pointer)
	if run.sim.avatar != null and leader() != null:
		run.sim.avatar.set_input(Vector2.ZERO, aim_tile, false)
	final_result = run.result()
	if flow == null:
		phase = "report"
		hud_layer.show_end(final_result)
		hud_layer.refresh()
		var sound = main.get("sound")
		if sound != null:
			sound.ui("ui_open", 0.8)
		return
	flow.finish(final_result)
	phase = "road_home"
	root.visible = false
	overlay_layer.visible = false
	hud_layer.show_road(road_title(), flow)
	hud_layer.refresh()


## The road home is done: the colony's view comes back (its rules held) with the report over it.
func _come_home() -> void:
	flow.home()
	phase = "report"
	_restore_colony(true)
	hud_layer.hide_road()
	root.visible = false
	overlay_layer.visible = false
	hud_layer.show_end(final_result, flow.news_lines())
	hud_layer.refresh()
	var sound = main.get("sound")
	if sound != null:
		sound.ui("ui_open", 0.8)


## "Go home" (Enter or the button): the colony is put back (and goes on), `finished` is sent once with the trip's result, and
## the raid is gone.
func go_home() -> void:
	if done or phase != "report":
		return
	done = true
	var result: Dictionary = final_result
	if flow != null:
		if main.get("speed") != null:
			main.set("speed", _speed_after)
		# the report is gone: the cards that came in while the player was out (and were kept waiting) open now, with the speed as it
		# was before the trip, so that the rules wait for the answer
		main.set("trip_report", null)
		var stories = main.get("story_ui")
		if stories != null and is_instance_valid(stories):
			stories.retry()
	else:
		_restore_colony()
	finished.emit(result)
	queue_free()


# ---------------------------------------------------------------- staging --

## A screenshot's way of playing (main.gd's `--raid-do=`): steps joined by "+", each "name" or "name:arg:arg": road[:share] (the
## road there runs to that share, or to its end), go (the road there to its end), wait:<seconds> (the place runs that long: the
## colony behind it), walk:<x>:<y> (the one you lead is put there), aim:<x>:<y> (the pointer is put at that tile), fire:<seconds>
## (the trigger is held that long), hold (held keys let go), sel:<n> (the nth of the squad is selected on the radio), base:<n>
## (the nth of the base), ask:<verb> (the selected contact is asked), news (opens the News panel), alarm, down (the one you
## lead falls), cam:<x>:<y>[:<zoom>], pause, hour:<h> (the colony's clock is set), exit (the whole squad is put in the exit and
## the place ends), roadhome[:share] (the road home runs to that share), home (the road home to its end: the report is up).
func stage(script: String) -> void:
	for step in script.split("+", false):
		var f := step.split(":")
		match f[0]:
			"road":
				_stage_road(float(f[1]) if f.size() > 1 else 1.0, "road_there")
			"go":
				_stage_road(1.0, "road_there")
			"wait":
				for i in int(float(f[1]) * 30.0):
					tick(1.0 / 30.0)
			"walk":
				var lead = leader()
				if lead != null:
					lead.x = float(f[1])
					lead.y = float(f[2])
					lead.path = []
					cam_center = Vector2(lead.x, lead.y)
					_clamp_camera()
					_apply_camera()
			"aim":
				_mouse = to_screen(Vector2(float(f[1]), float(f[2])))
				_staged_aim = true
			"fire":
				fire_held = true
				_staged_fire = true
				for i in int(float(f[1]) * 30.0):
					tick(1.0 / 30.0)
				fire_held = false
				_staged_fire = false
			"hold":
				held.clear()
				fire_held = false
			"sel":
				var squad := squad_contacts()
				var i := int(f[1]) - 1
				if i >= 0 and i < squad.size():
					select_contact("squad", squad[i])
			"base":
				var people := base_contacts()
				var j := int(f[1]) - 1
				if j >= 0 and j < people.size():
					select_contact("base", people[j])
			"ask":
				if not contact.is_empty():
					var r := ask(String(f[1]))
					hud_layer.say(contact.p, String(f[1]), r)
			"news":
				hud_layer.open_news(true)
			"alarm":
				toggle_alarm()
			"call":
				var radio = colony_radio()
				if radio != null:
					radio.raise_call("attack", "The east wall is under attack", "Three of the dead are at the boards", [{"id": "hold", "label": "Hold the wall"}, {"id": "help", "label": "Send help"}, {"id": "back", "label": "Fall back to the school"}], "hold", 30.0)
			"down":
				var lead2 = leader()
				if lead2 != null:
					lead2.downed = true
					lead2.hp = 0.0
			"cam":
				cam_center = Vector2(float(f[1]), float(f[2]))
				if f.size() > 3:
					zoom_px = float(f[3])
				_clamp_camera()
				_apply_camera()
			"pause":
				set_paused(true)
			"hour":
				var cs = colony()
				if cs != null:
					cs.minutes = float(f[1]) * 60.0
					cs.phase = cs.phase_at(cs.minutes)
					_mirror_colony()
					_update_tint()
			"exit":
				_was_out = true
				var spot: Vector2 = site.exit.get_center()
				for p in run.squad:
					if not p.dead:
						p.downed = false
						p.x = spot.x + randf_range(-1.0, 1.0)
						p.y = spot.y + randf_range(-0.8, 0.8)
				tick(1.0 / 30.0)
				tick(1.0 / 30.0)
			"roadhome":
				_stage_road(float(f[1]) if f.size() > 1 else 1.0, "road_home")
			"home":
				_stage_road(1.0, "road_home")
	hud_layer.refresh()
	overlay.queue_redraw()


## Runs the road of this phase until `share` of it is behind (a staging step).
func _stage_road(share: float, which: String) -> void:
	var guard := 0
	while phase == which and guard < 100000:
		if share < 1.0 and flow.road_progress() >= share:
			return
		tick(1.0 / 60.0)
		guard += 1


# ---------------------------------------------------- the radios the verbs ask --

## What the verbs of `radio_verbs.gd` ask of a radio (see radio_kit.gd): this is the squad's, which answers through the place
## (`RaidRun.request`: the squad's own willingness, trust and delay in the place's radio). A place has no walls to be sent to.
class SquadRadio:
	extends RefCounted
	var scene
	var VERBS: Array
	var VERB_NAMES: Dictionary

	func _init(the_scene) -> void:
		scene = the_scene
		VERBS = Radio.VERBS
		VERB_NAMES = Radio.VERB_NAMES

	func _real():
		return scene.run.sim.radio

	func verb_name(verb: String) -> String:
		return _real().verb_name(verb)

	func willingness(contact_p, verb: String) -> Dictionary:
		if verb == "post":
			return {"ok": false, "why": "No walls out here", "line": "", "delay_s": 0.0, "tone": "refused", "hard": true}
		return _real().willingness(contact_p, verb)

	func request(contact_p, verb: String, args: Dictionary = {}) -> Dictionary:
		return scene.squad_request(contact_p, verb, args)

	func trust_of(p) -> float:
		return _real().trust_of(p)

	func tone_of(p) -> String:
		return _real().tone_of(p)

	func trust_why(p) -> Array:
		return _real().trust_why(p)

	func leader():
		return scene.leader()

	func open_calls() -> Array:
		return scene.colony_radio().open_calls() if scene.colony_radio() != null else []

	func answer(id: int, option_id: String) -> bool:
		return scene.colony_radio().answer(id, option_id) if scene.colony_radio() != null else false

	func latest_id() -> int:
		return scene.colony_radio().latest_id() if scene.colony_radio() != null else 0

	func alarm(on: bool, at_dawn: bool = false) -> void:
		if scene.colony_radio() != null:
			scene.colony_radio().alarm(on, at_dawn)

	var news: Array:
		get:
			return scene.colony_radio().news if scene.colony_radio() != null else []

	var alarm_on: bool:
		get:
			return bool(scene.colony_radio().alarm_on) if scene.colony_radio() != null else false

	var sim:
		get:
			return scene.run.sim


## The base's: the people at the base are a radio call away and not within reach, so only "go back" (to what they were doing)
## and "to the walls" make sense; the rest says why not. They go through the colony's radio, which keeps the answer, the
## delay and the trust.
class BaseRadio:
	extends RefCounted
	var scene
	var VERBS: Array
	var VERB_NAMES: Dictionary

	func _init(the_scene) -> void:
		scene = the_scene
		VERBS = Radio.VERBS
		VERB_NAMES = Radio.VERB_NAMES

	func _real():
		return scene.colony_radio()

	func verb_name(verb: String) -> String:
		return _real().verb_name(verb)

	func willingness(contact_p, verb: String) -> Dictionary:
		if verb != "back" and verb != "post":
			return {"ok": false, "why": "%s: too far to follow" % String(contact_p.first), "line": "", "delay_s": 0.0, "tone": "refused", "hard": true}
		return _real().willingness(contact_p, verb)

	func request(contact_p, verb: String, args: Dictionary = {}) -> Dictionary:
		var w := willingness(contact_p, verb)
		if not bool(w.ok) and bool(w.get("hard", false)) and verb != "back" and verb != "post":
			return {"ok": false, "line": "", "why": String(w.why), "delay_s": 0.0, "tone": "refused", "insisted": false}
		return _real().request(contact_p, verb, args)

	func trust_of(p) -> float:
		return _real().trust_of(p)

	func tone_of(p) -> String:
		return _real().tone_of(p)

	func trust_why(p) -> Array:
		return _real().trust_why(p)

	func leader():
		return _real().leader()

	func open_calls() -> Array:
		return _real().open_calls()

	func answer(id: int, option_id: String) -> bool:
		return _real().answer(id, option_id)

	func latest_id() -> int:
		return _real().latest_id()

	func alarm(on: bool, at_dawn: bool = false) -> void:
		_real().alarm(on, at_dawn)

	var news: Array:
		get:
			return _real().news

	var alarm_on: bool:
		get:
			return bool(_real().alarm_on)

	var sim:
		get:
			return scene.colony()
