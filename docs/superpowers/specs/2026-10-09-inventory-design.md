# Inventory v1 (a light, Tarkov-style grid backpack)

Decided by the owner on 2026-10-09: inventory first, then food and water needs, then more zombies. This is the design for the first step. It is deliberately small: a backpack grid for Ruth, a loot window for containers, a deposit and withdraw panel at the base, ammo and bandages drawn from the pack. No attachments, armour, durability, weight, trading or loss on death (death ends the run anyway).

## Principles

- The colony's STORES stay as counts (food, water, ammo, meds, scrap): the crew, the builders and the scavengers keep working on them exactly as today. The inventory is how RUTH carries things out in the world.
- Carrying is the friction: finite grid space makes a scavenging trip a decision (what to take, when to go home), and the deposit trip is the payoff.
- Same units in, same units out: an item stands for store units (a box of shells = 6 rounds, a can = 1 food, a bottle = 1 water, a bandage = 1 meds), so the economy the lab was tuned on does not change by accident.
- Scrap from stripping furniture and cars stays immediate (it goes straight to the stores): it is the base's building currency, not a carried item.

## Items (assets/data/items.json, every number there)

Each item: id, name, size (w by h cells), stack (the most units per cell), res (the store resource it stands for: ammo, food, water, meds), units (store units per item), use (what using it does: eat, drink, bandage, none), a short description. Starting list:
- shells: 1x1, stack 24 rounds per cell, res ammo (a loose stack of rounds; a "box of shells" is an item of 6 or 12 rounds found in containers)
- canned_food: 1x1, stack 4, res food, units 1; ration_pack: 1x2, units 3
- water_bottle: 1x2, stack 1 per cell pair (units 1); water_jug: 2x2, units 4
- bandage: 1x1, stack 4, res meds, units 1; medkit: 2x1, units 3
Containers' loot tables (assets/data, the search module and the generator) produce these items instead of bare counts, with the same expected units per container and per house.

## The backpack and the equipment

- Backpack: 8 columns by 4 rows (32 cells), tunable in data. Items placed by cell, may be rotated (R while dragging) when w differs from h, stacks merge, a stack can be split.
- Equipment shown beside it: the weapon (the pump shotgun with its magazine count: reload takes shells from the pack) and the melee swing (no item). Nothing else to equip in v1.
- Ruth starts with a pack that holds what the start stock was (about 40 shells, a few cans, bottles and bandages): the 'start' stock in assets/data/one_house.json becomes her starting pack. Before the claim the top bar shows what she carries; after the claim it shows the base stores and the pack has its own chip.
- Her reserve ammo (the 'reserve' in `3 / 40`) is the shells in the pack. Reload moves rounds from the pack to the magazine. The crew's ammo is the stores' ammo as now.
- Bandaging herself uses a bandage from the pack first, then the stores' meds if she is at the base.

## The loot window

- Searching a container (E, the hold that exists: 2.5 s) opens the loot window beside the backpack. The container has its own small grid (a cupboard 4x3, a trunk 4x2, a car 4x2, a crate 3x3...). Its items are REVEALED one by one over the search time (about 0.4 s each) like Tarkov, not all at once.
- Take: drag an item to the pack, double-click for a quick move (to the first place it fits), Space or the Take all button moves everything that fits. Items that do not fit stay in the container (a searched container is marked looted only when its grid is empty or the player closes it: the 'looted' flag keeps meaning 'searched'; leftovers can be taken later: the shimmer returns while items remain).
- Closing: Esc, Tab, or walking away (more than 3 tiles) closes it. The game is NOT paused while a panel is open (like the radio panel), so a night attack keeps its tension; the panel never covers the avatar (reuse the coach card placement logic).
- Crew scavengers still work in abstract: they bring units straight to the stores as today.

## The base stash (deposit and withdraw)

- A stash point in every claimed house (an existing furniture object, a crate or locker; the base's 'stash' that the claim bonus fills). E at it opens the stash panel: the backpack on one side, the STORES on the other as five rows (ammo, food, water, meds, scrap) with the counts.
- Deposit: drag an item onto the stores panel, or the Deposit all button (everything stackable that stands for a resource). Withdraw: a row's buttons take N units out as items into the pack (1, 5, all that fits): ammo as shells, food as cans, and so on.
- When she walks into the base zone with a full pack, a toast offers 'Deposit (E at the stash)'. No auto deposit in v1.

## Keys and UI

- Tab (and I) toggles the inventory; mouse: drag and drop, right-click for a menu (use, split, drop), double-click quick move, R rotates the dragged item. Check the existing key table (scripts/ui/controls_table.gd, the single source) for conflicts and add the new rows (the legend and the Controls page read it).
- Drop: an item can be dropped on the ground (a pile) or put back in the container.
- Look: the game's own HUD kit (the dark green panels with brass edges, scripts/ui/hud.gd helpers), icons drawn in code in the game's style (simple outlined shapes: a can, a bottle, a box, a bandage), a clear highlight for where a dragged item fits (green) or not (red). Colour-blind markers: use shapes and a tick as well as green and red. Honour Reduce motion.
- Works at 1280x800, 1920x1080, 2560x1440 and 1024x640 (the window sizes the game supports).

## Rules and edge cases

- Saves: the backpack and the stash state are saved with the run; bump `TownGen.VERSION` (docs/save-compat.md) because the saved meaning changes (old saves are refused with the existing card).
- The lab bot uses the same sim API (add loot to the pack, deposit all when home, reload from the pack) so the lab keeps working and its numbers stay comparable; any change in the lab's held rates is reported and tuned in data, not hidden.
- No inventory in the school-yard modes (`--school`, the demo, the no-avatar sim): everything is gated to the town run (`sim.is_one_house()`), the golden tests stay unchanged.
- A full pack and an incoming item (a reward, a survivor's gift): the item goes to the ground at her feet with a toast.
- Performance: the UI is built once and updated on change; no per-frame rebuilds.

## Sim API (the contract between the logic and the window)

`scripts/sim/inventory.gd` (RefCounted, no nodes), data from `assets/data/items.json`:
- `Inventory.make_grid(w, h) -> Dictionary` and `grid.cells` placements `{item, x, y, rot, count}`.
- `can_place(grid, item, count, x, y, rot) -> bool`, `place(...)`, `remove(grid, index)`, `move(from_grid, index, to_grid, x, y, rot)`, `split(grid, index, count)`, `merge(...)`.
- `auto_add(grid, item, count) -> int` (units left over: stack first, then the first free place, rotating when needed), `quick_move(from, index, to) -> bool`, `take_all(from, to) -> int moved`.
- `units(grid, res) -> int`, `take_units(grid, res, n) -> int taken` (used by reload, eating, bandaging), `deposit_all(grid, stores) -> Dictionary`, `withdraw(stores, grid, res, n) -> int moved`.
- `to_dict()` and `from_dict()` for saves.
- The sim holds `sim.inv` (the backpack grid, the equipment, the stash panel state) and exposes it to the HUD and the bot.

## Build order

1. INV-CORE: items.json, the grid logic, the sim API, loot tables to items, the avatar's reload, bandage and start pack from the pack, the stash deposit and withdraw logic, saves, the bot, the lab; golden tests unchanged.
2. INV-UI: the inventory window, the loot window, the stash panel, icons, keys, tooltips, window sizes (coded against the API contract; the logic arrives from INV-CORE).
3. Integration and balance (the main agent): merge, the lab on seeds 1..64 (bot at least 56/64, idle 8 to 20), screenshots, a hand-play style probe of a whole loot-deposit cycle, the owner reviews screenshots before the next step.

Then step 2 of the owner's order: food and water needs (meters, eating from the pack and the stores, penalties), then more zombies.

## INV2 (2026-10-10): the windows, simplified, with better pictures and a doll (the logic above is unchanged)

The owner found the windows too large. What was done, in the owner's words "simplify, better assets, like Tarkov, a human shape on the right":

- **Compact.** The backpack window is the grid (8 by 4 cells of 34 points, 32 in a window under 1100 by 700) at the left and Ruth with her kit at the right, in the HUD's slim board, with one line (BACKPACK 19 / 32) over the grid and no help paragraph (the tips are tooltips and the Controls page). 452 by 186 points: **9.1 percent of the screen at 1280 x 720** (was 412 x 359, 16.0 percent). The loot window (the container's 4 by 3 grid, its name, how much is found, Take all) and the stash panel (five columns: the store's name and number and the buttons 1, 5, All; Deposit all in the head) are the same board, **put against the pack, under it or over it, never beside it**: the pair is at most 35 percent of the width and 44 of the height at 1280 x 720 (the budget is 45 and 55: `InvGeom.within_budget`, the placement `inv_ui.gd _best_against`).
- **The doll** (scripts/ui/inv_doll.gd): Ruth from the front (112 x 168 points), the pump shotgun in a slot at her hand (the rounds in the magazine and a Reload strip: a click is R), the swing in a slot at the other side (no item), and **four quick slots on her belt**. No slot for a head, a body or a back: there is nothing to put there, so no dead slots are drawn.
- **Quick slots.** A slot names a KIND of item ("bandage"), not a stack: the keys **1 2 3 4** (or a click on the slot) use the first stack of that kind in the pack through `sim.inv.use_item`; the slot is lit when the pack has it and dim when it has none (PH10: food and drink work now, see "Her needs" below; before that they were greyed with "needs: coming soon"). An item goes on a slot by dragging it from the pack (green and a tick; red and a cross for what has no use: shells), or by its menu ("Put on a quick slot"); a slot is cleared by its menu. A kind sits on one slot only. The belt starts with a bandage, a tin and a bottle (`begin`). Saved in `modules.inv.quick` (an optional key: a save without it loads with an empty belt; **no `TownGen.VERSION` bump**, nothing a saved value means changed). The only edit of the rules' files is the `quick` array of `scripts/town/inv.gd` (the variable, `start`, `begin`, `save`, `load_state`).
- **The keys 1 to 4.** The plain digits were the speeds in the One House (nobody is picked there). They are the belt's now and **the speeds are Shift and 1 2 3** (as in the school's avatar game, whose digits pick the crew): `main.gd _speed_key`, the toolbar's tooltips, the Controls table and the README say so. A card that answers the digits keeps them: the rescue card (1 2 3 answer, 4 to 9 are swallowed), the radio card and the pages (a full page has the keys), the wait button's question (1 to 4 swallowed), the morning card (the digit that puts it away is not a quick slot).
- **The pictures.** One PNG atlas (assets/ui/inv/inv_icons.png and its table inv_icons.json, 316 KB, 360 KB imported) made by tools/make_item_icons.py (PIL and numpy, 4 times supersampled): 128 px for each cell of an item's footprint, the game's flat look (a dark outline, one flat colour with a little wear, a pale top edge and a darker foot, a soft shadow): the shell (one, a few, a box's worth: by the stack's count), the tin, the ration pack, the bottle, the jug, the bandage roll, the medkit, the pump shotgun, the swing, the pack's badge, the quick slots' frames (empty, lit, off), a soft glow and Ruth. Drawn with mipmaps (`InvIcons.prepare`). The code-drawn pictures are gone.

## Her needs (PH10, 2026-10-10: step 2 of the owner's order, food and water; the logic is scripts/town/inv.gd and scripts/sim/supplies.gd, the board is scripts/ui/needs_board.gd)

Ruth is a person of the colony and already had the colony's hunger and thirst clocks (`p.hunger_h`, `p.thirst_h`: weaker from 18 and 14 game hours without a proper meal or drink, health lost from 36 and 24: scripts/sim/supplies.gd, constants unchanged). What was missing was any way for her to act on them: the stores fed her at 07:00, 13:00 and 19:00 wherever she stood. Now, in the One House run with a pack only (`sim.inv.active()`):

- **The base serves the people at the base.** At a meal hour the stores serve everyone who is on the map as ever, except Ruth when she is outside the base's compound: that meal is OWED (`inv.owed_meal`), and the moment she is inside the compound again the base serves ONE meal (not one for each she missed), a third of a ration and half a bottle as for the crew. At the table with empty stores the old fallback holds: her pack feeds her. (The choice: automatic, because that is how the crew eats and it needs no new key; E at the stash still withdraws food and drink into the pack, which is the way to go out with some.)
- **Out in the town she eats from her pack.** `use_item` on an item whose use is `eat` or `drink` (the belt's keys 1 to 4, right-click Use, a double click in the pack) takes ONE store unit: a tin, a bottle, or one unit of a ration pack or a jug, which is broken (the rest of its units go back as tins and bottles; nothing is wasted and nothing is credit). The clock starts again, as for a served meal. A unit is the item's own word (a tin is "one ration", a ration pack "three"): one unit holds the clock off for most of the 18 hours of hunger (a meal of the table is a third of a unit every 6 hours), so a day outside is one tin and one and a half bottles, and a day at the base costs the stores what it always did. She cannot eat before she is hungry enough (`items.json` `needs`: `eat_min_h` 6 and `drink_min_h` 5 hours since the last meal and drink): "You are not hungry yet", and the item is kept.
- **Telling her.** The first hungry and the first thirsty are one toast each (`inv_toast`, "Hungry: press 2 to eat (canned food)": the key is the belt slot that holds food she has; with none on the belt it says to open the pack; with none in the pack it says to search the kitchens or go home). What she went without since the last morning card is kept (`inv.went`) and the card says "You went hungry yesterday." (and thirsty, and when it cost health).
- **Day one is mild.** The run begins at 07:00 fed. With no food or water taken and never at the base, thirst begins at 21:00 on day 1 (14 hours), hunger at 01:00 on day 2, health is lost from 07:00 on day 2 (parched, one point of 100 an hour) and from 19:00 on day 2 (starving): nothing before the first dusk, nothing that kills before day 5. The pack at the start holds 8 tins, a jug and two bottles, and the belt has a tin on key 2 and a bottle on key 3.
- **The picture.** A water bottle is one cell (it was two tall; the jug stays 2 x 2 for four units, a ration pack 1 x 2 for three): `assets/ui/inv/inv_icons.png` is made again by `tools/make_item_icons.py` with the one-cell bottle (the other pictures are byte for byte as they were, but the atlas is packed again).
- **Saves.** The new state is the optional `modules.inv.needs` ({owed, told, went}); her clocks are the person's own variables, saved by reflection as before. No `TownGen.VERSION` bump: nothing a saved value meant has changed (docs/save-compat.md).
- **The lab's bot** keeps a tin and two bottles in the pack when it leaves the stash and eats when it is 12 hours since a meal and drinks at 10 (`tools/house_bot.gd`), so the lab stays comparable.
