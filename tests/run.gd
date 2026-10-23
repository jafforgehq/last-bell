## Runs every test_* method in tests/test_*.gd and exits non-zero if any fail:
##   Godot --headless --path . --script res://tests/run.gd [-- --only=text[,text...]] [--shard=I/N]
## Test methods may await (for example a few process frames).
extends SceneTree

const Prefs := preload("res://scripts/prefs.gd")
## The settings file the tests use: the player's own (user://prefs.cfg) is never read or
## written by a test run, whatever a test starts (the game scene reads the settings).
const TEST_PREFS := "user://prefs_test.cfg"


## Counts errors logged while tests run, so a test that crashes before its
## first check still fails. Warnings do not count.
class ErrorCounter:
	extends Logger
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1


var errors := ErrorCounter.new()
## The process-wide state a test may change and must put back, found in the scripts by `_find_globals`:
## plain: {"script", "name", "label", "start"} for each `static var` that holds a path or a flag (a test points one at a
## fixture file or flips it for a while); tables: {"script", "name", "label", "seen": key -> {"ref", "hash"}} for each static
## Dictionary (the shared data caches: a test that edits an entry in place changes the data of every game after it).
var _plain: Array = []
var _tables: Array = []
## The static Callables (a `static var x := Callable()`: PawnMotion.step_cb and thump_cb, which the game's scene points at its own effects when it starts): {"script", "name"}. A test that starts the
## game scene leaves them pointing at effects whose world is freed with it, and the next test to draw a dead one would call them: they are cleared after every case (the game sets them again
## whenever it starts), so that no case depends on which one ran before it.
var _callbacks: Array = []
## The classes of the nodes cases left in the tree (counted, and freed), and how many cases left some.
var _stray := {}
var _stray_cases := 0
var _plain_re := RegEx.create_from_string("^static var ([A-Za-z][A-Za-z0-9_]*)\\s*(?::\\s*[A-Za-z0-9_]+)?\\s*:?=\\s*(true|false|-?[0-9][0-9.]*|[A-Z][A-Z0-9_]*|\".*\")\\s*(#.*)?$")
var _table_re := RegEx.create_from_string("^static var ([A-Za-z_][A-Za-z0-9_]*)\\s*(?::\\s*Dictionary)?\\s*:?=\\s*\\{\\}")
var _callback_re := RegEx.create_from_string("^static var ([A-Za-z_][A-Za-z0-9_]*)\\s*(?::\\s*Callable)?\\s*:?=\\s*Callable\\(\\)")


func _initialize() -> void:
	Prefs.path = TEST_PREFS
	Prefs.reset()
	OS.add_logger(errors)
	_run.call_deferred()


func _run() -> void:
	var only := PackedStringArray()
	var shard := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",", false)
		elif a.begins_with("--shard="):    # --shard=I/N runs every Nth file from I, so CI can split the suite
			shard = a.trim_prefix("--shard=").split("/")
	var files: Array = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	if shard.size() == 2:
		files = files.filter(func(f): return files.find(f) % int(shard[1]) == int(shard[0]))
	_find_globals("res://scripts")
	_check_globals()    # notes what the shared data caches hold now
	errors.count = 0
	var passed := 0
	var failed := 0
	for f in files:
		var script = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			failed += 1
			print("  FAIL  %s does not load" % f)
			continue
		for m in script.get_script_method_list():
			var name: String = m.name
			var label := "%s:%s" % [f.get_basename(), name]
			if not name.begins_with("test_") or not _wanted(label, only):
				continue
			var failures: Array = await run_case(script, name)
			if failures.is_empty():
				passed += 1
				print("  ok    ", label)
			else:
				failed += 1
				print("  FAIL  ", label)
				for msg in failures:
					print("        ", msg)
	if _stray_cases > 0:
		print("(%d cases left nodes in the tree, which the runner freed: %s)" % [_stray_cases, str(_stray)])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


## Whether a test is asked for: every test when `only` is empty, else those whose label (`test_file:test_method`) contains one
## of the pieces of `--only=a,b,c` (a trailing colon on a file name is exactly that file).
func _wanted(label: String, only: PackedStringArray) -> bool:
	if only.is_empty():
		return true
	for piece in only:
		if label.contains(piece):
			return true
	return false


## Runs one test method on a fresh instance and returns its failure messages,
## plus one for any errors logged while it ran. Those errors are then taken
## back off the count, so a test that runs another case is judged on its own.
func run_case(script: GDScript, method: String) -> Array:
	var before := errors.count
	var case = script.new()
	var kids := root.get_children()
	await case.call(method)
	var failures: Array = case.failures.duplicate()
	failures.append_array(_leaks(kids))
	if errors.count > before:
		failures.append("%d error(s) logged while it ran" % (errors.count - before))
	errors.count = before
	return failures


## Finds the process-wide state in the game's scripts (see `_plain` and `_tables`): a `static var` of a plain value
## (a path, a flag, a number; a leading underscore marks a lazy cache and is left out) or of a Dictionary.
func _find_globals(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_find_globals(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		var path := dir.path_join(f)
		var plain: Array = []
		var tables: Array = []
		var callbacks: Array = []
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if not line.begins_with("static var "):
				continue
			var m := _plain_re.search(line)
			if m != null:
				plain.append(m.get_string(1))
				continue
			m = _table_re.search(line)
			if m != null:
				tables.append(m.get_string(1))
				continue
			m = _callback_re.search(line)
			if m != null:
				callbacks.append(m.get_string(1))
		if plain.is_empty() and tables.is_empty() and callbacks.is_empty():
			continue
		var script = load(path)
		for n in callbacks:
			_callbacks.append({"script": script, "name": n})
		for n in plain:
			_plain.append({"script": script, "name": n, "label": "%s.%s" % [f.get_basename(), n], "start": script.get(n)})
		for n in tables:
			_tables.append({"script": script, "name": n, "label": "%s.%s" % [f.get_basename(), n], "seen": {}})


## What a case left changed in the process-wide state, as failure messages; a plain setting is put back, so that the files
## after it read what they should (the failure names the case that left it, not the files that come later).
func _check_globals() -> Array:
	var out: Array = []
	for g in _callbacks:
		g.script.set(g.name, Callable())    # (cleared, not failed: the game sets them itself each time it starts)
	for g in _plain:
		var now = g.script.get(g.name)
		if now != g.start:
			out.append("left %s as %s (it was %s): a test puts back what it points elsewhere" % [g.label, str(now), str(g.start)])
			g.script.set(g.name, g.start)
	for g in _tables:
		var table: Dictionary = g.script.get(g.name)
		for k in table:
			if not (table[k] is Dictionary or table[k] is Array):
				continue    # (a cache of pictures and the like is refilled by a test that resets it, not edited)
			var h := hash(table[k])
			var was = g.seen.get(k)
			if was != null and is_same(was.ref, table[k]) and was.hash != h:
				out.append("changed the shared data %s[%s] in place: a test works on a copy (duplicate(true)) or puts it back" % [g.label, str(k).get_slice("|", 0)])
			g.seen[k] = {"ref": table[k], "hash": h}    # (an entry a test erased and read again is another thing, not an edit)
	return out


## What a case left that cannot stay for the files after it, as failure messages: a setting or a shared cache (`_check_globals`) and
## the engine's meta (the real game's `run`). What it left in the tree under the root (`kids` is what was there before: a world
## whose test never freed it, a screen) is freed here and counted (`_stray`), not failed: the old suites leave many, they do no
## harm once gone, and a screen left up would listen to the keys and clicks of every test after it.
func _leaks(kids: Array) -> Array:
	var out: Array = _check_globals()
	for k in Engine.get_meta_list():
		out.append("left the engine's meta %s set (%s): remove it when the test ends" % [k, str(Engine.get_meta(k)).left(60)])
		Engine.remove_meta(k)
	var stray := false
	for n in root.get_children():
		if not kids.has(n) and not n.is_queued_for_deletion():
			_stray[n.get_class()] = int(_stray.get(n.get_class(), 0)) + 1
			n.queue_free()
			stray = true
	_stray_cases += 1 if stray else 0
	return out
