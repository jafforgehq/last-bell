extends "res://tests/case.gd"
## The pictures the yard draws its buildings from (assets/data/building_art.json, drawn by tools/make_building_art.py and,
## for the older ones, by hand and tools/make_*.py): every picture named exists and loads, is about as wide to its height
## as the size it is drawn at (the yard stretches a picture to `w` by `h` tiles, so a picture with the wrong shape is a
## squashed one), is small enough to ship, the three tents are three colours, and the beds and the walls the simulation
## reads (`beds` and `solid`, scripts/sim/build.gd) are what they were: art may change, the rules may not.

const ART_PATH := "res://assets/data/building_art.json"
const OBJECTS := "res://assets/objects/"
## The pictures tools/make_building_art.py writes (143, 144 and 117 are the tents and the tarp it replaced, in place): the file size cap is for these.
const MADE := ["143_tent", "144_tent", "393_tent", "394_bunkroof", "395_bunkbed", "396_bunkbed", "397_bunkbed", "398_bunkbed",
		"399_workshop", "400_tunnel", "401_tunnel", "402_floodlight", "403_floodlight", "117_tarp", "404_tarp"]
## The four beds are strips that butt against each other, so their edges are solid (all but the bottom, where the shadow fades).
const TILES := ["395_bunkbed", "396_bunkbed", "397_bunkbed", "398_bunkbed"]
const MAX_KB := 64
## What the simulation reads of each building, as it was before the art was redrawn.
const SOLID := {
	"salvage_bench": [-1.5, -1.5, 1.5, 0.5],
	"greenhouse": [-1.5, -1.5, 1.5, 0.5],
	"workshop": [-1.5, -1.5, 1.5, 0.5],
	"tents": [-1.5, -1.5, 1.5, 0.5],
	"floodlights": [-0.5, -0.5, 0.5, 0.5],
	"watchtower": [-1.5, -1.5, 1.5, 0.5],
	"radio_mast": [-1.5, -0.5, 1.5, 0.5],
	"scrap_yard": [-1.5, -1.5, 1.5, 0.5],
}
const BEDS := [[-1.17, -0.5], [-0.39, -0.5], [0.39, -0.5], [1.17, -0.5]]


func _art() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ART_PATH))
	return parsed if parsed is Dictionary else {}


## Every prop of every building and of every scaffold stage, with the names of the pictures it may be drawn from.
func _props() -> Array:
	var art := _art()
	var out: Array = []
	for st in art.get("scaffold", []):
		for pr in st.get("props", []):
			out.append({"where": "scaffold", "pr": pr})
	var buildings: Dictionary = art.get("buildings", {})
	for id in buildings:
		for pr in buildings[id].get("props", []):
			out.append({"where": String(id), "pr": pr})
	return out


func _files_of(pr: Dictionary) -> Array:
	var files: Array = [String(pr.f)]
	if pr.has("e"):
		files.append(String(pr.e))
	for f in pr.get("by_n", []):
		files.append(String(f))
	return files


func _image(file: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(OBJECTS + file + ".png"))


func test_every_picture_the_art_names_exists_loads_and_is_drawn_to_its_own_shape() -> void:
	var props := _props()
	check(props.size() > 30, "the art has its props: %d" % props.size())
	for entry in props:
		var pr: Dictionary = entry.pr
		for file in _files_of(pr):
			var path: String = OBJECTS + String(file) + ".png"
			check(ResourceLoader.exists(path), "%s: %s is a picture" % [entry.where, file])
			var tex = load(path)
			check(tex is Texture2D, "%s: %s loads (is it imported? run Godot --headless --import)" % [entry.where, file])
			if not (tex is Texture2D):
				continue
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			check(tw >= 8.0 and th >= 8.0 and tw <= 1200.0 and th <= 1200.0, "%s: %s is a sane size: %dx%d" % [entry.where, file, int(tw), int(th)])
			var w := float(pr.w)
			var h := float(pr.h)
			# the yard stretches the picture to w x h tiles: its shape must be that of the size
			var shape := (tw / th) / (w / h)
			check(shape > 0.85 and shape < 1.18, "%s: %s is drawn %.2f x %.2f tiles but is %dx%d (stretched %.2f)" % [entry.where, file, w, h, int(tw), int(th), shape])
			# and about as fine as the other props (somewhere between 40 and 400 pixels to the tile: the deck's pieces are the finest)
			var ppt := tw / w
			check(ppt > 40.0 and ppt < 400.0, "%s: %s has %.0f pixels to the tile" % [entry.where, file, ppt])


func test_the_new_pictures_are_small_clean_and_on_a_transparent_ground() -> void:
	for file in MADE:
		var path := ProjectSettings.globalize_path(OBJECTS + file + ".png")
		var f := FileAccess.open(path, FileAccess.READ)
		check(f != null, "%s is on disk" % file)
		if f == null:
			continue
		var kb := int(f.get_length() / 1024)
		f.close()
		check(kb <= MAX_KB, "%s is %d KB (more than %d)" % [file, kb, MAX_KB])
		var img := _image(file)
		check(img != null and not img.is_empty(), "%s reads" % file)
		if img == null or img.is_empty():
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		# the shadow and the ropes fade out before the edge of the picture (nothing is cut off), the strips of floor excepted
		var edge := 0.0
		for x in w:
			edge = maxf(edge, img.get_pixel(x, h - 1).a)
			if not (file in TILES):
				edge = maxf(edge, img.get_pixel(x, 0).a)
		if not (file in TILES):
			for y in h:
				edge = maxf(edge, maxf(img.get_pixel(0, y).a, img.get_pixel(w - 1, y).a))
		check(edge < 0.05, "%s: nothing is cut off at the edge of the picture (alpha %.2f there)" % [file, edge])
		var solid := 0
		for y in range(0, h, 3):
			for x in range(0, w, 3):
				if img.get_pixel(x, y).a > 0.3:
					solid += 1
		var share := float(solid) / float(((h + 2) / 3) * ((w + 2) / 3))
		check(share > 0.08 and share < 0.97, "%s is a picture of something: %.2f of it is there" % [file, share])


func test_the_three_tents_are_three_colours_and_a_row_of_them_is_not_one_picture() -> void:
	var art := _art()
	var by_n: Array = []
	for pr in art.buildings.tents.props:
		if pr.has("by_n"):
			by_n = pr.by_n
	check(by_n.size() >= 3, "the tents have three pictures to choose among: %s" % str(by_n))
	var means: Array = []
	for file in by_n:
		var img := _image(String(file))
		check(img != null and not img.is_empty(), "%s reads" % file)
		if img == null or img.is_empty():
			continue
		img.convert(Image.FORMAT_RGBA8)
		var sum := Vector3.ZERO
		var n := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var c := img.get_pixel(x, y)
				if c.a > 0.95:
					sum += Vector3(c.r, c.g, c.b)
					n += 1
		check(n > 500, "%s has canvas to it" % file)
		means.append(sum / maxf(1.0, float(n)))
	for i in means.size():
		for j in range(i + 1, means.size()):
			check((means[i] as Vector3).distance_to(means[j]) > 0.08, "tents %d and %d are not the same colour" % [i, j])


func test_the_walls_and_the_beds_the_simulation_reads_are_unchanged() -> void:
	var buildings: Dictionary = _art().buildings
	eq(buildings.size(), 9, "nine buildings")
	for id in SOLID:
		check(buildings.has(id), "%s is in the art" % id)
		eq(buildings[id].get("solid", []), SOLID[id], "%s shuts what it shut" % id)
	check(not buildings.bunk_house.has("solid"), "the bunk house shuts nothing, as it did")
	eq(buildings.bunk_house.beds, BEDS, "the bunk house's four beds are where they were")
	# nothing but the floodlights carries lamps (tests/test_build_view.gd)
	for id in buildings:
		if id != "floodlights":
			check(not buildings[id].has("lights"), "%s has no lamps" % id)
	var lamps: Array = buildings.floodlights.lights
	eq(lamps.size(), 2, "two floodlights")


func test_the_bunk_house_lies_the_beds_on_floor_and_keeps_its_roof_off_the_hurt() -> void:
	var b: Dictionary = _art().buildings.bunk_house
	var roof: Dictionary = {}
	var floors: Array = []
	for pr in b.props:
		if bool(pr.get("flat", false)):
			floors.append(pr)
		else:
			roof = pr
	check(not roof.is_empty() and roof.has("sort"), "the roof stands up and has its feet where the posts are")
	eq(floors.size(), 4, "four beds lie on the ground")
	# every bed's spot is on one of the flat pictures, so the patient lies on a cot, not on the bare ground
	for spot in b.beds:
		var on := 0
		for pr in floors:
			var x := float(spot[0])
			var y := float(spot[1])
			if x >= float(pr.x) - float(pr.w) / 2.0 and x <= float(pr.x) + float(pr.w) / 2.0 and y >= float(pr.y) - float(pr.h) and y <= float(pr.y):
				on += 1
		check(on >= 1, "the bed at %s is on a picture" % str(spot))
	# and the roof's picture has nothing solid over a bed (only its shadow): the patients are not drawn under the sheets
	var img := _image(String(roof.f))
	check(img != null and not img.is_empty(), "the roof reads")
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGBA8)
	for spot in b.beds:
		var fx := (float(spot[0]) - (float(roof.x) - float(roof.w) / 2.0)) / float(roof.w)
		var fy := (float(spot[1]) - (float(roof.y) - float(roof.h))) / float(roof.h)
		var a := img.get_pixel(clampi(int(fx * img.get_width()), 0, img.get_width() - 1), clampi(int(fy * img.get_height()), 0, img.get_height() - 1)).a
		check(a < 0.62, "nothing but the roof's shadow is over the bed at %s (alpha %.2f)" % [str(spot), a])


func test_the_shade_shelter_keeps_the_shape_and_the_place_of_the_tarp_it_replaced_and_shows_what_is_under_it() -> void:
	var map = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/map.json"))
	var dressing = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/dressing.json"))
	var seen := 0
	var pieces: Array = []
	for o in map.objects:
		for pc in o.get("pieces", []):
			if String(pc.file).ends_with("/117_tarp.png"):
				pieces.append({"f": "117_tarp", "w": float(pc.w), "h": float(pc.h), "where": "the yard"})
	for pc in dressing.pieces:
		if String(pc.f) == "117_tarp" or String(pc.f) == "404_tarp":
			pieces.append({"f": String(pc.f), "w": float(pc.w), "h": float(pc.h), "where": "the street"})
	check(pieces.size() >= 5, "the yard's shelter and the street's are placed: %d" % pieces.size())
	var files := {}
	for pc in pieces:
		files[pc.f] = true
		var img := _image(String(pc.f))
		check(img != null and not img.is_empty(), "%s reads" % pc.f)
		if img == null or img.is_empty():
			continue
		# placed at the shape it was drawn in (the same as the blue tarp's: 836 x 717 pixels, 7.46 x 6.40 tiles in the yard)
		var shape := (float(img.get_width()) / float(img.get_height())) / (float(pc.w) / float(pc.h))
		check(shape > 0.97 and shape < 1.03, "%s in %s is not stretched (%.3f)" % [pc.f, pc.where, shape])
		seen += 1
	check(files.has("117_tarp") and files.has("404_tarp"), "both colours are in use: %s" % str(files.keys()))
	# it is shade cloth: the middle is see-through (the worktable, the generator and the crate under it show), its hem is not
	for f in ["117_tarp", "404_tarp"]:
		var img := _image(f)
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var mid := img.get_pixel(int(float(w) * 0.485), int(float(h) * 0.455)).a
		check(mid > 0.25 and mid < 0.75, "%s: the middle of the awning is see-through (alpha %.2f)" % [f, mid])
		var hem := img.get_pixel(int(float(w) * 0.485), int(float(h) * 0.125)).a
		check(hem > 0.85, "%s: its hem is solid (alpha %.2f)" % [f, hem])
