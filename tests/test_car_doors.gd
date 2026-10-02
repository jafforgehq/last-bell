extends "res://tests/case.gd"
## Round 15, the car doors: assets/data/vehicles.json says which way each picture's nose points (`nose`) and where its
## doors are (`doors`: id, side, the seats that use it, the panel rectangle and the hinge in the picture's pixels, how
## far it swings), and tools/make_car_doors.py cut the doors out of the game's own pictures:
##   assets/objects/<art>_open.png               the body with every door panel replaced by the dark cabin
##   assets/objects/<art>_door_<id>.png          one door, cut from the picture (same canvas, transparent elsewhere)
##   assets/objects/<art>_door_<id>_shadow.png   its soft shadow on the ground (same canvas, same hinge)
## The picture a car is drawn with while a door moves is `_open` plus the panels, so at angle 0 they must give back
## the original picture.

const VEHICLES_PATH := "res://assets/data/vehicles.json"
const OBJECTS := "res://assets/objects/"

## What "the same picture" means. The panels carry what makes a slab a door once it moves (a thin dark shut line along
## its cut edges, a handle), so they are not pixel for pixel the picture: a pixel is off when any premultiplied channel
## is further than PIXEL_TOLERANCE (0 to 1), at most OFF_SHARE_MAX of the pixels of the doors' area may be off, none by
## more than WORST_DIFF, and the mean difference stays under MEAN_DIFF_MAX.
const PIXEL_TOLERANCE := 10.0 / 255.0
const OFF_SHARE_MAX := 0.07
const WORST_DIFF := 110.0 / 255.0
const MEAN_DIFF_MAX := 4.0 / 255.0
## The hinge sits on the front edge of the panel, give or take this many pixels (the van's picture is tilted a little).
const HINGE_EDGE_SLACK := 6.0

const NOSE_FOR := {"N": Vector2(0, -1), "S": Vector2(0, 1), "E": Vector2(1, 0)}


func _kinds() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(VEHICLES_PATH))
	check(raw is Dictionary and raw.get("kinds") is Dictionary, "vehicles.json has its kinds")
	return raw.kinds if raw is Dictionary and raw.get("kinds") is Dictionary else {}


func _image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _rect(a) -> Rect2i:
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


func _door_path(art: String, id: String, suffix := "") -> String:
	return "%s%s_door_%s%s.png" % [OBJECTS, art, id, suffix]


func test_every_kind_says_which_way_its_nose_points_and_has_doors() -> void:
	var kinds := _kinds()
	for k in ["sedan", "pickup", "van", "bus"]:
		check(kinds.has(k), "%s is a kind" % k)
	for kind in kinds:
		var v: Dictionary = kinds[kind]
		check(NOSE_FOR.has(String(v.get("nose", ""))), "%s: nose is N, S or E (got %s)" % [kind, str(v.get("nose"))])
		check(v.get("doors") is Array and not v.doors.is_empty(), "%s has a list of doors" % kind)
		var ids := {}
		for d in v.get("doors", []):
			check(d is Dictionary, "%s: a door is an object" % kind)
			if not d is Dictionary:
				continue
			var id := String(d.get("id", ""))
			check(id != "" and not ids.has(id), "%s: door id %s is there and unique" % [kind, id])
			ids[id] = true
			check(["L", "R"].has(String(d.get("side", ""))), "%s %s: side is L or R" % [kind, id])
			# a door nobody is seated at is allowed (the sedan's rear left: a four-door body with three seats)
			check(d.get("seats") is Array, "%s %s: seats is a list" % [kind, id])
			check(d.get("panel") is Array and d.panel.size() == 4, "%s %s: panel is [x, y, w, h]" % [kind, id])
			check(d.get("hinge") is Array and d.hinge.size() == 2, "%s %s: hinge is [x, y]" % [kind, id])
			var deg := float(d.get("open_deg", 0.0))
			check(absf(deg) >= 60.0 and absf(deg) <= 100.0, "%s %s: open_deg %s is a real swing" % [kind, id, str(deg)])
			# positive is clockwise as drawn: a left door swings clockwise, a right door the other way
			check((deg > 0.0) == (String(d.get("side", "")) == "L"), "%s %s: the swing's sign follows the side" % [kind, id])


func test_every_seat_goes_through_exactly_one_door() -> void:
	var kinds := _kinds()
	for kind in kinds:
		var v: Dictionary = kinds[kind]
		var seats := int(v.get("seats", 0))
		var taken := {}
		for d in v.get("doors", []):
			for s in d.get("seats", []):
				check(int(s) >= 0 and int(s) < seats, "%s %s: seat %s is one the kind has" % [kind, d.get("id"), str(s)])
				check(not taken.has(int(s)), "%s: seat %s uses two doors" % [kind, str(s)])
				taken[int(s)] = String(d.get("id", ""))
		for s in seats:
			check(taken.has(s), "%s: seat %d has no door" % [kind, s])
		# the driver gets in on the left (seat 0 through a left door) wherever the kind has one
		if taken.has(0):
			check(String(taken[0]).begins_with("L") or kind == "bus", "%s: the driver's door is on the left" % kind)
	# the bus has one folding door, at the front on the right, and everybody uses it
	var bus: Dictionary = kinds.get("bus", {})
	eq(bus.get("doors", []).size(), 1, "the bus has one door")
	if bus.get("doors", []).size() == 1:
		eq(String(bus.doors[0].id), "F", "the bus door is F")
		eq(String(bus.doors[0].side), "R", "on the right")
		eq(bus.doors[0].seats.size(), int(bus.seats), "and all the bus's seats use it")
	# a sedan has two doors a side
	var sedan: Dictionary = kinds.get("sedan", {})
	var ids: Array = []
	for d in sedan.get("doors", []):
		ids.append(String(d.id))
	ids.sort()
	eq(ids, ["L1", "L2", "R1", "R2"], "a sedan has a front and a rear door on each side")


func test_the_pictures_and_pieces_are_there_and_load() -> void:
	var kinds := _kinds()
	for kind in kinds:
		var art := String(kinds[kind].get("art", ""))
		var body := _image("%s%s.png" % [OBJECTS, art])
		check(body != null, "%s: the picture %s loads" % [kind, art])
		var open_path := "%s%s_open.png" % [OBJECTS, art]
		check(ResourceLoader.exists(open_path) and load(open_path) is Texture2D, "%s: %s is imported" % [kind, open_path])
		var open := _image(open_path)
		check(open != null, "%s: _open reads as an image" % kind)
		if body != null and open != null:
			eq(open.get_size(), body.get_size(), "%s: _open has the picture's canvas" % kind)
		for d in kinds[kind].get("doors", []):
			for suffix in ["", "_shadow"]:
				var path := _door_path(art, String(d.id), suffix)
				check(ResourceLoader.exists(path) and load(path) is Texture2D, "%s is imported" % path)
				var img := _image(path)
				check(img != null, "%s reads as an image" % path)
				if img != null and body != null:
					eq(img.get_size(), body.get_size(), "%s has the picture's canvas" % path)


func test_panels_and_hinges_lie_inside_the_picture_and_match_the_cut() -> void:
	var kinds := _kinds()
	for kind in kinds:
		var art := String(kinds[kind].get("art", ""))
		var body := _image("%s%s.png" % [OBJECTS, art])
		if body == null:
			check(false, "%s: no picture" % kind)
			continue
		var canvas := Rect2i(Vector2i.ZERO, body.get_size())
		check(not kinds[kind].get("doors", []).is_empty(), "%s has doors to check" % kind)
		for d in kinds[kind].get("doors", []):
			var id := String(d.id)
			var panel := _rect(d.panel)
			check(canvas.encloses(panel) and panel.size.x > 0 and panel.size.y > 0, "%s %s: the panel is inside the picture" % [kind, id])
			var hinge := Vector2(float(d.hinge[0]), float(d.hinge[1]))
			check(canvas.has_point(Vector2i(hinge)), "%s %s: the hinge is inside the picture" % [kind, id])
			check(Rect2(panel).grow(1.0).has_point(hinge), "%s %s: the hinge is on its own panel" % [kind, id])
			var cut := _image(_door_path(art, id))
			if cut == null:
				check(false, "%s %s: no cut" % [kind, id])
				continue
			# the panel rectangle is exactly what the cut covers
			eq(cut.get_used_rect(), panel, "%s %s: the panel is the box of the cut" % [kind, id])
			var shadow := _image(_door_path(art, id, "_shadow"))
			if shadow != null:
				check(shadow.get_used_rect().encloses(panel), "%s %s: the shadow reaches past the panel" % [kind, id])
			# a door is a slab, not a speck: the cut fills most of its box
			var filled := 0
			for y in range(panel.position.y, panel.end.y):
				for x in range(panel.position.x, panel.end.x):
					if cut.get_pixel(x, y).a > 0.5:
						filled += 1
			check(float(filled) > 0.5 * panel.get_area(), "%s %s: the cut fills the panel (%d of %d)" % [kind, id, filled, panel.get_area()])


func test_the_hinge_is_at_the_front_edge_of_the_panel() -> void:
	var kinds := _kinds()
	for kind in kinds:
		var v: Dictionary = kinds[kind]
		var nose: Vector2 = NOSE_FOR.get(String(v.get("nose", "")), Vector2.ZERO)
		check(not v.get("doors", []).is_empty(), "%s has doors to check" % kind)
		for d in v.get("doors", []):
			var panel := Rect2(_rect(d.panel))
			var hinge := Vector2(float(d.hinge[0]), float(d.hinge[1]))
			# the front edge: the side of the panel the nose points at
			var front := 0.0
			var h := 0.0
			if nose.y < 0.0:
				front = panel.position.y
				h = hinge.y
			elif nose.y > 0.0:
				front = panel.end.y
				h = hinge.y
			else:
				front = panel.end.x
				h = hinge.x
			check(absf(h - front) <= HINGE_EDGE_SLACK, "%s %s: the hinge is %.1f px from the front edge" % [kind, d.id, absf(h - front)])
			# and the outer side: the hinge is on the side of the panel that faces away from the middle of the car
			# (the car's middle is the middle of the picture across the nose)


func test_left_and_right_doors_are_on_the_left_and_right_of_the_car() -> void:
	var kinds := _kinds()
	for kind in kinds:
		var v: Dictionary = kinds[kind]
		var nose: Vector2 = NOSE_FOR.get(String(v.get("nose", "")), Vector2.ZERO)
		var art := String(v.get("art", ""))
		var body := _image("%s%s.png" % [OBJECTS, art])
		if body == null or nose == Vector2.ZERO:
			continue
		# looking along the nose, left is (nose.y, -nose.x) in picture pixels (y runs down)
		var left := Vector2(nose.y, -nose.x)
		var centre := Vector2(body.get_size()) * 0.5
		check(not v.get("doors", []).is_empty(), "%s has doors to check" % kind)
		for d in v.get("doors", []):
			var mid := Vector2(_rect(d.panel).get_center()) - centre
			var side := mid.dot(left)
			check((side > 0.0) == (String(d.side) == "L"), "%s %s: the panel is on the %s of the car" % [kind, d.id, "left" if String(d.side) == "L" else "right"])


func _over_union(kind: Dictionary) -> Rect2i:
	var u := Rect2i()
	var first := true
	for d in kind.get("doors", []):
		var r := _rect(d.panel).grow(3)
		u = r if first else u.merge(r)
		first = false
	return u


func test_the_open_body_and_the_panels_give_back_the_picture() -> void:
	var kinds := _kinds()
	for kind in kinds:
		var v: Dictionary = kinds[kind]
		var art := String(v.get("art", ""))
		var body := _image("%s%s.png" % [OBJECTS, art])
		var open := _image("%s%s_open.png" % [OBJECTS, art])
		if body == null or open == null or body.get_size() != open.get_size():
			check(false, "%s: no picture or no _open" % kind)
			continue
		var comp := open.duplicate() as Image
		var area := 0
		var rects: Array = []
		for d in v.get("doors", []):
			var cut := _image(_door_path(art, String(d.id)))
			if cut == null or cut.get_size() != body.get_size():
				check(false, "%s %s: no cut" % [kind, d.id])
				continue
			var r := _rect(d.panel).grow(3).intersection(Rect2i(Vector2i.ZERO, body.get_size()))
			rects.append(r)
			comp.blend_rect(cut, r, r.position)
			area += r.get_area()
		# 1. inside the doors' boxes: the same picture, give or take rounding
		var off := 0
		var worst := 0.0
		var total := 0.0
		var n := 0
		for r in rects:
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var a := body.get_pixel(x, y)
					var b := comp.get_pixel(x, y)
					var diff := maxf(absf(a.a - b.a), maxf(absf(a.r * a.a - b.r * b.a), maxf(absf(a.g * a.a - b.g * b.a), absf(a.b * a.a - b.b * b.a))))
					total += diff
					worst = maxf(worst, diff)
					n += 1
					if diff > PIXEL_TOLERANCE:
						off += 1
		check(n > 0, "%s: there is something to compare" % kind)
		if n > 0:
			check(float(off) / float(n) <= OFF_SHARE_MAX, "%s: %d of %d pixels differ from the picture" % [kind, off, n])
			check(total / float(n) <= MEAN_DIFF_MAX, "%s: the mean difference is %.4f" % [kind, total / float(n)])
			check(worst <= WORST_DIFF, "%s: a pixel is off by %.3f" % [kind, worst])
		# 2. everywhere else the open body is the picture itself (the doors are the only thing cut out)
		var a2 := body.duplicate() as Image
		var b2 := open.duplicate() as Image
		for r in rects:
			a2.fill_rect(r, Color(0, 0, 0, 0))
			b2.fill_rect(r, Color(0, 0, 0, 0))
		check(a2.get_data() == b2.get_data(), "%s: outside the doors the open body is the picture" % kind)


func test_an_open_door_shows_a_dark_cabin_not_a_hole() -> void:
	var kinds := _kinds()
	for kind in kinds:
		var v: Dictionary = kinds[kind]
		var art := String(v.get("art", ""))
		var body := _image("%s%s.png" % [OBJECTS, art])
		var open := _image("%s%s_open.png" % [OBJECTS, art])
		if body == null or open == null:
			check(false, "%s: no pictures" % kind)
			continue
		for d in v.get("doors", []):
			var cut := _image(_door_path(art, String(d.id)))
			if cut == null:
				continue
			var panel := _rect(d.panel)
			var shut := 0.0
			var cabin := 0.0
			var covered := 0
			var seen := 0
			for y in range(panel.position.y, panel.end.y):
				for x in range(panel.position.x, panel.end.x):
					if cut.get_pixel(x, y).a < 0.99:
						continue
					covered += 1
					var o := open.get_pixel(x, y)
					if o.a < 0.99:
						continue
					seen += 1
					cabin += o.get_luminance()
					shut += body.get_pixel(x, y).get_luminance()
			check(covered > 0 and float(seen) > 0.8 * float(covered), "%s %s: the cabin fills the opening (%d of %d)" % [kind, d.id, seen, covered])
			if seen > 0:
				check(cabin / float(seen) < 0.22, "%s %s: the cabin is dark (mean luminance %.2f)" % [kind, d.id, cabin / float(seen)])
				check(cabin < 0.8 * shut, "%s %s: and darker than the door was (%.2f against %.2f)" % [kind, d.id, cabin / float(seen), shut / float(seen)])
