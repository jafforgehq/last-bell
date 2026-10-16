## EXPERIMENT (prison round 12): the STORY'S SCREENS. The radio-static story card (a beat, a letter, the convoy at the gate), the day banner ("DAY 12 OF 30" with the weather), and the story LOG
## (key L, also the Story tab of the board): the phases, the convoy's list with progress bars, the next night, and every message received, so the story can be read again.
## Pattern: the board's window style (Hud colours, the town's fonts, dark panel, gold line) and the stage card's gold-bordered card; the card is a Control that keeps running while the tree is paused
## (process_mode ALWAYS) so its static, its typewriter and its buttons work while the game waits behind it. One card at a time; none while a night attack, a raid, a cutscene or a window is on.
## In scripted runs (--auto, --shot, ...) nothing is shown: the beats go straight to the log (`--arcshow` shows them).
extends RefCounted

const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

var game
var arc
var layer: CanvasLayer
var card: Control    # the open card (a StaticCard) or null
var log_panel: PanelContainer
var log_body: VBoxContainer
var _open_beat := ""
var _log_sig := 0
var _log_dirty := true


# --------------------------------------------------------------------------- the card --

## A Control that runs while the tree is paused: typewriter text, a key or click goes on, the number keys answer a choice.
class StaticCard extends Control:
	signal answered(i: int)
	var label: Label
	var n_choices := 0
	var typing := true
	var cps := 90.0
	var _chars := 0.0
	var buttons: Array = []
	var go_btn: Button

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(dt: float) -> void:
		if label != null and typing:
			_chars += dt * cps
			label.visible_characters = int(_chars)
			if _chars >= float(label.get_total_character_count()):
				_finish_typing()

	func _finish_typing() -> void:
		typing = false
		if label != null:
			label.visible_characters = -1
		for b in buttons:
			(b as Button).disabled = false

	func _unhandled_input(ev: InputEvent) -> void:
		if not visible:
			return
		if ev is InputEventKey and ev.pressed and not ev.echo:
			var k := (ev as InputEventKey).keycode
			if k == KEY_SPACE or k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				if typing:
					_finish_typing()
				elif n_choices == 0:
					answered.emit(0)
			elif k >= KEY_1 and k < KEY_1 + n_choices:
				get_viewport().set_input_as_handled()
				if typing:
					_finish_typing()
				else:
					answered.emit(int(k - KEY_1))


## The static over the card: thin bright dashes that jump 14 times a second, scan lines, and a stronger burst while the station tunes in.
class StaticNoise extends Control:
	var t := 0.0

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(t * 14.0) * 7919 + 13
		var tune := clampf(1.0 - t / 1.4, 0.0, 1.0)
		var n := int(size.x * size.y / 2600.0 * (0.35 + 1.6 * tune))
		for i in n:
			var x := rng.randf() * size.x
			var y := rng.randf() * size.y
			draw_rect(Rect2(x, y, rng.randf_range(2.0, 26.0 + 60.0 * tune), 1.5), Color(1, 0.98, 0.88, rng.randf_range(0.03, 0.10 + 0.25 * tune)))
		var y2 := 0.0
		while y2 < size.y:
			draw_line(Vector2(0, y2), Vector2(size.x, y2), Color(0, 0, 0, 0.10), 1.0)
			y2 += 4.0
		if tune > 0.02:    # the picture rolls: one bright band
			var by := fposmod(t * 520.0, size.y)
			draw_rect(Rect2(0, by, size.x, 18.0 * tune), Color(1, 1, 0.9, 0.06 * tune))


class Bars extends Control:
	var t := 0.0

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		custom_minimum_size = Vector2(26, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _draw() -> void:
		var lit := 2 + int(1.0 + sin(t * 3.0) * 1.2 + sin(t * 9.1) * 0.6)
		for i in 4:
			var h := 4.0 + 3.5 * float(i)
			draw_rect(Rect2(float(i) * 6.0, 16.0 - h, 4.0, h), Hud.ACCENT if i < lit else Color(0.4, 0.4, 0.33, 0.6))


func _init(g, a) -> void:
	game = g
	arc = a
	layer = CanvasLayer.new()
	layer.layer = 14
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	g.add_child(layer)
	log_panel = PanelContainer.new()
	log_panel.visible = false
	log_panel.add_theme_stylebox_override("panel", _box(Color(Hud.PANEL, 0.985), Hud.LINE2, 14, 6))
	layer.add_child(log_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	log_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(_lab("THE STORY  [L]", 24, Hud.ACCENT, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var x := _btn("Close (L)")
	x.pressed.connect(close_log)
	head.add_child(x)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	log_body = VBoxContainer.new()
	log_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_body.add_theme_constant_override("separation", 8)
	sc.add_child(log_body)


# ------------------------------------------------------------------------------- builders --

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
	b.focus_mode = Control.FOCUS_NONE
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	b.add_theme_font_override("font", Fonts.cond(700))
	b.add_theme_font_size_override("font_size", 19)
	var base := _box(Color(Hud.PANEL_HI, 0.95), Hud.LINE2, 9, 5)
	var hover := base.duplicate() as StyleBoxFlat
	hover.border_color = Hud.ACCENT
	hover.bg_color = Color(0.26, 0.34, 0.3, 0.96)
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", _box(Color(0.1, 0.12, 0.11, 0.9), Hud.LINE, 9, 5))
	b.add_theme_color_override("font_color", Hud.INK)
	b.add_theme_color_override("font_hover_color", Hud.ACCENT)
	b.add_theme_color_override("font_disabled_color", Hud.INK3)
	return b


func _bar(frac: float, col: Color, h: float = 12.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.max_value = 1.0
	p.value = clampf(frac, 0.0, 1.0)
	p.custom_minimum_size = Vector2(150, h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.45), Hud.LINE, 0, 3))
	p.add_theme_stylebox_override("fill", _box(col, col, 0, 3))
	return p


## A drawn check box for a list row (not a typed "[ ]"): "done" a green box with a tick, "now" an amber box with a dot, "" an empty grey box.
func _tick(state: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(16, 16)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var col: Color = Hud.OK if state == "done" else (Hud.WARN if state == "now" else Hud.INK3)
		var r := Rect2(Vector2(1, 1), Vector2(14, 14))
		c.draw_rect(r, Color(0.05, 0.07, 0.06, 0.9))
		c.draw_rect(r, col, false, 2.0)
		if state == "done":
			c.draw_polyline(PackedVector2Array([Vector2(4, 8), Vector2(7, 11), Vector2(12, 4)]), col, 2.2)
		elif state == "now":
			c.draw_rect(Rect2(Vector2(5, 5), Vector2(6, 6)), col))
	return c


func _vp() -> Vector2:
	return game._vp()


# ----------------------------------------------------------------------------- the card --

func card_open() -> bool:
	return card != null and is_instance_valid(card)


## Builds and shows a radio card. `d`: kicker, title, from, text, tone ("radio"|"letter"|"convoy"), buttons [labels] (default one "Continue"), on_answer Callable(i).
func show_card(d: Dictionary) -> void:
	if card_open():
		card.queue_free()
	var v := _vp()
	var root := StaticCard.new()
	root.cps = 3000.0 if game.args.has("shot") else 90.0
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.03, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)
	var pc := PanelContainer.new()
	var tone := String(d.get("tone", "radio"))
	var line := Hud.ACCENT if tone != "letter" else Hud.BRASS
	var bg := Color(0.05, 0.075, 0.065, 0.985) if tone != "letter" else Color(0.1, 0.085, 0.06, 0.985)
	pc.add_theme_stylebox_override("panel", _box(bg, line, 26, 8))
	centre.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var bars := Bars.new()
	top.add_child(bars)
	top.add_child(_lab(String(d.get("kicker", "RADIO")), 16, Hud.INK3, true))
	vb.add_child(top)
	var title := _lab(String(d.title).to_upper(), 46, line, true)
	vb.add_child(title)
	if String(d.get("from", "")) != "":
		vb.add_child(_lab("from " + String(d.from), 17, Hud.INK3))
	var rule := ColorRect.new()
	rule.color = Hud.LINE2
	rule.custom_minimum_size = Vector2(0, 1)
	vb.add_child(rule)
	var tw := minf(640.0, v.x - 120.0)
	var text := _lab(String(d.text), 20, Hud.INK if tone != "letter" else Color("#e9dcb8"), false)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(tw, 0)
	text.visible_characters = 0
	vb.add_child(text)
	root.label = text
	var extra := String(d.get("extra", ""))
	if extra != "":
		var ex := _lab(extra, 16, Hud.WARN)
		ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ex.custom_minimum_size = Vector2(tw, 0)
		vb.add_child(ex)
	var labels: Array = d.get("buttons", ["Continue  (Space)"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for i in labels.size():
		var b := _btn(String(labels[i]))
		b.disabled = true
		root.buttons.append(b)
		b.pressed.connect(func(): root.answered.emit(i))
		row.add_child(b)
	vb.add_child(row)
	root.n_choices = labels.size() if labels.size() > 1 else 0
	var noise := StaticNoise.new()
	pc.add_child(noise)
	var cb: Callable = d.get("on_answer", Callable())
	root.answered.connect(func(i: int):
		_close_card()
		if cb.is_valid():
			cb.call(i))
	layer.add_child(root)
	card = root
	game.get_tree().paused = not game.args.has("shot")
	game.sound.play("bell", 0.35, 0.0)


func _close_card() -> void:
	if card_open():
		card.queue_free()
	card = null
	game.get_tree().paused = false


# --------------------------------------------------------------------------- the beats --

func can_show() -> bool:
	if card_open() or arc.endings.is_open():
		return false
	if game.mode != "base" or game.busy or game.siege.attacking or game.pause_menu.is_open() or game.board.is_open() or game.loadout.is_open or (game.pack.ui != null and game.pack.ui.is_open()):
		return false
	return float(game.tod) >= float(arc.cfg.calendar.card_h) or game.args.has("arcshow")


func frame(dt: float) -> void:
	if log_panel.visible:
		_log_frame()
	if card_open() or not arc.active():
		return
	if arc.scripted:
		var id: String = arc.next_due()
		while id != "":
			arc.deliver(id)
			id = arc.next_due()
		while arc.take_wait():
			arc.next_letter()
		if arc.next_event() != "":
			arc.deliver_event(-1)    # EVENTS: a scripted run takes the safe answer
		return
	if not can_show():
		return
	var due: String = arc.next_due()
	if due != "":
		show_beat(due)
	elif arc.take_wait():
		show_letter(arc.next_letter())
	elif arc.next_event() != "":
		show_event()


## EVENTS: the morning card (prison_events.gd). Its answer applies the effects and shows what came of it.
func show_event() -> void:
	var v: Dictionary = arc.event_view()
	if v.is_empty() or (v.choices as Array).is_empty():
		arc.deliver_event(-1)
		return
	var labs: Array = []
	for i in (v.choices as Array).size():
		var od: String = arc.events.odds_text(v.choices[i])    # (a roll shows its odds on the button)
		labs.append("%d  %s%s" % [i + 1, String(v.choices[i].label), "  (%s)" % od if od != "" else ""])
	show_card({"kicker": "MORNING  -  DAY %d" % arc.day, "title": String(v.title), "from": String(v.from), "text": String(v.text), "tone": String(v.tone), "buttons": labs,
		"on_answer": func(i: int):
			var res: Dictionary = arc.deliver_event(i)
			if not res.is_empty() and String(res.result) != "":
				show_card({"kicker": "MORNING  -  DAY %d" % arc.day, "title": String(v.title), "from": "what happened", "text": String(res.result), "tone": String(v.tone), "extra": String(res.extra)})})


## The card of a beat; its answer (or Continue) delivers it. A silent beat has no card.
func show_beat(id: String) -> void:
	var b: Dictionary = arc.beat(id)
	if b.is_empty():
		return
	if bool(b.get("silent", false)) and not game.args.has("story"):
		arc.deliver(id)
		return
	var text := String(b.text)
	var extra := ""
	if bool(b.get("readiness", false)):
		extra = arc.readiness_text()
	if String(b.get("opens_phase", "")) != "":
		extra = "New goal: Phase III, Evacuate. See the story log (L) and the objectives (O)."
	for f in b.get("if_flag", {}):    # (a letter found earlier changes what the card says)
		if arc.flags.has(String(f)):
			extra = (extra + "\n" if extra != "" else "") + String(b.if_flag[f].get("extra", ""))
	if String(b.get("event", "")) == "storm":
		extra = "Tonight: no power, a bigger wave. Mend the fence and fill the stores."
	var d := {"kicker": "RADIO  -  DAY %d  -  %s MHZ" % [arc.day, String(arc.cfg.calendar.radio_freq)], "title": String(b.title), "from": String(b.from), "text": text, "extra": extra, "tone": "radio"}
	if b.has("choice"):
		var labs: Array = []
		for i in b.choice.size():
			labs.append("%d  %s" % [i + 1, String(b.choice[i].label)])
		d["buttons"] = labs
		d["on_answer"] = func(i: int):
			arc.deliver(id, String(b.choice[i].id))
			_result_card(b, String(b.choice[i].id))
	else:
		d["on_answer"] = func(_i: int): arc.deliver(id)
	_open_beat = id
	show_card(d)


func _result_card(b: Dictionary, choice_id: String) -> void:
	var c: Dictionary = arc.choice_of(b, choice_id)
	if not c.is_empty():
		show_card({"kicker": "RADIO  -  DAY %d" % arc.day, "title": String(b.title), "from": "what happened", "text": String(c.result), "tone": "radio", "extra": _fx_text(c.get("effects", {}))})


func _fx_text(fx: Dictionary) -> String:
	var out: Array = []
	for k in fx.get("stores", {}):
		out.append("%+d %s" % [int(fx.stores[k]), k])
	if fx.has("morale"):
		out.append("%+d morale" % int(fx.morale))
	return ", ".join(out)


func show_letter(l: Dictionary) -> void:
	if l.is_empty():
		return
	var ex := ""
	var fx := _fx_text(l.get("reward", {}))
	if fx != "":
		ex = "Taken: " + fx
	if String(l.get("clue", "")) != "":
		ex += ("   " if ex != "" else "") + String(l.clue)
	show_card({"kicker": "A LETTER FOUND IN THE TOWN  -  DAY %d" % arc.day, "title": String(l.title), "from": String(l.from), "text": String(l.text), "extra": ex, "tone": "letter"})


## The convoy at the gate: the list, the seats, and the answer.
func show_convoy() -> void:
	var cc: Dictionary = arc.cfg.convoy_cards
	var rdy: bool = arc.ready()
	var lines: Array = []
	for r in arc.requirements():
		if bool(r.must):
			lines.append("%s %s: %s" % ["[x]" if bool(r.ok) else "[ ]", String(r.label), String(r.text)])
	var txt := String(cc.arrive).replace("{leaves}", String(arc.cfg.convoy.waits))
	txt += "\n\n" + "\n".join(lines)
	var d := {"kicker": "THE RIVER ROAD  -  DAY %d  -  %02d:00" % [arc.day, int(game.tod)], "title": "The convoy", "from": "Halloran, Harbor Relief", "text": txt, "tone": "convoy"}
	var seats: int = arc.seats()
	var n: int = arc.people_alive()
	if rdy:
		d["extra"] = String(cc.ready).replace("{seats}", str(seats)).replace("{people}", str(n)) + (" %d will have to stay." % (n - seats) if n > seats else "")
		d["buttons"] = ["1  Load up and go", "2  Stay and hold the fort"]
		d["on_answer"] = func(i: int): arc.convoy_answer(i == 0)
	else:
		d["extra"] = String(cc.short) + "  Missing: " + "; ".join(arc.missing()) + "."
		d["buttons"] = ["Watch them leave"]
		d["on_answer"] = func(_i: int): arc.convoy_answer(false)
	show_card(d)


# ----------------------------------------------------------------------------- the banner --

func banner(a: String, b: String = "") -> void:
	game._banner(a, b, 5.3, 34, Hud.ACCENT)    # MESSAGE LANES: the day banner and the convoy go through the game's banner lane

# ------------------------------------------------------------------------------- the log --

func log_changed() -> void:
	_log_dirty = true


func key(ev: InputEvent) -> bool:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return false
	var k := (ev as InputEventKey).keycode
	if log_panel.visible and (k == KEY_L or k == KEY_ESCAPE):
		close_log()
		return true
	if k == KEY_L and arc.started and not card_open() and not arc.endings.is_open() and not game.pause_menu.is_open() and not game.busy:
		open_log()
		return true
	return false


func open_log() -> void:
	game.pack.close()
	if game.board.is_open():
		game.board.close()
	log_panel.visible = true
	_log_dirty = true
	_log_frame()


func close_log() -> void:
	log_panel.visible = false


func _log_frame() -> void:
	var v := _vp()
	var sz := Vector2(minf(820.0, v.x - 24.0), minf(660.0, v.y - 24.0))
	log_panel.custom_minimum_size = sz
	log_panel.size = sz
	log_panel.position = ((v - sz) / 2.0).round()
	var sig: int = arc.log_entries.size() * 1000 + arc.day * 10 + int(game.stores.get("fuel", 0.0)) * 3 + int(game.stores.get("parts", 0.0)) + int(game.stores.get("meds", 0.0)) + arc.people_alive() * 7
	if _log_dirty or sig != _log_sig:
		_log_dirty = false
		_log_sig = sig
		for c in log_body.get_children():
			log_body.remove_child(c)
			c.queue_free()
		fill(log_body, _lab, _rich, _bar)


## The content of the story page (the L window and the board's Story tab): calendar, phases, the convoy's list with bars, the next night, the messages.
func fill(body: VBoxContainer, lab: Callable, rich: Callable, bar: Callable) -> void:
	var left: int = arc.days_left()
	var head := "Day %d of %d" % [arc.day, arc.days()]
	body.add_child(lab.call(head, 24, Hud.INK, true))
	var cd := ""
	match String(arc.convoy):
		"none":
			cd = "The Harbor Convoy comes to the gate on day %d, at %02d:00, and waits %s. %d day%s to go." % [arc.convoy_day(), int(arc.cfg.calendar.arrive_h), String(arc.cfg.convoy.waits), left, "" if left == 1 else "s"] if left > 0 else "The convoy comes today."
		"here":
			cd = "The convoy is at the gate now."
		"left":
			cd = "You left with the convoy."
		_:
			cd = "The convoy has gone."
	var r1: RichTextLabel = rich.call(cd, 15)
	body.add_child(r1)
	var w: Dictionary = arc.weather_now()
	var plan: Dictionary = arc.wave_plan(int(arc.game.siege.nights_started) + (0 if arc.game.siege.attacking else 1))
	body.add_child(lab.call(arc.horde_line(int(arc.game.siege.nights_started) + (0 if arc.game.siege.attacking else 1)), 15, Hud.WARN, false))
	body.add_child(lab.call("Tonight: %s%s - about %d dead at %d wall%s%s" % [("night %d" % (arc.game.siege.night if arc.game.siege.attacking else arc.game.siege.nights_started + 1)), (" (" + String(plan.name) + ")") if String(plan.name) != "" else "", int(plan.total), int(plan.segs), "" if int(plan.segs) == 1 else "s", ("   weather: " + String(w.label)) if String(w.kind) != "clear" else ""], 15, Hud.WARN, false))
	body.add_child(lab.call("Phases", 18, Hud.ACCENT, true))
	for p in arc.phases_list():
		var cur: bool = String(p.id) == String(arc.phase().id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_tick("done" if bool(p.done) else ("now" if cur else "")))
		var pl: Label = lab.call("%s   (by day %d)%s" % [String(p.name), int(p.by_day), "" if not cur else "   - " + String(p.text)], 15, Hud.OK if bool(p.done) else (Hud.INK if cur else Hud.INK3), false)
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pl)
		body.add_child(row)
	body.add_child(lab.call("The convoy's list", 18, Hud.ACCENT, true))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 5)
	body.add_child(g)
	for r in arc.requirements():
		g.add_child(lab.call("%s%s" % [String(r.label), "" if bool(r.must) else "  (optional)"], 15, Hud.OK if bool(r.ok) else Hud.INK, false))
		g.add_child(bar.call(float(r.frac), Hud.OK if bool(r.ok) else Hud.WARN, 12.0))
		g.add_child(lab.call(String(r.text), 15, Hud.OK if bool(r.ok) else Hud.INK2, false))
	body.add_child(lab.call("Seats: %d (the bus %d, your truck %d).  People alive: %d.%s" % [arc.seats(), int(arc.cfg.convoy.bus_seats), arc.seats() - int(arc.cfg.convoy.bus_seats), arc.people_alive(), "  Not everyone fits." if arc.people_alive() > arc.seats() else ""], 15, Hud.INK2, false))
	var bl: Array = []
	for b in arc.cfg.bonuses:
		bl.append(String(b.label) + " +%d" % int(b.points))
	body.add_child(lab.call("Extras that count: " + "; ".join(bl), 14, Hud.INK3, false))
	body.add_child(lab.call("Memorial wall", 18, Hud.ACCENT, true))    # META: the dead by name, with the day and the cause
	var wall: Array = arc.memorial()
	if wall.is_empty():
		body.add_child(lab.call("Nobody has died yet.", 15, Hud.INK3, false))
	for d in wall:
		body.add_child(lab.call("%s   day %d, %s" % [d.name, d.day, d.cause], 15, Hud.INK2, false))
	body.add_child(lab.call("Messages", 18, Hud.ACCENT, true))
	if arc.log_entries.is_empty():
		body.add_child(lab.call("Nothing yet. The radio is quiet.", 15, Hud.INK3, false))
	var i: int = arc.log_entries.size() - 1
	while i >= 0:
		var e: Dictionary = arc.log_entries[i]
		var col := Hud.INK if String(e.kind) == "radio" else (Color("#e9dcb8") if String(e.kind) == "letter" else Hud.INK3)
		body.add_child(lab.call("Day %d  -  %s%s" % [int(e.day), String(e.title), ("   (" + String(e.from) + ")") if String(e.get("from", "")) != "" else ""], 16, Hud.ACCENT if String(e.kind) != "note" else Hud.INK2, true))
		if String(e.get("text", "")) != "":
			body.add_child(rich.call("[color=#%s]%s[/color]" % [col.to_html(false), String(e.text)], 15))
		if String(e.get("result", "")) != "":
			body.add_child(rich.call("[i][color=#%s]%s[/color][/i]" % [Hud.INK3.to_html(false), String(e.result)], 14))
		i -= 1
