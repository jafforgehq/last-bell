# Prison management: first slice (spec, 2026-10-12)

Owner decision: build the first slice of base management in one go. Loot must matter: every raid answers a visible need, and every need is paid for with loot carried home. Nothing here is built yet; this file is the shared spec for the build agents.

## The loop

Raid, carry loot home, put it in the stash, spend it on projects at the project board, crew do the work, a building visibly changes, production and the prison's stage improve, daily upkeep and night sieges keep pushing back. The needs board at the gate shows the current shortage and which kind of place to raid for it.

## Resources

The base stock dictionary `stores` already holds food, water, ammo, meds and scrap. Add `parts` (electronics, pump and generator pieces) and `fuel`. Items in the backpack map to stock units through the existing item data; add item entries for parts and fuel cans. Storage has a cap per resource that rises with projects (larder, water tower). Food over the cap spoils, water over the cap is lost.

## Projects (data, `assets/data/prison_projects.json`)

Each building has up to three tiers. A project has: id, building, tier, cost (resource amounts), labor (crew-seconds of work at the site), required role, requires (other project tiers, power), and an effect. Cost numbers below are starting values for the tuning pass.

- Water: T1 rain barrels (scrap 10; a little water only while it rains). T2 hand pump on the well (scrap 20, parts 5; needs a worker). T3 electric pump and filter (scrap 20, parts 15; needs power tier 1 and fuel; runs with no worker). The water tower is a buffer and raises the water cap.
- Garden: T1 beds (scrap 8; crops grow on a cycle, a gardener plants and harvests). T2 irrigation (scrap 15, parts 6; needs water T2; faster growth). T3 greenhouse (scrap 30, parts 10; needs power 1; grows all year; fewer people needed).
- Kitchen: T1 stove (scrap 8). T2 larder (scrap 12; halves spoilage, raises the food cap). T3 canteen (scrap 20; meals feed more people per unit and give morale).
- Infirmary: T1 cots (scrap 8, beds +2; sick and bitten recover). T2 medicine bench (scrap 12, parts 4; meds treat bites). T3 surgery (parts 10).
- Dormitory: each tier raises bed capacity by 4 (scrap, parts). Bed capacity limits the population.
- Power: T1 generator (parts 12; burns 1 fuel a day). T2 floodlights on the towers and the fence (parts 8; night attacks are easier to see and guards hit more). 
- Fence: T1 patch every segment to full (scrap 15). T2 reinforced (+50 percent hp, scrap 30). T3 double fence (+100 percent hp, scrap 50, parts 10).
- Radio (Hub stage): T1 radio room (parts 20); later it will bring survivors and trade, but only the stage flag is built now.

Stages (shown on a card and in the HUD, and the prison looks different at each): Shelter (water T1, dormitory T1, a clean floor in the main rooms), Settlement (garden T2, kitchen T1, infirmary T1), Fortress (fence T2, power T2), Hub (radio T1 and every building at T2 or better).

## Production and upkeep

A game day is the existing day (6 minutes). Each person eats food 1 and drinks water 1 per day. Production per day: barrels 4 (rain only), hand pump 10, electric pump 24; beds 6 food, irrigated beds 12, greenhouse 20. A canteen adds 25 percent to the food value. The starting prison produces about 60 percent of what it consumes, so the first three days need loot, then projects close the gap. The HUD and the needs board show production against consumption per day, for example "Water +14 / -12". A shortage lowers morale; morale under 25 makes one person leave each night. Meals and clean rooms raise morale. Guards' ammo use is already charged from the stores. A power cut (no fuel) stops the electric pump and the lights; a fence breach can trample the garden (crop timer resets).

## Loot by place

Raid loot tables by place type: house (food, water, a little meds, scrap), shop (food, water), pharmacy and clinic (meds), hardware (scrap, parts), garage (parts, fuel, scrap), petrol station (fuel), police and army (ammo, rarely parts). Use the town generator's lot and building kinds and container kinds; where only containers and cars exist, tag by container kind. The needs board names the biggest shortage and the place type that fixes it; the raid map marks those places.

## People

Bed capacity caps the population. Rarely a survivor is found in a raid building; they join if they reach the extraction ring with you and a bed is free. Roles (gardener, cook, medic, mechanic, guard, cleaner, hauler) can be assigned in a roster panel; a project's labor is done only by someone with the required role, and a production building with no worker produces nothing (T3 pumps and greenhouse excepted). Unrest is the morale rule above.

## UI

Project board (E at the workshop bench): list by building, shows tier, cost, labor and what is missing; Start spends the cost from the stores and queues the work. Needs board (E at the gate, and a HUD line): shortages, per-day production against consumption, next attack, the suggested raid place. Roster panel (key R is taken: use B or a button on the board). Stage card when a stage is reached.

## Build split

1. Core (`scripts/prison/prison_econ.gd`, the data file, item data): resources and caps, projects and tiers, labor queue, daily production and upkeep, morale and leaving, stage rules, save-free state, a small API (`projects()`, `start(id)`, `tier(building)`, `daily()`, `needs()`). A text lab (`--econ-lab`) prints ten days with a scripted spender.
2. UI (`scripts/prison/prison_board.gd`): project board, needs board, roster, HUD line, stage card. Uses the core API.
3. World (`scripts/prison/prison_upgrades.gd`): the visible result of each tier in the compound (props, beds, garden beds, pump and barrels, generator and lights, fence look, cleaner floors), and crew doing the project work with the work poses; construction in progress shown.
4. Raids and people: loot tables by place, parts and fuel items, the needs-board raid marks, survivor finds and bed limit, and the 40 pack / 20 stores ammo start.

Merge order: core first (it defines the API), then the other three in parallel on branches cut from the merged core.
