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
##            "site": site id, "state": "out" | "away", "return_at": clock_min,
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
## Events: only the rules' own "banner" events.
extends RefCounted

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
const STOCKS := ["food", "water", "scrap", "ammo", "meds"]
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


func setup(s) -> void:
	sim = s
	_load_sites()


func start() -> void:
	parties.clear()
	raids.clear()
	trips = 0
	errands.clear()


## Every step: parties walking to the gate, away, and coming back.
func update(_dt: float) -> void:
	if parties.is_empty():
		return
	var keep: Array = []
	for party in parties:
		var open := true
		if party.state == "out":
			open = _walk_out(party)
		if open and _is_due(party):
			_come_back(party)
			open = false
		if open:
			keep.append(party)
	parties = keep


## A goal for a party member walking to the gate, or null (once they are back
## the rules walk them to their post or job as usual).
func goal_for(p):
	var party = _party_of(p)
	if party == null or party.state != "out" or _is_through(p, party):
		return null
	var gate := gate_center()
	return {"x": gate.x, "y": gate.y, "face": "N", "what": "Heading for the gate"}


## Whether a trip can be sent now (daytime departure window, nobody out
## already, not too many of the dead at the gate, someone free), and why not if
## it cannot.
func can_send() -> bool:
	return why_not() == ""


func why_not() -> String:
	if sim.over != "":
		return "The run is over."
	if sim.phase == "dusk" or sim.phase == "night":
		return "Nobody goes out after dark."
	if sim.phase == "dawn" or sim.hour < SEND_FROM_H:
		return "Too early: wait for daylight (06:30)."
	if sim.hour >= SEND_TO_H:
		return "Too late: parties leave between 06:30 and 10:00."
	if not parties.is_empty():
		return "A party is already out."
	if dead_at_gate() >= DEAD_LIMIT:
		return "Too many of the dead at the gate."
	if free_survivors().is_empty():
		return "Nobody is free to go."
	return ""


## The sites the player may pick now, each with its current state: the site's
## own fields plus {"loot_hint", "available", "note"}. A raided site is not
## available ("picked over") until it reopens.
func available_sites() -> Array:
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
func send(people: Array, site_id: String) -> bool:
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
	var tip := "Away scavenging" if _is_through(p, party) else "Heading out to scavenge"
	return [{"icon": "away", "color": AWAY_COLOR, "tip": tip}]


## The HUD's "Scavenge" button opens a dialog (which then calls send), so the
## rules take no part.
func gizmo(_id: String, _sel) -> bool:
	return false


# ------------------------------------------------------------ for the dialog --

## Whether `p` can be put in a party now: alive, on the map, on their feet, not
## drafted with an order, not already out, not busy treating someone or leaving
## through the gate, not delirious with fever.
func can_go(p) -> bool:
	if p == null or p.dead or p.downed or p.away != null or sim.morale.breakdown(p):
		return false
	if p.drafted or p.order != null:
		return false
	if _party_of(p) != null or sim.medical.goal_for(p) != null:
		return false
	return sim.medical.infection_stage(p) != "delirious"


## The survivors who can be sent now, in crew order.
func free_survivors() -> Array:
	var out: Array = []
	for p in sim.people:
		if can_go(p):
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
		saved.append({
			"n": int(party.n),
			"members": party.members.duplicate(),
			"through": through,
			"site": String(party.site),
			"state": String(party.state),
			"return_at": float(party.return_at),
			"result": _copy_result(party.result),
		})
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
	return {"loot": loot, "hurt": hurt, "lost": lost}


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
	if dropped and not someone_was_through:
		# nobody has left yet, so the trip is simply a smaller one
		party.result = _decide(party)
	if _all_through(party):
		party.state = "away"
		_announce_departure(party)
	return true


## Whether a member who has not yet reached the gate is still going there.
func _is_heading_out(p) -> bool:
	return not p.dead and not p.downed and not p.drafted and p.order == null and p.repair == null


func _go_through(p, party: Dictionary) -> void:
	if not _any_through(party):
		_record_raid(String(party.site))
	p.away = party
	p.moving = false
	p.path = []
	p.path_i = 0
	p.target = null
	p.goal_key = ""
	p.activity = "Scavenging at %s" % _where(String(party.site))


func _is_due(party: Dictionary) -> bool:
	return sim.clock_min >= float(party.return_at) or sim.phase != "day"


## Settles the trip: the living reappear at the gate, the loot is stored,
## injuries and losses go to the medical module, and the story is told.
func _come_back(party: Dictionary) -> void:
	var result: Dictionary = party.result
	var gate := gate_center()
	var came: Array = []
	var lost: Array = []
	for id in party.members:
		var p = _person(String(id))
		if p == null or not _is_through(p, party):
			continue # never left: still at home
		if p.dead or result.lost.has(id):
			lost.append(p)
		else:
			came.append(p)
	for i in came.size():
		var p = came[i]
		p.away = null
		p.x = gate.x + (float(i) - float(came.size() - 1) / 2.0) * 0.7
		p.y = gate.y
		p.moving = false
		p.path = []
		p.path_i = 0
		p.target = null
		p.goal_key = ""
		p.drafted = false
		p.order = null
		p.repair = null
	var brought := {}
	if not came.is_empty():
		for k in STOCKS:
			if result.loot.has(k) and int(result.loot[k]) > 0:
				brought[k] = int(result.loot[k])
				sim.stock[k] = float(sim.stock.get(k, 0.0)) + float(brought[k])
	for p in came:
		var kind := String(result.hurt.get(p.id, ""))
		if kind != "":
			sim.medical.add_wound(p, kind)
	for p in lost:
		p.away = {"kind": "lost", "site": String(party.site)}
		if not p.dead:
			sim.medical.kill(p, "scavenging")
	if not came.is_empty() or not lost.is_empty():
		_tell(party, came, lost, brought)


func _call_off(party: Dictionary) -> void:
	var where := _where(String(party.site))
	sim.alert("scav-%d" % int(party.n), "info", "The trip to %s is called off." % where, "Nobody is going out.", gate_center(), DEPART_ALERT_TTL)


func _announce_departure(party: Dictionary) -> void:
	var names: Array = []
	for id in party.members:
		names.append(_first(String(id)))
	sim.alert("scav-out-%d" % int(party.n), "info", "%s left for %s." % [_join(names), _where(String(party.site))], "Back by 16:00.", gate_center(), DEPART_ALERT_TTL)


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
	sim.events.append({"type": "banner", "text": title, "sub": line})


# -------------------------------------------------------------- the dice roll --

## Rolls the whole result of a trip from the rules' dice: what is brought, who is
## hurt and who is lost. Three dice are thrown for every member whatever comes
## up, so a run's dice stay in step.
func _decide(party: Dictionary) -> Dictionary:
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
