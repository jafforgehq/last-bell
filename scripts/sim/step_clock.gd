## The clock of the rules. It turns the frames' time into whole fixed steps of
## 1/30 s, so the rules take the same steps on every machine and at every frame
## rate (a seed plays the same game), and costs the same CPU at 60, 144 or 240
## frames a second. Drawing runs on frames and blends between the last two steps
## with alpha(). Nothing here knows about nodes: main.gd and the tests drive it.
extends RefCounted

## One step of the rules, in seconds of the rules' time.
const STEP := 1.0 / 30.0
## Most steps handed out for one frame. Past that the rest of the time is
## dropped: the game slows down instead of falling further and further behind.
const MAX_STEPS := 12
## A frame counts for at most this long (a stall, a window being dragged).
const MAX_FRAME := 0.1
## Rounding slack, in steps: nine frames of 1/270 s are one step, not 0.9999999999999998 of one.
const SLACK := 1e-6

var _acc := 0.0


## Adds one frame of `dt` real seconds at game `speed` and returns how many whole
## steps the rules should take now. Speed 0 takes none and leaves the clock as
## it was, so a paused game keeps drawing the same picture.
func advance(dt: float, speed: float) -> int:
	if speed <= 0.0:
		return 0
	_acc += clampf(dt, 0.0, MAX_FRAME) * speed
	var n := int(_acc / STEP + SLACK)
	if n > MAX_STEPS:
		_acc = 0.0
		return MAX_STEPS
	_acc = maxf(0.0, _acc - n * STEP)
	return n


## How far the time has run into the next step, 0 up to (not including) 1.
## Drawing puts everything that moves this far between its last two steps.
func alpha() -> float:
	return clampf(_acc / STEP, 0.0, 1.0 - SLACK)


## Forget the time that has not been spent yet (a new game was loaded).
func reset() -> void:
	_acc = 0.0
