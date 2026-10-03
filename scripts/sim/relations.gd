## Relations (round 20, slice 4): who is close to whom. One number for each pair of people, the AFFINITY, from -100 to 100 and the
## same both ways (deliberately: one number a pair). The roster's bonds (`sim.bonds.list`: Dez and Hector, Ruth and Marcus...) start
## at an ANCHOR value and never drift under a floor; every other pair starts at nothing and moves with what people do together:
## working at one station, standing still side by side, holding neighbouring posts at night, sharing a meal, coming home from a trip,
## being patched up (an event), going hungry together (it frays tempers); and it fades by a point a day. Temperaments
## (`assets/data/chemistry.json`) scale the warming or add a friction or a warmth to the pairs that meet.
##
## KINDS. A pair of 35 or more is FRIENDS (until it falls under 20), 85 or more for five days as friends is a COUPLE (until it falls under
## 60), -35 or less is RIVALS (until it rises over -20): hysteresis, so that a pair does not flicker. Nobody has more than three
## friends, one partner or two rivals (the strongest keep the kind); the player's own pairs are no part of that count. A kind that
## begins is News in the radio's log (at most two lines a day; a line that has to wait is told the next day).
##
## THE PLAYER'S PAIRS never move (trust in the player is the player's own number, `Person.trust`); what is stored stays.
##
## WHAT IT FEEDS (the hooks of other modules call the functions below; none of them does anything when the module is not `active()`):
## `bonds.of` and `bonds.bonded` (the roster plus the friends made in play: morale's near friend, the aim bonus, grief), morale (a rival
## near is on edge, a partner's loss is felt harder), the radio (a friend in the squad warms a request, a rival cools it; a friend who
## lies hurt and alone keeps someone home, except under the alarm; an enemy in the squad refuses; the echo of a push to a friend's friends), the jobs' fit, the player's
## succession (the one the community stands by), and the voice: the one people turn to, whose opinion the radio's calls may show.
##
## WHEN IT RUNS. Only in an avatar game of the settlement start (`active()`); never on Orientation Day or in the classic six start. The
## look is a slow one (`TICK_S` rules seconds, 30 game minutes). Nothing here uses `sim.rng`: every choice is a pure function of the
## state, ties broken by id, so a saved game replays bit for bit.
extends RefCounted

const Supplies := preload("res://scripts/sim/supplies.gd")

const CHEMISTRY_PATH := "res://assets/data/chemistry.json"

## Rules seconds between two looks (30 game minutes).
const TICK_S := 10.0

## The kinds: where they begin and where they end, and how many of each a person may have.
const FRIEND_AT := 35.0
const FRIEND_END := 20.0
const PARTNER_AT := 85.0
const PARTNER_END := 60.0
const PARTNER_DAYS := 5
const PARTNER_REST_DAYS := 10
const RIVAL_AT := -35.0
const RIVAL_END := -20.0
const ENEMY_AT := -65.0
const MAX_FRIENDS := 3
const MAX_PARTNERS := 1
const MAX_RIVALS := 2
## The kinds a pair can have.
const KINDS := ["friend", "partner", "rival"]

## A roster bond (map.json `bonds`) starts at the anchor of its kind and never drifts under the floor; only an event can break it.
const ANCHOR := {"friend": 55.0, "family": 60.0, "mentor": 50.0}
const ANCHOR_FLOOR := 40.0

## What moves a pair (per slow look, unless it says otherwise). A gain is multiplied by (1 - |value| / 120).
const STATION_GAIN := 0.25
const NEAR_GAIN := 0.15
const POST_GAIN := 0.2
const MEAL_GAIN := 0.8
const DECAY_PER_DAY := 1.0
## Events: a trip home together, with someone hurt (on top), a patient looked after, one who was down (on top), and going
## hungry or thirsty together (per look).
const TRIP_GAIN := 2.5
const TRIP_HURT_GAIN := 4.0
const RESCUE_GAIN := 6.0
const RESCUE_DOWNED_GAIN := 10.0
const SCARCE_LOSS := -0.5
## "Together": within this many tiles (and, for the shared place, both still). Neighbouring night posts: within this many.
const TOGETHER_TILES := 2.6
const POST_NEIGHBOUR_TILES := 5.2
## A look that comes more than this many game hours after the last (the clock was set by hand) crosses no meal.
const MEAL_SPAN_H := 3.0

## What friends and rivals do to the others (company_pull, rival_near, fit_adjust, the echo, succession).
const FRIEND_PULL := 6.0
const RIVAL_PUSH := -6.0
const ECHO_SHARE := 0.25
const ECHO_MIN := 3.0
const ECHO_GAP_MIN := 60.0
const RIVAL_NEAR := -3.0
const RIVAL_TILES := 4.0
const SUCCESSION_SHARE := 0.25
const GRIEF_PARTNER := 1.3
const FIT_RIVAL := -1.5
const FIT_FRIEND := 0.5
const FIT_FRIEND_MAX := 1.0

## The voice: the best standing (at least VOICE_MIN) among the living at the base, who changes only when beaten by VOICE_SWITCH.
const VOICE_MIN := 40.0
const VOICE_SWITCH := 8.0
## The community's trust in the leader under which nobody brings ideas (initiative.gd reads this).
const COMMUNITY_MIN := 35.0
const NEWS_PER_DAY := 2

## The words for a pair (`word`): the number each begins at.
const WARY_AT := -12.0
const FRIENDLY_AT := 12.0
const CLOSE_AT := 65.0

const MAX_WHY := 80
## The pairs of the last one lost are kept this many days (the farewell asks who they were close to), then forgotten like the rest.
const LOSS_KEEP_DAYS := 2
## The verbs of the radio a friend in the squad warms.
const PULL_VERBS := ["come", "cover", "search"]
const GO_WHATS := ["come", "cover", "search", "go"]

var sim
## Orientation Day, and a test of something else, switch the whole module off.
var enabled := true
## How many slow looks have been made (tests and the probe read it).
var looks := 0
## "a|b" (the ids sorted) -> {"a", "b", "v" (the affinity), "kind" ("", "friend", "partner" or "rival"), "since" (the day the
## kind began), "why" (what last moved it), "day" (when it last moved), "anchor" (a roster bond that still stands),
## "told" (whether the kind's News line has been said)}.
var pairs := {}
## id -> {other id: the pair's key}: the pairs of a person, kept on every write (the panels ask about everybody at 10 Hz).
var _adj := {}
var _tick := 0.0
## The day the decay last ran for (0: not yet seen), and the hour of the last look (-1: none), for the meal.
var _decay_day := 0
var _hour_seen := -1.0
var _news_day := 0
var _news_n := 0
## Pair keys whose kind is not yet in the News.
var _untold := {}
var _voice_id := ""
var _voice_told := ""
## "a>b" -> sim.clock_min of the last echo of a push on a to b.
var _echo_at := {}
var _echoing := false
## The last loss: {"id", "name", "day", "how"}, or {}.
var _loss := {}
## Person id -> the first day they may take a new partner.
var _rest_until := {}
## While a save is read: the id of the player it names (the avatar module is loaded after this one).
var _load_player := ""
## From chemistry.json: trait id -> the multiplier of a gain, and the per-look terms [{"a", "b", "per_look", "kind"}].
var _warm := {}
var _terms: Array = []
## The multiplier of each person for this look (cleared by each).
var _warm_cache := {}


func setup(s) -> void:
	sim = s
	_load_chemistry()
	_reset()


func start() -> void:
	_reset()
	_seed_roster("")


## Someone joined the crew (a recruit at the gate): the roster's bonds that now have both their people count.
func person_added(p) -> void:
	_seed_roster(_id(p))


func _reset() -> void:
	pairs = {}
	_adj = {}
	_tick = 0.0
	_decay_day = 0
	_hour_seen = -1.0
	_news_day = 0
	_news_n = 0
	_untold = {}
	_voice_id = ""
	_voice_told = ""
	_echo_at = {}
	_echoing = false
	_loss = {}
	_rest_until = {}
	_load_player = ""
	_warm_cache = {}
	looks = 0


func _load_chemistry() -> void:
	_warm = {}
	_terms = []
	if not FileAccess.file_exists(CHEMISTRY_PATH):
		push_error("Could not find %s" % CHEMISTRY_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CHEMISTRY_PATH))
	if not parsed is Dictionary:
		push_error("Could not read the chemistry from %s" % CHEMISTRY_PATH)
		return
	var warm = parsed.get("warm", {})
	if warm is Dictionary:
		for k in warm:
			if _number(warm[k]):
				_warm[String(k)] = clampf(float(warm[k]), 0.25, 2.0)
	for list_name in ["friction", "warmth"]:
		var list = parsed.get(list_name, [])
		if not list is Array:
			continue
		for e in list:
			if e is Dictionary and typeof(e.get("a")) == TYPE_STRING and typeof(e.get("b")) == TYPE_STRING and _number(e.get("per_look")):
				_terms.append({"a": String(e.a), "b": String(e.b), "per_look": clampf(float(e.per_look), -2.0, 2.0), "kind": list_name})


## Whether the rules of this module run: an avatar game of the settlement start (a small start), not Orientation Day.
func active() -> bool:
	if not enabled or sim == null or String(sim.player_id) == "":
		return false
	var rec = sim.recruits
	return rec != null and bool(rec.small)


# ------------------------------------------------------------------- the people --

func _person(id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


static func _alive(p) -> bool:
	return p != null and not p.dead and not p.turned


## The id of a person (the object), or the id itself.
static func _id(x) -> String:
	if x == null:
		return ""
	if typeof(x) == TYPE_STRING or typeof(x) == TYPE_STRING_NAME:
		return String(x)
	return String(x.id)


func _is_player(id: String) -> bool:
	return id != "" and (id == String(sim.player_id) or id == _load_player)


static func _key_of(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func _number(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


func _first(id: String) -> String:
	var p = _person(id)
	return String(p.first) if p != null else id


func _pair_of(a, b) -> Dictionary:
	var ia := _id(a)
	var ib := _id(b)
	if ia == "" or ib == "" or ia == ib:
		return {}
	return pairs.get(_key_of(ia, ib), {})


## The ids that have a pair with this one, sorted (an order that does not depend on the order things were written in).
func _others(id: String) -> Array:
	var out: Array = (_adj.get(id, {}) as Dictionary).keys()
	out.sort()
	return out


## The kind of the roster's bond between two ids ("friend", "family", "mentor"), or "".
func _roster_kind(a: String, b: String) -> String:
	for e in sim.bonds.list:
		if (String(e.a) == a and String(e.b) == b) or (String(e.a) == b and String(e.b) == a):
			return String(e.kind)
	return ""


func _cap(kind: String) -> int:
	match kind:
		"friend":
			return MAX_FRIENDS
		"partner":
			return MAX_PARTNERS
		"rival":
			return MAX_RIVALS
	return 0


# ---------------------------------------------------------------------- reading --

## The affinity of a pair (people or ids): 0.0 with no record (and while the module is not active).
func affinity(a, b) -> float:
	if not active():
		return 0.0
	var pr := _pair_of(a, b)
	return float(pr.v) if not pr.is_empty() else 0.0


## "", "friend", "partner" or "rival".
func kind(a, b) -> String:
	if not active():
		return ""
	var pr := _pair_of(a, b)
	return String(pr.kind) if not pr.is_empty() else ""


## A word for how two stand: enemies, at odds, wary, "" (between), friendly, friends, close, partners.
func word(a, b) -> String:
	if not active():
		return ""
	var pr := _pair_of(a, b)
	if pr.is_empty():
		return ""
	return _word_of(pr)


func _word_of(pr: Dictionary) -> String:
	if String(pr.kind) == "partner":
		return "partners"
	var v := float(pr.v)
	if v <= ENEMY_AT:
		return "enemies"
	if v <= RIVAL_AT:
		return "at odds"
	if v <= WARY_AT:
		return "wary"
	if v >= CLOSE_AT:
		return "close"
	if v >= FRIEND_AT:
		return "friends"
	if v >= FRIENDLY_AT:
		return "friendly"
	return ""


## The pairs of `p` that hold one of `kinds`, as [{"who": Person, "pair": Dictionary}]: the strongest first (the most hostile first for
## rivals), ties by id. Only the living, and not the player unless `with_player`.
func _held(p, kinds: Array, with_player: bool = false) -> Array:
	var out: Array = []
	var pid := _id(p)
	for oid in _others(pid):
		if not with_player and _is_player(String(oid)):
			continue
		var pr: Dictionary = pairs[_adj[pid][oid]]
		if not kinds.has(String(pr.kind)):
			continue
		var q = _person(String(oid))
		if not _alive(q):
			continue
		out.append({"who": q, "pair": pr})
	out.sort_custom(func(x, y):
		var sx := absf(float(x.pair.v))
		var sy := absf(float(y.pair.v))
		if sx != sy:
			return sx > sy
		return String(x.who.id) < String(y.who.id))
	return out


func _people_of(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append(e.who)
	return out


## The friends of a person (not the partner), alive at the base or away, the strongest first.
func friends_of(p) -> Array:
	if p == null or not active():
		return []
	return _people_of(_held(p, ["friend"]))


func rivals_of(p) -> Array:
	if p == null or not active():
		return []
	return _people_of(_held(p, ["rival"]))


## The partner (a Person), or null.
func partner_of(p):
	if p == null or not active():
		return null
	var list := _held(p, ["partner"])
	return list[0].who if not list.is_empty() else null


## The friends and the partner who are not already a pair of the roster's bonds, for `bonds.of`: [{"who", "kind" ("friend"), "role"
## ("friend" or "partner")}]. It never calls `bonds.of` (which calls this).
func circle(p) -> Array:
	var out: Array = []
	if p == null or not active():
		return out
	var pid := _id(p)
	for e in _held(p, ["friend", "partner"]):
		if _roster_kind(pid, String(e.who.id)) != "":
			continue
		out.append({"who": e.who, "kind": "friend", "role": "partner" if String(e.pair.kind) == "partner" else "friend"})
	return out


## Whether two are a pair of friends or a couple (for `bonds.bonded`).
func is_close(p, q) -> bool:
	if p == null or q == null or not active():
		return false
	var pr := _pair_of(p, q)
	return not pr.is_empty() and (String(pr.kind) == "friend" or String(pr.kind) == "partner")


## What the views show of a person: {"friends": [{"id", "first", "kind" (the roster's word for a roster bond: friend, family or
## mentor), "word", "value", "since"}], "rivals": [...], "partner": {} or one, "lines": ["Close to Ana, Marcus (family)", "At odds with Walt"]}.
## Empty while the module is not active.
func describe(p) -> Dictionary:
	if p == null or not active():
		return {}
	var pid := _id(p)
	var friends: Array = []
	for e in _held(p, ["friend"], true):
		friends.append(_entry(pid, e))
	var rivals: Array = []
	for e in _held(p, ["rival"], true):
		rivals.append(_entry(pid, e))
	var partner := {}
	var couple := _held(p, ["partner"], true)
	if not couple.is_empty():
		partner = _entry(pid, couple[0])
	var lines: Array = []
	if not partner.is_empty():
		lines.append("Together with %s" % String(partner.first))
	if not friends.is_empty():
		var names: Array = []
		for f in friends:
			var tag := " (%s)" % String(f.kind) if String(f.kind) == "family" or String(f.kind) == "mentor" else ""
			names.append(String(f.first) + tag)
		lines.append("Close to %s" % ", ".join(names))
	if not rivals.is_empty():
		var names: Array = []
		for f in rivals:
			names.append(String(f.first))
		lines.append("At odds with %s" % ", ".join(names))
	return {"friends": friends, "rivals": rivals, "partner": partner, "lines": lines}


func _entry(pid: String, e: Dictionary) -> Dictionary:
	var other = e.who
	var rk := _roster_kind(pid, String(other.id))
	var kind_name := rk if rk != "" else "friend"
	if String(e.pair.kind) == "rival":
		kind_name = "rival"
	return {"id": String(other.id), "first": String(other.first), "kind": kind_name, "word": _word_of(e.pair), "value": float(e.pair.v), "since": int(e.pair.since)}


## The community's standing of a person, 0 to 100: twice their Leading, 12 for each friend (at most three), 10 for a partner, 4 for each
## idea of theirs the player took up (at most five), 0.3 of the sum of their good feelings, less 8 for each rival. The player has none
## of the community's web: the pairs with the player are left out.
func standing(p) -> float:
	if p == null or not active():
		return 0.0
	var pid := _id(p)
	var friends := 0
	var partnered := false
	var rivals := 0
	var warmth := 0.0
	for oid in _others(pid):
		if _is_player(String(oid)):
			continue
		var pr: Dictionary = pairs[_adj[pid][oid]]
		if not _alive(_person(String(oid))):
			continue
		match String(pr.kind):
			"friend":
				friends += 1
			"partner":
				partnered = true
			"rival":
				rivals += 1
		if float(pr.v) > 0.0:
			warmth += float(pr.v)
	var s := 2.0 * float(p.skills.get("Leading", 0))
	s += 12.0 * float(mini(MAX_FRIENDS, friends))
	if partnered:
		s += 10.0
	s += 4.0 * float(mini(5, _taken(p)))
	s += 0.3 * warmth
	s -= 8.0 * float(rivals)
	return clampf(s, 0.0, 100.0)


## How many of this person's ideas the player took up (the initiative module, when there is one).
func _taken(p) -> int:
	var ini = sim.get("initiative")
	if ini != null and ini.has_method("taken_of"):
		return int(ini.taken_of(p))
	return 0


## The person the others turn to: a Person or null. Updated by each look.
func voice():
	if _voice_id == "" or not active():
		return null
	var p = _person(_voice_id)
	if not _alive(p) or _is_player(_voice_id):
		return null
	return p


## The mean trust in the player of the living who are not the player: what keeps the yard talking (55 at the start).
func community_trust() -> float:
	var sum := 0.0
	var n := 0
	for p in sim.people:
		if not _alive(p) or _is_player(String(p.id)):
			continue
		sum += float(p.trust)
		n += 1
	return sum / float(n) if n > 0 else 55.0


## The last loss, {"id", "name", "day", "how"}, or {} (for the farewell idea).
func recent_loss() -> Dictionary:
	if not active():
		return {}
	return _loss.duplicate()


# --------------------------------------------------------------------- the hooks --

## What a friend or a rival in the squad does to how a person answers a request: +FRIEND_PULL for come, cover and search when a friend or
## the partner of `contact` already follows or covers the leader (or has been agreed to), RIVAL_PUSH for a rival; 0.0 otherwise.
## `radio.willingness` adds it to the trust it reads (it is never stored).
func company_pull(contact, verb: String) -> float:
	if contact == null or not PULL_VERBS.has(verb) or not active():
		return 0.0
	var squad := _squad_ids([])
	if squad.is_empty():
		return 0.0
	var cid := _id(contact)
	var friend := false
	var rival := false
	for oid in _others(cid):
		if not squad.has(oid) or _is_player(String(oid)):
			continue
		var pr: Dictionary = pairs[_adj[cid][oid]]
		if String(pr.kind) == "friend" or String(pr.kind) == "partner":
			friend = true
		elif String(pr.kind) == "rival" or float(pr.v) <= ENEMY_AT:
			rival = true
	var pull := 0.0
	if friend:
		pull += FRIEND_PULL
	if rival:
		pull += RIVAL_PUSH
	return pull


## A soft reason, in the radio's words ("staying with Dez", "won't go with Walt", "won't work beside Walt"), or "" when there is none.
## `what`: come, cover, search, go (a person is asked to go somewhere with others: `with_ids` are who else is going) or work (at
## `station_id`). The squad is who follows or covers the leader now, or has agreed to. Insisting overrides it at the usual cost (once for
## a request that asks several: `radio.request_errand`). Under the call to arms (`radio.alarm_on`) there is NO reason of company: a
## friend does not stay behind, and an old quarrel waits.
func company_reason(contact, what: String, station_id: String = "", with_ids: Array = []) -> String:
	if contact == null or not active() or sim.radio.alarm_on:
		return ""
	var cid := _id(contact)
	if what == "work":
		if station_id == "":
			return ""
		for e in _held(contact, ["friend", "partner", "rival"]):
			if float(e.pair.v) > ENEMY_AT:
				continue
			if String(sim.jobs.job_of(e.who)) == station_id:
				return "won't work beside %s" % String(e.who.first)
		return ""
	if not GO_WHATS.has(what):
		return ""
	# a friend who lies hurt with nobody beside them
	for e in _held(contact, ["friend", "partner"]):
		if e.who.away == null and _needs_company(e.who, contact):
			return "staying with %s" % String(e.who.first)
	# an enemy in the squad
	var squad := _squad_ids(with_ids)
	if not squad.is_empty():
		for oid in _others(cid):
			if not squad.has(oid) or _is_player(String(oid)):
				continue
			var pr: Dictionary = pairs[_adj[cid][oid]]
			if float(pr.v) <= ENEMY_AT and _alive(_person(String(oid))):
				return "won't go with %s" % _first(String(oid))
	return ""


## The ids of the people who follow or cover the leader, have been agreed to (the radio's pending requests), or are named in `extra`.
func _squad_ids(extra: Array) -> Dictionary:
	var ids := {}
	for q in sim.people:
		if _alive(q) and q.away == null and not q.player and (String(q.stance) == "follow" or String(q.stance) == "cover"):
			ids[String(q.id)] = true
	for r in sim.radio.pending:
		if String(r.verb) == "come" or String(r.verb) == "cover":
			ids[String(r.who)] = true
	for x in extra:
		var id := _id(x)
		if id != "":
			ids[id] = true
	return ids


## Whether `q` (a friend of `contact`, at the base) lies down or bleeds with nobody looking after them: not in a bed (the infirmary's
## care, or their own rest, is care enough), nobody treating them, and nobody else up within TOGETHER_TILES. Somebody who is looked
## after does not keep their friends from the work; the one who is alone does.
func _needs_company(q, contact) -> bool:
	if not (q.downed or float(q.bleeding) > 0.0) or q.resting_bed != null:
		return false
	for j in sim.medical.jobs:
		if j.patient == q:
			return false
	var at := Vector2(q.x, q.y)
	for r in sim.people:
		if r == q or r == contact or not _alive(r) or r.away != null or r.downed:
			continue
		if Vector2(r.x, r.y).distance_to(at) <= TOGETHER_TILES:
			return false
	return true


## The nearest rival of `p` (alive, up, on the map) within RIVAL_TILES, or null (morale: "On edge near Walt").
func rival_near(p):
	if p == null or not active():
		return null
	var best = null
	var best_d := RIVAL_TILES
	for e in _held(p, ["rival"]):
		var q = e.who
		if q.downed or q.away != null:
			continue
		var d := Vector2(q.x - p.x, q.y - p.y).length()
		if d <= RIVAL_TILES and (best == null or d < best_d):
			best = q
			best_d = d
	return best


## How much harder `p` is hit by the loss of `lost`: GRIEF_PARTNER for a partner, else 1.0.
func grief_mult(p, lost) -> float:
	if p == null or lost == null or not active():
		return 1.0
	var pr := _pair_of(p, lost)
	if not pr.is_empty() and String(pr.kind) == "partner":
		return GRIEF_PARTNER
	return 1.0


## For `jobs._fit`: FIT_RIVAL when a rival of `p` crews that station, FIT_FRIEND for each friend there (at most FIT_FRIEND_MAX).
func fit_adjust(p, station_id: String) -> float:
	if p == null or station_id == "" or not active():
		return 0.0
	var friends := 0
	var rival := false
	for e in _held(p, ["friend", "partner", "rival"]):
		if String(sim.jobs.job_of(e.who)) != station_id:
			continue
		if String(e.pair.kind) == "rival":
			rival = true
		else:
			friends += 1
	var out := minf(FIT_FRIEND_MAX, FIT_FRIEND * float(friends))
	if rival:
		out += FIT_RIVAL
	return out


## What the community's standing adds to trust when the next in line is chosen (avatar.gd).
func succession_bonus(p) -> float:
	if p == null or not active():
		return 0.0
	return SUCCESSION_SHARE * standing(p)


## `radio.add_trust` calls this: a push or a gain of ECHO_MIN or more (either way) reaches the friends and the partner of `p` at
## ECHO_SHARE, once an hour for a pair, with the reason "How you treated Dez". The echo itself never echoes.
func on_trust_moved(p, delta: float) -> void:
	if p == null or _echoing or not active() or not is_finite(delta) or absf(delta) < ECHO_MIN:
		return
	var pid := _id(p)
	if _is_player(pid):
		return
	_echoing = true
	for e in _held(p, ["friend", "partner"]):
		var q = e.who
		var k := "%s>%s" % [pid, String(q.id)]
		if float(sim.clock_min) - float(_echo_at.get(k, -1.0e9)) < ECHO_GAP_MIN:
			continue
		_echo_at[k] = float(sim.clock_min)
		sim.radio.add_trust(q, delta * ECHO_SHARE, "How you treated %s" % String(p.first))
	_echoing = false


## `medical._finish`: the healer looked after the patient (more if the patient was down).
func on_treated(healer, patient, _kind: String) -> void:
	if healer == null or patient == null or healer == patient or not active():
		return
	var gain := RESCUE_GAIN + (RESCUE_DOWNED_GAIN if patient.downed else 0.0)
	add(healer, patient, gain, "%s looked after %s" % [String(healer.first), String(patient.first)])


## `scavenge._come_back`: every pair that came home together warms (more with someone hurt).
func on_trip(came: Array, _lost: Array, party: Dictionary) -> void:
	if came.size() < 2 or not active():
		return
	var hurt := false
	var result = party.get("result", {})
	if result is Dictionary:
		var marks = result.get("hurt", {})
		if marks is Dictionary:
			for p in came:
				if String(marks.get(String(p.id), "")) != "":
					hurt = true
	var gain := TRIP_GAIN + (TRIP_HURT_GAIN if hurt else 0.0)
	for i in came.size():
		for j in range(i + 1, came.size()):
			add(came[i], came[j], gain, "Came home together")


## `morale.on_lost`: a partner's loss starts the survivor's rest from new partners, and the loss is remembered for the farewell. The
## dead one's pairs stay until the next look (the grief of the others is still being worked out) and are dropped then.
func on_lost(p, how: String) -> void:
	if p == null or not active():
		return
	for e in _held(p, ["partner"], true):
		_rest_until[String(e.who.id)] = int(sim.day) + PARTNER_REST_DAYS
	_loss = {"id": _id(p), "name": String(p.first), "day": int(sim.day), "how": how}


## `morale.on_downed`: nothing to write (who stays with whom is read from the state when it is asked: `company_reason`).
func on_downed(_p) -> void:
	pass


# ------------------------------------------------------------------------ writing --

## THE writer: moves the pair by `delta` (clamped to -100..100), remembers `why`, works out the kinds again (with their caps and their
## hysteresis) and tells the News when a kind begins. Nothing happens while the module is not active, for a pair with oneself or the
## player, or for someone who is gone.
func add(a, b, delta: float, why: String) -> void:
	if not active() or not is_finite(delta) or delta == 0.0:
		return
	var ia := _id(a)
	var ib := _id(b)
	if ia == "" or ib == "" or ia == ib or _is_player(ia) or _is_player(ib):
		return
	if not _alive(_person(ia)) or not _alive(_person(ib)):
		return
	_write(ia, ib, delta, why, true)
	_tell()


func _ensure(a: String, b: String) -> Dictionary:
	var key := _key_of(a, b)
	if pairs.has(key):
		return pairs[key]
	var lo := a if a < b else b
	var hi := b if a < b else a
	var pr := {"a": lo, "b": hi, "v": 0.0, "kind": "", "since": int(sim.day), "why": "", "day": int(sim.day), "anchor": false, "told": true}
	pairs[key] = pr
	if not _adj.has(lo):
		_adj[lo] = {}
	if not _adj.has(hi):
		_adj[hi] = {}
	_adj[lo][hi] = key
	_adj[hi][lo] = key
	return pr


func _drop(key: String) -> void:
	var pr: Dictionary = pairs.get(key, {})
	if pr.is_empty():
		return
	for side in [[pr.a, pr.b], [pr.b, pr.a]]:
		var mine: Dictionary = _adj.get(side[0], {})
		mine.erase(side[1])
		if mine.is_empty():
			_adj.erase(side[0])
	pairs.erase(key)
	_untold.erase(key)


## Moves a pair. An `event` (add) can break a roster bond under its floor; a look (the slow moves, the decay) cannot.
func _write(a: String, b: String, delta: float, why: String, event: bool) -> void:
	var pr := _ensure(a, b)
	var key := _key_of(a, b)
	var v := clampf(float(pr.v) + delta, -100.0, 100.0)
	if bool(pr.anchor) and v < ANCHOR_FLOOR:
		if event:
			pr.anchor = false
		else:
			v = ANCHOR_FLOOR
	pr.v = v
	pr.day = int(sim.day)
	if why != "":
		pr.why = why.substr(0, MAX_WHY)
	_rederive(key, false, "")


## The kind a pair holds now: the first of its candidates there is room for (or that it holds already), else none.
## `as_if` is the kind it is taken to hold for the hysteresis (a save's hint), "" for the one it holds.
func _rederive(key: String, silent: bool, as_if: String) -> void:
	var pr: Dictionary = pairs[key]
	var was := String(pr.kind)
	var cur := as_if if as_if != "" else was
	var capped := not (_is_player(String(pr.a)) or _is_player(String(pr.b)))
	var chosen := ""
	for cand in _candidates(pr, cur):
		if cand == was or not capped or _room_for(pr, key, String(cand)):
			chosen = String(cand)
			break
	if chosen == was:
		return
	var redo: Array = []
	if chosen != "" and capped:
		redo = _make_room(pr, key, chosen)
	_set_kind(pr, chosen, silent)
	for k in redo:
		_rederive(String(k), true, "")


## The kinds a pair qualifies for, best first, given the kind it holds (the hysteresis).
func _candidates(pr: Dictionary, cur: String) -> Array:
	var v := float(pr.v)
	var out: Array = []
	if cur == "partner" and v >= PARTNER_END:
		out.append("partner")
	elif cur == "friend" and v >= PARTNER_AT and _can_partner(pr):
		out.append("partner")
	if v >= FRIEND_AT or ((cur == "friend" or cur == "partner") and v >= FRIEND_END):
		out.append("friend")
	if out.is_empty() and (v <= RIVAL_AT or (cur == "rival" and v <= RIVAL_END)):
		out.append("rival")
	return out


## A pair that has been friends for PARTNER_DAYS may be a couple, unless it is family or a mentor and a student, or one of the two is
## still in mourning for a partner.
func _can_partner(pr: Dictionary) -> bool:
	var rk := _roster_kind(String(pr.a), String(pr.b))
	if rk == "family" or rk == "mentor":
		return false
	if int(sim.day) - int(pr.since) < PARTNER_DAYS:
		return false
	return int(sim.day) >= int(_rest_until.get(String(pr.a), 0)) and int(sim.day) >= int(_rest_until.get(String(pr.b), 0))


## Whether both of the pair have room for it as `kind`: a free slot, or a holder weaker than this pair.
func _room_for(pr: Dictionary, key: String, kind: String) -> bool:
	var strength := absf(float(pr.v))
	return _slot_open(String(pr.a), kind, key, strength) and _slot_open(String(pr.b), kind, key, strength)


func _slot_open(id: String, kind: String, key: String, strength: float) -> bool:
	var n := 0
	var weakest := INF
	var mine: Dictionary = _adj.get(id, {})
	for oid in mine:
		var k: String = mine[oid]
		if k == key or _is_player(String(oid)) or not _alive(_person(String(oid))):
			continue
		var q: Dictionary = pairs[k]
		if String(q.kind) != kind:
			continue
		n += 1
		weakest = minf(weakest, absf(float(q.v)))
	return n < _cap(kind) or strength > weakest


## Takes the slot of the weakest holder at each end that is full. Returns the keys of the couples put out, which fall back to friends.
func _make_room(pr: Dictionary, key: String, kind: String) -> Array:
	var redo: Array = []
	for id in [String(pr.a), String(pr.b)]:
		var held: Array = []
		var mine: Dictionary = _adj.get(id, {})
		for oid in mine:
			var k: String = mine[oid]
			if k == key or _is_player(String(oid)) or not _alive(_person(String(oid))):
				continue
			if String(pairs[k].kind) == kind:
				held.append(k)
		if held.size() < _cap(kind):
			continue
		held.sort_custom(func(x, y):
			var sx := absf(float(pairs[x].v))
			var sy := absf(float(pairs[y].v))
			if sx != sy:
				return sx < sy
			return String(x) > String(y))
		_set_kind(pairs[held[0]], "", true)
		if kind == "partner":
			redo.append(held[0])
	return redo


func _set_kind(pr: Dictionary, kind: String, silent: bool) -> void:
	var was := String(pr.kind)
	if was == kind:
		return
	pr.kind = kind
	pr.since = int(sim.day)
	var key := _key_of(String(pr.a), String(pr.b))
	if kind == "" or silent or (kind == "friend" and was == "partner"):
		pr.told = true
		_untold.erase(key)
	else:
		pr.told = false
		_untold[key] = true


# ------------------------------------------------------------------------- news --

## Says each kind that has begun and has not been told, in the order they began, as long as the day's two lines are not spent.
func _tell() -> void:
	if _untold.is_empty():
		return
	var keys: Array = _untold.keys()
	keys.sort_custom(func(x, y):
		var sx := int(pairs[x].since) if pairs.has(x) else 0
		var sy := int(pairs[y].since) if pairs.has(y) else 0
		if sx != sy:
			return sx < sy
		return String(x) < String(y))
	for key in keys:
		var pr: Dictionary = pairs.get(key, {})
		if pr.is_empty() or bool(pr.told) or String(pr.kind) == "":
			_untold.erase(key)
			continue
		var names := _names_of(pr)
		var text := ""
		var news_kind := "bond"
		match String(pr.kind):
			"friend":
				text = "%s are close now" % names
			"partner":
				text = "%s are together now" % names
			"rival":
				text = "%s are at odds" % names
				news_kind = "rift"
		if not _news(news_kind, text, String(pr.why)):
			return
		pr.told = true
		_untold.erase(key)


## "Dez and Ana": the two first names, in the order of the crew list.
func _names_of(pr: Dictionary) -> String:
	var order: Array = []
	for p in sim.people:
		if String(p.id) == String(pr.a) or String(p.id) == String(pr.b):
			order.append(String(p.first))
	if order.size() < 2:
		return "%s and %s" % [_first(String(pr.a)), _first(String(pr.b))]
	return "%s and %s" % [order[0], order[1]]


## One line for the radio's News, as long as the day has one left. Whether it was said.
func _news(news_kind: String, text: String, sub: String) -> bool:
	if _news_day != int(sim.day):
		_news_day = int(sim.day)
		_news_n = 0
	if _news_n >= NEWS_PER_DAY:
		return false
	_news_n += 1
	sim.radio.log_news(news_kind, text, sub)
	return true


# ----------------------------------------------------------------------- the roster --

## Gives the roster's bonds (`sim.bonds.list`) their pairs, at their anchors, for the people who are here (`only_id`: just the bonds of
## that one, a late caller who has just come; "": all, at the start of a run). A pair that exists is left as it is.
func _seed_roster(only_id: String) -> void:
	for e in sim.bonds.list:
		var a := String(e.a)
		var b := String(e.b)
		if only_id != "" and a != only_id and b != only_id:
			continue
		if not _alive(_person(a)) or not _alive(_person(b)) or pairs.has(_key_of(a, b)):
			continue
		var pr := _ensure(a, b)
		pr.v = float(ANCHOR.get(String(e.kind), ANCHOR.friend))
		pr.anchor = true
		pr.why = "Old ties"
		_rederive(_key_of(a, b), true, "")


# --------------------------------------------------------------------- the slow look --

## Every step: every TICK_S seconds of rules time, a look.
func update(dt: float) -> void:
	if not active():
		return
	_tick += dt
	if _tick < TICK_S:
		return
	_tick = fmod(_tick, TICK_S)
	look()


## One slow look at once (the update calls it; tests and the probe too): the people who are up and at the base warm or fray, and the
## day's decay, the voice and the News follow.
func look() -> void:
	if not active():
		return
	looks += 1
	_warm_cache = {}
	_prune()
	var day := int(sim.day)
	var decay_now := false
	if _decay_day == 0:
		_decay_day = day
	elif day != _decay_day:
		_decay_day = day
		decay_now = true
	var crowd := _crowd()
	var acc := {}
	_work_together(acc)
	_stand_together(acc, crowd)
	_post_together(acc, crowd)
	var meal := _meal_crossed()
	if meal:
		_meal_together(acc, crowd)
	_fray_together(acc, crowd)
	_flush(acc)
	if decay_now:
		_decay()
		_forget_echoes()
	_voice_update()
	_tell()
	_tell_voice()


## The people who are up, on the map and not the player.
func _crowd() -> Array:
	var out: Array = []
	for p in sim.people:
		if _alive(p) and not p.downed and p.away == null and not _is_player(String(p.id)):
			out.append(p)
	return out


## Pairs of people not (or no longer) here are dropped: not in the crew list, dead, turned or sent out. The one lost last keeps theirs
## for LOSS_KEEP_DAYS (the farewell asks who they were close to; they count for nothing meanwhile).
func _prune() -> void:
	var keep := ""
	if not _loss.is_empty() and int(sim.day) - int(_loss.day) <= LOSS_KEEP_DAYS:
		keep = String(_loss.id)
	var here := {}
	for p in sim.people:
		if _alive(p) or String(p.id) == keep:
			here[String(p.id)] = true
	var keys: Array = pairs.keys()
	keys.sort()
	for key in keys:
		var pr: Dictionary = pairs[key]
		if not here.has(String(pr.a)) or not here.has(String(pr.b)):
			_drop(String(key))


## Adds to what this look gives a pair. A gain shrinks toward the ends ((1 - |value| / 120)) and grows with the warmth of the two.
func _gain(acc: Dictionary, a, b, amount: float, why: String) -> void:
	var key := _key_of(String(a.id), String(b.id))
	var e: Dictionary = acc.get(key, {})
	if e.is_empty():
		e = {"a": String(a.id), "b": String(b.id), "pa": a, "pb": b, "d": 0.0, "why": "", "top": -1.0}
		acc[key] = e
	var d := amount
	if amount > 0.0:
		var v := float(pairs[key].v) if pairs.has(key) else 0.0
		d = amount * (1.0 - absf(v) / 120.0) * _warm_of(a) * _warm_of(b)
	e.d = float(e.d) + d
	if absf(d) > float(e.top):
		e.top = absf(d)
		e.why = why


## How much more or less this person warms to others (the product of their traits' multipliers in chemistry.json).
func _warm_of(p) -> float:
	var id := String(p.id)
	if _warm_cache.has(id):
		return float(_warm_cache[id])
	var m := 1.0
	for t in _warm:
		if sim.traits.has_trait(p, String(t)):
			m *= float(_warm[t])
	_warm_cache[id] = m
	return m


func _chem_terms(a, b) -> Dictionary:
	var sum := 0.0
	var why := ""
	var top := 0.0
	for t in _terms:
		var x := String(t.a)
		var y := String(t.b)
		var hit: bool = (sim.traits.has_trait(a, x) and sim.traits.has_trait(b, y)) or (sim.traits.has_trait(a, y) and sim.traits.has_trait(b, x))
		if not hit:
			continue
		sum += float(t.per_look)
		if absf(float(t.per_look)) > top:
			top = absf(float(t.per_look))
			why = "Rub each other the wrong way" if float(t.per_look) < 0.0 else "Easy in each other's company"
	return {"d": sum, "why": why}


## People at the same station, at their seats and free to work: STATION_GAIN for each pair.
func _work_together(acc: Dictionary) -> void:
	for st in sim.jobs.stations():
		var crew: Array = []
		for p in sim.jobs.working(String(st.id)):
			if not _is_player(String(p.id)):
				crew.append(p)
		for i in crew.size():
			for j in range(i + 1, crew.size()):
				_gain(acc, crew[i], crew[j], STATION_GAIN, "Work side by side at the %s" % String(st.name).to_lower())


## People standing still within TOGETHER_TILES of each other: NEAR_GAIN.
func _stand_together(acc: Dictionary, crowd: Array) -> void:
	var reach := TOGETHER_TILES * TOGETHER_TILES
	for i in crowd.size():
		var a = crowd[i]
		if a.moving:
			continue
		for j in range(i + 1, crowd.size()):
			var b = crowd[j]
			if b.moving:
				continue
			if _dist2(a, b) <= reach:
				_gain(acc, a, b, NEAR_GAIN, "Spend the day side by side")


## At night: people whose posts are neighbours (within POST_NEIGHBOUR_TILES): POST_GAIN.
func _post_together(acc: Dictionary, crowd: Array) -> void:
	if not sim.is_night():
		return
	var spots: Array = []
	for p in crowd:
		var po: Dictionary = sim.jobs.post(String(sim.jobs.post_ids.get(String(p.id), "")))
		if not po.is_empty():
			spots.append({"p": p, "at": Vector2(po.pos)})
	var reach := POST_NEIGHBOUR_TILES
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if Vector2(spots[i].at).distance_to(spots[j].at) <= reach:
				_gain(acc, spots[i].p, spots[j].p, POST_GAIN, "Stand watch side by side")


## Whether the clock has passed a meal time since the last look.
func _meal_crossed() -> bool:
	var h := float(sim.hour)
	var last := _hour_seen
	_hour_seen = h
	if last < 0.0:
		return false
	var elapsed := fposmod(h - last, 24.0)
	if elapsed <= 0.0 or elapsed > MEAL_SPAN_H:
		return false
	for mh in Supplies.MEAL_HOURS:
		var gap := fposmod(float(mh) - last, 24.0)
		if gap > 0.0 and gap <= elapsed + 1.0e-9:
			return true
	return false


## At a meal: pairs within TOGETHER_TILES: MEAL_GAIN.
func _meal_together(acc: Dictionary, crowd: Array) -> void:
	var reach := TOGETHER_TILES * TOGETHER_TILES
	for i in crowd.size():
		for j in range(i + 1, crowd.size()):
			if _dist2(crowd[i], crowd[j]) <= reach:
				_gain(acc, crowd[i], crowd[j], MEAL_GAIN, "Share a meal")


## Hunger frays tempers: a pair together while either is hungry or thirsty: SCARCE_LOSS.
func _fray_together(acc: Dictionary, crowd: Array) -> void:
	var reach := TOGETHER_TILES * TOGETHER_TILES
	for i in crowd.size():
		for j in range(i + 1, crowd.size()):
			var a = crowd[i]
			var b = crowd[j]
			if _dist2(a, b) > reach:
				continue
			if _wanting(a) or _wanting(b):
				_gain(acc, a, b, SCARCE_LOSS, "Short tempers: hungry and thirsty")


func _wanting(p) -> bool:
	return float(p.hunger_h) >= Supplies.HUNGRY_H or float(p.thirst_h) >= Supplies.THIRSTY_H


static func _dist2(a, b) -> float:
	var dx: float = a.x - b.x
	var dy: float = a.y - b.y
	return dx * dx + dy * dy


## Writes what the look gave each pair that met, with the chemistry of the two, once.
func _flush(acc: Dictionary) -> void:
	var keys: Array = acc.keys()
	keys.sort()
	for key in keys:
		var e: Dictionary = acc[key]
		var chem := _chem_terms(e.pa, e.pb)
		var d := float(e.d) + float(chem.d)
		var why := String(e.why)
		if absf(float(chem.d)) > float(e.top):
			why = String(chem.why)
		if d != 0.0:
			_write(String(e.a), String(e.b), d, why, false)


## Once a day every pair moves a point toward nothing (a roster bond not under its floor), and a pair that has come to nothing is
## forgotten. The kinds are worked out again, in order, so that a slot that has come free goes to the strongest who was waiting.
func _decay() -> void:
	var keys: Array = pairs.keys()
	keys.sort()
	for key in keys:
		var pr: Dictionary = pairs[key]
		if _is_player(String(pr.a)) or _is_player(String(pr.b)):
			continue
		if not _alive(_person(String(pr.a))) or not _alive(_person(String(pr.b))):
			continue    # (what is kept of the one lost last is a memory: it stands still)
		var v := float(pr.v)
		var nv := v - signf(v) * minf(absf(v), DECAY_PER_DAY)
		if bool(pr.anchor):
			nv = maxf(nv, ANCHOR_FLOOR)
		pr.v = nv
		_rederive(String(key), false, "")
		if absf(nv) < 0.05 and String(pr.kind) == "" and not bool(pr.anchor):
			_drop(String(key))


func _forget_echoes() -> void:
	for k in _echo_at.keys():
		if float(sim.clock_min) - float(_echo_at[k]) >= ECHO_GAP_MIN:
			_echo_at.erase(k)


# ---------------------------------------------------------------------- the voice --

## The voice: the best standing of the living at the base (not the player), at least VOICE_MIN; the one who is it keeps it until
## someone beats them by VOICE_SWITCH.
func _voice_update() -> void:
	var best = null
	var best_s := -1.0
	for p in sim.people:
		if not _alive(p) or p.away != null or _is_player(String(p.id)):
			continue
		var s := standing(p)
		if best == null or s > best_s or (s == best_s and String(p.id) < String(best.id)):
			best = p
			best_s = s
	var cur = _person(_voice_id) if _voice_id != "" else null
	if cur != null and (not _alive(cur) or _is_player(String(cur.id))):
		cur = null
	var cur_s := standing(cur) if cur != null else -1.0
	var pick := ""
	if cur != null and cur_s >= VOICE_MIN and (best == null or best_s < cur_s + VOICE_SWITCH):
		pick = String(cur.id)
	elif best != null and best_s >= VOICE_MIN:
		pick = String(best.id)
	if pick != _voice_id:
		_voice_id = pick
		_voice_told = ""


func _tell_voice() -> void:
	if _voice_id == "" or _voice_told == _voice_id:
		return
	var p = _person(_voice_id)
	if p == null:
		return
	if _news("bond", "%s is who people turn to now" % String(p.first), ""):
		_voice_told = _voice_id


# ------------------------------------------------------------------------- save --

func save() -> Dictionary:
	var rows := {}
	for key in pairs:
		var pr: Dictionary = pairs[key]
		rows[String(key)] = {"v": float(pr.v), "kind": String(pr.kind), "since": int(pr.since), "why": String(pr.why), "day": int(pr.day), "anchor": bool(pr.anchor), "told": bool(pr.told)}
	return {
		"pairs": rows,
		"tick": _tick,
		"decay_day": _decay_day,
		"hour": _hour_seen,
		"news_day": _news_day,
		"news_n": _news_n,
		"voice": _voice_id,
		"voice_told": _voice_told,
		"echo": _echo_at.duplicate(),
		"loss": _loss.duplicate(),
		"rest": _rest_until.duplicate(),
		"player": String(sim.player_id),
	}


## Restores what `save` wrote. A save from before has none: a fresh start (the roster's bonds at their anchors). Every number is
## checked, unknown people and malformed entries are dropped, and the kinds are worked out again from the numbers (the file's word is
## only a hint for the hysteresis) with their caps, the strongest first.
func load_state(d: Dictionary) -> void:
	_reset()
	var rows = d.get("pairs")
	if not rows is Dictionary:
		_seed_roster("")
		return
	var player = d.get("player", "")
	_load_player = String(player) if typeof(player) == TYPE_STRING else ""
	var today := int(sim.day)
	var loaded: Array = []
	for key in rows:
		if typeof(key) != TYPE_STRING:
			continue
		var ids := String(key).split("|")
		if ids.size() != 2 or ids[0] == "" or ids[0] >= ids[1]:
			continue
		if _person(ids[0]) == null or _person(ids[1]) == null:
			continue
		var e = rows[key]
		if not e is Dictionary or not _number(e.get("v")):
			continue
		var pr := _ensure(ids[0], ids[1])
		pr.v = clampf(float(e.v), -100.0, 100.0)
		pr.day = clampi(int(e.get("day", today)) if _number(e.get("day")) else today, 0, today)
		pr.why = String(e.why).substr(0, MAX_WHY) if typeof(e.get("why")) == TYPE_STRING else ""
		pr.anchor = typeof(e.get("anchor")) == TYPE_BOOL and bool(e.anchor) and _roster_kind(ids[0], ids[1]) != ""
		var hint := String(e.kind) if typeof(e.get("kind")) == TYPE_STRING else ""
		loaded.append({
			"key": String(key),
			"hint": hint if KINDS.has(hint) else "",
			"since": clampi(int(e.get("since", today)) if _number(e.get("since")) else today, 0, today),
			"told": not (typeof(e.get("told")) == TYPE_BOOL and not bool(e.told)),
		})
	loaded.sort_custom(func(x, y):
		var sx := absf(float(pairs[x.key].v))
		var sy := absf(float(pairs[y.key].v))
		if sx != sy:
			return sx > sy
		return String(x.key) < String(y.key))
	for e in loaded:
		var pr: Dictionary = pairs[e.key]
		_rederive(String(e.key), true, String(e.hint))
		if String(pr.kind) == String(e.hint):
			pr.since = int(e.since)    # (also for a pair with no kind: it keeps the day it has, it does not take the day of the load)
		if String(pr.kind) != "":
			if not bool(e.told):
				pr.told = false
				_untold[String(e.key)] = true
	var tick = d.get("tick")
	_tick = clampf(float(tick), 0.0, TICK_S) if _number(tick) else 0.0
	var dd = d.get("decay_day")
	_decay_day = clampi(int(dd), 0, today) if _number(dd) else 0
	var hour = d.get("hour")
	_hour_seen = clampf(float(hour), -1.0, 24.0) if _number(hour) else -1.0
	var nd = d.get("news_day")
	_news_day = clampi(int(nd), 0, today) if _number(nd) else 0
	var nn = d.get("news_n")
	_news_n = clampi(int(nn), 0, NEWS_PER_DAY) if _number(nn) else 0
	var voice = d.get("voice")
	if typeof(voice) == TYPE_STRING and _alive(_person(String(voice))) and not _is_player(String(voice)):
		_voice_id = String(voice)
		var told = d.get("voice_told")
		_voice_told = _voice_id if typeof(told) == TYPE_STRING and String(told) == _voice_id else ""
	var echo = d.get("echo")
	if echo is Dictionary:
		for k in echo:
			if typeof(k) != TYPE_STRING or not _number(echo[k]):
				continue
			var ids := String(k).split(">")
			if ids.size() == 2 and _person(ids[0]) != null and _person(ids[1]) != null:
				_echo_at[String(k)] = float(echo[k])
	var loss = d.get("loss")
	if loss is Dictionary and typeof(loss.get("id")) == TYPE_STRING and typeof(loss.get("name")) == TYPE_STRING and _person(String(loss.id)) != null and _number(loss.get("day")):
		_loss = {"id": String(loss.id), "name": String(loss.name), "day": clampi(int(loss.day), 0, today), "how": String(loss.get("how", "")) if typeof(loss.get("how", "")) == TYPE_STRING else ""}
	var rest = d.get("rest")
	if rest is Dictionary:
		for id in rest:
			if typeof(id) == TYPE_STRING and _person(String(id)) != null and _number(rest[id]):
				_rest_until[String(id)] = clampi(int(rest[id]), 0, today + PARTNER_REST_DAYS)
	_load_player = ""
