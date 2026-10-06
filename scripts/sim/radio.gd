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
## THE CALLS OF THE NIGHT (round 19, scripts/sim/night_calls.gd: `radio.night`, watched at the end of `update` in avatar mode only, saved
## under "night"): a wall that is going (`going`), a brute on its way (`brute`), a section that has fallen (`breach`), the Big Night the
## lookout has read (`night`), the day-ahead notice at noon (`forecast`, news only) and the road home of a trip in a place (`night_road`).
## Their options that send people are `_reinforce_near` (two, the old `attack` call still sends everyone) and `_fall_back`; the newer
## call settles the older ones of the same wall (`settle_wall_calls`); what the rest do is in night_calls.gd (`carry_out`, which
## `_carry_out` hands every kind it does not know to).
##
## THE ALARM is the call to arms: `alarm(true)` puts everyone at their posts now (by day too, in any start) until
## `alarm(false)` or the dawn, and ends whatever stances there were.
##
## ASKING FOR WORK (round 18). The same request, for the colony's work: an errand (`request_errand`: people sent to a place without the
## player, a dice trip in `scavenge.gd` that does worse than the player's own), a day job (`request_job`), a night post
## (`request_post`), "fill the empty seats" (`request_fill`) and an order for a building (`request_build`). Each has a pure
## `*_willingness` that gives the reason when there is one, in the words the Jobs, Build and Map pages show (a page never writes a
## reason of its own); `reason_not` is the one list of the reasons a person may have, shared with the verbs (`willingness`). A roster
## change is a plan, accepted or refused at once with the person's line; an errand leaves after the radio's delay (`errand_wait`).
## Insisting (`args.insist`) overrides a soft refusal at the same cost as for a verb. Nothing is random.
##
## Events this module adds to sim.events: {"type": "radio_line", "who", "verb", "ok", "line", "tone"} when someone is asked,
## {"type": "stance", "who", "stance"} when a request takes effect, {"type": "alarm", "on"}, {"type": "radio_answered",
## "id", "option", "by_default"} when a call is settled, {"type": "call_raised", "id", "kind", "urgent"} when one is raised.
extends RefCounted

const NightCalls := preload("res://scripts/sim/night_calls.gd")

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
## The calls that cannot wait (a wall that is down or going, a brute on its way, the old attack call, the night's own): when one is raised the
## game drops to 1x once (main.gd: the `call_raised` event). Their times are game minutes, a few real seconds at 3x.
const URGENT_KINDS := ["attack", "going", "brute", "breach", "night", "gate", "dilemma"]
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
## Errands that have been agreed to and are waiting for their delay: [{"ids": [person ids], "place", "action" ("loot", "scout",
## "clear"), "vehicle" (an id or ""), "left" (seconds of the radio's time)}]. When it is up `scavenge.send` makes the party. Saved.
var errand_wait: Array = []
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
## The calls and notices of the night (round 19, night_calls.gd): a wall that is going, a brute, a breach, the night's forecast, the
## day-ahead notice, the road home. Made in `setup`, watched in `update` (avatar mode only), saved under "night".
var night


func setup(s) -> void:
	sim = s
	night = NightCalls.new()
	night.setup(self)


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
	errand_wait.clear()
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
	night.reset()


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
	if verb == "search" and _town_search():
		# (One House, CREW: a search order is "Search a house": the person's own reasons, scripts/town/crew_search.gd `person_reason`: nearly dark, on the watch, hurt, two already out)
		var tn: Dictionary = sim.crew_search.person_reason(contact)
		if not tn.is_empty():
			var said := String(tn.reason)
			return _refused(out, "%s: %s, can't search" % [first, said], said.substr(0, 1).to_upper() + said.substr(1) + ", can't search.", bool(tn.hard))
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
	if verb == "search" and _town_search():
		w = _town_search_answer(contact, w, args, lead)
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


## One House: a search order is for a house (`args.at`, a point of it) and the crew search module judges the house with the person: not cleared, already searched, nobody is let into a house with
## dead (hard), too far from home (soft: insisting sends them). The house's reasons come before the person's soft ones.
func _town_search() -> bool:
	return sim.is_one_house() and sim.get("crew_search") != null


func _town_search_answer(contact, w: Dictionary, args: Dictionary, lead) -> Dictionary:
	var cs = sim.crew_search
	var hr: Dictionary = cs.house_refusal(contact, cs.house_of_point(_point(args.get("at"), _aim_point(lead))))
	if hr.is_empty() or not (bool(w.ok) or bool(hr.hard)):
		return w
	return _refused(w, String(hr.why), String(hr.line), bool(hr.hard))


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
	if not errand_wait.is_empty():
		_tick_errands(dt)
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
			if verb == "search" and _town_search():
				if not sim.crew_search.begin_order(p, at):
					return    # (the world changed while they thought about it: the crew search module says so)
			else:
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
	_leave_patient(p)
	_sent.erase(String(p.id))
	_applied[String(p.id)] = {"at": _age, "hurt": false}


## A nurse pushed off her patient leaves them (the patient goes back in the queue).
func _leave_patient(p) -> void:
	var i: int = sim.medical.jobs.size() - 1
	while i >= 0:
		if sim.medical.jobs[i].healer == p:
			sim.medical.jobs.remove_at(i)
		i -= 1


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
	if stance == "search" and _town_search():
		return sim.crew_search.goal_for(p)    # (the house, then each container of it; null while there is no run)
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


# ------------------------------------------------------------------ asking for work --

## What they say, by tone: an errand, a day job or a night post, an order for a building.
const ERRAND_LINES := {"willing": "I'll go.", "grudging": "Fine. I'll go.", "doubtful": "...if you say so."}
const WORK_LINES := {"willing": "Right away.", "grudging": "Fine. I'll do it.", "doubtful": "...if you say so."}
const BUILD_LINES := {"willing": "On it.", "grudging": "Fine. I'll start.", "doubtful": "...if you say so."}
## What a refusal says they cannot do, by what is asked.
const CANT_GO := "go"
const CANT_JOB := "take a job now"
const CANT_POST := "take a post now"
## The errands that can be asked (`scavenge.send`'s actions).
const ERRAND_ACTIONS := ["loot", "scout", "clear"]
## No errand waits longer than this (a damaged save's `left` is held to it: the slowest answer is DELAY_SLOW).
const MAX_ERRAND_WAIT_S := 60.0
## The player is nobody's to give a seat or a post to.
const NO_SEAT_FOR_YOU := "You: no seat, you are the player"
const NO_POST_FOR_YOU := "You: no post, you are the player"
## What a Builders crew of nobody says (advice only: the site waits).
const NO_BUILDERS := "Nobody is on the Builders job: give it to someone on the Jobs page, or the site waits"


## Why this person cannot be asked something now: {"ok", "why" (the words, "Ana: tending a patient, can't go"; "" when ok), "hard"
## (nobody can argue with it), "sentence" ("Ana is tending a patient": for a line that names several), "line" (what they would say)}.
## `kind` "go": the reasons of `willingness(p, "come")` exactly (hard: is the player, gone, turned, down, away, in a breakdown, leaving by
## the gate, heading out with a party; soft: tending a patient, the lone nurse, the noon radio hour, the forecast, then bleeding, a
## fever or an infection, starving, parched, shaken). `kind` "work": the same words for a change TO a station or a post ("can't take a
## job now"); taking someone off their job (`job_willingness(p, "")`) is refused only by the hard ones. One list for the verbs, the
## errands and the roster: never two truths. Round 20's soft reason of company (`relations.company_reason`: "staying with Dez", "won't
## go with Walt" among `with_ids`, who else is going; "won't work beside Walt" at a station) follows the health reasons, here, once.
## Pure.
func reason_not(p, kind: String, with_ids: Array = []) -> Dictionary:
	return _reason_not(p, kind, "-", CANT_GO if kind == "go" else CANT_JOB, with_ids)


func _reason_not(p, kind: String, station_id: String, cant: String, with_ids: Array = []) -> Dictionary:
	var out := {"ok": true, "why": "", "hard": false, "sentence": "", "line": "", "company": false}
	if p == null:
		return _no(out, "Nobody answers", "Nobody answers", "", true)
	var hard := _hard_reason(p)
	if hard != "":
		return _no(out, hard, hard, "", true)
	var first := String(p.first)
	var busy := _busy_hard(p)
	if busy != "":
		return _no(out, "%s: %s, can't %s" % [first, busy, cant], "%s is %s" % [first, busy], _capital(busy) + ".", true)
	if kind != "go" and station_id == "":
		return out
	var reason := _busy_soft(p)
	if reason == "":
		reason = _health_reason(p)
	if reason == "":
		reason = sim.relations.company_reason(p, "go" if kind == "go" else "work", "" if kind == "go" else station_id, with_ids)
		out["company"] = reason != ""    # (round 20: a reason of company, not of the person's own: insisting on it is paid once for a request)
	if reason != "":
		return _no(out, "%s: %s, can't %s" % [first, reason, cant], "%s is %s" % [first, reason], _capital(reason) + ", can't %s." % cant, false)
	return out


func _no(out: Dictionary, why: String, sentence: String, line: String, hard: bool) -> Dictionary:
	out["ok"] = false
	out["why"] = why
	out["sentence"] = sentence
	out["line"] = line
	out["hard"] = hard
	return out


static func _capital(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


## "Dez", "Dez and Marcus", "Dez, Ana and Marcus".
static func _and(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


# ---- errands --

## "Without you: about 60% of the loot, ..." (the numbers are the scavenge module's).
func errand_note() -> String:
	var terms: Dictionary = sim.scavenge.errand_terms()
	return "Without you: about %d%% of the loot, no rare finds, no rescue, a worse chance everyone comes home" % roundi(float(terms.loot) * 100.0)


## Whether these people would go on an errand to this place (an action "loot", "scout" or "clear", in a vehicle or on foot): {"ok" (the
## trip can start with those who agree), "why" (the trip's own refusal first: `scavenge.why_not_errand`, the hour, the dead at the
## gate, the seats and the fuel, the place; else "Nobody can go: Ana is tending a patient, Dez is down"; "" when ok), "going" (the
## people who agree), "refused" ([{"id", "name", "why", "hard"}], each in the words of `reason_not(p, "go")`), "delay_s" (the slowest of
## those going), "tone" (the least willing's), "terms" (`scavenge.errand_terms()`), "loot_note"}. `with_ids`: the ids of who is going
## together, for a refusal of company ("won't go with Walt"): those asked, unless a roster that asks everyone at once names the party
## it means (the Map page's chips: the people ticked). Pure.
func errand_willingness(people: Array, place_id: String, action: String = "loot", vehicle_id: String = "", with_ids = null) -> Dictionary:
	var out := {"ok": false, "why": "", "going": [], "refused": [], "delay_s": 0.0, "tone": "refused", "terms": sim.scavenge.errand_terms(), "loot_note": errand_note()}
	var going: Array = []
	var refused: Array = []
	var sentences: Array = []
	var seen := {}
	var asked: Array = _ids_of(people) if with_ids == null else (with_ids as Array)    # (who else is going, for a soft reason of company)
	for p in people:
		if p == null or seen.has(String(p.id)):
			continue
		seen[String(p.id)] = true
		var r := _reason_not(p, "go", "-", CANT_GO, asked)
		var hard := bool(r.hard)
		var why := String(r.why)
		var sentence := String(r.sentence)
		if r.ok:
			if sim.scavenge.can_go(p):
				going.append(p)
				continue
			hard = true    # (the trip's rules will not take them, whatever they say)
			why = "%s cannot go now." % String(p.first)
			sentence = "%s cannot go now" % String(p.first)
		elif not hard and not sim.scavenge.can_go(p, false, true):
			hard = true    # (a fever too far gone, kept apart, in a party: not a thing to push)
		refused.append({"id": String(p.id), "name": String(p.first), "why": why, "hard": hard, "company": bool(r.get("company", false)) and not hard})
		sentences.append(sentence)
	out["going"] = going
	out["refused"] = refused
	var trip_why: String = String(sim.scavenge.why_not_errand(going, place_id, action, vehicle_id)) if not going.is_empty() else String(sim.scavenge.why_not_when())
	if trip_why == "" and not going.is_empty():
		trip_why = _waits_why(going.map(func(q): return String(q.id)))
	if trip_why != "":
		out["why"] = trip_why
		return out
	if going.is_empty():
		out["why"] = "Nobody is going." if sentences.is_empty() else "Nobody can go: " + ", ".join(sentences)
		return out
	var slowest := 0.0
	var least := 1000.0
	for p in going:
		slowest = maxf(slowest, delay_for(trust_of(p)))
		least = minf(least, trust_of(p))
	out["ok"] = true
	out["delay_s"] = slowest
	out["tone"] = tone_for(least)
	return out


## Asks these people to go on an errand: {"ok", "line" (the first of those going says it, by tone), "why", "going", "refused", "delay_s",
## "tone", "insisted"}. `args.insist` sends those who refused softly too, each at INSIST_COST of trust and a blow to the mood (nothing is
## paid when the trip itself is refused). Those who agree are queued in `errand_wait`; after `delay_s` of the radio's time `scavenge.send`
## makes the party (a trip that cannot start then, the hour having passed, is logged: "The errand could not start: ..."). An errand brings
## less than the player's own trip: `scavenge.errand_terms()`.
func request_errand(people: Array, place_id: String, action: String = "loot", vehicle_id: String = "", args: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "line": "", "why": "", "going": [], "refused": [], "delay_s": 0.0, "tone": "refused", "insisted": false}
	if leader() == null:
		out["why"] = "Nobody is on the radio"
		return out
	var w := errand_willingness(people, place_id, action, vehicle_id)
	out["refused"] = w.refused
	var agree := {}
	for p in w.going:
		agree[String(p.id)] = true
	var soft := {}
	var company := {}    # (the soft refusals that are of company: "staying with Dez", "won't go with Walt")
	if bool(args.get("insist", false)):
		for r in w.refused:
			if not bool(r.hard):
				soft[String(r.id)] = true
				if bool(r.get("company", false)):
					company[String(r.id)] = true
	var go: Array = []
	var pushed: Array = []
	for p in people:
		if p == null or go.has(p):
			continue
		if agree.has(String(p.id)):
			go.append(p)
		elif soft.has(String(p.id)):
			go.append(p)
			pushed.append(p)
	if go.is_empty():
		out["why"] = String(w.why)
		_say_the_refusal(people)
		return out
	var trip_why: String = String(sim.scavenge.why_not_errand(go, place_id, action, vehicle_id, true))
	if trip_why == "":
		trip_why = _waits_why(ids_of(go))
	if trip_why != "":
		out["why"] = trip_why
		return out
	var company_paid := false
	for p in pushed:
		if company.has(String(p.id)):
			# (pushing past a reason of company costs once for the whole request, not once for each of the people who share it)
			if company_paid:
				continue
			company_paid = true
		add_trust(p, -INSIST_COST, "You pushed them to go when they could not")
		sim.morale.shock(p, INSIST_MORALE, "Pushed to go when they could not")
	var delay := 0.0
	var least := 1000.0
	var ids: Array = []
	for p in go:
		delay = maxf(delay, delay_for(trust_of(p)))
		least = minf(least, trust_of(p))
		ids.append(String(p.id))
	_replace_waits(ids)
	errand_wait.append({"ids": ids, "place": place_id, "action": action, "vehicle": vehicle_id, "left": delay})
	var tone := "doubtful" if pushed.has(go[0]) else tone_of(go[0])
	var line := String(ERRAND_LINES[tone])
	_say(go[0], "errand", true, line, tone)
	var still: Array = []
	for r in w.refused:
		if not soft.has(String(r.id)):
			still.append(r)
	out["ok"] = true
	out["line"] = line
	out["going"] = go
	out["refused"] = still
	out["delay_s"] = delay
	out["tone"] = tone_for(least) if pushed.is_empty() else "doubtful"
	out["insisted"] = not pushed.is_empty()
	return out


func _ids_of(people: Array) -> Array:
	var ids: Array = []
	for p in people:
		if p != null:
			ids.append(String(p.id))
	return ids


## The ids of these people.
static func ids_of(people: Array) -> Array:
	var out: Array = []
	for p in people:
		out.append(String(p.id))
	return out


## Why one more errand cannot be queued: the parties that are out and the errands that wait for their delay (those of other people than
## `ids`: asking again for the same ones replaces their errand) fill what the game allows ("" when there is room).
func _waits_why(ids: Array) -> String:
	var town: bool = bool(sim.scavenge.town_mode)
	var waiting := 0
	for e in errand_wait:
		for id in e.ids:
			if not ids.has(String(id)):
				waiting += 1
				break
	if sim.scavenge.parties.size() + waiting >= (sim.scavenge.MAX_PARTIES_TOWN if town else 1):
		return "Both parties are out." if town else "A party is already out."
	return ""


## The first soft refusal of those asked says its line aloud (a bubble over their head, as a verb's does).
func _say_the_refusal(people: Array) -> void:
	var asked := _ids_of(people)
	for p in people:
		if p == null:
			continue
		var r := _reason_not(p, "go", "-", CANT_GO, asked)
		if not r.ok and String(r.line) != "":
			_say(p, "errand", false, String(r.line), "refused")
			return


## A new errand for these people replaces what they were waiting to do (an errand, a verb).
func _replace_waits(ids: Array) -> void:
	var i := errand_wait.size() - 1
	while i >= 0:
		var rest: Array = []
		for id in errand_wait[i].ids:
			if not ids.has(id):
				rest.append(id)
		if rest.is_empty():
			errand_wait.remove_at(i)
		else:
			errand_wait[i]["ids"] = rest
		i -= 1
	i = pending.size() - 1
	while i >= 0:
		if ids.has(String(pending[i].who)):
			pending.remove_at(i)
		i -= 1


## The errands whose time is up set off.
func _tick_errands(dt: float) -> void:
	var due: Array = []
	var i := errand_wait.size() - 1
	while i >= 0:
		errand_wait[i]["left"] = float(errand_wait[i].left) - dt
		if float(errand_wait[i].left) <= 0.0:
			due.push_front(errand_wait[i])
			errand_wait.remove_at(i)
		i -= 1
	for e in due:
		_start_errand(e)


## The party is made now, of those who can still go (someone lost or down meanwhile stays): they are off their stance and their patient,
## and `scavenge.send` takes them. When it cannot (the hour has passed, the dead at the gate...) the radio says so.
func _start_errand(e: Dictionary) -> void:
	if sim.get("scavenge") == null:
		return
	var people: Array = []
	var stayers: Array = []
	for id in e.ids:
		var p = _person(String(id))
		if p != null and _hard_reason(p) == "" and _busy_hard(p) == "":
			people.append(p)
		elif p != null and not (p.dead or p.turned):
			stayers.append(p)    # (someone who is down, away or already out stays behind)
	if people.is_empty():
		_errand_failed(e, "nobody is left who can go")
		return
	var why: String = String(sim.scavenge.why_not_errand(people, String(e.place), String(e.action), String(e.vehicle), true))
	if why != "":
		_errand_failed(e, why)
		return
	for p in people:
		clear_stance(p)
		_leave_patient(p)
	if not sim.scavenge.send(people, String(e.place), String(e.action), String(e.vehicle)):
		_errand_failed(e, "the party could not be made")
		return
	# (the others who were asked and could not go now say so, in the words of their refusal)
	if not stayers.is_empty():
		var names: Array = []
		var reasons_why: Array = []
		for q in stayers:
			names.append(String(q.first))
			var hard := _hard_reason(q)
			reasons_why.append(hard if hard != "" else "%s is %s" % [String(q.first), _busy_hard(q)])
		log_news("errand", "%s %s at the base." % [_and(names), "stays" if names.size() == 1 else "stay"], ". ".join(reasons_why) + ".")


func _errand_failed(e: Dictionary, why: String) -> void:
	var names: Array = []
	for id in e.ids:
		var q = _person(String(id))
		if q != null and not (q.dead or q.turned) and q.away == null:
			names.append(String(q.first))    # (those who are here: not the dead, not those gone on a trip of their own)
	var first_word := why.get_slice(" ", 0)
	var spoken := why
	var is_name := false
	for q in sim.people:
		is_name = is_name or String(q.first) == first_word
	if not is_name:
		spoken = why.substr(0, 1).to_lower() + why.substr(1)
	log_news("errand", "The errand could not start: %s" % spoken, "" if names.is_empty() else "%s %s at the base." % [_and(names), "stays" if names.size() == 1 else "stay"])


# ---- jobs and posts --

## Whether this person would take this day job (`station_id` "" is taking them off the one they have): {"ok", "why", "hard", "line"
## (what they say, by the tone of their trust: "Right away." / "Fine. I'll do it." / "...if you say so."; their refusal when they
## refuse), "tone", "delay_s" (0: a roster change is a plan, answered at once)}. Refused: the player ("You: no seat, you are the player"),
## then the reasons a person has (`reason_not(p, "work", station_id)`: the hard ones, so that no soft reason is offered on top of a seat
## that is not there), then the station (`jobs.why_not`: a full one names its crew, "no free seat at the Workbench: Dez and Marcus hold
## it", hard; one not built yet), then the soft reasons. Pure.
func job_willingness(p, station_id: String) -> Dictionary:
	var out := {"ok": true, "why": "", "hard": false, "line": "", "tone": "", "delay_s": 0.0}
	if p == null:
		return _work_no(out, "Nobody answers", "", true)
	if _is_leader(p):
		return _work_no(out, NO_SEAT_FOR_YOU, "", true)
	var r := _reason_not(p, "work", station_id, CANT_JOB)
	if not r.ok and bool(r.hard):
		return _work_no(out, String(r.why), String(r.line), true)
	var station_why := _station_why(p, station_id)
	if station_why != "":
		return _work_no(out, station_why, "", true)
	if not r.ok:
		return _work_no(out, String(r.why), String(r.line), false)
	out["tone"] = tone_of(p)
	out["line"] = String(WORK_LINES[out.tone])
	return out


func _work_no(out: Dictionary, why: String, line: String, hard: bool) -> Dictionary:
	out["ok"] = false
	out["why"] = why
	out["line"] = line
	out["hard"] = hard
	out["tone"] = "refused"
	out["delay_s"] = 0.0
	return out


## Why this station cannot have this person, in words: the jobs module's, with the crew named when the seats are all taken.
func _station_why(p, station_id: String) -> String:
	if station_id == "":
		return ""
	var why: String = sim.jobs.why_not(p, station_id)
	if why == "":
		return ""
	if sim.jobs.unlocked(station_id) and sim.jobs.seats_left(station_id) <= 0:
		var holders: Array = []
		for q in sim.jobs.crew_of(station_id):
			if q.away == null:
				holders.append(String(q.first))
		if not holders.is_empty():
			return "%s: %s %s it" % [why, _and(holders), "holds" if holders.size() == 1 else "hold"]
	return why


## Asks this person to take this day job: the answer at once ({"ok", "line", "why", "hard", "tone", "insisted"}); on ok `jobs.assign` is
## done and they say it. `args.insist` overrides a soft refusal at INSIST_COST (never one the station or a hard reason gives).
func request_job(p, station_id: String, args: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "line": "", "why": "", "hard": true, "tone": "refused", "insisted": false}
	if p == null or leader() == null:
		out["why"] = "Nobody is on the radio" if leader() == null else "Nobody answers"
		return out
	var w := job_willingness(p, station_id)
	return _answer_work(p, w, args, "job", func(): return sim.jobs.assign(p, station_id))


## Asks this person to hold this night post.
func post_willingness(p, post_id: String) -> Dictionary:
	var out := {"ok": true, "why": "", "hard": false, "line": "", "tone": "", "delay_s": 0.0}
	if p == null:
		return _work_no(out, "Nobody answers", "", true)
	if _is_leader(p):
		return _work_no(out, NO_POST_FOR_YOU, "", true)
	var r := _reason_not(p, "work", post_id, CANT_POST)
	if not r.ok and bool(r.hard):
		return _work_no(out, String(r.why), String(r.line), true)
	if sim.jobs.post(post_id).is_empty():
		return _work_no(out, "There is no such post", "", true)
	var holder = _post_holder(p, post_id)
	if holder != null:
		return _work_no(out, "You hold that post" if _is_leader(holder) else "%s holds that post" % String(holder.first), "", true)
	if not r.ok:
		return _work_no(out, String(r.why), String(r.line), false)
	out["tone"] = tone_of(p)
	out["line"] = String(WORK_LINES[out.tone])
	return out


## Who else holds this post (alive), or null: `jobs.set_post` refuses it for that reason.
func _post_holder(p, post_id: String):
	for q in sim.people:
		if q != p and not (q.dead or q.turned) and String(sim.jobs.post_ids.get(String(q.id), "")) == post_id:
			return q
	return null


func request_post(p, post_id: String, args: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "line": "", "why": "", "hard": true, "tone": "refused", "insisted": false}
	if p == null or leader() == null:
		out["why"] = "Nobody is on the radio" if leader() == null else "Nobody answers"
		return out
	var w := post_willingness(p, post_id)
	return _answer_work(p, w, args, "post_set", func(): return sim.jobs.set_post(p, post_id))


## Whether this person would go and fix this problem of the base (round 25, problems.gd owns the rules and asks `reason_not` for the words):
## {"ok", "why", "hard", "line", "tone", "delay_s", "chance", "cost", "eta_h"}. Pure.
func fix_willingness(p, problem_id) -> Dictionary:
	return sim.problems.fix_willingness(p, problem_id)


## Asks this person to go and fix this problem ({"ok", "line", "why", "hard", "tone", "insisted", "chance"}); `args.insist` as `request_job`.
func request_fix(problem_id, p, args: Dictionary = {}) -> Dictionary:
	return sim.problems.request_fix(problem_id, p, args)


## The answer to a request for a day job or a night post: refused with their words (a soft refusal pushed at INSIST_COST when asked to),
## or done (`apply`) with their line. They say the line aloud (a radio_line, `verb` "job" or "post_set").
func _answer_work(p, w: Dictionary, args: Dictionary, verb: String, apply: Callable) -> Dictionary:
	var insisted := false
	if not bool(w.ok):
		if not (bool(args.get("insist", false)) and not bool(w.hard)):
			_say(p, verb, false, String(w.line), "refused")
			return {"ok": false, "line": String(w.line), "why": String(w.why), "hard": bool(w.hard), "tone": "refused", "insisted": false}
		insisted = true
		w = {"ok": true, "why": "", "hard": false, "line": String(WORK_LINES["doubtful"]), "tone": "doubtful"}
	if not bool(apply.call()):
		return {"ok": false, "line": "", "why": "That cannot be done now", "hard": true, "tone": "refused", "insisted": false}
	if insisted:
		add_trust(p, -INSIST_COST, "You pushed them to take work when they could not")
		sim.morale.shock(p, INSIST_MORALE, "Pushed to take work when they could not")
	_say(p, verb, true, String(w.line), String(w.tone))
	return {"ok": true, "line": String(w.line), "why": "", "hard": false, "tone": String(w.tone), "insisted": insisted}


# ---- fill the empty seats --

## What "Fill empty seats" would do: {"seats" ([{"station", "left"}]: the stations with an open seat), "free" (ids of the people with no job
## who would take one), "stuck" ([{"id", "name", "why"}]: those with no job who would not, and why)}. The player is not in it. Pure.
func fill_willingness() -> Dictionary:
	var seats: Array = []
	for st in sim.jobs.stations():
		var open: int = sim.jobs.seats_of(String(st.id)) - sim.jobs.crew_of(String(st.id)).size()
		if open > 0 and not sim.jobs.MANUAL.has(String(st.id)):
			seats.append({"station": String(st.id), "left": open})
	var free: Array = []
	var stuck: Array = []
	for p in sim.people:
		if p.dead or p.turned or _is_leader(p) or String(sim.jobs.job_of(p)) != "":
			continue
		var r := _reason_not(p, "work", "any", CANT_JOB)
		if r.ok:
			free.append(String(p.id))
		else:
			stuck.append({"id": String(p.id), "name": String(p.first), "why": String(r.why)})
	return {"seats": seats, "free": free, "stuck": stuck}


## Gives the open seats to the people with no job (`jobs.fill_empty`: the best fit for each, nobody taken off a job, not those who would
## not today): {"ok" (a seat was filled), "assigned" ([{"who", "station"}]), "stuck" ([{"id", "name", "why"}]: who could not and why), "line"}.
func request_fill() -> Dictionary:
	var out := {"ok": false, "assigned": [], "stuck": [], "line": ""}
	if leader() == null:
		out["line"] = "Nobody is on the radio"
		return out
	var w := fill_willingness()
	var skip: Array = []
	for s in w.stuck:
		skip.append(String(s.id))
	var before := {}
	for p in sim.people:
		before[String(p.id)] = String(sim.jobs.job_of(p))
	var n: int = sim.jobs.fill_empty(skip)
	var assigned: Array = []
	var told: Array = []
	for p in sim.people:
		var now := String(sim.jobs.job_of(p))
		if String(before[String(p.id)]) == "" and now != "":
			assigned.append({"who": String(p.id), "station": now})
			told.append("%s at the %s" % [String(p.first), String(sim.jobs.station(now).get("name", now))])
	var stuck: Array = w.stuck.duplicate(true)
	for id in w.free:
		var q = _person(String(id))
		if q != null and String(sim.jobs.job_of(q)) == "":
			stuck.append({"id": String(id), "name": String(q.first), "why": "%s: no seat is open" % String(q.first)})
	out["ok"] = n > 0
	out["assigned"] = assigned
	out["stuck"] = stuck
	if n > 0:
		out["line"] = "Filled %d seat%s: %s." % [n, "" if n == 1 else "s", _and(told)]
	elif w.seats.is_empty():
		out["line"] = "Every seat is taken."
	elif w.free.is_empty():
		out["line"] = "Nobody without a job can take a seat now."
	else:
		out["line"] = "No seat is open to the people who are free."
	return out


# ---- buildings --

## Whether this building can be ordered now: {"ok", "why" (`build.why_not_build`: "it needs 30 scrap", "it needs the workshop first", "claim
## the north street first"...; "" when ok), "plot" (its home), "cost" (scrap), "note" (the crew, advice and never a refusal: "Nobody is on
## the Builders job: give it to someone on the Jobs page, or the site waits", "Dez is the only builder and is down"; "" when the
## crew is fine)}. Pure.
func build_willingness(building_id: String) -> Dictionary:
	var b: Dictionary = sim.build.building(building_id)
	var why: String = sim.build.why_not_build(building_id)
	return {"ok": why == "", "why": why, "plot": String(sim.build.home_for(building_id)), "cost": int(b.get("scrap", 0)), "note": _build_note()}


## The Builders crew, as advice: nobody; the only builder down or away; none of them able.
func _build_note() -> String:
	var crew: Array = []
	for q in sim.jobs.crew_of("builders"):
		if not _is_leader(q):
			crew.append(q)
	if crew.is_empty():
		return NO_BUILDERS
	for q in crew:
		if _hard_reason(q) == "":
			return ""
	if crew.size() == 1:
		var q = crew[0]
		return "%s is the only builder and is %s" % [String(q.first), _hard_reason(q).trim_prefix("%s is " % String(q.first))]
	var parts: Array = []
	for q in crew:
		parts.append(_hard_reason(q))
	return "None of the builders can work now: " + ", ".join(parts)


## The builder who would lead the work: the one on his feet at the Builders job with the most Building (null when none).
func _lead_builder():
	var best = null
	for q in sim.jobs.crew_of("builders"):
		if _is_leader(q) or _hard_reason(q) != "":
			continue
		if best == null or int(q.skills.Building) > int(best.skills.Building):
			best = q
	return best


## Orders the building on its home (`build.order`): {"ok", "line" (the lead builder's words, by tone of trust), "why", "plot", "who" (the
## lead builder's id, or "")}; the radio logs it (news kind "build").
func request_build(building_id: String, _args: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "line": "", "why": "", "plot": "", "who": ""}
	if leader() == null:
		out["why"] = "Nobody is on the radio"
		return out
	var w := build_willingness(building_id)
	out["plot"] = String(w.plot)
	if not bool(w.ok):
		out["why"] = String(w.why)
		return out
	if not sim.build.order(String(w.plot), building_id):
		out["why"] = String(sim.build.why_not(String(w.plot), building_id))
		return out
	var lead = _lead_builder()
	var name := String(sim.build.building(building_id).get("name", building_id))
	var sub := "%d scrap spent" % int(w.cost)
	if lead != null:
		var tone := tone_of(lead)
		out["line"] = String(BUILD_LINES[tone])
		out["who"] = String(lead.id)
		_say(lead, "build", true, String(out.line), tone)
		sub += ". %s builds it." % String(lead.first)
	else:
		out["line"] = "Ordered. Nobody is on the Builders job: the site waits."
		sub += ". The site waits for a builder."
	log_news("build", "%s ordered" % name, sub)
	out["ok"] = true
	return out


# ---- saving the errands --

func _errands_saved() -> Array:
	var out: Array = []
	for e in errand_wait:
		out.append({"ids": e.ids.duplicate(), "place": String(e.place), "action": String(e.action), "vehicle": String(e.vehicle), "left": float(e.left)})
	return out


## Reads them again; whatever is not sound is left out, and an id that names nobody is dropped from its entry.
func _load_errands(raw) -> void:
	errand_wait.clear()
	if not (raw is Array):
		return
	for r in raw:
		if not (r is Dictionary) or typeof(r.get("place")) != TYPE_STRING or String(r.place) == "":
			continue
		if not ERRAND_ACTIONS.has(String(r.get("action", ""))) or not _number(r.get("left")) or not (r.get("ids") is Array):
			continue
		var ids: Array = []
		for id in r.ids:
			if typeof(id) == TYPE_STRING and _person(String(id)) != null and not ids.has(String(id)):
				ids.append(String(id))
		if ids.is_empty():
			continue
		var vehicle = r.get("vehicle", "")
		errand_wait.append({"ids": ids, "place": String(r.place), "action": String(r.action), "vehicle": String(vehicle) if typeof(vehicle) == TYPE_STRING else "", "left": clampf(float(r.left), 0.0, MAX_ERRAND_WAIT_S)})


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
	# (round 19: a call's time is the game's, and the game may be running at 3x: the view slows it for the calls that cannot wait, `URGENT_KINDS`)
	sim.events.append({"type": "call_raised", "id": int(e.id), "kind": kind, "urgent": URGENT_KINDS.has(kind)})
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


func _settle(e: Dictionary, option_id: String, by_default: bool, quiet: bool = false) -> void:
	e["answered"] = option_id
	e["by_default"] = by_default
	e["result"] = _carry_out(e, option_id)
	if not quiet:
		sim.events.append({"type": "radio_answered", "id": int(e.id), "option": option_id, "by_default": by_default})


## A wall's older calls are over when a newer one says more of it (round 19: the wall is going, the wall is down): the open calls
## of these kinds about this section take their default, quietly (no answer is announced); and when `kinds` has "attack" the old call
## is not made for this section again tonight.
func settle_wall_calls(seg, kinds: Array) -> void:
	for e in news:
		if _open(e) and kinds.has(String(e.kind)) and int(e.data.get("seg", -1)) == int(seg.id):
			_settle(e, String(e.default), true, true)
	if kinds.has("attack"):
		_attack_called["%s:%d" % ["n" if sim.is_night() else "d", int(seg.id)]] = true


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
		"dilemma":
			return sim.dilemmas.carry_out(e, option_id)    # (round 25: the fever outbreak, treat or quarantine: dilemmas.gd)
		"problem":
			return sim.problems.carry_out(e, option_id)    # (round 25: trouble at the halfway mark, send someone or leave it: problems.gd)
		_:
			return night.carry_out(e, option_id)    # (the calls of the night, round 19: night_calls.gd)
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
	night.watch()


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
		if sim.dilemmas.claims(p):    # (round 25: an outbreak the camp is deciding on holds them: no plain call; false inactive)
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


## "Send two" (round 19, the calls of the night): the `n` free defenders nearest the section who do not already hold it (their post is
## not on it; if there are fewer of those, the nearest of its own make up the number) go to the section's nearest posts that nobody
## holds (the avatar's own post is nobody's), or behind the wall when there are none. The old call above sends everyone. Returns
## how many went.
func _reinforce_near(seg, n: int) -> int:
	var own: Array = []
	var others: Array = []
	for p in sim.people:
		if not _free_to_go(p):
			continue
		if _post_at(seg, sim.jobs.post_pos(p)):
			own.append(p)
		else:
			others.append(p)
	var nearer := func(a, b): return Vector2(a.x, a.y).distance_to(seg.center) < Vector2(b.x, b.y).distance_to(seg.center)
	own.sort_custom(nearer)
	others.sort_custom(nearer)
	var crew: Array = others + own
	if crew.size() > n:
		crew.resize(maxi(n, 0))
	var held: Array = []
	for q in sim.people:
		if not (q.dead or q.turned or _is_leader(q)):
			held.append(Vector2(sim.jobs.post_pos(q)))
	var spots: Array = []
	for po in sim.jobs.posts():
		var at := Vector2(po.pos)
		var taken := false
		for h in held:
			taken = taken or h.distance_to(at) < 0.5
		if not taken:
			spots.append(at)
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
		sim.gate.on_alarm()    # (round 22, avatar mode: the gate shuts unless something is in the gateway, gate.gd)
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
		"errand_wait": _errands_saved(),
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
		"night": night.save(),
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
	_load_errands(d.get("errand_wait", []))
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
	var nd = d.get("night", {})
	if nd is Dictionary:
		night.load_state(nd)    # (a save from before round 19 has none: no promise, no call remembered)


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
