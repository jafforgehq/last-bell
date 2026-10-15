extends "res://tests/case.gd"
## What the player keeps between runs (settings and a few facts) in a small text
## file in the user folder.

const Prefs := preload("res://scripts/prefs.gd")

const TEST_PATH := "user://prefs_test.cfg"


func _fresh() -> void:
	Prefs.path = TEST_PATH
	Prefs.reset()


func test_nothing_stored_gives_the_defaults() -> void:
	_fresh()
	near(float(Prefs.get_value("audio", "master")), 1.0, 0.0001, "full volume")
	near(float(Prefs.get_value("ui", "scale")), 1.0, 0.0001, "normal size")
	eq(Prefs.get_value("ui", "hints"), true, "hints on")
	eq(Prefs.flag("tutorial_done"), false, "the tutorial is not done")
	eq(Prefs.get_value("audio", "nonsense", 7), 7, "an unknown key gives the caller's default")
	eq(Prefs.get_value("audio", "nonsense"), null, "or nothing")


func test_a_value_is_kept_in_the_file() -> void:
	_fresh()
	Prefs.set_value("audio", "master", 0.4)
	Prefs.set_flag("tutorial_done")
	Prefs.forget()
	near(float(Prefs.get_value("audio", "master")), 0.4, 0.0001, "the volume survives a reload from the file")
	eq(Prefs.flag("tutorial_done"), true, "and so does the flag")
	eq(Prefs.flag("tutorial_offered"), false, "another flag is untouched")
	Prefs.set_flag("tutorial_done", false)
	Prefs.forget()
	eq(Prefs.flag("tutorial_done"), false, "a flag can be cleared")


func test_a_missing_file_is_not_an_error() -> void:
	Prefs.path = "user://prefs_that_was_never_written.cfg"
	Prefs.forget()
	near(float(Prefs.get_value("audio", "sfx")), 1.0, 0.0001, "the defaults")
	Prefs.path = TEST_PATH
	Prefs.forget()


func test_helpers_read_numbers_and_switches() -> void:
	_fresh()
	Prefs.set_value("ui", "scale", 1.25)
	Prefs.set_value("ui", "reduce_motion", true)
	near(Prefs.number("ui", "scale"), 1.25, 0.0001, "a number")
	eq(Prefs.on("ui", "reduce_motion"), true, "a switch")
	eq(Prefs.on("ui", "fullscreen"), false, "a switch that is off by default")
	Prefs.set_value("ui", "scale", "wide")
	near(Prefs.number("ui", "scale"), 1.0, 0.0001, "a value of the wrong kind falls back to the default")
	_fresh()


func test_screen_shake_defaults_to_full_and_is_clamped() -> void:
	const Access := preload("res://scripts/access.gd")
	_fresh()
	near(Access.shake_k(), 1.0, 0.0001, "full shake by default")
	Prefs.set_value("ui", "shake", 0.25)
	near(Access.shake_k(), 0.25, 0.0001, "a quarter")
	Prefs.set_value("ui", "shake", 7.0)
	near(Access.shake_k(), 1.0, 0.0001, "never more than all of it")
	_fresh()
