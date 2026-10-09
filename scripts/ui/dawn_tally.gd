## The morning summary (One House, NIGHTEV, RULES2): ONE card on the first frames of each morning that tells what happened in the night, the stores now and what changed, who does what,
## the weather with the clock to dusk, and the one thing that matters next. A SUMMARY AND NOTHING ELSE: nothing to choose, no button that does anything but put it away, nothing that waits for
## it. A VIEW PART of the town's facade (scripts/town/town_game.gd). (The classic game's morning assembly is scripts/ui/dawn_card.gd, the storyteller's, which is off in the town; the school's
## briefing card with its priority chips, scripts/ui/briefing_card.gd, is off in the town too: `briefing` and `priorities` are 99 in `modules_from_crew`, so the priorities stay at their default.)
##
##   title    "Morning" (a quiet night), or "The night is over" after one when the dead came (`scenario.attacks_on()` at any time of it)
##   rows     after an attack: Walls held (3 of 4 sections), Dead put down, Hurt, Lost; after a quiet night only what happened (kills, the hurt, the lost), or "A quiet night."
##            then "Fence needs mending: 2 sections" when a section is down or worn (the avatar's mend rule: under 95% of its hit points) and "Low: food (1 day)" when stores run short;
##            STORES (food, water, ammo, scrap, meds now, and what changed since the last morning), what the scavengers found yesterday, CREW (who does what), OUTSIDE (the weather, rain to come
##            today, the clock to dusk)
##   today    the objective's words (`scenario.objective()`), the new day's first suggestion
##   dismiss  a click on the card, any key (the key goes on to the game, but Enter, Space and Esc are the card's) or a click in the world, the "Good morning" button, or by itself after
##            `SHOW_S` seconds: a bar runs down. Nobody has to.
##
## It is NON-MODAL: the game does not pause, WASD still walks (a player in a fight at dawn is never held), the card sits clear of the avatar and of what the day's line points at
## (SAVE4: the coach card's placement, `Coach.best_rect` with `kept_clear()`: beside her when there is no room above or below, at every window size), and it is put away while a menu or a page is over the game. It waits for the sleep fade ("You slept until dawn") to end, so the two never
## stack. After the FIRST held attack the run is over and
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
const Coach := preload("res://scripts/ui/coach.gd")

## Real seconds the card stays; its fade in and out; rules seconds after the day begins before it comes (the night is judged by then).
const SHOW_S := 10.0
const FADE_S := 0.3
const DELAY_S := 0.6
## The card's width (less in a narrow window) and the gap from the screen's edge.
const CARD_W := 500.0
const CARD_W_MIN := 300.0
## A key or a click in the world puts the card away only after this many real seconds (a key pressed as the card comes up is not a wish to be rid of it).
const KEY_GRACE_S := 0.6
## The stores the summary names, in the order it names them, and the words of a person's stance for the crew row.
const STORES := [["food", "Food"], ["water", "Water"], ["ammo", "Ammo"], ["scrap", "Scrap"], ["meds", "Meds"]]
const STANCE_DOES := {"follow": "with you", "hold": "holding", "cover": "covering you", "search": "searching", "back": "going back to work"}
const EDGE := 12.0
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
## Whether the card has had a place (the next one keeps it unless another is clearly better).
var _placed := false
var _width := 0.0

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
## The stores at the last morning (whole numbers), for "what changed"; {} before the first look.
var _stores0 := {}
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
	var stores := _stores_now()
	var delta := {}
	if not _stores0.is_empty():
		for k in stores:
			delta[k] = int(stores[k]) - int(_stores0.get(k, stores[k]))
	_stores0 = stores.duplicate()    # (the next morning's change is counted from this one)
	return {
		"day": day, "night": had_night, "attack": _attack and had_night, "kills": maxi(0, int(sim.kills) - _kills0) if had_night else 0,
		"walls_total": secs.size(), "walls_held": maxi(secs.size() - fell, 0), "hurt": hurt, "lost": lost, "stores": stores, "delta": delta,
	}


## The stores as whole numbers: {"food": 11, "water": 17, ...}.
func _stores_now() -> Dictionary:
	var sim = _sim()
	var out := {}
	var stock = sim.get("stock") if sim != null else null
	if stock is Dictionary:
		for pair in STORES:
			out[String(pair[0])] = roundi(float((stock as Dictionary).get(String(pair[0]), 0.0)))
	return out


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


## Any key puts the card away, and goes on to the game (a walking key still walks; nothing waits for the card). Enter, Space and Esc are the card's: they put it away and go no further
## (Space is not a pause and Esc is not the menu while the card is up). A click in the world puts it away too, and still shoots, asks or uses.
func on_key(ev: InputEvent) -> bool:
	if not open or card == null or not card.visible:
		return false    # (a card hidden under a menu or a page does not take the keys)
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and _opened_s >= KEY_GRACE_S:
			_close(false)
		return false
	if not (ev is InputEventKey):
		return false
	var k := ev as InputEventKey
	if not k.pressed or k.echo:
		return false
	var code: Key = k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE or code == KEY_ESCAPE:
		_close(false)
		return true
	if _opened_s >= KEY_GRACE_S:
		_close(false)
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
		_stores0 = _stores_now()
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
		if hurt.is_empty() and lost.is_empty():
			rows.append(["Hurt or lost", "nobody", ""])
		else:
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
	# (RULES2: the rest of the summary: the stores and what changed, what the scavengers brought, who does what, the weather and the clock)
	var stores_text := _stores_text(t)
	if stores_text != "":
		rows.append(["Stores", stores_text, ""])
	var scav := _scavengers_text()
	if scav != "":
		rows.append(["", scav + ".", "ok"])
	var crew := _crew_text()
	if crew != "":
		rows.append(["Crew", crew, ""])
	var outside := _outside_text()
	if outside != "":
		rows.append(["Outside", outside, ""])
	return rows


## "Food 11 (-2)   Water 17   Ammo 272 (-5)   Scrap 11 (+30)   Meds 6": the stores now, and what changed since the last morning in brackets.
func _stores_text(t: Dictionary) -> String:
	var stores = t.get("stores", {})
	if not (stores is Dictionary) or (stores as Dictionary).is_empty():
		return ""
	var delta = t.get("delta", {})
	var bits: Array = []
	for pair in STORES:
		var k := String(pair[0])
		if not (stores as Dictionary).has(k):
			continue
		var bit := "%s\u00a0%d" % [String(pair[1]), int((stores as Dictionary)[k])]
		var d := int((delta as Dictionary).get(k, 0)) if delta is Dictionary else 0
		if d != 0:
			bit += "\u00a0(%s%d)" % ["+" if d > 0 else "-", absi(d)]
		bits.append(bit)
	return "   ".join(bits)


## What the Scavengers brought in yesterday ("Scavengers found: 12 food, 6 scrap yesterday"), or "".
func _scavengers_text() -> String:
	var sim = _sim()
	var cs = sim.get("crew_search") if sim != null else null
	if cs != null and cs.has_method("yesterday_text"):
		return String(cs.yesterday_text())
	return ""


## Who does what: "Beth: Builders; Kofi: Scavenger" (the others, not the avatar), or "".
func _crew_text() -> String:
	var sim = _sim()
	if sim == null:
		return ""
	var bits: Array = []
	for p in sim.people:
		if p.dead or p.turned or p.player:
			continue
		bits.append("%s: %s" % [String(p.first), _does(p)])
	return "; ".join(bits)


## One person's day in a few words: down or hurt, their job's name, else what they were asked to do, else nothing in particular.
func _does(p) -> String:
	var sim = _sim()
	var what := ""
	var jobs = sim.get("jobs")
	if jobs != null and jobs.has_method("job_of"):
		var sid := String(jobs.job_of(p))
		if sid != "":
			var st: Dictionary = jobs.station(sid) if jobs.has_method("station") else {}
			what = String(st.get("name", sid.capitalize()))
	if what == "":
		what = String(STANCE_DOES.get(String(p.stance), "no job"))
	if p.downed:
		return "down (%s)" % what
	if float(p.hp) < 50.0 or float(p.bleeding) > 0.0:
		return "%s, hurt" % what
	return what


## "9°C, clear. Rain expected about 14:00. Dusk in 12h 25m.": the weather as it is, rain that today's sky will bring, and the clock to dusk.
func _outside_text() -> String:
	var sim = _sim()
	if sim == null:
		return ""
	var h := float(sim.hour)
	var seasons = sim.get("seasons")
	var temp := roundi(seasons.temperature(h)) if seasons != null and seasons.campaign else roundi(9.0 + 8.0 * maxf(0.0, sin((h - 8.0) / 24.0 * TAU)))
	var skies = sim.get("skies")
	var word := String(skies.word()) if skies != null and skies.has_method("word") else String(sim.weather)
	var out := "%d°C, %s." % [temp, word]
	var ahead := _rain_ahead(skies, h)
	if ahead != "":
		out += " " + ahead + "."
	var to_dusk := fposmod((seasons.dusk_hour() if seasons != null else 19.0) - h, 24.0)
	if String(sim.phase) == "day":
		out += " Dusk\u00a0in\u00a0%dh\u00a0%02dm." % [int(to_dusk), int(fmod(to_dusk, 1.0) * 60.0)]
	return out


## "Rain expected about 14:00" when the day's schedule has a wet spell still to come (the schedule is the seed's: nothing held by a staging), else "".
func _rain_ahead(skies, h: float) -> String:
	if skies == null or not skies.has_method("period") or not skies.has_method("raining") or bool(skies.raining()):
		return ""
	if String(skies.get("_force")) != "" or String(skies.get("_first_night")) != "":
		return ""
	var sim = _sim()
	var k := int(sim.day) - 1
	if k < 0:
		return ""
	var p: Dictionary = skies.period(k)
	if not bool(p.get("wet", false)):
		return ""
	var from_h := 7.0 + float(p.s) - 24.0 * float(k)
	if from_h >= 24.0 or from_h <= h:
		return ""
	var kind: String = {"drizzle": "drizzle", "steady": "rain", "storm": "storm"}.get(String(p.kind), "rain")
	return "%s\u00a0expected\u00a0about\u00a0%02d:%02d" % [kind.capitalize(), int(from_h), floori(fmod(from_h, 1.0) * 6.0) * 10]


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
	# (a click on the card puts it away: the card takes the click, so it is not a shot)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and open:
			_close(false))
	var col: VBoxContainer = hud._vbox(5)
	card.add_child(col)
	var head: HBoxContainer = hud._hbox(10)
	_title = hud._label(title_text, Fonts.cond(700), 28, hud.INK)
	head.add_child(_title)
	head.add_child(hud._spacer())
	var day_l: Label = hud._label("DAY %d" % int(t.get("day", sim.day)), Fonts.cond(600, 2), 14, hud.ACCENT)
	day_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(day_l)
	col.add_child(head)
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
	var hint: Label = hud._label("Any key, or a click", Fonts.sans(400), 13, hud.INK3)
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
	_placed = false
	_place()
	var snd = main.get("sound")
	if snd != null and snd.has_method("ui"):
		snd.ui("ui_open", 0.6)


func _add_row(col: VBoxContainer, label: String, value: String, tone: String) -> void:
	var color := _tone_color(tone)
	if label == "":
		var line: Label = hud._label(value, Fonts.sans(600), 14, color)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(line)
		_wrap_inner.append(line)
		return
	var row: HBoxContainer = hud._hbox(8)
	var l: Label = hud._label(label.to_upper(), Fonts.cond(600, 1), 14, hud.INK3)
	l.custom_minimum_size.x = LABEL_W
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(l)
	var v: Label = hud._label(value, Fonts.sans(600), 15, color)
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

## The card's size and place (SAVE4): where it hides neither the avatar nor what the day's line points at, by the coach card's own rule (`Coach.best_rect`: the cheapest of the spots round the
## window and round the figure that covers least of what is kept clear, then least of the HUD's boards, the place it had kept unless another is clearly better). It used to be centred
## 30 px under the avatar's CENTRE, which at 1280 x 800 (a 390 px card) covered her feet.
func _place() -> void:
	if card == null:
		return
	var vp: Vector2 = hud.size
	var wmax := clampf(minf(CARD_W, vp.x - 2.0 * EDGE), minf(CARD_W_MIN, vp.x - 2.0 * EDGE), CARD_W)
	var kept := kept_clear()
	# the widths to try: the width it had (it stays while it hides nothing), then the widest down to the narrowest (a small window has no room beside her for the full width)
	var widths: Array = []
	for k in [wmax, 440.0, 390.0, 345.0, CARD_W_MIN]:
		if k <= wmax + 0.5 and k >= minf(CARD_W_MIN, wmax) - 0.5 and not widths.has(k):
			widths.append(k)
	if _placed and widths.has(_width):
		widths.erase(_width)
		widths.push_front(_width)
	var best_w: float = widths[0]
	var best_r := Rect2()
	var best_cost := INF
	for cand in widths:
		var sz := _size_at(float(cand))
		var prev := Rect2(card.position, sz) if _placed and is_equal_approx(float(cand), _width) else Rect2()
		var r: Rect2 = Coach.best_rect(hud, sz, vp, Rect2(), "bottom", false, true, kept, prev)
		var cost := 0.0
		for k in kept:
			var ov: Rect2 = r.intersection(k)
			cost += ov.size.x * ov.size.y
		if cost < best_cost - 0.5:
			best_cost = cost
			best_w = float(cand)
			best_r = r
		if cost <= 0.5:
			break
	var final := _size_at(best_w)
	card.size = final
	card.position = Vector2(roundf(best_r.position.x), roundf(best_r.position.y))
	_width = best_w
	_placed = true


## The card at width `w`: its long lines wrapped to it, its size set; returns the size.
func _size_at(w: float) -> Vector2:
	var margin: float = card.get_theme_stylebox("panel").get_minimum_size().x
	for c in _wrap_inner:
		RadioKit.wrap_at(c, w - margin)
	for c in _wrap_value:
		RadioKit.wrap_at(c, w - margin - LABEL_W - 8.0)
	card.custom_minimum_size.x = w
	card.size = Vector2(w, 0.0)
	var h := card.get_combined_minimum_size().y
	return Vector2(w, h)


## What the card keeps off, in the HUD's pixels (the coach's `_kept_clear`, and the bearing of the day's line): the avatar (the figure with its YOU tag, and the room round her for
## the gun's muzzle), the gun's readout and the place the objective points at.
func kept_clear() -> Array:
	var out: Array = []
	var sim = _sim()
	var me = sim.avatar.player() if sim != null and sim.get("avatar") != null else null
	if me == null or me.away != null:
		return out
	var at: Vector2 = main.view_pos(me)
	var a: Vector2 = main._tile_to_screen(at + Vector2(-0.5, -1.9))
	var b: Vector2 = main._tile_to_screen(at + Vector2(0.5, 0.5))
	out.append(Rect2(a, b - a).abs())
	var c: Vector2 = main._tile_to_screen(at + Vector2(0.0, -0.45))
	var rad: float = Coach.AVATAR_CLEAR * float(main.zoom_px)
	out.append(Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0))
	var gun = hud.get("ammo_panel")
	if gun != null and is_instance_valid(gun) and gun.is_visible_in_tree():
		out.append(gun.get_global_rect())
	# (the town HUD's words that a morning card would hide: the objective, the lesson's card and the keys' legend: the player reads them as the card comes up)
	var th = main.town.part("town_hud") if main.get("town") != null and main.town.has_method("part") else null
	if th != null:
		for n in ["obj_card", "lesson_card", "legend"]:
			var board = th.get(n)
			if board is Control and is_instance_valid(board) and board.is_visible_in_tree() and board.size.x > 0.0:
				out.append(board.get_global_rect())
	# (what she is pointed at: the objective's bearing, when it is on the screen)
	var sc = _scenario()
	if sc != null and sc.has_method("objective"):
		var o = sc.objective()
		if o is Dictionary and o.get("at") is Vector2:
			var p: Vector2 = main._tile_to_screen(o.at)
			if Rect2(Vector2.ZERO, hud.size).has_point(p):
				var half := 0.9 * float(main.zoom_px)
				out.append(Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0))
	return out


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
