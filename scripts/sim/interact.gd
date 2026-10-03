## What the avatar uses where it stands (round 18, slice 2 "Home"): E talks to a person, takes a night post, works the bench with its
## own hands and reads a car's fuel. Rules only: the views ask `candidates()` / `best()` for the prompt and `use()` for the key, and
## draw what comes back (scripts/ui/talk_card.gd, scripts/render/overlay_node.gd). Everything is behind avatar mode
## (`sim.player_id != ""`): with no avatar nothing here finds anything, takes anything or runs (the harness, the tests and
## Orientation Day play as they did).
##
## CANDIDATES. Within reach of the avatar's feet, nearest first, and a person beats a post beats the bench beats a car on a tie (two
## things within TIE tiles of each other): a person within TALK_REACH, a post within POST_REACH of its spot, the bench within
## BENCH_REACH, a parked car within CAR_REACH of the middle of its bay. A candidate that cannot be used now is still listed, with its
## reason (`ok` false, `why`), so the prompt can say so. Nothing at all while the avatar is down, away (on a trip) or gone.
## TALKING. `talk_to` is a conversation, not a command: the person says what is the matter (`needs_of`, in a fixed order: bleeding,
## fever, starving or parched, hungry or thirsty, shaken, no job in a settlement game, out of ammunition) or what they are doing, turns
## to face the avatar, and the first word of the game day earns TALK_TRUST of their trust (once per person per day).
## A POST. `take_post` puts the avatar on a night post of the wall: its nominal holder swaps posts with the avatar (the avatar's old
## post is theirs now), unless the posts are manned and the holder stands within HOLDER_AT of the post (a fight is no time to be
## moved); the avatar's feet are put on the spot, and while it stays within POST_LEAVE of it the aim is steadier (`brace_factor`,
## avatar.gd `spread_of`). Walking away, a fall, a new player or the post going away ends it; the alarm does not.
## THE BENCH. `work_bench` is the avatar's own hands at the worktable for BENCH_SECONDS of rules time: the workshop (workshop.gd)
## counts the avatar among those at work while `working == "bench"`, at BENCH_MULT of the scrap an hour its Building skill gives.
## `Person.work` and `work_t` are set each step so that the drawing's hammer pose shows. Walking, firing, a wound, a fall, the end of the
## scrap or of the room for ammunition, the dusk, all end it.
##
## Events this module adds to sim.events:
##   {"type": "talk", "who": id, "line": the first-person status line}
##   {"type": "interact", "kind": "person" | "post" | "bench" | "vehicle", "id", "ok"}   (use())
##   {"type": "post_taken", "post": id, "who": the player's id, "held_by_swap": id or ""}
##   {"type": "post_left", "post": id, "why"}
##   {"type": "bench_work", "on": true} and {"type": "bench_work", "on": false, "ammo": made, "scrap": used, "why"}  (why: "done",
##       "moved", "fired", "hurt", "stopped", or the workshop's reason)
## Saved: the post, the session (never resumed: it loads as none), and the days of the last word with each person.
extends RefCounted

const Convoy := preload("res://scripts/sim/convoy.gd")

## Tiles from the avatar's feet (for a car, to the middle of its bay).
const TALK_REACH := 1.9
const POST_REACH := 1.4
const BENCH_REACH := 1.8
const CAR_REACH := 3.0
## The talk card ends when the avatar is farther than this from the person (the view reads it).
const TALK_LEAVE := 3.5
## Trust earned by the first word of the day with a person.
const TALK_TRUST := 1.0
## The spread of a shot while standing on a post, as a share of the usual.
const BRACE := 0.7
## Rules seconds a bench session lasts (36 game minutes at the normal pace), and what the avatar's hands make as a share of the
## scrap an hour the same person's work would.
const BENCH_SECONDS := 12.0
const BENCH_MULT := 1.5
## Walking farther than this from the post (tiles) ends the hold.
const POST_LEAVE := 0.8
## Two candidates this close in distance are a tie, and the kind decides (a person, a post, the bench, a car).
const TIE := 0.3
## With the posts manned, a holder this close to the post is at it.
const HOLDER_AT := 1.5
## How far from a post's own spot the avatar's feet may be put to stand on open ground (the walkway is one tile wide).
const STAND_RADIUS := 0.5
## No stock of ammunition under this many rounds counts as having some (with the magazine empty: "Out of ammo").
const AMMO_LOW := 20.0
## The walking input this long is a hand on the keys.
const HANDS_ON := 0.25
const EPS := 1.0e-6
const RANK := {"person": 0, "post": 1, "bench": 2, "vehicle": 3}

var sim
## The post the avatar is on ("" none), what it is doing with its hands ("bench" or ""), the rules seconds of the session left, and
## the day of the last word with each person (person id to day).
var posted := ""
var working := ""
var work_left := 0.0
var talked := {}
## What the session in hand has made so far (the workshop adds as it goes; reported when it ends).
var made_scrap := 0.0
var made_ammo := 0.0
## The id of the player the post or the session belongs to, and their health when the session began.
var _who := ""
var _hp0 := 0.0


func setup(s) -> void:
	sim = s


## A new run: nothing is used, nobody has been spoken to.
func start() -> void:
	posted = ""
	working = ""
	work_left = 0.0
	talked = {}
	made_scrap = 0.0
	made_ammo = 0.0
	_who = ""
	_hp0 = 0.0


# ------------------------------------------------------------------- the person --

## The avatar's person, or null (no avatar).
func _lead():
	if String(sim.player_id) == "":
		return null
	return sim.avatar.player()


func _person(id: String):
	for q in sim.people:
		if String(q.id) == id:
			return q
	return null


## Why the avatar cannot do anything now ("" when it can).
func _cannot(p) -> String:
	if p.dead or p.turned:
		return "You are gone"
	if p.downed:
		return "You are down"
	if p.away != null:
		return "You are away"
	return ""


# -------------------------------------------------------------------- candidates --

## What the avatar could use from where it stands, nearest first (a person beats a post beats the bench beats a car within TIE
## tiles): [{"kind": "person" | "post" | "bench" | "vehicle", "id", "label" ("Talk to Dez", "Take the gate post", "Work the bench",
## "Check the pickup's fuel"), "pos": Vector2, "dist", "ok", "why"}]. [] with no avatar, while it is down or away.
func candidates() -> Array:
	var p = _lead()
	if p == null or _cannot(p) != "":
		return []
	var me := Vector2(p.x, p.y)
	var out: Array = []
	for q in sim.people:
		if q == p or q.dead or q.turned or q.away != null:
			continue
		var at := Vector2(q.x, q.y)
		var d := me.distance_to(at)
		if d <= TALK_REACH:
			out.append({"kind": "person", "id": String(q.id), "label": "Talk to %s" % q.first, "pos": at, "dist": d, "ok": true, "why": ""})
	for po in sim.jobs.posts():
		var at := Vector2(po.pos)
		var d := me.distance_to(at)
		if d > POST_REACH:
			continue
		var id := String(po.id)
		if posted == id:
			out.append({"kind": "post", "id": id, "label": "Leave the %s post" % _post_short(po), "pos": at, "dist": d, "ok": true, "why": ""})
		else:
			var why := _post_refusal(p, po)
			out.append({"kind": "post", "id": id, "label": "Take the %s post" % _post_short(po), "pos": at, "dist": d, "ok": why == "", "why": why})
	var bench: Vector2 = sim.workshop.bench()
	if bench != Vector2.ZERO and me.distance_to(bench) <= BENCH_REACH:
		if working == "bench":
			out.append({"kind": "bench", "id": "bench", "label": "Stop working the bench", "pos": bench, "dist": me.distance_to(bench), "ok": true, "why": ""})
		else:
			var why: String = sim.workshop.why_not_hand_craft(p)
			out.append({"kind": "bench", "id": "bench", "label": "Work the bench", "pos": bench, "dist": me.distance_to(bench), "ok": why == "", "why": why})
	for v in sim.vehicles.parked():
		var at: Vector2 = Convoy.bay(int(v.get("spot", -1)))
		var d := me.distance_to(at)
		if d <= CAR_REACH:
			out.append({"kind": "vehicle", "id": String(v.id), "label": "Check the %s's fuel" % String(sim.vehicles.name_of(String(v.id))).to_lower(), "pos": at, "dist": d, "ok": true, "why": ""})
	return _ordered(out)


## The nearest first, but within TIE tiles of the nearest left, the kind that ranks first (a person, a post, the bench, a car).
func _ordered(list: Array) -> Array:
	var left: Array = list.duplicate()
	var out: Array = []
	while not left.is_empty():
		var nearest := 0
		for i in left.size():
			if float(left[i].dist) < float(left[nearest].dist):
				nearest = i
		var cut: float = float(left[nearest].dist) + TIE
		var pick := nearest
		for i in left.size():
			if float(left[i].dist) > cut:
				continue
			var ri := int(RANK[String(left[i].kind)])
			var rp := int(RANK[String(left[pick].kind)])
			if ri < rp or (ri == rp and float(left[i].dist) < float(left[pick].dist)):
				pick = i
		out.append(left[pick])
		left.remove_at(pick)
	return out


## The best candidate, or {} (the view keeps its prompt on it with a little hysteresis so that it does not flicker).
func best() -> Dictionary:
	var list := candidates()
	return list[0] if not list.is_empty() else {}


## A fresh candidate of the same kind and id as `cand` (or the best, with none given): {} when it is no longer in reach.
func _fresh(cand: Dictionary) -> Dictionary:
	var list := candidates()
	if cand.is_empty():
		return list[0] if not list.is_empty() else {}
	for c in list:
		if String(c.kind) == String(cand.get("kind", "")) and String(c.id) == String(cand.get("id", "")):
			return c
	return {}


## Does what E does with `cand` (or the best candidate): {"ok", "kind", "id", "line", "why", ...what the kind adds}. A held post is
## left and a bench session in hand is stopped (`left`, `stopped`). Tells the views (`interact`); nothing in reach gives
## {"ok": false, "why": "Nothing here to use"} and no event.
func use(cand: Dictionary = {}) -> Dictionary:
	var c := _fresh(cand)
	if c.is_empty():
		return {"ok": false, "kind": "", "id": "", "line": "", "why": "Nothing here to use"}
	var kind := String(c.kind)
	var id := String(c.id)
	var r: Dictionary = {}
	match kind:
		"person":
			r = talk_to(_person(id))
		"post":
			if posted == id:
				var po: Dictionary = sim.jobs.post(id)
				leave_post("left")
				r = {"ok": true, "line": "Off the %s post." % _post_short(po), "why": "", "left": true}
			else:
				r = take_post(id)
		"bench":
			if working == "bench":
				stop_work("stopped")
				r = {"ok": true, "line": "Stopped working the bench.", "why": "", "stopped": true}
			else:
				r = work_bench()
		"vehicle":
			r = check_vehicle(id)
	r["kind"] = kind
	r["id"] = id
	if not r.has("why"):
		r["why"] = ""
	if not r.has("line"):
		r["line"] = ""
	sim.events.append({"type": "interact", "kind": kind, "id": id, "ok": bool(r.get("ok", false))})
	return r


# -------------------------------------------------------------------------- talk --

## The avatar talks to a person: {"ok", "who", "line" (their first-person status line: the first need's, else what they are doing),
## "needs", "trust", "tone", "gain" (TALK_TRUST for the day's first word, else 0), "why"}. They turn to face the avatar. Refused only
## for the avatar itself and for the gone ("Nobody there"). Emits `talk`.
func talk_to(p) -> Dictionary:
	var lead = _lead()
	if p == null or p == lead or p.dead or p.turned or p.away != null:
		return {"ok": false, "who": String(p.id) if p != null else "", "line": "", "why": "Nobody there", "needs": [], "trust": 0.0, "tone": "", "gain": 0.0}
	var id := String(p.id)
	var gain := 0.0
	if int(talked.get(id, 0)) != int(sim.day):
		talked[id] = int(sim.day)
		# (what trust can still rise by: at 100 the word earns nothing, and says so)
		gain = minf(TALK_TRUST, 100.0 - float(p.trust))
		if gain > 0.0:
			sim.radio.add_trust(p, gain, "Had a word with you")
		else:
			gain = 0.0
	if lead != null and not p.moving:
		var to := Vector2(lead.x - p.x, lead.y - p.y)
		if to.length() > 0.05:
			p.facing = sim.facing_of(to.x, to.y, String(p.facing))
	var needs := needs_of(p)
	var line := String(needs[0].line) if not needs.is_empty() else _activity_line(p)
	sim.events.append({"type": "talk", "who": id, "line": line})
	return {"ok": true, "who": id, "line": line, "why": "", "needs": needs, "trust": sim.radio.trust_of(p), "tone": sim.radio.tone_of(p), "gain": gain}


## What they are doing, as a sentence ("Holding the gate.").
func _activity_line(p) -> String:
	var a := String(p.activity).strip_edges()
	if a == "":
		return "Just here."
	return a if a.ends_with(".") or a.ends_with("!") or a.ends_with("?") else a + "."


## What is the matter with a person, in this order: bleeding, fever, starving or parched, hungry or thirsty, shaken, no job in a
## settlement game by day, out of ammunition: [{"id", "text" (for the card), "line" (what they say), "page" (the radio page that
## can help, "" for none)}].
func needs_of(p) -> Array:
	var out: Array = []
	if p == null or p.dead or p.turned:
		return out
	if p.bleeding > 0.0:
		out.append({"id": "bleeding", "text": "Bleeding: needs the infirmary", "line": "I'm bleeding. I need the infirmary.", "page": ""})
	var stage: String = sim.medical.infection_stage(p)
	if stage == "delirious":
		out.append({"id": "infection", "text": "Delirious: needs the infirmary", "line": "I can't think straight. Get me to the infirmary.", "page": ""})
	elif stage == "feverish":
		out.append({"id": "infection", "text": "Feverish: needs the infirmary", "line": "I'm burning up. I need the infirmary.", "page": ""})
	elif sim.storyteller.is_sick(p):
		out.append({"id": "fever", "text": "Sick with a fever: needs rest", "line": "I've a fever. I need to lie down.", "page": ""})
	if p.hunger_h >= sim.supplies.STARVING_H:
		out.append({"id": "starving", "text": "Starving: needs food", "line": "I'm starving. I need food.", "page": ""})
	if p.thirst_h >= sim.supplies.PARCHED_H:
		out.append({"id": "parched", "text": "Parched: needs water", "line": "I'm parched. I need water.", "page": ""})
	if p.hunger_h >= sim.supplies.HUNGRY_H and p.hunger_h < sim.supplies.STARVING_H:
		out.append({"id": "hungry", "text": "Hungry", "line": "I'm hungry.", "page": ""})
	if p.thirst_h >= sim.supplies.THIRSTY_H and p.thirst_h < sim.supplies.PARCHED_H:
		out.append({"id": "thirsty", "text": "Thirsty", "line": "I'm thirsty.", "page": ""})
	var mood: String = sim.morale.mood(p)
	if mood == "Shaken":
		out.append({"id": "shaken", "text": "Shaken: needs a quiet hour", "line": "I'm shaken. I need a quiet hour.", "page": ""})
	elif mood == "Breaking":
		out.append({"id": "shaken", "text": "Breaking: needs a quiet hour", "line": "I can't take much more. I need a quiet hour.", "page": ""})
	if not p.player and sim.recruits.small and sim.jobs.job_of(p) == "" and sim.phase == "day" and not sim.posts_manned():
		out.append({"id": "no_job", "text": "No job: nothing to do. Give them one", "line": "I've nothing to do. Give me a job.", "page": "jobs"})
	if not p.gun.get("melee", false) and p.mag <= 0 and float(sim.stock.ammo) < AMMO_LOW:
		out.append({"id": "ammo", "text": "Out of ammo", "line": "I'm out of ammo.", "page": ""})
	return out


# -------------------------------------------------------------------------- posts --

## "gate" for "The gate": a post's name in a sentence.
func _post_short(po: Dictionary) -> String:
	return String(po.get("name", po.get("id", "post"))).to_lower().trim_prefix("the ")


## Whoever holds the post on the roster (alive, and not `except`), or null. The dead hold nothing.
func _holder_of(post_id: String, except):
	for q in sim.people:
		if q == except or q.dead or q.turned:
			continue
		if String(sim.jobs.post_ids.get(String(q.id), "")) == post_id:
			return q
	return null


## Why the post cannot be taken now ("" when it can): the posts are manned and its holder is at it.
func _post_refusal(p, po: Dictionary) -> String:
	var holder = _holder_of(String(po.id), p)
	if holder == null or holder.away != null or holder.downed or not sim.posts_manned():
		return ""
	if Vector2(holder.x, holder.y).distance_to(Vector2(po.pos)) <= HOLDER_AT:
		return "%s is at the post" % holder.first
	return ""


## The place nearest to `at` (within STAND_RADIUS) where the avatar's box fits: the walkway is one tile wide and a post's spot may be a
## hair inside its rail.
func _stand_spot(at: Vector2) -> Vector2:
	if not sim.avatar._blocked(at.x, at.y):
		return at
	var best := at
	var best_d := 1.0e9
	var n := int(STAND_RADIUS / 0.05)
	for iy in range(-n, n + 1):
		for ix in range(-n, n + 1):
			var q := at + Vector2(float(ix), float(iy)) * 0.05
			var d := q.distance_to(at)
			if d > STAND_RADIUS or d >= best_d or sim.avatar._blocked(q.x, q.y):
				continue
			best = q
			best_d = d
	return best


## Puts the avatar on the post: {"ok", "line" ("On the gate post. Steadier here."), "why", "held_by_swap" (the holder's id, or "")}.
## The holder swaps posts with the avatar; refused when too far from the post, or the posts are manned and the holder is at it.
func take_post(post_id: String) -> Dictionary:
	var p = _lead()
	if p == null:
		return {"ok": false, "line": "", "why": "You are not here", "held_by_swap": ""}
	var gone := _cannot(p)
	if gone != "":
		return {"ok": false, "line": "", "why": gone, "held_by_swap": ""}
	var po: Dictionary = sim.jobs.post(post_id)
	if po.is_empty():
		return {"ok": false, "line": "", "why": "There is no such post", "held_by_swap": ""}
	var at := Vector2(po.pos)
	if posted == post_id:
		return {"ok": true, "line": "On the %s post. Steadier here." % _post_short(po), "why": "", "held_by_swap": ""}
	if Vector2(p.x, p.y).distance_to(at) > POST_REACH:
		return {"ok": false, "line": "", "why": "Too far from the post", "held_by_swap": ""}
	var why := _post_refusal(p, po)
	if why != "":
		return {"ok": false, "line": "", "why": why, "held_by_swap": ""}
	if posted != "":
		leave_post("took another post")
	var mine := String(sim.jobs.post_ids.get(String(p.id), ""))
	var holder = _holder_of(post_id, p)
	if holder != null:
		sim.jobs.post_ids[String(holder.id)] = mine
		holder.goal_key = ""
	sim.jobs.post_ids[String(p.id)] = post_id
	p.goal_key = ""
	var spot := _stand_spot(at)
	p.x = spot.x
	p.y = spot.y
	p.moving = false
	p.path = []
	p.facing = String(po.get("face", p.facing))
	posted = post_id
	_who = String(p.id)
	var swapped := String(holder.id) if holder != null else ""
	sim.events.append({"type": "post_taken", "post": post_id, "who": String(p.id), "held_by_swap": swapped})
	return {"ok": true, "line": "On the %s post. Steadier here." % _post_short(po), "why": "", "held_by_swap": swapped}


## Off the post (walking away, E again, a fall): says so. Nothing happens when the avatar is on none.
func leave_post(why: String = "") -> void:
	if posted == "":
		return
	var id := posted
	posted = ""
	sim.events.append({"type": "post_left", "post": id, "why": why})


## The steadier aim of a person on a post who is standing still: BRACE; 1.0 for anyone else and for the avatar off its post or moving.
func brace_factor(p) -> float:
	if posted != "" and p != null and p.player and not p.moving:
		return BRACE
	return 1.0


# ------------------------------------------------------------------------- bench --

## The avatar's own hands at the worktable for BENCH_SECONDS: {"ok", "line", "why", "seconds"}. Refused with the workshop's reason
## (`why_not_hand_craft`: night, no scrap to spare, the ammo at its target), when too far from the bench, or with a hand on the keys
## or the trigger. Emits `bench_work` on.
func work_bench() -> Dictionary:
	var p = _lead()
	if p == null:
		return {"ok": false, "line": "", "why": "You are not here", "seconds": 0.0}
	if working == "bench":
		return {"ok": true, "line": "Working the bench.", "why": "", "seconds": work_left}
	var why: String = sim.workshop.why_not_hand_craft(p)
	if why == "" and Vector2(p.x, p.y).distance_to(sim.workshop.bench()) > BENCH_REACH:
		why = "Too far from the bench"
	if why == "" and (p.input_move.length() > HANDS_ON or p.input_fire):
		why = "Stand still to work the bench"
	if why != "":
		return {"ok": false, "line": "", "why": why, "seconds": 0.0}
	working = "bench"
	work_left = BENCH_SECONDS
	made_scrap = 0.0
	made_ammo = 0.0
	_who = String(p.id)
	_hp0 = float(p.hp)
	p.work = "bench"
	p.work_t = 0.0
	p.activity = "Working the bench"
	sim.events.append({"type": "bench_work", "on": true})
	return {"ok": true, "line": "Working the bench.", "why": "", "seconds": BENCH_SECONDS}


## Ends the session (a view's E again, the end of the twelve seconds, a step, a shot, a wound...): tells what it made.
func stop_work(why: String = "") -> void:
	if working == "":
		return
	var scrap := made_scrap
	var ammo := made_ammo
	working = ""
	work_left = 0.0
	made_scrap = 0.0
	made_ammo = 0.0
	var p = _lead()
	if p != null and p.work == "bench":
		p.work = ""
		p.work_t = 0.0
	sim.events.append({"type": "bench_work", "on": false, "ammo": ammo, "scrap": scrap, "why": why})


## The workshop tells what it made for the avatar this step (it does the crafting: workshop.gd `update`).
func bench_made(scrap: float, ammo: float) -> void:
	made_scrap += scrap
	made_ammo += ammo


# ---------------------------------------------------------------------- vehicles --

## What the tank and the car are like, in words: {"ok", "line" ("Pickup: fuel 14 in the tank, about 4 hours of driving; 82% sound"), "why"}.
## The fuel is the fleet's one store; the hours are what the kind burns. No effect.
func check_vehicle(vehicle_id: String) -> Dictionary:
	var v: Dictionary = sim.vehicles.vehicle(vehicle_id)
	if v.is_empty():
		return {"ok": false, "line": "", "why": "There is no such vehicle"}
	var name: String = sim.vehicles.name_of(vehicle_id)
	if String(v.get("state", "parked")) != "parked":
		return {"ok": false, "line": "", "why": "The %s is out" % name.to_lower()}
	var k: Dictionary = sim.vehicles.kind_of(vehicle_id)
	var fuel := float(sim.vehicles.fuel)
	var burn := maxf(float(k.get("burn", 3.0)), 0.001)
	var full := maxf(float(k.get("hp", 100.0)), 1.0)
	var sound := clampi(roundi(100.0 * float(v.get("hp", full)) / full), 0, 100)
	var tank := ""
	if fuel < 0.05:
		tank = "the tank is empty"
	else:
		var hours := roundi(fuel / burn)
		var drive := "less than an hour of driving" if hours < 1 else "about %d hour%s of driving" % [hours, "" if hours == 1 else "s"]
		tank = "fuel %s in the tank, %s" % [str(snappedf(fuel, 0.1)).trim_suffix(".0"), drive]
	return {"ok": true, "line": "%s: %s; %d%% sound" % [name, tank, sound], "why": ""}


# ------------------------------------------------------------------------ update --

## Every step, after the people have moved (and before the radio reads the step): a post is let go when the avatar walks away, falls
## or is not the same person any more; the bench session counts its seconds and ends for the reasons above, and keeps the work pose.
func update(dt: float) -> void:
	var p = _lead()
	if p == null:
		leave_post("no avatar")
		stop_work("no avatar")
		return
	if (posted != "" or working != "") and _who == "":
		_who = String(p.id)    # (a post kept by a save: it belongs to whoever is the player now)
	if (posted != "" or working != "") and _who != String(p.id):
		leave_post("another player")
		stop_work("another player")
		return
	var gone := _cannot(p)
	if gone != "":
		leave_post(gone)
		stop_work(gone)
		return
	if posted != "":
		var po: Dictionary = sim.jobs.post(posted)
		if po.is_empty():
			leave_post("the post is gone")
		elif Vector2(p.x, p.y).distance_to(Vector2(po.pos)) > POST_LEAVE:
			leave_post("walked away")
	if working == "bench":
		_bench_step(p, dt)


## One step of the session: the reasons it ends, else the seconds run down and the pose is kept (the people loop has just cleared
## `Person.work` and set the avatar's own activity).
func _bench_step(p, dt: float) -> void:
	_hp0 = maxf(_hp0, float(p.hp))
	var why := ""
	if p.input_move.length() > HANDS_ON:
		why = "moved"
	elif p.input_fire:
		why = "fired"
	elif float(p.hp) < _hp0 - 0.001:
		why = "hurt"
	else:
		why = sim.workshop.why_not_hand_craft(p)
		if why == "" and not sim.workshop.can_make():
			why = "the ammo is at its target (%d)" % int(sim.workshop.target())
	if why == "":
		work_left -= dt
		if work_left <= EPS:
			why = "done"
	if why != "":
		stop_work(why)
		return
	p.work = "bench"
	p.work_t = BENCH_SECONDS - work_left
	p.activity = "Working the bench"
	var to: Vector2 = sim.workshop.bench() - Vector2(p.x, p.y)
	if to.length() > 0.3:
		p.facing = sim.facing_of(to.x, to.y, String(p.facing))


# -------------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {"posted": posted, "working": working, "work_left": work_left, "talked": talked.duplicate()}


## The post is kept when the avatar still stands at it; a session is never resumed; the words are kept for people who exist.
func load_state(d: Dictionary) -> void:
	start()
	var tk = d.get("talked", {})
	if tk is Dictionary:
		for k in tk:
			var v = tk[k]
			if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v)) and float(v) >= 1.0 and _person(String(k)) != null:
				talked[String(k)] = int(v)
	var po = d.get("posted", "")
	if typeof(po) != TYPE_STRING or String(po) == "":
		return
	var lead = _lead()
	var post: Dictionary = sim.jobs.post(String(po))
	if lead == null or post.is_empty() or _cannot(lead) != "":
		return
	if Vector2(lead.x, lead.y).distance_to(Vector2(post.pos)) <= POST_LEAVE:
		posted = String(po)
		_who = String(lead.id)
