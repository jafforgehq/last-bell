## The nights' tunables (round 19), read from assets/data/nights.json: the only home of the numbers of the Big Nights, the
## avatar's rally, the plated brutes, the breaches, the calls and the forecast, so that tuning never edits code.
## Asked by a dotted path ("rally.radius", "themes.siege.factor"); a missing or damaged file, or a missing key, gives the
## fallbacks below (the numbers of the plan, docs/superpowers/plans/2026-10-03-round-19.md). Tests point `data_path`
## elsewhere (as seasons.gd's do) and never copy a number: they read it through here.
##
##   static func num(path: String, fallback := 0.0) -> float    # `fallback` only when the plan has no number for the path either
##   static func text(path: String, fallback := "") -> String
##   static func list(path: String) -> Array                     # a copy ([] if none)
##   static func theme(id: String) -> Dictionary                 # a copy of themes.<id> ({} if none)
extends RefCounted

const DATA_PATH := "res://assets/data/nights.json"
## Tests may point this elsewhere (a copy, a damaged file, a path that does not exist).
static var data_path := DATA_PATH
static var _cache := {}

## What every path answers when the file or the key is missing: the plan's own numbers.
const FALLBACK := {
	"version": 1,
	"ordinary": {"avatar_weight": 0.5, "mult": 1.0, "growth": 0.10},
	"big_every": 10,
	"order": ["siege", "rush"],
	"themes": {
		"siege": {"name": "The Siege", "factor": 1.45, "runners": 0.10, "brutes": 0.22, "headings": 1, "main_share": 0.85, "brute_at": [0.25, 0.6], "cap": 70, "blurb": "Plated brutes at one wall. Be there."},
		"rush": {"name": "The Rush", "factor": 1.55, "runners": 0.35, "brutes": 0.12, "headings": 1, "main_share": 0.80, "brute_at": [0.30, 0.7], "cap": 70, "blurb": "A wave of runners, brutes behind. Be there."},
		"last": {"name": "The last night", "brute_at": [0.3, 0.8]},
	},
	"rally": {"radius": 9.0, "aim": 0.15, "fire": 0.85},
	"plated": {"armour": 0.2, "weak_mult": 3.0, "weak_r": 0.2, "head": 0.62, "npc_weak": 0.08},
	"breach": {"hot_r": 7.0, "hot_n": 2},
	"mend": {"reach": 1.6, "seconds": 10.0},
	"calls": {"going_below": 0.4, "going_ttl_min": 20, "brute_ttl_min": 45, "breach_ttl_min": 20, "reinforce_n": 2, "coming_morale": 4.0, "coming_window_min": 15, "kept_trust": 2.0, "broken_trust": -2.0, "brute_warn_r": 40.0},
	"forecast": {"notice_hour": 12.0, "decent_walls": 0.7, "decent_guns": 2, "road_margin_min": 30, "road_warn_min": 60},
}


## Forgets what was read (a test that rewrote the file at `data_path` asks for it to be read again).
static func forget() -> void:
	_cache.clear()


## The file's data, read once per path (a missing or damaged file is {}).
static func _data() -> Dictionary:
	if not _cache.has(data_path):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		_cache[data_path] = raw if typeof(raw) == TYPE_DICTIONARY else {}
	return _cache[data_path]


## The value at a dotted path in `from`, or null.
static func _dig(from: Dictionary, path: String):
	var node = from
	for key in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(key):
			return null
		node = node[key]
	return node


## The value at `path`: the file's, else the plan's, else null.
static func _value(path: String):
	var v = _dig(_data(), path)
	if v == null:
		v = _dig(FALLBACK, path)
	return v


static func num(path: String, fallback: float = 0.0) -> float:
	var v = _value(path)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return fallback


static func text(path: String, fallback: String = "") -> String:
	var v = _value(path)
	return String(v) if typeof(v) == TYPE_STRING else fallback


static func list(path: String) -> Array:
	var v = _value(path)
	return (v as Array).duplicate(true) if typeof(v) == TYPE_ARRAY else []


## A copy of the theme `id` ("siege", "rush", "last"): the plan's numbers under the file's, {} if there is none.
static func theme(id: String) -> Dictionary:
	var out := {}
	var base = _dig(FALLBACK, "themes.%s" % id)
	if typeof(base) == TYPE_DICTIONARY:
		out = (base as Dictionary).duplicate(true)
	var mine = _dig(_data(), "themes.%s" % id)
	if typeof(mine) == TYPE_DICTIONARY:
		for k in mine:
			out[k] = (mine[k].duplicate(true) if typeof(mine[k]) == TYPE_ARRAY or typeof(mine[k]) == TYPE_DICTIONARY else mine[k])
	return out
