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
##   --fast           step the rules at 15 Hz instead of 30 (about twice as fast)
##   --hz=N           step at N Hz (overrides --fast)
##   --policy=none    nobody gives any order: what the colony does alone
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
##  - the infected are treated while there is medicine, and sent out through the
##    gate once delirious with none left.
## Bandages, stabilising and healing in bed are automatic in the game.
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")


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
	## Sites that help with each need, most useful first.
	const SITE_FOR := {"food": "houses", "water": "houses", "meds": "pharmacy", "scrap": "hardware", "ammo": "hardware"}

	var sim
	## What it has done: trips sent, treatments ordered, people sent out, repairs ordered.
	var trips := 0
	var treats := 0
	var sendouts := 0
	var repairs := 0
	## Lines of what it did: [{"day", "hour", "text"}].
	var notes: Array = []
	var _sent_day := 0
	var _last_treat := {}

	func _init(s) -> void:
		sim = s

	func tick() -> void:
		if sim.over != "":
			return
		_scavenge()
		_repair()
		_infection()

	func _note(text: String) -> void:
		notes.append({"day": sim.day, "hour": snappedf(sim.hour, 0.01), "text": text})

	## Free to be given a job: on the map, on their feet, on no order, and not busy treating someone.
	func _free(p) -> bool:
		if p.dead or p.downed or p.away != null or p.drafted or p.order != null:
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
			var id: String = SITE_FOR[need]
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
			if a.def.skills.Shooting != b.def.skills.Shooting:
				return a.def.skills.Shooting > b.def.skills.Shooting
			return a.def.skills.Leading > b.def.skills.Leading)
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
		for p in sim.people:
			if p.repair != null or not _free(p):
				continue
			if best == null or p.def.skills.Building > best.def.skills.Building:
				best = p
		return best

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
## "trips", "treats", "sendouts", "repairs", "notes", "took"}. `rows` has one
## entry for the start of each day (and one at the end of a lost game): see _row.
## `hz` is how many steps of the rules a second; `orders` false plays with no
## orders given at all; `setup`, if given, is called with the new Sim before the
## first step (the tests use it to play a cheap game).
static func play(seed_value: int, difficulty: int, days: int, hz: float = 30.0, orders: bool = true, setup: Callable = Callable()) -> Dictionary:
	var started := Time.get_ticks_msec()
	var g := Helpers.make(seed_value, difficulty)
	var sim = g.sim
	if setup.is_valid():
		setup.call(sim)
	var policy := Policy.new(sim)
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
	var survived: bool = sim.over == "" and sim.day > days
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
	var walkers := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying":
			walkers += 1
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
		"walkers": walkers,
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
	var opts := {"games": "8", "days": "10", "difficulty": "1", "seed": "1", "out": "", "hz": "30", "policy": "default"}
	var verbose := false
	for arg in OS.get_cmdline_user_args():
		var text := String(arg).trim_prefix("--")
		var kv := text.split("=", true, 1)
		if kv[0] == "fast" and not opts.has("hz_set"):
			opts["hz"] = "15"
		elif kv[0] == "verbose":
			verbose = true
		elif opts.has(kv[0]) and kv.size() > 1:
			opts[kv[0]] = kv[1]
			if kv[0] == "hz":
				opts["hz_set"] = "1"
	var games_n := maxi(1, int(opts.games))
	var days := maxi(1, int(opts.days))
	var difficulty := clampi(int(opts.difficulty), 0, 2)
	var first_seed := int(opts.seed)
	var hz := clampf(float(opts.hz), 5.0, 60.0)
	var orders: bool = opts.policy != "none"
	var names := ["Story", "Standard", "Brutal"]
	print("Last Bell balance: %d games of %d days, %s, seeds from %d, %d Hz, %s" % [games_n, days, names[difficulty], first_seed, roundi(hz), "default policy" if orders else "no orders"])
	print("")
	print("game  seed  outcome    day  alive dead turn left |  food water scrap meds ammo | walls%  down kills | trips treats  secs")
	var games: Array = []
	for i in games_n:
		var r := play(first_seed + i, difficulty, days, hz, orders)
		games.append(r)
		var last: Dictionary = r.rows[r.rows.size() - 1]
		print("%4d %5d  %-9s %4d  %5d %4d %4d %4d | %5.1f %5.1f %5.1f %4.1f %4.0f | %5.0f%% %5d %5d | %5d %6d %5.1f" % [
			i + 1, r.seed, r.outcome, r.day, last.alive, last.dead, last.turned, last.left,
			last.food, last.water, last.scrap, last.meds, last.ammo,
			100.0 * last.wall_hp / last.wall_max, last.breached, last.kills, r.trips, r.treats, r.took])
		if verbose:
			for note in r.notes:
				print("        day %2d %05.2f  %s" % [note.day, note.hour, note.text])
	var summary := summarise(games)
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
	if opts.out != "":
		var f := FileAccess.open(String(opts.out), FileAccess.WRITE)
		if f == null:
			printerr("Could not write %s" % opts.out)
		else:
			f.store_string(JSON.stringify({"args": opts, "games": games, "summary": summary}, "  ", true, true))
			f.close()
			print("")
			print("Wrote %s" % opts.out)
	quit(0)
