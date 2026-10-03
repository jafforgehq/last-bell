extends "res://tests/case.gd"
## The events of the live road (round 21, S21.1 EVENTS: scripts/drive/road_events.gd and assets/data/road_events.json): the deck,
## the plan of a leg, the night road, the card's options and their refusals, what a choice does (`resolve`) and what the colony's
## side of it writes (`apply`). Pure and deterministic by seed: the colony's own random numbers are never drawn. The simulation
## additions (road_wear, wreck, hold_on_road...) are in test_road_sim.gd.

const RoadEvents := preload("res://scripts/drive/road_events.gd")
const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")

const FIXTURE := "user://test_r21_events_town.json"
const DECK_FIXTURE := "user://test_r21_events_deck.json"
const IDS := ["ambush", "breakdown", "checkpoint", "fuel_stash", "herd", "roadblock", "smoke", "survivor", "wreck_supplies"]
const TOWN := {
	"board": {"w": 160, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "The houses", "kind": "houses", "pos": [59, 35], "blurb": "Doors shut.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {}},
		{"id": "garage", "name": "The garage", "kind": "garage", "pos": [41, 35], "blurb": "Grease and a pickup.", "danger": 2, "known": true,
			"loot": {"scrap": [10, 20]}, "extra": {}, "vehicle": "pickup", "nest": {"strength": 2}},
		{"id": "mill", "name": "The mill", "kind": "mill", "pos": [62, 36], "blurb": "Quiet.", "danger": 1, "known": false,
			"loot": {"food": [5, 9]}, "extra": {}},
		{"id": "pier", "name": "The pier", "kind": "pier", "pos": [100, 36], "blurb": "Far.", "danger": 1, "known": false,
			"loot": {"water": [5, 9]}, "extra": {}},
	],
	"roads": [["home", "houses"], ["home", "garage"], ["houses", "mill"], ["mill", "pier"]],
	"beats": [],
}


## What a `PlaceFlow` has of the road (the fields `RoadEvents` reads and writes), so that these tests do not depend on it.
class FakeFlow:
	extends RefCounted
	var sim
	var going: Array = []
	var place_id := "houses"
	var vehicle_id := ""
	var vehicle_alive := true
	var road_loot := {}
	var road_lost: Array = []
	var road_survivors := 0
	var road_morale := 0.0


## The same without a mood counter: `apply` shocks the people itself.
class BareFlow:
	extends RefCounted
	var sim
	var going: Array = []
	var place_id := "houses"
	var vehicle_id := ""
	var road_loot := {}
	var road_lost: Array = []
	var road_survivors := 0


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _game() -> Dictionary:
	_write(FIXTURE, TOWN)
	Town.data_path = FIXTURE
	var g := Helpers.make(17, 1, 3)
	Town.data_path = Town.DATA_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	sim.events.clear()
	return g


func _end(g: Dictionary) -> void:
	g.world.free()


func _crew(sim, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		for p in sim.people:
			if p.id == id:
				out.append(p)
	return out


## A flow of a trip by `kind` (or on foot: "") of the people `ids`.
func _flow(sim, ids: Array = ["dez", "marcus"], kind: String = "pickup", place: String = "houses"):
	var f := FakeFlow.new()
	f.sim = sim
	f.going = _crew(sim, ids)
	f.place_id = place
	if kind != "":
		var v: Dictionary = sim.vehicles.add(kind)
		f.vehicle_id = String(v.id)
	return f


## The leg's world with everything the deck may want: a vehicle, a bed, a seat, room in the tank, a plain day.
func _ctx(extra: Dictionary = {}) -> Dictionary:
	var c := {
		"leg": "there", "danger": 1, "by_vehicle": true, "seats_free": 2, "seats": 2, "vehicle_name": "Pickup", "road_min": 60.0,
		"leg_s": 60.0, "hour": 9.0, "dusk": 18.0, "dawn": 6.0, "bed": true, "hp_share": 1.0, "fuel_room": 30.0, "fuel": 10.0,
		"stock": {"food": 40, "water": 50, "scrap": 60, "meds": 10, "ammo": 300}, "leading": 2, "building": 2, "caller": "Mia",
	}
	c.merge(extra, true)
	return c


func _foot(extra: Dictionary = {}) -> Dictionary:
	var c := _ctx({"by_vehicle": false, "seats_free": 1, "seats": 3, "vehicle_name": ""})
	c.merge(extra, true)
	return c


func _entry(id: String, seed: int = 1, night: bool = false) -> Dictionary:
	var def: Dictionary = RoadEvents.deck()[id]
	return {"uid": "e1", "id": id, "kind": String(def.kind), "at": 0.5, "seed": seed, "night": night, "state": "pending", "def": def}


func _ids_of(plan: Array) -> Array:
	var out: Array = []
	for e in plan:
		out.append(String(e.id))
	return out


## The ids that come up over many seeds of a world: {id: count}.
func _tally(ctx: Dictionary, seeds: int = 300) -> Dictionary:
	var out := {}
	for s in seeds:
		for e in RoadEvents.plan(s, ctx):
			out[String(e.id)] = int(out.get(String(e.id), 0)) + 1
	return out


## Whether no entry of any plan over many seeds is of one of these ids.
func _never(ctx: Dictionary, ids: Array, seeds: int = 200) -> bool:
	var tally := _tally(ctx, seeds)
	for id in ids:
		if tally.has(id):
			return false
	return true


# ----------------------------------------------------------------------- the deck --

func test_the_deck_loads_nine_events() -> void:
	var ids: Array = RoadEvents.deck().keys()
	ids.sort()
	eq(ids, IDS, "the nine events of the plan")


func test_every_def_is_complete() -> void:
	var deck := RoadEvents.deck()
	for id in deck:
		var d: Dictionary = deck[id]
		eq(String(d.id), String(id), "%s: its own id" % id)
		check(String(d.title).strip_edges() != "" and String(d.text).strip_edges() != "", "%s: a title and a text" % id)
		check(RoadEvents.KINDS.has(String(d.kind)), "%s: a kind of the plan (%s)" % [id, d.kind])
		check(float(d.weight) > 0.0, "%s: a weight" % id)
		check(not (d.legs as Array).is_empty(), "%s: legs" % id)
		for leg in d.legs:
			check(RoadEvents.LEGS.has(String(leg)), "%s: a leg that exists (%s)" % [id, leg])
		check(["any", "needs", "foot"].has(String(d.vehicle)), "%s: vehicle" % id)
		check(["any", "day", "night"].has(String(d.band)), "%s: band" % id)
		check(["always", "vehicle", "never"].has(String(d.card)), "%s: card" % id)
		check(["auto", "close"].has(String(d.timeout)), "%s: timeout" % id)
		check(float(d.ttl_s) > 0.0, "%s: ttl_s" % id)
		check(int(d.min_danger) >= 0, "%s: min_danger" % id)
		check(not (d.choices as Array).is_empty(), "%s: at least one choice" % id)
		var ids: Array = []
		for c in d.choices:
			ids.append(String(c.id))
			check(String(c.id) != "" and String(c.label).strip_edges() != "", "%s: a choice has an id and a label" % id)
			check(not (c.lines as Array).is_empty(), "%s/%s: the squad has words" % [id, c.id])
			for line in c.lines:
				check(String(line).strip_edges() != "", "%s/%s: no empty line" % [id, c.id])
			check(String(c.log.text).strip_edges() != "" and String(c.log.sub).strip_edges() != "", "%s/%s: the radio has a line" % [id, c.id])
		check(ids.has(String(d.auto)), "%s: auto names a choice (%s)" % [id, d.auto])
		for a in d.auto_else:
			check(ids.has(String(a)), "%s: auto_else names a choice (%s)" % [id, a])
		for i in ids.size():
			check(ids.find(ids[i]) == i, "%s: choice ids are unique" % id)


## Every effect a choice can have, wherever it hides (the choice, its dice branches).
func _all_effects(choice: Dictionary) -> Array:
	var out: Array = [choice.effects]
	if choice.has("maybe"):
		out.append(choice.maybe.get("effects", {}))
	for o in choice.get("one_of", []):
		out.append(o.get("effects", {}))
	if choice.has("gamble"):
		out.append(choice.gamble.win.get("effects", {}))
		out.append(choice.gamble.lose.get("effects", {}))
	return out


func test_effects_are_from_the_vocabulary_and_no_text_is_a_placeholder() -> void:
	var deck := RoadEvents.deck()
	for id in deck:
		for c in deck[id].choices:
			for fx in _all_effects(c):
				for k in fx:
					check(RoadEvents.EFFECT_KEYS.has(String(k)) and String(k) != "pick", "%s/%s: effect '%s' is in the vocabulary" % [id, c.id, k])
			var texts: Array = [c.label, c.log.text, c.log.sub]
			texts.append_array(c.lines)
			texts.append_array([deck[id].title, deck[id].text])
			for t in texts:
				var low := String(t).to_lower()
				check(not low.contains("todo") and not low.contains("placeholder") and not low.contains("xxx") and not low.contains("lorem"), "%s/%s: '%s' is real text" % [id, c.id, t])


func test_the_ambient_night_road_has_its_words() -> void:
	var amb := RoadEvents.ambient_def("night_road")
	check(String(amb.title) != "" and String(amb.text) != "", "a title and a text")
	check(not (amb.lines as Array).is_empty(), "the squad has words")
	check(String(amb.log.text) != "" and String(amb.log.sub) != "", "and the radio a line")
	near(float(amb.dead_mult), 1.5, 1e-9, "the dead x1.5")
	check(RoadEvents.ambient_def("no_such_road").is_empty(), "an ambient that is not there is {}")


func test_a_deck_can_be_read_from_another_file_and_a_missing_one_is_an_empty_deck() -> void:
	_write(DECK_FIXTURE, {"events": {"only": {"title": "Only", "text": "The only event.", "kind": "stop", "weight": 1, "card": "always", "auto": "go",
		"choices": [{"id": "go", "label": "Go", "effects": {}, "lines": ["On."], "log": {"text": "Went on.", "sub": "Yes."}}]}}})
	RoadEvents.data_path = DECK_FIXTURE
	RoadEvents.forget()
	var ids: Array = RoadEvents.deck().keys()
	var plan := RoadEvents.plan(5, _ctx())
	var planned := _ids_of(plan)
	RoadEvents.data_path = "user://test_r21_events_no_such_deck.json"
	RoadEvents.forget()
	var empty := RoadEvents.deck()
	var none := RoadEvents.plan(5, _ctx())
	RoadEvents.data_path = RoadEvents.DATA_PATH
	RoadEvents.forget()
	eq(ids, ["only"], "the other file's deck")
	check(not planned.is_empty() and planned.all(func(id): return id == "only"), "and its plan (an event may repeat when it is the only one: twice at most)")
	check(planned.size() <= RoadEvents.MAX_SAME, "(%d of them)" % planned.size())
	check(empty.is_empty() and none.is_empty(), "a file that is not there: no deck, no plan, no error")
	eq(RoadEvents.deck().size(), 9, "and the real deck is back")


# ------------------------------------------------------------------------- plan --

func test_a_plan_is_deterministic_and_differs_across_seeds() -> void:
	var a := RoadEvents.plan(7, _ctx())
	var b := RoadEvents.plan(7, _ctx())
	eq(JSON.stringify(a), JSON.stringify(b), "the same seed, the same leg")
	var seen := {}
	for s in range(1, 41):
		var p := RoadEvents.plan(s, _ctx({"leg_s": 90.0}))
		var sig: Array = []
		for e in p:
			sig.append([String(e.id), snappedf(float(e.at), 0.001)])
		seen[str(sig)] = true
	check(seen.size() >= 35, "forty seeds make %d different plans" % seen.size())
	check(JSON.stringify(RoadEvents.plan(7, _ctx({"leg": "home"}))) != JSON.stringify(a), "the road home is another plan from the road there")


func test_an_entry_has_the_shape_of_the_plan() -> void:
	var plan := RoadEvents.plan(3, _ctx({"leg_s": 90.0}))
	check(plan.size() >= 3, "a long leg has events")
	var deck := RoadEvents.deck()
	var last := -1.0
	var uids := {}
	for e in plan:
		for k in ["uid", "id", "kind", "at", "seed", "night", "state", "def"]:
			check(e.has(k), "entry has %s" % k)
		check(String(e.uid).begins_with("e") and not uids.has(String(e.uid)), "uid %s is its own" % e.uid)
		uids[String(e.uid)] = true
		check(deck.has(String(e.id)), "an event of the deck")
		eq(String(e.kind), String(deck[e.id].kind), "its kind is the def's")
		eq(String(e.def.id), String(e.id), "it carries its def")
		eq(String(e.state), "pending", "not met yet")
		check(typeof(e.seed) == TYPE_INT and typeof(e.night) == TYPE_BOOL, "types")
		check(float(e.at) > last, "sorted by at")
		last = float(e.at)
	eq(plan[0].uid, "e1", "the first is e1")


func test_the_number_of_events_follows_the_leg_and_the_danger() -> void:
	for pair in [[30.0, 1], [37.0, 1], [38.0, 2], [50.0, 2], [62.0, 2], [63.0, 3], [75.0, 3], [88.0, 4], [90.0, 4]]:
		for s in range(1, 21):
			eq(RoadEvents.plan(s, _ctx({"leg_s": pair[0], "danger": 1})).size(), int(pair[1]), "a %s second leg (seed %d)" % [pair[0], s])
	for pair in [[30.0, 2], [50.0, 3], [75.0, 4], [90.0, 5]]:
		for s in range(1, 21):
			eq(RoadEvents.plan(s, _ctx({"leg_s": pair[0], "danger": 3})).size(), int(pair[1]), "a %s second leg at danger 3 has one more (seed %d)" % [pair[0], s])
	eq(RoadEvents.plan(2, _ctx({"leg_s": 10.0})).size(), 1, "never fewer than one")
	eq(RoadEvents.plan(2, _ctx({"leg_s": 900.0, "danger": 9})).size(), 5, "never more than five")


func test_events_are_inside_the_road_and_apart() -> void:
	for s in 300:
		var plan := RoadEvents.plan(s, _ctx({"leg_s": 90.0, "danger": 3}))
		eq(plan.size(), 5, "five events (seed %d)" % s)
		for i in plan.size():
			var at := float(plan[i].at)
			check(at >= 0.12 - 1e-9 and at <= 0.9 + 1e-9, "at %.3f is inside [0.12, 0.9] (seed %d)" % [at, s])
			if i > 0:
				check(at - float(plan[i - 1].at) >= 0.12 - 1e-9, "events %d and %d are %.3f apart (seed %d)" % [i - 1, i, at - float(plan[i - 1].at), s])


func test_never_the_same_event_twice_in_a_row_nor_more_than_twice_a_leg() -> void:
	for s in 300:
		var ids := _ids_of(RoadEvents.plan(s, _ctx({"leg_s": 90.0, "danger": 3})))
		var counts := {}
		for i in ids.size():
			counts[ids[i]] = int(counts.get(ids[i], 0)) + 1
			if i > 0:
				check(ids[i] != ids[i - 1], "%s twice in a row (seed %d)" % [ids[i], s])
		for id in counts:
			check(int(counts[id]) <= 2, "%s %d times (seed %d)" % [id, counts[id], s])


func test_what_the_world_does_not_allow_does_not_come() -> void:
	check(_never(_foot(), ["breakdown", "fuel_stash"]), "no breakdown and no fuel on foot")
	check(_never(_ctx({"bed": false}), ["survivor"]), "no survivor with no bed")
	check(_never(_ctx({"seats_free": 0}), ["survivor"]), "no survivor with no seat")
	check(_never(_ctx({"fuel_room": 2.0}), ["fuel_stash"]), "no fuel stash with a tank that is full")
	check(_never(_ctx({"danger": 0}), ["ambush", "checkpoint"]), "no ambush and no checkpoint on a quiet road")
	var night := _ctx({"hour": 20.0, "road_min": 60.0})
	check(_never(night, ["checkpoint", "herd"]), "no checkpoint and no herd at night")
	var rich := _tally(_ctx())
	for id in ["survivor", "fuel_stash", "breakdown", "checkpoint", "herd", "ambush"]:
		check(int(rich.get(id, 0)) > 0, "(%s does come when the world allows it)" % id)
	check(int(_tally(night).get("ambush", 0)) > 0, "(an ambush is for the night too)")
	var foot_tally := _tally(_foot())
	check(int(foot_tally.get("roadblock", 0)) > 0, "(a roadblock is on foot too: a pile-up)")


func test_the_hour_of_the_slot_decides_day_and_night() -> void:
	# the leg starts at 16:00 and takes three hours: dusk (18:00) is two thirds of the way
	var ctx := _ctx({"hour": 16.0, "road_min": 180.0, "leg_s": 90.0, "danger": 2})
	var nights := 0
	var days := 0
	for s in 200:
		for e in RoadEvents.plan(s, ctx):
			var hour := 16.0 + float(e.at) * 3.0
			eq(bool(e.night), hour >= 18.0, "the slot at %.2f of the road is at %.1f o'clock (seed %d)" % [e.at, hour, s])
			if bool(e.night):
				nights += 1
				check(not ["herd", "checkpoint"].has(String(e.id)), "%s at night (seed %d)" % [e.id, s])
			else:
				days += 1
	check(nights > 50 and days > 50, "both come up (%d night, %d day)" % [nights, days])
	# after midnight and before dawn is night too
	for e in RoadEvents.plan(4, _ctx({"hour": 23.0, "road_min": 240.0, "leg_s": 90.0})):
		eq(bool(e.night), fposmod(23.0 + float(e.at) * 4.0, 24.0) < 6.0 or fposmod(23.0 + float(e.at) * 4.0, 24.0) >= 18.0, "the hours wrap round midnight")


func test_a_def_keeps_to_its_legs_and_bands() -> void:
	var base := {"title": "T", "text": "Text.", "kind": "stop", "weight": 1, "card": "always", "auto": "go",
		"choices": [{"id": "go", "label": "Go", "effects": {}, "lines": ["On."], "log": {"text": "Went on.", "sub": "Yes."}}]}
	var homeward := base.duplicate(true)
	homeward["legs"] = ["home"]
	var nightly := base.duplicate(true)
	nightly["band"] = "night"
	var plain := base.duplicate(true)
	_write(DECK_FIXTURE, {"events": {"homeward": homeward, "nightly": nightly, "plain": plain}})
	RoadEvents.data_path = DECK_FIXTURE
	RoadEvents.forget()
	var there := _tally(_ctx({"leg": "there"}))
	var home := _tally(_ctx({"leg": "home"}))
	var in_the_day := _tally(_ctx({"hour": 9.0}))
	var in_the_dark := _tally(_ctx({"hour": 21.0}))
	RoadEvents.data_path = RoadEvents.DATA_PATH
	RoadEvents.forget()
	check(not there.has("homeward") and home.has("homeward"), "a def of the road home is not on the road there")
	check(not in_the_day.has("nightly") and in_the_dark.has("nightly"), "a night def is for the night only")
	check(in_the_day.has("plain") and in_the_dark.has("plain"), "and a plain one for both")


func test_every_event_comes_up_and_none_dominates() -> void:
	var tally := _tally(_ctx({"danger": 2}), 300)
	var total := 0
	for id in tally:
		total += int(tally[id])
	for id in IDS:
		check(int(tally.get(id, 0)) > 0, "%s comes up in 300 seeds" % id)
		check(float(tally.get(id, 0)) / float(total) < 0.3, "%s is %.0f%% of what comes up" % [id, 100.0 * float(tally.get(id, 0)) / float(total)])
		check(float(tally.get(id, 0)) / float(total) > 0.02, "%s is not a rarity (%.0f%%)" % [id, 100.0 * float(tally.get(id, 0)) / float(total)])


func test_the_dead_come_more_with_danger_and_breakdowns_with_wear() -> void:
	var dead_share := func(danger: int) -> float:
		var t := _tally(_ctx({"danger": danger, "leg_s": 90.0}), 300)
		var total := 0
		for id in t:
			total += int(t[id])
		return float(int(t.get("ambush", 0)) + int(t.get("herd", 0))) / float(total)
	check(float(dead_share.call(3)) > float(dead_share.call(1)) + 0.02, "an ambush or a herd is likelier at danger 3 (%.2f) than at 1 (%.2f)" % [dead_share.call(3), dead_share.call(1)])
	var worn := int(_tally(_ctx({"hp_share": 0.2}), 400).get("breakdown", 0))
	var sound := int(_tally(_ctx({"hp_share": 1.0}), 400).get("breakdown", 0))
	check(worn > sound + 10, "a worn car breaks down more (%d against %d)" % [worn, sound])


func test_planning_draws_nothing_from_the_colony() -> void:
	var g := _game()
	var sim = g.sim
	var before: int = sim.rng.state
	var plan := RoadEvents.plan(11, _ctx())
	for e in plan:
		RoadEvents.options(e, _ctx())
		RoadEvents.resolve(e, String(e.def.auto), _ctx())
	RoadEvents.ambient_for(_ctx({"hour": 20.0}))
	eq(int(sim.rng.state), before, "the rules' dice were not thrown")
	_end(g)


# ---------------------------------------------------------------------- ambient --

func test_the_night_road_is_on_after_dusk_and_across_it() -> void:
	var on := RoadEvents.ambient_for(_ctx({"hour": 19.0, "road_min": 60.0}))
	eq(on.size(), 1, "after dusk")
	eq(String(on[0].id), "night_road", "the night road")
	near(float(on[0].dead_mult), 1.5, 1e-9, "the dead x1.5")
	near(float(on[0].runner_share), 0.15, 1e-9, "a share of runners")
	check(bool(on[0].headlights), "with the headlights")
	eq(RoadEvents.ambient_for(_ctx({"hour": 4.0, "road_min": 60.0})).size(), 1, "before dawn")
	eq(RoadEvents.ambient_for(_ctx({"hour": 16.5, "road_min": 120.0})).size(), 1, "a leg that crosses dusk")
	eq(RoadEvents.ambient_for(_ctx({"hour": 9.0, "road_min": 60.0})).size(), 0, "a day leg has none")
	eq(RoadEvents.ambient_for(_ctx({"hour": 16.0, "road_min": 60.0})).size(), 0, "one that ends before dusk has none")
	eq(RoadEvents.ambient_for(_ctx({"hour": 17.0, "road_min": 60.0})).size(), 1, "one that ends at dusk crosses it")
	eq(RoadEvents.ambient_for(_ctx({"hour": 7.0, "road_min": 60.0, "dawn": 7.5})).size(), 1, "dawn is the season's own")


# ---------------------------------------------------------------------- options --

func _by_id(options: Array) -> Dictionary:
	var out := {}
	for o in options:
		out[String(o.id)] = o
	return out


func test_every_refused_option_says_why_and_no_other_does() -> void:
	var worlds: Array = [
		_ctx(), _foot(),
		_ctx({"seats_free": 0, "bed": false, "fuel_room": 0.0, "stock": {}, "leading": 0, "building": 0}),
		_foot({"seats_free": 0, "bed": false, "fuel_room": 0.0, "stock": {"scrap": 5, "food": 3}}),
		_ctx({"stock": {"scrap": 19}}),
	]
	var refused := 0
	for ctx in worlds:
		for id in IDS:
			var entry := _entry(id)
			var autos := 0
			for o in RoadEvents.options(entry, ctx):
				if bool(o.ok):
					eq(String(o.why), "", "%s/%s: nothing to explain" % [id, o.id])
				else:
					refused += 1
					check(String(o.why).strip_edges() != "", "%s/%s refused with no reason" % [id, o.id])
					check(not bool(o.auto), "%s/%s: a refused option is never the auto one" % [id, o.id])
				if bool(o.auto):
					autos += 1
				check(String(o.label) != "", "%s/%s: a label" % [id, o.id])
			check(autos <= 1, "%s: at most one auto option" % id)
	check(refused >= 8, "(the worlds do refuse things: %d)" % refused)


func test_the_survivor_is_refused_for_a_seat_and_a_bed_in_words() -> void:
	var entry := _entry("survivor")
	var ok := _by_id(RoadEvents.options(entry, _ctx()))
	check(bool(ok.take.ok) and bool(ok.pass.ok), "with a bed and a seat both can be chosen")
	check(bool(ok.pass.auto) and not bool(ok.take.auto), "driving on is what the card does by itself")
	var full := _by_id(RoadEvents.options(entry, _ctx({"seats_free": 0})))
	check(not bool(full.take.ok), "no seat")
	eq(String(full.take.why), "No seat free: the pickup seats 2", "the reason names the car")
	check(bool(full.pass.ok), "driving on is always allowed")
	var foot := _by_id(RoadEvents.options(entry, _foot({"seats_free": 0})))
	check(String(foot.take.why).to_lower().contains("three"), "on foot: '%s'" % foot.take.why)
	var bedless := _by_id(RoadEvents.options(entry, _ctx({"bed": false})))
	check(not bool(bedless.take.ok) and String(bedless.take.why).to_lower().contains("bed"), "no bed: '%s'" % bedless.take.why)


func test_the_checkpoint_options_and_what_they_need() -> void:
	var entry := _entry("checkpoint")
	var rich := _by_id(RoadEvents.options(entry, _ctx()))
	check(bool(rich.toll.ok) and bool(rich.trade.ok) and bool(rich.talk.ok) and bool(rich.run.ok), "a rich party by car has all four")
	check(bool(rich.toll.auto), "it pays the toll by itself")
	var poor := _by_id(RoadEvents.options(entry, _ctx({"stock": {"food": 4, "scrap": 3, "ammo": 0}})))
	check(not bool(poor.toll.ok) and String(poor.toll.why).to_lower().contains("toll"), "too little for a toll: '%s'" % poor.toll.why)
	check(not bool(poor.trade.ok) and String(poor.trade.why).contains("only 3 scrap"), "and for a trade: '%s'" % poor.trade.why)
	check(bool(poor.talk.ok), "talking is free")
	check(bool(poor.talk.auto) and not bool(poor.toll.auto), "with no toll to pay the card talks by itself")
	var none := _by_id(RoadEvents.options(entry, _ctx({"stock": {}})))
	check(String(none.trade.why) == "You have no scrap to trade", "no scrap at all: '%s'" % none.trade.why)
	var foot := _by_id(RoadEvents.options(entry, _foot()))
	check(not bool(foot.run.ok) and String(foot.run.why) == "You are on foot", "nobody runs a barrier on foot: '%s'" % foot.run.why)


func test_cards_that_ask_nothing_have_no_options() -> void:
	eq(RoadEvents.options(_entry("ambush"), _ctx()).size(), 0, "an ambush asks nothing")
	eq(RoadEvents.options(_entry("herd"), _ctx()).size(), 0, "nor does a herd")
	eq(RoadEvents.options(_entry("roadblock"), _foot()).size(), 0, "a pile-up is climbed on foot: no card")
	var block := RoadEvents.options(_entry("roadblock"), _ctx())
	eq(block.size(), 1, "a car at a roadblock can clear it")
	eq(String(block[0].id), "clear", "that")
	check(bool(block[0].ok) and not bool(block[0].auto), "and nothing is done by itself: the card closes")
	eq(RoadEvents.options({}, _ctx()).size(), 0, "no entry, no card")
	var fix := RoadEvents.options(_entry("breakdown"), _ctx())
	check(fix.size() == 1 and bool(fix[0].ok) and bool(fix[0].auto), "the puncture is fixed by itself")


# ---------------------------------------------------------------------- resolve --

func test_resolve_is_deterministic_and_pure() -> void:
	for id in IDS:
		for c in RoadEvents.deck()[id].choices:
			var entry := _entry(id, 41)
			var ctx := _ctx()
			var entry_before := entry.duplicate(true)
			var ctx_before := ctx.duplicate(true)
			var a := RoadEvents.resolve(entry, String(c.id), ctx)
			var b := RoadEvents.resolve(entry, String(c.id), ctx)
			eq(JSON.stringify(a), JSON.stringify(b), "%s/%s: the same twice" % [id, c.id])
			eq(JSON.stringify(entry), JSON.stringify(entry_before), "%s/%s: the entry is not changed" % [id, c.id])
			eq(JSON.stringify(ctx), JSON.stringify(ctx_before), "%s/%s: the ctx is not changed" % [id, c.id])
	var varied := {}
	for s in 30:
		varied[JSON.stringify(RoadEvents.resolve(_entry("wreck_supplies", s), "search", _ctx())["effects"])] = true
	check(varied.size() >= 6, "other seeds find other things (%d kinds)" % varied.size())


func test_every_choice_resolves_into_real_words_and_vocabulary() -> void:
	for id in IDS:
		for c in RoadEvents.deck()[id].choices:
			for s in 25:
				var r := RoadEvents.resolve(_entry(id, s, s % 2 == 0), String(c.id), _ctx({"danger": 1 + s % 3}))
				check(bool(r.ok), "%s/%s resolves (seed %d)" % [id, c.id, s])
				for k in r.effects:
					check(RoadEvents.EFFECT_KEYS.has(String(k)), "%s/%s: '%s' is in the vocabulary" % [id, c.id, k])
				check(not (r.lines as Array).is_empty() and (r.lines as Array).size() <= 2, "%s/%s: one or two lines" % [id, c.id])
				for line in r.lines:
					check(String(line).strip_edges() != "" and not String(line).contains("{") and not String(line).contains("}"), "%s/%s: line '%s'" % [id, c.id, line])
				eq(String(r.log.kind), "road", "%s/%s: the radio's road kind" % [id, c.id])
				for k in ["text", "sub"]:
					check(String(r.log[k]).strip_edges() != "" and not String(r.log[k]).contains("{"), "%s/%s: log %s '%s'" % [id, c.id, k, r.log[k]])
				near(float(r.stop_s), float(r.effects.get("stop_s", 0.0)), 1e-9, "%s/%s: stop_s is the effect's" % [id, c.id])
				if r.effects.has("dead"):
					eq(r.spawn, r.effects.dead, "%s/%s: spawn is the dead" % [id, c.id])
				else:
					eq(r.spawn, {}, "%s/%s: nothing to spawn" % [id, c.id])
				check(not r.effects.has("pick") or r.effects.has("hurt"), "%s/%s: a pick only for a hurt" % [id, c.id])


func test_a_refused_or_unknown_choice_is_not_ok_and_says_why() -> void:
	var entry := _entry("survivor", 3)
	var ctx := _ctx({"seats_free": 0})
	var r := RoadEvents.resolve(entry, "take", ctx)
	check(not bool(r.ok), "refused")
	eq(String(r.why), String(_by_id(RoadEvents.options(entry, ctx)).take.why), "with the card's own reason")
	check(r.effects.is_empty() and float(r.stop_s) == 0.0 and r.spawn.is_empty() and r.log.is_empty(), "and it does nothing")
	check(not (r.lines as Array).is_empty(), "(the reason is the line)")
	var none := RoadEvents.resolve(entry, "no_such_choice", _ctx())
	check(not bool(none.ok) and String(none.why) != "", "a choice that is not there")


func test_an_ambush_brings_eight_to_fourteen_more_with_danger_and_runners_from_two() -> void:
	for danger in [1, 2, 3]:
		var low := 999
		var high := 0
		for s in 200:
			var r := RoadEvents.resolve(_entry("ambush", s), "through", _ctx({"danger": danger}))
			var d: Dictionary = r.spawn
			eq(String(d.where), "verges", "from both verges")
			eq(String(d.state), "hunt", "hunting")
			check(int(d.walker) >= 8 + 3 * danger and int(d.walker) <= 14 + 3 * danger, "%d walkers at danger %d" % [d.walker, danger])
			if danger < 2:
				eq(int(d.runner), 0, "no runners at danger 1")
			else:
				check(int(d.runner) >= 1 + danger and int(d.runner) <= 3 + danger, "%d runners at danger %d" % [d.runner, danger])
			low = mini(low, int(d.walker))
			high = maxi(high, int(d.walker))
		check(low == 8 + 3 * danger and high == 14 + 3 * danger, "the whole range comes up at danger %d (%d to %d)" % [danger, low, high])
	var day := RoadEvents.resolve(_entry("ambush", 5, false), "through", _ctx({"danger": 1}))
	var dark := RoadEvents.resolve(_entry("ambush", 5, true), "through", _ctx({"danger": 1}))
	eq(int(dark.spawn.walker), roundi(float(day.spawn.walker) * 1.5), "at night there are half as many again")
	eq(int(day.spawn.walker) + int(day.spawn.runner), int(String(day.log.text).get_slice("of the dead", 0).get_slice(": ", 1)), "the radio counts them")


func test_a_herd_is_twenty_four_to_thirty_six_standing() -> void:
	for s in 100:
		var d: Dictionary = RoadEvents.resolve(_entry("herd", s), "plough", _ctx())["spawn"]
		check(int(d.walker) >= 24 and int(d.walker) <= 36, "%d in the herd" % d.walker)
		eq(String(d.state), "still", "they are not awake")
		eq(String(d.where), "ahead", "ahead")
		eq(int(d.runner) + int(d.brute), 0, "walkers only")


func test_clearing_a_roadblock_takes_fourteen_seconds_and_brings_a_few_dead() -> void:
	for s in 60:
		var r := RoadEvents.resolve(_entry("roadblock", s), "clear", _ctx())
		near(float(r.stop_s), 14.0, 1e-9, "fourteen seconds")
		check(int(r.spawn.walker) >= 3 and int(r.spawn.walker) <= 6, "%d dead come" % r.spawn.walker)
		eq(String(r.spawn.where), "around", "around them while they work")
		eq(int(r.effects.block_cleared), 1, "and the block is cleared")


func test_the_survivor_card() -> void:
	var take := RoadEvents.resolve(_entry("survivor", 2), "take", _ctx())
	eq(int(take.effects.survivor), 1, "a survivor")
	near(float(take.effects.trust), 2.0, 1e-9, "trust +2")
	near(float(take.effects.morale), 2.0, 1e-9, "morale +2")
	near(float(take.stop_s), 4.0, 1e-9, "four seconds")
	check(String(take.log.text).begins_with("Mia"), "it is the caller: '%s'" % take.log.text)
	var nameless := RoadEvents.resolve(_entry("survivor", 2), "take", _ctx({"caller": ""}))
	check(String(nameless.log.text).begins_with("The stranger"), "or a stranger: '%s'" % nameless.log.text)
	var pass_by := RoadEvents.resolve(_entry("survivor", 2), "pass", _ctx())
	near(float(pass_by.effects.trust), -1.0, 1e-9, "driving on costs trust")
	check(not pass_by.effects.has("survivor") and float(pass_by.stop_s) == 0.0, "and nothing else")


func test_searching_a_wreck_finds_two_stocks_and_may_cost_a_scratch() -> void:
	for danger in [0, 2, 3]:
		for s in 40:
			var r := RoadEvents.resolve(_entry("wreck_supplies", s), "search", _ctx({"danger": danger}))
			near(float(r.stop_s), 10.0, 1e-9, "ten seconds")
			var stock: Dictionary = r.effects.stock
			eq(stock.size(), 2, "two stocks (danger %d, seed %d)" % [danger, s])
			for k in stock:
				check(RoadEvents.STOCKS.has(String(k)), "%s is a stock" % k)
				eq(int(stock[k]), 7 + 3 * danger, "%d of each at danger %d" % [7 + 3 * danger, danger])
	var hurt := 0
	for s in 600:
		var r := RoadEvents.resolve(_entry("wreck_supplies", s), "search", _ctx())
		if r.effects.has("dead"):
			hurt += 1
			eq(int(r.spawn.walker), 1, "one walker")
			eq(String(r.effects.hurt), "scratch", "and a scratch")
			check(r.effects.has("pick"), "for one of them")
		else:
			check(not r.effects.has("hurt"), "no scratch without the walker")
	check(hurt >= 120 and hurt <= 240, "about 30%% were bitten by a walker (%d of 600)" % hurt)
	var pass_by := RoadEvents.resolve(_entry("wreck_supplies", 1), "pass", _ctx())
	check(pass_by.effects.is_empty() and float(pass_by.stop_s) == 0.0, "driving on takes nothing")


func test_a_puncture_takes_as_long_as_the_best_builder_lets_it() -> void:
	for pair in [[0, 14.0], [2, 11.0], [5, 6.5], [6, 6.0], [10, 6.0]]:
		var r := RoadEvents.resolve(_entry("breakdown", 4), "fix", _ctx({"building": pair[0]}))
		near(float(r.stop_s), float(pair[1]), 1e-9, "building %d" % pair[0])
		eq(int(r.effects.vehicle_hp), -2, "the car takes a knock")
	check(String(RoadEvents.resolve(_entry("breakdown", 4), "fix", _ctx({"building": 2}))["log"]["text"]).contains("11 seconds"), "the radio says how long")


func test_a_fuel_stash_gives_four_to_nine() -> void:
	var seen := {}
	for s in 100:
		var r := RoadEvents.resolve(_entry("fuel_stash", s), "siphon", _ctx())
		var n := int(r.effects.fuel)
		check(n >= 4 and n <= 9, "%d fuel" % n)
		near(float(r.stop_s), 9.0, 1e-9, "nine seconds")
		seen[n] = true
		check(String(r.log.text).contains("%d fuel" % n), "the radio says so: '%s'" % r.log.text)
	eq(seen.size(), 6, "all of 4 to 9 come up")
	var full := RoadEvents.resolve(_entry("fuel_stash", 1), "siphon", _ctx({"fuel_room": 0.0}))
	check(not bool(full.ok) and String(full.why).to_lower().contains("full"), "a full tank cannot siphon: '%s'" % full.why)


func test_the_checkpoint_toll_trade_talk_and_run() -> void:
	# the toll: ten of something they have ten of
	for s in 40:
		var r := RoadEvents.resolve(_entry("checkpoint", s), "toll", _ctx({"stock": {"food": 4, "scrap": 60, "ammo": 3}}))
		eq(r.effects.stock, {"scrap": -10}, "only the scrap can pay")
		check(String(r.log.text).contains("10 scrap"), "'%s'" % r.log.text)
	var picked := {}
	for s in 60:
		for k in RoadEvents.resolve(_entry("checkpoint", s), "toll", _ctx())["effects"]["stock"]:
			picked[k] = true
	check(picked.size() >= 2 and not picked.has("water") and not picked.has("meds"), "it is food, scrap or ammo by the seed (%s)" % str(picked.keys()))
	# the trade: twenty scrap for eight fuel or three meds
	var got_fuel := 0
	var got_meds := 0
	for s in 80:
		var r := RoadEvents.resolve(_entry("checkpoint", s), "trade", _ctx())
		eq(int(r.effects.stock.scrap), -20, "twenty scrap")
		if r.effects.has("fuel"):
			got_fuel += 1
			eq(int(r.effects.fuel), 8, "eight fuel")
			check(not r.effects.stock.has("meds"), "and no meds")
		else:
			got_meds += 1
			eq(int(r.effects.stock.meds), 3, "or three meds")
	check(got_fuel > 15 and got_meds > 15, "both come up (%d fuel, %d meds)" % [got_fuel, got_meds])
	for s in 20:
		var r := RoadEvents.resolve(_entry("checkpoint", s), "trade", _ctx({"fuel_room": 0.0}))
		check(not r.effects.has("fuel") and int(r.effects.stock.meds) == 3, "a full tank takes meds")
	# the talk: a gamble on the best Leading
	for leading in [0, 5]:
		var won := 0
		for s in 600:
			var r := RoadEvents.resolve(_entry("checkpoint", s), "talk", _ctx({"leading": leading}))
			if r.effects.has("reveal"):
				won += 1
				eq(String(r.effects.reveal), "near", "the win shows a place")
				check(not r.effects.has("hp_all") and not r.effects.has("stock"), "and costs nothing")
			else:
				near(float(r.effects.hp_all), -3.0, 1e-9, "the loss: bruised")
				eq(int(r.effects.stock.values()[0]), -20, "and a toll of twenty")
		var want := 0.35 + 0.06 * float(leading)
		near(float(won) / 600.0, want, 0.07, "the chance with Leading %d" % leading)
	# running it
	var run := RoadEvents.resolve(_entry("checkpoint", 9), "run", _ctx())
	eq(int(run.effects.vehicle_hp), -10, "the car loses ten")
	eq(String(run.effects.hurt), "scratch", "someone is scratched")
	check(run.effects.has("pick"), "(one of them)")
	near(float(run.effects.trust), -2.0, 1e-9, "and trust falls")
	check(not bool(RoadEvents.resolve(_entry("checkpoint", 9), "run", _foot())["ok"]), "not on foot")


func test_smoke_shows_a_place_and_may_bring_a_walker() -> void:
	var walkers := 0
	for s in 500:
		var r := RoadEvents.resolve(_entry("smoke", s), "check", _ctx())
		near(float(r.stop_s), 5.0, 1e-9, "five seconds")
		eq(String(r.effects.reveal), "near", "a place on the map")
		if r.effects.has("dead"):
			walkers += 1
			eq(int(r.spawn.walker), 1, "one walker")
	check(walkers >= 100 and walkers <= 200, "about 30%% bring one (%d of 500)" % walkers)


func test_the_squad_says_two_of_its_lines_by_the_seed() -> void:
	var seen := {}
	for s in 40:
		var r := RoadEvents.resolve(_entry("ambush", s), "through", _ctx())
		eq((r.lines as Array).size(), 2, "two of the three")
		eq((r.lines as Array)[0] == (r.lines as Array)[1], false, "not the same twice")
		seen[str(r.lines)] = true
	check(seen.size() >= 2, "other seeds say other things")
	eq((RoadEvents.resolve(_entry("breakdown", 1), "fix", _ctx())["lines"] as Array).size(), 2, "two lines said as they are")
	eq((RoadEvents.resolve(_entry("checkpoint", 1), "toll", _ctx())["lines"] as Array).size(), 2, "and a card's")


func test_a_ctx_that_carries_the_flow_counts_the_survivors_already_taken() -> void:
	var g := _game()
	var sim = g.sim
	var f = _flow(sim, ["dez"])
	var ctx := _ctx({"seats_free": 1, "bed": true})
	ctx["flow"] = f
	check(bool(_by_id(RoadEvents.options(_entry("survivor"), ctx)).take.ok), "a seat and a bed: they may be taken in")
	f.road_survivors = 1
	var full := _by_id(RoadEvents.options(_entry("survivor"), ctx))
	check(not bool(full.take.ok) and String(full.take.why).begins_with("No seat free"), "the seat is taken by the one already in: '%s'" % full.take.why)
	check(not bool(RoadEvents.resolve(_entry("survivor"), "take", ctx).ok), "and resolve refuses it too")
	var bus = _flow(sim, ["dez"], "bus")
	bus.road_survivors = 3
	var bedless := _ctx({"seats_free": 5, "seats": 6, "bed": true, "vehicle_name": "Bus"})
	bedless["flow"] = bus
	var why := String(_by_id(RoadEvents.options(_entry("survivor"), bedless)).take.why)
	check(why.to_lower().contains("bed"), "three beds, three taken in: no bed for a fourth: '%s'" % why)
	# a caller that only knows whether the tank has room
	check(int(_tally(_ctx({"fuel_room": true}), 100).get("fuel_stash", 0)) > 0, "fuel_room as a yes: a stash comes")
	check(int(_tally(_ctx({"fuel_room": false}), 100).get("fuel_stash", 0)) == 0, "as a no: it does not")
	_end(g)


# ------------------------------------------------------------------------ apply --

func test_a_find_goes_into_the_bags_and_a_cost_is_paid_at_once() -> void:
	var g := _game()
	var sim = g.sim
	var f = _flow(sim)
	var told: Array = RoadEvents.apply({"stock": {"scrap": 13, "food": 13, "meds": -3, "ammo": -10}}, f)
	eq(f.road_loot, {"scrap": 13, "food": 13}, "a find is in the bags: it comes home with the party")
	near(float(sim.stock.scrap), 60.0, 1e-9, "and is not in the store yet")
	near(float(sim.stock.meds), 7.0, 1e-9, "a cost is paid now")
	near(float(sim.stock.ammo), 290.0, 1e-9, "(the ammo too)")
	check(told.size() == 4, "and told: %s" % str(told))
	for t in told:
		check(String(t).strip_edges() != "", "no empty line")
	RoadEvents.apply({"stock": {"scrap": 2}}, f)
	eq(int(f.road_loot.scrap), 15, "the bags add up")
	_end(g)


func test_a_cost_never_takes_the_store_below_nothing() -> void:
	var g := _game()
	var sim = g.sim
	var f = _flow(sim)
	sim.stock.scrap = 4.0
	var told: Array = RoadEvents.apply({"stock": {"scrap": -10}}, f)
	near(float(sim.stock.scrap), 0.0, 1e-9, "paid what there was")
	check(String(told[0]).contains("4 scrap"), "and said so: %s" % str(told))
	told = RoadEvents.apply({"stock": {"scrap": -10}}, f)
	near(float(sim.stock.scrap), 0.0, 1e-9, "never below 0")
	check(told.size() == 1 and String(told[0]).strip_edges() != "", "and a line for it: %s" % str(told))
	eq(f.road_loot, {}, "nothing found")
	_end(g)


func test_fuel_goes_into_the_base_tank_and_never_below_nothing_nor_past_the_cap() -> void:
	var g := _game()
	var sim = g.sim
	var f = _flow(sim)
	sim.vehicles.fuel = 10.0
	var told: Array = RoadEvents.apply({"fuel": 6}, f)
	near(float(sim.vehicles.fuel), 16.0, 1e-9, "siphoned into the tank")
	check(String(told[0]).contains("6"), "told: %s" % str(told))
	sim.vehicles.fuel = float(sim.vehicles.FUEL_CAP) - 2.0
	told = RoadEvents.apply({"fuel": 9}, f)
	near(float(sim.vehicles.fuel), float(sim.vehicles.FUEL_CAP), 1e-9, "the tank is full at the cap")
	check(String(told[0]).contains("2") and String(told[0]).contains("9"), "and the line says only some went in: %s" % str(told))
	sim.vehicles.fuel = 3.0
	RoadEvents.apply({"fuel": -2}, f)
	near(float(sim.vehicles.fuel), 1.0, 1e-9, "a leak or a toll")
	told = RoadEvents.apply({"fuel": -50}, f)
	near(float(sim.vehicles.fuel), 0.0, 1e-9, "never below 0")
	check(not told.is_empty(), "told")
	_end(g)


func test_the_vehicle_takes_a_knock_through_the_fleet_and_is_never_wrecked_by_one() -> void:
	var g := _game()
	var sim = g.sim
	var f = _flow(sim)
	var hp0 := float(sim.vehicles.vehicle(f.vehicle_id).hp)
	var told: Array = RoadEvents.apply({"vehicle_hp": -10}, f)
	near(float(sim.vehicles.vehicle(f.vehicle_id).hp), hp0 - 10.0, 1e-9, "the pickup is down ten")
	check(not told.is_empty() and String(told[0]).to_lower().contains("pickup"), "told: %s" % str(told))
	RoadEvents.apply({"vehicle_hp": -500}, f)
	near(float(sim.vehicles.vehicle(f.vehicle_id).hp), 1.0, 1e-9, "never below 1")
	eq(sim.vehicles.fleet.size(), 1, "and the fleet still has it: only the road's own crash wrecks")
	var on_foot = _flow(sim, ["dez"], "")
	check(RoadEvents.apply({"vehicle_hp": -10}, on_foot).is_empty(), "no vehicle, no knock")
	var gone = _flow(sim, ["dez"], "sedan")
	var sedan_hp := float(sim.vehicles.vehicle(gone.vehicle_id).hp)
	gone.vehicle_alive = false
	RoadEvents.apply({"vehicle_hp": -10}, gone)
	near(float(sim.vehicles.vehicle(gone.vehicle_id).hp), sedan_hp, 1e-9, "a wrecked car is not hit again")
	_end(g)


func test_trust_and_morale_reach_those_aboard() -> void:
	var g := _game()
	var sim = g.sim
	var f = _flow(sim, ["dez", "marcus", "ruth"])
	var dez = _crew(sim, ["dez"])[0]
	var marcus = _crew(sim, ["marcus"])[0]
	var ruth = _crew(sim, ["ruth"])[0]
	f.road_lost = ["marcus"]
	var t_dez := float(dez.trust)
	var t_marcus := float(marcus.trust)
	RoadEvents.apply({"trust": 2.0, "morale": 2.0}, f)
	near(float(dez.trust), t_dez + 2.0, 1e-9, "Dez trusts you more")
	near(float(marcus.trust), t_marcus, 1e-9, "Marcus is lost on the road: not told")
	near(float(f.road_morale), 2.0, 1e-9, "the mood is kept for the ones who come home")
	RoadEvents.apply({"trust": -1.0, "morale": -3.0}, f)
	near(float(dez.trust), t_dez + 1.0, 1e-9, "and less")
	near(float(f.road_morale), -1.0, 1e-9, "the mood adds up")
	ruth.dead = true
	f.going.append(ruth)
	var t_ruth := float(ruth.trust)
	RoadEvents.apply({"trust": 5.0}, f)
	near(float(ruth.trust), t_ruth, 1e-9, "the dead are not told")
	# a flow with no mood counter shocks the people itself
	var bare := BareFlow.new()
	bare.sim = sim
	bare.going = [dez]
	RoadEvents.apply({"morale": 2.0}, bare)
	check(true, "(a bare flow does not crash)")
	_end(g)


func test_a_survivor_needs_a_seat_and_a_bed() -> void:
	var g := _game()
	var sim = g.sim
	# the pickup seats two: two aboard, no seat
	var full = _flow(sim, ["dez", "marcus"])
	var told: Array = RoadEvents.apply({"survivor": 1}, full)
	eq(full.road_survivors, 0, "no seat: they stay on the road")
	check(String(told[0]).to_lower().contains("seat"), "and it says so: %s" % str(told))
	# one aboard, a seat free
	var one = _flow(sim, ["dez"])
	told = RoadEvents.apply({"survivor": 1}, one)
	eq(one.road_survivors, 1, "a seat and a bed: they climb in")
	check(String(told[0]).strip_edges() != "", "told")
	told = RoadEvents.apply({"survivor": 1}, one)
	eq(one.road_survivors, 1, "the second finds no seat left in a pickup of two")
	# on foot, three at most
	var walkers = _flow(sim, ["dez", "marcus"], "")
	RoadEvents.apply({"survivor": 1}, walkers)
	eq(walkers.road_survivors, 1, "three on foot")
	RoadEvents.apply({"survivor": 1}, walkers)
	eq(walkers.road_survivors, 1, "never a fourth")
	# the beds: six, three people, and the ones on the way count
	var many = _flow(sim, ["dez"], "bus")
	for i in 5:
		RoadEvents.apply({"survivor": 1}, many)
	eq(many.road_survivors, 3, "three beds are free: three come (%d)" % many.road_survivors)
	told = RoadEvents.apply({"survivor": 1}, many)
	check(String(told[0]).to_lower().contains("bed"), "and the fourth finds no bed: %s" % str(told))
	_end(g)


func test_a_place_nobody_knew_is_shown_by_a_sign_on_the_road() -> void:
	var g := _game()
	var sim = g.sim
	var f = _flow(sim)
	eq(sim.town.state_of("mill"), "unknown", "(the mill is not on the map)")
	var told: Array = RoadEvents.apply({"reveal": "near"}, f)
	eq(sim.town.state_of("mill"), "known", "the nearest to the houses is shown")
	eq(sim.town.state_of("pier"), "unknown", "and no other")
	check(String(told[0]).contains("The mill"), "named: %s" % str(told))
	told = RoadEvents.apply({"reveal": "near"}, f)
	eq(sim.town.state_of("pier"), "known", "the next sign shows the next place")
	told = RoadEvents.apply({"reveal": "near"}, f)
	check(told.is_empty(), "nothing left to show: no line")
	_end(g)


func test_apply_leaves_the_scenes_part_alone_and_draws_no_dice() -> void:
	var g := _game()
	var sim = g.sim
	var f = _flow(sim)
	var dez = _crew(sim, ["dez"])[0]
	var hp: float = dez.hp
	var stock: Dictionary = sim.stock.duplicate()
	var rng_state: int = sim.rng.state
	var told: Array = RoadEvents.apply({"hp_all": -9, "hurt": "bite", "pick": 3, "stop_s": 10.0, "block_cleared": 1,
		"dead": {"walker": 5, "runner": 0, "brute": 0, "where": "ahead", "state": "hunt"}}, f)
	check(told.is_empty(), "nothing told: %s" % str(told))
	near(float(dez.hp), hp, 1e-9, "the squad's health is the scene's")
	eq(sim.stock, stock, "no stock moved")
	eq(f.road_loot, {}, "no loot")
	eq(f.road_survivors, 0, "no survivor")
	eq(int(sim.rng.state), rng_state, "and no dice thrown")
	check(RoadEvents.apply({}, f).is_empty(), "no effects, no lines")
	# every real effect of the deck: no dice either
	for id in IDS:
		for c in RoadEvents.deck()[id].choices:
			for s in 8:
				RoadEvents.apply(RoadEvents.resolve(_entry(id, s), String(c.id), _ctx())["effects"], f)
	eq(int(sim.rng.state), rng_state, "the whole deck draws none of the colony's dice")
	for k in sim.stock:
		check(float(sim.stock[k]) >= 0.0, "%s is not below 0" % k)
	check(float(sim.vehicles.fuel) >= 0.0, "nor the fuel")
	_end(g)


# ----------------------------------------------------------------------- make_ctx --

func test_the_context_of_a_trip() -> void:
	var g := _game()
	var sim = g.sim
	sim.vehicles.fuel = 20.0
	var f = _flow(sim, ["dez", "marcus"], "pickup", "garage")
	f.going[0].skills["Leading"] = 4
	f.going[1].skills["Building"] = 3
	var c := RoadEvents.make_ctx(f, "there")
	eq(String(c.leg), "there", "the leg")
	eq(int(c.danger), 2 + 2, "the garage: its danger and its nest")
	check(bool(c.by_vehicle), "by vehicle")
	eq(int(c.seats), 2, "the pickup seats two")
	eq(int(c.seats_free), 0, "and both seats are taken")
	eq(String(c.vehicle_name), "Pickup", "the name")
	near(float(c.road_min), float(sim.scavenge.road_minutes("garage", f.vehicle_id)), 1e-9, "the road's minutes")
	near(float(c.leg_s), clampf(float(c.road_min), 30.0, 90.0), 1e-9, "the leg's seconds")
	near(float(c.hour), float(sim.hour), 1e-9, "the base's hour")
	near(float(c.dusk), float(sim.seasons.dusk_hour()), 1e-9, "dusk")
	near(float(c.dawn), float(sim.seasons.dawn_hour()), 1e-9, "dawn")
	check(bool(c.bed) and String(c.caller) != "" and not String(c.caller).contains(" "), "a bed and a caller by first name: '%s'" % c.caller)
	near(float(c.hp_share), 1.0, 1e-9, "a sound car")
	near(float(c.fuel_room), float(sim.vehicles.FUEL_CAP) - 20.0, 1e-9, "room in the tank")
	eq(int(c.stock.scrap), 60, "the base's scrap")
	eq(int(c.leading), 4, "the best Leading aboard")
	eq(int(c.building), maxi(3, int(f.going[0].skills.Building)), "the best Building aboard")
	check(not RoadEvents.plan(5, c).is_empty(), "and it plans")
	# cleared: the danger is gone
	sim.town.state["garage"].cleared = true
	eq(int(RoadEvents.make_ctx(f, "home").danger), 0, "a cleared place has no danger")
	eq(String(RoadEvents.make_ctx(f, "home").leg), "home", "the road home")
	# a worn car
	sim.vehicles.vehicle(f.vehicle_id)["hp"] = 18.0
	near(float(RoadEvents.make_ctx(f).hp_share), 0.2, 1e-9, "a worn car")
	# on foot
	var walk = _flow(sim, ["dez"], "", "houses")
	var w := RoadEvents.make_ctx(walk)
	check(not bool(w.by_vehicle) and int(w.seats_free) == 2 and int(w.seats) == 3, "on foot: three at most")
	near(float(w.road_min), float(sim.scavenge.road_minutes("houses", "")), 1e-9, "the whole way")
	# a wrecked car is a walk
	var gone = _flow(sim, ["dez"], "sedan", "houses")
	gone.vehicle_alive = false
	check(not bool(RoadEvents.make_ctx(gone).by_vehicle), "a car that is lost is not there")
	# the ones taken in fill the seats and the beds
	var taking = _flow(sim, ["dez"], "bus", "houses")
	taking.road_survivors = 3
	var t := RoadEvents.make_ctx(taking)
	eq(int(t.seats_free), 6 - 1 - 3, "the ones taken in take seats")
	check(not bool(t.bed), "and the beds (three free, three taken)")
	_end(g)


func test_a_game_with_no_beds_has_no_bed_in_the_context() -> void:
	var g := _game()
	var sim = g.sim
	while sim.recruits.housing_free() > 0:
		sim.add_person(sim.recruits.make_def(sim.recruits.generated))
		sim.recruits.generated += 1
	var f = _flow(sim, ["dez"])
	var c := RoadEvents.make_ctx(f)
	check(not bool(c.bed) and String(c.caller) == "", "no bed, no caller asked")
	check(_never(c, ["survivor"], 100), "and no survivor on the road")
	_end(g)
