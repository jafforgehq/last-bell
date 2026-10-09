# itch.io page draft (NOT published; the live page still has the old prototype's text)

Status: draft written 2026-10-07 (the owner chose the name Last Bell the same day) for the owner to approve; text and screenshot list brought up to date on 2026-10-09 (PH4). The name is decided (Last Bell). What still blocks publishing is the owner's approval of the text and the screenshots. The six clean stills and the GIF exist (list at the end; made with `--stock`, `--hide-lesson`, `--no-banner` and `--no-alerts`, so no 9741-scrap counter, "Step 5 of 5", stuck banner or "Seven things built" alert is left on them). The page is Restricted with a password: nothing here changes that, and nothing has been uploaded.

## Title
Last Bell

## Short description (one line, under 100 characters)
Hold one house against the dead. A dark, top-down survival and defence game.

## Description

You are Ruth. It is seven in the morning, the bell is ringing somewhere, and you are alone at the edge of a dead town with a pump shotgun and a handful of shells.

Find a house. Clear every room, search it, and claim it. Then talk to the voices on the radio: the people who answer will come and help, if you put down the dead between you and them. When two of them are home the dead start to come every night, and they come to the bell. Fence the house, hang floodlights, build a watchtower, and hold until dawn.

**This is a demo (about 20 to 30 minutes).** It covers the first day or two and your first attack night. The town is generated for each run: **a different town for every seed**, and the same number is the same town again.

**What you do**
- Clear a house room by room, search it, and claim it as your base.
- Search the street too: **parked cars hold loot** (a few have nothing), and your people search them on their own when you send them out.
- Rescue survivors over the radio; they take jobs (builders, lookouts, scavengers, the radio desk) and answer when you ask. At night the crew **patrols the fence by itself** and shoots what comes.
- Build the base: front fence, gate, watchtower, side and back fences, floodlights, planks on the doors.
- Hold the first night. **The dead start to come after your second rescue.** There is a day and a night, and rain, storms and lightning are part of the weather: they can fall on the night itself, and a storm hides the small sounds.

**Controls**
- W A S D move, X run, right mouse aim, left mouse fire, R reload, F swing the gun's butt
- E use (search, claim, build, talk, sleep, treat), Q put the weapon away
- T radio, M map, N build page, . (full stop) wait for the bell, Esc menu
- Hold E in a cleared room to search it all. Press E at a fence site and stay by it to build it yourself.

**Tips**
- The Settings page has a Brightness slider (the game is meant to be dark), reduce motion and reduce flashes switches, colour-blind markers and text size.
- The game needs a keyboard and mouse. Desktop browsers only; Chrome, Edge and Firefox are the ones tested. F11 for full screen.
- The first load downloads about 80 MB. After that it starts in a few seconds.

**Feedback wanted.** This is an early build for a small group of testers. Tell me what was confusing, what felt slow, and where you died.

Built with Godot 4.7.

## Tags (itch allows up to 10)
zombies, survival, top-down, base-building, tower-defense, atmospheric, 2D, singleplayer, demo, horror

## Page settings (leave as they are)
- Kind of project: HTML, played in the browser. Embed: ticked on LastBell-web.zip. Recommended viewport 1280 x 800, or full window.
- Visibility: Restricted, with "Also allow a password to view page" ON. Never change without the owner's word.

## Screenshots for the page (1920 x 1080, PH4; taken from the staged game with the artifacts switched off: `--stock=`, `--hide-lesson`, `--no-banner`, `--no-alerts`, README flag table)
The files are in the scratchpad `ph4-capture/stills/` (copy them to `build/itch-page/` when the owner approves). Order and captions:
1. `01-arrival-dawn.png`: "Dawn on the road into town. Find shelter before dark: three houses to choose from, the best one marked with a star." (`--town=1 --stage=arrive --hour=6.3 --weather=clear`)
2. `02-claimed-house-crew-at-work.png`: "Your house, claimed. By day the crew builds the fence while you watch the street." (`--stage=fourth --slots=sites --builders=3 --hour=10 --advance=25`)
3. `03-storm-night-patrol.png`: "A storm at night: rain, lightning and the crew walking the fence." (`--stage=night --slots=built --weather=storm --hour=21 --advance=30 --lightning=near --lightning-age=0.09`)
4. `04-build-page.png`: "The Build page: the front fence is ready to order, and you build it with your own hands." (`--stage=claimed --hour=9 --radio=build,focus:front`)
5. `05-fight-at-the-fence.png`: "The first attack at the gate: muzzle light, the dead in the street, the crew shooting beside you." (`--stage=night --slots=built --hour=22 --weapon=shotgun --fight=6,mix,149.5,95,1.4 --hold-fire --aiming --until-shot=1 --advance=3 --speed=0`)
6. `06-map.png`: "The map on the radio: the town, your base, the houses you have looked in." (`--stage=fourth --slots=built --hour=11 --radio=map`)
Plus `storm-night.gif`: 4 seconds, 12 fps, 640 px wide (a flash, a bolt of lightning and the crew in the rain; cut from the storm clip of docs/audio-capture.md with Pillow).
Every one is `--winpx=1920x1080 --os-scale=1 --shot=...` with `--hide-lesson --no-banner` and a `--stock=` (and `--no-alerts` on 5 and 6, whose staging leaves the alert stack and a radio call on screen); `--frames=` as the staging needs (150, 60, 80, 120, 16, 90). The numbers in the HUD are a real run's (40 shells, 30 scrap), the card at the bottom left is the key legend of the game itself.

## Open questions for the owner
1. The name.
2. Whether the page should say "demo" and promise a full game ("The full game has more...": the end card now has that line too).
3. Whether to add the short GIF (made: `storm-night.gif`) and a cover image (the old cover in build/itch-page/cover.png is the prototype's school-yard art; `05-fight-at-the-fence.png` or `03-storm-night-patrol.png` would do as a new one).
4. Sound: the page says nothing about it. Nobody has listened to the game yet; `docs/audio-capture.md` lists what to listen for first in the five clips that were made for the owner.
