extends "res://tools/capture_fight.gd"
## THE HUD AUDIT'S HANDS AND CAMERA (PH7): `--capture=audit` (tools/capture_audit.gd) plays a staged scene the way tools/capture_walk.gd and capture_fight.gd do (real key events, the
## game's own variables for the pointer and the trigger) and, at the moments a scenario names, takes a SNAPSHOT: the same frozen frame drawn again and again with one part of the UI
## switched off each time, so that tools/ui_audit/analyze.py can tell by a pixel diff what each part covers (a part that only draws has no rectangle worth having), plus a JSON of every
## visible Control with its rectangle, and where each awake dead one stands on the screen. Nothing in scripts/ is touched: the flags are the game's own (`--stage`, `--lesson`, `--radio`,
## `--hour`, `--weather`, `--advance`, `--winpx`...), the switches are visibility, set in the engine's `frame_pre_draw` (after every `_process`, so no part puts itself back) and undone after.
##
## Flags (after the `--`; the game's own ones come as in the README):
##   --capture=audit --capture-out=DIR --capture-scn=still|opening|clearing|night|dawn  --capture-name=TAG  [--capture-wait=FRAMES] [--capture-until=dawn|dead:N]
##   --capture-tips=1       the tips of a normal run (scripts/ui/hints.gd; a screenshot run has none) are made, with a settings file of their own (`--prefs=`)
##   --capture-hold=1       (still) the first screen of a real new run: the game held at speed 0 with "Press W A S D to begin" and no banner (a screenshot run skips the hold)
##   still     wait FRAMES (100), snapshot TAG, quit        (arrival, the day at the base, the Build page, the radio, a lesson of `--lesson=`)
##   opening   walk the opening's own route with W A S D (the banner of the first key is shown as the real run shows it) until the first walker steps out: snapshot TAG_0 at that instant and
##             TAG_3 three seconds of the game later (she keeps walking)
##   clearing  after a wait, put `--capture-dead=N` (2) walkers awake 5 to 8 tiles from her, run `--capture-run=S` (2.0) seconds, snapshot TAG
##   night     the hands of capture_fight.gd (aim, fire, reload, swing, walk to the fence that is attacked); a snapshot every `--capture-gap=S` (6) seconds while at least
##             `--capture-dead=N` (2) awake dead are on the screen, up to `--capture-shots=N` (3): TAG_1, TAG_2...
##   dawn      wait for the morning card to be up, snapshot TAG
## A snapshot freezes the game (`Engine.time_scale` 0), so every picture of it is the same instant; the files are OUT/TAG/{full,flags,nohud,world,e_<element>}.png and OUT/TAG/meta.json.

const TreeProbe := preload("res://tools/ui_audit/tree_probe.gd")
const Hints := preload("res://scripts/ui/hints.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")

var scn := "still"
var tag := "x"
var _busy := false
var _done := false
var _state := 0
var _snap_n := 0
var _last_snap_t := -999.0
var _route_i := 0
var _released_at := -1.0
var _first_key_t := -1.0
var _sim_t_at_state := 0.0
var _hint_node = null
## Nodes that are off in every picture of the snapshot (`--capture-guide=done`: the guide's card, cues and the legend of the keys, which a run some minutes old no longer has; a staged
## state, `--stage=fourth` and the like, begins them afresh at the last lesson).
var _base_hidden: Array = []
const GUIDE_PARTS := ["lesson_card", "lesson_cues", "rehearsal_card", "key_legend"]


func _begin() -> void:
	scn = String(opts.get("scn", "still"))
	tag = String(opts.get("name", scn))
	if out_dir == "":
		out_dir = "/tmp/ui_audit"
	DirAccess.make_dir_recursive_absolute(out_dir)
	if String(opts.get("tips", "")) == "1" and main.hints == null:
		_hint_node = Hints.new()
		main.add_child(_hint_node)
		var tips: Array = Hints.load_hints()
		if main.town != null:
			tips = OneHouse.town_hints(tips)
		_hint_node.setup(main, main.hud, main.sim, tips)
		main.hints = _hint_node
	if String(opts.get("hold", "")) == "1":
		main.speed = 0
		main.hud.toast("Press W A S D to begin", "info")
		if main.hud.banner_tween != null:
			main.hud.banner_tween.kill()
		main.hud.banner.modulate.a = 0.0
	print("AUDIT start: scn %s, tag %s, window %s, hour %.2f" % [scn, tag, str(get_window().size), float(main.sim.hour)])


func _read() -> void:
	pass


func _log() -> void:
	pass


func _calib() -> void:
	pass


func _exit_tree() -> void:
	pass


# ------------------------------------------------------------------------------ scenarios --

func _hands(dt: float) -> void:
	if _busy or _done:
		return
	var sim = main.sim
	var me = sim.avatar.player()
	if me == null:
		return
	if String(opts.get("hold", "")) == "1" and main.speed != 0 and scn == "still":
		main.speed = 0    # (the game's own hold lets go of it when the town part sees the loading card go; ours stays)
	match scn:
		"still", "dawn":
			var want := int(opts.get("wait", 100))
			var ok := _until_ok()
			# (the morning card may not come: a held first night has the end card instead, and the sim's dice decide; after `--capture-giveup` frames (900) the snapshot is taken of whatever is up)
			if frame >= want and (ok or frame >= want + int(opts.get("giveup", 900))):
				if not ok:
					print("AUDIT: the condition '%s' was not met; the snapshot is of what is on the screen" % String(opts.get("until", "")))
				_finish_after(tag)
		"opening":
			_opening(sim, me, dt)
		"clearing":
			_clearing(sim, me, dt)
		"night":
			_night(sim, me, dt)
		_:
			print("AUDIT: no scenario ", scn)
			_done = true
			get_tree().quit()


func _finish_after(label: String) -> void:
	_done = true
	await snap(label)
	print("AUDIT done: ", label)
	get_tree().quit()


func _until_ok() -> bool:
	var until := String(opts.get("until", ""))
	if until == "":
		return true
	if until == "dawn":
		var part = main.town.part("dawn_tally") if main.town != null else null
		return part != null and part.get("card") != null and (part.get("card") as Control).visible and (part.get("card") as Control).modulate.a > 0.9
	if until.begins_with("dead:"):
		return _awake_on_screen().size() >= int(until.get_slice(":", 1))
	return true


func _walk_route(op, me) -> void:
	var pos := Vector2(me.x, me.y)
	while _route_i < op.route.size() - 1 and pos.distance_to(op.route[_route_i]) < 0.9:
		_route_i += 1
	var wp: Vector2 = op.route[mini(_route_i + 1, op.route.size() - 1)]
	walk_keys((wp - pos).normalized(), false)


## The opening: walk the way the guide's first card says, along the opening's own route; the walker steps out by itself (the rules' trigger); snapshot then and 3 s later.
func _opening(sim, me, _dt: float) -> void:
	var op = sim.scenario.get("opening")
	if op == null or not bool(op.built):
		print("AUDIT: no opening in this run")
		_done = true
		get_tree().quit()
		return
	if frame < int(opts.get("wait", 20)):
		return
	if _first_key_t < 0.0:
		# the first key of a real run lifts the hold and says the opening words as a banner (a screenshot run said them 30 frames ago): the same words now, so that the banner is as old as it is in play
		_first_key_t = float(sim.t)
		main.hud.show_banner("The bell is ringing somewhere", "Find shelter before dark")
		main.hud.banner.modulate.a = 0.0
	if not bool(op.released):
		_walk_route(op, me)
		return
	if _state == 0:
		_state = 1
		_released_at = float(sim.t)
		print("AUDIT opening: first key at sim %.2f, walker out at %.2f (%.2f s of walking), banner alpha %.2f" % [_first_key_t, _released_at, _released_at - _first_key_t, main.hud.banner.modulate.a])
		snap_bg(tag + "_0")
		return
	_walk_route(op, me)
	if float(sim.t) - _released_at >= 3.0 and _state == 1:
		_state = 2
		_finish_after(tag + "_3")


func snap_bg(label: String) -> void:
	await snap(label)


## Clearing rooms with dead near: walkers put awake a few tiles off on free floor, run a moment, snapshot.
func _clearing(sim, me, _dt: float) -> void:
	if frame < int(opts.get("wait", 60)):
		return
	if _state == 0:
		_state = 1
		_sim_t_at_state = float(sim.t)
		var tc = _part("tutor_cues")
		if tc != null:
			tc.set("_freeze", false)    # (`--lesson=` holds the clock at 0 each frame: a real run is going)
		main.speed = 1
		var n := int(opts.get("dead", 2))
		var made := 0
		var dice := RandomNumberGenerator.new()
		dice.seed = 11
		var tries := 0
		var my_house := int(sim.houses.house_at(me.x, me.y))
		var my_room := int(sim.houses.room_at(me.x, me.y))
		while made < n and tries < 1200:
			tries += 1
			var a := dice.randf() * TAU
			var r := 3.5 + dice.randf() * 4.0
			var at := Vector2(floorf(me.x + cos(a) * r) + 0.5, floorf(me.y + sin(a) * r) + 0.5)
			if sim.world.is_solid(sim.world.solid_z, at.x, at.y) or sim.world.is_solid(sim.world.solid_p, at.x, at.y):
				continue
			# (in the house, in another room than hers: the dead of the next room, as a door opened shows them; outdoors only when the house has no room for them)
			if tries < 900 and (int(sim.houses.house_at(at.x, at.y)) != my_house or int(sim.houses.room_at(at.x, at.y)) == my_room):
				continue
			var z = sim.spawn(at.x, at.y, "approach", "walker")
			z.facing = "W" if at.x > me.x else "E"
			made += 1
		print("AUDIT: %d walkers put near her" % made)
		return
	if frame % 60 == 0:
		print("AUDIT clearing: frame %d, sim.t %.2f, speed %d, modal %s, dead %d" % [frame, float(sim.t), int(main.speed), str(main.town.modal()) if main.town != null else "-", sim.zombies.size()])
	if float(sim.t) - _sim_t_at_state >= float(opts.get("run", 2.0)):
		_finish_after(tag)


## The first attack night: Ruth fights as in capture_fight.gd with `--capture-waves=0` (the sim's own dead come to a fence of their choosing); snapshots while the dead are on the screen.
func _night(sim, me, dt: float) -> void:
	if frame < int(opts.get("wait", 30)):
		return
	if engage(dt, 14.0, true):
		walk_keys(Vector2.ZERO, false)
	else:
		_seek(sim, me)
	main.cam_hold = 0.0
	var need := int(opts.get("dead", 2))
	if float(sim.t) - _last_snap_t >= 30.0 and _snap_n > 0:
		need = 1    # (the night is quiet for a while: one will do after half a minute)
	if frame % 300 == 0:
		print("AUDIT night: frame %d, sim.t %.1f, awake %d, on screen %d, Ruth hp %s, speed %d, over %s" % [frame, float(sim.t), sim.zombies.size(), _awake_on_screen().size(), str(me.hp) if "hp" in me else "?", int(main.speed), str(sim.over)])
	var gap := float(opts.get("gap", 6.0))
	var shots_wanted := int(opts.get("shots", 3))
	if float(sim.t) - _last_snap_t >= gap and _awake_on_screen().size() >= need:
		_snap_n += 1
		_last_snap_t = float(sim.t)
		var label := "%s_%d" % [tag, _snap_n]
		if _snap_n >= shots_wanted:
			_finish_after(label)
		else:
			snap_bg(label)
	elif frame > int(opts.get("giveup", 14000)):
		print("AUDIT: gave up waiting for the dead")
		_done = true
		get_tree().quit()


# ------------------------------------------------------------------------------ what is where --

func _ratio() -> Vector2:
	var vp: Vector2 = main.get_viewport_rect().size
	var px := Vector2(get_window().size)
	return Vector2(px.x / vp.x, px.y / vp.y)


## Screen position (pixels) of a tile.
func _px_of(t: Vector2) -> Vector2:
	var r := _ratio()
	var p: Vector2 = main._tile_to_screen(t)
	return Vector2(p.x * r.x, p.y * r.y)


func _awake_on_screen() -> Array:
	var out: Array = []
	for d in _dead_list():
		if d.on_screen:
			out.append(d)
	return out


## Every awake dead one of the sim: kind, state, tile, screen point and the box of its sprite (pixels): about one tile wide and a tile and a half tall, the feet a little under the point
## the rules keep (measured on a walker of the opening: head 0.85 tile above the point, feet 0.35 below; a brute is drawn a third bigger).
func _dead_list() -> Array:
	var sim = main.sim
	var me = sim.avatar.player()
	var out: Array = []
	var px := Vector2(get_window().size)
	var ratio := _ratio()
	var tile_px: float = float(main.zoom_px) * ratio.x
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		var kind := String(z.kind) if "kind" in z else "walker"
		var c := _px_of(Vector2(z.x, z.y))
		var k := 1.33 if kind == "brute" else 1.0
		var box := Rect2(c.x - tile_px * 0.5 * k, c.y - tile_px * 0.85 * k - (k - 1.0) * tile_px * 0.35, tile_px * k, tile_px * 1.5 * k)
		var rec := {
			"kind": kind, "state": String(z.state), "x": snappedf(z.x, 0.01), "y": snappedf(z.y, 0.01),
			"dist": snappedf(Vector2(z.x - me.x, z.y - me.y).length(), 0.1), "px": [snappedf(c.x, 0.1), snappedf(c.y, 0.1)],
			"box": [snappedf(box.position.x, 0.1), snappedf(box.position.y, 0.1), snappedf(box.size.x, 0.1), snappedf(box.size.y, 0.1)],
			"on_screen": Rect2(Vector2.ZERO, px).intersects(box),
			"plated": bool(z.plated) if "plated" in z else false,
		}
		out.append(rec)
	out.sort_custom(func(a, b): return float(a.dist) < float(b.dist))
	return out


# ------------------------------------------------------------------------------ the snapshot --

## One picture of the frame as it is, with the nodes of `hidden` switched off for this draw only: they are hidden in the engine's `frame_pre_draw` (after every `_process` of the game,
## so a part that sets its own `visible` each frame, as the legend and the minimap do, cannot put them back) and shown again after the draw.
func _grab(dir: String, label: String, hidden: Array = [], keep_fx: bool = false) -> Image:
	await get_tree().process_frame
	var saved := {}
	var all: Array = hidden + _base_hidden
	if not keep_fx:
		all += _fx_nodes()    # (the red edge of a hurt avatar and the bell's vignette are shades of the screen's edge, not boards: measured on their own picture, `asplayed`)
	var hide_now := func() -> void:
		for n in all:
			if n != null and is_instance_valid(n):
				saved[n] = n.visible
				n.visible = false
	if not all.is_empty():
		RenderingServer.frame_pre_draw.connect(hide_now, CONNECT_ONE_SHOT)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	for n in saved.keys():
		if is_instance_valid(n):
			n.visible = saved[n]
	if label != "":
		img.save_png("%s/%s.png" % [dir, label])
	return img


func _part(name: String):
	return main.town.part(name) if main.town != null else null


func _v(obj, prop: String):
	return obj.get(prop) if obj != null else null


## The parts of the screen the audit tells apart, in the order of the report: {name, kind, group, nodes}. `kind`: persistent (always there), teaching (the guide's own),
## transient (comes and goes: banner, alerts, toasts, the morning card, the pages), world (marks and names drawn over the world). `group` is how the owner's flags see it:
## "tutorial" (`--hide-lesson`: the card and the cues), "banner" (`--no-banner`), "alerts" (`--no-alerts`), "hud" (what `--nohud` takes and the flags above do not), "world" (`--nohud` leaves it).
func _elements() -> Array:
	var hud = main.hud
	var th = _part("town_hud")
	var tc = _part("tutor_cues")
	var ea = _part("edge_arrows")
	var cm = _part("candidate_marks")
	var mm = _part("minimap")
	var sv = _part("sprint_view")
	var hp = _part("hurt_pulse")
	var ne = _part("night_event")
	var ls = _part("loot_shimmer")
	var sm = _part("salvage_marks")
	var dt = _part("dawn_tally")
	var rf = _part("room_flash")
	var rs = _part("room_search_ui")
	var sk = _part("search_marks")
	var over_layer = main.overlay.get_parent() if main.overlay != null else null
	# the right column's boards: the clock, then the weapon's (the column also holds boxes that are not boards: the first two that are PanelContainers and show)
	var right = hud.get("right_col")
	var boards: Array = []
	if right != null:
		for c in right.get_children():
			if c is PanelContainer and (c as Control).is_visible_in_tree():
				boards.append(c)
	var clock = boards[0] if boards.size() > 0 else null
	var weapon = boards[1] if boards.size() > 1 else null
	return [
		{"name": "stores", "kind": "persistent", "group": "hud", "nodes": [_v(hud, "res_panel")]},
		{"name": "objective", "kind": "persistent", "group": "hud", "nodes": [_v(th, "obj_card")]},
		{"name": "crew_cards", "kind": "persistent", "group": "hud", "nodes": [_v(hud, "bar")]},
		{"name": "clock", "kind": "persistent", "group": "hud", "nodes": [clock]},
		{"name": "weapon", "kind": "persistent", "group": "hud", "nodes": [weapon]},
		{"name": "toolbar", "kind": "persistent", "group": "hud", "nodes": [_v(hud, "speed_panel")]},
		{"name": "minimap", "kind": "persistent", "group": "hud", "nodes": [_v(mm, "root")]},
		{"name": "edge_arrows", "kind": "persistent", "group": "hud", "nodes": [_v(ea, "layer")]},
		{"name": "pennants", "kind": "persistent", "group": "hud", "nodes": [_v(cm, "layer")]},
		{"name": "objective_arrow_ring", "kind": "persistent", "group": "hud", "nodes": [_v(th, "layer")]},
		{"name": "radio_pill", "kind": "persistent", "group": "hud", "nodes": [_v(th, "radio_card")]},
		{"name": "sprint_arc", "kind": "persistent", "group": "hud", "nodes": [_v(sv, "layer")]},
		{"name": "key_legend", "kind": "teaching", "group": "tutorial", "nodes": [_v(th, "legend")]},    # (`--hide-lesson` puts it away too: checked against the real flags, tools/ui_audit/verify_flags.py)
		{"name": "lesson_card", "kind": "teaching", "group": "tutorial", "nodes": [_v(th, "lesson_card")]},
		{"name": "lesson_cues", "kind": "teaching", "group": "tutorial", "nodes": [_v(tc, "layer"), _v(tc, "top")]},
		{"name": "rehearsal_card", "kind": "teaching", "group": "tutorial", "nodes": [_v(tc, "card")]},
		{"name": "tip_card", "kind": "teaching", "group": "tutorial", "nodes": [main.hints]},
		{"name": "banner", "kind": "transient", "group": "banner", "nodes": [_v(hud, "banner")]},
		{"name": "alerts", "kind": "transient", "group": "alerts", "nodes": [_v(hud, "alerts_box"), _v(hud, "call_card"), _v(hud, "paused_pill")]},
		{"name": "toast", "kind": "transient", "group": "hud", "nodes": [_v(hud, "toast_panel")]},
		{"name": "morning_card", "kind": "transient", "group": "hud", "nodes": [_v(dt, "card")]},
		{"name": "room_chips", "kind": "transient", "group": "hud", "nodes": [_v(rf, "chip"), _v(rs, "chip"), _v(ne, "_chip")]},
		{"name": "radio_panel", "kind": "transient", "group": "hud", "nodes": [_v(hud, "radio_panel"), _v(hud, "radio_box")]},
		{"name": "loot_pops", "kind": "transient", "group": "hud", "nodes": [_v(sk, "pop_layer"), _v(sm, "pop_layer")]},
		{"name": "overlay_names_prompts", "kind": "world", "group": "world", "nodes": [over_layer]},
		{"name": "loot_shimmer_marks", "kind": "world", "group": "world", "nodes": [_v(ls, "node"), _v(sm, "_root")]},
	]


## The shades of the screen's edge: the red of a hurt avatar and the bell's vignette (kept out of every picture but `asplayed`).
func _fx_nodes() -> Array:
	var hp = _part("hurt_pulse")
	var ne = _part("night_event")
	return _live([_v(hp, "rect"), _v(ne, "_layer")])


func _live(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		if n != null and is_instance_valid(n):
			out.append(n)
	return out


func _shows(n) -> bool:
	if n != null and n == main.hints:
		return not (main.hints.active as Dictionary).is_empty()
	if n is Control:
		return (n as Control).is_visible_in_tree() and (n as Control).modulate.a > 0.02
	if n is CanvasLayer or n is CanvasItem:
		return n.visible
	return false


## Take one snapshot, as a coroutine: freeze, draw the frame with parts off, write the files.
func snap(label: String) -> void:
	_busy = true
	walk_keys(Vector2.ZERO, false)
	var dir := "%s/%s" % [out_dir, label]
	DirAccess.make_dir_recursive_absolute(dir)
	var prev := Engine.time_scale
	Engine.time_scale = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	var els := _elements()
	_base_hidden = []
	if String(opts.get("guide", "")) == "done":
		var kept: Array = []
		for e in els:
			if GUIDE_PARTS.has(String(e.name)):
				_base_hidden += _live(e.nodes)
			else:
				kept.append(e)
		els = kept
	var full := await _grab(dir, "full")
	var ratio := Vector2(float(full.get_width()) / float(main.get_viewport_rect().size.x), float(full.get_height()) / float(main.get_viewport_rect().size.y))
	var meta := _snap_meta(full, ratio)
	# a second take of the same frame: the noise floor (what moves by itself while the game is frozen)
	await _grab(dir, "again")
	await _grab(dir, "asplayed", [], true)
	# the owner's flags: --hide-lesson --no-banner --no-alerts, then --nohud, then the world with its own marks and names off too
	var tut: Array = []
	var hud_all: Array = [main.hud]
	var world_marks: Array = []
	for e in els:
		if e.group == "tutorial" or e.group == "banner" or e.group == "alerts":
			tut += _live(e.nodes)
		if e.group == "world":
			world_marks += _live(e.nodes)
	await _grab(dir, "flags", tut)
	await _grab(dir, "nohud", hud_all)
	await _grab(dir, "world", hud_all + world_marks)
	# one part at a time
	var listed: Array = []
	for e in els:
		var nodes := _live(e.nodes)
		var any := false
		var rects: Array = []
		var alpha := 0.0
		for n in nodes:
			if _shows(n):
				any = true
				# how opaque the part is drawn: its own and its parents' modulate (a card fading in, a board the game has made see-through): over 0.4 it hides what is under it
				var a := 1.0
				var up = n
				while up != null and up is CanvasItem:
					a *= float((up as CanvasItem).modulate.a)
					up = up.get_parent()
				alpha = maxf(alpha, a)
				if n is Control:
					var r := (n as Control).get_global_rect()
					rects.append([snappedf(r.position.x * ratio.x, 0.1), snappedf(r.position.y * ratio.y, 0.1), snappedf(r.size.x * ratio.x, 0.1), snappedf(r.size.y * ratio.y, 0.1)])
		if not any:
			continue
		await _grab(dir, "e_" + String(e.name), nodes)
		listed.append({"name": e.name, "kind": e.kind, "group": e.group, "rects": rects, "alpha": snappedf(alpha, 0.01)})
	meta["elements"] = listed
	var f := FileAccess.open(dir + "/meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	Engine.time_scale = prev
	print("AUDIT snapshot: ", label, " (", listed.size(), " parts)")
	_busy = false


func _snap_meta(full: Image, ratio: Vector2) -> Dictionary:
	var sim = main.sim
	var me = sim.avatar.player()
	var tile_px: float = float(main.zoom_px) * ratio.x
	var avatar_px := _px_of(Vector2(me.x, me.y))
	var m := {
		"label": tag, "size": [full.get_width(), full.get_height()], "ratio": [ratio.x, ratio.y], "zoom_px": float(main.zoom_px), "tile_px": tile_px,
		"hour": float(sim.hour), "day": int(sim.day), "sim_t": float(sim.t),
		"avatar": {"x": me.x, "y": me.y, "px": [avatar_px.x, avatar_px.y], "mag": int(me.mag)},
		"dead": _dead_list(),
		"cam": [main.cam_center.x, main.cam_center.y],
		"banner_alpha": float(main.hud.banner.modulate.a) if main.hud.banner.visible else 0.0,
		"speed": int(main.speed),
	}
	if sim.scenario != null and sim.scenario.has_method("objective"):
		var o = sim.scenario.objective()
		m["objective"] = o if o is Dictionary else str(o)
	if sim.scenario != null and sim.scenario.has_method("guide"):
		var gd = sim.scenario.guide()
		m["lesson"] = gd if gd is Dictionary else str(gd)
	if sim.scenario != null and sim.scenario.has_method("stage"):
		m["stage"] = String(sim.scenario.stage())
	var op = sim.scenario.get("opening") if sim.scenario != null else null
	if op != null and bool(op.built):
		var sp := _px_of(op.spawn_at)
		var bp := _px_of(op.box_at)
		m["opening"] = {"released": bool(op.released), "spawn_px": [sp.x, sp.y], "box_px": [bp.x, bp.y], "first_key_t": _first_key_t, "released_t": _released_at}
	m["tree"] = TreeProbe.walk(main, ratio)
	var crew: Array = []
	for p in sim.people:
		if p.dead:
			continue
		var cpx := _px_of(Vector2(p.x, p.y))
		crew.append({"id": str(p.id), "x": snappedf(p.x, 0.01), "y": snappedf(p.y, 0.01), "px": [cpx.x, cpx.y]})
	m["people"] = crew
	return m
