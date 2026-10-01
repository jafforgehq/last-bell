extends "res://tests/case.gd"
## Round 4, the view of people: the person panel's traits, mood, bonds and skill gains, the stats on the
## name, the mood mark and the memorial on the crew cards, the alert icons of the new alerts, and that
## the panel still fits the dock at every size. The rules behind them (tests/test_traits.gd, test_morale.gd,
## test_bonds.gd, test_skills.gd) are PEOPLE's: here the modules are the kit's table-driven fakes (and, near
## the end, the real ones). The speech bubbles are in tests/test_hud_bubbles.gd.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const TextTests := preload("res://tests/test_hud_text.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]


## A selected person and the HUD updated.
func _open(ctx: Dictionary, id: String):
	var p = Kit.person(ctx, id)
	Kit.select(ctx, p)
	Kit.update(ctx)
	return p


func _refs(ctx: Dictionary) -> Dictionary:
	return ctx.hud.inspect_refs


## The words of a tooltip with its line breaks put back as spaces (a long one is wrapped by hand).
func _flat(tip: String) -> String:
	return tip.replace("\n", " ")


# ------------------------------------------------------------------- traits --

func test_the_panel_has_a_chip_for_each_trait_with_its_blurb_in_the_tooltip() -> void:
	var ctx := Kit.build()
	_open(ctx, "ruth")
	var refs := _refs(ctx)
	check(Kit.texts(ctx.hud.inspect).has("TRAITS"), "a Traits row")
	var chips: Array = refs.traits_box.get_children()
	eq(chips.size(), 2, "two traits, two chips")
	eq(Kit.texts(chips[0]), ["Steady"], "the first")
	eq(Kit.texts(chips[1]), ["Loyal"], "the second")
	for i in 2:
		var quirk: Dictionary = ctx.sim.traits.of(Kit.person(ctx, "ruth"))[i]
		eq(_flat(chips[i].tooltip_text), String(quirk.blurb), "%s: the blurb is the tooltip" % quirk.name)
		check(chips[i].mouse_filter != Control.MOUSE_FILTER_IGNORE, "%s: and the chip takes the mouse, or there would be no tooltip" % quirk.name)
	Kit.free_all(ctx)


func test_every_person_shows_their_own_traits() -> void:
	var ctx := Kit.build()
	for p in ctx.sim.people:
		Kit.select(ctx, p)
		Kit.update(ctx)
		var shown: Array = []
		for chip in _refs(ctx).traits_box.get_children():
			shown.append(Kit.texts(chip)[0])
		var want: Array = []
		for t in ctx.sim.traits.of(p):
			want.append(t.name)
		eq(shown, want, "%s's chips" % p.first)
		eq(shown.size(), 2, "%s has two" % p.first)
	Kit.free_all(ctx)


func test_a_person_without_traits_has_no_row_and_the_chips_follow_the_module() -> void:
	var ctx := Kit.build()
	var ana = _open(ctx, "ana")
	var refs := _refs(ctx)
	check(refs.traits_head.visible and refs.traits_box.visible, "the row shows while there are traits")
	ctx.sim.traits.table["ana"] = []
	Kit.update(ctx)
	check(not refs.traits_head.visible and not refs.traits_box.visible, "no traits: no row")
	ctx.sim.traits.table["ana"] = ["tough"]
	Kit.update(ctx)
	check(refs.traits_head.visible, "a trait is given: the row is back")
	var shown: Array = []
	for chip in refs.traits_box.get_children():
		shown.append(Kit.texts(chip)[0])
	eq(shown, ["Tough"], "with the new chip only (the old ones are gone)")
	Kit.free_all(ctx)


# --------------------------------------------------------------------- mood --

func test_the_mood_row_shows_the_word_a_bar_of_the_value_and_the_colour_of_the_mood() -> void:
	var ctx := Kit.build()
	var ana = _open(ctx, "ana")
	var refs := _refs(ctx)
	check(Kit.texts(ctx.hud.inspect).has("MOOD"), "a Mood row")
	var cases := [[85.0, "Inspired"], [60.0, "Steady"], [30.0, "Shaken"], [12.0, "Breaking"]]
	for c in cases:
		ctx.sim.morale.values[ana.id] = c[0]
		ctx.sim.morale.moods.erase(ana.id)
		Kit.update(ctx)
		eq(refs.mood_word.text, c[1], "the word at %d" % int(c[0]))
		near(refs.mood_bar.value, c[0] / 100.0, 0.001, "the bar at %d" % int(c[0]))
		eq(refs.mood_bar.color, Hud.MOOD_COLORS[c[1]], "the bar's colour for %s" % c[1])
		eq(refs.mood_word.get_theme_color("font_color"), Hud.MOOD_TEXT[c[1]], "the word's colour for %s" % c[1])
	Kit.free_all(ctx)


func test_the_mood_tooltip_lists_every_reason_with_its_sign() -> void:
	var ctx := Kit.build()
	var ruth = _open(ctx, "ruth")
	ctx.sim.morale.values[ruth.id] = 66.0
	ctx.sim.morale.reasons[ruth.id] = [{"label": "fed and watered", "value": 5.0}, {"label": "the dead at the wall", "value": -8.0}, {"label": "a quiet night", "value": 2.0}, {"label": "the wall held", "value": 0.4}]
	Kit.update(ctx)
	var refs := _refs(ctx)
	var lines: PackedStringArray = refs.mood_word.tooltip_text.split("\n")
	check(lines[0].contains("Steady") and lines[0].contains("66"), "the first line says the mood and its number: '%s'" % lines[0])
	check(lines.has("+5 fed and watered"), "a lift: %s" % str(lines))
	check(lines.has("-8 the dead at the wall"), "a weight: %s" % str(lines))
	check(lines.has("+2 a quiet night"), "another lift")
	check(lines.has("+0.4 the wall held"), "a small one keeps its decimal instead of reading +0: %s" % str(lines))
	eq(refs.mood_head.tooltip_text, refs.mood_word.tooltip_text, "the caption has the same tooltip")
	eq(refs.mood_bar.tooltip_text, refs.mood_word.tooltip_text, "and so has the bar")
	for part in [refs.mood_head, refs.mood_bar, refs.mood_word]:
		check(part.mouse_filter != Control.MOUSE_FILTER_IGNORE, "%s takes the mouse" % part.get_class())
	Kit.free_all(ctx)


func test_a_shock_that_is_fading_says_so_and_the_tooltip_says_where_it_is_settling() -> void:
	var ctx := Kit.build()
	var dez = _open(ctx, "dez")
	ctx.sim.morale.reasons[dez.id] = [{"label": "Well fed and watered", "value": 5.0}, {"label": "Walt is down", "value": -10.0, "recent": true}]
	Kit.update(ctx)
	var lines: PackedStringArray = _refs(ctx).mood_word.tooltip_text.split("\n")
	check(lines.has("-10 Walt is down (fading)"), "a shock still fading: %s" % str(lines))
	check(lines.has("+5 Well fed and watered"), "what they are now is not: %s" % str(lines))
	check(lines.has("Settling toward 55"), "where it is going (60 and the reasons): %s" % str(lines))
	Kit.free_all(ctx)


func test_a_very_long_list_of_reasons_is_cut_and_says_how_many_more() -> void:
	var ctx := Kit.build()
	var ruth = _open(ctx, "ruth")
	var many: Array = []
	for i in 14:
		many.append({"label": "reason %d" % i, "value": float(14 - i)})
	ctx.sim.morale.reasons[ruth.id] = many
	Kit.update(ctx)
	var lines: PackedStringArray = _refs(ctx).mood_word.tooltip_text.split("\n")
	check(lines.has("+14 reason 0") and lines.has("+5 reason 9"), "the biggest ten: %s" % str(lines))
	check(not lines.has("+4 reason 10"), "and not the rest")
	check(lines.has("and 4 smaller"), "which are counted: %s" % str(lines))
	Kit.free_all(ctx)


func test_the_mood_tooltip_says_so_when_nothing_moves_it() -> void:
	var ctx := Kit.build()
	var ruth = _open(ctx, "ruth")
	ctx.sim.morale.reasons[ruth.id] = []
	Kit.update(ctx)
	check(_flat(_refs(ctx).mood_word.tooltip_text).contains("Nothing"), "nothing is moving it: '%s'" % _refs(ctx).mood_word.tooltip_text)
	Kit.free_all(ctx)


func test_a_breakdown_says_so_in_the_row_the_tooltip_and_the_doing_line() -> void:
	var ctx := Kit.build()
	var marcus = _open(ctx, "marcus")
	ctx.sim.morale.values[marcus.id] = 8.0
	ctx.sim.morale.broke[marcus.id] = true
	Kit.update(ctx)
	var refs := _refs(ctx)
	eq(refs.mood_word.text, "Breakdown", "the word")
	eq(refs.mood_word.get_theme_color("font_color"), Hud.DANGER_TEXT, "in red")
	eq(refs.mood_bar.color, Hud.DANGER, "and the bar")
	var first: String = refs.mood_word.tooltip_text.split("\n")[0]
	check(first.to_lower().contains("breakdown") and first.contains("Marcus"), "the tooltip leads with it: '%s'" % first)
	check(refs.mood_word.tooltip_text.to_lower().contains("cannot"), "and what it means: '%s'" % refs.mood_word.tooltip_text)
	eq(refs.doing.text, "Having a breakdown", "the Doing line too")
	ctx.sim.morale.broke[marcus.id] = false
	Kit.update(ctx)
	eq(refs.mood_word.text, "Breaking", "and it goes when it is over")
	Kit.free_all(ctx)


func test_the_mood_tooltip_gives_the_effect_on_work_when_there_is_one() -> void:
	var ctx := Kit.build()
	var walt = _open(ctx, "walt")
	var refs := _refs(ctx)
	check(not refs.mood_word.tooltip_text.contains("aims"), "nothing to report at full strength: '%s'" % refs.mood_word.tooltip_text)
	ctx.sim.morale.moods[walt.id] = "Shaken"
	ctx.sim.morale.values[walt.id] = 30.0
	ctx.sim.morale.perfs[walt.id] = 0.9
	Kit.update(ctx)
	var lines: PackedStringArray = refs.mood_word.tooltip_text.split("\n")
	check(lines.has("Works and aims at 90% of their best"), "what it costs: %s" % str(lines))
	ctx.sim.morale.moods[walt.id] = "Inspired"
	ctx.sim.morale.perfs[walt.id] = 1.05
	Kit.update(ctx)
	check(refs.mood_word.tooltip_text.split("\n").has("Works and aims at 105% of their best"), "and what it gives: '%s'" % refs.mood_word.tooltip_text)
	Kit.free_all(ctx)


func test_the_mood_row_is_hidden_while_morale_is_switched_off() -> void:
	var ctx := Kit.build()
	_open(ctx, "dez")
	var refs := _refs(ctx)
	check(refs.mood_head.visible and refs.mood_word.visible, "shown by default")
	ctx.sim.morale.enabled = false
	Kit.update(ctx)
	check(not refs.mood_head.visible and not refs.mood_bar.visible and not refs.mood_word.visible, "the tutorial's morale is off: nothing to show")
	ctx.sim.morale.enabled = true
	Kit.update(ctx)
	check(refs.mood_head.visible, "and back when it is on")
	Kit.free_all(ctx)


func test_the_dead_have_a_memorial_in_place_of_a_mood() -> void:
	var ctx := Kit.build()
	var dez = _open(ctx, "dez")
	ctx.sim.barks.epitaphs[dez.id] = "He fixed whatever you gave him."
	dez.dead = true
	Kit.update(ctx)
	var refs := _refs(ctx)
	eq(refs.mood_head.text, "MEMORY", "the caption")
	check(not refs.mood_bar.visible and not refs.mood_word.visible, "no bar, no word")
	check(refs.mood_memo.visible, "the memorial line shows")
	eq(refs.mood_memo.text, "He fixed whatever you gave him.", "with the epitaph")
	eq(refs.mood_memo.tooltip_text, "He fixed whatever you gave him.", "in full in its tooltip too")
	# one who turned or was sent out is not remembered like that: no row at all
	dez.turned = true
	Kit.update(ctx)
	check(not refs.mood_head.visible and not refs.mood_memo.visible, "turned: no row")
	dez.turned = false
	dez.away = {"kind": "exile"}
	Kit.update(ctx)
	check(not refs.mood_head.visible, "sent out: no row")
	dez.away = null
	dez.dead = false
	Kit.update(ctx)
	eq(refs.mood_head.text, "MOOD", "alive again (a test's trick): the caption is back")
	check(refs.mood_word.visible and not refs.mood_memo.visible, "and the word, not the memorial")
	Kit.free_all(ctx)


func test_a_memorial_with_no_epitaph_still_says_so() -> void:
	var ctx := Kit.build()
	var dez = _open(ctx, "dez")
	ctx.sim.barks.epitaphs[dez.id] = ""
	dez.dead = true
	Kit.update(ctx)
	check(_refs(ctx).mood_memo.visible and _refs(ctx).mood_memo.text != "", "a plain line: '%s'" % _refs(ctx).mood_memo.text)
	Kit.free_all(ctx)


# -------------------------------------------------------------------- bonds --

func test_the_bonds_line_names_who_and_what_kind() -> void:
	var ctx := Kit.build()
	_open(ctx, "ruth")
	var refs := _refs(ctx)
	check(Kit.texts(ctx.hud.inspect).has("BONDS"), "a Bonds row")
	eq(refs.bonds.text, "Marcus (family), Ana (friend)", "Ruth's")
	_open(ctx, "walt")
	eq(_refs(ctx).bonds.text, "Marcus (student)", "Walt's: Marcus is his student")
	_open(ctx, "marcus")
	eq(_refs(ctx).bonds.text, "Ruth (family), Walt (mentor)", "and Walt is Marcus's mentor")
	_open(ctx, "dez")
	eq(_refs(ctx).bonds.text, "Hector (friend)", "Dez's")
	Kit.free_all(ctx)


func test_the_bonds_tooltip_gives_the_full_names_and_what_a_bond_does() -> void:
	var ctx := Kit.build()
	_open(ctx, "ruth")
	var tip: String = _refs(ctx).bonds.tooltip_text
	check(tip.contains("Marcus Bell") and tip.contains("family"), "a full name and the kind: '%s'" % tip)
	check(tip.contains("Ana Reyes") and tip.contains("friend"), "the second: '%s'" % tip)
	check(_flat(tip).to_lower().contains("steadier") or _flat(tip).to_lower().contains("closer"), "and what they are for: '%s'" % tip)
	eq(_refs(ctx).bonds_head.tooltip_text, tip, "the caption has it too")
	Kit.free_all(ctx)


func test_a_bond_with_someone_who_is_gone_stays_on_the_line_and_says_so() -> void:
	var ctx := Kit.build()
	_open(ctx, "ruth")
	Kit.person(ctx, "marcus").dead = true
	Kit.update(ctx)
	eq(_refs(ctx).bonds.text, "Marcus (family, gone), Ana (friend)", "the line")
	check(_refs(ctx).bonds.tooltip_text.contains("Marcus Bell (family, gone)"), "and the tooltip: '%s'" % _refs(ctx).bonds.tooltip_text)
	Kit.free_all(ctx)


func test_no_bonds_no_row_and_it_follows_the_module() -> void:
	var ctx := Kit.build()
	_open(ctx, "ruth")
	var refs := _refs(ctx)
	ctx.sim.bonds.table["ruth"] = []
	Kit.update(ctx)
	check(not refs.bonds_head.visible and not refs.bonds.visible, "nobody close: no row")
	ctx.sim.bonds.table["ruth"] = [["dez", "friend"]]
	Kit.update(ctx)
	check(refs.bonds_head.visible, "a new friend: the row is back")
	eq(refs.bonds.text, "Dez (friend)", "with the new name")
	Kit.free_all(ctx)


func test_a_long_line_of_bonds_never_widens_the_panel() -> void:
	var ctx := Kit.build()
	_open(ctx, "ruth")
	ctx.sim.bonds.table["ruth"] = [["marcus", "family"], ["ana", "friend"], ["walt", "mentor"], ["dez", "friend"], ["hector", "friend"]]
	Kit.update(ctx)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	eq(Kit.rect(ctx.hud.inspect).size.x, float(Hud.INSPECT_W), "the panel keeps its width")
	check(_refs(ctx).bonds.tooltip_text.contains("Hector Ruiz"), "and the tooltip has them all: '%s'" % _refs(ctx).bonds.tooltip_text)
	Kit.free_all(ctx)


# ------------------------------------------------------------------- skills --

func test_the_skills_come_from_the_persons_own_copy_and_show_gains() -> void:
	var ctx := Kit.build()
	var marcus = _open(ctx, "marcus")
	var cells: Dictionary = _refs(ctx).skills
	eq(cells.keys(), Hud.SKILLS_SHOWN, "the three that matter, in order")
	# the roster says Shooting 8; he has grown to 9
	marcus.skills["Shooting"] = 9
	ctx.sim.skills.table["marcus"] = {"Shooting": 1}
	Kit.update(ctx)
	eq(cells.Shooting.value.text, "9", "his own Shooting, not the roster's")
	eq(cells.Shooting.gain.text, "+1", "with the gain beside it")
	check(cells.Shooting.gain.visible, "shown")
	check(not cells.Building.gain.visible and cells.Building.gain.text == "", "no gain, nothing beside it")
	near(cells.Shooting.bar.value, 0.9, 0.001, "the bar follows the skill")
	near(cells.Shooting.bar.gain, 0.1, 0.001, "and marks what was gained")
	eq(cells.Building.value.text, str(marcus.skills["Building"]), "an untouched skill keeps its number")
	Kit.free_all(ctx)


func test_the_skills_never_read_the_roster_when_the_person_has_their_own() -> void:
	var ctx := Kit.build()
	var dez = _open(ctx, "dez")
	dez.skills["Building"] = 10
	dez.def.skills["Building"] = 3
	Kit.update(ctx)
	eq(_refs(ctx).skills.Building.value.text, "10", "the person's own copy")
	dez.def.skills["Building"] = 9
	Kit.free_all(ctx)


func test_a_gain_appears_while_the_person_is_selected() -> void:
	var ctx := Kit.build()
	var ana = _open(ctx, "ana")
	var cells: Dictionary = _refs(ctx).skills
	check(not cells.Medicine.gain.visible, "no gain at first")
	ana.skills["Medicine"] = int(ana.skills["Medicine"]) + 1
	ctx.sim.skills.table["ana"] = {"Medicine": 1}
	Kit.update(ctx)
	check(cells.Medicine.gain.visible and cells.Medicine.gain.text == "+1", "it shows at the next update")
	ctx.sim.skills.table["ana"] = {"Medicine": 3}
	Kit.update(ctx)
	eq(cells.Medicine.gain.text, "+3", "and grows")
	Kit.free_all(ctx)


func test_a_skill_tooltip_says_where_it_started() -> void:
	var ctx := Kit.build()
	var marcus = _open(ctx, "marcus")
	marcus.skills["Shooting"] = 9
	ctx.sim.skills.table["marcus"] = {"Shooting": 1}
	Kit.update(ctx)
	var tip: String = _refs(ctx).skills.Shooting.box.tooltip_text
	check(tip.contains("Shooting 9") and tip.contains("8"), "the number and where it started: '%s'" % tip)
	check(tip.to_lower().contains("practice") or tip.to_lower().contains("use"), "and what makes it grow: '%s'" % tip)
	var untouched: String = _refs(ctx).skills.Medicine.box.tooltip_text
	check(not untouched.contains("started at"), "an untouched one does not say where it started: '%s'" % untouched)
	Kit.free_all(ctx)


func test_the_skills_still_show_only_what_matters() -> void:
	var ctx := Kit.build()
	_open(ctx, "ana")
	var all := Kit.texts(ctx.hud.inspect)
	for name in ["Shooting", "Building", "Medicine"]:
		check(all.has(name), "%s is listed" % name)
	for name in ["Melee", "Leading"]:
		check(not all.has(name), "%s is not" % name)
	Kit.free_all(ctx)


# -------------------------------------------------------------------- stats --

func test_the_name_carries_the_stats_in_a_tooltip() -> void:
	var ctx := Kit.build()
	var walt = _open(ctx, "walt")
	walt.stats = {"kills": 12, "kills_night": 3, "mended": 340.0, "treated": 2, "crafted": 20.0, "shots": 80}
	Kit.update(ctx)
	var name: Label = _refs(ctx).name
	eq(name.text, "Walt Haney", "the name label")
	check(name.mouse_filter != Control.MOUSE_FILTER_IGNORE, "it takes the mouse")
	var lines: PackedStringArray = name.tooltip_text.split("\n")
	check(lines.has("Kills: 12 (3 tonight)"), "kills: %s" % str(lines))
	check(lines.has("Shots fired: 80"), "shots: %s" % str(lines))
	check(lines.has("Wall mended: 340 HP"), "mended: %s" % str(lines))
	check(lines.has("Treated: 2"), "treated: %s" % str(lines))
	check(lines.has("Scrap made into ammo: 20"), "crafted: %s" % str(lines))
	Kit.free_all(ctx)


func test_the_stats_tooltip_leaves_out_what_is_nothing_and_follows_the_counters() -> void:
	var ctx := Kit.build()
	var hector = _open(ctx, "hector")
	hector.stats = {"kills": 0, "kills_night": 0, "mended": 0.0, "treated": 0, "crafted": 0.0, "shots": 0}
	Kit.update(ctx)
	var lines: PackedStringArray = _refs(ctx).name.tooltip_text.split("\n")
	eq(lines.size(), 1, "only kills when nothing else was done: %s" % str(lines))
	eq(lines[0], "Kills: 0", "which says none")
	hector.stats["kills"] = 5
	hector.stats["kills_night"] = 5
	Kit.update(ctx)
	check(_refs(ctx).name.tooltip_text.contains("Kills: 5 (5 tonight)"), "it follows: '%s'" % _refs(ctx).name.tooltip_text)
	Kit.free_all(ctx)


# --------------------------------------------------------------------- cards --

func test_a_shaken_person_has_a_mood_mark_on_their_card() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	Kit.update(ctx)
	eq(Kit.card(ctx, ana).marks.get_child_count(), 0, "a steady person has no mark")
	ctx.sim.morale.values[ana.id] = 30.0
	Kit.update(ctx)
	var c := Kit.card(ctx, ana)
	eq(c.marks.get_child_count(), 1, "a shaken one has one")
	var mark: TextureRect = c.marks.get_child(0)
	eq(mark.texture, ctx.hud.icons["mood"], "the face, not the question mark of an icon that is not there")
	eq(mark.modulate, Hud.WARN, "amber")
	check(mark.tooltip_text.contains("Shaken"), "with its tip: '%s'" % mark.tooltip_text)
	ctx.sim.morale.values[ana.id] = 10.0
	Kit.update(ctx)
	mark = Kit.card(ctx, ana).marks.get_child(0)
	eq(mark.modulate, Hud.DANGER, "red while breaking")
	ctx.sim.morale.values[ana.id] = 70.0
	Kit.update(ctx)
	eq(Kit.card(ctx, ana).marks.get_child_count(), 0, "and it goes when they are steady again")
	Kit.free_all(ctx)


func test_the_mood_mark_sits_among_the_others() -> void:
	var ctx := Kit.build()
	var ana = Kit.person(ctx, "ana")
	ctx.sim.morale.values[ana.id] = 30.0
	ctx.sim.supplies.marks[ana.id] = [{"icon": "hungry", "color": Hud.WARN, "tip": "Hungry"}]
	ctx.sim.medical.marks[ana.id] = [{"icon": "wound", "color": Hud.DANGER, "tip": "Bleeding"}]
	Kit.update(ctx)
	var c := Kit.card(ctx, ana)
	eq(c.marks.get_child_count(), 3, "three marks")
	var icons: Array = []
	for m in c.marks.get_children():
		icons.append(m.texture)
	check(icons.has(ctx.hud.icons["mood"]), "one is the mood")
	Kit.free_all(ctx)


func test_the_mood_mark_is_not_lost_when_there_are_more_marks_than_fit() -> void:
	var ctx := Kit.build(700, 700)
	var ana = Kit.person(ctx, "ana")
	ctx.sim.morale.values[ana.id] = 10.0
	var many: Array = []
	for icon in ["hungry", "thirsty", "wound", "fever", "down"]:
		many.append({"icon": icon, "color": Hud.WARN, "tip": icon})
	ctx.sim.medical.marks[ana.id] = many
	Kit.update(ctx)
	var found := false
	for m in Kit.card(ctx, ana).marks.get_children():
		if m.texture == ctx.hud.icons["mood"]:
			found = true
	check(found, "a person about to break shows it even with every other mark up")
	Kit.free_all(ctx)


func test_a_dead_persons_card_reads_in_memory_and_the_epitaph_is_in_its_tooltip() -> void:
	var ctx := Kit.build()
	var walt = Kit.person(ctx, "walt")
	var c := Kit.card(ctx, walt)
	Kit.update(ctx)
	eq(c.card.tooltip_text, "Walt Haney, retired cop", "alive: the name and the job, as before")
	ctx.sim.barks.epitaphs[walt.id] = "He taught us to hold our fire."
	walt.dead = true
	Kit.update(ctx)
	eq(c.word.text, "In memory", "the word on the card")
	check(c.veil.visible, "dimmed, as the dead always were")
	var lines: PackedStringArray = c.card.tooltip_text.split("\n")
	eq(lines[0], "Walt Haney, retired cop", "the tooltip keeps the name")
	check(lines.has("In memory"), "says it: %s" % str(lines))
	check(lines.has("He taught us to hold our fire."), "and gives the epitaph: %s" % str(lines))
	Kit.free_all(ctx)


func test_the_memorial_card_keeps_the_frame_and_greys_the_stock() -> void:
	var ctx := Kit.build()
	var walt = Kit.person(ctx, "walt")
	var c := Kit.card(ctx, walt)
	Kit.update(ctx)
	eq(c.card.self_modulate, Color.WHITE, "a living card is as it was made")
	walt.dead = true
	Kit.update(ctx)
	check(c.card.self_modulate.v < 0.9, "a memorial's stock is greyed: %s" % str(c.card.self_modulate))
	var box: StyleBox = c.card.get_theme_stylebox("panel")
	if Hud.has_frame("card"):
		check(box is StyleBoxTexture, "and it still wears the card frame")
	else:
		check(box is StyleBoxFlat, "and the flat card")
	walt.dead = false
	Kit.update(ctx)
	eq(c.card.self_modulate, Color.WHITE, "alive again: as it was")
	Kit.free_all(ctx)


func test_one_who_turned_or_was_sent_out_keeps_their_own_word() -> void:
	var ctx := Kit.build()
	var walt = Kit.person(ctx, "walt")
	var c := Kit.card(ctx, walt)
	ctx.sim.barks.epitaphs[walt.id] = "He taught us to hold our fire."
	walt.dead = true
	walt.turned = true
	Kit.update(ctx)
	eq(c.word.text, "Turned", "turned")
	check(not c.card.tooltip_text.contains("In memory"), "not in memory: '%s'" % c.card.tooltip_text)
	check(c.card.tooltip_text.contains("Turned into one of the dead") and c.card.tooltip_text.contains("He taught us to hold our fire."), "but what was said of them is there: '%s'" % c.card.tooltip_text)
	walt.turned = false
	walt.away = {"kind": "exile"}
	Kit.update(ctx)
	eq(c.word.text, "Left", "sent out")
	check(not c.card.tooltip_text.contains("In memory"), "nor is the one who left")
	Kit.free_all(ctx)


func test_a_game_whose_barks_have_no_epitaph_still_gets_the_word() -> void:
	var ctx := Kit.build()
	var walt = Kit.person(ctx, "walt")
	var plain = load("res://scripts/sim/barks.gd").new()
	plain.setup(ctx.sim)
	ctx.sim.barks = plain
	walt.dead = true
	Kit.update(ctx)
	var c := Kit.card(ctx, walt)
	eq(c.word.text, "In memory", "the word")
	eq(c.card.tooltip_text.split("\n")[0], "Walt Haney, retired cop", "the tooltip has no epitaph and does not break")
	Kit.free_all(ctx)


func test_the_in_memory_word_fits_a_card_at_both_sizes() -> void:
	for size in [[1280, 800], [700, 700]]:
		var ctx := Kit.build(size[0], size[1])
		var walt = Kit.person(ctx, "walt")
		walt.dead = true
		Kit.update(ctx)
		await Kit.settle()
		var c := Kit.card(ctx, walt)
		var card_rect: Rect2 = c.card.get_global_rect()
		var word: Label = c.word
		var font: Font = word.get_theme_font("font")
		var fs := word.get_theme_font_size("font_size")
		# the longest line the label breaks it into must fit the card's picture
		var widest := 0.0
		for part in word.text.split(" "):
			widest = maxf(widest, font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		check(widest <= word.size.x + 0.5, "%d px: the longest word (%.0f px) fits the picture (%.0f px)" % [size[0], widest, word.size.x])
		check(card_rect.encloses(word.get_global_rect().grow(-0.5)), "%d px: the word is inside the card" % size[0])
		Kit.free_all(ctx)


# ------------------------------------------------------------- alerts' icons --

func test_the_new_alerts_wear_their_icons() -> void:
	var ctx := Kit.build()
	var cases := {"skill-ana": "star", "breakdown-marcus": "mood", "story": "radio", "story-fog": "radio", "dawn": "sun"}
	for id in cases:
		eq(ctx.hud._alert_icon_name({"id": id, "level": "info"}), cases[id], id)
	check(ctx.hud.icons.has("star") and ctx.hud.icons.has("mood") and ctx.hud.icons.has("radio"), "the three new pictures are loaded")
	# and in the feed
	ctx.sim.alert("skill-ana", "info", "Ana is a better healer now", "Medicine 5", null, 60.0)
	ctx.sim.alert("breakdown-marcus", "danger", "Marcus is having a breakdown", "He cannot shoot until it passes", null, 60.0)
	Kit.update(ctx)
	for id in ["skill-ana", "breakdown-marcus"]:
		var it: Dictionary = ctx.hud.alert_items.get(id, {})
		check(not it.is_empty() and it.panel != null, "%s is in the feed" % id)
		if not it.is_empty() and it.panel != null:
			eq((it.icon as TextureRect).texture, ctx.hud.icons[cases[id]], "%s: with its icon" % id)
	Kit.free_all(ctx)


func test_the_old_alert_icons_are_as_they_were() -> void:
	var ctx := Kit.build()
	var cases := {"seg-3": "wall", "fever-ana": "fever", "bell": "bell", "horde": "walker", "workshop-idle": "ammo", "no-ammo": "ammo"}
	for id in cases:
		eq(ctx.hud._alert_icon_name({"id": id, "level": "warn"}), cases[id], id)
	Kit.free_all(ctx)


# ------------------------------------------------------------ modals, orders --

func test_modal_open_follows_the_dialog_and_the_end_screen() -> void:
	var ctx := Kit.build()
	check(not ctx.hud.modal_open(), "nothing open")
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.list = Kit.sample_sites()
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx)
	ctx.hud.open_scavenge(ctx.hud.selection)
	check(ctx.hud.modal_open(), "the scavenging dialog is a modal")
	ctx.hud.scavenge_dialog.cancel()
	check(not ctx.hud.modal_open(), "and not once it is closed")
	ctx.sim.over = "defeat"
	Kit.update(ctx)
	check(ctx.hud.modal_open(), "the end screen is one too")
	Kit.free_all(ctx)


func test_a_full_page_that_stops_the_mouse_is_a_modal_and_a_board_is_not() -> void:
	var ctx := Kit.build()
	# the storyteller's radio card: a page over the whole window that stops the mouse
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	ctx.hud.add_child(page)
	check(ctx.hud.modal_open(), "a page that covers the window is a modal")
	page.visible = false
	check(not ctx.hud.modal_open(), "not while it is hidden")
	page.visible = true
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check(not ctx.hud.modal_open(), "nor when it lets the mouse through (the dawn card does not block anybody)")
	page.free()
	# one of the HUD's own boards is never one, and a card that says so is
	var card := Control.new()
	card.custom_minimum_size = Vector2(300, 200)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	ctx.hud.add_child(card)
	check(not ctx.hud.modal_open(), "a small card that stops the mouse is not")
	card.set_meta("modal", true)
	check(ctx.hud.modal_open(), "unless it says it is")
	card.free()
	check(not ctx.hud.modal_open(), "and nothing is left over")
	Kit.free_all(ctx)


func test_a_person_in_a_breakdown_cannot_be_ordered_and_the_buttons_say_why() -> void:
	var ctx := Kit.build()
	var marcus = _open(ctx, "marcus")
	eq(ctx.hud.why_not("post"), "", "fine while steady")
	ctx.sim.morale.broke[marcus.id] = true
	Kit.update(ctx)
	eq(ctx.hud.why_not("post"), "Marcus is having a breakdown", "the reason")
	eq(ctx.hud.why_not("repair"), "Marcus is having a breakdown", "for every order")
	eq(ctx.hud.why_not("focus"), "", "but looking at them is always fine")
	var tip: String = Kit.gizmo(ctx, "post").tooltip_text
	check(tip.contains("Not now: Marcus is having a breakdown."), "in the tooltip: '%s'" % tip)
	check(Kit.gizmo(ctx, "post").modulate.a < 0.9, "and the button is ghosted")
	Kit.free_all(ctx)


# ------------------------------------------------------------ older games --

## A game from before round 4: the modules the panel reads and none of the people's.
class OldSim:
	extends RefCounted
	var stock
	var segments
	var medical
	var scavenge
	var tactics
	var supplies
	var scenario
	var alerts := {}
	var phase := "day"
	var over := ""
	func status_of(_p) -> Array:
		return []
	func perf(_p) -> float:
		return 1.0


func test_a_game_without_the_new_modules_gets_the_old_panel_and_nothing_breaks() -> void:
	var ctx := Kit.build()
	var old := OldSim.new()
	old.stock = ctx.sim.stock
	old.segments = ctx.sim.segments
	old.medical = ctx.sim.medical
	old.scavenge = ctx.sim.scavenge
	old.tactics = ctx.sim.tactics
	old.supplies = ctx.sim.supplies
	old.scenario = ctx.sim.scenario
	ctx.hud.sim_ref = old
	var ruth = Kit.person(ctx, "ruth")
	ctx.hud.select({"kind": "person", "ref": ruth})
	var refs := _refs(ctx)
	check(not refs.mood_head.visible and not refs.mood_word.visible, "no mood without a morale module")
	check(not refs.traits_head.visible, "no traits row")
	check(not refs.bonds_head.visible, "no bonds row")
	eq(refs.skills.Shooting.value.text, str(ruth.skills["Shooting"]), "the skills still show")
	check(not refs.skills.Shooting.gain.visible, "with no gain to report")
	eq(refs.name.tooltip_text.split("\n")[0].begins_with("Kills"), true, "the stats are the person's own")
	# a card of a dead person with no barks module
	ruth.dead = true
	ctx.hud._update_card(Kit.card(ctx, ruth), old)
	eq(Kit.card(ctx, ruth).word.text, "In memory", "the word does not need the module")
	ruth.dead = false
	ctx.hud.sim_ref = ctx.sim
	Kit.free_all(ctx)


# ------------------------------------------------------- the real modules --
# The game's own traits, morale, bonds and skills (PEOPLE's) under the same panel: what the rules say is
# what the player reads.

func _real(width: int = 1280, height: int = 800) -> Dictionary:
	return Kit.build(width, height, 1, true)


func test_with_the_real_modules_the_panel_shows_the_crews_own_traits_and_bonds() -> void:
	var ctx := _real()
	for p in ctx.sim.people:
		Kit.select(ctx, p)
		Kit.update(ctx)
		var traits: Array = ctx.sim.traits.of(p)
		var chips: Array = _refs(ctx).traits_box.get_children()
		eq(chips.size(), traits.size(), "%s: a chip for each trait" % p.first)
		check(chips.size() >= 1, "%s has traits" % p.first)
		for i in mini(chips.size(), traits.size()):
			eq(Kit.texts(chips[i]), [String(traits[i].name)], "%s: chip %d" % [p.first, i])
			eq(_flat(chips[i].tooltip_text), String(traits[i].blurb), "%s: and its blurb is the tooltip" % p.first)
		var bits: Array = []
		for b in ctx.sim.bonds.of(p):
			bits.append("%s (%s)" % [b.who.first, b.role])
		eq(_refs(ctx).bonds.text, ", ".join(bits), "%s: the bonds the rules give" % p.first)
		check(bits.size() >= 1, "%s has a bond" % p.first)
	# a mentor's student is a student (the other way round, a mentor)
	_open(ctx, "walt")
	check(_refs(ctx).bonds.text.contains("(student)"), "Walt's: %s" % _refs(ctx).bonds.text)
	_open(ctx, "marcus")
	check(_refs(ctx).bonds.text.contains("Walt (mentor)"), "Marcus's: %s" % _refs(ctx).bonds.text)
	Kit.free_all(ctx)


func test_the_real_bonds_tooltip_gives_the_rules_own_numbers() -> void:
	var ctx := _real()
	var bonds = ctx.sim.bonds
	var tiles := int(bonds.AIM_TILES)
	_open(ctx, "ana")
	var tip: String = _refs(ctx).bonds.tooltip_text
	var plain := roundi((float(bonds.AIM_BONUS) + ctx.sim.traits.add(Kit.person(ctx, "ana"), "bond")) * 100.0)
	check(tip.contains("Within %d tiles" % tiles) and tip.contains("aims %d%% better" % plain), "Ana: '%s'" % tip)
	check(tip.contains("Ruth Okafor (friend)"), "and the full name: '%s'" % tip)
	_open(ctx, "ruth")
	var loyal := roundi((float(bonds.AIM_BONUS) + ctx.sim.traits.add(Kit.person(ctx, "ruth"), "bond")) * 100.0)
	check(loyal > plain, "Ruth's trait adds to the bonus: %d against %d" % [loyal, plain])
	check(_refs(ctx).bonds.tooltip_text.contains("aims %d%% better" % loyal), "and the tooltip says so: '%s'" % _refs(ctx).bonds.tooltip_text)
	Kit.free_all(ctx)


func test_with_the_real_morale_the_row_the_reasons_and_the_card_mark_follow_the_rules() -> void:
	var ctx := _real()
	var morale = ctx.sim.morale
	var ana = _open(ctx, "ana")
	eq(_refs(ctx).mood_word.text, "Steady", "everyone starts steady")
	near(_refs(ctx).mood_bar.value, float(morale.START_VALUE) / 100.0, 0.001, "at the starting value")
	check(_refs(ctx).mood_word.tooltip_text.contains("%s Well fed and watered" % ctx.hud._signed(float(morale.WELL_FED))), "the reasons are the rules': %s" % _refs(ctx).mood_word.tooltip_text)
	eq(Kit.card(ctx, ana).marks.get_child_count(), 0, "no mark on the card while steady")
	morale.set_value(ana, float(morale.SHAKEN_BELOW) - 12.0)
	Kit.update(ctx)
	eq(_refs(ctx).mood_word.text, "Shaken", "shaken below %d" % int(morale.SHAKEN_BELOW))
	eq(_refs(ctx).mood_bar.color, Hud.MOOD_COLORS.Shaken, "the bar goes amber")
	var marks: Array = Kit.card(ctx, ana).marks.get_children()
	eq(marks.size(), 1, "and the card has the mood mark")
	if marks.size() == 1:
		eq(marks[0].texture, ctx.hud.icons["mood"], "the face")
		check(marks[0].tooltip_text.contains("Shaken"), "with the rules' own tip: '%s'" % marks[0].tooltip_text)
	var cost := roundi(float(morale.PERF_SHAKEN) * 100.0)
	check(_refs(ctx).mood_word.tooltip_text.contains("Works and aims at %d%% of their best" % cost), "and the cost: '%s'" % _refs(ctx).mood_word.tooltip_text)
	# a shock is listed while it fades
	morale.shock(ana, -12.0, "Marcus is down")
	Kit.update(ctx)
	check(_refs(ctx).mood_word.tooltip_text.contains("-12 Marcus is down (fading)"), "a shock: '%s'" % _refs(ctx).mood_word.tooltip_text)
	morale.set_value(ana, float(morale.BREAKING_BELOW) - 8.0)
	Kit.update(ctx)
	eq(_refs(ctx).mood_word.text, "Breaking", "breaking below %d" % int(morale.BREAKING_BELOW))
	eq(Kit.card(ctx, ana).marks.get_child(0).modulate, Hud.DANGER, "a red mark")
	Kit.free_all(ctx)


func test_with_the_real_morale_a_breakdown_shows_in_the_panel_the_card_and_the_orders() -> void:
	var ctx := _real()
	var ana = _open(ctx, "ana")
	var morale = ctx.sim.morale
	ctx.sim.day = int(morale.BREAKDOWN_FROM_DAY) + 1
	morale.shock(ana, -(morale.value(ana) - float(morale.BREAKDOWN_BELOW) + 4.0), "A terrible night")
	check(ctx.sim.morale.breakdown(ana), "the rules say she has broken down")
	Kit.update(ctx)
	eq(_refs(ctx).mood_word.text, "Breakdown", "the word")
	eq(_refs(ctx).doing.text, "Having a breakdown", "the Doing line")
	check(_refs(ctx).mood_word.tooltip_text.split("\n")[0].contains("breakdown"), "the tooltip leads with it")
	eq(ctx.hud.why_not("post"), "Ana is having a breakdown", "no orders")
	var marks: Array = Kit.card(ctx, ana).marks.get_children()
	check(marks.size() == 1 and marks[0].tooltip_text.contains("breakdown"), "and the card says so: %s" % str(marks.size()))
	Kit.free_all(ctx)


func test_with_the_real_skills_a_gain_shows_the_moment_it_is_made() -> void:
	var ctx := _real()
	var marcus = _open(ctx, "marcus")
	var cells: Dictionary = _refs(ctx).skills
	var start := int(marcus.def.skills.Shooting)
	eq(cells.Shooting.value.text, str(start), "the roster's number to begin with")
	check(not cells.Shooting.gain.visible, "no gain yet")
	var per := float(ctx.sim.skills.KINDS.kills.per)
	ctx.sim.skills.credit(marcus, "kills", per)
	Kit.update(ctx)
	eq(cells.Shooting.value.text, str(start + 1), "a point of Shooting once the kills make one (a quick learner gets there sooner, and does)")
	eq(cells.Shooting.gain.text, "+1", "with the gain beside it")
	var tip: String = cells.Shooting.box.tooltip_text
	check(tip.contains("started at %d" % start), "and where it started: '%s'" % tip)
	check(tip.contains("%d kills" % roundi(per)), "what makes it grow, from the rules' table: '%s'" % tip)
	var xp := roundi((ctx.sim.traits.mult(marcus, "xp") - 1.0) * 100.0)
	check(xp > 0 and tip.contains("Learns %d%% faster" % xp), "and what the Quick learner trait does to it: '%s'" % tip)
	check(marcus.stats.kills > 0 and _refs(ctx).name.tooltip_text.contains("Kills: %d" % marcus.stats.kills), "the kills are on his name: '%s'" % _refs(ctx).name.tooltip_text)
	Kit.free_all(ctx)


func test_with_the_real_modules_the_tutorial_keeps_its_panel_quiet() -> void:
	var ctx := _real()
	ctx.sim.morale.enabled = false
	_open(ctx, "ruth")
	check(not _refs(ctx).mood_head.visible, "no mood row while morale is off")
	check(_refs(ctx).traits_head.visible and _refs(ctx).bonds_head.visible, "but the traits and the bonds stay")
	Kit.free_all(ctx)


# -------------------------------------------------- layout: the dock still fits --

func _rects(ctx: Dictionary) -> Dictionary:
	var h = ctx.hud
	return {
		"stores": Kit.rect(h.res_panel), "legend": Kit.rect(h.fields_legend), "cards": Kit.rect(h.bar), "clock": Kit.rect(h.clock),
		"alerts": Kit.rect(h.alerts_box), "selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos), "speed": Kit.rect(h.speed_panel),
	}


## Somebody selected in the worst state the panel can be in: every row filled, a fever, both tags,
## nine buttons, a shaken mood, a skill that has grown.
func _packed(width: int, height: int, id: String) -> Dictionary:
	var ctx := Kit.build(width, height)
	var p = Kit.person(ctx, id)
	ctx.sim.medical.treat[p.id] = true
	ctx.sim.medical.sendout[p.id] = true
	ctx.sim.medical.stage[p.id] = "feverish"
	ctx.sim.scavenge.can = true
	ctx.sim.workshop.at_bench[p.id] = true
	ctx.sim.morale.values[p.id] = 30.0
	ctx.sim.skills.table[p.id] = {"Shooting": 3, "Building": 3, "Medicine": 3}
	for skill in ["Shooting", "Building", "Medicine"]:
		p.skills[skill] = 10
	p.hunger_h = 40.0
	p.thirst_h = 30.0
	p.wounds = 3
	p.bleeding = 4.0
	p.activity = "Making ammo at the worktable"
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 60.0)
	ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 60.0)
	Kit.select(ctx, p)
	Kit.update(ctx)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	return ctx


func test_the_full_panel_fits_the_dock_at_every_size_for_every_person() -> void:
	for size in SIZES:
		for id in ["ruth", "dez", "ana", "marcus", "walt", "hector"]:
			var ctx: Dictionary = await _packed(size[0], size[1], id)
			var where := "%s at %d x %d" % [id, size[0], size[1]]
			eq(Kit.gizmo_ids(ctx).size(), 9, "%s: all nine buttons" % where)
			eq(Kit.overlaps(_rects(ctx)), [], where)
			var win := Rect2(0, 0, size[0], size[1])
			var panel := Kit.rect(ctx.hud.inspect)
			check(win.encloses(panel.grow(-0.5)), "%s: the panel is inside the window (%s)" % [where, str(panel)])
			check(ctx.hud.inspect.get_combined_minimum_size().x <= float(Hud.INSPECT_W), "%s: and does not ask for more than its width (%s)" % [where, str(ctx.hud.inspect.get_combined_minimum_size())])
			if not ctx.hud.dock.vertical:
				eq(panel.size.x, float(Hud.INSPECT_W), "%s: and keeps its width" % where)
			check(win.encloses(Kit.rect(ctx.hud.gizmos).grow(-0.5)), "%s: the buttons too" % where)
			Kit.free_all(ctx)


func test_the_big_buttons_stay_at_700_by_700_with_the_full_panel() -> void:
	# the panel is as tall as it was before round 4 in its worst state (a fever and both tags): the buttons did not shrink for it
	var ctx: Dictionary = await _packed(700, 700, "ana")
	check(not ctx.hud.gizmo_mini, "the big buttons at 700 x 700")
	check(Kit.texts(Kit.gizmo(ctx, "treat")).has("TREAT"), "with their names")
	Kit.free_all(ctx)


func test_every_row_is_in_the_panel_in_its_worst_state() -> void:
	var ctx: Dictionary = await _packed(1280, 800, "ruth")
	var refs := _refs(ctx)
	for part in [refs.mood_head, refs.traits_head, refs.bonds_head, refs.infection_head]:
		check(part.visible, "%s shows" % part.text)
	check(refs.job_tag.visible and refs.craft_tag.visible, "both tags")
	var all := Kit.texts(ctx.hud.inspect)
	for caption in ["HEALTH", "MOOD", "WEAPON", "DOING", "NEEDS", "WOUNDS", "INFECTION", "TRAITS", "BONDS"]:
		check(all.has(caption), "%s has its row" % caption)
	Kit.free_all(ctx)


func test_the_panel_does_not_change_height_as_the_mood_moves() -> void:
	# a row that came and went would push the buttons about while the player watches
	var ctx := Kit.build(700, 700)
	var ana = _open(ctx, "ana")
	await Kit.settle()
	var heights: Array = []
	for v in [85.0, 60.0, 30.0, 10.0]:
		ctx.sim.morale.values[ana.id] = v
		Kit.update(ctx)
		await Kit.settle()
		heights.append(Kit.rect(ctx.hud.inspect).size.y)
	for h in heights:
		near(h, heights[0], 0.01, "the panel's height at each mood: %s" % str(heights))
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the text --

func test_the_new_words_read_on_the_boards_they_sit_on() -> void:
	var tt := TextTests.new()
	for frames in [true, false]:
		Hud.use_frames = frames
		var look := "frames" if frames else "flat"
		for state in ["Inspired", "Steady", "Shaken", "Breaking", "Breakdown", "Memorial"]:
			var ctx := Kit.build(1280, 800)
			var p = Kit.person(ctx, "marcus")
			match state:
				"Inspired":
					ctx.sim.morale.values[p.id] = 90.0
				"Shaken":
					ctx.sim.morale.values[p.id] = 30.0
				"Breaking":
					ctx.sim.morale.values[p.id] = 10.0
				"Breakdown":
					ctx.sim.morale.values[p.id] = 5.0
					ctx.sim.morale.broke[p.id] = true
				"Memorial":
					p.dead = true
			ctx.sim.skills.table[p.id] = {"Shooting": 1, "Building": 1}
			Kit.select(ctx, p)
			Kit.update(ctx, 0)
			eq(tt._hard_to_read(ctx.hud, Color.WHITE), [], "%s, %s: every word reads over the brightest ground" % [look, state])
			Kit.free_all(ctx)
	Hud.use_frames = true


func test_the_mood_colours_read_on_the_panel() -> void:
	for mood in Hud.MOOD_TEXT:
		var ratio := TextTests.contrast(Hud.MOOD_TEXT[mood], TextTests.over(Hud.PANEL, Color.WHITE))
		check(ratio >= TextTests.AA, "%s as a word is %.2f:1" % [mood, ratio])
	for mood in Hud.MOOD_COLORS:
		var ratio := TextTests.contrast(Hud.MOOD_COLORS[mood], Color(Hud.PANEL, 1.0))
		check(ratio >= 3.0, "%s as a bar is %.2f:1: it reads as a graphic" % [mood, ratio])


func test_nothing_in_the_new_rows_is_under_twelve_pixels() -> void:
	var tt := TextTests.new()
	for size in SIZES:
		var ctx: Dictionary = await _packed(size[0], size[1], "marcus")
		eq(tt._small_text(ctx.hud), [], "%d x %d" % [size[0], size[1]])
		ctx.sim.morale.values["marcus"] = 90.0
		Kit.person(ctx, "marcus").dead = true
		Kit.update(ctx)
		eq(tt._small_text(ctx.hud), [], "%d x %d, remembered" % [size[0], size[1]])
		Kit.free_all(ctx)


func test_no_new_word_is_in_the_dark_red() -> void:
	var tt := TextTests.new()
	var ctx: Dictionary = await _packed(1280, 800, "ana")
	ctx.sim.morale.values["ana"] = 5.0
	ctx.sim.morale.broke["ana"] = true
	Kit.update(ctx)
	eq(tt._dark_red_words(ctx.hud), [], "a breakdown's words")
	Kit.free_all(ctx)
