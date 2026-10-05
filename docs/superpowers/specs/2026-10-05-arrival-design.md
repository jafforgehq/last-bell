# Arrival: starting at the forest edge and choosing a house (design)

Status: proposed by the owner on 2026-10-05 after the first playthrough ("we are starting on the map edge coming from the forest, and then we claim a house and build the base from it"); the guided version below was recommended and approved ("do what you recommended").

## 1. Why

The current opening wakes Ruth inside a house chosen for her, with three dead placed in its rooms. It works, but it is contrived and gives the player no decision. An arrival gives the game a real beginning (alone, at the edge of a dead town, the bell far off), lets the player walk and shoot outdoors before clearing anything, makes the first decision matter (which house is the base), and gives day 1 a goal and a clock: find shelter before dusk.

## 2. The player's first minutes

1. **Arrive.** The run starts at about 07:00 on day 1 on the road at the forest edge of the town (trees behind, an abandoned car or two, a road sign). A short line: "The bell is ringing somewhere. Find shelter before dark." The objective points into town.
2. **Walk in.** A short calm walk (the street dead near the entry stand still or are absent: nothing bites in the first minute) to the first houses.
3. **Choose.** Three or four **candidate homes** are near the entry (25 to 45 tiles). Each shows a small marker when the avatar is near (about 14 tiles) with one honest line: "Family home. 8 rooms, big yard." / "Bungalow. 5 rooms, small yard." / "Cottage. 3 rooms, no yard." They differ: the family home is the best base (rooms for a crew, a yard for the fence ring) but takes the longest to clear; the cottage is quick but cramped and its base layout is poor. Every candidate is pre-validated so a base can really be built there.
4. **Clear and claim.** As today: dead inside, rooms revealed and cleared, the house is clear, claim it (E at the front door). The claim chooses the base layout for that house.
5. **Then as before:** rescue four, fortify, hold the first attack, the end card. Rescue spots, the calm start zone and the night's spawn points are computed around the CLAIMED house.

Not in this version: moving the base later; claiming a house that is not a candidate (the code may allow it, the game does not offer it).

## 3. Data contract (additions to `TownGen.make`, scripts/town/town_gen.gd)

- `entry`: `{"pos": Vector2 (the tile the avatar spawns on), "face": "N"|"E"|"S"|"W" (the direction into town), "road": Rect2i (the road end), "label": String}`.
- `candidates`: Array of 3 or 4 `{"house": id, "kind": String, "label": String, "rooms": int, "yard": "big"|"small"|"none", "dist": float (tiles from the entry), "tier": "best"|"ok"|"poor"}`. Each house passes `BaseLayout.validate` with its ring mostly free, has 3 to 5 dead inside, and a clear ring (no street dead within 20 tiles).
- `rescue_for`: Dictionary `String(house id) -> Array` of rescue records (the shape of `rescue`), one set per candidate, 12 spots near to far around that house (the first 12 to 25 tiles away). `rescue` (top level) = `rescue_for` of the best candidate.
- `start`: kept for compatibility: `{"house": best candidate id, "pos": entry.pos, "room": -1}`.

## 4. Sim and flow (scripts/town/one_house.gd and friends)

- Scenario stage `arrive` before `alone`: objective "Find shelter before dark" with an arrow to the nearest candidate; the guide's first lessons are outdoors (walk, aim and shoot, find a house).
- `base.claim` and `clearing.claimable` accept any candidate (not only `houses.start_house()`); the claim builds the layout for that house; rescue (`rescue.gd`) and the wake/calm rules use `rescue_for[claimed house]`.
- A world-space marker per candidate near the avatar (a small flag or house icon plus the label); the district map (M) shows candidates before a claim.
- Opening camera at the entry; start hour 07:00.
- If dusk comes before a claim: the streets are more dangerous (as for any night outdoors); no scripted rescue; the player can still claim at night.

## 5. Acceptance

- A new game starts at the forest edge; the bot (tools/house_bot.gd) walks in, picks the best candidate, clears, claims, rescues four, fortifies and holds the first attack; the lab (tools/house_lab.gd) holds its targets (bot at least 6 of 8, idle at most 3 of 8, claim before 14:00, four rescues by day 3, 20 to 34 real minutes) on seeds 1..16.
- Every seed 1..16 has at least three valid candidates within 45 tiles of the entry.
- Save and load work before and after the claim.
