## Dilemmas (round 25, S25.4 of docs/superpowers/plans/2026-10-04-round-25.md): the one hard choice with a timer and costs: a fever outbreak the medicine cannot
## cover for everyone, treat or quarantine. THIS FILE IS A STUB (phase 0b): every function has its contract's signature and returns the exact neutral value
## (no trigger, no claim, no call, no sign), so the hooks that read it (radio, initiative) change nothing. DILEMMA-SIM replaces the bodies; the signatures, the
## constants and the saved variables stay. No `sim.rng` anywhere: the outbreak risk is a deterministic accumulator.
extends RefCounted

const KINDS := ["outbreak"]
const FIRST_DAY := 4
const TTL_MIN := 180.0
const GAP_DAYS := 4
const MEDS_SLACK := 3.0
const QUARANTINE_H := 48.0
const SICK_H := 18.0
## The slow look: rules seconds between two looks (30 game minutes).
const TICK_S := 10.0

var sim
var enabled := true
## Saved. `closed`: the quarantine ({"until": clock_min, "ids": [...]}), {} when none; `exposure`: person id -> 0..1; `risk`: the outbreak risk accumulator 0..1.
var closed := {}
var exposure := {}
var risk := 0.0


func setup(s) -> void:
	sim = s


func start() -> void:
	closed = {}
	exposure = {}
	risk = 0.0


func person_added(_p) -> void:
	pass


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


func update(_dt: float) -> void:
	if not active():
		return


## PURE: {"patients": [ids], "need": meds for all, "meds": stock} when the camp has a dilemma now, else {} (and the plain "sick" call goes on as it does).
func trigger() -> Dictionary:
	return {}


## radio._watch_for_fever asks: the plain "sick" call is not raised for a person the dilemma holds (open, or `trigger()` claims them now).
func claims(_p) -> bool:
	return false


## Raises the call (radio kind "dilemma") once on a slow look when allowed; its id, 0 when none.
func raise() -> int:
	return 0


## radio._carry_out for kind "dilemma": "treat" or "quarantine". The line the News keeps.
func carry_out(_e: Dictionary, _option_id: String) -> String:
	return ""


## For the views: [{"kind": "quarantine", "at", "label": "Quarantine: 2 days"}]; [] otherwise.
func marks() -> Array:
	return []


## initiative.voice_opinion delegates for kind "dilemma": {"p": the person, "option": an option id of the call, "say": "treat them."} as `initiative._on_sick` makes it
## (use `sim.initiative.opinion_giver("medic", ...)` for the person); voice_opinion makes the title and the line. {} without a medic or a voice.
func opinion(_e: Dictionary) -> Dictionary:
	return {}


func save() -> Dictionary:
	return {"closed": closed.duplicate(true), "exposure": exposure.duplicate(), "risk": risk}


## Restores what `save` wrote; {} (a save from before) is a fresh module. What is not sound (a number that is not finite) is left out; the numbers are kept between 0 and 1.
func load_state(d: Dictionary) -> void:
	start()
	risk = clampf(float(d.get("risk", 0.0)), 0.0, 1.0) if _num(d.get("risk")) else 0.0
	var ex = d.get("exposure", {})
	if ex is Dictionary:
		for k in ex:
			if _num(ex[k]):
				exposure[str(k)] = clampf(float(ex[k]), 0.0, 1.0)


static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))
