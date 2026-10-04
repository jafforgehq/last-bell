## Problems (round 25, S25.3 of docs/superpowers/plans/2026-10-04-round-25.md): the small trouble the base throws up (a leak, a jammed generator, a quarrel, a
## cracked wall): a world marker with a timer that the player fixes in person (E) or hands to someone over the radio; unfixed it gets worse. THIS FILE IS A STUB
## (phase 0b): every function has its contract's signature and returns the exact neutral value (nothing open, nothing blocked, 1.0, [], false), so the hooks that
## read it (workshop, build, morale, `sim.perf`, radio, initiative, interact) change nothing. PROBLEMS-SIM replaces the bodies; the signatures, the constants and
## the saved variables stay. NO `sim.rng` anywhere: the one "roll" is `fix_roll`, a hash of the state.
##
## A problem is a record {"id": "p<n>", "kind", "day", "t0" (clock_min), "ttl_h", "at": Vector2, "label", "ids": [people], "seg": id, "stage" 0|1|2,
## "fixer": id, "state": "idle"|"walking"|"working", "cost": {"scrap": n}}; saved.
extends RefCounted

const FIRST_DAY := 3
const MAX_OPEN := 2
const TTL_H := {"leak": 18.0, "jam": 12.0, "quarrel": 24.0, "crack": 14.0}
const FIX_REACH := 1.8
## The slow look: rules seconds between two looks (30 game minutes).
const TICK_S := 10.0

var sim
var enabled := true
## Saved. The open problems (records), how many have been raised, the game minute before which none is raised. (PROBLEMS-SIM adds what else it keeps.)
var records: Array = []
var count := 0
var next_at := 0.0
## What the avatar's own hands are fixing now ({"id", "left"} rules seconds), {} when nothing.
var fixing := {}


func setup(s) -> void:
	sim = s


func start() -> void:
	records = []
	count = 0
	next_at = 0.0
	fixing = {}


func person_added(_p) -> void:
	pass


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


func update(_dt: float) -> void:
	if not active():
		return


## Game hours between two problems on this day: about one every 1.5 days in the first week, one a day by day 18.
func gap_h(day: int) -> float:
	return clampf(36.0 - 1.2 * float(day - 3), 18.0, 36.0)


func allowed_now() -> bool:
	return false


## PURE rotation: "leak" | "jam" | "quarrel" | "crack", "" when none is eligible.
func pick_kind() -> String:
	return ""


## The best pair for a quarrel (two people), [] when none reaches 30.
func quarrel_pair() -> Array:
	return []


func open() -> Array:
	return []


func record(_id) -> Dictionary:
	return {}


func has_open(_kind) -> bool:
	return false


## For the views: [{"id", "kind", "at", "label": "Leak: 11 h left", "stage", "pct", "state"}]; [] inactive.
func marks() -> Array:
	return []


## interact.candidates(): [{"kind": "problem", "id", "label", "pos", "dist", "ok", "why"}] within FIX_REACH of a marker.
func candidates() -> Array:
	return []


## interact.use(): starts the fix at the avatar's own hands. {"ok", "line", "why", ...}.
func use(_cand := {}) -> Dictionary:
	return {"ok": false, "line": "", "why": "Nothing here to fix"}


## Would this person go and fix it: {"ok", "why", "hard", "line", "tone", "delay_s", "chance", "cost", "eta_h"}. Pure.
func fix_willingness(_p, _problem_id) -> Dictionary:
	return {"ok": false, "why": "Nothing here to fix", "hard": true, "line": "", "tone": "refused", "delay_s": 0.0, "chance": 0.0, "cost": {}, "eta_h": 0.0}


## radio.request_fix delegates here: {"ok", "line", "why", "hard", "tone", "insisted", "chance"}.
func request_fix(_problem_id, _p, _args := {}) -> Dictionary:
	return {"ok": false, "line": "", "why": "Nothing here to fix", "hard": true, "tone": "refused", "insisted": false, "chance": 0.0}


## The only "dice": a pure function of the state (no `sim.rng`), 0.0 to 0.999.
func fix_roll(problem_id, person_id) -> float:
	return float(("%s|%s|%d" % [problem_id, person_id, int(sim.run_seed)]).hash() % 1000) / 1000.0


## The willing person with the best `chance` (ties by id): what the stage-2 call's "Send <name>" uses; null when nobody.
func best_for(_problem_id) -> Variant:
	return null


## Keeps a quarrel's two apart (no roll): {"ok", "line", "why"}.
func separate(_problem_id) -> Dictionary:
	return {"ok": false, "line": "", "why": "Nothing here to settle"}


## radio._carry_out for kind "problem": "send" -> request_fix(best_for), "leave" -> nothing. The line the News keeps.
func carry_out(_e: Dictionary, _option_id: String) -> String:
	return ""


## workshop.update (a jam stops the bench) and build.factor (the floodlights): `what` is "bench" or "floodlights".
func blocks(_what: String) -> bool:
	return false


## x0.85 for a quarrelling pair, else 1.0.
func perf_mult(_p) -> float:
	return 1.0


## morale._modifiers: [{"label", "value"}]; [] inactive.
func mood_lines(_p) -> Array:
	return []


func save() -> Dictionary:
	return {"records": records.duplicate(true), "count": count, "next_at": next_at, "fixing": fixing.duplicate(true)}


## Restores what `save` wrote; {} (a save from before) is a fresh module with nothing open. The stub keeps only what is sound.
func load_state(d: Dictionary) -> void:
	start()
	count = maxi(0, int(d.get("count", 0))) if _num(d.get("count")) else 0
	next_at = maxf(0.0, float(d.get("next_at", 0.0))) if _num(d.get("next_at")) else 0.0


static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))
