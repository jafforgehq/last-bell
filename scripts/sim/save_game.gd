## Saving and loading a run: the rules' whole state as versioned JSON.
## STUB: the run builder fills this in. A save can only be applied to a freshly
## built Sim (same map data); main.gd reloads the scene and applies it.
extends RefCounted

const VERSION := 1
const QUICK_PATH := "user://quicksave.json"
const AUTO_PATH := "user://autosave.json"


## The state of `sim` as plain data (numbers, strings, arrays, dictionaries).
static func to_dict(_sim) -> Dictionary:
	return {}


## Applies saved data to a freshly built `sim`. Returns false (and leaves the
## sim alone) if the data is missing, from another version or damaged.
static func apply(_sim, _data: Dictionary) -> bool:
	return false


static func write(sim, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(sim)))
	return true


## The saved data at `path`, or an empty dictionary if there is none or it does
## not parse.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
