# Thirty Bells (Godot)

A small crew holds a walled schoolyard against the dead for thirty nights: three survivors to begin with, and more who call in over the radio. Built in Godot 4.7. (Working title; it was Last Bell until 2026-10-01, when it turned out a Steam game called The Last Bell is coming. The itch.io page and the GitHub repository still carry the old name.)

Open the project and press **F5**. The main scene is `scenes/main.tscn`; a cold start shows the title screen (Continue, New game, Orientation Day, Load, Settings, Credits, Quit). A start with a run choice on the command line (`--new=1`, `--seed=N`, `--crew=3`, `--load=path`, `--shot=...`) goes straight into the yard.

## Controls

| Input | Action |
| --- | --- |
| Click | Select a person, walker or wall piece |
| Drag | Draw a box and select everyone in it (a group); **Shift** adds to the group, and a Shift-click on a person adds or takes them away |
| Ctrl+A (Cmd+A on a Mac) | Select everyone in the yard |
| Right-click | Send the selected person there (drafts them); a group is sent together and spreads round the spot |
| Middle-drag, Alt+drag, or W A S D / arrows | Pan |
| Scroll, pinch or two-finger scroll | Zoom |
| R / P / F | Draft or release / to post / repair, for everyone selected: **R** drafts all if any is not drafted and else releases all, **P** sends each to their own night post, **F** sends them to the worn walls, the worst first |
| C | Follow: the view keeps on the main pick (the first of a group, the one the panel shows; the strip at the top of the panel has a badge for each, a click makes that one the main pick, a Shift-click leaves them out) |
| T / X | Treat the wounded or infected / send an infected person out (the main pick only) |
| G | Send a scavenging party. With the classic start (six people) this is the four-site dialog (select someone first to have them lead); in a small start (three people) it is the **Town Board**, a map of the town with the places you know, the party picker and Go, Scout, Clear, Claim, Garrison and Recall (the bag button in the toolbar does the same, and so does the Scavenge button of a person's panel; G or Esc closes it); the game waits while either is open |
| M | Give the selected person the Workbench job (they make ammo at the worktable by day), or take it away again |
| V | Show how many guns reach each wall section from where the crew stands at night (red none, amber one, green two or more) |
| L | Set the alarm on the selected wall section |
| B | Give the selected person the Builders job (they mend the worn walls and build what you order, by day), or take it away again |
| J | The Jobs screen, the duty roster: everyone's day job and night post, the stations and their settings, Auto-assign and Clear (the clipboard button in the toolbar does the same); the game waits while it is open |
| N | The Build screen: a short list of the buildings (each has its own home in the yard: nobody picks a plot), what each costs and gives, Build, sites, cancel and demolish (the hammer button in the toolbar does the same, and so does a click on a home's sign in the yard, on that building). In a small start it is also where the **lots** of the streets round the school are claimed and walled in (below); the game waits while it is open |
| Space, 1, 2, 3 | Pause, normal, fast, fastest |
| Tab | Next person (skips the lost and those away) |
| Esc | Clear the selection (the whole group); with nothing selected, the menu (resume, save, load, settings, how to play, main menu, quit) |

## Playing

A new game starts on day 1 at 07:00 with a quiet yard. The dead come at dusk, more each night.

- **Supplies.** At 07:00, 13:00 and 19:00 everyone eats and drinks. The stores panel shows how many days of food and water are left. The rain barrels give a little each dawn, and the vegetable beds grow food by the hour for whoever works them. Repairs cost scrap (1 for every 10 points of wall health), bandages cost medicine, and shooting costs ammo: when the stock cannot pay for another shot the guns stay silent and people fight with the butt of the gun (a pike never runs dry), and an alert says so.
- **Wounds.** A bite or scratch bleeds until someone bandages it (Ana first); at 0 health a person is downed and must be stabilised within three game hours, then rests in bed. A **bite** can infect: a feverish person turns into a walker 12 to 24 hours later unless treated (**T**, two medicine, better with Medicine skill) or sent out through the gate (**X**).
- **Scavenging.** Select someone and press **G** to send one or two survivors through the gate between 06:30 and 10:00, to the houses (food and water), the pharmacy (medicine), the hardware store (scrap and ammo) or the scrapyard (a great deal of scrap, and the most dangerous). They come back at 16:00 with loot, hurt, or not at all. A raided site is picked over for three days. That is the classic start (six people).

  In a small start (the settlement game) the world beyond the wall is the **Town Board**: press **G** (or the bag in the toolbar) and a paper map of the town opens, with a pin for each place you know (an icon for what kind of place it is; a tick when it has been cleared, a flag when it is your outpost, a red disc with a number for a nest, a small figure for someone hiding there) and a faint question mark for each place nobody has seen yet. Click a pin, or Tab and the arrows to it and press Enter: the card says how dangerous the place is, how long the trip takes (a trip that would run past dusk is "back tomorrow": a night out, with nobody on the wall), what it is likely to give, and what is known about it. Pick one to three people who are free (the leader first; a lone scavenger brings back less, a good leader finds more) and one of six things, each of which says why it cannot be done when it cannot: **Go** searches the place for loot; **Scout** looks the way over and shows the places near it, with nothing brought back; **Clear** turns the dead out of the place and ends a nest (a nest needs two people; the page tells the chance in words, from the party's Shooting against the place's danger); **Claim** makes a cleared place with an outpost yours, for scrap, and it pays a daily yield at dawn; **Garrison** leaves the party at an outpost to hold it against the night (an outpost with nobody there can be overrun) until **Recall** brings them home. The map shows each party that is out on its road, there and back, and the strip under it says who is out, where, and when they are due ("back about 14:30", "back tomorrow"). A nest sends the dead to the night: clear it and the heading it leans to quietens and the night shrinks a little. A tip comes once, the first time the board could be opened.

  **Vehicles and fuel (round 13, a small start only).** The town holds a few vehicles (a sedan, a pickup, a van, a bus) in its places: a place that has one says so on its card ("A pickup stands here: loot it to try to get it running"), and a party that loots or clears it and comes home may have got it running and driven it home. It is then the colony's: it is **parked at the gate**, in the north street, in the picture of its kind (up to four stand there; one that is out with a party is not drawn, a badly worn one is darker and a nearly done one has a small spanner over it), and a click on one opens the Town Board. Once the colony has a vehicle the party picker has a **ride** row under the people: **On foot**, or a chip for each parked vehicle with its name, its seats, the **fuel** the trip to the chosen place burns and the trip's hours by it; the one you pick sets how many may go (its seats in place of three), the hours on the card and in the buttons' tips, and goes with **Go**, **Scout** and **Clear**. A vehicle makes the road in about half the time, carries more loot and burns fuel for each hour driven; what the rules refuse (not enough fuel, too many people for the seats) is written under the buttons like the other reasons. **Fuel** is found as loot (the gas stations, the garage, the truck stop, the fuel depot across the river) and kept in a tank of its own: in a small start the stores panel shows a **Fuel** line (a pump) once there is a vehicle or any fuel, in amber while it is under ten and there is a vehicle to burn it. **Across the river** the city (ten places, from a hospital and a mall to a rail yard and a power station) is too far to walk to: its pins have a blue ring of dashes and the card says "By vehicle only". The map shows what is known, not the whole board: it is the town at the start, and it widens when the bridge is found (the river is drawn through it and a chip at the east edge says "Across the river") and again when the city is. A party that went by vehicle is a blue plate with a small car on it, and the strip at the foot says "in the van". A tip comes once, the first time the colony has a vehicle, on the toolbar's Town Board button.
- **A played trip: taking control of the squad.** A trip does not have to be left to the dice: the party can be played on a small map of the place itself (scripts/raid/: `raid_run.gd` the rules, `site_gen.gd` the places, `raid_scene.gd` the scene). The squad arrives at the road's edge (or at its vehicle), the dead stand about the place and notice the squad within seven tiles and in sight (a shot is heard from twelve), and the things to search (shelves, crates, cabinets, fridges, lockers, trunks, pumps) hold what the place is known for. Search by standing at a container for a few seconds; the bags hold thirty for each person standing, and a vehicle's cargo room more; get everyone back to the road to leave. What is brought home, who is hurt (bitten) or lost, whether the place was cleared, whether someone was found and the ammo used are the trip's result, exactly as the dice would have made it. The colony waits while the raid is played, and none of its keys reach it. Controls: **left-click** a person or **drag a box** to select (shift adds or takes away; **1** to **6** pick one person, **Tab** goes round, **A** is everyone, a click on a card does the same); **right-click** open ground to walk the selection there (they spread a little round the click), a **container** to send the nearest of the selection to search it, a **friend who is down** to send the nearest other to help them up (four seconds beside them); **Space** pauses (orders can be given while it is paused); **scroll** zooms, the **middle mouse**, the **arrow keys** or the pointer at the window's edge pan, **F** follows the selection; **R** (or the Retreat button) sends everyone back to the road at once; **Esc** asks "Retreat?" first (Esc again or Enter says yes, any other key says no); **H** shows the legend again (it fades after fourteen seconds). The squad fires at what is in reach on its own, as in the yard. The cards along the top show each person's health, weapon and magazine and what they are doing (Searching, Helping, Down...), the bags' tally and how full they are is at the top right, the last four lines of what happened fade in at the foot, and a banner says when the dead have heard a shot or a friend has fallen. At the end a paper card gives the report and one button: **Go home** (Enter). Nothing opens one yet from the game: `main.open_raid(people, place, vehicle_id, loot_mult, on_done)` is the way in, for the Town Board's "Take control" button.
- **Jobs and stations (J).** Everyone has a day job and a night post, and you give them on the **Jobs screen** (the duty roster): a table of the crew with a day job and a night post to choose for each, the six stations with their seats and settings, and **Auto-assign** (fills the seats by skill) and **Clear**. The game waits while it is open; hovering a row, a station or a post marks its place in the yard. By day a person works at their station, at the bell they go to their post and hold it, and a person with nothing to do mends a badly worn wall (under half) or stands at ease. An order (right-click, **R**, **P**, **F**) beats the job until you release it, then they go back to it. The stations:
  - **Workbench** (2 seats, Building): turns scrap into ammo, 8 ammo for each scrap (2 scrap an hour, plus half a scrap for each point of Building), while the ammo is under the station's target (300) and the scrap above its reserve (3). **M** gives the selected person this job or takes it away.
  - **Builders** (3 seats, Building): mends the most worn wall section under the station's threshold (70%) while there is scrap, and builds what you order on the Build screen (below); a repair mends 5 points a second plus the person's Building skill. **B** gives or takes the job. **F** is still a one-off repair order.
  - **Vegetable beds** (2 seats): the beds grow about 0.2 food an hour for each gardener on top of a small share that grows unattended; one gardener is worth about 3 food a day, two about 5.
  - **Infirmary** (2 seats, Medicine): the people here treat the hurt first, and patients resting in a bed heal half as fast again while someone is on duty.
  - **Radio desk** (1 seat, Leading): the noon call comes only if someone is at the desk at 12:00, and that person speaks. With nobody there the radio stays silent that day and an alert says so.
  - **Lookout post** (1 seat, Shooting): the 17:00 forecast comes only from someone on watch there. With nobody there nobody tells the crew, and an alert says so.
  Ammo is what runs out first, and scrap is what the walls, the bench and the scrapyard trips are all about.
- **Buildings (N).** **Every building has its own home, a place where it belongs, and nobody picks a plot** (round 15; the homes are in `assets/data/plots.json`, nine in the compound, each with the name of the place and a sentence of why): the **salvage bench** by the junk pile in the south-west corner, the **greenhouse beds** against the garden's lower edge, the **workshop** under the workbench's tarp, the two **bunk houses** (numbered 1 of 2 and 2 of 2, built in that order) against the school's front wall, the **floodlights** and the two **watchtowers** (one either side of the gate, each reaching two night posts) on the north wall, the **radio mast** at the school's east end by the radio desk. No home is on the basketball court, the garden, the hopscotch or the four-square, the motor pool's apron, the ground in front of a school door or a ladder, the workbench's set or a prop (`tests/test_build_homes.gd` lists everything a home must avoid against the map's own rectangles). The yard is not covered in signs: a home's hammer sign and dashed outline show only while the Build screen is open, for the one home the mouse is within about three tiles of, and for a home with a site on it (with the screen shut and the mouse far from every home there is none to be seen; `--build-plots` keeps them all lit for a screenshot). Press **N** (or the hammer in the toolbar, or click a home's sign in the yard) to open the **Build screen**: a short list of the buildings, each with what it costs, why it cannot be had now ("Can't: needs 30 scrap", "Can't: after the first one"), how far along it is or that it stands, and, for the one you pick, what it gives, its scrap and its builder-hours, where it goes (the home's name and why), and a small map of the yard with its pin (the chosen building's home is outlined in the yard too). **Build** pays the scrap at once and puts a **site** at the building's home; by day the **Builders** walk to the oldest site and build it (an hour of a builder's work counts for 1 plus 0.12 for each point of Building, less when they are hungry or shaken, so a good builder is worth two, and building teaches Building as mending walls does), a badly worn wall still comes first, and at night the crew holds the posts and the site waits. The page says who is building and about how long it will take at their pace, or that nobody is on the Builders job. **Cancel** gives all the scrap back if no work was done and half after; **Demolish** (two clicks) gives half of a building's scrap back and ends what it did. The game waits while the screen is open; pointing at a building's slip marks its home in the yard. A watchtower reaches from its own body (its shooters are those within four tiles of the tower, not of the middle of its lot). A save from before round 15 has what it had refunded (a site in full, a building by half): the old plots are no more. Seven buildings to begin with (their numbers are in `assets/data/buildings.json`): the **salvage bench** (opens the Salvage station: two more jobs that sort the yard's junk into scrap), **greenhouse beds** (two more gardeners and a little more food each dawn), the **workshop** (a third seat at the bench, quicker work, more ammo from each scrap), the **bunk house** (four beds for the hurt, better sleep, and room for four more people), **floodlights** (the guns reach further by night; a blackout costs no aim), the **watchtower** (on the wall: shooters near it reach three tiles further) and the **radio mast** (better news on the radio, fewer bad surprises). A game in which nothing is built plays as it always did; the first building that pays for itself is the salvage bench. With nine homes for seven buildings (two of them may stand twice), what goes up first is the decision, not where; the streets round the school (below) are the room for more, and for the one building made only for them, the **scrap yard** (a little scrap every dawn).

  **The streets round the school: lots, mouths and walls (a small start only).** The map is a block, the compound in a ring of streets that is closed by rows of buildings at the map's edge and open at **ten places where the dead come in**. In a small start the **Build screen** has a **Lots page** (the first slip, "Claim the streets", and the page it opens on while a lot can be claimed and none has been) with a card for each of the three **lots** of the ring (the north street with its six ways in, the west road and the east road with three each; the numbers are in `assets/data/lots.json`): what a claim costs (scrap, a day, and some places cleared on the Town Board, each condition on a pill that goes amber while it is not met) and a **Claim** button that is always there and, when it cannot be pressed, the reason written under it and in its tooltip. A claim opens the Main gate to people (the dead stay out of it) and puts the lot's **ring homes** (two in all, round 15: the scrap yard is the one building made for the streets and it may stand twice, the first on the grass verge by the north-east corner, in the north lot, the second on the west verge, in the west lot; the east lot has walls and no home) on the list under the lot's name. **Twelve walls are one decision, not twelve**: once a lot is claimed its card is a **standing order**, one switch, "Wall the streets as the scrap allows" (the keyboard and the mouse turn it; a click on its words does too). With it on, whenever nothing is going up, the day has begun and the stores have the price and five scrap to spare, the module orders the wall of the next open street by itself, the sturdiest kit for its price, and the Builders put it up; then the next one, a street after another, till the lot is sealed. The card says which street is next and what its wall costs ("Next: the west alley, 11 scrap"; "Waiting for scrap" when the stores are short; "Every street has its wall"), how many of the lot's walls stand and whether the lot is **sealed**. There is no kit to choose anywhere: a street's **mouth** has no slip in the list, it is a pin on the map, and the pin's card says which of the ten streets it is, where the dead of it come from, what else shuts it (two walls shut the wider ones), the state of the street (open, with the one wall the order would put there and a button to order it now; a wall going up and how far; a wall that stands and how well; a wall that is down) and whether the lot's order is on. The Builders put the wall up like a building (by day, a heap of materials along the street and a bar over it while it goes up); a wall that stands is a wall section like the old ones (health, four damage states drawn in the world, places for the dead, a night post for a shooter behind it, which the Duty roster lists under the lot's name) and its card shows its health and what it means ("Failing: one more bad night may break it"); a wall is not pulled down, and one that falls opens the street again (marked "wall down" in the world, always; the Builders mend it by day while there is scrap). **Shut every street and nothing in the ring is raided**: at the bell each building out in a claimed lot has a chance of being ruined, 6% with all ten streets open, less by the share that are shut, and none when they are all shut (the page says "n of 10 open: x% a night for each building out here"). A **map** under the cards (over the plot's card, for a plot) shows the yard, or the whole block once a lot is claimed (a toggle chooses), with the plots and mouths as pins that the mouse and the keyboard can have (Enter on a street's pin chooses it and goes to its card), a mouth's line amber while the street is open, gold as the wall goes up, green, amber or red by its health, and the spawn point of its dead ringed; pointing at a lot's card lights the whole lot in the world and on the map. In the world an open street is a dashed amber line across it with the words "open street", drawn while the Build screen is open or the mouse is within about five tiles of it. The first time a lot could be claimed a tip says so (anchored on the toolbar's Build button), and the classic start has none of it.
- **The school.** The dead cannot walk into the school while its two north doors hold. They go for the doors once the yard has fallen and a person is hiding inside; a door that is down opens the whole building to them. Falling back is a last stand with a clock, not a bunker.
- **The dead.** Walkers come from the first night. From night 4 some are **runners**: quick and frail, they cross the yard in a third of the time and give the crew little warning. From night 8 a **brute** comes among them: slow, huge, many shots to bring down, and it tears at a wall several times as hard as a walker. The guns shoot a brute first and a runner second. Each night is planned at dusk: most of the dead come from one or two spawn points, the later part of the night is where the brutes are.
- **The lookout.** At 17:00 (two hours before dusk, whatever the season) whoever is on the Lookout post, if they are up and about, reports what tonight looks like: about how many (give or take 15%), from which way, and whether a brute or runners are among them. Without anyone on the post nobody tells the crew.
- **Fields of fire (V).** The shooters stand at their night posts (you choose them on the Jobs screen), and a wall section is only defended if their guns reach it. The view shows each section's cover; people on the walkways and towers can be scratched far less often than people on the ground.
- **The alarm (L).** Select a wall section and set the alarm: it costs 3 scrap, rings for three game hours, and draws the dead already on their way to that section, where the guns are. One alarm at a time; not on the school doors.
- **People.** Each survivor has two traits (Steady, Nervous, Tinkerer, Triage, Sharp-eyed, Steady hands, Tough, Optimist, Loyal, Quick learner), bonds with some of the others (family, mentor, friend), a mood and skills that grow with use. The person panel shows all of it; the mood's tooltip lists every reason with its sign. Mood runs from Inspired through Steady and Shaken to Breaking (a shaken person works and aims a little worse); someone who breaks down stops shooting and cannot be ordered for an hour (from day 4, not on Story). A loss hurts the ones who knew them most. Shooting, Melee, Medicine and Building each gain a point with enough use, at most three over where they started. People speak up when something happens (the bell, a wound, a friend down) and the others say a few words when one is lost.
- **The radio hour.** At noon whoever is at the Radio desk (Ruth to begin with) has news on the radio: about two days in three there is a card (never on the first day or the last). Fifteen cards: heavy rain, fog, a blackout that Dez must mend, a horde warning, stragglers at the wall by day, a fever, supplies falling from the sky, a stranger at the gate, a cry for help, a trade offer, an argument... A card with a choice waits for you and states its risk plainly; if nobody answers within two game hours its default is taken. A hidden tension leans the draw: after a bad stretch the radio is kinder. The morning after each night an assembly card says how many were put down and by whom, what the wall lost and gained, who was lost (and what the others said), what was learned and how the crew is.
- **A small start, and recruits over the radio.** A new game begins with three survivors, Ruth, Dez and Marcus (**Small crew (3)** on the New game screen, the choice it opens on; **Full crew (6)** begins with all six, as the game always was). The others call in over the radio. From day 2, at the noon radio hour, if someone is at the Radio desk and the compound has a bed free, a caller can come through: the card **A voice on the radio** asks you to **tell them the way in** (they reach the gate at 07:00 next morning and join the crew, with a bell, a banner and a new card in the crew bar) or say **Not yet** (they call again in two days). The first three callers are Ana, Walt and Hector; after them the callers are strangers (a name, a trade, skills, two traits, a weapon), eight at the most in a run. What caps the crew is **beds**: the school has six and each **bunk house** adds four (the Build screen's foot says how many the compound has beds for); with none free no call comes, and a call that was already on the table cannot be answered with the way in ("No bed for them"). A call comes every three days at the most (two with a **radio mast**). A newcomer may be **bitten**: they arrive bleeding and the infection rules take over, so the gate has a decision in it (treat them with **T**, or send them out with **X**). In a small start the nights follow the size of the crew: three people face about 60% of the night that six face, and a bigger crew a bigger night (at most 1.6 times). The crew bar fits a crew of fourteen (the cards shrink and then wrap into rows). A run chosen with **Full crew (6)**, Orientation Day and a save from before this round play as they always did; a save keeps who has come, who is on the way and who is still to call.
- **Orientation Day.** A guided first run (about ten minutes, a Story game that cannot be lost): seventeen short steps teach selecting and moving, posts on the decks, repairs, the stores, a scavenging trip, the bell, shooting, the fields-of-fire view and the alarm, wounds and fever, saving, making ammo and the duty roster. Offered on the first launch; replay it from the title screen. After that a few one-line tips show once each in real runs (first dusk, low stores, the first wound, the first runner and brute, the day the crew can first afford to build, and the Town Board in a small start); switch them off in Settings.
- **Menus and settings.** The title screen offers Continue (the newest save), New game (difficulty, crew, length and seed), Orientation Day, Load, Settings and Credits; **Esc** with nothing selected opens the pause menu, and so does the menu button next to the sound button. Settings keep five volumes (master, effects, ambience, music, interface), the interface size, hints, reduced motion and fullscreen in `user://prefs.cfg`.
- **The goal.** Hold thirty nights. Night 30 is the Big Night: more than twice the usual number of the dead, a third of them runners and brutes, coming from everywhere. At the dawn that starts day 31 a convoy is on the road and the run is won.

  The **Campaign** length goes on from there through Winter, Spring and Summer (see Seasons and the campaign below); each season ends with its own Big Night.
- **Save and load.** **F5** saves, **F9** loads; the game also autosaves at each dawn. When everyone is gone the game over screen offers a new game.

## Seasons and the campaign

A new game has two lengths, chosen on the New game screen under **Length** (the choice is remembered, like the crew's): **Autumn: thirty nights**, the game as it has always been, and **Campaign: the four seasons**, Autumn, Winter, Spring and Summer in turn (102 days), each with its own rules and its own Big Night. Either start (small crew or full) plays either length.

- **The Big Night is the last night of every season** (night 30, then 54, 78 and 102), and the season turns at the dawn after it: the banner says "Winter begins" and gives the season's line, a deep bell rings, and a one-line tip about the season comes once (not in a game that is not a campaign). Surviving the last season's Big Night wins ("The seasons are over"); a defeat says which season it came in ("You fell in Winter, on day 41"). A season's nights are sized as if the game were older: each season gone makes the nights six days older, and the season's own factor for the nights is on top.
- **What each season changes** (the numbers are in `assets/data/seasons.json`; Autumn repeats the old constants, and a game that is not a campaign is Autumn for ever). The hours are the real clock's: the bell rings at dusk, the night runs from an hour and a half after it until an hour before the day. The beds' yield, what a person eats and drinks, the road's hours on the Town Board and the size of the nights are multipliers of the Autumn game, and the Big Night's factor is over its day's budget:

| Season | Days | Dusk | Day | Beds (garden) | Food / water used | Roads (travel hours) | Nights | Big Night | Weather and cold |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Autumn | 30 | 19:00 | 6:30 | x1 | x1 / x1 | x1 | x1 | x2.4 | 33% rain (0% of it snow), 7 to 17 C |
| Winter | 24 | 16:30 | 7:30 | x0.15 | x1.15 / x0.9 | x1.3 | x1.15 | x2.6 | 40% rain (70% of it snow), -5 to 3 C |
| Spring | 24 | 19:30 | 6:00 | x0.8 | x1 / x0.9 | x1 | x1.2 | x2.8 | 55% rain (0% of it snow), 4 to 14 C |
| Summer | 24 | 21:00 | 5:30 | x1.3 | x1 / x1.3 | x0.9 | x1.1 | x3 | 12% rain (0% of it snow), 18 to 30 C |

- **What you see.** The clock says the season and the day in it ("WINTER, DAY 5 OF 24"; the short form "WINTER 5/24" in a narrow window and while paused), counts to the season's dusk and day, draws its strip with them, and gives the season's temperature and the weather ("-4C, snow"). The light is mapped to the season's day (Winter's dusk falls at 16:30, Summer's at 21:00) and tinted: Winter cold and blue, Spring a little green, Summer warm; Autumn is as it was. On a snow day (Winter only) soft flakes drift down and sideways, slowly, and the ground wears a light white cover that is lighter on the other Winter days. All of it is drawn in code, no art; under reduced motion the flakes fall at a third of the pace and do not sway.
- **Saves** keep the season and the day it began on; a save from before the campaign loads as Autumn.

## How it fits together

- `scripts/main.gd`: builds everything at startup, then runs the camera,
  input, the event→sound/HUD wiring and the frame loop.
- `scripts/world.gd`: the static map. The ground is a `TileMapLayer`; props,
  vehicles, wall pieces and roofs are sprites in draw order. It also owns the
  walkability grids.
- `scripts/sim/`: the simulation. `sim.gd` holds the clock, people, walkers,
  combat and wall damage; its modules are `waves.gd` (tonight's plan and the dead
  who come), `kinds.gd` (walker, runner, brute), `tactics.gd` (the alarm, the Builders' repairs,
  coverage and the lookout's forecast), supplies, medical, scavenge and scenario.
  `pathfinder.gd` wraps `AStarGrid2D` and smooths paths.
  `step_clock.gd` hands out whole 1/30 s steps, so the rules run at 30 Hz at any
  frame rate and a seed plays the same game everywhere; the drawing interpolates.
- `scripts/render/`: drawing.
  - `pawn_node.gd` draws one person, walker, runner or brute (y-sorted).
  - `pawn_art.gd` has the live legs, arms and hands, and the build of each kind of the dead (size, lean, tint).
  - `fire_node.gd` draws flames.
  - `fx.gd` handles effects.
  - `lighting.gd` covers the day/night sky (`CanvasModulate`) and every lamp (`PointLight2D`); in a campaign it maps the hour to the season's day and tints the sky with the season's tint.
  - `snow.gd` draws the snow: flakes on the screen on a snow day and the white cover over the outdoor ground.
  - `glow_node.gd` draws additive glows.
  - `overlay_node.gd` draws the names, bars and brackets, the fields-of-fire view and the alarm's marker.
- `scripts/ui/hud.gd`: the HUD, built from Controls; `scavenge_dialog.gd` and `game_over.gd` are its modals (in a small start the Town Board, `town_board.gd` with the paper map of `town_map.gd`, takes the dialog's place). Their surfaces come from `frames.gd` (nine-slice frames in `assets/ui/theme`).
- `scripts/ui/shell.gd` and its siblings (`title_menu.gd`, `pause_menu.gd`, `settings_menu.gd`, `new_game_menu.gd`, `load_menu.gd`, `credits.gd`): the title screen and the menus. `scripts/prefs.gd` keeps the settings in `user://prefs.cfg`.
- `scripts/render/parking_node.gd`, `scripts/ui/town_board.gd` (the ride row of the party picker), `scripts/ui/town_map.gd` (the map fitted to what is known, the river, the bridge and the city's icons) and the Fuel line of `hud.gd` (round 13, the view of vehicles and fuel; the rules are `scripts/sim/vehicles.gd` and the vehicle parameter of `scavenge.gd`, the kinds `assets/data/vehicles.json`): the fleet's vehicles are drawn there, in a settlement game only (round 15: `parking_node.gd` keeps one `scripts/render/vehicle_actor.gd` for each vehicle: parked in the motor pool, the doors swinging while people get in and out, driving the route through the gate and away, all a pure function of the saved state; it also says what the gate wants, `gate_demand()`). `tools/make_fuel_icon.py` draws the pump and the car of the stores and the alerts.
- `scripts/ui/coach.gd`, `scripts/sim/orientation.gd`, `assets/data/tutorial.json`, `assets/data/hints.json`: Orientation Day (a scripted scenario and the coach overlay) and the one-line tips.
- `scripts/sim/jobs.gd` (data in `assets/data/{stations,posts}.json`): jobs and stations (who works where, the seats, the settings, the night posts, Auto-assign). The stations do their work in the modules that own it: `workshop.gd` (scrap into ammo at the worktable), `tactics.gd` (the Builders' repairs and the lookout's forecast), `supplies.gd` (the beds), `medical.gd` (the infirmary), `storyteller.gd` (the radio desk). `scripts/ui/jobs_screen.gd` is the Jobs screen.
- `scripts/ui/build_screen.gd`: the Build screen (key N): a short list of the buildings (each has its own home: `sim.build.home_for`), what each costs and gives, Build, sites, cancel and demolish, with a small map of the yard. It reads and changes the buildings module (`sim.build`), is opened by `hud.open_build` (which pauses the rules like the Jobs screen) and hands the plot under the pointer to the yard through `main.build_hover`. `tools/make_build_icon.py` draws its hammer. In a settlement game (round 9) it also has the Lots page (`scripts/ui/build_lots.gd`: a card for each lot, and for a claimed one the standing-order switch, `lots.set_auto_walling`) and the map of the block (`scripts/ui/build_map.gd`), reads the lots module (`sim.lots`, `scripts/sim/lots.gd`: claims, mouths, the walls of the kits, the standing order, raids; data in `assets/data/lots.json`), and `scripts/render/build_node.gd` draws the plots' signs and outlines (only when the screen is open, a site is up or the pointer is near: `NEAR_PLOT`, `NEAR_STREET`) and marks the open streets in the world.
- `scripts/sim/{skills,traits,bonds,morale,barks}.gd` (data in `assets/data/{traits,barks}.json`): the people. `scripts/sim/storyteller.gd` and `assets/data/events.json`: the radio hour, the cards and the morning assembly; `scripts/ui/{radio_card,dawn_card,story_ui}.gd` show them.
- `scripts/audio/sound.gd`: one-shot sounds and the ambience loops. `scripts/audio/music.gd`: the four music loops (`assets/audio/music_*.wav`, made by `tools/make_music.py` from arithmetic alone: a placeholder score in A minor) that cross-fade between the title, the day, the night, a played trip and the dead at the wall; the Music volume in Settings is theirs.

## Art and sound

The files in `assets/` are the source art. Edit or replace them directly; a
replacement PNG at the same size drops straight in.

- `assets/objects`, `walls`, `terrain`: props, the school walls, ground textures.
- `scripts/render/deck_faces.gd`: draws what makes the walkways and towers look raised: the scaffold face under the planks, the tower bases, the supports along the side walkways, the shadows and the ladders (their sizes are constants at the top of the file). The pieces it draws are `assets/objects/deck_*.png`, made by `tools/make_deck_art.py` (Python with Pillow and NumPy) from three reference pictures in `tools/art_src/` (a scaffold front, a tower base and a ladder, made with Meshy and kept so the pieces can be rebuilt). The walkways can only be climbed at the ladders; `world.gd` shuts the tiles under the face for people and for the dead.
- `assets/pawns`, `portraits`, `weapons`, `trees`, `fx`: characters and effects.
- `assets/ui/icons`: HUD icons. `assets/ui/theme`: the noticeboard frames, built by `tools/make_ui_theme.py` from Meshy material pictures kept in `tools/ui_src/` (`docs/assets-log.md` records every AI-made picture).
- `assets/audio`: sound effects and ambience loops; the UI sounds (`ui_*.wav`) are synthesised by `tools/make_ui_sounds.py`.
- `assets/data/map.json`: the map layout, lights, wall segments and roster.

They were generated once from the original web prototype, which has since
been removed. Godot is the only version now.

## Publishing (itch.io)

The game is on itch.io at <https://jafforge.itch.io/last-bell>. The page is
**Restricted**: only you can see it, and it is unlisted. To show it to someone,
go to Edit game → Distribute → Download keys and create a key. The key's link
gives them access.

To publish an update:

1. Export the web build from the command line:

   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "Web" build/web/index.html
   ```

   Or use Project → Export → Web in the editor.
2. Zip the contents of `build/web` so that `index.html` is at the root of the zip.
3. On the itch.io edit page, replace the zip. Keep "This file will be played in
   the browser" ticked.

`build/` is ignored by Godot and git. The cover image and screenshots used on
the page are in `build/itch-page/`.

## Automated checks

`main.gd` accepts user arguments after `--`. They let you take a screenshot of a
given moment without touching the game:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --shot=/tmp/night.png --hour=21 --advance=25 --cam=39,19,40
```

| Flag | Effect |
| --- | --- |
| `--hour` | Set the time of day |
| `--advance` | Simulate N seconds first |
| `--cam=x,y,zoom` | Place the camera (tiles, px per tile) |
| `--select=ruth` | Select a person (`--select=ruth+dez+ana` a group, Ruth the main pick) |
| `--box=x0,y0,x1,y1` | Show a selection box being dragged over that part of the yard (tiles; after `--cam`) |
| `--title` | Show the title screen |
| `--menu=pause` | Open a menu (`pause`, `settings`, `new`, `load`, `credits`, `confirm`, `orientation`) |
| `--prefs=path` | Keep the settings in another file (so a screenshot run does not touch yours) |
| `--tutorial[=N]` | Start Orientation Day (at step N) |
| `--card=id` | Show a radio card (see `assets/data/events.json`) |
| `--weather=fog` | Start with fog (or `rain`, `clear`, and `snow` in a campaign: flakes and a white ground) |
| `--blackout` | Start in a blackout |
| `--dawn` | Show the morning assembly |
| `--wall=N` | Select wall section N |
| `--fields` | Start with the fields-of-fire view on |
| `--jobs` | Open the Jobs screen |
| `--jobs-hover=station:bench` | Open it with a place marked in the yard (`station:ID`, `post:ID` or `person:ID`) |
| `--build-plots` | Keep every plot's sign and outline lit in the yard, as when the Build screen is open (they are otherwise drawn only near the mouse, or on a plot with a site) |
| `--build-pointer=x,y` | Put the mouse at that point of the yard, in tiles (`30,34`): the plot nearest it shows its sign and an open street within five tiles its line and words (a screenshot has no mouse) |
| `--build[=plot]` | Open the Build screen (on that building's home, e.g. `--build=workshop_home`), once the other flags are in |
| `--build-site=plot:building[:share]` | Put sites up, comma-separated, with a share done from 0 to 1 (nothing is paid); `--build-built=plot:building` stands buildings at once |
| `--build-scrap=N` | Set the scrap in the stores (to show what cannot be ordered) |
| `--build-nobody` | Take everyone off the Builders job |
| `--town[=place]` | With `--crew=3`: open the Town Board (on that place), once the other flags are in; `--town-reveal=id,id` (or `all`) shows places that are hidden at the start, `--town-state=id:cleared` (or `:claimed[:person+person]`) stages them, `--town-send=person+person:place:loot[:vehicle]` sends a party at once (in that vehicle, when one is named and in the fleet), `--town-focus=id` puts the keyboard on a pin |
| `--vehicle=sedan,bus:30` | With `--crew=3`: put these vehicles in the colony's fleet, parked at the gate (the kinds of `assets/data/vehicles.json`: `sedan`, `pickup`, `van`, `bus`; `:30` is the share of its condition left, to show a worn one); `--fuel=N` fills the tank; `--town-ride=sedan` chooses that vehicle in the party picker when the board opens. Put them before `--town-send` |
| `--lots[=north,west]` | With `--crew=3`: claim the lots of the ring at once (all of them without a list; the day, the places cleared and the scrap are made up, nothing is paid). Put it before `--build-built` (the ring plots) and `--damage` or `--breach` (the walls: the first wall of the lots is section 16) |
| `--walls[=N]` | With `--crew=3`: stand a wall at N of the mouths (all twelve without N), the lots claimed, with the first kit that fits, or `--wall-kit=container_n` where that one fits |
| `--walling[=north,west]` | With `--crew=3`: switch the standing order on for those of the claimed lots (all of them without a list); put it after `--lots` |
| `--wall-site=mouth[:share]` | With `--crew=3`: put a half-built wall at a mouth (`west_road_top`; the share done from 0 to 1, half by default), its lot claimed |
| `--raid=place[,seed[,vehicle]]` | Open a played trip at once with the first three people (`--crew=3`), at a place of the Town Board by its id (`pharmacy`) or the first of a kind (`bakery`), its site made from the seed (else the run's, the place's and the day's), in a vehicle of that kind (`van`) when one is named |
| `--raid-do=steps` | Play it a little first, steps joined by `+`: `all`, `one`, `sel:N`, `search:N` (a container by its index, or `near`), `move:X:Y`, `help:N`, `down:N`, `wait:SECONDS`, `follow`, `cam:X:Y[:ZOOM]`, `pause`, `ask`, `retreat`, `end` (to the end card) |
| `--raid-stub` | Use the stand-in site (scripts/raid/stub_site.gd) in place of the generator |
| `--lure=N` | Set the alarm on wall section N (gives scrap if needed) |
| `--breach=N` | Break wall segment N |
| `--damage=N:F` | Leave wall segment N at the fraction F of its health |
| `--new=D` | Start a new run at difficulty D (0 story, 1 standard, 2 brutal); on its own it is the classic six, add `--crew=3` for the small start |
| `--campaign` | Play the long game of four seasons (without it a run is Autumn's thirty nights). Add `--crew=3` for the small start |
| `--season=N` | Begin a campaign in season N (0 Autumn, 1 Winter, 2 Spring, 3 Summer, or its name) at the first morning of that season, a little after its dawn. It implies `--campaign`; `--hour` and `--advance` then move the clock, and `--weather=snow` makes a snow day. Meant for screenshots |
| `--crew=3` | Start with the small crew (Ruth, Dez and Marcus; the others call in over the radio). `--crew=6` (or `full`, or no flag) is all six: a screenshot or a test is the classic six unless this is given |
| `--recruit[=id]` | With `--crew=3`: let a caller of the radio in at the gate now (`ana`, `walt`, `hector`, or the id of a generated one; with no name, the next in the queue), and the banner, the sound and the new card with it. It is 07:00 unless `--hour` came before it. Give it more than once for a bigger crew |
| `--seed=N` | The seed of the new run (the same seed plays the same game) |
| `--load=path` | Load a save (a file path, or `user://quicksave.json`) |
| `--selftest` | Drive the real input handlers once |
| `--frames` | Frames to wait before the shot |

The run prints average fps.

## Saving

F5 saves to `user://quicksave.json` and F9 loads it. The game also saves to
`user://autosave.json` at each dawn (not in screenshot runs). A save is JSON and
holds the whole state of the rules, so a loaded game carries on the way the
saved one would have. A save that cannot be loaded (damaged, or from another
version) is refused and the game carries on.

## Balance harness

`tools/balance.gd` plays whole games without a window, with a sensible default
policy (repair the worn walls by day, send the best shooters scavenging when a
stock runs low, treat the infected), and prints one row per game and the average
colony day by day:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/balance.gd -- --games=8 --days=10 --difficulty=1 --seed=1 [--fast] [--jobs=4] [--out=result.json]
```

`--fast` steps the rules at 15 Hz instead of 30, `--jobs=N` plays N games at a
time in worker processes, `--policy=none` gives no orders, `--policy=keep` hides the
crew in the school gym from the bell to dawn (the check that hiding does not beat
defending), `--policy=informed` plays the default policy and also reads the plan:
it stands the shooters where their guns cover the thinnest section and sets the alarm
(the check that knowing the night pays), `--sites=path` reads the scavenging sites from another file (to try a site before it is in the game), `--nostory` plays with the storyteller off (to see what the radio changes), `--verbose` lists what the policy did and who was lost; see the top of
the file for the rest. A game
whose colony collapses is slow to play (the walkers inside the yard re-path
every second).

## Tests

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run.gd [-- --only=text]
```

Every `tests/test_*.gd` file is run; a test fails if it fails a check or logs an error. `tests/helpers.gd` builds a headless game for tests.
