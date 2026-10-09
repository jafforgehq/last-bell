# HUD audit: how much of the screen the UI covers, and what it hides (PH7, 2026-10-09)

**Why.** A friend played the itch build (the embed, 1280 x 720) and did not see a zombie because overlays of the tutorial covered it. The owner says there are too many elements on screen at once and has decided that a new player gets a MINIMAL HUD in which an element appears when it matters. This is the measured audit of the clutter and the occlusion that the decision rests on. **No game behaviour was changed**: nothing under `scripts/` or `assets/` was touched; everything is in `tools/ui_audit/` (and `tools/capture_audit.gd`, the three-line file the game's own `--capture=audit` flag looks for). Sections 6 and 7 propose; they are not built.

Every number below was measured in a real window (Godot 4.7.2, Metal, the game's own flags), by diffing pictures of one frozen frame drawn with parts of the UI switched off. The pictures are in `/private/tmp/claude-501/-Users-jaf-lab-last-bell/6b84d821-4f10-4deb-be40-d511bdef2435/scratchpad/ph7-audit/` (sheets in `sheets3/`, every snapshot under `run3/<window>/s<seed>/<state>/`); copies of the sheets used here are in `docs/hud-audit-sheets/`.

## 0. The answer in one page

**The persistent boards alone (stores, objective, crew, clock, weapon, toolbar, minimap, the arrows) are 13 to 15 percent of the screen at 1280 x 720 in every state, from the first frame to the last, and on top of them come the guide, the banner, the alerts, the tips and the marks of the world: the whole UI is 20 to 26 percent in the first minutes, 28 by day at the base, 33 at the first attack night, 41 with the Build page or the morning card up.** At 1024 x 640 the same boards are 18 to 21 percent and the totals 28 to 52 percent. At 1920 x 1080 the boards are 9 to 10 percent and the totals 13 to 33 percent (the interface is scaled 1.2 there, the window is 2.25 times the area).

The boards keep to the edges: in the centre zone (the middle half of the width and of the height, a quarter of the screen, round the avatar) the persistent HUD is 0.0 to 1.9 percent. **What fills the centre is the guide and the banner: the banner is 5.7 percent of the screen and 6.3 percent of the centre zone, the guide's cues (the ring on the walker, "Hold the right button to aim", "Take the shells") 9 percent of the centre zone three seconds after the first walker steps out (14 in the shoot lesson's own state), the morning card 21 percent, the Build page 12 percent.**

**What hides the dead.** In the opening (seeds 1, 3, 5, 1280 x 720) the first walker was never hidden over half, in 6 looks (the moment it steps out and three seconds later), but: it steps out 2.3 to 2.8 s after the first key (the banner is 100, 52 and 0 percent up at that instant in seeds 3, 5 and 1), 12.8 to 14.2 tiles from her, at the edge of the window in two seeds, **within 0 to 4 pixels of the edge-arrow plate that points at the first house (18 percent under it in seed 3)**; and three seconds later **the shoot cue's own ring covers 33 to 38 percent of it in all three seeds** (the YOU tag and the distance arrow are beside it). At 1024 x 640, seed 3, the walker steps out **100 percent hidden under the "Cottage 43 m" plate** (edge_arrows 66 percent, pennants 29). At the first attack night, in a window of 1280 x 720 or 1280 x 800, the dead stand along the fence that is attacked, at the edge of the window, and **the right-hand column (clock, weapon panel and the alert and radio-call stack, 17 percent of the screen) or the crew cards at the top hide most of them: 3 of 5 dead in view in the clear night and 2 of 3 in the storm (one run), and 23 of 28 in a second run of the same scene (8 of 10, 9 of 9, 6 of 9 in its three looks); 6 of 8 at 1280 x 800 (the crew cards).** The things that hid them, in order: the alert and call column, the clock and weapon panels, the crew cards, the names, prompts and breach marks of the world, the morning card, the minimap, the tip card (12 percent), the edge-arrow plates.

**Top five offenders** (section 3): (1) the right-hand column of alerts and the radio call (8 to 11 percent of the screen at night; in the second run of the night it and the panels over it hid 8, 9 and 6 dead in three looks, four of them at 100 percent under the stack alone in one look); (2) the clock and weapon panels above it (5.7 percent, at the right edge, which is where the east fence is: each hid a dead one at 100 percent in every look of the second run); (3) the banner (5.7 percent of the screen, the largest single thing in the centre zone, up for 2.7 s at every start, at the walker's moment in two seeds of three); (4) the crew cards (1.9 percent, at the top edge, where the north fence's dead are: 54 to 100 percent over a brute, a runner and walkers at 1280 x 800, 94 percent over one in the storm); (5) the guide set: key legend 2.4, lesson card 1.8, cues up to 2.2 percent, and 9 to 14 percent of the centre.

**The proposal** (sections 6 and 7): a stage table for the first twenty minutes (the weapon panel as one line, the objective as one line, no clock panel, stores, crew cards, toolbar, legend, minimap or alerts until each matters), a threat rule (awake dead within 14 tiles or a shot in the last 3 s: everything that is not the fight collapses, boards over a dead one go ghost), a placement rule (one function keeps every card clear of the dead), and a budget: **persistent boards at most 6 percent of the screen before the claim and at a night, 12 by day; everything at most 10, 15, 10 percent (early, day, night); the centre zone at most 13, 5.5, 5; never a dead one in view hidden over half; a page or window at most 45 percent of the width, 55 of the height and 17 of the screen.** The minimal HUD, drawn from the same pictures (the kept parts cut down as the table says), has 5 to 8 percent UI in the first minutes against 20 to 26, and meets 298 of 316 budget checks (the 18 it fails are the night's boards over dead ones, which the ghost rule is for, the small windows and the 1920 scaling). `tools/ui_audit/run_audit.sh` re-measures it all in 3 minutes (the itch window) and says which lines are over.

## 1. Method

### What was played

`tools/ui_audit/driver.gd` is a driver of the game's own `--capture=<name>` kind (`scripts/main.gd` loads `res://tools/capture_<name>.gd`; here `tools/capture_audit.gd`, which only names the driver). It plays a staged scene with the same hands as `tools/capture_walk.gd` and `capture_fight.gd` (real W A S D key events, the game's own variables for the pointer and the trigger, aim, fire, reload, swing, walk to the fence that is attacked), and takes a SNAPSHOT at the moments a scene names.

**A snapshot** freezes the game (`Engine.time_scale = 0`: the sim, the camera, every tween stop, so the noise floor is measured and is **0 pixels in all 92 snapshots** (81 of the audit and 11 of the probe's run)) and draws the same frame again and again, each time with one part of the UI switched off. A part is switched off in the engine's `frame_pre_draw` (after every `_process`, so a part that sets its own `visible` each frame, as the legend and the minimap do, cannot put itself back) and is shown again after the draw. The pictures: `full` (as played), `again` (the noise floor), `asplayed` (with the edge shades), `flags` (what `--hide-lesson --no-banner --no-alerts` hides), `nohud` (what `--nohud` hides), `world` (the HUD and the names, prompts and marks of the world off: the bare world), and one `e_<part>` for each named part (22 of them: stores, objective, crew cards, clock, weapon, toolbar, minimap, the arrows, the pennants, the legend, the lesson card, the lesson cues, the banner, the alerts and the radio call, the toast, the morning card, the room chips, the radio panel, the loot pops, the overlay's names and prompts, the loot shimmer). The red edge of a hurt avatar and the bell's vignette are shades, not boards: they are off in every picture but `asplayed` and are not counted (`fx` in `result.json`).

Beside the pictures `meta.json` has: the rectangle of every part (pixels), the window, the zoom (32 px to the tile at 1280 x 720), Ruth's screen point, **every awake dead one** (`sim.zombies` not dying: kind, state, tile, tiles from her, screen point and the box of its sprite), the people, the lesson and objective, and a dump of the scene tree (every visible Control with its rectangle: `tools/ui_audit/tree_probe.gd`).

**The box of a dead one** is one tile wide and a tile and a half tall (a brute one third more), the feet 0.65 tile under the point the rules keep: measured on a walker of the opening (head 0.85 tile above the point, feet 0.35 below, the arm a little wider than a tile).

### What the pictures say

`tools/ui_audit/analyze.py` makes the masks (a pixel counts when its three channels together differ by more than 8 for the HUD, the guide, the banner and the alerts, 20 for the marks of the world, which have faint tints that are not ink, as the avatar's rally disc; then CLOSED by 4 and 2 pixels, so that the gap between two letters is not a hole to see through, and the boxes of the nodes are filled in, because a board on a dark night street hardly differs from it):
- **HUD**: `flags` against `nohud`: stores, objective, crew, clock, weapon, toolbar, minimap, the arrows and plates, the toasts, the pages, the morning card.
- **Guide, banner, alerts**: `full` against `flags`: what the owner's three flags put away: the lesson card, the key legend (`--hide-lesson` puts it away too: checked), the cues in the world, the rehearsal card, the tips, the banner, the alert stack and the radio call, the PAUSED pill.
- **Marks of the world** (world-space labels and prompts): `nohud` against `world`: the names, the YOU tag, the E prompt, barks, search marks, the room's flash, breach and forecast marks, the loot shimmer.
- **UI** is the union. Each is reported as a share of the screen and of the CENTRE ZONE (the middle 50 percent of the width and of the height).
- **BLIND share near her**: a box the size of a dead one's is put at every 4th pixel of the screen; the share of the places within 14 tiles of her (the threat rule's radius) where the UI covers more than half of the box. It is the chance that a dead one that walks into view stands where it cannot be seen, independent of where the dead of one run happened to stand.
- **Dead hidden** (over half): the share of a dead one's box under the UI; named by the part (`e_<part>` masks) that covers most of it.

### Checked against the game's own flags

`tools/ui_audit/verify_flags.py` plays three real screenshot runs of the arrival (plain, `--nohud`, `--hide-lesson --no-banner --no-alerts`) and compares their diffs with the snapshot's: `--nohud` **0.999** overlap (197,013 pixels against 196,900), the three flags **0.896** (90,637 against 86,942: the real flags leave the bottom-left corner, the guide's, 0.7 percent of the screen, a little different: they act through a saved setting at the next frame, the snapshot by hiding the nodes). The first check found that `--hide-lesson` also puts the key legend away; the snapshots count it with the guide.

### What was staged (the states)

All with `--winpx=WxH --os-scale=1 --town=<seed> --shot=<never> --frames=99999999 --prefs=<own file>` (so that nothing touches the owner's settings or save) and the scene's flags; a window is 1280x720 (the itch embed, the most important), 1280x800, 1920x1080, 1024x640.

| State | Flags (README) and hands | Seeds |
|---|---|---|
| (a) arrival, held | `--stage=arrive`; the game held at speed 0 as a real run holds it: "Press W A S D to begin", no banner (a screenshot run skips this) | 1, 3, 5 |
| (a) arrival, the first second | `--stage=arrive`; the banner "The bell is ringing somewhere", the WASD cue, the lesson card, the legend, the objective, the arrows | 1, 3, 5 |
| (b) the opening | `--stage=arrive`; Ruth walks the opening's own route with W A S D, the first key shows the banner as the real run does; snapshot at the instant the walker steps out (`opening.released`) and when 3 s of the game have passed | 1, 3, 5 |
| (c) in the house, dead near | `--stage=arrive --lesson=door:in` (inside the start house, the hall looked into), the clock running, two walkers put awake in the other rooms of the house 3.5 to 7.5 tiles off, run 2 s | 1, 3, 5 |
| (d) the claimed house by day | `--stage=rescued2 --hour=11 --advance=20`, the crew at work, the guide done, the tips on | 1 |
| (d) the first dusk | `--stage=fourth --slots=built --hour=18.7`, the guide done, the tips on | 1 |
| (e) the first attack night | `--stage=night --slots=built --weather=clear|storm --advance=135 --weapon=shotgun --avatar-at=149.5,91.5`; the hands of `capture_fight.gd` (aim, fire, reload, swing, walk to the fence that is attacked); three looks 6 s of the game apart while two or more dead are on the screen; the tips on | 1 |
| (f) the morning card | `--stage=night --slots=damaged --moment=dawn`; the card up | 1 |
| (g) the Build page, the radio panel | `--stage=arrive --lesson=build --radio=build`; `--stage=fourth --slots=built --hour=15 --radio=news,news` | 1 |
| the lessons | `--stage=arrive --lesson=walk|shoot|reload|find|claim|build|ask`, `--stage=claimed --lesson=rehearsal` | 1 |

"The guide done" (`--capture-guide=done`) puts the lesson card, its cues and the legend away in states that a real run reaches minutes after they are gone (a staged `fourth` or `night` run begins the guide again at its last lesson); the lessons are measured on their own. **The tips** (`hints.gd`: the dusk tip, the brute tip...) are the game's own and are off in a screenshot run; the driver makes them (`--capture-tips=1`) in the states where a real run has them. Seeds: the three of the opening are the town's seed (`--town=N`, README), i.e. three different towns.

### The commands

```bash
# once in a new worktree
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import

# one scene at one size (13 to 60 s): tools/ui_audit/scenes.py has all the scenes
python3 tools/ui_audit/scenes.py run OUT b_opening 1280x720 3
#   which is: Godot --path . -- --winpx=1280x720 --os-scale=1 --town=3 --stage=arrive --shot=OUT/raw/never.png --frames=99999999 \
#               --prefs=OUT/raw/prefs.cfg --capture=audit --capture-scn=opening --capture-name=b_opening --capture-out=OUT/1280x720/s3 --capture-wait=30

# the whole audit as run for this document (one Godot at a time; about 30 + 25 minutes on a busy laptop)
python3 tools/ui_audit/run_scenes.py OUT --scenes all   --sizes 1280x720
python3 tools/ui_audit/run_scenes.py OUT --scenes other --sizes 1024x640,1920x1080,1280x800
python3 tools/ui_audit/analyze.py --all OUT                # masks, parts, dead: result.json, sheet.png for each snapshot
python3 tools/ui_audit/report.py OUT --minimal --budget    # the tables of this document
python3 tools/ui_audit/check_budget.py OUT [--minimal]     # the budget, line by line (exit 1 when over)

# the probe, in 3 minutes (the itch window, town 1: arrival held and after the key, the opening, the house, the day, the night, the morning, the Build page)
tools/ui_audit/run_audit.sh /tmp/ui_audit
# the pictures
python3 tools/ui_audit/sheets.py OUT/1280x720/s3/b_opening_0 sheet.png --minimal    # as played | the masks and the dead | the minimal HUD | the numbers
python3 tools/ui_audit/dump_elements.py OUT/1280x720/s3/b_opening_0 [--tree]        # the list of parts with rectangles, areas, shares, and the dead
python3 tools/ui_audit/verify_flags.py OUT OUT/1280x720/s1/a_arrive 1280x720 1      # snapshot against the real flags
```

## 2. The tables

Shares of the screen in percent; the number in brackets is the share of the CENTRE ZONE. Mean of the seeds (a, b, c) or the three looks (e). "Dead in view" counts the dead with at least half their box on the screen, summed over the seeds and looks; the dice of the sim differ from run to run (section 4.3 has a second run of the night).

### 2.1 1280 x 720 (the itch embed)

| State | UI (the union) | HUD boards | Guide, banner, alerts, tips | Marks of the world | Persistent boards alone | Teaching parts | Transient parts |
|---|---|---|---|---|---|---|---|
| (a) arrival, held, before the first key | 20.3 (5.5) | 14.2 (0.2) | 5.9 (4.7) | 0.4 (0.6) | 13.4 (0.2) | 5.6 | 0.8 |
| (a) arrival, the first second after the key | 25.4 (8.7) | 13.6 (0.2) | 11.5 (7.9) | 0.4 (0.6) | 13.4 (0.2) | 5.6 | 5.7 |
| (b) opening: the walker steps out | 23.6 (7.0) | 14.8 (0.2) | 8.5 (6.0) | 0.4 (0.8) | 14.5 (0.2) | 4.6 | 3.8 |
| (b) opening: 3 s later | 21.7 (12.6) | 14.6 (1.9) | 6.5 (8.9) | 0.7 (2.0) | 14.4 (1.9) | 6.3 | 0.0 |
| (c) in the house, dead near | 20.2 (8.5) | 13.4 (0.0) | 5.2 (3.0) | 1.7 (6.1) | 13.1 (0.2) | 5.1 | 0.3 |
| (d) the claimed house by day, crew at work | 28.2 (9.1) | 14.9 (0.0) | 11.2 (5.1) | 2.3 (4.0) | 14.6 (0.0) | 0.0 | 11.2 |
| (d) the first dusk, the bell | 23.5 (4.3) | 15.5 (0.0) | 5.8 (0.0) | 2.3 (4.3) | 15.2 (0.0) | 0.0 | 5.8 |
| (e) first attack night, clear | 32.6 (4.9) | 21.3 (1.2) | 17.6 (1.6) | 1.2 (3.1) | 14.7 (0.2) | 6.4 | 11.2 |
| (e) first attack night, storm | 19.1 (2.4) | 15.1 (0.2) | 2.9 (0.0) | 1.1 (2.2) | 14.8 (0.2) | 0.0 | 2.9 |
| (f) the morning card | 40.9 (27.1) | 34.9 (20.9) | 2.9 (0.0) | 3.6 (7.1) | 14.5 (0.0) | 0.0 | 23.0 |
| (g) the Build page open | 41.1 (24.6) | 29.1 (12.2) | 9.4 (4.6) | 4.7 (8.7) | 13.1 (0.0) | 3.0 | 23.1 |
| (g) the radio panel open | 34.2 (14.1) | 28.8 (10.2) | 3.4 (0.0) | 2.4 (3.9) | 15.2 (0.0) | 0.0 | 17.7 |
| lesson: walk | 25.9 (11.8) | 14.1 (0.2) | 11.6 (11.0) | 0.4 (0.6) | 13.9 (0.2) | 5.6 | 5.9 |
| lesson: shoot | 27.2 (15.4) | 14.7 (0.2) | 12.3 (14.4) | 0.4 (0.9) | 14.5 (0.2) | 6.3 | 5.9 |
| lesson: reload | 27.5 (16.1) | 14.8 (0.2) | 11.8 (12.2) | 1.2 (4.2) | 14.6 (0.2) | 5.8 | 5.8 |
| lesson: find a house | 25.5 (9.0) | 14.6 (0.2) | 10.7 (7.9) | 0.4 (0.9) | 14.4 (0.2) | 4.6 | 5.9 |
| lesson: claim | 28.9 (14.8) | 14.5 (0.0) | 8.5 (4.8) | 6.5 (10.2) | 13.7 (0.0) | 4.5 | 4.6 |
| lesson: build | 28.6 (13.5) | 13.4 (0.0) | 11.3 (4.2) | 4.8 (9.3) | 12.5 (0.0) | 4.8 | 7.1 |
| lesson: ask | 30.6 (15.9) | 14.7 (0.0) | 11.5 (4.2) | 5.4 (11.7) | 13.6 (0.0) | 4.9 | 7.1 |
| lesson: rehearsal card | 30.4 (9.0) | 13.5 (0.0) | 14.8 (4.2) | 2.6 (4.7) | 12.6 (0.0) | 8.2 | 7.1 |

The same, with the blind share and the dead:

| State | UI % screen | UI % centre | HUD % | Guide, banner, alerts % | Marks of the world % | Persistent boards % | Blind near her % | Dead in view | Hidden over half |
|---|---|---|---|---|---|---|---|---|---|
| (a) arrival, held, before the first key | 20.3 | 5.5 | 14.2 | 5.9 | 0.4 | 13.4 | 14.5 | 0 | 0 |
| (a) arrival, the first second after the key | 25.4 | 8.7 | 13.6 | 11.5 | 0.4 | 13.4 | 21.1 | 0 | 0 |
| (b) opening: the walker steps out | 23.6 | 7.0 | 14.8 | 8.5 | 0.4 | 14.5 | 10.5 | 3 | 0 |
| (b) opening: 3 s later | 21.7 | 12.6 | 14.6 | 6.5 | 0.7 | 14.4 | 8.5 | 3 | 0 |
| (c) in the house, dead near | 20.2 | 8.5 | 13.4 | 5.2 | 1.7 | 13.1 | 6.6 | 14 | 0 |
| (d) the claimed house by day, crew at work | 28.2 | 9.1 | 14.9 | 11.2 | 2.3 | 14.6 | 17.2 | 0 | 0 |
| (d) the first dusk, the bell | 23.5 | 4.3 | 15.5 | 5.8 | 2.3 | 15.2 | 8.9 | 0 | 0 |
| (e) first attack night, clear | 32.6 | 4.9 | 21.3 | 17.6 | 1.2 | 14.7 | 13.0 | 5 | 3 |
| (e) first attack night, storm | 19.1 | 2.4 | 15.1 | 2.9 | 1.1 | 14.8 | 6.0 | 3 | 2 |
| (f) the morning card | 40.9 | 27.1 | 34.9 | 2.9 | 3.6 | 14.5 | 26.9 | 1 | 0 |
| (g) the Build page open | 41.1 | 24.6 | 29.1 | 9.4 | 4.7 | 13.1 | 18.8 | 1 | 0 |
| (g) the radio panel open | 34.2 | 14.1 | 28.8 | 3.4 | 2.4 | 15.2 | 11.9 | 0 | 0 |
| lesson: walk | 25.9 | 11.8 | 14.1 | 11.6 | 0.4 | 13.9 | 18.6 | 0 | 0 |
| lesson: shoot | 27.2 | 15.4 | 14.7 | 12.3 | 0.4 | 14.5 | 16.1 | 1 | 0 |
| lesson: reload | 27.5 | 16.1 | 14.8 | 11.8 | 1.2 | 14.6 | 18.6 | 0 | 0 |
| lesson: find a house | 25.5 | 9.0 | 14.6 | 10.7 | 0.4 | 14.4 | 12.9 | 0 | 0 |
| lesson: claim | 28.9 | 14.8 | 14.5 | 8.5 | 6.5 | 13.7 | 14.7 | 1 | 0 |
| lesson: build | 28.6 | 13.5 | 13.4 | 11.3 | 4.8 | 12.5 | 12.7 | 1 | 0 |
| lesson: ask | 30.6 | 15.9 | 14.7 | 11.5 | 5.4 | 13.6 | 15.6 | 1 | 0 |
| lesson: rehearsal card | 30.4 | 9.0 | 13.5 | 14.8 | 2.6 | 12.6 | 13.7 | 0 | 0 |

### 2.2 1280 x 800

| State | UI % screen | UI % centre | HUD % | Guide, banner, alerts % | Marks of the world % | Persistent boards % | Blind near her % | Dead in view | Hidden over half |
|---|---|---|---|---|---|---|---|---|---|
| (a) arrival, held, before the first key | 18.6 | 5.6 | 13.1 | 5.3 | 0.4 | 12.4 | 13.5 | 0 | 0 |
| (a) arrival, the first second after the key | 23.2 | 6.7 | 12.6 | 10.3 | 0.4 | 12.4 | 19.6 | 0 | 0 |
| (b) opening: the walker steps out | 21.6 | 3.3 | 13.6 | 7.7 | 0.4 | 13.3 | 8.5 | 3 | 0 |
| (b) opening: 3 s later | 19.7 | 11.4 | 13.3 | 5.8 | 0.6 | 13.1 | 6.4 | 3 | 0 |
| (c) in the house, dead near | 19.1 | 8.1 | 12.8 | 4.7 | 1.6 | 12.1 | 5.2 | 5 | 0 |
| (d) the claimed house by day, crew at work | 25.6 | 4.5 | 13.7 | 10.1 | 2.2 | 13.4 | 14.8 | 0 | 0 |
| (d) the first dusk, the bell | 21.6 | 4.1 | 14.1 | 5.2 | 2.2 | 13.9 | 7.4 | 0 | 0 |
| (e) first attack night, clear | 19.2 | 2.0 | 13.9 | 4.4 | 1.1 | 13.5 | 5.2 | 8 | 6 |
| (f) the morning card | 35.6 | 32.4 | 32.9 | 1.2 | 2.0 | 13.0 | 25.2 | 2 | 1 |
| (g) the Build page open | 40.4 | 22.9 | 29.6 | 8.5 | 4.4 | 12.0 | 15.6 | 1 | 0 |
| (g) the radio panel open | 32.6 | 11.2 | 25.4 | 5.2 | 2.2 | 14.0 | 9.1 | 0 | 0 |

### 2.3 1920 x 1080

| State | UI % screen | UI % centre | HUD % | Guide, banner, alerts % | Marks of the world % | Persistent boards % | Blind near her % | Dead in view | Hidden over half |
|---|---|---|---|---|---|---|---|---|---|
| (a) arrival, held, before the first key | 13.4 | 4.2 | 9.3 | 3.8 | 0.3 | 8.9 | 9.7 | 0 | 0 |
| (a) arrival, the first second after the key | 16.6 | 4.2 | 8.9 | 7.4 | 0.3 | 8.9 | 14.3 | 0 | 0 |
| (b) opening: the walker steps out | 15.4 | 2.3 | 9.6 | 5.5 | 0.3 | 9.6 | 5.4 | 3 | 0 |
| (b) opening: 3 s later | 14.2 | 8.6 | 9.5 | 4.2 | 0.5 | 9.5 | 3.9 | 3 | 0 |
| (c) in the house, dead near | 14.0 | 6.8 | 9.2 | 3.5 | 1.3 | 8.7 | 3.0 | 5 | 0 |
| (d) the claimed house by day, crew at work | 18.7 | 3.6 | 9.7 | 7.2 | 2.1 | 9.6 | 8.8 | 0 | 0 |
| (d) the first dusk, the bell | 15.5 | 3.9 | 10.0 | 3.4 | 2.1 | 9.9 | 3.8 | 0 | 0 |
| (e) first attack night, clear | 16.1 | 2.1 | 11.9 | 5.5 | 0.8 | 9.7 | 4.1 | 3 | 0 |
| (f) the morning card | 28.7 | 17.9 | 23.6 | 2.5 | 2.8 | 9.5 | 16.3 | 1 | 0 |
| (g) the Build page open | 32.5 | 11.9 | 24.2 | 6.0 | 3.6 | 8.7 | 9.1 | 1 | 0 |
| (g) the radio panel open | 24.7 | 6.0 | 19.2 | 3.4 | 2.2 | 10.0 | 6.0 | 0 | 0 |

### 2.4 1024 x 640

| State | UI % screen | UI % centre | HUD % | Guide, banner, alerts % | Marks of the world % | Persistent boards % | Blind near her % | Dead in view | Hidden over half |
|---|---|---|---|---|---|---|---|---|---|
| (a) arrival, held, before the first key | 28.5 | 6.7 | 20.1 | 8.2 | 0.5 | 18.8 | 23.2 | 0 | 0 |
| (a) arrival, the first second after the key | 32.7 | 17.2 | 19.2 | 13.2 | 0.5 | 18.7 | 29.1 | 0 | 0 |
| (b) opening: the walker steps out | 32.3 | 12.4 | 20.2 | 11.7 | 0.5 | 19.9 | 19.5 | 2 | 1 |
| (b) opening: 3 s later | 29.7 | 13.3 | 20.5 | 8.9 | 0.5 | 20.2 | 15.6 | 2 | 0 |
| (c) in the house, dead near | 28.7 | 11.2 | 19.4 | 7.2 | 2.4 | 18.1 | 14.0 | 5 | 0 |
| (d) the claimed house by day, crew at work | 37.6 | 17.4 | 20.7 | 15.3 | 2.4 | 20.2 | 28.7 | 0 | 0 |
| (d) the first dusk, the bell | 31.8 | 5.8 | 21.5 | 8.2 | 2.4 | 21.0 | 18.2 | 0 | 0 |
| (e) first attack night, clear | 24.6 | 3.6 | 20.8 | 2.7 | 1.3 | 20.4 | 12.3 | 0 | 0 |
| (f) the morning card | 47.1 | 41.9 | 45.5 | 0.0 | 2.6 | 19.5 | 39.2 | 7 | 1 |
| (g) the Build page open | 52.4 | 45.1 | 41.3 | 9.6 | 4.8 | 18.1 | 29.7 | 1 | 0 |
| (g) the radio panel open | 43.9 | 27.0 | 40.0 | 1.9 | 2.5 | 21.2 | 19.1 | 0 | 0 |

**Reading across the windows.** The persistent boards are 13.1 to 15.2 percent at 1280 x 720, 12.0 to 13.9 at 1280 x 800, 18.1 to 21.2 at 1024 x 640 and 8.7 to 10.0 at 1920 x 1080: the boards are the same size in points whatever the window (the interface is scaled up only from 1600 x 900), so the small window pays most. In the centre zone the small window is also worse (arrival 17.2 percent against 8.7: the banner is 8.5 percent of it). The Build page is 16.0 percent of the screen at 1280 x 720 (440 x 328) and at 1920 x 1080, 17.9 at 1280 x 800 and **22.9 at 1024 x 640**, the morning card 19.8 percent at 1280 x 720 (440 x 414) and 25.3 at 1024 x 640.

## 3. The biggest offenders, ranked

By the share of the screen they cover (mean over the arrival, the opening twice, the house, the day and the two nights; "most" is the worst state):

Mean over: a_arrive, b_opening_0, b_opening_3, c_clearing, d_day, e_night, e_storm.

| Rank | Part | Kind | Mean % of screen | Most % (in) | Mean % of centre | Blind near her % | In how many states |
|---|---|---|---|---|---|---|---|
| 1 | clock | persistent | 3.52 | 3.54 (e_storm) | 0.00 | 0.27 | 7 of 7 |
| 2 | alerts | transient | 2.86 | 10.62 (e_night) | 0.00 | 0.90 | 3 of 7 |
| 3 | banner | transient | 2.56 | 5.73 (a_arrive) | 2.80 | 3.78 | 4 of 7 |
| 4 | objective | persistent | 2.47 | 2.56 (a_arrive) | 0.00 | 0.58 | 7 of 7 |
| 5 | weapon | persistent | 2.19 | 2.20 (b_opening_3) | 0.00 | 0.59 | 7 of 7 |
| 6 | toolbar | persistent | 1.78 | 1.80 (b_opening_0) | 0.00 | 0.48 | 7 of 7 |
| 7 | key_legend | teaching | 1.33 | 2.40 (a_arrive) | 0.00 | 0.57 | 4 of 7 |
| 8 | minimap | persistent | 1.28 | 1.30 (e_storm) | 0.00 | 0.07 | 7 of 7 |
| 9 | crew_cards | persistent | 1.15 | 1.90 (d_day) | 0.00 | 1.99 | 7 of 7 |
| 10 | lesson_card | teaching | 1.05 | 1.85 (b_opening_0) | 0.00 | 0.19 | 4 of 7 |
| 11 | tip_card | teaching | 0.91 | 6.37 (e_night) | 0.13 | 0.59 | 1 of 7 |
| 12 | stores | persistent | 0.85 | 1.17 (e_storm) | 0.00 | 0.04 | 7 of 7 |
| 13 | overlay_names_prompts | world | 0.83 | 1.66 (c_clearing) | 2.28 | 0.39 | 7 of 7 |
| 14 | lesson_cues | teaching | 0.70 | 2.24 (b_opening_3) | 2.19 | 0.97 | 4 of 7 |
| 15 | pennants | persistent | 0.38 | 1.43 (b_opening_0) | 0.28 | 0.30 | 3 of 7 |
| 16 | edge_arrows | persistent | 0.33 | 0.78 (c_clearing) | 0.03 | 0.13 | 4 of 7 |
| 17 | loot_shimmer_marks | world | 0.23 | 1.48 (d_day) | 0.41 | 0.19 | 2 of 7 |
| 18 | radio_pill | persistent | 0.17 | 0.41 (d_day) | 0.00 | 0.00 | 3 of 7 |
| 19 | room_chips | transient | 0.11 | 0.75 (c_clearing) | 0.00 | 0.00 | 1 of 7 |
| 20 | objective_arrow_ring | persistent | 0.10 | 0.17 (c_clearing) | 0.18 | 0.00 | 6 of 7 |
| 21 | sprint_arc | persistent | 0.01 | 0.07 (c_clearing) | 0.03 | 0.00 | 1 of 7 |
| 22 | loot_pops | transient | 0.01 | 0.07 (c_clearing) | 0.03 | 0.00 | 1 of 7 |

At 1024 x 640:

Mean over: a_arrive, b_opening_0, b_opening_3, c_clearing, d_day, e_night.

| Rank | Part | Kind | Mean % of screen | Most % (in) | Mean % of centre | Blind near her % | In how many states |
|---|---|---|---|---|---|---|---|
| 1 | clock | persistent | 4.95 | 4.97 (a_arrive) | 0.00 | 1.78 | 6 of 6 |
| 2 | objective | persistent | 3.47 | 3.61 (b_opening_3) | 0.00 | 0.97 | 6 of 6 |
| 3 | weapon | persistent | 3.09 | 3.10 (a_arrive) | 0.25 | 2.40 | 6 of 6 |
| 4 | banner | transient | 2.73 | 6.12 (d_day) | 4.81 | 4.44 | 3 of 6 |
| 5 | toolbar | persistent | 2.51 | 2.53 (b_opening_3) | 0.00 | 1.41 | 6 of 6 |
| 6 | key_legend | teaching | 2.17 | 3.37 (a_arrive) | 0.00 | 0.85 | 4 of 6 |
| 7 | alerts | transient | 1.97 | 9.17 (d_day) | 0.20 | 1.30 | 2 of 6 |
| 8 | lesson_card | teaching | 1.72 | 2.60 (b_opening_0) | 0.00 | 0.06 | 4 of 6 |
| 9 | minimap | persistent | 1.51 | 1.51 (a_arrive) | 0.00 | 0.31 | 6 of 6 |
| 10 | crew_cards | persistent | 1.46 | 2.67 (d_day) | 0.00 | 2.59 | 6 of 6 |
| 11 | stores | persistent | 1.12 | 1.66 (e_night) | 0.00 | 0.00 | 6 of 6 |
| 12 | lesson_cues | teaching | 1.07 | 2.90 (b_opening_3) | 3.82 | 1.58 | 4 of 6 |
| 13 | overlay_names_prompts | world | 0.91 | 2.15 (c_clearing) | 2.57 | 0.44 | 6 of 6 |
| 14 | pennants | persistent | 0.69 | 2.04 (b_opening_0) | 0.37 | 0.54 | 3 of 6 |
| 15 | edge_arrows | persistent | 0.54 | 1.14 (a_arrive) | 0.01 | 0.26 | 4 of 6 |
| 16 | loot_shimmer_marks | world | 0.22 | 1.08 (d_day) | 0.47 | 0.17 | 2 of 6 |
| 17 | radio_pill | persistent | 0.19 | 0.58 (d_day) | 0.00 | 0.00 | 2 of 6 |
| 18 | room_chips | transient | 0.18 | 1.05 (c_clearing) | 0.00 | 0.02 | 1 of 6 |
| 19 | objective_arrow_ring | persistent | 0.15 | 0.22 (b_opening_3) | 0.20 | 0.00 | 5 of 6 |
| 20 | sprint_arc | persistent | 0.02 | 0.07 (c_clearing) | 0.01 | 0.00 | 2 of 6 |
| 21 | loot_pops | transient | 0.02 | 0.07 (c_clearing) | 0.01 | 0.00 | 2 of 6 |

**By what they hide**, which is the ranking that matters for the threat (section 4): (1) **the alert and call column** (the "alerts" part: `hud.alerts_box`, the call card, the PAUSED pill, 248 px wide, 0 to 11 percent: at night it is a stack of three or four alerts and the radio call "A plated brute is tearing at the east fence", 248 x 408 px from y = 239 to 660); it was the main cover over the east fence's dead: 3 hidden in the main run's first look (with the clock), and 8, 9 and 6 in the three looks of the second run, most of them under it at 100 percent. (2) **The clock and the weapon panel** (3.5 and 2.2 percent) over the right edge: they hid the dead of the same column, 100 percent each. (3) **The crew cards** (1.9 percent, 192 x 86 at the top middle): 54 to 100 percent over a brute, a runner and walkers of the north fence (six hidden in the three looks at 1280 x 800) and 94 percent over one at 1280 x 720 in the storm. (4) **The names, prompts and marks of the world** (the overlay, 1 to 2.6 percent, up to 5.6 percent of the centre at 1280 x 720): 46 percent of a walker in the house, 75 to 88 percent of three dead of a breach. (5) **The banner** (5.7 percent): it did not cover a dead one in any look, but it is up when the walker steps out in two seeds of three and is the biggest single thing in the centre zone. (6) The **edge-arrow plates and the pennants**: 0.3 to 0.7 percent, 100 percent over the walker at 1024 x 640. (7) **The tip card** (6.4 percent at the night): 12 percent over one dead one (the other looks had none under it). (8) **The minimap** (58 percent over one dead one in the street, 1024 x 640, morning) and **the morning card** (100 percent over one dead one at 1280 x 800).

Teaching parts (the key legend 2.4 percent, the lesson card 1.8, the cues 0.5 to 2.2 and 2 to 14 percent of the centre) are 4.6 to 6.3 percent of the screen throughout the first three minutes; the owner's three flags remove them (and the banner, the alerts and the radio call) and leave the HUD alone: 13 to 15 percent.

The list of the parts of one snapshot, with their rectangles (the first walker steps out, seed 3, 1280 x 720: `OUT/1280x720/s3/b_opening_0`):

b_opening, 1280x720, hour 7.1: UI 25.6% of the screen, 9.4% of the centre

| Part | Kind | Node rect (x, y, w, h) | Ink box | Ink px | % screen | % centre | Blind near her % |
|---|---|---|---|---|---|---|---|
| banner | transient | 339, 118, 602, 82 | (in its box) | 52812 | 5.73 | 6.31 | 8.91 |
| clock | persistent | 1020, 12, 248, 124 | (in its box) | 32556 | 3.53 | 0.00 | 0.31 |
| objective | persistent | 12, 49, 292, 76 | (in its box) | 23606 | 2.56 | 0.00 | 0.00 |
| key_legend | teaching | 12, 585, 327, 63 | (in its box) | 20601 | 2.24 | 0.00 | 0.24 |
| weapon | persistent | 1020, 149, 248, 77 | (in its box) | 20313 | 2.20 | 0.00 | 0.97 |
| lesson_card | teaching | 12, 654, 292, 54 | (in its box) | 17106 | 1.86 | 0.00 | 0.00 |
| toolbar | persistent | 894, 668, 374, 40 | (in its box) | 16588 | 1.80 | 0.00 | 0.65 |
| pennants | persistent | whole window (draws) | 1089, 54, 191, 562 | 13581 | 1.47 | 0.00 | 0.03 |
| minimap | persistent | 1145, 537, 122, 122 | (in its box) | 11766 | 1.28 | 0.00 | 0.00 |
| stores | persistent | 12, 12, 171, 29 | (in its box) | 5708 | 0.62 | 0.00 | 0.00 |
| crew_cards | persistent | 610, 10, 60, 86 | (in its box) | 5632 | 0.61 | 0.00 | 0.98 |
| lesson_cues | teaching | 0, 0, 1280, 720; 0, 0, 1280, 720 | (in its box) | 5012 | 0.54 | 2.11 | 0.75 |
| edge_arrows | persistent | whole window (draws) | 1124, 430, 144, 186 | 3625 | 0.39 | 0.00 | 0.00 |
| overlay_names_prompts | world | - | 384, 71, 882, 578 | 3338 | 0.36 | 0.80 | 0.00 |
| objective_arrow_ring | persistent | whole window (draws) | 13, 348, 1253, 305 | 1506 | 0.16 | 0.21 | 0.00 |

Dead in view:

| Kind | State | Tiles from her | Screen point | Box (x, y, w, h) | Covered % | Hidden | Nearest part (px) | Top parts over it |
|---|---|---|---|---|---|---|---|---|
| walker | chase | 14.2 | 1119, 456 | 1103, 429, 32, 48 | 18 | no | edge_arrows (0) | edge_arrows 18% |

And the first attack night (a second run of the scene, the second look: nine dead in view, nine hidden):

e_night, 1280x720, hour 23.5: UI 32.7% of the screen, 6.3% of the centre

| Part | Kind | Node rect (x, y, w, h) | Ink box | Ink px | % screen | % centre | Blind near her % |
|---|---|---|---|---|---|---|---|
| alerts | transient | 1020, 239, 248, 156; 1020, 441, 248, 195 | (in its box) | 89793 | 9.74 | 0.00 | 0.08 |
| tip_card | teaching | - | 11, 0, 1269, 351 | 58689 | 6.37 | 0.97 | 5.43 |
| clock | persistent | 1020, 12, 248, 124 | (in its box) | 32317 | 3.51 | 0.00 | 0.00 |
| overlay_names_prompts | world | - | 287, 79, 744, 576 | 24171 | 2.62 | 5.15 | 3.09 |
| objective | persistent | 12, 64, 292, 76 | (in its box) | 23491 | 2.55 | 0.00 | 1.27 |
| weapon | persistent | 1020, 149, 248, 77 | (in its box) | 20135 | 2.18 | 0.00 | 0.00 |
| crew_cards | persistent | 544, 10, 192, 86 | (in its box) | 17095 | 1.85 | 0.00 | 3.33 |
| toolbar | persistent | 894, 668, 374, 40 | (in its box) | 16213 | 1.76 | 0.00 | 0.00 |
| minimap | persistent | 1145, 537, 122, 122 | (in its box) | 11761 | 1.28 | 0.00 | 0.00 |
| stores | persistent | 12, 12, 229, 44 | (in its box) | 11066 | 1.20 | 0.00 | 0.00 |
| radio_pill | persistent | 12, 148, 119, 27 | (in its box) | 3647 | 0.40 | 0.00 | 0.00 |
| objective_arrow_ring | persistent | whole window (draws) | 572, 269, 26, 38 | 490 | 0.05 | 0.21 | 0.00 |

Dead in view:

| Kind | State | Tiles from her | Screen point | Box (x, y, w, h) | Covered % | Hidden | Nearest part (px) | Top parts over it |
|---|---|---|---|---|---|---|---|---|
| walker | breach | 12.4 | 972, 345 | 957, 318, 32, 48 | 75 | yes | overlay_names_prompts (0) | overlay_names_prompts 75% |
| brute | breach | 12.9 | 990, 346 | 969, 307, 42, 64 | 88 | yes | overlay_names_prompts (0) | overlay_names_prompts 88% |
| walker | breach | 13.1 | 992, 329 | 977, 302, 32, 48 | 86 | yes | overlay_names_prompts (0) | overlay_names_prompts 86% |
| walker | attack | 16.1 | 1090, 365 | 1075, 339, 32, 48 | 100 | yes | alerts (0) | alerts 100% |
| walker | attack | 16.2 | 1091, 301 | 1075, 275, 32, 48 | 100 | yes | alerts (0) | alerts 100% |
| walker | attack | 16.4 | 1091, 269 | 1075, 243, 32, 48 | 100 | yes | alerts (0) | alerts 100% |
| walker | breach | 16.8 | 1108, 300 | 1092, 273, 32, 48 | 100 | yes | alerts (0) | alerts 100% |
| walker | attack | 16.8 | 1091, 205 | 1075, 179, 32, 48 | 100 | yes | weapon (0) | weapon 100% |
| walker | attack | 18.9 | 1091, 45 | 1075, 19, 32, 48 | 100 | yes | clock (0) | clock 100% |

## 4. Do the overlays hide the dead? (occlusion)

### 4.1 The opening: where does the first walker appear? (the headline case)

The first walker (`scripts/town/opening.gd`) hides behind a car (or a solid thing of the street) near the way to the first house, `walker_ahead` 10 tiles short of the trigger point; it steps out when she has walked 6 tiles and is within 14 tiles of it; it then walks at her at 0.75 tile a second, and for the first 45 s (or until she has killed one) it holds 3 tiles off and its claw is kept back. In play the first key lifts the start hold and the banner appears; the walker steps out 2.3 to 2.8 s later. Seeds 1, 3, 5, 1280 x 720:

| Seed | First key to the walker out | Banner then (alpha) | The WASD cue card then | Where it appears (screen point; Ruth) | Tiles from her | Nearest part (pixels) | Covered then | Covered 3 s later (by) |
|---|---|---|---|---|---|---|---|---|
| 1 | 2.77 s | 0.00 (gone) | gone (it ends at 6 tiles walked) | 228, 242 (left, upper); Ruth 621, 353 | 12.8 | pennants, 72 | 0 percent | 38 (lesson cues: the ring and the aim card) |
| 3 | 2.27 s | **0.99 (up)** | gone | **1119, 456 (the right edge, 161 px from it)**; Ruth 676, 360 | 14.2 | **edge_arrows, 0: the "Cottage 43 m" plate** | **18 (edge_arrows)** | 33 (lesson cues) |
| 5 | 2.47 s | 0.52 (fading) | gone | **1119, 456 (the right edge)**; Ruth 694, 371 | 13.5 | pennants, 4 | 0 | 37 (lesson cues) |

- The banner (339, 118, 602 x 82) is 42 to 256 pixels above the walker in all three (seed 1: it has already faded): **it never covers it**. At the moment of the step-out the WASD card is gone. What is on the screen at that moment is the 14 to 15 percent of boards, the objective card, the weapon panel and the clock, and a plate: the plates (`edge_arrows.gd`, a pennant, a star for the best house) are put on the rim on the line from the middle of the window to the house, and **the first walker comes from the same bearing: it hides behind a car on the way to the first house.** In seeds 3 and 5 both are at the right edge, one against the other (0 and 4 px); in seed 1 the walker is at the left, the plates at the right, 72 px.
- Three seconds later the walker is 2.1 to 4.4 tiles from her and **the shoot cue is drawn on it**: the gold ring with its ticks, the "Ammo" tag, the YOU tag and the "14 m" arrow, the card "Hold the right button to aim, click to fire", the prompt "E Take the shells": 33 to 38 percent of its sprite in all three seeds. The cue is meant to mark it, and it is the one overlay that covers it. At 1920 x 1080 the same is 26 to 33 percent, at 1024 x 640 33 to 39.
- **At 1024 x 640** (seed 3) the walker steps out **100 percent hidden** (edge_arrows 66, pennants 29): the plate "Cottage 43 m" and its arrow are drawn on it; seed 5 clear. The window is 20 percent smaller each way, the plates the same size.
- **At arrival** (before the first key) nothing is dead on the screen; the walker is dormant behind a car 10 to 14 tiles ahead. In seed 5 its hiding place is on the first screen, at (1120, 456), under the right edge's plate column. The banner is 5.7 percent of the screen (608 x 87, 6.3 percent of the centre zone), the WASD card is beside Ruth, the legend and the lesson card at the bottom left.

Sheets (`docs/hud-audit-sheets/`; each is as played | the masks with the dead boxed | the minimal HUD | the numbers): `1280x720_03_opening_s3_walker_out.jpg` (the walker out, banner up, the plate beside it), `1280x720_08_opening_s5_plus3s.jpg` (the ring on it), `1024x640_21_opening_s3_walker_hidden.jpg` (hidden under the plate).

### 4.2 In the house, rooms not cleared, dead near

Two awake walkers put in the other rooms of the start house, with the house's own dead awake as well: 14 dead in view over the three seeds (5, 6, 3); none hidden over half. The names, prompts and marks cover them at most 46 percent (seed 3, the E prompt "Hold to claim. There are still dead in the hall" and the "Look in here" tag are drawn beside Ruth and the dead one is in the next doorway), the lesson cue 12 percent (26 at 1024 x 640), the edge-arrow plates and pennants 12 percent of one at the top edge. At 1024 x 640 a dead one at her feet is 48 percent under the "Look in here" tag and the claim prompt. The UI is 20 percent of the screen and 8.5 of the centre (the E prompt, "Look in here", the door's outline, the room's chip).

### 4.3 The first attack night

The night's dead come to the fence the dice pick; Ruth stands at the gate (the stage's place) and walks toward the dead of the fence that is attacked, as `capture_fight.gd` does. In the three looks of the main run at 1280 x 720 (clear) there were 3, 2 and 0 dead in view with at least half of the box on the screen; in the storm 0, 3, 0. The dead in view in every look at 1280 x 720 (the table covers all the states; the night is its rows (e)):

| State | Seed | Dead in view | Covered over 0 | Over 30 percent | Hidden over 50 percent | What covers them (top parts) |
|---|---|---|---|---|---|---|
| (b) opening: the walker steps out (b_opening_0) | 1 | 1 | 0 | 0 | 0 |  |
| (b) opening: the walker steps out (b_opening_0) | 3 | 1 | 1 | 0 | 0 | edge_arrows 18% |
| (b) opening: the walker steps out (b_opening_0) | 5 | 1 | 0 | 0 | 0 |  |
| (b) opening: 3 s later (b_opening_3) | 1 | 1 | 1 | 1 | 0 | lesson_cues 38% |
| (b) opening: 3 s later (b_opening_3) | 3 | 1 | 1 | 1 | 0 | lesson_cues 33% |
| (b) opening: 3 s later (b_opening_3) | 5 | 1 | 1 | 1 | 0 | lesson_cues 37% |
| (c) in the house, dead near (c_clearing) | 1 | 5 | 1 | 0 | 0 | overlay_names_prompts 17%, lesson_cues 12% |
| (c) in the house, dead near (c_clearing) | 3 | 6 | 2 | 2 | 0 | overlay_names_prompts 46%, edge_arrows 12%, pennants 12% |
| (c) in the house, dead near (c_clearing) | 5 | 3 | 1 | 0 | 0 | lesson_cues 6% |
| (e) first attack night, clear (e_night_1) | 1 | 3 | 3 | 3 | 3 | alerts 100%, clock 100% |
| (e) first attack night, clear (e_night_2) | 1 | 2 | 2 | 0 | 0 | tip_card 12%, overlay_names_prompts 1% |
| (e) first attack night, storm (e_storm_2) | 1 | 3 | 3 | 2 | 2 | crew_cards 94%, overlay_names_prompts 17% |
| (f) the morning card (f_dawn) | 1 | 1 | 1 | 1 | 0 | overlay_names_prompts 35% |
| (g) the Build page open (g_build) | 1 | 1 | 0 | 0 | 0 |  |
| lesson: shoot (l_shoot) | 1 | 1 | 1 | 0 | 0 | lesson_cues 18%, overlay_names_prompts 5% |
| lesson: claim (l_claim) | 1 | 1 | 0 | 0 | 0 |  |
| lesson: build (l_build) | 1 | 1 | 0 | 0 | 0 |  |
| lesson: ask (l_ask) | 1 | 1 | 0 | 0 | 0 |  |

A second run of the same clear night (the sim's dice differ between runs; `tools/ui_audit/run_audit.sh` made it, `probe1/`) had **10, 9 and 9 dead in view and 8, 9 and 6 hidden over half**: the east fence's dead stood in a column at x = 970 to 1190 px (12 to 19 tiles from her, the camera on her), under the clock (y 12 to 136), the weapon panel (149 to 226) and the alert stack (239 to 660): the part that hid them was **the alerts (100 percent over four to five of them in each look), the weapon panel (100), the clock (98 to 100), and the overlay's names, forecast brackets and breach rings (59 to 88 percent over three dead of a breach, a brute among them)**. The stack itself says what they are ("East fence, south part under attack", "A plated brute is tearing at the east fence"): **the card that tells the player where the dead are sits on top of them.**

At 1280 x 800 (the north fence): 8 dead in view over the three looks, 6 of them hidden, by the crew cards (a brute 98 percent, a runner 81, walkers 100 and 54) and the overlay (30 percent more on two of them). At 1920 x 1080: 3 dead in view, none hidden (11 percent at most); at 1024 x 640 the three looks had the dead at the very edge (under half a box on the screen). **The tip card** (the "Dusk" tip, 330 x 150 at the top left, placed by `Coach.best_rect` which keeps off the avatar and the gun's readout but not the dead) covered 12 percent of one dead one in the main run.

**Blind share near her** (the chance that a dead one within 14 tiles of her would be more than half hidden, wherever it stands), at 1280 x 720: 14.5 and 21.1 percent on the first screen (held, and after the first key), 10.5 and 8.5 in the opening, 6.6 in the first house, 17.2 by day (the IDEA call card), 13.0 in the clear night, 6.0 in the storm, 27 under the morning card, 18.8 under the Build page.

### 4.4 The morning card and the pages

The morning card is 440 x 414 (19.8 percent of the screen and 21 percent of the centre zone at 1280 x 720; 25.3 percent of the screen and 39 percent of the centre zone at 1024 x 640), placed by `Coach.best_rect` beside her; it covered 100 percent of one dead one at 1280 x 800, and the minimap 58 percent of another at 1024 x 640. The Build page and the radio panel: 440 x 328 and 440 x 293 at the right (16.0 and 14.3 percent of the screen, 12.2 and 10.2 percent of the centre); the banner "This house is yours" is up over the page for its 2.7 s.

## 5. How the overlays are placed today (the code audit)

| Part | Where, and by what | Looks at the dead? |
|---|---|---|
| Banner (`hud.show_banner`, `_fit_banner`) | hung from the middle of the top, under the crew bar, as wide as its words (up to 60 percent), 0.45 s in, 1.8 s held, 0.45 s out | no |
| Cue plates and rings (`tutor_cues.gd`, `_beside`) | beside the avatar, up and to the side with more room, the first of seven spots that is inside the window and clear of the HUD's boards (`_hud_rects`) | no: the boards only |
| Alert stack and radio call (`hud.alerts_box`, `alert_feed.gd`, `call_card.gd`) | the right column under the weapon panel, three cards then "+n more"; a call that waits is sticky and takes four buttons (248 x 195) | no |
| Edge-arrow plates (`edge_arrows.gd`, `HudFree.nearest_free`) | on the rim along the line from the middle to the house, slid clear of the boards and of each other | no: the boards only |
| Key legend and lesson card (`town_hud.place`) | bottom left, the legend above the card, hidden while it would touch another board | no |
| Tips (`hints.gd`) | `Coach.best_rect(hud, sz, vp, Rect2(), "top", false)`: the least cost over the HUD's boards, **no `keep_clear`** | no |
| Morning card (`dawn_tally.gd`) | `Coach.best_rect` with `kept_clear()`: the avatar and the gun's readout (the coach's own list), `prev` for hysteresis | the avatar only |
| Crew cards, clock, weapon, stores, toolbar, minimap | fixed corners | no |
| World names, prompts, YOU tag, range ring, forecast brackets, breach rings (`overlay_node.gd`) | in the world, at the thing | they mark them, and cover them |

`Coach.best_rect` (`scripts/ui/coach.gd`) is the one function that scores spots by what they cover: `keep_clear` rectangles cost 50 for each pixel, boards 1, a `prev` bonus keeps a card where it was. Only the morning card and the tips use it, and neither is given the dead. That is the small hook the placement rule (section 6) needs.

## 6. The minimal HUD: the stage table, the threat rule, the placement rule

What follows is drawn from the numbers above and kept to what the code can already do (a switch that exists) or a small addition (a reveal rule on a state the rules already keep). It is what `tools/ui_audit/sheets.py` draws as "the minimal HUD" in the sheets (section 8) and what the budget (section 7) was set against. Nothing here is built.

### The stage table (what is on the screen in each phase of the first 20 minutes)

Legend: **off** nothing drawn; **min** the collapsed form (named); **full** as it is now; **on demand** only when the player asks (a key or a click) or the game raises it, and it goes at the first threat. "exists" means the code already has the switch; "small" means a reveal rule on a state the rules already keep (no new system).

Phases (minutes are a first-time player's, from the owner's runs and the lab: the lab's bot is 12 to 28 real minutes to the end card): P1 arrival (0 to 0.2), P2 the road (0.2 to 1), P3 the first house (1 to 3), P4 clearing (3 to 7), P5 claim (7 to 8), P6 build (8 to 12), P7 rescue (10 to 16), P8 first dusk (16 to 18), P9 first night (18 to 25), P10 morning (25 on).

| Part | P1 arrival | P2 road | P3 first house | P4 clearing | P5 claim | P6 build | P7 rescue | P8 first dusk | P9 first night | P10 morning |
|---|---|---|---|---|---|---|---|---|---|---|
| Weapon panel (name, rounds, reload bar) | min: name and `3 / 40` | min | min | min | min | min | min | min | min | min |
| Stores strip | off (the rounds are in the weapon panel) | off | off | off | **full** (food, water, meds, scrap come with the stash) | full | full | full | min: the one that is low | full (it is on the card too) |
| Objective card | min: title line | min | full (2 lines: "Clear the house 1 of 8") | min while dead are awake within 14 tiles | full | full | full | full | off while dead are within 14 tiles, else min | in the card ("Today") |
| Objective arrow and distance at her feet | on (the road) | on | on until the door | off | off | off | on only when the objective is over 7 tiles away | off | off | off |
| Crew cards (top middle) | off (the YOU tag over Ruth says it) | off | off | off | off | off | **on**, one card for each person who has joined | full | compact: face and health bar, no name | full |
| Clock panel | min: day and hour | min | min | min | **full** (the dusk countdown matters from the claim) | full | full | full | min: hour and "dawn in" | min |
| Toolbar | min: pause, speed, menu (three icons) | min | min | min | full, 60 percent faded while idle | full (Build button lit by the lesson) | full (Radio lit) | full | min | full |
| Minimap | off | off | **on** | on | on | on | on | on | on (the dead's dots are the point) | on |
| Edge arrows to houses | on: ONE arrow, the best house | one | off from the door | off | off | off | off; "Home" arrow when she is over 50 tiles out | off | off | off |
| Key legend | off (its keys come with the lesson that needs each) | off | off | off | off | off | off | off | off | off |
| Lesson card | merged into the cue ("1 of 5 Walk") | merged | merged | merged (a HINT only after 20 s stuck) | merged | merged | merged | gone | gone | gone |
| Lesson cue in the world | WASD beside her | aim card and the ring on the walker; ammo box | ring on the door | outline of the next door; "?" over a container | ring where E claims | ring on the fence section | ring on the first crew card | off | off | off |
| Banner | top strip, 2 s ("The bell is ringing...") | none while a walker is awake | none | none | top strip, 2.5 s ("This house is yours") | none | top strip ("Two survivors are home") | top strip, the bell | top strip, "Night 4", held back while dead are within 14 tiles | none (the card) |
| Alerts and the radio call | off | off | off | off | off | one line | call card full when no dead are within 14 tiles, else one line | one line each, 2 at most | one line each, danger only, 2 at most, top right above the clock | one line |
| Toasts | one line at the top strip | same | same | same | same | same | same | same | danger only | same |
| Tips (the game's own, `hints.gd`) | none | none | none | none | none | none | none | **"Dusk" tip once**, shown only when she is indoors or no dead are within 14 tiles | held until quiet | none |
| Morning card | - | - | - | - | - | - | - | - | - | **compact card** (360 x 200 at a corner, placed by `Coach.best_rect`), 10 s |
| Radio, Build, Jobs, Map pages, inventory and loot window | - | - | - | - | on demand | on demand | on demand | on demand | on demand, closed at the first awake dead within 8 tiles | on demand |
| World labels: YOU tag, names, E prompt, range ring | YOU tag 10 s, prompt for the nearest thing only; ring off | same | same | same | same | same | names of crew within 6 tiles | same | same | same |

Triggers, in the code's own terms (all small):
- **Stores, clock and toolbar reveal at the claim**: `scenario.stage()` goes from `arrive` or `alone` to `claimed` (`stores_calm.ALWAYS` already has a list to reveal from; `revealed` is for good).
- **Crew cards at the first rescue**: `sim.people` has a second person (the HUD's `bar_plan` already lays out one card for each).
- **Minimap at the first house**: `sim.houses.house_at(avatar) >= 0` once or `scenario._near_candidate() < 8` (the setting `ui/minimap` stays the player's off switch).
- **One edge arrow**: `edge_arrows.gd` already takes the best tier first; show the rest only after 30 s of play.
- **Legend into the lessons**: `key_legend.gd` already removes a hint for good when its key is pressed; start every chip at alpha 0 and fade it in with the lesson id that names its key (walk, shoot, reload).
- **Lesson card merged with the cue**: the cue already names the verb ("Walk", "Shoot it"); drop the card's second line while a cue is up.
- **Banners and tips wait for quiet**: the HUD's `show_banner` and `hints.tick` ask `threat_near()` (below) and queue.
- **Dusk tip**: the existing `bell_rung` condition plus "indoors or quiet".
- **Morning card compact**: `dawn_tally.gd` has the placement; cut the stores and crew rows into one line each at 1280 x 720 and below.

### The threat rule

**Trigger.** `threat_near()` is true when any awake dead one (`sim.zombies` not dying or dead) is within **14 tiles** of the avatar by straight line, or she fired within the last **3 seconds**, or she is hurt (health under 70 percent). It goes false only when no awake dead one is within **18 tiles** and **3 seconds** have passed since the last shot (a hysteresis, so that nothing flickers at the edge of the circle).

**What fades or collapses when it is true** (0.25 s fade; each part keeps its place; nothing moves under the mouse):
1. Objective card: off (or its title line only, never its sub line); the arrow at her feet off.
2. Lesson card, key legend, banners, tips, toasts of the info kind: held in a queue; a banner older than 5 s when the threat ends is dropped, a tip is shown once the quiet comes.
3. Alerts and the radio call: the call card and each alert cut to ONE line (the title and an "Answer" word; the buttons come back on a click or when the threat ends); at most 2 lines, danger first, in the top strip, never in the right column under the weapon panel.
4. Crew cards: compact (face and health bar).
5. Clock: day and hour only. Toolbar: 35 percent alpha. Stores: the low store only.
6. Pages and windows (Build, radio, Jobs, inventory, loot): fade to 35 percent at once and close when an awake dead one comes within 8 tiles (the pages never pause the game; this is the same rule as the loot window that closes when she walks 3 tiles away).
7. The cues stay only when they are about the dead one (the ring on the walker, the aim card); a cue that points at a thing (door, ammo box, claim spot) goes.

**How it returns.** When the threat ends, in this order, 0.5 s apart: the clock and the objective, the crew cards, the toolbar, then the queue (banners and tips, newest first, none older than 5 s), then the alerts' buttons. The minimap and the weapon panel never go.

### The placement rule (banners, cue cards, tips, alerts, toasts, plates)

One function, `Coach.best_rect` (`scripts/ui/coach.gd`), already picks the spot for the morning card and the tips: the candidate with the least cost, a `keep_clear` list of rectangles that cost 50 for each pixel covered (today: the avatar and the gun's readout), the HUD's boards at 1, `prev` for hysteresis. The audit found that only the morning card and the tips use it; the banner, the cue plates (`tutor_cues._beside`), the alert column and the edge-arrow plates (`HudFree`) do not look at the dead.

1. **Keep clear, always**: the sprite box of every awake dead one within 14 tiles, grown by one tile each way (a box of 2 x 2.5 tiles round each), the avatar's box grown by one tile, and the segment from the avatar to the nearest awake dead one grown to 1.5 tiles wide (the line of fire). These go into `keep_clear` of `best_rect`, `tutor_cues._beside` (its `blocks`) and `HudFree.nearest_free` (its `others`).
2. **Never over a dead one in view**: a plate or card whose best spot still covers one moves to the next spot, and if every spot does, it waits (a banner, a tip) or becomes one line in the top strip (an alert).
3. **Cues point, they do not cover**: a ring on a dead one is drawn as four ticks 4 px outside its box, never a filled disc; the YOU tag and the name sit above the head, not at the feet, when a dead one is within 3 tiles.
4. **Edge-arrow plates slide off the bearing of the awake dead**: the plate to a house is put on the rim where the line from the middle of the window to the house leaves it; the first walker comes from the same bearing (it hides behind a car on the way to the first house). A plate within 80 px of an awake dead one's screen point slides along the rim to the nearest free place (`HudFree.nearest_free` already slides it clear of boards).
5. **Banners hang in the top strip only**: y under 100 px at 1280 x 720, between the crew cards and the clock, never in the middle third of the window; 40 percent of the width at most.
6. **Pages and windows open on the side away from the avatar** (the half of the window that does not have her), by the same function, and never over the strip within 5 tiles of her.
7. **One card at a time** of the kinds banner, tip, call card (a queue, longest-waiting first); a second one waits.
8. **Ghost the board over a dead one.** At the edge of the window (where the fence's dead stand, and where the right column, the clock and the crew cards are) no move of a card can clear them: any HUD board whose rectangle meets an awake dead one's box (grown by half a tile) within 14 tiles of her is drawn at 0.3 opacity until it has been clear for 1 s. `tools/ui_audit/analyze.py` already counts a part drawn at 0.4 opacity or less as not hiding, so the probe will show the effect.

## 7. The clutter budget, and the probe

Numbers to enforce, in percent of the screen at 1280 x 720 (at another window `persistent`, `ui`, `centre` and `blind` are multiplied by the area ratio and the square of the interface scale, `tools/ui_audit/budget.json`). They come from the best of the current states and from the minimal HUD of section 6 drawn on the same frames (`tools/ui_audit/sheets.py` `MINIMAL`): **a number that the minimal HUD does not meet is not in the table.**

| Group (the snapshots it holds) | Persistent boards | UI, all | Centre zone | Blind near her | Dead hidden over half | Most a dead one is covered |
|---|---|---|---|---|---|---|
| **early** (a_hold, a_arrive, b_opening, c_clearing, l_) | 6.0% | 10.0% | 13.0% | 5.5% | 0 | 40% |
| **day** (d_day, d_dusk) | 12.0% | 15.0% | 5.5% | 7.5% | 0 | 40% |
| **threat** (e_night, e_storm) | 6.0% | 10.0% | 5.0% | 5.0% | 0 | 40% |
| **card** (f_dawn) | 8.0% | 20.0% | 9.0% | 12.0% | 0 | 40% |
| **window** (g_build, g_radio) | 8.0% | 30.0% | 23.0% | 9.0% | 0 | 40% |

An on-demand window (Build, radio, Jobs, the inventory with its loot window, the stash): at most **45 percent of the width, 55 of the height and 17 of the screen** at every window size (a window is laid out in the interface's own points, so its share is not scaled). Now: the Build page 34.8 x 46.1 x 16.0 percent at 1280 x 720 (ok), 17.9 percent of the screen at 1280 x 800, 57.9 percent of the height at 1920 x 1080 and **22.9 percent of the screen and 43.6 x 52.8 at 1024 x 640** (over).

**Space for the inventory** (INV-UI is on `main` since 9ab8fed: `scripts/ui/inv_*.gd`; Tab and I open it, the game does not pause; `docs/superpowers/specs/2026-10-09-inventory-design.md`). **Measured** with the game's own staging (`--stage=claimed --hour=10 --inv=open`, scene `h_inv_pack`, the same snapshot and tree dump): the backpack window (the 8 x 4 grid, the weapon and the melee slot, a hint line) is **412 x 359 points at (12, 142)**, under the objective card at the left: 32 percent of the width, 50 of the height, **16.0 percent of the screen at 1280 x 720**; 348 x 292 (34 x 46, **15.5 percent**) at 1024 x 640; 412 x 359 (14.4 percent) at 1280 x 800; 494 x 431 (26 x 40, **10.3 percent**) at 1920 x 1080. It fits the window budget (45 x 55 x 17) at every size. With the persistent HUD behind it the whole UI is **37.4 percent of the screen and 20.2 percent of the centre zone at 1280 x 720, 45.0 and 30.7 at 1024 x 640, 34.5 and 16.0 at 1280 x 800, 24.5 and 3.9 at 1920 x 1080**: the window's own cost is 16 percent, the boards' 14 (sheet `1280x720_29_backpack_window.jpg`). **The loot window and the stash panel were not measured**: `--inv=loot` and `--inv=stash` open at frame 6 of a staged run and were gone by the time a frozen snapshot (or a shot at frame 40) was taken, whatever the stage (`claimed`, `cleared`): the part closes a window when she is not at its container or stash, and I did not find a staging that keeps her there. An estimate from the pack window's own cell (48 points): the loot grid 4 x 3 is 194 x 146 and with the title and the hint about 230 x 240 (6.0 percent at 1280 x 720); the stash panel with its five rows of stores about 340 x 260 (9.6 percent). **Side by side with the pack the pair is 642 px at 1280 x 720: 50 percent of the width, over the 45 percent line**; stacked it is 600 px, 83 percent of the height. So the loot window needs to take the place of the pack's weapon and melee strip (64 px) and the hint line while a container is open, or the cell must be 40 points at 1280 x 720 and 1024 x 640. Open, it takes the persistent budget with it (the threat rule closes it when an awake dead one comes within 8 tiles) and it should be placed by `Coach.best_rect` on the side of the window away from the avatar (today it is fixed at the left, over the house, and covers 20 percent of the centre zone).

**The probe.** `tools/ui_audit/run_audit.sh [OUTDIR] [--sizes ...] [--scenes probe|other|all|a,b] [--seeds each|1,3,5] [--skip-run]` runs the staged scenes (the default set is eight scenes of town 1 at 1280 x 720: a_hold, a_arrive, b_opening, c_clearing, d_day, e_night, f_dawn, g_build; **2 minutes 55 seconds** measured on this laptop with other Godots running, one at a time; the morning-card scene gives up after 15 s if the first night was held and there is no card to wait for), analyses them, prints the table of section 2 and the verdict of `check_budget.py`, and exits 1 when a line is over. `--sizes 1280x720,1024x640` or `--scenes all` for the full audit. Today it prints **44 of 69 lines over** for the probe set (the whole run, 4 windows: 279 of 510 over: 113 at 1280 x 720, 61 at 1280 x 800, 55 at 1024 x 640, 50 at 1920 x 1080); with `check_budget.py --minimal` the minimal HUD of the table is checked against the same budget: **18 of 316 over**: 6 are dead ones still hidden under boards that the minimal HUD keeps (the night's clock, weapon panel and crew cards: the ghost rule of section 6 makes them see-through, and the probe counts a part drawn at 0.4 opacity or less as not hiding), 6 are the 1920 x 1080 scaling (0.1 to 1.4 points over), 6 are the Build page and the radio panel at 1280 x 800 and 1024 x 640 (the page itself is over the window line there: 17.9 and 22.9 percent).

## 8. The minimal HUD, drawn from the same frames (what it would look like)

`tools/ui_audit/sheets.py ... --minimal` makes the world alone (`world.png`) and puts back only the parts the stage table keeps for that moment, cut down as the table says (the objective to its title line, the weapon panel to the name and the rounds, the clock to the hour, the alerts to one line, the crew cards to the top 75 percent); the banner is left out (the rule puts it in the top strip) and the dead and the avatar are the game's own. The sheets are two rows of two: as played | the audit's masks with the dead boxed; the minimal HUD | the numbers. They are in `docs/hud-audit-sheets/` (JPEG, named by window, number and state: `1280x720_03_opening_s3_walker_out` is the walker stepping out at the right edge beside its plate with the banner up, `1280x720_08_opening_s5_plus3s` the ring on it, `1024x640_21_opening_s3_walker_hidden` the walker hidden under the plate, `1024x640_22_arrival_first_second` and `1024x640_24_morning_card` the small window, `1280x720_12_night_clear_main_run_look1` and `1280x720_13_night_clear_second_run_look2` the east fence behind the right-hand column, `1280x800_19_night_crew_cards_hide` the north fence under the crew cards, `1280x720_02_arrival_first_second_s1` the first screen with the banner, `1280x720_15_morning_card`, `1280x720_16_build_page`) (and, 29 of them, in the scratchpad's `sheets3/`).

| State | UI % now | UI % minimal | Centre % now | Centre % minimal | Blind near her % now | minimal | Dead in view | Hidden over half now | minimal |
|---|---|---|---|---|---|---|---|---|---|
| (a) arrival, held, before the first key | 20.3 | 4.9 | 5.5 | 5.3 | 14.5 | 3.6 | 0 | 0 | 0 |
| (a) arrival, the first second after the key | 25.4 | 4.9 | 8.7 | 2.2 | 21.1 | 3.6 | 0 | 0 | 0 |
| (b) opening: the walker steps out | 23.6 | 4.9 | 7.0 | 2.7 | 10.5 | 1.5 | 3 | 0 | 0 |
| (b) opening: 3 s later | 21.7 | 6.9 | 12.6 | 10.6 | 8.5 | 4.2 | 3 | 0 | 0 |
| (c) in the house, dead near | 20.2 | 8.2 | 8.5 | 8.5 | 6.6 | 3.4 | 14 | 0 | 0 |
| (d) the claimed house by day, crew at work | 28.2 | 13.3 | 9.1 | 4.0 | 17.2 | 5.8 | 0 | 0 | 0 |
| (d) the first dusk, the bell | 23.5 | 13.5 | 4.3 | 4.3 | 8.9 | 5.4 | 0 | 0 | 0 |
| (e) first attack night, clear | 32.6 | 7.1 | 4.9 | 3.1 | 13.0 | 3.6 | 5 | 3 | 3 |
| (e) first attack night, storm | 19.1 | 6.9 | 2.4 | 2.2 | 6.0 | 2.8 | 3 | 2 | 1 |
| (f) the morning card | 40.9 | 18.0 | 27.1 | 7.9 | 26.9 | 11.0 | 1 | 0 | 0 |
| (g) the Build page open | 41.1 | 27.8 | 24.6 | 20.9 | 18.8 | 4.9 | 1 | 0 | 0 |
| (g) the radio panel open | 34.2 | 22.6 | 14.1 | 14.1 | 11.9 | 6.7 | 0 | 0 | 0 |

| State | UI % now | UI % minimal | Centre % now | Centre % minimal | Blind near her % now | minimal | Dead in view | Hidden over half now | minimal |
|---|---|---|---|---|---|---|---|---|---|
| (a) arrival, held, before the first key | 28.5 | 7.0 | 6.7 | 6.3 | 23.2 | 5.8 | 0 | 0 | 0 |
| (a) arrival, the first second after the key | 32.7 | 7.0 | 17.2 | 8.4 | 29.1 | 5.7 | 0 | 0 | 0 |
| (b) opening: the walker steps out | 32.3 | 6.2 | 12.4 | 3.8 | 19.5 | 3.1 | 2 | 1 | 0 |
| (b) opening: 3 s later | 29.7 | 8.5 | 13.3 | 10.9 | 15.6 | 6.6 | 2 | 0 | 0 |
| (c) in the house, dead near | 28.7 | 10.7 | 11.2 | 11.1 | 14.0 | 6.2 | 5 | 0 | 0 |
| (d) the claimed house by day, crew at work | 37.6 | 17.4 | 17.4 | 4.5 | 28.7 | 9.8 | 0 | 0 | 0 |
| (d) the first dusk, the bell | 31.8 | 17.8 | 5.8 | 5.0 | 18.2 | 9.9 | 0 | 0 | 0 |
| (e) first attack night, clear | 24.6 | 9.0 | 3.6 | 3.0 | 12.3 | 4.8 | 0 | 0 | 0 |
| (f) the morning card | 47.1 | 20.7 | 41.9 | 11.2 | 39.2 | 15.5 | 7 | 1 | 1 |
| (g) the Build page open | 52.4 | 37.1 | 45.1 | 35.2 | 29.7 | 9.0 | 1 | 0 | 0 |
| (g) the radio panel open | 43.9 | 30.3 | 27.0 | 26.7 | 19.1 | 10.4 | 0 | 0 | 0 |

(Hidden over half in the minimal HUD at the night: the crew cards and the clock that the minimal HUD still keeps, over dead at the top and top-right edge: the threat rule's last line, "a board over a dead one goes ghost", is what takes these to 0.)

## 9. What was not measured, and how it could be wrong

- **A frozen frame, a script's hands.** Ruth is a bot (the `capture_fight.gd` hands: aim, shoot, reload, walk toward the attacked fence, never nearer than 10 tiles), the walk of the opening is the route's own; a real player stops, panics, lingers. The dead of the night are the sim's dice (the second run had 28 in view where the first had 5): the two numbers to trust are the BLIND share and the list of WHAT hides, not the count of dead.
- **The box of a dead one** is the measured 1 x 1.5 tiles; the sprite is smaller (about 28 x 39 px at 1280 x 720), a brute's box is a guess (a third bigger). Roofs, the dim of an unopened room and the dead behind a wall are not considered; sleeping (dormant) dead are not counted, only `sim.zombies`.
- **The first walker** is one dead one in one place for each seed; the three towns are three samples. The state "held" and "after the first key" differ only in the banner and the paused pill.
- **Staged runs** begin the guide again at its last lesson (the lesson card in a `--stage=fourth` run); the snapshots of the day and the night have the guide put away, the tips on, and nothing else of a real run's history (no toasts that came before).
- **Not measured**: the web build in a browser (the itch iframe) and its canvas scaling; Settings' *Text size* Large and Larger (the boards grow, and the budget numbers must be checked at them); *Colour-blind markers*, *Reduce flashes*; tooltips (`--tooltip=`); the inventory's loot window and stash panel (the pack window is measured, the other two estimated, section 7); the minimap's dead dots; the real framerate.
- **Counting**: the mask of a board is the diff of the frame with and without it plus the box of its node; text over the bare world (the banner's letters, the cue's words) is the closing of its strokes, 4 px (HUD) or 2 (marks), so a floating word counts as its line. The faint tints (the avatar's rally disc, a room's veil) are 0.5 to 28 percent of the screen at night and are not counted (`faint` in `result.json`).

## 10. Hooks that the proposal would need (none was needed for the audit)

The audit and the probe needed **no change under `scripts/`**. To build the proposal, small additions (not made):
1. `threat_near()` (a function of the view, `scripts/ui/`): awake dead within 14 (leave at 18) tiles of the avatar, a shot in the last 3 s, or hurt; read by `hud.show_banner`, `hints.tick`, `alert_feed`, the town HUD's boards.
2. The dead's boxes into `Coach.best_rect`'s `keep_clear` (callers: `coach._kept_clear`, `dawn_tally.kept_clear`, `hints.gd` line 268), into `tutor_cues._beside` (its `blocks`, from `_hud_rects`) and into `HudFree.nearest_free`'s `others` (the edge arrows, the candidate pennants).
3. A ghost alpha of 0.3 on any board whose rectangle meets a dead one's box (the HUD already uses `modulate.a` for fades; `analyze.py` already treats a part at 0.4 or less as not hiding).
4. A banner and tip queue (one at a time, dropped when older than 5 s).
5. A reveal state for stores, clock, crew cards, toolbar, minimap, legend, from `scenario.stage()` and the people count (`stores_calm.revealed` and the `bar_plan` already exist).

## 11. Files

| File | What |
|---|---|
| `docs/hud-audit.md` | this document |
| `docs/hud-audit-sheets/` | the sheets of this document (JPEG) |
| `tools/capture_audit.gd` | the three-line file `--capture=audit` loads |
| `tools/ui_audit/driver.gd` | the hands, the snapshot (parts off in `frame_pre_draw`), the dead's screen boxes |
| `tools/ui_audit/tree_probe.gd` | the walk of the scene tree: every visible Control with its rectangle |
| `tools/ui_audit/scenes.py`, `run_scenes.py` | the staged scenes and the runner (one Godot at a time, killed by its own PID after a timeout; old results go to `~/.Trash`) |
| `tools/ui_audit/analyze.py` | the masks, the parts, the blind map, the dead, the sheet of one snapshot |
| `tools/ui_audit/report.py`, `sheets.py`, `dump_elements.py` | the tables, the sheets and the minimal HUD (`MINIMAL`), the list of parts |
| `tools/ui_audit/budget.json`, `check_budget.py`, `run_audit.sh` | the budget, its check and the probe |
| `tools/ui_audit/verify_flags.py` | the snapshot against the real flags |
| `tools/ui_audit/scenes.py` scene `h_inv_pack` | the inventory's backpack window (`--inv=open`), run with `run_scenes.py OUT --scenes inv` |
