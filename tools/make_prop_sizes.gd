## Writes assets/data/prop_sizes.json: the size in pixels of every picture the town generator can put on a lot (the props of assets/data/site_layouts.json and of the art kit), so that the
## generator reads a size instead of loading the picture to measure it (a picture of the kit is up to 1000 x 1700 pixels: loading them was half of the generator's time on a desktop, and a
## lot that met a new kind of furniture was a step of 60 ms). `GD.tex_size` reads the table; a path that is not in it is measured by loading it, as before. Run it again when a prop picture
## is added or changed (`scripts/town/town_loader.gd` warns when it loads a picture of another size than the table's):
##
##   Godot --headless --path . --script res://tools/make_prop_sizes.gd
extends SceneTree

const TownKit := preload("res://scripts/town/town_kit.gd")

const OUT := "res://assets/data/prop_sizes.json"


func _initialize() -> void:
	var lay: Dictionary = TownKit.layouts()
	var paths := {}
	for k in lay.props:
		var p: Dictionary = lay.props[k]
		for f in p.files:
			paths["res://assets/%s/%s.png" % [String(p.get("dir", "objects")), String(f)]] = true
	var keys: Array = paths.keys()
	keys.sort()
	var lines: Array = []
	var missing := 0
	# (WORLD3: the life items live in one sheet, tools/make_town_life.py: they have no picture of their own and keep the size that script wrote)
	var old = JSON.parse_string(FileAccess.get_file_as_string(OUT)) if FileAccess.file_exists(OUT) else {}
	for path in keys:
		if String(path).contains("/town/life/") and old is Dictionary and old.has(path):
			lines.append("\"%s\": [%d, %d]" % [path, int(old[path][0]), int(old[path][1])])
			continue
		var tex := load(String(path)) as Texture2D
		if tex == null:
			push_error("make_prop_sizes: no picture %s" % path)
			missing += 1
			continue
		lines.append("\"%s\": [%d, %d]" % [path, tex.get_width(), tex.get_height()])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("{\n" + ",\n".join(lines) + "\n}\n")
	f.close()
	print("make_prop_sizes: %d pictures written to %s (%d missing)" % [lines.size(), OUT, missing])
	quit()
