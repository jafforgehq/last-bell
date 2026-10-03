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
const BuildNode := preload("res://scripts/render/build_node.gd")
const DressingNode := preload("res://scripts/render/dressing_node.gd")
const ParkingNode := preload("res://scripts/render/parking_node.gd")
const GateNode := preload("res://scripts/render/gate_node.gd")
const RecruitArt := preload("res://scripts/render/recruit_art.gd")
const DrawNode := preload("res://scripts/render/draw_node.gd")
const Snow := preload("res://scripts/render/snow.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Sound := preload("res://scripts/audio/sound.gd")
const StreetAir := preload("res://scripts/audio/street_air.gd")
const Music := preload("res://scripts/audio/music.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const Shell := preload("res://scripts/ui/shell.gd")
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const Hints := preload("res://scripts/ui/hints.gd")
const StoryUi := preload("res://scripts/ui/story_ui.gd")
const RaidScene := preload("res://scripts/raid/raid_scene.gd")
## The generator of the places of a played trip (the SITES builder's) and, until it exists, a stand-in.
const SITE_GEN := "res://scripts/raid/site_gen.gd"
const SITE_STUB := "res://scripts/raid/stub_site.gd"    # TODO-SITEGEN: delete with the fallback in open_raid once SITE_GEN is there

const TILE := GD.TILE
const MAX_ZOOM := 84.0
## The title screen's yard: the clock is held at this hour (a warm dusk with the lamps and
## the fires lit, before the bell), the camera drifts about this point, and a few of the
## dead shuffle about in the street north of the wall.
const TITLE_HOUR := 18.0 + 40.0 / 60.0
const TITLE_CAM := Vector2(36.5, 18.8)
const TITLE_SEED := 11
const TITLE_DEAD := [Vector2(35.5, 14.2), Vector2(41.0, 13.0), Vector2(46.5, 15.6), Vector2(30.5, 15.0), Vector2(51.0, 13.4)]
## The interface size the settings offer, and the smallest window (in points at the normal
## size) a bigger interface may still be given: a size that would squeeze the HUD below
## this is held back.
const UI_SCALE_MIN := 0.8
const UI_SCALE_MAX := 1.5
const MIN_LOGICAL := Vector2(700.0, 560.0)
## Selecting a group (round 15): a left press that moves more than this many pixels is a box, not a click; the people of a
## group sent to one spot stand round it this far from it (a bigger group, a wider ring); a group's orders and how many a
## spread ring takes are in `order_group_move`.
const BOX_PX := 6.0
const GROUP_SPREAD := 0.55

var data: Dictionary
var world
var sim
var fx
var lighting
var hud
var sound
## The music (scripts/audio/music.gd): the loops that cross-fade with the hour, the dead and the title screen.
var music
var camera: Camera2D
var entities: Node2D
var corpses: Node2D
var fire_nodes: Array = []
var ground_bits
var air
var lanterns_node
var glow
var overlay
## The snow (round 10, scripts/render/snow.gd): the flakes on the screen, and the ground's white cover in the world.
var snow
var ground_snow
## The plots, sites and buildings of the yard (round 6, scripts/render/build_node.gd).
var build_view
## The dressing of the ring of streets, a settlement game's (round 12, scripts/render/dressing_node.gd).
var dressing_view
## The colony's vehicles in the motor pool and on the road, a settlement game's (round 13, scripts/render/parking_node.gd; round 15: each one an actor, scripts/render/vehicle_actor.gd).
var parking_view
## The vehicle gate in the north wall (round 15, scripts/render/gate_node.gd): the Main gate's two leaves slide apart. The parking view
## (vehicle actors) calls `gate_node.follow(parking_view.gate_demand(), dt)` itself.
var gate_node
## The soft groans of the streets by day, a settlement game's (round 12, scripts/audio/street_air.gd).
var street_air
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
## Everyone selected (round 15), the primary included, in the order they were picked: a box, shift, Ctrl+A. `selection` is
## the primary, the one the panel and the single-person orders (follow, treat, send out, scavenge, jobs) are about, and while
## the selection is one person this is just them; with a wall piece or a walker selected, or nothing, it is empty.
var selected_people: Array = []
var hover = null
var follow = null
var order_mark = null
var clock := 0.0
var fire_t := 0.0
var hud_t := 0.0
## A left or middle press that may become a box or a pan: {"pos", "center", "moved", "button", "box" (the Rect2 being
## drawn, screen pixels), "shift" (the group is added to), "pan" (the camera follows the pointer: the middle button, or Alt
## and the left)}.
var drag = null
var walkers := 0
## The fields-of-fire view (key V) is on: the overlay tints every wall section by how
## many guns reach it. A view only; the rules never read it.
var fields := false
## A save was asked for at start-up but could not be loaded (a new run began instead).
var load_failed := false
## The shell: the title screen, the pause menu and the screens they open (scripts/ui/shell.gd).
var shell
## The title screen is up instead of a run: the clock is held, the HUD is hidden and the
## input is the menu's. (A cold start with no run chosen; see wants_title.)
var title_mode := false
## A menu screen is open over the game: the camera keys are the menu's, not the camera's. (The Jobs screen and the
## Build screen, the HUD's own pages, count: they have the keys while they are up, and the cards of the radio and the
## tips wait.)
var menu_open: bool:
	get:
		return title_mode or (shell != null and shell.is_open()) or (hud != null and (hud.jobs_screen != null or hud.build_screen != null or hud.town_board_open())) or raid_open()
## The played trip's scene (round 14, scripts/raid/raid_scene.gd) while one is up, else null: it takes the screen and the
## keys (so it counts as a menu), the colony's world and HUD are hidden and its rules wait (see `open_raid`).
var raid = null
## A seed for the next played trip's site (a screenshot's `--raid=<place>,<seed>`); -1: the run's, the place's and the day's.
var raid_seed := -1
## `--raid-stub`: a played trip's site comes from the stand-in (scripts/raid/stub_site.gd), not the generator.
var raid_stub := false
## What the Jobs screen marks in the world (it sets it through the HUD): {} while it is closed, else {"station": id,
## "post": id, "person": id} (each "" when nothing of the kind is marked). The overlay draws the marks.
var jobs_hover := {}
## The Build screen (round 6, scripts/ui/build_screen.gd) is up: the yard draws the plots' signs more clearly.
var build_open: bool:
	get:
		return hud != null and hud.build_screen != null
## The plot the Build screen has under the pointer or the keyboard ({"plot": id}, {} for none, and while it is closed):
## the yard draws it brighter. (The screen sets it through the HUD.)
var build_hover := {}
## A test's way of watching a new run, a load or the return to the title without a scene
## reload: when set, it is called with the choice ({"difficulty", "seed"}, {"load": path} or
## {"title": true}) instead.
var restart: Callable
var _speed_before_pause := 1
var _title_t := 0.0
## Orientation Day, the tutorial, is the run: its scenario (scripts/sim/orientation.gd) cannot be
## lost, and `coach` (scripts/ui/coach.gd) teaches it. `coach` is null in every other run, and once
## the lesson is over; while it is null nothing below asks it anything. The tutorial's F5 writes its
## own file, never the real quick save, and it never autosaves.
var tutorial := false
var coach = null
var tutorial_step := 0
var tutorial_save_path := "user://tutorial_save.json"
## The tips of a normal run (scripts/ui/hints.gd): null in the tutorial, on the title and in a
## screenshot run, and they stay quiet in a headless one.
var hints = null
## The storyteller's cards (scripts/ui/story_ui.gd): the radio card, which holds the game still while it is
## up, and the dawn assembly.
var story_ui = null

# screenshot mode (used for automated checks): --shot=path.png
var shot_path := ""
var shot_frames := 25
## `--box=`: a selection box, in tiles, that the screenshot shows being dragged (put on the screen two frames before the shot,
## when the window has its size).
var shot_box := Rect2()
var frame_count := 0
var bench_start := 0
var bench_cpu := 0.0
var bench_gpu := 0.0
var bench_proc := 0.0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var prefs_path := prefs_file_for(OS.get_cmdline_user_args())
	if prefs_path != "":
		Prefs.path = prefs_path
		Prefs.forget()
		if prefs_path == SHOT_PREFS:
			Prefs.reset()
	data = GD.load_all()
	var logical := Vector2i(1280, 800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var wh := arg.trim_prefix("--size=").split("x")
			logical = Vector2i(int(wh[0]), int(wh[1]))
	SettingsMenu.apply_fullscreen()
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
	# the white cover of a snowy season's ground: just over the ground, under everything else (its look is the
	# snow's, see _process; not drawn at all until there is snow)
	ground_snow = DrawNode.new()
	ground_snow.name = "GroundSnow"
	ground_snow.painter = func(ci): Snow.paint_ground(ci, world)
	ground_snow.visible = false
	world.add_child(ground_snow)
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
	# the walls of the lots (round 9) are made and taken away in play (and by a load): the world draws and forgets them
	sim.on_segment_added = func(s): world.add_segment_art(s)
	sim.on_segment_removed = func(s): world.remove_segment_art(s)
	# a run is started (or a save loaded) by reloading the scene with the
	# choice kept in Engine meta: {"difficulty": int, "seed": int, "load": path};
	# the first run of a process takes it from the command line instead:
	# --new=<difficulty 0-2> --seed=<n> --load=<path>
	var run: Dictionary = Scenario.run_from_args(OS.get_cmdline_user_args())
	var had_meta := Engine.has_meta("run")
	if had_meta:
		run = Engine.get_meta("run")
		Engine.remove_meta("run")
	else:
		# --crew=3 plays the small start (the others come over the radio); without it a run is the classic six
		var crew_asked := crew_from_args(OS.get_cmdline_user_args())
		if crew_asked > 0:
			run["crew"] = crew_asked
		# --campaign (or --season=N) plays the long game of four seasons; without it a run is Autumn's thirty nights
		if campaign_from_args(OS.get_cmdline_user_args()):
			run["campaign"] = true
	# with no run chosen at all the title is shown, over a quiet run of its own
	title_mode = bool(run.get("title", false)) or wants_title(OS.get_cmdline_user_args(), had_meta)
	if title_mode:
		run = {"difficulty": 1, "seed": TITLE_SEED}
	# Orientation Day (the tutorial): chosen from a menu or the command line, or because the save
	# being loaded is one of its own
	tutorial = bool(run.get("tutorial", false)) and not title_mode
	tutorial_step = int(run.get("step", 0))
	var loaded := false
	if String(run.get("load", "")) != "":
		var saved := SaveGame.read(String(run.load))
		if Orientation.is_save(saved) and SaveGame.is_loadable(String(run.load)):
			Orientation.install(sim)
			tutorial = true
		loaded = SaveGame.apply(sim, saved)
		load_failed = not loaded
	if not loaded:
		if tutorial:
			Orientation.begin(sim)
		else:
			# a run with no crew in its choice is six (the tests, the screenshots and the title's yard are classic)
			sim.crew_start = clampi(int(run.get("crew", 6)), 3, 6)
			# (only a run asked for the long game is one: the tutorial, the title's yard and the tests are Autumn's)
			sim.seasons.campaign = bool(run.get("campaign", false))
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
		_add_person_pawn(p)

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
	lighting.seasons = sim.seasons
	# the dressing of the streets (a settlement game only): decals under the people, light props sorted among them
	dressing_view = DressingNode.new()
	dressing_view.name = "Dressing"
	world.add_child(dressing_view)
	dressing_view.setup(sim, entities)
	# the parked vehicles of the fleet (a settlement game only), by the main gate in the north street
	parking_view = ParkingNode.new()
	parking_view.name = "Parking"
	world.add_child(parking_view)
	parking_view.setup(sim, entities)
	# the vehicle gate: the Main gate's picture as two posts and two leaves that slide apart (the segment's rules do not change)
	gate_node = GateNode.new()
	gate_node.name = "Gate"
	world.add_child(gate_node)
	gate_node.setup(world, sim)
	parking_view.gate = gate_node    # (the vehicle view tells it every frame whether a car or a party on foot is about to pass)
	# the plots, the sites and the buildings: over the ground, sorted among the people, lit by the night
	build_view = BuildNode.new()
	build_view.name = "Buildings"
	world.add_child(build_view)
	build_view.setup(self, sim, entities, lighting)

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
	# the flakes of a snow day: on the screen, over the world and the glow and under the HUD
	var snow_layer := CanvasLayer.new()
	snow_layer.layer = 1
	add_child(snow_layer)
	snow = Snow.new()
	snow_layer.add_child(snow)

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
	hud.on_select = func(sel): _try_select(sel)
	hud.on_group_pick = func(p): _set_primary(p)
	hud.on_group_drop = func(p): _toggle_person(p)
	hud.on_group_toggle = func(p): _toggle_person(p)
	hud.on_focus = func(p): _focus(Vector2(p.x, p.y))
	hud.on_speed = func(s): _set_speed(s)
	hud.on_gizmo = _gizmo
	hud.on_alert = _on_alert
	hud.on_sound = _toggle_sound
	hud.on_fields = _toggle_fields
	hud.on_menu = show_title
	hud.on_open_menu = open_pause
	hud.on_jobs = toggle_jobs
	hud.on_jobs_hover = func(marks): jobs_hover = marks
	hud.on_build = toggle_build
	hud.on_town = toggle_town
	hud.on_raid = open_raid
	hud.on_build_hover = func(marks): build_hover = marks
	hud.on_ui_sound = func(sound_name, level): if sound != null: sound.ui(sound_name, level)
	hud_layer.add_child(hud)
	hud.setup(data, sim.people)
	story_ui = StoryUi.new()
	add_child(story_ui)
	story_ui.blocked = func(): return menu_open
	story_ui.speed_of = func(): return speed
	story_ui.ui_sound = func(sound_name, level): if sound != null: sound.ui(sound_name, level)
	story_ui.setup(hud, sim)

	sound = Sound.new()
	add_child(sound)
	sound.setup(data.sounds)
	parking_view.wire(fx, sound, _vol_at)    # the cars' dust and sounds (doors, engine, the gate's motor), by distance to the camera
	# the real game keeps one music across the scene reloads of a new run, a load and the title; a test's or a
	# screenshot's scene has its own
	if get_tree().current_scene == self:
		music = Music.shared(get_tree())
	else:
		music = Music.new()
		music.name = "Music"
		add_child(music)
		music.setup()
	street_air = StreetAir.new()
	street_air.name = "StreetAir"
	world.add_child(street_air)
	street_air.setup(self)

	# the menus: one layer above the HUD (and the coach), built once, shown when they are asked for
	var shell_layer := CanvasLayer.new()
	shell_layer.layer = 5
	add_child(shell_layer)
	shell = Shell.new()
	shell_layer.add_child(shell)
	shell.setup(self, hud)
	apply_settings()
	# the coach of Orientation Day, over the HUD and under the menus (none once the lesson is over)
	if tutorial and not bool(sim.scenario.get("finished")):
		_build_coach()

	var vp := _vp()
	zoom_px = clampf(vp.x / 26.0, 28.0, 52.0)
	_parse_args()
	_clamp_camera()
	_apply_camera()
	_start_shell()
	_start_hints()
	if load_failed:
		hud.show_banner("Could not load that save", "A new game was started instead")
	print("Thirty Bells ready in %d ms" % (Time.get_ticks_msec() - t0))


func _add_pawn(e, is_zombie: bool, key: String) -> void:
	var n := PawnNode.new()
	n.setup(e, is_zombie, data, key)
	entities.add_child(n)
	pawn_nodes[e] = n


## The node of a person. The six survivors have baked bodies; anyone else (a recruit who came over the radio, see
## scripts/sim/recruits.gd) is drawn on the baked body most like their look, in the colours of their look
## (scripts/render/recruit_art.gd).
func _add_person_pawn(p) -> void:
	if data.pawn.files.has(p.id):
		_add_pawn(p, false, p.id)
		return
	var base: String = RecruitArt.base_for(data, p.look)
	_add_pawn(p, false, base)
	var bodies: Dictionary = RecruitArt.bodies(data, p.look, base)
	for view in bodies:
		pawn_nodes[p].tex[view] = bodies[view]


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


## Keep the UI at a constant size in points on any display and window size, times the size
## the player chose in the settings (80% to 150%).
func _update_scale() -> void:
	var win := get_window()
	var s := DisplayServer.screen_get_scale()
	if s <= 0.0:
		s = 1.0
	var k := ui_scale_in_use()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(maxi(1, int(win.size.x / (s * k))), maxi(1, int(win.size.y / (s * k))))


## The interface size the settings ask for, as far as this window can give it. Smaller is always
## possible; a bigger one is held back when the window, at that size, would be narrower or
## shorter than the smallest the HUD is laid out for (MIN_LOGICAL). `window_px` is the window's
## size in pixels, `os_scale` the display's scale factor, `pref` the setting (1.0 is normal).
static func effective_ui_scale(window_px: Vector2, os_scale: float, pref: float) -> float:
	var want := clampf(pref, UI_SCALE_MIN, UI_SCALE_MAX)
	if want <= 1.0:
		return want
	var base := window_px / maxf(os_scale, 0.01)
	var room := minf(base.x / MIN_LOGICAL.x, base.y / MIN_LOGICAL.y)
	return clampf(minf(want, room), 1.0, UI_SCALE_MAX)


## The interface size in use now (the setting, held back if the window is too small for it).
func ui_scale_in_use() -> float:
	var win := get_window()
	var s := DisplayServer.screen_get_scale()
	return effective_ui_scale(Vector2(win.size), s if s > 0.0 else 1.0, Prefs.number("ui", "scale"))


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
	var zoom_was := zoom_px
	zoom_px = clampf(zoom_px * factor, _min_zoom(), MAX_ZOOM)
	var after := _screen_to_tile(screen)
	cam_center += before - after
	_clamp_camera()
	_did("zoom", absf(log(zoom_px / zoom_was)))


func _focus(at: Vector2) -> void:
	cam_center = at
	_clamp_camera()


func view_rect() -> Rect2:
	var vp := _vp()
	return Rect2(cam_center - vp / 2.0 / zoom_px, vp / zoom_px)


# -------------------------------------------------------------- selection --

## Selects exactly `sel` (a person, a walker, a wall section, or null for nothing): a person is a group of one.
func _select(sel) -> void:
	selection = sel
	selected_people = [sel.ref] if sel != null and sel.kind == "person" else []
	follow = null
	hud.select(sel, selected_people)


## Selects `people` as a group (round 15): the primary, the one the panel and the single-person orders are about, is
## `primary` if it is one of them, else the first. Doubles are dropped. Nobody at all lets go. (The tutorial's lock is
## `_pick_people`'s to ask.)
func select_people(people: Array, primary = null) -> void:
	var group: Array = []
	for p in people:
		if not group.has(p):
			group.append(p)
	if group.is_empty():
		_select(null)
		return
	selection = {"kind": "person", "ref": primary if primary != null and group.has(primary) else group[0]}
	selected_people = group
	follow = null
	hud.select(selection, selected_people)


## Whether `p` is in the yard and alive: the people a box, Ctrl+A or a shift-click may pick (a person who is down is).
func _is_here(p) -> bool:
	return not p.dead and not p.turned and p.away == null


## What the player does about the selection (a click, a crew card, Tab): the tutorial's soft lock may
## refuse it; the coach is told when it goes through.
func _try_select(sel) -> void:
	if not _allows("select", Coach.sel_key(sel)):
		return
	_select(sel)
	_did("select", sel)


## The player picks `people` at once (a box, Ctrl+A): they become the group, or with `add` join the one there is (the
## primary stays). The tutorial's lock lets through only whom the step teaches (the first it refuses is the one it says
## so for, once). A pick of nobody lets go, as a click on empty ground does, unless it is an addition.
func _pick_people(people: Array, add: bool = false) -> void:
	var allowed: Array = []
	var refused = null
	for p in people:
		if coach == null or coach.would_allow("select", Coach.sel_key({"kind": "person", "ref": p})):
			allowed.append(p)
		elif refused == null:
			refused = p
	if allowed.is_empty():
		if refused != null:
			_allows("select", Coach.sel_key({"kind": "person", "ref": refused}))
		elif not add:
			_try_select(null)
		return
	var group: Array = selected_people.duplicate() if add else []
	for p in allowed:
		if not group.has(p):
			group.append(p)
	var lead = selection.ref if add and selection != null and selection.kind == "person" else null
	select_people(group, lead)
	_did("select", selection)


## A shift-click on `p`: they join the group, or, if they are in it, leave it (the next in the group is then the primary
## if it was they). Someone who is not here is not added; a click that starts a group is a plain selection.
func _toggle_person(p) -> void:
	if selected_people.has(p):
		var rest: Array = selected_people.filter(func(q): return q != p)
		var lead = selection.ref if selection != null and selection.ref != p else null
		select_people(rest, lead)
		return
	if not _is_here(p):
		return
	if selection == null or selection.kind != "person":
		_try_select({"kind": "person", "ref": p})
	elif _allows("select", Coach.sel_key({"kind": "person", "ref": p})):
		select_people(selected_people + [p], selection.ref)
		_did("select", selection)


## A badge of the HUD's strip was clicked: `p`, of the group, is the primary now (the group as it was).
func _set_primary(p) -> void:
	if not selected_people.has(p) or not _allows("select", Coach.sel_key({"kind": "person", "ref": p})):
		return
	select_people(selected_people, p)
	_did("select", selection)


## Whom a box holds: everyone in the yard and alive whose body is inside `box` (screen pixels), in the order of the crew.
func box_people(box: Rect2) -> Array:
	var out: Array = []
	for p in sim.people:
		if _is_here(p) and box.has_point(_tile_to_screen(view_pos(p) + Vector2(0.0, -0.45))):
			out.append(p)
	return out


## Ctrl+A or Cmd+A: everyone who is here and alive (A alone pans).
func select_everyone() -> void:
	var all: Array = []
	for p in sim.people:
		if _is_here(p):
			all.append(p)
	_pick_people(all)


## Keeps the group in step with the game, every frame: a person who has died, turned, gone away or left the crew is
## taken out (and, if they were the primary, the next in the group is), a selection set from outside (the title, a test)
## is told to the group, and the HUD is told of any change. One person alone is left selected whatever becomes of them (their
## panel says what did), as it always was. Not while a played trip holds the colony (it gives the group back as it was).
func _prune_selection() -> void:
	if raid_open() or hud == null:
		return
	if selection == null or selection.kind != "person":
		if not selected_people.is_empty():
			selected_people = []
			hud.set_group(selected_people)
		return
	if not selected_people.has(selection.ref):
		# someone put in by hand: they are a group of one
		selected_people = [selection.ref]
		hud.set_group(selected_people)
		return
	if selected_people.size() < 2:
		return
	var here: Array = []
	for p in selected_people:
		if sim.people.has(p) and _is_here(p):
			here.append(p)
	if here.size() == selected_people.size():
		return
	if here.is_empty():
		selected_people = [selection.ref]
		hud.set_group(selected_people)
		return
	select_people(here, selection.ref if here.has(selection.ref) else here[0])


## A speed asked for with the keys or the buttons (and by the dialogs, which pause the game while
## they are open): the tutorial's coach may hold the game still while a card is up.
func _set_speed(n: int) -> void:
	if not _allows("speed", n):
		return
	speed = n
	_did("speed", n)


## The tutorial's soft lock: whether the player may do `kind` (an `arg` of it) now. Always true
## without a coach, so a normal run and every test are as they were. With one, a step that does not
## teach it refuses with a gentle toast (see coach.gd).
func _allows(kind: String, arg = null) -> bool:
	if coach == null:
		return true
	return coach.allows(kind, arg)


## What the player just did (kinds: select, move, gizmo, speed, pan, zoom, save, load, fields, jobs, build), told
## to the coach so the lesson's conditions can use it.
func _did(kind: String, arg = null) -> void:
	if coach != null:
		coach.on_did(kind, arg)


## The mouse cursor over a point of the yard (in tiles), `hit` being what _pick found there: a hand over what a click
## would do something with (a person, a walker, a wall section, a plot's sign), else the arrow.
func _cursor_for(hit, at: Vector2) -> Input.CursorShape:
	return Input.CURSOR_POINTING_HAND if hit != null or sim.build.sign_at(at) != "" or parking_view.vehicle_at(at) != "" else Input.CURSOR_ARROW


## What is under a point of the world (in tiles): a person, a walker or a wall section, or null.
## The box round a figure is drawn at its size: a brute (drawn bigger) is easier to hit,
## and a runner (a little smaller) is no harder than a walker.
func _pick(w: Vector2):
	var hit := func(e, k: float = 1.0): return w.x > e.x - 0.42 * k and w.x < e.x + 0.42 * k and w.y > e.y - 0.95 * k and w.y < e.y + 0.42 * k
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
		if hit.call(z, maxf(1.0, float(z.size))):
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
	if not _allows("gizmo", g):
		return
	_did("gizmo", g)
	if g == "scavenge":
		hud.open_scavenge(selection)
		return
	var sel = selection
	if sel == null:
		hud.toast("Click a wall section first" if g == "lure" else "Click someone first")
		return
	# R, P and F with a group selected are for all of them; the rest (C, T, X, G, B, M) are for the primary
	if sel.kind == "person" and selected_people.size() > 1 and (g == "draft" or g == "post" or g == "repair"):
		_gizmo_group(g)
		hud.select(selection)
		return
	# the jobs (M and B) are for the crew who are here: the page of jobs says the same of the gone and the away
	if (g == "job_bench" or g == "job_builders") and sel.kind == "person" and (sel.ref.dead or sel.ref.turned or sel.ref.away != null):
		var gone_why: String = hud.why_not(g)
		hud.toast("Not now: %s" % gone_why if gone_why != "" else "That can't be done right now", "warn")
		return
	if sim.handle_gizmo(g, sel):
		hud.select(selection)
		return
	if g == "treat" or g == "sendout" or g == "job_bench" or g == "job_builders":
		var why: String = hud.why_not(g)
		hud.toast("Not now: %s" % why if why != "" else "That can't be done right now", "warn")
	# the night tools (the rules module took them, or refused): the alarm names its reason
	if g == "lure":
		if sel.kind == "segment":
			var why_not: String = sim.tactics.why_not_lure(sel.ref)
			hud.toast("Not now: " + why_not if why_not != "" else "That can't be done right now", "warn")
		else:
			hud.toast("Click a wall section first")
		return
	if g == "auto":
		hud.toast("Click someone first")
		return
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


## R, P or F for the whole group (the sim has no order for many: each person is ordered in turn). R drafts everyone if
## anyone is not drafted, else releases everyone; P sends each to their own night post; F sends them to mend the worn
## wall pieces, the worst first, one piece to a person and round again when there are more people than pieces (those who are
## down stay). What cannot be done is said once, in the words the order's button has for it.
func _gizmo_group(g: String) -> void:
	match g:
		"draft":
			var want := false
			for p in selected_people:
				if not p.drafted:
					want = true
			var refused: Array = []
			for p in selected_people:
				if p.drafted != want:
					sim.toggle_draft(p)
				if p.drafted != want:
					refused.append(p)
			if not refused.is_empty():
				hud.toast("Not now: %s is having a breakdown" % refused[0].first, "warn")
		"post":
			for p in selected_people:
				sim.order_post(p)
		"repair":
			var no_go: String = hud.why_not("repair")
			var worn: Array = []
			for s in sim.segments:
				if s.hp < s.max_hp:
					worn.append(s)
			worn.sort_custom(func(a, b): return a.hp / a.max_hp < b.hp / b.max_hp or (a.hp / a.max_hp == b.hp / b.max_hp and a.id < b.id))
			var able: Array = selected_people.filter(func(p): return not p.downed and not p.dead and p.away == null)
			if no_go != "" or worn.is_empty() or able.is_empty():
				hud.toast("Not now: %s" % (no_go if no_go != "" else ("nothing is damaged" if worn.is_empty() else "nobody is free to repair")), "warn")
				return
			for i in able.size():
				sim.order_repair(able[i], worn[i % worn.size()])


## A right-click on the ground at `w` (tiles) with a group selected: everyone who can go is sent there through
## `sim.order_move`, spread on a ring round the click (the exact spot is tried when the ring's own is solid) so they do
## not stand on each other: a ring `GROUP_SPREAD` wide for five, wider the more they are. Who cannot go is said once (the
## first reason, and how many other reasons there were). Returns how many were sent.
func order_group_move(w: Vector2) -> int:
	# (a click on a wall or anything else nobody can stand on sends no one, as for one person)
	if world.is_solid(world.solid_p, w.x, w.y):
		hud.toast("Nobody can stand there", "warn")
		return 0
	var able: Array = []
	var reasons: Array = []
	for p in selected_people:
		if p.dead or p.turned or p.downed or p.away != null or sim.morale.breakdown(p):
			var why := _why_not_there(p, w)
			if not reasons.has(why):
				reasons.append(why)
		else:
			able.append(p)
	var sent := 0
	var ring := GROUP_SPREAD * maxf(1.0, float(able.size()) / 5.0)
	for i in able.size():
		var at := w
		if able.size() > 1:
			var a := TAU * float(i) / float(able.size()) + 0.4
			at = w + Vector2(cos(a), sin(a)) * ring
		if sim.order_move(able[i], at.x, at.y) or sim.order_move(able[i], w.x, w.y):
			sent += 1
		else:
			var why := _why_not_there(able[i], w)
			if not reasons.has(why):
				reasons.append(why)
	if sent > 0:
		order_mark = {"x": w.x, "y": w.y, "t": clock}
		_did("move")
	if not reasons.is_empty():
		hud.toast(String(reasons[0]) if reasons.size() == 1 else "%s (and %d more)" % [reasons[0], reasons.size() - 1], "warn")
	return sent


## Why an order to walk to `w` was refused, in a few words.
func _why_not_there(p, w: Vector2) -> String:
	if p.dead:
		return "%s is gone" % p.first
	if p.downed:
		return "%s is down" % p.first
	if p.away != null:
		return "%s is away" % p.first
	if sim.morale.breakdown(p):
		return "%s is having a breakdown" % p.first
	if world.is_solid(world.solid_p, w.x, w.y):
		return "Nobody can stand there"
	return "%s can't go there" % p.first


func _pick_repairer(seg):
	var best = null
	var bd := INF
	for p in sim.people:
		if p.downed or p.dead or p.away != null:
			continue
		var dist: float = Vector2(p.x - seg.center.x, p.y - seg.center.y).length() - float(p.skills.Building) * 3.0
		if dist < bd:
			bd = dist
			best = p
	return best


func _on_alert(id: String) -> void:
	if story_ui != null and story_ui.on_alert(id):
		return
	var a = sim.alerts.get(id)
	if a != null and a.at != null:
		_focus(a.at)


func _quick_save() -> void:
	quick_save()


## Writes the quick save and says how it went in a banner; true if it was written. (The
## pause menu's Save is this.)
func quick_save() -> bool:
	if sim.over != "":
		hud.show_banner("The run is over", "Start a new game or load a save")
	elif SaveGame.write(sim, _save_path()):
		hud.show_banner("Game saved", "Quick save (F9 loads it)")
		_did("save")
		return true
	else:
		hud.show_banner("Could not save", "Nothing was written")
	return false


## Where F5 saves and F9 loads: the quick save, or in the tutorial a file of its own (so the
## player's real quick save is never touched by a lesson).
func _save_path() -> String:
	return tutorial_save_path if tutorial else SaveGame.QUICK_PATH


func _quick_load() -> void:
	var path := _save_path()
	if not FileAccess.file_exists(path):
		hud.show_banner("No quick save yet", "Press F5 to save")
		return
	# check it before the current game is thrown away for it
	if not SaveGame.is_loadable(path):
		hud.show_banner("Could not load", "The quick save is damaged or from another version")
		return
	_did("load")
	Engine.set_meta("run", {"load": path})
	get_tree().reload_current_scene()


func _toggle_sound() -> void:
	sound_on = not sound_on
	sound.set_muted(not sound_on)


## The fields-of-fire view on or off (key V, or the button by the speed controls).
func _toggle_fields() -> void:
	if not _allows("fields"):
		return
	fields = not fields
	hud.set_fields(fields)
	_did("fields", fields)


## The Jobs screen (key J, the clipboard in the toolbar, the job tag in a person's panel): opens it, or closes it
## when it is up. It is not there in the title, nor while a menu or another page (the radio card, the scavenging
## dialog, the end screen) has the screen, and the tutorial's lock may refuse it. (With the screen up J reaches
## the screen itself, which closes; the rules wait while it is open.)
func toggle_jobs() -> void:
	if hud.jobs_screen != null:
		hud.close_jobs()
		return
	if title_mode or shell == null or shell.is_open() or hud.modal_open():
		return
	if not _allows("jobs"):
		return
	hud.open_jobs(sim)
	if hud.jobs_screen != null:
		_did("jobs")


## The Town Board (round 8, the settlement game's scavenging page: key G, the person panel's Scavenge button, the bag in
## the toolbar): the toolbar's button opens it or, with it up, closes it. It is not there in the title, nor while a menu
## or another page has the screen, and the tutorial's lock may refuse it (the same gate as the Scavenge button's).
## (With the board up G reaches the board itself, which closes; the rules wait while it is open.)
func toggle_town() -> void:
	if hud.town_board_open():
		hud.scavenge_dialog.close()
		return
	if title_mode or shell == null or shell.is_open() or hud.modal_open():
		return
	_gizmo("scavenge")


## The Build screen (key N, the hammer in the toolbar, a click on a plot's sign in the yard): opens it, on `plot_id`
## when that is given, or closes it when it is up. It is not there in the title, nor while a menu or another page
## (the radio card, the scavenging dialog, the end screen, the Jobs screen) has the screen, and the tutorial's lock
## may refuse it. (With the screen up N reaches the screen itself, which closes; the rules wait while it is open.)
func toggle_build(plot_id: String = "") -> void:
	if hud.build_screen != null:
		hud.close_build()
		return
	if title_mode or shell == null or shell.is_open() or hud.modal_open():
		return
	if not _allows("build"):
		return
	hud.open_build(plot_id, sim)
	if hud.build_screen != null:
		_did("build")


# ------------------------------------------------------------------- raid --
# A played trip (round 14): the party's place as a small map the player plays (scripts/raid/raid_scene.gd).

## Whether a played trip is up.
func raid_open() -> bool:
	return raid != null and is_instance_valid(raid)


## Opens a played trip: `people` (the party, colony people) go to `place` (a place of the town's: its dictionary) in
## `vehicle_id` (a fleet id, "" on foot) with their loot multiplied by `loot_mult`, and the player plays the place. The
## colony is hidden and held until the squad is home; `on_done(result)` is then called with the trip's result (loot,
## hurt, lost, clear, rescue, ammo_used, beats: what `scavenge.send_played` takes). Returns the scene, or null if one is
## already up. The colony's time stands still while it is played (the party's hours pass afterwards, as for the dice).
## Nobody calls this yet: the Town Board's "Take control" button will (R14.4), after closing the board, with the
## chosen people, place, vehicle and the loot multiplier its Go would have used.
func open_raid(people: Array, place: Dictionary, vehicle_id: String, loot_mult: float, on_done: Callable) -> Node:
	if raid_open() or people.is_empty():
		return null
	var seed_value: int = raid_seed if raid_seed >= 0 else int(sim.run_seed) * 1000003 + String(place.get("id", "")).hash() + int(sim.day) * 7919
	var by_vehicle: bool = vehicle_id != ""
	# TODO-SITEGEN: the stand-in is for a checkout without the generator (and `--raid-stub`, a screenshot's choice of it)
	var maker = load(SITE_GEN) if ResourceLoader.exists(SITE_GEN) and not raid_stub else null
	if maker == null or not maker.can_instantiate():
		maker = load(SITE_STUB)
	var site: Dictionary = maker.make(place, seed_value, people.size(), by_vehicle)
	var kind := "" if not by_vehicle else String(sim.vehicles.vehicle(vehicle_id).get("kind", ""))
	var scene := RaidScene.new()
	add_child(scene)
	var survivor: bool = bool(place.get("survivor", false)) and not bool(sim.town.state.get(String(place.get("id", "")), {}).get("rescued", false))
	scene.setup(self, hud, data, site, people, float(sim.stock.ammo), kind, loot_mult, survivor)
	if on_done.is_valid():
		scene.finished.connect(on_done)
	return scene


# ------------------------------------------------------------------ shell --
# The title, the pause menu and the settings (scripts/ui/shell.gd), and how a run is begun.

## Whether a start with these user arguments (the ones after `--`) shows the title instead of
## a run. It does when no run was chosen: nothing in Engine meta (`has_meta`) and no argument
## that starts with `--` (those are all for the tests and the screenshots, so anything the game
## might understand counts as a choice: --new, --seed, --load, --shot, --tutorial, ...).
## `--title` asks for it outright (for a screenshot of the title).
## How many times faster than real time the gate and the car views run: the cars drive in game time, so the gate's leaves
## (which take a fixed number of seconds to open) have to follow the game's speed or a fast game drives into a shut gate.
## Paused, they still move at their own pace.
static func gate_rate(game_speed: int) -> float:
	return float(maxi(game_speed, 1))


static func wants_title(args: Array, has_meta: bool) -> bool:
	if "--title" in args:
		return true
	if has_meta:
		return false
	for a in args:
		if String(a).begins_with("--"):
			return false
	return true


## The settings file a screenshot run uses when it names none: it starts from the defaults
## every time and keeps its settings and tips apart from the player's own.
const SHOT_PREFS := "user://prefs_shot.cfg"


## The settings file these user arguments ask for: the one `--prefs=` names, else a file of
## their own for a screenshot run (`--shot=`), else "" (the player's own file).
static func prefs_file_for(args: Array) -> String:
	var shot := false
	for a in args:
		var text := String(a)
		if text.begins_with("--prefs="):
			return text.trim_prefix("--prefs=")
		if text.begins_with("--shot="):
			shot = true
	return SHOT_PREFS if shot else ""


## The value of a `--name=value` user argument, or "".
func _shell_arg(arg_name: String) -> String:
	var prefix := "--%s=" % arg_name
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with(prefix):
			return String(a).trim_prefix(prefix)
	return ""


## Begins a run, or loads a save: the choice goes in Engine meta and the scene reloads, as it
## does for the first run of a process (see _ready). `restart`, if set, is called with the choice
## instead (a test's way of watching it without a reload).
func _begin(meta: Dictionary) -> void:
	if restart.is_valid():
		restart.call(meta)
		return
	Engine.set_meta("run", meta)
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		tree.reload_current_scene()


## A new run at difficulty 0 (Story), 1 (Standard) or 2 (Brutal) with this seed. `crew` is 3 (the small start: the
## others come over the radio) or 6 (all six from the first day); left out, no choice is made and the run is six.
## `campaign` is the long game of four seasons (round 10); left out, the run is Autumn's thirty nights.
func start_run(difficulty: int, seed_value: int, crew: int = 0, campaign: bool = false) -> void:
	var meta := {"difficulty": clampi(difficulty, 0, 2), "seed": seed_value}
	if crew > 0:
		meta["crew"] = clampi(crew, 3, 6)
	if campaign:
		meta["campaign"] = true
	_begin(meta)


## The crew a `--crew=` argument asks for: 3 (or "small", or anything under three), 6 (or "full", or anything over
## three), 0 when there is no such argument or it is not a crew.
static func crew_from_args(args: Array) -> int:
	for a in args:
		var text := String(a)
		if not text.begins_with("--crew="):
			continue
		var value := text.trim_prefix("--crew=").strip_edges().to_lower()
		if value == "small":
			return 3
		if value == "full":
			return 6
		if value.is_valid_int():
			return clampi(value.to_int(), 3, 6)
	return 0


## The seasons, by the name `--season=` may give them (the order of assets/data/seasons.json).
const SEASON_NAMES := ["autumn", "winter", "spring", "summer"]


## The season a `--season=` argument asks to begin in: 0 to 3 (a number outside them is the nearest, a name is
## that season), -1 when there is no such argument or it is not a season.
static func season_from_args(args: Array) -> int:
	for a in args:
		var text := String(a)
		if not text.begins_with("--season="):
			continue
		var value := text.trim_prefix("--season=").strip_edges().to_lower()
		if SEASON_NAMES.has(value):
			return SEASON_NAMES.find(value)
		if value.is_valid_int():
			return clampi(value.to_int(), 0, SEASON_NAMES.size() - 1)
	return -1


## Whether the command line asks for the long game: `--campaign` (or `--campaign=1`, `=yes`, `=true`) or a
## `--season=` of any season (a game that begins in Winter is a campaign).
static func campaign_from_args(args: Array) -> bool:
	for a in args:
		var text := String(a)
		if text == "--campaign":
			return true
		if text.begins_with("--campaign="):
			var value := text.trim_prefix("--campaign=").strip_edges().to_lower()
			if value in ["1", "yes", "true", "on"]:
				return true
	return season_from_args(args) >= 0


## Loads the save at `path`. A save that cannot be loaded is refused (false) and the game that
## is running goes on.
func load_run(path: String) -> bool:
	if not SaveGame.peek(path).ok:
		return false
	_begin({"load": path})
	return true


## Back to the title screen.
func show_title() -> void:
	_begin({"title": true})


func quit_game() -> void:
	get_tree().quit()


## The pause menu (Esc with nothing selected): the rules stand still while it is open.
func open_pause() -> void:
	if title_mode or shell == null or shell.is_open():
		return
	if hud.game_over != null or hud.scavenge_dialog != null:
		return
	_speed_before_pause = speed
	speed = 0
	shell.open_pause()


## The pause menu is closed: the rules go on at the speed they had. (It was closed to show the
## controls: then the game stays paused, and says so.)
func resume(keep_paused: bool = false) -> void:
	if keep_paused:
		hud.toast("Paused. Press Space to go on.")
	else:
		speed = _speed_before_pause


## Reads the settings again and puts them to work: volumes, fullscreen, the size of the
## interface and the hints. Called at start and each time the settings screen changes one.
func apply_settings() -> void:
	Buses.apply_all()
	SettingsMenu.apply_fullscreen()
	_update_scale()
	if hud != null and not Prefs.on("ui", "hints") and hud.hint != null:
		hud.hint.visible = false
		if hud.has_method("_layout_toast"):
			hud._layout_toast()


## At the end of _ready: the title if no run was chosen (or `--title`), and the screen `--menu=`
## asks for (pause, settings, new, load, credits, confirm or orientation: for a screenshot of it, over
## the title or, for pause, over the run). `--prefs=user://x.cfg` keeps a screenshot run's settings
## in a file of its own (read at the top of _ready).
func _start_shell() -> void:
	if title_mode:
		_enter_title()
		shell.show_title()
	var named := _shell_arg("menu")
	if named == "pause" and not title_mode:
		open_pause()
	elif named != "":
		shell.open_named(named)


## The title's yard: the clock stands still at dusk (so the lamps and the fires are lit and the
## bell never rings), the HUD and the names are hidden, the rules run on (the crew goes about the
## yard, a few of the dead shuffle in the street) and the camera drifts. Nothing is saved or ordered.
func _enter_title() -> void:
	title_mode = true
	sim.min_per_sec = 0.0
	sim.minutes = TITLE_HOUR * 60.0
	sim.clock_min = fposmod(sim.minutes - 420.0, 1440.0)
	sim.phase = Sim.phase_at(sim.minutes)
	sim.bell_rung = false
	for at in TITLE_DEAD:
		sim.spawn(at.x, at.y, "wander")
	hud.visible = false
	overlay.visible = false
	selection = null
	speed = 1
	_title_t = 0.0
	_title_camera(0.0)


## A slow drift of the camera about TITLE_CAM (still, if the settings ask for less motion).
func _title_camera(dt: float) -> void:
	if not Prefs.on("ui", "reduce_motion"):
		_title_t += dt
	zoom_px = clampf(_vp().x / 36.0, 28.0, 64.0)
	cam_center = TITLE_CAM + Vector2(sin(_title_t * 0.05) * 3.2, sin(_title_t * 0.033 + 1.1) * 1.4)


# ------------------------------------------------------------------ input --

func _unhandled_input(ev: InputEvent) -> void:
	# the title and the menus have the keys and the mouse: nothing here reaches the yard (and a drag that was
	# going on when a page opened is over: its release goes to the page, not to us)
	if menu_open:
		drag = null
		return
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(exp(0.2 * maxf(mb.factor, 0.2)), mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(exp(-0.2 * maxf(mb.factor, 0.2)), mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if selection != null and selection.kind == "person":
				var w := _screen_to_tile(mb.position)
				if not _allows("move", w):
					return
				if selected_people.size() > 1:
					order_group_move(w)
				elif sim.order_move(selection.ref, w.x, w.y):
					order_mark = {"x": w.x, "y": w.y, "t": clock}
					_did("move")
				else:
					hud.toast(_why_not_there(selection.ref, w), "warn")
				hud.select(selection)
			else:
				hud.toast("Click someone first, then right-click where they should go")
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				# the left button draws a box; the middle button, or Alt (Option) and the left, pans the camera
				drag = {"pos": mb.position, "center": cam_center, "moved": false, "button": mb.button_index, "box": Rect2(), "shift": mb.shift_pressed, "pan": mb.button_index == MOUSE_BUTTON_MIDDLE or mb.alt_pressed}
			else:
				if drag != null and mb.button_index != drag.button:
					return # (another button let go: the drag goes on)
				if drag != null and drag.button == MOUSE_BUTTON_LEFT and drag.moved and not drag.get("pan", false):
					_pick_people(box_people(drag.box), bool(drag.get("shift", false)) or mb.shift_pressed)
				elif drag != null and not drag.moved and drag.button == MOUSE_BUTTON_LEFT:
					var at := _screen_to_tile(mb.position)
					var hit = _pick(at)
					# a click that hit nothing else, near a plot's sign, opens the Build screen on that plot (the
					# tutorial's lock, if it refuses, leaves it an ordinary click on the ground)
					var sign_of: String = sim.build.sign_at(at) if hit == null else ""
					if sign_of != "" and (coach == null or coach.would_allow("build")):
						toggle_build(sign_of)
					elif hit == null and parking_view.vehicle_at(at) != "":
						# a click on a vehicle parked at the gate opens the Town Board, as its button does
						toggle_town()
					elif mb.shift_pressed and hit != null and hit.kind == "person":
						# shift and a click on a person: they join the group (or leave it)
						_toggle_person(hit.ref)
					elif mb.shift_pressed and hit == null:
						pass # (shift keeps the group: a click on empty ground does not let go of it)
					else:
						_try_select(hit)
				drag = null
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	elif ev is InputEventMouseMotion:
		var mm: InputEventMouseMotion = ev
		if drag != null:
			var dv: Vector2 = mm.position - drag.pos
			var panning: bool = drag.get("pan", false)
			if not drag.moved and dv.length() > BOX_PX:
				drag.moved = true
				hover = null
				Input.set_default_cursor_shape(Input.CURSOR_DRAG if panning else Input.CURSOR_CROSS)
			if drag.moved:
				if panning:
					follow = null
					var was_at := cam_center
					cam_center = drag.center - dv / zoom_px
					_clamp_camera()
					_did("pan", cam_center.distance_to(was_at))
				else:
					drag.box = Rect2(drag.pos, Vector2.ZERO).expand(mm.position)
		else:
			var at := _screen_to_tile(mm.position)
			var h = _pick(at)
			hover = h.ref if h != null and h.kind == "person" else null
			Input.set_default_cursor_shape(_cursor_for(h, at))
	elif ev is InputEventMagnifyGesture:
		_zoom_at(ev.factor, ev.position)
	elif ev is InputEventPanGesture:
		_zoom_at(exp(-ev.delta.y * 0.06), ev.position)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_SPACE:
				_set_speed(1 if speed == 0 else 0)
			KEY_1:
				_set_speed(1)
			KEY_2:
				_set_speed(2)
			KEY_3:
				_set_speed(3)
			KEY_ESCAPE:
				# Esc ends a box that is being drawn; else it lets go of the selection (the whole group); with nothing
				# selected it opens the pause menu
				if drag != null and drag.moved and not drag.get("pan", false):
					drag = null
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				elif selection != null or not selected_people.is_empty():
					_select(null)
				else:
					open_pause()
			KEY_A:
				# Ctrl+A (Cmd+A on a Mac): everyone in the yard. (A alone pans, with W S D.)
				if ev.ctrl_pressed or ev.meta_pressed:
					select_everyone()
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
			KEY_L:
				_gizmo("lure")
			KEY_B:
				_gizmo("job_builders")
			KEY_M:
				_gizmo("job_bench")
			KEY_J:
				toggle_jobs()
			KEY_N:
				toggle_build()
			KEY_V:
				_toggle_fields()
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
					_try_select({"kind": "person", "ref": p})
					_focus(Vector2(p.x, p.y))
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------- loop --

func _process(delta: float) -> void:
	var dt := clampf(delta, 0.0, StepClock.MAX_FRAME)
	clock += dt
	# the tutorial's coach looks at the lesson first: it may hold the game still for this frame
	if coach != null:
		coach.tick(dt)
	if hints != null:
		hints.tick(dt)
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

	if title_mode:
		_title_camera(dt)
	# (Ctrl or Cmd with a letter is a command, Ctrl+A selecting everyone, not the camera's key)
	var cmd := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	var kx := int((Input.is_key_pressed(KEY_D) and not cmd) or Input.is_key_pressed(KEY_RIGHT)) - int((Input.is_key_pressed(KEY_A) and not cmd) or Input.is_key_pressed(KEY_LEFT))
	var ky := int((Input.is_key_pressed(KEY_S) and not cmd) or Input.is_key_pressed(KEY_DOWN)) - int((Input.is_key_pressed(KEY_W) and not cmd) or Input.is_key_pressed(KEY_UP))
	# (the arrow keys are the menu's while one is open)
	if (kx != 0 or ky != 0) and not menu_open:
		follow = null
		cam_center += Vector2(kx, ky) * dt * 700.0 / zoom_px
		_did("pan", Vector2(kx, ky).length() * dt * 700.0 / zoom_px)
	if follow != null:
		cam_center += (Vector2(follow.x, follow.y) - cam_center) * minf(1.0, dt * 5.0)
	_clamp_camera()
	_apply_camera()
	_handle_events()
	_prune_selection()
	_sync_views()
	var look: Dictionary = sim.storyteller.look()
	lighting.update(sim.hour, sim.bell_rung, clock, fx.flash_lights(), look)
	# snow falls on a snow day of a campaign (and in no other game); the ground keeps a light cover all through a snowy season
	var campaign: bool = sim.seasons.campaign
	snow.follow({"snow": campaign and bool(look.get("snow", false))}, campaign and sim.seasons.snow_share() > 0.0, lighting.dark, dt)
	ground_snow.visible = snow.ground > 0.01
	ground_snow.modulate.a = snow.ground
	dressing_view.update()
	parking_view.update(dt * gate_rate(speed))    # (the vehicles, and the gate's demand for gate_node: the gate keeps the cars' time)
	street_air.update(dt)
	build_view.update(clock)
	glow.t = clock
	glow.queue_redraw()
	overlay.queue_redraw()
	hud_t -= dt
	if hud_t <= 0.0:
		hud_t = 0.1
		if not title_mode:
			hud.update_hud(sim, speed, sound_on, walkers)
			if coach != null:
				coach.after_hud()
		var near := 0
		for z in sim.zombies:
			if (z.state == "attack" or z.state == "approach") and Vector2(z.x, z.y).distance_to(cam_center) < 30.0:
				near += 1
		sound.set_ambience(lighting.dark, minf(1.0, near / 14.0), 0.1)
		music.follow(not title_mode and hud.game_over == null, raid_open(), lighting.dark, minf(1.0, near / 14.0), 0.1)
	if shot_path != "":
		frame_count += 1
		if frame_count == shot_frames - 2 and shot_box.size != Vector2.ZERO:
			var from_px := _tile_to_screen(shot_box.position)
			var to_px := _tile_to_screen(shot_box.end)
			drag = {"pos": from_px, "center": cam_center, "moved": true, "button": MOUSE_BUTTON_LEFT, "box": Rect2(from_px, Vector2.ZERO).expand(to_px), "shift": false, "pan": false}
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
	snow.advance(h)
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
		# someone who has joined since the yard was built (a recruit at the gate) gets their node here
		if not pawn_nodes.has(p):
			_add_person_pawn(p)
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
	# a season's first morning has its own banner ("Winter begins", with the season's line): the day's banner that
	# follows it in the same moment would cover it, so it is left out
	var season_turned := false
	for e in sim.events:
		if e.type == "season":
			season_turned = true
	for e in sim.events:
		if coach != null:
			coach.on_event(e)
		match e.type:
			"shot":
				sound.play("shot_%s" % e.weapon, _vol_at(e.x, e.y) * 0.8)
			"bell":
				sound.play("bell", 1.0, 0.0)
			"groan":
				# (the stragglers of the streets by day are far and many: a few of their groans are heard, and quietly)
				if randf() < (0.2 if bool(e.get("stray", false)) else 0.6):
					var d := Vector2(e.x, e.y).distance_to(cam_center)
					# a brute groans deep and a little louder, a runner thin and high
					var kind: String = String(e.get("kind", "walker"))
					var pitch := 0.72 if kind == "brute" else (1.3 if kind == "runner" else 1.0)
					var loud := 1.3 if kind == "brute" else 1.0
					sound.play("groan", minf(1.0, 10.0 / (d + 12.0) / 0.3) * loud * (0.5 if bool(e.get("stray", false)) else 1.0), 0.12, pitch)
			"lure":
				# the alarm goes off: the bell, higher and thinner than the dusk bell
				sound.play("bell", 0.6, 0.02, 1.4)
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
				build_view.hammer(e, fx)
			"built":
				# a building is finished: a small high bell and the menus' chime, and a little dust where it stands
				sound.play("bell", 0.3, 0.02, 1.8)
				sound.ui("ui_confirm", 0.9)
				build_view.celebrate(String(e.plot), fx)
			"demolished":
				sound.play("crash", 0.45)
				build_view.celebrate(String(e.plot), fx)
			"stab":
				sound.play("stab")
			"thud":
				sound.play("thud", _vol_at(e.x, e.y))
			"banner":
				if not (season_turned and String(e.text).begins_with("Day ")):
					hud.show_banner(e.text, e.sub)
			"season":
				# the season turns: a deep, slow bell
				sound.play("bell", 0.7, 0.0, 0.7)
			"bark":
				# what someone said: a speech bubble over their head (the overlay keeps quiet under a menu)
				overlay.add_bark(e)
			"story_card":
				story_ui.on_story_card()
			"dawn_report":
				story_ui.on_dawn_report()
			"day_start":
				_autosave()
			"arrived":
				_on_arrival(String(e.who))
	sim.events.clear()


## Someone has reached the gate (a recruit, recruits.gd): a soft bell and the chime, and their card, lit for a moment
## among the others. (Their pawn is made by the next _sync_views; the banner is a "banner" event of its own.)
func _on_arrival(who: String) -> void:
	sound.play("bell", 0.4, 0.02, 1.35)
	sound.ui("ui_confirm", 0.8)
	for p in sim.people:
		if p.id == who:
			hud.add_person(p)
			hud.flash_card(p)


## The dawn save: one file, written over at each new day. Not in a screenshot
## run, and not once the run is lost (that would replace the last good one).
func _autosave() -> void:
	if shot_path == "" and sim.over == "" and not title_mode and not tutorial:
		SaveGame.write(sim, SaveGame.AUTO_PATH)


# ----------------------------------------------------------------- tutorial --
# Orientation Day: the scenario (scripts/sim/orientation.gd) and its coach (scripts/ui/coach.gd).

## Starts Orientation Day: the scene reloads on the tutorial's scenario (Story, a fixed seed, a run
## that cannot be lost) with a coach teaching it. The title's Orientation Day button and the
## wrap-up's Replay call this.
func start_tutorial() -> void:
	_begin({"tutorial": true})


## The tips of a normal run, over the HUD (none in the tutorial, on the title or in a screenshot).
func _start_hints() -> void:
	if tutorial or title_mode or shot_path != "":
		return
	hints = Hints.new()
	add_child(hints)
	hints.setup(self, hud, sim, Hints.load_hints())


## Builds the coach over the HUD and starts it where the scenario was left (a new run: the first
## step; a loaded save: the step it was on), or at `tutorial_step` (--tutorial=N).
func _build_coach() -> void:
	coach = Coach.new()
	add_child(coach)
	coach.setup(self, hud, sim, Coach.load_steps())
	coach.begin(tutorial_step)


# ------------------------------------------------------------- automation --

func _parse_args() -> void:
	var advance := 0.0
	var lure_seg := -1
	var show_build := false
	var build_plot := ""
	var show_town := false
	var town_place := ""
	var town_focus := ""
	var town_ride := ""
	var raid_spec := ""
	var raid_do := ""
	# --season=N begins the long game in season N (0 Autumn, 1 Winter, 2 Spring, 3 Summer), before --hour sets the clock
	var season_asked := season_from_args(OS.get_cmdline_user_args())
	if season_asked >= 0:
		stage_season(season_asked)
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
				_set_hour(float(v))
			"advance":
				advance = float(v)
			"cam":
				var c := v.split(",")
				cam_center = Vector2(float(c[0]), float(c[1]))
				if c.size() > 2:
					zoom_px = float(c[2])
			"recruit":
				# --recruit=<id> lets that caller of the radio (ana, walt, hector, or the id of a generated one; none
				# named: the next) in at the gate now, with a --crew=3 start. At 07:00, unless --hour is given first.
				stage_recruit(v)
			"select":
				# --select=<id> selects that person; --select=<id>+<id>+<id> a group (the first is the primary)
				var chosen: Array = []
				for id in v.split("+"):
					for p in sim.people:
						if p.id == id:
							chosen.append(p)
				select_people(chosen)
			"box":
				# --box=x0,y0,x1,y1 (tiles) shows a selection box being dragged over that part of the yard, as a screenshot
				# of it (after --cam, which fixes where the tiles are on the screen)
				var corner := v.split(",")
				if corner.size() == 4:
					shot_box = Rect2(Vector2(float(corner[0]), float(corner[1])), Vector2.ZERO).expand(Vector2(float(corner[2]), float(corner[3])))
			"wall":
				# --wall=N selects wall section N (by its id)
				for s in sim.segments:
					if s.id == int(v):
						_select({"kind": "segment", "ref": s})
			"fields":
				# the fields-of-fire view starts on
				fields = true
				hud.set_fields(true)
			"jobs":
				# --jobs opens the Jobs screen (give --speed before it: the rules wait while it is open)
				hud.last_speed = speed
				hud.open_jobs(sim)
			"jobs-hover":
				# --jobs-hover=station:bench (or post:gate, person:dez) opens it with that place marked in the world
				var what := v.split(":")
				if hud.jobs_screen == null:
					hud.last_speed = speed
					hud.open_jobs(sim)
				if hud.jobs_screen != null and what.size() == 2:
					hud.jobs_screen.show_marks(what[1] if what[0] == "station" else "", what[1] if what[0] == "post" else "", what[1] if what[0] == "person" else "", true)
			"build":
				# --build opens the Build screen (--build=<plot id> on that plot), once the other arguments are in
				# (the plots staged with --build-site and --build-built; the --speed it pauses)
				show_build = true
				build_plot = v
			"town":
				# --town opens the Town Board (--town=<place id> on that place) in a settlement game (--crew=3), once the other
				# arguments are in (the board staged with --town-reveal, --town-state and --town-send; the --speed it pauses)
				show_town = true
				town_place = v
			"raid":
				# --raid=<place id or kind>[,<seed>] opens a played trip to that place with the people of the crew (up to three),
				# once the other arguments are in (the screenshot then shows it: --frames long enough for the squad to walk)
				raid_spec = v
			"raid-stub":
				raid_stub = true
			"raid-do":
				# --raid-do=<steps joined by +> plays the raid a little before the shot: all, one, sel:N, search:N, move:X:Y,
				# help:N, down:N, wait:SECONDS, pause, ask, retreat, end (see raid_scene.gd `stage`)
				raid_do = v
			"town-reveal":
				# --town-reveal=<place id>,<place id> (or "all") shows places of the board that are hidden at the start
				for id in (sim.town.state.keys() if v == "all" else v.split(",")):
					sim.town.reveal(String(id))
			"town-state":
				# --town-state=<place id>:cleared,<place id>:claimed[:<person id>+<person id>] stages places (a claimed place
				# may be held by people, who are off the map): no scrap is paid for them
				_stage_town(v)
			"town-ride":
				# --town-ride=<vehicle kind or id> chooses that parked vehicle in the board's party picker when it opens (--vehicle first)
				town_ride = v
			"town-focus":
				# --town-focus=<place id> puts the keyboard on that pin when the board opens (to see the ring)
				town_focus = v
			"town-send":
				# --town-send=<person id>+<person id>:<place id>:<loot|scout|clear>[:<vehicle kind or id>] sends a party at once, as
				# the board does (by a vehicle that is in the fleet: --vehicle first)
				_stage_party(v)
			"trip-phase":
				# --trip-phase=<out|driving_out|away|driving_in|unloading>,<0 to 1>[,<door id>] puts the first party that has a
				# vehicle in that state (--vehicle and --town-send first, --speed=0 so that it stays): driving, that share of
				# its route; out or unloading, a door of the car (the first, or the one named) that share through its swing
				_stage_trip_phase(v)
			"vehicle":
				# --vehicle=<kind>[,<kind>] puts these vehicles in the colony's fleet, parked at the gate (a settlement game, --crew=3;
				# the kinds are those of assets/data/vehicles.json: sedan, pickup, van, bus); --fuel=N fills the tank
				# (a kind may carry its condition, a share of its hp: --vehicle=sedan:30)
				for entry in v.split(","):
					var kf := String(entry).strip_edges().split(":")
					var added: Dictionary = sim.vehicles.add(kf[0])
					if not added.is_empty():
						if kf.size() > 1 and kf[1].is_valid_float():
							added["hp"] = float(sim.vehicles.kind(kf[0]).hp) * clampf(float(kf[1]) / 100.0, 0.0, 1.0)
						sim.events.clear()
			"fuel":
				sim.vehicles.fuel = clampf(float(v), 0.0, sim.vehicles.FUEL_CAP)
			"build-scrap":
				# --build-scrap=N sets the scrap in the stores (to show what cannot be ordered, say)
				sim.stock.scrap = float(v)
			"build-nobody":
				# --build-nobody takes everyone off the Builders job (to show what the page says of a site nobody builds)
				for p in sim.jobs.crew_of("builders"):
					sim.jobs.unassign(p)
			"build-site":
				# --build-site=<plot>:<building>[:<share done, 0 to 1>],... puts sites up (no scrap is paid for them)
				_stage_build(v, false)
			"build-built":
				# --build-built=<plot>:<building>,... stands buildings at once (no scrap is paid, nobody builds them)
				_stage_build(v, true)
			"lots":
				# --lots[=north,west] claims the lots of the ring at once (every one without a list; a settlement game, --crew=3): the
				# board's cleared places, the day and the scrap are not asked. Put it before --build-built (the ring plots) and
				# --damage or --breach (the walls)
				_stage_lots(v)
			"walls":
				# --walls[=N] stands a wall at N of the mouths (all of them without N) with the first kit that fits (--wall-kit=<kit>
				# picks that one where it fits), the lots they are in claimed; no scrap is paid and nobody builds them
				_stage_walls(int(v) if v.is_valid_int() else 99)
			"wall-kit":
				pass # (read by --walls, wherever it stands on the command line)
			"wall-site":
				# --wall-site=<mouth id>[:<share done, 0 to 1>] puts a half-built wall up at a mouth (the lot claimed, no scrap paid)
				_stage_wall_site(v)
			"walling":
				# --walling[=north,west] switches the standing order on for those of the claimed lots (all of them without a list)
				_stage_walling(v)
			"lure":
				# --lure=N sets the alarm on wall section N (scrap is given, the clock settled first)
				lure_seg = int(v)
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
			"tutorial":
				pass # --tutorial[=N] picks the scenario, before the run starts (see _ready and Scenario.run_from_args)
			"campaign", "season":
				pass # --campaign asks for the long game before the run starts (see _ready); --season=N is dealt with above
			"nohud":
				hud.visible = false
			"msaa":
				get_viewport().msaa_2d = int(v) as Viewport.MSAA
			"nolights":
				lighting.visible = false
			"build-plots":
				# --build-plots keeps the plots' outlines lit, as when the Build screen is open (for a screenshot of the yard)
				build_view.show_plots = true
			"build-pointer":
				# --build-pointer=x,y puts the pointer at that point of the yard (tiles): the plot nearest it shows its sign, and an
				# open street within five tiles its line (a screenshot has no mouse; without this the yard shows none of them)
				var xy := v.split(",")
				if xy.size() == 2 and xy[0].is_valid_float() and xy[1].is_valid_float():
					build_view.pointer = Vector2(float(xy[0]), float(xy[1]))
			"card":
				# --card=<id> puts a card of the storyteller's up (the radio card opens)
				sim.storyteller.force(v)
			"weather":
				# --weather=fog (or rain, or snow in a campaign) for the coming night, as a card would set it
				sim.weather = v
				sim.supplies.sources_day = sim.day    # (today's dawn has been rolled: the weather asked for stays for the day)
				if v == "snow":
					snow.follow({"snow": sim.seasons.campaign}, true, 0.0, 10.0)    # (it is already falling in the shot)
			"blackout":
				# --blackout: the generator is dead (see the storyteller)
				sim.storyteller.blackout = {"state": "dark", "at": sim.clock_min, "send": false, "fixer": "", "work": 0.0}
			"dawn":
				# --dawn shows a sample of the morning assembly
				sim.storyteller._report = {"day": 8, "night": 7, "kills": 41, "mvp": {"who": "Walt", "kills": 12}, "wall_lost": 310, "wall_mended": 180, "breaches": 0,
					"lost": [{"who": "Ana", "epitaph": "She would have wanted the lamp left on.", "how": "died"}], "hurt": ["Marcus"], "skill_ups": [{"who": "Dez", "skill": "Building", "value": 10}],
					"events": ["Heavy rain: The barrels are full."], "mood": "Mostly steady; Marcus is shaken.", "alive": 5}
				story_ui.show_dawn()
	if show_build:
		hud.last_speed = speed
		hud.open_build(build_plot, sim)
	if show_town:
		hud.update_hud(sim, speed, sound_on, 0)    # (the HUD has to have seen the game first)
		hud.last_speed = speed
		hud.open_scavenge(selection)
		if hud.town_board_open() and town_place != "":
			hud.scavenge_dialog.select_place(town_place)
		if hud.town_board_open() and town_ride != "":
			for parked in sim.vehicles.parked():
				if String(parked.id) == town_ride or String(parked.kind) == town_ride:
					hud.scavenge_dialog.choose_vehicle(String(parked.id))
					break
		if hud.town_board_open() and town_focus != "" and hud.scavenge_dialog.map.pins.has(town_focus):
			hud.scavenge_dialog.map.pins[town_focus].grab_focus()
	if raid_spec != "":
		_stage_raid(raid_spec)
		if raid_do != "" and raid_open():
			raid.stage(raid_do)
	if lure_seg >= 0:
		sim.stock.scrap = maxf(float(sim.stock.scrap), 10.0)
		for s in sim.segments:
			if s.id == lure_seg:
				sim.tactics.order_lure(s)
	if advance > 0.0:
		var steps := int(advance * 30.0)
		for i in steps:
			_sim_step()
			_visual_step(StepClock.STEP)
		for e in sim.events:
			if e.type == "banner":
				hud.show_banner(e.text, e.sub)
		sim.events.clear()


## The hour of day, as `--hour=` sets it: the phase, the bell and the game clock follow (it counts minutes from 07:00
## on day 1).
func _set_hour(hh: float) -> void:
	sim.minutes = hh * 60.0
	# (the season's own hours: in Autumn, and in any game that is not a campaign, they are 19:00 and 6.5 as ever)
	sim.phase = sim.seasons.phase_at(sim.minutes)
	sim.bell_rung = hh >= sim.seasons.dusk_hour() or hh < sim.seasons.dawn_hour() - 0.5
	sim.clock_min = (sim.day - 1) * 1440.0 + fposmod(sim.minutes - 420.0, 1440.0)


## A screenshot's way of beginning in a season (--season=N): the long game at the first morning of season `i` (0
## Autumn to 3 Summer), a little after its dawn, so that the day goes on from there (`seasons.jump_to` is the rules'
## own). `--hour` may then move the clock.
func stage_season(i: int) -> void:
	sim.seasons.jump_to(i)
	_set_hour(maxf(7.0, sim.seasons.dawn_hour() + 0.5))


## A screenshot's way of letting a caller in (--recruit): `id` is the one of the radio's queue who comes in at the gate
## now, "" for the next. False when no one is waiting by that name (a classic start has nobody waiting). The arrival is
## the rules' own (the banner, the alert, the mood, a bite for the bitten): it happens at once, at the gate hour.
func stage_recruit(id: String) -> bool:
	var queue: Array = sim.recruits.queue
	if id == "" and queue.is_empty():
		sim.recruits.current_caller()    # the queue ran out: the next caller is made
	var at := -1
	for i in queue.size():
		if id == "" or String(queue[i].id) == id:
			at = i
			break
	if at < 0:
		return false
	if not (sim.phase == "day" and sim.hour >= 7.0):
		_set_hour(7.2)
	sim.recruits.incoming.append({"def": queue[at], "day": sim.day})
	queue.remove_at(at)
	sim.recruits.update(0.0)
	return true


## A screenshot's way of putting sites up and buildings on the plots (--build-site, --build-built): "plot:building"
## entries, comma-separated, a share done (0 to 1) after a third colon for a site. Nothing is paid and no event is left.
func _stage_build(spec: String, finished: bool) -> void:
	var scrap: float = sim.stock.scrap
	for entry in spec.split(","):
		var f := entry.split(":")
		if f.size() < 2:
			continue
		sim.stock.scrap = 1000.0
		if not sim.build.order(f[0], f[1]):
			continue
		var pl: Dictionary = sim.build.plot(f[0])
		if finished:
			sim.build._finish(pl)
			sim.alerts.erase("built-%s" % f[0])
		elif f.size() > 2:
			pl.site.progress = clampf(float(f[2]), 0.0, 1.0) * float(pl.site.work)
	sim.stock.scrap = scrap
	sim.events.clear()


## `--lots`: every lot of the ring claimed (round 9), as a screenshot has it: the day, the cleared places and the scrap the
## claim asks for are made up for the moment (the places stay cleared) and nothing is paid. Does nothing in a game with no lots.
func _stage_lots(only: String = "") -> void:
	if not sim.lots.on:
		return
	var wanted: PackedStringArray = only.split(",", false) if only != "" else PackedStringArray()
	var day: int = sim.day
	var scrap: float = sim.stock.scrap
	for id in sim.town.state:
		sim.town.reveal(id)
		sim.town.state[id].cleared = true
	sim.day = maxi(day, 99)
	for l in sim.lots.lots():
		if not wanted.is_empty() and not wanted.has(String(l.id)):
			continue
		sim.stock.scrap = 10000.0
		sim.lots.claim(String(l.id))
	sim.day = day
	sim.stock.scrap = scrap
	sim.events.clear()
	for l in sim.lots.lots():
		sim.alerts.erase("lot-%s" % String(l.id))


## A wall at a mouth, ordered and finished at once (no scrap kept, nobody builds it): `kit` (a kit's id) where it fits the mouth,
## else the first kit that does. The lot is claimed first. False when it did not go up.
func _stage_wall(mouth_id: String, kit: String, finished: bool, share: float = 0.5) -> bool:
	_stage_lots(String(sim.lots.mouth(mouth_id).get("lot", "")))
	var scrap: float = sim.stock.scrap
	sim.stock.scrap = 10000.0
	var kits: Array = sim.lots.kits_for(mouth_id)
	var building := "wall_%s" % kit
	if not kits.has(building):
		building = String(kits[0]) if not kits.is_empty() else ""
	var ok: bool = building != "" and sim.build.order(mouth_id, building)
	if ok:
		var pl: Dictionary = sim.build.plot(mouth_id)
		if finished:
			sim.build._finish(pl)
		else:
			pl.site.progress = clampf(share, 0.0, 1.0) * float(pl.site.work)
	sim.stock.scrap = scrap
	sim.events.clear()
	sim.alerts.erase("wall-%s" % mouth_id)
	return ok


## `--walls[=N]`: walls at the first N mouths (the data's order), of the kit `--wall-kit=` names where it fits.
func _stage_walls(count: int) -> void:
	if not sim.lots.on:
		return
	var kit := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--wall-kit="):
			kit = String(a).trim_prefix("--wall-kit=")
	var n := 0
	for m in sim.lots.mouths():
		if n >= count:
			break
		if _stage_wall(String(m.id), kit, true):
			n += 1


## `--wall-site=<mouth id>[:<share done>]`.
func _stage_wall_site(spec: String) -> void:
	if not sim.lots.on:
		return
	var f := spec.split(":")
	_stage_wall(f[0], "", false, float(f[1]) if f.size() > 1 else 0.5)


## `--walling[=north,west]`: the standing order ("Wall the streets as the scrap allows") on for the lots claimed (put it after `--lots`).
func _stage_walling(only: String = "") -> void:
	if not sim.lots.on:
		return
	var wanted: PackedStringArray = only.split(",", false) if only != "" else PackedStringArray()
	for l in sim.lots.lots():
		if wanted.is_empty() or wanted.has(String(l.id)):
			sim.lots.set_auto_walling(String(l.id), true)


## `--town-state=`: places of the board cleared or claimed (and held) without a trip.
func _stage_town(spec: String) -> void:
	for entry in spec.split(","):
		var f := entry.split(":")
		if f.size() < 2 or not sim.town.state.has(f[0]):
			continue
		sim.town.reveal(f[0])
		if f[1] == "cleared" or f[1] == "claimed":
			sim.town.state[f[0]].cleared = true
		if f[1] == "claimed":
			sim.town.state[f[0]].claimed = true
			if f.size() > 2:
				var who: Array = []
				for id in f[2].split("+"):
					for p in sim.people:
						if p.id == id:
							who.append(p)
				if not who.is_empty():
					sim.town.garrison_send(f[0], who)


## `--town-send=`: a party out at once (the settlement game's `send`, from a screenshot's arguments).
func _stage_party(spec: String) -> void:
	var f := spec.split(":")
	if f.size() < 2:
		return
	var who: Array = []
	for id in f[0].split("+"):
		for p in sim.people:
			if p.id == id:
				who.append(p)
	var ride := ""
	if f.size() > 3:
		for v in sim.vehicles.parked():
			if String(v.id) == f[3] or String(v.kind) == f[3]:
				ride = String(v.id)
				break
	if not who.is_empty() and sim.scavenge.send(who, f[1], f[2] if f.size() > 2 else "loot", ride):
		sim.events.clear()


## `--trip-phase=`: a party that went by vehicle put in a state of the trip (a screenshot's staging; it stays there while the
## rules are paused). The numbers it sets are the fields of the saved state that the vehicle's view draws from.
func _stage_trip_phase(spec: String) -> void:
	var f := spec.split(",")
	var share := clampf(float(f[1]) if f.size() > 1 else 0.5, 0.0, 1.0)
	for party in sim.scavenge.parties:
		var vehicle_id := String(party.get("vehicle", ""))
		if vehicle_id == "":
			continue
		var state := String(f[0])
		party["state"] = state
		if state == "driving_out" or state == "driving_in":
			if float(party.get("drive_len", 0.0)) <= 0.0:
				party["drive_len"] = 30.0
			party["drive_t"] = share * float(party.drive_len)
		elif state == "out" or state == "unloading":
			var doors: Array = sim.vehicles.kind_of(vehicle_id).get("doors", [])
			var door := String(f[2]) if f.size() > 2 else (String(doors[0].id) if not doors.is_empty() else "")
			var who := String(party.members[0]) if not party.members.is_empty() else ""
			party["doors"] = [{"pid": who, "door": door, "t": share * 12.0, "dur": 12.0, "dir": "in" if state == "out" else "out"}]
		return


## `--raid=<place id or kind>[,<seed>[,<vehicle kind>]]`: a played trip opened at once with the first three people (a
## screenshot's staging; the seed is the site's, else the place's own; a vehicle kind puts one in the fleet and goes in it). The first place of the board with that id or kind.
func _stage_raid(spec: String) -> void:
	var f := spec.split(",")
	var place: Dictionary = {}
	for pl in sim.town.all_places():
		if String(pl.id) == f[0] or (place.is_empty() and String(pl.kind) == f[0]):
			place = pl
			if String(pl.id) == f[0]:
				break
	if place.is_empty():
		place = {"id": f[0], "name": f[0].capitalize(), "kind": f[0], "danger": 1, "loot": {"food": [8, 14], "water": [10, 20]}}
	var party: Array = []
	for p in sim.people:
		if party.size() < 3 and not p.dead and p.away == null:
			party.append(p)
	if f.size() > 1 and f[1].is_valid_int():
		raid_seed = int(f[1])
	# a third field puts a vehicle of that kind in the fleet and goes in it (`--raid=houses,5,van`)
	var vehicle_id := ""
	if f.size() > 2 and sim.vehicles.kind(f[2]).size() > 0:
		vehicle_id = "raid_%s" % f[2]
		sim.vehicles.fleet.append({"id": vehicle_id, "kind": f[2], "hp": 80.0, "state": "parked"})
	open_raid(party, place, vehicle_id, 1.0, Callable())
	raid_seed = -1


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
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(400, 400)
	_unhandled_input(press)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(300, 350)
	_unhandled_input(move)
	press.pressed = false
	press.position = move.position
	_unhandled_input(press)
	print("selftest: middle-drag pans camera by ", (cam_center - c0).snapped(Vector2(0.01, 0.01)))
	# a left-drag draws a box round the middle of the window and selects whoever is in it; Ctrl+A everyone
	var box_from := _vp() / 2.0 - Vector2(60, 60)
	var box_to := _vp() / 2.0 + Vector2(60, 60)
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	left.position = box_from
	_unhandled_input(left)
	var sweep := InputEventMouseMotion.new()
	sweep.position = box_to
	_unhandled_input(sweep)
	left.pressed = false
	left.position = box_to
	_unhandled_input(left)
	print("selftest: left-drag box selected %d, camera stayed %s" % [selected_people.size(), (cam_center - c0).snapped(Vector2(0.01, 0.01))])
	var all := InputEventKey.new()
	all.keycode = KEY_A
	all.ctrl_pressed = true
	all.pressed = true
	_unhandled_input(all)
	print("selftest: Ctrl+A selected ", selected_people.size())
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
