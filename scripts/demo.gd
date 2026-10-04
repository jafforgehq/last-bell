## The demo ("Three Bells", round 26): the first three nights of one run, the same every time (a fixed seed), with a clear end. This file is
## where the game asks whether it IS the demo and what the demo is made of; the rules' side is `scripts/sim/demo_run.gd` (the scenario that
## installs it in a run), the end of the run is `scripts/ui/demo_end_card.gd`, and what the demo keeps, hides and says is the data,
## `assets/data/demo.json`.
##
## IS IT THE DEMO? `Demo.on()`: the user argument `--demo` (`Godot --path . -- --demo`, the way to try it from the editor's checkout), or the
## custom feature tag `demo` of an export (`OS.has_feature("demo")`: the export preset "Web (demo)" in export_presets.cfg carries it). A game
## that is not the demo is exactly the full game: nothing here is read, and every hook of it that stands in the rules asks `sim.is_demo()`,
## which is true only for a run whose scenario is the demo's (a demo save keeps it, like Orientation Day's).
##
##   Demo.on() -> bool
##   Demo.data() -> Dictionary        # the data file over the fallbacks below (a missing or damaged file is the fallbacks); a copy
##   Demo.run_seed() / .crew() / .nights() / .big_night_day()
##   Demo.buildings() / .places() / .road_events() -> Array of ids
##   Demo.wishlist_url() -> String    # "" (the default) hides the end card's Wishlist button
##   Demo.copy(key) -> String         # a line of the end card's words
##   Demo.force(true|false|null)      # a test's way to turn it on or off, whatever the arguments are (null: the arguments decide again)
extends RefCounted

const DATA_PATH := "res://assets/data/demo.json"
## The user argument and the feature tag of an export.
const FLAG := "--demo"
const FEATURE := "demo"
## Where the data is read from (tests may point it at another file; `forget()` after).
static var data_path := DATA_PATH
static var _cache := {}
## -1: the arguments decide; 0: off; 1: on (`force`).
static var _forced := -1

## What the demo is when the file says nothing (or cannot be read).
const FALLBACK := {
	"seed": 3003,
	"crew": 5,
	"nights": 3,
	"big_night_day": 3,
	"briefing_from_day": 2,
	"ideas_from_day": 2,
	"trip_place": "pharmacy",
	"buildings": ["salvage_bench", "workshop", "bunk_house", "tents", "floodlights", "watchtower"],
	"places": ["houses", "pharmacy"],
	"road_events": ["ambush", "roadblock", "survivor", "wreck_supplies", "breakdown"],
	"start_stock": {},
	"night_mult": {},
	"big_night": {},
	"wishlist_url": "",
	"copy": {
		"caps": "Three Bells: the demo",
		"title": "Thanks for playing the Thirty Bells demo",
		"line": "Three nights held. That was the first of thirty.",
		"full": "The full game is thirty nights, with a convoy at the last bell.",
	},
}


## Whether this process is the demo.
static func on() -> bool:
	if _forced >= 0:
		return _forced == 1
	if OS.has_feature(FEATURE):
		return true
	return FLAG in OS.get_cmdline_user_args()


## A test's switch: true or false for the demo on or off whatever the arguments are, null to let them decide again.
static func force(value) -> void:
	_forced = -1 if value == null else (1 if bool(value) else 0)


static func forget() -> void:
	_cache.clear()


## The demo's data: the file over the fallbacks (a copy: the caller may do what it likes with it).
static func data() -> Dictionary:
	if not _cache.has(data_path):
		var out: Dictionary = FALLBACK.duplicate(true)
		var raw = null
		if FileAccess.file_exists(data_path):
			# (the instance's `parse` says nothing about a damaged file: the fallbacks stand in, quietly)
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(data_path)) == OK:
				raw = json.data
		if raw is Dictionary:
			for k in raw:
				if String(k).begins_with("_"):
					continue
				var base = out.get(k)
				if base is Dictionary and raw[k] is Dictionary:
					for kk in raw[k]:
						base[kk] = raw[k][kk]
				elif base == null or typeof(base) == typeof(raw[k]) or (_is_num(base) and _is_num(raw[k])):
					out[k] = raw[k]
		_cache[data_path] = out
	return (_cache[data_path] as Dictionary).duplicate(true)


static func _is_num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func run_seed() -> int:
	return int(data().seed)


static func crew() -> int:
	return clampi(int(data().crew), 3, 6)


## How many nights the demo has (the run ends at the dawn after them).
static func nights() -> int:
	return maxi(1, int(data().nights))


## The day whose night is the Big Night.
static func big_night_day() -> int:
	return int(data().big_night_day)


static func buildings() -> Array:
	return _ids(data().buildings)


static func places() -> Array:
	return _ids(data().places)


static func road_events() -> Array:
	return _ids(data().road_events)


static func _ids(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for v in raw:
			out.append(String(v))
	return out


## The store of the end card's Wishlist button, "" for none (the button is not there).
static func wishlist_url() -> String:
	return String(data().wishlist_url).strip_edges()


## A line of the end card's words ("caps", "title", "line", "full").
static func copy(key: String) -> String:
	var c = data().get("copy", {})
	if c is Dictionary and c.has(key):
		return String(c[key])
	return String((FALLBACK.copy as Dictionary).get(key, ""))
