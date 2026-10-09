## The stash panel (INV-UI): E at the base stash opens it (`sim.inv.stash_open`) beside the backpack. The STORES as five rows (ammo, food, water, medicine, scrap), each with the number the
## base holds now (read from `sim.inv.store_totals()` ten times a second: it follows the crew's work as it happens) and the buttons that take 1, 5 or all that fits out as items into the pack;
## Deposit all puts everything in the pack that stands for a store into the stores; an item dragged onto this panel is deposited too (`inv_ui.gd` does the drop). Scrap is never carried: it has
## a number and no buttons. It never takes a key and never pauses the game.
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
var hint: Label
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
	var st: StyleBox = hud._style(hud.PANEL, 6, hud.LINE2, true, "panel")
	if st is StyleBoxFlat:
		st.content_margin_left = 12
		st.content_margin_right = 12
		st.content_margin_top = 9
		st.content_margin_bottom = 10
	add_theme_stylebox_override("panel", st)
	var col: VBoxContainer = hud._vbox(6)
	add_child(col)
	var head: HBoxContainer = hud._hbox(8)
	title = hud._label("STORES AT THE BASE", Fonts.cond(700, 1), 15, hud.ACCENT)
	head.add_child(title)
	head.add_child(hud._spacer())
	close_button = RadioKit.small_button(hud, "×", 26.0, 18)
	close_button.custom_minimum_size.x = 30.0
	close_button.tooltip_text = "Close the stash\nKey: Esc"
	close_button.pressed.connect(func(): ctl.close_stash())
	head.add_child(close_button)
	col.add_child(head)
	for r in ROWS:
		col.add_child(_row(String(r[0]), String(r[1]), String(r[2])))
	deposit_button = RadioKit.small_button(hud, "Deposit all", 30.0, 15)
	deposit_button.tooltip_text = "Put everything in the pack that stands for a store into the stores"
	deposit_button.pressed.connect(func(): ctl.deposit_all_pressed())
	col.add_child(deposit_button)
	hint = hud._label("Drag an item onto this panel to deposit it.", Fonts.sans(400), 13, hud.INK3)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 120
	col.add_child(hint)


func _row(res: String, label: String, what: String) -> Control:
	var row: HBoxContainer = hud._hbox(8)
	row.custom_minimum_size.y = 34.0
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic: TextureRect = hud._icon(res, 20, InvIcons.res_color(res))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var name_l: Label = hud._label(label, Fonts.sans(600, 0), 15, hud.INK)
	name_l.custom_minimum_size.x = 70
	row.add_child(name_l)
	row.add_child(hud._spacer())
	var count: Label = hud._label("0", Fonts.cond(700, 0), 20, hud.INK)
	count.custom_minimum_size.x = 48
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count)
	var buttons: Array = []
	if what != "":
		for w in WITHDRAW:
			var b := RadioKit.small_button(hud, String(w[0]), 28.0, 14)
			b.custom_minimum_size.x = 34.0 if String(w[0]) != "All" else 40.0
			var n := int(w[1])
			b.tooltip_text = ("Take %d %s out of the stores into the pack, as %s" % [n, label.to_lower(), what]) if n > 0 else "Take all the %s that fits in the pack, as %s" % [label.to_lower(), what]
			b.pressed.connect(func(): ctl.withdraw_pressed(res, n))
			row.add_child(b)
			buttons.append(b)
	else:
		var note: Label = hud._label("kept at the base", Fonts.sans(400, 0), 12, hud.INK3)
		note.tooltip_text = "Scrap is never carried: it goes straight into the stores, and the base is built from it"
		row.add_child(note)
		row.tooltip_text = note.tooltip_text
	rows[res] = {"count": count, "buttons": buttons}
	return row


var _compact := false


## The small window (1024 x 640): the rows are a little shorter and the hint is the tooltip's, so that the panel fits between the alerts and the toolbar.
func set_compact(on: bool) -> void:
	if on == _compact:
		return
	_compact = on
	hint.visible = not on
	deposit_button.custom_minimum_size.y = 26.0 if on else 30.0
	for res in rows:
		var row: Control = (rows[res].count as Label).get_parent()
		row.custom_minimum_size.y = 28.0 if on else 34.0
		for b in rows[res].buttons:
			(b as Button).custom_minimum_size.y = 24.0 if on else 28.0
	tooltip_text = "Drag an item onto this panel to deposit it" if on else ""


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
