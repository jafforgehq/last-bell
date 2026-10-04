extends "res://tests/case.gd"
## Round 20, the no-avatar promise (docs/superpowers/plans/2026-10-03-round-20.md, Risks 1): every hook the round adds
## (relations, specialists, initiative) is exactly neutral in a game that has no avatar, so such a game plays byte for
## byte as it did before the round. This file replays whole games and compares what they ended as, as strings, with what
## the same games ended as at the baseline, the code of commit f23eee3 (round 17's last, before the stubs of phase 0b).
##
## A digest (`digest`) is a game played for some game days at 15 Hz (30 Hz costs about half as much again and no hook cares; the
## whole file is about a minute of processor time: the plain games are the three game days of the plan, from 07:00 on day 1 to
## 07:00 on day 4, three nights; the busier ones two days, two nights, the others a day and a half or a day) and then read as a few sections of "key=value" tokens, floats as "%.4f": the
## clock, the stocks, the kills and the dead on the field, the walls, every person's place, health, mood, trust, work and
## deeds, the radio's log length and the random generator's state (`sim.rng.state`: one extra or missing draw anywhere
## moves it). `PINNED` holds the digests of the baseline; a game that no longer ends as it did fails with the first
## token that moved, which names the module to look at (a stock or a position: a bonus that is not neutral; the
## state: a draw; the trust: a hook of the radio).
##
## The games, from the plain to the busy:
##  - "plain": the colony alone (jobs by themselves, nobody gives an order), seeds 1 and 9, crews 6 and 5;
##  - "informed": the harness's informed policy plays it (trips, treatments, buildings, lots, the storyteller's cards),
##    seeds 1 (crew 5) and 9 (crew 6): the hooks of the scavenging trips, the medicine and the jobs are reached;
##  - "orientation": the classic Orientation Day (no avatar), the script on the game's clock;
##  - "avatar_off": the new modules are switched off (`enabled = false`, as Orientation Day does) in a small start that DOES have an
##    avatar and a bot that asks the crew things over the radio, answers its calls and meets some mishaps (somebody is downed,
##    the player dies and the next in line takes over, another dies): the hooks of the radio, of the trust, of the morale and
##    of the succession are reached with the modules off, and it must still be the baseline's game;
##  - "avatar_classic": the same with the modules left ON in a classic six start: they are not active there (`active()` needs a
##    small start too: "a classic six start has no ideas"), so that is the baseline's game as well;
##  - "avatar_orientation": the avatar's Orientation Day (Ruth the player; the three modules are switched off by the lesson).
##
## The digest is written to run in any tree: it names nothing of round 20 (a throwaway runner in a copy of the baseline
## prints the strings that are pinned below; `Object.get` finds the modules when there are any). To re-pin after a
## change that is meant to move the no-avatar game (a retune of the base game, tools/balance.gd's Policy), run the
## runner on the code before the change and paste what it prints. NEVER re-pin to make a failure go away: a failure
## here means a round 20 hook is not neutral.
##
## The `informed` digests play the harness's `Balance.Policy` (tools/balance.gd): a change to that class re-pins them.

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Helpers := preload("res://tests/helpers.gd")
const Orientation := preload("res://scripts/sim/orientation.gd")
const Balance := preload("res://tools/balance.gd")

## The rules' steps a second (one game hour is 20 seconds of rules time).
const HZ := 15.0
## The sections of a digest, in order, and what joins them and the tokens of one.
const SECTIONS := ["clock", "stock", "field", "walls", "people", "deeds", "radio", "rng"]
const JOIN := " | "
## Where to look when a section moved first (a failure message says it).
const HINTS := {
	"clock": "the day, the hour or the player moved: avatar._before (the succession), a module that ends or starts a day",
	"stock": "a stock moved first: traits.mult / traits.add (a specialist's bonus), scavenge.loot_scale, jobs._fit, a build or a trip",
	"field": "the dead moved first: sim.aim_factor through traits (marksman), a post or a wall order",
	"walls": "a wall moved first: traits.mult (engineer: repair, build.rate), jobs._fit (who crews the walls), an order",
	"people": "a position, health, mood or trust moved first: morale._modifiers / on_lost / on_downed, bonds.of / bonded, radio.willingness / add_trust, jobs._fit, medical._finish",
	"deeds": "what somebody has done moved first: jobs._fit (who works where), traits.mult / add, medical._finish, scavenge._come_back",
	"radio": "the radio's log grew: a module logs News or raises a call with no avatar (relations / specialists / initiative active()), radio._carry_out",
	"rng": "the random generator moved: a draw of sim.rng in one of the three modules or a hook (they must use none)",
}

## The games (name, seed, crew, game days), in the order they are played.
const GAMES := [
	["plain", 1, 6, 3],
	["plain", 1, 5, 3],
	["plain", 9, 6, 3],
	["plain", 9, 5, 3],
	["informed", 1, 5, 2],
	["informed", 9, 6, 2],
	["orientation", 0, 6, 1.5],
	["avatar_off", 3, 5, 1.5],
	["avatar_classic", 4, 6, 1.5],
	["avatar_orientation", 0, 6, 1],
]

## RE-PINNED after rounds 18 to 21 (2026-10-03): the three avatar games below (avatar_off, avatar_classic, avatar_orientation) play
## AVATAR MODE, which rounds 18 (errands, interact, the panel), 19 (nights: presence, plated brutes, the avatar counted in the crew's
## size) and 21 (the drive) change on purpose; they were re-pinned from the merged tree after checking that rounds 18, 19 and 21 alone
## move them the same way (a round 20 hook leak would also move the NO-avatar games above, which are NOT re-pinned: plain, informed and
## orientation still end as the baseline f23eee3).
## RE-PINNED AGAIN by the round 19 tuning (2026-10-04): avatar_off and avatar_classic play the avatar game's first night, whose size is
## `assets/data/nights.json`'s (`ordinary.*`: the tuned numbers moved it); avatar_orientation (a scripted night) did not move. Any new
## tuning of those numbers moves the two again: re-pin them with a runner on the new numbers, never to hide a hook's leak.
## RE-PINNED A THIRD TIME by the round 22 rules fixes (2026-10-04): in avatar_off and avatar_classic the first night's strays claw a wall that no
## gun reaches for half an hour, and the radio now says so (`going`, "Nobody is covering the pallet barricade", night_calls.gd): ONE more News
## line each (news=15 to 16 and 9 to 10); nothing else of either digest moved (the clock, the stocks, the dead, the walls, the people, the
## deeds and the random generator are the ones of the last pin: the call only asks, and its default is to hold). avatar_orientation is not
## re-pinned: the lesson's scripted night is not called for (`_lesson_on`), and it did not move.
## The digests of the baseline (f23eee3), by "name:seed:crew": the sections of the digest, in order (the comment above each is its summary line).
const PINNED := {
	# plain:1:6: day 4 7.00h | stock ammo=320.0598 food=26.8891 meds=9.9687 scrap=0.0000 water=40.8498 | kills 93 | alive 6/6 | rng 4705235142794603518
	"plain:1:6": [
		"clock: day=4 min=420.0000 clock=4320.0000 t=1440.0000 phase=day over= player=",
		"stock: ammo=320.0598 food=26.8891 meds=9.9687 scrap=0.0000 water=40.8498",
		"field: kills=93 zombies=9",
		"walls: 0=420.0000 1=130.0000 2=220.0000 3=320.0000 4=180.0000 5=420.0000 6=420.0000 7=110.0000 8=190.0000 9=99.2000 10=420.0000 11=180.0000 12=22.2821 13=0.0000 14=160.0000 15=160.0000",
		"people: ruth:51.3605,38.6633,100.0000,65.7333,55.0000,- dez:43.9000,27.1000,100.0000,71.4000,55.0000,- ana:42.3000,47.5000,100.0000,65.7333,55.0000,- marcus:18.9000,16.9000,100.0000,65.7333,55.0000,- walt:45.5422,18.7873,100.0000,66.6667,55.0000,- hector:53.3460,31.4487,100.0000,71.4000,55.0000,-",
		"deeds: ruth:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=22.0000,job=radio,0.0033|0.0033 dez:crafted=0.0000,kills=8.0000,kills_night=1.0000,mended=298.6686,shots=81.0000,treated=0.0000,skills=23.0000,job=bench,0.0033|0.0033 ana:crafted=0.0000,kills=2.0000,kills_night=0.0000,mended=0.0000,shots=16.0000,treated=0.0000,skills=23.0000,job=infirmary,0.0033|0.0033 marcus:crafted=0.0000,kills=37.0000,kills_night=27.0000,mended=0.0000,shots=81.0000,treated=0.0000,skills=12.0000,job=watch,0.0033|0.0033 walt:crafted=0.0000,kills=46.0000,kills_night=5.0000,mended=99.2000,shots=216.0000,treated=0.0000,skills=21.0000,job=builders,0.0033|0.0033 hector:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=19.0000,job=garden,0.0033|0.0033",
		"radio: news=0 latest=0 alarm=false",
		"rng: state=4705235142794603518 seed=1",
	],
	# plain:1:5: day 4 7.00h | stock ammo=299.3148 food=22.5370 meds=9.9016 scrap=2.7397 water=53.0367 | kills 88 | alive 5/5 | rng -4803076983385517434
	"plain:1:5": [
		"clock: day=4 min=420.0000 clock=4320.0000 t=1440.0000 phase=day over= player=",
		"stock: ammo=299.3148 food=22.5370 meds=9.9016 scrap=2.7397 water=53.0367",
		"field: kills=88 zombies=12",
		"walls: 0=420.0000 1=130.0000 2=220.0000 3=320.0000 4=180.0000 5=420.0000 6=420.0000 7=110.0000 8=190.0000 9=130.0000 10=420.0000 11=180.0000 12=148.6295 13=0.0000 14=160.0000 15=108.0783",
		"people: ruth:60.4254,46.5897,100.0000,65.0000,55.0000,- dez:43.9000,27.1000,100.0000,69.6667,55.0000,- ana:48.5161,53.4677,100.0000,65.7333,55.0000,- marcus:18.9000,16.9000,100.0000,65.7333,55.0000,- walt:29.4000,41.4000,100.0000,65.7333,55.0000,-",
		"deeds: ruth:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=22.0000,job=radio,0.0033|0.0033 dez:crafted=0.0000,kills=14.0000,kills_night=4.0000,mended=110.0000,shots=138.0000,treated=0.0000,skills=23.0000,job=bench,0.0033|0.0033 ana:crafted=0.0000,kills=5.0000,kills_night=0.0000,mended=0.0000,shots=57.0000,treated=0.0000,skills=23.0000,job=infirmary,0.0033|0.0033 marcus:crafted=0.0000,kills=19.0000,kills_night=2.0000,mended=0.0000,shots=47.0000,treated=0.0000,skills=12.0000,job=watch,0.0033|0.0033 walt:crafted=0.0000,kills=50.0000,kills_night=22.0000,mended=260.0000,shots=245.0000,treated=0.0000,skills=21.0000,job=builders,0.0033|0.0033",
		"radio: news=0 latest=0 alarm=false",
		"rng: state=-4803076983385517434 seed=1",
	],
	# plain:9:6: day 4 7.00h | stock ammo=300.0000 food=26.9739 meds=9.9927 scrap=15.6694 water=48.9702 | kills 103 | alive 6/6 | rng 4082127260815537497
	"plain:9:6": [
		"clock: day=4 min=420.0000 clock=4320.0000 t=1440.0000 phase=day over= player=",
		"stock: ammo=300.0000 food=26.9739 meds=9.9927 scrap=15.6694 water=48.9702",
		"field: kills=103 zombies=8",
		"walls: 0=420.0000 1=130.0000 2=220.0000 3=320.0000 4=180.0000 5=420.0000 6=420.0000 7=105.7258 8=175.7279 9=26.6235 10=420.0000 11=180.0000 12=320.0000 13=110.0000 14=160.0000 15=160.0000",
		"people: ruth:51.3605,38.6633,100.0000,65.7333,55.0000,- dez:43.9000,27.1000,100.0000,71.4000,55.0000,- ana:42.3000,47.5000,100.0000,65.7333,55.0000,- marcus:18.9000,16.9000,100.0000,65.7333,55.0000,- walt:40.6821,28.9999,100.0000,66.9333,55.0000,- hector:53.3460,31.4487,100.0000,71.4000,55.0000,-",
		"deeds: ruth:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=22.0000,job=radio,0.0033|0.0033 dez:crafted=0.2562,kills=1.0000,kills_night=0.0000,mended=0.0000,shots=2.0000,treated=0.0000,skills=23.0000,job=bench,0.0033|0.0033 ana:crafted=0.0000,kills=15.0000,kills_night=12.0000,mended=0.0000,shots=191.0000,treated=0.0000,skills=23.0000,job=infirmary,0.0033|0.0033 marcus:crafted=0.0000,kills=32.0000,kills_night=22.0000,mended=0.0000,shots=80.0000,treated=0.0000,skills=12.0000,job=watch,0.0033|0.0033 walt:crafted=0.0000,kills=55.0000,kills_night=2.0000,mended=240.0000,shots=236.0000,treated=0.0000,skills=21.0000,job=builders,0.0033|0.0033 hector:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=19.0000,job=garden,0.0033|0.0033",
		"radio: news=0 latest=0 alarm=false",
		"rng: state=4082127260815537497 seed=9",
	],
	# plain:9:5: day 4 7.00h | stock ammo=312.7527 food=24.0671 meds=8.8776 scrap=0.0000 water=47.3964 | kills 88 | alive 4/5 | rng 5647354039282611896
	"plain:9:5": [
		"clock: day=4 min=420.0000 clock=4320.0000 t=1440.0000 phase=day over= player=",
		"stock: ammo=312.7527 food=24.0671 meds=8.8776 scrap=0.0000 water=47.3964",
		"field: kills=88 zombies=4",
		"walls: 0=420.0000 1=130.0000 2=220.0000 3=320.0000 4=180.0000 5=420.0000 6=420.0000 7=110.0000 8=190.0000 9=0.0000 10=420.0000 11=180.0000 12=85.7725 13=0.0000 14=160.0000 15=160.0000",
		"people: ruth:60.4254,46.5897,100.0000,65.7333,55.0000,- dez:43.9000,27.1000,100.0000,69.6667,55.0000,- ana:48.5161,53.4677,82.2773,57.0000,55.0000,x marcus:18.9000,16.9000,100.0000,65.7333,55.0000,- walt:29.4000,41.4000,100.0000,65.7333,55.0000,-",
		"deeds: ruth:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=1.0000,skills=22.0000,job=radio,0.0033|0.0033 dez:crafted=0.0000,kills=1.0000,kills_night=0.0000,mended=265.4425,shots=15.0000,treated=0.0000,skills=23.0000,job=bench,0.0033|0.0033 ana:crafted=0.0000,kills=7.0000,kills_night=0.0000,mended=0.0000,shots=115.0000,treated=0.0000,skills=23.0000,job=infirmary,4.9200|4.9200 marcus:crafted=0.0000,kills=51.0000,kills_night=24.0000,mended=0.0000,shots=139.0000,treated=0.0000,skills=12.0000,job=watch,0.0033|0.0033 walt:crafted=0.0000,kills=29.0000,kills_night=4.0000,mended=130.0000,shots=144.0000,treated=0.0000,skills=21.0000,job=builders,0.0033|0.0033",
		"radio: news=0 latest=0 alarm=false",
		"rng: state=5647354039282611896 seed=9",
	],
	# informed:1:5: day 3 7.00h | stock ammo=328.2800 food=38.4933 meds=7.0000 scrap=0.0000 water=47.5000 | kills 66 | alive 4/6 | rng -774968178190305847
	"informed:1:5": [
		"clock: day=3 min=420.0000 clock=2880.0000 t=960.0000 phase=day over= player=",
		"stock: ammo=328.2800 food=38.4933 meds=7.0000 scrap=0.0000 water=47.5000",
		"field: kills=66 zombies=4",
		"walls: 0=287.1340 1=130.0000 2=220.0000 3=320.0000 4=180.0000 5=271.3008 6=414.2394 7=110.0000 8=190.0000 9=130.0000 10=420.0000 11=180.0000 12=320.0000 13=110.0000 14=160.0000 15=160.0000",
		"people: ruth:60.4993,46.6000,100.0000,65.7333,55.0000,- dez:29.3652,41.3892,100.0000,70.7333,55.0000,- ana:48.5161,53.4677,100.0000,65.7333,55.0000,- marcus:37.9000,18.5000,95.7867,66.2000,55.0000,a walt:40.1135,18.6031,100.0000,66.0000,55.0000,a hector:30.5000,41.4000,100.0000,70.7333,55.0000,-",
		"deeds: ruth:crafted=0.0000,kills=7.0000,kills_night=7.0000,mended=0.0000,shots=18.0000,treated=0.0000,skills=22.0000,job=radio,0.0033|0.0033 dez:crafted=0.0000,kills=23.0000,kills_night=21.0000,mended=266.0448,shots=166.0000,treated=0.0000,skills=23.0000,job=builders,0.0033|0.0033 ana:crafted=0.0000,kills=1.0000,kills_night=1.0000,mended=0.0000,shots=11.0000,treated=2.0000,skills=23.0000,job=infirmary,0.0033|0.0033 marcus:crafted=0.0000,kills=21.0000,kills_night=4.0000,mended=0.0000,shots=67.0000,treated=0.0000,skills=12.0000,job=watch,11.8333|11.8333 walt:crafted=0.0000,kills=14.0000,kills_night=1.0000,mended=0.0000,shots=84.0000,treated=0.0000,skills=21.0000,job=salvage,11.9067|11.9067 hector:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=64.0413,shots=0.0000,treated=0.0000,skills=19.0000,job=builders,0.0033|0.0033",
		"radio: news=0 latest=0 alarm=false",
		"rng: state=-774968178190305847 seed=1",
	],
	# informed:9:6: day 3 7.00h | stock ammo=347.2200 food=29.6600 meds=10.0000 scrap=16.0000 water=56.0000 | kills 67 | alive 6/6 | rng 1346396378123742129
	"informed:9:6": [
		"clock: day=3 min=420.0000 clock=2880.0000 t=960.0000 phase=day over= player=",
		"stock: ammo=347.2200 food=29.6600 meds=10.0000 scrap=16.0000 water=56.0000",
		"field: kills=67 zombies=9",
		"walls: 0=333.1662 1=121.4657 2=220.0000 3=320.0000 4=180.0000 5=420.0000 6=418.6160 7=110.0000 8=190.0000 9=130.0000 10=420.0000 11=180.0000 12=320.0000 13=110.0000 14=160.0000 15=160.0000",
		"people: ruth:51.3605,38.6633,100.0000,69.0000,55.0000,- dez:29.3000,18.5000,100.0000,68.8000,55.0000,- ana:41.7000,47.5000,100.0000,74.4000,55.0000,- marcus:18.9444,16.9444,100.0000,69.2667,55.0000,- walt:41.5572,30.1909,100.0000,67.0667,55.0000,- hector:28.3134,35.8003,100.0000,65.8000,55.0000,-",
		"deeds: ruth:crafted=0.0000,kills=9.0000,kills_night=9.0000,mended=0.0000,shots=17.0000,treated=0.0000,skills=22.0000,job=radio,0.0033|0.0033 dez:crafted=0.0000,kills=7.0000,kills_night=0.0000,mended=0.0000,shots=60.0000,treated=0.0000,skills=23.0000,job=builders,0.0033|0.0033 ana:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=4.0000,treated=0.0000,skills=23.0000,job=infirmary,0.0033|0.0033 marcus:crafted=0.0000,kills=45.0000,kills_night=21.0000,mended=0.0000,shots=123.0000,treated=0.0000,skills=12.0000,job=watch,0.0033|0.0033 walt:crafted=0.0000,kills=6.0000,kills_night=3.0000,mended=0.0000,shots=48.0000,treated=0.0000,skills=21.0000,job=salvage,0.0033|0.0033 hector:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=140.0080,shots=0.0000,treated=0.0000,skills=19.0000,job=salvage,0.0033|0.0033",
		"radio: news=0 latest=0 alarm=false",
		"rng: state=1346396378123742129 seed=9",
	],
	# orientation:0:6: day 2 19.00h | stock ammo=143.0000 food=26.6000 meds=9.0000 scrap=40.0000 water=41.0000 | kills 9 | alive 6/6 | rng 7896914316066857157
	"orientation:0:6": [
		"clock: day=2 min=1140.0000 clock=2160.0000 t=720.0000 phase=dusk over= player=",
		"stock: ammo=143.0000 food=26.6000 meds=9.0000 scrap=40.0000 water=41.0000",
		"field: kills=9 zombies=0",
		"walls: 0=420.0000 1=130.0000 2=220.0000 3=144.0000 4=180.0000 5=420.0000 6=420.0000 7=110.0000 8=190.0000 9=26.0000 10=420.0000 11=180.0000 12=320.0000 13=22.0000 14=160.0000 15=160.0000",
		"people: ruth:60.2273,46.5625,100.0000,70.0000,55.0000,- dez:47.5422,18.7873,100.0000,70.0000,55.0000,- ana:48.5791,53.2779,100.0000,70.0000,55.0000,- marcus:18.9000,16.9000,100.0000,70.0000,55.0000,- walt:65.2000,16.9000,97.9333,70.0000,55.0000,- hector:34.2000,18.8000,100.0000,70.0000,55.0000,-",
		"deeds: ruth:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=22.0000,job=radio,0.0033|0.0033 dez:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=7.0000,treated=0.0000,skills=23.0000,job=,0.0033|0.0033 ana:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=1.0000,skills=23.0000,job=infirmary,0.0033|0.0033 marcus:crafted=0.0000,kills=4.0000,kills_night=0.0000,mended=0.0000,shots=11.0000,treated=0.0000,skills=12.0000,job=watch,0.0033|0.0033 walt:crafted=0.0000,kills=5.0000,kills_night=0.0000,mended=0.0000,shots=17.0000,treated=0.0000,skills=21.0000,job=,0.0033|0.0033 hector:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=19.0000,job=,0.0033|0.0033",
		"radio: news=0 latest=0 alarm=false",
		"rng: state=7896914316066857157 seed=1001",
	],
	# avatar_off:3:5: day 2 19.00h | stock ammo=368.8962 food=31.3340 meds=8.8286 scrap=0.0000 water=56.9907 | kills 21 | alive 3/5 | rng 8616171887323474408
	"avatar_off:3:5": [
		"clock: day=2 min=1140.0000 clock=2160.0000 t=720.0000 phase=dusk over= player=walt",
		"stock: ammo=368.8962 food=31.3340 meds=8.8286 scrap=0.0000 water=56.9907",
		"field: kills=21 zombies=0",
		"walls: 0=420.0000 1=130.0000 2=220.0000 3=320.0000 4=12.6000 5=73.2715 6=420.0000 7=110.0000 8=190.0000 9=59.7428 10=420.0000 11=180.0000 12=320.0000 13=110.0000 14=160.0000 15=160.0000",
		"people: ruth:60.5000,46.6000,100.0000,70.6000,55.0000,x dez:58.4054,46.5897,100.0000,58.1333,45.0000,x ana:29.2480,41.2700,100.0000,62.3267,45.0000,- marcus:33.1897,29.7759,100.0000,44.0667,45.0000,- walt:60.4254,46.5897,100.0000,65.0667,45.0000,-",
		"deeds: ruth:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=22.0000,job=,4.5533|4.5533 dez:crafted=0.0000,kills=6.0000,kills_night=0.0000,mended=0.0000,shots=66.0000,treated=1.0000,skills=23.0000,job=builders,4.0533|4.0533 ana:crafted=0.0000,kills=1.0000,kills_night=0.0000,mended=392.3428,shots=8.0000,treated=0.0000,skills=23.0000,job=builders,0.0033|0.0033 marcus:crafted=0.0000,kills=13.0000,kills_night=0.0000,mended=0.0000,shots=41.0000,treated=0.0000,skills=12.0000,job=garden,0.0033|0.0033 walt:crafted=0.0000,kills=1.0000,kills_night=0.0000,mended=0.0000,shots=3.0000,treated=0.0000,skills=21.0000,job=,0.0033|0.0033",
		"radio: news=16 latest=16 alarm=false",
		"rng: state=8616171887323474408 seed=3",
	],
	# avatar_classic:4:6: day 2 19.00h | stock ammo=354.0999 food=29.4976 meds=3.8754 scrap=0.0000 water=42.7491 | kills 27 | alive 4/6 | rng 3864034759446752742
	"avatar_classic:4:6": [
		"clock: day=2 min=1140.0000 clock=2160.0000 t=720.0000 phase=dusk over= player=walt",
		"stock: ammo=354.0999 food=29.4976 meds=3.8754 scrap=0.0000 water=42.7491",
		"field: kills=27 zombies=0",
		"walls: 0=393.7428 1=105.7351 2=220.0000 3=320.0000 4=180.0000 5=410.7572 6=420.0000 7=110.0000 8=190.0000 9=0.0000 10=420.0000 11=180.0000 12=320.0000 13=110.0000 14=160.0000 15=160.0000",
		"people: ruth:60.5000,46.6000,100.0000,72.0000,55.0000,x dez:53.5000,31.5000,100.0000,47.3333,45.0000,x ana:60.4923,46.3454,100.0000,68.0867,45.0000,- marcus:18.9444,16.9444,100.0000,60.2667,45.0000,- walt:60.4923,46.3454,100.0000,65.2000,45.0000,- hector:34.2000,18.8000,40.0000,47.8000,45.0000,-",
		"deeds: ruth:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=22.0000,job=,4.5533|4.5533 dez:crafted=0.0000,kills=22.0000,kills_night=0.0000,mended=0.0000,shots=191.0000,treated=3.0000,skills=23.0000,job=garden,4.0533|4.0533 ana:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=23.0000,job=builders,0.0033|0.0033 marcus:crafted=0.0000,kills=3.0000,kills_night=0.0000,mended=0.0000,shots=10.0000,treated=0.0000,skills=12.0000,job=watch,0.0033|0.0033 walt:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=21.0000,job=,0.0033|0.0033 hector:crafted=0.0000,kills=2.0000,kills_night=0.0000,mended=393.7428,shots=0.0000,treated=1.0000,skills=19.0000,job=builders,0.0033|0.0033",
		"radio: news=10 latest=10 alarm=false",
		"rng: state=3864034759446752742 seed=4",
	],
	# avatar_orientation:0:6: day 2 7.00h | stock ammo=141.8000 food=30.6000 meds=7.0000 scrap=40.0000 water=55.0000 | kills 7 | alive 6/6 | rng 3298888767220174665
	"avatar_orientation:0:6": [
		"clock: day=2 min=420.0000 clock=1440.0000 t=480.0000 phase=day over= player=ruth",
		"stock: ammo=141.8000 food=30.6000 meds=7.0000 scrap=40.0000 water=55.0000",
		"field: kills=7 zombies=1",
		"walls: 0=420.0000 1=130.0000 2=220.0000 3=320.0000 4=180.0000 5=414.5616 6=184.8111 7=110.0000 8=190.0000 9=26.0000 10=214.0055 11=180.0000 12=320.0000 13=22.0000 14=160.0000 15=160.0000",
		"people: ruth:43.0000,22.5000,100.0000,70.0000,55.0000,- dez:43.0000,22.5000,100.0000,70.0000,55.0000,- ana:20.8000,33.0000,100.0000,70.0000,55.0000,- marcus:43.0000,21.5000,100.0000,70.0000,55.0000,- walt:43.0000,22.5000,96.5067,70.0000,55.0000,- hector:43.0000,21.1500,100.0000,70.0000,55.0000,-",
		"deeds: ruth:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=22.0000,job=,0.0033|0.0033 dez:crafted=0.0000,kills=3.0000,kills_night=3.0000,mended=0.0000,shots=21.0000,treated=2.0000,skills=23.0000,job=,0.0033|0.0033 ana:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=23.0000,job=infirmary,0.0033|0.0033 marcus:crafted=0.0000,kills=4.0000,kills_night=4.0000,mended=0.0000,shots=19.0000,treated=0.0000,skills=12.0000,job=watch,0.0033|0.0033 walt:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=1.0000,treated=0.0000,skills=21.0000,job=,0.0033|0.0033 hector:crafted=0.0000,kills=0.0000,kills_night=0.0000,mended=0.0000,shots=0.0000,treated=0.0000,skills=19.0000,job=,0.0033|0.0033",
		"radio: news=6 latest=6 alarm=false",
		"rng: state=3298888767220174665 seed=1001",
	],
}


## The key of a game in PINNED (and in what the runner that records the baseline prints).
static func game_key(g: Array) -> String:
	return "%s:%d:%d" % [g[0], g[1], g[2]]


## Plays one game for `days` game days (a part of a day too) at `hz` rules' steps a second and returns its digest: {"sections": {name: string},
## "full": the sections joined, "summary": one readable line, "took": seconds}. `game` is one of the games above.
static func digest(game: String, seed_value: int, crew: int, days: float = 3.0, hz: float = HZ) -> Dictionary:
	var started := Time.get_ticks_msec()
	var world = null
	var sim = null
	var policy = null
	var bot := false
	var mishaps := false
	match game:
		"plain":
			var g := Helpers.make(seed_value, 1, crew)
			world = g.world
			sim = g.sim
		"informed":
			var g := Helpers.make(seed_value, 1, crew)
			world = g.world
			sim = g.sim
			sim.streets.enabled = true
			sim.storyteller.enabled = true    # (the harness plays with the radio's cards)
			policy = Balance.Policy.new(sim)
			policy.informed = true
			policy.builds = true
			policy.lots_enabled = true
			policy.vehicles_enabled = true
			policy.build_order = []
			policy.beds_first = false
		"orientation", "avatar_orientation":
			var data := GD.load_all()
			world = World.new()
			Engine.get_main_loop().root.add_child(world)
			world.build(data)
			sim = Sim.new(data, world, FxNull.new())
			Orientation.begin(sim, game == "avatar_orientation")
			if game == "avatar_orientation":
				sim.avatar.set_player("ruth")
			bot = game == "avatar_orientation"
		"avatar_off", "avatar_classic":
			var g := Helpers.make(seed_value, 1, crew)
			world = g.world
			sim = g.sim
			if game == "avatar_off":
				for m in ["relations", "specialists", "initiative"]:
					var mod = sim.get(m)    # (null in the baseline, which has none)
					if mod != null:
						mod.enabled = false
			sim.avatar.set_player("ruth")
			policy = Balance.Policy.new(sim)
			bot = true
			mishaps = true
		_:
			push_error("no such game: %s" % game)
			return {}
	var dt := 1.0 / hz
	var every := maxi(1, roundi(hz))
	var steps := int(days * 24.0 * 20.0 * hz)
	for i in steps:
		sim.update(dt)
		if sim.over != "":
			break
		if i % every == every - 1:
			var second := floori(float(i) / float(every))
			if policy != null:
				policy.tick()
			if bot:
				_bot(sim, second)
			if mishaps:
				_mishaps(sim, second)
	var out := read(sim)
	out["took"] = snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1)
	world.free()
	return out


## The bot of the avatar games: once a second of rules time it answers every call that waits and has an odd id with its first
## option (the others take their default when their time is up), and every 30 seconds (an hour and a half of game time) it
## asks the next living member of the crew for the next thing of the radio's six: come, hold, cover, search, back, post.
## (Nothing here is random and nothing names a module of round 20.)
static func _bot(sim, second: int) -> void:
	var radio = sim.radio
	for e in radio.open_calls():
		if int(e.id) % 2 == 1 and not e.options.is_empty():
			radio.answer(int(e.id), String(e.options[0].id))
	if second % 30 != 15:
		return
	var others: Array = []
	for p in sim.people:
		if not p.dead and not p.turned and not p.player and p.away == null:
			others.append(p)
	if others.is_empty():
		return
	var k := floori(second / 30.0)
	radio.request(others[k % others.size()], String(radio.VERBS[k % radio.VERBS.size()]))


## The mishaps of the avatar games (a fixed schedule, nothing random): the third of the living is downed by a bite at the 150th second
## (13:30 on day 1), the player dies at the 330th (the next in line takes over: `avatar._before`, `on_player_lost`), another dies
## at the 560th. They reach `morale.on_downed`, `on_lost` (the grief) and the succession.
static func _mishaps(sim, second: int) -> void:
	var living: Array = []
	for p in sim.people:
		if not p.dead and not p.turned and p.away == null:
			living.append(p)
	if second == 150 and living.size() > 2:
		sim.medical.on_downed(living[2], "bite")
	elif second == 330:
		var me = sim.avatar.player()
		if me != null:
			sim.medical.kill(me, "bled out")
	elif second == 560:
		for p in living:
			if not p.player and not p.dead:
				sim.medical.kill(p, "bled out")
				break


static func _f(v) -> String:
	return "%.4f" % float(v)


## The game as sections of tokens (see the top of the file).
static func read(sim) -> Dictionary:
	var sec := {}
	sec["clock"] = "day=%d min=%s clock=%s t=%s phase=%s over=%s player=%s" % [sim.day, _f(sim.minutes), _f(sim.clock_min), _f(sim.t), str(sim.phase), str(sim.over), str(sim.player_id)]
	var stock: Array = []
	var keys: Array = sim.stock.keys()
	keys.sort()
	for k in keys:
		stock.append("%s=%s" % [k, _f(sim.stock[k])])
	sec["stock"] = " ".join(stock)
	sec["field"] = "kills=%d zombies=%d" % [sim.kills, sim.zombies.size()]
	var walls: Array = []
	for i in sim.segments.size():
		walls.append("%d=%s" % [i, _f(sim.segments[i].hp)])
	sec["walls"] = " ".join(walls)
	var people: Array = []
	var deeds: Array = []
	var alive := 0
	for p in sim.people:
		var state := "-"
		if p.dead:
			state = "x"
		elif p.turned:
			state = "t"
		elif p.away != null:
			state = "a"
		elif p.downed:
			state = "d"
		else:
			alive += 1
		people.append("%s:%s,%s,%s,%s,%s,%s" % [p.id, _f(p.x), _f(p.y), _f(p.hp), _f(sim.morale.value(p)), _f(p.trust), state])
		var stats: Array = []
		var sk: Array = p.stats.keys()
		sk.sort()
		for k in sk:
			stats.append("%s=%s" % [k, _f(p.stats[k])])
		var skills := 0.0
		for k in p.skills:
			skills += float(p.skills[k])
		deeds.append("%s:%s,skills=%s,job=%s,%s" % [p.id, ",".join(stats), _f(skills), str(sim.jobs.job_of(p)), "|".join([_f(p.hunger_h), _f(p.thirst_h)])])
	sec["people"] = " ".join(people)
	sec["deeds"] = " ".join(deeds)
	sec["radio"] = "news=%d latest=%d alarm=%s" % [sim.radio.news.size(), sim.radio.latest_id(), str(sim.radio.alarm_on)]
	sec["rng"] = "state=%d seed=%d" % [sim.rng.state, sim.rng.seed]
	var parts: Array = []
	for s in SECTIONS:
		parts.append("%s: %s" % [s, sec[s]])
	var summary := "day %d %.2fh | stock %s | kills %d | alive %d/%d | rng %d" % [sim.day, sim.hour, sec["stock"], sim.kills, alive, sim.people.size(), sim.rng.state]
	return {"sections": sec, "full": JOIN.join(parts), "summary": summary}


## The first token that differs between two digests' texts, with where it is, for a failure message.
static func first_drift(pinned: String, got: String) -> String:
	var a := pinned.split(JOIN)
	var b := got.split(JOIN)
	for i in maxi(a.size(), b.size()):
		var x: String = a[i] if i < a.size() else "(missing)"
		var y: String = b[i] if i < b.size() else "(missing)"
		if x == y:
			continue
		var ta := x.split(" ")
		var tb := y.split(" ")
		for j in maxi(ta.size(), tb.size()):
			var u: String = ta[j] if j < ta.size() else "(missing)"
			var v: String = tb[j] if j < tb.size() else "(missing)"
			if u != v:
				return "first difference, section '%s' token %d: pinned '%s', now '%s'" % [x.split(":")[0], j, u, v]
	return "no difference"


# ----------------------------------------------------------------------- the games --

func _check_game(g: Array) -> void:
	var key := game_key(g)
	var d := digest(String(g[0]), int(g[1]), int(g[2]), float(g[3]))
	if d.is_empty():
		check(false, "%s: no digest" % key)
		return
	if not PINNED.has(key):
		check(false, "%s: nothing is pinned yet; it ended as: %s" % [key, d.summary])
		return
	var pinned := JOIN.join(PINNED[key])
	if String(d.full) != pinned:
		var drift := first_drift(pinned, String(d.full))
		var hint := ""
		for section in HINTS:
			if drift.contains("section '%s'" % section):
				hint = " Look at: %s." % HINTS[section]
				break
		check(false, "%s moved in a game where round 20 must change nothing (no avatar, the modules off, or not a small start). %s.%s Now: %s" % [key, drift, hint, d.summary])


func _check_games(names: Array) -> void:
	var n := 0
	for g in GAMES:
		if names.has(g[0]):
			_check_game(g)
			n += 1
	check(n >= names.size(), "the list has games called %s" % str(names))


func test_plain_games_end_as_they_did_before_round_20() -> void:
	_check_games(["plain"])


func test_the_harnesss_informed_policy_plays_the_same_games() -> void:
	_check_games(["informed"])


func test_the_classic_orientation_day_plays_the_same_game() -> void:
	_check_games(["orientation"])


func test_with_the_new_modules_off_or_not_active_an_avatar_game_is_the_old_game() -> void:
	_check_games(["avatar_off", "avatar_classic", "avatar_orientation"])


func test_the_digest_itself_is_deterministic_and_reads_what_it_should() -> void:
	# two plays of one game are the same string; a different seed is not (the digest sees the game)
	var a := digest("plain", 1, 6, 0.1)
	var b := digest("plain", 1, 6, 0.1)
	eq(a.full, b.full, "the same game twice")
	check(PINNED["plain:1:6"] != PINNED["plain:9:6"], "another seed is another digest")
	for s in SECTIONS:
		check(String(a.sections[s]) != "", "the section '%s' is not empty" % s)
	check(String(a.sections.people).contains("ruth:"), "the people are in it")
	eq(first_drift(a.full, a.full), "no difference", "no drift of a string from itself")
	check(first_drift(a.full, JOIN.join(PINNED["plain:9:6"])).begins_with("first difference"), "a drift is named")
