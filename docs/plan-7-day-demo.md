# Plan: a seven-day demo

Written 2026-10-09 for the owner. Nothing here is started. I read the request "next step is to have a demo for 7 days" as: the demo should cover SEVEN IN-GAME DAYS (today it ends at the dawn after the first attack night, about 23 real minutes). If it meant a seven-day public TEST WINDOW instead, see the last section.

## Where we are

- The run ends in `scripts/town/one_house.gd` ("THE END"): from the dawn after the first attack night, as soon as the data's `held_rule` is true (a leader alive, no dead in the house, a section of the base still standing), `sim.over = "victory"`. The end card is `scripts/ui/town_end_card.gd`.
- The dead attack every night once two survivors are home (`attack.from_rescue` 2). Later nights already come from the night machinery (`assets/data/one_house.json`: `night.first` 1.85, `night.growth` 0.15, `surges`, `big_night` only for the first night).
- The lab (`tools/house_lab.gd`) already plays "up to day 7" headless, with a bot and an idle avatar, and reports the first attack night. It does not report nights 2 to 7.
- Time: a game hour is half a real minute, so a day is about 12 real minutes at 1x (6 by day, 6 by night); sleeping skips quiet nights but is refused on an attack night. Seven days with attack nights from day 2 would be about 70 to 90 real minutes at 1x and about 45 to 60 with the speed keys and "wait for the bell".
- Never tested beyond night 1: fence damage and repair over several nights, the food, water and ammo economy over days, injuries, deaths of survivors, more rescues, what the player does with a full day after the base is built.

## Target

- Days 1 to 7. Day 1: arrive, claim, build, two rescues. Nights 2 to 7: six attack nights, rising. The demo is won at the dawn after night 7 (configurable: `end.nights_to_hold`).
- 50 to 75 real minutes for a normal player (45 to 90 acceptable).
- A bot that plays well wins at least 80 percent of runs through night 7; an idle avatar fails by night 3 or 4 almost always (the player matters); no night is a coin flip between "trivial" and "impossible" across seeds.

## Steps (each ends in a gate; nothing starts without the owner's go)

### 1. Measure what exists (about half a day of work)
- Make the lab report every night (held or not, wall damage, ammo, food, water, crew alive and hurt, dead counts) for nights 2 to 7 with the end rule switched to "hold N nights" (`end.nights_to_hold`, default 1 so today's game does not change).
- Run seeds 1..64 with bot and idle to day 8. Output: a table per night (held percent, median ammo, food, water, scrap, crew alive).
- Gate: we know where the current game breaks (ammo runs out? food? the fence? boredom?).

### 2. Design the arc (data and a short spec, about half a day)
- Night curve: night 2 and 3 grow on today's first night; night 4 a surge with two plated brutes; night 5 runners and a storm; night 6 a siege from three streets; night 7 the finale (the biggest, a storm, brutes, a final push at dawn). Numbers in `one_house.json`, one row per night.
- Day rhythm: a morning summary (already one card), 1 or 2 new survivors reachable each day until the crew is 5 or 6, new base projects as the crew grows (the nine base kits unlock by crew size: check the unlocks reach day 7), scavenging districts farther out each day (cars, shops, the new building plans) so supplies last.
- Economy: food and water at a rate that makes scavenging a choice on day 4 to 6, ammo that never strands a player who scavenges, scrap that keeps the fence in repair.
- Gate: a one-page arc table the owner reads and approves.

### 3. Build what the arc needs (2 to 4 days, split in parallel)
- Night data and the end rule for N nights, an end card for seven days (stats of the whole run: nights held, the dead put down, who is alive, who was lost, the base's state; "Play again with a new seed").
- Mid-run content, only what the lab shows missing: repairing fences cheaply, a second ring of fence sections, a medic and meds loop, daily survivor arrivals with a short line each, night events (the storyteller has fog and blackout looks), a radio news line per day.
- Enemy variety only if nights 5 to 7 feel samey: one or two new kinds (a spitter or bloater with a pattern), cosmetic differences otherwise.
- Gate: the lab runs seeds 1..64 through night 7 with the targets above.

### 4. Pace and polish pass (1 day)
- Real-time per day with the speed keys, "wait for the bell" and sleep; trim dead time (the morning, the walk to scavenge houses); a clear "what next" line each day in the objective.
- Autosave at every dawn (exists) and a safe Continue (old-save guard exists).
- Gate: a bot's real-minute distribution is 45 to 90 minutes in at least 85 percent of runs.

### 5. Human checks (the owner's days)
- You play days 1 to 7 once with sound on and write ten notes. I fix the top five.
- Then 3 to 5 outside testers, ideally recorded. Fix the top five again.

### 6. Build and publish
- Export, check in headless Chrome and in the local itch embed mimic, upload to itch (restricted page, replace in place), update the page text and screenshots, push to GitHub.

## Timeline (agent work, in parallel where possible)
Day 1: steps 1 and 2. Days 2 to 4: step 3 (3 to 4 builders). Day 5: step 4 and the first full run for you to play. Days 6 to 7: your notes, fixes, outside testers. Then step 6.

## Risks
- The economy is untested for seven days: the largest risk and the reason for step 1.
- A longer demo gives more places to be boring: the arc must change something every day (a new survivor, a new project, a new enemy pattern, a new weather).
- Old saves: any change to the generated town or the saved meaning must bump `TownGen.VERSION` (docs/save-compat.md).
- Test refresh: 48 stale tests are being updated in `.worktrees/ph4-tests`; new work should land after that merge to keep the suite meaningful.

## If you meant a seven-day public test window
- Day 0: publish the build and the page (restricted), invite 5 to 10 testers with a short note (what to try, how long it takes, how to report).
- Add a "Send feedback" line in the pause menu that opens a form or mail link (an owner's choice of address), and ask for three things: where you got stuck, where you were bored, where you died.
- Days 1 to 3: read feedback daily, fix only blockers. Day 4: a build with the top fixes. Days 5 and 6: more testers. Day 7: review, decide.
- No analytics exist in the web build today; feedback is by hand unless we add a small anonymous counter (needs the owner's go).
