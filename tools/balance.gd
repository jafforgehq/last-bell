## The balance harness: plays whole games headless with a default policy and
## reports how the colony fares, so the numbers can be tuned.
##
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --headless --path . --script res://tools/balance.gd -- --games=8 --days=10 --difficulty=1 --seed=1 [--out=path.json] [--fast]
##
## Flags (all optional):
##   --games=N        how many games (seeds seed, seed+1, ...)            default 8
##   --days=N         survive this many nights: a game ends when day N+1  default 10
##                    dawns, or when everyone is gone
##   --difficulty=N   0 story, 1 standard, 2 brutal                       default 1
##   --seed=N         the first seed                                      default 1
##   --fast           step the rules at 15 Hz instead of 30 (faster, a little coarser)
##   --hz=N           step at N Hz (overrides --fast)
##   --jobs=N         play N games at a time in worker processes (default 1; a
##                    game that collapses is slow, so a batch is worth spreading)
##   --seeds=a,b,c    play exactly these seeds instead of --games and --seed
##   --sites=path     read the scavenging sites from another file (to try a site before it is in the game)
##   --policy=none    nobody gives any order: what the colony does alone
##   --policy=keep    the default policy, but everyone hides in the school gym from the bell
##                    to dawn (the exploit check: hiding must not beat defending)
##   --policy=informed the default policy plus what the game tells a player: at dusk the crew
##                    is stood on the decks where its guns cover the walls tonight's dead
##                    will come to, and the alarm is set on the best-covered section
##   --nostory        play with the storyteller off (no card at noon, no assembly at dawn), to see
##                    what the radio changes; by default it is on and the policy answers each card
##                    with the choice the card names as its default
##   --verbose        print what the policy did and who was lost, game by game
##   --out=path.json  also write everything (every game, every day) as JSON
##
## The default policy is what a sensible player does without thinking:
##  - in the daytime the two best builders repair any wall under 80% (repairs
##    are not automatic in the game) while there is scrap; at the bell everyone
##    goes back to their post;
##  - in the morning (06:30 to 10:00), when food or water is under 4 days, or
##    meds under 3, or scrap under 10, or ammo under 60, the best two free
##    shooters go scavenging to the site that helps;
##  - by day, with ammo under 250 and 10 scrap or more to spare, the best free builder
##    makes ammo at the worktable until there is 450 (the scrapyard is the site
##    for scrap, then the hardware store);
##  - the infected are treated while there is medicine, and sent out through the
##    gate once delirious with none left;
##  - when the radio brings a card at noon it takes the answer the card names as its default
##    (a card with no choice is read); and when the dead come to the wall by day (stragglers)
##    the three best shooters stand to at their posts until they are put down.
## Bandages, stabilising and healing in bed are automatic in the game.
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")
const Scavenge := preload("res://scripts/sim/scavenge.gd")

## Another sites file for the whole run (--sites=path): to try a site before it is in the game.
static var sites_override := ""
## The storyteller is on (see --nostory).
static var story_on := true


## What a sensible player does, step by step. Call tick() about once a second
## of the rules' time.
class Policy:
	extends RefCounted

	## At most this many people repair at once, and only sections under this part of their health.
	const REPAIRERS := 2
	const REPAIR_BELOW := 0.8
	## A party goes when a stock is under these.
	const LOW_DAYS := 4.0
	const LOW_SCRAP := 10.0
	const LOW_MEDS := 3.0
	const LOW_AMMO := 60.0
	## An infected person is treated again no sooner than this many game minutes after the last try.
	const TREAT_GAP_MIN := 45.0
	## Sites that help with each need, most useful first (a site that is not in the
	## game, or is picked over, is skipped).
	const SITE_FOR := {"food": ["houses"], "water": ["houses"], "meds": ["pharmacy"], "scrap": ["scrapyard", "hardware"], "ammo": ["hardware", "scrapyard"]}
	## The workshop: one person makes ammo by day while the stock is under CRAFT_BELOW_AMMO
	## and there is scrap to spare, until it is over CRAFT_UNTIL_AMMO.
	const CRAFT_BELOW_AMMO := 250.0
	const CRAFT_UNTIL_AMMO := 450.0
	const CRAFT_MIN_SCRAP := 10.0
	## Against dead at the wall by day this many of the best shooters stand to at their posts.
	const STAND_TO := 3

	var sim
	## Hide in the school gym from the bell to dawn instead of holding the posts.
	var hide := false
	## Use the forecast and the coverage: place the crew and set the alarm at dusk.
	var informed := false
	var _placed_day := -1
	var _lured_day := -1
	var _placed: Dictionary = {}
	## What it has done: trips sent, treatments ordered, people sent out, repairs ordered.
	var trips := 0
	var treats := 0
	var sendouts := 0
	var repairs := 0
	var crafts := 0
	## Lines of what it did: [{"day", "hour", "text"}].
	var notes: Array = []
	var _sent_day := 0
	var _last_treat := {}
	## Radio cards answered, the one answered last ("day:id": a card is answered once), and who was
	## stood to the wall against dead by day (person id to true).
	var cards := 0
	var _answered := ""
	var _standing: Dictionary = {}

	func _init(s) -> void:
		sim = s

	func tick() -> void:
		if sim.over != "":
			return
		if hide:
			_hide()
		if informed:
			_inform()
		_story()
		_alarm()
		_scavenge()
		_repair()
		_infection()
		_craft()

	func _note(text: String) -> void:
		notes.append({"day": sim.day, "hour": snappedf(sim.hour, 0.01), "text": text})

	# ----------------------------------------------------------------------- the radio --

	## A card is waiting: the answer it names as its default is taken, once for each card (a card with no
	## choice is read). A choice that cannot be made is left to the card's own two hours.
	func _story() -> void:
		var card: Dictionary = sim.storyteller.pending()
		if card.is_empty():
			return
		var key := "%d:%s" % [sim.day, card.id]
		if key == _answered:
			return
		_answered = key
		var i := int(card.bot)
		var label := String(card.choices[i].label) if i >= 0 and i < card.choices.size() else ""
		if sim.storyteller.choose(i):
			cards += 1
			_note("answers the radio, %s: %s" % [String(card.title), label] if not bool(card.resolved) else "reads the radio: %s" % String(card.title))
		else:
			_note("leaves the radio's %s to its default" % String(card.title))

	## Dead at the wall by day (stragglers): the best shooters stand to at their posts until the dead are
	## put down, then they go back to what they were doing. (By night the posts are held anyway.)
	func _alarm() -> void:
		var threat := 0
		if sim.phase == "day":
			for z in sim.zombies:
				if z.state == "attack" or z.state == "breach" or (z.state == "approach" and z.slot != null):
					threat += 1
		if threat > 0:
			if _standing.is_empty():
				var crew: Array = []
				for p in sim.people:
					if _free(p):
						crew.append(p)
				crew.sort_custom(func(a, b): return a.skills.Shooting > b.skills.Shooting)
				for p in crew.slice(0, STAND_TO):
					sim.order_post(p)
					_standing[p.id] = true
				if not _standing.is_empty():
					_note("stands %d to the wall: %d of the dead at it by day" % [_standing.size(), threat])
			return
		if _standing.is_empty():
			return
		for p in sim.people:
			if _standing.has(p.id) and p.drafted:
				p.drafted = false
				p.order = null
				p.goal_key = ""
		_standing.clear()
		_note("stands down: the wall is clear")

	## Where a hiding crew stands: deep in the school gym.
	const KEEP_SPOTS := [Vector2(24.5, 52.5), Vector2(27.5, 52.5), Vector2(30.5, 52.5), Vector2(24.5, 55.5), Vector2(27.5, 55.5), Vector2(30.5, 55.5)]

	## From dusk to dawn everyone able goes into the school and stays; at dawn they are released.
	func _hide() -> void:
		var night: bool = sim.phase == "dusk" or sim.phase == "night"
		var i := 0
		for p in sim.people:
			var spot: Vector2 = KEEP_SPOTS[i % KEEP_SPOTS.size()]
			i += 1
			if p.dead or p.downed or p.away != null:
				continue
			if night:
				if not p.drafted or p.order == null:
					sim.order_move(p, spot.x, spot.y)
			elif p.drafted and p.y > 44.5:
				p.drafted = false
				p.order = null
				p.goal_key = ""

	# ------------------------------------------------------------- informed --

	## Where the informed crew may stand: the raised decks and the towers.
	func _spots() -> Array:
		var out: Array = []
		for x in range(22, 63, 3):
			out.append(Vector2(float(x) + 0.5, 18.6))
		for y in range(21, 43, 3):
			out.append(Vector2(20.6, float(y) + 0.5))
			out.append(Vector2(63.4, float(y) + 0.5))
		out.append(Vector2(18.9, 16.9))
		out.append(Vector2(65.2, 16.9))
		var ok: Array = []
		for v in out:
			if sim.world.on_deck(v.x, v.y):
				ok.append(v)
		return ok

	## How much a wall section matters tonight: more the nearer it is to where the
	## dead come from (the forecast), and a little for all of them.
	func _weight(seg, spawns: Array) -> float:
		var d := 80.0
		for sp in spawns:
			d = minf(d, Vector2(sp).distance_to(seg.center))
		return 1.0 + 4.0 * maxf(0.0, 1.0 - d / 45.0)

	func _inform() -> void:
		var hour: float = sim.hour
		var dusky: bool = sim.phase == "day" and hour >= 17.0 or sim.phase == "dusk"
		if not dusky and sim.phase != "night":
			# by day the crew goes back to its jobs
			if not _placed.is_empty():
				for p in sim.people:
					if _placed.has(p.id) and p.drafted:
						p.drafted = false
						p.order = null
						p.goal_key = ""
				_placed.clear()
			return
		if _placed_day != sim.day and dusky:
			_placed_day = sim.day
			_place_the_crew()
		if _lured_day != sim.day and sim.phase == "dusk":
			_lured_day = sim.day
			_set_the_alarm()

	func _place_the_crew() -> void:
		var f: Dictionary = sim.tactics.forecast()
		var spawns: Array = f.spawns if f.get("given", false) else []
		var spots := _spots()
		var count := {}
		for s in sim.segments:
			count[s.id] = 0
		var crew: Array = []
		for p in sim.people:
			if not (p.dead or p.downed or p.away != null):
				crew.append(p)
		crew.sort_custom(func(a, b): return a.skills.Shooting > b.skills.Shooting)
		var used := {}
		for p in crew:
			var best = null
			var best_gain := -1.0
			for v in spots:
				if used.has(v):
					continue
				var gain := 0.0
				var reach := float(p.gun.range)
				for s in sim.segments:
					var within := 0
					for sl in s.slots:
						if v.distance_to(Vector2(sl.x, sl.y)) <= reach:
							within += 1
					if within * 2 >= s.slots.size():
						gain += _weight(s, spawns) / float(1 + int(count[s.id]))
				gain -= Vector2(p.x, p.y).distance_to(v) * 0.01
				if gain > best_gain:
					best_gain = gain
					best = v
			if best == null:
				continue
			used[best] = true
			var reach2 := float(p.gun.range)
			for s in sim.segments:
				var within2 := 0
				for sl in s.slots:
					if best.distance_to(Vector2(sl.x, sl.y)) <= reach2:
						within2 += 1
				if within2 * 2 >= s.slots.size():
					count[s.id] = int(count[s.id]) + 1
			if sim.order_move(p, best.x, best.y):
				_placed[p.id] = true
		_note("places the crew for the %s" % (sim.waves.heading_text(sim.waves.plan_for(sim.day)) if f.get("given", false) else "night"))

	## The alarm goes on the best-covered section that is still whole, if scrap allows.
	func _set_the_alarm() -> void:
		if float(sim.stock.scrap) < 8.0 or sim.tactics.lure_seg() != null:
			return
		var best = null
		var best_score := 0.0
		for s in sim.segments:
			if s.state == 3 or s.kind == "door":
				continue
			var score := float(sim.tactics.coverage_of(s)) * 3.0 + minf(s.hp / 100.0, 3.0)
			if sim.tactics.coverage_of(s) >= 3 and score > best_score:
				best_score = score
				best = s
		if best != null and sim.tactics.order_lure(best):
			_note("sets the alarm at the %s" % best.name.to_lower())

	## Free to be given a job: on the map, on their feet, on no order, and not busy treating someone.
	func _free(p) -> bool:
		if p.dead or p.downed or p.away != null or p.drafted or p.order != null or sim.morale.breakdown(p):
			return false
		return sim.medical.goal_for(p) == null

	# ------------------------------------------------------------ scavenging --

	func _scavenge() -> void:
		if _sent_day == sim.day or sim.phase != "day" or sim.hour >= 10.0:
			return
		var site := _site_wanted()
		if site == "" or not sim.scavenge.can_send():
			return
		var crew := _scavengers()
		if crew.is_empty():
			return
		if sim.scavenge.send(crew, site):
			_sent_day = sim.day
			trips += 1
			var names: Array = []
			for p in crew:
				names.append(p.first)
			_note("sent %s to %s" % [" and ".join(names), site])

	## The site that helps most with what is lowest, if it is open; "" if nothing is needed.
	func _site_wanted() -> String:
		var needs: Array = []
		if sim.supplies.days_left("food") < LOW_DAYS:
			needs.append("food")
		if sim.supplies.days_left("water") < LOW_DAYS:
			needs.append("water")
		if float(sim.stock.meds) < LOW_MEDS:
			needs.append("meds")
		if float(sim.stock.scrap) < LOW_SCRAP:
			needs.append("scrap")
		if float(sim.stock.ammo) < LOW_AMMO:
			needs.append("ammo")
		var open := {}
		for site in sim.scavenge.available_sites():
			open[site.id] = site.available
		for need in needs:
			for id in SITE_FOR[need]:
				if open.get(id, false):
					return id
		return ""

	## The best two free shooters (Leading breaks a tie), or one if the colony
	## would be left too thin, or none.
	func _scavengers() -> Array:
		var free: Array = []
		for p in sim.people:
			if _free(p) and sim.scavenge.can_go(p):
				free.append(p)
		free.sort_custom(func(a, b):
			if a.skills.Shooting != b.skills.Shooting:
				return a.skills.Shooting > b.skills.Shooting
			return a.skills.Leading > b.skills.Leading)
		var n := 2 if free.size() >= 3 else (1 if free.size() == 2 else 0)
		return free.slice(0, n)

	# --------------------------------------------------------------- repairs --

	func _repair() -> void:
		# by night the wall is held from the posts
		if sim.phase != "day":
			for p in sim.people:
				if p.repair != null:
					p.repair = null
			return
		if float(sim.stock.scrap) < 1.0:
			return
		var busy := 0
		var taken: Array = []
		for p in sim.people:
			if p.repair != null and not p.dead:
				busy += 1
				taken.append(p.repair)
		var worn: Array = []
		for s in sim.segments:
			if s.hp / s.max_hp < REPAIR_BELOW and not taken.has(s):
				worn.append(s)
		worn.sort_custom(func(a, b): return a.hp / a.max_hp < b.hp / b.max_hp)
		while busy < REPAIRERS and not worn.is_empty():
			var builder = _best_builder()
			if builder == null:
				return
			var s = worn.pop_front()
			sim.order_repair(builder, s)
			busy += 1
			repairs += 1
			_note("%s repairs the %s" % [builder.first, s.name.to_lower()])

	func _best_builder():
		var best = null
		var best_key := -1.0e9
		for p in sim.people:
			if p.repair != null or not _free(p):
				continue
			# walls come before ammo, but a repair takes someone off the bench only if nobody else is free
			var key: float = float(p.skills.Building) - (100.0 if sim.workshop.crafting(p) else 0.0)
			if best == null or key > best_key:
				best = p
				best_key = key
		return best

	# -------------------------------------------------------------- workshop --

	## By day, while ammo is low and scrap can be spared, the best builder who is free
	## makes ammo at the worktable; they are called off when the stock is back up.
	func _craft() -> void:
		if sim.phase != "day":
			return
		var workers: Array = []
		for p in sim.people:
			if sim.workshop.crafting(p):
				workers.append(p)
		var ammo := float(sim.stock.ammo)
		if not workers.is_empty():
			if ammo >= CRAFT_UNTIL_AMMO:
				for p in workers:
					sim.workshop.stop(p)
					_note("%s is back from the worktable" % p.first)
			return
		if ammo >= CRAFT_BELOW_AMMO or float(sim.stock.scrap) < CRAFT_MIN_SCRAP:
			return
		var best = null
		for p in sim.people:
			if p.repair != null or not _free(p) or sim.workshop.why_not_craft(p) != "":
				continue
			if best == null or p.skills.Building > best.skills.Building:
				best = p
		if best != null and sim.workshop.order_craft(best):
			crafts += 1
			_note("%s makes ammo at the worktable" % best.first)

	# ------------------------------------------------------------- infection --

	func _infection() -> void:
		for p in sim.people:
			if p.dead or p.away != null or p.infected_at < 0.0 or sim.medical.sendouts.has(p.id):
				continue
			var sel := {"kind": "person", "ref": p}
			var since: float = sim.clock_min - float(_last_treat.get(p.id, -1.0e9))
			if float(sim.stock.meds) >= 2.0:
				if since >= TREAT_GAP_MIN and not sim.medical.treat_orders.has(p.id) and sim.medical.gizmo("treat", sel):
					_last_treat[p.id] = sim.clock_min
					treats += 1
					_note("treats %s's infection" % p.first)
			elif sim.medical.infection_stage(p) == "delirious" and sim.medical.can_send_out(p):
				if sim.medical.gizmo("sendout", sel):
					sendouts += 1
					_note("sends %s out through the gate" % p.first)


## Plays one game and returns {"seed", "difficulty", "days", "outcome"
## ("survived" or "defeat"), "day" (the day reached, at most `days`), "rows",
## "trips", "treats", "sendouts", "repairs", "crafts", "notes", "took"}. `rows` has one
## entry for the start of each day (and one at the end of a lost game): see _row.
## `hz` is how many steps of the rules a second; `orders` false plays with no
## orders given at all; `hide` makes the crew spend every night in the school gym; `setup`, if given, is called with the new Sim before the
## first step (the tests use it to play a cheap game).
static func play(seed_value: int, difficulty: int, days: int, hz: float = 30.0, orders: bool = true, setup: Callable = Callable(), hide: bool = false, informed: bool = false, story: bool = true) -> Dictionary:
	var started := Time.get_ticks_msec()
	var g := Helpers.make(seed_value, difficulty)
	var sim = g.sim
	# the storyteller: on (the radio brings its cards, the dawn has its assembly) unless asked not to
	sim.storyteller.enabled = story
	if setup.is_valid():
		setup.call(sim)
	var policy := Policy.new(sim)
	policy.hide = hide
	policy.informed = informed
	var dt := 1.0 / hz
	var every := maxi(1, roundi(hz))
	var rows: Array = [_row(sim)]
	var gone := {}
	var notes: Array = []
	var last_day: int = sim.day
	var step := 0
	while sim.over == "" and sim.day <= days:
		sim.update(dt)
		step += 1
		if sim.day != last_day:
			last_day = sim.day
			rows.append(_row(sim))
		if step % every != 0:
			continue
		if orders:
			policy.tick()
		for p in sim.people:
			if p.dead and not gone.has(p.id):
				gone[p.id] = true
				var how := "turned" if p.turned else ("left" if p.away is Dictionary and p.away.get("kind", "") == "exile" else "died")
				notes.append({"day": sim.day, "hour": snappedf(sim.hour, 0.01), "text": "%s %s" % [p.first, how]})
	if sim.over != "":
		rows.append(_row(sim))
	var survived: bool = (sim.over == "" and sim.day > days) or sim.over == "victory"
	var all_notes: Array = policy.notes + notes
	all_notes.sort_custom(func(a, b): return a.day < b.day or (a.day == b.day and a.hour < b.hour))
	var result := {
		"seed": seed_value,
		"difficulty": difficulty,
		"days": days,
		"outcome": "survived" if survived else "defeat",
		"day": mini(sim.day, days) if survived else sim.day,
		"rows": rows,
		"trips": policy.trips,
		"treats": policy.treats,
		"sendouts": policy.sendouts,
		"repairs": policy.repairs,
		"crafts": policy.crafts,
		"cards": policy.cards,
		"notes": all_notes,
		"took": snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1),
	}
	g.world.free()
	return result


## The colony at this moment, for the day-by-day log.
static func _row(sim) -> Dictionary:
	var alive := 0
	var dead := 0
	var turned := 0
	var left := 0
	var downed := 0
	for p in sim.people:
		if p.turned:
			turned += 1
		elif p.dead:
			if p.away is Dictionary and p.away.get("kind", "") == "exile":
				left += 1
			else:
				dead += 1
		else:
			alive += 1
			if p.downed:
				downed += 1
	var wall := 0.0
	var wall_max := 0.0
	var down := 0
	for s in sim.segments:
		wall += s.hp
		wall_max += s.max_hp
		if s.state == 3:
			down += 1
	var shaken := 0
	for p in sim.people:
		if not p.dead and (sim.morale.mood(p) == "Shaken" or sim.morale.mood(p) == "Breaking"):
			shaken += 1
	var walkers := 0
	var runners := 0
	var brutes := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			walkers += 1
			if z.kind == "runner":
				runners += 1
			elif z.kind == "brute":
				brutes += 1
	return {
		"day": sim.day,
		"hour": snappedf(sim.hour, 0.01),
		"food": snappedf(sim.stock.food, 0.1),
		"water": snappedf(sim.stock.water, 0.1),
		"scrap": snappedf(sim.stock.scrap, 0.1),
		"meds": snappedf(sim.stock.meds, 0.1),
		"ammo": snappedf(sim.stock.ammo, 0.1),
		"alive": alive,
		"downed": downed,
		"dead": dead,
		"turned": turned,
		"left": left,
		"wall_hp": snappedf(wall, 0.1),
		"wall_max": wall_max,
		"breached": down,
		"kills": sim.kills,
		"tension": snappedf(sim.storyteller.tension, 0.1),
		"shaken": shaken,
		"breakdowns": sim.morale.breakdown_count,
		"walkers": walkers,
		"runners": runners,
		"brutes": brutes,
	}


## Across games: how many were survived, the day reached, who was lost, the
## stocks at the end, and for each day the average colony over the games that
## got that far.
static func summarise(games: Array) -> Dictionary:
	var survived := 0
	var reached: Array = []
	var lost := {"dead": 0.0, "turned": 0.0, "left": 0.0}
	var final_stock := {"food": 0.0, "water": 0.0, "scrap": 0.0, "meds": 0.0, "ammo": 0.0}
	var by_day := {}
	for game in games:
		if game.outcome == "survived":
			survived += 1
		reached.append(game.day)
		var last: Dictionary = game.rows[game.rows.size() - 1]
		for k in lost:
			lost[k] += last[k]
		for k in final_stock:
			final_stock[k] += last[k]
		var seen := {}
		for row in game.rows:
			if row.alive > 0 and not seen.has(row.day):
				seen[row.day] = true
				if not by_day.has(row.day):
					by_day[row.day] = []
				by_day[row.day].append(row)
	reached.sort()
	var n := maxi(1, games.size())
	var curve: Array = []
	var day_keys := by_day.keys()
	day_keys.sort()
	for day in day_keys:
		var rows: Array = by_day[day]
		var avg := {"day": day, "games": rows.size()}
		for k in ["alive", "food", "water", "scrap", "meds", "ammo", "wall_hp", "wall_max", "kills", "walkers"]:
			var sum := 0.0
			for r in rows:
				sum += float(r[k])
			avg[k] = snappedf(sum / rows.size(), 0.1)
		curve.append(avg)
	for k in lost:
		lost[k] = snappedf(lost[k] / n, 0.01)
	for k in final_stock:
		final_stock[k] = snappedf(final_stock[k] / n, 0.1)
	return {
		"games": games.size(),
		"survived": survived,
		"median_day": reached[reached.size() / 2] if not reached.is_empty() else 0,
		"mean_lost": lost,
		"mean_final_stock": final_stock,
		"curve": curve,
	}


# ---------------------------------------------------------------------- run --

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var opts := {"games": "8", "days": "10", "difficulty": "1", "seed": "1", "out": "", "hz": "30", "policy": "default", "jobs": "1", "seeds": "", "sites": ""}
	var verbose := false
	var quiet := false
	for arg in OS.get_cmdline_user_args():
		var text := String(arg).trim_prefix("--")
		var kv := text.split("=", true, 1)
		if kv[0] == "fast" and not opts.has("hz_set"):
			opts["hz"] = "15"
		elif kv[0] == "verbose":
			verbose = true
		elif kv[0] == "quiet":
			quiet = true
		elif kv[0] == "nostory":
			story_on = false
		elif opts.has(kv[0]) and kv.size() > 1:
			opts[kv[0]] = kv[1]
			if kv[0] == "hz":
				opts["hz_set"] = "1"
	if String(opts.sites) != "":
		sites_override = String(opts.sites)
		Scavenge.sites_path = sites_override
	var days := maxi(1, int(opts.days))
	var difficulty := clampi(int(opts.difficulty), 0, 2)
	var hz := clampf(float(opts.hz), 5.0, 60.0)
	var orders: bool = opts.policy != "none"
	var hide: bool = opts.policy == "keep"
	var informed: bool = opts.policy == "informed"
	var jobs := clampi(int(opts.jobs), 1, 32)
	var seeds: Array = []
	if String(opts.seeds) != "":
		for t in String(opts.seeds).split(","):
			if t.is_valid_int():
				seeds.append(t.to_int())
	else:
		for i in maxi(1, int(opts.games)):
			seeds.append(int(opts.seed) + i)
	if not quiet:
		var names := ["Story", "Standard", "Brutal"]
		print("Thirty Bells balance: %d games of %d days, %s, seeds from %d, %d Hz, %s%s" % [
			seeds.size(), days, names[difficulty], seeds[0], roundi(hz), ("hide-in-the-school policy" if hide else ("informed policy" if informed else "default policy")) if orders else "no orders",
			((", %d at a time" % jobs) if jobs > 1 and seeds.size() > 1 else "") + ("" if story_on else ", storyteller off")])
		print("")
		if jobs == 1 or seeds.size() == 1:
			_print_header()
	var games: Array = []
	if jobs > 1 and seeds.size() > 1 and not quiet:
		games = _play_in_workers(seeds, jobs, days, difficulty, hz, orders, hide, informed)
		_print_header()
		for i in games.size():
			_print_game(i + 1, games[i], verbose)
	else:
		for i in seeds.size():
			var r := play(seeds[i], difficulty, days, hz, orders, Callable(), hide, informed, story_on)
			games.append(r)
			if not quiet:
				_print_game(i + 1, r, verbose)
	var summary := summarise(games)
	if not quiet:
		_print_summary(summary)
	if opts.out != "":
		var f := FileAccess.open(String(opts.out), FileAccess.WRITE)
		if f == null:
			printerr("Could not write %s" % opts.out)
		else:
			f.store_string(JSON.stringify({"args": opts, "games": games, "summary": summary}, "  ", true, true))
			f.close()
			if not quiet:
				print("")
				print("Wrote %s" % opts.out)
	quit(0)


## Plays the seeds in `jobs` worker processes (this same script, with --quiet)
## and gathers their games in seed order. A worker that cannot be started or
## leaves no result has its seeds played here instead.
func _play_in_workers(seeds: Array, jobs: int, days: int, difficulty: int, hz: float, orders: bool, hide: bool = false, informed: bool = false) -> Array:
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var scratch := ProjectSettings.globalize_path("user://")
	var workers: Array = []
	for w in mini(jobs, seeds.size()):
		var mine: Array = []
		var i := w
		while i < seeds.size():
			mine.append(seeds[i])
			i += jobs
		var out := scratch.path_join("balance_worker_%d_%d.json" % [OS.get_process_id(), w])
		var names: Array = []
		for sd in mine:
			names.append(str(sd))
		var args := ["--headless", "--quiet", "--path", project, "--script", "res://tools/balance.gd", "--",
			"--seeds=%s" % ",".join(names), "--days=%d" % days, "--difficulty=%d" % difficulty, "--hz=%s" % str(hz),
			"--policy=%s" % ("keep" if hide else ("informed" if informed else ("default" if orders else "none"))), "--quiet", "--out=%s" % out]
		if sites_override != "":
			args.append("--sites=%s" % sites_override)
		if not story_on:
			args.append("--nostory")
		workers.append({"pid": OS.create_process(exe, args), "out": out, "seeds": mine})
	while true:
		var running := 0
		for w in workers:
			if w.pid > 0 and OS.is_process_running(w.pid):
				running += 1
		if running == 0:
			break
		OS.delay_msec(300)
	var games: Array = []
	for w in workers:
		var got := 0
		if FileAccess.file_exists(w.out):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(w.out)) == OK and typeof(json.data) == TYPE_DICTIONARY:
				for g in json.data.get("games", []):
					games.append(g)
					got += 1
			DirAccess.remove_absolute(w.out)
		if got != w.seeds.size():
			printerr("A worker gave %d of its %d games; playing the seeds here" % [got, w.seeds.size()])
			var have := {}
			for g in games:
				have[int(g.seed)] = true
			for sd in w.seeds:
				if not have.has(sd):
					games.append(play(sd, difficulty, days, hz, orders, Callable(), false, false, story_on))
	games.sort_custom(func(a, b): return a.seed < b.seed)
	return games


func _print_header() -> void:
	print("game  seed  outcome    day  alive dead turn left |  food water scrap meds ammo | walls%  down kills | trips treats makes  secs")


func _print_game(n: int, r: Dictionary, verbose: bool) -> void:
	var last: Dictionary = r.rows[r.rows.size() - 1]
	print("%4d %5d  %-9s %4d  %5d %4d %4d %4d | %5.1f %5.1f %5.1f %4.1f %4.0f | %5.0f%% %5d %5d | %5d %6d %5d %5.1f" % [
		n, r.seed, r.outcome, r.day, last.alive, last.dead, last.turned, last.left,
		last.food, last.water, last.scrap, last.meds, last.ammo,
		100.0 * last.wall_hp / last.wall_max, last.breached, last.kills, r.trips, r.treats, r.get("crafts", 0), r.took])
	if verbose:
		for note in r.notes:
			print("        day %2d %05.2f  %s" % [note.day, note.hour, note.text])


func _print_summary(summary: Dictionary) -> void:
	print("")
	print("Survived %d of %d games; median day reached %d; lost per game: %.2f died, %.2f turned, %.2f sent out" % [
		summary.survived, summary.games, summary.median_day, summary.mean_lost.dead, summary.mean_lost.turned, summary.mean_lost.left])
	var st: Dictionary = summary.mean_final_stock
	print("Mean stock at the end: food %.1f, water %.1f, scrap %.1f, meds %.1f, ammo %.0f" % [st.food, st.water, st.scrap, st.meds, st.ammo])
	print("")
	print("Day by day, the average over the games still standing at the start of the day:")
	print(" day games alive |  food water scrap meds ammo | walls%  walkers kills")
	for c in summary.curve:
		print("%4d %5d %5.1f | %5.1f %5.1f %5.1f %4.1f %4.0f | %5.0f%% %8.1f %5.0f" % [
			c.day, c.games, c.alive, c.food, c.water, c.scrap, c.meds, c.ammo, 100.0 * c.wall_hp / maxf(1.0, c.wall_max), c.walkers, c.kills])
