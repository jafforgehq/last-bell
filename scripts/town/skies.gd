## The town's weather (RAIN): one house in a big town, and about one day in two it rains for a while. A TownSim part (`sim.skies`: scripts/town/town_sim.gd PARTS), the rules' side of the
## weather; what you see and hear of it is scripts/render/rain_view.gd (a view part of the town's facade) and the rain bed of scripts/audio/soundscape.gd. The school's own weather
## (supplies.gd `roll_dawn`, seasons.gd) is not touched: this part exists in the town only.
##
## THE SCHEDULE is a pure function of the run's seed and the game clock (`sim.run_seed`, `sim.clock_min`): nothing is rolled as the run goes, no die of the rules' is thrown for it (a
## RandomNumberGenerator of its own is seeded from the run seed and the day), so a run plays the same weather every time, a save needs no more than the clock and the seed it already has,
## and the school's streams (and so the golden files) are as they were. For each DAY of the schedule (the day begins at 07:00 of the day, not at midnight: day 0 is the first morning):
##   - the day is wet with a chance of WET_DAY (a half);
##   - a wet day has ONE rain period: it begins at a seeded hour between 07:00 and 23:00 (not before 09:00 on the first day: the first two game hours of a run are dry, so nothing falls
##     in its first ten minutes), lasts DUR_MIN to DUR_MAX game hours (so it may run on past midnight into the night), and is a DRIZZLE (40 percent), STEADY rain (35) or a STORM (25);
##   - the rain eases in over RAMP_IN game hours and out over RAMP_OUT, and the sky is OVERCAST for CLOUD hours before and after it.
## Nothing keeps the first attack night dry: the rain may fall on it, a storm included. The rain's effects on the rules are small and the lab (`tools/house_lab.gd --weather-first-night=`)
## puts a drizzle, a steady rain, a storm or none on that night on purpose to show the balance holds.
##
## WHAT THE RULES SEE. `sim.weather` is "clear", "rain" (a drizzle or a steady rain) or "storm" (the words the school's systems already read: base_life, the soundscape, the storyteller's
## look); the dead's noise is multiplied by NOISE_RAIN while it rains (`field.noise_mult`: a shot carries a fifth less far); the crew's scavengers stay in during a storm (crew_search.gd). The
## clock's word (`word()`: clear, overcast, drizzle, rain, storm), the intensity (`level()`, 0 to 1: 0.30 a drizzle, 0.62 a steady rain, 1 a storm, each eased in and out) and the clouds
## (`cloud`) are what the view reads.
##
## LIGHTNING (LOOK2) is part of the schedule too (`strikes_between`: the bolts of a storm and of a steady rain, and the dim sheet flashes, each a pure function of the seed and the clock); what is seen
## and heard of it is rain_view.gd's, and nothing of it touches the rules.
##
## STAGING (a screenshot, the lab): `force(word)` holds the weather for the run ("clear", "drizzle", "rain" or "steady", "storm"; "" lets the schedule go on), `force_first_night(word)` holds it
## only through the first attack night (dusk to dawn of the day the attacks begin, scripts/town/one_house.gd). Neither is saved.
extends RefCounted

const KINDS := ["drizzle", "steady", "storm"]
## How hard each kind rains, 0 to 1 (the view's density, the extra dark, the sound of the bed all follow it).
const KIND_LEVEL := {"drizzle": 0.30, "steady": 0.62, "storm": 1.0}
## The word on the clock for a kind, and the rules' own word for it (`sim.weather`).
const KIND_WORD := {"drizzle": "drizzle", "steady": "rain", "storm": "storm"}
const SIM_WORD := {"drizzle": "rain", "steady": "rain", "storm": "storm"}
## The share of the wet days that are each kind (LOOK2: it was 50, 35, 15; the owner never saw a lightning, storms were one wet day in seven).
const KIND_SHARE := [0.40, 0.35, 0.25]
## LIGHTNING (the strike schedule, `strikes_between`): the clock's hours are cut into CELLS, a storm's 0.7167 game hours long (21.5 s at x1) and a steady rain's 1.75 (52.5 s), and each cell has ONE
## bolt, at a seeded point of its middle (`BOLT_AT`, hours into the cell): the gaps between bolts are 11 to 32 s in a storm and 30 to 75 s in a steady rain, none in a drizzle. About one storm
## bolt in eight is NEAR (`NEAR_SHARE`: the crack comes within 0.3 s). A cell may also have a dim DISTANT SHEET flash on its edge (`SHEET_SHARE`), clear of the bolts.
const BOLT_CELL := {"storm": 0.7167, "steady": 1.75}
const BOLT_AT := {"storm": [0.1833, 0.5333], "steady": [0.5, 1.25]}
const SHEET_SHARE := {"storm": 0.55, "steady": 0.30}
const NEAR_SHARE := 0.125
## Storm bolts happen from this level up (the rain's ease-in is not lightning weather), steady rain's from its.
const BOLT_LEVEL := {"storm": 0.6, "steady": 0.5}
## The chance that a day has a rain period, and its length (game hours).
const WET_DAY := 0.5
const DUR_MIN := 2.0
const DUR_MAX := 5.0
## A period begins this many game hours after 07:00 (so at 07:00 to 23:00); on the first day not before FIRST_DRY_H (09:00).
const START_TO := 16.0
const FIRST_DRY_H := 2.0
## The rain eases in and out over this many game hours, and the clouds gather and clear over CLOUD.
const RAMP_IN := 0.30
const RAMP_OUT := 0.40
const CLOUD := 0.80
## The level from which the rules say it rains (`sim.weather`).
const WET_AT := 0.04
## What the rain does to the noise of a shot.
const NOISE_RAIN := 0.8
const TIPS := {
	"clear": "Clear skies.",
	"overcast": "Clouds are gathering: rain is coming.",
	"drizzle": "Drizzle. The rain is light: a shot carries a fifth less far, and the light is a little poorer.",
	"rain": "Rain. A shot carries a fifth less far, the light is poor, and the ground is wet.",
	"storm": "Storm. A shot carries a fifth less far, it is dark, and nobody goes out scavenging until it passes.",
}

var sim
## What the sky is doing now (read by the view and the rules): the level (0 dry to 1 a storm, a kind's level while it is at its height), the kind ("" dry), the cloud (0 to 1).
var level := 0.0
var kind := ""
var cloud := 0.0
## A staging asked for the picture at once (the view takes it and clears it): no easing of the wet ground or the dark.
var snap := false
var _force := ""
var _first_night := ""
var _cache := {}
var _seed := -1
var _n_level := 0.0
var _n_kind := ""
var _n_cloud := 0.0


func setup(s) -> void:
	sim = s


## A new run: the schedule is read again from the new seed, nothing is held.
func start() -> void:
	_cache.clear()
	_seed = -1
	_force = ""
	_first_night = ""
	snap = true
	_refresh()


func update(_dt: float) -> void:
	_refresh()


# --------------------------------------------------------------------- the schedule --

## A hash of the run's seed and the day, for the day's own random generator (not the rules').
static func _mix(seed_value: int, k: int) -> int:
	var h: int = ((seed_value & 0xFFFFFFFF) * 0x9E3779B1 + (k + 7) * 0x85EBCA6B + 0x27D4EB2F) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	h = ((h ^ (h >> 12)) * 0x297A2D39) & 0xFFFFFFFF
	return h ^ (h >> 15)


## The rain of day `k` of the schedule (day 0 is the first morning, from 07:00): {"wet": bool, "s", "e": the hours since the first 07:00 at which it begins and ends, "kind"}.
func period(k: int) -> Dictionary:
	if int(sim.run_seed) != _seed:
		_cache.clear()
		_seed = int(sim.run_seed)
	if _cache.has(k):
		return _cache[k]
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix(_seed, k)
	var wet := rng.randf() < WET_DAY
	var start := rng.randf_range(FIRST_DRY_H if k == 0 else 0.0, START_TO)
	var dur := rng.randf_range(DUR_MIN, DUR_MAX)
	var roll := rng.randf()
	var which: String = KINDS[0] if roll < float(KIND_SHARE[0]) else (KINDS[1] if roll < float(KIND_SHARE[0]) + float(KIND_SHARE[1]) else KINDS[2])
	var out := {"wet": wet, "s": 24.0 * float(k) + start, "e": 24.0 * float(k) + start + dur, "kind": which}
	_cache[k] = out
	return out


static func _ramp(x: float) -> float:
	var v := clampf(x, 0.0, 1.0)
	return v * v * (3.0 - 2.0 * v)


## The schedule's own sky at `t` game hours since the first 07:00: _n_level, _n_kind, _n_cloud.
func _natural(t: float) -> void:
	_n_level = 0.0
	_n_kind = ""
	_n_cloud = 0.0
	var k0 := floori(t / 24.0)
	for k in range(k0 - 1, k0 + 2):
		if k < 0:
			continue
		var p := period(k)
		if not bool(p.wet):
			continue
		var s: float = p.s
		var e: float = p.e
		var lv := float(KIND_LEVEL[p.kind]) * minf(_ramp((t - s) / RAMP_IN), _ramp((e - t) / RAMP_OUT))
		if lv > _n_level:
			_n_level = lv
			_n_kind = String(p.kind)
		_n_cloud = maxf(_n_cloud, minf(_ramp((t - s) / CLOUD + 1.0), _ramp((e + CLOUD - t) / CLOUD)))


## Whether it is the first attack night (dusk to dawn of the day the attacks begin).
func _in_first_night() -> bool:
	var sc = sim.scenario
	if sc == null or not sc.has_method("attacks_on") or not bool(sc.attacks_on()):
		return false
	return int(sim.day) == int(sc.get("_first_day")) and String(sim.phase) != "day"


func _refresh() -> void:
	_natural(float(sim.clock_min) / 60.0)
	var lv := _n_level
	var kd := _n_kind
	var cl := _n_cloud
	var held := _force
	if held == "" and _first_night != "" and _in_first_night():
		held = _first_night
	if held != "":
		if held == "clear":
			lv = 0.0
			kd = ""
			cl = 0.0
		else:
			kd = held
			lv = float(KIND_LEVEL[held])
			cl = 1.0
	level = lv
	kind = kd
	cloud = cl
	var w := String(SIM_WORD[kd]) if lv >= WET_AT else "clear"
	if String(sim.weather) != w:
		sim.weather = w
	var field = sim.get("field")
	if field != null and "noise_mult" in field:
		var m := NOISE_RAIN if w != "clear" else 1.0
		if float(field.noise_mult) != m:
			field.noise_mult = m


# ---------------------------------------------------------------------------- lightning --

## A number from 0 to 1 for the cell `c` of the schedule `s`, the `j`-th of that cell (its own hash: no die of the rules' is thrown, the seed and the clock say it all).
static func _u(s: int, c: int, j: int) -> float:
	return float(_mix(s, c * 8 + j) & 0xFFFFFF) / 16777215.0


## The lightning the clock passed over between `h0` (not counted) and `h1` (counted), in game hours since the first 07:00 (`sim.clock_min / 60`): an Array of strikes, in time order, each
## {"h": when, "sheet": a dim flash with no bolt, "near": the crack comes at once, "kind": "storm" or "steady", "power": how bright the flash (0 to 1), "u", "v": 0 to 1 where in the view the
## bolt lands, "seed": for its shape, "delay": seconds from flash to thunder, "far": 0 near to 1 far (the thunder's file and level), "calm": a strike that Reduce motion leaves out}. Empty
## unless it is a storm (level over 0.6) or a steady rain (over 0.5) NOW. A PURE function of the run's seed and the clock: a reloaded save has the same sky.
func strikes_between(h0: float, h1: float) -> Array:
	var out := []
	if h1 <= h0 or h1 - h0 > 2.0:
		return out
	var kd := ""
	if kind == "storm" and level > float(BOLT_LEVEL.storm):
		kd = "storm"
	elif kind == "steady" and level > float(BOLT_LEVEL.steady):
		kd = "steady"
	if kd == "":
		return out
	var w: float = BOLT_CELL[kd]
	var at: Array = BOLT_AT[kd]
	var s := (int(sim.run_seed) ^ (0x51ED7 if kd == "storm" else 0x2C3B9)) & 0xFFFFFFFF
	for c in range(floori(h0 / w) - 1, floori(h1 / w) + 2):
		if c < 0:
			continue
		var hb := float(c) * w + lerpf(float(at[0]), float(at[1]), _u(s, c, 0))
		if hb > h0 and hb <= h1:
			var near := kd == "storm" and _u(s, c, 1) < NEAR_SHARE
			var delay := 0.05 + 0.25 * _u(s, c, 7) if near else (1.0 + 2.0 * _u(s, c, 7) if kd == "storm" else 2.5 + 2.0 * _u(s, c, 7))
			var power := 1.0 if near else (0.55 + 0.20 * _u(s, c, 6) if kd == "storm" else 0.30 + 0.10 * _u(s, c, 6))
			out.append({"h": hb, "sheet": false, "near": near, "kind": kd, "power": power, "u": _u(s, c, 2), "v": _u(s, c, 3), "seed": _mix(s, c * 8 + 4) & 0xFFFF,
				"delay": delay, "far": clampf((delay - 1.0) / 2.0, 0.0, 1.0), "calm": (_mix(s, c * 8 + 4) >> 20) & 1 == 1})
		if _u(s, c, 5) < float(SHEET_SHARE[kd]):
			var hs := float(c) * w + (_u(s, c, 6) - 0.5) * 0.3 * w
			if hs > h0 and hs <= h1:
				out.append({"h": hs, "sheet": true, "near": false, "kind": kd, "power": (0.16 + 0.10 * _u(s, c, 3)) if kd == "storm" else 0.12, "u": _u(s, c, 2), "v": _u(s, c, 3), "seed": _mix(s, c * 8 + 4) & 0xFFFF,
					"delay": 0.0, "far": 1.0, "calm": true})
	if out.size() > 1:
		out.sort_custom(func(a, b): return float(a.h) < float(b.h))
	return out


# ---------------------------------------------------------------------------- staging --

static func _kind_of(word: String) -> String:
	match word.to_lower():
		"drizzle", "light":
			return "drizzle"
		"rain", "steady", "heavy":
			return "steady"
		"storm":
			return "storm"
		"clear":
			return "clear"
	return ""


## Holds the weather ("clear", "drizzle", "rain" or "steady", "storm") for the rest of the run; "" lets the schedule go on. False for a word it does not know.
func force(word: String) -> bool:
	var k := _kind_of(word)
	if word != "" and k == "":
		return false
	_force = k
	snap = true
	_refresh()
	return true


## Holds the weather through the first attack night only (the lab's `--weather-first-night`); "" clears it. False for a word it does not know.
func force_first_night(word: String) -> bool:
	var k := _kind_of(word)
	if word != "" and k == "":
		return false
	_first_night = k
	_refresh()
	return true


# ------------------------------------------------------------------- what is asked of it --

func raining() -> bool:
	return level >= WET_AT


func stormy() -> bool:
	return level >= WET_AT and kind == "storm"


## The word on the clock: "clear", "overcast", "drizzle", "rain" or "storm".
func word() -> String:
	if level >= WET_AT:
		return String(KIND_WORD[kind])
	return "overcast" if cloud > 0.3 else "clear"


func tip() -> String:
	return String(TIPS.get(word(), ""))


## How loud the rain bed is (soundscape.gd: 1 is the bed at its ordinary level): a drizzle a murmur, a steady rain full, a storm a roar.
func sound_level() -> float:
	if level < 0.01:
		return 0.0
	return clampf(level * 1.9, 0.0, 1.9) if level <= 0.62 else lerpf(1.18, 1.9, (level - 0.62) / 0.38)


## How much darker than the sky the rain makes the light (lighting.gd `set_extra_dim`, 0 to 1): 0.15 a drizzle, 0.3 a steady rain, 0.45 a storm, and a little under cloud.
func dim() -> float:
	var d := 0.0
	if level <= 0.30:
		d = level / 0.30 * 0.15
	elif level <= 0.62:
		d = lerpf(0.15, 0.30, (level - 0.30) / 0.32)
	else:
		d = lerpf(0.30, 0.45, (level - 0.62) / 0.38)
	return maxf(d, 0.06 * cloud)


## Whether it rained during the night that has just ended (the barrels of the dawn: supplies.gd `roll_dawn`): any rain between ten game hours ago and now.
func rained_in_the_night() -> bool:
	var sc = sim.scenario
	if _first_night != "" and sc != null and int(sim.day) - 1 == int(sc.get("_first_day")) and bool(sc.get("_attacks")):
		return _first_night != "clear"
	var t := float(sim.clock_min) / 60.0
	var k0 := floori(t / 24.0)
	for k in range(k0 - 1, k0 + 1):
		if k < 0:
			continue
		var p := period(k)
		if bool(p.wet) and float(p.s) < t and float(p.e) > t - 10.0:
			return true
	return false


# ------------------------------------------------------------------------------ saves --

## Nothing of the weather is kept: the schedule is the seed's and the clock's, both saved with the run.
func save() -> Dictionary:
	return {"v": 1}


func load_state(_d: Dictionary) -> void:
	_cache.clear()
	_seed = -1
	snap = true
	_refresh()
