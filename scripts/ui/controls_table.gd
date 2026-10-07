## The ONE table of the One House's controls: every key and mouse button the town run answers to, in the groups the player reads them in. The Controls page of the Esc menu
## (scripts/ui/controls_menu.gd), the HUD's help panel (the "?" in the toolbar: `hud.help_groups()`), the legend of keys in the first minute (scripts/ui/key_legend.gd) and the README's
## table are all made from, or checked against, this one list, so they cannot disagree.
##
## Every key here was read off the town run's own handlers (2026-10-06): scripts/main.gd `_unhandled_input` (Space, 1 2 3 the speeds, Esc, R, Q, F, E, T, G, L, J, N, V, F5, F9),
## `_input` (F11), scripts/ui/town_hud.gd `on_key` (M, Shift+N, Shift+G), scripts/ui/wheel_ctl.gd `key_down` (C, Shift+C, Z, Esc), scripts/ui/rescue_card.gd (1 2 3, E, Esc) and
## scripts/ui/dawn_tally.gd (Enter, Space), and PACE's two: X, held, polled by scripts/ui/pace_keys.gd (Shift is the aim's twin, so the run has a key of its own) and `.`, scripts/ui/wait_button.gd `on_key`. What is NOT here is not in the town: Tab and 1 to 5 (nobody is "picked": a click on a person or a card opens the wheel), the middle button's
## wheel, a right-click order, Y (the school's gate is off in the town) and B (the town has no Base page; its radio panel has Jobs, Build, Map and News).
##
## A row is {"keys": chips split at spaces ("|" between two chips reads "or"), "what": the words of the Controls page, "hud": [keys, words] for the narrow help panel, "aim": "" (always),
## "right" (only with "Right button aims") or "always" (only with "Always aim at the mouse"), "legend": [line, id, key, words] for the first minute's legend (omitted: not in it; the lines are "a",
## "b" and "c": what the hands do, what the player reaches for, and the three keys of the day's own pace, build, run and wait)}.
extends RefCounted

const AimMode := preload("res://scripts/aim_mode.gd")

const GROUPS := [
	{
		"title": "Move and fight",
		"rows": [
			{"keys": "W A S D", "what": "Walk. The arrow keys do too", "hud": ["W A S D", "Walk"], "legend": ["a", "move", "WASD", "move"]},
			{"keys": "X", "what": "Hold to run: faster for a few seconds, and the dead hear your feet", "hud": ["X", "Hold to run"], "legend": ["c", "run", "X", "run"]},
			{"keys": "Right-click", "what": "Hold to aim at the pointer. Shift aims too", "hud": ["Right-click", "Hold to aim"], "aim": "right", "legend": ["a", "aim", "Right-click", "aim"]},
			{"keys": "Click", "what": "Fire, while you aim", "hud": ["Click", "Fire, aiming"], "aim": "right", "legend": ["a", "fire", "Click", "fire"]},
			{"keys": "Mouse", "what": "Aim at the pointer; the left button fires", "hud": ["Mouse", "Aim and fire"], "aim": "always", "legend": ["a", "aim", "Mouse", "aim"]},
			{"keys": "Click", "what": "Fire", "hud": ["Click", "Fire"], "aim": "always", "legend": ["a", "fire", "Click", "fire"]},
			{"keys": "R", "what": "Reload", "hud": ["R", "Reload"], "legend": ["a", "reload", "R", "reload"]},
			{"keys": "F", "what": "Swing, whatever you hold", "hud": ["F", "Swing"], "legend": ["a", "swing", "F", "swing"]},
			{"keys": "E", "what": "Use: search, claim, build, talk, sleep, treat", "hud": ["E", "Use, search"], "legend": ["b", "use", "E", "use"]},
			{"keys": "E", "what": "Hold: search the whole room, when it is clear and has two containers or more", "hud": ["E", "Hold: whole room"]},
			{"keys": "Q", "what": "Put the weapon away, or draw it again", "hud": ["Q", "Weapon away"], "legend": ["b", "away", "Q", "weapon away"]},
			{"keys": "Scroll", "what": "Zoom, with the wheel or a pinch", "hud": ["Scroll", "Zoom"]},
		],
	},
	{
		"title": "The crew: ask, do not order",
		"rows": [
			{"keys": "Click", "what": "A person or a card: the order wheel opens", "hud": ["Click", "A person, a card"], "aim": "right"},
			{"keys": "Click", "what": "A card: the order wheel opens (in the world it fires)", "hud": ["Click", "A card"], "aim": "always"},
			{"keys": "C", "what": "Hold: the wheel, for whoever is nearest", "hud": ["C", "Wheel, hold"]},
			{"keys": "Shift C", "what": "Hold both: everyone within eight tiles", "hud": ["Shift C", "Wheel: all near"]},
			{"keys": "Z", "what": "The last order again, to the same people", "hud": ["Z", "Last order again"]},
			{"keys": "Esc", "what": "Close the wheel. A click outside it does too", "hud": ["Esc", "Close the wheel"]},
		],
	},
	{
		"title": "Panels and time",
		"rows": [
			{"keys": "T", "what": "The radio panel: the news, and the calls that wait", "hud": ["T", "Radio"], "legend": ["b", "radio", "T", "radio"]},
			{"keys": "J", "what": "Jobs: who works where, by day and at night", "hud": ["J", "Jobs"]},
			{"keys": "N", "what": "Build: what to fortify next", "hud": ["N", "Build"], "legend": ["c", "build", "N", "build"]},
			{"keys": "M | G", "what": "The map of the town", "hud": ["M", "Map"], "legend": ["b", "map", "M", "map"]},
			{"keys": "L", "what": "The call to arms, and standing down again", "hud": ["L", "Call to arms"]},
			{"keys": "V", "what": "Fields of fire: what the guns cover", "hud": ["V", "Fields of fire"]},
			{"keys": "Space", "what": "Pause, and go on", "hud": ["Space", "Pause"]},
			{"keys": ".", "what": "Wait until the bell: the day runs ahead, and stops if the dead come", "hud": [".", "Wait for the bell"], "legend": ["c", "wait", ".", "wait for the bell"]},
			{"keys": "1 2 3", "what": "Normal speed, twice as fast, three times", "hud": ["1 2 3", "Speed"]},
		],
	},
	{
		"title": "The game",
		"rows": [
			{"keys": "Esc", "what": "Close what is open; with nothing open, the menu", "hud": ["Esc", "Close, or menu"], "legend": ["b", "menu", "Esc", "menu"]},
			{"keys": "F5", "what": "Save", "hud": ["F5", "Save"]},
			{"keys": "F9", "what": "Load the last save", "hud": ["F9", "Load"]},
			{"keys": "F11", "what": "Fullscreen, on and off", "hud": ["F11", "Fullscreen"]},
		],
	},
]

## Said under the table on the Controls page: the keys that belong to a card while it is up.
const FOOTNOTE := "While a person at the door is talking, 1 2 3 answer them and E puts the card away. Enter or Space puts the dawn card away."


## The groups for the way the mouse aims now (`always`: "Always aim at the mouse"): {"title", "rows"}, a row that is for the other way left out.
static func groups(always: bool = AimMode.always()) -> Array:
	var out: Array = []
	for g in GROUPS:
		var rows: Array = []
		for r in g.rows:
			var only := String(r.get("aim", ""))
			if only == "" or (only == "always") == always:
				rows.append(r)
		out.append({"title": String(g.title), "rows": rows})
	return out


## The same, in the form the HUD's help panel is filled from: [caption, entries to a row, [[keys, words], ...]] (`hud._fill_help`).
static func hud_groups(always: bool = AimMode.always()) -> Array:
	var out: Array = []
	for g in groups(always):
		var entries: Array = []
		for r in g.rows:
			if r.has("hud"):
				entries.append((r.hud as Array).duplicate())
		var caption := String(g.title)
		out.append([caption, 2, entries])
	return out


## One line of the first minute's legend (`line` "a" or "b"): [[id, key, words], ...] in the table's order (a row that is for the other aim way is left out).
static func legend_line(line: String, always: bool = false) -> Array:
	var out: Array = []
	for g in groups(always):
		for r in g.rows:
			var l = r.get("legend")
			if l is Array and String(l[0]) == line:
				out.append([String(l[1]), String(l[2]), String(l[3])])
	return out


## Every key the table names, as chips of one word each ("Shift C" gives Shift and C), for a check against the handlers.
static func all_chips() -> Array:
	var out: Array = []
	for g in GROUPS:
		for r in g.rows:
			for word in String(r.keys).split(" "):
				if word != "|" and not out.has(word):
					out.append(word)
	return out
