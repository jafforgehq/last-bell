## The audio buses: `Master`, and under it `SFX` (the one-shot sounds), `UI` (the
## menu sounds), `Ambience` (wind, crickets, the horde's moan) and `Music`. The project
## has no bus layout file, so the four are made at start-up; making them twice is
## harmless. Each bus's volume is a setting (`Prefs`, section `audio`: 0 to 1, a straight
## amplitude slider turned into decibels here); at 0 a bus is muted outright.
##
## The HUD's sound button is a separate switch: it mutes the Master bus too, and
## the two never undo each other (`Master` is muted while either one asks for it).
extends RefCounted

const Prefs := preload("res://scripts/prefs.gd")

## The buses made under Master, in the order they are made.
const NAMES := ["SFX", "UI", "Ambience", "Music"]
## The pref key of each bus (section `audio`).
const PREF_KEY := {"Master": "master", "SFX": "sfx", "UI": "ui", "Ambience": "ambience", "Music": "music"}
## What a volume of 0 is, in decibels, for the volume knob (the mute switch does the rest).
const SILENT_DB := -80.0

## The sound button in the HUD has the game muted.
static var hud_muted := false


## Makes the buses that are missing. Safe to call any number of times.
static func ensure() -> void:
	for bus_name in NAMES:
		if AudioServer.get_bus_index(bus_name) < 0:
			# The position is given outright (the end), never left to the default of -1: the web export's
			# sample-bus code takes the -1 as a slot, files every new bus in the wrong place and wires the
			# buses into a loop that never reaches the speakers (silence in a browser, Godot 4.7.2).
			AudioServer.add_bus(AudioServer.bus_count)
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")


## A volume from 0 to 1 as decibels: 1 is 0 dB, 0.5 about -6 dB, 0 is SILENT_DB.
static func to_db(volume: float) -> float:
	if volume <= 0.0001:
		return SILENT_DB
	return clampf(linear_to_db(minf(volume, 1.0)), SILENT_DB, 0.0)


## The volume the player has set for a bus (0 to 1; the default is 1).
static func volume_of(bus_name: String) -> float:
	return clampf(Prefs.number("audio", String(PREF_KEY.get(bus_name, "master"))), 0.0, 1.0)


## Sets one bus from the settings (and, for Master, from the HUD's mute switch).
static func apply(bus_name: String) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	var v := volume_of(bus_name)
	AudioServer.set_bus_volume_db(i, to_db(v))
	var mute := v <= 0.0
	if bus_name == "Master":
		mute = mute or hud_muted
	AudioServer.set_bus_mute(i, mute)


## Makes the buses and sets all five from the settings.
static func apply_all() -> void:
	ensure()
	for bus_name in ["Master"] + NAMES:
		apply(bus_name)


## The HUD's sound button.
static func set_hud_muted(muted: bool) -> void:
	hud_muted = muted
	apply("Master")


## Whether a bus is silent right now (muted, or its volume is at the floor).
static func is_silent(bus_name: String) -> bool:
	var i := AudioServer.get_bus_index(bus_name)
	return i < 0 or AudioServer.is_bus_mute(i) or AudioServer.get_bus_volume_db(i) <= SILENT_DB + 0.01
