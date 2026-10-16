## EXPERIMENT (prison management, step 2): the UI on top of the economy core (`game.econ`, prison_econ.gd; only its public API is used). One window with three tabs: PROJECTS (E at the workshop bench),
## NEEDS (E at the sign by the gate, plus a compact two-line version in the HUD text) and ROSTER (key B). Also the stage card and the toasts (project done, person left, shortage, stage).
## Pattern: plain Control nodes (PanelContainer, tabs as toggle buttons, cards as PanelContainers) on one CanvasLayer, in the town's colours and fonts (ui/hud.gd constants, ui/fonts.gd), like the
## backpack windows; the HUD pattern is a small text block appended to the existing HUD label and a toast stack. The window rebuilds its rows only when a signature of what it shows changes, and
## the progress bars are updated in place, so a hover or an open drop-down is not thrown away. Opening it closes the backpack and the other way round; it blocks the gun like the backpack does.
## Staging flags (see docs/experiments/prison-management.md): --board=projects[:building]|needs|roster|card|toast, --econ=give:scrap=50,parts=20, --board-start=water1.
extends RefCounted

const PIcons := preload("res://scripts/prison/prison_icons.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Topbar := preload("res://scripts/prison/prison_topbar.gd")

const BOARD_AT := Vector2(31.0, 46.0)    # the needs sign, inside the gate (outside the gate prompt's reach)
const REACH := 2.8
const NAME_MAX := 14    # the longest name a person can be given in the Roster
const BUILDINGS := ["water", "garden", "kitchen", "infirmary", "dormitory", "power", "fence", "radio", "convoy"]
const TITLES := {"water": "Water", "garden": "Garden", "kitchen": "Kitchen", "infirmary": "Infirmary", "dormitory": "Dormitory", "power": "Power", "fence": "Fence", "radio": "Radio", "convoy": "Convoy"}
const BLURB := {
	"water": "Everyone drinks 1 water a day. The pump and barrels give more. Worked by a hauler.",
	"garden": "Grows the food: everyone eats 1 a day and part of the stock spoils. Worked by a gardener.",
	"kitchen": "Cooks the meals. A cook alive in a kitchen lifts morale every day; the larder keeps food from spoiling. Worked by a cook.",
	"infirmary": "Cots and medicine. A medic alive in the infirmary lifts morale and treats bites. Worked by a medic.",
	"dormitory": "Beds. More people than beds costs morale every day. Worked by a hauler.",
	"power": "The generator runs the floodlights and the radio room. It burns 1 fuel a day. Worked by a mechanic.",
	"fence": "Raises the hit points of every fence wall against the nightly attacks. Worked by a mechanic.",
	"radio": "Calls survivors to the prison: the last step of the Hub stage. Needs power. Worked by a mechanic.",
	"convoy": "The truck that joins the Harbor Convoy on day 30: 8 seats. Needs the generator and a mechanic. The convoy also wants fuel, parts, a radio room and a fence at tier 2 (the Story tab).",
}
const ROLES := ["gardener", "cook", "medic", "mechanic", "guard", "cleaner", "hauler"]
const RES_NAME := {"food": "Food", "water": "Water", "fuel": "Fuel", "ammo": "Ammo", "meds": "Meds", "scrap": "Scrap", "parts": "Parts"}
const DIM := Color("#8d927f")
## Where a crew stop is, in words (prison_crew.gd's `at` names without the number), for the roster's "walking to the ...".
const STOP_WORD := {"bed": "infirmary", "bench": "workbench", "chat_a": "yard", "chat_b": "yard", "fence_e": "fence", "fence_m": "fence", "fence_w": "fence", "fridge": "kitchen",
	"garden": "garden", "meds": "medicine shelf", "serve": "canteen", "stores_in": "stores", "stores_out": "stores", "stove": "kitchen", "well": "pump", "yard": "yard"}
const TAB_HINT := {
	"projects": "PROJECTS: what to build. Pick a building on the left, then press Start on a project: it spends the scrap and parts now, and the crew does the work.",
	"needs": "NEEDS: what the base is short of, what the day costs, and which kind of place to raid for it.",
	"roster": "ROSTER: who does which job. A building makes nothing until somebody holds its role. Change a role with the drop-down.",
	"defence": "DEFENCE: put a person on a post of the wall and set barricades. Do it before 21:00, when the dead attack.",
	"story": "STORY: the 30-day plan, the radio messages, and the list the convoy wants on day 30.",
}
const LEGEND := "B or Esc close     L the story     F1 F2 F3 game speed     . wait for dusk     U undo the last order     E at the workbench or the gate board     Tab backpack     H help"
const STEPS := [
	["open", "Press B to open the Base screen"],
	["water", "Start the Water project (Projects tab)"],
	["role", "Give somebody a job (Roster tab)"],
	["post", "Post a guard on the wall (Defence tab)"],
	["night", "Wait for the night: F3 speeds up, the period key waits for dusk"],
]

var game
var econ
var layer: CanvasLayer
var root: Control
var panel: PanelContainer
var body: VBoxContainer
var title: Label
var tab_btns := {}
var toasts: VBoxContainer
var card: PanelContainer
var tab := "projects"
var sel := "water"
var _sig := ""
var _etas := {}    # project id -> the ETA label (game hours left at the present crew)
var _bars := {}    # project id -> ProgressBar
var _frames := 0
var _card_tw: Tween
var _popup_open := false
var _bseg := 0    # the Defence tab: the fence segment chosen for a barricade
var hint: Button    # "Base (B)": always on in the managed base
var hint_dot: Label    # a pulsing dot on it while a project can be started; opening the Base screen clears it until the next one
var _dot_ready := false
var _dot_acked := false
var tabhint: Label
var steps_panel: PanelContainer
var steps_lab: Label
var did := {}    # the first-day checklist: step id -> done
var steps_off := false
var undo_btn: Button    # UNDO: the last order, for 30 game seconds
var wait_lab: Label    # WAIT: shown while the base fast-forwards to dusk
var morning: Control    # MORNING: the summary card of the dawn (any key closes it)
var _hl := ""    # WHAT NEXT: the project the button picked (its card is lit)
var _whynext := ""
var _clean_rounds := 0    # the cleaner's rounds at the last dawn


func _init(g) -> void:
	game = g
	econ = g.econ
	layer = CanvasLayer.new()
	layer.layer = 12
	g.add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	panel = PanelContainer.new()
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _box(Color(Hud.PANEL, 0.985), Hud.LINE2, 14, 6))
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	title = _lab("PRISON", 24, Hud.ACCENT, true)
	title.custom_minimum_size.x = 150
	head.add_child(title)
	for t in [["projects", "Projects"], ["needs", "Needs"], ["roster", "Roster"], ["defence", "Defence"], ["story", "Story (L)"]]:
		var b := _btn(String(t[1]))
		b.toggle_mode = true
		b.pressed.connect(func(): _show(String(t[0])))
		tab_btns[t[0]] = b
		head.add_child(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	undo_btn = _btn("Undo")
	undo_btn.visible = false
	undo_btn.pressed.connect(undo)
	head.add_child(undo_btn)
	var x := _btn("Close (Esc)")
	x.pressed.connect(close)
	head.add_child(x)
	tabhint = _lab("", 14, Hud.INFO)
	tabhint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tabhint)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	sc.add_child(body)
	var leg := _lab(LEGEND, 12, DIM)
	leg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(leg)
	hint = _btn("Base (B)")
	hint.visible = false
	hint.pressed.connect(func(): open("projects"))
	root.add_child(hint)
	hint_dot = Label.new()
	hint_dot.text = "\u25cf"
	hint_dot.add_theme_font_size_override("font_size", 18)
	hint_dot.add_theme_color_override("font_color", Hud.WARN)
	hint_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_dot.visible = false
	hint.add_child(hint_dot)
	hint_dot.position = Vector2(hint.size.x - 14.0, -10.0)
	wait_lab = _lab("Waiting for dusk, 3x. Press . to stop.", 18, Hud.ACCENT, true)
	wait_lab.visible = false
	root.add_child(wait_lab)
	steps_panel = PanelContainer.new()
	steps_panel.visible = false
	steps_panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.07, 0.06, 0.92), Hud.ACCENT, 10, 8))
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 3)
	steps_panel.add_child(sv)
	sv.add_child(_lab("FIRST DAY: THE BASE IN 5 STEPS", 14, Hud.ACCENT, true))
	steps_lab = _lab("", 14, Hud.INK)
	sv.add_child(steps_lab)
	var hide := _btn("Hide")
	hide.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hide.pressed.connect(func(): steps_off = true)
	sv.add_child(hide)
	root.add_child(steps_panel)
	toasts = VBoxContainer.new()
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_theme_constant_override("separation", 6)
	root.add_child(toasts)
	econ.project_done.connect(func(id): toast("Built: %s" % String(econ.defs[id].name), Hud.OK))
	econ.person_left.connect(func(nm): toast("%s has left the prison." % nm, Hud.DANGER_TEXT))
	econ.shortage.connect(func(r): toast("Shortage: the base ran out of %s." % r, Hud.WARN))
	econ.stage_changed.connect(_stage_card)


# ------------------------------------------------------------------------------ small builders --

func _box(bg: Color, line: Color, margin: int, radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _lab(text: String, size: int, col: Color, cond := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.cond(700) if cond else Fonts.sans(500))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rich(text: String, size: int = 15) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", Fonts.sans(500))
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", Hud.INK2)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.text = text
	return r


func _btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE    # (keys stay the game's: no Space or Enter on a button)
	b.add_theme_font_override("font", Fonts.cond(600))
	b.add_theme_font_size_override("font_size", 16)
	return b


func _bar(frac: float, col: Color, h: float = 12.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.max_value = 1.0
	p.value = clampf(frac, 0.0, 1.0)
	p.custom_minimum_size = Vector2(120, h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.45), Hud.LINE, 0, 3))
	p.add_theme_stylebox_override("fill", _box(col, col, 0, 3))
	return p


func _col(c: Color) -> String:
	return "#" + c.to_html(false)


func _pname(id: String) -> String:
	return String(econ.defs[id].name) if econ.defs.has(id) else id


# ------------------------------------------------------------------------------------ open / keys --

func prompt(me: Vector2) -> Dictionary:
	if game.phase != "managed" or game.mode != "base" or game.busy:
		return {}
	for s in ["bench1", "bench2"]:
		if me.distance_to(game.base.stations[s]) < REACH:
			return {"kind": "bench", "label": "E: open the project board (workbench): spend scrap and parts"}
	if me.distance_to(BOARD_AT) < REACH:
		return {"kind": "board", "label": "E: open the needs board (what we lack, where to raid)"}
	return {}


func open(which: String) -> void:
	if game.phase != "managed" or game.mode != "base":
		return
	game.pack.close()
	panel.visible = true
	_dot_acked = true
	did["open"] = true
	_show(which)


## The dot on Base (B): some project can be started now (affordable, with a worker). Checked twice a second; it is cleared when the Base screen opens and comes back when a project becomes startable again.
func _dot_frame(base_on: bool) -> void:
	if _frames % 30 == 1:
		var ok := false
		for p in econ.projects():
			if bool(econ.can_start(String(p.id)).ok):
				ok = true
				break
		if ok and not _dot_ready:
			_dot_acked = false
		_dot_ready = ok
	hint_dot.visible = base_on and _dot_ready and not _dot_acked
	if hint_dot.visible:
		hint_dot.position = Vector2(hint.size.x - 14.0, -10.0)
		hint_dot.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(float(_frames) * 0.12))


func close() -> void:
	panel.visible = false
	_bars.clear()
	_etas.clear()


func is_open() -> bool:
	return panel.visible or (morning != null and morning.visible)    # (the morning card is as modal as the window: no speed, no story card over it)


func _show(t: String) -> void:
	if t != tab:
		_hl = ""
		_whynext = ""
	tab = t
	_sig = ""


## UNDO: the last order is taken back with its whole cost, while the 30 game seconds last.
func undo() -> void:
	var id: String = econ.undo_id
	if econ.undo_start():
		toast("Undone: %s. The cost is back." % _pname(id), Hud.INFO)
		_sig = ""


## WHAT NEXT: the one project to start. Of the ones that can be started (their tiers below are built), an affordable one first, else the one nearest to affordable. A project that is on the way
## to the next stage, or that makes what the base is shortest of (`econ.needs()`), wins over a cheaper one. Returns {id, why}; selects its building and lights its card.
func pick_next() -> Dictionary:
	var nd: Dictionary = econ.needs()
	var want := String(nd.get("res", ""))
	var path: Array = econ.goal()
	var best := ""
	var best_sc := 1.0e9
	var best_ok := false
	for id in econ.order:
		if econ.state(id) != "available":
			continue
		var d: Dictionary = econ.defs[id]
		var can: Dictionary = econ.can_start(id)
		var ok := bool(can.ok)
		var tot := 0.0
		var miss := 0.0
		for k in d.cost:
			tot += float(d.cost[k])
		for k in can.missing:
			miss += float(can.missing[k])
		var sc := tot * 0.001 + (0.0 if ok else 1.0 + miss / maxf(tot, 1.0) + (0.5 if econ.workers(String(d.role)) == 0 else 0.0))
		if want != "" and String(econ.cfg.production_building.get(want, "")) == String(d.building):
			sc -= 0.4
		if path.has(id):
			sc -= 0.2
		if best == "" or (ok and not best_ok) or (ok == best_ok and sc < best_sc):
			best = String(id)
			best_sc = sc
			best_ok = ok
	if best == "":
		return {"id": "", "why": "Nothing is left to start: the rest is built or waits on a project in the queue."}
	var d2: Dictionary = econ.defs[best]
	var why := ""
	var can2: Dictionary = econ.can_start(best)
	if best_ok:
		why = "You can afford %s now" % String(d2.name)
	elif not (can2.missing as Dictionary).is_empty():
		var parts: Array = []
		for k in can2.missing:
			parts.append("%d %s" % [int(can2.missing[k]), k])
		why = "%s is the nearest to affordable: you are %s short" % [String(d2.name), " and ".join(parts)]
	else:
		why = "%s needs a %s: give somebody that job in the Roster" % [String(d2.name), String(d2.role)]
	if want != "" and String(econ.cfg.production_building.get(want, "")) == String(d2.building):
		why += ", and %s is what the base is shortest of." % want
	elif path.has(best):
		why += ", and it is on the way to the next stage."
	else:
		why += "."
	return {"id": best, "why": why}


func what_next() -> void:
	var r := pick_next()
	_hl = String(r.id)
	_whynext = String(r.why)
	if _hl != "":
		sel = String(econ.defs[_hl].building)
	tab = "projects"
	_sig = ""


## Esc and B for the window; Tab and I (the backpack) close it first. True when the key was used.
func key(ev: InputEvent) -> bool:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return false
	var k := ev as InputEventKey
	if morning != null and morning.visible:    # MORNING: any key puts the card away
		morning.visible = false
		return true
	if k.keycode == KEY_U and game.phase == "managed" and game.mode == "base" and not game.busy and econ.can_undo():    # UNDO
		undo()
		return true
	if panel.visible:
		if k.keycode == KEY_ESCAPE:
			close()
			return true
		if k.keycode == KEY_B:
			close()
			return true
		if k.keycode == KEY_TAB or k.keycode == KEY_I:
			close()
		return false
	if k.keycode == KEY_B and game.phase == "managed" and game.mode == "base" and not game.busy:
		open(tab)
		return true
	return false


## The mouse is over the window: the gun must not fire through it.
func blocks_fire() -> bool:
	var m: Vector2 = game.get_viewport().get_mouse_position()
	if hint.visible and Rect2(hint.position, hint.size).grow(6.0).has_point(m):
		return true
	return panel.visible and Rect2(panel.position, panel.size).grow(6.0).has_point(m)


# ------------------------------------------------------------------------------------------ frame --

func frame(_dt: float) -> void:
	_frames += 1
	var v: Vector2 = game._vp()
	toasts.position = Vector2(v.x - 330.0, game.topbar.toast_y() if game.topbar != null else 14.0)
	toasts.size.x = 316.0
	_stage_flags()
	var base_on: bool = game.phase == "managed" and game.mode == "base" and not game.busy
	hint.visible = base_on and not panel.visible
	hint.position = Vector2((v.x - hint.size.x) / 2.0, v.y - 46.0)
	_dot_frame(base_on)
	_checklist(base_on)
	wait_lab.visible = game.wait_dusk and base_on
	wait_lab.position = Vector2((v.x - wait_lab.size.x) / 2.0, 156.0)
	undo_btn.visible = panel.visible and econ.can_undo()
	if undo_btn.visible:
		undo_btn.text = "Undo: %s (%d s)  U" % [_pname(econ.undo_id), ceili(econ.undo_left)]
	_morning_frame(base_on, v)
	if not panel.visible:
		return
	if game.phase != "managed" or game.mode != "base":
		close()
		return
	var sz := Vector2(minf(980.0, v.x - 24.0), minf(660.0, v.y - 24.0))
	panel.custom_minimum_size = sz
	panel.size = sz
	panel.position = ((v - sz) / 2.0).round()
	for b in tab_btns:
		tab_btns[b].button_pressed = (b == tab)
	title.text = "BASE"
	tabhint.text = TAB_HINT[tab]
	tabhint.custom_minimum_size.x = sz.x - 40.0
	if _popup_open:
		_popup_open = _any_popup(body)
	var sig := _signature()
	if sig != _sig and not _popup_open:
		_sig = sig
		_rebuild()
	for id in _bars:
		var d: Dictionary = econ.defs[id]
		_bars[id].value = clampf(float(econ.st.get(id, {}).get("done", 0.0)) / float(d.labor), 0.0, 1.0)
		if _etas.has(id):
			(_etas[id] as Label).text = "about %.1f h left" % econ.eta_h(id)


func _any_popup(n: Node) -> bool:
	if n is LineEdit and (n as LineEdit).has_focus():    # (a name being typed in the Roster: the page must not be rebuilt under it)
		return true
	if n is OptionButton and (n as OptionButton).get_popup().visible:
		return true
	for c in n.get_children():
		if _any_popup(c):
			return true
	return false


## Everything the rows show except the progress bars, as one string.
func _signature() -> String:
	var s := "%s|%s|%s|%s|%s|" % [tab, sel, game.siege.attacking, _hl, _whynext]
	for k in game.stores:
		s += "%d," % int(game.stores[k])
	for id in econ.order:
		s += econ.state(id).left(2)
	if tab == "needs":
		s += "|%d|%d|%d" % [int(econ.morale), econ.day, int(game.siege.abs_h * 60.0 / 4.0)]
	if tab == "defence":
		s += "|%d|%s|%s" % [_bseg, game.siege.posts.assign.hash(), game.siege.bars.to_dict().hash()]
		for m in game.crew.members:
			s += "%s%s," % [m.def.id, m.def.get("stand", "")]
	if tab == "story":
		s += "|%d|%d|%d" % [game.arc.log_entries.size(), game.arc.day, game.arc.people_alive()]
	if tab == "roster":
		for m in game.crew.members:
			s += "%s%s%s," % [m.def.id, m.say, m.state]
		s += str(econ.cfg.crew_role.hash())
	return s


func _rebuild() -> void:
	_bars.clear()
	_etas.clear()
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	match tab:
		"projects":
			_projects_tab()
		"needs":
			_needs_tab()
		"roster":
			_roster_tab()
		"defence":
			_defence_tab()
		"story":
			game.arc.story.fill(body, _lab, _rich, _bar)    # ARC hook: calendar, phases, the convoy's list, the messages


# ----------------------------------------------------------------------------------- projects tab --

func _effect_text(d: Dictionary) -> String:
	var e: Dictionary = d.get("effect", {})
	var out: Array = []
	var prod: Dictionary = econ.cfg.production
	for r in prod:
		if String(econ.cfg.production_building[r]) == String(d.building):
			var tiers: Array = prod[r]
			var t := int(d.tier)
			if t < tiers.size():
				var a: float = float(tiers[t].amt) + float(tiers[t].get("passive", 0.0))
				var b: float = float(tiers[t - 1].amt) + float(tiers[t - 1].get("passive", 0.0))
				out.append("%s %d a day (was %d)" % [r, roundi(a), roundi(b)])
	if e.has("cap"):
		for r in e.cap:
			out.append("store up to %d %s" % [int(e.cap[r]), r])
	if e.has("beds"):
		out.append("+%d beds" % int(e.beds))
	if e.has("spoil"):
		out.append("food spoils at half the rate")
	if e.has("hit"):
		out.append("guards hit %d%% more at night while the generator runs" % roundi(float(e.hit) * 100.0))
	if e.has("fence"):
		out.append("fence walls hold x%.1f" % float(e.fence) if float(e.fence) != 1.0 else "every wall is mended")
	if e.has("hub"):
		out.append("opens the Hub stage")
	if e.has("note"):
		out.append(String(e.note))
	if out.is_empty():
		return "-"
	var t := "; ".join(out)
	return t.left(1).to_upper() + t.substr(1)


func _projects_tab() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	body.add_child(hb)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 170
	left.add_theme_constant_override("separation", 4)
	hb.add_child(left)
	for b in BUILDINGS:
		var n := (econ.projects(b) as Array).size()
		var ready := false
		for p in econ.projects(b):
			if bool(econ.can_start(String(p.id)).ok):
				ready = true
		var btn := _btn("%s   %d/%d%s" % [TITLES[b], econ.tier(b), n, "  +" if ready else ""])
		btn.toggle_mode = true
		btn.button_pressed = (b == sel)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func():
			sel = b
			_sig = "")
		left.add_child(btn)
	left.add_child(_lab("+ : something can be started now", 12, DIM))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	th.add_child(_lab(TITLES[sel], 22, Hud.INK, true))
	var wn := _btn("What next?")
	wn.tooltip_text = "Jumps to the one project that helps most right now: one you can afford first, otherwise the nearest to affordable."
	wn.pressed.connect(what_next)
	th.add_child(wn)
	right.add_child(th)
	if _whynext != "":
		var wl := _lab(_whynext, 15, Hud.WARN)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(wl)
	var role := String(econ.cfg.building_role[sel])
	var bl := _rich("%s\n[color=%s]Worker: %s, alive now: %d[/color]" % [BLURB[sel], _col(Hud.INFO), role, econ.workers(role)], 15)
	right.add_child(bl)
	for p in econ.projects(sel):
		right.add_child(_card(p))


func _card(p: Dictionary) -> Control:
	var id := String(p.id)
	var state := String(p.state)
	var can: Dictionary = econ.can_start(id)
	var line := Hud.LINE2
	if state == "built":
		line = Hud.OK
	elif state == "queued" or state == "building":
		line = Hud.ACCENT
	var pc := PanelContainer.new()
	var sb := _box(Hud.PANEL_HI, line, 10)
	if id == _hl:    # WHAT NEXT: the picked project has a thick warm border
		sb.border_color = Hud.WARN
		sb.set_border_width_all(4)
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	pc.tooltip_text = "%s\n%s" % [_pname(id), _effect_text(p)]
	if state == "locked":
		pc.modulate = Color(1, 1, 1, 0.6)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	pc.add_child(hb)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	hb.add_child(col)
	col.add_child(_lab("Tier %d   %s" % [int(p.tier), p.name], 19, Hud.INK, true))
	var gl := _lab(String(p.get("gives", "")), 14, Hud.INK)
	gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(gl)
	col.add_child(_lab(_effect_text(p), 13, DIM))
	var cost := ""
	var paid := state == "built" or state == "queued" or state == "building"    # (Start spent the cost: no shortage any more)
	for k in p.cost:
		var have := int(floor(float(game.stores.get(k, 0.0))))
		var need := int(p.cost[k])
		if paid or have >= need:
			cost += "%d %s    " % [need, k]
		else:
			cost += "[color=%s]%d %s (short %d)[/color]    " % [_col(Hud.DANGER_TEXT), need, k, need - have]
	if paid:
		cost = "[color=%s]Paid: %s[/color]" % [_col(DIM), cost]
	col.add_child(_rich(("" if paid else "Cost: ") + cost + "[color=%s]   Labor: %d s by a %s[/color]" % [_col(Hud.INK3), int(p.labor), p.role], 14))
	var stt := _status(p, can)
	col.add_child(_lab(String(stt[0]), 14, stt[1]))
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 140
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 6)
	hb.add_child(side)
	if state == "built":
		side.add_child(_lab("BUILT", 18, Hud.OK, true))
	elif state == "queued" or state == "building":
		side.add_child(_lab("Under way" if state == "building" else "Queued", 15, Hud.ACCENT, true))
		var el := _lab("about %.1f h left" % econ.eta_h(id), 13, Hud.INK2)
		_etas[id] = el
		side.add_child(el)
		var pb := _bar(float(p.done) / float(p.labor), Hud.ACCENT)
		_bars[id] = pb
		side.add_child(pb)
	else:
		var b := _btn("Start")
		b.disabled = not bool(can.ok)
		b.tooltip_text = "Spends the cost now; the crew does the work." if bool(can.ok) else String(can.why)
		b.pressed.connect(func():
			if econ.start(id):
				toast("Started: %s" % _pname(id), Hud.INFO)
			_sig = "")
		side.add_child(b)
	return pc


## One plain status line for a project: [text, colour].
func _status(p: Dictionary, can: Dictionary) -> Array:
	var state := String(p.state)
	if state == "built":
		return ["Built.", Hud.OK]
	if state == "queued" or state == "building":
		return ["The crew is working on it.", Hud.ACCENT]
	if state == "locked":
		return ["Locked: " + String(can.why) + " first.", Hud.WARN]
	if bool(can.ok):
		return ["You can afford it. Press Start.", Hud.OK]
	if not (can.missing as Dictionary).is_empty():
		var parts: Array = []
		for k in can.missing:
			parts.append("%d %s" % [int(can.missing[k]), k])
		return ["Missing " + ", ".join(parts) + ". Raid for it.", Hud.DANGER_TEXT]
	return ["Needs a %s: nobody holds that job. Give one in the Roster." % String(p.role), Hud.DANGER_TEXT]


# ------------------------------------------------------------------------------------- needs tab --

func _next_stage() -> String:
	var names: Array = ["Camp"]
	for s in econ.cfg.stages:
		names.append(String(s.name))
	var i := names.find(econ.stage())
	return String(names[i + 1]) if i + 1 < names.size() else ""


func next_attack() -> String:
	var sg = game.siege
	if sg.attacking:
		return "UNDER ATTACK: night %d, %d of the dead still at the walls" % [sg.night, sg._alive_wave()]
	var hrs := maxf(0.0, sg.NIGHT_H + 24.0 * float(sg.nights_started) - sg.abs_h)    # game hours, as the clock reads (not real seconds)
	return "%s (night %d, %s)" % [game.arc.horde_line(sg.nights_started + 1), sg.nights_started + 1, ("at %02d:00" % int(sg.NIGHT_H)) if hrs < 24.0 and hrs >= 1.0 else ("in %d min" % ceili(hrs * 60.0) if hrs < 1.0 else "in %d h" % int(hrs))]


func morale_reasons(rep: Dictionary) -> Array:
	var out: Array = []
	var crit: float = float(econ.cfg.needs.critical_days)
	if not (rep.last.short as Dictionary).is_empty():
		out.append(["went without " + " and ".join((rep.last.short as Dictionary).keys()) + " last night", false])
	for r in ["food", "water"]:
		var d: float = float(rep.res[r].days)
		if d >= 0.0 and d < crit:
			out.append(["less than %d days of %s left" % [int(crit), r], false])
	if int(rep.people) > int(rep.beds.cap):
		out.append(["more people than beds", false])
	if econ.tier("kitchen") > 0 and econ.workers("cook") > 0:
		out.append(["hot meals from the kitchen", true])
	if econ.tier("infirmary") > 0 and econ.workers("medic") > 0:
		out.append(["the infirmary is staffed", true])
	if game.cleaner != null:    # TRASH hook
		var n: int = game.cleaner.piles()
		if n == 0:
			out.append(["the base is tidy", true])
		elif n >= 3:
			out.append(["%d piles of trash" % n, false])
	if out.is_empty() or not out.any(func(o): return not o[1]):
		out.append(["nothing is wrong: morale recovers", true])
	if float(rep.morale) < float(econ.cfg.morale.leave_below):
		out.append(["below %d: someone leaves in the night" % int(econ.cfg.morale.leave_below), false])
	return out


## The three needs that matter most, ranked, each with the action that fixes it: [{res, line, action}].
## Food and water by days left under the critical days, then what the next stage's projects lack (the biggest gap first), then ammo and meds under their low mark.
func top_needs() -> Array:
	var out: Array = []
	var rep: Dictionary = econ.daily_report()
	var crit: float = float(econ.cfg.needs.critical_days)
	var rows: Array = []
	for r in ["food", "water"]:
		var e: Dictionary = rep.res[r]
		var d := float(e.days)
		if d >= 0.0 and d < crit:
			var b := "garden" if r == "food" else "water"
			var alt := ""
			for p in econ.projects(b):
				if String(p.state) == "available":
					alt = ", or build %s" % String(p.name)
					break
			rows.append([d, r, "%s: %.1f days left at %+d a day" % [RES_NAME[r], d, roundi(float(e.net))], "Raid a %s%s" % [econ.place_word(String(econ.cfg.fixes.get(r, "shop"))), alt]])
	var total := {}
	var first_for := {}
	var path: Array = econ.goal()
	if path.is_empty():
		var nid: String = econ.needs().get("for", "")
		if nid != "":
			path = [nid]
	for id in path:
		for k in econ.defs[id].cost:
			total[k] = float(total.get(k, 0.0)) + float(econ.defs[id].cost[k])
			if not first_for.has(k):
				first_for[k] = _pname(String(id))
	for k in total:
		var sh: float = float(total[k]) - float(game.stores.get(k, 0.0))
		if sh > 0.0:
			rows.append([100.0 + 1000.0 / maxf(1.0, sh), k, "%s: short by %d for %s" % [RES_NAME.get(k, k), int(ceil(sh)), first_for[k]], "Raid a %s" % econ.place_word(String(econ.cfg.fixes.get(k, "house")))])
	for r in econ.cfg.needs.low:
		var have: float = float(game.stores.get(r, 0.0))
		if have < float(econ.cfg.needs.low[r]) and not rows.any(func(q): return q[1] == r):
			rows.append([500.0 + have, r, "%s: only %d left" % [RES_NAME.get(r, r), int(have)], "Raid a %s" % econ.place_word(String(econ.cfg.fixes.get(r, "house")))])
	var bd0: Dictionary = econ.beds()
	if int(bd0.free) > 0 and not game.crew_full():    # (fix round 3: people come only from raids)
		rows.append([600.0 - float(int(bd0.used)) * 10.0, "people", "People: %d of %d beds are taken" % [int(bd0.used), int(bd0.cap)], "Raid for survivors (the HELP! markers on the map)"])
	rows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for q in rows.slice(0, 3):
		out.append({"res": q[1], "line": q[2], "action": q[3]})
	return out


func _needs_header() -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(Color(0.12, 0.09, 0.05, 0.9), Hud.ACCENT, 10, 6))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	pc.add_child(vb)
	vb.add_child(_lab("WHAT DO WE NEED", 18, Hud.ACCENT, true))
	var needs := top_needs()
	if needs.is_empty():
		vb.add_child(_lab("Nothing is short. Build the next project or stock up before the night.", 15, Hud.OK))
	var i := 1
	for n in needs:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		vb.add_child(hb)
		hb.add_child(_lab("%d" % i, 18, Hud.INK3, true))
		var ib := Topbar.IconBox.new(20)
		ib.set_icon(String(n.res) if Topbar.RES.has(String(n.res)) else "target", Topbar.RES_COL.get(String(n.res), Hud.ACCENT))
		hb.add_child(ib)
		var l := _lab(String(n.line), 16, Hud.INK)
		l.custom_minimum_size.x = 330
		hb.add_child(l)
		hb.add_child(_lab("-> " + String(n.action), 16, Hud.WARN))
		i += 1
	body.add_child(pc)


func _needs_tab() -> void:
	var rep: Dictionary = econ.daily_report()
	var nx := _next_stage()
	var goal: Array = econ.goal()
	var names: Array = []
	for id in goal:
		names.append(_pname(String(id)))
	_needs_header()
	body.add_child(_lab("Day %d    Stage: %s" % [int(rep.day), rep.stage], 22, Hud.INK, true))
	body.add_child(_rich(("Next stage: [b]%s[/b]. Still to build: %s." % [nx, ", ".join(names)]) if nx != "" else "The prison is a Hub. Nothing more to reach.", 15))
	# production against consumption per day
	body.add_child(_lab("Per day", 17, Hud.ACCENT, true))
	var g := GridContainer.new()
	g.columns = 7
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 3)
	body.add_child(g)
	for h in ["", "Stock", "Made", "Used", "Spoiled", "Net", "Left"]:
		g.add_child(_lab(h, 13, DIM))
	var caps: Dictionary = econ.caps()
	for r in ["food", "water", "fuel"]:
		var e: Dictionary = rep.res[r]
		var mk := roundi(float(e.prod))
		var us := roundi(float(e.cons))
		var sp := roundi(float(e.get("spoil", 0.0)))
		var net := mk - us - sp    # (the shown parts add up to the shown net)
		g.add_child(_lab(RES_NAME[r], 15, Hud.INK))
		g.add_child(_lab("%d / %d" % [int(e.stock), int(caps.get(r, 0))], 15, Hud.INK2))
		g.add_child(_lab("+%d" % mk, 15, Hud.INK2))
		g.add_child(_lab("-%d" % us if us > 0 else "0", 15, Hud.INK2))
		g.add_child(_lab("-%d" % sp if sp > 0 else "0", 15, Hud.INK2))
		g.add_child(_lab("%+d" % net, 15, Hud.OK if net >= 0 else Hud.DANGER_TEXT))
		var days := float(e.days)
		g.add_child(_lab("steady" if days < 0.0 else "%.1f days" % days, 15, Hud.INK2 if days < 0.0 or days >= 3.0 else Hud.DANGER_TEXT))
	var others := ""
	for r in ["ammo", "meds", "scrap", "parts"]:
		others += "%s %d / %d      " % [RES_NAME[r], int(game.stores.get(r, 0.0)), int(caps.get(r, 0))]
	body.add_child(_lab(others, 15, Hud.INK2))
	# morale
	var m := float(rep.morale)
	body.add_child(_lab("Morale  %d / 100" % int(m), 17, Hud.ACCENT, true))
	var mb := _bar(m / 100.0, Hud.OK if m >= 50.0 else (Hud.WARN if m >= 25.0 else Hud.DANGER), 14.0)
	mb.custom_minimum_size.x = 300
	mb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(mb)
	for r in morale_reasons(rep):
		body.add_child(_lab("%s %s" % ["+" if r[1] else "-", r[0]], 15, Hud.OK if r[1] else Hud.DANGER_TEXT))
	# people and beds, attack, shortage
	var bd: Dictionary = rep.beds
	body.add_child(_lab("People %d      Beds %d / %d%s" % [int(rep.people), int(bd.used), int(bd.cap), "   (too many people)" if int(bd.free) < 0 else ""], 16, Hud.INK if int(bd.free) >= 0 else Hud.DANGER_TEXT))
	body.add_child(_lab("Next horde: " + next_attack(), 16, Hud.INK if not game.siege.attacking else Hud.DANGER_TEXT))
	var nd: Dictionary = econ.needs()
	if nd.is_empty():
		body.add_child(_lab("Biggest shortage: none", 16, Hud.OK))
	else:
		var s := "Biggest shortage: %s, short by about %d" % [nd.res, int(nd.get("short", 0))]
		if float(nd.get("days", -1.0)) >= 0.0:
			s += " (%.1f days left)" % float(nd.days)
		if nd.get("place", "") != "":
			s += ".  Raid a %s." % econ.place_word(String(nd.place))
		body.add_child(_lab(s, 16, Hud.WARN))
		if String(nd.get("reason", "")) != "":
			body.add_child(_lab(String(nd.reason), 14, DIM))
	var rb := _btn("Roster")
	rb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rb.pressed.connect(func(): _show("roster"))
	body.add_child(rb)


## The stage part of the HUD's second line (food and water days left and the biggest need live on the needs board).
func hud_lines() -> String:
	if game.phase != "managed" or game.mode != "base" or econ == null:
		return ""
	var rep: Dictionary = econ.daily_report()
	var building := "none"
	if not (econ.queue as Array).is_empty():
		var id := String(econ.queue[0])
		building = "%s %d%%, about %.1f h" % [_pname(id), int(100.0 * float(econ.st[id].done) / float(econ.defs[id].labor)), econ.eta_h(id)]
	return "%s  morale %d  beds %d/%d  building: %s" % [rep.stage, int(rep.morale), int(rep.beds.used), int(rep.beds.cap), building]


# ------------------------------------------------------------------------------------ roster tab --

func _job_text(m: Dictionary) -> String:
	if m.state == "downed" or m.state == "down":
		return "down"
	if m.state == "post":
		return "on watch"
	if m.state == "play":
		return "playing"
	if m.state == "walk":    # "walking to the pump", not "Hauler (walk)"
		var route: Array = m.def.get("route", [])
		var stop: Dictionary = m.eat if m.has("eat") else (route[int(m.i)] if int(m.get("i", -1)) >= 0 and int(m.i) < route.size() else {})
		var at = "serve" if bool(stop.get("meal", false)) else stop.get("at", "")
		if at is String and STOP_WORD.has(String(at).rstrip("0123456789")):
			return "walking to the " + String(STOP_WORD[String(at).rstrip("0123456789")])
		return ("on the way: " + String(stop.say)) if stop.has("say") else "walking"
	return String(m.say)


func _roster_tab() -> void:
	body.add_child(_rich("Change who does which job. Gardeners, haulers, cooks, medics and mechanics work the buildings; a building makes nothing when nobody holds its role. Changing a role moves the person to that work (a guard goes to a free tower post, six in all). Nobody can be moved during an attack.", 14))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 6)
	body.add_child(g)
	for h in ["Name", "Role", "Doing now", "Note, traits and background"]:
		g.add_child(_lab(h, 13, DIM))
	var roles: Dictionary = econ.cfg.crew_role
	for m in game.crew.members:
		if m.def.has("ally"):
			continue
		var id := String(m.def.id)
		var nm_box := HBoxContainer.new()    # PORTRAIT: a small bust beside the name
		nm_box.add_theme_constant_override("separation", 6)
		nm_box.add_child(PIcons.portrait_box(id, 30.0))
		nm_box.add_child(_name_cell(String(m.def.name)))
		g.add_child(nm_box)
		var locked: bool = m.def.has("play") or game.siege.attacking
		if m.def.has("play"):
			g.add_child(_lab("child", 15, DIM))
		else:
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			ob.add_theme_font_override("font", Fonts.sans(500))
			ob.add_theme_font_size_override("font_size", 15)
			ob.custom_minimum_size.x = 140
			for r in ROLES:
				ob.add_item(String(r).capitalize())
			var cur := ROLES.find(String(roles.get(id, "")))
			ob.selected = cur if cur >= 0 else ROLES.find("hauler")
			if cur < 0:
				ob.add_item("-")
				ob.selected = ob.item_count - 1
			ob.disabled = locked
			ob.pressed.connect(func(): _popup_open = true)
			ob.item_selected.connect(func(i):
				_popup_open = false
				if i < ROLES.size():
					var res: Dictionary = game.crew.set_role(id, ROLES[i], econ, game.siege.attacking)
					if not bool(res.ok):
						toast(String(res.why), Hud.WARN)
					else:
						did["role"] = true
				_sig = "")
			g.add_child(ob)
		g.add_child(_lab(_job_text(m), 15, Hud.INK2))
		var note := ""
		if game.siege.attacking and m.def.has("stand"):
			note = "on the wall"
		elif m.def.has("stand"):
			note = String(m.def.role).to_lower() if not String(m.def.stand).begins_with("tower") else "tower guard"
		var who := String(m.def.name)    # TRAITS: the traits after the note, the background under it
		if game.arc.hurt_now(who):
			note = ("hurt, " + note) if note != "" else "hurt"
		var nb := VBoxContainer.new()
		nb.add_child(_lab((note + "   " if note != "" else "") + game.arc.events.trait_text(who), 14, DIM))
		var bio: String = game.arc.events.bio_of(who)
		if bio != "":
			var bl := _lab(bio, 12, Hud.INK3)
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bl.custom_minimum_size.x = 360
			nb.add_child(bl)
		g.add_child(nb)
	var cnt := ""
	for r in ROLES:
		cnt += "%s %d    " % [String(r).capitalize(), econ.workers(String(r))]
	body.add_child(_lab("Alive per role:  " + cnt, 14, Hud.INFO))
	var tr: String = game.cleaner.report() if game.cleaner != null else ""    # TRASH hook
	body.add_child(_lab(tr if tr != "" else "The base is tidy.", 14, Hud.WARN if tr != "" else Hud.INFO))


## A person's name in the Roster: a flat button that turns into a box (Enter keeps the name, Esc or an empty box takes the old one back; 14 characters at most). META: the name is only what is shown.
func _name_cell(nm: String) -> Control:
	var b := Button.new()
	b.text = game.arc.dn(nm)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = "Click to rename"
	b.add_theme_font_override("font", Fonts.sans(500))
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Hud.INK)
	b.pressed.connect(func():
		_popup_open = true
		var le := LineEdit.new()
		le.text = game.arc.dn(nm)
		le.max_length = NAME_MAX
		le.custom_minimum_size.x = 130
		le.add_theme_font_override("font", Fonts.sans(500))
		le.add_theme_font_size_override("font_size", 16)
		le.text_submitted.connect(func(t: String):
			rename(nm, t)
			le.release_focus()
			_sig = "")
		b.get_parent().add_child(le)
		b.get_parent().move_child(le, b.get_index())
		b.queue_free()
		le.grab_focus()
		le.select_all())
	return b


## Gives a person a new shown name ("" or their own name takes the custom one away).
func rename(nm: String, shown: String) -> void:
	shown = shown.strip_edges().left(NAME_MAX)
	if shown == "" or shown == nm:
		game.arc.renames.erase(nm)
	else:
		game.arc.renames[nm] = shown


# --------------------------------------------------------------------------------- defence tab --

func _pick(items: Array, cur: int, on_pick: Callable, disabled := false) -> OptionButton:
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_override("font", Fonts.sans(500))
	ob.add_theme_font_size_override("font_size", 15)
	ob.custom_minimum_size.x = 170
	for it in items:
		ob.add_item(String(it))
	ob.selected = cur
	ob.disabled = disabled
	ob.pressed.connect(func(): _popup_open = true)
	ob.item_selected.connect(func(i):
		_popup_open = false
		on_pick.call(i)
		_sig = "")
	return ob


## Crew posts (who stands where, and how they shoot there) and barricades (cheap, worn out by the nights).
func _defence_tab() -> void:
	var siege = game.siege
	var locked: bool = siege.attacking
	body.add_child(_rich("Post a person on a spot of the compound. They shoot only the dead in the post's field of fire, take fewer bites in cover, and shoot better or worse by their traits; a coward on an open post can break and run. Somebody with no post is a tower guard. Nobody can be moved or built for during an attack.", 14))
	var people: Array = []
	for m in game.crew.members:
		if not m.def.has("play") and not m.def.has("ally"):
			people.append(m)
	for p in siege.posts.cfg.posts:
		var pid := String(p.id)
		var hold: Dictionary = siege.posts.holder(pid)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _box(Hud.PANEL_HI, Hud.OK if not hold.is_empty() else Hud.LINE2, 10))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		pc.add_child(hb)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(col)
		col.add_child(_lab(String(p.name), 18, Hud.INK, true))
		col.add_child(_lab("%s  Cover %d%%, reach %d tiles, field %d degrees%s." % [String(p.blurb), int(100.0 * float(p.cover)), int(p.range), int(2.0 * float(p.arc)), ", open ground" if bool(p.exposed) else ""], 13, Hud.INK2))
		col.add_child(_lab(siege.posts.fit_text(p), 13, DIM))
		var names: Array = ["Nobody"]
		var cur := 0
		for m in people:
			names.append(game.arc.dn(String(m.def.name)) + (" (%s)" % game.arc.events.trait_text(String(m.def.name)) if game.arc.events.trait_text(String(m.def.name)) != "" else ""))
			if m == hold:
				cur = names.size() - 1
		var on_pick := func(i):
			var res: Dictionary = {"ok": true, "why": ""}
			if i == 0:
				if not hold.is_empty():
					res = game.crew.assign_post(String(hold.def.id), "tower", econ, siege.attacking)
			else:
				res = game.crew.assign_post(String(people[i - 1].def.id), pid, econ, siege.attacking)
			if not bool(res.ok):
				toast(String(res.why), Hud.WARN)
			elif i > 0:
				did["post"] = true
		hb.add_child(_pick(names, cur, on_pick, locked))
		body.add_child(pc)
	body.add_child(_lab("Barricades", 22, Hud.INK, true))
	body.add_child(_rich("One in front of a fence segment. Each wears out as it works and a little every night, and is lost if the wire falls. Buy again when it is gone.", 14))
	var bars = siege.bars
	var segs: Array = []
	var names2: Array = []
	for s in siege.segs:
		segs.append(s)
		var b: Dictionary = bars.of(s)
		names2.append(String(s.name) + ((" - " + String(bars.defs[b.id].name)) if not b.is_empty() else "") + (" (down)" if float(s.hp) <= 0.0 else ""))
	_bseg = clampi(_bseg, 0, segs.size() - 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_lab("Segment", 15, Hud.INK2))
	row.add_child(_pick(names2, _bseg, func(i): _bseg = i))
	body.add_child(row)
	var cur_seg: Dictionary = segs[_bseg]
	for id in bars.order:
		var d: Dictionary = bars.defs[id]
		var can: Dictionary = bars.can_build(cur_seg, String(id))
		var r2 := HBoxContainer.new()
		r2.add_theme_constant_override("separation", 12)
		var tx := VBoxContainer.new()
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tx.add_child(_lab("%s   (%s)" % [String(d.name), bars.cost_text(String(id))], 16, Hud.INK))
		tx.add_child(_lab(String(d.blurb), 13, Hud.INK2))
		r2.add_child(tx)
		var bb := _btn("Build")
		bb.disabled = not bool(can.ok)
		bb.tooltip_text = String(can.why)
		bb.pressed.connect(func():
			var res: Dictionary = bars.build(cur_seg, String(id))
			toast(("Built: %s at the %s" % [String(d.name), String(cur_seg.name)]) if bool(res.ok) else String(res.why), Hud.INFO if bool(res.ok) else Hud.WARN)
			_sig = "")
		r2.add_child(bb)
		body.add_child(r2)
	var sm: String = bars.summary()
	body.add_child(_lab("Standing now: " + (sm if sm != "" else "none"), 14, Hud.INFO))


# ------------------------------------------------------------------------------- the first-day list --

## The checklist of the first managed day: under the top bar until every step is done, gone for good with Hide, and gone from day 3. Off in scripted runs like the guide (`--guide` shows it).
func _checklist(base_on: bool) -> void:
	var on: bool = base_on and not steps_off and int(econ.day) <= 2 and (game.guide.enabled or game.args.has("checklist"))
	did["water"] = did.get("water", false) or econ.st.has("water1")
	did["night"] = did.get("night", false) or game.siege.nights_started >= 1
	var left := 0
	var txt := ""
	for s in STEPS:
		var ok: bool = did.get(s[0], false)
		left += 0 if ok else 1
		txt += "%s  %s\n" % ["[x]" if ok else "[ ]", s[1]]
	if left == 0:
		steps_off = true
	steps_panel.visible = on and not panel.visible and not game.guide.panel.visible
	steps_lab.text = txt.strip_edges()
	steps_panel.reset_size()
	var tb: Control = game.topbar.plate
	steps_panel.position = Vector2(8.0, tb.position.y + tb.size.y + 10.0)


# ----------------------------------------------------------------------------- toasts and the card --

func toast(text: String, col: Color = Hud.INK) -> void:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", _box(Hud.PANEL, col, 9))
	var l := _lab(text, 16, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 290
	pc.add_child(l)
	toasts.add_child(pc)
	while toasts.get_child_count() > 4:
		toasts.get_child(0).queue_free()
		toasts.remove_child(toasts.get_child(0))
	var tw := pc.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(pc, "modulate:a", 0.0, 0.8)
	tw.tween_callback(pc.queue_free)


func _stage_card(stage: String) -> void:
	if card != null and is_instance_valid(card):
		card.queue_free()
	var v: Vector2 = game._vp()
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _box(Color(0.06, 0.09, 0.08, 0.95), Hud.ACCENT, 28, 8))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)
	var small := _lab("NEW STAGE", 16, Hud.INK3, true)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(small)
	var big := _lab(stage.to_upper(), 56, Hud.ACCENT, true)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(big)
	var built: Array = []
	var nx := ""    # the stage AFTER the one on the card, and what it still lacks (not the econ's own next, which a staged card can lag)
	var need: Array = []
	var stages: Array = econ.cfg.stages
	for i in stages.size():
		if String(stages[i].name) == stage:
			for b in stages[i].tiers:
				built.append(_pname("%s%d" % [b, int(stages[i].tiers[b])]))
			if i + 1 < stages.size():
				nx = String(stages[i + 1].name)
				for b in stages[i + 1].tiers:
					for tr in range(1, int(stages[i + 1].tiers[b]) + 1):
						econ._need(need, "%s%d" % [b, tr])
	var nxt: Array = need.map(func(id): return _pname(String(id)))
	var t := ("Reached with: " + ", ".join(built) + ".") if not built.is_empty() else "The prison is yours, bare walls and a gate."
	if nx == "":
		t += "\nThe radio is on the air. Hold the prison."
	elif not nxt.is_empty():
		t += "\nNext, %s: %s." % [nx, ", ".join(nxt)]
	var d := _rich(t, 18)
	d.custom_minimum_size.x = 520
	vb.add_child(d)
	root.add_child(card)
	card.size = Vector2(600, 0)
	card.position = Vector2((v.x - 600.0) / 2.0, v.y * 0.2)
	card.modulate.a = 0.0
	_card_tw = card.create_tween()
	_card_tw.tween_property(card, "modulate:a", 1.0, 0.3)
	_card_tw.tween_interval(1.9)
	_card_tw.tween_property(card, "modulate:a", 0.0, 0.6)
	_card_tw.tween_callback(card.queue_free)


# ------------------------------------------------------------------------------- the morning card --

## MORNING: after the economy's day change (6:00) the card waits for the night report (6:30), the story's cards and the morning event, then shows once. Not in scripted runs (`--board=morning` shows it).
func _morning_frame(base_on: bool, v: Vector2) -> void:
	if morning != null and morning.visible:
		morning.position = ((v - morning.size) / 2.0).round()
		if not base_on:
			morning.visible = false
		return
	if not econ.morning_new:
		return
	var h: float = fposmod(float(game.tod), 24.0)
	if h > 14.0 or game.arc.scripted or game.phase != "managed":    # (a stale one, or a run with no hands)
		econ.morning_new = false
		return
	var quiet: bool = base_on and h >= 6.6 and not panel.visible and not game.arc.story.card_open() and game.arc.event_pending.is_empty() and game.arc._queue.is_empty() and not game.siege.attacking and not game.siege._card.visible and not game.loadout.is_open
	if quiet:
		econ.morning_new = false
		_morning_show()


func _morning_show() -> void:
	if morning != null:
		morning.queue_free()
	var lg: Dictionary = econ.dawn_log
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", _box(Color(0.05, 0.075, 0.065, 0.985), Hud.ACCENT, 24, 8))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	vb.add_child(_lab("MORNING  -  DAY %d" % int(game.arc.day), 38, Hud.ACCENT, true))
	var rule := ColorRect.new()
	rule.color = Hud.LINE2
	rule.custom_minimum_size = Vector2(0, 1)
	vb.add_child(rule)
	var rows: Array = []
	var n: int = game.cleaner.rounds - _clean_rounds if game.cleaner != null else 0
	if game.cleaner != null:
		_clean_rounds = game.cleaner.rounds
		var left: int = game.cleaner.piles()
		rows.append(["Cleaned", ("%d rounds of cleaning" % n if n > 0 else "no cleaning") + ("; %d piles of trash left" % left if left > 0 else "; the base is tidy"), Hud.OK if left == 0 else Hud.WARN])
	var ate: Dictionary = lg.get("ate", {})
	var made: Dictionary = lg.get("made", {})
	rows.append(["Eaten", "%d food, %d water" % [roundi(float(ate.get("food", 0.0))), roundi(float(ate.get("water", 0.0)))], Hud.INK])
	rows.append(["Produced", "%d food, %d water" % [roundi(float(made.get("food", 0.0))), roundi(float(made.get("water", 0.0)))], Hud.INK])
	var bl: Array = lg.get("built", [])
	rows.append(["Built", ", ".join(bl) if not bl.is_empty() else "nothing finished", Hud.INK if not bl.is_empty() else DIM])
	var hurt: Array = []
	var edge: Array = []    # MORNING: the night cost morale: those who stood it (a horde night's guards) are on edge
	var dropped: bool = float(econ.morale) <= float(lg.get("morale0", econ.morale)) - 1.5
	var wire: int = int(game.siege.stats.get("killed", 0))    # (the siege kill counter of the night just over)
	for m in game.crew.members:
		if m.def.has("ally"):
			continue
		if game.arc.hurt_now(String(m.def.name)):
			hurt.append(String(m.def.name))
		elif dropped and m.def.has("stand") and wire > 0:
			edge.append(String(m.def.name))
	var mo := float(econ.morale)
	var mood := "morale %d of 100%s" % [int(mo), " (low: people are unhappy)" if mo < 40.0 else ""]
	if String(econ.last.get("left", "")) != "":
		mood += "; %s left in the night" % String(econ.last.left)
	rows.append(["People", mood, Hud.WARN if mo < 40.0 else Hud.INK])
	var bad: Array = hurt.map(func(n): return "%s (hurt or ill)" % n) + edge.map(func(n): return "%s (on edge)" % n)
	rows.append(["Slept badly", ", ".join(bad) if not bad.is_empty() else "nobody", Hud.WARN if not bad.is_empty() else Hud.OK])
	if wire > 0:
		rows.append(["Last night", "%d dead at the wire" % wire, Hud.INK])
	var horde: bool = game.arc.is_horde_night(int(game.arc.day))
	rows.append(["Tonight", "A HORDE NIGHT: the dead come in numbers, mend the walls and stock ammo." if horde else "A quiet night is expected.", Hud.DANGER_TEXT if horde else Hud.OK])
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 8)
	for r in rows:
		g.add_child(_lab(String(r[0]), 17, DIM, true))
		var l := _lab(String(r[1]), 18, r[2])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 520
		g.add_child(l)
	vb.add_child(g)
	vb.add_child(_lab("Press any key", 14, Hud.INK3))
	root.add_child(pc)
	morning = pc
	pc.reset_size()


# --------------------------------------------------------------------------------------- the sign --

## The needs sign by the gate, drawn into the game's overlay (world pixels).
func paint(c: CanvasItem) -> void:
	var t: float = float(game.TILE)
	var p := BOARD_AT * t
	c.draw_rect(Rect2(p + Vector2(-14, -2), Vector2(4, 22)), Color(0.25, 0.18, 0.1))
	c.draw_rect(Rect2(p + Vector2(10, -2), Vector2(4, 22)), Color(0.25, 0.18, 0.1))
	c.draw_rect(Rect2(p + Vector2(-20, -30), Vector2(40, 30)), Color(0.36, 0.26, 0.15))
	c.draw_rect(Rect2(p + Vector2(-17, -27), Vector2(34, 24)), Color(0.88, 0.84, 0.7))
	for i in 3:
		c.draw_line(p + Vector2(-13, -21 + i * 7), p + Vector2(11 - i * 4, -21 + i * 7), Color(0.3, 0.25, 0.2), 2.0)
	c.draw_string(ThemeDB.fallback_font, p + Vector2(-60, 34), "NEEDS", HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(1, 1, 0.8, 0.8))


# ----------------------------------------------------------------------------------- staging flags --

func _stage_flags() -> void:
	var a: Dictionary = game.args
	if _frames == 3 and String(a.get("econ", "")).begins_with("give:"):
		for kv in String(a.econ).trim_prefix("give:").split(","):
			var p := kv.split("=")
			if p.size() == 2:
				game.stores[p[0]] = float(game.stores.get(p[0], 0.0)) + float(p[1])
	if _frames == 6 and a.has("board-start"):
		econ.start(String(a["board-start"]))
	if _frames == 10 and a.has("board"):
		var bp := String(a.board).split(":")
		if bp.size() > 1:
			sel = bp[1]
		match bp[0]:
			"card":
				_stage_card("Shelter")
			"next":
				open("projects")
				what_next()
			"morning":
				econ.dawn_log = {"day": econ.day, "ate": {"food": 12.0, "water": 12.0}, "made": {"food": 8.0, "water": 14.0}, "built": ["Rain barrels"], "spoiled": 1.0}
				_morning_show()
			"toast":
				toast("Built: Rain barrels", Hud.OK)
				toast("Shortage: the base ran out of food.", Hud.WARN)
				toast("Tomas has left the prison.", Hud.DANGER_TEXT)
			_:
				open(bp[0])
