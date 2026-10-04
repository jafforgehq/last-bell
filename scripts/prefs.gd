## What the player keeps between runs: settings and a few facts (has the tutorial
## been played), in a small text file in the user folder (`user://prefs.cfg`; on
## the web the browser keeps it). Everything has a default, so a missing file is
## fine. Every change is saved at once.
##
## Sections: `audio` (master, sfx, ambience, ui, music: 0 to 1), `ui` (scale,
## hints, reduce_motion, fullscreen, aim_mode: "right" or "always", see scripts/aim_mode.gd) and
## `flags` (tutorial_done, tutorial_offered).
extends RefCounted

const DEFAULT_PATH := "user://prefs.cfg"
const DEFAULTS := {
	"audio": {"master": 1.0, "sfx": 1.0, "ambience": 1.0, "ui": 1.0, "music": 1.0},
	"ui": {"scale": 1.0, "hints": true, "reduce_motion": false, "fullscreen": false, "aim_mode": "right"},
	"flags": {"tutorial_done": false, "tutorial_offered": false},
}

## Where the file is; tests point it somewhere else.
static var path := DEFAULT_PATH
static var _cfg: ConfigFile = null


static func _config() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if not FileAccess.file_exists(path) or _cfg.load(path) != OK:
			_cfg = ConfigFile.new()
	return _cfg


## Forgets what is in memory; the next read comes from the file again. (Not called
## `reload`: that is the name of a method every script has, and it would win.)
static func forget() -> void:
	_cfg = null


## Empties the file: every value goes back to its default.
static func reset() -> void:
	_cfg = ConfigFile.new()
	_cfg.save(path)


## A stored value, else `default`, else the built-in default (null for an unknown key).
static func get_value(section: String, key: String, default = null):
	var cfg := _config()
	if cfg.has_section_key(section, key):
		return cfg.get_value(section, key)
	if default != null:
		return default
	if DEFAULTS.has(section):
		return DEFAULTS[section].get(key)
	return null


static func set_value(section: String, key: String, value) -> void:
	var cfg := _config()
	cfg.set_value(section, key, value)
	cfg.save(path)


## A number setting; anything stored that is not a number gives the default.
static func number(section: String, key: String) -> float:
	var v = get_value(section, key)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return float(DEFAULTS.get(section, {}).get(key, 0.0))


## A switch setting; anything stored that is not true or false gives the default.
static func on(section: String, key: String) -> bool:
	var v = get_value(section, key)
	if typeof(v) == TYPE_BOOL:
		return v
	return bool(DEFAULTS.get(section, {}).get(key, false))


static func flag(name: String) -> bool:
	return on("flags", name)


static func set_flag(name: String, value: bool = true) -> void:
	set_value("flags", name, value)
