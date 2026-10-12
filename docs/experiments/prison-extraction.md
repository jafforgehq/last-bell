# Experiment: prison base + extraction raids (branch experiment/prison-extraction, from main 6cfb26b)

## What exists
- **Base**: a hand-authored 96 x 72 prison compound (`scripts/prison/prison_base.gd`): perimeter fence, two 24 x 15 cell blocks with 24 cells, canteen with kitchen, infirmary, workshop, stores, a walled garden, six watchtowers, a gate with sandbags and a truck. It is built as a TownGen-shaped town dictionary (grids, objects, kit codes), so the real `TownWorld`, `TownRun`/`TownSim` (Ruth, shooting, dormant dead) and renderer run it unchanged.
- **Ten people** (`prison_crew.gd`): Walt and Dez (tower guards), Mia (cook), Marcus and Nia (gardeners), Ana (medic), Hector (mechanic), Tomas (fence crew), Owen (hauler), June (patrol). Real `Sim.Person` objects drawn by the real PawnNode with the real work poses (sort, bench, garden, nurse, mend, haul, radio, watch). They walk routes with the town path finder, work at stations, and each finished stop changes the stores (garden +food, cook -food/-water, hauler +water, mechanic scrap -> ammo, medic scrap -> meds, fence crew -scrap). Floating "+1.5 food" text and a name/job/progress tag over each.
- **Dead at the fence**: 72 dormant records in the pen south of the gate, woken (real zombies, standing/shuffling, `sim.quiet` so they ignore Ruth) by a large wake radius; drawn by the real zombie art.
- **Go out**: E at the gate or truck (cutscene: fade, truck sliding across, caption), then a raid in a generated 64 x 64 town (`TownGen.make(seed, {blocks:2})`): houses, cars, containers, dormant dead that wake near you (the dead within 16 tiles of the drop are removed). The pack is a separate stock: 40 rounds and 1 med taken from the base stores.
- **Raid play**: real avatar, shotgun, melee (F), reload (R), E searches containers/cars/doors (real `sim.uses` and `sim.search`); loot goes to the pack stock. Two pickup rings (the drop-off, armed only after you walk 14+ tiles away, and the far road end), green edge arrows, a 2 s hold.
- **Extract**: cutscene, then the pack (loot + unspent ammo/meds) is added to the base stores and the base is rebuilt; a "Banked: +x" line shows. **Die**: cutscene, pack lost (ammo/med loadout gone), back at base.
- **Menu**: windowed "New game" (town meta, no save, no `--town`) boots the prison. `--onehouse` forces the old game; `--prison` forces this one. Headless runs (tests) are never redirected.

## Run it
```
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/jaf_lab/last-bell/.worktrees/exp-prison -- --prison
```
Keys: WASD, mouse aim, left button fire (raid only), R reload, F melee, E use/go out, wheel zoom, M overview, Esc quit.
Checks: `-- --prison --shot=out.png --frames=300 [--at=x,y] [--cam=x,y,zoom]`, `--raid [--seed=N]`, `--auto=extract|die|full|go` (scripted endings; frames run fast, use `--frames=2000` or more for a full cutscene round trip). Verified: base boots with 10 working NPCs and the crowd (screens), a raid starts, search works (car searched, looted flag set), extract banks (ammo 40 -> 80 back in stores), die loses the pack (ammo 80 -> 40), go-out cutscene hands over to a raid. Main menu click was NOT tested by hand (only the same code path via `--prison`).

## Screenshots (docs/experiments/prison/)
base_overview.png, base_gate_dead.png, base_kitchen.png, raid_start.png, after_extract.png

## Reused
TownGen (template and the raid map), TownWorld/chunk painter and art kit, TownRun/TownSim (avatar, shooting, melee, dormant dead, search/uses, door clearing), PawnNode + WorkAnim, FX, TownRoofs, path finder, game data. No sim code was changed (only `main.gd` got a hand-over of about 12 lines), so no golden tests were run.

## Fake or missing
- No inventory grid UI: the pack is a plain stock dictionary (food, water, ammo, meds, scrap). The backpack code (`sim.inv`) was not wired.
- NPCs are not in the sim: zombies never target them, they cannot be hurt, no needs, no relations. Bodies are the 5 baked sprites with palette tweaks, so some NPCs share a face. Tower guards stand on a drawn deck; nobody shoots.
- The base has no day/night, no attacks on the fence, no building, no saving. Stores consumption is only the cook's meal cycle. The fence is only a collision and a picture; the dead never get through.
- The compound is a box layout (fence drawn as a thin chain link, no yard variety, no roofs, no lights, flat daylight). The map is not the real prison silhouette.
- Raid map is the small generated town, one per raid, no loot rarity, no weapons variety, no extra ranged enemies. Exits are only road ends. The truck cutscene is drawn rectangles.
- Hunger/thirst of Ruth and the dark look of the One House game are not applied. Raid clock is fixed daytime.

## Verdict
Feasible and surprisingly cheap: the whole loop (base, crew, go out, search, fight, extract, bank, die) took one session because the town stack already does the hard parts. The base is fun to look at for about a minute (people at work, the mass at the fence reads well); the loop's tension is carried by the raid, which already plays like a small extraction shooter (the dead wake as you search). What decides if it is a game is not here yet: why you go out (needs: stores that drain, a goal), what you carry (inventory, risk), and what the base gives back (upgrades). Without those it is a tech demo, but a convincing one.

## Effort to make it real (rough)
- 1 to 2 weeks: wire the real backpack/inv UI into the raid and base stores; real needs for the crew (food/water drain, shortage consequences); better raid maps (districts, 2 to 3 sizes, longer raids, exit variety, loot tables with rarity); day/night and the dark look.
- 2 to 3 weeks: base threats (the mass pressing the fence, fence health the mender actually restores, night attacks), upgrades (workshop tiers, tower guards that shoot), NPC injuries/deaths and recruits found in raids, saving.
- 2+ weeks art/sound pass (prison tiles, towers, gate, more NPC bodies, truck, cutscene art). Total about 6 to 8 weeks for a small shippable version.

## Round 2 (owner feedback)
- **Rotation**: the base forced her aim to a fixed point south (my bug: `aim = (x, y+3)` in the base). Removed; she now turns to the mouse and walks facing like in a raid. `--aimdir=dx,dy` forces an aim for screenshots: base_aim_east.png vs base_aim_northwest.png.
- **Minimap**: own small full-map minimap (bottom right; not scripts/ui/minimap.gd, which is tied to Main and the HUD): terrain, gate (gold), crew (cyan), awake dead (red), the dead pen tint, extraction rings in a raid, her heading arrow and the camera window.
- **Fence guns**: 4 tower guards (Walt, Dez, Rae, Sol) shoot the dead that come within 5 tiles of the fence (muzzle flash and tracer from fx, the real rifle sound, 80 percent hit, the dead fall and bleed). New walkers drift in from the pen edges every 2 s (up to 66 awake) and a slow trickle is sent toward the gate fence. 4 or more at the fence: bell, banner "ALARM", the guards fire faster for 14 s and shout. Shot counter in the HUD.
- **Life**: crew chat in pairs (3 pairs, "heh" bubbles), everyone eats at the canteen at 07, 13, 19 h, June relieves the gate guard, two kids play in the yard, a dog (the existing dog_node), a washing line, campfires and lamps with additive glow, a 6 minute day/night (dusk tint, fires and tower lamps at night; `--hour=H` to set it), ambience loops (wind, crickets by night, the horde's moan by the pen) and real combat sounds in the raid too (it was silent before).
- **Trees**: Blender MCP was NOT reachable (every call: "Could not connect to Blender"), so no Blender renders. Instead `tools/make_prison_trees.py` draws 3 new variants in the same style as assets/trees (scrub bush tree_18, dry scrub tree_19, ragged dead pine tree_20); the base uses green, pine, dead and scrub only in loose margins, the border belt is green only, and the raid town swaps its orange/yellow trees for greens. Before/after: base_overview.png vs base_overview_v2.png, raid_start.png vs raid_start_v2.png.
- New screenshots: base_gate_guards.png, base_night.png, base_aim_east.png, base_aim_northwest.png, base_overview_v2.png, raid_start_v2.png.
- Still fake: guards never miss the pen's far dead, no ammo cost for the guards, the dead killed pile up as corpses until the sim clears them.

## Round 3: trees in Blender
The Blender MCP stayed unreachable, so the trees are modelled and rendered with HEADLESS Blender 5.2.1 (`/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/make_prison_trees_blender.py`, then `python3 tools/finish_prison_trees.py` for the sprite size and the soft shadow). Four variants, procedural: tree_21 bare dead tree with forking limbs, tree_22 pine, tree_23 scrub bush, tree_24 broadleaf with a clumpy low-poly crown. Workbench flat colours from the existing tree palette, Freestyle ink outline (34 26 19), orthographic camera at 68 degrees, 314 x 359, transparent. The scripts are in tools/, the .blend and raw renders in docs/experiments/prison/blender/. The earlier PIL trees (tree_18 to 20) were moved to ~/.Trash/prison-pil. The base and the raid town use these four (plus a few of the original greens). Screenshots: base_trees_blender.png, raid_trees_blender.png (compare base_overview_v2.png).

## Backpack and kids (branch experiment/prison-pack)
The raid and the base now use the One House backpack. It is the real thing: the town's `sim.inv` rules (scripts/town/inv.gd) and the real `InvUi` windows (backpack with Ruth's outline, the shotgun and swing slots, belt keys 1 to 4, loot window, stash window). Nothing was copied. The glue is scripts/prison/prison_pack.gd: it acts as the "main" the windows expect (screen maths, a bare real Hud control for the window helpers), keeps the grid and the belt between sims (the prison builds a new sim for the base and for every raid), and subclasses `inv.gd` only to put the stash at the stores. Keys: I or Tab backpack, 1 to 4 belt, Space take all, R turns a dragged item, Esc closes; no clash with the prison's own keys (E, R reload, F, M, wheel); the gun does not fire while the pointer is over a window.

Raid: E-search opens the loot window of the container (the town's rule, stacks are found one by one); Take all or drag moves items to the grid. What does not fit stays in the container and a "Pack full" line is shown. Rounds come from the shells in the grid. Going out with an empty pack hands you the standard kit (40 rounds, 1 med, 1 food, 1 water) and the belt is filled from what you carry. Extract: every item that stands for a resource goes back into the stock by the item data's own units (shells to ammo, cans and rations to food, bottles and jugs to water, bandages and medkits to meds), then the stock is banked and the "Banked" line lists it. Die: grid and belt are emptied.

Base: E at the stores (within 2.8 tiles) opens the stash window beside the backpack: the five store counts with withdraw 1, 5 or All, and Deposit all. The base sim now shares the `stores` dictionary itself, so it stays the source of truth for the crew. The player picks the loadout there before taking the truck.

Kids: Kit and Pip carried a rifle because PawnNode draws a weapon for every non-dead person. PawnNode got an `unarmed` flag (the gun is not drawn) set by the game for crew with `kid`. They no longer walk a route: scripts/prison/prison_kids.gd runs them (called from `prison_crew.gd update`, 3 small edits) through tag, a ball game (kicking the ball to each other, drawn and rolling in the yard) and hopscotch (chalk court, numbers float up), 16 s each.

Checked: stash screenshot at the stores, raid screenshot with grid and belt, search with loot window, banking (stores ammo 80 to 40 on going out, to 82 after extract with food and water returned), die (pack stacks 0, nothing banked), kids screenshots of tag, ball and hopscotch with no rifle. `--pack=open|stash|search|search-full` stages screenshots. Not checked by hand: mouse drag and the stash click buttons, the "Pack full" line (the staged full pack merged the shells), items left in the pack across a base visit.
