## The one node the inventory windows hang from (INV-UI): a full-window Control under the HUD that lets the pointer through (only its windows stop it) and passes the events the windows
## cannot see to the controller (`inv_ui.gd`): a click anywhere puts the right-click menu away, and a button let go outside the window ends a drag that lost its release.
extends Control

var ctl


func _init() -> void:
	name = "InvRoot"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _input(ev: InputEvent) -> void:
	if ctl != null:
		ctl.root_input(ev)
