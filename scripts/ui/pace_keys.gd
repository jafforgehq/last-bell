## The hands of the RUN (One House, PACE): what the keys and the staging flag say about sprinting, kept out of main.gd (which asks three small questions of it). Static functions only.
##
## THE KEY is X (`Sprint.KEY`): Shift is the right button's twin for one hand on the keys (it AIMS), and Ctrl is a browser's (Ctrl+W closes the tab of the web build) and a command's everywhere, so the run has a key of its own
## near the WASD hand. It is held, not toggled. The run is asked for (`sim.avatar.set_sprint`) every frame, and only when the player's hands are free: not under a menu, a page or the order wheel, and not while the survivor AIMS
## (the right button or Shift held, with "Right button aims"); with "Always aim at the mouse" the pointer aims all the time, so the run is let through and lowers the gun instead (scripts/sim/sprint.gd). The rules say the rest
## (the town only; not while reloading, at a task or with the breath short).
## STAGING: `--sprint[=dx,dy]` holds the run key and walks her that way (east without a direction), so that a screenshot of the breath's arc has one.
extends RefCounted

const Sprint := preload("res://scripts/sim/sprint.gd")
const AimMode := preload("res://scripts/aim_mode.gd")

## The walk a screenshot holds (`--sprint`): ZERO for none.
static var staged := Vector2.ZERO


## `--sprint[=dx,dy]`: hold the run key and walk that way.
static func stage(v: String) -> void:
	var xy := v.split(",")
	if xy.size() == 2 and xy[0].is_valid_float() and xy[1].is_valid_float():
		staged = Vector2(float(xy[0]), float(xy[1])).normalized()
	else:
		staged = Vector2.RIGHT


## Whether the run key is asked for now: `main` is the game (`avatar_hands_off`, `aiming`, `_key_down`).
static func sprint_wanted(main) -> bool:
	if main.avatar_hands_off() or (main.wheel_ctl != null and main.wheel_ctl.busy()):
		return false
	if staged != Vector2.ZERO:
		return true
	return main._key_down(Sprint.KEY) and (AimMode.mouse_aims() or not main.aiming())
