## How the mouse aims (round 22, "Controls"): the setting `ui.aim_mode` and the rules that every view of the survivor's hands shares (the
## yard in scripts/main.gd, a place in scripts/raid/raid_scene.gd and the road in scripts/drive/drive_scene.gd). Pure: nothing here
## reads the engine's input state.
##
## "right" (the default, "Right button aims"): the pointer is a free arrow that clicks; the survivor faces the way they walk and keeps
##   their last facing when they stand still. While the RIGHT button is held (or SHIFT, for one hand on the keys) the survivor turns to the
##   pointer, the crosshair and the aim line show, and the LEFT button fires. A left click without it never fires and never turns the
##   survivor: it picks people and uses what the E prompt is on. The aim lets go the moment the pointer is over a HUD control, a menu or a
##   page, or leaves the window, and when the window loses the focus.
## "always" ("Always aim at the mouse", the way it was): the survivor aims at the pointer every frame and the left button fires anywhere in the
##   world; the pointer over the bare world is the crosshair.
##
## THE HOLSTER (round 23, "Orders"): Q puts the weapon away or draws it, in either mode (`holstered`, for the session: it is not a setting and it
## is not saved; every run, every place and every road begins with the weapon drawn). While it is put away nothing aims and nothing fires: no
## crosshair, no aim line, the right button does not aim, the left button only clicks, R reloads nothing (a toast says so), and F still swings (a
## shove). The pointer is the free arrow whatever the setting says (`mouse_aims`), and a right click TAPPED (pressed and let go within TAP_S,
## without moving) is an order by radio for the person picked: the ground is "Hold here" at that spot, a night post is "To the walls", another person
## "Come with me"; in a place a container is "Search that" and the exit "Go back". A tapped right click orders the same with the weapon drawn
## when somebody is picked (a hold longer than TAP_S is the aim, as ever).
extends RefCounted

const Prefs := preload("res://scripts/prefs.gd")

const RIGHT := "right"
const ALWAYS := "always"
const MODES := [RIGHT, ALWAYS]
## What the Settings screen calls them, and what each says in a line.
const LABELS := {RIGHT: "Right button aims", ALWAYS: "Always aim at the mouse"}
const NOTES := {
	RIGHT: "Right button or Shift aims, left click shoots; the pointer stays free. Q puts the weapon away: a right click then orders. Hold C for the command wheel.",
	ALWAYS: "The survivor aims at the mouse all the time; the left button fires. Q puts the weapon away: a right click then orders. Hold C for the command wheel.",
}


## The weapon is put away (Q). A session's own state: the runner of the tests puts it back after each case, a new run draws it.
static var holstered := false

## A right click is a tap (an order, not an aim) when it is let go within this many seconds of the press and the pointer has not moved more than
## TAP_PX pixels from where it went down.
const TAP_S := 0.25
const TAP_PX := 8.0

## What the views say about the weapon and the orders (one set of words for the yard, a place and the HUD's button).
const PUT_AWAY := "Weapon is put away: Q to draw it"
const NOW_AWAY := "Weapon put away (Q draws it): pick someone, then right click to order"
const NOW_DRAWN := "Weapon drawn: hold the right button to aim"
const NO_ONE := "Select someone first (click them), then right click to order"
const BUTTON_DRAWN := "Weapon: drawn (Q)"
const BUTTON_AWAY := "Weapon: put away (Q)"
const BUTTON_TIP_DRAWN := "The weapon is drawn: the right button aims and the left fires. Click to put it away (Q): then the right button gives orders to the person picked, with the pointer free"
const BUTTON_TIP_AWAY := "The weapon is put away: nothing aims or fires, F still shoves. Click to draw it (Q). With someone picked, a right click orders them: on the ground Hold here, on a night post To the walls, on a person Come with me"


## The mode now: `ui.aim_mode`, "right" for anything the file holds that is not one of the two.
static func current() -> String:
	var v = Prefs.get_value("ui", "aim_mode")
	if typeof(v) == TYPE_STRING and MODES.has(String(v)):
		return String(v)
	return RIGHT


## Whether the mouse aims all the time (the old way).
static func always() -> bool:
	return current() == ALWAYS


## Whether the mouse aims all the time: the setting "Always aim at the mouse", and the weapon is drawn. (The views that act on it ask this; the words
## of the help and the settings ask `always`.)
static func mouse_aims() -> bool:
	return current() == ALWAYS and not holstered


## Puts the weapon away or draws it. Returns whether it is put away now.
static func set_holstered(on: bool) -> bool:
	holstered = on
	return holstered


## Whether a right click that was held `held_s` seconds and moved the pointer `moved_px` pixels was a tap.
static func is_tap(held_s: float, moved_px: float) -> bool:
	return held_s >= 0.0 and held_s <= TAP_S and moved_px <= TAP_PX


static func set_mode(mode: String) -> void:
	Prefs.set_value("ui", "aim_mode", mode if MODES.has(mode) else RIGHT)


## Whether the survivor's hands are aiming: in "always" the pointer in the window (the caller says); in "right" the right button or Shift held
## while the pointer is on the bare world (not over a HUD control, a menu or a page, nor out of the window) and the hands are free.
static func aiming(mode: String, right_held: bool, shift_held: bool, pointer_ok: bool, hands_off: bool, over_hud: bool) -> bool:
	if holstered:
		return false    # (the weapon is put away: nothing is aimed)
	if mode == ALWAYS:
		return pointer_ok
	return (right_held or shift_held) and pointer_ok and not hands_off and not over_hud

