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
const RAIN_MUFFLED_HZ := 1300.0
const RAIN_MUFFLED_DB := -1.5
## The category buses of the SOUND pass (docs/audio-mix.md), both sent to SFX, so that the Effects slider, the HUD's switch and the music's sidechain still see them: `Steps` (the footsteps of Ruth, the
## crew and the dead) and `Voices` (the dead's groans, growls, hiss and screech, the brute's, Ruth's pain and breath). In the layout, like the others; they have a fixed trim (TRIM_DB) and no slider of their own.
const STEPS := "Steps"
const VOICES := "Voices"
const CATEGORY_BUSES := ["Steps", "Voices"]
## THE MIX'S TRIMS (decibels, added to the bus's volume: the player's slider is 0 dB at 1.0 and goes down from there). Measured at the master with tools/mix_probe.gd and written in docs/audio-mix.md:
## SFX is the reference (a shot in the open is -12.8 LUFS at the master); the other categories are set against it. Steps: the footsteps' files are -33 to -26 LUFS and a step is a quiet sound.
## Voices: a positional voice loses 3 dB at the middle of the pan and falls off with the distance, so the bus gives 9 dB back (a groan at 3 tiles is -16 LUFS). Rain is the rain bed's own (see RAIN_TRIM_DB).
const TRIM_DB := {"SFX": 0.0, "UI": 0.0, "Ambience": 0.0, "Music": 0.0, "Steps": 2.5, "Voices": 9.0}
## Rain: the bed (the loop is -31 LUFS mono, -28 at the master; the storm plays it 4.7 dB louder) is lifted half a decibel so that a storm (-20.4 LUFS at the master) sits 7 LU under the gun and
## 4 under the near voices, inside the 3 to 8 that gunfire and voices are to keep over it (docs/audio-mix.md).
const RAIN_TRIM_DB := 0.5
## The Ambience bus ducks (a few decibels) while the SFX bus is loud, as the music does (music.gd `_update_duck`): a dip taken at once and let go slowly.
const AMB_DUCK_FLOOR_DB := -12.0
const AMB_DUCK_SLOPE := 0.33
const AMB_DUCK_MAX_DB := 2.5
## The pref key of each bus (section `audio`).
const PREF_KEY := {"Master": "master", "SFX": "sfx", "UI": "ui", "Ambience": "ambience", "Music": "music"}
## What a volume of 0 is, in decibels, for the volume knob (the mute switch does the rest).
const SILENT_DB := -80.0

## The sound button in the HUD has the game muted.
static var hud_muted := false
## The dips now (bus name -> decibels, 0 or less).
static var _duck := {}


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
	for cat in CATEGORY_BUSES:
		if AudioServer.get_bus_index(cat) < 0:
			AudioServer.add_bus(AudioServer.bus_count)
			var c := AudioServer.bus_count - 1
			AudioServer.set_bus_name(c, cat)
			AudioServer.set_bus_send(c, "SFX")
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
	AudioServer.set_bus_volume_db(i, RAIN_TRIM_DB + RAIN_MUFFLED_DB * k)
	if AudioServer.get_bus_effect_count(i) > 0:
		var fx = AudioServer.get_bus_effect(i, 0)
		if fx is AudioEffectLowPassFilter:
			# (the cutoff falls by the octave, so the closing sounds even: a straight line in hertz would do nothing until the last quarter)
			fx.cutoff_hz = exp(lerpf(log(RAIN_OPEN_HZ), log(RAIN_MUFFLED_HZ), k))


## The bus a category plays on (Steps, Voices): itself, or SFX when the layout has no such bus.
static func category_bus(name: String) -> String:
	return name if AudioServer.get_bus_index(name) >= 0 else "SFX"


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
	AudioServer.set_bus_volume_db(i, to_db(v) + (float(TRIM_DB.get(bus_name, 0.0)) + float(_duck.get(bus_name, 0.0)) if v > 0.0001 else 0.0))
	var mute := v <= 0.0
	if bus_name == "Master":
		mute = mute or hud_muted
	AudioServer.set_bus_mute(i, mute)


## Makes the buses and sets all five from the settings (and the fixed trims of the category buses).
static func apply_all() -> void:
	ensure()
	for bus_name in ["Master"] + NAMES:
		apply(bus_name)
	apply_trims()


## The category buses' trims (they have no slider: the SFX one governs them).
static func apply_trims() -> void:
	for bus_name in CATEGORY_BUSES:
		var i := AudioServer.get_bus_index(bus_name)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, float(TRIM_DB.get(bus_name, 0.0)))


## A dip of `db` (0 or less) on a bus that the sliders set (Ambience): the player's volume and the trim stay, the dip comes off them. Called every frame by scripts/audio/soundscape.gd.
static func set_duck(bus_name: String, db: float) -> void:
	var d := minf(db, 0.0)
	if is_equal_approx(float(_duck.get(bus_name, 0.0)), d):
		return
	_duck[bus_name] = d
	apply(bus_name)


## The dip the Ambience bus wants now for the SFX bus's loudest recent sample (`peak_db`, dBFS): AMB_DUCK_SLOPE decibels for each decibel over AMB_DUCK_FLOOR_DB, at most AMB_DUCK_MAX_DB.
static func ambience_duck_for(peak_db: float) -> float:
	return -clampf((peak_db - AMB_DUCK_FLOOR_DB) * AMB_DUCK_SLOPE, 0.0, AMB_DUCK_MAX_DB)


## The HUD's sound button.
static func set_hud_muted(muted: bool) -> void:
	hud_muted = muted
	apply("Master")


## Whether a bus is silent right now (muted, or its volume is at the floor).
static func is_silent(bus_name: String) -> bool:
	var i := AudioServer.get_bus_index(bus_name)
	return i < 0 or AudioServer.is_bus_mute(i) or AudioServer.get_bus_volume_db(i) <= SILENT_DB + 0.01
