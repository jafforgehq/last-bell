## The crew load (round 16): how many of the colony's job seats are staffed, and what the empty ones cost. A seat is staffed by
## someone assigned to its station who is here (not away on a trip) and up (not down); a station counts only while the colony
## has it (the salvage bench once it stands), with the seats its buildings give. Nothing here changes the rules: the HUD's
## strip ("Seats 5 of 11", scripts/ui/hud.gd) and the Town Board's warning (scripts/ui/town_board.gd) read it.
##
## The empty seats are told in the order of what they cost: the radio desk (no noon news, no stranger's call) and the lookout
## post (no forecast) first, then the builders, the workbench, the infirmary, the beds and the salvage bench. The level is
## "calm" while the radio desk and the lookout post are staffed and "warn" when one is not (amber in the strip; never an alarm).
extends RefCounted

## The stations in the order of what an empty one costs you.
const ORDER := ["radio", "watch", "builders", "bench", "infirmary", "garden", "salvage"]
## The stations whose empty seat makes the strip amber.
const IMPORTANT := ["radio", "watch"]
## What it costs when nobody sits there ("none") and when only some of the seats are staffed ("some").
const COSTS := {
	"watch": {"none": "no forecast at dusk", "some": "no forecast at dusk"},
	"builders": {"none": "walls and building wait", "some": "walls and building go slower"},
	"bench": {"none": "no ammo is made", "some": "ammo comes slower"},
	"infirmary": {"none": "the hurt wait for treatment", "some": "treatment is slower"},
	"garden": {"none": "no food is grown", "some": "less food is grown"},
	"salvage": {"none": "no scrap from the junk", "some": "less scrap from the junk"},
}
## A trip says how many stay home to hold the yard when this few or fewer do.
const THIN := 2
## The tooltip's last line.
const ROSTER_LINE := "Click for the Duty roster (J)"


## Whether this person is on a trip: away (through the gate) or still walking to it with their party.
static func on_trip(sim, p) -> bool:
	if p.away != null:
		return true
	var scav = sim.get("scavenge")
	if scav != null and scav.get("parties") is Array:
		for party in scav.parties:
			if party.get("members") is Array and party.members.has(p.id):
				return true
	return false


## The people at a station who are here and up, leaving out those in `leaving` (a party that is about to go).
static func staffed_in(sim, id: String, leaving: Array = []) -> Array:
	var out: Array = []
	for p in sim.jobs.crew_of(id):
		if not on_trip(sim, p) and not p.downed and not leaving.has(p):
			out.append(p)
	return out


## The first names of those assigned to a station who are away on a trip.
static func away_in(sim, id: String) -> Array:
	var out: Array = []
	for p in sim.jobs.crew_of(id):
		if on_trip(sim, p):
			out.append(String(p.first))
	return out


## The stations the colony has now, in the order of what an empty one costs.
static func _ids(sim) -> Array:
	var have: Array = []
	for st in sim.jobs.stations():
		have.append(String(st.id))
	var out: Array = []
	for id in ORDER:
		if have.has(id):
			out.append(id)
	for id in have:
		if not out.has(id):
			out.append(id)
	return out


## What an empty seat at this station costs, in words (`staffed`: how many of its seats have someone).
static func cost_of(sim, id: String, staffed: int) -> String:
	if id == "radio":
		var recruits = sim.get("recruits")
		if recruits != null and recruits.small:
			return "no news at noon; the next survivor will still call" if recruits.call_guaranteed() else "no news at noon, and no call from a stranger"
		return "no news at noon"
	var c: Dictionary = COSTS.get(id, {"none": "its work is not done", "some": "its work goes slower"})
	return String(c.some if staffed > 0 else c.none)


## {"seats", "staffed", "text" ("Seats 5 of 11"), "short" ("5/11"), "level" ("calm" or "warn"), "empty": [{"id", "name", "seats",
## "staffed", "missing", "away" (first names), "cost"}] (the stations with a seat that nobody holds, in the order of what it
## costs), "tip": the tooltip}.
static func report(sim) -> Dictionary:
	var seats := 0
	var staffed := 0
	var empty: Array = []
	var level := "calm"
	for id in _ids(sim):
		var n: int = sim.jobs.seats_of(id)
		var held := mini(staffed_in(sim, id).size(), n)
		seats += n
		staffed += held
		if held == 0 and IMPORTANT.has(id):
			level = "warn"
		if held < n:
			empty.append({
				"id": id, "name": String(sim.jobs.station(id).get("name", id)), "seats": n, "staffed": held, "missing": n - held,
				"away": away_in(sim, id), "cost": cost_of(sim, id, held),
			})
	var lines: Array = ["Seats staffed: %d of %d" % [staffed, seats]]
	if empty.is_empty():
		lines.append("Every seat has someone in it.")
	else:
		lines.append("Empty, the ones you miss most first:")
		for e in empty:
			var who := ""
			if not e.away.is_empty():
				who = " (%s %s away)" % [" and ".join(e.away), "is" if e.away.size() == 1 else "are"]
			var count := ", %d of %d" % [int(e.staffed), int(e.seats)] if int(e.staffed) > 0 else ""
			lines.append("%s%s%s: %s" % [e.name, count, who, e.cost])
	lines.append(ROSTER_LINE)
	return {
		"seats": seats, "staffed": staffed, "text": "Seats %d of %d" % [staffed, seats], "short": "%d/%d" % [staffed, seats],
		"level": level, "empty": empty, "tip": "\n".join(lines),
	}


# ----------------------------------------------------------------- a trip --

## The stations that have someone now and would have nobody if `party` went: [{"id", "name"}] in the order of what it
## costs. A station that is empty already is not left empty by the trip.
static func leaves_empty(sim, party: Array) -> Array:
	var out: Array = []
	if party.is_empty():
		return out
	for id in _ids(sim):
		if not staffed_in(sim, id).is_empty() and staffed_in(sim, id, party).is_empty():
			out.append({"id": id, "name": String(sim.jobs.station(id).get("name", id))})
	return out


## How many people stay at home while `party` is out: alive, here (not away on another trip) and up.
static func stay_count(sim, party: Array) -> int:
	var n := 0
	for p in sim.people:
		if not p.dead and not p.turned and not p.downed and not on_trip(sim, p) and not party.has(p):
			n += 1
	return n


## What the Town Board says under the party: what the trip leaves empty and, when few are left, how many hold the yard.
## "" when there is nothing to say (nobody chosen, nothing left empty and the yard is not thin).
static func trip_line(sim, party: Array) -> String:
	if party.is_empty():
		return ""
	var parts: Array = []
	var left := leaves_empty(sim, party)
	if not left.is_empty():
		var names: Array = []
		for e in left:
			names.append("the %s" % String(e.name))
		parts.append("This leaves %s empty." % _join(names))
	var stay := stay_count(sim, party)
	if stay <= THIN:
		parts.append("Nobody stays to hold the yard." if stay <= 0 else ("1 stays to hold the yard." if stay == 1 else "%d stay to hold the yard." % stay))
	return " ".join(parts)


## "a", "a and b", "a, b and c".
static func _join(names: Array) -> String:
	if names.size() <= 1:
		return "".join(names)
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]
