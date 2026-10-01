## Shared by the menu tests (tests/test_menus_*.gd; this file has no test_ prefix so the
## runner skips it): a stand-in for the game's main node that writes down what the menus
## ask of it, a sound node that writes down what it is asked to play, a shell built inside
## a window of a given size, save files of the tests' own, and key presses.
extends RefCounted

const Kit := preload("res://tests/hud_kit.gd")
const Helpers := preload("res://tests/helpers.gd")
const Shell := preload("res://scripts/ui/shell.gd")
const Prefs := preload("res://scripts/prefs.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


class FakeSound:
	extends Node
	var played: Array = []
	var ui_played: Array = []

	func ui(sound_name: String, _level: float = 1.0, _pitch_var: float = 0.02) -> void:
		ui_played.append(sound_name)

	func play(sound_name: String, _level: float = 1.0, _pitch_var: float = 0.04, _pitch_scale: float = 1.0) -> void:
		played.append(sound_name)


## What the menus call on the game, without Orientation Day (a build that has none yet).
class FakeMain:
	extends Node
	var calls: Array = []
	var sound
	var sim = null
	var save_ok := true
	var load_ok := true
	var scale_now := 1.0

	func _init() -> void:
		sound = FakeSound.new()
		add_child(sound)

	func start_run(difficulty: int, seed_value: int) -> void:
		calls.append(["start_run", difficulty, seed_value])

	func load_run(path: String) -> bool:
		calls.append(["load_run", path])
		return load_ok

	func show_title() -> void:
		calls.append(["show_title"])

	func quick_save() -> bool:
		calls.append(["quick_save"])
		return save_ok

	func quit_game() -> void:
		calls.append(["quit"])

	func resume(keep_paused: bool = false) -> void:
		calls.append(["resume", keep_paused])

	func apply_settings() -> void:
		calls.append(["apply_settings"])

	func ui_scale_in_use() -> float:
		return scale_now

	## The names of the calls so far, in order.
	func names() -> Array:
		var out: Array = []
		for c in calls:
			out.append(c[0])
		return out

	## The last call with this name, or [].
	func last(call_name: String) -> Array:
		for i in range(calls.size() - 1, -1, -1):
			if calls[i][0] == call_name:
				return calls[i]
		return []


## The same, with Orientation Day.
class FakeMainWithTutorial:
	extends FakeMain

	func start_tutorial() -> void:
		calls.append(["start_tutorial"])


## {"shell", "main", "sound", "hud", "holder", "sim", "paths"...}: a shell over the HUD kit's window of
## this size, its saves pointed at files of the test's own (nothing in them), and the first-launch card
## already taken as offered (a test about it clears the flag again).
static func build(width: int = 1280, height: int = 800, with_tutorial: bool = true) -> Dictionary:
	Prefs.path = "user://prefs_test.cfg"
	Prefs.reset()
	Prefs.set_flag("tutorial_offered")
	var ctx := Kit.build(width, height)
	var main = (FakeMainWithTutorial if with_tutorial else FakeMain).new()
	Engine.get_main_loop().root.add_child(main)
	var shell = Shell.new()
	ctx.holder.add_child(shell)
	shell.setup(main, ctx.hud)
	var paths := slot_paths("shell")
	set_slots(shell, paths)
	ctx["shell"] = shell
	ctx["main"] = main
	ctx["sound"] = main.sound
	ctx["paths"] = paths
	return ctx


static func free_all(ctx: Dictionary) -> void:
	clean(ctx.get("paths", []))
	ctx.main.free()
	Kit.free_all(ctx)
	Prefs.reset()


# ----------------------------------------------------------------- saves --

static func slot_paths(tag: String) -> Array:
	var pid := OS.get_process_id()
	return ["user://test_menu_%s_a_%d.json" % [tag, pid], "user://test_menu_%s_b_%d.json" % [tag, pid]]


static func set_slots(shell, paths: Array) -> void:
	shell.slots = [
		{"path": paths[0], "name": "Autosave", "note": "Written at each dawn"},
		{"path": paths[1], "name": "Quick save", "note": "F5 saves, F9 loads"},
	]


## Writes a real save of a run on this day at this hour (and difficulty), with `dead` of the six gone.
static func write_save(path: String, day: int = 3, hour: float = 14.5, difficulty: int = 1, dead: int = 0) -> bool:
	var g := Helpers.make(5, difficulty)
	g.sim.day = day
	g.sim.minutes = hour * 60.0
	g.sim.phase = g.sim.phase_at(g.sim.minutes)
	for i in dead:
		g.sim.people[i].dead = true
	var ok: bool = SaveGame.write(g.sim, path)
	g.world.free()
	return ok


static func write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


static func clean(paths: Array) -> void:
	for p in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ----------------------------------------------------------------- input --

## A key press (and release) sent to the window, the way a keyboard would.
static func key(code: Key) -> void:
	var root: Window = Engine.get_main_loop().root
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev, true)


## What has the keyboard now, or null.
static func focused() -> Control:
	return Engine.get_main_loop().root.gui_get_focus_owner()


# ------------------------------------------------------------- the game --

## The real game scene on a fixed run (the meta says which: {"difficulty", "seed"}, {"title": true}...),
## in the tree, its own per-frame work off (the tests drive `_process` by hand). The window it changed
## is put back by `leave`.
static func game(meta: Dictionary) -> Dictionary:
	var win: Window = Engine.get_main_loop().root
	var saved := {"size": win.size, "position": win.position, "mode": win.content_scale_mode, "aspect": win.content_scale_aspect, "scale_size": win.content_scale_size}
	Engine.set_meta("run", meta)
	var main = load("res://scenes/main.tscn").instantiate()
	win.add_child(main)
	main.set_process(false)
	return {"main": main, "window": saved}


static func leave(g: Dictionary) -> void:
	g.main.queue_free()
	await Engine.get_main_loop().process_frame
	var win: Window = Engine.get_main_loop().root
	var saved: Dictionary = g.window
	win.content_scale_mode = saved.mode
	win.content_scale_aspect = saved.aspect
	win.content_scale_size = saved.scale_size
	win.size = saved.size
	win.position = saved.position
	Prefs.reset()
