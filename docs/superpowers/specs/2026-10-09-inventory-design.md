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
