# Thirty Bells: one survivor, a living community and a radio (design, draft for the owner's review)

> Written 2026-10-03 from a brainstorm with the owner (the thread and every decision are in `docs/superpowers/brainstorm-avatar-and-radio.md`). **Nothing here is built or planned in detail yet.** It changes how the game is played, not what it is: a colony-defence game about thirty nights in a schoolyard.

## 1. The game in one paragraph

You play **one survivor** from the top down: WASD to move, the mouse to aim and shoot. Around you a **community of about 8 to 20 people lives on its own**: they work their jobs, eat, sleep, form friendships, have ideas, and defend the walls at night. You reach them through a **radio panel**, and you ask, you do not command. You walk the base for hands-on things and you leave it for **places** (a pharmacy, a farm, a warehouse), taking people who agree to come, driving between the places. While you are away **the base keeps running in step with you** and the radio calls with news and decisions. If you die, the next in line takes over; the run ends only if the community falls.

## 2. Principles

1. **You are one of the squad, never a one-man army.** Combat is never one gunner against a horde. The other survivors fight too, by themselves, with their own AI; the nights are tuned for a community that defends itself. Your aimed fire, your position and your leadership are worth a lot but do not carry a night alone.
2. **The community is a set of people, not tools.** A request can be refused only for a clear, visible reason (hurt, starving, terrified, busy with something critical), shown in the panel. Trust in you sets how willingly and how fast they answer. Nothing is random.
3. **The base is alive without you.** Ordinary nights it holds if its posts are staffed and its walls decent. The Big Nights and the breaches (a brute, a section falling) need you in the right place.
4. **Going out is the centre of the game,** and what only you can do is: go beyond the walls, lead and recruit, fight with real aim, drive.

## 3. Decisions (all from the owner)

| # | Decision |
|---|---|
| 1 | Only the player can go beyond the walls, lead and recruit, fight with real aim, and drive. Colonists stay in unless asked along or sent on an errand. |
| 2 | An errand without the player (a delegated trip) works but does worse than one the player leads: less loot, more losses, no rescues. |
| 3 | Death: the next in line takes over (most trusted, or best at Leading); the old character is gone; a setback follows (a trust drop, a mourning day, carried gear lost); the run ends only if the community falls. |
| 4 | Going out: places are generated scenes (as the played trip is now); between them a short live drive or walk where things can happen (an ambush, a roadblock, someone flagging you down). |
| 5 | At home: the avatar walks the base (talk to someone, take a post, use the workbench) and the radio panel is the colony's interface (jobs, build requests, the alarm, the map). |
| 6 | Time: the base runs in step with the player. Time in a place passes like game time, so a trip of an hour or two is a few real minutes. The radio brings news and decisions; the alarm can be raised from anywhere. |
| 7 | Requests, not commands; refusal only for a visible reason; trust sets willingness and speed. |
| 8 | Nights: ordinary nights are held by the community; the Big Nights and breaches need the player. The forecast and the alarm become tools. |
| 9 | The community does things on its own: it proposes ideas over the radio ("I could fix the east wall for 20 scrap"), forms relationships, and develops specialists. (Self-directed work, crises and growth come later.) |
| 10 | **Box select is removed.** With one avatar it has no purpose; WASD and the mouse belong to the avatar. |
| 11 | **The Town Board is not kept as it is:** it becomes an overview, the map the radio panel opens (known places, roads, nests, outposts), from which the player chooses where to go and who to ask. |
| 12 | Other survivors defend autonomously: combat is never one gunner against a horde. |

## 4. What stays, what changes, what goes

- **Stays (the engine):** the simulation (supplies, wounds, waves, jobs and stations, morale, traits, bonds, skills, build with homes, lots, seasons, vehicles and fuel, the motor pool and the gate, the storyteller, recruits, saves), the generated places (`scripts/raid/site_gen.gd`), the vehicle and gate animations, the work animations, the music and sounds, the harness.
- **Changes:** the player's input (the avatar); the **played trip becomes the main way to scavenge** (the dice trips become delegated errands); the **colony UI moves into the radio panel** (the Duty roster, the Build screen, the Town Board's map and trips become pages of it); the played trip no longer pauses the colony; the nights are tuned to a self-defending community.
- **Goes:** box select and group orders (`selected_people`, the strip, `--box`), WASD and middle-drag camera panning (the camera follows the avatar), the Town Board as a separate screen.

## 5. The radio panel (v1 sketch)

A panel in the corner you can open anywhere. A list of **contacts** (portrait, name, what they are doing, where, a trust mark), and for the selected contact a few **verbs**: *come with me*, *hold here*, *cover me*, *search that*, *go back*, *wait at the car*, *to the walls* (and for the whole base: *alarm*, *stand down*). The answer comes at once as a line ("Dez: on my way" or "Ana: tending a patient, can't come") and a delay by trust and distance. Pages: **Jobs** (the Duty roster), **Build**, **Map** (the overview), **News** (the radio calls and the decisions waiting).

## 6. Slice 1: be one survivor on a trip (the first thing to build)

- **The avatar** in the played-trip scenes: WASD movement with collision, mouse aim, shoot, reload, melee, an aimed-fire feel (recoil, hit feedback, the existing guns and ammo); `Person.player` marks the controlled person; the rest keep their AI.
- **The squad** (the people who agreed to come) moves and fights on its own: *follow*, *hold*, *cover me*, *search that*, *go back*, with line-of-sight targeting (the raid code has it).
- **The radio panel v1** with the contacts and verbs above, and the willingness rules (visible refusals, trust).
- **The base runs while you are out:** the colony simulation continues at the trip's pace; three kinds of radio call (an attack, a sickness, a stranger at the gate) with a decision each; the alarm from anywhere.
- **Succession on death.**
- **Removed in this slice:** box select and the yard's WASD pan.
- **Acceptance:** a trip is playable end to end by the avatar with a squad of two or three who follow, hold and cover by the radio; a refusal shows its reason; the base keeps living (a night passes while you are out and the calls come); dying hands the game to the next in line; the suite and the harness stay green (the harness plays the delegated errands, as it does now).

## 7. Slices after it (rough order)

2. **Home:** walking the base; the radio panel as the colony interface; refusal and trust everywhere.
3. **Nights:** the community holds ordinary nights; breaches and Big Nights need the player; forecast and alarm as tools.
4. **A community with ideas:** initiative proposals, relationships, specialisation.
5. **The live drive** between places, with events.

## 8. Risks and what we do about them

- **The squad's AI is the heart.** If followers are dumb the whole game is a chore. Slice 1 starts with a small, reliable set of behaviours and a test per behaviour, and the squad auto-fires at what it sees (as the raid does today).
- **Balance moves.** The waves are tuned for crews that auto-fire from posts. They stay that way (decision 12); the avatar adds a strong, mobile shooter and a leader, and the harness bot, which will not play the avatar, keeps measuring the community.
- **Time scale.** A place's game minutes against real time must feel right (searching an hour of game time in a few real minutes) and the base must keep pace; the exact factor is set in the plan and tuned by playing.
- **The pivot's size.** Slice 1 is about two big rounds. Every later slice is a round or two. The current game stays playable until slice 1 lands.
- **A third pivot.** The owner has dropped an outpost game and a 3D game before. This one keeps nearly all the code; if slice 1 is not fun the colony game is still there.

## 9. Not decided yet

- The look of the radio panel (a drawn radio set or a clean list?), and its exact verbs.
- The size of the difference between a trip you lead and a delegated errand.
- How a survivor becomes "the next in line" and how trust is earned (the plan sets numbers).
- Whether the avatar has its own look or is always one of the named survivors (the sketch assumes a named survivor).
