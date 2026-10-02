# Roadmap after round 6

> The user's direction (2026-10-02): the game grows from a small crew into a settlement, on a much bigger map, with a world to explore and seasons. They asked for **both** a bigger world to explore and a bigger base to defend, and for **seasons** and the **Town Board** (the "city map" kept for a later round since round 4). The itch demo and the Steam page still wait ("not in a rush"); a human playtest checkpoint is advised after round 7. Each round gets its own plan in `docs/superpowers/plans/` and is built the way rounds 5 and 6 were (core and plan first, builders on disjoint files, an independent review, the harness for balance).

Done: rounds 0 to 5 (supplies, wounds, the night puzzle, the shell and workshop, people and the storyteller, jobs and stations), round 6 (buildings on fixed plots, built by the Builders: seven buildings, the Build screen on N).

## Round 7: a small start, and recruits over the radio

The crew starts at **three** people. The others join over the radio: calls with a request (a person at a gate, a person trapped somewhere), rescued or let in, each with a short choice (is the stranger bitten? quarantine or the gate). The compound's **housing** (the school's six beds plus the bunk houses) is the cap. The six authored survivors become the first recruits in story order, later ones are generated (portraits through the existing portrait pipeline, traits, bonds). The size of the nights scales with the crew so that three people are not asked to hold a night built for six. The radio mast's range decides how far the calls reach. *Why first:* it is small, it changes the foundation of the balance, and it is where a human playtest tells the most.

## Round 8: the Town Board (a bigger world)

A large **town map** pinned on the noticeboard: named places (houses, pharmacy, hardware store, scrapyard, church, farm, clinic, police station, radio shop...) on streets, hidden until **scouted** (fog of war). Parties **travel** by distance and danger, with events on the way (expeditions in beats); a cleared place can become an **outpost** (a staffed, supplied, defended site that gives food, scrap, medicine or a recruit stream); the dead come from **nests** on the board, so clearing the north-west reduces the hordes from there and changes the night plans. Radio calls name places (survivors to rescue, traders, a cache), so rescues are where recruits come from. It replaces the scavenging dialog. *Art:* one illustrated map and pins in the noticeboard style (Meshy, a few pictures), no tactical art.

## Round 9: growing the walls (a bigger base)

The defended compound grows by **claiming adjacent lots** (the street, the shop row, the sports field), cleared through the board and then walled in: each lot adds plots to build on, wall sections to build and hold, posts, and new directions the dead come from. The map grows in stages to about three times its area, built from the existing tiles and props plus a few generated pieces; the dead's pathing may need the cost-map generalisation (spec section 6.2). *Why after the board:* lots are claimed through expeditions.

## Round 10: seasons and the long campaign

Four **seasons** with their own rules: the length of day and night, the weather, how well the garden grows, the cold (heating, clothes, a winter illness), how hard travel is, the harvest on the board. The 30-night game stays as the Autumn scenario; a **campaign** of three or four seasons with a Big Night at the end of each is the long game. Tints and sound for each season. *Why last:* it modifies everything before it (outposts, trips, walls), and the longer campaign needs the balance of the earlier rounds settled.

## Ideas kept in reserve (any of them fits between rounds)

Blueprints and research found on expeditions that unlock buildings and upgrades; people as events (traders, refugees, raiders at the gate); power and fuel (the generator, the floodlights, the radio); defence variety (traps, noise lures, a screamer that calls a horde); the convoy ending where only some can leave; a dog; music.

## Order and checkpoints

6 (buildings, in final checks) then 7 then **a playtest with a few people** (the restricted itch page) then 8, 9, 10. Rounds 9 and 10 can swap if seasons turn out cheaper than the territory work. Before a paid release: the rights audit of every asset and a formal trademark search of the name (see the audit's appendices).
