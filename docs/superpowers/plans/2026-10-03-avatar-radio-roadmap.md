# One survivor and a radio: the roadmap and round 17 (slice 1)

> Branch `feature/avatar-radio`. The design is `docs/superpowers/specs/2026-10-03-avatar-and-radio-design.md` (the owner approved it by saying "start building and don't stop until you are done with everything, on another branch"). The thread of decisions is `docs/superpowers/brainstorm-avatar-and-radio.md`. The slices are built one after another, each in phases of parallel builders on disjoint files, then integration, a review, a film of what it does and the harness, then a commit. The owner's instruction is to finish every slice.

## The slices

| Round | Slice | What it delivers |
|---|---|---|
| 17 | **1. Be one survivor** | The avatar (WASD, mouse aim, fire, reload, melee) in the yard and in the played trips; the radio verbs and their willingness and trust; the squad's stances; the colony keeps running while the player is in a place; radio calls; succession on death; box select and the yard's pan removed |
| 18 | **2. Home** | Walk the base and interact (E: talk, take a post, use the bench); the radio panel is the colony interface (Jobs, Build, Map, News pages); delegated errands by radio with their penalty; visible refusals everywhere |
| 19 | **3. Nights** | The community holds ordinary nights alone and the waves are tuned for it; breaches and Big Nights need the player (a leader's presence); the forecast and the alarm as tools; a harness bot that plays the avatar |
| 20 | **4. A community with ideas** | Initiative proposals over the radio, relationships (friends, rivals, trust between people), specialists |
| 21 | **5. The live drive** | A short driving scene between the base and a place with events (ambush, roadblock, survivor), replacing the abstract travel |

## Conventions for every builder (every round)

- Godot 4.7.2, GDScript, TDD (a failing test first). Own tests: `$G --headless --path . --script res://tests/run.gd -- --only=test_x:` (trailing colon = exact file). The orchestrator runs the whole suite. **Do not commit, do not push, never kill processes by pattern, delete only by moving to `~/.Trash`.** No downloads, no network, no Meshy; art from the game's own pictures or Python in `tools/`.
- Scratch in `/private/tmp/claude-501/-Users-jaf-lab-last-bell/6b84d821-4f10-4deb-be40-d511bdef2435/scratchpad/r<round>/<task>/`. Screenshots: `$G --path . --resolution 1600x1000 -- <flags> --shot=<png> --size=1600x1000`, then Read the PNG.
- Shared files (`scripts/main.gd`, `scripts/sim/sim.gd`, `scripts/ui/hud.gd`, `README.md`): small Edits only, re-read the lines just before editing; other builders edit them at the same time.
- Every new rule is behind **avatar mode** (`sim.player_id != ""`) unless it is only a view: the harness, `Helpers.make` and the classic tests do not set a player, so they play as before. The harness plays the community without an avatar.
- Nothing under 12 px on screen. A save from before must load. Final report short and honest.

## Round 17 (slice 1): contracts

### Controls in avatar mode (yard and places)

WASD move; the mouse aims; left button held fires; R reloads; F swings the melee; Space pauses as now; Esc the menu; wheel zooms; the camera follows the avatar. **Removed:** box select and groups, left-drag/middle-drag/WASD panning, right-click orders, the order keys (R draft, P post, F repair, C follow, T, X, B, M as hotkeys), the HUD's selection strip. **Kept:** J (Duty roster), N (Build), G (the map: the Town Board, becoming a page of the radio panel), L (alarm becomes "call to arms" in slice 2; for now the alarm as it is), V (fields of fire), and clicking a crew card to look at a person. Without avatar mode (`--noavatar`, tests) the old yard controls stay, minus box select. Orientation Day is taught in avatar mode (fixer T, round 17: `assets/data/tutorial.json`; the old yard's lesson is `tutorial_classic.json`, played with `--noavatar`).

### The simulation (S1.1 AVATAR, S1.2 RADIO, S1.3 CONTINUITY)

```
Sim.player_id: String           # "" = no avatar (the old game, the harness, the tests)
Person (new vars): player: bool; input_move: Vector2; input_aim: Vector2 (world tiles); input_fire: bool;
                   trust: float (0..100, toward the player; default 55); stance: String ("", "follow", "hold", "cover", "search", "back");
                   stance_at: Vector2 (the spot for "hold")
Sim.avatar (scripts/sim/avatar.gd): set_player(p) / player() -> Person|null; set_input(move, aim, fire); reload(); melee();
    update(p, dt)   # called by Sim._update_person for the player: movement with wall collision, aim -> p.aim/p.facing,
                    # aimed fire along a ray, auto-reload, melee arc; WALK_SPEED 3.2 tiles/s, RADIUS 0.3
    on_player_lost(p)   # succession: the next in line (most trusted, then best Leading) becomes the player; every living person's
                        # trust -10; a mourning shock to morale (label "Lost <name>"); the carried gear is lost; event
                        # {"type": "succession", "from": id, "to": id}; if nobody is alive the scenario's defeat as today
Sim.radio (scripts/sim/radio.gd): VERBS = come, hold, cover, search, back, post;
    willingness(contact, verb) -> {ok: bool, why: String, delay_s: float}   # pure: refuses only for a visible reason: down, bleeding badly,
                                                                            # starving, terrified/shaken, busy with something critical
                                                                            # (treating a patient, at the radio desk at noon, the lookout at the forecast);
                                                                            # trust sets the delay (a trusted friend 0.5 s, a doubtful one up to 4 s) and the tone
    request(contact, verb, args = {}) -> {ok, line, why, delay_s}  # applies the stance after the delay; the line is what they say
    trust_of(p) -> float; add_trust(p, delta, why)
    news: Array of {id, t, day, hour, kind, text, sub, options: [{id, label}], answered: ""}   # the radio's log; calls with options wait for an answer
    call(kind, text, sub, options, default_option, ttl_min) / answer(call_id, option_id) / news_since(index)
    kinds of calls fed from the simulation: "attack" (a wall section under attack by the dead), "sick" (a fever or infection),
    "stranger" (someone at the gate); each with 2 to 3 options and a default taken after ttl
    alarm(on): the call to arms (everyone to posts now; `tactics.threat_until` far ahead) / stand down
Stances in the yard sim (`Sim._goal_for`, after orders and medical duty): follow = stand within 2.2 tiles of the player; cover = stand 4 to 5 tiles
    behind the player's aim; hold = stay at `stance_at`; back = clear the stance (job goals again); a person fires at what they see as always
    (and stops to do it); a stance is cleared when they are downed.
Colony continuity (scavenge.gd, sim.gd): scavenge.begin_played(people, place, vehicle) marks the party away at once (the colony people vanish
    from the base) and keeps the party "in the place"; scavenge.finish_played(result) puts the trip's result in as send_played did and sets the
    return after the road home. Sim.fast_forward(game_minutes) runs the colony quickly with the events collected into the radio's news (the
    abstract travel there and back, until slice 5). Colony steps run inside a place scene at 1 colony step per 3 raid steps (1 game minute
    per real second).
```

### The views (S1.4 YARD, S1.5 RADIO UI, S1.6 PLACES)

- **Yard (main.gd, overlay_node.gd, pawn_node.gd, hud.gd readouts):** every frame in avatar mode `sim.avatar.set_input(...)` from WASD, the mouse's tile and the left button; R and F call `reload()`/`melee()`; the camera follows the avatar (eased); a crosshair at the mouse, an aim line from the muzzle, a reload ring, the avatar marked "YOU" on the crew card and over their head; muzzle flash, tracer and thrust drawn from the sim's events; an ammo readout (magazine and stock) near the clock. Box select code, tests and the `--box`, `--select=a+b` flags are removed; the old pan goes in avatar mode.
- **Radio UI (hud.gd, new `scripts/ui/radio_panel.gd`, `news_panel.gd`):** in avatar mode the dock's order buttons become the radio verbs of the selected contact (Come with me, Hold here, Cover me, Search that, Go back, To the walls); a verb calls `sim.radio.request`; the answer shows as a line at the contact's card and a toast; a refusal shows its reason in the dock; a **News** button in the toolbar opens a compact log; calls that wait for an answer appear as a small non-modal card (a few seconds' timer, 2 to 3 options, never pausing the game); an **Alarm** button in the toolbar (the call to arms).
- **Places (raid_scene.gd, raid_run.gd, raid_hud.gd, scripts/raid/squad_ai.gd, main.gd open_raid):** the same avatar controls; the squad of the people who agreed to come follows the stances (follow by default; hold; cover; search that = go to the container the mouse is over and search it; back = walk to the exit); the squad fires at what it sees; box select and right-click orders go; the raid HUD shows the radio contacts (the squad and the people at the base) and verbs, the News card, ammo; the colony runs at 1:3 while the scene is open; opening a place begins the party (colony people away) and fast-forwards the road there, leaving it fast-forwards the road home and finishes the party; succession when the avatar falls (the next squad member takes over; if the squad is gone the trip ends and the base is told).

### Phases of round 17

1. **Phase 1, simulation (parallel):** S1.1 AVATAR (`scripts/sim/avatar.gd`, the Person fields, the `_update_person` hook, other modules' gates, `tests/test_avatar.gd`), S1.2 RADIO (`scripts/sim/radio.gd`, trust, stances in `_goal_for`, news and calls, `tests/test_radio.gd`), S1.3 CONTINUITY (`scripts/sim/scavenge.gd`, `sim.gd` fast_forward and phase mirror, `raid_run.gd` result write-back, `tests/test_continuity.gd`).
2. **Phase 2, views (parallel):** S1.4 YARD, S1.5 RADIO UI, S1.6 PLACES.
3. **Phase 3:** integration, the whole suite, an independent review, a film of a trip and of a yard night, the harness (community only), fixes, commit.

## Acceptance of round 17

A new game starts with the avatar (Ruth) in the yard: WASD moves, the mouse aims, a click shoots the dead, R reloads, F swings; the camera follows. Asking Dez over the radio to come with me makes Dez follow; asking Ana while she nurses a patient is refused with the reason shown. The player can take a trip (G, the map, Take control): in the place the avatar and a squad of two or three play it, the stances work, the colony keeps living (a night can fall while out and radio calls with options arrive), and when the avatar dies the next in line takes over with the setback. Box select is gone. The suite is green and the harness without an avatar is as before.
