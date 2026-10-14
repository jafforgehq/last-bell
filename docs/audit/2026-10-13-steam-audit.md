# Last Bell: Steam Readiness Audit, 2026-10-13

Audit of the prison game on `main` (commit `cb5a42b`), for the owner. Written 2026-10-14 from nine audit agents, each checked by a "skeptic" agent that tried to refute the claims, plus research agents on the Steam market. The writer did not re-run the game; every run and line number below came from those agents. After review, the reviser recomputed the night table (2.1) and the scenario arithmetic (9.3) from repo data and the research dumps; it did not run the game either. What could not be verified says **unverified**.

Reading guide. "Run" means an agent ran the code. "Doc" means a repo doc line. "Estimate" means arithmetic on third-party data.

## At a glance (summary written at the end of the audit session)

**Verdict.** As a design the game grades C+. As a tested product it grades D. It is not ready for Steam. The gap is mostly plain work (save, desktop build, first minute, balance), not new systems.

**Blockers.**
- **No save.** A run takes at least 3 hours and the prison game has no save or load.
- **Wrong aim rule.** Left click does not fire unless the right button is held, and every on-screen hint says otherwise.
- **Convoy tuning.** The 30-day convoy goal was tuned on a lab that over-pays raids by roughly 2 to 6 times. The agents disagreed on the exact factor.
- **Quit crash.** Every prison quit aborts with exit 134. One cleanup in `_exit_tree` fixes it (tested in a scratch copy).
- **Night bugs.** The night 3, 6, 9 and 12 base horde never fires (a float-versus-int compare). A raid that returns after dawn cancels that night. A skipped night 30 gives the "held" ending.
- **No desktop build, no key art.** There is no Windows, macOS or Linux export preset. There is no capsule, trailer or title art, and the title screen still shows the old game.
- **Never played.** No human has played the 30-day arc or heard the audio.

**Name.** "The Last Bell" already exists on Steam (app 3719170, ZeroHint). The report recommends "Thirty Bells". That reverses the owner's 2026-10-07 choice, so it is the owner's call. Search the trademark registers before making any art.

**Steam forecast** (Boxleiter and third-party estimates, plus or minus 30 to 50 percent):

| Scenario | Year-one copies | Year-one net |
|---|---|---|
| Ship as-is in 4 weeks | about 170 | about $900 |
| Polished, Early Access at $12.99, demo at Next Fest (Feb 22 to Mar 1, 2027) | about 1,400 | about $8,000 |
| Strong case | about 3,600 | about $21,000 |
| Top 5 percent | about 9,000 | about $51,000 |

Four weeks is not possible anyway. Steam needs 21 to 30 days after the fee is paid, plus identity checks, and no desktop export exists yet.

**Process note.** The first workflow run lost 19 agents to the weekly usage limit. It was resumed from cache and all 40 agents completed. The runtime-evidence agent (game runs and tests) was among those rerun. The writer did not re-run the game, so every run and number comes from the agents' work. Unit figures are third-party estimates.

---

## Table of contents

1. [The short version](#1-the-short-version)
2. [Where we are right now](#2-where-we-are-right-now)
3. [What is good](#3-what-is-good)
4. [What is bad](#4-what-is-bad)
5. [What needs polish](#5-what-needs-polish)
6. [Subsystem by subsystem](#6-subsystem-by-subsystem)
7. [Competitors](#7-competitors)
8. [What players of this niche demand](#8-what-players-of-this-niche-demand-and-what-sinks-games-like-this)
9. [What to expect on Steam](#9-what-to-expect-on-steam)
10. [What we should do: the phased plan](#10-what-we-should-do-the-phased-plan)
11. [The 20 ideas, ranked](#11-the-20-ideas-ranked)
12. [Appendix: method, sources, open questions](#12-appendix-method-sources-open-questions)

---

## 1. The short version

1. **Where we are.** The prison game is three days old (first prison commit 2026-10-11, merged to main 2026-10-13) on a fifteen-day-old, single-author codebase of about 173,000 lines of game scripts (`scripts/`; the full GDScript count of 312,000 also holds 123,000 lines of tests and 16,000 of tools). It has a real spine: a clear phase, a 30-day managed arc with a raid by day and a siege by night, a convoy on day 30, and nine endings. The raid is the strongest part.
2. **Nobody has played it.** No human has played the managed phase or the 30-day arc for an hour, nobody has heard the audio, and nobody has seen it on a 1x non-Retina screen (STATUS.md:16, prison-audio-report.md:3). Every grade in this report is provisional until that happens.
3. **The verdict.** As a design it is a C+; as a tested product it is a D. It is not ready for Steam. The distance is mostly boring work (save, desktop build, first minute, balance), not new systems.
4. **Three blockers beat everything else.** No save in a run that is at least 3 hours (6 real minutes a day, 30 days). The first-minute aim rule contradicts every on-screen hint (left click does not fire unless the right button is held). The 30-day convoy goal has never been tested against real raid yield, and the lab that "proved" it over-pays raids by roughly 2 to 6 times (the agents disagree, see C3).
5. **Four small bugs break the night.** The base horde on nights 3, 6, 9 and 12 never fires (a float-versus-int compare, confirmed by a GDScript test). A raid that returns after dawn silently cancels that night. A skipped night 30 yields the "held" ending. The "Banked" line counts your own returned kit as loot. Together about 2 days of work.
6. **The quit crash is real and cheap.** Every prison quit aborts with `recursive_mutex lock failed`, exit 134, headless and windowed. One `_exit_tree` clearing five static callables fixes it (verified in a scratch copy: exit 0).
7. **What to do first.** In two weeks: fix the first minute and the four bugs, fix the quit crash, re-tune the convoy list on measured loot, play it yourself to day 30 twice, pay the Steam fee, decide the name. Then save, desktop build, time control, difficulty and seed. Then demo and store page.
8. **What to expect on Steam if it ships as-is in 4 weeks.** About 170 copies in year one (central estimate, range 50 to 700), about $900 net, about 5 reviews, and it burns the one Next Fest the game gets. Four weeks is not even possible: Valve's own pages give 21 or 30 days between paying the fee and release (plan for 30; four weeks is 28), identity, bank and tax checks add 10 to 30 days on top of or beside that (whether the clocks overlap is unverified), and no desktop export exists.
9. **What to expect if done properly.** Early Access at $12.99 with a demo at Next Fest Feb 22 to Mar 1 2027: a base case of about 3,000 launch wishlists, 1,400 copies in year one and about $8,000 net; a strong case of about 7,000 wishlists, 3,600 copies and $21,000 net; a top-5-percent case of 15,000 wishlists, 9,000 copies and $51,000 net. Probability-weighted about $11,000 net if executed, about $7,500 allowing for execution risk. Every figure is linear in the launch wishlist count W and worth about $2.3 to $2.5 net per wishlist in year one (9.3). An earlier draft of this report used 6,000 wishlists and $16,000 for the base case; the research band (2,000 to 5,000 for steady marketing plus a Next Fest) does not support it. These are estimates built on wishlists times conversion, not sales data.
10. **The name.** "The Last Bell" already exists on Steam (app 3719170, ZeroHint). "Thirty Bells" returns zero Steam apps and zero itch titles, fits the 30-day arc, and the save folder already says `ThirtyBells`. Search the trademark registers before making any art. This reverses your 2026-10-07 choice (STATUS.md:4), so it is your call.

---

## 2. Where we are right now

### 2.1 What the game is today

Main is "the prison game". A new game starts a **clear phase**: Ruth and three allies enter an old prison through a breach in the west fence and clear ten zones of 99 dormant dead (a bot needs about 6 minutes of game time; a human estimate of 8 to 12 minutes is unverified). Then the **managed phase** starts and runs 30 game days at 6 real minutes a day (`DAY_MIN_PER_SEC 4.0`, prison_game.gd:58):

- **By day:** base management (22 projects in 9 buildings with three tiers, production, upkeep, morale, stages, a roster with roles), and one **raid** out of the gate. The player picks one of five targets, a loadout (gun, spare, ammo, kit, up to two companions), and enters a generated 64x64 town with 38 to 50 containers and 108 to 118 dormant dead. Loot, rescue survivors (bed-limited), and extract or lose the pack.
- **By night:** a siege on a 14-segment fence. The night table climbs from 5 dead on night 1 to 95 on night 30 before guard scaling (the siege sends a fraction of it; see the table after this list), with named nights and a storm blackout on day 24.
- **Story:** eight radio beats, twelve letters, one choice (the dam, day 12), a convoy on day 30 that takes you if the base holds fuel 40, parts 25, a convoy truck, a radio room and a tier 2 fence, and nine endings with an epilogue built from who lived and died.
- **Systems:** a noise system with hordes, car alarms and four special infected (screamer, bloater, hunter, breacher), three guns (pump shotgun, service rifle, SMG), a grid inventory, a procedural nine-stem adaptive score, 92 prison sounds.
- **Still in the repo:** the school yard (`--school`) and One House (`--onehouse`) games, about 63,000 of the 173,357 lines in `scripts/` that the prison does not literally load (an upper-bound estimate; the skeptic notes the prison reaches 195 scripts and 110,000 lines through shared code).
- **Shipped on:** a restricted itch.io web build, 85 MB zip (pck 83,004,428 bytes, wasm 39,514,754 bytes). Steam is the goal. A browser pulls the 83 MB pck plus 10 to 39 MB of wasm before the title: about 40 to 60 s at 20 Mbps (runtime-evidence.md section 6; arithmetic, not a measured load). The pck was 44 MB on Oct 11 and 83 MB on Oct 13 (+39 MB in two days, from the 16-heading atlases and baked dead), so the growth trend matters more than the number. The closed itch playtest (idea 7) will lose some testers at the loading bar on a slow link (inference).

**What a night actually sends.** The night table (`prison_story.json` `nights`) is the unscaled plan. The siege multiplies the per-segment count by armed tower guards divided by 6, clamped to 0.3 to 1.0, with a floor of 2 per segment (`prison_siege.gd:369-372`; `prison_balance.json` siege `ref_armed` 6, `floor` 0.3). The start crew had two armed guards in the skeptic's runs (Cole and Bea, prison_crew.gd:87-89), a factor of 0.33. The combat skeptic's natural `--siege` runs sent 2, 2 and 3 on nights 1, 2 and 3 (`roundi(8 x 0.333)` = 3). The rest of this table is the reviser's computation from the formula, not an engine run:

| Night | Table value (pre-scaling) | Segments | Sent at 2 guards (x0.33) | At 4 guards (x0.67) | At 6 guards (x1.0) |
|---|---|---|---|---|---|
| 1 | 5 | 1 | 2 | 3 | 5 |
| 3 | 8 | 1 | 3 | 5 | 8 |
| 6 | 17 | 2 | 6 | 12 | 18 |
| 12 | 30 | 3 | 9 | 21 | 30 |
| 30 | 95 | 4 | 32 | 64 | 96 |

Reading it: the 5 to 95 figures quoted in 2.1, C4 and idea 3 are pre-scaling. Per-segment rounding makes full-guard sums 18 and 96 against a table 17 and 95. The wave follows the guns (a comment in the code calls it "fix round 3"), so a base that arms more towers meets more dead, not fewer; the pressure on a two-guard base on night 3 is 3 dead, not 8. The base horde (C4) is not guard-scaled and would run 34 to 100 dead, so once fixed it is the real cliff, not the table.

### 2.2 What is built, verified and not verified

| Area | Built | Verified how | Not verified |
|---|---|---|---|
| Suite | 223 `.gd` files in `tests/` (214 `test_*.gd` plus 9 helpers), 4,411 `func test_` methods in the 214 | Run: full headless suite 4411 passed, 0 failed, 0 script errors, rc 0 (runtime agent, 51 min) | Covers none of the prison. 0 of the 214 test files reference `scripts/prison` (2 mention it in comments) |
| Raid loop | Go out, loot, bank, die | Run: `--auto=loop --seed=3` deterministic, 5 SNAP lines identical across two runs, death loses the pack and the shotgun | Never played by a human for an hour |
| Clear phase | 10 zones | Run: 3 bot runs, 3 outcomes (about 395 s game time and secured; stuck at 7 of 10 zones from t=319; about 380 s). Doc claims 255 s | Human length; whether the wedge at (57.256, 27.607) is a level trap or bot steering |
| 30-day arc | Full | Run: arc lab seeds 1 to 4 average: 1 `evac_full`, 3 `evac_good`; passive seed 1 overrun day 12 | The lab uses a raid model about 2 to 6 times richer than the real loot (C3). A lab with measured yields ends all 8 seeds "overrun" on day 16 to 18. It only bounds the arc; a human run decides |
| Night skip | Siege only runs in base mode | Run (headless, seeds 3 and 7 loops): raid of 160 s from 20:48 returns 07:48, no attack; 60 s returns 01:08, attack starts | Not re-run windowed with the real gate cutscene; the proposed fix is untested and interacts with the horde fix (M1) |
| Web build | 85 MB zip; 83 MB pck plus 10 to 39 MB wasm to download (about 40 to 60 s at 20 Mbps, arithmetic); 60 fps on title and first screens | STATUS.md:14; runtime-evidence.md section 6 | Real play session in the itch embed, long-run memory, browser audio, a measured load time on a slow link |

### 2.3 Numbers from the runtime runs

| Number | Value | Source |
|---|---|---|
| Real minutes per game day | 6; 30 days = 180 min of game clock. The clock keeps running in raids, so raid time is inside the 180, not on top; card pauses, the clear phase (about 6 min for a bot) and cutscenes add real time | prison_game.gd:58, :1040 |
| Night attack real time | about 142 s (21:00 to 06:30 at 15 s an hour); daylight about 217 s | prison_siege.gd:30-32 |
| A 160 s raid costs | 10.7 game hours | run, core-loop agent |
| Start of the managed phase in the labs | 4 people, 8 beds, food 40, water 60, ammo 79.8, meds 6, scrap 30, parts 2, fuel 0, morale 45. These are the `stores` defaults of a `--managed` boot, which skips the clear phase (prison_game.gd:106). A real New game enters the managed phase from the clear phase, which starts on `CLEAR_STORES` (food 25, water 12, ammo 60 less the 40-round kit, meds 3, scrap 4, parts 2, fuel 0; prison_game.gd:73) plus whatever the clear phase banks (unverified how much). People and beds for the real start were not re-checked | SNAP line of the `--auto=loop --managed` run; economy.md section 2 and its skeptic's missed item 3 |
| Real loot per 3-minute raid | Untargeted (n = 30 seeds, solid): parts 2.4, fuel 1.6. Hunting parts / fuel: 3.0 / 2.2, but each target gets only about 6 seeds in the 30-seed run (prison_loot.gd:384-401 picks `options[s % 5]` per seed), so these two are noisy; the 24-seed run gave 3.5 / 2.3 at 4 to 5 seeds per target. Bound: a whole town holds 1 to 10 parts and 1 to 4 fuel (12 towns) | `--loot-lab=30` and `--loot-lab=24` runs (reproduced by the skeptic); `town_stats.gd` probe, n = 12 |
| What the arc lab pays per raid | about 13 parts, about 12 fuel; more than a whole real town holds (1 to 10 parts, 1 to 4 fuel) | prison_arclab.gd:113-133 |
| Convoy parts need | 131 (power1 30 + radio1 40 + convoy1 30 + fence2 6 + 25 handed over) | prison_projects.json, prison_story.json |
| Perf, windowed, loaded M1 | avg 12.2 to 13.8 ms, p95 22 to 25 ms, 69 to 76 awake dead. No quiet-machine number exists: load average was 8 to 14 on 8 cores with a 100%-CPU Godot of another project beside it, so the p95 over the 16.7 ms budget may be load | 9 runs (runtime and skeptic); runtime-evidence.md:5, :44 |
| Frame hitch | one 361 to 507 ms stall per run, 9 of 9 windowed runs; not caused by the new sprites or animation (all art flags off: still 463 ms). Cause and frame position unknown: `--perf` does not log the frame index of the stall (prison_game.gd:1020-1031), so it is not known whether it falls at load, at the first alarm or mid-fight. Rated major (M20) | runtime skeptic |
| Quit | exit 134 in every prison run that quits; `--onehouse` exits 0 | runs; root cause prison_game.gd:201 and pawn_node.gd:67 |
| Web download | 83 MB pck plus 10 to 39 MB wasm, about 40 to 60 s at 20 Mbps; pck 44 MB on Oct 11, 83 MB on Oct 13 | runtime-evidence.md section 6 (arithmetic, not a measured load) |

### 2.4 What the first ten minutes look like

Reconstructed from code and three stills (`fi_title.png`, `fi_weapon.png`, `clear_guide.png`); no timed capture, frame series or video exists, and nobody has watched a human do it. The agents give frame 30 and frame 31 for the guide, so treat frame numbers as approximate. The weapon card also runs under the title band for about 2.6 s (a 2.2 s band plus a 0.8 s fade, with the weapon card opening at frame 25 in real play; first-impression.md:23, :109), and the card's description line is cut through by the band's top rule (`fi_weapon.png`). One windowed first-minute video is on the plan (Phase 1, item 6). The title is the One House scene (a dim house interior) under a prison tagline (`fi_title.png`). After New game, within 0.4 s the weapon card opens over the 2.2 s "THE OLD PRISON" band and a seven-second key line, then a four-card guide at frame 30 (`fi_weapon.png`). The clear phase has a clear goal ("Cleared 0/10") and a minimap. The managed base opens with 13 chips and four objective lines; night 1 comes about 3 real minutes later. The Needs board is the clearest teaching in the game.

---

## 3. What is good

Ranked by how much it will matter to a Steam player or to your speed of fixing things.

**1. The raid is a real extraction loop and it is the best part.** Five gate targets (default is the base's biggest need), a loadout card, a generated town with seven place types retagged onto the buildings, 3 s searches that open an 8x4 grid, companions with a five-state machine and their own bags, survivors who follow after E, hazards from one noise system, two extraction rings, and real loss on death (pack, gun, spare, any survivor; three deaths end the run). Evidence: prison_loot.gd, prison_squad.gd (1,102 lines), prison_people.gd, prison_game.gd:1449-1456; the loop run showed banking and loss with no state leaks. Skeptic: targeting pays clearly only for meds (10.2 vs 4.4 in the lab); rings and signs guide more than yield does.

**2. The noise system is real, data-driven and readable.** One `emit` call with heat per 16-tile region, walls that cost 2.6 tiles, hordes, car alarms, a HUD chip, ripples and minimap chasers (prison_noise.gd, prison_noise.json). A shotgun is heard at 66, 31 and 0 percent at 5, 10 and 20 tiles in the open (prison-extraction.md:261-265). It makes shooting a decision, the loop Project Zomboid sells. Caveat: the base horde part is dead code (C4).


**3. Four specials, endings and fail states that explain themselves.** Screamer, hunter, bloater and breacher have telegraphs and counters (prison_special.gd); nine endings are built from who lived and died (prison_endings.gd:47-116); the morning card lists fence lost, dead killed of sent, ammo and crew lost (prison_siege.gd:710-731).

**4. A spine with a deadline, with every number in JSON.** `prison_story.json` holds calendar, phases, requirements, the night table, weather, beats, letters, endings and score; `prison_siege.gd:337` reads `wave_plan(n)` from it. Six JSON files hold the economy, story, raids, noise, weapons and gunners. Tuning is data edits, not code, which is the biggest asset for the balance pass you owe the game.

**5. The dead move and crowd well, and the art is one family.** Turn rates by kind, lurch, rise, lean on the wire, crowd spread (prison_dead.gd); 0 pairs nearer than 0.25 tile in a 28-dead wave (prison-extraction.md:148); 44 baked zombie animation sets in the crew's look. `rimz2_game_day_1x.png` is Steam-screenshot grade (a 2x Retina capture despite its name).



**6. The HUD teaches in plain words.** Chips with hover tips (what makes it, what uses it, net, days left; prison_topbar.gd:464-490), an objectives tracker with a pulsing world ring (706-795), E prompts that state cost and time, a Needs board that ranks shortages with the fix.


**7. A fast, clean pipeline with clean rights.** 40 in-house Python and Blender scripts make every sprite and sound; Barlow fonts under OFL; the user folder is fixed as `ThirtyBells`; 458 commits in 15 days with a clean tree; a test harness that restores static state between cases.

**8. The test instruments are rare for a three-day-old game, and they can run the 30-day arc without a human.** Seeded labs (`--loot-lab=N`, `--econ-lab=30`, the arc lab `--arcauto=average|passive|expert`), a loop driver (`--auto=loop`), a clear-phase bot and `prison_drive.gd` (nine windowed UI drives, about 61 check calls by grep) let an agent play the whole arc headless in minutes and reproduce numbers: the skeptic reproduced the loot lab exactly and two `--auto=loop --seed=3` runs gave identical SNAP lines. The `--auto=loop` hand-over structure (prison_game.gd boots straight into the managed base with `--managed`) is what makes this cheap. The caveat belongs in section 4: these tools are manual and debug-only, not wired into `tests/` or any CI (STATUS.md:16; three of the nine drives fail and were carried into main, prison-extraction.md:174), and the arc lab runs on the wrong loot (C3). Turning two of them into a smoke test is M18.

---

## 4. What is bad

Ranked critical, major, minor. Each item has impact, evidence, fix and effort (S under a day, M a few days, L about a week or two, XL more). Skeptic corrections are applied. Items marked "refuted" in the first pass are listed at the end of the section so you do not chase them.

### 4.1 Critical

**C1. No save in a 3-hour run.**
- Impact: any interruption loses up to three hours. The refund window is two hours. The Left Behind (solo dev, zombie survival, 2026-07-27) sits at about 17 percent positive, and reviewers flagged no save alongside performance, clunky combat and confusing menus (research-player-expectations.md:216), so it is a warning, not a single-cause comp; the most-repeated negative for They Are Billions is no manual save.
- Evidence: the only `user://` writes in `scripts/prison` are `prison_arc.json` (best score, prison_endings.gd:9,264-275) and `prison_ui.cfg` (guide flags, prison_guide.gd:9). The pause menu is Resume, Controls, Settings, Quit (prison_pause.gd:118-121). 6 real minutes a day x 30 days = 180 minutes of game clock; the clock keeps running in raids (prison_game.gd:1040), so raid time is inside the 180, and only card pauses, the clear phase and cutscenes add real time on top. The title still shows Continue and Load, which read the old games' saves (title_menu.gd:105).
- Fix: see idea 1. A new `prison_save.gd`, versioned JSON, autosave at dawn and on raid return, Continue on the title, "Save and quit" in the pause menu.
- Effort: M (3 to 5 days per the feasibility agent) when limited to the calm base; L if hordes and specials mid-fight must be kept (they should not be).

**C2. The aim rule contradicts every on-screen hint.**
- Impact: a new player clicks, nothing fires, nothing turns. Many will decide the gun is broken inside thirty seconds of the clear phase.
- Evidence: `prefs.gd:16` defaults `aim_mode` to `"right"`; `aim_mode.gd:116-121` ("a left click without it never fires"); prison_game.gd:1205 uses it. The words: prison_guide.gd:14 "The mouse aims and the left button fires", prison_game.gd:669, and the Controls page (prison_pause.gd:15). The drivers force the aim (prison_game.gd:1200), so no test notices. Shift is an undocumented fallback. The toggle exists only on the title's Settings screen, and the prison's pause Settings page has only volume sliders, so a player who learns the rule mid-run must quit the process and lose the run.
- Fix: prison-only default of "always" aim (do not change the global default, tests/test_r22c_controls.gd:180-189 assert "right"), plus a pause-menu toggle, plus a first-minute cue.
- Effort: S for the text and default; add 0.5 day for a feel pass on the shotgun and SMG cones.

**C3. The convoy goal has never been tested against real raid yield.**
- Impact: either the convoy is unreachable for an ordinary player (every run ends "held" or overrun), or companions' bags close the gap and nobody knows. The central promise of the game is unverified.
- Evidence, led by the bound: across 12 generated towns a whole town holds 1 to 10 parts and 1 to 4 fuel (`town_stats.gd`, n = 12; raids-loot.md:57), yet the arc lab pays about 13 parts and 12 fuel per raid (prison_arclab.gd:113-133). The lab pays more than many real towns contain. The must-list needs 131 parts (power1 30, radio1 40, convoy1 30, fence2 6, plus 25 handed over) and about 65 to 70 fuel.
- Measured raid yield, with n per figure. Untargeted 3-minute raid, n = 30 seeds (solid, the skeptic called it so): parts 2.4, fuel 1.6; the 24-seed run gave 2.5 and 1.5. Hunting a target: parts 3.0 and fuel 2.2 in the 30-seed run, but `prison_loot.gd:384-401` picks `options[s % 5]` per seed, so each target rests on about 6 seeds (4 to 5 in the 24-seed run, which gave 3.5 and 2.3). Treat the two hunting figures as noisy, roughly 2.5 to 3.5 parts and 2 to 2.5 fuel.
- Over-pay factor, range by agent: the first economy agent said 4 to 6 times; its skeptic computed 4.5 times on parts (13.6 against 3.0) and 5.5 times on fuel (12 against 2.2); the first raids agent said 3.7 and 3.5 times; the raids skeptic said 2 to 4 times is safer. Read it as "about 2 to 6 times, centre about 4". Direction is certain (the lab is richer than the towns); size is not.
- The old arithmetic, kept as an illustration only: at 3.0 parts per hunt the parts list alone is about 37 hunting raids and fuel about 25 more inside 30 days. It stands on the noisy hunting cells, so the town ceiling above is the firmer statement. Scrap is about 3 times short too (hardware scrap 24 in the lab against about 9 per real raid).
- Biases in the loot lab, in both directions. Make the lab number too high (a human gets less): it is a greedy 180 s walk (4 tiles/s, 6 s per container, nearest first) with no fights and no dead to lose time or the pack, and no 32-cell pack limit (the economy skeptic calls it an upper bound). Make it too low (a human gets more): no companions (their bags add loot, though they go to houses, which hold no parts), no human choosing the best containers, a fixed 180 s, and cars are not searched (cars hold ammo, food, water, meds and scrap, but no parts or fuel, raids-loot.md:55, so this matters little for the convoy list). The core-loop skeptic called 3.0 "a floor"; the economy skeptic called the lab "an upper bound"; both are right about different terms. The net direction is unknown until a human run.
- Lab start state is richer than a new game. Labs started with `--managed` use the `stores` defaults (food 40, water 60, scrap 30; prison_game.gd:106), not `CLEAR_STORES` (food 25, water 12, scrap 4, parts 2; prison_game.gd:73) plus what the clear phase banks. Every lab opening, including the arc lab's, is richer than a real new game (economy.md skeptic, missed item 3).
- Feasibility experiment (scratch copy): the arc lab patched to measured loot ends 0 of 8 seeds alive (overrun day 16 to 18). That only shows the lab's night model was calibrated on lavish loot; it bounds the arc, it does not decide it.
- Dropped: the "cap 60 against 131" framing; the cap is a stock ceiling and the largest single outlay is 40. Say "probably short, unmeasured", not "unreachable".
- Fix: idea 4. Make the lab call the real loot model, cut costs or raise rolls, then play days 1 to 30 by hand twice.
- Effort: S for data and lab (1 to 2 days); the human runs are playtest time.

**C4. The base horde never fires.**
- Impact: the documented hordes on nights 3, 6, 9 and 12 (34, 58, 82, 100 dead) do not exist in normal play. Docs (prison-extraction.md:246) describe a feature the player never sees; the night 3 "cliff" the first combat agent reported is refuted for the same reason (see 4.4).
- Evidence: prison_noise.gd:639 `(bc.nights as Array).has(n)`. JSON gives floats, so `[3.0,6.0,9.0,12.0].has(3)` is false. The skeptic printed "NIGHTS false" in a GDScript test, and a natural `--siege=3` run showed no "NOISE base horde" line. It spawns only when forced (`--horde`, `--noisetest=horde`).
- Fix: `has(float(n))`. But this turns on a 34-dead night 3 that nobody has ever played. The wave the siege actually sends on night 3 is 3 (guard-scaled, 2.1), so the horde is more than 11 times the real wave, not about 4 times the table's 8, and the arc lab does not model hordes. Budget a guard-scaling pass: scale `base_horde.size` by the same armed-guards factor, cap early hordes near 12, and move the first one to night 5 or 6.
- Test together: the horde fix, the guard scaling of the horde and the after-dawn night model (M1) all change nights 3 to 12, and none has a measured baseline. Run them in one lab pass, not one at a time. Proposed pass criteria (the reviser's, to be tuned): on a two-guard base no night 3 to 12 loses more than half of the fence's total hp; no run loses all four segments of a side before night 12; ammo spent per night is under 30 percent of the stock; the morning card's dead killed is at least 90 percent of dead sent.
- Effort: S for the fix, plus 1 day to rebalance.

**C5. The prison cannot quit cleanly.**
- Impact: every quit that was run aborts, and on this Mac that wrote an OS crash report (Abort trap 6). macOS holds 50 Godot `.ips` reports, some of them from the audit's own runs (docs wrongly call the abort harmless, prison-audio-report.md:230). Whether Steam would record it as a crash is a guess; the OS report is fact. It also blocks any headless prison test. Whether the windowed pause-menu Quit and a window close behave the same is unverified.
- Evidence: runs: `--headless --quit-after 240 -- --prison --nosave` exit 134 `libc++abi: ... recursive_mutex lock failed`; windowed the same; `--onehouse` exits 0. Root cause: prison_game.gd:186-203 stores lambdas capturing `fx` in static callables (`PawnNode.hurt_cb`, pawn_node.gd:67) with no `_exit_tree`. In a scratch copy, resetting all five static callables (`PawnNode.hurt_cb`, `Hanim.threat_cb`, `RimzFrames.blood_cb`, `PawnMotion.thump_cb`, `PawnMotion.step_cb`) in an `_exit_tree` gave exit 0.
- Unverified: the pause-menu Quit path itself (`_exit_tree` should fire on it), the window-close path, and what Steam's client does with an exit-134 abort.
- Effort: S.

**C6. No desktop build exists and no desktop run has ever happened.**
- Impact: Steam ships a Windows build. `project.godot` sets no `rendering_method`, so desktop uses the Forward+ default from the features line (project.godot:17) with the D3D12 driver on Windows (`rendering_device/driver.windows`, project.godot:46). That combination has never been seen on Windows or on an integrated GPU. The web build forces the Compatibility renderer, so desktop and web render differently.
- Evidence: export_presets.cfg has three presets, all Web. Templates for 4.7.2 are installed. In a scratch copy a Linux preset exported headless in 7 s to a 156 MB single file. Windows and macOS were not tried.
- Fix: add Windows, Linux and macOS presets and a hash-named export script; run on one real Windows laptop with an Intel iGPU. **Recommendation: ship the Compatibility renderer on desktop.** It is a 2D game, the web build already runs on it (title at 60 fps), it has the widest driver coverage including integrated Intel GPUs and the Deck, and the D3D12 setting only matters to the Forward+ and Mobile renderers (Godot docs; not re-checked here). Proposed minimum spec, unmeasured: Windows 10 64-bit, 4 GB RAM, an Intel UHD 620 class GPU, 1 GB disk. Gate for Phase 2: one run of the 30-day arc lab with `--perf` and one human session on a Windows laptop with an Intel iGPU, on Compatibility and on Forward+, before the choice is final. Settings that need a second look under Compatibility: the 2D light and tint, the canvas filter (`default_texture_filter=3`), `msaa_2d` (project.godot:48). The skeptic lowered this from critical to major because the config is minutes of work; the risk is the untested hardware.
- Effort: S for presets, M with the Windows test pass.

**C7. No store assets, and the name collides.**
- Impact: a Steam shopper decides on the capsule in a second. There is no Steam-format art for the prison: no capsule set, key art, hero or trailer. The repo copy of the itch cover in `build/itch-page/` is dated Sep 29 and shows the school prototype, but that copy is stale: STATUS.md:14 says the itch description, six 1280x720 screenshots from the current build and the cover (a tower-guard crop) were rewritten and retaken for the prison on 2026-10-13, and those files are not in the repo (first-impression skeptic: unverifiable from the repo), so the live itch page does have prison art. What is missing is Steam-format art, not any art. The skeptic notes this is a marketing deliverable and not a game defect, but it is on the critical path to a store page.
- Name: see section 9.5.

### 4.2 Major

**M1. A raid that returns after dawn cancels the night; a skipped night 30 yields "held".**
- Evidence: run: `--raidsecs=160 --hour0=20.6` returns 07:48 with `nights_started=1` and no attack; 60 s returns 01:08 and the attack starts. Code: `siege.update` runs only in base mode (prison_siege.gd:164), and the catch-up branch sets `nights_started = n` with no attack when past dawn (lines 271-280). `_late_end` (prison_arc.gd:703-715) gives "held" if `nights_started >= convoy_day`, with no fence check, so a raid out through the 95-dead night 30 ends the run on a good ending. The `back_t` rule (a night that falls during a raid starts on return) is deliberate ("harsh, owner call", prison-playtest.md:18); only the after-dawn hole is the bug.
- Fix: resolve the missed night from a model (fence loss, crew roll, ammo) with a morning card, or stop the clock in raids and charge a fixed 4 to 6 game hours. The proposed "start the night at the gate" does not work as written: `_start_attack` falls straight into the over-dawn test and ends. Do this before requiring `nights_held >= 30`, or a run can sit past day 30 with no ending.
- Fix risk: the after-dawn probe was run only headless (seeds 3 and 7 loops), never with the real gate cutscene, and the "resolve the missed night from a model" fix is untested against the base-horde fix (C4) that also changes nights 3 to 12. The three night changes (horde fix, guard scaling of the horde, skipped-night model) must go through one lab pass with the pass criteria listed under C4 (fence lost per night, ammo spent, crew lost).
- Effort: M.

**M2. Raid time is invisible, and the raid clock disagrees with the HUD.**
- Evidence (skeptic probe): the raid sim runs its own clock. `TownRun` sets `sim.minutes` to 10:00 (town_run.gd:23) at 3 game minutes per second (sim.gd:281), while the HUD hour runs at 4.0 per second (prison_game.gd:58,1040). Night wake x1.8 (town_sim.gd:241) therefore fires about 188 s into a raid, unrelated to the clock the player reads, and the screen stays bright (prison_game.gd:2582 forces white outside the base). The first agent's claim that night wake is "not wired" was refuted; what is missing is warning and tint. The raid row does have a sun and moon clock chip.
- Fix: two lines in `_enter_raid` (`sim.minutes = tod*60`, `sim.min_per_sec = DAY_MIN_PER_SEC`), a dusk ring on the HUD, a one-minute chime, a tint when wake starts.
- Effort: M (idea 9).

**M3. No time control.** `time_scale` has 0 hits in `scripts/`. A 6-minute day with idle base time reads as slow; a 3 to 5 minute raid burns 11 to 20 game hours. They Are Billions players ask for exactly this ("time acceleration", research-player-expectations.md:141). The dumps give no source for speed controls in Sheltered or RimWorld, and Rebuild 3 is turn-based, so the claim that peers have speed keys is dropped (unverified). Effort M (4 to 6 days, idea 9). Note `_tick` clamps frame dt to 0.1 and modules use variable dt, so 3x needs sub-stepping.

**M4. Ruth cannot be hurt in the managed base and cannot fail the clear phase.**
- Evidence: `run.invulnerable = true` (prison_game.gd:606), hp reset every step (1164-1166), a downed Ruth in the clear phase is teleported to the breach with 100 hp (2228-2235), siege comment "Ruth is untouchable anyway" (prison_siege.gd:394).
- Skeptic correction: severity major for the siege, minor for the clear phase (allies die for good; revive costs a med; prison_game.gd:2240-2256). It is a decision recorded in prison-management.md:124 as a fact, not a bug. The cost is that nights carry no personal stakes.
- Fix: idea 12. Caveat from the feasibility agent: Ruth is not in `crew.members`, `_bites` works by zombie distance to the inside of the fence, and the dead notice nobody in the managed base (`quiet=true`). So removing the flag alone does little; the risk exists only after a breach.

**M5. One choice in thirty days.** Eight beats, only `the_dam` has a choice, and it only moves stores and morale. The `l_weir` letter clue has no payoff, and letters are random (0.28 per raid) so it may arrive after day 12. The story is read, not played. Fix: idea 14 (event deck). Effort M.

**M6. The convoy list is hidden until day 18, and convoy1 is in no stage.** `objectives()` shows the requirements only in the evacuate phase (prison_arc.gd:258-262), which opens on the day-18 "arrangement" beat or the Fortress stage. `convoy1` (30 parts, 10 fuel) is in no stage, so the stage tracker steers parts into power2 (24 parts) and Hub tiers the convoy does not need. The lab bot starts the convoy path on day 6 because day 18 is too late. Fix: show the list from day 3 with a parts total and put convoy1 into a stage. Effort S.

**M7. Fuel requirement equals the fuel cap, and the convoy is a one-shot.** `caps.fuel 40` and the requirement `fuel 40`; the generator burns 1 a day from power tier 1; the lab's list flickers 4/5 and 5/5 from day 19 to 29. Worse (skeptic): the convoy card opens at 11:00 whenever Ruth is in base; if unready you get only "Watch them leave" and it is gone for good; a raid back after 15:00 silently loses it, with no card (prison_arc.gd:720-751, 729-734). Fix: requirement 32 or cap 60, a warning at the gate on day 30, truck tank. Effort S.

**M8. "Held the fort" is a good ending without the convoy.** `endings.held` tone good, score 40 vs evac 60+20. The route is the overrun gap timer under 25 s (prison_arc.gd:679-682) or `_late_end`. Fix: held with the list unmet is bitter, score 20. Effort S.

**M9. No difficulty, no seed, one map, fixed beats.** `grep -i difficulty scripts/prison` is empty. The New game card passes `{difficulty, seed, town}` but nothing in the prison reads it, and its facts line still says "A bite infects N times in 10" (new_game_menu.gd:269-271; STATUS.md:14 admits it). Base.build(1, clear) is the one hand-authored compound. The raid town seed is `1000 + raids*17 + Time.get_ticks_msec() % 997` (prison_game.gd:679), so runs and bug reports cannot be replayed, and 142 unseeded `randf`/`randi` calls mean even a seed fixes the map and loot only. Fix: idea 10. Effort S to M.

**M10. The first-minute stack and the two ammo units.** Weapon card, title band, key line and guide overlap (`fi_weapon.png`; the skeptic rates the overlap minor to moderate). The gun readout shows shots (`6 / 117`) while the top bar shows store units (`20 ammo`, `spare 40`); in the base the pack is empty so it reads `6 / 0` beside `Ammo 79/400`. The `kit` is taken at the clear-phase start (prison_game.gd:600, "her rounds are the pack's") and at each raid start (:703), but not on entering the managed base, which is why the base readout shows 6 / 0. Effort S (idea 2).

**M11. Title screen shows the wrong game.** The title boots a small One House town at dusk (main.gd:367-370, title_scene.gd:108-109, `fi_title.png`) with a stale Continue entry. Effort M for a baked still; 2 to 3 days for a live prison title.

**M12. The prison ignores most settings.** Text size, UI scale, colour-blind, reduce-flashes and brightness are not read by the prison's own UI (0 references except audio, prison_pause.gd:142-148); the backpack windows honour them. Brightness has no control although darkness was the first outside complaint. F11 is dead (main.gd:370-380). M.

**M13. No InputMap, no rebinding, no controller.** 0 `is_action`, 0 joypad, no `[input]` section; 102 `KEY_` references. Steam Deck Verified is unreachable; "Playable" via keyboard-mouse emulation is not excluded. Effort M for InputMap plus a rebind page; L for a controller layer.

**M14. Audio nobody has heard, mono and low-rate.** Wave-header scan: 70 prison files at 22.05 kHz mono, 22 (all music stems and ambience) at 16 kHz mono; music has an 8 kHz bandwidth. Special stings are code tones (prison_noise.gd:810-820; `Noise.sting` falls through to `_play`). Gunshots in the legacy folder are already 44.1 kHz. S for the listening pass, M to L for the rest.

**M15. Every raid is the same kind of town, and loot has no surprise.** 64x64, two blocks, daylight, the same seven place types forced by `min_places` in 96 to 100 percent of seeds, two exits, 14 item ids, guns only in police at 8 to 10 percent, 6 to 14 of 23 to 41 cars hold anything. Layout and loot do vary per seed; the sameness is of kind. L (idea 15).

**M16. Fight-depth gaps (design, not defects).** Every hit staggers a dead one 0.25 s whatever the gun, so the SMG stun-locks (sim.gd:1368, code-read). The shotgun reload is one 3.4 s block while the HUD draws shell pips (avatar.gd:690-720). The breacher can remove a 120 hp segment in two rams (prison_special.gd:478-505) though it is about a quarter of specials on night 4. NPC guns are dice rolls (prison_game.gd:2068-2113). Only tower guards shoot; the player has four night levers. S each; L for crew posts and barricades.

**M17. Melee and sprint are half-wired.** Corrected: melee is the tuned one (TownSim `is_one_house()` is true, so `melee.json` applies). What is missing is `fx.combat.set_melee` (called only at main.gd:727), so F has no hit-stop, push or trail; the combat skeptic calls the fix one line in `prison_game._make_stage` (combat.md:213; whether that line alone brings hit-stop is unverified, because idea 16's code check says the prison must also read `camera_push()` and `frozen()`). Sprint is unwired (`set_sprint` has one caller, main.gd:2298; prison_game.gd:4) but `sprint.gd` would run with noise built in. Only flood runners (3.3 to 4.6 tiles/s) beat Ruth's 3.2. Use X, not Shift. The `set_melee` line is S (polish item 3 in section 5); sprint, hit-stop reads and per-gun stagger stay M (idea 16).

**M18. No prison tests.** None of the 214 test files (223 `.gd` files in `tests/`) cover the 18,253 lines. `--prison --managed` boots headless (240 frames), so a smoke test is S. The labs, drivers and the clear-phase bot are manual and debug-only, not wired into any CI (STATUS.md:16), so "the arc can be tested headless" (section 3, item 8) is a capability, not a safety net. What the smoke test should check: (1) `--headless --prison --managed --quit-after 240` logs no `SCRIPT ERROR` or `ERROR` line; (2) a 60-frame tick with no logged error; (3) arc lab seed 1 reaches a named ending (today `evac_good` or `evac_full`; after the C3 retune, whatever the new expected ending is); (4) quit exit code 0 (needs C5); (5) a unit test that the horde nights match integer nights (the `has(float(n))` bug); (6) the six prison JSON files load and have their required keys. Shared render code (`hanim.gd`, `rimz_frames.gd`) also has 0 tests.

**M19. Asset weight and AI pictures.** `export_filter=all_resources` with no asset excludes. Imported: `zombies16` 12.1 MB, `ui/sites` 1.4, `ui/theme` 0.8, portraits 0.8, walls 0.3. The 22 Meshy pictures still ship; a scratch run without `ui/theme`, `ui/sites` and `deck_*` showed identical prison screens. `OFL.txt` is not in the pck; `icon.svg` is Godot's stock icon. S.

**M20. A 361 to 507 ms stall in every windowed run.** The runtime skeptic rates it major, a visible freeze of about half a second: it appeared in 9 of 9 windowed runs, does not depend on the art flags (all off: 463 ms), and the old docs show no frame above 14 to 27 ms. Cause and frame position unknown: it falls somewhere in the measured window of frames 600 to 1800, and `--perf` does not log the frame index (prison_game.gd:1020-1031), so it may be a first-alarm spawn, a rebuild or a garbage-collection pause, at load or mid-fight (all unverified). The avg and p95 numbers were taken on a loaded machine and there is no quiet-machine figure, so even the baseline is unsure. Fix: log the frame index and the active system, then bisect. Effort S to find, unknown to fix.

**M21. Readability at 1280x720 and Deck size.** STATUS.md:24 and `docs/hud-audit.md` record a friend who could not see a zombie behind the tutorial cards at 1280x720; that was the One House town, and the minimal HUD answered it for that game, not for the prison. The prison's own evidence: chip text is 15, 13 and 9 px (prison_topbar.gd:213-218) against the Deck's smallest-text floor of 9 px at 1280x800 with 12 recommended (research-name-and-legal.md, Valve doc; this HUD was not measured against it); name tags pile up over three people (`ui2_base_day_1280.png`); the weapon card, title band and guide overlap on the first screen (`fi_weapon.png`); the prison ignores text size and UI scale (M12); the 1x non-Retina look is unseen because the 1x capture path is broken (Phase 1 item 9); and the drivers checked the HUD only at 1024x640 and 1280x800 with "a human look at the sign sizes at the smallest window" still open (ui-ux.md:148). Fix: a 12 px floor for chips and tags at 1280x800, merge tags within 2 tiles, hide the tracker while a board is open, wire UI scale (M12), and re-shoot the first minute at 1x. Effort M.

### 4.3 Minor

- **Banked line counts the returned kit as loot** (prison_game.gd:1442-1448). Stores are correct (ammo 79.5 to 39.5 on death in the loop run); only the 10 s message is wrong. S.
- **Lab artifacts, not yet defects:** morale pinned at 100 from day 13, food and water at cap from day 8, parts pinned at cap. They come from the over-rich raid model; parts, fuel and scrap stay scarce with real yields.
- **Role gate:** `can_start` refuses a project with no living role holder (prison_econ.gd:171), Ruth cannot start one, and the refusal does not say "press B". The mechanic gates fence, power, radio and convoy, and the start crew has none.
- **Note-only effects:** the radio room and infirmary 2 and 3 do nothing the player can feel; the board blurb "Calls survivors to the prison" is false (prison_board.gd:25). `daily_report` nets only food, water and fuel, so scrap spent by recruit loops is invisible.
- **Crew are role strings** with no traits; the leaver is the least-missed person. A design wish, not a defect.
- **Process hygiene:** 108 `await` calls (a resumed coroutine on a freed instance logs and stops; it does not crash); 11 process-wide `PawnNode` statics; econ, siege, noise and crew run on clamped frame dt, so labs need `--fixed-fps 60`.
- **God object:** prison_game.gd is 2,619 lines, 43 preloads, 100 member vars, about 490 to 537 lines of bot code.
- **Docs drift:** STATUS.md is 127 KB, README has 0 prison mentions, `docs/experiments/README.md:3` says nothing is merged, `prison-management.md:166` says Ruth builds early projects (false). The lab's `ready=false` and `share=1.09` print fields are computed after hand-over (unverified).

### 4.4 Refuted or reduced after the skeptic pass

- **Night 3 cliff from a 34-dead horde:** refuted, the horde is dead code (C4). The real step is the forced uncovered segment from night 3 (prison_siege.gd:352-360); a run lost a north segment 120 to 0 hp by 100 s with nobody defending.
- **"Melee is the untuned old blow":** refuted; `melee.json` is in effect (M17).
- **"Archive `scripts/raid` as dead code":** refuted. It is 8,082 lines, and `site_gen.gd` and `site_canvas.gd` are preloaded by TownGen, TownKit and BuildingGen, which build the raid town. Only `raid_scene`, `raid_run`, `raid_sim`, `squad_ai`, `hud`, `overlay` are legacy.
- **"Clear-phase loot barely reaches the stores":** refuted; the bot never stashes, and gun loss on death is documented design.
- **"The fence is drawn whole at any hp", "towers are brown boxes", "Cole does not shoot", "zero commits to main.gd", "a seed replays the same game":** all wrong or stale (cracked, sagging and down states exist; occupied towers show heads and rifles; Cole and Bea are tower guards, prison_crew.gd:87-89; one hand-over commit; only the sim uses the fixed step).
- **"The dead shimmer at 1x":** reduced; the default filter is Linear Mipmap. Still unseen on a 1x display.

---

## 5. What needs polish

Ranked by value per day. All are small and independent; items already covered as bugs are not repeated.

1. **Space the first-minute cards** and hide the guide while the loadout card is open (prison_guide.gd:161). S.
2. **One ammo unit everywhere**, and top up the pack on entering the base so `6 / 0` stops appearing. S.
3. **Wire the melee feel.** One line in `prison_game._make_stage` calls `fx.combat.set_melee(...)` as main.gd:727 does for the town (combat.md:213), so F gets its trail and, if the prison reads `camera_push()` and `frozen()`, hit-stop and push (unverified). Sprint and per-gun stagger stay in idea 16. S.
4. **End-of-raid report card**: found, spent, brought back, kills, time out, rescued, lost. M.
5. **Message plates and one toast channel**, plus a short stacked log (45 `_say` call sites overwrite one label). M.
6. **Name and job tags** only for hovered or nearest people, merged within 2 tiles. M. Part of the readability item (M21).
7. **Hide the tracker and E prompt while the board is open**; place the hover tip clear of row 2; fonts in the readout and prompt (prison_hud.gd:109); hp bar coloured by fraction (prison_game.gd:421). S.
8. **Controls page** (16 rows) lists right button, H, Shift+E, Space, belt 1-4, choices 1-9, B's two meanings, derived from one table. S.
9. **Real stings for specials** in `tools/make_prison_audio.py`, routed to `prison_audio.stinger`; a breacher roar and minimap flash before the first ram. M.
10. **Shell-by-shell shotgun reload** with trigger cancel. S.
11. **Hunter leap arc, own corpse frames for screamer, bloater, hunter, a truck sprite** instead of drawn rectangles. M.
12. **Bring `rain_view.gd` into the prison** (781 lines, old game); today a storm only darkens the grade. M.
13. **Smoke, impact puffs, a longer muzzle flash.** S each.
14. **Gate choice shows expected yield; loot stacks reveal during the search.** S.
15. **Parts and fuel icons** (today a generic box, prison-management.md:87). S.
16. **Pause menu**: Back to title, fullscreen, version string, copy log path. S.
17. **Clean shipped strings**: "Thirty Bells demo" (demo_end_card.gd:2), stale `TAGLINE` fallbacks, the difficulty facts line, the red-cross cabinet (town_art.json:11354, a protected emblem; whether the prison raid town draws it is unverified, so check before removing). S.
18. **A field-guide card on first sight** of each special and one on noise before the first raid. S.
19. **Housekeeping**: spike logging in `--perf`, prune `build/` (1.2 GB), hash-named export script, refresh `KNOWN_BUGS.md`, STATUS and README, add a one-page CURRENT.md. S.

---

## 6. Subsystem by subsystem

Grades are mine, from the agents' evidence. One scale for every row: the thing as it is today against a shipped 2D Steam peer in this niche at its launch (Rebuild 3, Deadly Days, Into the Dead: ODD). A matches a peer; B is one polish pass away; C is playable but has a gap a reviewer would name; D has a blocker a reviewer would name inside the first hour; F is missing. A grade is not "good for three days of work". Rows that rest on code reading with no player run say so and are provisional; audio is left ungraded because nobody has listened. Almost every grade carries "no human has played".

| Subsystem | Grade | Why | Skeptic's corrections |
|---|---|---|---|
| Core loop, pacing, story | C+ as a design, D as a tested product | Up: a deadline, every number in JSON, a raid-by-day siege-by-night rhythm, named nights, earned endings. Down: days 15 to 30 never played; balance from an over-paying lab; a 6-minute day with no time control (a 160 s raid eats 10.7 game hours); an after-dawn return cancels the night; one choice in 30 days; no save; no difficulty | "Unreachable" became "probably short, unmeasured"; "one raid every day" is the lab's policy, not a game demand; "morale 100 from day 13" is a lab artifact; held-ending route is the 25 s gap timer or `_late_end` |
| Combat, specials, noise, sieges | C+ (code reading only, no player run; provisional) | Up: noise system, four telegraphed specials, a full hit-feedback kit, dead that move and crowd well, siege consequence chains, perf headroom to 192 awake dead at about 12 ms (M1, doc). Down: the base horde is dead code; stun-lock; breacher without a counter; passive crew; melee feel and sprint unwired; dice-roll NPC guns; tone stings. All feel claims are code reading; only `--only=dead1` (12 passed) plus three skeptic runs | Melee is tuned (refuted); the night 3 horde cliff is refuted (C4); Ruth invulnerability major not critical; Cole and Bea do shoot; four night levers, not three |
| Economy, base, people, morale | C- | Up: a small core (prison_econ.gd, 635 lines) over one JSON, three labs, a readable needs-to-target loop, cards with exact deltas, beds tied to rescue. Down: labs use loot about 2 to 6 times too rich and open on richer stores than a real new game, so every tuning rests on wrong numbers; role gate; people are role strings; morale has one dead rule; stages are labels; radio and infirmary are notes; no player conversions; no tests | "Solved by day 8" and "surplus thrown away" are lab artifacts; scrap drain was `--crew=full` only. New: the mechanic is a single point of failure for the convoy chain; convoy day is a one-shot |
| Raids, extraction, loot | C | Up: section 3, item 1. Down: same kind of town, flat loot, two exits, rescue is a pickup, no human hour. Written in 3 days with no tests; three of nine `--drive` checks failed when merged (prison-extraction.md:174, not re-run) | Banked bug major to minor; "same town" is "same kind of town"; the raid night clock exists but is out of step with the HUD; a rescue is lost silently at the ring with no bed |
| UI, UX, onboarding | C | Up: tooltips, tracker, Needs board, E prompts, morning card, guide hides in fights. Down: the aim rule, no save, hard-coded keys, ignored settings and brightness, difficulty card ignored, one message line, two ammo units, specials taught only when they hit, a volume-only pause menu | "No event log" overstated (siege banner, people banner, morning card, story log exist); Esc does pause the tree |
| Art and presentation | B- | Coherent look, store-grade gate screenshot, 44 animated zombie sets, hanim, a zero-PNG polish pass. Down: three character generations and two projections in one scene, flat tint for light, no rain, admitted animation gaps, thin VFX. Survivor pool: 21 of 24 have palette overrides | "29 survivors all empty looks" was wrong; fence damage is drawn; 1x shimmer reduced to minor |
| Audio | Ungraded (never heard) | A nine-stem adaptive score, bus layout, machine-measured, never heard. Mono, 16 to 22 kHz, 16 s loops in one key. The owner can settle it in 4 minutes with `--audiotour` | Gunshots in the legacy folder are already 44.1 kHz |
| Code and tech | Maintainability C-, Steam risk HIGH, velocity A (speed of change, not a peer comparison) | Up: fixed-step sim clock, module-plus-JSON pattern, a good harness, QOA audio, save patterns to copy, clean history. Down: zero prison tests, quit crash, no desktop build, god object, hard-coded keys, unseeded RNG | Texture memory is normal on desktop; coroutines do not crash; "a seed plays the same game" is false for the prison layer |
| Release readiness | F (the Steam items are missing) | Missing: save, desktop presets, version string, studio name, Steamworks account, controller, rebinding, localisation (0 `tr()`), store text (docs still describe One House), capsules, trailer, 1080p stills, content survey, trademark check. Present: clean rights, user folder fixed, templates installed | Settings prefs exist for the old shell, not for the prison |
| First impression | Hook C+, first 10 minutes C, visual B- | The hook is sayable and the art reads. The first screen is a text pile, the title shows the wrong game, the HUD is a spreadsheet by minute three, no hero image | Store art is a marketing task not a defect; an idle player with guards held night 1 (8 of 8, no fence lost) |

---

## 7. Competitors

All unit figures are estimates (reviews times 30 to 50, GameDiscoverCo's Boxleiter band) unless marked official. Review counts were read from the Steam reviews API (all languages) on 2026-10-13 or 14 (research-direct-competitors.md section 7); a later pull gave 8 to 12 percent fewer reviews for the same games (likely a filter difference), so treat counts as ±10 percent. Gamalytic and SteamDB were unreachable, and Raijin figures come from dated search snippets. "What they do better" and "how Last Bell differs" are my reading of the research and the repo, not play; Last Bell is unplayed, so no row claims it does anything better.

### 7.1 Comparison table

| Name | Year | Price | Reviews (pct) | Est. units | What they do better | How Last Bell differs on paper (unplayed) |
|---|---|---|---|---|---|---|
| Infection Free Zone | EA 2024 | $24.99 | 18,764 (81%) | 563K-938K | Real-world maps, build anywhere, 3D, frequent updates, content depth | A hand-built prison with one compound, a 30-day arc with endings and extraction raids (on paper); its complaints (fragile walls, tedious repair, squad AI, thin content) are your risks |
| Into the Dead: Our Darkest Days | EA 2025 | $24.99 | about 9,200-10,030 (89-90%) | 300K-500K | Studio polish, distinct survivors, atmosphere, a 300K-download demo, publisher | Open base layout, shooter raids, prison setting; yours is solo and unpolished |
| Rebuild 3 | 2015 | $14.99 | 2,051 (86%) | 62K-103K | Claim zones, factions, backstories and perks, four-X pull | Real-time action and a fixed finish; Rebuild 3 is turn-based |
| Deadly Days (and Roadtrip) | 2019 / EA 2025 | $11.99 / $14.99 | 1,917 / 3,062 (86% / 88%) | 58K-96K / 92K-153K | Tight loop, auto-firing crew, item variety, value | A bigger base layer and a story arc on paper (unplayed) |
| Dead Age | n/g | $14.99 (SteamSpy) | 5,612 (81.6%) | 168K-281K | 2D camp management with turn-based combat and events; detailed camp | Real-time raids and a night siege; its complaints (menu-driven camp with "very little player interaction", the same event order every run, a boring early game) are your risks |
| Sheltered | n/g | $14.99 (SteamSpy; EUR 12.99 store) | 6,301 (81.8%) | 189K-315K | 2D side-scroll shelter sim, cheap and readable | Action raids and a deadline; its complaints (agonising micromanagement, slow stockpiling, rarely punishes complacency, "boring after about 2 h") match your idle-base risk |
| Zombie Night Terror | n/g | $12.99 (SteamSpy bundles) | 4,029 (93.1%) | 121K-201K | Lemmings-style puzzle: not a comp | Not comparable; a data point that a 2D zombie game can sit at 93% |
| The Last Stand: Aftermath | n/g | $24.99 (SteamSpy) | 6,844 (80.5%) | 205K-342K | Top-down roguelite shooter with permadeath | Shooter only; no base |
| HumanitZ | EA 2023, 1.0 2026-02 | $19.99 (SteamSpy) | 14,594 (74.3%) | 438K-730K | 3D co-op survival | 2D, solo; its complaints (bugs, repeated points of interest, tedious looting, no endgame) are warnings |
| Night of the Dead | 1.0 2024 | $29.99 (SteamSpy) | 11,901 (76.9%) | 357K-595K | 3D co-op base | 2D, solo; its companions are called "boring and useless" |
| Quarantine Zone: The Last Check | 2026-01-12 | $19.99 | 12-13.5K (82%) | official >1M in 3 months (Devolver, may include Game Pass) | One-line hook, viral demo, publisher, 1M+ wishlists | Real zombie action; not a reachable baseline |
| Project Zomboid | 2013 EA | $24.99 | 488K (94%) | 8.2M-16.8M | Depth, mods, lighting, emergent stories; B42 raised CCU to about 121K | A fixed end and structure; not a scale comp |
| 7 Days to Die | 2013 EA, 1.0 2024 | $44.99 | 402K (87%) | 6.4M-13.5M | Build-by-day horde-night loop in 3D | Smaller scope, handcrafted |
| State of Decay 2 | 2020 Steam | $29.99 | 70K (83%) | 1.4M-2.1M | Community and base in 3D, co-op, readable base UI | The slot is 2D; complaints (shallow base, useless follower AI, grind) map to your companions and upkeep |
| They Are Billions | 2019 | $29.99 | 51.5K (85%) | 1.1M-1.5M | Wave tension, RTS control | Personal shooter control; they punish with no manual save and snowball |
| This War of Mine | 2014 | $19.99 | 98K (94%) | official 7M all platforms | Emotional storytelling, atmosphere, survivors with inner life | Action raids; Last Bell has one choice in 30 days (M5) |
| Infectonator: Survivors | 2016 | $9.99 | 1,172 (67%) | 35K-59K | Squad RTS plus roguelike | Closest shape: a hard 15-day cap rated Mixed (random off-screen deaths, cage-like limit) |
| Survivalist: Invisible Strain | 2025 1.0 | $11.99 | 4,596 (87%) | 138K-230K | NPC personalities and memories | Structured arc; 5 years in EA for under $1M solo |
| Death Road to Canada | 2016 | $14.99 | 10,554 (93%) | 317K-528K | Humour, randomised replay, co-op | Fewer random events; no co-op |
| ZERO Sievert | 2024 1.0 | $19.99 | 15.6K (85%) | official over 500K | Gunplay, progression, difficulty options, hardcore mode | You have a base and an arc; their raid is deeper and their 0-2 h approval was 25 percent against 81 percent later |
| Thronefall | 2024 | $12.99 | 23.6K (95%) | about 714K | Minimal clarity, tight scope, 2-person team | Bigger scope; Thronefall is the "tight loop beats scope" caution |
| Zombie Builder Defense 2 | 2023 | $9.99 | 210 (84%) | about 7K | none | The floor for a generic top-down zombie base with no marketing |
| Zomboard | EA 2025 | $7.99 | 3 | under 200 | none | The floor: solo, no marketing, 3 reviews in 19 months |

### 7.2 The three true comps

1. **Infection Free Zone.** Same loop: rebuild a base, squads loot, nightly hordes at the wall. It proves the loop sells (about 560K to 940K estimated units at $24.99), and its recurring complaints are Last Bell's risks: overwhelming nights, fragile walls with tedious repair, slow resources, squad micromanagement and poor AI, bugs and save corruption (weight 0.79), tedious squad management (0.72), thin content (0.70).
2. **Into the Dead: Our Darkest Days.** Shelter, scavenging runs, rescue, needs, permadeath. The best recent proof that the loop sells when polished: about 300K to 500K estimated units in about 18 months of EA. It needed a studio, a publisher and a demo with 300K downloads. Its 1.0 is announced for March 2027, a launch-window conflict.
3. **Rebuild 3.** The scale comp: 2D, small team, claim zones, rescue, morale. About 62K to 103K estimated units over 11 years at $14.99. This is the realistic Steam outcome for a self-published 2D management game with some polish. Deadly Days is a close fourth.

Structure comp for day and night tension: This War of Mine. Raid-half benchmark: ZERO Sievert.

**Why these three outrank Dead Age, Sheltered and Zombie Night Terror.** The three are picked for loop and for how the market treats that loop today. Infection Free Zone and Into the Dead: ODD are real-time, base plus sorties plus nightly defence, released 2024 to 2025, so their reviews describe what a shopper expects now. Rebuild 3 is the small-team 2D scale anchor. The others are older, and they differ in the loop: Dead Age is menu-driven camp management with turn-based combat, Sheltered a side-scroller with no wall defence, Zombie Night Terror a Lemmings puzzle. They do raise the ceiling of the 2D scale band, and the report should say so: Dead Age (168K to 281K units) and Sheltered (189K to 315K) each sold about three times Rebuild 3 (62K to 103K), at $14.99, with 5,600 to 6,300 reviews over many years. The dump's median for 2D and pixel management comps at this scale is about 2,000 reviews and 60K to 100K units over 6 to 10 years (research-direct-competitors.md section 7). So a polished game's realistic ceiling in this niche is a low six-figure unit count over years; year one is a small fraction of it. Their older release date and the far smaller catalogue they launched into are inference, not sourced.

**7.1b Value check: team, price and content volume.** What a shopper weighs against $12.99. Hours to finish were not gathered for any peer (HowLongToBeat was not queried): unverified.

| Game | Team and backing (from the dumps) | Price | Reviews (score) | Hours to finish |
|---|---|---|---|---|
| Infection Free Zone | publisher-backed (research-direct-competitors.md:243) | $24.99 | 18,764 (81%) | n/g |
| Into the Dead: ODD | studio plus publisher, 300K-download demo | $24.99 | about 10,030 (89%) | n/g |
| Rebuild 3 | small team (n/g) | $14.99 | 2,051 (86%) | n/g |
| Deadly Days | small studio (size n/g) | $11.99 | 1,917 (86%) | n/g |
| Survivalist: Invisible Strain | solo, 5 years in Early Access | $11.99 | 4,596 (87%) | n/g |
| Thronefall | 2 people | $12.99 | 23.6K (95%) | n/g |
| Zomboard | solo | $7.99 | 3 | n/g |
| **Last Bell** | one owner plus AI agents, 15 days | $12.99 planned | none | about 3 to 3.5 h for one run (6 min x 30 days plus the clear phase), no replay mode today (idea 20) |

Reading it: at $12.99 and about 3.3 hours the price is about $4 an hour on a first run; whether that is cheap depends on the three hours being good and on replay, and the peers' hours are unknown, so the report cannot say Last Bell is better value than any of them.

### 7.3 Feature matrix: Last Bell vs six comps

"Yes", "No", "Partial". Competitor cells come from the research dumps, not from play; treat as indicative. Rows whose competitor cells could not be sourced (difficulty, time speed, controller, rebinding) are removed from the matrix and handled in the table-stakes table below, with the dump line for each named game.

| Feature | Last Bell (today) | Infection Free Zone | Into the Dead: ODD | Rebuild 3 | This War of Mine | They Are Billions | ZERO Sievert |
|---|---|---|---|---|---|---|---|
| Save mid-run | **No** | Yes (corruption complaints) | Yes (a "no manual save" complaint, weight 0.05) | Yes | Day-start only | **No manual save, forced ironman** | Yes |
| Night defence of walls | Yes (14 segments) | Yes | Yes (shelter) | No | Yes (night raiders) | Yes | No |
| Extraction raids | Yes | Squads loot | Yes | Zone-claim | Yes (night scavenge) | No | Yes |
| Named survivors with traits | **No** | Partial | Yes | Yes | Yes | No | No |
| Story arc with endings | Yes (9, one choice) | No | Yes (1.0 pending) | Partial | Yes | Campaign | Quests |
| Hand-made single compound | **Yes** | No (real-world maps) | Yes | No | Yes | No | No |

**Table-stakes asks, with who is named for each in the dumps.**

| Ask | Last Bell | Named in the research dumps |
|---|---|---|
| Save you control | **No** | They Are Billions (top negative, forced ironman), This War of Mine 0.06, Death Road to Canada 0.25, ITD: ODD 0.05 (research-player-expectations.md:132) |
| Difficulty options | **No** (card ignored) | Praised: State of Decay 2 0.27, ZERO Sievert 0.10, Survivalist 0.45. Condemned when absent: This War of Mine 0.31, They Are Billions "no way to turn off ironman" (:133). ITD: ODD has a difficulty-balance complaint at 0.15 (:126) |
| Time acceleration | **No** | They Are Billions players ask for it (:141). Rebuild 3 is turn-based, so it does not apply. No source for the others |
| Key rebinding | **No** | Death Road to Canada (:141); ZED ZONE non-remappable controls; Infection Free Zone "confusing keybinds" (research-market-data.md section 9) |
| Controller and Deck | **No** | ZERO Sievert top negative, Project Zomboid Deck "broken", This War of Mine text size (:141, :154) |

What this says: Last Bell is missing the five table-stakes that the dumps name as review drivers (save, difficulty, time control, rebinding, controller), and it is distinctive on paper in a hand-made compound plus extraction raids plus a deadline. Nobody has played it, so none of that is a claim that it plays better than any peer.

---

## 8. What players of this niche demand, and what sinks games like this

From the research on 2D zombie base and sortie games and neighbours. Weights are from VaporLens, an AI aggregation of reviews; counts are Steam API figures. Treat the ranking as a reading, not a survey.

### 8.1 Demand list, ranked by how often it appears

1. **A save you control**, or resume mid-run, with permadeath kept as a rule.
2. **Difficulty presets** and a few sliders (praised: ZERO Sievert 0.10, SoD2 0.27; condemned when absent: This War of Mine 0.31).
3. **A tutorial that teaches the base loop by doing.** The first two hours decide the score: ZERO Sievert under-2h reviews about 25 percent positive vs about 81 percent over 2h; They Are Billions 40 percent at 0 to 2 h vs 87 percent at 20 h or more; This War of Mine 74 vs 94.
4. **Base depth with visible consequences**, upgrades without demolition, roles and stations. SoD2's fixed-slot base is called shallow.
5. **Named survivors with traits and memory** (Survivalist 0.48, This War of Mine storytelling 0.96).
6. **Fair deaths**, every loss traceable to a choice. Random off-screen deaths are the number-two complaint even in a 93 percent game (Death Road to Canada 0.48) and the stated cause of Infectonator's 67 percent.
7. **Readable, good-feeling combat.**
8. **Competent companion and enemy AI.** Survivalist: followers walking into enemy camps 0.61; SoD2: suicidal companions.
9. **Replay variety after the arc**: endless, seeds, scenarios. This War of Mine's main complaint is repetition after one run.
10. **QoL and platform basics**: grab-all, sort, time acceleration, rebinds, controller and Deck, localisation, later mod hooks.

### 8.2 What sinks reviews, in the order seen

Bugs, crashes and corrupt saves; hours lost to one mistake with no save; nothing to do after the first hours; unfair RNG deaths; mechanics unexplained (wiki dependence); tedious management UI; dumb AI; difficulty spikes without options; Early Access fatigue; friction outside the game (accounts, anti-cheat, controller, missing languages, price above perceived content). Bugs, softlocks and lost saves were the top complaint in every negative-review sample (Quarantine Zone 12 of 25, HumanitZ 9 of 25, VEIN 7 of 25).

### 8.3 Do not ship without (grounded in this repo)

| Item | Status today |
|---|---|
| A mid-run save | Missing |
| Difficulty options | Missing (the card is ignored) |
| A guide that covers the managed phase (projects, upkeep, morale, the night) | Partly: 4 managed cards; coverage of noise and specials is nil |
| No unavoidable deaths (a night that starts the moment Ruth returns) | Flagged harsh in prison-playtest.md; unverified |
| Crew that holds the fence without walking into the dead | Unverified |
| Windows and Linux export, controller and Deck handling | Missing |
| A HUD that reads at 1280x720 and Deck size | Open failure at 1280 wide in the old game's tutorial (STATUS.md:24); the prison's HUD is unmeasured and has 9 to 15 px chip text (M21) |
| Something after day 30 | Missing (idea 20) |
| A name check | Open |
| Inventory and squad QoL (grab-all, sort, clear orders) | Unverified |
| A stability soak and a save-safe update policy | None |

### 8.4 Recommendations, streamers, and the open slot

Players recommend a run that produces a story worth retelling, a developer who keeps updating, value at the sale price, and one-more-run pull in the first evening. Streamer pick-up for 2D colony zombie games is **inference only**; siege breaches, screamer hordes and named survivors lost on raids are the clip moments, and STATUS.md:24 already records a readability failure at 1280 wide (a friend could not see a zombie behind the tutorial cards; see M21). A State of Decay thread names Project Zomboid and Rebuild 3 as the nearest 2D options, so the "2D State of Decay" slot looks open, but demand evidence is thin and Reddit was not retrievable: a hypothesis. Also: 3D zombie sims outsold 2D, co-op dominates indie charts, and Colony Sim and Base Building have the lowest Deck share by tag (0.2 and 0.26 percent against a 0.55 percent median).

---

## 9. What to expect on Steam

### 9.1 The base rate

About 21,000 games shipped on Steam in 2025 (counts vary by tracker); about 66 percent grossed under $1,000, 47 percent sold under 100 copies, about 40 percent never recouped the $100 fee; only about 3 percent (608 of 20,282) reached 1,000 reviews; the median 2025 release grossed a few hundred dollars (several sources: $249, $347). In the colony-sim tag, 13.7 percent of 255 games from 2024 to mid-2025 reached 1,000 reviews and the median was 45 reviews. A solo game with no audience defaults to the modal outcome, not the median success story.

### 9.2 The model

First-week units = launch wishlists x c, where c is 0.10 to 0.15 for a game priced above $10 (GameDiscoverCo 2024-25 median 0.10 above $10, 0.15 for large lists; the 2020 median of 0.20 is an optimistic cap). Year one is 3 to 4 times week one (GDCo: 2 to 5 times). Reviews are units divided by 35 to 45 (Boxleiter; 50 above 1,000 reviews). Net to developer is list gross x 0.50 x (1 minus the refund rate). The 0.50 covers Steam's 30 percent, regional pricing and discounts (about 25 percent combined) and VAT (about 5 percent): 0.70 x 0.75 x 0.95. The refund rate is set per scenario instead of flat: 18 percent for the as-is build (my assumption: a 3-hour run with no save leaves most players inside the two-hour refund window, ZERO Sievert's 0 to 2 h approval was 25 percent, and EA refunds run 12.4 percent), 12.4 percent for the polished builds (the EA figure). That gives 0.41 and 0.44 of list gross, close to the earlier flat 0.44 to 0.46. Unit counts are before refunds. All unit figures are estimates; I would not trust them closer than a factor of two. A first-week score under 75 percent halves c.

### 9.3 The three scenarios, with the arithmetic

List $12.99 in every case. "Prob" is my estimate within the scenario group. Everything below is linear in W, the wishlists at launch, so every figure moves in proportion to it.

**Where W comes from.** W = weeks on the page x weekly velocity + Next Fest gain + posts, creators and any existing audience. Inputs, all from the market dump (research-market-data.md): Bronze-tier coming-soon velocity is 23 to 68 wishlists a week (:63); a Next Fest demo gains a median 806 for active marketers, 322 if the game enters with under 1,000 wishlists, P70 1,839, a top-10-percent demo about 3,000 and a top-5-percent demo about 7,000 (:72-75); the forecast bands are 300 to 1,500 for no marketing, 2,000 to 5,000 for steady marketing plus a Next Fest, 7,000 to 15,000 for a strong page and a top-10-percent demo (:213-219). The audience term is the one fact the report does not have: itch followers, page views, plays and Discord size were not gathered (open question 7), so every case below assumes no audience.

| Case | Weeks x velocity | Next Fest | Posts, creators, audience (assumed residual) | W |
|---|---|---|---|---|
| A1 | 4 x 23 = 92 | none | about 30 | about 120 |
| A2 | 4 x 50 = 200 | none | about 150 | about 350 |
| A3 | 4 x 68 = 272 | none | about 1,200 (one lucky post or streamer) | about 1,500, the top of the no-marketing band |
| B1 | 12 x 23 = 276 | none | about 100 | about 400 |
| B2 | 12 x 45 = 540 | none | about 350 | about 900 |
| B3 | 12 x 68 = 816 | none | about 700 | about 1,500, the top of the no-marketing band |
| C1 | 11 weeks to the fest x 23 = 250, plus 10 after x 23 = 230 | P30, +382 | about 450 | about 1,300 |
| C2 | 11 x 45 = 500, plus 10 after x 79 = 790 | median, +806 | about 900 | about 3,000 |
| C3 | 11 x 68 = 750, plus 10 after x 150 = 1,500 | top 10 percent, about +3,000 | about 1,750 | about 7,000, the bottom of the strong band |
| C4 | 750, plus 10 after x 300 = 3,000 | top 5 percent, about +7,000 | about 4,250 | about 15,000, the top of the strong band |

An earlier draft used 2,000 and 5,000 for B2 and B3 and 6,000 and 15,000 for C2 and C3. Those sit above the dump's bands for the described effort (no marketing is capped at 1,500; steady marketing with a Next Fest is 2,000 to 5,000), so they are replaced; they live on as the "if you already have an audience" columns of the sensitivity table. The posts-and-audience column is a residual I chose, not a measurement.

**A. Ship as-is in four weeks.** Only bug fixes; no save, no desktop polish, the name still collides, no trailer, page up about 2 to 4 weeks. Refund rate 18 percent (no-save 3-hour run, 2-hour refund window).

| | Wishlists | Week 1 | Year 1 units | Gross at list | Net (x 0.41) | Reviews | Prob |
|---|---|---|---|---|---|---|---|
| A1 dead on arrival | about 120 | 120 x 0.12 = about 15 | about 50 (x3.5) | about $650 | about $270 | 1-2 | 35% |
| A2 base case | about 350 | 350 x 0.13 = about 45 | about 170 (x3.8) | about $2,200 | about $900 | about 5 | 55% |
| A3 lucky tail | about 1,500 | 1,500 x 0.13 = about 190 | about 700 (x3.7) | about $9,100 | about $3,700 | about 20 | 10% |

Expected value: 0.35 x 50 + 0.55 x 170 + 0.10 x 700 = 181 units and about $960 net. A1 does not recoup the $100 fee, which needs $1,000 adjusted gross.

**B. After a 3-month polish pass, no marketing push.** Critical and major findings fixed: save, desktop builds, aim rule, first ten minutes, re-tuned arc, time control, difficulty and seed, Ruth at risk, rename, clean quit, audio listening pass. A page for about 12 weeks, no demo, no Next Fest. Refund rate 12.4 percent (EA, with a save).

| | Wishlists | Week 1 | Year 1 units | Gross at list | Net (x 0.44) | Reviews | Prob |
|---|---|---|---|---|---|---|---|
| B1 low | about 400 | 400 x 0.12 = about 48 | about 170 (x3.5) | about $2,200 | about $970 | about 5 | 35% |
| B2 base | about 900 | 900 x 0.125 = about 110 | about 370 (x3.3) | about $4,800 | about $2,100 | about 10 | 50% |
| B3 good tail | about 1,500 | 1,500 x 0.13 = about 195 | about 680 (x3.5) | about $8,800 | about $3,900 | about 19 | 15% |

Expected value: about 350 units and about $2,000 net. Compare the earlier draft's $5,100: the polish pass is worth about $1,000 more than as-is, because without a demo or a fest W barely moves. That is the argument for scenario C, not for B.

**C. After 6 to 9 months with demo, Next Fest and creator seeding.** Everything in B plus named crew, event deck, raid variety, endless mode, key art, trailer. Steam page Dec 2026, free demo, Next Fest Feb 22 to Mar 1 2027, EA late April to May 2027. Probabilities assume the plan is executed (about 60 percent odds for a solo dev). Refund rate 12.4 percent.

| | Wishlists | Week 1 | Year 1 units | Gross at list | Net (x 0.44) | Reviews | Prob |
|---|---|---|---|---|---|---|---|
| C1 low | about 1,300 | 1,300 x 0.13 = about 170 | about 590 (x3.5) | about $7,700 | about $3,400 | about 15 | 30% |
| C2 base | about 3,000 | 3,000 x 0.13 = about 390 | about 1,400 (x3.6) | about $18,200 | about $8,000 | about 35 | 45% |
| C3 strong | about 7,000 | 7,000 x 0.13 = about 910 | about 3,600 (x4) | about $47,300 | about $20,700 | about 90 | 20% |
| C4 top 5 percent | about 15,000 | 15,000 x 0.15 = about 2,250 | about 9,000 (x4) | about $116,900 | about $51,200 | about 200 | 5% |

Expected value: about 2,000 units and about $11,300 net if executed. Weighted with a 60 percent execution rate and the B fallback: 0.6 x 11,300 + 0.4 x 2,000 = about $7,600. The earlier draft's 40,000-wishlist breakout is dropped: the dump puts 50,000 and up at a publisher or a top-1-percent fest demo (Romestead 250,000), under 1 percent for a solo unknown.

Sanity checks: C2's 1,400 units in year one is below Rebuild 3 and Deadly Days, which reached 62K to 103K and 58K to 96K units over 6 to 11 years; C4 is nowhere near Into the Dead: ODD (300K to 500K units, publisher, 300K-download demo). Survivalist and ZED ZONE needed 3 to 5 EA years for about $0.9 million. None of this is a living wage: 6 to 9 months of solo work for C2 is about $8,000 net.

**Sensitivity: net revenue against W.** Rule of thumb at c = 0.125 and a year-one multiplier of 3.5 (0.4375 units per wishlist): a launch wishlist is worth about $5.70 gross, $2.33 net as-is (x0.41) and $2.49 net polished (x0.44). C3 and C4 used a multiplier of 4 and C4 a c of 0.15, so they land 15 to 30 percent above this line.

| Launch wishlists W | Year 1 units | Net as-is (18% refunds) | Net polished (12.4% refunds) |
|---|---|---|---|
| 120 | about 50 | $280 | $300 |
| 350 | about 150 | $820 | $870 |
| 500 | about 220 | $1,200 | $1,250 |
| 1,000 | about 440 | $2,300 | $2,500 |
| 1,500 | about 660 | $3,500 | $3,700 |
| 2,000 | about 875 | $4,700 | $5,000 |
| 3,000 | about 1,300 | $7,000 | $7,500 |
| 5,000 | about 2,200 | $11,700 | $12,400 |
| 7,000 | about 3,100 | $16,300 | $17,400 |
| 10,000 | about 4,400 | $23,300 | $24,900 |
| 15,000 | about 6,600 | $35,000 | $37,300 |

For scale: netting $30,000 in year one needs about 12,000 launch wishlists; recouping the $100 fee (about $1,000 adjusted gross, 77 units) needs about 180. A real audience moves the owner up this table, not the model: it is the only input that changes the answer by a tier.

**Key drivers.** Wishlists decide almost everything. Review score is the multiplier (over-performers launch at 91 percent against 67 percent; the known sinks are all present today). Page lead time: over-performers had about 214 days; C gets about 150, B about 85, A 15 to 30. Your real audience size could move A and B by one tier.

### 9.4 Price, Early Access or full release, timing

- **Price:** $12.99 at EA launch, $14.99 at 1.0, never above $14.99 at this polish. Every successful small-team 2D peer sits at $11.99 to $14.99 (Thronefall 12.99, Deadly Days 11.99, Death Road to Canada 14.99, Rebuild 3 14.99, Romestead 13.99); conversion falls above $10 and again above $20; the $24.99 small-team zombie builders with rough polish are Mixed (Zombie Cure Lab, Zelter). If shipped as-is anyway, $9.99 is the honest price, but it does not change the order of magnitude. Use a 10 to 15 percent launch discount, plan sales at 25 to 40 percent off after three months.
- **EA or full release:** Early Access at $12.99 with the full 30-day arc, endings and save playable, then 1.0 six to nine months later. Days 15 to 30 have never been played by a human, so patching a convoy under an EA label costs fewer reviews than under 1.0, and every close peer sold in EA. Costs: EA refunds about 12.4 percent vs 8 for 1.0, 20 to 30 percent fewer reviews per sale, and only about 20 percent of EA graduates beat their EA launch at 1.0, so the EA launch is the real launch. The research dumps disagree (one says finish a tight 1.0); my call is EA with a finished arc, switching to a straight 1.0 only if 20 or more external playthroughs finish all 30 days with no softlock.
- **Timing:** Next Fest Oct 19 to 26 2026 is not reachable. Pay the Steam fee now. Valve's own pages disagree: the wait between paying the fee and release is 30 days on the steamdirect page and 21 on the onboarding page (plan for 30), and identity, bank and tax verification is 15 to 30 days on one and 10 to 15 business days on the other. Whether these clocks run in series or overlap is unverified; the safe 30 days alone is enough to rule out a four-week ship. Public Coming Soon page by early December. Register for **Next Fest Feb 22 to Mar 1 2027** by Jan 10. **Plan A:** EA late April to May 2027, clear of the Spring Sale (Mar 18-25), the ITD ODD 1.0 weeks in March, the June Next Fest (Jun 14-21) and the Summer Sale (Jun 24 to Jul 8). **Plan B:** June Next Fest (register by Apr 25), EA late August. Avoid Oct 19 to Nov 2 2026 (two zombie launches), Dec 17 to Jan 4, and any State of Decay 3 week.

### 9.5 The name

"The Last Bell" is an unreleased Steam app (3719170, ZeroHint, publisher BellHood Games), asymmetric 4v1 horror, Windows only, with age ratings attached (USK 16, DEJUS 14, IGRS 18), so its page has passed Valve review. At least eight itch games carry the same words. Steam does not auto-block duplicate names (CURFEW and Curfew coexist), so the risk is search and wishlist collision plus an IP complaint, not a hard stop. No trademark register was queryable by the agents (JavaScript apps); **trademark clearance is unverified**. Ten alternatives returned zero Steam apps in the store-search check: Thirty Bells, Last Toll, Final Toll, Curfew Bell, Tolling Hour, Iron Bell, Cellblock Bell, Yard Bell, Bellguard, Gatebell. Thirty Bells has no itch title either, matches the arc, was your working name, and the user dir is already `ThirtyBells`. Prison Architect owns the word "prison" in search; keep it out of the title. Your earlier choice of "Last Bell" (STATUS.md:4, 2026-10-07) is reversed by this recommendation, so it is yours to make. Decide before any capsule.

### 9.6 The as-is verdict

Shipping as it is today would, most likely, sell 50 to 350 copies in year one (central about 170, about $900 net, about 5 reviews) and would miss recouping the $100 fee about one time in three. The sales number is not the main harm. The build has things that sink early reviews: no save in a 3-hour run, an aim rule that contradicts every hint, an untested convoy goal, a quit crash, unheard mono audio, a title that shows the old game, a colliding name, and an arc nobody has played. With about 5 reviews, one or two angry ones fix the score, and shipping spends the one Next Fest the game gets. The four-week date is itself unrealistic (no Steamworks account in the repo, a 30-day wait plus 10 to 30 days of checks of unknown overlap, no desktop export). The game underneath deserves a proper launch, where it plausibly lands near $8,000 net in the base case (about $11,000 probability-weighted, if executed; 9.3). Not verified: your audience size, every unit figure, how the arc plays.

### 9.7 What Steam will ask: content rating and AI disclosure

**Content survey and ratings.** The survey asks for honest disclosure of all content in the build, reachable or not, and Valve's page does not print the violence and gore question wording (research-name-and-legal.md 2.4; wording unverified). Germany: since 2024-11-15 a game without a rating is hidden from German customers; Valve's questionnaire can generate it, and a USK rating from IARC must not be entered. Valve also produces Brazil (DEJUS) and Indonesia (IGRS) ratings; the colliding Last Bell page shows USK 16 (Drastische Gewalt), DEJUS 14 and IGRS 18. Expect a "frequent violence" disclosure for shotgun kills; top-down sprites probably land a lower gore tier (my estimate, no run evidence). Content in the build: zombies, blood, shooting, "a bite infects", a hunter that shoves. The bigger rating question is children: kids live in the base (prison-playtest.md stage 6; prison_siege.gd:613 "allies and kids have no route"), and whether a kid can die in a siege is unverified (0 hits for kid and die or lost in prison_crew.gd and prison_siege.gd; release-readiness.md 1.11, :182). Confirm in code that a child cannot die, or disclose it; do this before filling the survey. There is no gore toggle in Settings. The red-cross cabinet (town_art.json:11354) is a protected emblem in some jurisdictions; whether the prison raid town draws it is unverified.

**AI disclosure and the Meshy pictures.** The survey's Generative AI section covers AI-made content that ships and that players consume (art, sound, narrative, localisation), pre-generated or live-generated; the research dump reads it as excluding AI tools used only for development (research-name-and-legal.md 2.5, matching the notebookcheck report that background tools are not reported). The release-readiness agent read it more broadly, since the whole repo is agent-written (458 commits in 15 days), and advises saying so plainly; the two readings differ and the cheap answer is to disclose development use in the page text too (unverified which Valve intends). Cost of a disclosure: AI-flagged games reach 100 reviews at about 55 percent of the non-AI rate and about 8 percent of buyers refuse outright; art is the worst case. Meshy provenance: `docs/assets-log.md` is a ledger with file, prompt, model (nano-banana-pro via Meshy text-to-image), date, task id and credits for the UI theme materials, the four site cards and the deck, tower, ladder and mast references: 63 credits in round 3, 9 in round 6 and earlier rows at 9 each, 22 pictures in all. The plan and licence at generation time are not recorded: "a paid plan is likely, but that is inference", and no invoice is in the repo. That conflicts in spirit with the owner's no-paid-services rule (2026-10-10), although the pictures predate it. The prison's own art is PIL sprites and Blender renders, not AI. Exclusion path: a scratch run without `ui/theme`, `ui/sites` and `deck_*` showed identical prison screens and no prison script references `sites/`, so excluding them from the export filter is S (M19); the inventory and loot windows were not checked, so "no AI art ships" holds only after a resource trace. Then update the credits line ("Some of the pictures were made with AI tools", `scripts/ui/credits.gd`) to match the build.

---

## 10. What we should do: the phased plan

Order matters: bugs before balance, balance before demo, demo before page push. Effort is days of work unless noted; Owner means it cannot be done by an agent.

### Phase 1: the next 2 weeks (to about Oct 28)

Goal: a build you would let a stranger play without a refund.

1. **First-minute fix** (idea 2, text half): prison default aim "always" and a pause toggle; one ammo unit; non-empty pack on entering the base; stagger the cards; hide Continue. 1 to 2 days.
2. **The bug batch** (idea 3): `has(float(n))` and a horde rebalance (scale by guards, first horde night 5 or 6, cap early hordes); the after-dawn night resolution; the held-ending guard; the Banked line. Test the horde, its guard scaling and the night-skip model together in one lab pass (pass criteria under C4). 1.5 to 2.5 days.
3. **Quit crash**: `_exit_tree` clearing the five static callables; re-run `--headless --quit -- --prison --managed` for exit 0. 0.5 day.
4. **Headless smoke test** of `--prison --managed` (M18): boot and 60 to 240 frames with no logged error, arc-lab seed 1 reaches a named ending, quit exit code 0 (after item 3), a test that the horde nights match integer nights, the six prison JSON files load. 1 day.
5. **Re-tune the convoy list** (idea 4): lab on real loot and the real starting stores; convoy1 into a stage; list shown from day 3 with a parts total; fuel requirement 32 or cap 60; day-30 gate warning; "held without the list" bitter. 1 to 2 days.
6. **Play it.** You, two full runs of days 1 to 30 with notes, and `--audiotour` (4 minutes). Without this nothing else is measured. Owner, about 7 hours.
7. **Steam fee and identity now** (a 30-day clock; Valve's pages say 21 or 30). Owner.
8. **Name decision and trademark search** in Class 9 and 41 (USPTO, EUIPO, UKIPO, WIPO), save the PDFs. Owner, 1 to 2 hours; the rename itself is 2 to 3 dev days later.
9. **Fix the 1x capture path** in `_fit_window` (read `--winpx` and `--os-scale`, about 15 lines) and take one screenshot on a real 1x display to settle the shimmer question. 0.5 day.

### Phase 2: the next 2 months (to about mid-December)

Goal: a build that deserves a public page and a first outside playtest wave.

1. **Dawn autosave, Continue, Save and quit** (idea 1). 3 to 5 days.
2. **Desktop presets, Windows test, export exclusions, settings parity** (idea 6): presets, fullscreen and brightness in the prison pause menu, exclude `zombies16`, `ui/sites`, `ui/theme`, `objects/deck_*` after a resource trace, ship `OFL.txt`, new icon and splash. 2 to 3 days core; 7 to 9 with UI scale and rebinding (split rebinding out). Decide the desktop renderer here: recommend Compatibility (C6), with one Windows Intel-iGPU run of the arc lab with `--perf` and one human session as the gate.
3. **Steamworks integration** (needs the Steamworks account from Phase 1 item 7 and the save from item 1): GodotSteam 4.23 (released 2026-10-05; the 4.22 release of 2026-08-22 already matched Godot 4.7.2) in the desktop export only, behind a guard so the web build never loads it, since a GDExtension cannot ride the web build (research-name-and-legal.md 3.1); a `steam_appid.txt` for development; Steam Cloud by Auto-Cloud, which needs no code, only a root path and file pattern in Steamworks for the new save in `user://` (project.godot:14-15 sets the folder to ThirtyBells); an overlay test in an exported build launched from Steam (the editor overlay does not work) on the chosen renderer; a depot build script with steamcmd and a private branch, plus a Proton launch check on Linux or Deck; optional 5 to 10 achievements (0 hits for `achievement` in `scripts/`; `prison_arc.json` already records kills, days, nights held and projects, so the data exists and the hooks do not). Days, an unverified estimate: init and overlay 1, Cloud 0.5, depot script 1 to 1.5, achievements 1 to 2 if wanted: 3.5 to 5. Watch: do not mix the GDExtension with a module build; Proton with Steamworks SDK 1.63 has a known Windows error (workaround Proton 10.0-4 or Experimental, or ship the native Linux build); the Steam Playtest in idea 7 needs this item first.
4. **Time control and the dusk clock** (idea 9), including the raid clock sync. 4 to 6 days.
5. **Difficulty presets and a run seed** (idea 10); strip or rewrite the New game card text. 2 to 3 days.
6. **Rename to the new name** and clear the legal surface (idea 5), plus version string and studio name. 2 to 3 days.
7. **First outside playtest wave** (idea 7): three to five people to day 10, one full run; add a playlog (day, phase, deaths, quit day, copy-to-clipboard report) so the data survives. 2 to 4 dev days.
8. **Ruth can fall** (idea 12), behind a flag, once a human has played nights 3 to 6. 5 to 8 days.
9. **Store kit** (idea 8): capsule set, five or more 1920x1080 stills, one 15-second clip; page public by early December. 4 to 6 days plus an artist if you want illustrated key art (a cost, not an AI service).
10. **Move kit** (idea 16) and **audio pass** (idea 17) in the gaps.

### Phase 3: to launch (Jan to May 2027)

1. **Demo** (idea 11) for Next Fest Feb 22 to Mar 1: clear phase plus days 1 to 7; register by Jan 10. 5 to 7 days without a demo-specific save.
2. **Named crew** (idea 13), **event deck** (idea 14), **raid variety phase 1** (idea 15), **dusk briefing** (idea 19), **endless mode** (idea 20), **shareable moments** (idea 18).
3. **Second playtest wave**, soak test on desktop and web, Steam content survey, AI disclosure answers.
4. **EA launch** late April to May 2027 at $12.99 (Plan A); Plan B is the June Next Fest.

### Effort, calendar and who builds

Assumed builder (my assumption, not stated by the owner): the owner directs and Claude agents build, as in the first 15 days (458 commits), while the owner's own time goes to playing, legal, art approvals and the Steamworks account. Owner hours per week is open question 10. All day counts are the reviser's sums of per-item estimates from a feasibility pass whose per-idea output is not saved in the audit dump (the one feasibility file, `ideas-feasibility-first.md`, carries S, M and L labels without day counts), so treat every day count as an unverified estimate.

| Phase | Dev days | Owner time |
|---|---|---|
| 1 (to Oct 28) | 5.5 to 8.5 | about 7 h of play, 1 to 2 h trademark search, fee and identity |
| 2 (to mid-Dec) | 24 to 44 for the eight originally listed items, plus Steamworks 3.5 to 5, plus move kit 2 to 4 and audio 5 to 7 in the gaps: 34 to 60 | playtest wave, store kit approvals |
| 3 (Jan to May) | 35 to 52 (demo 5 to 7, named crew 7 to 10, event deck 6 to 9, raid variety phase 1 4 to 6, dusk briefing 6 to 9, endless 3 to 5, shareable moments 4 to 6) | second playtest wave |
| Total | about 75 to 120 | |

Calendar check. October 14 to a late-April EA is about 28 weeks, or 140 working days at five a week. The full list needs 2.7 to 4.3 build days a week for that whole span if the estimates hold; at two build days a week it does not fit. Phase 1 plus 2 needs 40 to 69 dev days between Oct 14 and mid-December (nine weeks, 45 working days at five a week): the low end fits only at full-time pace and the high end does not fit at all. So "page public by early December" and "demo ready for the Jan 10 registration" are at risk, and Plan B (June Next Fest, EA late August) is the realistic fallback. The late-April date holds only for the minimal set: Phase 1, Phase 2 and the demo, which is 45 to 76 dev days (1.6 to 2.7 days a week over 28 weeks); named crew, event deck, raid variety, dusk briefing, endless mode and shareable moments move to the 1.0 roadmap. Estimates for a first game with no outside playtest data usually run over; the playtest wave in Phase 2 will add rework that is not in these sums.




---

## 11. The 20 ideas, ranked

The numbers 1 to 20 are IDs, kept so that references elsewhere in this report stay valid; they run in rough order of blocker status and impact, not in strict score order. The strict order is the score table below: score = impact (1 to 5) x confidence (1 to 5) / dev days (mid-point). Impact is the effect on a Steam outcome; confidence is how sure the reviser is that the effort and the effect are right; all three inputs are the reviser's judgement, shown so the ranking can be argued with. Effort days come from a feasibility pass whose per-idea output is not saved in the dump, so they are unverified estimates. Each entry gives the pitch, why, market evidence, and what the code check found (files, reuse, blockers).

| Rank by score | Idea (ID) | Impact | Confidence | Dev days (mid) | Score | Needs a human artist or composer? |
|---|---|---|---|---|---|---|
| 1 | 3 Bug batch | 4 | 5 | 2 | 10.0 | no |
| 1 | 4 Re-tune the arc | 5 | 3 | 1.5 | 10.0 | no |
| 3 | 7 First playtest wave | 5 | 4 | 3 | 6.7 | no (owner finds testers) |
| 4 | 5 Rename, legal surface | 4 | 4 | 2.5 | 6.4 | a logo may |
| 5 | 2 Fix the first minute | 5 | 5 | 4 | 6.2 | no |
| 6 | 1 Autosave and Continue | 5 | 4 | 4 | 5.0 | no |
| 7 | 10 Difficulty and seed | 3 | 4 | 2.5 | 4.8 | no |
| 8 | Steamworks plumbing (not one of the 20) | 4 | 4 | 4.25 | 3.8 | no |
| 9 | 6 Desktop build, clean quit | 5 | 4 | 5.5 | 3.6 | no |
| 10 | 16 Move kit | 3 | 3 | 3 | 3.0 | no |
| 11 | 11 Next Fest demo | 5 | 3 | 6 | 2.5 | no |
| 12 | 8 Capsule set and 1x kit | 4 | 3 | 5 | 2.4 | illustrated key art and logo may |
| 12 | 9 Time control and dusk clock | 4 | 3 | 5 | 2.4 | no |
| 14 | 20 Endless mode | 3 | 3 | 4 | 2.2 | no |
| 15 | 14 Event deck | 4 | 3 | 7.5 | 1.6 | no (text only) |
| 16 | 17 Audio pass | 3 | 3 | 6 | 1.5 | real music needs a composer; the current score is a generated placeholder |
| 17 | 13 Named crew | 4 | 3 | 8.5 | 1.4 | portraits via the PIL tool; AI disclosure if model-made |
| 18 | 12 Ruth can fall | 4 | 2 | 6.5 | 1.2 | no |
| 18 | 18 Shareable moments | 3 | 2 | 5 | 1.2 | no |
| 20 | 19 Dusk briefing | 3 | 2 | 7.5 | 0.8 | no |
| 21 | 15 Raid variety | 4 | 2 | 17 | 0.5 | new tile art by PIL; no |

Reading the table: idea 20 (endless mode, 3 to 5 days) ranks 14th, above every longer item (12, 13, 14, 15, 17, 18 and 19), as the stated rule demands. Idea 5 (rename) ranks fourth by score but is scheduled in Phase 2 because it is cheap only once a human has played and the name is decided; nothing blocks doing it earlier. Ideas 8, 5, 13 and 17 can run into the no-paid-services rule if they want a human artist or composer (a cost, not an AI service); that rule's reach is open question 6. Section 10 follows dependencies, not this order.

**1. Dawn autosave and a real Continue.** Impact high, effort M (3 to 5 days). *Pitch:* one versioned JSON slot saved at dawn, on raid return and on demand in the calm base; title Continue; "Save and quit". No hordes, specials or raid state. *Why:* C1; unlocks the demo and quit-to-title. *Market:* The Left Behind sits at 17 percent with no save among several faults (performance, clunky combat, confusing menus), so it is a warning rather than a single-cause comp; the lack of a manual save is They Are Billions' top complaint. *Code:* new `prison_save.gd` plus accessors in econ, arc, siege, people, arms, pack, game; button at prison_pause.gd:121; a prison-load branch at main.gd:376-383. Reuses `_enter_base()` (prison_game.gd:581), which already rebuilds the crew, siege and visuals from kept state on every raid return, plus `SaveGame.to_text` and its atomic write. Corrections: there is no per-person skill or bed (save `crew_role`, `native_roles`, `allies_alive`, `econ_gone`, recruits by pool name); there is no "morning card closes" event (trigger on `tod >= 6.4`, not attacking; `tick_day` fires at 6.0); main routes any `run_meta.load` to the old game, so use a separate key. Unverified: `user://` persistence on reload in the itch iframe. The clear phase is not covered.

**2. Fix the first minute.** Impact high, effort S for text and flags, M for the title (2 to 4 days). *Pitch:* prison default LMB fires (RMB-hold stays) plus a pause toggle; one ammo unit; queued cards; pack top-up; hide Continue; a prison title. *Why:* C2, M10, M11. *Market:* IFZ "confusing keybinds"; Zelter 47 percent on bad controls. *Code:* do not change the global default (tests/test_r22c_controls.gd:180-189 assert "right", and the One House shares it); add a prison-only default. "Always" aim ignores `over_hud`, so a feel pass is needed. Reuse `pack.kit` (prison_pack.gd:189), `sim.shot_cost`, `loadout.is_open`. Title: a baked prison-gate still on a CanvasLayer (about 1 day); a live prison title is 2 to 3 days.

**3. The bug batch.** Impact high, effort S (1.5 to 2.5 days). *Pitch:* `has(float(n))`, resolve a night missed during a raid, guard the held ending, fix Banked. *Why:* C4, M1, M8. *Market:* bugs are complaint number one. *Code:* "one day" holds only without the horde rebalance (a 34-dead horde on night 3 against a wave of 3 actually sent, then 58, 82 and 100 on nights 6, 9 and 12, while the night table runs 5 to 95 before guard scaling). The arc lab does not model hordes. "Start the night at the gate" does not work as written; fix 3 depends on fix 2. Held-check lines are prison_arc.gd:703-715. Also found: on day 30 a raid spanning 11:00 to 15:00 loses the convoy with no card.

**4. Re-tune the arc on real yield and show the list early.** Impact high, effort S (1 to 2 days). *Pitch:* lab calls the real loot model and opens on `CLEAR_STORES` (not the `--managed` defaults); cut the list; convoy1 into a stage; list from day 3; gate warning. *Why:* C3. *Market:* They Are Billions and Infectonator punish unwinnable runs. *Code:* cutting stock needs alone cannot reach 60 to 70 parts (the three projects are 106), so costs must change; power1 also sits in Fortress. Append requirement lines in `objectives()` (prison_arc.gd:249-275). The measured-yield lab ends 0 of 8 alive, so it only bounds; three human runs decide.

**5. Rename and clear the legal surface.** Impact high, effort S (2 to 3 dev days plus owner searches). *Pitch:* Thirty Bells; four trademark registers; version string, studio name, icon, splash; exclude or redraw the Meshy pictures (provenance and exclusion path: 9.7). *Why:* name collision and AI disclosure (AI-flagged games reach 100 reviews at about 55 percent of the non-AI rate; about 8 percent of buyers refuse). *Code:* about 10 string sites (title_menu.gd:133, credits.gd:13, 29, main.gd:1, 398, 811, shell.gd:462), two tests, project.godot. A scratch run without `ui/theme`, `ui/sites`, `deck_*` showed identical prison screens; no prison script calls `Hud.frame`. Unverified: trademark clearance, other PNGs' origin; a good logo may need a human artist.

**6. Desktop build, clean quit, settings parity.** Impact high, effort M (core 2 to 3 days, full 7 to 9). *Pitch:* three presets, quit fix, fullscreen, brightness, UI scale, reduce-flashes, rebinding, art exclusions. *Why:* C5, C6, M12, M13. *Market:* Godot peers ship Windows and Linux day one. *Code:* quit fix verified (five callables). Renderer: recommend Compatibility for desktop (C6); gate it with one Windows Intel-iGPU run. A Linux export took 7 s to 156 MB; Windows and macOS not run; macOS needs signing and notarisation. Brightness needs new code (scale `night_rect`); UI scale at 150 percent risks overflow; rebinding is 3 to 4 days across about 104 key sites; the "20 MB" exclusion needs a resource trace first.

**7. First human playtest wave and a Discord.** Impact high, effort S (2 to 4 dev days). *Pitch:* three to five outsiders to day 10, one full run. *Why:* nothing in this report is measured. *Market:* Quarantine Zone and Road to Vostok built wishlists on demos and clips. *Code:* via itch key; Steam Playtest needs a Steamworks app and GodotSteam first (Phase 2, item 3). Web load matters here: the itch build needs an 83 MB pck plus up to 39 MB of wasm before the title (about 40 to 60 s at 20 Mbps, arithmetic) and the pck grew from 44 MB to 83 MB in two days, so tell testers to expect a wait, or hand out desktop builds by itch key once the presets exist, or some will drop off at the loading bar. Add a playlog (day, phase, deaths, quit day, clipboard report) because the 3-hour run has no save and no logging. Keep it closed until ideas 2 to 4 are done.

**8. Hook line, capsule set, 1x screenshot kit.** Impact high, effort M (4 to 6 days). *Pitch:* "Raid the town by day. Hold the prison fence by night. Thirty days until the convoy." Capsules, five 1920x1080 stills, one silent 15 s clip. *Why:* store presence is F; over-performers had about 214 days of page lead. *Market:* Zombies plus Base Building plus Top-Down is about 103 games. *Code:* the prison cannot capture at 1x (main.gd returns before `_start_window`; a run gave 2560x1466); about 15 lines in `_fit_window`. Steam's set is larger than the pitch (920x430, 462x174, 1232x706, 748x896, 600x900, hero 3840x1240, a logo, a 1080p trailer at 5,000 kbps or more). PIL via `/usr/bin/python3`; ffmpeg is not installed. Key art may need a human artist.

**9. Time control and a visible dusk clock.** Impact high, effort M (4 to 6 days). *Pitch:* pause with live UI and 1x, 2x, 3x at base; dusk ring, chime and tint in raids. *Why:* M2, M3. *Market:* They Are Billions "no time acceleration". *Code:* `StepClock.advance(dt, speed)` already takes a speed (step_clock.gd:23-30); the prison passes 1.0. Sync the raid clock with two lines in `_enter_raid`. Blockers: dt clamps to 0.1 so 3x needs sub-stepping; countdown labels divide by speed; a live-UI pause is a new state apart from Esc; dusk is 19:00 in seasons.json but 18 to 20 in the prison grade; perf at 3x with 100 dead unverified.

**10. Difficulty presets and a real seed.** Impact medium, effort S (2 to 3 days). *Pitch:* wire the New game card; presets scale night table, loot, upkeep, starting ammo; the seed drives raid towns and loot. *Market:* This War of Mine 0.31; ZERO Sievert praised. *Code:* the meta is passed and not removed until main.gd:497-498, so `prison_game` can read it. About 94 unseeded gameplay random calls remain, so promise map and loot only. The card's facts text must be rewritten. "Standard" is what idea 4 re-tunes.

**11. Next Fest demo.** Impact high, effort M (5 to 7 days without a save). *Pitch:* clear phase plus days 1 to 7, a wishlist card, a stripped build. *Why:* about 19 percent of demo players wishlist. *Market:* Vostok 1.1M demo downloads; Next Fest median +18 followers, top 10 percent about +3,000. *Code:* demo plumbing exists (preset with `custom_features=demo`, `Demo.on()`, `demo_end_card.gd`) but is hooked only to the old game. A save-enabled demo is 12 to 18 days; skip it. The pitch's "convoy at the dam in 23 days" matches no data (day 3 has no date; the dam is day 12; the convoy is day 30), so write the day-7 card. Stripping assets needs a reference scan and a full playthrough. Depends on 1, 2, 5, 6.

**12. Ruth can fall at the fence.** Impact high, effort M (5 to 8 days). *Pitch:* no invulnerability from night 3; a downed Ruth is carried to the infirmary at a cost; wounds carry into the next raid. *Why:* M4. *Market:* SoD2, Zomboid, ZERO Sievert put the player at risk. *Code:* Ruth is not in `crew.members`, and `_bites` works by zombie distance inside the fence, so the feature is a breach consequence. Reuse crew's down state, medical bleeding, hanim downed poses, the infirmary station (prison_base.gd:266-275). New: a limp multiplier in `avatar.gd` (shared with old games), wound storage across `_enter_raid`. Ship behind a flag after a human has played nights 3 to 6.

**13. Named crew.** Impact high, effort M-to-L (7 to 10 days). *Pitch:* a trait, an arrival line and an obituary for each of 24 survivors; a memorial wall. *Why:* people are role strings. *Market:* ITD ODD distinct survivors; Survivalist 0.48. *Code:* reuses `sim/traits.gd` and `traits.json`, the morning card's "Crew lost", `show_card`, `make_portraits.py`. Econ counts role holders, so only a few traits move a number; "coward flees" has no hook; the pool overlaps the starting roster (about 12 recruit-only names); `show_card` has no image slot; the arrival card pauses the tree. Steam AI disclosure applies if text or portraits are model-generated (unverified).

**14. Event deck between the radio beats.** Impact high, effort M (6 to 9 days). *Pitch:* 24 to 40 two-choice cards in the dam-card format. *Why:* M5. *Market:* Rebuild 3, Dead Age, Death Road sell on events; Dead Age's "same events every run" sets the pool size. *Code:* the dam beat already is the format (prison_story.json:63-71). `_apply` handles only stores and morale (prison_arc.gd:554); other effects need routing through econ; each card needs a safe default for the labs; needs a run seed.

**15. Raid variety.** Impact high, effort L (14 to 20 days; phase 1 is 4 to 6). *Pitch:* fuel depot and parts yard place types, daily gate modifiers, then four town kinds. *Why:* M15; fuel cannot be raided in useful amounts. *Market:* ZERO Sievert and Tarkov sell on map identity; IFZ punished for repeated POIs. *Code:* place types are data (prison_raids.json); industrial and hospital recipes exist; car alarms are the alarm template. Every roll change shifts the economy, so re-run all three labs. `TownGen` has no theme option; at 64x64 a harbor is hard to read. Do not archive `scripts/raid`. The raid is not always daylight; it follows the global clock.

**16. Move kit.** Impact medium, effort M (2 to 4 days). The one-line `set_melee` wiring is split out as polish item 3 (S); this idea keeps sprint, the hit-stop and camera reads, and per-gun stagger. *Pitch:* sprint with noise, shove, melee feel, per-gun stagger. *Why:* M16, M17. *Code:* `sprint.gd`, `melee.gd` and `pace_keys.gd` exist unplugged; sprint noise already reaches the noise hook. `set_sprint` and `set_melee` each have one caller, in main.gd. Use X, not Shift (aim fallback, Shift+E room search). Hit-stop needs prison-side reading of `camera_push()` and `frozen()`. Stagger needs a lookup at sim.gd:1368. Unverified: whether the baked Ruth shows a sprint lean.

**17. Audio listening pass and remaster.** Impact medium, effort S for listening, 5 to 7 days total. *Pitch:* stereo stems, panning, hand-made stings, a top-20 list for you to approve. *Why:* M14. *Code:* gunshots are already 44.1 kHz; groans, foley and music are the low-rate files. Nothing pans today; positional pools exist (POOL2, `soundscape.play_at`) but need a mix retune. A higher rate adds no treble because voices are band-limited by code. Stereo 44.1 adds about 31 MB of music; prefer 32 kHz stereo for stems only. Add a prison asset test.

**18. Shareable moments.** Impact medium, effort M (4 to 6 days). *Pitch:* auto-capture on a fallen segment, a screamer or Ruth below 20 percent; a morning photo; an epilogue PNG. *Market:* a silent 15 s clip is the breakout pattern. *Code:* the seed does not exist (idea 10); web download needs `JavaScriptBridge.download_buffer`, unused and unverified in the itch iframe; `get_image()` may hitch; capture before the HUD.

**19. Dusk briefing and night forecast.** Impact medium, effort M (6 to 9 days). *Pitch:* a dusk board with tonight's side, size and special; three calls; twists as weather kinds; a breacher wind-up. *Market:* They Are Billions' countdown; Kingdom Two Crowns' blood moon. *Code:* `wave_plan()` and weather kinds are most of it. Fog is only `dim 0.2`; "rain muffles noise" has no hook; four tower posts only; an ammo ration needs a per-gun allocation that does not exist; weather is fixed per day.

**20. Hold the Line: endless mode.** Impact medium, effort S (3 to 5 days). *Pitch:* at the convoy choose to leave or stay; staying runs nights by formula with rising upkeep. *Market:* Infectonator's 15-day cage. *Code:* `wave_plan()` already extrapolates (+15 percent per night, 109 on night 31). `_spawn_batches` has no cap, so a trickle spawn is a rewrite; perf above 66 awake dead is unverified at 150 or more; about 6 strings hard-code 30.

**Plus: Steamworks integration (plumbing, not counted in the 20).** GodotSteam 4.23, Steam Cloud through Auto-Cloud for the new save, an overlay test, a steamcmd depot script and optional achievements, 3.5 to 5 days (unverified); detail in Phase 2, item 3. The web build cannot carry it, so it ships in the desktop export only, behind a guard. Depends on the Steamworks account (Phase 1 item 7) and on idea 1.

**Rejected:** mod folder (pays only with an audience); several ways out (balance multiplies per exit); fall-back line and noise lures (softlock risk; learn from the playtest); more special types (the existing four are unplayed); radio missions as timed objectives (collides with the dusk clock); charter starts and a Ledger (can strand the convoy chain); leaderboards and 40 achievements (5 to 10 achievements stay optional in Phase 2, item 3); gamepad and Deck verification (RMB aim and a dense HUD do not map; genre Deck share is near zero); a 15-day campaign; carry-over crews.

---

## 12. Appendix: method, sources, open questions

### 12.1 Method

**Agents.** Nine audit agents (core loop, combat, economy, raids, UI, art and audio, code, release readiness, first impression), a runtime-evidence agent, a skeptic per audit that tried to refute each claim (re-running some), six research sets, a top-20 with a feasibility check per idea, and a forecast agent. The day counts in sections 10 and 11 come from that feasibility pass, whose per-idea output is not saved in the dump (only `ideas-feasibility-first.md`, which has S, M and L labels). The writer did not re-run any of it. Where skeptic and first agent disagree, this report uses the skeptic.

**Read.** STATUS.md, `docs/experiments/prison-*.md`, the 2026-10-01 audit (history only), `scripts/prison/*.gd` (18,253 lines in 32 files), `main.gd`, `scripts/sim`, `town`, `render`, `ui`, `audio`, the six prison JSON files, `export_presets.cfg`, `project.godot`, the 223 test files, 100 prison screenshots, `tools/`.

**Run (agents, Apple M1 under load, Godot 4.7.2).** The full headless suite (4,411 passed); `tests/run.gd --only=dead1|test_inventory:|test_prefs:`; the clear-phase bot three times; `--auto=loop --managed --raidsecs=60|160 --hour0=20.6 --seed=3`; `--arcauto=average|passive|expert`; `--econ-lab=30`; `--loot-lab=24|30`; `--perf` in 14 runs; `--siege=3`; GDScript probes (`Array.has` on JSON floats, the quit crash, the raid night clock); scratch copies for a Linux export (7 s, 156 MB), a build without the Meshy pictures, and a measured-yield arc lab. The reviser's own figures (the night table in 2.1, the scenario arithmetic in 9.3, the line counts: 312,300 `.gd` lines in all, of which 173,357 in `scripts/`, 123,230 in `tests/` and 15,571 in `tools/`) are arithmetic on repo data and research-dump numbers, not game runs. **Not run:** a quiet-machine perf run, any human session, any Windows build, the web build at speed (the browser pane throttles a page to about 1 fps, so web numbers taken there are wrong), any listening, the windowed pause-menu Quit and window close, the three failing `--drive` checks.

**Searched.** Steam store search and app APIs (`storesearch`, `appdetails`, `appreviews`), SteamSpy, Raijin (snippets), GameDiscoverCo, How To Market A Game, Steam Page Analyzer, VaporLens, Valve Steamworks documentation, itch.io search, GodotSteam release notes. Gamalytic and SteamDB were unreachable (403 or JavaScript pages); trademark registers (USPTO, EUIPO, WIPO) are JavaScript apps and could not be queried.

### 12.2 What is unverified (the honest list)

1. Everything about how the game feels to a human: clear phase length, raid pacing, night difficulty, whether the convoy is reachable, whether days 15 to 30 hold interest, ally survival with a human.
2. All audio. Nobody has listened, including the agents.
3. The 1x non-Retina look and any shimmer on the dead; Windows and Linux behaviour; Intel iGPU performance; web memory and frame rate in a siege.
4. Whether the clear-phase wedge at (57.256, 27.607) is a level trap a human can hit, or bot steering.
5. The cause of the 361 to 507 ms hitch seen in every run, and the frame it falls on (load, first alarm or mid-fight); also any quiet-machine frame time, since all perf numbers came from a loaded machine.
6. The pause-menu Quit path, the window-close path, whether the quit crash hits the web build's tab close, and what Steam's client does with an exit-134 abort (a guess).
7. Whether Continue with an old One House save boots the wrong game (read from main.gd:376).
8. Trademark status of Last Bell, Thirty Bells and any alternative.
9. All unit and revenue figures (Boxleiter and third-party estimates, ±30 to 50 percent), the audience and posts residual in every wishlist estimate (itch followers, plays, views and Discord size were not gathered), the 18 percent as-is refund rate (an assumption), the post-June-2026 "Popular Upcoming" wishlist threshold, and Steam's current AI-disclosure wording (secondary sources; the dump and the release agent read its reach differently).
10. Competitor hours to finish and team sizes beyond the few in 7.1b (not gathered); the speed controls of Sheltered and RimWorld (no source).
11. The stale `prison-playtest.md` numbers (255 s clear, 8.7 ms, 17 crew) against today's runs (about 380 s or a wedge; 12 to 14 ms with 3 crew).
12. How many of the 22 AI pictures the prison draws (a scratch run shows none; the inventory and loot windows were not checked), and the Meshy plan and licence at generation time (inference only).
13. Whether the red-cross cabinet is drawn in the prison raid town, and whether a child can die in a siege (both feed the content survey).
14. The sample size behind each loot figure: untargeted parts and fuel rest on 30 seeds; hunting parts and fuel on about 6 seeds per target (4 to 5 in the 24-seed run); whole-town totals on 12 towns.
15. Whether Valve's fee wait and its identity, bank and tax checks overlap or run in series.
16. Whether the three night changes (horde fix, horde guard scaling, skipped-night model) are stable together; no baseline exists for nights 3 to 12.

### 12.3 Sources

Repo (all paths under `/Users/jaf_lab/last-bell`): `STATUS.md`; `docs/experiments/prison-extraction.md`, `prison-management.md`, `prison-story.md`, `prison-playtest.md`, `prison-audio-report.md`; `docs/audit/2026-10-01-full-audit.md`; `docs/assets-log.md`; `export_presets.cfg`; `project.godot`; `assets/data/prison_projects.json`, `prison_story.json`, `prison_raids.json`, `prison_noise.json`, `prison_weapons.json`, `prison_balance.json`; `scripts/prison/*.gd`. Agent dumps in `/private/tmp/claude-501/-Users-jaf-lab-last-bell/7f148be3-173f-498b-a1e1-aa182182e6e9/scratchpad/audit/` (one file per audit and research topic).

Web (read by the research agents, dates 2026-10-13 to 14 unless noted):
- Steam reviews API, Infection Free Zone: https://store.steampowered.com/appreviews/1465460?json=1&language=all
- Into the Dead: Our Darkest Days: https://store.steampowered.com/app/2239710/
- Rebuild 3: https://store.steampowered.com/app/257170/Rebuild_3_Gangs_of_Deadsville/ and https://steamspy.com/app/257170
- Deadly Days: https://store.steampowered.com/app/3026450/
- Quarantine Zone: https://store.steampowered.com/app/3419520/Quarantine_Zone_The_Last_Check/ and https://vgtimes.ru/news/153344-prodazhi-quarantine-zone-the-last-check-prevysili-1-mln-kopiy-vsego-za-tri-mesyaca.html
- Project Zomboid (Raijin): https://raijin.gg/app/108600/Project_Zomboid
- This War of Mine (11 bit): https://11bitstudios.com/this-war-of-mines-8th-anniversary/
- Infectonator reviews: https://steamcommunity.com/app/269310/reviews/?browsefilter=toprated
- They Are Billions discussion: https://steamcommunity.com/app/644930/discussions/0/2962796621662662365
- State of Decay 2 discussion: https://steamcommunity.com/app/495420/discussions/0/3173324051158754877
- Zelter, Windows Central: https://www.windowscentral.com/zelter-pc-stardew-valley-zombie-apocalypse-i-didnt-know-i-wanted
- The Left Behind (17 percent): https://ingamenews.com/pc-gaming/the-left-behind-solo-dev-addresses-17-percent-steam-score/
- GameDiscoverCo: https://newsletter.gamediscover.co/p/what-steam-review-count-tells-us ; https://newsletter.gamediscover.co/p/steam-survey-do-wishlists-and-sales ; https://newsletter.gamediscover.co/p/the-state-of-steam-wishlist-conversions ; https://newsletter.gamediscover.co/p/are-steam-game-prices-dropping-and ; https://newsletter.gamediscover.co/p/the-state-of-steam-early-access-graduates ; https://newsletter.gamediscover.co/p/are-steam-players-of-particular-genres ; https://newsletter.gamediscover.co/p/when-10-goes-nice-yet-another-zombie ; https://newsletter.gamediscover.co/p/the-shape-of-the-pc-new-game-market ; https://newsletter.gamediscover.co/p/what-are-steam-decks-biggest-2026
- How To Market A Game: https://howtomarketagame.com/benchmarks/ ; https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/ ; https://howtomarketagame.com/2024/01/29/do-wishlists-matter-any-more/ ; https://howtomarketagame.com/2026/04/13/making-sense-of-the-february-2026-steam-next-fest/ ; https://howtomarketagame.com/2026/10/13/wishlist-inflation-is-real-but-they-are-still-important/
- Steam Page Analyzer: https://www.steampageanalyzer.com/blog/how-many-games-release-on-steam ; https://www.steampageanalyzer.com/niches/colony-sim ; https://www.steampageanalyzer.com/blog/median-steam-game-2026
- Releases and revenue context: https://tech.yahoo.com/gaming/articles/over-5-000-games-released-152604830.html ; https://fragwyz.substack.com/p/three-years-of-ai-on-steam ; https://www.superjumpmagazine.com/state-of-indie-2026-part-1/ ; https://mp1st.com/news/18k-games-released-steam-2025-half-have-10-reviews
- Wishlist-to-buyer: https://alineaanalytics.substack.com/p/wishlist-to-buyer-conversions-for ; https://gamedevreports.substack.com/p/gamediscoverco-steam-refunds-research ; https://gamedevreports.substack.com/p/gamediscoverco-the-state-of-steam ; https://gamedevreports.substack.com/p/gamediscoverco-most-successful-new
- Steamworks docs: https://partner.steamgames.com/steamdirect ; https://partner.steamgames.com/doc/store/releasing ; https://partner.steamgames.com/doc/store/assets/standard ; https://partner.steamgames.com/doc/store/assets/libraryassets ; https://partner.steamgames.com/doc/store/trailer ; https://partner.steamgames.com/doc/steamdeck/compat ; https://partner.steamgames.com/doc/features/cloud ; https://partner.steamgames.com/doc/gettingstarted/contentsurvey ; https://partner.steamgames.com/doc/gettingstarted/contentsurvey/germany ; https://partner.steamgames.com/doc/marketing/upcoming_events ; https://partner.steamgames.com/doc/gettingstarted/onboarding ; https://partner.steamgames.com/doc/store/application/demos
- Name checks: https://store.steampowered.com/api/storesearch/?term=last%20bell&cc=us&l=en ; https://store.steampowered.com/api/appdetails?appids=3719170&cc=us&l=en ; https://itch.io/search?q=last+bell&type=games
- AI disclosure: https://www.notebookcheck.net/Steam-updates-AI-disclosure-form-requiring-developers-to-report-visible-and-in-game-AI-but-not-background-tools.1206103.0.html ; Meshy licence: https://help.meshy.ai/en/articles/9992001
- Godot and GodotSteam: https://godotsteam.com/blog/2026/10/05/updates-everywhere/ ; https://godotsteam.com/blog/2026/10/06/gdextensions-only/ ; https://godotsteam.com/issues/windows_issues/ ; https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html ; https://godotawesome.com/godot-games-table/ ; https://godotawesome.com/games-made-with-godot-2026/
- Fonts: https://openfontlicense.org/ofl-faq/
- Player complaints: https://vaporlens.app/app/1782120/zero_sievert/stats/details ; https://store.steampowered.com/appreviews/1782120?json=1 ; https://store.steampowered.com/appreviews/3419520?json=1 ; https://store.steampowered.com/appreviews/3543130?json=1&language=all
- Recent hits and upcoming: https://gamerant.com/upcoming-zombie-games-people-are-excited-for/ ; https://gamerevenuedata.com/games/infection-free-zone/ ; https://newsletter.gamediscover.co/p/july-2026s-top-new-pc-and-console ; https://newsletter.gamediscover.co/p/september-2026s-top-new-pc-and-console
- State of Decay thread and alternatives: https://steamcommunity.com/app/329430/discussions/0/1639794651175308598 ; https://gamersdecide.com/articles/games-like-state-of-decay-2
- Streaming: https://hatchet.gg/blog/survival-games-on-live-streaming-with-dune-awakening/

### 12.4 Open questions for the owner

1. **Name:** Thirty Bells, a subtitle on Last Bell, or another? This reverses your 2026-10-07 decision. Run the class 9 and 41 searches yourself or pay for a clearance opinion?
2. **Ruth's immortality:** a design pillar or a placeholder? Idea 12 depends on it.
3. **Held without the convoy:** a good ending, or is the convoy the point?
4. **Day length:** is 6 real minutes meant, or a first guess? Would you accept a game-time charge per raid instead of a running clock?
5. **The older games:** delete, hide behind a build flag, or keep for the title? This decides the export filter and how much of main.gd stays.
6. **AI pictures:** exclude them (free for the prison) or redraw? And is a paid human composer or artist acceptable under your no-paid-services rule?
7. **Audience and accounts:** how many people follow the itch page or would join a closed test, and is there a Steamworks account, legal entity, bank and tax file? The 30-day clock (21 on one Valve page) has not started.
8. **Early Access or finish first**, and is co-op out of scope for good?
9. **Can you play two full runs of days 1 to 30 this week?** Nothing in this report is measured until someone does.
10. **How many build hours a week, and who builds?** Section 10 assumes you direct and agents build; the late-April date needs 2.7 to 4.3 build days a week for 28 weeks, or the minimal set only.
