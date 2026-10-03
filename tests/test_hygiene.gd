extends "res://tests/case.gd"
## The tests of the tests: what a file of tests must not do to the files after it. The runner (run.gd) judges each case by what
## it left behind (a setting pointed elsewhere, a shared data cache edited in place, a node left in the tree, the engine's meta);
## what it cannot see is read here from the sources.

## Files two test files may both use: the settings file the whole run shares, and the quick-save the old controls tests clear.
const SHARED := ["user://prefs_test.cfg", "user://quicksave.json"]


## The data classes keep what they read of a file by the file's path (`Town._cache[path]` and its kin), so two test files that
## write different fixtures to ONE path read each other's data: the second file's town is the first one's (round 21: test_road_sim
## had no "city" because test_road_events had written its own town to the same name). Each file of tests names its own.
func test_no_two_files_of_tests_write_a_fixture_to_the_same_path() -> void:
	var literal := RegEx.create_from_string("\"(user://[^\"]+)\"")
	var users := {}    # path -> the files that name it
	for f in DirAccess.get_files_at("res://tests"):
		if not f.ends_with(".gd") or f == "test_hygiene.gd":
			continue
		for m in literal.search_all(FileAccess.get_file_as_string("res://tests/" + f)):
			var path := m.get_string(1)
			if SHARED.has(path):
				continue
			if not users.has(path):
				users[path] = []
			if not users[path].has(f):
				users[path].append(f)
	var shared_paths := []
	for path in users:
		if users[path].size() > 1:
			shared_paths.append("%s: %s" % [path, ", ".join(users[path])])
	shared_paths.sort()
	eq(shared_paths, [], "every fixture path belongs to one file of tests")
	check(users.size() > 10, "(the scan finds the fixtures: %d)" % users.size())
