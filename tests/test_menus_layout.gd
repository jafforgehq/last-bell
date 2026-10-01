extends "res://tests/case.gd"
## The menu screens at 700, 980, 1280 and 1920 wide: each builds without an error, sits inside
## the window, has no control on top of another, can be reached with the keyboard, reads at
## 4.5:1 or better and closes with Esc. A screen taller than a short window scrolls, and the
## scroll follows the keyboard.

const Fakes := preload("res://tests/menu_fakes.gd")
const HudKit := preload("res://tests/hud_kit.gd")
const TextTests := preload("res://tests/test_hud_text.gd")
const Buses := preload("res://scripts/audio/buses.gd")

const SIZES := [Vector2i(700, 560), Vector2i(980, 700), Vector2i(1280, 800), Vector2i(1920, 1080)]
## The screens a shell opens by name.
const SCREENS := ["pause", "settings", "new", "load", "credits", "confirm", "orientation"]


func _inside(r: Rect2, bounds: Rect2, slack: float = 0.75) -> bool:
	return r.position.x >= bounds.position.x - slack and r.position.y >= bounds.position.y - slack and r.end.x <= bounds.end.x + slack and r.end.y <= bounds.end.y + slack


## What the player can press, slide or type in, under `node` and on screen.
func _interactive(node: Node, out: Array = []) -> Array:
	if (node is BaseButton or node is Slider or node is LineEdit) and node.is_visible_in_tree():
		out.append(node)
	for c in node.get_children():
		_interactive(c, out)
	return out


## The colour behind a label: the flat boxes of the panels and buttons it sits in, over `ground`.
## null when it sits in something that is not a flat box (a picture frame: the text of those is
## judged by whoever made the frame) or in no box at all (the logo, on the world).
func _backdrop(n: Node, ground: Color):
	var chain: Array = []
	var p := n.get_parent()
	var stop: Node = Engine.get_main_loop().root
	while p != null and p != stop:
		var box = null
		if p is PanelContainer or p is Panel:
			box = p.get_theme_stylebox("panel")
		elif p is Button:
			box = p.get_theme_stylebox("disabled") if p.disabled else p.get_theme_stylebox("normal")
		if box != null:
			if not (box is StyleBoxFlat):
				return null
			# a ring (no centre drawn) adds nothing behind the words
			if box.draw_center:
				chain.append(box.bg_color)
		p = p.get_parent()
	if chain.is_empty():
		return null
	chain.reverse()
	var c := ground
	for bg in chain:
		c = TextTests.over(bg, c)
	return c


func _hard_to_read(node: Node, ground: Color, out: Array = []) -> Array:
	if node is Label and node.text != "" and node.is_visible_in_tree():
		var bg = _backdrop(node, ground)
		if bg != null:
			var ratio := TextTests.contrast(TextTests.over(node.get_theme_color("font_color"), bg), bg)
			if ratio < TextTests.AA:
				out.append("'%s' is %.2f:1" % [str(node.text).left(30), ratio])
	if node is Button and node.text != "" and node.is_visible_in_tree():
		var box = node.get_theme_stylebox("disabled") if node.disabled else node.get_theme_stylebox("normal")
		if box is StyleBoxFlat:
			var bg := TextTests.over(box.bg_color, ground)
			var word: Color = node.get_theme_color("font_disabled_color" if node.disabled else "font_color")
			var ratio := TextTests.contrast(TextTests.over(word, bg), bg)
			if ratio < TextTests.AA:
				out.append("the button '%s' is %.2f:1" % [str(node.text).left(30), ratio])
	for c in node.get_children():
		_hard_to_read(c, ground, out)
	return out


## Everything that has to hold for a screen that is up in a window of this size.
func _check_screen(ctx: Dictionary, screen_name: String, screen, size: Vector2i) -> void:
	var label := "%s at %dx%d" % [screen_name, size.x, size.y]
	await HudKit.settle()
	await HudKit.settle()
	var window := Rect2(Vector2.ZERO, Vector2(size))
	check(_inside(screen.panel.get_global_rect(), window), "%s: the panel %s is inside the window" % [label, str(screen.panel.get_global_rect())])
	var needs_scroll: bool = screen.body.get_combined_minimum_size().y > screen.scroll.size.y + 0.5
	var named := {}
	var reachable_inside_scroll: Array = []
	for c in _interactive(screen):
		check(c.focus_mode == Control.FOCUS_ALL, "%s: %s can be reached by the keyboard" % [label, c.name])
		if needs_scroll and screen.body.is_ancestor_of(c):
			reachable_inside_scroll.append(c)
			continue
		var r: Rect2 = c.get_global_rect()
		check(_inside(r, window), "%s: %s %s is inside the window" % [label, c.name, str(r)])
		named["%s%d" % [c.name, c.get_instance_id() % 10007]] = r
	var tangled := HudKit.overlaps(named)
	check(tangled.is_empty(), "%s: controls on top of each other: %s" % [label, str(tangled)])
	check(screen.is_ancestor_of(Fakes.focused()), "%s: the keyboard is in the screen" % label)
	var bad := _hard_to_read(screen, Color.WHITE)
	check(bad.is_empty(), "%s: hard to read: %s" % [label, str(bad)])
	# the head and the foot are never in the scrolling part
	check(_inside(screen.title_label.get_global_rect(), window), "%s: the heading is inside the window" % label)
	check(_inside(screen.foot.get_global_rect(), window), "%s: the buttons at the foot are inside the window" % label)
	# a screen that scrolls follows the keyboard
	if needs_scroll and not reachable_inside_scroll.is_empty():
		var last: Control = reachable_inside_scroll.back()
		last.grab_focus()
		await HudKit.settle()
		check(_inside(last.get_global_rect(), screen.scroll.get_global_rect(), 2.0), "%s: the scroll follows the keyboard to %s" % [label, last.name])
	# Esc closes it
	Fakes.key(KEY_ESCAPE)
	await HudKit.settle()
	check(ctx.shell.kinds().is_empty(), "%s: Esc closes it" % label)


func test_every_screen_fits_every_window() -> void:
	for size in SIZES:
		var ctx := Fakes.build(size.x, size.y)
		# something in the load list to show: a good save and a damaged one
		Fakes.write_save(ctx.paths[0], 12, 21.5, 2, 1)
		Fakes.write_text(ctx.paths[1], "{ not a save")
		ctx.main.sim = ctx.sim
		for screen_name in SCREENS:
			var screen = ctx.shell.open_pause() if screen_name == "pause" else ctx.shell.open_named(screen_name)
			check(screen != null, "%s opens" % screen_name)
			if screen == null:
				continue
			await _check_screen(ctx, screen_name, screen, size)
		Fakes.free_all(ctx)
		Buses.apply_all()


func test_a_screen_follows_the_window_when_it_is_resized() -> void:
	var ctx := Fakes.build(1920, 1080)
	var screen = ctx.shell.open_settings()
	await HudKit.settle()
	await HudKit.settle()
	var wide: Rect2 = screen.panel.get_global_rect()
	for size in [Vector2i(980, 700), Vector2i(700, 560), Vector2i(1280, 800)]:
		HudKit.resize(ctx, size.x, size.y)
		await HudKit.settle()
		await HudKit.settle()
		var window := Rect2(Vector2.ZERO, Vector2(size))
		check(_inside(screen.panel.get_global_rect(), window), "%dx%d: the panel %s is inside after the resize" % [size.x, size.y, str(screen.panel.get_global_rect())])
		check(_inside(screen.foot.get_global_rect(), window), "%dx%d: and so are its buttons" % [size.x, size.y])
		var centre: Vector2 = screen.panel.get_global_rect().get_center()
		check(absf(centre.x - size.x / 2.0) < 1.5 and absf(centre.y - size.y / 2.0) < 1.5, "%dx%d: and it is still in the middle: %s" % [size.x, size.y, str(centre)])
	check(wide.size.x >= 560.0, "in the wide window it had its full width: %s" % str(wide.size))
	Fakes.free_all(ctx)
	Buses.apply_all()


func test_settings_fits_the_smallest_window_without_scrolling() -> void:
	var small := Fakes.build(700, 560)
	var screen = small.shell.open_settings()
	await HudKit.settle()
	await HudKit.settle()
	check(screen.body.get_combined_minimum_size().y <= screen.scroll.size.y + 0.5, "nothing to scroll in 700x560 (%.0f of %.0f)" % [screen.body.get_combined_minimum_size().y, screen.scroll.size.y])
	Fakes.free_all(small)
	var tall := Fakes.build(1280, 800)
	screen = tall.shell.open_settings()
	await HudKit.settle()
	await HudKit.settle()
	eq(screen.body.get_theme_constant("separation"), 10, "in a tall window the rows have their room")
	Fakes.free_all(tall)
	Buses.apply_all()


func test_the_title_fits_every_window() -> void:
	for size in SIZES:
		var ctx := Fakes.build(size.x, size.y)
		Fakes.write_save(ctx.paths[0], 4, 8.0, 1)
		ctx.shell.show_title()
		await HudKit.settle()
		await HudKit.settle()
		var label := "the title at %dx%d" % [size.x, size.y]
		var title = ctx.shell.title
		var window := Rect2(Vector2.ZERO, Vector2(size))
		check(_inside(title.scroll.get_global_rect(), window), "%s: its column is inside the window" % label)
		var needs_scroll: bool = title.column.get_combined_minimum_size().y > title.scroll.size.y + 0.5
		check(not needs_scroll, "%s: nothing has to scroll (%.0f of %.0f)" % [label, title.column.get_combined_minimum_size().y, title.scroll.size.y])
		var named := {}
		for c in _interactive(title):
			check(c.focus_mode == Control.FOCUS_ALL, "%s: %s can be reached by the keyboard" % [label, c.name])
			check(_inside(c.get_global_rect(), window), "%s: %s is inside the window" % [label, c.name])
			named["%s%d" % [c.name, c.get_instance_id() % 10007]] = c.get_global_rect()
		eq(named.size(), 7, "%s: seven lines" % label)
		var tangled := HudKit.overlaps(named)
		check(tangled.is_empty(), "%s: lines on top of each other: %s" % [label, str(tangled)])
		var logo: Rect2 = title.logo.get_global_rect()
		var board: Rect2 = title.board.get_global_rect()
		check(not logo.intersects(board, false), "%s: the logo %s and the menu %s do not touch" % [label, str(logo), str(board)])
		check(_inside(logo, window), "%s: the logo is inside the window" % label)
		check(not title.hint.get_global_rect().intersects(board, false), "%s: the hint is clear of the menu" % label)
		check(title.is_ancestor_of(Fakes.focused()), "%s: the keyboard is on the menu" % label)
		var bad := _hard_to_read(title.board, Color.WHITE)
		check(bad.is_empty(), "%s: hard to read: %s" % [label, str(bad)])
		Fakes.free_all(ctx)
		Buses.apply_all()


func test_the_logo_does_not_move_when_a_screen_opens_over_the_title() -> void:
	for size in SIZES:
		var ctx := Fakes.build(size.x, size.y)
		ctx.shell.show_title()
		await HudKit.settle()
		await HudKit.settle()
		var before: Rect2 = ctx.shell.title.logo.get_global_rect()
		ctx.shell.open_settings()
		await HudKit.settle()
		await HudKit.settle()
		# the window is resized (or the title laid out again) while the screen is up
		ctx.shell.title._layout()
		await HudKit.settle()
		var during: Rect2 = ctx.shell.title.logo.get_global_rect()
		check(not ctx.shell.title.board.visible, "the menu has stepped aside")
		check(during.position.is_equal_approx(before.position) and during.size.is_equal_approx(before.size), "%dx%d: the logo stays put: %s then %s" % [size.x, size.y, str(before), str(during)])
		Fakes.free_all(ctx)
		Buses.apply_all()


func test_the_logo_is_big_in_a_tall_window_and_small_in_a_short_one() -> void:
	var tall := Fakes.build(1280, 800)
	tall.shell.show_title()
	await HudKit.settle()
	await HudKit.settle()
	var big: int = tall.shell.title.name_labels[0].get_theme_font_size("font_size")
	var tall_h: float = tall.shell.title.logo.size.y
	Fakes.free_all(tall)
	var short := Fakes.build(980, 600)
	short.shell.show_title()
	await HudKit.settle()
	await HudKit.settle()
	var small: int = short.shell.title.name_labels[0].get_theme_font_size("font_size")
	check(big > small, "the words are bigger in a tall window: %d against %d" % [big, small])
	check(small >= 40, "and still big in a short one: %d" % small)
	check(tall_h > short.shell.title.logo.size.y, "and the logo takes more room")
	Fakes.free_all(short)
	Buses.apply_all()


func test_nothing_under_twelve_pixels_in_the_menus() -> void:
	var ctx := Fakes.build(1280, 800)
	ctx.main.sim = ctx.sim
	ctx.shell.show_title()
	var found: Array = []
	for screen_name in SCREENS:
		var screen = ctx.shell.open_pause() if screen_name == "pause" else ctx.shell.open_named(screen_name)
		await HudKit.settle()
		_small_text(screen, found)
		Fakes.key(KEY_ESCAPE)
	_small_text(ctx.shell.title, found)
	check(found.is_empty(), "text under 12 px: %s" % str(found))
	Fakes.free_all(ctx)
	Buses.apply_all()


func _small_text(node: Node, out: Array) -> void:
	if node is Label and node.text != "":
		var px: int = node.get_theme_font_size("font_size")
		if px < 12:
			out.append("'%s' is %d px" % [str(node.text).left(24), px])
	for c in node.get_children():
		_small_text(c, out)
