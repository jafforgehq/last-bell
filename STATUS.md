# Thirty Bells: status

> **Read this first in a new session.** Written 2026-10-02 (end of a very long session) so that nothing lives only in a chat.
> The game is a 2D zombie colony-defence game in Godot 4.7.2 / GDScript. Working title **Thirty Bells** (the repo and the itch page still say *Last Bell*). Repo: `/Users/jaf_lab/last-bell`, branch `main`. Private GitHub: `jafforgehq/last-bell`. Restricted itch page: https://jafforge.itch.io/last-bell (project id 5076058, account `jafforge`).

## 1. Right now (the one-screen version)

| Thing | State |
| --- | --- |
| Game | Rounds 0 to 16 are built. **Nobody has played rounds 11 to 16 by hand** (tests, screenshots, a film of a trip and the bot only). You played up to about round 10. |
| Git | Everything is committed and **pushed**: GitHub's `main` is at the commit after `d97bb70` (rounds 15 and 16, the crew of five, the working audio fix). |
| Tests | **2267 passed, 1 failed** on `d97bb70`: the one failure was a raid-banner test that failed now and then in whole runs (never alone); it has since been made to pin its own state and passes alone, but the whole suite has not been re-run since. |
| itch (live) | Upload id 19534948 (2026-10-03 10:22): rounds 5 to 16 with the working audio fix, the louder sounds, the music, the crew of five and round 16's work life and animations. Checked: the embed loads to the title screen, the page is still Restricted, one file. |
| Biggest open risk | Balance and feel of rounds 11 to 14 for a human; the settlement game is harder than at round 10 (section 6). |

**Folders (home directory):** `/Users/jaf_lab/last-bell` is **the game** (the only Godot project, the only git repo, the one on GitHub and the one you open in Godot). `/Users/jaf_lab/last-bell-prototype-recovered` is only the old web prototype's JavaScript source, rebuilt on 2026-10-01 from an old chat transcript (`README.txt` inside says so); nothing in the game uses it, and it is outside git. Keep it (it is the generator of most of the art and sounds), but never work in it.

## 2. What the game is

A small crew holds a walled schoolyard against the dead for thirty nights (Autumn), or four seasons (Campaign, 102 days). You start with **three** survivors; the rest call in over the radio. Fixed 30 Hz rules loop with interpolated drawing; the sim is separate from the drawing so the harness and the tests run it headless. The design is `docs/superpowers/specs/2026-09-30-colony-sandbox-design.md` (sections 7a to 7m record what each round turned out to be; the appendix is the long-term wish list). Rules of play are in `README.md`.

Keys: **G** Town Board, **N** Build screen, **J** Duty roster, **M** workshop, **B** wall crew, **V** fields of fire, **L** alarm, **F5/F9** save/load, **Esc** pause menu.

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

- **Verified by machines:** the full test suite (rules, UI layout, saves, data), the balance harness (below), screenshots of the screens, a Web Audio probe of the web build (silent before the fix).
- **Never played by a human:** rounds 11 to 15 (the cut yard, the streets by day, cars and fuel, Take control, the car trip animation, the gate, the new Build screen), the Campaign's later seasons, outposts and garrisons, the new music and levels. A film of one real trip (a sedan with two people to the nearby houses, speed 1 and 3) was watched frame by frame by a tester agent and looked right from walking to the doors to unloading.
- **Process slips on record:** two `rm` calls on scratch files (the rule is "delete only via `~/.Trash`"); an earlier `pkill -f Godot` killed your open editor (never again).

### Known issues of round 16

- **Fixed after round 16's first report:** a mender now stands on the yard side of the wall piece (the first open ground in from the scaffold, `Sim.repair_spot`; the classic start and the lots' street walls keep the old spot), and the all-clear after a day threat is 45 game minutes (15 real seconds at the normal speed) instead of 10.
- **The pose reads weakly from behind** (hauling a crate, the rest mug, the nurse) and the hoe looks crude from the front. A real artist's frames would replace these.
- For a crew of five only Hector is guaranteed a call without the radio desk (the first three authored callers who did not start).
- The harness bot grows its crew to nine with tents first (`--beds`, off by default): a bigger crew faces bigger nights.

### Known issues of round 15 (found by review and the film, not fixed)

- **The bus's U-turn is a pirouette:** the 8-tile bus swings on the sedan-sized route, its tail pokes over the walkway at the gate and it lies across the apron for a moment. Rare (the bus is the last vehicle you find).
- **Three bays, four vehicles:** with all four home, the fourth shares a bay and overlaps.
- **Cars drive through the walls** you can build across the north street's two ends (the lane is at the street's middle): a walled lot does not stop a trip.
- **No headlights** (only brake lights), cars come home only by day, a vehicle found on a trip appears in its bay without driving in, and the van's open left door can touch a neighbouring sedan.
- **`--town-send` staging** needs the hour between 06:30 and 10:00 (`--hour=8`); at other hours the party is refused silently.

### First things to try by hand

1. Start a small-crew game; look at the yard (the motor pool and the gate), walk the survivor with **W A S D** and shoot with the mouse (round 17: `--noavatar` plays the old yard with right-click orders), press **N** (the Build screen is a list of buildings now).
1b. Send a trip **by car** early in the morning (06:30 to 10:00) and watch it from the doors to the unloading, at speed 1 and 3.
2. Press **G**: scout, loot, clear. Send a trip with **Take control** (the button on the place's card): move the squad, search a container, help a downed friend, retreat.
3. Send a trip **by car** (the Ride row on the board); watch the fuel line in the HUD; find fuel.
4. Watch the streets by day: do a few of the dead wander, and does shooting near them bring them?
5. Claim a lot on the Build screen and switch on "Wall the streets as the scrap allows".
6. Listen: music on the title and by day; at dusk the night track; a crowd at the wall switches to danger; the Settings Music slider.

## 6. Balance (the harness) and what it means

Harness: `tools/balance.gd` plays whole games headless with a bot policy. Standard difficulty, 30 days.

- **Settlement game** (`--crew=3`, informed bot, 8 games per seed): **2/8 and 3/8 wins on seeds 1 and 9** (median day 26.5 on both) with the cars on; 2/8 and 2/8 with no cars; 3/8 and 3/8 with no streets. Before the streets (round 10) it was about 7/16. The streets made it a bit harder; one cause was found and fixed (day gunfire drew every straggler to the walls).
- The bot's first use of cars (3 to 4 people by van to far places) lost games on days 16 to 21; sending 2 and only from 3 hours of road fixed it. That was the bot's policy, not the cars.
- **Round 15 (final tree, same bot, 8 games per seed):** settlement game seeds 1 and 9: **2/8 and 2/8 wins, medians 23.5 and 25** against 2/8 and 3/8, medians 26.5 and 26.5 before round 15: a little lower, within the noise of 8 games (the car trips cost about 71 game minutes each, the building homes moved the salvage bench). Classic start, informed, seed 9: 4/8 against 5/8, median 30 both.
- **Crew size (2026-10-02, after you said three felt low):** the New game screen offers Small crew (3), **Crew of five (the default for a new player)** and Full crew (6, the old yard). Harness, informed, seeds 1 and 9 together (16 games each): crew 3: 4 wins, medians 23.5 and 25; crew 4: 3 wins, 23 and 27.5; crew 5: 4 wins, 23.5 and 25.5. The nights scale with the crew, so the size changes how much there is to do, not how hard it is. (A prefs file that remembered crew 3 keeps showing 3 until you click another card.)
- **Round 16 (informed bot, crew 5, seeds 1, 9, 21 and 40, 8 games each = 32):** mean day reached 23.4 against 23.7 before; crew sizes identical (never above 6; the bot builds no tents). **Wins: 0 of 32 against 6 of 32.** The games that reach night 30 are few (5 in each arm, 3 of them survived it before and none now). A null perturbation (one extra random draw) takes the same bot from 4 wins to 2, so this may be noise, but it is not proven: if wins matter, run more seeds before trusting round 16's balance, or look at the Big Night (the dawn and day-threat rules are the suspects; switching all three round-16 rules off reproduces the old numbers exactly).
- **Classic start** (six people): identical to before round 7 up to round 14. **Round 15's map edits (the vehicle gate, the apron, the cleared street lane and the removed wreck) changed it a little**: default policy, 8 games seed 1, median day 17 -> 20.5 (0 wins both). An ablation with the old `map.json` and `dressing.json` restores the old numbers exactly, so it is the map, not the rules. It is easier, not harder; nobody plays the classic start to win, but the tutorial and the Full crew choice use it.
- **Campaign:** on Standard the bot dies in Autumn; on Story it finishes in 3 of 8. It needs a human's judgement.
- **Known balance gaps:** outposts are usually overrun in the harness (the policy never posts a garrison); the Campaign is not tuned for people.

## 7. How to do things

Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot` (alias `G` below). **You keep the Godot editor open on this folder: never `pkill`/`killall` Godot.**

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
cd /Users/jaf_lab/last-bell
$G --headless --path . --script res://tests/run.gd                    # the full suite (about 10 minutes)
$G --headless --path . --script res://tests/run.gd -- --only=test_music:   # one file (a trailing colon = exact file)
$G --headless --path . --import                                         # after adding assets (makes the .import files)
```

Tests extend `res://tests/case.gd` (`check`, `eq`, `near`); any logged error fails the run; write the failing test first.

Balance harness (flags: `--games --days --difficulty --seed --fast --jobs --policy=default|informed|none|keep --crew=3 --campaign --nolots --novehicles --nostreets --nobuild --out`):

```bash
$G --headless --path . --script res://tools/balance.gd -- --games=8 --days=30 --difficulty=1 --seed=1 --fast --jobs=4 --policy=informed --crew=3 --out=/tmp/x.json
```

Never run a matrix on a tree you are editing: `rsync` a snapshot first.

**Web export, zip, itch** (the page is Restricted with a password; **never** make it Public or untick the password without asking):

```bash
$G --headless --path . --export-release "Web" build/web/index.html
mv build/LastBell-web.zip build/LastBell-web-<date>-prev.zip     # keep the old zip
(cd build/web && zip -q -r ../LastBell-web.zip .)
```

Upload recipe that works (Claude in Chrome tools, your logged-in Chrome): full details in the memory file `itch-and-github.md`. In short: split the zip into 9 MB parts, one `file_upload` per part into an injected `<input type=file>`, rebuild the file inside the page and check its SHA-256 against the local zip, capture itch's own input by patching `HTMLInputElement.prototype.click`, press **Upload files**, set the file with a DataTransfer, wait, tick **This file will be played in the browser**, press **Save**. The same file name replaces the old upload in place. The edit page is https://itch.io/game/edit/5076058; the embed loads from `html-classic.itch.zone/html/<upload id>/` (current upload id 19523755). The itch page's title, text and screenshots are still the old prototype's.

**Probe web audio** (no ears needed): serve a copy of `build/web` with a hook in `index.html` that records `AudioContext`s, `AudioBufferSourceNode.start` calls and an analyser on the destination (`.claude/launch.json` has a `web-test` config on port 8123 serving the scratchpad's `webtest` folder). Headless tests use a dummy audio driver and cannot catch web audio bugs.

**Regenerate assets:** `python3 tools/make_music.py [title|day|night|danger]`, `python3 tools/level_sounds.py [--check]`, and the other `tools/make_*.py` (art; Python with Pillow and NumPy).

**Push:** only when you ask. `git push origin main` (fast-forward). The repo is private; scan the diff for keys first.

## 8. Rules for working here (from your instructions)

- Work and commit on **`main`**. Never push unless asked. Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Delete only by moving to `~/.Trash`**, never `rm`. **Never kill processes by pattern.**
- Keep builds lean and fast; short honest status with real numbers; don't ask mid-build questions that have a sensible default.
- The itch page stays Restricted with its password; the repo stays private.
- Use Meshy for art only when it clearly helps (costs confirmed and logged in `docs/assets-log.md`); do not draw realistic sprites as flat shapes in code (you rejected that).
- Before any paid release: a rights audit of every asset (sounds, fonts, images, AI-made pictures, with the AI-content disclosure Steam asks for) and a trademark check of the name.

## 9. What to do next (suggested order)

0. **Twenty more ideas** for the base, management and building are in `docs/superpowers/ideas-2026-10-03-base-and-management.md` (the author's picks marked: an inner wall, a kitchen, sanitation, a timetable, things going wrong inside, tiers of the settlement). The eight earlier ones (the gate as the heart of the night, fuel for the base, traps, upgrades, road events, territory, a garage, a heat map) are in the 2026-10-02 reply and `docs/superpowers/roadmap.md`'s reserve list.

1. **Finish the audio work** (section 4): confirm the web probe and the suite, commit, re-export, re-upload to itch, then listen.
2. **Playtest rounds 11 to 14 by hand** (checklist in section 5) and write down what is wrong or boring. This matters more than anything the bot says.
3. **Fix what the playtest finds**, then rebalance with the harness (the settlement game's win rate fell a little when the streets came in).
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
                               build, jobs, recruits, town, lots, seasons, streets, vehicles, save_game
scripts/render/                world drawing: build_node, dressing_node, parking_node, lighting, snow, fx ...
scripts/ui/                    HUD, menus, settings, Build screen (build_screen, build_lots, build_map), Town Board,
                               Duty roster (jobs_screen), tutorial coach, hints
scripts/raid/                  round 14: raid_sim (a Sim for one place), raid_run (the squad rules), site_gen,
                               raid_scene / raid_hud / raid_overlay / site_canvas
scripts/audio/                 buses, sound (one-shots + loops), music, street_air (far groans by day)
assets/data/                   all the numbers: buildings, lots, town, seasons, vehicles, stations, posts, events,
                               barks, traits, hints, tutorial, site_layouts, dressing, map ...
assets/audio/                  sounds and the four music loops
tests/                         the suite (about 2000 checks); tests/run.gd runs it
tools/                         balance.gd (harness) and the make_*.py asset generators
docs/superpowers/specs/        the design (sections 7a to 7m = what each round became)
docs/superpowers/plans/        one plan per round
docs/superpowers/roadmap.md    the roadmap (current to round 10)
docs/audit/                    the full audit of 2026-10-01 and its appendices
docs/assets-log.md             every AI-made picture, with prompt, model and date (for the rights audit)
build/                         exports and zips (git-ignored); LastBell-web.zip is what went to itch
```

## 11. Starting a new session

Paste something like this:

> Read `STATUS.md` in `/Users/jaf_lab/last-bell`, then the spec sections it points to. Work on `main`. Do not push or touch itch unless I ask. First: finish the audio work in section 4 (check the web probe and the suite, commit), then tell me what you need from my playtest.

Claude's own notes for this project live in `/Users/jaf_lab/.claude/projects/-Users-jaf-lab-last-bell/memory/` (index: `MEMORY.md`; the most useful: `colony-sandbox-direction.md`, `rounds-7-to-10.md`, `itch-and-github.md`, `audio-web-silence-2026-10-02.md`, `work-pace-and-safety.md`). They load automatically on this machine; this file is the same story for a fresh start or another machine.
