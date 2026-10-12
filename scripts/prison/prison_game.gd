## EXPERIMENT (prison extraction): the whole game loop in one scene. BASE: a hand-authored prison compound (prison_base.gd) with ten people at work (prison_crew.gd) and a mass of dead in the pen in
## front of the gate. GO OUT (E at the gate or the truck): a generated 64 x 64 town (TownGen, blocks 2) played with the real Sim (avatar, shooting, melee, search, dormant dead that wake near you).
## EXTRACT: stand in a pickup ring for 2 s, a short cutscene, and the loot (the raid sim's stock) is banked in the base's stores. DIE in the raid: the pack is lost, same cutscene back.
## Keys: WASD walk, mouse aim, left button fire (raid only), R reload, F melee, E use/search/go out, Shift sprint is not wired, wheel zoom, M overview, Esc quit.
## Flags: --shot=path --frames=N (screenshot then quit), --raid (start in a raid), --at=x,y (avatar position), --seed=N, --auto=raid|extract|die (scripted run for checks), --cam=x,y,zoom.
##
## PHASES (`phase`): "clear" first (the party of Ruth + 3 allies walks in through a breach in the west fence; ten zones full of dormant dead; each cleared zone frees crew; the gate stays shut), then
## "managed" (the base loop above). HOOK for other systems: connect `phase_changed(new_phase)` or test `phase == "managed"` (`in_managed()`): base attacks, the siege and the fence run only then. The
## fence breach (`Base.GAP`) is a normal fence tile in the managed layout. Flags: --managed boots straight into "managed"; --prison alone boots "clear"; --auto=clearall (kills zone by zone and
## searches one container each, for checks), --auto=ally (Ruth walks into the infirmary and the allies get bitten), --log prints ally and zone lines.
extends Node2D

signal phase_changed(new_phase: String)

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
const Tower := preload("res://scripts/prison/prison_tower.gd")
const Sound := preload("res://scripts/audio/sound.gd")
const Siege := preload("res://scripts/prison/prison_siege.gd")
const DogNode := preload("res://scripts/render/dog_node.gd")
const Pack := preload("res://scripts/prison/prison_pack.gd")
const Clean := preload("res://scripts/prison/prison_clean.gd")
const Loot := preload("res://scripts/prison/prison_loot.gd")    # RAIDS hook
const People := preload("res://scripts/prison/prison_people.gd")    # RAIDS hook
const Econ := preload("res://scripts/prison/prison_econ.gd")    # ECON hook
const Board := preload("res://scripts/prison/prison_board.gd")    # UI hook
const Upg := preload("res://scripts/prison/prison_upgrades.gd")    # WORLD hook
const PHud := preload("res://scripts/prison/prison_hud.gd")
const Drive := preload("res://scripts/prison/prison_drive.gd")    # --drive=NAME: real input events (fix round B)
const Arms := preload("res://scripts/prison/prison_arms.gd")    # SQUAD hook: guns and the weapon rack
const Squad := preload("res://scripts/prison/prison_squad.gd")    # SQUAD hook: raid companions
const SearchRules := preload("res://scripts/town/search.gd")
const Loadout := preload("res://scripts/prison/prison_loadout.gd")    # SQUAD hook: the loadout card
const DAY_MIN_PER_SEC := 4.0    # 6 real minutes a day
const GUARD_RANGE := 11.0
const FENCE_ZONE := 5.0    # a guard shoots what comes within this many tiles of the fence line

const CLEAR_WAKE_R := 10.0
const RELOAD_EVERY := 5    # a crew gun is reloaded after this many shots
const RELOAD_SECS := 1.7
const ALLY_FOLLOW := 3.6
const ALLY_RANGE := 9.0
const ALLY_REVIVE_HP := 30.0
const BITE_R := 0.95
const BITE_DMG := 8.0
const DOWN_SECS := 20.0
const REVIVE_SECS := 2.0
# (ammo 60 less the 40 round kit Ruth takes on entering = 20 left in the stores)
const CLEAR_STORES := {"food": 25.0, "water": 12.0, "ammo": 60.0, "meds": 3.0, "scrap": 4.0, "parts": 2.0, "fuel": 0.0}

const TILE := GD.TILE
const CAMERA_EASE := 8.0
const EXTRACT_R := 2.2
const EXTRACT_S := 2.0
const LOADOUT_AMMO := 40.0
const STOCK_KEYS := ["food", "water", "ammo", "meds", "scrap", "parts", "fuel"]

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
var stores := {"food": 40.0, "water": 60.0, "ammo": 80.0, "meds": 6.0, "scrap": 30.0, "parts": 2.0, "fuel": 0.0}
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
var aim_hold := {}    # person id -> seconds the aimed pose is still held
var shot_n := {}    # person id -> shots fired (a reload pause every RELOAD_EVERY)
var alarm_t := 0.0
var alarm_cd := 0.0
var _repl_t := 0.0
var _trickle_t := 0.0
var shots_fired := 0
var dog
var phase := "managed"    # "clear" (clear the prison) then "managed" (the base loop). See the header.
var zone_done: Array = []    # bool per Base.ZONES
var _zone_t := 0.0
var allies_alive: Array = ["cole", "bea", "ike"]
var ally_chasers := {}    # Zombie -> member: dead that go for an ally instead of Ruth (see _step)
var revive_t := 0.0
var _hurt_t := 0.0
var _auto_i := 0
var pack: Pack    # the backpack (prison_pack.gd)
var cleaner    # prison_clean.gd: the periodic clean-up (managed base only)
var board    # UI hook: prison_board.gd (project, needs and roster window, toasts, stage card)
var econ    # ECON hook: prison_econ.gd, the economy core (kept over raids, active only in phase "managed")
var upg    # WORLD hook: prison_upgrades.gd, the visible result of each project and the crew's work on site
var back_t := 0.0    # seconds since she came back from a raid (the siege shows its "back in the middle" card while this runs)
var econ_gone: Array = []    # names of people who left while the crew was out of the scene
var loot    # RAIDS hook: prison_loot.gd (loot by place, raid marks, the gate's choice)
var driver    # --drive checks (prison_drive.gd)
var people    # RAIDS hook: prison_people.gd (survivors, recruits, people walking out)
var siege    # prison_siege.gd: fence segments and night attacks, runs only in phase "managed"
var arms    # SQUAD hook: prison_arms.gd (the guns, the weapon rack)
var squad    # SQUAD hook: prison_squad.gd (the companions of a raid)
var loadout    # SQUAD hook: prison_loadout.gd (the card at the gate and at the start of the clear phase)
var loadout_kit := {}    # what the card chose to take from the stores for the next raid ({} = the standard kit)
var squad_regroup := false    # the call to the pickup: the companions run to Ruth
var _weapon_card := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			var kv := s.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	data = GD.load_all()
	Arms.merge(data)    # SQUAD hook: the prison's guns over the shared data (this process only)
	_fit_window()
	_make_hud()
	pack = Pack.new(self)
	siege = Siege.new(self)    # (before the first stage: a --raid start has no base yet)
	econ = Econ.new(self)    # ECON hook
	if args.has("loot-lab"):    # RAIDS hook
		Loot.lab(int(args["loot-lab"]))
		get_tree().quit()
		return
	loot = Loot.new(self)    # RAIDS hook
	people = People.new(self)    # RAIDS hook
	arms = Arms.new(self)    # SQUAD hook
	squad = Squad.new(self)
	loadout = Loadout.new(self)
	upg = Upg.new(self)    # WORLD hook
	econ.person_left.connect(_econ_left)
	econ.project_done.connect(_econ_done)
	board = Board.new(self)    # UI hook (connects to the econ signals itself: toasts and the stage card replace the message lines)
	_shot_wait = int(args.get("frames", "90"))
	var au := String(args.get("auto", ""))
	var clear_auto := au == "clearall" or au == "ally" or au == "play" or au == "reach" or au == "loop"
	phase = "managed" if (args.has("managed") or args.has("raid") or (au != "" and not clear_auto)) else "clear"
	if args.has("raid") or (au != "" and not clear_auto):
		_enter_raid()
	else:
		_enter_base()
	if args.has("hour0"):    # a start hour that then runs (--hour freezes the clock)
		tod = float(args.hour0)
		siege.abs_h = tod
		siege._last_tod = tod


func _fit_window() -> void:
	var win := get_window()
	if win.mode == Window.MODE_WINDOWED and not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var s := DisplayServer.screen_get_scale(win.current_screen)
		var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
		var base_sz := Vector2(1280, 800)
		if args.has("window"):    # --window=1024x640: a smaller window for layout checks
			var wp := String(args.window).split("x")
			if wp.size() == 2:
				base_sz = Vector2(float(wp[0]), float(wp[1]))
		var want := Vector2i(base_sz * s)
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
	hud_label = _lbl(15, Vector2(8, 6))
	var plate := StyleBoxFlat.new()    # a subtle plate so the text reads on grass, concrete and brick
	plate.bg_color = Color(0.03, 0.05, 0.04, 0.55)
	plate.set_corner_radius_all(4)
	plate.content_margin_left = 8
	plate.content_margin_right = 8
	plate.content_margin_top = 3
	plate.content_margin_bottom = 3
	hud_label.add_theme_stylebox_override("normal", plate)
	hud.add_child(hud_label)
	prompt_label = _lbl(22, Vector2(0, 0))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(prompt_label)
	msg_label = _lbl(20, Vector2(0, 0))
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	prompt_label.size = Vector2(v.x * 0.6, 30)    # (wrapped, centred: a long line no longer runs under the minimap)
	prompt_label.position = Vector2(v.x * 0.2, v.y - 130)
	msg_label.size = Vector2(v.x * 0.6, 30)
	msg_label.position = Vector2(v.x * 0.2, v.y - 200)
	cap_label.size = Vector2(v.x, 80)
	cap_label.position = Vector2(0, v.y * 0.5 + 60)


func _stock_line() -> String:
	var parts: Array = []
	var rep: Dictionary = econ.daily_report() if phase == "managed" else {}    # ECON hook: per-day net for food and water
	for k in STOCK_KEYS:
		if phase != "managed" and (k == "parts" or k == "fuel"):
			continue
		if rep.has("res") and (k == "food" or k == "water"):
			parts.append("%s %d (+%d/-%d)" % [String(k).capitalize(), int(stores[k]), roundi(rep.res[k].prod), roundi(rep.res[k].cons)])
		else:
			parts.append("%s %d" % [String(k).capitalize(), int(stores[k])])
	return "  ".join(parts)


## ECON hook: someone leaves the base (morale), or a project is done (the fence tier changes the siege's hp).
func _econ_left(nm: String) -> void:
	if crew != null and people.walk_out(nm):    # RAIDS hook: they walk out of the gate
		return
	if crew == null:
		econ_gone.append(nm)
	else:
		_econ_remove(nm)


func _econ_remove(nm: String) -> void:
	if not econ_gone.has(nm):
		econ_gone.append(nm)
	for m in crew.members.duplicate():
		if String(m.def.name) == nm:
			crew.members.erase(m)
			if m.def.has("ex_ally"):
				allies_alive.erase(String(m.def.id))
			if m.has("node") and is_instance_valid(m.node):
				m.node.queue_free()


func _econ_done(id: String) -> void:
	if String(id).begins_with("fence"):
		siege.apply_fence(econ.fence_mult(), String(id) == "fence1")


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
	if revive_t > 0.0:
		bars.draw_rect(Rect2(v.x / 2 - 110, v.y - 84, 220, 12), Color(0, 0, 0, 0.6))
		bars.draw_rect(Rect2(v.x / 2 - 110, v.y - 84, 220.0 * clampf(revive_t / REVIVE_SECS, 0, 1), 12), Color(0.4, 0.8, 1.0))
	if mode == "raid" and extract_t > 0.0:
		bars.draw_rect(Rect2(v.x / 2 - 110, v.y - 84, 220, 12), Color(0, 0, 0, 0.6))
		bars.draw_rect(Rect2(v.x / 2 - 110, v.y - 84, 220.0 * clampf(extract_t / EXTRACT_S, 0, 1), 12), Color(0.4, 0.9, 0.5))
	_draw_minimap(v)
	PHud.draw(self, bars, v)
	if mode == "raid":
		squad.draw_hud(bars, v)    # SQUAD hook: the card of the companions
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
	fx.combat.decal_hold = 600.0    # stains stay until a cleaner comes (prison_clean.gd), up to about 15 minutes
	fx.combat.decal_life = 900.0
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
	var decks := DrawNode.new()    # tower decks: under the guards
	decks.z_index = 5
	decks.painter = _paint_decks
	world.add_child(decks)
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
	arms.apply(run.avatar_p)    # SQUAD hook: the gun she chose (before the pawn is made: it draws that gun)
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
	_msg_t = 0.0    # (no message of the last stage is carried over)
	msg_label.text = ""
	mode = "base"
	base = Base.new()
	var clear := phase == "clear"
	var t: Dictionary = base.build(1, clear)
	_make_stage(t, false)
	if clear:
		run.invulnerable = false
		run.sim.quiet = false
		run.field.wake_r = CLEAR_WAKE_R
		run.field.sleep_r = 30.0
		run.field.active_cap = 60
		if zone_done.is_empty():
			stores = CLEAR_STORES.duplicate()
			zone_done.resize(Base.ZONES.size())
			zone_done.fill(false)
			tod = 9.0
			pack.kit(stores)    # her rounds are the pack's (inv is active): without the kit she has the 6 loaded shots and cannot reload
		run.sim.stock = stores    # the same dictionary: what a search finds is in the stores at once
		pack.attach(run.sim, base.stations.stores)
		run.avatar_p.x = Base.START.x
		run.avatar_p.y = Base.START.y
	else:
		run.invulnerable = true
		run.sim.quiet = true
		run.field.wake_r = 45.0
		run.field.sleep_r = 80.0
		run.field.active_cap = 100
		run.sim.stock = stores    # (the same dictionary: the stash window moves real stock)
		pack.attach(run.sim, base.stations.stores)
		run.avatar_p.x = Base.SPAWN.x
		run.avatar_p.y = Base.SPAWN.y
	run.sim.minutes = 8.0 * 60.0
	crew = Crew.new()
	crew.setup(run.sim, world, base, data, clear)
	crew.econ_owned = ["food", "water"]    # ECON hook: food and water come from the economy, not from the crew's stops (and the freed crew eat nothing until the prison is secured)
	if not clear:
		for nm in econ_gone:    # (kept for good: a person who walked out does not come back with the next rebuild of the crew)
			_econ_remove(String(nm))
		if args.has("econ") and String(args.econ).begins_with("start:"):
			econ.debug_build(String(args.econ).trim_prefix("start:"))
	if not clear:
		for a in Crew.CREW_FROM_ALLIES:    # the allies are crew from here on (a job and a place), not followers
			if allies_alive.has(String(a.id)):
				crew._make(a, Base.SPAWN + Vector2(-2.0, 1.5 + float(allies_alive.find(String(a.id)))))
	if not clear:
		people.spawn_recruits()    # RAIDS hook: the people found in raids are crew again
		crew.sync_roles(econ)    # the roster's roles (set before the raid) move the rebuilt crew to the right work
	for m in crew.members:
		var n := PawnNode.new()
		n.setup(m.p, false, data, String(m.key))
		n.unarmed = bool(m.def.get("unarmed", false))
		if m.def.has("scale"):
			n.scale = Vector2.ONE * float(m.def.scale)
		if m.def.has("stand"):
			n.z_index = 1    # a tower guard stands above his deck and the fence
		entities.add_child(n)
		m["node"] = n
	if not clear:
		dog = DogNode.new()
		dog.setup(world.solid_p, world.W, 7)
		entities.add_child(dog)
	if args.has("allyhp"):
		for m in crew.members:
			if m.def.has("ally"):
				m.hp = float(args.allyhp)
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
	if siege == null:
		siege = Siege.new(self)    # SIEGE hook (kept over raids: fence hp, night count)
	if not clear:
		siege.setup()
		cleaner = Clean.new(self)
		cleaner.setup()
		upg.setup()    # WORLD hook
	if clear:
		_card("THE OLD PRISON", "Clear it. Hold it.", 2.2)
		_say("WASD walk, mouse aim, left button fire, R reload, F melee, E search. Clear every zone.", 7.0)
	else:
		_say("The compound. Walk around and watch the others work. E at the gate or the truck: go out.", 6.0)


func _enter_raid() -> void:
	_msg_t = 0.0    # (no message of the last stage is carried over)
	msg_label.text = ""
	mode = "raid"
	raids += 1
	var seed_i := int(args.get("seed", str(1000 + raids * 17 + int(Time.get_ticks_msec() % 997))))
	var t: Dictionary = TownGen.make(seed_i, {"blocks": 2})
	# the autumn crowns of the old trees are swapped for greens, pines and scrub (same art style, tools/make_prison_trees_blender.py)
	var swap := [24, 24, 22, 23, 0, 2, 5, 24]
	for tr in t.data.trees:
		var m := String(tr.file).get_file().trim_prefix("tree_").trim_suffix(".png")
		if m.is_valid_int() and [1, 3, 4, 6, 9, 10, 12].has(int(m)):
			tr["file"] = "res://assets/trees/tree_%d.png" % swap[int(absf(tr.x * 7.0 + tr.y * 13.0)) % swap.size()]
	var drop: Vector2 = Vector2(t.entry.pos)
	t["dead"] = (t.dead as Array).filter(func(r): return Vector2(r.pos).distance_to(drop) > 16.0)    # a quiet drop-off
	loot.begin(t, seed_i)    # RAIDS hook: loot by place and the marked places (before the sim reads the containers)
	if crew != null:
		squad.snapshot()    # SQUAD hook: who could go (the base is torn down by the next line)
	_make_stage(t, true)
	run.sim.stock = {"food": 0.0, "water": 0.0, "ammo": 0.0, "meds": 0.0, "scrap": 0.0, "parts": 0.0, "fuel": 0.0}
	var kit_line: String = pack.kit(stores, loadout_kit)
	loadout_kit = {}
	pack.attach(run.sim)
	arms.carry_out()    # SQUAD hook: the main gun and the spare leave the rack
	var at: Vector2 = Vector2(t.entry.pos)
	run.avatar_p.x = at.x
	run.avatar_p.y = at.y
	run.avatar_p.hp = 100.0
	if args.has("at"):
		var c := String(args.at).split(",")
		run.avatar_p.x = float(c[0])
		run.avatar_p.y = float(c[1])
	exits = _pick_exits(t, at)
	people.begin_raid(t, seed_i)    # RAIDS hook: a survivor in a building, rarely
	squad_regroup = false
	squad.begin_raid()    # SQUAD hook: the companions step out of the truck
	if args.has("scav-test"):
		squad.start_test()
	cam_center = Vector2(run.avatar_p.x, run.avatar_p.y)
	extract_t = 0.0
	_armed = false
	run.sim.avatar.set_input(Vector2.ZERO, at, false)
	_say(kit_line + "Out in the town. Search (E), take the loot (Space), reach a pickup ring.", 7.0)


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


var _perf_last := 0
var _perf_ms: Array = []
## Ticks the shooting poses of the crew (they are not in the sim, which would do it): the kick falls away, the reload runs out, the aim is held about a second after a shot and then the work pose (watch) comes back.
func _gun_poses(dt: float) -> void:
	for m in crew.members:
		var g = m.p
		g.recoil = maxf(0.0, float(g.recoil) - dt * 8.0)
		g.reloading = maxf(0.0, float(g.reloading) - dt)
		var h := float(aim_hold.get(g.id, 0.0)) - dt
		aim_hold[g.id] = h
		if h <= 0.0 and g.target != null:
			g.target = null


func _tick(dt: float) -> void:
	if args.has("perf"):    # --perf: wall ms per frame, frames 600 to 1800, then one PERF line and quit (use with --managed --siege=3 --noguards)
		var nowu := Time.get_ticks_usec()
		if frames >= 600 and _perf_last > 0:
			_perf_ms.append(float(nowu - _perf_last) / 1000.0)
		_perf_last = nowu
		if frames == 1800:
			_perf_ms.sort()
			var sum := 0.0
			for v in _perf_ms:
				sum += float(v)
			print("PERF frames ", _perf_ms.size(), " avg ms ", snappedf(sum / _perf_ms.size(), 0.01), " p95 ", snappedf(_perf_ms[int(_perf_ms.size() * 0.95)], 0.01), " max ", snappedf(_perf_ms[-1], 0.01), " awake dead ", _awake_dead().size(), " crew ", crew.members.size())
			get_tree().quit()
	dt = clampf(dt, 0.0, StepClock.MAX_FRAME)
	clock += dt
	frames += 1
	_hands()
	for i in step_clock.advance(dt, 1.0):
		_step()
		sim_steps += 1
	if phase != "clear":
		tod = fposmod(tod + dt * DAY_MIN_PER_SEC / 60.0, 24.0)    # (the clear phase is one fixed morning)
	back_t = maxf(0.0, back_t - dt)
	if crew != null:
		crew.tod = tod
	fx.combat.listener = Vector2(run.avatar_p.x, run.avatar_p.y)
	if crew != null:
		_gun_poses(dt)
		crew.update(dt, stores)
	people.frame(dt)    # RAIDS hook
	if econ != null:    # ECON hook
		if args.has("econ-lab") and phase == "managed":
			econ.lab(dt)
		else:
			econ.update(dt)
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
	pack.frame(dt)
	board.frame(dt)    # UI hook
	_layout_labels()
	if _msg_t > 0.0:
		_msg_t -= dt
		if _msg_t <= 0.0:
			msg_label.text = ""
	if mode == "base":
		if phase == "clear":
			_clear_logic(dt)
		else:
			_base_logic(dt)
			_fence_guards(dt)
			cleaner.update(dt)
			upg.update(dt)    # WORLD hook
			_pen_life(dt)
			if dog != null:
				dog.tick(dt, clock, tod > 6.0 and tod < 20.0, true)
		if phase == "clear":
			_allies(dt)    # (follow, shoot, bites and revive are the clear phase only)
	else:
		_raid_logic(dt)
	_day_night(dt)
	siege.update(dt)    # SIEGE hook
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
	var olds := {}
	for z in ally_chasers:
		olds[z] = Vector2(z.x, z.y)
	run.sim.update(StepClock.STEP)
	_ally_prey_step(olds)
	for e in run.sim.events:
		pack.on_event(e)
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
			"searched":
				var parts: Array = []
				for k in e.loot:
					parts.append("+%d %s" % [int(e.loot[k]), k])
				_say("Found: " + (", ".join(parts) if not parts.is_empty() else "nothing"), 2.5)
				_auto_pick(String(e.get("container", "")))
	run.sim.events.clear()
	if run.invulnerable:
		run.avatar_p.hp = 100.0
		run.avatar_p.downed = false


func _hud_text() -> String:
	var p = run.avatar_p
	if mode == "base" and phase == "clear":
		var left := 0
		for zi in Base.ZONES.size():
			left += _dead_in_zone(zi).size() if not zone_done[zi] else 0
		var al := ""
		for m in crew.members:
			if m.def.has("ally"):
				al += "  %s %s" % [String(m.def.name), ("DOWN" if m.state == "downed" else "%d" % int(m.hp))]
		return "CLEAR THE PRISON  cleared %d/%d  dead left %d  mag %d  party:%s\n%s" % [_cleared_n(), Base.ZONES.size(), left, int(p.mag), al, _stock_line()]
	if mode == "base":
		return "%02d:%02d  %s\n%s  |  %s" % [int(tod), int(fposmod(tod, 1.0) * 60.0), _stock_line(), board.hud_lines(), siege.hud()]    # UI hook
	return "RAID %d    HP %d    Mag %d    scrap %d\n%s\nKills %d   Exits: %d\n%s" % [raids, int(p.hp), int(p.mag), int(run.sim.stock.scrap), pack.status(), run.sim.kills, exits.size(), loot.hint()]    # RAIDS hook: the marked places


func _hands() -> void:
	var move := Vector2.ZERO
	if not busy and not loadout.is_open:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
	if args.has("walk") and not busy and not loadout.is_open:
		var w := String(args.walk).split(",")
		move = Vector2(float(w[0]), float(w[1]))
	var aim := cam_center + (get_viewport().get_mouse_position() - _vp() / 2.0) / zoom_px
	if args.has("aimdir"):
		var ad := String(args.aimdir).split(",")
		aim = Vector2(run.avatar_p.x + float(ad[0]), run.avatar_p.y + float(ad[1]))
	var fire: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and (mode == "raid" or phase == "clear" or siege.can_fire()) and not busy and not args.has("shot") and not pack.blocks_fire() and not board.blocks_fire() and not loadout.is_open and not squad.blocks_fire()
	if not _bot_in.is_empty():
		move = _bot_in.move
		aim = _bot_in.aim
	if String(args.get("auto", "")) == "play" and not busy and mode == "base" and phase == "clear":
		var b: Dictionary = _bot_clear()
		move = b.move
		aim = b.aim
		fire = b.fire
	run.sim.avatar.set_input(move, aim, fire)


func _unhandled_input(ev: InputEvent) -> void:
	if run == null:
		return
	if loot.key(ev) or loadout.key(ev):    # RAIDS hook: the gate's choice takes its keys; SQUAD hook: so does the loadout card
		return
	if ev is InputEventKey and not busy and board.key(ev):    # UI hook
		return
	if ev is InputEventKey and not busy and squad.key(ev):    # SQUAD hook: C, the orders
		return
	if ev is InputEventKey and not busy and pack.key(ev):
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_E:
				if ev.shift_pressed and mode == "raid":
					_room_search()
				else:
					_use()
			KEY_R:
				if mode == "raid" or phase == "clear" or siege.can_fire():
					run.sim.avatar.reload()
			KEY_B:    # SQUAD hook: the spare gun
				if mode == "raid" and not busy:
					if arms.swap(run.avatar_p):
						_say("Now: %s." % arms.gun_name(String(run.avatar_p.weapon)), 2.0)
					else:
						_say("No spare gun in the pack.", 2.0)
			KEY_F:
				if (mode == "raid" or phase == "clear" or siege.can_fire()) and not busy:
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


## The prompt of a use: its words, and for a search how long it takes ("E: Search the cupboard (3 s)"), with the room search on Shift+E where the room has two or more to search.
func _use_label(c: Dictionary) -> String:
	var l := "E: %s" % String(c.label)
	if String(c.get("kind", "")) != "container" or not bool(c.get("session", false)) or run == null:
		return l
	var cont: Dictionary = run.sim.houses.container(String(c.get("id", "")))
	if not cont.is_empty() and not String(c.label).begins_with("Stop"):
		l += " (%d s)" % ceili(SearchRules.search_secs(run.sim, cont))
	var rsm = run.sim.get("room_search")
	if rsm != null and not run.sim.uses.busy():
		var o: Dictionary = rsm.offer()
		if not o.is_empty() and bool(o.get("ok", false)):
			l += "     Shift+E: search all %d in this room (%d s)" % [int(o.n), ceili(float(o.secs))]
	return l


## A searched container with ONE thing in it is taken at once (a floating "+2 Ammo"): the loot window is for more than one.
func _auto_pick(id: String) -> void:
	var inv = run.sim.inv
	if inv == null or id == "" or inv.open_id != id or inv.items_left(id) != 1:
		return
	var g: Dictionary = inv.grid_of(id)
	var pl: Dictionary = g.cells[0]
	var name := String(preload("res://scripts/sim/inventory.gd").name_of(String(pl.item)))
	var n := int(pl.count)
	if inv.take_all_open() > 0 or (g.cells as Array).is_empty():
		squad.floaters.append({"text": "+%d %s" % [n, name], "pos": Vector2(run.avatar_p.x, run.avatar_p.y - 1.8), "t": 0.0, "col": Color(0.7, 1.0, 0.7)})


## Shift+E: the whole room (the town's own module: it walks her from container to container).
func _room_search() -> void:
	var rsm = run.sim.get("room_search")
	if rsm == null or busy:
		return
	var r: Dictionary = rsm.begin()
	_say(String(r.get("line", "")) if bool(r.get("ok", false)) else String(r.get("why", "")), 3.0)


func _use() -> void:
	if busy or _prompt.is_empty():
		return
	if String(_prompt.get("kind", "")) == "gate":
		if loot.open_choice():    # RAIDS hook: what to hunt
			return
		_go_out()
		return
	if String(_prompt.get("kind", "")) == "survivor":    # RAIDS hook
		people.talk()
		return
	if String(_prompt.get("kind", "")) == "leave":    # SQUAD hook: E in the pickup ring: leave the ones that are not here
		squad.abandon()
		return
	if String(_prompt.get("kind", "")) == "locked":
		_say("The gate is chained shut and the pen behind it is full. Clear the prison first.", 3.0)
		return
	if String(_prompt.get("kind", "")) == "help":
		return    # WORLD hook: held E at a scaffold (prison_upgrades.gd `_ruth`)
	if String(_prompt.get("kind", "")) == "revive":
		return    # held, not pressed (_clear_logic)
	if String(_prompt.get("kind", "")) == "repair":
		return    # SIEGE hook: held E, handled in prison_siege.gd
	if String(_prompt.get("kind", "")) == "bench" or String(_prompt.get("kind", "")) == "board":    # UI hook
		board.open("projects" if String(_prompt.kind) == "bench" else "needs")
		return
	if String(_prompt.get("kind", "")) == "stores":
		pack.open_stash()
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
		_prompt = {"kind": "gate", "label": "E: take the truck out the gate (raid, with what is in your pack)"}
	elif me.distance_to(base.stations.stores) < 2.8:
		_prompt = {"kind": "stores", "label": "E: open the stash (choose what to carry out)"}
	else:
		_prompt = board.prompt(me)    # UI hook: the bench and the needs sign
	# the dead at the gate are not for shooting
	if run.avatar_p.hp < 100.0:
		run.avatar_p.hp = 100.0


func _raid_logic(dt: float) -> void:
	var p = run.avatar_p
	var me := Vector2(p.x, p.y)
	_prompt = {}
	if not busy:
		_prompt = squad.prompt()    # SQUAD hook: a downed companion beside her
		if _prompt.is_empty():
			for c in run.sim.uses.candidates(p):
				if bool(c.get("ok", true)):
					_prompt = {"kind": "use", "c": c, "label": _use_label(c)}
					break
		if _prompt.is_empty():    # RAIDS hook
			_prompt = people.prompt()
		people.update(dt)    # RAIDS hook
		squad.update(dt)    # SQUAD hook
		var in_ring := false
		if me.distance_to(Vector2(exits[0])) > 14.0:
			_armed = true    # the drop-off ring works only after you have walked away from it
		for k in exits.size():
			if me.distance_to(Vector2(exits[k])) < EXTRACT_R and (k > 0 or _armed):
				in_ring = true
		if in_ring and squad.any():
			squad.call_all()    # SQUAD hook: the call to the pickup
		squad_regroup = in_ring and squad.any()
		if in_ring and not run.sim.uses.busy():
			var rs: Dictionary = squad.ring_state(dt) if squad.any() else {"ok": true, "text": ""}
			if bool(rs.ok):
				extract_t += dt
				if extract_t >= EXTRACT_S:
					_extract(true)
			else:
				extract_t = 0.0
				_prompt = {"kind": "leave", "label": String(rs.text)}
		else:
			extract_t = maxf(0.0, extract_t - dt * 2.0)
		if p.downed or p.dead or float(p.hp) <= 0.5:
			if args.has("log"):
				print("DIED hp ", p.hp, " downed ", p.downed, " dead ", p.dead, " at ", me)
			_extract(false)


# ------------------------------------------------------------------- cutscenes --

func _go_out() -> void:
	busy = true
	pack.close()
	await _cut_out(["The gate grinds open. The truck rolls out through the dead.", "Somewhere ahead, a town nobody has searched."], true)
	_enter_raid()
	await _cut_in()
	busy = false


func _extract(alive: bool) -> void:
	if busy:
		return
	busy = true
	var loot_got := {}
	pack.close()
	var join_text: String = people.settle(alive)    # RAIDS hook: does the survivor join (a free bed, alive, at the ring)
	var gun_lines: Array = []
	if alive:
		var back: int = arms.land([pack.grid])    # SQUAD hook: her gun and the guns in the pack go to the rack
		var sq: Dictionary = squad.settle(true)    # the bags of the companions that are here go into the stock
		gun_lines = sq.lines
		if back > 0:
			gun_lines.append("%d gun%s for the weapon rack." % [back, "" if back == 1 else "s"])
		pack.bank()    # (the items go back into the raid's stock: the line below banks all of it)
		for k in STOCK_KEYS:
			var v := float(run.sim.stock.get(k, 0.0))
			loot_got[k] = v
	var lines: Array = ["You reach the pickup. The truck is waiting.", "Back through the gate, back to the compound."]
	if not alive:
		lines = ["You go down in the street.", "Whatever you carried stays out there."]
		arms.lost()    # SQUAD hook
		gun_lines = squad.settle(false).lines
	squad.end_raid()
	await _cut_out(lines, alive)
	var lost: int = 0 if alive else pack.lose()
	if alive:
		for k in loot_got:
			stores[k] = float(stores[k]) + float(loot_got[k])
	back_t = 4.0    # (a night that fell while she was out starts the attack at once: see prison_siege.gd `_start_attack`)
	_enter_base()
	var sum := "Banked:"
	for k in loot_got:
		if float(loot_got[k]) > 0.0:
			sum += "  +%d %s" % [int(loot_got[k]), k]
	if not alive:
		sum = "Backpack lost. (%d stacks, nothing banked)" % lost
	elif sum == "Banked:":
		sum = "You came back with nothing."
	if not gun_lines.is_empty():
		sum += "\n" + "\n".join(gun_lines)
	print("RESULT ", sum, " | stores ", stores, " | pack stacks ", pack.grid.cells.size())
	await _cut_in()
	_say(sum, 10.0)
	if join_text != "":    # RAIDS hook
		people.banner(join_text, Color(1, 0.6, 0.45) if join_text.contains("left") else Color(0.6, 1, 0.7))
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
		n2.modulate.a = clampf((70.0 - float(z.dead_t)) / 6.0, 0.0, 1.0) if z.state == "dead" else 1.0    # (a body that is taken away fades out)
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
	if mode == "raid":
		squad.sync(view, clock, sim_steps, alpha)    # SQUAD hook
	if crew != null:
		for m in crew.members:
			var n3: PawnNode = m.node
			n3.anim_t = clock
			n3.visible = view.has_point(Vector2(m.p.x, m.p.y))
			if n3.visible:
				n3.sync(true, sim_steps, alpha)
				if m.has("lift"):
					n3.position.y -= float(m.lift) * TILE    # (a kid's hop)


func _paint_decks(c: CanvasItem) -> void:
	if mode == "base" and base != null:
		for t in base.towers:
			Tower.draw_deck(c, t)


func _paint_overlay(c: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	if mode == "base":
		for t in base.towers:
			Tower.draw_roof(c, t, _night_of(tod))
		# the gate leaves
		var g := Vector2(Base.GATE_X, Base.FENCE.end.y - 1) * TILE
		c.draw_rect(Rect2(g, Vector2(Base.GATE_W * TILE * 0.5 - 2, TILE)), Color(0.45, 0.47, 0.5))
		c.draw_rect(Rect2(g + Vector2(Base.GATE_W * TILE * 0.5 + 2, 0), Vector2(Base.GATE_W * TILE * 0.5 - 2, TILE)), Color(0.45, 0.47, 0.5))
		siege.paint(c)    # SIEGE hook
		board.paint(c)    # UI hook
		if cleaner != null:
			cleaner.paint(c)
		for l in base.labels:
			c.draw_string(font, Vector2(l.pos) * TILE - Vector2(80, 0), String(l.text), HORIZONTAL_ALIGNMENT_CENTER, 160, 20, Color(1, 1, 0.8, 0.8))
		for m in crew.members:
			var p = m.p
			var tag := "%s: %s" % [String(m.def.name), String(m.say)]
			var at := Vector2(p.x, p.y - 1.55) * TILE
			c.draw_string(font, at - Vector2(100, 0), tag, HORIZONTAL_ALIGNMENT_CENTER, 200, 15, Color(1, 0.6, 0.55, 0.95) if m.state == "downed" else Color(1, 1, 1, 0.92))
			if m.def.has("ally"):
				var f2 := clampf(float(m.hp) / Crew.ALLY_HP, 0.0, 1.0)
				c.draw_rect(Rect2(at + Vector2(-20, 4), Vector2(40, 5)), Color(0, 0, 0, 0.7))
				c.draw_rect(Rect2(at + Vector2(-20, 4), Vector2(40.0 * f2, 5)), Color(0.3, 0.85, 0.35) if f2 > 0.3 else Color(0.9, 0.25, 0.2))
			if m.state == "work":
				var f := clampf(float(m.t) / float(m.def.route[m.i].secs), 0.0, 1.0)
				c.draw_rect(Rect2(at + Vector2(-20, 4), Vector2(40, 5)), Color(0, 0, 0, 0.6))
				c.draw_rect(Rect2(at + Vector2(-20, 4), Vector2(40.0 * f, 5)), Color(0.95, 0.8, 0.3))
		for fl in crew.floaters:
			var a := 1.0 - float(fl.t) / 2.2
			var col: Color = fl.col
			col.a = a
			c.draw_string(font, Vector2(fl.pos) * TILE + Vector2(-130, -float(fl.t) * 22.0), String(fl.text), HORIZONTAL_ALIGNMENT_CENTER, 260, 17, col)
		if phase == "clear":
			for ct in town.containers:
				if not run.sim.search.is_looted(String(ct.id)):
					var cp := Vector2(ct.at) * TILE
					c.draw_rect(Rect2(cp - Vector2(5, 5), Vector2(10, 10)), Color(1.0, 0.85, 0.25, 0.55 + 0.3 * sin(clock * 4.0)), false, 2.0)
			c.draw_string(font, Vector2(4.0, 31.6) * TILE, "WEST BREACH", HORIZONTAL_ALIGNMENT_CENTER, 140, 16, Color(1, 0.9, 0.5, 0.85))
			c.draw_string(font, Vector2(Base.GATE_POS.x, 56.2) * TILE - Vector2(100, 0), "CHAINED", HORIZONTAL_ALIGNMENT_CENTER, 200, 16, Color(1, 0.4, 0.35, 0.9))
		# the kids' hopscotch (chalk) and ball
		var hs := Crew.HOPSCOTCH * TILE
		for k in 6:
			var q := hs + Vector2(0.0, -float(k) * 0.55 * TILE)
			var w := 0.55 * TILE
			c.draw_rect(Rect2(q - Vector2(w / 2.0, w / 2.0), Vector2(w, w)), Color(0.95, 0.95, 0.85, 0.5), false, 2.0)
			if k == 3 or k == 4:
				c.draw_rect(Rect2(q + Vector2(w / 2.0, -w / 2.0), Vector2(w, w)), Color(0.95, 0.95, 0.85, 0.5), false, 2.0)
		var kids := false
		for m in crew.members:
			if m.state == "play":
				kids = true
		if kids:
			c.draw_circle(crew.ball * TILE + Vector2(0, 2), 7.0, Color(0, 0, 0, 0.3))
			c.draw_circle(crew.ball * TILE - Vector2(0, 4), 7.0, Color(0.85, 0.3, 0.25))
			c.draw_arc(crew.ball * TILE - Vector2(0, 4), 7.0, 0.3, 2.6, 8, Color(1, 1, 1, 0.8), 1.5)
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
		loot.paint(c)    # RAIDS hook
		people.paint(c)
		squad.paint(c)    # SQUAD hook
		_paint_search(c)


## Raid overlay: near her, each container says what it is: a yellow bracket (not searched), a green tick (done), an orange dot (searched, things left in it); the one she is searching has a ring that fills.
func _paint_search(c: CanvasItem) -> void:
	var me := Vector2(run.avatar_p.x, run.avatar_p.y)
	var inv = run.sim.inv
	var pulse := 0.5 + 0.5 * sin(clock * 4.0)
	for ct in town.containers:
		var at := Vector2(ct.at)
		if me.distance_to(at) > 7.0:
			continue
		var id := String(ct.id)
		var pp := at * TILE
		if run.sim.search.is_looted(id):
			if inv != null and inv.items_left(id) > 0:
				c.draw_circle(pp, 6.0, Color(1.0, 0.6, 0.2, 0.9))
			else:
				c.draw_polyline(PackedVector2Array([pp + Vector2(-6, 0), pp + Vector2(-2, 5), pp + Vector2(7, -6)]), Color(0.45, 1.0, 0.5, 0.75), 2.5)
		else:
			c.draw_rect(Rect2(pp - Vector2(9, 9), Vector2(18, 18)), Color(1.0, 0.85, 0.25, 0.5 + 0.3 * pulse), false, 2.0)
	var us = run.sim.uses
	if us.busy() and String(us._s.kind) == "container":
		var f := clampf(float(us._s.t) / maxf(float(us._s.of), 0.1), 0.0, 1.0)
		var cp := Vector2(us._s.at) * TILE
		c.draw_arc(cp, 20.0, 0, TAU, 28, Color(0, 0, 0, 0.6), 7.0)
		c.draw_arc(cp, 20.0, -PI / 2.0, -PI / 2.0 + f * TAU, 28, Color(0.95, 0.8, 0.3), 5.0)


# --------------------------------------------------------------------- scripted --

## --auto=raid: start a raid, walk to the nearest container and search it, then to an exit.  extract / die jump to those endings (for checks).
func _scripts(dt: float) -> void:
	if args.has("drive") and frames == 5:
		driver = Drive.new(self)
		driver.run(String(args.drive))
	if args.has("loadout") and frames == 30:    # staging: the loadout card (--loadout=weapon: the clear phase's weapon card)
		loadout.open("Food and water" if String(args.loadout) != "weapon" else "", String(args.loadout) == "weapon")
	if args.has("pick") and frames == 32 and loadout.is_open:    # staging: --pick=june,owen ticks companions on the card
		for id in String(args.pick).split(","):
			squad.toggle(id)
		loadout._refresh()
	if phase == "clear" and mode == "base" and frames == 25 and not _weapon_card and String(args.get("auto", "")) == "" and not args.has("shot") and not args.has("loadout") and DisplayServer.get_name() != "headless":
		_weapon_card = true
		loadout.open("", true)    # the first card of the party: which gun
	if args.has("reloadat") and frames == int(args.reloadat):    # (a check: half empty, then a reload, for the ring screenshot)
		run.avatar_p.mag = 2
		run.sim.avatar.reload()
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
	if a == "ally" and _auto_t > 14.0 and mode == "base":
		for m in crew.members:
			if m.state == "downed":
				run.avatar_p.x = m.p.x + 0.8
				run.avatar_p.y = m.p.y
				break
	if a == "loop":
		_auto_loop(dt)
	if a == "reach" and _auto_t > 0.5:
		_auto_reach()
	if a == "clearall" and mode == "base" and phase == "clear" and not busy:
		_auto_clear()


## --auto=clearall: zone by zone, walk Ruth onto one container of the zone and search it, then kill every dead one in the zone (the zone check does the rest).
var _auto_acc := 0.0
func _auto_clear() -> void:
	_auto_acc += get_process_delta_time()
	if _auto_acc < 1.2 or run.sim.uses.busy():
		return
	var zi := zone_done.find(false)
	if zi < 0:
		return
	if _auto_i % 2 == 0:
		_auto_acc = -2.5    # the search takes about 3 s
		for ct in town.containers:
			if int(ct.house) == zi and not run.sim.search.is_looted(String(ct.id)):
				run.avatar_p.x = float(ct.pos.x)
				run.avatar_p.y = float(ct.pos.y)
				for cd in run.sim.uses.candidates(run.avatar_p):
					if String(cd.kind) == "container":
						run.sim.uses.use(cd)
						print("AUTO search ", ct.id, " loot ", ct.loot, " stores before ", stores)
						break
				break
	else:
		_auto_acc = 0.0
		var ids := _dead_in_zone(zi)
		for i in ids:
			if run.field.status[i] == run.field.ACTIVE and run.field.active_of.has(i):
				run.sim._hurt_zombie(run.field.active_of[i], 9999.0, 0.0, null)
			else:
				run.field.remove_record(i)
		print("AUTO kill zone ", Base.ZONES[zi].id, " dead ", ids.size(), " stores after ", stores)
	_auto_i += 1


## --auto=play (clear phase): a player-like bot. Shoots the nearest awake dead in sight, reloads, revives a downed ally, searches containers within 12 tiles, else walks to the nearest remaining dead
## of an uncleared zone with the path finder. Prints STUCK when it has not moved for 6 s.
var _bot_hold_e := false
var _bot_last := Vector2.ZERO
var _bot_still := 0.0
func _bot_clear() -> Dictionary:
	var p = run.avatar_p
	var me := Vector2(p.x, p.y)
	var out := {"move": Vector2.ZERO, "aim": me + Vector2(1, 0), "fire": false}
	_bot_hold_e = false
	if pack.inv != null and pack.inv.open_id != "":
		pack.inv.take_all_open()
	var dt := get_process_delta_time()
	var best = null
	var bd := 1.0e9
	for z in _awake_dead():
		var d := me.distance_to(Vector2(z.x, z.y))
		if d < 10.0 and d < bd and run.sim.clear_shot(me, Vector2(z.x, z.y), 0.15):
			bd = d
			best = z
	if args.has("botlog") and frames % 300 == 0:
		if best != null:
			print("  target ", best.state, " ", Vector2(best.x, best.y), " hp ", best.hp, " kind ", best.get("kind"), " ang ", me.angle_to_point(Vector2(best.x, best.y)))
		print("BOT t=", snappedf(clock, 0.1), " me ", me, " mag ", p.mag, " best ", best != null, " awake ", _awake_dead().size(), " pack ammo ", pack.inv.shots_available(p), " cleared ", _cleared_n())
	var goal := Vector2(-1, -1)
	var dn = null
	for m in crew.members:
		if m.state == "downed":
			dn = m
	if best != null:
		out.aim = Vector2(best.x, best.y)
		out.fire = int(p.mag) > 0
		if int(p.mag) <= 0:
			run.sim.avatar.reload()
		if bd < 2.5:
			out.move = (me - Vector2(best.x, best.y)).normalized()
		elif bd > 6.0:
			var tp: Array = run.sim.path_p.find(world.solid_p, me.x, me.y, best.x, best.y)
			if not tp.is_empty():
				out.move = (Vector2(tp[0]) - me).normalized()
		return out
	if int(p.mag) < 4:
		run.sim.avatar.reload()
	if dn != null and float(stores.meds) >= 1.0:
		goal = Vector2(dn.p.x, dn.p.y)
		_bot_hold_e = me.distance_to(goal) < 1.5
	if goal.x < 0.0:
		var cb := 12.0
		for c in town.containers:
			if run.sim.search.is_looted(String(c.id)):
				continue
			var d2 := me.distance_to(Vector2(c.pos))
			if d2 < cb:
				cb = d2
				goal = Vector2(c.pos)
		if goal.x >= 0.0 and cb < 0.7:
			if not run.sim.uses.busy():
				for cd in run.sim.uses.candidates(p):
					if String(cd.kind) == "container":
						run.sim.uses.use(cd)
						break
			return out
	if goal.x < 0.0:
		var f = run.field
		var nb := 1.0e9
		for zi in Base.ZONES.size():
			if zone_done[zi]:
				continue
			for i in _dead_in_zone(zi):
				var pl: Vector2 = f._place_of(i)
				var d3 := me.distance_to(pl)
				if d3 < nb:
					nb = d3
					goal = pl
		for z in _awake_dead():
			var d4 := me.distance_to(Vector2(z.x, z.y))
			if d4 < nb and Base.zone_at(z.x, z.y) >= 0:
				nb = d4
				goal = Vector2(z.x, z.y)
	if goal.x < 0.0:
		return out
	var path: Array = run.sim.path_p.find(world.solid_p, me.x, me.y, goal.x, goal.y)
	if path.is_empty():
		print("BOT nopath from ", me, " to ", goal)
	else:
		var wp: Vector2 = path[0]
		if me.distance_to(wp) < 0.35 and path.size() > 1:
			wp = path[1]
		out.move = (wp - me).normalized()
		out.aim = wp
	if me.distance_to(_bot_last) < 0.3:
		_bot_still += dt
		if _bot_still > 6.0:
			_bot_still = 0.0
			print("STUCK at ", me, " goal ", goal, " zone ", Base.zone_at(me.x, me.y), " t ", snappedf(clock, 0.1))
	else:
		_bot_still = 0.0
		_bot_last = me
	return out


## --auto=loop --managed [--loops=N] [--loopdie=1,0,...]: base, go out, loot for 25 s (the --auto=loot walker), extract or die (per --loopdie), prints a SNAP line at every step to catch state leaks.
var _loop_n := 0
var _loop_die := false
var _raid_t := 0.0
func _snap(tag: String) -> void:
	var cells: int = (pack.grid.cells as Array).size()
	var q: Array = pack.quick
	print("SNAP ", tag, " phase=", phase, " mode=", mode, " tod=", snappedf(tod, 0.01), " stores=", stores, " pack_stacks=", cells, " belt=", q, " siege(att=", siege.attacking, " night=", siege.night, " started=", siege.nights_started, " abs_h=", snappedf(siege.abs_h, 0.1), ") crew=", (crew.members.size() if crew != null else -1), " allies=", allies_alive, " busy=", busy, " raids=", raids, " zombies=", run.sim.zombies.size(), " mag=", run.avatar_p.mag, " hp=", run.avatar_p.hp, " exits=", exits.size(), " me=", Vector2(run.avatar_p.x, run.avatar_p.y))


func _auto_loop(dt: float) -> void:
	if busy:
		return
	var n_max := int(args.get("loops", "2"))
	var dies := String(args.get("loopdie", "0,1")).split(",")
	if mode == "base":
		if _auto_t > 3.0:
			_snap("base before raid %d" % _loop_n)
			if _loop_n >= n_max:
				get_tree().quit()
				return
			_raid_t = 0.0
			_go_out()
			_auto_t = 0.0
	else:
		_raid_t += dt
		run.invulnerable = (_raid_t > 0.0 and _raid_t < float(args.get("raidsecs", "25"))) or (_raid_t < 0.0 and not _loop_die)
		if _raid_t > 0.0:
			_auto_loot()
		if _raid_t > float(args.get("raidsecs", "25")):
			var die: bool = dies[_loop_n % dies.size()] == "1"
			_loop_die = die
			_snap("raid end (die=%s)" % die)
			_loop_n += 1
			_auto_t = 0.0
			_raid_t = -1.0e9    # (decided: the ending takes a few seconds)
			if die:
				run.avatar_p.hp = 0.0
			else:
				_extract(true)


## --auto=reach: path finder check from the start point to every container stand point and every dead record of the clear phase (prints the ones with no path), then quits.
func _auto_reach() -> void:
	var from := Base.START
	var bad := 0
	for ct in town.containers:
		var pth: Array = run.sim.path_p.find(world.solid_p, from.x, from.y, ct.pos.x, ct.pos.y)
		var sp: int = world.solid_p[int(ct.pos.y) * world.W + int(ct.pos.x)]
		if pth.is_empty() or sp != 0:
			bad += 1
			print("REACH container ", ct.id, " ", ct.kind, " pos ", ct.pos, " solid ", sp, " path ", pth.size())
	for i in run.field.n:
		var pl: Vector2 = run.field._place_of(i)
		var pth2: Array = run.sim.path_p.find(world.solid_p, from.x, from.y, pl.x, pl.y)
		if pth2.is_empty():
			bad += 1
			print("REACH dead ", i, " zone ", Base.zone_at(pl.x, pl.y), " at ", pl, " solid ", world.solid_p[int(pl.y) * world.W + int(pl.x)])
	for zi in Base.ZONES.size():
		for id in Base.ZONES[zi].crew:
			pass
	print("REACH done: containers ", town.containers.size(), " dead ", run.field.n, " bad ", bad)
	get_tree().quit()


var _auto_target := Vector2(-1, -1)
var _bot_in := {}
var _bot_wait := 0.0
func _auto_loot() -> void:
	_bot_in = {}
	var p = run.avatar_p
	var me := Vector2(p.x, p.y)
	_bot_wait -= get_process_delta_time()
	if _bot_wait > 0.0:
		_bot_in = {"move": Vector2.ZERO, "aim": me}
		return
	var best = null
	var bd := 1.0e9
	if not run.sim.uses.busy():
		for cd in run.sim.uses.candidates(p):
			if String(cd.kind) == "container" and bool(cd.get("ok", true)):
				run.sim.uses.use(cd)
				_bot_wait = 4.0    # (a second use cancels the search)
				_bot_in = {"move": Vector2.ZERO, "aim": me}
				return
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
				_bot_wait = 4.0
				break
		_bot_in = {"move": Vector2.ZERO, "aim": me}
	else:
		var path: Array = run.sim.path_p.find(world.solid_p, me.x, me.y, best.pos.x, best.pos.y)
		if not path.is_empty():
			var wp: Vector2 = path[mini(1, path.size() - 1)]
			_bot_in = {"move": (wp - me).normalized(), "aim": wp}


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
	if mode == "base" and phase == "clear":
		for zi in Base.ZONES.size():
			var zr := Rect2(Base.ZONES[zi].rect)
			bars.draw_rect(Rect2(o + zr.position * sc, zr.size * sc), Color(0.3, 0.9, 0.4, 0.4) if zone_done[zi] else Color(0.55, 0.55, 0.58, 0.45))
			bars.draw_rect(Rect2(o + zr.position * sc, zr.size * sc), Color(0.3, 0.9, 0.4, 0.9) if zone_done[zi] else Color(0.7, 0.7, 0.72, 0.8), false, 1.0)
	if mode == "base":
		bars.draw_circle(o + Base.GATE_POS * sc, 3.5, Color(1, 0.85, 0.3))
		for m in crew.members:
			bars.draw_circle(o + Vector2(m.p.x, m.p.y) * sc, 1.8, Color(0.4, 0.85, 1.0))
		bars.draw_rect(Rect2(o + Vector2(5, 57) * sc, Vector2(86, 12) * sc), Color(0.8, 0.1, 0.1, 0.18))
		siege.mini(bars, o, sc)    # SIEGE hook
	for z in run.sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		bars.draw_rect(Rect2(o + Vector2(z.x, z.y) * sc - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), Color(0.95, 0.25, 0.2))
	if mode == "raid":
		for e in exits:
			bars.draw_arc(o + Vector2(e) * sc, 5.0, 0, TAU, 14, Color(0.4, 1, 0.5), 2.0)
		loot.mini(bars, o, sc)    # RAIDS hook
		people.mini(bars, o, sc)
		squad.mini(bars, o, sc)    # SQUAD hook
	var p = run.avatar_p
	var me := o + Vector2(p.x, p.y) * sc
	var ang := Vector2(p.x, p.y).angle_to_point(run.avatar_p.input_aim) if run.avatar_p.input_aim != Vector2.ZERO else 0.0
	var dir := Vector2.from_angle(ang)
	bars.draw_colored_polygon(PackedVector2Array([me + dir * 6.0, me + dir.rotated(2.5) * 4.0, me + dir.rotated(-2.5) * 4.0]), Color(1, 1, 0.9))
	# the camera's window
	var half := _vp() / zoom_px / 2.0 * sc
	bars.draw_rect(Rect2(o + cam_center * sc - half, half * 2.0), Color(1, 1, 1, 0.5), false, 1.0)



## One rifle shot from a person that is not in the sim (a tower guard, an ally) at a dead one: muzzle flash, tracer, the real rifle sound, `hit_p` to hit (55 damage, the dead fall and bleed).
func _shoot_at(g, z, hit_p: float) -> void:
	var ang := Vector2(g.x, g.y).angle_to_point(Vector2(z.x, z.y))
	g.facing = run.sim.facing_of(cos(ang), sin(ang), g.facing)    # (the pawn draws 4 views, E mirrored for W: the shooter turns to the nearest one)
	g.aim = ang
	if g.target == null:    # the first shot of a burst: the rifle is raised for 0.25 s before the flash
		g.target = z
		aim_hold[g.id] = 1.4
		await get_tree().create_timer(0.25).timeout
		if run == null or not siege._alive(z):
			return
	# the pose: PawnNode draws the aimed gun while `target` is set, the kick from `recoil`, the lowered gun and pump from `reloading` (the pawn's own states, ticked in `_gun_poses`)
	g.target = z
	g.recoil = 1.0
	aim_hold[g.id] = 1.1
	shot_n[g.id] = int(shot_n.get(g.id, 0)) + 1
	if int(shot_n[g.id]) % RELOAD_EVERY == 0:
		g.reloading = RELOAD_SECS
	if args.has("shotlog"):
		print("SHOT f=", frames, " ", g.id, " n=", shot_n[g.id])
	var mz: Vector2 = run.sim.muzzle(g, ang)    # (the gun's own muzzle, so the flash and the tracer start at the barrel)
	var mx := mz.x
	var my := mz.y
	var hit := randf() < hit_p
	var tx: float = z.x if hit else z.x + randf_range(-0.8, 0.8)
	var ty: float = z.y if hit else z.y + 1.2
	fx.muzzle(mx, my, ang, false)
	fx.tracer(mx, my, tx, ty)
	fx.combat.shot_sound({"type": "shot", "weapon": "rifle", "gun": "rifle", "x": g.x, "y": g.y})
	shots_fired += 1
	if hit:
		run.sim._hurt_zombie(z, 55.0, ang, null)


# ------------------------------------------------------------------ clear phase --

func in_managed() -> bool:
	return phase == "managed"


func _card(title: String, sub: String, secs: float) -> void:
	cap_label.text = title + "\n" + sub
	cap_label.modulate.a = 1.0
	await get_tree().create_timer(secs).timeout
	var tw := create_tween()
	tw.tween_property(cap_label, "modulate:a", 0.0, 0.8)


func _cleared_n() -> int:
	var n := 0
	for d in zone_done:
		if d:
			n += 1
	return n


## The record ids of the dead that are in a zone's rect now (dormant or awake, not dying), by where they are.
func _dead_in_zone(zi: int) -> Array:
	var f = run.field
	var r := Rect2(Base.ZONES[zi].rect)
	var out: Array = []
	for i in f.n:
		if f.status[i] == f.KILLED:
			continue
		if f.status[i] == f.ACTIVE and f.active_of.has(i):
			var zz = f.active_of[i]
			if zz.state == "dying" or zz.state == "dead":
				continue
		if r.has_point(f._place_of(i)):
			out.append(i)
	return out


func _add_member_node(m: Dictionary) -> void:
	var n := PawnNode.new()
	n.setup(m.p, false, data, String(m.key))
	n.unarmed = bool(m.def.get("unarmed", false))    # (the clear phase frees the kids through here)
	if m.def.has("scale"):
		n.scale = Vector2.ONE * float(m.def.scale)
	entities.add_child(n)
	m["node"] = n


func _clear_logic(dt: float) -> void:
	var p = run.avatar_p
	var me := Vector2(p.x, p.y)
	_prompt = {}
	if p.downed or p.dead or float(p.hp) <= 0.5:
		p.hp = 100.0
		p.downed = false
		p.dead = false
		p.x = 8.5
		p.y = 34.5
		_say("You went down. Your people dragged you back to the breach.", 4.0)
	var dn = _nearest_downed(me)
	if dn != null:
		var ok: bool = float(stores.meds) >= 1.0
		_prompt = {"kind": "revive", "label": ("Hold E: revive %s (1 med)" % String(dn.def.name)) if ok else "%s is down. No meds to revive." % String(dn.def.name)}
		var held := Input.is_key_pressed(KEY_E) or (String(args.get("auto", "")) == "ally" and _auto_t > 14.0)
		if ok and held:
			revive_t += dt
			if revive_t >= REVIVE_SECS:
				stores.meds = float(stores.meds) - 1.0
				dn.hp = ALLY_REVIVE_HP
				dn.state = "ally"
				dn.p.downed = false
				dn.say = "back up"
				revive_t = 0.0
				_say("%s is back on their feet." % String(dn.def.name), 3.0)
				if args.has("log"):
					print("ALLY revived ", dn.def.name, " meds left ", stores.meds)
		else:
			revive_t = maxf(0.0, revive_t - dt * 2.0)
	else:
		revive_t = 0.0
	if _prompt.is_empty():
		for c in run.sim.uses.candidates(p):
			if bool(c.get("ok", true)):
				_prompt = {"kind": "use", "c": c, "label": _use_label(c)}
				break
	if _prompt.is_empty() and me.distance_to(Base.GATE_POS) < 7.0:
		_prompt = {"kind": "locked", "label": "The gate is chained shut. Clear the prison first."}
	_zone_t -= dt
	if _zone_t <= 0.0 and not busy:
		_zone_t = 0.5
		_zone_check()


func _zone_check() -> void:
	for zi in Base.ZONES.size():
		if zone_done[zi] or _dead_in_zone(zi).size() > 0:
			continue
		zone_done[zi] = true
		var z: Dictionary = Base.ZONES[zi]
		var names: Array = []
		var k := 0
		for id in z.crew:
			var m: Dictionary = crew.release(String(id), Vector2(z.rel) + Vector2(float(k) * 0.9, 0.0))
			k += 1
			if not m.is_empty():
				_add_member_node(m)
				names.append(String(m.def.name))
		_say("%s cleared (%d/%d). %s %s free." % [String(z.name), _cleared_n(), Base.ZONES.size(), " and ".join(names), "is" if names.size() == 1 else "are"], 6.0)
		sound.play("bell", 0.5, 0.0)
		if args.has("log"):
			print("ZONE cleared t=", snappedf(clock, 0.1), " ", z.id, " ", _cleared_n(), "/", Base.ZONES.size(), " freed ", names, " stores ", stores)
	if _cleared_n() == Base.ZONES.size() and not busy:
		_secure()


## Every zone cleared: the card, the base is rebuilt in its managed form (gate open, breach sealed, the whole crew at work) and `phase_changed("managed")` is emitted.
func _secure() -> void:
	busy = true
	await _cut_out(["PRISON SECURED", "The gate is unlocked. The west breach is sealed."], false)
	phase = "managed"
	ally_chasers.clear()    # (no clear-phase state follows: the dead that chased an ally, the revive bar)
	revive_t = 0.0
	tod = 8.0
	_enter_base()
	await _cut_in()
	busy = false
	_say("The prison is yours. Hold it.", 8.0)
	if args.has("log"):
		print("PHASE managed: crew ", crew.members.size(), " allies ", allies_alive, " stores ", stores)
	phase_changed.emit(phase)


func _nearest_downed(me: Vector2):
	for m in crew.members:
		if m.state == "downed" and me.distance_to(Vector2(m.p.x, m.p.y)) < 1.8:
			return m
	return null


## The allies, every frame: bites, going down, shooting the nearest dead, following Ruth (hanging back behind her below 30 percent hp). Dead that are closer to an ally than to Ruth
## are marked in `ally_chasers` (see `_ally_prey_step`).
func _allies(dt: float) -> void:
	var rp = run.avatar_p
	var me := Vector2(rp.x, rp.y)
	var aim := Vector2(rp.input_aim) - me if rp.input_aim != Vector2.ZERO else Vector2(1, 0)
	aim = aim.normalized() if aim.length() > 0.1 else Vector2(1, 0)
	var zs := _awake_dead()
	var allies: Array = []
	for m in crew.members:
		if m.def.has("ally"):
			allies.append(m)
	ally_chasers.clear()
	for m in allies:
		var g = m.p
		var at := Vector2(g.x, g.y)
		if m.state == "downed":
			m.down_t = float(m.down_t) - dt
			m.say = "DOWN %ds" % int(ceil(float(m.down_t)))
			if float(m.down_t) <= 0.0:
				_ally_gone(m)
			continue
		m.cd = float(m.cd) - dt
		m.bite = float(m.bite) - dt
		m.repath = float(m.repath) - dt
		var biters := 0
		var best = null
		var bd := 1.0e9
		var hang: bool = float(m.hp) < 0.3 * Crew.ALLY_HP
		for z in zs:
			var d := at.distance_to(Vector2(z.x, z.y))
			if d < BITE_R:
				biters += 1
			if d < (6.5 if hang else ALLY_RANGE) and d < bd and run.sim.clear_shot(at, Vector2(z.x, z.y), 0.15):
				bd = d
				best = z
		if biters > 0 and float(m.bite) <= 0.0:
			m.bite = 0.9
			var dmg := BITE_DMG * float(mini(biters, 3))
			m.hp = float(m.hp) - dmg
			sound.play("bite", 0.5)
			crew.floaters.append({"text": "-%d" % int(dmg), "pos": Vector2(g.x, g.y - 1.6), "t": 0.0, "col": Color(1, 0.35, 0.3)})
			if float(m.hp) <= 0.0:
				m.hp = 0.0
				m.state = "downed"
				m.down_t = DOWN_SECS
				g.downed = true
				g.moving = false
				_say("%s is down! Hold E next to them to revive (1 med)." % String(m.def.name), 4.0)
				if args.has("log"):
					print("ALLY down ", m.def.name)
				continue
		g.hp = m.hp
		m.hold = float(m.get("hold", 0.0)) - dt
		if best != null and float(m.cd) <= 0.0 and float(g.reloading) <= 0.0:
			_shoot_at(g, best, 0.7)
			m.cd = randf_range(0.9, 1.6)
			m.hold = 0.35
			m.say = "firing"
		if float(m.hold) > 0.0:
			g.moving = false
			continue
		# follow
		var idx := allies.find(m)
		var slot := me - aim * 3.0 + aim.orthogonal() * (float(idx) - 1.0) * 1.2 if hang else me + Vector2.from_angle(float(idx) * 2.1 + 0.5) * 2.2
		var dist := at.distance_to(slot)
		if at.distance_to(me) > 18.0:
			g.x = me.x
			g.y = me.y
			m.path = []
			continue
		if dist > 1.1:
			if float(m.repath) <= 0.0:
				m.repath = 0.4
				m.path = run.sim.path_p.find(world.solid_p, g.x, g.y, slot.x, slot.y)
				if m.path.is_empty():
					m.path = run.sim.path_p.find(world.solid_p, g.x, g.y, me.x, me.y)
				m.pi = 0
			crew._advance(m, dt, 5.0 if dist > 8.0 else ALLY_FOLLOW)
			if best == null:
				m.say = "hanging back" if hang else "following"
		else:
			g.moving = false
			if best == null:
				m.say = "hanging back" if hang else "ready"
		# dead that are nearer to this ally than to Ruth go for the ally
		for z in zs:
			if z.state == "chase" and not ally_chasers.has(z):
				var da := at.distance_to(Vector2(z.x, z.y))
				if da < 8.0 and da < me.distance_to(Vector2(z.x, z.y)) - 0.5:
					ally_chasers[z] = m


## After a step of the rules: the dead that were sent after an ally walk toward the ally (the rules moved them toward Ruth; that move is undone).
func _ally_prey_step(olds: Dictionary) -> void:
	for z in olds:
		var m = ally_chasers.get(z)
		if m == null or z.state != "chase" or m.state != "ally":
			continue
		var o: Vector2 = olds[z]
		var to := Vector2(m.p.x, m.p.y) - o
		var d := to.length()
		z.x = o.x
		z.y = o.y
		if d < BITE_R * 0.8:
			z.moving = false
			continue
		var dir := to / d
		var sp: float = z.speed * StepClock.STEP
		for ax in [Vector2(dir.x, 0.0), Vector2(0.0, dir.y)]:
			var nx: float = z.x + ax.x * sp
			var ny: float = z.y + ax.y * sp
			if world.solid_p[int(ny) * world.W + int(nx)] == 0:
				z.x = nx
				z.y = ny
		z.facing = run.sim.facing_of(dir.x, dir.y, z.facing)
		z.moving = true


func _ally_gone(m: Dictionary) -> void:
	_say("%s is gone." % String(m.def.name), 5.0)
	allies_alive.erase(String(m.def.id))
	crew.members.erase(m)
	if m.has("node"):
		m.node.queue_free()
	if args.has("log"):
		print("ALLY gone ", m.def.name)


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
		if not m.def.has("stand") or not siege.guard_ok(m):    # SIEGE hook
			continue
		var g = m.p
		guard_cd[g.id] = float(guard_cd.get(g.id, randf() * 2.0)) - dt
		if float(guard_cd[g.id]) > 0.0 or float(g.reloading) > 0.0:
			continue
		var best = null
		var bd := 1.0e9
		for z in dead:
			if not siege.in_guard_zone(z):    # SIEGE hook (was the strip south of the gate fence)
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
		_shoot_at(g, best, 0.8 + (econ.hit_bonus() if _night_of(tod) > 0.5 else 0.0))    # ECON hook: floodlights
		siege.guard_shot(g)    # SIEGE hook: a shot costs ammo
		m.say = "firing"


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
		spots.append([Tower.lamp_pos(r) / TILE, 5.0, Color(1.0, 0.95, 0.75, 0.4 * n)])
	spots.append_array(upg.glow_spots(n))    # WORLD hook
	upg.draw_cones(glow, cam_center, zoom_px, v, n)    # WORLD hook: the floodlight cones, above the night tint
	for sp in spots:
		var scr: Vector2 = (Vector2(sp[0]) - cam_center) * zoom_px + v / 2.0
		var rad: float = float(sp[1]) * zoom_px
		if scr.x < -rad or scr.y < -rad or scr.x > v.x + rad or scr.y > v.y + rad:
			continue
		glow.draw_texture_rect(radial_tex, Rect2(scr - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false, sp[2])
