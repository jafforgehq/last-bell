# Seven nights: what the game does today (PH5 MEASURE7)

Written 2026-10-09 by the MEASURE7 builder. Step 1 of `docs/plan-7-day-demo.md`: measure, change no balance, add the plumbing. The numbers are the lab's (`tools/house_lab.gd`): seeds 1..32, the whole 192 x 192 town, 15 Hz, `night.first` 1.85, 0 errors. "Real minutes" are at the lab's player pace (the bot's game time times 1.25, plus 40 s for each night slept in the bed). Raw logs and tables: `/private/tmp/claude-501/-Users-jaf-lab-last-bell/6b84d821-4f10-4deb-be40-d511bdef2435/scratchpad/ph5-measure/` (`seven-bot-idle.*` and `seven-daywork.*` are the two runs; `tables-seven-nights.txt` has both table sets; `analysis-*.txt` and `income-*.txt` the extra numbers; `analyze.py` and `income.py` make them from the `.json`).

## What was run

```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --script res://tools/house_lab.gd -- --seeds=1..32 --mode=bot,idle --nights=7 --jobs=2 --out=A.json            # A: the bot as it is
$G --headless --path . --script res://tools/house_lab.gd -- --seeds=1..32 --mode=bot,idle --nights=7 --daywork --jobs=2 --out=B.json  # B: the bot works the days of the attacks
$G --headless --path . --script res://tools/house_lab.gd -- --tables=A.json                                                             # the tables again, no play
```

- `--nights=7` ends a run in victory at the dawn that makes seven attack nights HELD (a night not held does not count and the run goes on; the day limit is 11). Attack night 1 is the night of day 2 in 31 of 32 seeds (seed 21 claims its house on day 7, an old bot problem); night 7 is the night of day 8; the win is the dawn of day 9, 06:30.
- **A** is the lab's bot unchanged. It stops rescuing the moment the attacks begin and, on the days of the attacks, searches only houses that are already clear within 30 tiles. **B** (`--daywork`, new, off by default) lets it do what a player who does not sit at home does: bring more survivors home and search every house within 45 tiles, the ones with dead in them too, home by 16:30. B is a bot, not a measure of a person.
- With the default data (`end.nights_to_hold` 1) the lab on seeds 1..16 gives what main gives: bot 15/16, idle 4/16, every run line identical to the line on main except the "game min slept" figure, which main itself does not repeat from one run to the next (686 or 687).

## The summary table, A (the bot as it is: it spends the days at home)

Held = of the runs that got to the night; a run that ended inside a night counts it as not held. The middle columns are the bot's runs (median, stores at dusk, crew alive at dawn).

```
  night | bot there | bot held% | idle there | idle held% | dead | ammo | food | water | scrap | meds | crew | real min | failure, bot | failure, idle
      1 |        32 |        97 |         32 |         22 |   12 |   71 |   19 |    28 |     3 |   22 |  3.0 |      7.2 | fence fell 1 of 1 | fence fell 14 of 25
      2 |        32 |        91 |         28 |          7 |   27 |   54 |   17 |    25 |     3 |   22 |  3.0 |      7.2 | fence not mended 1 of 3 | avatar died 18 of 26
      3 |        32 |        38 |          7 |         14 |   32 |   26 |   14 |    25 |     2 |   20 |  3.0 |      7.2 | ammo out 14 of 20 | avatar died 6 of 6
      4 |        31 |         6 |          1 |        100 |   37 |    0 |   11 |    25 |     0 |   15 |  2.0 |      7.2 | fence not mended 19 of 29 | -
      5 |        31 |         0 |          1 |          0 |   42 |    0 |    9 |    25 |     0 |    8 |  1.0 |      7.2 | fence not mended 27 of 31 | avatar died 1 of 1
      6 |        29 |         0 |          0 |          - |   48 |    0 |    8 |    25 |     0 |    8 |  1.0 |      7.2 | fence not mended 27 of 29 | -
      7 |        25 |         0 |          0 |          - |   46 |    0 |    7 |    24 |     0 |    8 |  1.0 |      7.2 | fence not mended 24 of 25 | -
      8 |        22 |         0 |          0 |          - |   52 |    0 |    6 |    25 |     0 |    8 |  1.0 |      7.2 | fence not mended 22 of 22 | -
```

Runs won: bot 0 of 32, idle 0 of 32 (9 bot runs reached the day limit). Total real minutes of a run (all runs, most ended early): bot median 136.3 (p10 96.9, p90 156.7), idle median 36.8 (p10 25.4, p90 51.4).

## The summary table, B (`--daywork`: the bot rescues and searches on the days of the attacks)

```
  night | bot there | bot held% | idle there | idle held% | dead | ammo | food | water | scrap | meds | crew | real min | failure, bot | failure, idle
      1 |        31 |        97 |         31 |         77 |   28 |   73 |   23 |    26 |     3 |   22 |  6.0 |      7.2 | ammo out 1 of 1 | ammo out 6 of 7
      2 |        30 |        83 |         30 |         47 |   47 |   83 |   30 |    28 |     3 |   26 |  6.0 |      7.2 | ammo out 3 of 5 | ammo out 8 of 16
      3 |        25 |        84 |         21 |         48 |   55 |  116 |   32 |    33 |     3 |   38 |  6.0 |      7.2 | ammo out 2 of 4 | avatar died 7 of 11
      4 |        23 |        74 |         12 |         50 |   64 |  135 |   43 |    37 |     3 |   44 |  6.0 |      7.2 | ammo out 4 of 6 | avatar died 3 of 6
      5 |        22 |        64 |          9 |         33 |   74 |  130 |   43 |    40 |     3 |   45 |  6.0 |      7.2 | fence not mended 5 of 8 | avatar died 2 of 6
      6 |        22 |        64 |          5 |          0 |   83 |   82 |   40 |    41 |     3 |   47 |  6.0 |      7.2 | fence not mended 8 of 8 | avatar died 3 of 5
      7 |        22 |        27 |          1 |          0 |   85 |   30 |   38 |    42 |     1 |   46 |  5.0 |      7.2 | ammo out 8 of 16 | avatar died 1 of 1
      8 |        12 |         0 |          0 |          - |   58 |    0 |   44 |    38 |     0 |   25 |  1.0 |      7.2 | fence not mended 11 of 12 | -
```

Runs won: bot 6 of 32 (19 percent), idle 0 of 32. The 6 won runs took 106.4 real minutes (p10 101.8, p90 113.2); all 32 bot runs: median 111.3, p10 36.7, p90 139.3. Counting the runs that died on the way, the share that has held every night up to k is 94, 78, 66, 53, 44, 44 and 19 percent for k = 1 to 7. The idle avatar (hands off from each dusk) holds night 1 in 22 percent of A and 77 percent of B (a crew of six shoots for it) and none holds night 6.

## The day-by-day real-minute split (lab pace)

A day (06:30 to 19:00) is 7.8 minutes, a night (19:00 to 06:30) 7.2. Day 1 is 7.5, plus 0.7 for the night slept. The run to the dawn of day 9 is 8.2 + 7 x (7.8 + 7.2) = **113 minutes** (about 90 at the bot's own pace: the plan's 70 to 100 at 1x). Where the minutes go (the lab's DAY SPLIT, means by kind):

| | day phase, A (at home) | day phase, B (works the day) | night phase, A and B |
| --- | --- | --- | --- |
| walking | 0.2 to 0.6 | 3.1 to 4.0 (days 2 to 7), 2.7 (day 8), 1.6 (day 9) | 0.2 to 0.9 |
| searching, clearing, rescuing | 0.0 to 0.1 | 0.8 to 1.1 (0.5 and 0.3 on days 8 and 9) | 0.0 to 0.5 |
| building | 0.0 to 0.1 | 0.0 to 0.1 | 0.0 to 0.2 |
| trigger held | 0.0 | 0.6, 0.4, 0.3, 0.2, 0.2, 0.2, 0.1, 0.0 (days 2 to 9) | 0.2 to 0.4 |
| **waiting** | **7.1 to 7.4 (91 to 95 percent), days 2 to 8** | 1.3, 1.5, 1.6, 1.7, 2.0, 2.5, 3.4, 3.9 (days 2 to 9: 17 to 50 percent) | **6.0 to 6.7 of 7.2 (A), 5.5 to 6.2 (B)** |

Day 1 (both): walk 2.8 to 3.2, search 0.9 to 1.0, build 2.4 to 2.9, wait 0.6 to 0.7.

## Findings

**Where it breaks.** A, the bot at home: night 3. Nights 1 and 2 are held (97 and 91 percent), then nobody brings anything in: the ammo at dusk is 71, 54, 26 and 0 from night 4 (0 in 18 of 32 runs at night 4), the scrap is 0 in 30 of 32 runs by night 4, 2 of 31 runs hold night 4 and none holds a later one. B, the bot that works the days, is the better model of a player: nights 1 to 6 are held 97, 83, 84, 74, 64 and 64 percent of the runs that got there, **night 7 only 27 percent**, and 19 percent of the runs win. The reason is **ammo**: a night costs 0.73 to 0.88 round for each dead one (the nights use 23, 37, 44, 47, 54 and 61 rounds; night 7 with its 85 dead would take about 68), the houses near the base give +26, +46, +29, +13, +2 and +0 rounds on days 3 to 8 (median, next dusk minus this dawn: net of the day's own shooting), so the stock peaks at nights 4 and 5 (130 to 135 at dusk) and is 30 at night 7 (0 in 7 of 22 runs at that dusk). Half of the 16 failures of night 7 are "ammo out", the other half "fence not mended". The six winners had 90 to 220 rounds at dusk of night 7 against a median of 30 for the runs that got there: the runs that win are the ones whose first days happened to find the most.

**Where it is boring.** A: every day from day 2 to day 8 is 91 to 95 percent waiting (the bot is at home, `task: home`: **51 of the 113 minutes** are seven days of nothing), and every night 6.0 to 6.7 of 7.2 minutes (the trigger is held for 0.2 to 0.4 minute of a night: the crew's patrol shoots, and the avatar waits for the next of the three groups of dead, which come 0.3, 2.6 and 4.6 hours after dusk). B: the days are busy (walking 3.5 to 4.0, searching about 1, waiting 1.3 to 1.7 minutes) up to day 5; then the houses in range are empty and the waiting grows: 2.0 on day 6, 2.5 on day 7, 3.4 on day 8, 3.9 on day 9 (up to 50 percent). **Days 7 to 9 are the empty ones**, and every night is about 6 minutes of standing at the wall. Building is 0.0 to 0.1 minute a day from day 2 on: the projects are up (or there is no scrap for the next one) and the Build page has nothing to offer.

**Which resource runs out first.** Ammo and scrap; not food, water or meds. Of the 32 B runs, 21 had a stock at 0 at some dusk: scrap alone in 9, ammo and scrap together in 9, ammo alone in 3; 11 never did. Scrap is 3 at almost every dusk (every point goes into the next project; 0 in 11 of 22 runs at night 7) and the fence is never mended with it. With six people B never has food or water under 3 (median food 23 to 44, water 26 to 42, meds 22 to 47); with three people (A) the food falls 3 a day and is under 3 in 4 of 25 runs at night 7, water never.

**The night curve today.** The dead (walkers / runners / brutes) for the crew of three of A: 12 (9/2/1), 27 (27/0/0), 32 (31/1/0), 37 (35/2/0), 42 (39/3/0), 48 (44/4/0), 46 (40/5/1), 52 (44/7/1) on nights 1 to 8; in points (runner 2, brute 9) 22, 27, 33, 39, 45, 52, 59, 67. With a full house of six (B): 28 (24/3/1), 47 (47/0/0), 55 (53/2/0), 64 (61/3/0), 74 (70/4/0), 83 (76/7/0), 85 (75/9/1); points 39, 47, 57, 67, 78, 90, 102. Four things in it. (1) The size follows the crew (`crew_scale`: 0.53 for three with the avatar, 0.93 for six): the first night, tuned with three people at 12 dead, is 28 as soon as the house is full. (2) Night 1 is the special night (a plated brute and 2 runners: 22 points in 12 bodies) and the body count jumps on night 2: 12 to 27, 28 to 47. (3) After that it is a ramp of +13 to 23 percent of points a night, falling: **night 7 is 2 percent more bodies than night 6 (85 against 83), 13 percent more points: there is no finale.** (4) Kinds: night 2 is all walkers (the runner's first day is 4, the brute's 8), runners are 1 to 9 a night after, and the one brute after night 1 is on night 7.

**The crew by day 8.** A: three (the avatar and two), by design: the bot stops rescuing when the attacks begin. B: **six by the morning of day 2** (the fifth rescue happens on day 2, between 08:00 and 14:00, in 25 of 32 runs; the crew is six at the first dusk in 26 of 31), the house's six beds (`Build.BASE_HOUSING`) are full before attack night 1 and stay full; on days 7 to 10 there are 23 more joins in all 32 runs, each replacing a dead one. **Every town has 12 rescue spots (`rescue_for`), 7 of them stay unused in a typical run (5 join in 20 of 32), and nothing houses more than six today**: the building bonuses (+4 and +2 beds, `buildings.json`) belong to the school's lots and the town has no plots for them. So "one new survivor a day until the crew is five or six" is, today, "all of them on day 2".

**What the bot does between nights.** A: nothing. `_wants_rescue()` is false once the attacks are on and `_loot_task` takes only cleared houses within 30 tiles on an attack day (none are left after day 1), so `_plan` falls to `home` for 12.5 game hours a day. B: walks about 4 of 7.8 minutes, searches about 1, is home at 16:30 (`HOME_BY_ATTACK`), and from day 7 the day brings in almost no ammo (+2, +0) because nothing is left in range.

**The fence does not repair itself and must be repaired.** A section that falls stays down: of the 156 nights of A that ended with one down, 156 began the next dusk with one down (B: 47 of 48), and the held rule (`base_whole`) wants none down at dawn, so **one breach ends the holding for good unless somebody mends it**: this is the "fence not mended" row (A: 19 of 29 failures at night 4 and 27 of 31 at night 5; B: 8 of 8 at night 6). What mends: the builders by day, only with 5 scrap or more in the stores (`Tactics.AUTO_MIN_SCRAP`) and only a section under their threshold; the idle crew as a chore below 50 percent; the avatar by hand (E at the wall, 10 points of health for a scrap); the Build page rebuilds a fallen section as its NEXT project when the scrap pays for it. The runs have 0 to 3 scrap at every dusk, so none of it starts: the worn fence gained nothing between a dawn and the next dusk (median 0.0 points, every night of both runs; more than half a point in at most 6 of 22 nights) while it lost 1 to 9 points a night (B) and 22 points on night 3 (A). Scrap income, 3 at dusk, is the weakest number of the economy: there is no source after day 1 except what a search happens to hold.

**Smaller things seen.** Seed 21 claims its house on day 7 (the bot only; 1 run in 32 in A and B). `report().of` said 1 and the end card "Two survivors" whatever the crew: both come from the data now (N and `end.nights`). The lab's "game min slept" figure is not repeatable to the minute on main either.

## Three proposals for the arc (not implemented)

1. **Pay for the nights with the days (economy first).** The break is arithmetic: a night costs about 0.8 round a dead one, the houses in range are dry by day 7, and the fence has no scrap. Give each day a district farther out than the last, with a yield that is designed and not whatever is left (ammo about +40 a day up to day 8, scrap +15, a car-strip route), let the fence mend itself when it is cheap (`AUTO_MIN_SCRAP` from 5 to 1, builders mending any section under full health by day) and leave the Build page's projects a few scrap short of spending everything. Gate: the lab's B reaches night 7 with dusk ammo at least 1.2 times that night's need in 80 percent of runs.

2. **Make the curve a table and cut it loose from the crew.** One row for each night in `one_house.json` (the plan's step 2), in points that do not move with the number of people (or with `crew_scale` capped at a crew of four): night 1 the siege, 2 walkers, 3 the first runners, 4 a surge with two plated brutes, 5 runners in a storm, 6 a siege from three streets, 7 a finale of at least 1.5 times night 6 with a push at dawn. Today night 7 is 2 percent more bodies than night 6, and a full house (day 2) turns the first night from 12 dead into 28. With six people the share of B runs that have held every night through 6 is already 44 percent, so the finale is the one night worth making hard on purpose.

3. **Seven nights are 113 minutes: fill the days or make it five.** At the lab's pace the run is 113 minutes; 51 of them are the days of a bot with nothing to do, and a scavenging bot has little to do from day 7 (waiting 2.5, 3.4 and 3.9 of 7.8 minutes on days 7 to 9). (a) Five held nights (days 2 to 6): 8.2 + 5 x 15 = 83 minutes, the economy has to carry five nights (about 205 rounds; B has the 44 percent streak through night 5 and a peak stock of 135 today), and `nights_to_hold` is still one number. (b) Keep seven and give days 6 to 8 a purpose (the rescue schedule and one base project a day need beds first, which are six and full on day 2) and let the player skip the waiting of the nights (6 of every 7.2 minutes). I would take (a) for the demo and keep (b) for the full game.

## What changed in the code (for the record)

`scripts/town/one_house.gd` (`nights_to_hold()`, `set_nights_to_hold()`, `night_log()`, `judged_count()`; `_watch_the_dawn` counts held nights and ends the run at N; `total_days()`, `report().of`, `victory_banner()` and `end_card()` know N; the save keeps `to_hold`, and a save without it takes the data's, so `TownGen.VERSION` is not bumped: nothing generated changed and an old save reads as it did); `assets/data/one_house.json` (`end.nights_to_hold` 1, `end.nights`, `words.night_held`, `words.victory_nights`, the `_doc`); `tools/house_lab.gd` (`--nights`, `--daywork`, `--tables`, the night rows, the split, the tables); `tools/house_bot.gd` (`daywork`, off by default); `tests/test_oh_nights.gd` (4 tests); `README.md` (one sentence). `held_rule`, `big_night`, the night machinery and every number of the balance are as they were.
