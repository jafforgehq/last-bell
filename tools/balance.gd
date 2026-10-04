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
##   --crew=3         play the small start (three people, the others come over the radio); default 6
##   --nostreets      no dead in the streets by day (to see what they change)
##   --novehicles     the policy does not go for vehicles or fuel and walks (to see what they change)
##   --nolots         the informed policy does not claim lots or wall the streets (to see what they change)
##   --campaign       play the long game of four seasons (--days=102 plays it through)
##   --nobuild        the informed policy does not build (to see what the buildings change)
##   --beds           the informed policy puts tents (and the bunk house) first when the school's beds are full (off by default: the numbers
##                    of before round 16, which built the bunk house last and never got to the tents)
##   --build-order=a,b  the informed policy builds only these, in this order (building ids), to see what one building is worth
##   --nostory        play with the storyteller off (no card at noon, no assembly at dawn), to see
##                    what the radio changes; by default it is on and the policy answers each card
##                    with the choice the card names as its default
##   --verbose        print what the policy did and who was lost, game by game
##   --avatar=none    (default) nobody is the player: the harness of before round 17, game for game
##   --avatar=idle    Ruth is the player and keeps her hands off, in the school gym (`Policy.KEEP_SPOTS[5]`): the community alone
##                    holds the nights, with the avatar counted in the night's size but not defending (round 19, the lab's `idle`)
##   --avatar=bot     the bot plays Ruth (tools/avatar_bot.gd: walks to the wall the night will break on, climbs the ladder, aims, shoots,
##                    answers the radio's calls, mends the wall by hand). Either avatar mode adds each night's row (`nights`) to a game and
##                    a table of them to the summary (what the walls lost, who fell, how often the avatar stood where the pressure was)
##   --nightstats     the same rows and table without an avatar (the night lab's `none`)
##   --base           round 25: in an avatar game (--avatar=idle|bot) the base management is ON (the briefing, the priorities, the dials, the problems and the
##                    dilemma: scripts/sim/briefing.gd and its four). Without it the five are OFF, so that the numbers of rounds 19 and 20 hold. No effect with
##                    --avatar=none
##   --data=path      read the nights' numbers (rally, plating, Big Nights...) from another nights.json (to try a number before it is in the game)
##   --out=path.json  also write everything (every game, every day) as JSON
##
## The default policy is what a sensible player does without thinking:
##  - every morning the jobs are set by need: three hands are kept for the workbench (ammo up
##    to 350, keeping 10 scrap), the wall crew (walls under 80%) and the vegetable beds, spread
##    by what is short, and the people beyond those three keep the lookout post, the
##    infirmary and the radio desk (a crew of six keeps all three, five lose the radio first,
##    three keep none); at the bell everyone goes to their post;
##  - in the morning (06:30 to 10:00), when food or water is under 4 days, or
##    meds under 3, or scrap under 10, or ammo under 60, the best two free
##    shooters go scavenging to the site that helps;
##  - the scrapyard is the site for scrap, then the hardware store;
##  - the infected are treated while there is medicine, and sent out through the
##    gate once delirious with none left;
##  - when the radio brings a card at noon it takes the answer the card names as its default
##    (a card with no choice is read); and when the dead come to the wall by day (stragglers)
##    the three best shooters stand to at their posts until they are put down.
## Bandages, stabilising and healing in bed are automatic in the game.
extends SceneTree

const Helpers := preload("res://tests/helpers.gd")
const Scavenge := preload("res://scripts/sim/scavenge.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const NightData := preload("res://scripts/sim/night_data.gd")

## Another sites file for the whole run (--sites=path): to try a site before it is in the game.
static var sites_override := ""
## The storyteller is on (see --nostory).
static var story_on := true
## The informed policy builds (see --nobuild), and what, in what order, if --build-order says (else BUILD_ORDER).
static var build_on := true
static var build_order_override: Array = []
## The informed policy builds beds first when the crew is at the cap (see --beds; off by default so the numbers match earlier rounds: a bot with a crew of nine against nights scaled for nine fares worse).
static var beds_on := false
## How many people a game starts with (see --crew).
static var crew_start := 6
## Play the long game of four seasons (see --campaign; --days=102 plays it through).
static var campaign := false
## The informed policy claims lots and walls the streets (see --nolots).
static var lots_on := true
## The policy goes for vehicles and rides them (see --novehicles).
static var vehicles_on := true
## The dead in the streets by day (see --nostreets).
static var streets_on := true
## Who plays the player's person (see --avatar): "none", "idle" or "bot". With either of the last two a game has Ruth as the player.
static var avatar_mode := "none"
## The rows of each night are kept even with no avatar (see --nightstats).
static var nightstats_on := false
## The base management of round 25 is on in an avatar game (see --base); off, `Helpers.quiet_base` switches its five modules off.
static var base_on := false


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
	## The stations' settings of a sensible player: make ammo up to BENCH_TARGET keeping BENCH_RESERVE scrap
	## for the walls, mend the walls that are under WALL_BELOW percent. These stations stay staffed.
	const BENCH_TARGET := 350.0
	const BENCH_RESERVE := 10.0
	const WALL_BELOW := 80.0
	## The desks, in the order a short-handed crew gives them up last: the lookout post, the infirmary, the
	## radio. Three hands are kept for the bench, the wall crew and the beds (FLEX_HANDS); only the people
	## beyond those keep a desk, so a crew of six keeps all three and a crew of three keeps none.
	const DESKS := ["watch", "infirmary", "radio"]
	const FLEX_HANDS := 3
	## Who is given which of the three moving stations first: the bench wants the best builder (ammo from scrap
	## scales with Building as nothing else does), the wall crew the next, the beds whoever is left.
	const PICK_ORDER := ["bench", "builders", "salvage", "garden"]
	## Building (the informed policy only): from BUILD_FROM_DAY, on a morning with nothing going up, it orders the
	## next building of BUILD_ORDER that it can pay for with BUILD_KEEP scrap to spare, at its home (`build.home_for`: round
	## 15; the first free one) (it saves up for the next one rather than skipping ahead). While a site is up the Builders get a hand
	## more, and the Salvage station, once there is one, gets people while the scrap is short (under SALVAGE_BELOW).
	const BUILD_ORDER := ["salvage_bench", "greenhouse", "workshop", "floodlights", "watchtower", "radio_mast", "bunk_house"]
	## Beds first (the settlement game): when the school is full and a caller is waiting, the next of these that has a home
	## free goes up before anything else (a tent is cheap: eight scrap), as soon as it can be paid with BUILD_KEEP to spare.
	const BED_ORDER := ["tents", "bunk_house"]
	const BUILD_FROM_DAY := 2
	const BUILD_KEEP := 12.0
	const SALVAGE_BELOW := 40.0
	## The settlement game's board (see _town_trip): a trip must be back by BACK_BY unless at least OVERNIGHT_HANDS
	## people stay at home; scouting while the fog is thick (until SCOUT_UNTIL_DAY, every SCOUT_GAP_DAYS); a nest is
	## cleared by a party whose Shooting adds up to CLEAR_SHOOTING; an outpost is claimed with CLAIM_KEEP scrap to spare.
	const BACK_BY := 18.5
	const OVERNIGHT_HANDS := 3
	const SCOUT_UNTIL_DAY := 10
	const SCOUT_GAP_DAYS := 2
	const CLEAR_SHOOTING := 12.0
	const CLEAR_FROM_DAY := 5
	const CLAIM_KEEP := 8.0
	## Lots (the informed policy only): a lot is claimed with LOT_KEEP scrap to spare, and a mouth's wall is
	## ordered with WALL_KEEP to spare, the one the forecast names first.
	const LOT_KEEP := 6.0
	## Vehicles (the settlement game): a place this many hours away on foot is worth a ride; fuel is looked for when the
	## tank is under FUEL_LOW; a vehicle waiting in a place is gone for from VEHICLE_FROM_DAY.
	const RIDE_FROM_H := 3.0
	const FUEL_LOW := 25.0
	const VEHICLE_FROM_DAY := 3
	const WALL_KEEP := 10.0
	## What it builds on the ring once a lot is claimed (the building that only stands there: the scrap yard, round 11
	## dropped the orchard and the cistern), after BUILD_ORDER.
	const RING_ORDER := ["scrap_yard"]
	## Saving for a lot: the bench keeps the price of it (and LOT_KEEP) in scrap while the ammo is above this.
	const LOT_AMMO_FLOOR := 150.0
	## One shortage moves at most this much of a person towards a station.
	const NEED_MAX := 1.5
	## Against dead at the wall by day this many of the best shooters stand to at their posts.
	const STAND_TO := 3
	## The informed policy places the crew on the decks from this hour (the forecast is there from 17:00, the bell
	## rings at 19:00): people at their stations work until they are called, so a player who knows the night's
	## plan leaves them at it as long as the walk to the decks allows.
	const PLACE_HOUR := 18.25

	var sim
	## Hide in the school gym from the bell to dawn instead of holding the posts.
	var hide := false
	## Use the forecast and the coverage: place the crew and set the alarm at dusk.
	var informed := false
	var _placed_day := -1
	var _jobs_day := -1
	var _last_jobs: Dictionary = {}
	var _lured_day := -1
	var _placed: Dictionary = {}
	## What it has done: trips sent, treatments ordered, people sent out, jobs given.
	var trips := 0
	var treats := 0
	var sendouts := 0
	var rides := 0
	var vehicles_enabled := true
	var lots_enabled := true
	var lots_claimed := 0
	var walls_ordered := 0
	var _lots_day := 0
	var scouts := 0
	var clears := 0
	var claims := 0
	var rescues := 0
	var _scouted_day := -10
	var moves := 0
	var builds_ordered := 0
	## Builds (and orders them): see BUILD_ORDER (`build_order`, when not empty, is used instead: --build-order).
	var builds := false
	var build_order: Array = []
	## Beds first when the school is full and a caller is waiting (BED_ORDER; --beds switches it on).
	var beds_first := true
	var _build_day := 0
	## The radio hour of a small start: who was put at the desk for it, and what they were doing.
	var _radio_day := 0
	var _radio_prev := {}
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
		_jobs()
		_radio_noon()
		if builds:
			_lots()
			_build()
		_scavenge()
		_infection()

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
			if p.dead or p.downed or p.away != null or p.player:
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
		# behind each wall that stands across a street
		if sim.lots.on:
			for m in sim.lots.mouths():
				if sim.lots.segment_at(String(m.id)) != null and m.post.has("pos"):
					ok.append(Vector2(float(m.post.pos[0]), float(m.post.pos[1])))
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
		var dusky: bool = sim.phase == "day" and hour >= float(sim.seasons.dusk_hour()) - 0.75 or sim.phase == "dusk"
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
			if not (p.dead or p.downed or p.away != null or p.player):
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
				var reach: float = sim.reach_at(p.gun, v, true)
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
			var reach2: float = sim.reach_at(p.gun, best, true)
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
		# (round 19: the avatar is not a worker: the policy gives the player no seat, no errand, no post)
		if p.player or p.dead or p.downed or p.away != null or p.drafted or p.order != null or sim.morale.breakdown(p):
			return false
		return sim.medical.goal_for(p) == null

	# ------------------------------------------------------------ scavenging --

	func _scavenge() -> void:
		if sim.town.on:
			_town_trip()
			return
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

	# ------------------------------------------------------------------ the lots --

	## What the first lot not yet claimed costs.
	func _lot_price() -> float:
		for l in sim.lots.lots():
			if not sim.lots.claimed(String(l.id)):
				return float(l.claim.get("scrap", 0))
		return 0.0

	## A lot that can be claimed but for the scrap: the other buildings wait (the policy saves for it).
	func _saving_for_a_lot() -> bool:
		if not lots_enabled or not sim.lots.on:
			return false
		for l in sim.lots.lots():
			var id := String(l.id)
			if sim.lots.claimed(id):
				continue
			var why: String = sim.lots.why_not_claim(id)
			if why.begins_with("it needs"):
				return true
			break
		return false

	## Each morning: claim a lot if it can be (one a day), and if nothing is going up put a wall across the
	## mouth the forecast names (else any open one of a claimed lot) with the best kit it can pay for.
	func _lots() -> void:
		if not lots_enabled or not sim.lots.on or sim.phase != "day" or _lots_day == sim.day or sim.hour < 6.9:
			return
		_lots_day = sim.day
		for l in sim.lots.lots():
			var id := String(l.id)
			if not sim.lots.claimed(id) and sim.lots.why_not_claim(id) == "" and float(sim.stock.scrap) >= float(l.claim.get("scrap", 0)) + LOT_KEEP:
				if sim.lots.claim(id):
					lots_claimed += 1
					# one switch: the streets are walled one after another as the scrap allows
					sim.lots.set_auto_walling(id, true)
					_note("claims %s and turns the standing order on" % id)
				break
		if not sim.build.active_site().is_empty():
			return
		var heading: Array = sim.waves.plan_for(sim.day).get("heading", [])
		var best_mouth := ""
		var best_rank := 9
		for m in sim.lots.mouths():
			var pl: Dictionary = sim.build.plot(String(m.id))
			if pl.is_empty() or not sim.lots.claimed(String(m.get("lot", ""))) or pl.building != "" or not pl.site.is_empty():
				continue
			var rank := 0 if heading.has(int(m.get("spawn", -1))) else 1
			if rank < best_rank:
				best_rank = rank
				best_mouth = String(m.id)
		if best_mouth == "":
			return
		var best_kit := ""
		var best_value := 0.0
		for kid in sim.lots.kits_for(best_mouth):
			var b: Dictionary = sim.build.building(String(kid))
			if float(sim.stock.scrap) < float(b.scrap) + WALL_KEEP:
				continue
			var value: float = float(b.hp) / maxf(1.0, float(b.scrap))
			if value > best_value:
				best_value = value
				best_kit = String(kid)
		if best_kit != "" and sim.build.order(best_mouth, best_kit):
			walls_ordered += 1
			_note("orders a wall across %s" % best_mouth)

	# ----------------------------------------------------------------- the board --

	## The settlement game's morning: claim an outpost if the scrap is there, then send the best free party to the
	## place that helps most (a rescue first, then what is lowest, then scouting while the fog is thick, then a nest).
	func _town_trip() -> void:
		_claim()
		if _sent_day == sim.day or sim.phase != "day" or sim.hour >= 10.0 or not sim.scavenge.can_send():
			return
		var free: Array = _free_by_shooting()
		if free.is_empty():
			return
		var sites: Array = sim.scavenge.available_sites()
		var pick := _town_pick(sites, free)
		if pick.is_empty():
			return
		var crew: Array = free.slice(0, int(pick.n))
		var vehicle := String(pick.get("vehicle", ""))
		if sim.scavenge.send(crew, String(pick.id), String(pick.action), vehicle):
			_sent_day = sim.day
			trips += 1
			match String(pick.action):
				"scout":
					scouts += 1
					_scouted_day = sim.day
				"clear":
					clears += 1
			if bool(pick.get("rescue", false)):
				rescues += 1
			if vehicle != "":
				rides += 1
			var names: Array = []
			for p in crew:
				names.append(p.first)
			_note("sent %s to %s (%s%s)" % [" and ".join(names), pick.id, pick.action, ", by " + sim.vehicles.name_of(vehicle).to_lower() if vehicle != "" else ""])

	func _claim() -> void:
		for s in sim.scavenge.available_sites():
			if bool(s.can_claim) and float(sim.stock.scrap) >= float(s.outpost.get("cost", 0.0)) + CLAIM_KEEP:
				if sim.town.claim(String(s.id)):
					claims += 1
					_note("claimed %s" % s.id)
					return

	func _free_by_shooting() -> Array:
		var free: Array = []
		for p in sim.people:
			if _free(p) and sim.scavenge.can_go(p):
				free.append(p)
		free.sort_custom(func(a, b):
			if a.skills.Shooting != b.skills.Shooting:
				return a.skills.Shooting > b.skills.Shooting
			return a.skills.Leading > b.skills.Leading)
		return free

	## What to do this morning: {"id", "action", "n", "rescue"} or {} for nothing. `free` is who can go, best first.
	func _town_pick(sites: Array, free: Array) -> Dictionary:
		var left: float = (float(sim.seasons.dusk_hour()) - 0.5) - float(sim.hour)
		var n := 2 if free.size() >= 3 else (1 if free.size() == 2 else 0)
		var here := _hands_home()
		# a rescue, if there is a bed for them
		if int(sim.recruits.housing_free()) >= 1 and n > 0:
			for s in sites:
				if bool(s.survivor) and (s.available or s.state == "cleared") and s.state != "claimed":
					var action := "clear" if (int(s.danger) >= 2 and n >= 2) else "loot"
					var ride := _ride_for(s, n)
					if _fits(s, action, left, here, n, ride) and _ok(free, s, action, n, ride):
						return {"id": s.id, "action": action, "n": n, "rescue": true, "vehicle": ride}
		# a vehicle waiting in a place, when the colony has none: go and try to get it running
		if vehicles_enabled and sim.vehicles.fleet.is_empty() and sim.day >= VEHICLE_FROM_DAY and n > 0:
			for s in sites:
				if String(s.get("vehicle_here", "")) != "" and s.available and s.state != "claimed" and int(s.danger) + int(s.nest.get("strength", 0)) < 4:
					if _fits(s, "loot", left, here, n, "") and _ok(free, s, "loot", n, ""):
						return {"id": s.id, "action": "loot", "n": n}
		# fuel, when there is a vehicle and the tank is low
		if vehicles_enabled and not sim.vehicles.fleet.is_empty() and float(sim.vehicles.fuel) < FUEL_LOW and n > 0:
			var fuel_at := ""
			var fuel_best := 0.0
			for s in sites:
				if s.available and s.state != "claimed" and s.loot.has("fuel"):
					var f_ride := _ride_for(s, n)
					if _fits(s, "loot", left, here, n, f_ride) and _ok(free, s, "loot", n, f_ride) and float(s.loot.fuel[1]) > fuel_best:
						fuel_best = float(s.loot.fuel[1])
						fuel_at = String(s.id)
			if fuel_at != "":
				return {"id": fuel_at, "action": "loot", "n": n, "vehicle": _ride_for(_site_by(sites, fuel_at), n)}
		# what is lowest
		var needs := _needs()
		for need in needs:
			var best := ""
			var best_score := 0.0
			var best_ride := ""
			var best_n := n
			for s in sites:
				if not s.available or s.state == "claimed" or not s.loot.has(need):
					continue
				var ride := _ride_for(s, n)
				var crew_n := _crew_for(ride, free, n)
				if not _fits(s, "loot", left, here, maxi(crew_n, 1), ride) or not _ok(free, s, "loot", crew_n, ride):
					continue
				var span: Array = s.loot[need]
				var danger := float(s.danger) + float(s.nest.get("strength", 0))
				if danger >= 3.0 and _shooting(free.slice(0, crew_n)) < 10.0:
					continue
				var cargo := float(sim.vehicles.kind_of(ride).get("cargo", 1.0)) if ride != "" else 1.0
				var score: float = (float(span[0]) + float(span[1])) * 0.5 * cargo / (1.0 + 0.15 * sim.scavenge.action_hours(String(s.id), "loot", ride)) / (1.0 + 0.25 * danger)
				if score > best_score:
					best_score = score
					best = String(s.id)
					best_ride = ride
					best_n = crew_n
			if best != "" and best_n > 0:
				return {"id": best, "action": "loot", "n": best_n, "vehicle": best_ride}
		# nothing known has it, or the fog is still thick: look further
		if (not needs.is_empty() or sim.day <= SCOUT_UNTIL_DAY) and sim.day - _scouted_day >= SCOUT_GAP_DAYS:
			var from := _scout_from(sites, left)
			if from != "":
				return {"id": from, "action": "scout", "n": 1, "vehicle": _ride_for(_site_by(sites, from), 1)}
		# a nest, when there are hands to spare for it
		if sim.day >= CLEAR_FROM_DAY and n >= 2 and free.size() >= 3 and _shooting(free.slice(0, 2)) >= CLEAR_SHOOTING:
			var weakest := ""
			var weak := 99
			for s in sites:
				var st := int(s.nest.get("strength", 0))
				if st > 0 and s.state == "known" and st < weak and _fits(s, "clear", left, here, 2, "") and _ok(free, s, "clear", 2, ""):
					weak = st
					weakest = String(s.id)
			if weakest != "":
				return {"id": weakest, "action": "clear", "n": 2}
		return {}

	func _site_by(sites: Array, id: String) -> Dictionary:
		for s in sites:
			if String(s.id) == id:
				return s
		return {}

	## The vehicle this site is worth: one that is parked, fits the party and has the fuel, for a place far enough
	## (or across the river), else "" (on foot).
	func _ride_for(s: Dictionary, n: int) -> String:
		if not vehicles_enabled or sim.vehicles.fleet.is_empty():
			return ""
		var far: bool = float(s.get("hours", 0.0)) >= RIDE_FROM_H or bool(s.get("needs_vehicle", false))
		if not far:
			return ""
		for v in sim.vehicles.parked():
			var seats := int(sim.vehicles.kind_of(String(v.id)).get("seats", 2))
			if sim.vehicles.why_not_use(String(v.id), mini(n, seats), String(s.id)) == "":
				return String(v.id)
		return ""

	## How many go: two on foot (three people free), up to the seats by vehicle (one hand stays at home).
	func _crew_for(ride: String, free: Array, n: int) -> int:
		if ride == "":
			return n
		var seats := int(sim.vehicles.kind_of(ride).get("seats", 2))
		# three at most (two stay at home to hold the wall) unless the crew is large
		return clampi(mini(mini(seats, 2 if free.size() < 7 else 4), free.size() - 1), 1, 6)

	## Whether the rules let this party take this action at this place (a place across the river is refused on foot).
	func _ok(free: Array, s: Dictionary, action: String, n: int, ride: String) -> bool:
		return sim.scavenge.why_not_action(free.slice(0, n), String(s.id), action, ride) == ""

	func _shooting(people: Array) -> float:
		var t := 0.0
		for p in people:
			t += float(p.skills.Shooting)
		return t

	## People at home: alive, up and not away.
	func _hands_home() -> int:
		var here := 0
		for p in sim.people:
			if not p.dead and not p.downed and p.away == null and not p.player:
				here += 1
		return here

	## A trip fits when it is back before dusk, or when enough hands stay to hold the night.
	func _fits(s: Dictionary, action: String, left: float, here: int, n: int, ride: String = "") -> bool:
		var h: float = sim.scavenge.action_hours(String(s.id), action, ride)
		if h <= left:
			return true
		return here - n >= OVERNIGHT_HANDS and h <= 22.0

	## The known place with the most hidden places within the scouting radius that can be reached and left today.
	func _scout_from(sites: Array, left: float) -> String:
		var best := ""
		var best_n := 0
		for s in sites:
			var ride := _ride_for(s, 1)
			if bool(s.get("needs_vehicle", false)) and ride == "":
				continue
			if sim.scavenge.action_hours(String(s.id), "scout", ride) > left:
				continue
			var near := 0
			for q in sim.town.all_places():
				if String(q.state) == "unknown" and Vector2(q.pos).distance_to(Vector2(s.pos)) <= sim.town.SCOUT_RADIUS:
					near += 1
			if near > best_n:
				best_n = near
				best = String(s.id)
		return best

	## The stocks that are low, most urgent first (food, water, meds, scrap, ammo).
	func _needs() -> Array:
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
		return needs

	# ------------------------------------------------------------------ jobs --

	## Every morning the crew's jobs are set by what the colony needs: three hands (FLEX_HANDS) are spread over
	## the workbench, the wall crew and the vegetable beds by need (the garden when the food runs short, the
	## bench when the ammo does, the wall crew when the walls are worn), and the people beyond them keep the
	## desks (DESKS: the game starts with all three staffed; a shrinking crew gives up the radio first, then
	## the infirmary). The stations' settings are a sensible player's: make ammo to BENCH_TARGET while keeping
	## BENCH_RESERVE scrap, mend walls under WALL_BELOW.
	func _jobs() -> void:
		if sim.phase != "day" or _jobs_day == sim.day or sim.hour < 6.6:
			return
		_jobs_day = sim.day
		sim.jobs.set_setting("bench", "ammo_target", BENCH_TARGET)
		var reserve := BENCH_RESERVE
		if builds and _saving_for_a_lot() and float(sim.stock.ammo) > LOT_AMMO_FLOOR:
			reserve = _lot_price() + LOT_KEEP
		sim.jobs.set_setting("bench", "scrap_reserve", reserve)
		sim.jobs.set_setting("builders", "repair_below", WALL_BELOW)
		var alive: Array = []
		for p in sim.people:
			if not (p.dead or p.turned or p.player):
				alive.append(p)
		# the desks that are kept for a crew this size: whoever is on them stays; a vacancy goes to the best fit
		var kept: Array = DESKS.slice(0, clampi(alive.size() - FLEX_HANDS, 0, DESKS.size()))
		for id in kept:
			if sim.jobs.crew_of(id).is_empty():
				var best = null
				var best_score := -1.0e9
				for p in alive:
					var j: String = sim.jobs.job_of(p)
					if j in kept and sim.jobs.crew_of(j).size() <= 1:
						continue
					var score: float = sim.jobs._fit(p, id)
					if score > best_score:
						best_score = score
						best = p
				if best != null and sim.jobs.assign(best, id):
					moves += 1
					_note("%s takes the %s" % [best.first, String(sim.jobs.station(id).name).to_lower()])
		var flex: Array = []
		for p in alive:
			if not (sim.jobs.job_of(p) in kept):
				flex.append(p)
		if flex.is_empty():
			return
		var food_need := clampf(5.0 - sim.supplies.days_left("food"), 0.0, NEED_MAX)
		var ammo_need := 0.0
		if float(sim.stock.scrap) > BENCH_RESERVE:
			ammo_need = clampf((BENCH_TARGET - float(sim.stock.ammo)) / 100.0, 0.0, NEED_MAX)
		var worst := 100.0
		for seg in sim.segments:
			worst = minf(worst, 100.0 * seg.hp / seg.max_hp)
		var wall_need := clampf((WALL_BELOW - worst) / 10.0, 0.0, NEED_MAX)
		var site_need := 1.0 if not sim.build.active_site().is_empty() else 0.0
		var score := {"garden": 1.0 + food_need, "builders": 1.0 + wall_need + site_need, "bench": 0.5 + ammo_need}
		if sim.build.built("salvage_bench"):
			score["salvage"] = 0.6 + clampf((SALVAGE_BELOW - float(sim.stock.scrap)) / 10.0, 0.0, NEED_MAX)
		# the stations in the order the colony needs a person at them (each person placed lowers a station's need)
		var picks: Array = []
		for i in flex.size():
			var pick := "builders"
			for id in ["garden", "bench", "salvage"]:
				if score.has(id) and float(score[id]) > float(score[pick]):
					pick = id
			picks.append(pick)
			score[pick] = float(score[pick]) - 1.0
		# the two best shooters are the ones the morning trips take away: the people who stay home get the
		# stations that need someone there all day, and those who go are given the last of them
		var shooters := alive.duplicate()
		shooters.sort_custom(func(a, b): return a.skills.Shooting > b.skills.Shooting)
		var away_pair: Array = shooters.slice(0, 2)
		var stayers: Array = []
		var goers: Array = []
		for p in flex:
			sim.jobs.unassign(p)
			if p in away_pair:
				goers.append(p)
			else:
				stayers.append(p)
		picks.sort_custom(func(a, b): return PICK_ORDER.find(a) < PICK_ORDER.find(b))
		for pick in picks:
			var pool: Array = stayers if not stayers.is_empty() else goers
			var chosen = pool[0]
			for p in pool:
				# the beds suit whoever is least wanted at the bench or the wall; those want the best builders
				var better: bool = p.skills.Building < chosen.skills.Building if pick in ["garden", "salvage"] else p.skills.Building > chosen.skills.Building
				if better:
					chosen = p
			pool.erase(chosen)
			if sim.jobs.assign(chosen, pick):
				if pick != String(_last_jobs.get(chosen.id, "")):
					moves += 1
					_note("%s goes to the %s" % [chosen.first, String(sim.jobs.station(pick).name).to_lower()])
				_last_jobs[chosen.id] = pick

	# ------------------------------------------------------------ the radio hour --

	## In a small start the radio is how the crew grows, and a call comes only if someone is at the desk at
	## noon: when one is due and nobody sits there, the best leader goes to the desk at 11:20 and goes
	## back to what they were doing at 12:40.
	func _radio_noon() -> void:
		if sim.phase != "day" or not sim.recruits.small:
			return
		var h: float = sim.hour
		if h >= 11.3 and h < 12.0 and _radio_day != sim.day and sim.recruits.call_due() and sim.jobs.crew_of("radio").is_empty():
			_radio_day = sim.day
			var best = null
			for p in sim.people:
				if _free(p) and (best == null or p.skills.Leading > best.skills.Leading):
					best = p
			if best != null:
				_radio_prev = {"id": best.id, "job": sim.jobs.job_of(best)}
				sim.jobs.assign(best, "radio")
				_note("%s goes to the radio for the noon call" % best.first)
		elif h >= 12.6 and not _radio_prev.is_empty():
			for p in sim.people:
				if p.id == _radio_prev.id and sim.jobs.job_of(p) == "radio":
					sim.jobs.assign(p, String(_radio_prev.job))
			_radio_prev = {}

	# -------------------------------------------------------------- building --

	## See BUILD_ORDER.
	func _build() -> void:
		if sim.phase != "day" or _build_day == sim.day or sim.hour < 6.7 or sim.day < BUILD_FROM_DAY:
			return
		_build_day = sim.day
		if not sim.build.active_site().is_empty():
			return
		if _saving_for_a_lot():
			return
		var order: Array = build_order if not build_order.is_empty() else BUILD_ORDER
		if sim.lots.on and not sim.lots.claimed_on.is_empty():
			order = order + RING_ORDER
		# the crew is at the cap and someone is waiting to call: beds before anything else
		if beds_first and sim.recruits.small and sim.recruits.housing_free() < 1 and (not sim.recruits.queue.is_empty() or sim.recruits.generated < sim.recruits.MAX_GENERATED):
			for id in BED_ORDER:
				var home: String = sim.build.home_for(String(id))
				if home == "":
					continue
				var b: Dictionary = sim.build.building(String(id))
				if float(sim.stock.scrap) < float(b.scrap) + BUILD_KEEP:
					return
				if sim.build.why_not(home, String(id)) == "" and sim.build.order(home, String(id)):
					builds_ordered += 1
					_note("orders the %s at %s (the beds are full)" % [String(b.name).to_lower(), String(sim.build.plot(home).name).to_lower()])
				return
		for id in order:
			if String(id) in RING_ORDER:
				# ring buildings may stand more than once: one of each is enough to begin with
				if sim.build.count(String(id)) >= 1:
					continue
			elif sim.build.built(String(id)):
				continue
			var b: Dictionary = sim.build.building(String(id))
			if float(sim.stock.scrap) < float(b.scrap) + BUILD_KEEP:
				return
			# a building goes to its own home (round 15: nobody picks a plot; the first free home of the building)
			var home: String = sim.build.home_for(String(id))
			if home != "" and sim.build.why_not(home, String(id)) == "":
				if sim.build.order(home, String(id)):
					builds_ordered += 1
					_note("orders the %s at %s" % [String(b.name).to_lower(), String(sim.build.plot(home).name).to_lower()])
			return

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
## "trips", "treats", "sendouts", "moves", "notes", "took"}. `rows` has one
## entry for the start of each day (and one at the end of a lost game): see _row.
## `hz` is how many steps of the rules a second; `orders` false plays with no
## orders given at all; `hide` makes the crew spend every night in the school gym; `setup`, if given, is called with the new Sim before the
## first step (the tests use it to play a cheap game).
static func play(seed_value: int, difficulty: int, days: int, hz: float = 30.0, orders: bool = true, setup: Callable = Callable(), hide: bool = false, informed: bool = false, story: bool = true) -> Dictionary:
	var started := Time.get_ticks_msec()
	var g := Helpers.make(seed_value, difficulty, crew_start, campaign)
	var sim = g.sim
	sim.streets.enabled = streets_on
	# the storyteller: on (the radio brings its cards, the dawn has its assembly) unless asked not to
	sim.storyteller.enabled = story
	# the avatar (round 19, --avatar): Ruth is the player; an idle one stands in the school gym, the bot plays her
	var bot = null
	if avatar_mode != "none":
		sim.avatar.set_player("ruth")
		if not base_on:
			Helpers.quiet_base(sim)
		bot = BotLib.AvatarBot.new(sim, avatar_mode)
	var stats = BotLib.NightStats.new(sim, avatar_mode) if (avatar_mode != "none" or nightstats_on) else null
	if setup.is_valid():
		setup.call(sim)
	var policy := policy_for(sim, hide, informed)
	var dt := 1.0 / hz
	var every := maxi(1, roundi(hz))
	var rows: Array = [_row(sim)]
	var gone := {}
	var notes: Array = []
	var last_day: int = sim.day
	var step := 0
	var ride_watch := {}
	var ride_log: Array = []
	while sim.over == "" and sim.day <= days:
		if bot != null:
			bot.step(dt)
		sim.update(dt)
		if stats != null:
			stats.observe(dt)
		step += 1
		if not ride_watch.is_empty() or not sim.scavenge.parties.is_empty():
			_watch_rides(sim, ride_watch, ride_log)
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
	if stats != null:
		stats.finish()
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
		"town": _town_row(sim, policy),
		"ride_overhead": ride_log,
		"season": sim.seasons.index,
		"lots": {"claimed": policy.lots_claimed, "walls": policy.walls_ordered, "standing": _walls_standing(sim)} if sim.lots.on else {},
		"moves": policy.moves,
		"builds": policy.builds_ordered,
		"cards": policy.cards,
		"notes": all_notes,
		"took": snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1),
	}
	if stats != null:
		result["nights"] = stats.rows
		result["avatar"] = avatar_mode
	g.world.free()
	return result


## The policy of a game with the switches of this run (the flags above) set on it: the informed one builds, claims, rides and so on
## unless a flag says not. `play` and the night lab (tools/night_lab.gd) make theirs here.
static func policy_for(sim, hide: bool, informed: bool) -> Policy:
	var policy := Policy.new(sim)
	policy.hide = hide
	policy.informed = informed
	policy.builds = informed and build_on
	policy.lots_enabled = lots_on
	policy.vehicles_enabled = vehicles_on
	policy.build_order = build_order_override
	policy.beds_first = beds_on
	return policy


## Follows the parties that go by vehicle for what the animation of the trip costs (round 15: the walk to the car, the
## doors, the drive out and in, the people getting out; scavenge.gd): when one of them is over, `log` gets {"n", "out_min"
## (game minutes from the send to the car leaving the map), "in_min" (from the hour the party was due to the last person
## being home), "extra_min" (how much later they are home than the plain hours of the trip said)}.
static func _watch_rides(sim, watch: Dictionary, log: Array) -> void:
	var live := {}
	for party in sim.scavenge.parties:
		if String(party.get("vehicle", "")) == "":
			continue
		var n := int(party.n)
		live[n] = true
		if not watch.has(n):
			watch[n] = {"sent": float(sim.clock_min), "plain_due": float(party.return_at), "away": -1.0, "due": -1.0, "state": "", "due_day": -1}
		var w: Dictionary = watch[n]
		var st := String(party.state)
		if st != String(w.state):
			w["state"] = st
			if st == "away" and float(w.away) < 0.0:
				w["away"] = float(sim.clock_min)
			if st == "driving_in" and float(w.due) < 0.0:
				w["due"] = float(sim.clock_min)
				w["due_day"] = int(floor((float(sim.clock_min) / 60.0 + 7.0) / 24.0))
	for n in watch.keys():
		if live.has(n):
			continue
		var w: Dictionary = watch[n]
		watch.erase(n)
		if float(w.away) >= 0.0 and float(w.due) >= 0.0:    # (a trip that went and came home by car)
			# the hours of the day it was due by the plain hours, and whether the drives pushed it past dusk and so to the next day
			var plain_h := fposmod(float(w.plain_due) / 60.0 + 7.0, 24.0)
			var plain_day := int(floor((float(w.plain_due) / 60.0 + 7.0) / 24.0))
			var pushed: bool = plain_h < float(sim.seasons.dusk_hour()) and int(w.due_day) > plain_day
			log.append({"n": n, "out_min": snappedf(float(w.away) - float(w.sent), 0.1), "in_min": snappedf(float(sim.clock_min) - float(w.due), 0.1), "extra_min": snappedf(float(sim.clock_min) - float(w.plain_due), 0.1), "pushed_past_dusk": pushed})


## How many walls stand across the streets of the lots.
static func _walls_standing(sim) -> int:
	var n := 0
	for m in sim.lots.mouths():
		if sim.lots.segment_at(String(m.id)) != null:
			n += 1
	return n


## What the board looks like at the end of a settlement game, and what the policy did on it.
static func _town_row(sim, policy) -> Dictionary:
	if not sim.town.on:
		return {}
	var known := 0
	var cleared := 0
	var claimed := 0
	var nests := 0
	for p in sim.town.all_places():
		if p.state != "unknown":
			known += 1
		if p.state == "cleared":
			cleared += 1
		if p.state == "claimed":
			claimed += 1
		if int(p.get("nest", {}).get("strength", 0)) > 0 and p.state != "cleared" and p.state != "claimed":
			nests += 1
	return {"known": known, "cleared": cleared, "claimed": claimed, "nests_left": nests, "scouts": policy.scouts, "clears": policy.clears, "claims": policy.claims, "rescues": policy.rescues, "rides": policy.rides, "vehicles": sim.vehicles.fleet.size(), "fuel": snappedf(sim.vehicles.fuel, 0.1)}


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
		"built": _standing(sim),
		"walkers": walkers,
		"runners": runners,
		"brutes": brutes,
	}


## How many buildings stand.
static func _standing(sim) -> int:
	var n := 0
	for pl in sim.build.plots():
		if pl.building != "":
			n += 1
	return n


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
	var rides := {"trips": 0, "out_min": 0.0, "in_min": 0.0, "extra_min": 0.0, "max_extra_min": 0.0, "pushed_past_dusk": 0}
	for game in games:
		for r in game.get("ride_overhead", []):
			rides.trips += 1
			rides.out_min += float(r.out_min)
			rides.in_min += float(r.in_min)
			rides.extra_min += float(r.extra_min)
			rides.max_extra_min = maxf(float(rides.max_extra_min), float(r.extra_min))
			if bool(r.get("pushed_past_dusk", false)):
				rides.pushed_past_dusk += 1
	if int(rides.trips) > 0:
		for k in ["out_min", "in_min", "extra_min"]:
			rides[k] = snappedf(float(rides[k]) / float(rides.trips), 0.1)
	var games_nights: Array = []
	for game in games:
		if game.has("nights"):
			games_nights.append(game.nights)
	var result := {
		"games": games.size(),
		"survived": survived,
		"median_day": reached[reached.size() / 2] if not reached.is_empty() else 0,
		"mean_lost": lost,
		"mean_final_stock": final_stock,
		"curve": curve,
		"rides": rides,
	}
	# (only when the games have night rows: the summary of a game with no avatar is the old one, key for key)
	if not games_nights.is_empty():
		result["games_nights"] = games_nights
	return result


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
		elif kv[0] == "nobuild":
			build_on = false
		elif kv[0] == "beds":
			beds_on = true
		elif kv[0] == "crew" and kv.size() > 1:
			crew_start = clampi(int(kv[1]), 3, 6)
		elif kv[0] == "campaign":
			campaign = true
		elif kv[0] == "nolots":
			lots_on = false
		elif kv[0] == "novehicles":
			vehicles_on = false
		elif kv[0] == "nostreets":
			streets_on = false
		elif kv[0] == "nightstats":
			nightstats_on = true
		elif kv[0] == "base":
			base_on = true
		elif kv[0] == "avatar" and kv.size() > 1:
			if not ["none", "idle", "bot"].has(String(kv[1])):
				printerr("--avatar takes none, idle or bot (not '%s')" % kv[1])
				quit(2)
				return
			avatar_mode = String(kv[1])
		elif kv[0] == "data" and kv.size() > 1:
			# another nights.json for the whole run (the tuning: a number tried before it is in the game)
			NightData.data_path = String(kv[1])
			NightData.forget()
		elif kv[0] == "build-order" and kv.size() > 1:
			build_order_override = String(kv[1]).split(",")
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
			((", %d at a time" % jobs) if jobs > 1 and seeds.size() > 1 else "") + ("" if story_on else ", storyteller off") + ("" if avatar_mode == "none" else ", avatar: %s" % avatar_mode)])
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
		if not build_on:
			args.append("--nobuild")
		if beds_on:
			args.append("--beds")
		if crew_start != 6:
			args.append("--crew=%d" % crew_start)
		if campaign:
			args.append("--campaign")
		if not lots_on:
			args.append("--nolots")
		if not vehicles_on:
			args.append("--novehicles")
		if not streets_on:
			args.append("--nostreets")
		if not build_order_override.is_empty():
			args.append("--build-order=%s" % ",".join(build_order_override))
		if avatar_mode != "none":
			args.append("--avatar=%s" % avatar_mode)
		if nightstats_on:
			args.append("--nightstats")
		if base_on:
			args.append("--base")
		if NightData.data_path != NightData.DATA_PATH:
			args.append("--data=%s" % NightData.data_path)
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
	print("game  seed  outcome    day  alive dead turn left |  food water scrap meds ammo | walls%  down kills | trips treats moves builds  secs")


func _print_game(n: int, r: Dictionary, verbose: bool) -> void:
	var last: Dictionary = r.rows[r.rows.size() - 1]
	print("%4d %5d  %-9s %4d  %5d %4d %4d %4d | %5.1f %5.1f %5.1f %4.1f %4.0f | %5.0f%% %5d %5d | %5d %6d %5d %6d %5.1f" % [
		n, r.seed, r.outcome, r.day, last.alive, last.dead, last.turned, last.left,
		last.food, last.water, last.scrap, last.meds, last.ammo,
		100.0 * last.wall_hp / last.wall_max, last.breached, last.kills, r.trips, r.treats, r.get("moves", 0), r.get("builds", 0), r.took])
	if verbose:
		for note in r.notes:
			print("        day %2d %05.2f  %s" % [note.day, note.hour, note.text])


func _print_summary(summary: Dictionary) -> void:
	print("")
	print("Survived %d of %d games; median day reached %d; lost per game: %.2f died, %.2f turned, %.2f sent out" % [
		summary.survived, summary.games, summary.median_day, summary.mean_lost.dead, summary.mean_lost.turned, summary.mean_lost.left])
	var st: Dictionary = summary.mean_final_stock
	print("Mean stock at the end: food %.1f, water %.1f, scrap %.1f, meds %.1f, ammo %.0f" % [st.food, st.water, st.scrap, st.meds, st.ammo])
	var rides: Dictionary = summary.get("rides", {})
	if int(rides.get("trips", 0)) > 0:
		print("Trips by vehicle: %d; extra game minutes for each (the walk to the car, the doors, the drives): %.0f from the send to the car leaving the map, %.0f from the due hour to everyone home; %.0f later home than the plain hours (at most %.0f); %d of them were pushed past dusk, so home the next morning" % [
			int(rides.trips), float(rides.out_min), float(rides.in_min), float(rides.extra_min), float(rides.max_extra_min), int(rides.pushed_past_dusk)])
	var nights: Array = []
	for game_nights in summary.get("games_nights", []):
		nights.append_array(game_nights)
	if not nights.is_empty():
		print("")
		print("The nights (held: no wall of the compound fell and nobody died; present: the share of the pressed moments the avatar stood within the rally's reach):")
		for line in BotLib.table_lines(nights):
			print(line)
		var wiped := 0
		for game_nights in summary.get("games_nights", []):
			if not game_nights.is_empty() and bool(game_nights[game_nights.size() - 1].get("over", false)):
				wiped += 1
		print("Games lost in a night: %d of %d" % [wiped, int(summary.games)])
	print("")
	print("Day by day, the average over the games still standing at the start of the day:")
	print(" day games alive |  food water scrap meds ammo | walls%  walkers kills")
	for c in summary.curve:
		print("%4d %5d %5.1f | %5.1f %5.1f %5.1f %4.1f %4.0f | %5.0f%% %8.1f %5.0f" % [
			c.day, c.games, c.alive, c.food, c.water, c.scrap, c.meds, c.ammo, 100.0 * c.wall_hp / maxf(1.0, c.wall_max), c.walkers, c.kills])
