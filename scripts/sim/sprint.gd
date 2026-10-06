## SPRINT (One House, PACE): hold the run key and the avatar goes 45 percent faster than she walks, for as long as her breath lasts. A piece of `avatar.gd` (it makes one, `avatar.sprint`, and
## `avatar._move` asks it for the pace of each step); the town only: `sim.is_one_house()` is false in the school and for the no-player sim, so nothing here runs there and their walking is exactly
## what it was. Nothing here is saved: a load starts with a full breath.
##
## THE NUMBERS. SPEED_MULT 1.45 (3.2 tiles a second walking, 4.64 running). A full breath lasts DRAIN_S (4) seconds of running and comes back in RECOVER_S (6) seconds of anything else (walking or
## standing: it is a rest, not a punishment). A run cannot BEGIN with less than MIN_START (15 percent) in the tank, and one that ran the tank dry leaves her WINDED: she runs again only after the key has
## been let go and she has got back to MIN_START, so that holding the key does not stutter on and off every second.
## WHAT STOPS IT. The key let go, no walking asked, a reload in hand (`reloading`), a session (a search, the claim, a mend: `uses.busy()`), being down, or the tank empty. (Aiming is the view's: it does not
## ask for a run while the right button or Shift is held; with "Always aim at the mouse" a run lowers the gun and the trigger is ignored while it lasts: `avatar.update`.)
## NOISE. Running is heard: every NOISE_EVERY (0.5) seconds that she actually moves at the run the field is told of a sound NOISE_RADIUS (8) tiles round her (`field.noise`: the dead that stand or wander
## there go to look at the spot, a few of them at the most, the nearest first; a wanderer's pace, as for a shot), a third of that from inside a house (a shot's own share: TownSim `INDOOR_NOISE`).
## THE DRAWING reads `lean` (0 to 1, eased: the person's meta "sprint_lean", set here) for the body's lean and the lowered gun, and `shown()` for the breath's arc (scripts/ui/sprint_view.gd).
extends RefCounted

## The run key (the views read it: scripts/ui/pace_keys.gd says why X).
const KEY := KEY_X
const SPEED_MULT := 1.45
const DRAIN_S := 4.0
const RECOVER_S := 6.0
const MIN_START := 0.15
## The legs go this much faster than the pace alone makes them (the stride's phase advances `STRIDE_K` times as far for each tile).
const STRIDE_K := 1.1
const NOISE_EVERY := 0.5
const NOISE_RADIUS := 8.0
## The share of the radius that is heard from inside a house (TownSim `INDOOR_NOISE`, a shot's).
const INDOOR_SHARE := 0.3
## How fast the lean comes and goes (per second).
const LEAN_RATE := 9.0
const META := "sprint_lean"

var sim
## The hands: the run key is held (the view says so every frame, `set_wanted`).
var wanted := false
## Running this step.
var active := false
var stamina := 1.0
var winded := false
## 0 (upright) to 1 (running), eased.
var lean := 0.0
## The seconds of running at the pace until the next sound.
var _noise_t := NOISE_EVERY
var _who := ""
## Counters for a scripted run: how many sounds were made and how many seconds of running there were.
var noises := 0
var run_s := 0.0


func setup(s) -> void:
	sim = s


func start() -> void:
	wanted = false
	active = false
	stamina = 1.0
	winded = false
	lean = 0.0
	_noise_t = NOISE_EVERY
	_who = ""
	noises = 0
	run_s = 0.0


## The view's word, every frame: the run key is down (and nothing the view knows of forbids it: not aiming, no card open).
func set_wanted(on: bool) -> void:
	wanted = on


## Whether the breath's arc is to be drawn: while running, and while the tank is not full again.
func shown() -> bool:
	return active or stamina < 0.999 or winded


## The pace of this step as a factor of the walk: 1.0, or SPEED_MULT while running. Called by `avatar._move` at the start of every step of the player's person (`asking`: the hands ask for a walk).
func step(p, dt: float, asking: bool) -> float:
	if sim == null or not sim.is_one_house():
		active = false
		return 1.0
	var id := String(p.id)
	if id != _who:
		_who = id
		stamina = 1.0
		winded = false
		active = false
		lean = 0.0
	var can: bool = wanted and asking and _allowed(p)
	if winded and not wanted and stamina >= MIN_START:
		winded = false
	if active:
		if not can:
			active = false
	elif can and not winded and stamina >= MIN_START:
		active = true
		_noise_t = NOISE_EVERY
	var run := active
	if active:
		stamina = maxf(0.0, stamina - dt / DRAIN_S)
		run_s += dt
		if stamina <= 0.0:
			active = false
			winded = true
	else:
		stamina = minf(1.0, stamina + dt / RECOVER_S)
	var was := lean
	lean = move_toward(lean, 1.0 if run else 0.0, dt * LEAN_RATE)
	if lean != was or lean > 0.0:
		p.set_meta(META, lean)
	return SPEED_MULT if run else 1.0


## What forbids a run: down, away, reloading, a session in hand.
func _allowed(p) -> bool:
	if p.dead or p.turned or p.downed or p.away != null:
		return false
	if float(p.reloading) > 0.0:
		return false
	var uses = sim.get("uses")
	if uses != null and uses.has_method("busy") and bool(uses.busy()):
		return false
	return true


## After the person has moved `moved` tiles this step: the sound of a run is told to the field every NOISE_EVERY seconds of running.
func after_move(p, dt: float, moved: float) -> void:
	if not active or moved < 0.001:
		return
	_noise_t -= dt
	if _noise_t > 0.0:
		return
	_noise_t += NOISE_EVERY
	noises += 1
	var field = sim.get("field")
	if field == null or not field.has_method("noise"):
		return
	var r := NOISE_RADIUS
	var houses = sim.get("houses")
	if houses != null and int(houses.house_at(p.x, p.y)) >= 0:
		r *= INDOOR_SHARE
	field.noise(Vector2(p.x, p.y), p, r)


## Whether the gun is carried low and the trigger ignored: while running (the avatar asks this before it fires).
func lowered() -> bool:
	return active
