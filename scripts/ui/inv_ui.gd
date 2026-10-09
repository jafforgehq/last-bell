## The inventory's windows (INV-UI): a VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`, `on_event(e)`, `on_key(ev)`). It reads the
## sim's inventory (`sim.inv`, scripts/town/inv.gd, through scripts/ui/inv_api.gd, the only door) and changes it only by calling the rules' own functions (`take_item`, `move_item`, `put_back`,
## `deposit_item`, `deposit_all`, `withdraw`, `drop`, `use_item`, and the logic's `move`, `split`, `quick_move`: scripts/sim/inventory.gd), so everything it does is something the bot could do.
##
##   - THE BACKPACK (Tab and I, Esc): her pack as a grid with the equipment (scripts/ui/inv_pack_window.gd). Drag and drop with the mouse, a green (a tick) or red (a cross) frame of where the held
##     item fits, R turns it, a double-click moves a stack at once, a right-click opens its menu (use, split, turn, drop), a tooltip names it.
##   - THE LOOT WINDOW: `sim.inv.open_id` puts that container (`grid_of(id)`, its stacks found one by one: `revealed(id)`) beside the pack; Take all is Space or Enter and a button. The rules shut it
##     when she walks away or stops the search; Esc and Tab shut it too.
##   - THE STASH PANEL: `sim.inv.stash_open` puts the stores (five rows, live numbers, withdraw 1, 5, all, Deposit all, and a drop target) beside the pack.
##   - THE HUD: a chip in the stores strip with the pack's fullness (9/32) and its tooltip; what the top bar's numbers mean (scripts/ui/inv_totals.gd).
## The windows are built once, on the first frame of a run that has an inventory, and then only brought up to date when the pack changed (ten looks a second); a drag redraws one overlay. They
## never pause the game, never hold the avatar's hands and sit where they hide neither her nor the HUD's boards (the coach's placement rule, tried for each window in turn).
## Staging for screenshots and probes: `--inv=open|loot|stash|full|drag-ok|drag-bad|menu|probe` (scripts/ui/inv_stage.gd, tools/inv_probe.gd).
extends RefCounted

const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvGeom := preload("res://scripts/ui/inv_geom.gd")
const InvIcons := preload("res://scripts/ui/inv_icons.gd")
const InvRoot := preload("res://scripts/ui/inv_root.gd")
const InvMenu := preload("res://scripts/ui/inv_menu.gd")
const InvPackWindow := preload("res://scripts/ui/inv_pack_window.gd")
const InvLootWindow := preload("res://scripts/ui/inv_loot_window.gd")
const InvStashWindow := preload("res://scripts/ui/inv_stash_window.gd")
const InvStage := preload("res://scripts/ui/inv_stage.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const CbShapes := preload("res://scripts/ui/cb_shapes.gd")
const ControlsTable := preload("res://scripts/ui/controls_table.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Access := preload("res://scripts/access.gd")

## How often (seconds) the sim's inventory is looked at.
const POLL_S := 0.1
## How far (pixels) the pointer must move before a pressed stack is dragged.
const DRAG_PX := 4.0
const DEPOSIT_TEXT := "Deposit (E at the stash)"
const EDGE := 12.0
const OK := Color("#8fb85a")
const BAD := Color("#e0584a")
const ACCENT := Color("#f0c24a")
const INK := Color("#eeeadd")

var main
var hud
var sim
var root
var overlay: Control
var pack_win
var loot_win
var stash_win
var menu
## The pack's chip in the stores strip (a Control) and its words.
var chip: Control
var chip_label: Label
var chip_icon: Control
## The player opened the pack (Tab, I, the chip): it stays up till they put it away. A container or the stash opens it too, and it goes with them.
var pack_user := false
var cell := 48.0
## The drag in hand: {"src": "pack" | "loot", "grid": the control, "index", "item", "count", "rot", "grab": Vector2i, "pos": Vector2, "target": {...}}, {} for none.
var drag := {}
## A pressed stack that may become a drag: {"grid", "index", "from": Vector2}.
var pending := {}
## The menu's stack: {"grid", "index"}.
var menu_for := {}
## Toasts said (the tests read the last).
var last_toast := ""
var toast_count := 0

var _t := POLL_S
var _dirty := true
var _frames := 0
var _hud_size := Vector2.ZERO
var _placed := {}
var _stage := ""
var _stage_frame := 0
var _stage_done := false
var _pack_sig := 0
var _loot_sig := 0
var _chip_text := ""
var _size_fn := Callable(InvApi, "size_of")
var _cap_fn := Callable(self, "_cap_of")
var _last_visible := ""
## `--inv-cost`: the part's own script time, printed after COST_FRAMES frames (development).
var _cost_on := "--inv-cost" in OS.get_cmdline_user_args()
var _cost_us := 0
var _cost_n := 0
var _cost_max := 0
var _poll_us := 0
var _polls := 0
const COST_FRAMES := 150


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	sim = main.get("sim")
	if hud == null or sim == null:
		return
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--inv="):
			_stage = a.trim_prefix("--inv=")
	if _stage != "":
		InvStage.ensure(sim)    # (a screenshot or a probe of the windows: the staged run has an inventory even where the rules have none yet)
	if InvApi.active(sim):
		_build()


func modal() -> bool:
	return false


# ---------------------------------------------------------------------------------- build --

func _build() -> void:
	if root != null or hud == null:
		return
	cell = InvGeom.cell_for(hud.size)
	root = InvRoot.new()
	root.ctl = self
	hud.add_child(root)
	pack_win = InvPackWindow.new()
	pack_win.setup(self, hud, cell)
	loot_win = InvLootWindow.new()
	loot_win.setup(self, hud, cell)
	stash_win = InvStashWindow.new()
	stash_win.setup(self, hud)
	menu = InvMenu.new()
	menu.setup(self, hud)
	pack_win.set_cell(cell)
	stash_win.set_compact(cell < 44.0)
	for w in [pack_win, loot_win, stash_win]:
		w.visible = false
		root.add_child(w)
	overlay = Control.new()
	overlay.name = "InvOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(_draw_overlay)
	root.add_child(overlay)
	root.add_child(menu)
	_hud_size = hud.size


func active() -> bool:
	return root != null and sim != null and InvApi.active(sim)


## Whether any of the windows is up.
func is_open() -> bool:
	return root != null and (pack_win.visible or loot_win.visible or stash_win.visible)


# --------------------------------------------------------------------------------- frames --

func on_frame(dt: float) -> void:
	if not _cost_on:
		_per_frame(dt)
		return
	var t0 := Time.get_ticks_usec()
	_per_frame(dt)
	var us := Time.get_ticks_usec() - t0
	_cost_us += us
	_cost_n += 1
	_cost_max = maxi(_cost_max, us)
	if _cost_n == COST_FRAMES:
		print("INV_COST stage=%s open=%s: on_frame %.1f us a frame (max %d us) over %d frames; %d looks at the sim, %.1f us each; grid redraws %d" % [_stage, str(is_open()), float(_cost_us) / float(_cost_n), _cost_max, _cost_n, _polls, float(_poll_us) / maxf(float(_polls), 1.0), _redraws()])


func _per_frame(dt: float) -> void:
	_frames += 1
	if sim == null or hud == null:
		return
	if root == null:
		if _frames % 15 == 0 and InvApi.active(sim):
			_build()
		if root == null:
			return
	if not _chip_built():
		_build_chip()
	_t += dt
	if _t >= POLL_S or _dirty:
		_t = 0.0
		_dirty = false
		_poll()
	if _stage != "" and not _stage_done:
		_stage_frame += 1
		InvStage.step(self, _stage, _stage_frame)
	if not drag.is_empty() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _stage == "":
		cancel_drag()    # (the release was lost: the pointer left the window, or the focus did)


## Reads the sim and brings the windows up to date: which are up, their contents, the chip and, when one came or went or the window changed, their places.
func _poll() -> void:
	if _cost_on:
		var t0 := Time.get_ticks_usec()
		_poll_now()
		_poll_us += Time.get_ticks_usec() - t0
		_polls += 1
		return
	_poll_now()


## How many times the grids were told to draw again (the cost's other half: a draw is the engine's, a redraw only when something changed).
func _redraws() -> int:
	return (int(pack_win.grid_ctl.draws) + int(loot_win.grid_ctl.draws)) if root != null else 0


func _poll_now() -> void:
	# a menu, a full page or sleep has the screen: the windows wait behind it (they are not put away: the pack comes back as it was)
	var hidden: bool = main.get("menu_open") == true or hud.modal_open() or _asleep()
	if root.visible == hidden:
		root.visible = not hidden
		if hidden:
			cancel_drag()
			menu.close()
	var pk := InvApi.pack(sim)
	var lo := InvApi.loot(sim)
	var stash := InvApi.stash_open(sim)
	var want_loot := not lo.is_empty()
	var want_pack := pack_user or want_loot or stash
	var vis := "%s%s%s" % ["p" if want_pack else "", "l" if want_loot else "", "s" if stash else ""]
	var changed := vis != _last_visible
	if hud.size != _hud_size:
		_hud_size = hud.size
		var c := InvGeom.cell_for(hud.size)
		if not is_equal_approx(c, cell):
			cell = c
			pack_win.set_cell(cell)
			loot_win.set_cell(cell)
			stash_win.set_compact(cell < 44.0)
		changed = true
	if changed:
		_last_visible = vis
		pack_win.visible = want_pack
		loot_win.visible = want_loot
		stash_win.visible = stash
		if not want_loot and not drag.is_empty() and String(drag.src) == "loot":
			cancel_drag()
		if menu.visible:
			menu.close()
	if want_pack:
		var sig := hash(pk.cells) if not pk.is_empty() else 0
		pack_win.refresh(sim, pk, sig != _pack_sig or changed)
		_pack_sig = sig
		if drag.is_empty() and pack_win.grid_ctl.held_index >= 0:
			pack_win.grid_ctl.set_held(-1)
	if want_loot:
		var lsig := hash(lo.grid.cells) * 31 + int(lo.revealed)
		if lsig != _loot_sig or changed or String(lo.id) != loot_win.shown_id:
			_loot_sig = lsig
			loot_win.show_container(lo)
		if drag.is_empty() and loot_win.grid_ctl.held_index >= 0:
			loot_win.grid_ctl.set_held(-1)
	elif loot_win.shown_id != "":
		loot_win.shown_id = ""
		_loot_sig = 0
	if stash:
		stash_win.refresh(InvApi.store_totals(sim), _can_deposit(pk))
	_refresh_chip(pk)
	if changed or _needs_replace():
		_place()


func _needs_replace() -> bool:
	if not is_open():
		return false
	var kept := _kept_clear()
	var obs := _obstacles()
	var rects: Array = []
	for w in _open_windows():
		var r := Rect2(w.position, w.size)
		var want: Vector2 = w.get_combined_minimum_size()
		if want.x > 0.0 and not w.size.is_equal_approx(want):
			return true
		if Coach._hidden(r, kept) > 0.5 or Coach._hidden(r, obs) > 0.5:
			return true
		for o in rects:
			if (o as Rect2).intersects(r):
				return true
		rects.append(r)
	return false


func _open_windows() -> Array:
	var out: Array = []
	for w in [pack_win, loot_win, stash_win]:
		if w.visible:
			out.append(w)
	return out


func _can_deposit(pk: Dictionary) -> bool:
	if pk.is_empty():
		return false
	for c in pk.cells:
		if String(InvApi.item(String(c.item)).res) != "":
			return true
	return false


func _cap_of(id: String) -> int:
	return int(InvApi.item(id).stack)


# ---------------------------------------------------------------------------------- places --

## Where the windows go: one after the other (the pack first), each where it hides neither the avatar nor a board of the HUD nor a window placed before it, beside the pack for the second.
func _place() -> void:
	if not is_open():
		return
	var vp: Vector2 = hud.size
	var kept := _kept_clear()
	var obs := _obstacles()
	var placed: Array = []
	for w in _open_windows():
		w.size = Vector2.ZERO
		w.size = w.get_combined_minimum_size()
		var prev := Rect2(w.position, w.size) if _placed.has(w.name) else Rect2()
		var beside: Rect2 = placed[0] if not placed.is_empty() else Rect2()
		var keep: Array = kept.duplicate()
		keep.append_array(placed)
		var r := _best(w.size, keep, obs, prev, beside, vp)
		w.position = r.position
		_placed[w.name] = r
		placed.append(r)
	if overlay != null:
		overlay.queue_redraw()


## The cheapest place for a window of `sz`: from the sides of the window and, for the second window, round the first; the cost is what it would hide of `keep` (the avatar, the windows
## already placed) and of the HUD's boards, and a place that was kept is worth staying in.
func _best(sz: Vector2, keep: Array, obs: Array, prev: Rect2, beside: Rect2, vp: Vector2) -> Rect2:
	var bounds := Rect2(Vector2(EDGE, EDGE), vp - Vector2(EDGE, EDGE) * 2.0)
	var spots: Array = []
	if beside.size.x > 0.0:
		spots.append_array(Coach._beside(beside, sz))
	var mid_y := (vp.y - sz.y) * 0.5
	for p in [Vector2(vp.x - sz.x - EDGE, mid_y), Vector2(EDGE, mid_y), Vector2(vp.x - sz.x - EDGE, vp.y - sz.y - 90.0), Vector2(EDGE, vp.y - sz.y - 90.0), Vector2(vp.x - sz.x - EDGE, 150.0), Vector2(EDGE, 150.0),
			Vector2((vp.x - sz.x) * 0.5, vp.y - sz.y - EDGE), Vector2((vp.x - sz.x) * 0.5, EDGE)]:
		spots.append(Rect2(p, sz))
	spots.append(Coach.best_rect(hud, sz, vp, Rect2(), "bottom", false, true, keep, prev))
	var pick := Coach._fit(spots[0], bounds)
	var pick_cost := INF
	for i in spots.size():
		var r := Coach._fit(spots[i], bounds)
		var cost: float = Coach._hidden(r, keep) * Coach.KEEP_WEIGHT + Coach._hidden(r, obs) * 24.0 + float(i) * 150.0
		if prev.size == sz and r.position.distance_to(prev.position) < 1.0:
			cost -= Coach.STAY_BONUS + float(i) * 150.0
		if cost < pick_cost:
			pick_cost = cost
			pick = r
	return pick


## What a window keeps off: the avatar (the figure with her tag, and the room round her for the gun's muzzle: the coach's rule).
func _kept_clear() -> Array:
	var out: Array = []
	var me = sim.avatar.player() if sim.get("avatar") != null else null
	if me == null or me.away != null:
		return out
	var at: Vector2 = main.view_pos(me)
	var a: Vector2 = main._tile_to_screen(at + Vector2(-0.5, -1.9))
	var b: Vector2 = main._tile_to_screen(at + Vector2(0.5, 0.5))
	out.append(Rect2(a, b - a).abs())
	var c: Vector2 = main._tile_to_screen(at + Vector2(0.0, -0.45))
	var rad: float = Coach.AVATAR_CLEAR * float(main.zoom_px)
	out.append(Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0))
	return out


## The HUD's boards that cover the world (the stores, the clock, the gun's readout, the alerts, the radio panel, the crew's cards...) and the town's cards and the minimap.
func _obstacles() -> Array:
	var out: Array = hud.covered_rects()
	var town = main.get("town")
	var th = town.part("town_hud") if town != null and town.has_method("part") else null
	if th != null:
		for n in ["obj_card", "lesson_card", "legend", "radio_card"]:
			var board = th.get(n)
			if board is Control and is_instance_valid(board) and board.is_visible_in_tree() and board.size.x > 0.0:
				out.append(board.get_global_rect())
	var mm = town.part("minimap") if town != null and town.has_method("part") else null
	if mm != null and mm.get("root") is Control and (mm.root as Control).is_visible_in_tree():
		out.append((mm.root as Control).get_global_rect())
	return out


# ----------------------------------------------------------------------------- open, shut --

## Tab and I: the pack comes up, or everything that is up goes.
func toggle() -> void:
	if root == null:
		return
	if is_open():
		close_all()
	else:
		open_pack()


func open_pack() -> void:
	if root == null:
		return
	pack_user = true
	_dirty = true
	_poll()


## The pack's own close (the cross): the pack goes, and with it the container and the stash that were beside it.
func close_pack() -> void:
	close_all()


func close_all() -> void:
	if root == null:
		return
	cancel_drag()
	menu.close()
	pack_user = false
	if loot_win.visible:
		InvApi.close_container(sim)
	if stash_win.visible:
		InvApi.close_stash(sim)
	_dirty = true
	_poll()


func close_loot() -> void:
	if not drag.is_empty() and String(drag.src) == "loot":
		cancel_drag()
	InvApi.close_container(sim)
	_dirty = true
	_poll()


func close_stash() -> void:
	InvApi.close_stash(sim)
	_dirty = true
	_poll()


# ------------------------------------------------------------------------------------ keys --

func on_key(ev: InputEvent) -> bool:
	if root == null or not (ev is InputEventKey) or not active():
		return false
	var k := ev as InputEventKey
	if not k.pressed or k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return false
	if main.get("menu_open") == true or hud.modal_open() or String(sim.over) != "" or _asleep():
		return false
	var code: Key = k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if code == KEY_R and not drag.is_empty():
		if not k.echo:
			rotate_drag()
		return true
	if k.echo:
		return false
	match code:
		KEY_TAB, KEY_I:
			if k.shift_pressed:
				return false
			toggle()
			return true
		KEY_ESCAPE:
			if menu.visible:
				menu.close()
				return true
			if not drag.is_empty():
				cancel_drag()
				return true
			if is_open():
				close_all()
				return true
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if loot_win.visible:
				take_all_pressed()
				return true
	return false


## Whether she is asleep (the screen is black: no key opens the pack then).
func _asleep() -> bool:
	var sl = sim.get("sleep")
	return sl != null and sl.has_method("active") and bool(sl.active())


## Events the controller listens to: a toast the rules ask for (`deposit_hint`, `inv_toast`) is shown as they say it; any other event of the pack makes the windows look again.
func on_event(e: Dictionary) -> void:
	var t := String(e.get("type", ""))
	if t == "deposit_hint" or t == "inv_toast":
		say(String(e.get("text", DEPOSIT_TEXT)), String(e.get("level", "info")))
	if ["loot_open", "loot_close", "picked", "dropped", "stash_open", "deposit", "withdraw", "pack_full"].has(t):
		_dirty = true


func say(text: String, level: String = "info") -> void:
	last_toast = text
	toast_count += 1
	if hud != null:
		hud.toast(text, level)


## Every event of the root (before the GUI): a click away from the menu puts it away.
func root_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and menu != null and menu.visible:
		var mb := ev as InputEventMouseButton
		if not menu.get_global_rect().has_point(mb.position):
			menu.close()


func cancel_drag() -> void:
	if not drag.is_empty():
		var g = drag.grid
		if is_instance_valid(g):
			g.set_held(-1)
	drag = {}
	pending = {}
	if overlay != null:
		overlay.queue_redraw()


# -------------------------------------------------------------------------- the pointer --

## Every mouse event of a grid (the grids hand them on): a press picks a stack up, a move drags it, a release drops it; a right-click opens the menu, a double-click moves the stack.
func grid_input(g, ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		var gp: Vector2 = g.get_global_rect().position + mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(g, mb, gp)
			else:
				_release(gp)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and drag.is_empty():
			var idx: int = g.index_at(mb.position, true)
			if idx >= 0:
				pending = {}
				_open_menu(g, idx, gp)
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		var gp2: Vector2 = g.get_global_rect().position + mm.position
		if not drag.is_empty():
			drag_move(gp2)
		elif not pending.is_empty():
			if gp2.distance_to(pending.from) > DRAG_PX:
				var pg = pending.grid
				var pi: int = pending.index
				var from: Vector2 = pending.from
				pending = {}
				begin_drag(pg, pi, from)
				drag_move(gp2)
		else:
			g.set_hover(g.index_at(mm.position, true))


func grid_exit(g) -> void:
	if drag.is_empty():
		g.set_hover(-1)


func _press(g, mb: InputEventMouseButton, gp: Vector2) -> void:
	if menu.visible:
		menu.close()
	var idx: int = g.index_at(mb.position, true)
	if idx < 0:
		return
	if mb.double_click:
		pending = {}
		quick_move_index(g, idx)
		return
	pending = {"grid": g, "index": idx, "from": gp}


func _release(gp: Vector2) -> void:
	if not drag.is_empty():
		drop_at(gp)
	pending = {}


## Picks the stack `index` of grid `g` up, held by the cell under `from` (a point in the window's pixels).
func begin_drag(g, index: int, from: Vector2) -> void:
	if index < 0 or index >= g.grid.cells.size() or not drag.is_empty():
		return
	var c: Dictionary = g.grid.cells[index]
	var sz: Vector2i = InvApi.size_of(String(c.item), int(c.rot))
	var origin: Vector2 = g.get_global_rect().position + Vector2(g.PAD, g.PAD) + Vector2(float(c.x), float(c.y)) * g.cell
	var grab := Vector2i(clampi(int(floor((from.x - origin.x) / g.cell)), 0, sz.x - 1), clampi(int(floor((from.y - origin.y) / g.cell)), 0, sz.y - 1))
	drag = {"src": g.kind, "grid": g, "index": index, "item": String(c.item), "count": int(c.count), "rot": int(c.rot), "grab": grab, "pos": from, "target": {}}
	g.set_held(index)
	g.set_hover(-1)
	menu.close()
	drag.target = _target_at(from)
	overlay.queue_redraw()


func drag_move(gp: Vector2) -> void:
	if drag.is_empty():
		return
	drag.pos = gp
	drag.target = _target_at(gp)
	overlay.queue_redraw()


## R while an item is held: a quarter turn (a square item has none).
func rotate_drag() -> void:
	if drag.is_empty():
		return
	var d: Dictionary = InvApi.item(String(drag.item))
	if int(d.w) == int(d.h):
		return
	drag.rot = 1 - int(drag.rot)
	var sz: Vector2i = InvApi.size_of(String(drag.item), int(drag.rot))
	drag.grab = InvGeom.turned_grab(drag.grab, sz.x, sz.y)
	drag.target = _target_at(drag.pos)
	overlay.queue_redraw()


## What the held item is over at `gp`: {"over": "grid" | "stash" | "window" | "world", "grid", "state", "x", "y", "w", "h", "index"}.
func _target_at(gp: Vector2) -> Dictionary:
	for g in [pack_win.grid_ctl, loot_win.grid_ctl]:
		if not g.is_visible_in_tree():
			continue
		var r: Rect2 = g.get_global_rect()
		if not r.has_point(gp):
			continue
		var c: Vector2i = g.cell_at(gp - r.position)
		if c.x < 0:
			return {"over": "window", "state": InvGeom.BLOCKED}
		var skip: int = int(drag.index) if is_same(g, drag.grid) else -1
		var t: Dictionary = InvGeom.target(g.grid, _size_fn, _cap_fn, String(drag.item), int(drag.rot), int(drag.count), c, drag.grab, skip)
		if String(t.state) == InvGeom.MERGE:
			var h: Dictionary = g.grid.cells[int(t.index)]
			var hs: Vector2i = InvApi.size_of(String(h.item), int(h.rot))
			t["w"] = hs.x
			t["h"] = hs.y
		t["over"] = "grid"
		t["grid"] = g
		if g.kind == "loot" and String(drag.src) != "loot" and int(g.revealed) >= 0:
			t["state"] = InvGeom.BLOCKED    # (nothing is put into a container that is still being searched)
		return t
	if stash_win.visible and stash_win.get_global_rect().has_point(gp):
		var res := String(InvApi.item(String(drag.item)).res)
		return {"over": "stash", "state": InvGeom.FREE if (res != "" and String(drag.src) == "pack") else InvGeom.BLOCKED}
	for w in _open_windows():
		if (w as Control).get_global_rect().has_point(gp):
			return {"over": "window", "state": InvGeom.BLOCKED}
	for r in hud.covered_rects():
		if (r as Rect2).has_point(gp):
			return {"over": "window", "state": InvGeom.BLOCKED}
	return {"over": "world", "state": InvGeom.FREE if String(drag.src) == "pack" else InvGeom.BLOCKED}


## The held item is let go at `gp`.
func drop_at(gp: Vector2) -> void:
	if drag.is_empty():
		return
	var d: Dictionary = drag
	var t: Dictionary = _target_at(gp)
	drag = {}
	var src = d.grid
	if is_instance_valid(src):
		src.set_held(-1)
		# (the rules may have moved things while it was held, a reload that took the last shells, a container shut: the stack it was is no more, nothing is done)
		if int(d.index) >= src.grid.cells.size() or String(src.grid.cells[int(d.index)].item) != String(d.item):
			overlay.queue_redraw()
			_after_change()
			return
	match String(t.get("over", "world")):
		"grid":
			_drop_on_grid(d, t)
		"stash":
			if String(t.state) == InvGeom.FREE:
				deposit_index(int(d.index))
			else:
				say("The stores take food, water, ammo and medicine", "warn")
		"world":
			if String(t.state) == InvGeom.FREE:
				if InvApi.drop(sim, int(d.index), -1):
					say("Dropped %s" % _count_name(d), "info")
	overlay.queue_redraw()
	_after_change()


## A drop on a grid, by the rules' own calls: inside a grid (`move`, which joins a stack of its kind when it is dropped on one), from the container to the pack (`move_item`), back into it (`put_back`).
func _drop_on_grid(d: Dictionary, t: Dictionary) -> void:
	var tg = t.grid
	var sg = d.grid
	var ok := false
	var id := String(InvApi.loot(sim).get("id", ""))
	var state := String(t.state)
	if state != InvGeom.FREE and state != InvGeom.MERGE:
		if String(t.get("over", "")) == "grid" and tg.kind == "loot" and String(d.src) != "loot" and int(tg.revealed) >= 0:
			say("Wait until the search is done", "warn")
		else:
			say("It does not fit there", "warn")
		return
	if is_same(sg, tg):
		var c: Dictionary = sg.grid.cells[int(d.index)]
		if state == InvGeom.FREE and int(c.x) == int(t.x) and int(c.y) == int(t.y) and int(c.rot) == int(d.rot):
			return
		ok = InvApi.move(sg.grid, int(d.index), tg.grid, int(t.x), int(t.y), int(d.rot))
		InvApi.changed(sim)
	elif String(d.src) == "loot":
		ok = InvApi.move_item(sim, id, int(d.index), int(t.x), int(t.y), int(d.rot))
	else:
		ok = InvApi.put_back(sim, id, int(d.index), int(t.x), int(t.y), int(d.rot))
	if not ok:
		say("That stack is full" if state == InvGeom.MERGE else "It does not fit there", "warn")


func _count_name(d: Dictionary) -> String:
	var nm := String(InvApi.item(String(d.item)).name)
	return ("%d %s" % [int(d.count), nm]) if int(d.count) > 1 else nm


# ----------------------------------------------------------------------------- quick moves --

## A double-click: a stack of the container goes to the pack, a stack of the pack goes to the container that is open (when all of it is found), or onto the stores, or is used.
func quick_move_index(g, index: int) -> void:
	var pk := InvApi.pack(sim)
	if pk.is_empty() or index < 0 or index >= g.grid.cells.size():
		return
	var lo := InvApi.loot(sim)
	if g.kind == "loot":
		if not InvApi.take_item(sim, String(lo.id), index):
			say("No room in the pack", "warn")
		_after_change()
		return
	var c: Dictionary = g.grid.cells[index]
	var d: Dictionary = InvApi.item(String(c.item))
	if loot_win.visible and not lo.is_empty() and int(lo.revealed) >= lo.grid.cells.size():
		if InvApi.quick_move(pk, index, lo.grid):
			InvApi.changed(sim)
		else:
			say("No room in the container", "warn")
	elif stash_win.visible:
		deposit_index(index)
	elif String(d.use) == "bandage":
		use_index(index)
	_after_change()


## Uses the stack (a bandage) through the rules; they say why when they cannot.
func use_index(index: int) -> void:
	var r := InvApi.use_item(sim, index)
	if bool(r.get("ok", false)):
		say("Bandaging", "info")
	else:
		say(String(r.get("why", "")) if String(r.get("why", "")) != "" else "Nothing to do with it now", "warn")
	_after_change()


## One stack of the pack onto the stores, by the rules' own `deposit_item`.
func deposit_index(index: int) -> void:
	var pk := InvApi.pack(sim)
	if pk.is_empty() or index < 0 or index >= pk.cells.size():
		return
	var c: Dictionary = pk.cells[index]
	var d: Dictionary = InvApi.item(String(c.item))
	if String(d.res) == "":
		say("The stores do not take that", "warn")
		return
	var res := String(d.res)
	var u := InvApi.deposit_item(sim, index)
	if u <= 0:
		say("The stores did not take it", "warn")
		return
	say("Deposited: %d %s" % [u, "medicine" if res == "meds" else res], "info")
	_after_change()


func _deposit_words(got: Dictionary) -> String:
	var parts: Array = []
	for r in ["ammo", "food", "water", "meds"]:
		if int(got.get(r, 0)) > 0:
			parts.append("%d %s" % [int(got[r]), "medicine" if r == "meds" else r])
	return ("Deposited: " + ", ".join(parts)) if not parts.is_empty() else "Deposited"


func deposit_all_pressed() -> void:
	var got := InvApi.deposit_all(sim)
	say(_deposit_words(got) if not got.is_empty() else "Nothing in the pack that the stores take", "info" if not got.is_empty() else "warn")
	_after_change()


func withdraw_pressed(res: String, n: int) -> void:
	var have := int(InvApi.store_totals(sim).get(res, 0))
	if have <= 0:
		return
	var want := have if n < 0 else mini(n, have)
	var moved := InvApi.withdraw(sim, res, want)
	if moved <= 0:
		say("No room in the pack", "warn")
	elif moved < want and n < 0:
		say("Took %d: the pack is full" % moved, "info")
	_after_change()


## Take all: everything found that fits goes to the pack (the rules' `take_all_open`); while the search is half done only the stacks found are taken. What does not fit stays in the container.
func take_all_pressed() -> void:
	var lo := InvApi.loot(sim)
	if lo.is_empty():
		return
	var lg: Dictionary = lo.grid
	if lg.cells.is_empty():
		return
	var before := _units_in(lg)
	if int(lo.revealed) >= lg.cells.size():
		InvApi.take_all_open(sim)
	else:
		for i in range(int(lo.revealed) - 1, -1, -1):
			InvApi.take_item(sim, String(lo.id), i)
	var after := InvApi.loot(sim)
	var left := _units_in(after.grid) if not after.is_empty() else 0
	var moved := before - left
	if moved <= 0:
		say("No room in the pack", "warn")
	elif left > 0 and int(lo.revealed) >= lg.cells.size():
		say("Took %d. The rest does not fit: it stays here" % moved, "info")
	elif left > 0:
		say("Took %d. More is still being found" % moved, "info")
	else:
		say("Took it all", "info")
	_after_change()


func _units_in(g: Dictionary) -> int:
	var n := 0
	for c in g.cells:
		n += int(c.count)
	return n


func reload_pressed() -> void:
	if sim != null and sim.get("avatar") != null and sim.avatar.reload():
		_dirty = true


## After anything changed in the grids: look again at once.
func _after_change() -> void:
	_dirty = true
	if root != null:
		_poll()
		_dirty = false


# --------------------------------------------------------------------------------- the menu --

func _open_menu(g, index: int, at: Vector2) -> void:
	var c: Dictionary = g.grid.cells[index]
	var d: Dictionary = InvApi.item(String(c.item))
	var list: Array = []
	var lo := InvApi.loot(sim)
	if g.kind == "loot":
		list.append(["Take", "take", true, ""])
	else:
		var use := String(d.use)
		if use != "none":
			var verb: String = {"eat": "Eat", "drink": "Drink", "bandage": "Bandage a wound"}.get(use, "Use")
			var can: bool = use == "bandage"
			list.append([verb, "use", can, "Hunger and thirst come with the next step" if not can else ""])
		if loot_win.visible and not lo.is_empty() and int(lo.revealed) >= lo.grid.cells.size():
			list.append(["Put in the container", "put", true, ""])
		if stash_win.visible and String(d.res) != "":
			list.append(["Deposit in the stores", "deposit", true, ""])
	if int(c.count) >= 2:
		list.append(["Split in half", "split_half", true, ""])
		if int(c.count) > 2:
			list.append(["Split off 1", "split_one", true, ""])
	if int(d.w) != int(d.h):
		list.append(["Turn", "turn", true, ""])
	if g.kind == "pack":
		list.append(["Drop", "drop", true, ""])
	menu_for = {"grid": g, "index": index}
	menu.open_for(list, at, hud.size)


func menu_pick(id: String) -> void:
	var g = menu_for.get("grid")
	var index: int = int(menu_for.get("index", -1))
	menu.close()
	if g == null or not is_instance_valid(g) or index < 0 or index >= g.grid.cells.size():
		return
	var c: Dictionary = g.grid.cells[index]
	match id:
		"take", "put":
			quick_move_index(g, index)
		"use":
			use_index(index)
		"deposit":
			deposit_index(index)
		"split_half":
			_split(g, index, int(c.count) / 2)
		"split_one":
			_split(g, index, 1)
		"turn":
			var spot := _first_free_turned(g, index)
			if spot.x >= 0:
				InvApi.move(g.grid, index, g.grid, spot.x, spot.y, 1 - int(c.rot))
				InvApi.changed(sim)
			else:
				say("There is no room to turn it", "warn")
		"drop":
			var nm := _count_name({"item": c.item, "count": c.count})
			if InvApi.drop(sim, index, -1):
				say("Dropped %s" % nm, "info")
	_after_change()


func _split(g, index: int, n: int) -> void:
	var ni := InvApi.split(g.grid, index, maxi(n, 1))
	if ni < 0:
		say("There is no room to split it", "warn")
		return
	InvApi.changed(sim)
	g.glow(ni)


## The first place the stack at `index` fits turned over (its own cells are free for it; its own place first), (-1, -1) when none.
func _first_free_turned(g, index: int) -> Vector2i:
	var c: Dictionary = g.grid.cells[index]
	var sz: Vector2i = InvApi.size_of(String(c.item), 1 - int(c.rot))
	var occ := InvGeom.occupancy(g.grid, _size_fn, index)
	var spots: Array = [Vector2i(int(c.x), int(c.y))]
	for y in range(0, int(g.grid.h) - sz.y + 1):
		for x in range(0, int(g.grid.w) - sz.x + 1):
			spots.append(Vector2i(x, y))
	for s in spots:
		var ok: bool = s.x + sz.x <= int(g.grid.w) and s.y + sz.y <= int(g.grid.h)
		for yy in sz.y:
			for xx in sz.x:
				if occ.has(Vector2i(s.x + xx, s.y + yy)):
					ok = false
		if ok:
			return s
	return Vector2i(-1, -1)


# -------------------------------------------------------------------------------- tooltips --

## What a tooltip over a stack says: its name and count, what it is worth, what it does, and how to move it.
func tip_text(g, at: Vector2) -> String:
	if not drag.is_empty() or (menu != null and menu.visible):
		return ""
	var c: Vector2i = g.cell_at(at)
	if c.x < 0:
		return ""
	var i: int = InvGeom.index_at(g.grid, _size_fn, c)
	if i < 0:
		return ""
	if int(g.revealed) >= 0 and i >= int(g.revealed):
		return "Not found yet"
	return item_tip(g.grid.cells[i], g.kind)


func item_tip(c: Dictionary, kind: String = "pack") -> String:
	var d: Dictionary = InvApi.item(String(c.item))
	var n := int(c.count)
	var lines: Array = []
	lines.append(("%s x %d" % [d.name, n]) if n > 1 else String(d.name))
	if String(d.res) != "":
		var total: int = n * int(d.units)
		var store: String = {"ammo": "ammo", "food": "food", "water": "water", "meds": "medicine"}.get(String(d.res), String(d.res))
		lines.append("Worth %d %s at the stores" % [total, store])
	if String(d.desc) != "":
		lines.append(hud._wrap(String(d.desc), 40))
	if String(d.use) == "bandage":
		lines.append("Right-click: bandage a wound")
	lines.append("Drag it, or double-click it, to %s. Right-click: menu" % ("take it" if kind == "loot" else "move it"))
	return "\n".join(lines)


# --------------------------------------------------------------------------------- the chip --

func _chip_built() -> bool:
	return chip != null and is_instance_valid(chip)


## The pack's chip, in the strip of stores: a small pack and "9/32" (cells used of all); a click is the Tab key. Made when the HUD has made its strip.
func _build_chip() -> void:
	var calm = hud.get("_stores_calm")
	if calm == null or calm.strip == null:
		return
	var pair := HBoxContainer.new()
	pair.name = "InvChip"
	pair.add_theme_constant_override("separation", 4)
	pair.mouse_filter = Control.MOUSE_FILTER_STOP
	pair.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pair.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip_icon = ChipIcon.new()
	pair.add_child(chip_icon)
	chip_label = hud._label("0/32", Fonts.cond(600), 15, hud.INK)
	chip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_child(chip_label)
	pair.gui_input.connect(_chip_input)
	calm.strip.add_child(pair)
	chip = pair


func _chip_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		toggle()
		chip.accept_event()


func _refresh_chip(pk: Dictionary) -> void:
	if not _chip_built() or pk.is_empty():
		return
	var used := InvApi.used_cells(pk)
	var total := InvApi.cell_count(pk)
	var near_full := total > 0 and float(used) >= float(total) * 0.85
	var txt := "%d/%d" % [used, total]
	if Access.markers() and near_full:
		txt = "! " + txt
	if txt == _chip_text:
		return
	_chip_text = txt
	chip_label.text = txt
	chip_label.add_theme_color_override("font_color", hud.WARN if near_full else hud.INK)
	chip_icon.set("warn", near_full)
	chip_icon.queue_redraw()
	chip.tooltip_text = "Backpack: %d of %d cells used%s\nShells: %d. Food: %d. Water: %d. Medicine: %d\nKey: %s" % [used, total, " (nearly full)" if near_full else "", InvApi.units(pk, "ammo"), InvApi.units(pk, "food"), InvApi.units(pk, "water"), InvApi.units(pk, "meds"), ControlsTable.key_text("inv")]


class ChipIcon:
	extends Control
	var warn := false

	func _init() -> void:
		custom_minimum_size = Vector2(17, 17)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var ic := load("res://scripts/ui/inv_icons.gd")
		ic.draw_pack(self, Rect2(Vector2.ZERO, size), Color("#e8953a") if warn else Color("#d2a94e"))


# ------------------------------------------------------------------------------ the overlay --

## The held item, and the frame that says whether it fits where it is held: green with a tick (a plus for a stack it joins), red with a cross, over the grid; the stores panel green
## while it can be deposited there; a "Drop" tag in the world.
func _draw_overlay() -> void:
	if drag.is_empty():
		return
	var k := cell
	var t: Dictionary = drag.target
	var font := Fonts.cond(700, 0)
	var over := String(t.get("over", "world"))
	# the held item first (the frame over the place it would go is drawn over it, so a tick or a cross is never hidden by the picture)
	var sz: Vector2i = InvApi.size_of(String(drag.item), int(drag.rot))
	var grab: Vector2i = drag.grab
	var top: Vector2 = (drag.pos as Vector2) - (Vector2(float(grab.x), float(grab.y)) + Vector2(0.5, 0.5)) * k
	var ghost := Rect2(top, Vector2(float(sz.x), float(sz.y)) * k)
	overlay.draw_rect(ghost.grow(-2.0), Color(0.03, 0.06, 0.05, 0.9))
	InvIcons.draw_item(overlay, String(drag.item), ghost, int(drag.rot), k)
	if int(drag.count) > 1:
		var txt := str(int(drag.count))
		var fs := Access.scaled(15 if k >= 46.0 else 13)
		var at := Vector2(ghost.end.x - 4.0 - font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, ghost.end.y - 5.0)
		overlay.draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
		overlay.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	if over == "grid":
		var g = t.grid
		var gr: Rect2 = g.get_global_rect()
		var ok: bool = String(t.state) == InvGeom.FREE or String(t.state) == InvGeom.MERGE
		var fr := Rect2(gr.position + Vector2(g.PAD, g.PAD) + Vector2(float(t.x), float(t.y)) * k, Vector2(float(t.w), float(t.h)) * k)
		var area := Rect2(gr.position + Vector2(g.PAD, g.PAD), Vector2(float(g.cols()), float(g.rows())) * k)
		var vis := fr.intersection(area)
		if vis.size.x > 0.0 and vis.size.y > 0.0:
			_frame(vis, ok, "plus" if String(t.state) == InvGeom.MERGE else ("check" if ok else "cross"))
	elif over == "stash":
		_frame(stash_win.get_global_rect(), String(t.state) == InvGeom.FREE, "check" if String(t.state) == InvGeom.FREE else "cross")
	elif over == "world":
		var drop_ok: bool = String(t.state) == InvGeom.FREE
		var words := "Drop it here" if drop_ok else "Put it back"
		var wfs := Access.scaled(14)
		var wsz := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, wfs)
		var pill := Rect2(ghost.end + Vector2(6.0, -4.0), wsz + Vector2(14.0, 8.0))
		overlay.draw_rect(pill, Color(0.03, 0.06, 0.05, 0.9))
		overlay.draw_rect(pill, Color(BAD if drop_ok else ACCENT, 0.9), false, 1.5)
		overlay.draw_string(font, pill.position + Vector2(7.0, wsz.y * 0.8 + 3.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, wfs, INK)


## A frame over `r`: green with a tick (a plus for a stack it joins) when it fits, red with a cross when it does not: the shape says it as well as the colour, always, in a round badge at the corner.
func _frame(r: Rect2, ok: bool, shape: String) -> void:
	var col := OK if ok else BAD
	overlay.draw_rect(r, Color(col, 0.30))
	overlay.draw_rect(r, col, false, 3.0)
	var c := r.position + Vector2(14.0, 14.0)
	overlay.draw_circle(c, 11.0, Color("#10201a"))
	overlay.draw_circle(c, 9.5, col)
	CbShapes.mark(overlay, shape, c, 5.5, Color("#10201a"))
