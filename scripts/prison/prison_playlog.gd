## PLAYLOG: what a closed playtester's run looked like, so the owner can read it without watching. One JSON object per line in `user://playlog.jsonl` (the same user:// the save and the prefs use,
## so it works in the itch web build): a "run" header, one "day" line per game day (stores, crew, deaths, raids, the night, event cards), and an "end" line (how it ended, or where the player quit).
## The file keeps the last MAX_LINES lines (older runs fall off first). Every read and write is guarded: a damaged line is skipped, a failed write is ignored, nothing here can crash the game.
## Hooks live in prison_arc.gd (`plog`): `_on_day` (close_day), `deliver` (event), `on_raid` (raid), `night_over` (night), `end` (finish); prison_pause.gd calls `quit_at` and `copy_report`.
## Flags: `--nolog` (no file; `--nosave` too).
extends RefCounted

const BuildInfo := preload("res://scripts/build_info.gd")
const PATH := "user://playlog.jsonl"
const MAX_LINES := 150

var game
var arc
var lines: Array = []    # every kept line, older runs first (dictionaries)
var run_start := 0    # index in `lines` of this run's header
var notes := ""    # one line the player typed in the pause menu
var _raids: Array = []
var _events: Array = []
var _night := {}
var _cause := {}    # name -> cause, from the night's report
var _t0 := 0
var _off := false
var _closed := -1    # the last day written (the quit hook must not write a day twice)


func _init(g, a) -> void:
	game = g
	arc = a
	_t0 = Time.get_ticks_msec()
	var args: Dictionary = g.args
	_off = args.has("nosave") or args.has("nolog")
	lines = _load()
	run_start = lines.size()
	lines.append({"t": "run", "ver": BuildInfo.VERSION, "seed": String(args.get("seed", "random")), "diff": String(args.get("diff", "standard")), "date": Time.get_datetime_string_from_system(true)})
	_save()


# ----------------------------------------------------------------------------- hooks --

func raid(alive: bool, loot_got: Dictionary) -> void:
	var y := {}
	for k in loot_got:
		if float(loot_got[k]) > 0.0:
			y[k] = int(loot_got[k])
	_raids.append({"kind": "truck raid", "out": "back" if alive else "Ruth down", "yield": y})


func night(stat: Dictionary) -> void:
	var crew: Array = stat.get("crew", [])
	for nm in crew:
		_cause[String(nm)] = "night attack"
	_night = {"sent": int(stat.get("n", 0)), "killed": int(stat.get("killed", 0)), "fence_lost": (stat.get("lost", []) as Array).size(), "crew_lost": crew.size()}


func event(id: String, choice: String) -> void:
	_events.append(id if choice == "" else "%s:%s" % [id, choice])


## The day that is ending (arc.day is still its number): one line, and the buckets start empty.
func close_day() -> void:
	if int(arc.day) == _closed:
		return
	_closed = int(arc.day)
	var st := {}
	for k in game.stores:
		st[k] = int(float(game.stores[k]))
	var dead := []
	for nm in arc.ever:
		var e: Dictionary = arc.ever[nm]
		if String(e.fate) == "died" and int(e.get("day_out", -1)) == int(arc.day):
			var c := String(e.get("cause", ""))
			dead.append([nm, c if c != "" else String(_cause.get(nm, "unknown"))])
	_add({"t": "day", "day": int(arc.day), "phase": String(arc.phase().get("id", "")), "stores": st, "crew": arc.people_alive(), "dead": dead, "raids": _raids, "night": _night, "events": _events, "min": _minutes()})
	_raids = []
	_events = []
	_night = {}


func finish(how: String) -> void:
	close_day()
	_add({"t": "end", "how": how, "day": int(arc.day), "min": _minutes()})


## The player quit from the pause menu.
func quit_at() -> void:
	finish("quit from the pause menu")


# --------------------------------------------------------------------------- report --

## A compact plain-text summary of this run (and the version), for the clipboard.
func report() -> String:
	var out := PackedStringArray()
	var head: Dictionary = lines[run_start] if run_start < lines.size() else {}
	out.append("THIRTY BELLS playtest report | build %s | seed %s | difficulty %s" % [BuildInfo.VERSION, String(head.get("seed", "?")), String(head.get("diff", "?"))])
	out.append("Played %d min, now day %d of %d" % [_minutes(), int(arc.day), arc.days()])
	for i in range(run_start + 1, lines.size()):
		var l: Dictionary = lines[i]
		if String(l.t) == "day":
			var s := PackedStringArray()
			for k in l.stores:
				s.append("%s %d" % [k, int(l.stores[k])])
			var row := "D%d %s crew %d | %s" % [int(l.day), String(l.phase), int(l.crew), " ".join(s)]
			if not (l.dead as Array).is_empty():
				row += " | DEAD " + ", ".join((l.dead as Array).map(func(d): return "%s (%s)" % [d[0], d[1]]))
			for r in l.raids:
				row += " | raid %s %s" % [r.out, JSON.stringify(r.yield)]
			if not (l.night as Dictionary).is_empty():
				row += " | night sent %d killed %d fence lost %d crew lost %d" % [int(l.night.sent), int(l.night.killed), int(l.night.fence_lost), int(l.night.crew_lost)]
			if not (l.events as Array).is_empty():
				row += " | cards " + ", ".join(l.events)
			out.append(row)
		elif String(l.t) == "end":
			out.append("END: %s (day %d, %d min)" % [String(l.how), int(l.day), int(l.min)])
	if notes != "":
		out.append("NOTES: " + notes)
	out.append("")
	out.append("Send this to Fedja with what felt wrong.")
	return "\n".join(out)


func copy_report() -> void:
	DisplayServer.clipboard_set(report())


# ---------------------------------------------------------------------------- files --

func _minutes() -> int:
	return int((Time.get_ticks_msec() - _t0) / 60000)


func _add(l: Dictionary) -> void:
	lines.append(l)
	if lines.size() > MAX_LINES:
		var cut := lines.size() - MAX_LINES
		lines = lines.slice(cut)
		run_start = maxi(0, run_start - cut)
	_save()


func _load() -> Array:
	var out: Array = []
	if _off or not FileAccess.file_exists(PATH):
		return out
	for ln in FileAccess.get_file_as_string(PATH).split("\n", false):
		var j := JSON.new()    # (not parse_string: that logs an error for every damaged line)
		var p = j.data if j.parse(ln) == OK else null
		if p is Dictionary and String(p.get("t", "")) in ["run", "day", "end"]:
			out.append(p)
	return out.slice(maxi(0, out.size() - MAX_LINES + 1))


func _save() -> void:
	if _off:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	for l in lines:
		f.store_line(JSON.stringify(l))
	f.close()
