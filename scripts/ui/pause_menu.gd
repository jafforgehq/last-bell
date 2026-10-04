## The pause menu (Esc with nothing selected): Resume, Save, Load, Settings, How to
## play, Skip tutorial (only while Orientation Day's coach is teaching, round 26), Main menu and Quit (not on the web). The game's rules stand still while it is
## open and go on at the speed they had when it closes (main.gd does that: it calls
## resume() when the shell tells it this screen is gone).
extends "res://scripts/ui/menu_screen.gd"

## The menu closed to show the controls: the game stays paused (the player reads the
## keys, then presses Space).
var keep_paused := false
## The menu lines by name: resume, save, load, settings, help, skip (in the lesson), menu, quit.
var items := {}


func _init() -> void:
	kind = "pause"
	max_w = 360.0


func _build_body() -> void:
	_add("resume", shell.menu_item("Resume", "", true, "Esc"), close)
	# (not in a place: the game keeps no state there, and the line says so)
	var no_save: String = shell.save_blocked()
	_add("save", shell.menu_item("Save", no_save if no_save != "" else "Quick save", false, "F5"), shell.save_game)
	if no_save != "":
		shell.set_item_enabled(items["save"], false)
		items["save"].tooltip_text = no_save
	_add("load", shell.menu_item("Load", "Pick a save"), shell.open_load.bind(true))
	_add("settings", shell.menu_item("Settings"), shell.open_settings)
	_add("help", shell.menu_item("How to play", "Every key and mouse button"), _help)
	if _skippable():
		_add("skip", shell.menu_item("Skip tutorial", "Orientation Day ends and the game goes on"), _skip_tutorial)
	_add("menu", shell.menu_item("Main menu"), _main_menu)
	if not shell.on_web():
		_add("quit", shell.menu_item("Quit"), _quit)


func _add(key: String, b: Button, action: Callable) -> void:
	b.pressed.connect(action)
	body.add_child(b)
	items[key] = b


func default_focus() -> Control:
	return items["resume"]


func _help() -> void:
	keep_paused = true
	close_sound = ""
	shell.show_help()
	close()


## Whether Orientation Day's coach is up and has a lesson left to skip (not on its last card).
func _skippable() -> bool:
	var game = shell.main
	var coach = game.get("coach") if game != null else null
	return coach != null and is_instance_valid(coach) and coach.phase != "wrap" and coach.phase != "ended" and game.has_method("skip_tutorial")


## Skip tutorial: the menu closes first (it gives back the speed it took), then the coach goes to its last card, "Skipped", where the game waits
## for Start a real run, Replay or Keep playing here.
func _skip_tutorial() -> void:
	close()
	shell.main.skip_tutorial()


func _main_menu() -> void:
	shell.confirm("Leave this game?", "Anything since your last save is lost.", "Main menu", func(): shell.main.show_title())


func _quit() -> void:
	shell.confirm("Quit the game?", "Anything since your last save is lost.", "Quit", func(): shell.quit_game())
