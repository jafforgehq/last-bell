## A played trip, as a scene (round 14, R14.3). The colony sends a party to a place and the player takes control of the
## squad: this is the place as a small map of its own, over the game. It builds the world of the site (scripts/raid/
## site_gen.gd makes it, scripts/raid/raid_run.gd plays it), the pawns of the squad and of the dead, a camera of its
## own, the selection and the orders by mouse and keyboard, the sounds, and (raid_hud.gd, raid_overlay.gd) the
## squad's cards, the bags' tally, the log, the banners and the end card. It is a modal view: the colony's world, pawns
## and HUD are hidden while it runs and put back exactly as they were when it ends (the yard's camera and zoom, the
## selection, the speed), the colony's rules wait (the speed is 0) and none of the colony's input reaches the raid
## (main.gd's `menu_open` counts a raid as a menu) or the other way about (every key is taken here first).
##
## Opened by main.gd's `open_raid` (nobody calls that yet: the Town Board's "Take control" button will); it gives
## `finished(result)` once, when the end card is dismissed ("Go home": Enter or the button), with `RaidRun.result()`
## (the trip's result format), and frees itself after putting the colony back.
##
## CONTROLS. Left-click a person, or drag a box, to select; 1 to 6 pick one person, Tab goes round, A is everyone.
## Right-click on open ground: the selection walks there (spread a little round the click). Right-click a container
## (shelf, crate, cabinet...): the nearest of the selection goes and searches it. Right-click a downed friend: the
## nearest of the others goes and helps them up. Space pauses (orders can be given while paused). The wheel zooms,
## the middle mouse or the arrow keys pan, F follows the selection. R (or the Retreat button) sends everyone back to
## the road at once; Esc asks "Retreat?" first (Esc again or Enter says yes, any other key says no). H shows the
## legend again. The squad fires at what is in reach on its own, as in the yard.
extends Node

signal finished(result: Dictionary)

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const FX := preload("res://scripts/render/fx.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const RecruitArt := preload("res://scripts/render/recruit_art.gd")
const DrawNode := preload("res://scripts/render/draw_node.gd")
const StepClock := preload("res://scripts/sim/step_clock.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")
const RaidHud := preload("res://scripts/raid/raid_hud.gd")
const RaidOverlay := preload("res://scripts/raid/raid_overlay.gd")

const TILE := GD.TILE
const MAX_ZOOM := 84.0
const VEHICLES_PATH := "res://assets/data/vehicles.json"
## The parts of the colony's view that are hidden while a raid runs (main.gd's names for them).
const HIDDEN := ["world", "overlay", "glow", "snow", "hints"]
## What of the colony's state the raid keeps and gives back (main.gd's names), and which of it may be null.
const COLONY_KEYS := ["cam_center", "zoom_px", "selection", "selected_people", "follow", "speed", "hover", "drag", "order_mark"]
const COLONY_NULLABLE := ["selection", "follow", "hover", "drag", "order_mark"]
## How long (real seconds) a mark of an order shows, and how far from a click the people of a group stand.
const MARK_S := 0.8
const SPREAD := 0.55
## How near (tiles) a right-click must be to a container's prop (`at`) or to its spot (`pos`) to mean it.
const PICK_R := 0.95
## How far (pixels) the mouse must move before a left press is a box and not a click.
const DRAG_PX := 6.0
## The arrow keys pan this many pixels a second.
const PAN_PX := 700.0
## The pointer within this many pixels of the window's edge pans the view that way (only a real pointer, over the window).
const EDGE_PX := 4.0
## The banners are not repeated more often than this (real seconds).
const BANNER_GAP := 4.0

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
var overlay
var overlay_layer: CanvasLayer
var hud_layer
var pawn_nodes := {}
var vehicle_node = null
var step_clock := StepClock.new()
var sim_steps := 0

var cam_center := Vector2(20, 14)
var zoom_px := 40.0
## F: the camera follows the selection (the whole squad when nobody is selected).
var follow := false
var paused := false
## The persons of the squad that are selected (the run's own, not the colony's).
var selection: Array = []
## What the pointer is over: {"kind": "person"|"container", "ref": ...} or null.
var hover = null
## A left press that may become a box or a pan: {"pos", "center", "moved", "button", "box"}.
var drag = null
## The marks the orders leave: [{"x", "y", "t", "kind": "move"|"search"|"help"}].
var marks: Array = []
## The "Retreat?" question is up.
var asking := false
## The run is over and its end card is up / the card was dismissed and `finished` has been emitted.
var ended := false
var done := false
var final_result: Dictionary = {}
var clock := 0.0
var legend_t := 0.0
## What the colony looked like when the raid began (see `_hide_colony`).
var _saved := {}
var _hunters := 0
var _downed := {}
var _banner_t := -99.0
var _hud_t := 0.0
var _heard := false
var has_survivor := false
## Where the pointer was last seen (a real mouse motion), or (-1, -1) when it is not over the window.
var _mouse := Vector2(-1.0, -1.0)


## Builds the place and the squad, takes the screen and pauses the colony. `members_people` are the colony's people
## who go (their skills, weapon and health now), `ammo` what the colony lets them shoot, `vehicle_kind` the id of the
## vehicle they came in ("" on foot: a kind of assets/data/vehicles.json), `loot_mult` what the party's loot is
## multiplied by (a good leader, a lone scavenger), `has_survivor` whether someone is to be found in the place.
func setup(game, game_hud, base_data: Dictionary, the_site: Dictionary, members_people: Array, ammo: float, vehicle_kind: String = "", loot_mult: float = 1.0, survivor: bool = false) -> void:
	main = game
	hud = game_hud
	data = base_data
	site = the_site
	has_survivor = survivor
	name = "RaidScene"
	_hide_colony()
	_build_world()
	run = RaidRun.new(site, world, fx, RaidRun.squad_of(members_people), ammo, vehicle_kind, loot_mult, survivor)
	# the run's own Sim gives each person the colony job their def names (a seat in the yard); nobody here works one
	run.sim.jobs.clear()
	run.sim.tactics.chores = false
	for p in run.squad:
		_add_person_pawn(p)
	if vehicle_kind != "" and Vector2(site.get("vehicle_spot", Vector2(-1, -1))).x >= 0.0:
		_add_vehicle(vehicle_kind)
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
	_frame_start()
	_clamp_camera()
	_apply_camera()
	camera.make_current()
	legend_t = RaidHud.LEGEND_HOLD
	hud_layer.refresh()
	_sync_views(true)


# ------------------------------------------------------------ the colony --

## Hides what the colony shows and holds its rules (speed 0), remembering what was as it was. A part the game does not
## have (a fake in a test) is left alone.
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
	if main.get("speed") != null:
		main.set("speed", 0)
	main.set("follow", null)
	main.set("drag", null)
	main.set("hover", null)
	main.set("raid", self)


## Puts the colony back exactly as it was.
func _restore_colony() -> void:
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
	var cam = main.get("camera")
	if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
		cam.make_current()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_saved = {}


func _exit_tree() -> void:
	# freed without being sent home (the game was left, a test): the colony is put back all the same, no `finished`
	if not done:
		_restore_colony()


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
	# muzzle flashes, tracers, sparks: added to what is under them (there is no night to be dark in here)
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


func _add_pawn(e, is_zombie: bool, key: String) -> void:
	var n := PawnNode.new()
	n.setup(e, is_zombie, data, key)
	entities.add_child(n)
	pawn_nodes[e] = n


## The node of a person of the squad: the six survivors have baked bodies, a recruit is drawn on the body most like
## their look (as main.gd's `_add_person_pawn` does).
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
	cam_center.x = ww / 2.0 if hw * 2.0 >= ww + 2.0 * m else clampf(cam_center.x, hw - m, ww - hw + m)
	cam_center.y = wh / 2.0 if hh * 2.0 >= wh + 2.0 * m else clampf(cam_center.y, hh - m, wh - hh + m)


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


## Pans by `d` tiles (the keys, the middle mouse): it lets go of the follow.
func pan(d: Vector2) -> void:
	follow = false
	cam_center += d
	_clamp_camera()


## The first view: the squad and the things to search framed together when they fit at a size worth playing at, else the
## squad with the view leaning toward the things.
func _frame_start() -> void:
	var vp := _vp()
	var box := Rect2(_squad_centre(), Vector2.ZERO)
	for c in run.containers:
		box = box.expand(Vector2(c.at))
	box = box.grow(3.0)
	var fit := minf(vp.x / box.size.x, vp.y * 0.78 / box.size.y)
	zoom_px = clampf(fit, 28.0, 52.0)
	if fit >= 28.0:
		cam_center = box.get_center()
	else:
		var squad := _squad_centre()
		cam_center = squad + (box.get_center() - squad) * 0.5


func _squad_centre(only_selected: bool = false) -> Vector2:
	var list: Array = selection if only_selected and not selection.is_empty() else run.squad
	var sum := Vector2.ZERO
	var n := 0
	for p in list:
		if p.dead:
			continue
		sum += Vector2(p.x, p.y)
		n += 1
	if n == 0:
		return cam_center
	return sum / float(n)


func toggle_follow() -> void:
	follow = not follow
	if follow:
		cam_center = _squad_centre(true)
		_clamp_camera()
	hud_layer.toast("Following %s" % ("the selection" if not selection.is_empty() else "the squad") if follow else "Camera is free")


# ------------------------------------------------------------- selection --

func living_squad() -> Array:
	var out: Array = []
	for p in run.squad:
		if not p.dead:
			out.append(p)
	return out


func select(people: Array) -> void:
	selection = []
	for p in people:
		if p != null and not p.dead and run.squad.has(p) and not selection.has(p):
			selection.append(p)
	hud_layer.refresh()


func select_one(p) -> void:
	select([p] if p != null else [])


func select_all() -> void:
	var alive: Array = []
	for p in run.living():
		alive.append(p)
	select(alive)


## The nth of the squad (0 based), if they are still there to select.
func select_index(i: int) -> void:
	if i >= 0 and i < run.squad.size() and not run.squad[i].dead:
		select([run.squad[i]])


## Tab: the next of the squad after the one selected (the first when nobody is, or several are).
func cycle_selection() -> void:
	var alive := living_squad()
	if alive.is_empty():
		return
	var at := -1
	if selection.size() == 1:
		at = alive.find(selection[0])
	select([alive[(at + 1) % alive.size()]])


## Someone who is lost is no longer selected.
func _prune_selection() -> void:
	for p in selection.duplicate():
		if p.dead:
			selection.erase(p)


func is_selected(p) -> bool:
	return selection.has(p)


# ---------------------------------------------------------------- picking --

## The person of the squad under a point (tiles); `downed` asks for one who is down, else for one who stands.
func pick_person(w: Vector2, downed: bool = false):
	var list: Array = run.squad.duplicate()
	list.sort_custom(func(a, b): return a.y > b.y)
	for p in list:
		if p.dead or p.downed != downed:
			continue
		if w.x > p.x - 0.45 and w.x < p.x + 0.45 and w.y > p.y - 0.95 and w.y < p.y + 0.45:
			return p
	return null


## A person who is down and lies near the point: their body is wide, so this is a little kinder than `pick_person`.
func pick_downed(w: Vector2):
	var best = null
	var best_d := 1.0
	for p in run.squad:
		if p.dead or not p.downed:
			continue
		var d := Vector2(p.x, p.y - 0.25).distance_to(w)
		if d < best_d:
			best_d = d
			best = p
	return best


## The container (of the run's own list, looted or not) whose prop or whose standing spot is near the point.
func pick_container(w: Vector2) -> Dictionary:
	var best := {}
	var best_d := PICK_R
	for c in run.containers:
		var d := minf(Vector2(c.at).distance_to(w), Vector2(c.pos).distance_to(w))
		if d < best_d:
			best_d = d
			best = c
	return best


# ----------------------------------------------------------------- orders --

func _able(p) -> bool:
	return p != null and not p.dead and not p.downed


## The members of the selection who can act, nearest first to `to` (tiles).
func _actors(to: Vector2) -> Array:
	var out: Array = []
	for p in selection:
		if _able(p):
			out.append(p)
	out.sort_custom(func(a, b): return Vector2(a.x, a.y).distance_to(to) < Vector2(b.x, b.y).distance_to(to))
	return out


func _mark(kind: String, at: Vector2) -> void:
	marks.append({"x": at.x, "y": at.y, "t": clock, "kind": kind})


## Right-click on open ground: the selection walks to `tile`, the people of a group spread a little round it. Returns how
## many were sent.
func order_move(tile: Vector2) -> int:
	if run.phase != "play":
		hud_layer.toast("Already heading for the road", "warn")
		return 0
	var who := _actors(tile)
	if selection.is_empty():
		hud_layer.toast("Click someone first, then right-click where they should go")
		return 0
	if who.is_empty():
		hud_layer.toast("Nobody selected can move", "warn")
		return 0
	var sent := 0
	for i in who.size():
		var at := tile
		if who.size() > 1:
			var a := TAU * float(i) / float(who.size()) + 0.4
			at = tile + Vector2(cos(a), sin(a)) * SPREAD
		if run.order_move(who[i], at) or run.order_move(who[i], tile):
			sent += 1
	if sent == 0:
		hud_layer.toast("Nobody can stand there", "warn")
	else:
		_mark("move", tile)
	return sent


## Right-click on a container: the nearest of the selection goes and searches it. True if someone went.
func order_search(container_id: String) -> bool:
	var c: Dictionary = run.container(container_id)
	if c.is_empty():
		return false
	if run.phase != "play":
		hud_layer.toast("Already heading for the road", "warn")
		return false
	if bool(c.looted):
		hud_layer.toast("Nothing left in that")
		return false
	if selection.is_empty():
		hud_layer.toast("Click someone first, then right-click what to search")
		return false
	var who := _actors(Vector2(c.pos))
	if who.is_empty():
		hud_layer.toast("Nobody selected can search", "warn")
		return false
	if run.order_search(who[0], container_id):
		_mark("search", Vector2(c.at))
		return true
	hud_layer.toast("%s can't get there" % who[0].first, "warn")
	return false


## Right-click on a friend who is down: the nearest of the others in the selection goes and helps them up.
func order_help(friend) -> bool:
	if run.phase != "play":
		return false
	var who: Array = []
	for p in _actors(Vector2(friend.x, friend.y)):
		if p != friend:
			who.append(p)
	if who.is_empty():
		hud_layer.toast("Select someone else to help %s" % friend.first, "warn")
		return false
	if run.order_help(who[0], friend):
		_mark("help", Vector2(friend.x, friend.y))
		return true
	return false


## R or the button: everyone walks back to the road now.
func retreat() -> void:
	if ended or run.phase != "play":
		return
	asking = false
	run.retreat()
	_mark("move", Vector2(site.exit.get_center()))
	hud_layer.toast("Everyone is heading back to the road")
	hud_layer.refresh()


func set_paused(on: bool) -> void:
	paused = on
	hud_layer.refresh()


func ask_retreat() -> void:
	if ended or run.phase != "play":
		return
	asking = true
	drag = null
	hud_layer.refresh()


func cancel_ask() -> void:
	if asking:
		asking = false
		hud_layer.refresh()


## Whom a person is helping up and what they are searching (the run's own record of their orders).
func _helping_of(p):
	var h: Dictionary = run.get("_helping").get(String(p.id), {}) if run.get("_helping") != null else {}
	return run.person(String(h.who)) if not h.is_empty() else null


func _searching_of(p) -> Dictionary:
	var cid := String(run.get("_searching").get(String(p.id), "")) if run.get("_searching") != null else ""
	return run.container(cid) if cid != "" else {}


## What a person is doing, for their card: Down, Helping, Searching, Reloading, Retreating, Walking, Fighting or Ready.
func status_of(p) -> String:
	if p.dead:
		return "Lost"
	if p.downed:
		return "Down"
	var friend = _helping_of(p)
	if friend != null and friend.downed:
		return "Going to help" if p.moving or Vector2(p.x, p.y).distance_to(Vector2(friend.x, friend.y)) > RaidRun.REACH + 0.6 else "Helping"
	var c := _searching_of(p)
	if not c.is_empty() and not bool(c.looted):
		return "Going to search" if p.moving or Vector2(p.x, p.y).distance_to(Vector2(c.pos)) > RaidRun.REACH else "Searching"
	if p.reloading > 0.0:
		return "Reloading"
	if run.phase != "play":
		return "Retreating" if p.moving and not run.finished() else "Out"
	if p.moving:
		return "Walking"
	if p.target != null:
		return "Fighting"
	return "Ready"


## The short line under the place's name: what to do next.
func hint_line() -> String:
	if run.phase == "retreat":
		return "Heading back to the road."
	var down := ""
	for p in run.squad:
		if p.downed and not p.dead:
			down = p.first
	if down != "":
		return "%s is down. Right-click them with someone else to help." % down
	var left := 0
	for c in run.containers:
		if not bool(c.looted) and String(c.kind) != "survivor":
			left += 1
	if run.carried_total() >= run.capacity() and run.capacity() > 0:
		return "The bags are full. Head back to the road."
	if left == 0:
		return "Everything is searched. Head back to the road."
	if run.carried_total() == 0 and run.elapsed < 45.0:
		return "Right-click a shelf or a crate to search it. Back to the road to leave."
	return "%d place%s left to search. Retreat (R) when you have what you came for." % [left, "" if left == 1 else "s"]


# ------------------------------------------------------------------ input --

func _input(ev: InputEvent) -> void:
	if done or not (ev is InputEventKey) or not ev.pressed:
		return
	# every key belongs to the raid while it is up (the Town Board under it would take Esc, the yard its letters)
	get_viewport().set_input_as_handled()
	if ev.echo:
		return
	key_pressed(ev.keycode, ev.shift_pressed)


## A key, as the raid takes it (the tests press them through this).
func key_pressed(code: Key, shift: bool = false) -> void:
	if ended:
		if code == KEY_ENTER or code == KEY_KP_ENTER:
			go_home()
		return
	if asking:
		if code == KEY_ESCAPE or code == KEY_ENTER or code == KEY_KP_ENTER:
			retreat()
		else:
			cancel_ask()
		return
	match code:
		KEY_SPACE:
			set_paused(not paused)
		KEY_ESCAPE:
			if run.phase == "play":
				ask_retreat()
		KEY_R:
			retreat()
		KEY_TAB:
			cycle_selection()
		KEY_A:
			select_all()
		KEY_F:
			toggle_follow()
		KEY_H:
			legend_t = RaidHud.LEGEND_HOLD
			hud_layer.refresh()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			var i: int = int(code) - int(KEY_1)
			if shift and i < run.squad.size() and not run.squad[i].dead:
				var more: Array = selection.duplicate()
				if more.has(run.squad[i]):
					more.erase(run.squad[i])
				else:
					more.append(run.squad[i])
				select(more)
			else:
				select_index(i)


func _unhandled_input(ev: InputEvent) -> void:
	if done:
		return
	if ev is InputEventMouseButton:
		mouse_button(ev)
	elif ev is InputEventMouseMotion:
		mouse_motion(ev)
	elif ev is InputEventMagnifyGesture:
		zoom_at(ev.factor, ev.position)
	elif ev is InputEventPanGesture:
		zoom_at(exp(-ev.delta.y * 0.06), ev.position)


func mouse_button(mb: InputEventMouseButton) -> void:
	if ended or asking:
		return
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				zoom_at(exp(0.2 * maxf(mb.factor, 0.2)), mb.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				zoom_at(exp(-0.2 * maxf(mb.factor, 0.2)), mb.position)
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				right_click(mb.position)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				drag = {"pos": mb.position, "center": cam_center, "moved": false, "button": mb.button_index, "box": Rect2(), "shift": mb.shift_pressed}
			else:
				if drag != null and drag.button == mb.button_index and mb.button_index == MOUSE_BUTTON_LEFT:
					if drag.moved:
						_finish_box(drag.box, bool(drag.shift))
					else:
						left_click(mb.position, mb.shift_pressed)
				drag = null
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func mouse_motion(mm: InputEventMouseMotion) -> void:
	_mouse = mm.position
	if ended or asking:
		return
	if drag != null:
		var dv: Vector2 = mm.position - drag.pos
		if not drag.moved and dv.length() > DRAG_PX:
			drag.moved = true
		if drag.moved:
			if drag.button == MOUSE_BUTTON_MIDDLE:
				follow = false
				cam_center = drag.center - dv / zoom_px
				_clamp_camera()
			else:
				drag.box = Rect2(drag.pos, Vector2.ZERO).expand(mm.position)
		return
	var w := to_tile(mm.position)
	hover = null
	var p = pick_person(w)
	if p == null:
		p = pick_downed(w)
	if p != null:
		hover = {"kind": "person", "ref": p}
	else:
		var c := pick_container(w)
		if not c.is_empty() and not bool(c.looted):
			hover = {"kind": "container", "ref": c}
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hover != null else Input.CURSOR_ARROW)


## A left click (screen point): the person under it is selected (shift adds or takes away); nothing under it lets go.
func left_click(screen: Vector2, shift: bool = false) -> void:
	var w := to_tile(screen)
	var p = pick_person(w)
	if p == null:
		p = pick_downed(w)
	if p == null:
		if not shift:
			select([])
		return
	if shift:
		var more: Array = selection.duplicate()
		if more.has(p):
			more.erase(p)
		else:
			more.append(p)
		select(more)
	else:
		select([p])


func _finish_box(box: Rect2, shift: bool) -> void:
	var picked: Array = selection.duplicate() if shift else []
	for p in run.squad:
		if p.dead or p.downed or picked.has(p):
			continue
		if box.has_point(to_screen(view_pos(p) + Vector2(0.0, -0.45))):
			picked.append(p)
	select(picked)


## A right-click (screen point): a friend who is down is helped, a container searched, open ground walked to.
func right_click(screen: Vector2) -> void:
	var w := to_tile(screen)
	var friend = pick_downed(w)
	if friend != null and not (selection.size() == 1 and selection[0] == friend):
		order_help(friend)
		return
	var c := pick_container(w)
	if not c.is_empty():
		order_search(String(c.id))
		return
	order_move(w)


# ------------------------------------------------------------------- loop --

func _process(delta: float) -> void:
	tick(delta)


## One frame of `delta` real seconds: the run takes whole steps of the rules' clock (unless the raid is paused, or
## is being asked about its retreat, or is over), then the view follows.
func tick(delta: float) -> void:
	if done:
		return
	var dt := clampf(delta, 0.0, StepClock.MAX_FRAME)
	clock += dt
	legend_t = maxf(0.0, legend_t - dt)
	var running: bool = not paused and not asking and not run.finished()
	if running:
		for i in step_clock.advance(dt, 1.0):
			run.update(StepClock.STEP)
			sim_steps += 1
		fx.update(dt)
	elif run.finished():
		fx.update(dt)
	_handle_events()
	_prune_selection()
	var keys := Vector2(int(Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_LEFT)), int(Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_UP)))
	keys += edge_pan()
	if keys != Vector2.ZERO and not ended and not asking:
		pan(keys * dt * PAN_PX / zoom_px)
	if follow:
		cam_center += (_squad_centre(true) - cam_center) * minf(1.0, dt * 5.0)
	_clamp_camera()
	_apply_camera()
	marks = marks.filter(func(m): return clock - float(m.t) < MARK_S)
	_sync_views(false)
	if run.finished() and not ended:
		_on_ended()
	_hud_t -= dt
	if _hud_t <= 0.0:
		_hud_t = 0.1
		hud_layer.refresh()
	overlay.queue_redraw()


## Which way the pointer at the window's edge pans (a unit step on each axis it touches), or none: not without a real
## pointer over the window, not while a button is held (a drag) or the window is not the one in use.
func edge_pan() -> Vector2:
	if _mouse.x < 0.0 or drag != null or not is_inside_tree() or not get_window().has_focus():
		return Vector2.ZERO
	var vp := _vp()
	# (the pointer as it is now: a flick onto a panel that eats the motion must not leave the view scrolling)
	if DisplayServer.get_name() != "headless":
		_mouse = get_viewport().get_mouse_position()
	return Vector2(int(_mouse.x >= vp.x - EDGE_PX) - int(_mouse.x <= EDGE_PX), int(_mouse.y >= vp.y - EDGE_PX) - int(_mouse.y <= EDGE_PX))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_mouse = Vector2(-1.0, -1.0)


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
	for p in run.squad:
		var was: bool = bool(_downed.get(p.id, false))
		if p.downed and not was and not p.dead:
			_banner("%s is down" % p.first, "Right-click them with someone else to help them up")
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
			"thud":
				sound.play("thud", _vol_at(e.x, e.y))
			"searched":
				sound.ui("ui_confirm", 0.7)
			"survivor":
				sound.play("bell", 0.4, 0.02, 1.35)
				sound.ui("ui_confirm", 0.9)
	run.events.clear()


# ---------------------------------------------------------------- the end --

func _on_ended() -> void:
	ended = true
	asking = false
	drag = null
	hover = null
	final_result = run.result()
	hud_layer.show_end(final_result)
	hud_layer.refresh()
	var sound = main.get("sound")
	if sound != null:
		sound.ui("ui_open", 0.8)


## "Go home" (Enter or the button): the colony is put back, `finished` is sent once with the trip's result, and the raid
## is gone.
func go_home() -> void:
	if done or not ended:
		return
	done = true
	var result: Dictionary = final_result
	_restore_colony()
	finished.emit(result)
	queue_free()


# ---------------------------------------------------------------- staging --

## A screenshot's way of playing (main.gd's `--raid-do=`): steps joined by "+", each "name" or "name:arg:arg": all, one,
## sel:<n> (the nth person, from 1), search:<container index from 0, its id, or "near" for the nearest left>, move:<x>:<y>,
## help:<n>, down:<n> (a person falls), wait:<seconds> (the rules run that long), follow, cam:<x>:<y>[:<zoom>], pause, ask,
## retreat, end (retreat and run to the end card), home.
func stage(script: String) -> void:
	for step in script.split("+", false):
		var f := step.split(":")
		match f[0]:
			"all":
				select_all()
			"one":
				select_index(0)
			"sel":
				select_index(int(f[1]) - 1)
			"search":
				if selection.is_empty():
					select_all()
				var at := String(f[1])
				if at == "near":
					var best := INF
					for c in run.containers:
						var d := Vector2(c.pos).distance_to(_squad_centre())
						if String(c.kind) != "survivor" and not bool(c.looted) and d < best:
							best = d
							at = String(c.id)
				elif at.is_valid_int() and int(at) < run.containers.size():
					at = String(run.containers[int(at)].id)
				order_search(at)
			"follow":
				toggle_follow()
			"cam":
				cam_center = Vector2(float(f[1]), float(f[2]))
				if f.size() > 3:
					zoom_px = float(f[3])
				_clamp_camera()
				_apply_camera()
			"move":
				if selection.is_empty():
					select_all()
				order_move(Vector2(float(f[1]), float(f[2])))
			"help":
				var friend = null
				for p in run.squad:
					if p.downed:
						friend = p
				if friend != null:
					order_help(friend)
			"down":
				var victim = run.squad[int(f[1]) - 1]
				victim.downed = true
				victim.hp = 0.0
			"wait":
				for i in int(float(f[1]) * 30.0):
					tick(1.0 / 30.0)
			"pause":
				set_paused(true)
			"ask":
				ask_retreat()
			"retreat":
				retreat()
			"end":
				retreat()
				var guard := 0
				while not ended and guard < 6000:
					tick(1.0 / 30.0)
					guard += 1
			"home":
				go_home()
	hud_layer.refresh()
