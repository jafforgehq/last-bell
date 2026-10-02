## Draws a raid site (round 14) so it can be looked at: the real world (scripts/world.gd) built from the site's data,
## with the containers, the dead, the entry and the way out marked on it, saved as a PNG. Windowed (headless cannot
## render), from the repo root:
##
##   Godot --path . --script res://tools/site_preview.gd -- --kind=pharmacy --seed=3 --out=/tmp/pharmacy.png
##
## --kind=<place id or kind of assets/data/town.json> (the place's own data is used; a kind is the first place of it)
## --seed=N  --squad=N  --vehicle  --scale=0.55 (pixels to the tile are 64 x scale)  --bare (no markers)
## --ascii (print the site as text, no window needed: add --headless)  --stats (print what the site holds)
extends SceneTree

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const SiteGen := preload("res://scripts/raid/site_gen.gd")

var _site: Dictionary
var _marks: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
		if a == "--%s" % name:
			return "1"
	return default


static func place_for(key: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/town.json"))
	for p in parsed.places:
		if String(p.id) == key:
			return p
	for p in parsed.places:
		if String(p.kind) == key:
			return p
	return {"id": key, "name": key.capitalize(), "kind": key, "danger": 2, "loot": {"food": [8, 14], "scrap": [10, 20]}, "extra": {}}


func _run() -> void:
	var key := _arg("kind", "pharmacy")
	var seed_value := int(_arg("seed", "1"))
	var squad := int(_arg("squad", "3"))
	var place := place_for(key)
	var t0 := Time.get_ticks_msec()
	_site = SiteGen.make(place, seed_value, squad, _arg("vehicle") != "")
	var ms := Time.get_ticks_msec() - t0
	if _arg("stats") != "" or _arg("ascii") != "":
		_stats(ms)
	if _arg("ascii") != "":
		print(_ascii())
		if _arg("out") == "":
			quit()
			return
	var out := _arg("out", "")
	if out == "":
		quit()
		return
	var scale := float(_arg("scale", "0.55"))
	var size: Vector2i = _site.size
	var vp := SubViewport.new()
	vp.size = Vector2i(int(size.x * 64 * scale), int(size.y * 64 * scale))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.065, 0.055)
	bg.size = Vector2(size.x * 64, size.y * 64)
	vp.add_child(bg)
	var world := World.new()
	vp.add_child(world)
	world.build(_site.data)
	for tr in _site.data.trees:
		var s := Sprite2D.new()
		var box: Array = _site.data.tree.box
		var dens := float(_site.data.tree.density)
		s.texture = GD.tex(tr.file)
		s.centered = false
		s.offset = Vector2(box[0], box[1]) * dens
		s.scale = Vector2.ONE * (64.0 / dens)
		s.position = Vector2(tr.x, tr.y) * 64.0
		s.z_index = 6
		world.add_child(s)
	if _arg("bare") == "":
		_marks = Node2D.new()
		_marks.z_index = 20
		_marks.draw.connect(_draw_marks)
		world.add_child(_marks)
		_marks.queue_redraw()
	var cam := Camera2D.new()
	cam.position = Vector2(size.x, size.y) * 32.0
	cam.zoom = Vector2(scale, scale)
	vp.add_child(cam)
	cam.make_current()
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(out)
	print("saved %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	quit()


func _draw_marks() -> void:
	var T := 64.0
	var font := ThemeDB.fallback_font
	for c in _site.containers:
		var at: Vector2 = c.at
		var pos: Vector2 = c.pos
		_marks.draw_rect(Rect2((at - Vector2(0.5, 0.5)) * T, Vector2(T, T)), Color(1.0, 0.85, 0.1, 0.18))
		_marks.draw_rect(Rect2((pos - Vector2(0.35, 0.35)) * T, Vector2(0.7, 0.7) * T), Color(1.0, 0.85, 0.1, 0.9), false, 2.0)
		var parts: Array = []
		for k in c.loot:
			parts.append("%s%d" % [String(k).substr(0, 1), int(c.loot[k])])
		_marks.draw_string(font, pos * T + Vector2(-20, -24), "%s %s" % [String(c.kind).substr(0, 3), " ".join(parts)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.5))
	for z in _site.dead:
		var p: Vector2 = z.pos
		var col := Color(0.9, 0.2, 0.2, 0.85)
		var rad := 9.0
		if z.kind == "runner":
			col = Color(1.0, 0.55, 0.1, 0.9)
		elif z.kind == "brute":
			col = Color(0.7, 0.1, 0.8, 0.9)
			rad = 15.0
		_marks.draw_circle(p * T, rad, col)
		if z.state == "wander":
			_marks.draw_arc(p * T, rad + 4.0, 0, TAU, 16, Color(1, 1, 1, 0.8), 2.0)
	var e: Vector2 = _site.entry
	_marks.draw_circle(e * T, 9.0, Color(0.2, 1.0, 0.3, 0.9))
	_marks.draw_rect(Rect2(_site.exit.position * T, _site.exit.size * T), Color(0.2, 1.0, 0.3, 0.8), false, 3.0)
	var v: Vector2 = _site.vehicle_spot
	if v.x >= 0.0:
		_marks.draw_rect(Rect2((v - Vector2(1.0, 2.2)) * T, Vector2(2.0, 4.4) * T), Color(0.3, 0.6, 1.0, 0.9), false, 3.0)
	for r in _site.rooms:
		var rr: Rect2 = r.rect
		_marks.draw_rect(Rect2(rr.position * T, rr.size * T), Color(1, 1, 1, 0.35), false, 1.5)
		_marks.draw_string(font, rr.position * T + Vector2(6, 16), String(r.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))


func _stats(ms: int) -> void:
	var loot := {}
	var kinds := {}
	for c in _site.containers:
		kinds[c.kind] = int(kinds.get(c.kind, 0)) + 1
		for k in c.loot:
			loot[k] = int(loot.get(k, 0)) + int(c.loot[k])
	var dead := {}
	var near := 0
	for z in _site.dead:
		dead[z.kind] = int(dead.get(z.kind, 0)) + 1
		if Vector2(z.pos).distance_to(_site.entry) < 8.0:
			near += 1
	print("%s (%s) seed %d: %s tiles, made in %d ms" % [_site.name, _site.kind, _site.seed, str(_site.size), ms])
	print("  containers %d %s, loot %s" % [_site.containers.size(), str(kinds), str(loot)])
	print("  dead %d %s (%d near the entry), rooms %s" % [_site.dead.size(), str(dead), near, str(_site.rooms.map(func(r): return r.name))])
	print("  entry %s exit %s vehicle %s objects %d trees %d" % [str(_site.entry), str(_site.exit), str(_site.vehicle_spot), _site.data.objects.size(), _site.data.trees.size()])


## The site as text: # a wall or a prop, . open ground, digits and letters for what stands in it.
func _ascii() -> String:
	var d: Dictionary = _site.data
	var W := int(d.W)
	var H := int(d.H)
	var grid: Array = []
	for y in H:
		var row: Array = []
		for x in W:
			row.append("#" if int(d.solidP[y * W + x]) != 0 else ".")
		grid.append(row)
	for i in _site.containers.size():
		var c: Dictionary = _site.containers[i]
		var p: Vector2 = c.pos
		grid[int(p.y)][int(p.x)] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"[i % 52]
	for z in _site.dead:
		var p: Vector2 = z.pos
		if grid[int(p.y)][int(p.x)] in [".", "#"]:
			grid[int(p.y)][int(p.x)] = {"walker": "z", "runner": "r", "brute": "&"}[z.kind]
	var e: Vector2 = _site.entry
	grid[int(e.y)][int(e.x)] = "@"
	var lines: Array = []
	for y in H:
		lines.append("".join(grid[y]))
	return "\n".join(lines)
