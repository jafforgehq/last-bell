## The colony's side of a played trip (round 17, S1.6b): what happens to the base while the player goes to a place, plays it
## and comes home. The scene (raid_scene.gd) shows it and gives the hands; this holds the rules of the flow and nothing is
## drawn here, so that the tests can run a whole trip without a window.
##
##   pick_party   the people the player chose are ASKED over the radio to come (`radio.willingness(p, "come")`): who cannot
##                is left out, with the reason; the player (the avatar) always goes and always leads, so they are added if
##                the picker did not have them; more than the seats (or three on foot) and the last of the chosen stay.
##   begin        `scavenge.begin_played`: the party is "in_place" at once, its people gone from the base. The road THERE
##                is `road_minutes` of the colony run quickly (`Sim.fast_forward`) a few steps a frame, under the scene's
##                'Driving to ...' overlay: `road_step(dt)` once a frame until it says it is done. A road takes at least
##                MIN_ROAD_S on the screen however short it is (the overlay has to be read), and never more than
##                MAX_STEPS_PER_FRAME colony steps in a frame.
##   place_step   the colony RUNS while the place is played: for each step of the place (30 a second) it takes
##                `Sim.background_steps_for(place steps so far)` steps in all, one for each PLACE_STEP_RATIO (3) of the
##                place, so a second of the place is a minute of the day. The running total is kept here, so a remainder
##                is never lost, and the place's own Sim is given the colony's clock after each colony step (`mirror`).
##   finish       the place is over: `scavenge.finish_played(party, result)` (the people are on the road home from this
##                moment: the colony's rules bring them in after `road_minutes`), the radio is told of the trip (the trust
##                the place counted, `result.trust_delta`; `radio.on_trip_led` for the ones who came back when it counted
##                none) and the road HOME is run the same way as the road there. The people are home, or in sight of the
##                gate, when it is done.
## The road home is run AFTER `finish_played` (not before it): the party's way home is already in the colony's own rules
## (`return_at`), and the fast-forward only carries the clock to it, so the trip does not take its road twice.
extends RefCounted

const Sim := preload("res://scripts/sim/sim.gd")
const StepClock := preload("res://scripts/sim/step_clock.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")

## The most colony steps one frame of the road takes (about 60 is what a frame can spare), and the least a road takes to
## play out on the screen (real seconds).
const MAX_STEPS_PER_FRAME := 60
const MIN_ROAD_S := 2.5
## Three on foot (the seats of a vehicle otherwise): the avatar counts.
const MAX_ON_FOOT := 3
## The road home runs this many game minutes past the party's own time, so that they have reached the gate when it ends.
const ARRIVAL_MARGIN_MIN := 1.5
## How many news lines the overlay and the report keep.
const MAX_NEWS_LINES := 6

var sim
## The colony people who go (the avatar first), the party the colony keeps for them, and where.
var going: Array = []
var party: Dictionary = {}
var place_id := ""
var action := "loot"
var vehicle_id := ""
## Why `begin` was refused ("" when it was not).
var error := ""
## "idle", "road_there", "place", "road_home", "home".
var stage := "idle"
## The road in game minutes: all of it and what is left.
var road_total := 0.0
var road_left := 0.0
## The radio's newest news when the trip began (what the road and the place add is "news while you were out").
var news_from := 0
## The place's steps taken so far, and the colony's steps taken for them.
var place_steps := 0
var colony_steps := 0
## The clock of the colony (`clock_min`) when the trip began and the day: for the report.
var started_clock := 0.0
## The result the place gave (kept for the report).
var result: Dictionary = {}


func _init(colony) -> void:
	sim = colony


# ---------------------------------------------------------------- the party --

## Who goes when `chosen` (colony people) are asked to come: {"going": [the avatar, then those who said yes], "refused":
## [{"p", "why"}] (those who cannot, with the reason the radio gives), "left_out": [{"p", "why"}] (those who would not fit)}.
## With no avatar (the old game) nobody is asked: the chosen all go as they were, in the order they were picked.
static func pick_party(colony, chosen: Array, vehicle: String = "") -> Dictionary:
	var avatar = colony.avatar.player() if String(colony.player_id) != "" else null
	var asking: bool = avatar != null
	var yes: Array = []
	var refused: Array = []
	var left_out: Array = []
	for p in chosen:
		if p == null or p == avatar or yes.has(p):
			continue
		if asking:
			var w: Dictionary = colony.radio.willingness(p, "come")
			if not bool(w.ok):
				refused.append({"p": p, "why": _with_name(p, String(w.why))})
				continue
		yes.append(p)
	var most := seats(colony, vehicle)
	var room := most - (1 if asking else 0)
	while yes.size() > maxi(room, 0):
		var last = yes.pop_back()
		left_out.append({"p": last, "why": "%s stays: %s." % [String(last.first), ("room for %d" % most) if vehicle != "" else "three is the most on foot"]})
	var out: Array = []
	if asking:
		out.append(avatar)
	out.append_array(yes)
	return {"going": out, "refused": refused, "left_out": left_out}


## The most people a trip can take: the vehicle's seats, else three on foot.
static func seats(colony, vehicle: String) -> int:
	if vehicle != "":
		return int(colony.vehicles.kind_of(vehicle).get("seats", MAX_ON_FOOT))
	return MAX_ON_FOOT


static func _with_name(p, why: String) -> String:
	var first := String(p.first)
	return why if why.begins_with(first) else "%s: %s" % [first, why]


## What the picker tells the player (one line each) about those who did not come.
static func refusal_lines(picked: Dictionary) -> Array:
	var out: Array = []
	for r in picked.get("refused", []):
		out.append(String(r.why))
	for r in picked.get("left_out", []):
		out.append(String(r.why))
	return out


# -------------------------------------------------------------------- begin --

## The errand a played trip is made as at this place: looting where there is something to take, else clearing.
static func errand_at(colony, place_id_: String, vehicle: String, people: Array) -> String:
	if colony.scavenge.why_not_played(people, place_id_, "loot", vehicle) == "":
		return "loot"
	if colony.scavenge.why_not_played(people, place_id_, "clear", vehicle) == "":
		return "clear"
	return "loot"


## The trip begins: the party is made at once ("in_place"; its people gone from the base, the vehicle out), the road there is
## set. False, with `error` saying why, when the colony's rules refuse it.
func begin(people: Array, place: String, vehicle: String = "") -> bool:
	error = ""
	going = people.duplicate()
	place_id = place
	vehicle_id = vehicle
	action = errand_at(sim, place, vehicle, people)
	var why: String = sim.scavenge.why_not_played(people, place, action, vehicle)
	if why != "":
		error = why
		return false
	party = sim.scavenge.begin_played(people, place, action, vehicle)
	if party.is_empty():
		error = "They could not go out just now."
		return false
	road_total = sim.scavenge.road_minutes(place, vehicle)
	road_left = road_total
	news_from = int(sim.radio.latest_id())
	started_clock = float(sim.clock_min)
	place_steps = 0
	colony_steps = 0
	stage = "road_there"
	return true


# --------------------------------------------------------------------- road --

## How many colony steps this frame of the road may take: enough to play the whole road out in MIN_ROAD_S, at most
## MAX_STEPS_PER_FRAME, at least one.
func road_budget(dt: float) -> int:
	var rate := maxf(float(sim.min_per_sec), 0.001)
	var all_steps := road_total / (rate * StepClock.STEP)
	return clampi(ceili(all_steps * maxf(dt, 0.0) / MIN_ROAD_S), 1, MAX_STEPS_PER_FRAME)


## One frame of the road (there or home): the colony runs ahead. True when the road is done.
func road_step(dt: float) -> bool:
	if road_left <= 1.0e-6:
		return true
	road_left = sim.fast_forward(road_left, road_budget(dt))
	if String(sim.over) != "":
		road_left = 0.0
	return road_left <= 1.0e-6


## How much of the road is behind (0 to 1).
func road_progress() -> float:
	if road_total <= 1.0e-6:
		return 1.0
	return clampf(1.0 - road_left / road_total, 0.0, 1.0)


## The road there is done: the place is played from now.
func arrive() -> void:
	stage = "place"


# -------------------------------------------------------------------- place --

## One step of the place has been taken: the colony takes the steps that are owed for it (one in PLACE_STEP_RATIO), each
## followed by the place's Sim being given the colony's clock. Returns how many colony steps were taken.
func place_step(run_sim, dt: float = StepClock.STEP) -> int:
	place_steps += 1
	var want: int = Sim.background_steps_for(place_steps)
	var n := 0
	if colony_steps < want:
		# (the yard is hidden meanwhile: nothing it would draw is made, as in `Sim.fast_forward`)
		var real_fx = sim.fx
		sim.fx = FxNull.new()
		while colony_steps < want:
			colony_steps += 1
			if String(sim.over) == "":
				sim.update(dt)
			if run_sim != null:
				run_sim.mirror(sim)
			n += 1
		sim.fx = real_fx
	return n


# ------------------------------------------------------------------- finish --

## The place is over and `played` is what the scene made of it (a `RaidRun.result()`): the party is on the road home, the
## radio knows who came back and how the squad took it, and the road home is set. `played` is kept as `result`.
func finish(played: Dictionary) -> void:
	result = played
	sim.scavenge.finish_played(party, played)
	# the trust the trip earned: the place's own count (who followed to the end, never down), else the radio's flat bonus for
	# everyone who came back (the two are the same sum: only one is paid)
	if played.has("trust_delta"):
		_apply_trust(played.trust_delta)
	else:
		var came: Array = []
		var lost: Array = played.get("lost", [])
		for p in going:
			if not p.dead and not lost.has(String(p.id)):
				came.append(p)
		sim.radio.on_trip_led(came)
	_agree_on_the_leader(played)
	# (a minute more than the road, for the party's own time is a whole minute: they are at the gate when the road is done)
	road_total = sim.scavenge.road_minutes(place_id, vehicle_id) + ARRIVAL_MARGIN_MIN
	road_left = road_total
	stage = "road_home"


## The base's player is the person who led in the place when it ended (the scene passes the succession on as it happens; this is
## the safety for a trip whose last leader was not told to the base): not when that person is lost, whose loss the base's own
## succession takes care of when they are told dead.
func _agree_on_the_leader(played: Dictionary) -> void:
	if String(sim.player_id) == "" or not played.has("leader"):
		return
	var id := String(played.leader)
	if id == String(sim.player_id) or (played.get("lost", []) as Array).has(id):
		return
	for p in sim.people:
		if String(p.id) == id and not p.dead and not p.turned:
			sim.avatar.set_player(p)
			return


## The trust the place moved: a number for each person ({id: delta}), or one for them all.
func _apply_trust(delta) -> void:
	if delta is Dictionary:
		for id in delta:
			for p in sim.people:
				if String(p.id) == String(id) and not p.dead:
					sim.radio.add_trust(p, float(delta[id]), "On the trip")
	elif typeof(delta) == TYPE_FLOAT or typeof(delta) == TYPE_INT:
		if float(delta) != 0.0:
			for p in going:
				if not p.dead:
					sim.radio.add_trust(p, float(delta), "On the trip")


## The road home is done and the colony view comes back.
func home() -> void:
	stage = "home"


# --------------------------------------------------------------------- news --

## What the radio has logged since the trip began, oldest first: [{"text", "sub", "kind", ...}] (the radio's own entries).
func news() -> Array:
	return sim.radio.news_since(news_from)


## The latest of them as lines of plain words, the newest last, at most `count`.
func news_lines(count: int = MAX_NEWS_LINES) -> Array:
	var lines: Array = []
	for e in news():
		var text := String(e.get("text", ""))
		if text != "":
			lines.append(text)
	return lines.slice(maxi(0, lines.size() - count))


# --------------------------------------------------------------------- base --

## How the base is: {"key": "ok" | "attack" | "alarm" | "night" | "fallen", "text": the words after "Base: "}.
static func base_state(colony) -> Dictionary:
	if String(colony.over) != "":
		return {"key": "fallen", "text": "has fallen"}
	if bool(colony.radio.alarm_on):
		return {"key": "alarm", "text": "alarm, everyone at the posts"}
	for z in colony.zombies:
		if z.state == "attack" or z.state == "breach":
			return {"key": "attack", "text": "under attack at the wall"}
	if String(colony.phase) == "night" or String(colony.phase) == "dusk":
		return {"key": "night", "text": "holding the wall"}
	return {"key": "ok", "text": "walls holding"}


## "Day 3, 14:20" for the colony's clock.
static func clock_text(colony) -> String:
	var h := fposmod(float(colony.hour), 24.0)
	return "Day %d, %02d:%02d" % [int(colony.day), int(h), int(fmod(h, 1.0) * 60.0)]
