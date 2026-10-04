## Policies (round 25, S25.2 of docs/superpowers/plans/2026-10-04-round-25.md): the four dials the player sets for the base (rations, work hours, scavenger
## boldness, strangers at the gate), each option with a cost the player can see. THIS FILE IS A STUB (phase 0b): every function has its contract's signature
## and returns the exact neutral value (1.0, [], the base itself, "", true, 0, false), so the hooks that read it (supplies, traits, morale, `sim.perf`, scavenge,
## recruits) change nothing. POLICY-SIM replaces the bodies; the signatures, the constants and the saved variables stay. No `sim.rng` anywhere.
## NAME: the contract's `set(dial, option)` is `set_dial` here (GDScript does not allow a method named `set`: it is Object's own).
extends RefCounted

const OPTIONS := {"rations": ["full", "half", "hungry"], "hours": ["normal", "overtime"], "boldness": ["careful", "usual", "bold"], "strangers": ["let_in", "check", "turn_away"]}
## Every default is exactly today's game.
const DEFAULTS := {"rations": "full", "hours": "normal", "boldness": "usual", "strangers": "let_in"}
## The slow look: rules seconds between two looks (30 game minutes).
const TICK_S := 10.0

var sim
var enabled := true
## Saved. `current`: dial -> option; `weary`: person id -> 0..100; `changed_day`: dial -> the game day it was last changed (one change a dial a day).
var current: Dictionary = DEFAULTS.duplicate()
var weary := {}
var changed_day := {}


func setup(s) -> void:
	sim = s


func start() -> void:
	current = DEFAULTS.duplicate()
	weary = {}
	changed_day = {}


func person_added(_p) -> void:
	pass


## Whether the rules of this module run: an avatar game in the settlement game (a small start), not Orientation Day.
func active() -> bool:
	return enabled and sim != null and String(sim.player_id) != "" and bool(sim.recruits.small)


func update(_dt: float) -> void:
	if not active():
		return


## Sets a dial: {"ok", "line", "why"}. One change a dial a game day ("Changed today: again tomorrow").
func set_dial(_dial, _option) -> Dictionary:
	return {"ok": false, "line": "", "why": "The dials are not available yet"}


## The words of an option (policies.json's): {"name", "blurb", "pros", "cons"}.
func describe(_dial, _option) -> Dictionary:
	return {"name": "", "blurb": "", "pros": [], "cons": []}


## supplies: the share of a meal and of `days_left` per day ("food" or "water"); 1.0 inactive.
func ration_mult(_kind: String) -> float:
	return 1.0


## traits.mult / supplies._garden: keys "craft", "repair", "garden" only, else 1.0.
func work_mult(_p, _key: String) -> float:
	return 1.0


## sim.perf: rations and weariness; 1.0 inactive.
func perf_mult(_p) -> float:
	return 1.0


## morale._modifiers: [{"label", "value"}]; [] inactive.
func mood_lines(_p) -> Array:
	return []


## scavenge.errand_terms(): `base` merged with the boldness numbers; `base` itself when inactive or "usual".
func errand_terms(base: Dictionary) -> Dictionary:
	return base


## scavenge.why_not_errand: "" or the careful words (hard).
func errand_limit(_place_id: String) -> String:
	return ""


## recruits.call_due(): false only for "turn away" and a next caller who is not one of the authored three.
func strangers_call_ok() -> bool:
	return true


## recruits.accept: the days a stranger waits at the gate under "check" (+1).
func arrival_delay_days() -> int:
	return 0


## recruits._arrive: a bitten stranger turned back at the gate under "check" (nobody is added; the module sets `next_call_day`, tells the News, adds the event).
func caught_at_gate(_def: Dictionary) -> bool:
	return false


func save() -> Dictionary:
	return {"current": current.duplicate(), "weary": weary.duplicate(), "changed_day": changed_day.duplicate()}


## Restores what `save` wrote; {} (a save from before) is a fresh module with every dial at its default. What is not sound (a dial or option that is not known,
## a number that is not finite) is left out; weariness is kept between 0 and 100.
func load_state(d: Dictionary) -> void:
	start()
	var cur = d.get("current", {})
	if cur is Dictionary:
		for dial in OPTIONS:
			if cur.has(dial) and (OPTIONS[dial] as Array).has(str(cur[dial])):
				current[dial] = str(cur[dial])
	var w = d.get("weary", {})
	if w is Dictionary:
		for k in w:
			if _num(w[k]):
				weary[str(k)] = clampf(float(w[k]), 0.0, 100.0)
	var cd = d.get("changed_day", {})
	if cd is Dictionary:
		for dial in cd:
			if OPTIONS.has(str(dial)) and _num(cd[dial]):
				changed_day[str(dial)] = int(cd[dial])


static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))
