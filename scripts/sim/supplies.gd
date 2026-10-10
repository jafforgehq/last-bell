## Food, water, scrap, meds and ammo: meals and thirst, the sources, what
## repairs cost, and how hungry or thirsty people perform.
##
## Times are game hours (one is 20 real seconds at normal speed). The rules' day
## turns over at 06:30, so a "day" here runs from 06:30 to 06:30 and holds the
## day's three meals (07:00, 13:00, 19:00).
##
## NEEDS (One House with a pack, PH10): the person who carries the pack is the one exception to "everyone on the map is served": the stores serve her only at the base (`_out_of_the_base`), a meal that comes
## up while she is out is served the moment she is back (`_serve_owed`), and out in the town she eats and drinks from her pack (scripts/town/inv.gd `use_item`). The crew and every other game are served as ever.
##
## Alerts raised: `low-food`, `low-water`, `low-ammo`, `no-scrap`, `rain`. The only event
## added is the ordinary {"type": "banner", "text", "sub"}, "Short rations".
##
## From the buildings (build.gd) it reads `garden_base`: the greenhouse beds add to the food the
## vegetable beds pay each dawn (`roll_dawn`).
extends RefCounted

## The hours of the day's three meals.
const MEAL_HOURS := [7.0, 13.0, 19.0]
## What one meal takes from the stores, for each person who is on the map.
const FOOD_PER_MEAL := 1.0 / 3.0
const WATER_PER_MEAL := 0.5
## A person who is given at least this part of a share has had a proper meal or drink.
const FED_PART := 0.25
## Game hours without a proper meal (food) or drink (water) before people work
## and aim worse, and before they start to lose health.
const HUNGRY_H := 18.0
const THIRSTY_H := 14.0
const STARVING_H := 36.0
const PARCHED_H := 24.0
## How well a hungry or thirsty person works (1.0 is normal).
const WEAK_PERF := 0.8
## Health lost per game hour while starving or parched.
const STARVE_LOSS_PER_H := 1.0
## The hour the day turns over and the garden's small share and the barrels pay out.
const DAWN_HOUR := 6.5
## The vegetable beds (the Vegetable beds station): a small share grows unattended and is paid each
## dawn (if anyone is home), and each person working the beds (`jobs.working("garden")`) grows this
## much food for every game hour of work. Hector alone (about twelve hours a day) is worth the 3
## food the beds used to pay each dawn, two gardeners about 5.4. A greenhouse adds to the dawn's share
## (the buildings' `garden_base`).
const GARDEN_BASE := 0.6
const GARDEN_FOOD_PER_HOUR := 0.2
## The two rain barrels give this much on a clear day and on a rainy one (the chance of rain is
## for each day).
const BARREL_WATER := 2.0
const BARREL_WATER_RAIN := 10.0
const RAIN_CHANCE := 1.0 / 3.0
## Health points of repair that one scrap pays for.
const REPAIR_PER_SCRAP := 10.0
## What a living person uses in a day: the basis of days_left.
const FOOD_PER_DAY := 1.0
const WATER_PER_DAY := 1.5
## Fewer days of food or water than this is low: an alert, repeated at most
## every LOW_REPEAT_MIN game minutes, and shown for LOW_TTL seconds.
const LOW_DAYS := 2.0
const LOW_REPEAT_MIN := 60.0
const LOW_TTL := 10.0
## The marks on a person's card (the same orange and red as the HUD).
const WARN := Color("#e8953a")
const DANGER := Color("#e0584a")
## Less ammo than this in the stock is low: an alert (raised at most every six
## times LOW_REPEAT_MIN).
const LOW_AMMO := 60.0
## The stock below which the ammo alert is raised (`LOW_AMMO` unless a run says otherwise: the One House run keeps few rounds on purpose, 10).
var low_ammo := LOW_AMMO
## Slack for float noise: a stock under this is empty; a meal time that came up
## within a step is on time to within this many game hours.
const EPS := 1.0e-9
const LATE_SLACK_H := 1.0e-4
## The stores live in the yard. While the dead are in it they ruin what is there:
## each of them takes this share of every stock each second (20 of them for two
## minutes cost about 21% of everything). This is what falling back costs.
const LOOT_RATE := 1.0e-4
## "Never raised" for the alert timers (game minutes since the run began).
const NEVER := -1.0e9

var sim
## Turn off to see what the stores alone would last (tests and balance checks).
## The weather still rolls each dawn.
var sources_on := true
## The rules' day the meal counter belongs to, and how many of that day's three
## meals have been served or have passed.
var meal_day := 0
var meals_done := 0
## The rules' day the dawn sources were last rolled for.
var sources_day := 0
## Whether the last meal left somebody without, so that the banner comes once
## per shortage and not at every meal.
var short_of := {"food": false, "water": false}
## When (sim.clock_min) each low-stock alert was last raised.
var low_alert_min := {"food": NEVER, "water": NEVER, "ammo": NEVER}
var _spots := {}


func setup(s) -> void:
	sim = s
	_sync_clock()


## Called at the start of a run (after Sim.start_run set the stocks and clock):
## everyone is fed, the meals already passed today are not owed, and the day's
## weather is the clear one the run starts with.
func start() -> void:
	for p in sim.people:
		p.hunger_h = 0.0
		p.thirst_h = 0.0
	short_of = {"food": false, "water": false}
	low_alert_min = {"food": NEVER, "water": NEVER, "ammo": NEVER}
	_sync_clock()


## Every step: the dawn sources, the meals, hunger and thirst, the alerts.
func update(dt: float) -> void:
	if sim.day != sources_day:
		roll_dawn()
	_garden(sim.game_hours(dt))
	_serve_meals(dt)
	_serve_owed()
	_needs(sim.game_hours(dt))
	_low_stock_alerts()
	_ruin(dt)


## The dead inside the compound ruin a share of every stock (see LOOT_RATE).
func _ruin(dt: float) -> void:
	var n: int = sim.dead_inside()
	if n == 0:
		return
	var keep := exp(-LOOT_RATE * float(n) * dt)
	for kind in sim.stock:
		sim.stock[kind] = maxf(0.0, float(sim.stock[kind]) * keep)
	sim.alert("ruin", "danger", "The dead are in the stores", "Stocks are being ruined", null, 6.0)


## How well a person shoots and works right now: less once they are hungry or
## thirsty (a fifth less, not more if it is both).
func perf(p) -> float:
	if p.hunger_h >= HUNGRY_H or p.thirst_h >= THIRSTY_H:
		return WEAK_PERF
	return 1.0


## The people working the vegetable beds grow food for the hours they work (`hours` game hours
## have passed): GARDEN_FOOD_PER_HOUR each, from the moment they are at the beds.
func _garden(hours: float) -> void:
	if not sources_on or hours <= 0.0:
		return
	var hands: int = sim.jobs.working("garden").size()
	if hands > 0:
		sim.stock.food += GARDEN_FOOD_PER_HOUR * float(hands) * hours * sim.seasons.mult("garden") * sim.policies.work_mult(null, "garden")


## The day begins: rolls the day's weather (from the run's one random source) and,
## if anyone is on the map to tend them, the vegetable beds' small unattended share (more with a
## greenhouse) and the rain barrels pay out. Called by update() once a day; public so tests can call it.
func roll_dawn() -> void:
	sources_day = sim.day
	var rain: bool = sim.rng.randf() < sim.seasons.rain_chance()
	# (One House: the town's sky has a schedule of its own, scripts/town/skies.gd; the die above is still thrown, so the run's other dice fall as they did. The school has no `skies`.)
	if sim.get("skies") != null:
		rain = sim.skies.rained_in_the_night()
	# a season with snow throws one more die, so that every other season's run is as it was
	sim.weather = sim.seasons.weather_for(rain, sim.rng.randf()) if sim.seasons.snow_share() > 0.0 else ("rain" if rain else "clear")
	if not sources_on or not _someone_home():
		return
	sim.stock.food += GARDEN_BASE * sim.seasons.mult("garden") + sim.build.bonus("garden_base")
	var water := BARREL_WATER_RAIN if rain else BARREL_WATER
	sim.stock.water += water
	sim.stock.scrap += sim.build.bonus("scrap_base")
	if rain:
		sim.alert("rain", "info", "It %s in the night" % ("snowed" if sim.weather == "snow" else "rained"), "Barrels gave %d water" % roundi(water), _spot("water"), 10.0)


## How much of `amount` (health points of repair wanted this step) the scrap pays
## for: one scrap per ten points. Takes the scrap it uses; at none it returns 0
## and tells the crew why the hammering has stopped.
func repair_budget(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var scrap: float = sim.stock.scrap
	var cost := amount / REPAIR_PER_SCRAP
	if scrap > cost:
		sim.stock.scrap = scrap - cost
		return amount
	sim.stock.scrap = 0.0
	sim.alert("no-scrap", "warn", "No scrap: repairs stopped", "Try the hardware store", null, 8.0)
	return maxf(0.0, scrap) * REPAIR_PER_SCRAP


## Days of "food" or "water" left for the living crew at the usual use, not
## counting income (the away are counted: they come back hungry). 99 if nobody
## is alive, for anything else, and at most 99.
func days_left(kind: String) -> float:
	var per_day := 0.0
	if kind == "food":
		per_day = FOOD_PER_DAY * sim.seasons.mult("food") * sim.policies.ration_mult("food")
	elif kind == "water":
		per_day = WATER_PER_DAY * sim.seasons.mult("water") * sim.policies.ration_mult("water")
	var crew := 0
	for p in sim.people:
		if not p.dead:
			crew += 1
	if per_day <= 0.0 or crew == 0:
		return 99.0
	var have: float = sim.stock[kind]
	return minf(99.0, maxf(0.0, have) / (crew * per_day))


## Marks for a person's card and panel: hungry, starving, thirsty (red when it
## has begun to cost health). None for the dead and the away.
func status_of(p) -> Array:
	var marks: Array = []
	if p.dead or p.away != null:
		return marks
	if p.hunger_h >= STARVING_H:
		marks.append({"icon": "starving", "color": DANGER, "tip": "Starving"})
	elif p.hunger_h >= HUNGRY_H:
		marks.append({"icon": "hungry", "color": WARN, "tip": "Hungry"})
	if p.thirst_h >= PARCHED_H:
		marks.append({"icon": "thirsty", "color": DANGER, "tip": "Parched"})
	elif p.thirst_h >= THIRSTY_H:
		marks.append({"icon": "thirsty", "color": WARN, "tip": "Thirsty"})
	return marks


func save() -> Dictionary:
	return {
		"meal_day": meal_day,
		"meals_done": meals_done,
		"sources_day": sources_day,
		"short_of": short_of.duplicate(),
		"low_alert_min": low_alert_min.duplicate(),
	}


func load_state(d: Dictionary) -> void:
	meal_day = int(_num(d, "meal_day", sim.day))
	meals_done = clampi(int(_num(d, "meals_done", _meals_passed(sim.hour))), 0, MEAL_HOURS.size())
	sources_day = int(_num(d, "sources_day", sim.day))
	var shorts = d.get("short_of", {})
	var times = d.get("low_alert_min", {})
	for kind in ["food", "water"]:
		short_of[kind] = shorts is Dictionary and shorts.get(kind, false) == true
	for kind in ["food", "water", "ammo"]:
		low_alert_min[kind] = _num(times, kind, NEVER) if times is Dictionary else NEVER


# ------------------------------------------------------------------ meals --

## Takes the clock as it is: today's meal times that have passed are not owed,
## and today's sources are not due.
func _sync_clock() -> void:
	meal_day = sim.day
	meals_done = _meals_passed(sim.hour)
	sources_day = sim.day


## How many of the rules' day's meal times the clock (the hour of day `h`) has
## reached. The day turns over at 06:30, so between midnight and then the day's
## three are all behind.
func _meals_passed(h: float) -> int:
	if h < DAWN_HOUR:
		return MEAL_HOURS.size()
	var n := 0
	for mh in MEAL_HOURS:
		if h >= mh:
			n += 1
	return n


## Serves each meal once, however the steps fall. A slot counter per day, not a
## test of the time, so a step that jumps over a meal time cannot miss it or
## serve it twice. A meal time the clock was set past by hand (a screenshot
## flag, a test) is not owed; one that came up within this step is.
func _serve_meals(dt: float) -> void:
	if sim.day != meal_day:
		meal_day = sim.day
		meals_done = 0
	var h: float = sim.hour
	var step_h: float = sim.game_hours(dt)
	var passed := _meals_passed(h)
	# if the clock was set back, the meals after the time it was set to are ahead
	# again (counted as of the start of this step, so one crossed in it is served)
	meals_done = mini(meals_done, _meals_passed(fposmod(h - step_h, 24.0)))
	while meals_done < passed:
		var at: float = MEAL_HOURS[meals_done]
		meals_done += 1
		if fposmod(h - at, 24.0) <= step_h + LATE_SLACK_H:
			_serve_meal()


## Every living person on the map takes their share, in crew order, until the
## stores run out; the rest go without. A person who is given a quarter of a
## share or more has eaten (or drunk) and starts counting again from zero.
func _serve_meal() -> void:
	var without := {"food": 0, "water": 0}
	for p in sim.people:
		if p.dead or p.away != null:
			continue
		if _out_of_the_base(p):
			sim.inv.on_meal_missed()    # (NEEDS: the table is at the base: out in the town she eats from her pack, and the base serves what she missed when she is home)
			continue
		_feed(p, without)
	var newly: Array = []
	for kind in ["food", "water"]:
		var now: bool = without[kind] > 0
		if now and not short_of[kind]:
			newly.append(kind)
		short_of[kind] = now
	if not newly.is_empty():
		sim.events.append({"type": "banner", "text": "Short rations", "sub": "Not enough %s for everyone" % " or ".join(newly)})


## One person's share of a meal: from the stores, and for the one who carries a pack, from the pack when the stores are short. `without` counts the shares that could not be given.
func _feed(p, without: Dictionary) -> void:
	var food_share: float = FOOD_PER_MEAL * sim.seasons.mult("food") * sim.policies.ration_mult("food")
	var water_share: float = WATER_PER_MEAL * sim.seasons.mult("water") * sim.policies.ration_mult("water")
	var food := _take("food", food_share)
	if food < food_share - EPS and _eats_from_pack(p):
		food += float(sim.inv.eat("food", food_share - food))    # (INV-CORE: the stores are short and she has food in her pack)
	if food >= food_share * FED_PART:
		p.hunger_h = 0.0
	if food < food_share - EPS:
		without.food += 1
	var water := _take("water", water_share)
	if water < water_share - EPS and _eats_from_pack(p):
		water += float(sim.inv.eat("water", water_share - water))
	if water >= water_share * FED_PART:
		p.thirst_h = 0.0
	if water < water_share - EPS:
		without.water += 1


## NEEDS (One House with a pack): the one who carries it is fed by the stores only at the base. True for her when she is anywhere else.
func _out_of_the_base(p) -> bool:
	var inv = sim.get("inv")
	return inv != null and inv.active() and bool(p.player) and not inv.at_home(p)


## NEEDS: the meal that came up while she was out is served the moment she is at the base again (once: the meals she missed before it are not owed on top).
func _serve_owed() -> void:
	var inv = sim.get("inv")
	if inv == null or not inv.owed_meal or not inv.active():
		return
	var p = inv.lead()
	if p == null or p.dead or p.away != null or not inv.at_home(p):
		return
	inv.owed_meal = false
	_feed(p, {"food": 0, "water": 0})


## INV-CORE: whether this person is the one who carries a pack (the town's player), who eats and drinks from it when the stores cannot give a share.
func _eats_from_pack(p) -> bool:
	var inv = sim.get("inv")
	return inv != null and inv.active() and bool(p.player)


## Takes up to `share` of `kind` from the stores; returns what it got.
func _take(kind: String, share: float) -> float:
	var have: float = sim.stock[kind]
	var got := minf(share, have)
	if got <= 0.0:
		return 0.0
	var left := have - got
	sim.stock[kind] = 0.0 if left < EPS else left
	return got


# ------------------------------------------------- hunger, thirst, alerts --

## Hunger and thirst count up for everyone on the map (the away are on trip
## rations: their counters hold still, and so does the health of the dead). A
## starving or parched person loses health, and at none is handed to the
## medical module as down, whichever need is further gone.
func _needs(gh: float) -> void:
	if gh <= 0.0:
		return
	for p in sim.people:
		if p.dead or p.away != null:
			continue
		p.hunger_h += gh
		p.thirst_h += gh
		if p.hunger_h >= STARVING_H or p.thirst_h >= PARCHED_H:
			p.hp = maxf(0.0, p.hp - STARVE_LOSS_PER_H * gh)
			if p.hp <= 0.0 and not p.downed:
				sim.medical.on_downed(p, "thirst" if p.thirst_h / PARCHED_H > p.hunger_h / STARVING_H else "hunger")


func _low_stock_alerts() -> void:
	var rounds := float(sim.ammo_total())    # (the town: the stores' rounds and the pack's)
	if rounds >= low_ammo:
		sim.alerts.erase("low-ammo")
	elif rounds > 0.0 and sim.clock_min - float(low_alert_min["ammo"]) >= LOW_REPEAT_MIN * 6.0:
		low_alert_min["ammo"] = sim.clock_min
		sim.alert("low-ammo", "danger" if rounds < 20.0 else "warn", "Ammo is running low", "%d left" % roundi(rounds), null, LOW_TTL)
		sim.barks.on_low_ammo()
	for kind in ["food", "water"]:
		var id := "low-%s" % kind
		var days := days_left(kind)
		if days >= LOW_DAYS:
			sim.alerts.erase(id)
		elif sim.clock_min - float(low_alert_min[kind]) >= LOW_REPEAT_MIN:
			low_alert_min[kind] = sim.clock_min
			sim.alert(id, "danger" if days < 1.0 else "warn", "%s is running out" % kind.capitalize(), _days_text(days), _spot(kind), LOW_TTL)


## The alert's second line: whole days, rounded down like the stores panel does,
## so the two never disagree.
func _days_text(days: float) -> String:
	if days <= 0.0:
		return "none left"
	if days < 1.0:
		return "less than a day left"
	var n := floori(days)
	return "about %d day%s left" % [n, "" if n == 1 else "s"]


## Where the alert sends the camera: the fridge for food, the rain barrels for water.
func _spot(kind: String):
	var what := "fridge" if kind == "food" else "rainbarrel"
	if not _spots.has(what):
		_spots[what] = null
		for o in sim.d.objects:
			if o.kind == what:
				_spots[what] = Vector2(o.cx, o.cy)
				break
	return _spots[what]


func _someone_home() -> bool:
	for p in sim.people:
		if not p.dead and p.away == null:
			return true
	return false


static func _num(d: Dictionary, key: String, default: float) -> float:
	var v = d.get(key, default)
	return float(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else default
