## The town's slim stores (HUDA, the "clutter" pass): the panel at the top left of the One House's HUD, made light.
##
## The school's panel is a column of five rows (an icon, a name, a number, and under food and water the days left): 110 px of heavy frame at a corner of the
## window for a solo survivor who has four things that matter. The town's is ONE ROW of icon and number pairs in a thin frame:
##   - at the start ammo, food, water and medicine (scrap, and the fuel the town never shows, come the first time the player holds more scrap than the run
##     began with, or opens the Build page: a store that does not matter yet is not there to be read)
##   - the days left under food and water only when there are fewer than `DAYS_SHOWN_BELOW`, or while the mouse is on the panel
##   - every number stays reachable: the tooltip of a pair says its name, the number and, for food and water, the days
## It reuses the HUD's own labels (`res_values`, `res_days`: the HUD keeps writing the numbers and the colours, the coach keeps finding them) by moving them
## into a strip; the school's grid stays where it was, hidden. `lean()` (a window of 1080p or more) tightens the padding and thins the frames of the panels.
## A view only.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const OneHouse := preload("res://scripts/town/one_house.gd")
const InvTotals := preload("res://scripts/ui/inv_totals.gd")

const DAYS_SHOWN_BELOW := 5.0
## The stores that are always there; the others (scrap) are shown when they matter.
const ALWAYS := ["ammo", "food", "water", "meds"]
const NAMES := {"ammo": "Ammo", "scrap": "Scrap", "food": "Food", "water": "Water", "meds": "Medicine"}
## A window this wide (in the HUD's own points: 1080p and 1440p both lay it out in 1600) wears the lighter weight.
const LEAN_MIN_W := 1500.0

var hud
var strip: HBoxContainer
var pairs := {}
## The stores revealed so far (a reveal is for good).
var revealed := {}
var hovered := false
var _tips := {}
var _lean := false
var _start_scrap := -1


func _init(hud_node) -> void:
	hud = hud_node
	_build()
	on_resized()


func _build() -> void:
	var grid: GridContainer = hud.res_grid
	var kids := grid.get_children()
	strip = HBoxContainer.new()
	strip.add_theme_constant_override("separation", 12)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in hud.STORES.size():
		var kind := String(hud.STORES[i][0])
		# the grid's three cells of a store: the icon, the name (left in the grid, hidden), the number (with the days under it, for food and water)
		var icon_cell: Control = kids[3 * i]
		var value_cell: Control = kids[3 * i + 2]
		grid.remove_child(icon_cell)
		grid.remove_child(value_cell)
		var v: Label = hud.res_values[kind]
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.custom_minimum_size.x = 0
		var d = hud.res_days.get(kind)
		if d != null:
			d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			d.visible = false
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 4)
		pair.mouse_filter = Control.MOUSE_FILTER_PASS    # (the tooltip)
		pair.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		pair.add_child(icon_cell)
		pair.add_child(value_cell)
		strip.add_child(pair)
		pairs[kind] = pair
		pair.visible = ALWAYS.has(kind)
	grid.visible = false
	hud.res_panel.add_child(strip)
	hud.res_panel.mouse_filter = Control.MOUSE_FILTER_PASS


## The window's size changed (and once when made): the panels' weight.
func on_resized() -> void:
	var lean := lean_now()
	_lean = lean
	hud.res_panel.add_theme_stylebox_override("panel", panel_style(hud, true))
	if hud.ammo_panel != null:
		hud.ammo_panel.add_theme_stylebox_override("panel", panel_style(hud, false))
	strip.add_theme_constant_override("separation", 10 if lean else 12)


func lean_now() -> bool:
	return hud.size.x >= LEAN_MIN_W


## The thin board the town's small panels wear: the slim frame (the plain one is the school's), its padding tighter in a big window.
static func panel_style(hud_node, strip_panel: bool) -> StyleBox:
	var lean: bool = hud_node.size.x >= LEAN_MIN_W
	var st: StyleBox = hud_node._style(hud_node.PANEL, 6, hud_node.LINE2, true, "panel_slim")
	st.content_margin_left = 8.0 if lean else 10.0
	st.content_margin_right = 8.0 if lean else 10.0
	st.content_margin_top = 4.0 if lean else 5.0
	st.content_margin_bottom = 5.0 if lean else 6.0
	if not strip_panel:
		st.content_margin_left += 2.0
		st.content_margin_right += 2.0
		st.content_margin_top += 1.0
	return st


## Every HUD update (ten a second), after the HUD has written the numbers.
func update(sim) -> void:
	_reveal(sim)
	var c = hud.get_viewport().gui_get_hovered_control() if hud.is_inside_tree() else null
	hovered = c != null and (c == hud.res_panel or hud.res_panel.is_ancestor_of(c))
	for kind in pairs:
		var on: bool = ALWAYS.has(kind) or revealed.has(kind)
		var pair: Control = pairs[kind]
		if pair.visible != on:
			pair.visible = on
		var days := -1.0
		if hud.res_days.has(kind) and sim.supplies != null:
			days = float(sim.supplies.days_left(kind))
			var d: Label = hud.res_days[kind]
			var show_days := hovered or days < DAYS_SHOWN_BELOW
			if d.visible != show_days:
				d.visible = show_days
		var tip := tip_of(kind, roundi(float(sim.stock[kind])), days)
		if String(_tips.get(kind, "")) != tip:
			_tips[kind] = tip
			pair.tooltip_text = tip
	InvTotals.apply(hud, sim)    # (INV-UI: with an inventory the numbers are what she carries before the claim and the stores after it)


## "Food: 12. About 12 days at the crew's use." for the tooltip of a pair.
static func tip_of(kind: String, amount: int, days: float) -> String:
	var tip := "%s: %d" % [String(NAMES.get(kind, kind.capitalize())), amount]
	if days >= 0.0:
		tip += ". " + ("Plenty for weeks at the crew's use" if (not is_finite(days) or days >= 99.0) else ("Less than a day at the crew's use" if days < 1.0 else "About %d days at the crew's use" % int(days)))
	return tip


## Scrap (and any store that is not always there) shows the first time the player holds more than the run began with, or opens the Build page.
func _reveal(sim) -> void:
	if revealed.has("scrap"):
		return
	if _start_scrap < 0:
		var start: Dictionary = OneHouse.data().get("start", {}).get("stock", {})
		_start_scrap = roundi(float(start.get("scrap", 0.0)))    # (read once: the data is two files)
	# (and once the house is claimed: the reveal is not saved, so a run that is loaded after the fence spent the stash would hide it until the Build page was opened again)
	var has_base: bool = sim.scenario != null and sim.scenario.has_method("has_base") and sim.scenario.has_base()
	if roundi(float(sim.stock.get("scrap", 0.0))) > _start_scrap or hud.radio_page() == "build" or has_base:
		revealed["scrap"] = true
