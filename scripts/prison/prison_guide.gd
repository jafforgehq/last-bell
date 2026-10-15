## EXPERIMENT (prison UI round 2): the first-run guide, four small cards in the clear phase and four on the first managed day. One PanelContainer at the left under the top bar with a title,
## a few plain lines, "Next" and "Skip guide" buttons. Dismissed for good (user://prison_ui.cfg) once the last card is closed or skipped; key H brings it back. It never covers a fight: while the
## player is in one (the top bar's fight rule: the dead within 9 tiles in the clear phase, an attack at night) the card is hidden and comes back 3 seconds after it is quiet.
## Off in headless runs and in every scripted check (--auto, --drive, --shot, --raid, --managed) unless `--guide[=card index]` is given (screens, tests); with the flag nothing is saved.
extends RefCounted

const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const AimMode := preload("res://scripts/aim_mode.gd")
const PATH := "user://prison_ui.cfg"

const CARDS := {
	"clear": [
		["Welcome to the prison", "You and three survivors hold the west breach. The old prison is full of the dead. Clear it zone by zone, then lock the gate behind you."],
		["Move, aim, shoot", "WASD walks. %AIM%. R reloads, F stabs with your knife, any time: it needs no ammo and is quiet, the wheel zooms, M shows the whole prison. The top bar keeps your ammo and meds."],
		["Clear the zones", "The map at the bottom right marks ten zones. A zone is clear when no dead are left in it. E searches containers for ammo, food and meds. The pulsing ring in the world and the Objectives list show where to go next."],
		["Your party", "Cole, Bea and Ike follow you and shoot. Their hearts are on the top bar. When one goes down, hold E beside them to revive them (1 med). Press O to fold the Objectives list, H to see this guide again."],
	],
	"managed": [
		["The prison is yours", "The top bar shows what the base holds: each stock with its cap and the change per day. Amber means less than 3 days left, red less than 1. Hover a chip for what makes and uses it; a click opens the needs board."],
		["Who does what", "The icon over each person is their job and the ring under their feet is their role colour. Walk close or point at them for the name. B opens the Base screen (the Base (B) button at the bottom does too); its Roster tab is where you change jobs: a base makes nothing when nobody holds its role."],
		["Build up", "Press B for the Base screen: Projects, Needs, Roster, Defence and Story tabs, with a line on each. On Projects, Start a project and it spends the cost now while the crew does the work (E at the workbench opens it too). On Defence, post a guard before 21:00. People only come from raids: look for the HELP! markers, get them to the pickup, and keep a free bed. Better stages bring more beds and more morale; the Objectives list says what is next."],
		["Raid and hold", "E at the gate or the truck takes you out to raid for what the needs board asks for. Every night at 21:00 the dead attack the fence: keep the walls mended and the stores stocked. The clock chip counts down to it."],
	],
}

var game
var panel: PanelContainer
var title: Label
var body: Label
var step: Label
var which := ""
var idx := 0
var enabled := false
var seen := {}
var _quiet := 0.0
var _cfg := ConfigFile.new()


func _init(g) -> void:
	game = g
	var a: Dictionary = g.args
	var scripted: bool = a.has("auto") or a.has("drive") or a.has("shot") or a.has("raid") or a.has("managed") or a.has("econ-lab") or a.has("siege")
	enabled = a.has("guide") or (DisplayServer.get_name() != "headless" and not scripted)
	if _cfg.load(PATH) == OK:
		seen = {"clear": bool(_cfg.get_value("guide", "clear", false)), "managed": bool(_cfg.get_value("guide", "managed", false))}
	if a.has("guide"):
		seen = {}
		idx = clampi(int(a.guide) if String(a.guide) != "1" else 0, 0, 3)
	var layer := CanvasLayer.new()
	layer.layer = 11
	g.add_child(layer)
	panel = PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.07, 0.06, 0.95), Hud.ACCENT, 12, 8))
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	step = _lab("", 12, Hud.INK3, true)
	title = _lab("", 20, Hud.ACCENT, true)
	body = _lab("", 14, Hud.INK, false)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 300
	vb.add_child(step)
	vb.add_child(title)
	vb.add_child(body)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	var nx := _btn("Next")
	nx.pressed.connect(_next)
	hb.add_child(nx)
	var sk := _btn("Skip guide")
	sk.pressed.connect(_skip)
	hb.add_child(sk)


func _box(bg: Color, line: Color, margin: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _lab(text: String, size: int, col: Color, cond: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.cond(700) if cond else Fonts.sans(500))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Fonts.cond(600))
	b.add_theme_font_size_override("font_size", 15)
	return b


func _phase_key() -> String:
	if game.mode != "base":
		return ""
	return "clear" if game.phase == "clear" else "managed"


func _next() -> void:
	idx += 1
	if idx >= (CARDS[which] as Array).size():
		_finish()


func _skip() -> void:
	_finish()


func _finish() -> void:
	seen[which] = true
	if not game.args.has("guide"):
		_cfg.set_value("guide", which, true)
		_cfg.save(PATH)
	which = ""
	panel.visible = false


func key(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode == KEY_H and not game.board.is_open():
		var k := _phase_key()
		if k == "":
			return false
		if which != "":
			_finish()
		else:
			which = k
			idx = 0
			seen[k] = false
		return true
	return false


func frame(dt: float) -> void:
	var k := _phase_key()
	if enabled and which == "" and k != "" and not bool(seen.get(k, false)) and not game.busy and game.frames > 210:
		which = k
	if which != "" and which != k:
		which = ""    # the phase changed under the card (the prison was secured)
	if which == "":
		panel.visible = false
		return
	if game.topbar.fighting():
		_quiet = 3.0
	else:
		_quiet = maxf(0.0, _quiet - dt)
	panel.visible = _quiet <= 0.0 and not game.busy and not game.board.is_open() and not game.pack.ui.is_open() and not game.loadout.is_open
	var cards: Array = CARDS[which]
	idx = clampi(idx, 0, cards.size() - 1)
	step.text = "GUIDE  %d / %d" % [idx + 1, cards.size()]
	title.text = String(cards[idx][0])
	body.text = String(cards[idx][1]).replace("%AIM%", AimMode.prison_words())
	panel.reset_size()
	var tb: Control = game.topbar.plate
	panel.position = Vector2(8.0, tb.position.y + tb.size.y + 10.0)
