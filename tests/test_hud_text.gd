extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")

## The text colours the HUD uses (the dark red DANGER is for bars and icons, not words).
const TEXT_COLORS := {"INK": Hud.INK, "INK2": Hud.INK2, "INK3": Hud.INK3, "ACCENT": Hud.ACCENT, "DANGER_TEXT": Hud.DANGER_TEXT, "WARN": Hud.WARN, "OK": Hud.OK, "INFO": Hud.INFO, "DAWN": Hud.DAWN}
## WCAG AA for normal text.
const AA := 4.5


# ------------------------------------------------------------ contrast maths --

static func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


## WCAG relative luminance of an opaque colour.
static func luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)


## WCAG contrast ratio of two opaque colours (1 to 21).
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## `c` laid over an opaque `backdrop` (what a translucent panel really looks like).
static func over(c: Color, backdrop: Color) -> Color:
	return Color(backdrop.r * (1.0 - c.a) + c.r * c.a, backdrop.g * (1.0 - c.a) + c.g * c.a, backdrop.b * (1.0 - c.a) + c.b * c.a, 1.0)


func test_the_contrast_maths_matches_known_values() -> void:
	near(contrast(Color.BLACK, Color.WHITE), 21.0, 0.001, "black on white")
	near(contrast(Color.WHITE, Color.WHITE), 1.0, 0.001, "white on white")
	# the audit's figure for the old INK3 on the old panel over a light world
	near(contrast(Color("#7c7565"), over(Color(21 / 255.0, 20 / 255.0, 17 / 255.0, 0.86), Color(190 / 255.0, 190 / 255.0, 190 / 255.0))), 3.06, 0.05, "the old grey on the old panel")


func test_the_panel_is_nearly_opaque() -> void:
	check(Hud.PANEL.a > 0.939, "the panel's alpha is %.3f" % Hud.PANEL.a)


func test_every_text_colour_reads_on_the_panel() -> void:
	# the panel as drawn, and the worst a translucent panel can be: over the brightest thing in the world
	var backdrops := {"the panel": Color(Hud.PANEL, 1.0), "over white": over(Hud.PANEL, Color.WHITE), "over light grey": over(Hud.PANEL, Color(0.75, 0.75, 0.75))}
	for name in TEXT_COLORS:
		for where in backdrops:
			var ratio := contrast(TEXT_COLORS[name], backdrops[where])
			check(ratio >= AA, "%s on %s is %.2f:1, under %.1f" % [name, where, ratio, AA])


func test_the_old_dark_red_is_not_good_enough_for_words() -> void:
	# why DANGER_TEXT exists: DANGER is fine for bars and icons (3:1) but not for text on the lit panel
	var worst := over(Hud.PANEL, Color.WHITE)
	check(contrast(Hud.DANGER, worst) < AA, "DANGER over white is %.2f:1" % contrast(Hud.DANGER, worst))
	check(contrast(Hud.DANGER, Color(Hud.PANEL, 1.0)) >= 3.0, "but still reads as a graphic")
	check(contrast(Hud.DANGER_TEXT, worst) >= AA, "DANGER_TEXT does")


func test_the_key_chips_read_on_the_gold_button_too() -> void:
	check(contrast(Hud.ACCENT_INK, Hud.ACCENT) >= AA, "dark ink on gold is %.2f:1" % contrast(Hud.ACCENT_INK, Hud.ACCENT))


func test_the_send_button_still_reads_while_it_is_off() -> void:
	# no place chosen yet: the main button is off, and its word must not vanish into its own background
	var ctx := Kit.build()
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.list = Kit.sample_sites()
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx)
	ctx.hud.open_scavenge(ctx.hud.selection)
	var send: Button = ctx.hud.scavenge_dialog.send_button
	check(send.disabled, "Send is off until a place is chosen")
	var box: StyleBox = send.get_theme_stylebox("disabled")
	var word_colour: Color = send.get_theme_color("font_disabled_color")
	# the button as drawn, over the page behind it, at the worst of the picture it is made of
	var worst := 99.0
	var behind := _backdrops(send, Color.WHITE)
	var fills: Array = Kit.fills(box)
	for i in 2:
		var bg := over(fills[i], behind[i])
		worst = minf(worst, contrast(over(word_colour, bg), bg))
	check(worst >= AA, "the disabled Send reads at %.2f:1" % worst)
	ctx.hud.scavenge_dialog.cancel()
	Kit.free_all(ctx)


## The colours behind a label, as [darkest, lightest]: the backgrounds of the panels, cards,
## buttons and bars it sits in, laid one over the next on top of `ground` (the world under the
## HUD). A frame is a picture, so it has a darkest and a lightest (see Kit.fills): text has to
## read on both.
func _backdrops(n: Node, ground: Color) -> Array:
	var chain: Array = []
	var stop: Node = Engine.get_main_loop().root
	var p := n.get_parent()
	while p != null and p != stop:
		var box = null
		if p is PanelContainer or p is Panel:
			box = p.get_theme_stylebox("panel")
		elif p is Button:
			box = p.get_theme_stylebox("disabled") if p.disabled else p.get_theme_stylebox("normal")
		elif p is ColorRect:
			chain.append([p.color, p.color])
		if box != null:
			var f: Array = Kit.fills(box)
			if f[0].a > 0.0 or f[1].a > 0.0:
				chain.append(f)
		p = p.get_parent()
	chain.reverse()
	var lo := ground
	var hi := ground
	for layer in chain:
		lo = over(layer[0], lo)
		hi = over(layer[1], hi)
	return [lo, hi]


## The worst contrast of `color` on what is behind `node` (see _backdrops).
func _worst_contrast(node: Node, color: Color, ground: Color) -> float:
	var worst := 99.0
	for bg in _backdrops(node, ground):
		worst = minf(worst, contrast(over(color, bg), bg))
	return worst


func _hard_to_read(node: Node, ground: Color, out: Array = []) -> Array:
	if node is Label and node.text != "":
		var ratio := _worst_contrast(node, node.get_theme_color("font_color"), ground)
		if ratio < AA:
			out.append("'%s' is %.2f:1" % [str(node.text).left(30), ratio])
	for c in node.get_children():
		_hard_to_read(c, ground, out)
	return out


func test_every_label_reads_on_the_background_it_sits_on() -> void:
	# with the frames the theme has (the pictures of the noticeboard)
	await _every_label_reads(true)


func test_every_label_reads_on_the_flat_boards_too() -> void:
	# and with no frames at all: the flat chalkboards and paper every surface falls back on
	await _every_label_reads(false)


## The whole tree in a busy state, over the brightest ground: the stores, the clock, the alerts,
## the cards, the help, the toast, the dialog (four places) and the end screen.
func _every_label_reads(frames: bool) -> void:
	Hud.use_frames = frames
	var look := "frames" if frames else "flat"
	var ground := Color.WHITE
	var ctx := Kit.build(1280, 800)
	var ana = Kit.person(ctx, "ana")
	ana.hunger_h = 40.0
	ana.wounds = 2
	ana.bleeding = 4.0
	ctx.sim.medical.treat[ana.id] = true
	ctx.sim.medical.sendout[ana.id] = true
	ctx.sim.medical.stage[ana.id] = "feverish"
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.list = Kit.sample_sites(true)
	ctx.sim.supplies.days = {"food": 0.5, "water": 2.0}
	Kit.person(ctx, "walt").dead = true
	Kit.person(ctx, "walt").turned = true
	Kit.person(ctx, "dez").away = {"kind": "party", "site": "pharmacy"}
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
	ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
	ctx.sim.alert("a3", "info", "The bell has rung", "Everyone is heading to their posts", null, 60.0)
	ctx.sim.workshop.at_bench[ana.id] = true
	ctx.sim.bell_rung = true
	ctx.hud.help.visible = true
	Kit.select(ctx, ana)
	Kit.update(ctx, 0)
	ctx.hud.toast("Nothing is damaged", "warn")
	ctx.hud.show_banner("Dusk falls", "The bell has rung")
	eq(_hard_to_read(ctx.hud, ground), [], "%s: the HUD" % look)
	ctx.hud.open_scavenge(ctx.hud.selection)
	ctx.hud.scavenge_dialog.choose_site("houses")
	eq(_hard_to_read(ctx.hud.scavenge_dialog, ground), [], "%s: the scavenging dialog" % look)
	ctx.hud.scavenge_dialog.cancel()
	ctx.sim.over = "victory"
	Kit.update(ctx, 0)
	eq(_hard_to_read(ctx.hud.game_over, ground), [], "%s: the end screen" % look)
	Kit.free_all(ctx)
	Hud.use_frames = true


func test_the_label_check_does_catch_dim_text() -> void:
	# the walk is only worth something if it sees grey text on a panel that is too close in tone
	var ctx := Kit.build()
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#8a8470")
	panel.add_theme_stylebox_override("panel", box)
	var l := Label.new()
	l.text = "dim"
	l.add_theme_color_override("font_color", Hud.INK3)
	panel.add_child(l)
	ctx.hud.add_child(panel)
	eq(_hard_to_read(panel, Color.WHITE).size(), 1, "grey on grey is reported")
	panel.free()
	Kit.free_all(ctx)


# ------------------------------------------------------------------ 12 px floor --

func _small_text(node: Node, out: Array = []) -> Array:
	if node is Label or node is Button:
		var size: int = node.get_theme_font_size("font_size")
		if size < Fonts.MIN_PX:
			out.append("%s '%s' is %d px" % [node.get_class(), str(node.get("text")), size])
	for c in node.get_children():
		_small_text(c, out)
	return out


## The HUD with everything on it that has text: a person with every button, alerts, the help, a toast.
func _busy(width: int, height: int) -> Dictionary:
	var ctx := Kit.build(width, height)
	var ana = Kit.person(ctx, "ana")
	ctx.sim.medical.treat[ana.id] = true
	ctx.sim.medical.sendout[ana.id] = true
	ctx.sim.medical.stage[ana.id] = "feverish"
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.list = Kit.sample_sites()
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
	ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
	ctx.hud.help.visible = true
	Kit.select(ctx, ana)
	Kit.update(ctx, 0)
	if ctx.hud.has_method("toast"):
		ctx.hud.toast("Nothing is damaged", "warn")
	return ctx


func test_nothing_in_the_hud_is_under_twelve_pixels() -> void:
	eq(Fonts.MIN_PX, 12, "the floor")
	for size in [[1280, 800], [980, 700], [700, 700], [700, 560]]:
		var ctx := _busy(size[0], size[1])
		eq(_small_text(ctx.hud), [], "%d x %d" % [size[0], size[1]])
		Kit.free_all(ctx)


func test_the_floor_check_does_catch_a_small_label_or_button() -> void:
	# the walk above is only worth something if it sees a 9 px label and a 10 px button
	var ctx := Kit.build()
	var small := Label.new()
	small.text = "tiny"
	small.add_theme_font_size_override("font_size", 9)
	ctx.hud.add_child(small)
	var small_button := Button.new()
	small_button.text = "small"
	small_button.add_theme_font_size_override("font_size", 10)
	ctx.hud.inspect.add_child(small_button)
	var found := _small_text(ctx.hud)
	eq(found.size(), 2, "both are reported: %s" % str(found))
	small.free()
	small_button.free()
	Kit.free_all(ctx)


func test_nothing_under_twelve_for_a_wall_a_walker_and_the_dead() -> void:
	var ctx := Kit.build()
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
	Kit.update(ctx)
	eq(_small_text(ctx.hud), [], "a wall piece")
	ctx.hud.select({"kind": "zombie", "ref": ctx.sim.zombies[0]})
	Kit.update(ctx)
	eq(_small_text(ctx.hud), [], "a walker")
	var walt = Kit.person(ctx, "walt")
	walt.dead = true
	walt.turned = true
	Kit.person(ctx, "dez").away = {"kind": "party", "site": "pharmacy"}
	Kit.select(ctx, walt)
	Kit.update(ctx)
	eq(_small_text(ctx.hud), [], "the dead and the away")
	Kit.free_all(ctx)


func test_nothing_under_twelve_in_the_scavenging_dialog() -> void:
	for size in [[1280, 800], [700, 700]]:
		var ctx := Kit.build(size[0], size[1])
		ctx.sim.scavenge.can = true
		ctx.sim.scavenge.list = Kit.sample_sites()
		Kit.select(ctx, Kit.person(ctx, "ana"))
		Kit.update(ctx)
		ctx.hud.open_scavenge(ctx.hud.selection)
		var d = ctx.hud.scavenge_dialog
		d.choose_site("houses")
		d.toggle_second(Kit.person(ctx, "dez"))
		eq(_small_text(d), [], "the dialog at %d px" % size[0])
		ctx.sim.scavenge.send_ok = false
		d.send()
		check(d.error_label.visible, "the error line is up")
		eq(_small_text(d), [], "with its error line")
		d.cancel()
		ctx.sim.scavenge.can = false
		ctx.sim.scavenge.reason = "Nobody goes out after dark."
		ctx.hud.open_scavenge(ctx.hud.selection)
		eq(_small_text(ctx.hud.scavenge_dialog), [], "and the one that says why not")
		Kit.free_all(ctx)


func test_nothing_under_twelve_on_the_game_over_screens() -> void:
	for result in ["defeat", "victory"]:
		var ctx := Kit.build()
		Kit.person(ctx, "walt").dead = true
		Kit.person(ctx, "walt").turned = true
		Kit.person(ctx, "dez").dead = true
		ctx.hud.save_paths = []
		ctx.sim.over = result
		Kit.update(ctx)
		check(ctx.hud.game_over != null, "%s: the screen is up" % result)
		eq(_small_text(ctx.hud.game_over), [], result)
		Kit.free_all(ctx)


func test_the_names_in_the_world_are_twelve_pixels() -> void:
	check(OverlayNode.NAME_PX >= Fonts.MIN_PX, "world labels are %d px" % OverlayNode.NAME_PX)
	check(OverlayNode.FIELD_PX >= Fonts.MIN_PX, "and so are the numbers and words of the night tools: %d px" % OverlayNode.FIELD_PX)


## The HUD with the night tools showing: the forecast under the clock, the fields-of-fire legend,
## the job tag in a person's panel, and alerts for the alarm and the forecast.
func _night_tools(width: int, height: int) -> Dictionary:
	var ctx := Kit.build(width, height)
	var dez = Kit.person(ctx, "dez")
	ctx.sim.tactics.told = Kit.forecast({"brutes": 2, "heading": "north and west"})
	ctx.sim.alert("lure", "info", "Alarm at the school bus", "The dead are drawn to it for 3 hours", null, 60.0)
	ctx.sim.alert("forecast", "info", "Tonight's forecast", "About 55 tonight, mostly from the north and west", null, 60.0)
	ctx.sim.alert("brute", "danger", "A brute is coming", "From the north. It tears walls down.", null, 60.0)
	ctx.hud.set_fields(true)
	Kit.select(ctx, dez)
	Kit.update(ctx, 0)
	return ctx


func test_nothing_in_the_night_tools_is_under_twelve_pixels() -> void:
	for size in [[1280, 800], [700, 700], [700, 560]]:
		var ctx := _night_tools(size[0], size[1])
		eq(_small_text(ctx.hud), [], "a person, at %d x %d" % [size[0], size[1]])
		ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
		Kit.update(ctx)
		eq(_small_text(ctx.hud), [], "a wall section, at %d x %d" % [size[0], size[1]])
		Kit.free_all(ctx)


func test_the_night_tools_read_on_the_background_they_sit_on() -> void:
	var ground := Color.WHITE
	var ctx := _night_tools(1280, 800)
	check(ctx.hud.forecast_label.visible and ctx.hud.fields_legend.visible and ctx.hud.inspect_refs.job_tag.visible, "all three are up")
	eq(_hard_to_read(ctx.hud, ground), [], "the forecast, the legend, the tag and the alerts")
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
	Kit.update(ctx)
	eq(_hard_to_read(ctx.hud, ground), [], "and the Lure button")
	eq(_dark_red_words(ctx.hud), [], "no word in the dark red")
	Kit.free_all(ctx)


func test_a_label_asked_for_a_smaller_size_gets_the_floor() -> void:
	var ctx := Kit.build()
	var l: Label = ctx.hud._label("tiny", Fonts.sans(400), 9, Hud.INK)
	eq(l.get_theme_font_size("font_size"), Fonts.MIN_PX, "raised to the floor")
	l.free()
	Kit.free_all(ctx)


func test_the_key_chips_on_the_buttons_are_twelve_pixels() -> void:
	var ctx := _busy(1280, 800)
	var seen := 0
	for id in ["draft", "post", "repair", "focus", "job_builders", "job_bench", "treat", "sendout", "scavenge"]:
		var b: Button = Kit.gizmo(ctx, id)
		for l in b.find_children("*", "Label", true, false):
			check(l.get_theme_font_size("font_size") >= 12, "%s: '%s'" % [id, l.text])
			seen += 1
	check(seen >= 18, "each button has its name and its key: %d labels" % seen)
	Kit.free_all(ctx)


# --------------------------------------------------------- colours of the words --

func _dark_red_words(node: Node, out: Array = []) -> Array:
	if node is Label and node.get_theme_color("font_color") == Hud.DANGER:
		out.append("'%s'" % node.text)
	for c in node.get_children():
		_dark_red_words(c, out)
	return out


func test_no_word_is_set_in_the_dark_red() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	ana.hunger_h = 40.0
	ana.thirst_h = 30.0
	ana.wounds = 2
	ana.bleeding = 4.0
	ctx.sim.supplies.days = {"food": 0.5, "water": 0.2}
	Kit.person(ctx, "walt").turned = true
	Kit.person(ctx, "walt").dead = true
	Kit.select(ctx, ana)
	Kit.update(ctx)
	eq(_dark_red_words(ctx.hud), [], "stores, needs, wounds and cards")
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.send_ok = false
	ctx.sim.scavenge.list = Kit.sample_sites()
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	d.choose_site("houses")
	d.send()
	eq(_dark_red_words(d), [], "the dialog's error line")
	d.cancel()
	ctx.sim.over = "defeat"
	Kit.update(ctx)
	eq(_dark_red_words(ctx.hud.game_over), [], "the game over screen")
	Kit.free_all(ctx)
