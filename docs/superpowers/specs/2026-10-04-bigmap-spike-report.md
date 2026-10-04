# The big town foundation: what was built and what it costs (2026-10-04)

Branch `feature/town-core`. Not a go/no-go any more (the owner committed to the direction): these are the numbers that set the caps and the rules, and the data
the next packages build on. Machine: an Apple M1, 8 cores, with two other builders running Godot all the time (load average 5 to 10), so every number is good to about
30%; the p50 is the figure to trust, the max of a run is often the machine. Plan: `docs/superpowers/plans/2026-10-04-one-house-plan.md`.

## 1. What exists

`scripts/town/`: `town_gen.gd` (the generator, data shapes in its header), `town_world.gd` + `town_chunk_paint.gd` (the chunked ground, stepped build), `town_roofs.gd` (+ `.gdshader`,
the fallback roofs), `dormant_dead.gd` (the field), `town_sim.gd` (`TownSim extends town_rules.gd extends sim.gd`: the colony on the town), `houses.gd` (`sim.houses`),
`town_medical.gd`, `town_boot.gd` (factories, `--town` parsing, the loading card), `town_game.gd` (the facade and `VIEW_PARTS`), `town_run.gd` + `town_scene.gd` (the
standalone `--town-spike` scene and the benchmarks). `tools/town_bench.gd` (headless numbers). `tests/test_oh_town.gd` (five tests, all pass), `Helpers.town_game` at the end of `tests/helpers.gd`.

`--town[=seed]` is the REAL game on the town (seed 1; `--town-blocks=2` makes the 64 x 64 mini town; in a browser `index.html?town`); with `--crew` it still means the
school's Town Board. `--town-spike` (alias `--spike-town`) is the old standalone scene: WASD, mouse, N shout, L light, M map, F3 numbers, `--bench=SECONDS`.

## 2. The data (frozen at v1; the full shapes are the header of `town_gen.gd`)

`TownGen.make(seed, opts)` is deterministic (`TownGen.digest`); `opts.blocks` 2 to 6 (default 6 = 192 x 192, 179 houses, 513 rooms, 230 containers, 700 dead; 2 = 64 x 64, 18 houses,
78 dead, made in about 0.1 s). Result keys: `data` (the map in the schema of map.json), `houses`, `rooms`, `containers`, `dead`, `start`, `rescue`, `tile_house`, `tile_room`, `streets`, `stats`.
House: `id, kind (small|medium|terrace|shop), address, rect (walls = footprint), lot, front, fenced, door, doors [{tiles, exterior, side, out, in}], rooms [room indexes], containers [ids],
dead [record indexes at the start]`. Room: `id "h17:kitchen", house, name, rect`. Dead record: `pos, kind, state, house, room (-1 yard or street), group`. `start`: `house, pos, room, ring {rect, total, free}`
(the start lot is unfenced and its border and the row inside it are free: `free == total`; three dead inside). `rescue`: 12 candidates near to far (2 in the mini town), each `{house, pos, room, ring, dist}`,
each house with 2 to 4 guards, one in the survivor's room. `tile_house` / `tile_room` (W x H ints) answer "which house / room is this tile in" in O(1). `sim.houses` wraps them (plan 2.2),
`sim.field.dead_in_room(r)` / `dead_in_house(h)` give `{total, dormant, active, left}` by where the dead stand now.

## 3. Where the per-dead cost was (the colony's code, `main` at 9019934)

- `Sim._separate` (sim.gd 1831): every pair of the dead every step, a square: 100 dead 2.0 ms, 160 dead 6.1 ms, 240 dead 12.2 ms. This is the cost behind the old web numbers.
- `Sim._update_zombie` `hunt` arm (1650): gives up at 14 tiles (Streets.GIVE_UP), asks `region_at` twice a step (a flood of the whole map, 12 ms, redone after every door, wall or build) and searches a way every 0.8 s.
- `Sim._shot_noise` (1256) and `Avatar.trace` (avatar.gd 517) loop over every dead one per shot (cheap once the awake dead are capped).
- `Pathfinder.find` (AStarGrid2D, 8 way, string pulled): 60 us for 6 to 12 tiles, 176 us for 12 to 25, 436 us for 25 to 45, 763 us for 45 to 90; `sight` 5 to 10 us. Two grids of 192 x 192 cost 2.4 ms each to build and 6.5 MB.
- What scales with the map: the grids and `_compute_regions` (36,864 cells: 12 ms), `World.build` (124 to 142 ms headless: three GDScript loops over the tiles and one `GroundDetails._draw` of ~18,000 rects), `SiteCanvas._put`
  (two floods of the whole canvas per prop: why every lot is built on its own small canvas and stamped in).

The check on the model: the old web figures (60 fps at 80 dead, 48 to 57 at 160, 19 at 240) are the base's step times above times about 3 (5.7, 22, 41 ms a step). Web = 3 to 4 times the desktop.

## 4. The numbers (desktop M1; "step" = one rules step of 1/30 s, the colony's whole `Sim.update`)

| What | Base (hunt, square crowd) | New (chase, grid crowd) |
| --- | --- | --- |
| step, 0 dead awake | 0.07 ms | 0.08 ms |
| step, 60 awake, after the avatar | 1.31 ms | 0.79 ms |
| step, 100 | 2.68 ms | 1.14 ms (crowd 0.43, chase 0.44, A* 56 a second 0.15) |
| step, 160 | 7.41 ms | 2.22 ms |
| step, 240 | 13.66 ms | 3.28 ms (about 13 us a dead) |
| the avatar crosses the town for 200 s, cap 100 | | step mean 1.26, p50 1.10, p99 3.75 ms; awake mean 89, peak 100; woke 735, slept 635 |
| the same at cap 60 | | step mean 0.79, p99 2.4 ms; awake mean 59 |
| wake pass / sleep pass (every 0.25 s) | | 32 us / 28 us |

A frame at 60 fps takes one step in two, so 100 awake dead are 0.6 ms of a frame on average (1.1 on the step frames) on the desktop and 2 to 2.3 ms (3.4 to 4.6 on the step frames) in a browser.

| Load and render | Desktop |
| --- | --- |
| generator, full town / mini town | 197 to 294 ms / about 100 ms (stepped version: `begin/step/result`, 8 ms a frame) |
| `World.build` as it is / `TownWorld` (headless) | 124 to 142 ms / 19 ms (windowed adds about 100 ms of first texture loads) |
| `TownSim.new` | 13 to 33 ms |
| the real game, `--town`, to the first frame | 709 to 1020 ms (card drawn first); the standalone scene 600 to 1140 ms |
| memory (static) | town data 28 MB (with the prop pictures), World nodes 21 MB, TownSim 6.5 MB; 200 MB in all |
| frame at play zoom (42 px a tile), 100 awake | 3.6 ms with vsync off (the loop is paced at 300 Hz: that is a floor, not a cost); 118 draw calls mean, 213 max (45 with no dead) |
| frame as a map, all houses in view, before / after hiding props below 12 px a tile | 1628 / 402 draw calls, 4.8 / 5.0 ms |
| roofs: a node for each house / one MultiMesh | 118 / 112 draw calls at play zoom; 402 / 242 as a map; off 115 |
| the first sight of a look of the dead (a pawn node) | 2 ms before `TownBoot.warm_pawns`, 0.16 ms median and 0.5 ms at p95 after |
| a flow field (4-way BFS, 144 KB) from one target | 30 ms whole grid, 2.6 ms within 45 tiles, 1.2 ms within 28 |
| save: the field for 700 records | 8.6 KB of JSON (12.3 bytes each, 3 integers); 100 real zombies in the old format 43.8 KB, 800 of them 350 KB |

Flow fields do not pay for the avatar's chase: 100 chasers cost 0.15 ms a step in A*, a field within 45 tiles refreshed 4 times a second costs 0.35. Keep A* with the straight line;
use a cached field only for the base's perimeter at night (fixed targets).

## 5. Recommended caps and rules

- Active cap: **desktop 60 (a step 0.8 ms), up to 100 if the night needs it; web 40 (a step about 3 ms), 60 at most.** The desktop carries 240 at 3.3 ms; the limit is not the dead's rules but the render and the HUD. `TownSim.ACTIVE_CAP` / `ACTIVE_CAP_WEB`.
  The night's wave dead are not records and have their own cap (`CAP_NIGHT` 50, via `alive_for_cap`), so the worst night is 60 + 50 awake: 0.8 + 1.4 ms desktop, about 7 ms a step in a browser.
- Wake 28 tiles, sleep 45 (hysteresis), a shot or a shout 30 (wakes and sends them), a light 12 (wakes, leaves them wandering), "they see you" 7 tiles with a clear line; a dead one inside a house the avatar is not in wakes at half the radius
  (`INDOOR_SHARE`); `night_mult` (1.4 at night, set by the scenario) scales the radius; `pause_wake` stops all waking while a wave is on; the nearest wake first and the rest wait for room.
- A chasing dead one gives up at 45 and then sleeps; `still` dead cost nothing (no state arm), the crowd pass skips two still ones.
- Never bring the colony's `hunt` into the town (it gives up at 14 and floods the map); never `region_at` (the town sets `lots.on` false so nothing asks it).
- Hold the draw calls: props and trees are hidden below 12 px a tile (map view), roofs are one MultiMesh in a browser, the pawns' nodes are made a few a frame (the real `main._sync_views` makes all of them in one frame: WP9 adds the budget).
- Web: the export works (`--export-release "Web"`: 29 MB `.pck`, 39.5 MB `.wasm`, about 67 MB of files; the town starts with `index.html?town`). The browser check is the owner's: expect the town to take 2 to 4 s to make behind the card.

## 6. What is hard or risky (top five)

1. **The school's assumptions in the colony's `update`** keep turning up: `medical._gate` (`segments[2]` every step) is not in the plan's list (worked round in `town_medical.gd`), and the school's stations, posts and plots are still in `jobs` and `build`
   (a "Work the bench" prompt shows in the start house until `install_layout`). Each new module will find another; run the game, not only the tests.
2. **The first-sight hitches**: a pawn node (fixed by `warm_pawns`), 60 nodes at once when a shout wakes a street (main makes them all in one frame), and an A* burst of the woken (each starts at a random 0 to 0.3 s: spread).
3. **Draw calls in a browser**: 118 at play zoom is fine, 400 as a map is not; 3,900 canvas objects. The roof MultiMesh and the LOD are in; WebGL's cost per draw call is not measured here.
4. **Saves**: `field.sleep_all()` must run before `SaveGame.write` (SaveGame has no hook): `main.gd` calls `sim.pre_save()` at its two save sites; anything else that writes a save (a test, a tool) must call it too.
5. **The generator's fixed layout**: 32-tile pitch, 12 or 13 deep lots, four templates; windows do not exist, doors never close, the start lot is a medium house with two tiles to spare. Good for the demo, a limit for variety.

## 7. Facts others need

- `TownSim.update` = `field.update` (wake, sleep), `_notice`, the colony's `update`, then each part's `update(dt)`, then `_town_events` (the school's banners rewritten before the attacks begin). `TownSim.PARTS` and `TownGame.VIEW_PARTS` are pre-filled; a missing file is skipped.
- `main.gd` hooks (WP1): `_ready` (factories, the card, the facade, A13: no dressing, parking or gate node; `BaseLife` off), `_process`, `_sync_views` x2, `_handle_events`, `avatar_hands_off`, `_unhandled_input`, `_min_zoom`, `_clamp_camera`,
  the two saves, the `--town` arm of `_parse_args`. **Not done: `_music_context`** does not exist in this branch's `main.gd` (it arrived with the audio merge): add `if town != null: ctx = town.music_context(ctx)` before its `return ctx` when merging.
- `wants_avatar` for a test needs `"avatar": true` in the run meta (the real game is always an avatar game).
