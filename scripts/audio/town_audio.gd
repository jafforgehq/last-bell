## The town's sound (One House, WP7): what the music is told about the town, and the few sounds the new loop needs that the school never had. A VIEW PART of the
## town's facade (`on_ready(main)`, `on_event(e)`, `music_context(ctx)`); it makes no sound of its own accord and writes nothing in the rules (the golden tests' promise).
##
## MUSIC (scripts/audio/music.gd: it knows no map; main.gd `_music_context()` hands over the school's answers, this part corrects them for the town):
##   `indoors`   the avatar is inside a house (`sim.houses.house_at`), not whatever the school's floor-name test finds (the town's floors are the generator's)
##   `fortress`  true ONLY while `sim.scenario.attacks_on()` and it is dusk or night: the fourth rescue has called the dead and they are at the fortified house.
##               Before that the nights are the quiet score of the night outside, however many wanderers there are (the school's "Big Night" test is false in the town)
##   `phase`, `progress`, `over` are main's own and are left alone.
## SOUNDS, from the files the game already has (assets/audio): a door opening or closing as the avatar comes in and goes out of a house or looks into a room, a rummage
## when a container is searched, two bell chimes and a thud when a house is claimed (the doors are barred), one chime when a house is cleared, the warm stinger of the
## music and a chime when someone joins. They go through `sound.play` (the SFX bus) and the soundscape's bell (`sound.scape.ring`), so the sound button, the sliders and
## the music's ducking all apply. A file that is not there is skipped.
extends RefCounted

const MUSIC := preload("res://scripts/audio/music.gd")

## The town's own names for sounds made of files that exist (`sound.streams[name]`).
const FILES := {
	"town_door_open": ["res://assets/audio/door_open_0.wav"],
	"town_door_close": ["res://assets/audio/door_close_0.wav"],
	"town_rummage": ["res://assets/audio/scrape_wood_0.wav", "res://assets/audio/scrape_wood_1.wav", "res://assets/audio/creak_0.wav", "res://assets/audio/creak_1.wav"],
	"town_thud": ["res://assets/audio/thud_0.wav", "res://assets/audio/thud_1.wav"],
}
## Two door sounds closer than this (milliseconds of real time) are one: entering a house also reveals its room.
const DOOR_GAP_MS := 450
const DOOR_LEVEL := 0.55
const RUMMAGE_LEVEL := 0.7

var main
var sound
var played: Array = []
var _door_ms := -10000


func on_ready(main_node) -> void:
	main = main_node
	sound = main.get("sound")
	if sound == null or sound.get("streams") == null:
		return
	for name in FILES:
		var list: Array = []
		for path in FILES[name]:
			if ResourceLoader.exists(path):
				var s = load(path)
				if s != null:
					list.append(s)
		if not list.is_empty():
			sound.streams[name] = list


func _sim():
	return main.get("sim") if main != null else null


# ------------------------------------------------------------------------- music --

## main.gd's context for the music, corrected for the town (see the header). Changes `ctx` in place and returns it.
func music_context(ctx: Dictionary) -> Dictionary:
	var sim = _sim()
	if sim == null:
		return ctx
	var phase := String(ctx.get("phase", sim.phase if sim.get("phase") != null else ""))
	var houses = sim.get("houses")
	var me = sim.avatar.player() if sim.get("avatar") != null else null
	if houses != null and me != null and houses.has_method("house_at"):
		ctx["indoors"] = houses.house_at(me.x, me.y) >= 0
	var scenario = sim.get("scenario")
	var attacks: bool = scenario != null and scenario.has_method("attacks_on") and bool(scenario.attacks_on())
	ctx["fortress"] = attacks and (phase == "dusk" or phase == "night")
	return ctx


# ------------------------------------------------------------------------- events --

func on_event(e: Dictionary) -> void:
	if sound == null:
		return
	match String(e.get("type", "")):
		"entered":
			_door("town_door_open")
		"left":
			_door("town_door_close")
		"room_revealed":
			_door("town_door_open")
		"searched":
			_play("town_rummage", RUMMAGE_LEVEL)
		"house_clear":
			_chime(1.0)
			_ui("ui_notify", 0.7)
		"claimed":
			_ui("ui_confirm", 0.9)
			_chime(1.0)
			_later(0.45, func(): _chime(0.8))
			_later(0.2, func(): _play("town_thud", 0.9))
		"rescue_joined":
			_chime(1.0)
			_notify("rescue")


## What was played lately (the last few), for the tests.
func _log(name: String) -> void:
	played.append(name)
	if played.size() > 32:
		played.pop_front()


func _door(name: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _door_ms < DOOR_GAP_MS:
		return
	_door_ms = now
	_play(name, DOOR_LEVEL)


func _play(name: String, level: float) -> void:
	if sound == null or not sound.has_method("play") or sound.get("streams") == null or not sound.streams.has(name):
		return
	_log(name)
	sound.play(name, level)


func _ui(name: String, level: float) -> void:
	if sound != null and sound.has_method("ui"):
		_log(name)
		sound.ui(name, level)


func _chime(level: float) -> void:
	var scape = sound.get("scape") if sound != null else null
	if scape != null and scape.has_method("ring"):
		_log("chime")
		scape.ring("chime", level)


func _later(seconds: float, what: Callable) -> void:
	var scape = sound.get("scape") if sound != null else null
	if scape != null and scape.has_method("schedule"):
		scape.schedule(seconds, what)


## The music's: a stinger for a rescue (and the dips under it), through the game's own music if main has it, else the shared one.
func _notify(kind: String) -> void:
	var m = main.get("music") if main != null else null
	if m == null:
		m = MUSIC.current()
	if m != null and m.has_method("notify"):
		_log("music:" + kind)
		m.notify(kind)
