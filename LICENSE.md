# Licensing

| What | Licence |
| --- | --- |
| Source code: `scripts/`, `tests/`, `tools/`, `scenes/`, shaders, project files | MIT, see [`LICENSE`](LICENSE) |
| Art and audio made for this game: `assets/` (code-drawn sprites, tiles, icons, synthesised sounds and music), `site/img/`, screenshots | CC BY 4.0, see [`LICENSE-ASSETS.txt`](LICENSE-ASSETS.txt). Credit: "Last Bell by Fedja Hadziselimovic" |
| Recorded sounds in `assets/audio/lib/` | [Kenney](https://kenney.nl) packs, CC0 1.0 (public domain) |
| Fonts in `assets/fonts/` (Barlow, Barlow Condensed) | SIL Open Font License 1.1, see [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt) |
| `icon.svg` | Godot Engine logo, CC BY 4.0, Godot Engine contributors |
| Godot Engine (needed to run the project) | MIT, <https://godotengine.org/license> |

## Not included

The released game on itch.io also uses sound recordings from the Sonniss GDC Game Audio
Bundles (2017 to 2020). Their licence allows use inside a game but forbids redistributing the
raw sounds, so those files are **not** in this repository and were removed from its history.
Without them the game falls back to its synthesised sounds (`scripts/audio/library.gd`), so it
runs and plays the same, only with simpler sound effects. You may swap in your own recordings
with `tools/import_library_sounds.py`.

## Name

"Last Bell" is the working title of this project. A different game called *The Last Bell*
exists on Steam. The licences above cover the code and assets, not the name: if you publish a
fork, give it its own name.
