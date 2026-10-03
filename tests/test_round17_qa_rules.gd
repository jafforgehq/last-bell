extends "res://tests/case.gd"
## The rules the QA player's report of round 17 asked for (fixer A2): a card with a choice is not decided for the player while
## they are out in a place (its clock stands still, the place's News says it waits: scripts/sim/storyteller.gd `card_frozen`);
## the avatar does not fire into the face of a walkway from the ground (scripts/sim/avatar.gd `fire_blocked`, the `blocked_shot`
## event); the squad's cover follows an aim that is flipped exactly 180 degrees (scripts/raid/squad_ai.gd `_track`); a downed
## avatar has no hands (no firing flag, no walking, no reload, no swing).

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const Storyteller := preload("res://scripts/sim/storyteller.gd")
const RaidRun := preload("res://scripts/raid/raid_run.gd")

const FIXTURE := "user://test_round17_qa_rules_town.json"
const DT := 1.0 / 30.0

## Home is at (50, 35); the houses are an hour away on foot.
const TOWN := {
	"board": {"w": 160, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "The houses", "kind": "houses", "pos": [59, 35], "blurb": "Doors shut.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {}},
	],
	"roads": [["home", "houses"]],
	"beats": [],
}


# --------------------------------------------------------------- I2: helpers --

func _write(data: Dictionary) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


## A settlement game of three (Ruth, Dez, Marcus) at 08:00 of day 3 with the storyteller on and one card of its own in the deck:
## "A voice on the radio", two choices, the second the default, two game hours to answer (`choices` false: a card with none).
## `avatar`: Ruth is the player.
func _game(avatar: bool = true, choices: bool = true) -> Dictionary:
	_write(TOWN)
	Town.data_path = FIXTURE
	var g := Helpers.make(17, 1, 3)
	Town.data_path = Town.DATA_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.day = 3
	sim.minutes = 8.0 * 60.0
	sim.clock_min = 2.0 * 1440.0 + 8.0 * 60.0 - 420.0
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = false
	sim.supplies.sources_day = 3
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	Helpers.no_work(sim)
	if avatar:
		sim.avatar.set_player("ruth")
	sim.radio.start()
	sim.storyteller.enabled = true
	var raw := {"id": "voice", "kind": "choice", "title": "A voice on the radio", "text": "Somebody asks to be let in.", "wait": 2.0, "bot": 1}
	if choices:
		raw["choices"] = [
			{"label": "Let them in", "hint": "A mouth to feed.", "effects": [{"stock": {"food": -5}}]},
			{"label": "Not yet", "hint": "Nothing.", "effects": [{"stock": {"scrap": 5}}]}]
	else:
		raw["effects"] = [{"stock": {"water": 5}}]
		raw["result"] = "It was only static."
	sim.storyteller.cards = [Storyteller.normalise(raw)]
	sim.events.clear()
	return g


func _crew(sim, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		for p in sim.people:
			if p.id == id:
				out.append(p)
	return out


func _begin(sim) -> Dictionary:
	return sim.scavenge.begin_played(_crew(sim, ["ruth", "dez"]), "houses", "loot", "")


func _leave(sim, party: Dictionary) -> void:
	sim.scavenge.finish_played(party, {"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0})


## The News lines of kind "story" that mention the card.
func _story_news(sim) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if String(e.kind) == "story" and String(e.text).contains("A voice on the radio"):
			out.append(e)
	return out


## The game hours the pending card has left before its default is taken.
func _hours_left(sim) -> float:
	return fposmod(float(sim.storyteller.pending().until) - float(sim.hour), 24.0)


func _resolved(sim, id: String) -> bool:
	for e in sim.events:
		if String(e.get("type", "")) == "story_resolved" and String(e.get("id", "")) == id:
			return true
	return false


# ------------------------------------------------------------------ I2: tests --

func test_a_card_with_a_choice_waits_for_the_player_while_they_are_in_a_place() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.storyteller.force("voice"), "the card is raised")
	check(not sim.storyteller.card_frozen(), "at the base nothing is frozen")
	var left := _hours_left(sim)
	near(left, 2.0, 0.06, "two hours to answer at first")
	var party := _begin(sim)
	check(not party.is_empty(), "the trip begins")
	check(sim.storyteller.card_frozen(), "in the place the card's clock stands still")
	Helpers.run(sim, 60.0)    # three game hours
	check(not sim.storyteller.pending().is_empty(), "three game hours later the card still waits")
	eq(String(sim.storyteller.pending().id), "voice", "the same card")
	near(_hours_left(sim), left, 0.06, "with all the time it had: the answer is due that much later")
	check(not _resolved(sim, "voice"), "no default was taken")
	check(sim.storyteller.card_frozen(), "still frozen")
	g.world.free()


func test_the_clock_runs_again_when_the_player_leaves_the_place() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.storyteller.force("voice"), "the card is raised")
	var party := _begin(sim)
	Helpers.run(sim, 60.0)
	_leave(sim, party)
	check(sim.storyteller.card_frozen(), "on the road home the card still waits: the player cannot answer from the road")
	var left_on_the_road := _hours_left(sim)
	var steps := 0
	while sim.scavenge.player_out() and steps < 3000:    # the road home: the party is at the gate at `return_at`
		sim.update(DT)
		steps += 1
	check(not sim.scavenge.player_out(), "the party is home")
	check(not sim.storyteller.card_frozen(), "home: the card is not frozen")
	near(_hours_left(sim), left_on_the_road, 0.06, "the road home cost the card none of its time")
	check(not sim.storyteller.pending().is_empty(), "it is there for the player to answer")
	Helpers.run(sim, 20.0)    # one game hour
	check(not sim.storyteller.pending().is_empty(), "an hour later it still waits")
	Helpers.run(sim, 26.0)    # and a little more than another
	check(sim.storyteller.pending().is_empty(), "after the two hours it is settled by its default")
	check(_resolved(sim, "voice"), "and the radio says so")
	g.world.free()


func test_a_card_raised_in_the_place_is_kept_for_the_return_and_announced_in_the_news() -> void:
	var g := _game()
	var sim = g.sim
	var party := _begin(sim)
	Helpers.run(sim, 2.0)
	var news_from: int = sim.radio.latest_id()
	check(sim.storyteller.force("voice"), "the call comes while they are out")
	check(sim.storyteller.card_frozen(), "frozen from the first step")
	Helpers.run(sim, 3.0)
	var lines := _story_news(sim)
	eq(lines.size(), 1, "one News line for the card, not two: %s" % str(lines.map(func(e): return e.text)))
	if lines.size() == 1:
		var e: Dictionary = lines[0]
		eq(String(e.kind), "story", "of kind story")
		check(String(e.text).begins_with("The radio has news for you"), "it says the radio has news: %s" % String(e.text))
		check(String(e.text).contains("A voice on the radio"), "and which")
		check(String(e.sub).contains("waiting for your return"), "and that it waits: %s" % String(e.sub))
		check((e.options as Array).is_empty(), "no options in the place")
		check(int(e.id) > news_from, "a new entry")
	Helpers.run(sim, 60.0)
	eq(_story_news(sim).size(), 1, "told once however long they stay")
	check(not sim.storyteller.pending().is_empty(), "and still waiting")
	_leave(sim, party)
	check(not sim.storyteller.pending().is_empty(), "the card is there when they are back")
	g.world.free()


func test_a_card_that_was_up_when_they_left_is_announced_too() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.storyteller.force("voice"), "the card is up at the base")
	Helpers.run(sim, 1.0)
	eq(_story_news(sim).size(), 1, "the radio's own line (the ordinary one) is in the News already")
	var party := _begin(sim)
	check(not party.is_empty(), "they go")
	Helpers.run(sim, 2.0)
	eq(_story_news(sim).size(), 2, "the place's News says it waits for the return")
	if _story_news(sim).size() == 2:
		var last: Dictionary = _story_news(sim)[1]
		check(String(last.text).begins_with("The radio has news for you"), "in the new words: %s" % String(last.text))
	g.world.free()


func test_a_card_with_no_choice_is_not_held_and_is_not_announced_again() -> void:
	var g := _game(true, false)
	var sim = g.sim
	var party := _begin(sim)
	check(not party.is_empty(), "they go")
	check(sim.storyteller.force("voice"), "the card comes")
	check(not sim.storyteller.card_frozen(), "nothing to answer: nothing to freeze")
	Helpers.run(sim, 3.0)
	for e in sim.radio.news:
		check(not String(e.text).begins_with("The radio has news for you"), "no waiting line for a card that has happened already")
	g.world.free()


func test_the_old_game_is_unchanged_a_card_is_decided_in_two_hours_wherever_the_crew_are() -> void:
	var g := _game(false)
	var sim = g.sim
	eq(sim.player_id, "", "no avatar")
	check(sim.storyteller.force("voice"), "the card is raised")
	var party := _begin(sim)
	check(not party.is_empty(), "a trip is in its place")
	check(not sim.storyteller.card_frozen(), "an old game's card is never frozen")
	Helpers.run(sim, 30.0)
	check(not sim.storyteller.pending().is_empty(), "an hour and a half later it waits")
	Helpers.run(sim, 14.0)
	check(sim.storyteller.pending().is_empty(), "and at two hours its default is taken")
	g.world.free()


func test_a_frozen_card_stays_frozen_through_a_save() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.storyteller.force("voice"), "the card is raised")
	var party := _begin(sim)
	check(not party.is_empty(), "they go")
	Helpers.run(sim, 2.0)
	var told := _story_news(sim).size()
	var state: Dictionary = sim.storyteller.save()
	sim.storyteller.load_state(state)
	check(sim.storyteller.card_frozen(), "frozen after the load")
	Helpers.run(sim, 60.0)
	check(not sim.storyteller.pending().is_empty(), "and it is not decided meanwhile")
	eq(_story_news(sim).size(), told, "the News does not say it again")
	g.world.free()


# ----------------------------------------------------------- I5, M9: helpers --

## The classic map with Ruth as the avatar and a rifle at (x, y), nobody working, the dead cleared away.
func _yard(x: float, y: float, weapon: String = "rifle") -> Dictionary:
	var g := Helpers.make(7, 1, 6)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.waves.enabled = false
	sim.zombies.clear()
	var ruth = null
	for p in sim.people:
		if p.id == "ruth":
			ruth = p
	check(sim.avatar.set_player(ruth), "Ruth is the player")
	ruth.weapon = weapon
	ruth.gun = sim.weapons[weapon]
	ruth.mag = int(ruth.gun.get("mag", 0))
	ruth.x = x
	ruth.y = y
	ruth.cooldown = 0.0
	ruth.reloading = 0.0
	sim.events.clear()
	g["p"] = ruth
	return g


func _step(sim, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		sim.update(DT)


func _count(sim, type: String) -> int:
	var n := 0
	for e in sim.events:
		if String(e.get("type", "")) == type:
			n += 1
	return n


# ------------------------------------------------------------------ I5: tests --

## The north walkway's face hangs between y 19 and 21 along the wall; the ladder at x = 48.5 is open.
func test_from_the_ground_the_trigger_does_nothing_against_the_face_of_a_walkway() -> void:
	var g := _yard(40.0, 21.3)
	var sim = g.sim
	var p = g.p
	var ammo: float = sim.stock.ammo
	sim.avatar.set_input(Vector2.ZERO, Vector2(40.0, 12.0), true)
	_step(sim, 0.1)
	check(sim.avatar.fire_blocked(p), "the crosshair is greyed: the shot would only hit the face")
	_step(sim, 2.0)
	eq(p.mag, int(p.gun.mag), "no round is spent")
	eq(int(p.stats.shots), 0, "not counted as a shot")
	near(float(sim.stock.ammo), ammo, 0.0001, "the stores are untouched")
	near(p.recoil, 0.0, 0.0001, "no recoil")
	near(p.bloom, 0.0, 0.0001, "no bloom")
	eq(_count(sim, "shot"), 0, "no shot is heard")
	var clicks := _count(sim, "blocked_shot")
	check(clicks >= 3 and clicks <= 5, "a dry click now and then (at most one in half a second): %d in 2.1 s" % clicks)
	for e in sim.events:
		if String(e.get("type", "")) == "blocked_shot":
			eq(String(e.get("id", "")), "ruth", "the click is Ruth's")
	g.world.free()


func test_fire_blocked_is_true_only_while_aiming_into_a_face_within_a_tile_and_a_half() -> void:
	var g := _yard(40.0, 21.3)
	var sim = g.sim
	var p = g.p
	sim.avatar.set_input(Vector2.ZERO, Vector2(40.0, 12.0), false)
	_step(sim, 0.1)
	check(sim.avatar.fire_blocked(p), "aimed at the face, the trigger not pulled")
	# aimed along the wall and into the yard: nothing to grey out
	sim.avatar.set_input(Vector2.ZERO, Vector2(40.0, 30.0), false)
	_step(sim, 0.1)
	check(not sim.avatar.fire_blocked(p), "aimed into the yard")
	# a face farther than a tile and a half is the old behaviour (the shot spends its round on it)
	p.y = 24.0
	sim.avatar.set_input(Vector2.ZERO, Vector2(40.0, 12.0), true)
	_step(sim, 0.1)
	check(not sim.avatar.fire_blocked(p), "three tiles from the face it can still be fired")
	check(int(p.stats.shots) >= 1, "and it is")
	g.world.free()


func test_a_shot_that_can_pass_is_unchanged_from_a_ladder_and_from_the_deck() -> void:
	# the ladder foot: a column of the face that is open
	var g := _yard(48.5, 21.6)
	var sim = g.sim
	var p = g.p
	sim.avatar.set_input(Vector2.ZERO, Vector2(48.5, 12.0), true)
	_step(sim, 0.1)
	check(not sim.avatar.fire_blocked(p), "up the ladder's column nothing blocks the shot")
	check(int(p.stats.shots) >= 1, "and she fires")
	eq(_count(sim, "blocked_shot"), 0, "no click")
	g.world.free()
	# on the deck, over the wall
	g = _yard(40.5, 18.4)
	sim = g.sim
	p = g.p
	sim.avatar.set_input(Vector2.ZERO, Vector2(40.5, 10.0), true)
	_step(sim, 0.1)
	check(not sim.avatar.fire_blocked(p), "from the walkway the wall is low")
	check(int(p.stats.shots) >= 1, "and she fires over it")
	check(p.recoil > 0.0, "with its kick")
	eq(_count(sim, "blocked_shot"), 0, "no click")
	g.world.free()


func test_the_dead_between_her_and_the_face_are_shot_not_clicked_at() -> void:
	var g := _yard(40.0, 22.4)
	var sim = g.sim
	var p = g.p
	var z = sim.spawn(40.2, 21.7, "wander", "walker")
	z.hp = 1000.0
	z.stagger = 1.0e6
	z.limp = false
	sim.avatar.set_input(Vector2.ZERO, Vector2(40.0, 12.0), false)
	_step(sim, 0.1)
	check(not sim.avatar.fire_blocked(p), "something to hit before the face")
	# and with nothing in front the same spot is blocked
	sim.zombies.clear()
	check(sim.avatar.fire_blocked(p), "(the same place with nobody in front: a tile and a bit from the face)")
	g.world.free()


func test_the_butt_of_the_gun_is_not_a_blocked_shot() -> void:
	var g := _yard(40.0, 21.3, "rifle")
	var sim = g.sim
	var p = g.p
	sim.stock.ammo = 0.0    # nothing to feed the gun: the butt is swung
	sim.avatar.set_input(Vector2.ZERO, Vector2(40.0, 12.0), true)
	_step(sim, 0.1)
	check(not sim.avatar.fire_blocked(p), "a blow is not a shot")
	eq(_count(sim, "blocked_shot"), 0, "no click")
	g.world.free()


# ------------------------------------------------------------------ M9: tests --

func test_a_downed_avatar_has_no_hands() -> void:
	var g := _yard(40.0, 25.0)
	var sim = g.sim
	var p = g.p
	sim.avatar.set_input(Vector2(1.0, 0.0), Vector2(40.0, 12.0), true)
	p.input_reload = true
	p.input_melee = true
	p.downed = true
	_step(sim, 0.1)
	check(not p.input_fire, "no firing flag")
	eq(p.input_move, Vector2.ZERO, "no walking")
	check(not p.input_reload, "no reload")
	check(not p.input_melee, "no swing")
	check(not sim.avatar.fire_blocked(p), "and nothing to grey out")
	# the view goes on feeding the hands every frame: they stay empty
	sim.avatar.set_input(Vector2(0.0, 1.0), Vector2(40.0, 12.0), true)
	check(not p.input_fire, "the trigger is not taken from a downed person")
	eq(p.input_move, Vector2.ZERO, "nor the stick")
	_step(sim, 0.1)
	check(not p.input_fire and p.input_move == Vector2.ZERO, "still empty after a step")
	check(not sim.avatar.reload(), "the reload key does nothing")
	check(not sim.avatar.melee(), "nor the melee key")
	# got up again: the hands work
	p.downed = false
	sim.avatar.set_input(Vector2(1.0, 0.0), Vector2(45.0, 25.0), true)
	check(p.input_fire and p.input_move == Vector2(1.0, 0.0), "back on her feet she has them again")
	g.world.free()


func test_a_dead_avatar_who_has_not_been_replaced_has_no_hands_either() -> void:
	var g := _yard(40.0, 25.0)
	var sim = g.sim
	var p = g.p
	sim.avatar.set_input(Vector2(1.0, 0.0), Vector2(40.0, 12.0), true)
	p.dead = true
	_step(sim, 0.1)
	check(not p.input_fire and p.input_move == Vector2.ZERO and not p.input_reload and not p.input_melee, "nothing is held")
	check(not sim.avatar.fire_blocked(p), "and nothing is blocked")
	g.world.free()


# ------------------------------------------------------------------ M8: tests --

const W := 30
const H := 16


## The test_raid_avatar site: 30 x 16 of open ground with a walled house.
func _site() -> Dictionary:
	var data: Dictionary = GD.load_all().duplicate(true)
	var terrain: Array = []
	var solid: Array = []
	for y in H:
		for x in W:
			terrain.append(1)
			var wall := (x >= 14 and x <= 24 and y >= 3 and y <= 12) and (x == 14 or x == 24 or y == 3 or y == 12) and not (x == 14 and y == 8)
			solid.append(1 if wall else 0)
	data["W"] = W
	data["H"] = H
	data["terrain"] = terrain
	data["solidZ"] = solid.duplicate()
	data["solidP"] = solid.duplicate()
	data["objects"] = []
	data["walls"] = []
	data["marks"] = []
	data["lights"] = []
	data["trees"] = []
	data["segments"] = []
	data["people"] = []
	data["spawns"] = []
	return {
		"name": "A test house", "kind": "houses", "danger": 2, "size": Vector2i(W, H), "data": data,
		"entry": Vector2(3.5, 8.5), "exit": Rect2(1.0, 6.5, 5.0, 4.0), "vehicle_spot": Vector2(-1, -1),
		"containers": [], "dead": [], "rooms": [{"name": "hall", "rect": Rect2(15, 4, 9, 8)}], "seed": 1,
	}


func _at(p, x: float, y: float) -> void:
	p.x = x
	p.y = y
	p.path = []
	p.goal_key = ""
	p.moving = false


func _run_step(run, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		run.update(DT)


func test_cover_follows_an_aim_flipped_exactly_to_the_other_side() -> void:
	var site := _site()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(site.data)
	var g := Helpers.make(3, 1, 6)
	var members: Array = RaidRun.squad_of(g.sim.people.slice(0, 3))
	var run = RaidRun.new(site, world, FxNull.new(), members, 300.0)
	var me = run.squad[0]
	me.weapon = "rifle"
	me.gun = run.sim.weapons["rifle"]
	me.mag = int(me.gun.mag)
	check(run.set_player(me), "the player")
	var ana = run.squad[2]
	_at(me, 9.5, 8.5)
	_at(ana, 8.5, 9.0)
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(14.5, 8.5), false)
	check(run.request(ana, "cover").ok, "Ana covers")
	_run_step(run, 9.0)
	check(ana.x < me.x - 2.5, "behind them while they aim east: %s" % str(Vector2(ana.x, ana.y)))
	# the mouse goes to the other side of the player along the very same line: an aim exactly opposite
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(4.5, 8.5), false)
	_run_step(run, 0.2)
	check(run.squad_ai._aim.x < -0.9, "the tracked aim has turned (it was stuck at its old side): %s" % str(run.squad_ai._aim))
	_run_step(run, 9.0)
	check(ana.x > me.x + 2.5, "she goes round to the new back: %s" % str(Vector2(ana.x, ana.y)))
	# a small turn is still eased, not snapped
	run.sim.avatar.set_input(Vector2.ZERO, Vector2(9.5, 14.5), false)
	var before: Vector2 = run.squad_ai._aim
	_run_step(run, DT)
	check(run.squad_ai._aim.distance_to(before) < 0.4, "a quarter turn is eased")
	world.free()
	g.world.free()
