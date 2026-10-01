# Thirty Bells (Godot)

Six survivors hold a walled schoolyard against the dead for thirty nights. Built in Godot 4.7. (Working title; it was Last Bell until 2026-10-01, when it turned out a Steam game called The Last Bell is coming. The itch.io page and the GitHub repository still carry the old name.)

Open the project and press **F5**. The main scene is `scenes/main.tscn`.

## Controls

| Input | Action |
| --- | --- |
| Click | Select a person, walker or wall piece |
| Right-click | Send the selected person there (drafts them) |
| Drag, or W A S D | Pan |
| Scroll or pinch | Zoom |
| R / P / F / C | Draft or release / to post / repair / follow |
| T / X / G | Treat the wounded or infected / send an infected person out / send a scavenging party |
| V | Show how many guns reach each wall section from where the crew stands at night (red none, amber one, green two or more) |
| L | Set the alarm on the selected wall section |
| B | Switch auto-repair on or off for the selected person |
| Space, 1, 2, 3 | Pause, normal, fast, fastest |
| Tab | Next person (skips the lost and those away) |
| Esc | Clear selection |

## Playing

A new game starts on day 1 at 07:00 with a quiet yard. The dead come at dusk, more each night.

- **Supplies.** At 07:00, 13:00 and 19:00 everyone eats and drinks. The stores panel shows how many days of food and water are left. The vegetable beds and rain barrels give a little each dawn. Repairs cost scrap (1 for every 10 points of wall health), bandages cost medicine, and shooting costs ammo: when the stock cannot pay for another shot the guns stay silent and people fight with the butt of the gun (a pike never runs dry), and an alert says so.
- **Wounds.** A bite or scratch bleeds until someone bandages it (Ana first); at 0 health a person is downed and must be stabilised within three game hours, then rests in bed. A **bite** can infect: a feverish person turns into a walker 12 to 24 hours later unless treated (**T**, two medicine, better with Medicine skill) or sent out through the gate (**X**).
- **Scavenging.** Select someone and press **G** to send one or two survivors through the gate between 06:30 and 10:00. They come back at 16:00 with loot, hurt, or not at all. A raided site is picked over for three days.
- **The school.** The dead cannot walk into the school while its two north doors hold. They go for the doors once the yard has fallen and a person is hiding inside; a door that is down opens the whole building to them. Falling back is a last stand with a clock, not a bunker.
- **The dead.** Walkers come from the first night. From night 4 some are **runners**: quick and frail, they cross the yard in a third of the time and give the crew little warning. From night 8 a **brute** comes among them: slow, huge, many shots to bring down, and it tears at a wall several times as hard as a walker. The guns shoot a brute first and a runner second. Each night is planned at dusk: most of the dead come from one or two spawn points, the later part of the night is where the brutes are.
- **The lookout.** At 17:00 Marcus, if he is alive and about, reports what tonight looks like: about how many (give or take 15%), from which way, and whether a brute or runners are among them. Without him nobody tells the crew.
- **Fields of fire (V).** The shooters stand at their night posts, and a wall section is only defended if their guns reach it. The view shows each section's cover; people on the walkways and towers can be scratched far less often than people on the ground.
- **The alarm (L).** Select a wall section and set the alarm: it costs 3 scrap, rings for three game hours, and draws the dead already on their way to that section, where the guns are. One alarm at a time; not on the school doors.
- **Standing orders (B).** A person with auto-repair mends the most worn wall section by day without being told, while the stock has 5 scrap or more. Dez and Hector start with it on. A repair mends 5 points a second plus the person's Building skill.
- **The goal.** Hold thirty nights. Night 30 is the Big Night: more than twice the usual number of the dead, a third of them runners and brutes, coming from everywhere. At the dawn that starts day 31 a convoy is on the road and the run is won.
- **Save and load.** **F5** saves, **F9** loads; the game also autosaves at each dawn. When everyone is gone the game over screen offers a new game.

## How it fits together

- `scripts/main.gd`: builds everything at startup, then runs the camera,
  input, the event→sound/HUD wiring and the frame loop.
- `scripts/world.gd`: the static map. The ground is a `TileMapLayer`; props,
  vehicles, wall pieces and roofs are sprites in draw order. It also owns the
  walkability grids.
- `scripts/sim/`: the simulation. `sim.gd` holds the clock, people, walkers,
  combat and wall damage; its modules are `waves.gd` (tonight's plan and the dead
  who come), `kinds.gd` (walker, runner, brute), `tactics.gd` (the alarm, auto-repair,
  coverage and the lookout's forecast), supplies, medical, scavenge and scenario.
  `pathfinder.gd` wraps `AStarGrid2D` and smooths paths.
  `step_clock.gd` hands out whole 1/30 s steps, so the rules run at 30 Hz at any
  frame rate and a seed plays the same game everywhere; the drawing interpolates.
- `scripts/render/`: drawing.
  - `pawn_node.gd` draws one person, walker, runner or brute (y-sorted).
  - `pawn_art.gd` has the live legs, arms and hands, and the build of each kind of the dead (size, lean, tint).
  - `fire_node.gd` draws flames.
  - `fx.gd` handles effects.
  - `lighting.gd` covers the day/night sky (`CanvasModulate`) and every lamp (`PointLight2D`).
  - `glow_node.gd` draws additive glows.
  - `overlay_node.gd` draws the names, bars and brackets, the fields-of-fire view and the alarm's marker.
- `scripts/ui/hud.gd`: the HUD, built from Controls.
- `scripts/audio/sound.gd`: one-shot sounds and the ambience loops.

## Art and sound

The files in `assets/` are the source art. Edit or replace them directly; a
replacement PNG at the same size drops straight in.

- `assets/objects`, `walls`, `terrain`: props, the school walls, ground textures.
- `scripts/render/deck_faces.gd`: draws what makes the walkways and towers look raised: the scaffold face under the planks, the tower bases, the supports along the side walkways, the shadows and the ladders (their sizes are constants at the top of the file). The pieces it draws are `assets/objects/deck_*.png`, made by `tools/make_deck_art.py` (Python with Pillow and NumPy) from three reference pictures in `tools/art_src/` (a scaffold front, a tower base and a ladder, made with Meshy and kept so the pieces can be rebuilt). The walkways can only be climbed at the ladders; `world.gd` shuts the tiles under the face for people and for the dead.
- `assets/pawns`, `portraits`, `weapons`, `trees`, `fx`: characters and effects.
- `assets/ui/icons`: HUD icons.
- `assets/audio`: sound effects and ambience loops.
- `assets/data/map.json`: the map layout, lights, wall segments and roster.

They were generated once from the original web prototype, which has since
been removed. Godot is the only version now.

## Publishing (itch.io)

The game is on itch.io at <https://jafforge.itch.io/last-bell>. The page is
**Restricted**: only you can see it, and it is unlisted. To show it to someone,
go to Edit game → Distribute → Download keys and create a key. The key's link
gives them access.

To publish an update:

1. Export the web build from the command line:

   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "Web" build/web/index.html
   ```

   Or use Project → Export → Web in the editor.
2. Zip the contents of `build/web` so that `index.html` is at the root of the zip.
3. On the itch.io edit page, replace the zip. Keep "This file will be played in
   the browser" ticked.

`build/` is ignored by Godot and git. The cover image and screenshots used on
the page are in `build/itch-page/`.

## Automated checks

`main.gd` accepts user arguments after `--`. They let you take a screenshot of a
given moment without touching the game:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --shot=/tmp/night.png --hour=21 --advance=25 --cam=39,19,40
```

| Flag | Effect |
| --- | --- |
| `--hour` | Set the time of day |
| `--advance` | Simulate N seconds first |
| `--cam=x,y,zoom` | Place the camera (tiles, px per tile) |
| `--select=ruth` | Select a person |
| `--wall=N` | Select wall section N |
| `--fields` | Start with the fields-of-fire view on |
| `--lure=N` | Set the alarm on wall section N (gives scrap if needed) |
| `--breach=N` | Break wall segment N |
| `--damage=N:F` | Leave wall segment N at the fraction F of its health |
| `--new=D` | Start a new run at difficulty D (0 story, 1 standard, 2 brutal) |
| `--seed=N` | The seed of the new run (the same seed plays the same game) |
| `--load=path` | Load a save (a file path, or `user://quicksave.json`) |
| `--selftest` | Drive the real input handlers once |
| `--frames` | Frames to wait before the shot |

The run prints average fps.

## Saving

F5 saves to `user://quicksave.json` and F9 loads it. The game also saves to
`user://autosave.json` at each dawn (not in screenshot runs). A save is JSON and
holds the whole state of the rules, so a loaded game carries on the way the
saved one would have. A save that cannot be loaded (damaged, or from another
version) is refused and the game carries on.

## Balance harness

`tools/balance.gd` plays whole games without a window, with a sensible default
policy (repair the worn walls by day, send the best shooters scavenging when a
stock runs low, treat the infected), and prints one row per game and the average
colony day by day:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/balance.gd -- --games=8 --days=10 --difficulty=1 --seed=1 [--fast] [--jobs=4] [--out=result.json]
```

`--fast` steps the rules at 15 Hz instead of 30, `--jobs=N` plays N games at a
time in worker processes, `--policy=none` gives no orders, `--policy=keep` hides the
crew in the school gym from the bell to dawn (the check that hiding does not beat
defending), `--policy=informed` plays the default policy and also reads the plan:
it stands the shooters where their guns cover the thinnest section and sets the alarm
(the check that knowing the night pays), `--verbose` lists what the policy did and who was lost; see the top of
the file for the rest. A game
whose colony collapses is slow to play (the walkers inside the yard re-path
every second).

## Tests

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run.gd [-- --only=text]
```

Every `tests/test_*.gd` file is run; a test fails if it fails a check or logs an error. `tests/helpers.gd` builds a headless game for tests.
