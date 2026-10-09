## The card a save that cannot be continued gets (SAVE4): it is from an older version of the game (or of its town: the same seed would make other houses and other dead), or it is
## damaged. Nothing is loaded and nothing is thrown away: the game under it (the title, or the pause menu over the run) stays as it is. Two ways on: New game, or Close.
## Opened by `Shell.open_old_save(reason)`: from the Load page, Continue, F9 and a `--load=` file at the start (the title stays up under it).
extends "res://scripts/ui/menu_screen.gd"

## Why: "older" or "newer" (the save is from another version of the game), "damaged" (it cannot be read) or "missing" (the file is not there).
var reason := "older"
var new_button: Button
var close_button: Button

const WORDS := {
	"older": "This save is from an older version of Last Bell and cannot be continued. Start a new game.",
	"newer": "This save is from a newer version of Last Bell and cannot be continued here. Start a new game.",
	"damaged": "This save is damaged and cannot be continued. Start a new game.",
	"missing": "There is no save there to continue. Start a new game.",
}
const HEADINGS := {
	"older": "Save from an older version",
	"newer": "Save from a newer version",
	"damaged": "Save damaged",
	"missing": "No save there",
}


func _init() -> void:
	kind = "old_save"
	max_w = 440.0


## The heading for `why` (the shell makes the screen with it).
static func heading(why: String) -> String:
	return String(HEADINGS.get(why, HEADINGS["older"]))


## The card's words for `why`.
static func words(why: String) -> String:
	return String(WORDS.get(why, WORDS["older"]))


func _build_body() -> void:
	body.add_child(note(words(reason), ink(), 15))


func _build_foot() -> void:
	close_button = button("Close", false)
	close_button.pressed.connect(close)
	foot.add_child(close_button)
	new_button = button("New game", true)
	new_button.pressed.connect(_new_game)
	foot.add_child(new_button)


func default_focus() -> Control:
	return new_button


## New game: the card goes and the New game screen comes up in its place (over the title, or over the pause menu of the game that is running: it begins nothing by itself).
func _new_game() -> void:
	close_sound = ""
	var s = shell
	close()
	s.open_new_game()
