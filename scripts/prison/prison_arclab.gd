## EXPERIMENT (prison round 12): the 30-day LAB, `--arcauto[=passive|average|expert] [--seed=N] [--arcdays=N] --managed`. One frame is one day of a scripted player: it raids (the REAL loot model: a generated town, a kind of town chosen by shortage from the kinds on offer, prison_loot.gd's retag and rolls and its greedy 180 s walk; the pack limit is not modelled), spends on the projects the arc needs, mends the fence, rescues people now and then, and the night is resolved by a small model
## (the table's dead against the guards' fire, the fence's hit points and the ammo, numbers in prison_story.json `lab`). The economy, the arc, the story and the endings are the real code; only
## the raid and the night are stand-ins (the night model was set against `--siege=N` runs, see docs/experiments/prison-story.md). Prints one line a day and one `ARCLAB RESULT` line.
## A batch: `for s in 1 2 3 4 5 6 7 8; do Godot --headless --path . --fixed-fps 60 -- --prison --managed --arcauto=average --seed=$s | grep "ARCLAB RESULT"; done`.
extends RefCounted

const Crew := preload("res://scripts/prison/prison_crew.gd")
const Loot := preload("res://scripts/prison/prison_loot.gd")

var game
var arc
var econ
var cfg: Dictionary = {}
var skill: Dictionary = {}
var skill_name := "average"
var rng := RandomNumberGenerator.new()
var _init_done := false
var _days_max := 31
var _names: Array = []
var _recruited := 0
var _log: Array = []
var _final_night_done := false
var _towns := {}    # town seed -> generated town (the generator is the slow part)


func _init(a) -> void:
	arc = a
	game = a.game
	econ = game.econ
	cfg = a.cfg.lab
	skill_name = String(game.args.get("arcauto", "average"))
	if skill_name == "1" or not cfg.skills.has(skill_name):
		skill_name = "average"
	skill = cfg.skills[skill_name]
	rng.seed = int(game.args.get("seed", "1"))
	_days_max = int(game.args.get("arcdays", "31"))
	var raids = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/prison_raids.json"))
	for p in raids.people:
		_names.append(p)


func step(_dt: float) -> void:
	if arc.ended_id != "":
		return
	if not arc.started:
		return
	if not _init_done:
		_setup()
		return
	if int(econ.day) > _days_max:
		_finish("time")
		return
	_one_day()


func _setup() -> void:
	_init_done = true
	econ.person_left.connect(func(nm): game._econ_remove(String(nm)))    # no frames run: the walk to the gate is skipped
	var keep := ["cole", "bea", "ike", "hal", "wren"]
	var n_keep := int(cfg.start_people)
	var kept := 0
	for m in game.crew.members.duplicate():
		var id := String(m.def.id)
		if keep.has(id) and kept < n_keep:
			kept += 1
		else:
			game._econ_remove(String(m.def.name))
	var s: Dictionary = cfg.start_stores
	for k in s:
		game.stores[k] = float(s[k])
	arc.ever.clear()
	arc.stats.peak_people = 0
	arc._track_people()
	print("ARCLAB start skill=%s seed=%s people=%d" % [skill_name, str(game.args.get("seed", "1")), econ.people()])


# ----------------------------------------------------------------------------------- a day --

func _one_day() -> void:
	var d: int = econ.day
	var sk := skill
	var raids_n := int(floor(float(sk.raids))) + (1 if rng.randf() < float(sk.raids) - floor(float(sk.raids)) else 0)
	var got := {}
	for r in raids_n:
		_raid(got)
		if arc.ended_id != "":
			return
	_assign()
	_mend(float(sk.mend))
	_spend(float(sk.spend))
	_ammo()
	for i in 12:    # the crew's work through the day
		econ._labor(30.0)
	if d == arc.convoy_day():
		_convoy()
		if arc.ended_id != "":
			return
	_night(d)
	if arc.ended_id != "":
		return
	var before := int(econ.day)
	econ.tick_day()
	game.tod = 6.5
	arc.frame(1.0)
	arc.frame(1.0)
	_row(d)
	if arc.ended_id == "" and int(econ.day) > arc.convoy_day() and arc.convoy != "left":
		_finish("held")


func _raid(got: Dictionary) -> void:
	var sk := skill
	var pick := _pick_raid()
	var pc: Dictionary = Loot.place_cfg(String(pick.kind))
	game.stores["fuel"] = maxf(0.0, float(game.stores.get("fuel", 0.0)) - float(pc.get("fuel", 0)))
	var dead := rng.randf() < float(cfg.raid_death_p) * float(pc.get("danger", 2.5)) / 2.5    # (a deadlier place kills more often)
	arc.stats.raids = int(arc.stats.raids) + 1
	if dead:
		arc.stats.ruth_deaths = int(arc.stats.ruth_deaths) + 1
		if int(arc.stats.ruth_deaths) >= int(game.Bal.dm("ruth_deaths", arc.cfg.rules.ruth_deaths)):
			arc.end("dead")
		return
	# the REAL loot model: a generated town, retagged and re-rolled by prison_loot.gd for the chosen kind, and the loot lab's greedy 180 s walk (a stand-in for the hands: no fights, no pack limit)
	var ts := rng.randi_range(1, 40)
	var tk := "%d:%s" % [ts, String(pick.kind)]
	if not _towns.has(tk):
		_towns[tk] = Loot.make_town(ts, String(pick.kind))    # (RAID SITES: the place's own map when it has one)
	var t: Dictionary = _towns[tk]
	var pls := Loot.prepare(t, rng.randi() & 0x7fffffff, String(pick.kind))
	var found: Dictionary = Loot._sim_raid(t, pls, pick.types)
	if game.args.has("arcraids"):
		print("RAID D%02d kind %s hunt %s found %s" % [int(econ.day), String(pick.kind), str(pick.types), str(found)])
	for k in found:
		if not game.stores.has(k):
			continue    # (distractions, guns)
		var v := float(found[k]) * float(sk.loot)
		game.stores[k] = float(game.stores.get(k, 0.0)) + v
		got[k] = float(got.get(k, 0.0)) + v
		if k == "scrap":
			arc.stats.scrap = float(arc.stats.scrap) + v
	game.stores["ammo"] = float(game.stores.ammo) - float(cfg.raid_ammo)
	if rng.randf() < float(arc.cfg.letter_chance):
		arc.next_letter()
	if rng.randf() < float(sk.rescue_p) and int(econ.beds().free) > 0:
		_recruit()
	arc.stats.kills = int(arc.stats.kills) + int(cfg.raid_kills)


## The gate's choice of a bot: the biggest shortage decides the resource; of the kinds on offer today the one that answers the shortages best, else the plain town; the option that hunts the resource.
func _pick_raid() -> Dictionary:
	var rep: Dictionary = econ.daily_report()
	var need := _needs()
	var sh := {}
	for r in ["food", "water"]:
		var days := float(rep.res[r].days)
		sh[r] = (4.0 - days) * 30.0 if days >= 0.0 and days < 4.0 else (20.0 if float(game.stores[r]) < float(rep.res[r].cons) * 3.0 else 0.0)
	for r in ["fuel", "parts", "scrap", "meds", "ammo"]:
		sh[r] = (float(need.get(r, 0.0)) - float(game.stores.get(r, 0.0))) * (1.4 if r == "fuel" else 1.0) + (8.0 if r == "ammo" else 0.0)
	var kind := "standard"
	var best := 0.0
	for k in Loot.offer(int(econ.day)):    # (the places open today that the truck has the fuel for)
		if float(Loot.place_cfg(String(k)).get("fuel", 0)) > float(game.stores.get("fuel", 0.0)):
			continue
		var sc := 0.0
		for r in Loot.kind_cfg(String(k)).get("answers", []):
			sc += maxf(0.0, float(sh.get(String(r), 0.0)))
		if sc > best:
			best = sc
			kind = String(k)
	var want := ""
	var bs := 0.0
	var ans: Array = Loot.kind_cfg(kind).get("answers", [])
	for r in sh:
		if (ans.is_empty() or ans.has(r)) and float(sh[r]) > bs:
			bs = float(sh[r])
			want = String(r)
	var types: Array = Loot.cfg().options[0].types
	for o in Loot.cfg().options:
		if (o.res as Array).has(want):
			types = o.types
			break
	return {"kind": "" if kind == "standard" else kind, "types": types}


## What the base wants in stock now: the cost of the projects on the path, the convoy's list after day 8, a reserve of scrap and ammo.
func _needs() -> Dictionary:
	var need := {"scrap": 30.0, "ammo": maxf(60.0, 3.0 * float(arc.wave_plan(int(econ.day))["total"]) * float(cfg.night.ammo_per_kill)), "meds": 4.0}
	need["scrap"] = float(need.scrap) + maxf(0.0, float(need.ammo) - float(game.stores.ammo)) / 2.0    # the bench turns scrap into rounds
	var path := _path()
	for id in path:
		for k in econ.defs[id].cost:
			need[k] = float(need.get(k, 0.0)) + float(econ.defs[id].cost[k])
	if int(econ.day) >= int(cfg.arc_start_day):    # the list is on the tracker from day 3: the bot fetches the stock from the arc's start
		for r in arc.cfg.requirements:
			if String(r.kind) == "stock":
				need[String(r.res)] = float(need.get(String(r.res), 0.0)) + float(r.need)
		need["fuel"] = float(need.get("fuel", 0.0)) + econ._fuel_burn() * maxf(0.0, float(arc.convoy_day() - int(econ.day)))    # (the generator burns fuel every day until the convoy: a list met on day 28 fell short on day 30)
	return need


## The projects the bot works towards, in order: the stage's missing tiers, then the convoy's needs.
func _path() -> Array:
	var out: Array = econ.goal()
	if int(econ.day) >= int(cfg.arc_start_day):
		for id in ["power1", "radio1", "fence2", "convoy1"]:
			econ._need(out, id)
	if int(econ.beds().free) <= 1 and not out.has("dormitory1"):
		econ._need(out, "dormitory1")
	return out


func _spend(f: float) -> void:
	if f <= 0.0:
		return
	var path := _path()
	var chain := {}
	for id in ["power1", "radio1", "fence2", "convoy1"]:
		arc._chain(chain, id)
	var guard := 0
	while guard < 12:
		guard += 1
		var best := ""
		var bc := 1.0e9
		for id in path:
			if not bool(econ.can_start(String(id)).ok):
				continue
			var cost: Dictionary = econ.defs[id].cost
			if float(game.stores.scrap) - float(cost.get("scrap", 0.0)) < float(cfg.scrap_reserve) and String(id) != "water1":
				continue
			if int(econ.day) >= 18 and not chain.has(String(id)) and _breaks_stock(cost):
				continue    # (late, a project off the convoy's path must not eat the fuel and parts that are handed over)
			var c := 0.0
			for k in cost:
				c += float(cost[k])
			if c < bc:
				bc = c
				best = String(id)
		if best == "" or not econ.start(best):
			break


## True when paying `cost` would leave less than the convoy's stock requirement of a resource (fuel, parts).
func _breaks_stock(cost: Dictionary) -> bool:
	for r in arc.cfg.requirements:
		if String(r.kind) == "stock" and float(game.stores.get(String(r.res), 0.0)) - float(cost.get(String(r.res), 0.0)) < float(r.need):
			if float(cost.get(String(r.res), 0.0)) > 0.0:
				return true
	return false


## The player puts spare people on the wall: guards up to six (the towers' posts), one worker kept for every other job.
func _assign() -> void:
	if float(skill.spend) <= 0.0:
		return
	var want := mini(6, 2 + int(econ.day) / 4)
	var have: int = econ.workers("guard")
	var crew: Array = econ.crew()
	var cnt := {}
	for c in crew:
		cnt[String(c.role)] = int(cnt.get(String(c.role), 0)) + 1
	for c in crew:
		if have >= want:
			break
		var r := String(c.role)
		if bool(c.kid) or r == "guard" or int(cnt.get(r, 0)) <= 1:
			continue
		econ.cfg.crew_role[String(c.id)] = "guard"
		cnt[r] = int(cnt[r]) - 1
		have += 1


func _mend(f: float) -> void:
	var missing := 0.0
	for s in game.siege.segs:
		missing += float(s.max) - float(s.hp)
	var scrap_need := missing / 8.0 * f
	var spend := minf(scrap_need, float(game.stores.scrap))
	if spend <= 0.0:
		return
	var frac := (spend * 8.0) / maxf(1.0, missing)
	game.stores["scrap"] = float(game.stores.scrap) - spend
	for s in game.siege.segs:
		s.hp = minf(float(s.max), float(s.hp) + (float(s.max) - float(s.hp)) * frac)


## A mechanic at the bench turns scrap into rounds.
func _ammo() -> void:
	var want := float(_needs().ammo) - float(game.stores.ammo)
	if want > 0.0 and econ.workers("mechanic") > 0 and float(game.stores.scrap) > float(cfg.scrap_reserve):
		var k := minf(minf(float(cfg.bench_scrap), want / 2.0), float(game.stores.scrap) - float(cfg.scrap_reserve))
		game.stores["scrap"] = float(game.stores.scrap) - k
		game.stores["ammo"] = float(game.stores.ammo) + k * 2.0


func _recruit() -> void:
	var cnt := {}
	for m in econ.crew():
		cnt[String(m.role)] = int(cnt.get(String(m.role), 0)) + 1
	var pick := "hauler"
	var order := ["mechanic", "gardener", "guard", "medic", "cook", "guard", "hauler"]
	var bs := 1.0e9
	for r in order:
		var sc := float(cnt.get(r, 0)) * 10.0 + float(order.find(r)) * 0.1
		if sc < bs:
			bs = sc
			pick = r
	var who: Dictionary = _names[_recruited % _names.size()]
	_recruited += 1
	var nm := String(who.name) + ("" if _recruited <= _names.size() else str(_recruited))
	var sample: String = {"gardener": "marcus", "cook": "mia", "medic": "ana", "mechanic": "hector", "hauler": "owen", "guard": "june"}[pick]
	var route: Array = []
	for r in Crew.ROSTER:
		if String(r.id) == sample:
			for stop in r.route:
				if not bool(stop.get("chat", false)):
					route.append((stop as Dictionary).duplicate(true))
	var id := "r_" + nm.to_lower()
	econ.cfg.crew_role[id] = pick
	var def := {"id": id, "name": nm, "role": pick.capitalize(), "key": String(who.key), "look": who.look, "route": route, "recruit": true}
	if game.crew != null:
		var m: Dictionary = game.crew._make(def, Vector2(30.0, 38.0))
		game._add_member_node(m)


# ---------------------------------------------------------------------------------- night --

func _night(d: int) -> void:
	if not arc.is_horde_night(d):    # HORDES: a quiet night
		game.siege.night = d
		game.siege.nights_started = d
		arc.night_over(d, {"killed": 0, "lost": [], "crew": []})
		_log.append("night %d: quiet" % d)
		return
	var n: Dictionary = cfg.night
	var plan: Dictionary = arc.wave_plan(d)
	var guards: int = econ.workers("guard")
	var gf: float = game.siege.guard_factor(guards)    # (the real siege sends the table's dead times this, and the base horde too)
	var total := maxf(2.0, roundf(float(plan.total) * gf)) + float(game.noise.base_horde_size(d, gf))
	var fp := float(n.base_defense) + float(guards) * float(n.guard_kills) + float(n.ruth_kills) * float(skill.defense)
	if econ.tier("power") >= 1 and econ.power_on and not arc.blackout_for(d):
		fp *= 1.0 + float(n.light_bonus)
	var ammo_need := total * float(n.ammo_per_kill)
	var have := float(game.stores.ammo)
	if have < ammo_need:
		fp *= have / maxf(ammo_need, 1.0)
	game.stores["ammo"] = maxf(0.0, have - minf(have, ammo_need))
	var leak := maxf(0.0, total - fp)
	var killed := minf(total, fp)
	var segs: Array = game.siege.segs
	var live: Array = segs.filter(func(s): return float(s.hp) > 0.0)
	var k := mini(int(plan.segs), live.size())
	live.shuffle()
	var hit: Array = live.slice(0, k)
	var gaps := 0
	var lost: Array = []
	var dmg_each := (leak * float(n.hp_per_dead) + total * float(n.wear)) / maxf(1.0, float(k))
	for s in hit:
		s.hp = float(s.hp) - dmg_each
		if float(s.hp) <= 0.0:
			s.hp = 0.0
			gaps += 1
			lost.append(String(s.name))
	var open_now := 0
	for s in segs:
		if float(s.hp) <= 0.0:
			open_now += 1
	var crew_lost: Array = []
	for g in gaps:
		for v in econ.crew():
			if rng.randf() < float(n.casualty_p) and not crew_lost.has(String(v.name)):
				arc.kill(String(v.name), "night")
				crew_lost.append(String(v.name))
	game.siege.night = d
	game.siege.nights_started = d
	arc.night_over(d, {"killed": int(killed), "lost": lost, "crew": crew_lost})
	if open_now >= int(arc.cfg.rules.overrun.gaps):
		arc.end("overrun")
	_log.append("night %d: dead %d fire %d leak %d gaps %d lost %s" % [d, int(total), int(fp), int(leak), gaps, str(crew_lost)])


## Day 30 at noon: the convoy is at the gate; the bot goes when the list is complete.
func _convoy() -> void:
	game.tod = 11.5
	arc._convoy_hours()
	if arc.convoy == "here":
		arc.convoy_answer(arc.ready())


func _row(d: int) -> void:
	var reqs: Array = arc.requirements()
	var ok := 0
	var must := 0
	for r in reqs:
		if bool(r.must):
			must += 1
			if bool(r.ok):
				ok += 1
	var s: Dictionary = game.stores
	print("D%02d %-10s people %2d beds %2d morale %3d | F%3d W%3d A%3d S%3d P%3d Fu%3d M%2d | list %d/%d fence%d radio%d truck%d | %s" % [d, econ.stage(), econ.people() + 1, econ.beds().cap, econ.morale, s.food, s.water, s.ammo, s.scrap, s.parts, s.fuel, s.meds, ok, must, econ.tier("fence"), econ.tier("radio"), 1 if econ.tier("convoy") >= 1 else 0, _log[-1] if not _log.is_empty() else ""])


func _finish(why: String) -> void:
	if arc.ended_id == "":
		arc.end(arc.held_id() if why == "held" else "abandoned")
	_report()


func report_if_ended() -> void:
	if arc.ended_id != "":
		_report()


func _report() -> void:
	var st: Dictionary = arc.stats
	var ever_n: int = 1 + arc.ever.size()
	var alive: int = arc.endings.last_saved if arc.ended_id.begins_with("evac") else 1 + econ.people()
	var lst := 0
	for r in arc.requirements():
		if bool(r.must) and bool(r.ok):
			lst += 1
	print("ARCLAB RESULT skill=%s seed=%s ending=%s day=%d people_alive=%d ever=%d share=%.2f rescues=%d deaths=%d walked=%d nights=%d raids=%d ready=%s list=%d score=%d" % [skill_name, str(game.args.get("seed", "1")), arc.ended_id, arc.day, alive, ever_n, float(alive) / float(maxi(1, ever_n)), int(st.rescues), int(st.deaths), int(st.left), int(st.nights_held), int(st.raids), str(arc.ready()), lst, arc.endings.last_score])
	game.get_tree().quit()
