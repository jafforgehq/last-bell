## Scavenging trips: at dawn the player sends one or two survivors through the
## gate to a site; they are off the map until the afternoon and come back with
## loot, hurt, or not at all.
##
## A trip goes like this:
##   send()    makes the party and decides its whole result from sim.rng (the
##             loot, who is hurt, who is lost). Nothing is applied yet.
##   "out"     the members walk to the gate (goal_for). One who comes within
##             GATE_REACH tiles of it is through: p.away is set and main.gd stops
##             drawing them. One who is given an order, goes down or dies on the
##             way is left out of the party; if that is everyone, the trip is off.
##   "away"    everyone is through; nothing happens until the party is due.
##   back      at return_at (16:00), or at dusk at the latest (nobody is out
##             overnight), the living reappear at the gate, the loot goes into
##             sim.stock, wounds and deaths go through sim.medical, and an alert
##             and a banner tell the story.
##
## Shapes other code may rely on (plain data only, so it can be saved as JSON):
##   party = {"kind": "party", "n": trip number, "members": [person ids],
##            "site": site id, "state": "out" | "away" (a trip by car has more, and a played one is "in_place": see below),
##            "return_at": clock_min,
##            "result": {"loot": {stock: int}, "hurt": {id: "scratch" | "bite"},
##                       "lost": [ids]}}
##   p.away is that very dictionary while a member is off the map, and
##   {"kind": "lost", "site": id} for someone who did not come back (who is dead
##   and stays off the map).
##
## A raided site is "picked over" (closed) until PICKED_OVER_DAYS days after the
## raid, and every raid in the last RAID_MEMORY_DAYS days cuts its loot by
## RAID_FACTOR. A site that reopens on the first day it can is therefore worth
## 75%; one left another day is whole again.
##
## THE TOWN (round 8). In the settlement game (a small start) the sites are the places of the town board
## (`sim.town`): `use_town()` swaps them in, `available_sites()` lists the known ones with their distance
## and what can be done there, a trip takes `2 x hours + SEARCH_H` hours (the party may be out overnight and
## comes back by day), and `send(people, place, action)` takes an action: "loot" (as before), "scout" (no
## loot, shows the places near), "clear" (the place is turned out: its nest and its danger go, if the
## party is strong enough). The way there and back also meets the town's beats (data), decided with the
## rest at the send. A rescue brings a survivor home. In the classic start none of this exists.
##
## A TRIP BY CAR (round 15, "the yard in motion"). A party sent in a vehicle does not vanish at the gate: its states are
##   "out"          the members walk to the doors of the car (`goal_for`: `Convoy.door_spot` of the door of their seat,
##                  "Heading for the car"). One who stands within BOARD_REACH of it is held still and the door opens:
##                  party.doors gets {pid, door, t, dur: BOARD_MIN, dir: "in"} (game minutes); at half of `dur` they go in
##                  (`p.away` is the party, as ever, and they are hidden), at `dur` the door shuts and the entry ends. A
##                  door takes one at a time (a bus has the one), the others queue beside it. One who is given another
##                  errand on the way is let go as on foot (the trip is decided again for the smaller party if nobody has
##                  gone in yet; nobody left: the trip is called off and the vehicle and its fuel are given back).
##   "driving_out"  everybody is aboard and every door is shut: `drive_t` of `drive_len` game minutes along the vehicle's
##                  out route (`Convoy.route(spot, "out")`; the length of the route over CAR_SPEED_TPM, about six seconds
##                  at the normal speed). The rules never move the car: the view takes its pose from `drive_t / drive_len`.
##   "away"         the trip's hours, which start when the car has left the map (`return_at` and `depart` are moved to then,
##                  so the drive out is not taken out of them).
##   "driving_in"   at the hour the party is due the car drives in along the in route (`drive_t` of `drive_len` again).
##   "unloading"    the car is parked. Every UNLOAD_GAP_MIN game minutes the next person gets out: {pid, door, t, dur, dir:
##                  "out"} in party.doors; at half of `dur` they stand at their door (`p.away` is null, facing away from the
##                  car) and are free; at `dur` the door shuts. When the last door has shut the trip is told as ever (the
##                  loot, the wounds, the report, the vehicle home), everyone who came home already stands at their door.
##                  A party nobody survived (the vehicle is lost with it), or that never left, does not drive home.
## A trip on foot is as it was ("out", "away"). The party also has `seats` ({id: the seat in the vehicle}), `aboard` and
## `unload` (the people to get out, in order) and `unload_wait` while it unloads. A played trip (`send_played`) by vehicle
## skips the way out (the raid screen was it): it is "away" at once, and comes home the same way as the others.
##
## Events of a trip by car (for the view and the sounds; the rules need none of them):
##   {"type": "board", "vehicle": id, "person": id, "door": door id}    a person goes in (the middle of the door's time)
##   {"type": "seated", "vehicle": id, "person": id, "door": door id}   the door shuts behind them
##   {"type": "depart", "vehicle": id}                                  everybody is in: the car starts to drive out
##   {"type": "arrive", "vehicle": id}                                  the hour is up: the car comes back (it starts to drive in)
##   {"type": "parked", "vehicle": id}                                  the car has driven in and stopped in its bay
##   {"type": "alight", "vehicle": id, "person": id, "door": door id}   a person has got out (stands at their door)
## Besides these, only the rules' own "banner" events.
##
## A TRIP IN A PLACE (round 17, "one survivor and a radio"). The player plays the place while the base goes on:
##   begin_played(people, place, action, vehicle) -> the party, or {} (refused as `send` refuses, see `why_not_played`).
##        The party is "in_place" at once: its members are away (gone from the base), the vehicle is out and its fuel is
##        burnt, the place is raided. Nothing is due while it is in the place (`return_at` is only the old estimate, for
##        the Town Board's map): the base's rules run on, jobs, nights, the day's threat, the radio.
##   finish_played(party or its number, result) -> the scene says what came of it. The result is sanitised as a played
##        result always is (`_played_result`), the members' health and skills are put back (see below), and the party is on
##        the road home: "away" with `return_at = clock_min + road_minutes` (half the round trip by vehicle, the way there
##        on foot: the abstract travel until the live drive), then home as any trip (`driving_in`, `_come_back`, the report).
##        A party nobody of whom is left is settled at once (nobody is on the road): the banner, the vehicle lost. A second
##        finish, or one for a party that is not in a place, does nothing.
##   A save in the place loads as a party that is still "in_place" and is finished at the next step with an empty result (the
##        scene is not saved): they turn back with nothing and come home after the road.
## The played result (`RaidRun.result()`, in the dice's shape: loot, hurt, lost, clear, rescue, beats, ammo_used) has two keys
## more for this: `hp` {person id: health (0 to 100) they have when they leave the place} and `skills` {person id: {skill:
## points gained there}}. Both are applied at the finish to those who come home (a missing key changes nothing).
##
## THE LIVE ROAD (round 21, "the live drive"). A trip the player leads in avatar mode drives its road home in a scene instead of
## the abstract travel: `hold_on_road(party, true)` keeps the party from being due while the scene plays that road (the flag
## `road_live` is not saved: a load falls back to the abstract return); `amend_result(party, d)` merges what the road found
## ({hurt, lost, loot, hp, morale, road_survivors, road, beats}) into the settled result, sanitised as the place's result is;
## `arrive_home(party)` ends the road: the party is due at once, night or not (`night_ok`, saved), and comes in at the gate as any
## trip does. `result.road_survivors` (a whole number) are the survivors the squad took in on the road: they join the crew as a
## rescue does (`recruits.rescue_home("road")`), the ones with no bed stay callers and an alert says so. A vehicle wrecked on the
## road (`vehicles.wreck`) turns its party into a party on foot.
extends RefCounted

const Convoy := preload("res://scripts/sim/convoy.gd")

const SITES_PATH := "res://assets/data/sites.json"
## Where the sites are read from (the harness and the tests may point it at another file).
static var sites_path := SITES_PATH

## The gate is wall section 2 ("Main gate"): parties leave and return through it.
const GATE_SEGMENT := 2
## Parties may leave between these hours of the morning (game clock) ...
const SEND_FROM_H := 6.5
const SEND_TO_H := 10.0
## ... and are due back at this hour of the same day.
const RETURN_H := 16.0
## A member is through the gate once this close to its centre (tiles).
const GATE_REACH := 1.2
## No party goes while this many living zombies are within DEAD_RADIUS tiles of the gate.
const DEAD_LIMIT := 3
const DEAD_RADIUS := 20.0
const MAX_PARTY := 2
## In the town two parties may be out at once, and up to three people go together.
const MAX_PARTIES_TOWN := 2
## Each stretch of the way meets a beat (the town's data) with this chance.
const BEAT_CHANCE := 0.6
## A trip that is out when the dusk falls (a night out, with no wall to stand behind) adds this to each member's
## wound chance (before their Shooting takes its share off).
const NIGHT_OUT_WOUND := 0.15
## The most of one stock a played trip may bring home (a squad carries far less: this only stops a forged result).
const PLAYED_LOOT_MAX := 400
const MAX_PARTY_TOWN := 3
## The days a raided site stays closed: raided on day 5, it opens again on day 8.
const PICKED_OVER_DAYS := 3
## Raids this many days back (or fewer) still cut the loot, each by RAID_FACTOR.
const RAID_MEMORY_DAYS := 3
const RAID_FACTOR := 0.75
## A lone scavenger carries less; a leader in the party finds more.
const LONE_FACTOR := 0.7
const LEADER_BONUS := 1.15
const LEADER_SKILL := 5
## A member's chance of a wound is WOUND_BASE x danger x difficulty x (1 - Shooting / 15),
## and BITE_SHARE of those are bites (the rest scratches).
const WOUND_BASE := 0.12
const BITE_SHARE := 0.25
## A member's chance of not coming back at a site of danger LOSS_MIN_DANGER or more:
## LOSS_BASE x difficulty.
const LOSS_BASE := 0.01
const LOSS_MIN_DANGER := 2
## The danger multiplier for story, standard and brutal.
const DANGER_MULT := [0.5, 1.0, 1.6]
## The stocks a trip can bring back, in the order they are rolled and told.
const STOCKS := ["food", "water", "scrap", "ammo", "meds", "fuel"]
## A trip by car (see the header): a person within BOARD_REACH tiles of their door starts to get in; a door takes BOARD_MIN game
## minutes (about 1.3 seconds at the normal speed) from the start of the entry to its end; those who are unloaded get out UNLOAD_GAP_MIN
## minutes apart; the car drives CAR_SPEED_TPM tiles in a game minute (the way out is about 70 tiles: about six seconds).
const BOARD_REACH := 0.7
const BOARD_MIN := 4.0
const UNLOAD_GAP_MIN := 2.5
const CAR_SPEED_TPM := 3.8
## The states a party can be in. "in_place": the player is playing the place (round 17, see the header).
const STATES := ["out", "driving_out", "away", "driving_in", "unloading", "in_place"]
const IN_PLACE := "in_place"
## The most health a person may come home with from a played trip.
const PLAYED_HP_MAX := 100.0
## The live road (round 21): the most survivors a trip may take in on its road, the most its mood may move (as the dice's beats),
## and the most lines of the road a result keeps.
const MAX_ROAD_SURVIVORS := 6
const MAX_ROAD_MORALE := 8.0
const MAX_ROAD_LINES := 6
const AWAY_COLOR := Color("#7fa6c9")
## How long the departure and return alerts stay up (seconds of rules time).
const DEPART_ALERT_TTL := 10.0
const RETURN_ALERT_TTL := 25.0

var sim
## The sites, loaded from assets/data/sites.json: [{"id", "name", "where", "blurb",
## "danger", "loot": {stock: [min, max]}, "extra": {stock: [chance, amount]},
## "image"}].
var sites: Array = []
## Parties out on a trip (at most one at a time); see the header for their shape.
var parties: Array = []
## Site id -> the days (sim.day) it was raided on, oldest first.
var raids := {}
## Trips made in this run: numbers the trips and their alerts.
var trips := 0
## Errands the storyteller made up (a crate in the road): site id to a site shaped like those
## above. They are not offered in the dialog; `send` takes them at any hour of the day.
var errands := {}
## Whether the sites are the town's (see the header).
var town_mode := false


func setup(s) -> void:
	sim = s
	_load_sites()


func start() -> void:
	if town_mode:
		town_mode = false
		_load_sites()
	parties.clear()
	raids.clear()
	trips = 0
	errands.clear()


## Every step: parties walking to the gate (or to their car), away, and coming back.
func update(dt: float) -> void:
	sim.vehicles.sync_blocks()    # (the ground under the cars that stand in their bays: people walk round them)
	if parties.is_empty():
		return
	var mins := dt * float(sim.min_per_sec)
	var keep: Array = []
	for party in parties:
		var open := true
		var by_car := _by_car(party)
		match String(party.state):
			"out":
				open = _board_out(party, mins) if by_car else _walk_out(party)
			"driving_out":
				_drive_out(party, mins)
			"driving_in":
				_drive_in(party, mins)
			"unloading":
				open = _unload(party, mins)
			"in_place":
				if bool(party.get("orphan", false)):
					open = _finish_party(party, {})    # (loaded from a save: the scene is gone, they turn back with nothing)
		var waiting: bool = String(party.state) == "out" or String(party.state) == "away"
		if open and waiting and _is_due(party):
			if by_car and String(party.state) == "away":
				open = _start_return(party)
			else:
				_come_back(party)
				open = false
		if open:
			keep.append(party)
	parties = keep


## A goal for a party member walking to the gate (or to the door of their car), or null (once they are back
## the rules walk them to their post or job as usual).
func goal_for(p):
	var party = _party_of(p)
	if party == null or party.state != "out" or _is_through(p, party):
		return null
	if _by_car(party):
		return _car_goal(party, p)
	var gate := gate_center()
	return {"x": gate.x, "y": gate.y, "face": "N", "what": "Heading for the gate"}


## Whether a trip can be sent now (daytime departure window, nobody out
## already, not too many of the dead at the gate, someone free), and why not if
## it cannot.
func can_send() -> bool:
	return why_not() == ""


func why_not() -> String:
	return _why_not(false)


## `why_not`, for a trip the player leads when `played` (the avatar may go: someone is free if the player is).
func _why_not(played: bool) -> String:
	if sim.over != "":
		return "The run is over."
	if sim.phase == "dusk" or sim.phase == "night":
		return "Nobody goes out after dark."
	if sim.phase == "dawn" or sim.hour < SEND_FROM_H:
		return "Too early: wait for daylight (%s)." % _clock_text(maxf(SEND_FROM_H, float(sim.seasons.dawn_hour())))
	if sim.hour >= SEND_TO_H:
		return "Too late: parties leave between %s and 10:00." % _clock_text(maxf(SEND_FROM_H, float(sim.seasons.dawn_hour())))
	if parties.size() >= (MAX_PARTIES_TOWN if town_mode else 1):
		return "A party is already out." if not town_mode else "Both parties are out."
	if dead_at_gate() >= DEAD_LIMIT:
		return "Too many of the dead at the gate."
	if free_survivors(played).is_empty():
		return "Nobody is free to go."
	return ""


## The sites the player may pick now, each with its current state: the site's
## own fields plus {"loot_hint", "available", "note"}. A raided site is not
## available ("picked over") until it reopens.
func available_sites() -> Array:
	if town_mode:
		return _town_sites()
	var out: Array = []
	for s in sites:
		var e: Dictionary = s.duplicate(true)
		var id: String = s.id
		e["loot_hint"] = _hint(s)
		var wait := _days_until_ready(id)
		e["available"] = wait <= 0
		if wait > 0:
			e["note"] = "Picked over. Ready again on day %d." % (_last_raid(id) + PICKED_OVER_DAYS)
		elif _recent_raids(id) > 0:
			e["note"] = "Raided on day %d: less to find." % _last_raid(id)
		else:
			e["note"] = ""
		out.append(e)
	return out


## Sends the survivors (Person objects, one or two) to the site (its id). True
## if it went. The party's result is decided here.
func send(people: Array, site_id: String, action: String = "loot", vehicle_id: String = "") -> bool:
	if town_mode and not errands.has(site_id):
		return _send_town(people, site_id, action, vehicle_id)
	if not (can_send() or _errand_ok(site_id)):
		return false
	if people.is_empty() or people.size() > MAX_PARTY:
		return false
	if _site(site_id).is_empty() or _days_until_ready(site_id) > 0:
		return false
	var ids: Array = []
	for p in people:
		if p == null or not can_go(p) or ids.has(p.id):
			return false
		ids.append(p.id)
	trips += 1
	var party := {
		"kind": "party",
		"n": trips,
		"members": ids,
		"site": site_id,
		"state": "out",
		# 16:00 of this day on the run's own clock, in whole minutes (saves as JSON exactly)
		"return_at": snappedf(sim.clock_min + (RETURN_H * 60.0 - sim.minutes), 1.0),
		"result": {},
	}
	for p in people:
		p.drafted = false
		p.order = null
		p.repair = null
		p.target = null
		p.goal_key = ""
	party.result = _decide(party)
	parties.append(party)
	return true


## Marks for the card and panel: members are "away".
func status_of(p) -> Array:
	var party = _party_of(p)
	if party == null:
		return []
	if String(party.state) == "unloading" and not _is_through(p, party):
		return []    # out of the car: home again, though the trip is not told yet
	var tip := "Away scavenging" if _is_through(p, party) else "Heading out to scavenge"
	if String(party.state) == IN_PLACE:
		tip = "Out at %s" % _where(String(party.site))    # (the player's trip: they are playing it)
	return [{"icon": "away", "color": AWAY_COLOR, "tip": tip}]


## The HUD's "Scavenge" button opens a dialog (which then calls send), so the
## rules take no part.
func gizmo(_id: String, _sel) -> bool:
	return false


# ------------------------------------------------------------ for the dialog --

## Whether `p` can be put in a party now: alive, on the map, on their feet, not
## drafted with an order, not already out, not busy treating someone or leaving
## through the gate, not delirious with fever. In an avatar game the only orders there are are the radio's (a stance that
## drafted them, "to the walls", a call's errand: the old controls are gone), and being taken on a trip is what "come with me"
## asks: the party's opening ends them, so they are no reason to refuse. The old game keeps refusing a person it has drafted
## or sent somewhere by hand.
func can_go(p, played: bool = false) -> bool:
	if p == null or p.dead or p.downed or p.away != null or sim.morale.breakdown(p) or (p.player and not played):
		return false    # (the player leaves by their own hands: a played trip (`played`), never the dice's party)
	if String(sim.player_id) == "" and (p.order != null or (p.drafted and String(p.stance) == "")):
		return false    # (a stance, the radio's, drafted them: that is not an order of the old controls)
	if _party_of(p) != null or sim.medical.goal_for(p) != null:
		return false
	return sim.medical.infection_stage(p) != "delirious"


## The survivors who can be sent now, in crew order.
func free_survivors(played: bool = false) -> Array:
	var out: Array = []
	for p in sim.people:
		if can_go(p, played):
			out.append(p)
	return out


## The centre of the gate: where parties leave and return.
func gate_center() -> Vector2:
	for s in sim.segments:
		if s.id == GATE_SEGMENT:
			return s.center
	return Vector2(39.0, 18.9)


## How many living zombies are within DEAD_RADIUS tiles of the gate.
func dead_at_gate() -> int:
	var gate := gate_center()
	var n := 0
	for z in sim.zombies:
		if z.state == "dying" or z.state == "dead":
			continue
		if Vector2(z.x - gate.x, z.y - gate.y).length() <= DEAD_RADIUS:
			n += 1
	return n


## What a played trip's loot is multiplied by at this place: each raid of the last days takes its share (RAID_FACTOR).
func raid_penalty(site_id: String) -> float:
	return pow(RAID_FACTOR, _recent_raids(site_id))


## What the loot of a trip by `people` to the site is multiplied by: less for
## each recent raid and for a lone scavenger, more with a leader.
func loot_scale(site_id: String, people: Array) -> float:
	var scale := pow(RAID_FACTOR, _recent_raids(site_id))
	if people.size() == 1:
		scale *= LONE_FACTOR
	for p in people:
		if int(p.skills.Leading) >= LEADER_SKILL:
			scale *= LEADER_BONUS
			break
	return scale


# ------------------------------------------------------------------- saving --

func save() -> Dictionary:
	var saved: Array = []
	for party in parties:
		var through: Array = []
		for id in party.members:
			var p = _person(String(id))
			if p != null and _is_through(p, party):
				through.append(id)
		var entry := {
			"n": int(party.n),
			"members": party.members.duplicate(),
			"through": through,
			"site": String(party.site),
			"state": String(party.state),
			"return_at": float(party.return_at),
			"result": _copy_result(party.result),
			"action": String(party.get("action", "loot")),
			"depart": float(party.get("depart", -1.0)),
			"vehicle": String(party.get("vehicle", "")),
		}
		if bool(party.get("played", false)):
			entry["played"] = true
		if bool(party.get("night_ok", false)):
			entry["night_ok"] = true
		if _by_car(party):
			entry["seats"] = (party.get("seats", {}) as Dictionary).duplicate()
			entry["doors"] = _copy_doors(party.get("doors", []))
			for key in ["drive_t", "drive_len", "unload_wait"]:
				if party.has(key):
					entry[key] = float(party[key])
			for key in ["aboard", "unload"]:
				if party.has(key):
					entry[key] = (party[key] as Array).duplicate()
		saved.append(entry)
	var lost := {}
	for p in sim.people:
		if p.away is Dictionary and p.away.get("kind", "") == "lost":
			lost[p.id] = String(p.away.get("site", ""))
	var raided := {}
	for id in raids:
		raided[id] = raids[id].duplicate()
	return {"trips": trips, "raids": raided, "parties": saved, "lost": lost}


## Restores parties, raids and the lost onto a freshly built sim. The people
## themselves are restored by the save module; here their `away` is set again.
func load_state(d: Dictionary) -> void:
	parties.clear()
	raids.clear()
	trips = int(d.get("trips", 0))
	var raided = d.get("raids", {})
	if raided is Dictionary:
		for id in raided:
			var days: Array = []
			for day in raided[id]:
				days.append(int(day))
			raids[String(id)] = days
	var saved = d.get("parties", [])
	if saved is Array:
		for entry in saved:
			if entry is Dictionary:
				_restore_party(entry)
	var lost = d.get("lost", {})
	if lost is Dictionary:
		for id in lost:
			var p = _person(String(id))
			if p != null:
				p.away = {"kind": "lost", "site": String(lost[id])}


func _restore_party(entry: Dictionary) -> void:
	var members: Array = []
	for id in entry.get("members", []):
		members.append(String(id))
	var party := {
		"kind": "party",
		"n": int(entry.get("n", 0)),
		"members": members,
		"site": String(entry.get("site", "")),
		"state": String(entry.get("state", "away")),
		"return_at": float(entry.get("return_at", 0.0)),
		"result": _copy_result(entry.get("result", {})),
	}
	if entry.has("action"):
		party["action"] = String(entry.action)
	if float(entry.get("depart", -1.0)) >= 0.0:
		party["depart"] = float(entry.depart)
	if String(entry.get("vehicle", "")) != "":
		party["vehicle"] = String(entry.vehicle)
	if bool(entry.get("played", false)):
		party["played"] = true
	if bool(entry.get("night_ok", false)):
		party["night_ok"] = true
	if not STATES.has(String(party.state)) or (not _by_car(party) and not ["out", "away", IN_PLACE].has(String(party.state))):
		party["state"] = "away"    # (a state this version does not know, or a car's state for a party on foot)
	if String(party.state) == IN_PLACE:
		party["played"] = true
		party["orphan"] = true    # (the place's scene was not saved: the next step finishes the trip with nothing, see `update`)
	if _by_car(party):
		_restore_car(party, entry)
	parties.append(party)
	var through = entry.get("through", [])
	for id in members:
		var p = _person(id)
		if p != null:
			p.away = party if through is Array and through.has(id) else null


## A result as plain, typed data (whole-number loot, kinds as words, ids as strings).
func _copy_result(raw) -> Dictionary:
	var loot := {}
	var hurt := {}
	var lost: Array = []
	if raw is Dictionary:
		var raw_loot = raw.get("loot", {})
		if raw_loot is Dictionary:
			for k in STOCKS:
				if raw_loot.has(k) and int(raw_loot[k]) > 0:
					loot[k] = int(raw_loot[k])
		var raw_hurt = raw.get("hurt", {})
		if raw_hurt is Dictionary:
			for id in raw_hurt:
				hurt[String(id)] = String(raw_hurt[id])
		var raw_lost = raw.get("lost", [])
		if raw_lost is Array:
			for id in raw_lost:
				lost.append(String(id))
	var out := {"loot": loot, "hurt": hurt, "lost": lost}
	if raw is Dictionary:
		for k in ["clear", "rescue"]:
			if bool(raw.get(k, false)):
				out[k] = true
		for k in ["beats", "reveals"]:
			var list = raw.get(k, [])
			if list is Array and not list.is_empty():
				var strs: Array = []
				for v in list:
					strs.append(String(v))
				out[k] = strs
		if float(raw.get("morale", 0.0)) != 0.0:
			out["morale"] = float(raw.morale)
		if String(raw.get("vehicle", "")) != "":
			out["vehicle"] = String(raw.vehicle)
		if _is_number(raw.get("road_survivors", 0)) and int(raw.get("road_survivors", 0)) > 0:
			out["road_survivors"] = int(raw.road_survivors)
		var road_lines = raw.get("road", [])
		if road_lines is Array and not road_lines.is_empty():
			var texts: Array = []
			for v in road_lines:
				texts.append(String(v))
			out["road"] = texts
	return out


# ------------------------------------------------------------------ the trip --

## Moves a walking party along: members who reach the gate go through, members
## who were given other business are let go. False if the trip is called off.
func _walk_out(party: Dictionary) -> bool:
	var gate := gate_center()
	var someone_was_through := _any_through(party)
	var dropped := false
	for id in party.members.duplicate():
		var p = _person(String(id))
		if p != null and _is_through(p, party):
			continue
		if p == null or not _is_heading_out(p):
			party.members.erase(id)
			party.result.hurt.erase(id)
			party.result.lost.erase(id)
			dropped = true
			continue
		if Vector2(p.x - gate.x, p.y - gate.y).length() <= GATE_REACH:
			_go_through(p, party)
	if party.members.is_empty():
		_call_off(party)
		return false
	if dropped and not someone_was_through and not bool(party.get("played", false)):
		# nobody has left yet, so the trip is simply a smaller one (a played trip's result stands: it was played)
		party.result = _decide(party)
	if _all_through(party):
		party.state = "away"
		_announce_departure(party)
	return true


## Whether a member who has not yet reached the gate is still going there.
func _is_heading_out(p) -> bool:
	return not p.dead and not p.downed and not p.drafted and p.order == null and p.repair == null and not p.player


func _go_through(p, party: Dictionary) -> void:
	# a scout takes nothing, so it picks nothing over
	if not _any_through(party) and String(party.get("action", "loot")) != "scout":
		_record_raid(String(party.site))
	p.away = party
	p.moving = false
	p.path = []
	p.path_i = 0
	p.target = null
	p.goal_key = ""
	p.activity = "Scavenging at %s" % _where(String(party.site))
	_clear_stance(p)


## A person who leaves or comes home has no radio stance any more (follow, hold... are for the yard or the place they are
## in); the property is the radio's (round 17), so a person without it is left alone.
static func _clear_stance(p) -> void:
	if p.get("stance") != null:
		p.set("stance", "")


# ------------------------------------------------------------------ the trip by car --

## Whether the party travels in a vehicle.
func _by_car(party: Dictionary) -> bool:
	return String(party.get("vehicle", "")) != ""


func _vehicle_of(party: Dictionary) -> Dictionary:
	return sim.vehicles.vehicle(String(party.get("vehicle", "")))


## The party's place in the motor pool (0 for a vehicle that is not in the fleet any more: a damaged save).
func _spot_of(party: Dictionary) -> int:
	var v := _vehicle_of(party)
	return int(v.get("spot", 0)) if not v.is_empty() else 0


func _kind_id_of(party: Dictionary) -> String:
	return String(_vehicle_of(party).get("kind", ""))


## The door of a member's seat (a member with no seat takes the one their place in the party says).
func _door_of(party: Dictionary, id: String) -> String:
	var seats: Dictionary = party.get("seats", {})
	var seat := int(seats.get(id, party.members.find(id)))
	return String(sim.vehicles.seat_door(_kind_id_of(party), maxi(seat, 0), _spot_of(party)))


## Where a member stands to use their door.
func _door_at(party: Dictionary, id: String) -> Vector2:
	return Convoy.door_spot(_spot_of(party), _kind_id_of(party), _door_of(party, id))


## Which way a person at a door faces to look at the car: east from the west side of it, west from the east side.
func _face_to_car(party: Dictionary, at: Vector2) -> String:
	return "E" if at.x < Convoy.bay(_spot_of(party)).x else "W"


## The door entry of this person ("in" while they board, "out" as they leave), or {}.
func _entry_of(party: Dictionary, id: String, dir: String = "in") -> Dictionary:
	for e in party.get("doors", []):
		if String(e.pid) == id and String(e.dir) == dir:
			return e
	return {}


## A door is taken while someone who is going through it has not yet gone in (the one after them waits beside it).
func _door_busy(party: Dictionary, door: String) -> bool:
	for e in party.get("doors", []):
		if String(e.door) == door and String(e.dir) == "in" and float(e.t) < float(e.dur) / 2.0:
			return true
	return false


## How many of the party stand ahead of this member at their door (one door may serve several: a bus has the one).
func _queue_index(party: Dictionary, id: String, door: String) -> int:
	var n := 0
	for other in party.members:
		if String(other) == id:
			break
		var q = _person(String(other))
		if q != null and not _is_through(q, party) and _door_of(party, String(other)) == door:
			n += 1
	return n


## What a member walking to the car is told to do: go to the door of their seat (beside the others waiting at it); at the
## door with the door open, stand still.
func _car_goal(party: Dictionary, p):
	var id := String(p.id)
	var at := _door_at(party, id)
	var face := _face_to_car(party, at)
	if not _entry_of(party, id).is_empty():
		return {"x": p.x, "y": p.y, "face": face, "what": "Getting into the car"}
	var wait := float(_queue_index(party, id, _door_of(party, id))) * 0.6
	return {"x": at.x, "y": at.y + wait, "face": face, "what": "Heading for the car"}


## Moves a party walking to its car along: members who reach a door get in, members who were given other business are let
## go. False if the trip is called off.
func _board_out(party: Dictionary, mins: float) -> bool:
	var someone_was_through := _any_through(party)
	var dropped := false
	for id in party.members.duplicate():
		var p = _person(String(id))
		if p != null and _is_through(p, party):
			continue
		if p == null or not _is_heading_out(p):
			party.members.erase(id)
			party.result.hurt.erase(id)
			party.result.lost.erase(id)
			(party.seats as Dictionary).erase(String(id))
			for e in party.doors.duplicate():
				if String(e.pid) == String(id):
					party.doors.erase(e)
			dropped = true
	_step_doors(party, mins)
	for id in party.members:
		var p = _person(String(id))
		if p == null or _is_through(p, party) or not _entry_of(party, String(id)).is_empty():
			continue
		var door := _door_of(party, String(id))
		if Vector2(p.x, p.y).distance_to(_door_at(party, String(id))) <= BOARD_REACH and not _door_busy(party, door):
			party.doors.append({"pid": String(id), "door": door, "t": 0.0, "dur": BOARD_MIN, "dir": "in"})
	if party.members.is_empty():
		_call_off(party)
		return false
	if dropped and not someone_was_through and not bool(party.get("played", false)):
		# nobody has gone in yet, so the trip is simply a smaller one (a played trip's result stands: it was played)
		party.result = _decide(party)
	if _all_through(party) and party.doors.is_empty():
		_depart(party)
	return true


## Runs the open doors on: a person goes in at the middle of their door's time, the door shuts at its end.
func _step_doors(party: Dictionary, mins: float) -> void:
	for e in party.doors.duplicate():
		e["t"] = float(e.t) + mins
		var p = _person(String(e.pid))
		if p != null and String(e.dir) == "in" and not _is_through(p, party) and float(e.t) >= float(e.dur) / 2.0:
			_go_through(p, party)
			sim.events.append({"type": "board", "vehicle": String(party.vehicle), "person": String(e.pid), "door": String(e.door)})
		if float(e.t) >= float(e.dur):
			party.doors.erase(e)
			if String(e.dir) == "in":
				sim.events.append({"type": "seated", "vehicle": String(party.vehicle), "person": String(e.pid), "door": String(e.door)})


## Game minutes the car takes to drive a route.
func _drive_minutes(route: Array) -> float:
	return maxf(Convoy.length(route) / CAR_SPEED_TPM, 0.5)


## Everybody is in and every door is shut: the car drives out.
func _depart(party: Dictionary) -> void:
	party.state = "driving_out"
	party["drive_t"] = 0.0
	party["drive_len"] = _drive_minutes(Convoy.route(_spot_of(party), "out"))
	sim.events.append({"type": "depart", "vehicle": String(party.vehicle)})


func _drive_out(party: Dictionary, mins: float) -> void:
	party["drive_t"] = float(party.get("drive_t", 0.0)) + mins
	if float(party.drive_t) < float(party.get("drive_len", 0.0)):
		return
	# off the map: the trip's hours start now (the drive was not part of them)
	party.state = "away"
	party.erase("drive_t")
	party.erase("drive_len")
	if float(party.get("depart", -1.0)) >= 0.0:
		var trip := float(party.return_at) - float(party.depart)
		party["depart"] = sim.clock_min
		party.return_at = snappedf(sim.clock_min + trip, 1.0)
	_announce_departure(party)


## A played trip by car has no way out to show (the raid screen was it): everybody is off the map at once.
func _skip_departure(party: Dictionary) -> void:
	for id in party.members:
		var p = _person(String(id))
		if p != null:
			_go_through(p, party)
	party.state = "away"
	_announce_departure(party)


## The hour of return of a trip by car: the car drives in if somebody is in it to get out. False if the trip was settled at
## once instead (nobody lived, or nobody ever left: the vehicle is lost or was never gone).
func _start_return(party: Dictionary) -> bool:
	var aboard: Array = []
	var survivors: Array = []
	for id in party.members:
		var p = _person(String(id))
		if p == null or not _is_through(p, party):
			continue
		aboard.append(String(id))
		if not p.dead and not party.result.lost.has(id):
			survivors.append(String(id))
	if survivors.is_empty():
		_come_back(party)
		return false
	var v := _vehicle_of(party)
	if not v.is_empty():
		sim.vehicles.ensure_spot(v)    # (its place may have been taken while it was out)
	party.state = "driving_in"
	party["drive_t"] = 0.0
	party["drive_len"] = _drive_minutes(Convoy.route(_spot_of(party), "in"))
	party["aboard"] = aboard
	party["unload"] = survivors
	party["unload_wait"] = 0.0
	sim.events.append({"type": "arrive", "vehicle": String(party.vehicle)})
	return true


func _drive_in(party: Dictionary, mins: float) -> void:
	party["drive_t"] = float(party.get("drive_t", 0.0)) + mins
	if float(party.drive_t) < float(party.get("drive_len", 0.0)):
		return
	party["drive_t"] = float(party.get("drive_len", 0.0))
	party.state = "unloading"
	party["unload_wait"] = 0.0
	sim.events.append({"type": "parked", "vehicle": String(party.vehicle)})


## The survivors get out one at a time; when the last door has shut the trip is told. False once it is.
func _unload(party: Dictionary, mins: float) -> bool:
	for e in party.doors.duplicate():
		e["t"] = float(e.t) + mins
		if String(e.dir) == "out" and float(e.t) >= float(e.dur) / 2.0:
			var p = _person(String(e.pid))
			if p != null and _is_through(p, party):
				_alight(p, party, String(e.door))
		if float(e.t) >= float(e.dur):
			party.doors.erase(e)
	var queue: Array = party.get("unload", [])
	party["unload_wait"] = float(party.get("unload_wait", 0.0)) - mins
	while not queue.is_empty() and float(party.unload_wait) <= 0.0:
		var id := String(queue.pop_front())
		party.doors.append({"pid": id, "door": _door_of(party, id), "t": 0.0, "dur": BOARD_MIN, "dir": "out"})
		party["unload_wait"] = UNLOAD_GAP_MIN
	if queue.is_empty() and party.doors.is_empty():
		_come_back(party, true)
		return false
	return true


## A person steps out of the car at their door, facing away from it, and is free.
func _alight(p, party: Dictionary, door: String) -> void:
	var at := Convoy.door_spot(_spot_of(party), _kind_id_of(party), door)
	p.away = null
	p.x = at.x
	p.y = at.y
	p.moving = false
	p.path = []
	p.path_i = 0
	p.target = null
	p.goal_key = ""
	p.drafted = false
	p.order = null
	p.repair = null
	p.facing = "W" if at.x < Convoy.bay(_spot_of(party)).x else "E"
	_clear_stance(p)
	sim.events.append({"type": "alight", "vehicle": String(party.vehicle), "person": String(p.id), "door": door})


## Where a person who is home from the trip stands: at the gate in a row (on foot), at their door (by car).
func _home_point(party: Dictionary, p, i: int, n: int, gate: Vector2) -> Vector2:
	if _by_car(party):
		return _door_at(party, String(p.id))
	return Vector2(gate.x + (float(i) - float(n - 1) / 2.0) * 0.7, gate.y)


## The open doors as plain data (a saved party's): only what is well formed.
func _copy_doors(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for e in raw:
			if e is Dictionary and String(e.get("pid", "")) != "" and ["in", "out"].has(String(e.get("dir", ""))):
				out.append({"pid": String(e.pid), "door": String(e.get("door", "")), "t": float(e.get("t", 0.0)), "dur": maxf(float(e.get("dur", BOARD_MIN)), 0.1), "dir": String(e.dir)})
	return out


## What a saved party by car holds besides the common fields (see `_restore_party`). A save from before round 15 has none of
## it: the seats are the party's order, no door is open, and a party that was "away" drives in when it is due.
func _restore_car(party: Dictionary, entry: Dictionary) -> void:
	var seats := {}
	var raw_seats = entry.get("seats", {})
	if raw_seats is Dictionary:
		for id in raw_seats:
			if party.members.has(String(id)):
				seats[String(id)] = int(raw_seats[id])
	for i in party.members.size():
		var id := String(party.members[i])
		if not seats.has(id):
			var seat: int = i
			while seats.values().has(seat):
				seat += 1
			seats[id] = seat
	party["seats"] = seats
	var doors := _copy_doors(entry.get("doors", []))
	party["doors"] = doors.filter(func(e): return party.members.has(String(e.pid)))
	var state := String(party.state)
	if state == "driving_out" or state == "driving_in" or state == "unloading":
		var route := Convoy.route(_spot_of(party), "in" if state != "driving_out" else "out")
		party["drive_len"] = float(entry.get("drive_len", _drive_minutes(route)))
		party["drive_t"] = clampf(float(entry.get("drive_t", party.drive_len if state == "unloading" else 0.0)), 0.0, float(party.drive_len))
	if state == "driving_in" or state == "unloading":
		var through: Array = entry.get("through", [])
		var aboard := _ids_of(entry.get("aboard", through), party.members)
		party["aboard"] = aboard
		var unload: Array
		if entry.has("unload"):
			unload = _ids_of(entry.unload, party.members)
		else:
			unload = aboard.filter(func(id): return through.has(id) and not party.result.lost.has(id))
		party["unload"] = unload
		party["unload_wait"] = float(entry.get("unload_wait", 0.0))


## The ids of `raw` that are in `members`, as strings, once each.
func _ids_of(raw, members: Array) -> Array:
	var out: Array = []
	if raw is Array:
		for id in raw:
			if members.has(String(id)) and not out.has(String(id)):
				out.append(String(id))
	return out


## "06:30" for an hour of the day.
static func _clock_text(h: float) -> String:
	var total := roundi(h * 60.0)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [total / 60, total % 60]


func _is_due(party: Dictionary) -> bool:
	if bool(party.get("road_live", false)):
		return false    # (the player is driving the road home: the scene says when they are at the gate, `arrive_home`)
	if bool(party.get("night_ok", false)):
		return sim.clock_min >= float(party.return_at)    # (the player brought them to the gate: by day or by night)
	if town_mode and not errands.has(String(party.site)):
		return sim.clock_min >= float(party.return_at) and sim.phase == "day"    # (a party may be out overnight; it comes in by day)
	return sim.clock_min >= float(party.return_at) or sim.phase != "day"


## Settles the trip: the living reappear at the gate (at their doors, for a trip by car), the loot is stored,
## injuries and losses go to the medical module, and the story is told. `unloaded`: the survivors of a trip by car have
## already got out (`_unload`), so they are not put anywhere and are known by `party.aboard`.
func _come_back(party: Dictionary, unloaded: bool = false) -> void:
	var result: Dictionary = party.result
	var gate := gate_center()
	var came: Array = []
	var lost: Array = []
	for id in party.members:
		var p = _person(String(id))
		if p == null:
			continue
		var aboard := _is_through(p, party) or (unloaded and (party.get("aboard", []) as Array).has(String(id)))
		if not aboard:
			continue # never left: still at home
		if p.dead or result.lost.has(id):
			lost.append(p)
		else:
			came.append(p)
	if not unloaded:
		for i in came.size():
			var p = came[i]
			p.away = null
			var at := _home_point(party, p, i, came.size(), gate)
			p.x = at.x
			p.y = at.y
			p.moving = false
			p.path = []
			p.path_i = 0
			p.target = null
			p.goal_key = ""
			p.drafted = false
			p.order = null
			p.repair = null
			_clear_stance(p)
	var brought := {}
	if not came.is_empty():
		for k in STOCKS:
			if result.loot.has(k) and int(result.loot[k]) > 0:
				brought[k] = int(result.loot[k])
				if k == "fuel":
					var found_fuel := int(brought[k])
					var put_fuel := int(roundf(sim.vehicles.add_fuel(float(found_fuel))))
					brought.erase(k)
					if put_fuel > 0:
						brought[k] = put_fuel
					if put_fuel < found_fuel:
						sim.alert("tank-full", "info", "The tank is full", "%d fuel stayed behind" % (found_fuel - put_fuel), gate_center(), RETURN_ALERT_TTL)
				else:
					sim.stock[k] = float(sim.stock.get(k, 0.0)) + float(brought[k])
	for p in came:
		var kind := String(result.hurt.get(p.id, ""))
		if kind != "":
			sim.medical.add_wound(p, kind)
	for p in lost:
		p.away = {"kind": "lost", "site": String(party.site)}
		if not p.dead:
			sim.medical.kill(p, "scavenging")
	if town_mode and not came.is_empty() and not errands.has(String(party.site)):
		_town_return(party, came)
	if String(party.get("vehicle", "")) != "":
		if came.is_empty() and lost.is_empty():
			sim.vehicles.cancel(String(party.vehicle), String(party.site))    # (nobody ever left: it was never gone)
		else:
			sim.vehicles.come_home(String(party.vehicle), int(_site(String(party.site)).get("danger", 0)), result.hurt.size(), came.is_empty())
	if not came.is_empty() or not lost.is_empty():
		_tell(party, came, lost, brought)


func _call_off(party: Dictionary) -> void:
	if String(party.get("vehicle", "")) != "":
		sim.vehicles.cancel(String(party.vehicle), String(party.site))
	var where := _where(String(party.site))
	sim.alert("scav-%d" % int(party.n), "info", "The trip to %s is called off." % where, "Nobody is going out.", gate_center(), DEPART_ALERT_TTL)


func _announce_departure(party: Dictionary) -> void:
	var names: Array = []
	for id in party.members:
		names.append(_first(String(id)))
	var back := "Back by 16:00."
	if town_mode:
		var due: float = fposmod(float(party.return_at) / 60.0 + 7.0, 24.0)
		back = "Back in about %d hours." % maxi(1, roundi((float(party.return_at) - sim.clock_min) / 60.0))
		if float(party.return_at) - sim.clock_min > 14.0 * 60.0 or due < 6.5:
			back = "Back tomorrow, or the day after."
	sim.alert("scav-out-%d" % int(party.n), "info", "%s left for %s." % [_join(names), _where(String(party.site))], back, gate_center(), DEPART_ALERT_TTL)


## The alert and banner for a settled trip.
func _tell(party: Dictionary, came: Array, lost: Array, brought: Dictionary) -> void:
	var where := _where(String(party.site))
	var came_names: Array = []
	for p in came:
		came_names.append(p.first)
	var lost_names: Array = []
	for p in lost:
		lost_names.append(p.first)
	var hurt_lines: Array = []
	for p in came:
		match String(party.result.hurt.get(p.id, "")):
			"bite":
				hurt_lines.append("%s was bitten." % p.first)
			"scratch":
				hurt_lines.append("%s is bleeding." % p.first)
	var text := ""
	var sub := ""
	var level := "info"
	if came.is_empty():
		text = "%s did not come back from %s." % [_join(lost_names), where]
		sub = "Nobody saw what happened."
		level = "danger"
	else:
		text = "%s %s back from %s with %s." % [_join(came_names), "is" if came.size() == 1 else "are", where, _loot_text(brought)]
		for line in hurt_lines:
			text += " " + line
		if not lost.is_empty():
			text += " %s did not come back." % _join(lost_names)
			sub = "We lost someone."
			level = "danger"
		elif not hurt_lines.is_empty():
			sub = "Someone needs bandaging."
			level = "warn"
		else:
			sub = "Everyone is in one piece." if came.size() > 1 else "In one piece."
	var news := _news(party, came)
	if not news.is_empty():
		text += " " + news
	sim.alert("scav-%d" % int(party.n), level, text, sub, gate_center(), RETURN_ALERT_TTL)
	var title := "Back from %s" % where
	var line := _capitalise(_loot_text(brought)) + "."
	if not lost.is_empty():
		title = "%s did not come back" % _join(lost_names)
		if came.is_empty():
			line = "Lost at %s." % where
		else:
			line = "%s %s home with %s." % [_join(came_names), "is" if came.size() == 1 else "are", _loot_text(brought)]
	for hurt_line in hurt_lines:
		line += " " + hurt_line
	if not news.is_empty():
		line += " " + news
	sim.events.append({"type": "banner", "text": title, "sub": line})


## What the trip learned, in a sentence or two (the settlement game only): what the way held (the beats), the
## places it showed, and how a clearing went.
func _news(party: Dictionary, came: Array) -> String:
	if not town_mode or errands.has(String(party.site)) or came.is_empty():
		return ""
	var result: Dictionary = party.result
	var parts: Array = []
	for b in result.get("beats", []):
		parts.append(String(b))
		if parts.size() >= 2:
			break
	var shown: Array = []
	for pid in result.get("reveals", []):
		shown.append(String(sim.town.place(String(pid)).get("name", pid)))
	if not shown.is_empty():
		parts.append("%s %s on the map now." % [_join(shown), "is" if shown.size() == 1 else "are"])
	# what the live road held (round 21)
	var on_the_road := _whole(result.get("road_survivors", 0), 0, MAX_ROAD_SURVIVORS)
	if on_the_road > 0:
		parts.append(("A survivor joined them on the road." if on_the_road == 1 else "%d survivors joined them on the road." % on_the_road))
	for line in _lines_of(result.get("road", [])).slice(0, 2):
		parts.append(String(line))
	if String(party.get("action", "loot")) == "clear":
		var name := String(sim.town.place(String(party.site)).get("name", "the place"))
		parts.append("%s is cleared." % name if bool(result.get("clear", false)) else "They could not turn the dead out of %s." % name)
	return " ".join(parts)


# ------------------------------------------------------------------- the town --

## The town's places as sites (the same shape): a trip's loot, danger and words.
func use_town() -> void:
	town_mode = true
	sites = []
	for p in sim.town.places:
		var loot := {}
		for k in p.loot:
			loot[String(k)] = [int(p.loot[k][0]), int(p.loot[k][1])]
		var extra := {}
		for k in p.extra:
			extra[String(k)] = [float(p.extra[k][0]), int(p.extra[k][1])]
		sites.append({
			"id": String(p.id), "name": String(p.name), "where": String(p.get("where", _where_of(String(p.name)))),
			"blurb": String(p.get("blurb", "")), "danger": int(p.danger), "loot": loot, "extra": extra, "image": String(p.get("image", "")),
		})


## How a place is spoken of when its data gives no `where`: "The pharmacy" is "the pharmacy", a name that is a
## name ("Pell's bakery", "Eastgate clinic") is left as it is.
static func _where_of(name: String) -> String:
	if name.begins_with("The "):
		return "the " + name.trim_prefix("The ").to_lower()
	return name


## The known places, as the board offers them: the site's own fields plus {"loot_hint", "available",
## "note", "state", "hours" (one way), "trip_hours", "kind", "pos", "nest" ({strength} or {}), "survivor"
## (someone is hiding there), "outpost" ({yield, cost} or {}), "garrison" (person ids), "can_claim",
## "actions" (which of "loot", "scout", "clear" make sense now)}.
func _town_sites() -> Array:
	var out: Array = []
	for e in sim.town.known_places():
		var id := String(e.id)
		var s := _site(id)
		if s.is_empty():
			continue
		var d: Dictionary = s.duplicate(true)
		d["loot_hint"] = _hint(s)
		var wait := _days_until_ready(id)
		d["available"] = wait <= 0 and e.state != "claimed"
		if e.state == "claimed":
			d["note"] = "Your outpost."
		elif wait > 0:
			d["note"] = "Picked over. Ready again on day %d." % (_last_raid(id) + PICKED_OVER_DAYS)
		elif _recent_raids(id) > 0:
			d["note"] = "Raided on day %d: less to find." % _last_raid(id)
		else:
			d["note"] = ""
		d["state"] = e.state
		d["hours"] = e.hours
		d["trip_hours"] = sim.town.trip_hours(id)
		d["kind"] = String(e.get("kind", ""))
		d["pos"] = e.pos
		d["nest"] = e.get("nest", {})
		d["survivor"] = bool(e.get("survivor", false)) and not bool(e.get("rescued", false))
		d["outpost"] = e.get("outpost", {})
		d["garrison"] = e.garrison
		d["can_claim"] = sim.town.can_claim(id)
		d["needs_vehicle"] = bool(e.get("needs_vehicle", false))
		d["vehicle_here"] = String(e.get("vehicle", "")) if not bool(sim.town.state.get(id, {}).get("vehicle_taken", false)) else ""
		var actions: Array = []
		var has_loot: bool = not (s.loot as Dictionary).is_empty() or not (s.extra as Dictionary).is_empty()
		if e.state != "claimed" and has_loot:
			actions.append("loot")
		actions.append("scout")
		if e.state == "known" and (int(e.danger) > 0 or int(e.get("nest", {}).get("strength", 0)) > 0):
			actions.append("clear")
		d["actions"] = actions
		out.append(d)
	return out


## Why this party cannot take this action at this place ("" when it can).
func why_not_action(people: Array, place_id: String, action: String, vehicle_id: String = "") -> String:
	var e: Dictionary = sim.town.place(place_id)
	if e.is_empty() or not sim.town.is_known(place_id):
		return "Nobody knows where that is."
	if vehicle_id != "":
		var why_vehicle: String = sim.vehicles.why_not_use(vehicle_id, people.size(), place_id)
		if why_vehicle != "":
			return why_vehicle
	elif bool(e.get("needs_vehicle", false)):
		return "Too far to go on foot: take a vehicle."
	var st: String = sim.town.state_of(place_id)
	for other in parties:
		if String(other.site) == place_id:
			return "A party is already out there."
	if action == "loot" and (_site(place_id).get("loot", {}) as Dictionary).is_empty() and (_site(place_id).get("extra", {}) as Dictionary).is_empty():
		return "There is nothing here to take."
	if action == "loot" and st == "claimed":
		return "It is your outpost: garrison it or leave it be."
	if action == "loot" and _days_until_ready(place_id) > 0:
		return "Picked over."
	if action == "clear":
		if st != "known":
			return "There is nothing left to clear."
		if int(e.danger) <= 0 and sim.town.nest_strength(place_id) <= 0:
			return "There is nothing to clear."
		if sim.town.nest_strength(place_id) > 0 and people.size() < 2:
			return "A nest takes at least two."
	if not ["loot", "scout", "clear"].has(action):
		return "Unknown errand."
	return ""


## The hours a trip of this action takes, there and back (and the search).
func action_hours(place_id: String, action: String, vehicle_id: String = "") -> float:
	var h: float = sim.vehicles.drive_hours(place_id, vehicle_id) if vehicle_id != "" else 2.0 * sim.town.hours_to(place_id)
	return h if action == "scout" else h + sim.town.SEARCH_H + (1.0 if action == "clear" else 0.0)


## Sends the party with the result of a trip that was played (scripts/raid/raid_run.gd: loot, hurt, lost, clear,
## rescue, ammo_used, beats) in place of the dice's: the party is away for the trip's hours as always, and comes home
## with what the player's squad brought. Only loot and clear trips are played. True if it went.
func send_played(people: Array, site_id: String, action: String, vehicle_id: String, played: Dictionary) -> bool:
	if action == "scout" or not town_mode or played.is_empty():
		return false
	return _send_town(people, site_id, action, vehicle_id, played)


## Why a party of `people` cannot set off for this place with this action in this vehicle now ("" when it can): what `send`
## refuses in the settlement game, the hour, the dead at the gate, a party that is already out, nobody free (`why_not`),
## the seats, then the place and the errand (`why_not_action`), then each person (`can_go`). `played`: the player leads it
## (the avatar may go).
func _why_not_town(people: Array, site_id: String, action: String, vehicle_id: String, played: bool = false) -> String:
	var why := _why_not(played)
	if why != "":
		return why
	var most: int = int(sim.vehicles.kind_of(vehicle_id).get("seats", MAX_PARTY_TOWN)) if vehicle_id != "" else MAX_PARTY_TOWN
	if people.is_empty():
		return "Nobody is going."
	if people.size() > maxi(most, 0):
		return "There is room for %d." % maxi(most, 0)
	var why_action := why_not_action(people, site_id, action, vehicle_id)
	if why_action != "":
		return why_action
	if _site(site_id).is_empty():
		return "Nobody knows where that is."
	var ids: Array = []
	for p in people:
		if p == null or not can_go(p, played):
			return "%s cannot go now." % (String(p.first) if p != null else "Someone")
		if ids.has(p.id):
			return "%s is on the list twice." % String(p.first)
		ids.append(p.id)
	return ""


## Makes the party of a trip in the settlement game: its number, its members (and their seats, if it goes by vehicle: the
## vehicle is taken and its fuel burnt), the old estimate of its return, and the orders of its members cleared. It is not
## yet in `parties`: the caller gives it its result and its state. The party is not checked here (`_why_not_town`).
func _open_party(people: Array, site_id: String, action: String, vehicle_id: String) -> Dictionary:
	var ids: Array = []
	for p in people:
		ids.append(p.id)
	trips += 1
	var minutes := action_hours(site_id, action, vehicle_id) * 60.0
	var party := {
		"kind": "party", "n": trips, "members": ids, "site": site_id, "state": "out", "action": action,
		"return_at": snappedf(sim.clock_min + minutes, 1.0), "result": {}, "depart": sim.clock_min, "vehicle": vehicle_id,
	}
	if vehicle_id != "":
		var seats := {}
		for i in ids.size():
			seats[String(ids[i])] = i
		party["seats"] = seats
		party["doors"] = []
		sim.vehicles.take(vehicle_id, site_id)
	for p in people:
		p.drafted = false
		p.order = null
		p.repair = null
		p.target = null
		p.goal_key = ""
	return party


func _send_town(people: Array, site_id: String, action: String, vehicle_id: String = "", played: Dictionary = {}) -> bool:
	if _why_not_town(people, site_id, action, vehicle_id, not played.is_empty()) != "":
		return false
	var party := _open_party(people, site_id, action, vehicle_id)
	if played.is_empty():
		party.result = _decide(party)
	else:
		party.result = _played_result(played, party, people)
		party["played"] = true
		sim.stock.ammo = maxf(0.0, float(sim.stock.ammo) - clampf(float(played.get("ammo_used", 0.0)), 0.0, float(sim.stock.ammo)))
	# what the way met may have held them up (decided already, so a save keeps it)
	party.return_at = snappedf(float(party.return_at) + float(party.result.get("delay_h", 0.0)) * 60.0, 1.0)
	party.result.erase("delay_h")
	parties.append(party)
	if vehicle_id != "" and not played.is_empty():
		_skip_departure(party)    # (the raid screen was the way out)
	return true


# ------------------------------------------------------------- a trip in a place --

## The party the player is playing now (state "in_place"), or {}.
func party_in_place() -> Dictionary:
	for party in parties:
		if String(party.state) == IN_PLACE:
			return party
	return {}


## Whether a trip the player led is out: in its place, or on the road home (finished, not yet at the gate). The player cannot answer
## anything from there: the storyteller's cards wait for them (`Storyteller.card_frozen`).
func player_out() -> bool:
	for party in parties:
		if String(party.state) == IN_PLACE or bool(party.get("played", false)):
			return true
	return false


## The game minutes of the road from the base to a place (and back: the same): half the round trip by this vehicle, the
## way there on foot. The abstract travel until the live drive; a place's scene runs it with `Sim.fast_forward`.
func road_minutes(place_id: String, vehicle_id: String = "") -> float:
	if vehicle_id != "":
		return float(sim.vehicles.drive_hours(place_id, vehicle_id)) / 2.0 * 60.0
	return float(sim.town.hours_to(place_id)) * 60.0


## Why the player cannot begin a played trip to this place now ("" when they can): what `send` refuses (`_why_not_town`:
## the hour, the dead at the gate, nobody free, the seats and the fuel, the place, each person), a scouting trip (it is not
## played), and a second place while one is being played.
func why_not_played(people: Array, place_id: String, action: String = "loot", vehicle_id: String = "") -> String:
	if not town_mode:
		return "There is nowhere to go."
	if action == "scout":
		return "A scouting trip is not played."
	if not party_in_place().is_empty():
		return "A trip is already being played."
	return _why_not_town(people, place_id, action, vehicle_id, true)


## The player's trip begins: the party is made at once, "in_place", and returned ({} when it is refused: `why_not_played`).
## Its people (the avatar may be one) are away from this moment, the vehicle is out and its fuel burnt as `send` does it,
## the place is raided. No result yet and nothing due: `finish_played` ends it. See the header.
func begin_played(people: Array, place_id: String, action: String = "loot", vehicle_id: String = "") -> Dictionary:
	if why_not_played(people, place_id, action, vehicle_id) != "":
		return {}
	var party := _open_party(people, place_id, action, vehicle_id)
	party["state"] = IN_PLACE
	party["played"] = true
	party["result"] = {"loot": {}, "hurt": {}, "lost": []}
	parties.append(party)
	for p in people:
		_go_through(p, party)
	return party


## The player's trip is over: `result` is what the place's scene made of it (see the header: the dice's shape and `hp`,
## `skills`). `party_or_id` is the party `begin_played` returned, or its number. A party that is not in a place (already
## finished, home, a dice's trip, no such number) is left alone.
func finish_played(party_or_id, result: Dictionary = {}) -> void:
	var party := _party_by(party_or_id)
	if party.is_empty() or String(party.state) != IN_PLACE:
		return
	if not _finish_party(party, result):
		_drop_party(party)


## The player drives the road home in a scene (round 21): while this is on the party is never due, so the abstract return does not
## bring it in early or late; the scene ends it with `arrive_home`. Not saved (a load falls back to the abstract return).
func hold_on_road(party_or_id, on: bool) -> void:
	var party := _party_by(party_or_id)
	if party.is_empty():
		return
	if on:
		party["road_live"] = true
	else:
		party.erase("road_live")


## What the road home found, put into the settled result of a played party that is on its way home (`d`: the dice's shape, {hurt,
## lost, loot}, and `hp`, `morale`, `road_survivors`, `road`, `beats`: every key optional). Sanitised as `_played_result` does it:
## only members can be hurt or lost (a bite is worse than a scratch and stays), only real stocks come home, a stock of the
## road and the place together never passes PLAYED_LOOT_MAX. The people lost are dead when the party gets in (`_come_back`). A
## party that is not played, is still in its place (no result yet) or is not found is left alone.
func amend_result(party_or_id, d: Dictionary) -> void:
	var party := _party_by(party_or_id)
	if party.is_empty() or not bool(party.get("played", false)) or String(party.state) == IN_PLACE or d.is_empty():
		return
	var people: Array = []
	var members_ids: Array = []
	for id in party.members:
		var p = _person(String(id))
		if p != null:
			people.append(p)
			members_ids.append(String(p.id))
	var result: Dictionary = party.result
	var found_loot = d.get("loot", {})
	if found_loot is Dictionary:
		var loot: Dictionary = result.get("loot", {})
		for k in STOCKS:
			if found_loot.has(k) and _is_number(found_loot[k]) and int(found_loot[k]) > 0:
				loot[k] = mini(int(loot.get(k, 0)) + mini(int(found_loot[k]), PLAYED_LOOT_MAX), PLAYED_LOOT_MAX)
		result["loot"] = loot
	var found_hurt = d.get("hurt", {})
	if found_hurt is Dictionary:
		var hurt: Dictionary = result.get("hurt", {})
		for pid in found_hurt:
			if members_ids.has(String(pid)) and String(hurt.get(String(pid), "")) != "bite":
				hurt[String(pid)] = "bite" if String(found_hurt[pid]) != "scratch" else "scratch"
		result["hurt"] = hurt
	var found_lost = d.get("lost", [])
	if found_lost is Array:
		var lost: Array = result.get("lost", [])
		for pid in found_lost:
			if members_ids.has(String(pid)) and not lost.has(String(pid)):
				lost.append(String(pid))
		result["lost"] = lost
	_apply_played_state(people, d, result)
	if _is_number(d.get("morale", 0.0)) and float(d.get("morale", 0.0)) != 0.0:
		result["morale"] = clampf(float(result.get("morale", 0.0)) + float(d.morale), -MAX_ROAD_MORALE, MAX_ROAD_MORALE)
	var more := _whole(d.get("road_survivors", 0), 0, MAX_ROAD_SURVIVORS)
	if more > 0:
		result["road_survivors"] = mini(_whole(result.get("road_survivors", 0), 0, MAX_ROAD_SURVIVORS) + more, MAX_ROAD_SURVIVORS)
	for key in ["road", "beats"]:
		var add := _lines_of(d.get(key, []))
		if not add.is_empty():
			var all: Array = (result.get(key, []) as Array).duplicate()
			all.append_array(add)
			result[key] = all.slice(maxi(0, all.size() - MAX_ROAD_LINES))


## The party is at the gate (the scene's road home is over): it is due at once, by day or by night (the player brought them,
## `night_ok`: the gate is still only a picture), and comes in as any trip does (a car drives in and parks, a party on foot walks
## in). The road is no longer held.
func arrive_home(party_or_id) -> void:
	var party := _party_by(party_or_id)
	if party.is_empty():
		return
	party.erase("road_live")
	if String(party.state) == IN_PLACE:
		return    # (still in the place: there is no road to have come home by)
	party["return_at"] = floorf(float(sim.clock_min))
	party["night_ok"] = true


static func _whole(v, lo: int, hi: int) -> int:
	return clampi(int(v), lo, hi) if _is_number(v) else lo


## Up to MAX_ROAD_LINES lines of text (a list of anything: each is a string, none empty).
static func _lines_of(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for v in raw:
			var s := String(v).strip_edges()
			if s != "" and out.size() < MAX_ROAD_LINES:
				out.append(s)
	return out


## Settles the end of a party's time in a place: puts the sanitised result in, applies what the place did to the members,
## and sets the party on the road home. False if the party is done with (nobody of it is coming home: it is told and
## the vehicle dealt with at once), so that the caller takes it out of `parties`.
func _finish_party(party: Dictionary, played: Dictionary) -> bool:
	var people: Array = []
	for id in party.members:
		var p = _person(String(id))
		if p != null:
			people.append(p)
	var result := _played_result(played, party, people)
	party["result"] = result
	party.erase("orphan")
	_apply_played_state(people, played, result)
	sim.stock.ammo = maxf(0.0, float(sim.stock.ammo) - clampf(float(played.get("ammo_used", 0.0)), 0.0, float(sim.stock.ammo)))
	var coming := false
	for p in people:
		if not p.dead and not (result.lost as Array).has(String(p.id)):
			coming = true
	if not coming:
		_come_back(party)
		return false
	party["state"] = "away"
	party["return_at"] = snappedf(sim.clock_min + road_minutes(String(party.site), String(party.get("vehicle", ""))), 1.0)
	return true


## What the place did to those who come home: their health as they left it and the skills they gained there (the result's
## `hp` and `skills`; a missing key or a name that is not a member's changes nothing; a gain is at most what a run can give,
## `Skills.MAX_GAIN`, within the skill's cap, and Leading does not grow).
func _apply_played_state(people: Array, played: Dictionary, result: Dictionary) -> void:
	var hp = played.get("hp", {})
	var gains = played.get("skills", {})
	for p in people:
		if p.dead or (result.lost as Array).has(String(p.id)):
			continue
		if hp is Dictionary and hp.has(String(p.id)) and _is_number(hp[String(p.id)]):
			p.hp = clampf(float(hp[String(p.id)]), 1.0, PLAYED_HP_MAX)
		var row = gains.get(String(p.id), {}) if gains is Dictionary else {}
		if not row is Dictionary:
			continue
		for k in row:
			var skill := String(k)
			if not sim.skills.SKILLS.has(skill) or sim.skills.NO_GROWTH.has(skill) or not _is_number(row[k]):
				continue
			var now := int(p.skills.get(skill, 0))
			var to := maxi(now, mini(int(sim.skills.cap_of(p, skill)), now + clampi(int(row[k]), 0, int(sim.skills.MAX_GAIN))))
			if to > now:
				p.skills[skill] = to
				sim.skills._announce(p, skill, to)


static func _is_number(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


## The party with this number (or the one given, found again by its number), or {}.
func _party_by(party_or_id) -> Dictionary:
	var n := -1
	if party_or_id is Dictionary:
		n = int(party_or_id.get("n", -1))
	elif typeof(party_or_id) == TYPE_INT or typeof(party_or_id) == TYPE_FLOAT:
		n = int(party_or_id)
	elif typeof(party_or_id) == TYPE_STRING and String(party_or_id).is_valid_int():
		n = int(String(party_or_id))
	for party in parties:
		if int(party.n) == n:
			return party
	return {}


func _drop_party(party: Dictionary) -> void:
	for i in parties.size():
		if is_same(parties[i], party):
			parties.remove_at(i)
			return


## A played trip's result in the shape the return reads (see `_decide_town`): its loot, wounds and losses, a cleared
## nest or a rescue; the vehicle a place holds is a die thrown here, as for the dice's trips.
func _played_result(played: Dictionary, party: Dictionary, people: Array) -> Dictionary:
	var id := String(party.site)
	var members_ids: Array = []
	for p in people:
		members_ids.append(String(p.id))
	var loot := {}
	for k in STOCKS:
		if played.get("loot", {}).has(k) and int(played.loot[k]) > 0:
			loot[k] = mini(int(played.loot[k]), PLAYED_LOOT_MAX)
	var hurt := {}
	for pid in played.get("hurt", {}):
		if members_ids.has(String(pid)):
			hurt[String(pid)] = "bite" if String(played.hurt[pid]) != "scratch" else "scratch"
	var lost: Array = []
	for pid in played.get("lost", []):
		if members_ids.has(String(pid)) and not lost.has(String(pid)):
			lost.append(String(pid))
	var result := {"loot": loot, "hurt": hurt, "lost": lost}
	if bool(played.get("clear", false)):
		result["clear"] = true
	if bool(played.get("rescue", false)):
		result["rescue"] = true
	var beats: Array = []
	for b in played.get("beats", []):
		beats.append(String(b))
	if not beats.is_empty():
		result["beats"] = beats
	# what the road there held (the live drive, round 21; a place's own result has none of these)
	var road_survivors := _whole(played.get("road_survivors", 0), 0, MAX_ROAD_SURVIVORS)
	if road_survivors > 0:
		result["road_survivors"] = road_survivors
	if _is_number(played.get("morale", 0.0)) and float(played.get("morale", 0.0)) != 0.0:
		result["morale"] = clampf(float(played.morale), -MAX_ROAD_MORALE, MAX_ROAD_MORALE)
	var road_lines := _lines_of(played.get("road", []))
	if not road_lines.is_empty():
		result["road"] = road_lines
	var place: Dictionary = sim.town.place(id)
	if not played.is_empty() and String(place.get("vehicle", "")) != "" and not bool(sim.town.state.get(id, {}).get("vehicle_taken", false)) and lost.size() < people.size() and (String(party.get("action", "loot")) == "loot" or bool(played.get("clear", false))):
		var building_total := 0.0
		for p in people:
			building_total += float(p.skills.Building)
		if sim.rng.randf() < sim.vehicles.start_chance(building_total):
			result["vehicle"] = String(place.vehicle)
	return result


## The chance that this party clears this place, as the rules throw it: 0.35 plus 0.08 for each point of Shooting,
## less 0.12 for each point of danger and nest (none once it is cleared), kept between 0.1 and 0.95.
func clear_chance(people: Array, place_id: String) -> float:
	var shooting := 0.0
	for p in people:
		shooting += float(p.skills.Shooting)
	var cleared: bool = sim.town.state_of(place_id) == "cleared"
	var danger := 0 if cleared else int(_site(place_id).get("danger", 0))
	var nest: int = 0 if cleared else sim.town.nest_strength(place_id)
	return clampf(0.35 + 0.08 * shooting - 0.12 * float(danger + nest), 0.1, 0.95)


## The extras of a trip's end in the settlement game: the places shown, a nest gone, a survivor home, the
## road's effect on the mood.
func _town_return(party: Dictionary, came: Array) -> void:
	var result: Dictionary = party.result
	var id := String(party.site)
	for pid in result.get("reveals", []):
		sim.town.reveal(String(pid))
	if bool(result.get("clear", false)):
		sim.town.mark_cleared(id)
	var morale := float(result.get("morale", 0.0))
	if morale != 0.0:
		for p in came:
			sim.morale.shock(p, morale, "On the road")
	if bool(result.get("rescue", false)) and not bool(sim.town.state.get(id, {}).get("rescued", false)):
		sim.recruits.rescue_home(id)
	# the survivors the squad took in on the road (round 21): each joins the crew while there is a bed, else stays a caller
	for _i in _whole(result.get("road_survivors", 0), 0, MAX_ROAD_SURVIVORS):
		if sim.recruits.housing_free() >= 1 and not sim.recruits.current_caller().is_empty():
			sim.recruits.rescue_home("road")
		elif sim.recruits.small:
			sim.alert("no-bed-road", "warn", "A survivor met on the road could not come in", "There is no bed for them yet", null, RETURN_ALERT_TTL)
	var found_kind := String(result.get("vehicle", ""))
	if found_kind != "" and sim.town.state.has(id) and not bool(sim.town.state[id].get("vehicle_taken", false)):
		sim.town.state[id]["vehicle_taken"] = true
		var v: Dictionary = sim.vehicles.add(found_kind)
		if not v.is_empty():
			sim.alert("vehicle-found-%s" % id, "info", "A %s is home" % String(sim.vehicles.kind(found_kind).name).to_lower(), "They got it running at %s and drove it back" % _where(id), gate_center(), RETURN_ALERT_TTL)


# -------------------------------------------------------------- the dice roll --

## Rolls the whole result of a trip from the rules' dice: what is brought, who is
## hurt and who is lost. Three dice are thrown for every member whatever comes
## up, so a run's dice stay in step.
func _decide(party: Dictionary) -> Dictionary:
	if town_mode and not errands.has(String(party.site)):
		return _decide_town(party)
	var site := _site(String(party.site))
	if site.is_empty():
		return {"loot": {}, "hurt": {}, "lost": []} # a site that is not in the data (a damaged save)
	var members: Array = []
	for id in party.members:
		var p = _person(String(id))
		if p != null:
			members.append(p)
	var scale := loot_scale(String(party.site), members)
	var found := {}
	for k in STOCKS:
		if site.loot.has(k):
			var span: Array = site.loot[k]
			var base: int = sim.rng.randi_range(int(span[0]), int(span[1]))
			found[k] = roundi(base * scale)
	for k in STOCKS:
		if site.extra.has(k):
			var pair: Array = site.extra[k]
			var luck: float = sim.rng.randf()
			if luck < float(pair[0]):
				found[k] = int(found.get(k, 0)) + roundi(float(pair[1]) * scale)
	var mult: float = DANGER_MULT[clampi(int(sim.difficulty), 0, DANGER_MULT.size() - 1)]
	var danger := int(site.danger)
	var hurt := {}
	var lost: Array = []
	for p in members:
		var roll_loss: float = sim.rng.randf()
		var roll_wound: float = sim.rng.randf()
		var roll_kind: float = sim.rng.randf()
		if danger >= LOSS_MIN_DANGER and roll_loss < LOSS_BASE * mult:
			lost.append(p.id)
			continue
		var shooting := float(p.skills.Shooting)
		if roll_wound < WOUND_BASE * danger * mult * (1.0 - shooting / 15.0):
			hurt[p.id] = "bite" if roll_kind < BITE_SHARE else "scratch"
	var loot := {}
	if lost.size() < members.size():
		for k in STOCKS:
			if int(found.get(k, 0)) > 0:
				loot[k] = int(found[k])
	return {"loot": loot, "hurt": hurt, "lost": lost}


## The settlement game's version of the dice: the same dice as the classic trip for the loot, the wounds and
## the losses (so a trip is as dangerous as ever, scaled by the place's danger and nest), and more: the
## clearing, a survivor found, the places a scouting trip shows, and the beats of the way (the town's
## data), each thrown whatever comes up so that a run's dice stay in step.
func _decide_town(party: Dictionary) -> Dictionary:
	var id := String(party.site)
	var site := _site(id)
	if site.is_empty():
		return {"loot": {}, "hurt": {}, "lost": []}
	var action := String(party.get("action", "loot"))
	var place: Dictionary = sim.town.place(id)
	var members: Array = []
	for mid in party.members:
		var p = _person(String(mid))
		if p != null:
			members.append(p)
	var cleared: bool = sim.town.state_of(id) == "cleared"
	var vehicle_id := String(party.get("vehicle", ""))
	var scale := loot_scale(id, members)
	if vehicle_id != "":
		scale *= float(sim.vehicles.kind_of(vehicle_id).get("cargo", 1.0))
	var found := {}
	for k in STOCKS:
		if site.loot.has(k):
			var span: Array = site.loot[k]
			found[k] = roundi(sim.rng.randi_range(int(span[0]), int(span[1])) * scale)
	for k in STOCKS:
		if site.extra.has(k):
			var pair: Array = site.extra[k]
			if sim.rng.randf() < float(pair[0]):
				found[k] = int(found.get(k, 0)) + roundi(float(pair[1]) * scale)
	var danger := 0 if cleared else int(site.danger)
	var nest: int = 0 if cleared else sim.town.nest_strength(id)
	var effective := float(danger + nest)
	if action == "clear":
		effective *= 2.0
	elif action == "scout":
		effective *= 0.5
	var roll_clear: float = sim.rng.randf()
	var clear_ok := false
	if action == "clear":
		clear_ok = roll_clear < clear_chance(members, id)
	var mult: float = DANGER_MULT[clampi(int(sim.difficulty), 0, DANGER_MULT.size() - 1)]
	var hurt := {}
	var lost: Array = []
	var night_out: bool = float(sim.hour) + action_hours(id, action, vehicle_id) >= float(sim.seasons.dusk_hour())
	for p in members:
		var roll_loss: float = sim.rng.randf()
		var roll_wound: float = sim.rng.randf()
		var roll_kind: float = sim.rng.randf()
		if effective >= float(LOSS_MIN_DANGER) and roll_loss < LOSS_BASE * mult * (effective / 2.0):
			lost.append(p.id)
			continue
		var wound_p: float = (WOUND_BASE * effective * mult + (NIGHT_OUT_WOUND * mult if night_out else 0.0)) * (1.0 - float(p.skills.Shooting) / 15.0)
		if action == "clear" and not clear_ok:
			wound_p = minf(0.95, wound_p * 2.5)
		if roll_wound < wound_p:
			hurt[p.id] = "bite" if roll_kind < BITE_SHARE else "scratch"
	var roll_rescue: float = sim.rng.randf()
	var rescue := bool(place.get("survivor", false)) and not bool(sim.town.state.get(id, {}).get("rescued", false)) and (clear_ok or cleared or (action == "loot" and roll_rescue < 0.5))
	if action == "scout":
		rescue = false
	# the way: a beat or none for each stretch of it
	var hours: float = action_hours(id, action, vehicle_id)
	var slots := 1 + int((sim.town.hours_to(id) / float(sim.vehicles.kind_of(vehicle_id).get("speed", 1.0))) / 2.5)
	var eligible: Array = []
	var total := 0.0
	for b in sim.town.beats():
		if float(b.get("min_hours", 0.0)) <= hours:
			eligible.append(b)
			total += float(b.get("weight", 1.0))
	var texts: Array = []
	var reveals: Array = []
	var loot_pct := 0.0
	var delay := 0.0
	var morale := 0.0
	for i in slots:
		var roll_slot: float = sim.rng.randf()
		var roll_pick: float = sim.rng.randf()
		var roll_who: float = sim.rng.randf()
		if eligible.is_empty() or roll_slot >= BEAT_CHANCE or members.is_empty():
			continue
		var at := roll_pick * total
		var beat: Dictionary = eligible[eligible.size() - 1]
		for b in eligible:
			at -= float(b.get("weight", 1.0))
			if at < 0.0:
				beat = b
				break
		texts.append(String(beat.text))
		var fx: Dictionary = beat.get("effects", {})
		loot_pct += float(fx.get("loot_pct", 0.0))
		delay += float(fx.get("delay_h", 0.0))
		morale += float(fx.get("morale", 0.0))
		var who = members[int(roll_who * float(members.size())) % members.size()]
		if fx.has("hurt") and not lost.has(who.id) and not hurt.has(who.id):
			hurt[who.id] = String(fx.hurt)
		if bool(fx.get("lost", false)) and not lost.has(who.id) and lost.size() < members.size() - 1:
			lost.append(who.id)
		if String(fx.get("reveal", "")) == "near":
			var nearest := ""
			var best_d := 1.0e9
			for q in sim.town.places:
				var qid := String(q.id)
				if sim.town.state_of(qid) == "unknown" and not reveals.has(qid):
					var d: float = Vector2(q.pos).distance_to(place.pos)
					if d < best_d:
						best_d = d
						nearest = qid
			if nearest != "":
				reveals.append(nearest)
	if action == "scout":
		for q in sim.town.places:
			var qid := String(q.id)
			if sim.town.state_of(qid) == "unknown" and not reveals.has(qid) and Vector2(q.pos).distance_to(place.pos) <= sim.town.SCOUT_RADIUS:
				reveals.append(qid)
	var loot := {}
	var gave := action == "loot" or (action == "clear" and clear_ok)
	if gave and lost.size() < members.size():
		for k in STOCKS:
			var amount := roundi(float(found.get(k, 0)) * maxf(0.2, 1.0 + loot_pct / 100.0))
			if amount > 0:
				loot[k] = amount
	var result := {"loot": loot, "hurt": hurt, "lost": lost}
	if clear_ok:
		result["clear"] = true
	# a place that holds a vehicle: the party that comes home may have got it running (one more die, only for such a place)
	if String(place.get("vehicle", "")) != "" and not bool(sim.town.state.get(id, {}).get("vehicle_taken", false)) and (action == "loot" or (action == "clear" and clear_ok)) and lost.size() < members.size():
		var building_total := 0.0
		for p in members:
			building_total += float(p.skills.Building)
		if sim.rng.randf() < sim.vehicles.start_chance(building_total):
			result["vehicle"] = String(place.vehicle)
	if rescue and lost.size() < members.size():
		result["rescue"] = true
	if not texts.is_empty():
		result["beats"] = texts
	if not reveals.is_empty():
		result["reveals"] = reveals
	if morale != 0.0:
		result["morale"] = clampf(morale, -8.0, 8.0)
	if delay > 0.0:
		result["delay_h"] = delay
	return result


# ------------------------------------------------------------------- raids --

func _record_raid(site_id: String) -> void:
	if not raids.has(site_id):
		raids[site_id] = []
	var days: Array = raids[site_id]
	days.append(sim.day)
	while days.size() > 6:
		days.pop_front()


func _last_raid(site_id: String) -> int:
	var last := -1
	for d in raids.get(site_id, []):
		last = maxi(last, int(d))
	return last


## Raids of the site within the last RAID_MEMORY_DAYS days (today counts).
func _recent_raids(site_id: String) -> int:
	var n := 0
	for d in raids.get(site_id, []):
		if int(d) <= sim.day and sim.day - int(d) <= RAID_MEMORY_DAYS:
			n += 1
	return n


## Days still to wait before the site reopens (0 or less when it is open).
func _days_until_ready(site_id: String) -> int:
	var last := _last_raid(site_id)
	if last < 0:
		return 0
	return last + PICKED_OVER_DAYS - sim.day


# ------------------------------------------------------------------- helpers --

func _party_of(p):
	for party in parties:
		if party.members.has(p.id):
			return party
	return null


## Whether `p` is off the map with this party.
func _is_through(p, party: Dictionary) -> bool:
	return p.away is Dictionary and p.away.get("kind", "") == "party" and int(p.away.get("n", -1)) == int(party.n)


func _any_through(party: Dictionary) -> bool:
	for id in party.members:
		var p = _person(String(id))
		if p != null and _is_through(p, party):
			return true
	return false


func _all_through(party: Dictionary) -> bool:
	for id in party.members:
		var p = _person(String(id))
		if p == null or not _is_through(p, party):
			return false
	return true


func _person(id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _first(id: String) -> String:
	var p = _person(id)
	return String(p.first) if p != null else id


## Whether an errand of the storyteller's (a site in `errands`) may go out now: by day and at
## least an hour before the parties are due back, whatever else is out, unless too many of the
## dead stand at the gate.
func _errand_ok(site_id: String) -> bool:
	return errands.has(site_id) and sim.over == "" and sim.phase == "day" and sim.hour < RETURN_H - 1.0 and dead_at_gate() < DEAD_LIMIT


func _site(id: String) -> Dictionary:
	for s in sites:
		if s.id == id:
			return s
	return errands.get(id, {})


## "the pharmacy": how the site reads in a sentence.
func _where(site_id: String) -> String:
	return String(_site(site_id).get("where", "the site"))


## "meds" or "scrap and ammo" or "food, water and meds".
func _join(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


## "14 scrap and 35 ammo", "1 med", or "nothing".
func _loot_text(brought: Dictionary) -> String:
	var parts: Array = []
	for k in STOCKS:
		if brought.has(k):
			var n: int = brought[k]
			parts.append("%d %s" % [n, "med" if k == "meds" and n == 1 else k])
	return _join(parts) if not parts.is_empty() else "nothing"


## What a site is good for, for the dialog: "Scrap and ammo", "Meds, sometimes food".
func _hint(site: Dictionary) -> String:
	var main: Array = []
	var sometimes: Array = []
	for k in STOCKS:
		if site.loot.has(k):
			main.append(k)
		if site.extra.has(k):
			sometimes.append(k)
	var text := _join(main)
	if not sometimes.is_empty():
		text += ", sometimes " + _join(sometimes)
	return _capitalise(text)


func _capitalise(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


func _load_sites() -> void:
	sites = []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(sites_path))
	var list = parsed.get("sites", []) if parsed is Dictionary else parsed
	if not list is Array:
		push_error("Could not read the scavenging sites from %s" % sites_path)
		return
	for raw in list:
		var loot := {}
		for k in raw.get("loot", {}):
			loot[String(k)] = [int(raw.loot[k][0]), int(raw.loot[k][1])]
		var extra := {}
		for k in raw.get("extra", {}):
			extra[String(k)] = [float(raw.extra[k][0]), int(raw.extra[k][1])]
		sites.append({
			"id": String(raw.id),
			"name": String(raw.name),
			"where": String(raw.get("where", String(raw.name).to_lower())),
			"blurb": String(raw.get("blurb", "")),
			"danger": int(raw.get("danger", 1)),
			"loot": loot,
			"extra": extra,
			"image": String(raw.get("image", "")),
		})
