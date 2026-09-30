extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700]]


## A game where a party can go, the three sites are on offer and Ana is selected.
func _ready_to_send(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := Kit.build(width, height)
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.list = Kit.sample_sites()
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx)
	return ctx


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func test_the_dialog_lists_the_sites_with_their_details() -> void:
	var ctx := _ready_to_send()
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	check(d != null, "the dialog opens")
	eq(d.site_cards.keys(), ["pharmacy", "hardware", "houses"], "three sites, in order")
	var all := Kit.texts(d)
	for t in ["Send a scavenging party", "The pharmacy", "The hardware store", "Neighbourhood houses", "Shelves stripped, but the back room was locked.", "Picked over"]:
		check(all.has(t), "shows \"%s\"" % t)
	eq(d.site_cards.pharmacy.pips, 2, "the pharmacy is danger 2")
	eq(d.site_cards.houses.pips, 1, "the houses are danger 1")
	check(d.site_cards.pharmacy.available and not d.site_cards.hardware.available, "the hardware store is picked over")
	Kit.free_all(ctx)


func test_the_selected_person_leads_and_one_other_can_join() -> void:
	var ctx := _ready_to_send()
	var ana = Kit.person(ctx, "ana")
	var dez = Kit.person(ctx, "dez")
	var walt = Kit.person(ctx, "walt")
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	eq(d.first, ana, "Ana leads")
	eq(d.second, null, "nobody else yet")
	check(not d.candidates.has(ana.id), "she is not offered as her own partner")
	check(d.candidates.has(dez.id) and d.candidates.has(walt.id), "the others are")
	d.toggle_second(dez)
	eq(d.second, dez, "Dez joins")
	d.toggle_second(walt)
	eq(d.second, walt, "at most two: Walt replaces Dez")
	d.toggle_second(walt)
	eq(d.second, null, "asking again drops him")
	Kit.free_all(ctx)


func test_people_who_cannot_go_are_not_offered() -> void:
	var ctx := _ready_to_send()
	Kit.person(ctx, "dez").downed = true
	Kit.person(ctx, "walt").dead = true
	Kit.person(ctx, "marcus").away = {"kind": "party"}
	Kit.person(ctx, "hector").drafted = true
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	eq(d.candidates.keys(), ["ruth"], "only Ruth is free besides Ana")
	Kit.free_all(ctx)


func test_send_waits_for_a_site_and_then_sends_the_party() -> void:
	var ctx := _ready_to_send()
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	check(d.send_button.disabled, "Send is off until a place is chosen")
	d.choose_site("houses")
	check(not d.send_button.disabled, "then it is on")
	d.toggle_second(Kit.person(ctx, "dez"))
	d.send_button.pressed.emit()
	eq(ctx.sim.scavenge.sent, [{"ids": ["ana", "dez"], "site": "houses"}], "the party and the place reach the scavenging module")
	check(ctx.hud.scavenge_dialog == null, "the dialog closes")
	Kit.free_all(ctx)


func test_a_lone_scavenger_can_go_too() -> void:
	var ctx := _ready_to_send()
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	d.choose_site("pharmacy")
	d.send_button.pressed.emit()
	eq(ctx.sim.scavenge.sent, [{"ids": ["ana"], "site": "pharmacy"}], "Ana alone")
	Kit.free_all(ctx)


func test_a_picked_over_site_cannot_be_chosen() -> void:
	var ctx := _ready_to_send()
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	d.choose_site("hardware")
	eq(d.site_id, "", "not chosen")
	check(d.send_button.disabled, "so Send stays off")
	d.choose_site("pharmacy")
	d.choose_site("hardware")
	eq(d.site_id, "pharmacy", "and the choice before it stands")
	Kit.free_all(ctx)


func test_cancel_and_escape_close_without_sending() -> void:
	var ctx := _ready_to_send()
	ctx.hud.open_scavenge(ctx.hud.selection)
	ctx.hud.scavenge_dialog.cancel_button.pressed.emit()
	check(ctx.hud.scavenge_dialog == null, "Cancel closes it")
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	d.choose_site("houses")
	d._input(_key(KEY_ESCAPE))
	check(ctx.hud.scavenge_dialog == null, "so does Esc")
	eq(ctx.sim.scavenge.sent, [], "nobody was sent")
	Kit.free_all(ctx)


func test_enter_sends_once_a_site_is_chosen() -> void:
	var ctx := _ready_to_send()
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	d._input(_key(KEY_ENTER))
	eq(ctx.sim.scavenge.sent, [], "Enter does nothing before a place is chosen")
	d.choose_site("houses")
	d._input(_key(KEY_ENTER))
	eq(ctx.sim.scavenge.sent.size(), 1, "then it sends")
	Kit.free_all(ctx)


func test_when_nobody_can_go_the_dialog_says_why() -> void:
	var ctx := Kit.build()
	ctx.sim.scavenge.can = false
	ctx.sim.scavenge.reason = "Too late: parties leave between 06:30 and 10:00."
	ctx.sim.scavenge.list = Kit.sample_sites()
	Kit.select(ctx, Kit.person(ctx, "ana"))
	Kit.update(ctx)
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	check(Kit.texts(d).has("Too late: parties leave between 06:30 and 10:00."), "the reason is shown")
	check(d.site_cards.is_empty(), "with no sites to pick")
	check(d.send_button == null or d.send_button.disabled or not d.send_button.visible, "and nothing to send")
	d.cancel_button.pressed.emit()
	check(ctx.hud.scavenge_dialog == null, "it can still be closed")
	Kit.free_all(ctx)


func test_a_refused_send_keeps_the_dialog_open_and_says_so() -> void:
	var ctx := _ready_to_send()
	ctx.sim.scavenge.send_ok = false
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	d.choose_site("houses")
	d.send_button.pressed.emit()
	check(ctx.hud.scavenge_dialog != null, "still open")
	check(d.error_label.visible and d.error_label.text != "", "with a line about it")
	Kit.free_all(ctx)


func test_without_a_selected_person_the_first_free_survivor_leads() -> void:
	var ctx := Kit.build()
	ctx.sim.scavenge.can = true
	ctx.sim.scavenge.list = Kit.sample_sites()
	Kit.update(ctx)
	ctx.hud.open_scavenge(null)
	var d = ctx.hud.scavenge_dialog
	eq(d.first, Kit.person(ctx, "ruth"), "Ruth is first in the crew")
	Kit.free_all(ctx)


func test_a_selected_person_who_cannot_go_is_replaced_by_one_who_can() -> void:
	var ctx := _ready_to_send()
	Kit.person(ctx, "ana").downed = true
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	eq(d.first, Kit.person(ctx, "ruth"), "Ruth leads instead")
	check(Kit.texts(d).has("Ana can't go out now."), "and the dialog says why Ana is not in it")
	Kit.free_all(ctx)


func test_the_dialog_pauses_the_game_and_gives_the_speed_back() -> void:
	var ctx := _ready_to_send()
	Kit.update(ctx, 2)
	ctx.hud.open_scavenge(ctx.hud.selection)
	eq(ctx.speeds, [0], "paused on open")
	ctx.hud.scavenge_dialog.cancel_button.pressed.emit()
	eq(ctx.speeds, [0, 2], "and back to the old speed on close")
	ctx.speeds.clear()
	Kit.update(ctx, 0)
	ctx.hud.open_scavenge(ctx.hud.selection)
	ctx.hud.scavenge_dialog.cancel_button.pressed.emit()
	eq(ctx.speeds, [], "a game that was paused stays paused")
	Kit.free_all(ctx)


func test_opening_it_twice_does_not_stack_dialogs() -> void:
	var ctx := _ready_to_send()
	ctx.hud.open_scavenge(ctx.hud.selection)
	var first = ctx.hud.scavenge_dialog
	ctx.hud.open_scavenge(ctx.hud.selection)
	eq(ctx.hud.scavenge_dialog, first, "the same dialog")
	Kit.free_all(ctx)


func test_a_site_without_a_picture_gets_a_placeholder() -> void:
	var ctx := _ready_to_send()
	var sites := Kit.sample_sites()
	sites[0]["image"] = "res://assets/ui/sites/there-is-no-such-picture.png"
	sites[1]["image"] = ""
	ctx.sim.scavenge.list = sites
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	check(d.site_cards.pharmacy.image.texture == null and d.site_cards.pharmacy.placeholder.visible, "a missing file")
	check(d.site_cards.hardware.image.texture == null and d.site_cards.hardware.placeholder.visible, "no path at all")
	if FileAccess.file_exists("res://assets/ui/sites/houses.png"):
		check(d.site_cards.houses.image.texture != null and not d.site_cards.houses.placeholder.visible, "a picture that exists is shown")
	Kit.free_all(ctx)


func test_the_loot_is_shown_with_its_amounts() -> void:
	var ctx := _ready_to_send()
	ctx.hud.open_scavenge(ctx.hud.selection)
	var all := Kit.texts(ctx.hud.scavenge_dialog)
	check(all.has("3–6"), "meds 3 to 6")
	check(all.has("8–14") and all.has("10–20"), "food and water at the houses")
	check(all.has("sometimes"), "and what comes now and then")
	Kit.free_all(ctx)


func test_the_dialog_fits_the_window_at_every_width() -> void:
	for size in SIZES:
		var ctx := _ready_to_send(size[0], size[1])
		ctx.hud.open_scavenge(ctx.hud.selection)
		ctx.hud.scavenge_dialog.choose_site("houses")
		ctx.hud.scavenge_dialog.toggle_second(Kit.person(ctx, "dez"))
		await Kit.settle()
		await Kit.settle()
		var d = ctx.hud.scavenge_dialog
		var win := Rect2(0, 0, size[0], size[1])
		var named := {"panel": Kit.rect(d.panel), "send": Kit.rect(d.send_button), "cancel": Kit.rect(d.cancel_button)}
		for id in d.site_cards:
			named["card " + id] = Kit.rect(d.site_cards[id].card)
		for name in named:
			var r: Rect2 = named[name]
			check(r.size != Vector2.ZERO, "%s is shown at %d px" % [name, size[0]])
			check(win.encloses(r.grow(-0.5)), "%s inside the %d px window: %s" % [name, size[0], str(r)])
		# the buttons sit in the panel, and the cards do not overlap each other
		var inner := {}
		for id in d.site_cards:
			inner["card " + id] = named["card " + id]
		inner["send"] = named.send
		inner["cancel"] = named.cancel
		eq(Kit.overlaps(inner), [], "%d px: cards and buttons apart" % size[0])
		check(named.panel.encloses(named.send) and named.panel.encloses(named.cancel), "the buttons are inside the panel")
		Kit.free_all(ctx)


func test_the_mouse_picks_a_place_a_partner_and_sends() -> void:
	var ctx := _ready_to_send()
	ctx.hud.open_scavenge(ctx.hud.selection)
	var d = ctx.hud.scavenge_dialog
	await Kit.settle()
	await Kit.settle()
	Kit.click_on(d.site_cards.houses.card)
	eq(d.site_id, "houses", "a click on a place chooses it")
	Kit.click_on(d.site_cards.hardware.card)
	eq(d.site_id, "houses", "a picked over place does not take the choice")
	Kit.click_on(d.candidates.dez.row)
	eq(d.second, Kit.person(ctx, "dez"), "a click on a survivor brings them")
	Kit.click_on(d.candidates.dez.row)
	eq(d.second, null, "and another takes them out again")
	Kit.click_on(d.candidates.ruth.row)
	Kit.click_on(d.send_button)
	eq(ctx.sim.scavenge.sent, [{"ids": ["ana", "ruth"], "site": "houses"}], "the Send button sends the party")
	Kit.free_all(ctx)


func test_clicks_do_not_reach_the_game_behind_the_dialog() -> void:
	var ctx := _ready_to_send()
	ctx.hud.open_scavenge(ctx.hud.selection)
	await Kit.settle()
	var behind: Button = Kit.gizmo(ctx, "draft")
	Kit.click_on(behind)
	eq(ctx.pressed, [], "the Draft button under the dim does not fire")
	Kit.free_all(ctx)
