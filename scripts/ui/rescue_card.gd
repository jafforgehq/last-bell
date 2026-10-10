## The rescue card (One House, WP4): what E at a survivor opens, a view part of the town's facade. A small board low in the window: their portrait, name and
## role, why they are hiding, what they say, and what you can answer (Come with me, Stay here, I will come back, Take this), each with its reason in amber
## when it is not on offer. While a dead one is still in their room they say so and the card has no answer to give. It is built like talk_card.gd: the HUD
## lends its looks (`host._style`, `_label`, `_button`...), nothing here changes the rules but through `sim.rescue.choose`.
##
## It holds the avatar's hands while it is up (`modal()`, asked by the facade): 1, 2, 3 or a click answers, Esc, E or the cross puts it away. It does not pause
## the game. It goes by itself when the avatar is lost or far from them. After "Come with me" or "Stay here" it keeps their answer on the board a moment.
##
## The part's calls (all optional, the facade asks each part): `on_ready(main)`, `on_frame(dt)`, `on_event(e)`, `modal()`, `on_key(ev)`.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const MenuKit := preload("res://scripts/ui/menu_kit.gd")

const CARD_W := 340.0
## The talk is over when the avatar is this far (tiles) from the survivor (the rules' own TALK_LEAVE).
const LEAVE := 3.5
## How long (real milliseconds) an answer that ends the talk stays up.
const REPLY_MS := 1500
## The gap between the board and the foot of the window.
const LIFT := 150.0

var main
var host
var panel: PanelContainer
var portrait: TextureRect
var name_label: Label
var role_label: Label
var hide_label: Label
var line_label: Label
var reply_label: Label
var choices_box: VBoxContainer
## The survivor the card is for ("" when it is shut), its choice buttons by id, and the end of a closing reply (0: none).
var shown := ""
var buttons := {}
var _closing_at := 0
var _sig := ""


func on_ready(m) -> void:
	main = m
	host = m.get("hud") if m != null else null


func _sim():
	return main.get("sim") if main != null else null


func _rescue():
	var s = _sim()
	return s.get("rescue") if s != null else null


# ------------------------------------------------------------------------ the part --

func modal() -> bool:
	return shown != ""


func is_open() -> bool:
	return shown != ""


func on_event(e: Dictionary) -> void:
	var t := String(e.get("type", ""))
	if t == "rescue_talk":
		open(String(e.get("id", "")))
	elif t == "rescue_seen" and host != null and host.has_method("toast"):
		host.toast("Someone is alive in here", "info")


func on_frame(_dt: float) -> void:
	if shown == "":
		return
	if _closing_at > 0 and Time.get_ticks_msec() >= _closing_at:
		close()
		return
	var why := _ending()
	if why != "":
		close()
		return
	refresh()
	_place()


## 1, 2, 3 answer; Esc and E put the card away. True when the key was the card's.
func on_key(ev: InputEvent) -> bool:
	if shown == "" or not ev is InputEventKey or not ev.pressed or ev.echo:
		return false
	var code: int = ev.keycode
	if code == KEY_ESCAPE or code == KEY_E:
		close()
		return true
	var i := code - KEY_1
	if i >= 0 and i < 3 and _closing_at == 0:
		var m := _model()
		var list: Array = m.get("choices", [])
		if i < list.size() and bool(list[i].ok):
			answer(String(list[i].id))
		return true
	if i >= 0 and i < 9:
		return true    # (INV2: a digit is the card's while it is up, so the fourth is not a quick slot used by mistake)
	return false


# ----------------------------------------------------------------------- open, close --

func open(id: String) -> void:
	var r = _rescue()
	if r == null or host == null or not host.has_method("_label") or r.card(id).is_empty():
		return
	_build()
	shown = id
	_closing_at = 0
	_sig = ""
	reply_label.visible = false
	panel.visible = true
	refresh()
	_place()


func close() -> void:
	shown = ""
	_closing_at = 0
	if panel != null:
		panel.visible = false


## The card as the rules have it now (the survivor's own words, the answers and why one is out of reach).
func _model() -> Dictionary:
	var r = _rescue()
	return r.card(shown) if r != null and shown != "" else {}


func refresh() -> void:
	if _closing_at > 0:
		return    # (their answer is on the board: it is not redrawn)
	var m := _model()
	if m.is_empty():
		close()
		return
	var sig := "%s|%s|%s" % [String(m.line), str(m.choices), str(m.blocked)]
	if sig == _sig:
		return
	_sig = sig
	name_label.text = String(m.name)
	role_label.text = String(m.role)
	hide_label.text = String(m.hiding)
	hide_label.visible = String(m.hiding) != ""
	line_label.text = "\"%s\"" % String(m.line)
	if String(m.portrait) != "" and ResourceLoader.exists(String(m.portrait)):
		portrait.texture = load(String(m.portrait))
	for c in choices_box.get_children():
		choices_box.remove_child(c)
		c.queue_free()
	buttons = {}
	var n := 0
	for ch in m.choices:
		n += 1
		var row: VBoxContainer = host._vbox(1)
		var b: Button = host._button("%d   %s" % [n, String(ch.text)], String(ch.id) == "come" and bool(ch.ok))
		b.custom_minimum_size = Vector2(CARD_W - 28.0, 34)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not bool(ch.ok)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(answer.bind(String(ch.id)))
		row.add_child(b)
		if not bool(ch.ok) and String(ch.why) != "":
			var why: Label = host._label(String(ch.why), Fonts.sans(400), 12, host.WARN)
			row.add_child(why)
		choices_box.add_child(row)
		buttons[String(ch.id)] = b


## A choice was made: the rules answer, and the board keeps the answer (a gift leaves the talk open, the others end it).
func answer(choice: String) -> Dictionary:
	var r = _rescue()
	if r == null or shown == "" or _closing_at > 0:
		return {}
	var out: Dictionary = r.choose(shown, choice)
	if not bool(out.get("ok", false)):
		return out
	reply_label.text = "\"%s\"" % String(out.line)
	reply_label.visible = String(out.line) != ""
	_sig = ""
	if choice == "gift":
		refresh()
	else:
		for c in choices_box.get_children():
			choices_box.remove_child(c)
			c.queue_free()
		buttons = {}
		_closing_at = Time.get_ticks_msec() + REPLY_MS
	return out


## Why the talk is over now ("" while it goes on): the avatar is gone, down or far from them, or they are not to be talked to any more.
func _ending() -> String:
	var s = _sim()
	var r = _rescue()
	if s == null or r == null:
		return "lost"
	var me = s.avatar.player() if s.get("avatar") != null and String(s.player_id) != "" else null
	if me == null or me.dead or me.turned or me.downed or me.away != null:
		return "lost"
	var rec: Dictionary = r.get_record(shown)
	if rec.is_empty() or Vector2(me.x, me.y).distance_to(rec.pos) > LEAVE:
		return "far"
	return ""


# -------------------------------------------------------------------------- build --

func _build() -> void:
	if panel != null:
		return
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", host._style(host.PANEL, 6, host.LINE, true, "panel_slim"))
	panel.custom_minimum_size.x = CARD_W
	panel.visible = false
	host.add_child(panel)
	var v: VBoxContainer = host._vbox(8)
	panel.add_child(v)
	var head: HBoxContainer = host._hbox(10)
	portrait = host._pic(null)
	head.add_child(portrait)
	var titles: VBoxContainer = host._vbox(1)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label = host._label("", Fonts.cond(700), 21, host.INK)
	role_label = host._label("", Fonts.sans(400), 13, host.INK2)
	titles.add_child(name_label)
	titles.add_child(role_label)
	head.add_child(titles)
	var x: Button = host._button("x")
	x.custom_minimum_size = Vector2(30, 26)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.tooltip_text = "Close (E or Esc)"
	x.pressed.connect(close)
	head.add_child(x)
	v.add_child(head)
	hide_label = host._label("", Fonts.sans(400), 12, host.INK3)
	hide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hide_label.custom_minimum_size.x = CARD_W - 28.0
	v.add_child(hide_label)
	line_label = host._label("", Fonts.sans(600), 15, host.INK)
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size.x = CARD_W - 28.0
	v.add_child(line_label)
	choices_box = host._vbox(5)
	v.add_child(choices_box)
	reply_label = host._label("", Fonts.sans(600), 14, host.OK)
	reply_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reply_label.custom_minimum_size.x = CARD_W - 28.0
	reply_label.visible = false
	v.add_child(reply_label)


## Low and in the middle of the window, over the people's boards.
func _place() -> void:
	if panel == null or host == null:
		return
	var card := panel.get_combined_minimum_size()
	panel.size = card
	panel.position = Vector2(roundf((host.size.x - card.x) * 0.5), maxf(8.0, host.size.y - card.y - LIFT))
