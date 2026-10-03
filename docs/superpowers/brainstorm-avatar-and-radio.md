# Brainstorm: one playable survivor and a community that lives on its own (2026-10-03)

> Not a spec and not agreed work: a thread of decisions from a conversation with the owner, kept so a new session can pick it up. Nothing here is built.

## The idea (the owner's words, tidied)

The player controls **one character** from the top down (WASD to move, mouse to aim and shoot). The rest of the **community works, defends and changes by itself**. The player reaches them through a **radio panel**: asking someone to come along on a trip, asking people to defend the walls (an alarm), and so on. It is partial control: the player influences the community more than commands it.

## Decided so far

1. **What only the player can do:** go beyond the walls, lead and recruit, fight with real aim, drive. Colonists stay inside the walls unless asked to come along or sent on an errand.
2. **Errands without the player** exist (the Town Board's trips, by dice) but do worse than a trip the player leads: less loot, more losses, no rescues.
3. **Death (option 2 of three):** the next in line takes over (the person the community trusts most, or the best at Leading); the old character is gone; a setback follows (a trust drop, a mourning day, the carried gear lost); the run ends only if the community falls.
4. **Going out (option 3 of three, the hybrid):** places stay separate generated scenes (as the played trip is now); the travel between them is a short live drive or walk where things can happen (an ambush, a roadblock, a survivor flagging the player down); the base keeps running while the player is out.
5. **Radio = requests, not commands** (confirmed by 8): a person may agree, grumble or refuse by mood, trust, injuries and what they are doing; trust in the player is a resource. The alarm is a call to arms.
6. **At home (option 3 of three, both):** the avatar walks the base for hands-on things (talk to someone, take a post, use the workbench) and the **radio panel is the colony's interface**: jobs, build requests, the alarm, the map. Nobody has to walk across the yard to give an order.
7. **Time (option 2 of three):** the base runs in step with the player. Time in a place passes like game time (searching and walking cost game minutes), so a trip of an hour or two is a few real minutes, and the base keeps living meanwhile. The radio calls the player with news and decisions ("wall breach at the north", "someone is sick", "a stranger at the gate"); the player answers or the community copes alone. The alarm can be raised from anywhere.
8. **Can they say no? (option 3 of three):** a person refuses only for a clear, visible reason (hurt, starving, terrified, busy with something critical), and the radio panel says why ("Ana: tending a patient, can't come"). Trust decides how willingly and how fast they answer: a trusted friend drops everything, a doubtful one grumbles and takes longer. Nothing is random. A possible "because I'm asking" button gets the favour at a cost to trust.
9. **Nights (option 3 of three):** ordinary nights the community holds alone if its posts are staffed and its walls are decent; the Big Nights and the breaches (brutes, a section falling) need the player in the right place. The player answers the radio call "the north wall is going", and is not the one who must hold every night. The forecast and the alarm become real tools (stay home on purpose, or drive back in time).
10. **What the community does on its own (1, 2 and 3 of six):** *initiative* (someone proposes something over the radio: "I could fix the east wall properly for 20 scrap", "the garden could feed two more"; the player says yes or no), *relationships* (friendships, rivalries, couples, someone emerging as the person others trust; this feeds the trust and refusal rules), *specialisation* (people get good at what they do and become the one to call: the best medic, the engineer, the scout). Left for later: self-directed work, crises and change, growth.
11. **Box select is removed** (no purpose with one avatar); WASD and the mouse belong to the avatar. **The Town Board becomes an overview** (the map the radio panel opens), not a separate screen.
12. **Combat is never one gunner against a horde:** the other survivors defend too, autonomously; the nights are tuned for a community that defends itself.

## What the code already has that this would use

- The community's brain: jobs and stations (`scripts/sim/jobs.gd`), night posts, morale, bonds, the storyteller, the radio hour and its calls, recruits.
- The played trip (`scripts/raid/`): a generated map of a place, squad control, line of sight, a result that goes back to the colony.
- Vehicles, fuel, the motor pool and the gate; the Town Board's trips by dice; the alarm (L).

## What it would need (rough)

- A player avatar: movement, aimed fire, reload, melee, camera follow; a way for a Person to be player-controlled while the rest keep their AI.
- A combat model for one gunner against hordes (the waves are tuned for auto-fire crews).
- Autonomy good enough that the base can be left alone for a day.
- A radio panel: contacts with status, a handful of verbs, willingness rules.
- The base running while the player is out (the played trip today pauses the colony).
- Succession on death.

## Open questions (one at a time)

- How does the player's presence change an errand (the size of the difference)?
- What does the radio panel look like, and how many verbs?

## A proposed order of work (not agreed)

- **A. Be one survivor on a trip.** WASD, mouse aim, shoot, reload, melee in the played-trip scenes (the raid code); a radio panel v1 with about six verbs for the squad (follow, hold, cover me, search that, go back, wait at the car); the squad's AI follows and fights; the base runs in step with the trip with three kinds of radio call; death passes the player to the next in line. This proves the fun.
- **B. Home.** Walking the base; the radio panel becomes the colony interface (jobs, build requests, the alarm, the map); the refusal and trust rules.
- **C. Nights.** The community holds ordinary nights alone; breaches and Big Nights need the player; the forecast and the alarm as tools.
- **D. A community with ideas.** Initiative proposals, relationships, specialisation.
- **E. The live drive** between places, with events.

Still to decide: what happens to box select and the Town Board (kept as overview tools, or retired); the look of the radio panel; the combat feel of one gunner.
