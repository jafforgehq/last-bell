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
