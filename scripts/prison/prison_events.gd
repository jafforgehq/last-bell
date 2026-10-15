## EXPERIMENT (event deck + traits of the people): two small things the 30-day arc (prison_arc.gd, `events`) owns.
## 1. WHO PEOPLE ARE: assets/data/prison_bios.json gives every person of the prison (the roster, the three allies, the pool raids find) one to two traits (assets/data/traits.json, the ten of the
##    colony plus coward, hothead, scrounger, thief, veteran, pacifist) and a one-line background. `traits_of(name)` is that list plus what events added (`arc.person_traits`). The rules ask by name
##    (`mult`, `sum`, `has`): the crew is rebuilt after every raid, so nothing here lives on a pawn.
## 2. THE DECK: assets/data/prison_events.json, a card each for a morning with no story beat. `draw(day)` picks one (seeded by `arc.run_seed` and the day, never the same card twice, filtered by
##    `if`); the story shows it (prison_story.gd `show_event`); `arc.deliver_event` applies the choice through `arc._apply`, which hands the new effect keys to `apply_extra` here.
## Card: {id, title, from, tone, text, pick (who the card is about: "trait:thief|random"), urgent (bypasses the draw chance), if {...}, choices: [{id, label, if, safe, result, effects}]}.
## Rare card keys: `odds` (a share of the quiet mornings, rolled on its own: it comes before the common draw) and `repeat` (it can be drawn again, as a stranger can).
## `if`: day [a,b], stock_min {res:n}, stock_max {res:n}, tier {building:n}, trait id, crew_min n, crew_max n (crew without kids and Ruth), morale_min, morale_max, role id (someone alive does it),
##    beds_free n, flag id|[ids], no_flag id|[ids], flag_age {id: days since it was set}, seen id (a card shown before), no_trait id, unused name (nobody of the pool by that name is in the crew yet),
##    any [conditions] (one of them holds).
## Effects (every key is optional, every failure is a no-op): stores {res: n}, morale n, flag id|{id: true}, night_mod {size, weather, night (0 = tonight)}, raid_mod "variant" (the next raid; another
##    agent reads `arc.take_raid_mod()`), set_piece {...} (a marked cache, as the ferry depot), person: one op or an array of
##    {"op": "add", "name"|"skill", "trait", "hurt": days, "else": effects if there is no bed or nobody left to find}
##    {"op": "wound", "who", "days"}   {"op": "kill", "who"}   {"op": "leave", "who"}   {"op": "trait", "who", "add"}
##    `who`: "$who" (the card's person), "random", "trait:id", "role:id", "guard", or a name; kids are never picked at random.
## Text: {who} is the card's person, {name} the person an effect just picked or added.
extends RefCounted

const PATH := "res://assets/data/prison_events.json"
const BIOS := "res://assets/data/prison_bios.json"
const TRAITS := "res://assets/data/traits.json"

var arc
var game
var cards: Array = []
var chance := 0.7
var first_day := 2
var last_day := 28
var bios: Dictionary = {}
var defs: Dictionary = {}    # trait id -> {name, blurb, effects}


func _init(a) -> void:
	arc = a
	game = a.game
	var p = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if p is Dictionary:
		cards = p.get("cards", [])
		chance = float(p.get("chance", chance))
		first_day = int(p.get("first_day", first_day))
		last_day = int(p.get("last_day", last_day))
	var b = JSON.parse_string(FileAccess.get_file_as_string(BIOS))
	if b is Dictionary:
		bios = b.get("people", {})
	var t = JSON.parse_string(FileAccess.get_file_as_string(TRAITS))
	if t is Dictionary:
		for e in t.get("traits", []):
			defs[String(e.id)] = e


# ------------------------------------------------------------------------------- people --

func traits_of(nm: String) -> Array:
	var out: Array = (bios.get(nm, {}).get("traits", []) as Array).duplicate()
	for t in arc.person_traits.get(nm, []):
		if not out.has(t):
			out.append(t)
	return out


func bio_of(nm: String) -> String:
	return String(bios.get(nm, {}).get("bio", ""))


func has(nm: String, id: String) -> bool:
	return traits_of(nm).has(id)


## The product of the traits' numbers for `key` (1.0 when none have it).
func mult(nm: String, key: String) -> float:
	var m := 1.0
	for t in traits_of(nm):
		m *= float(defs.get(t, {}).get("effects", {}).get(key, 1.0))
	return m


## The sum of the traits' numbers for `key` (0.0 when none have it).
func sum(nm: String, key: String) -> float:
	var s := 0.0
	for t in traits_of(nm):
		s += float(defs.get(t, {}).get("effects", {}).get(key, 0.0))
	return s


## "Steady, Veteran": the names of the traits, for the roster and the cards.
func trait_text(nm: String) -> String:
	var out: Array = []
	for t in traits_of(nm):
		out.append(String(defs.get(t, {}).get("name", t)))
	return ", ".join(out)


## "Cole (Steady, Veteran)".
func label(nm: String) -> String:
	var t := trait_text(nm)
	return nm if t == "" else "%s (%s)" % [nm, t]


# -------------------------------------------------------------------------------- deck --

func card(id: String) -> Dictionary:
	for c in cards:
		if String(c.id) == id:
			return c
	return {}


func _rng(salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = arc.run_seed * 7919 + arc.day * 104729 + salt
	return r


func _crew(kids := false) -> Array:
	return (game.econ.crew() as Array).filter(func(c): return kids or not bool(c.kid))


## The card for this morning: {id, who} or {}.
func draw(d: int) -> Dictionary:
	if d < first_day or d > last_day or game.args.has("noevents"):    # (`--noevents`: the lab without the deck, to see what it costs)
		return {}
	var ok: Array = []
	var urgent: Array = []
	for c in cards:
		if (arc.events_seen.has(String(c.id)) and not bool(c.get("repeat", false))) or not _cond(c.get("if", {}), d):
			continue
		if c.has("odds"):    # a rare card: its own roll, and it may come again
			var ro := RandomNumberGenerator.new()
			ro.seed = hash([arc.run_seed, d, String(c.id)])    # (hashed: nearby day seeds of _rng give nearby first numbers)
			if ro.randf() < float(c.odds):
				return {"id": String(c.id), "who": ""}
			continue
		(urgent if bool(c.get("urgent", false)) else ok).append(c)
	var r := _rng(1)
	var pool: Array = urgent
	if pool.is_empty():
		pool = ok
		if pool.is_empty() or r.randf() > chance:
			return {}
	var c: Dictionary = pool[r.randi() % pool.size()]
	var who := ""
	if c.has("pick"):
		who = _pick(String(c.pick), r)
	return {"id": String(c.id), "who": who}


func _cond(cond: Dictionary, d: int) -> bool:
	if cond.has("day") and (d < int(cond.day[0]) or d > int(cond.day[1])):
		return false
	for k in cond.get("stock_min", {}):
		if float(game.stores.get(k, 0.0)) < float(cond.stock_min[k]):
			return false
	for k in cond.get("stock_max", {}):
		if float(game.stores.get(k, 0.0)) > float(cond.stock_max[k]):
			return false
	for k in cond.get("tier", {}):
		if int(game.econ.tier(String(k))) < int(cond.tier[k]):
			return false
	if cond.has("any"):
		var hit := false
		for sub in cond.any:
			hit = hit or _cond(sub, d)
		if not hit:
			return false
	if cond.has("unused") and (game.people._used() as Array).has(String(cond.unused)):
		return false
	var crew := _crew()
	if cond.has("trait") and _by_trait(crew, String(cond.trait)).is_empty():
		return false
	if cond.has("no_trait") and not _by_trait(crew, String(cond.no_trait)).is_empty():
		return false
	if cond.has("crew_min") and crew.size() < int(cond.crew_min):
		return false
	if cond.has("crew_max") and crew.size() > int(cond.crew_max):
		return false
	if cond.has("morale_min") and float(game.econ.morale) < float(cond.morale_min):
		return false
	if cond.has("morale_max") and float(game.econ.morale) > float(cond.morale_max):
		return false
	if cond.has("role") and int(game.econ.workers(String(cond.role))) <= 0:
		return false
	if cond.has("beds_free") and int(game.econ.beds().free) < int(cond.beds_free):
		return false
	for f in _list(cond.get("flag", [])):
		if not arc.flags.has(String(f)):
			return false
	for f in _list(cond.get("no_flag", [])):
		if arc.flags.has(String(f)):
			return false
	for f in cond.get("flag_age", {}):
		if not arc.flags.has(String(f)) or d - int(arc.flags[f]) < int(cond.flag_age[f]):
			return false
	for f in _list(cond.get("seen", [])):
		if not arc.events_seen.has(String(f)):
			return false
	return true


static func _list(v) -> Array:
	return v if v is Array else [v]


## The choices the player is offered (a choice may have its own `if`).
func choices(c: Dictionary) -> Array:
	return (c.get("choices", []) as Array).filter(func(ch): return _cond(ch.get("if", {}), arc.day))


## The choice a scripted run takes: the one marked `safe`, else the last.
func safe_index(c: Dictionary) -> int:
	var list := choices(c)
	for i in list.size():
		if bool(list[i].get("safe", false)):
			return i
	return maxi(0, list.size() - 1)


## The text with the card's person and the one an effect picked put in.
func fill(text: String, ctx: Dictionary) -> String:
	return text.replace("{who}", arc.dn(String(ctx.get("who", "someone")))).replace("{name}", arc.dn(String(ctx.get("name", ctx.get("who", "someone")))))


# ---------------------------------------------------------------------------- who and what --

func _by_trait(crew: Array, id: String) -> Array:
	return crew.filter(func(c): return has(String(c.name), id))


## One name by a selector ("trait:thief|random" falls back to the next); "" when nobody fits.
func _pick(sel: String, r: RandomNumberGenerator, ctx: Dictionary = {}) -> String:
	for one in sel.split("|"):
		var crew := _crew(one == "kid")
		var list: Array = []
		if one == "$who":
			return String(ctx.get("who", ""))
		elif one == "random":
			list = crew
		elif one == "kid":
			list = crew.filter(func(c): return bool(c.kid))
		elif one.begins_with("trait:"):
			list = _by_trait(crew, one.substr(6))
		elif one.begins_with("role:"):
			list = crew.filter(func(c): return String(c.role) == one.substr(5))
		elif one == "guard":
			list = crew.filter(func(c): return bool(c.guard))
		else:
			list = crew.filter(func(c): return String(c.name) == one)
		if not list.is_empty():
			return String(list[r.randi() % list.size()].name)
	return ""


## The effect keys `_apply` does not know. Every one of them does nothing when it cannot happen.
func apply_extra(fx: Dictionary, ctx: Dictionary) -> void:
	if not ctx.has("lines"):
		ctx["lines"] = []
	var r := _rng(2 + int(ctx.get("n", 0)))
	ctx["n"] = int(ctx.get("n", 0)) + 1
	if fx.has("flag"):
		var f = fx.flag
		for k in (f.keys() if f is Dictionary else [f]):
			arc.flags[String(k)] = arc.day
	if fx.has("night_mod"):
		var m: Dictionary = fx.night_mod
		var n := str(arc.day + int(m.get("night", 0)))
		var e: Dictionary = arc.night_mods.get(n, {})
		e["size"] = float(e.get("size", 1.0)) * float(m.get("size", 1.0))
		arc.night_mods[n] = e
		if m.has("weather") and arc.cfg.weather_kinds.has(String(m.weather)):
			arc.weather_over[n] = String(m.weather)
		var pct := roundi((float(m.get("size", 1.0)) - 1.0) * 100.0)
		if pct != 0:
			ctx.lines.append("tonight %+d%% dead" % pct)
	if fx.has("raid_mod"):
		arc.raid_mod = String(fx.raid_mod)
	if fx.has("set_piece") and arc.set_piece.is_empty():
		arc.set_piece = (fx.set_piece as Dictionary).duplicate(true)
		arc.set_piece["pos"] = Vector2(-1, -1)
		ctx.lines.append("a cache is marked for the next raid")
	var ops = fx.get("person", [])
	for op in (ops if ops is Array else [ops]):
		_op(op, ctx, r)


func _op(op: Dictionary, ctx: Dictionary, r: RandomNumberGenerator) -> void:
	var kind := String(op.get("op", ""))
	if kind == "add":
		if not _add(op, ctx):
			arc._apply(op.get("else", {}), ctx)
		return
	var nm := _pick(String(op.get("who", "random")), r, ctx)
	if nm == "":
		return
	ctx["name"] = nm
	match kind:
		"wound":
			var days := int(op.get("days", 2))
			arc.hurt[nm] = arc.day + days - 1
			ctx.lines.append("%s is hurt for %d day%s" % [nm, days, "" if days == 1 else "s"])
		"kill":
			arc.kill(nm, "event")
			ctx.lines.append("%s dies" % nm)
		"leave":
			game.econ.person_left.emit(nm)
			ctx.lines.append("%s leaves" % nm)
		"trait":
			var t := String(op.get("add", ""))
			if defs.has(t) and not has(nm, t):
				arc.person_traits[nm] = (arc.person_traits.get(nm, []) as Array) + [t]
				if arc.game.crew != null:
					for m in arc.game.crew.members:
						if String(m.def.name) == nm:
							arc.game.run.sim.traits.give(m.p, traits_of(nm))
				ctx.lines.append("%s is now %s" % [nm, String(defs[t].name)])


## A person of the pool joins the crew (a free bed and an unused name are needed). `name` first, else the first unused of `skill`.
func _add(op: Dictionary, ctx: Dictionary) -> bool:
	var people = game.people
	if int(game.econ.beds().free) <= 0 or game.crew == null:
		return false
	var used: Array = people._used()
	var who: Dictionary = {}
	for q in people._c().people:
		var nm := String(q.name)
		if used.has(nm):
			continue
		if (op.has("name") and nm == String(op.name)) or (not op.has("name") and (not op.has("skill") or String(q.skill) == String(op.skill))):
			who = q
			break
	if who.is_empty():
		return false
	var nm2 := String(who.name)
	var rr := _rng(9)
	if op.has("traits") and rr.randf() < float(op.get("trait_odds", 0.5)):    # a stranger may come with a trait of their own
		op = op.duplicate()
		op["trait"] = (op.traits as Array)[rr.randi() % (op.traits as Array).size()]
	if op.has("hurt_odds") and rr.randf() >= float(op.hurt_odds):
		op = op.duplicate()
		op["hurt"] = 0
	if op.has("trait") and defs.has(String(op.trait)):
		arc.person_traits[nm2] = (arc.person_traits.get(nm2, []) as Array) + ([String(op.trait)] if not has(nm2, String(op.trait)) else [])
	var rc: Dictionary = people._make_recruit(who)
	people.recruits.append(rc)
	people.rescued += 1
	var m: Dictionary = people._spawn_one(rc, people.recruits.size())
	if game.entities != null and not m.has("node"):
		game._add_member_node(m)
	if int(op.get("hurt", 0)) > 0:
		arc.hurt[nm2] = arc.day + int(op.hurt) - 1
	ctx["name"] = nm2
	ctx.lines.append("%s joins as %s (%s)" % [nm2, String(rc.role).to_lower(), trait_text(nm2).to_lower()])
	return true
