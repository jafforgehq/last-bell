## A contact sheet of the inventory's pictures (INV2): every item of items.json (and the loose shells as one, a few and a box) drawn as the windows draw them, from the atlas
## (assets/ui/inv/inv_icons.png, made by tools/make_item_icons.py), on the grid's own plate at 72, 48 and 32 px a cell, with the shotgun, the swing, the pack's badge, the quick slots'
## frames (empty, lit, off) and Ruth, to be looked at (readable at the smallest cell, told apart by shape). Windowed (headless cannot render), from the repo root:
##
##   Godot --path . --script res://tools/inv_icon_sheet.gd -- --out=/tmp/inv_icons.png
extends SceneTree

const InvApi := preload("res://scripts/ui/inv_api.gd")
const InvIcons := preload("res://scripts/ui/inv_icons.gd")

## The cell sizes of the rows of the sheet.
const CELLS := [72.0, 48.0, 32.0]
## What an item is drawn with: [item, count] (the loose shells in their three looks).
const LOOKS := [["shells", 1], ["shells", 5], ["shells", 24], ["canned_food", 3], ["ration_pack", 1], ["water_bottle", 1], ["water_jug", 1], ["bandage", 3], ["medkit", 1]]


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
	return default


func _initialize() -> void:
	_run.call_deferred()


class Sheet:
	extends Control

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		var y := 12.0
		for k in CELLS:
			var x := 12.0
			for look in LOOKS:
				var d: Dictionary = InvApi.item(String(look[0]))
				var r := Rect2(Vector2(x, y), Vector2(float(d.w), float(d.h)) * k)
				draw_rect(r.grow(-1.0), Color(InvIcons.res_color(String(d.res)), 0.16))
				draw_rect(r.grow(-1.0), Color("#d2a94e", 0.40), false, 1.0)
				InvIcons.draw_item(self, String(look[0]), r, 0, k, int(look[1]))
				x += float(d.w) * k + 8.0
			# the turned ones
			for look in LOOKS:
				var d2: Dictionary = InvApi.item(String(look[0]))
				if int(d2.w) != int(d2.h) and String(look[0]) != "shells":
					var r2 := Rect2(Vector2(x, y), Vector2(float(d2.h), float(d2.w)) * k)
					draw_rect(r2.grow(-1.0), Color(InvIcons.res_color(String(d2.res)), 0.16))
					draw_rect(r2.grow(-1.0), Color("#d2a94e", 0.40), false, 1.0)
					InvIcons.draw_item(self, String(look[0]), r2, 1, k, int(look[1]))
					x += float(d2.h) * k + 8.0
			y += 2.0 * k + 12.0
		# the equipment, the badge, the quick slots' frames and Ruth, at a cell of 72, 48 and 32 points
		y += 4.0
		var x2 := 12.0
		for k in CELLS:
			draw_rect(Rect2(Vector2(x2, y), Vector2(k * 2.0, k)), Color(0.035, 0.07, 0.06))
			InvIcons.draw_gun(self, Rect2(Vector2(x2 + 3.0, y + 2.0), Vector2(k * 2.0 - 6.0, k - 4.0)))
			x2 += k * 2.0 + 8.0
			draw_rect(Rect2(Vector2(x2, y), Vector2(k, k)), Color(0.035, 0.07, 0.06))
			InvIcons.draw_melee(self, Rect2(Vector2(x2, y), Vector2(k, k)))
			x2 += k + 8.0
			InvIcons.draw_pack(self, Rect2(Vector2(x2, y), Vector2(k * 0.6, k * 0.6)))
			x2 += k * 0.6 + 8.0
			for frame in ["slot", "slot_on", "slot_off"]:
				InvIcons.draw_region(self, frame, Rect2(Vector2(x2, y), Vector2(k * 0.8, k * 0.8)))
				x2 += k * 0.8 + 4.0
			x2 += 12.0
		InvIcons.draw_region(self, "ruth", Rect2(Vector2(1230.0, 12.0), Vector2(112.0, 168.0)))
		InvIcons.draw_region(self, "ruth", Rect2(Vector2(1360.0, 12.0), Vector2(56.0, 84.0)))


func _run() -> void:
	var out := _arg("out", "/tmp/inv_icons.png")
	var vp := SubViewport.new()
	vp.size = Vector2i(1440, 450)
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
