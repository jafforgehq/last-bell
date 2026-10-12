# Prison playtest log (branch experiment/prison-extraction, merged build)

Drivers added to prison_game.gd (debug only): `--auto=play` (a bot for the clear phase: shoots the nearest dead in sight, walks to the next dead by the path finder, searches containers within 12 tiles, revives a downed ally; add `--botlog`), `--auto=reach` (path finder from the start to every container and dead record), `--auto=loop --managed [--loops=N --loopdie=0,1 --raidsecs=S --seed=N]` (base, raid, loot, extract or die, prints SNAP lines to catch state leaks), `--hour0=H` (a start hour that keeps running; `--hour` freezes the clock), `--perf` (wall ms per frame over 1200 frames). Run: `Godot --path . --fixed-fps 60 --disable-vsync -- --prison ...`.

## Stage 1, clear phase: pass, with fixes
Cold `--prison`: intro card "THE OLD PRISON", party of four outside the west breach, walks in (screenshot). Reach check: all 30 containers and all 99 zone dead have a path from the start (the 72 pen dead are outside the fence, by design). The bot cleared 10/10 zones in 255 s of game time (4.3 minutes, the bot is a good shot and never idle, so a human will be slower), all three allies survived, no STUCK once the bot's own steering bug was fixed. Zone crews were freed in order, HUD counter and minimap updated, loot reached the stores (meds 3 to 6.5, scrap).
- Bug: Ruth could not reload. With the pack wired in, her rounds are the pack's (`inv.active()`), the clear phase gave her only the 6 loaded shots while the 60 rounds sat in the stores. Fix: first entry takes the standard kit from the stores (`pack.kit`: 40 rounds, 1 med, food, water; stores ammo 60 to 20). Balance of that split is an owner call.
- Bug: kids freed in the clear phase and in the base carried a rifle: the game read `def.kid` but the def key is `unarmed`. Fixed in both spawn paths.
- Note: food fell from 10 to 1 during the clear (crew meals as people are freed) and the guards' pen shooting ate ammo down to 0 at the end of the first full day (see stage 5).

## Stage 2, PRISON SECURED: pass
Card, rebuild in the managed layout, 17 members (14 crew + 3 allies), gate prompt "E: take the truck out", no locked-gate prompt, breach sealed (minimap and screenshots), day clock running. Allies stay in the base with "ready" tags and health bars (they follow Ruth and shoot): see owner decisions.

## Stage 3, backpack: partly verified
Windows (backpack, belt, loot window, "Take all", stash window with 1/5/All and Deposit all) render at the stores and in raids (screenshots p1, loop). Bot looted real containers; take-all moved items to the grid. Stale text: the raid-start message ended with a baked "Pack 5/32 cells ..." that never updated. Fixed (the HUD line is live). The belt kept ids after banking (items gone to the stores): cleared in `bank()`. NOT exercised: the "Pack full" line (the staged full pack hit an empty car; the 32/32 fill itself works), mouse drag, stash button clicks, gun-over-window.

## Stage 4, raid loop: pass
Two to three raids in a row (extract, die, extract): stores banked (`Banked: +1 food +3 water +40 ammo +1 meds`), die loses the pack ("Backpack lost (5 stacks)"), belt and grid empty in the base, siege object, phase, crew count (17), allies and tod all carried over without a leak. A night that falls while she is out starts the attack the moment she is back (00:30, ammo 0.8): harsh, owner call.
- Bug: `siege` was only made in `_enter_base`, so a `--raid` start crashed every frame (`update` on Nil). Siege is now made in `_ready`.

## Stage 5, siege: pass, one bug fixed
Natural night with guards and an idle player (`--hour0=20`): night 1 at 21:00, 8/8 dead killed, no fence lost, 28 to 32 rounds used, the morning card at dawn (natural dawn end exercised, screenshot s1), night 2 started on the second evening (12 sent, 12/12 killed in a forced run, 17 rounds). Without guards (`--noguards`, night 3): two fences lost, Rae and Tomas (or Kit and Pip) lost, only 13 of 32 killed.
- Bug: a bitten ally or kid has no `route`, the siege put it in state "down" and `crew.update` threw `Invalid access to property 'route'` every frame. Fixed (those keep their state, "down" members are skipped), and an ally lost to a bite now leaves `allies_alive` (it came back at the next base build).

## Stage 6, kids and towers: pass after the kid fix
Kids unarmed and playing tag with the ball in both phases (screenshot t3). Towers show Walt, Sol and the empty decks; night glow from the tower lamps and fires (t1).

## Stage 7, perf: pass
Managed base, 66 awake dead, 17 crew: avg 8.7 ms, p95 10.2, max 14.4. With a night-3 wave (105 awake): avg 9.9, p95 11.8, max 17.2 (a second Godot was running at the time).

## Open
Owner decisions and human checks are in the final report.

## Round 5 checks (HUD, tower poses, allies after the clear, cleaning)
- HUD: screenshots with `--aimdir` in the clear phase (line, crosshair, "Pump shotgun 6 / 117") and in the managed base (readout, line); `--reloadat=N` staged reload shows the ring and "RELOADING". In the managed base boot without a kit the pack is empty so it reads "6 / 0": correct, the shells are in the pack. NOT checked: a raid screenshot (same code path), colour-blind markers.
- Tower guards: shot log (`--shotlog=1`) shows a reload pause of about 100 frames after every 5th shot; screenshot shows Walt with the rifle aimed south, then the watch pose again. Weak: facing south the aimed rifle points at the camera and reads small.
- Allies: `--auto=clearall` reaches PHASE managed with 17 crew, no script errors; screenshot shows Cole "Gate watch", Bea "Yard patrol", Ike "Quartermaster" with no ready tag or bar. A raid loop (2 raids) ran with no errors. NOT checked: an ex-ally bitten in a siege.
- Cleaning: `--hour0=9.5 --cleannow=1 --log` prints the plans, Mia sweeps with the broom (screenshot), the log says "body being cleared by Mia" and the staged corpses fade (screenshot). Others (laundry, rubbish haul) were only seen in the plan log; the walk to the far yard takes about 40 s real time. Siege interruption is by code only (not run).
- Ammo split: stores ammo 20 in the clear phase; the short-stores message was not triggered in a run.
