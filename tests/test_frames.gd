extends "res://tests/case.gd"
## The frames of the noticeboard look: assets/ui/theme/frames.json, the pictures it lists
## (made by tools/make_ui_theme.py) and scripts/ui/frames.gd, which turns them into style boxes.

const Frames := preload("res://scripts/ui/frames.gd")

const JSON_PATH := "res://assets/ui/theme/frames.json"
## The HUD's text colours (scripts/ui/hud.gd) and the dark ink of a modal.
const INK := Color("#ece6d8")
const INK2 := Color("#b7af9e")
const INK3 := Color("#9a937f")
const ACCENT_INK := Color("#1a1508")
const PAPER_INK := Color("#262b36")
## The frames the plan names (round 3, the interfaces section).
const PLANNED := ["panel", "panel_inset", "card", "card_selected", "slip", "paper", "tooltip", "toast", "chip", "button",
		"button_hover", "button_pressed", "button_off", "button_primary", "button_primary_hover", "bar_track", "pill", "clock", "banner"]
## The dark ones: boards the HUD's light text is read on.
const DARK := ["panel", "panel_slim", "panel_inset", "card", "card_selected", "tooltip", "toast", "clock", "banner"]
const BUTTONS := ["button", "button_hover", "button_pressed", "button_off", "button_primary", "button_primary_hover", "button_primary_pressed"]


func _table() -> Dictionary:
	var json := JSON.new()
	check(json.parse(FileAccess.get_file_as_string(JSON_PATH)) == OK, "frames.json parses")
	return json.data if typeof(json.data) == TYPE_DICTIONARY else {}


func _image(entry: Dictionary) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(String(entry.file)))


## Relative luminance of a colour (WCAG), and the contrast of two colours.
func _lum(c: Color) -> float:
	var lin := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## The average colour of the middle of a frame's picture (inside its nine-patch margins).
func _middle_average(entry: Dictionary) -> Color:
	var img := _image(entry)
	var m: Array = entry.margin
	var x0 := int(m[0])
	var y0 := int(m[1])
	var x1 := img.get_width() - int(m[2])
	var y1 := img.get_height() - int(m[3])
	if x1 <= x0 or y1 <= y0:                                    # a bar has no middle: take its centre rows
		x0 = int(m[0]) - 1
		x1 = img.get_width() - int(m[2]) + 1
		y0 = img.get_height() / 2 - 1
		y1 = img.get_height() / 2 + 1
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			sum += Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
			n += 1
	return Color(sum.r / maxf(sum.a, 0.0001), sum.g / maxf(sum.a, 0.0001), sum.b / maxf(sum.a, 0.0001), sum.a / float(n))


func test_frames_json_lists_the_planned_frames() -> void:
	var t := _table()
	for name in PLANNED:
		check(t.has(name), "frames.json lists %s" % name)
	for name in t:
		var e: Dictionary = t[name]
		for key in ["file", "margin", "content", "expand", "stretch"]:
			check(e.has(key), "%s has %s" % [name, key])
		eq(String(e.get("file", "")), "res://assets/ui/theme/%s.png" % name, "%s file" % name)
		for key in ["margin", "content", "expand"]:
			eq(typeof(e.get(key)), TYPE_ARRAY, "%s %s is a list" % [name, key])
			eq((e.get(key) as Array).size(), 4, "%s %s has four numbers" % [name, key])


func test_every_listed_file_exists_and_loads() -> void:
	var t := _table()
	for name in t:
		var path := String(t[name].file)
		check(FileAccess.file_exists(path), "%s: the file is there" % name)
		check(ResourceLoader.exists(path), "%s: the file is imported" % name)
		var tex = load(path) if ResourceLoader.exists(path) else null
		check(tex is Texture2D, "%s loads as a texture" % name)


func test_margins_fit_inside_the_picture() -> void:
	var t := _table()
	for name in t:
		var e: Dictionary = t[name]
		var img := _image(e)
		check(img != null and not img.is_empty(), "%s: the picture reads" % name)
		if img == null or img.is_empty():
			continue
		var w := img.get_width()
		var h := img.get_height()
		check(w % 2 == 0 and h % 2 == 0, "%s: %dx%d, the sides are even (the picture is drawn at half size)" % [name, w, h])
		var m: Array = e.margin
		check(int(m[0]) + int(m[2]) <= w and int(m[1]) + int(m[3]) <= h, "%s: the margins %s leave room in %dx%d" % [name, str(m), w, h])
		for i in 4:
			check(float(m[i]) >= 0.0, "%s: margin %d is not negative" % [name, i])
			check(float((e.content as Array)[i]) >= 0.0, "%s: content margin %d is not negative" % [name, i])
			# the shadow outside the board lies inside the margins, or the Control's edge would cut the nine-patch
			check(float((e.expand as Array)[i]) * 2.0 <= float(m[i]) + 0.001, "%s: the shadow (%s) is within the margin %s" % [name, str(e.expand), str(m)])
		for mode in e.stretch:
			check(String(mode) in ["stretch", "tile", "tile_fit"], "%s: a known stretch mode" % name)


func test_box_is_a_nine_patch_at_half_size() -> void:
	Frames.forget()
	var t := _table()
	for name in t:
		var e: Dictionary = t[name]
		var sb = Frames.box(name)
		check(sb is StyleBoxTexture, "%s: a StyleBoxTexture" % name)
		if not (sb is StyleBoxTexture):
			continue
		var m: Array = e.margin
		near(sb.texture_margin_left, float(m[0]) * 0.5, 0.001, "%s left margin, halved for the 2x picture" % name)
		near(sb.texture_margin_top, float(m[1]) * 0.5, 0.001, "%s top margin" % name)
		near(sb.texture_margin_right, float(m[2]) * 0.5, 0.001, "%s right margin" % name)
		near(sb.texture_margin_bottom, float(m[3]) * 0.5, 0.001, "%s bottom margin" % name)
		var c: Array = e.content
		near(sb.content_margin_left, float(c[0]), 0.001, "%s content left" % name)
		near(sb.content_margin_top, float(c[1]), 0.001, "%s content top" % name)
		near(sb.content_margin_right, float(c[2]), 0.001, "%s content right" % name)
		near(sb.content_margin_bottom, float(c[3]), 0.001, "%s content bottom" % name)
		var x: Array = e.expand
		near(sb.expand_margin_left, float(x[0]), 0.001, "%s shadow left" % name)
		near(sb.expand_margin_bottom, float(x[3]), 0.001, "%s shadow bottom" % name)
		check(sb.texture != null, "%s has its texture" % name)
		eq(sb.modulate_color, Color.WHITE, "%s is untinted by default" % name)
		check(sb.draw_center, "%s draws its middle" % name)
		var modes := {"stretch": StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH, "tile": StyleBoxTexture.AXIS_STRETCH_MODE_TILE, "tile_fit": StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT}
		eq(sb.axis_stretch_horizontal, modes[String(e.stretch[0])], "%s stretches its middle sideways as frames.json says" % name)
		eq(sb.axis_stretch_vertical, modes[String(e.stretch[1])], "%s stretches its middle up and down as frames.json says" % name)
		# the whole picture is at twice the size it is shown at: the texture says half
		var img := _image(e)
		if sb.texture is ImageTexture:
			eq(sb.texture.get_size(), Vector2(img.get_width() / 2, img.get_height() / 2), "%s reports half its size" % name)


func test_box_takes_a_tint_and_is_a_fresh_style_each_time() -> void:
	Frames.forget()
	var red := Color("#e0584a")
	var a = Frames.box("slip", red)
	var b = Frames.box("slip", red)
	check(a is StyleBoxTexture and b is StyleBoxTexture, "slips")
	eq(a.modulate_color, red, "the tint is the style's modulate colour")
	check(a != b, "each call gives a new style, so a caller may change its margins")
	check(a.texture == b.texture, "but the picture is made once")
	a.content_margin_left = 40.0
	near(b.content_margin_left, 9.0, 0.001, "changing one leaves the other alone")
	eq(Frames.box("slip").modulate_color, Color.WHITE, "and the tint is not kept")


func test_unknown_frame_gives_null_and_no_error() -> void:
	Frames.forget()
	eq(Frames.box("no_such_frame"), null, "an unknown name gives no style box")
	eq(Frames.box("no_such_frame", Color.RED), null, "with a tint too")
	eq(Frames.box(""), null, "an empty name")
	check(not Frames.has("no_such_frame"), "has says no")
	check(not Frames.has(""), "has says no to an empty name")
	eq(Frames.info("no_such_frame"), {}, "no info")
	# the test runner fails the case if any error was logged while it ran


func test_a_missing_picture_or_a_missing_or_broken_list_is_not_an_error() -> void:
	var path := "user://frames_test.json"
	# a frame whose picture is not there, a frame with no picture named, and one that is fine
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"ghost": {"file": "res://assets/ui/theme/no_such_picture.png", "margin": [8, 8, 8, 8], "content": [4, 4, 4, 4], "expand": [0, 0, 0, 0], "stretch": ["stretch", "stretch"]},
		"nameless": {"margin": [8, 8, 8, 8]},
		"real": {"file": "res://assets/ui/theme/panel.png", "margin": [28, 26, 28, 34], "content": [12, 10, 12, 10]},
	}))
	f.close()
	Frames.path = path
	Frames.forget()
	eq(Frames.box("ghost"), null, "a frame whose picture is missing gives no style box")
	check(not Frames.has("ghost"), "and has says no")
	eq(Frames.box("nameless"), null, "a frame with no picture named")
	var real = Frames.box("real", Color.RED)
	check(real is StyleBoxTexture, "a frame with only a file and the margins still works")
	if real is StyleBoxTexture:
		near(real.expand_margin_left, 0.0, 0.001, "no shadow when none is listed")
		eq(real.modulate_color, Color.RED, "tinted")
	# a list that is not JSON, then no list at all
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	Frames.forget()
	eq(Frames.box("panel"), null, "a broken list gives nothing")
	eq(Frames.names(), [], "and no names")
	Frames.path = "user://frames_that_was_never_written.json"
	Frames.forget()
	eq(Frames.box("panel"), null, "a missing list gives nothing")
	check(not Frames.has("panel"), "has says no")
	Frames.path = Frames.DEFAULT_PATH
	Frames.forget()
	check(Frames.has("panel"), "and the real list is read again")


func test_has_and_names() -> void:
	Frames.forget()
	var t := _table()
	for name in t:
		check(Frames.has(name), "has(%s)" % name)
	eq(Frames.names().size(), t.size(), "names() lists every frame")
	check("panel" in Frames.names(), "names() has panel")
	eq(String(Frames.info("panel").get("file", "")), "res://assets/ui/theme/panel.png", "info has the file")
	var info := Frames.info("panel")
	info["file"] = "changed"
	eq(String(Frames.info("panel").get("file", "")), "res://assets/ui/theme/panel.png", "info is a copy")


func test_avg_and_ink_come_from_frames_json() -> void:
	Frames.forget()
	eq(Frames.avg("panel").to_html(false), String(Frames.info("panel").avg).trim_prefix("#"), "avg is the colour frames.json states")
	eq(Frames.ink("panel").to_html(false), "ece6d8", "the ink on a board is the HUD's ink")
	eq(Frames.ink("button_primary").to_html(false), "1a1508", "and on a gold button the dark one")
	eq(Frames.avg("no_such_frame"), Color(0, 0, 0, 0), "an unknown frame has no average")
	eq(Frames.ink("no_such_frame"), Color.WHITE, "and no ink")


func test_the_middle_of_a_dark_frame_keeps_the_ink_readable() -> void:
	var t := _table()
	for name in DARK:
		check(t.has(name), "%s is listed" % name)
		if not t.has(name):
			continue
		var avg := _middle_average(t[name])
		check(avg.a > 0.98, "%s: the middle is opaque" % name)
		for ink in [INK, INK2, INK3]:
			var c := _contrast(ink, avg)
			check(c >= 4.5, "%s: %s on its middle %s reads %.2f:1" % [name, ink.to_html(false), avg.to_html(false), c])
		eq(avg.to_html(false), String(t[name].avg).trim_prefix("#"), "%s: frames.json states the average colour of the picture" % name)


func test_the_light_ink_reads_on_buttons_and_the_dark_ink_on_the_pale_ones() -> void:
	var t := _table()
	for name in BUTTONS:
		var avg := _middle_average(t[name])
		if name.begins_with("button_primary"):
			check(_contrast(ACCENT_INK, avg) >= 4.5, "%s: the dark ink reads on %s (%.2f:1)" % [name, avg.to_html(false), _contrast(ACCENT_INK, avg)])
		elif name == "button_off":
			check(_contrast(INK, avg) >= 4.5, "%s: the ink reads on %s" % [name, avg.to_html(false)])
		else:
			check(_contrast(INK, avg) >= 4.5 and _contrast(INK2, avg) >= 4.5, "%s: INK and INK2 read on %s" % [name, avg.to_html(false)])
	for name in ["paper", "slip", "pill"]:
		var avg := _middle_average(t[name])
		check(_contrast(ACCENT_INK, avg) >= 4.5, "%s: the dark ink reads on %s" % [name, avg.to_html(false)])
	check(_contrast(PAPER_INK, _middle_average(t["paper"])) >= 4.5, "paper: the pen ink reads")
	var chip := _middle_average(t["chip"])
	check(_contrast(INK, chip) >= 4.5, "chip: the key's letter reads")


func test_a_tinted_slip_keeps_dark_text_readable() -> void:
	# the HUD tints a slip with the colour of its level (light: half the way to white)
	var paper := _middle_average(_table()["slip"])
	for level in [Color("#e0584a"), Color("#e8953a"), Color("#7fa6c9")]:
		var tint := Color.WHITE.lerp(level, 0.5)
		var shown := Color(paper.r * tint.r, paper.g * tint.g, paper.b * tint.b)
		check(_contrast(ACCENT_INK, shown) >= 4.5, "slip tinted %s: dark text on %s reads %.2f:1" % [level.to_html(false), shown.to_html(false), _contrast(ACCENT_INK, shown)])
	# and the full colour of the worst of them still does
	var full := Color("#e0584a")
	var worst := Color(paper.r * full.r, paper.g * full.g, paper.b * full.b)
	check(_contrast(ACCENT_INK, worst) >= 4.5, "slip tinted with the full danger colour: %.2f:1" % _contrast(ACCENT_INK, worst))
