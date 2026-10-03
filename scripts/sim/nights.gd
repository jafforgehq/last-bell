## Presence, plating and breaches (round 19, slice 3: docs/superpowers/plans/2026-10-03-round-19.md, S3.2).
##
## PHASE 0 STUB. Every function returns its neutral value (what the old code did), so that the hooks in `sim.gd`, `avatar.gd`
## and `interact.gd` are one line each and the game plays byte for byte as before until BREACH-SIM writes the rules in here.
## BREACH-SIM owns this file from phase 1: it keeps these signatures and replaces the bodies. Everything below is behind
## `active()`: `sim.nights_on` (false in a place's sim, `raid_sim.gd`) and an avatar (`sim.player_id != ""`).
##
## Saved with the modules (`save`/`load_state`): only `warned` and the hot-breach alert marks.
extends RefCounted

var sim
## Sections of tonight a warning was given for (segment id -> day), and the hot breaches already announced (segment id -> day).
var warned := {}
var hot_marks := {}


func setup(s) -> void:
	sim = s


func start() -> void:
	warned = {}
	hot_marks = {}


## Once a step (`Sim.update`, right after the streets): the stub does nothing.
func update(_dt: float) -> void:
	pass


## Whether any of this applies: the settlement game's sim (not a place's) with an avatar.
func active() -> bool:
	return sim.nights_on and sim.player_id != ""


## The avatar is up, at the base, `p` is someone else and within rally.radius (9) tiles of them.
func rallied(_p) -> bool:
	return false


## 1 + rally.aim if `rallied(p)`, else 1.0 (multiplies `Sim.aim_factor`).
func aim_mult(_p) -> float:
	return 1.0


## rally.fire (0.85) if `rallied(p)`, else 1.0 (multiplies the gun's cooldown in `Sim._fire`).
func fire_mult(_p) -> float:
	return 1.0


## `dmg` for anything not plated; a plated brute: dmg x weak_mult on a head hit, else dmg x armour.
func damage_to(_z, dmg: float, _weak: bool) -> float:
	return dmg


## Whether the pellet's ray passes within weak_r x size of the head's centre.
func weak_hit(_z, _from: Vector2, _dir: Vector2) -> bool:
	return false


## A defender's shot at a plated brute: one die (rng.randf() < npc_weak); no die for anything else.
func npc_weak(_z) -> bool:
	return false


## A fallen section (state 3) with at least hot_n of the dead near it.
func breach_hot(_seg) -> bool:
	return false


## 0.0 for a person mending a hot breach with nobody rallying them; else 1.0.
func repair_mult(_p, _seg) -> float:
	return 1.0


## The one number the bot, the calls and the view's marks use: how hard a section is pressed (0 for doors).
func section_threat(_seg) -> float:
	return 0.0


## The most threatened non-door compound section: {"seg": the section or null, "threat": its score}.
func contested() -> Dictionary:
	return {"seg": null, "threat": 0.0}


## Where a gunner covers the section: among `jobs.posts()` the one that reaches at least half of its slots, nearest to its middle
## (the stub: `sim.repair_spot(seg)`, the contract's own fallback).
func stand_for(seg, _gun: Dictionary) -> Vector2:
	return sim.repair_spot(seg)


func save() -> Dictionary:
	return {"warned": warned.duplicate(), "hot_marks": hot_marks.duplicate()}


func load_state(d: Dictionary) -> void:
	warned = {}
	hot_marks = {}
	var w = d.get("warned", {})
	if typeof(w) == TYPE_DICTIONARY:
		for k in w:
			warned[int(k)] = int(w[k])
	var h = d.get("hot_marks", {})
	if typeof(h) == TYPE_DICTIONARY:
		for k in h:
			hot_marks[int(k)] = int(h[k])
