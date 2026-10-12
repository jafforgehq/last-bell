## RUTH AND HER KIT (INV2): the right-hand side of the backpack window, laid out like Tarkov's: Ruth's outline from the front (a picture of the atlas, 112 x 168 points), the pump shotgun in a slot
## at her hand (the rounds in the magazine over a Reload strip: a click on it is the R key), the swing in the slot at the other side (no item), and a row of FOUR QUICK SLOTS on her belt: each
## names a kind of item from the pack (a bandage, a meal, a drink) and the keys 1 to 4 (or a click) use it. A slot is lit when its item is in the pack and dim when it is not. PH10: a meal or a
## drink works (it is eaten when she is hungry enough: scripts/town/inv.gd `use_item`) and is MARKED while she needs it: an amber rim and a small triangle on its corner, so that the key to press
## is the one that shows. Items are put on a slot by dragging them from the pack (`inv_ui.gd` does the drop: `quick_at`) or by the item's menu.
## There are no empty slots for a head or a body: there is nothing to put there in this version, so the outline alone carries the look, with a soft glow where the weapon and the belt are.
## Drawn, not laid out, and drawn again only when something changed (`refresh`), the pointer moved onto another slot, or a drag is over a slot. It never takes a key.
extends Control

const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvIcons := preload("res://scripts/ui/inv_icons.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Access := preload("res://scripts/access.gd")
const CbShapes := preload("res://scripts/ui/cb_shapes.gd")

## The size of the doll, in interface points.
const W := 150.0
const H := 168.0
const FIGURE := Rect2(19.0, 0.0, 112.0, 168.0)
## The slot of the weapon (bottom left, at her hand) and of the swing (bottom right).
const WEAPON := Rect2(0.0, 118.0, 50.0, 50.0)
const MELEE := Rect2(100.0, 118.0, 50.0, 50.0)
## The quick slots: SLOTS squares of SLOT points a gap apart, on the belt.
const SLOTS := 4
const SLOT := 28.0
const GAP := 2.0
const BELT_Y := 90.0

const INK := Color("#eeeadd")
const INK2 := Color("#c1c5b5")
const INK3 := Color("#a8ae9d")
const ACCENT := Color("#f0c24a")
const WARN := Color("#e8953a")
const DANGER := Color("#f27f72")
const BRASS := Color("#d2a94e")
const SLOT_BG := Color(0.035, 0.07, 0.06, 0.92)

var ctl
var gun_name := "Pump shotgun"
var gun_id := "shotgun"
var mag := 0
var cap := 0
var reserve := 0
var melee_only := false
var can_reload := false
var can_reload_now := false
var reloading := false
## The belt, one entry for each slot: {"id", "count", "state": "empty" | "ready" | "off", "name", "use", "due": she needs it now (hungry for food, thirsty for drink)}.
var quick: Array = []
## What the pointer is over: "" | "weapon" | "melee" | "q0" to "q3".
var hover := ""
var _sig := ""


func setup(controller) -> void:
	ctl = controller
	name = "InvDoll"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(W, H)
	InvIcons.prepare(self)
	for i in SLOTS:
		quick.append({"id": "", "count": 0, "state": "empty", "name": "", "use": "none", "due": false})


# --------------------------------------------------------------------------------- geometry --

## The rectangle of quick slot `i` in this control's own points.
static func slot_rect(i: int) -> Rect2:
	var x0 := (W - (float(SLOTS) * SLOT + float(SLOTS - 1) * GAP)) * 0.5
	return Rect2(Vector2(x0 + float(i) * (SLOT + GAP), BELT_Y), Vector2(SLOT, SLOT))


## The quick slot under a point of this control (-1 for none).
func quick_at(local: Vector2) -> int:
	for i in SLOTS:
		if slot_rect(i).grow(1.0).has_point(local):
			return i
	return -1


func quick_at_global(p: Vector2) -> int:
	return quick_at(p - get_global_rect().position)


func slot_global_rect(i: int) -> Rect2:
	var r := slot_rect(i)
	return Rect2(get_global_rect().position + r.position, r.size)


func belt_rect() -> Rect2:
	var a := slot_rect(0)
	var b := slot_rect(SLOTS - 1)
	return Rect2(a.position, b.end - a.position)


func _key_at(local: Vector2) -> String:
	var q := quick_at(local)
	if q >= 0:
		return "q%d" % q
	if WEAPON.has_point(local):
		return "weapon"
	if MELEE.has_point(local):
		return "melee"
	return ""


# ------------------------------------------------------------------------------------ state --

## Each time the sim's pack, her gun or the belt changed: reads them and draws again when they differ from what is shown.
func refresh(sim, pack: Dictionary) -> void:
	var w: Dictionary = InvApi.equipment(sim).get("weapon", {})
	var n := int(w.get("reserve", InvApi.units(pack, "ammo") if not pack.is_empty() else 0))
	var gm := int(w.get("mag", 0))
	var gc := int(w.get("cap", 0))
	var nm := String(w.get("name", "Pump shotgun"))
	var gid := String(w.get("id", "shotgun"))
	var rl: bool = float(w.get("reloading", 0.0)) > 0.0
	var belt: Array = InvApi.quick(sim)
	var entries: Array = []
	var needs: Dictionary = InvApi.needs(sim)
	var sig := "%s|%s|%d|%d|%d|%s|%s|%s" % [nm, gid, gm, gc, n, str(rl), str(Access.markers()), str(Access.text_k())]
	for i in SLOTS:
		var id := String(belt[i])
		var count := InvApi.count_of(pack, id) if id != "" else 0
		var d: Dictionary = InvApi.item(id) if id != "" else {}
		var use := String(d.get("use", "none"))
		var state := "empty"
		if id != "":
			state = "off" if count <= 0 else "ready"
		var due: bool = state == "ready" and ((use == "eat" and String(needs.get("hunger", {}).get("state", "fed")) != "fed") or (use == "drink" and String(needs.get("thirst", {}).get("state", "fed")) != "fed"))
		entries.append({"id": id, "count": count, "state": state, "name": String(d.get("name", "")), "use": use, "due": due})
		sig += "|%s:%d:%s:%s" % [id, count, state, str(due)]
	if sig == _sig:
		return
	_sig = sig
	gun_name = nm
	gun_id = gid
	mag = gm
	cap = gc
	reserve = n
	melee_only = w.is_empty() or gc <= 0
	reloading = rl
	can_reload = not melee_only and cap > 0
	can_reload_now = can_reload and mag < cap and reserve > 0 and not rl
	quick = entries
	queue_redraw()


func _set_hover(key: String) -> void:
	if key != hover:
		hover = key
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if key != "" else Control.CURSOR_ARROW
		queue_redraw()


# ------------------------------------------------------------------------------------- input --

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_set_hover(_key_at((ev as InputEventMouseMotion).position))
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and ctl != null:
		var mb := ev as InputEventMouseButton
		var key := _key_at(mb.position)
		if key.begins_with("q"):
			var i := int(key.substr(1))
			if mb.button_index == MOUSE_BUTTON_LEFT:
				ctl.quick_pressed(i)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				ctl.quick_menu(i, get_global_rect().position + mb.position)
		elif key == "weapon" and mb.button_index == MOUSE_BUTTON_LEFT:
			ctl.reload_pressed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hover("")


func _get_tooltip(at_position: Vector2) -> String:
	var key := _key_at(at_position)
	if key.begins_with("q"):
		return quick_tip(int(key.substr(1)))
	if key == "weapon":
		if melee_only:
			return "No gun in hand: only the swing"
		return "%s: %d in the magazine of %d, %d shells in the pack.\nClick the strip, or press R, to reload from the shells in the pack." % [gun_name, mag, cap, reserve]
	if key == "melee":
		return "The swing: no item, no ammunition. A blow is quiet.\nKey: F"
	return "Ruth. The pump shotgun is in her hand; four quick slots hang on her belt.\nDrag a bandage, a meal or a drink onto a slot, then press its number."


## What a quick slot's tooltip says (the tests read it).
func quick_tip(i: int) -> String:
	var e: Dictionary = quick[i]
	var key := "Key: %d" % (i + 1)
	match String(e.state):
		"empty":
			return "Quick slot %d: empty\nDrag a bandage, a meal or a drink from the pack onto it.\n%s" % [i + 1, key]
		"off":
			return "Quick slot %d: %s\nNone in the pack.\nRight-click: clear the slot. %s" % [i + 1, e.name, key]
	var verb: String = {"eat": "eat", "drink": "drink"}.get(String(e.use), "use")
	var note := ""
	if String(e.use) == "eat" or String(e.use) == "drink":
		note = ("\nYou need it now." if bool(e.due) else "\nNot needed yet: it is kept until you are %s." % ("hungry" if String(e.use) == "eat" else "thirsty"))
	return "Quick slot %d: %s x %d\nClick, or press %d, to %s one.%s\nRight-click: clear the slot." % [i + 1, e.name, int(e.count), i + 1, verb, note]


# ------------------------------------------------------------------------------------ drawing --

func _draw() -> void:
	var font := Fonts.cond(700, 0)
	var small := Fonts.sans(600, 0)
	# Ruth, with a soft light where the weapon and the belt are
	InvIcons.draw_region(self, "ruth", FIGURE)
	InvIcons.draw_region(self, "glow", Rect2(belt_rect()).grow_individual(26.0, 14.0, 26.0, 14.0), Color(BRASS, 0.20))
	InvIcons.draw_region(self, "glow", WEAPON.grow(14.0), Color(ACCENT, 0.16))
	_draw_weapon(font, small)
	_draw_melee(font)
	for i in SLOTS:
		_draw_quick(i, font)


## The size at which `text` fits `max_w` points, from `fs` down to 9 (Large and Larger text make the words wider than a slot).
static func _fit(font: Font, text: String, max_w: float, fs: int) -> int:
	var s := fs
	while s > 9 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > max_w:
		s -= 1
	return s


func _slot_box(r: Rect2, lit: bool) -> void:
	draw_rect(r, SLOT_BG)
	draw_rect(r, Color(ACCENT if lit else BRASS, 0.95 if lit else 0.5), false, 1.5 if lit else 1.0)


func _draw_weapon(font: Font, small: Font) -> void:
	var r := WEAPON
	_slot_box(r, hover == "weapon" and can_reload_now)
	if melee_only:
		draw_string(small, r.position + Vector2(5.0, 22.0), "No gun", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8.0, Access.scaled(12), INK3)
		return
	InvIcons.draw_gun(self, Rect2(r.position + Vector2(3.0, 2.0), Vector2(r.size.x - 6.0, 20.0)), Color.WHITE, gun_id)
	var low := mag <= maxi(1, ceili(float(cap) * 0.25))
	var mc: Color = DANGER if mag <= 0 else (WARN if low else INK)
	var mt := "%d / %d" % [mag, cap]
	if Access.markers() and low:
		mt = ("!! " if mag <= 0 else "! ") + mt    # (Colour-blind markers: the amber and the red of the rounds are marks too, as on the gun's readout)
	var fs := _fit(font, mt, r.size.x - 4.0, Access.scaled(14))
	var tw := font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, r.position + Vector2((r.size.x - tw) * 0.5, 34.5), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, mc)
	var strip := Rect2(r.position + Vector2(3.0, 37.0), Vector2(r.size.x - 6.0, 12.0))
	var word := "Reload"
	if reloading:
		word = "..."
	elif mag >= cap:
		word = "Full"
	elif reserve <= 0:
		word = "No shells"
	draw_rect(strip, Color(BRASS, 0.42 if can_reload_now else 0.12))
	if can_reload_now:
		draw_rect(strip, Color(BRASS, 0.9), false, 1.0)
	var wfs := _fit(font, word, strip.size.x - 2.0, Access.scaled(12))
	var ww := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, wfs).x
	draw_string(font, strip.position + Vector2((strip.size.x - ww) * 0.5, strip.size.y - 2.0), word, HORIZONTAL_ALIGNMENT_LEFT, strip.size.x, wfs, INK if can_reload_now else INK3)


func _draw_melee(small: Font) -> void:
	var r := MELEE
	_slot_box(r, hover == "melee")
	InvIcons.draw_melee(self, Rect2(r.position + Vector2(8.0, 2.0), Vector2(34.0, 34.0)))
	var word := "F  Swing"
	var wfs := _fit(small, word, r.size.x - 4.0, Access.scaled(12))
	var ww := small.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, wfs).x
	draw_string(small, r.position + Vector2((r.size.x - ww) * 0.5, 47.0), word, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 4.0, wfs, INK2)


func _draw_quick(i: int, font: Font) -> void:
	var r := slot_rect(i)
	var e: Dictionary = quick[i]
	var state := String(e.state)
	InvIcons.draw_region(self, {"empty": "slot", "ready": "slot_on", "off": "slot_off"}[state], r)
	if state != "empty":
		var dim := state == "off"
		InvIcons.draw_fit(self, InvIcons.picture_of(String(e.id), int(e.count)), r.grow(-4.0), Color(0.62, 0.64, 0.62, 0.6) if dim else Color.WHITE)
		if dim and Access.markers():
			draw_line(r.position + Vector2(5.0, 5.0), r.end - Vector2(5.0, 5.0), Color(INK3, 0.9), 1.5)    # (a grey is not told by its grey alone)
	var kfs := Access.scaled(11)
	var key := str(i + 1)
	draw_string_outline(font, r.position + Vector2(3.5, 10.5), key, HORIZONTAL_ALIGNMENT_LEFT, -1, kfs, 4, Color(0, 0, 0, 0.85))
	draw_string(font, r.position + Vector2(3.5, 10.5), key, HORIZONTAL_ALIGNMENT_LEFT, -1, kfs, ACCENT if state == "ready" else INK3)
	if state != "empty" and int(e.count) > 1:
		var cs := str(int(e.count))
		var cfs := Access.scaled(12)
		var cw := font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var at := r.end - Vector2(cw + 2.5, 3.0)
		draw_string_outline(font, at, cs, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, 4, Color(0, 0, 0, 0.9))
		draw_string(font, at, cs, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, INK)
	if bool(e.due):
		# (she needs it now: an amber rim and a triangle, so that the mark is a shape as well as a colour)
		draw_rect(r, Color(WARN, 0.95), false, 1.5)
		CbShapes.mark(self, "triangle", r.position + Vector2(r.size.x - 6.5, 6.5), 4.0, WARN)
	if hover == "q%d" % i:
		draw_rect(r, Color(ACCENT, 0.95), false, 1.5)
