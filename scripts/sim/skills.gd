## Skills grow with use: a person who shoots a lot shoots better, one who mends a lot
## builds faster; up to three points over where they started. Each person has their
## own copy (`Person.skills`, from the roster's `def.skills`), and counters of what they
## have done (`Person.stats`).
##
## Credit comes through `credit(p, kind, amount)`, from where the work happens:
##   kills    one for each of the dead put down with a shot (+1 Shooting per 60)
##   melee    one for each put down with the pike or the butt of the gun (+1 Melee per 40)
##   treated  one for each bandage, stabilising or cure given (+1 Medicine per 6)
##   mended   health points put back into a wall (+1 Building per 400)
##   crafted  scrap made into ammo at the worktable (+1 Building per 60)
## Every credit adds its share of a point to the person's progress in that skill (so
## mending and the bench add up); a whole point raises the skill. At most MAX_GAIN
## points over where they started and never past MAX_SKILL; Leading does not grow. A
## quick learner (the `xp` trait key) gets there 1.5 times faster.
##
## Events: {"type": "skill_up", "who": id, "skill": String, "value": int}; alert `skill-<id>`.
extends RefCounted

## The five skills, in the roster's order.
const SKILLS := ["Shooting", "Melee", "Building", "Medicine", "Leading"]
## What each kind of work is worth: the skill it feeds and how much of it makes a point.
const KINDS := {
	"kills": {"skill": "Shooting", "per": 100.0},
	"melee": {"skill": "Melee", "per": 40.0},
	"treated": {"skill": "Medicine", "per": 6.0},
	"mended": {"skill": "Building", "per": 400.0},
	"crafted": {"skill": "Building", "per": 60.0},
}
## At most this many points over where they started, and never past this.
const MAX_GAIN := 3
const MAX_SKILL := 10
## These never grow.
const NO_GROWTH := ["Leading"]
## How a gain reads in the alert: "Marcus is a better shot now".
const PHRASE := {"Shooting": "a better shot", "Melee": "a better fighter", "Building": "a better builder", "Medicine": "a better healer"}
## How long the alert stays up (seconds of rules time).
const ALERT_TTL := 10.0
## A progress this close to a whole point is a whole point (sums of fractions of a point).
const EPS := 1.0e-9

var sim
## Progress toward the next point: person id -> {skill: 0 up to 1, not including}.
var progress := {}


func setup(s) -> void:
	sim = s


## The counters of someone who has done nothing yet.
static func new_stats() -> Dictionary:
	return {"kills": 0, "kills_night": 0, "mended": 0.0, "treated": 0, "crafted": 0.0, "shots": 0}


## A person's own copy of the roster's skills, as whole numbers (the roster is read from
## JSON, where every number is a float).
static func copy_of(roster: Dictionary) -> Dictionary:
	var out := {}
	for k in SKILLS:
		out[k] = roundi(float(roster.get(k, 0)))
	return out


## A fresh run: everyone back to the roster's skills and no counts.
func start() -> void:
	progress.clear()
	for p in sim.people:
		p.skills = copy_of(p.def.skills)
		p.stats = new_stats()


## The bell: the night's kills are counted from here.
func on_bell() -> void:
	for p in sim.people:
		p.stats["kills_night"] = 0


## How many points this person has gained per skill since the run began: {skill: n},
## only the skills that gained.
func gained(p) -> Dictionary:
	var out := {}
	for k in SKILLS:
		var n := int(p.skills.get(k, 0)) - int(p.def.skills.get(k, 0))
		if n > 0:
			out[k] = n
	return out


## How high this skill of this person may go: three over where they started, at most ten.
func cap_of(p, skill: String) -> int:
	if NO_GROWTH.has(skill):
		return int(p.def.skills.get(skill, 0))
	return mini(MAX_SKILL, int(p.def.skills.get(skill, 0)) + MAX_GAIN)


## Credit for work done: `kind` is "kills", "melee", "mended", "treated" or "crafted"
## (anything else is ignored); `amount` is how many (kills, treatments), HP or scrap.
func credit(p, kind: String, amount: float) -> void:
	if p == null or amount <= 0.0 or not KINDS.has(kind):
		return
	_count(p, kind, amount)
	var skill: String = KINDS[kind].skill
	var now := int(p.skills.get(skill, 0))
	var cap := cap_of(p, skill)
	if now >= cap or NO_GROWTH.has(skill):
		return
	var row: Dictionary = progress.get(p.id, {})
	var got: float = float(row.get(skill, 0.0)) + amount / float(KINDS[kind].per) * sim.traits.mult(p, "xp")
	while got >= 1.0 - EPS and now < cap:
		got -= 1.0
		now += 1
		p.skills[skill] = now
		_announce(p, skill, now)
	row[skill] = 0.0 if now >= cap else maxf(0.0, got)
	progress[p.id] = row


func _count(p, kind: String, amount: float) -> void:
	var stats: Dictionary = p.stats
	match kind:
		"kills", "melee":
			var n := roundi(amount)
			stats["kills"] = int(stats.get("kills", 0)) + n
			stats["kills_night"] = int(stats.get("kills_night", 0)) + n
		"treated":
			stats["treated"] = int(stats.get("treated", 0)) + roundi(amount)
		"mended":
			stats["mended"] = float(stats.get("mended", 0.0)) + amount
		"crafted":
			stats["crafted"] = float(stats.get("crafted", 0.0)) + amount


func _announce(p, skill: String, value: int) -> void:
	sim.events.append({"type": "skill_up", "who": p.id, "skill": skill, "value": value})
	var at = Vector2(p.x, p.y) if p.away == null else null
	sim.alert("skill-%s" % p.id, "info", "%s is %s now" % [p.first, PHRASE.get(skill, "better")], "%s %d" % [skill, value], at, ALERT_TTL)
	sim.barks.say(p, "skill_up")


# ---------------------------------------------------------------------- save --

func save() -> Dictionary:
	var rows := {}
	for id in progress:
		rows[id] = progress[id].duplicate()
	return {"progress": rows}


## Restores the progress, and puts every person's skills and counters in order: a save from
## before skills grew has neither (they keep what the roster gave them), a save that lost
## some keys gets them back, and numbers read from text become whole numbers again.
func load_state(d: Dictionary) -> void:
	progress.clear()
	var saved = d.get("progress", {})
	if saved is Dictionary:
		for id in saved:
			if _person(String(id)) == null or not saved[id] is Dictionary:
				continue
			var row := {}
			for k in saved[id]:
				var v = saved[id][k]
				if SKILLS.has(String(k)) and (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v)):
					row[String(k)] = clampf(float(v), 0.0, 1.0 - EPS)
			progress[String(id)] = row
	for p in sim.people:
		var skills := {}
		for k in SKILLS:
			skills[k] = clampi(roundi(float(p.skills.get(k, p.def.skills.get(k, 0)))), 0, MAX_SKILL)
		p.skills = skills
		var stats := new_stats()
		for k in stats:
			var v = p.stats.get(k, stats[k])
			if (typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT) or not is_finite(float(v)):
				v = stats[k]
			stats[k] = maxf(0.0, float(v)) if typeof(stats[k]) == TYPE_FLOAT else maxi(0, roundi(float(v)))
		p.stats = stats


func _person(id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null
