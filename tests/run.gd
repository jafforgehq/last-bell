## Runs every test_* method in tests/test_*.gd and exits non-zero if any fail:
##   Godot --headless --path . --script res://tests/run.gd [-- --only=text]
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


func _initialize() -> void:
	Prefs.path = TEST_PREFS
	Prefs.reset()
	OS.add_logger(errors)
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var files: Array = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
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
			if not name.begins_with("test_") or (only != "" and not label.contains(only)):
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
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


## Runs one test method on a fresh instance and returns its failure messages,
## plus one for any errors logged while it ran. Those errors are then taken
## back off the count, so a test that runs another case is judged on its own.
func run_case(script: GDScript, method: String) -> Array:
	var before := errors.count
	var case = script.new()
	await case.call(method)
	var failures: Array = case.failures.duplicate()
	if errors.count > before:
		failures.append("%d error(s) logged while it ran" % (errors.count - before))
	errors.count = before
	return failures
