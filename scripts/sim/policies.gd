## Policies (round 25, S25.2 of docs/superpowers/plans/2026-10-04-round-25.md): the four dials the player sets for the base, each option with a cost the
## player can see. RATIONS (full / half / hungry: how much everyone eats and drinks), WORK HOURS (normal / overtime: 25% more made, and the crew wears
## out), SCAVENGER BOLDNESS (careful / usual / bold: the numbers of an errand) and STRANGERS AT THE GATE (let in / check / turn away). The numbers and the
## words are assets/data/policies.json's; a number it does not have is the neutral one.
##
## EXACTLY NEUTRAL when inactive (no avatar, Orientation Day, the harness, the classic start: `active()`) and at the default options (full, normal, usual,
## let in: today's game), so the hooks that read this module (supplies, traits, morale, `sim.perf`, scavenge, recruits) multiply by 1.0, add nothing and
## ask nothing. No `sim.rng` anywhere: the weariness is an accumulator of the state.
##
## WEARINESS (`weary`, person id -> 0 to 100): only overtime builds it (+2.5 an hour while someone is at work: `Person.work` is a word of a station, a
## mend, a sort; not "" and not "rest"), and everyone sheds it (-0.6 an hour, whoever they are, times 1 + the Rest priority's weight while they sit at a
## rest spot). Worn out at 60 (mood -4, work x0.9), spent at 85 (mood -8, work x0.8); the News says when someone crosses. Worked out on the slow look
## (30 game minutes, `TICK_S`). The player is not tracked (they have no job to tire of). A person who is away is not working.
##
## One change a dial a game day (`changed_day`). A change is News kind "policy" and, for the dials that have a standing mood line, a mood shock of the
## difference at once (rations, hours); event {"type": "policy", "dial", "option"}.
##
## Reads: `jobs`-free (`Person.work`), `priorities.weight("rest")` (when the module has it), `scavenge._site` and `town.state_of` for a place's danger,
## `recruits.queue` (is the next caller one of the authored survivors), `radio.log_news`, `morale.shock`. Read by: supplies (`ration_mult`), traits
## (`work_mult`), `sim.perf` (`perf_mult`), morale (`mood_lines`), scavenge (`errand_terms`, `errand_limit`), recruits (`strangers_call_ok`,
## `arrival_delay_days`, `caught_at_gate`), and by the briefing, the priorities and the dilemmas (`weary`, `weariness`, `tier_of`, `worn_out`, `fever_risk`).
extends RefCounted

const DATA_PATH := "res://assets/data/policies.json"
## Where the data is read from (tests may point it at another file).
static var data_path := DATA_PATH
static var _cache := {}

const OPTIONS := {"rations": ["full", "half", "hungry"], "hours": ["normal", "overtime"], "boldness": ["careful", "usual", "bold"], "strangers": ["let_in", "check", "turn_away"]}
## Every default is exactly today's game.
const DEFAULTS := {"rations": "full", "hours": "normal", "boldness": "usual", "strangers": "let_in"}
## The slow look: rules seconds between two looks (30 game minutes).
const TICK_S := 10.0
## The keys of `traits.mult` that overtime makes more of.
const WORK_KEYS := ["craft", "repair", "garden"]

var sim
var enabled := true
## Saved. `current`: dial -> option; `weary`: person id -> 0..100; `changed_day`: dial -> the game day it was last changed (one change a dial a day).
var current: Dictionary = DEFAULTS.duplicate()
var weary := {}
var changed_day := {}
## Saved: the rules seconds since the last look (so that a save loads on to the same look).
var _acc := 0.0


func setup(s) -> void:
	sim = s


func start() -> void:
	current = DEFAULTS.duplicate()
	weary = {}
	changed_day = {}
	_acc = 0.0


## A newcomer starts rested (a key for everyone who is here, so that `weary[p.id]` is always there to read once the rules run).
func person_added(p) -> void:
	if active() and _tracked(p):
		weary[String(p.id)] = 0.0


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


# ------------------------------------------------------------------------ data --

static func _data() -> Dictionary:
	if not _cache.has(data_path):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		_cache[data_path] = raw if raw is Dictionary else {}
	return _cache[data_path]


## A dial's entry in the data ({} for one it does not have).
static func _dial(dial: String) -> Dictionary:
	var all = _data().get("dials", {})
	var d = all.get(dial, {}) if all is Dictionary else {}
	return d if d is Dictionary else {}


## An option's entry ({} for one it does not have: that option does nothing).
static func _opt(dial: String, option: String) -> Dictionary:
	var all = _dial(dial).get("options", {})
	var o = all.get(option, {}) if all is Dictionary else {}
	return o if o is Dictionary else {}


## The weariness block of the data.
static func _wear() -> Dictionary:
	var w = _data().get("weariness", {})
	return w if w is Dictionary else {}


static func _tier_data(tier: String) -> Dictionary:
	var t = _wear().get(tier, {})
	return t if t is Dictionary else {}


## `d[key]` as a float, or `fallback` when it is not a finite number.
static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v = d.get(key)
	return float(v) if _num(v) else fallback


## The words of a list in the data ([] for anything else).
static func _words(v) -> Array:
	var out: Array = []
	if v is Array:
		for w in v:
			out.append(String(w))
	return out


## The option now set for a dial (the data's entry).
func _cur(dial: String) -> Dictionary:
	return _opt(dial, String(current.get(dial, DEFAULTS[dial])))


# ----------------------------------------------------------------------- stepping --

func update(dt: float) -> void:
	if not active():
		return
	_acc += dt
	if _acc < TICK_S:
		return
	var looks := int(_acc / TICK_S)
	_acc = fposmod(_acc, TICK_S)
	_look(sim.game_hours(TICK_S * float(looks)))


## The slow look: `hours` game hours have passed. Weariness is gained while at work under overtime and shed always (faster at rest); someone crossing
## 60 or 85 is told in one News line each. Only people who are here and not the player are tracked; the dead and the turned drop out.
func _look(hours: float) -> void:
	var tires := bool(_cur("hours").get("tires", false))
	var gain := _f(_wear(), "gain_per_h", 0.0)
	var decay := _f(_wear(), "decay_per_h", 0.0)
	var rest_w := _rest_weight()
	var crossed := {"worn": [], "spent": []}
	var keep := {}
	for p in sim.people:
		if not _tracked(p):
			continue
		var id := String(p.id)
		keep[id] = true
		var w := clampf(float(weary.get(id, 0.0)), 0.0, 100.0)
		var was := _tier_for(w)
		var word := String(p.work) if p.away == null and not p.downed else ""
		var working := word != "" and word != "rest"
		var rate := -decay * (1.0 + rest_w if word == "rest" else 1.0)
		if tires and working:
			rate += gain
		w = clampf(w + rate * hours, 0.0, 100.0)
		weary[id] = w
		var now := _tier_for(w)
		if _tier_rank(now) > _tier_rank(was):
			crossed[now].append(p)
	for id in weary.keys():
		if not keep.has(id):
			weary.erase(id)
	for tier in ["worn", "spent"]:
		var who: Array = crossed[tier]
		if who.is_empty():
			continue
		var td := _tier_data(tier)
		var names: Array = []
		for p in who:
			names.append(String(p.first))
		var text := String(td.get("text", "{names} {verb} " + tier)).format({"names": _and(names), "verb": "is" if names.size() == 1 else "are"})
		_news(text, String(td.get("sub", "")), {"tier": tier, "who": who.map(func(q): return String(q.id))})


## Someone this module tracks the weariness of: here (not dead, not turned) and not the player.
func _tracked(p) -> bool:
	return p != null and not p.dead and not p.turned and not p.player and String(p.id) != String(sim.player_id)


## The Rest priority's weight (0.0 without the module, or while it is not set).
func _rest_weight() -> float:
	var pr = sim.get("priorities")
	if pr != null and pr.has_method("weight"):
		return maxf(0.0, float(pr.weight("rest")))
	return 0.0


# --------------------------------------------------------------------- weariness --

## 0..100: how worn a person is (0 for the player, the dead and anyone not tracked).
func weariness(p) -> float:
	if p == null:
		return 0.0
	return float(weary.get(String(p.id), 0.0))


## "" (fresh enough), "worn" (60 or more) or "spent" (85 or more).
func tier_of(p) -> String:
	return _tier_for(weariness(p))


func _tier_for(w: float) -> String:
	if w >= _f(_tier_data("spent"), "at", 85.0):
		return "spent"
	if w >= _f(_tier_data("worn"), "at", 60.0):
		return "worn"
	return ""


static func _tier_rank(tier: String) -> int:
	return 2 if tier == "spent" else (1 if tier == "worn" else 0)


## The ids of everyone worn out or spent, the most weary first (ties by id): for the briefing and the Rest priority.
func worn_out() -> Array:
	var out: Array = []
	for id in weary:
		if _tier_for(float(weary[id])) != "":
			out.append(String(id))
	out.sort_custom(func(a, b):
		var wa: float = float(weary[a])
		var wb: float = float(weary[b])
		return wa > wb if wa != wb else String(a) < String(b))
	return out


# ------------------------------------------------------------------------- dials --

## The words of a dial's title ("Rations", "Work hours", "Scavengers", "Strangers at the gate").
func title(dial) -> String:
	return String(_dial(str(dial)).get("title", ""))


## The words of an option (policies.json's): {"name", "blurb", "pros", "cons", "title"} (the dial's title too); empty for what it does not know.
func describe(dial, option) -> Dictionary:
	var o := _opt(str(dial), str(option))
	if o.is_empty():
		return {"name": "", "blurb": "", "pros": [], "cons": [], "title": ""}
	return {"name": String(o.get("name", "")), "blurb": String(o.get("blurb", "")), "pros": _words(o.get("pros")), "cons": _words(o.get("cons")), "title": title(dial)}


## Why this dial cannot be set to this option now ("" when it can): not a dial, not an option, already set, or changed today.
func why_not_set(dial, option) -> String:
	var d := str(dial)
	var o := str(option)
	if not active():
		return "The dials are not available yet"
	if not OPTIONS.has(d) or not (OPTIONS[d] as Array).has(o):
		return "Not a setting this base has"
	if String(current.get(d, DEFAULTS[d])) == o:
		return "Already set"
	if changed_day.has(d) and int(changed_day[d]) >= int(sim.day):
		return "Changed today: again tomorrow"
	return ""


## Sets a dial: {"ok", "line", "why"}. One change a dial a game day ("Changed today: again tomorrow"). On success: News kind "policy" (the option's
## words), the mood shock of what the standing mood line moved by, event "policy".
func set_dial(dial, option) -> Dictionary:
	var d := str(dial)
	var o := str(option)
	var why := why_not_set(d, o)
	if why != "":
		return {"ok": false, "line": "", "why": why}
	var old := String(current.get(d, DEFAULTS[d]))
	var was := _opt(d, old)
	var opt := _opt(d, o)
	current[d] = o
	changed_day[d] = int(sim.day)
	var line := String(opt.get("news", "%s: %s" % [title(d), String(opt.get("name", o))]))
	_news(line, String(opt.get("sub", "")), {"dial": d, "option": o})
	var shift := _f(opt, "mood", 0.0) - _f(was, "mood", 0.0)
	if shift != 0.0:
		sim.morale.shock(null, shift, String(_dial(d).get("shock_cut" if shift < 0.0 else "shock_eased", title(d))))
	sim.events.append({"type": "policy", "dial": d, "option": o})
	return {"ok": true, "line": line, "why": ""}


# --------------------------------------------------------- what the dials do --

## supplies: the share of a meal and of `days_left` per day ("food" or "water"); 1.0 inactive.
func ration_mult(kind: String) -> float:
	if kind != "food" and kind != "water":
		return 1.0
	if not active():
		return 1.0
	return _f(_cur("rations"), kind, 1.0)


## traits.mult / supplies._garden: keys "craft", "repair", "garden" only, else 1.0.
func work_mult(_p, key: String) -> float:
	if not WORK_KEYS.has(key):
		return 1.0
	if not active():
		return 1.0
	return _f(_cur("hours"), "work", 1.0)


## sim.perf: rations (hungry on purpose) and weariness (worn out, spent); 1.0 inactive.
func perf_mult(p) -> float:
	if not active():
		return 1.0
	var m := _f(_cur("rations"), "perf", 1.0)
	var tier := tier_of(p)
	if tier != "":
		m *= _f(_tier_data(tier), "perf", 1.0)
	return m


## morale._modifiers: [{"label", "value"}]; [] inactive. Each dial's standing line (half rations, hungry on purpose, overtime) and the person's
## weariness (worn out, spent).
func mood_lines(p) -> Array:
	var out: Array = []
	if not active():
		return out
	for dial in ["rations", "hours"]:
		var o := _cur(dial)
		var v := _f(o, "mood", 0.0)
		if v != 0.0:
			out.append({"label": String(o.get("mood_label", title(dial))), "value": v})
	var tier := tier_of(p)
	if tier != "":
		var td := _tier_data(tier)
		out.append({"label": String(td.get("label", tier)), "value": _f(td, "mood", 0.0)})
	return out


## The outbreak risk the dials add to every slow look (dilemmas): half rations, hungry, overtime with someone worn out. 0.0 inactive.
func fever_risk() -> float:
	if not active():
		return 0.0
	var risk := _f(_cur("rations"), "fever", 0.0)
	if bool(_cur("hours").get("tires", false)) and not worn_out().is_empty():
		risk += _f(_wear(), "fever_worn_overtime", 0.0)
	return risk


## scavenge.errand_terms(): `base` merged with the boldness numbers; `base` itself when inactive or "usual".
func errand_terms(base: Dictionary) -> Dictionary:
	if not active() or String(current.get("boldness", "usual")) == "usual":
		return base
	var o := _cur("boldness")
	var out: Dictionary = base.duplicate()
	for key in ["loot", "wound", "loss_per_danger", "clear"]:
		if o.has(key) and _num(o[key]):
			out[key] = float(o[key])
	return out


## scavenge.why_not_errand: "" or the careful words (hard): a careful base goes only to a place of danger `max_danger` or less (the danger the Map
## page shows: none once the place is cleared).
func errand_limit(place_id: String) -> String:
	if not active() or String(current.get("boldness", "usual")) != "careful":
		return ""
	var o := _cur("boldness")
	if not _num(o.get("max_danger")):
		return ""
	var site: Dictionary = sim.scavenge._site(place_id)
	if site.is_empty():
		return ""
	var danger := int(site.get("danger", 0))
	var town = sim.get("town")
	if town != null and town.has_method("state_of") and String(town.state_of(place_id)) == "cleared":
		danger = 0
	if danger <= int(o.max_danger):
		return ""
	return String(o.get("limit", "Careful: not to a place this dangerous.")).format({"danger": danger})


# ----------------------------------------------------------------------- strangers --

## recruits.call_due(): false only for "turn away" and a next caller who is not one of the authored survivors (they always come). The queue is read as
## it is: nothing is made (an empty queue means the next caller would be a made-up stranger).
func strangers_call_ok() -> bool:
	if not active() or String(current.get("strangers", "let_in")) != "turn_away":
		return true
	var queue: Array = sim.recruits.queue
	if queue.is_empty():
		return false
	return _authored(queue[0])


## recruits.accept: the days a stranger waits at the gate under "check" (+1).
func arrival_delay_days() -> int:
	if not active():
		return 0
	return maxi(0, int(_f(_cur("strangers"), "arrival_delay_days", 0.0)))


## recruits._arrive: a bitten stranger turned back at the gate under "check" (nobody is added; this sets `next_call_day`, tells the News, adds the
## event). A stranger who is clear is checked too and the News says so. The authored survivors are never turned back.
func caught_at_gate(def: Dictionary) -> bool:
	if not active() or String(current.get("strangers", "let_in")) != "check":
		return false
	var o := _cur("strangers")
	var gate = _data().get("gate", {})
	if not (gate is Dictionary):
		gate = {}
	var who := String(def.get("name", "A stranger")).split(" ")[0]
	var checker := _checker()
	var bitten := bool(def.get("bitten", false)) and bool(o.get("catches_bitten", false)) and not _authored(def)
	if not bitten:
		_news(String(gate.get("clear", "{checker} checked {name} at the gate: clear")).format({"checker": checker, "name": who}), String(gate.get("clear_sub", "")), {"dial": "strangers", "name": who, "bitten": false})
		return false
	_news(String(gate.get("bitten", "{checker} checked {name} at the gate: bitten")).format({"checker": checker, "name": who}), String(gate.get("bitten_sub", "")), {"dial": "strangers", "name": who, "bitten": true})
	sim.recruits.next_call_day = int(sim.day) + int(sim.recruits.REFUSE_DAYS)
	sim.events.append({"type": "turned_away", "who": String(def.get("id", "")), "name": who})
	sim.alert("turned-%s" % String(def.get("id", who)), "info", String(gate.get("alert", "{name} was turned back at the gate")).format({"name": who}), String(gate.get("alert_sub", "")), null, 14.0)
	return true


## Whether a def is one of the authored survivors (Ana, Walt, Hector and the starters), who are not strangers.
func _authored(def) -> bool:
	return sim.recruits.STORY.has(String(def.get("id", ""))) if def is Dictionary else false


## First name of who looks a stranger over at the gate: the best Medicine of those who are here and up (not the player), ties by id; else the player;
## else "The gate watch".
func _checker() -> String:
	var best = null
	for p in sim.people:
		if p.dead or p.turned or p.downed or p.away != null or p.player:
			continue
		if best == null or int(p.skills.get("Medicine", 0)) > int(best.skills.get("Medicine", 0)) or (int(p.skills.get("Medicine", 0)) == int(best.skills.get("Medicine", 0)) and String(p.id) < String(best.id)):
			best = p
	if best == null:
		for p in sim.people:
			if p.player and not p.dead:
				best = p
	return String(best.first) if best != null else "The gate watch"


# ----------------------------------------------------------------------- helpers --

func _news(text: String, sub: String = "", data: Dictionary = {}) -> void:
	var radio = sim.get("radio")
	if radio != null and radio.has_method("log_news"):
		radio.log_news("policy", text, sub, {"data": data})


## "Dez", "Dez and Marcus", "Dez, Ana and Marcus".
static func _and(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


# ------------------------------------------------------------------------- saving --

func save() -> Dictionary:
	return {"current": current.duplicate(), "weary": weary.duplicate(), "changed_day": changed_day.duplicate(), "acc": _acc}


## Restores what `save` wrote; {} (a save from before) is a fresh module with every dial at its default. What is not sound (a dial or option that is not known,
## a number that is not finite, a person who is not here) is left out; weariness is kept between 0 and 100 and a change day is never after today.
func load_state(d: Dictionary) -> void:
	start()
	var cur = d.get("current", {})
	if cur is Dictionary:
		for dial in OPTIONS:
			if cur.has(dial) and (OPTIONS[dial] as Array).has(str(cur[dial])):
				current[dial] = str(cur[dial])
	var here := {}
	for p in sim.people:
		here[String(p.id)] = true
	var w = d.get("weary", {})
	if w is Dictionary:
		for k in w:
			if _num(w[k]) and here.has(str(k)):
				weary[str(k)] = clampf(float(w[k]), 0.0, 100.0)
	var cd = d.get("changed_day", {})
	if cd is Dictionary:
		for dial in cd:
			if OPTIONS.has(str(dial)) and _num(cd[dial]):
				changed_day[str(dial)] = mini(int(cd[dial]), int(sim.day))
	_acc = clampf(float(d.get("acc", 0.0)), 0.0, TICK_S) if _num(d.get("acc")) else 0.0


static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))
