## Thirty Bells: six survivors hold a walled schoolyard against the dead.
## Builds the world from the baked data, runs the simulation, the camera,
## input, sound and HUD.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const StepClock := preload("res://scripts/sim/step_clock.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Scenario := preload("res://scripts/sim/scenario.gd")
const FX := preload("res://scripts/render/fx.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const FireNode := preload("res://scripts/render/fire_node.gd")
const Lighting := preload("res://scripts/render/lighting.gd")
const GlowNode := preload("res://scripts/render/glow_node.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")
const DrawNode := preload("res://scripts/render/draw_node.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Sound := preload("res://scripts/audio/sound.gd")

const TILE := GD.TILE
const MAX_ZOOM := 84.0

var data: Dictionary
var world
var sim
var fx
var lighting
var hud
var sound
var camera: Camera2D
var entities: Node2D
var corpses: Node2D
var fire_nodes: Array = []
var ground_bits
var air
var lanterns_node
var glow
var overlay
var pawn_nodes := {} # entity -> node
## Turns frames into whole 1/30 s steps of the rules, and says how far the time
## has run into the next one (the drawing blends between the last two steps).
var step_clock := StepClock.new()
## How many steps the rules have taken, for the pawn nodes' interpolation.
var sim_steps := 0

var cam_center := Vector2(41, 21)
var zoom_px := 32.0
var speed := 1
var sound_on := true
var selection = null
var hover = null
var follow = null
var order_mark = null
var clock := 0.0
var fire_t := 0.0
var hud_t := 0.0
var drag = null
var walkers := 0
## A save was asked for at start-up but could not be loaded (a new run began instead).
var load_failed := false

# screenshot mode (used for automated checks): --shot=path.png
var shot_path := ""
var shot_frames := 25
var frame_count := 0
var bench_start := 0
var bench_cpu := 0.0
var bench_gpu := 0.0
var bench_proc := 0.0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	data = GD.load_all()
	var logical := Vector2i(1280, 800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var wh := arg.trim_prefix("--size=").split("x")
			logical = Vector2i(int(wh[0]), int(wh[1]))
	_fit_window(logical)
	get_window().size_changed.connect(_update_scale)
	_update_scale()

	world = World.new()
	world.name = "World"
	add_child(world)
	world.build(data)

	var decals := Node2D.new()
	decals.name = "Decals"
	decals.z_index = 5
	world.add_child(decals)
	var radial := _radial_texture()
	fx = FX.new()
	fx.setup(data, decals, radial)

	ground_bits = DrawNode.new()
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
	var fire_layer := Node2D.new()
	fire_layer.name = "Fire"
	fire_layer.z_index = 7
	world.add_child(fire_layer)
	air = DrawNode.new()
	air.name = "Air"
	air.z_index = 8
	air.painter = fx.draw_air
	world.add_child(air)

	sim = Sim.new(data, world, fx)
	sim.on_segment_change = func(s): world.set_segment_state(s.id, s.state)
	# a run is started (or a save loaded) by reloading the scene with the
	# choice kept in Engine meta: {"difficulty": int, "seed": int, "load": path};
	# the first run of a process takes it from the command line instead:
	# --new=<difficulty 0-2> --seed=<n> --load=<path>
	var run: Dictionary = Scenario.run_from_args(OS.get_cmdline_user_args())
	if Engine.has_meta("run"):
		run = Engine.get_meta("run")
		Engine.remove_meta("run")
	var loaded := false
	if String(run.get("load", "")) != "":
		loaded = SaveGame.apply(sim, SaveGame.read(String(run.load)))
		load_failed = not loaded
	if not loaded:
		sim.start_run(int(run.get("difficulty", 1)), int(run.get("seed", randi())))

	for tr in data.trees:
		var s := Sprite2D.new()
		var tex := GD.tex(tr.file)
		var box: Array = data.tree.box
		var dens := float(data.tree.density)
		s.texture = tex
		s.centered = false
		s.offset = Vector2(box[0], box[1]) * dens
		s.scale = Vector2.ONE * (TILE / dens)
		s.position = Vector2(tr.x, tr.y) * TILE
		entities.add_child(s)
	for p in sim.people:
		_add_pawn(p, false, p.id)

	for l in data.lights:
		if l.get("fire", false):
			var f := FireNode.new()
			f.setup(l.x, l.y, l.get("big", false))
			fire_layer.add_child(f)
			fire_nodes.append(f)
	lanterns_node = DrawNode.new()
	lanterns_node.painter = _draw_lanterns
	fire_layer.add_child(lanterns_node)

	lighting = Lighting.new()
	lighting.name = "Lighting"
	world.add_child(lighting)
	var cm := CanvasModulate.new()
	world.add_child(cm)
	lighting.setup(data, cm)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

	var glow_layer := CanvasLayer.new()
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)
	glow = GlowNode.new()
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.setup(data, fx, lighting, radial)
	glow_layer.add_child(glow)

	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 2
	add_child(overlay_layer)
	overlay = OverlayNode.new()
	overlay.main = self
	overlay_layer.add_child(overlay)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 3
	add_child(hud_layer)
	hud = Hud.new()
	hud.on_select = func(sel): _select(sel)
	hud.on_focus = func(p): _focus(Vector2(p.x, p.y))
	hud.on_speed = func(s): speed = s
	hud.on_gizmo = _gizmo
	hud.on_alert = _on_alert
	hud.on_sound = _toggle_sound
	hud_layer.add_child(hud)
	hud.setup(data, sim.people)

	sound = Sound.new()
	add_child(sound)
	sound.setup(data.sounds)

	var vp := _vp()
	zoom_px = clampf(vp.x / 26.0, 28.0, 52.0)
	_parse_args()
	_clamp_camera()
	_apply_camera()
	if load_failed:
		hud.show_banner("Could not load that save", "A new game was started instead")
	print("Thirty Bells ready in %d ms" % (Time.get_ticks_msec() - t0))


func _add_pawn(e, is_zombie: bool, key: String) -> void:
	var n := PawnNode.new()
	n.setup(e, is_zombie, data, key)
	entities.add_child(n)
	pawn_nodes[e] = n


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


## On a Retina screen the project's 1280x800 window opens at that many pixels,
## i.e. at half size. Grow it to 1280x800 points (within the screen) and centre it.
func _fit_window(logical: Vector2i) -> void:
	var win := get_window()
	# in a browser the page sizes the canvas
	if win.mode != Window.MODE_WINDOWED or OS.has_feature("web"):
		return
	var s := DisplayServer.screen_get_scale(win.current_screen)
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var want := Vector2i(Vector2(logical) * s)
	want.x = mini(want.x, int(usable.size.x * 0.94))
	want.y = mini(want.y, int(usable.size.y * 0.94))
	win.size = want
	win.position = usable.position + (usable.size - want) / 2


## Keep the UI at a constant size in points on any display and window size.
func _update_scale() -> void:
	var win := get_window()
	var s := DisplayServer.screen_get_scale()
	if s <= 0.0:
		s = 1.0
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(maxi(1, int(win.size.x / s)), maxi(1, int(win.size.y / s)))


func _vp() -> Vector2:
	return get_viewport_rect().size


# ---------------------------------------------------------------- camera --

func _min_zoom() -> float:
	var vp := _vp()
	return maxf(10.0, minf(vp.x / (world.W + 2.0), vp.y / (world.H + 2.0)))


func _clamp_camera() -> void:
	zoom_px = clampf(zoom_px, _min_zoom(), MAX_ZOOM)
	var vp := _vp()
	var hw := vp.x / 2.0 / zoom_px
	var hh := vp.y / 2.0 / zoom_px
	var m := 1.0
	var W: float = world.W
	var H: float = world.H
	cam_center.x = W / 2.0 if hw * 2.0 >= W + 2.0 * m else clampf(cam_center.x, hw - m, W - hw + m)
	cam_center.y = H / 2.0 if hh * 2.0 >= H + 2.0 * m else clampf(cam_center.y, hh - m, H - hh + m)


func _apply_camera() -> void:
	camera.position = cam_center * TILE
	camera.zoom = Vector2.ONE * (zoom_px / TILE)


func _screen_to_tile(p: Vector2) -> Vector2:
	return cam_center + (p - _vp() / 2.0) / zoom_px


func _zoom_at(factor: float, screen: Vector2) -> void:
	var before := _screen_to_tile(screen)
	zoom_px = clampf(zoom_px * factor, _min_zoom(), MAX_ZOOM)
	var after := _screen_to_tile(screen)
	cam_center += before - after
	_clamp_camera()


func _focus(at: Vector2) -> void:
	cam_center = at
	_clamp_camera()


func view_rect() -> Rect2:
	var vp := _vp()
	return Rect2(cam_center - vp / 2.0 / zoom_px, vp / zoom_px)


# -------------------------------------------------------------- selection --

func _select(sel) -> void:
	selection = sel
	follow = null
	hud.select(sel)


func _pick(w: Vector2):
	var hit := func(e): return w.x > e.x - 0.42 and w.x < e.x + 0.42 and w.y > e.y - 0.95 and w.y < e.y + 0.42
	var ppl: Array = sim.people.duplicate()
	ppl.sort_custom(func(a, b): return a.y > b.y)
	for p in ppl:
		if p.away == null and not p.turned and hit.call(p):
			return {"kind": "person", "ref": p}
	var zs: Array = []
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			zs.append(z)
	zs.sort_custom(func(a, b): return a.y > b.y)
	for z in zs:
		if hit.call(z):
			return {"kind": "zombie", "ref": z}
	for s in sim.segments:
		var o: Dictionary = s.obj
		var c := cos(-float(o.a))
		var sn := sin(-float(o.a))
		var dx: float = w.x - o.cx
		var dy: float = w.y - o.cy
		var lx := dx * c - dy * sn
		var ly := dx * sn + dy * c
		if absf(lx) < o.w / 2.0 and absf(ly) < o.h / 2.0 + 0.3:
			return {"kind": "segment", "ref": s}
	return null


func _gizmo(g: String) -> void:
	if g == "scavenge":
		hud.open_scavenge(selection)
		return
	var sel = selection
	if sel == null:
		hud.toast("Click someone first")
		return
	if sim.handle_gizmo(g, sel):
		hud.select(selection)
		return
	if g == "treat" or g == "sendout":
		var why: String = hud.why_not(g)
		hud.toast("Not now: %s" % why if why != "" else "That can't be done right now", "warn")
	if g == "draft" and sel.kind == "person":
		sim.toggle_draft(sel.ref)
	elif g == "post" and sel.kind == "person":
		sim.order_post(sel.ref)
	elif g == "repair":
		var no_go: String = hud.why_not("repair")
		if sel.kind == "segment":
			var p = _pick_repairer(sel.ref)
			if p != null and no_go == "":
				sim.order_repair(p, sel.ref)
			else:
				hud.toast("Not now: %s" % (no_go if no_go != "" else "nobody is free to repair it"), "warn")
		elif sel.kind == "person":
			var worst = null
			for s in sim.segments:
				if s.hp < s.max_hp and (worst == null or s.hp / s.max_hp < worst.hp / worst.max_hp):
					worst = s
			if worst != null and no_go == "":
				sim.order_repair(sel.ref, worst)
			else:
				hud.toast("Not now: %s" % (no_go if no_go != "" else "nothing is damaged"), "warn")
	elif g == "focus":
		if sel.kind == "segment":
			_focus(sel.ref.center)
		else:
			_focus(Vector2(sel.ref.x, sel.ref.y))
			follow = sel.ref
	hud.select(selection)


## Why an order to walk to `w` was refused, in a few words.
func _why_not_there(p, w: Vector2) -> String:
	if p.dead:
		return "%s is gone" % p.first
	if p.downed:
		return "%s is down" % p.first
	if p.away != null:
		return "%s is away" % p.first
	if world.is_solid(world.solid_p, w.x, w.y):
		return "Nobody can stand there"
	return "%s can't go there" % p.first


func _pick_repairer(seg):
	var best = null
	var bd := INF
	for p in sim.people:
		if p.downed or p.dead or p.away != null:
			continue
		var dist: float = Vector2(p.x - seg.center.x, p.y - seg.center.y).length() - float(p.def.skills.Building) * 3.0
		if dist < bd:
			bd = dist
			best = p
	return best


func _on_alert(id: String) -> void:
	var a = sim.alerts.get(id)
	if a != null and a.at != null:
		_focus(a.at)


func _quick_save() -> void:
	if sim.over != "":
		hud.show_banner("The run is over", "Start a new game or load a save")
	elif SaveGame.write(sim, SaveGame.QUICK_PATH):
		hud.show_banner("Game saved", "Quick save (F9 loads it)")
	else:
		hud.show_banner("Could not save", "Nothing was written")


func _quick_load() -> void:
	if not FileAccess.file_exists(SaveGame.QUICK_PATH):
		hud.show_banner("No quick save yet", "Press F5 to save")
		return
	# check it before the current game is thrown away for it
	if not SaveGame.is_loadable(SaveGame.QUICK_PATH):
		hud.show_banner("Could not load", "The quick save is damaged or from another version")
		return
	Engine.set_meta("run", {"load": SaveGame.QUICK_PATH})
	get_tree().reload_current_scene()


func _toggle_sound() -> void:
	sound_on = not sound_on
	sound.set_muted(not sound_on)


# ------------------------------------------------------------------ input --

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(exp(0.2 * maxf(mb.factor, 0.2)), mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(exp(-0.2 * maxf(mb.factor, 0.2)), mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if selection != null and selection.kind == "person":
				var w := _screen_to_tile(mb.position)
				if sim.order_move(selection.ref, w.x, w.y):
					order_mark = {"x": w.x, "y": w.y, "t": clock}
				else:
					hud.toast(_why_not_there(selection.ref, w), "warn")
				hud.select(selection)
			else:
				hud.toast("Click someone first, then right-click where they should go")
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				drag = {"pos": mb.position, "center": cam_center, "moved": false, "button": mb.button_index}
			else:
				if drag != null and not drag.moved and drag.button == MOUSE_BUTTON_LEFT:
					_select(_pick(_screen_to_tile(mb.position)))
				drag = null
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	elif ev is InputEventMouseMotion:
		var mm: InputEventMouseMotion = ev
		if drag != null:
			var dv: Vector2 = mm.position - drag.pos
			if not drag.moved and dv.length() > 4.0:
				drag.moved = true
				Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			if drag.moved:
				follow = null
				cam_center = drag.center - dv / zoom_px
				_clamp_camera()
		else:
			var h = _pick(_screen_to_tile(mm.position))
			hover = h.ref if h != null and h.kind == "person" else null
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if h != null else Input.CURSOR_ARROW)
	elif ev is InputEventMagnifyGesture:
		_zoom_at(ev.factor, ev.position)
	elif ev is InputEventPanGesture:
		_zoom_at(exp(-ev.delta.y * 0.06), ev.position)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_SPACE:
				speed = 1 if speed == 0 else 0
			KEY_1:
				speed = 1
			KEY_2:
				speed = 2
			KEY_3:
				speed = 3
			KEY_ESCAPE:
				_select(null)
			KEY_R:
				_gizmo("draft")
			KEY_P:
				_gizmo("post")
			KEY_F:
				_gizmo("repair")
			KEY_C:
				_gizmo("focus")
			KEY_T:
				_gizmo("treat")
			KEY_X:
				_gizmo("sendout")
			KEY_G:
				_gizmo("scavenge")
			KEY_F5:
				_quick_save()
			KEY_F9:
				_quick_load()
			KEY_TAB:
				# Tab goes round the people who are here and alive: not the lost, not those away
				var here: Array = []
				for q in sim.people:
					if not q.dead and q.away == null:
						here.append(q)
				if not here.is_empty():
					var i: int = here.find(selection.ref) if selection != null and selection.kind == "person" else -1
					var p = here[(i + 1) % here.size()]
					_select({"kind": "person", "ref": p})
					_focus(Vector2(p.x, p.y))
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------- loop --

func _process(delta: float) -> void:
	var dt := clampf(delta, 0.0, StepClock.MAX_FRAME)
	clock += dt
	# The rules only ever take whole steps of 1/30 s, however long the frame was,
	# so a seed plays the same game at any frame rate. Everything that is only
	# drawn (effects, flames, light, camera) runs on the frame's own time.
	for i in step_clock.advance(dt, speed):
		_sim_step()
	var rem := dt * speed
	while rem > 1e-6:
		var h := minf(rem, StepClock.STEP)
		_visual_step(h)
		rem -= h

	var kx := int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	var ky := int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	if kx != 0 or ky != 0:
		follow = null
		cam_center += Vector2(kx, ky) * dt * 700.0 / zoom_px
	if follow != null:
		cam_center += (Vector2(follow.x, follow.y) - cam_center) * minf(1.0, dt * 5.0)
	_clamp_camera()
	_apply_camera()
	_handle_events()
	_sync_views()
	lighting.update(sim.hour, sim.bell_rung, clock, fx.flash_lights())
	glow.t = clock
	glow.queue_redraw()
	overlay.queue_redraw()
	hud_t -= dt
	if hud_t <= 0.0:
		hud_t = 0.1
		hud.update_hud(sim, speed, sound_on, walkers)
		var near := 0
		for z in sim.zombies:
			if (z.state == "attack" or z.state == "approach") and Vector2(z.x, z.y).distance_to(cam_center) < 30.0:
				near += 1
		sound.set_ambience(lighting.dark, minf(1.0, near / 14.0), 0.1)
	if shot_path != "":
		frame_count += 1
		if frame_count == 50:
			RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		if frame_count == 60:
			bench_start = Time.get_ticks_usec()
		if frame_count > 60:
			var vp_rid := get_viewport().get_viewport_rid()
			bench_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu()
			bench_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
			bench_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		if frame_count == 10 and "--selftest" in OS.get_cmdline_user_args():
			_selftest()
		if frame_count == shot_frames:
			_take_shot()


## One step of the rules.
func _sim_step() -> void:
	sim.update(StepClock.STEP)
	sim_steps += 1


## The effects and the flames for `h` seconds of the game's time (a frame's time
## at the game's speed, in pieces of at most one step so a long frame at the top
## speed still moves the particles in small steps).
func _visual_step(h: float) -> void:
	fx.update(h)
	fire_t += h
	for f in fire_nodes:
		var big: bool = f.big
		var p: Vector2 = f.position / TILE
		if randf() < h * (14.0 if big else 5.0):
			fx.smoke(p.x + ((randf() - 0.5) * 2.0 if big else 0.0), p.y - (0.6 if big else 0.5), 0.35 if big else 0.2, big)
		if randf() < h * (10.0 if big else 4.0):
			fx.ember(p.x + ((randf() - 0.5) * 2.4 if big else 0.0), p.y - 0.4)


## Where an entity is drawn right now, in tiles: the interpolated position of
## its node (the rules' own position is up to a step ahead of it). The overlay
## puts its brackets, names and bars here so they stay on the character. A node
## that is out of sight is not moved, so its entity's own position is used.
func view_pos(e) -> Vector2:
	var n = pawn_nodes.get(e)
	return n.tile_pos() if n != null and n.visible else Vector2(e.x, e.y)


## Create, move and retire the nodes that draw people and walkers. Corpses
## that have settled are not redrawn, and when zoomed far out characters
## animate every other frame. Characters are drawn between their last two
## steps: the rules move them 30 times a second, the screen shows every frame.
func _sync_views() -> void:
	var view := view_rect().grow(3.0)
	var frame := Engine.get_process_frames()
	var lod := zoom_px < 26.0
	var alpha := step_clock.alpha()
	walkers = 0
	var alive := {}
	var i := 0
	for z in sim.zombies:
		i += 1
		alive[z] = true
		var dead: bool = z.state == "dead" or z.state == "dying"
		if not dead:
			walkers += 1
		if not pawn_nodes.has(z):
			_add_pawn(z, true, "z%d" % z.look_index)
		var n = pawn_nodes[z]
		if dead and n.get_parent() == entities:
			n.reparent(corpses)
		n.anim_t = clock
		n.visible = view.has_point(Vector2(z.x, z.y))
		if not n.visible:
			continue
		var redraw := true
		if z.state == "dead":
			redraw = z.dead_t < 0.2 or (z.dead_t > 55.0 and frame % 3 == 0)
		elif lod:
			redraw = (frame + i) % 2 == 0
		n.sync(redraw, sim_steps, alpha)
	for e in pawn_nodes.keys():
		if pawn_nodes[e].zombie and not alive.has(e):
			pawn_nodes[e].queue_free()
			pawn_nodes.erase(e)
			if selection != null and selection.ref == e:
				_select(null)
	for p in sim.people:
		var n = pawn_nodes[p]
		n.anim_t = clock
		n.visible = view.has_point(Vector2(p.x, p.y)) and p.away == null
		if n.visible:
			n.sync(true, sim_steps, alpha)
	var fire_view := view_rect().grow(4.0)
	for f in fire_nodes:
		f.visible = fire_view.has_point(f.position / TILE)
		if f.visible and frame % 2 == 0:
			f.tick(fire_t)
	ground_bits.queue_redraw()
	air.queue_redraw()
	if frame % 10 == 0:
		lanterns_node.queue_redraw()


func _draw_lanterns(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	var on: bool = lighting.lamp_level > 0.1
	for l in data.lights:
		if not l.get("lantern", false):
			continue
		ci.draw_rect(Rect2(l.x - 0.09, l.y - 0.13, 0.18, 0.24), Color("#2a2622"))
		ci.draw_rect(Rect2(l.x - 0.06, l.y - 0.09, 0.12, 0.16), Color("#ffd890") if on else Color("#8a7a5a"))


func _vol_at(x: float, y: float) -> float:
	return clampf(1.0 - Vector2(x, y).distance_to(cam_center) / 50.0, 0.12, 1.0)


func _handle_events() -> void:
	for e in sim.events:
		match e.type:
			"shot":
				sound.play("shot_%s" % e.weapon, _vol_at(e.x, e.y) * 0.8)
			"bell":
				sound.play("bell", 1.0, 0.0)
			"groan":
				if randf() < 0.6:
					var d := Vector2(e.x, e.y).distance_to(cam_center)
					sound.play("groan", minf(1.0, 10.0 / (d + 12.0) / 0.3), 0.12)
			"claw":
				if randf() < 0.35:
					sound.play("scrape_%s" % e.material, _vol_at(e.x, e.y))
			"crash":
				sound.play("crash")
			"bite":
				sound.play("bite")
			"reload":
				sound.play("reload", 0.8)
			"hammer":
				sound.play("hammer", 0.8, 0.1)
			"stab":
				sound.play("stab")
			"thud":
				sound.play("thud", _vol_at(e.x, e.y))
			"banner":
				hud.show_banner(e.text, e.sub)
			"day_start":
				_autosave()
	sim.events.clear()


## The dawn save: one file, written over at each new day. Not in a screenshot
## run, and not once the run is lost (that would replace the last good one).
func _autosave() -> void:
	if shot_path == "" and sim.over == "":
		SaveGame.write(sim, SaveGame.AUTO_PATH)


# ------------------------------------------------------------- automation --

func _parse_args() -> void:
	var advance := 0.0
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		var k := kv[0]
		var v := kv[1] if kv.size() > 1 else ""
		match k:
			"shot":
				shot_path = v
			"frames":
				shot_frames = int(v)
			"hour":
				sim.minutes = float(v) * 60.0
				sim.phase = Sim.phase_at(sim.minutes)
				var hh := float(v)
				sim.bell_rung = hh >= 19.0 or hh < 6.0
				# the game clock follows: it counts minutes from 07:00 on day 1
				sim.clock_min = (sim.day - 1) * 1440.0 + fposmod(sim.minutes - 420.0, 1440.0)
			"advance":
				advance = float(v)
			"cam":
				var c := v.split(",")
				cam_center = Vector2(float(c[0]), float(c[1]))
				if c.size() > 2:
					zoom_px = float(c[2])
			"select":
				for p in sim.people:
					if p.id == v:
						_select({"kind": "person", "ref": p})
			"speed":
				speed = int(v)
			"breach":
				var seg = sim.segments[int(v)]
				sim._damage_segment(seg, seg.hp + 1.0)
			"damage":
				# --damage=N:F leaves wall section N at the fraction F of its health
				var nf := v.split(":")
				if nf.size() == 2 and int(nf[0]) >= 0 and int(nf[0]) < sim.segments.size():
					var worn = sim.segments[int(nf[0])]
					worn.hp = worn.max_hp * clampf(float(nf[1]), 0.0, 1.0)
					sim._segment_state(worn)
			"nohud":
				hud.visible = false
			"msaa":
				get_viewport().msaa_2d = int(v) as Viewport.MSAA
			"nolights":
				lighting.visible = false
	if advance > 0.0:
		var steps := int(advance * 30.0)
		for i in steps:
			_sim_step()
			_visual_step(StepClock.STEP)
		for e in sim.events:
			if e.type == "banner":
				hud.show_banner(e.text, e.sub)
		sim.events.clear()


func _tile_to_screen(t: Vector2) -> Vector2:
	return (t - cam_center) * zoom_px + _vp() / 2.0


func _click(pos: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.position = pos
		ev.pressed = pressed
		_unhandled_input(ev)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	_unhandled_input(ev)


## Drives the real input handlers once, so broken code paths show up in logs.
func _selftest() -> void:
	var ruth = sim.people[0]
	_focus(Vector2(ruth.x, ruth.y))
	_apply_camera()
	_click(_tile_to_screen(Vector2(ruth.x, ruth.y - 0.3)), MOUSE_BUTTON_LEFT)
	print("selftest: click selects ", selection.ref.name if selection != null else "nothing")
	_click(_tile_to_screen(Vector2(ruth.x + 3, ruth.y + 6)), MOUSE_BUTTON_RIGHT)
	print("selftest: right-click order ", ruth.order, " drafted ", ruth.drafted)
	for k in [KEY_R, KEY_R, KEY_P, KEY_F, KEY_C, KEY_TAB, KEY_TAB, KEY_SPACE, KEY_SPACE, KEY_2, KEY_1]:
		_key(k)
	print("selftest: keys ok, selected ", selection.ref.name, ", speed ", speed)
	var z0 := zoom_px
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 1.0
	wheel.position = _vp() / 2.0
	_unhandled_input(wheel)
	print("selftest: wheel zoom %.1f -> %.1f" % [z0, zoom_px])
	var c0 := cam_center
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(400, 400)
	_unhandled_input(press)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(300, 350)
	_unhandled_input(move)
	press.pressed = false
	press.position = move.position
	_unhandled_input(press)
	print("selftest: drag pans camera by ", (cam_center - c0).snapped(Vector2(0.01, 0.01)))
	for z in sim.zombies:
		if z.state == "attack":
			_focus(Vector2(z.x, z.y))
			_click(_tile_to_screen(Vector2(z.x, z.y - 0.3)), MOUSE_BUTTON_LEFT)
			break
	print("selftest: walker selected: ", selection != null and selection.kind == "zombie")
	var bus = sim.segments[3]
	_focus(bus.center)
	_click(_tile_to_screen(Vector2(bus.obj.cx, bus.obj.cy)), MOUSE_BUTTON_LEFT)
	print("selftest: segment selected: ", selection.ref.name if selection != null else "nothing")
	bus.hp = bus.max_hp * 0.5
	_gizmo("repair")
	var fixer = null
	for p in sim.people:
		if p.repair == bus:
			fixer = p
	print("selftest: repair ordered for ", fixer.name if fixer != null else "nobody")
	_key(KEY_ESCAPE)
	print("selftest: done, selection cleared: ", selection == null)
	var loaded := 0
	for k in sound.streams:
		loaded += sound.streams[k].size()
	var w: AudioStreamWAV = sound.wind.stream
	print("selftest: %d sounds loaded; wind loop %s, %.1f s, playing %s" % [loaded, w.loop_mode == AudioStreamWAV.LOOP_FORWARD, w.get_length(), sound.wind.playing])


func _take_shot() -> void:
	print("clock at shot: game %.1f min, real %.1f s, sim.t %.1f s" % [sim.minutes, clock, sim.t])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	var frames := frame_count - 60
	var avg := 0.0
	if frames > 0 and bench_start > 0:
		avg = frames / ((Time.get_ticks_usec() - bench_start) / 1e6)
	print("shot saved: %s (%dx%d), walkers %d, avg fps after warm-up %.1f" % [shot_path, img.get_width(), img.get_height(), walkers, avg])
	if frames > 0:
		print("  per frame: process %.2f ms, render cpu %.2f ms, gpu %.2f ms" % [bench_proc / frames, bench_cpu / frames, bench_gpu / frames])
	get_tree().quit()
