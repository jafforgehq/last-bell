## The conditions of Orientation Day: what a step waits for before it is done (`done`), what
## a step waits for before it begins (`start`, `pause_until`) and what decides where the
## coach points (`when` on an anchor). assets/data/tutorial.json names them as
## {"cond": name, "params": {...}}; the coach (scripts/ui/coach.gd) evaluates them.
##
## Each is a Callable(sim, params, state) -> bool in the registry below. `sim` is the
## game's rules, `params` the step's own numbers and names, and `state` what the coach
## keeps for the step it is on (plain data, saved with the run):
##   "t"          real seconds since the step began
##   "pan"        tiles the view has been panned since it began
##   "zoom"       how far the view has been zoomed since it began (the size of the log
##                of each factor, added up)
##   "did"        what the player did since it began, counted: "select:person:ruth",
##                "gizmo:draft", "move", "speed:3", "save", "fields"...
##   "events"     the rules' events since it began, counted by type: "shot", "bell"... (a "radio_line" is counted as
##                "radio_line:<who>:<verb>:ok" or ":no", the answer to a request of the radio; an "assigned"
##                event that names a station, a job given, also counts as "assigned:job": one that
##                takes a job away does not)
##   "next"       the card's Got it was pressed
##   "base"       the world as the step began: {"ammo": n, "kills": n, "pos": {person id: [x, y]}, "mine": {"shots": n,
##                "kills": n} (what the player's own person had done: avatar mode), "news": the id of the newest line of the radio's log}
##   "selection"  {"kind": "person", "id": "ruth"}, {"kind": "segment", "id": 3} or {}
##   "speed"      the game's speed (0 to 3), "fields": the fields-of-fire view is on
##   "dialog"     {"open": bool, "site": the place chosen in the scavenging dialog or ""}
##   "jobs"       {"open": bool}: the Duty roster's page (key J) is open
##   "news"       {"open": bool}: the News panel (key T, avatar mode) is open
##   "wheel"      {"open": bool}: the command wheel (hold C, avatar mode) is up
## A condition may note something in `state` (a wound seen, say), but never reads the
## screen: anything it needs the coach has put in `state`, so the tests can drive it.
extends RefCounted

const NightData := preload("res://scripts/sim/night_data.gd")
const GateKit := preload("res://scripts/ui/gate_kit.gd")

## name -> Callable(sim, params, state), filled once.
static var _table := {}


static func registry() -> Dictionary:
	if _table.is_empty():
		_table = {
			"always": _always,
			"never": _never,
			"next": _next,
			"elapsed": _elapsed,
			"did": _did,
			"event": _event,
			"look_around": _look_around,
			"selected": _selected,
			"ordered": _ordered,
			"arrived": _arrived,
			"released": _released,
			"post_ordered": _post_ordered,
			"posted": _posted,
			"repair_ordered": _repair_ordered,
			"wall_mended": _wall_mended,
			"dialog_open": _dialog_open,
			"site_chosen": _site_chosen,
			"party_out": _party_out,
			"speed_pressed": _speed_pressed,
			"forecast_given": _forecast_given,
			"bell_rung": _bell_rung,
			"ammo_spent": _ammo_spent,
			"kills": _kills,
			"ammo_gained": _ammo_gained,
			"fields_on": _fields_on,
			"lure_set": _lure_set,
			"healed": _healed,
			"treat_ordered": _treat_ordered,
			"cured": _cured,
			"saved": _saved,
			"day_started": _day_started,
			"crafting": _crafting,
			"jobs_open": _jobs_open,
			"jobs_given": _jobs_given,
			"low_stores": _low_stores,
			"low_ammo": _low_ammo,
			"wounded": _wounded,
			"feverish": _feverish,
			"breached": _breached,
			"kind_alive": _kind_alive,
			"can_build": _can_build,
			"town_on": _town_on,
			"avatar_game": _avatar_game,
			"can_use": _can_use,
			"ring_night": _ring_night,
			"big_night_ahead": _big_night_ahead,
			"panel_page": _panel_page,
			"contact_picked": _contact_picked,
			"gate_dusk": _gate_dusk,
			"gate_open_day": _gate_open_day,
			"season": _season,
			"lot_open": _lot_open,
			"has_vehicle": _has_vehicle,
			"walked": _walked,
			"on_deck": _on_deck,
			"shots": _shots,
			"player_kills": _player_kills,
			"reloaded": _reloaded,
			"asked": _asked,
			"has_stance": _has_stance,
			"insisted": _insisted,
			"news_open": _news_open,
			"news_seen": _news_seen,
			"call_open": _call_open,
			"call_answered": _call_answered,
			"board_read": _board_read,
			"alarm_on": _alarm_on,
			"alarm_cycled": _alarm_cycled,
			"holstered": _holstered,
			"wheel_open": _wheel_open,
			"gate_shut": _gate_shut,
			"all": _all,
			"any": _any,
			"not": _not,
		}
	return _table


## Whether `name` is a condition.
static func has(name: String) -> bool:
	return registry().has(name)


## Evaluates `spec` ({"cond": name, "params": {...}}, or an empty one, which holds).
## A condition that is not in the registry does not hold.
static func check(spec: Dictionary, sim, state: Dictionary) -> bool:
	if spec.is_empty():
		return true
	var name := String(spec.get("cond", ""))
	var table := registry()
	if not table.has(name):
		return false
	var params = spec.get("params", {})
	return bool(table[name].call(sim, params if typeof(params) == TYPE_DICTIONARY else {}, state))


# ------------------------------------------------------------------ helpers --

static func _person(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


static func _wall(sim, id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


static func _counted(table, key: String) -> float:
	return float(table.get(key, 0.0)) if typeof(table) == TYPE_DICTIONARY else 0.0


# ---------------------------------------------------------------- the basics --

static func _always(_sim, _p, _st) -> bool:
	return true


static func _never(_sim, _p, _st) -> bool:
	return false


## The card's Got it button was pressed.
static func _next(_sim, _p, st) -> bool:
	return bool(st.get("next", false))


## {"seconds": s}: the step has been up this long.
static func _elapsed(_sim, p, st) -> bool:
	return float(st.get("t", 0.0)) >= float(p.get("seconds", 0.0))


## {"what": "gizmo:draft"}: the player did that (see main.gd's _did) at least once.
static func _did(_sim, p, st) -> bool:
	return _counted(st.get("did", {}), String(p.get("what", ""))) > 0.0


## {"type": "shot", "min": 3}: the rules produced that many events of that type since the step began.
static func _event(_sim, p, st) -> bool:
	return _counted(st.get("events", {}), String(p.get("type", ""))) >= float(p.get("min", 1.0))


## {"pan": tiles, "zoom": amount}: the view was panned and zoomed this much.
static func _look_around(_sim, p, st) -> bool:
	return float(st.get("pan", 0.0)) >= float(p.get("pan", 6.0)) and float(st.get("zoom", 0.0)) >= float(p.get("zoom", 0.15))


## {"who": person id} or {"wall": section id}: that one is selected.
static func _selected(_sim, p, st) -> bool:
	var sel = st.get("selection", {})
	if typeof(sel) != TYPE_DICTIONARY or sel.is_empty():
		return false
	if p.has("who"):
		return sel.get("kind", "") == "person" and String(sel.get("id", "")) == String(p.who)
	if p.has("wall"):
		return sel.get("kind", "") == "segment" and int(sel.get("id", -1)) == int(p.wall)
	return true


# ------------------------------------------------------------------- orders --

## {"who": id, "min_dist": tiles}: sent somewhere (an order to walk, not a post), at least
## min_dist tiles from where they stood when the step began.
static func _ordered(sim, p, st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	if who == null or who.order == null or who.order.z > 0.5:
		return false
	var start = st.get("base", {}).get("pos", {}).get(who.id)
	if typeof(start) == TYPE_ARRAY and start.size() == 2:
		var target := Vector2(who.order.x, who.order.y)
		return Vector2(float(start[0]), float(start[1])).distance_to(target) >= float(p.get("min_dist", 0.0))
	return true


## Like `ordered`, and they have got there.
static func _arrived(sim, p, st) -> bool:
	if not _ordered(sim, p, st):
		return false
	var who = _person(sim, String(p.get("who", "")))
	return Vector2(who.x, who.y).distance_to(Vector2(who.order.x, who.order.y)) < float(p.get("radius", 0.8))


## {"who": id}: back to their routine (no order, not drafted).
static func _released(sim, p, _st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	return who != null and not who.drafted and who.order == null


## {"who": id}: told to go to their post.
static func _post_ordered(sim, p, _st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	return who != null and who.order != null and who.order.z > 0.5


## Told to go to their post, and they are standing at it.
static func _posted(sim, p, st) -> bool:
	if not _post_ordered(sim, p, st):
		return false
	var who = _person(sim, String(p.get("who", "")))
	return Vector2(who.x, who.y).distance_to(Vector2(who.order.x, who.order.y)) < float(p.get("radius", 0.8))


## {"wall": id}: somebody has been told to mend that wall piece.
static func _repair_ordered(sim, p, _st) -> bool:
	for who in sim.people:
		if who.repair != null and who.repair.id == int(p.get("wall", -1)):
			return true
	return false


## {"wall": id, "frac": share}: that wall piece is at least this whole.
static func _wall_mended(sim, p, _st) -> bool:
	var seg = _wall(sim, int(p.get("wall", -1)))
	return seg != null and seg.hp >= seg.max_hp * float(p.get("frac", 0.99)) - 0.001


## The scavenging dialog is open, and a place has been chosen in it.
static func _dialog_open(_sim, _p, st) -> bool:
	return bool(st.get("dialog", {}).get("open", false))


static func _site_chosen(_sim, _p, st) -> bool:
	var d = st.get("dialog", {})
	return bool(d.get("open", false)) and String(d.get("site", "")) != ""


## A party has been sent out.
static func _party_out(sim, _p, _st) -> bool:
	return not sim.scavenge.parties.is_empty()


## {"n": speed}: the player pressed that speed.
static func _speed_pressed(_sim, p, st) -> bool:
	return _counted(st.get("did", {}), "speed:%d" % int(p.get("n", 3))) > 0.0


# ---------------------------------------------------------------- the world --

## The lookout has given tonight's forecast.
static func _forecast_given(sim, _p, _st) -> bool:
	return bool(sim.tactics.forecast().get("given", false))


## The dusk bell has rung (and it is not yet dawn).
static func _bell_rung(sim, _p, _st) -> bool:
	return sim.bell_rung and sim.phase != "day"


## {"min": n}: that much ammo has gone since the step began.
static func _ammo_spent(sim, p, st) -> bool:
	return float(st.get("base", {}).get("ammo", sim.stock.ammo)) - float(sim.stock.ammo) >= float(p.get("min", 1.0))


## {"min": n}: that many of the dead have been shot since the step began.
static func _kills(sim, p, st) -> bool:
	return float(sim.kills) - float(st.get("base", {}).get("kills", sim.kills)) >= float(p.get("min", 3.0))


## {"min": n}: that much ammo has been made since the step began.
static func _ammo_gained(sim, p, st) -> bool:
	return float(sim.stock.ammo) - float(st.get("base", {}).get("ammo", sim.stock.ammo)) >= float(p.get("min", 8.0))


static func _fields_on(_sim, _p, st) -> bool:
	return bool(st.get("fields", false))


static func _lure_set(sim, _p, _st) -> bool:
	return sim.tactics.lure_id >= 0


## {"who": id}: their wound has been bandaged (and was seen bleeding first; if it
## never shows, the step does not wait for it).
static func _healed(sim, p, st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	if who == null:
		return true
	if who.bleeding > 0.0:
		st["seen"] = true
	if bool(st.get("seen", false)):
		return who.bleeding <= 0.0
	return float(st.get("t", 0.0)) > 3.0


## {"who": id}: told to be treated (or already cured).
static func _treat_ordered(sim, p, _st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	return who == null or who.infected_at < 0.0 or sim.medical.treat_orders.has(who.id)


## {"who": id}: their fever is gone (and was seen first, as for `healed`).
static func _cured(sim, p, st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	if who == null:
		return true
	if who.infected_at >= 0.0:
		st["seen"] = true
	if bool(st.get("seen", false)):
		return who.infected_at < 0.0
	return float(st.get("t", 0.0)) > 3.0


static func _saved(_sim, _p, st) -> bool:
	return _counted(st.get("did", {}), "save") > 0.0


## {"day": n}: day n has begun (the dawn after the night has come).
static func _day_started(sim, p, _st) -> bool:
	return sim.day >= int(p.get("day", 2)) and sim.phase == "day"


## Somebody (or {"who": id}) has the worktable's job (the Workbench: the key M gives it). It is the
## job that counts, not the work: a lesson that waits for it holds the game still, and nobody
## walks to the bench while it does. Without a workshop it never is.
static func _crafting(sim, p, _st) -> bool:
	var shop = sim.get("workshop")
	if shop == null:
		return false
	var has_it := func(who) -> bool:
		return sim.jobs.job_of(who) == "bench" if sim.get("jobs") != null else bool(shop.crafting(who))
	if p.has("who"):
		var who = _person(sim, String(p.who))
		return who != null and has_it.call(who)
	for who in sim.people:
		if has_it.call(who):
			return true
	return false


# ----------------------------------------------------------- the duty roster --

## The Duty roster's page (key J) is open.
static func _jobs_open(_sim, _p, st) -> bool:
	return bool(st.get("jobs", {}).get("open", false))


## Somebody was given a job since the step began (the coach counts those as "assigned:job").
static func _jobs_given(_sim, _p, st) -> bool:
	return _counted(st.get("events", {}), "assigned:job") >= 1.0


# -------------------------------------------- the hints' triggers (normal runs) --

## {"days": n}: food or water is down to fewer days than that for the crew.
static func _low_stores(sim, p, _st) -> bool:
	var days := float(p.get("days", 2.0))
	return sim.supplies.days_left("food") < days or sim.supplies.days_left("water") < days


## {"below": n}: less ammo than that is left (and some, or the alarm for none says it).
static func _low_ammo(sim, p, _st) -> bool:
	return float(sim.ammo_total()) < float(p.get("below", 60.0))


## Somebody alive is bleeding.
static func _wounded(sim, _p, _st) -> bool:
	for who in sim.people:
		if not who.dead and who.away == null and who.bleeding > 0.0:
			return true
	return false


## Somebody alive has a fever.
static func _feverish(sim, _p, _st) -> bool:
	for who in sim.people:
		if not who.dead and sim.medical.infection_stage(who) != "":
			return true
	return false


## A wall section of the yard is down.
static func _breached(sim, _p, _st) -> bool:
	for s in sim.segments:
		if s.state == 3:
			return true
	return false


## {"kind": "brute"}: one of the dead of that kind is about.
static func _kind_alive(sim, p, _st) -> bool:
	var kind := String(p.get("kind", "walker"))
	for z in sim.zombies:
		if z.kind == kind and z.state != "dead" and z.state != "dying" and z.state != "retreat":
			return true
	return false


## {"day": n, "scrap": n}: the crew could build (round 6): it is that day (3) or later, the stores hold that much scrap
## (30) or more, and nothing is built or going up on any plot yet.
static func _can_build(sim, p, _st) -> bool:
	var buildings = sim.get("build")
	if buildings == null or sim.day < int(p.get("day", 3)) or float(sim.stock.scrap) < float(p.get("scrap", 30.0)):
		return false
	for plot in buildings.plots():
		if String(plot.building) != "" or not plot.site.is_empty():
			return false
	return true


## The game has a Town Board (round 8): a settlement game (a small start), where the scavenging page is the board. For the
## tip about it, which comes once the first time the board could be opened.
static func _town_on(sim, _p, _st) -> bool:
	var town = sim.get("town")
	return town != null and town.on


## {"id": season id}: the game is a campaign (round 10) and it is that season ("winter", "spring", "summer"). For the tip
## of each season, which comes once, when the player first sees it.
static func _season(sim, p, _st) -> bool:
	var seasons = sim.get("seasons")
	return seasons != null and seasons.campaign and String(seasons.current().id) == String(p.get("id", ""))


## The game has lots (round 9: a settlement game) and one of them could be claimed now: the day, the places cleared on the town
## board and the scrap are there. For the tip about the streets round the school, which comes once, the first time it could be done.
static func _lot_open(sim, _p, _st) -> bool:
	var lots = sim.get("lots")
	if lots == null or not lots.on:
		return false
	for l in lots.lots():
		if String(lots.why_not_claim(String(l.id))) == "":
			return true
	return false


## The colony has a vehicle (round 13: one the party has got running and driven home, parked or out). For the tip about taking it
## from the Town Board's party, which comes once, the first time there is one.
static func _has_vehicle(sim, _p, _st) -> bool:
	var vehicles = sim.get("vehicles")
	var town = sim.get("town")
	return vehicles != null and town != null and town.on and not vehicles.fleet.is_empty()



# ----------------------------------------- the avatar game's tips (round 22, the QA's list) --

## The game is played by an avatar (a player named: the hand-played game of rounds 17 to 21).
static func _avatar_game(sim, _p, _st) -> bool:
	return sim.get("player_id") != null and String(sim.player_id) != ""


## The avatar could use something where he stands (a person to talk to, a post, the bench, a car, a worn wall: `Interact.candidates`):
## the moment to say what E is.
static func _can_use(sim, _p, _st) -> bool:
	var it = sim.get("interact")
	return it != null and _avatar_game(sim, _p, _st) and not it.candidates().is_empty()


## The rally's ring is up round the avatar in a night: the bell has rung, he is up and at the base, and the nights' rules apply.
static func _ring_night(sim, _p, _st) -> bool:
	var me = _me(sim)
	if me == null or me.dead or me.downed or me.turned or me.away != null:
		return false
	var nights = sim.get("nights")
	return nights != null and bool(nights.active()) and sim.bell_rung and sim.phase != "day"


## A Big Night is on the way: tonight is one (any hour of its day), or it is past the notice hour and tomorrow's is. The forecast
## the lookout gives and the notice at noon say the same, whoever hears them.
static func _big_night_ahead(sim, _p, _st) -> bool:
	var waves = sim.get("waves")
	if waves == null or not _avatar_game(sim, _p, _st):
		return false
	if not waves.big_night(int(sim.day)).is_empty():
		return true
	return sim.phase == "day" and float(sim.hour) >= NightData.num("forecast.notice_hour", 12.0) and not waves.big_night(int(sim.day) + 1).is_empty()


## The gate's rules are in charge (avatar mode: scripts/sim/gate.gd) and it is the last hour of the day, dusk or night: the moment to say what the
## lever is for. The stand-in a test leaves in the sim's meta "gate_stub" counts (`GateKit.gate_of`).
static func _gate_dusk(sim, _p, _st) -> bool:
	if not GateKit.is_active(sim):
		return false
	var phase := String(sim.phase)
	if phase == "dusk" or phase == "night":
		return true
	return phase == "day" and float(sim.hour) >= float(sim.seasons.dusk_hour()) - 1.0


## The gate's rules are in charge, it is day and the gate stands open (the avatar has opened it, or a car has): the moment to say that walking out
## through it is how the base is left (round 23: the Map opens past the street).
static func _gate_open_day(sim, _p, _st) -> bool:
	if not GateKit.is_active(sim) or String(sim.phase) != "day":
		return false
	return GateKit.open_of(GateKit.active_gate(sim)) >= 0.99


## {"page": "map"}: the radio panel is open on that page (the hints' own state, `{"panel": page}`, from the HUD: the rules do not know
## the screen).
static func _panel_page(_sim, p, st) -> bool:
	return String(st.get("panel", "")) == String(p.get("page", "map"))


## Somebody is picked in the dock (the hints' own state, `{"contact": the person's id}`, from the game: the rules do not know the screen): the moment to
## say that a right click orders them (round 23).
static func _contact_picked(_sim, _p, st) -> bool:
	return String(st.get("contact", "")) != ""


# --------------------------------------------------- the avatar's lesson (round 17) --

## The person the player plays, or null (no avatar: nothing below holds).
static func _me(sim):
	var avatar = sim.get("avatar")
	return avatar.player() if avatar != null else null


## {"min": tiles}: the player has walked this far from where they stood when the step began.
static func _walked(sim, p, st) -> bool:
	var me = _me(sim)
	if me == null:
		return false
	var start = st.get("base", {}).get("pos", {}).get(me.id)
	if typeof(start) != TYPE_ARRAY or start.size() != 2:
		return false
	return Vector2(float(start[0]), float(start[1])).distance_to(Vector2(me.x, me.y)) >= float(p.get("min", 6.0))


## The player stands on a raised walkway (they climbed a ladder).
static func _on_deck(sim, _p, _st) -> bool:
	var me = _me(sim)
	return me != null and sim.levels.on_deck(me)


## {"min": n}: the player has fired this many rounds since the step began.
static func _shots(sim, p, st) -> bool:
	var me = _me(sim)
	var base := int(st.get("base", {}).get("mine", {}).get("shots", 0))
	return me != null and int(me.stats.shots) - base >= int(p.get("min", 1))


## {"min": n}: the player's own shots or blows have put this many of the dead down since the step began.
static func _player_kills(sim, p, st) -> bool:
	var me = _me(sim)
	var base := int(st.get("base", {}).get("mine", {}).get("kills", 0))
	return me != null and int(me.stats.kills) - base >= int(p.get("min", 1))


## The player pressed R and the gun is full again (and no reload is still going on).
static func _reloaded(sim, _p, st) -> bool:
	var me = _me(sim)
	if me == null or _counted(st.get("did", {}), "reload") <= 0.0:
		return false
	return float(me.reloading) <= 0.0 and int(me.mag) >= int(me.gun.get("mag", 0))


## {"who": id, "verb": verb, "ok": bool}: the player asked that one (that verb, with that answer; each is optional) over the
## radio since the step began. `ok`: whether they agreed (false: they refused, and said why).
static func _asked(_sim, p, st) -> bool:
	var events = st.get("events", {})
	if typeof(events) != TYPE_DICTIONARY:
		return false
	for key in events:
		var parts := String(key).split(":")
		if parts.size() != 4 or parts[0] != "radio_line" or float(events[key]) <= 0.0:
			continue
		if p.has("who") and parts[1] != String(p.who):
			continue
		if p.has("verb") and parts[2] != String(p.verb):
			continue
		if p.has("ok") and (parts[3] == "ok") != bool(p.ok):
			continue
		return true
	return false


## {"who": id, "stance": "follow"}: they do what the player asked now (the request took effect: it takes a moment): they hold the
## stance named, or any stance when none is.
static func _has_stance(sim, p, _st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	if who == null:
		return false
	return String(who.stance) == String(p.stance) if p.has("stance") else String(who.stance) != ""


## {"who": id}: the player pushed them (insisted over a refusal): they trust the player less than everybody did to begin with.
static func _insisted(sim, p, _st) -> bool:
	var who = _person(sim, String(p.get("who", "")))
	return who != null and float(sim.radio.trust_of(who)) < float(sim.radio.TRUST_START) - 0.01


## The News panel is open now (the coach notes that in `state.news`).
static func _news_open(_sim, _p, st) -> bool:
	return bool(st.get("news", {}).get("open", false))


## The News panel was open at some time since the step began.
static func _news_seen(_sim, _p, st) -> bool:
	if bool(st.get("news", {}).get("open", false)):
		st["news_seen"] = true
	return bool(st.get("news_seen", false))


## {"kind": "attack"}: a call of the radio (of that kind, if one is named) waits for an answer.
static func _call_open(sim, p, _st) -> bool:
	for e in sim.radio.open_calls():
		if not p.has("kind") or String(e.kind) == String(p.kind):
			return true
	return false


## {"kind": "attack"}: the player answered a call that came since the step began (not one the radio's clock answered).
static func _call_answered(sim, p, st) -> bool:
	var after := int(st.get("base", {}).get("news", 0))
	for e in sim.radio.news:
		if int(e.id) > after and String(e.answered) != "" and not bool(e.get("by_default", false)) and (not p.has("kind") or String(e.kind) == String(p.kind)):
			return true
	return false


## The page that G opens (the board, or in a game without one the scavenging dialog) was open, a place was chosen on it, and
## it is shut again (the coach notes the page in `state.dialog`).
static func _board_read(_sim, _p, st) -> bool:
	var d = st.get("dialog", {})
	if bool(d.get("open", false)):
		st["board_open"] = true
		if String(d.get("site", "")) != "":
			st["board_site"] = true
		return false
	return bool(st.get("board_open", false)) and bool(st.get("board_site", false))


## {"on": true}: the call to arms is on (false: it is off).
static func _alarm_on(sim, p, _st) -> bool:
	return bool(sim.radio.alarm_on) == bool(p.get("on", true))


## The alarm was on at some time since the step began and is off now.
static func _alarm_cycled(sim, _p, st) -> bool:
	if bool(sim.radio.alarm_on):
		st["alarm_seen"] = true
		return false
	return bool(st.get("alarm_seen", false))


## The weapon of the person played is put away (Q): main.gd keeps `holstered` on them, as their drawing reads it (round 26: the lesson of Q).
static func _holstered(sim, _p, _st) -> bool:
	var me = _me(sim)
	return me != null and bool(me.holstered)


## The command wheel (hold C) is up now (the coach notes that in `state.wheel`).
static func _wheel_open(_sim, _p, st) -> bool:
	return bool(st.get("wheel", {}).get("open", false))


## The gate's rules are in charge (avatar mode) and the gate is shut, all the way across, and nothing wants it open: shut by a hand at the lever or
## by the bell's keeper (round 26: the lesson of the gate and the bell). A gate that has been asked to open and has not moved yet is not shut.
static func _gate_shut(sim, _p, _st) -> bool:
	var g = GateKit.active_gate(sim)
	if g == null or GateKit.open_of(g) > GateKit.EPS:
		return false
	return not (g.has_method("wants_open") and bool(g.wants_open()))


# ------------------------------------------------------------- combinators --

## {"of": [{"cond", "params"}, ...]}: every one holds.
static func _all(sim, p, st) -> bool:
	for spec in p.get("of", []):
		if not check(spec, sim, st):
			return false
	return true


## {"of": [...]}: at least one holds.
static func _any(sim, p, st) -> bool:
	for spec in p.get("of", []):
		if check(spec, sim, st):
			return true
	return false


## {"of": {"cond", "params"}}: that one does not hold.
static func _not(sim, p, st) -> bool:
	var spec = p.get("of", {})
	return typeof(spec) == TYPE_DICTIONARY and not check(spec, sim, st)
