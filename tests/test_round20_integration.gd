extends "res://tests/case.gd"
## Round 20, the three modules TOGETHER (docs/superpowers/plans/2026-10-03-round-20.md, "Tests", orchestrator): a twelve-day avatar game
## on a small start with the REAL relations, specialists and initiative (every other test of the ideas runs them against the fakes of
## tests/initiative_kit.gd), the colony played by the harness's informed policy and the avatar bot of round 19, and a bot that answers
## every idea it can afford (yes) and puts off the rest (later), a game minute after they come.
##
## What it asserts is what the round promises, not how fast the camp forms ties (the rates are the TUNING phase's: thresholds and gains
## in chemistry.json, titles.json and the module constants move with it, and this file must not): the schedule's rules hold in a whole
## game (ideas by day, never in the radio hour, never within the gap (`Initiative.GAP_ALL_MIN`) of one another, nothing open at night or on top of an
## urgent call, an open call never lost from the News, at most two lines a day for bonds and rifts), every yes that is carried out does its
## thing (checked kind by kind from the state after the answer), and the MECHANICS of the community are asserted with a forced affinity,
## a forced practice and a forced circle of friends (a friendship begins and is told, a title is earned and its bonus is on the stat it
## belongs to, a voice stands and gives its opinion under an idea), then through a save from day 6 on (made with an idea waiting, as the game's
## own save writes it: `SaveGame.to_text`) that loads and continues identically (eight game hours on, the digest of the no-avatar test every
## ten seconds of rules time, then the saved states of the three modules, the radio and the whole game, compared number for number), and a
## save made without the three modules (a game from before the round) that loads, names the titles silently and plays on. The second
## half of the twelve days is the LOADED game, played on with a new bot and policy. The days play at 5 steps a second (the digests of the
## no-avatar test play at 15; no rule here cares) so that the file stays near a minute.
##
## The game is played once (`_fixture`, cached in a static variable) and each test reads what it recorded.

const Helpers := preload("res://tests/helpers.gd")
const Balance := preload("res://tools/balance.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const NoAv := preload("res://tests/test_round20_noavatar.gd")
const Initiative := preload("res://scripts/sim/initiative.gd")
const Relations := preload("res://scripts/sim/relations.gd")

const SEED := 1
const CREW := 5
const HZ := 5.0
const LAST_DAY := 12
## The save: at the first moment from 08:00 of day 6 on when an idea waits for an answer, then both games are played on for SPAN_H game
## hours with an answerer that has no memory, and compared. The schedule's own ideas come when the kinds' gaps, the people's gaps and the
## people at home allow (the tuning's numbers, and a day of the small camp may have nobody to ask: the colony is out on a trip), so the
## save waits for one up to the afternoon (SAVE_LATEST_H) of day SAVE_LAST_DAY and only then brings one by `propose_now`.
const SAVE_DAY := 6
const SAVE_LAST_DAY := 9
const SAVE_FROM_H := 8.0
const SAVE_LATEST_H := 16.0
const SPAN_H := 8.0
## A game hour after an idea comes the bot answers it (so that some wait when the save is made).
const ANSWER_AFTER_MIN := 60.0
## Forced events: (day, hour) of the friendship, the practice of a title, the circle that makes a voice. They are checked 45 game minutes
## later, when a slow look (30 game minutes) has passed.
const FRIEND_AT := [4, 10.0]
const TITLE_AT := [4, 11.0]
const VOICE_AT := [5, 9.0]
const LOOK_WAIT_MIN := 45.0

static var _fx := {}


# ----------------------------------------------------------------------- the game --

static func _new_game() -> Dictionary:
	var g := Helpers.avatar_game(SEED, CREW)
	g.sim.storyteller.enabled = true
	return g


static func _fixture() -> Dictionary:
	if _fx.is_empty():
		_fx = _play()
	return _fx


static func _play() -> Dictionary:
	var fx := {
		"ideas": [], "violations": [], "community": {"bond": [], "rift": [], "title": []}, "per_day": {}, "seen_open": {},
		"friend": {}, "title": {}, "voice": {}, "save": {}, "nomod": {}, "final": {},
	}
	var g := _new_game()
	var sim = g.sim
	# 1. day 1 to the save: the colony plays, ideas come and are answered, the three forced things are done and read
	_play_to(sim, fx, SAVE_LAST_DAY, SAVE_LATEST_H, func(s): return int(s.day) >= SAVE_DAY and float(s.hour) >= SAVE_FROM_H and not _open_ideas(s).is_empty())
	if _open_ideas(sim).is_empty():
		sim.initiative.propose_now()    # (the schedule had nothing for all those days: the save is made with an idea waiting all the same, if one can be)
	var open_at_save := _open_ideas(sim).size()
	var text := SaveGame.to_text(SaveGame.to_dict(sim))
	# 2. the same game loaded into a new one; both are played on with an answerer that has no memory
	var h := _new_game()
	var sim_b = h.sim
	var ok: bool = SaveGame.apply(sim_b, SaveGame.from_text(text))
	fx["save"] = {"ok": ok, "bytes": text.length(), "open_ideas": open_at_save, "day": int(sim.day), "hour": float(sim.hour), "digest_same_at_load": NoAv.read(sim).full == NoAv.read(sim_b).full}
	if ok:
		_play_alike(sim, sim_b, fx)
	# 3. a save that has none of the three modules (a game from before the round)
	var old: Dictionary = SaveGame.from_text(text)
	for name in ["relations", "specialists", "initiative"]:
		(old.modules as Dictionary).erase(name)
	var c := _new_game()
	var sim_c = c.sim
	var ok_c: bool = SaveGame.apply(sim_c, old)
	fx["nomod"] = {"ok": ok_c}
	if ok_c:
		_play_without_modules(sim_c, fx)
	c.world.free()
	g.world.free()
	# 4. the loaded game is the one that is played on, to the end of day twelve
	if ok and sim_b.over == "":
		_play_to(sim_b, fx, LAST_DAY + 1, 0.0, Callable())
		fx["final"] = _final_of(sim_b)
	elif ok:
		fx["final"] = _final_of(sim_b)
	h.world.free()
	return fx


static func _final_of(sim) -> Dictionary:
	var alive := 0
	for p in sim.people:
		if not (p.dead or p.turned):
			alive += 1
	return {"day": int(sim.day), "over": String(sim.over), "alive": alive, "counts": sim.initiative.stats(), "people": sim.people.size()}


static func _open_ideas(sim) -> Array:
	var out: Array = []
	for e in sim.radio.open_calls():
		if String(e.kind) == "idea" and not bool(e.data.get("synthetic", false)):
			out.append(e)
	return out


## Plays `sim` (the bot at the wall, the harness's informed policy, the answerer of ideas) up to `day` and `hour`, or until `stop` says so.
static func _play_to(sim, fx: Dictionary, day: int, hour: float, stop: Callable) -> void:
	var bot = BotLib.AvatarBot.new(sim, "bot")
	var policy = Balance.policy_for(sim, false, true)
	var dt := 1.0 / HZ
	var every := roundi(HZ)
	var step := 0
	while sim.over == "" and not (int(sim.day) > day or (int(sim.day) == day and float(sim.hour) >= hour)):
		bot.step(dt)
		var before_id: int = sim.radio.latest_id()
		sim.update(dt)
		step += 1
		if sim.radio.latest_id() != before_id:
			_watch_news(sim, fx, before_id, true)
		if step % every == 0:
			policy.tick()
			var mark: int = sim.radio.latest_id()
			_second(sim, fx)
			if sim.radio.latest_id() != mark:
				_watch_news(sim, fx, mark, false)    # (what the answers and the forcing wrote: the community's lines, not ideas raised by hand)
			if stop.is_valid() and bool(stop.call(sim)):
				return


# ------------------------------------------------------------------- the watching --

## The entries that came in this step: the ideas (the schedule's rules are read off them) and the community's lines.
static func _watch_news(sim, fx: Dictionary, before_id: int, ideas: bool) -> void:
	for e in sim.radio.news_since(before_id):
		var kind := String(e.kind)
		if kind == "idea":
			if ideas and not (e.options as Array).is_empty() and not bool(e.data.get("synthetic", false)):
				_note_idea(sim, fx, e, before_id)
		elif kind == "bond" or kind == "rift" or kind == "title":
			(fx.community[kind] as Array).append({"text": String(e.text), "sub": String(e.sub), "day": int(e.day)})
			if kind != "title":
				var key := "%d" % int(e.day)
				fx.per_day[key] = int(fx.per_day.get(key, 0)) + 1


static func _note_idea(sim, fx: Dictionary, e: Dictionary, before_id: int) -> void:
	var dusk: float = sim.seasons.dusk_hour()
	var h := float(e.hour)
	var idea := {
		"id": int(e.id), "kind": String(e.data.get("idea", "")), "who": String(e.data.get("who", "")), "day": int(e.day), "hour": h, "t": float(e.t),
		"life_min": float(e.due) - float(e.t), "answered": "", "result": "", "effect": "", "cost": (e.data.get("cost", {}) as Dictionary).duplicate(),
	}
	var ideas: Array = fx.ideas
	var last_hour := minf(Initiative.HOURS_TO, dusk - Initiative.LAST_BEFORE_DUSK_H)
	var why: Array = []
	if int(e.day) < Initiative.FIRST_DAY:
		why.append("before day 3")
	if h < Initiative.HOURS_FROM - 0.011 or h > last_hour + 0.011:
		why.append("at %.2fh" % h)
	if h >= Initiative.RADIO_FROM_H + 0.011 and h <= Initiative.RADIO_TO_H - 0.011:
		why.append("in the radio hour")
	if not ideas.is_empty() and float(e.t) - float(ideas[ideas.size() - 1].t) < Initiative.GAP_ALL_MIN - 0.01:
		why.append("%.0f game minutes after the last" % (float(e.t) - float(ideas[ideas.size() - 1].t)))
	if h + idea.life_min / 60.0 > dusk + 0.011:
		why.append("a life of %.0f minutes from %.2fh goes past the dusk (%.1fh)" % [idea.life_min, h, dusk])
	for o in sim.radio.open_calls():
		if String(o.kind) != "idea" and int(o.id) <= before_id:
			why.append("raised over an open %s call" % String(o.kind))
	if not why.is_empty():
		(fx.violations as Array).append("idea #%d (%s) on day %d: %s" % [int(e.id), idea.kind, int(e.day), "; ".join(why)])
	ideas.append(idea)


## What is read once a second: no idea open at night, no open call lost from the log, the answerer, the forced events.
static func _second(sim, fx: Dictionary) -> void:
	if String(sim.phase) != "day":
		for e in sim.radio.open_calls():
			if String(e.kind) == "idea":
				(fx.violations as Array).append("an idea (#%d) is open at %s on day %d (phase %s)" % [int(e.id), str(sim.hour), int(sim.day), String(sim.phase)])
	var open_now := {}
	for e in sim.radio.open_calls():
		open_now[int(e.id)] = true
		fx.seen_open[int(e.id)] = true
	for id in fx.seen_open.keys():
		if not open_now.has(id) and (sim.radio._entry(int(id)).is_empty()):
			(fx.violations as Array).append("call #%d was open and is gone from the News unanswered" % int(id))
			fx.seen_open.erase(id)
		elif not open_now.has(id):
			fx.seen_open.erase(id)
	_answer_ideas(sim, fx, ANSWER_AFTER_MIN)
	_force(sim, fx)


## The bot: every idea it can afford a "yes" (and the effect is read off the state), the others a "later"; each after `after_min` game minutes.
static func _answer_ideas(sim, fx: Dictionary, after_min: float) -> void:
	for e in _open_ideas(sim):
		if float(sim.clock_min) - float(e.t) < after_min:
			continue
		var affordable := true
		var cost: Dictionary = e.data.get("cost", {})
		for k in cost:
			if float(sim.stock.get(String(k), 0.0)) + 1.0e-9 < float(cost[k]):
				affordable = false
		var before := _before(sim)
		var id := int(e.id)
		sim.radio.answer(id, "yes" if affordable else "later")
		var done: Dictionary = sim.radio._entry(id)
		for idea in fx.ideas:
			if int(idea.id) == id:
				idea["answered"] = String(done.answered)
				idea["result"] = String(done.result)
				if affordable and not String(done.result).begins_with("Not now"):
					idea["effect"] = "seen" if _effect_seen(sim, e, before) else "NONE"
				elif affordable:
					idea["effect"] = "not now"


## The state a yes can change, before it is given.
static func _before(sim) -> Dictionary:
	var jobs := {}
	var morale := {}
	for p in sim.people:
		jobs[String(p.id)] = String(sim.jobs.job_of(p))
		morale[String(p.id)] = float(sim.morale.value(p))
	return {
		"food": float(sim.stock.food), "bench": float(sim.jobs.setting("bench", "ammo_target")), "line": float(sim.jobs.setting("builders", "repair_below")),
		"posts": (sim.jobs.post_ids as Dictionary).duplicate(), "jobs": jobs, "waits": sim.radio.errand_wait.size(), "doing": sim.initiative.doing.size(), "morale": morale,
	}


## Whether the yes did its thing (the kind's own effect, from the state right after the answer).
static func _effect_seen(sim, e: Dictionary, before: Dictionary) -> bool:
	var who = _person(sim, String(e.data.get("who", "")))
	var args: Dictionary = e.data.get("args", {}) if e.data.get("args", {}) is Dictionary else {}
	var others: Array = e.data.get("others", [])
	match String(e.data.get("idea", "")):
		"fix_wall":
			return who != null and who.repair != null
		"build":
			return not sim.build.active_site().is_empty()
		"bench_target":
			return float(sim.jobs.setting("bench", "ammo_target")) > float(before.bench)
		"wall_line":
			return float(sim.jobs.setting("builders", "repair_below")) > float(before.line)
		"desk":
			return String(sim.jobs.job_of(who)) == String(args.get("station", "?"))
		"garden":
			return not others.is_empty() and String(sim.jobs.job_of(_person(sim, String(others[0])))) == "garden"
		"errand":
			return sim.radio.errand_wait.size() > int(before.waits)
		"swap_posts", "post_beside":
			return (sim.jobs.post_ids as Dictionary) != (before.posts as Dictionary)
		"quarrel":
			if (sim.jobs.post_ids as Dictionary) != (before.posts as Dictionary):
				return true
			for p in sim.people:
				if String(sim.jobs.job_of(p)) != String(before.jobs.get(String(p.id), "")):
					return true
			return false
		"supper":
			return float(sim.stock.food) < float(before.food) - 1.5
		"lesson":
			return sim.initiative.doing.size() > int(before.doing)
		"farewell":
			for p in sim.people:
				if absf(float(sim.morale.value(p)) - float(before.morale.get(String(p.id), 0.0))) > 0.01 and String(p.id) != String(e.data.get("who", "")):
					return true
			return false
	return true


static func _person(sim, id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


# --------------------------------------------------------------------- the forcing --

## The three things the rates may or may not bring in twelve days, made to happen so that what follows them can be asserted: a friendship
## (two people who are no pair of the roster and have no kind, the affinity of a friend), a title (a person with the skill and the practice
## of a medic), a voice (a person with three friends). Each is read 45 game minutes later (a slow look is 30).
static func _force(sim, fx: Dictionary) -> void:
	var now := float(sim.clock_min)
	if fx.friend.is_empty() and _at_or_after(sim, FRIEND_AT):
		var pair := _free_pair(sim)
		if not pair.is_empty():
			sim.relations.add(pair[0], pair[1], Relations.FRIEND_AT + 15.0, "forced by the integration test")
			fx.friend = {"a": String(pair[0].id), "b": String(pair[1].id), "first_a": String(pair[0].first), "first_b": String(pair[1].first), "read_at": now + LOOK_WAIT_MIN}
	elif not fx.friend.is_empty() and not fx.friend.has("kind") and now >= float(fx.friend.read_at):
		var a = _person(sim, String(fx.friend.a))
		var b = _person(sim, String(fx.friend.b))
		var listed := false
		for row in sim.bonds.of(a):
			if row.who == b and String(row.role) == "friend":
				listed = true
		fx.friend["kind"] = String(sim.relations.kind(a, b))
		fx.friend["bonded"] = sim.bonds.bonded(a, b)
		fx.friend["listed"] = listed
		fx.friend["described"] = false
		for f in sim.relations.describe(a).get("friends", []):
			if String(f.id) == String(b.id):
				fx.friend["described"] = true
	if fx.title.is_empty() and _at_or_after(sim, TITLE_AT):
		var best = null
		for p in sim.people:
			if not (p.dead or p.turned or p.player) and (best == null or int(p.skills.get("Medicine", 0)) > int(best.skills.get("Medicine", 0))):
				best = p
		if best != null:
			best.stats["treated"] = 12.0
			fx.title = {"who": String(best.id), "first": String(best.first), "held_before": String(sim.specialists.title_of(best).get("id", "")), "read_at": now + LOOK_WAIT_MIN}
	elif not fx.title.is_empty() and not fx.title.has("holder") and now >= float(fx.title.read_at):
		var p = _person(sim, String(fx.title.who))
		var holder = sim.specialists.holder("medic")
		fx.title["holder"] = String(holder.id) if holder != null else ""
		fx.title["title_of"] = String(sim.specialists.title_of(p).get("id", ""))
		fx.title["bandage"] = float(sim.traits.mult(p, "bandage"))
		fx.title["cure"] = float(sim.traits.add(p, "cure"))
		fx.title["bandage_other"] = float(sim.traits.mult(_person(sim, "ruth"), "bandage"))
	if fx.voice.is_empty() and _at_or_after(sim, VOICE_AT):
		var chosen := _circle_of_three(sim)
		if not chosen.is_empty():
			fx.voice = {"who": String(chosen[0].id), "read_at": now + LOOK_WAIT_MIN}
	elif not fx.voice.is_empty() and not fx.voice.has("voice") and now >= float(fx.voice.read_at):
		var v = sim.relations.voice()
		fx.voice["voice"] = String(v.id) if v != null else ""
		fx.voice["standing"] = float(sim.relations.standing(v)) if v != null else 0.0
		fx.voice["opinion"] = _opinion_under_an_idea(sim, v)


static func _at_or_after(sim, when: Array) -> bool:
	return int(sim.day) > int(when[0]) or (int(sim.day) == int(when[0]) and float(sim.hour) >= float(when[1]))


## Two living people at the base, neither the player, no pair of the roster and with no kind between them yet.
static func _free_pair(sim) -> Array:
	var here: Array = []
	for p in sim.people:
		if not (p.dead or p.turned or p.downed or p.player) and p.away == null:
			here.append(p)
	for i in here.size():
		for j in range(i + 1, here.size()):
			if sim.relations.friends_of(here[i]).size() >= Relations.MAX_FRIENDS or sim.relations.friends_of(here[j]).size() >= Relations.MAX_FRIENDS:
				continue
			if not sim.bonds.bonded(here[i], here[j]) and String(sim.relations.kind(here[i], here[j])) == "" and float(sim.relations.affinity(here[i], here[j])) < Relations.FRIEND_AT - 20.0:
				return [here[i], here[j]]
	return []


## A person and three others made friends of theirs (a standing that makes a voice); [the person, ...] or [].
static func _circle_of_three(sim) -> Array:
	var here: Array = []
	for p in sim.people:
		if not (p.dead or p.turned or p.downed or p.player) and p.away == null:
			here.append(p)
	if here.size() < 4:
		return []
	here.sort_custom(func(x, y): return sim.relations.friends_of(x).size() < sim.relations.friends_of(y).size())
	for i in range(1, 4):
		sim.relations.add(here[0], here[i], Relations.FRIEND_AT + 25.0, "forced by the integration test")
	return [here[0], here[1], here[2], here[3]]


## An idea that somebody other than the voice brings (made by hand, marked so that the statistics leave it out) and what the voice says of it.
static func _opinion_under_an_idea(sim, voice) -> Dictionary:
	if voice == null:
		return {}
	var other = null
	for p in sim.people:
		if p != voice and not (p.dead or p.turned or p.downed or p.player) and p.away == null:
			other = p
			break
	if other == null:
		return {}
	var id: int = sim.radio.raise_call("idea", "%s: a spare supper" % other.first, "", [{"id": "yes", "label": "Yes"}, {"id": "later", "label": "Later"}, {"id": "no", "label": "No"}], "later", 60.0, {"idea": "supper", "who": String(other.id), "others": [], "args": {}, "cost": {"food": 1}, "synthetic": true}, null)
	var e: Dictionary = sim.radio._entry(id)
	var o: Dictionary = sim.initiative.voice_opinion(e)
	sim.radio.answer(id, "later")
	return o


# --------------------------------------------------------------------- the save --

## The two games, the one that was saved and the one that was loaded from it, played on for SPAN_H game hours with an answerer that has no memory
## (every idea that waits is answered yes when it can be paid for, else later); compared once every ten seconds of rules time by the
## digest of the no-avatar test (the clock, the stocks, every person, the radio's log, the dice), and at the end by the three modules'
## saves and by the whole save, as text.
static func _play_alike(a, b, fx: Dictionary) -> void:
	var dt := 1.0 / HZ
	var n := int(SPAN_H * 20.0 * HZ)
	var first_diff := -1
	var drift := ""
	var compared := 0
	for i in n:
		a.update(dt)
		b.update(dt)
		if i % roundi(HZ) == roundi(HZ) - 1:
			_stateless_answers(a)
			_stateless_answers(b)
		if i % roundi(HZ * 10.0) == roundi(HZ * 10.0) - 1:
			compared += 1
			var da: String = NoAv.read(a).full
			var db: String = NoAv.read(b).full
			if da != db and first_diff < 0:
				first_diff = i
				drift = NoAv.first_drift(da, db)
	var same := {}
	var da_all: Dictionary = SaveGame.to_dict(a)
	var db_all: Dictionary = SaveGame.to_dict(b)
	for name in ["relations", "specialists", "initiative", "radio"]:
		same[name] = _first_diff(da_all.modules[name], db_all.modules[name], name)
	fx.save["compared"] = compared
	fx.save["first_diff"] = first_diff
	fx.save["drift"] = drift
	fx.save["modules_same"] = same
	fx.save["full_diff"] = _first_diff(da_all, db_all, "save")
	fx.save["raised_a"] = int(a.initiative.stats().raised)
	fx.save["raised_b"] = int(b.initiative.stats().raised)
	fx.save["news_a"] = a.radio.news.size()
	fx.save["news_b"] = b.radio.news.size()
	fx.save["rng_same"] = a.rng.state == b.rng.state


## Where two saved states first differ ("" when they do not): numbers are numbers (a save's text gives whole floats back for ints), and
## a key that holds only an empty string is no key (the jobs module writes a job of "" for a person without one when it loads).
static func _first_diff(a, b, path: String) -> String:
	var an: bool = typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var bn: bool = typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if an and bn:
		return "" if float(a) == float(b) else "%s: %s against %s" % [path, str(a), str(b)]
	if typeof(a) != typeof(b):
		return "%s: %s against %s" % [path, str(a).substr(0, 60), str(b).substr(0, 60)]
	if a is Dictionary:
		for k in a:
			if typeof(a[k]) == TYPE_STRING and a[k] == "":
				continue
			if not b.has(k):
				return "%s.%s is only in the first" % [path, str(k)]
			var d := _first_diff(a[k], b[k], "%s.%s" % [path, str(k)])
			if d != "":
				return d
		for k in b:
			if typeof(b[k]) == TYPE_STRING and b[k] == "":
				continue
			if not a.has(k):
				return "%s.%s is only in the second" % [path, str(k)]
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: %d entries against %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := _first_diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s against %s" % [path, str(a).substr(0, 60), str(b).substr(0, 60)]


static func _stateless_answers(sim) -> void:
	for e in sim.radio.open_calls():
		if String(e.kind) != "idea":
			continue
		var affordable := true
		var cost: Dictionary = e.data.get("cost", {})
		for k in cost:
			if float(sim.stock.get(String(k), 0.0)) + 1.0e-9 < float(cost[k]):
				affordable = false
		sim.radio.answer(int(e.id), "yes" if affordable else "later")


## The game made from a save without the modules: the first evaluation of the titles (silent: the camp is not told what it earned before), then
## a few game hours of play.
static func _play_without_modules(sim, fx: Dictionary) -> void:
	var dt := 1.0 / HZ
	var titles_before := 0
	for e in sim.radio.news:
		if String(e.kind) == "title":
			titles_before += 1
	sim.specialists.look()
	var titles_after := 0
	for e in sim.radio.news:
		if String(e.kind) == "title":
			titles_after += 1
	var held: Array = []
	for t in ["medic", "engineer", "marksman", "scout"]:
		var h = sim.specialists.holder(t)
		if h != null:
			held.append("%s=%s" % [t, String(h.id)])
	fx.nomod["new_title_lines"] = titles_after - titles_before
	fx.nomod["held"] = held
	fx.nomod["active"] = sim.relations.active() and sim.specialists.active() and sim.initiative.active()
	fx.nomod["pairs"] = sim.relations.pairs.size()
	fx.nomod["records"] = sim.initiative.records.size()
	for i in int(4.0 * 20.0 * HZ):
		sim.update(dt)
		if i % roundi(HZ) == roundi(HZ) - 1:
			_stateless_answers(sim)
	fx.nomod["over"] = String(sim.over)
	fx.nomod["day"] = int(sim.day)


# ======================================================================== the tests ==

func test_ideas_arrive_by_the_schedule_and_are_carried_out_over_twelve_days() -> void:
	var fx := _fixture()
	var ideas: Array = fx.ideas
	check(ideas.size() >= 5, "ideas came (%d in the game)" % ideas.size())
	var kinds := {}
	var yes := 0
	for idea in ideas:
		kinds[idea.kind] = true
		if String(idea.answered) == "yes" and String(idea.effect) != "not now":
			yes += 1
	check(kinds.size() >= 3, "of several kinds: %s" % str(kinds.keys()))
	check(yes >= 3, "and several were carried out (%d yes)" % yes)
	for idea in ideas:
		if String(idea.effect) == "NONE":
			check(false, "a yes to the %s idea of %s (day %d) did nothing: %s" % [idea.kind, idea.who, idea.day, idea.result])
		if String(idea.effect) == "seen":
			check(String(idea.result) != "", "the %s idea says what came of it" % idea.kind)
	for v in fx.violations:
		check(false, "the schedule was broken: %s" % v)
	check(int(fx.final.get("day", 0)) >= LAST_DAY or String(fx.final.get("over", "")) != "", "twelve days were played (or the camp fell): %s" % str(fx.final))
	check(int(fx.final.get("counts", {}).get("raised", 0)) >= ideas.size() - 1, "the module's own count agrees: %s" % str(fx.final.get("counts", {})))


func test_no_more_than_two_bond_and_rift_lines_a_day() -> void:
	var fx := _fixture()
	for day in fx.per_day:
		check(int(fx.per_day[day]) <= Relations.NEWS_PER_DAY, "day %s: %d lines of bonds and rifts" % [day, int(fx.per_day[day])])


func test_a_friendship_begins_is_listed_and_is_told() -> void:
	var fx := _fixture()
	var f: Dictionary = fx.friend
	check(not f.is_empty() and f.has("kind"), "a pair was made friends and read: %s" % str(f))
	if not f.has("kind"):
		return
	eq(f.kind, "friend", "%s and %s are friends" % [f.first_a, f.first_b])
	check(bool(f.bonded), "the bonds module says they are bonded (morale's near friend, the aim bonus and grief follow)")
	check(bool(f.listed), "the person's bonds list the friend")
	check(bool(f.described), "and the person panel's description")
	var told := false
	for line in fx.community.bond:
		if String(line.text).contains(String(f.first_a)) and String(line.text).contains(String(f.first_b)) and String(line.text).ends_with("are close now"):
			told = true
	check(told, "the News says so (%s): %s" % [str(f), str(fx.community.bond)])


func test_a_title_is_earned_with_its_bonus_on_the_work_it_belongs_to() -> void:
	var fx := _fixture()
	var t: Dictionary = fx.title
	check(not t.is_empty() and t.has("holder"), "a person with the skill and the practice was read: %s" % str(t))
	if not t.has("holder"):
		return
	eq(t.title_of, "medic", "%s is the medic" % t.first)
	eq(t.holder, t.who, "the medic's holder is %s" % t.first)
	check(float(t.bandage) > float(t.bandage_other) + 0.01, "the bandage is quicker for the medic (%.3f against %.3f)" % [float(t.bandage), float(t.bandage_other)])
	check(float(t.cure) > 0.0, "and the cure better (+%.3f)" % float(t.cure))
	var told := false
	for line in fx.community.title:
		if String(line.text).contains(String(t.first)) and String(line.text).contains("medic"):
			told = true
	check(told or String(t.held_before) == "medic", "the News says so: %s" % str(fx.community.title))


func test_a_voice_stands_and_gives_its_opinion_under_an_idea() -> void:
	var fx := _fixture()
	var v: Dictionary = fx.voice
	check(not v.is_empty() and v.has("voice"), "a circle of friends was made and read: %s" % str(v))
	if not v.has("voice"):
		return
	check(String(v.voice) != "", "somebody is the one people turn to")
	check(float(v.standing) >= Relations.VOICE_MIN, "with the standing for it (%.1f)" % float(v.standing))
	var o: Dictionary = v.opinion
	check(not o.is_empty(), "and the voice has an opinion under an idea that is not theirs")
	if not o.is_empty():
		check(String(o.line).begins_with(String(o.first)), "in their own words: %s" % String(o.line))
		check(["yes", "later"].has(String(o.option)), "yes or later: %s" % String(o.option))


func test_a_save_from_day_six_on_with_an_idea_waiting_loads_and_continues_identically() -> void:
	var fx := _fixture()
	var s: Dictionary = fx.save
	check(bool(s.get("ok", false)), "the save of day %d loads (%d bytes)" % [int(s.get("day", 0)), int(s.get("bytes", 0))])
	if not bool(s.get("ok", false)):
		return
	check(int(s.open_ideas) >= 1, "(it was made with an idea waiting for its answer)")
	check(bool(s.digest_same_at_load), "the loaded game is the saved one, to the digest")
	eq(int(s.first_diff), -1, "the two games keep the same digest for %d game hours (%d comparisons): %s" % [int(SPAN_H), int(s.get("compared", 0)), str(s.get("drift", ""))])
	for name in s.modules_same:
		eq(String(s.modules_same[name]), "", "the %s module's state is the same after the stretch" % name)
	check(bool(s.rng_same), "the dice are in the same place")
	eq(int(s.news_a), int(s.news_b), "the News has the same length")
	eq(String(s.full_diff), "", "the whole saves of the two are the same")
	check(int(s.raised_a) == int(s.raised_b), "the same ideas were raised (%d, %d)" % [int(s.raised_a), int(s.raised_b)])


func test_a_save_made_without_the_three_modules_loads_names_titles_silently_and_plays_on() -> void:
	var fx := _fixture()
	var n: Dictionary = fx.nomod
	check(bool(n.get("ok", false)), "a save from before the round loads")
	if not bool(n.get("ok", false)):
		return
	check(bool(n.active), "the modules run (an avatar game on a small start) with nothing remembered")
	check(int(n.pairs) > 0, "the roster's friends are in their pairs again")
	eq(int(n.records), 0, "and no idea has been asked yet")
	eq(int(n.new_title_lines), 0, "the titles are named silently (no 'is the camp's medic now' for what was earned before): %s" % str(n.held))
	check((n.held as Array).size() > 0, "and they are named (the practice and the skills are the people's own): %s" % str(n.held))
	eq(String(n.over), "", "the camp plays on")
