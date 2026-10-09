## The right-click menu of a stack (INV-UI): a small board of the HUD's buttons at the pointer: Use, Split, Turn, Take or Put back or Deposit, Drop. Made once and refilled for each stack
## (`open_for`); each button calls the controller (`inv_ui.gd`) and the menu goes. It is put away by Esc, by a click anywhere else and when the window under it closes.
extends PanelContainer

const RadioKit := preload("res://scripts/ui/radio_kit.gd")

var ctl
var hud
var box: VBoxContainer
## The entries of the open menu as [label, id] (the tests read them).
var entries: Array = []


func setup(controller, hud_node) -> void:
	ctl = controller
	hud = hud_node
	name = "InvMenu"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st: StyleBox = hud._style(hud.PANEL, 6, hud.LINE2, true, "panel_slim")
	if st is StyleBoxFlat:
		st.content_margin_left = 6
		st.content_margin_right = 6
		st.content_margin_top = 6
		st.content_margin_bottom = 6
	add_theme_stylebox_override("panel", st)
	box = hud._vbox(3)
	add_child(box)
	visible = false


## Fills the menu with `list` ([[label, id, enabled, why], ...]) and puts it at `at` (kept inside the window).
func open_for(list: Array, at: Vector2, bounds: Vector2) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	entries = []
	for e in list:
		var b := RadioKit.small_button(hud, String(e[0]), 28.0, 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 150.0
		var ok := bool(e[2])
		b.disabled = not ok
		if not ok and String(e[3]) != "":
			b.tooltip_text = String(e[3])
		var id := String(e[1])
		b.pressed.connect(func(): ctl.menu_pick(id))
		box.add_child(b)
		entries.append([String(e[0]), id])
	reset_size()
	size = get_combined_minimum_size()
	position = Vector2(clampf(at.x, 6.0, maxf(6.0, bounds.x - size.x - 6.0)), clampf(at.y, 6.0, maxf(6.0, bounds.y - size.y - 6.0)))
	visible = true


func close() -> void:
	visible = false
