## EXPERIMENT (prison round 12): the 30-DAY ARC of the managed phase. A calendar (Day N of 30), the story beats and the letters (prison_story.gd), the goal chain with its numbers
## (phases, the convoy's requirements), the night table by day, the weather, the convoy on day 30 and the endings (prison_endings.gd). Every number and word is in assets/data/prison_story.json.
## Owned by prison_game.gd (`arc`, `# ARC hook`); acts only while game.phase == "managed". It reads the economy (`econ.day`, stores, tiers, crew) and the siege (the night's plan, the open gaps)
## and writes only through their public calls. Pattern: plain data (the JSON) and one RefCounted that polls the day number (the economy has no day signal), like the econ and siege owners.
##
## API (for the UI and the tests):
##   day, days() -> int, convoy_day() -> int, days_left() -> int            weather_now() -> {kind, label, text, dim, blackout, wave_mult, water}     blackout() -> bool
##   phase() -> {id, name, text, by_day, done}        requirements() -> [{id, label, cur, need, frac, ok, must, text}]     ready() -> bool     missing() -> [text]     seats() -> int
##   objectives() -> [{t, done, bad, bar}] (the tracker's lines)    chip() -> the top bar's convoy chip    wave_plan(night) -> {total, segs, per, runner, name}
##   evacuate() -> {saved, left, tier, id}    end(id) shows an ending card (once)    stats {kills, raids, rescues, deaths, left, scrap, nights_held, letters, ...}
## Hooks (prison_game.gd, each one line): `frame(dt)`, `begin_raid(t, seed)` (letters and the set-piece cache), `take_notes(grid)` and `on_raid(alive, loot)` (a raid ends), `key(ev)` (L), `paint(c)`,
## `dim()`; prison_siege.gd `_start_attack` (`wave_plan`) and `_end_attack` (`night_over`); prison_econ.gd `hit_bonus` (`blackout`).
## Flags: `--day=N` (start on day N, the earlier beats are in the log), `--arcready` (the base is ready for the convoy), `--story=ID` (show a beat card at frame 20), `--arcshow` (cards in scripted runs),
## `--ending=ID` (show an ending card at frame 20), `--arcauto[=skill]` (the scripted days: prison_arclab.gd).
extends RefCounted

const Story := preload("res://scripts/prison/prison_story.gd")
const Endings := preload("res://scripts/prison/prison_endings.gd")
const Events := preload("res://scripts/prison/prison_events.gd")
const Playlog := preload("res://scripts/prison/prison_playlog.gd")    # PLAYLOG hook: the run, one line a day
const PATH := "res://assets/data/prison_story.json"

signal day_changed(day: int)
signal ended(id: String)

var game
var cfg: Dictionary = {}
var story
var endings
var plog    # PLAYLOG hook
var day := 1
var weather := "clear"
var started := false
var ended_id := ""
var convoy := "none"    # none | here | gone | left (taken)
var delivered: Dictionary = {}    # beat id -> the day it was delivered
var choices: Dictionary = {}    # beat id -> the choice id
var letters_found: Array = []
var log_entries: Array = []    # [{day, kind, title, from, text, tag, result}]
var set_piece: Dictionary = {}    # a cache the next raid marks: {name, loot, note, pos, id}
var storm_seen := false
var stats := {"kills": 0, "raids": 0, "rescues": 0, "deaths": 0, "left": 0, "scrap": 0.0, "nights_held": 0, "letters": 0, "ruth_deaths": 0, "starved": 0, "peak_people": 0, "fence_lost": 0}
var ever: Dictionary = {}    # person name -> {day, fate ("" | "died" | "walked"), cause, day_out}
# EVENTS (prison_events.gd): the plain dicts a save can read. flags: memory key -> the day it was set. person_traits: name -> trait ids an event gave on top of prison_bios.json. hurt: name -> the last day
# they are out. night_mods: night number (string) -> {size, weather}. event_pending: the card drawn for this morning {id, who}. raid_mod: the next raid's variant (read and cleared by `take_raid_mod`).
var events
var run_seed := 0
var flags: Dictionary = {}
var events_seen: Array = []
var person_traits: Dictionary = {}
var hurt: Dictionary = {}
var night_mods: Dictionary = {}
var weather_over: Dictionary = {}
var raid_mod := ""
var event_pending: Dictionary = {}
var scripted := false    # a scripted run (--auto, --shot ...): cards go to the log only
var _cfg_nights: Array = []
var _last_day := 0
var _start_t := 0.0
var _gap_t := 0.0
var _track_t := 0.0
var _pending_end := ""
var _convoy_open := false
var _convoy_decided := false
var _convoy_missed := false    # the convoy came and went while she was out: the card is shown when she is back in the base
var _walked: Array = []
var _queue: Array = []
var _notes_wait: Array = []
var _day_banner_t := 0.0
var _ready_cache := {}


func _init(g) -> void:
	game = g
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	cfg = parsed if parsed is Dictionary else {}
	_cfg_nights = cfg.get("nights", [])
	var a: Dictionary = g.args
	scripted = (a.has("shot") or a.has("auto") or a.has("drive") or a.has("perf") or a.has("seq") or a.has("raid") or a.has("log") or a.has("turntest") or a.has("econ-lab") or a.has("arcauto") or a.has("loot-lab") or a.has("siege")) and not a.has("arcshow")
	events = Events.new(self)
	story = Story.new(g, self)
	endings = Endings.new(g, self)
	plog = Playlog.new(g, self)
	g.econ.person_left.connect(func(nm): _walked.append(String(nm)))


# ------------------------------------------------------------------------------ numbers --

func days() -> int:
	return int(cfg.calendar.days)


func convoy_day() -> int:
	return int(cfg.calendar.convoy_day)


func days_left() -> int:
	return maxi(0, convoy_day() - day)


func active() -> bool:
	return game.phase == "managed" and ended_id == "" and started


func weather_of(d: int) -> Dictionary:
	var kind := String(weather_over.get(str(d), cfg.weather.get(str(d), "clear")))    # (EVENTS: a card can change tonight's weather)
	var e: Dictionary = (cfg.weather_kinds.get(kind, cfg.weather_kinds.clear) as Dictionary).duplicate()
	e["kind"] = kind
	return e


## The weather of the day the present hour belongs to (the night after day 24 is day 24's).
func weather_now() -> Dictionary:
	return weather_of(day - 1 if float(game.tod) < float(cfg.calendar.card_h) and day > 1 else day)


func blackout() -> bool:
	return active() and bool(weather_now().get("blackout", false)) and _night_hour()


func _night_hour() -> bool:
	var h: float = float(game.tod)
	return h >= 17.0 or h < 6.5


## The darkening of the world's tint by the weather (0 to 1): the storm is dark all evening.
func dim() -> float:
	if not active() or game.mode != "base":
		return 0.0
	var w := weather_now()
	var f := float(w.get("dim", 0.0))
	if String(w.kind) == "storm" and not _night_hour():
		f *= 0.5
	return f


## The night table: the dead sent on night n, the segments and the runner share (rows are interpolated), times the weather of that day.
func wave_plan(n: int) -> Dictionary:
	var rows: Array = _cfg_nights
	var lo: Array = rows[0]
	var hi: Array = rows[rows.size() - 1]
	for r in rows:
		if int(r[0]) <= n:
			lo = r
	for r in rows:
		if int(r[0]) >= n:
			hi = r
			break
	var t := 0.0 if int(hi[0]) == int(lo[0]) else clampf(float(n - int(lo[0])) / float(int(hi[0]) - int(lo[0])), 0.0, 1.0)
	var total := lerpf(float(lo[1]), float(hi[1]), t)
	if n > int((rows[rows.size() - 1] as Array)[0]):
		total = float((rows[rows.size() - 1] as Array)[1]) * (1.0 + 0.15 * float(n - int((rows[rows.size() - 1] as Array)[0])))
	total *= float(weather_of(n).get("wave_mult", 1.0))
	total *= float((night_mods.get(str(n), {}) as Dictionary).get("size", 1.0))    # EVENTS hook: a card made tonight bigger or smaller
	var segs := int(lo[2])
	var runner := lerpf(float(lo[3]), float(hi[3]), t)
	var tot := maxi(2, roundi(total))
	segs = clampi(segs, 1, tot)
	return {"total": tot, "segs": segs, "per": ceili(float(tot) / float(segs)), "runner": runner, "name": String(cfg.night_names.get(str(n), "")), "storm": String(weather_of(n).kind) == "storm"}


# ------------------------------------------------------------------------ requirements --

func _stock(res: String) -> float:
	return float(game.stores.get(res, 0.0))


func people_alive() -> int:
	return 1 + game.econ.people()    # Ruth and the crew


func seats() -> int:
	var n: int = int(cfg.convoy.bus_seats)
	for id in game.econ.order:
		if bool(game.econ.st.get(id, {}).get("built", false)):
			n += int(game.econ.defs[id].effect.get("seats", 0))
	return n


func requirements() -> Array:
	var out: Array = []
	var econ = game.econ
	for r in cfg.requirements:
		var cur := 0.0
		var need := 1.0
		var text := ""
		match String(r.kind):
			"stock":
				cur = _stock(String(r.res))
				need = float(r.need)
				text = "%d / %d" % [int(cur), int(need)]
			"project":
				need = 1.0
				var st: String = econ.state(String(r.project))
				cur = 1.0 if st == "built" else (0.5 if st == "building" else 0.0)
				text = {"built": "built", "building": "being built", "queued": "queued", "available": "not started", "locked": "locked"}.get(st, st)
			"tier":
				need = float(r.tier)
				cur = float(econ.tier(String(r.building)))
				text = "tier %d / %d" % [int(cur), int(need)]
			"people":
				cur = float(people_alive())
				need = float(r.need)
				text = "%d / %d" % [int(cur), int(need)]
		var frac := clampf(cur / maxf(need, 0.001), 0.0, 1.0)
		var ok := frac >= 0.999 if String(r.kind) != "project" else cur >= 1.0
		out.append({"id": String(r.id), "label": String(r.label), "cur": cur, "need": need, "frac": frac, "ok": ok, "must": bool(r.get("must", false)), "text": text, "kind": String(r.kind), "res": String(r.get("res", ""))})
	return out


func ready() -> bool:
	for r in requirements():
		if bool(r.must) and not bool(r.ok):
			return false
	return true


func missing() -> Array:
	var out: Array = []
	for r in requirements():
		if bool(r.must) and not bool(r.ok):
			out.append("%s (%s)" % [String(r.label), String(r.text)])
	return out


func phase() -> Dictionary:
	var stage_order: Array = ["Camp", "Shelter", "Settlement", "Fortress", "Hub"]
	var cur: int = stage_order.find(String(game.econ.stage()))
	var chosen: Dictionary = {}
	for p in cfg.phases:
		var need_st := String(p.stage)
		var done := false
		if String(p.id) == "evacuate":
			done = convoy == "left"
		else:
			done = cur >= stage_order.find(need_st)
		var e: Dictionary = (p as Dictionary).duplicate()
		e["done"] = done
		if chosen.is_empty() and not done:
			chosen = e
	if chosen.is_empty():
		chosen = (cfg.phases[cfg.phases.size() - 1] as Dictionary).duplicate()
		chosen["done"] = true
	# the convoy's confirmation opens phase III whatever the stage
	if delivered.has("arrangement") and String(chosen.id) != "evacuate":
		for p in cfg.phases:
			if String(p.id) == "evacuate":
				chosen = (p as Dictionary).duplicate()
				chosen["done"] = false
	return chosen


func phases_list() -> Array:
	var stage_order: Array = ["Camp", "Shelter", "Settlement", "Fortress", "Hub"]
	var cur: int = stage_order.find(String(game.econ.stage()))
	var out: Array = []
	for p in cfg.phases:
		var e: Dictionary = (p as Dictionary).duplicate()
		e["done"] = (convoy == "left") if String(p.id) == "evacuate" else cur >= stage_order.find(String(p.stage))
		out.append(e)
	return out


# ------------------------------------------------------------------------- tracker and bar --

## The parts the convoy's list asks for in all (the projects on its path plus the stock handed over) and how many are still to find after what is built, being built and held.
func convoy_parts() -> Dictionary:
	var econ = game.econ
	var ids := {}
	for r in cfg.requirements:
		if String(r.kind) == "project":
			_chain(ids, String(r.project))
		elif String(r.kind) == "tier":
			for t in range(1, int(r.tier) + 1):
				_chain(ids, "%s%d" % [String(r.building), t])
	var total := 0.0
	var left := 0.0
	for id in ids:
		var p := float(econ.defs[id].cost.get("parts", 0.0))
		total += p
		if not ["built", "building"].has(String(econ.state(String(id)))):
			left += p
	for r in cfg.requirements:
		if String(r.kind) == "stock" and String(r.res) == "parts":
			total += float(r.need)
			left += float(r.need)
	return {"total": total, "left": maxf(0.0, left - _stock("parts"))}


func _chain(ids: Dictionary, id: String) -> void:
	if ids.has(id):
		return
	ids[id] = true
	for r in game.econ.defs[id].requires:
		_chain(ids, String(r))


## The tracker's lines for the arc (the top bar's `objectives()` adds them after the urgent line). Each: {t, done, bad, bar (0 to 1, optional)}.
func objectives() -> Array:
	var out: Array = []
	if not started or ended_id != "":
		return out
	var ph := phase()
	var left := days_left()
	var head := "%s  -  day %d of %d%s" % [String(ph.name), day, days(), ("  (%d left to the convoy)" % left) if left > 0 and convoy == "none" else ""]
	var late: bool = int(ph.by_day) > 0 and day > int(ph.by_day) and not bool(ph.done) and String(ph.id) != "evacuate"
	out.append({"t": head, "done": false, "bad": late, "head": true})
	if convoy == "none" and day >= 3:    # the rumour is out: the list and its parts total are on the tracker from day 3
		var cp := convoy_parts()
		var ok_n := 0
		var must_n := 0
		for r in requirements():
			if bool(r.must):
				must_n += 1
				ok_n += 1 if bool(r.ok) else 0
		out.append({"t": "Convoy list: %d of %d ready. Parts %d in all, %d still to find" % [ok_n, must_n, int(cp.total), int(cp.left)], "done": ok_n == must_n, "bad": left <= 3 and ok_n < must_n, "bar": 1.0 - float(cp.left) / maxf(1.0, float(cp.total)), "list": true})
	if String(ph.id) == "evacuate":
		var n := 0
		for r in requirements():
			if bool(r.must) and bool(r.ok):
				continue
			if not bool(r.must) and bool(r.ok):
				continue
			out.append({"t": "%s: %s%s" % [String(r.label), String(r.text), "" if bool(r.must) else "  (not required)"], "done": false, "bad": left <= 3 and bool(r.must), "bar": float(r.frac)})
			n += 1
			if n >= 2:
				break
		if n == 0:
			out.append({"t": "Everything on the convoy's list is ready. Hold the gate.", "done": true})
	return out


## The top bar's convoy chip.
func chip() -> Dictionary:
	var reqs := requirements()
	var must_n := 0
	var ok_n := 0
	for r in reqs:
		if bool(r.must):
			must_n += 1
			if bool(r.ok):
				ok_n += 1
	var left := days_left()
	var main := "Convoy: day %d" % convoy_day()
	var sub := "in %d d" % left
	var st := "ok"
	if convoy == "here":
		main = "CONVOY HERE"
		sub = "until %02d:00" % int(cfg.calendar.leave_h)
		st = "danger"
	elif convoy != "none" or day >= convoy_day():
		sub = "gone" if convoy == "gone" else ("today" if day == convoy_day() else "passed")
	elif left <= 3 and ok_n < must_n:
		st = "danger"
	elif left <= 7 and ok_n < must_n:
		st = "warn"
	var tip := "%s comes to the gate on day %d at %02d:00 and waits %s. Ready: %d of %d things on its list.\n" % [String(cfg.convoy.name).capitalize(), convoy_day(), int(cfg.calendar.arrive_h), String(cfg.convoy.waits), ok_n, must_n]
	for r in reqs:
		tip += "\n%s %s: %s" % ["[x]" if bool(r.ok) else "[ ]", String(r.label), String(r.text)]
	var cp := convoy_parts()
	tip += "\n\nParts in all: %d, still to find: %d." % [int(cp.total), int(cp.left)]
	tip += "\nSeats: %d for %d people.   L: the story log." % [seats(), people_alive()]
	return {"main": main, "sub": sub, "state": st, "tip": tip, "meter": float(ok_n) / maxf(1.0, float(must_n))}


# ---------------------------------------------------------------------------------- frame --

func frame(dt: float) -> void:
	if game.args.has("arcquit") and game.frames >= int(game.args.arcquit):    # a check: quit after N frames
		game.get_tree().quit()
		return
	if game.phase != "managed" or ended_id != "":
		return
	if not started:
		if game.run != null and game.crew != null and game.mode == "base":
			_begin()
		return
	_start_t += dt
	_day_banner_t = maxf(0.0, _day_banner_t - dt)
	var d: int = game.econ.day
	if d != _last_day:
		_last_day = d
		_on_day(d)
	_track_t += dt
	if _track_t >= 1.0:
		_track_t = 0.0
		_track_people()
	_overrun(dt)
	_convoy_hours()
	_late_end()
	if _pending_end != "" and not game.busy:
		var e := _pending_end
		_pending_end = ""
		end(e)
		return
	story.frame(dt)
	if game.args.has("story") and game.frames == 20:
		if String(game.args.story) == "letter":
			story.show_letter(next_letter())
		else:
			story.show_beat(String(game.args.story))
	if game.args.has("ending") and game.frames == 20:
		endings.show_test(String(game.args.ending))


func _begin() -> void:
	started = true
	day = int(game.econ.day)
	_last_day = day
	_start_t = 0.0
	_track_people()
	var a: Dictionary = game.args
	if run_seed == 0:
		run_seed = int(a.get("seed", str(randi() % 900000 + 1)))    # EVENTS: the card draw is a function of this and the day (a save keeps it)
	if a.has("day") and int(a.day) > 1:
		_jump(int(a.day))
	if a.has("arcready"):
		_make_ready()
	_last_day = int(game.econ.day)
	day = _last_day
	weather = String(weather_of(day).kind)
	_queue_due(true)
	story.log_changed()


## --day=N: the calendar starts on day N. The beats of the earlier days are in the log, the nights before it are counted as held.
func _jump(n: int) -> void:
	game.econ.day = n
	game.siege.nights_started = n - 1
	game.siege.abs_h = 24.0 * float(n - 1) + float(game.tod)
	game.siege._last_tod = float(game.tod)
	for b in cfg.beats:
		if int(b.day) < n and not delivered.has(String(b.id)):
			delivered[String(b.id)] = int(b.day)
			if String(b.id) == "the_dam":
				choices["the_dam"] = "stay"
			log_entries.append(_entry(b, int(b.day)))
	stats.nights_held = n - 1
	day = n


## --arcready (a check): the convoy's list is met, so the day-30 card can be tried.
func _make_ready() -> void:
	var econ = game.econ
	for id in ["power1", "radio1", "fence2", "convoy1", "dormitory2", "water2", "garden2", "kitchen1", "infirmary1"]:
		econ.debug_build(id)
	game.stores["fuel"] = maxf(float(game.stores.get("fuel", 0.0)), 45.0)
	game.stores["parts"] = maxf(float(game.stores.get("parts", 0.0)), 30.0)
	game.stores["meds"] = maxf(float(game.stores.get("meds", 0.0)), 10.0)
	game.stores["food"] = maxf(float(game.stores.get("food", 0.0)), 40.0)
	game.stores["scrap"] = maxf(float(game.stores.get("scrap", 0.0)), 60.0)
	game.stores["ammo"] = maxf(float(game.stores.get("ammo", 0.0)), 120.0)
	game.siege.apply_fence(econ.fence_mult(), true)


func _on_day(d: int) -> void:
	plog.close_day()    # PLAYLOG hook (the day that ends)
	day = d
	weather = String(weather_of(d).kind)
	var w := weather_of(d)
	if float(w.get("water", 0.0)) > 0.0 and game.econ.tier("water") >= 1:
		game.stores["water"] = float(game.stores.water) + float(w.water)
	if String(w.kind) == "storm":
		storm_seen = true
	_starve()
	_queue_due(false)
	if _queue.is_empty() and event_pending.is_empty():
		event_pending = events.draw(d)    # EVENTS hook: a morning with no story beat may get a card
	_day_banner()
	day_changed.emit(d)
	if game.args.has("arclog"):
		print("ARC day ", d, " weather ", weather, " phase ", phase().id, " people ", people_alive(), " ready ", ready(), " stores ", game.stores)


func _day_banner() -> void:
	if scripted:
		return
	var w := weather_of(day)
	var t := "DAY %d OF %d" % [day, days()]
	if day == convoy_day():
		t = "DAY %d OF %d  -  THE CONVOY COMES TODAY" % [day, days()]
	var sub := String(w.label)
	if sub != "clear":
		t += "   " + sub
	var warn := String(w.get("text", ""))
	if day == convoy_day() and not ready():    # (the convoy is a one-shot: say at dawn what the list still lacks)
		warn = "NOT READY: " + "; ".join(missing())
	story.banner(t, warn)


## Starvation: a streak of days without food or water takes people.
func _starve() -> void:
	var rule: Dictionary = cfg.rules.starvation
	var streak := maxi(int(game.econ._streak.food), int(game.econ._streak.water))
	if streak < int(rule.after_days):
		return
	for i in int(rule.per_day):
		var crew: Array = game.econ.crew()
		if crew.is_empty():
			return
		var pick: Dictionary = crew[crew.size() - 1]
		for c in crew:    # the youngest go last, the guards stay: the one with no role first
			if String(c.role) == "" or String(c.role) == "cleaner":
				pick = c
				break
		kill(String(pick.name), "starved")
		stats.starved = int(stats.starved) + 1


## A person dies (not the siege's: it removes its own). `cause`: starved, ...
func kill(nm: String, cause: String) -> void:
	if game.crew != null:
		game._econ_remove(nm)
	else:
		if not game.econ_gone.has(nm):
			game.econ_gone.append(nm)
	game.people.forget(nm)
	_mark(nm, "died", cause)
	if not scripted:
		game.people.banner("%s has died of hunger." % nm if cause == "starved" else "%s is dead." % nm, Color(1, 0.5, 0.45))


func _mark(nm: String, fate: String, cause: String) -> void:
	if ever.has(nm) and String(ever[nm].fate) == "":
		ever[nm].fate = fate
		ever[nm]["cause"] = cause
		ever[nm]["day_out"] = day
		if fate == "died":
			stats.deaths = int(stats.deaths) + 1
		else:
			stats.left = int(stats.left) + 1


## Who is here, who came and who is gone (once a second): names appear (a rescue) or vanish (died, or walked out).
func _track_people() -> void:
	if game.crew == null:
		return
	var here := {}
	for c in game.econ.crew():
		here[String(c.name)] = c
		if not ever.has(String(c.name)):
			ever[String(c.name)] = {"day": day, "fate": "", "cause": "", "role": String(c.role), "kid": bool(c.kid), "start": not started or _start_t < 2.0}
			if started and _start_t >= 2.0:
				stats.rescues = int(stats.rescues) + 1
				if not scripted:
					log_entries.append({"day": day, "kind": "note", "title": "%s joined" % String(c.name), "from": "the gate", "text": "", "tag": "join", "result": ""})
	for nm in ever:
		if String(ever[nm].fate) == "" and not here.has(nm):
			_mark(String(nm), "walked" if _walked.has(String(nm)) else "died", "")
	stats.peak_people = maxi(int(stats.peak_people), here.size() + 1)


func names_with(fate: String) -> Array:
	var out: Array = []
	for nm in ever:
		if String(ever[nm].fate) == fate:
			out.append(String(nm))
	return out


func alive_names() -> Array:
	var out: Array = ["Ruth"]
	for c in game.econ.crew():
		out.append(String(c.name))
	return out


# ----------------------------------------------------------------------- beats and letters --

## A choice of a beat as it stands now: `if_flag` on the beat ({flag: {"extra": text, "choices": {choice id: keys that replace the choice's own}}}) changes it once the flag is set (the weir letter and the dam).
func choice_of(b: Dictionary, choice_id: String) -> Dictionary:
	for c in b.get("choice", []):
		if String(c.id) == choice_id:
			var out: Dictionary = (c as Dictionary).duplicate(true)
			for f in b.get("if_flag", {}):
				if flags.has(String(f)):
					out.merge((b.if_flag[f].get("choices", {}) as Dictionary).get(choice_id, {}), true)
			return out
	return {}


func _entry(b: Dictionary, d: int) -> Dictionary:
	var res := ""
	if choices.has(String(b.id)):
		res = String(choice_of(b, String(choices[String(b.id)])).get("result", ""))
	return {"day": d, "kind": "radio", "id": String(b.id), "title": String(b.title), "from": String(b.from), "text": String(b.text), "tag": String(b.get("tag", "")), "result": res, "short": String(b.get("short", ""))}


## Every beat of a day up to today that is not delivered goes to the queue; `quiet` puts them in the log without a card (a start on a later day).
func _queue_due(quiet: bool) -> void:
	for b in cfg.beats:
		if int(b.day) <= day and not delivered.has(String(b.id)) and not _queue.has(String(b.id)):
			_queue.append(String(b.id))


## Called by the story every frame: the next card, when the moment is quiet. Returns the beat id or "".
func next_due() -> String:
	if _queue.is_empty() or _start_t < 4.0:
		return ""
	return String(_queue[0])


func beat(id: String) -> Dictionary:
	for b in cfg.beats:
		if String(b.id) == id:
			return b
	return {}


## The beat was shown (or logged): its effects apply and it goes in the log.
func deliver(id: String, choice_id: String = "") -> void:
	var b := beat(id)
	if b.is_empty() or delivered.has(id):
		return
	_queue.erase(id)
	delivered[id] = day
	if choice_id != "":
		choices[id] = choice_id
	elif b.has("choice"):
		choices[id] = String(b.choice[b.choice.size() - 1].id)    # a scripted run takes the last (the safe) answer
		choice_id = String(choices[id])
	plog.event(id, choice_id)    # PLAYLOG hook
	_apply(b.get("reward", {}))
	if b.has("choice"):
		_apply(choice_of(b, choice_id).get("effects", {}))
	if b.has("set_piece"):
		set_piece = (b.set_piece as Dictionary).duplicate(true)
		set_piece["pos"] = Vector2(-1, -1)
	log_entries.append(_entry(b, day))
	story.log_changed()


## The effects of a beat, a choice, a letter or an event card: stores {res: n}, morale n, and (events, see prison_events.gd `apply_extra`) person, flag, night_mod, raid_mod, set_piece. `ctx` carries the
## card's person and collects the lines the result card shows.
func _apply(fx: Dictionary, ctx: Dictionary = {}) -> void:
	for k in fx.get("stores", {}):
		game.stores[k] = maxf(0.0, float(game.stores.get(k, 0.0)) + float(fx.stores[k]))
	if fx.has("morale"):
		game.econ.morale = clampf(float(game.econ.morale) + float(fx.morale), 0.0, 100.0)
	if fx.has("person") or fx.has("flag") or fx.has("night_mod") or fx.has("raid_mod") or fx.has("set_piece"):
		events.apply_extra(fx, ctx)


## The readiness line for the last beats: the convoy's list as it stands.
func readiness_text() -> String:
	var miss := missing()
	if miss.is_empty():
		return "Today the list is complete. Hold the gate."
	return "Still missing: " + "; ".join(miss) + "."


## A raid begins: letters in containers, the set-piece cache marked.
func begin_raid(t: Dictionary, seed_i: int) -> void:
	if not started:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 31 + 7
	var cs: Array = t.containers
	if cs.is_empty():
		return
	var entry := Vector2(t.entry.pos)
	if not set_piece.is_empty():
		var best: Dictionary = {}
		var bd := -1.0
		for ct in cs:
			var d := Vector2(ct.pos).distance_to(entry)
			if d > bd and d < 52.0:
				bd = d
				best = ct
		if not best.is_empty():
			var loot: Dictionary = best.loot
			for k in set_piece.loot:
				loot[k] = float(loot.get(k, 0.0)) + float(set_piece.loot[k])
			if bool(set_piece.get("note", false)):
				loot["note"] = 1
			set_piece["pos"] = Vector2(best.pos)
			if game.args.has("arclog"):
				print("ARC cache ", set_piece.name, " in ", best.id, " at ", best.pos, " loot ", best.loot)
			set_piece["id"] = String(best.id)
	if letters_found.size() < cfg.letters.size() and rng.randf() < float(cfg.letter_chance):
		var pool: Array = cs.filter(func(c): return String(c.id) != String(set_piece.get("id", "")) and not (c.loot as Dictionary).has("note"))
		if not pool.is_empty():
			var ct2: Dictionary = pool[rng.randi() % pool.size()]
			(ct2.loot as Dictionary)["note"] = 1
			if game.args.has("arclog"):
				print("ARC letter hidden in ", ct2.id, " at ", ct2.pos)


## Back from a raid: the notes in the pack are read (and leave the pack); returns how many.
func take_notes(grid: Dictionary) -> int:
	var n := 0
	var keep: Array = []
	for c in (grid.cells as Array):
		if String(c.item) == "note":
			n += int(c.get("count", 1))
		else:
			keep.append(c)
	if n > 0:
		if game.args.has("arclog"):
			print("ARC notes brought home: ", n)
		(grid.cells as Array).clear()
		(grid.cells as Array).append_array(keep)
		for i in n:
			_notes_wait.append(1)
	return n


## What a raid brought home (called as the raid ends): the counts, and the cache found.
func on_raid(alive: bool, loot_got: Dictionary) -> void:
	if not started:
		return
	stats.raids = int(stats.raids) + 1
	plog.raid(alive, loot_got)    # PLAYLOG hook
	stats.scrap = float(stats.scrap) + float(loot_got.get("scrap", 0.0))
	var f = game.run.field
	var killed := 0
	for s in f.status:
		if int(s) == int(f.KILLED):
			killed += 1
	stats.kills = int(stats.kills) + killed
	if not set_piece.is_empty() and set_piece.has("id") and alive and game.run.sim.search.is_looted(String(set_piece.id)):
		var sp_name := String(set_piece.get("name", "the cache"))
		log_entries.append({"day": day, "kind": "note", "title": sp_name, "from": "the raid", "text": String(set_piece.get("found", "")), "tag": "cache", "result": ""})
		set_piece = {}
		story.log_changed()
	if not alive:
		stats.ruth_deaths = int(stats.ruth_deaths) + 1
		if int(stats.ruth_deaths) >= int(game.Bal.dm("ruth_deaths", cfg.rules.ruth_deaths)):
			_pending_end = "dead"
		elif not scripted:
			game.people.banner("Ruth went down in the street (%d of %d). The pack is lost." % [int(stats.ruth_deaths), int(game.Bal.dm("ruth_deaths", cfg.rules.ruth_deaths))], Color(1, 0.5, 0.45), 7.0)


## A letter is read (a note came home): picks the next one nobody has read.
func next_letter() -> Dictionary:
	var rest: Array = cfg.letters.filter(func(l): return not letters_found.has(String(l.id)))
	if rest.is_empty():
		return {}
	var l: Dictionary = rest[(day * 7 + letters_found.size() * 3) % rest.size()]
	letters_found.append(String(l.id))
	stats.letters = int(stats.letters) + 1
	_apply(l.get("reward", {}))
	log_entries.append({"day": day, "kind": "letter", "title": String(l.title), "from": String(l.from), "text": String(l.text), "tag": "letter", "result": String(l.get("clue", ""))})
	story.log_changed()
	return l


func take_wait() -> bool:
	if _notes_wait.is_empty():
		return false
	_notes_wait.pop_front()
	return true


# ----------------------------------------------------------------------------- events --

## The id of this morning's event card when it is time to show it ("" otherwise). The story calls it every frame, after the beats.
func next_event() -> String:
	if event_pending.is_empty() or _start_t < 4.0 or not _queue.is_empty():
		return ""
	return String(event_pending.id)


## The card with its text filled for the person it is about, and the choices on offer.
func event_view() -> Dictionary:
	var c: Dictionary = events.card(String(event_pending.get("id", "")))
	if c.is_empty():
		return {}
	var ctx := {"who": String(event_pending.get("who", ""))}
	return {"card": c, "title": String(c.title), "from": String(c.get("from", "")), "text": events.fill(String(c.text), ctx), "tone": String(c.get("tone", "radio")), "choices": events.choices(c)}


## The player's answer (an index into `event_view().choices`; -1 takes the safe one). Returns {result, extra}: the words and the effects of the choice, for the result card.
func deliver_event(i: int) -> Dictionary:
	var v := event_view()
	if v.is_empty():
		event_pending = {}
		return {}
	var chs: Array = v.choices
	if chs.is_empty():
		event_pending = {}
		return {}
	if i < 0 and game.args.has("eventpick"):    # a check: a scripted run answers with this choice (0 = the first, clamped) instead of the safe one, so every effect can be tried
		i = int(game.args.eventpick)
	var c: Dictionary = chs[events.safe_index(v.card) if i < 0 else clampi(i, 0, chs.size() - 1)]
	var ctx := {"who": String(event_pending.get("who", ""))}
	events_seen.append(String(v.card.id))
	event_pending = {}
	if game.args.has("arclog"):
		print("ARC event day ", day, " ", v.card.id, " -> ", c.id, " who ", ctx.who)
	_apply(c.get("effects", {}), ctx)
	weather = String(weather_of(day).kind)
	var res: String = events.fill(String(c.get("result", "")), ctx)
	log_entries.append({"day": day, "kind": "radio", "title": String(v.title), "from": String(v.from), "text": String(v.text), "tag": "event", "result": res})
	story.log_changed()
	var extra: Array = []
	var fx: String = story._fx_text(c.get("effects", {}))
	if fx != "":
		extra.append(fx)
	extra.append_array(ctx.get("lines", []))
	return {"result": res, "extra": ", ".join(extra)}


## RAID hook (another agent): the variant the last card asked for ("" when none); reading it clears it.
func take_raid_mod() -> String:
	var m := raid_mod
	raid_mod = ""
	return m


# ----------------------------------------------------------------------- people's traits --

func traits_of(nm: String) -> Array:
	return events.traits_of(nm)


func hurt_now(nm: String) -> bool:
	return hurt.has(nm) and day <= int(hurt[nm])


## How many of the crew on their feet (not kids) have trait `id`, optionally only those whose econ role is `role`.
func count_trait(id: String, role: String = "") -> int:
	var n := 0
	for c in game.econ.crew():
		if bool(c.ok) and not bool(c.kid) and (role == "" or String(c.role) == role) and events.has(String(c.name), id):
			n += 1
	return n


## Veterans calm the base: the morale a day gets from them (at most two count).
func calm() -> float:
	var s := 0.0
	for c in game.econ.crew():
		if bool(c.ok) and not bool(c.kid):
			s += events.sum(String(c.name), "calm")
	return minf(s, 1.2)


## What scroungers eat on top of their share, a day.
func extra_eating() -> float:
	var s := 0.0
	for c in game.econ.crew():
		s += events.sum(String(c.name), "eats")
	return s


## A raid is over and `names` came home with Ruth: scroungers find more, thieves bring one thing extra and now and then something of the stores goes missing. Changes `loot` (the raid's takings),
## returns the lines for the banner.
func raid_bonus(names: Array, loot: Dictionary) -> Array:
	var lines: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 31 + day * 977 + int(stats.raids)
	for nm in names:
		var n := String(nm)
		if events.sum(n, "loot") > 0.0:
			loot["scrap"] = float(loot.get("scrap", 0.0)) + 3.0
			loot["food"] = float(loot.get("food", 0.0)) + 2.0
			lines.append("%s turned out two more pockets: +3 scrap, +2 food." % n)
		if events.sum(n, "loot_extra") > 0.0:
			var k: String = ["parts", "meds", "ammo", "fuel"][rng.randi() % 4]
			loot[k] = float(loot.get(k, 0.0)) + (2.0 if k == "meds" or k == "fuel" else 4.0)
			lines.append("%s came back with a little extra: %s." % [n, k])
			if rng.randf() < 0.12:
				var miss: String = ["scrap", "meds", "ammo"][rng.randi() % 3]
				var took := minf(float(game.stores.get(miss, 0.0)), 4.0 if miss != "meds" else 1.0)
				game.stores[miss] = float(game.stores.get(miss, 0.0)) - took
				if took > 0.0:
					lines.append("Some %s is missing from the stores. Nobody saw anything." % miss)
	return lines


# ---------------------------------------------------------------------------------- nights --

## The siege hook: a night is over. `stat` is the siege's stats dictionary.
func night_over(night: int, stat: Dictionary) -> void:
	if not started:
		return
	plog.night(stat)    # PLAYLOG hook
	stats.kills = int(stats.kills) + int(stat.get("killed", 0))
	stats.fence_lost = int(stats.fence_lost) + (stat.lost as Array).size()
	if ended_id == "":
		stats.nights_held = maxi(int(stats.nights_held), night)
	if night >= convoy_day() and ended_id == "" and _overrun_t() < float(cfg.rules.overrun.secs):
		_pending_end = held_id() if _fence_stands() else "overrun"


func _overrun_t() -> float:
	return _gap_t


func _gaps() -> int:
	var n := 0
	for s in game.siege.segs:
		if float(s.hp) <= 0.0:
			n += 1
	return n


func _overrun(dt: float) -> void:
	var rule: Dictionary = cfg.rules.overrun
	if game.siege.attacking and _gaps() >= int(rule.gaps):
		_gap_t += dt
		if _gap_t >= float(rule.secs):
			_gap_t = 0.0
			_pending_end = "overrun"
	else:
		_gap_t = maxf(0.0, _gap_t - dt * 2.0)


## Everyone gone: no crew at all.
func _late_end() -> void:
	if _pending_end != "" or game.mode != "base" or game.busy:
		return
	if day >= 3 and game.econ.people() == 0 and int(stats.peak_people) >= 2:
		_pending_end = "starved" if int(stats.starved) > 0 else "abandoned"
	if day > convoy_day() and not game.siege.attacking and convoy != "left" and float(game.tod) >= float(cfg.calendar.card_h) and game.siege.nights_started >= convoy_day():
		_pending_end = held_id() if _fence_stands() else "overrun"


## The fence still stands: fewer gaps than the overrun rule.
func _fence_stands() -> bool:
	return _gaps() < int(cfg.rules.overrun.gaps)


## Surviving the last night is "held" only with the convoy's list met; without it the people stayed because nothing came for them (a bitter ending, lower score).
func held_id() -> String:
	return "held" if ready() else "held_bitter"


# ---------------------------------------------------------------------------------- convoy --

func _convoy_hours() -> void:
	if _convoy_missed and not game.busy and game.mode == "base" and not game.siege.attacking and not scripted:
		_convoy_missed = false
		var mis: Array = missing()
		story.show_card({"kicker": "THE RIVER ROAD  -  DAY %d" % day, "title": "The convoy", "from": "Halloran, Harbor Relief", "text": String(cfg.convoy_cards.missed),
			"extra": ("It could not wait for you. On its list you were missing: " + "; ".join(mis) + ".") if not mis.is_empty() else "Everything on its list was ready. You were not there.", "tone": "convoy"})
	if day != convoy_day() or convoy == "left" or convoy == "gone":
		return
	var h: float = float(game.tod)
	var cal: Dictionary = cfg.calendar
	if convoy == "none" and h >= float(cal.arrive_h) and h < float(cal.leave_h):
		convoy = "here"
		if not scripted:
			story.banner("THE CONVOY IS AT THE GATE", "Halloran waits until %02d:00." % int(cal.leave_h) + ("" if ready() else "  NOT READY: " + "; ".join(missing())))
	if convoy == "here":
		if h >= float(cal.leave_h):
			convoy = "gone"
			log_entries.append({"day": day, "kind": "radio", "title": "The convoy leaves", "from": "Harbor Relief", "text": String(cfg.convoy_cards.missed if not _convoy_decided else cfg.convoy_cards.gone), "tag": "convoy", "result": ""})
			story.log_changed()
			_convoy_open = false
			_convoy_missed = not _convoy_decided
		elif not _convoy_open and not game.busy and game.mode == "base" and not game.siege.attacking and (not scripted or game.args.has("arcshow")):
			_convoy_open = true
			story.show_convoy()
	elif convoy == "none" and h >= float(cal.leave_h):
		convoy = "gone"
		_convoy_missed = true    # (the raid took the whole afternoon: no card was ever shown)


## The player's answer to the convoy card.
func convoy_answer(go: bool) -> void:
	_convoy_decided = true
	_convoy_open = false
	if go and ready():
		var r := evacuate()
		convoy = "left"
		end(String(r.id), r)
	else:
		convoy = "gone"
		log_entries.append({"day": day, "kind": "radio", "title": "The convoy leaves", "from": "Harbor Relief", "text": String(cfg.convoy_cards.gone) if ready() else String(cfg.convoy_cards.short), "tag": "convoy", "result": ""})
		story.log_changed()


## Who goes, who stays, the ending id. The fuel and parts are handed over.
func evacuate() -> Dictionary:
	var names: Array = ["Ruth"]
	var kids: Array = []
	var rest: Array = []
	for c in game.econ.crew():
		if bool(c.kid):
			kids.append(String(c.name))
		else:
			rest.append(String(c.name))
	names.append_array(kids)
	names.append_array(rest)
	var n_seats := seats()
	var saved: Array = names.slice(0, n_seats)
	var left: Array = names.slice(n_seats)
	var total_ever := 1 + ever.size()
	var share := float(saved.size()) / float(maxi(1, total_ever))
	var tier := "bitter"
	for t in cfg.evac_tiers:
		if share >= float(t.min_share):
			tier = String(t.id)
			break
	var id := "evac_" + tier
	if saved.size() == 1:
		id = "evac_lonely"
		tier = "lonely"
	var bonuses := bonuses_got(saved.size())
	for r in cfg.requirements:
		if bool(r.get("take", false)):
			game.stores[String(r.res)] = maxf(0.0, _stock(String(r.res)) - float(r.need))
	return {"id": id, "tier": tier, "saved": saved, "left": left, "share": share, "bonuses": bonuses}


func bonuses_got(saved_n: int) -> Array:
	var out: Array = []
	for b in cfg.bonuses:
		var rule := String(b.rule)
		var ok := false
		if rule == "seat_spare":
			ok = seats() - saved_n >= 1 and game.dog != null
		elif rule.begins_with("stock:"):
			var p := rule.split(":")
			ok = _stock(p[1]) >= float(p[2])
		elif rule == "no_deaths":
			ok = int(stats.deaths) == 0
		if ok:
			out.append(b)
	return out


# ---------------------------------------------------------------------------------- ending --

func end(id: String, extra: Dictionary = {}) -> void:
	if ended_id != "":
		return
	ended_id = id
	plog.finish("ending " + id)    # PLAYLOG hook
	if id == "evac_full" or id == "evac_good" or id == "evac_bitter" or id == "evac_lonely":
		convoy = "left"
	endings.show(id, extra)
	ended.emit(id)


# ------------------------------------------------------------------------------ the world --

func paint(c: CanvasItem) -> void:
	if not started or ended_id != "":
		return
	var t: float = float(game.TILE)
	if game.mode == "raid" and not set_piece.is_empty() and set_piece.has("id"):
		var p: Vector2 = Vector2(set_piece.pos) * t
		var pulse := 0.5 + 0.5 * sin(game.clock * 3.2)
		c.draw_arc(p, 40.0 + 6.0 * pulse, 0.0, TAU, 28, Color(0.94, 0.76, 0.29, 0.8), 3.0, true)
		c.draw_string(ThemeDB.fallback_font, p + Vector2(-90, -52), String(set_piece.name).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 180, 17, Color(1, 0.9, 0.5, 0.95))
		return
	if game.mode == "base" and convoy == "here":
		var gate: Vector2 = Vector2(game.base.stations.truck) * t + Vector2(-3.0 * t, 5.0 * t)
		_draw_convoy(c, gate)
	elif game.mode == "base" and game.econ.tier("convoy") >= 1:
		var at: Vector2 = Vector2(game.base.stations.truck) * t + Vector2(-2.6 * t, 1.1 * t)
		c.draw_rect(Rect2(at, Vector2(150, 56)), Color(0.3, 0.33, 0.3))
		c.draw_rect(Rect2(at + Vector2(100, -14), Vector2(50, 36)), Color(0.24, 0.3, 0.34))
		c.draw_rect(Rect2(at + Vector2(0, 2), Vector2(98, 6)), Color(0.94, 0.76, 0.29, 0.8))
		c.draw_circle(at + Vector2(24, 58), 12, Color(0.05, 0.05, 0.05))
		c.draw_circle(at + Vector2(118, 58), 12, Color(0.05, 0.05, 0.05))
		c.draw_string(ThemeDB.fallback_font, at + Vector2(6, 32), "CONVOY", HORIZONTAL_ALIGNMENT_LEFT, 90, 15, Color(0.94, 0.9, 0.7))


func _draw_convoy(c: CanvasItem, at: Vector2) -> void:
	for i in 3:
		var o := at + Vector2(float(i) * 170.0, 0.0)
		c.draw_rect(Rect2(o, Vector2(150, 60)), Color(0.22, 0.28, 0.24) if i == 0 else Color(0.34, 0.34, 0.3))
		c.draw_rect(Rect2(o + Vector2(104, -16), Vector2(46, 38)), Color(0.2, 0.26, 0.32))
		c.draw_circle(o + Vector2(24, 62), 12, Color(0.05, 0.05, 0.05))
		c.draw_circle(o + Vector2(120, 62), 12, Color(0.05, 0.05, 0.05))
	c.draw_string(ThemeDB.fallback_font, at + Vector2(0, -26), "HARBOR RELIEF", HORIZONTAL_ALIGNMENT_LEFT, 200, 20, Color(1, 0.9, 0.5))


## The key L: the story log (a window of its own, in the base or on a raid).
func key(ev: InputEvent) -> bool:
	return story.key(ev)


## The weather of night `d` has a blackout (the lab's night model).
func blackout_for(d: int) -> bool:
	return bool(weather_of(d).get("blackout", false))


var labrun    # prison_arclab.gd, made on the first call of `--arcauto`


## `--arcauto`: one scripted day a frame (see prison_arclab.gd).
func lab(dt: float) -> void:
	if labrun == null:
		labrun = load("res://scripts/prison/prison_arclab.gd").new(self)
	labrun.step(dt)
	if ended_id != "":
		labrun.report_if_ended()


## SAVE hook (prison_save.gd): the story so far. The calendar's day is the economy's (`econ.day`).
func to_dict() -> Dictionary:
	return {"day": day, "weather": weather, "ended_id": ended_id, "convoy": convoy, "delivered": delivered.duplicate(), "choices": choices.duplicate(), "letters_found": letters_found.duplicate(),
		"log_entries": log_entries.duplicate(true), "set_piece": set_piece.duplicate(true), "storm_seen": storm_seen, "stats": stats.duplicate(), "ever": ever.duplicate(true), "queue": _queue.duplicate(),
		"convoy_open": _convoy_open, "convoy_decided": _convoy_decided, "walked": _walked.duplicate(), "notes_wait": _notes_wait.duplicate(),
		"run_seed": run_seed, "flags": flags.duplicate(), "events_seen": events_seen.duplicate(), "person_traits": person_traits.duplicate(true), "hurt": hurt.duplicate(),
		"night_mods": night_mods.duplicate(true), "weather_over": weather_over.duplicate(), "raid_mod": raid_mod, "event_pending": event_pending.duplicate(true)}


## Puts a saved story back (before the base is built): the arc is `started`, so its first-frame begin (which would deliver the day's beats again) does not run.
func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	weather = String(d.get("weather", "clear"))
	convoy = String(d.get("convoy", "none"))
	delivered = (d.get("delivered", {}) as Dictionary).duplicate()
	choices = (d.get("choices", {}) as Dictionary).duplicate()
	letters_found = (d.get("letters_found", []) as Array).duplicate()
	log_entries = (d.get("log_entries", []) as Array).duplicate(true)
	set_piece = (d.get("set_piece", {}) as Dictionary).duplicate(true)
	storm_seen = bool(d.get("storm_seen", false))
	for k in (d.get("stats", {}) as Dictionary):
		stats[String(k)] = d.stats[k]
	ever = (d.get("ever", {}) as Dictionary).duplicate(true)
	_queue = (d.get("queue", []) as Array).duplicate()
	_convoy_open = bool(d.get("convoy_open", false))
	_convoy_decided = bool(d.get("convoy_decided", false))
	_walked = (d.get("walked", []) as Array).duplicate()
	_notes_wait = (d.get("notes_wait", []) as Array).duplicate()
	run_seed = int(d.get("run_seed", 0))
	flags = (d.get("flags", {}) as Dictionary).duplicate()
	events_seen = (d.get("events_seen", []) as Array).duplicate()
	person_traits = (d.get("person_traits", {}) as Dictionary).duplicate(true)
	hurt = (d.get("hurt", {}) as Dictionary).duplicate()
	night_mods = (d.get("night_mods", {}) as Dictionary).duplicate(true)
	weather_over = (d.get("weather_over", {}) as Dictionary).duplicate()
	raid_mod = String(d.get("raid_mod", ""))
	event_pending = (d.get("event_pending", {}) as Dictionary).duplicate(true)
	started = true
	_last_day = int(game.econ.day)
	day = _last_day
	_start_t = 0.0
	story.log_changed()
