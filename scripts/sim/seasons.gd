## The seasons (round 10). Autumn is the 30-night game as it has always been; the **campaign** goes on
## from it through Winter, Spring and Summer (assets/data/seasons.json), each with its own length, its
## own hours of day and night, weather, garden, appetite, roads and nights, and each ending with its
## own Big Night. The season turns at the dawn after its last night.
##
## A run that is not a campaign is Autumn for ever, and every answer is what it was before this module
## existed (`campaign` is set before `start_run`; the data's Autumn repeats the old constants).
##
## THE SCHEDULE. `dusk_hour()` and `dawn_hour()` are the season's; the phases follow them (`phase_at`:
## dusk is an hour and a half from the dusk hour, night from there until an hour before the dawn
## hour, then dawn). The season's dusk takes effect the day it begins, its dawn at the first dusk after
## (the morning a season begins is the old season's), so that a change of season never runs a day
## twice or skips a night. `light_hour(h)` maps a real hour to the hour of the standard day, so that the
## lighting's keyframes (made for dusk at 19) follow any schedule.
##
## THE NIGHTS. `effective_day(day)` is the day the nights are sized by: the day in the season plus SEASON_STEP
## for each season gone, so Winter begins as Autumn's seventh day does and Spring as its thirteenth.
## `big_factor()` is the Big Night's factor, `mult("waves")` the season's share on top.
##
## Events: {"type": "season", "season": id, "index": n} when a season begins.
extends RefCounted

const DATA_PATH := "res://assets/data/seasons.json"
## Where the data is read from (tests may point it at another file).
static var data_path := DATA_PATH
static var _cache := {}

## Each season gone makes the nights this many days older.
const SEASON_STEP := 6
## The dusk lasts this long, and the dawn this long.
const DUSK_H := 1.5
const DAWN_H := 1.0
## The standard day's own hours, to which `light_hour` maps.
const STD_DUSK := 19.0
const STD_DAWN := 6.5

var sim
## Whether this run is the long game (set before `start_run`).
var campaign := false
var index := 0
var _seasons: Array = []
var _start_day := 1
var _dusk := STD_DUSK
var _dawn := STD_DAWN


func setup(s) -> void:
	sim = s
	_load()


func _load() -> void:
	if not _cache.has(data_path):
		var out: Array = []
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		if raw is Dictionary:
			for r in raw.get("seasons", []):
				if r is Dictionary and String(r.get("id", "")) != "":
					out.append(r.duplicate(true))
		if out.is_empty():
			out.append({"id": "autumn", "name": "Autumn", "days": 30, "dusk": STD_DUSK, "dawn": STD_DAWN, "rain": 1.0 / 3.0, "big": 2.4})
		_cache[data_path] = out
	_seasons = _cache[data_path]


## A new run: Autumn, day 1. `campaign` is kept (the caller sets it before `start_run`).
func start() -> void:
	index = 0
	_start_day = 1
	_dusk = float(_seasons[0].get("dusk", STD_DUSK))
	_dawn = float(_seasons[0].get("dawn", STD_DAWN))


# ---------------------------------------------------------------------- seasons --

func count() -> int:
	return _seasons.size() if campaign else 1


func current() -> Dictionary:
	return _seasons[mini(index, _seasons.size() - 1)]


func season(i: int) -> Dictionary:
	return _seasons[clampi(i, 0, _seasons.size() - 1)]


## The day within the season (1 to its length).
func season_day(day: int = -1) -> int:
	return (sim.day if day < 0 else day) - _start_day + 1


func season_length() -> int:
	return int(current().get("days", 30))


## The last day of this season (cumulative): its night is the Big Night.
func end_day() -> int:
	return _start_day + season_length() - 1


func is_last() -> bool:
	return index + 1 >= count()


## The day the nights are sized by.
func effective_day(day: int) -> int:
	return (day - _start_day + 1) + SEASON_STEP * index


## A multiplier of the season (1 when it has none).
func mult(key: String) -> float:
	return float(current().get(key, 1.0)) if campaign else 1.0


func big_factor() -> float:
	return float(current().get("big", 2.4))


func rain_chance() -> float:
	return float(current().get("rain", 1.0 / 3.0))


## The share of wet days that are snow.
func snow_share() -> float:
	return float(current().get("snow", 0.0))


func tint() -> Color:
	var t = current().get("tint", [1.0, 1.0, 1.0])
	return Color(float(t[0]), float(t[1]), float(t[2]))


## What the day's weather is, from two dice the supplies module rolled (the first decides rain, the second,
## only drawn for a season with snow, whether it is snow).
func weather_for(wet: bool, snow_roll: float) -> String:
	if not wet:
		return "clear"
	return "snow" if snow_roll < snow_share() else "rain"


## The temperature at an hour of the day (degrees): the season's mean, a swing that is warmest at 15:00.
func temperature(hour: float) -> float:
	var t: Dictionary = current().get("temperature", {"mean": 12.0, "swing": 5.0})
	return float(t.mean) + float(t.swing) * cos((hour - 15.0) / 24.0 * TAU)


# --------------------------------------------------------------------- schedule --

func dusk_hour() -> float:
	return _dusk


func dawn_hour() -> float:
	return _dawn


## The hours of the dark, from the end of the dusk to the start of the dawn.
func night_hours() -> float:
	return (24.0 - (_dusk + DUSK_H)) + (_dawn - DAWN_H)


## How long this season's night is against the standard one (the dead are spread over it).
func night_scale() -> float:
	if not campaign:
		return 1.0
	return night_hours() / ((24.0 - (STD_DUSK + DUSK_H)) + (STD_DAWN - DAWN_H))


## The phase of the day at a time of day in minutes.
func phase_at(mins: float) -> String:
	var h := fmod(mins / 60.0, 24.0)
	if h >= _dusk and h < _dusk + DUSK_H:
		return "dusk"
	if h >= _dusk + DUSK_H or h < _dawn - DAWN_H:
		return "night"
	if h < _dawn:
		return "dawn"
	return "day"


## The hour of the standard day that this real hour looks like: dusk at 19, the night 20:30 to 05:30, dawn to
## 06:30, however long the season's day is.
func light_hour(h: float) -> float:
	if is_equal_approx(_dusk, STD_DUSK) and is_equal_approx(_dawn, STD_DAWN):
		return h
	var x := h if h >= _dawn else h + 24.0
	var s: float
	var d_end := _dusk + DUSK_H
	var n_end := _dawn + 24.0 - DAWN_H
	if x < _dusk:
		s = STD_DAWN + (x - _dawn) / (_dusk - _dawn) * (STD_DUSK - STD_DAWN)
	elif x < d_end:
		s = STD_DUSK + (x - _dusk) / DUSK_H * (20.5 - STD_DUSK)
	elif x < n_end:
		s = 20.5 + (x - d_end) / (n_end - d_end) * (29.5 - 20.5)
	else:
		s = 29.5 + (x - n_end) / DAWN_H * (30.5 - 29.5)
	return fposmod(s, 24.0)


## Puts a campaign at the first day of season `i` (for screenshots and tests): the day, the schedule and the season.
func jump_to(i: int) -> void:
	campaign = true
	index = clampi(i, 0, _seasons.size() - 1)
	var day := 1
	for k in index:
		day += int(_seasons[k].get("days", 30))
	_start_day = day
	sim.day = day
	_dusk = float(current().get("dusk", STD_DUSK))
	_dawn = float(current().get("dawn", STD_DAWN))


## The morning of a new day: a season that has run its course gives way to the next (after its Big Night).
func on_new_day() -> void:
	if not campaign:
		return
	if sim.day > end_day() and index + 1 < _seasons.size():
		index += 1
		_start_day = sim.day
		_dusk = float(current().get("dusk", STD_DUSK))
		var s := current()
		sim.events.append({"type": "season", "season": String(s.id), "index": index})
		sim.events.append({"type": "banner", "text": "%s begins" % String(s.name), "sub": String(s.get("blurb", ""))})
		sim.alert("season", "info", "%s has come" % String(s.name), String(s.get("blurb", "")), null, 30.0)


## The dusk begins: tomorrow's dawn is the season's.
func on_dusk() -> void:
	_dawn = float(current().get("dawn", STD_DAWN))


# --------------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {"campaign": campaign, "index": index, "start_day": _start_day, "dusk": _dusk, "dawn": _dawn}


func load_state(d: Dictionary) -> void:
	campaign = bool(d.get("campaign", false))
	index = clampi(int(d.get("index", 0)), 0, maxi(0, _seasons.size() - 1)) if campaign else 0
	_start_day = maxi(1, int(d.get("start_day", 1)))
	var dusk := float(d.get("dusk", float(current().get("dusk", STD_DUSK))))
	var dawn := float(d.get("dawn", float(current().get("dawn", STD_DAWN))))
	# a save with a schedule no season has (a broken file) gets the season's own, or the day would never turn
	if dusk < 15.0 or dusk > 22.0 or dawn < 4.5 or dawn > 8.5:
		dusk = float(current().get("dusk", STD_DUSK))
		dawn = float(current().get("dawn", STD_DAWN))
	_dusk = dusk
	_dawn = dawn
