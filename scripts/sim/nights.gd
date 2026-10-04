## Presence, plating and breaches (round 19, slice 3: docs/superpowers/plans/2026-10-03-round-19.md, S3.2).
##
## "Needs the player" is mechanical and small, three rules keyed to one fact, the avatar standing near the thing:
##   RALLY. The avatar up, at the base and within `rally.radius` tiles of a defender: the defender aims better (`aim_mult`, multiplied into
##     `Sim.aim_factor`) and fires faster (`fire_mult`, into the cooldown of `Sim._fire`). The avatar himself never gets it.
##   PLATING. A brute of a Big Night (`Zombie.plated`) takes `plated.armour` of a hit, but a hit on its head (the pellet's ray within
##     `plated.weak_r` x size of the head's centre: `weak_hit`, which `Avatar.trace` reports as "weak") `plated.weak_mult` times. A defender
##     finds the head by luck: one die a shot at a plated brute (`npc_weak`), none for anything else. `damage_to` is the one place the two meet.
##   BREACH. A section that fell stays open until it has been mended above 40% (`Sim._segment_state`). Nobody mends at night; what is new:
##     a defender sent to mend a hot breach (two or more of the dead near it) does nothing unless the avatar rallies them (`repair_mult`: the
##     mender drops the order and an alert says why), and the avatar mends by hand (`wall_candidates`, `mend_wall`, a session like the bench's).
## Everything is behind `active()`: the settlement's own sim (`Sim.nights_on`, false in a place's sim) with an avatar (`Sim.player_id`). Without
## either, every function returns its neutral value, throws no die and changes no number (the hooks are one factor of 1.0 each), so the game
## plays byte for byte as before (tests/test_nights_regression.gd).
##
## THE NUMBERS are in assets/data/nights.json (read through NightData: rally, plated, breach, mend); the weights of `section_threat` are
## below. `section_threat`, `contested` and `stand_for` are the one place the bot, the calls and the view's marks ask where a night is hot.
##
## ROUND 22, ONE PRESS: a hand-mending session goes on until the wall is whole (`seg.hp == max_hp`), the scrap is gone, or something stops it
## (a step, the trigger, a wound, one of the dead within `DANGER_R` tiles of him, a fall) and says why (`stop_words`, which the view toasts); it
## used to stop silently after `mend.seconds`, three presses and three silent stops for a fallen container. `mend.seconds` is now the round
## of the ring that shows the hands at work. When a fallen section stands again under his hands the News says "The <wall> is shut again".
## THE HAND-MENDING SESSION (`mend_wall`) lives here, not in interact.gd (round 18's E interactions are another branch when this was built):
## `wall_candidates()` is the list of E candidates of kind "wall" (the same dictionary shape as `Interact.candidates`: kind, id (the section's id
## as text), label, pos, dist, ok, why, and `seg` the id as a number), `mend_wall(seg_id)` starts a session, `stop_mend(why)` ends it, and
## `working` is "wall" while it goes on (`work_left`: the rules seconds left, `mend_seg`: the section's id). The merge adds the candidates to
## `Interact.candidates()` (rank after the vehicle) and calls these from `Interact.use()`.
##
## Events this module adds to sim.events:
##   {"type": "wall_work", "on": true, "seg": id, "hp": 0.0} and {"type": "wall_work", "on": false, "seg": id, "hp": mended, "why": ...}
##       (why: "moved", "fired", "hurt", "danger", "whole", "no scrap", "stopped", or why the avatar cannot ("You are down"...))
## Alerts: "hot-<id>" when a fallen section turns hot, "nomend-<id>" when a mender gives up a hot breach.
##
## Saved with the modules (`save`/`load_state`): `warned` and the hot-breach alert marks. A session is never resumed.
extends RefCounted

const NightData := preload("res://scripts/sim/night_data.gd")
const Lots := preload("res://scripts/sim/lots.gd")

## `section_threat`: what each thing at a section is worth (the plan's numbers).
const W_ATTACKER := 1.0
const W_APPROACHER := 0.35
const APPROACH_R := 25.0
const W_BRUTE := 5.0
const W_WOUND := 6.0
const W_BREACHER := 0.8
const BREACHER_R := 10.0
const W_HOT := 4.0
## Where the dead of a breach go when there is nobody they can reach (round 22: a lost wall lets them in): the middle of the yard, the
## stores' place (the middle the waves' outlook uses too).
const YARD_MIDDLE := Vector2(42.0, 32.0)
## `contested` names a section only when its threat is at least this.
const CONTESTED_MIN := 2.0
## How often (rules seconds) the hot breaches are looked at for their alert.
const WATCH_EVERY := 1.0
## A section at or above this share of its health is not mended by hand (unless it is down).
const SOUND := 0.95
## The walking input this long is a hand on the keys; a hammer blow every this many seconds.
const HANDS_ON := 0.25
const HAMMER_EVERY := 0.45
## One of the dead (approaching, clawing, in a breach or hunting) this near the avatar stops his hands at a wall, and keeps them from beginning.
const DANGER_R := 2.0
const EPS := 1.0e-6

var sim
## Sections a warning was given for (segment id -> day): the mender who gave a hot breach up, and the hot breaches already announced
## (segment id -> day), so that each is told once a day.
var warned := {}
var hot_marks := {}
## The avatar's hand-mending: "wall" while it goes on, the rules seconds left, the section's id, and who it belongs to, their health when it
## began and what it has mended so far. Never saved.
var working := ""
var work_left := 0.0
var mend_seg := -1
var _who := ""
var _hp0 := 0.0
var _mended := 0.0
var _hammer := 0.0
var _watch := 0.0


func setup(s) -> void:
	sim = s


func start() -> void:
	warned = {}
	hot_marks = {}
	_forget_session()
	_watch = 0.0


## Once a step (`Sim.update`, right after the streets): once a second the fallen sections that the dead are at are told of, once a day each.
func update(dt: float) -> void:
	if not active():
		return
	_watch += dt
	if _watch < WATCH_EVERY:
		return
	_watch = 0.0
	for s in sim.segments:
		if s.state == 3 and breach_hot(s) and int(hot_marks.get(int(s.id), 0)) != int(sim.day):
			hot_marks[int(s.id)] = int(sim.day)
			sim.alert("hot-%d" % s.id, "danger", "The dead are at the %s" % String(s.name).to_lower(), "No mending under fire: put them down, or come to it", s.center, 15.0)


## Whether any of this applies: the settlement game's sim (not a place's) with an avatar.
func active() -> bool:
	return sim.nights_on and sim.player_id != ""


# ------------------------------------------------------------------------------------- rally --

## The avatar is up, at the base, `p` is someone else and within rally.radius (9) tiles of them. A person who is dead, turned or away
## on a trip is nobody's to rally; the avatar himself never is.
func rallied(p) -> bool:
	if p == null or not active():
		return false
	var lead = sim.avatar.player()
	if lead == null or p == lead:
		return false
	if lead.dead or lead.downed or lead.turned or lead.away != null:
		return false
	if p.dead or p.turned or p.away != null:
		return false
	return Vector2(p.x, p.y).distance_to(Vector2(lead.x, lead.y)) <= NightData.num("rally.radius")


## 1 + rally.aim if `rallied(p)`, else 1.0 (multiplies `Sim.aim_factor`).
func aim_mult(p) -> float:
	return 1.0 + NightData.num("rally.aim") if rallied(p) else 1.0


## rally.fire (0.85) if `rallied(p)`, else 1.0 (multiplies the gun's cooldown in `Sim._fire`).
func fire_mult(p) -> float:
	return NightData.num("rally.fire", 1.0) if rallied(p) else 1.0


# ----------------------------------------------------------------------------------- plating --

## `dmg` for anything not plated (and always when the rules do not apply); a plated brute: dmg x weak_mult on a head hit, else
## dmg x armour.
func damage_to(z, dmg: float, weak: bool) -> float:
	if z == null or not z.plated or not active():
		return dmg
	return dmg * (NightData.num("plated.weak_mult") if weak else NightData.num("plated.armour"))


## Whether the pellet's ray (from `from` along `dir`, any length) passes within weak_r x size of the head's centre,
## (z.x, z.y - head x size): the body's centre is BODY (0.3) up, as `Avatar.trace` has it. Only a plated brute has a weak point.
func weak_hit(z, from: Vector2, dir: Vector2) -> bool:
	return weak_along(z, from, dir) >= 0.0


## How far along the ray (from `from`, along `dir`) the head's disc is met: the distance to the point nearest the head's middle, or -1.0 when the ray
## does not pass within weak_r x size of it (or the rules do not apply). `weak_hit` is this; `Avatar.trace` takes a plated brute's head as part of
## the brute with it, since the head's disc sticks out of the body's: one geometry for the pellet, the rules and the ring that shows it.
func weak_along(z, from: Vector2, dir: Vector2) -> float:
	if z == null or not z.plated or not active() or dir.length_squared() < 1.0e-12:
		return -1.0
	var size := float(z.size)
	var head := Vector2(z.x, z.y - NightData.num("plated.head") * size) - from
	var ray := dir.normalized()
	var along := head.dot(ray)
	if along < 0.0 or absf(head.cross(ray)) > NightData.num("plated.weak_r") * size:
		return -1.0
	return along


## A defender's shot at a plated brute: one die (rng.randf() < npc_weak); no die for anything else.
func npc_weak(z) -> bool:
	if z == null or not z.plated or not active():
		return false
	return sim.rng.randf() < NightData.num("plated.npc_weak")


# ----------------------------------------------------------------------------------- breaches --

## A fallen section (state 3) with at least breach.hot_n of the dead (approach, attack, breach) within breach.hot_r tiles of its middle.
## Read as it is now, so that nobody has to wait for the once-a-second look to learn it.
func breach_hot(seg) -> bool:
	if seg == null or seg.state != 3 or not active():
		return false
	var r: float = NightData.num("breach.hot_r")
	var need := int(NightData.num("breach.hot_n"))
	var n := 0
	for z in sim.zombies:
		if z.state != "approach" and z.state != "attack" and z.state != "breach":
			continue
		if Vector2(z.x, z.y).distance_to(seg.center) <= r:
			n += 1
			if n >= need:
				return true
	return false


## 0.0 for a person (not the avatar) mending a hot breach with nobody rallying them; else 1.0. Asked by the repair branch of
## `Sim._update_person` as the mender arrives: the answer 0.0 also drops their order and says why (an alert), so that the one who was sent
## does not stand there hammering at nothing. The avatar's own hands (`mend_wall`) are never stopped by it.
func repair_mult(p, seg) -> float:
	if p == null or seg == null or p.player or not active():
		return 1.0
	if not breach_hot(seg) or rallied(p):
		return 1.0
	p.repair = null
	p.goal_key = ""
	var id := "nomend-%d" % seg.id
	if int(warned.get(int(seg.id), 0)) != int(sim.day) or not sim.alerts.has(id):
		warned[int(seg.id)] = int(sim.day)
		sim.alert(id, "warn", "Nobody will mend the %s under fire" % String(seg.name).to_lower(), "Put the dead down, or come to it", seg.center, 12.0)
	return 0.0


## How hard a section is pressed, the one number the bot, the calls and the view's marks use: attackers (the dead in `attack` at its places)
## + 0.35 x approachers (with a place there, within 25 tiles) + 5 x brutes (attack or approach there) + 6 x (1 - hp/max_hp) + 0.8 x the dead
## in `breach` within 10 tiles + 4 if the breach is hot. 0 for a door and when the rules do not apply.
func section_threat(seg) -> float:
	if seg == null or not active() or seg.kind == sim.DOOR_KIND:
		return 0.0
	var attackers := 0
	var approachers := 0
	var brutes := 0
	var breachers := 0
	for z in sim.zombies:
		match String(z.state):
			"attack":
				if z.slot != null and z.slot.seg == seg:
					attackers += 1
					if z.kind == "brute":
						brutes += 1
			"approach":
				if z.slot != null and z.slot.seg == seg:
					if Vector2(z.x, z.y).distance_to(seg.center) <= APPROACH_R:
						approachers += 1
					if z.kind == "brute":
						brutes += 1
			"breach":
				if Vector2(z.x, z.y).distance_to(seg.center) <= BREACHER_R:
					breachers += 1
	var lost := 1.0 - clampf(float(seg.hp) / maxf(float(seg.max_hp), 1.0), 0.0, 1.0)
	var total := W_ATTACKER * float(attackers) + W_APPROACHER * float(approachers) + W_BRUTE * float(brutes) + W_WOUND * lost + W_BREACHER * float(breachers)
	if breach_hot(seg):
		total += W_HOT
	return total


## The most threatened non-door compound section: {"seg": the section or null, "threat": its score}; nothing (null, 0.0) when every one is
## below 2.0. A section of the lots (id 100 and over) is not the compound's.
func contested() -> Dictionary:
	var best = null
	var top := 0.0
	if active():
		for s in sim.segments:
			if s.kind == sim.DOOR_KIND or int(s.id) >= Lots.FIRST_SEGMENT_ID:
				continue
			var t := section_threat(s)
			if t > top:
				top = t
				best = s
	if best == null or top < CONTESTED_MIN:
		return {"seg": null, "threat": 0.0}
	return {"seg": best, "threat": top}


## Where a gunner covers the section: among `jobs.posts()` the one that reaches at least half of its places with this gun
## (`sim.reach_at(gun, post, true)`, the night's reach there), nearest to the section's middle; with none, the place a mender stands
## (`sim.repair_spot(seg)`). Pure geometry: it does not need an avatar.
func stand_for(seg, gun: Dictionary) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for po in sim.jobs.posts():
		var at := Vector2(po.pos)
		var reach: float = sim.reach_at(gun, at, true)
		var within := 0
		for sl in seg.slots:
			if at.distance_to(Vector2(sl.x, sl.y)) <= reach:
				within += 1
		if seg.slots.is_empty() or within * 2 < seg.slots.size():
			continue
		var d := at.distance_to(seg.center)
		if d < best_d:
			best_d = d
			best = at
	return best if best_d < INF else sim.repair_spot(seg)


# ------------------------------------------------------------------------ the hands at the wall --

func _lead():
	if String(sim.player_id) == "":
		return null
	return sim.avatar.player()


## Why the avatar cannot do anything now ("" when it can).
func _cannot(p) -> String:
	if p.dead or p.turned:
		return "You are gone"
	if p.downed:
		return "You are down"
	if p.away != null:
		return "You are away"
	return ""


## The compound's section with this id, or null (a section of the lots is the lots'; a wall crew mends it).
func _section(id: int):
	if id >= Lots.FIRST_SEGMENT_ID:
		return null
	for s in sim.segments:
		if int(s.id) == id:
			return s
	return null


func _needs_mending(seg) -> bool:
	return seg.state == 3 or float(seg.hp) < float(seg.max_hp) * SOUND


func _pct(seg) -> int:
	return clampi(roundi(float(seg.hp) / maxf(float(seg.max_hp), 1.0) * 100.0), 0, 100)


## Why the avatar cannot mend this section by hand now ("" when it can).
func _mend_refusal(p, seg) -> String:
	var gone := _cannot(p)
	if gone != "":
		return gone
	if not _needs_mending(seg):
		return "The %s is sound" % String(seg.name).to_lower()
	if Vector2(p.x, p.y).distance_to(sim.repair_spot(seg)) > NightData.num("mend.reach"):
		return "Too far from the wall"
	if p.input_move.length() > HANDS_ON or p.input_fire:
		return "Stand still to mend"
	if _danger_near(p):
		return "One of the dead is on you"
	if float(sim.stock.scrap) <= 0.0:
		return "There is no scrap to spare"
	return ""


## Whether one of the dead that is after the compound or a person (not a straggler wandering, not one falling or going home) is within
## `DANGER_R` tiles of this person.
func _danger_near(p) -> bool:
	var me := Vector2(p.x, p.y)
	for z in sim.zombies:
		var st := String(z.state)
		if st != "approach" and st != "attack" and st != "breach" and st != "hunt":
			continue
		if me.distance_to(Vector2(z.x, z.y)) <= DANGER_R:
			return true
	return false


## What to tell the player when the hands have left a wall (`wall_work`'s "why"): {"line": the words (empty: nothing to say, or the key
## that stopped it has its own line), "warn": amber, for a danger or a want}. `wall` is the section's name in a sentence ("red container"),
## `share` the percent of the wall the hands mended since they began.
static func stop_words(why: String, wall: String, share: int) -> Dictionary:
	var mended := " (%d%% mended)" % share if share > 0 else ""
	match why:
		"whole":
			return {"line": "The %s is whole again" % wall, "warn": false}
		"no scrap":
			return {"line": "No scrap left to mend the %s with%s" % [wall, mended], "warn": true}
		"hurt":
			return {"line": "Hurt: stopped mending the %s%s" % [wall, mended], "warn": true}
		"danger":
			return {"line": "The dead are on you: stopped mending the %s%s" % [wall, mended], "warn": true}
		"fired":
			return {"line": "Stopped mending the %s to shoot%s" % [wall, mended], "warn": false}
		"moved":
			return {"line": "You moved: stopped mending the %s%s" % [wall, mended], "warn": false}
		"done":
			return {"line": "Mended the %s: %d%% more" % [wall, share], "warn": false} if share > 0 else {"line": "", "warn": false}
		"You are down", "You are gone", "You are away":
			return {"line": "%s: stopped mending the %s%s" % [why, wall, mended], "warn": true}
	return {"line": "", "warn": false}


## What the avatar could mend from where it stands, nearest first: a compound section (a door too) that is under 95% or down, within
## mend.reach tiles of its mending place (`sim.repair_spot`); [{"kind": "wall", "id" (the section's id as text), "seg", "label" ("Mend the
## Red container (35%)"), "pos", "dist", "ok", "why"}]. The section being mended is "Stop mending the ...". [] with no avatar, while it is
## down, away or gone, and where the rules do not apply.
func wall_candidates() -> Array:
	var p = _lead()
	if p == null or not active() or _cannot(p) != "":
		return []
	var me := Vector2(p.x, p.y)
	var reach: float = NightData.num("mend.reach")
	var out: Array = []
	for s in sim.segments:
		if int(s.id) >= Lots.FIRST_SEGMENT_ID:
			continue
		var spot: Vector2 = sim.repair_spot(s)
		var d := me.distance_to(spot)
		if d > reach:
			continue
		if working == "wall" and mend_seg == int(s.id):
			out.append({"kind": "wall", "id": str(int(s.id)), "seg": int(s.id), "label": "Stop mending the %s" % String(s.name).to_lower(), "pos": spot, "dist": d, "ok": true, "why": ""})
			continue
		if not _needs_mending(s):
			continue
		var why := _mend_refusal(p, s)
		out.append({"kind": "wall", "id": str(int(s.id)), "seg": int(s.id), "label": "Mend the %s (%d%%)" % [s.name, _pct(s)], "pos": spot, "dist": d, "ok": why == "", "why": why})
	out.sort_custom(func(a, b): return float(a.dist) < float(b.dist))
	return out


## The avatar's own hands at a wall, until it is whole (round 22; before, `mend.seconds` of rules time): {"ok", "line", "why", "seconds" (the round
## of the ring: `mend.seconds`)}. Refused with the reason (no scrap to
## spare, too far from the wall, nothing to mend, a hand on the keys or the trigger). The work is any repairer's ((REPAIR_BASE + Building) x
## how well they are x their traits) through the scrap, the section's state follows, Building and morale are credited as for anyone; under
## fire is allowed. Ends on walking, the trigger, a wound, one of the dead at his back (`DANGER_R`), a fall, a whole wall or the scrap gone.
func mend_wall(seg_id: int) -> Dictionary:
	var p = _lead()
	if p == null or not active():
		return {"ok": false, "line": "", "why": "You are not here", "seconds": 0.0}
	var seg = _section(seg_id)
	if seg == null:
		return {"ok": false, "line": "", "why": "There is no such wall", "seconds": 0.0}
	if working == "wall" and mend_seg == int(seg.id):
		return {"ok": true, "line": "Mending the %s." % String(seg.name).to_lower(), "why": "", "seconds": work_left}
	var why := _mend_refusal(p, seg)
	if why != "":
		return {"ok": false, "line": "", "why": why, "seconds": 0.0}
	if working != "":
		stop_mend("stopped")
	working = "wall"
	work_left = NightData.num("mend.seconds")
	mend_seg = int(seg.id)
	_who = String(p.id)
	_hp0 = float(p.hp)
	_mended = 0.0
	_hammer = 0.0
	p.work = "mend"
	p.work_t = 0.0
	p.activity = "Mending the %s" % String(seg.name).to_lower()
	sim.events.append({"type": "wall_work", "on": true, "seg": int(seg.id), "hp": 0.0})
	return {"ok": true, "line": "Mending the %s." % String(seg.name).to_lower(), "why": "", "seconds": work_left}


## Ends the session (E again, the seconds up, a step, a shot, a wound...): tells what it mended.
func stop_mend(why: String = "") -> void:
	if working == "":
		return
	var id := mend_seg
	var got := _mended
	var p = _lead()
	if p != null and p.work == "mend":
		p.work = ""
		p.work_t = 0.0
	_forget_session()
	sim.events.append({"type": "wall_work", "on": false, "seg": id, "hp": got, "why": why})


func _forget_session() -> void:
	working = ""
	work_left = 0.0
	mend_seg = -1
	_who = ""
	_hp0 = 0.0
	_mended = 0.0
	_hammer = 0.0


## Every step, after the people and the dead have moved (and before the radio reads the step): the session counts its seconds, mends, and
## ends for the reasons above. The pose is kept (the people loop has just cleared `Person.work`).
func after_people(dt: float) -> void:
	if working == "":
		return
	var p = _lead()
	if p == null or not active():
		stop_mend("no avatar")
		return
	if _who != String(p.id):
		stop_mend("another player")
		return
	var gone := _cannot(p)
	if gone != "":
		stop_mend(gone)
		return
	var seg = _section(mend_seg)
	if seg == null:
		stop_mend("the wall is gone")
		return
	_hp0 = maxf(_hp0, float(p.hp))
	var why := ""
	if p.input_move.length() > HANDS_ON or Vector2(p.x, p.y).distance_to(sim.repair_spot(seg)) > NightData.num("mend.reach") + 0.5:
		why = "moved"
	elif p.input_fire:
		why = "fired"
	elif float(p.hp) < _hp0 - 0.001:
		why = "hurt"
	elif _danger_near(p):
		why = "danger"
	elif seg.hp >= seg.max_hp:
		why = "whole"
	elif float(sim.stock.scrap) <= 0.0:
		why = "no scrap"
	if why != "":
		stop_mend(why)
		return
	var rate: float = (sim.REPAIR_BASE + float(p.skills.Building)) * sim.perf(p) * sim.traits.mult(p, "repair")
	var done: float = sim.supplies.repair_budget(dt * rate)
	if done > 0.0:
		var before: float = seg.hp
		var was_down: bool = seg.state == 3
		sim._repair_segment(seg, done)
		var gain: float = seg.hp - before
		_mended += gain
		sim.skills.credit(p, "mended", gain)
		if seg.hp >= seg.max_hp and gain > 0.0:
			sim.morale.on_repaired(p)
		if was_down and seg.state != 3:
			sim.radio.night.shut_again(seg)    # (the News says so, once: the call's own watch of the wall finds the line made)
	_hammer -= dt
	if _hammer <= 0.0:
		_hammer = HAMMER_EVERY
		sim.events.append({"type": "hammer", "x": p.x, "y": p.y})
		var toward: Vector2 = (seg.center - Vector2(p.x, p.y)).normalized() if Vector2(p.x, p.y).distance_to(seg.center) > 0.5 else Vector2.ZERO
		sim.fx.hit_material(p.x + toward.x * 0.7, p.y + toward.y * 0.7, "metal")
	work_left -= dt
	if work_left <= EPS:
		work_left += maxf(NightData.num("mend.seconds"), 1.0)    # (the ring comes round again: one press goes on, round 22)
	var to: Vector2 = seg.center - Vector2(p.x, p.y)
	if to.length() > 0.3:
		p.facing = sim.facing_of(to.x, to.y, String(p.facing))
	p.work = "mend"
	p.work_t = NightData.num("mend.seconds") - work_left
	p.activity = "Mending the %s" % String(seg.name).to_lower()


# --------------------------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {"warned": warned.duplicate(), "hot_marks": hot_marks.duplicate()}


## The marks come back (a session never does: it loads as none).
func load_state(d: Dictionary) -> void:
	start()
	var w = d.get("warned", {})
	if typeof(w) == TYPE_DICTIONARY:
		for k in w:
			warned[int(k)] = int(w[k])
	var h = d.get("hot_marks", {})
	if typeof(h) == TYPE_DICTIONARY:
		for k in h:
			hot_marks[int(k)] = int(h[k])
