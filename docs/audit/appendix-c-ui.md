# Appendix C: UI/UX review, tutorial design and redesign blueprint

> A read-only review of the HUD code and input handling. Line numbers refer to HEAD e4fa379. Part of [the full audit](2026-10-01-full-audit.md), 2026-10-01, repo HEAD e4fa379.

## 1. What exists today
**Boot:** none. `main.tscn` runs `main.gd:_ready`, builds the world, starts a Standard run with a random seed (main.gd:123-132). No menu, difficulty/seed choice, pause menu (Esc only deselects, :478), settings, slots, codex, credits, quit; Godot's default splash. A victory screen exists but no rule sets it (scenario.gd:1-3). No Theme, InputMap, ConfigFile, `tr()` or audio buses (grep).

**Screens** (code-built, no scenes): world overlay (overlay_node.gd: names, HP/wall bars, selection, range ring). HUD (hud.gd): stores top-left (:303), crew cards top-centre (:368), clock top-right (:498), alert feed below (:550; max 5, click jumps camera), banner (:598), selection panel plus 4-7 order buttons bottom-left (:629), speed/sound/help bottom-right (:990), help panel (:1029), one-line hint (:1046). Modals: scavenge dialog; game over (stats; New game / Load last save).

**Scaling:** canvas_items/expand, base 1280x800, but `_update_scale` sets content size to window / OS scale (main.gd:250-257): constant physical size, no user scale. <980 wide = compact (store names hidden, 48 px cards, hud.gd:1158-1167); <640 = alerts hidden (:1175).

**Tests:** 82 headless HUD tests (overlap sweeps 700-1400 wide, gating, dialog, fuzz); none for look, input pipeline, tooltips, scaling, widths <700.

## 2. Problems, ranked
**High**
1. **No onboarding.** The run starts unpaused at 07:00; the only guidance is a hint that dies at first selection (hud.gd:714), hidden <980 px (:1168). Bell, nights, goal: explained nowhere.
2. **Orders undiscoverable, refusals silent.** Big order buttons lack tooltips (mini mode only, :881); key letters are 10 px grey (:889); help (:1036) omits P F C 1-3 Esc F5 F9; "Draft" is jargon and drafted people stay put until R. Silent when `order_move` is refused (sim.gd:332), F with nothing damaged (main.gd:366-371), T/X unavailable, nothing selected. A right-click on open ground outside the wall has no path and falls back to a straight line through it (sim.gd:519-523; code reading, not run).
3. **Readability.** 10-13 px text (hud.gd:224, 273, 889); INK3 #7c7565 (:14) is 3.0-4.1:1 yet carries captions, days-left, key hints; panels are 86% opaque. No UI scale; 1:1 scaling means tiny UI at 4K/100% and on a 7" Steam Deck (`screen_get_scale` on Windows/Linux unverified). Small laptops OK (tested 700x560).
4. **Colour-only state.** HP and days-left use green/orange/red (hud.gd:1197, 1292; overlay_node.gd:109); deuteranopia simulation: OK vs WARN 1.06:1, OK vs DANGER 1.4:1. No colour-blind mode.
5. **Alerts.** TTL counts sim seconds (sim.gd:465): 4-6 s alerts last ~1.5 s at 3x. `seg-N` text changes every claw (sim.gd:869), so the feed is rebuilt up to 10x/s in a siege (hud.gd:1333-1341), eating clicks, and each build leaks an unparented ColorRect (`edge`, :567-569). Icon follows level, not type: warn shows the walker (:29). Sub-lines don't wrap (:579): medical.gd:640 probably widens the feed over the cards when narrow (unverified).

**Medium**
6. Selection/camera: single selection, no box/groups/hotkeys (digits are speed); Tab cycles dead and away people (main.gd:499); LMB-drag pans (:441), blocking box-select; WASD by logical keycode (:517, wrong on AZERTY); no home key or minimap; posts fixed per person; no focus-fire.
7. Input: no remapping; every button FOCUS_NONE (hud.gd:864, 970, 1129): no keyboard/gamepad UI; no touch right-click (web touch gestures unverified); browser F5 vs save key (unverified).
8. Hierarchy: equal-weight panels; wall health only as world bars (overlay_node.gd:48), no 14-section overview; no ETA on "Away"; ammo lacks days-left; banners overwrite each other (hud.gd:616), no log, no PAUSED mark.
9. Strings are literals everywhere, including sim alerts and plurals (hud.gd:1474); Barlow glyph coverage unverified. Styling: 29 style-box sites, 54 overrides in hud.gd, colours duplicated (overlay_node.gd:9, 56; modules), default tooltip theme.
10. Save UX: F5/F9 only, one quick plus one autosave, no slot list (main.gd:404-418, 676). Audio: one master mute, not persisted (sound.gd:76).

**Low** HUD tick is cheap (earlier scratchpad profile, not mine: 0.04 ms/frame, 4 walkers) but wasteful: theme overrides plus a new StyleBoxFlat per tick (hud.gd:1287-1300), `_pick` sorts on every mouse move (main.gd:318).

## 3. Tutorial: "Orientation Day" (~9 min, scripted scenario)
**Rules:** cannot fail (Story, `permadeath=false`, wall floor 20%, never `over`); sim paused during teach cards; soft lock (every intent refused except the step's own, camera, pause); 20 s idle escalates pulse, arrow, "Show me"; skip anywhere; replayable.

**Steps** (done = condition; hl = highlight):
1. Pan 8 tiles, zoom 20%. 2. Click Ruth (hl card). 3. Right-click the ring (Ruth within 0.8 tile). 4. R: back to routine; "drafted = obeys only you" (`!drafted`; hl Draft). 5. Ladders: Hector, P (`order.z>0.5`; hl Post, 3 north ladders). 6. C follows him. 7. Click the pre-damaged bus (45%), F: 1 scrap per 10 HP (`repair==seg`; hl wall, Repair, Scrap). 8. Wait (`repaired` event). 9. Stores, days-left. 10. Ana, G, Houses, Send (`scavenge.parties.size()==1`; hl card, Scavenge, site, Send). 11. Press 3 (event `trip_back`). 12. 19:00 bell, posts, "more each night" (event `bell`; hl clock). 13. Marcus: ring = range, pips = rounds, shots cost ammo (`kills>=3`; hl weapon row, Ammo). 14. Click the alert (`on_alert`; scripted claws at the bus). 15. Walt scratched: Ana bandages, 1 medicine (`bleeding==0`; hl marks). 16. Hector feverish: T treats (2 medicine); X exiles (locked, explained) (`infected_at<0`). 17. Dawn: autosave; F5 saves to a tutorial slot (`day_start`). 18. Wrap-up: real run / replay / keep playing.

**Scripted night:** `Orientation extends scenario.gd`, swapped in as tests do (hud_kit.gd:100-105). `start()`: seed const, 07:00, `waves.enabled=false` (waves.gd:27), bus 45%. `update()` fires beats on `sim.clock_min`: 19:20 three walkers at (55,0.5), 20:30 four more, 21:30 scratch Walt, 22:00 infect Hector (6.2 h ago, turn +72 h). Rules-side, so headless-testable; SaveGame persists it by reflection (save_game.gd:121); no autosave in tutorial runs (main.gd:674). Scripted = this scenario (offered at first launch and from the menu), ending in a Standard run; all else is normal, taught by hints.

**Architecture:** `assets/data/tutorial.json` (text keys, targets, allow lists, done = {cond, params}) plus a `conditions.gd` registry. `scripts/ui/coach.gd`: CanvasLayer 4, mouse IGNORE: dim, ring/arrow, callout, dots, Skip; resolves targets every frame (gizmos are rebuilt, hud.gd:896). Gate: `main._allows(kind,arg)`, consulted only while a gate exists; HUD buttons ghosted via `hud.set_locked`; no blocking overlay: real game and tests untouched. `prefs.gd`: ConfigFile `user://prefs.cfg` (`tutorial_done`, `hints_seen`, volumes, ui_scale; IndexedDB on web). Contextual hints in normal runs reuse Coach and flags (first dusk, alert, low food, wound, breach, draft).

**Hooks:** main.gd 123-132 `run.scenario`; 185-196 build Coach; 312/346/430/453/470 `_did(kind,arg)` (centralise speed); 428 gate; 508 `coach.tick`; 639-669 `coach.on_event`; 404/414 slot path. hud.gd 166 `anchor_rect(name)` (`stores.<k>`, `card:<id>`, `clock`, `alerts`, `gizmo:<id>`, `speed.<n>`, `dialog.send`); 616 `toast()` (also refusals); 860 locked look; 1046 replace hint. sim.gd 326-356 orders emit `order` events; 532 `repaired`; 867 add `seg` to `claw`; add `set_hour()` (main.gd:692), `damage_segment_to()` (:715). scavenge.gd 434/487 `trip_back`/`trip_out`; medical.gd 205-222 extract `scratch()`, add `infect()`, `treated` at :625. Usable now: events bell, day_start, banner, thud, claw, hammer, turned, over; alerts by id (`seg-N`, `fever-<id>`, `scav-N`, `low-water`).

## 4. UI redesign blueprint
**Identity:** schoolyard noticeboard: slate chalkboard panels in oak trim, chalk ink (#ece6d8), bus yellow (#f0c24a, already the accent), brass-bell clock, hall-pass crew badges, pinned carbon "detention slip" alerts, notebook-paper modals (a trip is a permission slip), report-card end screen. HUD stays dark; paper only in modals.

**Layout** (1280x800; 1920x1080 = same at ui_scale 1.35; body 14 px, captions 12, nothing smaller): top-left stores plus defence strip (14 wall pills N/W/E, pattern-coded, click focuses); top-centre six badges 72x96 (HP/ammo pips, 16 px marks, away ETA); top-right time cluster (bell clock, dusk countdown, speed buttons, PAUSED stamp) over max 4 slips plus log; bottom-left selection (three big facts, rest folded) and order bar (14 px labels, key chips, tooltips say what and why disabled); bottom-right minimap, menu, help, sound; centre toast, banner, coach.

**Theme:** one `assets/ui/theme/last_bell.theme` built by `tools/build_theme.gd` (as make_icons.gd does), set as project default (tooltips) and on the HUD root. Type variations (Panel.Chalk/Paper/Slip/Badge, Button.Command/Primary/Tool, ProgressBar.Chalk with hatch fill, KeyChip) replace `_style/_label/_button` via a `UiKit` factory. Palette = theme colours; high-contrast and colour-blind variants swap at runtime; overlay_node shares it. Keep field names (`cards`, `gizmos`, `inspect_refs`) so the 82 tests survive. Fixes: INK3 to #9a937f (4.55:1), panel alpha .94, DANGER text #ef6c5d.

**Art rules:** 9-slice at 2x (192 px sources, 24 px margins) as StyleBoxTexture, baked shadows (cheaper on web). Icons stay white-on-alpha tinted glyphs, 128 px; alerts get type icons. Type: Barlow stays (OFL); add Special Elite (slips), Caveat (chalk notes); check licences and glyphs; sizes 12/14/16/22/30.

**Motion/sound:** slip pin-drop, floating store deltas, bell swing at 19:00, eased camera to alerts, chalk-write banners, reduce-motion toggle; buses SFX/UI/Ambience/Music with sliders; UI click/confirm/error, alert chimes.

**Menus:** title (Continue, New game with difficulty/seed/permadeath, Orientation Day, Load, Settings, Credits, Quit), Esc pause, settings (audio, UI scale, palette, remap, hints), report card.

**New assets, by batch:**
A. Seamless 1024 px materials: slate, oak, ruled paper, brass, cork, carbon paper. Generate these, then assemble frames with a Pillow script (like tools/make_deck_art.py) so 9-slice edges are exact; don't prompt for frames.
B. Frames: panel_chalk 192, panel_inset 128, paper_page 192, slip 192x128, badge 160x208 (+selected), dialog_frame 384, tooltip 96, toast 192x64, bar track/fill 256x32, key_chip 64, buttons (4 kinds x 4 states) 96, pushpin 48.
C. Icons, 128 px white-alpha, ~70: redo the 35; add bell_clock, ladder, wall_n/w/e, breach, bandage, pill, canteen, crate, ammo_box, hammer, skull, save, gear, minimap, log, mouse buttons, keycap.
D. Cursors 64 px x 8.
E. Illustrations: chalk doodle sheet 1024; narrator bust 512 x 3; crew portraits 256 x 3 states x 6; stamps 512; 6 more sites 720x405.
F. Key art: logo 2048x768 (+1-colour); title 3840x2160 in 4 parallax layers; loading 1920x1080; Steam capsules 460x215, 616x353, 374x448, hero 3840x1240, logo 1280x720 (verify sizes in Steamworks docs); five 1920x1080 screenshots.
G. Audio: ~20 UI sfx, 4 music loops. Log prompt, model, date per asset (rights audit; Steam requires AI-content disclosure).

## 5. Effort and order
1. Quick fixes (S): leak, alert rebuild, type icons, tooltips, refusal toasts, 12 px floor, contrast, Tab, help. 2. Foundation (M): prefs, InputMap, buses, ui_scale (main.gd:257), `anchor_rect`, `_did`, sim events. 3. Theme/UiKit port (L), with art pass 1 (batches A-D: materials, frames, icons, cursors) (L) in parallel. 4. Menus, pause, settings, slots, report card (L). 5. Orientation Day, hints, bot test (L). 6. Juice, UI sound (M); itch demo. 7. Art pass 2 (batches E-F: illustrations, key art, capsules) (M); Steam page. 8. Early Access: localisation (L), controller/Deck (L), accessibility (M). Art lands last: the Theme makes it a data swap; tutorial anchors survive re-skins.
