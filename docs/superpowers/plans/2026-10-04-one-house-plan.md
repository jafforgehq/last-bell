# One House: the implementation plan (nine packages, built in parallel)

> Spec: `docs/superpowers/specs/2026-10-04-one-house-design.md` (the owner's COMMITTED design). This plan was made on 2026-10-04 from `main` (e455186) and from the foundation builder's worktree `.worktrees/spike-bigmap` (branch `feature/town-core`, uncommitted, read-only) and the art builder's `.worktrees/town-art` (`feature/town-art`, nothing written yet when this was made). Nothing in the repository was changed to write it.
> Integration branch to create first: `feature/one-house` (from `main`). Every package works in `.worktrees/oh-wpN` on `feature/oh-wpN-<name>` made from it (section 7 has the commands).
> Where this plan says **VERIFY** it is something the planner could not settle by reading; the package owner settles it in the first half hour and says so in the report.

## 0. The whole thing in ten lines

1. The game is **one real game in `main.gd`** (not a new scene): a new `TownSim` (extends `sim.gd`, the colony) on a 192 x 192 town map, drawn by a chunked `TownWorld`. The foundation's standalone `town_scene.gd` stays only as a benchmark tool.
2. **Nothing of the school's rules is edited for the town.** The school's assumptions (a compound at (42, 32), a gate that is wall section 2, a fixed `posts.json`, `stations.json`, `plots.json`, wall sections 0 to 13) are generalised by **eleven neutral hooks** in shared files (section 1.5, made first, by WP5 phase A) and **overrides in two new subclasses** (`TownRules` then `TownSim`). The golden tests stay byte-identical because every hook returns today's value in every game that is not the town.
3. **The dead of the town are records** (a struct of arrays in the foundation's `DormantDead`), woken into the real `Sim.Zombie` near the avatar (cap about 60), put back to sleep far away. The night's wave dead are plain zombies with no record: the two never mix up (section 1.3).
4. **A house is data** (the generator's `houses`, `rooms`, `doors`, `containers`, `tile_house`, `tile_room`): the rules read it through `sim.houses`, the screen through new view parts. Roofs are one node per house that fade out when the avatar is inside; rooms behind a closed door are dark until revealed; a dead one in a dark room is not drawn.
5. **Claiming** a cleared house runs `base.claim(house)`: it installs a generated **base layout** (a Dictionary built from the house's lot) into `build`, `jobs`, the perimeter module and the spawn list. The perimeter slots are **Build plots**: fence and gate go up as wall sections made in play (`sim.add_segment`, the lots' mechanism of round 9), tower and floodlight are the existing buildings.
6. **Rescued survivors** are `recruits`-style people (`sim.add_person`, saved through `recruits.arrived`), found as bystanders in houses (hiding, wary, spoken to, joined, lost), who join after a card with the player's choice.
7. **The fourth rescue** (`OneHouse.on_survivor_joined`) sets `attacks_on`; until then `waves.enabled` is false and the bell does not send the wanderers at the wall.
8. **Solo start** = the existing community modules, switched by their own `enabled` flags according to how many people there are (data in `one_house.json`).
9. Packages never edit the same function: shared files get **one-line hooks** by a named owner; everything else is a **new file** loaded by a soft-wired table (a package that has not landed yet is skipped, so merges can come in any order).
10. The demo is about **25 minutes** (a game hour is 30 real seconds: `min_per_sec` 2.0) and a bot (`tools/house_lab.gd`) plays it end to end as the acceptance test.

---

## 1. Architecture decisions

### 1.1 One host, one rules class (D1)

**Decision.** The town is played in `scripts/main.gd` like the school: `Main._ready` builds the data, the world and the sim through three factory calls (`TownBoot.data(run)`, `.world()`, `.sim(data, world, fx)`) when the run is a town run (`run.town` from the title's New game, or `--town`), so the HUD, the radio, the command wheel, the pawns, the avatar's hands, the music, the saves and the end card are the real ones. The foundation's `scripts/town/town_scene.gd` (its own scene with its own camera, started by `--town` today) is kept as the benchmark and the visual check (`tools/town_bench.gd`); `--town` in `main.gd` now means the real game and the old scene gets `--town-spike`.

**The rules class is the colony, not a place.** The foundation's `town_sim.gd` extends `raid_sim.gd` (a place: `nights_on = false`, no posts, no yard, the squad). The One House needs the colony machinery (radio, jobs, build, nights, briefing, gate...). So the final class is `TownSim extends "res://scripts/town/town_rules.gd"` and `TownRules extends "res://scripts/sim/sim.gd"`. What `RaidSim` overrides that the town also needs is copied into `TownSim`/`TownRules` as overrides with the colony's values (below). Why two classes: WP5 (the school's assumptions) and WP1 (the dead, the field, the loop) then never edit the same file.

| Override | Class | What it does in the town | Source of the pattern |
| --- | --- | --- | --- |
| `_seed()` | TownRules | nothing (`Sim._seed` indexes `segments[...]`, which a town starts without) | `raid_sim.gd` |
| `start_run(d, s)` | TownRules | `super`, then `zombies.clear()` (Sim.start_run puts four dead at the school's corners) | sim.gd 681 |
| `_in_yard`, `_in_the_yard`, `inside_school`, `dead_inside` | TownRules | the base's yard rectangle and the house floor (`base.yard_rect()`, `houses.house_at`); false before a claim | sim.gd 1129, 1761, 1475, 1481 |
| `_dead_coming()` | TownRules | `approach`/`attack`/`breach` dead within `THREAT_R` of `base.compound()` (the static `_compound_dist` cannot be overridden: the override is of the instance method) | sim.gd 951 |
| `posts_manned()` | TownRules | `radio.alarm_on or (scenario.attacks_on() and night rules)`; false while no attack is on | sim.gd 905, raid_sim.gd |
| `_dawn_sweep()` | TownRules | only the wave dead (no record in `field.rec_of`) retreat; the town's own dead stay | sim.gd 1547 |
| `yard_open()`, `_breached()` | TownRules | `super() or perimeter.no_outer_wall()` for the first (with no fence built the barred doors are the outer wall, so the dead go for them); both also true while the base's gate stands open | sim.gd 1440, 1573 |
| the hook functions of 1.5 | TownRules | `base_center()`, `yard_middle()` = the base's; `_wanderers_rally()` = `scenario.attacks_on()`; `_any_gate_open()` = `perimeter.gate_open()`; `_is_open_gate(s)` = `s.kind == "gate"`; `alive_for_cap()` counts only zombies with no record in `field.rec_of`; `is_one_house()` = true | H1 to H6 |
| `_find_target(p)` | TownRules | the place version: a clear line (`path_z.sight`) to the target, no yard bonus | raid_sim.gd |
| `_hunted(p)` | TownRules | also true for a `chase` dead with `hunt_id == p.id` (by day a person defends himself) | sim.gd 1152 |
| `_hunt_allowed()` | TownRules | true at every hour | raid_sim.gd |
| `update(dt)` | TownSim | `field.update(dt, anchors)`, `_notice()`, `super.update(dt)`, then the parts' `update`, then `_town_events()` (renames the school's banners, section 1.8) | town_run.gd `update` |
| `_update_zombie`, `_separate`, `_shot_noise`, `start_chase`, `_chase` | TownSim | the spike's `chase` and `still` states, the one-tile grid crowd pass, shots go to `field.noise` | town_sim.gd |
| `prepare_load(data)`, `restore_load(before)` | TownSim | before a save is read: `recruits.prepare_load`, `base.prepare_load`, `perimeter.prepare_load`, in that order (section 1.11) | sim.gd / save_game.gd `apply` |

### 1.2 One world, no map chunks in the rules (D2)

**Decision.** One walking grid of 192 x 192 tiles (36,864 bytes per grid, two `Pathfinder` AStarGrid2D, as the school's 84 x 64 with more cells). There are no map chunks in the rules. Chunking is in the **drawing** only: `TownWorld` (foundation, `town_world.gd`: ground as about a dozen meshes, curb and lane paint by 32 x 32 chunk that is drawn only when seen, sprites in batches), one roof node per house with the renderer's own culling, pawn nodes only for what is in `view_rect().grow(3)` (`main._sync_views` already does this for the dead).
**Why.** Two grids of 36k cells are small for A*; the spike's measurement is the foundation report (its `tools/town_bench.gd`); a chunked rules world would need cross-chunk paths for every night's dead and for the avatar's gun (a shot crosses chunks), all of it new bugs for no gain. **What is capped instead** is the number of awake dead (section 1.3) and the path searches per step (WP9).
**Costs to watch** (WP9): `Sim.region_at` floods the whole map on demand (36k tiles): only `assign_slot` with `lots.on` and the base `hunt` state call it; the town has `lots.on = false` and the `chase` state, so it is never called (a test asserts `_regions_dirty` stays true through a night). `Pathfinder.find` is called by wander (every 6 to 14 s each), wave `assign_slot` and chase (rate-limited by distance): WP9 adds a per-step budget (`path_budget`, default 24) in `TownSim` if the bench shows spikes.

### 1.3 The dormant dead: records, the awake few, and the nights (D3)

- **A dormant dead is a record**, not an entity: `DormantDead` (`scripts/town/dormant_dead.gd`, foundation) keeps x, y, kind, look, hp, stands, status, room in packed arrays and in a 16-tile spatial hash (`cells`). 700 records cost nothing per step. **An awake dead is the real `Sim.Zombie`** (`sim.spawn`) with a back-link (`rec_of[zombie] -> record`, `active_of[record] -> zombie`), so every rule that exists (shooting, `avatar.trace`, kill counts, blood, `_separate`, saves) works unchanged.
- **Wake**: every 0.25 s the records within `wake_r` (28; 40 at night, `field.night_mult`) of the avatar wake, nearest first, never above `active_cap` (60 on desktop, 40 on the web: WP9) record-born zombies at once. A shot (`noise`, 30 tiles) wakes and sends them; a light wakes and leaves them wandering. **Sleep**: an awake dead that is not after anybody and is farther than `sleep_r` (45) from every living person goes back to its record (place and hit points kept). A dead that was killed is closed for good (`KILLED`).
- **The night's wave dead are NOT records.** `Waves.update` spawns `approach` zombies with `sim.spawn` at `sim.spawns` (the base's entrances) exactly as at the school; they have no `rec_of`, they retreat at dawn (`_dawn_sweep`), they are saved the old way (the save's `zombies`). Record-born dead that are awake near the base at night behave as dead of the street: they chase what they notice and may join the fight.
- **They share one cap.** `Waves.update` counts `alive` over all `sim.zombies` against `CAP_NIGHT` (50) / `CAP_BIG` (90): street dead that are awake would eat the night's room. Hook H6 (section 1.5): the count goes through `sim.alive_for_cap()` (default: the same loop), `TownRules` overrides it to count only zombies with no record. And at night, when an attack is on, `field.pause_wake = true` (no new wakes near the base: the night belongs to the wave; the street comes back in the morning), set by `OneHouse` (WP6).
- **Before the fourth rescue** (no attack): `waves.enabled = false`; the dead of the street are the only danger; by night `wake_r` x 1.4 and the `still` share of newly woken records is lower (they wander more): "the streets are dangerous in the dark"; the base is a cleared house whose doors are barred (D5).
- **Clear detection** counts records by where they are *now*: `field.dead_in_room(r)`, `dead_in_house(h)` (the foundation has them, `{"total","dormant","active","left"}`); a dead one that walked out of the house to chase the avatar and was shot outside no longer counts; one that is still inside does.
- **Saves**: `field.save()` is 3 integers per record ({x, y} in tenths of a tile, one flags word: kind, stands, look, hp in halves, killed bit): 700 records = about 20 KB of JSON. Before a save the awake record-born dead are put to sleep (`field.sleep_all()`, called by `TownSim.pre_save()`), except those in `approach`/`attack`/`breach` (the wave's, which are saved by the old way). Autosave is at dawn (`day_start`), when nothing of the wave is left.

### 1.4 Houses, rooms, doors, roofs: what is sim and what is view (D4)

**Sim (static data, from the generator, never saved):** `town.houses[i]` (`rect` the footprint, `lot`, `front`, `doors`, `rooms` indexes, `containers`), `town.rooms[i]` (`id` "h17:kitchen", `rect` the floor), `town.doors` (`tiles`, `exterior`, `out`, `in`), `town.tile_house` and `town.tile_room` (W x H int arrays: "which house/room is this tile in", O(1)). `sim.houses` (`scripts/town/houses.gd`, WP1) wraps them: `house_at(x, y)`, `room_at(x, y)`, `rooms_of`, `doors_of`, `containers_of`, `dead_in_room`, `dead_in_house`.
**Sim (dynamic state, saved), `sim.clearing` (WP3):** which rooms are *revealed*, which are *clear*, which houses were *visited*, the avatar's current house, the claimable test, the events of section 2.4.
**Doors never block.** A door is an opening in the terrain walls (a gap: `solid` 0). It has no collision state: the dead, the people and the avatar pass as they do today. A door has two uses: (1) the **reveal**: standing within 1.2 tiles of a door, or on its tile, reveals the room on the other side (`clearing.reveal(room)`); E at a door ("Look in") reveals both sides without stepping through (the door sprite swings open and stays open; a door that nobody is near swings shut; open/closed is only a picture); (2) at a **claim**, the house's two exterior doors get a *barred door* segment of kind `door` (shut to the dead's grid, open to people: the school's own door kind, sim.gd `open_segment`, 1520), so a cleared, claimed house is shut to the wanderers. No other door ever has a segment.
**View (WP2), `house_view` part:** one roof per house over `house.rect` (z above the entities: what is inside is hidden by the roof itself, no per-pawn rule), the roof of the house the avatar is in fades out over 0.25 s (`TownRoofs` of the foundation is the working fallback, the part replaces it with the art kit's roofs and eaves); one *veil* (a dark shape) per room of the house the avatar is in, on until the room is revealed; **a pawn that stands in a room that is not revealed is not drawn** and has no bubble/bracket (`TownGame.pawn_visible(entity)`, one hook in `_sync_views`); a pawn outside every house is always drawn; the roof of a house the avatar is not in hides everything under it. The avatar's own room is always revealed. Line of sight inside a house is not modelled (the spec's later refinement): a revealed room shows all it holds.
**Interior art:** floors, walls and furniture are the generator's terrain and objects (placeholder art today, the kit's later through the manifest `assets/data/town_art.json`, accessed only through `TownArt`, WP2).
**Pawn visibility rule, in full** (WP2 implements, WP3's `clearing` provides the state): `visible = in_view and (house_at(pawn) < 0 or (house_at(pawn) == avatar_house and revealed[room_at(pawn)] or room_at(pawn) < 0))`, and for the avatar always true.

### 1.5 What in the sim assumes the school, and what is done about it (D5, D6)

The complete list found by reading (file and line are of `main`):

| # | Assumption | Where | In the town | Owner |
| --- | --- | --- | --- | --- |
| A1 | the dead around the school at the start of a run | `Sim._seed`, `start_run` (545, 681) | overrides (section 1.1) | WP5 (TownRules) |
| A2 | the compound rectangle `COMPOUND` (20, 18, 44, 26) and the yard (`_in_yard`, `_in_the_yard`, `dead_inside`, `inside_school`, 62, 81, 1129, 1475, 1481, 1761) | sim.gd | overrides read `base.compound()`, `base.yard_rect()`; **no edit of sim.gd** | WP5 |
| A3 | the compound's middle (42, 32) as where the dead go and where the night is "from" | `waves.direction_name` (static, 347), `waves._arrival_seconds` (456), `nights.YARD_MIDDLE` used by sim.gd 1755, 1770 | **H2** (below) | WP5-A |
| A4 | the bell turns every wanderer into an attacker | sim.gd 1628 | **H3** | WP5-A |
| A5 | the gate is wall section 2 (`gate.SEGMENT`) and an open gate lets the dead in | sim.gd 1315, 1667; gate.gd | the school's `gate` is `enabled = false` in the town; **H4** `_open_to_dead(seg)` | WP5-A |
| A6 | the night's cap counts every dead alive | waves.gd 566 | **H6** | WP5-A |
| A7 | the compound's wall sections are ids below 100, the lots' above (`Lots.FIRST_SEGMENT_ID`) | sim.gd 1442, 1576; waves `target_sections`; avatar_bot | base segments take ids 10 to 99 (door barrier 10, 11; slots 12 on); the gate is just one of them | WP5 |
| A8 | stations, posts, resting spots, `_face_of` thresholds are in `stations.json` / `posts.json` | jobs.gd 87, 132 | **H8** `jobs.install_layout` | WP5-A |
| A9 | plots, buildings, art are in `plots.json` / `buildings.json` / `building_art.json` and the lots' mouths | build.gd 80, 130 | **H7** `build.install_layout`, slot kit hook in `_finish` | WP5-A |
| A10 | lots, the town board (`town.on`), streets, vehicles, scavenge, convoy, the drive | lots.gd 150, 696; town.gd 159; streets.gd | **H9** `sim.is_one_house()` guards in `Lots.begin/load_state`, `Town.begin`; `streets.enabled = false`; no car | WP5-A |
| A11 | the forecast and the lookout speak of tonight's wave | tactics.gd 351, 433 | **H10** gate by `scenario.forecast_on()` | WP5-A |
| A12 | SaveGame needs the same segments in a fresh sim and people from the roster | save_game.gd 457, 475 | **H11** one generic `prepare_load` hook | WP5-A |
| A13 | school-bound views: `BaseLife` (flags, bell, dog, mast), `DressingNode`, `ParkingNode`, `GateNode`, `BuildNode` art, `lighting` lamps from `data.lights`, `overlay` base marks, `StreetAir`, the title yard | main.gd 471 to 496, 2671 | each is disabled or not created in a town run (`life_view.set_enabled(false)`; dressing/parking are `town.on` only, so absent; **`GateNode` is not created**: its `setup` makes the lever at the school's (36, 21.6) before it looks for the gate's holder) | WP1 |
| A14 | `jobs.person_added` gives a post to everyone; fewer posts than people falls back to the first | jobs.gd 141, 178 | the layout lists enough posts (at least 8, behind the fence line, built or not) | WP5 |
| A15 | `recruits.begin` needs three people at least (`clampi(crew_start, 3, 6)`) | recruits.gd 83 | the scenario sets `recruits.small = true` itself, after `start_run` | WP6 |
| A16 | the day is 24 / `min_per_sec` minutes (3.0: 8 real minutes) | `d.minPerSec` | the scenario sets `sim.min_per_sec = 2.0` (data) | WP6 |
| A17 | the music's `fortress` context is "a Big Night" | main.gd 2693 | the part adds `ctx.fortress = scenario.attacks_on()` | WP7 |

**The eleven neutral hooks** (all by WP5 phase A, in the first hour, merge #1; each returns today's value in every non-town game; none draws from `sim.rng`; none adds an event):

| Hook | File: function | Change |
| --- | --- | --- |
| H1 | sim.gd next to `is_demo` (349) | `func is_one_house() -> bool: return false` |
| H2 | sim.gd | `func base_center() -> Vector2: return Vector2(42.0, 32.0)` and `func yard_middle() -> Vector2: return nights.YARD_MIDDLE`; `_update_zombie`'s `breach` arm (1755) and `_come_in` (1770) call `yard_middle()`; `waves.gd` `direction_name(v, centre := Vector2(42.0, 32.0))` (static, a default), `heading_text` and the alerts in `update` pass `sim.base_center()`, `_arrival_seconds` uses `sim.base_center()` |
| H3 | sim.gd `_update_zombie` `wander` arm (1628) | `if bell_rung and _wanderers_rally() and rng.randf() < dt * 0.1` with `func _wanderers_rally() -> bool: return true` (the order `bell_rung`, the call, then the draw keeps the dice identical) |
| H4 | sim.gd `assign_slot` (1306, 1315), `attack` arm (1667), `yard_open` (1444), `_breached` (1578) | two tiny functions with today's bodies: `func _any_gate_open() -> bool: return gate.lets_dead_in()` and `func _is_open_gate(s) -> bool: return int(s.id) == gate.SEGMENT`; `assign_slot`'s `var gate_open: bool = gate.lets_dead_in()` becomes `_any_gate_open()` and its test `gate_open and int(s.id) == gate.SEGMENT` becomes `gate_open and _is_open_gate(s)`; the `attack` arm's `(int(s.id) == gate.SEGMENT and gate.lets_dead_in())` becomes `(_is_open_gate(s) and _any_gate_open())`; the `return gate.lets_dead_in()` ends of `yard_open` and `_breached` become `return _any_gate_open()`. (The school's `gate` is `enabled = false` in the town, so its answers are false; `TownRules` overrides the two functions with the base's gate: `perimeter.gate_open()` and `seg.kind == "gate"`. Replacing only the per-section test would not work: the once-computed `gate_open` would short-circuit it.) |
| H5 | (kept free: the planner's slot for a hook a package finds it needs; ask the integrator) | |
| H6 | waves.gd `update` (566) | the loop that counts `alive` becomes `var alive: int = sim.alive_for_cap()`; sim.gd `func alive_for_cap() -> int` holds the same loop |
| H7 | build.gd | `func install_layout(plots: Array, buildings: Array, art: Dictionary = {}) -> void` (adds the layout's plots and catalogue entries, `version += 1`, refreshes; remembered so `_reset()` drops them) and `clear_layout()`; `_finish` (599): `if pl.kind == "slot": sim.perimeter.on_built(pl, id); return` after the `wall_kit` branch; `refresh_plots` (185) and `why_not` (413) also ask `sim.get("perimeter")` (null in every other game: `perimeter.unlocked(pl)` hides/locks a slot plot) |
| H8 | jobs.gd | `func install_layout(stations: Array, posts: Array, rest: Dictionary) -> void` (replaces `_stations`, `_posts`, `_base_posts`, `_rest` and the by-id maps, `post_ids` of everyone are re-made, `settings` kept for stations of the same id) and `clear_layout()` (reloads the file's data); a post carries its own `face` (the layout gives it; `_face_of` is the school's fallback only) |
| H9 | lots.gd `begin` (151) and `load_state` (696); town.gd `begin` | `and not sim.is_one_house()` |
| H10 | tactics.gd `_tell_the_forecast` (433), `forecast` (351) | return early when `sim.scenario.has_method("forecast_on") and not sim.scenario.forecast_on()` |
| H11 | save_game.gd `apply` (457) | `var town_before = sim.prepare_load(data) if sim.has_method("prepare_load") else null` before the others, `sim.restore_load(town_before)` where the others are restored on a refused save |
| H12 | interact.gd `candidates` (before `_ordered`, 190), `use` (the `match`, 300), `_ordered` (211) | `out.append_array(sim.uses.candidates(p) if sim.get("uses") != null else [])`; a default arm `_: if sim.get("uses") != null: r = sim.uses.use(c)`; the new kinds ("container", "door", "claim", "bed", "stash", "rescue", "slot", "gate_base") get ranks in the order list (owner of the lines: WP3) |

(Eleven are real: H1 to H4, H6 to H12; H5 is spare.)

**The generated base is the school's mechanism with data in place of the files.** `stations.json` and `posts.json` become the layout's `stations`, `posts`, `rest` (H8); `plots.json` / `buildings.json` become the layout's `plots`, `buildings` (H7); a wall section made in play is `sim.add_segment(def)` (sim.gd 1350: `def` = id, kind, side, from, to, name, hp, tiles, center, slots, obj, art; the world draws it through `on_segment_added`, as the lots' walls since round 9; `lots.gd` `_make_section` is the model); its dead's places are `slots` ({x, y, ax, ay, face}); night shooters stand at `jobs` posts; a tower is the existing `watchtower` building (`reach_bonus` 3, `reach_radius` 4: build.gd 380), a floodlight the existing `floodlights` (`night_reach_mult` 1.12); the avatar mends with E through `nights.wall_candidates` (generic over `sim.segments`); the dead choose slots by distance and crowd in `assign_slot` (generic over `sim.segments`).

### 1.6 The base layout format (D5)

`BaseLayout.make(town: Dictionary, house_id: int, opts := {}) -> Dictionary` (pure, deterministic, `scripts/town/base_layout.gd`, WP5) from the claimed house's `lot` and `rect`, `front`, doors, rooms and the free tiles round the lot. **`validate(layout, town) -> Array` (list of problems, empty is good)** is the unit test. The shape (tile coordinates; Vector2 points, Rect2i tiles; everything JSON-friendly when saved as `{house}` only: the layout is re-made on load, not saved):

```
{
  "version": 1, "house": int, "kind": "small|medium|terrace|shop", "front": "N|S",
  "plot": Rect2i,                    # the lot: the perimeter runs on its border
  "center": Vector2, "yard_middle": Vector2,
  "compound": Rect2,                 # the plot grown by 3 tiles: "at the base" / "outside" tests
  "claim_spot": Vector2,             # inside by the front door: where E claims
  "interior": [ {"id": "bed"|"stash"|"radio"|"bench"|"cot1"..., "kind": prop kind of the art kit, "pos": Vector2, "room": int, "face": "N|E|S|W"} ],
  "stations": [ {id, name, where, pos: [x, y], seats, skill, icon, blurb, what, work, settings, requires?} ],   # stations.json shape: bench, builders, radio, watch, infirmary
  "rest": {"what": "Resting", "work": "rest", "spots": [{"pos": [x, y], "face": "S"}]},
  "posts": [ {"id", "name", "pos": [x, y], "what", "face": "N|E|S|W", "slot": slot id or ""} ],       # at least 8, in the yard just inside the perimeter
  "doors": [ {"id": "door_front", "tiles": [Vector2i...], "hp": 90} ],                              # the house's exterior doors: barred at the claim (segments 10, 11)
  "slots": [ {"id", "kind": "fence|gate|tower|floodlight|door", "name", "rect": Rect2i, "dir": "h|v", "side": "N|E|S|W",
              "unlock": {"crew": n}, "kits": [kit ids], "dead_places": [{x, y, ax, ay, face}], "post": post id or ""} ],
  "plots": [ the same slots as Build plots: {id, name, kind: "slot", lot: "", home: "", n: 1, why, pos: [x, y], size: [w, h], work: [x, y], kits, dir, side, unlock} ],
  "buildings": [ catalogue entries: {id: "kit_fence", name, blurb, scrap, work, max: 99, requires: "", effects: {}, slot_kit: "fence", hp, length} ... ],
  "spawns": [Vector2],               # the night's entrances: 4 walkable road tiles 35 to 60 tiles from `center`, one to each side
  "ring": {"free": int, "blocked": int}   # how many perimeter tiles were free (a report for the tests)
}
```
**Kits** are `assets/data/base_kits.json` (WP5): `{"kits": {id: {name, blurb, slot_kinds, hp, scrap, work (builder-hours), length, stand, art, effects, post}}, "unlock": {...}}`. Starting numbers (tuned by WP8): fence 120 hp / 5 scrap / 3 hours; fence_strong 260 / 12 / 7; gate 200 / 14 / 8; door_plank (the barred door's upgrade) 90 / 4 / 2; tower = `watchtower` (36 scrap / 32 hours today: a cheaper `tower_small` entry of 22 / 14); floodlight = `floodlights` (28 / 20 today: 16 / 8). A slot's unlock stage is the **crew count** (people alive including the avatar): 1 (the doors and two fence sections at the front), 2 (the front fence), 3 (sides, gate, a tower), 4 (the back, the second tower, floodlights).
**What the claim installs, in order** (`base.claim`, WP3, section 2.3): layout made; `build.install_layout(layout.plots, layout.buildings)`; `jobs.install_layout(...)`; `perimeter.activate(layout)` (door segments, the posts list, the first unlocks); `sim.spawns = layout.spawns`; props to draw (`base.props()`); the claim banner and event.
**The start house is special.** The demo's base is the start house (hand-placed). The generator (WP1 addendum 3) keeps its lot **unfenced with a clear ring** (no tree, no prop, no decal on the border of the lot and one tile inside) so that the ring of slots is always free; for any other house the layout builder takes the free tiles it finds (`ring.free`) and drops the slots that do not fit. Only the start house can be claimed in the demo build (`base.claim` accepts any house; the demo offers the claim only where `houses.start_house() == h`); the others are the "later" of the spec.

### 1.7 Rescue encounters and the community (D7)

**Record** (`sim.rescue.list()`, WP4): `{id: "r0".."r11", house, room, pos: Vector2, ring, def: Dictionary (a roster-shaped def from `recruits.make_def(i)`, made once at start from the run's seed, so the same run meets the same people), state: "hiding"|"wary"|"spoken"|"joined"|"lost", trust0, asked: bool}`. The 12 candidates are the generator's `town.rescue` (near to far); WP4 data `assets/data/rescue.json` holds their lines and the choices.
**States.** *hiding*: the survivor is in a room that is not revealed; no pawn is drawn. *wary*: the avatar's room is theirs (or the door is open), the pawn is drawn (an ordinary person pawn from `sim.make_person(def)`, held by the module, not in `sim.people`, drawn by `bystander_view.gd` through `PawnNode`, with a "wary" pose: weapon lowered, facing the avatar), nobody attacks them, the E candidate "Talk to <name>" appears within 1.9 tiles *unless the house still has dead in the survivor's room* (they say "Get them out first" in the card, no choices). *spoken*: the card has been shown; the card's choices (from the data): **Come with me** (needs the base claimed and `recruits.housing_free() >= 1`), **Stay here, I will come back** (the survivor stays, `spoken`), **Take this** (a gift of one food or one ammo: +trust for the later job, optional). *joined*: `sim.add_person(def)` (the existing path: morale, traits, bonds, jobs `person_added`, skills), `recruits.arrived.append(def)` (so `recruits.prepare_load` rebuilds them on a load: round 16's mechanism), the person appears at the base's front gate spot after `ARRIVE_MIN` game minutes (distance x 0.4, at least 3: "they go ahead"; no escort game), a pack (scrap, ammo, food from the data), `jobs.fill_empty()`, an event and `scenario.on_survivor_joined(p, count)`. *lost*: off by default (`rescue.json: lost_after_days: 0`); if on, the survivor of a house still full of dead after N days is lost with a News line. Survivors are never lost before the fourth in the demo (the spec's open question: answered "no" for the demo; the state exists for later).
**Radio.** A joined person is a normal contact of `sim.radio` (the verbs follow, hold, cover, search, post, the wheel, trust, refusals, the News): the radio panel and the wheel already iterate `sim.people`; no new code but the first-contact line ("<name> is on the radio now"), a News entry (`radio.log_news`) by the rescue module.
**Jobs.** The layout's stations are the jobs: bench (2 seats), builders (3), radio (1), watch (the tower post, 1), infirmary (1). `jobs.fill_empty()` places new people by skill; a rescued survivor's def names a `station` of its role (`recruits.json`), which `person_added` honours when there is a seat.

### 1.8 The fourth-rescue trigger and what nights are (D8)

`OneHouse` (WP6, the scenario module, `sim.scenario`) owns the stage machine: `alone` (start) -> `cleared` (the house is clear, claim offered) -> `claimed` -> `growing` (1 to 3 rescued) -> `fortify` (the fourth rescued: `attacks_on`, "four voices on the radio, the dead will come every night from the next dusk") -> `held` (the first attack night survived: the run is won, end card). Data: `attack_from_rescue: 4`, `attack_first_night: "next dusk"`.
**Before the trigger:** `waves.enabled = false`; `posts_manned()` false; `forecast_on()` false (no lookout forecast, no "The dead are coming" alert); the bell still rings at dusk (the sound is the soundscape's) but `TownSim._town_events` rewrites its banners (the school's "Everyone to the wall" and "Hold the wall until dawn" become "Night falls" / "Be indoors: the streets are not safe in the dark") and removes the `horde` alert; the wanderers stay wanderers (H3); the street is more dangerous by night (section 1.3).
**After:** `waves.enabled = true`; `OneHouse.night_mult(day)` sizes the night (the demo.json pattern: `night_mult`, `big_night_for`, `total_days`, `victory_banner`, `report`); the first attack is announced at 17:00 by the forecast (`forecast_on()` true, a person at the `watch` post or the avatar), the dead come from `layout.spawns` (4 entrances on the streets), `posts_manned()` at the bell, the avatar fights and mends. The **night is held** when the dawn comes with the avatar alive, no dead inside the house and at least one fence/door of the base standing (data: `held_rule`); a breach into the house that is not mended by dawn, or the avatar's death with nobody to take over, is the ordinary game over. The end card follows the first held night.
The Big Night machinery of the school (milestone nights, plated brutes) is **not** used for the first attack; `big_night_for` returns `{}` for the demo's one night unless `one_house.json` asks for a brute (the lab decides: WP8).

### 1.9 A solo start with the community modules (D9)

At `OneHouse.begin(sim)` (after `start_run`): `recruits.small = true` (`briefing`, `priorities`, `initiative`, `policies`, `problems`, `dilemmas`, `relations`, `specialists` all use `recruits.small` and `player_id` in `active()`), `recruits.queue.clear()` and `next_call_day = 99999` (no caller by radio: the radio does not recruit in the town), `town.on = false` (no board), `lots.on = false`, `streets.enabled = false`, `storyteller.enabled = false` (its noon cards and the generator at (46.8, 28.2) are the school's), `gate.enabled = false`, `levels.enabled = false`, `waves.enabled = false` until the trigger, `seasons.campaign = false`. Then **`OneHouse.apply_stage()`** runs on every change of the crew count and sets each module's `enabled` from `one_house.json: modules_from_crew` (default: `briefing` 3, `priorities` 3, `initiative` 3, `relations` 4, everything else off for the whole demo): the same `enabled` pattern the demo and Orientation Day use, so no module is edited. With one person: the radio panel lists nobody and says "Nobody is on the radio yet" (WP7), the jobs page has only the avatar (who is never given a job: `Sim._update_person` hands the player to `avatar.update`), the morning card is silent, `supplies` feeds one.

### 1.10 Time, sleeping and the clock (D10)

`sim.min_per_sec = 2.0` for the town (a game hour is 30 real seconds; the day, 06:30 to 19:00, is about 6 real minutes; the night about 5; the school's 3.0 would give 4-minute days, too short to clear a house, walk to a rescue and come back). The player passes the quiet nights in the bed (E: "Sleep until dawn", WP3 `sleep`): the module refuses with a reason when an attack is on and it is dusk to dawn, when a dead one is awake within 20 tiles of the house, or when the avatar is hurt-and-bleeding; it runs `sim.fast_forward(minutes, 300)` a frame at a time (the effects are a sink, the noise events are dropped: the existing mechanism of round 17), stops when a dead one comes within 12 tiles or a shot is heard, heals a little (`medical`), and ends at 06:30 or the chosen hour. The sleep fade and the "You slept until dawn" line are WP7's.

### 1.11 Saves (D11)

A save is the existing `SaveGame` JSON plus the modules (every module held in a script variable of `TownSim` with `save()` and `load_state()` is found by `SaveGame._modules`: `houses` (nothing), `field` (the compact records), `clearing`, `search`, `base` (only `{claimed, house, props...}`), `sleep` (nothing), `rescue` (states, joined ids), `perimeter` (built slots and kit ids, gate state), the scenario `OneHouse` (stage, counters, the clock of the end)). **Before reading** (`SaveGame.apply` through H11 -> `TownSim.prepare_load(data)`): `recruits.prepare_load` (the rescued are made from `recruits.arrived`), `base.prepare_load` (re-installs the layout of the saved house into `build`, `jobs`, `spawns`), `perimeter.prepare_load` (re-makes the segments of the built slots **by id** so that `SaveGame._parse` finds them: the lots' `prepare_load` is the model), then `restore_load` if the save is refused. The town itself is **not saved**: it is made again from `seed` (`TownGen.make(seed)` is deterministic: `TownGen.digest`), so `OneHouse` saves `town_seed` and `size`. A load is `run.load` in the Engine meta as today; `main._ready` calls `OneHouse.is_save(saved)` -> `OneHouse.install(sim)` before `SaveGame.apply`, as `DemoRun.is_save` does (WP6).
The save version stays 3; a town save is recognised by its scenario kind `"one_house"`; a school build refuses it (`SaveGame.is_loadable` -> the kind is unknown there: it must say "needs the town"; WP6).

### 1.12 The no-avatar promise and the golden tests (D12)

`tests/test_nights_regression.gd` and `tests/test_round20_noavatar.gd` (and `tests/golden/harness_noavatar.json`) play the school's whole game with the real `Sim`. They stay byte-identical because: (1) **no town class is ever instantiated by them**; (2) the eleven hooks return the old value and make no draw from `sim.rng` and add no event (tested: each hook's neutral value in `tests/test_oh_hooks.gd`, WP5); (3) every new rule lives in a new module reached only through `TownSim`'s variables; (4) in a school game `sim.get("uses")`, `sim.get("perimeter")` are null. **Rules for everyone:** never edit a golden test or `golden/*.json`; never re-pin; if one fails, a hook is not neutral. Run `--only=test_nights_regression:` and `--only=test_round20_noavatar:` (about a minute each; the first runs three games in worker processes) after any edit of sim.gd, waves.gd, build.gd, jobs.gd, tactics.gd, lots.gd, town.gd, interact.gd or save_game.gd (WP5-A, WP3's two lines); everyone else leaves them to the integrator.

### 1.13 Soft wiring: modules, parts, uses, events (D13)

**Sim modules** (`TownSim.PARTS`, a constant table pre-filled by WP1 with *all* names; a missing file is skipped, so a package can land any time): each is a `RefCounted` with `setup(sim)`, `start()`, `update(dt)`, `save()`, `load_state(d)`, optional `prepare_load(data)` / `restore(before)` / `person_added(p)`, and `enabled`.

| Var on `sim` | File | Owner |
| --- | --- | --- |
| `houses` | scripts/town/houses.gd | WP1 |
| `field` | scripts/town/dormant_dead.gd | WP1 |
| `clearing` | scripts/town/clearing.gd | WP3 |
| `search` | scripts/town/search.gd | WP3 |
| `base` | scripts/town/base.gd | WP3 |
| `sleep` | scripts/town/sleep.gd | WP3 |
| `uses` | scripts/town/uses.gd | WP3 |
| `rescue` | scripts/town/rescue.gd | WP4 |
| `perimeter` | scripts/town/perimeter.gd | WP5 |
| `scenario` (replaces `Scenario`) | scripts/town/one_house.gd | WP6 |

**View parts** (`TownGame.VIEW_PARTS`, same soft wiring; `scripts/town/town_game.gd` is the facade `main.gd` holds as `town`, WP1): a part is any object with any of `on_ready(main)`, `on_frame(dt)`, `on_sync_views(view: Rect2)`, `pawn_visible(entity) -> bool`, `on_event(e: Dictionary)`, `music_context(ctx: Dictionary) -> Dictionary`, `modal() -> bool`, `on_key(ev: InputEvent) -> bool` (true: used it). `main.gd` calls the facade at nine fixed places (one line each, WP1 makes them all): `_ready` (after the HUD), `_process` (after `_sync_views`), `_sync_views` (twice: the sync and each pawn's visibility), `_handle_events` (inside the event loop), `_music_context`, `avatar_hands_off`, `_unhandled_input` (first line), `_clamp_camera` (the town's bounds). Parts: `house_view` (WP2), `base_props_view` (WP2), `bystander_view` (WP4), `rescue_card` (WP4), `town_hud` (WP7), `sleep_fade` (WP7), `town_audio` (WP7).

**E uses** (`sim.uses`, WP3): `register(provider)`, `candidates(p) -> Array`, `use(c) -> Dictionary`, `progress() -> Dictionary` ({"label", "t", "of"} of the session in hand, "" label for none). Providers (each a sim module with `candidates(p)` and `use(c)`): `clearing` (kind "door": "Look in"), `search` ("container"), `base` ("claim", "bed", "stash"), `sleep` (the bed), `rescue` ("rescue"), `perimeter` ("slot": nothing to use; "gate_base": open or shut the base's gate). A candidate has the shape of `Interact.candidates` ({kind, id, label, pos, dist, ok, why}) plus optional `session: true` (the use begins a session that ends when the avatar walks, fires or is hurt, as the bench and the wall: the progress ring reads `uses.progress()`).

### 1.14 Searching containers (D14)

`RaidRun` (825 lines) is a wrapper around a place's sim and cannot be reused in the colony's sim; the rules it uses are small (`begin_search`, `_search_step`, `_open`: raid_run.gd 325, 637, 663). `sim.search` (WP3) re-implements them against `sim.houses.containers_of(h)`: the avatar stands within 0.9 tiles of the container's `pos`, E begins a session of `search_s` (4 s; skill-free), hands off the keys end it, the loot goes **straight into `sim.stock`** (no bags in the demo: the stash *is* the stock; `base`'s "stash" use shows the stores), the container is `looted` (saved), `{"type": "searched", "container", "house", "loot"}`. A looted container is drawn open (WP2, a flag read through `search.is_looted(id)`).

---

## 2. Contracts (frozen at v1: add, never change)

### 2.1 Town data (from the generator, WP1; already in `feature/town-core`)
`TownGen.make(seed: int, opts := {}) -> Dictionary` with `data`, `houses`, `rooms`, `containers`, `dead`, `start`, `rescue`, `tile_house`, `tile_room`, `streets`, `stats` as the header of `town_gen.gd` says. **WP1 addendum** (section 3, WP1) adds: `opts.blocks` (2 = a 64 x 64 test town; default 6), the start house's lot unfenced with a clear ring, 2 to 4 dead round each rescue spot, `houses[i].address`.

### 2.2 Sim modules (signatures)
```gdscript
# sim.houses (WP1)
func house_at(x: float, y: float) -> int            # -1 outside every house's walls
func room_at(x: float, y: float) -> int             # -1 on a wall, a doorway, outside
func house(id: int) -> Dictionary
func room(i: int) -> Dictionary
func rooms_of(house_id: int) -> Array               # room indexes
func doors_of(house_id: int) -> Array
func containers_of(house_id: int) -> Array
func start_house() -> int
func nearest_house(at: Vector2, only: Callable = Callable()) -> int
func dead_in_room(room: int) -> int                 # not killed, awake or dormant, by where they are now
func dead_in_house(id: int) -> int

# sim.clearing (WP3)
func is_revealed(room: int) -> bool
func reveal(room: int, why: String = "") -> bool    # true when it was news
func is_clear(room: int) -> bool
func house_clear(h: int) -> bool
func visited(h: int) -> bool
func explored() -> Array                            # house ids, for the map
func inside_house() -> int                          # the avatar's house, -1 outside
func claimable(h: int) -> Dictionary                # {"ok": bool, "why": String}

# sim.base (WP3)
var claimed: bool; var house: int; var layout: Dictionary
func claim(h: int) -> Dictionary                    # {"ok", "why"}
func center() -> Vector2; func compound() -> Rect2; func yard_rect() -> Rect2; func yard_middle() -> Vector2
func spawns() -> Array; func claim_spot() -> Vector2; func props() -> Array; func at_base(p) -> bool
func prepare_load(data: Dictionary); func restore(before)

# sim.search (WP3)   func is_looted(id: String) -> bool;  func state(id: String) -> Dictionary
# sim.sleep  (WP3)   func can_sleep() -> Dictionary;  func begin(until: String = "dawn") -> Dictionary;  func active() -> bool;  func advance() -> void
# sim.uses   (WP3)   as in 1.13

# sim.rescue (WP4)
func list() -> Array;  func get_record(id: String) -> Dictionary
func near(p, r: float = 1.9) -> String             # id or ""
func talk(id: String) -> Dictionary                # the card: {"id","name","role","line","portrait","choices": [{"id","text","ok","why"}]}
func choose(id: String, choice: String) -> Dictionary   # {"ok","line","joined": bool}
func joined_count() -> int
func bystander(id: String)                          # the Person to draw, or null

# sim.perimeter (WP5)
func slots() -> Array             # [{"id","kind","name","rect","state": "locked|open|ordered|building|built|broken","kit","hp","max_hp","unlock","why_not","plot"}]
func kits_for(slot_id: String) -> Array             # [{"id","name","blurb","scrap","work","hp","ok","why"}]
func order(slot_id: String, kit_id: String) -> bool;  func cancel(slot_id: String) -> bool;  func demolish(slot_id: String) -> bool
func on_built(plot: Dictionary, building_id: String); func unlocked(plot: Dictionary) -> bool
func activate(layout: Dictionary); func no_outer_wall() -> bool
func gate_open() -> bool;  func toggle_gate() -> Dictionary
func built_count() -> int; func sections() -> Array; func prepare_load(data: Dictionary); func restore(before)

# sim.scenario = OneHouse (WP6)
static func begin(sim); static func install(sim); static func is_save(data: Dictionary) -> bool
func stage() -> String; func rescued() -> int; func crew_count() -> int
func attacks_on() -> bool; func forecast_on() -> bool
func objective() -> Dictionary      # {"id","text","sub","at": Vector2 or null,"step": int,"of": int}
func guide() -> Dictionary          # {"id","text","goal","done": bool} the lesson now, {} when over
func on_survivor_joined(p, count: int); func on_house_clear(h: int); func on_claimed(h: int)
func report() -> Dictionary;  func end_card() -> Dictionary   # {"title","line","stats": [[label, value]...]}
func night_mult(day: int) -> float; func big_night_for(day: int) -> Dictionary; func total_days() -> int; func victory_banner() -> Array
```
`OneHouse` does **not** define `is_demo()` (the school demo's views key off it).

### 2.3 What `base.claim(h)` does (WP3, the order is the contract)
refuse unless `clearing.house_clear(h)` and the avatar is inside `h` (within 6 tiles of `claim_spot`) and not already claimed; `layout = BaseLayout.make(houses.town, h)` (WP5; a stub with interior only until it lands); `build.install_layout`; `jobs.install_layout`; `perimeter.activate(layout)` (if present); `sim.spawns = layout.spawns`; `claimed = true`; `scenario.on_claimed(h)`; events `{"type": "claimed", "house": h}` and a banner "This house is yours"; the claim costs nothing.

### 2.4 Events (all in `sim.events`, read by `main._handle_events` and the parts)
`{"type": "entered"|"left", "house": h, "first": bool}`; `{"type": "room_revealed", "room": i, "house": h, "name": s}`; `{"type": "room_clear", "room": i, "house": h, "name": s}`; `{"type": "house_clear", "house": h}`; `{"type": "searched", "container": id, "house": h, "loot": {}}`; `{"type": "claimed", "house": h}`; `{"type": "sleep", "on": bool, "why": s}`; `{"type": "rescue_seen"|"rescue_talk"|"rescue_joined"|"rescue_waits"|"rescue_lost", "id": s, "who": person id (joined), "count": n}`; `{"type": "fourth"}`; `{"type": "attacks_on", "from_day": d}`; `{"type": "slot_ordered"|"slot_built"|"slot_lost", "slot": id, "kit": id}`; `{"type": "held", "night": n}`. The existing `banner`, `bell`, `built`, `shot`, `thud`... stay as they are.

### 2.5 Data files (one owner each, so that nobody edits another's file)
`assets/data/town_art.json` (art builder; read only by `TownArt`, WP2), `assets/data/base_kits.json` (WP5), `assets/data/rescue.json` (WP4), `assets/data/one_house.json` (WP6: min_per_sec, start stock, `modules_from_crew`, attack rule, night numbers, guide steps, end card words), `assets/data/one_house_tuning.json` (WP8: overrides of numbers found by the lab, merged by `OneHouse` over `one_house.json` key by key).

---

## 3. Work packages

Naming: tests are `tests/test_oh_<name>.gd` (at most five tests each, lean), run with `--only=test_oh_<name>:`. Sizes: S under 2 hours of builder time, M 2 to 4, L 4 to 8.

### WP1. Foundation integration (owner: the foundation builder, RUNNING) [L]
**Goal.** The town is a real map in the real game: generated, drawn in chunks, walkable by the avatar in the colony's `Sim`, with the dormant dead, the houses registry and the facade for everyone else.
**Owns.** `scripts/town/*` (`town_gen`, `town_world`, `town_chunk_paint`, `town_roofs`, `dormant_dead`, `town_sim` rebased, new `houses.gd`, `town_boot.gd`, `town_game.gd`, `town_scene.gd` kept as bench), `tools/town_bench.gd`, `tests/test_oh_town.gd`, the end of `tests/helpers.gd` (`town_game`).
**Hooks in shared files.** `main.gd`: `_ready` top (`TownBoot` factories for data, world, sim; the run meta `town`), `_ready` after the HUD (`town = TownGame.make(self)`; `town.on_ready(self)`), `_process`, `_sync_views` (x2), `_handle_events`, `_music_context`, `avatar_hands_off`, `_unhandled_input`, `_clamp_camera` and `_min_zoom` (the town's bounds), `_parse_args` (`--town[=seed]`, `--town-spike`); the school-bound views off (A13). **Nobody else edits those lines.**
**Produces.** `TownGen.make`; `TownBoot.data(run) / .world() / .sim(data, world, fx)`; `TownSim` (extends `town_rules.gd`; until WP5-A lands, extends `sim.gd` and the extends line is swapped by one line afterwards); `sim.houses`, `sim.field` (with `noise`, `light`, `pause_wake`, `night_mult`, `active_cap`, `save/load_state`, `sleep_all`, `dead_in_room/house`); `TownGame` (nine hooks, `VIEW_PARTS` table with every part of section 1.13); `TownSim.PARTS` table; `Helpers.town_game(seed := 1, opts := {}) -> {"sim", "world", "town"}` (a mini town by default: `opts.blocks = 2`, one start house, a few dead, the avatar Ruth as player, `OneHouse` absent); the save of the field; the loading card.
**Consumes.** Nothing from the others (every part is soft-wired).
**WP1 ADDENDUM: paste this to the foundation builder now.** (1) `TownSim` must extend `res://scripts/sim/sim.gd` (the colony), not `raid_sim.gd`; keep the spike's overrides (`_separate` grid, `chase`, `still`, `_shot_noise` -> `field.noise`, `_hunt_allowed` true); do not copy `nights_on = false`. (2) `TownGen.make(seed, {"blocks": 2})` makes a 64 x 64 town with 4 blocks, the start house in it, 2 rescue spots (for tests under 2 s). (3) The start house's lot is **unfenced**, its border and the tile inside it free of trees, props and decals (a ring of free tiles: the perimeter goes there); its three dead stay inside; each rescue spot has 2 to 4 dead in its house, one of them in the survivor's room. (4) `houses.gd` as in 2.2 and `sim.houses`. (5) The facade `town_game.gd`, the `PARTS` and `VIEW_PARTS` tables, the nine one-line hooks in `main.gd`. (6) `field.pause_wake`, `field.night_mult` (a float, 1.0), `field.sleep_all()` called from `TownSim.pre_save()`; `field.save()` compact as now. (7) `Helpers.town_game`. (8) Keep `town_scene.gd` working under `--town-spike`.
**Depends on.** Nothing. **Can start now:** running.
**Acceptance (at most five).** (1) `TownGen.digest` of seed 1 is stable and `make(1, {"blocks": 2})` has a start house with three dead and an unfenced clear ring (`ring.free == ring.total`). (2) `field` wakes the records within `wake_r` of an avatar, never above `active_cap`, sleeps them again far away, and a killed one never wakes; `save()` -> `load_state` round trip keeps counts. (3) Kill the three dead of the start house through the real `sim` loop -> `houses.dead_in_house(start) == 0`. (4) `Helpers.town_game` + 600 steps of the avatar walking out of the door and down the street: no logged error, `sim.zombies.size() <= active_cap`, mean step under 4 ms. (5) `Main` boots a town run (`restart` callback pattern of `tests/`) to the first frame with `sim` a `TownSim`, no school view node alive (`BaseLife` disabled, no `GateNode`, no dressing or parking node).

### WP2. The houses on screen: roofs, rooms, doors, props [M]
**Goal.** What the spec's arc 1 shows: a roof that fades when you step in, dark rooms behind closed doors, doors that swing, furniture and base props from the art manifest; and the rule that what is in an unrevealed room is not drawn.
**Owns.** `scripts/render/house_view.gd` (the part: roofs, veils, doors), `scripts/render/base_props_view.gd` (the part: bed/stash/radio/bench at a claim and the open/closed look of containers), `scripts/render/room_veil.gd`, `scripts/render/door_node.gd`, `scripts/town/town_art.gd` (the **only** reader of `assets/data/town_art.json`: `TownArt.roof(kind, variant)`, `.door(kind)`, `.fence(kit, state)`, `.prop(kind)`, each returns `{file, rect, nine, size}` or a placeholder descriptor drawn with flat colours; **WP5 calls `TownArt.fence`**), shaders, `tools/house_view_demo.gd` (a scene to look at one house), `tests/test_oh_view.gd`. `town_roofs.gd` stays as the fallback and the bench's.
**Hooks.** None in shared files (the facade calls the parts; the parts table is already filled by WP1).
**Produces.** The two parts; `TownArt`.
**Consumes.** `sim.houses` (queries), `sim.clearing.is_revealed/reveal/inside_house` and `sim.search.is_looted` (soft: a missing module means "all revealed", "never looted"), `sim.base.props()`, the manifest (when it lands: read its real schema in the first half hour and map it inside `TownArt` only), the avatar's position.
**Depends on.** The `town` dict and `houses` (stub them: it can build its own tiny town with `TownGen.make(1, {"blocks": 2})` from the foundation worktree files). **Can start now: yes** (against a fake sim with the three queries); real wiring waits for WP1's facade.
**Acceptance.** (1) With the avatar's house set to h, the roof of h goes to alpha 0 within 0.3 s and every other roof stays 1.0; leaving restores it. (2) `pawn_visible`: a dead in an unrevealed room of the avatar's house is false, in a revealed room true, outside every house true, in another house false. (3) A door node is open while a pawn is within 1.6 tiles and shut after 0.5 s without one; E-peek (a `clearing.reveal`) wedges it open. (4) A veil per room of the avatar's house exists, hides on `room_revealed`, and no node is created for houses far from the avatar (node count bounded). (5) With no manifest, every descriptor is a placeholder and nothing logs an error.
**Size.** M.

### WP3. Clear, search, claim, sleep, E-uses [L]
**Goal.** Arcs 2 and 3: reveal and clear rooms, the house-clear moment, search containers, claim the house, sleep.
**Owns.** `scripts/town/clearing.gd`, `search.gd`, `base.gd`, `sleep.gd`, `uses.gd`, `tests/test_oh_clear.gd`.
**Hooks.** `interact.gd` (H12: three lines in `candidates`, `use`, `_ordered`) only.
**Produces.** The modules of 2.2 for `clearing`, `base`, `search`, `sleep`, `uses`; the events of 2.4 (`entered`, `left`, `room_revealed`, `room_clear`, `house_clear`, `searched`, `claimed`, `sleep`); `base.props()` (the interior stations to draw); `clearing.explored()`.
**Consumes.** `houses`, `field.dead_in_*`, `BaseLayout.make` (WP5; a stub in the tests and a fallback of its own: an interior-only layout with the avatar's room's bed as the bed), `build.install_layout`, `jobs.install_layout` (H7, H8; absent hooks: the claim calls them with `has_method`), `scenario.on_claimed/on_house_clear` (soft).
**Depends on.** WP1 (`houses`, `field`) and H1, H7, H8, H12 (WP5-A) for the real wiring; **can start now** against `Helpers.town_game` stubs (a fake field with a settable count) and fake hooks.
**Details.** `clearing.update` every 0.25 s (no work while the avatar is away from every house): (a) the avatar's house changes -> `entered/left`; (b) rooms within 1.2 tiles through a door and the avatar's own room are revealed; (c) a revealed room whose `dead_in_room` is 0 and was not clear before -> `room_clear` (once; saved); (d) all rooms of a house revealed and clear -> `house_clear` (once). Claim: the E candidate "Claim this house" appears only at `claim_spot` of a clear house (`ok` false with "There are still dead in the <room>" otherwise); the claim is a 2 s session. Sleep: section 1.10. Search: section 1.14. `uses.progress()` for the ring.
**Acceptance.** (1) Scripted: the three dead of the start house shot one by one -> `room_clear` for each room it empties, `house_clear` after the last, never twice. (2) Walking through a door reveals the far room and `pawn_visible` agrees with WP2's rule data (`clearing.is_revealed`). (3) `claim` refused with a reason while a dead remains, allowed after: layout installed (the plots exist in `build.plots()` when WP5 is in, otherwise the stub's), spawns replaced, `claimed` event once. (4) Search: a container gives its loot to `sim.stock`, is looted afterwards, survives save -> load. (5) Sleep from 21:00 ends at 06:30 with the stores eaten for the hours; with a dead awake 15 tiles away it refuses; with one arriving it wakes the avatar.
**Size.** L.

### WP4. Rescue and the community [M]
**Goal.** Arc 4: survivors in houses, the conversation, joining, their work and radio, the counter and the fourth.
**Owns.** `scripts/town/rescue.gd`, `assets/data/rescue.json`, `scripts/ui/rescue_card.gd` (the card, a part: built on `menu_kit.gd` / `call_card.gd` like `talk_card.gd`), `scripts/render/bystander_view.gd` (the part drawing the survivors as `PawnNode`s with the wary pose), `tests/test_oh_rescue.gd`.
**Hooks.** None in shared files (`recruits.arrived.append` from outside, `sim.add_person`).
**Produces.** `sim.rescue` (2.2), the events `rescue_*`, the card, the counter, `scenario.on_survivor_joined(p, count)` calls (soft).
**Consumes.** `houses` (rooms), `clearing.is_revealed` (to be wary rather than hiding), `field.dead_in_room` (the survivor's room must be clear to talk), `base.claimed` (to join), `recruits.make_def`, `recruits.housing_free`, `jobs.fill_empty`, `radio.log_news`, `scenario.on_survivor_joined`.
**Depends on.** WP1 (`town.rescue`, `houses`); **can start now** with `Helpers.town_game` and fakes for `base` and `scenario`.
**Acceptance.** (1) Start: 12 records, each with a def, same defs for the same seed, none joined. (2) State flow hiding -> wary (room revealed) -> spoken (card) -> joined; "Come with me" is refused with the reason before a claim or without a bed; with dead in the room the card has no choices. (3) A join adds exactly one `Person` (`sim.people.size() + 1`), one `recruits.arrived` def, `jobs` gives them a station when a seat is free, and `scenario.on_survivor_joined(p, n)` is called with n counting. (4) Save -> load keeps the states and the joined people (through `recruits.prepare_load`). (5) The card's model lists the choices with `ok`/`why` and the bystander is drawn only while its room is revealed.
**Size.** M.

### WP5. Base layout, perimeter slots, the sim generalisation, nights [L]
**Goal.** Make the school's machinery work for a generated base: the hooks, the layout, the slots as Build plots, the fence/gate/tower/floodlight, the nightly attacks tuned to be holdable.
**Phase A (first hour, merge #1, small).** The hooks H1 to H4, H6 to H12 of section 1.5 in the shared files, plus `scripts/town/town_rules.gd` (the overrides table of 1.1 for `TownRules`, each delegating to `base`, `perimeter`, `scenario` through `get()` and null checks), plus `tests/test_oh_hooks.gd` (each hook's neutral value; `TownRules` instantiates on a `Helpers.town_game` map; run the two golden tests).
**Phase B.** `scripts/town/base_layout.gd` (+ `validate`), `scripts/town/perimeter.gd`, `assets/data/base_kits.json`, the fence art through `TownArt.fence(kit, state)` (WP2; flat placeholders until then), the `watchtower`/`floodlights` entries of the layout's `buildings`, the barred-door segments (kind `door`, ids 10, 11; **`sim.add_segment` shuts both walking grids**, so right after it the door tiles are opened again for people in `world.solid_p` and `path_p`, the pattern of `Lots._passage_tiles`, lots.gd 303; a door that falls (state 3) is opened for the dead by `open_segment` as the school's doors are), the base's gate (a slot of kind `gate`: a segment whose tiles open when `gate_open`; `perimeter._open_to_dead` is `TownRules._open_to_dead`'s answer), the posts, `spawns`, the night's waves for a base (nothing new in `waves.gd` beyond H2/H6: `layout.spawns` and `OneHouse.night_mult`), mend and breach on the generated sections, and `tests/test_oh_base.gd`.
**Owns.** `town_rules.gd`, `base_layout.gd`, `perimeter.gd`, `base_kits.json`, the tests; edits of sim.gd, waves.gd, build.gd, jobs.gd, tactics.gd, lots.gd, town.gd, save_game.gd (one-line hooks only, **no other edit of those files by anyone else, with one exception: H12 in interact.gd belongs to WP3**).
**Produces.** `BaseLayout.make/validate`, `sim.perimeter` (2.2), `TownRules`, the slots as plots with ids `slot_*`, segment ids 10 to 99.
**Consumes.** `houses`/the town dict, `base.claim` calls `BaseLayout.make` and `perimeter.activate`, `TownArt`, `field` for the dead's room tests (none), `scenario.attacks_on/forecast_on`.
**Depends on.** Phase A depends on nothing and **starts now**; phase B needs WP1's `Helpers.town_game` (a mini town) and `TownSim`.
**Acceptance.** (1) Every hook returns the old value in a school `Sim` (and the two golden tests pass). (2) `BaseLayout.make` on the start house of seeds 1 to 8 validates (slots on free tiles, no overlaps, gate on the front, at least 8 posts, spawns on walkable ground 35 to 60 tiles out, `kits` known). (3) Order a fence on a slot: scrap paid, builders at the work spot finish it in `work` builder-hours, `sim.segments` gains a section with hp and dead places, its tiles shut, `world` told; demolish gives half back. (4) With 12 dead sent at an unbuilt perimeter they claw the barred door and breach it; with the fence built they claw the fence (assign_slot) and a mended fence stops them; the tower raises a post's reach (`reach_bonus_at`). (5) `save -> load` of a base with three built slots restores the segments by id, hp and posts.
**Size.** L (phase A is S).

### WP6. The One House scenario and the game flow [M]
**Goal.** The stage machine, the solo start, the economy, the lessons, the end, the save, the New game.
**Owns.** `scripts/town/one_house.gd` (the scenario `OneHouse`), `assets/data/one_house.json`, `scripts/ui/new_game_menu.gd` and `title_menu.gd` (the town as the New game's start; the demo and school paths stay reachable by flag only), the `--stage=` staging (in `one_house.gd`: `OneHouse.stage_to(sim, "cleared|claimed|rescued2|fourth|night")` for screenshots, the lab and the tests), `tests/test_oh_flow.gd`.
**Hooks in shared files.** `main.gd` `_ready` load/new branch: `OneHouse.is_save` -> `install` before `SaveGame.apply`; the new run -> `OneHouse.begin(sim)` (two lines, in the block that already reads `run`; the factories above are WP1's); `main._parse_args`: `--stage=` (one line to `OneHouse.stage_to`).
**Produces.** `OneHouse` (2.2): `begin`: seed, Ruth the player, 08:00 day 1, `min_per_sec` 2.0, the start stock (one_house.json: ammo 40, scrap 10, food 12, water 18, meds 2), the module switches of 1.9, `apply_stage`; the **guide** (six lessons, data in `one_house.json: guide`): walk (W A S D, 6 steps), aim and shoot (hold the aim button, fire: one dead killed), open a door and enter (the roof fades), clear the dead (`house_clear` progress "2 of 3 rooms clear"), search a container, claim the house (E at the front); `objective()` after the lessons ("Find survivors: 0 of 4", "Fortify the house before dark", "Hold the night"); `attacks_on` at the fourth; the stage events; `report()`; the end at the first held dawn (`sim.over = "victory"`, `victory_banner`); `night_mult`; autosave at `day_start` already works; the save of the stage.
**Consumes.** Everything by soft calls (`sim.get("rescue")`, ...), the data, `hud` through events only.
**Depends on.** WP1's `Helpers.town_game`; **can start now** (it begins as a skeleton the others can run: `begin`, `stage`, `attacks_on`, `objective`).
**Acceptance.** (1) `begin` gives one person, the stock, no waves, `town.on` false, `recruits.small` true, the modules' `enabled` as the table says for crew 1. (2) The guide advances with scripted events and `objective()` follows `stage()`. (3) The fourth `on_survivor_joined` sets `attacks_on` and `waves.enabled` and `forecast_on`; crew changes switch `briefing.enabled` at 3. (4) A fast-forwarded first attack night with the sim's own defenders ends with `sim.over == "victory"` at the dawn when the base stands (a stub base) and `"defeat"` when everyone is gone. (5) Save -> load keeps stage, counters, `min_per_sec`, module switches.
**Size.** M.

### WP7. HUD, UI and audio for the new loop [L]
**Goal.** Everything the player reads and clicks in the town that is not a house on the screen.
**Owns.** `scripts/ui/town_hud.gd` (a part: the objective line with a bearing arrow, the "The house is clear" banner and room-clear toasts, the E prompt with the progress ring from `sim.uses.progress()`, the day/night clock extras, the "Nobody is on the radio yet" line), `scripts/ui/slot_page.gd` (+ a plan drawing, `slot_plan.gd`: a top-down plan of the base with slot markers, pick a slot, pick a kit, "Order", cost and builder-hours, locked slots with their unlock), `scripts/ui/district_map.gd` (the town as a map with explored houses, the base, the survivors you know of, the player: key M, the Map page in a town run; the school's `town_map.gd` is untouched), `scripts/ui/sleep_fade.gd`, `scripts/ui/town_end_card.gd` (the end card from `scenario.end_card()`, built on `demo_end_card.gd`), `scripts/audio/town_audio.gd` (the part: music context, a claim chime, a rescue stinger, door and search sounds from the existing set), `tests/test_oh_ui.gd`.
**Hooks in shared files (WP7 only).** `hud.gd`: a profile call (`hud.set_profile("one_house")`, hides the school-only buttons: town board, scavenge, car) in `setup`'s end; the end-card choice at line 3523 (`sim.scenario.has_method("end_card")` -> `TownEndCard`). (A card of a part, such as WP4's rescue card, holds the avatar's hands through `town.modal()`, which WP1's `avatar_hands_off` hook asks: no edit of `hud.modal_open()`.) `radio_panel.gd`: `page_node("build")` and `page_node("map")` build `slot_page` / `district_map` when `sim.is_one_house()` (two lines each).
**Produces.** The parts of 1.13 for `town_hud`, `sleep_fade`, `town_audio`; the slot page and the map; the end card.
**Consumes.** `OneHouse.objective/guide/end_card`, `perimeter.slots/kits_for/order/cancel/demolish`, `clearing.explored`, `base`, `rescue.list` (known survivors only), the events of 2.4, `sim.uses.progress`.
**Depends on.** WP6's `objective()` and WP5's `perimeter` API are read through the frozen contract; **can start now** with fakes (a fake sim object with those methods).
**Acceptance.** (1) The objective line shows the text of `objective()` and updates on `house_clear`, with the banner shown once. (2) The slot page lists the fake slots with their state, and pressing Order calls `perimeter.order(slot, kit)`; a locked slot shows its reason. (3) The progress ring follows `uses.progress()`. (4) The end card shows `end_card().stats`. (5) `music_context` has `indoors` true in a house and `fortress` true only while `attacks_on` and it is night.
**Size.** L.

### WP8. QA bot and balance [M]
**Goal.** The acceptance test of section 5 and the numbers.
**Owns.** `tools/house_bot.gd` (`HouseBot`: plays through `sim.avatar.set_input`, `sim.interact.use`, `sim.rescue.choose`, `sim.perimeter.order`, `sim.sleep.begin`, and the radio; it walks `sim.path_p`; it fights as `AvatarBot` does (reuse `tools/avatar_bot.gd` for the night's wall defence: `Sections.compound` is replaced by the base's sections)), `tools/house_lab.gd` (headless: `--seeds=1..4 --hz=15 --out=path.json`, prints a timeline of the arc in game minutes, the verdicts, the night's `NightStats` row), `assets/data/one_house_tuning.json`, `tests/test_oh_arc.gd` (one seed, the arc to the end, fast: a budget of 90 s of CPU, tagged so the integrator can skip it).
**Hooks.** None.
**Produces.** The bot, the lab, the tuning file (numbers: kit costs, `night_mult`, start stock, survivor packs, `wake_r`, `active_cap` for the lab), a short "tuning notes" section in the lab's output (not a file).
**Consumes.** All sim contracts; stubs for the packages not landed (the bot skips a milestone whose module is absent and says so).
**Depends on.** The contracts; the skeleton **can start now** (HouseBot against fakes); the real runs need WP3, WP4, WP5, WP6 merged.
**Acceptance.** (1) The bot clears the start house, claims it, and the lab prints the milestone times. (2) The bot rescues four survivors (any four of the 12) within 3 game days. (3) It builds the perimeter it can afford and the first attack night is held in at least 6 of 8 seeds with the bot and in at least 2 of 8 with an idle avatar (the target of section 5). (4) The full arc is 20 to 32 real minutes when played at the bot's human-paced speed (the lab reports game minutes; 1 game hour = 30 s). (5) A lab run changes no file but its `--out`.
**Size.** M.

### WP9. Performance and the web [S to M, after WP1]
**Goal.** The demo runs at the desktop's 60 fps and the web's 30.
**Owns.** `scripts/town/town_perf.gd` (platform caps: `active_cap` 60/40, `path_budget`, the number of dead at generation 700/350 on the web, the roof mode `multi` on the web), `tools/town_bench.gd` (extended), the web export check (`export_presets.cfg` preset "Web (demo)" is the school demo's: a town preset "Web (one house)" with the `demo` tag off; the export itself is run by the integrator, see STATUS.md section 7), `tests/test_oh_perf.gd`.
**Hooks.** `main.gd`: none beyond WP1's facade (`town.on_frame` adapts the cap to the frame time when the web build drops under 40 fps: halve `active_cap`, restore later).
**Consumes.** WP1's field and world; the whole game for the final measurement.
**Depends on.** WP1 merged; the real measurement waits for the rest. **Can start now** on the foundation's own bench.
**Acceptance.** (1) With 60 awake dead and the avatar standing in the street, a step costs under 5 ms (desktop headless). (2) The town generates in under 1.5 s (desktop) and the loading card is shown while it does (the async `begin/step/result`). (3) A night with an attack (wave dead + the cap) never exceeds `CAP_NIGHT` + `active_cap` zombies. (4) Search budget: no step above 24 `Pathfinder.find` calls. (5) The save file of a mid-game town is under 120 KB.

---

## 4. Integration order and the shared files

### 4.1 Merge order (the integrator merges; builders only report)
0. The owner creates `feature/one-house` from `main` and merges the art builder's `feature/town-art` when its manifest lands (any time: `TownArt` falls back to placeholders).
1. **WP5 phase A** (hooks + `town_rules.gd`, neutral): first, because everything branches from it. Golden tests green.
2. **WP1** (foundation): then everyone rebases on it. `Helpers.town_game` exists.
3. **WP6 skeleton** (`OneHouse.begin`, stage, objective; it can come with WP1) so the others can run the whole flow.
4. **WP3, WP2, WP4** in any order (they do not touch each other's files).
5. **WP5 phase B** (layout, perimeter) after WP3 (claim installs it) but its tests do not need WP3.
6. **WP6 complete** (guide, end, save, menu), **WP7** parts as they come, **WP8** bot and lab, **WP9** last.
After every merge the integrator runs: `--only=test_oh_` (all new tests), the two golden tests (after steps 1, 2, 5), a 30 s boot of `--town`, and once an hour the full suite (about 10 minutes, STATUS.md 1d).

### 4.2 Shared files: who edits what (everything else is a new file)
| File | Rule |
| --- | --- |
| `scripts/main.gd` | WP1: the factories in `_ready`, the nine facade hooks, camera bounds, `_parse_args` `--town`. WP6: two lines in the `_ready` run branch, one in `_parse_args` (`--stage=`). Nobody else. Hooks are single lines `if town != null: ...` calling the facade. |
| `scripts/ui/hud.gd` | WP7 only (the profile call, the end card choice). |
| `scripts/ui/radio_panel.gd` | WP7 only (two page constructors). |
| `scripts/sim/sim.gd` | WP5 phase A only (H1 to H4, H6 helpers). Nobody else, ever. |
| `waves.gd`, `build.gd`, `jobs.gd`, `tactics.gd`, `lots.gd`, `town.gd`, `save_game.gd` | WP5 phase A only (the hook lines). |
| `scripts/sim/interact.gd` | WP3 only (H12). |
| `scripts/sim/recruits.gd`, `radio.gd`, `avatar.gd`, `nights.gd`, `gate.gd` | nobody (used as they are; if a package finds it needs a line, it asks the integrator, who gives it to WP5). |
| `scripts/render/overlay_node.gd`, `lighting.gd`, `pawn_node.gd` | nobody in the first pass; WP2 may ask for one hook each (name, function) in its report. |
| `scripts/ui/new_game_menu.gd`, `title_menu.gd` | WP6 only. |
| `tests/helpers.gd` | WP1 appends `town_game` at the end. Others append their own helpers **to their test file**. |
| `assets/data/*.json` | one owner per file (2.5); `map.json`, `buildings.json`, `plots.json`, `stations.json`, `posts.json`, `lots.json`, `nights.json`, `demo.json`: nobody. |
| `tests/golden/*`, `tests/test_nights_regression.gd`, `tests/test_round20_noavatar.gd` | nobody, ever. |
| `STATUS.md`, `README.md`, `docs/` | the integrator only. |
| `export_presets.cfg`, `project.godot` | WP9 asks, the integrator edits. |

### 4.3 What can start now, what must wait
Now: WP1 (running), WP5 phase A, WP2, WP3, WP4, WP6, WP7, WP8 (the skeleton), WP9 (its bench). Waiting: WP5 phase B (needs WP1's mini town, a few hours in), WP8's real runs, WP9's final numbers. Every package that consumes another's module uses `sim.get("name")` and the frozen signatures of 2.2, with a fake in its tests.

---

## 5. The demo acceptance (what must work end to end)

**Target real time: about 25 minutes** for a normal playthrough (20 to 32 accepted), at `min_per_sec` 2.0 (a game hour is 30 s): day 1 from 08:00 (clear, claim, a first look round, about 6 min), the night skipped in the bed (under a minute of fast-forward), day 2 (two rescues, building, about 6.5 min), night 2 skipped, day 3 (two more rescues, fortify, about 6.5 min), the first attack night (about 5 min), the end card.

1. **Boot.** Title -> New game starts the town: a loading card (under 3 s desktop, 10 s web), Ruth wakes in the start house at 08:00 on day 1, the roof of that house is hidden, the other rooms are dark, three dead are in the house, the objective line says what to do, the guide's first lesson is up.
2. **Lessons** (six, none blocking): walk; aim and shoot a dead one; open a door and enter another house or room (roof fade seen); clear; search a container; claim.
3. **Clear.** Room by room (dark rooms, doors that open, dead you cannot see until the door is open); `room_clear` toasts; the stores gain from searches; "The house is clear" banner when the last dead is down; the objective changes to the claim.
4. **Claim.** E at the front door (a 2 s session): the bed, the stash, the radio and the workbench appear; the house's two doors are barred (shut to the dead, open to you); the Build page shows the perimeter slots (locked and open); the radio says nobody is on it yet; the claim is saved.
5. **Explore and rescue.** The streets have wandering dead (more by night); houses hold loot and dead; a survivor in each of 12 houses (the nearest within about 25 tiles); with the room clear, E talks: the card offers "Come with me" (only after the claim, and only with a bed), "I will come back", "Take this"; "Come" makes them arrive at the base within a couple of game minutes with a small pack; they take jobs (`jobs.fill_empty`), appear in the crew bar, answer the radio (follow, hold, cover, search) and the wheel.
6. **Nights before the fourth are quiet**: no wave, no forecast, the bell tolls, wanderers stay wanderers, sleeping in the bed skips the night (refused when a dead is near).
7. **The fourth rescue**: banner "Four voices on the radio. The dead will come tonight", the objective "Fortify the house before dark", the slots of stage 4 unlock, the forecast at 17:00 names the size and the side.
8. **Fortify.** The player orders fence sections, the gate, a tower and a floodlight (scrap, builder-hours, hit points shown); the builders build by day; the posts are manned at the bell.
9. **The night**: the dead come from the streets in groups through the dusk and the night; the community shoots from the posts; the avatar shoots and mends (E); a fence section that falls is a breach the dead walk through; the night is held when the dawn comes with the avatar alive, no dead in the house and the base standing.
10. **The end card** after the first held dawn: nights held, people, houses cleared, dead put down, slots built, a thanks line; Esc and "Back to title" work; a defeat is the ordinary game over.
11. **Save/load** at any point (quick save, autosave at dawn): a load restores the stage, the revealed and cleared rooms, the looted containers, the claimed base and its built slots, the joined people and their jobs, the stock, the awake and sleeping dead.
12. **Speed**: 60 fps desktop with up to 60 awake dead, 30 fps web with up to 40; no logged error in a full playthrough.
13. **The school game, the demo (`--demo`), Orientation Day and the harness are as before** (golden tests green, the full suite green).

**The bot proves it.** `tools/house_lab.gd --seeds=1..4` plays steps 1 to 10 headless with `HouseBot` and prints each milestone in game minutes (house clear, claim, each rescue, the fourth, each slot built, the bell, held/lost); the accepted verdicts: claim before 12:00 on day 1; four rescues by the end of day 3; the first attack held in at least 6 of 8 seeds with the bot at the wall and in at least 2 of 8 with an idle avatar (the community alone must be able to *nearly* hold it: the player's hands are the margin, as round 19 designed); the real-time length 20 to 32 minutes. `tests/test_oh_arc.gd` runs one seed of it with a CPU budget so the integrator has a one-command check.

---

## 6. Risks and fallbacks (top five) and what to cut first

1. **The school's assumptions leak into the town** (a hard-coded corner I did not find; a hook that is not neutral; the golden tests move). *Mitigation:* the list of 1.5 was made by grepping every coordinate literal and `COMPOUND`/`YARD_MIDDLE`/`SEGMENT`/`DOOR_KIND`/`FIRST_SEGMENT_ID` in `scripts`; hooks are one line each; subclasses override the rest; the two golden tests run after every shared-file merge. *Fallback:* if the generated base cannot be made to behave with the school's `assign_slot`/`gate` code, WP5 writes the town's own small `assign_slot` in `TownRules` (the dead walk to the nearest built section or the door), and keeps the same data.
2. **Performance and the web** (700 dead, a 192 x 192 grid, 3000 sprites, 8 to 12 shooters at night). *Mitigation:* dormancy, the cap (60/40), chunked paint, roof `multi` mode, the path budget, WP9's bench from day one. *Fallback (in order):* 350 dead on the web, `active_cap` 30, a 160 x 160 town (6 x 6 blocks of 26), no roofs animation on the web, desktop-only demo.
3. **The art is late** (the kit and its manifest). *Mitigation:* `TownArt` is the only reader; every descriptor has a flat-colour placeholder; WP2 and WP5 never name a file; the manifest's schema is read once, in `TownArt`. *Fallback:* ship the placeholders (flat roofs from the base map's ROOF terrains, the generator's terrain walls, the school's fence pieces tinted).
4. **Balance: four survivors and a handful of slots must be able to hold a night.** *Mitigation:* a first attack sized by `night_mult` from `one_house.json` and `one_house_tuning.json`, the night lab's `NightStats` rows, WP8's eight seeds; the avatar counts for half a defender (`ordinary.avatar_weight`). *Fallback:* a gentler first attack (fewer, no runners, the dead come in one group), stronger starting slots (hit points x1.5), a second night before the end card, or the end card after the first night *survived* rather than held without a breach.
5. **Integration drift and merge pain** (main.gd, hud.gd; eight builders; one world). *Mitigation:* the facade and the soft-wired tables, one owner per file, frozen contracts, a merge order, the integrator runs the tests after every merge, packages report the exact lines they touched. *Fallback:* the integrator freezes new work in the last hours and only fixes.

**Cut first, in this order if time runs short:** (1) the web target (desktop demo only); (2) the window/door upgrade slots, sandbags, the second tower and floodlight; (3) the town map page (a list of "houses explored" in the objective instead); (4) the sleep fast-forward (the player waits or plays through the quiet night at x4); (5) per-room darkness (keep the roof fade only; reveal by door stays as data); (6) the "Take this" gift and the survivors' pack; (7) the guide's lessons 5 and 6 as separate steps; (8) the lost state (already off). **Never cut:** the roof fade, clear-and-claim, the four rescues, the perimeter slots with the gate, the held night and the end card, the save/load.

---

## 7. The common builder briefing (paste into every builder prompt)

```
You are a BUILDER for the Thirty Bells "One House" build (Godot 4.7.2, GDScript, /Users/jaf_lab/last-bell).
Read FIRST: docs/superpowers/plans/2026-10-04-one-house-plan.md (your package, section 3; the contracts, section 2;
the shared-file rules, section 4.2) and docs/superpowers/specs/2026-10-04-one-house-design.md. Your package is WP<N>: <name>.
Do exactly your package, lean and fast: a first working slice in 45 minutes, then the rest; no gold plating, no new docs,
no README/STATUS/plan edits, no report files.

RULES (all of them matter)
1. WORKTREE. Work only in your own worktree, made from the integration branch:
     cd /Users/jaf_lab/last-bell && git worktree add .worktrees/oh-wp<N> -b feature/oh-wp<N>-<name> feature/one-house
     cp -R .godot .worktrees/oh-wp<N>/.godot        # the import cache (never `git stash`: the stash is shared by all worktrees)
   `.worktrees/` is already in .git/info/exclude. Never touch the main folder or another worktree (reading others is fine).
   If resources do not load in the new worktree run once, in the background: $G --headless --path . --import
2. DO NOT COMMIT, merge, rebase, push, tag or publish anything; do not touch itch.io or GitHub. Leave the work uncommitted in your
   worktree and report; the owner commits and merges.
3. FILES. Edit only the files your package OWNS and the one-line hooks the plan names for you (file and function). Anything else you
   need in a shared file: do NOT edit it, name it in your report (file, function, the line you want). Frozen contracts (plan 2.2 to 2.5):
   add, never change a signature or an event; if you must, add an overload and say so.
4. NEUTRAL. Every hook in a shared file returns today's value in every game that is not the town: no `sim.rng` draw, no event, no
   news, no allocation per step. New rules live in new files reached through the town's own variables (`sim.get("name")` may be null: guard it).
   NEVER edit, re-pin or "fix" tests/golden/*, tests/test_nights_regression.gd or tests/test_round20_noavatar.gd; if one fails, your hook
   is not neutral. (Only packages that edit sim.gd, waves.gd, build.gd, jobs.gd, tactics.gd, lots.gd, town.gd, interact.gd or
   save_game.gd run them: --only=test_nights_regression: and --only=test_round20_noavatar:.)
5. TESTS. At most FIVE tests for your package, in tests/test_oh_<name>.gd, extending res://tests/case.gd (check, eq, near), each under
   2 seconds, one shared mini town (`Helpers.town_game(1, {"blocks": 2})`) or a fake, no waiting on timers, no `static var` caches or
   flags that a test can change (tests/run.gd `_find_globals` fails the run for shared state a test leaves changed), any logged error fails
   the run. Write the failing test first when you can. Run ONLY yours:
     G=/Applications/Godot.app/Contents/MacOS/Godot
     nohup $G --headless --path . --script res://tests/run.gd -- --only=test_oh_<name>: > $SCRATCH/out.txt 2>&1 &
   then poll the file. Do not run the whole suite (10+ minutes): the integrator does.
6. PROCESSES. Run EVERY Godot command in the BACKGROUND with nohup and poll its output file (a foreground command can hang the session).
   NEVER kill by pattern: no pkill, no killall, no `kill $(pgrep ...)`: the owner keeps the Godot editor open and it has been killed that way
   before. If a process of YOURS must stop, `kill <the exact PID you started>` (`$!`), nothing else.
7. SCRATCH. Temporary files go in your session scratchpad directory, never in /tmp, never in the repo.
8. DELETING. Never `rm`. Move what must go to ~/.Trash.
9. NO DOWNLOADS, no network installs, no new assets from outside, no secrets, no emojis in code, comments or text.
10. STYLE. Match the code: tabs, `##` doc comments that say what and why in plain words, typed signatures where cheap, `preload` constants
    (the project uses no class_name), modules shaped as `setup(sim)`, `start()`, `update(dt)`, `save()`, `load_state(d)`, `enabled`/`active()`.
    Everything in tiles; a tile is about a metre; the rules step is 1/30 s; a game hour is 30 real seconds in the town.
11. WHEN STUCK for more than 15 minutes on a contract question, make the smallest assumption, say it in the report, and go on.

REPORT (under 300 words, as your last message): what you built; the files you created and edited (absolute paths) and, for each shared
file, the exact function and line you touched; the tests and their result (pass/fail counts); how to try it (one command); what is stubbed
or missing; any contract you had to add; any "VERIFY" you settled and how.
```

---

## 8. Open points for the owner (answers change a number, not the plan)

1. **Which house is the base in the demo?** The plan says the start house only (hand-placed, clear ring); any house is claimable in the code. Confirm.
2. **The clock.** `min_per_sec` 2.0 (a game hour = 30 s) is the plan's choice to fit 25 minutes with sleeping through the quiet nights; say if the owner wants the school's 3.0 (shorter days, harder rescues).
3. **Loot goes straight into the stock** (no bags, no stash trips) in the demo: the stash is where you read and spend the stock. Confirm.
4. **The first attack's size and the held rule** (alive, nobody dead in the house, the base standing) are the lab's to tune; the owner may prefer "survive the night, whatever the cost".
5. **Window barricades and sandbags are cut** from the first slot set (the generator has no windows); the front and back doors take a plank upgrade instead.
