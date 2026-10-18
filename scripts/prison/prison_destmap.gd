## The DESTINATION MAP of the gate: a code-drawn map of the town round the prison with the named places of `places` in assets/data/prison_raids.json as markers. Click a marker (or Left/Right/Tab,
## or the number keys) and the side panel names it, says in plain words what a trip there may find (often / sometimes / rarely, never a number), its danger, the dead, the fuel it costs and a Go button.
## Places not open yet are grey with the reason. Places that cover what the base is short of (prison_loot.gd `short_res`) pulse green. Opened by E at the truck (loot.open_choice) or M at the base (view only).
## Go calls loot.go_to(id). Pure view: every number is the data's.
## RAID EXTRAS (scripts/prison/prison_raidx.gd): a Day or Night choice (T), today's weather, a fuel gauge with the reason Go is refused, and a mark for each place (X: none, done, avoid).
extends RefCounted

const PIcons := preload("res://scripts/prison/prison_icons.gd")
const UI := preload("res://scripts/prison/prison_ui.gd")    # the windows' one look and motion

const TAGS := {"often": Color(0.5, 0.88, 0.5), "sometimes": Color(0.95, 0.82, 0.4), "rarely": Color(0.7, 0.7, 0.75)}
const DANGER_WORD := ["", "Low", "Moderate", "High", "Very high", "Deadly"]

## A control that hands its drawing and its mouse to callables.
class Canvas extends Control:
	var draw_cb: Callable
	var input_cb: Callable

	func _draw() -> void:
		draw_cb.call(self)

	func _gui_input(ev: InputEvent) -> void:
		input_cb.call(ev)

	func _process(_dt: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

var loot
var game
var ids: Array = []
var sel := 0
var is_open := false
var view_only := false
var forced := ""    # an event card sends the next raid to this place
var shorts: Array = []
var day := 1
var root: PanelContainer
var canvas: Canvas
var side: RichTextLabel
var go_btn: Button
var sub: Label
var note: Label
var pick_time := ""    # "day" or "night": kept between visits to the map
var time_btns: Array = []
var mark_btn: Button
var fuel_c: Canvas
var hover_i := -1    # the marker under the pointer (a soft ring, and the pointing hand)


func _init(l, g) -> void:
	loot = l
	game = g
	ids = loot.place_ids()


func open(view: bool, forced_id: String) -> void:
	view_only = view
	forced = forced_id
	day = int(game.econ.day) if game.econ != null else 1
	shorts = loot.short_res()
	if pick_time == "" or game.raidx.time_cfg(pick_time).is_empty():
		pick_time = game.raidx.default_time()
	var nd: Dictionary = game.econ.needs()
	if root == null:
		_build()
	sub.text = ("The base is short of: %s" % String(nd.get("reason", ""))) if not nd.is_empty() else "Nothing is short. Pick what to hunt."
	if forced != "":
		sub.text = "The radio call sends the truck to one place this time."
	sel = _first_open()
	if forced != "":
		sel = ids.find(forced)
	var want := String(game.args.get("choice", ""))    # staging: --choice=port preselects a place
	if want != "" and ids.has(want):
		sel = ids.find(want)
	is_open = true
	var was := root.visible
	root.visible = true
	if not was:
		UI.open_fx(root)
	root.reset_size()
	root.position = Vector2(10.0, maxf(100.0, (game._vp().y - root.size.y) / 2.0))    # (clear of the top bar and the objectives list on the right)
	_refresh()


func close() -> void:
	is_open = false
	loot.choosing = false
	if root != null:
		UI.close_fx(root)
		root.visible = false


## The open place that covers the most of what the base lacks (the first open one when none does).
func _first_open() -> int:
	var best := -1
	var bs := -1
	for i in ids.size():
		if not status(String(ids[i])).ok:
			continue
		var sc := covers(String(ids[i])).size() * 10 + (1 if best < 0 else 0)
		if sc > bs:
			bs = sc
			best = i
	return maxi(best, 0)


## What of the base's shortage a place answers.
func covers(id: String) -> Array:
	var out: Array = []
	var ans: Array = loot.kind_cfg(id).get("answers", [])
	for r in shorts:
		if ans.has(r):
			out.append(String(r))
	return out


## {ok: can go, open: on the map and not locked, why}.
func status(id: String) -> Dictionary:
	var pc: Dictionary = loot.place_cfg(id)
	if forced != "" and id != forced:
		return {"ok": false, "open": false, "why": "The radio call sends the truck to %s this time." % String(loot.place_cfg(forced).get("name", forced))}
	var ud := int(pc.get("unlock_day", 1))
	if day < ud:
		return {"ok": false, "open": false, "why": "Not yet (day %d). %s" % [ud, String(pc.get("unlock_note", "The way is closed."))]}
	var fuel := float(game.stores.get("fuel", 0.0))
	var fc := int(pc.get("fuel", 0))
	if fuel < float(fc):
		return {"ok": false, "open": true, "fuel_short": true, "why": "Not enough fuel: the trip costs %d and the tank holds %d (short by %d). %s" % [fc, int(fuel), fc - int(fuel), _refuel_text(fuel)]}
	if view_only:
		return {"ok": false, "open": true, "why": "To go, walk to the truck and press E."}
	return {"ok": true, "open": true, "why": ""}


## Where fuel can be found with what the tank holds now (the open places that answer fuel and cost no more than the tank), else the data's plain note.
func _refuel_text(fuel: float) -> String:
	var names: Array = []
	for id in ids:
		var pc: Dictionary = loot.place_cfg(String(id))
		if (loot.kind_cfg(String(id)).get("answers", []) as Array).has("fuel") and day >= int(pc.get("unlock_day", 1)) and float(pc.get("fuel", 0)) <= fuel:
			names.append(String(pc.name))
	if names.is_empty():
		return String(game.raidx.cfg().get("fuel_note", ""))
	return "Refuel first: a trip to %s finds fuel." % " or ".join(names)


func _build() -> void:
	root = PanelContainer.new()
	root.add_theme_stylebox_override("panel", UI.frame_box(12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	var head := HBoxContainer.new()    # the title, and the keys beside it in small print
	head.add_theme_constant_override("separation", 14)
	head.add_child(UI.title("WHERE TO?"))
	var keys := UI.label("Click a place. Left/Right or Tab to move, Enter or E to go, Esc to stay.", UI.SMALL_PX, Color(0.75, 0.75, 0.7))
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(keys)
	col.add_child(head)
	sub = UI.label("", UI.BODY_PX, Color(1, 0.85, 0.5))
	col.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	canvas = Canvas.new()
	var vp: Vector2 = game._vp()
	var cw := clampf(vp.x - 724.0, 330.0, 600.0)    # (narrow enough that the objectives list on the right is not overlapped at 1024 wide)
	canvas.custom_minimum_size = Vector2(cw, clampf(cw * 0.78, 280.0, vp.y - 130.0))
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw_cb = _draw_map
	canvas.input_cb = _map_input
	canvas.mouse_exited.connect(func(): hover_i = -1)
	row.add_child(canvas)
	var sc := VBoxContainer.new()
	sc.custom_minimum_size = Vector2(300, 0)
	sc.add_theme_constant_override("separation", 6)
	row.add_child(sc)
	side = RichTextLabel.new()
	side.bbcode_enabled = true
	side.fit_content = false
	side.scroll_active = true    # (a small window: the place's words ran on under the hour buttons, cut off)
	side.custom_minimum_size = Vector2(300, canvas.custom_minimum_size.y - 110.0)
	side.add_theme_font_size_override("normal_font_size", 14)
	side.add_theme_font_size_override("bold_font_size", 15)
	sc.add_child(side)
	var trow := HBoxContainer.new()    # RAID EXTRAS: when to go, and the player's mark of the place
	trow.add_theme_constant_override("separation", 6)
	for tid in ["day", "night"]:
		var tb := UI.button(String(game.raidx.time_cfg(tid).get("name", tid)))
		tb.pressed.connect(func(): set_time(tid))
		trow.add_child(tb)
		time_btns.append(tb)
	mark_btn = UI.button("")
	mark_btn.pressed.connect(cycle_mark)
	trow.add_child(mark_btn)
	sc.add_child(trow)
	fuel_c = Canvas.new()    # RAID EXTRAS: the fuel gauge
	fuel_c.custom_minimum_size = Vector2(300, 26)
	fuel_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fuel_c.draw_cb = _draw_fuel
	fuel_c.input_cb = func(_ev): pass
	sc.add_child(fuel_c)
	note = UI.label("", UI.SMALL_PX + 1, Color(1, 0.6, 0.5))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 300.0
	sc.add_child(note)
	go_btn = UI.button("Go", true, UI.BUTTON_PX + 2)
	go_btn.custom_minimum_size.y = 40
	go_btn.pressed.connect(go)
	sc.add_child(go_btn)
	root.visible = false
	game.hud.add_child(root)


func select(i: int) -> void:
	sel = clampi(i, 0, ids.size() - 1)
	_refresh()


func go() -> void:
	if not is_open:
		return
	var id := String(ids[sel])
	if status(id).ok:
		game.raidx.time = pick_time    # (the raid reads it when it begins)
		loot.go_to(id)


func set_time(t: String) -> void:
	if not game.raidx.time_cfg(t).is_empty():
		pick_time = t
		_refresh()


## X: the mark of the chosen place goes none, done, avoid, none.
func cycle_mark() -> void:
	game.raidx.cycle_mark(String(ids[sel]))
	_refresh()


func _refresh() -> void:
	var id := String(ids[sel])
	var pc: Dictionary = loot.place_cfg(id)
	var kc: Dictionary = loot.kind_cfg(id)
	var stt := status(id)
	var b := "[b]%s[/b]\n%s\n\n" % [String(pc.name), String(pc.blurb)]
	b += "[b]You may find:[/b]\n"
	for f in pc.finds:
		b += "   %s  [color=#%s]%s[/color]\n" % [String(f[0]), (TAGS[String(f[1])] as Color).to_html(false), String(f[1])]
	var dg := clampi(int(pc.danger), 1, 5)
	b += "\n[b]Danger:[/b] "
	side.text = ""
	side.append_text(b)
	for i in 5:    # five pips, the lit ones red (drawn squares, not "##---")
		side.add_image(_pip(i < dg), 12, 12)
		side.add_text(" ")
	b = " %s\n" % DANGER_WORD[dg]
	b += "[b]The dead:[/b] %s\n" % _crowd(float(kc.get("dead_mult", 1.0)))
	b += "[b]Watch for:[/b] %s\n" % String(pc.threats)
	var fc := int(pc.get("fuel", 0))
	fuel_c.visible = fc > 0    # (no gauge for a trip that costs no fuel)
	b += "[b]Travel:[/b] %s km%s\n" % [str(pc.dist), (", costs %d fuel" % fc) if fc > 0 else ", no fuel"]
	var cv: Array = covers(id)
	if not cv.is_empty() and bool(stt.open):
		b += "[color=#80e080][b]Covers what the base lacks:[/b] %s[/color]\n" % ", ".join(cv)
	if bool(pc.get("convoy", false)):
		b += "[color=#9ab8ff]The convoy's list is filled fastest here.[/color]\n"
	if bool(stt.open) and game.arc.stash_line() != "":
		b += "[color=#ffc040]%s[/color]\n" % game.arc.stash_line()
	var mk: String = game.raidx.mark_of(id)
	if mk == "done":
		b += "[color=#80e080]You marked this place done.[/color]\n"
	elif mk == "avoid":
		b += "[color=#ff9080]You marked this place to avoid.[/color]\n"
	side.append_text(b)
	note.text = String(stt.why)
	go_btn.disabled = not bool(stt.ok)
	go_btn.text = "Go to %s" % String(pc.name) if bool(stt.ok) else ("Closed" if not bool(stt.open) else ("Not enough fuel" if bool(stt.get("fuel_short", false)) else "Go to %s" % String(pc.name)))
	for i in time_btns.size():
		var tid: String = ["day", "night"][i]
		(time_btns[i] as Button).add_theme_color_override("font_color", Color(1, 0.85, 0.3) if tid == pick_time else Color(0.75, 0.75, 0.75))
		(time_btns[i] as Button).text = "%s%s" % [String(game.raidx.time_cfg(tid).get("name", tid)), " (T)" if tid != pick_time else " *"]
	mk = game.raidx.mark_of(id)
	mark_btn.text = "Mark (X): %s" % (String(game.raidx.cfg().mark_words.get(mk, "none")) if mk != "" else "none")
	canvas.queue_redraw()


static var _pips := {}


## A danger pip: a flat square with the dark outline, red when lit, grey when not.
static func _pip(on: bool) -> ImageTexture:
	if not _pips.has(on):
		var im := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		im.fill(Color("#0e1a15"))
		im.fill_rect(Rect2i(2, 2, 8, 8), Color("#e0584a") if on else Color("#4a524c"))
		_pips[on] = ImageTexture.create_from_image(im)
	return _pips[on]


static func _crowd(m: float) -> String:
	if m < 0.9:
		return "fewer than usual"
	if m <= 1.1:
		return "the usual crowd"
	if m <= 1.5:
		return "a bigger crowd than usual"
	if m <= 2.0:
		return "a large crowd"
	return "a very large crowd"


func key(ev: InputEvent) -> bool:
	if not is_open or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return is_open
	var k: int = ev.keycode
	if k >= KEY_1 and k < KEY_1 + ids.size():
		select(k - KEY_1)
	elif k == KEY_LEFT or k == KEY_A or k == KEY_UP or k == KEY_W:
		select(posmod(sel - 1, ids.size()))
	elif k == KEY_RIGHT or k == KEY_D or k == KEY_DOWN or k == KEY_S or k == KEY_TAB:
		select((sel + 1) % ids.size())
	elif k == KEY_T:
		set_time("night" if pick_time == "day" else "day")
	elif k == KEY_X:
		cycle_mark()
	elif k == KEY_E or k == KEY_ENTER or k == KEY_KP_ENTER:
		go()
	elif k == KEY_ESCAPE or k == KEY_M:
		close()
	return true


# ------------------------------------------------------------------ drawing --

func _pos(id: String, sz: Vector2) -> Vector2:
	var m: Array = loot.place_cfg(id).map
	return Vector2(float(m[0]) * sz.x, float(m[1]) * sz.y)


func _map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		hover_i = _near(ev.position)
		canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover_i >= 0 else Control.CURSOR_ARROW
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var best := _near(ev.position)
		if best >= 0:
			UI.click(game)
			select(best)


## The marker within 30 points of `at` on the map (the nearest), or -1.
func _near(at: Vector2) -> int:
	var best := -1
	var bd := 30.0
	for i in ids.size():
		var d := _pos(String(ids[i]), canvas.size).distance_to(at)
		if d < bd:
			bd = d
			best = i
	return best


const FOOT_H := 46.0    # the band at the foot of the map: what the hour and the weather mean


func _draw_map(c: Canvas) -> void:
	var sz := c.size
	var font := ThemeDB.fallback_font
	var t := Time.get_ticks_msec() / 1000.0
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.13, 0.17, 0.12))
	for i in range(1, 8):    # (a faint grid: a map, not a picture)
		c.draw_line(Vector2(sz.x * i / 8.0, 0), Vector2(sz.x * i / 8.0, sz.y), Color(1, 1, 1, 0.035), 1.0)
		c.draw_line(Vector2(0, sz.y * i / 8.0), Vector2(sz.x, sz.y * i / 8.0), Color(1, 1, 1, 0.035), 1.0)
	var sea := PackedVector2Array([Vector2(0.64, 1.0), Vector2(0.7, 0.95), Vector2(0.8, 0.93), Vector2(0.9, 0.89), Vector2(1.0, 0.87), Vector2(1.0, 1.0)])
	for i in sea.size():
		sea[i] *= sz
	c.draw_colored_polygon(sea, Color(0.12, 0.23, 0.36))
	for w in 3:    # (waves)
		var y := sz.y * (0.95 + 0.015 * w)
		c.draw_line(Vector2(sz.x * (0.78 + 0.05 * w), y), Vector2(sz.x * (0.84 + 0.05 * w), y), Color(0.4, 0.6, 0.8, 0.35), 1.5)
	c.draw_line(Vector2(0.03, 0.93) * sz, Vector2(0.21, 0.79) * sz, Color(0.38, 0.4, 0.45), 9.0)    # the airport's runway
	c.draw_line(Vector2(0.03, 0.93) * sz, Vector2(0.21, 0.79) * sz, Color(0.9, 0.9, 0.8, 0.55), 1.5)
	c.draw_arc(_pos("stadium", sz) + Vector2(0, 0), 30.0, 0, TAU, 40, Color(0.42, 0.43, 0.4), 3.0)    # the stadium's bowl (concrete grey: a green ring is the shortage mark, and the stadium may be locked)
	var base := Vector2(0.5, 0.52) * sz
	for id in ids:
		var op: bool = status(String(id)).open
		var p := _pos(String(id), sz)
		var mid := (base + p) * 0.5 + Vector2((p - base).y, -(p - base).x) * 0.12
		var rc := Color(0.45, 0.45, 0.4, 0.9) if op else Color(0.3, 0.3, 0.3, 0.6)
		c.draw_polyline(PackedVector2Array([base, mid, p]), Color(0.05, 0.05, 0.05, 0.8), 6.0)
		c.draw_polyline(PackedVector2Array([base, mid, p]), rc, 3.0)
	c.draw_rect(Rect2(base - Vector2(15, 11), Vector2(30, 22)), Color(0.28, 0.3, 0.34))    # the prison
	c.draw_rect(Rect2(base - Vector2(15, 11), Vector2(30, 22)), Color(0.9, 0.85, 0.7), false, 2.0)
	c.draw_string(font, base + Vector2(-60, 28), "THE PRISON", HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(0.95, 0.9, 0.75))
	var placed: Array = []    # the names already written: a name that would run into one goes to the other side of its marker
	for i in ids.size():
		var id := String(ids[i])
		var pc: Dictionary = loot.place_cfg(id)
		var stt := status(id)
		var p := _pos(id, sz)
		var tint := Color(String(pc.get("tint", loot.kind_cfg(id).get("tint", "#c0c0c0"))))
		var fill := tint.darkened(0.25) if bool(stt.open) else Color(0.28, 0.28, 0.3)
		if bool(stt.open) and not covers(id).is_empty():
			var pulse := 0.5 + 0.5 * sin(t * 4.0)
			c.draw_circle(p, 24.0 + 3.0 * pulse, Color(0.4, 1.0, 0.5, 0.18 + 0.12 * pulse))
			c.draw_arc(p, 22.0, 0, TAU, 32, Color(0.5, 1.0, 0.55, 0.95), 2.5)
		c.draw_circle(p, 16.0, Color(0.03, 0.03, 0.03))
		c.draw_circle(p, 14.0, fill)
		c.draw_string(font, p + Vector2(-14, 5), String(pc.get("tag", "??")), HORIZONTAL_ALIGNMENT_CENTER, 28, 14, Color(0.05, 0.05, 0.05) if bool(stt.open) else Color(0.6, 0.6, 0.62))
		if i == sel:
			c.draw_arc(p, 19.0 + 1.5 * sin(t * 6.0), 0, TAU, 32, Color(1, 1, 1), 3.0)
		elif i == hover_i:    # (the pointer is on it: a click picks it)
			c.draw_arc(p, 19.0, 0, TAU, 32, Color(1, 0.9, 0.6, 0.7), 2.0)
		var lab := String(pc.name) if bool(stt.open) else "%s (day %d)" % [String(pc.name), int(pc.get("unlock_day", 1))]
		var lc := Color(0.95, 0.95, 0.9) if bool(stt.open) else Color(0.55, 0.55, 0.58)
		var ly := p.y + 32.0 if p.y + 44.0 < sz.y - FOOT_H else p.y - 34.0    # (a name that would run into the two lines at the foot of the map goes over its marker)
		var lw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var clash := func(y: float) -> bool:
			if y + 12.0 > sz.y - FOOT_H:
				return true
			for pr in placed:
				if (pr as Rect2).intersects(Rect2(p.x - lw / 2.0, y - 14.0, lw, 26.0)):
					return true
			return false
		if clash.call(ly):
			ly = p.y - 34.0 if ly > p.y else p.y + 32.0
		var named: bool = not clash.call(ly)    # (no room on either side, on a small map: the marker's letters alone; the side panel names it when it is picked)
		if named:
			placed.append(Rect2(p.x - lw / 2.0, ly - 14.0, lw, 26.0))
		if named:
			c.draw_string(font, Vector2(p.x - 80.0, ly), lab, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, lc)
		var dg := clampi(int(pc.danger), 1, 5)
		for d in (5 if named else 0):    # (danger pips under the name)
			c.draw_circle(Vector2(p.x - 20.0 + d * 10.0, ly + 8.0), 3.0, Color(0.9, 0.3, 0.25) if d < dg and bool(stt.open) else (Color(0.4, 0.2, 0.2) if d < dg else Color(0.25, 0.25, 0.25)))
		var mk: String = game.raidx.mark_of(id)    # the player's mark: a badge on the marker
		if mk != "":
			var bp := p + Vector2(13.0, -13.0)
			var bc := Color(0.35, 0.8, 0.45) if mk == "done" else Color(0.9, 0.3, 0.25)
			c.draw_circle(bp, 9.0, Color(0.03, 0.03, 0.03))
			c.draw_circle(bp, 7.5, bc.darkened(0.2))
			if mk == "done":
				PIcons.draw(c, "check", bp, 12.0, Color(1, 1, 1))
			else:    # (PIcons' "cross" is the medic's plus: avoid is an X)
				c.draw_line(bp + Vector2(-3.5, -3.5), bp + Vector2(3.5, 3.5), Color(1, 1, 1), 2.2)
				c.draw_line(bp + Vector2(-3.5, 3.5), bp + Vector2(3.5, -3.5), Color(1, 1, 1), 2.2)
	var wid: String = game.raidx.forecast()    # today's weather and the chosen hour, in the corner
	var wcol := Color("#9fc4e8") if wid == "rain" else (Color("#c9d0d2") if wid == "fog" else Color(1.0, 0.85, 0.4))
	PIcons.draw(c, {"rain": "rain", "fog": "fog"}.get(wid, "sun"), Vector2(20, 20), 22.0, wcol)
	c.draw_string(font, Vector2(36, 26), "%s, %s" % [String(game.raidx.weather_cfg(wid).get("name", "")), String(game.raidx.time_cfg(pick_time).get("name", "")).to_lower()], HORIZONTAL_ALIGNMENT_LEFT, 200, 15, Color(0.92, 0.92, 0.88))
	var wc: Dictionary = game.raidx.weather_cfg(wid)    # what the choices mean, in the map's corner
	var tc: Dictionary = game.raidx.time_cfg(pick_time)
	c.draw_rect(Rect2(0, sz.y - FOOT_H, sz.x, FOOT_H), Color(0.05, 0.06, 0.07, 0.72))    # (their own dark band: the airport's name ran under them)
	c.draw_string(font, Vector2(10, sz.y - 30), "%s: %s" % [String(tc.get("name", "")), String(tc.get("note", ""))], HORIZONTAL_ALIGNMENT_LEFT, sz.x - 20, 13, Color(0.92, 0.92, 0.88))
	c.draw_string(font, Vector2(10, sz.y - 12), "%s: %s" % [String(wc.get("name", "")), String(wc.get("note", ""))], HORIZONTAL_ALIGNMENT_LEFT, sz.x - 20, 13, wcol)
	if pick_time == "night":    # (a dark wash over the map: the night choice is felt)
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.08, 0.2, 0.28))


## The fuel gauge: what the tank holds against what the chosen trip costs.
func _draw_fuel(c: Canvas) -> void:
	var font := ThemeDB.fallback_font
	var fuel := float(game.stores.get("fuel", 0.0))
	var cost := float(loot.place_cfg(String(ids[sel])).get("fuel", 0))
	var cap := maxf(maxf(float(game.econ.caps().get("fuel", 10.0)), fuel), maxf(cost, 1.0))
	var bar := Rect2(64, 7, c.size.x - 64.0, 12)
	var ok := fuel >= cost
	c.draw_string(font, Vector2(0, 18), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, 60, 14, Color(0.85, 0.85, 0.8))
	c.draw_rect(bar, Color(0.12, 0.12, 0.12))
	c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(fuel / cap, 0.0, 1.0), bar.size.y)), Color(0.4, 0.8, 0.45) if ok else Color(0.9, 0.35, 0.3))
	c.draw_rect(bar, Color(0.7, 0.7, 0.65), false, 1.0)
	if cost > 0.0:    # (the trip's cost: a white tick on the bar)
		var x := bar.position.x + bar.size.x * clampf(cost / cap, 0.0, 1.0)
		c.draw_line(Vector2(x, 3), Vector2(x, 23), Color(1, 1, 1), 2.0)
	c.draw_string(font, Vector2(bar.position.x, 18), "%d now / trip %d" % [int(fuel), int(cost)], HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x - 6.0, 13, Color(1, 1, 1))    # (at the right end: the trip's tick sits at the left end of a big tank and cut through the words)
