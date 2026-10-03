## The calls and notices of the night (round 19, slice 3, S3.3 and S3.4: docs/superpowers/plans/2026-10-03-round-19.md). The radio
## (`sim.radio.night`) watches the walls and the clock in avatar mode and speaks to the player when a night needs him; it only ever
## ASKS: every call has its options and a default that is taken when nobody answers, and what the community does without him is
## what the nights' rules (nights.gd, waves.gd) give it. Everything here is behind avatar mode (`sim.player_id != ""`; `watch` is only
## called then) and the settlement's own sim (`sim.nights_on`): with no avatar nothing is raised and nothing is saved.
##
## CALLS (`radio.raise_call`; once for a section a night each; a call raised while the avatar is away has no option that needs him at
## the base, so it reads as a plain warning):
##   going   a compound section under `calls.going_below` of its health with two of the dead at it, or a plated brute at it
##           (hold | send two | I'm on my way | fall back). It settles the section's open `attack` call by its default, quietly.
##   brute   a brute on its way to a section, within `calls.brute_warn_r` tiles of it
##           (keep the guns on it | I'll take it | send two | draw it to the best defended other section, 3 scrap)
##   breach  a compound section has fallen in the night (hold the line | close it, needs you there | pull back | I'm on my way)
##   night   the lookout has given the forecast and the night is Big (hold: understood | call to arms now | the alarm on the best
##           defended section, 3 scrap), until the bell
##   night_road  a played trip is out and the dusk with a Big Night is coming (news at "soon", a call at "now", see `road_status`)
## NEWS ONLY: `forecast` (the day-ahead notice of a Big Night at noon, only when someone is at the Radio desk), `night_road`, and
## "The <wall> is shut again" (kind `breach`, no options) when a breach has been closed.
##
## WHAT AN OPTION DOES (`carry_out`, from `Radio._carry_out`): reinforce sends the nearest `calls.reinforce_n` free defenders who do
## not already hold the wall (`Radio._reinforce_near`); fall_back is the old `Radio._fall_back`; coming is a promise (`focus`): the
## defenders near the wall are lifted at once, and when the avatar is near it before the time is up each of them trusts him more, else
## less; close sends the two nearest free defenders to mend the breach (they work only while the avatar rallies them: nights.gd);
## lure is `tactics.order_lure`; arms is `radio.alarm(true)`; home (the road call) sets `leave_requested`, which the place's scene reads.
##
## THE ROAD HOME (S3.4): `road_status()` for a played trip that is in its place or on the road home: the dusk, the road, the hour to
## leave by (`forecast.road_margin_min` before the dusk) and "free", "soon", "now" or "late". `Scavenge.night_warning` asks the same
## numbers for a trip that has not begun.
extends RefCounted

const Kinds := preload("res://scripts/sim/kinds.gd")
const Lots := preload("res://scripts/sim/lots.gd")
const NightData := preload("res://scripts/sim/night_data.gd")

## How many go to mend a breach ("the two nearest").
const CLOSE_N := 2
## The notice of a Big Night is made when the desk is staffed within this many hours of the notice hour (a person walking to it).
const NOTICE_WINDOW_H := 0.5

## Who has been called for what, and the day it is for: "going:3" (a section), "night", "road-soon"... to a day (`sim.day`).
var called := {}
## What each wall section's state was last step (segment id to state): a fall is a change to 3.
var seen := {}
## The breaches that have been called and are not shut yet (segment id to the day).
var breaches := {}
## The day whose noon has been looked at for the day-ahead notice.
var notice_day := 0
## What the player has promised ("I'm on my way"): {"seg": id, "until": sim.clock_min, "who": [ids of those who were told]} or {}.
var focus := {}
## Whether the player has asked to head home from the place (the place's scene reads it and clears it). Not saved.
var leave_requested := false

var sim
var radio


func setup(r) -> void:
	radio = r
	sim = r.sim


## A new run, or the start of a load: nothing is remembered.
func reset() -> void:
	called = {}
	seen = {}
	breaches = {}
	notice_day = 0
	focus = {}
	leave_requested = false


# ------------------------------------------------------------------- the words --

## "08:20" for an hour of the day.
static func clock_text(h: float) -> String:
	var total := roundi(fposmod(h, 24.0) * 60.0)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [(total / 60) % 24, total % 60]


## "1 h 20", "2 h", "40 min": a stretch of game minutes.
static func duration_text(minutes: float) -> String:
	var m := maxi(0, roundi(minutes))
	@warning_ignore("integer_division")
	var h := m / 60
	var r := m % 60
	if h == 0:
		return "%d min" % r
	if r == 0:
		return "%d h" % h
	return "%d h %d" % [h, r]


## The hour of the day of a game minute (the run's clock begins at 07:00).
static func hour_of(clock_min: float) -> float:
	return fposmod(clock_min / 60.0 + 7.0, 24.0)


static func _word(n: int) -> String:
	var words := ["no one", "one", "two", "three", "four", "five", "six"]
	return words[n] if n >= 0 and n < words.size() else str(n)


## "the school bus" (a section's name in a sentence).
func _the(seg) -> String:
	return "the %s" % String(seg.name).to_lower()


func _the_cap(seg) -> String:
	return "The %s" % String(seg.name).to_lower()


# --------------------------------------------------------------- the situation --

## Whether this has been done for this day: false (and noted) the first time, true after.
func _once(key: String) -> bool:
	if int(called.get(key, -1)) == int(sim.day):
		return false
	called[key] = int(sim.day)
	return true


## The avatar is at the base and up: what "I'm on my way" and "close it" need.
func avatar_here() -> bool:
	var lead = radio.leader()
	return lead != null and lead.away == null and not lead.dead and not lead.turned and not lead.downed


## Whether the avatar stands within the rally's reach of the section.
func _avatar_within(seg) -> bool:
	var lead = radio.leader()
	if lead == null or lead.away != null or lead.dead or lead.turned:
		return false
	return Vector2(lead.x, lead.y).distance_to(seg.center) <= NightData.num("rally.radius", 9.0)


## The people the avatar would be among: up, here, not him.
func _defenders() -> Array:
	var out: Array = []
	for p in sim.people:
		if p.dead or p.turned or p.downed or p.away != null or radio._is_leader(p):
			continue
		out.append(p)
	return out


func _is_compound(seg) -> bool:
	return seg.kind != sim.DOOR_KIND and int(seg.id) < Lots.FIRST_SEGMENT_ID


## Tonight (the night that follows `sim.day`) is a Big Night.
func _tonight_big() -> bool:
	return not sim.waves.big_night(int(sim.day)).is_empty()


## An outlook that needs the player: a Big Night (the plan's `needs_you`), or one with plated brutes.
func _needs_you(o: Dictionary) -> bool:
	return bool(o.get("needs_you", false)) or String(o.get("kind", "ordinary")) != "ordinary" or int(o.get("plated", 0)) > 0


## How the compound's sections rank as a place for the dead to be drawn to: the most guns that cover it, then the most health.
func _lure_better(a, b) -> bool:
	var ca: int = sim.tactics.coverage_of(a)
	var cb: int = sim.tactics.coverage_of(b)
	if ca != cb:
		return ca > cb
	return a.hp / a.max_hp > b.hp / b.max_hp + 1.0e-9


## The compound section the alarm is best set on: the one the most guns cover, then the one with the most health, that is not `avoid`
## (a section, or its id), not a door, not down, and that the alarm can be set on now (`tactics.why_not_lure`: scrap, no alarm
## already ringing). Null when there is none.
func best_lure_section(avoid = null):
	var avoid_id := -1
	if avoid != null:
		avoid_id = int(avoid) if (typeof(avoid) == TYPE_INT or typeof(avoid) == TYPE_FLOAT) else int(avoid.id)
	var best = null
	for s in sim.segments:
		if not _is_compound(s) or int(s.id) == avoid_id or s.state == 3 or sim.tactics.why_not_lure(s) != "":
			continue
		if best == null or _lure_better(s, best):
			best = s
	return best


# ----------------------------------------------------------------------- watching --

## Once a step, in avatar mode (`Radio.update`, after the radio's own calls).
func watch() -> void:
	if not radio.avatar_mode() or not sim.nights_on:
		return
	_watch_walls()
	_watch_focus()
	_watch_forecast()
	_watch_road()


## The walls: the calls of a wall that is going, a brute on its way and a breach, and the news of a breach that is shut again.
func _watch_walls() -> void:
	var night: bool = sim.is_night()
	var warn_r := NightData.num("calls.brute_warn_r", 40.0)
	var below := NightData.num("calls.going_below", 0.4)
	for s in sim.segments:
		if not _is_compound(s):
			continue
		var id := int(s.id)
		var was := int(seen.get(id, 0))
		seen[id] = int(s.state)
		if s.state != 3 and breaches.has(id):
			breaches.erase(id)
			radio.log_news("breach", "%s is shut again" % _the_cap(s), "", {"at": s.center})
		if not night:
			continue
		if s.state == 3:
			if was != 3:
				_raise_breach(s)
			continue
		var attackers := 0
		var plated_at := false
		var coming = null
		for sl in s.slots:
			var z = sl.who
			if z == null:
				continue
			if z.state == "attack":
				attackers += 1
				if z.kind == Kinds.BRUTE and z.plated:
					plated_at = true
			elif z.state == "approach" and z.kind == Kinds.BRUTE and z.slot == sl and coming == null and Vector2(z.x, z.y).distance_to(s.center) <= warn_r:
				coming = z
		if coming != null:
			_raise_brute(s, coming)
		var share: float = s.hp / s.max_hp
		if (share < below and attackers >= 2) or plated_at:
			_raise_going(s, attackers, share, plated_at)


func _raise_going(s, attackers: int, share: float, plated: bool) -> void:
	if not _once("going:%d" % int(s.id)):
		return
	radio.settle_wall_calls(s, ["attack"])
	var pct := roundi(share * 100.0)
	var text := "%s is going" % _the_cap(s)
	if share >= NightData.num("calls.going_below", 0.4):
		text = "A plated brute is tearing at %s" % _the(s)
	var sub := "%d of the dead at it, %d%% intact" % [attackers, pct]
	if plated and share < NightData.num("calls.going_below", 0.4):
		sub += ", a plated brute among them"
	var options: Array = [
		{"id": "hold", "label": "Hold"},
		{"id": "reinforce", "label": "Send %s to it" % _word(_reinforce_n())},
	]
	if avatar_here():
		options.append({"id": "coming", "label": "I'm on my way"})
	options.append({"id": "fall_back", "label": "Give it up, fall back to the school"})
	radio.raise_call("going", text, sub, options, "hold", NightData.num("calls.going_ttl_min", 20.0), {"seg": int(s.id)}, s.center)


func _raise_brute(s, z) -> void:
	if not _once("brute:%d" % int(s.id)):
		return
	var plated: bool = z.plated
	var text := ("A plated brute at %s" if plated else "A brute at %s") % _the(s)
	var sub := "Armoured but for its head: the guns will take a wall's worth of time on it" if plated else "It tears walls down"
	var options: Array = [{"id": "watch", "label": "Keep the guns on it"}]
	if avatar_here():
		options.append({"id": "coming", "label": "I'll take it"})
	options.append({"id": "reinforce", "label": "Send %s" % _word(_reinforce_n())})
	var data := {"seg": int(s.id), "plated": plated}
	# (drawing it to another wall only makes sense when that wall is the better defended one)
	var other = best_lure_section(s)
	if other != null and _lure_better(other, s):
		options.append({"id": "lure", "label": "Draw it to the %s (%d scrap)" % [String(other.name).to_lower(), int(sim.tactics.LURE_COST)]})
		data["lure"] = int(other.id)
	radio.raise_call("brute", text, sub, options, "watch", NightData.num("calls.brute_ttl_min", 45.0), data, Vector2(z.x, z.y))


func _raise_breach(s) -> void:
	if not _once("breach:%d" % int(s.id)):
		return
	breaches[int(s.id)] = int(sim.day)
	radio.settle_wall_calls(s, ["attack", "going"])
	var options: Array = [{"id": "hold", "label": "Hold the line"}]
	var here := avatar_here()
	if here:
		options.append({"id": "close", "label": "Close it (needs you there)"})
	options.append({"id": "fall_back", "label": "Pull back to the school"})
	if here:
		options.append({"id": "coming", "label": "I'm on my way"})
	radio.raise_call("breach", "%s is down" % _the_cap(s), "The dead are getting in", options, "hold", NightData.num("calls.breach_ttl_min", 20.0), {"seg": int(s.id)}, s.center)


func _reinforce_n() -> int:
	return maxi(1, int(NightData.num("calls.reinforce_n", 2.0)))


# ------------------------------------------------------------------- the promise --

## "I'm on my way" is kept when the avatar is among them before the time is up, and broken when it is up and he is not.
func _watch_focus() -> void:
	if focus.is_empty():
		return
	var seg = radio._segment(int(focus.get("seg", -1)))
	if seg == null:
		focus = {}
		return
	if _avatar_within(seg):
		_judge(true)
	elif sim.clock_min >= float(focus.get("until", 0.0)):
		_judge(false)


## Those who were told take it as it came: more trust in him for a promise kept, less for one broken.
func _judge(kept: bool) -> void:
	var who: Array = focus.get("who", [])
	focus = {}
	for id in who:
		var p = radio._person(String(id))
		if p == null or p.dead or p.turned or p.away != null:
			continue
		if kept:
			radio.add_trust(p, NightData.num("calls.kept_trust", 2.0), "You came when you said")
		else:
			radio.add_trust(p, NightData.num("calls.broken_trust", -2.0), "You said you were coming")


## The avatar says he is coming to the wall: the defenders near it are lifted now and watch for him until the time is up.
func _coming(seg) -> String:
	if not avatar_here():
		return "You are not at the base: there is nobody to promise"
	if not focus.is_empty() and int(focus.get("seg", -1)) != int(seg.id):
		var old = radio._segment(int(focus.get("seg", -1)))    # (a promise for another wall is judged now: he came, or he did not)
		_judge(old != null and _avatar_within(old))
	var who: Array = []
	var radius := NightData.num("rally.radius", 9.0)
	for p in _defenders():
		if Vector2(p.x, p.y).distance_to(seg.center) <= radius:
			sim.morale.shock(p, NightData.num("calls.coming_morale", 4.0), "Help is on the way")
			who.append(String(p.id))
	focus = {"seg": int(seg.id), "until": float(sim.clock_min) + NightData.num("calls.coming_window_min", 15.0), "who": who}
	if who.is_empty():
		return "On your way to %s: nobody is near it yet" % _the(seg)
	return "On your way to %s: they know it" % _the(seg)


# --------------------------------------------------------------------- the options --

## What the option the player (or the clock) chose does; the line that says what came of it.
func carry_out(e: Dictionary, option_id: String) -> String:
	var data: Dictionary = e.data
	var kind := String(e.kind)
	match kind:
		"going", "brute", "breach":
			var seg = radio._segment(int(data.get("seg", -1)))
			if seg == null:
				return ""
			match option_id:
				"reinforce":
					return "Reinforcements sent (%d)" % radio._reinforce_near(seg, _reinforce_n())
				"fall_back":
					return "Falling back to the school (%d)" % radio._fall_back(seg)
				"coming":
					return _coming(seg)
				"close":
					return _close(seg)
				"lure":
					return _lure(data, seg)
			return {"going": "Holding", "brute": "Keeping the guns on it", "breach": "Holding the line"}[kind]
		"night":
			match option_id:
				"arms":
					if radio.alarm_on:
						return "The alarm is already ringing"
					radio.alarm(true)
					return "Everyone to their posts"
				"lure":
					return _lure(data, null)
			return "Understood"
		"night_road":
			if option_id == "home":
				leave_requested = true
				return "Heading home"
			return "Staying out: the base holds the night alone"
	return ""


## "Close it": the nearest free defenders go to mend the fallen section, and are told to be sure of him: nobody mends it under fire
## unless he is there (nights.gd).
func _close(seg) -> String:
	if not avatar_here():
		return "You are not at the base: they will not mend it without you"
	var spot: Vector2 = sim.repair_spot(seg)
	var crew: Array = []
	for p in sim.people:
		if radio._free_to_go(p):
			crew.append(p)
	crew.sort_custom(func(a, b): return Vector2(a.x, a.y).distance_to(spot) < Vector2(b.x, b.y).distance_to(spot))
	var names: Array = []
	for p in crew:
		if names.size() >= CLOSE_N:
			break
		sim.order_repair(p, seg)
		names.append(String(p.first))
	if names.is_empty():
		return "Nobody is free to mend it"
	var who: String = names[0] if names.size() == 1 else "%s and %s" % [names[0], names[1]]
	return "%s %s to mend it. They need you there." % [who, "goes" if names.size() == 1 else "go"]


## "Draw it to...": the alarm on the section the call named (or, when that cannot be, the best now).
func _lure(data: Dictionary, avoid_seg) -> String:
	var seg = radio._segment(int(data.get("lure", -1))) if data.has("lure") else null
	if seg == null or sim.tactics.why_not_lure(seg) != "":
		seg = best_lure_section(avoid_seg)
	if seg == null:
		return "There is no wall to draw them to"
	if sim.tactics.order_lure(seg):
		return "The alarm rings at %s" % _the(seg)
	return "The alarm cannot be set: %s" % sim.tactics.why_not_lure(seg)


# ---------------------------------------------------------------------- the forecast --

## The day-ahead notice at noon (a Big Night tomorrow, when someone is at the Radio desk) and the call of the lookout's forecast.
func _watch_forecast() -> void:
	if String(sim.phase) != "day":
		return
	var from := NightData.num("forecast.notice_hour", 12.0)
	var h: float = sim.hour
	if notice_day != int(sim.day) and h >= from:
		if h > from + NOTICE_WINDOW_H:
			notice_day = int(sim.day)    # (nobody was at the desk: there is no notice, though the night will come)
		elif sim.jobs.operator("radio") != null:
			notice_day = int(sim.day)
			_tell_tomorrow()
	_watch_tonight()


## "Big Night tomorrow: The Siege" from the waves' outlook of the day after this one.
func _tell_tomorrow() -> void:
	var o: Dictionary = sim.waves.outlook(int(sim.day) + 1)
	if o.is_empty() or not _needs_you(o):
		return
	var text := "Big Night tomorrow: %s" % _night_name(o)
	var sub := "%s Be home by %s." % [describe(o), clock_text(home_hour())]
	radio.log_news("forecast", text, sub)
	sim.alert("bignight-next", "warn", text, sub, null, 60.0)


## The hour the avatar is asked to be home by: the dusk, less the road's margin.
func home_hour() -> float:
	return float(sim.seasons.dusk_hour()) - NightData.num("forecast.road_margin_min", 30.0) / 60.0


func _night_name(o: Dictionary) -> String:
	var name := String(o.get("name", ""))
	return name if name != "" else "a night for him"


## What a night will bring, as a few sentences: "About 70 to 95 from the east side (the second bus, the chain-link). 2 plated brutes
## after 23:00." from the waves' outlook.
static func describe(o: Dictionary) -> String:
	var line := "About %d to %d" % [int(o.get("low", 0)), int(o.get("high", 0))]
	var where := _where_text(o)
	if where != "":
		line += " from %s" % where
	line += "."
	var brutes := int(o.get("brutes", 0))
	if brutes > 0:
		var plated := int(o.get("plated", 0)) > 0
		var what := ("a plated brute" if plated else "a brute") if brutes == 1 else ("%d plated brutes" if plated else "%d brutes") % brutes
		var at := float(o.get("brute_at", -1.0))
		var when := ""
		if at >= 0.0:
			when = " after midnight" if is_zero_approx(fposmod(at, 24.0)) else " after %s" % clock_text(at)
		line += " %s%s." % [what.substr(0, 1).to_upper() + what.substr(1), when]
	if bool(o.get("runners", false)):
		line += " Runners with them."
	return line


## "the east side (the second bus, the chain-link)" from the outlook's "the east side: the second bus, the chain-link".
static func _where_text(o: Dictionary) -> String:
	var text := String(o.get("section_text", ""))
	var cut := text.find(": ")
	if cut >= 0:
		return "%s (%s)" % [text.substr(0, cut), text.substr(cut + 2)]
	if text != "":
		return text
	var side := String(o.get("side", ""))
	return "the %s side" % side if side != "" else ""


## From the lookout's forecast to the bell: a Big Night read by him is a call (understood, call to arms now, the alarm on the best
## defended section), until the bell. Nobody on watch gave no forecast, so there is none.
func _watch_tonight() -> void:
	if int(sim.tactics.forecast_day) != int(sim.day) or String(sim.tactics.forecast_who) == "" or radio._person(String(sim.tactics.forecast_who)) == null:
		return
	if int(called.get("night", -1)) == int(sim.day):
		return
	called["night"] = int(sim.day)
	var o: Dictionary = sim.waves.outlook(int(sim.day))
	if o.is_empty() or not _needs_you(o):
		return
	var sub := describe(o)
	var first := float(o.get("first_at", -1.0))
	if first >= 0.0:
		sub += " The first of them at about %s." % clock_text(first)
	# the community's own reading of tonight (the forecast's `ready`: posts manned, the walls the dead will come to; round 19, tactics.gd)
	var ready = sim.tactics.forecast().get("ready")
	if ready is Dictionary and ready.has("manned") and ready.has("posts") and ready.has("walls"):
		sub += " Posts %d of %d, walls %d%%." % [int(ready.manned), int(ready.posts), roundi(float(ready.walls) * 100.0)]
	var options: Array = [{"id": "hold", "label": "Understood"}, {"id": "arms", "label": "Call to arms now"}]
	var data := {"day": int(sim.day)}
	var best = best_lure_section()
	if best != null:
		options.append({"id": "lure", "label": "Alarm on the %s (%d scrap)" % [String(best.name).to_lower(), int(sim.tactics.LURE_COST)]})
		data["lure"] = int(best.id)
	var to_the_bell := maxf(1.0, (float(sim.seasons.dusk_hour()) - float(sim.hour)) * 60.0)
	radio.raise_call("night", "Big Night tonight: %s" % _night_name(o), sub, options, "hold", to_the_bell, data)


# ------------------------------------------------------------------------ the road --

## The played trip that is in its place or on the road home (the one the avatar is on, else any), or {}.
func _played_party() -> Dictionary:
	var lead = radio.leader()
	var any := {}
	for party in sim.scavenge.parties:
		if not bool(party.get("played", false)) and String(party.state) != sim.scavenge.IN_PLACE:
			continue
		if lead != null and (party.members as Array).has(String(lead.id)):
			return party
		if any.is_empty():
			any = party
	return any


## The game minute of the dusk of the night that is coming, or, from the dusk to the dawn, of the one that has come.
func _dusk_clock() -> float:
	var dusk_h: float = sim.seasons.dusk_hour()
	var h: float = sim.hour
	if String(sim.phase) == "day":
		return float(sim.clock_min) + (dusk_h - h) * 60.0
	return float(sim.clock_min) - fposmod(h - dusk_h, 24.0) * 60.0


## The road home for a played trip (`Scavenge.begin_played`): {"on" (a trip is out and is the player's), "dusk" (the game minute the
## dusk begins), "road_min" (the road home), "leave_by" (the game minute by which the party must leave the place to be home
## `forecast.road_margin_min` before the dusk), "left_min" (minutes to that: negative when it is past; on the road home, minutes to
## spare on the arrival), "state": "free" (time to spare), "soon" (within `forecast.road_warn_min` of leaving), "now" (leave now: the
## margin is being used), "late" (they cannot be home before the dusk: they will be out tonight), "big" (tonight is a Big Night),
## "text"}. A party on the road home is "free" or "late": nothing can be done from there but the road. `{"on": false}` and the
## neutral numbers when there is no such trip or no avatar.
func road_status() -> Dictionary:
	var off := {"on": false, "dusk": 0.0, "road_min": 0.0, "leave_by": 0.0, "left_min": 0.0, "state": "free", "big": false, "text": ""}
	if not radio.avatar_mode():
		return off
	var party := _played_party()
	if party.is_empty():
		return off
	var road: float = sim.scavenge.road_minutes(String(party.site), String(party.get("vehicle", "")))
	var margin := NightData.num("forecast.road_margin_min", 30.0)
	var warn := NightData.num("forecast.road_warn_min", 60.0)
	var dusk := _dusk_clock()
	var in_place: bool = String(party.state) == String(sim.scavenge.IN_PLACE)
	var arrival: float = float(sim.clock_min) + road if in_place else float(party.return_at)
	var left := dusk - margin - arrival
	var state := "free"
	if in_place:
		if String(sim.phase) != "day" or left < -margin:
			state = "late"
		elif left <= 0.0:
			state = "now"
		elif left <= warn:
			state = "soon"
	elif left < -margin:
		state = "late"
	var big := _tonight_big()
	var out := {"on": true, "dusk": dusk, "road_min": road, "leave_by": dusk - margin - road, "left_min": left, "state": state, "big": big, "text": ""}
	out["text"] = _road_text(out, in_place, arrival)
	return out


func _road_text(st: Dictionary, in_place: bool, arrival: float) -> String:
	var with_it := ", and a Big Night with it" if bool(st.big) else ""
	if String(st.state) == "late":
		return "You will be out tonight%s" % ((": the base holds the Big Night alone") if bool(st.big) else "")
	if not in_place:
		return "On the road home: back by %s" % clock_text(hour_of(arrival))
	return "Dusk in %s%s: leave by %s" % [duration_text(float(st.dusk) - float(sim.clock_min)), with_it, clock_text(hour_of(float(st.leave_by)))]


## The trip's news: a line at "soon", a call at "now", and when the bell has rung on a Big Night with the avatar still out, the radio
## notes that the base holds it alone. Only for a Big Night: an ordinary one is held by the community anyway.
func _watch_road() -> void:
	if leave_requested and sim.scavenge.party_in_place().is_empty():
		leave_requested = false
	var st := road_status()
	if not bool(st.on) or not bool(st.big):
		return
	var trip := int(_played_party().get("n", 0))    # (each trip of the day has its own warnings)
	var road: float = float(st.road_min)
	match String(st.state):
		"soon":
			if _once("road-soon:%d" % trip):
				radio.log_news("night_road", String(st.text), "The road home takes %s" % duration_text(road))
		"now":
			if _once("road-now:%d" % trip):
				radio.raise_call("night_road", "Time to head home: a Big Night is coming",
					"The road home takes %s and the dusk is in %s. Leave now, or the base holds the night alone." % [duration_text(road), duration_text(float(st.dusk) - float(sim.clock_min))],
					[{"id": "home", "label": "Head home now"}, {"id": "stay", "label": "Stay out, the base holds alone"}],
					"stay", NightData.num("forecast.road_margin_min", 30.0), {"day": int(sim.day)})
	if String(st.state) == "late" and String(sim.phase) != "day" and _once("stayed:%d" % trip):
		radio.log_news("night_road", "You stayed out", "The base holds the night alone.")


# ----------------------------------------------------------------------------- save --

func save() -> Dictionary:
	var keep := {}
	for k in called:
		if int(called[k]) >= int(sim.day) - 1:
			keep[String(k)] = int(called[k])
	return {
		"called": keep,
		"seen": seen.duplicate(),
		"breaches": breaches.duplicate(),
		"notice_day": notice_day,
		"focus": focus.duplicate(true),
	}


## Restores what `save` wrote; what is not sound is left out (a save from before round 19 has none of it).
func load_state(d: Dictionary) -> void:
	reset()
	var c = d.get("called", {})
	if c is Dictionary:
		for k in c:
			if typeof(k) == TYPE_STRING and _number(c[k]):
				called[String(k)] = int(c[k])
	for field in ["seen", "breaches"]:
		var m = d.get(field, {})
		if m is Dictionary:
			for k in m:
				if (typeof(k) == TYPE_INT or (typeof(k) == TYPE_STRING and String(k).is_valid_int())) and _number(m[k]):
					(seen if field == "seen" else breaches)[int(k)] = int(m[k])
	notice_day = int(d.notice_day) if _number(d.get("notice_day")) else 0
	var f = d.get("focus", {})
	if f is Dictionary and _number(f.get("seg")) and _number(f.get("until")):
		var who: Array = []
		var raw = f.get("who", [])
		if raw is Array:
			for id in raw:
				if typeof(id) == TYPE_STRING:
					who.append(String(id))
		focus = {"seg": int(f.seg), "until": float(f.until), "who": who}


static func _number(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))
