# Last Bell: The Thirty Days — Design (version 1)

> **Renamed 2026-10-01:** the working title is now **Thirty Bells** (a Steam game called The Last Bell is coming; see [the audit](../../audit/2026-10-01-full-audit.md)). The text below keeps the old name as written.

Status: draft for review. Branch: `feature/colony-sandbox` (`main` stays the published game until the owner says merge). This replaces the first draft of this document; that full design is kept as the appendix, as the long-term roadmap.

## 1. Vision and scope

**The game:** a compact survive-thirty-days colony defence. You lead six survivors in a walled schoolyard. Each day you decide how to spend scarce supplies, who to risk outside the walls, and how to treat the wounded. Each night the dead come in greater numbers and new kinds. Hold out until the rescue arrives on the thirtieth day.

**Why small:** the full design (the appendix) is a RimWorld-sized game. Version 1 is deliberately the smallest game that still has decisions, stories and an ending, built on what the game already has. It can be played, judged and tuned within days, and everything postponed becomes the roadmap for later updates.

**Audience and ambition:** a paid release, reached in stages: a free public demo on itch.io, then a Steam page, then Steam Early Access once the core is fun. The itch page stays private until the owner decides otherwise.

**What "great" means for version 1:**
- A first-time player can play 45 minutes after a short tutorial and wants to keep going.
- A thirty-day run produces at least three moments the player retells: a dilemma, a close call, a loss.
- Each zombie type has a counter that visibly works.
- On Standard difficulty the median run ends between day 18 and the final night.
- It holds 60 fps in the web build with 60 live zombies, and survives a ten-hour soak without a crash.

**Not in version 1** (all in the appendix, for later): rest, morale, traits and relationships; the work-priority table; free-form building, its new zombie pathfinding and rooms as stations; a full storyteller; extra scenarios, random crews, more maps and expansion; music composed for the game (placeholder ambience only until release work).

## 2. The starting point

The 2D game on `main` is about 4,100 lines of GDScript in Godot 4.7: rules in `scripts/sim` (`sim.gd`: people, zombies, the 14 wall sections with attack slots, stocks, day and night, the bell, alerts), drawing in `scripts/render`, the HUD in `scripts/ui/hud.gd`, data in `assets/data/map.json` (the map, six people with skills, posts and jobs, rooms, lights).

What version 1 builds on: the five stocks already shown in the HUD (ammo, scrap, food, water, meds), the infirmary and Ana (Medicine 10), the 14 wall sections with damage states and repair, the bell and the night spawning, and the existing orders (draft, post, repair, send).

What is missing, and so what version 1 adds: only ammo is ever spent; a downed person is out for good although the alert says "Get them to Ana"; there is one zombie type; there is no goal, no save and no start screen.

## 3. The game in one page

- **Scenario:** thirty days. The night of day 30 is the Big Night. If at least one survivor is alive at the dawn that follows, the rescue arrives and the run ends in victory. Defeat: every survivor is dead or turned (someone downed but still savable counts as alive). A run starts on day 1 at 07:00 with a quiet first day.
- **Time:** as today: a game day is 8 minutes at normal speed (one game hour is 20 seconds); speeds 1, 2, 3 and pause. A full run is about 4 hours at normal speed and 80 to 120 minutes at the speeds players use.
- **Difficulty:** Story, Standard, Brutal. It scales the night budget (0.7, 1.0, 1.4), the infection chance (30%, 60%, 100%), and how dangerous scavenging is.
- **Save and load:** manual save, and an autosave at each dawn, as versioned JSON of the rules' state. One random source with a seed per run, so a run can be reproduced in tests and shared.
- **Menus:** a start screen (new game, continue, difficulty, settings), an Esc menu (resume, save, load, settings, quit), an end screen with the run's numbers (days, kills, who lived, who turned).

## 4. The six features

All numbers are **starting values, to be tuned with the balance harness** (section 7). Times are in game hours; one game hour is 20 seconds at normal speed.

### 4.1 Supplies that matter

- **Stocks stay the five already shown:** ammo, scrap, food, water, meds. The panel also says how many days of food and water are left.
- **Eating and drinking:** at 07:00, 13:00 and 19:00 each living survivor takes a third of a food and half a water from the stores. If the stores run short the person goes hungry or thirsty: after 18 hours without food or 14 without water they work and aim 20% worse; after 36 hours without food or 24 without water they lose 1 health an hour until they eat or drink. (The longest normal gap between meals is the 12 hours overnight, so nobody is penalised while the stores last.)
- **Sources:** the vegetable beds already in the yard give 3 food each dawn; the two rain barrels already on the map give 2 water a day, or 10 on a rainy day (about one day in three); supply drops (an event in section 4.3); scavenging runs.
- **Uses of scrap:** repairs cost 1 scrap per 10 health restored, and wall upgrades (section 4.5). Repairs stop at 0 scrap, with an alert that says why.
- **Scavenging runs:** at dawn the player can send one or two survivors to one of three sites. They walk out of the gate, are away until about 16:00, and must be back before dusk.

| Site | Loot on a good run | Danger |
| --- | --- | --- |
| Pharmacy | 3 to 6 meds, sometimes food | 2 |
| Hardware store | 10 to 20 scrap, 20 to 60 ammo | 2 |
| Neighbourhood houses | 8 to 14 food, 10 to 20 water, sometimes 1 med | 1 |

Each trip is settled when the party comes back: the loot shrinks if the party is small or weak, and each member has a chance of a wound, a bite or (only at the most dangerous sites and very late) not returning, lowered by their Shooting and by a Leading party-mate. A site that has been raided is picked over for three days. The result shows as an alert with a line of text.

### 4.2 Wounds, healing and infection

- **Wounds:** a claw or bite starts a wound that bleeds 4 health an hour until bandaged. Zombies clawing at a wall can also scratch a defender standing right behind it (a lighter wound that bleeds 2 an hour and never infects), so injuries happen even while the walls hold. A bandage costs 1 meds and takes a few game minutes; the best Medicine nearby treats first (Ana, then the others), automatically, or the player orders "Treat".
- **Downed:** at 0 health a person is downed and has 3 hours to be stabilised by anyone with Medicine. They are then carried to a bed (the infirmary first), and heal 10 health an hour while resting. If the time runs out they die. The existing alert "Get them to Ana" finally works.
- **Infection:** a bite infects with the difficulty's chance (30%, 60%, 100%). An infected person turns into a zombie 12 to 24 hours later, at the spot where they stand. The panel shows only a fever stage (feverish, then delirious), not the clock. The player can **treat** (2 meds; success is 30% plus 10% per Medicine point, at most 90%, and a failed try can be repeated while the time lasts) or **send them out** through the gate. The game does not judge. A person who turns appears as a zombie with their name, and is added to the walkers.
- **Skills:** Medicine now matters (speed, success, survival of the downed); Shooting and Building keep their current effects. Melee and Leading stay unused in version 1 and are hidden from the panel until they do something.
- **Permadeath** is on by default; a setting turns it off so the downed always recover in the end.

### 4.3 Two new zombie types and rising waves

| Type | Health | Speed | What it does | Counter | From |
| --- | --- | --- | --- | --- | --- |
| Walker | 4 to 7 | 0.5 to 0.85 tiles/s | The current zombie | Anything | Day 1 |
| Runner | 3 | 1.8 | Fast and fragile: reaches the wall before the defenders are in place | Walls; shoot early | Day 6 |
| Brute | 40 | 0.4 | Does four times the damage to walls and shrugs off small rounds | Focus fire, upgraded walls | Day 10 |

- **Night budget:** `30 × (1 + 0.10 × (day - 1)) × difficulty` points a night, spent on units (walker 1, runner 2, brute 8) by day: walkers only until day 5; from day 6 up to a quarter of the budget in runners; from day 10 one brute a night and from day 20 two; the Big Night spends three times the budget and always includes three brutes. The current dusk trickle and night groups stay, driven by the budget instead of a fixed rate; the cap on live zombies is raised to 60.
- **A few random events** (about six): supply drop (a crate at the edge of the yard), storm (rain fills the barrels, shorter sight), a stranger at the gate (let in: a helper or a thief; the player decides), a straggler group at the wall in daytime, sickness in one person, a radio message (at the radio desk already on the map: a line of story, and a hint of the rescue). One event at most a day, never on the night before the Big Night.
- **Art and sound without new assets:** the runner is the walker drawn leaner, tinted and animating faster; the brute is the walker scaled up 1.35 times, darker and slow; their sounds are the current groan and thud pitched up and down. Dedicated art can replace these later.

### 4.4 A goal and an ending

The clock shows "Day N of 30". The Big Night has its own banner and alert. Dawn after it shows the rescue and the victory screen; the end screens (victory and defeat) list the run's numbers and offer "New game". Every run starts from the start screen.

### 4.5 Wall upgrades

The 14 wall sections can be upgraded with scrap instead of a free-form build system. Each has two more tiers: **Reinforced** (+50% maximum health) and **Fortified** (+120%). The cost depends on the section:

| Section kind | Reinforced | Fortified |
| --- | --- | --- |
| Chain-link, pallets | 10 scrap | 20 scrap |
| Cinderblock, car | 16 scrap | 32 scrap |
| Container, bus, gate | 24 scrap | 48 scrap |

The player selects a section and picks "Upgrade"; the survivor with the best Building skill who is free does the work (time shrinks with skill), and the section shows the change as plates and planks drawn on its art in the existing style. Brutes are the reason to do it.

### 4.6 The basics

Save and load (section 3); a start screen and an Esc menu; a short tutorial over the first three days (about eight prompts, dismissable); settings (volume, fullscreen, key help); a balance pass with the harness; a check of the web build.

## 5. Interface changes

Keep the current look and extend it: the stores panel gains "days left" lines; portrait cards show a red drop for a wound and a fever mark for infection; the person panel shows health, wounds, infection stage and Medicine, with "Treat", "Send out" and "Scavenge" buttons where they apply; the wall panel gains "Upgrade (cost)"; a scavenging dialog (site, party, back by 16:00); the start and Esc menus; the tutorial prompts; the end screens. A few new icons drawn in the existing style.

## 6. Architecture

- Keep the split: rules in `scripts/sim` never touch nodes; drawing in `scripts/render` reads their state.
- New rule modules, each small with headless tests: `supplies.gd` (meals, stocks, sources), `medical.gd` (wounds, downed, infection), `scavenge.gd` (sites, parties, results), `waves.gd` (the budget and events), `upgrades.gd` (tiers and work), `scenario.gd` (the run, goal and end), `save.gd`. `sim.gd` becomes the coordinator that steps them in a fixed order.
- Data in `assets/data`: `zombies.json`, `sites.json`, `events.json` and the upgrade table, next to `map.json`.
- One seeded random source in the rules (never the global functions), so runs and tests are reproducible.
- **Testing:** a headless test runner (`tests/run.gd`, which fails on any logged error) with tests beside each module; a **balance harness** (`tools/balance.gd`) that plays whole thirty-day games with a default AI over many seeds at simulation speed, reporting the day reached, deaths, stock curves and wave times; windowed screenshot checks for the drawing. `main` has no tests folder today; they live on this branch, and the owner decides whether they return to `main` at merge.

## 7. Rounds of work

Each round ends in a game you can play, with tests passing and a short note of what was tuned. Each gets its own implementation plan.

1. **Supplies and wounds.** Section 4.1 and 4.2, the setup of a new run (day 1 at 07:00, started by a simple command until the start screen exists), and save and load. *Done when:* a scripted ten-day run shows food and water falling and being managed; a wounded person is bandaged, a downed one is saved or lost; a bitten person can be treated or sent out, or turns; a saved game reloads to the same state; the harness shows a sensible attrition curve.
2. **Enemies and the goal.** Section 4.3 and 4.4. *Done when:* runners and brutes arrive on their days and each has a counter that works; the Big Night and the victory and defeat screens work; the harness shows median Standard runs ending between day 18 and the final night.
3. **Upgrades and the basics.** Section 4.5 and 4.6. *Done when:* a section can be upgraded and visibly changes, brutes are slowed by it, the start and Esc menus and tutorial work, and a new player can finish the first three days unaided.
4. **Balance, the demo and release prep.** Tune with the harness across difficulties; performance and the web build; an asset rights audit and a name check; music and sound plan; the public itch demo. Then decide about Steam and Early Access from what players say.

## 7b. Tuned values after round 1

Round 1 was tuned with `tools/balance.gd` (Standard, 8 games, 20 days, the default policy). Where a number differs from the text above, this table wins.

| Value | First draft | Now | Why |
| --- | --- | --- | --- |
| Night budget | 12 × (1 + 0.12 × day) | 30 × (1 + 0.10 × (day − 1)) | The original night spawner brought about 130 walkers a night from the first night, so no default crew lived past day 9; 12 would have felt empty. |
| Most walkers alive at once | 60 | 50 (30 at dusk) | As the game was before; raising it belongs with the performance work of round 4. |
| Starting food, water | 41, 120 | 36, 54 | Six days of full rations for six people, so water matters like food. |
| Starting ammo, scrap, meds | 212, 24, 7 | 300, 30, 10 | A little more runway: the first nights spend most of the medicine. |
| Hardware store loot | scrap 10 to 20, ammo 20 to 60 | scrap 12 to 24, ammo 40 to 90 | Ammo was the binding constraint around day 10. |
| Pharmacy loot | meds 3 to 6 | meds 4 to 8 | The same, for medicine. |
| Scratch from a wall claw | 4% a claw, reach 1.5 tiles | 15%, reach 2.5 tiles | With the first numbers a defender was scratched about once in ten nights. |
| Cure chance | 30% + 10% per Medicine point | 45% + 10% per point (at most 90%) | Most healers have Medicine 1 or 2, and a nurse who is herself infected cannot treat herself. |
| Scavenger lost at a danger 2 site | 2% a trip | 1% a trip | Two early deaths in five trips ended runs by luck. |
| Infection roll | each bite | once per encounter (at least one game hour apart) | Six bites in one fight would have made 30% into about 88%. |

**What the harness shows now:** a hands-off crew stays at full strength for the first ten days, then loses people as ammo and medicine run out; the median run ends on day 16 and one in eight reaches day 20. Food and water are managed (the vegetable beds, the barrels and scavenging keep them level); scrap is spent as fast as it comes; ammo has no source yet except the hardware store, which is what round 3's workshop is for.

## 7c. After round 0 (2026-10-01)

Round 0 made the numbers bind (plan: `docs/superpowers/plans/2026-10-01-round-0.md`; findings: `docs/audit/`). **A correction to 7b:** the note "ammo was the binding constraint around day 10" was wrong. The stock went down when someone shot, but nothing stopped the shooting, so a crew with 0 ammo killed exactly as many walkers as one with 300. Now a shot needs a whole shot in the stock; with less the gun is silent, people fight with the butt of it (a pike never runs dry) and an alert says so. Ammo is therefore a real limit, and the values were retuned on top of that.

The harness got a second policy, `--policy=keep` (everyone hides in the school gym from the bell to dawn and does the default daytime jobs), because the audit found that hiding in the school beat everything: all six alive and unhurt on day 20 in 3 of 3 seeds, since the dead could not enter the building at all. The school now has two attackable boarded doors; the dead go for them once the yard has fallen and someone is inside, a door that is down opens the building, and the dead in the yard ruin a share of every stock each second (the stores are in the yard).

| Value | Before round 0 | Now | Why |
| --- | --- | --- | --- |
| Shot cost | free | 0.2 ammo (shotgun 0.34) | Ammo has to bind. |
| Starting ammo | 300 | 400 | The first nights with real ammo. |
| Hardware store loot | scrap 12 to 24, ammo 40 to 90 | scrap 14 to 28, ammo 70 to 130 | The only source of both. |
| Pharmacy loot | meds 4 to 8 | meds 6 to 11 | Medicine became the limit once ammo was real. |
| Houses, medicine on the side | 0.35 to 1 | 0.5 to 1.5 | The same. |
| Scratch from a wall claw | 15% | 11% | Fewer scratches means fewer bandages and fevers. |
| School doors | none (the building was sealed) | 2 doors, 160 HP, 10 places each | Hiding must not be free. |
| Stores ruined by the dead in the yard | none | 1.0e-4 of each stock a second per walker inside | Falling back has a cost and a clock. |
| The dead leaving at dawn | all in one step | 6 a step | Each is a path search. |
| Victory | none | at the dawn that starts day 31, if anyone is left | A goal. |

**What the harness shows now** (Standard, 20 days, 8 games per row):

| Crew | Seeds 1-8 | Seeds 9-16 |
| --- | --- | --- |
| Gives no orders (`--policy=none`) | median day 12, 0 of 8 reach day 20 | not run |
| The default policy (posts, repairs, scavenging, treating) | median day 19, 3 of 8 | median day 19, 3 of 8 |
| Hides in the school from the bell to dawn (`--policy=keep`) | median day 18, 3 of 8 | median day 16, 2 of 8 |

Before round 0 the same default policy reached day 17 with 0 of 8 (and ammo that did nothing), and the hiding crew had all six alive and unhurt on day 20 in every seed tried; with real ammo and the old numbers the default policy fell to day 14 to 15. Hiding no longer wins, but the harness's default crew is naive (it never repositions anyone), so the margin is modest; the informed policy of round 2 should widen it.

## 7d. After round 2 (2026-10-01)

Round 2 made the night something to read and solve (plan: `docs/superpowers/plans/2026-10-01-round-2.md`). The dead now come in three kinds, a night has a plan that the lookout can forecast, the player can see where the guns reach, steer the dead with an alarm and hand the chores to standing orders, and the thirtieth night is a climax.

- **Kinds** (`scripts/sim/kinds.gd`). Walker as before. **Runner** from night 4: hit points 2 to 4, speed 1.5 to 2.1, claws a wall at 0.8, never limps, counts 2 in a night's budget. **Brute** from night 8: hit points 22 to 30, speed 0.42 to 0.6, claws a wall at 3.5 times a walker, counts 9. Runners are 6% of a night's budget on night 4, rising 3 points a night to 30%; brutes 8% on night 8, rising 2 points a night to 20%. A kind that has started brings at least one. The guns shoot a brute before a runner before a walker.
- **Tonight's plan** (`waves.gd`). At dusk the night gets a queue of kinds and one or two main spawn points that bring 65% of the dead; the brutes are placed in the later 60% of the night. The plan comes from a generator seeded by the run's seed and the day, never from the rules' own dice, so the forecast at 17:00 and the dusk that spends it agree, and a loaded game carries on with the same night.
- **The forecast** (`tactics.gd`). At 17:00 the lookout (Marcus), if he is alive, here and up, reports a number (within 15%), a direction and whether runners or a brute are among them. Without him the crew gets "No forecast".
- **The alarm.** A wall section can be set as the alarm (key L): 3 scrap, three game hours, one at a time, not on the school doors. Its places score 40 tiles better when the dead choose where to go, and 70% of those already on their way and not yet at a wall switch to it when a place is free.
- **Standing orders.** Auto-repair (key B) mends the most worn section under 70% by day while the stock has 5 scrap or more; Dez and Hector start with it on. A repair now mends 5 points a second plus the person's Building skill (was a flat 9), so Dez does 14 and Marcus 6.
- **Fields of fire** (key V, view only). Each wall section shows how many guns reach at least half its places from where their owners stand at night: none red, one amber, two or more green.
- **Decks.** A person on a walkway or a tower is scratched by a wall claw a fifth as often as one on the ground (11% becomes about 2%).
- **The Big Night.** Night 30 brings 2.4 times its budget, 30% of it runners and 25% brutes, with up to 90 of the dead alive at once; a banner and an alert say so at dusk, and the dawn is the victory.

| Value | Before round 2 | Now | Why |
| --- | --- | --- | --- |
| Starting scrap | 30 | 40 | With brutes tearing walls the stock was gone by day 5. |
| Hardware store scrap | 14 to 28 | 18 to 34 | The same. |
| Repair speed | 9 a second | 5 + Building | Skill should count. |
| Scratch on a deck | 11% | 11% of 20% | The raised places have to be worth something. |

**What the harness shows now** (Standard, 30 days, 8 games per row):

| Crew | Seeds 1-8 | Seeds 9-16 | Both |
| --- | --- | --- | --- |
| Gives no orders (`--policy=none`) | median day 11 | not run | |
| The default policy | median day 16.5 | median day 17 | **17**, best 27 |
| The informed policy (reads the plan, places the guns, sets the alarm) | median day 22 | median day 24 | **24**, none reaches 30 |

The informed crew outlasts the default one by seven days, so knowing the night pays. On Story (the dead at 0.7 times) the informed policy wins 5 of 8 games and the default one 2 of 8, and the Big Night is what ends the runs that reach day 30 and fall. What ends a Standard run: the default crew is out of scrap from about day 6 (the walls stop being mended and fall); the informed crew has the walls and runs out of ammo (about 1000 to 1150 kills, empty around day 22 to 26). Ammo has no source except the hardware store, so the workshop of round 3 is where the Standard win comes from.

## 8. Risks and open questions

- **Balance and feel:** infection, scavenging and the wave curve are where a run can feel unfair or dull. The harness and difficulty levels are the safety valves; early playtests matter.
- **Art consistency:** new art is limited to tints, scales, plates and a few icons in version 1; decide later between extending the drawing code and commissioning an artist for dedicated zombie art.
- **Rights:** before any paid release, list every sound, font and image with its licence or origin and replace anything unclear. Check that the name "Last Bell" is free to use on Steam and in trademark databases.
- **Music:** none exists; decide between a composer and licensed tracks before release.
- **Steam and platform work** (Steamworks, achievements, cloud saves, controller and Steam Deck support, store page assets): research current requirements and fees before round 4.

---

## Appendix: the full design (long-term roadmap)

This is the first, larger draft. Version 1 implements the subset above. Where the two differ (for example antibiotics, which version 1 replaces with meds), version 1 wins. Everything here is a candidate for later updates.

### 1. Vision

Last Bell becomes a **colony-defense sandbox with a storyteller**: you lead a small group of survivors in a walled schoolyard, keep them fed, healthy and sane, build up the defences, and survive escalating zombie hordes until a rescue arrives on a final day.

Inspirations, for the feel and not the content: RimWorld (people with needs and traits, a storyteller that paces events, stories that come out of the systems), They Are Billions (base defence against escalating hordes, a survival map that ends in a huge final wave), Prison Architect (placing structures, rooms that do something, management UI).

**Audience and ambition:** a paid release, reached in stages: a free public demo on itch.io, then a Steam page, then Steam Early Access once the core is fun. Until the owner decides otherwise, the itch page stays private and `main` stays the published game.

**What "great" means here** (how we will know):
- A first-time player can play 45 minutes after a short tutorial and wants to keep going.
- A 30-day run produces at least three moments the player remembers and retells: a dilemma, a close call, a loss.
- Defence is a puzzle: each zombie type has a counter, and what the player builds changes how the dead move.
- Losing feels earned, and the median run on Standard difficulty ends between day 18 and the final night.
- 60 fps on a 2020 laptop in the web build with up to 120 live zombies; no crash in a ten-hour soak.

**Non-goals for now:** 3D or first person (tried and dropped), multiplayer, mobile, mod support, a roguelite unlock tree, a large open world.

### 2. What exists today (the starting point)

The 2D game on `main` is about 4,100 lines of GDScript in Godot 4.7.

| Part | Where | Notes |
| --- | --- | --- |
| Rules | `scripts/sim/sim.gd` (835 lines), `pathfinder.gd` | Everything in tile units, one tile about a metre. `Person`, `Zombie`, `Segment` (14 damageable wall sections with attack `Slot`s), `stock` (ammo, scrap, food, water, meds), day and night phases, the bell at 19:00, night spawning (up to 50 alive), alerts and events. |
| Drawing | `scripts/render/*`, `scripts/world.gd` | Sprites in draw order, PointLight2D lighting, fire, effects. Art is baked PNGs in `assets/`, made by code from the original web prototype. |
| HUD | `scripts/ui/hud.gd` (1,031 lines) | Stores panel, portrait cards, clock, alerts, gizmos (draft, post, repair, focus), speed controls, help. |
| Data | `assets/data/map.json` | Map 84×64 tiles, terrain, solid grids, 376 objects, wall sections, lights, rooms (hall, gym, bunks, infirmary, kitchen), spawn points, six people with skills, posts and jobs. |
| Sound | `scripts/audio/sound.gd`, `assets/audio` | One-shots and ambience loops. No music. |

**Strong:** readable art and lighting, six named people with faces and roles, the bell, day and night rhythm, walls that take damage and are repaired.

**Thin (the work of this design):**
- Only ammo is ever spent. Food, water, scrap and medicine are shown but nothing uses or produces them.
- Only Shooting and Building are used; Melee, Medicine and Leading are just numbers.
- A downed person is out for good; the alert says "Get them to Ana" but nothing revives anyone. The infirmary, kitchen, bunks and gym on the map do nothing.
- One zombie type, no director, no goal, no save.

### 3. Structure of a game

- **Scenario:** "The Long Night": survive 30 days. The night of day 30 is the final wave; if the compound and at least one survivor hold until dawn, the rescue arrives and the run ends in victory. Defeat: every survivor is dead or turned (someone who is downed but can still be stabilised counts as alive). Later scenarios change the start (crew, stocks, length, map).
- **Time:** as today, a game day is 8 minutes at normal speed (3 game minutes per second); speeds 1, 2 and 3 and pause-and-plan. A 30-day run is about 4 hours at normal speed and 80 to 120 minutes at the speeds players will use.
- **Difficulty** (chosen at start): Story (forgiving), Standard, Brutal. It scales the director's budget, supply drops and how harsh injuries and infection are. Permadeath is on by default; a setting turns it off, so the downed always recover in the end.
- **Save and load:** manual and an autosave at each dawn. Versioned JSON. A run can be resumed after closing the game.
- **Seeds:** every run has a seed; the director, survivor generation and events all use one seeded random source, so a run can be reproduced in tests and shared.

### 4. People and survival

Everything here is a **starting value, to be tuned by the balance harness** (section 9).

#### 4.1 Needs

Each person has four needs from 0 to 100.

| Need | Falls by | Restored by | When low |
| --- | --- | --- | --- |
| Hunger | 1 food unit a day, eaten at meal times (07:00, 13:00, 19:00) | Eating food or a cooked meal | Below 25: slower work, worse aim. At 0: loses health, morale drops fast. |
| Thirst | 1.5 water units a day | Drinking | Same, and twice as fast to become deadly. |
| Rest | About 6 points an hour awake | Sleeping in a bunk (fast) or on the floor (slow) | Below 25: mistakes (slower, misses more). At 0: collapses asleep where they stand. |
| Morale | Set by modifiers (below) | Modifiers recover with time | Below 25: shaken (aim and work penalties). Below 10: breakdown for one to two hours (freezes, flees or wanders). |

Morale modifiers: a hot meal (+), a bed (+), a leader nearby (+, scales with Leading), zombies at the wall (−, worse at night, worse for the Nervous), someone hurt or dead (−, bigger for friends), a recent kill streak or repaired wall (+), sleeping on the floor (−), a dirty infirmary (−).

#### 4.2 Supplies and the economy

Stock items: **ammo, scrap, food, water, meds** (bandages), **antibiotics**, and **meals** (cooked food). Starting stock follows today's numbers and is tuned later.

| Source | Gives | Needs |
| --- | --- | --- |
| Garden plot | Food, slowly (about 3 a day per plot at full attention) | A builder to place it, a person with the Garden job |
| Rain barrel | Water when it rains | Scrap to build |
| Kitchen (stove) | Turns 1 food into 1 meal; a meal feeds as 1.25 food and gives morale | A cook |
| Workshop (bench) | Scrap to ammo (2 scrap to 10 rounds), scrap to bandages | A crafter |
| Scavenging trip | Loot from a nearby site | See below |

**Scavenging trips (abstract, not a second map).** At dawn the player can send one or two survivors through the gate to a site from a list of nearby places (a pharmacy, a hardware store, a bus depot, a neighbour's house), each with a loot type, a distance and a danger. They are away for a number of hours, must be back before dusk, and the result is settled by skills, gear and luck with a short event text; they can come back with loot, hurt, bitten, or not at all.

#### 4.3 Injuries, healing and infection

- Each person has health 0 to 100. Claws and bites cause **wounds**: a wound bleeds a little health an hour until bandaged. A bandage costs 1 meds and takes a person with Medicine a short while; skill changes the speed and the chance of a clean job.
- At 0 health a person is **downed** and starts a bleed-out timer of one game hour. Someone with Medicine can stabilise them; they are then carried to a bed (best in the infirmary) and heal slowly. If the timer runs out, they die.
- A **bite** infects the person with a chance set by difficulty (Story 30%, Standard 60%, Brutal 100%). An infected person turns into a zombie between 12 and 24 game hours later unless treated with antibiotics (the chance depends on Medicine). The player sees the timer only as a fever stage (chills, sweating, delirium), not an exact clock. The player decides what to do: treat them, tell them to keep away from the others, or send them out through the gate. The game does not judge.
- A turned survivor appears as a zombie at that spot, with the survivor's name, and the crew who knew them take a morale hit.
- **Permadeath** is on by default. When someone dies, friends and family take a morale penalty and the portrait card shows a memorial.

#### 4.4 Skills, traits and relationships

- **Skills** 0 to 10 (as today) all matter and grow with use (slowly, with diminishing returns):
  - Shooting: accuracy and rate of fire.
  - Melee: damage and speed with melee weapons and when cornered.
  - Building: build and repair speed, and quality.
  - Medicine: treatment speed and success, survival of the downed.
  - Leading: morale aura within about 8 tiles, and calmer under pressure.
- **Traits:** each person has two or three from a launch list of about 14 (for example Nervous, Tough, Insomniac, Optimist, Claustrophobic, Green thumb, Steady hand, Heavy sleeper, Loner, Quick learner, Cook, Coward, Hothead, Gentle). Traits give modifiers to needs, morale, skills or behaviour, and they are visible on the person's panel.
- **Relationships:** each survivor has one or two links to others (friend, rival, family) defined in data. Links change who takes the loss hardest and who works well together.
- **Crew generation (later):** in scenario starts a random crew is drawn from a pool of survivors with their own skills, traits and links.

#### 4.5 Jobs

Work types: **Doctor, Cook, Build and repair, Scavenge, Haul, Garden, Craft, Guard.** Each person has a priority from 0 (never) to 4 (first) for each, set in a small table, with sensible defaults from their role. Each tick an idle person takes the highest-priority job that is available and reachable. **Guard** is automatic at night for people with Shooting, unless they are too tired. The existing orders stay: draft a person, send them somewhere, post them at the wall, order a repair.

### 5. Threats and the director

#### 5.1 Zombie types

| Type | Health | Speed | What it does | Counter | Appears from |
| --- | --- | --- | --- | --- | --- |
| Walker | 4 to 7 | 0.5 to 0.85 tiles/s | The current zombie; claws at walls and people | Anything | Day 1 |
| Runner | 3 | 1.8 | Fast and fragile; arrives before the defences are manned | Walls and traps; hard to shoot in time | Day 6 |
| Brute | 40 | 0.4 | Does four times the damage to structures; shrugs off small rounds | Focus fire, spike strips, fire | Day 10 |
| Screamer | 4 | 0.6 | Screams every 20 seconds: zombies within 40 tiles head for the noise and move 20% faster | Kill it first; sneak past | Day 8 |
| Crawler | 6 | 0.6 | Low to the ground: much harder to hit; slips under low barricades | Melee, spike strips | Day 12 |

Values are starting points. Each type has its own drawing (sprites in the existing style), sound, hit reaction and state machine in data.

#### 5.2 The director (storyteller)

- **Night waves.** Every night the director has a **threat budget**: `base × (1 + 0.12 × day) × difficulty × (1 + 0.5 × colony strength)`. The base is 12 points (about twelve walkers on the first night), difficulty is 0.7, 1.0 or 1.4 (Story, Standard, Brutal), and colony strength is a number from 0 to 1 that grows with able people, their combined Shooting, wall health and what has been built. It spends the budget on units (walker 1, runner 2, crawler 2, screamer 4, brute 8) in a composition set by the day and the storyteller.
- **Day events** (about 12 at launch), drawn from a weighted table with cooldowns:
  - Threats: extra horde at dusk, daytime stragglers at the wall, fire in a tent or barrel, a structure weakens.
  - Hardship: sickness in one person, a heatwave (thirst ×1.5), a breakdown, theft of food.
  - Opportunity: a supply drop (a crate at the edge of the yard), a storm (rain fills barrels, sight is shorter), a stranger at the gate (join, steal or trap; the player decides), a radio message (lore, and hints at the rescue timeline).
- **Tension:** a hidden tension value rises with threat events and falls with time and rest; the director avoids stacking spikes. The player picks the **style** at the start: Calm (fast recovery, few spikes), Steady (balanced), Brutal (frequent, doubled spikes).
- **Final wave:** the night of day 30 spends three times the usual budget and always includes brutes and screamers.

### 6. Building and the compound

#### 6.1 Build mode

Press B (or use the build menu): place blueprints on free tiles of the compound. Builders (the Build job, scaled by Building skill) carry scrap to a blueprint and build it; it can be cancelled or deconstructed for a partial refund. Structures at launch (costs are starting values):

| Structure | Cost | Notes |
| --- | --- | --- |
| Wooden barricade | 4 scrap | 120 health |
| Sandbag wall | 6 scrap | 160 health, low: shooters fire over it |
| Metal wall | 12 scrap | 300 health |
| Gate | 15 scrap | Opens for people, blocks the dead |
| Spike strip | 5 scrap | Damages the dead that cross it; wears out |
| Noise trap | 3 scrap | Draws the dead away for about a minute |
| Watchtower | 25 scrap | Platform with longer sight and cover |
| Rain barrel | 4 scrap | Fills when it rains |
| Garden plot | 2 scrap | Grows food |
| Bunk | 6 scrap | Rest |
| Stove | 10 scrap | Kitchen |
| Med table | 8 scrap | Infirmary |
| Workbench | 10 scrap | Workshop |

The 14 existing wall sections (containers, buses, cars, pallets, chain-link, cinderblock, the gate) stay as pre-built structures, with their damage states, and work with the same rules as the new ones.

#### 6.2 How the dead move (changes the rules)

Today the dead walk to fixed attack slots on predefined wall sections. With player-built structures this must generalise: the zombie pathfinder runs on a cost map in which a structure is **passable at a cost equal to its health**, so the dead go around through an opening if one is cheap and otherwise break through the weakest or cheapest line. They attack whatever blocks the path. This gives chokepoints, gates and kill corridors and is the core of the defence puzzle. Attack slots become simply positions around a blocking structure.

#### 6.3 Rooms that work

The map's rooms get a purpose. A room becomes effective when it has its furniture, and its effectiveness scales with how much:
- Infirmary: a med table and beds; speeds healing and treatment.
- Kitchen: a stove; makes meals.
- Bunks: beds; faster rest and better morale.
- Workshop (new room): a workbench; crafting.
- Gym: equipment (later); slow skill growth and morale.
- Hall: the common room; a meal together lifts morale.

#### 6.4 Noise and light

Gunfire, hammering, screams and traps make noise that the dead walk toward. Light is partly cosmetic: lamps and fires help morale at night (less fear) and the player's view; a floodlight structure comes with a power system later.

#### 6.5 Expansion (later)

Reach neighbouring buildings to clear and claim them for more space and supplies. Out of scope for the first releases.

### 7. Interface

Keep the current look (dark panels, the same type and colours) and extend it:
- **Stores panel:** ammo, scrap, food, water, meds, antibiotics, meals, with a line for days of food and water left.
- **Portrait cards:** small icons for hunger, thirst, rest and mood; a red dot for a wound; a fever mark for infection.
- **Person panel:** needs, mood and its reasons, health and wounds, skills, traits, relationships, the work-priority table.
- **Build menu** (bottom) with costs and a blueprint cursor; rooms highlight what they lack.
- **Event log and alerts** as today, with choices for events that ask for a decision.
- **Scavenging dialog** (sites, party, return time) and a **storyteller indicator**.
- **Menus:** new game (scenario, difficulty, storyteller, seed), save and load, settings (volume, fullscreen, key help).
- **Tutorial:** a guided first three days, dismissable.

### 8. Architecture

- **Keep the split** between the rules (`scripts/sim`) and the drawing (`scripts/render`). The rules never touch nodes; the drawing reads the rules' state. This is what makes the rules testable without a window.
- **New rule modules** in `scripts/sim`, each small and with headless tests: `needs.gd`, `medical.gd`, `jobs.gd`, `economy.gd`, `rooms.gd`, `build.gd` (blueprints, structures, the cost map), `scavenge.gd`, `director.gd`, `events.gd`, `scenario.gd`, `save.gd`. `sim.gd` becomes the coordinator that steps them in a fixed order; it is split as it grows.
- **Data-driven content** in `assets/data`: `zombies.json`, `structures.json`, `traits.json`, `events.json`, `sites.json`, `scenarios.json`, next to `map.json`. Adding a zombie type, a structure or an event should be a data change plus art and sound.
- **One seeded random source** in the rules; never the global random functions.
- **Save format:** versioned JSON of the rules' state (people, zombies, structures, stocks, director state, clock, seed). Loading rebuilds the drawing from it. A round-trip test guards it.
- **Testing:** a headless test runner (`tests/run.gd`, which fails on any logged error) with tests next to each module; a **balance harness** (`tools/balance.gd`) that plays whole 30-day games with a default AI across many seeds at simulation speed and reports the day reached, losses, stock curves and wave times, used to tune the numbers in this document; windowed screenshot checks for the drawing.
- **Performance budget:** up to 120 live zombies, 60 fps on a 2020 laptop in the web build; drawing is culled to the camera, animation slows at a distance, and the zombie pathfinder uses a shared flow field rather than one path each.
- **Art and sound:** new sprites (zombie types, furniture, structures, icons) follow the existing illustrated style by extending the drawing code; new sounds match the current set. Music is needed for release.

### 9. Milestones

Each milestone ends in a game you can play, with tests passing and a short note of what was tuned. Each milestone gets its own implementation plan; this document is the umbrella. Work happens on `feature/colony-sandbox`.

1. **Survival.** Needs and their effects; stocks used and produced, from a garden and rain barrels placed in the map data and from simple scavenging trips (three sites); injuries, bleeding, bandages, the downed and bleed-out; infection and treatment; all five skills used and growing; traits and relationships; the work-priority table (Doctor, Cook, Garden, Repair, Haul, Guard, Scavenge; Build and Craft join in milestone 3); the infirmary, kitchen and bunks working as rooms using the furniture already on the map; save and load with autosave; the new panels. *Done when:* a scripted ten-day run shows food and water falling and being managed, a bitten person can be saved or lost, a save reloads to the identical state, and the balance harness reports a sensible attrition curve.
2. **Threats.** The four new zombie types with art and sound; the director (budget, events, tension, styles); the 30-day scenario with its final wave, victory and defeat screens; difficulty levels. *Done when:* the harness shows median Standard runs ending between day 18 and the final night, and every zombie type has a counter that visibly works.
3. **Building.** Build mode with blueprints and builders; the structures table; the generalised zombie pathing and breakable structures; traps; the workshop and crafting; more scavenging sites, gear and risks. *Done when:* a player can wall off the gate, leave a gap, and watch the dead funnel through it, and can build a new garden or bunk that is used.
4. **Scenarios and variety.** New-game menu; two more scenarios; random crews from a survivor pool; more events and traits; a second map or map variant; the tutorial.
5. **Polish and release.** Balance pass with the harness; interface pass; music and sound; performance and web build; settings and accessibility basics; controller support to be decided; an asset rights audit and a name check; the public demo on itch; then the Steam page and Early Access decision.

### 10. Risks and open questions

- **Scope.** This is a large game. Mitigation: milestones that each stand alone, the harness to tune early, and a go or no-go after the demo.
- **Art consistency.** New sprites must match the existing look. Decide between extending the drawing code and commissioning an artist for the set of zombie types and furniture.
- **Rights.** Before any paid release: list every sound, font and image with its licence or origin; replace or clear anything unclear. Check that the name "Last Bell" is free to use on Steam and in trademark databases.
- **Music.** No soundtrack exists; decide between a composer and licensed tracks.
- **Steam and platform work** (Steamworks, achievements, cloud saves, Steam Deck and controller support, store page assets): research current requirements and fees before milestone 5.
- **Balance and feel.** Infection, morale and the director are the parts most likely to feel unfair or dull; playtests and the harness catch this early, and the difficulty levels and storyteller styles are the safety valves.
- **Tests on `main`.** `main` currently has no tests folder. They live on this branch; the owner decides whether they go back to `main` at merge.
