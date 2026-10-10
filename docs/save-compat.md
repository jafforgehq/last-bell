# Save compatibility

A save does not hold the town. A One House save holds the town's **seed** (and size) and the state of the run; on a load the town is made again from the seed
(`TownBoot.plan_of` -> `TownGen.make`), and the saved base house, dead, survivors, cars and fence sections are put back into it **by id**. So a save only means
something in the town it was made in. If the generator or the building plans change, the same seed makes a different town and an old save would load into the wrong
houses (the base house, the dead in it and the survivors would not match).

## The rule

`TownGen.VERSION` (scripts/town/town_gen.gd) is the version of the **town**: the generator, the building plans, the props, the placement of the dead and the rescues,
and the meaning of what a save holds. **Any change that alters the generated town for a seed, or the meaning of the saved state, must bump it.** Examples that need a
bump: a building plan added, removed or edited; the layout, the fields, the districts or the streets changed; the rescue rings, the arrival or the loot data changed; a
saved variable renamed or given another meaning. Changes that leave every seed's town and every saved value as they were (UI, sound, balance numbers that are read
at run time and not saved as ids) do not.

Do not bump it for a change made and shipped in the same unreleased build more than once: one bump per release is enough (the saves of the last release are the ones
that exist). But when in doubt, bump: a refused save costs a player a game, a wrong load costs a broken one.

## What is written and checked

* `OneHouse.save()` writes `town_version` (= `TownGen.VERSION`) into the `scenario` module of every One House save (`modules.scenario.town_version`).
* `SaveGame.town_compat(data)` says whether a save is of another town: `""` (fine, or not a One House save: the school's and the demo's saves hold no town), `"older"`
  (no `town_version`, as in every save made by builds up to main 236bb1e, or a lower one) or `"newer"` (a higher one: a save from a later build).
* `SaveGame.peek` answers `ok: false, incompatible: true, reason: "Older version" | "Newer version"` for those (and for a save of another `SaveGame.VERSION`, the
  format). `SaveGame._top_ok`, which `apply` and `is_loadable` use, refuses them too, and `apply` checks it before it puts anything of the town in place, so a refused
  save never leaves a half-loaded game.

## What the player sees

* **Continue** (and the game over card's **Load last save**) skip incompatible saves and use the newest one that can be continued; with none, Continue is greyed and says
  "Older saves cannot be continued".
* The **Load** page lists an incompatible save greyed: "older version: cannot be continued". Clicking it, F9 on an incompatible quick save, and `--load=path` show the card
  (scripts/ui/old_save_card.gd): "This save is from an older version of Last Bell and cannot be continued. Start a new game." with **Close** and **New game**. The game
  that is running stays where it is (F9 holds it as the pause menu does); at the start of the program the title stays up under the card.
* A `--load=` file that is refused for any reason (older, newer, damaged, missing) never starts a game: the title comes up with the card. (Before SAVE4 a damaged file
  started the school-yard game.)

## When you bump it

1. Raise `TownGen.VERSION` and add a line to the history above its constant.
2. Nothing else: the saves of the older number are refused by the checks above.
3. If the *format* of the state changes without the town changing, bump `SaveGame.VERSION` instead (it is refused the same way, with the same card).

Not a bump (INV2, 2026-10-10): the quick slots on Ruth's belt are saved as `modules.inv.quick` (four item ids). It is an optional key with a safe default: a save made before it loads with an empty belt, a bad entry is dropped, and nothing that an existing saved value means changed, so version 3 stays the version.

Not a bump (PH10, 2026-10-10): Ruth's needs add the optional `modules.inv.needs` ({owed, told, went}); a save made before loads with nothing owed and nothing told (so the one toast of the first hunger may come once more), a bad entry is dropped, and her hunger and thirst clocks were always saved with the person. The stores serving her only at the base is a rule, not a saved meaning. The water bottle became one cell: a saved pack with bottles loads (a placement is x, y, rot, count, and the grid is read again by the data's sizes: `Inventory.from_dict` cleans what no longer fits), so version 3 stays the version.

History: 1 = up to main 236bb1e (no number written). 2 = SAVE4 (the town of CLEAR3's clear ground and a town for every seed, WORLD3's 164 building plans). 3 = INV-CORE (2026-10-09, the
backpack): the generated towns are the same, but the *meaning* of the saved state changed, which is what a bump is for. A One House save now carries an `inv` module (the backpack grid, the
grids of the containers she opened with the items left in them, the piles on the ground, the credit of the fractions paid ahead); the avatar's reserve ammo, her bandages and her meals come from
that pack and no longer from `stock`, so `stock` of a version 2 save holds food, rounds and medicine that are now in the pack; and a container's `looted` means *searched* (items she left in it
stay and are saved in the module). A version 2 save loaded into this build would play with an empty pack and double-counted stores: it is refused with the usual card.
