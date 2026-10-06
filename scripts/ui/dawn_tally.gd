## The dawn tally (One House, NIGHTEV): a card on the first frames of each morning that tells the night in four lines and the day's first thing to do. A VIEW PART of the
## town's facade (scripts/town/town_game.gd). (The classic game's morning assembly is scripts/ui/dawn_card.gd, the storyteller's, which is off in the town: this is the town's.)
##
##   title    "Morning" (a quiet night), or "The night is over" after one when the dead came (`scenario.attacks_on()` at any time of it)
##   rows     after an attack: Walls held (3 of 4 sections), Dead put down, Hurt, Lost; after a quiet night only what happened (kills, the hurt, the lost), or "A quiet night."
##            then "Fence needs mending: 2 sections" when a section is down or worn (the avatar's mend rule: under 95% of its hit points) and "Low: food (1 day)" when stores run short
##   today    the objective's words (`scenario.objective()`), the new day's first suggestion
##   button   "Good morning" (a click, Enter or Space; the key goes to the card and not to the game while it is up), and it goes by itself after `SHOW_S` seconds: a bar runs down
##
## It is NON-MODAL: the game does not pause, WASD still walks (a player in a fight at dawn is never held), the card sits clear of the avatar (below her, or above when there is no
## room: she is where the camera is), and it is put away while a menu or a page is over the game. It waits for the sleep fade ("You slept until dawn") to end, so the two never
## stack, and the morning briefing's card (the HUD's) waits for it as it waits for the classic dawn card (`hud.briefing_gate`). After the FIRST held attack the run is over and
## the end card has the screen: no tally then (the card waits `DELAY_S` of rules time after the day begins, for the rules to judge the night, and is dropped on `held`, `over`).
##
## THE NIGHT'S NUMBERS are the card's own record, kept by looking each frame (the storyteller that would keep them is off in the town, and nothing in the rules is written): from the
## first moment of dusk to the day's start, the kills (`sim.kills`), who was hurt (downed, or hit points down by `HURT_HP`), who is dead or turned, which sections went down
## (`perimeter.sections()` and the event `slot_lost`). A run loaded in the middle of a night begins its record where it is.
##
## DEBUG: `--moment=dawn` plays the rules, idle, from now through the next night to the first morning (every event told to this part), then the card is up; `--moment=sleep`
## puts the avatar to bed (`sim.sleep.begin`) and the card comes after the sleep fade; a screenshot run takes its shot about a second after the card is up.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")

## Real seconds the card stays; its fade in and out; rules seconds after the day begins before it comes (the night is judged by then).
const SHOW_S := 10.0
const FADE_S := 0.3
const DELAY_S := 0.6
## The card's width (less in a narrow window), the gap from the screen's edge, and the room kept clear round the avatar: above her head and below her feet (her name).
const CARD_W := 420.0
const CARD_W_MIN := 300.0
const EDGE := 12.0
const TOP_MIN := 78.0
const HEAD_TILES := 1.25
const ABOVE_PX := 30.0
const BELOW_PX := 30.0
## The width of the labels' column of a row.
const LABEL_W := 118.0
## A section is worn under this share of its hit points (the avatar's own rule: scripts/sim/nights.gd SOUND); hit points lost to be named hurt; days of food or water that are "low".
const SOUND := 0.95
const HURT_HP := 15.0
const LOW_DAYS := 1.5
## Frames between the card being up a moment and a debug shot.
const SHOT_AFTER_FRAMES := 30
const MAX_DEBUG_STEPS := 130000

var main
var hud
var card: PanelContainer
## What the card was made from (the tests read it): {"day", "night", "attack", "kills", "walls_total", "walls_held", "hurt": [names], "lost": [names]}.
var tally := {}
## The words of the rows the card shows now: [[label, value]...] ("" label: a line of its own).
var shown_rows: Array = []
var title_text := ""
var open := false

var _bar: Control
var _title: Label
var _wrap_inner: Array = []
var _wrap_value: Array = []
var _left := 0.0
var _opened_s := 0.0
## The night's record.
var _in_night := false
var _night_day := -1
var _kills0 := 0
var _alive0 := {}
var _hp0 := {}
var _hp_low := {}
var _fell := {}
var _hurt := {}
var _attack := false
## The morning that waits for its card.
var _pending := false
var _pending_t0 := 0.0
var _told_day := -1
var _last_day := -1
var _started := false
var _debug := ""
var _debug_done := false
var _shot_asked := false


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--moment="):
			_debug = String(arg).trim_prefix("--moment=")
	# (the morning briefing waits for the classic dawn card, up or about to be: it waits for this one too)
	if "briefing_gate" in hud:
		var prev: Callable = hud.briefing_gate
		hud.briefing_gate = func() -> bool:
			return (prev.is_valid() and bool(prev.call())) or open or _pending


func _sim():
	return main.get("sim") if main != null else null


func _scenario():
	var sim = _sim()
	return sim.get("scenario") if sim != null else null


func _attacks() -> bool:
	var sc = _scenario()
	return sc != null and sc.has_method("attacks_on") and bool(sc.attacks_on())


# ----------------------------------------------------------------------- the record --

func _sections() -> Array:
	var sim = _sim()
	var per = sim.get("perimeter") if sim != null else null
	var out: Array = []
	if per == null or not per.has_method("sections"):
		return out
	for s in per.sections():
		var kind := String(s.get("kind", ""))
		if kind == "door" or kind == "fence" or kind == "gate":
			out.append(s)
	return out


func _begin_night() -> void:
	var sim = _sim()
	_in_night = true
	_night_day = int(sim.day)
	_kills0 = int(sim.kills)
	_attack = false
	_fell = {}
	_hurt = {}
	_alive0 = {}
	_hp0 = {}
	_hp_low = {}
	for p in sim.people:
		if not p.dead and not p.turned:
			_alive0[String(p.id)] = String(p.first)
			_hp0[String(p.id)] = float(p.hp)
			_hp_low[String(p.id)] = float(p.hp)


## A look at the night as it stands (every frame while it lasts, and once more at the morning).
func _poll() -> void:
	var sim = _sim()
	if _attacks():
		_attack = true
	for p in sim.people:
		if p.dead or p.turned:
			continue
		var id := String(p.id)
		if not _hp0.has(id):
			continue    # (someone who came after the dusk: not part of this night's record)
		_hp_low[id] = minf(float(_hp_low.get(id, p.hp)), float(p.hp))
		if p.downed or float(_hp0[id]) - float(_hp_low[id]) >= HURT_HP:
			_hurt[id] = String(p.first)
	for s in _sections():
		if int(s.get("state", 0)) == 3:
			_fell[String(s.get("slot", ""))] = true


func _track() -> void:
	var sim = _sim()
	var phase := String(sim.phase)
	if phase == "dusk" or phase == "night" or phase == "dawn":
		if not _in_night:
			_begin_night()
		_poll()
	elif _in_night and int(sim.day) != _night_day:
		_dawn(int(sim.day))    # (the day began and no `day_start` was told: the same morning)


## The morning begins: the night's numbers are taken now, and the card waits its turn.
func _dawn(day: int) -> void:
	var sim = _sim()
	if day == _told_day or sim == null:
		return
	_told_day = day
	if _in_night:
		_poll()
	var had_night := _in_night
	_in_night = false
	if String(sim.over) != "":
		return
	tally = _make_tally(day, had_night)
	_pending = true
	_pending_t0 = float(sim.t)


func _make_tally(day: int, had_night: bool) -> Dictionary:
	var sim = _sim()
	var secs := _sections()
	var fell := 0
	for s in secs:
		if _fell.has(String(s.get("slot", ""))):
			fell += 1
	var lost: Array = []
	for id in _alive0:
		for p in sim.people:
			if String(p.id) == id and (p.dead or p.turned):
				lost.append(String(p.first))
	var hurt: Array = []
	for id in _hurt:
		if not lost.has(String(_hurt[id])):
			hurt.append(String(_hurt[id]))
	return {
		"day": day, "night": had_night, "attack": _attack and had_night, "kills": maxi(0, int(sim.kills) - _kills0) if had_night else 0,
		"walls_total": secs.size(), "walls_held": maxi(secs.size() - fell, 0), "hurt": hurt, "lost": lost,
	}


# --------------------------------------------------------------------------- events --

func on_event(e: Dictionary) -> void:
	var sim = _sim()
	if sim == null:
		return
	match String(e.get("type", "")):
		"day_start":
			_dawn(int(e.get("day", sim.day)))
		"slot_lost":
			_fell[String(e.get("slot", ""))] = true
		"held", "over":
			_pending = false    # (the first attack is held, or the run is lost: the end card has the screen)
			_close(true)


func modal() -> bool:
	return false


## Enter or Space puts the card away (the key is the card's while it is up).
func on_key(ev: InputEvent) -> bool:
	if not open or card == null or not card.visible or not (ev is InputEventKey):
		return false    # (a card hidden under a menu or a page does not take the keys)
	var k := ev as InputEventKey
	if not k.pressed or k.echo:
		return false
	var code: Key = k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
		_close(false)
		return true
	return false


# --------------------------------------------------------------------------- frames --

func on_frame(dt: float) -> void:
	if hud == null or main == null:
		return
	var sim = _sim()
	if sim == null or sim.get("scenario") == null:
		return
	if not _started:
		_started = true
		_last_day = int(sim.day)
	if _debug != "" and not _debug_done:
		_debug_done = true
		_debug_start()
	_track()
	_try_show()
	if open:
		_run(dt)
	if _debug != "" and open and not _shot_asked and _opened_s >= 0.9 and String(main.get("shot_path")) != "":
		_shot_asked = true
		main.shot_frames = int(main.frame_count) + SHOT_AFTER_FRAMES


## What keeps the card from coming now: a menu, a page, the sleep fade or a sleep in progress, the end of the run.
func _blocked() -> bool:
	var sim = _sim()
	if bool(main.get("menu_open")) or hud.get("game_over") != null or (hud.has_method("modal_open") and bool(hud.modal_open())):
		return true
	var sl = sim.get("sleep")
	if sl != null and sl.has_method("active") and bool(sl.active()):
		return true
	var town = main.get("town")
	var fade = town.part("sleep_fade") if town != null and town.has_method("part") else null
	return fade != null and fade.has_method("active") and bool(fade.active())


func _try_show() -> void:
	if not _pending or open:
		return
	var sim = _sim()
	if String(sim.over) != "" or int(sim.day) != int(tally.get("day", -1)) or float(sim.hour) >= 12.0:
		_pending = false    # (the run is over, or the morning has gone: it is not news any more)
		return
	if float(sim.t) - _pending_t0 < DELAY_S or _blocked():
		return
	_pending = false
	_open()


# ------------------------------------------------------------------------------ rows --

## The sections of the base that need mending now: [count, the word for them ("Fence" or "Doors")].
func _mending() -> Array:
	var n := 0
	var fence := false
	for s in _sections():
		var kind := String(s.get("kind", ""))
		if kind == "fence" or kind == "gate":
			fence = true
		if int(s.get("state", 0)) == 3 or float(s.get("hp", 0.0)) < float(s.get("max_hp", 1.0)) * SOUND:
			n += 1
	return [n, "Fence" if fence else "Doors"]


## "Low: food (1 day), water (1 day)" or "".
func _stores_low() -> String:
	var sim = _sim()
	var sup = sim.get("supplies")
	if sup == null or not sup.has_method("days_left"):
		return ""
	var bits: Array = []
	for kind in ["food", "water"]:
		var d := float(sup.days_left(kind))
		if d < LOW_DAYS:
			bits.append("%s (%s)" % [kind, "under a day" if d < 1.0 else "1 day"])
	return ("Low: %s" % ", ".join(bits)) if not bits.is_empty() else ""


static func _plural(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


static func _names(list: Array, none: String) -> String:
	if list.is_empty():
		return none
	if list.size() == 1:
		return String(list[0])
	return "%s and %s" % [", ".join(list.slice(0, list.size() - 1)), String(list[list.size() - 1])]


## The rows of the card from the night's numbers and the rules as they stand: [[label, value, tone]...], label "" for a line that stands alone. Tones: "", "ok", "warn", "bad".
func rows_for(t: Dictionary) -> Array:
	var rows: Array = []
	var attack := bool(t.get("attack", false))
	var kills := int(t.get("kills", 0))
	var hurt: Array = t.get("hurt", [])
	var lost: Array = t.get("lost", [])
	var total := int(t.get("walls_total", 0))
	if attack:
		if total > 0:
			var held := int(t.get("walls_held", 0))
			rows.append(["Walls held", "%d of %s" % [held, _plural(total, "section", "sections")], "ok" if held == total else "warn"])
		rows.append(["Dead put down", str(kills), ""])
		rows.append(["Hurt", _names(hurt, "nobody"), "warn" if not hurt.is_empty() else ""])
		rows.append(["Lost", _names(lost, "nobody"), "bad" if not lost.is_empty() else ""])
	else:
		if kills > 0:
			rows.append(["Dead put down", str(kills), ""])
		if not hurt.is_empty():
			rows.append(["Hurt", _names(hurt, ""), "warn"])
		if not lost.is_empty():
			rows.append(["Lost", _names(lost, ""), "bad"])
		if rows.is_empty():
			rows.append(["", "A quiet night.", ""])
	var mend := _mending()
	if int(mend[0]) > 0:
		rows.append(["", "%s needs mending: %s." % [String(mend[1]), _plural(int(mend[0]), "section", "sections")], "warn"])
	var low := _stores_low()
	if low != "":
		rows.append(["", low + ".", "warn"])
	return rows


# ------------------------------------------------------------------------------ card --

func _tone_color(tone: String) -> Color:
	match tone:
		"ok":
			return hud.OK
		"warn":
			return hud.WARN
		"bad":
			return hud.DANGER_TEXT
	return hud.INK


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = hud.LINE2
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _open() -> void:
	var sim = _sim()
	_close(true)
	var t := tally
	var after_attack := bool(t.get("attack", false))
	title_text = "The night is over" if after_attack else "Morning"
	card = hud._panel(hud._style(hud.PANEL, 6, hud.LINE2, true, "panel"))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var st: StyleBox = card.get_theme_stylebox("panel")
	if st is StyleBoxFlat:
		st.content_margin_left = 20
		st.content_margin_right = 20
		st.content_margin_top = 14
		st.content_margin_bottom = 14
	var col: VBoxContainer = hud._vbox(7)
	card.add_child(col)
	col.add_child(hud._label("DAY %d" % int(t.get("day", sim.day)), Fonts.cond(600, 2), 14, hud.ACCENT))
	_title = hud._label(title_text, Fonts.cond(700), 32, hud.INK)
	col.add_child(_title)
	col.add_child(_rule())
	_wrap_inner = []
	_wrap_value = []
	shown_rows = []
	for r in rows_for(t):
		_add_row(col, String(r[0]), String(r[1]), String(r[2]))
		shown_rows.append([String(r[0]), String(r[1])])
	var sc = _scenario()
	var o := {}
	if sc != null and sc.has_method("objective"):
		var got = sc.objective()
		if got is Dictionary:
			o = got
	if String(o.get("text", "")) != "":
		col.add_child(_rule())
		col.add_child(hud._label("TODAY", Fonts.cond(600, 2), 14, hud.INK3))
		var ot: Label = hud._label(String(o.get("text", "")), Fonts.sans(600), 16, hud.INK)
		ot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(ot)
		_wrap_inner.append(ot)
		if String(o.get("sub", "")) != "":
			var osub: Label = hud._label(String(o.get("sub", "")), Fonts.sans(400), 14, hud.INK2)
			osub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(osub)
			_wrap_inner.append(osub)
		shown_rows.append(["Today", String(o.get("text", ""))])
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 4)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	col.add_child(_bar)
	var foot: HBoxContainer = hud._hbox(10)
	var hint: Label = hud._label("Enter or Space", Fonts.sans(400), 13, hud.INK3)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hint)
	foot.add_child(hud._spacer())
	var ok: Button = hud._button("Good morning", true)
	ok.pressed.connect(func(): _close(false))
	foot.add_child(ok)
	col.add_child(foot)
	card.modulate.a = 0.0
	hud.add_child(card)
	open = true
	_left = SHOW_S
	_opened_s = 0.0
	_place()
	var snd = main.get("sound")
	if snd != null and snd.has_method("ui"):
		snd.ui("ui_open", 0.6)


func _add_row(col: VBoxContainer, label: String, value: String, tone: String) -> void:
	var color := _tone_color(tone)
	if label == "":
		var line: Label = hud._label(value, Fonts.sans(600), 15, color)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(line)
		_wrap_inner.append(line)
		return
	var row: HBoxContainer = hud._hbox(8)
	var l: Label = hud._label(label.to_upper(), Fonts.cond(600, 1), 14, hud.INK3)
	l.custom_minimum_size.x = LABEL_W
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(l)
	var v: Label = hud._label(value, Fonts.sans(600), 16, color)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	_wrap_value.append(v)
	col.add_child(row)


func _draw_bar() -> void:
	if _bar == null:
		return
	var r := Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_rect(r, Color(hud.INK, 0.12))
	_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(_left / SHOW_S, 0.0, 1.0), r.size.y)), Color(hud.ACCENT, 0.85))


func _run(dt: float) -> void:
	if card == null or not is_instance_valid(card):
		open = false
		return
	var covered := _blocked_by_page()
	card.visible = not covered
	if covered:
		return    # (the clock of the card waits while a page is over it)
	_left -= dt
	_opened_s += dt
	if _left <= 0.0:
		_close(false)
		return
	var calm: bool = hud.has_method("_calm") and bool(hud._calm())
	if calm:
		card.modulate.a = 1.0
	else:
		card.modulate.a = clampf(minf(_opened_s / FADE_S, _left / FADE_S), 0.0, 1.0)
	_bar.queue_redraw()
	_place()


## A menu or a page is over the game: the card is put out of the way.
func _blocked_by_page() -> bool:
	return bool(main.get("menu_open")) or (hud.has_method("modal_open") and bool(hud.modal_open())) or hud.get("game_over") != null


func _close(quiet: bool) -> void:
	open = false
	if card != null and is_instance_valid(card):
		card.queue_free()
	card = null
	_bar = null
	if not quiet:
		var snd = main.get("sound") if main != null else null
		if snd != null and snd.has_method("ui"):
			snd.ui("ui_close", 0.5)


# --------------------------------------------------------------------------- place --

## The avatar in the HUD's pixels (her feet) and the pixels to the tile.
func _avatar_screen() -> Array:
	var sim = _sim()
	var me = sim.avatar.player() if sim.get("avatar") != null else null
	var z := float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	if me == null:
		return [hud.size * 0.5, z]
	var at := Vector2(me.x, me.y)
	if main.has_method("view_pos"):
		at = main.view_pos(me)
	var cam: Vector2 = main.get("cam_center") if main.get("cam_center") is Vector2 else Vector2.ZERO
	return [(at - cam) * z + hud.size * 0.5, z]


## The card's size and place: centred, below the avatar when there is room (her name is under her feet), above her when there is not.
func _place() -> void:
	if card == null:
		return
	var vp: Vector2 = hud.size
	var w := clampf(minf(CARD_W, vp.x - 2.0 * EDGE), minf(CARD_W_MIN, vp.x - 2.0 * EDGE), CARD_W)
	var margin: float = card.get_theme_stylebox("panel").get_minimum_size().x
	for c in _wrap_inner:
		RadioKit.wrap_at(c, w - margin)
	for c in _wrap_value:
		RadioKit.wrap_at(c, w - margin - LABEL_W - 8.0)
	card.custom_minimum_size.x = w
	var h := card.get_combined_minimum_size().y
	card.size = Vector2(w, h)
	var at := _avatar_screen()
	var feet: Vector2 = at[0]
	var z: float = at[1]
	var below := feet.y + BELOW_PX
	var above := feet.y - HEAD_TILES * z - ABOVE_PX
	var y := below
	if below + h > vp.y - EDGE:
		# (above her: the bottom of the card clear of her head and the "YOU" over it)
		if above - h >= TOP_MIN:
			y = above - h
		elif vp.y - EDGE - below >= above - TOP_MIN:
			y = maxf(TOP_MIN, vp.y - EDGE - h)    # (neither fits: the side with more room, over her rather than off the screen)
		else:
			y = TOP_MIN
	card.position = Vector2(roundf((vp.x - w) * 0.5), roundf(y))


# --------------------------------------------------------------------------- debug --

func _debug_start() -> void:
	var sim = _sim()
	match _debug.split(":")[0]:
		"dawn":
			var start_day := int(sim.day)
			var steps := 0
			var tail := -1
			while steps < MAX_DEBUG_STEPS and String(sim.over) == "":
				sim.update(1.0 / 30.0)
				steps += 1
				var evs: Array = sim.events.duplicate()
				sim.events.clear()
				for e in evs:
					on_event(e)
				_track()
				if int(sim.day) > start_day and tail < 0:
					tail = 0
				if tail >= 0:
					tail += 1
					if tail > 30:
						break    # (a second of the morning: the rules have judged the night)
			var sc = _scenario()
			print("--moment=dawn: %d steps, day %d, over '%s', first night '%s', tally %s" % [steps, int(sim.day), String(sim.over), String(sc.first_night_result()) if sc != null and sc.has_method("first_night_result") else "?", str(tally)])
		"sleep":
			var r: Dictionary = sim.sleep.begin("dawn")
			print("--moment=sleep: %s" % str(r))
