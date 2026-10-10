## The WAIT UNTIL DUSK button and its words (One House, PACE): a sun setting in the toolbar, after the speed keys, and the key `.`. A VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`,
## `on_frame(dt)`, `on_event(e)`, `on_key(ev)`); the rules are scripts/town/wait_dusk.gd's (`sim.waiter`), and this part only asks them: it presses the button, runs `advance()` every frame while the wait lasts, ends
## it when a card or a page comes up or the player takes the wheel (a walk key, a click that fires, a key), and says in a toast why the wait stopped or could not begin.
##
## THE BUTTON. Before a claim it is disabled and its tooltip says why ("Claim a house first": the arrival day has its own dusk pressure). After it, it is always pressable: the reasons that stop a wait (the dead near,
## shots, somebody bleeding or infected, you far from home, the plan not ready) are given as a toast when it is pressed, and a wait that is on is lit and pressing it again stops it. The icon is drawn here (a half sun on a
## horizon with a small arrow down: `sunset_icon`); the rest is the toolbar's own look (`hud._speed_button`).
## THE QUESTION. With the dead coming tonight and the Build plan short of READY BY DUSK the rules ask "The plan is not ready. Wait anyway?" (`begin()` answers {"ask"}): a small card with two buttons, the game paused
## meanwhile (Enter or Y wait, Esc or N do not).
## STAGING (a screenshot has no hands): `--wait` begins the wait at once (a moment into the run), `--wait=dead` also puts one of the dead 18 tiles from her a second later (the wait stops on it and the toast says so).
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const WaitDusk := preload("res://scripts/town/wait_dusk.gd")

const KEY := KEY_PERIOD
const TIP := "Wait until the bell (.)"
const TIP_ON := "Waiting for the bell. Click, or any key, to stop"
const REFRESH_S := 0.2
## Where in the toolbar's row the button goes: after the four speed keys.
const INSERT_AT := 4
const ICON_PX := 64
## The frames a staged `--wait` waits for before it begins, and the dead one's (`--wait=dead`).
const STAGE_FRAME := 8
const STAGE_DEAD_FRAME := 40

var main
var hud
var button: Button
var card: PanelContainer
var card_label: Label
var _icon: TextureRect
var _t := 0.0
var _lit := false
var _disabled := false
var _tip := ""
var _asking := false
var _speed_before := 1
var _stage := ""
var _frames := 0


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null or hud.get("speed_panel") == null or _waiter() == null:
		return
	hud.icons["sunset"] = sunset_icon()
	button = hud._speed_button("sunset", TIP)
	button.name = "WaitButton"
	_icon = button.get_meta("icon")
	button.add_theme_stylebox_override("disabled", hud._lit_look(false))
	button.pressed.connect(press)
	var row: Control = hud.speed_panel.get_child(0)
	row.add_child(button)
	row.move_child(button, mini(INSERT_AT, row.get_child_count() - 1))
	_build_card()
	for arg in OS.get_cmdline_user_args():
		if String(arg) == "--wait" or String(arg).begins_with("--wait="):
			_stage = String(arg).trim_prefix("--wait=") if "=" in String(arg) else "now"
	_refresh()
	if hud.has_method("_layout_dock"):
		hud._layout_dock.call_deferred()


func _sim():
	return main.get("sim") if main != null else null


func _waiter():
	var s = _sim()
	return s.get("waiter") if s != null else null


# --------------------------------------------------------------------------- the icon --

## The picture of the button, white on clear like the toolbar's others (the toolbar colours it): a half sun on a horizon with its rays, and a small arrow down under the line. Drawn from distances, so the edges are soft.
static func sunset_icon() -> ImageTexture:
	var img := Image.create_empty(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	var horizon := 40.0
	var c := Vector2(32.0, horizon)
	var segs: Array = []
	# the horizon, the rays (five, over the sun), the arrow under the line
	segs.append([Vector2(6.0, horizon), Vector2(58.0, horizon), 2.6])
	for i in 5:
		var a := PI + PI * float(i) / 4.0
		var d := Vector2.from_angle(a)
		segs.append([c + d * 21.0, c + d * 29.0, 2.2])
	segs.append([Vector2(32.0, 47.0), Vector2(32.0, 58.0), 2.4])
	segs.append([Vector2(25.0, 52.0), Vector2(32.0, 59.0), 2.4])
	segs.append([Vector2(39.0, 52.0), Vector2(32.0, 59.0), 2.4])
	for y in ICON_PX:
		for x in ICON_PX:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var cover := 0.0
			# the sun: the disc cut by the horizon
			var dd := maxf(p.distance_to(c) - 14.0, p.y - horizon)
			cover = maxf(cover, clampf(0.5 - dd, 0.0, 1.0))
			for s in segs:
				cover = maxf(cover, clampf(0.5 - (_seg_dist(p, s[0], s[1]) - float(s[2])), 0.0, 1.0))
			if cover > 0.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, cover))
	return ImageTexture.create_from_image(img)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --------------------------------------------------------------------------- the card --

func _build_card() -> void:
	card = PanelContainer.new()
	card.set_meta("modal", true)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var st: StyleBox = hud._style(hud.PANEL, 8, hud.ACCENT, true, "toast")
	if st is StyleBoxFlat:
		st.border_width_left = 3
		st.border_width_top = 2
		st.border_width_right = 2
		st.border_width_bottom = 2
		st.content_margin_left = 16
		st.content_margin_right = 16
		st.content_margin_top = 12
		st.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", st)
	var col: VBoxContainer = hud._vbox(10)
	card_label = hud._label(WaitDusk.ASK_PLAN, Fonts.sans(600), 15, hud.INK)
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(card_label)
	var row: HBoxContainer = hud._hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var yes := RadioKit.small_button(hud, "Wait", 28.0, 14)
	yes.tooltip_text = "Wait for the bell anyway (Enter)"
	yes.pressed.connect(func(): _answer(true))
	row.add_child(yes)
	var no := RadioKit.small_button(hud, "Not yet", 28.0, 14)
	no.tooltip_text = "Go back to the plan (Esc)"
	no.pressed.connect(func(): _answer(false))
	row.add_child(no)
	col.add_child(row)
	card.add_child(col)
	card.visible = false
	hud.add_child(card)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.offset_top = -60.0
	card.offset_bottom = -60.0


func _ask(words: String) -> void:
	card_label.text = words
	card.visible = true
	_asking = true
	_speed_before = int(main.get("speed"))
	if _speed_before > 0:
		main._set_speed(0)


func _answer(yes: bool) -> void:
	if not _asking:
		return
	_asking = false
	card.visible = false
	if int(main.get("speed")) == 0 and _speed_before > 0:
		main._set_speed(_speed_before)
	if yes:
		_handle(_waiter().begin(true))


# ------------------------------------------------------------------------------ pressing --

## The button, the key: begins the wait, or stops the one that is on.
func press() -> void:
	var w = _waiter()
	if w == null or _asking:
		return
	if w.active():
		w.cancel("input")
		return
	if main.avatar_hands_off():
		return
	_handle(w.begin(false))


## What `begin` answered: a wait that is on, a question, or a reason (a toast).
func _handle(r: Dictionary) -> void:
	_refresh()
	if bool(r.get("ok", false)):
		if int(main.get("speed")) == 0:
			main._set_speed(1)
		return
	if r.has("ask"):
		_ask(String(r.ask))
		return
	var why := String(r.get("why", ""))
	if why == "":
		return
	var code := String(r.get("code", ""))
	hud.toast(why if code == "claim" else "Cannot wait: %s" % why, "info" if code == "claim" or code == "night" or code == "late" else "warn")


# ------------------------------------------------------------------------------ the frame --

func on_frame(dt: float) -> void:
	var w = _waiter()
	if w == null or button == null:
		return
	_frames += 1
	if _stage != "":
		_stage_step(w)
	if w.active():
		_watch_hands(w)
		if w.active():
			w.advance(dt)
	_t += dt
	if _t >= REFRESH_S:
		_t = 0.0
		_refresh()


## A card or a page that comes up, a walk key, a held trigger: the player has the wheel again.
func _watch_hands(w) -> void:
	if main.avatar_hands_off():
		w.cancel("card")
	elif bool(main.get("firing")) or main._walk_keys() != Vector2.ZERO:
		w.cancel("input")


func _refresh() -> void:
	var w = _waiter()
	if w == null or button == null:
		return
	var sim = _sim()
	var claimed: bool = sim.get("base") != null and bool(sim.base.claimed)
	var on: bool = w.active()
	var off: bool = not claimed
	var tip := TIP_ON if on else (TIP + ("\n" + WaitDusk.NEED_CLAIM if off else ""))
	if tip != _tip:
		_tip = tip
		button.tooltip_text = tip
	if off != _disabled:
		_disabled = off
		button.disabled = off
	if on != _lit:
		_lit = on
		button.add_theme_stylebox_override("normal", hud._lit_look(on))
	_icon.modulate = hud.ACCENT if on else (hud.INK3 if off else hud.INK2)


func on_event(e: Dictionary) -> void:
	if String(e.get("type", "")) != "wait" or hud == null:
		return
	if bool(e.get("on", false)):
		hud.toast("Waiting for the bell. Any key stops it")
	elif String(e.get("code", "")) == "bell":
		hud.toast("The bell is about to ring")
	else:
		var code := String(e.get("code", ""))
		hud.toast("Stopped: %s" % String(e.get("why", "")), "info" if code == "input" or code == "card" else "warn")
	_refresh()


## `.` begins or stops the wait; with a question up Enter or Y says yes and Esc or N no; any other key (but a modifier) ends a wait that is on and goes on to what it was for.
func on_key(ev: InputEvent) -> bool:
	if main == null or hud == null or button == null or not (ev is InputEventKey):
		return false
	var k := ev as InputEventKey
	if not k.pressed or k.echo:
		return false
	var code: Key = k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if _asking:
		if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_Y:
			_answer(true)
			return true
		if code == KEY_ESCAPE or code == KEY_N:
			_answer(false)
			return true
		# (the game is paused for the question: the speed keys are not let to unpause it)
		return code == KEY_SPACE or code == KEY_1 or code == KEY_2 or code == KEY_3 or code == KEY_4    # (4: INV2's fourth quick slot)
	var w = _waiter()
	if w == null:
		return false
	if code == KEY and not (k.ctrl_pressed or k.alt_pressed or k.meta_pressed):
		press()
		return true
	if w.active() and not [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK].has(code):
		w.cancel("input")
	return false


# --------------------------------------------------------------------------------- staging --

func _stage_step(w) -> void:
	if _frames == STAGE_FRAME and not w.active():
		w.hold_ms = 0
		press()
	if _stage == "dead" and _frames == STAGE_DEAD_FRAME:
		var sim = _sim()
		var me = sim.avatar.player()
		if me != null:
			sim.spawn(me.x + 18.0, me.y, "wander")
