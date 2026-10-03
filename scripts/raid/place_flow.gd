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
##                the place counted, `result.trust` (what it cost them and what it earned them: one number each, paid once);
##                `radio.on_trip_led` for the ones who came back when it counted none), the base is told who led at the end
##                (the loss of a leader who is lost, with its setback, or just the new player when she lived: see
##                `_agree_on_the_leader`) and the road HOME is run the same way as the road there. The people are home, or in
##                sight of the gate, when it is done.
## The road home is run AFTER `finish_played` (not before it): the party's way home is already in the colony's own rules
## (`return_at`), and the fast-forward only carries the clock to it, so the trip does not take its road twice.
##
## THE LIVE DRIVE (round 21, S21.4). For a trip the player leads in avatar mode (`live_for`) the overlay's road is replaced by two
## legs of a live drive (scripts/drive/drive_scene.gd plays them; this holds their rules): `begin_leg("there")`, the scene
## calls `leg_step` once per scene step (the colony runs behind it at the leg's pace: `pace_for`), `end_leg(result)` takes what
## the drive did to the people, the stores and the car; the place is played as ever (`arrive`, `place_step`, `finish`); then
## `begin_leg("home")`, `leg_step`, `end_leg(result)` and `home()`. The party is "in_place" from the gate to the place's end, and
## on the road home the colony does not bring it in by its own clock (`scavenge.hold_on_road`): it arrives when the drive ends
## (`scavenge.arrive_home`, by night too). The old overlay (`road_step`) stays for the classic game, the tests and `--fastroad`.
##
## The clock is the bonus: a leg takes `leg_seconds(road minutes)` real seconds at cruise (30 to 90), the colony takes
## `floor(scene steps x pace / 3)` steps behind it, so a drive at cruise takes exactly the road's game minutes, a faster one
## takes fewer (`saved_min`) and a slow one, a crash or a stop takes more. Fuel is not time: `vehicles.take` burnt both legs' fuel
## at the gate and nothing here burns more.
##
## What a LEG'S RESULT is (`end_leg`'s argument: DriveScene's `leg_result()`), every key optional:
##   hp {person id: health now}     the people who are still on their feet (written to the colony's people at once)
##   lost [ids]                     who is dead or down for good on this leg: they are out of the trip (`going`), dead at the return
##   hurt {id: "scratch"|"bite"}    wounds of this leg (the report; the colony wounds them when the party is home)
##   ammo_used float                what the squad shot on the road: taken from the stores at the end of the leg
##   vehicle_hp_lost float          what crashes, rams and the dead did to the car (`vehicles.road_wear`; NOT what `RoadEvents.apply`
##                                  took itself through the same function)
##   wrecked bool                   the car's hp hit 0 (`vehicles.wreck`: it is lost, the rest of the way is on foot)
##   failed bool                    nobody is left standing: no place, no road home, the colony settles the party
##   leader id                      who leads at the end of the leg (the run's own succession)
##   beats [strings], loot {stock: n}, survivors int    what the leg found that `RoadEvents.apply` did not already put in `road_loot`
##                                  and `road_survivors` (the scene must not report here what it applied: it would count twice)
extends RefCounted

const Sim := preload("res://scripts/sim/sim.gd")
const StepClock := preload("res://scripts/sim/step_clock.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Avatar := preload("res://scripts/sim/avatar.gd")

## The live drive's pace. A leg takes at least LEG_MIN_S and at most LEG_MAX_S real seconds at cruise whatever the road's minutes
## (the colony's clock runs faster on a long road, `pace_for`); a road strip is never longer than MAX_STRIP tiles; the car's top
## speed is TOP_FACTOR times its cruise.
const LEG_MIN_S := 30.0
const LEG_MAX_S := 90.0
const MAX_STRIP := 700
const TOP_FACTOR := 1.5
## A leg is called "there" or "home".
const LEGS := ["there", "home"]
## From this much lost to the car's wear a log line says the car took a beating (some knocks from the lesser).
const BEATING_HP := 20.0
const KNOCKS_HP := 8.0

## The live drive is on (the tests of round 17's overlay put it off: they keep the old road), `--fastroad` keeps the overlay for a
## whole run, `--noevents` leaves the road's events out (the scene asks `no_events`).
static var live_enabled := true
static var fast_road := false
static var no_events := false

## The most colony steps one frame of the road takes (about 60 is what a frame can spare), and the least a road takes to
## play out on the screen (real seconds).
const MAX_STEPS_PER_FRAME := 60
const MIN_ROAD_S := 2.5
## Three on foot (the seats of a vehicle otherwise): the avatar counts.
const MAX_ON_FOOT := 3
## How fast the base's clock runs while the place is played, against the yard's normal speed: a third (a game minute a real second
## where the yard has three). The radio's countdowns are read at this pace there (`RadioKit.left_seconds`).
const PLACE_PACE := 1.0 / Sim.PLACE_STEP_RATIO
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
## Who of the people the player chose did not come, one line each with the reason ("Dez: bleeding, can't come": `refusal_lines` of
## `pick_party`; main.gd's `open_raid` sets it): the road's overlay and the report show them, so that nobody is left out unseen.
var refusals: Array = []
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
## The result the place gave (kept for the report; with the live drive, the place's result and the road's: after the road home
## it holds the whole trip's, `merge_road` and the home leg folded in).
var result: Dictionary = {}

## --- the live drive (see the header) ---
## The trip is a live drive (`main.open_raid` sets it from `live_for`): the legs below are used instead of `road_step`.
var live := false
## Everyone who left the base (`going` loses those lost on the road), who leads now (the run's last word), the car still runs.
var started: Array = []
var leader_id := ""
var vehicle_alive := true
## "there" | "home" | "": the leg on the road, its road in game minutes (the abstract leg), the game minutes per real second at cruise.
var leg_which := ""
var leg_road_min := 0.0
var leg_pace := 1.0
## The scene's steps in this leg and the colony's steps taken behind them.
var leg_steps := 0
var leg_colony := 0
## What the road gave and took (both legs): the loot found and the wounds, the lost, the people taken in, the beats and the
## ammo shot (the report's; the loot, the lost and the hurt go to the colony in the place's result: `merge_road`).
var road_loot := {}
var road_hurt := {}
var road_lost: Array = []
var road_survivors := 0
var road_beats: Array = []
var road_ammo := 0.0
## The mood the road's choices left (what `RoadEvents.apply` writes: people on the road are away and the base's `morale.shock` would not
## reach them): the colony shocks the ones who come home by it ("On the road"), in the result's `morale`.
var road_morale := 0.0
## Nobody was left standing on the road (no place, no road home: the colony has settled the party).
var failed := false
## What each leg was, for the report: [{"leg", "road_min", "elapsed_min", "saved_min", "pace", "vehicle_hp_lost", "wrecked", "lost", "failed"}].
var legs: Array = []
var last_leg: Dictionary = {}
## The ammo the legs have already taken from the stores (the place's `finish_played` must not take it again), and what the road's
## totals were when this leg began (the home leg's own findings are amended into the settled result).
var _ammo_paid := 0.0
var _leg_from := {}
## `finish` has settled the trip (a trip that failed on the road is settled by `end_leg`: a scene's own `finish` after it is not paid twice).
var _settled := false


func _init(colony) -> void:
	sim = colony


# --------------------------------------------------------------- the pace --

## Whether a trip opened now is a live drive: the drive is on, `--fastroad` is not, and there is an avatar to drive (the classic game
## and the harness have none).
static func live_for(colony) -> bool:
	return live_enabled and not fast_road and String(colony.player_id) != ""


## The real seconds a leg of this many game minutes takes AT CRUISE: the road's minutes (a game minute a real second is the
## place's own 1:3), never fewer than LEG_MIN_S nor more than LEG_MAX_S.
static func leg_seconds(road_min: float) -> float:
	return clampf(road_min, LEG_MIN_S, LEG_MAX_S)


## How many game minutes the colony runs per real second of the leg at cruise: an 80 minute road is 1.0, a 36 minute one 1.2,
## a 185 minute one 2.1 and the longest walk 4.4.
static func pace_for(road_min: float) -> float:
	return maxf(road_min, 0.0) / leg_seconds(road_min)


## The tiles a second a vehicle of this kind (a row of vehicles.json) cruises at: the avatar's walk times its `speed` (a sedan 7.7,
## a pickup or a van 7.0, a bus 5.8); on foot ({}) the walk itself, 3.2.
static func cruise_of(kind: Dictionary) -> float:
	if kind.is_empty():
		return Avatar.WALK_SPEED
	return Avatar.WALK_SPEED * float(kind.get("speed", 1.0))


## How many tiles long the road of a leg is: the seconds it takes at cruise times the cruise, never more than MAX_STRIP.
static func strip_len(road_min: float, cruise: float) -> int:
	return mini(roundi(leg_seconds(road_min) * cruise), MAX_STRIP)


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
	started = people.duplicate()
	leader_id = String(sim.player_id) if String(sim.player_id) != "" and _is_going(String(sim.player_id)) else ""
	vehicle_alive = true
	road_loot = {}
	road_hurt = {}
	road_lost = []
	road_survivors = 0
	road_beats = []
	road_ammo = 0.0
	road_morale = 0.0
	_settled = false
	failed = false
	legs = []
	last_leg = {}
	leg_which = ""
	_ammo_paid = 0.0
	_leg_from = {}
	stage = "road_there"
	return true


func _is_going(id: String) -> bool:
	for p in going:
		if String(p.id) == id:
			return true
	return false


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


# --------------------------------------------------------------- the legs --
# The live drive (the header): what the scene asks of the flow while it drives.

## The road of the leg that is on, or of the next one, in game minutes (the abstract leg: half the round trip by the vehicle, the
## whole way on foot once the car is gone).
func leg_road_minutes() -> float:
	return sim.scavenge.road_minutes(place_id, vehicle_id if vehicle_alive else "")


## The tiles a second the party cruises at on this road: the car's, or the walk's.
func leg_cruise() -> float:
	if vehicle_alive and vehicle_id != "":
		return cruise_of(sim.vehicles.kind_of(vehicle_id))
	return cruise_of({})


## The kind of the vehicle the party drives now ("" on foot, or once the car is wrecked): a row of vehicles.json's id.
func vehicle_kind_now() -> String:
	if vehicle_alive and vehicle_id != "":
		return String(sim.vehicles.vehicle(vehicle_id).get("kind", ""))
	return ""


## What the road has said since the trip began, oldest first: the radio's "road" entries (a leg's words, an event's, who was lost), as
## lines (`news_lines` is everything the radio logged, newest six).
func road_news_lines() -> Array:
	var lines: Array = []
	for e in news():
		if String(e.get("kind", "")) == "road" and String(e.get("text", "")) != "":
			lines.append(String(e.text))
	return lines


## How many tiles long this road is (`strip_len` of its minutes and its cruise).
func leg_strip_len() -> int:
	return strip_len(leg_road_minutes(), leg_cruise())


## A leg begins ("there" or "home"): the counters start again, the colony's pace is the road's, and on the way home the colony is told
## to leave the party alone until the drive is over.
func begin_leg(which: String) -> void:
	leg_which = which if LEGS.has(which) else "there"
	leg_road_min = leg_road_minutes()
	leg_pace = pace_for(leg_road_min)
	leg_steps = 0
	leg_colony = 0
	_leg_from = {"loot": road_loot.duplicate(), "hurt": road_hurt.duplicate(), "lost": road_lost.duplicate(), "survivors": road_survivors,
		"beats": road_beats.size(), "ammo": road_ammo, "morale": road_morale}
	if leg_which == "home":
		stage = "drive_home"
		_hold_on_road(true)
	else:
		stage = "drive_there"


## One step of the scene has been taken on the road: the colony takes the steps that are owed for it, `floor(steps x pace / 3)` in all
## (the running total, so no remainder is lost), each followed by the road's Sim being given the colony's clock. Returns how many
## colony steps were taken.
func leg_step(run_sim, dt: float = StepClock.STEP) -> int:
	leg_steps += 1
	var want := floori(float(leg_steps) * leg_pace / float(Sim.PLACE_STEP_RATIO) + 1.0e-9)
	var n := 0
	if leg_colony < want:
		var real_fx = sim.fx
		sim.fx = FxNull.new()
		while leg_colony < want:
			leg_colony += 1
			if String(sim.over) == "":
				sim.update(dt)
			if run_sim != null:
				run_sim.mirror(sim)
			n += 1
		sim.fx = real_fx
	return n


## The game minutes the leg has taken so far: the colony's steps behind it, a tenth of a minute each at the colony's pace.
func elapsed_min() -> float:
	return float(leg_colony) * StepClock.STEP * float(sim.min_per_sec)


## The minutes the leg has saved on the road's own (a leg driven at cruise saves none, a perfect one a third of them): negative when it is
## behind.
func saved_min() -> float:
	return leg_road_min - elapsed_min()


## Ahead of the clock (positive) or behind it now, `progress` (0 to 1) of the way along: the share of the road's minutes less the
## minutes taken. The HUD's "Ahead of the clock: 6 min" / "Behind: 9 min".
func delta_min(progress: float) -> float:
	return clampf(progress, 0.0, 1.0) * leg_road_min - elapsed_min()


## A leg is over; `r` is the scene's result of it (see the header). What it did to the people, the stores and the car is taken now, the
## radio is told how it went; after the way there the place is next (`stage` "place"), after the way home the party arrives (the colony
## brings it in at once, by night too) and the trip is over. A leg in which nobody was left standing ends the trip (`failed`).
func end_leg(r: Dictionary) -> void:
	var which := leg_which if leg_which != "" else "there"
	var elapsed := elapsed_min()
	var saved := leg_road_min - elapsed
	var broke: bool = bool(r.get("failed", false))
	_take_health(r.get("hp", {}))
	# who is lost: out of the trip from here (the colony buries them when the party is home); with nobody standing, everyone is
	var lost_now: Array = []
	for id in r.get("lost", []):
		var sid := String(id)
		if _started_has(sid) and not road_lost.has(sid) and not lost_now.has(sid):
			lost_now.append(sid)
	if broke:
		for p in going:
			var pid := String(p.id)
			if not road_lost.has(pid) and not lost_now.has(pid):
				lost_now.append(pid)
	road_lost.append_array(lost_now)
	going = going.filter(func(p): return not road_lost.has(String(p.id)))
	var hurt = r.get("hurt", {})
	if hurt is Dictionary:
		for id in hurt:
			if _started_has(String(id)):
				road_hurt[String(id)] = _worse(String(road_hurt.get(String(id), "")), "scratch" if String(hurt[id]) == "scratch" else "bite")
	# what the squad shot is taken from the stores now (the place begins with what is left)
	var used := clampf(float(r.get("ammo_used", 0.0)), 0.0, float(sim.stock.ammo))
	if used > 0.0:
		sim.stock.ammo = float(sim.stock.ammo) - used
		_ammo_paid += used
		road_ammo += used
	var found = r.get("loot", {})
	if found is Dictionary:
		for k in found:
			if int(found[k]) > 0:
				road_loot[String(k)] = int(road_loot.get(String(k), 0)) + int(found[k])
	road_survivors += maxi(0, int(r.get("survivors", 0)))
	for b in r.get("beats", []):
		road_beats.append(String(b))
	# the car
	var wear := 0.0
	var wrecked := false
	var car_name := ""
	if vehicle_alive and vehicle_id != "":
		wear = maxf(0.0, float(r.get("vehicle_hp_lost", 0.0)))
		car_name = String(sim.vehicles.name_of(vehicle_id)).to_lower()
		if bool(r.get("wrecked", false)):
			wrecked = true
		elif wear > 0.0 and not _road_wear(wear):
			wrecked = true
		if wrecked:
			_wreck_vehicle()
	# who leads
	var lead := String(r.get("leader", ""))
	if lead != "" and not road_lost.has(lead):
		leader_id = lead
	elif road_lost.has(leader_id):
		leader_id = ""
	var entry := {"leg": which, "road_min": leg_road_min, "elapsed_min": elapsed, "saved_min": saved, "pace": leg_pace, "vehicle_hp_lost": wear,
		"wrecked": wrecked, "lost": lost_now.duplicate(), "failed": broke}
	last_leg = entry
	legs.append(entry)
	entry["line"] = _log_leg(entry, car_name)
	if broke:
		failed = true
	if which == "there":
		if broke:
			# no place and no road home: the colony settles the party (nobody is coming home, it buries them and tells the story)
			finish(merge_road({"loot": {}, "hurt": {}, "lost": [], "ammo_used": 0.0, "beats": []}))
			stage = "home"
		else:
			stage = "place"
		return
	_end_home_leg(lost_now)


## The way home is over: what the road home found and lost is put into the result the colony already holds, the party arrives (now,
## whatever the hour) and the base is told who leads if that changed on the road.
func _end_home_leg(lost_now: Array) -> void:
	var d := _home_findings()
	_amend(d)
	# the report's result has the road home in it too
	result = _fold(result, d)
	_arrive_home()
	_agree_on_the_leader({"leader": leader_id, "lost": lost_now}, "on the road")
	stage = "home"


## What the home leg found, as the settled result takes it: {"loot", "hurt", "lost", "road_survivors", "ammo", "beats", "morale",
## "road"}, the road's totals less what they were when the leg began.
func _home_findings() -> Dictionary:
	var loot := {}
	for k in road_loot:
		var more := int(road_loot[k]) - int(_leg_from.get("loot", {}).get(k, 0))
		if more > 0:
			loot[k] = more
	var hurt := {}
	for id in road_hurt:
		if String(_leg_from.get("hurt", {}).get(id, "")) != String(road_hurt[id]):
			hurt[id] = road_hurt[id]
	var lost: Array = []
	for id in road_lost:
		if not (_leg_from.get("lost", []) as Array).has(id):
			lost.append(id)
	var beats: Array = road_beats.slice(int(_leg_from.get("beats", 0)))
	return {"loot": loot, "hurt": hurt, "lost": lost, "road_survivors": road_survivors - int(_leg_from.get("survivors", 0)),
		"ammo": road_ammo - float(_leg_from.get("ammo", 0.0)), "beats": beats, "morale": road_morale - float(_leg_from.get("morale", 0.0)),
		"road": [String(last_leg.get("line", ""))] if String(last_leg.get("line", "")) != "" else []}


## The place's result with the road's findings folded in (what the road THERE found, and every leg's so far), for the colony and the
## report: the loot and the ammo shot are summed, the hurt and the lost are unioned (a bite is worse than a scratch), the road's beats
## are appended, the people taken in on the road are counted (`road_survivors`), the road's mood goes in `morale` and the legs' own
## words in `road`; `leader`, `hp`, `skills` and `trust` are the place's. A result that was merged says so (`road_merged`), so that
## `finish` does not take the road's ammo from the stores a second time.
func merge_road(played: Dictionary) -> Dictionary:
	var lines: Array = []
	for e in legs:
		if String(e.get("line", "")) != "":
			lines.append(String(e.line))
	var out := _fold(played, {"loot": road_loot, "hurt": road_hurt, "lost": road_lost, "ammo": road_ammo, "beats": road_beats,
		"road_survivors": road_survivors, "morale": road_morale, "road": lines})
	out["road_merged"] = true
	return out


## `base` (a result) with `found` ({"loot", "hurt", "lost", "ammo", "beats", "road_survivors", "morale", "road": every key optional}) added.
static func _fold(base: Dictionary, found: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	var sum: Dictionary = out.get("loot", {}).duplicate()
	var loot: Dictionary = found.get("loot", {})
	for k in loot:
		sum[k] = int(sum.get(k, 0)) + int(loot[k])
	out["loot"] = sum
	var wounds: Dictionary = out.get("hurt", {}).duplicate()
	var hurt: Dictionary = found.get("hurt", {})
	for id in hurt:
		wounds[id] = _worse(String(wounds.get(id, "")), String(hurt[id]))
	out["hurt"] = wounds
	var gone: Array = out.get("lost", []).duplicate()
	for id in found.get("lost", []):
		if not gone.has(String(id)):
			gone.append(String(id))
	out["lost"] = gone
	out["ammo_used"] = float(out.get("ammo_used", 0.0)) + float(found.get("ammo", 0.0))
	for key in ["beats", "road"]:
		var told: Array = out.get(key, []).duplicate()
		told.append_array(found.get(key, []))
		if not told.is_empty():
			out[key] = told
	if int(found.get("road_survivors", 0)) > 0:
		out["road_survivors"] = int(out.get("road_survivors", 0)) + int(found.road_survivors)
	if float(found.get("morale", 0.0)) != 0.0:
		out["morale"] = float(out.get("morale", 0.0)) + float(found.morale)
	return out


## The worse of two wounds: a bite, a scratch, none.
static func _worse(a: String, b: String) -> String:
	if a == "bite" or b == "bite":
		return "bite"
	return "scratch" if a == "scratch" or b == "scratch" else ""


func _started_has(id: String) -> bool:
	for p in started:
		if String(p.id) == id:
			return true
	return false


func _colony_person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


## The people on their feet have the health the road left them (the place and the report read it from the colony's own people).
func _take_health(hp) -> void:
	if not hp is Dictionary:
		return
	for id in hp:
		var p = _colony_person(String(id))
		if p != null and not p.dead and _started_has(String(id)) and not road_lost.has(String(id)):
			p.hp = clampf(float(hp[id]), 1.0, float(sim.scavenge.PLAYED_HP_MAX))


## "the pharmacy" for "The pharmacy": the place in a sentence.
func _where() -> String:
	var place_name := String(sim.town.place(place_id).get("name", "the place"))
	return "the " + place_name.trim_prefix("The ") if place_name.begins_with("The ") else place_name


## "8 min early", "14 min late", "on time": what the clock says of a leg (`saved` in game minutes).
static func early_late(saved: float) -> String:
	var m := roundi(absf(saved))
	if m < 1:
		return "on time"
	return "%d min %s" % [m, "early" if saved > 0.0 else "late"]


## What the road's log says of a leg, and of each person it lost.
func _log_leg(e: Dictionary, car_name: String) -> String:
	var there: bool = String(e.leg) == "there"
	var sub := ("The road to %s" if there else "The road home from %s") % _where()
	var text := ""
	if bool(e.failed):
		text = "Nobody got through"
	else:
		text = ("Arrived " if there else "Home ") + early_late(float(e.saved_min))
		if car_name != "":
			if bool(e.wrecked):
				text += ", the %s is a wreck" % car_name
			elif float(e.vehicle_hp_lost) >= BEATING_HP:
				text += ", the %s took a beating" % car_name
			elif float(e.vehicle_hp_lost) >= KNOCKS_HP:
				text += ", the %s took some knocks" % car_name
	sim.radio.log_news("road", text, sub)
	for id in e.lost:
		var p = _colony_person(String(id))
		if p != null:
			sim.radio.log_news("road", "%s was lost on the road" % String(p.first), sub)
	return "" if bool(e.failed) else text


# The colony's additions for a live road (EVENTS, S21.1): the party is held while its drive is on, a night party is let in, the road
# home's findings are amended into the settled result.

func _hold_on_road(on: bool) -> void:
	sim.scavenge.hold_on_road(party, on)


func _arrive_home() -> void:
	sim.scavenge.arrive_home(party)


func _amend(d: Dictionary) -> void:
	sim.scavenge.amend_result(party, {"loot": d.loot, "hurt": d.hurt, "lost": d.lost, "road_survivors": d.road_survivors, "beats": d.beats,
		"morale": d.morale, "road": d.road})


## The car wears by what the road did to it; false when it was at its last hp (then it is wrecked: `_wreck_vehicle`).
func _road_wear(hp_lost: float) -> bool:
	return sim.vehicles.road_wear(vehicle_id, hp_lost)


## The car is lost on the road (the colony says so and takes it off the fleet, its party on foot); the party walks the rest.
func _wreck_vehicle() -> void:
	vehicle_alive = false
	sim.vehicles.wreck(vehicle_id, "left on the road to %s" % _where())
	if party.has("vehicle"):
		party["vehicle"] = ""


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
	if _settled and failed:
		return    # (the road settled it already: nobody is paid twice)
	_settled = true
	result = played
	var settle := played
	if bool(played.get("road_merged", false)) and _ammo_paid > 0.0:
		# (the road's ammo was taken from the stores at the end of each leg: the colony takes only the place's now)
		settle = played.duplicate()
		settle["ammo_used"] = maxf(0.0, float(played.get("ammo_used", 0.0)) - _ammo_paid)
	sim.scavenge.finish_played(party, settle)
	# the trust the trip changed: the place's own count (`trust`: what it cost, a push to go or a bite while following, and the bonus
	# for who followed to the end, never down; `trust_delta` is that bonus alone), else the radio's flat bonus for everyone who
	# came back (they are the same sum: ONE number is paid for each person)
	if played.has("trust"):
		_apply_trust(played.trust)
	elif played.has("trust_delta"):
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
	if live and not _coming_home():
		stage = "home"    # (nobody is coming home: there is no road to drive)


## The colony has the party on its way home (it was not settled with nobody coming: `finish_played` drops that one at once).
func _coming_home() -> bool:
	for q in sim.scavenge.parties:
		if is_same(q, party):
			return String(q.state) == "away"
	return false


## The base is told who leads when the place ends (the scene does NOT tell it when the one you lead only falls: she may be got up
## and come home, and then nobody has been lost). The player the base has now is the one who went in; `played.leader` is who led at
## the end, `played.lost` who is not coming home:
##   - the old leader is lost (and the colony has not buried her yet: the road home does): the base's own succession now, with the
##     place's chosen heir (the last leader, if they are not lost) in place of its order, and so its setback (everyone's trust, the
##     mourning, the news). If nobody is left standing the colony has already buried everyone (`finish_played`) and has done it;
##   - the old leader lives: the last leader is the base's player, with no setback and no news of a loss (a line in the alerts says so).
func _agree_on_the_leader(played: Dictionary, where: String = "in the place") -> void:
	if String(sim.player_id) == "":
		return
	var old = sim.avatar.player()
	# (a leader lost on the road is no longer in `going` but did go: `started` is everyone who left)
	if old == null or not (going.has(old) or started.has(old)):
		return
	var lost: Array = played.get("lost", [])
	var heir = null
	var heir_id := String(played.get("leader", ""))
	if heir_id != "" and not lost.has(heir_id):
		for p in sim.people:
			if String(p.id) == heir_id and not p.dead and not p.turned:
				heir = p
	if lost.has(String(old.id)):
		if not old.dead:
			sim.avatar.on_player_lost(old, heir)
	elif heir != null and heir != old:
		sim.avatar.set_player(heir)
		sim.alert("leader", "info", "You are %s now" % heir.first, "%s went down %s" % [old.first, where], null, 20.0)


## The trust the place moved: a number for each person ({id: delta}), or one for them all.
func _apply_trust(delta) -> void:
	if delta is Dictionary:
		for id in delta:
			for p in sim.people:
				if String(p.id) == String(id) and not p.dead:
					sim.radio.add_trust(p, float(delta[id]), _trust_reason(float(delta[id])))
	elif typeof(delta) == TYPE_FLOAT or typeof(delta) == TYPE_INT:
		if float(delta) != 0.0:
			for p in going:
				if not p.dead:
					sim.radio.add_trust(p, float(delta), _trust_reason(float(delta)))


## What the tooltip says the trip did to their trust.
static func _trust_reason(delta: float) -> String:
	return "Came back safe from a trip you led" if delta >= 0.0 else "Pushed or hurt on a trip you led"


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
