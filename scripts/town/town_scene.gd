## The town as a scene (feature/town-core): the avatar alone in the start house of a 192 x 192 town, in the real sim (scripts/town/town_run.gd: the colony's Sim for a
## place, the real dead, the real shooting) and the real renderer (World, PawnNode, FX), with the dead of the town dormant until the avatar, a shot or a light wakes them.
## Started by `--town` (alias `--spike-town`) on the game's command line (scripts/main.gd hands the screen to it).
##
## KEYS: WASD walk, the mouse aims and the left button fires, R reload, F melee, N shout (a noise: wakes the dead within 30 tiles and sends them), L light (wakes within 12, they wander),
## M the whole town as a map and back, the wheel zooms, F3 the numbers, F4 roofs on/off, Esc quits.
##
## FLAGS (after `--town`): --seed=N (the town, 1), --cap=N (the most dead awake at once, 100), --ai=hunt|chase (the base's hunt or the town's chase, chase), --crowd=square|grid (grid),
## --roofs=house|multi|off (house), --size=WxH, --cam=x,y,zoom (a fixed camera: the avatar does not move it), --avatar-at=x,y, --wake=x,y,r (wake the dead round that point at the
## start, sent after the avatar), --shot=path (a screenshot after --frames=N frames, 90, then quit), --nohud, --overlay (the numbers on), --bench=SECONDS (walk the town by the roads,
## print the frame and step numbers, quit; vsync off), --bench-zoom=px.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/town/town_world.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")
const TownRun := preload("res://scripts/town/town_run.gd")
const TownRoofs := preload("res://scripts/town/town_roofs.gd")
const FX := preload("res://scripts/render/fx.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const DrawNode := preload("res://scripts/render/draw_node.gd")
const StepClock := preload("res://scripts/sim/step_clock.gd")

const TILE := GD.TILE
const MAX_ZOOM := 84.0
const CAMERA_EASE := 8.0
const NODES_PER_FRAME := 8
const OVERLAY_EVERY := 0.25

var args := {}
var state := "gen"
var gen
var town: Dictionary
var data: Dictionary
var world
var roofs
var run
var fx
var decals: Node2D
var corpses: Node2D
var entities: Node2D
var camera: Camera2D
var overlay_layer: CanvasLayer
var overlay: Label
var loading: Label
var pawn_nodes := {}
var step_clock := StepClock.new()
var sim_steps := 0
var cam_center := Vector2(96, 96)
var zoom_px := 36.0
var play_zoom := 36.0
var map_view := false
var fixed_cam := false
var clock := 0.0
var frames := 0
var _overlay_t := 0.0
var _step_us := PackedFloat32Array()
var _step_ring := 0
var _frame_ms := PackedFloat32Array()
var _draws := PackedFloat32Array()
var _cpu_ms := PackedFloat32Array()
var _script_ms := PackedFloat32Array()
var _tick_t0 := 0
var _shot_wait := 0
var _bench_left := -1.0
var _bench_route: Array = []
var _bench_leg := 0
var _bench_path: Array = []
var _bench_i := 0
var _load_t0 := 0
var load_report := {}
var _chunks_shown := 0
var _nodes_made_frame := 0
var _frame_worst_nodes := 0
var _last_script_ms := 0.0
var _tree_nodes: Array = []
var _lod_low := false
## Below this zoom (px per tile) the pictures of the things (furniture, cars, trees) are not drawn: the town as a map is the ground, the paint, the roofs and the dead.
const LOD_ZOOM := 12.0
var _node_costs := PackedFloat32Array()
var _node_us := 0
var _node_n := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			var kv := s.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	# in a browser the flags are the page's query: `index.html?town&cap=60&overlay`
	if OS.has_feature("web"):
		var qs := String(JavaScriptBridge.eval("window.location.search"))
		for part in qs.trim_prefix("?").split("&", false):
			var kv2 := String(part).split("=", true, 1)
			args[kv2[0]] = kv2[1] if kv2.size() > 1 else "1"
	_load_t0 = Time.get_ticks_usec()
	data = GD.load_all()
	_fit_window()
	loading = Label.new()
	loading.text = "Building the town..."
	loading.position = Vector2(40, 40)
	loading.add_theme_font_size_override("font_size", 22)
	var ll := CanvasLayer.new()
	ll.layer = 20
	ll.add_child(loading)
	add_child(ll)
	gen = TownGen.new()
	gen.begin(int(args.get("seed", "1")), {})
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if args.has("bench"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _fit_window() -> void:
	var logical := Vector2i(1280, 800)
	if args.has("size"):
		var wh := String(args.size).split("x")
		logical = Vector2i(int(wh[0]), int(wh[1]))
	var win := get_window()
	if win.mode == Window.MODE_WINDOWED and not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var s := DisplayServer.screen_get_scale(win.current_screen)
		var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
		var want := Vector2i(Vector2(logical) * s)
		want.x = mini(want.x, int(usable.size.x * 0.94))
		want.y = mini(want.y, int(usable.size.y * 0.94))
		win.size = want
		win.position = usable.position + (usable.size - want) / 2
	var sc := DisplayServer.screen_get_scale()
	if sc <= 0.0:
		sc = 1.0
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(maxi(1, int(win.size.x / sc)), maxi(1, int(win.size.y / sc)))


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


# ---------------------------------------------------------------------- loading --

func _process(delta: float) -> void:
	match state:
		"gen":
			if gen.step(8.0):
				load_report["gen_ms"] = float(gen.result().stats.ms.total)
				town = gen.result()
				world = World.new()
				world.name = "World"
				add_child(world)
				world.begin_build(town.data)
				state = "world"
			loading.text = "Building the town... %d%%" % int(gen.progress() * 50.0)
		"world":
			var done: bool = world.step_build(8.0)
			loading.text = "Building the town... %d%%" % int(50.0 + world.build_progress() * 50.0)
			if done:
				_finish_loading()
		"ready":
			_tick(delta)


func _finish_loading() -> void:
	var t0 := Time.get_ticks_usec()
	fx_setup()
	roofs = TownRoofs.new()
	roofs.name = "Roofs"
	world.add_child(roofs)
	roofs.setup(town, data, String(args.get("roofs", "house")))
	var ai := String(args.get("ai", "chase")) == "chase"
	var grid := String(args.get("crowd", "grid")) == "grid"
	run = TownRun.new(town, world, fx, int(args.get("cap", "100")), ai, grid)
	var avatar_at: Vector2 = town.start.pos
	if args.has("avatar-at"):
		var c := String(args["avatar-at"]).split(",")
		avatar_at = Vector2(float(c[0]), float(c[1]))
		run.avatar_p.x = avatar_at.x
		run.avatar_p.y = avatar_at.y
	run.invulnerable = args.has("bench") or args.has("invulnerable")
	# the trees stand among the people (y-sorted)
	for tr in town.data.trees:
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
		_tree_nodes.append(s)
	var avatar_node := PawnNode.new()
	avatar_node.work_poses = false
	avatar_node.setup(run.avatar_p, false, data, "ruth")
	entities.add_child(avatar_node)
	pawn_nodes[run.avatar_p] = avatar_node
	camera = Camera2D.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()
	var vp := _vp()
	play_zoom = clampf(minf(vp.x / 30.0, vp.y / 17.0), 28.0, 52.0)
	zoom_px = play_zoom
	cam_center = avatar_at
	if args.has("cam"):
		var c := String(args.cam).split(",")
		cam_center = Vector2(float(c[0]), float(c[1]))
		if c.size() > 2:
			zoom_px = float(c[2])
		fixed_cam = true
	if args.has("zoom"):
		zoom_px = float(args.zoom)
	_apply_camera()
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 10
	add_child(overlay_layer)
	overlay = Label.new()
	overlay.position = Vector2(10, 8)
	overlay.add_theme_font_size_override("font_size", 14)
	overlay.add_theme_color_override("font_color", Color(1, 1, 0.85))
	overlay.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	overlay.add_theme_constant_override("shadow_offset_x", 1)
	overlay.add_theme_constant_override("shadow_offset_y", 1)
	overlay.visible = args.has("overlay") and not args.has("nohud")
	overlay_layer.add_child(overlay)
	loading.get_parent().visible = false
	if args.has("wake"):
		var w := String(args.wake).split(",")
		run.field._wake_near(Vector2(float(w[0]), float(w[1])), float(w[2]), "stage", run.avatar_p)
	if args.has("bench"):
		_bench_left = float(args.bench)
		var cz := float(args.get("bench-zoom", str(play_zoom)))
		zoom_px = cz
		_bench_route = [Vector2(94.5, 91.5), Vector2(158.5, 91.5), Vector2(158.5, 155.5), Vector2(30.5, 155.5), Vector2(30.5, 27.5), Vector2(94.5, 27.5), Vector2(94.5, 91.5)]
		if not args.has("avatar-at"):
			run.avatar_p.x = 94.5
			run.avatar_p.y = 91.5
	load_report["finish_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	load_report["world_ms"] = world.build_ms
	load_report["total_ms"] = float(Time.get_ticks_usec() - _load_t0) / 1000.0
	state = "ready"
	_shot_wait = int(args.get("frames", "90"))
	print("town ready: seed %s, %d houses, %d dead records, gen %.0f ms, world %s, to ready %.0f ms (wall, stepped across frames)" % [str(town.seed), town.houses.size(), town.dead.size(), load_report.gen_ms, JSON.stringify(world.build_ms), load_report.total_ms])


func fx_setup() -> void:
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
	var glow := DrawNode.new()
	glow.name = "Glow"
	glow.z_index = 9
	glow.painter = fx.draw_add
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = mat
	world.add_child(glow)


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


# -------------------------------------------------------------------- the frame --

func _min_zoom() -> float:
	var vp := _vp()
	return maxf(2.0, minf(vp.x / (float(world.W) + 2.0), vp.y / (float(world.H) + 2.0)))


func _apply_camera() -> void:
	zoom_px = clampf(zoom_px, _min_zoom(), MAX_ZOOM)
	camera.position = cam_center * TILE
	camera.zoom = Vector2.ONE * (zoom_px / TILE)


func view_rect() -> Rect2:
	var vp := _vp()
	return Rect2(cam_center - vp / 2.0 / zoom_px, vp / zoom_px)


func to_tile(screen: Vector2) -> Vector2:
	return cam_center + (screen - _vp() / 2.0) / zoom_px


func _tick(dt: float) -> void:
	_tick_t0 = Time.get_ticks_usec()
	dt = clampf(dt, 0.0, StepClock.MAX_FRAME)
	clock += dt
	frames += 1
	_hands(dt)
	for i in step_clock.advance(dt, 1.0):
		var t := Time.get_ticks_usec()
		run.update(StepClock.STEP)
		sim_steps += 1
		_note_step(float(Time.get_ticks_usec() - t))
	fx.update(dt)
	# the camera follows the avatar
	var p = run.avatar_p
	if not fixed_cam:
		var goal := Vector2(p.x, p.y) if not map_view else Vector2(float(world.W) / 2.0, float(world.H) / 2.0)
		cam_center += (goal - cam_center) * (1.0 - exp(-CAMERA_EASE * dt))
	_apply_camera()
	if (zoom_px < LOD_ZOOM) != _lod_low:
		_set_lod(zoom_px < LOD_ZOOM)
	_chunks_shown = world.show_chunks(view_rect().grow(2.0))
	roofs.update(TownGen.house_at(town, p.x, p.y), dt)
	_sync_views()
	_overlay_t -= dt
	if overlay != null and _overlay_t <= 0.0:
		_overlay_t = OVERLAY_EVERY
		if overlay.visible:
			overlay.text = overlay_text()
	_record(dt, float(Time.get_ticks_usec() - _tick_t0) / 1000.0)
	if _bench_left >= 0.0:
		_bench_left -= dt
		if _bench_left < 0.0:
			_bench_report()
			get_tree().quit()
	elif args.has("shot") and frames >= _shot_wait:
		_save_shot()
		get_tree().quit()


func _set_lod(low: bool) -> void:
	_lod_low = low
	for k in world.layers:
		world.layers[k].visible = not low
	for t in _tree_nodes:
		t.visible = not low


func _note_step(us: float) -> void:
	if _step_us.size() < 60:
		_step_us.append(us)
	else:
		_step_us[_step_ring % 60] = us
		_step_ring += 1


func _hands(dt: float) -> void:
	var move := Vector2.ZERO
	if _bench_left >= 0.0:
		move = _bench_steer()
	else:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
	var aim := to_tile(get_viewport().get_mouse_position())
	var fire := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not args.has("shot")
	if args.has("hold-fire"):
		fire = true
	run.sim.avatar.set_input(move, aim, fire)


## The bench's walker: along the roads of the town by the people's grid.
func _bench_steer() -> Vector2:
	var p = run.avatar_p
	if _bench_i >= _bench_path.size():
		_bench_leg = (_bench_leg + 1) % (_bench_route.size() - 1)
		var tgt: Vector2 = _bench_route[_bench_leg + 1]
		_bench_path = run.sim.path_p.find(world.solid_p, p.x, p.y, tgt.x, tgt.y)
		_bench_i = 0
		if _bench_path.is_empty():
			_bench_path = [tgt]
	var wp: Vector2 = _bench_path[_bench_i]
	var to := wp - Vector2(p.x, p.y)
	if to.length() < 0.5:
		_bench_i += 1
	# a shot's noise now and then, so that the dead come
	if frames % 180 == 90:
		run.sim._shot_noise(p)
	return to


func _unhandled_input(ev: InputEvent) -> void:
	if state != "ready":
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_F3:
				overlay.visible = not overlay.visible
			KEY_F4:
				roofs.visible = not roofs.visible
			KEY_M:
				map_view = not map_view
				zoom_px = _min_zoom() if map_view else play_zoom
			KEY_R:
				run.sim.avatar.reload()
			KEY_F:
				run.sim.avatar.melee()
			KEY_N:
				run.field.noise(Vector2(run.avatar_p.x, run.avatar_p.y), run.avatar_p)
			KEY_L:
				run.field.light(Vector2(run.avatar_p.x, run.avatar_p.y), 12.0)
			KEY_ESCAPE:
				get_tree().quit()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_px *= 1.12
			play_zoom = zoom_px
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_px /= 1.12
			play_zoom = zoom_px


## Makes, moves and retires the nodes of the dead (as raid_scene.gd `_sync_views`), a few new ones a frame.
func _sync_views() -> void:
	var view := view_rect().grow(3.0)
	var frame := Engine.get_process_frames()
	var alpha := step_clock.alpha()
	var alive := {}
	var made := 0
	var node_t := Time.get_ticks_usec()
	for z in run.sim.zombies:
		alive[z] = true
		var dead: bool = z.state == "dead" or z.state == "dying"
		var in_view := view.has_point(Vector2(z.x, z.y))
		if not pawn_nodes.has(z):
			if not in_view or made >= NODES_PER_FRAME:
				continue
			made += 1
			var t_node := Time.get_ticks_usec()
			var n := PawnNode.new()
			n.work_poses = false
			n.setup(z, true, data, "z%d" % z.look_index)
			entities.add_child(n)
			pawn_nodes[z] = n
			_node_costs.append(float(Time.get_ticks_usec() - t_node))
		var n2 = pawn_nodes[z]
		if dead and n2.get_parent() == entities:
			n2.reparent(corpses)
		n2.anim_t = clock
		n2.visible = in_view
		if not n2.visible:
			continue
		var redraw := true
		if z.state == "dead":
			redraw = z.dead_t < 0.2 or (z.dead_t > 55.0 and frame % 3 == 0)
		n2.sync(redraw, sim_steps, alpha)
	for e in pawn_nodes.keys():
		if pawn_nodes[e].zombie and not alive.has(e):
			pawn_nodes[e].queue_free()
			pawn_nodes.erase(e)
	var an = pawn_nodes[run.avatar_p]
	an.anim_t = clock
	an.sync(true, sim_steps, alpha)
	if made > 0:
		_node_us += Time.get_ticks_usec() - node_t
		_node_n += made
		_frame_worst_nodes = maxi(_frame_worst_nodes, made)


# ------------------------------------------------------------- numbers, shots --

func _record(dt: float, script_ms: float) -> void:
	_last_script_ms = script_ms
	if frames < 30:
		return
	_frame_ms.append(dt * 1000.0)
	_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_script_ms.append(script_ms)
	var rid := get_viewport().get_viewport_rid()
	_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu())


func overlay_text() -> String:
	var c: Dictionary = run.field.counts()
	var step_ms := 0.0
	var step_max := 0.0
	for v in _step_us:
		step_ms += v
		step_max = maxf(step_max, v)
	step_ms = step_ms / maxf(1.0, float(_step_us.size())) / 1000.0
	var p = run.avatar_p
	var house := TownGen.house_at(town, p.x, p.y)
	var room := TownGen.room_at(town, p.x, p.y)
	var chase := 0
	for z in run.sim.zombies:
		if z.state == "chase" or z.state == "hunt":
			chase += 1
	var rid := get_viewport().get_viewport_rid()
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	var lines: Array = []
	lines.append("fps %d   frame %.1f ms   town script %.2f ms   render cpu %.2f ms   draw calls %d   objects %d" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()), _last_script_ms, cpu, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	lines.append("dead: awake %d (cap %d, after the avatar %d, in the sim %d with corpses)   dormant %d   killed %d   woke %d  slept %d" % [c.active, run.field.active_cap, chase, run.sim.zombies.size(), c.dormant, c.killed, run.field.woke_total, run.field.slept_total])
	lines.append("rules step %.2f ms mean (last 60), %.2f ms worst   steps %d   pawn nodes %d   scene nodes %d   chunks painted %d   roofs closed %d" % [step_ms, step_max / 1000.0, sim_steps, pawn_nodes.size(), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), _chunks_shown, roofs.shown])
	var where := "outside"
	if house >= 0:
		where = "house %d (%s), %s" % [house, town.houses[house].kind, town.rooms[room].name if room >= 0 else "a doorway"]
		var left: Dictionary = run.field.dead_in_house(house)
		where += "   dead left in it: %d" % int(left.left)
	lines.append("avatar (%.1f, %.1f)  hp %d  ammo in magazine %d   in %s   kills %d   zoom %.1f px/tile" % [p.x, p.y, int(p.hp), int(p.mag), where, run.sim.kills, zoom_px])
	return "\n".join(lines)


func _save_shot() -> void:
	if DisplayServer.get_name() == "headless":
		print("shot skipped: headless")
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(String(args.shot))
	print("shot saved: %s (%dx%d); %s" % [String(args.shot), img.get_width(), img.get_height(), overlay_text().replace("\n", " | ")])


static func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[mini(b.size() - 1, int(float(b.size()) * q))]


static func _mean(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(1.0, float(a.size()))


func _bench_report() -> void:
	var c: Dictionary = run.field.counts()
	var fps := 1000.0 / maxf(0.001, _mean(_frame_ms))
	print("BENCH town %s: zoom %.1f px/tile, cap %d, ai %s, crowd %s, roofs %s | %d frames: frame ms mean %.2f p50 %.2f p95 %.2f p99 %.2f max %.2f (uncapped %.0f fps) | town script ms mean %.2f p95 %.2f max %.2f | render cpu ms mean %.2f p95 %.2f | draw calls mean %.0f max %.0f | active mean-end %d | woke %d slept %d | pawn nodes %d, made in a frame at most %d, one costs %.0f us median %.0f p95 %.0f max | rules step %.2f ms mean (60 last)" % [
		"", zoom_px, run.field.active_cap, String(args.get("ai", "chase")), String(args.get("crowd", "grid")), String(args.get("roofs", "house")), _frame_ms.size(),
		_mean(_frame_ms), _pct(_frame_ms, 0.5), _pct(_frame_ms, 0.95), _pct(_frame_ms, 0.99), _pct(_frame_ms, 1.0), fps,
		_mean(_script_ms), _pct(_script_ms, 0.95), _pct(_script_ms, 1.0), _mean(_cpu_ms), _pct(_cpu_ms, 0.95), _mean(_draws), _pct(_draws, 1.0), c.active, run.field.woke_total, run.field.slept_total,
		pawn_nodes.size(), _frame_worst_nodes, _pct(_node_costs, 0.5), _pct(_node_costs, 0.95), _pct(_node_costs, 1.0), _mean(_step_us) / 1000.0])
