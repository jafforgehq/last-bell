# Appendix A: code and architecture review

> A read-only review of scripts/, tests/ and tools/ (nothing was run; the numbers marked as estimates are the reviewer's). Part of [the full audit](2026-10-01-full-audit.md), 2026-10-01, repo HEAD e4fa379.

## 1. Verdict
The rules layer is the strong part: one seeded RNG (no global randf/randi in `scripts/sim`), an atomic bit-exact save, 278 tests with fuzz and replay checks. The platform around it will not carry a bigger game yet: the sim steps at display rate, needs a real `World` node tree, is hard-wired to one compound, runs per-zombie A*, and loads roughly 240-350 MB of uncompressed per-instance textures from an unauthorable one-line `map.json`. No crash or data-loss bug found in normal play. Do the six refactors in section 6 first.

## 2. Findings (ranked)
1. **HIGH sim.gd:635-652**: ammo never gates shooting. `stock.ammo` is only decremented and clamped (no other reader); reloads are free. At 0 the colony fires forever, so spec 7b's "binding constraint around day 10" and the tuned night budget rest on a stock with no effect. Fix: refuse fire/reload at 0 with an alert; re-run `balance.gd`.
2. **HIGH main.gd:509-515**: sim step = frame time (up to 1/30), not fixed. At 120 Hz the rules take 4x the steps of harness/tests; `_separate` pushes per step, not per second (sim.gd:935); `rng.randf() < dt` draws (787, 793) change RNG use, so shared seeds and harness numbers do not reproduce live play (libm can also differ per platform). Fix: 30 Hz accumulator, step cap.
3. **HIGH sim.gd:438-441, 830-856**: path storms. At dawn every zombie `retreat()`s in one step (A* + GDScript smoothing each). Breach hunters take the nearest person by distance only, then re-path "each second" unless the path is empty (848), which defeats the throttle. Tower sentries' tiles (18,16), (65,16) are solid in `solid_z`, nearest free tile in the street component (my port of `_apply_deck_barriers`): a yard walker targeting them runs a failing A* over the ~950-tile yard every step and freezes. Fix: reachability-aware prey, failure back-off, per-step path budget.
4. **HIGH assets/**/*.import (all 639: `compress/mode=0`, mipmaps)**: lossless imports upload uncompressed; 14 of 425 textures are reused. From PNG headers: ~240 MB at start, 350 MB eventually (school walls and roofs ~115 MB). Web-demo risk now. Fix: VRAM compression (main lever), prop catalogue/atlases, per-chunk loading.
5. **HIGH map.json; sim.gd:287-296, 410, 493-500, 580**: one generated line with baked derived data (`solidZ/P`, segment `tiles` as y*84+x, slots); `wall`, `rooms`, `yard`, `pivot`, `version` are unused while code re-hardcodes them (580 is `yard`). `_seed()` indexes segments 0-11 and fixed slots: a smaller map crashes `Sim._init`. More: scavenge.gd:38,253, medical.gd:784, deck_faces.gd:84,87,178,234, main.gd:42,203. `solid_p` joins yard and street at the corners, unvalidated. Fix: source format, baker, validator test.
6. **MED sim.gd:919-943**: `_separate` is O(n^2) over all zombies including corpses (kept 70 s, line 763). N=100: 4,950 pair checks per step (est. 2.5 ms) times #2's step rate. Fix: spatial hash; corpses in their own list.
7. **MED supplies.gd:76 (and 4 more modules), sim.gd:213-214**: RefCounted cycles (module.sim<->Sim, Slot.seg<->Segment) never free. Each New game/Load leaks a Sim (~200 objects, 2 AStarGrid2D); an earlier suite log ends "48078 ObjectDB instances were leaked". Fix: `dispose()` or WeakRef.
8. **MED sim.gd:793-795**: approach->breach keeps its reserved slot (the attack path, 819-822, releases it). Hunters hold wall slots until they die, starving later arrivals. Fix: release on transition.
9. **MED save_game.gd:295, 475-511, 536-543, 688-689**: version equality only, no migration, no map/content hash; module sections are unvalidated before `_commit` mutates the sim (`medical.load_state` casts unchecked data: half-applied); free-text `facing` (386) becomes a KeyError at PIVOT (sim.gd:629); one autosave slot (main.gd:674-676). Fix: schema version + migrations, validate-all-then-commit, rotating slots.
10. **MED save_game.gd:199-203, 248-252; main.gd:668**: each non-integer float is stringified and re-parsed, then all text is parsed and validated again, synchronously each dawn. Est. tens of ms, more on web. Fix: bits-as-array, validate once, spread over frames.
11. **MED lighting.gd:46-47, 88-111; world.gd:177-181**: startup bakes 573,440 light-texture pixels in GDScript (23 lights; est. 0.5-1 s); each wall's first hit loads its damage-state textures synchronously (42 files, 45 MB raw). Fix: bake/dedupe offline; preload on a loading screen.
12. **MED supplies.gd:48, medical.gd:81, sim.gd:436-447, hud.gd:31-43, 791**: presentation lives in the rules; HUD copies thresholds and indexes `SIDE[s.side]`/`MATERIAL[s.kind]` (KeyError on a new wall kind). Blocks tutorial, localisation, UI rewrite. Fix: events with ids+params, `tr()`, data tables.
13. **MED main.gd:468-503, 517**: hard-coded `KEY_*`, no InputMap, modifiers ignored (Ctrl+R drafts), no gamepad, no pause on focus loss; F5 save is the browser's reload key (web, unverified).
14. **MED tests/helpers.gd:13-20, sim.gd:187-188**: rules need a real `World`: 150 build call sites. tools/balance.gd:34 and tests/test_scenario.gd:8 import each other; tests pin segment indices; no CI; dev flags (main.gd:681-829) and tests/tools ship in the export (export_presets.cfg:8-10).
15. **LOW sim.gd:150, balance.gd:221**: `events` is drained only by main.gd:669; headless games keep every claw/groan/shot (est. tens of MB per 30-day game). Churn: goal dict per person (473), 14 PackedVector2Array per pawn redraw (pawn_art.gd:70), alert stack rebuilt when a "% intact" line changes (hud.gd:1333).

## 3. Performance hotspots (estimates; no profiler)
- Per step (x display Hz): `_separate` N^2/2; `_find_target` P x N at night (sim.gd:570).
- Per zombie per second: breach A* + string-pull. Modelled on shipped `solidZ` (24 spawn-to-slot paths): 17-85 cells, 15-840 expansions, 246-24,676 `free_at` calls (median 3.7k) from `sight()` (pathfinder.gd:69-96): ~0.2-17 ms in GDScript at ~2 us per sample. Smoothing, not A*, dominates (worst case O(L^2)). Dawn runs N at once: tens to 100+ ms hitch.
- Per frame: `_sync_views` O(N) (main.gd:579-607); each visible walker redraws ~38 draw commands (50 visible: 1.9k); `air`, `ground_bits`, `glow`, `overlay` redraw every frame; `fx` runs 3 passes over ~190 particles that 5 fires emit even off-screen (main.gd:562-568).
- Growth: sim N^2 + K*L^2 (K hunters, path length L); map x4 doubles L (smoothing x2-4); draw follows visible pawns; particles follow fires map-wide.

## 4. Scalability
Now: 5,376 tiles (3 byte grids 16 KB; 2 AStarGrid2D under 1 MB est.), 380 objects (174 decals, 153 props, 53 big; lockers 54, cracks 36, blood 33, papers 30, stains 27, cars 14), 3 wall images, 13 trees, 425 textures, 23 lights, 14 walls/100 slots, 1,148 curb rects in one CanvasItem. At 4x: ~1.5k sprites, 1.4 GB textures, 92 lights (2.3M-pixel bake), grids ~3.5 MB (fine).
Breaks first: (1) authoring: no generator or validator exists; (2) texture memory/load; (3) startup (lights, `set_cell`s, nodes); (4) sim (N, path length, separation); (5) draw: big CanvasItems cull whole, `glow` loops every light.
Streaming: split `World` into node-free `MapGrid` (byte grids + one AStarGrid2D, fine to x16) and a chunked `WorldView` (32x32 tiles of sprites, details, lights) built near the camera and freed beyond; pool ~24 PointLight2D on the nearest lamps. Sim: a flow field per goal rebuilt when a wall changes, far walkers at low rate, spawns on a ring.
Authoring: diffable source (Tiled/TileMap scene or pretty JSON: ASCII terrain, props by kind from a catalogue), `tools/bake_map.gd` emitting chunks, solids, wall tiles, slots, and a connectivity validator (yard sealed for the dead, posts reachable, spawns free) run in tests. Today the only route is throwaway scripts patching one line.

## 5. Test suite
Strong: medical 65, scavenge 38, supplies 36, save 19 (replay after load, atomic write), HUD 82 with fuzz and real clicks; any logged error fails a case (run.gd:9-16); an earlier mutation run on supplies.gd killed 21/23 (survivors: meal counter not saved/not reset).
Uncovered: sim.gd combat, zombie states, slots, separation, retreat (6 scaffold tests), pathfinder, world beyond decks, main.gd (input, camera, picking, autosave), every render node, audio, game_data.
Brittle: HUD tests need two awaited frames and pixel overlaps (hud_kit.gd:134); balance literals; map indices; a script error skips `world.free()`, leaving nodes under root.
Speed: not measured (150 World builds, night-length runs).

## 6. Refactors before features
1. Fixed 30 Hz loop, event drain, dt-scaled separation (S): 4x CPU, reproducible runs, tutorial pause.
2. Node-free `MapGrid`; Sim without World/FX nodes; one `set_blocked()` (solids are synced by hand at sim.gd:893-903, save_game.gd:645-650); break cycles (M).
3. Map pipeline: source format, baker, validator, chunks, prop catalogue, texture compression, data-driven compound constants (L).
4. Navigation/AI: flow fields, path budget, spatial hash, zombie types as data with enum states (M-L); runners/brutes and build mode need it.
5. Command + event layer (ids, not strings), InputMap, scene/theme HUD (M-L): tutorial, localisation, controller, UI overhaul.
6. Save v2: schema version, migrations, content hash, validation, slots (M), before any Early Access save exists.

Not verified: engine costs, web (Compatibility renderer) behaviour, F5 in browsers, test timings.
Note: an untracked `docs/audit/` appeared in the repo at 08:40; this audit did not create it.
