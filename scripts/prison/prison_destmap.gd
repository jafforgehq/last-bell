## The DESTINATION MAP of the gate: a code-drawn map of the town round the prison with the named places of `places` in assets/data/prison_raids.json as markers. Click a marker (or Left/Right/Tab,
## or the number keys) and the side panel names it, says in plain words what a trip there may find (often / sometimes / rarely, never a number), its danger, the dead, the fuel it costs and a Go button.
## Places not open yet are grey with the reason. Places that cover what the base is short of (prison_loot.gd `short_res`) pulse green. Opened by E at the truck (loot.open_choice) or M at the base (view only).
## Go calls loot.go_to(id). Pure view: every number is the data's.
extends RefCounted

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


func _init(l, g) -> void:
	loot = l
	game = g
	ids = loot.place_ids()


func open(view: bool, forced_id: String) -> void:
	view_only = view
	forced = forced_id
	day = int(game.econ.day) if game.econ != null else 1
	shorts = loot.short_res()
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
	root.visible = true
	root.reset_size()
	root.position = Vector2(10.0, maxf(100.0, (game._vp().y - root.size.y) / 2.0))    # (clear of the top bar and the objectives list on the right)
	_refresh()


func close() -> void:
	is_open = false
	loot.choosing = false
	if root != null:
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
		return {"ok": false, "open": true, "why": "The truck needs %d fuel for the trip; the stores hold %d." % [fc, int(fuel)]}
	if view_only:
		return {"ok": false, "open": true, "why": "To go, walk to the truck and press E."}
	return {"ok": true, "open": true, "why": ""}


func _build() -> void:
	root = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.07, 1.0)
	st.border_color = Color(0.85, 0.7, 0.3)
	st.set_border_width_all(2)
	st.set_content_margin_all(12)
	root.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	var title := Label.new()
	title.text = "WHERE TO?   Click a place. Left/Right or Tab to move, Enter or E to go, Esc to stay."
	title.add_theme_font_size_override("font_size", 17)
	col.add_child(title)
	sub = Label.new()
	sub.add_theme_font_size_override("font_size", 15)
	sub.modulate = Color(1, 0.85, 0.5)
	col.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	canvas = Canvas.new()
	var vp: Vector2 = game._vp()
	var cw := clampf(vp.x - 700.0, 360.0, 600.0)
	canvas.custom_minimum_size = Vector2(cw, clampf(cw * 0.78, 280.0, vp.y - 130.0))
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw_cb = _draw_map
	canvas.input_cb = _map_input
	row.add_child(canvas)
	var sc := VBoxContainer.new()
	sc.custom_minimum_size = Vector2(300, 0)
	sc.add_theme_constant_override("separation", 6)
	row.add_child(sc)
	side = RichTextLabel.new()
	side.bbcode_enabled = true
	side.fit_content = false
	side.scroll_active = false
	side.custom_minimum_size = Vector2(300,canvas.custom_minimum_size.y - 70.0)
	side.add_theme_font_size_override("normal_font_size", 15)
	side.add_theme_font_size_override("bold_font_size", 17)
	sc.add_child(side)
	note = Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 300.0
	note.add_theme_font_size_override("font_size", 14)
	note.modulate = Color(1, 0.6, 0.5)
	sc.add_child(note)
	go_btn = Button.new()
	go_btn.focus_mode = Control.FOCUS_NONE
	go_btn.add_theme_font_size_override("font_size", 20)
	go_btn.text = "Go"
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
		loot.go_to(id)


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
	b += "\n[b]Danger:[/b] %s %s\n" % ["#".repeat(dg) + "-".repeat(5 - dg), DANGER_WORD[dg]]
	b += "[b]The dead:[/b] %s\n" % _crowd(float(kc.get("dead_mult", 1.0)))
	b += "[b]Watch for:[/b] %s\n" % String(pc.threats)
	var fc := int(pc.get("fuel", 0))
	b += "[b]Travel:[/b] %s km%s\n" % [str(pc.dist), (", costs %d fuel" % fc) if fc > 0 else ", no fuel"]
	var cv: Array = covers(id)
	if not cv.is_empty() and bool(stt.open):
		b += "[color=#80e080][b]Covers what the base lacks:[/b] %s[/color]\n" % ", ".join(cv)
	if bool(pc.get("convoy", false)):
		b += "[color=#9ab8ff]The convoy's list is filled fastest here.[/color]\n"
	side.text = ""
	side.append_text(b)
	note.text = String(stt.why)
	go_btn.disabled = not bool(stt.ok)
	go_btn.text = "Go to %s" % String(pc.name) if bool(stt.ok) else ("Closed" if not bool(stt.open) else "Go to %s" % String(pc.name))
	canvas.queue_redraw()


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
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var best := -1
		var bd := 30.0
		for i in ids.size():
			var d := _pos(String(ids[i]), canvas.size).distance_to(ev.position)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			select(best)


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
	c.draw_arc(_pos("stadium", sz) + Vector2(0, 0), 30.0, 0, TAU, 40, Color(0.4, 0.6, 0.35), 3.0)    # the stadium's bowl
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
		var lab := String(pc.name) if bool(stt.open) else "%s (day %d)" % [String(pc.name), int(pc.get("unlock_day", 1))]
		var lc := Color(0.95, 0.95, 0.9) if bool(stt.open) else Color(0.55, 0.55, 0.58)
		var ly := p.y + 32.0 if p.y < sz.y - 40.0 else p.y - 22.0
		c.draw_string(font, Vector2(p.x - 80.0, ly), lab, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, lc)
		var dg := clampi(int(pc.danger), 1, 5)
		for d in 5:    # (danger pips under the name)
			c.draw_circle(Vector2(p.x - 20.0 + d * 10.0, ly + 8.0), 3.0, Color(0.9, 0.3, 0.25) if d < dg and bool(stt.open) else (Color(0.4, 0.2, 0.2) if d < dg else Color(0.25, 0.25, 0.25)))
