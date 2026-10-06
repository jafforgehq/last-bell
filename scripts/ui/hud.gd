## The HUD, laid out the way colony games do it: people across the top, stores
## top left, clock and alerts top right, the selection bottom left, time
## controls bottom right. Mirrors the web version's HUD.
##
## The look (round 3) is the schoolyard noticeboard: slate chalkboards in oak trim, hall-pass
## badges for the crew, paper slips for alerts, notebook paper for modals, brass for the clock.
## Every surface asks for a frame by name (Frames, scripts/ui/frames.gd, made by tools/
## make_ui_theme.py) and falls back to a flat chalkboard of the same colours where the theme
## does not have it: `_style(bg, radius, border, shadow, kind, tint)` (a StyleBox: the frame
## `kind` when there is one, else the flat style), `_panel()` (a board), `_paper_style()` (a
## page), `_button(text, primary, paper)`, `_kbd(key)` and `_label` / `_caps` (chalk ink; on
## paper use PAPER_INK and its greys). `frame(kind)`, `has_frame(kind)` and `use_frames` (off
## shows the flat look) are static; FRAME_KINDS lists what the HUD wears. Text colours read at
## 4.5:1 on the frame they sit on (tests/test_hud_text.gd lays each label over the frame's pixels).
##
## The person panel (the selection dock, built in `select`, kept in line in `_refresh_selection`) has,
## besides the health, weapon, doing, needs and wounds rows of before, the round 4 rows from the people's
## modules: Mood (a bar and a word, the reasons in a tooltip), Traits (chips, a blurb each), Bonds (who they
## are close to) and the skills with what they have gained; their record (kills, walls mended...) is the
## tooltip of their name. Each is read through `_mod`, so a game without a module has no row for it. A
## person's rows sit close (PERSON_ROW_GAP): the dock, with its nine buttons, has to fit beside or above the
## panel in a 700 x 560 window (tests/test_hud_layout.gd and tests/test_hud_people.gd sweep the sizes).
##
## Round 5 (jobs): a person's day job is a gold tag in the header of their panel ("Job: Workbench"; a click opens the Jobs
## screen, the Duty roster, scripts/ui/jobs_screen.gd: key J, the clipboard at the right end of the toolbar, a paper page
## that pauses the rules like the scavenging dialog and gives the speed back), and the keys B and M are the buttons
## `job_builders` (Builders) and `job_bench` (Workbench): they give the job and take it away again, lit while the person
## has it, ghosted with the jobs module's reason when there is no seat. All of it is read through `_jobs()`, so a game with
## no jobs module (an older fake) has no such tag or buttons and no Jobs screen. main.gd keeps what the screen marks in the
## world (`jobs_hover`) for the overlay.
##
## Round 6 (buildings): the Build screen (scripts/ui/build_screen.gd), key N, the hammer after the clipboard in the
## toolbar (`build_button`), a click on a plot's sign in the yard: the same paper page, which pauses the rules and gives
## the speed back (`open_build`, `close_build`, `toggle_build`). It marks the plot under the pointer in the world
## (`build_hover`, main.gd's `build_hover` for the yard); the tutorial's lock ghosts its button like the Jobs one.
##
## Round 8 (the town): in a settlement game (`sim.town.on`) `open_scavenge` (key G, a person's Scavenge button, the bag in
## the toolbar: `town_button`, there only in that game) opens the Town Board (scripts/ui/town_board.gd) in place of the
## four-site dialog, which the classic start keeps as it was. The board is `scavenge_dialog` (it has the dialog's
## `closed` and `close`), pauses the rules the same way and is told to `refresh` with the rest of the HUD
## (`town_board_open`). The help's G reads "Town Board" there (`help_g`).
extends Control

const GD := preload("res://scripts/game_data.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Dialog := preload("res://scripts/ui/scavenge_dialog.gd")
const JobsScreen := preload("res://scripts/ui/jobs_screen.gd")
const BuildScreen := preload("res://scripts/ui/build_screen.gd")
const TownBoard := preload("res://scripts/ui/town_board.gd")
const GameOver := preload("res://scripts/ui/game_over.gd")
const DemoEndCard := preload("res://scripts/ui/demo_end_card.gd")
const TownEndCard := preload("res://scripts/ui/town_end_card.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")
const Tactics := preload("res://scripts/sim/tactics.gd")
const Kinds := preload("res://scripts/sim/kinds.gd")
const CrewLoad := preload("res://scripts/sim/crew_load.gd")
const Prefs := preload("res://scripts/prefs.gd")
const AimMode := preload("res://scripts/aim_mode.gd")
const RadioVerbs := preload("res://scripts/ui/radio_verbs.gd")
const CallCard := preload("res://scripts/ui/call_card.gd")
const NewsPanel := preload("res://scripts/ui/news_panel.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const RadioPanel := preload("res://scripts/ui/radio_panel.gd")
const CommandWheel := preload("res://scripts/ui/command_wheel.gd")
const WheelCtl := preload("res://scripts/ui/wheel_ctl.gd")
const CommunityKit := preload("res://scripts/ui/community_kit.gd")
const NightKit := preload("res://scripts/ui/night_kit.gd")
const GateKit := preload("res://scripts/ui/gate_kit.gd")
const AlertFeed := preload("res://scripts/ui/alert_feed.gd")
const StoresCalm := preload("res://scripts/ui/stores_calm.gd")
const ControlsTable := preload("res://scripts/ui/controls_table.gd")
const Access := preload("res://scripts/access.gd")

## The schoolyard noticeboard: slate-green chalkboards in oak trim, chalk ink, bus yellow
## for the accent, brass for the clock, paper for slips and modal pages. The text colours
## all read at 4.5:1 or better on the panel, even over the brightest ground
## (tests/test_hud_text.gd computes it). DANGER is for bars, dots and icons; words in red
## use DANGER_TEXT.
const INK := Color("#eeeadd")
const INK2 := Color("#c1c5b5")
const INK3 := Color("#a8ae9d")
const PANEL := Color(27 / 255.0, 42 / 255.0, 38 / 255.0, 0.94)
const PANEL_HI := Color(40 / 255.0, 58 / 255.0, 52 / 255.0, 0.94)
const LINE := Color(0.93, 0.96, 0.89, 0.10)
const LINE2 := Color(0.93, 0.96, 0.89, 0.20)
const ACCENT := Color("#f0c24a")
const ACCENT_INK := Color("#1a1508")
const DANGER := Color("#e0584a")
const DANGER_TEXT := Color("#f27f72")
## The words of the Big Night's badge (round 19): a lighter red than DANGER_TEXT, which on the badge's own tinted chip reads at only 4.1 to 1 over
## the brightest ground (the HUD's rule is 4.5).
const DANGER_BADGE := Color("#ff9b8e")
const WARN := Color("#e8953a")
const OK := Color("#8fb85a")
const INFO := Color("#7fa6c9")
const DAWN := Color("#e2a3b6")
## The trim of a board (oak) and the brass of the clock and the bell.
const OAK := Color("#8a6238")
const OAK_DARK := Color("#56391f")
const BRASS := Color("#d2a94e")
## Paper (alert slips, the notebook page of a dialog): dark ink on it, each at 4.5:1 or
## better on the palest and on the tinted slips (tests/test_hud_text.gd computes it).
const PAPER := Color("#efe9d6")
const PAPER_INK := Color("#26241c")
const PAPER_INK2 := Color("#47443a")
const PAPER_INK3 := Color("#575443")
const PAPER_LINE := Color(0.16, 0.14, 0.1, 0.16)
## The slips an alert is written on, by its level, and the dark colour of its icon and
## its edge on that paper (the level colours are for the dark boards).
const SLIP := {"danger": Color("#f0c4b8"), "warn": Color("#f2dc9c"), "info": Color("#cfe0dc")}
const SLIP_MARK := {"danger": Color("#a8301f"), "warn": Color("#92500c"), "info": Color("#2a6488")}

const PHASE_ICON := {"day": "sun", "dusk": "sun", "night": "moon", "dawn": "sun"}
const PHASE_COLOR := {"day": ACCENT, "dusk": WARN, "night": INFO, "dawn": DAWN}
## The icon of an alert nothing more specific is known about: by its level.
const LEVEL_ICON := {"danger": "warn", "warn": "warn", "info": "bell"}
const LEVEL_COLOR := {"danger": DANGER, "warn": WARN, "info": INFO}
## The icon an alert gets for what it is about, by the start of its id (the first
## match wins; sim.gd and the modules raise `seg-3`, `fever-ana`, `scav-out-2`,
## `low-food`...). An id that matches none of these and names a store gets that
## store's icon (`no-ammo`); anything else gets the level's icon.
const ALERT_ICONS := [
	["seg-", "wall"], ["breach-", "wall"], ["fever-", "fever"], ["scav-", "scavenge"], ["hurt-", "wound"],
	["scratch-", "wound"], ["down-", "down"], ["turned-", "turned"], ["treated-", "treat"], ["nohealer-", "treat"],
	["exile-", "sendout"], ["bell", "bell"], ["horde", "walker"], ["rain", "water"],
	# round 2: a brute and runners are the dead; the alarm, the forecast and the last night ring a bell
	["brute", "walker"], ["runners", "walker"], ["lure", "bell"], ["forecast", "bell"], ["bignight", "bell"],
	# round 3: the worktable (`workshop-idle`) is about ammo
	["workshop-", "ammo"],
	# round 4: a skill went up (a star), someone broke down (a face), the radio hour and the
	# storyteller's cards (the bell: someone is calling), the dawn assembly (the sun)
	["skill-", "star"], ["breakdown-", "mood"], ["story", "radio"], ["story-", "radio"], ["dawn", "sun"],
	# round 5: nobody at the radio desk (the radio) or on watch (the lookout's post)
	["job-radio", "radio"], ["job-watch", "post"],
	# round 9: a lot is claimed (the hammer), a wall is put up across a street (the wall), a building out in the streets is ruined
	["lot-", "build"], ["wall-", "wall"], ["ruined-", "down"],
	# round 13: a vehicle found or lost (the sim's `vehicle-<id>` and `vehicle-found-<place>`)
	["vehicle-", "car"],
]
## The order buttons with no icon of their own wear one that is already there: the alarm a
## bell; the Builders job the wall (the hammer is Repair's own, and in the small size, where only the
## icons show, two hammers side by side could not be told apart); the Workbench the ammo store's icon.
const GIZMO_ICON := {"lure": "bell", "job_builders": "wall", "job_bench": "ammo"}
const STORE_ICONS := ["ammo", "scrap", "food", "water", "meds"]
## Icons the HUD adds to the baked ones (assets/data/map.json): white on clear, 64 px, like the rest
## (tools/make_menu_icon.py draws the menu's; tools/make_people_icons.py the star, a skill that went
## up, and the face, someone who is Shaken or Breaking; tools/make_jobs_icon.py the clipboard of the
## Jobs screen; tools/make_build_icon.py the hammer of the Build screen).
const EXTRA_ICONS := {"menu": "res://assets/ui/icons/menu.png", "star": "res://assets/ui/icons/star.png", "mood": "res://assets/ui/icons/mood.png", "radio": "res://assets/ui/icons/radio.png", "jobs": "res://assets/ui/icons/jobs.png", "build": "res://assets/ui/icons/build.png", "fuel": "res://assets/ui/icons/fuel.png", "car": "res://assets/ui/icons/car.png"}
## The panel of one of the dead by its kind: [title, second line]; and what it does on its way in.
const ZOMBIE_NAMES := {"walker": ["Walker", "One of the dead"], "runner": ["Runner", "Fast and frail"], "brute": ["Brute", "Slow, huge, tears walls down"]}
## A brute of a Big Night (round 19): armoured, soft only at the head.
const PLATED_NAMES := ["Plated brute", "Armoured: only the head is soft"]
const ZOMBIE_VERBS := {"walker": "Shambling toward the wall", "runner": "Running toward the wall", "brute": "Lumbering toward the wall"}
## Walls and doors, by side and by what they are made of. A piece the HUD has no
## name for (a new kind of wall or door) shows its own words instead of failing.
const SIDE := {"N": "North wall", "W": "West wall", "E": "East wall", "S": "School"}
## A wall made at a mouth of a lot (round 9: the sections from this id on) is a street wall, not a side of the compound.
const LOT_WALL_FROM := 100
const LOT_WALL := "Street wall"
const MATERIAL := {"container": "shipping container", "bus": "school bus", "car": "wrecked car", "pallets": "pallets and stakes", "gate": "steel gate", "chainlink": "fence and wire", "blocks": "cinderblock", "door": "boarded door"}
const STORES := [["ammo", "Ammo"], ["scrap", "Scrap"], ["food", "Food"], ["water", "Water"], ["meds", "Medicine"]]
## The stores that also show how many days of them are left.
const DAYS_STORES := ["food", "water"]
## Only the skills that do something in version 1 are listed in the person panel.
const SKILLS_SHOWN := ["Shooting", "Building", "Medicine"]
## The colour of a skill's bar (the part it has gained is the accent's gold).
const SKILL_COLOR := Color("#b3a57f")
## What each skill grows with, for its tooltip when the skills module does not say how much (and what a
## unit of each kind of work is, when it does).
const SKILL_FED := {
	"Shooting": "kills", "Melee": "kills with the pike or the butt of the gun",
	"Building": "walls mended and scrap made into ammo", "Medicine": "people treated",
}
const SKILL_UNITS := {
	"kills": "kills", "melee": "kills with the pike or the butt of the gun", "treated": "people treated",
	"mended": "HP of wall mended", "crafted": "scrap made into ammo",
}
## A person's mood (round 4, sim.morale.mood) in colours: the bar's, a graphic (3:1 on the board), and
## the word's, a text colour (4.5:1; tests/test_hud_people.gd computes both). A breakdown wears Breaking's.
const MOOD_COLORS := {"Inspired": ACCENT, "Steady": INFO, "Shaken": WARN, "Breaking": DANGER}
const MOOD_TEXT := {"Inspired": ACCENT, "Steady": INK, "Shaken": WARN, "Breaking": DANGER_TEXT}
## How wide the word at the end of the Health and the Mood rows is ("Breakdown" is the longest), so
## the two bars end together.
const MOOD_W := 62
## A person's panel has more rows than the other panels, so its rows sit closer (a row is 16 px tall)
## and the blocks of it (the header, the rows, the skills) a little less far apart.
const PERSON_ROW_GAP := 3
const PERSON_BLOCK_GAP := 6
## The stock of a card whose person is remembered: greyer than a living one's.
const MEMORIAL_STOCK := Color(0.7, 0.7, 0.72)
## The longest a line of a tooltip about a person is, in letters, before it is broken (the engine's
## own wrapping of a tooltip is no help in a narrow window).
const TIP_WRAP := 44
## The most reasons the mood tooltip lists (the biggest first, the rest in a line).
const MOOD_LINES := 10
## Game hours without a meal or a drink at which a person is called hungry,
## starving, thirsty and parched (the supplies module penalises at these).
const HUNGRY_H := 18.0
const STARVING_H := 36.0
const THIRSTY_H := 14.0
const PARCHED_H := 24.0
## The selection panel's width and the gizmo buttons' size and gap.
const INSPECT_W := 300
const GIZMO_W := 66
const GIZMO_GAP := 6
## In a window too short for two rows of buttons above the selection panel they
## shrink to a single row of icons (the name and key are in the tooltip).
const GIZMO_MINI := 44
## The clock's width (and the alert feed's under it): wide enough for "DAY 30 OF 30",
## the longest phase and the PAUSED pill in one row, so pausing never moves it.
const CLOCK_W := 248
const CLOCK_W_COMPACT := 164
## Every alert panel stays up at least this many real milliseconds from when it
## first appeared, even if the rules drop the alert sooner: they count an alert's
## life in game seconds, so at 3x speed a five-second alert would last under two.
const ALERT_HOLD_MS := 6000
## The most alerts shown at once (fewer in a narrow window).
const ALERTS_MAX := 5
const ALERTS_MAX_COMPACT := 3
## The gap between two alert slips (the feed's separation).
const ALERT_GAP := 6.0
## The banner fades in and out over BANNER_FADE seconds and stays up BANNER_HOLD between.
## (TEMPO, 2026-10-07: 0.7 and 3.0, a 4.4 s sign: 0.45 and 1.8, 2.7 s)
const BANNER_FADE := 0.45
const BANNER_HOLD := 1.8
## A toast is up this many real seconds, fading over the last TOAST_FADE of them.
## The card of the offer to leave the base (round 23).
const LEAVE_TEXT := "Leave the base?  E / click: open the Map"
const TOAST_SECONDS := 2.5
const TOAST_FADE := 0.4
const TOAST_COLOR := {"danger": DANGER_TEXT, "warn": WARN, "info": INK}
## The window must be this tall for the fields-of-fire legend to show: in a shorter one the
## stores, the legend and the smallest selection dock would not all fit down the left side.
const LEGEND_MIN_H := 600.0
## The tooltip of the fields-of-fire button.
const FIELDS_TIP := "Fields of fire: which wall pieces your guns reach at night\nKey: V"
## The width of a key of the toolbar (the speeds, the fields view, the sound, the help, the Jobs screen, the Build
## screen, the menu).
const TOOL_W := 26
## The tooltip of the Jobs button.
const JOBS_TIP := "Jobs: who works where by day and holds which post at night\nKey: J"
## The tooltip of the Build button.
const BUILD_TIP := "Build: pick a building, and the Builders raise it where it belongs\nKey: N"
## The same in a settlement game, where the screen also claims the streets round the school and walls them in.
const BUILD_LOTS_TIP := "Build: order a building for the Builders to raise, claim the streets round the school and wall them in\nKey: N"
## What the help's N says when pointed at in a settlement game.
const HELP_N_LOTS_TIP := "The Build screen: buildings, and the streets round the school to claim and wall in"
## The tooltip of the help's G in a settlement game (round 13: the vehicles are picked on the board).
const HELP_G_TOWN_TIP := "The Town Board: the map of the town and the city across the river, who goes and in what: a vehicle makes the road quicker and carries more, and burns fuel"
## The fuel store's row in the stores panel (round 13), shown in a settlement game once there is a vehicle or any fuel;
## the fuel is in the amber below this much while there is a vehicle to burn it.
const FUEL_LOW := 10.0
## The tooltip of the Town Board button (a settlement game only: the classic start has no board).
const TOWN_TIP := "Town Board: the map of the town, the places on the road and the parties out\nKey: G"
## Round 17, the radio's toolbar buttons (avatar mode only): the News log and the call to arms.
const NEWS_TIP := "Radio panel: News, what the radio heard and the calls that wait for your answer, with Jobs, Build and the Map one tab away. Click a crew card to ask them something.\nKey: T"
## Round 18, avatar mode: the toolbar's Jobs, Build and Town Board buttons open the radio panel on a page; the full (modal) page is Shift and the key.
const JOBS_TIP_AVATAR := "Jobs: who works where by day and holds which post at night. You ask, and they answer, on the radio panel\nKey: J (Shift+J: the full page)"
const BUILD_TIP_AVATAR := "Build: pick a building, and the Builders raise it where it belongs\nKey: N (Shift+N: the full page, with the streets)"
const BUILD_LOTS_TIP_AVATAR := "Build: order a building for the Builders to raise; the full page claims the streets round the school and walls them in\nKey: N (Shift+N: the full page)"
const TOWN_TIP_AVATAR := "Map: the places on the road and the parties out. Take control of a trip, or ask someone to go\nKey: G (Shift+G: the Town Board, the full page)"
## The One House's toolbar words (its radio panel has Jobs, Build, Map and News; Shift+J, N and G are not the school's full pages there).
const JOBS_TIP_TOWN := "Jobs: who works where by day and holds which post at night. You ask, and they answer\nKey: J"
const BUILD_TIP_TOWN := "Build: fortify the house. The page says what comes next, and one button orders a whole project\nKey: N"
const NEWS_TIP_TOWN := "The radio: what was heard, the calls that wait for an answer, and Jobs, Build and the Map a tab away. Click a card to ask someone something\nKey: T"
const FORECAST_TIP := "What the lookout saw on the road: how many are coming tonight, and from where"
const ALARM_TIP := "Call to arms: everyone to their posts now, by day too, until you stand down or the dawn comes"
const ALARM_OFF_TIP := "Stand down: end the call to arms and send everyone back to work"
## How the trust a person has in the player reads, by the radio's word (radio.tone_of): the bar and the word.
const TRUST_BAR := {"willing": OK, "grudging": WARN, "doubtful": DANGER}
const TRUST_WORD := {"willing": OK, "grudging": WARN, "doubtful": DANGER_TEXT}
## The News panel is at least this tall to be worth showing; under it the alerts give up room (see `_layout_news`).
const NEWS_MIN_H := 110.0
## What the speed buttons do and their keys, for the tooltips: [words, key].
const SPEED_TIPS := [["Pause the game", "Space"], ["Play at normal speed", "1"], ["Play twice as fast", "2"], ["Play three times as fast", "3"]]
## The controls panel: [caption, entries to a row, [[keys, what it does], ...]]. `keys` is
## one entry's chips, one chip for each word ("W A S D" is four). Every key and mouse
## button main.gd's _unhandled_input answers to is here.
const HELP := [
	["Orders for the selection", 3, [["R", "Draft"], ["P", "To post"], ["F", "Repair"], ["C", "Follow"], ["T", "Treat"], ["X", "Send out"], ["G", "Scavenge"], ["B", "Builders"], ["L", "Lure"], ["M", "Workbench"]]],
	["Mouse", 2, [["Click", "Select"], ["Right-click", "Send"], ["Middle Drag", "Pan"], ["Alt Drag", "Pan"], ["Scroll", "Zoom"]]],
	# (Esc, the longest, wraps in as little as 76 px, so in the width of the column ("Fields of fire") as
	# "Deselect, or" and "the menu": it does not widen the panel; J, the Jobs screen, is "Jobs" and N, the Build
	# screen, "Build" so that the other column, which has "Speed" in it, stays as narrow: the order buttons must still
	# sit beside the selection panel in a 1280 window)
	["Keyboard", 2, [["W A S D", "Pan"], ["Arrows", "Pan"], ["Space", "Pause"], ["1 2 3", "Speed"], ["Tab", "Next person"], ["F5", "Save"], ["V", "Fields of fire"], ["J", "Jobs"], ["Esc", "Deselect, or the menu", 76], ["N", "Build"], ["F9", "Load"]]],
]
## The controls of avatar mode (round 17), in the same form: the survivor the player plays, and the keys that are left. (No order
## keys, no selecting in the yard, no panning: the camera follows. G, the Town Board, and N, Build, keep their places so that
## the words the HUD gives them in a settlement game still reach them.)
const HELP_AVATAR := [
	["You", 2, [["W A S D", "Move"], ["Right-click", "Hold to aim"], ["Click", "Fire (aiming)"], ["Shift", "Aim, one hand"], ["E Click", "Use, pick"], ["R F", "Reload, melee"], ["Q", "Weapon away"], ["Right-click", "Tap to order"]]],
	["Radio: card or wheel (C)", 2, [["C Middle", "Wheel (hold)"], ["Shift", "Wheel: all near"], ["1-5", "Pick crew"], ["Z", "Last order"], ["Click", "Crew card: pick"], ["Esc", "Wheel: cancel"]]],
	["Keyboard", 2, [["Space", "Pause"], ["Shift 1-3", "Speed"], ["Scroll", "Zoom"], ["Tab", "Next person"], ["J", "Jobs"], ["N", "Build"], ["B", "Base"], ["G", "Scavenge"], ["L", "Alarm"], ["T", "Radio"], ["V", "Fields of fire"], ["F5 F9", "Save, load"], ["Esc", "Close, or the menu", 76], ["Shift", "J N G: full"]]],
]
## (With "Always aim at the mouse", round 22's setting: the mouse aims by itself and the left button fires, as it did.)
const HELP_AVATAR_ALWAYS := [
	["You", 2, [["W A S D", "Move"], ["Mouse", "Aim and fire"], ["E", "Use"], ["R F", "Reload, melee"], ["Q", "Weapon away"], ["Right-click", "Tap to order"]]],
	["Radio: card or wheel (C)", 2, [["C Middle", "Wheel (hold)"], ["Shift", "Wheel: all near"], ["1-5", "Pick crew"], ["Z", "Last order"], ["Click", "Crew card: pick"], ["Esc", "Wheel: cancel"]]],
	["Keyboard", 2, [["Space", "Pause"], ["Shift 1-3", "Speed"], ["Scroll", "Zoom"], ["Tab", "Next person"], ["J", "Jobs"], ["N", "Build"], ["B", "Base"], ["G", "Scavenge"], ["L", "Alarm"], ["T", "Radio"], ["V", "Fields of fire"], ["F5 F9", "Save, load"], ["Esc", "Close, or the menu", 76], ["Shift", "J N G: full"]]],
]
## (The One House's controls are not here: they are the one table, scripts/ui/controls_table.gd, which the Controls page and the legend are made from too.)
## What a crew card says of the stance its person has been put in (avatar mode), in whole words and, on a narrow card, short ones.
const STANCE_WORDS := {"follow": "Following", "hold": "Holding", "cover": "Covering", "search": "Searching", "back": "Back"}
const STANCE_SHORT := {"follow": "Follow", "hold": "Hold", "cover": "Cover", "search": "Search", "back": "Back"}
const STANCE_TIPS := {"follow": "Following you", "hold": "Holding where you left them", "cover": "Covering your back", "search": "Searching where you pointed", "back": "On the way back to work"}
## The one-line hint at the foot of the window, [words, [key, words]...]: the old yard's and avatar mode's.
const HINT := ["Click someone in the yard", [["Right-click", "to send them"], ["Scroll", "to zoom"], ["Space", "to pause"]]]
## (Avatar mode's is two lines, so that it fits a 700 px window: the survivor's hands, then the radio, the map and the news.)
const HINT_AVATAR := [
	["", [["WASD", "to move"], ["Right-click", "to aim"], ["Click", "to fire"], ["R", "to reload"], ["F", "to swing"], ["Q", "weapon away"]]],
	["Click a person to radio, or hold C for the wheel", [["E", "to use"], ["G", "the map"], ["T", "News"]]],
]
## (and with "Always aim at the mouse": the mouse aims, a click fires.)
const HINT_AVATAR_ALWAYS := [
	["", [["WASD", "to move"], ["Mouse", "to aim"], ["Click", "to fire"], ["R", "to reload"], ["F", "to swing"], ["Q", "weapon away"]]],
	["Click a card to radio, or hold C for the wheel", [["E", "to use"], ["G", "the map"], ["T", "News"]]],
]
## (The town's: one survivor alone has nobody to radio yet, and the walls are not the school's.)
const HINT_TOWN := [
	["", [["WASD", "to move"], ["Right-click", "to aim"], ["Click", "to fire"], ["R", "to reload"], ["F", "to swing"], ["E", "to use"]]],
	["", [["Q", "weapon away"], ["M", "the map"], ["T", "the radio"], ["Esc", "the menu"]]],
]
const HINT_TOWN_ALWAYS := [
	["", [["WASD", "to move"], ["Mouse", "to aim"], ["Click", "to fire"], ["R", "to reload"], ["F", "to swing"], ["E", "to use"]]],
	["", [["Q", "weapon away"], ["M", "the map"], ["T", "the radio"], ["Esc", "the menu"]]],
]
## The legend of the fields-of-fire view: the tint of a wall section by how many guns
## reach it, [colour, words] (the overlay tints with the same colours).
const FIELDS_LEGEND := [[DANGER, "Red: no gun reaches it"], [WARN, "Amber: one gun"], [OK, "Green: two or more"]]


## A rounded meter: background track and a coloured fill.
class Bar:
	extends Control
	var value := 1.0
	var color := Color("#8fb85a")
	var track := Color(0.93, 0.96, 0.89, 0.12)
	## The groove frame (bar_track) the meter lies in, when the HUD has one and the bar is tall
	## enough for it (a thin bar keeps the flat track).
	var groove: StyleBox = null
	## The last part of the fill, as a fraction of the whole bar, drawn in `gain_color`: what a skill
	## has gained since the run began (0 for no such part).
	var gain := 0.0
	var gain_color := Color("#f0c24a")

	func _draw() -> void:
		if groove != null and size.y >= 6.0:
			draw_style_box(groove, Rect2(Vector2.ZERO, size))
			if value > 0.0:
				var h := size.y - 2.0
				var fill_w := maxf(h, (size.x - 2.0) * clampf(value, 0.0, 1.0))
				_rr(Rect2(1, 1, fill_w, h), h * 0.5, color)
				if gain > 0.0:
					var g := minf(fill_w, (size.x - 2.0) * clampf(gain, 0.0, 1.0))
					_rr(Rect2(1 + fill_w - g, 1, g, h), h * 0.5, gain_color)
			return
		var r := size.y * 0.5
		_rr(Rect2(Vector2.ZERO, size), r, track)
		if value > 0.0:
			var fill_w := maxf(size.y, size.x * clampf(value, 0.0, 1.0))
			_rr(Rect2(0, 0, fill_w, size.y), r, color)
			if gain > 0.0:
				var g := minf(fill_w, size.x * clampf(gain, 0.0, 1.0))
				_rr(Rect2(fill_w - g, 0, g, size.y), r, gain_color)

	func _rr(rect: Rect2, r: float, c: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(int(r))
		sb.anti_aliasing = true
		draw_style_box(sb, rect)


## The 24-hour strip in the clock: night, dawn, day, dusk, with a marker.
class Strip:
	extends Control
	var hour := 0.0
	var gradient: Gradient
	## The rules' seasons (round 10): in a campaign the day's hours are mapped onto the colours of the standard day, so
	## the dusk and the dawn of the strip are the season's. Null (or not a campaign): the day's own.
	var seasons = null

	## The colour of the strip at an hour of the real day.
	func colour_at(h: float) -> Color:
		if seasons != null and seasons.campaign:
			h = seasons.light_hour(h)
		return gradient.sample(h / 24.0)

	func _init() -> void:
		gradient = Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.21, 0.245, 0.28, 0.5, 0.76, 0.805, 0.85, 0.9, 1.0])
		gradient.colors = PackedColorArray([Color("#28304c"), Color("#28304c"), Color("#8a6a7c"), Color("#d8c9a4"), Color("#e9dfc3"), Color("#e2b67e"), Color("#b8684a"), Color("#45405e"), Color("#28304c"), Color("#28304c")])

	func _draw() -> void:
		var y := size.y * 0.5 - 3.0
		var n := 64
		for i in n:
			var x0 := size.x * i / n
			var x1 := size.x * (i + 1) / n
			draw_rect(Rect2(x0, y, x1 - x0 + 0.5, 6), colour_at((i + 0.5) / n * 24.0))
		var mx := size.x * hour / 24.0
		draw_rect(Rect2(mx - 2.5, y - 4, 5, 14), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(mx - 1.5, y - 3, 3, 12), Color("#ece6d8"))


## A small round lamp (round 22, the gate's indicator in the clock): a coloured disc with a dark rim and a glint, a faint halo when it is lit.
class Lamp:
	extends Control
	var color := Color("#e0584a")
	## Whether it is lit (a halo round it); the colour is the state's either way.
	var lit := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(14, 14)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		if lit:
			draw_circle(c, r + 1.0, Color(color, 0.25))
		draw_circle(c, r - 1.0, Color(0.03, 0.05, 0.05, 0.95))
		draw_circle(c, r - 2.0, color)
		draw_circle(c + Vector2(-1.5, -1.5), 1.4, Color(1, 1, 1, 0.55))


var data: Dictionary
var icons := {}
var people: Array = []
var selection = null
var compact := false

var on_select: Callable
var on_focus: Callable
var on_speed: Callable
var on_gizmo: Callable
var on_alert: Callable
var on_sound: Callable
## The fields-of-fire button was pressed (main.gd flips the view and calls set_fields).
var on_fields: Callable
## The report card's Main menu button was pressed (the shell sets it; nothing happens while it is not).
var on_menu: Callable
## The toolbar's Menu button was pressed: main.gd opens the pause menu (nothing happens while it is not set).
var on_open_menu: Callable
## The toolbar's Jobs button (or a person's job tag) was pressed: main.gd opens or closes the Jobs screen (it asks the
## tutorial's lock first). With nobody listening the HUD opens it itself.
var on_jobs: Callable
## The Jobs screen marks a place in the world (a station, a night post, a person): called with {} when the screen is
## closed, else {"station": id, "post": id, "person": id} (each "" when nothing of the kind is marked); main.gd keeps
## it for the overlay to draw (`jobs_hover`).
var on_jobs_hover: Callable
## The toolbar's Build button was pressed: main.gd opens or closes the Build screen (it asks the tutorial's lock
## first). With nobody listening the HUD opens it itself.
var on_build: Callable
## The toolbar's Town Board button was pressed (settlement game): main.gd opens or closes the board (it asks the
## tutorial's lock and the pages first). With nobody listening the HUD opens it itself.
var on_town: Callable
## The toolbar's Alarm button was pressed (avatar mode): called first, with no arguments, and the alarm is only rung or stood down if
## it returns true (main.gd asks the tutorial's lock, which refuses it in the lessons that do not teach it). With nobody listening it is.
var on_alarm: Callable
## The weapon button under the gun's readout was pressed (avatar mode, round 23): main.gd puts the weapon away or draws it (Q does the same). With nobody
## listening the HUD flips the state itself.
var on_holster: Callable
## Opens a played trip (main.gd's `open_raid(people, place, vehicle_id, loot_mult, on_done)`): the Town Board's "Take control".
var on_raid: Callable
## The clock's Gate row was clicked (round 23, avatar mode): main.gd works the gate when the avatar is at it, else says where it is and glides the camera
## to the lever. With nobody listening nothing happens.
var on_gate: Callable
## The offer of the Map on leaving the base (round 23): called with no arguments when its card is clicked or its button pressed (main.gd opens the Map).
var on_leave: Callable
## The Build screen marks a plot in the world: called with {} when the pointer is not on a plot's slip or the screen
## is closed, else {"plot": id}; main.gd keeps it for the yard to draw (`build_hover`).
var on_build_hover: Callable
## Plays one of the menu sounds (ui_open, ui_close, ui_click, ui_confirm, ui_error) at a level: main.gd sets it; the Jobs
## screen uses it (nothing happens while it is not set).
var on_ui_sound: Callable
## Starting a new run or loading a save takes a scene reload, which is the
## game's business: by default the choice is put in Engine meta ("run") for
## main.gd and the scene is reloaded; a test sets this to see the choice instead.
var restart: Callable
## Where the game's saves are (the newest one is offered when a run is lost).
var save_paths: Array = [SaveGame.AUTO_PATH, SaveGame.QUICK_PATH]
## The open scavenging dialog (in a settlement game, round 8, the Town Board: scripts/ui/town_board.gd, which has the
## same `closed` and `close`) and the game-over overlay, or null.
var scavenge_dialog = null
var game_over = null
var _paused_for_dialog := false
var _speed_before_dialog := 0
## The open Jobs screen (the Duty roster, scripts/ui/jobs_screen.gd), or null; the rules wait while it is up
## and the speed comes back when it is closed, as for the scavenging dialog. `jobs_hover` is what it last
## marked in the world.
var jobs_screen = null
var jobs_hover := {}
var _paused_for_jobs := false
var _speed_before_jobs := 0
## The open Build screen (scripts/ui/build_screen.gd), or null: the rules wait while it is up, like the Jobs
## screen. `build_hover` is the plot it last marked in the world.
var build_screen = null
var build_hover := {}
var _paused_for_build := false
var _speed_before_build := 0

## The column at the top left: the stores, and under them the fields-of-fire legend
## while that view is on.
var left_col: VBoxContainer
var res_panel: PanelContainer
var res_grid: GridContainer
var res_values := {}
var res_days := {}
var res_labels: Array = []
## The fuel row of the stores panel (round 13): [icon, name, number] and the number's label, which are shown only in a settlement
## game once there is a vehicle or any fuel (the panel is as it always was without them).
var fuel_cells: Array = []
## Round 16, the crew-load strip under the stores: "Seats 5 of 11" (scripts/sim/crew_load.gd), a tooltip that lists the empty
## seats, a click that opens the Duty roster. Amber while the radio desk or the lookout post is empty.
var crew_load_panel: PanelContainer
var crew_load_label: Label
var crew_load_icon: TextureRect
var _crew_load_sig := ""
## The crew's cards across the top: a row, or rows when there are more people than a row has room for (a crew that
## has grown: recruits come over the radio). `bar_plan` is how they are laid out now, see _layout_bar.
var bar: HFlowContainer
var cards: Array = []
var bar_plan := {"w": 60, "rows": 1, "per_row": 6, "gap": 6, "roam": false}
## What the row was last laid out for (the number of cards, the window's width and the room), so that it is laid out
## again only when one of them changes.
var _bar_sig := ""
## Kept clear between the cards and the stores, and between the cards and the clock.
const BAR_MARGIN := 12.0
## The size of the status marks on a card and how many fit (set with the card size).
var mark_px := 0
var mark_max := 4
## The last sim the HUD was updated from (for the things it opens itself).
var sim_ref = null
## The column at the top right: the clock, and under it the alerts.
var right_col: VBoxContainer
var clock: PanelContainer
## The small brass bell on the clock's top edge: there while the dusk bell has rung (until dawn).
var clock_bell: TextureRect
var day_label: Label
var phase_chip: PanelContainer
var phase_icon: TextureRect
var phase_label: Label
var time_label: Label
var until_label: Label
var strip: Strip
var temp_icon: TextureRect
var temp_label: Label
var walkers_label: Label
## The lookout's forecast of tonight, in the clock from 17:00 until dawn (hidden before).
var forecast_label: Label
## Round 19, in avatar mode: the community's own reading of tonight under the forecast ("Should hold: posts 5 of 5, walls 90%"; green or
## amber), and the badge of a Big Night in a row of its own under the day counter ("Big Night tomorrow" from the radio desk's notice,
## "Big Night" tonight), its bell and its words. Anchor `clock.night` is the badge.
var ready_label: Label
var night_badge: PanelContainer
var night_badge_icon: TextureRect
var night_badge_label: Label
var _badge_state := ""
## Round 22, in avatar mode, in the clock above the forecast: the gate's state in a lamp and a word ("Gate: open", "Gate: shut", "Gate: held open"), the
## lamp being green while it is open, red while it is shut and amber while the leaves move. Only there with the gate's rules in charge
## (scripts/ui/gate_kit.gd). Anchor `clock.gate`. `_gate_last` and `_gate_dir` are the leaves' last `open` and which way they were going.
var gate_row: HBoxContainer
var gate_lamp: Lamp
var gate_label: Label
var _gate_last := -1.0
var _gate_dir := 0
var alerts_box: VBoxContainer
## The order the feed shows its alerts in ("id:level|..."): the panels are moved only when it changes.
var alert_sig := ""
## What the feed knows, by alert id: {"id", "level", "text", "sub", "born", "seq", "live" (the
## rules still hold it), "seen" and "first_ms" (whether its panel has appeared, and when it
## first did, in Time.get_ticks_msec() terms), "panel" (null while it is not shown), and the
## parts of the panel: "icon", "title", "subl", "col"}.
var alert_items := {}
## How long a panel stays after the rules drop its alert (a test shortens it).
var alert_hold_ms := ALERT_HOLD_MS
var alert_seq := 0
## HUDA, the town's calm HUD (made by `set_profile("one_house")`, null in the school's): the alert feed (fading info cards, merged siblings, three cards and a
## "+N more" pill: scripts/ui/alert_feed.gd) and the slim stores (icon and number, scrap shown when it matters: scripts/ui/stores_calm.gd).
var _alert_feed = null
var _stores_calm = null
## The "PAUSED" pill in the clock, shown while the game is paused.
var paused_pill: PanelContainer
var paused_label: Label
var banner: PanelContainer
var banner_title: Label
var banner_sub: Label
var banner_tween: Tween
var dock: BoxContainer
var inspect: PanelContainer
var inspect_refs := {}
var gizmos: GridContainer
## How many buttons are in the dock now (children being freed still count in the tree).
var gizmo_count := 0
## Whether the buttons are the small icon-only kind (see GIZMO_MINI).
var gizmo_mini := false
var speed_panel: PanelContainer
var speed_buttons: Array = []
var sound_button: Button
## The fields-of-fire view's button (lit while the view is on) and its legend.
var fields_button: Button
var fields_on := false
var fields_legend: PanelContainer
var help_button: Button
## The Jobs button (a clipboard) next to the Menu button at the right end of the toolbar (the Jobs screen: J).
var jobs_button: Button
## The Build button (a hammer) after it (the Build screen: N).
var build_button: Button
## The Town Board button (the scavenging bag) between the sound and the help, there only in a settlement game (the Town
## Board: G).
var town_button: Button
## The word beside the G key in the controls help ("Scavenge", or "Town Board" in a settlement game).
var help_g: Label
## The word beside the N key in the controls help ("Build": there is no room for more beside it; in a settlement game, round 9,
## pointing at it says that the screen also claims the streets round the school).
var help_n: Label
## The Menu button at the right end of the toolbar (the pause menu: Esc).
var menu_button: Button
var help: PanelContainer
var hint: PanelContainer
## Avatar mode (round 17; main.gd's `set_avatar`, and the HUD notices it from the sim): the controls help and the hint describe the
## survivor's keys, the readout of the gun is up and the avatar's crew card says YOU. `ammo_panel` is that readout in the right
## column under the clock: the weapon's name (`ammo_name`), "12 / 340" the rounds that can be fired over the stores (`ammo_label`: the
## magazine's, but never more than the stores hold, as shots come from them; amber while the magazine is low or the stores cannot fill
## it, red when they are dry) and a bar (`ammo_bar`, the reload while the gun is being reloaded, else how full the magazine is).
## ROUND 26: a real run is always an avatar game, so `avatar_ui` is false only for the title's yard and a test's helper scene: the old yard's
## help (HELP), hint (HINT) and the dock's order buttons (the gizmos) below are what those show. No player reaches them.
var avatar_ui := false
## Orientation Day (main.gd sets it before `set_avatar`): the lessons teach the modal pages, locked by the coach, so the radio panel has
## the News page only and the toolbar's tips are the plain ones (`panel_ui`).
var tutorial_ui := false
var ammo_panel: PanelContainer
var ammo_label: Label
var ammo_name: Label
var ammo_bar: Bar
## The small button under the readout (round 23, scripts/aim_mode.gd): "Weapon: drawn (Q)" or "Weapon: put away (Q)"; pressing it is the Q key.
var holster_button: Button
var _help_col: Control = null
var _hint_row: Control = null
## The one-line hint's job is done (the old yard's: the first selection, the end of the run, or a window too
## narrow for it; avatar mode's, which is two short lines that fit any window: the player has asked somebody for something over
## the radio, or the run has ended): it does not come back. Whether it shows now also depends on the player's
## settings (hints on: Prefs ui/hints) and, in avatar mode, on the dock, the help and the News being shut, see _refresh_hint.
var hint_spent := false
## The town's keys legend (key_legend.gd) is wanted now: what `_refresh_hint` works out for the bar in the school's game.
var legend_wanted := false
## The hint was spent only because the window was too narrow for the old yard's (avatar mode, which may be told a moment later, has one that fits).
var _hint_spent_by_width := false
## The one-line message near the bottom centre (see toast()).
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
## The colour of the level of the toast now up (its bar, with the frame).
var toast_col := INFO
var toast_seconds := TOAST_SECONDS
## The offer of the Map on leaving the base (round 23, avatar mode: scripts/sim/gate.gd `leave_offer`): a card above the toast, a click on it (or E) opens the Map.
var leave_card: PanelContainer
var leave_label: Label
var last_speed := -1
## Round 17, the radio's views (scripts/ui/radio_verbs.gd, call_card.gd, news_panel.gd; avatar mode only, see `_sync_radio`). The
## dock's `radio_box` holds the verbs (`radio_verbs`) of the selected person in place of the order buttons; `call_card` hangs under the
## alerts in the right column; `news_panel` is the log, opened by `news_button` (with its `news_dot` while there is something unread:
## key T), in the free band above the toolbar; `alarm_button` rings the call to arms. (How many alerts the feed shows is worked out afresh
## by `_layout_news` each time, from the room the column has: it is not remembered.)
var radio_box: PanelContainer
var radio_verbs
var call_card
## Round 24: the key that picks each person of the crew (1 to 5, by card order: `WheelCtl.crew_of`), person to number; empty without an avatar.
var crew_keys := {}
## HUDB: a part of the town (scripts/ui/crew_marks.gd) that puts one status chip in a corner of each crew card sets this: `(person, marks) -> marks`, the foot row's marks
## without the ones the chip already shows. Not valid in any other game, and the foot row is then as it always was.
var mark_filter: Callable
## Round 24: the command wheel (scripts/ui/command_wheel.gd), a view on top of everything in the HUD that main.gd's controller (wheel_ctl.gd) opens and moves.
var wheel
## Round 18: the radio panel (scripts/ui/radio_panel.gd), the colony's interface in avatar mode, with the pages Jobs, Build, Map and News;
## `news_panel` is its News page (the log of round 17, still the object the News wrappers and the tests speak to).
var radio_panel
var news_panel
var news_button: Button
var news_dot: Control
var alarm_button: Button
var _call_seen := false
## True while the clock's forecast lines are put away to leave a call card its room (see `_layout_news`).
var _forecast_squeezed := false
## The look of the HUD for the kind of game: "" is the school's (everything), "one_house" is the town's calm one (One House: the Town Board,
## Scavenge, the car's fuel and the school's crew-seats strip are put away; the rest is the same). Set by `set_profile`.
var profile := ""


func setup(game_data: Dictionary, crew: Array) -> void:
	data = game_data
	people = crew
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _tooltip_theme()
	for key in data.icons:
		icons[key] = GD.tex(data.icons[key])
	# the icons the HUD brought itself (not in the baked data): the menu button's three bars
	for key in EXTRA_ICONS:
		if not icons.has(key):
			icons[key] = GD.tex(EXTRA_ICONS[key])
	_build_stores()
	_build_bar()
	_build_clock()
	_build_ammo()
	_build_alerts()
	_build_banner()
	_build_dock()
	_build_speed()
	_build_help()
	_build_hint()
	_build_toast()
	_build_leave_card()
	_build_radio_ui()
	_build_talk_card()
	wheel = CommandWheel.new()
	add_child(wheel)
	resized.connect(_on_resized)
	_on_resized()
	# One House (WP7): a town run (the run's meta says so, or the data does) wears the town's calm profile; the town's HUD part and the first
	# update (`is_one_house`) say it too, whichever comes first
	var run = Engine.get_meta("run", {}) if Engine.has_meta("run") else {}
	if bool(game_data.get("one_house", false)) or (run is Dictionary and bool(run.get("town", false))):
		set_profile("one_house")


## The HUD's profile: "one_house" puts away what only the school has (the Town Board's button, Scavenge, the car's fuel and the crew-seats strip); "" is the
## school's whole HUD. Nothing else changes: the rules' own modules decide what is shown of them.
func set_profile(name: String) -> void:
	if name == profile:
		return
	profile = name
	var school := name == ""
	if town_button != null:
		town_button.visible = town_button.visible and school
	if crew_load_panel != null and not school:
		crew_load_panel.visible = false
	if help_g != null and not school:
		help_g.text = "Map"
	if not school:
		_layout_dock.call_deferred()
		if help != null:
			_fill_help()    # (the town's controls: one way to command the crew)
			if help_g != null:
				help_g.text = "Map"
		_speed_tips()
		_town_tips()
		if hint != null:
			_fill_hint()    # (the town's words)
		# (HUDA: the town's calmer alert feed and slim stores; the keys' legend is the town part's, scripts/ui/key_legend.gd)
		if _alert_feed == null and alerts_box != null and right_col != null:
			_alert_feed = AlertFeed.new(self)
			_alert_feed.make_pill(right_col, alerts_box)
		if _stores_calm == null and res_panel != null:
			_stores_calm = StoresCalm.new(self)


# ----------------------------------------------------------------- frames --

## The noticeboard's pictures (scripts/ui/frames.gd, made by ART from assets/ui/theme) are
## used wherever the one a surface asks for is there; the flat chalkboard look below is what
## every surface falls back on when it is not. It is loaded when first asked for, so a
## checkout without the frames still runs. A test switches the frames off to see the flat look.
const FRAMES_PATH := "res://scripts/ui/frames.gd"
## The frames the HUD, the dialog and the report card wear, where each is used (tests/test_hud_look.gd
## checks that the theme has them all). `bubble` is worn by what people say in the world: the speech
## bubbles of scripts/render/overlay_node.gd ask for it through `frame`.
const FRAME_KINDS := [
	"panel", "panel_slim", "panel_inset", "clock", "card", "card_selected", "slip", "paper", "tooltip", "toast", "banner",
	"chip", "pill", "bar_track", "button", "button_hover", "button_pressed", "button_off", "button_primary", "button_primary_hover",
	"bubble",
]
static var use_frames := true
static var _frames_script = null
static var _frames_looked := false


static func _frames():
	if not _frames_looked:
		_frames_looked = true
		if ResourceLoader.exists(FRAMES_PATH):
			_frames_script = load(FRAMES_PATH)
	return _frames_script


## Whether the frame `kind` ("panel", "clock", "slip"...) is there to use.
static func has_frame(kind: String) -> bool:
	if not use_frames or kind == "":
		return false
	var f = _frames()
	return f != null and bool(f.has(kind))


## A new style box of the frame `kind` tinted `tint`, or null when there is none. The box
## remembers which frame it is (meta "frame"), which the tests read the colours behind text from.
static func frame(kind: String, tint: Color = Color.WHITE) -> StyleBox:
	if not has_frame(kind):
		return null
	var box = _frames().box(kind, tint)
	if box != null:
		box.set_meta("frame", kind)
	return box


## The average colour of the middle of the frame `kind`, as frames.json says it; `fallback`
## when there is no such frame.
static func frame_avg(kind: String, fallback: Color) -> Color:
	if not has_frame(kind):
		return fallback
	var text := String(_frames().info(kind).get("avg", ""))
	return Color.html(text) if text.is_valid_html_color() else fallback


# ---------------------------------------------------------------- helpers --

## The look of a tooltip: the noticeboard's panel (or the flat slate one), ink and font.
## Only the two tooltip types are set (the controls under the HUD find them through their
## parents; the rest of the look is still set control by control).
func _tooltip_theme() -> Theme:
	var t := Theme.new()
	var sb := _style(Color(32 / 255.0, 48 / 255.0, 43 / 255.0, 0.98), 6, LINE2, false, "tooltip")
	if sb is StyleBoxFlat:
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
	t.set_stylebox("panel", "TooltipPanel", sb)
	t.set_font("font", "TooltipLabel", Fonts.sans(400))
	t.set_font_size("font_size", "TooltipLabel", 13)
	t.set_color("font_color", "TooltipLabel", INK)
	return t


## The flat look of a surface: a slate board with a thin chalk edge (and a shadow).
func _flat(bg: Color = PANEL, radius: int = 6, border: Color = LINE, shadow: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.38)
		s.shadow_size = 12
		s.shadow_offset = Vector2(0, 5)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


## The look of a panel. With `kind` (the name of a frame: "panel", "clock", "slip"...) and that
## frame there, the frame (tinted `tint`); else the flat style of `bg`, `radius`, `border` and
## `shadow`, as before. Without a `kind` it is always the flat style.
func _style(bg: Color = PANEL, radius: int = 6, border: Color = LINE, shadow: bool = true, kind: String = "", tint: Color = Color.WHITE) -> StyleBox:
	if kind != "":
		var f := frame(kind, tint)
		if f != null:
			return f
	return _flat(bg, radius, border, shadow)


## A page of notebook paper for a modal: the 'paper' frame, or flat a sheet of paper with a
## dark edge. The ink on it is PAPER_INK and its greys (never the chalk colours).
func _paper_style() -> StyleBox:
	var f := frame("paper")
	if f != null:
		return f
	var s := _flat(PAPER, 6, Color(PAPER_INK, 0.55), true)
	s.shadow_color = Color(0, 0, 0, 0.5)
	return s


## A panel container; without a style it is a noticeboard panel.
func _panel(style: StyleBox = null) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style if style != null else _style(PANEL, 6, LINE, true, "panel"))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


## A label. Nothing is set under Fonts.MIN_PX: a smaller size is raised to it.
func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", maxi(size, Fonts.MIN_PX))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A small heading in capitals; `color` is INK3, the dim chalk, unless it is on paper.
func _caps(text: String, color: Color = INK3) -> Label:
	return _label(text.to_upper(), Fonts.cond(600, 1), 12, color)


func _icon(name: String, size: int, color: Color = Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icons.get(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _hbox(sep: int) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _vbox(sep: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A key chip: the key's name (a letter, "Tab", "Right-click") in a small
## rounded box, 12 px. `on_gold` is for a chip on a gold button.
func _kbd(text: String, on_gold: bool = false) -> PanelContainer:
	# a keycap: the chip frame on the dark boards; flat on a gold button, where it is only a wash of dark
	var s: StyleBox = null if on_gold else frame("chip")
	if s == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(ACCENT_INK, 0.12) if on_gold else Color(0.93, 0.96, 0.89, 0.1)
		f.border_color = Color(ACCENT_INK, 0.35) if on_gold else LINE2
		f.set_border_width_all(1)
		f.set_corner_radius_all(3)
		f.content_margin_left = 4
		f.content_margin_right = 4
		f.content_margin_top = 0
		f.content_margin_bottom = 1
		s = f
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := _label(text, Fonts.cond(600), 12, ACCENT_INK if on_gold else INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _corner(c: Control, right: bool, bottom: bool, x: float, y: float) -> void:
	c.anchor_left = 1.0 if right else 0.0
	c.anchor_right = c.anchor_left
	c.anchor_top = 1.0 if bottom else 0.0
	c.anchor_bottom = c.anchor_top
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	if right:
		c.offset_right = -x
	else:
		c.offset_left = x
	if bottom:
		c.offset_bottom = -y
	else:
		c.offset_top = y


func _center_top(c: Control, y: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.offset_top = y


# ----------------------------------------------------------------- stores --

func _build_stores() -> void:
	res_panel = _panel()
	var grid := GridContainer.new()
	res_grid = grid
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in STORES:
		var ic := _icon(s[0], 14, INK3)
		var k := _label(s[1], Fonts.sans(400), 13, INK2)
		var v := _label("0", Fonts.cond(600), 15, INK)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size.x = 34
		res_values[s[0]] = v
		if s[0] in DAYS_STORES:
			# the days left sit under the number; the icon and name stay level with it
			var d := _label("", Fonts.cond(600), 12, INK3)
			d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			res_days[s[0]] = d
			var cell := _vbox(0)
			cell.add_child(v)
			cell.add_child(d)
			var line_h := v.get_minimum_size().y
			grid.add_child(_padded(ic, int((line_h - 14.0) * 0.5)))
			var kp := _padded(k, int((line_h - k.get_minimum_size().y) * 0.5))
			res_labels.append(kp)
			grid.add_child(kp)
			grid.add_child(cell)
		else:
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(ic)
			res_labels.append(k)
			grid.add_child(k)
			grid.add_child(v)
	# round 13: the fuel row, there only in a settlement game with a vehicle or some fuel (the grid leaves out what is hidden)
	var fuel_ic := _icon("fuel", 14, INK3)
	fuel_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fuel_k := _label("Fuel", Fonts.sans(400), 13, INK2)
	var fuel_v := _label("0", Fonts.cond(600), 15, INK)
	fuel_v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fuel_v.custom_minimum_size.x = 34
	res_values["fuel"] = fuel_v
	fuel_cells = [fuel_ic, fuel_k, fuel_v]
	for c in fuel_cells:
		c.visible = false
		grid.add_child(c)
	res_panel.add_child(grid)
	res_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left_col = _vbox(8)
	left_col.add_child(res_panel)
	left_col.add_child(_build_crew_load())
	left_col.add_child(_build_legend())
	add_child(left_col)
	_corner(left_col, false, false, 12, 12)


## The crew-load strip (round 16): a small stamp under the stores, an icon and "Seats 5 of 11"; a click opens the Duty roster.
func _build_crew_load() -> PanelContainer:
	crew_load_panel = PanelContainer.new()
	crew_load_panel.add_theme_stylebox_override("panel", _crew_load_style(false))
	crew_load_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	crew_load_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	crew_load_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	crew_load_panel.visible = false    # (the first update shows it in a settlement game: the classic start never has it)
	crew_load_panel.gui_input.connect(_on_crew_load_input)
	var row := _hbox(6)
	crew_load_icon = _icon("jobs", 14, INK3)
	crew_load_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(crew_load_icon)
	crew_load_label = _label("Seats 0 of 0", Fonts.sans(400), 13, INK)
	row.add_child(crew_load_label)
	crew_load_panel.add_child(row)
	return crew_load_panel


## A small slate stamp (dark enough to read on any ground), its edge amber while the radio desk or the lookout post is empty.
func _crew_load_style(warn: bool) -> StyleBoxFlat:
	var s := _flat(PANEL, 6, Color(WARN, 0.8) if warn else LINE2, false)
	s.content_margin_left = 9
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


func _on_crew_load_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_press_jobs()


## The strip follows the game: the seats staffed, amber while the radio desk or the lookout post is empty, a tooltip that lists
## what is empty. In a narrow window the 'of' goes. It is there in the settlement game only (a small start): the classic start's
## column of stores is as tight as the dock beside it was laid out for, and has no recruits whose seats are to be filled.
func _update_crew_load(sim) -> void:
	if crew_load_panel == null:
		return
	var recruits = sim.get("recruits")
	var on: bool = profile == "" and sim.get("jobs") != null and sim.get("build") != null and recruits != null and bool(recruits.small)
	if crew_load_panel.visible != on:
		crew_load_panel.visible = on
		_layout_dock.call_deferred()
	if not on:
		return
	var r := CrewLoad.report(sim)
	var text: String = ("Seats %s" % String(r.short)) if compact else String(r.text)
	var sig := "%s|%s|%s" % [text, String(r.level), String(r.tip)]
	if sig == _crew_load_sig:
		return
	_crew_load_sig = sig
	var warn: bool = String(r.level) == "warn"
	crew_load_label.text = text
	crew_load_label.add_theme_color_override("font_color", WARN if warn else INK)
	crew_load_panel.add_theme_stylebox_override("panel", _crew_load_style(warn))
	crew_load_icon.modulate = WARN if warn else INK3
	crew_load_panel.tooltip_text = String(r.tip)


## The legend of the fields-of-fire view: a swatch for each tint and what it means.
## Hidden until the view is on (see set_fields).
func _build_legend() -> PanelContainer:
	fields_legend = _panel()
	fields_legend.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# a legend is read, not pressed: clicks pass through it to the world
	fields_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := _vbox(5)
	col.add_child(_caps("Fields of fire"))
	for entry in FIELDS_LEGEND:
		var row := _hbox(8)
		var swatch := Panel.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(entry[0], 0.55)
		st.border_color = entry[0]
		st.set_border_width_all(1)
		st.set_corner_radius_all(3)
		swatch.add_theme_stylebox_override("panel", st)
		swatch.custom_minimum_size = Vector2(16, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		row.add_child(_label(String(entry[1]), Fonts.sans(400), 12, INK2))
		col.add_child(row)
	fields_legend.add_child(col)
	fields_legend.visible = false
	return fields_legend


## `c` with `top` pixels of space above it, so it can sit level with a taller neighbour.
func _padded(c: Control, top: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_top", maxi(0, top))
	m.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	m.add_child(c)
	return m


# ---------------------------------------------------------- colonist bar --

## The hall-pass badge of a crew card: the frame (card, card_selected) or, flat, a slate
## card with a pale laminate edge, gold while it is the selected one.
func _card_style(selected: bool) -> StyleBox:
	var f := frame("card_selected" if selected else "card")
	if f != null:
		return f
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#16221f")
	s.border_color = ACCENT if selected else Color(0.82, 0.78, 0.64, 0.5)
	s.set_border_width_all(2 if selected else 1)
	s.set_corner_radius_all(5)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 4)
	s.anti_aliasing = true
	return s


## How far in from the card's edge its contents sit (left, top, right, bottom): the dark window
## of the hall-pass badge, which is what the frame's content margins are (the badge's rim is
## drawn outside the card's rectangle, by the frame's expand margins), a pixel for the flat card.
func _card_inset() -> Vector4:
	var sb := _card_style(false)
	return Vector4(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP), sb.get_margin(SIDE_RIGHT), sb.get_margin(SIDE_BOTTOM))


## The height of a card `w` wide: inside its rim a square picture, a line for the name and the
## health bar (80 for a 60 flat card, as it always was; a badge with a thick rim is taller).
func _card_height(w: int) -> int:
	var inset := _card_inset()
	return ceili(inset.y + (float(w) - inset.x - inset.z) + 17.0 + 3.0 + inset.w)


func _build_bar() -> void:
	bar = HFlowContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.alignment = FlowContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 4)
	add_child(bar)
	for p in people:
		var c := _make_card(p)
		bar.add_child(c.card)
		cards.append(c)
	_size_cards(60)


## The picture of a person: the one their def names (a recruit's: it is made for them), else the roster's, else
## none (a card with only a name, a panel with no face: a missing file is not an error).
func portrait_of(p) -> Texture2D:
	var path := String(p.def.get("portrait", ""))
	if path == "" and data.has("portraits") and data.portraits.has(p.id):
		path = String(data.portraits[p.id])
	if path == "":
		return null
	if ResourceLoader.exists(path):
		return GD.tex(path)
	# a picture made since the project was last opened in the editor has not been imported yet: read the file itself
	if not _loose_pictures.has(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
		_loose_pictures[path] = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
	return _loose_pictures[path]


static var _loose_pictures := {}


## One crew card, not yet in the row: the hall-pass badge of `p` and the parts _update_card moves.
func _make_card(p) -> Dictionary:
	var card := Panel.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "%s, %s" % [p.name, String(p.def.role).to_lower()]
	card.add_theme_stylebox_override("panel", _card_style(false))
	# nothing sticks out of the picture's window, and the badge's glow reaches outside the card
	card.clip_contents = false
	var pic := TextureRect.new()
	pic.texture = portrait_of(p)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pic)
	# a dark veil and a word over the picture of someone who is gone or away
	var veil := ColorRect.new()
	veil.color = Color(0.03, 0.06, 0.05, 0.62)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.visible = false
	card.add_child(veil)
	var word := _label("", Fonts.cond(700, 1), 12, INK2)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# it sits on a picture: a dark edge keeps it readable over any face
	word.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.035, 0.9))
	word.add_theme_constant_override("outline_size", 3)
	card.add_child(word)
	var nm := _label(p.first, Fonts.cond(600), 13, INK)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# a long name (a recruit's) is trimmed with a dot dot dot, not spilled over the next card (the tooltip has it whole)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(nm)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0.03, 0.02, 0.55)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hp_bg)
	var hp := ColorRect.new()
	hp.color = OK
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hp)
	var badge := Panel.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = ACCENT
	bs.set_corner_radius_all(9)
	bs.anti_aliasing = true
	badge.add_theme_stylebox_override("panel", bs)
	badge.size = Vector2(17, 17)
	badge.position = Vector2(3, 3)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bi := _icon("draft", 11, ACCENT_INK)
	bi.position = Vector2(3, 3)
	bi.size = Vector2(11, 11)
	badge.add_child(bi)
	badge.visible = false
	card.add_child(badge)
	# the stance the radio has put them in, in words (avatar mode): a small gold tag in the corner of the picture
	var stance_box := PanelContainer.new()
	var sts := StyleBoxFlat.new()
	sts.bg_color = ACCENT
	sts.set_corner_radius_all(4)
	sts.anti_aliasing = true
	sts.content_margin_left = 3
	sts.content_margin_right = 3
	sts.content_margin_top = 0
	sts.content_margin_bottom = 0
	stance_box.add_theme_stylebox_override("panel", sts)
	stance_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stance := _label("", Fonts.cond(700, 0), 12, ACCENT_INK)
	stance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stance_box.add_child(stance)
	stance_box.visible = false
	card.add_child(stance_box)
	# "YOU" on the card of the person the player plays (round 17): a small gold tag in the corner of the picture
	var you := PanelContainer.new()
	var ys := StyleBoxFlat.new()
	ys.bg_color = ACCENT
	ys.set_corner_radius_all(4)
	ys.anti_aliasing = true
	ys.content_margin_left = 3
	ys.content_margin_right = 3
	ys.content_margin_top = 0
	ys.content_margin_bottom = 0
	you.add_theme_stylebox_override("panel", ys)
	you.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var you_word := _label("YOU", Fonts.cond(700, 1), 12, ACCENT_INK)
	you_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	you.add_child(you_word)
	you.size = Vector2(30, 15)
	you.visible = false
	card.add_child(you)
	# the key that picks them in avatar mode (round 24: 1 to 5, by card order, not counting you): small, at the foot of the picture
	var key := _label("", Fonts.cond(700, 0), 12, INK)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.035, 0.95))
	key.add_theme_constant_override("outline_size", 4)
	key.size = Vector2(14, 15)
	key.visible = false
	card.add_child(key)
	var fight := Panel.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = DANGER
	fs.set_corner_radius_all(4)
	fs.anti_aliasing = true
	fight.add_theme_stylebox_override("panel", fs)
	fight.size = Vector2(7, 7)
	fight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fight.visible = false
	card.add_child(fight)
	# the status marks (hungry, bleeding, feverish...) along the foot of the picture
	var marks_box := PanelContainer.new()
	var ms := StyleBoxFlat.new()
	ms.bg_color = Color(0.03, 0.06, 0.05, 0.74)
	ms.set_corner_radius_all(7)
	ms.content_margin_left = 2
	ms.content_margin_right = 2
	ms.content_margin_top = 2
	ms.content_margin_bottom = 2
	ms.anti_aliasing = true
	marks_box.add_theme_stylebox_override("panel", ms)
	marks_box.mouse_filter = Control.MOUSE_FILTER_PASS
	marks_box.visible = false
	var marks := _hbox(0)
	marks_box.add_child(marks)
	card.add_child(marks_box)
	card.gui_input.connect(_on_card_input.bind(p))
	return {"card": card, "p": p, "pic": pic, "name": nm, "hp_bg": hp_bg, "hp": hp, "badge": badge, "stance_box": stance_box, "stance": stance, "you": you, "key": key, "fight": fight, "sel": false, "veil": veil, "word": word, "marks_box": marks_box, "marks": marks, "marks_sig": "", "marks_data": [], "state": "", "epitaph": ""}


## Someone has joined the crew (a recruit at the gate): their card goes in the row, and the row is laid out again.
## A person who has a card is left alone.
func add_person(p) -> void:
	for c in cards:
		if c.p == p:
			return
	if not people.has(p):
		people.append(p)
	var c := _make_card(p)
	bar.add_child(c.card)
	cards.append(c)
	_layout_bar()
	if sim_ref != null:
		_update_card(c, sim_ref)


## A card lit for a moment (someone has arrived): it comes up bright and settles back.
func flash_card(p) -> void:
	for c in cards:
		if c.p != p:
			continue
		var card: Panel = c.card
		card.modulate = Color(1.25, 1.2, 1.08) if Access.reduce_flashes() else Color(1.75, 1.6, 1.15)    # (Reduce flashes: a faint glow, not a bright one)
		if not is_inside_tree():
			card.modulate = Color.WHITE
			return
		var t := create_tween()
		if _calm():
			t.tween_interval(1.4)
			t.tween_callback(func(): card.modulate = Color.WHITE)
		else:
			t.tween_interval(0.5)
			t.tween_property(card, "modulate", Color.WHITE, 1.2)
		return


## Gives a card to everyone in `crew` who has none (the HUD is shown the crew each update, so a person who arrives
## after it was built is not missed).
func _sync_cards(crew: Array) -> void:
	for p in crew:
		add_person(p)


func _size_cards(w: int) -> void:
	var h := _card_height(w)
	var was := mark_px
	mark_px = 12 if w >= 56 else 11
	mark_max = 4 if w >= 56 else (3 if w >= 48 else 2)
	# the picture, the name and the health bar sit inside the badge's rim (a pixel on the flat card)
	var inset := _card_inset()
	var pw := float(w) - inset.x - inset.z
	for c in cards:
		c.card.custom_minimum_size = Vector2(w, h)
		c.pic.position = Vector2(inset.x, inset.y)
		c.pic.size = Vector2(pw, pw)
		c.veil.position = c.pic.position
		c.veil.size = c.pic.size
		c.word.position = c.pic.position
		c.word.size = c.pic.size
		# the name takes the room between the picture and the health bar
		var bar_top := h - inset.w - 3.0
		c.name.position = Vector2(inset.x, inset.y + pw)
		c.name.size = Vector2(pw, bar_top - (inset.y + pw))
		c.name.add_theme_font_size_override("font_size", 13 if w >= 56 else 12)
		c.hp_bg.position = Vector2(inset.x, bar_top)
		c.hp_bg.size = Vector2(pw, 3)
		c.hp.position = c.hp_bg.position
		c.fight.position = Vector2(inset.x + pw - 11.0, inset.y + 4.0)
		c.badge.position = Vector2(inset.x + 2.0, inset.y + 2.0)
		c.stance_box.position = Vector2(inset.x + 2.0, inset.y + 2.0)
		c.you.position = Vector2(inset.x + 2.0, inset.y + 2.0)
		c.key.position = Vector2(inset.x + pw - 16.0, inset.y + pw - 17.0)
		c.marks_box.position = Vector2(inset.x + 2.0, inset.y + pw - 1.0 - mark_px - 4.0)
		if was != mark_px:
			_fill_marks(c, c.marks_data)


## How `n` cards are laid out: {"w" (a card's width), "rows", "per_row", "gap", "roam"}. `std` is the width cards
## have when they fit (60, or 48 in a narrow window), `sym` how wide a row may be when it is centred on the window
## and `free` how wide when it may sit anywhere between the stores and the clock. Six or fewer (the classic crew,
## and a small start's three) are laid out as they always were. More take one row if one fits, then two, then
## three; a row is kept centred if it can be, and shrinks the cards (never under 44) before it takes another row.
static func plan_cards(n: int, std: int, sym: float, free: float) -> Dictionary:
	if n <= 6:
		return {"w": std, "rows": 1, "per_row": maxi(n, 1), "gap": 6, "roam": false}
	var gap := 4
	var widths: Array = []
	var k := std
	while k >= 48:
		widths.append(k)
		k -= 4
	widths.append(44)
	for rows in range(1, 4):
		var per_row := ceili(float(n) / float(rows))
		for roam in [false, true]:
			var room := free if roam else sym
			for w in widths:
				if float(per_row * w + (per_row - 1) * gap) <= room:
					return {"w": w, "rows": rows, "per_row": per_row, "gap": gap, "roam": roam}
	# not even then (a very narrow window): the smallest cards, as many rows as it takes
	var fit := maxi(1, int((free + float(gap)) / float(44 + gap)))
	return {"w": 44, "rows": ceili(float(n) / float(fit)), "per_row": fit, "gap": gap, "roam": true}


## The room the cards have across the top: how wide a row may be when it is centred on the window ("sym") and
## when it may sit anywhere between the stores and the clock ("free"), and the middle of that stretch ("mid").
## (In a window under 640 wide the cards are along the bottom and have all of it.)
func _bar_room() -> Dictionary:
	var w := size.x
	if w < 640.0:
		return {"sym": w - 16.0, "free": w - 16.0, "mid": w * 0.5}
	# the columns are as wide as they are now (or as they will be: the clock is never narrower than its floor)
	var from := 12.0 + maxf(left_col.get_combined_minimum_size().x, left_col.size.x) + BAR_MARGIN
	var to := w - 12.0 - maxf(maxf(right_col.get_combined_minimum_size().x, right_col.size.x), float(CLOCK_W_COMPACT if compact else CLOCK_W)) - BAR_MARGIN
	return {"sym": 2.0 * minf(w * 0.5 - from, to - w * 0.5), "free": to - from, "mid": (from + to) * 0.5}


## Sizes the cards and the row they are in for as many people as there are, in the room there is (a crew that has
## grown has more cards than a row holds). Under the cards, the banner hangs below the last row.
func _layout_bar() -> void:
	if bar == null or left_col == null or right_col == null:
		return
	var room := _bar_room()
	var sig := "%d|%s|%s|%s" % [cards.size(), str(size.x), str(snappedf(float(room.sym), 0.5)), str(snappedf(float(room.free), 0.5))]
	if sig == _bar_sig:
		return
	_bar_sig = sig
	var plan := plan_cards(cards.size(), 48 if compact else 60, float(room.sym), float(room.free))
	bar_plan = plan
	_size_cards(int(plan.w))
	bar.add_theme_constant_override("h_separation", int(plan.gap))
	bar.custom_minimum_size.x = float(int(plan.per_row) * int(plan.w) + (int(plan.per_row) - 1) * int(plan.gap))
	var shift := float(room.mid) - size.x * 0.5 if bool(plan.roam) else 0.0
	bar.offset_left = shift
	bar.offset_right = shift
	if banner != null and size.x >= 640.0:
		var rows := int(plan.rows)
		var bar_h := float(rows * _card_height(int(plan.w)) + (rows - 1) * 4)
		banner.offset_top = maxf(118.0, 10.0 + bar_h + 22.0)


func _on_card_input(ev: InputEvent, p) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		# (One House: a click on a card opens the order wheel, and that is all it does: no second click that takes the camera away)
		if ev.double_click and profile == "":
			on_focus.call(p)
		else:
			on_select.call({"kind": "person", "ref": p})
		accept_event()


# ------------------------------------------------------------------ clock --

## The phase chip's look: a faint stamp of the phase's colour (the pill frame tinted by it, or
## flat a wash of it).
func _chip_style(c: Color) -> StyleBox:
	var f := frame("pill", Color(c, 0.2))
	if f != null:
		return f
	var s := StyleBoxFlat.new()
	s.bg_color = Color(c, 0.17)
	s.set_corner_radius_all(3)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 2
	s.content_margin_bottom = 3
	return s


## The look of a small toolbar button that may be lit (the speed in use, the fields view): clear
## while it is off; lit, a faint gold key (the main-choice button frame, mostly clear) or flat a
## wash of gold.
func _lit_look(on: bool) -> StyleBox:
	if on:
		var f := frame("button_primary", Color(1, 1, 1, 0.34))
		if f != null:
			return f
	var st := StyleBoxFlat.new()
	st.bg_color = Color(ACCENT, 0.16) if on else Color(0, 0, 0, 0)
	st.set_corner_radius_all(4)
	return st


## The "PAUSED" stamp in the clock's top row, beside the phase chip: a pale pill
## with a pause mark and the word, shown while the game is paused (update_hud).
func _build_paused_pill() -> PanelContainer:
	# a pale stamp: the pill frame, or a flat pale pill
	var s: StyleBox = frame("pill")
	if s == null:
		var f := StyleBoxFlat.new()
		f.bg_color = INK
		f.set_corner_radius_all(9)
		f.anti_aliasing = true
		f.content_margin_left = 6
		f.content_margin_right = 7
		f.content_margin_top = 1
		f.content_margin_bottom = 2
		s = f
	paused_pill = PanelContainer.new()
	paused_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paused_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paused_pill.add_theme_stylebox_override("panel", s)
	var row := _hbox(3)
	var ic := _icon("pause", 11, ACCENT_INK)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	paused_label = _label("PAUSED", Fonts.cond(700, 1), 12, ACCENT_INK)
	row.add_child(paused_label)
	paused_pill.add_child(row)
	paused_pill.visible = false
	return paused_pill


func _build_clock() -> void:
	# a brass-rimmed face: the frame, or flat a slate board with a brass edge
	var face := _style(PANEL, 6, Color(BRASS, 0.75), true, "clock")
	if face is StyleBoxFlat:
		face.set_border_width_all(2)
	clock = _panel(face)
	var v := _vbox(6)
	var r1 := _hbox(8)
	day_label = _caps("Day 3")
	r1.add_child(day_label)
	r1.add_child(_spacer())
	r1.add_child(_build_paused_pill())
	phase_chip = PanelContainer.new()
	phase_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := _hbox(5)
	phase_icon = _icon("sun", 12)
	phase_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(phase_icon)
	phase_label = _label("DAY", Fonts.cond(700, 1), 12, ACCENT)
	chip.add_child(phase_label)
	phase_chip.add_child(chip)
	r1.add_child(phase_chip)
	v.add_child(r1)
	# round 19: the badge of a Big Night, in a row of its own (the day counter's row has no room for it), there only in avatar mode
	night_badge = PanelContainer.new()
	night_badge.mouse_filter = Control.MOUSE_FILTER_PASS
	night_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	night_badge.add_theme_stylebox_override("panel", _chip_style(DANGER))
	var badge_row := _hbox(5)
	night_badge_icon = _icon("bell", 13, DANGER_TEXT)
	night_badge_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_row.add_child(night_badge_icon)
	night_badge_label = _label("Big Night tomorrow", Fonts.cond(700, 1), 12, DANGER_BADGE)
	badge_row.add_child(night_badge_label)
	night_badge.add_child(badge_row)
	night_badge.visible = false
	v.add_child(night_badge)
	var r2 := _hbox(8)
	time_label = _label("18:46", Fonts.cond(600), 30, INK)
	r2.add_child(time_label)
	r2.add_child(_spacer())
	until_label = _label("", Fonts.sans(400), 12, INK2)
	until_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	until_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r2.add_child(until_label)
	v.add_child(r2)
	strip = Strip.new()
	strip.custom_minimum_size = Vector2(0, 16)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(strip)
	var r4 := _hbox(5)
	temp_icon = _icon("sun", 13, INK3)
	temp_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r4.add_child(temp_icon)
	temp_label = _label("", Fonts.sans(400), 12, INK2)
	r4.add_child(temp_label)
	r4.add_child(_spacer())
	var wi := _icon("walker", 13, INK3)
	wi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r4.add_child(wi)
	walkers_label = _label("", Fonts.sans(400), 12, INK2)
	r4.add_child(walkers_label)
	v.add_child(r4)
	# (round 22) in avatar mode, the gate under them (above the forecast, which is put away first when a call needs the room): a lamp and a word, with the tooltip that says what the lever does
	gate_row = _hbox(6)
	gate_row.mouse_filter = Control.MOUSE_FILTER_PASS
	gate_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gate_row.gui_input.connect(_on_gate_row_input)
	gate_row.tooltip_text = GateKit.TIP
	gate_lamp = Lamp.new()
	gate_lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gate_row.add_child(gate_lamp)
	gate_label = _label("Gate: shut", Fonts.sans(400), 12, INK2)
	gate_label.mouse_filter = Control.MOUSE_FILTER_PASS
	gate_label.tooltip_text = GateKit.TIP
	gate_row.add_child(gate_label)
	gate_row.visible = false
	v.add_child(gate_row)
	# the lookout's forecast, once it is given (see update_hud); a long one wraps
	forecast_label = _label("", Fonts.sans(400), 12, INK2)
	forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forecast_label.visible = false
	v.add_child(forecast_label)
	# (round 19) and under it, in avatar mode, the community's own reading of the night
	ready_label = _label("", Fonts.sans(400), 12, OK)
	ready_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ready_label.tooltip_text = NightKit.READY_TIP
	ready_label.mouse_filter = Control.MOUSE_FILTER_PASS
	ready_label.visible = false
	v.add_child(ready_label)
	clock.add_child(v)
	# a small brass bell on the clock's top edge once the dusk bell has rung (see update_hud); it is
	# set by hand in a layer of its own, so it takes no room in the clock
	var bell_layer := Control.new()
	bell_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.add_child(bell_layer)
	clock_bell = _icon("bell", 20, BRASS)
	clock_bell.size = Vector2(20, 20)
	clock_bell.mouse_filter = Control.MOUSE_FILTER_PASS
	clock_bell.tooltip_text = "The bell has rung: everyone is at their post for the night"
	clock_bell.visible = false
	bell_layer.add_child(clock_bell)
	clock.resized.connect(_place_bell)
	clock.custom_minimum_size.x = CLOCK_W
	_place_bell()
	# the alerts hang from the clock, so a taller clock pushes them down
	right_col = _vbox(13)
	right_col.add_child(clock)
	add_child(right_col)
	_corner(right_col, true, false, 12, 12)


## The bell sits across the clock's top edge, a little in from the left. Its layer starts at the
## clock's inner corner (inside the frame's margins), so the margins are taken off.
func _place_bell() -> void:
	if clock == null or clock_bell == null:
		return
	var sb := clock.get_theme_stylebox("panel")
	clock_bell.position = Vector2(15.0 - sb.get_margin(SIDE_LEFT), -10.0 - sb.get_margin(SIDE_TOP))


## The readout of the avatar's gun (round 17), under the clock: the weapon's name, "12 / 340" (the magazine, the stock) and a bar.
## Hidden until avatar mode (`set_avatar`, or the first update that sees a player).
func _build_ammo() -> void:
	ammo_panel = _panel(_style(PANEL, 6, LINE, true, "panel_slim"))
	ammo_panel.size_flags_horizontal = Control.SIZE_FILL
	var v := _vbox(4)
	var r1 := _hbox(8)
	ammo_name = _label("", Fonts.cond(600, 1), 12, INK3)
	ammo_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ammo_name.clip_text = true
	ammo_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ammo_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(ammo_name)
	ammo_label = _label("0 / 0", Fonts.cond(700, 0), 24, INK)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r1.add_child(ammo_label)
	v.add_child(r1)
	ammo_bar = Bar.new()
	ammo_bar.custom_minimum_size = Vector2(0, 6)
	ammo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_bar.color = ACCENT
	v.add_child(ammo_bar)
	holster_button = RadioKit.small_button(self, AimMode.BUTTON_DRAWN, 22.0, 12)
	holster_button.tooltip_text = AimMode.BUTTON_TIP_DRAWN
	holster_button.pressed.connect(_on_holster_pressed)
	v.add_child(holster_button)
	ammo_panel.add_child(v)
	ammo_panel.tooltip_text = AMMO_TIP
	ammo_panel.visible = avatar_ui
	right_col.add_child(ammo_panel)
	right_col.move_child(ammo_panel, 1)


## The weapon button was pressed: the Q key's own work (main.gd), or, with nobody to ask, the state itself.
func _on_holster_pressed() -> void:
	if on_holster.is_valid():
		on_holster.call()
	else:
		AimMode.set_holstered(not AimMode.holstered)
		update_holster()


## The weapon button and the readout say whether the weapon is drawn or put away (the readout is dimmed, and amber says it is not in hand).
func update_holster() -> void:
	if holster_button == null:
		return
	var away: bool = AimMode.holstered
	var words: String = AimMode.BUTTON_AWAY if away else AimMode.BUTTON_DRAWN
	if holster_button.text != words:
		holster_button.text = words
	var holster_tip := AimMode.button_tip(away, profile != "")    # (kept in line each time: the town's words come when the profile does, and the aim setting changes them)
	if holster_button.tooltip_text != holster_tip:
		holster_button.tooltip_text = holster_tip
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		holster_button.add_theme_color_override(state, WARN if away else INK2)
	var dim := 0.5 if away else 1.0
	ammo_label.modulate.a = dim
	ammo_name.modulate.a = dim
	ammo_bar.modulate.a = dim


## The readout's tooltip: what the two numbers are, and where rounds come from.
const AMMO_TIP := "Rounds you can fire / rounds in the stores.\nShots are taken from the stores: rounds come from the stores, so with fewer in them than the magazine holds that is all you can fire.\nR reloads."
## How low a magazine is before the readout warns: this share of its size (and never less than one round).
const AMMO_LOW := 0.25


## The readout follows the avatar: the weapon, the rounds in it and in the stores (amber when the magazine is low, red when the
## stores cannot feed another round), and the bar, which is the reload while there is one and else the magazine.
func _update_ammo(sim) -> void:
	if ammo_panel == null:
		return
	var me = sim.avatar.player() if sim.get("avatar") != null else null
	set_avatar(me != null)
	if me == null:
		return
	var gun: Dictionary = me.gun
	var melee: bool = bool(gun.get("melee", false))
	var cap := int(gun.get("mag", 0))
	var stock: float = float(sim.stock.ammo)
	var dry: bool = not melee and stock < float(sim.shot_cost(me))
	var low: bool = not melee and me.mag <= maxi(1, ceili(float(cap) * AMMO_LOW))
	# the rounds that can be fired: shots are taken from the stores (a reload takes nothing), so a magazine of six over one round in
	# the stores is one round to fire, and with the stores dry there is nothing in the magazine to speak of
	var rounds := floori(stock)
	var ready: int = mini(me.mag, rounds)
	var short: bool = not melee and rounds < cap
	ammo_name.text = String(gun.get("name", me.weapon))
	ammo_label.text = "-" if melee else "%d / %d" % [ready, rounds]
	# a round fired from a low magazine (and the last one above all) makes the readout flash: it is hard to miss that it is running out
	if not melee and _ammo_seen >= 0 and me.mag < _ammo_seen and (low or me.mag <= 0):
		pulse_ammo(me.mag <= 0)
	_ammo_seen = -1 if melee else me.mag
	var col := INK
	if dry:
		col = DANGER_TEXT
	elif low or short:
		col = WARN
	ammo_label.add_theme_color_override("font_color", col)
	if Access.markers() and not melee and (dry or low or short):
		ammo_label.text = ("!! " if dry else "! ") + ammo_label.text    # (Colour-blind markers: the amber and the red of the rounds are marks too)
	if me.reloading > 0.0:
		var total: float = maxf(0.01, float(gun.get("reload", 1.0)) * float(sim.traits.mult(me, "reload")))
		ammo_bar.value = clampf(1.0 - me.reloading / total, 0.0, 1.0)
		ammo_bar.color = ACCENT
	else:
		ammo_bar.value = 1.0 if melee or cap <= 0 else clampf(float(me.mag) / float(cap), 0.0, 1.0)
		ammo_bar.color = col if col != INK else Color(0.82, 0.78, 0.64, 0.8)
	ammo_bar.queue_redraw()
	update_holster()


## The magazine's rounds at the last look (-1: none, or a gun with no magazine), and the flash of the readout when it runs low.
var _ammo_seen := -1
var _ammo_tween: Tween = null


## The readout's flash: it swells a little and goes bright and back in under a fifth of a second, longer and brighter for the last round (and
## for a trigger pulled on an empty gun, main.gd). Under "reduce motion" nothing moves: the amber and the red of the number already say it.
func pulse_ammo(last: bool) -> void:
	if Access.calm_flashes() or ammo_label == null or not ammo_label.is_inside_tree():
		return    # (Reduce motion or Reduce flashes: nothing swells or brightens; the amber and the red of the number say it)
	if _ammo_tween != null and _ammo_tween.is_valid():
		_ammo_tween.kill()
	ammo_label.pivot_offset = Vector2(ammo_label.size.x, ammo_label.size.y * 0.5)
	var bright := Color(2.2, 1.5, 1.2) if last else Color(1.7, 1.45, 1.2)
	var big := 1.3 if last else 1.18
	_ammo_tween = create_tween().set_parallel(true)
	ammo_label.scale = Vector2.ONE * big
	ammo_label.self_modulate = bright
	_ammo_tween.tween_property(ammo_label, "scale", Vector2.ONE, 0.22 if last else 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ammo_tween.tween_property(ammo_label, "self_modulate", Color.WHITE, 0.3 if last else 0.2)


## Whether the player asked for less motion (Prefs ui/reduce_motion): the banner and the toast
## come and go with no fade, the bell does not swing and the fight badge does not pulse.
func _calm() -> bool:
	return Prefs.on("ui", "reduce_motion")


## The bell swings on its hook when the dusk bell first rings (not with reduced motion).
func _swing_bell() -> void:
	if _calm():
		return
	clock_bell.pivot_offset = Vector2(clock_bell.size.x * 0.5, 2.0)
	var t := create_tween()
	for angle in [0.38, -0.3, 0.2, -0.12, 0.06, 0.0]:
		t.tween_property(clock_bell, "rotation", angle, 0.16).set_trans(Tween.TRANS_SINE)


# ----------------------------------------------------------------- alerts --

func _build_alerts() -> void:
	alerts_box = _vbox(int(ALERT_GAP))
	alerts_box.custom_minimum_size.x = CLOCK_W
	right_col.add_child(alerts_box)


## The icon an alert gets: for what it is about (ALERT_ICONS, then a store named in
## its id), else its level's.
func _alert_icon_name(it: Dictionary) -> String:
	var id := String(it.id)
	for pair in ALERT_ICONS:
		if id.begins_with(pair[0]) and icons.has(pair[1]):
			return pair[1]
	for part in id.split("-"):
		if part in STORE_ICONS and icons.has(part):
			return part
	return String(LEVEL_ICON.get(it.level, "warn"))


## Whether alert `a` goes above alert `b` in the feed: the more urgent first, then
## the newer (by the rules' clock, then by when the HUD first saw it).
func _alert_before(a: Dictionary, b: Dictionary) -> bool:
	var ra := _rank(a)
	var rb := _rank(b)
	if ra != rb:
		return ra > rb
	if a.born != b.born:
		return a.born > b.born
	return a.seq > b.seq


## The tint that turns the paper of the slip frame into the slip of `level`: the slip's colour
## over the colour of the paper.
func _slip_tint(level: String) -> Color:
	var c: Color = SLIP.get(level, SLIP.warn)
	var base := frame_avg("slip", PAPER)
	return Color(c.r / base.r, c.g / base.g, c.b / base.b)


## The slip an alert of `level` is written on: the frame tinted for the level, or flat a small
## sheet of the level's paper with a darker edge; a shade lighter while the mouse is on it.
func _slip_style(level: String, hover: bool = false) -> StyleBox:
	var c: Color = SLIP.get(level, SLIP.warn)
	var lift := 1.05 if hover else 1.0
	var f := frame("slip", Color(_slip_tint(level) * lift, 1.0))
	if f != null:
		# the pin is in the top right corner and the page is folded at the bottom right: keep the words clear
		f.content_margin_right = maxf(f.content_margin_right, 15.0)
		f.content_margin_left = maxf(f.content_margin_left, 13.0)
		if _alert_feed != null and size.x >= StoresCalm.LEAN_MIN_W:
			# (the town's slips in a big window: tighter padding, a lighter weight)
			f.content_margin_top = 5.0
			f.content_margin_bottom = 5.0
		return f
	var s := _flat(c.lightened(0.07) if hover else c, 3, Color(SLIP_MARK.get(level, SLIP_MARK.warn), 0.45), true)
	s.content_margin_left = 13
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## Makes the panel for an alert and puts it at the end of the feed (see
## _sync_alerts): a paper slip, tinted by the level, with a bar of the level's dark colour
## down the left edge, the icon of what it is about, a headline and a second line (dark ink).
## Both lines wrap, so a long one makes the panel taller, not wider. Click it to look at
## the place.
func _make_alert_panel(it: Dictionary) -> void:
	var p := _panel(_slip_style("warn"))
	var row := _hbox(9)
	var ic := _icon("warn", 16, SLIP_MARK.warn)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ic)
	var col := _vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label("", Fonts.sans(600), 13, PAPER_INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var subl := _label("", Fonts.sans(400), 12, PAPER_INK2)
	subl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(subl)
	row.add_child(col)
	p.add_child(row)
	p.set_meta("id", String(it.id))
	p.gui_input.connect(_on_alert_input.bind(String(it.id)))
	p.mouse_entered.connect(_slip_hover.bind(it, true))
	p.mouse_exited.connect(_slip_hover.bind(it, false))
	# a bar of the level's colour down the left edge
	p.draw.connect(func(): p.draw_rect(Rect2(4, 4, 3, p.size.y - 8), it.col))
	it.panel = p
	it.icon = ic
	it.title = title
	it.subl = subl
	it.shown_level = ""
	it.col = SLIP_MARK.warn
	alerts_box.add_child(p)
	_update_alert_panel(it)


## The slip turns a shade lighter while the mouse is on it (it can be clicked).
func _slip_hover(it: Dictionary, on: bool) -> void:
	var p = it.panel
	if p != null and is_instance_valid(p):
		p.add_theme_stylebox_override("panel", _slip_style(String(it.shown_level), on))


## Brings a shown panel in line with its alert: new words go into the labels it
## already has, and a new level re-colours the slip, its edge and the icon. Nothing is
## rebuilt (a wall's "86% intact" changes with every claw).
func _update_alert_panel(it: Dictionary) -> void:
	var title: Label = it.title
	if title.text != it.text:
		title.text = it.text
	var subl: Label = it.subl
	var slip: Control = it.panel
	# (a panel that has not been laid out yet, or is hidden for want of room, knows no width to wrap at: its height is worked out from the
	# fonts, `_alert_height`, not read from it)
	var inner := _alert_inner_w(slip)
	var sub := _alert_sub(String(it.sub), inner, ALERT_SUB_LINES_TOWN if _alert_feed != null else (ALERT_SUB_LINES_COMPACT if compact else ALERT_SUB_LINES))
	if subl.text != sub:
		subl.text = sub
	# (the whole of a line that was cut is the slip's tooltip)
	var tip := String(it.sub) if sub != String(it.sub) else _alert_tip(it)
	if slip.tooltip_text != tip:
		slip.tooltip_text = tip
	subl.visible = it.sub != ""
	if it.shown_level != it.level:
		it.shown_level = it.level
		it.col = SLIP_MARK.get(it.level, SLIP_MARK.warn)
		var ic: TextureRect = it.icon
		ic.texture = icons.get(_alert_icon_name(it))
		ic.modulate = it.col
		var p: Control = it.panel
		p.add_theme_stylebox_override("panel", _slip_style(String(it.level)))
		p.set_meta("level", String(it.level))
		p.queue_redraw()
	if _alert_feed != null:
		_fade_alert_panel(it)


## What a click on a slip does, for its tooltip when it has nothing longer to say: the camera goes to where it is (when the alert has a place), and the radio's News keeps every alert.
func _alert_tip(it: Dictionary) -> String:
	if not avatar_ui:
		return ""
	var id := String(it.id)
	if _alert_feed != null:
		id = String(_alert_feed.target(id))
	var a = sim_ref.alerts.get(id) if sim_ref != null and sim_ref.get("alerts") is Dictionary else null
	var where: bool = a != null and a.get("at") != null
	return ("Click: the camera goes to it. " if where else "") + "The radio's News (T) keeps every alert"


## The width an alert's words wrap at: the feed's, less the slip's margins, the icon and the gap after it.
func _alert_inner_w(p: Control) -> float:
	var st: StyleBox = p.get_theme_stylebox("panel")
	var across := float(CLOCK_W_COMPACT if compact else CLOCK_W)
	return maxf(60.0, across - (st.get_minimum_size().x if st != null else 28.0) - 16.0 - 9.0 - 1.0)


## How many lines an alert's second line may take (the whole of it is the slip's tooltip, and the News has it).
const ALERT_SUB_LINES := 4
const ALERT_SUB_LINES_COMPACT := 3
## (the town's cards keep to two, see alert_feed.gd)
const ALERT_SUB_LINES_TOWN := 2


## An alert's second line kept to `lines` lines at `width`: the whole of it when it fits; else its first sentence and its last (the day-ahead
## notice ends with the hour to be home by, which is the part to act on), else the last alone, else the start of it with an ellipsis.
func _alert_sub(sub: String, width: float, lines: int) -> String:
	if sub == "" or width < 20.0 or _wrapped_lines(sub, width) <= lines:
		return sub
	var parts := sub.split(". ", false)
	if parts.size() >= 2:
		for i in parts.size() - 1:
			parts[i] = String(parts[i]).trim_suffix(".") + "."
		var first := String(parts[0])
		var last := String(parts[parts.size() - 1])
		for candidate in [first + " ... " + last if parts.size() >= 3 else first + " " + last, last]:
			if _wrapped_lines(candidate, width) <= lines:
				return candidate
		sub = last
	var cut := sub
	while cut.length() > 8 and _wrapped_lines(cut + "...", width) > lines:
		cut = cut.substr(0, cut.length() - 4)
	if _alert_feed != null and cut.length() < sub.length():
		# (the town's cards end a cut line on a whole word: "floodlights, second watchtower, ..." and not "watch...")
		var space := cut.rfind(" ")
		if space > 8:
			cut = cut.substr(0, space).trim_suffix(",")
	return cut.strip_edges() + "..."


## How tall the slip of an alert is (or would be): its words wrapped at the width the slip gives them, between the slip's margins. Worked out
## from the fonts, not read from the panel, whose labels know no width until they have been laid out (a hidden panel never is: it measured
## as tall as the words can be, one to a line, and stayed hidden for it).
func _alert_height(p: Control) -> float:
	var it: Dictionary = alert_items.get(String(p.get_meta("id", "")), {})
	if it.is_empty() or it.panel != p:
		return p.get_combined_minimum_size().y
	var st: StyleBox = p.get_theme_stylebox("panel")
	var inner := _alert_inner_w(p)
	var title_font: Font = Fonts.sans(600)
	# (a label puts its theme's line spacing between its lines, which the font's own measure does not know: left out, the slips were laid
	# out 3 px short for each line after the first, and a column of them ran over the toolbar)
	var spacing := float(it.title.get_theme_constant("line_spacing"))
	var title_box: Vector2 = title_font.get_multiline_string_size(String(it.title.text), HORIZONTAL_ALIGNMENT_LEFT, inner, 13, -1, TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var title_h := maxf(title_font.get_height(13), 1.0)
	var col := maxf(title_box.y, title_h) + spacing * float(maxi(0, roundi(title_box.y / title_h) - 1))
	var sub := String(it.subl.text)
	if sub != "":
		var sub_font: Font = Fonts.sans(400)
		var sub_box: Vector2 = sub_font.get_multiline_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, inner, 12, -1, TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
		var sub_h := maxf(sub_font.get_height(12), 1.0)
		col += 1.0 + sub_box.y + spacing * float(maxi(0, roundi(sub_box.y / sub_h) - 1))
	return maxf(16.0, col) + (st.get_minimum_size().y if st != null else 16.0)


## How many lines `text` takes in the alerts' second-line face at `width`.
func _wrapped_lines(text: String, width: float) -> int:
	var font: Font = Fonts.sans(400)
	var size_px := 12
	var box: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, -1, TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	return maxi(1, roundi(box.y / maxf(1.0, font.get_height(size_px))))


## Takes the panel of an alert out of the feed and frees it; the alert's record stays.
func _free_alert_panel(it: Dictionary) -> void:
	var p = it.panel
	it.panel = null
	if p != null and is_instance_valid(p):
		if p.get_parent() != null:
			p.get_parent().remove_child(p)
		p.queue_free()


func _drop_alert(id: String) -> void:
	if alert_items.has(id):
		_free_alert_panel(alert_items[id])
		alert_items.erase(id)


## The feed follows the rules' alerts without being rebuilt: a panel is made when
## an alert first makes the top of the list and kept (its words and colour updated
## in place) until the alert leaves it; the panels are moved only when the order
## changes. An alert the rules drop (they count its life in game seconds, so at 3x
## speed it can go in under two real ones) stays for alert_hold_ms real time after
## its panel first appeared. At most ALERTS_MAX are shown (fewer in a narrow window).
func _sync_alerts(sim) -> void:
	var now := Time.get_ticks_msec()
	# (the town's feed is calmer than the rules': info cards fade, siblings merge, see alert_feed.gd)
	var feed: Dictionary = sim.alerts if _alert_feed == null else _alert_feed.feed(sim.alerts, now)
	for id in feed:
		var a: Dictionary = feed[id]
		var it: Dictionary = alert_items.get(id, {})
		if it.is_empty():
			alert_seq += 1
			it = {"id": String(id), "seq": alert_seq, "seen": false, "first_ms": 0, "panel": null}
			alert_items[id] = it
		it.live = true
		it.level = String(a.level)
		it.text = String(a.text)
		it.sub = String(a.sub)
		it.born = float(a.born)
		it.fade = float(a.get("fade", 1.0))
	for id in alert_items.keys():
		if feed.has(id):
			continue
		var gone: Dictionary = alert_items[id]
		gone.live = false
		gone.fade = _gone_alert_fade(gone, now)
		# a panel that was up stays until it has had its time; an alert never shown goes at once
		if not gone.seen or now - int(gone.first_ms) >= alert_hold_ms or (_alert_feed != null and _alert_feed.is_spent(id)):
			_drop_alert(id)
	var list: Array = alert_items.values()
	list.sort_custom(_alert_before)
	var total_alerts := list.size()
	list = list.slice(0, _alert_cap())
	if _alert_feed != null:
		_alert_feed.sync_pill(total_alerts - list.size(), total_alerts)
	var shown := {}
	for it in list:
		shown[it.id] = true
	for id in alert_items:
		if not shown.has(id) and alert_items[id].panel != null:
			_free_alert_panel(alert_items[id])
	var sig := ""
	for it in list:
		if it.panel == null:
			if not it.seen:
				it.seen = true
				it.first_ms = now
			_make_alert_panel(it)
		else:
			_update_alert_panel(it)
		sig += "%s:%s|" % [it.id, it.level]
	if sig != alert_sig:
		alert_sig = sig
		for i in list.size():
			alerts_box.move_child(list[i].panel, i)


func _on_alert_input(ev: InputEvent, id: String) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		on_alert.call(id if _alert_feed == null else _alert_feed.target(id))    # (a merged card means its latest alert)
		accept_event()


## The town's feed (HUDA): the stack made again at once (the "+N more" pill's click unfolds or folds it).
func refresh_alerts() -> void:
	if sim_ref != null:
		_sync_alerts(sim_ref)
		_layout_news()


## How far an info card whose alert the rules have dropped is into its fade (1.0 until the last part of the hold, then falling to 0).
func _gone_alert_fade(it: Dictionary, now: int) -> float:
	if _alert_feed == null or String(it.level) != "info" or not it.seen:
		return 1.0
	return clampf(float(alert_hold_ms - (now - int(it.first_ms))) / float(AlertFeed.FADE_MS), 0.0, 1.0)


## A card's fade in its panel: a tween over what is left of it, started once; back to whole when a merged card gets a new member.
func _fade_alert_panel(it: Dictionary) -> void:
	var p: Control = it.panel
	var f := float(it.get("fade", 1.0))
	var tw = it.get("fade_tween")
	if f >= 1.0:
		if tw != null and tw.is_valid():
			tw.kill()
		it.erase("fade_tween")
		p.modulate.a = 1.0
	elif tw == null or not tw.is_valid():
		if _calm():
			p.modulate.a = f
		else:
			var t := p.create_tween()
			t.tween_property(p, "modulate:a", 0.0, f * AlertFeed.FADE_MS / 1000.0)
			it["fade_tween"] = t


# ----------------------------------------------------------------- banner --

func _build_banner() -> void:
	# the announcement hangs on a sign: the banner frame, or flat a slate board
	banner = PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sign_box := _style(PANEL, 6, LINE2, true, "banner")
	if sign_box is StyleBoxFlat:
		sign_box.content_margin_left = 28
		sign_box.content_margin_right = 28
		sign_box.content_margin_top = 10
		sign_box.content_margin_bottom = 12
	banner.add_theme_stylebox_override("panel", sign_box)
	var words := _vbox(2)
	banner.add_child(words)
	banner_title = _label("", Fonts.cond(700, 5), 34, INK)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	banner_title.add_theme_constant_override("shadow_offset_y", 2)
	banner_title.add_theme_constant_override("shadow_outline_size", 10)
	words.add_child(banner_title)
	banner_sub = _label("", Fonts.sans(400), 14, INK2)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	banner_sub.add_theme_constant_override("shadow_outline_size", 8)
	words.add_child(banner_sub)
	banner.modulate.a = 0.0
	add_child(banner)
	_center_top(banner, 118)


func show_banner(text: String, sub: String) -> void:
	banner_title.text = text.to_upper()
	banner_sub.text = sub
	if banner_tween != null:
		banner_tween.kill()
	banner_tween = create_tween()
	if _calm():
		# reduced motion: no fades, the sign is simply there, and gone after as long as it would have been
		banner.modulate.a = 1.0
		banner_tween.tween_interval(BANNER_HOLD + BANNER_FADE)
		banner_tween.tween_callback(func(): banner.modulate.a = 0.0)
		return
	banner_tween.tween_property(banner, "modulate:a", 1.0, BANNER_FADE)
	banner_tween.tween_interval(BANNER_HOLD)
	banner_tween.tween_property(banner, "modulate:a", 0.0, BANNER_FADE)


# ------------------------------------------------------------ dock / inspect --

func _build_dock() -> void:
	# a row (the buttons beside the selection panel) or a column (the buttons
	# above it) depending on the room: see _layout_dock
	dock = BoxContainer.new()
	dock.add_theme_constant_override("separation", 8)
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dock)
	_corner(dock, false, true, 12, 12)
	inspect = _panel()
	inspect.custom_minimum_size.x = INSPECT_W
	inspect.size_flags_vertical = Control.SIZE_SHRINK_END
	inspect.visible = false
	dock.add_child(inspect)
	gizmos = GridContainer.new()
	gizmos.add_theme_constant_override("h_separation", GIZMO_GAP)
	gizmos.add_theme_constant_override("v_separation", GIZMO_GAP)
	gizmos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gizmos.size_flags_vertical = Control.SIZE_SHRINK_END
	dock.add_child(gizmos)


## The buttons go to the right of the selection panel when that leaves room
## clear of the speed controls and the help panel; else in rows above the panel,
## and if that would run into the stores panel, as one row of small buttons.
func _layout_dock() -> void:
	if dock == null or speed_panel == null or help == null or left_col == null:
		return
	help.offset_bottom = -_help_lift()
	# the legend takes room down the left side (it gives way in a short window)
	fields_legend.visible = fields_on and size.y >= LEGEND_MIN_H
	if radio_box != null and radio_box.visible:
		_layout_dock_radio()
		return
	gizmos.visible = true
	var n := gizmo_count
	var panel_w := maxf(float(INSPECT_W), inspect.get_combined_minimum_size().x)
	var beside := float(n * GIZMO_W + maxi(0, n - 1) * GIZMO_GAP)
	var reserve := _right_reserve()
	var fits := n == 0 or panel_w + 8.0 + beside <= size.x - 24.0 - reserve
	dock.vertical = not fits
	var mini := false
	if not fits:
		var per_row := maxi(1, int((panel_w + GIZMO_GAP) / (GIZMO_W + GIZMO_GAP)))
		var rows := ceili(float(n) / float(per_row))
		var tall := float(rows * GIZMO_W + (rows - 1) * GIZMO_GAP) + 8.0 + inspect.get_combined_minimum_size().y
		# measured with a little to spare: a font can make a panel a few pixels taller than its minimum;
		# the column at the top left is the stores and, while the fields-of-fire view is on, its legend
		var room := size.y - 12.0 - (12.0 + left_col.get_combined_minimum_size().y + 24.0)
		mini = tall > room
	if mini != gizmo_mini:
		gizmo_mini = mini
		_build_gizmos()
		return
	if fits:
		dock.move_child(inspect, 0)
		gizmos.columns = maxi(1, n)
		gizmos.size_flags_vertical = Control.SIZE_SHRINK_END
	else:
		dock.move_child(gizmos, 0)
		# big buttons stack as wide as the panel; small ones take the room there is
		var across := (size.x - 24.0 - reserve) if gizmo_mini else panel_w
		var side := GIZMO_MINI if gizmo_mini else GIZMO_W
		gizmos.columns = maxi(1, int((across + GIZMO_GAP) / (side + GIZMO_GAP)))
		gizmos.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _meter() -> Array:
	var row := _hbox(8)
	var b := Bar.new()
	b.custom_minimum_size = Vector2(60, 6)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.groove = frame("bar_track")
	row.add_child(b)
	var v := _label("100%", Fonts.cond(600), 13, INK)
	v.custom_minimum_size.x = 36
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return [row, b, v]


## The Mood row of the person panel: [row, bar, word, memo]. The bar is the Health meter's twin and the word
## ("Steady") ends the row in the same column as the health figure. For one who is remembered the bar and the
## word give way to the memo, a line in memory (see _refresh_mood).
func _mood_row() -> Array:
	var row := _hbox(8)
	var b := Bar.new()
	b.custom_minimum_size = Vector2(60, 6)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.groove = frame("bar_track")
	b.value = 0.7
	b.color = MOOD_COLORS.Steady
	row.add_child(b)
	var word := _label("Steady", Fonts.cond(600), 13, INK)
	word.custom_minimum_size.x = MOOD_W
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	word.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(word)
	var memo := _label("", Fonts.sans(400), 13, INK2)
	memo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	memo.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	memo.mouse_filter = Control.MOUSE_FILTER_PASS
	memo.visible = false
	row.add_child(memo)
	return [row, b, word, memo]


## A small chip of paper with a few words on it (a trait): the pill frame, or flat a pale pill; dark ink, so
## it stands out on the chalkboard like a name tag. `tip` is its tooltip.
func _chip(text: String, tip: String) -> PanelContainer:
	var st: StyleBox = frame("pill")
	if st == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color("#e4ddc6")
		f.border_color = Color(PAPER_INK, 0.45)
		f.set_border_width_all(1)
		f.set_corner_radius_all(8)
		f.anti_aliasing = true
		st = f
	st.content_margin_left = 7
	st.content_margin_right = 7
	st.content_margin_top = 0
	st.content_margin_bottom = 1
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", st)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.tooltip_text = tip
	chip.add_child(_label(text, Fonts.cond(700), 12, ACCENT_INK))
	return chip


## One skill of the person panel, three to a row: its name, its number, what it has gained (gold, "+1") and a
## thin bar under them. {"box", "name", "value", "gain", "bar"}; _refresh_skills fills it.
func _skill_cell(skill_name: String) -> Dictionary:
	var box := _vbox(2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var top := _hbox(4)
	var n := _label(skill_name, Fonts.sans(400), 12, INK2)
	top.add_child(n)
	var num := _label("0", Fonts.cond(600), 12, INK)
	top.add_child(num)
	var gain := _label("", Fonts.cond(600), 12, ACCENT)
	gain.visible = false
	top.add_child(gain)
	box.add_child(top)
	var b := Bar.new()
	b.custom_minimum_size = Vector2(20, 3)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.color = SKILL_COLOR
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(b)
	return {"box": box, "name": n, "value": num, "gain": gain, "bar": b}


## Shows `sel` (a person, a walker, a wall section, or null) in the panel and the buttons.
func select(sel) -> void:
	selection = sel
	for c in inspect.get_children():
		inspect.remove_child(c)
		c.queue_free()
	_clear_gizmos()
	inspect_refs = {}
	if sel == null:
		inspect.visible = false
		if radio_verbs != null:
			radio_verbs.set_contact(null)
		_refresh_hint()
		_layout_dock()
		_layout_toast()
		return
	inspect.visible = true
	# (the old yard's hint is done with the first selection; avatar mode's is done when the player has asked someone for something)
	hint_spent = hint_spent or not avatar_ui
	_refresh_hint()
	_layout_toast()
	var tight: bool = sel.kind == "person"
	var v := _vbox(PERSON_BLOCK_GAP if tight else 10)
	var head := _hbox(11)
	var titles := _vbox(1)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", PERSON_ROW_GAP if tight else 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sel.kind == "person":
		var p = sel.ref
		head.add_child(_pic(portrait_of(p)))
		# the name carries the person's record (kills, walls mended...) in a tooltip, so it takes the mouse
		var pname := _label(p.name, Fonts.cond(700), 21, INK)
		pname.mouse_filter = Control.MOUSE_FILTER_PASS
		titles.add_child(pname)
		inspect_refs.name = pname
		titles.add_child(_label("%s · %d" % [p.def.role, int(p.def.age)], Fonts.sans(400), 13, INK2))
		var m := _meter()
		m[2].custom_minimum_size.x = MOOD_W
		_row(grid, "Health", m[0])
		inspect_refs.hp = m[1]
		inspect_refs.hpv = m[2]
		# how they are holding up: a bar and a word, and the reasons in a tooltip (round 4)
		var mood := _mood_row()
		inspect_refs.mood_head = _row(grid, "Mood", mood[0])
		inspect_refs.mood_head.mouse_filter = Control.MOUSE_FILTER_PASS
		inspect_refs.mood_row = mood[0]
		inspect_refs.mood_bar = mood[1]
		inspect_refs.mood_word = mood[2]
		inspect_refs.mood_memo = mood[3]
		# how far they trust the player (avatar mode only: hidden until `_refresh_trust` says so)
		var trust := _trust_row()
		inspect_refs.trust_head = _row(grid, "Trust", trust[0])
		inspect_refs.trust_head.mouse_filter = Control.MOUSE_FILTER_PASS
		inspect_refs.trust_row = trust[0]
		inspect_refs.trust_bar = trust[1]
		inspect_refs.trust_word = trust[2]
		inspect_refs.trust_head.visible = false
		trust[0].visible = false
		var wrow := _hbox(6)
		wrow.add_child(_label(p.gun.name, Fonts.sans(400), 13, INK))
		var pips := _hbox(2)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not p.gun.get("melee", false):
			for i in mini(int(p.gun.mag), 20):
				var pip := ColorRect.new()
				pip.custom_minimum_size = Vector2(3, 10)
				pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pips.add_child(pip)
		wrow.add_child(pips)
		inspect_refs.pips = pips
		_row(grid, "Weapon", wrow)
		var doing := _label("", Fonts.sans(400), 13, INK)
		doing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		doing.custom_minimum_size.x = 200
		_row(grid, "Doing", doing)
		inspect_refs.doing = doing
		var needs := _label("Fed", Fonts.sans(400), 13, INK)
		_row(grid, "Needs", needs)
		inspect_refs.needs = needs
		var wounds := _label("None", Fonts.sans(400), 13, INK2)
		_row(grid, "Wounds", wounds)
		inspect_refs.wounds = wounds
		# only a fever shows: the row is there but hidden until the medical module names a stage
		var infection := _label("", Fonts.sans(400), 13, WARN)
		var infection_head := _row(grid, "Infection", infection)
		infection.visible = false
		infection_head.visible = false
		inspect_refs.infection = infection
		inspect_refs.infection_head = infection_head
		# who they are: their traits as chips, and who they are close to (round 4)
		var chips := _hbox(4)
		chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inspect_refs.traits_head = _row(grid, "Traits", chips)
		inspect_refs.traits_box = chips
		inspect_refs.traits_sig = ""
		var bonds := _label("", Fonts.sans(400), 13, INK)
		bonds.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bonds.mouse_filter = Control.MOUSE_FILTER_PASS
		inspect_refs.bonds_head = _row(grid, "Bonds", bonds)
		inspect_refs.bonds_head.mouse_filter = Control.MOUSE_FILTER_PASS
		inspect_refs.bonds = bonds
		# their day job is a gold tag at the right of the header ("Job: Workbench"; a click opens the Jobs screen)
		inspect_refs.job_tag = _job_tag()
		# and the worktable's: "Making ammo" while the workshop's mark is on them
		inspect_refs.craft_tag = _craft_tag()
	elif sel.kind == "zombie":
		var z = sel.ref
		head.add_child(_pic(GD.tex(data.portraits["z%d" % z.look_index])))
		var names: Array = ZOMBIE_NAMES.get(String(z.kind), ZOMBIE_NAMES.walker)
		if bool(z.plated):
			names = PLATED_NAMES
		titles.add_child(_label(String(names[0]), Fonts.cond(700), 21, INK))
		titles.add_child(_label(String(names[1]), Fonts.sans(400), 13, INK2))
		var m := _meter()
		_row(grid, "Health", m[0])
		inspect_refs.hp = m[1]
		inspect_refs.hpv = m[2]
		var doing := _label("", Fonts.sans(400), 13, INK)
		_row(grid, "Doing", doing)
		inspect_refs.doing = doing
	else:
		var s = sel.ref
		var box := Panel.new()
		# the wall piece's picture sits in a block let into the board
		var bs: StyleBox = frame("panel_inset")
		if bs == null:
			var flat := StyleBoxFlat.new()
			flat.bg_color = Color("#243833")
			flat.set_corner_radius_all(4)
			bs = flat
		box.add_theme_stylebox_override("panel", bs)
		box.custom_minimum_size = Vector2(46, 46)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wi := _icon("wall", 20, INK2)
		wi.position = Vector2(13, 13)
		wi.size = Vector2(20, 20)
		box.add_child(wi)
		head.add_child(box)
		titles.add_child(_label(s.name, Fonts.cond(700), 21, INK))
		titles.add_child(_label("%s · %s" % [LOT_WALL if int(s.id) >= LOT_WALL_FROM else SIDE.get(s.side, "Wall"), MATERIAL.get(s.kind, String(s.kind))], Fonts.sans(400), 13, INK2))
		var m := _meter()
		_row(grid, "Integrity", m[0])
		inspect_refs.hp = m[1]
		inspect_refs.hpv = m[2]
		var doing := _label("", Fonts.sans(400), 13, INK)
		_row(grid, "Status", doing)
		inspect_refs.doing = doing
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(titles)
	if inspect_refs.has("job_tag"):
		head.add_child(_spacer())
		# the tags are stacked at the right of the header (each takes no room while it is hidden)
		var tags := _vbox(3)
		tags.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for tag in [inspect_refs.job_tag, inspect_refs.craft_tag]:
			tag.size_flags_horizontal = Control.SIZE_SHRINK_END
			tags.add_child(tag)
		head.add_child(tags)
	v.add_child(head)
	v.add_child(grid)
	inspect_refs.v = v
	if sel.kind == "person":
		# the skills in one row: a name, its number, what it has gained and a bar under them
		var sk := _hbox(10)
		inspect_refs.skills = {}
		for skill_name in SKILLS_SHOWN:
			var cell := _skill_cell(skill_name)
			sk.add_child(cell.box)
			inspect_refs.skills[skill_name] = cell
		v.add_child(sk)
	inspect.add_child(v)
	if sel.kind == "person":
		# the rows of round 4 are filled in first, so the dock is laid out for a panel as tall as it will be
		_refresh_people_rows(sel.ref)
	_build_gizmos()
	_refresh_selection()


## A small gold pill with a few words for the person panel's header, hidden until
## _refresh_selection says what it stands for is the case.
func _gold_tag(text: String, tip: String) -> PanelContainer:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(ACCENT, 0.14)
	st.border_color = Color(ACCENT, 0.55)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 1
	st.content_margin_bottom = 2
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", st)
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.tooltip_text = tip
	# (no letter spacing: "Job: Vegetable beds" is the longest of them and must fit the header beside a long name)
	tag.add_child(_label(text, Fonts.cond(700, 0), 12, ACCENT))
	tag.visible = false
	return tag


## The tag "Job: Workbench" in the person panel's header: their day job (_refresh_selection words it). It is
## pressed like a button: it opens the Jobs screen.
func _job_tag() -> PanelContainer:
	var tag := _gold_tag("Job: none", "")
	tag.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tag.gui_input.connect(_on_job_tag_input)
	return tag


func _on_job_tag_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if panel_ui() and selection != null and selection.kind == "person":
			# (in avatar mode the radio panel's Jobs page is what opens, on their row; the click never shuts it)
			open_radio("jobs", {"focus": String(selection.ref.id)})
		else:
			_press_jobs()
		accept_event()


## The tag "Making ammo", shown while the workshop's mark is on the person (its tooltip is
## the mark's own words).
func _craft_tag() -> PanelContainer:
	return _gold_tag("Making ammo", "At the workbench: scrap becomes ammo")


func _pic(t: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.custom_minimum_size = Vector2(46, 46)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _row(grid: GridContainer, label: String, value: Control) -> Label:
	var l := _caps(label)
	l.custom_minimum_size.x = 58
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value)
	return l


func _gizmo(id: String, text: String, key: String, on: bool) -> Button:
	var b := Button.new()
	var side := GIZMO_MINI if gizmo_mini else GIZMO_W
	b.custom_minimum_size = Vector2(side, side)
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("id", id)
	b.set_meta("label", text)
	b.set_meta("key", key)
	b.set_meta("on", on)
	# a lit order (a drafted person's Release, Auto while it is on) is the gold one
	var normal := _button_style("normal", on, true)
	normal.set_content_margin_all(0)
	var hover := _button_style("hover", on, true)
	hover.set_content_margin_all(0)
	var pressed := _button_style("pressed", on, true)
	pressed.set_content_margin_all(0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var col := ACCENT_INK if on else INK
	var inner := _vbox(7)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := _icon(String(GIZMO_ICON.get(id, id)), 20 if gizmo_mini else 22, col)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(ic)
	if not gizmo_mini:
		# a long name (Make ammo) is set without the letters spread, so it keeps clear of the frame
		var l := _label(text.to_upper(), Fonts.cond(600, 1 if text.length() <= 8 else 0), 12, col)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(l)
	b.add_child(inner)
	if not gizmo_mini:
		# the key in a small chip at the top right of the button
		var chip := _kbd(key, on)
		b.add_child(chip)
		_corner(chip, true, false, 4, 4)
	_update_gizmo_tip(b)
	b.pressed.connect(func(): on_gizmo.call(id))
	return b


## What an order does, in plain words: the first line of its tooltip. `label` is the
## button's name (Draft or Release); the kind of selection picks the words for
## Repair and Follow.
func _order_words(id: String, label: String) -> String:
	var kind: String = String(selection.kind) if selection != null else ""
	match id:
		"draft":
			if label == "Release":
				return "Release: back to their usual routine"
			return "Draft: take control, they hold their place"
		"post":
			return "To post: go to their post on the wall and hold it"
		"repair":
			if kind == "segment":
				return "Repair: a builder fixes this wall piece (costs scrap)"
			return "Repair: fix the most damaged wall piece (costs scrap)"
		"focus":
			if kind == "segment":
				return "Focus: centre the view on this wall piece"
			if kind == "zombie":
				return "Focus: keep the view on this walker"
			return "Follow: keep the view on this person"
		"treat":
			return "Treat: bandage or cure them (uses medicine)"
		"sendout":
			return "Send out: they leave through the gate for good"
		"scavenge":
			return "Scavenge: send a party out for supplies"
		"lure":
			return "Alarm: draws the dead to this wall for %d hours\nCosts %d scrap. One at a time." % [int(Tactics.LURE_HOURS), int(Tactics.LURE_COST)]
		"job_bench", "job_builders":
			return _job_words(id)
	return label


## The jobs the M and B keys give (and take away): the order button's id -> the station's id (assets/data/stations.json).
const JOB_OF_GIZMO := {"job_bench": "bench", "job_builders": "builders"}


## The tooltip of the Workbench and Builders buttons above their key line: what the job is, with what it is set to
## on the Jobs screen and, for the Workbench, what the person would make (the workshop's rates, slower when they
## are hungry or hurt). The station's name leads, so the first line names the order; for someone who has the job
## it says how to take them off it.
func _job_words(id: String) -> String:
	var jobs = _jobs()
	var station_id := String(JOB_OF_GIZMO.get(id, ""))
	var p = selection.ref if selection != null and selection.kind == "person" else null
	var name := String(jobs.station(station_id).get("name", station_id)) if jobs != null else station_id
	if p != null and jobs != null and jobs.job_of(p) == station_id:
		return "%s: %s is on it. Press again to take them off" % [name, p.first]
	var lines: Array = []
	if station_id == "bench":
		lines.append("Workbench: makes ammo from scrap by day while the stock is under the target")
		if jobs != null:
			lines.append("The target is %d (set on the Jobs screen)" % int(jobs.setting("bench", "ammo_target")))
		var w = _workshop()
		if w != null and p != null and w.has_method("scrap_per_hour") and sim_ref != null:
			var per: float = float(w.ammo_per_scrap()) if w.has_method("ammo_per_scrap") else float(w.get("AMMO_PER_SCRAP"))
			if per > 0.0:
				var scrap_h: float = float(w.scrap_per_hour(p)) * float(sim_ref.perf(p))
				lines.append("1 scrap makes %s ammo. %s makes about %s ammo an hour." % [_num(per), p.first, _num(scrap_h * per)])
	else:
		var below := " under %d%%" % int(jobs.setting("builders", "repair_below")) if jobs != null else ""
		lines.append("%s: mend the most worn wall%s by day while there is scrap" % [name, below])
		if sim_ref != null and sim_ref.get("build") != null:
			lines.append("They also build what is ordered on the Build screen (N)")
	return "\n".join(lines)


## A number for words: whole when it is, else one decimal.
func _num(x: float) -> String:
	return str(roundi(x)) if absf(x - roundf(x)) < 0.05 else "%.1f" % x


## Why the order would do nothing right now, in a few words ("nothing is damaged"),
## or "" when it is fine or the HUD cannot tell. Only what the HUD can see: the
## person's state, the walls and the stores. (The buttons for treating, sending out
## and scavenging only show when the modules offer them.)
func _blocker_for(id: String, sel) -> String:
	if sim_ref == null or sel == null:
		return ""
	var job_id := String(JOB_OF_GIZMO.get(id, ""))
	if job_id != "" and sel.kind != "person":
		return "pick one of the crew first"
	if sel.kind == "person":
		var p = sel.ref
		if job_id != "":
			# the gone and the away are given nothing (the key can be pressed for anyone); the jobs module says the
			# rest (the seats are taken); someone who has the job can always be taken off it
			if p.dead or p.turned:
				return "%s is gone" % p.first
			if p.away != null:
				return "%s is away" % p.first
			var jobs = _jobs()
			return String(jobs.why_not(p, job_id)) if jobs != null else ""
		# in a breakdown they cannot be ordered (looking at them is always fine)
		if id != "focus" and not p.dead and p.away == null and _breakdown(p):
			return "%s is having a breakdown" % p.first
		if p.dead or p.away != null:
			return ""
		match id:
			"post":
				if p.downed:
					return "%s is down" % p.first
			"repair":
				if p.downed:
					return "%s is down" % p.first
				if not _any_wall_damaged():
					return "nothing is damaged"
				if float(sim_ref.stock.scrap) <= 0.0:
					return "no scrap left"
			"treat":
				var need := _meds_needed(p)
				var have := float(sim_ref.stock.meds)
				if have < need:
					return "not enough medicine (needs %d, have %d)" % [int(need), int(have)]
	elif sel.kind == "segment" and id == "repair":
		var seg = sel.ref
		if seg.hp >= seg.max_hp:
			return "this wall piece is not damaged"
		if not _someone_free_to_work():
			return "nobody is free to repair it"
		if float(sim_ref.stock.scrap) <= 0.0:
			return "no scrap left"
	elif sel.kind == "segment" and id == "lure":
		# the rules say why (a door, a section that is down, an alarm already ringing, too little scrap)
		return String(sim_ref.tactics.why_not_lure(sel.ref))
	return ""


## The order button `id`'s blocker for the selection, as `_blocker_for` says.
func _order_blocker(id: String) -> String:
	return _blocker_for(id, selection)


## Why the order `id` would do nothing right now ("" when it is fine or the HUD
## cannot tell): what the tooltips say, for the game to say when a key is pressed.
func why_not(id: String) -> String:
	return _order_blocker(id)


func _any_wall_damaged() -> bool:
	for s in sim_ref.segments:
		if s.hp < s.max_hp:
			return true
	return false


func _someone_free_to_work() -> bool:
	for p in people:
		if not p.downed and not p.dead and p.away == null:
			return true
	return false


## The medicine treating `p` takes: a bandage first if they need one, else the cure.
func _meds_needed(p) -> float:
	var bandage: bool = (p.downed and not p.stabilised) or p.bleeding > 0.0
	if not bandage and p.infected_at < 0.0:
		# a passing fever (a radio card's) takes one medicine, not the two of a cure
		var story = sim_ref.get("storyteller")
		if story != null and story.has_method("is_sick") and story.is_sick(p):
			return float(story.SICK_MEDS)
	return float(sim_ref.medical.BANDAGE_MEDS if bandage else sim_ref.medical.CURE_MEDS)


## "what it does\nKey: R" and, when the HUD knows the order would do nothing now, a
## third line "Not now: why."
func _gizmo_tip(id: String, label: String, key: String, why: String) -> String:
	var tip := "%s\nKey: %s" % [_order_words(id, label), key]
	if why != "":
		tip += "\nNot now: %s." % why
	return tip


## Sets a button's tooltip, and ghosts it (still pressable: the order is the game's to
## refuse) while the HUD knows it would do nothing.
func _update_gizmo_tip(b: Button) -> void:
	var id: String = b.get_meta("id")
	var why := _order_blocker(id)
	var tip := _gizmo_tip(id, String(b.get_meta("label")), String(b.get_meta("key")), why)
	if b.tooltip_text != tip:
		b.tooltip_text = tip
	b.modulate.a = 0.55 if why != "" else 1.0


## The buttons follow the game: what is damaged, the stores, who is down.
func _refresh_gizmo_tips() -> void:
	for b in gizmos.get_children():
		if b is Button and b.has_meta("id"):
			_update_gizmo_tip(b)


func _clear_gizmos() -> void:
	for c in gizmos.get_children():
		gizmos.remove_child(c)
		c.queue_free()
	gizmo_count = 0
	if radio_box != null:
		radio_box.visible = false


## The buttons for the selection: the usual ones, and for a person Treat, Send
## out and Scavenge when the modules offer them.
func _build_gizmos() -> void:
	_clear_gizmos()
	if selection == null:
		_layout_dock()
		return
	if avatar_ui and selection.kind == "person" and radio_box != null:
		# avatar mode (round 17): the verbs of the radio in place of the order buttons (for the player themself the box says who they are)
		radio_box.visible = true
		radio_verbs.set_contact(selection.ref)
		inspect_refs.gizmo_sig = _gizmo_sig()
		_layout_dock()
		return
	if selection.kind == "person":
		var p = selection.ref
		if p.away != null:
			pass # off the map: nothing to order
		elif p.dead:
			gizmos.add_child(_gizmo("focus", "Follow", "C", false))
		else:
			var all_drafted: bool = p.drafted
			gizmos.add_child(_gizmo("draft", "Release" if all_drafted else "Draft", "R", all_drafted))
			gizmos.add_child(_gizmo("post", "To post", "P", false))
			gizmos.add_child(_gizmo("repair", "Repair", "F", false))
			gizmos.add_child(_gizmo("focus", "Follow", "C", false))
			# the day jobs the keys B and M give and take away (a game with no jobs has neither), lit while they have it
			if _jobs() != null:
				gizmos.add_child(_gizmo("job_builders", "Builders", "B", _job_of(p) == "builders"))
				gizmos.add_child(_gizmo("job_bench", "Workbench", "M", _job_of(p) == "bench"))
			if sim_ref != null and sim_ref.medical.can_treat(p):
				gizmos.add_child(_gizmo("treat", "Treat", "T", false))
			if sim_ref != null and sim_ref.medical.can_send_out(p):
				gizmos.add_child(_gizmo("sendout", "Send out", "X", false))
			if _can_scavenge(p):
				gizmos.add_child(_gizmo("scavenge", "Scavenge", "G", false))
	elif selection.kind == "segment":
		gizmos.add_child(_gizmo("repair", "Repair", "F", false))
		gizmos.add_child(_gizmo("focus", "Focus", "C", false))
		gizmos.add_child(_gizmo("lure", "Lure", "L", false))
	else:
		gizmos.add_child(_gizmo("focus", "Focus", "C", false))
	gizmo_count = gizmos.get_child_count()
	inspect_refs.gizmo_sig = _gizmo_sig()
	_layout_dock()


## What decides which buttons the selection gets: when it changes they are rebuilt.
func _gizmo_sig() -> String:
	if selection == null or selection.kind != "person":
		return ("" if selection == null else String(selection.kind)) + ("|avatar" if avatar_ui else "")
	var p = selection.ref
	if avatar_ui:
		return "radio|%s" % p.id
	var sig := "%s|%s|%s" % [p.drafted, p.dead, p.away != null]
	if sim_ref != null and not p.dead and p.away == null:
		sig += "|%s|%s|%s|%s|%s" % [sim_ref.medical.can_treat(p), sim_ref.medical.can_send_out(p), _can_scavenge(p), _jobs() != null, _job_of(p)]
	return sig


## The jobs module (sim.jobs), or null in a game that has none (an older fake).
func _jobs():
	return null if sim_ref == null else sim_ref.get("jobs")


## `p`'s day job, a station's id ("" for none, and in a game with no jobs).
func _job_of(p) -> String:
	var jobs = _jobs()
	return String(jobs.job_of(p)) if jobs != null else ""


## The worktable's module (sim.workshop), or null in a game that has none (an older fake).
func _workshop():
	return null if sim_ref == null else sim_ref.get("workshop")


## The tip of the workshop's mark on `p` ("Making ammo at the worktable") when the modules'
## status marks (sim.status_of) carry the ammo mark, else "".
func _ammo_mark_tip(p) -> String:
	if sim_ref == null or p.dead:
		return ""
	for m in sim_ref.status_of(p):
		if String(m.get("icon", "")) == "ammo":
			return String(m.get("tip", "Making ammo"))
	return ""


## Whether `p` could be sent scavenging now: on the map, on their feet, not held
## by an order and not too ill to travel. (The scavenging module has the last say.)
func is_free_to_go(p) -> bool:
	if sim_ref != null and sim_ref.scavenge.has_method("can_go"):
		return sim_ref.scavenge.can_go(p)
	if p.dead or p.downed or p.away != null:
		return false
	if p.drafted and p.order != null:
		return false
	return sim_ref == null or sim_ref.medical.infection_stage(p) != "delirious"


## Whether the Scavenge button is offered for `p`.
func _can_scavenge(p) -> bool:
	return profile == "" and sim_ref != null and sim_ref.scavenge.can_send() and is_free_to_go(p)


# ------------------------------------------------------------ time controls --

func _speed_button(icon_name: String, tip: String) -> Button:
	var b := Button.new()
	# (narrower than it was: with the Jobs and Build keys the toolbar has eleven, and a full row of nine order
	# buttons must still sit beside the selection panel in a 1280 window)
	b.custom_minimum_size = Vector2(TOOL_W, 30)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	var n := _lit_look(false)
	# under the mouse the button shows as a key (the button frame, half clear), or flat a pale wash
	var h: StyleBox = frame("button_hover", Color(1, 1, 1, 0.55))
	if h == null:
		var wash := StyleBoxFlat.new()
		wash.bg_color = Color(1, 1, 1, 0.07)
		wash.set_corner_radius_all(4)
		h = wash
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ic := _icon(icon_name, 16, INK2)
	ic.position = Vector2(float(TOOL_W - 16) * 0.5, 7)
	ic.size = Vector2(16, 16)
	b.add_child(ic)
	b.set_meta("icon", ic)
	return b


func _build_speed() -> void:
	# the controls sit in the slim board when there is one; the full board at its slimmest if not
	var slim := has_frame("panel_slim")
	var s := _style(PANEL, 6, LINE, true, "panel_slim" if slim else "panel")
	if s is StyleBoxFlat:
		s.set_content_margin_all(4)
	elif not slim:
		s.set_content_margin_all(7)
	var panel := _panel(s)
	speed_panel = panel
	# the keys are close (a pixel apart): with the menu button the toolbar must stay narrow enough
	# for a full row of order buttons to sit beside the selection panel in a 1280 window
	var row := _hbox(1)
	var names := ["pause", "play", "ff", "fff"]
	for i in 4:
		var b := _speed_button(names[i], "%s\nKey: %s" % SPEED_TIPS[i])
		b.pressed.connect(func(): on_speed.call(i))
		row.add_child(b)
		speed_buttons.append(b)
	var sep := ColorRect.new()
	sep.color = LINE2
	sep.custom_minimum_size = Vector2(1, 20)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_spacer_fixed(3))
	row.add_child(sep)
	row.add_child(_spacer_fixed(3))
	fields_button = _speed_button("draft", FIELDS_TIP)
	fields_button.pressed.connect(func(): if on_fields.is_valid(): on_fields.call())
	row.add_child(fields_button)
	sound_button = _speed_button("soundOn", "Turn the sound off")
	sound_button.pressed.connect(func(): on_sound.call())
	row.add_child(sound_button)
	# the Town Board (round 8): only a settlement game has one, so the button is not there in the classic start
	town_button = _speed_button("scavenge", TOWN_TIP)
	town_button.pressed.connect(_press_town)
	town_button.visible = false
	row.add_child(town_button)
	# the radio (round 17): the News log (T) and the call to arms; only avatar mode has them
	news_button = _speed_button("radio", NEWS_TIP)
	news_button.pressed.connect(toggle_news)
	news_button.visible = false
	row.add_child(news_button)
	news_dot = Control.new()
	news_dot.custom_minimum_size = Vector2(9, 9)
	news_dot.size = Vector2(9, 9)
	news_dot.position = Vector2(TOOL_W - 11, 2)
	news_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	news_dot.draw.connect(func(): news_dot.draw_circle(Vector2(4.5, 4.5), 4.0, ACCENT))
	news_dot.visible = false
	news_button.add_child(news_dot)
	alarm_button = _speed_button("bell", ALARM_TIP)
	alarm_button.pressed.connect(_press_alarm)
	alarm_button.visible = false
	row.add_child(alarm_button)
	help_button = _speed_button("help", "Show or hide the controls: every key and mouse button")
	help_button.pressed.connect(_press_help)
	row.add_child(help_button)
	# the Jobs screen (who works where by day and holds which post at night), the Build screen (what to build and
	# where) and the menu (what Esc opens when nothing is selected) at the right end
	jobs_button = _speed_button("jobs", JOBS_TIP)
	jobs_button.pressed.connect(_press_jobs)
	row.add_child(jobs_button)
	build_button = _speed_button("build", BUILD_TIP)
	build_button.pressed.connect(_press_build)
	row.add_child(build_button)
	menu_button = _speed_button("menu", "Menu\nKey: Esc")
	menu_button.pressed.connect(func(): if on_open_menu.is_valid(): on_open_menu.call())
	row.add_child(menu_button)
	panel.add_child(row)
	add_child(panel)
	_corner(panel, true, true, 12, 12)


## The fields-of-fire view lit or dark: its button by the speed controls and its legend.
## (main.gd flips the view; the overlay draws it.)
func set_fields(on: bool) -> void:
	fields_on = on
	if fields_button != null:
		fields_button.add_theme_stylebox_override("normal", _lit_look(on))
		fields_button.get_meta("icon").modulate = ACCENT if on else INK2
	_layout_dock()
	_layout_bar()


func _spacer_fixed(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Whether the colony's interface is the radio panel (avatar mode, outside Orientation Day), else the modal pages.
func panel_ui() -> bool:
	return avatar_ui and not tutorial_ui


## Avatar mode on or off (main.gd says so at the start of a run; the HUD also notices it from the sim at each update): the
## controls help and the hint are rewritten, the readout of the gun is shown or hidden and the cards say who is YOU.
func set_avatar(on: bool) -> void:
	if on == avatar_ui:
		return
	avatar_ui = on
	if on and _hint_spent_by_width:
		hint_spent = false
		_hint_spent_by_width = false
	if help != null:
		_fill_help()
	if hint != null:
		_fill_hint()
		_layout_toast()
	if ammo_panel != null:
		ammo_panel.visible = on
	_apply_radio_mode(on)
	# (the words that the town and the lots give the help's G and N are put there again at the next update)


## The controls, in groups, two entries to a row: every key and mouse button the
## game answers to. In a group of single keys the chips of a column are all as wide
## as its widest, like a row of keycaps.
func _build_help() -> void:
	help = _panel()
	_fill_help()
	help.visible = false
	add_child(help)
	_corner(help, true, true, 12, _help_lift())


## The controls the help lists now: the old yard's (HELP), or avatar mode's for the way the mouse aims (HELP_AVATAR, or HELP_AVATAR_ALWAYS with
## the setting "Always aim at the mouse").
func help_groups() -> Array:
	if not avatar_ui:
		return HELP
	if profile != "":
		return ControlsTable.hud_groups(AimMode.always())    # (the One House's: the one table)
	return HELP_AVATAR_ALWAYS if AimMode.always() else HELP_AVATAR


## The lines of the hint now (the same two ways).
func hint_lines() -> Array:
	if not avatar_ui:
		return [HINT]
	if profile != "":
		return HINT_TOWN_ALWAYS if AimMode.always() else HINT_TOWN
	return HINT_AVATAR_ALWAYS if AimMode.always() else HINT_AVATAR


## The setting of how the mouse aims has changed: the help and the hint say the new controls.
func controls_changed() -> void:
	if not avatar_ui:
		return
	if help != null:
		_fill_help()
	if hint != null:
		_fill_hint()
		_layout_toast()


## The groups of the controls in the help panel: the old yard's (HELP) or avatar mode's (`help_groups`).
func _fill_help() -> void:
	if _help_col != null and is_instance_valid(_help_col):
		help.remove_child(_help_col)
		_help_col.queue_free()
	help_g = null
	help_n = null
	var col := _vbox(8)
	for group in help_groups():
		var g := _vbox(4)
		g.add_child(_caps(String(group[0])))
		var per_row: int = group[1]
		var uniform := true
		for entry in group[2]:
			if String(entry[0]).contains(" "):
				uniform = false
		var grid := GridContainer.new()
		grid.columns = per_row * 2
		grid.add_theme_constant_override("h_separation", 8)
		# the rows are close: the Esc entry takes two lines, there are eleven keys to the keyboard group
		# (the Build screen's N), and in a 560 px window the panel must still clear the clock
		grid.add_theme_constant_override("v_separation", 1)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := 0
		for entry in group[2]:
			var keys := _hbox(2)
			keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			for word in String(entry[0]).split(" "):
				var chip := _kbd(word)
				if uniform:
					chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				keys.add_child(chip)
			var cell: Control = keys
			if n % per_row > 0:
				# the second entry in a row: a little room before its key
				var pad := MarginContainer.new()
				pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pad.add_theme_constant_override("margin_left", 12)
				pad.add_child(keys)
				cell = pad
			grid.add_child(cell)
			var what := _label(String(entry[1]), Fonts.sans(400), 12, INK2)
			what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if String(entry[0]) == "G":
				help_g = what
				# (the word is "Town Board" in a settlement game and "Scavenge" in the classic one: the room is kept for the longer, so that
				# the panel is as wide in either)
				what.custom_minimum_size.x = Fonts.sans(400).get_string_size("Town Board", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			if String(entry[0]) == "N":
				help_n = what
			if entry.size() > 2:
				# a long entry (its third number is the width it wraps at) takes two lines, not a wider panel
				what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				what.custom_minimum_size.x = float(entry[2])
			grid.add_child(what)
			n += 1
		g.add_child(grid)
		col.add_child(g)
	help.add_child(col)
	_help_col = col


## How far above the window's foot the controls help sits: clear of the speed controls under
## it (their panel is taller or shorter with the frame it wears), with a gap.
func _help_lift() -> float:
	return 12.0 + (speed_panel.get_combined_minimum_size().y if speed_panel != null else 38.0) + 8.0


func _build_hint() -> void:
	hint = _panel()
	_fill_hint()
	add_child(hint)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -96
	_refresh_hint()


## The words of the hint: the old yard's (HINT) or avatar mode's (HINT_AVATAR).
func _fill_hint() -> void:
	if _hint_row != null and is_instance_valid(_hint_row):
		hint.remove_child(_hint_row)
		_hint_row.queue_free()
	var lines: Array = hint_lines()
	var rows := _vbox(4)
	for words in lines:
		var row := _hbox(5)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		if String(words[0]) != "":
			row.add_child(_label(String(words[0]), Fonts.sans(400), 13, INK2))
		for part in words[1]:
			row.add_child(_kbd(part[0]))
			row.add_child(_label(part[1], Fonts.sans(400), 13, INK2))
		rows.add_child(row)
	hint.add_child(rows)
	_hint_row = rows


## Shows or hides the one-line hint: it shows until its job is done, unless the player has turned
## hints off in the settings (it follows the setting each time the HUD is updated, so switching
## hints on or off takes effect at once). The toast is moved to suit.
func _refresh_hint() -> void:
	if hint == null:
		return
	var show := not hint_spent and Prefs.on("ui", "hints")
	# (in avatar mode a selected contact has the dock, which would cover it: it waits, and comes back when the dock goes)
	if avatar_ui and inspect != null and inspect.visible:
		show = false
	# (and the controls help and the News panel are in its way too: it is only the first screen's)
	if avatar_ui and ((help != null and help.visible) or radio_open()):
		show = false
	# (and so is a call that waits: the legend sat over the card's last option in a narrow window; it comes back when the call is settled)
	if avatar_ui and call_card != null and call_card.shown_id != 0 and not call_card.suppressed:
		show = false
	# (the town's keys are a compact legend in the corner, above the lesson card: scripts/ui/key_legend.gd, placed by town_hud.gd; the bar never shows there)
	if profile == "one_house":
		legend_wanted = show
		show = false
	if hint.visible != show:
		hint.visible = show
		_layout_toast()


# ------------------------------------------------------------------ toast --

func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = _label("", Fonts.sans(600), 14, INK)
	toast_panel.add_child(toast_label)
	toast_panel.visible = false
	# on the frame the level is a bar of its colour down the left edge (flat, the edge says it)
	toast_panel.draw.connect(_draw_toast_bar)
	add_child(toast_panel)
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.anchor_top = 1.0
	toast_panel.anchor_bottom = 1.0
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_layout_toast()


func _draw_toast_bar() -> void:
	if not (toast_panel.get_theme_stylebox("panel") is StyleBoxFlat):
		toast_panel.draw_rect(Rect2(5, 6, 3, toast_panel.size.y - 12), toast_col)


## A short message near the bottom centre for something that did not happen
## ("Nothing is damaged"): one line, up for toast_seconds of real time with a fade
## at the end, replaced by the next one. `level` is "info" (the default), "warn"
## or "danger".
func toast(text: String, level: String = "info") -> void:
	if toast_panel == null or text.strip_edges() == "":
		return
	if Access.markers() and level != "info":
		text = ("!! " if level == "danger" else "! ") + text    # (Colour-blind markers: the red and the amber of a toast are marks too)
	var st := _style(PANEL, 6, LEVEL_COLOR.get(level, INFO), true, "toast")
	toast_col = LEVEL_COLOR.get(level, INFO)
	if st is StyleBoxFlat:
		# flat: the level's colour is the edge, heavy on the left; with the frame a bar is drawn
		st.border_width_left = 3
		st.content_margin_left = 12
		st.content_margin_right = 14
		st.content_margin_top = 7
		st.content_margin_bottom = 8
	toast_panel.add_theme_stylebox_override("panel", st)
	toast_panel.queue_redraw()
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", TOAST_COLOR.get(level, INK))
	if toast_tween != null:
		toast_tween.kill()
	toast_panel.modulate.a = 1.0
	toast_panel.visible = true
	_layout_toast()
	toast_tween = create_tween()
	if _calm():
		# reduced motion: it stays as it is and goes at the end, with no fade
		toast_tween.tween_interval(toast_seconds)
	else:
		toast_tween.tween_interval(maxf(0.0, toast_seconds - TOAST_FADE))
		toast_tween.tween_property(toast_panel, "modulate:a", 0.0, minf(TOAST_FADE, toast_seconds))
	toast_tween.tween_callback(func(): toast_panel.visible = false)


func _layout_toast() -> void:
	if toast_panel == null:
		return
	var lift := 96.0
	if hint != null and hint.visible:
		lift += hint.get_combined_minimum_size().y + 8.0
	toast_panel.offset_bottom = -lift
	var shift := _toast_shift(toast_panel.get_combined_minimum_size().x * 0.5)
	toast_panel.offset_left = shift
	toast_panel.offset_right = shift
	_layout_leave_card(lift)


## The toast sits at the bottom centre above the order buttons, above the hint while
## that shows, and is moved clear of the selection panel in a window too narrow to
## have both side by side: how far from the centre (pixels, negative to the left) for a card of this half width.
func _toast_shift(half: float) -> float:
	var shift := 0.0
	# (with the radio panel up the toast keeps to the left of it when it can: it would cover the page's answer line, which says the same)
	if radio_open():
		var room_to := size.x - 12.0 - _radio_panel_width() - 8.0
		shift = minf(0.0, room_to - half - size.x * 0.5)
		shift = maxf(shift, minf(0.0, 12.0 + half - size.x * 0.5))    # (and not off the left edge of a narrow window)
	if inspect != null and inspect.visible:
		shift = maxf(shift, 12.0 + _radio_dock_width() + 8.0 + half - size.x * 0.5)
		shift = minf(shift, maxf(0.0, size.x * 0.5 - 12.0 - half))
	return shift


## The card of the offer to leave the base (round 23): "Leave the base?" and what to press, a gold-edged card above the toast; the whole of it is a button
## (E does the same: main.gd). Hidden until the rules make the offer (`show_leave`).
func _build_leave_card() -> void:
	leave_card = PanelContainer.new()
	leave_card.mouse_filter = Control.MOUSE_FILTER_STOP
	leave_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	leave_card.focus_mode = Control.FOCUS_NONE
	leave_card.tooltip_text = "You are outside the walls. The Map is where a trip is chosen: the places on the road, who goes. Walk back inside to forget it."
	var st := _style(PANEL, 8, ACCENT, true, "toast")
	if st is StyleBoxFlat:
		st.border_width_left = 3
		st.border_width_top = 2
		st.border_width_right = 2
		st.border_width_bottom = 2
		st.content_margin_left = 14
		st.content_margin_right = 14
		st.content_margin_top = 8
		st.content_margin_bottom = 9
	leave_card.add_theme_stylebox_override("panel", st)
	leave_label = _label(LEAVE_TEXT, Fonts.sans(600), 14, INK)
	leave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leave_card.add_child(leave_label)
	leave_card.visible = false
	leave_card.gui_input.connect(_on_leave_card_input)
	add_child(leave_card)
	leave_card.anchor_left = 0.5
	leave_card.anchor_right = 0.5
	leave_card.anchor_top = 1.0
	leave_card.anchor_bottom = 1.0
	leave_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	leave_card.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _on_leave_card_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		leave_card.accept_event()
		if on_leave.is_valid():
			on_leave.call()


## Shows or hides the offer of the Map (the rules' `leave_offer`).
func show_leave(on: bool) -> void:
	if leave_card == null or leave_card.visible == on:
		return
	leave_card.visible = on and avatar_ui
	_layout_toast()


func leave_shown() -> bool:
	return leave_card != null and leave_card.visible


func leave_text() -> String:
	return leave_label.text if leave_card != null and leave_card.visible else ""


## Above the toast's place (a toast is about 36 pixels tall), and clear of the radio panel and the selection panel as the toast is.
func _layout_leave_card(toast_lift: float) -> void:
	if leave_card == null:
		return
	leave_card.offset_bottom = -(toast_lift + 46.0)
	var shift := _toast_shift(leave_card.get_combined_minimum_size().x * 0.5)
	leave_card.offset_left = shift
	leave_card.offset_right = shift


# ----------------------------------------------- dialog and game over --

## Whether a modal is up over the game: the scavenging dialog, the end screen, or any page of the HUD that covers
## the whole window and stops the mouse (the storyteller's radio card is one) or says so with the meta "modal". A
## menu is the shell's (main.gd's `menu_open`). The speech bubbles keep quiet while one is up.
func modal_open() -> bool:
	if scavenge_dialog != null or game_over != null or jobs_screen != null or build_screen != null:
		return true
	for c in get_children():
		if not (c is Control) or not c.visible or c == wheel:
			continue    # (the order wheel is no page: it takes the mouse while it is up, so that no card's tooltip comes up through the ring, and that is all)
		if c.has_meta("modal") or (c.mouse_filter == Control.MOUSE_FILTER_STOP and _covers_window(c)):
			return true
	return false


## Whether a control is anchored over the whole of its parent (a page, not one of the HUD's boards).
func _covers_window(c: Control) -> bool:
	return c.anchor_left == 0.0 and c.anchor_top == 0.0 and c.anchor_right == 1.0 and c.anchor_bottom == 1.0


## Opens the "Send a scavenging party" dialog for the selection (a person, or
## nothing: then the first free survivor leads). The game is paused meanwhile.
func open_scavenge(sel) -> void:
	if scavenge_dialog != null or game_over != null or sim_ref == null:
		return
	var who = sel.ref if sel != null and sel.kind == "person" else null
	# the settlement game plans on the Town Board (round 8); the classic start keeps this dialog as it was
	if sim_ref.get("town") != null and sim_ref.town.on:
		_open_town_board(who)
		return
	var d := Dialog.new()
	scavenge_dialog = d
	add_child(d)
	d.closed.connect(_on_dialog_closed)
	d.setup(self, sim_ref, who)
	_speed_before_dialog = last_speed
	_paused_for_dialog = last_speed > 0
	if _paused_for_dialog and on_speed.is_valid():
		on_speed.call(0)


## The Town Board (key G, a person's Scavenge button, the toolbar's bag) in a settlement game, in place of the dialog:
## it pauses the game like the dialog and the speed comes back when it is closed. It does not open over another page
## (the radio card, the Jobs or Build screen) or the end screen.
func _open_town_board(who) -> void:
	if modal_open():
		return
	var b := TownBoard.new()
	scavenge_dialog = b
	add_child(b)
	b.closed.connect(_on_board_closed)
	b.setup(self, sim_ref, who)
	ui_sound("ui_open")
	_speed_before_dialog = last_speed
	_paused_for_dialog = last_speed > 0
	if _paused_for_dialog and on_speed.is_valid():
		on_speed.call(0)


## Whether the open dialog is the Town Board.
func town_board_open() -> bool:
	return scavenge_dialog != null and is_instance_valid(scavenge_dialog) and scavenge_dialog is TownBoard


func _on_board_closed() -> void:
	ui_sound("ui_close")
	_on_dialog_closed()


## The toolbar's Town Board button: main.gd decides (the tutorial's lock, another page being up); with nobody
## listening the HUD opens it itself.
func _press_town() -> void:
	if on_town.is_valid():
		on_town.call()
	elif town_board_open():
		scavenge_dialog.close()
	else:
		open_scavenge(selection)


func _on_dialog_closed() -> void:
	scavenge_dialog = null
	if _paused_for_dialog and on_speed.is_valid():
		on_speed.call(_speed_before_dialog)
	_paused_for_dialog = false


## Opens the Jobs screen (the Duty roster: key J, the clipboard in the toolbar, the job tag in a person's panel).
## The game is paused meanwhile, and the speed comes back when it is closed. Nothing happens while another
## modal is up, in a game with no jobs, or before the HUD has seen the game (`with_sim` stands in for that).
func open_jobs(with_sim = null) -> void:
	if jobs_screen != null or scavenge_dialog != null or game_over != null or modal_open():
		return
	var sim = sim_ref if sim_ref != null else with_sim
	if sim == null or sim.get("jobs") == null:
		return
	var s := JobsScreen.new()
	jobs_screen = s
	add_child(s)
	s.closed.connect(_on_jobs_closed)
	s.setup(self, sim)
	ui_sound("ui_open")
	_speed_before_jobs = last_speed
	_paused_for_jobs = last_speed > 0
	if _paused_for_jobs and on_speed.is_valid():
		on_speed.call(0)


## A menu sound for the Jobs screen (see on_ui_sound).
func ui_sound(sound_name: String, level: float = 1.0) -> void:
	if on_ui_sound.is_valid():
		on_ui_sound.call(sound_name, level)


## Closes the Jobs screen (it gives the speed back).
func close_jobs() -> void:
	if jobs_screen != null:
		jobs_screen.close()


## J: the Jobs screen open or shut.
func toggle_jobs() -> void:
	if jobs_screen != null:
		close_jobs()
	else:
		open_jobs()


## The toolbar's Jobs button and the job tag: main.gd decides (the tutorial's lock, another page being up); with
## nobody listening the HUD does it itself.
func _press_jobs() -> void:
	if on_jobs.is_valid():
		on_jobs.call()
	else:
		toggle_jobs()


func _on_jobs_closed() -> void:
	jobs_screen = null
	set_jobs_hover({})
	ui_sound("ui_close")
	if _paused_for_jobs and on_speed.is_valid():
		on_speed.call(_speed_before_jobs)
	_paused_for_jobs = false


## The Jobs screen marks a place in the world (see on_jobs_hover): {} when it is closed.
func set_jobs_hover(marks: Dictionary) -> void:
	jobs_hover = marks.duplicate()
	if on_jobs_hover.is_valid():
		on_jobs_hover.call(jobs_hover)


## Opens the Build screen (key N, the hammer in the toolbar, a click on a plot's sign in the yard), on `plot_id` (the
## plot being built, else the first with nothing on it, when none is asked for). The game is paused meanwhile, and
## the speed comes back when it is closed. Nothing happens while another modal is up, in a game with no buildings, or
## before the HUD has seen the game (`with_sim` stands in for that); with the screen already up, it is the plot that
## changes.
func open_build(plot_id: String = "", with_sim = null) -> void:
	if build_screen != null:
		if plot_id != "":
			build_screen.select_plot(plot_id)
		return
	if scavenge_dialog != null or game_over != null or modal_open():
		return
	var sim = sim_ref if sim_ref != null else with_sim
	if sim == null or sim.get("build") == null:
		return
	var s := BuildScreen.new()
	build_screen = s
	add_child(s)
	s.closed.connect(_on_build_closed)
	s.setup(self, sim, plot_id)
	ui_sound("ui_open")
	_speed_before_build = last_speed
	_paused_for_build = last_speed > 0
	if _paused_for_build and on_speed.is_valid():
		on_speed.call(0)


## Closes the Build screen (it gives the speed back).
func close_build() -> void:
	if build_screen != null:
		build_screen.close()


## N: the Build screen open or shut.
func toggle_build() -> void:
	if build_screen != null:
		close_build()
	else:
		open_build()


## The toolbar's Build button: main.gd decides (the tutorial's lock, another page being up); with nobody listening
## the HUD does it itself.
func _press_build() -> void:
	if on_build.is_valid():
		on_build.call()
	else:
		toggle_build()


func _on_build_closed() -> void:
	build_screen = null
	set_build_hover({})
	ui_sound("ui_close")
	if _paused_for_build and on_speed.is_valid():
		on_speed.call(_speed_before_build)
	_paused_for_build = false


## The Build screen marks a plot in the world (see on_build_hover): {} when none is, or it is closed.
func set_build_hover(marks: Dictionary) -> void:
	build_hover = marks.duplicate()
	if on_build_hover.is_valid():
		on_build_hover.call(build_hover)


## The Build screen's button for the Builders' job: the page gives way to the Jobs screen (the pause is carried over:
## the rules wait through both) with the Builders' station marked in the yard. Nothing is lost if the Jobs screen
## does not open (the tutorial's lock, say): the Build screen is shut and the speed is given back.
func open_jobs_from_build() -> void:
	if build_screen == null:
		return
	var kept_paused := _paused_for_build
	var kept_speed := _speed_before_build
	_paused_for_build = false
	close_build()
	if kept_paused:
		# (the game is paused: the Jobs screen finds it so, and its own pause is the one carried over below)
		last_speed = 0
	_press_jobs()
	if jobs_screen != null:
		_paused_for_jobs = kept_paused
		_speed_before_jobs = kept_speed
		jobs_screen.show_marks("builders")
	elif kept_paused and on_speed.is_valid():
		on_speed.call(kept_speed)


func _show_game_over(sim) -> void:
	if scavenge_dialog != null:
		scavenge_dialog.close()
	if jobs_screen != null:
		jobs_screen.close()
	if build_screen != null:
		build_screen.close()
	hint_spent = true
	_refresh_hint()
	# (round 26: the demo's three nights held end on its own card; a defeat is the ordinary report card)
	if String(sim.over) == "victory" and sim.scenario != null and sim.scenario.has_method("end_card"):
		# (One House, WP7: the town's held night ends on its own card, from the scenario's end_card(); a defeat is still the report card)
		game_over = TownEndCard.new()
	else:
		game_over = DemoEndCard.new() if String(sim.over) == "victory" and sim.has_method("is_demo") and sim.is_demo() else GameOver.new()
	add_child(game_over)
	game_over.setup(self, sim)


## Begins a new run or loads a save: `meta` is what main.gd reads from Engine
## meta "run" ({"difficulty", "seed"} or {"load": path}) when the scene reloads.
func start_run(meta: Dictionary) -> void:
	if restart.is_valid():
		restart.call(meta)
		return
	Engine.set_meta("run", meta)
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		tree.reload_current_scene()


## The newest save that exists, or "".
func last_save() -> String:
	var best := ""
	var best_time := -1
	for path in save_paths:
		if FileAccess.file_exists(path):
			var t := FileAccess.get_modified_time(path)
			if t > best_time:
				best_time = t
				best = path
	return best


## One look of a button: the frame for the state (button, button_hover, button_pressed,
## button_off; button_primary and button_primary_hover for the main choice and a lit order),
## or flat a slate board, gold for the main choice. `state` is normal, hover, pressed or
## disabled. `paper` is for a button on a notebook page: a disabled main choice is then a
## pale gold with dark ink (on the dark boards it is a dimmed gold with gold ink).
func _button_style(state: String, primary: bool = false, shadow: bool = false, paper: bool = false) -> StyleBox:
	var kind := "button"
	var tint := Color.WHITE
	if primary:
		kind = "button_primary_hover" if state == "hover" else "button_primary"
		if state == "pressed":
			# the pressed gold has its own picture when the theme has one, else the gold a shade darker
			if has_frame("button_primary_pressed"):
				kind = "button_primary_pressed"
			else:
				tint = Color(0.9, 0.9, 0.9, 1.0)
		elif state == "disabled":
			tint = Color(1, 1, 1, 0.45)
	else:
		kind = {"normal": "button", "hover": "button_hover", "pressed": "button_pressed", "disabled": "button_off"}.get(state, "button")
	var f := frame(kind, tint)
	if f != null:
		return f
	var bg := PANEL
	var edge := LINE
	if primary:
		edge = ACCENT
		match state:
			"hover":
				bg = ACCENT.lightened(0.14)
			"pressed":
				bg = ACCENT.darkened(0.08)
			"disabled":
				bg = Color(ACCENT, 0.35 if paper else 0.28)
			_:
				bg = ACCENT
	elif state == "hover" or state == "pressed":
		bg = PANEL_HI
		edge = LINE2 if state == "hover" else LINE
	return _flat(bg, 6, edge, shadow)


## A button in the game's style for the dialog, the game-over screen and the menus: the main
## choice in gold, the others dark (chalkboard slate). `paper` says it sits on a notebook page.
func _button(text: String, primary: bool = false, paper: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(112, 40)
	b.add_theme_font_override("font", Fonts.cond(700, 1))
	b.add_theme_font_size_override("font_size", 15)
	var ink := ACCENT_INK if primary else INK
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, ink)
	# a disabled button's word still reads (gold on the dimmed gold, cream on the dark, dark on the
	# pale gold of a notebook page): it is the main choice
	var off_ink := Color(ink, 0.6)
	if primary:
		off_ink = Color(ACCENT_INK, 0.85) if paper else Color(ACCENT, 0.9)
	b.add_theme_color_override("font_disabled_color", off_ink)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var st := _button_style(state, primary, false, paper)
		st.content_margin_top = 0
		st.content_margin_bottom = 0
		st.content_margin_left = 16
		st.content_margin_right = 16
		b.add_theme_stylebox_override(state, st)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


# ------------------------------------------------------------------ layout --

func _on_resized() -> void:
	var w := size.x
	var was := compact
	compact = w < 980.0
	var bottom_bar := w < 640.0
	if compact != was or cards.size() > 0:
		for l in res_labels:
			l.visible = not compact
		res_grid.columns = 2 if compact else 3
		clock.custom_minimum_size.x = CLOCK_W_COMPACT if compact else CLOCK_W
		_fit_clock_words()
		_fit_card_words()
		alerts_box.custom_minimum_size.x = CLOCK_W_COMPACT if compact else CLOCK_W
		time_label.add_theme_font_size_override("font_size", 24 if compact else 30)
		# a window too narrow for the hint loses it for good (as it always did; avatar mode's is two short lines and fits)
		if compact and not avatar_ui and not hint_spent:
			hint_spent = true
			_hint_spent_by_width = true
		_refresh_hint()
	if bottom_bar:
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
		bar.offset_top = 0
		bar.offset_bottom = -56
		alerts_box.visible = false
	else:
		bar.anchor_top = 0.0
		bar.anchor_bottom = 0.0
		bar.grow_vertical = Control.GROW_DIRECTION_END
		bar.offset_top = 10
		bar.offset_bottom = 10
		alerts_box.visible = true
	_center_h(bar)
	_bar_sig = ""
	_layout_bar()
	if selection != null and selection.kind == "person" and inspect_refs.has("traits_head"):
		_refresh_people_rows(selection.ref)
	_layout_dock()
	_layout_toast()
	_layout_news()
	if _stores_calm != null:
		_stores_calm.on_resized()    # (the town's panels are lighter in a big window)


func _center_h(c: Control) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.offset_left = 0
	c.offset_right = 0


# ------------------------------------------------------------------ update --

func _hp_color(f: float) -> Color:
	return DANGER if f < 0.34 else (WARN if f < 0.67 else OK)


## "6 d": whole days left, rounded down, and "<1 d" under a day.
func _days_text(days: float) -> String:
	if not is_finite(days) or days >= 99.0:
		return "99+ d"
	if days < 1.0:
		return "<1 d"
	return "%d d" % int(days)


## The word over the card of someone who is gone or away, or "". One who died is "In memory" (round 4: the
## card's tooltip says what was said about them); one who turned is "Turned" and one who was sent out "Left".
func _card_word(p) -> String:
	if p.turned:
		return "Turned"
	if p.dead:
		return "Left" if p.away is Dictionary and String(p.away.get("kind", "")) == "exile" else "In memory"
	if p.away != null:
		return "Away"
	return ""


## The tooltip of a card: the name and the job; for one who died, that and what was said of them (for one who
## turned, what was said too).
func _card_tip(p, word: String, epitaph: String) -> String:
	var tip := "%s, %s" % [p.name, String(p.def.role).to_lower()]
	if p.player and word == "":
		tip += "\nThis is you"
		# (round 22: the faint ring round him was never explained: the rally's reach, as the nights' rules have it)
		if sim_ref != null and sim_ref.get("nights") != null and bool(sim_ref.nights.active()):
			tip += "\nThe green ring round you: the crew inside it shoots better"
	if avatar_ui and word == "" and not p.player and STANCE_TIPS.has(String(p.stance)):
		tip += "\n" + String(STANCE_TIPS[String(p.stance)])
	if profile != "" and word == "" and not p.player:
		tip += "\nClick to ask them for something"
	# round 20: the title they are known by and who they are close to or at odds with (the card itself shows nothing more)
	if not p.dead and not p.turned:
		for line in CommunityKit.person_lines(sim_ref, p):
			tip += "\n" + String(line)
	if word == "In memory" or word == "Turned":
		tip += "\nIn memory" if word == "In memory" else "\nTurned into one of the dead"
		if epitaph != "":
			tip += "\n" + _wrap(epitaph)
	return tip


func _update_card(c: Dictionary, sim) -> void:
	var p = c.p
	var sel: bool = selection != null and selection.ref == p
	if sel != c.sel:
		c.sel = sel
		c.card.add_theme_stylebox_override("panel", _card_style(sel))
	var word := _card_word(p)
	var state := "%s|%s" % [word, p.downed]
	if state != c.state:
		c.state = state
		c.veil.visible = word != ""
		c.veil.color.a = 0.66 if p.dead else 0.48
		c.word.text = word
		# "In memory" is the longest word a card carries: set without the spread letters, and broken into
		# two lines where the picture is narrow
		c.word.add_theme_font_override("font", Fonts.cond(700, 0 if word == "In memory" else 1))
		c.word.autowrap_mode = TextServer.AUTOWRAP_WORD
		c.card.self_modulate = MEMORIAL_STOCK if word == "In memory" else Color.WHITE
		c.word.add_theme_color_override("font_color", DANGER_TEXT if word == "Turned" else (INFO if word == "Away" else INK2))
		c.name.add_theme_color_override("font_color", INK3 if p.dead else INK)
		var dim := 0.4 if p.dead else (0.7 if p.away != null else (0.45 if p.downed else 1.0))
		c.pic.modulate = Color(dim, dim, dim)
	# the tooltip: the name and the job, and for the remembered the epitaph (asked for until there is one)
	if word == "In memory" or word == "Turned":
		if c.epitaph == "":
			c.epitaph = _epitaph(p)
	else:
		c.epitaph = ""
	var tip := _card_tip(p, word, c.epitaph)
	if c.card.tooltip_text != tip:
		c.card.tooltip_text = tip
	var f: float = clampf(p.hp / 100.0, 0.0, 1.0)
	c.hp.size = Vector2(c.hp_bg.size.x * f, 3)
	c.hp.color = _hp_color(f)
	var present: bool = not p.dead and p.away == null
	# the stance in words (avatar mode: the radio's; a narrow card has the short ones), else the old gold glyph of a drafted person
	var word_of := ""
	if avatar_ui and present and not p.player:
		var table: Dictionary = STANCE_WORDS if c.card.custom_minimum_size.x >= 56.0 else STANCE_SHORT
		word_of = String(table.get(String(p.stance), ""))
	if c.stance.text != word_of:
		c.stance.text = word_of
		c.stance_box.reset_size()
	c.stance_box.visible = word_of != ""
	c.badge.visible = p.drafted and present and word_of == ""
	c.you.visible = p.player and present
	var key_n := int(crew_keys.get(p, 0)) if avatar_ui and present and not p.player else 0
	var key_text := str(key_n) if key_n > 0 else ""
	if c.key.text != key_text:
		c.key.text = key_text
		c.key.visible = key_n > 0
	c.fight.visible = p.target != null and not p.downed and present
	if c.fight.visible:
		c.fight.modulate.a = 1.0 if _calm() else 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
	var marks: Array = [] if p.dead else _fit_marks(mark_filter.call(p, sim.status_of(p)) if mark_filter.is_valid() else sim.status_of(p))
	var sig := ""
	for m in marks:
		sig += "%s|%s|%s;" % [m.get("icon", ""), Color(m.get("color", INK2)).to_html(), m.get("tip", "")]
	if sig != c.marks_sig:
		c.marks_sig = sig
		c.marks_data = marks
		_fill_marks(c, marks)


## `marks` as the modules give them, with the mood mark (a person about to break) kept among the first
## `mark_max` when there are more marks than the card has room for: the modules' order puts it last, and it
## would be the first to be cut.
func _fit_marks(marks: Array) -> Array:
	if marks.size() <= mark_max:
		return marks
	var i := 0
	while i < marks.size() and String(marks[i].get("icon", "")) != "mood":
		i += 1
	if i < mark_max or i >= marks.size():
		return marks
	var out := marks.duplicate()
	var keep = out[i]
	out[i] = out[mark_max - 1]
	out[mark_max - 1] = keep
	return out


## The little row of status icons on a card: what the modules say is wrong with
## the person (hungry, bleeding, feverish...), each with its tip as a tooltip.
func _fill_marks(c: Dictionary, marks: Array) -> void:
	var row: HBoxContainer = c.marks
	for ch in row.get_children():
		row.remove_child(ch)
		ch.queue_free()
	var shown := mini(marks.size(), mark_max)
	for i in shown:
		var m: Dictionary = marks[i]
		var t := TextureRect.new()
		t.texture = icons.get(String(m.get("icon", "")), icons.get("help"))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(mark_px, mark_px)
		t.modulate = Color(m.get("color", INK2))
		t.tooltip_text = String(m.get("tip", ""))
		t.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(t)
	c.marks_box.visible = shown > 0


func update_hud(sim, speed: int, sound_on: bool, walkers: int) -> void:
	sim_ref = sim
	if profile == "" and sim.has_method("is_one_house") and sim.is_one_house():
		set_profile("one_house")
	if cards.size() != sim.people.size():
		_sync_cards(sim.people)
	_layout_bar()
	_refresh_hint()
	if sim.over != "" and game_over == null:
		_show_game_over(sim)
	for s in STORES:
		var v := roundi(float(sim.stock[s[0]]))
		var lbl: Label = res_values[s[0]]
		lbl.text = str(v)
		var low_ammo: float = float(sim.supplies.get("low_ammo")) if sim.supplies != null and sim.supplies.get("low_ammo") != null else 60.0
		var low: bool = (s[0] == "ammo" and v < low_ammo) or (s[0] == "meds" and v < 3)
		lbl.add_theme_color_override("font_color", WARN if low else INK)
	_update_fuel(sim)
	_update_crew_load(sim)
	_update_ammo(sim)
	for kind in res_days:
		var days: float = sim.supplies.days_left(kind)
		var dl: Label = res_days[kind]
		dl.text = _days_text(days)
		dl.add_theme_color_override("font_color", DANGER_TEXT if days < 1.0 else (WARN if days < 3.0 else INK3))
	if _stores_calm != null:
		_stores_calm.update(sim)    # (the town's slim stores: which pairs and days are shown, the tooltips)
	crew_keys = {}
	if avatar_ui and profile == "":    # (the One House has no 1 to 5: a click on a card is the way)
		var n := 0
		for q in WheelCtl.crew_of(sim.people):
			n += 1
			if n <= WheelCtl.KEYS:
				crew_keys[q] = n
	for c in cards:
		_update_card(c, sim)
	# clock
	var m := int(sim.minutes)
	var h: float = sim.hour
	day_label.text = _day_text(sim, speed)
	var pc: Color = PHASE_COLOR.get(sim.phase, ACCENT)
	phase_chip.add_theme_stylebox_override("panel", _chip_style(pc))
	phase_icon.texture = icons[PHASE_ICON.get(sim.phase, "sun")]
	phase_icon.modulate = pc
	paused_pill.visible = speed == 0
	var rung := bool(sim.bell_rung)
	if rung and not clock_bell.visible:
		_swing_bell()
	clock_bell.visible = rung
	# in a narrow window the clock has no room for the day as well as the pill: the pill takes its place
	day_label.visible = not (speed == 0 and compact)
	phase_label.text = String(sim.phase).to_upper()
	phase_label.add_theme_color_override("font_color", pc)
	time_label.text = "%02d:%02d" % [m / 60, m % 60]
	# (the season's own dawn and dusk; a game that is not a campaign is Autumn's 6.5 and 19.0)
	var seasons = sim.get("seasons")
	var to_dawn := fposmod((seasons.dawn_hour() if seasons != null else 6.5) - h, 24.0)
	var to_dusk := fposmod((seasons.dusk_hour() if seasons != null else 19.0) - h, 24.0)
	var next_name := "Dusk" if sim.phase == "day" else "Dawn"
	var next_h := to_dusk if sim.phase == "day" else to_dawn
	until_label.text = "%s in %dh %02dm" % [next_name, int(next_h), int(fmod(next_h, 1.0) * 60.0)]
	strip.hour = h
	strip.seasons = seasons
	strip.queue_redraw()
	var temp := roundi(seasons.temperature(h)) if seasons != null and seasons.campaign else roundi(9.0 + 8.0 * maxf(0.0, sin((h - 8.0) / 24.0 * TAU)))
	temp_icon.texture = icons[PHASE_ICON.get(sim.phase, "sun")]
	temp_label.text = "%d°C, %s" % [temp, sim.skies.word() if sim.get("skies") != null else sim.weather]    # (the town's sky has more words: overcast, drizzle, rain, storm)
	if profile != "":
		# (the town's word is "the dead", and the count is the ones awake round you: the rest are asleep where they stand)
		walkers_label.text = "no dead about" if walkers == 0 else "%d dead about" % walkers
	else:
		walkers_label.text = "%d walkers" % walkers
	_update_forecast(sim)
	_update_gate(sim)
	# speed and sound
	if speed != last_speed:
		last_speed = speed
		for i in speed_buttons.size():
			var b: Button = speed_buttons[i]
			var on := i == speed
			b.add_theme_stylebox_override("normal", _lit_look(on))
			b.get_meta("icon").modulate = ACCENT if on else INK2
	sound_button.get_meta("icon").texture = icons["soundOn" if sound_on else "soundOff"]
	var sound_tip := "Turn the sound off" if sound_on else "Turn the sound on"
	if sound_button.tooltip_text != sound_tip:
		sound_button.tooltip_text = sound_tip
	_sync_alerts(sim)
	_refresh_selection()
	_sync_radio(sim)
	_sync_talk()
	_sync_briefing()
	if jobs_screen != null:
		jobs_screen.refresh()
	if build_screen != null:
		build_screen.refresh()
	if town_board_open():
		scavenge_dialog.refresh()
	_sync_town(sim)
	_sync_lots(sim)


## The clock's day: "DAY 7 OF 30" (a game that is not a campaign), or in a campaign the season and the day in it,
## "WINTER, DAY 5 OF 24" ("WINTER 5/24" in a narrow window, and while the game is paused: the PAUSED pill takes
## the room of the longer words, so that the clock does not widen).
func _day_text(sim, speed: int = 1) -> String:
	var seasons = sim.get("seasons")
	if seasons != null and seasons.campaign:
		var season_name := String(seasons.current().name).to_upper()
		return ("%s %d/%d" if compact or speed == 0 else "%s, DAY %d OF %d") % [season_name, seasons.season_day(sim.scenario.day()), seasons.season_length()]
	var day: int = sim.scenario.day()
	if profile != "" and sim.has_method("is_one_house") and sim.is_one_house():
		return "DAY %d" % day    # (the One House run has no day limit: it ends when the first attack night is held)
	if sim.has_method("is_demo") and sim.is_demo():
		day = mini(day, int(sim.scenario.total_days()))    # (round 26: the dawn that ends the demo is not "DAY 4 OF 3")
	return ("DAY %d/%d" if compact else "DAY %d OF %d") % [day, sim.scenario.total_days()]


## The fuel row of the stores (round 13): there in a settlement game once there is a vehicle or any fuel; the number is in the
## amber while the tank is low and there is a vehicle to burn it. Not there, the panel is as it was.
func _update_fuel(sim) -> void:
	var rules = sim.get("vehicles")
	var on: bool = profile == "" and rules != null and sim.get("town") != null and sim.town.on and (not rules.fleet.is_empty() or float(rules.fuel) > 0.0)
	if fuel_cells.is_empty():
		return
	# (the name is left out, as the others' are, in a narrow window: see _on_resized)
	var changed: bool = on != fuel_cells[2].visible
	fuel_cells[0].visible = on
	fuel_cells[1].visible = on and not compact
	fuel_cells[2].visible = on
	if changed:
		_layout_dock.call_deferred()
	if not on:
		return
	var amount := roundi(float(rules.fuel))
	fuel_cells[2].text = str(amount)
	var low: bool = float(rules.fuel) < FUEL_LOW and not rules.fleet.is_empty()
	fuel_cells[2].add_theme_color_override("font_color", WARN if low else INK)
	var tip := "Fuel: %d. A vehicle burns it on the road; the gas stations and the fuel depot have more." % amount
	for c in fuel_cells:
		c.tooltip_text = tip
		c.mouse_filter = Control.MOUSE_FILTER_PASS


## The Town Board's button is in the toolbar, and the G of the help says so, only in a settlement game.
func _sync_town(sim) -> void:
	var on: bool = profile == "" and sim.get("town") != null and sim.town.on
	if town_button != null and town_button.visible != on:
		town_button.visible = on
		_layout_dock.call_deferred()
	if help_g != null:
		var word := ("Map" if panel_ui() else "Town Board") if on else ("Map" if panel_ui() else "Scavenge")    # (no town: an old save plays with an avatar, and its Map page says so)
		if help_g.text != word:
			help_g.text = word
		var g_tip := HELP_G_TOWN_TIP if on else ""
		if help_g.tooltip_text != g_tip:
			help_g.tooltip_text = g_tip
			help_g.mouse_filter = Control.MOUSE_FILTER_PASS if on else Control.MOUSE_FILTER_IGNORE


## In a settlement game (round 9) the Build screen has the streets round the school too: the button's tooltip and the help's N say so.
func _sync_lots(sim) -> void:
	var on: bool = sim.get("lots") != null and sim.lots.on
	if build_button != null:
		var tip := (BUILD_LOTS_TIP_AVATAR if panel_ui() else BUILD_LOTS_TIP) if on else (BUILD_TIP_AVATAR if panel_ui() else BUILD_TIP)
		if profile != "":
			tip = BUILD_TIP_TOWN    # (the One House: the page of the base's projects)
		if build_button.tooltip_text != tip:
			build_button.tooltip_text = tip
	if help_n != null:
		var tip := HELP_N_LOTS_TIP if on else ""
		if help_n.tooltip_text != tip:
			help_n.tooltip_text = tip
			help_n.mouse_filter = Control.MOUSE_FILTER_PASS if on else Control.MOUSE_FILTER_IGNORE


## The lookout's forecast under the clock: from the hour he tells it (17:00) until dawn,
## and only while he can tell it; at other times the line is not there.
func _update_forecast(sim) -> void:
	_fit_clock_words()
	var f: Dictionary = sim.tactics.forecast()
	var text := ""
	var whole := ""
	var ready := {}
	if bool(f.get("given", false)) and sim.phase != "dawn":
		# (in a campaign the last night of a season that has seasons to come is its Big Night, not the last)
		var last: bool = NightKit.last_night(sim)
		if String(sim.player_id) != "" and NightKit.has_outlook(f):
			# round 19, avatar mode: the outlook of the night (its kind, size, side, brutes and hours) and the community's reading of it; in a
			# narrow window (the clock is 164 px across there) the short forms, with the whole line as the tooltip
			whole = NightKit.forecast_line(f, last)
			text = NightKit.forecast_line_compact(f, last) if compact else whole
			ready = NightKit.ready_line_compact(f) if compact else NightKit.ready_line(f)
		else:
			text = _forecast_text(f, last)
	if forecast_label.text != text:
		forecast_label.text = text
	forecast_label.visible = text != "" and not _forecast_squeezed
	var forecast_tip := whole if whole != text else (FORECAST_TIP if text != "" else "")
	if forecast_label.tooltip_text != forecast_tip:
		forecast_label.tooltip_text = forecast_tip
		forecast_label.mouse_filter = Control.MOUSE_FILTER_PASS if forecast_tip != "" else Control.MOUSE_FILTER_IGNORE
	var ready_text := String(ready.get("text", ""))
	if ready_text != "" and Access.markers():
		ready_text = ("+ " if bool(ready.get("holds", false)) else "- ") + ready_text    # (Colour-blind markers: the green and the amber of the reading are a plus and a minus too)
	if ready_label.text != ready_text:
		ready_label.text = ready_text
	ready_label.visible = ready_text != "" and not _forecast_squeezed
	if ready_text != "":
		ready_label.add_theme_color_override("font_color", OK if bool(ready.get("holds", false)) else WARN)
	_update_night_badge(sim, f)


## A click on the clock's Gate row (round 23): main.gd works the gate (at the lever) or says where the lever is.
func _on_gate_row_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		gate_row.accept_event()
		if on_gate.is_valid():
			on_gate.call()


## The gate's lamp and word in the clock (round 22): there only while the gate's rules are in charge (avatar mode). The lamp is the picture's
## (green open, red shut, amber on the move); the word is amber when the gate is open in the dark.
func _update_gate(sim) -> void:
	if gate_row == null:
		return
	var open := GateKit.open_of(GateKit.active_gate(sim))
	if _gate_last >= 0.0 and not is_equal_approx(open, _gate_last):
		_gate_dir = 1 if open > _gate_last else -1
	_gate_last = open
	var st: Dictionary = GateKit.status(sim, _gate_dir, bool(sim.is_night()))
	var on := bool(st.on)
	if gate_row.visible != on:
		gate_row.visible = on
		_layout_dock.call_deferred()
	if not on:
		_gate_last = -1.0
		_gate_dir = 0
		return
	if gate_label.text != String(st.text):
		gate_label.text = String(st.text)
	var col: Color = WARN if bool(st.dark) else INK2
	if gate_label.get_theme_color("font_color") != col:
		gate_label.add_theme_color_override("font_color", col)
	if gate_lamp.color != st.lamp:
		gate_lamp.color = st.lamp
		gate_lamp.queue_redraw()


## The words of the gate's indicator now ("" while it is not shown): "Gate: open".
func gate_text() -> String:
	return gate_label.text if gate_row != null and gate_row.visible else ""


## The call card's words and buttons wrap at the column's width less the card's margins (see CallCard.set_wrap).
func _fit_card_words() -> void:
	if call_card == null or call_card.get("view") == null:
		return
	var w := CLOCK_W_COMPACT if compact else CLOCK_W
	call_card.set_wrap(float(w) - call_card.get_theme_stylebox("panel").get_minimum_size().x - 2.0)


## The forecast lines wrap at the clock's width: given it as their least, they measure right whether they show or are put away (and are not
## wider than the clock after the window has been made narrower).
func _fit_clock_words() -> void:
	if forecast_label == null or ready_label == null or clock == null:
		return
	var inner := _clock_inner_w()
	for l in [forecast_label, ready_label]:
		RadioKit.wrap_at(l, inner)


## The width the clock's own words wrap at: its width less its board's margins.
func _clock_inner_w() -> float:
	var st: StyleBox = clock.get_theme_stylebox("panel")
	return maxf(60.0, float(CLOCK_W_COMPACT if compact else CLOCK_W) - (st.get_minimum_size().x if st != null else 28.0) - 2.0)


## The badge of a Big Night by the day counter (avatar mode): "Big Night tomorrow" from the radio desk's notice, "Big Night" tonight once
## told; its tooltip is the notice or the forecast. Not there for an ordinary night, without the notice or without an avatar.
func _update_night_badge(sim, f: Dictionary) -> void:
	var b: Dictionary = NightKit.badge(sim, f)
	_badge_state = String(b.get("state", ""))
	night_badge.visible = _badge_state != ""
	if _badge_state == "":
		return
	var word := String(b.get("text", ""))
	if night_badge_label.text != word:
		night_badge_label.text = word
	night_badge.tooltip_text = String(b.get("tip", ""))


## "tomorrow", "tonight" or "": what the badge by the day counter says now.
func badge_state() -> String:
	return _badge_state


## "Tonight: about 55 from the north east, a brute"; "..., runners"; on the last night
## "The last night: about 120, from everywhere" ("The Big Night: ..." when `last` is false: a season of a campaign
## that has others to come).
func _forecast_text(f: Dictionary, last: bool = true) -> String:
	if bool(f.get("big", false)):
		return "%s: about %d, from everywhere" % ["The last night" if last else "The Big Night", int(f.get("total", 0))]
	var text := "Tonight: about %d" % int(f.get("total", 0))
	var heading := String(f.get("heading", ""))
	if heading != "":
		text += " from the %s" % heading
	var brutes := int(f.get("brutes", 0))
	if brutes > 0:
		text += ", a brute" if brutes == 1 else ", %d brutes" % brutes
	elif bool(f.get("runners", false)):
		text += ", runners"
	return text


func _rank(a: Dictionary) -> int:
	return 3 if a.level == "danger" else (2 if a.level == "warn" else 1)


## About how much health a fresh one of this kind has, for the meter: a walker's is
## five, the others the middle of their range (see kinds.gd).
func _zombie_hp(z) -> float:
	var k: Dictionary = Kinds.KINDS.get(String(z.kind), Kinds.KINDS.walker)
	if z.kind == Kinds.WALKER:
		return 5.0
	return maxf(1.0, (float(k.hp[0]) + float(k.hp[1])) / 2.0)


func _doing_zombie(z) -> String:
	match z.state:
		"dead", "dying":
			return "Dead for good"
		"attack":
			return "Clawing at the %s" % String(z.slot.seg.name).to_lower()
		"approach":
			return String(ZOMBIE_VERBS.get(String(z.kind), ZOMBIE_VERBS.walker))
		"breach":
			return "Inside the yard, hunting"
		"retreat":
			return "Drifting back into the city"
	return "Wandering the street"


## What a person is doing, or why they are not.
## What a person is doing, in words (the order wheel says it under the ring).
func doing_of(p) -> String:
	return _doing_person(p)


func _doing_person(p) -> String:
	if p.dead:
		if p.turned:
			return "Turned into one of the dead"
		return "Left through the gate" if p.away is Dictionary and String(p.away.get("kind", "")) == "exile" else "Dead"
	if p.away != null:
		return _away_text(p)
	if p.downed:
		# the medical module says what ("Down and bleeding", "Collapsed from hunger", "Resting in the infirmary")
		return p.activity if p.activity != "" else "Down and bleeding"
	if _breakdown(p):
		return "Having a breakdown"
	if p.reloading > 0.0:
		return "Reloading"
	if p.target != null:
		return "Shooting at a walker"
	return p.activity


## "Scavenging at the pharmacy" for someone out with a scavenging party.
func _away_text(p) -> String:
	if p.away is Dictionary and sim_ref != null:
		if String(p.away.get("kind", "")) == "garrison":
			return "Holding %s" % String(sim_ref.town.place(String(p.away.get("place", ""))).get("name", "an outpost"))
		var id := String(p.away.get("site", ""))
		for site in sim_ref.scavenge.sites:
			if String(site.get("id", "")) == id:
				return "Scavenging at %s" % String(site.get("where", String(site.get("name", "")).to_lower()))
	return "Away scavenging"


## [text, colour] for the Needs row, from the game hours since a meal and a drink.
func _needs_of(p) -> Array:
	if p.dead:
		return ["–", INK3]
	var bits: Array = []
	var severe := false
	if p.hunger_h >= STARVING_H:
		bits.append("Starving")
		severe = true
	elif p.hunger_h >= HUNGRY_H:
		bits.append("Hungry")
	if p.thirst_h >= PARCHED_H:
		bits.append("Parched")
		severe = true
	elif p.thirst_h >= THIRSTY_H:
		bits.append("Thirsty")
	if bits.is_empty():
		return ["Fed", INK]
	var text: String = bits[0]
	for i in range(1, bits.size()):
		text += ", " + String(bits[i]).to_lower()
	return [text, DANGER_TEXT if severe else WARN]


## [text, colour] for the Wounds row.
func _wounds_of(p) -> Array:
	if p.dead:
		return ["–", INK3]
	if p.wounds > 0:
		return ["%d wound%s, bleeding" % [p.wounds, "" if p.wounds == 1 else "s"], DANGER_TEXT]
	if p.bleeding > 0.0:
		return ["Bleeding", DANGER_TEXT]
	return ["None", INK2]


func _set_text(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


# --------------------------------------------------------------- the people --
# Round 4: the rows of the person panel that come from the people's modules (sim.morale, traits, bonds,
# skills and barks). Each is read through `_mod`, so a game that has none of them (an older fake) just has
# no such row; every modifier the rules apply to a person is in a tooltip here.

## A module of the game by name, or null in a game that has none.
func _mod(name: String):
	return null if sim_ref == null else sim_ref.get(name)


## `text` broken at spaces into lines of about `width` letters: a tooltip is as wide as its longest line.
static func _wrap(text: String, width: int = TIP_WRAP) -> String:
	var lines: Array = []
	var line := ""
	for word in text.split(" "):
		if line != "" and line.length() + 1 + word.length() > width:
			lines.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	if line != "":
		lines.append(line)
	return "\n".join(lines)


## "+5", "-8", "+0.4", "+5.4": a number with its sign, whole when it is.
static func _signed(x: float) -> String:
	if absf(x) < 0.0001:
		return "0"
	if absf(x - roundf(x)) < 0.05:
		return "%+d" % roundi(x)
	return "%+.1f" % x


## Whether `p` is in a breakdown just now: they cannot shoot or be ordered (the morale module says; a game
## without one has none).
func _breakdown(p) -> bool:
	var m = _mod("morale")
	return m != null and m.get("enabled") != false and m.has_method("breakdown") and bool(m.breakdown(p))


## Whether `p` is dead and remembered (as against turned, or sent out through the gate).
func _remembered(p) -> bool:
	return p.dead and not p.turned and not (p.away is Dictionary and String(p.away.get("kind", "")) == "exile")


## The line said about `p` now that they are gone (the barks' epitaph), or "" when nothing is said.
func _epitaph(p) -> String:
	var b = _mod("barks")
	if b == null or not b.has_method("epitaph"):
		return ""
	var line = b.epitaph(p)
	return String(line).strip_edges() if line is String else ""


## How many points each skill of `p` has gained: what the skills module says, else what they hold over the roster.
func _gained(p) -> Dictionary:
	var sk = _mod("skills")
	if sk != null and sk.has_method("gained"):
		var g = sk.gained(p)
		if g is Dictionary:
			return g
	var out := {}
	var mine = p.get("skills")
	if mine is Dictionary:
		for k in mine:
			var n := int(mine[k]) - int(p.def.skills.get(k, mine[k]))
			if n > 0:
				out[k] = n
	return out


## The tooltip of a skill: its number and where it started, and what makes it grow (the skills module's own
## table: a point for so many kills, so much wall mended...), how far, and what a trait adds.
func _skill_tip(p, skill_name: String, now: int, up: int) -> String:
	var tip := "%s %d" % [skill_name, now]
	if up > 0:
		tip += " (started at %d, +%d from practice)" % [now - up, up]
	var sk = _mod("skills")
	var kinds = sk.get("KINDS") if sk != null else null
	var feeds: Array = []
	if kinds is Dictionary:
		for kind in kinds:
			if kinds[kind] is Dictionary and String(kinds[kind].get("skill", "")) == skill_name:
				feeds.append("%d %s" % [roundi(float(kinds[kind].get("per", 0.0))), SKILL_UNITS.get(kind, String(kind))])
	if feeds.is_empty():
		tip += "\nGrows with use: %s." % String(SKILL_FED.get(skill_name, "practice"))
	else:
		tip += "\nA point for every " + " or ".join(feeds) + "."
		var cap = sk.get("MAX_GAIN")
		if cap != null:
			tip += "\nAt most %d over where they started." % int(cap)
	var t = _mod("traits")
	var xp: float = float(t.mult(p, "xp")) if t != null and t.has_method("mult") else 1.0
	if absf(xp - 1.0) > 0.01:
		tip += "\nLearns %d%% %s." % [roundi(absf(xp - 1.0) * 100.0), "faster" if xp > 1.0 else "slower"]
	return tip


## The record on a person's name: kills (and tonight's), shots, walls mended, people treated, scrap made into
## ammo; only what is more than nothing, except the kills. "" when the game keeps no counters.
func _stats_tip(p) -> String:
	var st = p.get("stats")
	if not (st is Dictionary):
		return ""
	var kills := int(st.get("kills", 0))
	var tonight := int(st.get("kills_night", 0))
	var lines: Array = ["Kills: %d (%d tonight)" % [kills, tonight] if tonight > 0 else "Kills: %d" % kills]
	if int(st.get("shots", 0)) > 0:
		lines.append("Shots fired: %d" % int(st.get("shots", 0)))
	if roundi(float(st.get("mended", 0.0))) > 0:
		lines.append("Wall mended: %d HP" % roundi(float(st.get("mended", 0.0))))
	if int(st.get("treated", 0)) > 0:
		lines.append("Treated: %d" % int(st.get("treated", 0)))
	if roundi(float(st.get("crafted", 0.0))) > 0:
		lines.append("Scrap made into ammo: %d" % roundi(float(st.get("crafted", 0.0))))
	return "\n".join(lines)


## What a bond does, in words: with the rules' own numbers (bonds.AIM_TILES, AIM_BONUS, morale.NEAR_BOND and the
## Loyal trait's addition) when the modules have them, in general words when they do not.
func _bond_words(p) -> String:
	var b = _mod("bonds")
	var m = _mod("morale")
	var t = _mod("traits")
	var tiles = b.get("AIM_TILES") if b != null else null
	var bonus = b.get("AIM_BONUS") if b != null else null
	var steady = m.get("NEAR_BOND") if m != null else null
	if tiles == null or bonus == null or steady == null:
		return "Steadier near them, and a loss hits hard."
	var aim: float = float(bonus) + (float(t.add(p, "bond")) if t != null and t.has_method("add") else 0.0)
	return "Within %d tiles: steadier (%s mood) and aims %d%% better.\nA loss hits hard." % [roundi(float(tiles)), _signed(float(steady)), roundi(aim * 100.0)]


## The tooltip of the mood row: how they are (or the breakdown), every reason with its sign, and what it costs
## or gives in work and aim.
func _mood_tip(p, m, word: String, value: float, broke: bool) -> String:
	var lines: Array = []
	if broke:
		lines.append(_wrap("Having a breakdown: %s cannot shoot or be ordered until it passes" % p.first))
		lines.append("Mood %d out of 100" % roundi(value))
	else:
		lines.append("%s (%d out of 100)" % [word, roundi(value)])
	var reasons: Array = []
	if m.has_method("explain"):
		var got = m.explain(p)
		if got is Array:
			reasons = got
	for i in mini(reasons.size(), MOOD_LINES):
		var r: Dictionary = reasons[i]
		# a shock (a kill, a friend lost) fades away; what they are now stays while it is so
		lines.append("%s %s%s" % [_signed(float(r.get("value", 0.0))), String(r.get("label", "")), " (fading)" if bool(r.get("recent", false)) else ""])
	if reasons.size() > MOOD_LINES:
		lines.append("and %d smaller" % (reasons.size() - MOOD_LINES))
	if reasons.is_empty():
		lines.append("Nothing is moving it right now")
	elif m.has_method("target"):
		lines.append("Settling toward %d" % roundi(float(m.target(p))))
	var perf: float = float(m.perf(p)) if m.has_method("perf") else 1.0
	if absf(perf - 1.0) > 0.004:
		lines.append("Works and aims at %d%% of their best" % roundi(perf * 100.0))
	return "\n".join(lines)


## The mood row, in line with the game: the bar, the word (a breakdown is its own word), the tooltip. For a
## person who is remembered the row is a memorial (the epitaph); for one who turned or left there is none; with
## no morale module, or while the tutorial has morale off, there is none for the living.
func _refresh_mood(p) -> void:
	var refs := inspect_refs
	var m = _mod("morale")
	var mood_on: bool = m != null and m.get("enabled") != false and not p.dead
	var memo_on := _remembered(p)
	refs.mood_head.visible = mood_on or memo_on
	refs.mood_row.visible = mood_on or memo_on
	refs.mood_bar.visible = mood_on
	refs.mood_word.visible = mood_on
	refs.mood_memo.visible = memo_on
	if memo_on:
		var line := _epitaph(p)
		if line == "":
			line = "%s will not be forgotten" % p.first
		if refs.mood_head.text != "MEMORY":
			refs.mood_head.text = "MEMORY"
		if refs.mood_memo.text != line:
			refs.mood_memo.text = line
			refs.mood_memo.tooltip_text = _wrap(line)
		return
	if refs.mood_head.text != "MOOD":
		refs.mood_head.text = "MOOD"
	if not mood_on:
		return
	var broke := _breakdown(p)
	var word := String(m.mood(p))
	var value := float(m.value(p))
	var key := "Breaking" if broke else word
	var bar_value := clampf(value / 100.0, 0.0, 1.0)
	var bar_color: Color = MOOD_COLORS.get(key, OK)
	if not is_equal_approx(refs.mood_bar.value, bar_value) or refs.mood_bar.color != bar_color:
		refs.mood_bar.value = bar_value
		refs.mood_bar.color = bar_color
		refs.mood_bar.queue_redraw()
	_set_text(refs.mood_word, "Breakdown" if broke else word, MOOD_TEXT.get(key, INK))
	var tip := _mood_tip(p, m, word, value, broke)
	for c in [refs.mood_head, refs.mood_bar, refs.mood_word]:
		if c.tooltip_text != tip:
			c.tooltip_text = tip


## The chips of the person's traits (rebuilt when they change), each with its blurb as the tooltip.
func _refresh_traits(p) -> void:
	var refs := inspect_refs
	var t = _mod("traits")
	var list: Array = []
	if t != null and t.has_method("of"):
		var got = t.of(p)
		if got is Array:
			list = got
	# round 20: a title earned (the medic...) is a gold chip first, with the numbers in its tooltip ("" when they have none)
	var title_sig := CommunityKit.title_sig(sim_ref, p)
	refs.traits_head.visible = not list.is_empty() or title_sig != ""
	refs.traits_box.visible = not list.is_empty() or title_sig != ""
	var sig := title_sig
	for tr in list:
		sig += "%s|%s|%s;" % [tr.get("id", ""), tr.get("name", ""), tr.get("blurb", "")]
	if sig == refs.traits_sig:
		return
	refs.traits_sig = sig
	for c in refs.traits_box.get_children():
		refs.traits_box.remove_child(c)
		c.queue_free()
	if title_sig != "":
		var chip = CommunityKit.title_chip(self, sim_ref, p)
		if chip != null:
			refs.traits_box.add_child(chip)
	for tr in list:
		var blurb := String(tr.get("blurb", ""))
		refs.traits_box.add_child(_chip(String(tr.get("name", "")), _wrap(blurb if blurb != "" else String(tr.get("name", "")))))


## "Marcus (family), Ana (friend)" and the tooltip with the full names, what a bond is for and, while a friend
## is close, what it is doing for their aim.
func _refresh_bonds(p) -> void:
	var refs := inspect_refs
	# round 20: who they are at odds with is a row of its own under this one (made when somebody has a rival)
	CommunityKit.sync_rivals(self, refs, sim_ref, p)
	var b = _mod("bonds")
	var list: Array = []
	if b != null and b.has_method("of"):
		var got = b.of(p)
		if got is Array:
			list = got
	refs.bonds_head.visible = not list.is_empty()
	refs.bonds.visible = not list.is_empty()
	if list.is_empty():
		return
	var short: Array = []
	var full: Array = []
	for e in list:
		var who = e.who
		# what the other is to them (a mentor's student is "student"); the kind when the module does not say
		var role := String(e.get("role", e.get("kind", "friend")))
		# one who is gone (dead, turned or sent out) is still on the line, and says so
		short.append("%s (%s%s)" % [who.first, role, ", gone" if who.dead else ""])
		full.append("%s (%s%s)" % [who.name, role, ", gone" if who.dead else ""])
	var tip := "Close to:\n" + "\n".join(full) + "\n" + _bond_words(p)
	if b.has_method("aim_bonus") and not p.dead and float(b.aim_bonus(p)) > 0.0:
		tip += "\nA friend is close now: aims %d%% better." % roundi(float(b.aim_bonus(p)) * 100.0)
	# round 20: how each friendship stands, and since when
	var stands := CommunityKit.bond_tip(sim_ref, p)
	if stands != "":
		tip += "\n" + stands
	_set_text(refs.bonds, ", ".join(short), INK)
	for c in [refs.bonds, refs.bonds_head]:
		if c.tooltip_text != tip:
			c.tooltip_text = tip


## Each skill's number (the person's own copy, never the roster's), what it has gained, its bar and its tooltip.
func _refresh_skills(p) -> void:
	var cells = inspect_refs.get("skills")
	if not (cells is Dictionary):
		return
	var gained := _gained(p)
	var mine = p.get("skills")
	for skill_name in cells:
		var cell: Dictionary = cells[skill_name]
		var base := int(p.def.skills.get(skill_name, 0))
		var now: int = int(mine.get(skill_name, base)) if mine is Dictionary else base
		var up := int(gained.get(skill_name, 0))
		_set_text(cell.value, str(now), INK)
		var gain_text := "+%d" % up if up > 0 else ""
		if cell.gain.text != gain_text:
			cell.gain.text = gain_text
		cell.gain.visible = up > 0
		var bar: Bar = cell.bar
		if not is_equal_approx(bar.value, now / 10.0) or not is_equal_approx(bar.gain, up / 10.0):
			bar.value = now / 10.0
			bar.gain = up / 10.0
			bar.queue_redraw()
		var tip := _skill_tip(p, skill_name, now, up)
		if cell.box.tooltip_text != tip:
			cell.box.tooltip_text = tip


## The job tag in the person panel's header: "Job: Workbench" (or "Job: none"), what the station does and how to
## change it in its tooltip. Not for someone who is gone, nor in a game with no jobs.
func _refresh_job_tag(p) -> void:
	var tag: PanelContainer = inspect_refs.job_tag
	var jobs = _jobs()
	tag.visible = jobs != null and not p.dead
	if not tag.visible:
		return
	var st: Dictionary = jobs.station(_job_of(p))
	var text := "Job: %s" % String(st.get("name", "")) if not st.is_empty() else "Job: none"
	var label: Label = tag.get_child(0)
	if label.text != text:
		label.text = text
	var tip := ""
	if st.is_empty():
		tip = "Day job: none. They %s by day." % jobs.no_job_text()
	else:
		tip = "Day job: %s (%s)\n%s" % [String(st.name), String(st.get("where", "")), _wrap(String(st.get("blurb", "")))]
	tip += "\nClick to open the Jobs screen. Key: J"
	if tag.tooltip_text != tip:
		tag.tooltip_text = tip


## The person's rows that come from round 4's modules, in line with the game as it is now.
func _refresh_people_rows(p) -> void:
	_refresh_mood(p)
	_refresh_traits(p)
	_refresh_bonds(p)
	_refresh_skills(p)
	_refresh_trust(p)
	var record := _stats_tip(p)
	if inspect_refs.name.tooltip_text != record:
		inspect_refs.name.tooltip_text = record


func _refresh_selection() -> void:
	if selection == null or inspect_refs.is_empty():
		return
	var f := 1.0
	var doing := ""
	if selection.kind == "person":
		var p = selection.ref
		f = p.hp / 100.0
		doing = _doing_person(p)
		var need := _needs_of(p)
		_set_text(inspect_refs.needs, need[0], need[1])
		var wound := _wounds_of(p)
		_set_text(inspect_refs.wounds, wound[0], wound[1])
		var stage: String = sim_ref.medical.infection_stage(p) if sim_ref != null else ""
		inspect_refs.infection.visible = stage != ""
		inspect_refs.infection_head.visible = stage != ""
		_set_text(inspect_refs.infection, stage.capitalize(), WARN)
		_refresh_job_tag(p)
		# "Making ammo" while the workshop's mark is on them, with the mark's own tip
		var ammo_tip := _ammo_mark_tip(p)
		inspect_refs.craft_tag.visible = ammo_tip != ""
		if ammo_tip != "" and inspect_refs.craft_tag.tooltip_text != ammo_tip:
			inspect_refs.craft_tag.tooltip_text = ammo_tip
		_refresh_people_rows(p)
		var pips: HBoxContainer = inspect_refs.pips
		var n := pips.get_child_count()
		if n > 0:
			var full := roundi(float(p.mag) / float(p.gun.mag) * n)
			for i in n:
				var pip: ColorRect = pips.get_child(i)
				pip.color = ACCENT if i < full else Color(1, 1, 1, 0.14)
		if inspect_refs.get("gizmo_sig") != _gizmo_sig():
			_build_gizmos()
	elif selection.kind == "zombie":
		var z = selection.ref
		f = maxf(0.0, z.hp) / _zombie_hp(z)
		doing = _doing_zombie(z)
	else:
		var s = selection.ref
		f = s.hp / s.max_hp
		var n := 0
		for sl in s.slots:
			if sl.who != null:
				n += 1
		if s.state == 3:
			doing = "Breached"
		elif n > 0:
			doing = "%d walker%s clawing at it" % [n, "s" if n > 1 else ""]
		elif f < 1.0:
			doing = "Damaged"
		else:
			doing = "Holding"
	var b: Bar = inspect_refs.hp
	b.value = clampf(f, 0.0, 1.0)
	b.color = _hp_color(f)
	b.queue_redraw()
	inspect_refs.hpv.text = "%d%%" % roundi(clampf(f, 0.0, 1.0) * 100.0)
	if inspect_refs.doing.text != doing:
		inspect_refs.doing.text = doing
	_refresh_gizmo_tips()


# ------------------------------------------------------------------- the radio --
# Round 17: the radio's views. The rules are scripts/sim/radio.gd; the views are scripts/ui/radio_verbs.gd (the verbs of a contact),
# call_card.gd / call_view.gd (a call that waits for an answer) and news_panel.gd (the log). Each is given this HUD, for its looks, and
# a Callable that returns the radio, so the raid's HUD mounts the same pieces over its own. All of it is there in avatar mode only
# (`avatar_ui`: main.gd's `set_avatar`, noticed from the sim at each update); without an avatar the dock, the toolbar and the alerts
# are as they were.

## The radio of the game being shown, or null.
func _radio():
	return null if sim_ref == null else sim_ref.get("radio")


func _build_radio_ui() -> void:
	var getter := func(): return _radio()
	var speed_getter := func(): return maxi(last_speed, 1)
	# the verbs of the person picked: in the dock, in place of the order buttons
	radio_box = _panel(_style(PANEL, 6, LINE, true, "panel_slim"))
	radio_box.size_flags_vertical = Control.SIZE_SHRINK_END
	radio_box.visible = false
	radio_verbs = RadioVerbs.new()
	radio_box.add_child(radio_verbs)
	dock.add_child(radio_box)
	radio_verbs.setup(self, getter, {"place": false})
	radio_verbs.requested.connect(_on_radio_requested)
	# the oldest open call: under the alerts
	call_card = CallCard.new()
	right_col.add_child(call_card)
	call_card.setup(self, getter, {"speed_getter": speed_getter})
	# the radio panel (round 18): Jobs, Build, Map and News, in the free band above the toolbar, where the controls help also opens (one or
	# the other); the News page is the log of round 17 (`news_panel`)
	radio_panel = RadioPanel.new()
	add_child(radio_panel)
	radio_panel.setup(self, func(): return sim_ref)
	radio_panel.changed.connect(_on_radio_panel_changed)
	news_panel = radio_panel.page_node("news")
	_corner(radio_panel, true, true, 12, _help_lift())


## Avatar mode comes or goes (`set_avatar` says so): the toolbar's News and Alarm, the dock's verbs and the call card appear or are put away.
func _apply_radio_mode(on: bool) -> void:
	if news_button == null:
		return
	news_button.visible = on
	alarm_button.visible = on
	# (round 24: with an avatar the digits pick the crew, so the speeds are Shift and 1 2 3; the One House picks nobody)
	_speed_tips(on)
	jobs_button.tooltip_text = JOBS_TIP_AVATAR if on and not tutorial_ui else JOBS_TIP
	town_button.tooltip_text = TOWN_TIP_AVATAR if on and not tutorial_ui else TOWN_TIP
	_town_tips()
	if not on:
		radio_panel.close()
		news_dot.visible = false
		call_card.clear()
		_light(news_button, false)
		_light(alarm_button, false)
	if selection != null:
		_build_gizmos()
	_layout_dock()
	_layout_toast()
	_layout_news()


## The One House's own words on the toolbar's Jobs, Build and radio keys (the school's say "Shift+N: the full page", which is not the town's).
func _town_tips() -> void:
	if profile == "" or news_button == null:
		return
	jobs_button.tooltip_text = JOBS_TIP_TOWN
	build_button.tooltip_text = BUILD_TIP_TOWN
	news_button.tooltip_text = NEWS_TIP_TOWN


## The speed buttons' tooltips: "Key: Shift+2" in the school's avatar game (the digits pick the crew there), "Key: 2" in the One House.
func _speed_tips(avatar: bool = avatar_ui) -> void:
	for i in speed_buttons.size():
		var key := String(SPEED_TIPS[i][1])
		speed_buttons[i].tooltip_text = "%s\nKey: %s" % [SPEED_TIPS[i][0], ("Shift+" + key) if avatar and i > 0 and profile == "" else key]


## A toolbar key lit or dark.
func _light(b: Button, on: bool) -> void:
	var look := _lit_look(on)
	# (a lit key keeps the key's size: the frame's own margins would make it wider than an unlit one, and the toolbar with it)
	look.set_content_margin_all(0)
	b.add_theme_stylebox_override("normal", look)
	b.get_meta("icon").modulate = ACCENT if on else INK2


## A request went to the radio (the dock's verbs): what they said, or why they cannot, in a toast as well as in the dock.
func _on_radio_requested(contact, _verb: String, result: Dictionary) -> void:
	# (somebody has been asked for something: the first screen's hint has taught what it was for)
	hint_spent = true
	_refresh_hint()
	if bool(result.get("ok", false)):
		var line := String(result.get("line", ""))
		if line != "":
			toast("%s: %s" % [String(contact.first), line])
	else:
		var why := String(result.get("why", ""))
		if why != "":
			toast(why, "warn")


## The Trust row of the person panel: [row, bar, word], as the Mood row has them.
func _trust_row() -> Array:
	var row := _hbox(8)
	var b := Bar.new()
	b.custom_minimum_size = Vector2(60, 6)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.groove = frame("bar_track")
	b.value = 0.55
	b.color = OK
	row.add_child(b)
	var word := _label("willing", Fonts.cond(600), 13, INK)
	word.custom_minimum_size.x = MOOD_W
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	word.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(word)
	return [row, b, word]


## How far the person trusts the player: a bar and a word (willing, grudging, doubtful), and in a tooltip why it has moved. Not for the
## player themself, the dead, or anywhere there is no avatar.
func _refresh_trust(p) -> void:
	var refs := inspect_refs
	if not refs.has("trust_head"):
		return
	var radio = _radio()
	var show: bool = avatar_ui and radio != null and not p.dead and not p.turned and not p.player
	refs.trust_head.visible = show
	refs.trust_row.visible = show
	if not show:
		return
	var trust := float(radio.trust_of(p))
	var tone := String(radio.tone_of(p))
	var bar: Bar = refs.trust_bar
	var value := clampf(trust / 100.0, 0.0, 1.0)
	var col: Color = TRUST_BAR.get(tone, OK)
	if not is_equal_approx(bar.value, value) or bar.color != col:
		bar.value = value
		bar.color = col
		bar.queue_redraw()
	_set_text(refs.trust_word, tone, TRUST_WORD.get(tone, INK))
	var tip := _trust_tip(p, radio, trust, tone)
	for c in [refs.trust_head, refs.trust_bar, refs.trust_word]:
		if c.tooltip_text != tip:
			c.tooltip_text = tip


func _trust_tip(p, radio, trust: float, tone: String) -> String:
	var lines: Array = ["%s's trust in you: %s (%d of 100)" % [p.first, tone, roundi(trust)]]
	lines.append(_wrap("The more they trust you, the faster and the more gladly they answer the radio. Bring them home and it grows; push them, or lead them into harm, and it falls."))
	var why: Array = radio.trust_why(p)
	if why.is_empty():
		lines.append("Nothing has moved it yet: everyone starts at 55.")
	else:
		lines.append("Lately:")
		for r in why:
			lines.append(_wrap("%s  %s (day %d)" % [_signed(float(r.delta)), String(r.why), int(r.day)], 64))
	# round 20: how their ideas have gone, and who people turn to
	for line in CommunityKit.trust_lines(sim_ref, p):
		lines.append(_wrap(String(line), 64))
	return "\n".join(lines)


## The dock in avatar mode, with a person selected: the radio box where the order buttons were. Beside the panel when there is room (two
## columns of whole names), else above it (three columns), else, in a short window, one row of short names. The box is the same height
## whatever it says, so it does not jump.
func _layout_dock_radio() -> void:
	gizmos.visible = false
	gizmo_count = 0
	gizmo_mini = false
	var panel_w := maxf(float(INSPECT_W), inspect.get_combined_minimum_size().x)
	var reserve := _right_reserve()
	radio_verbs.set_form(2, false)
	var fits := panel_w + 8.0 + radio_box.get_combined_minimum_size().x <= size.x - 24.0 - reserve
	dock.vertical = not fits
	if fits:
		dock.move_child(inspect, 0)
		radio_box.size_flags_vertical = Control.SIZE_SHRINK_END
		dock.queue_sort()
		return
	dock.move_child(radio_box, 0)
	radio_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	radio_verbs.set_form(3, false)
	var room := size.y - 12.0 - (12.0 + left_col.get_combined_minimum_size().y + 24.0)
	if radio_box.get_combined_minimum_size().y + 8.0 + inspect.get_combined_minimum_size().y > room:
		radio_verbs.set_form(6, true)
	dock.queue_sort()


## How much of the window's width the boards at the right of the foot keep from the dock: the toolbar and the controls help, and the radio
## panel while it is up (it is the widest), with a gap.
func _right_reserve() -> float:
	var w := maxf(speed_panel.get_combined_minimum_size().x, help.get_combined_minimum_size().x)
	if radio_open():
		w = maxf(w, _radio_panel_width())
	return w + 8.0


## How wide the radio panel is (its form in this window), whether or not it is up.
func _radio_panel_width() -> float:
	return minf(RadioPanel.WIDTH_COMPACT if compact else RadioPanel.WIDTH, maxf(180.0, size.x - 24.0))


## The width the dock takes from the left edge when the radio box is beside the panel (the toast keeps clear of it).
func _radio_dock_width() -> float:
	if radio_box == null or not radio_box.visible:
		return float(INSPECT_W)
	if dock.vertical:
		return maxf(float(INSPECT_W), radio_box.get_combined_minimum_size().x)
	return float(INSPECT_W) + 8.0 + radio_box.get_combined_minimum_size().x


## The rectangles of the boards that cover the world now: what a speech bubble keeps out from under (overlay_node.gd). `skip` are boards left
## out (the talk card asks without itself).
func covered_rects(skip: Array = []) -> Array:
	var out: Array = []
	var parts: Array = [res_panel, crew_load_panel, clock, ammo_panel, alerts_box, call_card, inspect, radio_box, gizmos, speed_panel, help, radio_panel, fields_legend]
	for c in cards:
		parts.append(c.card)
	parts.append(talk_card)
	parts.append(briefing_card.panel if briefing_open() else null)
	for c in parts:
		if c != null and is_instance_valid(c) and c is Control and not skip.has(c) and c.is_visible_in_tree():
			var r: Rect2 = c.get_global_rect()
			if r.size.x > 0.0 and r.size.y > 0.0:
				out.append(r)
	return out


## The rectangle the dock takes at the foot of the window (the selection's panel and, beside or above it, the radio's verbs or the
## order buttons): empty when nothing is selected. The yard's camera keeps the avatar out from under it.
func dock_rect() -> Rect2:
	if dock == null or not dock.is_visible_in_tree():
		return Rect2()
	var out := Rect2()
	var any := false
	for c in dock.get_children():
		if c is Control and c.is_visible_in_tree():
			var r: Rect2 = c.get_global_rect()
			if r.size.x > 0.0 and r.size.y > 0.0:
				out = r if not any else out.merge(r)
				any = true
	return out


# ---- the radio panel (round 18), the News wrappers, the alarm, the call card

## Opens the radio panel on `page` ("base", "jobs", "build", "map" or "news"; "" for the page it was left on, News the first time), or moves it there;
## `opts.focus` goes to the page's `focus_on` (a person id, a station id, a building id, a place id). Avatar mode only: without an avatar, and
## while a modal page has the screen, nothing happens. The panel never pauses the game; opening it takes the place of the controls help.
func open_radio(page: String = "", opts: Dictionary = {}) -> void:
	if radio_panel == null or not avatar_ui or game_over != null or modal_open():
		return
	radio_panel.open(page, opts)


func close_radio() -> void:
	if radio_panel != null:
		radio_panel.close()


## The key of a page: opens the panel on it, shuts it when it is already on that page, moves to another page ("" is the key of the panel
## itself: its last page, or shut).
func toggle_radio(page: String = "") -> void:
	if radio_panel == null:
		return
	if radio_panel.is_open() and (page == "" or page == radio_panel.page()):
		radio_panel.close()
	else:
		open_radio(page)


func radio_open() -> bool:
	return radio_panel != null and radio_panel.is_open()


## The page of the radio panel that is up ("" while it is shut).
func radio_page() -> String:
	return radio_panel.page() if radio_panel != null else ""


## The part of the window the world can be seen in: the whole of it, or while the radio panel is up what is left of it at the panel's left (so
## not under the panel, nor the clock column above it; the crew's cards are across the top of what is left). main.gd keeps the avatar in the
## middle of it.
func free_view() -> Rect2:
	var whole := Rect2(Vector2.ZERO, size)
	if not radio_open():
		return whole
	var r: Rect2 = radio_panel.get_global_rect() if radio_panel.is_visible_in_tree() else Rect2()
	if r.size.x <= 0.0:
		return whole
	var right := clampf(r.position.x - 8.0, 0.0, whole.size.x)
	return Rect2(0.0, 0.0, right, whole.size.y)


## The radio panel was opened, shut or moved to another page: the toolbar's keys, the help, the hint and the room of the alerts follow.
func _on_radio_panel_changed() -> void:
	var on := radio_open()
	var page := radio_page()
	if on and help != null:
		help.visible = false
	_light(news_button, on and page == "news")
	_light(jobs_button, on and page == "jobs")
	_light(build_button, on and page == "build")
	_light(town_button, on and page == "map")
	if not on and sim_ref != null:
		_sync_alerts(sim_ref)
	if on and news_dot != null and page == "news":
		news_dot.visible = false
	_refresh_hint()
	_layout_dock()
	_layout_toast()
	_layout_news()


# (round 17's News, as wrappers over the News page of the panel)

func news_open() -> bool:
	return radio_page() == "news"


func toggle_news() -> void:
	toggle_radio("news")


## Opens or shuts the News page (avatar mode only). Shutting it reads everything.
func set_news(on: bool) -> void:
	if on == news_open():
		return
	if on:
		open_radio("news")
	else:
		close_radio()


func _press_help() -> void:
	help.visible = not help.visible
	if help.visible and radio_open():
		close_radio()
	_refresh_hint()


## The call to arms from the toolbar: rings it, or stands everyone down (the radio does the rest and says it in a banner).
func _press_alarm() -> void:
	var radio = _radio()
	if radio == null or not avatar_ui:
		return
	if on_alarm.is_valid() and not bool(on_alarm.call()):
		return
	var on: bool = not radio.alarm_on
	radio.alarm(on)
	if not on:
		toast("Stood down: back to work")
	_sync_alarm(radio)


func _sync_alarm(radio) -> void:
	var on := bool(radio.alarm_on)
	if on != bool(alarm_button.get_meta("lit", false)) or alarm_button.tooltip_text != (ALARM_OFF_TIP if on else ALARM_TIP):
		alarm_button.set_meta("lit", on)
		_light(alarm_button, on)
		alarm_button.tooltip_text = ALARM_OFF_TIP if on else ALARM_TIP


## How many alerts the feed makes a panel for: as many as it ever does (what the column has room for is `_layout_news`'s say, and it only
## hides the panels it has no room for: it never makes the feed shorter for good).
func _alert_cap() -> int:
	if _alert_feed != null:
		return _alert_feed.cap()    # (the town: three cards, the rest folded under "+N more")
	return ALERTS_MAX_COMPACT if compact else ALERTS_MAX


## The alert panels of the feed, in order (the most urgent first).
func _alert_panels() -> Array:
	var out: Array = []
	for c in alerts_box.get_children():
		if c is Control and not c.is_queued_for_deletion():
			out.append(c)
	return out


## Shows the first `n` panels of the feed and hides the rest (-1: all of them).
func _show_alert_panels(n: int) -> void:
	var panels := _alert_panels()
	for i in panels.size():
		var on: bool = n < 0 or i < n
		if panels[i].visible != on:
			panels[i].visible = on


## The right column in avatar mode: the clock, the gun's readout, the alerts and the call card hang one under the other, and the radio
## panel (when it is open) takes what is left down to the toolbar; while it is open the call card steps aside, the panel keeping the oldest
## open call in view itself (the News page lists them with their buttons, the other pages have a slim strip under the tabs). The call is a
## decision and an alert only says something, so the card claims its room first (it tells less of itself only when it has none even with no
## alert), then the alerts take what is left, the most urgent first, and when there is not enough for the panel's least height (MIN_H) when it
## is open, the least urgent give up theirs. Every pass starts from the whole feed and counts afresh (the heights are those the panels would
## have, laid out or not: see `_update_alert_panel`), so what was hidden comes back as soon as there is room. What does not fit in the panel
## scrolls.
func _layout_news() -> void:
	if radio_panel == null:
		return
	var w := CLOCK_W_COMPACT if compact else CLOCK_W
	call_card.custom_minimum_size.x = w
	_fit_card_words()
	if not avatar_ui:
		_show_alert_panels(-1)
		return
	var lift := _help_lift()
	var need := RadioPanel.MIN_H if radio_open() else 0.0
	call_card.set_suppressed(radio_open())
	var edge := lift + 12.0 + 8.0
	var bare := right_col.get_combined_minimum_size().y - alerts_box.get_combined_minimum_size().y
	# round 20: an idea tells more than the old calls did (the voice's line, a yes that wraps): when even with no alerts the card is
	# taller than the room it has, it tells less of itself (the lines under its title first), and all of it again when there is room.
	# Before that (a narrow, short window) the clock puts its forecast lines away: the call says as much, and every option of a call must
	# be in view
	var squeeze := false
	if call_card.visible:
		call_card.set_level(0)
		var held := _forecast_lines_height(true) if _forecast_squeezed else 0.0
		var room_card: float = size.y - edge - (right_col.get_combined_minimum_size().y - alerts_box.get_combined_minimum_size().y - call_card.get_combined_minimum_size().y) - held
		squeeze = call_card.get_combined_minimum_size().y > room_card and _forecast_lines_height(true) > 0.0
		if squeeze != _forecast_squeezed:
			_set_forecast_squeezed(squeeze)
			room_card = size.y - edge - (right_col.get_combined_minimum_size().y - alerts_box.get_combined_minimum_size().y - call_card.get_combined_minimum_size().y)
		call_card.fit(room_card)
		bare = right_col.get_combined_minimum_size().y - alerts_box.get_combined_minimum_size().y
	elif _forecast_squeezed:
		_set_forecast_squeezed(false)
		bare = right_col.get_combined_minimum_size().y - alerts_box.get_combined_minimum_size().y
	# (the 8 px of `edge` past the column is the gap the radio panel keeps under the column: with no panel up the alerts have the room it would take)
	var room := size.y - edge - bare + (0.0 if radio_open() else 8.0)
	var panels := _alert_panels()
	var shown := 0
	var used := 0.0
	for i in panels.size():
		var h: float = _alert_height(panels[i]) + (ALERT_GAP if i > 0 else 0.0)
		if room - (used + h) < need:
			break
		used += h
		shown += 1
	_show_alert_panels(shown)
	var avail := size.y - edge - right_col.get_combined_minimum_size().y
	if radio_open():
		radio_panel.set_compact(compact)
		radio_panel.fit(avail, size.x - 24.0)
		_corner(radio_panel, true, true, 12.0, lift)


## What the clock's forecast lines (the outlook and the readiness) take of its height while they show (`natural`: while they have words,
## whether they are put away or not), the gaps between them included.
func _forecast_lines_height(natural: bool = false) -> float:
	var gap := float((forecast_label.get_parent() as BoxContainer).get_theme_constant("separation"))
	var h := 0.0
	for l in [forecast_label, ready_label]:
		if (l.visible and not natural) or (natural and l.text != ""):
			h += l.get_combined_minimum_size().y + gap
	return h


## Puts the clock's forecast lines away (or brings them back): `_update_forecast` keeps them away while it is on.
func _set_forecast_squeezed(on: bool) -> void:
	_forecast_squeezed = on
	forecast_label.visible = forecast_label.text != "" and not on
	ready_label.visible = ready_label.text != "" and not on


## Each update, in avatar mode: the call card and the News panel follow the radio, the dot says whether anything is unread, the alarm key
## shows whether the alarm is on, and the dock's verbs follow the game (who is down, who is busy).
func _sync_radio(sim) -> void:
	if radio_box == null or not avatar_ui:
		return
	var radio = sim.get("radio")
	if radio == null:
		return
	call_card.refresh()
	if (call_card.shown_id != 0) != _call_seen:
		_call_seen = call_card.shown_id != 0
		_refresh_hint()
	radio_panel.refresh()
	news_dot.visible = not news_open() and news_panel.unread() > 0
	_sync_alarm(radio)
	if radio_box.visible:
		radio_verbs.refresh()
	_layout_news()


# ---- coach hooks (tutorial) ----
# For the tutorial's coach (scripts/ui/coach.gd) and nothing else: they read the HUD's parts and
# ghost buttons, and change nothing the HUD does. Written by TUTORIAL: leave this block at the end.

## What the tutorial step allows right now, as a Callable(kind, arg) -> bool (kinds "gizmo" with
## an order's id, "speed" with 0 to 3, "fields", "jobs" and "build"), or an invalid Callable when nothing is locked.
var lock_allowed: Callable


## The global rectangle of a named part of the HUD, or an empty Rect2 when it is not there (not
## built, hidden, or the selection has no such button). Looked up by name each time: the cards,
## the order buttons and the dialog are rebuilt. Names: `stores`, `stores.<ammo|scrap|food|water|
## meds|fuel>`, `card:<person id>`, `bar`, `clock`, `clock.time`, `clock.forecast`, `clock.night` (the badge of a Big Night, avatar mode), `clock.gate` (the gate's lamp and word, avatar mode), `alerts`, `inspect`,
## `inspect.weapon`, `gizmo:<order id>`, `speed`, `speed.<0 to 3>`, `fields`, `help`, `sound`, `jobs` (the
## toolbar's Jobs button, and while the Jobs screen is open its parts: `jobs.screen`, `jobs.auto`, `jobs.clear`,
## `jobs.close`, `jobs.list`, `jobs.row:<person id>`, `jobs.job:<id>`, `jobs.post:<id>`, `jobs.station:<id>` and
## `jobs.item:<id>`), `town` (the toolbar's Town Board button: there only in a settlement game), `build` (the toolbar's Build button, and while the Build screen is open its parts: `build.screen`,
## `build.close`, `build.row:<plot id>`, `build.detail`, `build.order:<building id>`, `build.cancel`, `build.demolish`
## and `build.jobs`; in a settlement game `build.lots` (the Lots slip), `build.map`, `build.pin:<plot id>`, `build.claim:<lot id>` and `build.walling:<lot id>`, the switch of a claimed lot's standing order),
## `legend`, `toast`, `banner` and, while the scavenging dialog is open, `dialog.send`,
## `dialog.cancel`, `dialog.site:<site id>` and `dialog.party`; in avatar mode (round 17) `news` (the toolbar's News button), `news.panel`,
## `alarm` (the toolbar's call to arms), `radio` (the verbs in the dock), `radio.<verb>` (one verb's button: come, hold, cover, search,
## back, post), `radio.insist` (the Insist button, there after a refusal), `ammo` (the readout of the gun), `call` (the call card) and `talk` (the card E at a person opens);
## round 18: `panel` (the radio panel), `panel.tab:<page>` (a tab: base, jobs, build, map, news) and `panel.page` (the page that is up; the part of it in view when it scrolls);
## round 25: `briefing` (the morning briefing's card).
func anchor_rect(name: String) -> Rect2:
	if name.begins_with("stores."):
		return _anchor_store(name.trim_prefix("stores."))
	if name == "alerts":
		return _anchor_alerts()
	var c = _anchor_control(name)
	if c == null or not is_instance_valid(c) or not (c is Control) or not c.is_visible_in_tree():
		return Rect2()
	var r: Rect2 = c.get_global_rect()
	# (a page that is taller than the room scrolls: the part of it that is on screen is the anchor, not the whole page, most of which may be out of view)
	if name == "panel.page" and radio_panel.scroll != null:
		r = r.intersection(radio_panel.scroll.get_global_rect())
	return r if r.size.x > 0.0 and r.size.y > 0.0 else Rect2()


func _anchor_control(name: String):
	if name.begins_with("card:"):
		var id := name.trim_prefix("card:")
		for c in cards:
			if c.p.id == id:
				return c.card
		return null
	if name.begins_with("gizmo:"):
		var gid := name.trim_prefix("gizmo:")
		if gizmos == null:
			return null
		for b in gizmos.get_children():
			if b is Button and b.has_meta("id") and String(b.get_meta("id")) == gid and not b.is_queued_for_deletion():
				return b
		return null
	if name.begins_with("panel.tab:"):
		return radio_panel.tab_button(name.trim_prefix("panel.tab:")) if radio_panel != null else null
	if name == "panel.page":
		return radio_panel.pages.get(radio_panel.page()) if radio_panel != null and radio_panel.is_open() else null
	if name.begins_with("radio."):
		if name == "radio.insist":
			return radio_verbs.insist_button if radio_verbs != null else null
		return radio_verbs.buttons.get(name.trim_prefix("radio.")) if radio_verbs != null else null
	if name.begins_with("speed."):
		var i := name.trim_prefix("speed.").to_int()
		return speed_buttons[i] if i >= 0 and i < speed_buttons.size() else null
	if name.begins_with("dialog."):
		return _anchor_dialog(name.trim_prefix("dialog."))
	if name.begins_with("jobs."):
		return _anchor_jobs(name.trim_prefix("jobs."))
	if name.begins_with("build."):
		return _anchor_build(name.trim_prefix("build."))
	match name:
		"stores":
			return res_panel
		"bar":
			return bar
		"clock":
			return clock
		"clock.time":
			return time_label
		"clock.forecast":
			return forecast_label
		"clock.gate":
			return gate_row
		"clock.night":
			return night_badge
		"inspect":
			return inspect
		"inspect.weapon":
			# the "Weapon" row of a person's panel: the gun's name and the pips of its magazine
			var pips = inspect_refs.get("pips") if selection != null and selection.kind == "person" else null
			return pips.get_parent() if pips != null and is_instance_valid(pips) else null
		"speed":
			return speed_panel
		"fields":
			return fields_button
		"help":
			return help_button
		"jobs":
			return jobs_button
		"build":
			return build_button
		"town":
			return town_button
		"news":
			return news_button
		"news.panel":
			return news_panel
		"panel":
			return radio_panel
		"alarm":
			return alarm_button
		"ammo":
			return ammo_panel
		"radio":
			return radio_box
		"call":
			return call_card
		"talk":
			return talk_card
		"briefing":
			return briefing_card.panel if briefing_card != null and is_instance_valid(briefing_card) and briefing_card.is_open() else null
		"sound":
			return sound_button
		"legend":
			return fields_legend
		"toast":
			return toast_panel
		"banner":
			return banner
	return null


## One store's row in the stores panel: as wide as the panel, as tall as its number (and, for
## food and water, the days left under it).
func _anchor_store(kind: String) -> Rect2:
	var v = res_values.get(kind)
	if v == null or res_panel == null or not is_instance_valid(v) or not res_panel.is_visible_in_tree():
		return Rect2()
	var r: Rect2 = v.get_global_rect()
	var d = res_days.get(kind)
	if d != null and is_instance_valid(d):
		r = r.merge(d.get_global_rect())
	var panel: Rect2 = res_panel.get_global_rect()
	return Rect2(panel.position.x + 6.0, r.position.y - 3.0, panel.size.x - 12.0, r.size.y + 6.0)


## Where the alerts are: their column, or, with none up, the space under the clock where
## they appear.
func _anchor_alerts() -> Rect2:
	if alerts_box == null or clock == null or not alerts_box.is_visible_in_tree():
		return Rect2()
	var r: Rect2 = alerts_box.get_global_rect()
	if r.size.y >= 8.0:
		return r
	var c: Rect2 = clock.get_global_rect()
	return Rect2(c.position.x, c.end.y + 10.0, c.size.x, 60.0)


func _anchor_dialog(part: String):
	var d = scavenge_dialog
	if d == null or not is_instance_valid(d):
		return null
	if part == "send":
		return d.get("send_button")
	if part == "cancel":
		return d.get("cancel_button")
	if part == "close":
		return d.get("close_button")    # (the Town Board's)
	if part == "party":
		return d.get("party_box")
	if part.begins_with("site:"):
		var cards_of = d.get("site_cards")
		var entry = cards_of.get(part.trim_prefix("site:")) if typeof(cards_of) == TYPE_DICTIONARY else null
		return entry.card if entry != null else null
	return null


## A part of the Jobs screen while it is open: `screen`, `auto`, `clear`, `close`, `list` (the open list), `row:<person id>`,
## `job:<person id>` and `post:<person id>` (a person's buttons), `station:<station id>` (a card) and `item:<id>` (a line of
## the open list, by the station's or the post's id).
func _anchor_jobs(part: String):
	var s = jobs_screen
	if s == null or not is_instance_valid(s):
		return null
	match part:
		"screen":
			return s.get("panel")
		"auto":
			return s.get("auto_button")
		"clear":
			return s.get("clear_button")
		"close":
			return s.get("close_button")
		"list":
			return s.get("list")
	var kind := part.get_slice(":", 0)
	var id := part.get_slice(":", 1)
	if kind == "row" or kind == "job" or kind == "post":
		var rows = s.get("rows")
		return rows[id].get(kind) if typeof(rows) == TYPE_DICTIONARY and rows.has(id) else null
	if kind == "station":
		var station_cards = s.get("station_cards")
		return station_cards[id].card if typeof(station_cards) == TYPE_DICTIONARY and station_cards.has(id) else null
	if kind == "item":
		var items = s.get("list_items")
		return items.get(id) if typeof(items) == TYPE_DICTIONARY else null
	return null


## A part of the Build screen while it is open: `screen`, `close`, `detail` (the card of the chosen plot), `row:<plot id>`
## (a plot's slip), `order:<building id>` (an Order button), `cancel`, `demolish` and `jobs` (the button for the Jobs screen); and,
## in a settlement game, `lots` (the Lots slip), `map`, `pin:<plot id>` (a plot's pin on the map) and `claim:<lot id>` (a Claim button).
func _anchor_build(part: String):
	var s = build_screen
	if s == null or not is_instance_valid(s):
		return null
	match part:
		"screen":
			return s.get("panel")
		"close":
			return s.get("close_button")
		"detail":
			return s.get("detail")
		"cancel":
			return s.get("cancel_button")
		"demolish":
			return s.get("demolish_button")
		"jobs":
			return s.get("jobs_button")
		"lots":
			return s.get("lots_row")
		"map":
			return s.get("map")
	var kind := part.get_slice(":", 0)
	var id := part.get_slice(":", 1)
	if kind == "row":
		var rows = s.get("rows")
		return rows[id].row if typeof(rows) == TYPE_DICTIONARY and rows.has(id) else null
	if kind == "order":
		var entries = s.get("entries")
		return entries[id].order if typeof(entries) == TYPE_DICTIONARY and entries.has(id) else null
	if kind == "pin":
		var m = s.get("map")
		return m.pins.get(id) if m != null and m.pins.has(id) else null
	if kind == "claim":
		var cards = s.get("lot_cards")
		return cards[id].claim if typeof(cards) == TYPE_DICTIONARY and cards.has(id) else null
	if kind == "walling":
		var cards2 = s.get("lot_cards")
		return cards2[id].switch if typeof(cards2) == TYPE_DICTIONARY and cards2.has(id) else null
	return null

## Ghosts the order buttons, the speed buttons and the fields button that the tutorial step
## does not allow: dimmed, no hover look, a cursor that says no. They can still be pressed (the
## game refuses the order and says why in a toast). An invalid Callable lifts the lock.
func set_locked(allowed: Callable) -> void:
	lock_allowed = allowed
	apply_lock()


## Puts the lock's look on the buttons as they are now. The order buttons are rebuilt with
## the selection and the HUD brightens them every tenth of a second, so the coach calls this
## every frame while a lock is on.
func apply_lock() -> void:
	var locking := lock_allowed.is_valid()
	if gizmos != null:
		for b in gizmos.get_children():
			if b is Button and b.has_meta("id") and not b.is_queued_for_deletion():
				_ghost(b, locking and not bool(lock_allowed.call("gizmo", String(b.get_meta("id")))))
	for i in speed_buttons.size():
		_ghost(speed_buttons[i], locking and not bool(lock_allowed.call("speed", i)))
	if fields_button != null:
		_ghost(fields_button, locking and not bool(lock_allowed.call("fields", null)))
	if jobs_button != null:
		_ghost(jobs_button, locking and not bool(lock_allowed.call("jobs", null)))
	if build_button != null:
		_ghost(build_button, locking and not bool(lock_allowed.call("build", null)))
	if town_button != null:
		_ghost(town_button, locking and not bool(lock_allowed.call("gizmo", "scavenge")))
	if alarm_button != null and alarm_button.visible:
		_ghost(alarm_button, locking and not bool(lock_allowed.call("alarm", null)))


func _ghost(b: Button, locked: bool) -> void:
	var was := bool(b.get_meta("coach_ghost", false))
	if locked:
		if not was:
			b.set_meta("coach_ghost", true)
			b.set_meta("coach_hover", b.get_theme_stylebox("hover"))
			b.set_meta("coach_pressed", b.get_theme_stylebox("pressed"))
			var plain: StyleBox = b.get_theme_stylebox("normal") if b.has_meta("id") else StyleBoxEmpty.new()
			b.add_theme_stylebox_override("hover", plain)
			b.add_theme_stylebox_override("pressed", plain)
			b.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
		b.modulate.a = 0.35
	elif was:
		b.set_meta("coach_ghost", false)
		b.add_theme_stylebox_override("hover", b.get_meta("coach_hover"))
		b.add_theme_stylebox_override("pressed", b.get_meta("coach_pressed"))
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
		b.modulate.a = 1.0


# ---- the talk card (round 18, slice 2: E at a person) ----
# The card beside the person that E opens (scripts/ui/talk_card.gd): what they say of themselves, what they need (a button to the radio
# panel's page that deals with it), how far they trust you and the radio's verbs for them. A view only. main.gd's E key calls `show_talk`;
# Esc, E again, the distance and the person's fall call `hide_talk` (or the card closes itself, see `TalkCard.ending`). Anchor name:
# `talk`. The card is a board over the yard, never a modal: the game does not stop and WASD still walks.

const TalkCard := preload("res://scripts/ui/talk_card.gd")

## The card (made by `setup`) and where a tile of the world is on this HUD: a Callable(tile: Vector2) -> pixels that main.gd sets (the
## canvas transform stands in when there is none).
var talk_card
var talk_anchor: Callable


func _build_talk_card() -> void:
	talk_card = TalkCard.new()
	add_child(talk_card)
	talk_card.setup(self)


## Opens the talk card for `p` (avatar mode only). `result` is what the rules' `interact.talk_to(p)` said (its line, its needs, the
## trust earned): without it the card says what it can of its own.
func show_talk(p, result: Dictionary = {}) -> void:
	if talk_card == null or p == null or not avatar_ui:
		return
	talk_card.open(p, result)


func hide_talk() -> void:
	if talk_card != null:
		talk_card.close("hide")


func talk_open() -> bool:
	return talk_card != null and talk_card.is_open()


## The person the card is for, or null.
func talk_person():
	return talk_card.person if talk_open() else null


func _sync_talk() -> void:
	if talk_card != null and talk_card.is_open():
		talk_card.refresh()


# ---- the briefing card (round 25, V25.1: the morning briefing) ----
# The slim card under the crew bar that the `briefing` event brings (scripts/ui/briefing_card.gd): the base's concerns, ranked, and the six priority chips.
# A view only, never a modal (the game does not stop, WASD still walks, every control takes no focus). main.gd calls `queue_briefing()` on the event,
# `close_briefing("esc")` for Esc (after the talk card, before the radio panel) and the staging flag `--briefing` `show_briefing()`; the Details
# button opens the Base page (`open_radio("base")`). Anchor name: `briefing` (the card's board).

const BriefingCard := preload("res://scripts/ui/briefing_card.gd")
## The card waits for the dawn card to close, and shows anyway after this long (real seconds).
const BRIEFING_WAIT_S := 18.0

## The card (null while none is up), and what main.gd tells the HUD about the screen: a Callable() -> bool that is true while the dawn card or the storyteller's
## card is up (unset: nothing is in the way).
var briefing_card = null
var briefing_gate: Callable
## The briefing is waiting to be shown, and how many real seconds of waiting it has left before it is shown whatever is up.
var briefing_wanted := false
var briefing_wait_left := 0.0
var _briefing_msec := 0
var _briefing_compact := false


## The `briefing` event: the card is shown once nothing is in the way (the dawn card has closed, no modal is up), or after BRIEFING_WAIT_S.
func queue_briefing() -> void:
	if not avatar_ui or tutorial_ui:
		return
	briefing_wanted = true
	briefing_wait_left = BRIEFING_WAIT_S
	_briefing_msec = Time.get_ticks_msec()


## Shows the card now: `data` is the sim's `briefing.current` ({"day", "lines", "order", "suggested"}); without it the card is made from the sim's own
## `briefing.current` of today, else from the concerns as they are now. False when there is no avatar, the tutorial has the screen or there is no game.
func show_briefing(data: Dictionary = {}) -> bool:
	if sim_ref == null or not avatar_ui or tutorial_ui or game_over != null:
		return false
	close_briefing("replaced")
	briefing_wanted = false
	var card := BriefingCard.new()
	add_child(card)
	card.setup(self, data if not data.is_empty() else _briefing_data())
	card.closed.connect(_on_briefing_closed.bind(card))
	briefing_card = card
	_briefing_compact = compact
	card.set_compact(compact)
	if radio_panel != null:
		radio_panel.note_briefing_seen()
	return true


## What the card shows when it is not handed the sim's snapshot: today's `briefing.current` or the concerns as they stand.
func _briefing_data() -> Dictionary:
	var sim = sim_ref
	var b = sim.get("briefing") if sim != null else null
	var out := {"day": int(sim.day) if sim != null else 1, "lines": [], "order": [], "suggested": []}
	if b == null:
		return out
	var cur = b.get("current")
	if cur is Dictionary and int((cur as Dictionary).get("day", 0)) == int(sim.day) and not ((cur as Dictionary).get("lines", []) as Array).is_empty():
		return (cur as Dictionary).duplicate(true)
	if b.has_method("concerns"):
		var lines: Array = []
		for c in b.concerns():
			if c is Dictionary and String(c.get("level", "info")) != "ok":
				lines.append(c)
		out.lines = lines
	return out


func briefing_open() -> bool:
	return briefing_card != null and is_instance_valid(briefing_card) and briefing_card.is_open()


## Puts the card away (Esc, or the HUD when the avatar goes). `why` is for the card's `closed` signal.
func close_briefing(why: String = "dismiss") -> void:
	briefing_wanted = false
	if briefing_open():
		briefing_card.close(why)


func _on_briefing_closed(_why: String, card) -> void:
	if briefing_card == card:
		briefing_card = null


## Each update: the waiting card is shown when the way is clear (or its time is up), the open card follows the window's form and goes with the avatar.
func _sync_briefing() -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _briefing_msec) / 1000.0, 0.0, 1.0)
	_briefing_msec = now
	if not avatar_ui or tutorial_ui:
		if briefing_wanted or briefing_open():
			close_briefing("gone")
		return
	if briefing_open():
		if compact != _briefing_compact:
			_briefing_compact = compact
			briefing_card.set_compact(compact)
		return
	if not briefing_wanted:
		return
	briefing_wait_left = maxf(0.0, briefing_wait_left - dt)
	var in_the_way: bool = briefing_gate.is_valid() and bool(briefing_gate.call())
	if (in_the_way and briefing_wait_left > 0.0) or modal_open():
		return
	show_briefing()
