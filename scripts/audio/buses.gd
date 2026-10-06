## The audio buses: `Master` (with a hard limiter, so that the sum of the music and the guns never clips), and under it `SFX` (the
## one-shot sounds), `UI` (the menu sounds), `Ambience` (wind, crickets, the horde's moan) and `Music`; and `Distant`, which is sent
## to Ambience and has a low-pass and a reverb on it (a crow, a dog, a far gunshot: the sounds that are meant to be a long way
## off, scripts/audio/soundscape.gd). Its volume is Ambience's slider. They are
## defined in `res://default_bus_layout.tres`, which the project loads at start-up, and
## NOT made at run time: on the web export a bus made with `AudioServer.add_bus()` is
## filed in the wrong slot (the engine hands the web layer -1 whatever position is
## given) and the mix is wired into a loop that never reaches the speakers, so a browser
## heard nothing (measured with a Web Audio probe, 2026-10-02). `ensure()` only makes
## what is missing, for a run without the layout (a test, a stripped export); making them
## twice is harmless. Each bus's volume is a setting (`Prefs`, section `audio`: 0 to 1, a
## straight amplitude slider turned into decibels here); at 0 a bus is muted outright.
##
## The HUD's sound button is a separate switch: it mutes the Master bus too, and
## the two never undo each other (`Master` is muted while either one asks for it).
extends RefCounted

const Prefs := preload("res://scripts/prefs.gd")

## The buses made under Master, in the order they are made (`Distant` is made after them, under Ambience).
const NAMES := ["SFX", "UI", "Ambience", "Music"]
## The far-away bus: its name, where it is sent, and the filter on it.
const DISTANT := "Distant"
const DISTANT_CUTOFF_HZ := 3200.0
## The rain's bus (RAIN): the rain bed plays on it, sent to Ambience, with a low-pass that is open outdoors (OPEN_HZ) and closes to MUFFLED_HZ, and a few decibels quieter, with a roof
## overhead (`set_rain_muffle`, from scripts/render/rain_view.gd). In the layout, like the others.
const RAIN := "Rain"
const RAIN_OPEN_HZ := 20500.0
const RAIN_MUFFLED_HZ := 780.0
const RAIN_MUFFLED_DB := -4.5
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
			AudioServer.add_bus(AudioServer.bus_count)
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	if AudioServer.get_bus_index(DISTANT) < 0:
		AudioServer.add_bus(AudioServer.bus_count)
		var d := AudioServer.bus_count - 1
		AudioServer.set_bus_name(d, DISTANT)
		AudioServer.set_bus_send(d, "Ambience")
		var low := AudioEffectLowPassFilter.new()
		low.cutoff_hz = DISTANT_CUTOFF_HZ
		AudioServer.add_bus_effect(d, low)
		var room := AudioEffectReverb.new()
		room.room_size = 0.65
		room.damping = 0.7
		room.dry = 0.75
		room.wet = 0.3
		AudioServer.add_bus_effect(d, room)
	if AudioServer.get_bus_index(RAIN) < 0:
		AudioServer.add_bus(AudioServer.bus_count)
		var r := AudioServer.bus_count - 1
		AudioServer.set_bus_name(r, RAIN)
		AudioServer.set_bus_send(r, "Ambience")
		var open := AudioEffectLowPassFilter.new()
		open.cutoff_hz = RAIN_OPEN_HZ
		AudioServer.add_bus_effect(r, open)


## The bus the rain bed plays on: Rain, or Ambience when the layout has no such bus.
static func rain_bus() -> String:
	return RAIN if AudioServer.get_bus_index(RAIN) >= 0 else "Ambience"


## How shut in the rain is, 0 (outdoors: open) to 1 (under a roof: a low-pass at RAIN_MUFFLED_HZ and RAIN_MUFFLED_DB). A bus that is not there is left alone.
static func set_rain_muffle(k: float) -> void:
	var i := AudioServer.get_bus_index(RAIN)
	if i < 0:
		return
	k = clampf(k, 0.0, 1.0)
	AudioServer.set_bus_volume_db(i, RAIN_MUFFLED_DB * k)
	if AudioServer.get_bus_effect_count(i) > 0:
		var fx = AudioServer.get_bus_effect(i, 0)
		if fx is AudioEffectLowPassFilter:
			# (the cutoff falls by the octave, so the closing sounds even: a straight line in hertz would do nothing until the last quarter)
			fx.cutoff_hz = exp(lerpf(log(RAIN_OPEN_HZ), log(RAIN_MUFFLED_HZ), k))


## The bus the far-away sounds play on: Distant, or Ambience when the layout has no such bus.
static func far_bus() -> String:
	return DISTANT if AudioServer.get_bus_index(DISTANT) >= 0 else "Ambience"


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
