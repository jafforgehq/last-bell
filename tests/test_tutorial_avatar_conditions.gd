extends "res://tests/case.gd"
## The conditions of the avatar's Orientation Day (scripts/tutorial_conditions.gd), one by one, on a headless game with Ruth as the
## player and states written by hand: what each is true of and what it is not. The shots and the walk are the avatar's real ones.

const Tut := preload("res://tests/tutorial_kit.gd")
const Conditions := preload("res://scripts/tutorial_conditions.gd")


func _ok(spec: Dictionary, sim, st: Dictionary = {}) -> bool:
	return Conditions.check(spec, sim, st)


func _c(name: String, params: Dictionary = {}) -> Dictionary:
	return {"cond": name, "params": params}


## What the coach notes when a step begins.
func _base(sim) -> Dictionary:
	var pos := {}
	for p in sim.people:
		pos[p.id] = [p.x, p.y]
	var me = sim.avatar.player()
	return {"ammo": float(sim.stock.ammo), "kills": float(sim.kills), "pos": pos, "news": int(sim.radio.latest_id()), "mine": {"shots": int(me.stats.shots), "kills": int(me.stats.kills)}}


func test_the_registry_knows_them_all() -> void:
	for name in ["walked", "on_deck", "shots", "player_kills", "reloaded", "asked", "has_stance", "insisted", "news_open", "news_seen", "call_open", "call_answered", "board_read", "alarm_on", "alarm_cycled"]:
		check(Conditions.has(name), "'%s' is a condition" % name)
	check(not Conditions.has("following"), "(and the one that was called 'following' is 'has_stance')")


func test_without_an_avatar_none_of_the_players_conditions_holds() -> void:
	var g := Tut.make()
	var sim = g.sim
	var st := {"base": {"pos": {"ruth": [0.0, 0.0]}, "mine": {}}, "did": {"reload": 1.0}}
	for name in ["walked", "on_deck", "shots", "player_kills", "reloaded"]:
		check(not _ok(_c(name), sim, st), "no avatar: '%s' does not hold" % name)
	g.world.free()


func test_walking_is_the_distance_from_where_the_step_began() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var me = sim.avatar.player()
	var st := {"base": _base(sim)}
	var six := _c("walked", {"min": 6})
	check(not _ok(six, sim, st), "not a step yet")
	# the keys' own way: the hands walk the avatar
	sim.avatar.set_input(Vector2.RIGHT, Vector2.ZERO, false)
	Tut.run(sim, 1.0)
	check(not _ok(six, sim, st), "a second's walk (%.1f tiles) is not six" % [absf(me.x - st.base.pos.ruth[0])])
	Tut.run(sim, 1.5)
	check(_ok(six, sim, st), "two and a half seconds are (%.1f tiles)" % [absf(me.x - st.base.pos.ruth[0])])
	check(not _ok(six, sim, {"base": {}}), "with no note of where they stood it does not hold")
	g.world.free()


func test_the_walkway_is_where_the_ladder_leads() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var me = sim.avatar.player()
	check(not _ok(_c("on_deck"), sim), "in the yard: not on a deck")
	# up the ladder at the bus, the way the lesson shows (north from its foot)
	me.x = 48.5
	me.y = 21.6
	sim.avatar.set_input(Vector2.UP, Vector2.ZERO, false)
	Tut.run(sim, 1.6)
	sim.avatar.set_input(Vector2.ZERO, Vector2.ZERO, false)
	check(me.y < 19.5, "she is north of the foot of the ladder (%.2f)" % me.y)
	check(_ok(_c("on_deck"), sim), "on the walkway")
	g.world.free()


func test_the_players_own_shots_and_kills_are_counted_since_the_step_began() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var me = sim.avatar.player()
	me.x = 40.5
	me.y = 30.5
	var st := {"base": _base(sim)}
	check(not _ok(_c("shots", {"min": 1}), sim, st) and not _ok(_c("player_kills", {"min": 1}), sim, st), "nothing yet")
	# somebody else's kill is not the player's
	var other = sim.spawn(30.5, 40.5, "wander")
	sim._hurt_zombie(other, 100.0, 0.0, Tut.person(sim, "dez"))
	check(not _ok(_c("player_kills", {"min": 1}), sim, st), "Dez's kill is Dez's")
	# one of the dead in front of the gun, shot at with the real hands
	var z = sim.spawn(43.5, 30.5, "wander")
	z.hp = 1.0
	z.stagger = 1.0e6
	sim.avatar.set_input(Vector2.ZERO, Vector2(43.5, 30.2), true)
	Tut.run(sim, 1.2)
	sim.avatar.set_input(Vector2.ZERO, Vector2(43.5, 30.2), false)
	check(_ok(_c("shots", {"min": 1}), sim, st), "a round fired")
	check(_ok(_c("player_kills", {"min": 1}), sim, st), "and the one in front of it is down: the player's kill")
	check(not _ok(_c("player_kills", {"min": 5}), sim, st), "(one is not five)")
	# a step that begins later counts from then
	var later := {"base": _base(sim)}
	check(not _ok(_c("shots", {"min": 1}), sim, later) and not _ok(_c("player_kills", {"min": 1}), sim, later), "a later step starts from nothing")
	g.world.free()


func test_a_reload_is_the_key_and_a_full_magazine() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var me = sim.avatar.player()
	var spec := _c("reloaded")
	me.mag = 2
	check(not _ok(spec, sim, {"did": {}}), "no key pressed")
	check(not _ok(spec, sim, {"did": {"reload": 1.0}}), "pressed, and the gun is still low (the key was only pressed)")
	check(sim.avatar.reload(), "R is taken")
	Tut.run(sim, 0.2)
	check(me.reloading > 0.0 and not _ok(spec, sim, {"did": {"reload": 1.0}}), "while it goes on it does not hold")
	Tut.run(sim, float(me.gun.reload) + 0.5)
	check(_ok(spec, sim, {"did": {"reload": 1.0}}), "full again, and R was pressed: it does")
	check(not _ok(spec, sim, {"did": {}}), "full, but nobody pressed R")
	g.world.free()


func test_the_radios_answers_are_who_what_and_whether() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var st := {"events": {"radio_line:dez:come:ok": 1.0}}
	check(_ok(_c("asked", {"who": "dez"}), sim, st), "Dez was asked")
	check(_ok(_c("asked", {"who": "dez", "verb": "come"}), sim, st), "to come")
	check(_ok(_c("asked", {"who": "dez", "verb": "come", "ok": true}), sim, st), "and said yes")
	check(not _ok(_c("asked", {"who": "dez", "verb": "come", "ok": false}), sim, st), "not no")
	check(not _ok(_c("asked", {"who": "dez", "verb": "hold"}), sim, st), "another verb is not it")
	check(not _ok(_c("asked", {"who": "ana"}), sim, st), "Ana was not asked")
	check(_ok(_c("asked"), sim, st), "anyone at all")
	check(not _ok(_c("asked", {"who": "ana", "ok": false}), sim, {"events": {"radio_line:ana:come:ok": 1.0}}), "a yes is not a refusal")
	check(_ok(_c("asked", {"who": "ana", "ok": false}), sim, {"events": {"radio_line:ana:come:no": 2.0, "shot": 3.0}}), "a refusal is, among other events")
	check(not _ok(_c("asked", {"who": "dez"}), sim, {"events": {"radio_line:dez:come:ok": 0.0}}), "a count of none is none")
	check(not _ok(_c("asked", {"who": "dez"}), sim, {}), "no events")
	g.world.free()


func test_a_stance_is_what_they_do_after_they_were_asked() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var dez = Tut.person(sim, "dez")
	check(not _ok(_c("has_stance", {"who": "dez"}), sim), "no stance yet")
	var r: Dictionary = sim.radio.request(dez, "come")
	check(r.ok, "Dez agrees")
	check(not _ok(_c("has_stance", {"who": "dez", "stance": "follow"}), sim), "the moment he says so he does not follow yet")
	Tut.run(sim, 5.0)
	check(_ok(_c("has_stance", {"who": "dez", "stance": "follow"}), sim), "and then he does")
	check(_ok(_c("has_stance", {"who": "dez"}), sim), "(any stance)")
	check(not _ok(_c("has_stance", {"who": "dez", "stance": "hold"}), sim), "not another one")
	check(not _ok(_c("has_stance", {"who": "ana"}), sim), "not Ana")
	g.world.free()


func test_insisting_is_what_costs_trust() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var ana = Tut.person(sim, "ana")
	var spec := _c("insisted", {"who": "ana"})
	check(not _ok(spec, sim), "nobody has pushed her")
	sim.medical.jobs.append({"healer": ana, "patient": Tut.person(sim, "walt"), "kind": "bandage", "work": 0.0, "stand": null, "anchor": Vector2.ZERO})
	var asked: Dictionary = sim.radio.request(ana, "come")
	check(not asked.ok and not _ok(spec, sim), "asking and being refused costs nothing")
	var pushed: Dictionary = sim.radio.request(ana, "come", {"insist": true})
	check(pushed.ok and pushed.insisted, "pushed: she comes")
	check(_ok(spec, sim), "and she trusts the player less than she did")
	check(not _ok(_c("insisted", {"who": "dez"}), sim), "Dez does not")
	g.world.free()


func test_the_news_panel_was_open_at_some_time() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var st := {}
	check(not _ok(_c("news_open"), sim, st) and not _ok(_c("news_seen"), sim, st), "not opened")
	st["news"] = {"open": true}
	check(_ok(_c("news_open"), sim, st) and _ok(_c("news_seen"), sim, st), "open")
	st["news"] = {"open": false}
	check(not _ok(_c("news_open"), sim, st), "shut again: not open")
	check(_ok(_c("news_seen"), sim, st), "but it was seen: the condition kept the note")
	g.world.free()


func test_a_call_waits_and_is_answered_by_the_player_not_by_the_clock() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var radio = sim.radio
	# a call that was settled long before the step: not the step's
	var old: int = radio.raise_call("attack", "Old", "", [{"id": "hold", "label": "Hold"}], "hold", 30.0)
	radio.answer(old, "hold")
	var st := {"base": _base(sim)}
	check(not _ok(_c("call_open", {"kind": "attack"}), sim, st), "no call waits")
	check(not _ok(_c("call_answered", {"kind": "attack"}), sim, st), "and the old one is not an answer of this step")
	var id: int = radio.raise_call("attack", "Wall", "", [{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send"}], "hold", 30.0)
	check(_ok(_c("call_open", {"kind": "attack"}), sim, st) and _ok(_c("call_open"), sim, st), "a call waits")
	check(not _ok(_c("call_open", {"kind": "sick"}), sim, st), "(not a sick one)")
	check(not _ok(_c("call_answered", {"kind": "attack"}), sim, st), "not answered")
	# the clock answers it: that is not the lesson
	radio._settle(radio._entry(id), "hold", true)
	check(not _ok(_c("call_open", {"kind": "attack"}), sim, st), "settled: no longer open")
	check(not _ok(_c("call_answered", {"kind": "attack"}), sim, st), "by its default, which is not an answer")
	var id2: int = radio.raise_call("attack", "Wall", "", [{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send"}], "hold", 30.0)
	check(radio.answer(id2, "reinforce"), "the player answers")
	check(_ok(_c("call_answered", {"kind": "attack"}), sim, st), "and that is")
	check(not _ok(_c("call_answered", {"kind": "sick"}), sim, st), "(of that kind)")
	g.world.free()


func test_the_page_that_g_opens_was_read_when_a_place_was_chosen_and_it_is_shut() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var spec := _c("board_read")
	var st := {"dialog": {"open": false, "site": ""}}
	check(not _ok(spec, sim, st), "not opened")
	st.dialog = {"open": true, "site": ""}
	check(not _ok(spec, sim, st), "open, no place chosen")
	st.dialog = {"open": false, "site": ""}
	check(not _ok(spec, sim, st), "shut with no place chosen: only a look at the page")
	st.dialog = {"open": true, "site": "pharmacy"}
	check(not _ok(spec, sim, st), "a place chosen, the page still open")
	st.dialog = {"open": false, "site": ""}
	check(_ok(spec, sim, st), "shut again after a place was chosen: it was read")
	g.world.free()


func test_the_alarm_is_rung_and_stood_down() -> void:
	var g := Tut.make_avatar()
	var sim = g.sim
	var st := {}
	check(_ok(_c("alarm_on", {"on": false}), sim) and not _ok(_c("alarm_on"), sim), "off to begin with")
	check(not _ok(_c("alarm_cycled"), sim, st), "not rung")
	sim.radio.alarm(true)
	check(_ok(_c("alarm_on"), sim) and not _ok(_c("alarm_on", {"on": false}), sim), "rung")
	check(not _ok(_c("alarm_cycled"), sim, st), "rung is not rung and stood down")
	sim.radio.alarm(false)
	check(_ok(_c("alarm_cycled"), sim, st), "stood down after it was rung: the cycle")
	check(not _ok(_c("alarm_cycled"), sim, {}), "(with no note of it, it was never rung)")
	g.world.free()
