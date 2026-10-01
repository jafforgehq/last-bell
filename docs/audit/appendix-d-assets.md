# Appendix D: assets, licensing provenance and release readiness

> A read-only review of assets/, git history and the earlier session transcripts. Part of [the full audit](2026-10-01-full-audit.md), 2026-10-01, repo HEAD e4fa379.

**Bottom line.** All but 15 of 639 PNGs, and all 31 WAVs, were made by code (Claude-written Canvas2D and Web Audio in the deleted web prototype, baked 2026-09-29): no third-party art or audio to clear. Safe to ship: those, plus the OFL fonts (ship the licence text). Ship only after proof of plan: the 15 Meshy nano-banana-pro images. Not shippable as is: stock Godot icon and splash, no credits. Pixellab: no evidence of use (zero tool calls in both session transcripts, no trace in repo, git or memory).

## 1-3. Groups: facts, origin (evidence), paid-release risk, action

| Group (assets/) | Facts | Origin and evidence | Risk | Do |
|---|---|---|---|---|
| objects | 439 PNG, 15.6 MB, 26x20 to 1724x1495 | 427 code-drawn props, baked; all in first commit 5955b08, none changed since. 12 `deck_*` cut by tools/make_deck_art.py from Meshy refs (e4fa379) | L (12: M) | see Meshy |
| pawns, portraits, trees, walls, weapons, fx, terrain | 90 (368x327), 30 (24 at 128², 6 at 192²), 13 (314x359), 3 (1661x1854), 6 (336x70), 8 (192²/64²), 13 (512²); 9.0 MB | Canvas2D `src/art/pawn.js` (parametric `look`: skin, hair, hat, top; zombies from `zombieLooks(seed)`), noise-painted `terrain.js`; no reference images; `src/bake.js` ran 2026-09-29 17:48Z ("376 objects, 30 characters, 31 sounds") | L | keep |
| ui/icons | 34 PNG, 64², 34 KB | 22 from LLM-written SVG paths on a 16-grid (no icon-set credit found); 12 from tools/make_icons.gd (3831cc7) | L | none |
| ui/sites, deck_*, tools/art_src | 3 PNG 720x405 RGB; 12; 3 refs, 2.8 MB | Meshy `text_to_image`, model `fal-ai/nano-banana-pro` (XMP `meshy:AIGenerated` in ref_*.png, 2026-10-01 05:23-05:27Z). Sites made 2026-09-30 21:44Z, metadata stripped; tasks 01a0f446-a899-70a2-a0de-d76a6ef06b0a (pharmacy), -aa5c-71f3-bcb8-c2d11fd73be0 (hardware), -aea0-7571-a73f-2d82cb1fa623 (houses) | M | keep invoices, task IDs, prompts; or redraw |
| audio | 31 WAV, 3.98 MB, 44.1 kHz mono 16-bit, 0.05-16.7 s each, no tags | Web Audio synthesis rendered offline (bake.js; sound.gd header); no samples | L; quality weak | normalise: 24 of 31 peak below -15 dBFS, 14 below -30, scrape_* about -50 |
| fonts | 5 TTF, 535 KB, OFL.txt | Barlow and Barlow Condensed 1.408, Jeremy Tribby, SIL OFL 1.1, fetched 2026-09-29 from github.com/google/fonts | L | ship OFL.txt (not exported into the pck); Latin only |
| data, icon.svg, build/ | map.json+sites.json 180 KB; icon 995 B; zip 26.4 MB, itch-page cover 630x500 + 3 JPG 1600x910 (1.36 MB) | own data; icon is Godot's stock one; build is git-ignored | placeholder | replace icon |

**Styles.** A: flat-shaded, dark-outlined code art (objects, pawns, portraits, trees, walls, weapons). B: noise-painted soft textures (terrain). C: AI hand-inked cartoon (deck_*). D: AI painterly isometric dioramas (sites). E: white line icons.

**Inconsistencies.** Density, px per tile: decals 64, props 96, vehicles/containers/roofs/trees/walls 112, terrain 128, pawns 160, weapons and deck_* 192; world 64, zoom to 84. At max zoom on Retina props upsample 1.5-1.75x and decals 2.6x while pawns and decks stay sharp. deck_* is visibly richer than the flat props; the site cards match nothing else. 24 zombies share one template. `objects/308_spray.png` bakes English ("TURN BACK").

**Unused/duplicate.** 660 of 678 files are referenced by literal path (map.json, sites.json, scripts); 12 `deck_*` by prefix (deck_faces.gd:97-104); OFL.txt is a licence. Orphans: objects/158-162_ladder.png, 19 KB (pieces emptied in map.json). 16 byte-identical groups, 90 files, 0.41 MB (50 lockers are 2 images). Decoded textures about 270 MB (360 with mipmaps; import is lossless, no VRAM compression): walls 3 x 12.3 MB, roofs 49 MB, `131_tufts.png` 734x905 at 0.9% painted.

## 2. Provenance evidence and unknowns
- Git: everything except icons, sites and decks arrived in 5955b08 ("synthesised sound", "Barlow fonts bundled (OFL)"). No generator script, .glb or .blend ever in history. Downloads in the transcripts: Barlow, Godot templates, Meshy outputs only.
- Generator source: the web project went to ~/.Trash on 2026-09-29; ~/.Trash is a 64-byte directory (looks empty; listing is blocked) and Spotlight finds no bake.js or pawn.js. Only surviving copy: the transcript ~/.claude/projects/-Users-jaf-lab-test/d1c4c8cf-1429-4b60-bc6e-25afc38c0154.jsonl. Back it up. The Meshy 2.5D/3D characters were dropped, not shipped.
- Meshy plan: unprovable from files. Balance 499 (09-28), 248 (09-30), 2043 (10-01 04:53Z, after the 00:00Z monthly reset) exceeds the Free tier's 100 a month, so paid on both dates is likely (inference). Meshy's help says rights follow the plan at generation time (Free: CC BY 4.0 plus credit; paid: private, owned, commercial), but that article covers 3D models only, and nano-banana-pro is a Google model hosted by fal.ai: its extra terms or watermark are unknown. AI output may lack US copyright, so ownership is weak even where the licence is clean.
- Franchise/brand grep (scripts, data, scenes, project, svg): clean. RimWorld, They Are Billions, Prison Architect appear only in docs/superpowers/specs and the first commit message. Vehicles carry no logos. Soft spots: "walker" (8 UI strings, Walking Dead vocabulary); red-cross cabinet `085_cabinet.png` and Ana's badge (`portraits/ana.png`; protected emblem, use green).
- itch AI disclosure was answered Yes (graphics, sounds, text, code). Steam asks the same for player-facing AI content (dev-tool use exempt).

## 4. Release readiness
- **Presets.** Only Web (single-thread, `all_resources`; excludes README.md only, so tests/ and tools/ scripts ship; add `tests/*,tools/*,docs/*`). 4.7.2 templates for macOS, Windows, Linux are installed. Needed: Windows .ico (rcedit; Wine on macOS unless 4.7 changed that; Authenticode optional); macOS universal .icns, bundle ID, Developer ID signing, notarisation, entitlements for third-party dylibs (GodotSteam); Linux PNG icon; version/company. Icon, loading splash (Godot logo, index.png) and window title ("LastBell") are stock.
- **Steam.** $100 per app, 21 days after fee, Coming Soon page 2+ weeks, 1-5 day review, bank and tax. GodotSteam plus steam_appid, depots per OS, Auto-Cloud, achievements (none), store art: header 920x430, small 462x174, main 1232x706, vertical 748x896, 5+ screenshots at 1920x1080 (itch shots are 1600x910; library, logo and icon sizes: check docs). Content survey with AI answers.
- **Web.** build/LastBell-web.zip 26.44 MB, stale (2026-09-29, from main): wasm 39.5 MB raw/10.1 zipped (38%), pck 17.3 MB (61%): objects 9.4 MB, terrain 3.2, pawns 1.9. This branch adds about 1.5 MB (estimate). Single-thread build needs no SharedArrayBuffer or COOP/COEP; keep it. About 21 s first load at 10 Mbit/s. Audio waits for the first click (not tested). 360 MB textures strain low-RAM devices; touch unsupported. Web runs Compatibility, desktop Forward+ (D3D12 on Windows): test both.
- **Settings/accessibility.** Only mute and help. No start, pause or quit menu (Esc clears selection), volume, fullscreen, UI scale, rebinding, colour-blind cues or subtitles. HUD labels mostly 12-13 px (min 10). No settings file.
- **Saves.** `user://quicksave.json`, `autosave.json` (21.6 KB), JSON, VERSION 1 (save_game.gd:35), atomic write, other versions refused, no migration, one slot. macOS ~/Library/Application Support/Godot/app_userdata/LastBell; renaming `config/name` moves it, so set a custom user dir. Web: IndexedDB.
- **Errors.** No handler, telemetry, network code or report button; only Godot's rotating logs/godot.log.
- **Localisation.** 0 `tr()`; about 190 multi-word (320 incl. labels) literals in 10 scripts, English plural logic in 5 places, names in map.json/sites.json, baked text; Barlow lacks Cyrillic/Greek/CJK.
- **Controller.** None: raw mouse/keys, no InputMap or gamepad (main.gd:428-500). Deck: Playable at best.
- **Window.** 1280x800 base, canvas_items/expand, opens at 94% of screen, no fullscreen toggle.

## 5. Name
"Last Bell" appears in README.md:1, project.godot `config/name="LastBell"` (window, web title, save folder), scripts/main.gd:1,209, tools/balance.gd:402, docs spec (twice: "check the name"), jafforge.itch.io/last-bell, github.com/jafforgehq/last-bell. Not on any screen or asset; "bell" is a mechanic. Collisions not checked.

**Name check, 2026-10-01 (after the rename to Thirty Bells).** Three web searches ("Thirty Bells" with Steam, with zombie and schoolyard, with trademark or itch.io) found no game, product or trademark called Thirty Bells. Near neighbours: [Ten Bells](https://store.steampowered.com/app/3044030/Ten_Bells/) (Steam, 2024, an anomaly horror game in a pub; thirty anomalies are in its blurb), [The Silent Bells](https://store.steampowered.com/app/2166870/The_Silent_Bells/) and [Dream of Bells](https://store.steampowered.com/app/1602770/Dream_of_Bells/). They are different titles in different genres, but "Bells" is a crowded word, so the name will share search results with them. A web search is not a trademark search: before the Steam page, search the USPTO and EUIPO databases for classes 9 and 41 and look the name up in Steam's own store search.

**Status after rounds 3 and 4 (2026-10-01).** Done from the list below: items 3 (credits screen with the Godot and Barlow lines; the AI-pictures line says so plainly), 5 in part (the name; a custom user directory `ThirtyBells` was set; icon and splash are still Godot's), 6 in part (the web export leaves out tests, tools and docs), 7 (a pause menu, settings with volumes, interface size and fullscreen, saved in `user://prefs.cfg`). Round 3 added seven Meshy pictures (six materials and the scrapyard picture, 63 credits), all logged in `docs/assets-log.md`; the count of AI-made pictures to prove is now 22, not 15.

## 6. Before the Steam page (effort)
1. Prove Meshy plan; keep task IDs and prompts for the 15 images, or redraw (S).
2. Back up the transcript generator source and the art (S).
3. Rights ledger, credits screen: Godot MIT notices, Barlow OFL, include OFL.txt in builds (S).
4. Steam AI disclosure matching itch (S).
5. New icon, splash, name "Last Bell", version, custom user dir (S).
6. Exclude tests/tools/docs; Windows, macOS (sign, notarise), Linux presets (M).
7. Pause/settings menu: volume, fullscreen, UI scale, quit, persisted (M).
8. Audio pass and music plan (M).
9. Store art, 1920x1080 screenshots, trailer; artist for capsule art (M).
10. GodotSteam, Auto-Cloud, achievements (M).
11. Name and trademark check, green cross, delete 5 orphan ladders (S).
12. Texture memory: VRAM compression, trim walls/roofs/tufts (M).
13. Error log attach, report link (S).
14. Controller and key rebinding (L).
15. String externalisation and fallback fonts (L, defer to Early Access).

Not verified: Developer ID, Meshy invoices and image terms, Trash contents, browser audio unlock, in-browser memory, Steam library-art sizes, 4.7 Windows icon tooling. I ran `Godot --version` once (prints a version string only, no project) despite the no-Godot instruction. Untracked `docs/audit/` appeared in the repo at 08:40; not created by me.

Sources: help.meshy.ai/en/articles/16102098, help.meshy.ai/en/articles/9992001, docs.meshy.ai/en/webapp/pricing, partner.steamgames.com/doc/gettingstarted/contentsurvey, partner.steamgames.com/doc/store/assets/standard, partner.steamgames.com/doc/gettingstarted/onboarding.
