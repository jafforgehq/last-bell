## Briefing (round 25, S25.1 of docs/superpowers/plans/2026-10-04-round-25.md): the morning briefing (about 06:30, day 2 on, never pausing: the base's concerns,
## ranked), the evening debrief (what got done and what slipped) and the facilities' bottleneck labels. THIS FILE IS A STUB (phase 0b): every function has
## its contract's signature and returns the exact neutral value (no concern, no card, no facility), so the game plays as before. BRIEF-SIM replaces the
## bodies. It reads the other four modules (one way, by name, each read guarded with `has_method`); nobody reads it. No `sim.rng` anywhere.
extends RefCounted

const FIRST_DAY := 2
const BRIEF_FROM_H := 6.5
const MAX_LINES := 7
const DEBRIEF_BEFORE_DUSK_H := 0.25
## The slow look: rules seconds between two looks (30 game minutes).
const TICK_S := 10.0

var sim
var enabled := true
## What the briefing card shows (the latest `compose()`), {} before the first one.
var current := {}


func setup(s) -> void:
	sim = s


func start() -> void:
	current = {}


func person_added(_p) -> void:
	pass


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


func update(_dt: float) -> void:
	if not active():
		return


## PURE, ranked: [{"id", "level" ("alarm"|"warn"|"info"|"ok"), "text", "sub", "page", "focus", "score"}].
func concerns() -> Array:
	return []


## Once a day at the first slow look at or after 06:30 in the day phase, from FIRST_DAY: {"day", "lines", "order", "suggested"}; {} when nothing is composed.
func compose() -> Dictionary:
	return {}


## Once a day at `seasons.dusk_hour() - 0.25`: {"day", "deltas", "built", "mended", "treated", "errand", "hours", "done", "slipped"}; {} when nothing is said.
func debrief() -> Dictionary:
	return {}


## [{"id", "name", "pos": Vector2, "ok": bool, "bottleneck", "line", "fix": {"page", "focus"}}]: what each station waits on. Pure.
func facilities() -> Array:
	return []


func save() -> Dictionary:
	return {"current": current.duplicate(true)}


## Restores what `save` wrote; {} (a save from before) is a fresh module.
func load_state(d: Dictionary) -> void:
	start()
	var raw = d.get("current", {})
	if raw is Dictionary:
		current = (raw as Dictionary).duplicate(true)
