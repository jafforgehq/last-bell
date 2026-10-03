extends "res://tests/case.gd"
## The nights' tunables (round 19, scripts/sim/night_data.gd, assets/data/nights.json): the file holds every number of the Big Nights,
## the rally, the plated brutes, the breaches, the calls and the forecast; a missing or damaged file, or a missing key, gives the
## plan's own numbers (`NightData.FALLBACK`). The tests read numbers through NightData and never copy one.

const NightData := preload("res://scripts/sim/night_data.gd")

const FIXTURE := "user://test_r19_nights_data_%d.json"
var _n := 0


## Points NightData at a file holding `content` (null: a path with no file), asks `probe`, puts everything back and returns the answer.
func _with(content, probe: Callable):
	var was: String = NightData.data_path
	_n += 1
	var path := FIXTURE % (OS.get_process_id() * 100 + _n)
	if content != null:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(String(content))
		f.close()
	NightData.data_path = path
	NightData.forget()
	var answer = probe.call()
	NightData.data_path = was
	NightData.forget()
	if content != null:
		DirAccess.remove_absolute(path)
	return answer


# ------------------------------------------------------------------ the file --

func test_the_file_is_there_and_names_every_group_of_numbers() -> void:
	eq(NightData.data_path, NightData.DATA_PATH, "the game reads assets/data/nights.json")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(NightData.DATA_PATH))
	check(typeof(parsed) == TYPE_DICTIONARY, "the file parses to a dictionary")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for group in NightData.FALLBACK:
		check(parsed.has(group), "the file has `%s`" % group)
		if typeof(NightData.FALLBACK[group]) == TYPE_DICTIONARY and parsed.has(group):
			for key in NightData.FALLBACK[group]:
				check(parsed[group].has(key), "the file has `%s.%s`" % [group, key])


func test_every_number_in_the_file_reads_as_a_number() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(NightData.DATA_PATH))
	for group in ["ordinary", "rally", "plated", "breach", "mend", "calls", "forecast"]:
		for key in parsed[group]:
			var v = NightData.num("%s.%s" % [group, key], NAN)
			check(not is_nan(v), "%s.%s reads as a number" % [group, key])
			near(v, float(parsed[group][key]), 0.0, "%s.%s is what the file says" % [group, key])


func test_the_themes_are_whole_and_in_range() -> void:
	var order: Array = NightData.list("order")
	check(order.size() >= 1, "there is an order of milestones")
	for id in order:
		var t: Dictionary = NightData.theme(String(id))
		check(not t.is_empty(), "the order names a theme that exists: %s" % id)
		check(String(t.get("name", "")) != "", "%s has a name" % id)
		check(String(t.get("blurb", "")) != "", "%s has a blurb" % id)
		check(float(t.get("factor", 0.0)) > 1.0, "%s is bigger than an ordinary night: %s" % [id, str(t.get("factor"))])
		var runners := float(t.get("runners", -1.0))
		var brutes := float(t.get("brutes", -1.0))
		check(runners >= 0.0 and brutes > 0.0 and runners + brutes < 1.0, "%s: the shares leave room for walkers: %s, %s" % [id, str(runners), str(brutes)])
		check(int(t.get("headings", 0)) >= 1, "%s has a heading" % id)
		check(float(t.get("main_share", 0.0)) > 0.0 and float(t.get("main_share", 0.0)) <= 1.0, "%s: the main share is a share" % id)
		check(int(t.get("cap", 0)) >= 10, "%s: a cap that lets the night happen" % id)
		check(int(t.get("min_brutes", 0)) >= 1, "%s: a Big Night has a brute to be there for" % id)
		var at: Array = t.get("brute_at", [])
		check(at.size() == 2 and float(at[0]) >= 0.0 and float(at[0]) < float(at[1]) and float(at[1]) <= 1.0, "%s: the brutes come in a range of the queue: %s" % [id, str(at)])
	var last: Dictionary = NightData.theme("last")
	check(String(last.get("name", "")) != "", "the last night has a name")
	var at: Array = last.get("brute_at", [])
	check(at.size() == 2 and float(at[0]) < float(at[1]) and float(at[1]) <= 1.0, "and its brutes come in a range: %s" % str(at))
	check(NightData.theme("nothing").is_empty(), "a theme that is not there is {}")
	check(float(NightData.num("big_every")) >= 2.0, "a Big Night every few nights")


func test_a_theme_is_a_copy() -> void:
	var t: Dictionary = NightData.theme("siege")
	var factor: float = t.factor
	t["factor"] = 99.0
	(t["brute_at"] as Array)[0] = 0.99
	var again: Dictionary = NightData.theme("siege")
	near(float(again.factor), factor, 0.0, "changing the answer does not change the data")
	check(float(again.brute_at[0]) < 0.9, "nor its lists")
	var order: Array = NightData.list("order")
	order.clear()
	check(NightData.list("order").size() >= 1, "a list is a copy too")


# ----------------------------------------------------------------- fallbacks --

func test_a_missing_file_gives_the_plans_numbers() -> void:
	var seen = _with(null, func(): return {
		"radius": NightData.num("rally.radius", -1.0),
		"factor": NightData.num("themes.siege.factor", -1.0),
		"name": NightData.text("themes.rush.name", "?"),
		"order": NightData.list("order"),
		"siege": NightData.theme("siege"),
		"last": NightData.theme("last"),
		"extra": NightData.num("nothing.at.all", 7.5),
		"text": NightData.text("nothing.at.all", "none"),
	})
	near(float(seen.radius), float(NightData.FALLBACK.rally.radius), 0.0, "the rally radius is the plan's")
	near(float(seen.factor), float(NightData.FALLBACK.themes.siege.factor), 0.0, "so is a theme's factor")
	eq(seen.name, NightData.FALLBACK.themes.rush.name, "and its name")
	eq(seen.order, NightData.FALLBACK.order, "and the order")
	eq(seen.siege, NightData.FALLBACK.themes.siege, "a whole theme")
	eq(seen.last, NightData.FALLBACK.themes.last, "the last night's")
	near(float(seen.extra), 7.5, 0.0, "a path the plan has no number for gives the caller's")
	eq(seen.text, "none", "and the caller's text")


func test_a_damaged_file_gives_the_plans_numbers() -> void:
	for content in ["this is not json {", "[1, 2, 3]", "", "null", "42"]:
		var seen = _with(content, func(): return {"radius": NightData.num("rally.radius", -1.0), "siege": NightData.theme("siege"), "order": NightData.list("order")})
		near(float(seen.radius), float(NightData.FALLBACK.rally.radius), 0.0, "the plan's radius after `%s`" % content)
		eq(seen.siege, NightData.FALLBACK.themes.siege, "and its theme after `%s`" % content)
		eq(seen.order, NightData.FALLBACK.order, "and its order after `%s`" % content)


func test_a_value_of_the_wrong_type_gives_the_plans_number() -> void:
	var content := JSON.stringify({"rally": {"radius": "wide", "aim": null, "fire": [1]}, "order": "siege", "themes": {"siege": {"factor": "x", "name": 7, "brute_at": "mid", "cap": 80}}})
	var seen = _with(content, func(): return {
		"radius": NightData.num("rally.radius", -1.0), "aim": NightData.num("rally.aim", -1.0), "fire": NightData.num("rally.fire", -1.0),
		"order": NightData.list("order"), "name": NightData.text("themes.siege.name", "?"), "siege": NightData.theme("siege")})
	near(float(seen.radius), float(NightData.FALLBACK.rally.radius), 0.0, "a text where a number goes: the plan's")
	near(float(seen.aim), float(NightData.FALLBACK.rally.aim), 0.0, "a null: the plan's")
	near(float(seen.fire), float(NightData.FALLBACK.rally.fire), 0.0, "a list: the plan's")
	eq(seen.order, NightData.FALLBACK.order, "a text where a list goes: the plan's")
	eq(seen.name, NightData.FALLBACK.themes.siege.name, "a number where a text goes: the plan's")
	near(float(seen.siege.factor), float(NightData.FALLBACK.themes.siege.factor), 0.0, "a theme with a bad factor has the plan's")
	eq(seen.siege.brute_at, NightData.FALLBACK.themes.siege.brute_at, "and the plan's range when it is no list")
	near(float(seen.siege.cap), 80.0, 0.0, "but what it has right it keeps")


func test_a_partial_file_changes_only_what_it_names() -> void:
	var content := JSON.stringify({"rally": {"radius": 12.5}, "themes": {"siege": {"factor": 2.0, "brute_at": [0.1, 0.2]}}})
	var seen = _with(content, func(): return {
		"radius": NightData.num("rally.radius", -1.0), "aim": NightData.num("rally.aim", -1.0), "plated": NightData.num("plated.armour", -1.0),
		"siege": NightData.theme("siege"), "rush": NightData.theme("rush")})
	near(float(seen.radius), 12.5, 0.0, "what the file names is the file's")
	near(float(seen.aim), float(NightData.FALLBACK.rally.aim), 0.0, "its neighbour is the plan's")
	near(float(seen.plated), float(NightData.FALLBACK.plated.armour), 0.0, "a group the file lacks is the plan's")
	near(float(seen.siege.factor), 2.0, 0.0, "the theme has the file's factor")
	eq(seen.siege.brute_at, [0.1, 0.2], "and its range")
	eq(seen.siege.name, NightData.FALLBACK.themes.siege.name, "and the plan's name")
	eq(seen.rush, NightData.FALLBACK.themes.rush, "a theme the file lacks is the plan's")


func test_the_file_is_read_once_and_forget_reads_it_again() -> void:
	var was: String = NightData.data_path
	var path := "user://test_r19_nights_data_forget_%d.json" % OS.get_process_id()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"rally": {"radius": 3.0}}))
	f.close()
	NightData.data_path = path
	NightData.forget()
	var first: float = NightData.num("rally.radius")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"rally": {"radius": 4.0}}))
	f.close()
	var cached: float = NightData.num("rally.radius")
	NightData.forget()
	var fresh: float = NightData.num("rally.radius")
	NightData.data_path = was
	NightData.forget()
	DirAccess.remove_absolute(path)
	near(first, 3.0, 0.0, "the file's number")
	near(cached, 3.0, 0.0, "read once")
	near(fresh, 4.0, 0.0, "and again after `forget`")
