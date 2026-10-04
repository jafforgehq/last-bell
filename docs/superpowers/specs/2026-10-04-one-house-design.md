# One House: a solo start in a big town (design)

Status: COMMITTED by the owner on 2026-10-04 ("it's not a spike, I want to go with that direction, pivot fully"). The foundation (town generator, dormant dead, `--town`) is being built for real on branch feature/town-core; its measurements (`docs/superpowers/specs/2026-10-04-bigmap-spike-report.md`) set the active-dead caps and wake rules, not a go/no-go. The implementation plan with parallel work packages is `docs/superpowers/plans/2026-10-04-one-house-plan.md`.

## 1. Why

The avatar game starts inside a finished base (the school) with a crew that already runs it, so the first minutes have little to do and nothing is earned. The owner's idea: start with **one building and one survivor**, and make everything after that something the player earns: clear the house, claim it, explore, rescue people, and only when the community is big enough do the dead come for it and the base must be fortified.

This replaces the school compound as the start of the game. The school stays in the repository as art and data (and may return later as a big base to move into).

## 2. The arc (what the player does)

1. **Alone in a house.** Ruth wakes in one house of a big town. The roof of any building the avatar is inside is hidden, so the rooms are visible; rooms the avatar has not opened yet are dark. Some rooms have dead inside, some have loot (containers searched as in the played places today).
2. **Clear it.** Kill or avoid the dead in the rooms, search the containers. When every room of the house is clear the game says so ("The house is clear").
3. **Claim it.** One action (E at the front door or a table, a short hold) makes it the **base**: a bed, a stash, a radio. From now on the house is where the player sleeps, stores and returns, and the clock matters: the first nights are quiet but the streets are dangerous in the dark.
4. **Explore and rescue.** Houses around the town hold loot, dead and sometimes a **survivor** (barricaded, wary). Clearing their house and talking to them brings them home if the base is safe enough. Each rescued survivor takes a job at the base (the existing jobs and the radio/wheel: ask, refuse, trust).
5. **Four is a crowd.** When the **fourth** survivor has been rescued the community is loud enough that the dead start coming to the base **every night**. (Optional hook: the bell is hung with the fourth survivor and the first night attack comes at its first toll.)
6. **Fortify.** The house has a **perimeter of predefined slots** (fence sections, a gate, corner towers, floodlights, sandbag or barricaded windows) that are unlocked and built with scrap and builder-hours, as buildings are today. Nights are held at the perimeter by the community and the avatar, as at the school wall today.
7. **Demo ending:** the demo ends after the first fortified night attack is held (about 25 minutes), with an end card.

## 3. The town

- One open map of about 192 x 192 tiles (size to be confirmed by the spike): a street grid, 150 to 250 houses of three or four templates, a few shops, parked cars and trees as obstacles. Generated from a fixed seed so the demo is the same every time; the start house, the first rescue and the first loot are hand-placed exceptions.
- **Houses** have named rooms, doors (openings), windows, containers with loot (reusing `SiteGen`'s containers and rooms) and dead.
- **Roofs** are drawn per building and fade out when the avatar is inside that building (and its connected yard); a room's interior is revealed when its door is opened (line of sight inside buildings is a later refinement).
- The **dead** are spread over the whole town (hundreds) but are **dormant data** (a spatial hash) until the avatar, a noise (a shot) or a light comes near; they go back to sleep when the avatar is far. Only a capped number are active at once (the cap is set by the spike for desktop and web).

## 4. The base and its fortification kit (all predefined)

- A claimed house gets a **base layout** (data, like the school's `map.json` pieces): its plot, a ring of perimeter slots with ids, the posts for night shooters, the gate position, and the interior stations (bed, stash, radio, workbench).
- **Slots** are built from a short catalogue (data): fence section (cheap, weak), reinforced fence, gate, tower (a post that reaches further), floodlight, window barricade, sandbags. Each slot has a cost in scrap and builder-hours and hit points. Slots are unlocked as the community grows (2, 3, 4 people), so the player has something to build at each step.
- Nights use the **existing night, wall-segment and post logic**: a perimeter section is a wall segment with hit points; the dead pick the nearest open or weak segment; the community shoots from posts; the avatar can mend and shoot. Before the fourth rescue, only wandering dead reach the base, and a barricaded cleared house is safe.

## 5. What is reused and what is new

Reused: the avatar and aimed combat, the radio and command wheel, jobs, trust and refusals, the played-place machinery (`SiteGen`, `RaidRun`, `RaidScene`: rooms, containers, search), nights, wall segments and posts, building with homes (plots), the morning briefing and priorities, the gate, the pickup (later), art, sound.

New: the big town and its generator; the dormant-dead system; roof cutaway and room reveal; clear-and-claim; a generic base layout for any house (instead of one hand-made map); the perimeter slot catalogue and the fourth-rescue trigger; rescue encounters (a survivor inside a house); a solo-start economy and a new short tutorial (move, aim, clear a room, claim); a new demo flow.

## 6. Technical risks (to be answered by the spike)

1. Per-dead simulation cost in the web build (60 fps with about 80 dead; 19 fps with 240): dormancy and an active cap are required.
2. Pathing and flow fields on a 192 x 192 grid: cost per recompute and memory.
3. Ground and roof rendering for 200 buildings: draw calls and the load time.
4. Saving dormant dead compactly.
5. Generalising night logic from one hand-made wall to a generated base layout.

## 7. Staged plan

- **Foundation (now):** the town generator, the dormant-dead system, the `--town` start, and the measurements that set the caps.
- **Slice 1, One House:** solo start, interiors with roof cutaway, clear and claim, the first quiet night, one rescue.
- **Slice 2, The fortress:** the fourth rescue starts the nightly attacks; the perimeter kit; the held first fortified night; the end card (this is the demo).
- **Slice 3, polish** of the new flow (the earlier polish work on combat feel, art and audio carries over).

## 8. Open questions

- Map size and whether the car and the drive come back inside the open map (probably later).
- Whether claiming needs a minimum of cleared rooms or only the house's own rooms.
- How many slots per stage and the exact scrap costs (to be tuned with the balance tools).
- Whether survivors can be lost (taken, killed outside) before the fourth rescue.
