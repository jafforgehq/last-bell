## The kinds of the dead. A walker is the plain one; a runner is quick and frail;
## a brute is slow, huge and tears walls down. Numbers are starting values, tuned
## with tools/balance.gd.
extends RefCounted

const WALKER := "walker"
const RUNNER := "runner"
const BRUTE := "brute"

## Per kind: hit points and speed (tiles a second) as [low, high], the damage of
## its claw on walls as a multiple of a walker's, its cost in a night's budget, its
## size in the drawing and the first night it comes.
const KINDS := {
	"walker": {"hp": [4, 7], "speed": [0.5, 0.85], "claw": 1.0, "cost": 1.0, "size": 1.0, "first": 1},
	"runner": {"hp": [2, 4], "speed": [1.5, 2.1], "claw": 0.8, "cost": 2.0, "size": 0.94, "first": 4},
	"brute": {"hp": [22, 30], "speed": [0.42, 0.6], "claw": 3.5, "cost": 9.0, "size": 1.4, "first": 8},
}

## The share of a night's budget spent on runners and on brutes: it starts at the
## first night of the kind and rises a step a night up to a cap.
const RUNNER_START := 0.06
const RUNNER_STEP := 0.03
const RUNNER_CAP := 0.30
const BRUTE_START := 0.08
const BRUTE_STEP := 0.02
const BRUTE_CAP := 0.20
## The shares on the Big Night (the last night).
const BIG_RUNNERS := 0.30
const BIG_BRUTES := 0.25
## The order the player's guns pick targets in: a lower number is shot first.
const PRIORITY := {"brute": -8.0, "runner": -2.0, "walker": 0.0}


## What share of a night's budget goes to each kind on this night.
static func shares(day: int, big: bool) -> Dictionary:
	if big:
		return {"walker": 1.0 - BIG_RUNNERS - BIG_BRUTES, "runner": BIG_RUNNERS, "brute": BIG_BRUTES}
	var runner := 0.0
	if day >= int(KINDS.runner.first):
		runner = minf(RUNNER_CAP, RUNNER_START + RUNNER_STEP * float(day - int(KINDS.runner.first)))
	var brute := 0.0
	if day >= int(KINDS.brute.first):
		brute = minf(BRUTE_CAP, BRUTE_START + BRUTE_STEP * float(day - int(KINDS.brute.first)))
	return {"walker": 1.0 - runner - brute, "runner": runner, "brute": brute}


## How many of each kind a night with this budget brings. A kind that has begun
## brings at least one. `rng` rounds the part of a creature that is left over.
static func counts(budget: float, day: int, big: bool, rng: RandomNumberGenerator) -> Dictionary:
	var sh := shares(day, big)
	var out := {"walker": 0, "runner": 0, "brute": 0}
	var spent := 0.0
	for kind in ["brute", "runner"]:
		if sh[kind] <= 0.0:
			continue
		var want: float = budget * float(sh[kind]) / float(KINDS[kind].cost)
		var n := int(floor(want))
		if rng.randf() < want - float(n):
			n += 1
		out[kind] = maxi(n, 1)
		spent += float(out[kind]) * float(KINDS[kind].cost)
	out["walker"] = maxi(0, roundi(budget - spent))
	return out
