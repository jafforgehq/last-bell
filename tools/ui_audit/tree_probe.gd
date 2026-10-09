extends Node
## Tools-only probe (PH7 HUD audit): `--capture=...` is not needed; this is a driver loaded with `--script`-less use: run as
##   Godot --path . -- --winpx=1280x720 --os-scale=1 --town=1 --stage=arrive --shot=/tmp/x.png --frames=99999 --capture=audit --capture-scn=tree
## (see tools/capture_audit.gd). This file only holds the TREE WALK that capture_audit.gd uses, so that it can be tried and read on its own.
##
## `walk(root, ratio)` returns one record for each node of the CanvasLayers under `root` that is a CanvasItem showing (visible in the tree, an effective alpha over 0.04):
## {path, cls, layer, rect [x, y, w, h] in screen PIXELS, alpha, bg (a stylebox or a ColorRect/TextureRect that paints), text, script}.
## A Control whose rect is the whole window and that only draws (`_draw`) is marked `draw: true`: its rectangle says nothing, the pixel diff does.


static func walk(root: Node, ratio: Vector2) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is CanvasLayer:
			_walk(child, ratio, int((child as CanvasLayer).layer), 1.0, out, str(child.name))
	return out


static func _walk(n: Node, ratio: Vector2, layer: int, alpha: float, out: Array, path: String) -> void:
	for c in n.get_children():
		if not (c is CanvasItem):
			if c is CanvasLayer:
				_walk(c, ratio, int((c as CanvasLayer).layer), 1.0, out, path + "/" + str(c.name))
			continue
		var ci := c as CanvasItem
		if not ci.visible:
			continue
		var a := alpha * ci.modulate.a * ci.self_modulate.a
		if a < 0.04:
			continue
		var p := path + "/" + str(c.name)
		if c is Control:
			var ctl := c as Control
			var r := ctl.get_global_rect()
			var rec := {
				"path": p, "cls": ctl.get_class(), "layer": layer, "alpha": snappedf(a, 0.01),
				"rect": [r.position.x * ratio.x, r.position.y * ratio.y, r.size.x * ratio.x, r.size.y * ratio.y],
				"bg": _paints(ctl), "text": _text(ctl), "script": _script(ctl),
			}
			var vp_size := ctl.get_viewport_rect().size
			rec["full"] = r.size.x >= vp_size.x * 0.9 and r.size.y >= vp_size.y * 0.9
			out.append(rec)
		elif c is Node2D and not (c is Camera2D):
			var n2 := c as Node2D
			var gp := n2.get_global_transform_with_canvas().origin
			out.append({"path": p, "cls": c.get_class(), "layer": layer, "alpha": snappedf(a, 0.01), "rect": [gp.x * ratio.x, gp.y * ratio.y, 0.0, 0.0], "bg": false, "text": "", "script": _script(c), "n2d": true})
		_walk(c, ratio, layer, a, out, p)


static func _script(n: Node) -> String:
	var s = n.get_script()
	return String(s.resource_path).get_file() if s != null else ""


static func _text(ctl: Control) -> String:
	if ctl is Label:
		return String((ctl as Label).text).substr(0, 60)
	if ctl is Button:
		return String((ctl as Button).text).substr(0, 40)
	if ctl is RichTextLabel:
		return String((ctl as RichTextLabel).text).substr(0, 60)
	return ""


static func _paints(ctl: Control) -> bool:
	if ctl is ColorRect:
		return (ctl as ColorRect).color.a > 0.04
	if ctl is TextureRect:
		return (ctl as TextureRect).texture != null
	if ctl is Label or ctl is Button or ctl is RichTextLabel:
		return String(_text(ctl)) != "" or ctl is Button
	for sb_name in ["panel", "normal"]:
		if ctl.has_theme_stylebox(sb_name):
			var sb := ctl.get_theme_stylebox(sb_name)
			if sb is StyleBoxFlat and ((sb as StyleBoxFlat).bg_color.a > 0.04 or (sb as StyleBoxFlat).border_width_left > 0):
				return ctl is PanelContainer or ctl is Panel
			if sb is StyleBoxTexture:
				return ctl is PanelContainer or ctl is Panel
	return false
