extends "res://tests/case.gd"
## Round 22, GATE-SIM (scripts/sim/gate.gd): the Main gate as a real gate in avatar mode. The rules of the gate by themselves: it is a gate
## only with an avatar (never in Orientation Day, never without one), how long it takes, the hand at the lever and its refusals, what is held,
## what a car or a party asks for and the keeper's shutting after them, the bell, the alarm, the open gate in the dark and its call, a gate that
## shuts only when nobody is in it, the interact's candidate, and the save. The world it changes (the walking grids, the dead, the trips) is
## tests/test_gate_world.gd's.
## (The round 15 picture of the gate is tests/test_gate.gd's, the views' tests/test_gate_view.gd's.)

const Helpers := preload("res://tests/helpers.gd")
const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")
const Gate := preload("res://scripts/sim/gate.gd")
const Interact := preload("res://scripts/sim/interact.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const DT := 1.0 / 30.0
## Where somebody stands in the gateway (the mouth: columns 37 to 40, rows 15 to 17 and 19, 20).
const IN_MOUTH := Vector2(39.5, 16.5)
## Where the avatar stands at the lever, and well away from it.
const AT_LEVER := Vector2(36.5, 22.3)
const FAR := Vector2(50.5, 30.5)


# ----------------------------------------------------------------- helpers --

## A quiet avatar game (Ruth the player) at 09:00 of day 1: no dead, nobody working, nobody in the gateway, the avatar well away.
func _game(crew: int = 5) -> Dictionary:
	var g := Helpers.avatar_game(3, crew)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.no_work(sim)
	Helpers.at(sim, 1, 9.0)
	sim.events.clear()
	sim.radio.news.clear()
	_put(_p(sim, "ruth"), FAR)
	_put(_p(sim, "dez"), Vector2(44.5, 30.5))
	g["ruth"] = _p(sim, "ruth")
	g["dez"] = _p(sim, "dez")
	return g


func _p(sim, id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


func _put(p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.path = []
	p.goal_key = ""
	p.moving = false


## `p` stands still at `at` however long it takes (drafted to hold the position: nobody walks out of the gateway meanwhile).
func _hold_at(p, at: Vector2) -> void:
	_put(p, at)
	p.drafted = true
	p.order = Vector3(at.x, at.y, 0.0)


## `p` is let go and put at `at`.
func _release(p, at: Vector2) -> void:
	p.drafted = false
	p.order = null
	_put(p, at)


## The clock at `hour` of `day` with the bell already rung the way a day rings it (one step: the gate has seen the bell), the gate untouched.
func _dark(sim, day: int, hour: float) -> void:
	Helpers.at(sim, day, hour)
	_go(sim, 0.05)
	sim.events.clear()
	sim.radio.news.clear()


func _go(sim, seconds: float) -> void:
	for i in int(round(seconds * 30.0)):
		sim.update(DT)


func _events(sim, type: String) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e.get("type", "")) == type:
			out.append(e)
	return out


func _gate_states(sim) -> Array:
	var out: Array = []
	for e in _events(sim, "gate"):
		out.append(String(e.state))
	return out


## The News lines of the gate's kind.
func _news(sim) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if String(e.kind) == "gate":
			out.append(e)
	return out


## The gate fully open by a hand and still (held open), ready for the next thing.
func _opened(g: Dictionary) -> void:
	var sim = g.sim
	check(bool(sim.gate.request(true).ok), "the hand opens it")
	_go(sim, Gate.OPEN_S + 0.2)
	eq(sim.gate.open, 1.0, "open")
	sim.events.clear()


func _wreck(sim) -> void:
	for s in sim.segments:
		if int(s.id) == Gate.SEGMENT:
			sim._damage_segment(s, 9999.0)


# ------------------------------------------------------------- when it is a gate --

func test_with_no_avatar_the_gate_is_the_wall_it_was() -> void:
	var g := Helpers.make(3, 1, 6)
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	check(not sim.gate.active(), "no avatar, no gate")
	check(not sim.gate.is_passable() and not sim.gate.lets_dead_in(), "a shut wall")
	eq(sim.gate.who_blocks(), [], "nobody blocks nothing")
	var r: Dictionary = sim.gate.request(true)
	check(not bool(r.ok), "a hand is refused")
	eq(String(r.why), "There is no gate here", "with its reason")
	check(sim.gate.demand("car_out", "The sedan"), "nothing holds a car or a caller back: the rules are the old ones")
	eq(sim.gate.drive_minutes({"state": "driving_out", "drive_t": 0.0, "drive_len": 5.0, "vehicle": "v1"}, 2.5), 2.5, "and a drive is not held")
	_go(sim, 6.0)
	eq(sim.gate.open, 0.0, "a demand opens nothing")
	eq(_events(sim, "gate"), [], "and no event")
	for col in Gate.MOUTH_COLS:
		for row in Gate.WALL_ROWS + Gate.FACE_ROWS:
			eq(int(g.world.solid_p[row * g.world.W + col]), 1, "the mouth is as solid as the map made it: %d,%d" % [col, row])
	g.world.free()


func test_the_gate_is_a_wall_in_orientation_day() -> void:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	Orientation.begin(sim, true)
	sim.avatar.set_player("ruth")
	check(not sim.gate.enabled, "the lesson switches the gate's rules off")
	check(not sim.gate.active(), "so it is not a gate there")
	check(not bool(sim.gate.request(true).ok), "a hand is refused")
	check(sim.gate.demand("car_out"), "and a demand is not held")
	_go(sim, 3.0)
	eq(sim.gate.open, 0.0, "it never moves")
	world.free()


func test_the_gate_is_a_gate_in_avatar_mode_and_the_lever_is_on_the_apron() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.gate.active(), "an avatar, a gate")
	eq(Gate.SEGMENT, 2, "the Main gate")
	eq(Gate.OPEN_S, 2.0, "two seconds")
	eq(Gate.KEEP_OPEN_AFTER_PASS_S, 4.0, "it waits four seconds after the last one through")
	eq(Gate.REACH, 3.5, "the reach of the lever and the front of the mouth (round 23: it was 2.2 from the lever alone)")
	eq(sim.gate.open, 0.0, "shut")
	eq(sim.gate.held, "", "held at nothing")
	eq(sim.gate.state(), "shut", "shut")
	check(not sim.gate.is_passable(), "nobody goes through a shut gate")
	var spot: Vector2 = sim.gate.control_spot()
	check(not g.world.is_solid(g.world.solid_p, spot.x, spot.y), "the lever stands on open ground")
	check(g.world.on_deck(spot.x, spot.y) == false, "not on the catwalk")
	check(not Rect2(Gate.GATEWAY).has_point(spot), "and not in the gateway")
	check(spot.distance_to(Vector2(39.0, 18.0)) < 6.0, "close to the gate")
	var mouth: Rect2 = sim.gate.gateway()
	check(mouth.has_point(Vector2(39.0, 17.0)) and mouth.has_point(Vector2(37.5, 15.5)) and mouth.has_point(Vector2(40.5, 20.5)), "the mouth is the opening between the posts, wall and bridge")
	check(not mouth.has_point(Vector2(36.5, 17.0)) and not mouth.has_point(Vector2(41.5, 17.0)), "the posts are not in it")
	# the lever is reachable on foot from the yard
	var path: Array = sim.path_p.find(g.world.solid_p, FAR.x, FAR.y, spot.x, spot.y)
	check(not path.is_empty(), "a way to the lever")
	g.world.free()


# -------------------------------------------------------------------- the hand --

func test_a_hand_opens_it_in_two_seconds_and_it_is_passable_from_half() -> void:
	var g := _game()
	var sim = g.sim
	var r: Dictionary = sim.gate.request(true)
	check(bool(r.ok), "opened")
	eq(String(r.why), "", "no reason against")
	eq(String(r.line), "Opening the gate.", "the line")
	check(not bool(r.warn), "in the day there is nothing to warn of")
	eq(sim.gate.held, "open", "held open: it stays until somebody shuts it")
	check(sim.gate.wants_open(), "it is wanted open")
	_go(sim, 0.4)
	check(sim.gate.open > 0.1 and sim.gate.open < 0.3, "the leaves are on the move: %f" % sim.gate.open)
	check(not sim.gate.is_passable(), "not yet a gateway")
	eq(sim.gate.state(), "opening", "opening")
	_go(sim, 0.7)    # (1.1 seconds in)
	check(sim.gate.open > 0.5 and sim.gate.is_passable(), "past half it is passable: %f" % sim.gate.open)
	check(sim.gate.lets_dead_in(), "and the dead may come in")
	_go(sim, 0.7)
	check(sim.gate.open > 0.85 and sim.gate.open < 1.0, "nearly open at 1.8 seconds: %f" % sim.gate.open)
	_go(sim, 0.3)
	eq(sim.gate.open, 1.0, "open after two seconds")
	eq(sim.gate.state(), "open", "open")
	var states := _gate_states(sim)
	eq(states, ["opening", "open"], "the events, once each")
	eq(String(_events(sim, "gate")[0].by), "player", "by the player")
	_go(sim, 20.0)
	eq(sim.gate.open, 1.0, "held open it stays open")
	eq(_news(sim).size(), 0, "the player's own hand is not News")
	g.world.free()


func test_a_hand_shuts_it_in_two_seconds_and_locks_it() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	var r: Dictionary = sim.gate.request(false)
	check(bool(r.ok), "shut")
	eq(String(r.line), "Shutting the gate. Locked: cars wait outside", "the line (round 23: the player's hand locks it)")
	check(bool(r.locked), "locked")
	eq(sim.gate.held, "shut", "held shut: a car waits until the player opens it again")
	check(not sim.gate.wants_open(), "not wanted open")
	_go(sim, 0.7)
	check(sim.gate.open > 0.5 and sim.gate.is_passable(), "still passable a moment later: %f" % sim.gate.open)
	_go(sim, 0.6)
	check(sim.gate.open < 0.5 and not sim.gate.is_passable(), "the wall again from half: %f" % sim.gate.open)
	check(not sim.gate.lets_dead_in(), "the dead are kept out")
	eq(sim.gate.state(), "closing", "closing")
	_go(sim, 0.8)
	eq(sim.gate.open, 0.0, "shut after two seconds")
	eq(_gate_states(sim), ["closing", "shut"], "the events")
	eq(String(_events(sim, "gate")[0].by), "player", "by the player")
	_go(sim, 20.0)
	eq(sim.gate.open, 0.0, "and it stays shut")
	g.world.free()


func test_a_hand_in_the_dark_says_the_dead_can_walk_in() -> void:
	var g := _game()
	var sim = g.sim
	_dark(sim, 1, 21.0)
	var r: Dictionary = sim.gate.request(true)
	check(bool(r.ok) and bool(r.warn), "allowed, with a warning")
	check(String(r.line).contains("dead can walk in"), "it says why: %s" % String(r.line))
	g.world.free()


# --------------------------------------------------------------------- refusals --

func test_a_wrecked_gate_cannot_be_worked() -> void:
	var g := _game()
	var sim = g.sim
	_wreck(sim)
	_go(sim, 0.2)
	check(sim.gate.wrecked(), "state 3")
	for want in [true, false]:
		var r: Dictionary = sim.gate.request(want)
		check(not bool(r.ok), "refused")
		eq(String(r.why), "The gate is wrecked", "with its reason")
	check(sim.gate.is_passable(), "a heap of rubble to pass through")
	check(not sim.gate.lets_dead_in(), "(its being down is the breach rules' own)")
	check(sim.gate.demand("car_out", "The pickup"), "a car goes on through the rubble")
	check(not sim.gate.hold("open"), "nothing to hold")
	eq(sim.gate.open, 0.0, "the leaves are not there to move")
	g.world.free()


func test_it_does_not_shut_on_somebody_in_the_gateway() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	_put(g.dez, IN_MOUTH)
	var r: Dictionary = sim.gate.request(false)
	check(not bool(r.ok), "refused")
	eq(String(r.why), "Dez is in the gateway", "by name")
	eq(sim.gate.who_blocks(), ["Dez"], "who blocks")
	check(sim.gate.held == "open" and sim.gate.open == 1.0, "nothing moved")
	# the avatar himself, under the bridge
	_put(g.dez, Vector2(44.5, 30.5))
	_put(g.ruth, Vector2(39.5, 19.5))
	r = sim.gate.request(false)
	eq(String(r.why), "You are in the gateway", "the avatar's own feet")
	# two people
	_put(g.dez, IN_MOUTH)
	r = sim.gate.request(false)
	eq(String(r.why), "You and Dez are in the gateway", "two names")
	# the dead: one that is clawing at the face is not in the way, one that is in the mouth is
	_put(g.ruth, FAR)
	_put(g.dez, Vector2(44.5, 30.5))
	var z = sim.spawn(39.5, 16.0, "wander")
	r = sim.gate.request(false)
	eq(String(r.why), "The dead are in the gateway: put them down first", "the dead")
	z.state = "attack"
	r = sim.gate.request(false)
	check(bool(r.ok), "one clawing at the wall's face is no obstacle: it is where the wall is")
	g.world.free()


func test_the_dying_and_the_dead_do_not_block() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	var z = sim.spawn(39.5, 16.0, "wander")
	z.state = "dying"
	eq(sim.gate.who_blocks(), [], "a falling one")
	z.state = "dead"
	eq(sim.gate.who_blocks(), [], "a corpse")
	var p = g.dez
	p.dead = true
	_put(p, IN_MOUTH)
	eq(sim.gate.who_blocks(), [], "a dead person")
	p.dead = false
	p.away = {"kind": "party"}
	eq(sim.gate.who_blocks(), [], "one who is off the map")
	g.world.free()


# ------------------------------------------------------------------ what is held --

func test_held_open_it_stays_and_held_shut_keeps_a_car_waiting() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.gate.hold("open"), "held open")
	sim.gate.demand("car_in", "The pickup")    # (a demand opens it, and held open it stays open)
	_go(sim, 3.0)
	eq(sim.gate.open, 1.0, "it opened")
	_go(sim, 15.0)
	eq(sim.gate.open, 1.0, "and nobody shuts it: held open")
	# held shut: the choice of the player who is here
	check(sim.gate.hold("shut"), "held shut")
	eq(sim.gate.held, "shut", "the standing choice")
	_go(sim, 2.3)
	eq(sim.gate.open, 0.0, "it shut")
	check(not sim.gate.demand("car_in", "The pickup"), "a car that comes in is not let in")
	_go(sim, 5.0)
	eq(sim.gate.open, 0.0, "it stays shut for the car")
	var lines := _news(sim)
	eq(lines.size(), 1, "one line of News about the car")
	eq(String(lines[0].text), "The pickup waits outside: the gate is shut", "which says why")
	for i in 60:
		sim.gate.demand("car_in", "The pickup")
		sim.update(DT)
	eq(_news(sim).size(), 1, "and says it once")
	check(not sim.gate.demand("arrival", "Mia Hale"), "a caller waits too")
	check(not sim.gate.demand("foot_out", "Dez and Ana"), "and a party that would go out")
	var texts: Array = []
	for e in _news(sim):
		texts.append(String(e.text))
	check(texts.has("Mia Hale is outside the gate: the gate is shut"), "the caller: %s" % str(texts))
	check(texts.has("Dez and Ana wait to go out: the gate is shut"), "the party: %s" % str(texts))
	# let go of it: the next demand opens it
	check(sim.gate.hold(""), "let go")
	check(sim.gate.demand("car_in", "The pickup") == false, "(it is still shut at the moment of asking)")
	_go(sim, 0.3)
	check(sim.gate.open > 0.0, "and it begins to open")
	g.world.free()


func test_a_standing_choice_to_keep_it_shut_is_not_kept_while_the_avatar_is_away() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.gate.hold("shut"), "held shut")
	g.ruth.away = {"kind": "party"}    # (on a trip: somebody inside has to let the party in)
	check(not sim.gate.demand("car_in", "The pickup") or sim.gate.is_passable(), "it is asked")
	_go(sim, 3.0)
	eq(sim.gate.open, 1.0, "and it opens")
	g.ruth.away = null
	g.world.free()


# ------------------------------------------------------------------- the keeper --

func test_a_demand_opens_it_and_it_shuts_by_itself_after_the_last_one() -> void:
	var g := _game()
	var sim = g.sim
	for i in 90:    # three seconds of a car on its way
		sim.gate.demand("car_in", "The pickup")
		sim.update(DT)
	eq(sim.gate.open, 1.0, "open for the car")
	eq(_gate_states(sim), ["opening", "open"], "the events")
	eq(String(_events(sim, "gate")[0].by), "auto", "by the keeper")
	eq(sim.gate.held, "", "nobody held it")
	_go(sim, 3.5)
	eq(sim.gate.open, 1.0, "it waits after the last one: 3.5 seconds on, still open")
	_go(sim, 1.0)
	check(sim.gate.open < 1.0, "4.5 seconds on, the leaves have begun to close: %f" % sim.gate.open)
	_go(sim, 2.2)
	eq(sim.gate.open, 0.0, "shut")
	eq(_gate_states(sim), ["opening", "open", "closing", "shut"], "the events, in order")
	eq(String(_events(sim, "gate")[3].by), "auto", "by the keeper")
	g.world.free()


func test_the_wait_starts_again_with_each_demand() -> void:
	var g := _game()
	var sim = g.sim
	for i in 75:
		sim.gate.demand("foot_in", "Dez")
		sim.update(DT)
	_go(sim, 3.0)
	sim.gate.demand("foot_in", "Dez")    # (another one comes)
	_go(sim, 3.0)
	eq(sim.gate.open, 1.0, "3 seconds after the second: still open")
	_go(sim, 1.5)
	check(sim.gate.open < 1.0, "and then it closes")
	g.world.free()


func test_the_gate_waits_for_somebody_in_it_and_shuts_when_they_are_gone() -> void:
	var g := _game()
	var sim = g.sim
	for i in 75:
		sim.gate.demand("car_in", "The pickup")
		sim.update(DT)
	_hold_at(g.dez, IN_MOUTH)
	_go(sim, 12.0)
	eq(sim.gate.open, 1.0, "with Dez in the gateway it does not close, however long")
	eq(_gate_states(sim), ["opening", "open"], "no event of closing")
	_release(g.dez, Vector2(44.5, 30.5))
	_go(sim, 3.9)
	eq(sim.gate.open, 1.0, "it waits four seconds after the last one is clear")
	_go(sim, 3.0)
	eq(sim.gate.open, 0.0, "then it shuts")
	g.world.free()


func test_the_leaves_stop_where_they_are_if_somebody_steps_in_as_it_closes() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	check(bool(sim.gate.request(false).ok), "shut")
	_go(sim, 0.6)
	var at: float = sim.gate.open
	check(at > 0.6 and at < 0.9, "on its way: %f" % at)
	_hold_at(g.dez, IN_MOUTH)
	_go(sim, 3.0)
	near(sim.gate.open, at, 1.0e-6, "it does not close on him")
	check(sim.gate.is_passable(), "and stays passable")
	_release(g.dez, Vector2(44.5, 30.5))
	_go(sim, 2.0)
	eq(sim.gate.open, 0.0, "once he is clear it goes on")
	g.world.free()


# ------------------------------------------------------------------ bell and alarm --

func test_the_bell_shuts_a_gate_held_open() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	Helpers.at(sim, 1, 18.99)
	sim.bell_rung = false
	_hold_at(g.dez, Vector2(39.0, 18.8))    # (at the gate post, on the catwalk over the gate: he is the keeper)
	_go(sim, 1.0)
	check(sim.bell_rung, "the bell has rung")
	_go(sim, 2.3)
	eq(sim.gate.open, 0.0, "the gate is shut")
	eq(sim.gate.held, "", "and nothing is held any more")
	var lines := _news(sim)
	eq(lines.size(), 1, "one line")
	eq(String(lines[0].text), "Dez shuts the gate for the night", "the keeper at the post")
	var by: Array = []
	for e in _events(sim, "gate"):
		by.append(String(e.by))
	eq(by, ["dusk", "dusk"], "the events are the keeper's (closing, shut)")
	g.world.free()


func test_with_no_keeper_the_shutting_is_automatic() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	Helpers.at(sim, 1, 18.99)
	sim.bell_rung = false
	_go(sim, 3.5)
	eq(sim.gate.open, 0.0, "shut")
	eq(String(_news(sim)[0].text), "The gate shuts for the night", "nobody at the post")
	g.world.free()


func test_the_bell_waits_for_somebody_in_the_gateway_and_says_so_once() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	Helpers.at(sim, 1, 18.99)
	sim.bell_rung = false
	_hold_at(g.dez, IN_MOUTH)
	_go(sim, 8.0)
	eq(sim.gate.open, 1.0, "it waits")
	var lines := _news(sim)
	eq(lines.size(), 1, "one line, once")
	eq(String(lines[0].text), "The gate cannot shut yet", "it says so")
	eq(String(lines[0].sub), "Dez is in the gateway", "and who")
	_release(g.dez, Vector2(44.5, 30.5))
	_go(sim, 2.5)
	eq(sim.gate.open, 0.0, "then it shuts, at once: no four seconds' wait at the bell")
	eq(_news(sim).size(), 2, "with its own line")
	g.world.free()


func test_the_bell_rings_each_day() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	Helpers.at(sim, 1, 18.99)
	sim.bell_rung = false
	_go(sim, 4.0)
	eq(sim.gate.open, 0.0, "shut the first night")
	Helpers.at(sim, 2, 9.0)
	_opened(g)
	Helpers.at(sim, 2, 18.99)
	sim.bell_rung = false
	_go(sim, 4.0)
	eq(sim.gate.open, 0.0, "and the second")
	g.world.free()


func test_the_alarm_shuts_it_unless_something_is_in_the_gateway() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	sim.radio.alarm(true)
	_go(sim, 2.3)
	eq(sim.gate.open, 0.0, "the call to arms shut it")
	eq(String(_news(sim)[0].text), "The gate shuts: call to arms", "with its line")
	sim.radio.alarm(false)
	_opened(g)
	sim.radio.news.clear()
	sim.radio.alarm(true)
	_hold_at(g.dez, IN_MOUTH)
	_go(sim, 5.0)
	eq(sim.gate.open, 1.0, "with Dez in it the gate waits")
	_release(g.dez, Vector2(44.5, 30.5))
	_go(sim, 2.5)
	eq(sim.gate.open, 0.0, "and shuts when he is clear")
	g.world.free()


func test_a_party_that_would_go_out_waits_for_the_morning_and_one_that_comes_in_is_let_in() -> void:
	var g := _game()
	var sim = g.sim
	sim.radio.alarm(true)
	check(not sim.gate.demand("car_out", "The sedan"), "the alarm: nobody goes out")
	check(not sim.gate.demand("foot_out", "Dez"), "on foot either")
	eq(String(_news(sim)[0].text), "The sedan waits to go out: the gate stays shut for the alarm", "the News says why")
	sim.radio.alarm(false)
	_dark(sim, 1, 21.0)
	check(not sim.gate.demand("car_out", "The sedan"), "the night: nobody goes out")
	_go(sim, 3.0)
	eq(sim.gate.open, 0.0, "it did not open")
	# one that comes in, even in the dark, is let in: a trip brought home by the player is out till dark
	sim.gate.demand("car_in", "The sedan")
	_go(sim, 0.1)
	sim.gate.demand("car_in", "The sedan")
	_go(sim, 2.4)
	eq(sim.gate.open, 1.0, "the gate opens for it")
	_go(sim, 8.0)
	eq(sim.gate.open, 0.0, "and shuts behind it")
	g.world.free()


# --------------------------------------------------------------------- the dark --

func test_a_gate_held_open_in_the_dark_with_the_dead_near_raises_one_call_a_night() -> void:
	var g := _game()
	var sim = g.sim
	_dark(sim, 1, 20.0)
	check(bool(sim.gate.request(true).ok), "opened by hand in the dark")
	_go(sim, 2.5)
	eq(sim.radio.open_calls().size(), 0, "no dead near, no call")
	sim.spawn(39.0, 6.0, "wander")
	_go(sim, 0.1)
	var calls: Array = sim.radio.open_calls()
	eq(calls.size(), 1, "the dead are near: a call")
	var c: Dictionary = calls[0]
	eq(String(c.kind), "gate", "of its own kind")
	eq(String(c.text), "The gate is open and it is dark", "its words")
	var ids: Array = []
	for o in c.options:
		ids.append(String(o.id))
	eq(ids, ["shut", "keep"], "shut it or keep it open")
	eq(String(c.default), "shut", "the default is to shut it")
	eq(int(c.data.seg), 2, "about the gate")
	check(_events(sim, "call_raised").size() == 1 and bool(_events(sim, "call_raised")[0].urgent), "urgent: the game drops to 1x")
	_go(sim, 3.0)
	eq(sim.radio.open_calls().size(), 1, "and once")
	# keep it open
	check(sim.radio.answer(int(c.id), "keep"), "answered")
	eq(sim.gate.held, "open", "kept")
	check(sim.gate.lets_dead_in(), "a breach: the dead walk in")
	_go(sim, 3.0)
	eq(sim.radio.open_calls().size(), 0, "no second call tonight")
	g.world.free()


func test_the_call_to_shut_it_shuts_it_and_by_default_too() -> void:
	var g := _game()
	var sim = g.sim
	_dark(sim, 1, 20.0)
	sim.gate.request(true)
	sim.spawn(39.0, 6.0, "wander")
	_go(sim, 2.5)
	var c: Dictionary = sim.radio.open_calls()[0]
	check(sim.radio.answer(int(c.id), "shut"), "answered: shut it")
	_go(sim, 2.3)
	eq(sim.gate.open, 0.0, "shut")
	eq(sim.gate.held, "", "held at nothing")
	# the next night; nobody answers and the call's time runs out
	_dark(sim, 2, 20.5)
	sim.gate.request(true)
	sim.zombies.clear()
	sim.spawn(39.0, 6.0, "wander")
	_go(sim, 2.5)
	eq(sim.radio.open_calls().size(), 1, "a call the next night")
	sim.clock_min += 40.0
	_go(sim, 0.2)
	eq(sim.radio.open_calls().size(), 0, "its time ran out")
	_go(sim, 2.5)
	eq(sim.gate.open, 0.0, "and by default the gate was shut")
	g.world.free()


func test_no_call_before_half_an_hour_after_the_dusk_or_for_a_gate_a_demand_opened() -> void:
	var g := _game()
	var sim = g.sim
	_dark(sim, 1, 19.2)
	sim.gate.request(true)
	sim.spawn(39.0, 6.0, "wander")
	_go(sim, 3.0)
	eq(sim.radio.open_calls().size(), 0, "19:12 is too early")
	_dark(sim, 1, 20.0)
	sim.gate.hold("")
	sim.gate.demand("car_in", "The sedan")
	_go(sim, 0.5)
	sim.gate.demand("car_in", "The sedan")
	_go(sim, 1.5)
	eq(sim.gate.open, 1.0, "open for a car")
	eq(sim.radio.open_calls().size(), 0, "a gate that is open for a car is not the player's choice: no call")
	g.world.free()


# ----------------------------------------------------------------------- interact --

func test_e_at_the_lever_opens_the_gate_and_again_shuts_it() -> void:
	var g := _game()
	var sim = g.sim
	check(sim.interact.candidates().is_empty(), "nothing in reach far away")
	_put(g.ruth, AT_LEVER)
	var list: Array = sim.interact.candidates()
	var gates: Array = list.filter(func(c): return String(c.kind) == "gate")
	eq(gates.size(), 1, "the lever is a candidate")
	var c: Dictionary = gates[0]
	eq(String(c.label), "Open the gate", "its label")
	eq(String(c.id), "gate", "its id")
	check(bool(c.ok), "it can be used")
	eq(c.pos, sim.gate.control_spot(), "at the control spot")
	near(float(c.dist), sim.gate.reach_dist(AT_LEVER), 1.0e-6, "its distance (to the working ground)")
	var r: Dictionary = sim.interact.use()
	check(bool(r.ok), "E opens it")
	eq(String(r.kind), "gate", "the answer says what was used")
	eq(sim.gate.held, "open", "held open")
	eq(_events(sim, "interact")[0].kind, "gate", "the interact event")
	eq(String(sim.interact.best().label), "Shut the gate", "at once the label is the other: E again toggles, even before the leaves are open")
	_go(sim, 2.3)
	r = sim.interact.use()
	check(bool(r.ok), "E again")
	eq(String(r.line), "Shutting the gate. Locked: cars wait outside", "shuts it, and locks it")
	eq(String(sim.interact.best().label), "Open the gate", "and the label is back")
	_go(sim, 2.3)
	eq(sim.gate.open, 0.0, "shut")
	g.world.free()


func test_the_lever_is_only_in_reach_near_it_and_ranks_below_the_bench_and_above_a_car() -> void:
	var g := _game()
	var sim = g.sim
	var spot: Vector2 = sim.gate.control_spot()
	_put(g.ruth, spot + Vector2(0.0, Gate.REACH - 0.05))
	check(not sim.interact.candidates().filter(func(c): return String(c.kind) == "gate").is_empty(), "just inside the reach")
	_put(g.ruth, spot + Vector2(0.0, Gate.REACH + 0.1))
	check(sim.interact.candidates().filter(func(c): return String(c.kind) == "gate").is_empty(), "just outside")
	check(Interact.RANK.bench < Interact.RANK.gate and Interact.RANK.gate < Interact.RANK.vehicle, "between the bench and a car")
	var far: Array = sim.interact.far_things().filter(func(c): return String(c.kind) == "gate")
	eq(far.size(), 1, "from afar the lever is a thing to walk to")
	eq(far[0].pos, spot, "where it is")
	g.world.free()


func test_e_at_the_lever_is_refused_with_the_reason() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	_put(g.ruth, AT_LEVER)
	_put(g.dez, IN_MOUTH)
	var c: Dictionary = sim.interact.best()
	eq(String(c.kind), "gate", "the lever")
	eq(String(c.label), "Shut the gate", "to shut it")
	check(not bool(c.ok), "cannot now")
	eq(String(c.why), "Dez is in the gateway", "and why")
	var r: Dictionary = sim.interact.use()
	check(not bool(r.ok), "E is refused")
	eq(String(r.why), "Dez is in the gateway", "with the reason")
	eq(sim.gate.held, "open", "and nothing changed")
	_put(g.dez, Vector2(44.5, 30.5))
	check(bool(sim.interact.use().ok), "once he is out of the way it shuts")
	_wreck(sim)
	_go(sim, 0.1)
	c = sim.interact.best()
	check(not bool(c.ok) and String(c.why) == "The gate is wrecked", "and a wrecked one cannot be worked: %s" % str(c))
	g.world.free()


func test_working_the_gate_stops_the_bench_and_a_wall_session() -> void:
	var g := _game()
	var sim = g.sim
	_put(g.ruth, AT_LEVER)
	sim.interact.working = "bench"
	sim.interact.work_left = 5.0
	check(bool(sim.interact.use().ok), "the gate is worked")
	eq(sim.interact.working, "", "the bench session was stopped: the hands are at one thing")
	g.world.free()


func test_no_lever_without_an_avatar() -> void:
	var g := Helpers.make(3, 1, 6)
	var sim = g.sim
	check(sim.interact.candidates().is_empty() and sim.interact.far_things().is_empty(), "with no avatar the lever is nothing")
	g.world.free()


# ------------------------------------------------------------------------- saving --

func test_a_save_in_the_middle_of_the_opening_loads_and_goes_on_the_same() -> void:
	var a := _game()
	var sim = a.sim
	sim.gate.request(true)
	_go(sim, 1.4)
	var mid: float = sim.gate.open
	check(mid > 0.6 and mid < 0.8, "mid-way: %f" % mid)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	check(d.modules.has("gate"), "the gate is a module of the save")
	var b := Helpers.make(3, 1, 5)
	check(SaveGame.apply(b.sim, d), "it loads")
	var bs = b.sim
	check(bs.gate.active(), "the avatar is back, so the gate rules")
	eq(bs.gate.open, mid, "the leaves are where they were, bit for bit")
	eq(bs.gate.held, "open", "held open")
	eq(bs.gate.state(), "opening", "opening")
	check(bs.gate.is_passable(), "past half: passable")
	check(int(b.world.solid_p[16 * b.world.W + 39]) == 0 and int(b.world.solid_z[16 * b.world.W + 39]) == 0, "and the world's tiles are open again on the loaded game")
	check(not b.world.deck_face_tiles.has(19 * b.world.W + 39), "and so is the deck's face under the bridge")
	_go(sim, 3.0)
	_go(bs, 3.0)
	eq(bs.gate.open, 1.0, "it finishes opening")
	eq(sim.gate.open, bs.gate.open, "as the game it was saved from does")
	# shut then save then load: solid
	sim.gate.request(false)
	_go(sim, 2.5)
	var d2: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	var c := Helpers.make(3, 1, 5)
	check(SaveGame.apply(c.sim, d2), "the shut gate loads")
	eq(c.sim.gate.open, 0.0, "shut")
	eq(int(c.world.solid_p[16 * c.world.W + 39]), 1, "solid")
	a.world.free()
	b.world.free()
	c.world.free()


func test_an_older_save_loads_as_a_shut_gate() -> void:
	var a := _game()
	var sim = a.sim
	_go(sim, 1.0)
	var d: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	d.modules.erase("gate")
	var b := Helpers.make(3, 1, 5)
	check(SaveGame.apply(b.sim, d), "a save with no gate in it loads")
	eq(b.sim.gate.open, 0.0, "a shut gate")
	eq(b.sim.gate.held, "", "nothing held")
	eq(b.sim.gate.state(), "shut", "shut")
	# damaged data: a gate that holds rubbish
	var junk: Dictionary = SaveGame.from_text(SaveGame.to_text(SaveGame.to_dict(sim)))
	junk.modules.gate = {"open": "wide", "held": 7, "state": [], "forced": "nonsense", "noted": 3}
	var c := Helpers.make(3, 1, 5)
	check(SaveGame.apply(c.sim, junk), "so does one with rubbish in it")
	eq(c.sim.gate.open, 0.0, "shut")
	eq(c.sim.gate.held, "", "held at nothing")
	a.world.free()
	b.world.free()
	c.world.free()


func test_a_new_run_shuts_the_gate_and_forgets() -> void:
	var g := _game()
	var sim = g.sim
	_opened(g)
	sim.gate.hold("open")
	sim.start_run(1, 5)
	eq(sim.gate.open, 0.0, "shut")
	eq(sim.gate.held, "", "nothing held")
	eq(int(g.world.solid_p[16 * g.world.W + 39]), 1, "the mouth is solid again")
	g.world.free()
