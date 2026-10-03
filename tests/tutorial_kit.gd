## Shared by the Orientation Day tests (tests/test_tutorial*.gd; this file has no test_
## prefix so the runner skips it): a headless game with the tutorial scenario installed,
## and small helpers for the games the tests build.
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")
const Prefs := preload("res://scripts/prefs.gd")


## {"sim", "world", "data", "scenario"}: Orientation Day, begun (day 1, 07:00, Story, its
## fixed seed). Free `world` when the test is done.
static func make() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	var scenario = Orientation.begin(sim)
	return {"sim": sim, "world": world, "data": data, "scenario": scenario}


## {"sim", "world", "data", "scenario"}: the avatar's Orientation Day, begun (as `make`, with the town on and Ruth the player), the
## way main.gd makes it. Free `world` when the test is done.
static func make_avatar() -> Dictionary:
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	var scenario = Orientation.begin(sim, true)
	sim.avatar.set_player("ruth")
	return {"sim": sim, "world": world, "data": data, "scenario": scenario}


static func person(sim, id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


## Steps the rules for `seconds` of the rules' time.
static func run(sim, seconds: float) -> void:
	for i in int(seconds * 30.0):
		sim.update(1.0 / 30.0)


## Steps the rules until the game clock (minutes since 07:00 on day 1) reaches `minutes`.
static func run_to_clock(sim, minutes: float) -> void:
	var guard := 0
	while sim.clock_min < minutes and guard < 200000:
		sim.update(1.0 / 30.0)
		guard += 1


## How many of the dead that are not drifting back to the city are about.
static func living_dead(sim) -> int:
	var n := 0
	for z in sim.zombies:
		if z.state != "dead" and z.state != "dying" and z.state != "retreat":
			n += 1
	return n


## A state of the game as one line, to compare two runs.
static func fingerprint(sim) -> String:
	var line := "%d|%.3f|%d|%.3f|%.3f|%.3f|%.3f|%.3f" % [sim.zombies.size(), sim.clock_min, sim.kills, sim.stock.ammo, sim.stock.scrap, sim.stock.food, sim.stock.water, sim.stock.meds]
	for p in sim.people:
		line += "|%.3f,%.3f,%.2f" % [p.x, p.y, p.hp]
	for s in sim.segments:
		line += "|%.2f" % s.hp
	return line


## Points the preferences at a file of the test's own and empties it, so a test never
## touches the real one.
static func use_test_prefs() -> void:
	Prefs.path = "user://prefs_test.cfg"
	Prefs.forget()
	Prefs.reset()


## Puts the preferences back where they belong.
static func restore_prefs() -> void:
	Prefs.path = Prefs.DEFAULT_PATH
	Prefs.forget()


# ----------------------------------------------------------- the real game --

## The window as the tests found it, to put back (the game scene fits and scales it).
static var _window := {}
static var _tutorial_save := ""


## The real game scene as the classic Orientation Day (the old yard: no avatar, assets/data/tutorial_classic.json; what `--noavatar`
## and the tests of the old controls play), from step `step`, in a window of `width` x `height`,
## with the preferences and the tutorial's save file pointed at files of the test's own. Its own
## per-frame work is switched off: the tests drive `_process` by hand (see `frames`). Give it back
## with `leave`.
static func game(step: int = 0, width: int = 1280, height: int = 800) -> Node:
	return start({"tutorial": true, "step": step}, width, height)


## The real game scene as the avatar's Orientation Day (what a player gets from the title: Ruth is the player, the town is on, the
## coach teaches from assets/data/tutorial.json), from step `step`, as `game` has it otherwise.
static func avatar_game(step: int = 0, width: int = 1280, height: int = 800) -> Node:
	return start({"tutorial": true, "step": step, "avatar": true}, width, height)


## The real game scene for the run the choice `meta` asks for ({"tutorial": true, ...}, {"load":
## path}, {"difficulty": 1, "seed": 5}), set up like `game`.
static func start(meta: Dictionary, width: int = 1280, height: int = 800) -> Node:
	use_test_prefs()
	var win: Window = Engine.get_main_loop().root
	_window = {"size": win.size, "position": win.position, "mode": win.content_scale_mode, "aspect": win.content_scale_aspect, "scale_size": win.content_scale_size}
	Engine.set_meta("run", meta)
	var main = load("res://scenes/main.tscn").instantiate()
	_tutorial_save = "user://tutorial_save_test_%d.json" % OS.get_process_id()
	main.tutorial_save_path = _tutorial_save
	win.add_child(main)
	main.set_process(false)
	resize(width, height)
	return main


## The window set to this size, with nothing scaling it (so the HUD is laid out for exactly it).
static func resize(width: int, height: int) -> void:
	var win: Window = Engine.get_main_loop().root
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.size = Vector2i(width, height)


## The game given back: freed, the window and the preferences as they were, the test's save gone
## (unless `keep_save`: a test that loads it next).
static func leave(main: Node, keep_save: bool = false) -> void:
	main.queue_free()
	await Engine.get_main_loop().process_frame
	var win: Window = Engine.get_main_loop().root
	win.content_scale_mode = _window.mode
	win.content_scale_aspect = _window.aspect
	win.content_scale_size = _window.scale_size
	win.size = _window.size
	win.position = _window.position
	restore_prefs()
	if _tutorial_save != "" and not keep_save and FileAccess.file_exists(_tutorial_save):
		OS.move_to_trash(ProjectSettings.globalize_path(_tutorial_save))
	if not keep_save:
		_tutorial_save = ""
	if Engine.has_meta("run"):
		Engine.remove_meta("run")


## Drives the game's frame `n` times at `dt` seconds each, and lets the containers settle on
## the engine's own frames now and then (the cards and buttons get their sizes a frame late).
static func frames(main: Node, n: int, dt: float = 1.0 / 30.0, every: int = 6) -> void:
	var tree := Engine.get_main_loop()
	for i in n:
		main._process(dt)
		if i % every == every - 1:
			await tree.process_frame
	await tree.process_frame


## Lets the layout settle after something changed (a card's words, a selection).
static func settle() -> void:
	var tree := Engine.get_main_loop()
	await tree.process_frame
	await tree.process_frame
