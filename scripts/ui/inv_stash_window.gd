## The stash panel (INV2): E at the base stash opens it (`sim.inv.stash_open`) under or over the backpack. The STORES as a strip of five columns (ammo, food, water, medicine, scrap), each with
## the number the base holds now (read from `sim.inv.store_totals()` ten times a second: it follows the crew's work as it happens) and the buttons that take 1, 5 or all that fits out as items
## into the pack; Deposit all puts everything in the pack that stands for a store into the stores; an item dragged onto this panel is deposited too (`inv_ui.gd` does the drop). Scrap is never
## carried: it has a number and no buttons. The same slim board as the pack, about as wide as it is and a hand high. It never takes a key and never pauses the game.
extends PanelContainer

const InvApi := preload("res://scripts/ui/inv_api.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const InvIcons := preload("res://scripts/ui/inv_icons.gd")

const ROWS := [["ammo", "Ammo", "shells"], ["food", "Food", "cans"], ["water", "Water", "bottles"], ["meds", "Medicine", "bandages"], ["scrap", "Scrap", ""]]
const WITHDRAW := [["1", 1], ["5", 5], ["All", -1]]

var ctl
var hud
var title: Label
var close_button: Button
var deposit_button: Button
## res -> {"count": Label, "buttons": [Button]}
var rows := {}
var totals := {}
## Whether a dragged item is over the panel now (the overlay draws the frame; `inv_ui.gd` sets it).
var drop_hot := false


func setup(controller, hud_node) -> void:
	ctl = controller
	hud = hud_node
	name = "InvStashWindow"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st: StyleBox = hud._style(hud.PANEL, 6, hud.LINE2, true, "panel_slim")
	st.content_margin_left = 8 if st is StyleBoxFlat else 9
	st.content_margin_right = 8 if st is StyleBoxFlat else 9
	st.content_margin_top = 7 if st is StyleBoxFlat else 8
	st.content_margin_bottom = 8 if st is StyleBoxFlat else 10
	add_theme_stylebox_override("panel", st)
	var col: VBoxContainer = hud._vbox(4)
	add_child(col)
	var head: HBoxContainer = hud._hbox(8)
	title = hud._label("STORES AT THE BASE", Fonts.cond(700, 1), 14, hud.ACCENT)
	head.add_child(title)
	head.add_child(hud._spacer())
	deposit_button = RadioKit.small_button(hud, "Deposit all", 22.0, 13)
	deposit_button.tooltip_text = "Put everything in the pack that stands for a store into the stores"
	deposit_button.pressed.connect(func(): ctl.deposit_all_pressed())
	head.add_child(deposit_button)
	close_button = RadioKit.small_button(hud, "×", 22.0, 16)
	close_button.custom_minimum_size = Vector2(24.0, 22.0)
	close_button.tooltip_text = "Close the stash\nKey: Esc"
	close_button.pressed.connect(func(): ctl.close_stash())
	head.add_child(close_button)
	col.add_child(head)
	var strip: HBoxContainer = hud._hbox(4)
	for r in ROWS:
		strip.add_child(_column(String(r[0]), String(r[1]), String(r[2])))
	col.add_child(strip)
	tooltip_text = "Drag an item onto this panel to deposit it"


func _column(res: String, label: String, what: String) -> Control:
	var col: VBoxContainer = hud._vbox(1)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top: HBoxContainer = hud._hbox(4)
	var ic: TextureRect = hud._icon(res, 16, InvIcons.res_color(res))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(ic)
	top.add_child(hud._label(label, Fonts.sans(600, 0), 13, hud.INK2))
	col.add_child(top)
	var count: Label = hud._label("0", Fonts.cond(700, 0), 20, hud.INK)
	col.add_child(count)
	var row: HBoxContainer = hud._hbox(2)
	var buttons: Array = []
	if what != "":
		for w in WITHDRAW:
			var b := RadioKit.small_button(hud, String(w[0]), 22.0, 13)
			for state in ["normal", "hover", "pressed", "disabled"]:
				var sb: StyleBox = b.get_theme_stylebox(state)
				sb.content_margin_left = 3
				sb.content_margin_right = 3
			b.custom_minimum_size.x = 22.0 if String(w[0]) != "All" else 30.0
			var n := int(w[1])
			b.tooltip_text = ("Take %d %s out of the stores into the pack, as %s" % [n, label.to_lower(), what]) if n > 0 else "Take all the %s that fits in the pack, as %s" % [label.to_lower(), what]
			b.pressed.connect(func(): ctl.withdraw_pressed(res, n))
			row.add_child(b)
			buttons.append(b)
	else:
		var note: Label = hud._label("kept here", Fonts.sans(400, 0), 12, hud.INK3)
		note.custom_minimum_size.y = 22.0
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(note)
		col.tooltip_text = "Scrap is never carried: it goes straight into the stores, and the base is built from it"
	col.add_child(row)
	rows[res] = {"count": count, "buttons": buttons}
	return col


## The numbers of the stores now (a dictionary of res -> units) and what the pack could be deposited.
func refresh(store: Dictionary, can_deposit: bool) -> void:
	totals = store
	for res in rows:
		var n := int(store.get(res, 0))
		var l: Label = rows[res].count
		var t := str(n)
		if l.text != t:
			l.text = t
		for b in rows[res].buttons:
			(b as Button).disabled = n <= 0
	deposit_button.disabled = not can_deposit
