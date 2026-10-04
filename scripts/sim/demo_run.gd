## The demo's run (round 26, "Three Bells"): the scenario that makes a run the first three nights of the game, the same every time, with a clear end.
## What the demo is made of is `assets/data/demo.json` (read through scripts/demo.gd); this module is the rules' side and works on its own, with no
## screen: `DemoRun.begin(sim)` on a freshly built Sim installs it and starts the run, as `Orientation.begin` does the tutorial's.
##
## WHAT IT KEEPS. The avatar (the survivor you play), the radio and the community (the verbs, trust, refusals, the ideas, which begin on day 2), the nights at
## the wall (the lookout's forecast, the calls, the real gate with its lever), the base and its look, the one trip (the starting pickup, driven to the pharmacy),
## the morning briefing with its priorities (from day 2).
##
## WHAT IT SWITCHES OFF (kept in the code; `enabled = false` as Orientation Day does, and the views of each guard on `active()`): the four dials
## (`policies`), the trouble in the yard (`problems`), the fever dilemma (`dilemmas`), who is close to whom (`relations`) and the specialists
## (`specialists`); the lots, the streets of the dead and the seasons (`lots.on`, `streets.enabled`: the Autumn of the run is three days long); the long-term
## building (the Build page offers the demo's six buildings: `build.restrict`); the places (the Map has only the demo's two: `town.restrict`); the road's
## events (five kinds: `ctx.only` of scripts/drive/road_events.gd); the errand options, the Jobs tab and the Policies and Trouble sections of the Base page
## (views: they ask `sim.is_demo()`).
##
## THE RUN. A fixed seed, a crew of five, Standard. It is over at the dawn after the last night (`total_days()` is the demo's three): the run's result is
## "victory" and the HUD puts up the END CARD (scripts/ui/demo_end_card.gd) instead of the report card; a defeat is the ordinary game over. Night 3 is a
## Siege, a Big Night (`big_night_for`, read by waves.gd) with plated brutes; nights 1 and 2 are ordinary and gentle (`night_mult`). The first morning has the
## pharmacy's trip put to the player (`stage`).
##
## Saved with the run like every module (`save` says `kind: demo`, which `is_save` reads, so a load installs the demo again before the save is read).
extends "res://scripts/sim/scenario.gd"

const Demo := preload("res://scripts/demo.gd")
const NightData := preload("res://scripts/sim/night_data.gd")

const KIND := "demo"
## The modules the demo switches off: their `enabled`.
const OFF := ["policies", "problems", "dilemmas", "relations", "specialists"]
## Difficulty of the demo: Standard.
const DIFFICULTY := 1

var _theme := {}
var _mults := {}
var _idea_day := -1


## Swaps this scenario into a freshly built `game` (before the run starts, or before a save is read) and puts the demo's switches on it. Returns it.
static func install(game):
	var script: GDScript = load("res://scripts/sim/demo_run.gd")
	var module = script.new()
	game.scenario = module
	module.setup(game)
	for module_name in OFF:
		var m = game.get(module_name)
		if m != null:
			m.enabled = false
	game.streets.enabled = false
	game.crew_start = Demo.crew()
	game.seasons.campaign = false
	game.town.restrict(Demo.places())
	game.build.restrict(Demo.buildings())
	return module


## Installs it and starts the run on the demo's seed: Ruth is the player, the board is on (the two places), and the pickup is in the motor pool with fuel.
static func begin(game):
	var module = install(game)
	game.start_run(DIFFICULTY, Demo.run_seed())
	module.stage()
	return module


## Whether `data` (a save as SaveGame.read gives it) is a demo save.
static func is_save(data: Dictionary) -> bool:
	var modules = data.get("modules")
	if typeof(modules) != TYPE_DICTIONARY:
		return false
	var mine = modules.get("scenario")
	return typeof(mine) == TYPE_DICTIONARY and String(mine.get("kind", "")) == KIND


## What a new run is, once `start_run` has set it up: the player, the board and the pickup, the demo's stock, the lots and the streets off, and the
## first morning's word about the pharmacy.
func stage() -> void:
	sim.avatar.set_player("ruth")
	sim.lots.on = false    # (the lots' own `begin` says the same: a demo has none)
	var stock: Dictionary = Demo.data().start_stock
	for k in stock:
		sim.stock[String(k)] = float(stock[k])
	sim.vehicles.give_starting_car()
	_first_morning()


## The first morning's trip: the pharmacy has medicine, which is what the stores lack, and the pickup is fuelled. A News line and an alert say so.
func _first_morning() -> void:
	var place: String = String(Demo.data().trip_place)
	var site: Dictionary = sim.town.place(place)
	if site.is_empty() or not sim.town.on:
		return
	var name_of := String(site.get("name", place))
	sim.radio.log_news("road", "%s: medicine" % name_of, "The stores are short of it. Open the Map (G), pick the place and Take control: the pickup is fuelled")
	sim.alert("demo_trip", "info", "Medicine is short", "%s has some: open the Map (G) and drive the pickup there" % name_of, null, 90.0)


# ----------------------------------------------------------------- the rules --

func is_demo() -> bool:
	return true


## The run lasts the demo's nights.
func total_days() -> int:
	return Demo.nights()


## The size of the night after `day` over what an ordinary night of the avatar game is (waves.gd): the data's, 1 when it names none.
func night_mult(day: int) -> float:
	if _mults.is_empty():
		var table = Demo.data().night_mult
		_mults = table if table is Dictionary and not (table as Dictionary).is_empty() else {"_": 1.0}
	if _mults.has(str(day)):
		return maxf(float(_mults[str(day)]), 0.05)
	return 1.0


## The first day of the community's ideas (initiative.gd).
func idea_day() -> int:
	if _idea_day < 0:
		_idea_day = int(Demo.data().ideas_from_day)
	return _idea_day


## The Big Night after `day` as waves.gd's `big_night` answers it ({} for an ordinary night): the demo's night is a Siege: plated brutes at one wall,
## the numbers of nights.json's `themes.siege` with the demo's own over them.
func big_night_for(day: int) -> Dictionary:
	if day != Demo.big_night_day():
		return {}
	if _theme.is_empty():
		var t := NightData.theme("siege")
		var mine = Demo.data().big_night
		if mine is Dictionary:
			for k in mine:
				t[k] = mine[k]
		var span := _range(t.get("brute_at", []))
		_theme = {
			"kind": "milestone", "id": "siege", "index": 0, "name": String(t.get("name", "The Siege")), "factor": maxf(float(t.get("factor", 2.0)), 1.0),
			"runners": clampf(float(t.get("runners", 0.0)), 0.0, 0.8), "brutes": clampf(float(t.get("brutes", 0.2)), 0.0, 0.8),
			"min_brutes": maxi(0, int(t.get("min_brutes", 1))), "headings": 1, "main_share": clampf(float(t.get("main_share", 0.95)), 0.0, 1.0),
			"brute_at": span, "cap": maxi(10, int(t.get("cap", 60))), "blurb": String(t.get("blurb", "Plated brutes at one wall. Be there.")), "plated": true,
		}
	return _theme.duplicate(true)


func _range(v) -> Array:
	var lo := 0.3
	var hi := 0.65
	if typeof(v) == TYPE_ARRAY and v.size() == 2:
		lo = float(v[0])
		hi = float(v[1])
	lo = clampf(lo, 0.0, 0.99)
	return [lo, clampf(hi, lo + 0.01, 1.0)]


func victory_banner() -> Array:
	return ["Three nights held", "The demo ends here"]


## What the end card tells of the run so far: {"nights" (held), "of", "alive", "lost" (dead or turned), "kills" (the dead put down), "trips", "built" (buildings
## that stand)}.
func report() -> Dictionary:
	var alive := 0
	var lost := 0
	for p in sim.people:
		if p.dead or p.turned:
			lost += 1
		else:
			alive += 1
	var built := 0
	for pl in sim.build.plots():
		if String(pl.building) != "":
			built += 1
	var held := total_days() if sim.over == "victory" else clampi(int(sim.day) - 1, 0, total_days())
	return {"nights": held, "of": total_days(), "alive": alive, "lost": lost, "kills": int(sim.kills), "trips": int(sim.scavenge.trips), "built": built}


## A screenshot's staging (`--demo --endcard`): the colony plays its three days alone, quickly (no drawing), until the run is over, so that the end card has
## numbers of a real run behind it. At most a few game days' worth of steps.
func stage_end() -> void:
	var guard := 0
	while sim.over == "" and guard < 40:
		sim.fast_forward(720.0)
		guard += 1


func save() -> Dictionary:
	return {"kind": KIND}
