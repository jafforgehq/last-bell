# Idea: a raid and extraction action game in the Last Bell world

Status: an idea only, saved on 2026-10-08 so we can come back to it. Nothing is designed in detail and nothing is built. The owner decided not to do any of it for now ("lets finish what we have"): Last Bell's demo comes first.

## Where it came from

A friend of the owner likes quick, shooter-heavy action and is not a fan of RimWorld-style management. He pointed at Zero Sievert (a top-down extraction shooter with survival). The question was whether Last Bell should have a different mode for players like him, or whether a separate game makes sense.

## What that kind of player wants (Zero Sievert in short)

- Short raids: go out with a gun, loot, fight, get out. The raid is the whole game; the hideout is a quick stop in between.
- Real stakes: ammo is scarce, a bad fight costs health and time, and dying can lose what you carried.
- Loot tension: what is in that building, can I carry it, is it worth the risk.
- Gun variety and upgrades: weapon types, ammo types, attachments, armour.
- Light survival pressure: bleeding, injuries, sometimes hunger or radiation, medical items.
- Not management: no job lists, no commanding a crew, no base micromanagement.

It is not bullet hell in the strict sense (no dense patterns), it is tactical top-down shooting with risk and reward.

## What Last Bell already has that this idea would reuse

- The top-down shooting feel: aiming, recoil, shotgun rack, melee swing (`scripts/sim/avatar.gd`, `scripts/sim/melee.gd`, `assets/data/melee.json`, `scripts/render/combat_fx.gd`, `scripts/render/pawn_motion.gd`).
- A generated town of 192 x 192 tiles with districts, many house shapes and rooms (`scripts/town/town_gen.gd` and friends), with dormant dead that wake near the player (`scripts/town/dormant_dead.gd`).
- Looting and searching: room search, loot shimmer, containers (`scripts/town/search.gd`, `room_search.gd`), salvage of furniture and wrecks (`scripts/town/salvage.gd`, `assets/data/salvage.json`).
- The mood: the dark look and day/night, rain, storms and lightning (`scripts/render/dark_look.gd`, `scripts/town/skies.gd`, `scripts/render/rain_view.gd`), the sound set (`docs/audio-mix.md`), the map and minimap, the HUD kit.
- Survivors and a base as a hideout (the house claim, the Build page, the crew), which could be reduced to a simple hub.

## What is missing for a raid game

- Loot depth: an inventory with limited space, item rarity and weights, weapon and ammo types, armour, attachments, medical items.
- Health model: bleeding, injuries, healing items, perhaps hunger or fatigue.
- The raid rules: a start, an exit (extraction) and the risk of losing the carried loot on death.
- Enemy variety with ranged threats and patterns (spitters, bloaters, hurlers) for the bullet-hell flavour.
- Progression between raids: a hideout with upgrades, traders or a stash, unlocks.
- Balance for a faster pace, and a pass on the UI for loot and inventory (this is the largest new UI).

## Three sizes of the idea

1. An "auto-manage" option in Last Bell (about 2 to 3 days). The crew assigns its own jobs and builds the base by itself. The player only fights, loots and rescues. It also answers the early complaint that commanding is complex.
2. A raid mode in Last Bell (about 2 to 3 weeks). A new-game choice: start at the base, pick a district, loot and fight, return before the dusk bell with what you carry. Death loses the loot. The base grows from what you bring back. This is the Zero Sievert-like loop on our world and shooting.
3. A separate action game (months): new design, new content and its own identity.

## What to find out first

- Have the friend play the current Last Bell build and watch what he does and what he misses: the loot tension, the extraction, faster action, weapon variety, or just less management.
- Ask which of the Zero Sievert features he would give up first. That picks the smallest version worth building.

## Risks

- A second mode doubles the balancing and the testing, and blurs what Last Bell is on its store page.
- Loot and inventory are a lot of UI and data work before the raid even feels good.
- The raid loop competes with Last Bell's own pacing: keep the demo's identity clear until it has real feedback.

## When to look at this again

After the Last Bell demo has had outside players and the feedback is in. Then decide: the cheap auto-manage option first, a raid mode second, a separate game last.
