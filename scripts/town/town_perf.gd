## What the town does to stay fast (One House, WP9): the platform's caps in one place, and the adaptive cap that keeps a slow machine playable.
##
## CAPS (static: nothing here holds state, so a test or a tool can ask without making anything):
##   `active_cap()`      the most real dead awake at once: 60 on a desktop, 40 in a browser (`OS.has_feature("web")`: the single-threaded web build is 3 to 4 times slower than the
##                       desktop, measured in docs/superpowers/specs/2026-10-04-bigmap-spike-report.md and again with the real game, tools/town_bench.gd `--what=game`).
##   `path_budget()`     the most `Pathfinder.find` calls one rules step may make for the chasing dead (the rest ask again a few steps later): 24 on a desktop, 12 in a browser.
##   `max_view_tiles()`  the largest area of the town the camera may show (the draw calls and the pawns that are made grow with it): `min_zoom(viewport)` is the zoom that gives it.
##   `NODES_PER_FRAME`   how many pawn nodes one frame may make (`Main._sync_views`: a street woken by a shout is made over a few frames, not in one).
##
## ADAPTATION (an instance, `TownGame` holds it and calls `frame()` once a frame): the real frame time (the wall clock, not the clamped step the game feeds its views) is smoothed;
## when it stays over SLOW_MS (28 ms, under 36 fps) for SLOW_S (2 s) the active cap is halved (down to MIN_CAP) and the awake dead above it that are not after anybody go back to
## sleep (DEAD1: and the night's cap of the dead alive at once, 70, is cut by the same share, `TownRules.wave_cap`); when it stays under FAST_MS (18 ms) for FAST_S (5 s) the cap grows back by
## half of the way to the platform's own. A frame that took more than HITCH_S is a stall (a hidden
## browser tab, a save, a card), not a trend: it is not counted.
extends RefCounted

const ACTIVE_CAP := 60
const ACTIVE_CAP_WEB := 40
const MIN_CAP := 10
const PATH_BUDGET := 24
const PATH_BUDGET_WEB := 12
## The most of the town the camera shows at the furthest zoom out, in tiles (a house is about 200 tiles of the town: 24 houses at most on the desktop).
const MAX_VIEW_TILES := 5200.0
const MAX_VIEW_TILES_WEB := 3600.0
const NODES_PER_FRAME := 6

const SLOW_MS := 28.0
const SLOW_S := 2.0
const FAST_MS := 18.0
const FAST_S := 5.0
const HITCH_S := 0.5
## The smoothing of the frame time: the share of the old average kept each second.
const KEEP_PER_S := 0.05

var sim
var full := ACTIVE_CAP
var cap := ACTIVE_CAP
## The smoothed frame time (ms) and the seconds it has been over SLOW_MS / under FAST_MS.
var avg_ms := 16.7
var slow_s := 0.0
var fast_s := 0.0
var halved := 0
var restored := 0
var enabled := true
var _last_us := 0


static func is_web() -> bool:
	return OS.has_feature("web")


static func desktop_cap() -> int:
	return ACTIVE_CAP


static func web_cap() -> int:
	return ACTIVE_CAP_WEB


static func active_cap() -> int:
	return ACTIVE_CAP_WEB if is_web() else ACTIVE_CAP


static func path_budget() -> int:
	return PATH_BUDGET_WEB if is_web() else PATH_BUDGET


static func max_view_tiles() -> float:
	return MAX_VIEW_TILES_WEB if is_web() else MAX_VIEW_TILES


## The zoom (pixels to the tile) that shows no more than `max_view_tiles()` of the town in a viewport of `vp` logical pixels.
static func min_zoom(vp: Vector2) -> float:
	return sqrt(maxf(1.0, vp.x * vp.y) / max_view_tiles())


# ------------------------------------------------------------------- the adaptive cap --

func setup(the_sim) -> void:
	sim = the_sim
	full = active_cap()
	cap = full
	_last_us = Time.get_ticks_usec()
	var field = sim.get("field") if sim != null else null
	if field != null:
		field.active_cap = cap


## Called once a frame (`TownGame.on_frame`). `now_us` is for a test that wants to hand the clock over.
func frame(now_us: int = -1) -> void:
	var now := Time.get_ticks_usec() if now_us < 0 else now_us
	var dt := float(now - _last_us) / 1.0e6
	_last_us = now
	if not enabled or dt <= 0.0 or dt > HITCH_S:
		return
	step(dt)


## One frame of `dt` seconds (the part a test drives with made-up times).
func step(dt: float) -> void:
	var keep := pow(KEEP_PER_S, dt)
	avg_ms = avg_ms * keep + dt * 1000.0 * (1.0 - keep)
	if avg_ms > SLOW_MS:
		slow_s += dt
		fast_s = 0.0
		if slow_s >= SLOW_S:
			slow_s = 0.0
			_set_cap(maxi(MIN_CAP, int(float(cap) * 0.5)))
			halved += 1
	elif avg_ms < FAST_MS:
		slow_s = 0.0
		if cap < full:
			fast_s += dt
			if fast_s >= FAST_S:
				fast_s = 0.0
				_set_cap(mini(full, cap + maxi(1, int(ceil(float(full - cap) * 0.5)))))
				restored += 1
	else:
		slow_s = 0.0
		fast_s = 0.0


func _set_cap(value: int) -> void:
	if value == cap:
		return
	cap = value
	# (DEAD1: the night's own dead are held to the same share: the rest wait outside, `TownRules.wave_cap`)
	if sim != null and sim.get("wave_scale") != null:
		sim.wave_scale = float(cap) / float(maxi(full, 1))
	var field = sim.get("field") if sim != null else null
	if field != null:
		field.active_cap = cap
		if field.has_method("trim"):
			field.trim(cap)
