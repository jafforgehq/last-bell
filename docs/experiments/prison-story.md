# The prison's story arc: 30 days, a convoy, an ending (round 12)

Owner request (idea 13): the game needs a point. After the prison is secured the managed phase is a 30-day arc with a goal, a calendar, a story told over the radio and endings with a score. Everything the arc says or counts is data in `assets/data/prison_story.json`; the code is `scripts/prison/prison_arc.gd` (rules and numbers), `prison_story.gd` (cards, banner, log), `prison_endings.gd` (end cards, score, record), `prison_arclab.gd` (the scripted 30 days). Free tools only (no services, no new assets: the cards are drawn in code).

## The story

The survivors hold an old prison. A fragile radio signal from Harbor Relief promises a convoy (a bus and two trucks) that will pass the river road on **day 30**, stop at your gate at 11:00 and wait until 15:00. To be taken you need fuel, parts, a truck of your own, a radio room, a fence that holds, and as many people alive as you can keep. Voices: a woman at Harbor Relief (day 1 and 3), a work crew that dies on the air (day 7), a warm voice that may be a lure (day 12), Halloran, the convoy's man (day 18, 24, 28 and 30).

| Day | Beat | What it does |
| --- | --- | --- |
| 1 | **Static** (first contact) | Harbor Relief, calling any station. |
| 3 | **A convoy** (rumour) | A convoy is coming up the river road, no date. +4 food. |
| 7 | **The ferry depot** (distress, set piece) | The next raid marks a cache (fuel 8, parts 9, meds 4, ammo 18) at the far end of the town, with a note in it. A pulsing ring and the name show on the map. |
| 12 | **The dam** (a lie on the radio) | Choice: send the truck (it was a lure: -6 fuel, -20 ammo, -8 morale) or keep the gate shut (-4 morale). A result card says what happened. |
| 18 | **The arrangement** (the demands) | Halloran confirms day 30 and the list. Opens Phase III. +4 parts. |
| 24 | **The storm** | Day 24 is a storm: dark, no power at night (floodlights off), the night's dead x 1.2. |
| 28 | **Two days** (final preparations) | The card ends with the list as it stands ("still missing: ..."). |
| 30 | **The convoy** | At 11:00 the convoy is at the gate: a card with the list, the seats and two answers: load up and go, or stay and hold the fort. |

Each beat is a radio-static card (a typewriter text under moving static, signal bars, scan lines), shown once, in a quiet moment (daylight, no night attack, no raid, no window open). Space finishes the typing, then continues; a choice is answered by the keys 1 and 2 or the buttons. The game is paused while a card is open. **L** opens the log of everything received (also the Story tab of the board): the calendar, the phases, the convoy's list with progress bars, tonight's size, the messages newest first.

Letters: about one raid in four hides a `note` item in a random container (rare, small, 1 cell). Back at the base it is read (a card in the letter style, a small reward or a clue line) and joins the log. 12 letters, never repeated.

## The goals

The objectives tracker (key O) shows, under the urgent line, the phase line `Phase II: Prepare - day 12 of 30 (18 left to the convoy)` (red when the phase is later than its `by_day`) and, from day 3 (the rumour), one line for the convoy's list: `Convoy list: 2 of 5 ready. Parts 151 in all, 120 still to find`, with a bar for the parts. From the day the convoy confirms (18) or when Phase III is reached the two missing items of the list follow, each with a thin bar. The parts total counts the projects on the list's path (generator, radio room, fence tier 2, convoy truck) that are not built yet plus the parts handed over, less what is in the stores. The convoy chip's hover shows the same total. The top bar's clock reads **Day 12 of 30** (gold "CONVOY" on day 30), and a new chip **Convoy: day 30, in 18 d** (amber with 7 days left, red with 3) carries a meter of the list and a hover with every item.

* **Phase I: Establish** (by day 7): stage Shelter (water, dormitory).
* **Phase II: Prepare** (by day 20): Settlement and Fortress (garden 2, kitchen, infirmary, fence 2, power 2).
* **Phase III: Evacuate**: the convoy's list. Required: **fuel 32, parts 35** (in the stores on day 30, handed over), **Convoy truck** built (project `convoy1`: scrap 30, parts 40, fuel 10, 120 s of a mechanic, needs the generator; 8 seats), **radio room tier 1**, **fence tier 2**. Not required, shown with a bar: **people alive 9** (the bus has 4 seats, the truck 8: 12 seats in all, so at most 12 people go; Ruth and the children first).
* Extras that add to the score: a seat for the dog (+10), 10 meds for the sick (+15), 30 food for the road (+10), nobody lost on the way (+25).

If the required list is complete the convoy takes everyone who fits. If not, the convoy does not stop (the card reads what is missing); the run goes on to the last night.

## The endings

| Ending | When |
| --- | --- |
| **EVACUATED, full** | The list is complete, you load up, and 85 percent or more of everyone who ever lived in the base is on the truck. |
| **EVACUATED, good** | 50 percent or more. |
| **EVACUATED, bitter** | Fewer. |
| **EVACUATED, lonely** | Ruth alone. |
| **HELD THE FORT** | You stayed (or the convoy was not satisfied) and the last night (night 30, 90 dead at four walls) ended at dawn with the fence up. |
| **OVERRUN** | Any day: three walls down at the same time for 25 seconds during a night. |
| **STARVED / ABANDONED** | Nobody is left in the base (day 3 on). STARVED when someone died of hunger: three days of shortage of food or water kill one person a day. |
| **DEAD** | Ruth was lost on a raid three times. (She does not die at the base.) |

The card shows the epilogue (made from what happened: the names of the people lost, who walked out, kills, days, nights, projects, whether the dog came), a score breakdown (people x 20, days, nights x 4, projects x 3, dead at the fence x 0.1, rescues x 6, deaths x -6, letters x 3, +80 for the convoy or +40 for the fort, extras), the stats screen (days, nights held, kills, raids, rescues, deaths, walked out, scrap brought home, letters, walls lost), **New game** and **Quit**. The last run and the best score are in `user://prison_arc.json`. `--nosave` skips it.

## The nights and the weather

`nights` in the JSON is a table of rows `[night, dead sent, walls attacked, runner share]`; nights between rows are interpolated and the weather multiplies the dead. Night n is the night of day n. Nights 1 to 4 are 5 to 11 dead (one or two walls), a climb to 57 dead at night 19 (the worst week), a lull on days 21 to 23, the storm night 24 (51 x 1.2), 49 to 58 on the last days and a big night 30 (95) for those who stay. `weather` gives rain, fog and the storm by day; rain fills the barrels (+6 water with barrels built), the storm +10; rain, fog and storm darken the day a little (the storm most, at night). The siege (`prison_siege.gd`) reads the table in `_start_attack`; `--siege=N` uses night N's row.

## Pacing, as measured (the lab)

`--prison --managed --arcauto[=passive|average|expert] [--seed=N]` runs a scripted player through the 30 days, one day a frame, with the real economy, arc, story and endings, and now the real loot model; only the night is a stand-in. It prints one line a day (people, beds, morale, stores, the convoy list n/5, fence, radio, truck, the night's size and what it did) and one `ARCLAB RESULT` line. A batch: see the header of `prison_arclab.gd`. `--arcraids` adds one line per raid (kind of town, the places hunted, what the walk found).

**The raid.** Each lab raid does what a player does at the gate: the bot reads the biggest shortage, picks from the kinds of town on offer that day (`Loot.offer(day)`) the one that answers it (industrial yard for parts, fuel and scrap, residential for food and water, hospital for meds, police for ammo, else the mixed town), picks the gate option that hunts it, generates a town, retags and re-rolls it with `prison_loot.gd` for that kind and walks it with the loot lab's greedy 180 s walk (4 tiles a second, 6 seconds a container, nearest first). The walk finds no fights and has no 32-cell pack limit, so the skills scale it: average 0.8, expert 1.0. This replaces the old model, which paid about 13 parts and 12 fuel for every raid whatever the town, several times what a mixed town holds (a mixed town gives about 2.4 parts and 1.6 fuel to an untargeted raid, a hunt in it about 5 parts, an industrial yard about 12 to 19 parts and 9 fuel).

**The start.** The lab no longer opens on the `--managed` defaults. `lab.start_stores` is the new game's stores plus a typical clear phase: `CLEAR_STORES` (food 25, water 12, ammo 60 less the 40-round kit, meds 3, scrap 4, parts 2) plus about a third of the 32 containers' loot: food 40, water 30, ammo 40, meds 3, scrap 24, parts 2, fuel 0. (The clear bot `--auto=clearall` searches one container a zone and does not bank the loot, so the bank is an estimate from the loot of the ten containers it opened, scaled up.)

**The list, retuned.** Parts for the road 25 to 35, convoy truck 30 to 40 parts (fuel 32, 10 for the truck, unchanged), so the list asks for 151 parts in all (generator 30, radio room 40, truck 40, fence tier 2 six, handed over 35) and 32 fuel on top of the generator's one a day. The caps are unchanged (parts 60, fuel 40; the requirement of 32 is no longer the cap). The convoy truck is in the Fortress stage (fence 2, power 2, truck), so the stage tracker steers parts towards it instead of into Hub tiers the list does not need. The lab's bot follows the same path from day 6 and, from day 18, does not spend the handed-over fuel and parts on anything off the path.

Seeds 1 to 8, eight runs per skill, three people at the start. Before is the old raid model and the old start; after is the real loot, the real start and the new list.

| Player | Before | After |
| --- | --- | --- |
| passive (no raids, no spending) | 0 of 8, overrun day 20 to 24 | 0 of 8, overrun day 19 to 21 |
| average (a raid a day, spends, mends, rescues at 25 percent a raid) | 7 of 8 evac_full, 1 dead (Ruth lost on a raid) | 5 of 8 evac_full, 2 overrun on day 30 with the list unfinished, 1 held (list unfinished) |
| expert (more loot, more rescues) | 8 of 8 (4 full, 4 good) | 6 of 8 (5 full, 1 good), 1 overrun on day 25, 1 held (list unfinished) |

Every failed average run ends day 30 with the list unfinished (parts or the truck), so the list is the lever, not the night. The list is reachable but not free. These are bot runs: three human runs of days 1 to 30 are the real decision.

A day-by-day line for any run: `--prison --managed --arcauto=average --seed=N`. The stock of fuel and parts is fetched in the last days because the generator burns the fuel. The tuning knobs, in the order to turn them: the `nights` rows (the biggest lever for the night), `lab.skills.*.loot`, the list's parts (`requirements` and the costs of `power1`, `radio1`, `convoy1` in `prison_projects.json`), `caps`, `lab.start_stores`, `rules`.

## Flags

`--day=N` start on day N (earlier beats in the log), `--arcready` the base meets the convoy's list (try it with `--day=30 --hour0=11.2 --arcshow`), `--story=ID` show a beat card at frame 20, `--ending=ID` show an ending card at frame 20 (`evac_full`, `evac_good`, `evac_bitter`, `evac_lonely`, `held`, `overrun`, `abandoned`, `starved`, `dead`), `--arcshow` show cards in scripted runs (they go to the log only otherwise: `--auto`, `--shot`, `--drive`, `--siege`, ...), `--arclog` one line a day, `--arcquit=N` quit after N frames, `--nosave`. Existing drivers are unchanged: `--auto=clearall`, `--auto=loop`, `--siege=N`, `--econ-lab=18` (its line now ends with `[day 12 of 30, convoy list 3/5, next night 31 dead]`), `--drive=...`.

## How to change it

* **A beat**: add an object to `beats` in the JSON: `id`, `day`, `title`, `from`, `text` (3 to 5 sentences), `short`; optional `reward` {stores}, `choice` [{id, label, result, effects {stores, morale}}] (the last answer is the one a scripted run takes), `set_piece` {name, loot, note, found}, `opens_phase`, `readiness` (adds the list as it stands), `event` ("storm"), `silent` (log only). Nothing else to change.
* **A letter**: add to `letters`: `id`, `title`, `from`, `text`, `reward` {stores}, optional `clue`. `letter_chance` is the chance a raid hides one.
* **An ending**: add to `endings`: `title`, `sub`, `tone` (good, bitter, bad), `lines` (a string, or {if, text} with `if` one of lost, left, left_behind, dog, convoy_gone; placeholders {saved}, {names_saved}, {names_lost}, {names_left}, {names_walked}, {days}, {kills}, {nights}, {projects}, {night}). To reach it, call `arc.end("id")` where the rule is (`_late_end`, `_overrun`, `convoy_answer`, `evacuate`).
* **A requirement**: add to `requirements` (kind stock, project, tier or people; `must`; `take` hands the stock over); a bonus to `bonuses` (rule `seat_spare`, `no_deaths` or `stock:res:n`).
* **A night or the weather**: rows of `nights`, entries of `weather` and `weather_kinds` (wave_mult, dim, blackout, water). The score weights are `score`; the rules (starvation, overrun, Ruth's lives) are `rules`.

* **An event card** (the deck between the beats): add to `cards` in `assets/data/prison_events.json`. The whole language of `if`, the choices and the effects is in the header of `scripts/prison/prison_events.gd`. A card is drawn on a morning with no beat, by a seed (`arc.run_seed` and the day), once per run. Save fields (plain dicts on the arc): `run_seed`, `flags`, `events_seen`, `person_traits`, `hurt`, `night_mods`, `weather_over`, `raid_mod`, `event_pending`.
* **A person's traits and background**: `assets/data/prison_bios.json` (name to traits and one line). The six prison-only traits are in `traits.json` with `"only": "prison"`; where each is read: aim and reload for every guard in `prison_game.gd` `_fence_guards` (coward, hothead, veteran and the ten old ones; a pacifist never fires, a coward stops firing in a night at morale under 30; a hothead also burns more ammo), loot in `_extract` through `arc.raid_bonus` (scrounger, thief), eating in `econ._consume` (scrounger), daily morale in `econ._morale` (veteran `calm`, a pacifist cook or medic +20% on the kitchen or infirmary bonus).

## Weak spots

* The lab's night is a model, not the game, and its raid is the loot lab's greedy walk (no fights, no pack limit, no companions, a fixed 180 s; the skill factor stands in for the hands). A night is the table's dead against `guard_kills` 5 each and Ruth's 28 (times her skill) from `lab.night` with the leak breaking walls (8 hp a dead). It was set against one real run (`--siege=10 --siegefor=90`: 19 of 38 dead killed in 90 s, 4.3 shots a kill, 20 rounds, one wall down and 11 of 17 crew lost). A human playtest of days 15 to 30 is the missing check; every number is in the JSON.
* The lab starts with three people (the base starts small), and rescues come at 25 percent a raid (expert 40). If the other agent's rescue rules differ, set `lab.start_people` and the skills' `rescue_p`.
* The real game's storm has no rain art (a darker tint and the banner only), the convoy is drawn from rectangles, and the "dog" is a seat rule (the dog never dies).
* Cards pause the whole game; nothing shows in scripted runs unless `--arcshow`.

## Horde nights (2026-10-15)

The owner found the fence attacked all the time. Now the dead outside never damage the fence by day or on a quiet night: the pen's crowd drifts loose in the field, the guards raise no alarm for it, and what is left of a horde at dawn wanders off. The base is attacked only on horde nights, a schedule in `assets/data/prison_story.json` `hordes`: forced nights 1, 6, 9, 12, 24 (the storm) and 30, with a gap of three to five days between hordes drawn from the run seed (`prison_arc.gd` `is_horde_night`). A horde is the old night's wave times `size_mult` 1.3, still scaled by the armed guards, with the base horde of nights 6, 9 and 12 and the specials as before. The day banner says at dawn that a horde comes tonight, or is expected tomorrow night; the attack chip, the Base screen and the story page say "Quiet night, next horde: night N". A scream, an alarm or a very loud base on a quiet stretch may call a small horde (`hordes.small`, once per eight hours at the base, once per raid in town). A quiet night still counts as held for the arc, and a horde night missed on a raid uses the old missed-night model. Arc lab seeds 1 to 4, average and expert: 8 of 8 evacuated before and after (scores about 7 percent lower after, as fewer nights are fought); the lab skips the night on quiet nights.
