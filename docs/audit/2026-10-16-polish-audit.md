# Polish audit, playtest-3 (2026-10-16)

Three agents played the prison game windowed at 1280x720 using staging flags and bots, took 79 screenshots, and graded every screen. The screenshots are in `build/audit-2026-10-16/` (git-ignored): `a_menus_clear/`, `b_base/`, `c_raids_endings/`. The lead checked the worst ones by eye. No code was changed for this audit.

Overall: the world art, the title and menu screens, the ending cards, the destination map and the top bar are in good shape. The game is held back by five themes, in this order.

## 1. Text piles up in the middle of the screen (the biggest problem)

Almost every screenshot has two to four text layers stacked on or near the crosshair: subtitles, prompts, toasts, hints, banners, barks and name pills. The player's eye has nowhere to rest, and the world is covered where the action is.

- First frames stack the "Day 1" line, the "THE OLD PRISON" band across the middle third, and a two-line controls hint under the crosshair (`a/08_first_frame`).
- The day-1 base line "The compound. Walk around..." stays from 08:00 to 19:36 over the crosshair and GATE label (`b/01`, `02`, `10`, `11`, `13`, `14`, `19`, `21`).
- "The prison is yours. Hold it.", "Raid for loot" and "E: take the truck out" stack over the gate at the hand-over (`a/22_secure_04`).
- The first-raid hint runs through the crosshair; screamer and breacher messages show twice, as a toast and a centre line (`c/04`, `05`, `07`, `09`; `b/18`).
- "Saved at dawn." prints over the crosshair (`a/07`).
- Ally pills overlap each other ("Cole - Ike following", "Fo[Bea]llow"); "Ike - Ally: firing" plus a "Firing" pill say the same thing twice (`a/08`, `a/12`).

Fix (one change, biggest win): a single message system with three fixed lanes: a top banner lane for big moments, a toast lane on the right under Objectives, and a prompt lane just above the weapon panel. Never draw text within about 120 px of the crosshair. Queue messages instead of stacking them, show each message once, and fade the day-1 intro line after 10 seconds or the first B press. Ally pills only on hover or state change.

## 2. Wrong or contradictory information

These break trust and look like bugs to a player.

- A night raid shows a NIGHT chip, but the clock says 08:26 with a sun and "Clear day"; the world is barely darker (`c/06`, `19`, `21`).
- After Start, a paid project still says "20 scrap (short 10)" in red (`b/09`).
- The Needs tab says food Made +0, Used -4, Net -7 (spoilage is missing from the sum) (`b/05`).
- The east-entry variant still says "west breach" in the guide card and the secured card, and draws the WEST BREACH label in the west (`a/20`; `prison_game.gd:1986`, `:2768`, `prison_guide.gd:14`).
- The ending prose says "0 dead were shot at its fence", "you built 0 things" and "On night 0 the wall went" after 11 nights held (`c/24` to `27`; possibly partly from `--day` staging).
- The pause Controls page says "B: the roster"; B is the Base screen (`a/06`).
- New game shows "Always aim at the mouse" selected while Settings shows "Right button aims" (`a/02`, `a/03`).
- Day 1 shows "Horde tonight" (night 1 is a forced horde by design; the player is not told why) (`a/22_secure_04`).
- "Horde tonight in 3:13" next to an 08:07 clock reads as hours but is minutes:seconds (`b/01` to `20`).
- The fence chip flips between "Fence 10/10 intact" and "100% sound" (`b/15`, `b/20`).
- The zone marker says "Cell block" while its ring says "DORMITORY" (`a/12`, `a/13`).
- The pack's melee slot says "F Swing" with a bat icon; the HUD says "F: Knife" (`a/12`).
- The Shelter stage card's "Next" line repeats the stage just reached (`b/21`).
- Guards are tagged "Firing" on a quiet night while their bark says "Nothing out there" (`b/15`).

## 3. Big moments have no weight

- PRISON SECURED, the end of the clear phase, is a small caption on black for 1.6 s (`a/22`, `a/24`). It should be a large banner with zones, kills and loot for 3 s or more, with a sound.
- Raid start, return and death show 4 to 6 s of black with one line of text (`c/18`, `c/30`). It should be under 2 s and skippable, with the world faded behind.
- After extraction or death, the only result is one small line over the GATE label (`c/31`, `c/33`). It should be a short card: banked, lost, spent.
- The horde fight at the fence happens in the bottom 15 percent of the screen, under the weapon panel, Base button and minimap (`b/16` to `18`). At night the camera should frame the fence mid-screen. No damage numbers were seen.
- Low health is a short red sliver in an unlabelled bar; the full bar is solid red all the time (`a/16`). The bar should be neutral when healthy, with an hp number and a red edge vignette below 25 percent.

## 4. Raid places do not look like their names

Port, airport, stadium and hospital all use the same four-block street grid with garages and hardware stores; the airport has "Hardware: parts, hangars" (`c/09` to `12`). There is no quay water, runway or stadium bowl in the generated map. On the map view, loot rings overlap and their labels collide and run under the HUD (`c/10`, `c/11`). The fog is blotchy, with a hard seam (`c/08`), and the hospital patient is hidden under the danger disc (`c/21`). This is the largest piece of work in the list, but also the one that makes the raid map promise feel kept.

## 5. Panels and screens

- The Base screen is see-through: subtitles and Objectives show through it, and it covers the morale chip (`b/03` to `09`). Make it nearly opaque and start it below the top bar.
- The Defence tab is wider than the others and covers the minimap; Barricades are below the fold with no scroll cue (`b/07`).
- The pause Controls list runs off the screen, with no scrollbar or Back button (`a/06`).
- The evacuation ending card is taller than 720 px (`c/24`).
- The Objectives panel covers the loadout card's right edge and clips the weapon text; the squad list is cut mid-row (`c/03`).
- The orders "wheel" (C) is a flat text table with the current order shown only as "(Hold)" text (`c/22`).
- The primary Start button is dark on dark (`b/03`); renaming has no visible affordance (`b/06`); Story tab checkboxes are typed as "[ ]" (`b/08`); "Danger: ##---" looks like placeholder text (`c/01`).
- The pause panel is flat teal while the other menus use the chalkboard-and-wood frame, and it shows the "What felt wrong?" tester field to every player (`a/05`).
- Closed doors are a thin brown line, hard to tell from wall trim (`a/14`); night guards are nearly invisible apart from their rings (`b/15`, `b/23`).

## What already looks good

- World art is coherent RimWorld-style: buildings, floors and the dead read clearly.
- Title, New game, Settings and Credits share a strong chalkboard-and-wood style with clear selected states.
- The ending cards have strong typography, a score breakdown, a run table and the Copy report button.
- The destination map reads at a glance: places, locked days, danger, "You may find" with often/sometimes/rarely.
- The top-bar chips have clear icons, trend arrows and useful tooltips.
- Door swing, the reload ring, the last-round flash and the noise pill all read at a glance.

## Not captured

The stranger-at-the-gate card (no flag forces an event), the dawn banner (covered by the radio card), the quit-risk badge (not seen even at morale 20), the Base button dot, the Milestones panel, the knife prompt in a fight, an ally down with the revive prompt, New game plus, and the searched-container marks. The `raidx` drive reported two failures in this run: a preset kept only one companion, and one patient found where it expected one or two (both pass with `--managed`; worth a check).

## Suggested order of fixes

1. One message system with fixed lanes and nothing near the crosshair (theme 1).
2. The wrong-information list (theme 2), all small text and data fixes.
3. Weight for PRISON SECURED, the raid return card, faster raid transitions, the night fence camera and the low-health cue (theme 3).
4. Panel fixes (theme 5).
5. Distinct raid place layouts (theme 4), the largest job.
