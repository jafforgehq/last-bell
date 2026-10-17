## The recorded sounds (tools/import_library_sounds.py, from Kenney's CC0 packs and the Sonniss GDC bundles): assets/audio/lib/library.json maps a file the game
## already loads (a synthesised one) to the recordings that stand in for it. `recorded(stream)` is called where a sound is loaded: a one-shot becomes an
## AudioStreamRandomizer of its 3 to 6 takes, each play a little higher or lower (about 6 percent) and louder or softer (about 2 dB); a loop becomes the
## recorded loop (a plain AudioStreamWAV, so the code that sets its loop points still works). A file with no recording, or a missing map, is left as it was.
extends RefCounted

const MAP_FILE := "res://assets/audio/lib/library.json"
const PITCH := 1.06
const VOLUME_DB := 2.0

static var _map = null
static var _made := {}


static func _read() -> Dictionary:
	if _map == null:
		_map = {}
		var f := FileAccess.open(MAP_FILE, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		if d is Dictionary:
			_map = d
	return _map


## The recording for `st` (by the path it was loaded from), or `st` itself.
static func recorded(st: AudioStream) -> AudioStream:
	if st == null or st.resource_path == "":
		return st
	var path := st.resource_path
	if _made.has(path):
		return _made[path]
	var m := _read()
	var out: AudioStream = st
	if (m.get("loops", {}) as Dictionary).has(path):
		var lp := String(m.loops[path])
		if ResourceLoader.exists(lp):
			out = load(lp)
	elif (m.get("sounds", {}) as Dictionary).has(path):
		var takes: Array = []
		for p in m.sounds[path]:
			if ResourceLoader.exists(String(p)):
				takes.append(load(String(p)))
		if not takes.is_empty():
			var r := AudioStreamRandomizer.new()
			for i in takes.size():
				r.add_stream(i, takes[i])
			r.random_pitch = PITCH
			r.random_volume_offset_db = VOLUME_DB
			r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS if takes.size() > 1 else AudioStreamRandomizer.PLAYBACK_RANDOM
			out = r
	_made[path] = out
	return out


## `recorded` on each of a list of streams.
static func recorded_all(list: Array) -> Array:
	return list.map(func(s): return recorded(s))
