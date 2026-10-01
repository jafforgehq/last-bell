# Appendix B: gameplay and systems review

> A read-only design review of the rules, data and HUD. Items marked [?] were reasoned from code, not run; the school-keep exploit it flags was then tested (see the main audit, section 2). Part of [the full audit](2026-10-01-full-audit.md), 2026-10-01, repo HEAD e4fa379.

[V] read in code/data; [C] my arithmetic from the data files; [?] reasoned, not run (Godot was not run).

## 1. What the player actually does

Five decision types, about 10 meaningful inputs per game-day (~300 a run, one per ~50 s):
- **Scavenge (G), daily:** up to 2 people, 1 of 3 sites, only 06:30-10:00 (60-70 s), one trip a day. `scavenge.gd send()` pre-rolls everything; nothing is decided again until 16:00 [V].
- **Repair (F), daily, 0-6 orders:** manual, one wall at a time [V]; flat 9 HP/s, 1 scrap per 10 HP. Building only picks who walks over (`main.gd _pick_repairer`), not speed [V].
- **Re-post (right-click, R, P), nightly, 0-4:** one person at a time; no multi-select [V].
- **Treat (T) / Send out (X), rare:** bites come only from walkers already inside, or trips [V].
- Speed, pause, camera, alert clicks.

Automatic: targeting, firing, reload; meals; bandaging, stabilising, bed rest (spends meds); posts at the bell; all walkers leaving at dawn; garden, barrels; autosave. Daytime "jobs" are decorative standing spots; nobody fires by day unless drafted [V]. Skills never grow, Melee is unused, Leading only gives x1.15 loot at 5+ [V].

## 2. Fun, flat, broken

Fun now: lighting and sound, alert micro-stories, the infection dilemma, the 3-hour rescue scramble, night breaches.
- **Pacing:** daytime is 52% of each 8-minute day with 1-3 inputs, no threat, no work; nights are mostly watching auto-fire; every day repeats the same inputs with bigger numbers.
- **Ammo binds nothing.** `sim.gd _fire` subtracts from `stock.ammo`, but nothing checks it; at 0 everyone keeps shooting [V]. Hardware ammo is worthless and a round-3 ammo workshop would be pointless. If gated: ~0.4 (Marcus) to ~2 (Ana) ammo per kill, ~2,200 walkers, dry around day 12-14 [C].
- **The real constraints are wall HP and meds.** Walls total 3,570 HP; a clawing walker does 1.2 HP/s; scrap income ~4.5/day = 45 HP [C]. Auto-bandage spends 1 med per scratch against ~1.7 meds/day income [C]. A depletion clock, no sinks or growth (day-30 base = day-1 base). Death spiral: lose Ana (the only Medicine above 2) and the rest follows.
- **Scavenging is a chore.** ~1% loss, 11-21% wound, odds hidden. A 3-day re-raid (x0.75) pays the same per day as waiting 4 (x1.0); food income ~6.25 vs 6 eaten [C]. "Whichever site is open" is dominant.
- **Information gaps:** no forecast, no coverage view. At default night posts 15 of 100 attack slots (E second bus 7, E chain-link 5, W pallets 3) are in range of nobody [C]: the first breach is predictable and invisible. Most alerts last 4-14 s, five shown. Treat hides cure odds (Ana 90%, others 55-65%).
- **Exploits:** (a) ignore ammo. (b) *School keep* [?]: the dead cannot enter the school, and `pathfinder.nearest_free` gives up beyond 5 tiles, so for 174 floor tiles (x 25-58, y 49-54: gym, bunks, infirmary, kitchen) `find()` returns [] and a breached walker whose nearest person is there just stands. If it holds, standing there at the bell wins with no walls, scrap or ammo. Test first. (c) Deck turtling is just the default: posts already sit on walkways and towers; ladders (e4fa379) matter only after a breach; nothing grants cover.
- **Harness blind spot:** `tools/balance.gd` never repositions anyone, so "median day 17" rates a naive crew.

## 3. First 10 minutes

07:00 day 1: six people on decorative posts, four wanderers outside, a hint bar; no objective, start screen or difficulty choice (CLI only; the web build is always Standard) [V]. Four real minutes of nothing; the Scavenge button vanishes at 10:00 unexplained; the 19:00 bell is the first life. Night 1 (30 walkers) should be easy and teach nothing [?]; "Repair the wall" at dawn is the only instruction.

Cannot know: repairs are manual and cost scrap; the 10:00 cut-off; dawn retreat; the ramp (30 to 117 a night); the weak wall; Ana as lifeline. Quit points: minutes 2-4; after night 1; the first unexplained east-flank breach (day 3-8); the repair chore.

## 4. Missing or thin versus the genre

- **Crew:** fixed skills; no traits, mood, rest, relationships, barks. Unused hook: the 16-year-old lookout is Marcus *Bell*; Ruth is the principal.
- **Base:** 14 fixed sections; no placement, funnels, traps, gates; rooms, workbench, generator are props. No crafting, no sinks.
- **Threats:** walkers only (runner/brute are round 2; no screamers or raiders); noise is only gunfire waking wanderers within 30 tiles; rain is cosmetic; no fire or blackout (generator and lamps exist).
- **Storyteller:** `waves.gd` is a +10% a night ramp: no events, no valleys.
- **Goal/replay:** "Day N of 30" is a counter; no code sets victory [V]. Seeds exist; one map, fixed crew. **Risk/reward:** only scavenging and exile.

## 5. Top 15, ranked by impact / effort
P personality, S story, D defence, C city, R replay, B bell/school.

1. **Real ammo + fire discipline** (S) [D]. Gate `_fire` and reload on `stock.ammo`; dry guns fall back to melee (Melee finally counts). Per-person policy: free / wall-only / hold; panel shows nights of ammo. `sim.gd _fire/_combat`, `hud.gd`. Risk: dry-gun spiral; retune with the harness.
2. **Standing orders + Building speed** (S). Auto-repair below 70% while scrap is 5+ (on for Dez, Hector); auto-treat. Repair HP/s = 5 + Building (Dez 14, Marcus 6). `sim.gd _goal_for`, `hud.gd`. Risk: too hands-off.
3. **Lures** (S) [D]. The two wrecked cars in the wall get "Alarm" (3 scrap, 3 game-hours): slot score -15 within 12 tiles, ~70% of arrivals go there, +15% wanderers. You choose the sacrificed wall. `sim.gd _assign_slot`. Risk: trivial if cheap.
4. **Fields-of-fire overlay + forecast** (S/M) [D]. V tints sections by shooters in range (red 0, amber 1, green 2+) and shows range rings; at 17:00 Marcus forecasts "~57 tonight, mostly north-east" (+/-15%; `waves.gd` weights 2 of 10 spawns 60/40); dead Marcus, no forecast. `overlay_node.gd`, `waves.gd`, `hud.gd`. Risk: solves the puzzle; keep it fuzzy.
5. **Dawn assembly + toll** (S/M) [S,B]. At 06:30 a card from counters: kills per person (MVP), wall HP lost, bandages, incidents; the bell tolls once per person lost. `sim.gd` counters, new `ui/report.gd`, `sound.gd` (`bell_0.wav`). Risk: overload.
6. **Skills grow + study hall** (S/M) [P,B]. Shooting +1/60 kills, Medicine +1/6 treatments, Building +1/300 HP, cap start+3. At the classroom desks a teacher (6+) trains a student (3+ below) at x3: Ana teaches Marcus Medicine. Copy `def.skills` per Person (shared data); `save_game.gd`, `hud.gd`. Risk: slow.
7. **Storyteller deck** (M) [S,R]. `events.gd` + `events.json`: one card a day at a 12:00 radio hour (Ruth's job made real); hidden tension 0-100 picks boon or threat. Cards: supply drop, storm, fog, full moon, blackout (generator dies at 22:00, lamps off, Dez restarts it), sickness. `waves.gd`, `lighting.gd`, dialog like `scavenge_dialog.gd`. Risk: content volume.
8. **Traits + barks** (M) [P]. Two each in `map.json`: Ruth Steady (+10% hit within 8 tiles), Dez Tinkerer (+30% repair), Ana Triage (bandage 30% faster), Marcus Jumpy (freezes 10 s near 6+ walkers; +20% far), Walt Steady Hands (reload -25%), Hector Stubborn; six barks each. `sim.gd perf/_fire`. Risk: text, balance.
9. **Last-Bell Knock** (M) [S,B]. 17:30-18:55 a survivor runs at the gate, 2-4 walkers 30 s behind: open (15 s; each chaser 50% slips in), cover from the walkway, or leave them. The 19:00 bell shuts the gate. Reward 6 meds or a lead; 40% bitten. `waves.gd`, `scavenge.gd gate_center`, `events.gd`. Risk: v1 a visitor, not crew (HUD cards are fixed).
10. **Bonds, grief, exile costs** (M) [P]. `map.json` bonds (Ruth-Marcus, Walt-Marcus, Dez-Hector, Ana-Ruth): +8% hit within 6 tiles; a friend down, dead or turned = 6 game-hours at -15%; X warns "Marcus may follow" (50%). `medical.gd kill/_turn/_exile`. Risk: punitive; warn first.
11. **Scavenging in beats + scouting** (M) [C]. Beats at 08:30, 11:00, 14:00 may pose a two-way card (force the stockroom: +50% loot, 5 walkers follow). Marcus scouts one site a morning. `scavenge.gd`, `sites.json`, dialog. Risk: UI.
12. **Workshop** (M). Gym bench (23.4, 49.8): 4 scrap to 12 ammo an hour; daily walls-or-bullets choice. `supplies.gd`, `sim.gd _goal_for`. Risk: needs #1.
13. **Wall sockets** (M/L) [D]. Two a section: sandbag step (6 scrap: no scratches, +10% hit), spike strip (5: 0.5 dmg/s), burning barrel (4 + fuel: 3 dmg/s; the fire barrels exist), floodlight. `sim.gd _claw`, `map.json`, `world.gd`. Risk: art, UI.
14. **Class of...: crew draft + Yearbook + daily seed** (M) [R,B]. Roll call picks 6 of 12 (coach, lunch lady, shop teacher...), 2 traits each; epitaphs (#5) go on the classroom chalkboard (49.5, 49.1); date-based `run_seed`. `scenario.gd`, start screen. Risk: baked portraits.
15. **Town board** (L) [C,R]. 8-10 sites on a drawn card, 1-3 h each way, 6 drawn per seed; specials (hospital, gas station); fuel for bus runs that may return after the bell. `scavenge.gd`, `sites.json`, `supplies.gd`. Risk: art x7, scope.

## 6. Roadmap, next three rounds

- **Round 2, the night as a puzzle:** 1-4, runner/brute (lures as counter), Big Night and the missing victory trigger, a school-keep decision, a harness policy that repositions. *Proves:* information and positioning change outcomes (informed bot beats naive by 3+ days; testers say why they lost).
- **Round 3, days and people matter:** 5-12 plus tutorial. *Proves:* three retellable moments a run, no dead time (5+ meaningful inputs a day; testers recall names).
- **Round 4, demo and replay:** itch demo = days 1-7 plus a scaled Big Night, start screen with difficulty, #14, 60-walker web performance, rights audit. *Proves:* the hook (40%+ reach night 3, median session 40+ min, wishlists). Later: 13, 15, a school fall-back.
