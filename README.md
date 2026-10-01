# Thirty Bells (Godot)

Six survivors hold a walled schoolyard against the dead for thirty nights. Built in Godot 4.7. (Working title; it was Last Bell until 2026-10-01, when it turned out a Steam game called The Last Bell is coming. The itch.io page and the GitHub repository still carry the old name.)

Open the project and press **F5**. The main scene is `scenes/main.tscn`; a cold start shows the title screen (Continue, New game, Orientation Day, Load, Settings, Credits, Quit). A start with a run choice on the command line (`--new=1`, `--seed=N`, `--load=path`, `--shot=...`) goes straight into the yard.

## Controls

| Input | Action |
| --- | --- |
| Click | Select a person, walker or wall piece |
| Right-click | Send the selected person there (drafts them) |
| Drag, or W A S D | Pan |
| Scroll or pinch | Zoom |
| R / P / F / C | Draft or release / to post / repair / follow |
| T / X / G | Treat the wounded or infected / send an infected person out / send a scavenging party |
| M | Send the selected person to make ammo at the worktable (again to call them back) |
| V | Show how many guns reach each wall section from where the crew stands at night (red none, amber one, green two or more) |
| L | Set the alarm on the selected wall section |
| B | Switch auto-repair on or off for the selected person |
| Space, 1, 2, 3 | Pause, normal, fast, fastest |
| Tab | Next person (skips the lost and those away) |
| Esc | Clear the selection; with nothing selected, the menu (resume, save, load, settings, how to play, main menu, quit) |

## Playing

A new game starts on day 1 at 07:00 with a quiet yard. The dead come at dusk, more each night.

- **Supplies.** At 07:00, 13:00 and 19:00 everyone eats and drinks. The stores panel shows how many days of food and water are left. The vegetable beds and rain barrels give a little each dawn. Repairs cost scrap (1 for every 10 points of wall health), bandages cost medicine, and shooting costs ammo: when the stock cannot pay for another shot the guns stay silent and people fight with the butt of the gun (a pike never runs dry), and an alert says so.
- **Wounds.** A bite or scratch bleeds until someone bandages it (Ana first); at 0 health a person is downed and must be stabilised within three game hours, then rests in bed. A **bite** can infect: a feverish person turns into a walker 12 to 24 hours later unless treated (**T**, two medicine, better with Medicine skill) or sent out through the gate (**X**).
- **Scavenging.** Select someone and press **G** to send one or two survivors through the gate between 06:30 and 10:00, to the houses (food and water), the pharmacy (medicine), the hardware store (scrap and ammo) or the scrapyard (a great deal of scrap, and the most dangerous). They come back at 16:00 with loot, hurt, or not at all. A raided site is picked over for three days.
- **The workshop.** Ammo is what runs out first. By day select a person and press **M**: they walk to the worktable in the yard and turn scrap into ammo, 8 ammo for each scrap (Dez gets through 6.5 scrap an hour, Marcus 2.5), and keep 3 scrap back for the walls. They go back to their jobs at the bell, or when you give them another order. Scrap is what the walls, the bench and the scrapyard trips are all about.
- **The school.** The dead cannot walk into the school while its two north doors hold. They go for the doors once the yard has fallen and a person is hiding inside; a door that is down opens the whole building to them. Falling back is a last stand with a clock, not a bunker.
- **The dead.** Walkers come from the first night. From night 4 some are **runners**: quick and frail, they cross the yard in a third of the time and give the crew little warning. From night 8 a **brute** comes among them: slow, huge, many shots to bring down, and it tears at a wall several times as hard as a walker. The guns shoot a brute first and a runner second. Each night is planned at dusk: most of the dead come from one or two spawn points, the later part of the night is where the brutes are.
- **The lookout.** At 17:00 Marcus, if he is alive and about, reports what tonight looks like: about how many (give or take 15%), from which way, and whether a brute or runners are among them. Without him nobody tells the crew.
- **Fields of fire (V).** The shooters stand at their night posts, and a wall section is only defended if their guns reach it. The view shows each section's cover; people on the walkways and towers can be scratched far less often than people on the ground.
- **The alarm (L).** Select a wall section and set the alarm: it costs 3 scrap, rings for three game hours, and draws the dead already on their way to that section, where the guns are. One alarm at a time; not on the school doors.
- **Standing orders (B).** A person with auto-repair mends the most worn wall section by day without being told, while the stock has 5 scrap or more. Dez and Hector start with it on. A repair mends 5 points a second plus the person's Building skill.
- **People.** Each survivor has two traits (Steady, Nervous, Tinkerer, Triage, Sharp-eyed, Steady hands, Tough, Optimist, Loyal, Quick learner), bonds with some of the others (family, mentor, friend), a mood and skills that grow with use. The person panel shows all of it; the mood's tooltip lists every reason with its sign. Mood runs from Inspired through Steady and Shaken to Breaking (a shaken person works and aims a little worse); someone who breaks down stops shooting and cannot be ordered for an hour (from day 4, not on Story). A loss hurts the ones who knew them most. Shooting, Melee, Medicine and Building each gain a point with enough use, at most three over where they started. People speak up when something happens (the bell, a wound, a friend down) and the others say a few words when one is lost.
- **The radio hour.** At noon Ruth (or whoever leads, if she is gone) has news on the radio: about two days in three there is a card (never on the first day or the last). Fifteen cards: heavy rain, fog, a blackout that Dez must mend, a horde warning, stragglers at the wall by day, a fever, supplies falling from the sky, a stranger at the gate, a cry for help, a trade offer, an argument... A card with a choice waits for you and states its risk plainly; if nobody answers within two game hours its default is taken. A hidden tension leans the draw: after a bad stretch the radio is kinder. The morning after each night an assembly card says how many were put down and by whom, what the wall lost and gained, who was lost (and what the others said), what was learned and how the crew is.
- **Orientation Day.** A guided first run (about ten minutes, a Story game that cannot be lost): sixteen short steps teach selecting and moving, posts on the decks, repairs, the stores, a scavenging trip, the bell, shooting, the fields-of-fire view and the alarm, wounds and fever, saving and making ammo. Offered on the first launch; replay it from the title screen. After that a few one-line tips show once each in real runs (first dusk, low stores, the first wound, the first runner and brute); switch them off in Settings.
- **Menus and settings.** The title screen offers Continue (the newest save), New game (difficulty and seed), Orientation Day, Load, Settings and Credits; **Esc** with nothing selected opens the pause menu, and so does the menu button next to the sound button. Settings keep four volumes (effects, ambience, interface, master), the interface size, hints, reduced motion and fullscreen in `user://prefs.cfg`.
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
- `scripts/ui/hud.gd`: the HUD, built from Controls; `scavenge_dialog.gd` and `game_over.gd` are its modals. Their surfaces come from `frames.gd` (nine-slice frames in `assets/ui/theme`).
- `scripts/ui/shell.gd` and its siblings (`title_menu.gd`, `pause_menu.gd`, `settings_menu.gd`, `new_game_menu.gd`, `load_menu.gd`, `credits.gd`): the title screen and the menus. `scripts/prefs.gd` keeps the settings in `user://prefs.cfg`.
- `scripts/ui/coach.gd`, `scripts/sim/orientation.gd`, `assets/data/tutorial.json`, `assets/data/hints.json`: Orientation Day (a scripted scenario and the coach overlay) and the one-line tips.
- `scripts/sim/workshop.gd`: scrap into ammo at the worktable.
- `scripts/sim/{skills,traits,bonds,morale,barks}.gd` (data in `assets/data/{traits,barks}.json`): the people. `scripts/sim/storyteller.gd` and `assets/data/events.json`: the radio hour, the cards and the morning assembly; `scripts/ui/{radio_card,dawn_card,story_ui}.gd` show them.
- `scripts/audio/sound.gd`: one-shot sounds and the ambience loops.

## Art and sound

The files in `assets/` are the source art. Edit or replace them directly; a
replacement PNG at the same size drops straight in.

- `assets/objects`, `walls`, `terrain`: props, the school walls, ground textures.
- `scripts/render/deck_faces.gd`: draws what makes the walkways and towers look raised: the scaffold face under the planks, the tower bases, the supports along the side walkways, the shadows and the ladders (their sizes are constants at the top of the file). The pieces it draws are `assets/objects/deck_*.png`, made by `tools/make_deck_art.py` (Python with Pillow and NumPy) from three reference pictures in `tools/art_src/` (a scaffold front, a tower base and a ladder, made with Meshy and kept so the pieces can be rebuilt). The walkways can only be climbed at the ladders; `world.gd` shuts the tiles under the face for people and for the dead.
- `assets/pawns`, `portraits`, `weapons`, `trees`, `fx`: characters and effects.
- `assets/ui/icons`: HUD icons. `assets/ui/theme`: the noticeboard frames, built by `tools/make_ui_theme.py` from Meshy material pictures kept in `tools/ui_src/` (`docs/assets-log.md` records every AI-made picture).
- `assets/audio`: sound effects and ambience loops; the UI sounds (`ui_*.wav`) are synthesised by `tools/make_ui_sounds.py`.
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
| `--title` | Show the title screen |
| `--menu=pause` | Open a menu (`pause`, `settings`, `new`, `load`, `credits`, `confirm`, `orientation`) |
| `--prefs=path` | Keep the settings in another file (so a screenshot run does not touch yours) |
| `--tutorial[=N]` | Start Orientation Day (at step N) |
| `--card=id` | Show a radio card (see `assets/data/events.json`) |
| `--weather=fog` | Start with fog (or `rain`, `clear`) |
| `--blackout` | Start in a blackout |
| `--dawn` | Show the morning assembly |
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
(the check that knowing the night pays), `--sites=path` reads the scavenging sites from another file (to try a site before it is in the game), `--nostory` plays with the storyteller off (to see what the radio changes), `--verbose` lists what the policy did and who was lost; see the top of
the file for the rest. A game
whose colony collapses is slow to play (the walkers inside the yard re-path
every second).

## Tests

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run.gd [-- --only=text]
```

Every `tests/test_*.gd` file is run; a test fails if it fails a check or logs an error. `tests/helpers.gd` builds a headless game for tests.
