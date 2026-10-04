# Thirty Bells: status

> **Read this first in a new session.** Written 2026-10-02 (end of a very long session); the top of it (section 1) and the known issues (5b) were rewritten on 2026-10-04, when rounds 17 to 21 were integrated, so that nothing lives only in a chat.
> The game is a 2D zombie colony-defence game in Godot 4.7.2 / GDScript. Working title **Thirty Bells** (the repo and the itch page still say *Last Bell*). Repo: `/Users/jaf_lab/last-bell` (the only git repo; extra worktrees live in `.worktrees/`, section 1c). Private GitHub: `jafforgehq/last-bell`. Restricted itch page: https://jafforge.itch.io/last-bell (project id 5076058, account `jafforge`).

## 1. Right now (the one-screen version)

| Thing | State |
| --- | --- |
| Game | Rounds 0 to 23 are built and **on `main`**: the classic colony game plus the **avatar game** (rounds 17 to 21: one survivor, a radio, Home, nights, a community, a live drive), round 22 (easier controls: a free pointer, the right button aims, a real gate) and round 23 (Q puts the weapon away, right-click orders, an easy gate, leaving the base). The classic game is still there (`--noavatar`, or the Full crew start). **Nobody has played rounds 11 to 23 by hand** (tests, scripted QA players and a web smoke test only). |
| Git | **`main` = `origin/main` = `d413a01`** (pushed 2026-10-04, 36 commits: everything above). The old feature branches and worktrees are gone (1c). |
| Tests | Last full run **4127 passed, 4 failed** on `894d189` (2026-10-04); the four were layout/text tests that the gate row and the Controls section moved, fixed in `d413a01` and re-run with 22 related files (**668 passed, 0 failed**). No second full run after that, by the owner's lean-tests rule. The no-avatar harness (12 games, informed, seed 1) is identical to the old `main` apart from the `took` field. |
| itch (live) | **Upload id 19553346** (2026-10-04): `main` at `d413a01`, the avatar game, 37.2 MB. SHA-256 matched in the page, the embed box is ticked and saved, the page is still Restricted with its password, one file, the embed loads to the title screen. Web check before the upload: loads, no console errors, 60 fps through the first nights and with about 80 dead (12 to 13 ms a frame); about 160 dead 48 to 57 fps; 240 dead 19 fps (the simulation, not the drawing). |
| Biggest open risk | **Nobody has played the avatar game with hands**: the feel of aiming and of standing at a wall, whether the Big Nights are fair, whether a trip by car is fun or a chore (a near trip is 2.5 to 4 real minutes), and **the web build has not been measured** since the performance work (5b). The nights were tuned by a bot (6c). |

### 1a. Rounds 17 to 21 (the avatar game), one line each

Design: `docs/superpowers/specs/2026-10-03-avatar-and-radio-design.md`, thread `docs/superpowers/brainstorm-avatar-and-radio.md`, roadmap `docs/superpowers/plans/2026-10-03-avatar-radio-roadmap.md` (round 17's contracts), one plan for each later round (`2026-10-03-round-18.md` to `-21.md`). A new game is played by one survivor; `--noavatar` and a Full crew (6) start play the old yard.

| Round | What it delivers | Status |
| --- | --- | --- |
| 17 | **Be one survivor**: the avatar (WASD, mouse aim, fire, R, F); the radio verbs (Come with me, Hold here, Cover me, Search that, Go back, To the walls) with trust and visible refusals; calls with a default (a wall under attack, a fever, a stranger); the alarm as the call to arms; succession when the survivor falls; played trips with the base running behind; box select and panning gone; an avatar Orientation Day | built, reviewed, tuned, suite green |
| 18 | **Home**: one non-modal radio panel (Jobs, Build, Map, News; the old pages stay behind Shift+J/N/G); E at a person (a talk card), a post, the workbench, a car; errands by radio (loot x0.6, no rare finds, a worse chance everyone comes home); every refusal shows its reason | built, reviewed, tuned, suite green |
| 19 | **Nights**: the community holds an ordinary night alone; Big Nights (a Siege on day 10, a Rush on day 20, the last night of each season) need you at one wall: plated brutes with a head weak point, a rally ring that sharpens the defenders' aim, hot breaches, calls of the night, a day-ahead notice and the forecast as tools, mending a wall by hand (E); a harness bot that plays the avatar and a night lab | built, reviewed, tuned, suite green |
| 20 | **A community with ideas**: relationships (friends, rivals, couples), titles (the medic, the engineer, the marksman, the scout), the voice, and 13 kinds of idea brought over the radio (yes, later, no; a no costs trust, three noes go quiet) | built, reviewed, tuned, suite green |
| 21 | **The live drive**: a trip you lead is a drive (or a walk) down a road, 30 to 90 real seconds a leg, with a car you steer, the squad shooting from the windows, 9 road events and a night road, Tab for the autopilot, the base running behind at the place's pace, and the clock as the bonus (fast and clean arrives early) | built, reviewed, tuned, suite green |
| 22 | **Easier controls and a real gate**: the pointer is free, the right button (or Shift) aims, the left button fires only while aiming, a click selects a person or uses what is in reach; a setting restores always-aim; the Main gate is a real passage (`sim.gate`): E opens and shuts it, the dusk keeper shuts it, an open gate at night lets the dead in | built, on `main` |
| 23 | **Orders and leaving**: Q puts the weapon away (a button by the gun readout); a tapped right click orders the picked person by radio (hold at that tile, to a post, come with me; in a place search that, go back); the gate is easy to work (3.5 tiles, a label, clickable, Y, E-shut locks it); a "Leave the base?" card past the wall opens the Map | built, on `main` |

"Tuned" means: the night numbers (19) and the community's (20) were tuned with the lab and the probe (sections 6b and 6c); rounds 17, 18 and 21 run on their planned constants and were exercised by a scripted QA player (no crash or soft lock in about 60 runs; its report's important items were fixed in `6c2f001`).

### 1b. Reading order for the avatar game

`README.md` (controls, the avatar game, nights, community, drive), then this file's 5b (open items), 6b and 6c (the numbers and what they cannot say), then the plan of the round you touch.

### 1c. Branches and worktrees

Only `main` exists (`origin/main` is the same). The feature branches of rounds 17 to 23 (`feature/avatar-radio`, `int`, `r18-home` to `r23-orders-leave`, `fix`, `fix2`, `tune`, and the old `colony-sandbox`) were all merged into `main` and deleted on 2026-10-04, and their ten worktrees (1.5 GB, nothing uncommitted) were moved to `~/.Trash/last-bell-worktrees-2026-10-04`. Every commit is still in `main`'s history. For new parallel work make a worktree again (`git worktree add .worktrees/<name> -b <branch> main`, copy `.godot` into it, add `.worktrees/` to `.git/info/exclude`); never `git stash` with several worktrees (the stash is shared).

### 1d. How to run things

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
cd /Users/jaf_lab/last-bell                          # (or a worktree: each is a full copy of the project)
$G --headless --path . --script res://tests/run.gd                          # the whole suite (10+ minutes)
$G --headless --path . --script res://tests/run.gd -- --only=test_x:        # one file (a trailing colon = exactly that file)
```

- **Balance harness** (`tools/balance.gd`; full flag list at the top of the file and in section 7). The avatar flags: `--avatar=none` (the default: nobody is the player, the games of before round 17), `--avatar=idle` (Ruth is the player and keeps her hands off in the school gym: the community alone), `--avatar=bot` (the bot of `tools/avatar_bot.gd` plays her); `--nightstats` gives each night's row and a table without an avatar; `--data=path` reads another `nights.json`. Example: `$G --headless --path . --script res://tools/balance.gd -- --games=8 --days=10 --seed=1 --fast --jobs=4 --policy=informed --crew=5 --avatar=idle`.
- **Night lab** (`tools/night_lab.gd`): the same night played with no avatar, an idle one and the bot, from states saved at 17:30 of days 3, 6, 9, 10 and 20: `... --script res://tools/night_lab.gd -- --days=3,6,9,10 --seeds=1..16 --reps=3 --modes=none,idle,bot --crew=5 --jobs=2 --states=<dir>`. Prints the table and the plan's targets (6c).
- **Community probe** (`tools/community_probe.gd`): avatar games of 10 days that answer every idea by `--policy=accept|affordable|refuse` (`--avatar=idle|gate|bot`, `--noideas`, `--nocommunity`, `--save=path` for a staged save); command in 6b.
- **Road preview** (`tools/road_preview.gd`) draws generated roads; `tools/hud_shots.gd` and `tools/work_sheet.gd` draw sheets of screens and work poses.
- **Staging flags** (a screenshot of a given moment: `--shot`, `--hour`, `--night=siege`, `--forecast=ahead`, `--plated`, `--breach`, `--radio=news`, `--talk=`, `--drive=pharmacy,3,pickup` and the rest): the table in `README.md`, "Automated checks".
- **Never run a matrix on a tree you are editing**: `rsync` a snapshot first.

### 1e. The NO-AVATAR PROMISE

Every rule that rounds 17 to 21 added is behind avatar mode (`sim.player_id != ""`) or is only a view. **The harness without an avatar (`--avatar=none`, the default) must stay identical to `main`'s game, apart from the `took` field** (how many seconds a game took). The same goes for a plain `Helpers.make` game, the classic Orientation Day and a Full crew start. Two golden tests pin it, and a failure means a hook is not neutral (never re-pin to make it go away):

- `tests/test_nights_regression.gd` (round 19, T-GOLD): the harness rows (`--policy=informed --crew=5 --hz=15 --days=6`, seeds 1, 9, 21) against `tests/golden/harness_noavatar.json`, the rules' random state at 18:00 of day 4 (seed 7: no draw added anywhere), `plan_for` and `night_budget` of 30 and 102 days (with `nights.json` renamed or absurd: the file is never read without an avatar) and the forecast's numbers and words.
- `tests/test_round20_noavatar.gd` (round 20): whole-game digests (the clock, the stores, the kills, every person, the radio's log length, `sim.rng.state`) of plain, informed, classic-Orientation and avatar-with-the-modules-off games. The golden numbers were recorded at `f23eee3` (round 17's last commit). The avatar-mode digests were re-pinned after rounds 18 to 21 and the tuning; the no-avatar ones never moved.
- **To compare two trees' harness**: run the same command on each with `--out=a.json` and `--out=b.json`, then `python3 tools/compare_harness.py a.json b.json` (it prints `identical` or the games that differ, ignores `took` and the `out` path; exit 0 identical, 1 different, 2 unreadable). Run the check against a checkout of `main` itself before any merge.

**Folders (home directory):** `/Users/jaf_lab/last-bell` is **the game** (the only Godot project, the only git repo, the one on GitHub and the one you open in Godot; its worktrees under `.worktrees/` are more checkouts of the same repo). `/Users/jaf_lab/last-bell-prototype-recovered` is only the old web prototype's JavaScript source, rebuilt on 2026-10-01 from an old chat transcript (`README.txt` inside says so); nothing in the game uses it, and it is outside git. Keep it (it is the generator of most of the art and sounds), but never work in it.

## 2. What the game is

A small crew holds a walled schoolyard against the dead for thirty nights (Autumn), or four seasons (Campaign, 102 days). You start with **five** survivors (a Small crew of three and a Full crew of six, the old yard, are the other choices on the New game screen); the rest call in over the radio. In a new game you play **one** of them (Ruth), seen from above; the others are asked, not ordered (section 1a). Fixed 30 Hz rules loop with interpolated drawing; the sim is separate from the drawing so the harness and the tests run it headless. The design is `docs/superpowers/specs/2026-09-30-colony-sandbox-design.md` (sections 7a to 7m record what each round turned out to be; the appendix is the long-term wish list). Rules of play are in `README.md`.

Keys (the avatar game, the default for a new game; the full table is in `README.md`): **W A S D** walk, the **mouse** aims, the **left button** fires, **R** reload, **F** melee, **E** use what the prompt says (talk, take a post, work the bench, mend a wall, read a car's fuel), **T / J / N / G** the radio panel on News / Jobs / Build / Map (**Shift** with J, N or G opens the old full page), **L** call to arms, **V** fields of fire, **Tab** next person, **Space / 1 / 2 / 3** pause and speed, **F5 / F9** save and load, **Esc** closes a card, the panel or the selection, then the menu. On a road: **W S A D** drive, **E** stop, **1 2 3** answer a card, **Tab** autopilot. The old yard (`--noavatar`, Full crew, saves from before round 17) keeps the right-click orders and the order keys **M**, **B**, **P**, **C**, **X**.

## 3. What was built, round by round

| Round | What | Notes / where |
| --- | --- | --- |
| 0 | Truth and foundation: ammo really gates shooting, the school can fall, victory at the dawn of day 31, fixed 30 Hz loop | after the full audit in `docs/audit/` |
| 1 | Supplies, wounds and infection, scavenging, save/load, HUD, balance harness | `tools/balance.gd` |
| 2 | The night as a puzzle: runners (night 4), brutes (night 8), nightly plan and lookout forecast, fields-of-fire view, alarm, Big Night, informed bot | spec 7d |
| 3 | Shell and look: workshop, scrapyard, title screen, menus, settings (`scripts/prefs.gd`), Orientation Day tutorial, noticeboard UI | spec 7e |
| 4 | People: skills, traits, bonds, morale, barks, radio storyteller | spec 7f |
| 5 | Jobs and stations; Duty roster (J) | `scripts/sim/jobs.gd`, spec 7g |
| 6 | Buildings on plots built by the Builders; Build screen (N); 7 buildings | `scripts/sim/build.gd`, spec 7h |
| 7 | **Small start (3 people)**, recruits over the radio, beds cap the crew | `scripts/sim/recruits.gd` |
| 8 | **Town Board**: map of the town, fog, roads in hours, nests, outposts, rescues, expeditions (loot / scout / clear / claim / garrison) | `scripts/sim/town.gd`, `scavenge.gd`, `assets/data/town.json` |
| 9 | **The lots**: the ring of streets round the school, 10 street mouths, walls as one standing order, raids on ring buildings | `scripts/sim/lots.gd`, `assets/data/lots.json` |
| 10 | **Seasons and the Campaign** (Winter, Spring, Summer, snow, tints) | `scripts/sim/seasons.gd`, `seasons.json` |
| 11 | **The cut** (your "too many slots" feedback): 7 compound plots, 6 ring plots, one switch per lot | spec 7m |
| 12 | **Living streets** (your "dead city" feedback): stragglers hunt by day; street dressing | `scripts/sim/streets.gd`, `scripts/render/dressing_node.gd` |
| 13 | **Vehicles and fuel**: cars, pickups, vans, buses; a city across the river reachable only by vehicle | `scripts/sim/vehicles.gd`, `assets/data/vehicles.json`, town 160x70 |
| 14 | **Take control**: play a trip yourself on a generated map of the place | `scripts/raid/` (see the file map) |
| audio | Music + web-audio fix + sound levels (2026-10-02, committed, on itch) | section 4 |
| 16 | **People at work** (2026-10-03): by day nobody stands on a wall but the Lookout (Builders with nothing to build sort materials in a yard, the jobless rest at the picnic tables; a day threat sends everyone to posts and ten quiet minutes send them back); a pose, a tool and small effects for every job (`scripts/render/work_anim.gd`, `tools/make_tools.py`); the first callers need no one at the radio desk; a crew-load strip ("Seats 5 of 11") and a trip warning; tents (2 beds each); a crew of five is the default start | plan `docs/superpowers/plans/2026-10-03-round-16.md`; `scripts/sim/crew_load.gd` |
| 15 | **The yard in motion**: drag-box select (removed again in round 17: one survivor, no box); trips by car are real (walk to the doors, doors open, car out through a sliding vehicle gate and off the map, back, U-turn and reverse into the bay, doors open, people out); a motor pool inside the base; car doors cut from the car pictures and car sounds; each building has its own home and the Build screen is a list of buildings | plan `docs/superpowers/plans/2026-10-02-round-15.md`; `scripts/sim/convoy.gd`, `scripts/render/vehicle_actor.gd`, `gate_node.gd`, `assets/data/motor_pool.json`, `tools/make_motor_pool.py` + `check_motor_pool.py`, `tools/make_car_doors.py`, `scripts/sim/build.gd` homes |
| 17 | **Be one survivor** (2026-10-03): the avatar, the radio and the base that keeps living | plan `docs/superpowers/plans/2026-10-03-avatar-radio-roadmap.md`; `scripts/sim/avatar.gd`, `radio.gd`, `scavenge.gd` (`begin_played`), `scripts/ui/radio_*.gd`, `news_panel.gd`, `call_card.gd`, `scripts/raid/squad_ai.gd`, `assets/data/tutorial.json` (the avatar's lesson; the old one is `tutorial_classic.json`) |
| 18 | **Home**: the radio panel, E interactions, errands by radio | plan `...-round-18.md`; `scripts/sim/interact.gd`, `radio.gd` (asking for work, errands), `scripts/ui/radio_panel.gd`, `jobs_page.gd`, `build_page.gd`, `map_page.gd`, `map_data.gd`, `talk_card.gd` |
| 19 | **Nights**: Big Nights, plated brutes, breaches that need you, the forecast, the bot | plan `...-round-19.md`; `scripts/sim/nights.gd`, `night_calls.gd`, `night_data.gd`, `waves.gd`, `tactics.gd`, `assets/data/nights.json`, `tools/avatar_bot.gd`, `night_lab.gd`; numbers in 6c |
| 20 | **A community with ideas**: relationships, titles, 13 ideas | plan `...-round-20.md`; `scripts/sim/relations.gd`, `specialists.gd`, `initiative.gd`, `assets/data/chemistry.json`, `titles.json`, `ideas.json`, `scripts/ui/community_kit.gd`, `tools/community_probe.gd`; numbers in 6b |
| 21 | **The live drive**: a road, a car, 9 road events, the colony running behind | plan `...-round-21.md`; `scripts/drive/` (`drive_scene`, `drive_hud`, `car_sim`, `autopilot`, `road_gen`, `road_events`, `car_node`), `scripts/raid/place_flow.gd`, `assets/data/road_events.json`, `road_layouts.json`, `tools/road_preview.gd` |
| 17 to 21 fixes | review fixes, the QA fix pass (alerts, Map page, 700x560 clipping, far walls, one-press mending, hints), baked pawn meshes (`scripts/render/pawn_mesh.gd`: a dead one in 3 draw calls) and a ground mesh per terrain | section 1c |
| 22 | **Easier controls and a real gate**: the pointer is free, the right button (or Shift) aims, the left button fires only while aiming, a click selects a person or uses what is in reach; a setting restores always-aim; the Main gate is a real passage (`sim.gate`): E opens and shuts it, the dusk keeper shuts it, an open gate at night lets the dead in | built, on `main` |
| 23 | **Orders and leaving**: Q puts the weapon away (a button by the gun readout); a tapped right click orders the picked person by radio (hold at that tile, to a post, come with me; in a place search that, go back); the gate is easy to work (3.5 tiles, a label, clickable, Y, E-shut locks it); a "Leave the base?" card past the wall opens the Map | built, on `main` |

Not built yet (from the roadmap, `docs/superpowers/roadmap.md`, which is only current to round 10): blueprints and research, traders and raiders as events, power and fuel for the base (the fuel in round 13 is for cars), defence variety (traps, lures), the convoy ending where only some leave, a dog.

## 4. The audio session (2026-10-02), committed and on itch

You noticed there was no music and no sound effects. Findings and what was done:

1. **The web build was silent for everyone.** Buses made at run time with `AudioServer.add_bus()` are filed in the wrong slot by Godot 4.7.2's *web* sample-bus code, which wires Master -> UI -> SFX -> Master, a loop with no way to the speakers (measured with a Web Audio probe: the destination read exactly 0). **The first fix (`add_bus(bus_count)`) did NOT work** (the engine still hands the web layer -1; the probe on the real export proved it, and I had pushed it as `05e1113`). **The fix that works is `default_bus_layout.tres`** at the project root (SFX, UI, Ambience, Music, all sent to Master; the project loads it at start-up); `Buses.ensure()` is only a fallback. Desktop was never affected. Headless tests cannot see this class of bug, so always probe a fresh web export (section 7).
2. **The baked sounds were 20 to 50 dB under the menu sounds** (shots -17 to -26 dBFS, thuds/stabs/hammer about -32, claw scrapes -43 to -53, wind -35, crickets -43; UI clicks -6). `tools/level_sounds.py` rescales 23 files (idempotent; `--check` lists any off their level).
3. **Two music bugs found by the same probe:** on the web a sample's restart reuses its start offset (a loop begun at 33 s of 64 replayed only its tail), so music starts at 0 on the web (`Music.start_offset`); and the scene reload of a new run / load / title killed the music node (a dead cut, then a fade-in from nothing), so the music now hangs on the tree root (`Music.shared`).
4. **There was no music.** `tools/make_music.py` writes four seamless mono 22050 Hz loops from arithmetic (A minor, no samples, no downloads): `music_title`, `music_day`, `music_night`, `music_danger`. `scripts/audio/music.gd` cross-fades them (4 s) by the hour, the dead at the wall (danger holds at least 14 s), a played trip (tense track) and the title. Settings has a new **Music** slider (the compact settings layout was tightened to fit 700x560).
5. Tests: `tests/test_music.gd` (15), `tests/test_sounds_data.gd` (6: every sound the code plays exists, every gun has a shot, the layout file, level guard).
6. **It is a placeholder score.** It will not sound like a composed soundtrack. Before release: a composer or licensed tracks (spec section 8).

Verification: a Web Audio probe on the REAL fixed export (headless Chrome with a fake sink) passed all five items: the engine builds the buses in order, every one of 379 sources reaches the speakers, the title (music) peaks 0.20 to 0.27 and play 0.14 to 0.65, Master 0 / HUD mute / Music 0 silence what they should, music loops start at 0, the title-to-run crossfade has no dead cut (minimum 0.164), and the bell, shots and groans arrive. **Nobody has *listened*** to the music or the new levels: the levels are numbers in `tools/level_sounds.py` (`LEVELS`), easy to nudge. Not verified: autoplay after a cold page load, the 40 s danger track.

## 5. What is verified and what is not

- **Verified by machines:** the full test suite (3987 checks: rules, UI layout at five window sizes, saves, data, the no-avatar goldens), the balance harness, the night lab and the community probe (below), screenshots of the screens, a Web Audio probe of the web build (silent before the fix), and a scripted QA player on `feature/int` (about 60 runs of bases, nights, the community and the drive: no crash, no script error, no soft lock; its important findings were fixed in `6c2f001`).
- **Never played by a human:** rounds 11 to 21 (the cut yard, the streets by day, cars and fuel, Take control, the car trip animation, the gate, the Build screen; and the whole avatar game: aiming and standing at a wall, the radio panel, E, a Big Night, ideas and friendships, a drive and its events), the Campaign's later seasons, outposts and garrisons, the new music and levels. A film of one real trip (a sedan with two people to the nearby houses, speed 1 and 3) was watched frame by frame by a tester agent in round 15 and looked right.
- **Process slips on record:** two `rm` calls on scratch files (the rule is "delete only via `~/.Trash`"); an earlier `pkill -f Godot` killed your open editor (never again).

### 5b. Known issues and open items (rounds 15 to 21, one list)

**Not played, not measured**
- **Nobody has played the avatar game by hand** (section 5). The numbers of the nights and of the community are a bot's and a probe's: a human may stand at a wall for 25% of the night and gain 17 points over an idle avatar, or for 70% and gain 75 (6c); the weak-point disc, the call timers and the avatar-mode economy are only tuned by a playtest. The lab's table (the bot holds 90% of Big Nights on day 10) and the QA player's sweep on fresh states (before the far-wall fix the bot held 1 of 4 and an idle avatar 0 of 4) disagree; more seeds and an informed colony are needed to say who is right.
- **The web build has NOT been measured** since the performance work. It was done on the desktop: a dead one is drawn from a baked mesh in 3 calls instead of about 41 (`scripts/render/pawn_mesh.gd`; 80 dead went from 4288 to 641 draw calls), the ground is one mesh for each terrain, the live drive builds its road in parts behind its card, and the trip's scripts are read in a background thread (`_warm_a_trip_script`, `ResourceLoader.load_threaded_request`; the web export has threads off). Before the fix a crowd cost about 0.55 ms a dead one on an M1 (40 dead 35 fps, 80 dead 19 fps), and the web build is expected to be slower than the desktop. Measure a Big Night and a drive in a fresh export (section 7) before showing it.
- **People at work still draw uncached:** the baked meshes cover a figure's shadow, legs, reaching arms and hands, but not the poses at work (tools, small effects) nor the weapons, so a busy base by day costs more than it should.

**Rules and numbers** (the analysis is in 6b and 6c; each of these needs a rule or a better instrument, not a number)
- **Rivalries and couples never form in the community probe** (over a hundred games): chemistry only acts on pairs that share a station, a post or a meal and the friction pairs never meet. Something has to push people apart (a clash at a shared station, a refused swap of posts that costs more, the storyteller's `argument` card feeding relations). Friendships do form; couples need a long game. A title blocks its holder from every other title (the rule).
- **The lab's day-20 states are wrecks** (no ammo, Ruth dead or hurt, one colony a single person), so the Rush's factor (1.75) is a guess from day 10 and the growth; fix the lab (healthiest person as avatar, stores refilled, walls mended before the flip), then tune day 20. **The `first_at` metric** cannot reach its 80% target by any number: the lab compares clock hours without wrapping at midnight, takes the targets before the lure moves the night and finds a claw at a target wall in only 55% of Big Nights; the forecast hour is honest to about plus or minus 2 hours (a window "21:00 to 23:00" would be the rule change). The brute ratio (1.8) is a survivors-only proxy; the mechanism's own duel gives x6.6. `readiness()` looks at two sections only (a whole-compound rule would meet its target).
- **The final night in avatar mode is about half its old size** (day 30: budget 59 x the season's 2.4 = 142 against 281 without an avatar), because the ordinary multiplier and growth reach it and its factor is `seasons.json`'s `big`: raise `big` there if the owner wants it as hard as before. The idle avatar loses the camp on nights 7 to 10 in about half the games with or without ideas.
- **Trips by foot and by car are long:** a leg is 30 to 90 real seconds whatever the road (a long road raises the base's pace instead), so **a near trip is 2.5 to 4 real minutes** (two legs and the place) and a far one 90 s each way plus the place; by foot 31 of 35 places are 90 s legs, in a pickup 24 of 35. Tab (the autopilot) is the escape for a leg you do not want to play; it is slower and never wins the clock bonus. Whether the road is fun or a chore is the playtest's call.
- **A stranger cannot be answered from a place and takes its default.** The storyteller's modal card waits while a trip is out and for the report to be dismissed, then holds the game until it is answered; but a stranger at the gate is not a radio call with options, so while the player is in a place it cannot be answered there and, if left, takes its default after two game hours. (The radio calls with options, the attack, the fever, are answered from the place.)
- **Dead standing in pockets with no path to the yard** (a map quirk south-east of wall 13).
- **The Orientation Day teaches only part of the controls:** its 13 steps cover walk, aim, reload, who is who, ask, a refusal, News and calls, the map, the alarm, dusk and the duty roster; E (posts, bench, mending, a car), Tab, a trip, a Big Night and the forecast are left to the one-line hints (`assets/data/hints.json`: use, ring, bignight, trips, build). The rally ring round Ruth is explained only by its hint.
- **The keys change meaning between a screen and the next:** Tab is the next person at the base and the autopilot on the road, 1 2 3 are the speed at the base and the options of a card on the road, L is the alarm at the base and has no key on the road (the Alarm button), G J N do nothing on the road. Consistent inside a screen, by design. (From the QA report, not re-checked: driving exactly at cruise reads "Behind: 1 min" because of the acceleration; the first seconds at a place have no grace: dead are within 8 tiles of a thick place at once, and an idle squad lost 60 hit points in 15 s.)

**Older (rounds 15 and 16; found by review and the film, not fixed)**
- The bus's U-turn is a pirouette (its tail pokes over the walkway at the gate; rare: the bus is the last vehicle); with four vehicles home the fourth shares a bay and overlaps; cars drive through the walls you can build across the north street's two ends (a walled lot does not stop a trip); the yard's cars have no headlights (only brake lights), come home only by day, and a vehicle found on a trip appears in its bay without driving in; the van's open left door can touch a neighbouring sedan. (The live drive's road does have headlights at night.)
- The work pose reads weakly from behind (hauling a crate, the rest mug, the nurse) and the hoe looks crude from the front: a real artist's frames would replace these.
- For a crew of five only Hector is guaranteed a call without the radio desk (the first three authored callers who did not start).
- The harness bot grows its crew to nine with tents first (`--beds`, off by default): a bigger crew faces bigger nights.
- `--town-send` staging needs the hour between 06:30 and 10:00 (`--hour=8`); at other hours the party is refused silently.

### First things to try by hand (the avatar game)

1. Start a game (Crew of five): walk Ruth with **W A S D**, aim with the mouse, fire, press **R** and **F**. Click Dez's card and ask him to come (the dock's verbs); ask Ana while she nurses someone and read the refusal.
2. Walk to Dez and press **E** (the talk card: what he is doing, what he needs). **E** at the gate post (a steadier aim), at the workbench (twelve seconds of ammo), at a damaged wall (it mends until whole).
3. Press **T**, **J**, **N**, **G** (the radio panel on News, Jobs, Build, Map: the game does not pause; **Shift** with J, N or G opens the old full page). Order a building; ask someone to take a job.
4. From day 3 watch for an idea on the radio (by day, never at noon): answer yes, later and no.
5. By day press **G**, pick a place and **Take control**: drive (W S A D), meet a road event (1 2 3, **E** to stop), play the place, drive home; then once with **Tab** (the autopilot) and once on foot. Send someone on an **errand** without you and read what comes back.
6. Day 9 at noon, with someone at the radio desk: the Big Night notice. Day 10, the Siege: stand among the defenders (the green ring), shoot the plated brutes in the head, mend the wall if it falls. Then once from a trip, to see the dusk line and the leave-by hour.
7. Listen: music on the title and by day; at dusk the night track; a crowd at the wall switches to danger; the Settings Music slider. Old checks still worth a look: the streets by day (do a few of the dead wander?), a lot claimed on the Build screen with "Wall the streets as the scrap allows", a trip by car from the doors to the unloading.

## 6. Balance (the harness) and what it means

Harness: `tools/balance.gd` plays whole games headless with a bot policy. Standard difficulty, 30 days. **The numbers in this section are the game without an avatar (`--avatar=none`, the games of rounds 0 to 16, which the no-avatar promise of section 1e keeps unchanged);** the avatar game's nights and community are in 6b and 6c.

- **Settlement game** (`--crew=3`, informed bot, 8 games per seed): **2/8 and 3/8 wins on seeds 1 and 9** (median day 26.5 on both) with the cars on; 2/8 and 2/8 with no cars; 3/8 and 3/8 with no streets. Before the streets (round 10) it was about 7/16. The streets made it a bit harder; one cause was found and fixed (day gunfire drew every straggler to the walls).
- The bot's first use of cars (3 to 4 people by van to far places) lost games on days 16 to 21; sending 2 and only from 3 hours of road fixed it. That was the bot's policy, not the cars.
- **Round 15 (final tree, same bot, 8 games per seed):** settlement game seeds 1 and 9: **2/8 and 2/8 wins, medians 23.5 and 25** against 2/8 and 3/8, medians 26.5 and 26.5 before round 15: a little lower, within the noise of 8 games (the car trips cost about 71 game minutes each, the building homes moved the salvage bench). Classic start, informed, seed 9: 4/8 against 5/8, median 30 both.
- **Crew size (2026-10-02, after you said three felt low):** the New game screen offers Small crew (3), **Crew of five (the default for a new player)** and Full crew (6, the old yard). Harness, informed, seeds 1 and 9 together (16 games each): crew 3: 4 wins, medians 23.5 and 25; crew 4: 3 wins, 23 and 27.5; crew 5: 4 wins, 23.5 and 25.5. The nights scale with the crew, so the size changes how much there is to do, not how hard it is. (A prefs file that remembered crew 3 keeps showing 3 until you click another card.)
- **Round 16 (informed bot, crew 5, seeds 1, 9, 21 and 40, 8 games each = 32):** mean day reached 23.4 against 23.7 before; crew sizes identical (never above 6; the bot builds no tents). **Wins: 0 of 32 against 6 of 32.** The games that reach night 30 are few (5 in each arm, 3 of them survived it before and none now). A null perturbation (one extra random draw) takes the same bot from 4 wins to 2, so this may be noise, but it is not proven: if wins matter, run more seeds before trusting round 16's balance, or look at the Big Night (the dawn and day-threat rules are the suspects; switching all three round-16 rules off reproduces the old numbers exactly).
- **Classic start** (six people): identical to before round 7 up to round 14. **Round 15's map edits (the vehicle gate, the apron, the cleared street lane and the removed wreck) changed it a little**: default policy, 8 games seed 1, median day 17 -> 20.5 (0 wins both). An ablation with the old `map.json` and `dressing.json` restores the old numbers exactly, so it is the map, not the rules. It is easier, not harder; nobody plays the classic start to win, but the tutorial and the Full crew choice use it.
- **Campaign:** on Standard the bot dies in Autumn; on Story it finishes in 3 of 8. It needs a human's judgement.
- **Known balance gaps:** outposts are usually overrun in the harness (the policy never posts a garrison); the Campaign is not tuned for people.

## 6b. Round 20 tuning (the community's numbers)

`tools/community_probe.gd` plays avatar games of the settlement start headless (the colony by the harness's `Balance.Policy`, informed, crew 5; Ruth is the player and stands still in the school gym, `--avatar=idle`, or at the gate, `--avatar=gate`, or is round 19's bot, `--avatar=bot`) and answers every idea the community brings by `--policy=accept|affordable|refuse` (affordable: yes when the price leaves 5 scrap and 10 food, else later). It prints, by day: ideas raised and answered (and by kind), scrap and food spent on them, friendships, rivalries, couples, titles, the voice, the mean mood and trust, who was lost and whether the colony survived; and the plan's targets with a verdict. `--noideas` plays the same game with the initiative module off (relations and specialists stay on), `--nocommunity` all three, `--save=path --save-day=N` writes a save (SaveGame) at the first moment an idea is open from day N on (the staged game for the film), `--out=path.json` everything. A game of 10 days costs 1 to 2 minutes of processor time.

```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --script res://tools/community_probe.gd -- --seeds=1,2,3 --days=10 --crew=5 --policy=affordable [--avatar=bot] [--noideas] [--verbose] [--out=p.json]
```

**What was changed (constants and data only; no rule):**

| Where | Constant | Was | Now | Why |
| --- | --- | --- | --- | --- |
| `relations.gd` | `FRIEND_AT` / `FRIEND_END` | 35 / 20 | 30 / 15 | pairs that had one good day (a rescue, a trip) sat at 25 to 30 and decayed back; nobody beyond the roster was friends by day 10 |
| | `STATION_GAIN`, `NEAR_GAIN`, `POST_GAIN`, `MEAL_GAIN` | 0.25, 0.15, 0.2, 0.8 | 0.5, 0.3, 0.4, 1.5 | the slow moves could not outrun the decay (a pair at one hour a day plateaued at 10) |
| | `DECAY_PER_DAY` | 1.0 | 0.8 | the same |
| | `TRIP_GAIN`, `TRIP_HURT_GAIN`, `RESCUE_GAIN`, `RESCUE_DOWNED_GAIN` | 2.5, 4, 6, 10 | 4, 6, 8, 12 | friendships in the probe come from shared trouble: the events are what moves a pair over the line |
| | `SCARCE_LOSS` | -0.5 | -1.0 | doubled with the gains, so that hunger still outweighs working side by side |
| | `VOICE_MIN` / `VOICE_SWITCH` | 40 / 8 | 52 / 12 | Walt's roster mentor bond alone stands at 37 (voice on day 3); and the voice changed two or three times in ten days |
| `chemistry.json` | friction, warmth | -0.25, -0.2, +0.2, +0.2 | -0.5, -0.4, +0.4, +0.4 | doubled with the gains, so a pair's temperament weighs as much as before |
| `titles.json` | `need`: medic / engineer / marksman / scout | 6 / 30 / 20 / 3 | 2 / 60 / 150 / 12 | the marksman was named on day 2 (20 kills in the first night) and flipped between two people in one night; the medic was never reached (Ana treats 2 to 6 people in ten days); the scout (3 trips) was named on day 3 and, holding a title, blocked the same person from the marksman's |
| `initiative.gd` | `GAP_ALL_MIN` | 240 | 360 | up to two ideas a day, 12 to 15 in ten days in a crowded camp; now one or two a day and 7 to 10 |
| | `GAP_KIND_DAYS` | 3 | 5 | the same idea (the radio desk, a lesson) came back every third day |
| | `NO_WINDOW_DAYS` | 4 | 5 | a person is asked at most every `GAP_PERSON_DAYS` = 2 days, so three refusals can never fall in four days: the quiet after three noes could not happen (it can now: "Ana has stopped bringing ideas") |
| `ideas.json` | `fix_wall.params.under` | 0.9 | 0.85 | fewer ideas to mend a wall at 85 to 90% for 3 to 7 scrap |

Tests that copied these numbers now read them from the modules or the data (`test_specialists.gd`: the needs; `test_relations.gd`: the friend lines and the daily decay; `test_initiative.gd`: the kind gap and the refusal window; `test_ideas_effects.gd`: `under`). The three avatar digests of `test_round20_noavatar.gd` did not move (the three modules are off or inactive in those games), so nothing was re-pinned.

**Result** (10 days, crew 5, `affordable`; the idle avatar is a hard case: the community alone holds the nights and the base game loses people in most games, with or without ideas):

| Target | Shipped constants (idle, 3 seeds) | Tuned, idle avatar (6 seeds) | Tuned, avatar bot (4 seeds) |
| --- | --- | --- | --- |
| Ideas in all, 5 to 12 | 10.3 (max 12) | 7.3 (max 10) | 8.8 (max 10) |
| Least gap between two ideas, 4 h or more | 4.5 h | 6.0 h | 6.0 h |
| Friendships beyond the roster at the end, 1 to 3 | 0 | 0.7 (2.7 formed in the game) | 1.0 (2.8 formed) |
| Rivalries, 0 to 2 | 0 | 0 | 0 |
| Couples, at most 1 | 0 | 0 | 0 |
| Titles at the end, 1 to 3; the medic first | 1.0; medic never, marksman day 2 | 1.0 (1.6 at dawn of day 10); medic first in 3 of 5 games with one | 1.5; medic first in 4 of 4 |
| The voice, by about day 6 | days 3, 4, 5 | 3, 4, 5, 5, 6, 7 | 4, 5, 7, 7 |
| Mean mood against `--noideas`, not under by more than 2 | | 63.0 against 64.3 (paired -1.2) | 68.2 against 67.9 (+0.3) |
| Scrap spent on ideas / scrap that came in, under 25% | 0% (keep-12 refused every scrap idea) | 8% | 18% |
| Survival (day 10) against `--noideas` | 2/3 against 3/3 | 5/6 against 6/6 (seed 6 collapsed on night 7 in both; 0 alive against 3) | 4/4 against 4/4 |

`accept` (yes to everything, 3 seeds): 8.0 ideas, mood +0.0 against `--noideas`, 8% of the scrap. `refuse` (no to everything, 3 seeds): 7.3 ideas, mood -2.0 against `--noideas`, mean trust 53 against 55 in a game that held; with the window of 5 days Ana goes quiet in two of three games. About 40 rows of variants (and what each changed) are in the log of every run, `scratchpad/int/tune20.md`.

**Not reachable by numbers (a rule or a driver is missing):**
- **Rivalries never form.** Not one in over a hundred games. The two friction pairs (nervous with tough, two sharp-eyed) seem never to meet: chemistry only acts on a pair that has a gain in the same look (working at one station, standing still side by side, neighbouring posts, a meal), and Marcus (nervous) shares no station or post with Dez or Hector in the harness; the four games played with friction at -4 per look came out identical to those at -1.4. Scarcity needs hunger, which the camp does not reach in 10 days. Something has to push people apart (a clash at a shared station, a refused swap of posts that costs more, the storyteller's `argument` card feeding relations, or friction pairs for traits that do meet).
- **Couples form only in a long game**: the roster pair Dez and Hector reaches 85 on day 9 to 11 at best; with `PARTNER_AT` 90 or slower roster growth none forms in ten days.
- **A title blocks its holder from every other** (the rule): whoever is named first (the scout on day 3 at the old numbers) can never be the marksman; at need 12 the scout is rare (the person with the most trips is usually the marksman).
- **The idle avatar loses the camp at night 7 to 10** in about half the games with or without ideas: survival comparisons need many more seeds than the 6 and 4 played here.

## 6c. Round 19 tuning (the nights' numbers, 2026-10-04)

Instrument: `tools/night_lab.gd` (crew 5, 15 Hz, states at 17:30 of days 3, 6, 9, 10 and 20 of no-avatar informed games, **16 seeds (1 to 16) x 3 reps**, the same dice for `none`, `idle` and `bot`), tried number by number with `--data=<a copy of nights.json>` on a snapshot of the tree (never on the tree being edited), 13 runs (about 3,500 nights). Only `assets/data/nights.json` moved; nothing in `nights.gd` or `night_calls.gd`.

**What changed (and why):**

| Number | Was | Now | Why |
| --- | --- | --- | --- |
| `ordinary.avatar_weight` | 0.5 | 0.0 | an idle avatar is not a gun: a night sized for 5 defenders, so that a 6th (the player) is a boon and not a need |
| `ordinary.mult` | 1.0 | 0.75 | idle nights 1 to 9 held 72% at 0.5 / 1.0 / 0.10 (weight, mult, growth), 66% at 0 / 1.0 / 0.10 (96 nights), 79% at 0 / 0.85 / 0.07 (96), 80% at 0 / 0.8 / 0.07, 86% at 0 / 0.75 / 0.07 (144 each; the failures that stay are strays, not size); an ordinary night is now 21 dead (it was 36), the no-avatar game's is 39 |
| `ordinary.growth` | 0.10 | 0.07 | the plan's suggestion; flattens the late nights (day 30's budget 91 against 117) |
| `themes.siege.factor` | 1.45 | 2.1 | with the ordinary night 40% smaller the Big Night is made by its factor: day 10 now brings 45 (it brought 54), idle holds 15% (was 52), the bot 90% (was 92) |
| `themes.rush.factor` | 1.55 | 1.75 | the Rush of day 20 is about 1.2 times the points of the Siege of day 10 (the crew is the same size) |
| `themes.siege.main_share` / `themes.rush.main_share` | 0.85 / 0.80 | 0.95 / 0.90 | a target wall among the three hardest hit in the bot's Big Nights: 49 to 62% at 0.85, 85% at 0.95 (day 10) |
| `plated.armour` | 0.2 | 0.1 | a plated brute lives 18 s (from its first claw) under the crew's fire at 0.2, 27 s at 0.1; unit duel (`test_nights_plated`): plain 4.1 s, plated 27.2 s, x6.6 |
| `plated.npc_weak` | 0.08 | 0.03 | same: a defender finds the head on one hit in 33 |
| `plated.weak_r` | 0.2 | 0.25 | the avatar's head hits had slipped to 8.8 s with the shotgun at 4 tiles (the body hits' share fell with the armour); now 6.8 s, rifle 4.4 s (bar 8 s). A larger head disc is also the plan's first fix if a human finds it unfair |

Not changed: rally (`radius` 9, `aim` 0.15, `fire` 0.85: the bot at presence 0.68 holds Big Nights, at presence 0.25 it gains 17 points over `idle`, so "not a god"), `weak_mult`, breach, mend, calls, forecast (`first_k` 3, `decent_*`: see below). `night_data.gd`'s fallbacks still hold the plan's old numbers (a missing file gives them).

**The table** (lab, 16 seeds x 3 reps; `none` is today's game for reference, a Big Night's `none` is that day's ordinary night):

| Cell | `none` | `idle` before -> now | `bot` before -> now |
| --- | --- | --- | --- |
| nights 1 to 9, held | 76% | 72% -> **86%** | 96% -> 95% (+9 points over idle) |
| nights 1 to 9, deaths a night / someone downed | 0.03 / 4% | 0.10 / 13% -> 0.05 / 8% | 0.01 -> 0.01 |
| Big Night day 10, held | 60% | 52% -> **15%** | 92% -> **90%** |
| day 10: sections fallen / deaths a night | 0.31 / 0.12 | 0.25 / 0.38 -> 0.79 / 0.96 | 0.04 / 0.06 -> 0.08 / 0.04 |
| day 10: presence / avatar downed / dead a night | | | 0.71 / 0.04 / 0.00 -> 0.69 / 0.02 / 0.00 |
| Big Night day 20, held (poor states, see below) | 42% | 0% -> 14% | 14% -> 31% (presence 0.27) |

**The six targets** (the lab's own verdicts, `days=3,6,9,10`; with day 20 added: 2, 3 and part of 6 fail for the reasons below):

1. **Not met, three of five parts**: held 86% (>= 80), someone downed 8% (<= 20) and the full harness (`--avatar=idle --policy=informed --crew=5 --days=10`, seeds 1, 9, 21, 40 x 8 games: **30 of 32 (94%) reach day 11**, >= 90%) are met; held when ready 88% (>= 90) and deaths 0.049 a night (<= 0.03) are not. (The full games' own nights 1 to 9 hold 72%, 64 to 81% by block, deaths 0.09 a night: their economy is the handicap of Risk 8, the idle avatar does no job and the stores run poorer than the lab's flipped states.)
2. **Met on day 10**: idle held 15% (<= 35), a section fell or someone died 85% (>= 70), colonies that go on 100%. With day 20: 92% (the lab's day-20 colonies are dying anyway: an ordinary no-avatar night of day 20 loses 17% of them).
3. **Met on day 10**: bot held 90% (>= 80), sections fallen 0.08 (<= 0.3), deaths 0.04 (<= 0.3), presence 0.69 (>= 0.6), avatar downed 0.02 (<= 0.25) and dead 0.00 (<= 0.05). With day 20 pooled: held 64%, fallen 0.51, presence 0.50: not met.
4. **Met**: bot over idle +9 points on nights 1 to 9 (>= 5), never below idle minus 2 on any of days 3, 6, 9.
5. **Met**: golden numbers equal (`test_nights_regression`, and the harness compared before and after for seeds 1 and 9: identical).
6. **Partly**: a target wall among the three hardest hit in Big Nights 76% (>= 70) and the bot puts a plated brute down in 4.2 s from its first claw (<= 10) are met; the lab's brute ratio reads 1.8 (>= 2.5) and `first_at` within 1.5 h 4% (>= 80%) are not.

**What the numbers cannot fix** (each needs a rule or a change of the instrument, not a number):

- **The day-20 lab states are wrecks**, not nights to tune by: of the 12 (4 colonies were lost before day 20) 5 have no ammo (0 to 34), Ruth is dead in 3 and hurt (hp 14 to 53) in 6 (the bot lies in bed: presence 0.00, no shot), one colony is a single person; and 38 of the 46 day-10 idle deaths are in states that begin with a section already open (the harness runs out of scrap and nobody mends). Tuning day 20 to "bot >= 80%" would make the real game trivial. Fix in the lab (healthiest person as avatar, stores refilled, walls mended before the flip), then tune day 20; until then the Rush's factor (1.75) is a guess from day 10 and the growth.
- **Ordinary deaths and `ready`**: all 7 deaths of idle nights 1 to 9 are in states with a section down at dusk or a crew under five (18 of the 144 nights); and `readiness()` looks at the two predicted sections only, while the nights that fail are strays at others (e.g. two walkers clawing a container for eleven hours, one gun covering half its places). Probe, 48 nights: whatever `decent_walls` (0.7 to 0.95) and `decent_guns` (2, 3), held-when-ready stays 79 to 88%; "no section down and none under 70% (the whole compound)" gives **92% held and 73% of nights ready**. A rule change (`tactics.readiness` and the lab's `_target_ids_for` over the whole compound) would meet it. Nights 8 and 9 also hold less (idle 77%, against 92% and 90% on days 3 and 6) for a rule the numbers do not reach: the first brute of every night comes on night 8 and `Kinds.counts` gives it at least one whatever the size.
- **`first_at`**: no `forecast.first_k` gets near 80%. The lab compares the clock hour of the first claw at a target wall with `first_at` without wrapping at midnight (a claw at 00:30 against 22:00 reads -21.5 h: `tools/night_lab.gd` `targets`), takes the targets before the informed policy's lure moves the night, and finds a claw at the target walls in only 55% of Big Nights (the others are shot at range: no wall damage at all). Probe on the real arrivals (the k-th dead within 10 tiles of a target, 64 nights, 45 with any): `first_k` 3 to 5 is the best, 54 to 61% within 1.5 h of the 3rd or 5th arrival (k = 1: 60% for the first); the error is unbiased with a spread of about 2 h. So the forecast hour is honest to about plus or minus 2 hours; telling a window ("21:00 to 23:00") is the rule change.
- **Brute ratio**: the lab's 1.8 is a survivors-only proxy (83% of plated brutes die before their first claw, and the plain ones it compares with are 8 brutes); the mechanism's own duel gives x6.6.
- **The final night in avatar mode is about half of what it was** (day 30: budget 59 x the season's 2.4 = 142 against 281 without an avatar), because `ordinary.mult` and `growth` reach it and its factor is `seasons.json`'s `big`. If the owner wants it as hard as before, raise `big` there (not a number of this file).

**Tuned only with the owner's playtest** (the plan said so): how a human's presence compares with the bot's (the bot is a decent shot with 0.03 rad of jitter and a 0.25 s reaction; a human may stand at the wall for 25% of the time and gain +17 points, or 70% and gain +75), the avatar-mode economy (a Big Night held in the lab is held in the game, not the reverse), and the feel of the call timers (`calls.*` untouched).

Re-run: `$G --headless --path . --script res://tools/night_lab.gd -- --days=3,6,9,10 --seeds=1..16 --reps=3 --modes=none,idle,bot --crew=5 --jobs=2 --states=<dir>` (days 3,6,9,10 give the verdicts above; add 20 for the harsh cell). Tests that copied numbers now read them (`test_nights_plated`, `test_nights_rally`, `test_nights_mend`, `test_nights_plan`: the cap test uses a copy of the data with a lower cap); the two avatar digests of `test_round20_noavatar` that play the first avatar night were re-pinned (the no-avatar ones did not move).

## 7. How to do things

Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot` (alias `G` below). **You keep the Godot editor open on the main folder: never `pkill`/`killall` Godot.** The commands run in any worktree (`cd` into it); section 1d has the short list for the avatar game.

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
cd /Users/jaf_lab/last-bell                                              # or a worktree under .worktrees/
$G --headless --path . --script res://tests/run.gd                    # the full suite (10+ minutes; about 4000 checks)
$G --headless --path . --script res://tests/run.gd -- --only=test_music:   # one file (a trailing colon = exact file)
$G --headless --path . --import                                         # after adding assets (makes the .import files)
```

Tests extend `res://tests/case.gd` (`check`, `eq`, `near`); any logged error fails the run; write the failing test first.

Balance harness (flags, all in the header of `tools/balance.gd`: `--games --days --difficulty --seed --seeds=a,b,c --fast|--hz=N --jobs --policy=default|informed|none|keep --crew=3..6 --campaign --nolots --novehicles --nostreets --nobuild --beds --build-order --nostory --verbose --sites=path --out`; since round 19 also **`--avatar=none|idle|bot`**, `--nightstats` and `--data=path`):

```bash
$G --headless --path . --script res://tools/balance.gd -- --games=8 --days=30 --difficulty=1 --seed=1 --fast --jobs=4 --policy=informed --crew=3 --out=/tmp/x.json
$G --headless --path . --script res://tools/balance.gd -- --games=8 --days=10 --seed=1 --fast --jobs=4 --policy=informed --crew=5 --avatar=bot --out=/tmp/y.json   # the avatar game: the bot plays Ruth, each night's row is in the output
python3 tools/compare_harness.py before.json after.json                                   # identical? (the no-avatar promise, section 1e)
```

The night lab and the community probe are in sections 1d, 6b and 6c.

Never run a matrix on a tree you are editing: `rsync` a snapshot first.

**Web export, zip, itch** (the page is Restricted with a password; **never** make it Public or untick the password without asking):

```bash
$G --headless --path . --export-release "Web" build/web/index.html
mv build/LastBell-web.zip build/LastBell-web-<date>-prev.zip     # keep the old zip
(cd build/web && zip -q -r ../LastBell-web.zip .)
```

Upload recipe that works (Claude in Chrome tools, your logged-in Chrome): full details in the memory file `itch-and-github.md`. In short: split the zip into 9 MB parts, one `file_upload` per part into an injected `<input type=file>`, rebuild the file inside the page and check its SHA-256 against the local zip, capture itch's own input by patching `HTMLInputElement.prototype.click`, press **Upload files**, set the file with a DataTransfer, wait, tick **This file will be played in the browser**, press **Save**. The same file name replaces the old upload in place. The edit page is https://itch.io/game/edit/5076058; the embed loads from `html-classic.itch.zone/html/<upload id>/` (current upload id 19553346). The itch page's title, text and screenshots are still the old prototype's.

**Probe web audio** (no ears needed): serve a copy of `build/web` with a hook in `index.html` that records `AudioContext`s, `AudioBufferSourceNode.start` calls and an analyser on the destination (`.claude/launch.json` has a `web-test` config on port 8123 serving the scratchpad's `webtest` folder). Headless tests use a dummy audio driver and cannot catch web audio bugs.

**Regenerate assets:** `python3 tools/make_music.py [title|day|night|danger]`, `python3 tools/level_sounds.py [--check]`, and the other `tools/make_*.py` (art; Python with Pillow and NumPy).

**Push:** only when you ask. `git push origin main` (fast-forward) is how rounds 0 to 16 went; rounds 17 and later are on feature branches that have not been pushed: merge `feature/int` into `main` (after the no-avatar check of section 1e) only when you say so, then push. The repo is private; scan the diff for keys first.

## 8. Rules for working here (from your instructions)

- Work and commit on **`main`** (rounds 17 and later: on their feature branches in worktrees until you say merge; section 1c). Never push unless asked. Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Delete only by moving to `~/.Trash`**, never `rm`. **Never kill processes by pattern.**
- Keep builds lean and fast; short honest status with real numbers; don't ask mid-build questions that have a sensible default.
- The itch page stays Restricted with its password; the repo stays private.
- Use Meshy for art only when it clearly helps (costs confirmed and logged in `docs/assets-log.md`); do not draw realistic sprites as flat shapes in code (you rejected that).
- Before any paid release: a rights audit of every asset (sounds, fonts, images, AI-made pictures, with the AI-content disclosure Steam asks for) and a trademark check of the name.

## 9. What to do next (suggested order)

0. **Twenty more ideas** for the base, management and building are in `docs/superpowers/ideas-2026-10-03-base-and-management.md` (the author's picks marked: an inner wall, a kitchen, sanitation, a timetable, things going wrong inside, tiers of the settlement). The eight earlier ones (the gate as the heart of the night, fuel for the base, traps, upgrades, road events, territory, a garage, a heat map) are in the 2026-10-02 reply and `docs/superpowers/roadmap.md`'s reserve list.

1. **Playtest the avatar game by hand** (the checklist after 5b: aim and stand at a wall, E, the radio panel, ideas, a Big Night, a drive) and write down what is wrong or boring. This matters more than anything the bot says. Also still unplayed: rounds 11 to 16 (the old checks of that list) and **listening** to the audio (section 4; it is already on itch).
2. **Land round 22** (easier controls and a real gate, `feature/r22-controls-gate`) on `feature/int`, run the suite and the no-avatar check (section 1e), then decide on the merge into `main`.
3. **Fix what the playtest finds**, then rebalance with the lab and the probe (6b and 6c: the Big Nights and the community were tuned by a bot), and settle the open items of 5b (measure the web build first).
4. **Update the itch page**: title, text, screenshots (still the old prototype's), once the build is worth showing.
5. **Release prep** (spec section 8 and `docs/audit/appendix-d-assets.md`): rights audit, name decision (Thirty Bells vs Last Bell; one commit swaps it; the Steam game *The Last Bell* collides with the old name), a maker line in the credits (your studio name; the itch and GitHub names are `jafforge` and `jafforgehq`), a real score.
6. **Later ideas** (roadmap, kept in reserve): blueprints/research, traders and raiders, base power, traps and lures, the convoy ending, a dog, controller support, Steam page and Early Access.

## 10. File map

```
STATUS.md                      this file
README.md                      rules of play, controls, architecture, art and sound notes
project.godot, export_presets.cfg   Godot project; the Web preset (threads off)
scenes/main.tscn               the one scene; scripts/main.gd drives it
scripts/sim/                   the rules (headless): sim.gd (coordinator) + modules: supplies, medical, scavenge,
                               scenario, waves, tactics, workshop, traits, morale, bonds, skills, barks, storyteller,
                               build, jobs, recruits, town, lots, seasons, streets, vehicles, save_game;
                               rounds 17 to 21: avatar, radio, interact, nights, night_calls, night_data, relations,
                               specialists, initiative
scripts/render/                world drawing: build_node, dressing_node, parking_node, lighting, snow, fx ...
scripts/ui/                    HUD, menus, settings, Build screen (build_screen, build_lots, build_map), Town Board,
                               Duty roster (jobs_screen), tutorial coach, hints; the radio panel (radio_panel with its
                               pages jobs_page, build_page, map_page, news_panel; call_card, call_view, radio_verbs,
                               talk_card, night_kit, community_kit)
scripts/raid/                  round 14: raid_sim (a Sim for one place), raid_run (the squad rules), site_gen,
                               raid_scene / raid_hud / raid_overlay / site_canvas
scripts/drive/                 round 21: drive_scene (a subclass of raid_scene), drive_hud, car_sim, autopilot, road_gen,
                               road_events, car_node
scripts/audio/                 buses, sound (one-shots + loops), music, street_air (far groans by day)
assets/data/                   all the numbers: buildings, lots, town, seasons, vehicles, stations, posts, events,
                               barks, traits, hints, tutorial, site_layouts, dressing, map ...
assets/audio/                  sounds and the four music loops
tests/                         the suite (about 4000 checks); tests/run.gd runs it; tests/golden/ is the no-avatar harness numbers
tools/                         balance.gd (harness), avatar_bot.gd, night_lab.gd, community_probe.gd, compare_harness.py,
                               road_preview.gd, hud_shots.gd, work_sheet.gd and the make_*.py asset generators
docs/superpowers/specs/        the design (sections 7a to 7m = what each round became; 2026-10-03-avatar-and-radio-design.md is the avatar game's)
docs/superpowers/plans/        one plan per round (17's contracts are in the avatar-radio roadmap)
docs/superpowers/roadmap.md    the roadmap (current to round 10)
docs/audit/                    the full audit of 2026-10-01 and its appendices
docs/assets-log.md             every AI-made picture, with prompt, model and date (for the rights audit)
build/                         exports and zips (git-ignored); LastBell-web.zip is what went to itch
```

## 11. Starting a new session

Paste something like this:

> Read `STATUS.md` (branch `main`: the avatar game, rounds 17 to 23, pushed and on itch), sections 1 and 5b, then `README.md`. Do not push or touch itch unless I ask. First: tell me what you need from my playtest of the avatar game (the checklist after section 5b).

Claude's own notes for this project live in `/Users/jaf_lab/.claude/projects/-Users-jaf-lab-last-bell/memory/` (index: `MEMORY.md`; the most useful: `colony-sandbox-direction.md`, `rounds-7-to-10.md`, `itch-and-github.md`, `audio-web-silence-2026-10-02.md`, `work-pace-and-safety.md`). They load automatically on this machine; this file is the same story for a fresh start or another machine.
