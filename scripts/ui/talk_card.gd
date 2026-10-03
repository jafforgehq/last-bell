## The talk card (round 18, slice 2, V2.5): what E at a person opens. A small board beside them, over the yard and never a
## modal: their portrait, name and role, what they say of themselves (the rules' own line: `interact.talk_to`), what they need
## (`interact.needs_of`: a need that a page of the radio panel can deal with has a button for it), how far they trust you (the
## person panel's bar and word), the word they had with you (trust +1, the day's first), and the radio's verbs for them (Come
## with me, Hold here...: the round 17 `RadioVerbs`, 3 to a row, with the answer, the refusal in amber and Insist). It asks, it never
## commands: every refusal is the radio's own.
##
## The card follows the person on the screen (it keeps beside them, off the avatar, the boards of the HUD and the window's edge: see
## `place`) and closes when it should: Esc and E (main.gd and the HUD), the avatar going farther than TALK_LEAVE, the person
## going away, falling, dying, a modal page opening, the avatar being down or lost.
##
## The HUD builds it and owns it (hud.gd, the last section: `show_talk(p, result)`, `hide_talk()`, `talk_open()`, anchor `talk`). It
## borrows the HUD's looks as the other radio views do (`host.PANEL`, `host._label()`...); nothing here changes the rules but
## through the radio. It asks the HUD for the sim (`host.sim_ref`) and for the screen place of a tile (`host.talk_anchor`, a
## Callable(tile) -> pixels that main.gd sets; the canvas transform when there is none).
extends PanelContainer

const Fonts := preload("res://scripts/ui/fonts.gd")
const RadioVerbs := preload("res://scripts/ui/radio_verbs.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")

## The card is closing: the HUD hides it. (The reason is for the tests: "esc", "e", "far", "away", "down", "gone", "modal", "lost".)
signal closed(why: String)

const CARD_W := 330.0
## How far from the person's feet (tiles) the avatar may go before the talk is over: the rules' `TALK_LEAVE` when the interact module
## has one, else this.
const TALK_LEAVE := 3.5
## The gap to the person and to the window's edge, in pixels.
const GAP := 12.0
const MARGIN := 8.0
## How much better (square pixels of overlap) another side has to be before the card moves to it: it does not flicker between two.
const STAY_BONUS := 500.0
## What the card above or below the people costs more than beside them (the same square pixels of overlap).
const VERTICAL_COST := 600.0
const PAGE_BUTTON := {"jobs": "Open Jobs", "build": "Open Build", "map": "Open Map", "news": "Open News"}
const NEED_NONE := "Nothing: they are fine"

var host
var person = null
## What `interact.talk_to` said when the card was opened ({} when it was opened without), and the trust it earned.
var result := {}
var gain := 0.0
var verbs
var shown_side := ""
## What the last press of a need's button asked of the radio panel: {"page", "focus"} ({} before any), for the tests.
var last_page_request := {}
## The needs the card shows now (as `needs_of` gave them), by their button: {"id": the need's id, "button": Button}.
var need_rows: Array = []
## The column the card is made of, and whether it is in its close form (a small window: the heading and some of the room are given up).
var stack: VBoxContainer
var compact := false
var name_label: Label
var role_label: Label
var status_label: Label
var needs_head: Label
var needs_box: VBoxContainer
var trust_head: Label
var trust_bar
var trust_word: Label
var gain_label: Label
var close_button: Button
var portrait: TextureRect
## A window under this wide or this tall has the card in its close form.
const COMPACT_W := 980.0
const COMPACT_H := 700.0
## What the needs were (as a text) when the card was last filled and when it was opened; NONE_YET before either (an empty list of needs
## has the signature "" too, so it must not look like "not filled").
const NONE_YET := "?"
var _needs_sig := NONE_YET
var _opening_sig := NONE_YET
var _opening_activity := ""
var _built := false


# ------------------------------------------------------------------ helpers --

## The interact module of a game: the sim's own, or (in a test, before the real module is there or to make one say something
## particular) the stand-in the test left in the sim's meta "interact_stub". Null when there is none.
static func interact_of(sim):
	if sim == null:
		return null
	if sim.has_meta("interact_stub"):
		return sim.get_meta("interact_stub")
	return sim.get("interact")


## A constant of the interact module's script (the rules' numbers), or `fallback` when it has none (a stand-in).
static func rule(it, key: String, fallback):
	var s = it.get_script() if it != null else null
	if s != null:
		var table: Dictionary = s.get_script_constant_map()
		if table.has(key):
			return table[key]
	return fallback


## The area (square pixels) two rectangles have in common.
static func overlap(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return maxf(0.0, i.size.x) * maxf(0.0, i.size.y)


## Where a card of `card` pixels goes, beside the person at `person_px` (their feet, in pixels) and the avatar at `you_px`, a tile being
## `tile_px` wide: {"pos" (its top-left), "side" ("right", "left", "below" or "above"), "score" (the overlap it leaves, less is better)}.
## It keeps off the person and the avatar (heavily), the rectangles of `avoid` (the HUD's boards) and the edge of `view`; `last_side` is
## the side it was on, which wins unless another is clearly better.
static func place(card: Vector2, person_px: Vector2, you_px: Vector2, tile_px: float, view: Rect2, avoid: Array, last_side: String = "") -> Dictionary:
	var u := maxf(tile_px, 8.0)
	var body := func(at: Vector2) -> Rect2: return Rect2(at.x - 0.5 * u, at.y - 1.15 * u, u, 1.75 * u)
	var person_box: Rect2 = body.call(person_px)
	var you_box: Rect2 = body.call(you_px)
	# (beside the two of them together: the avatar stands within a couple of tiles of the person, and the card is not to cover either)
	var both := person_box.merge(you_box)
	var lift := person_px.y - card.y * 0.4
	var wants := {
		"right": Vector2(both.end.x + GAP, lift),
		"left": Vector2(both.position.x - GAP - card.x, lift),
		"below": Vector2(person_px.x - card.x * 0.5, both.end.y + GAP),
		"above": Vector2(person_px.x - card.x * 0.5, both.position.y - GAP - card.y),
	}
	var lo := view.position + Vector2(MARGIN, MARGIN)
	var hi := view.end - Vector2(MARGIN, MARGIN) - card
	var best := {}
	for side in ["right", "left", "below", "above"]:
		var want: Vector2 = wants[side]
		var at := Vector2(clampf(want.x, lo.x, maxf(lo.x, hi.x)), clampf(want.y, lo.y, maxf(lo.y, hi.y)))
		var rect := Rect2(at, card)
		var score := 4.0 * overlap(rect, person_box) + 4.0 * overlap(rect, you_box) + at.distance_to(want) * 60.0 + rect.get_center().distance_to(person_px) * 2.0
		for r in avoid:
			score += 3.0 * overlap(rect, r)
		# (a card is taller than it is wide to the eye of a yard: beside the people is where it belongs, above and below are for when it must)
		if side == "below" or side == "above":
			score += VERTICAL_COST
		if side == last_side:
			score -= STAY_BONUS
		if best.is_empty() or score < float(best.score):
			best = {"pos": at, "side": side, "score": score}
	return best


# -------------------------------------------------------------------- build --

func setup(host_hud) -> void:
	host = host_hud
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", host._style(host.PANEL, 6, host.LINE, true, "panel_slim"))
	custom_minimum_size.x = CARD_W
	visible = false
	var v: VBoxContainer = host._vbox(7)
	stack = v
	add_child(v)
	# the head: portrait, name and role, and the way out
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
	close_button = RadioKit.small_button(host, "x", 26.0, 14)
	close_button.custom_minimum_size.x = 28.0
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.tooltip_text = "Close (E or Esc)"
	close_button.pressed.connect(close.bind("button"))
	head.add_child(close_button)
	v.add_child(head)
	# what they say of themselves
	status_label = host._label("", Fonts.sans(600), 14, host.INK)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = CARD_W - 28.0
	v.add_child(status_label)
	# what they need
	needs_head = host._caps("They need")
	v.add_child(needs_head)
	needs_box = host._vbox(4)
	v.add_child(needs_box)
	# how far they trust you
	var trust: Array = host._trust_row()
	var trust_row: HBoxContainer = host._hbox(8)
	trust_head = host._caps("Trust")
	trust_head.custom_minimum_size.x = 46
	trust_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trust_head.mouse_filter = Control.MOUSE_FILTER_PASS
	trust_row.add_child(trust_head)
	trust[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trust_row.add_child(trust[0])
	trust_bar = trust[1]
	trust_word = trust[2]
	v.add_child(trust_row)
	gain_label = host._label("", Fonts.sans(600), 13, host.OK)
	gain_label.visible = false
	v.add_child(gain_label)
	# the verbs (a column of them: three to a row)
	verbs = RadioVerbs.new()
	v.add_child(verbs)
	verbs.setup(host, func(): return _radio(), {"place": false})
	verbs.requested.connect(_on_requested)
	set_process(false)


func _sim():
	return null if host == null else host.get("sim_ref")


func _radio():
	var s = _sim()
	return null if s == null else s.get("radio")


func _interact():
	return interact_of(_sim())


# --------------------------------------------------------------- open, close --

## Shows the card for `p`. `res` is what `interact.talk_to(p)` just said ({"line", "needs", "trust", "tone", "gain"}); without it the card
## says what it can of its own (no word of the day).
func open(p, res: Dictionary = {}) -> void:
	if p == null or host == null:
		return
	var same: bool = p == person
	person = p
	result = res
	gain = float(res.get("gain", 0.0))
	shown_side = "" if not same else shown_side
	verbs.set_contact(p)
	visible = true
	set_process(true)
	_needs_sig = NONE_YET
	_opening_sig = NONE_YET
	_opening_activity = String(p.activity)
	refresh()
	_place()


## Puts the card away (and tells the HUD, which says why to whoever asks).
func close(why: String = "") -> void:
	if not visible and person == null:
		return
	visible = false
	set_process(false)
	person = null
	result = {}
	gain = 0.0
	need_rows = []
	verbs.set_contact(null)
	closed.emit(why)


func is_open() -> bool:
	return visible and person != null


## Why the talk is over now (a reason for `close`), or "" while it goes on.
func ending() -> String:
	var p = person
	if p == null:
		return "gone"
	if p.dead or p.turned:
		return "gone"
	if p.away != null:
		return "away"
	if p.downed:
		return "down"
	var s = _sim()
	if s == null or not bool(host.get("avatar_ui")):
		return "lost"
	if host.has_method("modal_open") and host.modal_open():
		return "modal"
	var me = s.avatar.player() if s.get("avatar") != null else null
	if me == null or me.dead or me.turned or me.away != null or me.downed:
		return "lost"
	var it = _interact()
	var leave := float(rule(it, "TALK_LEAVE", TALK_LEAVE))
	if Vector2(p.x, p.y).distance_to(Vector2(me.x, me.y)) > leave:
		return "far"
	return ""


# ------------------------------------------------------------------ refresh --

## Brings the card in line with the game (the HUD does it with every update): closes it when the talk is over, else the words, the needs,
## the trust and the verbs.
func refresh() -> void:
	if person == null:
		return
	var why := ending()
	if why != "":
		close(why)
		return
	var p = person
	var radio = _radio()
	var it = _interact()
	var needs: Array = it.needs_of(p) if it != null and it.has_method("needs_of") else []
	_apply_form()
	# the head
	if portrait.texture == null or portrait.get_meta("who", "") != p.id:
		portrait.texture = host.portrait_of(p)
		portrait.set_meta("who", String(p.id))
	if name_label.text != String(p.name):
		name_label.text = String(p.name)
	var role := "%s · %d" % [String(p.def.get("role", "")), int(p.def.get("age", 0))]
	if role_label.text != role:
		role_label.text = role
	# what they say
	var sig := _signature(needs)
	if _opening_sig == NONE_YET:
		_opening_sig = sig
	var line := _status_line(p, needs, sig == _opening_sig and String(p.activity) == _opening_activity)
	if status_label.text != line:
		status_label.text = line
	# what they need
	if sig != _needs_sig:
		_needs_sig = sig
		_fill_needs(needs)
	# how far they trust you
	_refresh_trust(p, radio)
	# the word they had with you
	var word := _gain_text(gain)
	gain_label.visible = word != ""
	if gain_label.text != word:
		gain_label.text = word
	verbs.refresh()


## The close form in a small window (under COMPACT_W wide or COMPACT_H tall): the room between the lines is tighter, the portrait smaller and
## the heading over the needs is left out (each need says what it is).
func _apply_form() -> void:
	var want: bool = host.size.x < COMPACT_W or host.size.y < COMPACT_H
	if want == compact and stack.get_theme_constant("separation") == (4 if compact else 7):
		return
	compact = want
	stack.add_theme_constant_override("separation", 4 if compact else 7)
	portrait.custom_minimum_size = Vector2(36, 36) if compact else Vector2(46, 46)
	needs_head.visible = not compact


func _signature(needs: Array) -> String:
	var parts: Array = []
	for n in needs:
		parts.append("%s|%s|%s" % [String(n.get("id", "")), String(n.get("text", "")), String(n.get("page", ""))])
	return ";".join(parts)


## What they say: the rules' own line while nothing has changed since they said it (their needs, what they are doing), else the first
## need's, else what they are doing now.
func _status_line(p, needs: Array, unchanged: bool) -> String:
	var said := String(result.get("line", ""))
	if said != "" and unchanged:
		return said
	if not needs.is_empty():
		var n: Dictionary = needs[0]
		return String(n.get("line", n.get("text", "")))
	var act := String(p.activity).strip_edges()
	return "%s." % act if act != "" else "Nothing much."


func _gain_text(g: float) -> String:
	if g <= 0.0:
		return ""
	var n := "%d" % roundi(g) if is_equal_approx(g, roundf(g)) else "%.1f" % g
	return "Had a word with you: trust +%s" % n


func _fill_needs(needs: Array) -> void:
	for c in needs_box.get_children():
		needs_box.remove_child(c)
		c.queue_free()
	need_rows = []
	if needs.is_empty():
		var none: Label = host._label(NEED_NONE, Fonts.sans(400), 13, host.INK2)
		needs_box.add_child(none)
		return
	for n in needs:
		var row: HBoxContainer = host._hbox(8)
		var text: Label = host._label(String(n.get("text", "")), Fonts.sans(400), 13, host.WARN)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size.x = 100
		text.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(text)
		var page := String(n.get("page", ""))
		var entry := {"id": String(n.get("id", "")), "page": page, "label": text, "button": null}
		if page != "":
			var b: Button = RadioKit.small_button(host, String(PAGE_BUTTON.get(page, "Open %s" % page.capitalize())), 26.0, 13)
			b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			b.tooltip_text = "Open the %s page of the radio, on %s" % [page.capitalize(), String(person.first)]
			b.pressed.connect(open_page.bind(page))
			row.add_child(b)
			entry["button"] = b
		needs_box.add_child(row)
		need_rows.append(entry)


## The trust bar and its word, as the person panel has them (the same colours, the same tooltip).
func _refresh_trust(p, radio) -> void:
	var showing: bool = radio != null and not p.player
	trust_head.visible = showing
	trust_bar.get_parent().visible = showing
	if not showing:
		return
	var trust := float(radio.trust_of(p))
	var tone := String(radio.tone_of(p))
	var value := clampf(trust / 100.0, 0.0, 1.0)
	var col: Color = host.TRUST_BAR.get(tone, host.OK)
	if not is_equal_approx(trust_bar.value, value) or trust_bar.color != col:
		trust_bar.value = value
		trust_bar.color = col
		trust_bar.queue_redraw()
	var tcol: Color = host.TRUST_WORD.get(tone, host.INK)
	if trust_word.text != tone:
		trust_word.text = tone
	trust_word.add_theme_color_override("font_color", tcol)
	var tip: String = host._trust_tip(p, radio, trust, tone) if host.has_method("_trust_tip") else ""
	for c in [trust_head, trust_bar, trust_word]:
		if c.tooltip_text != tip:
			c.tooltip_text = tip


## A need's button: the page of the radio panel that deals with it, on this person (the panel's own `open_radio`; a HUD with no panel
## opens the full page that the old game has).
func open_page(page: String) -> void:
	if person == null:
		return
	last_page_request = {"page": page, "focus": String(person.id)}
	if host.has_method("open_radio"):
		host.open_radio(page, {"focus": String(person.id)})
	elif page == "jobs" and host.has_method("open_jobs"):
		host.open_jobs()
	elif page == "build" and host.has_method("open_build"):
		host.open_build()


## A verb was asked of them: the card has the answer in its own line; the hint of the first screen has done its work.
func _on_requested(_contact, _verb: String, _answer: Dictionary) -> void:
	if host.get("hint_spent") != null:
		host.hint_spent = true
		if host.has_method("_refresh_hint"):
			host._refresh_hint()


# ------------------------------------------------------------------- placing --

func _process(_dt: float) -> void:
	if visible and person != null:
		_place()


## Beside the person on the screen (see `place`).
func _place() -> void:
	if person == null or host == null:
		return
	var p = person
	var s = _sim()
	var me = s.avatar.player() if s != null and s.get("avatar") != null else null
	var feet := Vector2(p.x, p.y)
	var you := Vector2(me.x, me.y) if me != null else feet
	var here := _px(feet)
	var tile_px := absf(_px(feet + Vector2(1.0, 0.0)).x - here.x)
	var view := _free_view()
	# (the boards of the HUD it keeps off; it is not one of them, so it is hidden while they are asked)
	var was := visible
	visible = false
	var avoid: Array = host.covered_rects().duplicate() if host.has_method("covered_rects") else []
	visible = was
	# (the line of tips at the foot of the window is not a board that covers the world, but the card keeps off it too)
	var tips = host.get("hint")
	if tips is Control and is_instance_valid(tips) and tips.is_visible_in_tree():
		avoid.append(tips.get_global_rect())
	var card := get_combined_minimum_size()
	var at: Dictionary = place(card, here, _px(you), tile_px if tile_px > 1.0 else 48.0, view, avoid, shown_side)
	shown_side = String(at.side)
	size = card
	position = at.pos


## Where a tile of the world is on the HUD (pixels).
func _px(tile: Vector2) -> Vector2:
	var f = host.get("talk_anchor")
	if f is Callable and f.is_valid():
		return f.call(tile)
	return get_viewport().get_canvas_transform() * (tile * 64.0)


## The part of the window the card may be in: what the radio panel leaves free (when there is a panel), else the whole window.
func _free_view() -> Rect2:
	var whole := Rect2(Vector2.ZERO, host.size)
	if host.has_method("free_view"):
		var fv = host.free_view()
		if fv is Rect2 and (fv as Rect2).size.x > 50.0 and (fv as Rect2).size.y > 50.0:
			return fv
	return whole
