# Last Bell: the real mix, recorded (PH4, 2026-10-09)

**Nobody who made the game can listen to it.** The sound pass (`docs/audio-mix.md`) was measured one sound at a time, and by a probe that plays them on the buses in a headless engine. This document is about the other half: **the whole game played for a minute, frame by frame, with its real mixed audio written to a file**, and measured. It is still not hearing: no number below says "it sounds good". What it does say is whether what reaches the speakers is what the mix table promised, whether anything clips, and where the mix is crowded.

## The method

Godot's movie writer renders every frame of a real window run at a fixed 30 fps and writes the AVI with the **Master bus's own audio** (16-bit, 48 kHz, stereo). A slow or busy machine changes nothing: the game's clock is the frame counter. On top of that, `tools/capture_tap.gd` (added by the flag `--capture=`, README flag table) puts an `AudioEffectCapture` on the Master bus before and after its hard limiter and on SFX, Steps, Voices, Ambience, Rain, Distant, Music and UI, and writes **the stem of every bus** and a per-frame log (`meta.csv`: game hour, Ruth's tile, the ground under her feet, the dead awake, her magazine, every bus's fader in dB) next to the movie. The drivers `capture_walk.gd`, `capture_fight.gd` and `capture_build.gd` play the hands of a player with the game's own inputs (W A S D and X as key events, the right button and the trigger as the game's variables, R and F and E as key events): they aim at the nearest of the dead that is in a clear line, fire, reload, swing the butt, walk through the house and the street by the people's grid, order the front fence and build it. Nothing in the game's rules or sound code is touched by any of it.

One fact to keep in mind: **a capture on a bus is taken before that bus's own fader**. The SFX stem is exactly 2.818 times the Voices stem (the Voices trim, +9.0 dB), so `tools/audio_capture.py` applies the faders recorded in `meta.csv` (the sliders, the fixed trims, the Rain bus's roof, the Ambience bus's duck) before it measures, and every number below is "as it reaches the Master", the same place the mix table measures. (The first pass of the analysis did not, and found Steps 2.5 LU and Voices 9 LU under the table: a false alarm that is worth remembering, because the check is just as easy to get wrong the next time.)

### The commands (one Godot at a time)

```bash
# once in a new worktree: the import (the movie shows squares without it)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import

# one clip: record, split the AVI, measure.  tools/capture_clip.sh OUTDIR NAME FRAMES  <game flags>
tools/capture_clip.sh /tmp/cap a_walk 2000 --town=1 --stage=claimed --hour=8 --weather=clear --stock=scrap:30,ammo:24,food:12,water:18,meds:3 --capture=walk
# which is, inside:
Godot --path . --write-movie /tmp/cap/raw/a_walk.avi --fixed-fps 30 --quit-after 2000 -- --shot=/tmp/cap/raw/never.png --frames=99999999 \
      --winpx=1920x1080 --os-scale=1 --hide-lesson --no-banner <flags> --capture-out=/tmp/cap/raw/a_walk
python3 tools/avi_extract.py /tmp/cap/raw/a_walk.avi /tmp/cap/raw/a_walk_x --luma=/tmp/cap/raw/a_walk_luma.csv
python3 tools/audio_capture.py /tmp/cap/raw/a_walk --wav /tmp/cap/raw/a_walk_x/audio.wav --luma /tmp/cap/raw/a_walk_luma.csv --name a_walk --json /tmp/cap/a_walk.json

# tables for this document, and the files for a person to open
python3 tools/audio_capture_tables.py before=/tmp/cap_before after=/tmp/cap
swiftc -O tools/make_mp4.swift -o /tmp/make_mp4
python3 tools/capture_publish.py /tmp/cap /tmp/owner /tmp/make_mp4
```

Why `--shot=... --frames=99999999`: a run with `--shot=` keeps its settings and tips in a file of its own (`user://prefs_shot.cfg`), never writes the player's autosave and shows no tips, and the huge frame count means that the shot is never taken. (Without it, a dawn in a movie run would overwrite the owner's autosave.) The first 4.5 to 5 seconds of every movie are the loading card (the tap waits for the game to be up, then 30 frames; `meta.csv` and the stems begin there, the files for the owner are cut there). The AVI's picture is 1920 x 1080 whatever `--winpx` says; the MJPEG AVI is 100 to 150 MB a minute, only an intermediate.

The clips (flags after `--town=1`, seed 1, so that the same house and street come back; `--stock=` is the clean counter of `--stock=scrap:30,ammo:24,food:12,water:18,meds:3` unless it says otherwise):

| Clip | Length | What the hands do | Flags |
|---|---|---|---|
| a, the morning walk | 62 s | Ruth leaves the hall of the claimed start house: tile, wood (living room), tile (kitchen), carpet (bedroom), the front door, the lawn, the sidewalk, the road at a run and at a walk, twice round; she stops and shoots a straggler when one is in a clear line | `--stage=claimed --hour=8 --weather=clear --capture=walk` |
| b, the day fight at the base | 60 s | the base with its crew (`--stage=fourth --slots=built`), Ruth at the gate with the pump gun: five waves of the dead from the street (walkers and a mix with runners and a brute), two of them standing at her feet for the butt of the gun | `--stage=fourth --slots=built --hour=11 --weather=clear --weapon=shotgun --avatar-at=149.5,91.5 --stock=...ammo:90 --capture=fight` |
| c, a storm at night at the base | 60 s | 16 s in the yard in the rain, in at the door and 12 s under the roof, out again; nobody comes: the rain, the thunder, the lightning and the crew's patrol | `--stage=night --slots=built --weather=storm --hour=21 --avatar-at=149.5,91.5 --no-alerts --capture=walk --capture-route=storm` |
| d, the night attack | 60 s | the first attack night 135 s after the dusk bell (`--advance=135`): the dead at a fence (a different one in each take, so Ruth walks to it, out of the gate if need be, and fights there), the crew patrolling and shooting, the same hands as in b | `--stage=night --slots=built --weather=clear --advance=135 --weapon=shotgun --avatar-at=149.5,91.5 --capture=fight --capture-waves=0` |
| e1, building by hand | 50 s | Ruth orders the front fence, walks to its first section and presses E there: the hammer, the section's bell | `--stage=claimed --hour=9 --capture=build` |
| e2, the morning card | 35 s | the dawn after a night that was not held: the tally card ("The night is over") | `--stage=night --slots=damaged --moment=dawn --capture=tap` |
| h, the worst case | 60 s | d, in a storm: the guns, the dead and the crew under the loudest rain | d with `--weather=storm` |
| g, the calibration | 25 s | a walker's groan played from 3, 3, 8, 14, 3 and 8 tiles east of the camera (`--capture-calib=groan`) | `--stage=claimed --hour=11 --capture=tap --capture-calib=groan` |

**How the numbers are made** (`tools/audio_capture.py`): loudness is ITU-R BS.1770-4 (K-weighted, 400 ms blocks every 100 ms, the integrated figure gated at -70 LUFS and 10 LU under the rest), the same filters as `tools/audio_measure.py`; "M-max" is the loudest 400 ms, as in the mix table. A gun is a burst of the SFX bus *alone* (SFX less Steps and Voices, which are sent to it) whose loudest 400 ms is over -15 LUFS (the pump gun is -12.7 to -13.9; a far shot of the crew is under it and counts with the blows). Ruth's footsteps are the loudest 400 ms of the Steps bus while the log says she walked (or ran) over that ground the whole time, as `tools/mix_probe.gd` measures them. Thunder is a rise of the Rain bus's 30 to 250 Hz band of 6 dB over its median for 0.3 s; lightning is a spike of the picture's brightness (`avi_extract.py --luma`). The stems line up with the movie's own audio to -73 to -81 dB (they are the same samples): the files for the owner are what was measured.

## What the capture says (the short version)

1. **The mix is the one the mix table promised.** Played for a minute at a time in a real window, with the crew shooting and the dead groaning, the numbers land on the table's: the pump gun (SFX alone) **-13.3 LUFS median** (table -12.7 to -13.9); Ruth walking **-28.2 to -31.4** on pavement, tile, wood, grass and carpet (table -28.2 to -30.5) and running **-22.7** (table -21.4 to -23.9); a groan played from 3 / 8 / 14 tiles **-14.4 to -16.0 / -18.3 to -18.6 / -22.4** (table -15.5 to -17.0 / -18.6 to -19.9 / -22.0 to -22.7); the storm's rain outdoors **-20.4** at its loudest (table -20.4), under a roof **-32.7** median (table -31.8); a near thunder **-13.4** (table -13.4). Nothing is 3 LU or more away from the table except what is explained below. So the two new buses and the Rain bus are doing what they were built to do.
2. **Nothing clips.** In all seven clips (about 6.5 minutes of the real game, twice over) the 16-bit file has **0 samples at full scale**, its peak never above **-0.50 dBFS** (the limiter's ceiling). The limiter does work in a fight, because the crew's shots and Ruth's stack: before the limiter the Master peaked at **-0.1 to +2.2 dBFS** in the fights (+3.0 in an earlier take of the night attack), over the ceiling for **7 to 14 episodes and 0.1 to 0.4 s of every 60** in the day fight, the night attack and the storm attack, **up to 49 episodes and 1.6 s (2.6 percent) in the earlier take of the night attack**, and it took off at most **2.7 dB** (3.5 dB in that take) for a few milliseconds each. The docs/audio-mix.md worst case ("at most 0.9 to 1.6 dB") was one gun; with the crew shooting at the same moment it is **up to 3.5 dB**. Not a fault (that is a limiter's job, it never clipped), but it means that in a big fight the loudest shots are shaved and the whole mix dips for a moment: the guns' real peak is flatter than their files'.
3. **Gunfire and voices over the rain: inside the owner's 3 to 8 LU, at the top of it.** In the loudest weather (the storm, outdoors, **-20.4**): the pump gun **-12.3 to -12.9** in the two takes with enough shots (+7.5 to +8.1; **-14.3** in the take with four shots, +6.1), thunder near **-13.4 to -13.7** (+7.0), the loudest voice heard in a storm take **-18.3** (+2.1: a growl or the screech, the table's weakest) and the day fight's loudest, **-14.7**, would be +5.7 over the same rain; a groan at the fences (11 tiles) **-22 or less** (the storm hides it, as the table says it does). The footsteps (-28 to -31) and the far dead are under the storm, by design.
4. **One real outlier, now tuned: the radio call's ring.** A call that waits for an answer (the cards "A brute at the front gate", "A plated brute is tearing at the west fence") rings `ui_radio_call` at 0.9: **-11.8 LUFS at the Master, as loud as the pump gun** (peak -9.8 dBFS), 4 LU over a groan at 3 tiles and over the dusk bell's first toll (-12.6): a menu sound louder than the fight it comes in. It was in none of the mix table's rows. **Now 0.55 (`soundscape.gd`, one number): -16.0** in the next recording (UI M-max -11.8 to -16.0 in the day fight and the night attack), 4 LU under the gun and level with the confirm chime and a groan at 3 tiles.
5. **What I did not change, and why.** (a) The night music is the loudest sustained layer of the mix: -16.8 to -18.8 integrated in the storm and the night attack, against -22.8 by day, and its loudest 400 ms (-12.6 to -13.9) is as loud as a gun. Before a shot the median margin of the gun over the music was **8.7 LU by day, 4.8 to 6.5 LU in the night attacks, and 10 percent of the 92 shots in the (after) clips were under 3 LU over it** (the lowest 0.8 LU). That is the "music masking the guns" case, but the rule that was given to the mix is for the rain, it is met, and the music is as the table described (stems -7 to -9 LU under the gun *each*, the mood is their sum); nothing was clipped or inaudible. It is the first knob to try if the first listening says the night is crowded (`Buses.TRIM_DB["Music"]`, or the night stems in `music.gd`). (b) The footsteps in a storm (-29) are 9 LU under the rain and the dead at the fences in a storm (-22 and less) at or under it: a design choice of the table ("a storm hides them"). (c) Thunder: the ones that come 2.3 s or more after their flash (-18.5 to -22.3) are no louder than the rain's own loudness (-20.4) in K-weighted LUFS, but they rise **+21 to +28 dB in their own band (30 to 250 Hz)** over the bed's, which has next to nothing there, so they are a rumble under a hiss, not a swell lost in it; I left them. The near ones (-13.1 to -13.9, up to 1.3 s after the flash; -14.6 to -16.0 at 1.6 s) are +5 to +7 over the rain. Lightning and thunder pair up as the rules say: in the four storm clips the picture has **12 bright flashes (2.1 to 2.8 times the frame before) and the thunder came 0.1 to 3.0 s after each**; the four dim ones (1.2 times, the "sheet" flash) have none.

## The numbers

LUFS are at the Master (after the faders), loudest-400-ms ("M-max") or integrated over the clip as the column says. "Before" is the game as it was at 236bb1e; "after" is with the radio call at 0.55. The clips are *takes*: the sim's own dice (which fence the dead choose, how many shots the crew fires, which thunder comes) are not the same in two runs, so the two tables differ by more than the one change; the gun, step, groan, rain and thunder rows are the ones to compare with the table, and the UI row is the one that changed.

### The master of each clip, before the tune

| Clip | Length (s) | Peak of the 16-bit file (dBFS) | Samples at full scale | Integrated (LUFS) | M-max | Short-term max | Pre-limiter peak (dBFS) | Over the -0.5 ceiling (samples) | Limiter working (ms, episodes) | Most it took off (dB) |
|---|---|---|---|---|---|---|---|---|---|---|
| a walk | 62 | -2.10 | 0 | -21.2 | -13.4 | -17.2 | -2.10 | 0 | 0 ms, 0 | 0.0 |
| b day fight | 60 | -0.50 | 0 | -15.0 | -9.2 | -12.2 | 2.24 | 266 | 380 ms, 14 | 2.7 |
| c storm | 60 | -0.50 | 0 | -16.2 | -11.4 | -15.0 | 1.43 | 84 | 60 ms, 1 | 1.9 |
| d night attack | 60 | -0.50 | 0 | -15.7 | -10.5 | -13.5 | 0.64 | 22 | 120 ms, 6 | 1.1 |
| e1 build | 50 | -1.31 | 0 | -20.1 | -12.2 | -17.0 | -1.31 | 0 | 0 ms, 0 | 0.0 |
| e2 dawn card | 35 | -4.27 | 0 | -18.4 | -12.0 | -13.6 | -4.27 | 0 | 0 ms, 0 | 0.0 |
| h storm attack | 60 | -0.50 | 0 | -14.5 | -10.4 | -12.5 | 1.28 | 188 | 360 ms, 11 | 1.8 |

(An earlier take of the night attack, in which Ruth stood at the gate and the dead were at the front fence: integrated -12.7, **pre-limiter peak +3.0 dBFS, 607 samples over full scale before the limiter, working 1.56 s in 49 episodes, up to 3.5 dB**; the file's peak -0.50, 0 samples at full scale.)

### The master of each clip, after the tune

| Clip | Length (s) | Peak of the 16-bit file (dBFS) | Samples at full scale | Integrated (LUFS) | M-max | Short-term max | Pre-limiter peak (dBFS) | Over the -0.5 ceiling (samples) | Limiter working (ms, episodes) | Most it took off (dB) |
|---|---|---|---|---|---|---|---|---|---|---|
| a walk | 62 | -0.50 | 0 | -20.9 | -11.9 | -16.1 | 0.02 | 4 | 60 ms, 3 | 0.5 |
| b day fight | 60 | -0.50 | 0 | -16.4 | -10.2 | -14.5 | 2.24 | 69 | 200 ms, 8 | 2.7 |
| c storm | 60 | -1.06 | 0 | -16.1 | -12.3 | -15.2 | -1.06 | 0 | 0 ms, 0 | 0.0 |
| d night attack | 60 | -0.50 | 0 | -14.7 | -10.4 | -13.0 | 1.42 | 115 | 320 ms, 11 | 1.9 |
| e1 build | 50 | -0.62 | 0 | -19.8 | -12.1 | -17.2 | -0.62 | 0 | 20 ms, 1 | 0.0 |
| e2 dawn card | 35 | -6.61 | 0 | -22.8 | -20.2 | -22.0 | -6.61 | 0 | 0 ms, 0 | 0.0 |
| h storm attack | 60 | -0.50 | 0 | -13.8 | -10.6 | -12.8 | -0.07 | 22 | 140 ms, 7 | 0.4 |

(The file's peak of -0.50 dBFS is the limiter's ceiling: it held. The e2 clip's M-max is 8 LU lower after than before because the music is a different mood in that second: a take, not a change.)

### Each bus as it reaches the Master, after (integrated LUFS over the clip / loudest 400 ms)

| Bus | a walk | b day fight | c storm | d night attack | e1 build | e2 dawn card | h storm attack |
|---|---|---|---|---|---|---|---|
| SFX (all that goes through it) | -25.3 / -12.0 | -16.4 / -10.1 | -24.5 / -12.9 | -15.9 / -10.5 | -23.9 / -12.4 | -29.0 / -25.6 | -17.5 / -14.2 |
| Steps | -29.6 / -22.7 | -40.5 / -32.9 | -33.9 / -29.6 | -33.6 / -28.9 | -32.3 / -30.6 | -41.1 / -35.5 | -32.4 / -29.4 |
| Voices | -22.0 / -18.1 | -20.9 / -14.7 | - | -22.6 / -18.2 | -20.6 / -17.3 | -45.7 / -41.7 | -28.3 / -22.3 |
| Ambience (with Rain and Distant) | -30.5 / -27.7 | -30.0 / -24.2 | -21.3 / -13.2 | -32.3 / -29.3 | -30.5 / -26.0 | -30.6 / -27.5 | -21.3 / -13.5 |
| Rain | - | - | -22.4 / -13.4 | - | - | - | -22.6 / -13.7 |
| Distant | -35.7 / -30.7 | -36.3 / -31.9 | -35.9 / -29.5 | -38.1 / -33.2 | -33.6 / -29.1 | -34.4 / -30.9 | -37.2 / -31.2 |
| Music | -22.8 / -18.5 | -22.7 / -19.5 | -17.7 / -13.5 | -18.8 / -13.9 | -21.7 / -18.5 | -24.5 / -21.2 | -16.8 / -12.6 |
| UI | -57.2 / -57.2 | **-18.5 / -16.0** (was -14.2 / -11.8) | - | **-18.5 / -16.0** (was -14.2 / -11.8) | -28.1 / -24.6 | -33.9 / -32.9 | - |

The Music bus is the loudest layer in every clip but the day fight (where the SFX bus is); the morning card (e2) makes next to no sound of its own (UI -33.9).

### Against the mix table (after; the "before" rows are within 1 LU of these except the UI)

| What | Measured in the real mix (LUFS at the Master) | Mix table (docs/audio-mix.md) |
|---|---|---|
| Pump gun (bursts of the SFX bus alone over -15 LUFS), day fight | 39 bursts, median **-13.3**, quietest -14.4, loudest -9.9 (two guns at once) | -13 (-12.7 to -13.9) |
| the same, night attack / walk / storm / build | median -13.4 (39 bursts) / -13.4 / -12.9 / -13.8 | |
| Ruth walking, pavement / tile / wood / grass / carpet (loudest 400 ms) | **-28.2 / -29.4 / -29.2 / -30.0 / -31.4** | -28.2 / -28.9 / (wood not measured) / -29.6 / -30.5 |
| Ruth running, pavement | **-22.7** | -21.4 to -23.9 |
| Groan played from 3 tiles (three times) | **-16.0, -14.9, -14.4** | -15.5 to -17.0 |
| from 8 tiles / from 14 tiles | **-18.6, -18.3 / -22.4** | -18.6 to -19.9 / -22.0 to -22.7 |
| Voices in the day fight, the loudest (wind-up growls, Ruth's pain, a few tiles) | **-14.7** (median -19.1) | growl at 2.5 tiles -15.2 to -18.2; pain -17.2 to -17.8 |
| Rain bed outdoors, storm, loudest 400 ms with no thunder in it | **-20.4** (median -22.6), twice | -20.4 |
| Rain bed under a roof, storm (median) | **-32.7** | -31.8 |
| Thunder (loudest 400 ms) | near **-13.4, -13.7**; a little farther -14.6 to -16.0 (before); mid **-18.5 to -22.3** (no far one in the 8 strikes) | near -13.4, mid -21.4, far -27.8 |
| Radio call's ring (UI) | before **-11.8**, after **-16.0** | not in the table |

### The picture of the storm

Sixteen flashes were found in the picture of the four storm clips (a spike of the screen's brightness): twelve bright ones (2.1 to 2.8 times the frame before) and four dim ones (1.2 times). The thunder came **0.1 to 3.0 s** after each bright one (0.1, 1.0, 1.0, 1.3, 1.3, 1.6, 1.7, 1.7, 2.3, 2.4, 2.6, 3.0 s: the rules' 1 to 3 s, and the one in eight that is near, 0.05 to 0.3 s); the dim ones are the "sheet" flash, which has none.

## Where the numbers could be wrong

- **Not hearing.** The K-weighted loudness of a rumble below 100 Hz is small and the ear's is smaller still at a low level; a number cannot say that a far thunder is felt, only that it is not covered.
- **Takes, not a population.** Each clip is one minute of one seed (town 1), recorded twice. The gun and groan rows have 30 to 40 samples; the thunder rows 3 to 4 a clip.
- **Guns are told from the blows by loudness** (over -15 LUFS in the SFX bus alone); a far shot of the crew (-16) is counted with the blows. The count of "guns" is therefore the near shots.
- **Ruth is a script.** The hands aim at the nearest dead in a clear line and never miss a beat; the crew and the dead are the sim's. A player pauses, panics and stands in the house, so the real limiter and the real masking are likely a little less busy than here.
- **A movie run is not the web build.** The browser's audio path (the Web Audio probe of STATUS.md section 4) is still unmeasured; this is the desktop engine's mixer.

## What the owner should listen for first

The files are in the scratchpad's `ph4-capture/for-owner/` (below). Open the `.mp4` (picture and sound) or the `.wav` (the sound only, exactly what the game's Master played: 48 kHz, 16-bit, stereo).

1. **`lastbell_d_night`** (60 s): the first attack night from the gate. Are the guns the loudest thing without hurting, and can you still hear the dead groan and Ruth's breath and the crew's steps under them? Is the music in the way (it is -18.8 LUFS here, and its loudest moment is as loud as a gun)? Watch for the limiter: it takes up to 2 dB for a few milliseconds when two guns overlap; if the shots sound "flat" or the music "pumps" at a volley, that is it.
2. **`lastbell_h_storm_attack`** (60 s): the same in a storm. Is the rain a wall or a bed? Do the guns come through (+7.5 to +8 over it)? Do you hear a thunder after each flash, and is the mid one (-21) a rumble or lost?
3. **`lastbell_c_storm`** (60 s): the storm alone, 16 s in the open, 12 s under a roof, then out again. The roof should take 10 to 12 LU off the rain (-20 to -32) and 5 to 6 off a thunder; the muffle is a low-pass closing from 20 kHz to 1.3 kHz. Listen for the moment she steps in at the door: does the rain close like a door, or fade like a wall?
4. **`lastbell_a_walk`** (62 s): Ruth through the house (tile, wood, tile, carpet), over the lawn and the sidewalk, the road at a run and at a walk, twice. Each ground should sound different; the run should be about 6 LU louder than the walk. This is the quietest clip (-21 LUFS) and the best one to hear the footsteps and the straggler's groan against the music and the wind. Is the music too loud for the steps?
5. **`lastbell_b_fight`** (60 s): the day fight at the gate: the pump gun, the reload and the rack (R), five waves of walkers, runners and a brute, and two of the dead at her feet that she kills with the butt of the gun (F): the swoosh, the thud and the wet kill, the groans, the growls before each bite, Ruth's grunt when bitten. The first listening should say whether the melee reads as one blow.
6. **`lastbell_e1_build`** (50 s): the hammer (every 0.6 s while her hands work, at -30 LUFS a blow, 8 LU under the music, with a peak as high as the music's) and the small bell when a section is done; **`lastbell_e2_dawn`** (35 s): the morning card "The night is over" with almost no sound of its own.
7. **The radio call's ring**, in the fights (`b` at about 14 s, 20 s and 45 s into the clip, `d` at 11 s and 54 s: the times change from take to take): it is 4 LU quieter than it was and may now be too soft to notice in the middle of a volley; that is the number to move (`soundscape.gd`, `on_event` "call_raised", `ui("ui_radio_call", 0.55)`: 0.7 is -2 dB).

What plays where: the `.mp4` files are H.264 and AAC, 1280 x 720, 15 to 27 MB each: QuickTime, Safari, Chrome, VLC, the phone's player and any messenger. The `.wav` files play anywhere (QuickTime, VLC, a DAW). The raw movie-writer AVIs (MJPEG with PCM sound, 100 to 150 MB a minute) are the intermediates and were not kept for sending: QuickTime does not play them.

## The stills and the GIF

Six clean stills at 1920 x 1080 and a 4 s GIF (12 fps, 640 px wide, 4.9 MB) for the itch page are in `ph4-capture/stills/` and are listed with a caption and the flags that made each in `docs/itch-page-draft.md`. The staging artifacts of the old ones (the 9741 scrap, "Step 5 of 5", a banner stuck over the picture, the stack of "Seven things built" and a radio call, the PAUSED pill) are each a flag now: `--stock`, `--hide-lesson`, `--no-banner`, `--no-alerts` (README flag table). The GIF is cut from the storm clip (`c`, a recording with `--no-alerts`), around the first flash.

## Re-running

The commands above, `tools/capture_clip.sh` and `tools/capture_publish.py`; about 70 to 90 s a clip on this machine (the movie writer runs at 90 to 120 percent of real time). One Godot at a time. The scenes were taken with the base house of town 1 (`houses.house(46)`, the hall at 149.5, 87.5): another seed has another house, but the walk finds its own rooms and door, and the night's drivers go to whichever fence the dead pick (they choose a different one each take).
