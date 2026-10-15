## META: what outlives a run. Three small JSON files in user:// (all beside the save: `--savefile=NAME` gives NAME.legacy.json and NAME.milestones.json, so a scripted run never touches the real ones):
## the LEGACY of the last finished run (best gun and the survivor with the most days; New game plus starts from it), the MILESTONES (twelve achievements, toast when one unlocks), and the DAILY SEED
## (a number from the UTC date, for a new game; nothing is stored). Every read and write is guarded: a bad file is an empty one, a failed write is ignored.
extends RefCounted

const LEGACY := "prison_legacy.json"
const MILES := "prison_milestones.json"
## The twelve milestones: id, name, and the rule in words (the rules themselves are in `_met`).
const LIST := [
	["first_clear", "First clear", "Clear the prison and take the base."],
	["first_rescue", "First rescue", "Bring one survivor home from a raid."],
	["five_rescues", "Full house", "Bring five survivors home in one run."],
	["first_horde", "First horde held", "Live through a night attack."],
	["raids10", "Ten raids", "Go out on ten raids in one run."],
	["day10", "Day 10", "Reach day 10."],
	["day20", "Day 20", "Reach day 20."],
	["day30", "Day 30", "Reach day 30, the day of the convoy."],
	["kills200", "Two hundred dead", "Put down 200 of the dead in one run."],
	["evacuated", "Out of there", "Leave on the convoy."],
	["held_fort", "Held the fort", "Hold the prison to the dawn."],
	["no_one_lost", "Nobody lost", "Finish a run with nobody dead and nobody walked out."]]

static var sf_override := ""    # a test names its own files here


## The savefile name this process was started with (`--savefile=NAME`), "" for the real files.
static func savefile() -> String:
	if sf_override != "":
		return sf_override
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--savefile="):
			return String(a).trim_prefix("--savefile=").get_file().trim_suffix(".json")
	return ""


static func path(kind: String) -> String:
	var sf := savefile()
	if sf == "":
		return "user://" + kind
	return "user://%s.%s" % [sf, kind.trim_prefix("prison_")]


static func _read(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _write(p: String, d: Dictionary) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()


static func _quiet(g) -> bool:
	return g.args.has("nosave")


# ------------------------------------------------------------------------------ legacy -------

## The last finished run's legacy ({} when there is none).
static func legacy() -> Dictionary:
	var d := _read(path(LEGACY))
	return d if typeof(d.get("weapon")) == TYPE_STRING and String(d.weapon) != "" else {}


## One line for the New game screen: "Keeps the rifle and Lena (23 days)".
static func legacy_line(arms_names: Dictionary = {}) -> String:
	var d := legacy()
	if d.is_empty():
		return ""
	var gun := String(arms_names.get(String(d.weapon), d.weapon))
	var s: Dictionary = d.get("survivor", {})
	return "Keeps the %s%s." % [gun, (" and %s (%d days)" % [String(s.name), int(s.get("days", 0))]) if not s.is_empty() else ""]


## Written at an evacuation or a held ending: the gun in her hands and the recruit who has been here longest.
static func write_legacy(g, ending_id: String) -> void:
	if _quiet(g) or not (ending_id.begins_with("evac") or ending_id.begins_with("held")):
		return
	var best := {}
	var most := -1
	for r in g.people.recruits:
		var e: Dictionary = g.arc.ever.get(String(r.name), {})
		var days: int = int(g.arc.day) - int(e.get("day", g.arc.day))
		if e.is_empty() or String(e.get("fate", "")) != "" or days <= most:
			continue
		most = days
		best = {"name": String(r.name), "key": String(r.key), "look": r.look, "role": String(g.econ.cfg.crew_role.get(String(r.id), "hauler")), "days": days}
	_write(path(LEGACY), {"weapon": String(g.arms.main), "ending": ending_id, "day": int(g.arc.day), "survivor": best})


## New game plus: her best gun is in the rack and in her hands, the survivor walks in at the gate.
static func apply_legacy(g) -> void:
	var d := legacy()
	if d.is_empty() or not g.arms.cfg().guns.has(String(d.weapon)):
		return
	g.arms.main = String(d.weapon)
	g.arms.armory[g.arms.main] = maxi(1, int(g.arms.armory.get(g.arms.main, 0)))
	var s: Dictionary = d.get("survivor", {})
	if not s.is_empty():
		g.people.recruits.append(g.people._make_recruit({"name": String(s.name), "key": String(s.key), "look": s.look, "skill": String(s.role)}))


# ---------------------------------------------------------------------------- milestones -----

static func unlocked() -> Dictionary:
	return _read(path(MILES))


static func _met(id: String, g, ending_id: String) -> bool:
	var st: Dictionary = g.arc.stats
	match id:
		"first_clear": return g.phase == "managed" and g.arc.started
		"first_rescue": return int(st.rescues) >= 1
		"five_rescues": return int(st.rescues) >= 5
		"first_horde": return int(st.nights_held) >= 1
		"raids10": return int(st.raids) >= 10
		"day10": return int(g.arc.day) >= 10
		"day20": return int(g.arc.day) >= 20
		"day30": return int(g.arc.day) >= 30
		"kills200": return int(st.kills) >= 200
		"evacuated": return ending_id.begins_with("evac")
		"held_fort": return ending_id.begins_with("held")
		"no_one_lost": return (ending_id.begins_with("evac") or ending_id.begins_with("held")) and int(st.deaths) == 0 and int(st.left) == 0
	return false


## Unlocks what is met now (the file is written, a toast says each one). Returns the new ids.
static func check(g, ending_id := "") -> Array:
	if _quiet(g) or not g.arc.started and ending_id == "":
		return []
	var have := unlocked()
	var got: Array = []
	for m in LIST:
		if not have.has(m[0]) and _met(String(m[0]), g, ending_id):
			have[m[0]] = int(Time.get_unix_time_from_system())
			got.append(m)
	if got.is_empty():
		return []
	_write(path(MILES), have)
	for m in got:
		g.board.toast("Milestone: %s" % String(m[1]), Color(0.95, 0.8, 0.35))
	return got.map(func(m): return m[0])


# ----------------------------------------------------------------------------- daily seed ----

## {"seed": 100000..999999, "date": "2026-10-15"}: the same for everybody on the same UTC day.
static func daily(unix := -1) -> Dictionary:
	var t := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) if unix < 0 else unix)
	var date := "%04d-%02d-%02d" % [t.year, t.month, t.day]
	return {"seed": ("daily " + date).hash() % 900000 + 100000, "date": date}
