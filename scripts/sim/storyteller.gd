## The storyteller: a hidden tension, a card a day at the radio hour (12:00), and the dawn
## assembly that tells the story of the night.
##
## THE RADIO HOUR. At noon each day the person at the radio desk (whoever works the Radio desk
## station, Ruth to begin with; with nobody there the radio is silent that day) may bring a card
## from assets/data/events.json: a boon, a threat or a choice. About two days in three have one;
## never day 1 (a quiet start) or the last day (the Big Night); at most two threats in a row; the
## same card not again within six days. The draw leans on a hidden tension (0 to 100) that rises
## with trouble (a breach, a death, someone downed, a threat card, a bad night) and falls eight
## on a quiet day: under 20 threats are twice as likely, over
## 70 boons are. Story is calm (threats x0.6), Brutal brings more threats and fewer boons. The draw
## has its own generator, seeded from the run's seed and the day (tomorrow cannot be known, and the
## same run and orders always tell the same story); the rules' own dice (`sim.rng`) are only used
## to settle a `chance` of a card.
##
## A card with a choice waits for the player (the view pauses the rules while the radio card is
## open) and, left alone, takes its `bot` choice two game hours later. A card with no choice is
## settled at once and waits only to be read (one choice, "Understood").
##
## THE DECK is data: {"id", "kind", "weight", "min_day", "max_day", "hour" (when it comes, 12 by
## default), "wait" (game hours before the default is taken), "title", "text", "pick" (what to
## choose when it is drawn: "person", "pair", "section", "lookout"), "needs" (what must be so for
## it to be drawn), "flavor", "effects", "result", "choices": [{"label", "hint", "effects",
## "result", "needs"}], "bot"}. Words may carry {name}, {pair}, {section_name}, {speaker}...; an
## effect may name "@person" for the one chosen. The effects: `stock` {food, water, scrap, ammo,
## meds: delta or {"pct": n}}, `morale` {who, delta, label}, `wound` {who, kind}, `sick` {who,
## hours}, `weather` ("fog", "rain", "clear"), `blackout` {from_hour, until: "fixed", send},
## `night_budget` {multiplier}, `spawn_day` {count, plus_day_div, at, inside}, `wall_damage`
## {section, fraction}, `party` {size, site, followed}, `chance` {p, then, else}, `tension`
## {delta}, `say` (a line of the outcome) and `at_hour` {hour, do} (the same, later).
##
## THE REST OF THE RULES ask this module a few things: `perf(p)` (a sick person works slower),
## `status_of(p)` (the mark), `reach_mult()` (fog: the guns reach less far), `aim_mult(dist)` (in a
## blackout aim is worse far off), `budget_mult(day)` (a warning of a horde: the night's budget),
## `look()` (what the lighting draws) and `treat(p)` (Ana can treat a fever for one medicine).
##
## THE DAWN ASSEMBLY (`report()`): built at each dawn from the night's counters.
##
## Events: {"type": "story_card"} when a card is up, {"type": "story_resolved", "id", "text"} when
## it is settled, {"type": "dawn_report"}. Alerts: `story` (a card waits), `story-<id>` (what came
## of it), `dawn`.
##
## From the buildings (build.gd) it reads `boon_mult` and `threat_mult` (the radio mast: the draw's
## weights of boons and threats, see `_weight`) and `blackout_proof` (the floodlights: a blackout costs
## no aim, see `aim_mult`). The blackout card itself and its generator are as they were.
extends RefCounted

## Where the cards are read from (a test may point it at another file).
const CARDS_PATH := "res://assets/data/events.json"
static var cards_path := CARDS_PATH
static var _parsed := {}

# ------------------------------------------------------------------ the radio hour --
## The hour of the radio, and the chance that a day brings a card at all (about two in three).
const RADIO_HOUR := 12.0
const DRAW_CHANCE := 0.67
## The first day that may have a card (day 1 is a quiet start); the last day (the Big Night) never does.
const FIRST_DAY := 2
## The same card is not drawn again within this many days; at most this many threats come in a row.
const COOLDOWN_DAYS := 6
const MAX_THREATS_IN_ROW := 2
## Game hours a card waits for an answer before its default is taken.
const WAIT_HOURS := 2.0
## How many of the last cards' kinds are remembered.
const RECENT := 4

# ---------------------------------------------------------------------- the tension --
const TENSION_START := 25.0
## Under LEAN_BELOW threats are LEAN times as likely; over LEAN_ABOVE boons are.
const LEAN_BELOW := 20.0
const LEAN_ABOVE := 70.0
const LEAN := 2.0
## The style of each difficulty: the weights of threats and boons (Story, Standard, Brutal).
const STYLE := [{"threat": 0.6, "boon": 1.0}, {"threat": 1.0, "boon": 1.0}, {"threat": 1.5, "boon": 0.7}]
## What each kind of trouble adds, and what a quiet day takes off.
const T_BREACH := 8.0
const T_DEATH := 20.0
const T_DOWNED := 4.0
const T_THREAT := 6.0
const T_BAD_NIGHT := 10.0
const QUIET_DAY := -8.0
## A night that takes this share of the whole wall's health is a bad one.
const BAD_NIGHT_WALL := 0.2

# --------------------------------------------------------------------- what cards do --
## Fog: the guns reach this share of their range (tonight, from dusk to dawn).
const FOG_REACH := 0.7
## A blackout: aim is this much of itself beyond DARK_FROM_TILES; the generator is mended in
## FIX_MINUTES of work by someone standing within FIX_REACH tiles of it.
const DARK_AIM := 0.75
const DARK_FROM_TILES := 6.0
const GENERATOR := Vector2(46.8, 28.2)
const FIX_MINUTES := 40.0
const FIX_REACH := 1.3
## A fever: work is this much of itself; a treatment takes this much medicine.
const SICK_PERF := 0.75
const SICK_HOURS := 20.0
const SICK_MEDS := 1.0
## How many lines the log of the day keeps.
const LOG_MAX := 12
const STOCK_ORDER := ["food", "water", "scrap", "ammo", "meds"]
const STOCK_NAME := {"food": "Food", "water": "Water", "scrap": "Scrap", "ammo": "Ammo", "meds": "Medicine"}
const MARK_COLOR := Color("#7fa6c9")
## How far outside the wall the dead appear when they come by day.
const OUTSIDE := 9.0

## Tests and the tutorial switch the storyteller off with this: no draws, no assembly, no tension.
var enabled := true
## 0 to 100: it rises with trouble and falls with quiet; the draw leans on it.
var tension := TENSION_START
var sim
## The deck, loaded from events.json (see `normalise`).
var cards: Array = []
## Card id to the day it was last drawn, and the kinds of the last few cards drawn (newest last).
var history := {}
var recent: Array = []
## The day whose radio hour has been held.
var radio_day := 0
## What has happened since the last dawn, for the assembly: [{"day", "hour", "text"}].
var day_log: Array = []
## The blackout, if one is coming or on: {"state": "pending" or "dark", "at": clock_min,
## "send": whether to send someone to mend it, "fixer": id, "work": game minutes done}.
var blackout := {}
## Tonight's multiplier of the budget of the dead: {"day", "mult"}.
var night_mult := {"day": 0, "mult": 1.0}
## Who is sick, and until when (person id to sim.clock_min).
var sick := {}
## What is to happen later: [{"at": clock_min, "deliver": card id} or {"at", "do": effects}, "ctx"].
var schedule: Array = []
## The party out on a card's errand: {"n": party number, "site", "followers", "went", "who"}.
var errand := {}

var _card := {}
var _report := {}
var _seen_day := 1
var _trouble_today := 0.0
var _watch_ready := false
var _down := {}
var _hurt := {}
var _gone := {}
var _hp := {}
var _dusk_day := 0
var _kills_at_dusk := 0
var _night_lost := 0.0
var _night_mended := 0.0
var _breaches := 0
var _lost_log: Array = []
var _hurt_log: Array = []
var _gained_seen := {}
## The day whose dusk has had its word about the weather (a fog tonight).
var _dusk_told := 0


func setup(s) -> void:
	sim = s
	_load_cards()


## A fresh run: the first day's tension and no history.
func start() -> void:
	tension = TENSION_START
	history = {}
	recent = []
	radio_day = 0
	day_log = []
	blackout = {}
	night_mult = {"day": 0, "mult": 1.0}
	sick = {}
	schedule = []
	errand = {}
	_card = {}
	_report = {}
	_seen_day = sim.day
	_trouble_today = 0.0
	_watch_ready = false
	_dusk_day = 0
	_kills_at_dusk = 0
	_night_lost = 0.0
	_night_mended = 0.0
	_breaches = 0
	_lost_log = []
	_hurt_log = []
	_gained_seen = {}
	_dusk_told = 0
	_down = {}
	_hurt = {}
	_gone = {}
	_hp = {}


# ------------------------------------------------------------------------------ the deck --

func _load_cards() -> void:
	cards = []
	if not _parsed.has(cards_path):
		var list: Array = []
		if FileAccess.file_exists(cards_path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(cards_path))
			var raw = parsed.get("cards", []) if parsed is Dictionary else parsed
			if raw is Array:
				for entry in raw:
					if entry is Dictionary:
						list.append(normalise(entry))
		else:
			push_error("Could not read the cards from %s" % cards_path)
		_parsed[cards_path] = list
	cards = _parsed[cards_path].duplicate(true)


## A card as the rules use it: every field present and of the right kind.
static func normalise(raw: Dictionary) -> Dictionary:
	var kind := String(raw.get("kind", "boon"))
	if not kind in ["boon", "threat", "choice"]:
		kind = "boon"
	var choices: Array = []
	var raw_choices = raw.get("choices", [])
	if raw_choices is Array:
		for c in raw_choices:
			if c is Dictionary:
				choices.append({
					"label": String(c.get("label", "")),
					"hint": String(c.get("hint", "")),
					"result": String(c.get("result", "")),
					"effects": _list(c.get("effects", [])),
					"needs": _dict(c.get("needs", {})),
				})
	var pick: Array = []
	var raw_pick = raw.get("pick", [])
	if raw_pick is Array:
		for k in raw_pick:
			pick.append(String(k))
	return {
		"id": String(raw.get("id", "")),
		"kind": kind,
		"weight": float(raw.get("weight", 1.0)),
		"min_day": int(raw.get("min_day", FIRST_DAY)),
		"max_day": int(raw.get("max_day", 29)),
		"hour": float(raw.get("hour", RADIO_HOUR)),
		"wait": float(raw.get("wait", WAIT_HOURS)),
		"title": String(raw.get("title", "")),
		"text": String(raw.get("text", "")),
		"pick": pick,
		"needs": _dict(raw.get("needs", {})),
		"flavor": _dict(raw.get("flavor", {})),
		"effects": _list(raw.get("effects", [])),
		"result": String(raw.get("result", "")),
		"choices": choices,
		"bot": clampi(int(raw.get("bot", 0)), 0, maxi(choices.size() - 1, 0)),
	}


static func _list(v) -> Array:
	return v.duplicate(true) if v is Array else []


static func _dict(v) -> Dictionary:
	return v.duplicate(true) if v is Dictionary else {}


static func _strings(v) -> Array:
	var out: Array = []
	if v is Array:
		for e in v:
			out.append(String(e))
	return out


## `v` with every whole float made a whole number, all the way down: saved data comes back from
## JSON with every number a float, and a save must read the same before and after.
static func _tidy(v):
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if is_finite(v) and absf(v) < 1.0e15 and v == floorf(v) else v
		TYPE_ARRAY:
			var list: Array = []
			for e in v:
				list.append(_tidy(e))
			return list
		TYPE_DICTIONARY:
			var dict := {}
			for k in v:
				dict[k] = _tidy(v[k])
			return dict
	return v


## The card with this id, or {}.
func card_named(id: String) -> Dictionary:
	for c in cards:
		if c.id == id:
			return c
	return {}


# ---------------------------------------------------------------------------- the draw --

## The card the radio brings on `day` (or {}), by the rules above. It changes nothing: `remember`
## records a card as drawn.
func draw(day: int) -> Dictionary:
	# the day in the season (the day itself in Autumn): each season has its own quiet first day and Big Night
	if sim.seasons.season_day(day) < FIRST_DAY or day >= sim.scenario.total_days():
		return {}
	var rng := _draw_rng(day)
	var today := rng.randf()
	var roll := rng.randf()
	if today >= DRAW_CHANCE:
		return {}
	var streak := _threat_streak()
	var pool: Array = []
	var total := 0.0
	for c in cards:
		if not _eligible(c, day, streak):
			continue
		var w := _weight(c)
		if w <= 0.0:
			continue
		pool.append([c, w])
		total += w
	if pool.is_empty():
		return {}
	var at := roll * total
	for entry in pool:
		at -= float(entry[1])
		if at < 0.0:
			return entry[0]
	return pool[pool.size() - 1][0]


## Records that `card` was drawn on `day`: its cooldown, and the run of kinds.
func remember(card: Dictionary, day: int) -> void:
	history[String(card.id)] = day
	recent.append(String(card.kind))
	while recent.size() > RECENT:
		recent.pop_front()


## A generator of its own for the day: the same whenever it is asked for.
func _draw_rng(day: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (sim.run_seed * 2654435761 + day * 40503 + 987654321) & 0x7fffffff
	return rng


## Another, for the things a card picks (who, which wall), so the draw itself never moves.
func _pick_rng(salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (sim.run_seed * 2654435761 + salt * 40503 + 123456789) & 0x7fffffff
	return rng


func _threat_streak() -> int:
	var n := 0
	for i in range(recent.size() - 1, -1, -1):
		if recent[i] != "threat":
			break
		n += 1
	return n


func _eligible(c: Dictionary, day: int, streak: int) -> bool:
	var season_day: int = sim.seasons.season_day(day)
	if season_day < int(c.min_day) or season_day > int(c.max_day):
		return false
	if c.kind == "threat" and streak >= MAX_THREATS_IN_ROW:
		return false
	if day - int(history.get(c.id, -1000)) < COOLDOWN_DAYS:
		return false
	return _needs_ok(c.needs)


## The weight of a card in the draw: its own, leaned on by the tension and the difficulty, and by the
## radio mast (the buildings' `boon_mult` and `threat_mult`; a choice is as it was).
func _weight(c: Dictionary) -> float:
	var w := float(c.weight)
	var style: Dictionary = STYLE[clampi(sim.difficulty, 0, 2)]
	if c.kind == "threat":
		w *= float(style.threat)
		w *= sim.build.factor("threat_mult")
		if tension < LEAN_BELOW:
			w *= LEAN
	elif c.kind == "boon":
		w *= float(style.boon)
		w *= sim.build.factor("boon_mult")
		if tension > LEAN_ABOVE:
			w *= LEAN
	return w


## Whether what a card needs is so now: {"stock": {kind: at least}, "free": n people who can be
## sent out (besides the one at the radio), "alive": [ids] who are all up, "people": n up, "wall":
## a wall piece worth hurting}.
func _needs_ok(needs: Dictionary) -> bool:
	var stock = needs.get("stock", {})
	if stock is Dictionary:
		for k in stock:
			if float(sim.stock.get(String(k), 0.0)) < float(stock[k]):
				return false
	if needs.has("free") and _errand_crew(int(needs.free)).size() < int(needs.free):
		return false
	var alive = needs.get("alive", [])
	if alive is Array:
		for id in alive:
			var p = _person(String(id))
			if p == null or not _up(p):
				return false
	if needs.has("people") and _well().size() < int(needs.people):
		return false
	if needs.get("wall", false) and _rot_candidates().is_empty():
		return false
	# a call about a place (the settlement game): there must be someone hiding where the board has not been told
	if needs.get("town_tip", false) and (not sim.town.on or sim.town.tip_place() == ""):
		return false
	return true


# ------------------------------------------------------------------------------ the step --

## Every step: the dawn, the radio hour, what is due, the blackout and the fevers.
func update(dt: float) -> void:
	if not enabled:
		return
	_watch()
	_new_day()
	_radio_hour()
	_dusk_word()
	_run_schedule()
	_wait_for_the_answer()
	_blackout_step(dt)
	_sick_step()
	_errand_step()


func _radio_hour() -> void:
	if radio_day == sim.day or sim.phase != "day" or sim.hour < RADIO_HOUR:
		return
	radio_day = sim.day
	if sim.over != "" or not _card.is_empty() or speaker() == null:
		return
	# a survivor asking the way in (recruits.gd) comes before the day's draw
	var card := card_named("survivor_call") if sim.recruits.call_due() else {}
	if card.is_empty():
		card = draw(sim.day)
	if not card.is_empty():
		_take(card)


## At the bell of a foggy day the crew is reminded what the fog does to the guns tonight.
func _dusk_word() -> void:
	if sim.phase != "dusk" or _dusk_told == sim.day:
		return
	_dusk_told = sim.day
	if sim.weather == "fog":
		sim.alert("story-fog-night", "warn", "Fog tonight", "The guns reach %d%% less far" % roundi((1.0 - FOG_REACH) * 100.0), null, 16.0)


## The person at the radio: whoever is working the Radio desk right now (assigned to it, at their
## seat, up and free); null when nobody is, and then there is no card.
func speaker():
	return sim.jobs.operator("radio")


## Puts a card up now whatever the rules say: for tests and screenshots.
func force(id: String) -> bool:
	var card := card_named(id)
	if card.is_empty() or not _card.is_empty():
		return false
	_take(card)
	return true


## The card is drawn: remembered, and put up (or kept for its hour).
func _take(card: Dictionary) -> void:
	remember(card, sim.day)
	var ctx := _context(card)
	if float(card.hour) > RADIO_HOUR + 0.01:
		schedule.append({"at": _clock_at(float(card.hour)), "deliver": String(card.id), "ctx": ctx})
		return
	_deliver(card, ctx)


func _deliver(card: Dictionary, ctx: Dictionary) -> void:
	var sp = speaker()
	ctx["speaker"] = sp.first if sp != null else "The radio"
	ctx["speaker_id"] = sp.id if sp != null else ""
	_card = {"id": String(card.id), "ctx": ctx, "due": sim.clock_min + float(card.wait) * 60.0, "resolved": false, "result": "", "changes": []}
	if card.kind == "threat":
		_trouble(T_THREAT)
	if card.choices.is_empty():
		var out := _apply(card.effects, ctx)
		var text := _result_text(String(card.result), out, ctx)
		_card["resolved"] = true
		_card["result"] = text
		_card["changes"] = out.changes
		_settled(card, text, out, ctx)
	else:
		sim.alert("story", "info", "%s has news on the radio" % ctx.speaker, "%s: answer by %s" % [_fmt(String(card.title), ctx), _clock_text(float(_card.due))], null, float(card.wait) * 20.0 + 6.0)
	sim.events.append({"type": "story_card"})


## The card waiting for an answer, or {}: {"id", "kind", "title", "text", "speaker" (a first name),
## "speaker_id", "choices": [{"label", "hint", "enabled", "why"}] (a card with no choice has one: "Understood"),
## "bot" (the default), "resolved" (a card with no choice has happened already), "result" and
## "changes" (what came of it), "until" (the hour of the day the default is taken)}.
func pending() -> Dictionary:
	if _card.is_empty():
		return {}
	var card := card_named(String(_card.id))
	if card.is_empty():
		return {}
	var ctx: Dictionary = _card.ctx
	var choices: Array = []
	if card.choices.is_empty():
		choices.append({"label": "Understood", "hint": "", "enabled": true, "why": ""})
	else:
		for c in card.choices:
			var why := _why_not(c)
			choices.append({"label": _fmt(String(c.label), ctx), "hint": _fmt(String(c.hint), ctx), "enabled": why == "", "why": why})
	return {
		"id": String(card.id),
		"kind": String(card.kind),
		"title": _fmt(String(card.title), ctx),
		"text": _fmt(String(card.text), ctx),
		"speaker": String(ctx.get("speaker", "The radio")),
		"speaker_id": String(ctx.get("speaker_id", "")),
		"choices": choices,
		"bot": int(card.bot),
		"resolved": bool(_card.resolved),
		"result": String(_card.result),
		"changes": _card.changes.duplicate(),
		"until": fposmod(float(_card.due) / 60.0 + 7.0, 24.0),
	}


## Answers the pending card with choice `i`; false if nothing is pending, `i` is out of range or
## that choice cannot be made now.
func choose(i: int) -> bool:
	if _card.is_empty():
		return false
	var card := card_named(String(_card.id))
	if card.is_empty():
		_close()
		return false
	if card.choices.is_empty():
		if i != 0:
			return false
		_close()
		return true
	if i < 0 or i >= card.choices.size() or _why_not(card.choices[i]) != "":
		return false
	var ctx: Dictionary = _card.ctx
	var choice: Dictionary = card.choices[i]
	_close()
	var out := _apply(choice.effects, ctx)
	_settled(card, _result_text(String(choice.result), out, ctx), out, ctx)
	return true


## Why a choice cannot be made now ("" when it can).
func _why_not(choice: Dictionary) -> String:
	var needs: Dictionary = choice.get("needs", {})
	if needs.has("housing") and sim.recruits.housing_free() < int(needs.housing):
		return "No bed for them"
	var stock = needs.get("stock", {})
	if stock is Dictionary:
		for k in stock:
			if float(sim.stock.get(String(k), 0.0)) < float(stock[k]):
				return "Needs %d %s" % [int(stock[k]), String(STOCK_NAME.get(String(k), String(k))).to_lower()]
	return ""


func _close() -> void:
	_card = {}
	sim.alerts.erase("story")


## A card is settled: the outcome is told, kept for the assembly, and the view is told.
func _settled(card: Dictionary, text: String, out: Dictionary, ctx: Dictionary) -> void:
	var title := _fmt(String(card.title), ctx)
	var line := text
	if line == "" and not out.changes.is_empty():
		line = ", ".join(out.changes)
	sim.events.append({"type": "story_resolved", "id": String(card.id), "text": text})
	sim.alert("story-%s" % card.id, "warn" if card.kind == "threat" else "info", title, line, null, 30.0)
	_log("%s: %s" % [title, line] if line != "" else title)


## The line that says what came of a card: what the dice said, else what the card says.
func _result_text(base: String, out: Dictionary, ctx: Dictionary) -> String:
	if not out.say.is_empty():
		return " ".join(out.say)
	return _fmt(base, ctx)


## Settles a card nobody has answered in time: its default, or the first choice that can be made.
func _wait_for_the_answer() -> void:
	if _card.is_empty() or sim.clock_min < float(_card.due):
		return
	var card := card_named(String(_card.id))
	if card.is_empty() or card.choices.is_empty():
		_close()
		return
	var i := int(card.bot)
	if _why_not(card.choices[i]) != "":
		i = -1
		for k in card.choices.size():
			if _why_not(card.choices[k]) == "":
				i = k
				break
	if i < 0 or not choose(i):
		_close()


# ----------------------------------------------------------------------------- the words --

## `text` with {name}, {pair}... filled in from `ctx`.
func _fmt(text: String, ctx: Dictionary) -> String:
	if not text.contains("{"):
		return text
	var out := text
	for k in ctx:
		var token := "{%s}" % String(k)
		if out.contains(token):
			var v = ctx[k]
			if v is float and is_finite(v) and v == floorf(v):
				v = int(v)
			out = out.replace(token, str(v))
	return out


## What a card picks when it is drawn (who, which wall, who is on the road).
func _context(card: Dictionary) -> Dictionary:
	var rng := _pick_rng(sim.day)
	var ctx := {"day": sim.day}
	for what in card.pick:
		match String(what):
			"person":
				# (a card the rules draw has somebody well to name; one forced on a crew who are all down has not:
				# it is then about "someone", with the line anybody would have)
				var chosen = _random_up(rng)
				var flavor: Dictionary = card.flavor
				var by_role = flavor.get("by_role", {})
				var line := String(flavor.get("default", ""))
				if chosen != null:
					ctx["person"] = chosen.id
					ctx["name"] = chosen.first
					if by_role is Dictionary and by_role.has(String(chosen.def.get("role", ""))):
						line = String(by_role[String(chosen.def.get("role", ""))])
				else:
					ctx["name"] = "Someone"
				ctx["flavor"] = line
			"pair":
				var ids: Array = []
				var names: Array = []
				for p in _errand_crew(2):
					ids.append(p.id)
					names.append(p.first)
				ctx["pair_ids"] = ids
				ctx["pair"] = _join(names) if not names.is_empty() else "two of us"
			"section":
				var options := _rot_candidates()
				if not options.is_empty():
					var seg = options[rng.randi() % options.size()]
					ctx["section"] = seg.id
					ctx["section_name"] = _where(seg)
			"caller":
				var def: Dictionary = sim.recruits.current_caller()
				if not def.is_empty():
					var line := String(def.get("line", ""))
					ctx["caller_name"] = String(def.name)
					ctx["caller"] = String(def.name).split(" ")[0]
					ctx["caller_role"] = String(def.get("role", "survivor")).to_lower()
					ctx["caller_line"] = line if line != "" else "A voice comes through the static, thin and tired: someone alone, asking whether there is room behind the wall."
			"place":
				var tip: String = sim.town.tip_place() if sim.town.on else ""
				if tip != "":
					ctx["place_id"] = tip
					ctx["place"] = String(sim.town.place(tip).get("name", tip))
			"lookout":
				# whoever is on the Lookout post (the first of them who is up), else only "the lookout"
				var look = null
				for p in sim.jobs.crew_of("watch"):
					if not p.dead and not p.downed:
						look = p
						break
				ctx["lookout"] = look.first if look != null else "The lookout"
	return ctx


func _where(seg) -> String:
	var side: String = {"N": "north", "W": "west", "E": "east", "S": "south"}.get(String(seg.side), "")
	if side == "":
		return "the %s" % String(seg.name).to_lower()
	return "the %s on the %s wall" % [String(seg.name).to_lower(), side]


# --------------------------------------------------------------------------- the effects --

## Applies a list of effects; returns {"changes": [what changed, as the view says it], "say": [lines
## of the outcome the dice chose]}.
func _apply(effects: Array, ctx: Dictionary) -> Dictionary:
	var out := {"changes": [], "say": []}
	for e in effects:
		if e is Dictionary:
			_do(e, ctx, out)
	return out


func _do(effect: Dictionary, ctx: Dictionary, out: Dictionary) -> void:
	for key in effect:
		var v = effect[key]
		match String(key):
			"stock":
				_fx_stock(v, out)
			"morale":
				_fx_morale(v, ctx, out)
			"wound":
				_fx_wound(v, ctx, out)
			"sick":
				_fx_sick(v, ctx, out)
			"weather":
				_fx_weather(String(v), out)
			"reveal_place":
				_fx_reveal_place(ctx, out)
			"blackout":
				_fx_blackout(v, out)
			"night_budget":
				_fx_budget(v, out)
			"spawn_day":
				_fx_spawn(v, ctx, out)
			"wall_damage":
				_fx_wall(v, ctx, out)
			"party":
				_fx_party(v, ctx, out)
			"chance":
				_fx_chance(v, ctx, out)
			"tension":
				tension = clampf(tension + float(v), 0.0, 100.0)
			"recruit":
				_fx_recruit(String(v), out)
			"say":
				out.say.append(_fmt(String(v), ctx))
			"at_hour":
				_fx_later(v, ctx, out)


## The answer to a survivor's call (recruits.gd): "accept" (they come tomorrow at seven) or "refuse".
func _fx_recruit(action: String, out: Dictionary) -> void:
	if action == "accept":
		if sim.recruits.accept():
			out.changes.append("Someone is on the way")
	else:
		sim.recruits.refuse()


func _fx_stock(spec, out: Dictionary) -> void:
	if not spec is Dictionary:
		return
	for kind in STOCK_ORDER:
		if not spec.has(kind):
			continue
		var have := float(sim.stock.get(kind, 0.0))
		var want = spec[kind]
		var delta := 0.0
		var percent := false
		if want is Dictionary:
			delta = snappedf(have * float(want.get("pct", 0.0)) / 100.0, 0.1)
			percent = true
		else:
			delta = float(want)
		var now := maxf(0.0, have + delta)
		sim.stock[kind] = now
		var got := now - have
		if absf(got) < 0.05:
			continue
		if percent:
			out.changes.append("%s %d%% (%s)" % [STOCK_NAME[kind], roundi(float(want.get("pct", 0.0))), _signed(got)])
		else:
			out.changes.append("%s %s" % [STOCK_NAME[kind], _signed(got)])


func _fx_morale(spec, ctx: Dictionary, out: Dictionary) -> void:
	if not spec is Dictionary:
		return
	var who := String(spec.get("who", "all"))
	var delta := float(spec.get("delta", 0.0))
	var label := _fmt(String(spec.get("label", "The radio")), ctx)
	if who == "all":
		sim.morale.shock(null, delta, label)
		out.changes.append("Morale %s for everyone" % _signed(delta))
		return
	var names: Array = []
	for p in _who(who, ctx):
		sim.morale.shock(p, delta, label)
		names.append(p.first)
	if not names.is_empty():
		out.changes.append("Morale %s for %s" % [_signed(delta), _join(names)])


func _fx_wound(spec, ctx: Dictionary, out: Dictionary) -> void:
	if not spec is Dictionary:
		return
	var kind := String(spec.get("kind", "scratch"))
	for p in _who(String(spec.get("who", "@person")), ctx):
		sim.medical.add_wound(p, kind)
		out.changes.append("%s is %s" % [p.first, "bitten" if kind == "bite" else "scratched"])


func _fx_sick(spec, ctx: Dictionary, out: Dictionary) -> void:
	if not spec is Dictionary:
		return
	var hours := float(spec.get("hours", SICK_HOURS))
	for p in _who(String(spec.get("who", "@person")), ctx):
		sick[String(p.id)] = snappedf(sim.clock_min + hours * 60.0, 1.0)
		out.changes.append("%s is sick (works at %d%%)" % [p.first, roundi(SICK_PERF * 100.0)])


func _fx_reveal_place(ctx: Dictionary, out: Dictionary) -> void:
	var id := String(ctx.get("place_id", ""))
	if id == "" or not sim.town.on:
		return
	sim.town.reveal(id)
	out.changes.append("%s is on the town board" % String(ctx.get("place", id)))


func _fx_weather(weather: String, out: Dictionary) -> void:
	if not weather in ["fog", "rain", "clear"]:
		return
	sim.weather = weather
	match weather:
		"fog":
			out.changes.append("Fog tonight: the guns reach %d%% less far" % roundi((1.0 - FOG_REACH) * 100.0))
		"rain":
			out.changes.append("Rain tonight")
		"clear":
			out.changes.append("The sky clears")


func _fx_blackout(spec, out: Dictionary) -> void:
	if not spec is Dictionary:
		return
	var from := float(spec.get("from_hour", 21.0))
	blackout = {"state": "pending", "at": _clock_at(from), "send": bool(spec.get("send", false)), "fixer": "", "work": 0.0}
	var line := "The generator fails at %s" % _hour_text(from)
	if bool(blackout.send):
		line += "; the mechanic goes to mend it"
	else:
		line += " and stays out until morning"
	out.changes.append(line)


func _fx_budget(spec, out: Dictionary) -> void:
	var mult := float(spec.get("multiplier", 1.0)) if spec is Dictionary else float(spec)
	var now := float(night_mult.mult) if int(night_mult.day) == sim.day else 1.0
	night_mult = {"day": sim.day, "mult": now * mult}
	out.changes.append("Tonight's dead: x%s" % _num(mult))


func _fx_spawn(spec, ctx: Dictionary, out: Dictionary) -> void:
	if not spec is Dictionary:
		return
	var count := int(spec.get("count", 1))
	if spec.has("plus_day_div"):
		count += floori(float(sim.seasons.effective_day(sim.day)) / float(maxi(int(spec.plus_day_div), 1)))
	var inside := bool(spec.get("inside", false))
	var seg = _section_for(String(spec.get("at", "north")), ctx, count)
	var kind := String(spec.get("kind", "walker"))
	var place := _where(seg) if seg != null else "the yard"
	for i in count:
		var spot := _spawn_spot(seg, inside, i)
		var z = sim.spawn(spot.x, spot.y, "breach" if inside else "approach", kind)
		if inside:
			z.turned_name = String(spec.get("name", ""))
			z.stagger = 0.8
		elif seg != null:
			sim.assign_slot(z, seg)
	if inside:
		out.changes.append("%d of the dead in the yard" % count if count != 1 else "One of the dead in the yard")
	else:
		out.changes.append("%d of the dead at %s" % [count, place])
	if bool(spec.get("alarm", true)):
		var headline := String(spec.get("alert", ""))
		if headline == "":
			headline = "The dead are in the yard" if inside else "%d of the dead are at %s" % [count, place]
		sim.alert("story-dead", "danger", headline, String(spec.get("sub", "Draft shooters to the wall")), seg.center if seg != null else null, 25.0)


## The wall piece the dead are sent to: "north", "west", "east" (one of that side that still stands,
## chosen by the day's generator, and with room for all of them if there is one), "gate", or a
## piece's id (or "@section").
func _section_for(at: String, ctx: Dictionary, count: int = 1):
	if at == "gate":
		for s in sim.segments:
			if s.kind == "gate":
				return s
		return null
	if at.begins_with("@"):
		return _segment_by_id(int(ctx.get(at.substr(1), -1)))
	if at.is_valid_int():
		return _segment_by_id(int(at))
	var side: String = {"north": "N", "west": "W", "east": "E"}.get(at, "")
	if side == "":
		return null
	var options: Array = []
	var roomy: Array = []
	for s in sim.segments:
		if s.side == side and s.state != 3 and s.kind != sim.DOOR_KIND:
			options.append(s)
			if s.slots.size() >= count:
				roomy.append(s)
	if options.is_empty():
		return null
	if not roomy.is_empty():
		options = roomy
	return options[_pick_rng(sim.day).randi() % options.size()]


func _segment_by_id(id: int):
	for s in sim.segments:
		if s.id == id:
			return s
	return null


## Where one of the dead appears for a card: outside the wall piece a few tiles apart, or just inside
## the gate; somewhere open (else the nearest of the usual spawn points).
func _spawn_spot(seg, inside: bool, i: int) -> Vector2:
	var rng := _pick_rng(sim.day * 31 + i)
	var base := Vector2(39.0, 22.0)
	if seg != null and not inside:
		var away: Vector2 = {"N": Vector2(0, -1), "W": Vector2(-1, 0), "E": Vector2(1, 0), "S": Vector2(0, 1)}.get(String(seg.side), Vector2(0, -1))
		base = seg.center + away * (OUTSIDE + rng.randf() * 2.0)
		base += Vector2(-away.y, away.x) * (rng.randf() - 0.5) * 6.0
	elif seg != null:
		base = seg.center + Vector2(0.0, 2.5)
		base.x += (rng.randf() - 0.5) * 1.6
	for k in 6:
		var candidate := base + Vector2(float(k) * 0.7, float(k) * 0.4) * (1.0 if k % 2 == 0 else -1.0)
		if not sim.world.is_solid(sim.world.solid_z, candidate.x, candidate.y):
			return candidate
	var best: Vector2 = sim.spawns[0]
	for sp in sim.spawns:
		if Vector2(sp).distance_to(base) < best.distance_to(base):
			best = sp
	return best


func _fx_wall(spec, ctx: Dictionary, out: Dictionary) -> void:
	if not spec is Dictionary:
		return
	var which := String(spec.get("section", "@section"))
	var seg = null
	if which.begins_with("@"):
		seg = _segment_by_id(int(ctx.get(which.substr(1), -1)))
	elif which.is_valid_int():
		seg = _segment_by_id(int(which))
	elif which == "random":
		var options := _rot_candidates()
		if not options.is_empty():
			seg = options[_pick_rng(sim.day).randi() % options.size()]
	if seg == null:
		return
	var fraction := float(spec.get("fraction", 0.3))
	sim._damage_segment(seg, seg.max_hp * fraction)
	out.changes.append("%s loses %d%% of its health" % [_where(seg).capitalize(), roundi(fraction * 100.0)])


## The wall pieces worth hurting: not a door, still standing and at least half whole (so a rotten
## board can never bring a wall down by itself).
func _rot_candidates() -> Array:
	var out: Array = []
	for s in sim.segments:
		if s.kind != sim.DOOR_KIND and s.state != 3 and s.hp >= s.max_hp * 0.5:
			out.append(s)
	return out


func _fx_party(spec, ctx: Dictionary, out: Dictionary) -> void:
	if not spec is Dictionary:
		return
	var site := _site_def(spec.get("site", {}))
	var crew := _errand_party(int(spec.get("size", 2)), ctx) if sim.scavenge.get("errands") != null else []
	if crew.is_empty() or site.is_empty():
		out.say.append(String(spec.get("none", "Nobody could be spared, and by evening the crate was gone.")))
		return
	sim.scavenge.errands[String(site.id)] = site
	if not sim.scavenge.send(crew, String(site.id)):
		sim.scavenge.errands.erase(String(site.id))
		out.say.append(String(spec.get("blocked", "The road was not clear, so nobody went.")))
		return
	var followed = spec.get("followed", {})
	var followers := 0
	if followed is Dictionary and not followed.is_empty() and sim.rng.randf() < float(followed.get("p", 0.0)):
		followers = int(followed.get("count", 3))
	var names: Array = []
	for p in crew:
		names.append(p.first)
	errand = {"n": sim.scavenge.trips, "site": site, "followers": followers, "went": false, "who": names}
	out.changes.append("%s go out until %s" % [_join(names), _hour_text(sim.scavenge.RETURN_H)])


## A site as the scavenging module has them (see sites.json), made from a card's data.
func _site_def(raw) -> Dictionary:
	if not raw is Dictionary or raw.is_empty():
		return {}
	var loot := {}
	var raw_loot = raw.get("loot", {})
	if raw_loot is Dictionary:
		for k in raw_loot:
			loot[String(k)] = [int(raw_loot[k][0]), int(raw_loot[k][1])]
	var extra := {}
	var raw_extra = raw.get("extra", {})
	if raw_extra is Dictionary:
		for k in raw_extra:
			extra[String(k)] = [float(raw_extra[k][0]), int(raw_extra[k][1])]
	return {
		"id": String(raw.get("id", "errand")),
		"name": String(raw.get("name", "An errand")),
		"where": String(raw.get("where", "the errand")),
		"blurb": String(raw.get("blurb", "")),
		"danger": int(raw.get("danger", 1)),
		"loot": loot,
		"extra": extra,
		"image": "",
	}


## The people who could go: the free survivors with the best Shooting, the one at the radio excepted.
func _errand_crew(size: int) -> Array:
	if not sim.scavenge.has_method("free_survivors"):
		return []
	var sp = speaker()
	var free: Array = []
	for p in sim.scavenge.free_survivors():
		if p != sp:
			free.append(p)
	free.sort_custom(func(a, b):
		if _skill(a, "Shooting") != _skill(b, "Shooting"):
			return _skill(a, "Shooting") > _skill(b, "Shooting")
		return sim.people.find(a) < sim.people.find(b))
	return free.slice(0, size)


## The card's pair if they are still free, else the best who are.
func _errand_party(size: int, ctx: Dictionary) -> Array:
	var crew: Array = []
	var ids = ctx.get("pair_ids", [])
	if ids is Array:
		for id in ids:
			var p = _person(String(id))
			if p != null and sim.scavenge.can_go(p) and crew.size() < size:
				crew.append(p)
	if crew.size() < size:
		for p in _errand_crew(size + crew.size()):
			if not crew.has(p) and crew.size() < size:
				crew.append(p)
	return crew


func _fx_chance(spec, ctx: Dictionary, out: Dictionary) -> void:
	if not spec is Dictionary:
		return
	var lucky: bool = sim.rng.randf() < float(spec.get("p", 0.5))
	var branch = spec.get("then", []) if lucky else spec.get("else", [])
	if branch is Array:
		for e in branch:
			if e is Dictionary:
				_do(e, ctx, out)


## Something later today (or tonight): the effects wait in `schedule` until their hour.
func _fx_later(spec, ctx: Dictionary, out: Dictionary) -> void:
	if not spec is Dictionary:
		return
	var effects = spec.get("do", [])
	if not effects is Array:
		return
	schedule.append({"at": _clock_at(float(spec.get("hour", 14.0))), "do": effects.duplicate(true), "ctx": ctx.duplicate(true)})
	var note := String(spec.get("note", ""))
	if note != "":
		out.changes.append(_fmt(note, ctx))


## Who an effect means: "all", "@key" (a person or two chosen when the card was drawn), "role:Nurse",
## "speaker", or a person's id; only those who are not gone.
func _who(spec: String, ctx: Dictionary) -> Array:
	var out: Array = []
	if spec == "all":
		for p in sim.people:
			if not p.dead:
				out.append(p)
	elif spec == "speaker":
		var p = _person(String(ctx.get("speaker_id", "")))
		if p != null and not p.dead:
			out.append(p)
	elif spec.begins_with("@"):
		var v = ctx.get(spec.substr(1), "")
		var ids: Array = v if v is Array else [v]
		for id in ids:
			var p = _person(String(id))
			if p != null and not p.dead:
				out.append(p)
	elif spec.begins_with("role:"):
		for p in sim.people:
			if not p.dead and String(p.def.get("role", "")) == spec.substr(5):
				out.append(p)
	else:
		var p = _person(spec)
		if p != null and not p.dead:
			out.append(p)
	return out


# --------------------------------------------------------------------------- what is due --

## Effects and cards that were put off to their hour.
func _run_schedule() -> void:
	if schedule.is_empty():
		return
	var keep: Array = []
	var due: Array = []
	for entry in schedule:
		if sim.clock_min >= float(entry.at):
			due.append(entry)
		else:
			keep.append(entry)
	schedule = keep
	for entry in due:
		var ctx: Dictionary = entry.get("ctx", {})
		if entry.has("deliver"):
			var card := card_named(String(entry.deliver))
			if card.is_empty():
				continue
			if not _card.is_empty():
				# another card is still up: this one comes a little later
				entry["at"] = float(entry.at) + 10.0
				schedule.append(entry)
				continue
			_deliver(card, ctx)
		elif entry.has("do"):
			var out := _apply(entry.do, ctx)
			for line in out.say:
				_log(String(line))
			for line in out.changes:
				_log(String(line))


## The next time the clock reads `hour` (today if it is still ahead), in the rules' whole minutes.
func _clock_at(hour: float) -> float:
	var ahead := fposmod(hour * 60.0 - float(sim.minutes), 1440.0)
	return snappedf(sim.clock_min + ahead, 1.0)


# ------------------------------------------------------------------------ the blackout --

## The spot beside the generator where the work is done: the nearest open ground to it.
func work_spot() -> Vector2:
	var offsets := [Vector2(0, 1.2), Vector2(-1.0, 0), Vector2(1.0, 0), Vector2(0, -1.0), Vector2(-1.0, 1.2), Vector2(1.0, 1.2), Vector2(0, 2.0)]
	for off in offsets:
		var at: Vector2 = GENERATOR + off
		if not sim.world.is_solid(sim.world.solid_p, at.x, at.y):
			return at
	return GENERATOR


func _blackout_step(dt: float) -> void:
	if blackout.is_empty():
		return
	if String(blackout.state) == "pending":
		if sim.clock_min >= float(blackout.at):
			blackout["state"] = "dark"
			sim.events.append({"type": "banner", "text": "Blackout", "sub": "The generator has died"})
			var sub := "The lamps are out. Aim is worse beyond %d tiles" % int(DARK_FROM_TILES)
			if lights_hold():
				sub = "The lamps are out, but the floodlights run on their own"
			sim.alert("story-blackout", "danger", "The generator has died", sub, GENERATOR, 30.0)
			_log("The generator died and the lights went out.")
		return
	# dark: the day brings the light back
	if sim.phase == "day":
		_blackout_over("It was mended at first light.")
		return
	if not bool(blackout.get("send", false)):
		return
	var fixer = _person(String(blackout.get("fixer", "")))
	var spot := work_spot()
	if fixer != null and _up(fixer):
		# another order takes them off the job: the dark stays until morning
		if fixer.order == null or Vector2(fixer.order.x, fixer.order.y).distance_to(spot) > 0.6:
			blackout["send"] = false
			blackout["fixer"] = ""
			return
		if not fixer.moving and Vector2(fixer.x, fixer.y).distance_to(spot) <= FIX_REACH:
			blackout["work"] = float(blackout.get("work", 0.0)) + sim.game_hours(dt) * 60.0
			if float(blackout.work) >= FIX_MINUTES:
				fixer.drafted = false
				fixer.order = null
				fixer.goal_key = ""
				_blackout_over("%s mended the generator." % fixer.first)
		return
	var next = _fixer()
	if next == null:
		return
	if sim.order_move(next, spot.x, spot.y):
		blackout["fixer"] = next.id
		blackout["work"] = 0.0
	else:
		blackout["send"] = false


## Who mends the generator: Dez, else the best builder who is up.
func _fixer():
	var dez = _person("dez")
	if dez != null and _up(dez):
		return dez
	var best = null
	for p in sim.people:
		if _up(p) and (best == null or _skill(p, "Building") > _skill(best, "Building")):
			best = p
	return best


func _blackout_over(how: String) -> void:
	blackout = {}
	sim.alerts.erase("story-blackout")
	sim.alert("story-lights", "info", "The lights are back", how, GENERATOR, 14.0)
	_log("The lights came back. %s" % how)


## Whether tonight's multiplier is a number that makes sense (for the tests' sake).
func mult_ok() -> bool:
	return is_finite(float(night_mult.mult)) and float(night_mult.mult) > 0.0 and float(night_mult.mult) < 100.0


## The state of the blackout: "" (none), "pending" (it fails tonight) or "dark".
func blackout_state() -> String:
	return String(blackout.get("state", "")) if enabled else ""


# ---------------------------------------------------------------------------- fevers --

func is_sick(p) -> bool:
	return enabled and sick.has(String(p.id)) and sim.clock_min < float(sick[String(p.id)])


func _sick_step() -> void:
	if sick.is_empty():
		return
	for id in sick.keys():
		if sim.clock_min >= float(sick[id]):
			sick.erase(id)
			var p = _person(String(id))
			if p != null and not p.dead:
				sim.alert("story-well-%s" % id, "info", "%s is over the fever" % p.first, "Back to full strength", Vector2(p.x, p.y), 8.0)


## How well a person works for what the storyteller has done to them: a fever takes a quarter.
func perf(p) -> float:
	return SICK_PERF if is_sick(p) else 1.0


## Ana (or anyone who knows medicine) treats a fever for one medicine and it is over.
func treat(p) -> bool:
	if not is_sick(p) or float(sim.stock.meds) < SICK_MEDS:
		return false
	var healer = null
	for h in sim.people:
		if h != p and _up(h) and _skill(h, "Medicine") >= 1 and (healer == null or _skill(h, "Medicine") > _skill(healer, "Medicine")):
			healer = h
	if healer == null:
		return false
	sim.stock.meds = maxf(0.0, float(sim.stock.meds) - SICK_MEDS)
	sick.erase(String(p.id))
	sim.alert("treated-sick-%s" % p.id, "info", "%s's fever has broken" % p.first, "%s treated it" % healer.first, Vector2(p.x, p.y), 12.0)
	return true


## The marks for a person's card and panel: a fever.
func status_of(p) -> Array:
	if not is_sick(p):
		return []
	var until := _clock_text(float(sick[String(p.id)]))
	return [{"icon": "fever", "color": MARK_COLOR, "tip": "Sick with a fever: works at %d%% until %s. Ana can treat it with %d medicine." % [roundi(SICK_PERF * 100.0), until, int(SICK_MEDS)]}]


# --------------------------------------------------------------------- the party's errand --

func _errand_step() -> void:
	if errand.is_empty():
		return
	var party = null
	for pt in sim.scavenge.parties:
		if int(pt.n) == int(errand.n):
			party = pt
	if party != null:
		if not bool(errand.get("went", false)):
			for id in party.members:
				var p = _person(String(id))
				if p != null and p.away is Dictionary and p.away.get("kind", "") == "party" and int(p.away.get("n", -1)) == int(errand.n):
					errand["went"] = true
		return
	# the party is home (or the trip was called off)
	var followers := int(errand.get("followers", 0))
	var went := bool(errand.get("went", false))
	var site: Dictionary = errand.get("site", {})
	sim.scavenge.errands.erase(String(site.get("id", "")))
	errand = {}
	if followers > 0 and went:
		var out := _apply([{"spawn_day": {"count": followers, "at": "gate", "alert": "%d of the dead followed them home" % followers, "sub": "They are at the gate. Draft shooters to the wall"}}], {})
		for line in out.changes:
			_log(String(line))


# ------------------------------------------------------------------------ the tension --

func _trouble(amount: float) -> void:
	tension = clampf(tension + amount, 0.0, 100.0)
	_trouble_today += amount


func _in_night() -> bool:
	return sim.phase == "dusk" or sim.phase == "night" or sim.phase == "dawn"


## Every step: what has gone wrong since the last one (a breach, someone downed or lost), and the
## night's counters for the assembly.
func _watch() -> void:
	if not _watch_ready:
		_resync_watch()
		return
	if _in_night() and _dusk_day != sim.day:
		_start_night()
	var night := _in_night()
	for s in sim.segments:
		var down: bool = s.state == 3
		if down and not _down.has(s.id):
			_down[s.id] = true
			_trouble(T_BREACH)
			if night:
				_breaches += 1
		elif not down and _down.has(s.id):
			_down.erase(s.id)
		var change: float = s.hp - float(_hp.get(s.id, s.hp))
		if night and change != 0.0:
			if change < 0.0:
				_night_lost -= change
			else:
				_night_mended += change
		_hp[s.id] = s.hp
	for p in sim.people:
		if p.dead:
			if not _gone.has(p.id):
				_gone[p.id] = true
				var how := _how_lost(p)
				_lost_log.append({"id": p.id, "how": how})
				if how != "left":
					_trouble(T_DEATH)
		elif p.downed:
			if not _hurt.has(p.id):
				_hurt[p.id] = true
				_hurt_log.append(p.id)
				_trouble(T_DOWNED)
		elif _hurt.has(p.id):
			_hurt.erase(p.id)


## The first look at the world after a start or a load: nothing that is already so counts.
func _resync_watch() -> void:
	_watch_ready = true
	_down = {}
	_hurt = {}
	_gone = {}
	_hp = {}
	for s in sim.segments:
		if s.state == 3:
			_down[s.id] = true
		_hp[s.id] = s.hp
	for p in sim.people:
		if p.dead:
			_gone[p.id] = true
		elif p.downed:
			_hurt[p.id] = true


## Dusk: the numbers of the night begin from here.
func _start_night() -> void:
	_dusk_day = sim.day
	_kills_at_dusk = sim.kills
	_night_lost = 0.0
	_night_mended = 0.0
	_breaches = 0


func _how_lost(p) -> String:
	if p.turned:
		return "turned"
	if p.away is Dictionary and String(p.away.get("kind", "")) == "exile":
		return "left"
	if p.away is Dictionary and String(p.away.get("kind", "")) == "lost":
		return "lost"
	return "died"


# ----------------------------------------------------------------------- the assembly --

func _new_day() -> void:
	if sim.day == _seen_day:
		return
	var natural: bool = sim.day == _seen_day + 1
	_seen_day = sim.day
	if natural:
		_dawn()


## The day turns: the tension takes its quiet day or its bad night, and the assembly is built.
func _dawn() -> void:
	var night: int = sim.day - 1
	var wall_max := 0.0
	for s in sim.segments:
		wall_max += float(s.max_hp)
	var had_night: bool = _dusk_day == night
	var lost: float = _night_lost if had_night else 0.0
	var mended: float = _night_mended if had_night else 0.0
	var kills: int = maxi(0, sim.kills - _kills_at_dusk) if had_night else 0
	var bad: bool = wall_max > 0.0 and lost >= BAD_NIGHT_WALL * wall_max
	if _trouble_today <= 0.0 and not bad:
		tension = clampf(tension + QUIET_DAY, 0.0, 100.0)
	if bad:
		tension = clampf(tension + T_BAD_NIGHT, 0.0, 100.0)
	_trouble_today = 0.0
	var mvp := {}
	var best := 0
	for p in sim.people:
		var n := _stat(p, "kills_night")
		if n > best:
			best = n
			mvp = {"who": p.first, "kills": n}
	var gone: Array = []
	for entry in _lost_log:
		var p = _person(String(entry.id))
		if p != null:
			gone.append({"who": p.first, "epitaph": _epitaph(p, String(entry.how)), "how": String(entry.how)})
	var hurt: Array = []
	for id in _hurt_log:
		var p = _person(String(id))
		if p != null and not p.dead:
			hurt.append(p.first)
	_report = _tidy({
		"day": sim.day,
		"night": night,
		"kills": kills,
		"mvp": mvp,
		"wall_lost": roundi(lost),
		"wall_mended": roundi(mended),
		"breaches": _breaches if had_night else 0,
		"lost": gone,
		"hurt": hurt,
		"skill_ups": _skill_ups(),
		"events": _log_lines(),
		"mood": _mood_text(),
		"alive": _ups_and_away().size(),
	})
	_lost_log = []
	_hurt_log = []
	day_log = []
	var sub := "%d put down" % kills if kills > 0 else "A quiet night"
	if not gone.is_empty():
		var names: Array = []
		for g in gone:
			names.append(String(g.who))
		sub += "; %s lost" % _join(names)
	sim.alert("dawn", "info", "Dawn assembly: night %d" % night, sub, null, 150.0)
	sim.events.append({"type": "dawn_report"})


## What the dawn assembly shows: {"day", "night", "kills", "mvp": {"who", "kills"}, "wall_lost",
## "wall_mended", "breaches", "lost": [{"who", "epitaph"}], "hurt": [names], "skill_ups": [{"who",
## "skill", "value"}], "events": [String], "mood": String, "alive"}; {} before the first dawn (and
## while the storyteller is off).
func report() -> Dictionary:
	if not enabled or _report.is_empty():
		return {}
	return _report.duplicate(true)


## The skill points everyone has gained since the last assembly.
func _skill_ups() -> Array:
	var ups: Array = []
	for p in sim.people:
		var now: Dictionary = sim.skills.gained(p)
		var before: Dictionary = _gained_seen.get(String(p.id), {})
		for skill in now:
			if int(now[skill]) > int(before.get(skill, 0)):
				ups.append({"who": p.first, "skill": String(skill), "value": _skill(p, String(skill))})
		_gained_seen[String(p.id)] = now.duplicate()
	return ups


func _log_lines() -> Array:
	var out: Array = []
	for e in day_log:
		out.append(String(e.text))
	return out


func _log(text: String) -> void:
	if text == "":
		return
	day_log.append({"day": sim.day, "hour": snappedf(sim.hour, 0.01), "text": text})
	while day_log.size() > LOG_MAX:
		day_log.pop_front()


## A few words on how the crew is: "Everyone is steady." or "Mostly steady; Marcus is shaken."
func _mood_text() -> String:
	var groups := {}
	var order: Array = []
	for p in _ups_and_away():
		var word: String = String(sim.morale.mood(p)).to_lower()
		if not groups.has(word):
			groups[word] = []
			order.append(word)
		groups[word].append(p.first)
	if order.is_empty():
		return ""
	var main_word: String = order[0]
	for w in order:
		if groups[w].size() > groups[main_word].size():
			main_word = w
	if order.size() == 1:
		return "Everyone is %s." % main_word
	var rest: Array = []
	for w in order:
		if w != main_word:
			rest.append("%s %s %s" % [_join(groups[w]), "is" if groups[w].size() == 1 else "are", w])
	return "Mostly %s; %s." % [main_word, "; ".join(rest)]


## What is said of someone who is gone: their own line (barks) or a plain one.
func _epitaph(p, how: String) -> String:
	if sim.barks.has_method("epitaph"):
		var line = sim.barks.epitaph(p)
		if line is String and line != "":
			return line
	match how:
		"turned":
			return "%s turned in the night. We put them down." % p.first
		"left":
			return "%s left through the gate." % p.first
		"lost":
			return "%s did not come back from the road." % p.first
	return "%s did not see the morning." % p.first


func _stat(p, key: String) -> int:
	var st = p.get("stats")
	if st is Dictionary and st.has(key):
		return int(st[key])
	return 0


# ------------------------------------------------------- what the rest of the rules ask --

## How far the guns reach, as a share of their range: less in a fog (from dusk to dawn).
func reach_mult() -> float:
	if enabled and sim.weather == "fog" and sim.phase != "day":
		return FOG_REACH
	return 1.0


## How well a shot at `dist` tiles goes, as a share: worse far off in the dark of a blackout, unless
## the floodlights stand (`lights_hold`).
func aim_mult(dist: float) -> float:
	if enabled and String(blackout.get("state", "")) == "dark" and dist > DARK_FROM_TILES and not lights_hold():
		return DARK_AIM
	return 1.0


## Whether the wall is lit on its own while the generator is dead: the floodlights (the buildings'
## `blackout_proof`) have a generator of their own. The blackout still happens; it costs no aim.
func lights_hold() -> bool:
	return sim.build.bonus("blackout_proof") > 0.0


## What tonight's budget of the dead is multiplied by on `day` (a warning of a horde).
func budget_mult(day: int) -> float:
	if enabled and int(night_mult.day) == day:
		return float(night_mult.mult)
	return 1.0


## What the lighting draws: {"fog": 0 to 1 (how thick), "rain": bool, "blackout": bool}. A fog thickens
## from the afternoon to dusk.
func look() -> Dictionary:
	var fog := 0.0
	if enabled and sim.weather == "fog":
		fog = 1.0 if sim.phase != "day" else clampf(0.35 + 0.65 * (sim.hour - RADIO_HOUR) / (sim.seasons.dusk_hour() - RADIO_HOUR), 0.35, 1.0)
	return {
		"fog": fog,
		"rain": enabled and sim.weather == "rain",
		"snow": enabled and sim.weather == "snow",
		"blackout": enabled and String(blackout.get("state", "")) == "dark",
	}


# ------------------------------------------------------------------------------ saves --

func save() -> Dictionary:
	return _tidy({
		"enabled": enabled,
		"tension": tension,
		"history": history.duplicate(),
		"recent": recent.duplicate(),
		"radio_day": radio_day,
		"seen_day": _seen_day,
		"card": _card.duplicate(true),
		"log": day_log.duplicate(true),
		"blackout": blackout.duplicate(true),
		"night_mult": {"day": int(night_mult.day), "mult": float(night_mult.mult)},
		"sick": sick.duplicate(),
		"schedule": schedule.duplicate(true),
		"errand": errand.duplicate(true),
		"report": _report.duplicate(true),
		"trouble": _trouble_today,
		"dusk_day": _dusk_day,
		"kills_at_dusk": _kills_at_dusk,
		"night_lost": _night_lost,
		"night_mended": _night_mended,
		"breaches": _breaches,
		"lost_log": _lost_log.duplicate(true),
		"hurt_log": _hurt_log.duplicate(),
		"gained_seen": _gained_seen.duplicate(true),
		"dusk_told": _dusk_told,
	})


func load_state(d: Dictionary) -> void:
	# a save says whether the storyteller was on (the tutorial's is off); one from before it did not
	# says nothing, and the game keeps what it has
	if d.has("enabled"):
		enabled = bool(d.enabled)
	tension = clampf(float(d.get("tension", TENSION_START)), 0.0, 100.0)
	history = {}
	var h = d.get("history", {})
	if h is Dictionary:
		for k in h:
			history[String(k)] = int(h[k])
	recent = _strings(d.get("recent", []))
	radio_day = int(d.get("radio_day", 0))
	_seen_day = int(d.get("seen_day", sim.day))
	_card = {}
	var c = d.get("card", {})
	if c is Dictionary and c.has("id") and not card_named(String(c.id)).is_empty():
		_card = {
			"id": String(c.id),
			"ctx": _tidy(_dict(c.get("ctx", {}))),
			"due": float(c.get("due", 0.0)),
			"resolved": bool(c.get("resolved", false)),
			"result": String(c.get("result", "")),
			"changes": _strings(c.get("changes", [])),
		}
	day_log = []
	var lg = d.get("log", [])
	if lg is Array:
		for e in lg:
			if e is Dictionary:
				day_log.append({"day": int(e.get("day", 0)), "hour": float(e.get("hour", 0.0)), "text": String(e.get("text", ""))})
	blackout = {}
	var b = d.get("blackout", {})
	if b is Dictionary and not b.is_empty():
		blackout = {"state": String(b.get("state", "pending")), "at": float(b.get("at", 0.0)), "send": bool(b.get("send", false)), "fixer": String(b.get("fixer", "")), "work": float(b.get("work", 0.0))}
	night_mult = {"day": 0, "mult": 1.0}
	var nm = d.get("night_mult", {})
	if nm is Dictionary:
		night_mult = {"day": int(nm.get("day", 0)), "mult": float(nm.get("mult", 1.0))}
	sick = {}
	var sk = d.get("sick", {})
	if sk is Dictionary:
		for k in sk:
			sick[String(k)] = float(sk[k])
	schedule = []
	var sc = d.get("schedule", [])
	if sc is Array:
		for e in sc:
			if not (e is Dictionary and e.has("at")):
				continue
			var entry := {"at": float(e.at), "ctx": _tidy(_dict(e.get("ctx", {})))}
			if e.has("deliver"):
				entry["deliver"] = String(e.deliver)
			elif e.get("do") is Array:
				entry["do"] = _tidy(_list(e.do))
			else:
				continue
			schedule.append(entry)
	errand = {}
	var er = d.get("errand", {})
	if er is Dictionary and not er.is_empty():
		errand = {"n": int(er.get("n", 0)), "site": _site_def(er.get("site", {})), "followers": int(er.get("followers", 0)), "went": bool(er.get("went", false)), "who": _strings(er.get("who", []))}
		if not errand.site.is_empty():
			sim.scavenge.errands[String(errand.site.id)] = errand.site
	_report = _tidy(_dict(d.get("report", {})))
	_trouble_today = float(d.get("trouble", 0.0))
	_dusk_day = int(d.get("dusk_day", 0))
	_kills_at_dusk = int(d.get("kills_at_dusk", 0))
	_night_lost = float(d.get("night_lost", 0.0))
	_night_mended = float(d.get("night_mended", 0.0))
	_breaches = int(d.get("breaches", 0))
	_lost_log = []
	var ll = d.get("lost_log", [])
	if ll is Array:
		for e in ll:
			if e is Dictionary:
				_lost_log.append({"id": String(e.get("id", "")), "how": String(e.get("how", "died"))})
	_hurt_log = _strings(d.get("hurt_log", []))
	_gained_seen = {}
	var gs = d.get("gained_seen", {})
	if gs is Dictionary:
		for k in gs:
			if gs[k] is Dictionary:
				var skills := {}
				for s in gs[k]:
					skills[String(s)] = int(gs[k][s])
				_gained_seen[String(k)] = skills
	_dusk_told = int(d.get("dusk_told", 0))
	_watch_ready = false


# -------------------------------------------------------------------------------- helpers --

func _person(id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## Alive, on their feet and on the map.
func _up(p) -> bool:
	return not p.dead and not p.downed and p.away == null


func _ups() -> Array:
	var out: Array = []
	for p in sim.people:
		if _up(p):
			out.append(p)
	return out


## The people who are up and not sick: whom a card can name.
func _well() -> Array:
	var out: Array = []
	for p in _ups():
		if not is_sick(p):
			out.append(p)
	return out


func _ups_and_away() -> Array:
	var out: Array = []
	for p in sim.people:
		if not p.dead:
			out.append(p)
	return out


## Someone who is up (and not already sick), chosen by `rng`.
func _random_up(rng: RandomNumberGenerator):
	var options: Array = []
	for p in _ups():
		if not is_sick(p):
			options.append(p)
	if options.is_empty():
		return null
	return options[rng.randi() % options.size()]


## A skill of someone: their own (it grows) if they have it, else the roster's.
func _skill(p, skill_name: String) -> int:
	var own = p.get("skills")
	if own is Dictionary and own.has(skill_name):
		return int(own[skill_name])
	return int(p.def.skills.get(skill_name, 0))


## "+20", "-5", "+1.5": a number with its sign, whole when it is.
func _signed(x: float) -> String:
	return ("+" if x >= 0.0 else "-") + _num(absf(x))


func _num(x: float) -> String:
	return str(roundi(x)) if absf(x - roundf(x)) < 0.05 else "%.1f" % x


## "Dez", "Dez and Hector", "Dez, Hector and Ana".
func _join(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


## 16.0 as "16:00".
func _hour_text(hour: float) -> String:
	var m := roundi(fposmod(hour * 60.0, 1440.0))
	return "%02d:%02d" % [floori(m / 60.0), m % 60]


## A time on the run's clock (game minutes, 0 at 07:00 of day 1) as the hour of the day: "14:20".
func _clock_text(clock: float) -> String:
	return _hour_text((clock + 420.0) / 60.0)
