## The radio panel (round 18, slice 2): the colony's interface in avatar mode, one NON-MODAL board on the right of the window with four
## pages, Jobs, Build, Map and News (the old Duty roster, Build screen, Town Board and News log, as pages one asks things of). It never
## pauses the game, takes no key (every control of it is FOCUS_NONE: W A S D and E keep working while it is up) and never covers the clock,
## the gun's readout or the toolbar: the HUD puts it under the right column, over the toolbar, and keeps the avatar in view (`hud.free_view()`,
## main.gd's camera). The modal pages are still there as the FULL pages (Shift+J, Shift+N, Shift+G, and each page's "Full page" button).
##
## A child of the HUD, in the HUD's board look (the HUD lends its colours and helpers: `host.PANEL`, `host._label()`...):
##
##   var p := RadioPanel.new(); hud.add_child(p)
##   p.setup(hud, func(): return sim)                 # the sim (the panel gets the radio from it)
##   p.open("jobs", {"focus": "dez"})                 # a page ("" = the last one; News the first time); opts.focus goes to the page's `focus_on`
##   p.toggle("map"); p.close(); p.is_open(); p.page() # the page that is up ("" while shut); p.last_page is the one it was left on
##   p.refresh()                                       # each HUD update (10 Hz): the tabs and the open page only
##   p.fit(max_h, max_w); p.set_compact(on)            # the HUD says how much room there is (a narrow window has the narrow form)
##
## Every page node has the same four functions: `setup(host, sim_getter, options := {})`, `refresh()`, `focus_on(id)` (a person, a station, a
## building, a place) and `full_page()` (the modal version, through the HUD). Pages are built when first asked for and kept. The News page is
## news_panel.gd; the others are scripts/ui/jobs_page.gd, build_page.gd and map_page.gd (loaded when needed: a page that does not load takes
## down only itself). The Map page is there in a settlement game only (`sim.town.on`).
##
## While a page other than News is up, the oldest call that waits for an answer stays in view as a slim strip under the tabs (call_card.gd:
## a decision is never hidden behind a page); on News the page's own list has it, as in round 17. The News tab wears a gold dot while there
## is something unread and a "!" while a call waits.
extends PanelContainer

const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const NewsPanel := preload("res://scripts/ui/news_panel.gd")
const CallCard := preload("res://scripts/ui/call_card.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## The panel was opened, shut, or moved to another page.
signal changed

const PAGES := ["jobs", "build", "map", "news"]
const PAGE_NAMES := {"jobs": "Jobs", "build": "Build", "map": "Map", "news": "News"}
const PAGE_KEYS := {"jobs": "J", "build": "N", "map": "G", "news": "T"}
const PAGE_TIPS := {
	"jobs": "Jobs: who works where by day and holds which post at night. You ask, and they answer",
	"build": "Build: pick a building, and the Builders raise it where it belongs",
	"map": "Map: the places on the road and the parties out. Take control of a trip, or ask someone to go",
	"news": "News: what the radio heard, and the calls that wait for your answer",
}
## Where the pages of the others are (loaded when first asked for).
const PAGE_PATHS := {
	"jobs": "res://scripts/ui/jobs_page.gd",
	"build": "res://scripts/ui/build_page.gd",
	"map": "res://scripts/ui/map_page.gd",
}
const WIDTH := 440.0
const WIDTH_COMPACT := 316.0
const MIN_H := 280.0
## The least the page area is tall, whatever the room (it scrolls).
const MIN_PAGE_H := 60.0

var host
## The page the panel was left on (News the first time): `open("")` goes there.
var last_page := "news"
## Page id to its node, for the pages built so far.
var pages := {}
## Page id to its tab (a small button).
var tabs := {}
var close_button: Button
## The slim strip of the oldest call, under the tabs.
var call_strip
var scroll: ScrollContainer
var _sim_getter: Callable
var _page := ""
var _compact := false
var _built := false
var _head: HBoxContainer
var _marks := {}
var _lit := "?"
var _col: VBoxContainer


func setup(host_hud, sim_getter: Callable) -> void:
	host = host_hud
	_sim_getter = sim_getter
	if _built:
		return
	_built = true
	add_theme_stylebox_override("panel", host._style(host.PANEL, 6, host.LINE, true, "panel"))
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = WIDTH
	_col = host._vbox(6)
	add_child(_col)
	_head = host._hbox(4)
	_col.add_child(_head)
	for page in PAGES:
		_head.add_child(_make_tab(String(page)))
	_head.add_child(host._spacer())
	close_button = RadioKit.small_button(host, "×", 26.0, 18)
	close_button.custom_minimum_size.x = 30.0
	close_button.tooltip_text = "Close the radio panel\nKey: Esc, or the key of the page"
	close_button.pressed.connect(close)
	_head.add_child(close_button)
	var radio_getter := func():
		var s = _sim()
		return s.get("radio") if s != null else null
	call_strip = CallCard.new()
	_col.add_child(call_strip)
	call_strip.setup(host, radio_getter, {"speed_getter": _speed_getter(), "slim": true})
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, MIN_H - 80.0)
	_col.add_child(scroll)
	visible = false


func _sim():
	return _sim_getter.call() if _sim_getter.is_valid() else null


func _speed_getter() -> Callable:
	return func(): return maxi(int(host.get("last_speed")) if host != null and host.get("last_speed") != null else 1, 1)


# ------------------------------------------------------------------------- the tabs --

func _make_tab(page: String) -> Button:
	var b := RadioKit.small_button(host, String(PAGE_NAMES[page]), 26.0, 13)
	b.custom_minimum_size.x = 66.0 if page == "news" else 52.0
	b.tooltip_text = _tab_tip(page, false)
	b.pressed.connect(_on_tab.bind(page))
	# the marks (a dot for what is unread, a "!" for a call that waits) are drawn over the tab's right end
	var marks := Control.new()
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marks.set_meta("dot", false)
	marks.set_meta("bang", false)
	marks.draw.connect(_draw_marks.bind(marks))
	b.add_child(marks)
	_marks[page] = marks
	tabs[page] = b
	return b


## The tooltip of a tab: what the page is, its key and, for the pages that have one, the key of its full (modal) page.
func _tab_tip(page: String, call_waits: bool) -> String:
	var key := String(PAGE_KEYS[page])
	var text := "%s\nKey: %s" % [PAGE_TIPS[page], key]
	if page != "news":
		text += " (Shift+%s: the full page)" % key
	if call_waits:
		text += "\nA call waits for your answer"
	return text


func _on_tab(page: String) -> void:
	if is_open() and _page == page:
		return
	open(page)


func _draw_marks(c: Control) -> void:
	if bool(c.get_meta("bang", false)):
		var at := Vector2(c.size.x - 11.0, c.size.y * 0.5)
		c.draw_circle(at, 7.0, host.WARN)
		var font: Font = Fonts.cond(700, 0)
		c.draw_string(font, at + Vector2(-2.5, 4.5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, host.ACCENT_INK)
	elif bool(c.get_meta("dot", false)):
		c.draw_circle(Vector2(c.size.x - 8.0, 8.0), 3.5, host.ACCENT)


## The look of a tab: the page that is up is lit (the gold of a main choice).
func _style_tab(page: String, on: bool) -> void:
	var b: Button = tabs[page]
	for state in ["normal", "hover", "pressed", "disabled"]:
		var st: StyleBox = host._button_style(state, on, false, false)
		st.content_margin_top = 0
		st.content_margin_bottom = 0
		st.content_margin_left = 6
		st.content_margin_right = 6
		b.add_theme_stylebox_override(state, st)
	var ink: Color = host.ACCENT_INK if on else host.INK
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, ink)


func tab_button(page: String) -> Button:
	return tabs.get(page)


## What a tab wears now: {"dot": there is something unread, "bang": a call waits for an answer} (only the News tab has either).
func tab_marks(page: String) -> Dictionary:
	var m = _marks.get(page)
	if m == null:
		return {"dot": false, "bang": false}
	return {"dot": bool(m.get_meta("dot")), "bang": bool(m.get_meta("bang"))}


## Whether the page can be had: the Map is for a settlement game (`sim.town.on`); in Orientation Day (`host.tutorial_ui`: its lessons teach
## the modal pages, and the coach's lock is the modal pages' key) the News is the only page, so that no tab goes round the lock.
func page_available(page: String) -> bool:
	if not PAGES.has(page):
		return false
	if page != "news" and host != null and bool(host.get("tutorial_ui")):
		return false
	if page == "map":
		var sim = _sim()
		var town = sim.get("town") if sim != null else null
		return town != null and bool(town.on)
	return true


## The marks and the lit tab, brought up to date.
func _sync_tabs() -> void:
	if tabs.is_empty():
		return
	for page in PAGES:
		var here := page_available(String(page))
		if tabs[page].visible != here:
			tabs[page].visible = here
	var news = page_node("news")
	var shown_news := is_open() and _page == "news"
	var radio = _radio()
	var dot: bool = news != null and not shown_news and news.unread() > 0
	var bang: bool = radio != null and not shown_news and not radio.open_calls().is_empty()
	var marks: Control = _marks["news"]
	if bool(marks.get_meta("dot")) != dot or bool(marks.get_meta("bang")) != bang:
		marks.set_meta("dot", dot)
		marks.set_meta("bang", bang)
		marks.queue_redraw()
	var lit := _page if is_open() else ""
	if lit != _lit:
		for page in PAGES:
			_style_tab(String(page), String(page) == lit)
		_lit = lit
	var news_tip := _tab_tip("news", bang)
	if tabs["news"].tooltip_text != news_tip:
		tabs["news"].tooltip_text = news_tip


func _radio():
	var s = _sim()
	return s.get("radio") if s != null else null


# ------------------------------------------------------------------------ the pages --

## The node of a page, made the first time it is asked for ("" for no such page, or one that does not load).
func page_node(page: String) -> Control:
	if pages.has(page):
		return pages[page]
	if not PAGES.has(page) or scroll == null:
		return null
	var node: Control = null
	var opts := {"panel": self, "speed_getter": _speed_getter()}
	if page == "news":
		node = NewsPanel.new()
		scroll.add_child(node)
		opts["embedded"] = true
		node.setup(host, _sim_getter, opts)
	else:
		var script = load(String(PAGE_PATHS[page]))
		if script == null or not script.can_instantiate():
			return null
		node = script.new()
		scroll.add_child(node)
		node.setup(host, _sim_getter, opts)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.visible = false
	if _compact and node.has_method("set_compact"):
		node.set_compact(true)
	pages[page] = node
	return node


func is_open() -> bool:
	return visible


## The page that is up ("" while the panel is shut).
func page() -> String:
	return _page if visible else ""


## Opens the panel on `page` ("" for the one it was left on; News the first time), or moves it there. `opts.focus` is handed to the page's
## `focus_on`. A page that is not there (the Map in the classic start) leaves things as they are.
func open(page_id: String = "", opts: Dictionary = {}) -> void:
	if host == null:
		return
	var want := page_id if page_id != "" else last_page
	if not page_available(want):
		if page_id != "":
			return
		want = "news"
	var node := page_node(want)
	if node == null:
		return
	var was := _page if visible else ""
	if was == want and visible and not opts.has("focus"):
		return
	if was == "news" and want != "news":
		_read_news()
	if was != "" and was != want and pages.has(was):
		pages[was].visible = false
		_clear_marks(was)
	_page = want
	last_page = want
	visible = true
	node.visible = true
	_sync_tabs()
	refresh()
	if opts.has("focus") and node.has_method("focus_on"):
		node.focus_on(String(opts.focus))
	if was != want:
		changed.emit()


func close() -> void:
	if not visible:
		return
	if _page == "news":
		_read_news()
	if pages.has(_page):
		pages[_page].visible = false
	_clear_marks(_page)
	visible = false
	_page = ""
	_sync_tabs()
	changed.emit()


## The key of a page: the page opens, the same key shuts it, another page's key moves to it ("" is T: the last page, or shut).
func toggle(page_id: String = "") -> void:
	if visible and (page_id == "" or page_id == _page):
		close()
	else:
		open(page_id)


## A page that marks a place in the yard while the pointer is on one of its rows (Jobs: a station, a post, a person; Build: a plot) lets go of
## it when it is left or the panel is shut (the modal screens do the same when they close).
func _clear_marks(page_id: String) -> void:
	if host == null:
		return
	if page_id == "jobs" and host.get("jobs_screen") == null and not host.jobs_hover.is_empty():
		host.set_jobs_hover({})
	elif page_id == "build" and host.get("build_screen") == null and not host.build_hover.is_empty():
		host.set_build_hover({})


func _read_news() -> void:
	var news = pages.get("news")
	if news != null:
		news.mark_read()


## The full (modal) version of the page that is up, or of the last one: through the HUD.
func full_page() -> void:
	var node := page_node(_page if _page != "" else last_page)
	if node != null and node.has_method("full_page"):
		node.full_page()


## The tabs, the strip and the open page, brought up to date (the HUD does it with each update).
func refresh() -> void:
	if host == null or not _built:
		return
	if visible and _page == "map" and not page_available("map"):
		open("news")
		return
	_sync_tabs()
	if not visible:
		return
	call_strip.set_suppressed(_page == "news")
	call_strip.refresh()
	var node = pages.get(_page)
	if node != null:
		node.refresh()


# ------------------------------------------------------------------------- fitting --

## The narrow form (a window under 980 px wide).
func set_compact(on: bool) -> void:
	if on == _compact:
		return
	_compact = on
	custom_minimum_size.x = WIDTH_COMPACT if on else WIDTH
	for node in pages.values():
		if node.has_method("set_compact"):
			node.set_compact(on)


func is_compact() -> bool:
	return _compact


## Makes the panel as tall as its page wants, at least MIN_H and at most `max_h` (what does not fit scrolls), and as wide as its form,
## at most `max_w`.
func fit(max_h: float, max_w: float = INF) -> void:
	if not visible or scroll == null:
		return
	custom_minimum_size.x = minf(WIDTH_COMPACT if _compact else WIDTH, maxf(180.0, max_w))
	var node = pages.get(_page)
	if node == null:
		return
	var chrome := get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
	if _page == "news":
		node.fit(maxf(MIN_PAGE_H, max_h - chrome))
	var want: float = node.get_combined_minimum_size().y
	var h := minf(maxf(chrome + want, MIN_H), max_h)
	scroll.custom_minimum_size.y = maxf(MIN_PAGE_H, h - chrome)
