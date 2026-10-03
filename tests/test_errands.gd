extends "res://tests/case.gd"
## Delegated errands (round 18, slice 2, S2.1: scripts/sim/scavenge.gd). In avatar mode (`sim.player_id != ""`) a trip the dice
## decide (an errand: someone sent from the radio panel or the old dialog; the player's own trip is `begin_played`, never dice)
## works, but worse than with the player along: loot x0.6, no rare finds, no rescue, no vehicle recovered, a worse chance of
## clearing a place, wounds x1.5 and losses far likelier. With no avatar every number is the old one.

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Helpers := preload("res://tests/helpers.gd")
const Town := preload("res://scripts/sim/town.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Scavenge := preload("res://scripts/sim/scavenge.gd")

const FIXTURE := "user://test_r18_errands_town.json"
const FIXTURE_SITES := "user://test_r18_errands_sites.json"
const FIXTURE_BEATS := "user://test_r18_errands_beats.json"

## Home is at (50, 35); a place 9 tiles away is an hour on foot. Every extra (a rare find) is a sure one, so that a missing find
## cannot be luck; the clinic hides a survivor, the garage a pickup, the yard a nest.
const TOWN := {
	"board": {"w": 160, "h": 70},
	"home": [50, 35],
	"places": [
		{"id": "houses", "name": "The houses", "kind": "houses", "pos": [59, 35], "blurb": "Doors shut.", "danger": 1, "known": true,
			"loot": {"food": [8, 14], "water": [10, 20]}, "extra": {"meds": [1.0, 4]}},
		{"id": "pharmacy", "name": "The pharmacy", "kind": "pharmacy", "pos": [41, 35], "blurb": "Boarded up.", "danger": 2, "known": true,
			"loot": {"meds": [6, 11]}, "extra": {"food": [1.0, 4]}},
		{"id": "clinic", "name": "The clinic", "kind": "clinic", "pos": [50, 44], "blurb": "Someone behind a door.", "danger": 1, "known": true,
			"loot": {"meds": [5, 9]}, "extra": {}, "survivor": true},
		{"id": "garage", "name": "The garage", "kind": "garage", "pos": [50, 26], "blurb": "A pickup on the ramp.", "danger": 1, "known": true,
			"loot": {"scrap": [10, 20]}, "extra": {}, "vehicle": "pickup"},
		{"id": "yard", "name": "The scrapyard", "kind": "scrapyard", "pos": [50, 53], "blurb": "A nest.", "danger": 1, "known": true,
			"loot": {"scrap": [20, 40]}, "extra": {}, "nest": {"strength": 1}},
	],
	"roads": [["home", "houses"], ["home", "pharmacy"], ["home", "clinic"], ["home", "garage"], ["home", "yard"]],
	"beats": [],
}


## The classic start's four sites, as the data had them when the numbers were pinned (a retune of sites.json must not move a pin).
const SITES := {"sites": [
	{"id": "pharmacy", "name": "The pharmacy", "where": "the pharmacy", "blurb": "Boarded up.", "danger": 2, "loot": {"meds": [6, 11]}, "extra": {"food": [0.5, 4]}, "image": ""},
	{"id": "hardware", "name": "The hardware store", "where": "the hardware store", "blurb": "Shutter dented.", "danger": 2, "loot": {"scrap": [18, 34], "ammo": [70, 130]}, "extra": {}, "image": ""},
	{"id": "houses", "name": "Neighbourhood houses", "where": "the houses", "blurb": "Doors shut.", "danger": 1, "loot": {"food": [8, 14], "water": [10, 20]}, "extra": {"meds": [0.5, 1.5]}, "image": ""},
	{"id": "scrapyard", "name": "The scrapyard", "where": "the scrapyard", "blurb": "Sheet metal.", "danger": 3, "loot": {"scrap": [35, 60]}, "extra": {"food": [0.3, 3]}, "image": ""},
]}


# ------------------------------------------------------------------ helpers --

## The skills the trips' formulas read, pinned (a retune of the roster must not move a pin): Shooting, Building and Leading.
func _skills(sim) -> void:
	var shooting := {"ruth": 5, "dez": 6, "ana": 4, "marcus": 8, "walt": 7, "hector": 2}
	for p in sim.people:
		p.skills["Shooting"] = int(shooting.get(String(p.id), 3))
		p.skills["Building"] = 4
		p.skills["Leading"] = 9 if String(p.id) == "ruth" else 2

func _write(data: Dictionary) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _at(sim, day: int, hour: float) -> void:
	sim.day = day
	sim.minutes = hour * 60.0
	sim.clock_min = float(day - 1) * 1440.0 + (hour * 60.0 - 420.0)
	sim.phase = sim.phase_at(sim.minutes)
	sim.bell_rung = hour >= 19.0 or hour < 6.0
	sim.supplies.sources_day = day


## A settlement game (Ruth, Dez, Marcus) with the small town above, at `hour` of day 3, the waves off. `avatar`: Ruth is the player.
func _town(avatar: bool, hour: float = 8.0, difficulty: int = 1) -> Dictionary:
	_write(TOWN)
	Town.data_path = FIXTURE
	var g := Helpers.make(17, difficulty, 3)
	Town.data_path = Town.DATA_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	_skills(sim)
	_at(sim, 3, hour)
	sim.stock = {"ammo": 300.0, "scrap": 60.0, "food": 40.0, "water": 50.0, "meds": 10.0}
	if avatar:
		check(sim.avatar.set_player("ruth"), "Ruth is the player")
	sim.events.clear()
	return g


## The classic start (six people, the four sites of sites.json), at `hour` of day 3. `avatar`: Ruth is the player.
func _classic(avatar: bool, hour: float = 7.0, difficulty: int = 1) -> Dictionary:
	var f := FileAccess.open(FIXTURE_SITES, FileAccess.WRITE)
	f.store_string(JSON.stringify(SITES))
	f.close()
	Scavenge.sites_path = FIXTURE_SITES
	var g := Helpers.make(3, difficulty, 6)
	Scavenge.sites_path = Scavenge.SITES_PATH
	var sim = g.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	_skills(sim)
	_at(sim, 3, hour)
	if avatar:
		check(sim.avatar.set_player("ruth"), "Ruth is the player")
	sim.events.clear()
	return g


func _p(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _crew(sim, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append(_p(sim, String(id)))
	return out


## Sends the people at the next seed and returns the party's result ({} if it was refused).
func _send(sim, ids: Array, place: String, action: String, seed_value: int, vehicle: String = "") -> Dictionary:
	sim.scavenge.parties.clear()
	sim.scavenge.raids.clear()
	for p in sim.people:
		p.away = null
	sim.rng.seed = seed_value
	if not sim.scavenge.send(_crew(sim, ids), place, action, vehicle):
		return {}
	return sim.scavenge.parties[0].result


func _free(g: Dictionary) -> void:
	g.world.free()


## Checks that `count` out of `n` is about `p` (within 4.5 standard deviations).
func _rate(count: int, n: int, p: float, label: String) -> void:
	var tol := 4.5 * sqrt(p * (1.0 - p) / float(n)) + 1.0 / float(n)
	var got := float(count) / float(n)
	if absf(got - p) > tol:
		failures.append("%s: expected %.4f +- %.4f, got %.4f" % [label, p, tol, got])


## The banner event whose title contains `text` (the last one), or {}.
func _banner(sim, text: String) -> Dictionary:
	var found := {}
	for e in sim.events:
		if e.type == "banner" and String(e.text).contains(text):
			found = e
	return found


func _news(sim, kind: String) -> Array:
	var out: Array = []
	for e in sim.radio.news:
		if e.kind == kind:
			out.append(e)
	return out


## Steps until nobody is out (or `seconds` of the rules' time). True when the parties are home.
func _until_home(sim, seconds: float = 6000.0) -> bool:
	var t := 0.0
	while not sim.scavenge.parties.is_empty() and t < seconds:
		Helpers.run(sim, 1.0)
		t += 1.0
	return sim.scavenge.parties.is_empty()


# ------------------------------------------------ the old numbers, pinned ----

## What the dice made of 40 seeded trips for each place, action and crew, in one string (sorted keys: the same run, the same string).
func _digest_town(sim) -> String:
	var out: Array = []
	for place in ["houses", "pharmacy", "clinic", "garage", "yard"]:
		for action in ["loot", "scout", "clear"]:
			for ids in [["dez"], ["dez", "marcus"]]:
				for i in 40:
					var r := _send(sim, ids, place, action, 9000 + i * 7)
					out.append(JSON.stringify(r, "", true))
		out.append(str(snappedf(sim.scavenge.clear_chance(_crew(sim, ["dez", "marcus"]), place), 0.00001)))
	return "|".join(out)


func _digest_classic(sim) -> String:
	var out: Array = []
	for d in 3:
		sim.difficulty = d
		for site in ["pharmacy", "hardware", "houses", "scrapyard"]:
			for ids in [["dez"], ["hector", "marcus"], ["ruth", "dez"]]:
				for i in 40:
					out.append(JSON.stringify(_send(sim, ids, site, "loot", 4000 + i * 3), "", true))
	return "|".join(out)


## The digests of the dice as they were before round 18 (taken from the module as it stood at the end of round 17, with the skills and
## the places pinned above): any change of a number with no avatar shows here.
const GOLDEN_TOWN := "ee9fad5aa68fabbc87317f7337fbb75ba1cb9f309ee73f5899892f6393d09e9f"
const GOLDEN_CLASSIC := "f09644ea46143cdd24a17061f829969b03f19a65c9c9f3df8eca94c414d085d5"


func test_with_no_player_the_dice_are_byte_for_byte_the_old_ones() -> void:
	var g := _town(false)
	eq(_digest_town(g.sim).sha256_text(), GOLDEN_TOWN, "the settlement game's trips, with no player")
	_free(g)
	var c := _classic(false)
	eq(_digest_classic(c.sim).sha256_text(), GOLDEN_CLASSIC, "the classic start's trips, with no player")
	_free(c)


# ------------------------------------------------------------- the terms ----

func test_the_errand_terms_are_one_set_of_constants() -> void:
	var g := _town(true)
	var sc = g.sim.scavenge
	near(sc.ERRAND_LOOT, 0.6, 0.0001, "the loot scale")
	near(sc.ERRAND_WOUND, 1.5, 0.0001, "the wound factor")
	near(sc.ERRAND_LOSS_PER_DANGER, 0.03, 0.0001, "the loss for each point of danger")
	near(sc.ERRAND_CLEAR, -0.2, 0.0001, "the clearing chance")
	var t: Dictionary = sc.errand_terms()
	near(float(t.loot), sc.ERRAND_LOOT, 0.0001, "the terms carry the loot scale")
	near(float(t.wound), sc.ERRAND_WOUND, 0.0001, "the wound factor")
	near(float(t.loss_per_danger), sc.ERRAND_LOSS_PER_DANGER, 0.0001, "the loss")
	near(float(t.clear), sc.ERRAND_CLEAR, 0.0001, "the clearing")
	eq(t.extras, false, "no rare finds")
	eq(t.rescue, false, "no rescue")
	eq(t.vehicle, false, "no vehicle")
	# danger 2 (the pharmacy): the loss is at least five times what it was
	var old: float = sc.LOSS_BASE * (2.0 / 2.0)
	check(sc.ERRAND_LOSS_PER_DANGER * 2.0 >= 5.0 * old, "a loss at danger 2 is at least five times likelier")
	_free(g)


func test_only_a_dice_party_in_avatar_mode_is_an_errand() -> void:
	var g := _town(true)
	var sc = g.sim.scavenge
	check(sc.is_errand({"kind": "party", "members": []}), "a dice party, with a player, is an errand")
	check(not sc.is_errand({"kind": "party", "played": true}), "the player's own trip is not")
	g.sim.player_id = ""
	check(not sc.is_errand({"kind": "party", "members": []}), "with no player nothing is")
	_free(g)


# ------------------------------------------------------------------ the loot --

func test_an_errand_brings_sixty_percent_of_the_loot_and_never_a_rare_find() -> void:
	var g := _town(true)
	var sim = g.sim
	var sc = sim.scavenge
	var crew := ["dez", "marcus"]
	var checked := 0
	for i in 60:
		var seed_value := 500 + i * 11
		var r := _send(sim, crew, "houses", "loot", seed_value)
		check(not r.is_empty(), "the errand is sent (seed %d)" % seed_value)
		if r.is_empty() or (r.lost as Array).size() == crew.size():
			continue
		sim.rng.seed = seed_value
		var food: int = sim.rng.randi_range(8, 14)
		var water: int = sim.rng.randi_range(10, 20)
		var scale: float = sc.loot_scale("houses", _crew(sim, crew))
		scale *= sc.ERRAND_LOOT
		eq(int(r.loot.get("food", 0)), roundi(food * scale), "food is round(base x scale x 0.6), seed %d" % seed_value)
		eq(int(r.loot.get("water", 0)), roundi(water * scale), "water likewise, seed %d" % seed_value)
		check(not r.loot.has("meds"), "the sure rare find (meds) is rolled but not added, seed %d" % seed_value)
		eq(r.get("errand", false), true, "it is marked an errand")
		checked += 1
	check(checked >= 55, "most trips could be checked (%d)" % checked)
	_free(g)


func test_the_same_trip_with_no_player_keeps_its_rare_find() -> void:
	var g := _town(false)
	var sim = g.sim
	var with_meds := 0
	var runs := 0
	for i in 30:
		var r := _send(sim, ["dez", "marcus"], "houses", "loot", 500 + i * 11)
		if (r.lost as Array).size() == 2:
			continue
		runs += 1
		if int(r.loot.get("meds", 0)) > 0:
			with_meds += 1
		check(not r.has("errand"), "no errand flag with no player")
	eq(with_meds, runs, "the sure extra is always found when nobody is an avatar")
	_free(g)


func test_the_classic_start_runs_errands_too() -> void:
	var g := _classic(true)
	var sim = g.sim
	var sc = sim.scavenge
	var crew := ["hector", "marcus"]
	var checked := 0
	for i in 40:
		var seed_value := 77 + i * 5
		var r := _send(sim, crew, "houses", "loot", seed_value)
		check(not r.is_empty(), "sent")
		if r.is_empty() or (r.lost as Array).size() == crew.size():
			continue
		sim.rng.seed = seed_value
		var food: int = sim.rng.randi_range(8, 14)
		var water: int = sim.rng.randi_range(10, 20)
		var scale: float = sc.loot_scale("houses", _crew(sim, crew))
		scale *= sc.ERRAND_LOOT
		eq(int(r.loot.get("food", 0)), roundi(food * scale), "food at 60%%, seed %d" % seed_value)
		eq(int(r.loot.get("water", 0)), roundi(water * scale), "water at 60%%, seed %d" % seed_value)
		check(not r.loot.has("meds"), "no rare finds, seed %d" % seed_value)
		check(bool(r.get("errand", false)), "marked")
		checked += 1
	check(checked >= 35, "(%d checked)" % checked)
	_free(g)


func test_no_rescue_and_no_vehicle_come_from_an_errand() -> void:
	var old_g := _town(false)
	var new_g := _town(true)
	var old_rescues := 0
	var old_vehicles := 0
	for i in 80:
		var seed_value := 1200 + i * 13
		var r_old := _send(old_g.sim, ["dez", "marcus"], "clinic", "loot", seed_value)
		var r_new := _send(new_g.sim, ["dez", "marcus"], "clinic", "loot", seed_value)
		if r_old.get("rescue", false):
			old_rescues += 1
		check(not r_new.get("rescue", false), "an errand never brings the survivor home (seed %d)" % seed_value)
		var v_old := _send(old_g.sim, ["dez", "marcus"], "garage", "loot", seed_value)
		var v_new := _send(new_g.sim, ["dez", "marcus"], "garage", "loot", seed_value)
		if v_old.has("vehicle"):
			old_vehicles += 1
		check(not v_new.has("vehicle"), "an errand never gets the pickup running (seed %d)" % seed_value)
	check(old_rescues > 10, "(the same dice with no player do rescue: %d)" % old_rescues)
	check(old_vehicles > 10, "(and do get the pickup running: %d)" % old_vehicles)
	_free(old_g)
	_free(new_g)


# ----------------------------------------------------- wounds, losses, clearing --

func test_wounds_and_losses_follow_the_errand_formula() -> void:
	var g := _town(true)
	var sim = g.sim
	var sc = sim.scavenge
	var n := 2500
	for place in ["houses", "pharmacy"]:
		var danger: int = 1 if place == "houses" else 2
		var who := ["dez", "marcus"]
		var lost := [0, 0]
		var hurt := [0, 0]
		for i in n:
			var r := _send(sim, who, place, "loot", 7000 + i)
			for k in 2:
				if (r.lost as Array).has(who[k]):
					lost[k] += 1
				elif r.hurt.has(who[k]):
					hurt[k] += 1
		for k in 2:
			var shooting := float(_p(sim, who[k]).skills.Shooting)
			var loss_p: float = sc.ERRAND_LOSS_PER_DANGER * float(danger)
			var wound_p: float = sc.WOUND_BASE * danger * (1.0 - shooting / 15.0) * sc.ERRAND_WOUND
			_rate(lost[k], n, loss_p, "%s lost at the %s" % [who[k], place])
			_rate(hurt[k], n, (1.0 - loss_p) * wound_p, "%s hurt at the %s" % [who[k], place])
	_free(g)


func test_an_errand_is_lost_wherever_the_old_dice_lost_someone_and_far_oftener() -> void:
	var old_g := _town(false)
	var new_g := _town(true)
	var lost_old := 0
	var lost_new := 0
	for i in 1500:
		var seed_value := 20000 + i * 3
		var r_old := _send(old_g.sim, ["dez", "marcus"], "pharmacy", "loot", seed_value)
		var r_new := _send(new_g.sim, ["dez", "marcus"], "pharmacy", "loot", seed_value)
		for id in r_old.lost:
			check((r_new.lost as Array).has(id), "%s lost with no player is lost on an errand too (seed %d)" % [id, seed_value])
		lost_old += (r_old.lost as Array).size()
		lost_new += (r_new.lost as Array).size()
	check(lost_old > 0 and lost_new >= 4 * lost_old, "losses at danger 2: %d on errands against %d" % [lost_new, lost_old])
	_free(old_g)
	_free(new_g)


func test_a_danger_one_place_that_never_lost_anyone_now_does() -> void:
	var g := _town(true)
	var lost := 0
	for i in 600:
		lost += (_send(g.sim, ["dez", "marcus"], "houses", "loot", 3000 + i).lost as Array).size()
	check(lost > 0, "someone is lost on an errand to a danger 1 place (%d)" % lost)
	_free(g)
	var old_g := _town(false)
	lost = 0
	for i in 600:
		lost += (_send(old_g.sim, ["dez", "marcus"], "houses", "loot", 3000 + i).lost as Array).size()
	eq(lost, 0, "and nobody is, with no player")
	_free(old_g)


func test_clearing_is_twenty_points_less_likely_on_an_errand() -> void:
	var g := _town(true)
	var sim = g.sim
	var sc = sim.scavenge
	var pair := _crew(sim, ["dez", "marcus"])
	for p in pair:
		p.skills.Shooting = 3
	near(sc.clear_chance(pair, "houses"), 0.71, 0.0001, "a plain chance at the houses with Shooting 3 each")
	near(sc.clear_chance(pair, "houses", true), 0.51, 0.0001, "the errand's is 0.2 under it")
	near(sc.clear_chance(pair, "pharmacy", true), 0.39, 0.0001, "at the pharmacy (danger 2) 0.59 - 0.2")
	near(sc.clear_chance(pair, "yard", true), 0.39, 0.0001, "at the nest 0.59 - 0.2")
	var strong := _crew(sim, ["dez", "marcus", "ruth"])
	for p in strong:
		p.skills.Shooting = 9
	near(sc.clear_chance(strong, "houses"), 0.95, 0.0001, "the old chance still stops at 0.95")
	near(sc.clear_chance(strong, "houses", true), 0.95, 0.0001, "a party this strong is still at the cap on an errand: the limits stay")
	for p in strong:
		p.skills.Shooting = 0
	near(sc.clear_chance(strong, "yard", true), 0.1, 0.0001, "and the 0.1 floor stays")
	_free(g)


func test_an_errand_clears_a_place_at_the_lowered_chance() -> void:
	var g := _town(true)
	var sim = g.sim
	var sc = sim.scavenge
	var pair := _crew(sim, ["dez", "marcus"])
	for p in pair:
		p.skills.Shooting = 6
	var want: float = sc.clear_chance(pair, "yard", true)
	check(want > 0.12 and want < 0.9, "the chance is not at a limit (%.2f)" % want)
	var n := 1500
	var cleared := 0
	for i in n:
		if _send(sim, ["dez", "marcus"], "yard", "clear", 40000 + i).get("clear", false):
			cleared += 1
	_rate(cleared, n, want, "the share of clearings that work")
	_free(g)


func test_the_dice_stay_in_step_whatever_is_done_with_them() -> void:
	var old_g := _town(false)
	var new_g := _town(true)
	var compared := 0
	for action in ["loot", "scout", "clear"]:
		for i in 40:
			var seed_value := 60000 + i * 17
			var r_old := _send(old_g.sim, ["dez", "marcus"], "houses", action, seed_value)
			var r_new := _send(new_g.sim, ["dez", "marcus"], "houses", action, seed_value)
			check(not r_old.is_empty() and not r_new.is_empty(), "%s sent" % action)
			eq(new_g.sim.rng.state, old_g.sim.rng.state, "the same number of dice thrown (%s, seed %d)" % [action, seed_value])
			compared += 1
	eq(compared, 120, "all compared")
	# the classic sites too
	var old_c := _classic(false)
	var new_c := _classic(true)
	for i in 40:
		var seed_value := 90 + i
		_send(old_c.sim, ["hector", "marcus"], "hardware", "loot", seed_value)
		_send(new_c.sim, ["hector", "marcus"], "hardware", "loot", seed_value)
		eq(new_c.sim.rng.state, old_c.sim.rng.state, "the classic dice stay in step (seed %d)" % seed_value)
	for x in [old_g, new_g, old_c, new_c]:
		_free(x)


func test_the_beats_of_the_road_and_the_scouts_reveals_are_the_same_on_an_errand() -> void:
	var town := TOWN.duplicate(true)
	town["beats"] = [
		{"id": "dog", "text": "A thin dog fell in behind the party.", "weight": 1, "min_hours": 0, "effects": {"morale": 3}},
		{"id": "cache", "text": "A cache under a floorboard.", "weight": 1, "min_hours": 0, "effects": {"loot_pct": 25}},
	]
	town["places"][1]["known"] = false
	var f := FileAccess.open(FIXTURE_BEATS, FileAccess.WRITE)
	f.store_string(JSON.stringify(town))
	f.close()
	Town.data_path = FIXTURE_BEATS
	var old_g := Helpers.make(17, 1, 3)
	var new_g := Helpers.make(17, 1, 3)
	Town.data_path = Town.DATA_PATH
	for g in [old_g, new_g]:
		g.sim.waves.enabled = false
		g.sim.zombies.clear()
		_skills(g.sim)
		_at(g.sim, 3, 8.0)
	new_g.sim.avatar.set_player("ruth")
	var with_beats := 0
	for action in ["loot", "scout"]:
		for i in 40:
			var seed_value := 300 + i * 9
			var r_old := _send(old_g.sim, ["dez", "marcus"], "houses", action, seed_value)
			var r_new := _send(new_g.sim, ["dez", "marcus"], "houses", action, seed_value)
			eq(r_new.get("beats", []), r_old.get("beats", []), "the beats are the road's (%s, seed %d)" % [action, seed_value])
			eq(r_new.get("reveals", []), r_old.get("reveals", []), "the scout shows what it showed (%s, seed %d)" % [action, seed_value])
			near(float(r_new.get("morale", 0.0)), float(r_old.get("morale", 0.0)), 0.0001, "the mood of the road")
			if r_new.has("beats"):
				with_beats += 1
	check(with_beats > 10, "some trips met a beat (%d)" % with_beats)
	check((_send(new_g.sim, ["dez", "marcus"], "houses", "scout", 5).get("reveals", []) as Array).has("pharmacy"), "and a scouting errand shows the unknown place")
	_free(old_g)
	_free(new_g)


# ----------------------------------------------------- a save, the news --

func test_the_errand_flag_is_in_the_result_and_in_a_save() -> void:
	var g := _town(true)
	var sim = g.sim
	var sc = sim.scavenge
	var r := _send(sim, ["dez", "marcus"], "houses", "loot", 5)
	check(r.get("errand", false), "in the result")
	var d: Dictionary = JSON.parse_string(JSON.stringify(sc.save()))
	check(bool(d.parties[0].result.get("errand", false)), "in the saved result")
	sc.parties.clear()
	sc.load_state(d)
	eq(sc.parties.size(), 1, "the party comes back")
	check(bool(sc.parties[0].result.get("errand", false)), "and is still an errand after a load")
	_free(g)


func test_an_errand_is_told_on_the_way_out_and_on_the_way_home() -> void:
	var g := _town(true)
	var sim = g.sim
	check(sim.scavenge.send(_crew(sim, ["dez", "marcus"]), "houses", "loot", ""), "the errand goes")
	sim.scavenge.parties[0].result = {"loot": {"food": 12, "water": 14}, "hurt": {}, "lost": [], "errand": true}
	check(_until_home(sim), "and comes home")
	var told := _news(sim, "errand")
	eq(told.size(), 2, "the radio's news has two lines: %s" % str(told))
	eq(String(told[0].text), "Dez and Marcus set off for the houses.", "the departure")
	eq(String(told[0].sub), "They will find less without you.", "and what to expect")
	var banner := _banner(sim, "Back from the houses")
	check(not banner.is_empty(), "the banner tells the return")
	check(String(banner.sub).contains("Without you along they found less."), "and says the bag was lighter: %s" % str(banner))
	eq(String(told[1].text), String(banner.text), "the news repeats the banner's title")
	eq(String(told[1].sub), String(banner.sub), "and its line")
	_free(g)


func test_an_errand_that_loses_someone_is_told_too() -> void:
	var g := _town(true)
	var sim = g.sim
	check(sim.scavenge.send(_crew(sim, ["dez", "marcus"]), "pharmacy", "loot", ""), "the errand goes")
	sim.scavenge.parties[0].result = {"loot": {"meds": 5}, "hurt": {}, "lost": ["dez"], "errand": true}
	check(_until_home(sim), "and comes home")
	var told := _news(sim, "errand")
	eq(told.size(), 2, "departure and return")
	check(String(told[1].text).contains("Dez did not come back"), "the loss is the title: %s" % str(told[1]))
	var banner := _banner(sim, "Dez did not come back")
	eq(String(told[1].sub), String(banner.sub), "the same words as the banner")
	check(String(told[1].sub).contains("Without you along they found less."), "with the penalty reminder (loot came home)")
	_free(g)


func test_an_errand_that_brings_nothing_does_not_say_the_bag_was_lighter() -> void:
	var g := _town(true)
	var sim = g.sim
	check(sim.scavenge.send(_crew(sim, ["dez", "marcus"]), "houses", "scout", ""), "a scouting errand goes")
	check(_until_home(sim), "and comes home")
	var banner := _banner(sim, "Back from the houses")
	check(not String(banner.get("sub", "")).contains("Without you"), "a scout brings no loot to be lighter: %s" % str(banner))
	_free(g)


func test_the_players_own_trip_and_the_old_game_are_untouched() -> void:
	var g := _town(true)
	var sim = g.sim
	var party: Dictionary = sim.scavenge.begin_played(_crew(sim, ["ruth", "dez"]), "houses", "loot", "")
	check(not party.is_empty(), "the player's trip begins")
	check(not sim.scavenge.is_errand(party), "it is not an errand")
	sim.scavenge.finish_played(party, {"loot": {"food": 14, "water": 20}, "hurt": {}, "lost": [], "ammo_used": 0.0})
	check(_until_home(sim), "and comes home")
	check(not bool(party.result.get("errand", false)), "its result carries no errand flag")
	eq(int(party.result.loot.get("food", 0)), 14, "its loot is what the place gave")
	eq(_news(sim, "errand").size(), 0, "and the radio tells nothing of an errand")
	var banner := _banner(sim, "Back from the houses")
	check(not String(banner.get("sub", "")).contains("Without you"), "nor does the banner")
	_free(g)
	var old_g := _town(false)
	var sim2 = old_g.sim
	check(sim2.scavenge.send(_crew(sim2, ["dez", "marcus"]), "houses", "loot", ""), "the old game sends")
	check(_until_home(sim2), "and gets them home")
	eq(_news(sim2, "errand").size(), 0, "with no news of an errand")
	check(not String(_banner(sim2, "Back from").get("sub", "")).contains("Without you"), "and no penalty line")
	_free(old_g)


func test_a_trip_pulled_apart_before_the_gate_is_still_an_errand() -> void:
	var g := _town(true)
	var sim = g.sim
	var sc = sim.scavenge
	check(sc.send(_crew(sim, ["dez", "marcus"]), "houses", "loot", ""), "the errand goes")
	var party: Dictionary = sc.parties[0]
	# Marcus is given other business before anyone has reached the gate: the trip is decided again for the smaller party
	var marcus = _p(sim, "marcus")
	marcus.drafted = true
	marcus.order = {"x": 40.0, "y": 30.0, "z": 0.0}
	Helpers.run(sim, 0.2)
	eq(party.members, ["dez"], "Marcus left the party")
	check(bool(party.result.get("errand", false)), "the smaller trip is still an errand")
	_free(g)
