# Log of the AI-made pictures

As of 2026-10-17 the game contains no AI-generated pictures, and neither does the repository.
Every picture in the project is drawn in code (Python scripts with Pillow and NumPy, or the
game's own drawing code) or made by hand. For Steam's AI-content disclosure there is no
pre-generated or live-generated AI art to declare.

## History

Between 2026-09-30 and 2026-10-02, 22 pictures were made with Meshy's text-to-image service
(the `nano-banana-pro` model, 9 credits each). They were used as follows, and all of them were
removed on 2026-10-17:

- Six material swatches in `tools/ui_src/` (slate, chalk dust, oak, brass, notebook paper and
  card stock) that `tools/make_ui_theme.py` baked into the noticeboard frames in
  `assets/ui/theme/`. The script now draws those materials itself from seeded noise
  (`material_slate`, `material_dust`, `material_oak`, `material_brass`, `material_paper`,
  `material_card`), at the same sizes and with the same average colours and spread, and the
  frames were rebuilt from them.
- Four site pictures in `assets/ui/sites/` (pharmacy, hardware store, houses, scrapyard; the
  scrapyard was made from `tools/ui_src/ref_scrapyard_a.png`) for the scavenging dialog and
  the Town Board of the older games. They were deleted and the places no longer name a
  picture; the cards show their placeholder instead.
- Three reference pictures in `tools/art_src/` (a walkway face, a tower base and a ladder) from
  which `tools/make_deck_art.py` cut the deck pieces `assets/objects/deck_*.png`, and one
  (`ref_mast.png`) from which `tools/make_mast_art.py` cut the radio mast
  `assets/objects/392_mast.png`. Both scripts now draw these pieces in code, at the same sizes,
  in flat colours with a dark outline.
- Three concept boards in `docs/audit/img/` (`concept_keyart.jpg`, `concept_ui_chalkboard.jpg`,
  `concept_city_map.jpg`) used in the audit of 2026-10-01. They were deleted and the audit now
  says where they stood.

A backup of every removed original, and of the frames, deck pieces and mast sprite that had
been made from them, is in `~/.Trash/meshy-assets-2026-10-17/` on the owner's machine (it is
not in the repository). The prompts and Meshy task ids are in the git history of this file
(the version before 2026-10-17).

Two screenshots in `docs/audit/img/` (`shot_scavenge_dialog.jpg` and
`shot_platforms_before_after.jpg`) are captures of the game from that time and show some of the
old pictures; they are documentation, not part of the game, and are not exported.

# Recorded sounds (2026-10-17)

The prison game's most heard sounds are now human recordings from two free libraries, cut,
levelled and written as mono 16-bit WAVs (22.05 or 44.1 kHz) in `assets/audio/lib/` by
`tools/import_library_sounds.py`. No sound in the project is AI-generated, and no paid service
was used. The raw library files are kept outside the repository in `~/sfx-sources/` on the
owner's machine and are never committed; only the processed game files are. To rebuild them,
put the same files back under `~/sfx-sources/` and run
`python3 -I tools/import_library_sounds.py`.

## Sources and licences

- Kenney (kenney.nl), CC0 1.0 (public domain, no attribution required): Impact Sounds,
  RPG Audio and Interface Sounds, downloaded as the three zip files from kenney.nl (2.5 MB in
  all). Used for footsteps, metal and plate hits, fist blows, door open and close, cloth, leather,
  pots and glass, the hammer, and the menu clicks.
- Sonniss GDC Game Audio Bundles 2017, 2018, 2019 and 2020 (sonniss.com/gameaudiogdc). Their
  licence allows commercial use in games without attribution, forbids redistributing the raw
  sounds and forbids using them to train AI. Only the files that were needed were downloaded:
  113 single files (717 MB) read out of the bundle zips on the your.org mirror with HTTP range
  requests, from GDC 2017 part 4, GDC 2018 parts 1 to 6 and 8, GDC 2019 parts 1, 2, 3, 5, 6 and
  8, and GDC 2020 parts 1 to 10, 12, 13 and 14. The packs used include Pole Position
  (M1911A1, Walther P38, Tokarev TT-33, K98k, Springfield M1903A3, MP 40, PPSh-41, Thompson,
  the Indoor and Outdoor Gun Acoustics Libraries, the Burning House Library), FLYSOUND Mosin
  Nagant, Super Thump (M3 Grease Gun, Weapons of World War II), Wav Junction (Shotguns, Doors,
  Footsteps, Ambience), Gamemaster Audio, Watson Wu, Olivier Girardot, PMSFX (Bullet Bys and
  Impacts, Bloodbath, Steps), Glitchedtones Zombie, Articulated Sounds (Yeti, Camel, Fun
  Monsters, Bones and Blood, Ghosts Return), SmartSoundFX Monsters, Audiomeals, Sound Spark
  Gore, Red Libraries Bodyfall, Studio 23 footsteps, 344 Audio Practical Doors, RZ Post Creepy
  Door, Alex Lane, Conor Bradley Metal Chains, InspectorJ, Soundrangers Wind, 2496SoundEffects,
  Ivo Vicic, Discover Oregon and justsoundeffects crickets. `assets/audio/lib/library.json`
  names the exact source file of every take.

The in-game Credits screen names both libraries.

## What stays synthesised

The music, the stingers and the bells; the crew's and Ruth's voices (`pv_*`, `ruth_pain`,
`ruth_breath`); the shell going into the tube (`shell_load`); the heartbeat, warning, alarm,
eating, drinking and bandage sounds (`pu_*` apart from those listed above); the saw, drill and
finished-project chime (`pb_*`); the room tone, floodlight hum, washing line and radio static
(`pa_room`, `pa_buzz`, `pa_flutter`, `pa_static`); thunder; the generator, radio and car loops;
and the menu's card, notification and radio tones. These had no good recording in the downloaded set. The synthesised files
that do have a recording stay on disk as the fallback (the town and school games and the tests
still read them), and `scripts/audio/library.gd` plays the recording in their place.
