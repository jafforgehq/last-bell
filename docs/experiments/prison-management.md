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

## Core as built (step 1, 2026-10-12)

Files: `assets/data/prison_projects.json` (every number: projects, caps, spoilage, per-person upkeep, production by tier, morale, stage rules, loot tables per place, crew-to-role map), `scripts/prison/prison_econ.gd` (the economy; a RefCounted made in `_ready` beside the siege, kept over raids, active only in phase "managed"), `items.json` (parts box and fuel can items). Pattern: plain data plus one owner object with its own signals; a Resource per project, an event-bus autoload and a state machine were rejected (the spec wants one JSON file to tune, there is one owner and four listeners, and a project's state is a word computed from built, labor done and requirements).

API (also in the file header): `projects(building="")`, `state(id)` (locked, available, queued, building, built), `can_start(id)` (ok, why, missing), `start(id)` (spends the cost from `stores`, queues the work), `tier(building)`, `stage()` (Camp, Shelter, Settlement, Fortress, Hub), `caps()`, `beds()` (used, cap, free), `daily_report()` (per resource stock, production, consumption, net, days left; morale; people; next shortage; what the last night lost), `needs()` (the biggest shortage and the place type that fixes it: food and water under three days of stock first, then what the next stage's projects still lack, resolved through the loot table `fixes`), `goal()` (project ids still missing for the next stage), `site(id)`, `add_labor(id, secs)`, `fence_mult()`, `hit_bonus()`. Signals: `project_done(id)`, `stage_changed(stage)`, `person_left(name)`, `shortage(resource)`.

Rules as built: the day changes at dawn (6:00). The tick adds production, takes 1 food and 1 water per person (all crew, kids included), loses 5 percent of the food to spoilage (half with the larder), clips to the caps, burns 1 fuel for the generator (no fuel means no power: the electric pump falls back to the hand pump and the floodlights go out), then updates morale and lets one person leave when morale is under 25 (never below 4 people; guards and kids last). Morale: shortage hits (food 40, water 50, times the unmet share, growing 60 percent per day in a row), worry when under three days of stock are left (up to 15), +3 a day when nothing is wrong, +kitchen and infirmary bonus while their worker is alive, -6 when people exceed beds. Production needs a living crew member of the building's role (gardener, hauler); labor for a project is done by the building's role too. Until the world agent calls `add_labor` from the crew's work stop, `fallback_labor` supplies it: each living worker of the role advances one queued project in game seconds. Crew stops no longer change food or water (`crew.econ_owned`); meds, ammo and scrap stops are unchanged. Fence: `siege.apply_fence(mult, patch)` rescales every segment's max hp when a fence tier is built (tier 1 mends all). Floodlights add 0.12 to the guards' hit chance at night while the generator runs.

Flags: `--econ=start:water2` builds that project (and the tiers below it) for free at the start; `--econ-lab[=days]` (use with `--managed`) runs the economy on its own clock, 30 game seconds a frame, prints one line a day and quits; `--econ-raid=0` turns the scripted raid off; `--log` prints one ECON line at each real day change. Run: `Godot --path . --fixed-fps 60 --disable-vsync -- --prison --managed --noguards --econ-lab=18`. The lab raid adds the loot of the place `needs()` names (loot tables in the JSON); the spender buys the cheapest project of the next stage's path (and anything else affordable once the path is empty, the dormitory only when few beds are free).

Tuned numbers that differ from the spec: start production food 10 and water 10 a day against 17 each (59 percent); tier totals food 10, 13, 18, 26 and water 10, 12, 16, 28 (the spec's "barrels 4, hand pump 10, electric 24" are totals per tier here, rain counted as 2 a day); costs about twice the spec for Settlement items and three times for Fortress (power 1 parts 30, power 2 parts 24, fence 2 scrap 70 and parts 6, water 2 scrap 35 and parts 10, garden 2 scrap 30 and parts 10, dormitory 1 scrap 18 and parts 5, radio parts 40); stores start with parts 2 and fuel 0; starting morale 45. Lab with a raid every day: Shelter on day 2, Settlement day 6, Fortress day 13, Hub day 19; without raids food is gone on day 6, the first person leaves on day 6 and five have left by day 11, nothing goes negative.

Open: the "clean floor" Shelter rule is not checked; `--auto=clearall` then managed starts from the clear phase's small stores (food 10, scrap 4), which the lab does not model; beds only count (the people side must enforce the limit); `person_left` takes the last non-guard crew member, which can be the well's hauler and halve the water.


## UI as built (step 2, 2026-10-12)

File: `scripts/prison/prison_board.gd` (a RefCounted made in `_ready` after the economy; it uses only the public API of `econ`). Pattern: plain Control nodes (PanelContainer cards, toggle buttons as tabs, a ScrollContainer) on one CanvasLayer in the town's colours and fonts (`ui/hud.gd` constants, `ui/fonts.gd`), as the backpack windows do; the HUD part is two lines appended to the existing HUD text and a toast stack. The window rebuilds its rows only when a signature of what it shows changes and updates progress bars in place, so a hover or an open drop-down survives.

One window with three tabs. Projects (E at either workbench): a list of the eight buildings on the left with tier built over tiers total and a plus when something can be started; on the right the building's purpose and worker, and one card per tier with name, effect in plain words, cost (red with the shortfall where the stores lack it), labor and role, the reason when locked, a Start button (disabled with the reason as tooltip) or a progress bar while it is built. Needs (E at the new sign by the gate, at tile 54,47): day and stage, the next stage and what is still to build, food, water and fuel with stock, made, used, net and days left, the other stocks, morale with a bar and the reasons, people and beds, the next attack time from the siege, and the biggest shortage with the place to raid (`needs()`). Roster (key B, or the button on the needs tab): every adult with a role drop-down (gardener, cook, medic, mechanic, guard, cleaner, hauler), what they are doing, and the count alive per role; kids have no drop-down; tower guards are locked while an attack runs. A role change writes `econ.cfg.crew_role[id]` directly, so no core hook was needed.

HUD: two lines under the stock line (stage, morale, beds, building in progress; days of food and water left and the need with its place). Toasts at the top right for project done, person left, shortage and stage change; the stage card (big stage name, what it was reached with, what comes next) fades in for about six seconds. The old message-line texts for these four signals were removed from `prison_game.gd`.

Keys: Esc closes the window (it no longer quits while the window is open), B toggles the roster, Tab and I close it and open the backpack, opening the board closes the backpack, the mouse over the window blocks the gun. Movement, E, R, F, M, wheel and 1 to 4 are unchanged. Only in phase managed, in the base.

Hooks in `prison_game.gd` (all marked `# UI hook`): the preload and `board`, its creation after the econ signals, the key call before the backpack's, `blocks_fire`, `frame`, the prompt in `_base_logic`, the `_use` dispatch, `hud_lines()` in the base HUD text, `paint` for the sign.

Staging flags: `--board=projects[:building]|needs|roster|card|toast` (opens at frame 10), `--econ=give:scrap=50,parts=20` (adds to the stores at frame 3), `--board-start=water1` (starts a project at frame 6). Example: `Godot --path . --fixed-fps 60 --disable-vsync -- --prison --managed --noguards --board=projects:water --econ=give:scrap=20,parts=5 --shot=x.png --frames=60`.

Weak: the role change is an economy fact only (the crew still walks its old route until the world step makes stops follow roles); tabs can be switched from anywhere once open, so Projects is reachable from the roster; the 1024x640 window was not checked on screen (the panel is clamped to the viewport minus 24 px and scrolls, and the backpack is closed when the board opens); clicks on Start and on the drop-down were not driven by a script.
