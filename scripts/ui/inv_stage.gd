## Staging the inventory windows for a screenshot or a probe (INV-UI): `--inv=open|loot|stash|full|drag-ok|drag-bad|menu|probe` (README, "Automated checks"). A staged run puts sample content in
## the pack and opens the window named, a few frames after the run has started and the windows have been laid out. The pointer is not needed: a drag is held at a place the stage picks.
## `--inv-reveal=N` sets how many stacks of the staged container are found (the search itself is the rules': it reveals one every 0.4 s). Development only: nothing here runs in a played game.
extends RefCounted

const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvGeom := preload("res://scripts/ui/inv_geom.gd")
const INV_PART := "res://scripts/town/inv.gd"

## The frame the stage is set on, and the frame the window is shown on.
const SET_FRAME := 6
const SHOW_FRAME := 14


## A staged run has an inventory even where the rules did not give the run one: the sim part (scripts/town/inv.gd) is made and put on the sim by hand. A run that has one is left alone.
static func ensure(sim) -> void:
	if InvApi.inv(sim) != null or not ResourceLoader.exists(INV_PART):
		return
	var part = load(INV_PART).new()
	part.setup(sim)
	part.begin({"shells": 40})
	(sim as Object).set_meta("inv", part)


## The sample pack: a mixed one, with the stacks put where they read well.
static func mixed_pack(pack: Dictionary) -> void:
	pack.cells.clear()
	for p in [["shells", 24, 0, 0, 0], ["shells", 17, 1, 0, 0], ["canned_food", 3, 2, 0, 0], ["canned_food", 4, 3, 0, 0], ["bandage", 3, 4, 0, 0], ["bandage", 2, 5, 0, 0],
			["water_bottle", 1, 0, 1, 0], ["ration_pack", 1, 1, 1, 0], ["water_jug", 1, 2, 1, 0], ["medkit", 1, 4, 1, 0], ["water_bottle", 1, 4, 2, 1], ["canned_food", 2, 6, 0, 0]]:
		InvApi.place(pack, String(p[0]), int(p[1]), int(p[2]), int(p[3]), int(p[4]))


## A pack with every cell taken.
static func full_pack(pack: Dictionary) -> void:
	mixed_pack(pack)
	for item in ["water_jug", "ration_pack", "medkit", "water_bottle", "canned_food", "bandage", "shells"]:
		var guard := 0
		while guard < 40 and InvApi.auto_add(pack, item, int(InvApi.item(item).stack)) == 0:
			guard += 1


## The grid of a container of four by three with five stacks.
static func container_grid() -> Dictionary:
	var g := InvApi.make_grid(4, 3)
	for p in [["canned_food", 2, 0, 0, 0], ["water_bottle", 1, 1, 0, 0], ["bandage", 2, 2, 0, 0], ["shells", 6, 3, 0, 0], ["medkit", 1, 0, 2, 0]]:
		InvApi.place(g, String(p[0]), int(p[1]), int(p[2]), int(p[3]), int(p[4]))
	return g


## Opens `grid` as the loot window of a container of the avatar's house (the first one it has, so that its name and place are real), `revealed` stacks found (-1: all).
static func open_container(sim, grid: Dictionary, revealed: int) -> String:
	var inv = InvApi.inv(sim)
	var hs = sim.get("houses")
	var me = sim.avatar.player()
	var id := "stage_cupboard"
	if hs != null and me != null:
		var h: int = hs.house_at(me.x, me.y)
		if h < 0:
			h = hs.start_house()
		for c in hs.containers_of(h):
			id = String(c.id)
			break
	inv.containers[id] = grid
	inv.open_id = id
	inv.searched[id] = true    # (so that the rules do not take a staged search for a stopped one and shut the window on the next step)
	inv.set_meta("stage_revealed", revealed if revealed >= 0 else grid.cells.size())
	_stand_at(sim, hs.container(id).get("at", hs.container(id).get("pos", null)) if hs != null else null)
	inv.changed()
	return id


## Puts the avatar beside a point of the map (a staged window stays up only while she is near the container or the stash that it belongs to).
static func _stand_at(sim, at) -> void:
	var me = sim.avatar.player() if sim.get("avatar") != null else null
	if me == null or at == null:
		return
	var p := Vector2(at)
	me.x = p.x
	me.y = p.y + 1.0


## One frame of a stage: `frame` counts the frames since the run began.
static func step(ui, stage: String, frame: int) -> void:
	var sim = ui.sim
	var inv = InvApi.inv(sim)
	if inv == null:
		return
	if stage == "real":
		_real(ui, frame)
		return
	if frame == SET_FRAME:
		var pk := InvApi.pack(sim)
		if stage == "full":
			full_pack(pk)
		else:
			mixed_pack(pk)
		var rev := 2
		for arg in OS.get_cmdline_user_args():
			if String(arg).begins_with("--inv-reveal="):
				rev = int(String(arg).trim_prefix("--inv-reveal="))
		match stage:
			"loot":
				open_container(sim, container_grid(), rev)
			"stash":
				inv.stash_open = true
				var sp: Vector2 = inv._stash_pos()
				if sp != Vector2.INF:
					_stand_at(sim, sp)
			"full":
				ui.pack_user = true
				sim.alert("pack-home", "info", "Your pack is full", "Deposit it at the stash (E)", null, 30.0)    # (what the rules raise when she walks home with it)
			"open", "drag-ok", "drag-bad", "menu", "probe":
				ui.pack_user = true
			"quick", "drag-quick":
				ui.pack_user = true
				for i in InvApi.QUICK_SLOTS:    # (the belt full: a bandage, a tin, a bottle and the medkit; the drag stage leaves the last one empty for the drop)
					InvApi.set_quick(sim, i, ["bandage", "canned_food", "water_bottle", "" if stage == "drag-quick" else "medkit"][i])
			"help":
				ui.hud._press_help()    # (the "?" panel of the controls: the table's new rows must fit it)
		inv.changed()
		ui._dirty = true
	elif frame == SHOW_FRAME:
		match stage:
			"drag-ok", "drag-bad":
				_stage_drag(ui, stage == "drag-ok")
			"drag-quick":
				_stage_drag_quick(ui)
			"menu":
				var g = ui.pack_win.grid_ctl
				var idx := 2    # (the three cans)
				ui._open_menu(g, idx, g.get_global_rect().position + g.rect_of(idx).get_center())
			"probe":
				var probe = load("res://tools/inv_probe.gd").new()
				probe.run(ui)
		ui._stage_done = true


## `--inv=real`: the same through the engine's own input (`Input.parse_input_event`), so that the key goes the whole way (the viewport, the GUI, `Main._unhandled_input`, the town's facade, this part)
## and the pointer is routed by the GUI as a player's would be (the press picks the stack, the motion and the release come to the grid that was pressed). Prints `REAL name: PASS|FAIL`.
static func _real(ui, frame: int) -> void:
	var sim = ui.sim
	var g = ui.pack_win.grid_ctl
	match frame:
		SET_FRAME:
			mixed_pack(InvApi.pack(sim))
			InvApi.inv(sim).changed()
		12:
			_key(KEY_TAB)
		16:
			_report("Tab opens the pack through the game's own input", ui.pack_win.visible)
			ui._poll()
		20:
			_mouse_move(ui, g, Vector2(0, 0))
		21:
			_mouse_button(ui, g, Vector2(0, 0), true)
		22:
			_mouse_move(ui, g, Vector2(3, 2))
		23:
			_report("a press and a move pick the stack up", not ui.drag.is_empty())
			_mouse_move(ui, g, Vector2(7, 3))
		24:
			_mouse_button(ui, g, Vector2(7, 3), false)
		28:
			var c: Dictionary = InvApi.pack(sim).cells[0]
			_report("the release drops it where the pointer was (the shells at (7, 3): %d, %d)" % [int(c.x), int(c.y)], int(c.x) == 7 and int(c.y) == 3 and ui.drag.is_empty())
			var mag_before := int(sim.avatar.player().mag)
			_key(KEY_R)
			ui.set_meta("mag_before", mag_before)
		32:
			_report("R with nothing held reaches the reload (the magazine %d -> %d)" % [int(ui.get_meta("mag_before")) if ui.has_meta("mag_before") else -1, int(sim.avatar.player().mag)], sim.avatar.player().reloading > 0.0 or int(sim.avatar.player().mag) > int(ui.get_meta("mag_before")))
			_key(KEY_ESCAPE)
		36:
			_report("Esc puts the pack away and does not open the menu", not ui.is_open() and not bool(ui.main.menu_open))
			_key(KEY_I)
		40:
			_report("I opens it again", ui.pack_win.visible)
			ui.close_all()
			ui.set_meta("toasts", ui.toast_count)
			ui.set_meta("speed", int(ui.main.speed))
			for i in InvApi.QUICK_SLOTS:
				InvApi.set_quick(sim, i, ["bandage", "canned_food", "water_bottle", ""][i])
			_key(KEY_2)    # (INV2: a plain digit is a quick slot in the town)
		44:
			_report("the key 2 goes the whole way to the belt (slot 2, a tin: %s)" % ui.last_toast, ui.toast_count == int(ui.get_meta("toasts")) + 1 and ui.last_toast.to_lower().contains("coming soon"))
			_report("and does not change the speed", int(ui.main.speed) == int(ui.get_meta("speed")))
			_key(KEY_2, true)
		48:
			_report("Shift and 2 is the speed (it was %d, it is %d)" % [int(ui.get_meta("speed")), int(ui.main.speed)], int(ui.main.speed) == 2)
			ui.main._set_speed(int(ui.get_meta("speed")))
			ui._stage_done = true


static func _key(code: Key, shift: bool = false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		ev.shift_pressed = shift
		Input.parse_input_event(ev)


static func _window_point(ui, hud_point: Vector2) -> Vector2:
	return ui.main.get_viewport().get_final_transform() * hud_point


static func _cell_point(g, cell: Vector2) -> Vector2:
	return g.get_global_rect().position + Vector2(g.PAD, g.PAD) + (cell + Vector2(0.5, 0.5)) * g.cell


static func _mouse_move(ui, g, cell: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _window_point(ui, _cell_point(g, cell))
	ev.global_position = ev.position
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if (not ui.drag.is_empty() or not ui.pending.is_empty()) else 0
	Input.parse_input_event(ev)


static func _mouse_button(ui, g, cell: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _window_point(ui, _cell_point(g, cell))
	ev.global_position = ev.position
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)


static func _report(what: String, ok: bool) -> void:
	print("REAL %s: %s" % [what, "PASS" if ok else "FAIL"])


## Holds the medkit over the empty fourth quick slot (the green frame and the tick).
static func _stage_drag_quick(ui) -> void:
	var g = ui.pack_win.grid_ctl
	var idx := InvApi.first_stack(g.grid, "medkit")
	if idx < 0:
		return
	ui.begin_drag(g, idx, g.get_global_rect().position + g.rect_of(idx).get_center() - Vector2(g.cell * 0.5, g.cell * 0.5))
	ui.drag_move(ui.pack_win.doll.slot_global_rect(InvApi.QUICK_SLOTS - 1).get_center())


## Holds the water jug (2 by 2) at a place where it fits (`ok`) or over a stack (it does not).
static func _stage_drag(ui, ok: bool) -> void:
	var g = ui.pack_win.grid_ctl
	var pk: Dictionary = g.grid
	var idx := -1
	for i in pk.cells.size():
		if String(pk.cells[i].item) == "water_jug":
			idx = i
	if idx < 0:
		return
	var from: Vector2 = g.get_global_rect().position + g.rect_of(idx).get_center() - Vector2(g.cell * 0.5, g.cell * 0.5)
	ui.begin_drag(g, idx, from)
	var target_cell := Vector2i(6, 2)    # (free: the two columns at the right of the third row and the fourth)
	if not ok:
		target_cell = Vector2i(1, 1)    # (over the ration pack)
	var gp: Vector2 = g.get_global_rect().position + Vector2(g.PAD, g.PAD) + (Vector2(float(target_cell.x), float(target_cell.y)) + Vector2(0.5, 0.5)) * g.cell
	ui.drag_move(gp)
