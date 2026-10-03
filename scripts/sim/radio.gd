## The radio (round 17, slice 1): the player asks, the community answers. A set that reaches everyone at the base and,
## in a place, the squad; no views here, only rules (the dock, the News card and the call cards read them).
##
## ASKING. The player is one survivor among others; what they say over the radio is a request (`request`), never a
## command. There are six verbs (`VERBS`): come with me, hold here, cover me, search that, go back, to the walls. A
## request is refused ONLY for a clear reason the dock can show (`willingness`): the person is down, gone, away, in a
## breakdown (these cannot be argued with); bleeding, feverish, starving, parched or shaken; or busy with something
## critical (tending a patient, the only one at the infirmary with a patient, at the radio for the noon hour, the lookout
## half an hour before the forecast, heading out with a party). "Go back" and "to the walls" are asked of anyone on their
## feet. Nothing is random. TRUST in the player (`Person.trust`, 0 to 100, 55 to begin with) sets how fast and in what voice
## they answer: half a second and a willing "On my way." from 80 up, up to four seconds and a doubtful "...if you say so."
## from 20 down. Insisting (`args.insist`) overrides a refusal that is not a hard one, at a cost of trust and a blow to the
## mood. Asking costs nothing; trust is earned by what comes of it (`on_trip_led`) and lost by it (`on_hurt_following`).
##
## STANCES. A request that is agreed to takes effect after its delay: follow (a goal within 2.2 tiles of the player, facing
## where they aim), hold (a spot), cover (4 to 5 tiles behind the player's aim), search (a point: the container the squad
## goes to). `Sim._goal_for` asks `stance_goal`; a person with a stance still shoots what they see (the NPCs' own `_combat`)
## and is drafted so that the day's rules let them. A stance ends when the person goes down, is lost, goes away, breaks
## down or is asked to go back or to the walls, and with the alarm. "Go back" is the job again, "to the walls" the night post.
##
## NEWS AND CALLS. A log of what the radio heard (`news`, 60 entries, saved) and calls that wait for an answer: a call has
## options (`[{"id", "label"}]`), a default and a time (`ttl_min` game minutes) after which the default is taken. In avatar
## mode (`sim.player_id != ""`) the radio makes its entries by itself from the step's events and state, at the end of
## `Sim.update`: a call when a wall section is under attack by the dead (hold; send reinforcements: everyone free to a post
## near it; fall back to the school: the people of that section's posts), a call when someone has a fever (treat them; keep
## them apart: off work, resting at a bed of the bunks, `medical.keep_apart`; and, for an infection with no medicine to treat it,
## send them out through the gate), a log entry for every card of the storyteller (the card itself stays the storyteller's), for every arrival
## and for a succession; the community's ideas (round 20, kind "idea", yes / later / no) are raised and answered by initiative.gd
## through `raise_call` and `_carry_out`. With no avatar (the old game, the harness, the tests) none of that happens.
##
## THE ALARM is the call to arms: `alarm(true)` puts everyone at their posts now (by day too, in any start) until
## `alarm(false)` or the dawn, and ends whatever stances there were.
##
## Events this module adds to sim.events: {"type": "radio_line", "who", "verb", "ok", "line", "tone"} when someone is asked,
## {"type": "stance", "who", "stance"} when a request takes effect, {"type": "alarm", "on"}, {"type": "radio_answered",
## "id", "option", "by_default"} when a call is settled.
extends RefCounted

const VERBS := ["come", "hold", "cover", "search", "back", "post"]
const VERB_NAMES := {"come": "Come with me", "hold": "Hold here", "cover": "Cover me", "search": "Search that", "back": "Go back", "post": "To the walls"}
## The stance each verb that asks for one gives.
const STANCE_OF := {"come": "follow", "hold": "hold", "cover": "cover", "search": "search"}
## What a refusal says they cannot do.
const CANT := {"come": "come", "hold": "hold", "cover": "cover you", "search": "search"}
## What they say, by verb and tone.
const LINES := {
	"come": {"willing": "On my way.", "grudging": "Fine. Coming.", "doubtful": "...if you say so."},
	"hold": {"willing": "Holding here.", "grudging": "Fine. I'll hold.", "doubtful": "...if you say so."},
	"cover": {"willing": "I've got your back.", "grudging": "Fine. Covering you.", "doubtful": "...if you say so."},
	"search": {"willing": "Searching it.", "grudging": "Fine. I'll look.", "doubtful": "...if you say so."},
	"back": {"willing": "Heading back.", "grudging": "Fine. Back to it.", "doubtful": "...if you say so."},
	"post": {"willing": "To the wall.", "grudging": "Fine. To the wall.", "doubtful": "...if you say so."},
}

## Trust: where it starts, the answer's delay (seconds) from the most trusted to the least, and the tones.
const TRUST_START := 55.0
const TRUST_FAST := 80.0
const TRUST_SLOW := 20.0
const DELAY_FAST := 0.5
const DELAY_SLOW := 4.0
const TONE_WILLING := 50.0
const TONE_GRUDGING := 30.0
## What insisting costs: trust, and a blow to the mood.
const INSIST_COST := 6.0
const INSIST_MORALE := -4.0
## Someone hurt while following a request this recently (seconds of the radio's time) costs the player this much trust;
## a person who comes back safe from a trip the player led is worth this much.
const HURT_COST := 3.0
const HURT_WINDOW_S := 120.0
const TRIP_BONUS := 2.0
const MAX_REASONS := 6
const MAX_NEWS := 60
## The mark the radio puts on an event it has read.
const READ_KEY := "radio_read"

## Stances: a follower stands within FOLLOW_R of the leader (and not on top of them: FOLLOW_MIN), at a place FOLLOW_SLOT
## behind them when they have to walk; the cover stands COVER_BACK behind the aim, COVER_APART from the next one.
const FOLLOW_R := 2.2
const FOLLOW_MIN := 0.9
const FOLLOW_SLOT := 1.7
const FOLLOW_SPREAD := 0.9
const COVER_BACK := 4.5
const COVER_APART := 1.4
## How fast people walk (tiles a second), and how fast a follower or a cover hurries when the leader has got this far ahead
## of them (the avatar walks at 3.2).
const WALK_SPEED := 3.0
const HURRY_SPEED := 3.7
const HURRY_FOLLOW := 3.2
const HURRY_COVER := 7.0

## The calls: how long they wait (game minutes), and what keeping a sick one apart costs.
const ATTACK_TTL_MIN := 30.0
const SICK_TTL_MIN := 60.0
const APART_MORALE := -4.0
## The alarm's threat is set this far ahead (game minutes).
const ALARM_FAR_MIN := 40.0 * 24.0 * 60.0
## The radio hour of the storyteller and the lookout's forecast, as the radio knows them (hours before and after).
const RADIO_FROM_H := 11.5
const RADIO_TO_H := 12.5
const LOOKOUT_BEFORE_H := 0.5

var sim
## The log, oldest first: [{"id", "t" (sim.clock_min), "day", "hour", "kind", "text", "sub", "options": [{"id", "label"}],
## "default", "due" (sim.clock_min), "answered" ("" while it waits), "by_default", "result", "at" (a Vector2 or null),
## "data" (a plain dictionary the kind keeps what it needs in)}].
var news: Array = []
## The id of the newest line the player has read (the News panels of the yard and of a place both read and set it: what is read in
## one is read in the other). Not saved: a game that is loaded starts with everything unread, as a panel always did.
var news_seen := 0
## Requests that have been agreed to and are waiting for their delay: [{"who", "verb", "at", "left" (seconds), "insist"}].
var pending: Array = []
var alarm_on := false
## Why each person trusts the player as they do, newest last: person id to [{"why", "delta", "day"}].
var reasons := {}
## What `add_trust` has really moved for each person (person id to the sum of the changes, after the 0 to 100 limits) since the
## radio began: not saved. A place's own radio is a new one for each trip, and the trip's report (`RaidRun.result`) reads what the
## trip cost the squad's trust here; the succession's loss is not in it (the base's own succession pays that).
var trust_moved := {}
var _next_id := 1
## The radio's own time (seconds, from the steps it is given).
var _age := 0.0
## Person id to {"at": when their stance began (radio time), "hurt": whether it has cost trust yet}.
var _applied := {}
## Called with (person, verb, at) when a request takes effect, for whoever needs more than the stance says (a place's squad
## walks to the exit at "go back"). Not saved: whoever sets it sets it again.
var on_applied: Callable
## The sections that have had their call this night (or day) and the day it is kept for.
var _attack_called := {}
var _attack_day := 0
var _sick_called := {}
## Who has been sent somewhere by a call (person id to wall section id), until the posts are manned no more.
var _sent := {}
## What the wall sections were worth last step (id to hp) and the last phase the radio saw.
var _seg_hp := {}
var _phase_seen := ""


func setup(s) -> void:
	sim = s


func start() -> void:
	_reset()
	for p in sim.people:
		p.trust = TRUST_START
		p.stance = ""
		p.stance_at = Vector2.ZERO
	_phase_seen = String(sim.phase)


func _reset() -> void:
	news.clear()
	pending.clear()
	alarm_on = false
	reasons.clear()
	trust_moved.clear()
	_next_id = 1
	_age = 0.0
	_applied.clear()
	_attack_called.clear()
	_attack_day = 0
	_sick_called.clear()
	_sent.clear()
	_seg_hp.clear()
	_phase_seen = ""


# ------------------------------------------------------------------ the people --

func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


## Whether this run has an avatar (every automatic thing the radio does is behind it).
func avatar_mode() -> bool:
	return String(sim.player_id) != ""


## The person the player controls, or null.
func leader():
	var id := String(sim.player_id)
	if id == "":
		return null
	return _person(id)


func _is_leader(p) -> bool:
	return p.player or (String(sim.player_id) != "" and String(p.id) == String(sim.player_id))


func _first_of(id: String) -> String:
	var p = _person(id)
	return String(p.first) if p != null else id


# ---------------------------------------------------------------------- trust --

func trust_of(p) -> float:
	return float(p.trust)


## Changes someone's trust in the player (kept between 0 and 100) and remembers why, for a tooltip.
func add_trust(p, delta: float, why: String) -> void:
	if p == null or delta == 0.0 or not is_finite(delta):
		return
	var was := float(p.trust)
	p.trust = clampf(was + delta, 0.0, 100.0)
	trust_moved[String(p.id)] = float(trust_moved.get(String(p.id), 0.0)) + (float(p.trust) - was)
	var list: Array = reasons.get(String(p.id), [])
	list.append({"why": why, "delta": delta, "day": int(sim.day)})
	while list.size() > MAX_REASONS:
		list.pop_front()
	reasons[String(p.id)] = list
	sim.relations.on_trust_moved(p, delta)    # (round 20: a push or a gain reaches the person's friends)


## The last few reasons someone's trust has moved, newest first: [{"why", "delta", "day"}].
func trust_why(p) -> Array:
	var out: Array = []
	var list: Array = reasons.get(String(p.id), [])
	for i in range(list.size() - 1, -1, -1):
		out.append(list[i].duplicate())
	return out


## How long they take to answer, in seconds: half a second from TRUST_FAST up to four from TRUST_SLOW down.
func delay_for(trust: float) -> float:
	var f := clampf((trust - TRUST_SLOW) / (TRUST_FAST - TRUST_SLOW), 0.0, 1.0)
	return lerpf(DELAY_SLOW, DELAY_FAST, f)


## "willing", "grudging" or "doubtful".
func tone_for(trust: float) -> String:
	if trust >= TONE_WILLING:
		return "willing"
	if trust >= TONE_GRUDGING:
		return "grudging"
	return "doubtful"


func tone_of(p) -> String:
	return tone_for(trust_of(p))


## Someone who was with the player on a trip they led has come back safe: a little more trust each.
func on_trip_led(people: Array) -> void:
	for p in people:
		if p == null or p.dead or p.turned or p.downed:
			continue
		add_trust(p, TRIP_BONUS, "Came back safe from a trip you led")


## Someone was hurt (bitten) while following a request: if their stance began within two minutes it costs trust, once.
func on_hurt_following(p) -> void:
	if p == null or String(p.stance) == "":
		return
	var rec: Dictionary = _applied.get(String(p.id), {})
	if rec.is_empty() or bool(rec.get("hurt", false)) or _age - float(rec.get("at", -1.0e9)) > HURT_WINDOW_S:
		return
	rec["hurt"] = true
	add_trust(p, -HURT_COST, "Hurt following your lead")


# ---------------------------------------------------------------- willingness --

func verb_name(verb: String) -> String:
	return String(VERB_NAMES.get(verb, verb))


## Whether `contact` will do what `verb` asks, now, and how: {"ok", "why" (the reason, "Ana: tending a patient, can't
## come", "" when ok), "line" (what they say, without their name; "" when they cannot say anything), "delay_s", "tone"
## ("willing", "grudging", "doubtful", or "refused"), "hard" (a refusal nobody can argue with: down, gone, away, in a
## breakdown, the leader)}. Pure: it changes nothing.
func willingness(contact, verb: String) -> Dictionary:
	var out := {"ok": true, "why": "", "line": "", "delay_s": 0.0, "tone": "", "hard": false}
	if contact == null or not VERBS.has(verb):
		return _refused(out, "Nobody answers", "", true)
	var trust: float = trust_of(contact) + sim.relations.company_pull(contact, verb)    # (round 20: a friend in the squad warms, a rival cools; +0.0 without an avatar)
	out["delay_s"] = delay_for(trust)
	out["tone"] = tone_for(trust)
	var first := String(contact.first)
	var hard := _hard_reason(contact)
	if hard != "":
		return _refused(out, hard, "", true)
	var busy := _busy_hard(contact)
	if busy != "":
		return _refused(out, "%s: %s, can't %s" % [first, busy, String(CANT.get(verb, "do that"))], busy.substr(0, 1).to_upper() + busy.substr(1) + ".", true)
	if verb == "back" or verb == "post":
		out["line"] = String(LINES[verb][out.tone])
		return out
	var reason := _busy_soft(contact)
	if reason == "" and verb != "hold":
		reason = _health_reason(contact)
	if reason == "" and verb != "hold":
		reason = sim.relations.company_reason(contact, verb)    # (round 20: a soft reason of company: staying with a hurt friend, an enemy in the squad)
	if reason != "":
		var spoken := reason.substr(0, 1).to_upper() + reason.substr(1) + ", can't %s." % String(CANT.get(verb, "do that"))
		return _refused(out, "%s: %s, can't %s" % [first, reason, String(CANT.get(verb, "do that"))], spoken, false)
	out["line"] = String(LINES[verb][out.tone])
	return out


func _refused(out: Dictionary, why: String, line: String, hard: bool) -> Dictionary:
	out["ok"] = false
	out["why"] = why
	out["line"] = line
	out["delay_s"] = 0.0
	out["tone"] = "refused"
	out["hard"] = hard
	return out


## A reason nobody can argue with, or "".
func _hard_reason(p) -> String:
	var first := String(p.first)
	if _is_leader(p):
		return "That is you"
	if p.turned:
		return "%s has turned" % first
	if p.dead:
		return "%s is gone" % first
	if p.downed:
		return "%s is down" % first
	if p.away != null:
		return "%s is away" % first
	if sim.morale.breakdown(p):
		return "%s is having a breakdown" % first
	return ""


## Something they are in the middle of that no insisting changes (the rules would send them back to it): "" when none.
func _busy_hard(p) -> String:
	if sim.medical.sendouts.has(p.id):
		return "leaving through the gate"
	if sim.scavenge.goal_for(p) != null:
		return "heading out with the party"
	return ""


## Something critical they are doing that a push could pull them from: "" when none.
func _busy_soft(p) -> String:
	for j in sim.medical.jobs:
		if j.healer == p:
			return "tending a patient"
	var job := String(sim.jobs.job_of(p))
	if job == "infirmary" and _lone_nurse(p):
		return "the only one at the infirmary with a patient"
	if sim.phase == "day":
		var h: float = sim.hour
		if job == "radio" and h >= RADIO_FROM_H and h <= RADIO_TO_H:
			return "at the radio for the noon hour"
		if job == "watch" and int(sim.tactics.forecast_day) != int(sim.day):
			var fh: float = sim.tactics.forecast_hour()
			if h >= fh - LOOKOUT_BEFORE_H and h <= fh:
				return "about to give the forecast"
	return ""


## Whether `p` is all the infirmary has on duty while somebody lies there.
func _lone_nurse(p) -> bool:
	var patient := false
	for q in sim.people:
		if q != p and not q.dead and not q.turned and q.away == null and (q.downed or q.resting_bed != null):
			patient = true
	if not patient:
		return false
	for q in sim.jobs.crew_of("infirmary"):
		if q != p and not q.dead and not q.downed and q.away == null:
			return false
	return true


## What is the matter with them: "" when nothing.
func _health_reason(p) -> String:
	if p.bleeding > 0.0:
		return "bleeding"
	var stage: String = sim.medical.infection_stage(p)
	if stage != "":
		return stage
	if sim.storyteller.is_sick(p):
		return "sick with a fever"
	if p.hunger_h >= sim.supplies.STARVING_H:
		return "starving"
	if p.thirst_h >= sim.supplies.PARCHED_H:
		return "parched"
	var mood: String = sim.morale.mood(p)
	if mood == "Shaken" or mood == "Breaking":
		return "too shaken"
	return ""


# ------------------------------------------------------------------- requests --

## Asks `contact` to do what `verb` says: {"ok", "line" (what they say), "why" (the refusal, "" when ok), "delay_s", "tone",
## "insisted", "hard" (a refusal that insisting cannot change: the view does not offer Insist for it)}. `args`: "at" (a Vector2: the spot of "hold", the container of "search"), "insist" (true: override a refusal
## that is not a hard one, at a cost of trust and a blow to the mood). If they agree, what was asked comes true after
## `delay_s` seconds of the radio's time (`tick`); a later request to the same person replaces one still waiting.
func request(contact, verb: String, args: Dictionary = {}) -> Dictionary:
	if contact == null:
		return {"ok": false, "line": "", "why": "Nobody answers", "delay_s": 0.0, "tone": "refused", "insisted": false, "hard": true}
	var lead = leader()
	if lead == null:
		return {"ok": false, "line": "", "why": "Nobody is on the radio", "delay_s": 0.0, "tone": "refused", "insisted": false, "hard": true}
	var w := willingness(contact, verb)
	if w.ok and lead.away != null and (verb == "come" or verb == "cover" or (verb == "hold" and not args.has("at"))):
		w = _refused(w, "%s: you are not at the base, can't %s" % [String(contact.first), String(CANT[verb])], "", true)
	var insisted := false
	if not w.ok:
		if bool(args.get("insist", false)) and not bool(w.hard):
			insisted = true
			add_trust(contact, -INSIST_COST, "You pushed them to go when they could not")
			sim.morale.shock(contact, INSIST_MORALE, "Pushed to go when they could not")
			w = {"ok": true, "why": "", "line": String(LINES[verb]["doubtful"]), "delay_s": delay_for(trust_of(contact)), "tone": "doubtful", "hard": false}
		else:
			_say(contact, verb, false, String(w.line), "refused")
			return {"ok": false, "line": String(w.line), "why": String(w.why), "delay_s": 0.0, "tone": "refused", "insisted": false, "hard": bool(w.hard)}
	var at := Vector2.ZERO
	if verb == "hold":
		at = _point(args.get("at"), Vector2(lead.x, lead.y))
	elif verb == "search":
		at = _point(args.get("at"), _aim_point(lead))
	var i := pending.size() - 1
	while i >= 0:
		if String(pending[i].who) == String(contact.id):
			pending.remove_at(i)
		i -= 1
	pending.append({"who": String(contact.id), "verb": verb, "at": at, "left": float(w.delay_s), "insist": insisted})
	_say(contact, verb, true, String(w.line), String(w.tone))
	return {"ok": true, "line": String(w.line), "why": "", "delay_s": float(w.delay_s), "tone": String(w.tone), "insisted": insisted, "hard": false}


func _say(p, verb: String, ok: bool, line: String, tone: String) -> void:
	sim.events.append({"type": "radio_line", "who": String(p.id), "verb": verb, "ok": ok, "line": line, "tone": tone})


func _point(v, fallback: Vector2) -> Vector2:
	return Vector2(v) if typeof(v) == TYPE_VECTOR2 else fallback


## Where the player aims (the point of the world the mouse is over), or where they stand when there is none.
func _aim_point(lead) -> Vector2:
	var at = lead.get("input_aim")
	if typeof(at) == TYPE_VECTOR2 and Vector2(at) != Vector2.ZERO:
		return Vector2(at)
	return Vector2(lead.x, lead.y)


## The radio's own clock, and what it has been waiting on: the requests whose delay is up take effect; a stance that no
## longer makes sense (the person is down, gone, away, in a breakdown, or is the leader; a follower or a cover whose leader is away
## or gone) ends. `update` calls it each step;
## a place's scene, which does not run `Sim.update`, calls it with the place's step.
func tick(dt: float) -> void:
	_age += dt
	var i := pending.size() - 1
	var due: Array = []
	while i >= 0:
		pending[i]["left"] = float(pending[i].left) - dt
		if float(pending[i].left) <= 0.0:
			due.push_front(pending[i])
			pending.remove_at(i)
		i -= 1
	for e in due:
		var p = _person(String(e.who))
		if p != null and _hard_reason(p) == "" and _busy_hard(p) == "":
			_take_effect(p, String(e.verb), e.at)
	# (a follower or a cover has nobody to follow while the leader is out on a trip or gone: they go back to their jobs; a hold or
	# a search is a spot, and stays)
	var lead = leader()
	var leader_out: bool = lead == null or lead.away != null or lead.dead or lead.turned
	for p in sim.people:
		var stance := String(p.stance)
		if stance == "":
			continue
		if p.downed or p.dead or p.turned or p.away != null or _is_leader(p) or sim.morale.breakdown(p) or (leader_out and (stance == "follow" or stance == "cover")):
			clear_stance(p)


## What an agreed request does to the person.
func _take_effect(p, verb: String, at: Vector2) -> void:
	match verb:
		"back":
			clear_stance(p)
			p.order = null
			p.drafted = false
			p.goal_key = ""
			_sent.erase(String(p.id))
		"post":
			clear_stance(p)
			_sent.erase(String(p.id))
			sim.order_post(p)
		_:
			var stance := String(STANCE_OF.get(verb, ""))
			if stance == "":
				return
			set_stance(p, stance, at)
	sim.events.append({"type": "stance", "who": String(p.id), "verb": verb, "stance": String(p.stance)})
	if on_applied.is_valid():
		on_applied.call(p, verb, at)


## Puts a stance on a person at once, with no asking and no delay ("follow", "hold", "cover", "search"; "" ends it): for whoever
## has to start someone off in one (a place's squad that begins the trip following the player). `at` is the spot of a hold or a
## search. They are drafted, off any job, order or repair, and no longer a healer on a case.
func set_stance(p, stance: String, at: Vector2 = Vector2.ZERO) -> void:
	if stance == "":
		clear_stance(p)
		return
	p.stance = stance
	p.stance_at = at
	p.drafted = true
	p.order = null
	p.repair = null
	p.goal_key = ""
	sim.tactics.forget_trip(p)
	# a nurse pushed off her patient leaves them (the patient goes back in the queue)
	var i: int = sim.medical.jobs.size() - 1
	while i >= 0:
		if sim.medical.jobs[i].healer == p:
			sim.medical.jobs.remove_at(i)
		i -= 1
	_sent.erase(String(p.id))
	_applied[String(p.id)] = {"at": _age, "hurt": false}


## Ends whatever the person was asked to follow, hold, cover or search, and what it drafted them for.
func clear_stance(p) -> void:
	if String(p.stance) == "":
		return
	p.stance = ""
	p.stance_at = Vector2.ZERO
	if p.order == null:
		p.drafted = false
	p.goal_key = ""
	_applied.erase(String(p.id))


# -------------------------------------------------------------------- stances --

## The goal a stance gives a person ({"x", "y", "face", "what"}, see `Sim._goal_for`), or null with none (or when it no
## longer applies). Follow: a place within FOLLOW_R of the leader, facing where they aim (they stay where they are while
## they are near enough); cover: COVER_BACK behind the aim, side by side with the other covers; hold and search: the spot.
func stance_goal(p):
	var stance := String(p.stance)
	if stance == "" or p.downed or p.dead or p.turned or p.away != null:
		return null
	if stance == "hold" or stance == "search":
		var at: Vector2 = p.stance_at if p.stance_at != Vector2.ZERO else Vector2(p.x, p.y)
		return {"x": at.x, "y": at.y, "face": "", "what": "Holding here" if stance == "hold" else "Searching"}
	var lead = leader()
	if lead == null or lead == p or lead.away != null or lead.dead:
		return null
	if stance == "follow":
		return _follow_goal(p, lead)
	if stance == "cover":
		return _cover_goal(p, lead)
	return null


## Where the leader aims, as a unit vector: the mouse's point when there is one, else the way they face.
func _aim_dir(lead) -> Vector2:
	var at = lead.get("input_aim")
	if typeof(at) == TYPE_VECTOR2 and Vector2(at) != Vector2.ZERO:
		var d: Vector2 = Vector2(at) - Vector2(lead.x, lead.y)
		if d.length() > 0.3:
			return d.normalized()
	match String(lead.facing):
		"N":
			return Vector2(0.0, -1.0)
		"S":
			return Vector2(0.0, 1.0)
		"W":
			return Vector2(-1.0, 0.0)
	return Vector2(1.0, 0.0)


## The people with this stance (alive, here), in the order of the crew list: each takes a place of its own.
func _with_stance(stance: String) -> Array:
	var out: Array = []
	for q in sim.people:
		if String(q.stance) == stance and not (q.dead or q.downed or q.turned or q.away != null):
			out.append(q)
	return out


func _follow_goal(p, lead) -> Dictionary:
	var pp := Vector2(lead.x, lead.y)
	var me := Vector2(p.x, p.y)
	var aim := _aim_dir(lead)
	var face: String = sim.facing_of(aim.x, aim.y, String(p.facing))
	var what := "Following %s" % String(lead.first)
	var dist := me.distance_to(pp)
	if dist <= FOLLOW_R and dist >= FOLLOW_MIN:
		return {"x": p.x, "y": p.y, "face": face, "what": what}
	var group := _with_stance("follow")
	var n := group.size()
	var k := maxi(0, group.find(p))
	var spread := (float(k) - float(n - 1) * 0.5) * FOLLOW_SPREAD
	var slot := _open_spot(pp, pp + (-aim).rotated(spread) * FOLLOW_SLOT)
	return {"x": slot.x, "y": slot.y, "face": face, "what": what}


func _cover_goal(p, lead) -> Dictionary:
	var pp := Vector2(lead.x, lead.y)
	var aim := _aim_dir(lead)
	var face: String = sim.facing_of(aim.x, aim.y, String(p.facing))
	var group := _with_stance("cover")
	var n := group.size()
	var k := maxi(0, group.find(p))
	var side := (float(k) - float(n - 1) * 0.5) * COVER_APART
	var spot := _open_spot(pp, pp + (-aim) * COVER_BACK + aim.orthogonal() * side)
	return {"x": spot.x, "y": spot.y, "face": face, "what": "Covering %s" % String(lead.first)}


## How fast this person walks now (`Sim._update_person` asks): the usual 3.0 tiles a second, a little faster for someone who
## is following or covering the player and has been left behind, so that a leader who walks on does not leave them.
func speed_of(p) -> float:
	var stance := String(p.stance)
	if stance != "follow" and stance != "cover":
		return WALK_SPEED
	var lead = leader()
	if lead == null or lead == p or lead.away != null:
		return WALK_SPEED
	var far := Vector2(p.x, p.y).distance_to(Vector2(lead.x, lead.y))
	return HURRY_SPEED if far > (HURRY_FOLLOW if stance == "follow" else HURRY_COVER) else WALK_SPEED


## The farthest point from `origin` toward `want` (in tenths of the way) that is open ground a person could walk to in a
## straight line from `origin`; `origin` itself when there is none.
func _open_spot(origin: Vector2, want: Vector2) -> Vector2:
	var world = sim.world
	var to := want - origin
	for k in 11:
		var pt := origin + to * (1.0 - float(k) * 0.1)
		if world.is_solid(world.solid_p, pt.x, pt.y):
			continue
		if sim.path_p.sight(world.solid_p, origin, pt, 0.2):
			return pt
	return origin


# ----------------------------------------------------------------------- news --

## Adds an entry to the log (the oldest goes at MAX_NEWS) and returns it. `extra` overrides or adds fields.
func log_news(kind: String, text: String, sub: String = "", extra: Dictionary = {}) -> Dictionary:
	var e := {
		"id": _next_id, "t": float(sim.clock_min), "day": int(sim.day), "hour": snappedf(float(sim.hour), 0.01), "kind": kind,
		"text": text, "sub": sub, "options": [], "default": "", "due": 0.0, "answered": "", "by_default": false, "result": "",
		"at": null, "data": {},
	}
	e.merge(extra, true)
	_next_id += 1
	news.append(e)
	while news.size() > MAX_NEWS:
		var drop := 0
		for i in news.size():
			if not _open(news[i]):
				drop = i
				break
		news.remove_at(drop)
	return e


## The entries after the one with this id (0: all of them), oldest first.
func news_since(after_id: int) -> Array:
	var out: Array = []
	for e in news:
		if int(e.id) > after_id:
			out.append(e)
	return out


## The id of the newest entry (0 when there is none).
func latest_id() -> int:
	return int(news[news.size() - 1].id) if not news.is_empty() else 0


func _open(e: Dictionary) -> bool:
	return not e.options.is_empty() and String(e.answered) == ""


## The calls that wait for an answer, oldest first.
func open_calls() -> Array:
	var out: Array = []
	for e in news:
		if _open(e):
			out.append(e)
	return out


func _entry(id: int) -> Dictionary:
	for e in news:
		if int(e.id) == id:
			return e
	return {}


## Raises a call: an entry with options ([{"id", "label"}, ...]) that waits for `answer`; after `ttl_min` game minutes the
## option `default_option` is taken. `data` is what the kind keeps (a section's id, a person's id), `at` a point the view may
## show (a Vector2). Returns its id.
func raise_call(kind: String, text: String, sub: String, options: Array, default_option: String, ttl_min: float, data: Dictionary = {}, at = null) -> int:
	var opts: Array = []
	var ids: Array = []
	for o in options:
		opts.append({"id": String(o.id), "label": String(o.label)})
		ids.append(String(o.id))
	var fallback := default_option if ids.has(default_option) else (String(ids[0]) if not ids.is_empty() else "")
	var e := log_news(kind, text, sub, {"options": opts, "default": fallback, "due": float(sim.clock_min) + ttl_min, "data": data.duplicate(true), "at": at})
	return int(e.id)


## The player answers a call with one of its options. False when there is no such open call or option.
func answer(id: int, option_id: String) -> bool:
	var e := _entry(id)
	if e.is_empty() or not _open(e):
		return false
	var found := false
	for o in e.options:
		if String(o.id) == option_id:
			found = true
	if not found:
		return false
	_settle(e, option_id, false)
	return true


func _settle(e: Dictionary, option_id: String, by_default: bool) -> void:
	e["answered"] = option_id
	e["by_default"] = by_default
	e["result"] = _carry_out(e, option_id)
	sim.events.append({"type": "radio_answered", "id": int(e.id), "option": option_id, "by_default": by_default})


## Calls whose time is up take their default.
func _expire_calls() -> void:
	for e in news:
		if _open(e) and float(sim.clock_min) >= float(e.due):
			_settle(e, String(e.default), true)


## What an option does; the line that says what came of it.
func _carry_out(e: Dictionary, option_id: String) -> String:
	var data: Dictionary = e.data
	match String(e.kind):
		"attack":
			var seg = _segment(int(data.get("seg", -1)))
			if seg == null:
				return ""
			if option_id == "reinforce":
				return "Reinforcements sent (%d)" % _reinforce(seg)
			if option_id == "fall_back":
				return "Falling back to the school (%d)" % _fall_back(seg)
			return "Holding"
		"sick":
			var p = _person(String(data.get("who", "")))
			if p == null or p.dead or p.turned:
				return ""
			if option_id == "treat":
				if sim.medical.gizmo("treat", {"kind": "person", "ref": p}):
					return "Treating %s" % String(p.first)
				return "Cannot treat %s now" % String(p.first)
			if option_id == "apart":
				if not sim.medical.keep_apart(p):
					return "Cannot keep %s apart now" % String(p.first)
				sim.morale.shock(p, APART_MORALE, "Kept apart from the others")
				return "%s rests apart, off work until it passes" % String(p.first)
			if option_id == "sendout":
				if sim.medical.gizmo("sendout", {"kind": "person", "ref": p}):
					return "%s is sent out through the gate" % String(p.first)
				return "Cannot send %s out now" % String(p.first)
		"idea":
			# an idea the community brought (initiative.gd, round 20): the module does what a yes asks and keeps the accounts
			return sim.initiative.carry_out(e, option_id)
	return ""


func _segment(id: int):
	for s in sim.segments:
		if int(s.id) == id:
			return s
	return null


# ---------------------------------------------------------------------- update --

## One step of the rules' time, at the end of `Sim.update`: the requests and the calls run in any game; the news that the
## radio makes by itself (from the events and the state of the step) only in avatar mode.
func update(dt: float) -> void:
	tick(dt)
	_expire_calls()
	_dawn()
	_release_the_sent()
	if not avatar_mode():
		_seg_hp.clear()
		return
	_read_events()
	_watch_the_walls()
	_watch_for_fever()


## The alarm stands down by itself when the day comes.
func _dawn() -> void:
	var now := String(sim.phase)
	if alarm_on and now == "day" and _phase_seen != "" and _phase_seen != "day":
		alarm(false, true)
	_phase_seen = now


## The events of this step that the radio turns into news. It reads each event once: it marks the ones it has read (the view
## clears the list between frames, and `Sim.fast_forward` takes some out of it, so a place kept in the list is not enough).
func _read_events() -> void:
	for e in sim.events:
		if e.has(READ_KEY):
			continue
		e[READ_KEY] = true
		_on_event(e)


func _on_event(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"story_card":
			var pend: Dictionary = sim.storyteller.pending()
			# (a card that comes while the player is out is told in its own line, "waiting for your return": storyteller.gd)
			if not pend.is_empty() and not bool(pend.get("resolved", false)) and not sim.storyteller.card_frozen():
				var who := String(pend.speaker)
				log_news("story", String(pend.title), "A call on the radio" if who == "The radio" else "%s on the radio" % who)
		"story_resolved":
			var id := String(e.get("id", ""))
			var a: Dictionary = sim.alerts.get("story-%s" % id, {})
			var title := String(a.get("text", ""))
			var line := String(a.get("sub", ""))
			if title == "":
				title = String(sim.storyteller.card_named(id).get("title", id))
				line = String(e.get("text", ""))
			log_news("story", title, line)
		"arrived":
			var p = _person(String(e.get("who", "")))
			if p != null:
				log_news("recruit", "%s has joined the crew" % String(p.name), String(p.def.get("role", "")))
		"succession":
			log_news("succession", "%s is gone. %s leads now." % [_first_of(String(e.get("from", ""))), _first_of(String(e.get("to", "")))], "")
		"bite":
			on_hurt_following(_person(String(e.get("who", ""))))


## A call for every wall section the dead are clawing at (one a night per section, one a day per section).
func _watch_the_walls() -> void:
	if _attack_day != int(sim.day):
		_attack_day = int(sim.day)
		_attack_called.clear()
	var night: bool = sim.is_night()
	for s in sim.segments:
		var was: float = float(_seg_hp.get(s.id, s.hp))
		_seg_hp[s.id] = s.hp
		if s.state == 3 or s.hp >= was - 1.0e-9:
			continue
		var n := 0
		for sl in s.slots:
			if sl.who != null and sl.who.state == "attack":
				n += 1
		if n == 0:
			continue
		var key := "%s:%d" % ["n" if night else "d", int(s.id)]
		if _attack_called.has(key):
			continue
		_attack_called[key] = true
		var pct := roundi(float(s.hp) / float(s.max_hp) * 100.0)
		raise_call("attack", "%s under attack" % String(s.name), "%d of the dead at it, %d%% intact" % [n, pct], [
			{"id": "hold", "label": "Hold"},
			{"id": "reinforce", "label": "Send reinforcements"},
			{"id": "fall_back", "label": "Fall back to the school"},
		], "hold", ATTACK_TTL_MIN, {"seg": int(s.id)}, s.center)


## A call for each person who has a fever (once for each sickness).
func _watch_for_fever() -> void:
	for p in sim.people:
		var id := String(p.id)
		var sick: bool = not (p.dead or p.turned or p.away != null) and (sim.medical.infection_stage(p) != "" or sim.storyteller.is_sick(p))
		if not sick or _is_leader(p):
			_sick_called.erase(id)
			continue
		if _sick_called.has(id) or sim.medical.treat_orders.has(p.id):
			continue
		_sick_called[id] = true
		var options: Array = [
			{"id": "treat", "label": "Treat them"},
			{"id": "apart", "label": "Keep them apart"},
		]
		var sub := "Treat them, or keep them apart"
		# (with no medicine to treat an infection with, the gate is an answer too: never the default)
		if sim.medical.can_send_out(p) and float(sim.stock.meds) < float(sim.medical.CURE_MEDS):
			options.append({"id": "sendout", "label": "Send them out"})
			sub = "No medicine to treat them with: keep them apart, or send them out"
		raise_call("sick", "%s has a fever" % String(p.first), sub, options, "treat", SICK_TTL_MIN, {"who": id}, Vector2(p.x, p.y))


# --------------------------------------------------------------- the call's options --

## Whether someone could be sent somewhere by a call: up, here, not the leader, not with the leader, not at something critical.
func _free_to_go(p) -> bool:
	if p.dead or p.turned or p.downed or p.away != null or _is_leader(p) or String(p.stance) != "":
		return false
	return not sim.morale.breakdown(p) and _hard_reason(p) == "" and _busy_hard(p) == "" and _busy_soft(p) == ""


## "Send reinforcements": everyone who is free is sent to a post near the section, the nearest of them to the nearest
## post. Returns how many went.
func _reinforce(seg) -> int:
	var crew: Array = []
	for p in sim.people:
		if _free_to_go(p):
			crew.append(p)
	crew.sort_custom(func(a, b): return Vector2(a.x, a.y).distance_to(seg.center) < Vector2(b.x, b.y).distance_to(seg.center))
	var spots: Array = []
	for po in sim.jobs.posts():
		spots.append(Vector2(po.pos))
	spots.sort_custom(func(a, b): return a.distance_to(seg.center) < b.distance_to(seg.center))
	var yard: Vector2 = sim.repair_spot(seg)
	var sent := 0
	for i in crew.size():
		var at: Vector2 = spots[i] if i < spots.size() else yard + Vector2(float(i - spots.size()) * 0.8, 0.0)
		if sim.order_move(crew[i], at.x, at.y) or sim.order_move(crew[i], yard.x, yard.y):
			_sent[String(crew[i].id)] = int(seg.id)
			sent += 1
	return sent


## "Fall back to the school": the people whose posts are at this section are sent inside, to the school door nearest them.
func _fall_back(seg) -> int:
	var doors: Array = []
	for s in sim.segments:
		if s.kind == sim.DOOR_KIND and s.state != 3:
			doors.append(s)
	if doors.is_empty():
		return 0
	var sent := 0
	for p in sim.people:
		if not _free_to_go(p) or not _post_at(seg, sim.jobs.post_pos(p)):
			continue
		var door = doors[0]
		for s in doors:
			if Vector2(p.x, p.y).distance_to(s.center) < Vector2(p.x, p.y).distance_to(door.center):
				door = s
		var at: Vector2 = door.center + Vector2(float(sent) * 0.9 - 0.9, 2.0)
		if sim.order_move(p, at.x, at.y):
			_sent[String(p.id)] = int(seg.id)
			sent += 1
	return sent


## Whether a post is on this wall section: along the wall within the section's reach and close to its line.
func _post_at(seg, at: Vector2) -> bool:
	var along := at.x if (seg.side == "N" or seg.side == "S") else at.y
	var across := absf(at.y - seg.center.y) if (seg.side == "N" or seg.side == "S") else absf(at.x - seg.center.x)
	return across < 4.5 and along >= float(seg.from) - 1.0 and along <= float(seg.to) + 1.0


## The orders a call gave end when the posts are manned no more (the day comes).
func _release_the_sent() -> void:
	if _sent.is_empty() or sim.posts_manned():
		return
	for id in _sent.keys():
		var p = _person(String(id))
		if p != null and p.order != null and p.order.z < 0.5 and String(p.stance) == "":
			p.order = null
			p.drafted = false
			p.goal_key = ""
	_sent.clear()


# ---------------------------------------------------------------------- the alarm --

## The call to arms: everyone to their posts now, by day too, until it is stood down (`alarm(false)`, or the dawn).
func alarm(on: bool, at_dawn: bool = false) -> void:
	if on == alarm_on:
		return
	alarm_on = on
	if on:
		sim.tactics.threat_until = maxf(float(sim.tactics.threat_until), float(sim.clock_min) + ALARM_FAR_MIN)
		for p in sim.people:
			clear_stance(p)
			sim.tactics.call_back(p)
			_sent.erase(String(p.id))
		sim.alert("alarm", "warn", "Call to arms", "Everyone to their posts", null, 15.0)
		sim.events.append({"type": "banner", "text": "Call to arms", "sub": "Everyone to their posts"})
		log_news("alarm", "Call to arms", "Everyone to their posts")
	else:
		sim.tactics.threat_until = minf(float(sim.tactics.threat_until), float(sim.clock_min))
		sim.alerts.erase("alarm")
		log_news("alarm", "Stood down", "The alarm ended at dawn" if at_dawn else "Back to work")
	sim.events.append({"type": "alarm", "on": on})


# ------------------------------------------------------------------------- save --

func save() -> Dictionary:
	var list: Array = []
	for e in news:
		var c: Dictionary = e.duplicate(true)
		if c.at != null:
			c["at"] = [float(c.at.x), float(c.at.y)]
		list.append(c)
	var wait: Array = []
	for r in pending:
		wait.append({"who": String(r.who), "verb": String(r.verb), "at": [float(r.at.x), float(r.at.y)], "left": float(r.left), "insist": bool(r.insist)})
	return {
		"news": list,
		"pending": wait,
		"alarm_on": alarm_on,
		"reasons": reasons.duplicate(true),
		"next_id": _next_id,
		"age": _age,
		"applied": _applied.duplicate(true),
		"attack_called": _attack_called.duplicate(),
		"attack_day": _attack_day,
		"sick_called": _sick_called.keys(),
		"sent": _sent.duplicate(),
		"phase": _phase_seen,
	}


## Restores what `save` wrote. A save from before the radio has none of it: an empty radio. Anything that is not sound is
## left out.
func load_state(d: Dictionary) -> void:
	_reset()
	_phase_seen = String(d.get("phase", sim.phase)) if typeof(d.get("phase", "")) == TYPE_STRING else String(sim.phase)
	alarm_on = bool(d.get("alarm_on", false)) if typeof(d.get("alarm_on", false)) == TYPE_BOOL else false
	var raw = d.get("news", [])
	if raw is Array:
		for r in raw:
			var e := _entry_in(r)
			if not e.is_empty():
				news.append(e)
	while news.size() > MAX_NEWS:
		news.remove_at(0)
	var top := 0
	for e in news:
		top = maxi(top, int(e.id))
	_next_id = maxi(top + 1, int(d.get("next_id", 1)) if _number(d.get("next_id")) else 1)
	_age = float(d.age) if _number(d.get("age")) else 0.0
	var wait = d.get("pending", [])
	if wait is Array:
		for r in wait:
			if r is Dictionary and typeof(r.get("who")) == TYPE_STRING and VERBS.has(String(r.get("verb", ""))) and _number(r.get("left")):
				pending.append({"who": String(r.who), "verb": String(r.verb), "at": _vec(r.get("at")), "left": float(r.left), "insist": bool(r.get("insist", false))})
	var why = d.get("reasons", {})
	if why is Dictionary:
		for id in why:
			if _person(String(id)) == null or not (why[id] is Array):
				continue
			var list: Array = []
			for r in why[id]:
				if r is Dictionary and typeof(r.get("why")) == TYPE_STRING and _number(r.get("delta")):
					list.append({"why": String(r.why), "delta": float(r.delta), "day": int(r.get("day", 0)) if _number(r.get("day")) else 0})
			while list.size() > MAX_REASONS:
				list.pop_front()
			if not list.is_empty():
				reasons[String(id)] = list
	var applied = d.get("applied", {})
	if applied is Dictionary:
		for id in applied:
			var rec = applied[id]
			if rec is Dictionary and _number(rec.get("at")) and _person(String(id)) != null:
				_applied[String(id)] = {"at": float(rec.at), "hurt": bool(rec.get("hurt", false))}
	var called = d.get("attack_called", {})
	if called is Dictionary:
		for k in called:
			_attack_called[String(k)] = true
	_attack_day = int(d.attack_day) if _number(d.get("attack_day")) else 0
	var sick = d.get("sick_called", [])
	if sick is Array:
		for id in sick:
			_sick_called[String(id)] = true
	var sent = d.get("sent", {})
	if sent is Dictionary:
		for id in sent:
			if _number(sent[id]) and _person(String(id)) != null:
				_sent[String(id)] = int(sent[id])


func _entry_in(r) -> Dictionary:
	if not (r is Dictionary) or not _number(r.get("id")) or typeof(r.get("kind")) != TYPE_STRING or typeof(r.get("text")) != TYPE_STRING:
		return {}
	var opts: Array = []
	var raw_opts = r.get("options", [])
	if raw_opts is Array:
		for o in raw_opts:
			if o is Dictionary and typeof(o.get("id")) == TYPE_STRING and typeof(o.get("label")) == TYPE_STRING:
				opts.append({"id": String(o.id), "label": String(o.label)})
	var data := {}
	var raw_data = r.get("data", {})
	if raw_data is Dictionary:
		for k in raw_data:
			var v = raw_data[k]
			data[String(k)] = int(v) if (typeof(v) == TYPE_FLOAT and v == floorf(v) and absf(v) < 1.0e15) else v
	var at = null
	var raw_at = r.get("at")
	if raw_at is Array and raw_at.size() == 2 and _number(raw_at[0]) and _number(raw_at[1]):
		at = Vector2(float(raw_at[0]), float(raw_at[1]))
	return {
		"id": int(r.id), "t": float(r.t) if _number(r.get("t")) else 0.0, "day": int(r.day) if _number(r.get("day")) else 1,
		"hour": float(r.hour) if _number(r.get("hour")) else 0.0, "kind": String(r.kind), "text": String(r.text),
		"sub": String(r.get("sub", "")), "options": opts, "default": String(r.get("default", "")),
		"due": float(r.due) if _number(r.get("due")) else 0.0, "answered": String(r.get("answered", "")),
		"by_default": bool(r.get("by_default", false)), "result": String(r.get("result", "")), "at": at, "data": data,
	}


func _vec(v) -> Vector2:
	if v is Array and v.size() == 2 and _number(v[0]) and _number(v[1]):
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


static func _number(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))
