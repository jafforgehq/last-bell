## Wounds, bleeding, bandages, the downed, healing in bed and infection.
##
## The rules step this module every frame and call its hooks (see sim.gd):
## `after_bite`, `on_downed` and `on_wall_claw` when the dead hurt someone,
## `perf`, `goal_for` and `status_of` for the people, `gizmo` for the HUD's
## Treat and Send out buttons.
##
## In short:
## - A bite or a scratch (`add_wound`) bleeds until it is bandaged. A bite also
##   rolls for infection, once per encounter rather than once per bite (a run
##   of bites in a fight is one roll, so the difficulty's chance means what it
##   says).
## - At 0 health a person is downed and has 3 game hours to be stabilised.
## - Every step the module finds patients (the downed, then the bleeding, then
##   the infected the player ordered treated) and sends the best free healer
##   (Medicine 1 or more) to each. A treatment is a "job": the healer walks to
##   the patient and works while standing within reach. The medicine is used
##   when the job is done, and no job is given out that the stock cannot pay.
## - A stabilised person is carried to a bed (cots, then the bunks) and heals
##   10 health an hour, half as fast again while someone is on duty at the
##   Infirmary station; at 40 they get up. The people on the infirmary job are
##   preferred as healers.
## - An infected person turns into a walker 12 to 24 game hours after the bite
##   unless cured or sent out through the gate.
##
## Events added to sim.events (main.gd ignores kinds it does not know):
##   {"type": "turned", "x": float, "y": float}   a survivor just became a walker
extends RefCounted

## Health lost per game hour by each kind of wound.
const BITE_BLEED := 4.0
const SCRATCH_BLEED := 2.0
## A claw at the wall scratches someone behind it with this chance, if anyone
## stands within SCRATCH_REACH tiles of the spot behind the wall.
const SCRATCH_CHANCE := 0.11
const SCRATCH_REACH := 2.5
## A defender on a raised deck (a walkway or a tower) is only reached by this share
## of the scratches that would have found them on the ground.
const DECK_SCRATCH := 0.2
## A bite infects with this chance by difficulty (story, standard, brutal).
const INFECT_CHANCE := [0.3, 0.6, 1.0]
## Bites within this many game hours of the last roll are the same encounter.
const INFECT_GAP_H := 1.0
## The turn comes 12 to 24 game hours after the infection.
const TURN_MIN_H := 12.0
const TURN_SPAN_H := 12.0
## Game hours after the infection when the fever and the delirium show.
const FEVER_H := 6.0
const DELIRIUM_H := 10.0
## Game hours a downed person has to be stabilised.
const BLEED_OUT_H := 3.0
## Game minutes and medicine a bandage (also stabilising) takes.
const BANDAGE_MIN := 10.0
const BANDAGE_MEDS := 1.0
## Game minutes and medicine an infection treatment takes, and its chance:
## 30% plus 10% a point of Medicine, at most 90%.
const CURE_MIN := 15.0
const CURE_MEDS := 2.0
const CURE_BASE := 0.45
const CURE_PER_POINT := 0.1
const CURE_MAX := 0.9
## A healer works while within REACH tiles of the patient and waits a little
## way off them (at most 0.8 tiles), not on top of them. The waiting spot is
## worked out again once the patient has moved ANCHOR_SLACK from where it was.
const REACH := 0.9
const STAND := 0.55
const ANCHOR_SLACK := 0.1
## Choosing a healer: each point of Medicine is worth this many tiles of walk, and a person on the
## Infirmary job is worth this many tiles more (the infirmary's crew is who the player has put there
## to treat the hurt).
const SKILL_TILES := 3.0
const INFIRMARY_PREFERENCE := 6.0
## Health a person regains an hour lying stabilised, and where they get up. While someone is on
## duty in the infirmary (`jobs.working("infirmary")`) a patient in a bed heals this many times
## as fast.
const REST_HEAL_H := 10.0
const INFIRMARY_HEAL_MULT := 1.5
const GET_UP_HP := 40.0
## Below this health people work and shoot worse.
const HURT_HP := 40.0
const HURT_PERF := 0.85
## Sending out: within EXILE_REACH tiles of the gate they leave; if they have
## not got there in EXILE_TIMEOUT_H game hours they leave anyway.
const EXILE_REACH := 1.0
const EXILE_TIMEOUT_H := 1.5
## The no-medicine alert comes at most this often (game hours).
const NO_MEDS_EVERY_H := 2.0
## Thresholds that fall on exact multiples of a step are met with this much to
## spare, so a save that lost the last digit of a float plays out the same.
const EPS := 1e-6

const DANGER := Color("#e0584a")
const WARN := Color("#e8953a")
const INFO := Color("#7fa6c9")

var sim
## Treatments under way: {"healer": Person, "patient": Person, "kind": "bandage"
## or "infection", "work": game minutes done, "stand": where the healer waits
## (Vector2 or null until worked out), "anchor": where the patient was then}.
var jobs: Array = []
## People the player ordered treated (by id).
var treat_orders := {}
## People walking to the gate to be sent out: id -> sim.clock_min of the order.
var sendouts := {}
## The beds, cots first: [{"pos": Vector2, "kind": "cot" or "mattress"}].
var beds: Array = []
## id -> sim.clock_min of the last infection roll.
var last_roll := {}
## id -> the fever stage already announced.
var stage_seen := {}
var no_meds_at := -1.0e9


func setup(s) -> void:
	sim = s
	beds = _find_beds()


func start() -> void:
	jobs.clear()
	treat_orders.clear()
	sendouts.clear()
	last_roll.clear()
	stage_seen.clear()
	no_meds_at = -1.0e9
	beds = _find_beds()


func _find_beds() -> Array:
	var cots: Array = []
	var bunks: Array = []
	for o in sim.d.objects:
		if o.kind == "cot":
			cots.append({"pos": Vector2(o.cx, o.cy), "kind": "cot"})
		elif o.kind == "mattress":
			bunks.append({"pos": Vector2(o.cx, o.cy), "kind": "mattress"})
	return cots + bunks


# ------------------------------------------------------------------ stepping --

## Every step: bleeding, bleed-out timers, healing in bed, infection, turning,
## people walking to the gate, treatments, and handing out new ones.
func update(dt: float) -> void:
	var gh: float = sim.game_hours(dt)
	for p in sim.people:
		if p.dead or p.away != null:
			continue
		_tick(p, gh)
	_update_sendouts()
	_update_jobs(dt)
	_assign()


## How much faster than plain rest a patient heals: a patient in a bed heals INFIRMARY_HEAL_MULT
## times as fast while someone is on duty in the infirmary.
func _care_mult(p) -> float:
	if p.resting_bed != null and not sim.jobs.working("infirmary").is_empty():
		return INFIRMARY_HEAL_MULT
	return 1.0


func _tick(p, gh: float) -> void:
	if p.infected_at >= 0.0:
		if p.turn_at < 0.0:
			p.turn_at = p.infected_at + (TURN_MIN_H + TURN_SPAN_H * sim.rng.randf()) * 60.0
		if sim.clock_min >= p.turn_at:
			_turn(p)
			return
		_announce_fever(p)
	if p.bleeding > 0.0 and not (p.downed and p.stabilised):
		p.hp = maxf(0.0, p.hp - p.bleeding * gh)
		if p.hp <= 0.0 and not p.downed:
			on_downed(p, "bleeding")
	if p.downed:
		if p.stabilised:
			p.hp = minf(100.0, p.hp + REST_HEAL_H * gh * _care_mult(p))
			if p.hp + EPS >= GET_UP_HP:
				_get_up(p)
			elif p.resting_bed == null:
				_carry_to_bed(p)
		else:
			if p.bleed_out < 0.0:
				p.bleed_out = BLEED_OUT_H # downed by some other code
			p.bleed_out -= gh
			if p.bleed_out <= EPS:
				_bled_out(p)
	if treat_orders.has(p.id) and not _needs_bandage(p) and p.infected_at < 0.0:
		treat_orders.erase(p.id)


# -------------------------------------------------------------------- wounds --

## A zombie just bit `p` (health already reduced, blood and alert done).
func after_bite(_z, p) -> void:
	# a tough person is sometimes spared the wound (and so the infection): the Tough trait
	var tough: float = sim.traits.mult(p, "wound")
	if tough < 1.0 and sim.rng.randf() >= tough:
		return
	add_wound(p, "bite")


## Give `p` a wound: kind "scratch" or "bite" (a bite rolls for infection).
func add_wound(p, kind: String) -> void:
	if p.dead:
		return
	p.wounds += 1
	p.bleeding += BITE_BLEED if kind == "bite" else SCRATCH_BLEED
	if kind == "bite":
		_roll_infection(p)
	sim.barks.say(p, "wounded")


func _roll_infection(p) -> void:
	if p.infected_at >= 0.0:
		return
	if sim.clock_min - float(last_roll.get(p.id, -1.0e9)) < INFECT_GAP_H * 60.0 - EPS:
		return # the same fight
	last_roll[p.id] = sim.clock_min
	var chance: float = INFECT_CHANCE[clampi(sim.difficulty, 0, 2)]
	if sim.rng.randf() < chance:
		p.infected_at = sim.clock_min
		p.turn_at = p.infected_at + (TURN_MIN_H + TURN_SPAN_H * sim.rng.randf()) * 60.0


## A zombie clawing at a wall section may scratch a defender right behind it:
## someone within SCRATCH_REACH of the spot just inside the wall, level with
## the walker. The wound is light and never infects.
func on_wall_claw(z, seg) -> void:
	var roll: float = sim.rng.randf()
	if roll >= SCRATCH_CHANCE:
		return
	var behind := Vector2(z.x, seg.center.y) if seg.side == "N" or seg.side == "S" else Vector2(seg.center.x, z.y)
	var victim = null
	var best := SCRATCH_REACH
	for p in sim.people:
		if p.dead or p.downed or p.away != null:
			continue
		var d := Vector2(p.x, p.y).distance_to(behind)
		if d <= best:
			best = d
			victim = p
	if victim == null:
		return
	if sim.world.on_deck(victim.x, victim.y) and sim.rng.randf() >= DECK_SCRATCH:
		return
	if roll >= SCRATCH_CHANCE * sim.traits.mult(victim, "wound"):
		return # a tough person shrugs it off (the Tough trait)
	add_wound(victim, "scratch")
	sim.fx.blood(victim.x, victim.y - 0.25, victim.x - z.x, victim.y - z.y, 5)
	sim.alert("scratch-%s" % victim.id, "warn", "%s was scratched" % victim.first, "It bleeds until it is bandaged", Vector2(victim.x, victim.y), 6.0)


## 0.85 when badly hurt, else 1.0.
func perf(p) -> float:
	return HURT_PERF if p.hp < HURT_HP else 1.0


# ------------------------------------------------------------------- the downed --

## `p` reached 0 health ("bite", "bleeding", "hunger", "thirst"...): down, with
## three game hours to be stabilised.
func on_downed(p, cause: String) -> void:
	if p.dead or p.downed:
		return
	p.downed = true
	p.stabilised = false
	p.moving = false
	p.bleed_out = BLEED_OUT_H
	p.drafted = false
	p.order = null
	p.repair = null
	p.target = null
	p.path = []
	p.goal_key = ""
	p.activity = {"hunger": "Collapsed from hunger", "thirst": "Collapsed from thirst"}.get(cause, "Down and bleeding")
	_drop_jobs_of(p, true)
	sendouts.erase(p.id)
	var ana = _person("ana")
	var able: bool = ana != null and ana != p and not ana.dead and not ana.downed and ana.away == null
	sim.alert("down-%s" % p.id, "danger", "%s is down" % p.first, "Get them to Ana" if able else "Stabilise them", Vector2(p.x, p.y), 60.0)
	sim.morale.on_downed(p)
	sim.barks.on_friend_down(p)


func _bled_out(p) -> void:
	if sim.permadeath:
		kill(p, "bled out")
	else:
		stabilise(p)


## Stops a downed person bleeding out and carries them to a bed: the nearest
## free cot, else the nearest free bunk, else they stay where they lie. They
## heal there whether or not there is a bed.
func stabilise(p) -> void:
	if p.dead or not p.downed:
		return
	p.stabilised = true
	p.bleed_out = -1.0
	p.bleeding = 0.0
	p.wounds = 0
	sim.alerts.erase("down-%s" % p.id)
	_carry_to_bed(p)


func _carry_to_bed(p) -> void:
	if p.resting_bed != null:
		return
	p.path = []
	p.goal_key = ""
	p.moving = false
	var bed = _free_bed(Vector2(p.x, p.y))
	if bed == null:
		p.activity = "Resting"
		return
	var pos: Vector2 = bed.pos
	p.x = pos.x
	p.y = pos.y
	p.resting_bed = pos
	p.activity = "Resting in the infirmary" if bed.kind == "cot" else "Resting in the bunks"


func _free_bed(from: Vector2):
	for kind in ["cot", "mattress"]:
		var best = null
		var best_d := INF
		for b in beds:
			if b.kind != kind or _bed_taken(b.pos):
				continue
			var d := from.distance_to(b.pos)
			if d < best_d:
				best_d = d
				best = b
		if best != null:
			return best
	return null


func _bed_taken(pos: Vector2) -> bool:
	for q in sim.people:
		if not q.dead and q.resting_bed != null and Vector2(q.resting_bed).distance_to(pos) < 0.05:
			return true
	return false


func _get_up(p) -> void:
	p.downed = false
	p.stabilised = false
	p.bleed_out = -1.0
	p.resting_bed = null
	p.moving = false
	p.path = []
	p.goal_key = ""
	sim.alert("up-%s" % p.id, "info", "%s is back up" % p.first, "Back at work, %d%% health" % roundi(p.hp), Vector2(p.x, p.y), 6.0)


## `p` dies for good (cause is a short word such as "scavenging").
func kill(p, cause: String) -> void:
	if p.dead:
		return
	var at = Vector2(p.x, p.y) if p.away == null else null
	_forget(p)
	p.dead = true
	p.downed = true
	p.moving = false
	p.resting_bed = null
	p.bleeding = 0.0
	p.wounds = 0
	p.bleed_out = -1.0
	p.infected_at = -1.0
	p.turn_at = -1.0
	p.activity = "Dead"
	sim.alerts.erase("down-%s" % p.id)
	sim.alert("dead-%s" % p.id, "danger", "%s died" % p.first, _cause_text(cause), at, 60.0)
	if cause != "scavenging": # a lost party tells its own story
		sim.events.append({"type": "banner", "text": "%s died" % p.first, "sub": _cause_text(cause)})
	sim.morale.on_lost(p, "died")
	sim.barks.on_lost(p)


func _cause_text(cause: String) -> String:
	var known := {"bled out": "Bled out", "hunger": "Starved", "thirst": "Died of thirst", "scavenging": "Lost while scavenging"}
	if known.has(cause):
		return known[cause]
	return cause.substr(0, 1).to_upper() + cause.substr(1)


# ------------------------------------------------------------------ infection --

## "", "feverish" or "delirious": what the panel shows for an infected person.
func infection_stage(p) -> String:
	if p.dead or p.infected_at < 0.0:
		return ""
	var hours: float = (sim.clock_min - p.infected_at) / 60.0
	if hours + EPS >= DELIRIUM_H:
		return "delirious"
	if hours + EPS >= FEVER_H:
		return "feverish"
	return ""


func _announce_fever(p) -> void:
	var stage := infection_stage(p)
	if stage == String(stage_seen.get(p.id, "")):
		return
	stage_seen[p.id] = stage
	var at := Vector2(p.x, p.y)
	if stage == "feverish":
		sim.alert("fever-%s" % p.id, "warn", "%s has a fever" % p.first, "Treat them, or send them out", at, 12.0)
	elif stage == "delirious":
		sim.alert("fever-%s" % p.id, "danger", "%s is delirious" % p.first, "It will not be long", at, 12.0)


## `p` becomes a walker where they stand (or lie).
func _turn(p) -> void:
	var at := Vector2(p.x, p.y)
	_forget(p)
	p.dead = true
	p.turned = true
	p.downed = true
	p.moving = false
	p.resting_bed = null
	p.bleeding = 0.0
	p.wounds = 0
	p.bleed_out = -1.0
	p.infected_at = -1.0
	p.turn_at = -1.0
	p.activity = "Turned"
	sim.alerts.erase("down-%s" % p.id)
	sim.alerts.erase("fever-%s" % p.id)
	var z = sim.spawn(p.x, p.y, "breach")
	z.turned_name = p.name
	z.facing = p.facing
	z.stagger = 1.2 # it takes a moment to get up
	sim.alert("turned-%s" % p.id, "danger", "%s has turned" % p.first, "Put them down", at, 30.0)
	sim.events.append({"type": "banner", "text": "%s has turned" % p.first, "sub": "Put them down"})
	sim.events.append({"type": "turned", "x": p.x, "y": p.y})
	sim.morale.on_lost(p, "turned")
	sim.barks.on_lost(p)


## The chance that `healer` clears an infection: 30% plus 10% a point of
## Medicine, at most 90%, and on top of that what the healer's traits add (Triage: 10%).
func cure_chance(healer) -> float:
	var by_skill := minf(CURE_MAX, CURE_BASE + CURE_PER_POINT * float(healer.skills.Medicine))
	return clampf(by_skill + sim.traits.add(healer, "cure"), 0.0, 1.0)


## Takes 2 medicine and rolls the healer's chance; true if the infection is gone.
func try_cure(healer, patient) -> bool:
	_use_meds(CURE_MEDS)
	if sim.rng.randf() < cure_chance(healer):
		patient.infected_at = -1.0
		patient.turn_at = -1.0
		stage_seen.erase(patient.id)
		sim.alerts.erase("fever-%s" % patient.id)
		return true
	return false


# ----------------------------------------------------------------- treating --

func _needs_bandage(p) -> bool:
	return (p.downed and not p.stabilised) or p.bleeding > 0.0


func _use_meds(amount: float) -> void:
	sim.stock.meds = maxf(0.0, float(sim.stock.meds) - amount)


func _person(id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


func _job_of_healer(h):
	for j in jobs:
		if j.healer == h:
			return j
	return null


func _job_of_patient(p):
	for j in jobs:
		if j.patient == p:
			return j
	return null


## Free to go and treat someone: able, off orders, not already busy, and with
## at least a little Medicine.
func _is_free(h) -> bool:
	if h.dead or h.downed or h.away != null or h.order != null or sim.morale.breakdown(h):
		return false
	if int(h.skills.Medicine) < 1 or sendouts.has(h.id):
		return false
	if _job_of_healer(h) != null or _job_of_patient(h) != null:
		return false
	return sim.scavenge.goal_for(h) == null


func _job_ok(j) -> bool:
	var h = j.healer
	var p = j.patient
	if h == p or not _is_free_for_job(h):
		return false
	if p.dead or p.away != null or sendouts.has(p.id):
		return false
	if j.kind == "bandage":
		return _needs_bandage(p)
	return p.infected_at >= 0.0 and treat_orders.has(p.id)


## Like _is_free, for a healer who already holds a job.
func _is_free_for_job(h) -> bool:
	if h.dead or h.downed or h.away != null or h.order != null or sim.morale.breakdown(h):
		return false
	return not sendouts.has(h.id) and sim.scavenge.goal_for(h) == null


func _drop_jobs_of(p, as_healer_only: bool = false) -> void:
	for j in jobs.duplicate():
		if j.healer == p or (not as_healer_only and j.patient == p):
			jobs.erase(j)


## Forget everything that involves `p` (they died, turned or left).
func _forget(p) -> void:
	_drop_jobs_of(p)
	treat_orders.erase(p.id)
	sendouts.erase(p.id)
	stage_seen.erase(p.id)


## Medicine not yet promised to a job in progress.
func _free_meds() -> float:
	var free := float(sim.stock.meds)
	for j in jobs:
		free -= BANDAGE_MEDS if j.kind == "bandage" else CURE_MEDS
	return free


## The patients in order of need: the downed (soonest to bleed out first), the
## bleeding (worst first), then the infected the player ordered treated.
func _queue() -> Array:
	var items: Array = []
	for i in sim.people.size():
		var p = sim.people[i]
		if p.dead or p.away != null or sendouts.has(p.id) or _job_of_healer(p) != null:
			continue
		if p.downed and not p.stabilised:
			items.append({"p": p, "kind": "bandage", "rank": 0, "key": float(p.bleed_out), "i": i})
		elif p.bleeding > 0.0:
			items.append({"p": p, "kind": "bandage", "rank": 1, "key": -float(p.bleeding), "i": i})
		elif p.infected_at >= 0.0 and treat_orders.has(p.id):
			items.append({"p": p, "kind": "infection", "rank": 2, "key": float(p.turn_at), "i": i})
	items.sort_custom(func(a, b):
		if a.rank != b.rank:
			return a.rank < b.rank
		if a.key != b.key:
			return a.key < b.key
		return a.i < b.i)
	return items


## Hands the patients to healers, most urgent first.
func _assign() -> void:
	var queue := _queue()
	if queue.is_empty():
		return
	var short: Array = []
	for item in queue:
		var p = item.p
		if _job_of_patient(p) != null:
			continue
		var cost: float = BANDAGE_MEDS if item.kind == "bandage" else CURE_MEDS
		if _free_meds() + 1e-6 < cost:
			short.append(p)
			continue
		var healer = _best_healer(p)
		if healer != null:
			jobs.append({"healer": healer, "patient": p, "kind": item.kind, "work": 0.0, "stand": null, "anchor": Vector2.ZERO})
		elif item.rank < 2:
			_turn_a_healer_to(p, item.rank)
	if not short.is_empty() and sim.clock_min - no_meds_at + EPS >= NO_MEDS_EVERY_H * 60.0:
		no_meds_at = sim.clock_min
		var p = short[0]
		var dying: bool = p.downed and not p.stabilised
		var sub := "Nothing to bandage %s with" % p.first
		if p.infected_at >= 0.0 and not _needs_bandage(p):
			sub = "Not enough to treat %s (it takes 2)" % p.first
		sim.alert("no-meds", "danger" if dying else "warn", "No medicine", sub, Vector2(p.x, p.y), 8.0)


## How good a choice `h` is as the healer of `patient` (lower is better): the tiles to walk, less a
## few for each point of Medicine and a few more for being on the Infirmary job.
func _healer_score(h, patient) -> float:
	var score: float = Vector2(h.x, h.y).distance_to(Vector2(patient.x, patient.y)) - SKILL_TILES * float(h.skills.Medicine)
	if sim.jobs.job_of(h) == "infirmary":
		score -= INFIRMARY_PREFERENCE
	return score


## The free healer for `patient`: the nearest, with each point of Medicine
## worth a few tiles, so Ana goes first, and the infirmary's crew preferred. Never the patient,
## never someone with no Medicine, never someone on an order.
func _best_healer(patient):
	var best = null
	var best_score := INF
	for h in sim.people:
		if h == patient or not _is_free(h):
			continue
		var score := _healer_score(h, patient)
		if score < best_score:
			best_score = score
			best = h
	return best


## How urgent a patient is: 0 down and not stabilised, 1 bleeding, 2 the rest.
func _rank_of(p) -> int:
	if p.downed and not p.stabilised:
		return 0
	return 1 if p.bleeding > 0.0 else 2


## Nobody is free for `patient` (of urgency `rank`): a healer who is still
## walking to someone less urgent, and has not started work, is sent here
## instead. The other patient goes back in the queue.
func _turn_a_healer_to(patient, rank: int) -> void:
	var best = null
	var best_score := INF
	for j in jobs:
		if j.work > 0.0 or j.healer == patient or _rank_of(j.patient) <= rank:
			continue
		var h = j.healer
		if Vector2(h.x, h.y).distance_to(Vector2(j.patient.x, j.patient.y)) <= REACH:
			continue
		var score := _healer_score(h, patient)
		if score < best_score:
			best_score = score
			best = j
	if best != null:
		best.patient = patient
		best.kind = "bandage" if rank < 2 else "infection"
		best.work = 0.0
		best.stand = null


## Drops jobs that no longer make sense and does the work of the rest.
func _update_jobs(dt: float) -> void:
	var minutes: float = sim.game_hours(dt) * 60.0
	for j in jobs.duplicate():
		if not _job_ok(j):
			jobs.erase(j)
			continue
		if Vector2(j.healer.x, j.healer.y).distance_to(Vector2(j.patient.x, j.patient.y)) > REACH:
			if j.stand != null and Vector2(j.healer.x, j.healer.y).distance_to(j.stand) < 0.15:
				j.stand = null # they are at their spot and the patient is not: find a new one
			continue
		j.work += minutes * (sim.traits.mult(j.healer, "bandage") if j.kind == "bandage" else 1.0)
		if j.work + EPS >= (BANDAGE_MIN if j.kind == "bandage" else CURE_MIN):
			jobs.erase(j)
			_finish(j)


func _finish(j) -> void:
	var healer = j.healer
	var p = j.patient
	if j.kind == "bandage":
		_use_meds(BANDAGE_MEDS)
		p.bleeding = 0.0
		p.wounds = 0
		if p.downed and not p.stabilised:
			stabilise(p)
		sim.skills.credit(healer, "treated", 1.0)
		return
	treat_orders.erase(p.id)
	var at := Vector2(p.x, p.y)
	if try_cure(healer, p):
		sim.alert("treated-%s" % p.id, "info", "%s's infection is gone" % p.first, "%s's treatment worked" % healer.first, at, 12.0)
	else:
		sim.alert("treated-%s" % p.id, "warn", "The treatment did not take", "%s is still infected. Try again (2 medicine)" % p.first, at, 12.0)
	sim.skills.credit(healer, "treated", 1.0)


## A goal the rules walk a person to, {"x", "y", "face", "what"}: to the gate
## for someone being sent out, to the patient for a healer with a job.
func goal_for(p):
	if p.dead or p.downed or p.away != null:
		return null
	if sendouts.has(p.id):
		var gate := _gate()
		return {"x": gate.x, "y": gate.y, "face": "N", "what": "Leaving through the gate"}
	var j = _job_of_healer(p)
	if j == null:
		return null
	var patient = j.patient
	var stand := _stand_for(j)
	var word := "Bandaging"
	if j.kind == "infection":
		word = "Treating"
	elif patient.downed and not patient.stabilised:
		word = "Stabilising"
	return {"x": stand.x, "y": stand.y, "face": _face(patient.x - stand.x, patient.y - stand.y), "what": "%s %s" % [word, patient.first]}


func _face(dx: float, dy: float) -> String:
	if absf(dx) > absf(dy):
		return "E" if dx > 0.0 else "W"
	return "S" if dy > 0.0 else "N"


## Where the healer waits: not on top of the patient. For someone lying on the
## ground (drawn with the head to the east) that is at their feet; for someone
## in bed, at the bedside; else beside them, on the side the healer comes from.
## Kept until the patient moves, so the rules do not plan a new path every step.
func _stand_for(j) -> Vector2:
	var pv := Vector2(j.patient.x, j.patient.y)
	if j.stand == null or pv.distance_to(j.anchor) > ANCHOR_SLACK:
		j.stand = _work_out_stand(j.healer, j.patient)
		j.anchor = pv
	return j.stand


func _work_out_stand(healer, patient) -> Vector2:
	var pv := Vector2(patient.x, patient.y)
	var hv := Vector2(healer.x, healer.y)
	var options: Array = []
	if patient.resting_bed != null:
		var side := -1.0 if hv.x < pv.x else 1.0
		options = [pv + Vector2(0.75 * side, -0.2), pv + Vector2(-0.75 * side, -0.2)]
	elif patient.downed:
		options = [pv + Vector2(-0.6, 0.25)]
	else:
		var off := hv - pv
		if off.length() <= 0.7:
			return hv
		var side := -1.0 if off.x < 0.0 else 1.0
		options = [pv + Vector2(0.65 * side, 0.1), pv + Vector2(-0.65 * side, 0.1), pv + off.normalized() * STAND]
	for spot in options:
		if not sim.world.is_solid(sim.world.solid_p, spot.x, spot.y):
			return spot
	return pv


# -------------------------------------------------------------------- buttons --

## Whether the HUD should offer "Treat" for `p` (bleeding, down and not yet
## stabilised, or infected).
func can_treat(p) -> bool:
	if p.dead or p.turned or p.away != null:
		return false
	return _needs_bandage(p) or p.infected_at >= 0.0 or sim.storyteller.is_sick(p)


## Whether the HUD should offer "Send out" for `p` (infected, and able to walk
## to the gate: someone down and not stabilised is not).
func can_send_out(p) -> bool:
	if p.dead or p.turned or p.away != null or p.infected_at < 0.0:
		return false
	return not (p.downed and not p.stabilised)


## Marks for the card and panel: wound, fever, down, resting.
func status_of(p) -> Array:
	var out: Array = []
	if p.dead or p.away != null:
		return out
	if p.bleeding > 0.0:
		out.append({"icon": "wound", "color": DANGER, "tip": "Bleeding (%d %s)" % [p.wounds, "wound" if p.wounds == 1 else "wounds"]})
	var stage := infection_stage(p)
	if stage != "":
		out.append({"icon": "fever", "color": WARN, "tip": stage.capitalize()})
	if p.downed and not p.stabilised:
		out.append({"icon": "down", "color": DANGER, "tip": "Down: bleeding out"})
	elif p.downed:
		out.append({"icon": "resting", "color": INFO, "tip": "Resting"})
	return out


## Handles the HUD buttons "treat" and "sendout" for the selection
## {"kind": "person", "ref": Person}. True if it took the button.
func gizmo(id: String, sel) -> bool:
	if id != "treat" and id != "sendout":
		return false
	if typeof(sel) != TYPE_DICTIONARY or sel.get("kind", "") != "person":
		return false
	var p = sel.ref
	if id == "treat":
		if not can_treat(p):
			return false
		# a passing fever (a card of the storyteller's) is treated at once, for one medicine
		if sim.storyteller.is_sick(p) and not _needs_bandage(p) and p.infected_at < 0.0:
			return sim.storyteller.treat(p)
		sendouts.erase(p.id) # they changed their mind
		treat_orders[p.id] = true
		no_meds_at = -1.0e9 # the player asked: tell them if it cannot be done
		_assign()
		if _job_of_patient(p) == null and _free_meds() >= (BANDAGE_MEDS if _needs_bandage(p) else CURE_MEDS) and _best_healer(p) == null:
			sim.alert("nohealer-%s" % p.id, "warn", "Nobody is free to treat %s" % p.first, "Take someone off their orders", Vector2(p.x, p.y), 6.0)
		return true
	if not can_send_out(p):
		return false
	_start_sendout(p)
	return true


func _start_sendout(p) -> void:
	sendouts[p.id] = sim.clock_min
	treat_orders.erase(p.id)
	p.drafted = false
	p.order = null
	p.repair = null
	p.target = null
	p.path = []
	p.goal_key = ""
	if p.downed: # out of bed, on their feet
		p.downed = false
		p.stabilised = false
		p.bleed_out = -1.0
		p.resting_bed = null
	_drop_jobs_of(p)


func _gate() -> Vector2:
	for s in sim.segments:
		if s.kind == "gate":
			var c: Vector2 = s.center
			return c
	return sim.segments[2].center


## People on their way to the gate: they leave when they get there, or when
## they have been walking too long; a new order (or a fall) cancels it.
func _update_sendouts() -> void:
	var gate := _gate()
	for id in sendouts.keys():
		var p = _person(String(id))
		if p == null or p.dead or p.away != null or p.downed or p.order != null or p.repair != null:
			sendouts.erase(id)
			continue
		var waited: float = (sim.clock_min - float(sendouts[id])) / 60.0
		if Vector2(p.x, p.y).distance_to(gate) <= EXILE_REACH or waited + EPS >= EXILE_TIMEOUT_H:
			_exile(p)


func _exile(p) -> void:
	_forget(p)
	p.away = {"kind": "exile"}
	p.dead = true
	p.moving = false
	p.bleeding = 0.0
	p.wounds = 0
	p.infected_at = -1.0
	p.turn_at = -1.0
	p.activity = "Left through the gate"
	sim.alert("exile-%s" % p.id, "warn", "%s left through the gate" % p.first, "", null, 10.0)
	sim.morale.on_lost(p, "left")


# ---------------------------------------------------------------------- save --

func save() -> Dictionary:
	var saved_jobs: Array = []
	for j in jobs:
		var entry := {"healer": j.healer.id, "patient": j.patient.id, "kind": j.kind, "work": j.work}
		if j.stand != null:
			entry["stand"] = [j.stand.x, j.stand.y]
			entry["anchor"] = [j.anchor.x, j.anchor.y]
		saved_jobs.append(entry)
	return {
		"jobs": saved_jobs,
		"orders": treat_orders.keys(),
		"sendouts": sendouts.duplicate(),
		"rolls": last_roll.duplicate(),
		"stages": stage_seen.duplicate(),
		"no_meds_at": no_meds_at,
	}


func load_state(d: Dictionary) -> void:
	jobs.clear()
	treat_orders.clear()
	sendouts.clear()
	last_roll.clear()
	stage_seen.clear()
	no_meds_at = float(d.get("no_meds_at", -1.0e9))
	if typeof(d.get("jobs")) == TYPE_ARRAY:
		for j in d.jobs:
			if typeof(j) != TYPE_DICTIONARY:
				continue
			var h = _person(String(j.get("healer", "")))
			var p = _person(String(j.get("patient", "")))
			var kind := String(j.get("kind", ""))
			if h == null or p == null or h == p or (kind != "bandage" and kind != "infection"):
				continue
			var job := {"healer": h, "patient": p, "kind": kind, "work": float(j.get("work", 0.0)), "stand": null, "anchor": Vector2.ZERO}
			var stand = j.get("stand")
			var anchor = j.get("anchor")
			if typeof(stand) == TYPE_ARRAY and stand.size() == 2 and typeof(anchor) == TYPE_ARRAY and anchor.size() == 2:
				job.stand = Vector2(float(stand[0]), float(stand[1]))
				job.anchor = Vector2(float(anchor[0]), float(anchor[1]))
			jobs.append(job)
	if typeof(d.get("orders")) == TYPE_ARRAY:
		for id in d.orders:
			if _person(String(id)) != null:
				treat_orders[String(id)] = true
	if typeof(d.get("sendouts")) == TYPE_DICTIONARY:
		for id in d.sendouts:
			if _person(String(id)) != null:
				sendouts[String(id)] = float(d.sendouts[id])
	if typeof(d.get("rolls")) == TYPE_DICTIONARY:
		for id in d.rolls:
			if _person(String(id)) != null:
				last_roll[String(id)] = float(d.rolls[id])
	if typeof(d.get("stages")) == TYPE_DICTIONARY:
		for id in d.stages:
			if _person(String(id)) != null:
				stage_seen[String(id)] = String(d.stages[id])
