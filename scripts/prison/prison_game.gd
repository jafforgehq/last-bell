## EXPERIMENT (prison extraction): the whole game loop in one scene. BASE: a hand-authored prison compound (prison_base.gd) with ten people at work (prison_crew.gd) and a mass of dead in the pen in
## front of the gate. GO OUT (E at the gate or the truck): a generated 64 x 64 town (TownGen, blocks 2) played with the real Sim (avatar, shooting, melee, search, dormant dead that wake near you).
## EXTRACT: stand in a pickup ring for 2 s, a short cutscene, and the loot (the raid sim's stock) is banked in the base's stores. DIE in the raid: the pack is lost, same cutscene back.
## Keys: WASD walk, mouse aim, left button fire (raid only), R reload, F melee, E use/search/go out, Shift sprint is not wired, wheel zoom, M overview, Esc quit.
## Flags: --shot=path --frames=N (screenshot then quit), --raid (start in a raid), --at=x,y (avatar position), --seed=N, --auto=raid|extract|die (scripted run for checks), --cam=x,y,zoom.
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
const Base := preload("res://scripts/prison/prison_base.gd")
const Crew := preload("res://scripts/prison/prison_crew.gd")
const Sound := preload("res://scripts/audio/sound.gd")
const DogNode := preload("res://scripts/render/dog_node.gd")
const DAY_MIN_PER_SEC := 4.0    # 6 real minutes a day
const GUARD_RANGE := 11.0
const FENCE_ZONE := 5.0    # a guard shoots what comes within this many tiles of the fence line

const TILE := GD.TILE
const CAMERA_EASE := 8.0
const EXTRACT_R := 2.2
const EXTRACT_S := 2.0
const LOADOUT_AMMO := 40.0
const STOCK_KEYS := ["food", "water", "ammo", "meds", "scrap"]

var args := {}
var data: Dictionary
var mode := "base"
var stage: Node2D
var world
var run
var fx
var town: Dictionary
var base
var crew
var entities: Node2D
var corpses: Node2D
var decals: Node2D
var roofs
var camera: Camera2D
var pawn_nodes := {}
var step_clock := StepClock.new()
var clock := 0.0
var frames := 0
var sim_steps := 0
var zoom_px := 40.0
var play_zoom := 40.0
var cam_center := Vector2(48, 48)
var map_view := false
var stores := {"food": 40.0, "water": 60.0, "ammo": 80.0, "meds": 6.0, "scrap": 30.0}
var raids := 0
var exits: Array = []
var extract_t := 0.0
var busy := false    # a cutscene is playing
var overlay: Node2D    # world-space drawing (labels, exits, tower decks)
var hud: CanvasLayer
var hud_label: Label
var prompt_label: Label
var msg_label: Label
var bars: Control
var fade: ColorRect
var cap_label: Label
var cut_art: Control
var cut_x := -1.0
var _msg_t := 0.0
var _prompt: Dictionary = {}
var _loadout := 0.0
var _auto_t := 0.0
var _armed := false
var _shot_wait := 90
var _quit_after := false
var sound
var tod := 8.0    # hour of the day
var night_rect: ColorRect
var glow: Control
var radial_tex: Texture2D
var mini_tex: ImageTexture
var guard_cd := {}
var alarm_t := 0.0
var alarm_cd := 0.0
var _repl_t := 0.0
var _trickle_t := 0.0
var shots_fired := 0
var dog


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			var kv := s.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	data = GD.load_all()
	_fit_window()
	_make_hud()
	_shot_wait = int(args.get("frames", "90"))
	if args.has("raid") or String(args.get("auto", "")) != "":
		_enter_raid()
	else:
		_enter_base()


func _fit_window() -> void:
	var win := get_window()
	if win.mode == Window.MODE_WINDOWED and not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var s := DisplayServer.screen_get_scale(win.current_screen)
		var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
		var want := Vector2i(Vector2(1280, 800) * s)
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


# ------------------------------------------------------------------------- hud --

func _lbl(size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 0.88))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _make_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	hud_label = _lbl(18, Vector2(14, 10))
	hud.add_child(hud_label)
	prompt_label = _lbl(22, Vector2(0, 0))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(prompt_label)
	msg_label = _lbl(20, Vector2(0, 0))
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(msg_label)
	bars = Control.new()
	bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.draw.connect(_draw_bars)
	hud.add_child(bars)
	sound = Sound.new()
	add_child(sound)
	sound.setup(data.sounds)
	var nl := CanvasLayer.new()
	nl.layer = 5
	add_child(nl)
	night_rect = ColorRect.new()
	night_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	night_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mm := CanvasItemMaterial.new()
	mm.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	night_rect.material = mm
	night_rect.color = Color(1, 1, 1, 1)
	nl.add_child(night_rect)
	glow = Control.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var am := CanvasItemMaterial.new()
	am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = am
	glow.draw.connect(_draw_glow)
	nl.add_child(glow)
	var cl := CanvasLayer.new()
	cl.layer = 30
	add_child(cl)
	cut_art = Control.new()
	cut_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	cut_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cut_art.draw.connect(_draw_cut)
	cl.add_child(cut_art)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(fade)
	cap_label = _lbl(30, Vector2(0, 0))
	cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_label.modulate.a = 0.0
	cl.add_child(cap_label)


func _say(t: String, secs: float = 3.5) -> void:
	msg_label.text = t
	_msg_t = secs


func _layout_labels() -> void:
	var v := _vp()
	prompt_label.size = Vector2(v.x, 30)
	prompt_label.position = Vector2(0, v.y - 120)
	msg_label.size = Vector2(v.x, 30)
	msg_label.position = Vector2(0, 74)
	cap_label.size = Vector2(v.x, 80)
	cap_label.position = Vector2(0, v.y * 0.5 + 60)


func _stock_line() -> String:
	var s := ""
	for k in STOCK_KEYS:
		s += "%s %d    " % [String(k).capitalize(), int(stores[k])]
	return s


func _draw_bars() -> void:
	if run == null:
		return
	var v := _vp()
	var p = run.avatar_p
	var hp := clampf(float(p.hp) / 100.0, 0.0, 1.0)
	bars.draw_rect(Rect2(14, v.y - 34, 220, 14), Color(0, 0, 0, 0.6))
	bars.draw_rect(Rect2(14, v.y - 34, 220.0 * hp, 14), Color(0.8, 0.2, 0.18))
	var up: Dictionary = run.sim.uses.progress()
	if float(up.of) > 0.0:
		var f := clampf(float(up.t) / float(up.of), 0.0, 1.0)
		bars.draw_rect(Rect2(v.x / 2 - 110, v.y - 84, 220, 12), Color(0, 0, 0, 0.6))
		bars.draw_rect(Rect2(v.x / 2 - 110, v.y - 84, 220.0 * f, 12), Color(0.95, 0.8, 0.3))
	if mode == "raid" and extract_t > 0.0:
		bars.draw_rect(Rect2(v.x / 2 - 110, v.y - 84, 220, 12), Color(0, 0, 0, 0.6))
		bars.draw_rect(Rect2(v.x / 2 - 110, v.y - 84, 220.0 * clampf(extract_t / EXTRACT_S, 0, 1), 12), Color(0.4, 0.9, 0.5))
	_draw_minimap(v)
	if mode == "raid" and not busy:
		# arrows to the pickups at the edge of the screen
		for e in exits:
			var scr := (Vector2(e) - cam_center) * zoom_px + v / 2.0
			if Rect2(Vector2(30, 30), v - Vector2(60, 60)).has_point(scr):
				continue
			var dir := (scr - v / 2.0).normalized()
			var edge := v / 2.0 + dir * minf((v.x / 2 - 40) / maxf(absf(dir.x), 0.001), (v.y / 2 - 40) / maxf(absf(dir.y), 0.001))
			bars.draw_colored_polygon(PackedVector2Array([edge + dir * 14, edge + dir.rotated(2.5) * 12, edge + dir.rotated(-2.5) * 12]), Color(0.4, 1, 0.5))


# ------------------------------------------------------------------------ stage --

func _free_stage() -> void:
	if stage != null:
		stage.queue_free()
	if camera != null:
		camera.queue_free()
	if overlay != null:
		overlay = null
	pawn_nodes.clear()
	roofs = null
	run = null
	crew = null


func _make_stage(the_town: Dictionary, with_roofs: bool) -> void:
	_free_stage()
	town = the_town
	stage = Node2D.new()
	add_child(stage)
	move_child(stage, 0)
	world = World.new()
	world.name = "World"
	stage.add_child(world)
	world.build(town.data)
	if world.looks.has("tree") and not (world.looks.tree as Array).is_empty():
		var green = world.looks.tree[0]    # the border belt: one green look in all three slots, no orange and yellow wall
		world.looks["tree"] = [green, green, green]
	decals = Node2D.new()
	decals.z_index = 5
	world.add_child(decals)
	fx = FX.new()
	radial_tex = _radial_texture()
	fx.setup(data, decals, radial_tex)
	fx.combat.sound = sound
	guard_cd.clear()
	alarm_t = 0.0
	var gb := DrawNode.new()
	gb.z_index = 5
	gb.painter = fx.draw_ground_bits
	world.add_child(gb)
	corpses = Node2D.new()
	corpses.z_index = 5
	world.add_child(corpses)
	entities = Node2D.new()
	entities.z_index = 6
	entities.y_sort_enabled = true
	world.add_child(entities)
	var air := DrawNode.new()
	air.z_index = 8
	air.painter = fx.draw_air
	world.add_child(air)
	var glow := DrawNode.new()
	glow.z_index = 9
	glow.painter = fx.draw_add
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = mat
	world.add_child(glow)
	if with_roofs:
		roofs = TownRoofs.new()
		world.add_child(roofs)
		roofs.setup(town, data, "house")
	run = TownRun.new(town, world, fx, 100, true, true)
	run.sim.feel = fx.combat
	fx.combat.listener = Vector2(run.avatar_p.x, run.avatar_p.y)
	mini_tex = _mini_texture(town.data)
	if dog != null:
		dog = null
	for tr in town.data.trees:
		var s := Sprite2D.new()
		var box: Array = data.tree.box
		var dens := float(data.tree.density)
		s.texture = GD.tex(tr.file)
		s.centered = false
		s.offset = Vector2(box[0], box[1]) * dens
		s.scale = Vector2.ONE * (TILE / dens)
		s.position = Vector2(tr.x, tr.y) * TILE
		entities.add_child(s)
	var an := PawnNode.new()
	an.work_poses = false
	an.setup(run.avatar_p, false, data, "ruth")
	entities.add_child(an)
	pawn_nodes[run.avatar_p] = an
	overlay = DrawNode.new()
	overlay.z_index = 12
	overlay.painter = _paint_overlay
	world.add_child(overlay)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	var vp := _vp()
	play_zoom = clampf(minf(vp.x / 30.0, vp.y / 17.0), 28.0, 52.0)
	zoom_px = play_zoom
	map_view = false


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


# ----------------------------------------------------------------------- modes --

func _enter_base() -> void:
	mode = "base"
	base = Base.new()
	var t: Dictionary = base.build(1)
	_make_stage(t, false)
	run.invulnerable = true
	run.sim.quiet = true
	run.field.wake_r = 45.0
	run.field.sleep_r = 80.0
	run.field.active_cap = 100
	run.sim.stock = stores.duplicate()
	run.avatar_p.x = Base.SPAWN.x
	run.avatar_p.y = Base.SPAWN.y
	run.sim.minutes = 8.0 * 60.0
	crew = Crew.new()
	crew.setup(run.sim, world, base, data)
	for m in crew.members:
		var n := PawnNode.new()
		n.setup(m.p, false, data, String(m.key))
		if m.def.has("scale"):
			n.scale = Vector2.ONE * float(m.def.scale)
		entities.add_child(n)
		m["node"] = n
	dog = DogNode.new()
	dog.setup(world.solid_p, world.W, 7)
	entities.add_child(dog)
	if args.has("at"):
		var c := String(args.at).split(",")
		run.avatar_p.x = float(c[0])
		run.avatar_p.y = float(c[1])
	cam_center = Vector2(run.avatar_p.x, run.avatar_p.y)
	if args.has("cam"):
		var cc := String(args.cam).split(",")
		cam_center = Vector2(float(cc[0]), float(cc[1]))
		if cc.size() > 2:
			zoom_px = float(cc[2])
		args["fixcam"] = "1"
	_say("The compound. Walk around and watch the others work. E at the gate or the truck: go out.", 6.0)


func _enter_raid() -> void:
	mode = "raid"
	raids += 1
	var seed_i := int(args.get("seed", str(1000 + raids * 17 + int(Time.get_ticks_msec() % 997))))
	var t: Dictionary = TownGen.make(seed_i, {"blocks": 2})
	# the autumn crowns of the old trees are swapped for greens, pines and scrub (same art style, tools/make_prison_trees.py)
	var swap := [0, 2, 5, 7, 8, 11, 14, 18, 19]
	for tr in t.data.trees:
		var m := String(tr.file).get_file().trim_prefix("tree_").trim_suffix(".png")
		if m.is_valid_int() and [1, 3, 4, 6, 9, 10, 12].has(int(m)):
			tr["file"] = "res://assets/trees/tree_%d.png" % swap[int(absf(tr.x * 7.0 + tr.y * 13.0)) % swap.size()]
	var drop: Vector2 = Vector2(t.entry.pos)
	t["dead"] = (t.dead as Array).filter(func(r): return Vector2(r.pos).distance_to(drop) > 16.0)    # a quiet drop-off
	_make_stage(t, true)
	run.sim.stock = {"food": 0.0, "water": 0.0, "ammo": 0.0, "meds": 0.0, "scrap": 0.0}
	_loadout = minf(LOADOUT_AMMO, stores.ammo)
	stores.ammo -= _loadout
	run.sim.stock.ammo = _loadout
	run.sim.stock.meds = minf(1.0, stores.meds)
	stores.meds -= float(run.sim.stock.meds)
	var at: Vector2 = Vector2(t.entry.pos)
	run.avatar_p.x = at.x
	run.avatar_p.y = at.y
	run.avatar_p.hp = 100.0
	if args.has("at"):
		var c := String(args.at).split(",")
		run.avatar_p.x = float(c[0])
		run.avatar_p.y = float(c[1])
	exits = _pick_exits(t, at)
	cam_center = Vector2(run.avatar_p.x, run.avatar_p.y)
	extract_t = 0.0
	_armed = false
	run.sim.avatar.set_input(Vector2.ZERO, at, false)
	_say("Out in the town. Search houses (E), find the pickup rings (green arrows), get back alive. Ammo %d in the pack." % int(_loadout), 7.0)


## Pickup points: the entry road and the far end of the road on the other side of the map.
func _pick_exits(t: Dictionary, from: Vector2) -> Array:
	var d: Dictionary = t.data
	var W := int(d.W)
	var H := int(d.H)
	var best := Vector2(-1, -1)
	var bd := 0.0
	for y in range(2, H - 2):
		for x in [3, W - 4]:
			if int(d.terrain[y * W + x]) == 1 and int(d.solidP[y * W + x]) == 0:
				var dist := from.distance_to(Vector2(x, y))
				if dist > bd:
					bd = dist
					best = Vector2(x + 0.5, y + 0.5)
	for x in range(2, W - 2):
		for y in [3, H - 4]:
			if int(d.terrain[y * W + x]) == 1 and int(d.solidP[y * W + x]) == 0:
				var dist2 := from.distance_to(Vector2(x, y))
				if dist2 > bd:
					bd = dist2
					best = Vector2(x + 0.5, y + 0.5)
	var out: Array = [from]
	if best.x >= 0.0:
		out.append(best)
	return out


# ------------------------------------------------------------------------ frame --

func _process(delta: float) -> void:
	if run == null:
		return
	_tick(delta)


func _tick(dt: float) -> void:
	dt = clampf(dt, 0.0, StepClock.MAX_FRAME)
	clock += dt
	frames += 1
	_hands()
	for i in step_clock.advance(dt, 1.0):
		_step()
		sim_steps += 1
	tod = fposmod(tod + dt * DAY_MIN_PER_SEC / 60.0, 24.0)
	if crew != null:
		crew.tod = tod
	fx.combat.listener = Vector2(run.avatar_p.x, run.avatar_p.y)
	if crew != null:
		crew.update(dt, stores)
	fx.update(dt)
	var p = run.avatar_p
	if not args.has("fixcam"):
		var goal := Vector2(p.x, p.y) if not map_view else Vector2(float(world.W) / 2.0, float(world.H) / 2.0)
		cam_center += (goal - cam_center) * (1.0 - exp(-CAMERA_EASE * dt))
	zoom_px = clampf(zoom_px, maxf(2.0, minf(_vp().x / (float(world.W) + 2.0), _vp().y / (float(world.H) + 2.0))), 84.0)
	camera.position = cam_center * TILE
	camera.zoom = Vector2.ONE * (zoom_px / TILE)
	world.show_chunks(Rect2(cam_center - _vp() / 2.0 / zoom_px, _vp() / zoom_px).grow(2.0))
	if roofs != null:
		roofs.update(TownGen.house_at(town, p.x, p.y), dt)
	_sync_views()
	_layout_labels()
	if _msg_t > 0.0:
		_msg_t -= dt
		if _msg_t <= 0.0:
			msg_label.text = ""
	if mode == "base":
		_base_logic(dt)
		_fence_guards(dt)
		_pen_life(dt)
		if dog != null:
			dog.tick(dt, clock, tod > 6.0 and tod < 20.0, true)
	else:
		_raid_logic(dt)
	_day_night(dt)
	hud_label.text = _hud_text()
	prompt_label.text = String(_prompt.get("label", "")) if not busy else ""
	overlay.queue_redraw()
	bars.queue_redraw()
	glow.queue_redraw()
	_scripts(dt)
	if args.has("shot") and frames >= _shot_wait and not _quit_after:
		_save_shot()
		get_tree().quit()


func _step() -> void:
	run.sim.update(StepClock.STEP)
	for e in run.sim.events:
		match String(e.type):
			"shot":
				fx.combat.shot_sound(e)
			"thud":
				fx.combat.thud_sound(e)
			"reload":
				if not fx.combat.reload_event(e, run.avatar_p):
					sound.play("reload", 0.8)
			"bite", "crash":
				sound.play(String(e.type))
			"stab":
				sound.play("stab", 0.6, 0.08)
	run.sim.events.clear()
	if run.invulnerable:
		run.avatar_p.hp = 100.0
		run.avatar_p.downed = false


func _hud_text() -> String:
	var p = run.avatar_p
	if mode == "base":
		return "PRISON BASE  %02d:%02d    " % [int(tod), int(fposmod(tod, 1.0) * 60.0)] + _stock_line() + "\nTrucks out: %d   shots from the walls: %d" % [raids, shots_fired]
	return "RAID %d    HP %d    Mag %d    Pack: ammo %d  food %d  water %d  meds %d  scrap %d\nKills %d   Exits: %d" % [raids, int(p.hp), int(p.mag), int(run.sim.stock.ammo), int(run.sim.stock.food), int(run.sim.stock.water), int(run.sim.stock.meds), int(run.sim.stock.scrap), run.sim.kills, exits.size()]


func _hands() -> void:
	var move := Vector2.ZERO
	if not busy:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
	if args.has("walk") and not busy:
		var w := String(args.walk).split(",")
		move = Vector2(float(w[0]), float(w[1]))
	var aim := cam_center + (get_viewport().get_mouse_position() - _vp() / 2.0) / zoom_px
	if args.has("aimdir"):
		var ad := String(args.aimdir).split(",")
		aim = Vector2(run.avatar_p.x + float(ad[0]), run.avatar_p.y + float(ad[1]))
	var fire := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and mode == "raid" and not busy and not args.has("shot")
	run.sim.avatar.set_input(move, aim, fire)


func _unhandled_input(ev: InputEvent) -> void:
	if run == null:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_E:
				_use()
			KEY_R:
				if mode == "raid":
					run.sim.avatar.reload()
			KEY_F:
				if mode == "raid" and not busy:
					run.sim.avatar.melee()
			KEY_M:
				map_view = not map_view
				zoom_px = 6.0 if map_view else play_zoom
			KEY_ESCAPE:
				get_tree().quit()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_px *= 1.12
			play_zoom = zoom_px
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_px /= 1.12
			play_zoom = zoom_px


func _use() -> void:
	if busy or _prompt.is_empty():
		return
	if String(_prompt.get("kind", "")) == "gate":
		_go_out()
		return
	if String(_prompt.get("kind", "")) == "stores":
		_say("Stores: " + _stock_line(), 5.0)
		return
	var r: Dictionary = run.sim.uses.use(_prompt.c)
	if String(r.get("line", "")) != "":
		_say(String(r.line), 2.0)
	elif String(r.get("why", "")) != "":
		_say(String(r.why), 2.0)


func _base_logic(_dt: float) -> void:
	var p = run.avatar_p
	var me := Vector2(p.x, p.y)
	_prompt = {}
	if me.distance_to(Base.GATE_POS) < 7.0 or me.distance_to(base.stations.truck) < 3.5:
		_prompt = {"kind": "gate", "label": "E: take the truck out the gate (raid, %d rounds in the pack)" % int(minf(LOADOUT_AMMO, stores.ammo))}
	elif me.distance_to(base.stations.stores) < 4.0:
		_prompt = {"kind": "stores", "label": "E: check the stores"}
	# the dead at the gate are not for shooting
	if run.avatar_p.hp < 100.0:
		run.avatar_p.hp = 100.0


func _raid_logic(dt: float) -> void:
	var p = run.avatar_p
	var me := Vector2(p.x, p.y)
	_prompt = {}
	if not busy:
		for c in run.sim.uses.candidates(p):
			if bool(c.get("ok", true)):
				_prompt = {"kind": "use", "c": c, "label": "E: %s" % String(c.label)}
				break
		var in_ring := false
		if me.distance_to(Vector2(exits[0])) > 14.0:
			_armed = true    # the drop-off ring works only after you have walked away from it
		for k in exits.size():
			if me.distance_to(Vector2(exits[k])) < EXTRACT_R and (k > 0 or _armed):
				in_ring = true
		if in_ring and not run.sim.uses.busy():
			extract_t += dt
			if extract_t >= EXTRACT_S:
				_extract(true)
		else:
			extract_t = maxf(0.0, extract_t - dt * 2.0)
		if p.downed or p.dead or float(p.hp) <= 0.5:
			_extract(false)


# ------------------------------------------------------------------- cutscenes --

func _go_out() -> void:
	busy = true
	await _cut_out(["The gate grinds open. The truck rolls out through the dead.", "Somewhere ahead, a town nobody has searched."], true)
	_enter_raid()
	await _cut_in()
	busy = false


func _extract(alive: bool) -> void:
	if busy:
		return
	busy = true
	var loot := {}
	if alive:
		for k in STOCK_KEYS:
			var v := float(run.sim.stock.get(k, 0.0))
			loot[k] = v
	var lines: Array = ["You reach the pickup. The truck is waiting.", "Back through the gate, back to the compound."]
	if not alive:
		lines = ["You go down in the street.", "Whatever you carried stays out there."]
	await _cut_out(lines, alive)
	if alive:
		for k in loot:
			stores[k] = float(stores[k]) + float(loot[k])
	_enter_base()
	var sum := "Banked:"
	for k in loot:
		if float(loot[k]) > 0.0:
			sum += "  +%d %s" % [int(loot[k]), k]
	if not alive:
		sum = "Backpack lost. (Ammo %d, nothing banked)" % int(_loadout)
	elif sum == "Banked:":
		sum = "You came back with nothing."
	await _cut_in()
	_say(sum, 8.0)
	busy = false


func _cut_out(lines: Array, truck: bool) -> void:
	cut_x = -1.0
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.7)
	await tw.finished
	for i in lines.size():
		cap_label.text = String(lines[i])
		cap_label.modulate.a = 1.0
		if truck:
			cut_x = 0.0
			var t2 := create_tween()
			t2.tween_property(self, "cut_x", 1.0, 1.5)
			var t3 := create_tween()
			t3.tween_method(func(_v): cut_art.queue_redraw(), 0.0, 1.0, 1.5)
		await get_tree().create_timer(1.6).timeout
	cap_label.modulate.a = 0.0
	cut_x = -1.0
	cut_art.queue_redraw()


func _cut_in() -> void:
	await get_tree().create_timer(0.2).timeout
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.9)
	await tw.finished


func _draw_cut() -> void:
	if cut_x < 0.0:
		return
	var v := _vp()
	var x := lerpf(-260.0, v.x + 60.0, cut_x)
	var y := v.y * 0.5
	cut_art.draw_rect(Rect2(x, y, 200, 70), Color(0.28, 0.3, 0.26))
	cut_art.draw_rect(Rect2(x + 130, y - 30, 70, 38), Color(0.22, 0.26, 0.3))
	cut_art.draw_circle(Vector2(x + 40, y + 74), 17, Color(0.05, 0.05, 0.05))
	cut_art.draw_circle(Vector2(x + 160, y + 74), 17, Color(0.05, 0.05, 0.05))
	cut_art.draw_colored_polygon(PackedVector2Array([Vector2(x + 200, y + 40), Vector2(x + 380, y + 5), Vector2(x + 380, y + 75)]), Color(1, 0.95, 0.6, 0.18))


# ------------------------------------------------------------------- the views --

func _sync_views() -> void:
	var view := Rect2(cam_center - _vp() / 2.0 / zoom_px, _vp() / zoom_px).grow(3.0)
	var alpha := step_clock.alpha()
	var alive := {}
	var made := 0
	for z in run.sim.zombies:
		alive[z] = true
		var dead: bool = z.state == "dead" or z.state == "dying"
		var in_view := view.has_point(Vector2(z.x, z.y))
		if not pawn_nodes.has(z):
			if not in_view or made >= 6:
				continue
			made += 1
			var n := PawnNode.new()
			n.work_poses = false
			n.setup(z, true, data, "z%d" % z.look_index)
			entities.add_child(n)
			pawn_nodes[z] = n
		var n2 = pawn_nodes[z]
		if dead and n2.get_parent() == entities:
			n2.reparent(corpses)
		n2.anim_t = clock
		n2.visible = in_view
		if not n2.visible:
			continue
		n2.sync(not (z.state == "dead" and z.dead_t > 0.2), sim_steps, alpha)
	for e in pawn_nodes.keys():
		if pawn_nodes[e].zombie and not alive.has(e):
			pawn_nodes[e].queue_free()
			pawn_nodes.erase(e)
	var an = pawn_nodes[run.avatar_p]
	an.anim_t = clock
	an.sync(true, sim_steps, alpha)
	if crew != null:
		for m in crew.members:
			var n3: PawnNode = m.node
			n3.anim_t = clock
			n3.visible = view.has_point(Vector2(m.p.x, m.p.y))
			if n3.visible:
				n3.sync(true, sim_steps, alpha)


func _paint_overlay(c: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	if mode == "base":
		for t in base.towers:
			var r: Rect2 = t
			c.draw_rect(Rect2(r.position * TILE + Vector2(6, 6), r.size * TILE - Vector2(12, 12)), Color(0.32, 0.24, 0.17))
			c.draw_rect(Rect2(r.position * TILE + Vector2(6, 6), r.size * TILE - Vector2(12, 12)), Color(0.15, 0.1, 0.06), false, 3.0)
			for q in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				c.draw_rect(Rect2((r.position + q * (r.size - Vector2(0.4, 0.4))) * TILE, Vector2(0.4, 0.4) * TILE), Color(0.2, 0.14, 0.08))
		# the gate leaves
		var g := Vector2(Base.GATE_X, Base.FENCE.end.y - 1) * TILE
		c.draw_rect(Rect2(g, Vector2(Base.GATE_W * TILE * 0.5 - 2, TILE)), Color(0.45, 0.47, 0.5))
		c.draw_rect(Rect2(g + Vector2(Base.GATE_W * TILE * 0.5 + 2, 0), Vector2(Base.GATE_W * TILE * 0.5 - 2, TILE)), Color(0.45, 0.47, 0.5))
		for l in base.labels:
			c.draw_string(font, Vector2(l.pos) * TILE - Vector2(80, 0), String(l.text), HORIZONTAL_ALIGNMENT_CENTER, 160, 20, Color(1, 1, 0.8, 0.8))
		for m in crew.members:
			var p = m.p
			var tag := "%s: %s" % [String(m.def.name), String(m.say)]
			var at := Vector2(p.x, p.y - 1.55) * TILE
			c.draw_string(font, at - Vector2(100, 0), tag, HORIZONTAL_ALIGNMENT_CENTER, 200, 15, Color(1, 1, 1, 0.92))
			if m.state == "work":
				var f := clampf(float(m.t) / float(m.def.route[m.i].secs), 0.0, 1.0)
				c.draw_rect(Rect2(at + Vector2(-20, 4), Vector2(40, 5)), Color(0, 0, 0, 0.6))
				c.draw_rect(Rect2(at + Vector2(-20, 4), Vector2(40.0 * f, 5)), Color(0.95, 0.8, 0.3))
		for fl in crew.floaters:
			var a := 1.0 - float(fl.t) / 2.2
			var col: Color = fl.col
			col.a = a
			c.draw_string(font, Vector2(fl.pos) * TILE + Vector2(-60, -float(fl.t) * 22.0), String(fl.text), HORIZONTAL_ALIGNMENT_CENTER, 120, 17, col)
		# a washing line with laundry, swaying a little
		var l0 := Vector2(12.5, 46.5) * TILE
		var l1 := Vector2(24.5, 46.5) * TILE
		c.draw_line(l0, l1, Color(0.2, 0.15, 0.1), 2.0)
		c.draw_rect(Rect2(l0 - Vector2(3, 0), Vector2(6, 22)), Color(0.25, 0.18, 0.1))
		c.draw_rect(Rect2(l1 - Vector2(3, 0), Vector2(6, 22)), Color(0.25, 0.18, 0.1))
		var cols := [Color(0.85, 0.85, 0.8), Color(0.75, 0.3, 0.25), Color(0.3, 0.5, 0.7), Color(0.9, 0.8, 0.4), Color(0.8, 0.8, 0.85), Color(0.4, 0.6, 0.4)]
		for k in 6:
			var x := lerpf(l0.x, l1.x, (float(k) + 0.5) / 6.0)
			var sw := sin(clock * 1.7 + float(k)) * 2.0
			c.draw_rect(Rect2(Vector2(x - 9.0 + sw, l0.y + 1.0), Vector2(18, 22 + (k % 3) * 5)), cols[k], true)
		c.draw_string(font, Vector2(Base.GATE_POS.x, 62.5) * TILE - Vector2(150, 0), "THE DEAD OUTSIDE THE FENCE", HORIZONTAL_ALIGNMENT_CENTER, 300, 18, Color(1, 0.5, 0.45, 0.7))
	else:
		var pulse := 0.5 + 0.5 * sin(clock * 4.0)
		for e in exits:
			var p: Vector2 = Vector2(e) * TILE
			c.draw_circle(p, EXTRACT_R * TILE, Color(0.3, 1, 0.45, 0.12 + 0.1 * pulse))
			c.draw_arc(p, EXTRACT_R * TILE, 0, TAU, 40, Color(0.4, 1, 0.5, 0.9), 3.0)
			c.draw_string(font, p - Vector2(60, EXTRACT_R * TILE + 8), "EXTRACTION", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(0.6, 1, 0.7))


# --------------------------------------------------------------------- scripted --

## --auto=raid: start a raid, walk to the nearest container and search it, then to an exit.  extract / die jump to those endings (for checks).
func _scripts(dt: float) -> void:
	var a := String(args.get("auto", ""))
	if a == "":
		return
	_auto_t += dt
	if a == "extract" and _auto_t > 2.0 and mode == "raid" and not busy:
		var e = exits[exits.size() - 1]
		run.avatar_p.x = float(e.x)
		run.avatar_p.y = float(e.y)
	if a == "die" and _auto_t > 2.0 and mode == "raid" and not busy:
		run.avatar_p.hp = 0.0
	if a == "full" and mode == "raid" and not busy:
		if _auto_t < 9.0:
			run.avatar_p.hp = 100.0
			run.sim.avatar.set_input(Vector2.ZERO, Vector2(run.avatar_p.x, run.avatar_p.y), false)
			for c in run.sim.uses.candidates(run.avatar_p):
				if String(c.kind) == "container" and not run.sim.uses.busy():
					run.sim.uses.use(c)
					break
		elif _auto_t > 9.0:
			print("AUTO looted ", run.sim.search.looted.keys(), " stock ", run.sim.stock)
			run.avatar_p.x = float(exits[exits.size() - 1].x)
			run.avatar_p.y = float(exits[exits.size() - 1].y)
	if a == "loot" and mode == "raid" and not busy:
		_auto_loot()
	if a == "go" and mode == "base" and _auto_t > 2.0 and not busy:
		_go_out()


var _auto_target := Vector2(-1, -1)
func _auto_loot() -> void:
	var p = run.avatar_p
	var me := Vector2(p.x, p.y)
	var best = null
	var bd := 1.0e9
	for c in town.containers:
		if run.sim.search.is_looted(String(c.id)):
			continue
		var d := me.distance_to(Vector2(c.pos))
		if d < bd:
			bd = d
			best = c
	if best == null:
		return
	if bd < 0.7:
		for c in run.sim.uses.candidates(p):
			if String(c.kind) == "container":
				run.sim.uses.use(c)
				break
		run.sim.avatar.set_input(Vector2.ZERO, me, false)
	else:
		var path: Array = run.sim.path_p.find(world.solid_p, me.x, me.y, best.pos.x, best.pos.y)
		if not path.is_empty():
			var wp: Vector2 = path[mini(1, path.size() - 1)]
			run.sim.avatar.set_input(wp - me, wp, false)


func _save_shot() -> void:
	if DisplayServer.get_name() == "headless":
		print("shot skipped: headless")
		return
	get_viewport().get_texture().get_image().save_png(String(args.shot))
	print("shot saved: %s | mode %s stores %s sim stock %s" % [String(args.shot), mode, stores, run.sim.stock])


# ----------------------------------------------------------------------- minimap --

func _mini_texture(d: Dictionary) -> ImageTexture:
	var w := int(d.W)
	var h := int(d.H)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			var t := int(d.terrain[i])
			var c := Color(0.2, 0.3, 0.17)    # grass
			match t:
				1:
					c = Color(0.22, 0.22, 0.25)
				2, 12:
					c = Color(0.5, 0.5, 0.5)
				3, 13:
					c = Color(0.45, 0.38, 0.28)
				5:
					c = Color(0.3, 0.2, 0.12)
				6, 7, 8, 9, 10, 11:
					c = Color(0.62, 0.55, 0.45)
				20, 21:
					c = Color(0.75, 0.35, 0.28)
				22:
					c = Color(0.85, 0.85, 0.9)
			if int(d.kit.line[i]) == 5:
				c = Color(0.15, 0.3, 0.12)
			elif int(d.solidP[i]) == 1 and t != 20 and t != 21 and t != 22:
				c = c.darkened(0.35)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _draw_minimap(v: Vector2) -> void:
	if mini_tex == null:
		return
	var sc := 2.0 if mode == "base" else 2.6
	var sz := Vector2(float(world.W), float(world.H)) * sc
	var o := Vector2(v.x - sz.x - 14.0, v.y - sz.y - 14.0)
	bars.draw_rect(Rect2(o - Vector2(3, 3), sz + Vector2(6, 6)), Color(0, 0, 0, 0.7))
	bars.draw_texture_rect(mini_tex, Rect2(o, sz), false, Color(1, 1, 1, 0.92))
	if mode == "base":
		bars.draw_circle(o + Base.GATE_POS * sc, 3.5, Color(1, 0.85, 0.3))
		for m in crew.members:
			bars.draw_circle(o + Vector2(m.p.x, m.p.y) * sc, 1.8, Color(0.4, 0.85, 1.0))
		bars.draw_rect(Rect2(o + Vector2(5, 57) * sc, Vector2(86, 12) * sc), Color(0.8, 0.1, 0.1, 0.18))
	for z in run.sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		bars.draw_rect(Rect2(o + Vector2(z.x, z.y) * sc - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), Color(0.95, 0.25, 0.2))
	if mode == "raid":
		for e in exits:
			bars.draw_arc(o + Vector2(e) * sc, 5.0, 0, TAU, 14, Color(0.4, 1, 0.5), 2.0)
	var p = run.avatar_p
	var me := o + Vector2(p.x, p.y) * sc
	var ang := Vector2(p.x, p.y).angle_to_point(run.avatar_p.input_aim) if run.avatar_p.input_aim != Vector2.ZERO else 0.0
	var dir := Vector2.from_angle(ang)
	bars.draw_colored_polygon(PackedVector2Array([me + dir * 6.0, me + dir.rotated(2.5) * 4.0, me + dir.rotated(-2.5) * 4.0]), Color(1, 1, 0.9))
	# the camera's window
	var half := _vp() / zoom_px / 2.0 * sc
	bars.draw_rect(Rect2(o + cam_center * sc - half, half * 2.0), Color(1, 1, 1, 0.5), false, 1.0)


# --------------------------------------------------------------- the fence's guns --

func _awake_dead() -> Array:
	var out: Array = []
	for z in run.sim.zombies:
		if z.state != "dying" and z.state != "dead":
			out.append(z)
	return out


func _fence_guards(dt: float) -> void:
	var fence_y := float(Base.FENCE.end.y) - 0.5
	var dead := _awake_dead()
	var near := 0
	for z in dead:
		if z.y > fence_y and z.y < fence_y + 4.5:
			near += 1
	alarm_cd = maxf(0.0, alarm_cd - dt)
	alarm_t = maxf(0.0, alarm_t - dt)
	if near >= 4 and alarm_cd <= 0.0:
		alarm_cd = 45.0
		alarm_t = 14.0
		sound.play("bell", 0.9, 0.0)
		_say("ALARM: the dead are at the fence!", 4.0)
		for m in crew.members:
			if m.def.has("stand"):
				m.say = "Contact! Contact!"
	for m in crew.members:
		if not m.def.has("stand"):
			continue
		var g = m.p
		guard_cd[g.id] = float(guard_cd.get(g.id, randf() * 2.0)) - dt
		if float(guard_cd[g.id]) > 0.0:
			continue
		var best = null
		var bd := 1.0e9
		for z in dead:
			if z.y < fence_y - 0.5 or z.y > fence_y + FENCE_ZONE:
				continue
			var d := Vector2(z.x, z.y).distance_to(Vector2(g.x, g.y))
			if d < GUARD_RANGE and d < bd:
				bd = d
				best = z
		if best == null:
			guard_cd[g.id] = 0.4
			if alarm_t <= 0.0:
				m.say = String(m.def.role)
			continue
		guard_cd[g.id] = (0.7 if alarm_t > 0.0 else randf_range(1.6, 3.0))
		var ang := Vector2(g.x, g.y).angle_to_point(Vector2(best.x, best.y))
		g.facing = run.sim.facing_of(cos(ang), sin(ang), g.facing)
		var mx: float = g.x + cos(ang) * 0.7
		var my: float = g.y + sin(ang) * 0.7 - 0.3
		fx.muzzle(mx, my, ang, false)
		var hit := randf() < 0.8
		var tx: float = best.x if hit else best.x + randf_range(-0.8, 0.8)
		var ty: float = best.y if hit else best.y + 1.2
		fx.tracer(mx, my, tx, ty)
		run.sim.events.append({"type": "shot", "weapon": "rifle", "gun": "rifle", "x": g.x, "y": g.y})
		fx.combat.shot_sound({"type": "shot", "weapon": "rifle", "gun": "rifle", "x": g.x, "y": g.y})
		run.sim.events.clear()
		shots_fired += 1
		m.say = "firing"
		if hit:
			run.sim._hurt_zombie(best, 55.0, ang, null)


## The pen never empties: new dead drift in from the edges and a slow trickle of them is sent to the fence by the gate.
func _pen_life(dt: float) -> void:
	_repl_t -= dt
	_trickle_t -= dt
	var dead := _awake_dead()
	if _repl_t <= 0.0:
		_repl_t = 2.0
		if dead.size() < 66:
			var side := randi() % 3
			var at := Vector2(randf_range(8.0, W_BASE - 8.0), 70.0)
			if side == 1:
				at = Vector2(7.0, randf_range(60.0, 69.0))
			elif side == 2:
				at = Vector2(W_BASE - 7.0, randf_range(60.0, 69.0))
			var i: int = run.field.add_record(at, "runner" if randf() < 0.08 else "walker", false)
			var z = run.field._wake(i)
			if z != null:
				run.field._investigate(z, Vector2(48.0 + randfn(0.0, 11.0), 57.4))
	if _trickle_t <= 0.0:
		_trickle_t = 3.0
		if not dead.is_empty():
			var z2 = dead[randi() % dead.size()]
			if z2.y > 56.0 and String(z2.state) != "chase":
				run.field._investigate(z2, Vector2(clampf(48.0 + randfn(0.0, 12.0), 10.0, 86.0), 57.2 + randf() * 0.6))


const W_BASE := 96.0


# ------------------------------------------------------------------- night and glow --

func _night_of(h: float) -> float:
	# 0 by day, 1 at night: dusk 18 to 20, dawn 5 to 7
	if h >= 7.0 and h < 18.0:
		return 0.0
	if h >= 18.0 and h < 20.0:
		return (h - 18.0) / 2.0
	if h >= 5.0 and h < 7.0:
		return 1.0 - (h - 5.0) / 2.0
	return 1.0


func _day_night(_dt: float) -> void:
	var n := _night_of(tod)
	var warm := 0.0
	if tod >= 17.0 and tod < 20.0:
		warm = 1.0 - absf(tod - 18.5) / 1.5
	var c := Color(1, 1, 1).lerp(Color(0.32, 0.38, 0.62), n)
	c = c.lerp(Color(1.0, 0.82, 0.62), clampf(warm, 0.0, 1.0) * 0.6 * (1.0 - n))
	night_rect.color = c if mode == "base" or args.has("night") else Color(1, 1, 1).lerp(c, 0.0)
	if args.has("hour"):
		tod = float(args.hour)
	if sound != null:
		var horde := clampf(float(_awake_dead().size()) / 60.0, 0.0, 1.0) * (0.8 if mode == "base" else 0.4)
		sound.set_ambience(n, horde, _dt)


func _draw_glow() -> void:
	var n := _night_of(tod)
	if n <= 0.02 or mode != "base":
		return
	var v := _vp()
	var spots: Array = []
	for f in base.fires:
		spots.append([f, 7.0, Color(1.0, 0.55, 0.2, 0.85 * n * (0.85 + 0.15 * sin(clock * 11.0 + f.x)))])
	for l in base.lamps:
		spots.append([l, 6.0, Color(1.0, 0.9, 0.6, 0.55 * n)])
	for t in base.towers:
		var r: Rect2 = t
		spots.append([r.get_center(), 5.0, Color(1.0, 0.95, 0.75, 0.4 * n)])
	for sp in spots:
		var scr: Vector2 = (Vector2(sp[0]) - cam_center) * zoom_px + v / 2.0
		var rad: float = float(sp[1]) * zoom_px
		if scr.x < -rad or scr.y < -rad or scr.x > v.x + rad or scr.y > v.y + rad:
			continue
		glow.draw_texture_rect(radial_tex, Rect2(scr - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false, sp[2])
