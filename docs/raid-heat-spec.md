# Raid heat: spec (agreed 2026-10-18)

The owner's playtest of playtest-8 found raids aimless: no reason to stop, no way to put the squad to work, and noise that was hard to read. This round turns the existing noise system (`scripts/prison/prison_noise.gd`, per-region heat, hordes) into one visible heat meter for the whole raid, with clear stages, and lets companions loot on their own when it is safe.

## Decisions taken with the owner

- Heat fills from noise first, and also from a slow trickle of time, so even a silent raid cannot last forever.
- At 100% the place is overrun: waves keep coming until the party leaves. There is no forced end and no game-over screen.
- Raids stand alone. A loud raid does not make the next horde night bigger, and a place does not stay hot for a later visit.
- Companions loot by themselves while following Ruth, only when no awake dead are near. There is no order key for looting.

## The meter

One value from 0 to 100 for the raid, shown on the raid top bar in place of the "Noise" chip, as a bar with the stage name. It is fed by the same `Noise.emit` calls that exist today, so every sound already in the game counts.

| Heat | Stage | What happens | What the player sees |
|---|---|---|---|
| 0 to 30 | Quiet | The dead sleep. Only a noise right beside a sleeper wakes it. | Green bar, "Quiet" |
| 30 to 60 | Stirring | Dead within earshot of each noise wake and walk to it, as the noise system does now. | Amber bar, banner "They're stirring" once |
| 60 to 90 | Hunted | One horde enters from a map edge and heads for the loudest place. Its side is shown. | Red bar, banner "A horde is coming", an arrow at the edge |
| 90 to 100 | Overrun | Waves keep entering from the edges every so often until the party leaves. | Pulsing red bar, banner "Get out" |

What fills it (tuning starts here, all numbers in `assets/data/prison_noise.json`):

- A gunshot: a large step, larger for a shotgun or rifle than a pistol.
- Breaking a door or glass, a car alarm, a thrown firecracker: a large step.
- Running: a small step per second. Searching a container: a small step per search.
- A knife kill: almost nothing.
- Time: a slow trickle, about 1 point a minute, so a quiet raid reaches Stirring after about 30 minutes and never stays quiet forever.

Cooling: heat drains slowly while nothing loud happens, but never below the start of the stage already reached. Once a horde has come, it does not go away. Night raids keep their current effect on how easily the dead wake; the meter works the same by night.

## Companions loot on their own

- While following, a companion searches containers within about 5 tiles of Ruth, one at a time, in rooms Ruth has already entered.
- It only starts or continues while no awake dead are within about 10 tiles of it or of Ruth. The moment one is, it stops, returns to Ruth's side and fights under the leash rules (prison_squad.gd), then resumes when it is clear.
- At Hunted or Overrun companions stop looting and stay with Ruth.
- Their searches make noise like Ruth's, so two looting companions are faster but louder.
- What they find goes straight to the truck's cargo (the raid's stock that is banked at the pickup today), not into their own bags, so the player never manages a companion's pack. The raid bar shows the truck's tally. Ruth's own pack works as now.
- A short floater shows what they found ("Ike: 4 scrap").

## Leaving

A "Leave" prompt shows at the truck (the pickup ring) at any heat. Everyone with Ruth comes along. A companion still out of reach is called back first (the existing All back / retreat V), as now.

## Not in this round

Order keys for looting, raids that change the base's nights, places that remember heat, new enemy types.

## Checks for the build

Staged raid runs that walk a quiet raid with the knife, a loud raid with the shotgun, and a raid left to idle, logging the heat over time and the stage changes; companions looting in a quiet raid and dropping it the moment a walker wakes; screenshots of the meter at each stage; test cases in an existing test file for the stage thresholds, the floor that heat cannot cool below, companion looting stopping near awake dead, and loot going to the truck.
