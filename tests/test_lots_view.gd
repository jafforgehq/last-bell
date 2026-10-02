extends "res://tests/case.gd"
## Round 9, the view of the lots (VIEW): the Build screen's Lots page (a card for each lot, Claim, the reasons), the map of the
## block with the ring plots and the mouths as pins, a mouth's card (the kits that fit across the street, a wall going up, a
## wall that stands and its health), the Duty roster's night posts of the lots, the HUD's card of a lot's wall, the hint, and the
## walls' art in the world (a wall built is drawn, a load takes it away and draws it again). The rules are tests/test_lots.gd's
## (the core's): here the game is the HUD kit's with the real lots (assets/data/lots.json) and the real buildings and jobs.

const Kit := preload("res://tests/hud_kit.gd")
const Helpers := preload("res://tests/helpers.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Lots := preload("res://scripts/sim/lots.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const BuildNode := preload("res://scripts/render/build_node.gd")

const SIZES := [[700, 700], [980, 700], [1280, 800], [1920, 1080]]


# ------------------------------------------------------------------ the kit --

## The mouse put in a corner where no control is (a pointer left over a button by an earlier test would let its tooltip come up).
func _park_the_mouse() -> void:
	var root: Window = Engine.get_main_loop().root
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(1, 1)
	ev.global_position = Vector2(1, 1)
	root.push_input(ev, true)


## A settlement game (the small start, with lots) on day `day` with `scrap` in the stores, the HUD set up and the Build screen open
## on `plot` (the default one when it is ""). `crew` 6 is the classic start.
func _open(width: int = 1280, height: int = 800, plot: String = "", scrap: float = 400.0, day: int = 4, crew: int = 3) -> Dictionary:
	_park_the_mouse()
	var ctx := Kit.build(width, height, 1, false, crew)
	var sim = ctx.sim
	sim.day = day
	sim.stock.scrap = scrap
	Kit.update(ctx, 1)
	ctx.hud.open_build(plot)
	return ctx


## A game with the lot's claim possible: places cleared on the town board (n of them).
func _clear_places(sim, n: int) -> void:
	var i := 0
	for id in sim.town.state:
		if i >= n:
			return
		sim.town.state[id].cleared = true
		i += 1


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev


func _press(code: Key) -> void:
	var root: Window = Engine.get_main_loop().root
	var down := _key(code)
	root.push_input(down, false)
	var up := _key(code)
	up.pressed = false
	root.push_input(up, false)


## The texts of the labels under `node` that can be seen (a hidden control's words are not on the page).
func _seen(node: Node, out: Array = []) -> Array:
	if node is CanvasItem and not node.visible:
		return out
	if node is Label:
		out.append(node.text)
	for c in node.get_children():
		_seen(c, out)
	return out


func _has_text(node: Node, part: String) -> bool:
	for t in _seen(node):
		if String(t).contains(part):
			return true
	return false


# ------------------------------------------------------------ the Lots page --

func test_a_classic_game_has_no_lots_page_and_no_map() -> void:
	var ctx := _open(1280, 800, "", 100.0, 4, 6)
	var s = ctx.hud.build_screen
	check(not ctx.sim.lots.on, "(the classic start has no lots)")
	check(s != null and not s.lots_on, "the screen knows it")
	check(s.lots_row == null, "no Lots slip")
	check(s.map != null and s.map_block_button == null and s.map_yard_button == null and not s.map.whole, "a small map of the yard (round 15), with no choice of the whole block")
	eq(s.rows.size(), ctx.sim.build.plots().size(), "a slip for each building and no more")
	check(not _has_text(s, "Lots"), "no word of lots")
	Kit.free_all(ctx)


func test_a_settlement_game_has_the_lots_slip_the_plots_and_the_map() -> void:
	var ctx := _open()
	var s = ctx.hud.build_screen
	check(ctx.sim.lots.on and s.lots_on, "lots are on")
	check(s.lots_row != null and s.lots_row.is_visible_in_tree(), "a slip for the Lots page")
	check(s.map != null and s.map.is_visible_in_tree(), "a map of the compound")
	var yard: Array = _yard_ids(ctx.sim)
	check(not yard.is_empty() and s.rows.has(yard[0]) and s.rows[yard[0]].row.visible, "the yard's plots are listed")
	var ring := _ring(ctx.sim, "north")
	check(s.rows.has(ring) and not s.rows[ring].row.visible, "a lot's plots are known to the list but not shown until it is claimed")
	for m in ctx.sim.lots.mouths():
		check(not s.rows.has(String(m.id)), "the street %s is a pin on the map, with no slip in the list" % String(m.id))
	Kit.free_all(ctx)


func test_the_lots_page_has_a_card_for_each_lot_with_its_terms() -> void:
	var ctx := _open(1280, 800, "@lots")
	var s = ctx.hud.build_screen
	eq(s.selected, "@lots", "the page is chosen")
	eq(s.lot_cards.keys(), ["north", "west", "east"], "a card for each lot, in the data's order")
	var north: Dictionary = s.lot_cards.north
	check(_has_text(north.card, "The north street"), "its name")
	check(_has_text(north.card, "Six ways in to shut"), "its blurb")
	check(_has_text(north.card, "%d scrap" % int(ctx.sim.lots.lot("north").claim.scrap)), "its price in scrap")
	check(_has_text(north.card, "day 3"), "the day it needs")
	check(_has_text(north.card, "1 place"), "the places cleared it needs")
	var page_text := " ".join(_seen(s.lots_view))
	check(page_text.contains("Shut every street") and page_text.contains("10 of 10 open"), "what the lots are for, and how many streets are open: %s" % page_text)
	Kit.free_all(ctx)


func test_a_lot_that_cannot_be_claimed_says_why_and_its_button_is_off_but_not_hidden() -> void:
	var ctx := _open(1280, 800, "@lots", 400.0, 2)
	var s = ctx.hud.build_screen
	var north: Dictionary = s.lot_cards.north
	var why: String = ctx.sim.lots.why_not_claim("north")
	check(why.contains("day 3"), "(the day is the first thing it wants: %s)" % why)
	check(north.claim.is_visible_in_tree() and north.claim.disabled, "the Claim button is there and off")
	eq(north.why.text, why.substr(0, 1).to_upper() + why.substr(1) + ".", "the reason is on a line under it")
	eq(north.claim.tooltip_text, north.why.text, "and is its tooltip")
	var before: float = float(ctx.sim.stock.scrap)
	check(not s.claim_lot("north"), "a claim that is refused")
	eq(float(ctx.sim.stock.scrap), before, "costs nothing")
	check(not ctx.sim.lots.claimed("north"), "and claims nothing")
	check(s.error_label.visible and s.error_label.text.contains("day 3"), "the page says why at its foot")
	# the places on the town board come next: the words the core gives
	ctx.sim.day = 4
	Kit.update(ctx, 1)
	s.refresh(true)
	check(north.why.text.contains("Clear 1 place on the town board first (0 so far)"), "the places: %s" % north.why.text)
	_clear_places(ctx.sim, 1)
	s.refresh(true)
	eq(north.why.text, "", "with everything in place there is no reason")
	check(not north.claim.disabled, "and the button is on")
	Kit.free_all(ctx)


func test_a_claim_from_the_screen_reaches_the_module() -> void:
	var ctx := _open(1280, 800, "@lots", 400.0, 4)
	var sim = ctx.sim
	_clear_places(sim, 1)
	var s = ctx.hud.build_screen
	s.refresh(true)
	var before: float = float(sim.stock.scrap)
	var price: float = float(sim.lots.lot("north").claim.scrap)
	s.lot_cards.north.claim.pressed.emit()
	check(sim.lots.claimed("north"), "the north lot is claimed")
	eq(float(sim.stock.scrap), before - price, "the price is paid")
	check(not s.lot_cards.north.claim.is_visible_in_tree(), "the Claim button gives way")
	check(_has_text(s.lot_cards.north.card, "CLAIMED"), "to the word: %s" % " ".join(_seen(s.lot_cards.north.card)))
	check(_has_text(s.lot_cards.north.card, "0 of 6 walls stand"), "and how many walls stand: %s" % " ".join(_seen(s.lot_cards.north.card)))
	check(_has_text(s.lot_cards.north.card, "streets are not all shut"), "and that its streets are not all shut")
	for id in sim.lots.lot("north").plots:
		check(s.rows[String(id)].row.visible, "its plot %s is on the list now" % String(id))
	for id in sim.lots.lot("west").plots:
		check(not s.rows[String(id)].row.visible, "another lot's (%s) are not" % String(id))
	check(s.lot_cards.west.claim.is_visible_in_tree(), "the other lots can still be claimed")
	Kit.free_all(ctx)


# ----------------------------------------------------------- the standing order --

const SWITCH_WORDS := "Wall the streets as the scrap allows"


## `ids` of the lots claimed (the conditions made up for them), the screen told.
func _claimed_game(ids: Array, scrap: float = 400.0, size: Array = [1280, 800]) -> Dictionary:
	var ctx := _open(size[0], size[1], "@lots", scrap, 4)
	_clear_places(ctx.sim, 3)
	ctx.sim.day = maxi(int(ctx.sim.day), 12)
	for id in ids:
		check(ctx.sim.lots.claim(String(id)), "(%s is claimed)" % String(id))
	ctx.sim.stock.scrap = scrap
	Kit.update(ctx, 1)
	ctx.hud.build_screen.refresh(true)
	return ctx


## The first kit that fits a mouth, as the id a wall is ordered by.
func _first_kit(sim, mouth_id: String) -> String:
	return String(sim.lots.mouth(mouth_id).kits[0])


## A ring plot of a lot (the data's order; the ids may move).
func _ring(sim, lot_id: String, i: int = 0) -> String:
	return String(sim.lots.lot(lot_id).plots[i])


## Every mouth of a lot has its wall, as the Builders would leave it.
func _wall_the_lot(sim, lot_id: String) -> void:
	for m in sim.lots.mouths_of(lot_id):
		_wall(sim, String(m.id), _first_kit(sim, String(m.id)))


func test_a_claimed_lots_card_has_the_switch_and_a_lot_that_is_not_has_none() -> void:
	var ctx := _open(1280, 800, "@lots", 400.0, 4)
	await Kit.settle()
	var s = ctx.hud.build_screen
	var sim = ctx.sim
	var north: Dictionary = s.lot_cards.north
	check(north.has("switch") and north.has("next"), "(the card has a switch and a line for the next street)")
	check(not north.switch.is_visible_in_tree() and not north.next.is_visible_in_tree(), "no switch before the claim")
	check(north.claim.is_visible_in_tree(), "(the claim is what it has)")
	_clear_places(sim, 1)
	s.refresh(true)
	check(s.claim_lot("north"), "(claimed from the screen)")
	await Kit.settle()
	check(north.switch.is_visible_in_tree() and not north.switch.button_pressed, "after the claim there is a switch, and it is off")
	check(_has_text(north.card, SWITCH_WORDS), "with its words: %s" % " ".join(_seen(north.card)))
	check(not north.claim.is_visible_in_tree(), "(the Claim button has given way)")
	check(not s.lot_cards.west.switch.is_visible_in_tree(), "another lot that is not claimed has none")
	check(not sim.lots.auto_walling("north"), "(the module's order is off)")
	north.switch.button_pressed = true
	check(sim.lots.auto_walling("north"), "turned on, the module's standing order is on")
	check(north.switch.button_pressed, "and the switch says so")
	north.switch.button_pressed = false
	check(not sim.lots.auto_walling("north"), "turned off, it is off again")
	# the module changes under the page: the switch follows
	sim.lots.set_auto_walling("north", true)
	s.refresh()
	check(north.switch.button_pressed, "the order was put on elsewhere (a load, a test): the switch follows")
	# the words are clickable too (a switch with its label)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	north.switch_label.gui_input.emit(click)
	check(not sim.lots.auto_walling("north"), "a click on the words turns it off")
	Kit.free_all(ctx)


func test_the_card_says_which_street_is_next_what_it_costs_and_that_it_waits_for_scrap() -> void:
	var ctx := _claimed_game(["north"])
	await Kit.settle()
	var s = ctx.hud.build_screen
	var sim = ctx.sim
	var c: Dictionary = s.lot_cards.north
	var street: String = sim.lots.next_street("north")
	check(street != "", "(a street is next)")
	var price: int = sim.lots.next_price("north")
	check(price > 0, "(it has a price)")
	var name: String = String(sim.lots.mouth(street).name)
	eq(c.next.text, "Next: %s, %d scrap" % [name, price], "the street and its price")
	check(c.next.is_visible_in_tree(), "and it is on the card")
	# the stores are short of it
	sim.stock.scrap = float(price) - 1.0
	s.refresh(true)
	check(c.next.text.begins_with("Next: %s, %d scrap" % [name, price]) and c.next.text.contains("Waiting for scrap"), "short of scrap it says so: %s" % c.next.text)
	sim.stock.scrap = 400.0
	s.refresh(true)
	check(not c.next.text.contains("Waiting"), "with the scrap it does not: %s" % c.next.text)
	# a wall going up across the next street: the one after it is next
	sim.stock.scrap = 900.0
	check(sim.build.order(street, sim.lots.best_kit(street)), "(the first street is ordered by hand)")
	s.refresh(true)
	var after: String = sim.lots.next_street("north")
	check(after != street and after != "", "(the next street is another)")
	eq(c.next.text, "Next: %s, %d scrap" % [String(sim.lots.mouth(after).name), sim.lots.next_price("north")], "the card moves on to it")
	# every street has its wall
	sim.build.cancel(street)
	_wall_the_lot(sim, "north")
	s.refresh(true)
	eq(c.next.text, "Every street has its wall", "nothing is left to wall")
	var m: int = sim.lots.mouths_of("north").size()
	eq(c.walls.text, "%d of %d walls stand" % [m, m], "all of them stand")
	check(_has_text(c.card, "Its streets are shut"), "and the lot is sealed: %s" % " ".join(_seen(c.card)))
	Kit.free_all(ctx)


func test_with_the_switch_on_the_lot_is_walled_street_by_street_and_the_card_follows() -> void:
	var ctx := _claimed_game(["north"], 600.0)
	await Kit.settle()
	var s = ctx.hud.build_screen
	var sim = ctx.sim
	sim.phase = "day"
	sim.bell_rung = false
	var c: Dictionary = s.lot_cards.north
	var first: String = sim.lots.next_street("north")
	sim.lots.update(Lots.AUTO_EVERY + 0.1)
	check(sim.build.plot(first).site.is_empty(), "the order is off: nothing is ordered")
	c.switch.button_pressed = true
	var before: float = float(sim.stock.scrap)
	sim.lots.update(Lots.AUTO_EVERY + 0.1)
	check(not sim.build.plot(first).site.is_empty(), "the switch on, the first street's wall is ordered")
	check(float(sim.stock.scrap) < before, "and paid for")
	s.refresh()
	var second: String = sim.lots.next_street("north")
	check(second != first, "(the next street is another)")
	check(c.next.text.contains(String(sim.lots.mouth(second).name)), "the card says which street is next: %s" % c.next.text)
	# the Builders finish it: the count moves, the next street is ordered in its turn
	var pl: Dictionary = sim.build.plot(first)
	pl.site.progress = float(pl.site.work)
	sim.build._finish(pl)
	sim.lots.update(Lots.AUTO_EVERY + 0.1)
	check(not sim.build.plot(second).site.is_empty(), "one wall after another")
	s.refresh()
	check(c.walls.text.begins_with("1 of "), "one wall stands: %s" % c.walls.text)
	Kit.free_all(ctx)


func test_a_mouth_has_no_slip_in_the_list_and_the_lists_plots_are_the_compounds_and_the_claimed_lots_ring_plots() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	var sim = ctx.sim
	for m in sim.lots.mouths():
		check(not s.rows.has(String(m.id)), "no slip for the mouth %s" % String(m.id))
	for l in sim.lots.lots():
		for id in l.plots:
			check(s.rows.has(String(id)) and not s.rows[String(id)].row.visible, "the ring plot %s has a slip, hidden until its lot is claimed" % String(id))
	_claim(ctx, ["north"])
	await Kit.settle()
	for id in sim.lots.lot("north").plots:
		check(s.rows[String(id)].row.visible, "claimed, the ring plot %s is listed" % String(id))
	for id in sim.lots.lot("west").plots:
		check(not s.rows[String(id)].row.visible, "another lot's are not")
	var slips := 0
	for id in s.rows:
		if id != "@lots":
			slips += 1
	var want: int = _yard_ids(sim).size()
	for l in sim.lots.lots():
		want += l.plots.size()
	eq(slips, want, "a slip for each plot of the compound and of every lot, and none for a street")
	Kit.free_all(ctx)


func test_the_card_of_an_open_mouth_offers_the_one_wall_the_standing_order_would_put_there() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	var sim = ctx.sim
	_claim(ctx, ["north"])
	await Kit.settle()
	await Kit.settle()
	var mouth := String(sim.lots.lot("north").mouths[0])
	var pin: Button = s.map.pins[mouth]
	check(pin.visible, "(the mouth's pin is on the map)")
	pin.pressed.emit()
	await Kit.settle()
	eq(s.selected, mouth, "a pin chooses the mouth")
	check(s.empty_view.visible and not s.site_view.visible and not s.built_view.visible and not s.lots_view.visible, "an open street shows the empty view")
	eq(s.plot_tag.text, "STREET WALL", "its tag")
	var best: String = sim.lots.best_kit(mouth)
	check(best != "", "(a kit fits)")
	var shown: Array = []
	for id in s.entries:
		if s.entries[id].card.visible:
			shown.append(String(id))
	eq(shown, [best], "one wall and no list of kits: %s" % str(shown))
	check(s.mouth_info.visible and s.mouth_info.text.contains("Street"), "the street's words are there: %s" % s.mouth_info.text)
	sim.stock.scrap = 3.0
	s.refresh(true)
	check(s.entries[best].order.disabled and s.entries[best].why.visible, "short of scrap its button is off with the reason")
	sim.stock.scrap = 300.0
	s.refresh(true)
	var before: float = float(sim.stock.scrap)
	s.entries[best].order.pressed.emit()
	eq(String(sim.build.plot(mouth).site.get("building", "")), best, "the order reaches the module with that kit")
	check(float(sim.stock.scrap) < before, "and pays")
	check(s.site_view.visible and not s.empty_view.visible, "the card shows the wall going up")
	Kit.free_all(ctx)


func test_the_keyboard_finds_a_mouth_without_a_slip_through_its_pin() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	var sim = ctx.sim
	_claim(ctx, ["north"])
	await Kit.settle()
	await Kit.settle()
	var mouth := String(sim.lots.lot("north").mouths[0])
	var pin: Button = s.map.pins[mouth]
	pin.grab_focus()
	_press(KEY_ENTER)
	eq(s.selected, mouth, "Enter on its pin chooses it")
	eq(_focus_owner(), pin, "the keyboard stays on the pin")
	_focus_owner().release_focus()
	s.focus_default()
	eq(_focus_owner(), pin, "with a street chosen and the keyboard nowhere, it goes to the street's pin")
	s.select_plot("@lots")
	_press(KEY_ESCAPE)
	Kit.free_all(ctx)


# ------------------------------------------------------------------- the map --

## `ids` of the lots claimed (the conditions made up for them), the screen told.
func _claim(ctx: Dictionary, ids: Array) -> void:
	var sim = ctx.sim
	ctx.hud.build_screen.select_plot("@lots")    # (a lot is claimed on the Lots page: the map shows the block there)
	_clear_places(sim, 3)
	sim.day = maxi(int(sim.day), 12)
	sim.stock.scrap = maxf(float(sim.stock.scrap), 400.0)
	for id in ids:
		check(sim.lots.claim(String(id)), "(%s is claimed)" % String(id))
	Kit.update(ctx, 1)
	ctx.hud.build_screen.refresh(true)


func _yard_ids(sim) -> Array:
	var out: Array = []
	for pl in sim.build.plots():
		if String(pl.get("lot", "")) == "":
			out.append(String(pl.id))
	return out


func test_the_map_shows_the_yard_until_a_lot_is_claimed_and_then_the_block() -> void:
	var ctx := _open()
	await Kit.settle()
	await Kit.settle()
	var s = ctx.hud.build_screen
	check(not s.map.whole and s.map_yard_button.button_pressed and not s.map_block_button.button_pressed, "the yard to begin with, and the toggle says so")
	var yard := _yard_ids(ctx.sim)
	eq(yard.size(), ctx.sim.build.plots().size(), "(before a claim every plot is the compound's)")
	var pins: Array = s.map.visible_pins()
	pins.sort()
	var want := yard.duplicate()
	want.sort()
	eq(pins, want, "a pin for each plot of the yard and none of the ring")
	# the player may look at the whole block before any claim: the lots' plots are there, faint, not to be pointed at
	s.map_block_button.pressed.emit()
	await Kit.settle()
	check(s.map.whole and s.map_block_button.button_pressed, "the toggle zooms out")
	eq(s.map.state_of(_ring(ctx.sim, "north")), "locked", "a plot of a lot that is not claimed is the shape of what a claim brings")
	eq(s.map.state_of("west_road_top"), "locked", "so is a mouth")
	pins = s.map.visible_pins()
	pins.sort()
	eq(pins, want, "and still only the yard's can be pointed at")
	s.map_yard_button.pressed.emit()
	await Kit.settle()
	check(not s.map.whole, "and back")
	Kit.free_all(ctx)


func test_after_a_claim_the_map_shows_the_block_for_the_streets_and_the_yard_for_the_yards_buildings_unless_the_player_chose() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_claim(ctx, ["north"])
	await Kit.settle()
	await Kit.settle()
	check(s.map.whole and s.map_block_button.button_pressed, "claimed on the Lots page: the whole block")
	s.select_plot(String(_yard_ids(ctx.sim)[0]))
	await Kit.settle()
	check(not s.map.whole and s.map_yard_button.button_pressed, "a building of the yard is chosen: the yard, whatever is claimed")
	s.select_plot("@lots")
	await Kit.settle()
	check(s.map.whole and s.map_block_button.button_pressed, "the Lots page: the whole block once a lot is claimed")
	var north: Dictionary = ctx.sim.lots.lot("north")
	var pins: Array = s.map.visible_pins()
	for id in north.plots + north.mouths:
		check(pins.has(String(id)), "a pin for %s" % String(id))
	for id in ctx.sim.lots.lot("west").plots + ctx.sim.lots.lot("west").mouths:
		check(not pins.has(String(id)), "none for %s of a lot that is not claimed" % String(id))
	eq(pins.size(), _yard_ids(ctx.sim).size() + north.plots.size() + north.mouths.size(), "the yard's, the lot's plots and its mouths")
	s.select_plot(String(_yard_ids(ctx.sim)[0]))
	await Kit.settle()
	check(not s.map.whole, "a building of the yard again: the yard")
	# the player's own choice stands
	s.map_yard_button.pressed.emit()
	_claim(ctx, ["west"])
	await Kit.settle()
	check(not s.map.whole, "the yard it was asked to be stays the yard")
	s.select_plot(_ring(ctx.sim, "west"))
	await Kit.settle()
	check(s.map.whole, "(a plot in the streets is chosen: the map shows it)")
	Kit.free_all(ctx)


func test_a_pin_chooses_its_plot_and_points_at_it_in_the_world() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_claim(ctx, ["north"])
	await Kit.settle()
	await Kit.settle()
	var pin: Button = s.map.pins.west_road_top
	check(pin.visible and pin.size.x >= 18.0 and pin.size.y >= 18.0, "a mouth's pin is big enough for the pointer: %s" % str(pin.size))
	check(pin.tooltip_text.contains("Top of the west road") and pin.tooltip_text.contains("open street"), "its tooltip says what it is: %s" % pin.tooltip_text)
	pin.pressed.emit()
	eq(s.selected, "west_road_top", "pressed, it chooses the plot")
	eq(s.map.selected, "west_road_top", "and the map knows")
	check(s.detail.is_visible_in_tree() and s.plot_title.text == "Top of the west road", "the card is the street's: %s" % s.plot_title.text)
	pin.mouse_entered.emit()
	eq(ctx.hud.build_hover, {"plot": "west_road_top"}, "pointing at a pin marks the plot in the world")
	pin.mouse_exited.emit()
	eq(ctx.hud.build_hover, {"plot": "west_road_top"}, "and leaving marks the chosen one's again")
	var ring := _ring(ctx.sim, "north")
	s.map.pins[ring].pressed.emit()
	eq(s.selected, ring, "a ring plot's pin too")
	check(s.rows[ring].row.get_meta("chosen", false), "and its slip is gold")
	Kit.free_all(ctx)


## A game with a wall going up at the west road, a wall that stands at the north-west end and a ring plot with a building.
func _stage(ctx: Dictionary) -> void:
	var sim = ctx.sim
	_claim(ctx, ["north", "west"])
	sim.stock.scrap = 900.0
	check(sim.build.order("west_road_top", "wall_container_n"), "(a wall is ordered at the west road)")
	sim.build.plot("west_road_top").site.progress = 9.0
	check(sim.build.order("north_west_end", "wall_bus_e"), "(and one at the west end)")
	var pl: Dictionary = sim.build.plot("north_west_end")
	pl.site.progress = float(pl.site.work)
	sim.build._finish(pl)
	sim.build.plot(_ring(sim, "north", 0)).building = "scrap_yard"
	sim.build.version += 1
	Kit.update(ctx, 1)
	ctx.hud.build_screen.refresh(true)


func test_the_map_marks_a_mouth_open_going_up_standing_and_down() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_stage(ctx)
	var m = s.map
	eq(m.state_of("north_east_end"), "open", "a mouth with nothing: open")
	eq(m.state_of("west_road_top"), "site", "with a wall going up: a site")
	eq(m.state_of("north_west_end"), "wall", "with a wall that stands: a wall")
	eq(m.state_of(_ring(ctx.sim, "north", 0)), "built", "a ring plot with a building")
	eq(m.state_of(_ring(ctx.sim, "west")), "empty", "and with none")
	check(m.mouth_color("north_east_end") == m.AMBER and m.mouth_color("west_road_top") == m.GOLD and m.mouth_color("north_west_end") == m.GREEN, "amber, gold and green")
	var seg = ctx.sim.lots.segment_at("north_west_end")
	check(seg != null, "(the wall has a section)")
	seg.hp = seg.max_hp * 0.5
	ctx.sim._segment_state(seg)
	check(m.mouth_color("north_west_end") == m.AMBER, "a worn wall is amber")
	ctx.sim._damage_segment(seg, seg.hp + 1.0)
	eq(int(seg.state), 3, "(it falls)")
	eq(m.state_of("north_west_end"), "down", "down")
	check(m.mouth_color("north_west_end") == m.RED, "red")
	check(m.tooltip_of("north_west_end").contains("wall down"), "and its tooltip says so: %s" % m.tooltip_of("north_west_end"))
	check(m.tooltip_of("west_road_top").contains("going up, 50%"), "a site's says how far: %s" % m.tooltip_of("west_road_top"))
	Kit.free_all(ctx)


# ------------------------------------------------------------ a ring plot and a mouth --

func test_a_ring_home_is_the_scrap_yards_and_takes_no_other_building_and_no_wall() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_claim(ctx, ["north"])
	var ring := _ring(ctx.sim, "north")
	var yard := String(_yard_ids(ctx.sim)[0])
	s.select_plot(ring)
	await Kit.settle()
	check(s.empty_view.visible and not s.site_view.visible and not s.built_view.visible, "a scrap yard not built is offered")
	var shown: Array = []
	for id in s.entries:
		if s.entries[id].card.visible:
			shown.append(String(id))
	eq(shown, ["scrap_yard"], "the scrap yard is the one building a ring home offers (and no wall: that is for a street)")
	eq(Kit.texts(s.plot_title), ["Scrap yard 1 of 2"], "numbered, as it has two homes")
	check(_has_text(s.detail, "North-east verge"), "its words say where it goes: %s" % " ".join(_seen(s.plot_sub)))
	s.select_plot(yard)
	check(not s.entries.scrap_yard.card.visible, "and the yard's buildings do not offer it")
	s.select_plot(ring)
	var before: float = float(ctx.sim.stock.scrap)
	check(s.order("scrap_yard"), "an order from the screen")
	check(ctx.sim.build.plot(ring).site.building == "scrap_yard" and float(ctx.sim.stock.scrap) < before, "reaches the module and pays")
	check(s.site_view.visible, "the card shows the site")
	Kit.free_all(ctx)


func test_the_wall_a_street_offers_says_what_it_is_costs_and_why_it_cannot_be_ordered() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_claim(ctx, ["north", "west"])
	ctx.sim.stock.scrap = 100.0
	s.select_plot("west_road_top")
	await Kit.settle()
	eq(s.plot_tag.text, "STREET WALL", "its tag")
	check(_has_text(s.plot_sub, "11 tiles wide"), "how wide the street is: %s" % s.plot_sub.text)
	var info: String = s.mouth_info.text
	check(s.mouth_info.visible and info.contains("Street 3 of 10") and info.contains("north"), "which street, and where its dead come from: %s" % info)
	check(info.contains("0 of 6 walls stand"), "and what lot it is part of: %s" % info)
	check(info.contains("standing order is off"), "and what the lot's standing order is: %s" % info)
	ctx.sim.lots.set_auto_walling("north", true)
	s.refresh()
	check(s.mouth_info.text.contains("standing order is on"), "which follows the switch: %s" % s.mouth_info.text)
	var best: String = ctx.sim.lots.best_kit("west_road_top")
	var kit: Dictionary = ctx.sim.lots.kit(best.trim_prefix("wall_"))
	var card: Control = s.entries[best].card
	var words := " ".join(_seen(card))
	check(words.contains(String(kit.name)) and words.contains("%d scrap" % int(kit.scrap)) and words.contains("%d builder-hours" % int(kit.work)) and words.contains("%d health" % int(kit.hp)), "name, price, hours and health: %s" % words)
	check(words.contains(String(kit.blurb).substr(0, 20)), "and what it is: %s" % words)
	# with too little scrap: the reason, the button off
	ctx.sim.stock.scrap = 20.0
	s.refresh(true)
	check(s.entries[best].order.disabled and s.entries[best].why.visible, "a wall that costs more than the stores have is refused with its reason")
	check(s.entries[best].why.text.contains("%d scrap" % int(kit.scrap)), "in words: %s" % s.entries[best].why.text)
	ctx.sim.stock.scrap = 200.0
	s.refresh(true)
	check(not s.entries[best].order.disabled, "with the scrap it can be ordered")
	s.entries[best].order.pressed.emit()
	var pl: Dictionary = ctx.sim.build.plot("west_road_top")
	eq(String(pl.site.get("building", "")), best, "the order reaches the module")
	near(float(ctx.sim.stock.scrap), 200.0 - float(kit.scrap), 1e-9, "and the scrap is paid")
	check(s.site_view.visible and not s.empty_view.visible, "the card shows the wall going up")
	check(_has_text(s.site_title, String(kit.name)), "its name: %s" % s.site_title.text)
	Kit.free_all(ctx)


func test_a_wall_going_up_shows_how_far_and_can_be_cancelled() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_stage(ctx)
	s.select_plot("west_road_top")
	await Kit.settle()
	check(s.site_view.visible, "a site")
	eq(s.site_percent.text, "50%", "half done")
	check(_has_text(s.site_done, "9 of 18 builder-hours"), "in hours: %s" % s.site_done.text)
	var half: float = float(ctx.sim.lots.kit("container_n").scrap) * 0.5
	check(s.cancel_button.text.contains("+%d" % int(half)), "Cancel gives half the scrap back: %s" % s.cancel_button.text)
	var before: float = float(ctx.sim.stock.scrap)
	s.cancel_button.pressed.emit()
	check(ctx.sim.build.plot("west_road_top").site.is_empty(), "cancelled")
	near(float(ctx.sim.stock.scrap), before + half, 1e-9, "half back")
	eq(s.map.state_of("west_road_top"), "open", "the street is open again on the map")
	Kit.free_all(ctx)


func test_a_wall_that_stands_shows_its_kit_and_health_and_is_not_demolished() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_stage(ctx)
	s.select_plot("north_west_end")
	await Kit.settle()
	check(s.built_view.visible and not s.empty_view.visible and not s.site_view.visible, "a wall that stands")
	eq(s.built_title.text, "School bus", "its kit")
	check(s.wall_box.visible and s.wall_text.text.contains("320 of 320 health"), "its health: %s" % s.wall_text.text)
	eq(s.wall_percent.text, "100%", "whole")
	check(not s.demolish_button.visible, "there is no Demolish: a wall is not pulled down")
	check(s.demolish_why.visible and s.demolish_why.text.contains("not pulled down"), "and it says so: %s" % s.demolish_why.text)
	check(s.mouth_info.text.contains("1 of 6 walls stand"), "the lot's count follows: %s" % s.mouth_info.text)
	var seg = ctx.sim.lots.segment_at("north_west_end")
	ctx.sim._damage_segment(seg, 120.0)
	ctx.hud.update_hud(ctx.sim, 1, true, 4)
	await Kit.settle()
	check(s.wall_text.text.contains("200 of 320 health") and s.wall_text.text.contains("Worn"), "worn, in words: %s" % s.wall_text.text)
	ctx.sim._damage_segment(seg, 130.0)
	ctx.hud.update_hud(ctx.sim, 1, true, 4)
	eq(s.wall_percent.text, "%d%%" % roundi(float(seg.hp) / float(seg.max_hp) * 100.0), "damage shows as the page follows the game")
	check(s.wall_text.text.contains("70 of 320 health") and s.wall_text.text.contains("Failing"), "in words: %s" % s.wall_text.text)
	ctx.sim._damage_segment(seg, 500.0)
	ctx.hud.update_hud(ctx.sim, 1, true, 4)
	check(s.wall_text.text.contains("Down") and s.wall_text.text.contains("street is open"), "a wall that is down says the street is open: %s" % s.wall_text.text)
	s.select_plot("@lots")
	check(_has_text(s.lot_cards.north.card, "0 of 6 walls stand"), "a wall that is down is not standing: %s" % " ".join(_seen(s.lot_cards.north.card)))
	Kit.free_all(ctx)


func test_the_lists_slips_say_what_is_on_a_ring_plot_and_a_mouth() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_stage(ctx)
	for m in ctx.sim.lots.mouths():
		check(not s.rows.has(String(m.id)), "(a mouth has no slip: %s)" % String(m.id))
	check(s.map.tooltip_of("west_road_top").contains("shipping container going up, 50%"), "a wall going up, how far, is on its pin: %s" % s.map.tooltip_of("west_road_top"))
	var yard := String(_yard_ids(ctx.sim)[0])
	eq(Kit.texts(s.rows[_ring(ctx.sim, "north", 0)].status), ["Built"], "a building on a ring home")
	eq(Kit.texts(s.rows[_ring(ctx.sim, "west")].status), ["28 scrap, 20 builder-hours"], "a scrap yard not built, what it costs")
	check(not s.rows[yard].tag.is_visible_in_tree() and not s.rows[_ring(ctx.sim, "west")].tag.is_visible_in_tree(), "no slip has a tag for a kind of lot (round 15)")
	eq(Kit.texts(s.rows["@lots"].status), ["2 of 3 claimed"], "the Lots slip says how many")
	check(s.lot_headers.north.visible and s.lot_headers.west.visible and not s.lot_headers.east.visible, "a caption for each lot that is claimed")
	Kit.free_all(ctx)


func test_pointing_at_a_lots_card_marks_the_whole_lot_in_the_world_and_on_the_map() -> void:
	var ctx := _open(1280, 800, "@lots")
	await Kit.settle()
	var s = ctx.hud.build_screen
	var card: Control = s.lot_cards.west.card
	card.mouse_entered.emit()
	eq(ctx.hud.build_hover, {"lot": "west"}, "the lot is marked")
	eq(s.map.lit_lot, "west", "and lit on the map")
	card.mouse_exited.emit()
	eq(ctx.hud.build_hover, {}, "and let go")
	eq(s.map.lit_lot, "", "on the map too")
	s.lot_cards.east.claim.focus_entered.emit()
	eq(ctx.hud.build_hover, {"lot": "east"}, "the keyboard on a Claim button marks it as well")
	s.lot_cards.east.claim.focus_exited.emit()
	eq(ctx.hud.build_hover, {}, "and leaving lets go")
	ctx.hud.close_build()
	eq(ctx.hud.build_hover, {}, "a page that is closed marks nothing")
	Kit.free_all(ctx)


# ------------------------------------------------------------------- the keyboard --

func _focus_owner() -> Control:
	return Engine.get_main_loop().root.gui_get_focus_owner()


func test_the_keyboard_goes_through_the_lots_page_to_a_claim() -> void:
	var ctx := _open(1280, 800, "@lots")
	await Kit.settle()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_clear_places(ctx.sim, 3)
	ctx.sim.day = 12
	s.refresh(true)
	await Kit.settle()
	_press(KEY_TAB)
	eq(_focus_owner(), s.rows["@lots"].row, "the first Tab puts the keyboard on the Lots slip, the page that is chosen")
	_press(KEY_RIGHT)
	eq(_focus_owner(), s.lot_cards.north.claim, "Right goes to the first Claim button that can be pressed")
	_press(KEY_DOWN)
	eq(_focus_owner(), s.lot_cards.west.claim, "an arrow down to the next")
	_press(KEY_UP)
	_press(KEY_LEFT)
	eq(_focus_owner(), s.rows["@lots"].row, "Left comes back to the slip")
	_press(KEY_RIGHT)
	_press(KEY_ENTER)
	await Kit.settle()
	check(ctx.sim.lots.claimed("north"), "Enter on Claim claims the lot")
	eq(_focus_owner(), s.rows["@lots"].row, "and the keyboard is back on the slip")
	_press(KEY_DOWN)
	eq(_focus_owner(), s.rows[String(_yard_ids(ctx.sim)[0])].row, "an arrow down goes on to the plots")
	Kit.free_all(ctx)


func test_enter_on_a_streets_pin_chooses_it_and_goes_to_its_wall_and_enter_there_orders_it() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	var sim = ctx.sim
	_claim(ctx, ["north"])
	await Kit.settle()
	await Kit.settle()
	var mouth := String(sim.lots.lot("north").mouths[0])
	var best: String = sim.lots.best_kit(mouth)
	var pin: Button = s.map.pins[mouth]
	pin.grab_focus()
	eq(_focus_owner(), pin, "the keyboard on the street's pin")
	_press(KEY_ENTER)
	await Kit.settle()
	eq(s.selected, mouth, "Enter chooses the street")
	eq(_focus_owner(), s.entries[best].order, "and goes on to the one wall it offers")
	_press(KEY_LEFT)
	eq(_focus_owner(), pin, "Left comes back to the street's pin (it has no slip)")
	_press(KEY_ENTER)
	await Kit.settle()
	eq(_focus_owner(), s.entries[best].order, "(and Enter goes on again)")
	_press(KEY_ENTER)
	await Kit.settle()
	eq(String(sim.build.plot(mouth).site.get("building", "")), best, "Enter there orders it")
	eq(_focus_owner(), pin, "and the keyboard is back on the pin, as it is on a slip after an order")
	_press(KEY_ESCAPE)
	Kit.free_all(ctx)


func test_the_pins_of_the_map_can_have_the_keyboard_and_enter_on_one_chooses_it() -> void:
	var ctx := _open()
	await Kit.settle()
	var s = ctx.hud.build_screen
	_claim(ctx, ["north"])
	await Kit.settle()
	await Kit.settle()
	var pin: Button = s.map.pins.north_east_end
	eq(pin.focus_mode, Control.FOCUS_ALL, "a pin takes the keyboard")
	pin.grab_focus()
	eq(ctx.hud.build_hover, {"plot": "north_east_end"}, "and, with it there, the plot is marked in the world")
	_press(KEY_ENTER)
	eq(s.selected, "north_east_end", "Enter chooses it")
	for id in s.map.pins:
		if s.map.pins[id].visible:
			eq(s.map.pins[id].focus_mode, Control.FOCUS_ALL, "pin %s can have the keyboard" % id)
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the page fits --

const BuildScreenTests := preload("res://tests/test_build_screen.gd")
const TextTests := preload("res://tests/test_hud_text.gd")


## The views of a lots game's detail: the Lots page, an empty ring plot, an empty mouth, a mouth with a wall going up, a wall that stands.
func _views(sim) -> Array:
	return [["the Lots page", "@lots"], ["an empty ring home", _ring(sim, "west")], ["an open mouth", "north_east_end"], ["a wall going up", "west_road_top"],
		["a wall that stands", "north_west_end"], ["a ring home with a building", _ring(sim, "north", 0)], ["a yard home not built", String(_yard_ids(sim)[0])]]


## A lots game in a window `size` with everything staged, settled.
func _settled(size: Array) -> Dictionary:
	var ctx := _open(size[0], size[1], "@lots", 900.0, 4)
	await Kit.settle()
	_stage(ctx)
	await Kit.settle()
	await Kit.settle()
	await Kit.settle()
	_park_the_mouse()
	await Kit.settle()
	return ctx


func test_the_page_fits_and_overlaps_nothing_at_700_980_1280_and_1920() -> void:
	var fit := BuildScreenTests.new()
	for size in SIZES:
		var ctx: Dictionary = await _settled(size)
		var s = ctx.hud.build_screen
		for view in _views(ctx.sim):
			s.select_plot(view[1])
			await Kit.settle()
			await Kit.settle()
			eq(fit._misfits(ctx, size), [], "%d x %d, %s" % [size[0], size[1], view[0]])
			# the map sits inside its card, its pins inside the map, and its legend beside it
			var card := Kit.rect(s.map_card)
			var m := Kit.rect(s.map)
			check(card.grow(0.5).encloses(m) and m.size.x >= 150.0 and m.size.y >= 150.0, "%d x %d, %s: the map %s is in its card %s" % [size[0], size[1], view[0], str(m), str(card)])
			for id in s.map.visible_pins():
				var pr := Kit.rect(s.map.pins[id])
				check(m.grow(0.5).encloses(pr), "%d x %d: the pin of %s %s is in the map %s" % [size[0], size[1], id, str(pr), str(m)])
		Kit.free_all(ctx)


func test_nothing_on_the_lots_page_is_under_twelve_pixels() -> void:
	var tt := TextTests.new()
	for size in [[1920, 1080], [1280, 800], [980, 700], [700, 700], [700, 560]]:
		var ctx: Dictionary = await _settled(size)
		var s = ctx.hud.build_screen
		for view in _views(ctx.sim):
			s.select_plot(view[1])
			await Kit.settle()
			eq(tt._small_text(s), [], "%d x %d, %s" % [size[0], size[1], view[0]])
		Kit.free_all(ctx)


func test_every_word_of_the_lots_views_reads_on_the_paper() -> void:
	var tt := TextTests.new()
	for size in [[1280, 800], [700, 700]]:
		var ctx: Dictionary = await _settled(size)
		var s = ctx.hud.build_screen
		ctx.sim.stock.scrap = 20.0
		ctx.sim.day = 1
		s.refresh(true)
		for view in _views(ctx.sim):
			s.select_plot(view[1])
			await Kit.settle()
			eq(tt._hard_to_read(s, Color.WHITE), [], "%d, %s" % [size[0], view[0]])
			eq(tt._dark_red_words(s), [], "%d, no word in the dark red (%s)" % [size[0], view[0]])
		Kit.free_all(ctx)


# ---------------------------------------------------------- the Duty roster's posts --

func test_the_night_posts_of_a_claimed_lot_are_on_the_roster_under_its_name() -> void:
	_park_the_mouse()
	var ctx := Kit.build(1280, 800, 1, false, 3)
	var sim = ctx.sim
	sim.day = 12
	sim.stock.scrap = 400.0
	Kit.update(ctx, 1)
	var base: int = sim.jobs.posts().size()
	ctx.hud.open_jobs()
	var s = ctx.hud.jobs_screen
	var ruth = Kit.person(ctx, "ruth")
	s.open_post_list(ruth)
	eq(s.list_items.size(), base, "before a claim only the wall's own posts are listed")
	check(not s.list_items.has("post_west_road_top"), "none of a lot that is not claimed")
	s.close_list(false)
	ctx.hud.close_jobs()
	_clear_places(sim, 3)
	check(sim.lots.claim("north"), "(the north lot is claimed)")
	ctx.hud.open_jobs()
	s = ctx.hud.jobs_screen
	s.open_post_list(ruth)
	eq(s.list_items.size(), base + 6, "the six mouths of the lot add six posts")
	var mouth: Dictionary = sim.lots.mouth("west_road_top")
	check(s.list_items.has("post_west_road_top"), "the post of a mouth is there")
	check(Kit.texts(s.list_items.post_west_road_top).has(String(mouth.name)), "under the mouth's name: %s" % str(Kit.texts(s.list_items.post_west_road_top)))
	check(Kit.texts(s.list).has("THE NORTH STREET"), "grouped under the lot's name, not under the wall's: %s" % str(Kit.texts(s.list)))
	check(not Kit.texts(s.list).has("SCHOOL"), "(no heading is the wrong wall)")
	for heading in ["North wall", "West wall", "East wall", "Towers"]:
		check(Kit.texts(s.list).has(heading.to_upper()), "the wall's own groups stay: %s" % heading)
	check(not s.list_items.post_west_road_top.disabled, "a free post can be taken")
	s.list_items.post_west_road_top.pressed.emit()
	eq(String(sim.jobs.post_of(ruth).id), "post_west_road_top", "Ruth holds it")
	eq(Kit.texts(s.rows.ruth.post), [String(mouth.name)], "her row says so: %s" % str(Kit.texts(s.rows.ruth.post)))
	# a taken one is greyed with who holds it
	var dez = Kit.person(ctx, "dez")
	s.open_post_list(dez)
	check(s.list_items.post_west_road_top.disabled and Kit.texts(s.list_items.post_west_road_top).has("Ruth"), "Ruth has it: it is off for Dez and says who: %s" % str(Kit.texts(s.list_items.post_west_road_top)))
	check(not s.choose_post(dez, "post_west_road_top"), "and it is refused")
	check(s.error_label.visible and s.error_label.text.contains("Ruth"), "with a line that says who holds it: %s" % s.error_label.text)
	check(s.choose_post(dez, "post_north_east_end"), "another of the lot's is free")
	Kit.free_all(ctx)


# ------------------------------------------------------------------ the HUD's card --

func test_the_hud_card_of_a_street_wall_says_what_it_is() -> void:
	var ctx := _open()
	await Kit.settle()
	_stage(ctx)
	ctx.hud.close_build()
	var seg = ctx.sim.lots.segment_at("north_west_end")
	check(seg != null, "(a wall stands at the west end)")
	ctx.hud.select({"kind": "segment", "ref": seg})
	Kit.update(ctx)
	var all := Kit.texts(ctx.hud.inspect)
	check(all.has("North street, west end"), "its name: %s" % str(all))
	check(all.has("Street wall · school bus"), "and what it is, not a side of the compound: %s" % str(all))
	check(not all.has("West wall · school bus"), "(the west end of a street is not the school's west wall)")
	# the compound's own sections are named as they were
	ctx.hud.select({"kind": "segment", "ref": ctx.sim.segments[3]})
	Kit.update(ctx)
	check(Kit.texts(ctx.hud.inspect).has("North wall · school bus"), "the compound's own bus is still the north wall's: %s" % str(Kit.texts(ctx.hud.inspect)))
	# a mouth on the south side is not the school either
	var south = ctx.sim.lots.segment_at("north_alley_east")
	check(south == null, "(no wall at the north alley yet)")
	Kit.free_all(ctx)


# -------------------------------------------------------------------------- the tip --

const Tut := preload("res://tests/tutorial_kit.gd")
const Hints := preload("res://scripts/ui/hints.gd")
const Coach := preload("res://scripts/ui/coach.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")
const Prefs := preload("res://scripts/prefs.gd")

const LOTS_TIP := "The streets round the school can be claimed on the Build screen (N): shut them with walls and the dead stay out of what you build there."


func _tip() -> Dictionary:
	for h in Hints.load_hints():
		if String(h.id) == "lots":
			return h
	return {}


func test_the_lots_tip_is_in_the_file_before_the_build_tip_and_says_what_to_do() -> void:
	var h := _tip()
	check(not h.is_empty(), "there is a tip about the lots")
	eq(String(h.get("text", "")), LOTS_TIP, "its words")
	eq(h.get("anchor", []), ["build"], "it lights the toolbar's Build button")
	var list := Hints.load_hints()
	var at := -1
	for i in list.size():
		if String(list[i].id) == "lots":
			at = i
	eq(String(list[list.size() - 1].id), "build", "the build tip stays the last")
	check(at >= 0 and at < list.size() - 1, "and the lots tip is before it")
	var words: int = Coach.words(LOTS_TIP)
	check(words >= 8 and words <= Coach.MAX_WORDS, "short enough for a card: %d words" % words)


func test_the_lots_tip_is_for_a_settlement_game_when_a_lot_could_be_claimed() -> void:
	var h := _tip()
	check(not h.is_empty(), "(the tip)")
	var g := Helpers.make(5, 1, 3)
	var sim = g.sim
	check(not Conditions.check(h.start, sim, {}), "not at the start: the day, the board and the scrap are not there")
	sim.day = 3
	sim.stock.scrap = 200.0
	check(not Conditions.check(h.start, sim, {}), "not before a place of the board is cleared")
	_clear_places(sim, 1)
	eq(sim.lots.why_not_claim("north"), "", "(the north lot can be claimed)")
	check(Conditions.check(h.start, sim, {}), "now it is time")
	sim.stock.scrap = 5.0
	check(not Conditions.check(h.start, sim, {}), "not without the scrap")
	sim.stock.scrap = 200.0
	check(sim.lots.claim("north") and sim.lots.claim("west") == false, "(the first lot is claimed, the second cannot be)")
	g.world.free()
	var classic := Helpers.make(5, 1, 6)
	classic.sim.day = 12
	classic.sim.stock.scrap = 400.0
	for id in classic.sim.town.state:
		classic.sim.town.state[id].cleared = true
	check(not Conditions.check(h.start, classic.sim, {}), "never in the classic start, whatever the day and the scrap")
	classic.world.free()


func test_the_lots_tip_comes_once_with_the_build_button_lit() -> void:
	var main = Tut.start({"difficulty": 1, "seed": 5, "crew": 3})
	Prefs.set_flag("hint_town", true)    # (the tip about the Town Board would come first: it is not what this is about)
	await Tut.frames(main, 3)
	main.hints.armed = true
	main.sim.t = 60.0
	var hints = main.hints
	main.sim.day = 3
	main.sim.stock.scrap = 60.0
	_clear_places(main.sim, 1)
	main.sim.stock.scrap = 30.0
	await Tut.frames(main, 40)
	var shown: String = hints.shown_id()
	eq(shown, "lots", "the tip about the lots is up (and not the build tip): %s" % shown)
	check(Prefs.flag("hint_lots"), "marked as shown the moment it was")
	check(hints.target_rect.size.x > 0.0 and hints.target_rect == main.hud.anchor_rect("build"), "the Build button is lit: %s" % str(hints.target_rect))
	eq(hints.text_label.text, LOTS_TIP, "with its words")
	hints.ok_button.pressed.emit()
	await Tut.frames(main, 4)
	await Tut.frames(main, 40 + 45 * 30)
	check(hints.shown_id() != "lots", "once is all")
	await Tut.leave(main)


# --------------------------------------------------------------- the help and the button --

func test_the_help_and_the_build_button_mention_the_lots_in_a_settlement_game_only() -> void:
	var classic := Kit.build(1280, 800, 1, false, 6)
	Kit.update(classic)
	eq(classic.hud.build_button.tooltip_text, Hud.BUILD_TIP, "the classic start's button is as it was")
	eq(classic.hud.help_n.text, "Build", "and the help's N says Build")
	eq(classic.hud.help_n.tooltip_text, "", "with nothing to add")
	var wide: float = classic.hud.help.get_combined_minimum_size().x
	Kit.free_all(classic)
	var ctx := Kit.build(1280, 800, 1, false, 3)
	Kit.update(ctx)
	var tip: String = ctx.hud.build_button.tooltip_text
	check(tip.begins_with("Build:") and tip.contains("streets") and tip.ends_with("Key: N"), "a settlement game's button names the streets and keeps its key: %s" % tip)
	eq(ctx.hud.help_n.text, "Build", "the help's N still says Build (there is no room beside it for more)")
	check(ctx.hud.help_n.tooltip_text.contains("streets") and ctx.hud.help_n.mouse_filter == Control.MOUSE_FILTER_PASS, "but pointing at it says what else it does: %s" % ctx.hud.help_n.tooltip_text)
	check(ctx.hud.help.get_combined_minimum_size().x <= wide + 0.5, "and the help panel is no wider than it was (%.0f against %.0f)" % [ctx.hud.help.get_combined_minimum_size().x, wide])
	Kit.free_all(ctx)


# --------------------------------------------------------------- the walls' art in the world --

## A wall of `kit` at `mouth` (its lot claimed first, the conditions made up), as the Builders would leave it.
func _wall(sim, mouth_id: String, kit_id: String) -> void:
	_clear_places(sim, 3)
	sim.day = maxi(int(sim.day), 12)
	sim.stock.scrap = 900.0
	var lot := String(sim.lots.mouth(mouth_id).lot)
	if not sim.lots.claimed(lot):
		check(sim.lots.claim(lot), "(%s is claimed)" % lot)
	check(sim.build.order(mouth_id, "wall_%s" % kit_id), "(a %s is ordered at %s)" % [kit_id, mouth_id])
	var pl: Dictionary = sim.build.plot(mouth_id)
	pl.site.progress = float(pl.site.work)
	sim.build._finish(pl)


## The nodes of the world that draw the walls of the lots (their holders' names begin with "Segment1" and have three digits).
func _holders(world) -> Array:
	var out: Array = []
	for c in world.layers[4].get_children():
		if String(c.name).begins_with("Segment") and not c.is_queued_for_deletion():
			var n := int(String(c.name).trim_prefix("Segment").to_int())
			if n >= 100:
				out.append(c)
	return out


func _scene() -> Node:
	var main = Tut.start({"difficulty": 1, "seed": 5, "crew": 3})
	return main


func test_a_wall_built_is_drawn_in_the_world_and_changes_state_with_its_health() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	var sim = main.sim
	var world = main.world
	check(sim.on_segment_added.is_valid() and sim.on_segment_removed.is_valid(), "the game hears of walls made and taken away")
	eq(_holders(world).size(), 0, "no wall of the lots to begin with")
	_wall(sim, "west_road_top", "container_n")
	var seg = sim.lots.segment_at("west_road_top")
	check(seg != null, "(the wall has its section)")
	var id: int = int(seg.id)
	check(world.segment_holders.has(id) and world.segment_states.has(id), "the world has a holder for it")
	eq(_holders(world).size(), 1, "one more node in the world")
	eq(world.segment_holders[id].get_child_count(), seg.art[0].size(), "drawn from the first of its four states' pictures")
	check(seg.art.size() == 4, "(it has four states)")
	for state in [1, 2, 3]:
		seg.hp = seg.max_hp * [0.5, 0.2, 0.0][state - 1]
		sim._segment_state(seg)
		eq(int(seg.state), state, "(state %d)" % state)
		await Tut.frames(main, 2)
		var holder: Node2D = world.segment_holders[id]
		eq(holder.get_child_count(), seg.art[state].size(), "state %d: its own pictures, the old ones gone" % state)
		var files: Array = []
		for c in holder.get_children():
			files.append(String((c as Sprite2D).texture.resource_path).get_file())
		var want: Array = []
		for p in seg.art[state]:
			want.append(String(p.file).get_file())
		eq(files, want, "state %d: the right pictures" % state)
	# it stands where its tiles are: the pictures are over the street it shuts
	var box := Rect2()
	for c in world.segment_holders[id].get_children():
		box = box.merge(Rect2((c as Sprite2D).position / 64.0, (c as Sprite2D).texture.get_size() * (c as Sprite2D).scale / 64.0)) if box.size != Vector2.ZERO else Rect2((c as Sprite2D).position / 64.0, (c as Sprite2D).texture.get_size() * (c as Sprite2D).scale / 64.0)
	var mouth: Dictionary = sim.lots.mouth("west_road_top")
	var rect := Rect2(float(mouth.rect[0]), float(mouth.rect[1]), float(mouth.rect[2]) - float(mouth.rect[0]) + 1.0, float(mouth.rect[3]) - float(mouth.rect[1]) + 1.0)
	check(box.grow(0.1).intersects(rect) and absf(box.get_center().x - rect.get_center().x) < 1.0, "the picture covers the street it shuts: %s and the mouth %s" % [str(box), str(rect)])
	await Tut.leave(main)


func test_a_load_takes_the_walls_art_away_and_draws_it_again_and_leaves_nothing_over() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	var sim = main.sim
	var world = main.world
	var before: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	_wall(sim, "west_road_top", "container_n")
	_wall(sim, "north_east_end", "bus_e")
	var worn = sim.lots.segment_at("north_east_end")
	sim._damage_segment(worn, 200.0)
	await Tut.frames(main, 2)
	eq(_holders(world).size(), 2, "two walls are drawn")
	var saved: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	# the older save has no wall: both are taken away
	check(SaveGame.apply(sim, before), "(the save from before loads)")
	await Tut.frames(main, 2)
	eq(_holders(world).size(), 0, "no wall of the lots is left in the world")
	eq(world.segment_holders.size(), 16, "the compound's sixteen holders only")
	check(sim.lots.segment_at("west_road_top") == null, "(nor in the rules)")
	# the later one has both, one of them worn: they are drawn, in their states
	check(SaveGame.apply(sim, saved), "(the save with two walls loads)")
	await Tut.frames(main, 2)
	eq(_holders(world).size(), 2, "both are drawn again, none twice")
	eq(world.segment_holders.size(), 18, "eighteen holders")
	var seg = sim.lots.segment_at("north_east_end")
	check(seg != null and int(seg.state) == 1, "the worn one is worn (state %d)" % (int(seg.state) if seg != null else -1))
	eq(world.segment_holders[int(seg.id)].get_child_count(), seg.art[1].size(), "and drawn from its worn pictures")
	# loading it again changes nothing and leaves no copy
	check(SaveGame.apply(sim, saved), "(loaded again)")
	await Tut.frames(main, 2)
	eq(_holders(world).size(), 2, "still two")
	var names: Array = []
	for c in world.layers[4].get_children():
		if not c.is_queued_for_deletion():
			names.append(String(c.name))
	var dup := false
	for n in names:
		if names.count(n) > 1:
			dup = true
	check(not dup, "no holder twice in the layer")
	await Tut.leave(main)


func test_a_bad_save_leaves_the_art_of_the_walls_as_it_was() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	var sim = main.sim
	var world = main.world
	var a: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	_wall(sim, "west_road_top", "container_n")
	await Tut.frames(main, 2)
	a["day"] = -5
	check(not SaveGame.apply(sim, a), "the broken save is refused")
	await Tut.frames(main, 2)
	eq(_holders(world).size(), 1, "the wall that stood is still drawn, once")
	check(world.segment_holders.has(int(sim.lots.segment_at("west_road_top").id)), "and its holder is the world's")
	await Tut.leave(main)


func test_a_new_run_forgets_the_art_too() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	var sim = main.sim
	_wall(sim, "west_road_top", "container_n")
	await Tut.frames(main, 2)
	eq(_holders(main.world).size(), 1, "(a wall is drawn)")
	sim.start_run(1, 9)
	await Tut.frames(main, 2)
	eq(_holders(main.world).size(), 0, "a new run in the same world draws none")
	await Tut.leave(main)


# ------------------------------------------------------------ the marks in the world --

class FakeMain:
	extends Node
	var build_open := false
	var build_hover := {}
	var title_mode := false
	var tutorial := false
	var coach = null


class FakeLighting:
	extends Node2D
	var dark := 0.0
	var fog := 0.0


## A stand-in for the canvas item the node paints on: it counts what it is asked to draw (and the words).
class Pen:
	extends RefCounted
	var rects := 0
	var lines := 0
	var words: Array = []
	var boxes := 0

	func draw_rect(_rect, _color, _filled = true, _width = -1.0) -> void:
		rects += 1

	func draw_circle(_at, _radius, _color) -> void:
		pass

	func draw_arc(_at, _radius, _from, _to, _points, _color, _width = -1.0, _aa = false) -> void:
		pass

	func draw_multiline(_points, _color, _width = -1.0, _aa = false) -> void:
		lines += 1

	func draw_texture_rect(_texture, _rect, _tile, _modulate = Color.WHITE) -> void:
		pass

	func draw_set_transform(_at, _rotation, _scale) -> void:
		pass

	func draw_style_box(_box, _rect) -> void:
		boxes += 1

	func draw_string(_font, _at, text, _align, _width, _size, _color) -> void:
		words.append(String(text))


## The node on a settlement game with the north lot claimed (and the world quiet).
func _street_game() -> Dictionary:
	var g := Helpers.make(21, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 12
	sim.stock = {"ammo": 300.0, "scrap": 900.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	_clear_places(sim, 3)
	check(sim.lots.claim("north"), "(the north lot is claimed)")
	var fake := FakeMain.new()
	var light := FakeLighting.new()
	var tall := Node2D.new()
	tall.y_sort_enabled = true
	g.world.add_child(fake)
	g.world.add_child(light)
	g.world.add_child(tall)
	var n := BuildNode.new()
	g.world.add_child(n)
	n.setup(fake, sim, tall, light)
	n.pointer = NOWHERE    # (the real mouse is nowhere a test knows)
	return {"g": g, "sim": sim, "node": n, "main": fake}


## A point of the map that is far from every plot and every street.
const NOWHERE := Vector2(-40.0, -40.0)


func test_an_open_street_is_a_dashed_line_with_its_words_and_a_wall_that_stands_is_not() -> void:
	var h := _street_game()
	var n = h.node
	var sim = h.sim
	h.main.build_open = true    # (the Build screen is open: every street is marked)
	n.pointer = NOWHERE
	var pen := Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_streets, 6, "the six streets of the claimed lot are open")
	check(pen.words.count("open street") == 6, "each with its words: %s" % str(pen.words))
	eq(n.street_state(sim.build.plot("west_road_top")), "open", "(the state)")
	check(n.street_state(sim.build.plot(_ring(sim, "north"))) == "", "a ring plot has none")
	_wall(sim, "west_road_top", "container_n")
	n.update(0.0)
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_streets, 5, "a wall that stands closes its street on the map")
	eq(n.street_state(sim.build.plot("west_road_top")), "", "no mark for it")
	var seg = sim.lots.segment_at("west_road_top")
	sim._damage_segment(seg, seg.hp + 1.0)
	eq(n.street_state(sim.build.plot("west_road_top")), "down", "a wall that has fallen is a street that is open again")
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_streets, 6, "and it is marked")
	check(pen.words.has("wall down") and pen.words.count("open street") == 5, "in its own words: %s" % str(pen.words))
	# a wall going up is not an open street
	check(sim.build.order("north_east_end", "wall_container_w"), "(a wall is ordered)")
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_streets, 5, "a site is no open street (it has its heap and its bar)")
	h.g.world.free()


func test_a_street_is_marked_only_while_the_screen_is_open_or_the_pointer_is_near_or_its_wall_is_down() -> void:
	var h := _street_game()
	var n = h.node
	var sim = h.sim
	n.pointer = NOWHERE
	var pen := Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_streets, 0, "with the screen shut and the pointer far away no street is marked")
	check(pen.words.is_empty() and pen.lines == 0, "no words, no dashes: %s" % str(pen.words))
	# the pointer near one street: that one has its line and its words
	var mouth: Dictionary = sim.build.plot("west_road_top")
	n.pointer = Vector2(mouth.pos)
	pen = Pen.new()
	n._paint_ground(pen)
	check(n.drawn_streets >= 1 and pen.words.has("open street"), "the pointer on a street: its words are up (%d marked)" % n.drawn_streets)
	check(n.drawn_streets < 6, "and not every street's")
	near(n.outline_alpha(mouth), 0.0, 1.0e-9, "its line and words are its outline: no box of dashes round it as well")
	near(n.sign_alpha(mouth), BuildNode.SIGN_NEAR, 1.0e-9, "but it has its sign, the thing a click opens its card on")
	# a point NEAR_STREET tiles from its edge is near, a point further is not
	var half := Vector2(mouth.size) / 2.0
	n.pointer = Vector2(mouth.pos) + Vector2(0.0, half.y + BuildNode.NEAR_STREET - 0.2)
	check(n.street_wanted(mouth), "within NEAR_STREET tiles of it")
	n.pointer = Vector2(mouth.pos) + Vector2(0.0, half.y + BuildNode.NEAR_STREET + 0.5)
	check(not n.street_wanted(mouth), "beyond it, not")
	# the screen open marks them all
	n.pointer = NOWHERE
	h.main.build_open = true
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_streets, 6, "with the Build screen open every open street is marked")
	h.main.build_open = false
	# a wall that is down is marked wherever the pointer is: the street is open and the dead come through it
	_wall(sim, "west_road_top", "container_n")
	var seg = sim.lots.segment_at("west_road_top")
	sim._damage_segment(seg, seg.hp + 1.0)
	n.update(0.0)
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_streets, 1, "a wall that is down is always marked")
	check(pen.words == ["wall down"], "in its words: %s" % str(pen.words))
	# a wall going up is not an open street, and has its heap and its bar whatever the pointer does
	check(sim.build.order("north_east_end", "wall_container_w"), "(a wall is ordered)")
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_streets, 1, "a site is not marked as an open street")
	check(n.drawn_outlines >= 1, "but it keeps its outline")
	h.g.world.free()


func test_a_classic_game_marks_no_street_and_an_unclaimed_lots_streets_are_not_marked() -> void:
	var g := Helpers.make(21, 1, 3)
	var fake := FakeMain.new()
	var light := FakeLighting.new()
	g.world.add_child(fake)
	g.world.add_child(light)
	var n := BuildNode.new()
	g.world.add_child(n)
	n.setup(fake, g.sim, null, light)
	var pen := Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_streets, 0, "before a claim nothing is marked out in the streets")
	g.world.free()
	var c := Helpers.make(21, 1, 6)
	var n2 := BuildNode.new()
	c.world.add_child(n2)
	n2.setup(FakeMain.new(), c.sim, null, FakeLighting.new())
	var pen2 := Pen.new()
	n2._paint_ground(pen2)
	eq(n2.drawn_streets, 0, "the classic start marks no street")
	check(pen2.words.is_empty(), "and writes nothing")
	c.world.free()


func test_a_site_across_a_street_has_a_heap_every_few_tiles_along_it() -> void:
	var h := _street_game()
	var n = h.node
	var sim = h.sim
	check(sim.build.order("west_road_top", "wall_container_n"), "(a wall is ordered across the west road: eleven tiles, east to west)")
	var pl: Dictionary = sim.build.plot("west_road_top")
	var heaps: Array = n._heaps(pl)
	eq(heaps.size(), 3, "three heaps for eleven tiles")
	var c := Vector2(pl.pos)
	check(absf(heaps[1].x - c.x) < 0.01 and heaps[0].x < heaps[1].x and heaps[1].x < heaps[2].x and absf(heaps[0].y - c.y) < 0.01, "in a row along the street, the middle at its middle: %s" % str(heaps))
	n.update(0.0)
	var one := Helpers.make(22, 1, 3)
	var yard_heap: Array = n._heaps(sim.build.plot(String(_yard_ids(sim)[0])))
	eq(yard_heap.size(), 1, "a plot in the yard has the one")
	check(sim.build.order("north_west_end", "wall_container_w"), "(and one across the end of the north street: north to south)")
	var v: Array = n._heaps(sim.build.plot("north_west_end"))
	check(v.size() == 3 and absf(v[0].x - v[2].x) < 0.01 and v[0].y < v[2].y, "a wall that runs north to south has its heaps in a column: %s" % str(v))
	n.update(0.1)
	check(n.sprite_count() >= 3 * 3 * 2, "the heaps are drawn: %d pictures" % n.sprite_count())
	one.world.free()
	h.g.world.free()


func test_pointing_at_a_whole_lot_lights_its_plots_and_mouths_claimed_or_not() -> void:
	var h := _street_game()
	var n = h.node
	var sim = h.sim
	var pen := Pen.new()
	n._paint_ground(pen)
	var plain: int = n.drawn_outlines
	h.main.build_hover = {"lot": "north"}
	check(n.outline_alpha(sim.build.plot(_ring(sim, "north"))) == BuildNode.ALPHA_HOVER, "a claimed lot's plots are brightest while it is pointed at")
	check(n.outline_alpha(sim.build.plot(String(_yard_ids(sim)[0]))) < BuildNode.ALPHA_HOVER, "and the yard's are not")
	h.main.build_hover = {"lot": "west"}
	pen = Pen.new()
	n._paint_ground(pen)
	var lot: Dictionary = sim.lots.lot("west")
	eq(n.drawn_outlines, plain + lot.plots.size() + lot.mouths.size(), "a lot that is not claimed is outlined (its %d plots and %d mouths) all the same" % [lot.plots.size(), lot.mouths.size()])
	h.main.build_hover = {"plot": _ring(sim, "west")}
	check(n.hovered() == _ring(sim, "west") and n.hovered_lot() == "", "a plot is still pointed at as before")
	h.main.build_hover = {}
	pen = Pen.new()
	n._paint_ground(pen)
	eq(n.drawn_outlines, plain, "nothing pointed at, nothing extra")
	h.g.world.free()


# ------------------------------------------------------------- the walls' pictures --

func _art_box(art_state: Array) -> Rect2:
	var box := Rect2()
	var first := true
	for p in art_state:
		var r := Rect2(float(p.x), float(p.y), float(p.w), float(p.h))
		box = r if first else box.merge(r)
		first = false
	return box


func test_every_kit_is_drawn_over_the_street_it_shuts_on_every_mouth_it_fits() -> void:
	var g := Helpers.make(21, 1, 3)
	var sim = g.sim
	var n := 0
	for m in sim.lots.mouths():
		var rect := Rect2(float(m.rect[0]), float(m.rect[1]), float(m.rect[2]) - float(m.rect[0]) + 1.0, float(m.rect[3]) - float(m.rect[1]) + 1.0)
		for kit_id in m.kits:
			var seg = sim.lots._make_section(m, sim.lots.kits()[String(kit_id)])
			check(seg != null and seg.art.size() == 4, "(%s at %s has four states)" % [kit_id, m.id])
			for state in 4:
				var box := _art_box(seg.art[state])
				var c := box.get_center()
				var along: float = absf(c.x - rect.get_center().x) if String(m.dir) == "h" else absf(c.y - rect.get_center().y)
				var across: float = c.y - rect.get_center().y if String(m.dir) == "h" else c.x - rect.get_center().x
				check(along < 1.0, "%s at %s, state %d: centred along the street (%.2f off)" % [kit_id, m.id, state, along])
				check(absf(across) < 1.6, "%s at %s, state %d: on the wall's own ground, not a wall's thickness away (%.2f across)" % [kit_id, m.id, state, across])
			sim.remove_segment(seg)
			n += 1
	check(n >= 25, "(every kit on every mouth it fits: %d)" % n)
	g.world.free()


func test_the_pallets_and_the_wire_face_the_dead_wherever_the_mouth_looks() -> void:
	var g := Helpers.make(21, 1, 3)
	var sim = g.sim
	var cases := [["east_alley", "pallets_w", "flip_h"], ["west_alley", "chainlink_e", "flip_h"], ["east_alley", "chainlink_w", "flip_h"],
		["west_alley", "pallets_w", ""], ["west_alley", "chainlink_w", ""], ["east_alley", "chainlink_e", ""], ["north_alley_east", "pallets_n", ""],
		["west_alley", "blocks_w", ""], ["east_alley", "blocks_w", ""], ["north_east_end", "container_w", ""], ["north_west_end", "bus_e", ""], ["south_west_a", "container_n", ""]]
	for c in cases:
		var seg = sim.lots._make_section(sim.lots.mouth(c[0]), sim.lots.kits()[c[1]])
		var flagged := ""
		for p in seg.art[0]:
			for f in ["flip_h", "flip_v"]:
				if p.has(f) and bool(p[f]):
					flagged = f
		eq(flagged, c[2], "%s at %s" % [c[1], c[0]])
		sim.remove_segment(seg)
	# a flag is a picture turned over where the world draws it
	var seg2 = sim.lots._make_section(sim.lots.mouth("east_alley"), sim.lots.kits()["pallets_w"])
	var holder := Node2D.new()
	g.world.add_child(holder)
	g.world._add_pieces(holder, seg2.art[0])
	check(holder.get_child_count() > 0, "(the pieces are drawn)")
	for s in holder.get_children():
		check((s as Sprite2D).flip_h and not (s as Sprite2D).flip_v, "turned over left to right")
	holder.free()
	sim.remove_segment(seg2)
	g.world.free()


func test_the_parts_of_the_lots_page_can_be_pointed_at_by_name() -> void:
	var ctx := _open(1280, 800, "@lots")
	await Kit.settle()
	await Kit.settle()
	var h = ctx.hud
	var s = h.build_screen
	_clear_places(ctx.sim, 3)
	ctx.sim.day = 12
	s.refresh(true)
	await Kit.settle()
	for pair in [["build.lots", s.lots_row], ["build.map", s.map], ["build.claim:north", s.lot_cards.north.claim], ["build.row:@lots", s.rows["@lots"].row]]:
		var r: Rect2 = h.anchor_rect(pair[0])
		check(r.size != Vector2.ZERO and r == Kit.rect(pair[1]), "%s is found: %s" % [pair[0], str(r)])
	eq(h.anchor_rect("build.claim:nowhere"), Rect2(), "a lot that is not there")
	eq(h.anchor_rect("build.walling:north"), Rect2(), "a lot that is not claimed has no switch to point at")
	check(s.claim_lot("north"), "(the north lot is claimed)")
	await Kit.settle()
	var sw: Rect2 = h.anchor_rect("build.walling:north")
	check(sw.size != Vector2.ZERO and sw == Kit.rect(s.lot_cards.north.switch), "a claimed lot's switch is found: %s" % str(sw))
	eq(h.anchor_rect("build.walling:nowhere"), Rect2(), "and a lot that is not there has none")
	eq(h.anchor_rect("build.pin:west_alley"), Rect2(), "a pin of a lot that is not claimed is not shown")
	check(h.anchor_rect("build.pin:west_road_top").size != Vector2.ZERO, "and one of the lot that is, is")
	check(h.anchor_rect("build.pin:%s" % String(_yard_ids(ctx.sim)[0])).size != Vector2.ZERO, "a pin of the yard is")
	var classic := _open(1280, 800, "", 100.0, 4, 6)
	eq(classic.hud.anchor_rect("build.lots"), Rect2(), "no Lots slip in the classic start")
	eq(classic.hud.anchor_rect("build.map"), Rect2(), "and no map")
	Kit.free_all(classic)
	Kit.free_all(ctx)


# -------------------------------------------------------------------------- fuzz --

## What the page says about the lots against what the game says: a list of what does not match.
func _lots_page_matches_the_game(ctx: Dictionary) -> Array:
	var bad: Array = []
	var s = ctx.hud.build_screen
	var sim = ctx.sim
	var build = sim.build
	for pl in build.plots():
		var id := String(pl.id)
		var mouth: bool = String(pl.kind) == "mouth"
		if mouth and s.rows.has(id):
			bad.append("a slip for the street %s" % id)
		if not mouth and not s.rows.has(id):
			bad.append("no slip for %s" % id)
			continue
		var want := "Open street"
		if not mouth:
			var home: Dictionary = build.building(String(pl.home))
			var because: String = build.why_not(id, String(home.id))
			want = "%s scrap, %s builder-hours" % [s._num(float(home.scrap)), s._num(float(home.work))] if because == "" else "Can't: %s" % s._short_why(because)
		if pl.building != "":
			want = String(build.building(String(pl.building)).name) if mouth else "Built"
			if mouth:
				var seg = sim.lots.segment_at(id)
				if seg != null:
					want += ": down" if int(seg.state) == 3 else ": %d%%" % roundi(float(seg.hp) / float(seg.max_hp) * 100.0)
		elif not pl.site.is_empty():
			want = "Going up: %d%%" % mini(99, floori(build.progress_of(id) * 100.0)) if not mouth else "%s: %d%%" % [String(build.building(String(pl.site.building)).name), mini(99, floori(build.progress_of(id) * 100.0))]
		if not mouth:
			var r: Dictionary = s.rows[id]
			if Kit.texts(r.status) != [want]:
				bad.append("%s's slip reads %s, not '%s'" % [id, str(Kit.texts(r.status)), want])
			if not r.row.visible:
				bad.append("the slip of the open plot %s is hidden" % id)
		var state: String = s.map.state_of(id)
		var expect := ""
		if not pl.site.is_empty():
			expect = "site"
		elif pl.building != "":
			expect = ("down" if want.ends_with("down") else "wall") if mouth else "built"
		else:
			expect = "open" if mouth else "empty"
		if state != expect:
			bad.append("the map says %s is '%s', not '%s'" % [id, state, expect])
	for l in sim.lots.lots():
		var claimed: bool = sim.lots.claimed(String(l.id))
		if s.lot_headers[String(l.id)].visible != (claimed and not (l.plots as Array).is_empty()):
			bad.append("the caption of %s is %s" % [l.id, s.lot_headers[String(l.id)].visible])
		for pid in l.plots:
			if s.rows[String(pid)].row.visible != claimed:
				bad.append("the slip of %s is %s with the lot %s" % [pid, s.rows[String(pid)].row.visible, claimed])
		var c: Dictionary = s.lot_cards[String(l.id)]
		if c.foot.visible == claimed:
			bad.append("the Claim line of %s is %s with the lot %s" % [l.id, c.foot.visible, claimed])
		if not claimed:
			var why: String = sim.lots.why_not_claim(String(l.id))
			if c.claim.disabled != (why != ""):
				bad.append("the Claim button of %s is %s with why_not_claim '%s'" % [l.id, c.claim.disabled, why])
			if why != "" and c.why.text != s._sentence(why):
				bad.append("the reason of %s is '%s' not '%s'" % [l.id, c.why.text, why])
		else:
			var want := "%d of %d walls stand" % [sim.lots.standing_walls(String(l.id)), sim.lots.mouths_of(String(l.id)).size()]
			if Kit.texts(c.walls) != [want]:
				bad.append("the count of %s reads %s, not '%s'" % [l.id, str(Kit.texts(c.walls)), want])
			if c.switch.button_pressed != sim.lots.auto_walling(String(l.id)) or not c.order_row.visible:
				bad.append("the switch of %s is %s with the order %s" % [l.id, c.switch.button_pressed, sim.lots.auto_walling(String(l.id))])
			var street: String = sim.lots.next_street(String(l.id))
			if street == "":
				if c.next.text != "Every street has its wall":
					bad.append("%s has every street walled and its next line says '%s'" % [l.id, c.next.text])
			elif not c.next.text.begins_with("Next: %s, %d scrap" % [String(sim.lots.mouth(street).name), sim.lots.next_price(String(l.id))]):
				bad.append("the next street of %s is %s and its line says '%s'" % [l.id, street, c.next.text])
	if Kit.texts(s.rows["@lots"].status) != ["%d of %d claimed" % [sim.lots.claimed_on.size(), sim.lots.lots().size()]]:
		bad.append("the Lots slip says %s" % str(Kit.texts(s.rows["@lots"].status)))
	if s.selected == "@lots":
		if not s.lots_view.visible or s.empty_view.visible or s.site_view.visible or s.built_view.visible:
			bad.append("the Lots page is not the only view")
	else:
		var sel: Dictionary = build.plot(s.selected)
		if s.lots_view.visible:
			bad.append("the Lots page is showing over %s" % s.selected)
		if s.empty_view.visible != (sel.building == "" and sel.site.is_empty()):
			bad.append("the catalogue is %s for %s" % [s.empty_view.visible, s.selected])
		if s.site_view.visible != (sel.building == "" and not sel.site.is_empty()):
			bad.append("the site view is %s for %s" % [s.site_view.visible, s.selected])
		if s.built_view.visible != (sel.building != ""):
			bad.append("the building view is %s for %s" % [s.built_view.visible, s.selected])
		if s.empty_view.visible and String(sel.kind) == "mouth":
			var best: String = sim.lots.best_kit(s.selected)
			for b in build.catalogue():
				var id := String(b.id)
				if b.has("wall_kit") and s.entries[id].card.visible != (id == best):
					bad.append("%s is %s across %s (the one wall is %s)" % [id, s.entries[id].card.visible, s.selected, best])
				var why: String = build.why_not(s.selected, id)
				if s.entries[id].card.visible and s.entries[id].order.disabled != (why != ""):
					bad.append("%s's Order is %s with why_not '%s'" % [id, s.entries[id].order.disabled, why])
		if String(sel.kind) == "mouth" and sel.building != "" and s.demolish_button.visible:
			bad.append("a wall has a Demolish")
	return bad


func test_random_lots_games_and_random_clicks_never_break_the_page() -> void:
	var total := {"claimed": 0, "walls": 0, "sites": 0}
	for seed_value in [31, 8, 2024]:
		var seen: Dictionary = await _lots_fuzz(seed_value)
		for k in total:
			total[k] = maxi(int(total[k]), int(seen[k]))
	check(int(total.claimed) >= 1 and int(total.walls) >= 1 and int(total.sites) >= 1, "(the random games did claim, build and put sites up: %s)" % str(total))


func _lots_fuzz(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sizes := [[700, 700], [980, 700], [1280, 800], [1920, 1080], [700, 560]]
	var fit := BuildScreenTests.new()
	var bad: Array = []
	var seen := {"claimed": 0, "walls": 0, "sites": 0}
	for round in 5:
		var size: Array = sizes[rng.randi() % sizes.size()]
		var ctx := _open(size[0], size[1], "", 150.0 + rng.randf() * 250.0, 3 + rng.randi() % 8)
		var sim = ctx.sim
		var build = sim.build
		_clear_places(sim, 1 + rng.randi() % 3)
		var s = ctx.hud.build_screen
		s.refresh(true)
		var ids: Array = ["@lots"]
		for pl in build._plots:
			ids.append(String(pl.id))
		var buildings: Array = []
		for b in build.catalogue():
			buildings.append(String(b.id))
		await Kit.settle()
		for step in 40:
			var what := rng.randi() % 18
			if what >= 16:
				what = 6    # (claims and orders are the heart of it)
			var id: String = ids[rng.randi() % ids.size()]
			match what:
				0, 1, 2:
					if rng.randf() < 0.4 and not sim.lots.mouths().is_empty():
						id = String(sim.lots.mouths()[rng.randi() % sim.lots.mouths().size()].id)
					s.select_plot(id)
				3:
					var kits: Array = sim.lots.kits_for(s.selected) if s.selected != "@lots" else []
					if not kits.is_empty() and rng.randf() < 0.85:
						s.order(String(kits[rng.randi() % kits.size()]))
					else:
						s.order(buildings[rng.randi() % buildings.size()])
				4:
					s.cancel()
				5:
					s.demolish()
				6:
					var lot: String = String(sim.lots.lots()[rng.randi() % sim.lots.lots().size()].id)
					if rng.randf() < 0.5:
						s.claim_lot(lot)
					else:
						s.lot_cards[lot].claim.pressed.emit()
				7:
					# the board and the calendar move on under the page: a place is cleared, a day passes, scrap comes and goes
					_clear_places(sim, rng.randi() % 4)
					sim.day = 1 + rng.randi() % 14
					sim.stock.scrap = rng.randf() * 360.0
					Kit.update(ctx, 0)
				8:
					# a site is finished by the Builders, or gets headway
					var with_sites: Array = []
					for q in build.plots():
						if not q.site.is_empty():
							with_sites.append(q)
					var pl: Dictionary = with_sites[rng.randi() % with_sites.size()] if not with_sites.is_empty() else {}
					if not pl.is_empty():
						if rng.randf() < 0.6:
							pl.site.progress = float(pl.site.work)
							build._finish(pl)
						else:
							pl.site.progress = float(pl.site.work) * rng.randf() * 0.98
					Kit.update(ctx, 0)
				9:
					# the dead go at a wall: damage, a breach, a mend
					var mouth: Dictionary = sim.lots.mouths()[rng.randi() % sim.lots.mouths().size()]
					var seg = sim.lots.segment_at(String(mouth.id))
					if seg != null:
						match rng.randi() % 3:
							0:
								sim._damage_segment(seg, rng.randf() * seg.max_hp * 0.6)
							1:
								sim._damage_segment(seg, seg.max_hp + 1.0)
							_:
								sim._repair_segment(seg, seg.max_hp)
					Kit.update(ctx, 0)
				10:
					size = sizes[rng.randi() % sizes.size()]
					Kit.resize(ctx, size[0], size[1])
					await Kit.settle()
				11:
					var pin_ids: Array = s.map.pins.keys()
					var pin: Button = s.map.pins[pin_ids[rng.randi() % pin_ids.size()]]
					if pin.visible:
						if rng.randf() < 0.5:
							pin.pressed.emit()
						else:
							pin.mouse_entered.emit()
				12:
					if rng.randf() < 0.5:
						s.map_block_button.pressed.emit()
					else:
						s.map_yard_button.pressed.emit()
				13:
					var lot2: String = String(sim.lots.lots()[rng.randi() % sim.lots.lots().size()].id)
					if rng.randf() < 0.5:
						s.lot_cards[lot2].card.mouse_entered.emit()
					else:
						s.lot_cards[lot2].card.mouse_exited.emit()
				14:
					# a switch is turned (one of a lot that is not claimed has none to turn: it stays off)
					var lot3: String = String(sim.lots.lots()[rng.randi() % sim.lots.lots().size()].id)
					var sw: Button = s.lot_cards[lot3].switch
					sw.button_pressed = not sw.button_pressed
					if not sim.lots.claimed(lot3) and sim.lots.auto_walling(lot3):
						bad.append("round %d step %d: a lot that is not claimed has a standing order" % [round, step])
				15:
					# the Builders' day goes by: the standing orders put walls up
					sim.phase = "day"
					sim.bell_rung = false
					sim.lots.update(Lots.AUTO_EVERY + 0.1)
			if round == 0 and step == 12:
				# (a wall stands in every random game, whatever the dice did: the page must follow it)
				var first: Dictionary = build.plot("north_west_end")
				if first.building == "" and first.site.is_empty():
					_wall(sim, "north_west_end", _first_kit(sim, "north_west_end"))
					Kit.update(ctx, 0)
			if ctx.hud.build_screen == null:
				ctx.hud.open_build()
				s = ctx.hud.build_screen
				if s == null:
					bad.append("round %d step %d: it would not open again" % [round, step])
					break
				await Kit.settle()
			s.refresh()
			seen.claimed = maxi(int(seen.claimed), sim.lots.claimed_on.size())
			seen.walls = maxi(int(seen.walls), sim.segments.size() - 16)
			for pl in build.plots():
				if not pl.site.is_empty() and String(pl.kind) == "mouth":
					seen.sites = int(seen.sites) + 1
			for line in _lots_page_matches_the_game(ctx):
				bad.append("round %d step %d (%d): %s" % [round, step, what, line])
		await Kit.settle()
		await Kit.settle()
		_park_the_mouse()
		await Kit.settle()
		for line in fit._misfits(ctx, size):
			bad.append("round %d at %d x %d: %s" % [round, size[0], size[1], line])
		Kit.free_all(ctx)
	eq(bad, [], "a random lots game under the page (seed %d)" % seed_value)
	return seen


func test_the_alerts_of_the_lots_wear_their_own_icons() -> void:
	var ctx := Kit.build(1280, 800, 1, false, 3)
	Kit.update(ctx)
	for pair in [["lot-north", "build"], ["wall-west_road_top", "wall"], ["ruined-street_west", "down"]]:
		eq(ctx.hud._alert_icon_name({"id": pair[0], "level": "info"}), pair[1], "%s" % pair[0])
	Kit.free_all(ctx)


# ----------------------------------------------------------------- the overlay and the staging --

const OverlayNode := preload("res://scripts/render/overlay_node.gd")


func test_the_overlay_covers_the_new_sections_with_their_boxes_and_bars() -> void:
	var g := Helpers.make(21, 1, 3)
	var sim = g.sim
	sim.waves.enabled = false
	_wall(sim, "west_road_top", "container_n")
	var seg = sim.lots.segment_at("west_road_top")
	var overlay := OverlayNode.new()
	var plan: Dictionary = overlay.fields_plan(sim)
	var found: Dictionary = {}
	for item in plan.sections:
		if int(item.id) == int(seg.id):
			found = item
	check(not found.is_empty(), "the fields-of-fire view has a box for the new section (%d sections)" % plan.sections.size())
	var mouth: Dictionary = sim.lots.mouth("west_road_top")
	var rect := Rect2(float(mouth.rect[0]), float(mouth.rect[1]), float(mouth.rect[2]) - float(mouth.rect[0]) + 1.0, float(mouth.rect[3]) - float(mouth.rect[1]) + 1.0)
	check(found.get("rect", Rect2()).grow(0.01).encloses(rect.grow(-0.01)) and found.rect.size.x <= rect.size.x + 0.1, "its box is the mouth's tiles: %s and %s" % [str(found.get("rect")), str(rect)])
	check(not bool(found.get("damaged", true)), "a whole wall has no damage bar")
	sim._damage_segment(seg, 100.0)
	plan = overlay.fields_plan(sim)
	for item in plan.sections:
		if int(item.id) == int(seg.id):
			check(bool(item.damaged), "a worn wall has one (the overlay's bars read sim.segments, as the old ones')")
	overlay.free()
	g.world.free()


func test_the_staging_arguments_claim_lots_and_stand_walls_without_paying() -> void:
	var main = _scene()
	await Tut.frames(main, 3)
	var sim = main.sim
	var scrap: float = sim.stock.scrap
	var day: int = sim.day
	main._stage_lots("north")
	check(sim.lots.claimed("north") and not sim.lots.claimed("west"), "only the lot asked for is claimed")
	near(float(sim.stock.scrap), scrap, 1e-9, "no scrap was paid")
	eq(sim.day, day, "the day is as it was")
	check(not sim.alerts.has("lot-north") and sim.events.is_empty(), "and nothing is announced")
	main._stage_walls(2)
	check(sim.lots.segment_at("north_west_end") != null and sim.lots.segment_at("north_east_end") != null, "the first two mouths have their walls")
	check(sim.lots.segment_at("west_road_top") == null, "and the third has none")
	near(float(sim.stock.scrap), scrap, 1e-9, "no scrap was paid for them either")
	main._stage_wall_site("west_road_top:0.5")
	near(sim.build.progress_of("west_road_top"), 0.5, 1e-6, "a site with half the work done")
	main._stage_wall_site("west_alley")
	check(sim.lots.claimed("west") and not sim.build.plot("west_alley").site.is_empty(), "a site at a mouth of another lot claims it")
	main._stage_walling("north")
	check(sim.lots.auto_walling("north") and not sim.lots.auto_walling("west"), "the standing order is put on for the lot asked for")
	main._stage_walling()
	check(sim.lots.auto_walling("west") and not sim.lots.auto_walling("east"), "and for every lot that is claimed without a list (a lot that is not has none)")
	await Tut.leave(main)
	var classic = Tut.start({"difficulty": 1, "seed": 5})
	await Tut.frames(classic, 3)
	var plots_before: int = classic.sim.build.plots().size()
	classic._stage_lots()
	classic._stage_walls(3)
	classic._stage_wall_site("west_road_top")
	check(not classic.sim.lots.on and classic.sim.segments.size() == 16 and classic.sim.build.plots().size() == plots_before, "in the classic start they do nothing")
	await Tut.leave(classic)
