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

The objectives tracker (key O) shows, under the urgent line, the phase line `Phase II: Prepare - day 12 of 30 (18 left to the convoy)` (red when the phase is later than its `by_day`) and, from the day the convoy confirms (18) or when Phase III is reached, the convoy's list with thin progress bars. The top bar's clock reads **Day 12 of 30** (gold "CONVOY" on day 30), and a new chip **Convoy: day 30, in 18 d** (amber with 7 days left, red with 3) carries a meter of the list and a hover with every item.

* **Phase I: Establish** (by day 7): stage Shelter (water, dormitory).
* **Phase II: Prepare** (by day 20): Settlement and Fortress (garden 2, kitchen, infirmary, fence 2, power 2).
* **Phase III: Evacuate**: the convoy's list. Required: **fuel 40, parts 25** (in the stores on day 30, handed over), **Convoy truck** built (project `convoy1`: scrap 30, parts 30, fuel 10, 120 s of a mechanic, needs the generator; 8 seats), **radio room tier 1**, **fence tier 2**. Not required, shown with a bar: **people alive 9** (the bus has 4 seats, the truck 8: 12 seats in all, so at most 12 people go; Ruth and the children first).
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

`--arcauto[=passive|average|expert] --managed [--seed=N]` runs a scripted player through the 30 days, one day a frame, with the real economy, arc, story and endings; the raid and the night are stand-ins (see the weak spots). It prints one line a day (people, beds, morale, stores, the convoy list n/5, fence, radio, truck, the night's size and what it did) and one `ARCLAB RESULT` line. A batch: see the header of `prison_arclab.gd`.

Seeds 1 to 12, three people at the start, the table above:

| Player | Reaches the convoy | Endings | People on the truck (of everyone who ever lived there) | Ends |
| --- | --- | --- | --- | --- |
| passive (no raids, no spending) | 0 of 12 | overrun 12 | none | day 12 to 15 (the fence, unmended, falls at night 12 to 14) |
| average (a raid a day, spends, mends, 3 rescues in 12 days) | 8 of 12 | full 5, good 1, bitter 2, overrun 3, abandoned 1 | 79 percent of those who got there (53 percent counting the lost runs) | evac day 30; failures day 24 to 29 (the storm and the last week) |
| expert (more loot, more rescues) | 12 of 12 | full 7, good 5 | 85 percent | day 30 |

The goal progress for one average run (seed 4: the convoy's list of 5 must-haves met, the stage, people with Ruth, the night's size):

| Day | Stage | List | People | Fence / radio / truck | Night (dead, wall fire) |
| --- | --- | --- | --- | --- | --- |
| 1 | Shelter | 0/5 | 5 | 0 / 0 / 0 | 5, 24 |
| 5 | Shelter | 1/5 | 5 | 0 / 0 / 0 | 14, 24 |
| 10 | Fortress | 2/5 | 8 | 2 / 0 / built | 24, 27 |
| 15 | Hub | 3/5 | 8 | 2 / 1 / built | 42, 27 (leak 14) |
| 20 | Hub | 4/5 | 10 | 2 / 1 / built | 52, 38 |
| 25 | Hub | 4/5 | 13 | 2 / 1 / built | 50, 19 (leak 30) |
| 29 | Hub | 4/5 | 8 | 2 / 1 / built | 58, 12 (leak 45): five lost in the last nights |

The 5th item (the stock of fuel and parts) is fetched in the last days because the generator burns the fuel; the lab's bot takes it from day 18. The tuning knobs, in the order to turn them: the `nights` rows (the biggest lever: between the table of an earlier run, about 15 percent lower, every average run got there, and about 15 percent higher none did), `lab.night.guard_kills` and `ruth_kills`, `caps` (fuel 40 and parts 60 are the economy's caps: the requirement fuel 40 sits exactly on the cap), the convoy truck's cost in `prison_projects.json`, `rules`. The target "an average competent player gets there with about 70 percent of the people, a passive one fails by day 15 to 20" holds for the lab (79 percent, and the passive run ends at day 12 to 15: a little early; raise `start_stores` or lower nights 9 to 14 to move it).

## Flags

`--day=N` start on day N (earlier beats in the log), `--arcready` the base meets the convoy's list (try it with `--day=30 --hour0=11.2 --arcshow`), `--story=ID` show a beat card at frame 20, `--ending=ID` show an ending card at frame 20 (`evac_full`, `evac_good`, `evac_bitter`, `evac_lonely`, `held`, `overrun`, `abandoned`, `starved`, `dead`), `--arcshow` show cards in scripted runs (they go to the log only otherwise: `--auto`, `--shot`, `--drive`, `--siege`, ...), `--arclog` one line a day, `--arcquit=N` quit after N frames, `--nosave`. Existing drivers are unchanged: `--auto=clearall`, `--auto=loop`, `--siege=N`, `--econ-lab=18` (its line now ends with `[day 12 of 30, convoy list 3/5, next night 31 dead]`), `--drive=...`.

## How to change it

* **A beat**: add an object to `beats` in the JSON: `id`, `day`, `title`, `from`, `text` (3 to 5 sentences), `short`; optional `reward` {stores}, `choice` [{id, label, result, effects {stores, morale}}] (the last answer is the one a scripted run takes), `set_piece` {name, loot, note, found}, `opens_phase`, `readiness` (adds the list as it stands), `event` ("storm"), `silent` (log only). Nothing else to change.
* **A letter**: add to `letters`: `id`, `title`, `from`, `text`, `reward` {stores}, optional `clue`. `letter_chance` is the chance a raid hides one.
* **An ending**: add to `endings`: `title`, `sub`, `tone` (good, bitter, bad), `lines` (a string, or {if, text} with `if` one of lost, left, left_behind, dog, convoy_gone; placeholders {saved}, {names_saved}, {names_lost}, {names_left}, {names_walked}, {days}, {kills}, {nights}, {projects}, {night}). To reach it, call `arc.end("id")` where the rule is (`_late_end`, `_overrun`, `convoy_answer`, `evacuate`).
* **A requirement**: add to `requirements` (kind stock, project, tier or people; `must`; `take` hands the stock over); a bonus to `bonuses` (rule `seat_spare`, `no_deaths` or `stock:res:n`).
* **A night or the weather**: rows of `nights`, entries of `weather` and `weather_kinds` (wave_mult, dim, blackout, water). The score weights are `score`; the rules (starvation, overrun, Ruth's lives) are `rules`.

## Weak spots

* The lab's raid and night are a model, not the game: one raid is three places' loot (`loot` of the economy's own table) times a skill factor, and a night is the table's dead against `guard_kills` 5 each and Ruth's 28 (times her skill) from `lab.night` with the leak breaking walls (8 hp a dead). It was set against one real run (`--siege=10 --siegefor=90`: 19 of 38 dead killed in 90 s, 4.3 shots a kill, 20 rounds, one wall down and 11 of 17 crew lost). A human playtest of days 15 to 30 is the missing check; every number is in the JSON.
* The lab starts with three people (the base starts small), and rescues come at 25 percent a raid (expert 40). If the other agent's rescue rules differ, set `lab.start_people` and the skills' `rescue_p`.
* The real game's storm has no rain art (a darker tint and the banner only), the convoy is drawn from rectangles, and the "dog" is a seat rule (the dog never dies).
* Cards pause the whole game; nothing shows in scripted runs unless `--arcshow`.
