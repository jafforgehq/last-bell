## EXPERIMENT (prison UI round 2): the TOP BAR and the OBJECTIVE TRACKER. Replaces the two plain text lines of the HUD.
## Pattern picked (godot-ui + hud-system): one CanvasLayer (11, under the board's 12), a dark PanelContainer built from containers (two HBox rows of "chips": icon, amount, small per-day net with an arrow),
## in the town's fonts and colours (ui/hud.gd, ui/fonts.gd); chips are updated at 5 Hz from the game's data (no polling in `_draw`, no per-frame text), only the warning pulse runs every frame.
## A chip is a PanelContainer; the hover text is our own panel (not the engine tooltip) so it can be styled, kept inside the window and staged by `--hover=food` for screenshots.
## Rows: managed base = clock, seven resources (stock/cap, net a day, amber under 3 days, red under 1 day or empty) / people, morale, stage, next attack, fence. Clear phase = zones, party hearts, dead left /
## ammo, meds, next zone. Raid = pack fullness, ammo, meds, target need, exits. A click on a resource opens the needs board.
## The tracker (top right under the bar, key O to fold) lists the objective chain with check boxes (`objectives()`), and `focus()` names the place the world arrow points at (prison_tags.gd).
extends RefCounted

const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Icons := preload("res://scripts/prison/prison_icons.gd")
const Base := preload("res://scripts/prison/prison_base.gd")
const PHud := preload("res://scripts/prison/prison_hud.gd")
const UI := preload("res://scripts/prison/prison_ui.gd")    # COUNTERS: a stock that changes counts to its new value
const Inventory := preload("res://scripts/sim/inventory.gd")

const RES := ["food", "water", "ammo", "meds", "scrap", "parts", "fuel"]
const RES_NAME := {"food": "Food", "water": "Water", "ammo": "Ammo", "meds": "Meds", "scrap": "Scrap", "parts": "Parts", "fuel": "Fuel"}
const RES_COL := {"food": Color("#e08a5a"), "water": Color("#6fb4e8"), "ammo": Color("#d9bf6a"), "meds": Color("#f27f72"), "scrap": Color("#b8bcc0"), "parts": Color("#8fd0a8"), "fuel": Color("#e8953a")}
const RES_USE := {
	"ammo": "Spent by your gun and by the guards at night. A mechanic at the workbench turns 1 scrap into 2 rounds.",
	"meds": "Treats bites and revives people. An infirmary with a medic makes a little from scrap.",
	"scrap": "Pays for projects and fence repairs. A mechanic turns it into ammo.",
	"parts": "Needed by the pump, generator and radio projects. Found in raids on garages.",
	"fuel": "Burned by the generator once it is built (1 a day). Found in raids on petrol stations.",
}
## The last line of a chip's hover text: what to do when it runs low.
const RES_LOW := {
	"food": "When low: build or staff the garden, or raid a shop or house for food.",
	"water": "When low: build the well or pump, or raid for bottled water.",
	"ammo": "When low: put a mechanic on the workbench (scrap to rounds) or raid a police station.",
	"meds": "When low: raid a pharmacy or hospital, or staff the infirmary.",
	"scrap": "When low: raid industrial places and strip what you find.",
	"parts": "When low: raid a garage.",
	"fuel": "When low: raid a petrol station before the generator stops.",
	"people": "When over the beds: build a dormitory, or morale falls.",
	"morale": "When low: fix hunger and thirst, tidy the base, build comforts; people leave below the limit.",
	"noise": "When loud: stop shooting, use the knife (F) or move away.",
}
const ROW_ECON := ["clock", "speed", "food", "water", "ammo", "meds", "scrap", "parts", "fuel"]
const ROW_ECON2 := ["people", "morale", "stage", "attack", "fence", "noise", "convoy"]
const ROW_CLEAR := ["clock", "zones", "party", "dead"]
const ROW_CLEAR2 := ["c_ammo", "c_meds", "nextzone", "noise"]
const ROW_RAID := ["clock", "dusk", "weather", "pack", "r_ammo", "r_meds", "need", "exits", "noise"]
const DIM := Color("#8d927f")

var game
var layer: CanvasLayer
var root: Control
var plate: PanelContainer
var row1: HBoxContainer
var row2: HBoxContainer
var chips := {}
var tip: PanelContainer
var tip_label: Label
var tracker: PanelContainer
var tr_head: Label
var tr_body: VBoxContainer
var tr_folded := false
var tr_auto := false    # folded by the fight rule, not by the player
var hover := ""
var _t := 0.0
var _acc := 99.0
var _sig := ""
var _clock_icon: IconBox
var _clock_main: Label
var _clock_sub: Label
var _mood := []    # [time, morale] samples for the trend arrow
var _fight_t := 0.0
var _names := false
var _rep := {}    # COUNTERS: the last daily report, for the stock chips redrawn while they count


class IconBox extends Control:
	const I := preload("res://scripts/prison/prison_icons.gd")
	var icon := ""
	var col := Color.WHITE
	var sz := 18.0

	func _init(s: float = 18.0) -> void:
		sz = s
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_icon(i: String, c: Color) -> void:
		if i != icon or c != col:
			icon = i
			col = c
			queue_redraw()

	func _draw() -> void:
		I.draw(self, icon, size / 2.0, sz * 0.92, col)


class PipBox extends Control:
	const I := preload("res://scripts/prison/prison_icons.gd")
	var vals: Array = []    # per person: hp fraction, or -1 for a person who is down

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(16, 18)

	func set_vals(v: Array) -> void:
		if v != vals:
			vals = v
			custom_minimum_size = Vector2(maxf(16.0, 19.0 * float(v.size())), 18)
			queue_redraw()

	func _draw() -> void:
		for i in vals.size():
			var f := float(vals[i])
			var col := Color("#4a4f46") if f < 0.0 else (Color("#e0584a") if f < 0.34 else (Color("#e8953a") if f < 0.67 else Color("#8fb85a")))
			I.draw(self, "heart", Vector2(9.5 + 19.0 * float(i), 9.0), 15.0, col)


func _init(g) -> void:
	game = g
	layer = CanvasLayer.new()
	layer.layer = 11
	g.add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	plate = PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_STOP
	plate.add_theme_stylebox_override("panel", _box(Color(0.03, 0.05, 0.04, 0.9), Hud.LINE2, 6, 7))
	plate.position = Vector2(8, 6)
	root.add_child(plate)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	plate.add_child(vb)
	row1 = _row()
	row2 = _row()
	vb.add_child(row1)
	vb.add_child(row2)
	_build_clock()
	_chip("speed", row1, 24, false)    # TIME hook
	_chip("dusk", row1, 60, false)
	for k in ["food", "water", "ammo", "meds", "scrap", "parts", "fuel"]:
		_chip(k, row1, 46, true)
	for k in ["zones", "party", "dead"]:
		_chip(k, row1, 40, false)
	for k in ["weather", "pack", "r_ammo", "r_meds", "need", "exits"]:
		_chip(k, row1, 40, false)
	for k in ["people", "morale", "stage", "attack", "fence", "convoy"]:
		_chip(k, row2, 40, false)
	for k in ["c_ammo", "c_meds", "nextzone"]:
		_chip(k, row2, 40, false)
	_chip("noise", row2, 40, false)    # NOISE hook
	var pips := PipBox.new()
	chips["party"].main.get_parent().add_child(pips)
	chips["party"].main.get_parent().move_child(pips, 1)
	chips["party"]["pips"] = pips
	chips["need"].pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for k in RES:
		chips[k].pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_tracker()
	tip = PanelContainer.new()
	tip.visible = false
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_theme_stylebox_override("panel", _box(Color(0.04, 0.06, 0.05, 0.97), Hud.LINE2, 9, 5))
	tip_label = _lab("", 14, Hud.INK2)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size.x = 300
	tip.add_child(tip_label)
	root.add_child(tip)


# ------------------------------------------------------------------------------------ builders --

func _box(bg: Color, line: Color, margin: int, radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _lab(text: String, size: int, col: Color, cond := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.cond(700) if cond else Fonts.sans(500))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	return h


func _build_clock() -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(Color(0.1, 0.13, 0.11, 0.9), Hud.LINE, 4, 5))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	pc.add_child(hb)
	_clock_icon = IconBox.new(22)
	hb.add_child(_clock_icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -3)
	hb.add_child(vb)
	_clock_main = _lab("08:00", 17, Hud.INK)
	_clock_sub = _lab("Day 1", 12, DIM)
	vb.add_child(_clock_main)
	vb.add_child(_clock_sub)
	row1.add_child(pc)
	chips["clock"] = {"pc": pc}


func _chip(key: String, row: HBoxContainer, min_w: float, clickable: bool) -> void:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.add_theme_stylebox_override("panel", _box(Color(0.1, 0.13, 0.11, 0.9), Hud.LINE, 4, 5))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	pc.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	vb.add_child(hb)
	var icon := IconBox.new(18)
	hb.add_child(icon)
	var main := _lab("", 15, Hud.INK)
	main.custom_minimum_size.x = min_w
	hb.add_child(main)
	var arrow := IconBox.new(9)
	hb.add_child(arrow)
	var sub := _lab("", 13, DIM)
	hb.add_child(sub)
	var meter := ProgressBar.new()
	meter.show_percentage = false
	meter.max_value = 1.0
	meter.custom_minimum_size = Vector2(0, 4)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.5), Hud.LINE, 0, 2))
	meter.visible = false
	vb.add_child(meter)
	row.add_child(pc)
	pc.mouse_entered.connect(func():
		hover = key
		_show_tip())
	pc.mouse_exited.connect(func():
		if hover == key:
			hover = ""
			tip.visible = false)
	if clickable:
		pc.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_open_needs())
	chips[key] = {"pc": pc, "icon": icon, "main": main, "arrow": arrow, "sub": sub, "meter": meter, "state": "ok", "tip": ""}


func _open_needs() -> void:
	if game.phase == "managed" and game.mode == "base" and not game.busy:
		game.board.open("needs")


func _build_tracker() -> void:
	tracker = PanelContainer.new()
	tracker.mouse_filter = Control.MOUSE_FILTER_STOP
	tracker.add_theme_stylebox_override("panel", _box(Color(0.03, 0.05, 0.04, 0.82), Hud.LINE2, 8, 6))
	root.add_child(tracker)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	tracker.add_child(vb)
	tr_head = _lab("OBJECTIVES  [O]", 14, Hud.ACCENT)
	tr_head.mouse_filter = Control.MOUSE_FILTER_STOP
	tr_head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tr_head.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			tr_folded = not tr_folded)
	vb.add_child(tr_head)
	tr_body = VBoxContainer.new()
	tr_body.add_theme_constant_override("separation", 3)
	vb.add_child(tr_body)


# --------------------------------------------------------------------------------- input / frame --

func key(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode == KEY_O and not game.board.is_open():
		tr_folded = not tr_folded
		return true
	return false


## The mouse is over the bar or the tracker: the gun must not fire through it.
func blocks_fire() -> bool:
	var m: Vector2 = game.get_viewport().get_mouse_position()
	return Rect2(plate.position, plate.size).grow(4.0).has_point(m) or (tracker.visible and Rect2(tracker.position, tracker.size).grow(4.0).has_point(m))


## A window or a card is up over the game: the objectives step out of its way.
func _modal() -> bool:
	return (game.board != null and game.board.is_open()) or (game.loadout != null and game.loadout.is_open) or (game.squad != null and game.squad.open) or (game.arc != null and (game.arc.story.card_open() or game.arc.endings.is_open()))


## The y under the tracker, where the toasts begin.
func toast_y() -> float:
	return (tracker.position.y + tracker.size.y + 8.0) if tracker.visible else plate.position.y + plate.size.y + 8.0


func frame(dt: float) -> void:
	_t += dt
	_acc += dt
	var v: Vector2 = game._vp()
	if game.args.has("stores") and game.frames == 4:    # staging: --stores=food=2,water=0 sets those stocks
		for kv in String(game.args.stores).split(","):
			var q := kv.split("=")
			if q.size() == 2:
				game.stores[q[0]] = float(q[1])
	if game.args.has("hover") and game.frames == 20:
		hover = String(game.args.hover)
		_show_tip()
	if _acc >= 0.2:
		_acc = 0.0
		_refresh()
	elif UI.ticking() and game.phase == "managed" and game.mode == "base" and not _rep.is_empty():    # COUNTERS: every frame while a number counts
		for r in RES:
			_res_chip(r, _rep)
	# the warning pulse
	for k in chips:
		var c: Dictionary = chips[k]
		if not c.has("state"):
			continue
		var st := String(c.state)
		var a := 1.0
		if st == "danger":
			a = 0.72 + 0.28 * (0.5 + 0.5 * sin(_t * 6.5))
		elif st == "warn":
			a = 0.86 + 0.14 * (0.5 + 0.5 * sin(_t * 3.0))
		(c.pc as Control).modulate.a = a
	plate.reset_size()
	plate.position = Vector2(8, 6)
	var bw := plate.size.x
	tracker.visible = not game.busy and not _modal()    # (hidden under a window: the loadout, the Base screen, a card, the orders)
	plate.visible = not game.busy
	tracker.reset_size()
	var tw := 316.0
	tracker.custom_minimum_size.x = tw
	tracker.size.x = tw
	var ty := plate.position.y + plate.size.y + 8.0
	# on a narrow window the tracker goes under the bar's right end; the bar is never wider than the window
	tracker.position = Vector2(v.x - tw - 8.0, ty)
	if bw > v.x - 16.0:
		plate.size.x = v.x - 16.0
	if tip.visible:
		_place_tip()


func _fighting() -> bool:
	if game.siege.attacking:
		return true
	if game.mode == "base" and game.phase == "clear":
		return _fight_t > 0.0
	return false


func fighting() -> bool:
	return _fighting()


# --------------------------------------------------------------------------------------- refresh --

func _refresh() -> void:
	if game.run == null:
		return
	_names = game._vp().x >= 1250.0
	var mode: String = game.mode
	var managed: bool = game.phase == "managed" and mode == "base"
	var clear: bool = game.phase == "clear" and mode == "base"
	var show: Array = ROW_RAID if mode == "raid" else (ROW_ECON + ROW_ECON2 if managed else ROW_CLEAR + ROW_CLEAR2)
	for k in chips:
		(chips[k].pc as Control).visible = show.has(k)
	row2.visible = mode != "raid"
	_clock()
	_time_chips()
	var rep: Dictionary = game.econ.daily_report() if game.econ != null else {}
	_rep = rep
	if managed:
		for r in RES:
			_res_chip(r, rep)
		_econ_row2(rep)
	elif clear:
		_clear_chips()
	else:
		_raid_chips(rep)
	_noise_chip()
	_mood_sample()
	_tracker(managed or clear or mode == "raid")
	if hover != "" and tip.visible:
		_show_tip()


func _clock() -> void:
	var tod: float = game.raidx.hour() if game.mode == "raid" and game.raidx != null else game.tod    # (a raid runs on the hour the map chose)
	var night: bool = game._night_of(tod) > 0.5
	var period := "night" if night else ("morning" if tod < 12.0 else ("afternoon" if tod < 17.0 else "evening"))
	_clock_icon.set_icon("moon" if night else "sun", Color("#9fb4e8") if night else Hud.ACCENT)
	_clock_main.text = "%02d:%02d" % [int(tod), int(fposmod(tod, 1.0) * 60.0)]
	if game.phase == "managed":
		var arc = game.arc    # ARC hook: "Day 12 of 30", the convoy's day in gold
		var dn: int = game.econ.day
		var on_cd: bool = arc != null and dn == arc.convoy_day()
		_clock_sub.text = ("Day %d of %d, %s" % [dn, arc.days(), "CONVOY" if on_cd else period]) if arc != null else "Day %d, %s" % [dn, period]
		_clock_sub.add_theme_color_override("font_color", Hud.ACCENT if on_cd else DIM)
	else:
		_clock_sub.text = "Clear phase"


## TIME hook: the speed chip in the managed base, the dusk chip in a raid.
func _time_chips() -> void:
	_put("speed", "sun", Hud.ACCENT if game.speed > 1 else DIM, "%dx" % game.speed, "F1-F3", DIM, "", "ok", "Time speed: F1, F2, F3 (or - and =) run the base at 1x, 2x, 3x. It drops to 1x when a card opens, at night attacks, in raids.")
	var ds: Dictionary = game.dusk_state()
	(chips["dusk"].pc as Control).visible = not ds.is_empty() and game.mode == "raid"
	if ds.is_empty():
		return
	if bool(ds.night):
		_put("dusk", "moon", Hud.DANGER_TEXT, "NIGHT", "the dead wake", Hud.DANGER_TEXT, "", "danger", "It is dark: the dead hear from farther. Head for an exit.")
	else:
		var s := int(ds.secs)
		_put("dusk", "moon", Hud.WARN, "Dusk %d:%02d" % [s / 60, s % 60], "", DIM, "", "warn", "Night falls soon and the dead wake from farther. Wrap up and head for an exit.", 1.0 - float(ds.secs) / 45.0, Hud.WARN)


func _state_style(st: String) -> StyleBoxFlat:
	var line := Hud.LINE
	var bg := Color(0.1, 0.13, 0.11, 0.9)
	if st == "warn":
		line = Hud.WARN
		bg = Color(0.2, 0.15, 0.07, 0.92)
	elif st == "danger":
		line = Hud.DANGER
		bg = Color(0.25, 0.08, 0.07, 0.94)
	return _box(bg, line, 4, 5)


## Sets what a chip shows. `state`: ok, warn or danger (plate colour and pulse). `meter` < 0 hides the thin bar.
func _put(key: String, icon: String, icol: Color, main: String, sub := "", sub_col := DIM, arrow := "", state := "ok", tip_text := "", meter := -1.0, mcol := Hud.OK) -> void:
	var c: Dictionary = chips[key]
	(c.icon as IconBox).set_icon(icon, icol)
	(c.main as Label).text = main
	var main_col := Hud.INK
	if state == "warn":
		main_col = Hud.WARN
	elif state == "danger":
		main_col = Hud.DANGER_TEXT
	(c.main as Label).add_theme_color_override("font_color", main_col)
	(c.sub as Label).text = sub
	(c.sub as Label).add_theme_color_override("font_color", sub_col)
	(c.arrow as IconBox).visible = arrow != ""
	(c.arrow as IconBox).set_icon(arrow, sub_col)
	if String(c.state) != state or not c.has("styled"):
		c.state = state
		c["styled"] = true
		(c.pc as PanelContainer).add_theme_stylebox_override("panel", _state_style(state))
	c.tip = tip_text
	var m := c.meter as ProgressBar
	m.visible = meter >= 0.0
	if meter >= 0.0:
		m.value = clampf(meter, 0.0, 1.0)
		m.add_theme_stylebox_override("fill", _box(mcol, mcol, 0, 2))


func _res_chip(r: String, rep: Dictionary) -> void:
	var stock: float = float(game.stores.get(r, 0.0))
	var caps: Dictionary = game.econ.caps()
	var cap := int(caps.get(r, 0))
	var low: Dictionary = game.econ.cfg.needs.low
	var crit: float = float(game.econ.cfg.needs.critical_days)
	var state := "ok"
	var sub := ""
	var arrow := ""
	var sub_col := DIM
	var res: Dictionary = (rep.res as Dictionary).get(r, {}) if rep.has("res") else {}
	var days := -1.0
	if not res.is_empty():
		var net := float(res.net)
		days = float(res.days)
		sub = "%+d" % roundi(net)
		arrow = "up" if net > 0.4 else ("down" if net < -0.4 else "flat")
		sub_col = Hud.OK if net > 0.4 else (Hud.DANGER_TEXT if net < -0.4 else DIM)
		if net > -0.4 and net < 0.4:
			sub = "0"
		if days >= 0.0 and days < 1.0:
			state = "danger"
		elif days >= 0.0 and days < crit:
			state = "warn"
	if stock < 0.5 and (not res.is_empty() and float(res.cons) > 0.0 or low.has(r) or r == "ammo" or r == "meds"):
		state = "danger"
	elif state == "ok" and low.has(r) and stock < float(low[r]):
		state = "warn"
	var amt := "%d/%d" % [int(round(UI.tick("hud." + r, float(int(stock))))), cap]
	if _names:
		amt = "%s %s" % [RES_NAME[r], amt]
	(chips[r].main as Label).custom_minimum_size.x = 46 if not _names else 92
	_put(r, r, RES_COL[r], amt, sub, sub_col, arrow, state, _res_tip(r, rep, stock, cap, days), -1.0)


func _res_tip(r: String, rep: Dictionary, stock: float, cap: int, days: float) -> String:
	var econ = game.econ
	var t := "%s  %d / %d" % [RES_NAME[r], int(stock), cap]
	if rep.has("res") and (rep.res as Dictionary).has(r):
		var e: Dictionary = rep.res[r]
		var b := String(econ.cfg.production_building.get(r, ""))
		if b != "":
			var role := String(econ.cfg.production_role.get(r, ""))
			t += "\nMade: +%d a day (%s tier %d, %d on the %s job)" % [roundi(float(e.prod)), b, econ.tier(b), econ.workers(role), role]
		elif r == "fuel":
			t += "\nMade: nothing. Fuel only comes from raids on petrol stations."
		var per := float(econ.cfg.per_person.get(r, 0.0))
		if r == "fuel":
			t += "\nUsed: -%d a day by the generator%s" % [roundi(float(e.cons)), "" if econ.tier("power") >= 1 else " (not built yet)"]
		else:
			t += "\nUsed: -%d a day (%d people, %s each)" % [roundi(float(e.cons)), econ.people(), str(per)]
		if r == "food":
			t += "\nSpoils: about %d a day" % roundi(maxf(0.0, float(e.prod) - float(e.cons) - float(e.net)))
		t += "\nNet: %+d a day. %s" % [roundi(float(e.net)), ("Out now." if stock < 0.5 else "Lasts %.1f days." % days) if days >= 0.0 else "Steady."]
		if r == "food" or r == "water":
			t += "\nOver the cap is lost."
	else:
		t += "\n" + String(RES_USE.get(r, ""))
	var place := String(econ.cfg.fixes.get(r, ""))
	if place != "":
		t += "\nFind more: raid a %s.   Click: needs board." % econ.place_word(place)
	return t + "\n" + String(RES_LOW.get(r, ""))


func _econ_row2(rep: Dictionary) -> void:
	var econ = game.econ
	var bd: Dictionary = rep.beds
	var over: bool = int(bd.free) < 0
	_put("people", "people", Hud.INFO, "%d/%d" % [int(bd.used), int(bd.cap)], "beds", DIM, "", "danger" if over else "ok",
		"People %d, beds %d.%s" % [int(bd.used), int(bd.cap), "\nMore people than beds costs morale every day: build a dormitory." if over else "\nEveryone eats and drinks 1 a day."] + "\n" + String(RES_LOW.people))
	var m := float(rep.morale)
	var trend := _trend()
	var face := "face_good" if m >= 50.0 else ("face_mid" if m >= 25.0 else "face_bad")
	var mcol := Hud.OK if m >= 50.0 else (Hud.WARN if m >= 25.0 else Hud.DANGER)
	var reasons: Array = game.board.morale_reasons(rep)
	var rt := "Morale %d / 100 (people leave below %d)" % [int(m), int(econ.cfg.morale.leave_below)]
	for q in reasons:
		rt += "\n%s %s" % ["+" if q[1] else "-", q[0]]
	_put("morale", face, mcol, "%d" % int(m), "morale", DIM, "up" if trend > 0.6 else ("down" if trend < -0.6 else "flat"), "danger" if m < 25.0 else ("warn" if m < 40.0 else "ok"), rt + "\n" + String(RES_LOW.morale), m / 100.0, mcol)
	# the stage and the way to the next one
	var names: Array = ["Camp"]
	for s in econ.cfg.stages:
		names.append(String(s.name))
	var i := names.find(econ.stage())
	var nx := String(names[i + 1]) if i + 1 < names.size() else ""
	var frac := 1.0
	var gtxt := ""
	if nx != "":
		var total := 0
		var built := 0
		for s in econ.cfg.stages:
			if String(s.name) == nx:
				for b in s.tiers:
					for t in range(1, int(s.tiers[b]) + 1):
						total += 1
						if econ.tier(String(b)) >= t:
							built += 1
		frac = float(built) / maxf(1.0, float(total))
		var goal: Array = econ.goal()
		var gn: Array = []
		for id in goal:
			gn.append(String(econ.defs[id].name))
		gtxt = "\nTo reach %s still build: %s." % [nx, ", ".join(gn)]
	_put("stage", "star", Hud.ACCENT, String(econ.stage()), ("next: " + nx) if nx != "" else "top stage", DIM, "", "ok", "Prison stage: %s.%s" % [econ.stage(), gtxt], frac, Hud.ACCENT)
	_attack_chip()
	_fence_chip()
	_convoy_chip()


func _trend() -> float:
	if _mood.size() < 2:
		return 0.0
	return float(_mood[-1][1]) - float(_mood[0][1])


func _mood_sample() -> void:
	if game.econ == null:
		return
	var now := _t
	if _mood.is_empty() or now - float(_mood[-1][0]) >= 3.0:
		_mood.append([now, game.econ.morale])
		while _mood.size() > 8:
			_mood.pop_front()


## NOISE hook: the chip that says how loud it is here (quiet, loud, very loud), and a horde or a car alarm when there is one.
func _noise_chip() -> void:
	if game.noise == null or not chips.has("noise"):
		return
	var want: Control = row1 if game.mode == "raid" else row2    # (the raid has one row)
	var pc: Control = chips.noise.pc
	if pc.get_parent() != want:
		pc.get_parent().remove_child(pc)
		want.add_child(pc)
	var c: Array = game.noise.chip()
	var st := String(c[2])
	_put("noise", "bell", Hud.DANGER_TEXT if st == "danger" else (Hud.WARN if st == "warn" else Hud.INK2), String(c[0]), String(c[1]), Hud.DANGER_TEXT if st == "danger" else (Hud.WARN if st == "warn" else DIM), "", st, String(c[3]) + "\n" + String(RES_LOW.noise), float(c[4]), Hud.DANGER if st == "danger" else (Hud.WARN if st == "warn" else Hud.OK))


func _attack_chip() -> void:
	var sg = game.siege
	if sg.attacking:
		var hz: String = game.noise.horde_text()    # NOISE hook: "Horde from the east in 40 s"
		_put("attack", "bell", Hud.DANGER_TEXT, "ATTACK", hz if hz != "" else "night %d  %d left" % [sg.night, sg._alive_wave()], Hud.DANGER_TEXT, "", "danger", "The dead are at the walls. Guards shoot from the towers; hold E at a broken wall to mend it.")
		return
	var secs: float = maxf(0.0, (sg.NIGHT_H + 24.0 * float(sg.nights_started) - sg.abs_h) * sg.SEC_PER_HOUR / float(game.speed))
	var st := "warn" if secs < 90.0 else "ok"
	var hn: int = sg.nights_started + 1
	var horde: bool = game.arc.is_horde_night(hn)
	if not horde:
		st = "ok"
	var days: int = game.arc.next_horde_night(hn) - hn
	var head := "Horde tonight" if horde else ("Horde in %d day%s" % [days, "" if days == 1 else "s"] if days <= 5 else "Quiet")
	var hrs: float = maxf(0.0, sg.NIGHT_H + 24.0 * float(sg.nights_started) - sg.abs_h)    # game hours to the horde (the chip speaks the clock's time, not real seconds)
	var when := ("at %02d:00" % int(sg.NIGHT_H)) if hrs >= 1.0 else "in %d min" % ceili(hrs * 60.0)
	var why := "The dead followed you in from the clear: they come for the fence on the first night. " if hn == 1 else ""
	_put("attack", "bell", Hud.WARN if st == "warn" else Hud.INK2, head, when if horde else "night %d" % game.arc.next_horde_night(hn), Hud.WARN if st == "warn" else DIM, "", st,
		why + "A horde comes at %02d:00 tonight. Mend the fence and keep ammo in the stores before it." % int(sg.NIGHT_H) if horde else "Nobody breaks the fence tonight. The next horde comes on night %d: use the quiet days to raid and build." % game.arc.next_horde_night(hn))
	(chips["attack"].main as Label).custom_minimum_size.x = 100


func _convoy_chip() -> void:    # ARC hook
	var arc = game.arc
	if arc == null or not arc.started:
		(chips["convoy"].pc as Control).visible = false
		return
	var c: Dictionary = arc.chip()
	_put("convoy", "exit", Hud.ACCENT if String(c.state) == "ok" else (Hud.WARN if String(c.state) == "warn" else Hud.DANGER_TEXT), String(c.main), String(c.sub), DIM, "", String(c.state), String(c.tip), float(c.meter), Hud.ACCENT)
	(chips["convoy"].main as Label).custom_minimum_size.x = 78


func _fence_chip() -> void:
	var sg = game.siege
	var w: Dictionary = sg.weakest()
	var f: float = float(w.hp) / float(w.max)
	var st := "danger" if f < 0.3 else ("warn" if f < 0.6 else "ok")
	var col := Hud.DANGER_TEXT if st == "danger" else (Hud.WARN if st == "warn" else Hud.OK)
	var up := 0    # one format day and night: how many parts still stand, then the weakest one when it is hurt
	for sgm in sg.segs:
		if float(sgm.hp) > 0.0:
			up += 1
	var main := "Fence %d/%d" % [up, sg.segs.size()]
	var sub: String = "intact" if f >= 0.97 else "%s %d%%" % [String(w.name), int(f * 100.0)]
	_put("fence", "fence", col, main, sub, DIM, "", st,
		"Weakest fence part: %s at %d%% (%s).\nMend with scrap: hold E at the damaged wall, or a mechanic does it." % [String(w.name), int(f * 100.0), sg.state_of(w)], f, col)


# ------------------------------------------------------------------------------ clear and raid --

func _clear_chips() -> void:
	var n: int = game._cleared_n()
	var total: int = Base.ZONES.size()
	_put("zones", "zones", Hud.OK, "Cleared %d/%d" % [n, total], "", DIM, "", "ok", "Zones cleared: %d of %d. A zone is clear when no dead are left in it. Nobody joins you for it: people come from rescues on raids." % [n, total], float(n) / float(total), Hud.OK)
	(chips["zones"].main as Label).custom_minimum_size.x = 92
	var vals: Array = []
	var names: Array = []
	for m in game.crew.members:
		if m.def.has("ally"):
			vals.append(-1.0 if m.state == "downed" else clampf(float(m.hp) / 45.0, 0.0, 1.0))
			names.append("%s %s" % [String(m.def.name), "DOWN" if m.state == "downed" else str(int(m.hp))])
	(chips["party"].pips as PipBox).set_vals(vals)
	_put("party", "", Hud.INK, "", "", DIM, "", "ok", "Your party: " + ", ".join(names) + ".\nA downed friend can be revived: hold E beside them (1 med).")
	(chips["party"].icon as IconBox).visible = false
	(chips["party"].main as Label).custom_minimum_size.x = 0
	var left := 0
	for zi in Base.ZONES.size():
		if not game.zone_done[zi]:
			left += game._dead_in_zone(zi).size()
	_put("dead", "target", Hud.DANGER_TEXT, "%d" % left, "dead left", DIM, "", "ok", "Dead still standing in the zones that are not clear.")
	for r in ["ammo", "meds"]:
		if r == "ammo":
			var sp: int = PHud.reserve(game, game.run.avatar_p)    # shots in the pack: the gun readout's unit
			_put("c_ammo", "ammo", RES_COL.ammo, "%d" % sp, "spare", DIM, "", "danger" if sp <= 0 else ("warn" if sp < 12 else "ok"), "Shots in your backpack, not counting the gun's magazine. The stores hold %d units of ammo.\n%s" % [int(game.stores.get("ammo", 0.0)), RES_USE.ammo] + "\n" + String(RES_LOW.ammo))
			continue
		var low: Dictionary = game.econ.cfg.needs.low
		var stock := float(game.stores.get(r, 0.0))
		var st := "danger" if stock < 0.5 else ("warn" if stock < float(low.get(r, 0.0)) else "ok")
		_put("c_" + r, r, RES_COL[r], "%d" % int(stock), RES_NAME[r].to_lower(), DIM, "", st, "%s in the stores: %d.\n%s" % [RES_NAME[r], int(stock), RES_USE[r]] + "\n" + String(RES_LOW[r]))
	var nz := _next_zone()
	_put("nextzone", "target", Hud.ACCENT, ("Next: " + String(Base.ZONES[nz].name)) if nz >= 0 else "Secure the gate", "", DIM, "", "ok", "The pulsing marker in the world points there.")
	(chips["nextzone"].main as Label).custom_minimum_size.x = 100


func _raid_chips(_rep: Dictionary) -> void:
	var grid: Dictionary = game.pack.grid
	var used := int(Inventory.used_cells(grid))
	var total := int(Inventory.cell_count(grid))
	var full := float(used) / maxf(1.0, float(total))
	var st := "danger" if full >= 0.95 else ("warn" if full >= 0.8 else "ok")
	_put("pack", "pack", Hud.INK2, "%d/%d" % [used, total], "pack", DIM, "", st, "Backpack cells used: %d of %d.%s\nI opens it; loot that does not fit stays behind." % [used, total, "  It is nearly full." if st != "ok" else ""], full, Hud.DANGER if st == "danger" else (Hud.WARN if st == "warn" else Hud.INFO))
	var am := PHud.reserve(game, game.run.avatar_p)    # shots, the gun readout's unit
	_put("r_ammo", "ammo", RES_COL.ammo, "%d" % am, "spare", DIM, "", "danger" if am <= 0 else ("warn" if am < 12 else "ok"), "Shots in the backpack, not counting the gun's magazine. R reloads.\n" + String(RES_LOW.ammo))
	var md := int(Inventory.units(grid, "meds"))
	_put("r_meds", "meds", RES_COL.meds, "%d" % md, "meds", DIM, "", "ok", "Medicine carried. Unspent meds go home with you.\n" + String(RES_LOW.meds))
	var nd: Dictionary = game.econ.needs() if game.econ != null else {}
	var hint: String = game.loot.hint()
	if nd.is_empty():
		_put("need", "target", Hud.OK, "No pressing need", "", DIM, "", "ok", hint if hint != "" else "Take what you can carry.")
	else:
		var have := int(Inventory.units(grid, String(nd.res)))
		_put("need", String(nd.res) if RES.has(String(nd.res)) else "target", RES_COL.get(String(nd.res), Hud.ACCENT), "Need %s" % String(nd.res), "carrying %d" % have, DIM, "", "warn", ("%s\n%s" % [String(nd.get("reason", "")), hint]).strip_edges())
	(chips["need"].main as Label).custom_minimum_size.x = 70
	var ex: int = game.exits.size()
	_put("exits", "exit", Hud.OK, "Exits %d" % ex, "", DIM, "", "ok", "Reach a green EXTRACTION ring and hold still to go home with the pack. The first one is where the truck dropped you.\nV: retreat. The whole squad runs to the nearest ring and an arrow shows you the way.")
	var rx = game.raidx    # RAID EXTRAS: today's weather (and the hour the map chose)
	var wid := String(rx.weather)
	var wcfg: Dictionary = rx.weather_cfg(wid)
	var rnight: bool = game._night_of(rx.hour()) > 0.5
	_put("weather", {"rain": "rain", "fog": "fog"}.get(wid, "moon" if rnight else "sun"), Color("#9fc4e8") if wid == "rain" else (Color("#c9d0d2") if wid == "fog" else (Color("#9fb4e8") if rnight else Hud.ACCENT)), String(wcfg.get("name", "Clear")), "night" if rnight else "day", DIM, "", "warn" if wid == "fog" else "ok", "Weather today: %s. %s" % [String(wcfg.get("name", "Clear")), String(wcfg.get("note", ""))])
	(chips["weather"].main as Label).custom_minimum_size.x = 44


# --------------------------------------------------------------------------------------- hover --

func _show_tip() -> void:
	if hover == "" or not chips.has(hover):
		tip.visible = false
		return
	var t := String(chips[hover].get("tip", ""))
	if t == "":
		tip.visible = false
		return
	tip_label.text = t
	tip.visible = true
	tip.reset_size()
	_place_tip()


func _place_tip() -> void:
	if hover == "" or not chips.has(hover):
		return
	var pc: Control = chips[hover].pc
	var v: Vector2 = game._vp()
	tip.size = tip.get_combined_minimum_size()
	var p := Vector2(pc.global_position.x, pc.global_position.y + pc.size.y + 6.0)
	p.x = clampf(p.x, 6.0, maxf(6.0, v.x - tip.size.x - 6.0))
	tip.position = p


# ------------------------------------------------------------------------------------ objectives --

func _next_zone() -> int:
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var best := -1
	var bd := 1.0e9
	for zi in Base.ZONES.size():
		if game.zone_done[zi]:
			continue
		var d := me.distance_to(Vector2(Base.ZONES[zi].rel))
		if d < bd:
			bd = d
			best = zi
	return best


func _cost_text(id: String) -> String:
	var out: Array = []
	var cost: Dictionary = game.econ.defs[id].cost
	for k in cost:
		out.append("%s %d" % [k, int(cost[k])])
	return ", ".join(out)


## [{t, done}] the objective chain for what the player is doing now (at most five lines).
func objectives() -> Array:
	var out: Array = []
	var econ = game.econ
	if game.mode == "raid":
		var nd: Dictionary = econ.needs()
		var hint: String = game.loot.hint()
		if not nd.is_empty():
			var have := int(Inventory.units(game.pack.grid, String(nd.res)))
			out.append({"t": "Search %s for %s (carrying %d, short %d)" % ["the marked buildings" if hint != "" else "buildings", nd.res, have, int(nd.get("short", 0))], "done": have >= int(nd.get("short", 1))})
		else:
			out.append({"t": "Search buildings for loot", "done": false})
		out.append({"t": "Reach an exit with the pack (%d marked)" % game.exits.size(), "done": false})
		return out
	if game.phase == "clear":
		var n: int = game._cleared_n()
		var total: int = Base.ZONES.size()
		var nz := _next_zone()
		out.append({"t": "Clear the %d zones (%d/%d)%s" % [total, n, total, (" - next: " + String(Base.ZONES[nz].name)) if nz >= 0 else ""], "done": n == total})
		out.append({"t": "Secure the gate", "done": false})
		return out
	var nd2: Dictionary = econ.needs()
	if not nd2.is_empty() and float(nd2.get("days", -1.0)) >= 0.0:
		out.append({"t": "Fix %s: %.1f days left - raid a %s" % [nd2.res, float(nd2.days), game.econ.place_word(String(nd2.place))], "done": false, "bad": true})
	var arc_lines: Array = game.arc.objectives() if game.arc != null else []    # ARC hook: the phase and the convoy's list
	out.append_array(arc_lines.filter(func(l): return bool(l.get("head", false))))
	var evac: bool = game.arc != null and game.arc.started and String(game.arc.phase().id) == "evacuate"
	if evac:
		out.append_array(arc_lines.filter(func(l): return not bool(l.get("head", false))))
	else:
		out.append_array(arc_lines.filter(func(l): return bool(l.get("list", false))))    # (the convoy's list and its parts total, from day 3)
	var shown := 0
	for id in econ.goal():
		var st: String = econ.state(String(id))
		var nm := String(econ.defs[id].name)
		if st == "building" or st == "queued":
			out.append({"t": "Building %s: %d%%" % [nm, int(100.0 * float(econ.st[id].done) / float(econ.defs[id].labor))], "done": false})
		else:
			var can: Dictionary = econ.can_start(String(id))
			if bool(can.ok):
				out.append({"t": "Start %s at the workbench (%s)" % [nm, _cost_text(String(id))], "done": false})
			else:
				var miss: Array = []
				for k in (can.missing as Dictionary):
					miss.append("%s %d" % [k, int(can.missing[k])])
				out.append({"t": "Build %s (needs %s)%s" % [nm, _cost_text(String(id)), (" - short " + ", ".join(miss)) if not miss.is_empty() else ""], "done": false})
		shown += 1
		if shown >= (1 if evac else 2):
			break
	if not game.crew_full():
		var rs: int = game.people.rescued
		out.append({"t": "Rescue survivors on raids (%d/6)" % mini(rs, 6), "done": rs >= 6})
	var sg = game.siege
	var nn: int = sg.night if sg.attacking else sg.nights_started + 1
	if sg.attacking or game.arc.is_horde_night(nn):
		out.append({"t": "Survive night %d" % nn, "done": false})
	else:
		out.append({"t": "Quiet nights: raid and build before the horde of night %d" % game.arc.next_horde_night(nn), "done": false})
	var m: float = econ.morale
	out.append({"t": "%s morale above 60 (now %d)" % ["Keep" if m >= 60.0 else "Raise", int(m)], "done": m >= 60.0})
	var bd: Dictionary = econ.beds()
	if int(bd.free) < 0 and out.size() < 5:
		out.append({"t": "More people than beds: build a dormitory", "done": false, "bad": true})
	return out.slice(0, 5)


## Where in the world the current objective is (tiles), or Vector2.INF: the arrow of prison_tags.gd points at it.
func focus() -> Dictionary:
	if game.mode == "raid":
		var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
		var best := Vector2.INF
		var bd := 1.0e9
		for pl in game.loot.places:
			if game.loot.target.has(String(pl.type)):
				var d := me.distance_to(Vector2(pl.pos))
				if d < bd and d > 3.0:
					bd = d
					best = Vector2(pl.pos)
		if best != Vector2.INF:
			return {"pos": best, "label": "Search here"}
		return {}
	if game.phase == "clear":
		var nz := _next_zone()
		return {"pos": Vector2(Base.ZONES[nz].rel), "label": String(Base.ZONES[nz].name)} if nz >= 0 else {"pos": Vector2(Base.GATE_POS), "label": "The gate"}
	var econ = game.econ
	for id in econ.goal():
		var st: String = econ.state(String(id))
		if st == "building" or st == "queued":
			return {"pos": econ.site(String(id)), "label": "Building site"}
		var can: Dictionary = econ.can_start(String(id))
		if bool(can.ok):
			return {"pos": Vector2(game.base.stations.bench1), "label": "Workbench"}
		if not (can.missing as Dictionary).is_empty():
			return {"pos": Vector2(Base.GATE_POS), "label": "Raid for loot"}
		break
	return {}


func _tracker(on: bool) -> void:
	if not on:
		return
	if game.mode == "base" and game.phase == "clear":
		if _fight_t > 0.0:
			_fight_t = maxf(0.0, _fight_t - 0.2)
		for z in game.run.sim.zombies:
			if z.state != "dying" and z.state != "dead" and Vector2(z.x, z.y).distance_to(Vector2(game.run.avatar_p.x, game.run.avatar_p.y)) < 9.0:
				_fight_t = 3.0
				break
	var items: Array = objectives()
	var compact := _fighting() and not tr_folded
	var sig := "%s|%s|%s" % [tr_folded, compact, str(items)]
	tr_head.text = "OBJECTIVES  [O]%s" % ("   +" if tr_folded else "")
	if sig == _sig:
		return
	_sig = sig
	for c in tr_body.get_children():
		tr_body.remove_child(c)
		c.queue_free()
	tr_body.visible = not tr_folded
	var k := 0
	for it in items:
		if compact and k >= 1:
			break
		k += 1
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		var ib := IconBox.new(15)
		ib.set_icon("boxcheck" if bool(it.done) else "box", Hud.OK if bool(it.done) else (Hud.DANGER_TEXT if bool(it.get("bad", false)) else Hud.ACCENT))
		hb.add_child(ib)
		var l := _lab(String(it.t), 14, DIM if bool(it.done) else (Hud.INK if k == 1 else Hud.INK2), false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 276
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		if it.has("bar"):    # ARC hook: a thin progress bar under the line
			var vb := VBoxContainer.new()
			vb.add_theme_constant_override("separation", 1)
			vb.add_child(hb)
			var pb := ProgressBar.new()
			pb.show_percentage = false
			pb.max_value = 1.0
			pb.value = float(it.bar)
			pb.custom_minimum_size = Vector2(0, 4)
			pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pb.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.5), Hud.LINE, 0, 2))
			pb.add_theme_stylebox_override("fill", _box(Hud.ACCENT, Hud.ACCENT, 0, 2))
			vb.add_child(pb)
			tr_body.add_child(vb)
		else:
			tr_body.add_child(hb)
