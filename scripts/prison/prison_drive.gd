## EXPERIMENT (prison fix round B): a driver that checks the prison's UI with REAL input events (InputEventKey, InputEventMouseMotion, InputEventMouseButton through Input.parse_input_event), not by
## calling the handlers. Debug only: `--drive=board|roster|keys|gate|gateclick|stash|drag|packfull|gunwin` (managed base or raid, windowed). Each prints `DRIVE ...` lines (ok or FAIL) and quits.
## Run: `Godot --path . --fixed-fps 60 --disable-vsync -- --prison --managed --drive=board`
extends RefCounted

var g    # prison_game.gd
var fails := 0


func _init(game) -> void:
	g = game


func _wait(n: int = 2) -> void:
	for i in n:
		await g.get_tree().process_frame


func _xf() -> Transform2D:
	return g.get_viewport().get_final_transform()


func _key(code: int, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _tap(code: int) -> void:
	_key(code, true)
	await _wait(2)
	_key(code, false)
	await _wait(2)


func _mouse_to(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _xf() * p
	e.global_position = e.position
	Input.parse_input_event(e)
	await _wait(1)
	if g.get_viewport().get_mouse_position().distance_to(p) > 2.0:    # (a parsed motion does not move the viewport's pointer: warp the real one, the window is the game's own)
		g.get_viewport().warp_mouse(p)
		await _wait(2)


func _btn(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = _xf() * p
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)


func _click(p: Vector2) -> void:
	await _mouse_to(p)
	_btn(p, true)
	await _wait(2)
	_btn(p, false)
	await _wait(3)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _find(n: Node, pred: Callable) -> Array:
	var out: Array = []
	if pred.call(n):
		out.append(n)
	for ch in n.get_children():
		out.append_array(_find(ch, pred))
	return out


func _buttons(root: Node, prefix: String) -> Array:
	return _find(root, func(n): return n is Button and (n as Button).visible and (n as Button).is_visible_in_tree() and (n as Button).text.begins_with(prefix))


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	printerr("DRIVE ", "ok   " if ok else "FAIL ", what)


func _put(at: Vector2) -> void:
	g.run.avatar_p.x = at.x
	g.run.avatar_p.y = at.y
	await _wait(4)


func _finish() -> void:
	printerr("DRIVE done, failures: ", fails)
	g.get_tree().quit()


func run(name: String) -> void:
	printerr("DRIVE start ", name)
	await _wait(25)
	match name:
		"board":
			await _board()
		"roster":
			await _roster()
		"keys":
			await _keys()
		"gate", "gateclick":
			await _gate(name == "gateclick")
		"places":
			await _places()
		"squad":
			await _squad()
		"raidx":
			await _raidx()
		"searched":
			await _searched()
		"stash":
			await _stash()
		"drag":
			await _drag()
		"packfull":
			await _packfull()
		"gunwin":
			await _gunwin()
	await _finish()


# ----------------------------------------------------------------------------------- scenarios --

func _board() -> void:
	var st: Dictionary = g.stores
	st.scrap = 200.0
	st.parts = 30.0
	await _put(Vector2(g.base.stations.bench1) + Vector2(0.0, 1.2))
	_check(String(g._prompt.get("kind", "")) == "bench", "at the bench the prompt is the project board")
	await _tap(KEY_E)
	_check(g.board.is_open() and g.board.tab == "projects", "E opens the project board")
	await _wait(6)
	var before: float = float(st.scrap)
	var q0: int = (g.econ.queue as Array).size()
	var starts := _buttons(g.board.panel, "Start").filter(func(b): return not (b as Button).disabled)
	_check(not starts.is_empty(), "a Start button that can be pressed (%d)" % starts.size())
	if not starts.is_empty():
		await _click(_center(starts[0]))
		_check((g.econ.queue as Array).size() == q0 + 1, "click on Start queues the project (queue %d to %d: %s)" % [q0, (g.econ.queue as Array).size(), g.econ.queue])
		var spent := {}
		for k in ["scrap", "parts", "meds", "food", "water", "fuel"]:
			spent[k] = k
		_check(float(st.scrap) < before or float(st.parts) < 30.0, "the cost was spent (scrap %d to %d, parts 30 to %d)" % [int(before), int(st.scrap), int(st.parts)])
	await _tap(KEY_ESCAPE)
	_check(not g.board.is_open(), "Esc closes the board")


func _roster() -> void:
	await _put(Vector2(g.base.stations.bench1) + Vector2(0.0, 1.2))
	await _tap(KEY_B)
	_check(g.board.is_open(), "B opens the Base screen")
	g.board._show("roster")
	await _wait(8)
	var obs := _find(g.board.panel, func(n): return n is OptionButton and not (n as OptionButton).disabled)
	_check(not obs.is_empty(), "role drop-downs on the roster (%d)" % obs.size())
	if not obs.is_empty():
		var ob: OptionButton = obs[0]
		var row := _find(g.board.panel, func(n): return n is OptionButton).find(ob)
		var who := ""
		var roles: Dictionary = g.econ.cfg.crew_role
		var ids: Array = []
		for m in g.crew.members:
			if not m.def.has("ally") and not m.def.has("play"):
				ids.append(String(m.def.id))
		who = String(ids[row]) if row < ids.size() else ""
		var old := String(roles.get(who, ""))
		await _click(_center(ob))
		var pop := ob.get_popup()
		_check(pop.visible, "click on the drop-down opens its list")
		var want := 2 if ob.selected != 2 else 3
		var item_h := float(pop.size.y) / float(maxi(1, pop.item_count))
		var click_at: Vector2 = Vector2(pop.position) + Vector2(30.0, item_h * (float(want) + 0.5))
		await _click(click_at)
		await _wait(4)
		var now := String(roles.get(who, ""))
		_check(now != old and now == String(g.board.ROLES[want]), "choosing a role changes the job of %s (%s to %s)" % [who, old, now])
	await _tap(KEY_B)
	_check(not g.board.is_open(), "B again closes the roster")


func _keys() -> void:
	await _put(Vector2(g.base.stations.bench1) + Vector2(0.0, 1.2))
	await _tap(KEY_B)
	_check(g.board.is_open() and g.board.tab == "roster", "B: roster opens")
	await _tap(KEY_B)
	_check(not g.board.is_open(), "B: and closes it")
	await _tap(KEY_E)
	_check(g.board.is_open() and g.board.tab == "projects", "E at the bench: project board")
	await _tap(KEY_B)
	_check(g.board.is_open() and g.board.tab == "roster", "B in the board: switches to the roster")
	await _tap(KEY_ESCAPE)
	_check(not g.board.is_open(), "Esc closes the board")
	await _tap(KEY_E)
	await _tap(KEY_TAB)
	_check(not g.board.is_open(), "Tab closes the board")
	_check(g.pack.ui != null and g.pack.ui.is_open(), "and Tab opens the backpack")
	await _tap(KEY_TAB)
	_check(not g.pack.ui.is_open(), "Tab again puts the backpack away")
	await _tap(KEY_I)
	_check(g.pack.ui.is_open(), "I opens the backpack")
	await _tap(KEY_B)
	_check(g.board.is_open() and not g.pack.ui.is_open(), "B opens the Base screen and closes the backpack (%s, pack open %s)" % [g.board.is_open(), g.pack.ui.is_open()])
	await _tap(KEY_I)
	_check(not g.board.is_open() and g.pack.ui.is_open(), "I closes the board and opens the backpack")
	await _tap(KEY_ESCAPE)
	_check(not g.pack.ui.is_open(), "Esc closes the backpack")


func _gate(by_click: bool) -> void:
	await _put(Vector2(g.base.stations.truck) + Vector2(0.0, 1.0))
	_check(String(g._prompt.get("kind", "")) == "gate", "at the truck the prompt is the gate")
	await _tap(KEY_E)
	_check(g.loot.choosing and g.loot.dest.is_open, "E opens the destination map")
	await _wait(4)
	_check(g.loot.dest.ids.size() >= 7, "the map lists the places (%d)" % g.loot.dest.ids.size())
	var want := "hospital"
	var i := int(g.loot.dest.ids.find(want))
	if by_click:
		var pos: Vector2 = g.loot.dest.canvas.global_position + g.loot.dest._pos(want, g.loot.dest.canvas.size)
		await _click(pos)
	else:
		await _tap(KEY_1 + i)
	_check(String(g.loot.dest.ids[g.loot.dest.sel]) == want, "the marker is selected (%s)" % String(g.loot.dest.ids[g.loot.dest.sel]))
	_check(not g.loot.dest.go_btn.disabled, "Go is on for an open place")
	await _tap(KEY_ENTER)
	_check(not g.loot.choosing and g.loot.picked_kind == want and g.loot.picked == 1, "Go sets the town (%s) and the meds mark (picked %d)" % [g.loot.picked_kind, g.loot.picked])
	await _wait(4)
	_check(g.loadout.is_open, "the choice opens the loadout card (gun, kit, companions)")
	await _tap(KEY_ENTER)
	await _wait(400)
	_check(g.mode == "raid", "the truck goes out (mode %s)" % g.mode)
	_check(g.loot.kind == want and g.loot.option == 1, "the raid is at the %s and hunts option %d: %s" % [g.loot.kind, g.loot.option, g.loot.target])


## The data of the places is whole: every place has a town kind, finds with the three words, an unlock day, a map spot, and the late places are later than the early ones.
func _places() -> void:
	var L = g.loot
	var late := {}
	for id in L.place_ids():
		var pc: Dictionary = L.place_cfg(id)
		_check(not L.raw_kind(String(pc.kind)).is_empty(), "%s has the town kind %s" % [id, pc.kind])
		_check(not (pc.finds as Array).is_empty() and (pc.finds as Array).all(func(f): return ["often", "sometimes", "rarely"].has(String(f[1]))), "%s: finds use often/sometimes/rarely" % id)
		_check(int(pc.danger) >= 1 and int(pc.danger) <= 5 and (pc.map as Array).size() == 2, "%s: danger 1 to 5 and a map spot" % id)
		late[id] = int(pc.unlock_day)
	_check(int(late.stadium) == 5 and int(late.port) == 8 and int(late.airport) == 12, "stadium day 5, port day 8, airport day 12")
	_check(L.offer(1).size() < L.offer(12).size() and L.offer(12).size() == L.place_ids().size(), "places open by day (day 1: %d, day 12: %d)" % [L.offer(1).size(), L.offer(12).size()])
	_check(L.kind_cfg("airport").get("answers", []).has("parts") and L.place_for("police") == "police", "a place carries its kind's data; an event's kind word finds its place")


func _squad() -> void:
	# the gate's second step with real keys: 1 and 2 pick two companions, W the next gun, Enter goes; in the raid C opens the orders and 2 holds them all
	await _put(Vector2(g.base.stations.truck) + Vector2(0.0, 1.0))
	await _tap(KEY_E)
	await _tap(KEY_1)    # (the map: the first place, then Enter goes)
	await _tap(KEY_ENTER)
	await _wait(4)
	_check(g.loadout.is_open, "the choice opens the loadout card")
	var shown: int = g.squad.cands.size()
	_check(shown > 5, "the card lists the crew (%d)" % shown)
	await _tap(KEY_1)
	await _tap(KEY_2)
	_check(g.squad.picked.size() == 2, "keys 1 and 2 pick two companions: %s" % [g.squad.picked])
	await _tap(KEY_3)
	_check(g.squad.picked.size() == 2, "a third is refused (two at most)")
	var gun0: String = g.arms.main
	await _tap(KEY_W)
	_check(g.arms.main != gun0, "W picks the next gun (%s to %s)" % [gun0, g.arms.main])
	await _tap(KEY_ENTER)
	await _wait(400)
	_check(g.mode == "raid" and g.squad.members.size() == 2, "the raid starts with two companions (%d)" % g.squad.members.size())
	_check(String(g.run.avatar_p.weapon) == g.arms.main, "Ruth holds the gun she chose (%s)" % g.run.avatar_p.weapon)
	_check(g.econ.crew().filter(func(c): return c.get("out", false)).size() == 2, "the economy counts them as out")
	await _tap(KEY_C)
	_check(g.squad.open, "C opens the orders")
	await _tap(KEY_2)
	_check(g.squad.members.all(func(m): return String(m.cmd) == "hold"), "2 holds them all")
	_check(not g.squad.open, "the panel closes after an order")
	await _tap(KEY_C)
	await _tap(KEY_6)
	_check(g.squad.members.all(func(m): return String(m.cmd) == "spread"), "6 spreads them out")
	g.squad.command_all("follow")
	await _wait(30)
	_check(g.squad.members.all(func(m): return String(m.say) in ["with you", "fighting", "firing"] or String(m.say).begins_with("hurt")), "the status line says what they do (%s)" % [g.squad.members.map(func(m): return m.say)])


## RAID EXTRAS: fuel refusal, Done and Avoid marks, Night, presets, weather, the retreat key, the hospital patient, the save round trip.
func _raidx() -> void:
	var rx = g.raidx
	g.stores["fuel"] = 0.0
	g.econ.day = 9
	await _put(Vector2(g.base.stations.truck) + Vector2(0.0, 1.0))
	await _tap(KEY_E)
	var d = g.loot.dest
	await _tap(KEY_1 + int(d.ids.find("port")))
	_check(d.go_btn.disabled and d.note.text.begins_with("Not enough fuel") and d.go_btn.text == "Not enough fuel", "no fuel: Go is refused with a clear message (%s)" % d.note.text)
	g.stores["fuel"] = 10.0
	d.select(d.ids.find("hospital"))
	_check(not d.go_btn.disabled, "with fuel (and a free place) Go is on")
	await _tap(KEY_X)
	_check(rx.mark_of("hospital") == "done", "X marks the place done")
	await _tap(KEY_X)
	_check(rx.mark_of("hospital") == "avoid", "X again: avoid")
	await _tap(KEY_X)
	_check(rx.mark_of("hospital") == "", "X again: no mark")
	await _tap(KEY_X)
	await _tap(KEY_T)
	_check(d.pick_time == "night", "T picks the night")
	await _tap(KEY_ENTER)
	await _wait(4)
	await _tap(KEY_1)
	await _tap(KEY_2)
	var picked0: Array = g.squad.picked.duplicate()
	g.loadout.save_preset(1)
	g.squad.picked = []
	g.loadout.apply_preset(1)
	_check(picked0.size() == 2 and g.squad.picked == picked0, "a preset keeps the two companions and puts them back (%s)" % [g.squad.picked])
	await _tap(KEY_ENTER)
	await _wait(400)
	_check(g.mode == "raid" and g.loot.kind == "hospital", "the raid is at the hospital")
	_check(rx.hour() >= 20.0 and String(g.run.sim.phase) != "day", "Night: the raid hour is %.1f, phase %s" % [rx.hour(), g.run.sim.phase])
	_check(["clear", "rain", "fog"].has(String(rx.weather)), "the raid has a weather (%s)" % rx.weather)
	await _tap(KEY_V)
	await _wait(40)
	_check(rx.retreating and g.squad.members.all(func(m): return String(m.say) == "retreating" or m.state != "up"), "V: the squad retreats (%s)" % [g.squad.members.map(func(m): return m.say)])
	await _tap(KEY_V)
	_check(not rx.retreating, "V again stands down")
	var pats: Array = g.special.list.values().filter(func(i): return i.kind == "patient")
	_check(pats.size() >= 1 and pats.size() <= 2 and pats.all(func(i): return i.phase == "idle"), "the hospital has 1 or 2 patients lying still (%d)" % pats.size())
	if not pats.is_empty():
		var z = pats[0].z
		await _put(Vector2(z.x, z.y) + Vector2(2.0, 0.0))
		await _wait(10)
		_check(String(pats[0].phase) == "lunge", "a patient lunges when Ruth is within 3 tiles")
	var dd := {"marks": {"hospital": "avoid", "x": "bad"}, "presets": [{"main": "smg"}, {}, {}]}
	rx.from_dict(dd)
	_check(rx.mark_of("hospital") == "avoid" and rx.mark_of("x") == "" and rx.presets.size() == 3 and rx.presets[0].main == "smg", "marks and presets load (bad entries dropped)")
	rx.from_dict({})
	_check(rx.marks.is_empty() and rx.presets == [{}, {}, {}], "an older save has neither: both empty")


## RAID EXTRAS: the searched marks. Ruth stands in a room, one container is searched by the sim, the others of the room are marked searched and empty; a picture goes to --shot when given.
func _searched() -> void:
	await _put(Vector2(11.5, 42.5))
	var room := -2
	for ct in g.town.containers:
		if Vector2(ct.pos).distance_to(Vector2(11.5, 42.5)) < 0.6:
			room = int(ct.room)
	var n := 0
	for ct in g.town.containers:
		if int(ct.room) == room:
			g.run.sim.search.looted[String(ct.id)] = true
			n += 1
	_check(n >= 1, "a room with containers was marked searched (%d)" % n)
	await _wait(10)
	if g.args.has("shot"):
		g.get_viewport().get_texture().get_image().save_png(String(g.args.shot))


func _stash() -> void:
	var st: Dictionary = g.stores
	await _put(Vector2(g.base.stations.stores) + Vector2(0.0, 1.0))
	_check(String(g._prompt.get("kind", "")) == "stores", "at the stores the prompt is the stash")
	await _tap(KEY_E)
	_check(g.pack.inv.stash_open, "E opens the stash")
	await _wait(20)
	var sw = g.pack.ui.stash_win
	var food0 := int(st.food)
	var pack0: int = int(g.pack.grid.cells.size())
	var b5: Button = sw.rows["food"].buttons[1]    # "5"
	await _click(_center(b5))
	var food1 := int(st.food)
	_check(food1 == food0 - 5, "stash '5' on food moves 5 into the pack (stores %d to %d, pack stacks %d to %d)" % [food0, food1, pack0, g.pack.grid.cells.size()])
	var ball: Button = sw.rows["water"].buttons[2]    # "All"
	var w0 := int(st.water)
	await _click(_center(ball))
	_check(int(st.water) < w0, "stash 'All' on water takes what fits (stores %d to %d)" % [w0, int(st.water)])
	await _click(_center(sw.deposit_button))
	_check(int(st.food) >= food0 and int(st.water) >= w0, "Deposit all puts it back (food %d, water %d)" % [int(st.food), int(st.water)])
	await _tap(KEY_ESCAPE)
	_check(not g.pack.inv.stash_open, "Esc closes the stash")


func _drag() -> void:
	await _put(Vector2(g.base.stations.stores) + Vector2(0.0, 1.0))
	var Inv := preload("res://scripts/sim/inventory.gd")
	g.pack.grid.cells.clear()
	Inv.auto_add(g.pack.grid, "bandage", 1)
	g.pack.inv.version = int(g.pack.inv.version) + 1
	await _tap(KEY_I)
	await _wait(15)
	var win = g.pack.ui.pack_win
	var gc = win.grid_ctl
	_check(g.pack.ui.is_open() and (g.pack.grid.cells as Array).size() == 1, "backpack open with one stack")
	var c0: Dictionary = ((g.pack.grid.cells as Array)[0] as Dictionary).duplicate()
	var r: Rect2 = gc.rect_of(0)
	var from: Vector2 = gc.get_global_rect().position + r.get_center()
	var to: Vector2 = from + Vector2(float(gc.get_global_rect().size.x / maxf(1.0, float(gc.cols()))) * 3.0, float(gc.get_global_rect().size.x / maxf(1.0, float(gc.cols()))) * 2.0)
	await _mouse_to(from)
	_btn(from, true)
	await _wait(2)
	var steps := 8
	for i in steps + 1:
		await _mouse_to(from.lerp(to, float(i) / steps))
	_check(not g.pack.ui.drag.is_empty(), "pressing and moving picks the stack up (drag %s)" % (g.pack.ui.drag.get("item", "none")))
	_check(g.pack.blocks_fire(), "and the gun is blocked while it is held")
	_btn(to, false)
	await _wait(4)
	var c1: Dictionary = (g.pack.grid.cells as Array)[0] if (g.pack.grid.cells as Array).size() > 0 else {}
	_check(g.pack.ui.drag.is_empty() and (c0.x != c1.get("x", c0.x) or c0.y != c1.get("y", c0.y)), "release drops it on a new cell (%s,%s to %s,%s)" % [c0.x, c0.y, c1.get("x"), c1.get("y")])
	await _tap(KEY_I)


func _packfull() -> void:
	# the pack is filled to 32 of 32 cells, a container that holds loot is searched, and Space (take all) is pressed: what does not fit must stay in the container
	var inv = g.pack.inv
	var Inv := preload("res://scripts/sim/inventory.gd")
	for n in 300:
		Inv.auto_add(g.pack.grid, "water_jug", 1)
		Inv.auto_add(g.pack.grid, "water_bottle", 1)
		Inv.auto_add(g.pack.grid, "ration_pack", 1)
		Inv.auto_add(g.pack.grid, "canned_food", 4)
		Inv.auto_add(g.pack.grid, "medkit", 1)
		Inv.auto_add(g.pack.grid, "bandage", 1)
	_check(Inv.used_cells(g.pack.grid) >= Inv.cell_count(g.pack.grid) - 1, "the pack is full (%d of %d cells)" % [Inv.used_cells(g.pack.grid), Inv.cell_count(g.pack.grid)])
	var ct = null
	for c in g.town.containers:
		if not (c.loot as Dictionary).is_empty() and Vector2(c.pos).distance_to(Vector2(g.run.avatar_p.x, g.run.avatar_p.y)) < 40.0:
			ct = c
			break
	_check(ct != null, "a container with loot is near the start")
	if ct == null:
		return
	await _put(Vector2(ct.pos))
	var used := false
	for c in g.run.sim.uses.candidates(g.run.avatar_p):
		if String(c.kind) == "container":
			g.run.sim.uses.use(c)
			used = true
			break
	_check(used, "the container is searched")
	var seen_id := ""
	for i in 600:
		await _wait(1)
		if inv.open_id != "":
			seen_id = inv.open_id
			break
	_check(seen_id != "", "its loot window opens (%s)" % seen_id)
	await _wait(10)
	var before: int = int((inv.containers[seen_id].cells as Array).size()) if seen_id != "" else 0
	await _tap(KEY_SPACE)
	var shown := false
	for i in 90:
		if g.msg_label.text.begins_with("Pack full") or g.msg_label.text.begins_with("No room"):
			shown = true
			break
		await _wait(1)
	var left: int = int((inv.containers[seen_id].cells as Array).size()) if seen_id != "" and inv.containers.has(seen_id) else -1
	_check(shown, "a full-pack line shows (No room in the pack, or Pack full): %s" % g.msg_label.text)
	_check(left > 0, "the item stays in the container (stacks before %d, after %d)" % [before, left])


func _gunwin() -> void:
	await _put(Vector2(g.base.stations.stores) + Vector2(0.0, 1.0))
	await _wait(10)
	var shots0: int = int(g.run.sim.stats.get("shots", 0)) if g.run.sim.get("stats") != null else 0
	await _tap(KEY_I)
	await _wait(15)
	var win = g.pack.ui.pack_win
	var inside: Vector2 = win.get_global_rect().get_center()
	await _mouse_to(inside)
	_check(g.pack.blocks_fire(), "the pointer over the backpack blocks the gun")
	var m0: int = int(g.run.avatar_p.mag)
	_btn(inside, true)
	await _wait(20)
	_btn(inside, false)
	await _wait(5)
	_check(int(g.run.avatar_p.mag) == m0, "a held click over the window fires nothing (mag %d to %d)" % [m0, int(g.run.avatar_p.mag)])
	await _tap(KEY_I)
	var out := Vector2(g._vp().x * 0.5, g._vp().y * 0.3)
	await _mouse_to(out)
	_btn(out, true)
	await _wait(20)
	_btn(out, false)
	_check(int(g.run.avatar_p.mag) < m0, "the same click on the field fires (mag %d to %d)" % [m0, int(g.run.avatar_p.mag)])
