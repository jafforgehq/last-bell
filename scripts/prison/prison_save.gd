## SAVE (Steam audit C1, idea 1): the prison's one save slot. A versioned JSON file in user:// of its own (not the old games' saves, not prison_arc.json), written by `prison_game.gd` at dawn, on a return from a raid and
## when the pause menu asks, and read by the title's Continue and `--prison --continue`.
## WHAT IS SAVED: the managed base only: the clock and the night count, the stores, the economy (projects, tiers, roles, morale), the story (beats seen, choices, letters, log, stats), the fence's hit points, the crew
## (the three first people by `allies_alive`, who walked out or died by `econ_gone`, the people raids brought by `people.recruits`), the weapon rack, the backpack and the belt.
## ALSO (no version change: an older file lacks the key and loads with empty defaults): `raidx`, the destination map's Done and Avoid marks and the three loadout presets.
## WHAT IS NOT: a raid, a night attack and the clear phase (a save is refused in all three; the clear phase starts again from its beginning); a crew member's place on the floor (the crew is rebuilt at the gate, as at every
## return from a raid); the dead of the pen; the gate's choice of target.
## FAIL SAFE: a file that cannot be read, is not what it says or is of another version is refused with a line of words and nothing is loaded; the previous save is kept as `prison_save.bak.json` and is the fallback.
## The file name can be changed with `--savefile=NAME` (a lab or a test then never touches the player's save).
extends RefCounted

const VERSION := 2    # 2: the project list was cut to ten (water, garden, kitchen, infirmary, dormitory, power, fence 1-2, radio, convoy)
const FILE := "prison_save.json"
const SECTIONS := ["game", "econ", "arc", "siege", "people", "arms", "pack"]


static func path_for(args: Dictionary = {}) -> String:
	return "user://" + String(args.get("savefile", FILE)).get_file()


static func _bak(p: String) -> String:
	return p.trim_suffix(".json") + ".bak.json"


## Whether this process was asked to continue: `--continue` or the title's Continue (the run's meta).
static func wants(args: Dictionary) -> bool:
	if args.has("continue"):
		return true
	return Engine.has_meta("run") and typeof(Engine.get_meta("run")) == TYPE_DICTIONARY and bool((Engine.get_meta("run") as Dictionary).get("prison_load", false))


# ------------------------------------------------------------------------------- when -------

## "" when the game may be saved now, else the reason in words. Only the calm base: not in a raid, an attack, the clear phase, a cut-scene, an ending, or when a night attack is due this very moment.
static func why_not(g) -> String:
	if g.phase != "managed":
		return "Not while clearing the prison. The clear phase starts again from the beginning."
	if g.mode != "base":
		return "Not out on a raid. The game is saved when you are back."
	if g.siege.attacking or g.siege.pending > 0:
		return "Not during an attack. The game is saved at dawn."
	if g.siege.abs_h >= g.siege.NIGHT_H + 24.0 * float(g.siege.nights_started):
		return "The night is falling. The game is saved at dawn."
	if g.busy or g.run == null or g.crew == null:
		return "Not now."
	if g.arc.ended_id != "" or not g.arc.started:
		return "Not now."
	if g.arc.story.card != null:
		return "Close the card first."
	return ""


## The autosave at dawn: once a day, from 6:36 (the economy's day turns at 6:00, the night's report is done by 6:30) to the morning, from day 2.
static func dawn(g) -> void:
	if g.phase != "managed" or g.tod < 6.6 or g.tod > 10.0 or int(g.econ.day) < 2 or int(g.econ.day) == int(g.save_day):
		return
	if why_not(g) == "":
		if write(g, "dawn") == "":
			g._say("Saved at dawn.", 2.5)


## The autosave of a return from a raid (silent: the raid's own line is on the screen).
static func raid_return(g) -> void:
	if g.args.has("nosave") or why_not(g) != "":
		return
	write(g, "raid")


# ------------------------------------------------------------------------------- write -------

## Writes the save. "" when it is done, else why not. The old file becomes the backup, and the new one is written whole before it replaces anything.
static func write(g, reason: String) -> String:
	var why := why_not(g)
	if why != "":
		return why
	var snap := snapshot(g)
	snap["reason"] = reason
	var p := path_for(g.args)
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "The save could not be written."
	f.store_string(JSON.stringify(_enc(snap)))
	f.close()
	if FileAccess.file_exists(p):
		DirAccess.copy_absolute(p, _bak(p))    # (one backup: the save before this one)
	if DirAccess.rename_absolute(tmp, p) != OK:
		return "The save could not be written."
	g.save_day = int(g.econ.day)
	return ""


static func snapshot(g) -> Dictionary:
	var stores := {}
	for k in g.stores:
		stores[String(k)] = float(g.stores[k])
	return {
		"version": VERSION, "unix": int(Time.get_unix_time_from_system()),
		"day": int(g.econ.day), "days": int(g.arc.days()), "nights": int(g.siege.nights_started), "people": int(g.econ.people()),
		"game": {"tod": float(g.tod), "stores": stores, "raids": int(g.raids), "allies_alive": g.allies_alive.duplicate(), "econ_gone": g.econ_gone.duplicate(), "shots_fired": int(g.shots_fired)},
		"econ": g.econ.to_dict(), "arc": g.arc.to_dict(), "siege": g.siege.to_dict(), "people_mod": g.people.to_dict(), "arms": g.arms.to_dict(), "pack": g.pack.to_dict(), "clean": g.cleaner.to_dict() if g.cleaner != null else {}, "raidx": g.raidx.to_dict(), "level": int(g.Bal.level), "run_seed": int(g.Bal.run_seed)}


## `--saveecho` (a check): writes what the game holds now to user://<savefile>.echo.json, to be compared with the save it was loaded from.
static func echo(g) -> void:
	var f := FileAccess.open(path_for(g.args) + ".echo.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_enc(snapshot(g))))
	f.close()


# -------------------------------------------------------------------------------- read -------

## {"ok", "why", "data", "backup"}: the newest file that can be used (the backup when the save is bad). `why` says what is wrong with the file when none can be used, and `backup` when the backup was used.
static func read(args: Dictionary = {}) -> Dictionary:
	var p := path_for(args)
	var first := _read_file(p)
	if bool(first.ok):
		return first
	var second := _read_file(_bak(p))
	if bool(second.ok):
		second["backup"] = true
		return second
	if not FileAccess.file_exists(p) and not FileAccess.file_exists(_bak(p)):
		return {"ok": false, "why": "There is no saved game yet.", "missing": true}
	return first if FileAccess.file_exists(p) else second


static func _read_file(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {"ok": false, "why": "There is no saved game."}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "why": "The save is damaged and cannot be read."}
	var d: Dictionary = _dec(parsed)
	if not d.has("version") or int(d.version) != VERSION:
		return {"ok": false, "why": "This save is from an older version of the game (the base projects changed) and cannot be continued. Start a new game.", "version": true}
	for s in ["game", "econ", "arc", "siege", "people_mod", "arms", "pack"]:
		if typeof(d.get(s)) != TYPE_DICTIONARY:
			return {"ok": false, "why": "The save is damaged and cannot be read."}
	var gm: Dictionary = d.game
	if typeof(gm.get("stores")) != TYPE_DICTIONARY or not gm.has("tod") or typeof(gm.get("allies_alive")) != TYPE_ARRAY or typeof(gm.get("econ_gone")) != TYPE_ARRAY:
		return {"ok": false, "why": "The save is damaged and cannot be read."}
	return {"ok": true, "why": "", "data": d, "backup": false}


## For the title: {} when there is no save at all, else {"ok", "line", "why"}: one line for the Continue button.
static func peek(args: Dictionary = {}) -> Dictionary:
	var r := read(args)
	if not bool(r.ok):
		return {} if bool(r.get("missing", false)) else {"ok": false, "line": String(r.why), "why": String(r.why)}
	var d: Dictionary = r.data
	var line := "Day %d of %d, %d people. Saved at dawn." % [int(d.day), int(d.days), int(d.people)]
	return {"ok": true, "line": line, "why": "", "unix": int(d.get("unix", 0)), "backup": bool(r.get("backup", false))}


# -------------------------------------------------------------------------------- apply ------

## Puts a save back into a game that has been made but has not built its base yet (`_enter_base` comes next and builds the crew, the fence and the visuals from this).
static func apply(g, d: Dictionary) -> void:
	var gm: Dictionary = d.game
	g.tod = float(gm.tod)
	for k in (gm.stores as Dictionary):
		g.stores[String(k)] = float(gm.stores[k])
	g.raids = int(gm.get("raids", 0))
	g.allies_alive = (gm.allies_alive as Array).duplicate()
	g.econ_gone = (gm.econ_gone as Array).duplicate()
	g.shots_fired = int(gm.get("shots_fired", 0))
	g.Bal.level = clampi(int(d.get("level", 1)), 0, 2)    # (the difficulty and the run seed come back with the run)
	g.Bal.run_seed = int(d.get("run_seed", g.Bal.run_seed))
	g.econ.from_dict(d.econ)
	g.siege.from_dict(d.siege)
	g.people.from_dict(d.people_mod)
	g.arms.from_dict(d.arms)
	g.pack.from_dict(d.pack)
	g.Clean.pending = d.get("clean", {})    # (the piles are put on the spots when the base is built)
	g.arc.from_dict(ints(d.arc))
	g.raidx.from_dict(ints(d.get("raidx", {})))    # (RAID EXTRAS: the map's marks and the loadout presets; an older save has none and starts with none)
	g.save_day = int(g.econ.day)


## Whole floats back to ints (JSON has one number type): the story's counters and days are ints.
static func ints(v):
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if is_finite(v) and v == floorf(v) and absf(v) < 1.0e15 else v
		TYPE_ARRAY:
			var a: Array = []
			for e in v:
				a.append(ints(e))
			return a
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[k] = ints(v[k])
			return o
	return v


# ------------------------------------------------------------------------------- encoding -----

## JSON has no Vector2: a crew route's stop and the set piece's place are written as {"$v2": [x, y]}.
static func _enc(v):
	match typeof(v):
		TYPE_VECTOR2:
			return {"$v2": [v.x, v.y]}
		TYPE_VECTOR2I:
			return {"$v2": [v.x, v.y]}
		TYPE_ARRAY:
			var a: Array = []
			for e in v:
				a.append(_enc(e))
			return a
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[String(k)] = _enc(v[k])
			return o
		TYPE_FLOAT:
			return v if is_finite(v) else 0.0
		TYPE_COLOR:
			return v.to_html()
	return v


static func _dec(v):
	match typeof(v):
		TYPE_ARRAY:
			var a: Array = []
			for e in v:
				a.append(_dec(e))
			return a
		TYPE_DICTIONARY:
			if v.size() == 1 and v.has("$v2") and typeof(v["$v2"]) == TYPE_ARRAY and (v["$v2"] as Array).size() == 2:
				return Vector2(float(v["$v2"][0]), float(v["$v2"][1]))
			var o := {}
			for k in v:
				o[k] = _dec(v[k])
			return o
	return v
