## Puts the storyteller's cards in front of the player. main.gd builds one over the HUD and tells it
## the storyteller's events (`on_story_card`, `on_dawn_report`) and the alerts that were clicked
## (`on_alert`):
##   - the radio card (radio_card.gd) is a modal: the rules are paused while it is up and the speed
##     comes back after, as for the scavenging dialog. Put off with Esc, it stays pending and the
##     alert `story` opens it again; a card left pending by a save is opened when the game starts.
##   - the dawn card (dawn_card.gd) is only shown: the game goes on under it; the alert `dawn` brings
##     it back.
## While the title, a menu, the scavenging dialog or the game-over page is up the cards wait their turn.
extends Node

const RadioCard := preload("res://scripts/ui/radio_card.gd")
const DawnCard := preload("res://scripts/ui/dawn_card.gd")
const GD := preload("res://scripts/game_data.gd")

const RADIO_ICON := "res://assets/ui/icons/radio.png"
## The sign that says "Day 8" is up for about this long (real seconds) at the dawn: the assembly waits for it.
const DAWN_WAIT := 4.6

var hud
var sim
## The cards that are up now, or null.
var radio = null
var dawn = null
## Asks the game whether a menu (or the title) has the screen, and how fast it runs: set by main.gd.
## Unset: nothing has the screen, and the HUD's own idea of the speed is used.
var blocked: Callable
var speed_of: Callable
## Plays one of the menu sounds: called with its name and a level (set by main.gd; unset: silence).
var ui_sound: Callable
var _paused := false
var _speed_before := 0
var _radio_wanted := false
var _dawn_wanted := false
var _dawn_wait := 0.0


func setup(hud_node, sim_node) -> void:
	hud = hud_node
	sim = sim_node
	# the radio's picture is not one of the baked icons: the HUD gets it from here
	if hud.get("icons") is Dictionary and not hud.icons.has("radio") and ResourceLoader.exists(RADIO_ICON):
		hud.icons["radio"] = GD.tex(RADIO_ICON)
	# a card left pending by a save
	_radio_wanted = not sim.storyteller.pending().is_empty()


## The storyteller has a card up: the page opens (as soon as nothing else is in the way).
func on_story_card() -> void:
	_radio_wanted = true
	_try_open()


## The assembly is ready: the card is shown.
func on_dawn_report() -> void:
	_dawn_wanted = true
	_dawn_wait = DAWN_WAIT
	_try_open()


## An alert of the feed was clicked: `story` opens the radio card again, `dawn` the assembly. True if
## it was one of these (the camera has nowhere to go for them).
func on_alert(id: String) -> bool:
	if id == "story":
		if not sim.storyteller.pending().is_empty():
			_radio_wanted = true
			_try_open()
		return true
	if id == "dawn":
		show_dawn()
		return true
	return false


## Shows the last assembly again.
func show_dawn() -> void:
	if sim.storyteller.report().is_empty():
		return
	_dawn_wanted = true
	_dawn_wait = 0.0
	_try_open()


func _process(dt: float) -> void:
	if sim == null:
		return
	_dawn_wait = maxf(0.0, _dawn_wait - dt)
	if radio != null and sim.over != "":
		radio.put_away()
	_try_open()


func _blocked() -> bool:
	if hud.get("scavenge_dialog") != null or hud.get("game_over") != null:
		return true
	return blocked.is_valid() and bool(blocked.call())


func _try_open() -> void:
	if sim == null or hud == null or _blocked():
		return
	if _radio_wanted and radio == null:
		_open_radio()
	elif _dawn_wanted and dawn == null and radio == null and _dawn_wait <= 0.0:
		_open_dawn()


func _open_radio() -> void:
	_radio_wanted = false
	if sim.storyteller.pending().is_empty() or sim.over != "":
		return
	var card := RadioCard.new()
	radio = card
	hud.add_child(card)
	card.closed.connect(_on_radio_closed)
	card.setup(hud, sim)
	_play("ui_open")
	# the rules wait for the answer (and the speed comes back after), as for the scavenging dialog
	var speed: int = int(speed_of.call()) if speed_of.is_valid() else int(hud.get("last_speed"))
	_paused = speed > 0 and hud.on_speed.is_valid()
	_speed_before = speed
	if _paused:
		hud.on_speed.call(0)


func _on_radio_closed(answered: bool) -> void:
	radio = null
	_play("ui_confirm" if answered else "ui_close")
	if _paused and hud.on_speed.is_valid():
		hud.on_speed.call(_speed_before)
	_paused = false


func _open_dawn() -> void:
	_dawn_wanted = false
	var report: Dictionary = sim.storyteller.report()
	if report.is_empty():
		return
	var card := DawnCard.new()
	dawn = card
	hud.add_child(card)
	card.closed.connect(func(): dawn = null)
	card.setup(hud, report)
	_play("ui_open", 0.6)


func _play(sound_name: String, level: float = 1.0) -> void:
	if ui_sound.is_valid():
		ui_sound.call(sound_name, level)
