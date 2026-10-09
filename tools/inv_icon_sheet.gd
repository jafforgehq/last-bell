## A contact sheet of the inventory's pictures (INV-UI): every item of items.json drawn by `scripts/ui/inv_icons.gd` on the grid's own cells at 96, 48 and 40 px a cell, with the gun, the swing and the pack,
## to be looked at (readable at the smallest window, told apart by shape). Windowed (headless cannot render), from the repo root:
##
##   Godot --path . --script res://tools/inv_icon_sheet.gd -- --out=/tmp/inv_icons.png
extends SceneTree

const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvIcons := preload("res://scripts/ui/inv_icons.gd")

## The cell sizes of the rows of the sheet.
const CELLS := [96.0, 48.0, 40.0]


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
	return default


func _initialize() -> void:
	_run.call_deferred()


class Sheet:
	extends Control

	func _draw() -> void:
		var ids: Array = InvApi.defs().keys()
		ids.sort()
		var y := 12.0
		for k in CELLS:
			var x := 12.0
			for id in ids:
				var d: Dictionary = InvApi.item(String(id))
				var r := Rect2(Vector2(x, y), Vector2(float(d.w), float(d.h)) * k)
				draw_rect(r.grow(-2.0), Color(InvIcons.res_color(String(d.res)), 0.2))
				draw_rect(r.grow(-2.0), Color("#d2a94e", 0.55), false, 1.5)
				InvIcons.draw_item(self, String(id), r, 0, k)
				x += float(d.w) * k + 10.0
			# the turned ones
			for id in ids:
				var d2: Dictionary = InvApi.item(String(id))
				if int(d2.w) != int(d2.h):
					var r2 := Rect2(Vector2(x, y), Vector2(float(d2.h), float(d2.w)) * k)
					draw_rect(r2.grow(-2.0), Color(InvIcons.res_color(String(d2.res)), 0.2))
					draw_rect(r2.grow(-2.0), Color("#d2a94e", 0.55), false, 1.5)
					InvIcons.draw_item(self, String(id), r2, 1, k)
					x += float(d2.h) * k + 10.0
			y += 2.0 * k + 16.0
		draw_rect(Rect2(Vector2(12.0, y), Vector2(330, 70)), Color(0.035, 0.07, 0.06))
		InvIcons.draw_gun(self, Rect2(Vector2(20.0, y + 8.0), Vector2(130, 54)))
		InvIcons.draw_melee(self, Rect2(Vector2(170.0, y + 8.0), Vector2(54, 54)))
		InvIcons.draw_pack(self, Rect2(Vector2(250.0, y + 8.0), Vector2(54, 54)), Color("#d2a94e"))


func _run() -> void:
	var out := _arg("out", "/tmp/inv_icons.png")
	var vp := SubViewport.new()
	vp.size = Vector2i(1500, 620)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color("#1b2a26")
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	var sheet := Sheet.new()
	sheet.size = Vector2(vp.size)
	vp.add_child(sheet)
	for i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	img.save_png(out)
	print("sheet saved: ", out)
	quit()
