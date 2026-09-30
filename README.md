# Last Bell (Godot)

Six survivors hold a walled schoolyard against the dead. Built in Godot 4.7.

Open the project and press **F5**. The main scene is `scenes/main.tscn`.

## Controls

| Input | Action |
| --- | --- |
| Click | Select a person, walker or wall piece |
| Right-click | Send the selected person there (drafts them) |
| Drag, or W A S D | Pan |
| Scroll or pinch | Zoom |
| R / P / F / C | Draft or release / to post / repair / follow |
| T / X | Treat the wounded or infected / send an infected person out |
| Space, 1, 2, 3 | Pause, normal, fast, fastest |
| Tab | Next person |
| Esc | Clear selection |

## How it fits together

- `scripts/main.gd`: builds everything at startup, then runs the camera,
  input, the event→sound/HUD wiring and the frame loop.
- `scripts/world.gd`: the static map. The ground is a `TileMapLayer`; props,
  vehicles, wall pieces and roofs are sprites in draw order. It also owns the
  walkability grids.
- `scripts/sim/`: the simulation. `sim.gd` holds the clock, people, walkers,
  combat and wall damage. `pathfinder.gd` wraps `AStarGrid2D` and smooths paths.
- `scripts/render/`: drawing.
  - `pawn_node.gd` draws one person or walker (y-sorted).
  - `pawn_art.gd` has the live legs, arms and hands.
  - `fire_node.gd` draws flames.
  - `fx.gd` handles effects.
  - `lighting.gd` covers the day/night sky (`CanvasModulate`) and every lamp (`PointLight2D`).
  - `glow_node.gd` draws additive glows.
  - `overlay_node.gd` draws the names, bars and brackets.
- `scripts/ui/hud.gd`: the HUD, built from Controls.
- `scripts/audio/sound.gd`: one-shot sounds and the ambience loops.

## Art and sound

The files in `assets/` are the source art. Edit or replace them directly; a
replacement PNG at the same size drops straight in.

- `assets/objects`, `walls`, `terrain`: props, the school walls, ground textures.
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
| `--breach=N` | Break wall segment N |
| `--selftest` | Drive the real input handlers once |
| `--frames` | Frames to wait before the shot |

The run prints average fps.
