# Thirty Bells: the audio mix (the SOUND pass, 2026-10-07)

**Nobody who made this could listen to it.** Every number below was measured, not heard: the loudness of each file with `tools/audio_measure.py`, and what really reaches the speakers with `tools/mix_probe.gd` (the game's own sound nodes play on the real buses, on a generated town, with Ruth and the dead as the rules have them; a capture effect after the Master's limiter is measured). "It sounds good" is **not** claimed anywhere in this document. What the owner should listen for first is at the end.

## How to read the numbers

- **LUFS / LU.** The loudness of the *loudest 400 ms* (momentary loudness, K-weighted as in ITU-R BS.1770 / EBU R128), written **M-max**. 1 LU is 1 dB; "A is 6 LU under B" means A's M-max is 6 less than B's. A sound shorter than 400 ms is measured as heard in that window, so a click and a bed are on one scale.
- **File** numbers (`tools/audio_measure.py`) are of a mono file, 3 LU lower than the same file played in the middle of the stereo master. **Master** numbers (`tools/mix_probe.gd`) are what the stereo output measures, after the buses and the limiter. Peaks are dBFS.
- **The reference** is the pump gun (Ruth's) in the open: **-12.7 to -13.2 LUFS** at the Master, peak -3.4 to -4.0 dBFS.
- Re-measure with `Godot --headless --path . --script res://tools/mix_probe.gd -- --out=/tmp/mix.txt` (about 6 minutes, one Godot at a time; `--only=gun,steps,...` for some). Files: `python3 tools/audio_measure.py assets/audio/<file>.wav`.

## The buses

```
Master (hard limiter, ceiling -0.5 dBFS)
 |- SFX      slider "Effects"      trim   0 dB   guns, blows, reload, doors, gate, bells, thud, bite ...
 |   |- Steps    (new)   fixed trim +2.5 dB   footsteps of Ruth, the crew and the dead
 |   '- Voices   (new)   fixed trim +9.0 dB   groans, growls, hiss, screech, Ruth's pain and breath (the brute's roar stays on SFX: its file is -11.7 LUFS)
 |- UI       slider "Interface"    trim   0 dB
 |- Ambience slider "Ambience"     trim   0 dB   ducks up to 2.5 dB under the SFX bus's peak (new)
 |   |- Distant  low-pass 3200 Hz + reverb      a crow, a dog, a far shot
 |   '- Rain     low-pass 20.5 kHz open, 1.3 kHz under a roof, trim +0.5 dB, -1.5 dB under a roof
 '- Music    slider "Music"        trim   0 dB   ducks up to 3 dB under the SFX bus's peak (as before)
```

All of them are in `default_bus_layout.tres` (the layout file, **not** `add_bus` at run time: see STATUS.md section 4, the web build was once silent because of that); `Buses.ensure()` is only the fallback. Steps and Voices are sent to SFX, so the Effects slider, the HUD's sound switch and the music's sidechain still see them. The trims are `Buses.TRIM_DB` (and `RAIN_TRIM_DB`), applied by `Buses.apply()` on top of the player's slider (a slider at 0 mutes outright, as before).

(The layout file holds the same trims as the code, 2.5 and 9.0 dB, so that the buses are right before any script runs.) Why Voices is +9 dB: a positional voice (an `AudioStreamPlayer2D`) loses 3 dB at the middle of the pan, its file is -21 LUFS mono, and its distance fall-off is `(1 - d/reach)^2`; at 3 tiles that left a groan at -27 LUFS at the Master, 15 LU under the shot and **under the storm's rain** (-21). The bus (and +1 dB on the groan) lifts it to -16.

## The MIX TABLE (what reaches the speakers; "ref" = distance from the camera)

| Category | Sound (what the table measures) | Target at Master (LUFS, M-max) | **Measured** | Bus (trim) | Gain on the player (dB) | LU vs the gun |
|---|---|---|---|---|---|---|
| **Gunfire** | pump gun in the open (3 files) | -13 | **-12.7, -12.8, -13.2** (peak -3.4 to -4.0) | SFX (0) | -1.0 | 0 (ref) |
| | pump gun in a room (3 files; tail dense, 0.5 s) | -13 | **-12.9, -13.4, -13.9** (peak -2.6 to -2.7) | SFX (0) | +0.5 | -0.5 |
| | the old shot (school, other guns use their own) | | -8.1 to -9.0 | SFX | | +4 |
| **Melee** | swoosh (blow in the air) | -20 | **-20.7** | SFX (0) | file | -8 |
| | thud (a blow that lands) | -20 | **-20.3** | SFX (0) | file | -7.5 |
| | wet kill (laid on the thud) | -19 | **-19.6** (0.8 play level) | SFX (0) | file | -7 |
| | a killing blow: thud + wet kill together | -17 | **-16.8** (peak -3.4) | SFX (0) | | -4 |
| **Reload** | shell into the tube | -23 | **-23.2** | SFX (0) | file | -10 |
| | pump rack (chk-CLACK) | -20 | **-19.6** | SFX (0) | file | -7 |
| | empty click | -23 | **-23.4** | SFX (0) | file | -10 |
| **Voices** (near) | groan at 3 tiles (16 files) | -16 | **-15.5 to -17.0** (peak -5.0 to -6.4) | Voices (+9) | +1.0 (+ jitter -2..0) | -3 |
| | groan at 8 tiles / 14 tiles | | **-18.6 to -19.9 / -22.0 to -22.7** | Voices | | -6 / -10 |
| | groan at 20 tiles (the dark far files) / 30 tiles | | **-35.3 to -35.9 / -48.8 to -49.9** | Voices | -1.0 | |
| | straggler of the streets at 6 tiles | | **-27.5** | Voices | -10 more than a near groan | |
| | wind-up growl at 2.5 tiles (walker / brute) | -17 | **-16.8 / -15.2** | Voices | -0.5 / -1.0 | -4 / -2.5 |
| | runner hiss / screech at 2.5 tiles | -17 | **-17.2 / -18.2** | Voices | +3.0 / -2.0 | -4 / -5 |
| | brute roar at 6 / 20 tiles | -15 | **-15.1 / -19.1** | SFX (0) | +1.0 | -2 |
| | Ruth's pain (a bite) | -18 | **-17.2 to -17.8** | Voices | -2.0 | -4.5 |
| | Ruth's breath, tank at 8 percent / 25 percent | -27 | **-27.5 / -31.3** | Voices | -6.0 (less with more breath) | -14 / -18 |
| **Footsteps** | Ruth walking (grass, pavement, tile, carpet) | -29 | **-29.6, -28.2, -28.9, -30.5** | Steps (+2.5) | -1.0 | -16 |
| | Ruth running | -22 | **-22.5, -21.4, -21.6, -23.9** (+6.5 to +7.5 over a walk) | Steps | +0.5 | -9 |
| | the crew (a walker 4 tiles away) | -38 | not played in the probe (the solo start has no crew): about -39 by arithmetic from Ruth's walk (the same files, 4 dB lower play level, the fall-off of -6 dB at 4 tiles) | Steps | -5.0 | |
| | the dead's shuffle at about 4 tiles (walker / limper / brute) | -38 | **-40.8 / -38.8 / -38.1** | Steps | 0.0 (+3.5 for a brute) | -26 |
| **Rain** | drizzle / steady / storm, outdoors | | **-31.5 / -25.2 / -20.4** | Rain (+0.5) | bed 0.57 / 1.14 / 1.9 x 0.9 | -19 / -12 / -7.5 |
| | the same under a roof | | **-41.5 / -35.4 / -31.8** (10 to 10.5 LU under) | Rain (-1.5, 1.3 kHz) | | |
| | thunder near / mid (far 0.5) / far (far 1.0) | -14 / -21 / -28 | **-13.4 / -21.4 / -27.8** (under a roof: -19.9 / -26.4) | Rain | -2 .. -8 | |
| **Ambience** | wind, day (level 0.8) | | **-28.6** | Ambience (0) | | -16 |
| | night bed (0.85) | | **-29.8** | Ambience | | |
| | the horde's moan at full (1.0) | | **-22.1** (it was -18.1 before the -4 dB trim) | Ambience | -4.0 | |
| **Music** | the stems at full (outdoors / indoors / night / fortress) | | **-19.9 / -22.4 / -20.6 / -19.4** (one stem; the mood is the sum) | Music (0) | | -7 to -9 |
| **UI** | click / confirm / notify (0.6) / chime | | **-27.3 / -15.1 / -20.5 / -15.5** | UI (0) | | |
| | the dusk bell, first toll (not changed) | | **-12.6** (it was -10.9 on another toll: a random one of three) | SFX | | 0 |

The moan row: the bed was -18.1 LUFS before the trim, about as loud as a groan three tiles away, which is the wrong way round for a bed; `Foley.LEVEL_DB["moan"]` takes 4 dB off (`sound.gd set_ambience`).

### The rule the owner gave, checked

"Gunfire and voices on top of rain by 3 to 8 LU": in the **loudest weather (a storm, outdoors, -20.4 LUFS)**

| | LUFS | over the storm's rain |
|---|---|---|
| the pump gun (six takes, open and room) | -12.7 to -13.9 | **+7.3** (6.5 to 7.7) |
| a groan at 3 tiles | -15.5 to -17.0 | **+4.4** (3.4 to 4.9) |
| a wind-up growl, hiss, screech at 2.5 tiles | -15.2 to -18.2 | **+2.2 to +5.2** (the screech, one in three runners' bites, is the +2.2) |
| Ruth's pain | -17.2 to -17.8 | **+2.6 to +3.2** |
| a brute's roar at 6 tiles | -15.1 | **+5.3** |
| thunder, near | -13.4 | +7.0 |

A steady rain is 12 LU under the gun, a drizzle 19 LU: lighter weather is quieter still. **Outside the band, by design:** a far groan (at 14 tiles it is -23, under the storm), the dead's shuffle, the footsteps (-28 to -30 walking) and Ruth's breath: a storm hides them, which is what a storm does. Ruth's pain and the screech are the two a little under 3 LU over; they are one number each (`ruth_pain`, `screech`).

### Ducking ("a little under gunfire")

- Music: unchanged, the SFX bus's peak above -12 dBFS dips the stems 0.33 dB per dB, at most 3 dB, taken in 40 ms and given back over half a second (`music.gd _update_duck`).
- **Ambience (new):** the same from `Buses.ambience_duck_for` (floor -12 dBFS, 0.33 dB per dB, **at most 2.5 dB**, 40 ms attack, 0.6 s release), run every frame by the soundscape (`_duck_tick`). The rain and the far sounds are under Ambience, so they dip too. Measured: a shot dips the Ambience bus **to -2.25 dB** and it is back to -0.03 dB 1.2 s later. The dip follows the SFX bus's peak, and Steps and Voices are inside it, so the loud ones among them dip the ambience too (and the music, whose sidechain is the same): measured on the Ambience bus, a groan one tile away **-1.1 dB**, a brute's growl one tile away **-2.2 dB**, the dusk bell's first toll -1.3 dB, a thud with its wet kill -0.4 dB, Ruth's running step on tile -0.1 dB (a click a few samples tall: the peak meter barely sees it). So a voice at your elbow makes the music and the rain give way by a decibel or two, which is a choice the owner may not want (set `AMB_DUCK_FLOOR_DB` higher, or the Music's `SFX_FLOOR_DB`).

### Clipping and the limiter (ceiling -0.5 dBFS)

Every new file peaks at -3.2 dBFS or lower (`tests/test_audio_assets.gd` wants -3.0). In the engine, played at their game levels, no single category reaches the ceiling: the loudest are a killing blow (thud + wet kill, peak -3.4), an indoor shot (-2.6) and a tile run step (-3.4). **The worst case** (a storm, a music stem, Ruth running with an empty tank, a shot every 0.45 s, thirty of the dead at their bites for 8 s): the Master peaks at **-0.5 dBFS with the limiter on** (the ceiling: nothing goes through it) and **+0.4 dBFS with the limiter switched off** (5 samples over full scale in 6 s), so the limiter takes at most 0.9 dB for a few milliseconds; the loudest 400 ms of that is -10.1 LUFS. At most 3 of the 12 positional voices were in use, 30 growls were played (never more than 2 at once, 0.22 s apart) and 30 were dropped for the cap. (The worst case is random: an earlier take, before the new groans' peaks were held at -7.5 dBFS, measured +1.1 dBFS unlimited, so assume the limiter takes up to 1.6 dB in such a moment.)

## The weather audio check (item 6)

- **The rain bed is on the Rain bus** (`soundscape.gd setup`: `Buses.rain_bus()`), sent to Ambience. Playing at the soundscape's own levels it measures -31.5 / -25.2 / -20.4 LUFS (drizzle / steady / storm). Its +0.5 dB trim puts the storm 7.5 LU under the gun.
- **The indoor muffle** (`Buses.set_rain_muffle`, by how far indoors Ruth is): the bus's low-pass goes from 20.5 kHz to **1300 Hz** (it was 780 Hz) and the bus **-1.5 dB** (it was -4.5). Measured, the old setting made a roof take **16 to 17.5 LU** off the rain (a drizzle indoors was -49 LUFS: no sound at all, the rain loop has most of its energy above 1 kHz); the new one takes **10 to 10.5 LU** (drizzle -41.5, steady -35.4, storm -31.8). Thunder through the same roof loses 5 to 6.5 LU (it is mostly low).
- **Thunder** (`rain_view.gd _boom`): it used to be the far gunshot and a thud pitched down. It is now `thunder_near_0..1`, `thunder_mid_0..1`, `thunder_far_0` (`tools/make_weather_sounds.py`: a tearing crack of 6 to 10 snaps and a rip for the near one, a dull snap for the mid one, none for the far one, then a rumble in rolling waves, 4.4 / 5.8 / 7.2 s), chosen by how far the strike is. **The distance delay is what was there**: the thunder comes 1 to 3 s after the flash (`delay`, random), and `far = (delay - 1) / 2` picks the file (near under 0.34, mid under 0.67, far above) and the level (`Foley.thunder_db`: -2 dB at the nearest, 6 dB less at the farthest, 3 dB less with a roof overhead). It plays on the **Rain bus**, so a roof muffles it like the rain. The old files are the fallback when the new ones are not there.
- **Thunder after LOOK2 (lightning you can see).** The strike schedule moved to `skies.strikes_between` (a pure function of seed and clock) and every strike now carries its own `delay` and `far`: a storm's ordinary bolt as before (delay 1 to 3 s, `far` 0 to 1 by the delay, so the near, mid or far file by `Foley.thunder_key`); about **one storm bolt in eight is NEAR** (delay 0.05 to 0.3 s, `far` 0: `thunder_near` at the loudest level, -13.4 dB measured, within 0.3 s of the flash); a **steady rain's** bolt (every 30 to 75 s) is far and soft (delay 2.5 to 4.5 s, `far` 0.75 to 1: `thunder_far` or the far end of `thunder_mid`, 5.5 to 6 dB under the near one); a dim **sheet flash** has no thunder. Nothing else about the thunder changed (the same files, bus and indoor loss); the more frequent strikes (storms are 25 percent of the rain periods now, not 14) are the only change in how much of it is heard. Not listened to.
- **Not verifiable here:** that the rain *sounds* like rain (its loop is the earlier generator's, `rain_loop.wav`: a 16 kHz noise loop with a centroid of 2.8 kHz) and that the thunder sounds like thunder; the web build has never had these buses heard (see the end).

## What each sound is made of, and how it is staged

Everything is arithmetic (`tools/make_foley_sounds.py`, `make_voice_sounds.py`, `make_weather_sounds.py`; the kit is `audio_dsp.py` and, for the voices, `voice_kit.py`: a glottal pulse source, three moving formants, a rasp, breath), a fixed seed each, so a second run writes the same bytes. The numbers of every file (peak, RMS, **M-max LUFS**, centroid, bytes) are in `assets/audio/audio_manifest.json`.

| Group (files) | Rate | Length (s) | Peak (dBFS) | M-max, mono file (LUFS) | Notes |
|---|---|---|---|---|---|
| `fs_<ground>_0..2`, 7 grounds x 3: walking steps | 22.05 k | 0.24 | -15.0 to -6.5 | -33.0 to -30.0 | grass -32, dirt -31, gravel -30, pave -31, wood -31, tile -31, carpet -33; centroid 125 Hz (carpet) to 3.1 kHz (gravel) |
| `fs_<ground>_run_0..1`, 7 x 2: running steps | 22.05 k | 0.30 | -12.3 to -6.1 | -29.0 to -26.0 | 4 LU over the walk, a push-off scuff added |
| `dead_soft_0..2`, `dead_hard_0..2`, `dead_drag_0..1` | 22.05 k | 0.34 / 0.34 / 0.50 | -17.7 to -14.5 | -34 / -32 / -30 | a soft foot and a scuff; the limper's file is a step and a drag |
| `blast_out_0..2` (the open) / `blast_in_0..2` (a room) | 44.1 k | 0.85 / 1.15 | -3.2 | -15.4..-14.9 / -17.8..-16.8 | layers: click, crack, pellets, chest (90 to 900 Hz), sub thump 118 to 38 Hz; outdoors one slap-back at 0.15 s and a faint one at 0.33 s, the energy 40 dB down by 0.46 to 0.56 s (the old shot: not before 0.89 s, the end of the file); in a room a 0.5 s reverb. Energy shares under 150 Hz / 150-800 / 800-3000 / over 3000: 25/43/21/11 % (the old shot 40/36/15/9) |
| `shell_load_0..2`, `pump_rack_0..1`, `trigger_click_0..1` | 44.1 k | 0.22 / 0.52 / 0.14 | -4.3 to -3.6 | -25 / -22 / -25.5 | they take the names `shell_in`, `pump`, `dry_click` (`Foley.OVERRIDES`); the old files stay |
| `melee_swoosh_0..2`, `melee_thud_0..2`, `melee_kill_0..2` | 44.1 k | 0.30 / 0.26 / 0.46 | -8.6 to -3.6 | -24 / -23 / -21 | the swoosh rises in 45 ms and falls, so that it peaks as the blow lands 50 ms after it begins (`melee.json`: swoosh_at_s 0.09, hit_at_s 0.14); thud centroid 0.5 kHz, wet kill 1.8 kHz |
| `zgroan_0..7` | 22.05 k | 0.72 to 1.60 | -9.3 to -7.7 | -21 | pitch 87 to 125 Hz (measured by autocorrelation), centroid 0.3 to 0.5 kHz |
| `zgroan_far_0..2` | 22.05 k | 2.6 to 2.8 | -14.8 to -12.6 | -27 | the same, 8 percent lower, low-passed at 620 Hz, a 0.9 s room |
| `zgrowl_0..3`, `zbrute_growl_0..1` | 22.05 k | 0.30 to 0.42 / 0.55 to 0.62 | -5.4 to -3.7 | -19 / -17 | pitch 68 to 78 Hz / about 52 Hz, strong rasp |
| `zrun_hiss_0..1`, `zrun_screech_0..1` | 22.05 k | 0.55 | -12.5 to -10.3 | -24 / -19 | the hiss's centroid is 5.6 kHz, the screech climbs 400 to 900 Hz |
| `ruth_pain_0..3`, `ruth_breath_0..3` | 22.05 k | 0.35 to 0.50 / 0.55 to 0.80 | -7.3 to -5.3 / -16.7 to -15.6 | -21 / -29 | pain at 199 to 248 Hz |
| `thunder_near_0..1`, `_mid_0..1`, `_far_0` | 22.05 k | 4.4 / 5.8 / 7.2 | -4.5 / -7.7 / -11.9 | -15 / -20 / -25 | centroid 1.0 kHz / 0.2 kHz / 0.1 kHz: the far one is under 400 Hz |

**Which sound plays when** (all in `scripts/audio/`):

| | By | Gain staging (`Foley.LEVEL_DB`, dB) |
|---|---|---|
| Footsteps (Ruth, crew) | `soundscape._foot_tick`: a stride of 0.85 tiles; the ground is `Foley.ground_at(world.grp)` (one array look-up, 2 microseconds); a person on a deck is on wood | Ruth -1.0, running +0.5 (own files, `sprint_lean` over 0.5), crew -5.0 |
| The dead's steps | `life_sounds._dead_tick`: a stride of 0.62 tiles; soft on earth and carpet, hard elsewhere; a limper (`z.limp`) drags (`dead_drag`); a brute +3.5 dB and 18 percent lower | 0.0; at most 2 a tick, 13 tiles |
| The wind-up growl | `life_sounds`: the dead one's `attack_t` (the rules' beat; the bite is at 0) falls under 0.42 s; walker `zgrowl`, runner hiss (70) or screech (30 percent), brute `zbrute_growl`; at most 2 at once and 0.22 s apart, a third as often at 14 tiles | -0.5 / +3.0, -2.0 / -1.0 |
| Idle groans | `life_sounds._idle_tick`: one of the dead not at its bite, 4 to 26 tiles away, every 4 to 9 s by day and 2.4 to 5.5 s by night, not within 2.5 s of another groan. Measured: 7 in 40 s by day, 9 by night, never more than 2 groan voices at once | as the groans |
| Groans of the rules | `soundscape.groan` (60 percent of the rules' events, 20 percent of a straggler's): one of the old 8 and the new 8 (the old ones are trimmed by `OLD_GROAN_TRIM_DB` to the new loudness, -4.7 to +2.6 dB), or one of the 3 dark far ones from 16 tiles | +1.0 (+ -2..0), far -1.0, straggler -10 more |
| Ruth's pain | `life_sounds.on_bite`: the rules' `bite` event with Ruth's id; 0.07 s after it, not twice in 0.7 s | -2.0 |
| Ruth's breath | `life_sounds._breath_tick`: the sprint's stamina under 30 percent, while running, winded or for 6 s after; every 0.6 to 1.2 s (quicker and louder the emptier) | -6.0 (to -11 at 30 percent) |
| The pump gun | `combat_fx.shot_sound` -> `Sound.gunfight.shot` (`fight_sounds.gd`): the in-a-room file when the rules say the shooter is in a house (`sim.houses.house_at`), else by the floor | -1.0 / +0.5, distance factor as before |
| The blow | `stab` event at `swoosh_at_s` -> `melee_swing` (now the swoosh); `hit` -> `melee_hit` (now the thud); `kill` -> `melee_kill` (new, one line in `combat_fx.kill`) | file, 0.8 for the kill |

## Budget

- **The exported .pck grew by 926,640 bytes (0.88 MB; the budget was 3 MB)**: `Web (one house)` exported with `--export-pack` at the branch's base commit 68d19c4 is 40,789,236 bytes, with the pass 41,715,876. The 99 new sounds are 3.85 MB of 16-bit WAV on disk and **817 KB as the QOA samples the export carries** (the project's import default; played in the engine, the shot, the room's shot and the blows peaked within 0.3 dB of their files: QOA did not add peaks to them, as it did to the old squashed shot, whose file peaks at -3.0 and whose QOA peaked at 0.0). `tests/test_audio_assets.gd`'s source-size budget went from 24 to 28 MB for this.
- **Nothing is loaded at start-up for the new footsteps, dead and Ruth** (they load on first use: the first step on a ground loads its 3 + 2 files, a few milliseconds): `Soundscape.group()`. The pump gun's two groups, the kill, the three reload sounds and the swoosh and thud (22 small files, 0.2 MB as QOA) are loaded with the others in `Sound.setup`, as every other sound is (265 files already).
- The two new buses and the Rain trim are in the layout file. **The web build must be probed again** (a Web Audio probe on a fresh export, STATUS.md section 4): nobody has heard the Rain bus on the web, and these two buses are more of the same kind.

## Where to turn the knobs

`scripts/audio/buses.gd`: `TRIM_DB` (Steps, Voices, and the four sliders' own), `RAIN_TRIM_DB`, `RAIN_MUFFLED_HZ` / `RAIN_MUFFLED_DB`, `AMB_DUCK_*`. `scripts/audio/foley.gd`: `LEVEL_DB` (every sound), `OLD_GROAN_TRIM_DB`, `THUNDER_*`. `life_sounds.gd`: the strides, the wind-up point, the idle gaps, the breath. `soundscape.gd`: `MAX_VOICES` 12 (was 8), `KIND_CAP`, `FAR_GROAN_FROM`. The files: the generators' `LOUD` / `*_LOUD` tables (then run them and `Godot --headless --import`).

## What nobody has heard, and what to listen for first

1. **The pump gun** outdoors, then in a house: does it have punch and a short tail, and is the room's tail dense rather than long? (Measured: a flatter spectrum than the old shot, 6 LU less loud in the file, peak equal.) Fire it with rain falling, once.
2. **The footsteps on each ground** (grass lawns, the street, the house floors: wood, tile, carpet) and Ruth's run against her walk (+6.5 to +7.5 LU).
3. **A fight with the blade**: swoosh, then thud, then the wet kill: do they read as one blow?
4. **Zombie voices:** a street of the dead by day (the idle groans), then a few at your door at night (the wind-up growls before each bite). The runner's hiss and screech and the brute's growl are the least certain: they are formant synthesis, the likeliest to sound artificial.
5. **A storm:** rain, then thunder after the flash (near, mid, far), then walk indoors: the roof's muffle is now 10 LU.
6. Ruth's pain on a bite and her breath at the end of a sprint.

Open: the first listening will probably want the Voices trim (+9) and the rain moved by a few decibels (one number each); the generated voices may be replaced by recordings later.
