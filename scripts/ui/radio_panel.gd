## The radio panel (round 18, slice 2): the colony's interface in avatar mode, one NON-MODAL board on the right of the window with five
## pages, Base, Jobs, Build, Map and News (the old Duty roster, Build screen, Town Board and News log, as pages one asks things of; round 25 adds
## the Base page, where the base is run by priorities and dials and the briefing's concerns are handled). It never
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
## news_panel.gd; the others are scripts/ui/base_page.gd, jobs_page.gd, build_page.gd and map_page.gd (loaded when needed: a page that does not
## load takes down only itself). The Map page is there in a settlement game only (`sim.town.on`), and so is the Base page (an avatar game of the
## small start: `sim.priorities.active()`).
##
## While a page other than News is up, the oldest call that waits for an answer stays in view as a slim strip under the tabs (call_card.gd:
## a decision is never hidden behind a page); on News the page's own list has it, as in round 17. The News tab wears a gold dot while there
## is something unread and a "!" while a call waits. The Base tab (round 25) wears a "!" while a problem is at its second stage or a dilemma waits, and
## a gold dot while the morning's briefing has not been looked at (`note_briefing_seen`: the card or the page).
extends PanelContainer

const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const NewsPanel := preload("res://scripts/ui/news_panel.gd")
const CallCard := preload("res://scripts/ui/call_card.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## The panel was opened, shut, or moved to another page.
signal changed

const PAGES := ["base", "jobs", "build", "map", "news"]
const PAGE_NAMES := {"base": "Base", "jobs": "Jobs", "build": "Build", "map": "Map", "news": "News"}
const PAGE_KEYS := {"base": "B", "jobs": "J", "build": "N", "map": "G", "news": "T"}
const PAGE_TIPS := {
	"base": "Base: what the base worries about, your priorities, the four dials, what each station waits on and the trouble in the yard",
	"jobs": "Jobs: who works where by day and holds which post at night. You ask, and they answer",
	"build": "Build: pick a building, and the Builders raise it where it belongs",
	"map": "Map: the places on the road and the parties out. Take control of a trip, or ask someone to go",
	"news": "News: what the radio heard, and the calls that wait for your answer",
}
## Where the pages of the others are (loaded when first asked for).
const PAGE_PATHS := {
	"base": "res://scripts/ui/base_page.gd",
	"jobs": "res://scripts/ui/jobs_page.gd",
	"build": "res://scripts/ui/build_page.gd",
	"map": "res://scripts/ui/map_page.gd",
}
## One House (WP7): in the town the Build page is the base's projects (the front fence, the gate, a tower...) and the Map page is the district's map (built when `sim.is_one_house()`).
const TOWN_PAGE_PATHS := {
	"build": "res://scripts/ui/slot_page.gd",
	"map": "res://scripts/ui/district_map.gd",
}
const TOWN_PAGE_TIPS := {
	"build": "Build: fortify the house. The page says what to do next (the front fence first); one button orders a whole project, and the Builders raise it\nKey: N",
	"map": "Map: the town, the houses you have been in, the base and the people you know of\nKey: M",
}
## How wide a tab is at least in the whole form (five tabs, the close button and the gaps are under 340 px: a window that leaves the panel less is narrow).
const TAB_W := {"base": 48.0, "jobs": 48.0, "build": 50.0, "map": 46.0, "news": 60.0}
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
## The foot under the scroll: a page pins a strip there that stays in view while the page scrolls (`set_foot`; the Map's Take control and
## Ask). It shows while its page is up and its strip is not hidden.
var foot: VBoxContainer
var _foot_page := ""
var _foot_node: Control
var _sim_getter: Callable
var _page := ""
var _compact := false
var _built := false
var _head: HBoxContainer
var _marks := {}
var _lit := "?"
## The day whose briefing has been looked at (the card was shown, or the Base page was opened).
var _briefing_seen_day := 0
var _seen_init := false
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
	foot = host._vbox(0)
	foot.visible = false
	_col.add_child(foot)
	visible = false


func _sim():
	return _sim_getter.call() if _sim_getter.is_valid() else null


## Pins a strip of `page_id`'s under the scroll: it is in view whatever the page is scrolled to, while that page is up (and the strip is not
## hidden by the page). One strip at a time.
func set_foot(page_id: String, node: Control) -> void:
	if _foot_node != null and is_instance_valid(_foot_node):
		if _foot_node.visibility_changed.is_connected(_sync_foot):
			_foot_node.visibility_changed.disconnect(_sync_foot)
		if _foot_node.get_parent() == foot:
			foot.remove_child(_foot_node)
	_foot_page = page_id
	_foot_node = node
	if node == null:
		_sync_foot()
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	foot.add_child(node)
	node.visibility_changed.connect(_sync_foot)
	_sync_foot()


func _sync_foot() -> void:
	if foot == null:
		return
	var on: bool = visible and _foot_node != null and is_instance_valid(_foot_node) and _foot_node.visible and _page == _foot_page
	if foot.visible != on:
		foot.visible = on


func _speed_getter() -> Callable:
	return func(): return maxi(int(host.get("last_speed")) if host != null and host.get("last_speed") != null else 1, 1)


# ------------------------------------------------------------------------- the tabs --

func _make_tab(page: String) -> Button:
	var b := RadioKit.small_button(host, String(PAGE_NAMES[page]), 26.0, 13)
	b.custom_minimum_size.x = _tab_width(page)
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


## How wide a tab is at least: the whole form has room for a little more than the words; the narrow one (five tabs and the close button in 316 px) lets each be
## as wide as its word.
func _tab_width(page: String) -> float:
	if _compact:
		return 0.0
	return float(TAB_W.get(page, 48.0))


## The tooltip of a tab: what the page is, its key and, for the pages that have one, the key of its full (modal) page.
func _tab_tip(page: String, call_waits: bool) -> String:
	if TOWN_PAGE_TIPS.has(page) and _is_town():
		return String(TOWN_PAGE_TIPS[page])
	var key := String(PAGE_KEYS[page])
	var text := "%s\nKey: %s" % [PAGE_TIPS[page], key]
	if page != "news" and page != "base":
		text += " (Shift+%s: the full page)" % key
	if call_waits:
		text += "\nA call waits for your answer" if page == "news" else "\nSomething waits for you here"
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


## What a tab wears now: {"dot": there is something unread (Base: a briefing nobody has looked at), "bang": a call waits for an answer (Base: a problem is at its
## second stage, or a dilemma waits)} (only the News and the Base tabs have either).
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
		# (round 26: an avatar game with no town, an old Full crew save, has the tab too: the page says there is no town to go out to)
		return (town != null and bool(town.on)) or (sim != null and String(sim.get("player_id")) != "")
	if page == "base":
		# (round 25: the small start with an avatar, where the priorities and the dials are in play)
		var sim2 = _sim()
		var town2 = sim2.get("town") if sim2 != null else null
		var pr = sim2.get("priorities") if sim2 != null else null
		if town2 == null or not bool(town2.on) or pr == null or not pr.has_method("toggle"):
			return false
		return not pr.has_method("active") or bool(pr.active())
	return true


## Whether a page has no tab although it can be had (round 26: the demo's Jobs page is advanced and the briefing replaces it: the Base page's "Jobs (advanced)"
## and the full page, Shift+J, still open it).
func tab_hidden(page: String) -> bool:
	if page != "jobs":
		return false
	var sim = _sim()
	return sim != null and sim.has_method("is_demo") and sim.is_demo()


## The marks and the lit tab, brought up to date.
func _sync_tabs() -> void:
	if tabs.is_empty():
		return
	for page in PAGES:
		var here := page_available(String(page)) and not tab_hidden(String(page))
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
	# round 25: the Base tab's own marks
	if _marks.has("base"):
		if not _seen_init:
			# (a briefing that is already there when the panel first looks, a loaded game's, is not one that waits)
			_seen_init = true
			var sim0 = _sim()
			var b0 = sim0.get("briefing") if sim0 != null else null
			var cur0 = b0.get("current") if b0 != null else null
			if cur0 is Dictionary and int((cur0 as Dictionary).get("day", 0)) == int(sim0.day):
				_briefing_seen_day = int(sim0.day)
		var shown_base := is_open() and _page == "base"
		var base_bang := not shown_base and _base_bang()
		var base_dot := not shown_base and _briefing_waits()
		var bmarks: Control = _marks["base"]
		if bool(bmarks.get_meta("dot")) != base_dot or bool(bmarks.get_meta("bang")) != base_bang:
			bmarks.set_meta("dot", base_dot)
			bmarks.set_meta("bang", base_bang)
			bmarks.queue_redraw()
		var base_tip := _tab_tip("base", base_bang)
		if tabs["base"].tooltip_text != base_tip:
			tabs["base"].tooltip_text = base_tip
	var lit := _page if is_open() else ""
	if lit != _lit:
		for page in PAGES:
			_style_tab(String(page), String(page) == lit)
		_lit = lit
	var news_tip := _tab_tip("news", bang)
	if tabs["news"].tooltip_text != news_tip:
		tabs["news"].tooltip_text = news_tip
	# (One House: the Build and Map tabs say what the town's pages are; the tabs are made before the sim is known)
	for town_page in TOWN_PAGE_TIPS:
		if tabs.has(town_page):
			var town_tip := _tab_tip(String(town_page), false)
			if tabs[town_page].tooltip_text != town_tip:
				tabs[town_page].tooltip_text = town_tip


func _radio():
	var s = _sim()
	return s.get("radio") if s != null else null


## Round 25: something at the base that waits for the player, whichever page is up: a problem at its second stage (half its time gone: the call is
## raised) or a dilemma (a call of the kind "dilemma" that is open). False in a game without the modules.
func _base_bang() -> bool:
	var sim = _sim()
	if sim == null:
		return false
	var problems = sim.get("problems")
	if problems != null and problems.has_method("open"):
		var open = problems.open()
		if open is Array:
			for r in open:
				if r is Dictionary and int(r.get("stage", 0)) >= 2:
					return true
	var radio = _radio()
	if radio != null and radio.has_method("open_calls"):
		for e in radio.open_calls():
			if String(e.get("kind", "")) == "dilemma":
				return true
	return false


## A briefing that was composed today and has not been looked at: the card was never shown (it waits for the dawn card, a tutorial step, a modal) or
## it went by while the player was elsewhere, and the Base page has not been opened.
func _briefing_waits() -> bool:
	var sim = _sim()
	if sim == null or not page_available("base"):
		return false
	var b = sim.get("briefing")
	var cur = b.get("current") if b != null else null
	return cur is Dictionary and int((cur as Dictionary).get("day", 0)) == int(sim.day) and _briefing_seen_day != int(sim.day)


## The morning's briefing has been looked at (the HUD shows the card, or the Base page is opened): its dot on the tab goes.
func note_briefing_seen() -> void:
	var sim = _sim()
	if sim != null:
		_briefing_seen_day = int(sim.day)
		_sync_tabs()


# ------------------------------------------------------------------------ the pages --

## Whether this is a One House run (the town's pages and words), false in the school and when the sim has no such hook.
func _is_town() -> bool:
	var s = _sim()
	return s != null and s.has_method("is_one_house") and s.is_one_house()


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
		var path := String(TOWN_PAGE_PATHS[page]) if TOWN_PAGE_PATHS.has(page) and _is_town() else String(PAGE_PATHS[page])
		var script = load(path)
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
	if want == "base":
		note_briefing_seen()
	_sync_tabs()
	_sync_foot()
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
	_sync_foot()
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
	if visible and (_page == "map" or _page == "base") and not page_available(_page):
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
	for page in tabs:
		tabs[page].custom_minimum_size.x = _tab_width(String(page))
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
