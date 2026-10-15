## EXPERIMENT (prison management, step 1): the ECONOMY CORE. Resources and caps, projects with tiers, labor, daily production and upkeep, morale and leaving, stage rules. Every number is in
## assets/data/prison_projects.json; this file only runs it. Owned by prison_game.gd (`econ`, made beside `siege`, kept over raids). It acts only while game.phase == "managed".
## Pattern: plain data (the JSON, read once into dictionaries) and one RefCounted that owns the state, with its own signals. A custom Resource per project was rejected (the spec wants one JSON
## file the tuning pass edits, and a project has only a state word and a number); an event-bus autoload and a state machine were rejected (one owner, four listeners that connect to this object;
## a project's state is a word that is a function of three facts: built, labor done, requirements).
##
## API (stable; the UI, world and raid agents build on it):
##   projects(building := "") -> Array of {id, building, tier, name, cost, labor, role, requires (all ids needed), effect, state, done, why}   state(id) -> "locked"|"available"|"queued"|"building"|"built"
##   can_start(id) -> {ok, why, missing {res: n}}     start(id) -> bool (spends the cost from game.stores and queues the work)
##   tier(building) -> int (0 = nothing built)        stage() -> "Camp"|"Shelter"|"Settlement"|"Fortress"|"Hub"      caps() -> {res: cap}      beds() -> {used, cap, free}
##   daily_report() -> {day, stage, morale, people, beds, power_on, res {food|water|fuel: {stock, prod, cons, net, days}}, next_shortage {res, days} ({} if none), last {spoiled, lost, left, short}}
##   needs() -> {res, days, short, place, reason}  (the biggest shortage and the place type that fixes it; {} when all is well)
##   site(id) -> Vector2 (where the work is done)      add_labor(id, secs)  (the world agent calls it from the crew's work stop; then set `fallback_labor = false`)
##   fence_mult() -> float (siege fence hp)            hit_bonus() -> float (guards' hit chance at night, floodlights)
## Signals: project_done(id), stage_changed(stage), person_left(name), shortage(resource).
## Hooks: prison_game.gd (`# ECON hook`), prison_siege.gd `apply_fence`, prison_crew.gd `econ_owned` (food and water are this file's, not the crew stops').
## Lab: `--econ-lab[=days]` (see `lab`), `--econ=start:water2` (debug: build a project at once).
extends RefCounted

signal project_done(id: String)
signal stage_changed(stage: String)
signal person_left(name: String)
signal shortage(resource: String)

const PATH := "res://assets/data/prison_projects.json"
const RES := ["food", "water", "ammo", "meds", "scrap", "parts", "fuel"]

var game
var cfg: Dictionary = {}
var defs: Dictionary = {}    # id -> project definition (with role and the full requires list)
var order: Array = []    # ids in file order
var st: Dictionary = {}    # id -> {"done": labor seconds, "built": bool}   (present = started)
var queue: Array = []    # ids started and not built, in start order
var day := 1
var morale := 55.0
var power_on := false
var fallback_labor := true    # labor comes by itself while a crew member with the role is alive; the world agent sets false when crew stops call add_labor
var rate_cb: Callable    # WORLD hook: how many people work a project now (prison_upgrades.gd `workers_on`), for the ETA
var native_roles: Dictionary = {}    # crew id -> the role their route was made for (the roster can change cfg.crew_role)
var _stage := "Camp"
var _last_tod := -1.0
var _roster: Array = []
var _streak := {"food": 0, "water": 0}
var last := {"spoiled": 0.0, "lost": 0.0, "left": "", "short": {}}
## UNDO: the last project ordered can be taken back, with a full refund, for `UNDO_S` game seconds.
const UNDO_S := 30.0
var undo_id := ""
var undo_left := 0.0
## MORNING: what the last day change did, for the morning card ({day, ate, made, built (names), spoiled}); `morning_new` is set by the day change and cleared by whoever shows the card.
var dawn_log := {}
var morning_new := false
var _built_today: Array = []


func _init(g) -> void:
	game = g
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	cfg = parsed if parsed is Dictionary else {}
	var roles: Dictionary = cfg.get("building_role", {})
	for p in cfg.get("projects", []):
		var d: Dictionary = (p as Dictionary).duplicate(true)
		d["role"] = String(roles.get(d.building, ""))
		var req: Array = []
		if int(d.tier) > 1:
			req.append("%s%d" % [d.building, int(d.tier) - 1])
		req.append_array(d.get("requires", []))
		d["requires"] = req
		defs[String(d.id)] = d
		order.append(String(d.id))
	morale = float(cfg.start.morale)
	native_roles = (cfg.get("crew_role", {}) as Dictionary).duplicate()


func active() -> bool:
	return game != null and game.phase == "managed"


# ------------------------------------------------------------------ people ------

## The crew as [{id, name, role (econ role), ok (on its feet), guard, kid}], kids included. While the crew is not in the scene (a raid) the last roster is used.
func crew() -> Array:
	if game != null and game.crew != null:
		var roles: Dictionary = cfg.crew_role
		_roster = []
		for m in game.crew.members:
			if m.def.has("ally"):
				continue    # the clear phase's party is not the base's people
			_roster.append({"id": String(m.def.id), "name": String(m.def.name), "role": String(roles.get(String(m.def.id), "")), "ok": not m.has("down") and String(m.state) != "downed" and not (game.arc != null and game.arc.hurt_now(String(m.def.name))), "guard": m.def.has("stand"), "kid": m.def.has("play")})
	var out: Array = game.squad.out_ids() if game != null and game.squad != null else []    # SQUAD hook: the companions of a raid are not at work
	if out.is_empty():
		return _roster
	var shown: Array = []
	for r in _roster:
		var e: Dictionary = (r as Dictionary).duplicate()
		if out.has(String(e.id)):
			e["ok"] = false
			e["out"] = true
		shown.append(e)
	return shown


## Everybody who eats and sleeps here: the crew and Ruth (`start.ruth`; not with `--crew=full`, the old 17-person start).
func people() -> int:
	return crew().size() + (0 if game.crew_full() else int(cfg.start.ruth))


func workers(role: String) -> int:
	var n := 0
	for c in crew():
		if c.ok and String(c.role) == role:
			n += 1
	return n


# ---------------------------------------------------------------- projects ------

func tier(building: String) -> int:
	var t := 0
	for id in order:
		var d: Dictionary = defs[id]
		if d.building == building and bool(st.get(id, {}).get("built", false)):
			t = maxi(t, int(d.tier))
	return t


func _built(id: String) -> bool:
	return bool(st.get(id, {}).get("built", false))


func state(id: String) -> String:
	if not defs.has(id):
		return "locked"
	if _built(id):
		return "built"
	if st.has(id):
		return "building" if float(st[id].done) > 0.0 else "queued"
	for r in defs[id].requires:
		if not _built(String(r)):
			return "locked"
	return "available"


func projects(building: String = "") -> Array:
	var out: Array = []
	for id in order:
		var d: Dictionary = defs[id]
		if building != "" and d.building != building:
			continue
		var e: Dictionary = d.duplicate(true)
		e["state"] = state(id)
		e["done"] = float(st.get(id, {}).get("done", 0.0))
		e["why"] = String(can_start(id).why)
		out.append(e)
	return out


func can_start(id: String) -> Dictionary:
	if not defs.has(id):
		return {"ok": false, "why": "no such project", "missing": {}}
	var d: Dictionary = defs[id]
	var s := state(id)
	if s == "built":
		return {"ok": false, "why": "already built", "missing": {}}
	if s == "queued" or s == "building":
		return {"ok": false, "why": "already under way", "missing": {}}
	for r in d.requires:
		if not _built(String(r)):
			return {"ok": false, "why": "needs %s" % String(defs[String(r)].name), "missing": {}}
	var miss := {}
	for k in d.cost:
		var short: float = float(d.cost[k]) - float(game.stores.get(k, 0.0))
		if short > 0.001:
			miss[k] = ceili(short)
	if not miss.is_empty():
		var parts: Array = []
		for k in miss:
			parts.append("%d %s" % [int(miss[k]), k])
		return {"ok": false, "why": "missing " + ", ".join(parts), "missing": miss}
	if workers(String(d.role)) == 0:
		return {"ok": false, "why": "nobody with the %s role" % d.role, "missing": {}}
	return {"ok": true, "why": "", "missing": {}}


func start(id: String) -> bool:
	if not active() or not bool(can_start(id).ok):
		return false
	for k in defs[id].cost:
		game.stores[k] = float(game.stores[k]) - float(defs[id].cost[k])
	_queue(id)
	undo_id = id
	undo_left = UNDO_S
	return true


## Takes back the last order while the undo window is open: the whole cost comes back and the project is as if never started.
func can_undo() -> bool:
	return undo_id != "" and undo_left > 0.0 and st.has(undo_id) and not _built(undo_id)


func undo_start() -> bool:
	if not can_undo():
		return false
	for k in defs[undo_id].cost:
		game.stores[k] = float(game.stores.get(k, 0.0)) + float(defs[undo_id].cost[k])
	st.erase(undo_id)
	queue.erase(undo_id)
	undo_id = ""
	undo_left = 0.0
	return true


func _queue(id: String) -> void:
	st[id] = {"done": 0.0, "built": false}
	queue.append(id)


## Debug: build a project at once for free (`--econ=start:water2`), with the tiers below it.
func debug_build(id: String) -> void:
	if not defs.has(id) or _built(id):
		return
	for r in defs[id].requires:
		debug_build(String(r))
	st[id] = {"done": 0.0, "built": false}
	_finish(id)


func site(id: String) -> Vector2:
	var name := String(cfg.site.get(String(defs[id].building), "stores")) if defs.has(id) else "stores"
	return game.base.stations.get(name, Vector2(30.0, 38.0)) if game != null and game.base != null else Vector2(30.0, 38.0)


func add_labor(id: String, secs: float) -> void:
	if not st.has(id) or _built(id):
		return
	st[id].done = float(st[id].done) + secs
	if float(st[id].done) >= float(defs[id].labor):
		_finish(id)


## Game hours until a started project is built at the present number of workers (one when nobody is there yet).
func eta_h(id: String) -> float:
	if not st.has(id) or _built(id):
		return 0.0
	var n := 1
	if rate_cb.is_valid():
		n = maxi(1, int(rate_cb.call(id)))
	return maxf(0.0, float(defs[id].labor) - float(st[id].done)) / float(n) * 24.0 / float(cfg.day_secs)


func _finish(id: String) -> void:
	st[id].built = true
	queue.erase(id)
	_built_today.append(String(defs[id].name))
	var old := _stage
	project_done.emit(id)
	_stage = _calc_stage()
	if _stage != old:
		stage_changed.emit(_stage)


## Fallback labor: each role with a living worker advances its first queued projects, one per worker, in real game seconds.
func _labor(dt: float) -> void:
	var left := {}
	for id in queue.duplicate():
		var role := String(defs[id].role)
		if not left.has(role):
			left[role] = workers(role)
		if int(left[role]) > 0:
			left[role] = int(left[role]) - 1
			add_labor(id, dt)


# --------------------------------------------------------------- the numbers ------

func caps() -> Dictionary:
	var c: Dictionary = (cfg.caps as Dictionary).duplicate()
	for id in order:
		if _built(id):
			var add: Dictionary = defs[id].effect.get("cap", {})
			for k in add:
				c[k] = float(c.get(k, 0.0)) + float(add[k])
	return c


func beds() -> Dictionary:
	var cap: int = int(cfg.start.full_beds) if game.crew_full() else int(cfg.start.beds)
	for id in order:
		if _built(id):
			cap += int(defs[id].effect.get("beds", 0))
	var used := people()
	return {"used": used, "cap": cap, "free": cap - used}


func _spoil_rate() -> float:
	var r: float = float(cfg.spoil.food)
	for id in order:
		if _built(id) and defs[id].effect.has("spoil"):
			r *= float(defs[id].effect.spoil)
	if game.cleaner != null:
		r *= game.cleaner.spoil_mult()    # TRASH hook: rubbish at the kitchen
	return r


func fence_mult() -> float:
	var m := 1.0
	for id in order:
		if _built(id):
			m = maxf(m, float(defs[id].effect.get("fence", 1.0)))
	return m


func hit_bonus() -> float:
	return float(cfg.light_hit_bonus) if tier("power") >= 1 and power_on and not game.arc.blackout() else 0.0    # (ARC hook: the storm night is dark)


## Production of one resource per day by what is built and who is at work. `power` says whether the generator runs.
func _produce(r: String, power: bool) -> float:
	var list: Array = cfg.production[r]
	var t := mini(tier(String(cfg.production_building[r])), list.size() - 1)
	var e: Dictionary = list[t]
	if bool(e.get("power", false)) and not power:
		t -= 1
		e = list[t]
	var amt: float = float(e.amt) if workers(String(cfg.production_role[r])) > 0 else float(e.get("none", 0.0))
	return amt + float(e.get("passive", 0.0))


func _consume(r: String) -> float:
	var n: float = float(people()) * float(cfg.per_person[r])
	if r == "food" and game.arc != null:
		n += game.arc.extra_eating()    # TRAITS hook: scroungers eat more
	n *= float(game.Bal.dm("drain"))
	return n


func _fuel_burn() -> float:
	return float(cfg.generator_fuel) if tier("power") >= 1 else 0.0


func _power_now() -> bool:
	return tier("power") >= 1 and float(game.stores.get("fuel", 0.0)) >= _fuel_burn()


## What the next day change would do, per resource.
func _flows(power: bool) -> Dictionary:
	var out := {}
	for r in ["food", "water"]:
		var prod := _produce(r, power)
		var cons := _consume(r)
		var spoil := float(game.stores.get(r, 0.0)) * _spoil_rate() if r == "food" else 0.0
		out[r] = {"prod": prod, "cons": cons, "spoil": spoil, "net": prod - cons - spoil}
	out["fuel"] = {"prod": 0.0, "cons": _fuel_burn(), "spoil": 0.0, "net": -_fuel_burn()}
	return out


func daily_report() -> Dictionary:
	var f := _flows(_power_now())
	var res := {}
	var nxt := {}
	for r in f:
		var stock: float = float(game.stores.get(r, 0.0))
		var days := -1.0 if float(f[r].net) >= -0.001 else stock / -float(f[r].net)
		res[r] = {"stock": stock, "prod": f[r].prod, "cons": f[r].cons, "net": f[r].net, "days": days}
		if days >= 0.0 and (nxt.is_empty() or days < float(nxt.days)) and float(f[r].cons) > 0.0:
			nxt = {"res": r, "days": days}
	return {"day": day, "stage": _stage, "morale": morale, "people": people(), "beds": beds(), "power_on": _power_now(), "res": res, "next_shortage": nxt, "last": last}


func stage() -> String:
	return _stage


func _calc_stage() -> String:
	var name := "Camp"
	for s in cfg.stages:
		for b in s.tiers:
			if tier(String(b)) < int(s.tiers[b]):
				return name
		name = String(s.name)
	return name


# --------------------------------------------------------------------- needs ------

## The biggest shortage and the kind of place that fixes it. Food and water first (days of stock left under `critical_days`), then the stock the cheapest open project lacks, then the low ones.
func needs() -> Dictionary:
	var rep := daily_report()
	var crit: float = float(cfg.needs.critical_days)
	var worst := {}
	for r in ["food", "water"]:
		var e: Dictionary = rep.res[r]
		if float(e.days) >= 0.0 and float(e.days) < crit and (worst.is_empty() or float(e.days) < float(worst.days)):
			worst = {"res": r, "days": e.days, "short": ceilf(-float(e.net) * crit - float(e.stock))}
	if worst.is_empty():
		var path := goal()
		if path.is_empty() and _next_project() != "":
			path = [_next_project()]
		var total := {}
		for id in path:
			for k in defs[id].cost:
				total[k] = float(total.get(k, 0.0)) + float(defs[id].cost[k])
		var best_short := 0.0
		for k in total:
			var sh: float = float(total[k]) - float(game.stores.get(k, 0.0))
			if sh > best_short:
				best_short = sh
				var for_id := ""
				for id in path:
					if defs[id].cost.has(k):
						for_id = id
						break
				worst = {"res": k, "days": -1.0, "short": ceilf(sh), "for": for_id}
	if worst.is_empty():
		for r in ["food", "water"]:
			var e2: Dictionary = rep.res[r]
			if float(e2.days) >= 0.0 and (worst.is_empty() or float(e2.days) < float(worst.days)):
				worst = {"res": r, "days": e2.days, "short": ceilf(-float(e2.net) * 5.0)}
	if worst.is_empty():
		for r in cfg.needs.low:
			if float(game.stores.get(r, 0.0)) < float(cfg.needs.low[r]):
				worst = {"res": r, "days": -1.0, "short": ceilf(float(cfg.needs.low[r]) * 2.0 - float(game.stores.get(r, 0.0)))}
				break
	if worst.is_empty():
		return {}
	worst["place"] = String(cfg.fixes.get(worst.res, "house"))
	worst["reason"] = "%s %s" % [String(worst.res), ("lasts %.1f days" % float(worst.days)) if float(worst.days) >= 0.0 else ("short by %d%s" % [int(worst.short), (" for " + String(defs[worst["for"]].name)) if worst.has("for") else ""])]
	return worst


## The project the player is saving for: the cheapest one whose requirements are built (not under way).
func _next_project() -> String:
	var best := ""
	var bc := 1.0e9
	for id in order:
		if state(id) != "available":
			continue
		var c := 0.0
		for k in defs[id].cost:
			c += float(defs[id].cost[k])
		if c < bc:
			bc = c
			best = id
	return best


# ------------------------------------------------------------------ the day ------

## Called every frame by the game: the fallback labor, and the day change at `day_change_h` (dawn).
func update(dt: float) -> void:
	if not active():
		_last_tod = -1.0
		return
	if undo_left > 0.0:
		undo_left -= dt
		if undo_left <= 0.0:
			undo_id = ""
	if fallback_labor:
		_labor(dt)
	var tod: float = game.tod
	var h: float = float(cfg.day_change_h)
	if _last_tod >= 0.0 and _last_tod < h and tod >= h and tod - _last_tod < 12.0:
		tick_day()
	_last_tod = tod


func tick_day() -> void:
	day += 1
	var s: Dictionary = game.stores
	power_on = _power_now()
	var f := _flows(power_on)
	var short := {}
	for r in ["food", "water"]:
		var have: float = float(s.get(r, 0.0)) + float(f[r].prod)
		var need: float = float(f[r].cons)
		if have >= need:
			s[r] = have - need
			_streak[r] = 0
		else:
			s[r] = 0.0
			short[r] = (need - have) / maxf(need, 0.001)
			_streak[r] = int(_streak[r]) + 1
			shortage.emit(r)
	if tier("power") >= 1:
		if power_on:
			s["fuel"] = float(s.get("fuel", 0.0)) - _fuel_burn()
		else:
			shortage.emit("fuel")
	var spoiled: float = float(s.food) * _spoil_rate()
	s["food"] = float(s.food) - spoiled
	var lost := 0.0
	var cp := caps()
	for r in cp:
		if float(s.get(r, 0.0)) > float(cp[r]):
			lost += float(s[r]) - float(cp[r])
			s[r] = float(cp[r])
	if game.cleaner != null:
		game.cleaner.daily()    # TRASH hook: a dirty dormitory makes someone ill
	dawn_log = {"day": day, "ate": {"food": float(f.food.cons), "water": float(f.water.cons)}, "made": {"food": float(f.food.prod), "water": float(f.water.prod)}, "built": _built_today.duplicate(), "spoiled": spoiled}
	_built_today.clear()
	morning_new = true
	_morale(short)
	last = {"spoiled": spoiled, "lost": lost, "left": last.left, "short": short}
	_leave()
	if game.args.has("log"):
		print("ECON day ", day, " stage ", _stage, " stores ", game.stores, " morale ", snappedf(morale, 0.1), " people ", people(), " short ", short, " fence hp ", game.siege.segs[0].max)


func _morale(short: Dictionary) -> void:
	var m: Dictionary = cfg.morale
	var d := 0.0
	for r in ["food", "water"]:
		if short.has(r):
			d -= float(m.shortage[r]) * float(short[r]) * (1.0 + float(m.streak_gain) * float(int(_streak[r]) - 1))
	var crit: float = float(cfg.needs.critical_days)    # worry: less than `critical_days` of food or water left at the going rate
	var rep := daily_report()
	var worried := false
	for r in ["food", "water"]:
		var days: float = float(rep.res[r].days)
		if days >= 0.0 and days < crit:
			d -= float(m.worry) * (1.0 - days / crit)
			worried = true
	if short.is_empty() and not worried:
		d += float(m.recover)
	for b in m.building:
		var role := String(cfg.building_role[b])
		if workers(role) > 0:
			var bon := float(m.building[b][mini(tier(String(b)), (m.building[b] as Array).size() - 1)])
			d += bon * (1.2 if game.arc != null and game.arc.count_trait("pacifist", role) > 0 else 1.0)    # TRAITS hook: a pacifist cook or medic does the job 20% better
	if people() > int(beds().cap):
		d -= float(m.overcrowd)
	if game.arc != null:
		d += game.arc.calm()    # TRAITS hook: veterans
	if game.cleaner != null:
		d += game.cleaner.morale_delta()    # TRASH hook: piles drag, a tidy base lifts
	morale = clampf(morale + d, 0.0, float(m.max))


## Morale under the limit: one person leaves in the night, never in a siege. The one the base misses least goes first: nobody's job (no role, cleaners), then a worker whose role has
## another worker, then a patrol guard, then a tower guard, then the only worker of a building; kids are the very last.
func _leave() -> void:
	last.left = ""
	if morale >= float(cfg.morale.leave_below) or people() <= int(cfg.morale.keep_min) or game.siege.attacking:
		return
	var best = next_leaver()
	if best != null:
		last.left = String(best.name)
		_roster.erase(best)
		person_left.emit(String(best.name))


## The person the base misses least (null for nobody): the one who goes first when morale is under the limit.
func next_leaver():
	var c := crew().duplicate()
	var cnt := {}
	for p in c:
		if p.ok and not p.kid:
			cnt[String(p.role)] = int(cnt.get(String(p.role), 0)) + 1
	var best = null
	var bs := 99
	for i in range(c.size() - 1, -1, -1):    # (the later ones first on a tie, as before)
		var p: Dictionary = c[i]
		var r := String(p.role)
		var sc := 5
		if p.kid:
			sc = 9
		elif r == "" or r == "cleaner":
			sc = 0
		elif r != "guard" and int(cnt.get(r, 0)) >= 2:
			sc = 1
		elif r == "guard" and not p.guard:
			sc = 2
		elif r == "guard":
			sc = 3
		else:
			sc = 4
		if sc < bs:
			bs = sc
			best = p
	return best


# ---------------------------------------------------------------------- lab ------
## `--econ-lab[=days]` (default 10) with `--managed`: the economy runs on its own clock (30 game seconds a frame, the real crew stays at work) and prints one line a day: stores after the day
## change, production and consumption of food and water, morale, people and beds, stage. Then a scripted raid (`--econ-raid=0` turns it off) adds the loot of the place that needs() names, and a
## scripted spender buys the cheapest available project (not the dormitory while beds are free, not the radio before the Fortress) until nothing is affordable.
const LAB_STEP := 30.0
var _lab_t := 0.0
var _lab_days := 0
var _lab_log: Array = []


func lab(dt: float) -> void:
	if _lab_days == 0:
		_lab_days = maxi(int(game.args.get("econ-lab", "10")), 2) if int(game.args.get("econ-lab", "10")) > 1 else 10
		stage_changed.connect(func(s): _lab_log.append("STAGE " + s))
		project_done.connect(func(id): _lab_log.append("built " + id))
		person_left.connect(func(n): _lab_log.append("LEFT " + String(n)))
		_lab_row("start")
		_lab_play()
	_lab_t += LAB_STEP
	_labor(LAB_STEP)
	if _lab_t >= float(cfg.day_secs):
		_lab_t = 0.0
		tick_day()
		_lab_row("d%d" % day)
		_lab_play()
		if day > _lab_days:
			print("ECONLAB done")
			game.get_tree().quit()


func _lab_play() -> void:
	var place := ""
	if String(game.args.get("econ-raid", "1")) != "0":
		var nd := needs()
		place = String(nd.get("place", "house"))
		var loot: Dictionary = cfg.loot.get(place, {})
		for k in loot:
			game.stores[k] = float(game.stores.get(k, 0.0)) + float(loot[k])
	if String(game.args.get("econ-rescue", "1")) != "0" and day % 2 == 0:    # (fix round 3: a rescue on every other raid; `--econ-rescue=0` for none)
		var who: String = game.people.lab_rescue(day * 131 + 7)
		if who != "":
			_lab_log.append("rescued " + who)
	var bought: Array = []
	while true:
		var want := goal()    # the next stage's missing tiers come first, then anything else that is affordable
		var best := ""
		var bc := 1.0e9
		for id in order:
			if not bool(can_start(id).ok):
				continue
			var b: String = defs[id].building
			var on_path: bool = want.has(id)
			if not on_path and (b == "radio" or b == "convoy" or (b == "dormitory" and int(beds().free) > 2) or not want.is_empty()):
				continue
			var c := 0.0
			for k in defs[id].cost:
				c += float(defs[id].cost[k])
			if c < bc:
				bc = c
				best = id
		if best == "" or not start(best):
			break
		bought.append(best)
	print("  raid %-9s bought %s" % [place, ", ".join(bought)])


## The project ids still missing for the next stage (the tiers of its rules, every tier below included): what the player should be saving for.
func goal() -> Array:
	var out: Array = []
	for st_i in cfg.stages:
		for b in st_i.tiers:
			for t in range(1, int(st_i.tiers[b]) + 1):
				_need(out, "%s%d" % [b, t])
		if not out.is_empty():
			return out
	return out


func _need(out: Array, id: String) -> void:
	if _built(id) or out.has(id):
		return
	for r in defs[id].requires:
		_need(out, String(r))
	out.append(id)


## ARC hook: the day model's progress on the lab's line: "Day 12 of 30", the convoy's list ready so far, the night's size.
func _lab_arc() -> String:
	if game.arc == null or not game.arc.started:
		return ""
	var rq: Array = game.arc.requirements()
	var ok := 0
	var must := 0
	for r in rq:
		if bool(r.must):
			must += 1
			ok += 1 if bool(r.ok) else 0
	return "   [day %d of %d, convoy list %d/%d, next night %d dead]" % [game.arc.day, game.arc.days(), ok, must, int(game.arc.wave_plan(game.arc.day).total)]


func _lab_row(tag: String) -> void:
	var r := daily_report()
	var s: Dictionary = game.stores
	print("%-3s %-10s F%4d W%4d S%4d P%3d Fu%3d M%2d | prod F%2d W%2d cons F%2d W%2d | morale %3d people %2d beds %2d | %s" % [tag, _stage, s.food, s.water, s.scrap, s.get("parts", 0), s.get("fuel", 0), s.meds, r.res.food.prod, r.res.water.prod, r.res.food.cons, r.res.water.cons, morale, people(), beds().cap, ", ".join(_lab_log)] + _lab_arc())
	_lab_log.clear()


## SAVE hook (prison_save.gd): what the economy keeps from day to day. The projects' definitions are the JSON's; only progress is saved.
func to_dict() -> Dictionary:
	return {"day": day, "morale": morale, "power_on": power_on, "st": st.duplicate(true), "queue": queue.duplicate(), "streak": _streak.duplicate(), "crew_role": (cfg.crew_role as Dictionary).duplicate(),
		"native_roles": native_roles.duplicate(), "last": last.duplicate(true)}


## Puts a saved economy back (before the base is built). A project the data no longer knows is dropped.
func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	morale = float(d.get("morale", morale))
	power_on = bool(d.get("power_on", false))
	st = {}
	for id in (d.get("st", {}) as Dictionary):
		if defs.has(String(id)):
			var e: Dictionary = d.st[id]
			st[String(id)] = {"done": float(e.get("done", 0.0)), "built": bool(e.get("built", false))}
	queue = []
	for id in (d.get("queue", []) as Array):
		if st.has(String(id)) and not bool(st[String(id)].built):
			queue.append(String(id))
	for k in (d.get("streak", {}) as Dictionary):
		_streak[String(k)] = int(d.streak[k])
	for k in (d.get("crew_role", {}) as Dictionary):
		cfg.crew_role[String(k)] = String(d.crew_role[k])
	for k in (d.get("native_roles", {}) as Dictionary):
		native_roles[String(k)] = String(d.native_roles[k])
	var l: Dictionary = d.get("last", {})
	last = {"spoiled": float(l.get("spoiled", 0.0)), "lost": float(l.get("lost", 0.0)), "left": String(l.get("left", "")), "short": l.get("short", {})}
	_stage = _calc_stage()    # (no signal: nobody is told of a stage that was reached before the save)
	_last_tod = float(game.tod)
