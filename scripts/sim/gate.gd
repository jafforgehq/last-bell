## The gate (round 22, "a proper gate": the Main gate, wall section 2 of the north wall, worked with the avatar's own hands).
##
## TODAY'S RULES, KEPT. With no avatar (the classic game, the harness, the tests, Orientation Day: `active()` false) the Main gate is a
## shut wall section with health, the dead claw at it, and the leaves of its picture (scripts/render/gate_node.gd) slide apart by the vehicle
## view's demand while cars and parties pass "through the picture". Nothing here runs, throws a die or changes a grid then.
##
## THE REAL GATE (avatar mode: `sim.nights_on` and `sim.player_id != ""` and `enabled`). `open` (0 shut to 1 open) is the REAL state: from
## `PASS_AT` (0.5) up the gate is a gateway, not solid for people, vehicles and the dead; below it the section is the wall again, with its
## health, and the dead claw at it as ever. The gateway is the mouth between the posts: four tile columns (37 to 40), through the wall (rows 15
## to 17) and under the catwalk bridge (the deck's face, rows 19 and 20: the one place in the whole front where the barrier lets ground
## through), the catwalk's own row 18 between them is deck either way (round 24: and the passage as well: whoever is in it is on the deck or on the ground
## by the way they came in, `sim.levels`; the ground in the way of the leaves is in the gateway for `who_blocks`, the one on the bridge deck is not). The segment's health and damage state are independent of `open`:
## an open gate takes no damage (the dead who come to it walk in: `lets_dead_in`), a gate that is wrecked (state 3) is a heap that cannot be
## worked (`wrecked`, `request` says so) and is rubble to pass through (`is_passable`).
##
## WHO OPENS IT. `request(want_open, who)` is a hand (the avatar's E at the lever `control_spot()`, the radio's answer): opening sets
## `held` to "open" (it stays open until somebody shuts it: no auto-shut but the bell's), shutting sets `held` to "" and the gate shuts now.
## `hold("shut")` is the standing choice to keep it shut even for a car (the car waits, with the reason in the News), `hold("open")` and
## `hold("")` the others; the avatar being away or down, the choice of "shut" is not kept (somebody inside has to let the party in).
## `demand(reason, who)` is the automatic keeper: a car, a party on foot or a caller that is about to pass asks for it every step it
## needs it (scavenge.gd, recruits.gd) and gets `true` when the gate is passable now; it opens the gate unless it is held "shut" (with the
## avatar here) or, for a party that wants to GO OUT ("car_out", "foot_out"), unless the bell has rung or the alarm is on. After the last
## one through, or the last thing in the gateway, it shuts by itself KEEP_OPEN_AFTER_PASS_S seconds later unless it is held open.
## A closing gate never closes on somebody: while anything stands in the gateway (`who_blocks`) the leaves do not move towards shut, and a
## hand that asks is refused with the reason ("Dez is in the gateway", "The dead are in the gateway: put them down first").
##
## THE BELL AND THE ALARM. The bell (`sim.bell_rung`, once a day) and the call to arms (`radio.alarm(true)`) shut the gate by themselves, even
## when it is held open, a keeper's work (the person at the gate post, `keeper`, else it is automatic): when something is in the gateway
## it waits for it to clear (one News line says so, "gate" kind) and shuts then. The avatar may open it again by hand (that is a choice
## made in the dark: the section then behaves like a fallen one for the dead, `lets_dead_in`: they stop clawing at it and walk in, by the
## breach rules of sim.gd and nights.gd), and when it is held open in the dark with the dead near (`DEAD_NEAR_R`) half an hour after the
## dusk a call "The gate is open and it is dark" is raised once a night (shut it | keep it open, default shut).
##
## TRIPS AND CALLERS (scavenge.gd, recruits.gd): a car on its drive out or in asks for the gate from the start of the drive and waits at
## its stop line (`drive_minutes`: the nose never meets a shut gate) until the gate is passable; a party on foot at the gate and a caller at
## 07:00 wait the same way, each with its News line once a day.
##
## EVENTS (sim.events): {"type": "gate", "state": "opening" | "open" | "closing" | "shut", "by": "player" | "auto" | "dusk"} ("dusk" is the
## bell's and the alarm's keeper). News ("gate" kind, `radio.log_news`) only for the dusk, a gate that cannot shut, a car or a caller that
## waits at a gate held shut: not for the player's own hand.
## Saved with the modules (`save`/`load_state`); an older save loads as a shut gate.
##
## ROUND 23, "we can't open the gate, we can't leave the map". (1) EASY TO WORK: the avatar works the gate from REACH (3.5) tiles of the working
## ground (`reach_dist`: the lever and the front of the mouth, so that standing where a shut gate stops you is in reach), a click on the gate's
## picture works it from CLICK_REACH (6) (`picked`), a hand that SHUTS it (E at the lever) LOCKS it (`held` "shut": cars and parties wait, the
## News says so, until the player opens it again) and one that opens it holds it open until the bell; the keeper's automatic shutting (no hold) is
## as it was. (2) THE AVATAR OUTSIDE: the gate is never shut behind the avatar. While the avatar is outside the compound (`outside_by`) the bell's
## and the alarm's shutting waits ("The gate stays open for you", News) until they are back inside or it is day again, nothing else shuts it
## either, and a shut gate opens by itself for an avatar who comes back to it (`demand("avatar_in")`: it overrides a lock). (3) LEAVING: the
## avatar who walks out through the gateway and on past LEAVE_R tiles of the compound is offered the Map (`leave_offer`, the event
## {"type": "leave_offer", "on": true | false, "why"}): once a crossing, with a cooldown, never at night, never without the rules (Orientation Day), and it is
## dismissed by walking back inside the line, by `dismiss_leave` (the views: E, a click, the Map opening) or after LEAVE_CARD_S. A trip the avatar
## leads out (`scavenge.begin_played`) opens the gate for them (`let_out`): a lock of theirs is lifted, with a line in the News.
extends RefCounted

const Convoy := preload("res://scripts/sim/convoy.gd")

## The wall section this is.
const SEGMENT := 2
## Rules' seconds from shut to open and back.
const OPEN_S := 2.0
## Rules' seconds the gate stays open after the last one through (and with nothing in the gateway) when nobody holds it open.
const KEEP_OPEN_AFTER_PASS_S := 4.0
## Tiles from the working ground (`reach_dist`) within which the avatar works the gate (round 23: it was 2.2 from the lever alone).
const REACH := 3.5
## A click on the gate's picture works it from this far (`Interact.gate_candidate`), and says "Too far: walk to the gate" from beyond; the floating
## word over the lever shows from LABEL_R tiles (scripts/render/overlay_node.gd).
const CLICK_REACH := 6.0
const LABEL_R := 12.0
## The working ground is the line from the lever to the front of the mouth (the apron under the bridge's face): the other end.
const FRONT_END := Vector2(40.8, 21.6)
## The gate's picture (the posts and the leaves, tiles) and how close to the lever's spot still counts as on the lever: `picked`.
const PICK := Rect2(35.8, 16.6, 6.8, 2.2)
const LEVER_PICK_R := 1.8
## From this `open` up the gate is passable (and the dead may come in).
const PASS_AT := 0.5
## The tile columns of the mouth, the rows through the wall (the section's own) and the rows of the deck's face under the bridge (the barrier
## that the open gate lets ground through; the row between, 18, is the catwalk).
const MOUTH_COLS := [37, 38, 39, 40]
const WALL_ROWS := [15, 16, 17]
const FACE_ROWS := [19, 20]
## The catwalk's row between them: the bridge deck over the passage (round 24: a person in its four tiles is on the deck or in the passage, `sim.levels`).
const BRIDGE_ROW := 18
## The mouth as a rectangle (tiles).
const GATEWAY := Rect2(37.0, 15.0, 4.0, 6.0)
## Where the avatar works the gate: a lever on the foot of the walkway's face, the west side of the opening, on the apron.
const CONTROL_SPOT := Vector2(36.0, 21.6)
## The gate post (jobs.gd): whoever stands at it is the keeper.
const POST_ID := "gate"
const KEEPER_REACH := 3.0
## A car's nose stops this far short of the gateway's ends (the street's end at y = 15, the apron's end at y = 21), and a car's drive is
## looked along in this many steps for those places.
const STOP_MARGIN := 0.35
const SCAN_STEPS := 600
## A car this many game minutes past its stop line is taken to be through it.
const PAST_LINE_MIN := 0.02
## Where "the dead are near" is looked for (tiles from the middle of the gateway) for the call of the open gate in the dark, and how long after the
## dusk (hours) it is made, and for how long it waits for an answer (game minutes).
const NEAR_AT := Vector2(39.0, 17.0)
const DEAD_NEAR_R := 25.0
const CALL_AFTER_DUSK_H := 0.5
const CALL_TTL_MIN := 30.0
## The reasons a car, a party or a caller gives `demand`: the ones that want to GO OUT wait while the bell has rung or the alarm is on.
const LEAVING := ["car_out", "foot_out"]
## The compound (tiles: the walls and the school), for "outside": a point that is not in it, and how far it is from it (`outside_by`).
const COMPOUND := Rect2(17.0, 15.0, 50.0, 45.0)
## Past this many tiles from the compound the avatar is offered the Map; the offer is made once a crossing: it is armed again once the avatar is
## within LEAVE_REARM_R of the compound (and the cooldown has run), put away when they walk back to LEAVE_BACK tiles short of the line, and goes
## by itself after LEAVE_CARD_S rules seconds.
const LEAVE_R := 5.5
const LEAVE_BACK := 1.5
const LEAVE_REARM_R := 2.0
const LEAVE_COOLDOWN_S := 20.0
const LEAVE_CARD_S := 15.0
## A shut gate opens for the avatar who comes back to it from this close (tiles from the middle of the mouth's outer end).
const RETURN_R := 4.5
const OUTER_MOUTH := Vector2(39.0, 15.0)
## Seconds the gate is kept open for a trip the avatar leads out.
const ESCORT_S := 6.0

var sim
## Whether the rules apply at all (Orientation Day, the tutorial's lesson and a test of something else switch it off).
var enabled := true
## 0 shut to 1 open: the REAL state (see the header). Saved.
var open := 0.0
## The player's standing choice: "" (automatic), "open" or "shut". Saved.
var held := ""
## What the gate is doing now: "shut", "opening", "open" or "closing" (read by `update`, which emits the events).
var _state := "shut"
## Whether the gate is wanted open (the target of the last step or hand), seconds since anything wanted it or stood in it, whether a demand came in
## this step, whether it was shut by hand (then it stays shut until a demand or a hand opens it).
var _want := false
var _idle := 0.0
var _demanded := false
var _hand_shut := false
## A shutting that waits to be done: "" | "dusk" | "alarm" (the bell, the alarm, an answer of the call).
var _forced := ""
var _forced_said := false
## The day a shutting was asked for (round 23: one that waits for the avatar outside is not asked of the day after).
var _forced_day := 0
## Who is the cause of what the gate is doing: "player", "auto" or "dusk".
var _by := "auto"
## Whether the world's grids hold the gate open now (the gateway's tiles walkable).
var _applied := false
var _was_wrecked := false
## The day the bell was seen for, and the day the open gate's call was raised for.
var _bell_day := 0
var _call_day := 0
## The lines of the News said once ("key:day": true).
var _noted := {}
## The mouth's tiles that are the deck's face (so that they are put back as they were when the gate shuts).
var _faces := {}
var _faces_read := false
## Cars: where each (spot, direction, kind) meets the gateway along its drive: {"stop": progress, "clear": progress}. Not saved.
var _marks := {}
## The wall section (found once).
var _seg = null
## Round 23: whether the offer of the Map is up (the views draw its card), whether the next crossing may make one, the cooldown (rules seconds),
## the rules seconds the card has been up, and the rules seconds the gate is still kept open for a trip that leaves. Not saved.
var leave_offer := false
var _leave_armed := true
var _leave_cool := 0.0
var _leave_t := 0.0
var _escort := 0.0


func setup(s) -> void:
	sim = s


## A new run: shut, nothing held, nothing remembered.
func start() -> void:
	open = 0.0
	held = ""
	_state = "shut"
	_want = false
	_idle = 0.0
	_demanded = false
	_hand_shut = false
	_forced = ""
	_forced_said = false
	_forced_day = 0
	_by = "auto"
	_was_wrecked = false
	_bell_day = 0
	_call_day = 0
	_noted = {}
	leave_offer = false
	_leave_armed = true
	_leave_cool = 0.0
	_leave_t = 0.0
	_escort = 0.0
	if _applied:
		_apply_world(false)


# ---------------------------------------------------------------------------------------------------- the facts --

## Whether the rules of the real gate apply: avatar mode in the settlement's own sim.
func active() -> bool:
	return enabled and sim != null and bool(sim.nights_on) and String(sim.player_id) != "" and _segment() != null


func _segment():
	if _seg != null:
		return _seg
	for s in sim.segments:
		if int(s.id) == SEGMENT:
			_seg = s
			return s
	return null


## The section is down (state 3): a heap, nothing to work.
func wrecked() -> bool:
	var s = _segment()
	return s != null and int(s.state) == 3


## Whether people, cars and the dead can go through now: the gate open to PASS_AT or more, or wrecked (rubble). False with no avatar (the
## section is a wall then).
func is_passable() -> bool:
	if not active():
		return false
	return wrecked() or open >= PASS_AT


## Whether the dead may walk in: the gate stands open (a wrecked one is the breach rules' own, state 3). Read by sim.gd.
func lets_dead_in() -> bool:
	return active() and open >= PASS_AT and not wrecked()


## "shut", "opening", "open" or "closing".
func state() -> String:
	return _state


## Whether the gate is wanted open now (what E would shut: the target, not where the leaves are).
func wants_open() -> bool:
	return _want


## Where the avatar works the gate (tiles).
func control_spot() -> Vector2:
	return CONTROL_SPOT


## Tiles from `at` to the working ground: the line from the lever to the front of the mouth (0 on it). A hand works the gate from REACH of it, so
## that standing where a shut gate stops you (the face under the bridge) is in reach whichever side of the opening you came to.
func reach_dist(at: Vector2) -> float:
	var ab := FRONT_END - CONTROL_SPOT
	var t := clampf((at - CONTROL_SPOT).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return at.distance_to(CONTROL_SPOT + ab * t)


## Whether a point of the world is on the gate for a click: its picture (the posts and the leaves) or the lever.
func picked(at: Vector2) -> bool:
	return PICK.has_point(at) or at.distance_to(CONTROL_SPOT) <= LEVER_PICK_R


## The mouth (tiles): from the street's end of the wall to the apron's end of the bridge.
func gateway() -> Rect2:
	return GATEWAY


## How far (tiles) a point is from the compound: 0 inside it (the walls, the school and the gateway included), more outside.
func outside_by(at: Vector2) -> float:
	var dx := maxf(maxf(COMPOUND.position.x - at.x, at.x - COMPOUND.end.x), 0.0)
	var dy := maxf(maxf(COMPOUND.position.y - at.y, at.y - COMPOUND.end.y), 0.0)
	return Vector2(dx, dy).length()


## Whether the avatar is up and outside the compound (the street beyond the north wall): the gate is never shut behind them.
func _avatar_outside() -> bool:
	if not _player_here():
		return false
	var lead = sim.avatar.player()
	return outside_by(Vector2(lead.x, lead.y)) > 0.0


## Whether the point is in a tile of the mouth that is solid while the gate is shut (the wall's three rows and the deck's face under the bridge).
func _in_mouth(x: float, y: float) -> bool:
	var col := floori(x)
	var row := floori(y)
	return MOUTH_COLS.has(col) and (WALL_ROWS.has(row) or FACE_ROWS.has(row))


## Whether the point is in the bridge's tile of the mouth (the catwalk's row 18, which is also the passage under the planks). A person there is in the
## way of the gate only on the ground (`sim.levels`): one on the bridge deck, the keeper at his post, is above it.
func _in_bridge(x: float, y: float) -> bool:
	return MOUTH_COLS.has(floori(x)) and floori(y) == BRIDGE_ROW


## The tiles of the mouth that the gate's state changes: the wall's rows (unless the section is down: the wreck opened those) and the face's.
func _mouth_tiles(with_wall: bool = true) -> Array:
	var out: Array = []
	var w: int = sim.W
	for col in MOUTH_COLS:
		if with_wall:
			for row in WALL_ROWS:
				out.append(int(row) * w + int(col))
		for row in FACE_ROWS:
			out.append(int(row) * w + int(col))
	return out


## Who is in the way of the gate shutting: [{"kind": "dead" | "vehicle" | "person", "name": "A walker" | "The pickup" | "Dez"}], the dead first (any
## that is up, but those clawing at the wall's face), then cars on their drive, then people (the avatar too). [] with no avatar and while
## nobody is.
func _blockers() -> Array:
	var out: Array = []
	if not active():
		return out
	for z in sim.zombies:
		var st := String(z.state)
		if st == "dying" or st == "dead" or st == "attack":
			continue
		if _in_mouth(z.x, z.y) or _in_bridge(z.x, z.y):
			out.append({"kind": "dead", "name": "A %s" % String(z.kind)})
	for c in _cars_in_the_gateway():
		out.append({"kind": "vehicle", "name": String(c)})
	for p in sim.people:
		if p.dead or p.turned or p.away != null:
			continue
		if _in_mouth(p.x, p.y) or (_in_bridge(p.x, p.y) and not sim.levels.on_deck(p)):
			out.append({"kind": "person", "name": String(p.first), "player": bool(p.player)})
	return out


## The names of who is in the gateway: ["Dez", "A walker", "The pickup"] (the views' lines: scripts/ui/gate_kit.gd). [] with no avatar.
func who_blocks() -> Array:
	var names: Array = []
	for b in _blockers():
		names.append(String(b.name))
	return names


## Why the gate cannot shut for what stands in it ("" for nothing), as a sentence for the player.
func _blocked_line(list: Array) -> String:
	if list.is_empty():
		return ""
	var who: Array = []
	for b in list:
		if String(b.kind) == "dead":
			return "The dead are in the gateway: put them down first"
		who.append("You" if bool(b.get("player", false)) else String(b.name))
	if who.size() == 1:
		return "You are in the gateway" if who[0] == "You" else "%s is in the gateway" % who[0]
	return "%s and %s are in the gateway" % [", ".join(PackedStringArray(who.slice(0, who.size() - 1))), who[who.size() - 1]]


## The person at the gate post who shuts the gate for the night (not the avatar, up and not away), or null.
func keeper():
	var po: Dictionary = sim.jobs.post(POST_ID)
	if po.is_empty():
		return null
	var at := Vector2(po.pos)
	for p in sim.people:
		if p.dead or p.turned or p.downed or p.away != null or p.player:
			continue
		if Vector2(p.x, p.y).distance_to(at) <= KEEPER_REACH:
			return p
	return null


## Whether the avatar is up at the base (so that a standing choice of his can be kept: nobody else is to lock the others out).
func _player_here() -> bool:
	var lead = sim.avatar.player()
	return lead != null and lead.away == null and not lead.dead and not lead.turned and not lead.downed


# ---------------------------------------------------------------------------------------------------- hands --

## Why a hand cannot do this now ("" when it can): there is no gate, it is wrecked, or something stands in the gateway when it would shut.
func refusal(want_open: bool) -> String:
	if not active():
		return "There is no gate here"
	if wrecked():
		return "The gate is wrecked"
	if want_open:
		return ""
	if _avatar_outside():
		return "You are outside: the gate stays open for you"
	if open > 0.0:
		return _blocked_line(_blockers())
	return ""


## A hand at the gate: {"ok", "why" (the reason it was refused), "line" (what to say: "Opening the gate."), "warn" (true when it is dark and the
## dead can walk in), "open" (the state wanted), "locked" (the player's hand shut it and it stays shut)}. Opening sets `held` to "open" (it stays
## open until the bell or until somebody shuts it); the PLAYER's hand shutting sets it to "shut" and shuts the gate now: it is LOCKED, cars and
## parties wait outside (the News says so) until the player opens it again (round 23); another hand (the radio's answer, `who` another word) shuts
## it and holds nothing (a demand may open it again). `who` is "player" (E at the lever, a click, the HUD's row, Y).
func request(want_open: bool, who: String = "player") -> Dictionary:
	var why := refusal(want_open)
	if why != "":
		return {"ok": false, "why": why, "line": "", "warn": false, "open": want_open, "locked": false}
	var by := "player" if who == "player" else ("dusk" if who == "dusk" else "auto")
	_forced = ""
	_forced_said = false
	_by = by
	if want_open:
		held = "open"
		_hand_shut = false
		_want = true
		_idle = 0.0
		var dark: bool = sim.is_night()
		return {"ok": true, "why": "", "line": "Opening the gate: the dead can walk in." if dark else "Opening the gate.", "warn": dark, "open": true, "locked": false}
	var locked := who == "player"
	held = "shut" if locked else ""
	_hand_shut = true
	_want = false
	return {"ok": true, "why": "", "line": "Shutting the gate. Locked: cars wait outside" if locked else "Shutting the gate.", "warn": false, "open": false, "locked": locked}


## The standing choice: "open" (no auto-shut but the bell's), "shut" (shut even for a car: it waits, the News says why) or "" (automatic).
func hold(mode: String) -> bool:
	if not ["", "open", "shut"].has(mode) or not active() or wrecked():
		return false
	if mode == "open":
		_hand_shut = false
		_forced = ""
	elif mode == "shut":
		var why := refusal(false)
		if why != "":
			return false
		_hand_shut = true
		_forced = ""
	held = mode
	return true


## A car, a party or a caller is about to pass (or waits to): opens the gate unless it is held shut or the lockdown (the bell, the alarm: for
## a party that wants OUT) says no. Called every step the need lasts. `reason`: "car_out", "car_in", "foot_out", "foot_in" or "arrival"; `who`: the
## words for the News ("The pickup", "Dez and Ana", "Mia Hale"). True when the gate is passable now (and always without the rules: nothing holds them).
func demand(reason: String, who: String = "") -> bool:
	if not active() or wrecked():
		return true
	var why := _kept_shut(reason)
	if why != "":
		_say_wait(reason, who, why)
		return false
	if not _want and not _demanded:
		_by = "auto"    # (this is what opens it)
	_demanded = true
	_hand_shut = false
	if _forced != "" and not LEAVING.has(reason):
		_forced = ""    # (one that comes IN is let in: the bell does not lock a returning party out)
		_forced_said = false
	return is_passable()


## "" when a demand may open the gate; "shut" (held shut with the avatar here), "alarm" or "night" for a party that wants out.
func _kept_shut(reason: String) -> String:
	if held == "shut" and _player_here() and reason != "avatar_in":
		return "shut"
	if LEAVING.has(reason):
		if sim.radio.alarm_on:
			return "alarm"
		if sim.is_night():
			return "night"
	return ""


## Notes kept for the lines said once a day: the older days' are dropped.
func _note(key: String) -> bool:
	var full := "%s:%d" % [key, int(sim.day)]
	if _noted.has(full):
		return false
	if _noted.size() > 48:
		for k in _noted.keys():
			if not String(k).ends_with(":%d" % int(sim.day)):
				_noted.erase(k)
	_noted[full] = true
	return true


func _say_wait(reason: String, who: String, why: String) -> void:
	if not _note("wait:%s:%s" % [reason, who]):
		return
	var name := who if who != "" else "Someone"
	var tail := "the gate is shut"
	match why:
		"night":
			tail = "the gate stays shut tonight"
		"alarm":
			tail = "the gate stays shut for the alarm"
	var many := name.contains(" and ")
	var line := ""
	match reason:
		"car_out", "foot_out":
			line = "%s %s to go out: %s" % [name, "wait" if many else "waits", tail]
		"arrival":
			line = "%s %s outside the gate: %s" % [name, "are" if many else "is", tail]
		_:
			line = "%s %s outside: %s" % [name, "wait" if many else "waits", tail]
	sim.radio.log_news("gate", line, "Open it at the lever" if why == "shut" else "")


## The bell has rung or the call to arms has gone out: the gate shuts by itself, a keeper's work. Waits for what is in the gateway.
func shut_for(by: String) -> void:
	if not active() or wrecked():
		return
	if held == "open":
		held = ""
	_hand_shut = false
	if open <= 0.0 and not _want:
		return
	_forced = by
	_forced_said = false
	_forced_day = int(sim.day)
	_by = "dusk"


## The call to arms: the gate shuts unless something is in the gateway (radio.gd `alarm`).
func on_alarm() -> void:
	shut_for("alarm")


# ---------------------------------------------------------------------------------------------------- the step --

## One step of the rules' time (`Sim.update`, after the trips and the callers have asked and before the people and the dead move).
func update(dt: float) -> void:
	if not active():
		if _applied or open > 0.0 or _state != "shut":
			_snap_shut()
		_end_offer("off")
		return
	var down := wrecked()
	if down != _was_wrecked:
		_was_wrecked = down
		if down:
			# the heap: nothing to work; the wreck opened the wall's rows itself, the face's rows are put back
			_snap_shut(false)
	_watch_leave(dt)
	if down:
		_demanded = false
		return
	_watch_bell()
	var outside := _avatar_outside()
	if outside:
		_watch_return()
	var demanded := _demanded or _escort > 0.0
	_escort = maxf(0.0, _escort - dt)
	_demanded = false
	var blockers: Array = _blockers() if open > 0.0 else []
	if demanded or not blockers.is_empty():
		_idle = 0.0
	else:
		_idle = minf(_idle + dt, 1000.0)
	var want := false
	if _forced != "":
		want = false
	elif held == "open":
		want = true
	elif held == "shut" and _player_here() and not outside:
		want = false
	elif demanded:
		want = true
	elif _hand_shut:
		want = false
	else:
		want = open > 0.0 and _idle < KEEP_OPEN_AFTER_PASS_S
	if not want and outside and open > 0.0:
		# (round 23: the gate is never shut behind the avatar: the keeper waits for them, and says so once a day)
		want = true
		if _forced != "":
			_say_waits_for_avatar()
	_want = want
	var prev := open
	var next := move_toward(open, 1.0 if want else 0.0, dt / OPEN_S)
	if next < prev and not blockers.is_empty():
		next = prev    # (a closing gate never closes on somebody: it waits)
		if _forced != "":
			_say_blocked(blockers)
	if next < prev and _forced != "" and not _forced_said:
		_forced_said = true
		_say_shutting()
	open = next
	var now_pass := open >= PASS_AT
	if now_pass != _applied:
		_apply_world(now_pass)
		if not now_pass:
			_forget_paths()
	_events(prev)
	if _forced != "" and open <= 0.0:
		_forced = ""
		_forced_said = false
	_watch_dark()


## The bell rings once a day: the gate shuts by itself.
func _watch_bell() -> void:
	if sim.bell_rung and _bell_day != int(sim.day):
		_bell_day = int(sim.day)
		shut_for("dusk")
	elif _forced == "dusk" and _forced_day != int(sim.day) and not sim.is_night() and not sim.bell_rung:
		# (round 23: a shutting that has waited for the avatar outside the wall is not asked of the day that has begun)
		_forced = ""
		_forced_said = false


## The keeper has not shut the gate because the avatar is outside: one line a day.
func _say_waits_for_avatar() -> void:
	if _note("waits_for_avatar"):
		sim.radio.log_news("gate", "The gate stays open for you", "It shuts when you are back inside")


## The avatar is outside and the gate is not open: it opens for them as they come to it (a lock does not keep them out).
func _watch_return() -> void:
	if open >= PASS_AT:
		return
	var lead = sim.avatar.player()
	if Vector2(lead.x, lead.y).distance_to(OUTER_MOUTH) > RETURN_R:
		return
	demand("avatar_in", "You")
	if _note("returns"):
		var k = keeper()
		sim.radio.log_news("gate", "%s opens the gate for you" % String(k.first) if k != null else "The gate opens for you")


func _say_shutting() -> void:
	var k = keeper()
	var line := "The gate shuts for the night"
	if _forced == "alarm":
		line = "The gate shuts: call to arms"
	if k != null:
		line = "%s shuts the gate for the night" % String(k.first) if _forced != "alarm" else "%s shuts the gate: call to arms" % String(k.first)
	sim.radio.log_news("gate", line)


func _say_blocked(blockers: Array) -> void:
	if not _note("blocked:%s" % _forced):
		return
	sim.radio.log_news("gate", "The gate cannot shut yet", _blocked_line(blockers))


## The events of a step: the state changes of the leaves.
func _events(prev: float) -> void:
	var now := _state
	if open <= 0.0:
		now = "shut"
	elif open >= 1.0:
		now = "open"
	elif open > prev:
		now = "opening"
	elif open < prev:
		now = "closing"
	if now != _state:
		_state = now
		sim.events.append({"type": "gate", "state": now, "by": _by})


# ---------------------------------------------------------------------------------------------------- leaving --

## One step of the offer of the Map (round 23): the avatar who has walked out past LEAVE_R tiles of the compound is offered it once a crossing
## (`leave_offer`, the event {"type": "leave_offer", "on": true}), never at night or under the call to arms, and it is put away when they walk back
## (LEAVE_BACK short of the line), when the views say so (`dismiss_leave`) or after LEAVE_CARD_S seconds. It is armed again once the avatar is
## within LEAVE_REARM_R of the compound and LEAVE_COOLDOWN_S seconds have run since the last card.
func _watch_leave(dt: float) -> void:
	_leave_cool = maxf(0.0, _leave_cool - dt)
	if not _player_here():
		_end_offer("away")
		return
	var lead = sim.avatar.player()
	var d := outside_by(Vector2(lead.x, lead.y))
	if leave_offer:
		_leave_t += dt
		if d < LEAVE_R - LEAVE_BACK:
			_end_offer("back")
		elif _leave_t >= LEAVE_CARD_S:
			_end_offer("timeout")
		elif sim.is_night() or bool(sim.radio.alarm_on):
			_end_offer("night")
		return
	if d <= LEAVE_REARM_R:
		_leave_armed = true
	if d < LEAVE_R or not _leave_armed or _leave_cool > 0.0:
		return
	if sim.is_night() or bool(sim.radio.alarm_on):
		return
	leave_offer = true
	_leave_armed = false
	_leave_cool = LEAVE_COOLDOWN_S
	_leave_t = 0.0
	sim.events.append({"type": "leave_offer", "on": true, "why": ""})


## Puts the offer away (the views: the key, a click or the Map opening; "back", "timeout", "night", "away", "off" are the rules'). False when none was up.
func dismiss_leave(why: String = "taken") -> bool:
	return _end_offer(why)


func _end_offer(why: String) -> bool:
	if not leave_offer:
		return false
	leave_offer = false
	_leave_t = 0.0
	sim.events.append({"type": "leave_offer", "on": false, "why": why})
	return true


## The avatar leads a trip out through the gate (the Map's Take control, scavenge.gd `begin_played`): the gate opens for them and shuts a few seconds
## after, and a lock of the player's own is lifted (they are the one leaving). The line to say ("The gate opens for you", "Unlocked: the gate opens
## for you"), "" with no rules, and nothing to do for a gate that is wrecked.
func let_out(who: String = "") -> String:
	if not active() or wrecked():
		return ""
	var unlocked := held == "shut"
	if unlocked:
		held = ""
	_hand_shut = false
	_escort = ESCORT_S
	_by = "auto"
	var line := "Unlocked: the gate opens for you" if unlocked else "The gate opens for you"
	if unlocked:
		sim.radio.log_news("gate", "The gate is unlocked for %s" % who if who != "" else "The gate is unlocked for the trip")
	return line


# ---------------------------------------------------------------------------------------------------- the world --

## The gateway's tiles walkable (`pass_`) or solid again, on both walking grids and both path grids, the deck's face as it was.
func _apply_world(pass_: bool) -> void:
	_read_faces()
	var tiles := _mouth_tiles(not wrecked())
	sim.block_tiles(tiles, not pass_)
	var faces: Dictionary = sim.world.deck_face_tiles
	for col in MOUTH_COLS:
		for row in FACE_ROWS:
			var i: int = int(row) * int(sim.W) + int(col)
			if pass_:
				faces.erase(i)
			elif _faces.has(i):
				faces[i] = true
	_applied = pass_


func _read_faces() -> void:
	if _faces_read:
		return
	_faces_read = true
	for col in MOUTH_COLS:
		for row in FACE_ROWS:
			var i: int = int(row) * int(sim.W) + int(col)
			if sim.world.deck_face_tiles.has(i):
				_faces[i] = true


## Shut at once, for no reason the rules know (the avatar is gone, the rules are off, the section fell).
func _snap_shut(with_wall: bool = true) -> void:
	var prev := open
	open = 0.0
	held = ""
	_want = false
	_forced = ""
	_forced_said = false
	_hand_shut = false
	_idle = 0.0
	if _applied:
		_read_faces()
		sim.block_tiles(_mouth_tiles(with_wall and not wrecked()), true)
		var faces: Dictionary = sim.world.deck_face_tiles
		for i in _faces:
			faces[i] = true
		_applied = false
		_forget_paths()
	if _state != "shut":
		_state = "shut"
		if prev > 0.0 and active():
			sim.events.append({"type": "gate", "state": "shut", "by": "auto"})


## Walkers whose way ran through the mouth are asked again once it is solid.
func _forget_paths() -> void:
	for z in sim.zombies:
		if z.path.is_empty() or z.state == "dying" or z.state == "dead":
			continue
		if _path_through(z.path, z.path_i):
			z.path = []
			z.path_i = 0
			z.repath = 0.0
	for p in sim.people:
		if p.path.is_empty() or p.player:
			continue
		if _path_through(p.path, p.path_i):
			p.path = []
			p.path_i = 0
			p.goal_key = ""


func _path_through(path: Array, from_i: int) -> bool:
	for i in range(maxi(from_i, 0), path.size()):
		var pt: Vector2 = path[i]
		if _in_mouth(pt.x, pt.y):
			return true
	return false


# ---------------------------------------------------------------------------------------------------- the dark --

## Whether it is dark enough for the call: from half an hour after the dusk to dawn.
func _dark() -> bool:
	if not sim.is_night():
		return false
	var h: float = sim.hour
	var dusk: float = sim.seasons.dusk_hour()
	return h >= dusk + CALL_AFTER_DUSK_H or h < sim.seasons.dawn_hour()


func _dead_near() -> bool:
	for z in sim.zombies:
		var st := String(z.state)
		if st == "dying" or st == "dead" or st == "retreat":
			continue
		if Vector2(z.x, z.y).distance_to(NEAR_AT) <= DEAD_NEAR_R:
			return true
	return false


## An open gate that the avatar holds open in the dark with the dead near: the call, once a night.
func _watch_dark() -> void:
	if held != "open" or open < PASS_AT or _call_day == int(sim.day):
		return
	if not _dark() or not _dead_near():
		return
	_call_day = int(sim.day)
	var options: Array = [{"id": "shut", "label": "Shut it"}, {"id": "keep", "label": "Keep it open"}]
	sim.radio.raise_call("gate", "The gate is open and it is dark", "The dead are near: shut it, or keep it open?", options, "shut", CALL_TTL_MIN, {"seg": SEGMENT}, GATEWAY.get_center())


## What an option of the call does; the line that says what came of it (`NightCalls.carry_out` passes the "gate" kind here).
func carry_out(_e: Dictionary, option_id: String) -> String:
	if not active():
		return ""
	if wrecked():
		return "The gate is down"
	if option_id == "keep":
		held = "open"
		_hand_shut = false
		_forced = ""
		return "Keeping the gate open: the dead can walk in"
	var r := request(false, "radio")
	if bool(r.ok):
		return "Shutting the gate"
	shut_for("dusk")
	return "%s: it shuts when the way is clear" % String(r.why)


# ---------------------------------------------------------------------------------------------------- cars --

## Where a party's car is on its drive: {"pos", "heading", "len"} or {} when it is not driving.
func _car_at(party: Dictionary) -> Dictionary:
	var state := String(party.get("state", ""))
	if state != "driving_out" and state != "driving_in":
		return {}
	var v: Dictionary = sim.vehicles.vehicle(String(party.get("vehicle", "")))
	if v.is_empty():
		return {}
	var total := float(party.get("drive_len", 0.0))
	if total <= 0.0:
		return {}
	var route: Array = Convoy.route(int(v.get("spot", 0)), "out" if state == "driving_out" else "in")
	if route.is_empty():
		return {}
	var at: Dictionary = Convoy.pose(route, clampf(float(party.get("drive_t", 0.0)) / total, 0.0, 1.0))
	return {"pos": at.pos, "heading": float(at.heading), "len": _length_of(String(v.get("kind", "")))}


func _length_of(kind_id: String) -> float:
	return float(sim.vehicles.kind(kind_id).get("h", Convoy.DEFAULT_H))


## The names ("The pickup") of the cars whose body (along its axis) is in the gateway now.
func _cars_in_the_gateway() -> Array:
	var out: Array = []
	var sc = sim.scavenge
	if sc == null:
		return out
	for party in sc.parties:
		var at := _car_at(party)
		if at.is_empty():
			continue
		var dir := Vector2.from_angle(float(at.heading))
		var half := float(at.len) / 2.0
		var k := -half
		var inside := false
		while k <= half + 0.001:
			var pt: Vector2 = Vector2(at.pos) + dir * k
			if pt.x >= GATEWAY.position.x and pt.x < GATEWAY.end.x and pt.y >= GATEWAY.position.y and pt.y <= GATEWAY.end.y:
				inside = true
				break
			k += 0.5
		if inside:
			out.append("The %s" % String(sim.vehicles.name_of(String(party.vehicle))).to_lower())
	return out


## Where along a drive (progress 0 to 1 of the route) the nose of a car of this kind first meets the gateway (`stop`) and where its tail has left
## it (`clear`): {"stop", "clear"}, looked along the route in SCAN_STEPS steps; both 1.0 for a route that does not run through it.
func _marks_of(spot: int, dir: String, kind_id: String) -> Dictionary:
	var key := "%d:%s:%s" % [spot, dir, kind_id]
	if _marks.has(key):
		return _marks[key]
	var route: Array = Convoy.route(spot, dir)
	var half := _length_of(kind_id) / 2.0
	var lo := GATEWAY.position.x - 1.0
	var hi := GATEWAY.end.x + 1.0
	var top := GATEWAY.position.y - STOP_MARGIN
	var bottom := GATEWAY.end.y + STOP_MARGIN
	var stop := -1.0
	var clear := 1.0
	var inside := false
	for i in SCAN_STEPS + 1:
		var s := float(i) / float(SCAN_STEPS)
		var at: Dictionary = Convoy.pose(route, s)
		var h := Vector2.from_angle(float(at.heading))
		var nose: Vector2 = Vector2(at.pos) + h * half
		var tail: Vector2 = Vector2(at.pos) - h * half
		if stop < 0.0:
			if nose.x >= lo and nose.x <= hi and nose.y >= top and nose.y <= bottom:
				stop = maxf(0.0, s - 1.0 / float(SCAN_STEPS))
		else:
			# the car has cleared the gateway once no part of its axis is in it any more, after some part has been
			var any := false
			for pt in [nose, tail, at.pos]:
				if pt.x >= lo and pt.x <= hi and pt.y >= GATEWAY.position.y and pt.y <= GATEWAY.end.y:
					any = true
			if any:
				inside = true
			elif inside:
				clear = s
				break
	if stop < 0.0:
		stop = 1.0
	var marks := {"stop": stop, "clear": clear}
	_marks[key] = marks
	return marks


## How many of `mins` game minutes a car on its drive (`party`: "driving_out" or "driving_in", `drive_t` of `drive_len`) may drive now: all of
## them, or only as far as its stop line when the gate is not passable (it asks for the gate all the way until it has cleared it). All of them
## with no avatar.
func drive_minutes(party: Dictionary, mins: float) -> float:
	if not active() or wrecked():
		return mins
	var total := float(party.get("drive_len", 0.0))
	if total <= 0.0:
		return mins
	var v: Dictionary = sim.vehicles.vehicle(String(party.get("vehicle", "")))
	if v.is_empty():
		return mins
	var out := String(party.get("state", "")) == "driving_out"
	var marks := _marks_of(int(v.get("spot", 0)), "out" if out else "in", String(v.get("kind", "")))
	var t := float(party.get("drive_t", 0.0))
	if t >= float(marks.clear) * total:
		return mins
	var name := "The %s" % String(sim.vehicles.name_of(String(party.vehicle))).to_lower()
	var passable := demand("car_out" if out else "car_in", name)
	if passable:
		return mins
	var room := float(marks.stop) * total - t
	if room < -PAST_LINE_MIN:
		return mins    # (already through the line: a load from a save, or a gate that was shut with it in)
	return clampf(room, 0.0, mins)    # (to the line and no farther)


# ---------------------------------------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {"open": open, "held": held, "state": _state, "want": _want, "idle": _idle, "hand_shut": _hand_shut, "forced": _forced, "by": _by,
			"bell_day": _bell_day, "call_day": _call_day, "noted": _noted.duplicate()}


## Restores what `save` wrote onto a freshly built sim (the grids are the map's: the gateway is made walkable again when it was open). A save
## from before the gate has none of it: a shut gate.
func load_state(d: Dictionary) -> void:
	start()
	_leave_armed = false    # (a game loaded with the avatar outside makes no offer until they have been back at the wall)
	var o = d.get("open", 0.0)
	open = clampf(float(o), 0.0, 1.0) if (typeof(o) == TYPE_FLOAT or typeof(o) == TYPE_INT) else 0.0
	var h = d.get("held", "")
	held = String(h) if typeof(h) == TYPE_STRING and ["", "open", "shut"].has(String(h)) else ""
	var st = d.get("state", "")
	_state = String(st) if typeof(st) == TYPE_STRING and ["shut", "opening", "open", "closing"].has(String(st)) else _state_of_open()
	_want = bool(d.get("want", false)) if typeof(d.get("want", false)) == TYPE_BOOL else false
	var idle = d.get("idle", 0.0)
	_idle = maxf(0.0, float(idle)) if (typeof(idle) == TYPE_FLOAT or typeof(idle) == TYPE_INT) else 0.0
	_hand_shut = bool(d.get("hand_shut", false)) if typeof(d.get("hand_shut", false)) == TYPE_BOOL else false
	var forced = d.get("forced", "")
	_forced = String(forced) if typeof(forced) == TYPE_STRING and ["", "dusk", "alarm"].has(String(forced)) else ""
	var by = d.get("by", "auto")
	_by = String(by) if typeof(by) == TYPE_STRING and ["player", "auto", "dusk"].has(String(by)) else "auto"
	_bell_day = int(d.get("bell_day", 0)) if typeof(d.get("bell_day", 0)) in [TYPE_INT, TYPE_FLOAT] else 0
	_call_day = int(d.get("call_day", 0)) if typeof(d.get("call_day", 0)) in [TYPE_INT, TYPE_FLOAT] else 0
	var noted = d.get("noted", {})
	if typeof(noted) == TYPE_DICTIONARY:
		for k in noted:
			_noted[String(k)] = true
	_was_wrecked = wrecked()
	if active() and not _was_wrecked and open >= PASS_AT:
		_apply_world(true)
	elif _was_wrecked:
		open = 0.0
		_state = "shut"


func _state_of_open() -> String:
	if open <= 0.0:
		return "shut"
	return "open" if open >= 1.0 else ("opening" if open >= PASS_AT else "closing")
