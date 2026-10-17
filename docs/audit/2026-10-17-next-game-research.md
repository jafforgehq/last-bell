# What to make next: market research and reuse audit (2026-10-17)

The question: with a similar pattern, assets and look as Last Bell (2D top-down, RimWorld-style flat art with dark outlines, code-drawn and PIL sprites, base management plus raids plus night sieges), what other game has the best commercial chance on Steam, with space as the owner's first idea?

Three research passes were run: Steam market data for space sub-genres, Steam market data for other genres, and a read-only audit of what the Last Bell code can carry over. Every sales figure below is a third-party estimate unless it was announced by the developer, and trackers disagree with each other by up to three or four times. The revenue ranges are judgment calls anchored on the comparables, not data.

## The base rates

- About 19,000 games came out on Steam in 2025; nearly half have fewer than 10 reviews. The median release grosses a few hundred dollars; most games make under $10k, and roughly 1 in 10 makes over $100k.
- Net to the developer is roughly a third to a half of gross (Valve's cut, refunds, regional prices, tax).
- Wishlists convert worse than they used to: a median first-week conversion of about 0.10 to 0.15 for 2024 to 2025 launches. Aim for 10k to 20k wishlists at launch; a Next Fest demo is the main lever.
- Breakouts in 2025 to 2026 mostly spread through streamers, and almost all had one simple hook visible in the capsule art.

## Space sub-genres

| Sub-genre | Comparables (sales) | Verdict for us |
| --- | --- | --- |
| Ship or station colony sim | Space Haven 700k+ (10 years, 3 people), Stardeus 46k to 92k est., Starmancer about $250k, RimWorld Odyssey covers it | Saturated; winners took 4 to 10 years. Avoid. |
| Crew combat and boarding (FTL-like) | FTL about 1.7M, Cosmoteer about 300k in 3 months (solo), Void War 98k to 196k, The Last Starship 50k | Healthy niche with steady mid-size hits; harsh expert audience. |
| Derelict salvage and extraction | Duskers about 192k ($2.5M), Void Bastards about 250k, Barotrauma about 2.9M (co-op), Lethal Company about 10M (co-op) | Single-player 2D is thin and open. Co-op is crowded and needs netcode. |
| Station or tower defence | Pure space TD releases have 0 to 11 reviews; Mindustry and Dome Keeper (500k+) sell as hybrids | Only as a hybrid. |
| Planet survival | Planetbase about 570k, Stranded: Alien Dawn about 221k, ONI about 2M | Mostly 3D and mid-size studios; reads as a zombie reskin. |
| Space trader or trucker | Starcom: Unknown Space 134k to 267k, Star Trucker about 111k | Uses little of our code. |
| 2D derelict horror | No 2025 to 2026 hit found; Duskers is still the reference | Open, but horror needs strong audio and lighting. |

## Other genres

| Genre | Comparables | Verdict |
| --- | --- | --- |
| Zombie survival (current niche) | Project Zomboid 15M+, Quarantine Zone 750k (2026), Infection Free Zone about 800k, Dead Estate 300k, Into the Dead: Our Darkest Days about 250k to 500k | One of the strongest niches on Steam right now. Hits come from a clear twist. |
| Single-player extraction | Zero Sievert 600k+ (solo, 2D top-down), Escape from Duckov 2M in two weeks (2025) | Hot, proven solo, closest to our systems; Duckov now owns the top-down look. |
| Medieval siege colony | Thronefall 1M+, Against the Storm 2M+, Going Medieval 1M, Cataclismo 250k+ | Proven but crowded and publisher-led. |
| Roguelite base defence | Dome Keeper 1M, Kingdom Two Crowns about 800k, They Are Billions about 1.1M est. | Strong and short to build. |
| Post-apocalyptic shelter | This War of Mine 7M+ | Old genre without a fresh angle. |
| Prison management, wild west, underwater or arctic base, cozy | Prison Architect owned by Paradox; no wild west demand data; Surviving the Abyss about 100k | Not recommended. |

## What our code can carry over

About 22 percent of the 182k script lines is engine that carries over directly (pathfinding, lighting and night grade, pawn renderer, audio runtime, inventory grid, save, playlog, menus and settings, test harness), and about 11 percent more can be reskinned (economy and Base screen, events and story arc, siege segments, noise, squad orders, loot tables, destination map). About 72 percent is old town, school and One House code that the prison game still reaches through hard-coded preloads. Before a second game, about 3 to 4 weeks should go to pulling out a shared `core/` folder: a palette module out of the 6,088-line `hud.gd`, one inventory, one save, a small map interface instead of the fake town generator, an InputMap with desktop export presets, and the legacy code moved out.

Fit per setting (solo weeks after that clean-up, art counts are estimates):

| Setting | Carries over | New systems | Weeks |
| --- | --- | --- | --- |
| Derelict salvage extraction | Raid and extraction rings, pack grid, loot tables, destination map as a star map, squad orders, noise and wake, doors, meta, playlog | Oxygen or power timer, airlocks and hazards, a ship-layout generator | 10 to 14 |
| Boarding FTL-lite | Raid sites as enemy ship interiors, squad orders, loot, events deck | Ship-to-ship layer, run map, ship upgrades | 14 to 18 (estimate) |
| Frontier settlement | Town generator, raids, econ, events, sieges as bandit raids | Ranged human AI with cover | 14 to 20 |
| Arctic or underwater base | Econ, crew, events, expeditions, creature sieges, snow and dark lighting | Temperature or pressure, exposure | 14 to 18 |
| Medieval siege colony | Siege segments, towers, barricades, posts, econ, crew, events | Bows, siege engines, foraging | 16 to 22 |
| Space station colony | Crew jobs, econ, events, breaches as sieges | Free building, room atmosphere and power grid, boarders | 18 to 26 |

## Recommendation

1. **Highest expected value: finish Last Bell and sell it on its strongest hook.** It sits in one of the strongest niches on Steam, it is most of the way there, and it already contains the extraction loop the market is buying ("Tarkov-style raids, a RimWorld-style base, zombie nights"). A second game started now would compete with it for the same months. Revenue range for a polished release at $15 to $18: low $15k, median $60k to $120k gross, with a long tail if streamers pick it up (Zero Sievert, Quarantine Zone).
2. **Best space game: single-player derelict salvage extraction.** You dock a home ship at procedural wrecks, take two or three named crew who can die for good, salvage against an oxygen and power timer, and leave before what is aboard wakes; between runs you upgrade the home ship and choose the next wreck on a star map. It is underserved in 2D single-player, it has the highest code reuse of any space idea (10 to 14 weeks after the core clean-up), and it does not compete with Space Haven or RimWorld Odyssey. Comparables: Duskers, Void Bastards, Zero Sievert. Range: low $5k, median $30k to $70k, high $400k. Risk: being read as a Lethal Company clone; it needs a clear single-player crew hook and strong audio.
3. **Higher ceiling, harder audience: a boarding-party FTL-lite**, where ship fights are won by boarding enemy interiors top-down with a pausable crew. Comparables: FTL, Cosmoteer, Void War. Range: low $10k, median $50k to $100k, high $1M. Risk: FTL players are expert and harsh, and it needs a whole ship-to-ship layer.
4. **Avoid:** a ship or station colony sim (saturated, long Early Access), pure space tower defence, a space trader, and co-op anything (netcode).

## How to decide with data, not guesses

Make a Steam page with a capsule image and a 30-second trailer for the top one or two ideas, run them for two to four weeks, and compare wishlist velocity before committing months of work. Do the shared-core clean-up first either way: it helps Last Bell's Steam build (desktop export, controller, rebinding) and every game after it.
