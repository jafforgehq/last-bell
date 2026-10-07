## One House, WP4: the rescue module (sim.rescue), its card and its view. A real mini town (`Helpers.town_game`) with fakes for the modules of the other packages (clearing, base,
## scenario), and a full-size town's twelve spots for the counts.
extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const Rescue := preload("res://scripts/town/rescue.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const BystanderView := preload("res://scripts/render/bystander_view.gd")
const RescueCard := preload("res://scripts/ui/rescue_card.gd")
const Hud := preload("res://scripts/ui/hud.gd")


class FakeClearing:
	extends RefCounted
	var revealed := {}

	func is_revealed(room: int) -> bool:
		return bool(revealed.get(room, false))


class FakeBase:
	extends RefCounted
	var claimed := false
	var spot := Vector2(10.0, 10.0)

	func claim_spot() -> Vector2:
		return spot

	func center() -> Vector2:
		return spot


class FakeScenario:
	extends RefCounted
	var calls: Array = []

	func on_survivor_joined(p, count: int) -> void:
		calls.append([String(p.id), count])


class FakeHouses:
	extends RefCounted
	var town := {}


class FakeField:
	extends RefCounted

	func dead_in_room(_room: int) -> Dictionary:
		return {"total": 0, "left": 0}


class FakeMain:
	extends Node
	var sim
	var data := {}
	var entities: Node2D
	var hud
	var clock := 0.0
	var sim_steps := 0


## A rescue module over the town game's sim with the twelve spots of a full-size town and nothing else in its way (no dead anywhere, nothing revealed).
func _twelve(sim, big: Dictionary, run_seed: int = 1) -> Object:
	var r = Rescue.new()
	r.setup(sim)
	var houses := FakeHouses.new()
	houses.town = big
	r.links = {"houses": houses, "field": FakeField.new(), "clearing": FakeClearing.new(), "base": FakeBase.new(), "scenario": FakeScenario.new()}
	sim.run_seed = run_seed
	r.start()
	return r


func _wire(r) -> Dictionary:
	var f := {"clearing": FakeClearing.new(), "base": FakeBase.new(), "scenario": FakeScenario.new()}
	r.links = f
	return f


## The dead of a room are all put down (the records of the dormant field closed).
func _clear_room(field, room: int) -> void:
	for i in field.n:
		if field.status[i] != field.KILLED and field.tile_room[floori(field.ys[i]) * field.W + floori(field.xs[i])] == room:
			field.status[i] = field.KILLED


func _events(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e.get("type", "")) == type:
			out.append(e)
	return out


# 1 ------------------------------------------------------------------ the start --

func test_oh_rescue_start_twelve_people_the_same_each_run() -> void:
	var g := Helpers.town_game(1, {"blocks": 2})
	var sim = g.sim
	eq(sim.rescue.list().size(), g.town.rescue.size(), "a record for each spot of the town the game has")
	var big := TownGen.make(1)
	var dice_before: int = sim.rng.state
	var recruits_before: int = sim.recruits._rng.state
	var people_before: int = sim.people.size()
	var a = _twelve(sim, big)
	var b = _twelve(sim, big)
	eq(a.list().size(), 12, "twelve records in a full town")
	eq(sim.rng.state, dice_before, "the sim's dice are not drawn")
	eq(sim.recruits._rng.state, recruits_before, "nor the radio callers' dice")
	eq(sim.people.size(), people_before, "nobody is in the crew yet")
	var roles := {}
	for r in Rescue._read(Rescue.DATA_PATH).get("survivors", []):
		roles[String(r.role)] = true
	var recruit_roles := {}
	for r in Rescue._read("res://assets/data/recruits.json").get("roles", []):
		recruit_roles[String(r.role)] = true
	var names := {}
	for i in 12:
		var ra: Dictionary = a.list()[i]
		var rb: Dictionary = b.list()[i]
		eq(ra.state, "hiding", "everybody starts hiding")
		check(not bool(ra.arrived), "nobody has joined")
		check(ra.def == rb.def, "the same run meets the same person (%d)" % i)
		check(recruit_roles.has(String(ra.def.role)), "%s is a role the radio callers have" % ra.def.role)
		check(sim.weapons.has(String(ra.def.weapon)), "their weapon exists")
		check(String(ra.def.station) != "", "they name a station")
		check(String(ra.def.portrait) != "", "they have a face")
		check(ra.pos == Vector2(big.rescue[i].pos), "at the generator's spot")
		names[String(ra.def.name)] = true
	eq(names.size(), 12, "twelve different names")
	eq(a.joined_count(), 0)
	var c = _twelve(sim, big, 2)
	var differs := false
	for i in 12:
		differs = differs or c.list()[i].def != a.list()[i].def
	check(differs, "another run meets other faces and skills")
	eq(sim.rng.state, dice_before, "still no draw from the sim")
	g.world.free()


# 2 ------------------------------------------------------------ states, refusals --

func test_oh_rescue_states_and_the_refusals_of_the_card() -> void:
	var g := Helpers.town_game(1, {"blocks": 2})
	var sim = g.sim
	var r = sim.rescue
	var fakes := _wire(r)
	var rec: Dictionary = r.list()[0]
	var id := String(rec.id)
	var me = sim.avatar.player()
	me.x = rec.pos.x + 0.6
	me.y = rec.pos.y
	r.update(0.3)
	eq(rec.state, "hiding", "a closed room hides them")
	eq(r.near(me), "", "nobody to talk to")
	check(r.candidates(me).is_empty(), "no E use")
	check(r.card(id).is_empty(), "no card")
	fakes.clearing.revealed[rec.room] = true
	r.update(0.3)
	eq(rec.state, "wary", "an open room makes them wary")
	eq(_events(sim, "rescue_seen").size(), 1, "seen, once")
	eq(r.near(me), id, "near enough to talk")
	eq(r.candidates(me)[0].kind, "rescue", "an E use")
	check(String(r.candidates(me)[0].label).begins_with("Talk to "), "named after them")
	# the dead of their room
	check(int(sim.field.dead_in_room(rec.room).left) > 0, "the generator leaves a dead one in the survivor's room")
	var blocked: Dictionary = r.talk(id)
	check(bool(blocked.blocked), "they say it")
	check(String(blocked.line).contains("Put down the dead in this room first"), "in their own words")
	eq(blocked.choices.size(), 0, "and offer nothing")
	eq(rec.state, "wary", "no word was had")
	check(not bool(r.choose(id, "come").ok), "no answer is taken")
	# the room is clear: three answers
	_clear_room(sim.field, rec.room)
	var m: Dictionary = r.talk(id)
	var ids: Array = []
	for c in m.choices:
		ids.append(c.id)
		check(c.has("text") and c.has("ok") and c.has("why"), "each answer has a text, ok and why")
	eq(ids, ["come", "stay", "gift"], "the answers")
	eq(rec.state, "spoken", "they have spoken now")
	check(not bool(m.choices[0].ok) and String(m.choices[0].why) != "", "Come with me is refused before a claim, with its reason")
	var out: Dictionary = r.choose(id, "come")
	check(not bool(out.ok) and String(out.why) != "", "and the refusal says why")
	eq(rec.state, "spoken", "they stay")
	fakes.base.claimed = true
	check(bool(r.card(id).choices[0].ok), "a claimed house with a bed: yes")
	# no bed
	var n := 0
	while int(sim.recruits.housing_free()) > 0 and n < 20:
		sim.add_person(sim.recruits.make_def(40 + n))
		n += 1
	check(not bool(r.card(id).choices[0].ok), "no bed, no way in")
	check(String(r.card(id).choices[0].why).contains("bed"), "and it says so")
	eq(r.joined_count(), 0)
	# "stay": they wait and remember it
	var waits: Dictionary = r.choose(id, "stay")
	check(bool(waits.ok) and not bool(waits.joined) and String(waits.line) != "", "they answer")
	eq(_events(sim, "rescue_waits").size(), 1, "waits")
	eq(r.card(id).line, "You came back.", "and know you when you are back")
	# "take this": a little food, once, and trust
	var food := float(sim.stock.food)
	var trust0 := float(rec.trust0)
	check(bool(r.choose(id, "gift").ok), "a gift")
	near(float(sim.stock.food), food - 1.0, 0.001, "a food")
	check(float(rec.trust0) > trust0, "trust for later")
	check(not bool(r.card(id).choices[2].ok), "once")
	g.world.free()


# 3 ------------------------------------------------------------------------ join --

func test_oh_rescue_join_adds_one_person_after_the_walk_and_the_fourth_is_announced() -> void:
	var g := Helpers.town_game(1, {"blocks": 2})
	var sim = g.sim
	var big := TownGen.make(1)
	var r = _twelve(sim, big)
	var base = r.links.base
	var scn = r.links.scenario
	base.claimed = true
	for rec in r.list():
		rec.state = "spoken"
	var first: Dictionary = r.list()[0]
	var people0: int = sim.people.size()
	var arrived0: int = sim.recruits.arrived.size()
	var scrap0 := float(sim.stock.scrap)
	# near: three game minutes at least
	base.spot = first.pos + Vector2(2.0, 0.0)
	var out: Dictionary = r.choose(first.id, "come")
	check(bool(out.ok) and bool(out.joined) and String(out.line) != "", "they say yes")
	eq(first.state, "joined")
	eq(sim.people.size(), people0, "they walk ahead: nobody is in the crew yet")
	eq(r.on_the_way(), [first.id])
	sim.clock_min += 2.5
	r.update(0.3)
	eq(sim.people.size(), people0, "not yet")
	sim.clock_min += 0.6
	r.update(0.3)
	eq(sim.people.size(), people0 + 1, "exactly one person")
	eq(sim.recruits.arrived.size(), arrived0 + 1, "one def for the save")
	var p = sim.people[sim.people.size() - 1]
	eq(String(p.id), String(first.def.id))
	check(Vector2(p.x, p.y).distance_to(base.spot) < 1.0, "at the base's front spot")
	check(sim.jobs.job_of(p) != "", "with a seat")
	eq(scn.calls, [[String(p.id), 1]], "the scenario is told, with the count")
	var joined: Array = _events(sim, "rescue_joined")
	eq(joined.size(), 1)
	eq(String(joined[0].who), String(p.id))
	eq(int(joined[0].count), 1)
	eq(_events(sim, "arrived").size(), 1, "the crew bar's own event")
	check(String(sim.radio.news[sim.radio.news.size() - 1].text).contains("is on the radio now"), "a News line")
	check(float(sim.stock.scrap) != scrap0 or float(sim.stock.food) > 0.0, "and what they bring")
	eq(r.joined_count(), 1)
	eq(r.arrived_count(), 1)
	# far: the walk takes distance x 0.4 minutes
	var second: Dictionary = r.list()[1]
	base.spot = second.pos + Vector2(50.0, 0.0)
	check(bool(r.choose(second.id, "come").ok))
	sim.clock_min += 19.0
	r.update(0.3)
	eq(sim.people.size(), people0 + 1, "twenty minutes for fifty tiles")
	sim.clock_min += 1.5
	r.update(0.3)
	eq(sim.people.size(), people0 + 2)
	eq(scn.calls[1][1], 2, "counting")
	# the third and the fourth
	for i in [2, 3]:
		var rec: Dictionary = r.list()[i]
		check(bool(r.choose(rec.id, "come").ok), "survivor %d joins" % i)
		sim.clock_min += 400.0
		r.update(0.3)
		if i == 2:
			eq(_events(sim, "fourth").size(), 0, "not yet the fourth")
	eq(sim.people.size(), people0 + 4)
	eq(_events(sim, "fourth").size(), 1, "the fourth, once")
	eq(scn.calls.size(), 4)
	eq(int(scn.calls[3][1]), 4)
	var stations := {}
	for q in sim.people:
		stations[sim.jobs.job_of(q)] = true
	check(stations.size() >= 2, "they work at different seats")
	g.world.free()


# 4 ------------------------------------------------------------------ save, load --

func test_oh_rescue_save_and_load_keep_the_states_and_the_joined() -> void:
	var g := Helpers.town_game(1, {"blocks": 2})
	var sim = g.sim
	var r = sim.rescue
	var fakes := _wire(r)
	sim.recruits.small = true
	fakes.base.claimed = true
	var a: Dictionary = r.list()[0]
	var b: Dictionary = r.list()[1]
	for rec in [a, b]:
		_clear_room(sim.field, rec.room)
		fakes.clearing.revealed[rec.room] = true
	r.update(0.3)
	r.talk(a.id)
	check(bool(r.choose(a.id, "come").ok))
	sim.clock_min += 500.0
	r.update(0.3)
	r.talk(b.id)
	check(bool(r.choose(b.id, "gift").ok))
	check(bool(r.choose(b.id, "stay").ok))
	eq(sim.people.size(), 2, "Ruth and the first one")
	var text := SaveGame.to_text(SaveGame.to_dict(sim))
	var g2 := Helpers.town_game(1, {"blocks": 2})
	var sim2 = g2.sim
	check(SaveGame.apply(sim2, SaveGame.from_text(text)), "the save is read")
	var r2 = sim2.rescue
	eq(sim2.people.size(), 2, "the joined person is made again")
	eq(String(sim2.people[1].id), String(a.def.id))
	eq(sim2.recruits.arrived.size(), 1)
	var a2: Dictionary = r2.get_record(a.id)
	var b2: Dictionary = r2.get_record(b.id)
	eq(a2.state, "joined")
	check(bool(a2.arrived), "arrived")
	eq(b2.state, "spoken")
	check(bool(b2.gifted) and bool(b2.asked), "the gift and the word are remembered")
	near(float(b2.trust0), float(b.trust0), 0.001, "trust")
	check(a2.def == a.def or String(a2.def.name) == String(a.def.name), "the same person")
	eq(r2.joined_count(), 1)
	# one on the way is still on the way
	var sim3
	var fakes2 := _wire(r2)
	fakes2.base.claimed = true
	fakes2.base.spot = b2.pos + Vector2(40.0, 0.0)
	r2.update(0.3)
	check(bool(r2.choose(b.id, "come").ok))
	var g3 := Helpers.town_game(1, {"blocks": 2})
	sim3 = g3.sim
	check(SaveGame.apply(sim3, SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim2)))), "a second save is read")
	eq(sim3.rescue.on_the_way(), [b.id], "still walking")
	eq(sim3.people.size(), 2, "not in the crew yet")
	for w in [g, g2, g3]:
		w.world.free()


# 5 ------------------------------------------------------------- the card, the view --

func test_oh_rescue_card_and_bystander_view() -> void:
	var g := Helpers.town_game(1, {"blocks": 2})
	var sim = g.sim
	var r = sim.rescue
	var fakes := _wire(r)
	var rec: Dictionary = r.list()[0]
	var id := String(rec.id)
	var dice: int = sim.rng.state
	check(r.bystander(id) == null, "a hidden survivor has no figure")
	var main := FakeMain.new()
	main.sim = sim
	main.data = sim.d
	main.entities = Node2D.new()
	main.add_child(main.entities)
	Engine.get_main_loop().root.add_child(main)
	var view := BystanderView.new()
	view.on_ready(main)
	view.on_sync_views(Rect2(0, 0, 192, 192))
	eq(main.entities.get_child_count(), 0, "nothing is drawn while their room is closed")
	check(not view.drawn(id))
	fakes.clearing.revealed[rec.room] = true
	r.update(0.3)
	var p = r.bystander(id)
	check(p != null, "wary: a figure")
	check(p.holstered, "the weapon is lowered")
	check(not sim.people.has(p), "not one of the crew")
	eq(sim.rng.state, dice, "making the figure draws nothing from the sim")
	view.on_sync_views(Rect2(0, 0, 192, 192))
	eq(main.entities.get_child_count(), 1, "one node")
	check(view.drawn(id))
	var me = sim.avatar.player()
	me.x = rec.pos.x + 3.0
	me.y = rec.pos.y
	r.update(0.3)
	eq(String(p.facing), "E", "they turn to the avatar")
	# the card's model
	_clear_room(sim.field, rec.room)
	var m: Dictionary = r.card(id)
	eq(String(m.name), String(rec.def.name))
	check(String(m.line) != "" and String(m.role) != "" and String(m.hiding) != "", "words")
	eq(m.choices.size(), 3)
	check(not bool(m.choices[0].ok) and String(m.choices[0].why) != "", "ok and why")
	# the card on a HUD
	var holder := Control.new()
	holder.size = Vector2(1280, 800)
	Engine.get_main_loop().root.add_child(holder)
	var hud = Hud.new()
	holder.add_child(hud)
	hud.setup(sim.d, sim.people)
	main.hud = hud
	var card := RescueCard.new()
	card.on_ready(main)
	check(not card.modal(), "shut: the hands are free")
	card.on_event({"type": "rescue_talk", "id": id})
	check(card.modal(), "open: the hands are held")
	eq(card.shown, id)
	eq(card.buttons.size(), 3, "three buttons")
	check(card.buttons.come.disabled and not card.buttons.stay.disabled, "the refused one is greyed")
	check(card.on_key(_key(KEY_2)), "2 answers")
	eq(rec.state, "spoken")
	check(String(card.reply_label.text).contains("\""), "the answer is on the board")
	check(card.on_key(_key(KEY_ESCAPE)) and not card.modal(), "Esc puts it away")
	# they say yes: the figure goes
	fakes.base.claimed = true
	r.choose(id, "come")
	view.on_sync_views(Rect2(0, 0, 192, 192))
	check(not view.drawn(id) and r.bystander(id) == null, "no figure once they have gone ahead")
	main.queue_free()
	holder.queue_free()
	g.world.free()


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.pressed = true
	return ev
