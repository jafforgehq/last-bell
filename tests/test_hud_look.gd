extends "res://tests/case.gd"
## Round 3, the schoolyard-noticeboard look of the HUD: the paper of the slips and the dialogs and
## its dark ink, the frames where there are some and the flat chalkboards where there are not, the
## hall-pass cards, the brass bell on the clock, the report card and the scavenging dialog with
## any number of places. (The text colours on every surface are in test_hud_text.gd, the layout in
## test_hud_layout.gd.)

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Dialog := preload("res://scripts/ui/scavenge_dialog.gd")
const TextTests := preload("res://tests/test_hud_text.gd")

const SAVE := "user://hud_look_test_save.json"
const SIZES := [[1280, 800], [980, 700], [700, 700]]


## A HUD with something on every surface: alerts of each level, a selected person with their
## buttons, the help, the toast, the legend.
func _busy(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := Kit.build(width, height)
	var ana = Kit.person(ctx, "ana")
	ctx.sim.medical.treat[ana.id] = true
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.list = Kit.sample_sites()
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
	ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
	ctx.sim.alert("a3", "info", "The bell has rung", "Everyone is heading to their posts", null, 60.0)
	ctx.hud.help.visible = true
	ctx.hud.set_fields(true)
	Kit.select(ctx, ana)
	Kit.update(ctx, 0)
	ctx.hud.toast("Nothing is damaged", "warn")
	return ctx


## The surfaces of a busy HUD as [name, the frame it asks for, its style box].
func _surfaces(ctx: Dictionary) -> Array:
	var h = ctx.hud
	var out: Array = [
		["stores", "panel", h.res_panel.get_theme_stylebox("panel")],
		["legend", "panel", h.fields_legend.get_theme_stylebox("panel")],
		["clock", "clock", h.clock.get_theme_stylebox("panel")],
		["selection", "panel", h.inspect.get_theme_stylebox("panel")],
		["help", "panel", h.help.get_theme_stylebox("panel")],
		["hint", "panel", h.hint.get_theme_stylebox("panel")],
		["speed", "panel", h.speed_panel.get_theme_stylebox("panel")],
		["toast", "toast", h.toast_panel.get_theme_stylebox("panel")],
		["card", "card", h.cards[0].card.get_theme_stylebox("panel")],
		["tooltip", "tooltip", h.theme.get_stylebox("panel", "TooltipPanel")],
	]
	for id in h.alert_items:
		var it: Dictionary = h.alert_items[id]
		if it.panel != null:
			out.append(["slip %s" % id, "slip", it.panel.get_theme_stylebox("panel")])
	for b in h.gizmos.get_children():
		if b is Button and b.has_meta("id") and not b.get_meta("on"):
			out.append(["button %s" % b.get_meta("id"), "button", b.get_theme_stylebox("normal")])
	return out


## Whether a style box is what a surface wears: the picture of the frame `kind` when the theme has
## that frame, else the flat board.
func _wears(sb: StyleBox, kind: String) -> bool:
	if Hud.has_frame(kind):
		return sb is StyleBoxTexture
	return sb is StyleBoxFlat


# ------------------------------------------------------------- paper and ink --

func test_the_paper_inks_read_on_the_paper_and_on_every_slip() -> void:
	var papers := {"paper": Hud.PAPER}
	for level in Hud.SLIP:
		papers["%s slip" % level] = Hud.SLIP[level]
	var inks := {"PAPER_INK": Hud.PAPER_INK, "PAPER_INK2": Hud.PAPER_INK2, "PAPER_INK3": Hud.PAPER_INK3}
	for where in papers:
		for ink in inks:
			var ratio := TextTests.contrast(inks[ink], papers[where])
			check(ratio >= TextTests.AA, "%s on the %s is %.2f:1" % [ink, where, ratio])
	for level in Hud.SLIP_MARK:
		var ratio := TextTests.contrast(Hud.SLIP_MARK[level], Hud.SLIP[level])
		check(ratio >= 3.0, "the %s mark on its slip is %.2f:1: it reads as a graphic" % [level, ratio])


func test_a_slip_is_pale_paper_with_dark_ink() -> void:
	var ctx := _busy()
	var seen := 0
	for id in ["a1", "a2", "a3"]:
		var it: Dictionary = ctx.hud.alert_items[id]
		var box: StyleBox = it.panel.get_theme_stylebox("panel")
		var look: Array = Kit.fills(box)
		if look[1].a > 0.0:
			check(look[0].v > 0.55, "%s: pale all through: %s" % [id, str(look)])
		eq(it.title.get_theme_color("font_color"), Hud.PAPER_INK, "%s: the headline is in dark ink" % id)
		eq(it.subl.get_theme_color("font_color"), Hud.PAPER_INK2, "%s: and the line under it" % id)
		seen += 1
	eq(seen, 3, "all three slips")
	Kit.free_all(ctx)


func test_the_levels_differ_by_more_than_colour() -> void:
	# the icon is of what the alert is about (its shape), the edge bar is drawn in the level's dark
	# colour; and a slip of each level is its own paper
	var ctx := _busy()
	var papers := {}
	for id in ["a1", "a2", "a3"]:
		var it: Dictionary = ctx.hud.alert_items[id]
		check(not papers.has(it.level), "one slip a level")
		papers[it.level] = Kit.fills(it.panel.get_theme_stylebox("panel"))
		eq(it.icon.modulate, Hud.SLIP_MARK[it.level], "%s: the icon wears the level's dark colour" % id)
		check(it.icon.texture != null, "%s: and has a shape" % id)
	if papers.danger[1].a > 0.0:
		check(papers.danger != papers.warn and papers.warn != papers.info, "and the papers are not the same: %s" % str(papers))
	Kit.free_all(ctx)


func test_a_slip_turns_lighter_under_the_mouse_and_back() -> void:
	var ctx := _busy()
	var it: Dictionary = ctx.hud.alert_items["a2"]
	var p: PanelContainer = it.panel
	var calm: Array = Kit.fills(p.get_theme_stylebox("panel"))
	p.mouse_entered.emit()
	var hot: Array = Kit.fills(p.get_theme_stylebox("panel"))
	if calm[1].a > 0.0:
		check(hot[1].get_luminance() > calm[1].get_luminance(), "lighter while the mouse is on it: %s then %s" % [str(calm), str(hot)])
	p.mouse_exited.emit()
	eq(Kit.fills(p.get_theme_stylebox("panel")), calm, "and as it was after")
	Kit.free_all(ctx)


# ------------------------------------------------------------ frames and flat --

func test_a_style_with_a_kind_is_flat_when_the_frame_is_missing() -> void:
	var ctx := Kit.build()
	var h = ctx.hud
	check(h._style(Hud.PANEL, 6, Hud.LINE, true) is StyleBoxFlat, "without a kind it is always the flat style")
	var odd = h._style(Hud.PANEL, 6, Hud.LINE, true, "no-such-frame")
	check(odd is StyleBoxFlat and odd.bg_color == Hud.PANEL, "a frame that does not exist: the flat style of today")
	check(Hud.frame("no-such-frame") == null and not Hud.has_frame("no-such-frame"), "and the frame helper says so")
	var framed = h._style(Hud.PANEL, 6, Hud.LINE, true, "panel")
	if Hud.has_frame("panel"):
		check(framed is StyleBoxTexture, "a frame that is there is used")
	else:
		check(framed is StyleBoxFlat, "no panel frame yet: flat")
	Hud.use_frames = false
	check(h._style(Hud.PANEL, 6, Hud.LINE, true, "panel") is StyleBoxFlat, "and switched off, flat whatever is there")
	Hud.use_frames = true
	Kit.free_all(ctx)


func test_with_the_frames_off_every_surface_is_flat_and_the_dialogs_too() -> void:
	Hud.use_frames = false
	var ctx := _busy()
	for s in _surfaces(ctx):
		check(s[2] is StyleBoxFlat, "%s is flat: %s" % [s[0], str(s[2])])
	ctx.hud.open_scavenge(ctx.hud.selection)
	check(ctx.hud.scavenge_dialog.panel.get_theme_stylebox("panel") is StyleBoxFlat, "the dialog's page is flat paper")
	ctx.hud.scavenge_dialog.cancel()
	ctx.sim.over = "defeat"
	Kit.update(ctx)
	check(ctx.hud.game_over.panel.get_theme_stylebox("panel") is StyleBoxFlat, "so is the report card's")
	Hud.use_frames = true
	Kit.free_all(ctx)


func test_surfaces_wear_the_frames_that_exist_and_are_flat_where_there_is_none() -> void:
	var ctx := _busy()
	for s in _surfaces(ctx):
		if Hud.has_frame(s[1]):
			check(s[2] is StyleBoxTexture, "%s wears the %s frame" % [s[0], s[1]])
		else:
			check(s[2] is StyleBoxFlat, "there is no %s frame: %s is flat" % [s[1], s[0]])
	ctx.hud.open_scavenge(ctx.hud.selection)
	var page: StyleBox = ctx.hud.scavenge_dialog.panel.get_theme_stylebox("panel")
	if Hud.has_frame("paper"):
		check(page is StyleBoxTexture, "the dialog's page is the paper frame")
	else:
		check(page is StyleBoxFlat, "no paper frame: flat paper")
	ctx.hud.scavenge_dialog.cancel()
	Kit.free_all(ctx)


func test_the_theme_has_every_frame_the_hud_wears() -> void:
	# the frames are made by another hand (tools/make_ui_theme.py): if one goes missing the HUD falls
	# back to its flat board for it, and this says which
	var missing: Array = []
	for kind in Hud.FRAME_KINDS:
		if not Hud.has_frame(kind):
			missing.append(kind)
	eq(missing, [], "frames the HUD asks for that the theme does not have")


func test_the_pictures_of_the_frames_can_be_read_so_the_contrast_tests_mean_something() -> void:
	# the text tests lay each label over the pixels of the frame it sits on: if a picture could not be
	# read they would see nothing behind the words and pass for the wrong reason
	for kind in Hud.FRAME_KINDS:
		# (the groove of a meter has no text on it, and its middle is partly clear)
		if not Hud.has_frame(kind) or kind == "bar_track":
			continue
		var look: Array = Kit.fills(Hud.frame(kind))
		check(look[0].a > 0.0 and look[1].a > 0.0, "the middle of %s can be read: %s" % [kind, str(look)])
		check(look[0].get_luminance() <= look[1].get_luminance() + 0.0001, "%s: darkest first" % kind)


func test_the_dark_frames_stay_dark_and_the_paper_ones_pale() -> void:
	# what the text colours were chosen against (see test_hud_text.gd): chalk ink on the boards
	for kind in ["panel", "panel_slim", "panel_inset", "clock", "tooltip", "toast", "banner", "button", "card"]:
		if Hud.has_frame(kind):
			var look: Array = Kit.fills(Hud.frame(kind))
			check(TextTests.luminance(look[1]) < 0.06, "%s is a dark board even at its lightest: %.3f" % [kind, TextTests.luminance(look[1])])
	for kind in ["slip", "paper"]:
		if Hud.has_frame(kind):
			var look: Array = Kit.fills(Hud.frame(kind))
			check(TextTests.luminance(look[0]) > 0.5, "%s is pale paper even at its darkest: %.3f" % [kind, TextTests.luminance(look[0])])


func test_the_small_parts_wear_their_frames_and_keep_their_words() -> void:
	var ctx := _busy()
	var h = ctx.hud
	var pill: StyleBox = h.paused_pill.get_theme_stylebox("panel")
	check(_wears(pill, "pill"), "the PAUSED stamp: the pill frame, or a flat pill")
	Kit.update(ctx, 0)
	check(Kit.texts(h.paused_pill).has("PAUSED"), "and it still says so")
	var chips := 0
	for b in h.gizmos.get_children():
		if b is Button and b.has_meta("id") and not b.get_meta("on"):
			for chip in b.find_children("*", "PanelContainer", true, false):
				check(_wears(chip.get_theme_stylebox("panel"), "chip"), "the key chip of %s" % b.get_meta("id"))
				chips += 1
	check(chips >= 4, "a key chip on each button: %d" % chips)
	# the groove of the health meter
	var bar = h.inspect_refs.hp
	check((bar.groove != null) == Hud.has_frame("bar_track"), "the health meter lies in a groove when there is one")
	Kit.free_all(ctx)


func test_the_announcement_hangs_on_a_sign_and_never_blocks_the_mouse() -> void:
	var ctx := Kit.build()
	var b: PanelContainer = ctx.hud.banner
	eq(b.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the sign lets clicks through, shown or not")
	var box: StyleBox = b.get_theme_stylebox("panel")
	check(_wears(box, "banner"), "on the banner frame, or flat a slate board")
	ctx.hud.show_banner("Dusk falls", "The bell has rung")
	eq(ctx.hud.banner_title.text, "DUSK FALLS", "the title is in capitals")
	eq(ctx.hud.banner_sub.text, "The bell has rung", "and the line under it")
	await Kit.settle()
	var sign := Kit.rect(b)
	check(sign.size != Vector2.ZERO and Rect2(0, 0, 1280, 800).encloses(sign), "inside the window: %s" % str(sign))
	near(sign.get_center().x, 640.0, 1.5, "in the middle")
	Kit.free_all(ctx)


func test_the_dialog_page_is_pale_in_either_look() -> void:
	for frames in [false, true]:
		Hud.use_frames = frames
		var ctx := _busy()
		ctx.hud.open_scavenge(ctx.hud.selection)
		var look: Array = Kit.fills(ctx.hud.scavenge_dialog.panel.get_theme_stylebox("panel"))
		if look[1].a > 0.0:
			check(look[0].v > 0.55, "frames %s: the page is pale paper: %s" % [frames, str(look)])
		ctx.hud.scavenge_dialog.cancel()
		Kit.free_all(ctx)
	Hud.use_frames = true


# ------------------------------------------------------------------ the clock --

func test_a_brass_bell_sits_on_the_clock_once_the_bell_has_rung() -> void:
	var ctx := Kit.build()
	ctx.sim.bell_rung = false
	Kit.update(ctx)
	check(not ctx.hud.clock_bell.visible, "no bell by day")
	await Kit.settle()
	var before := Kit.rect(ctx.hud.clock)
	ctx.sim.bell_rung = true
	ctx.sim.phase = "night"
	Kit.update(ctx)
	await Kit.settle()
	check(ctx.hud.clock_bell.visible, "the bell shows after dusk")
	eq(ctx.hud.clock_bell.texture, ctx.hud.icons["bell"], "it is the bell icon")
	eq(ctx.hud.clock_bell.modulate, Hud.BRASS, "in brass")
	var clock := Kit.rect(ctx.hud.clock)
	eq(clock.size, before.size, "it takes no room in the clock")
	var bell := Kit.rect(ctx.hud.clock_bell)
	check(bell.size != Vector2.ZERO and bell.get_center().y >= clock.position.y - 6.0 and bell.get_center().y <= clock.position.y + 6.0, "straddling the top edge: bell %s, clock %s" % [str(bell), str(clock)])
	check(bell.position.x >= clock.position.x and bell.end.x <= clock.end.x, "and above the clock, not beside it")
	check(Rect2(0, 0, 1280, 800).encloses(bell), "inside the window")
	ctx.sim.bell_rung = false
	ctx.sim.phase = "day"
	Kit.update(ctx)
	check(not ctx.hud.clock_bell.visible, "and gone at dawn")
	Kit.free_all(ctx)


func test_the_bell_does_not_cover_the_words_in_the_clock() -> void:
	for size in SIZES:
		var ctx := Kit.build(size[0], size[1])
		ctx.sim.bell_rung = true
		ctx.sim.phase = "night"
		Kit.update(ctx, 0)
		await Kit.settle()
		Kit.update(ctx, 0)
		await Kit.settle()
		var bell := Kit.rect(ctx.hud.clock_bell)
		var words := {"day": Kit.rect(ctx.hud.day_label), "pill": Kit.rect(ctx.hud.paused_pill), "chip": Kit.rect(ctx.hud.phase_chip)}
		for name in words:
			var r: Rect2 = words[name]
			if r.size != Vector2.ZERO:
				var inter := bell.intersection(r)
				check(inter.size.x <= 0.5 or inter.size.y <= 0.5, "%dpx: the bell clears the %s (%s on %s)" % [size[0], name, str(bell), str(r)])
		Kit.free_all(ctx)


# ----------------------------------------------------------------- the cards --

func test_a_card_keeps_its_size_and_its_picture_sits_inside_its_rim() -> void:
	for size in SIZES:
		var ctx := Kit.build(size[0], size[1])
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var compact: bool = size[0] < 980
		var w := 48 if compact else 60
		for c in ctx.hud.cards:
			eq(c.card.custom_minimum_size, Vector2(w, ctx.hud._card_height(w)), "%dpx: the card is as wide as it was, as tall as its badge needs" % size[0])
			if not Hud.has_frame("card"):
				eq(ctx.hud._card_height(w), w + 20, "%dpx: flat, the height it always was" % size[0])
			var card := Kit.rect(c.card)
			var pic := Kit.rect(c.pic)
			var name := Kit.rect(c.name)
			var hp := Kit.rect(c.hp_bg)
			check(card.encloses(pic) and card.encloses(name) and card.encloses(hp), "%dpx %s: picture, name and bar are inside the card" % [size[0], c.p.first])
			# (the name's box is a pixel taller than the room above the bar, as it always was: only its letters count)
			eq(Kit.overlaps({"picture": pic, "name": name, "bar": hp}, 1.5), [], "%dpx %s: and do not overlap" % [size[0], c.p.first])
			check(pic.position.x >= card.position.x + 1.0 - 0.01 and pic.position.y >= card.position.y + 1.0 - 0.01, "%dpx %s: the picture is inside the rim" % [size[0], c.p.first])
			near(pic.size.x, pic.size.y, 0.01, "%dpx: and square" % size[0])
		Kit.free_all(ctx)


func test_the_selected_card_is_the_gold_badge() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	Kit.update(ctx)
	var c := Kit.card(ctx, ana)
	var plain: StyleBox = c.card.get_theme_stylebox("panel")
	Kit.select(ctx, ana)
	Kit.update(ctx)
	var picked: StyleBox = c.card.get_theme_stylebox("panel")
	if picked is StyleBoxFlat:
		eq(picked.border_color, Hud.ACCENT, "flat: a gold edge")
		check(plain.border_color != picked.border_color, "and not on the others")
	else:
		check(picked is StyleBoxTexture and (picked.texture != plain.texture or picked.modulate_color != plain.modulate_color), "the badge of the selected one is another picture")
	Kit.free_all(ctx)


func test_the_marks_and_badges_stay_in_the_picture_whatever_the_rim() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	ana.drafted = true
	ana.target = ctx.sim.zombies[0]
	ctx.sim.medical.marks[ana.id] = [{"icon": "wound", "color": Hud.DANGER, "tip": "Bleeding"}, {"icon": "fever", "color": Hud.WARN, "tip": "Feverish"}]
	Kit.update(ctx)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	var c := Kit.card(ctx, ana)
	var pic := Kit.rect(c.pic)
	for part in ["badge", "fight", "marks_box"]:
		var r := Kit.rect(c[part])
		check(r.size != Vector2.ZERO and pic.encloses(r), "%s is on the picture: %s in %s" % [part, str(r), str(pic)])
	Kit.free_all(ctx)


# ------------------------------------------------------ the scavenging dialog --

func _four_sites(width: int, height: int) -> Dictionary:
	var ctx := Kit.build(width, height)
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.list = Kit.sample_sites(true)
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx)
	return ctx


func test_how_many_cards_go_side_by_side_follows_the_room() -> void:
	eq(Dialog.columns_for(1, 100.0), 1, "one place is one column")
	eq(Dialog.columns_for(3, 700.0), 3, "three fit in a wide page, as before")
	eq(Dialog.columns_for(3, 500.0), 1, "and stack in a narrow one, as before")
	eq(Dialog.columns_for(4, 760.0), 4, "four in a row while each keeps %d px" % int(Dialog.COL_W))
	eq(Dialog.columns_for(4, 700.0), 2, "two by two when four would be too narrow")
	eq(Dialog.columns_for(4, 360.0), 2, "...as long as two are wide enough")
	eq(Dialog.columns_for(4, 300.0), 1, "and one above the other when they are not")
	eq(Dialog.columns_for(6, 1000.0), 3, "six go three by three")
	eq(Dialog.columns_for(0, 500.0), 1, "no places: one column, nothing in it")


func test_four_places_fit_the_window_at_every_width_and_no_card_is_squeezed() -> void:
	for size in SIZES:
		var ctx := _four_sites(size[0], size[1])
		ctx.hud.open_scavenge(ctx.hud.selection)
		var d = ctx.hud.scavenge_dialog
		eq(d.site_cards.keys(), ["pharmacy", "hardware", "houses", "scrapyard"], "%dpx: four places in order" % size[0])
		d.choose_site("scrapyard")
		d.toggle_second(Kit.person(ctx, "dez"))
		await Kit.settle()
		await Kit.settle()
		var win := Rect2(0, 0, size[0], size[1])
		var named := {"panel": Kit.rect(d.panel), "send": Kit.rect(d.send_button), "cancel": Kit.rect(d.cancel_button)}
		var cards := {}
		for id in d.site_cards:
			var r := Kit.rect(d.site_cards[id].card)
			cards["card " + id] = r
			check(r.size.x >= Dialog.CARD_MIN_W - 0.5, "%dpx: %s is %d px wide, not squeezed under %d" % [size[0], id, int(r.size.x), int(Dialog.CARD_MIN_W)])
		for name in named:
			check(named[name].size != Vector2.ZERO and win.encloses(named[name].grow(-0.5)), "%dpx: %s is inside the window: %s" % [size[0], name, str(named[name])])
		eq(Kit.overlaps(cards), [], "%dpx: the cards do not overlap" % size[0])
		# the cards that the page scrolls to are the page's: each one is inside the scroll area's width
		for name in cards:
			var r: Rect2 = cards[name]
			check(r.position.x >= named.panel.position.x - 0.5 and r.end.x <= named.panel.end.x + 0.5, "%dpx: %s is inside the page's width" % [size[0], name])
		check(d.sites_box.columns in [1, 2, 4], "%dpx: %d columns: all in a row, two by two or one above the other" % [size[0], d.sites_box.columns])
		# the fourth place can be chosen and sent to
		d.send_button.pressed.emit()
		eq(ctx.sim.scavenge.sent, [{"ids": ["ana", "dez"], "site": "scrapyard"}], "%dpx: the party goes to the scrapyard" % size[0])
		Kit.free_all(ctx)


func test_four_places_go_two_by_two_in_a_medium_window() -> void:
	var ctx := _four_sites(980, 700)
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	await Kit.settle()
	await Kit.settle()
	eq(d.sites_box.columns, 2, "980 px: two columns")
	var a := Kit.rect(d.site_cards.pharmacy.card)
	var b := Kit.rect(d.site_cards.hardware.card)
	var c := Kit.rect(d.site_cards.houses.card)
	check(b.position.x > a.position.x + a.size.x * 0.5 and absf(a.position.y - b.position.y) < 1.0, "the second is beside the first")
	check(c.position.y >= a.end.y - 0.5 and absf(c.position.x - a.position.x) < 1.0, "the third is under the first")
	Kit.free_all(ctx)


func test_the_page_and_its_cards_are_dark_ink_on_light_paper() -> void:
	var ctx := _four_sites(1280, 800)
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	d.choose_site("houses")
	d.toggle_second(Kit.person(ctx, "dez"))
	var seen := 0
	for l in d.find_children("*", "Label", true, false):
		var colour: Color = l.get_theme_color("font_color")
		check(colour.get_luminance() < 0.45, "'%s' is in a dark ink, not chalk: %s" % [l.text, colour.to_html()])
		seen += 1
	check(seen > 20, "a good many labels were looked at: %d" % seen)
	ctx.hud.scavenge_dialog.cancel()
	Kit.free_all(ctx)


# ----------------------------------------------------------------- report card --

func _over(ctx: Dictionary, result: String) -> void:
	ctx.sim.over = result
	Kit.update(ctx)


func _remove_save() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _button(ctx: Dictionary, text: String) -> Button:
	for b in ctx.hud.game_over.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func test_the_end_screen_is_a_report_card_on_paper_with_ruled_lines() -> void:
	_remove_save()
	var ctx := Kit.build()
	ctx.hud.save_paths = []
	Kit.person(ctx, "walt").dead = true
	ctx.sim.kills = 12
	_over(ctx, "defeat")
	var go = ctx.hud.game_over
	var all := Kit.texts(go)
	check(all.has("REPORT CARD"), "headed REPORT CARD: %s" % str(all))
	check(all.has("Everyone is gone"), "with the verdict")
	for caption in ["DAYS SURVIVED", "WALKERS PUT DOWN", "DIED OR TURNED"]:
		check(all.has(caption), "a line for %s" % caption)
	eq(go.stat_values.keys(), ["days", "kills", "lost"], "the three numbers, each in its own label")
	eq(go.stat_values.kills.text, "12", "the same facts")
	# the numbers are ruled lines: a rule under each, and one over the first
	var rules := 0
	for r in go.find_children("*", "ColorRect", true, false):
		if r.custom_minimum_size.y == 1.0 and r.custom_minimum_size.x == 0.0:
			rules += 1
	check(rules >= 4, "ruled lines: %d" % rules)
	for key in go.stat_values:
		var row: Control = go.stat_values[key].get_parent()
		check(row is HBoxContainer and row.get_parent() is VBoxContainer, "%s sits on its line" % key)
	var look: Array = Kit.fills(go.panel.get_theme_stylebox("panel"))
	if look[1].a > 0.0:
		check(look[0].v > 0.55, "on pale paper: %s" % str(look))
	eq(go.title_label.get_theme_color("font_color"), Hud.PAPER_INK, "in dark ink")
	Kit.free_all(ctx)


func test_the_report_card_has_a_main_menu_button_that_calls_the_shell() -> void:
	_remove_save()
	var ctx := Kit.build()
	ctx.hud.save_paths = []
	var called := []
	_over(ctx, "defeat")
	var b := _button(ctx, "Main menu")
	check(b != null, "there is a Main menu button")
	b.pressed.emit()
	check(true, "with nobody listening a press does nothing and breaks nothing")
	ctx.hud.on_menu = func(): called.append(true)
	b.pressed.emit()
	eq(called.size(), 1, "and with the shell listening it calls it once")
	var order := []
	for x in ctx.hud.game_over.find_children("*", "Button", true, false):
		order.append(x.text)
	eq(order, ["New game", "Main menu"], "New game first, Main menu last (no save: no Load)")
	Kit.free_all(ctx)


func test_main_menu_comes_after_load_last_save() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	var ctx := Kit.build()
	ctx.hud.save_paths = [SAVE]
	_over(ctx, "victory")
	var order := []
	for x in ctx.hud.game_over.find_children("*", "Button", true, false):
		order.append(x.text)
	eq(order, ["New game", "Load last save", "Main menu"], "the three buttons in order")
	Kit.free_all(ctx)
	_remove_save()


func test_the_crew_row_is_a_badge_for_each_with_the_fates_in_chalk_on_slate() -> void:
	_remove_save()
	var ctx := Kit.build()
	ctx.hud.save_paths = []
	Kit.person(ctx, "walt").dead = true
	Kit.person(ctx, "walt").turned = true
	_over(ctx, "victory")
	var go = ctx.hud.game_over
	var fates := 0
	for l in go.find_children("*", "Label", true, false):
		if l.text in ["Alive", "Died", "Turned", "Left"]:
			fates += 1
	eq(fates, 6, "one fate for each of the six")
	Kit.free_all(ctx)


func test_the_report_card_fits_the_window_in_either_look() -> void:
	_remove_save()
	for frames in [false, true]:
		Hud.use_frames = frames
		for size in SIZES:
			var ctx := Kit.build(size[0], size[1])
			ctx.hud.save_paths = [SAVE]
			var f := FileAccess.open(SAVE, FileAccess.WRITE)
			f.store_string("{}")
			f.close()
			_over(ctx, "defeat")
			await Kit.settle()
			await Kit.settle()
			var win := Rect2(0, 0, size[0], size[1])
			var panel := Kit.rect(ctx.hud.game_over.panel)
			check(panel.size != Vector2.ZERO and win.encloses(panel.grow(-0.5)), "frames %s, %dpx: the card is inside the window: %s" % [frames, size[0], str(panel)])
			for text in ["New game", "Load last save", "Main menu"]:
				var r := Kit.rect(_button(ctx, text))
				check(r.size != Vector2.ZERO and panel.encloses(r), "frames %s, %dpx: %s is on the card: %s" % [frames, size[0], text, str(r)])
			Kit.free_all(ctx)
			_remove_save()
	Hud.use_frames = true


# -------------------------------------------------- the toolbar and the phase chip --

func test_the_speed_in_use_and_the_fields_view_light_up_and_the_rest_do_not() -> void:
	var ctx := Kit.build()
	Kit.update(ctx, 2)
	var lit: Array = []
	for i in ctx.hud.speed_buttons.size():
		var b: Button = ctx.hud.speed_buttons[i]
		var box: StyleBox = b.get_theme_stylebox("normal")
		if (box is StyleBoxTexture) or (box is StyleBoxFlat and box.bg_color.a > 0.0):
			lit.append(i)
		eq(b.get_meta("icon").modulate, Hud.ACCENT if i == 2 else Hud.INK2, "speed %d: the icon is gold only while it is in use" % i)
	eq(lit, [2], "only the speed in use is lit")
	var off: StyleBox = ctx.hud.fields_button.get_theme_stylebox("normal")
	check(off is StyleBoxFlat and off.bg_color.a == 0.0, "the fields view is dark while it is off")
	ctx.hud.set_fields(true)
	var on: StyleBox = ctx.hud.fields_button.get_theme_stylebox("normal")
	check(on is StyleBoxTexture or (on is StyleBoxFlat and on.bg_color.a > 0.0), "and lit while it is on")
	Kit.free_all(ctx)


func test_the_phase_chip_takes_the_colour_of_the_phase_in_either_look() -> void:
	for frames in [false, true]:
		Hud.use_frames = frames
		var ctx := Kit.build()
		for phase in ["day", "dusk", "night", "dawn"]:
			ctx.sim.phase = phase
			Kit.update(ctx, 1)
			var box: StyleBox = ctx.hud.phase_chip.get_theme_stylebox("panel")
			check(_wears(box, "pill") or not frames, "frames %s, %s: the chip wears the pill frame when there is one" % [frames, phase])
			eq(ctx.hud.phase_label.get_theme_color("font_color"), Hud.PHASE_COLOR[phase], "%s: the word is in the phase's colour" % phase)
		Kit.free_all(ctx)
	Hud.use_frames = true
