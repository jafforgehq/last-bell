## The community probe (round 20, phase 2: docs/superpowers/plans/2026-10-03-round-20.md): plays avatar games of the settlement start
## headless and prints how the community fared: the ideas it brought and what was said to them, what they cost, who became friends,
## rivals, a couple, who earned a title, who became the voice, how the crew felt, and whether the colony survived.
##
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --headless --path . --script res://tools/community_probe.gd -- --games=3 --days=10 --seed=1 --crew=5 --policy=affordable [--noideas] [--out=path.json] [--save=path]
##
## Each game is a game of tools/balance.gd: the colony is played by `Balance.Policy` (the informed one by default: it builds, claims lots,
## places the crew at dusk, answers the storyteller's cards), Ruth is the player, and what she does with her hands is `--avatar`:
## `idle` stands still deep in the school gym (round 19's lab `idle`: the community alone holds the nights), `gate` stands still at the
## gate (the people of the day see her there), `bot` is round 19's avatar bot (tools/avatar_bot.gd: walks to the wall the night will break
## on, shoots, answers the night's calls). What she says to the community's ideas is `--policy`, and it is the probe's, never the bot's:
##   accept      yes to every idea (the community's best case; ideas that cannot be done say "Not now" and count as a later)
##   affordable  yes to an idea when what it costs leaves `--keep-scrap` scrap and `--keep-food` food in the stores, else later (default)
##   refuse      no to every idea (the worst case: three refusals and a person falls silent)
## An idea is read for `--read` game minutes (default 20) before it is answered; one that is not answered runs out to "later" in six hours.
##
## Flags (all optional):
##   --games=N          how many games (seeds seed, seed+1, ...)                              default 3
##   --seed=N, --seeds=a,b,c   the first seed, or exactly these seeds                         default 1
##   --days=N           a game ends when day N+1 dawns, or when everyone is gone              default 10
##   --crew=N           the small start's crew, 3 to 5 (6 is the classic start: the modules are off there)   default 5
##   --difficulty=N     0 story, 1 standard, 2 brutal                                         default 1
##   --policy=accept|affordable|refuse   how the player answers an idea                      default affordable
##   --noideas          the initiative module off (relations and specialists stay on): the same game with no ideas
##   --nocommunity      all three modules of the round off (the avatar game of before the round)
##   --base             round 25: the base management (briefing, priorities, dials, problems, dilemma) is ON; without it the five modules are OFF (the numbers of round 20
##                      hold). `--nobase` says the default out loud
##   --colony=informed|default|none   who plays the colony (the harness's policies)          default informed
##   --avatar=idle|gate|bot   what Ruth does with her hands                                   default idle
##   --hz=N, --fast     rules steps a second (default 15; --fast is 15, kept for the harness's habit)
##   --read=N           game minutes an idea is read before it is answered                    default 20
##   --keep-scrap=N, --keep-food=N   what `affordable` leaves in the stores                    default 5 and 10
##   --verbose          every idea, every line of News of the community, game by game
##   --out=path.json    write every game, every day and every idea as JSON
##   --save=path        write a save (SaveGame) of the first game: from `--save-day` (default the last day) at the first moment an idea
##                      is open on the radio, or at the end of that game when none is (the staged game for the film)
##   --save-day=N       see --save
##   --quiet            print nothing (a worker's)
## A game costs about 6 to 12 s of processor time for each game day at 15 Hz (more with the bot, more on a busy machine).
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")
const Balance := preload("res://tools/balance.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")

const TITLES := ["medic", "engineer", "marksman", "scout"]
## The kinds of News the community writes.
const NEWS_KINDS := ["idea", "bond", "rift", "title"]
const POLICIES := ["accept", "affordable", "refuse"]
const AVATARS := ["idle", "gate", "bot"]
## The plan's targets for 10 days at crew 5 with `affordable` (the verdict lines say which a run meets).
const IDEAS_MIN := 5
const IDEAS_MAX := 12
const GAP_MIN_H := 4.0
const FRIENDS_MIN := 1
const FRIENDS_MAX := 3
const RIVALS_MAX := 2
const COUPLES_MAX := 1
const TITLES_MIN := 1
const TITLES_MAX := 3
const VOICE_BY_DAY := 6
const MOOD_LOSS_MAX := 2.0
const SCRAP_SHARE_MAX := 0.25


# ============================================================================= the player's answers ==

## Answers the ideas on the radio the way the policy says, after the time it takes to read them.
class Answerer:
	extends RefCounted

	var sim
	var policy := "affordable"
	var read_min := 20.0
	var keep_scrap := 12.0
	var keep_food := 10.0
	var _seen := {}
	## What was said: {"yes", "no", "later"} and the yes that came back "Not now".
	var said := {"yes": 0, "no": 0, "later": 0}
	## id -> the option said.
	var answers := {}

	func _init(s) -> void:
		sim = s

	## Once a second of rules time.
	func tick() -> void:
		for e in sim.radio.open_calls():
			if String(e.kind) != "idea":
				continue
			var id := int(e.id)
			if not _seen.has(id):
				_seen[id] = float(sim.clock_min)
				continue
			if float(sim.clock_min) - float(_seen[id]) < read_min:
				continue
			var option := _choose(e)
			if sim.radio.answer(id, option):
				said[option] = int(said[option]) + 1
				answers[id] = option

	func _choose(e: Dictionary) -> String:
		match policy:
			"accept":
				return "yes"
			"refuse":
				return "no"
		var cost: Dictionary = e.data.get("cost", {}) if e.data.get("cost", {}) is Dictionary else {}
		if float(cost.get("scrap", 0.0)) > float(sim.stock.scrap) - keep_scrap and float(cost.get("scrap", 0.0)) > 0.0:
			return "later"
		if float(cost.get("food", 0.0)) > float(sim.stock.food) - keep_food and float(cost.get("food", 0.0)) > 0.0:
			return "later"
		return "yes"


# ============================================================================= one game ==

## Plays one game and returns what happened: {"seed", "policy", "outcome" ("survived" or "defeat"), "day", "rows" (one for the start of each
## day and one at the end), "ideas" (one for each idea raised), "news" (the community's lines), "scrap_in", "scrap_ideas", "food_ideas",
## "min_gap_h", "voice" ({"day", "hour", "who"} or {}), "titles" ({title: {"day", "who"}} the first time each was named), "practice",
## "end" (the community at the end), "took"}.
static func play(opts: Dictionary, seed_value: int, save_state: Dictionary) -> Dictionary:
	var started := Time.get_ticks_msec()
	var days: int = opts.days
	var hz: float = opts.hz
	var g := Helpers.make(seed_value, int(opts.difficulty), int(opts.crew), false)
	var sim = g.sim
	sim.streets.enabled = true
	sim.storyteller.enabled = true
	sim.avatar.set_player("ruth")
	if not bool(opts.get("base", false)):
		Helpers.quiet_base(sim)    # (round 25: the base management is off unless --base)
	if bool(opts.nocommunity):
		sim.relations.enabled = false
		sim.specialists.enabled = false
		sim.initiative.enabled = false
	elif bool(opts.noideas):
		sim.initiative.enabled = false
	var mode := "bot" if String(opts.avatar) == "bot" else "idle"
	var bot = BotLib.AvatarBot.new(sim, mode)
	if String(opts.avatar) == "gate":
		var po: Dictionary = sim.jobs.post("gate")
		if not po.is_empty():
			bot.put_at(Vector2(po.pos))
	var answerer := Answerer.new(sim)
	answerer.policy = String(opts.policy)
	answerer.read_min = float(opts.read)
	answerer.keep_scrap = float(opts.keep_scrap)
	answerer.keep_food = float(opts.keep_food)
	var policy = Balance.policy_for(sim, false, String(opts.colony) == "informed")
	var orders: bool = String(opts.colony) != "none"
	var dt := 1.0 / hz
	var every := maxi(1, roundi(hz))
	var rows: Array = []
	var last_day: int = sim.day
	var step := 0
	var scrap_was := float(sim.stock.scrap)
	var scrap_in := 0.0
	var tracker := {"last_news": sim.radio.latest_id(), "ideas": {}, "idea_order": [], "news": [], "voice": {}, "titles": {}, "saved": false, "voice_id": "", "lost": [], "gone": {}, "was_away": {}, "ever": {"friend": {}, "rival": {}, "partner": {}}}
	rows.append(_row(sim, answerer))
	while sim.over == "" and sim.day <= days:
		if mode == "bot":
			bot.step(dt)
		# (the salvage bench pays a little every step while the bench uses some: the step's net would hide it, so it is counted by itself)
		var salvage: float = sim.build.SALVAGE_PER_HOUR * float(sim.jobs.working("salvage").size()) * sim.game_hours(dt)
		sim.update(dt)
		var scrap_now := float(sim.stock.scrap)
		scrap_in += salvage + maxf(0.0, scrap_now - scrap_was - salvage)
		scrap_was = scrap_now
		step += 1
		if sim.day != last_day:
			last_day = sim.day
			rows.append(_row(sim, answerer))
		if step % every != 0:
			continue
		if orders:
			policy.tick()
		answerer.tick()
		_watch(sim, tracker, answerer)
		if not save_state.is_empty() and not bool(save_state.done) and sim.day >= int(save_state.day) and not sim.radio.open_calls().is_empty():
			for e in sim.radio.open_calls():
				if String(e.kind) == "idea":
					save_state["done"] = SaveGame.write(sim, String(save_state.path))
					save_state["at"] = "day %d %05.2f" % [sim.day, sim.hour]
					break
	_watch(sim, tracker, answerer)
	rows.append(_row(sim, answerer))
	if not save_state.is_empty() and not bool(save_state.done):
		save_state["done"] = SaveGame.write(sim, String(save_state.path))
		save_state["at"] = "the end (day %d %05.2f, no idea open)" % [sim.day, sim.hour]
	var survived: bool = (sim.over == "" and sim.day > days) or sim.over == "victory"
	var ideas: Array = []
	for id in tracker.idea_order:
		ideas.append(tracker.ideas[id])
	var min_gap := INF
	for i in range(1, ideas.size()):
		min_gap = minf(min_gap, (float(ideas[i].t) - float(ideas[i - 1].t)) / 60.0)
	var stats: Dictionary = sim.initiative.stats()
	var bench := 0.0
	for p in sim.people:
		bench += float(p.stats.get("crafted", 0.0))
	var result := {
		"seed": seed_value,
		"policy": String(opts.policy),
		"outcome": "survived" if survived else "defeat",
		"days": days,
		"day": mini(sim.day, days) if survived else sim.day,
		"rows": rows,
		"ideas": ideas,
		"news": tracker.news,
		"lost": tracker.lost,
		"ever": {"friends": (tracker.ever.friend as Dictionary).size(), "rivals": (tracker.ever.rival as Dictionary).size(), "couples": (tracker.ever.partner as Dictionary).size(), "pairs": tracker.ever},
		"scrap_in": snappedf(scrap_in, 0.1),
		"scrap_bench": snappedf(bench, 0.1),
		"scrap_ideas": snappedf(float(stats.get("scrap", 0.0)), 0.1),
		"food_ideas": snappedf(float(stats.get("food", 0.0)), 0.1),
		"by_kind": stats.get("by_kind", {}),
		"min_gap_h": snappedf(min_gap, 0.01) if min_gap < INF else -1.0,
		"voice": tracker.voice,
		"titles": tracker.titles,
		"practice": _practice(sim),
		"end": _community(sim),
		"alive": int(rows[rows.size() - 1].alive),
		"took": snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1),
	}
	g.world.free()
	return result


## Once a second: the News the community wrote, the ideas (when they were raised, how they were answered), when the voice and each title
## first appeared.
static func _watch(sim, tracker: Dictionary, answerer) -> void:
	for e in sim.radio.news_since(int(tracker.last_news)):
		tracker.last_news = int(e.id)
		var kind := String(e.kind)
		if NEWS_KINDS.has(kind):
			tracker.news.append({"day": int(e.day), "hour": float(e.hour), "kind": kind, "text": String(e.text), "sub": String(e.sub)})
		if kind == "idea" and not e.options.is_empty():
			tracker.ideas[int(e.id)] = {"id": int(e.id), "day": int(e.day), "hour": float(e.hour), "t": float(e.t), "kind": String(e.data.get("idea", "")), "who": String(e.data.get("who", "")),
				"text": String(e.text), "cost": e.data.get("cost", {}), "answer": "", "by_default": false, "result": ""}
			tracker.idea_order.append(int(e.id))
	for key in sim.relations.pairs:
		var pr: Dictionary = sim.relations.pairs[key]
		var kind := String(pr.kind)
		if kind != "" and (kind != "friend" or sim.relations._roster_kind(String(pr.a), String(pr.b)) == ""):
			if not tracker.ever[kind].has(key) and not sim.relations._is_player(String(pr.a)) and not sim.relations._is_player(String(pr.b)):
				tracker.ever[kind][key] = {"day": int(sim.day), "hour": snappedf(float(sim.hour), 0.01)}
	for p in sim.people:
		var pid := String(p.id)
		if (p.dead or p.turned) and not tracker.gone.has(pid):
			tracker.gone[pid] = true
			var how := "turned" if p.turned else ("left" if p.away is Dictionary and p.away.get("kind", "") == "exile" else "died")
			tracker.lost.append({"day": int(sim.day), "hour": snappedf(float(sim.hour), 0.01), "who": String(p.first), "how": how, "on_trip": bool(tracker.was_away.get(pid, false))})
		tracker.was_away[pid] = p.away != null
	for id in tracker.idea_order:
		var rec: Dictionary = tracker.ideas[id]
		if String(rec.answer) != "":
			continue
		for e in sim.radio.news:
			if int(e.id) == int(id) and String(e.answered) != "":
				rec["answer"] = String(e.answered)
				rec["by_default"] = bool(e.by_default)
				rec["result"] = String(e.result)
				rec["answered_h"] = snappedf((float(sim.clock_min) - float(rec.t)) / 60.0, 0.01)
	var voice = sim.relations.voice()
	if voice != null and tracker.voice.is_empty():
		tracker.voice = {"day": int(sim.day), "hour": snappedf(float(sim.hour), 0.01), "who": String(voice.first)}
	for tid in TITLES:
		var holder = sim.specialists.holder(tid)
		if holder != null and not tracker.titles.has(tid):
			tracker.titles[tid] = {"day": int(sim.day), "hour": snappedf(float(sim.hour), 0.01), "who": String(holder.first)}


## The living who are not the player.
static func _others(sim) -> Array:
	var out: Array = []
	for p in sim.people:
		if not p.dead and not p.turned and not p.player:
			out.append(p)
	return out


## The community now: friendships beyond the roster, rivalries, couples, who holds which title, the voice.
static func _community(sim) -> Dictionary:
	var friends := 0
	var rivals := 0
	var couples := 0
	var roster_friends := 0
	var names: Array = []
	for key in sim.relations.pairs:
		var pr: Dictionary = sim.relations.pairs[key]
		var a = _find(sim, String(pr.a))
		var b = _find(sim, String(pr.b))
		if a == null or b == null or a.dead or b.dead or a.turned or b.turned or a.player or b.player:
			continue
		var roster: bool = sim.relations._roster_kind(String(pr.a), String(pr.b)) != ""
		match String(pr.kind):
			"friend":
				if roster:
					roster_friends += 1
				else:
					friends += 1
					names.append("%s+%s %.0f" % [a.first, b.first, float(pr.v)])
			"partner":
				couples += 1
				names.append("%s+%s (a couple) %.0f" % [a.first, b.first, float(pr.v)])
				if not roster:
					friends += 1
			"rival":
				rivals += 1
				names.append("%s-%s (rivals) %.0f" % [a.first, b.first, float(pr.v)])
	var titles: Array = []
	for tid in TITLES:
		var holder = sim.specialists.holder(tid)
		if holder != null:
			titles.append("%s:%s" % [tid, holder.first])
	var voice = sim.relations.voice()
	return {"friends": friends, "roster_friends": roster_friends, "rivals": rivals, "couples": couples, "titles": titles, "voice": String(voice.first) if voice != null else "", "pairs": names}


static func _find(sim, id: String):
	for p in sim.people:
		if String(p.id) == id:
			return p
	return null


## The colony at this moment, for the by-day table.
static func _row(sim, answerer) -> Dictionary:
	var mood := 0.0
	var trust := 0.0
	var n := 0
	var low := 0
	for p in _others(sim):
		mood += float(sim.morale.value(p))
		trust += float(p.trust)
		if float(p.trust) < 25.0:
			low += 1
		n += 1
	var com := _community(sim)
	var stats: Dictionary = sim.initiative.stats()
	var standings: Array = []
	for p in _others(sim):
		if p.away == null:
			standings.append([String(p.first), snappedf(float(sim.relations.standing(p)), 0.1)])
	standings.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return {
		"day": int(sim.day), "hour": snappedf(float(sim.hour), 0.01),
		"alive": n + (0 if sim.avatar.player() == null or sim.avatar.player().dead else 1),
		"others": n,
		"mood": snappedf(mood / float(maxi(1, n)), 0.01),
		"trust": snappedf(trust / float(maxi(1, n)), 0.01),
		"quiet": low,
		"scrap": snappedf(float(sim.stock.scrap), 0.1), "food": snappedf(float(sim.stock.food), 0.1), "ammo": snappedf(float(sim.stock.ammo), 0.1),
		"raised": int(stats.get("raised", 0)), "yes": int(stats.get("yes", 0)), "no": int(stats.get("no", 0)), "later": int(stats.get("later", 0)),
		"scrap_spent": snappedf(float(stats.get("scrap", 0.0)), 0.1), "food_spent": snappedf(float(stats.get("food", 0.0)), 0.1),
		"friends": int(com.friends), "rivals": int(com.rivals), "couples": int(com.couples), "titles": com.titles, "voice": com.voice,
		"standing": standings.slice(0, 3), "top_pairs": _top_pairs(sim, 4), "prac": _practice(sim),
	}


## The `n` pairs of the living (the player left out) that are furthest from nothing, as "Dez+Ana 21f" (f friend, p partner, r rival, * a roster bond).
static func _top_pairs(sim, n: int) -> Array:
	var list: Array = []
	for key in sim.relations.pairs:
		var pr: Dictionary = sim.relations.pairs[key]
		var a = _find(sim, String(pr.a))
		var b = _find(sim, String(pr.b))
		if a == null or b == null or a.dead or b.dead or a.turned or b.turned or a.player or b.player:
			continue
		var tag: String = String({"friend": "f", "partner": "p", "rival": "r"}.get(String(pr.kind), ""))
		if sim.relations._roster_kind(String(pr.a), String(pr.b)) != "":
			tag += "*"
		list.append({"v": absf(float(pr.v)), "text": "%s+%s %.0f%s" % [a.first, b.first, float(pr.v), tag]})
	list.sort_custom(func(x, y): return float(x.v) > float(y.v))
	var out: Array = []
	for e in list.slice(0, n):
		out.append(String(e.text))
	return out


## How close each title is: the practice of the one with the skill for it who has done the most, against the need.
static func _practice(sim) -> Dictionary:
	var out := {}
	for tid in TITLES:
		var def: Dictionary = sim.specialists._defs.get(tid, {})
		if def.is_empty():
			continue
		var best := "-"
		var best_p := 0.0
		var skill := 0.0
		for p in sim.people:
			if p.dead or p.turned:
				continue
			var have := float(p.skills.get(String(def.skill), 0)) if String(def.skill) != "" else 0.0
			if have < float(def.min_skill):
				continue
			var pr: float = sim.specialists.practice_of(p, tid)
			if best == "-" or pr > best_p:
				best_p = pr
				best = String(p.first)
				skill = have
		out[tid] = {"who": best, "practice": snappedf(best_p, 0.1), "need": float(def.need), "skill": skill, "min_skill": float(def.min_skill)}
	return out


# ============================================================================= reading it ==

## Across games: the means the plan's targets are about.
static func summarise(games: Array) -> Dictionary:
	var n := maxf(1.0, float(games.size()))
	var s := {"games": games.size(), "survived": 0, "ideas": 0.0, "yes": 0.0, "no": 0.0, "later": 0.0, "min_gap_h": INF, "scrap_in": 0.0, "scrap_ideas": 0.0, "food_ideas": 0.0,
		"friends": 0.0, "friends_ever": 0.0, "rivals": 0.0, "couples": 0.0, "titles": 0.0, "mood": 0.0, "trust": 0.0, "voice_days": [], "no_voice": 0, "medic_first": 0, "had_titles": 0, "mood_end": 0.0, "day_reached": 0.0,
		"quiet_people": 0.0}
	for g in games:
		if String(g.outcome) == "survived":
			s.survived += 1
		var last: Dictionary = g.rows[g.rows.size() - 1]
		s.ideas += float(last.raised)
		s.yes += float(last.yes)
		s.no += float(last.no)
		s.later += float(last.later)
		if float(g.min_gap_h) >= 0.0:
			s.min_gap_h = minf(float(s.min_gap_h), float(g.min_gap_h))
		s.scrap_in += float(g.scrap_in)
		s.scrap_ideas += float(g.scrap_ideas)
		s.food_ideas += float(g.food_ideas)
		s.friends += float(g.end.friends)
		s.friends_ever += float(g.get("ever", {}).get("friends", 0))
		s.rivals += float(g.end.rivals)
		s.couples += float(g.end.couples)
		s.titles += float((g.end.titles as Array).size())
		s.mood += _mean_mood(g)
		s.mood_end += float(last.mood)
		s.trust += float(last.trust)
		s.quiet_people += float(last.quiet)
		s.day_reached += float(g.day)
		if (g.voice as Dictionary).is_empty():
			s.no_voice += 1
		else:
			s.voice_days.append(int(g.voice.day))
		if not (g.titles as Dictionary).is_empty():
			s.had_titles += 1
			var first_id := ""
			var first_t := INF
			for tid in g.titles:
				var t: Dictionary = g.titles[tid]
				var when := float(t.day) * 24.0 + float(t.hour)
				if when < first_t:
					first_t = when
					first_id = String(tid)
			if first_id == "medic":
				s.medic_first += 1
	if float(s.min_gap_h) == INF:
		s.min_gap_h = -1.0
	for k in ["ideas", "yes", "no", "later", "scrap_in", "scrap_ideas", "food_ideas", "friends", "friends_ever", "rivals", "couples", "titles", "mood", "mood_end", "trust", "quiet_people", "day_reached"]:
		s[k] = snappedf(float(s[k]) / n, 0.01)
	return s


## The mean of the crew's mood over the rows that start the days of a game, the last day included but not the snapshot of the end (the
## number a `--noideas` game is compared on: what the last night did is not the mood of the days).
static func _mean_mood(g: Dictionary) -> float:
	var sum := 0.0
	var k := 0
	for r in g.rows:
		if int(r.others) > 0 and int(r.day) <= int(g.get("days", 9999)):
			sum += float(r.mood)
			k += 1
	return sum / float(maxi(1, k))


## The verdict on each of the plan's numeric targets for these games, one line each: [{"name", "got", "want", "ok" (true, false, or null: not known)}].
static func verdicts(summary: Dictionary, games: Array, base_mood: float = NAN) -> Array:
	var out: Array = []
	var ideas := float(summary.ideas)
	out.append({"name": "ideas in all", "got": "%.1f" % ideas, "want": "%d to %d" % [IDEAS_MIN, IDEAS_MAX], "ok": ideas >= float(IDEAS_MIN) and ideas <= float(IDEAS_MAX)})
	var gap := float(summary.min_gap_h)
	out.append({"name": "least gap between two ideas", "got": ("%.2f h" % gap) if gap >= 0.0 else "-", "want": "%.0f h or more" % GAP_MIN_H, "ok": gap < 0.0 or gap >= GAP_MIN_H - 1.0e-6})
	var friends := float(summary.friends)
	out.append({"name": "friendships beyond the roster, at the end", "got": "%.1f" % friends, "want": "%d to %d" % [FRIENDS_MIN, FRIENDS_MAX], "ok": friends >= float(FRIENDS_MIN) and friends <= float(FRIENDS_MAX)})
	var ever := float(summary.friends_ever)
	out.append({"name": "friendships formed in the game (ever)", "got": "%.1f" % ever, "want": "%d to %d" % [FRIENDS_MIN, FRIENDS_MAX], "ok": ever >= float(FRIENDS_MIN) and ever <= float(FRIENDS_MAX)})
	out.append({"name": "rivalries", "got": "%.1f" % float(summary.rivals), "want": "0 to %d" % RIVALS_MAX, "ok": float(summary.rivals) <= float(RIVALS_MAX) + 0.5})
	var most_couples := 0
	for g in games:
		most_couples = maxi(most_couples, int(g.end.couples))
	out.append({"name": "couples (most in a game)", "got": "%d" % most_couples, "want": "at most %d" % COUPLES_MAX, "ok": most_couples <= COUPLES_MAX})
	var titles := float(summary.titles)
	out.append({"name": "titles at the end", "got": "%.1f" % titles, "want": "%d to %d" % [TITLES_MIN, TITLES_MAX], "ok": titles >= float(TITLES_MIN) and titles <= float(TITLES_MAX)})
	out.append({"name": "the medic first (games with a title)", "got": "%d of %d" % [summary.medic_first, summary.had_titles], "want": "all", "ok": int(summary.medic_first) == int(summary.had_titles) and int(summary.had_titles) > 0})
	var days: Array = summary.voice_days
	days.sort()
	var med: int = int(days[days.size() / 2]) if not days.is_empty() else -1
	out.append({"name": "the voice appears on day (median)", "got": ("%d" % med) if med >= 0 else "never", "want": "about %d (4 to %d)" % [VOICE_BY_DAY, VOICE_BY_DAY + 1], "ok": med >= 4 and med <= VOICE_BY_DAY + 1})
	var scrap_in := float(summary.scrap_in)
	var share := float(summary.scrap_ideas) / scrap_in if scrap_in > 0.0 else 0.0
	out.append({"name": "scrap spent on ideas / scrap that came in", "got": "%.0f%% (%.1f of %.1f)" % [share * 100.0, float(summary.scrap_ideas), scrap_in], "want": "under %.0f%%" % (SCRAP_SHARE_MAX * 100.0), "ok": share < SCRAP_SHARE_MAX})
	if not is_nan(base_mood):
		out.append({"name": "mean mood against --noideas", "got": "%+.2f (%.1f against %.1f)" % [float(summary.mood) - base_mood, float(summary.mood), base_mood], "want": "not under -%.0f" % MOOD_LOSS_MAX, "ok": float(summary.mood) - base_mood >= -MOOD_LOSS_MAX})
	return out


# ============================================================================= printing ==

static func _print_game(n: int, g: Dictionary, verbose: bool) -> void:
	var last: Dictionary = g.rows[g.rows.size() - 1]
	print("game %d seed %d: %s, day %d, %d alive, %d ideas raised (%d yes, %d no, %d later), scrap %.0f in / %.0f on ideas, food %.0f on ideas, %s, %.1f s" % [
		n, g.seed, g.outcome, g.day, g.alive, last.raised, last.yes, last.no, last.later, g.scrap_in, g.scrap_ideas, g.food_ideas,
		("least gap %.1f h" % g.min_gap_h) if float(g.min_gap_h) >= 0.0 else "fewer than two ideas", g.took])
	print("   day  hr  alive | mood trust quiet | scrap food | raised  yes  no later |  scrap food on ideas | friends rivals couples | titles / voice")
	var seen := {}
	for r in g.rows:
		var key := "%d:%s" % [r.day, "end" if r == g.rows[g.rows.size() - 1] else ""]
		if seen.has(key):
			continue
		seen[key] = true
		print("   %3d %4.1f %5d | %5.1f %5.1f %5d | %5.0f %4.0f | %6d %4d %3d %5d | %6.0f %4.0f | %7d %6d %6d | %s / %s" % [
			r.day, r.hour, r.alive, r.mood, r.trust, r.quiet, r.scrap, r.food, r.raised, r.yes, r.no, r.later, r.scrap_spent, r.food_spent,
			r.friends, r.rivals, r.couples, ", ".join(r.titles) if not (r.titles as Array).is_empty() else "-", r.voice if String(r.voice) != "" else "-"])
	print("   day | the standing of the community's best three | the closest pairs (f friend, p partner, r rival, * a roster bond) | practice of the best candidate / need")
	var seen_day := {}
	for r in g.rows:
		var day_key := "%d:%s" % [r.day, "end" if r == g.rows[g.rows.size() - 1] else ""]
		if seen_day.has(day_key):
			continue
		seen_day[day_key] = true
		var stand: Array = []
		for e in r.standing:
			stand.append("%s %.0f" % [e[0], float(e[1])])
		var prac: Array = []
		for tid in TITLES:
			var pr: Dictionary = r.prac.get(tid, {})
			if not pr.is_empty():
				prac.append("%s %s %.0f/%.0f" % [String(tid).substr(0, 3), String(pr.who).substr(0, 3), float(pr.practice), float(pr.need)])
		print("   %3d | %-34s | %-70s | %s" % [r.day, ", ".join(stand), ", ".join(r.top_pairs), " ".join(prac)])
	print("   ever (any time in the game): %d friendships beyond the roster, %d rivalries, %d couples" % [g.ever.friends, g.ever.rivals, g.ever.couples])
	var lost: Array = []
	for l in g.lost:
		lost.append("%s %s day %d %.1f%s" % [l.who, l.how, l.day, l.hour, " (on a trip)" if bool(l.on_trip) else ""])
	print("   lost: %s" % (", ".join(lost) if not lost.is_empty() else "nobody"))
	var kinds: Array = []
	for k in g.by_kind:
		var row: Dictionary = g.by_kind[k]
		kinds.append("%s %d (%d yes %d no %d later)" % [k, row.raised, row.yes, row.no, row.later])
	print("   by kind: %s" % ("; ".join(kinds) if not kinds.is_empty() else "none"))
	print("   voice: %s; titles: %s" % [("%s from day %d %.1f" % [g.voice.who, g.voice.day, g.voice.hour]) if not (g.voice as Dictionary).is_empty() else "never", _titles_text(g.titles)])
	var near: Array = []
	for tid in g.practice:
		var p: Dictionary = g.practice[tid]
		near.append("%s: %s %.1f of %.0f (skill %.0f of %.0f)" % [tid, p.who, p.practice, p.need, p.skill, p.min_skill])
	print("   practice: %s" % "; ".join(near))
	if not (g.end.pairs as Array).is_empty():
		print("   pairs at the end: %s" % ", ".join(g.end.pairs))
	if verbose:
		for i in g.ideas:
			print("     idea day %d %05.2f  %-12s %-6s -> %-6s%s  %s" % [i.day, i.hour, i.kind, i.who, i.answer if String(i.answer) != "" else "open", " (by default)" if bool(i.by_default) else "", i.result])
		for e in g.news:
			print("     news day %d %05.2f  [%s] %s%s" % [e.day, e.hour, e.kind, e.text, (" (" + String(e.sub) + ")") if String(e.sub) != "" else ""])


static func _titles_text(titles: Dictionary) -> String:
	if titles.is_empty():
		return "none"
	var parts: Array = []
	for tid in titles:
		parts.append("%s %s day %d" % [tid, titles[tid].who, titles[tid].day])
	return ", ".join(parts)


static func _print_summary(s: Dictionary, verdict_lines: Array, mood_note: String) -> void:
	print("")
	print("%d games: survived %d, mean day reached %.1f; per game: %.1f ideas (%.1f yes, %.1f no, %.1f later), scrap %.1f in / %.1f on ideas, food %.1f on ideas; friendships %.1f, rivalries %.1f, couples %.1f, titles %.1f; mean mood %.1f, trust %.1f at the end %.1f, quiet people %.1f%s" % [
		s.games, s.survived, s.day_reached, s.ideas, s.yes, s.no, s.later, s.scrap_in, s.scrap_ideas, s.food_ideas, s.friends, s.rivals, s.couples, s.titles, s.mood, s.trust, s.mood_end, s.quiet_people, mood_note])
	print("")
	print("Targets (10 days, crew 5, affordable):")
	for v in verdict_lines:
		print("  %-4s %-44s %-28s want %s" % ["ok" if v.ok == true else "MISS", v.name, v.got, v.want])


# ============================================================================= run ==

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var opts := {"games": "3", "days": "10", "difficulty": "1", "seed": "1", "seeds": "", "crew": "5", "policy": "affordable", "colony": "informed", "avatar": "idle",
		"hz": "15", "read": "20", "keep_scrap": "5", "keep_food": "10", "out": "", "save": "", "save_day": "0"}
	var flags := {"noideas": false, "nocommunity": false, "base": false, "nobase": false, "verbose": false, "quiet": false}
	for arg in OS.get_cmdline_user_args():
		var text := String(arg).trim_prefix("--")
		var kv := text.split("=", true, 1)
		var key := String(kv[0]).replace("-", "_")
		if key == "fast":
			continue
		if flags.has(key):
			flags[key] = true
		elif opts.has(key) and kv.size() > 1:
			opts[key] = kv[1]
		else:
			printerr("Unknown flag --%s" % kv[0])
			quit(2)
			return
	if not POLICIES.has(String(opts.policy)) or not AVATARS.has(String(opts.avatar)) or not ["informed", "default", "none"].has(String(opts.colony)):
		printerr("--policy takes %s, --avatar %s, --colony informed, default or none" % [", ".join(POLICIES), ", ".join(AVATARS)])
		quit(2)
		return
	var days := maxi(1, int(opts.days))
	var seeds: Array = []
	if String(opts.seeds) != "":
		for t in String(opts.seeds).split(","):
			if t.is_valid_int():
				seeds.append(t.to_int())
	else:
		for i in maxi(1, int(opts.games)):
			seeds.append(int(opts.seed) + i)
	var play_opts := {
		"days": days, "hz": clampf(float(opts.hz), 5.0, 60.0), "difficulty": clampi(int(opts.difficulty), 0, 2), "crew": clampi(int(opts.crew), 3, 6),
		"policy": String(opts.policy), "colony": String(opts.colony), "avatar": String(opts.avatar), "read": float(opts.read),
		"keep_scrap": float(opts.keep_scrap), "keep_food": float(opts.keep_food), "noideas": flags.noideas, "nocommunity": flags.nocommunity, "base": flags.base and not flags.nobase,
	}
	var quiet: bool = flags.quiet
	if not quiet:
		print("Community probe: %d games of %d days, crew %d, colony %s, avatar %s, answers: %s%s%s%s, %d Hz, seeds from %d" % [
			seeds.size(), days, play_opts.crew, play_opts.colony, play_opts.avatar, play_opts.policy,
			", NO IDEAS" if flags.noideas else "", ", NO COMMUNITY" if flags.nocommunity else "", ", BASE ON" if play_opts.base else "", roundi(play_opts.hz), seeds[0]])
		print("")
	var save_state := {}
	if String(opts.save) != "":
		save_state = {"path": String(opts.save), "day": int(opts.save_day) if int(opts.save_day) > 0 else days, "done": false, "at": ""}
	var games: Array = []
	for i in seeds.size():
		var g := play(play_opts, int(seeds[i]), save_state if i == 0 else {})
		games.append(g)
		if not quiet:
			_print_game(i + 1, g, flags.verbose)
			print("")
	var summary := summarise(games)
	var verdict_lines := verdicts(summary, games)
	if not quiet:
		_print_summary(summary, verdict_lines, "")
		if not save_state.is_empty():
			print("")
			print("Save: %s at %s (%s)" % [String(save_state.path), String(save_state.at), "written" if bool(save_state.done) else "NOT written"])
	if String(opts.out) != "":
		var f := FileAccess.open(String(opts.out), FileAccess.WRITE)
		if f == null:
			printerr("Could not write %s" % opts.out)
		else:
			f.store_string(JSON.stringify({"args": opts, "flags": flags, "games": games, "summary": summary, "verdicts": verdict_lines}, "  ", true, true))
			f.close()
			if not quiet:
				print("Wrote %s" % opts.out)
	quit(0)
