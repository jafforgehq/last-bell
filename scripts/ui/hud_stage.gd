## HUD8, THE MINIMAL HUD (One House): decides which boards of the HUD are on the screen, collapsed or put away, from where the run is (the STAGE TABLE of docs/hud-audit.md, section 6) and from
## the fight (the THREAT RULE), and keeps what covers the dead (and the avatar) see-through. A VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`, the last of the HUD's, so that it
## runs after the parts that make the boards); it reads the rules and writes only the look of the HUD (the opacity, the visibility, the forms the HUD itself applies: `hud.apply_stage`).
##
##   THE SETTING   Settings, HUD: `minimal` (the default, also for settings made before it existed) or `full` (today's HUD: every board, always: this part then does nothing at all). The key H puts the HUD
##                 away and brings it back (this session only; the lessons' cues go too). The school's yard and the game with no avatar have no such part: they are as they were.
##   THE STAGE     `phase_of`: road, house, claimed, rescue, dusk, night, morning, from the scenario's stage, the people, the clock's phase and the morning card (`TABLE`: the form of each part in each).
##                 A form is "off" (not there), "min" (one line, or cut down), "full", "low" (the store that is low), "thin" (cards as icons), "on", "one", "home"... as the part's own owner reads it.
##   THE THREAT    `Threat`: on when an awake dead one is within 14 tiles of her, she fired in the last 3 s or lost health in them; off when none is within 18 tiles and the three seconds are over
##                 (a hysteresis, nothing flickers at the edge of the circle). While it is on, everything that is not the fight collapses (`THREAT_FORMS`), the banners and the tips wait in a queue, and
##                 when it ends they come back after a beat, with a fade (`FADE_S`; none under Reduce motion).
##   THE GHOST     Any board that lies over an awake dead one in view, or over the avatar, is drawn at `GHOST_A` and lets the pointer through, at once, until it has been clear for `GHOST_HOLD_S`.
##   THE PLACEMENT `dead_rects` and `keep_clear` are what every card (the banner, the cues, the tips, the morning card, the windows, the plates at the edge) keeps clear of: the awake dead in view, the
##                 avatar, and the line from her to the nearest one.
extends RefCounted

const Prefs := preload("res://scripts/prefs.gd")
const Arrival := preload("res://scripts/town/arrival.gd")

# ------------------------------------------------------------------------------ the setting --

const MODES := ["minimal", "full"]
const LABELS := {"minimal": "Minimal", "full": "Full"}
const NOTES := {
	"minimal": "The boards come when they matter: the clock, the stores and the toolbar at the claim, the crew when someone joins, and in a fight only the gun, the objective and the crew. H hides it all.",
	"full": "Every board, always, as the game was. H hides the HUD whichever you choose.",
}

## The parts of the screen this decides, by name.
const PARTS := ["weapon", "stores", "objective", "arrow", "crew", "clock", "toolbar", "minimap", "edge", "legend", "lesson", "cues", "alerts", "tips", "radio", "rehearsal"]
## The phases of the first twenty minutes (docs/hud-audit.md, 6): the road in, the first house (to the claim), the claimed house alone, with the crew, the first dusk, the first night, the morning.
const PHASES := ["road", "house", "claimed", "rescue", "dusk", "night", "morning"]
## THE STAGE TABLE: for each part its form in each phase, in the order of PHASES.
const TABLE := {
	"weapon": ["min", "min", "min", "min", "min", "min", "min"],
	"stores": ["off", "off", "full", "full", "full", "low", "full"],
	"objective": ["min", "min", "full", "min", "min", "off", "off"],
	"arrow": ["on", "on", "off", "on", "off", "off", "off"],
	"crew": ["off", "off", "off", "full", "full", "thin", "thin"],
	"clock": ["min", "min", "min", "min", "mid", "min", "min"],
	"toolbar": ["min", "min", "full", "full", "full", "min", "min"],
	"minimap": ["off", "on", "on", "on", "on", "on", "on"],
	"edge": ["one", "off", "off", "home", "off", "off", "off"],
	"legend": ["off", "off", "off", "off", "off", "off", "off"],
	"lesson": ["off", "off", "off", "off", "off", "off", "off"],
	"cues": ["on", "on", "on", "on", "off", "off", "off"],
	"alerts": ["danger", "danger", "lines", "lines", "lines", "lines", "lines"],
	"tips": ["off", "off", "on", "on", "on", "on", "on"],
	"radio": ["on", "on", "on", "off", "off", "off", "off"],
	"rehearsal": ["off", "off", "on", "on", "off", "off", "off"],
}
## What a part is in the full HUD (and in no stage at all).
const FULL := {"weapon": "full", "stores": "full", "objective": "full", "arrow": "on", "crew": "full", "clock": "full", "toolbar": "full", "minimap": "on", "edge": "all", "legend": "on", "lesson": "on",
	"cues": "on", "alerts": "full", "tips": "on", "radio": "on", "rehearsal": "on"}
## THE THREAT RULE: what a part is while a fight is on (a part that is off stays off).
const THREAT_FORMS := {"stores": "low", "objective": "min", "crew": "thin", "clock": "min", "toolbar": "min", "edge": "off", "arrow": "off", "legend": "off", "lesson": "ghost", "cues": "fight", "alerts": "lines",
	"tips": "off", "radio": "off", "rehearsal": "off"}
## THE RETURN: after a fight the parts leave their fight form in this order, `RETURN_GAP_S` apart (seconds after the fight ends), the ones that are not named at once.
const RETURN := {"clock": 0.0, "objective": 0.0, "stores": 0.0, "crew": 0.5, "cues": 0.5, "toolbar": 1.0, "lesson": 1.0, "edge": 1.0, "alerts": 1.5, "tips": 2.0, "rehearsal": 1.5}

## The opacity of a form: what the part is drawn at (a form that is not named is whole).
const FORM_ALPHA := {"off": 0.0, "ghost": 0.25}
## A board over a dead one, or over the avatar, is drawn at this opacity; a board that is less than `CLICK_THROUGH_A` lets the pointer by.
const GHOST_A := 0.25
const CLICK_THROUGH_A := 0.6
## How long (seconds) a board is clear before its ghost goes, and how long the fade of a form is.
const GHOST_HOLD_S := 1.0
const FADE_S := 0.25
## THE THREAT: the dead within this many tiles (and the circle it is kept to), the seconds after a shot or a wound, how long the return waits.
const THREAT_R := 14.0
const LEAVE_R := 18.0
const SHOT_S := 3.0
const HURT_S := 3.0
## THE QUIET: no awake dead one within this many tiles (and the circle it is kept to): what can wait (a tip, a call that is not a danger, in its whole form) waits for it.
const QUIET_R := 24.0
const QUIET_LEAVE_R := 28.0
## A board that comes back after a fight waits this long between one and the next, in the order of RETURN (the last of them is at `RETURN_LAST`).
const RETURN_GAP_S := 0.5
const RETURN_LAST := 2.0
## How near (tiles) the nearest house to claim is when the first house begins (the minimap and the rest of the first house come).
const NEAR_HOUSE := 4.0
## The banner's wait: a banner older than this when the fight ends is dropped.
const BANNER_STALE_S := 5.0
## The toolbar of the claimed house is this faded while the pointer is not near it.
const TOOLBAR_IDLE_A := 0.6
## The tiles round a dead one's box that a card keeps off. A ring that marks a dead one is drawn at least this many tiles from the middle of its box (the box's corner is 0.9 tile from it), and a card keeps
## this many tiles of room round the avatar's figure for the muzzle (the coach's own).
const DEAD_GROW := 0.75
const RING_CLEAR := 0.9
const AVATAR_ROOM := 1.2
## The key that puts the HUD away.
const HIDE_KEY := KEY_H

## The names the nodes of a part are looked for under, kept in `_nodes`.
const OWNED := ["weapon", "stores", "crew", "clock", "toolbar", "edge", "cues", "alerts"]


# --------------------------------------------------------------------------- the pure rules --

## The setting now.
static func mode() -> String:
	var m := String(Prefs.get_value("ui", "hud_mode", "minimal"))
	return m if MODES.has(m) else "minimal"


static func set_mode(m: String) -> void:
	if MODES.has(m):
		Prefs.set_value("ui", "hud_mode", m)


## The phase of the run for a snapshot of it: {"stage": the scenario's stage, "crew": how many people besides her are alive, "near": a house to claim is near (the first house has begun), "phase": the clock's
## phase (day, dusk, night, dawn), "card": the morning card is up}.
static func phase_of(s: Dictionary) -> String:
	var stage := String(s.get("stage", "arrive"))
	if stage == "arrive" or stage == "alone" or stage == "cleared":
		if stage == "arrive":
			return "house" if bool(s.get("near", false)) else "road"
		return "house"
	if bool(s.get("card", false)):
		return "morning"
	match String(s.get("phase", "day")):
		"dawn":
			return "morning"
		"night":
			return "night"
		"dusk":
			return "dusk"
	return "rescue" if int(s.get("crew", 0)) >= 1 else "claimed"


## The form of `part` in `phase` with the fight on or off, the HUD put away (`hidden`) and the setting (`full_mode`).
static func form_of(part: String, phase: String, threat: bool, hidden: bool = false, full_mode: bool = false) -> String:
	if hidden:
		return "off"
	if full_mode:
		return String(FULL.get(part, "on"))
	var i := PHASES.find(phase)
	var row: Array = TABLE.get(part, [])
	var base := String(row[i]) if i >= 0 and i < row.size() else "on"
	if not threat or base == "off" or not THREAT_FORMS.has(part):
		return base
	var fight := String(THREAT_FORMS[part])
	if part == "objective" and phase == "night":
		return "off"    # (the night's fight has the gun and the crew; the day's objective is the card of the morning)
	if part == "alerts" and base == "danger":
		return base
	return fight


## The opacity a form asks for (before any ghost): "off" is nothing, "ghost" a quarter, every other form is whole.
static func alpha_of(form: String) -> float:
	return float(FORM_ALPHA.get(form, 1.0))


## THE THREAT RULE as a pure state machine (the tests drive it): `step` is told how far the nearest awake dead one is (tiles; INF for none), how long since she fired and since she lost health (seconds) and says
## whether the fight is on.
class Threat:
	extends RefCounted
	var on := false
	## Seconds the fight has been over (the HUD comes back in its own order from here).
	var calm_for := 0.0

	func step(dt: float, nearest: float, shot_age: float, hurt_age: float) -> bool:
		var enter := nearest <= THREAT_R or shot_age <= SHOT_S or hurt_age <= HURT_S
		var stay := nearest <= LEAVE_R or shot_age <= SHOT_S or hurt_age <= HURT_S
		if enter or (on and stay):
			on = true
			calm_for = 0.0
		else:
			on = false
			calm_for += dt
		return on


## The share of `a` that lies under `b` (0 to 1), for the ghost.
static func covered(a: Rect2, b: Rect2) -> float:
	if a.size.x <= 0.0 or a.size.y <= 0.0:
		return 0.0
	var hit := a.intersection(b)
	return (hit.size.x * hit.size.y) / (a.size.x * a.size.y)


## The box of an awake dead one on the screen (pixels): one tile wide and a tile and a half tall with its feet a little under the point the rules keep, a brute a third bigger (the audit's measure),
## grown by `grow_tiles` on every side.
static func dead_box(at: Vector2, zoom: float, brute: bool = false, grow_tiles: float = 0.0) -> Rect2:
	var k := 1.33 if brute else 1.0
	var r := Rect2(at.x - zoom * 0.5 * k, at.y - zoom * 0.85 * k - (k - 1.0) * zoom * 0.35, zoom * k, zoom * 1.5 * k)
	return r.grow(grow_tiles * zoom)


## Whether a dead one is a brute (its box is a third bigger).
static func is_brute(z) -> bool:
	return "kind" in z and String(z.kind) == "brute"


## Whether a dead one that the sim holds is awake and on its feet (not falling, not gone).
static func awake(z) -> bool:
	var st := String(z.state)
	if st == "dying" or st == "dead" or st == "retreat":
		return false
	return not bool(z.remove)


# ------------------------------------------------------------------------------ the part --

var main
var hud
var sim

## The phase, the forms (part -> form) and the fight, as they stand (the tests and the screenshots read them).
var phase := "road"
var forms := {}
var threat := Threat.new()
## The HUD put away with H (this session).
var hidden := false
## The opacity each part is at now (part -> 0..1) and each part's ghost (part -> 0..1: 1 whole, `GHOST_A` over a dead one).
var alpha := {}
var ghost := {}
## Seconds each part has left of its ghost.
var _hold := {}
var _target := {}
var _read_t := 0.0
var _mode_t := 0.0
var _full := false
var _near_latched := false
var _shots_last := -1
var _shot_t := 99.0
var _hp_last := -1.0
var _hurt_t := 99.0
var _nearest := INF
var _quiet := true
## Dead one's boxes in view this frame (pixels) and the avatar's boxes: what a board is ghosted over.
var _dead_boxes: Array = []
var _avatar_boxes: Array = []
## A node's saved mouse filters while it is click-through (instance id -> {node, filters}) and its saved visibility.
var _through := {}
var _saved_vis := {}
## The banners that wait for the fight to end: [{"text", "sub", "t"}], the clock they are told the time by, and whether a fight has been on and its return is not over.
var _queue: Array = []
var _clock := 0.0
var _fought := false
var _banner_shown_t := -99.0
var _applied_sig := ""
var _calm := false


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	sim = main.get("sim")
	if hud == null:
		return
	if "banner_gate" in hud:
		hud.banner_gate = _banner_gate
	_full = mode() == "full"
	_read(true)


## The part of this run, or null (the school's yard and the game with no avatar have none).
static func of(main_node):
	var town = main_node.get("town") if main_node != null else null
	return town.part("hud_stage") if town != null and town.has_method("part") else null


## Whether the HUD is minimal now (false with no such part: every other game).
static func minimal_on(main_node) -> bool:
	var p = of(main_node)
	return p != null and not bool(p._full)


# ------------------------------------------------------------------------------ the state --

func _scenario():
	return sim.get("scenario") if sim != null else null


func _me():
	if sim == null or sim.get("avatar") == null or String(sim.get("player_id")) == "":
		return null
	return sim.avatar.player()


## What the run is: the snapshot `phase_of` reads.
func state() -> Dictionary:
	var s := {"stage": "arrive", "crew": 0, "near": _near_latched, "phase": "day", "card": false}
	var sc = _scenario()
	if sc != null and sc.has_method("stage"):
		s.stage = String(sc.stage())
	if sim != null:
		s.phase = String(sim.phase)
		var pid := String(sim.get("player_id")) if sim.get("player_id") != null else ""
		var n := 0
		for p in sim.people:
			if String(p.id) != pid and not p.dead and not p.turned:
				n += 1
		s.crew = n
	var town = main.get("town") if main != null else null
	var dt = town.part("dawn_tally") if town != null else null
	s.card = dt != null and bool(dt.get("open"))
	return s


func _read(force: bool = false) -> void:
	var s := state()
	if not _near_latched and String(s.stage) == "arrive":
		var me = _me()
		var sc = _scenario()
		if me != null and sc != null and sc.has_method("_near_candidate"):
			var houses = sim.get("houses")
			var inside: bool = houses != null and int(houses.house_at(me.x, me.y)) >= 0
			if inside or float(sc._near_candidate()) < NEAR_HOUSE:
				_near_latched = true
				s.near = true
	phase = phase_of(s)
	_full = mode() == "full"
	var changed := force
	for part in PARTS:
		# (a part that has a place in the order of the return keeps its fight form until its turn comes)
		var fight := threat.on or (threat.calm_for < float(RETURN.get(part, 0.0)) and threat.calm_for > 0.0 and _fought)
		var f := form_of(part, phase, fight, hidden, _full)
		if String(forms.get(part, "")) != f:
			forms[part] = f
			changed = true
	if changed:
		_apply_forms()


# ------------------------------------------------------------------------------- the frame --

func on_frame(dt: float) -> void:
	if hud == null or sim == null:
		return
	_clock += dt
	_calm = Prefs.on("ui", "reduce_motion")
	_look(dt)
	_read_t += dt
	if _read_t >= 0.1:
		_read_t = 0.0
		_read()
	_targets(dt)
	_boxes()
	_fade(dt)
	_flush_queue()


## The fight: how far the nearest awake dead one is, how long since she fired and since she lost health.
func _look(dt: float) -> void:
	var me = _me()
	_nearest = INF
	if me == null:
		threat.step(dt, INF, 99.0, 99.0)
		return
	var shots := int(me.stats.shots) if "stats" in me and me.stats != null and me.stats.get("shots") != null else 0
	if _shots_last >= 0 and shots > _shots_last:
		_shot_t = 0.0
	_shots_last = shots
	_shot_t += dt
	var hp := float(me.hp) if "hp" in me else 100.0
	if _hp_last >= 0.0 and hp < _hp_last - 0.01:
		_hurt_t = 0.0
	_hp_last = hp
	_hurt_t += dt
	var houses = sim.get("houses")
	var mine: int = int(houses.house_at(me.x, me.y)) if houses != null else -1
	for z in sim.zombies:
		var st := String(z.state)
		if st == "dying" or st == "dead" or st == "retreat" or bool(z.remove):
			continue
		var d := Vector2(z.x - me.x, z.y - me.y).length()
		if d >= _nearest:
			continue
		# (one standing in a house she is not in is not at her: the walls are between)
		if houses != null:
			var zh: int = int(houses.house_at(z.x, z.y))
			if zh >= 0 and zh != mine:
				continue
		_nearest = d
	var was := threat.on
	threat.step(dt, _nearest, _shot_t, _hurt_t)
	if threat.on:
		_fought = true
	elif threat.calm_for > float(RETURN_LAST) + 0.2:
		_fought = false
	# (the QUIET: nothing awake in view, 24 tiles, out to 28: a call, a tip or a banner that can wait waits for it)
	var quiet := _quiet
	if threat.on or _nearest <= QUIET_R:
		quiet = false
	elif _nearest > QUIET_LEAVE_R:
		quiet = true
	if threat.on != was or quiet != _quiet:
		_quiet = quiet
		_read(true)


## The opacity each part asks for now.
func _targets(_dt: float) -> void:
	for part in PARTS:
		var f := String(forms.get(part, "on"))
		var a := alpha_of(f)
		if part == "toolbar" and f == "full" and not _full and phase != "road" and not _pointer_near(hud.get("speed_panel")):
			a = minf(a, TOOLBAR_IDLE_A)
		if part == "stores" and f == "low":
			var sc = hud.get("_stores_calm")
			if sc != null and not bool(sc.any_low):
				a = 0.0    # (a fight with no store low: no stores)
		_target[part] = a


func _pointer_near(c) -> bool:
	if c == null or not (c is Control) or not is_instance_valid(c):
		return false
	var r := (c as Control).get_global_rect().grow(90.0)
	var m = main.get("mouse_screen")
	return m is Vector2 and r.has_point(m)


## The dead in view and the avatar as boxes (pixels).
func _boxes() -> void:
	_dead_boxes.clear()
	_avatar_boxes.clear()
	if _full:
		return
	var z: float = float(main.get("zoom_px"))
	for d in sim.zombies:
		if not awake(d):
			continue
		var at: Vector2 = main._tile_to_screen(Vector2(d.x, d.y))
		var box := dead_box(at, z, is_brute(d), 0.5)
		if Rect2(Vector2.ZERO, main._vp()).intersects(box):
			_dead_boxes.append(box)
	var me = _me()
	if me != null:
		var at2: Vector2 = main._tile_to_screen(main.view_pos(me) if main.has_method("view_pos") else Vector2(me.x, me.y))
		_avatar_boxes.append(Rect2(at2.x - z * 0.6, at2.y - z * 1.9, z * 1.2, z * 2.4))


## Fades each part to its target, applies it to its nodes with the ghost of the nodes that lie over a dead one.
func _fade(dt: float) -> void:
	for part in PARTS:
		var t := float(_target.get(part, 1.0))
		var a := float(alpha.get(part, 1.0))
		if _calm or _full:
			a = t
		else:
			a = move_toward(a, t, dt / FADE_S if t >= a else dt / (FADE_S * 0.5))
		alpha[part] = a
		_apply(part, a, dt)


## The nodes a part is on the screen as.
func _nodes(part: String) -> Array:
	var town = main.get("town")
	var th = town.part("town_hud") if town != null else null
	var tc = town.part("tutor_cues") if town != null else null
	var out: Array = []
	match part:
		"weapon":
			out.append(hud.get("ammo_panel"))
		"stores":
			out.append(hud.get("res_panel"))
		"objective":
			out.append(th.get("obj_card") if th != null else null)
		"crew":
			out.append(hud.get("bar"))
		"clock":
			out.append(hud.get("clock"))
		"toolbar":
			out.append(hud.get("speed_panel"))
		"minimap":
			var mm = town.part("minimap") if town != null else null
			out.append(mm.get("root") if mm != null else null)
		"edge":
			var ea = town.part("edge_arrows") if town != null else null
			out.append(ea.get("layer") if ea != null else null)
		"legend":
			out.append(th.get("legend") if th != null else null)
		"lesson":
			out.append(th.get("lesson_card") if th != null else null)
		"radio":
			out.append(th.get("radio_card") if th != null else null)
		"rehearsal":
			out.append(tc.get("card") if tc != null else null)
		"cues":
			if tc != null:
				out.append(tc.get("layer"))
				out.append(tc.get("top"))
		"alerts":
			out.append(hud.get("alerts_box"))
			if not bool(hud.get_meta("no_alerts", false)):
				out.append(hud.get("call_card"))
				var feed = hud.get("_alert_feed")
				out.append(feed.pill if feed != null else null)
	return out


func _apply(part: String, a: float, dt: float) -> void:
	if part == "arrow" or part == "tips":
		return    # (an arrow and a tip are drawn by their owners, who ask `form`)
	var items: Array = []
	for n in _nodes(part):
		if n != null and is_instance_valid(n) and n is CanvasItem:
			items.append(n)
	# (a part is a ghost as a whole: the column of the alerts is one board to the dead, whichever of its cards they are under)
	var g := _ghost_of(part, items, dt)
	ghost[part] = g
	for n in items:
		var item := n as CanvasItem
		var shown := a * g
		if part != "legend":
			item.modulate.a = shown
		var on := shown > 0.01
		if OWNED.has(part) and (part != "alerts" or item == hud.get("alerts_box")):
			if on and not item.visible and _owner_wants(part, item):
				item.visible = true
			elif not on and item.visible:
				item.visible = false
		elif not on and item.visible and part != "rehearsal":
			item.visible = false    # (the rehearsal card is shown once, by its owner, for a few seconds: it is made clear and click-through, never put away for good)
		if item is Control:
			_click_through(item as Control, shown < CLICK_THROUGH_A and not _full)


## What the owner of the node wants when the part is on (the gun's readout is only there with an avatar).
func _owner_wants(part: String, item: CanvasItem) -> bool:
	if part == "weapon":
		return bool(hud.get("avatar_ui"))
	if part == "crew":
		return not (hud.get("cards") as Array).is_empty()
	if part == "alerts":
		return hud.size.x >= 640.0    # (a window narrower than that has the bar at the bottom and no column)
	return true


## The ghost of a part: 1 while nothing is over any of its boards, GHOST_A the moment a dead one or the avatar is, and back after `GHOST_HOLD_S` clear.
func _ghost_of(part: String, items: Array, dt: float) -> float:
	if _full or part == "cues" or part == "edge" or part == "legend":
		_hold.erase(part)
		return 1.0
	var over := false
	for item in items:
		if not (item is Control) or not item.visible:
			continue
		var rect := (item as Control).get_global_rect()
		if part == "alerts" and item == hud.get("alerts_box"):
			rect = _alerts_rect(item as Control)
		if rect.size.x > 1.0 and rect.size.y > 1.0 and (_touches(rect, _dead_boxes) or _touches(rect, _avatar_boxes)):
			over = true
	if over:
		_hold[part] = GHOST_HOLD_S
	elif _hold.has(part):
		_hold[part] = float(_hold[part]) - dt
		if float(_hold[part]) <= 0.0:
			_hold.erase(part)
	var want := GHOST_A if _hold.has(part) else 1.0
	var g := float(ghost.get(part, 1.0))
	if _calm or want < g:
		return want    # (at once)
	return move_toward(g, want, dt / FADE_S)


## The alerts' column is as tall as its cards, not as tall as the column that holds them.
func _alerts_rect(box: Control) -> Rect2:
	var r := Rect2()
	var first := true
	for c in box.get_children():
		if c is Control and (c as Control).visible and not c.is_queued_for_deletion():
			var cr := (c as Control).get_global_rect()
			r = cr if first else r.merge(cr)
			first = false
	return r


static func _touches(rect: Rect2, boxes: Array) -> bool:
	for b in boxes:
		if rect.intersects(b):
			return true
	return false


## A node that is nearly clear lets the pointer by (its children too), and has its filters back when it is whole again.
func _click_through(c: Control, on: bool) -> void:
	var id := c.get_instance_id()
	if on and not _through.has(id):
		var saved := {}
		_collect_filters(c, saved)
		_through[id] = {"node": c, "filters": saved}
		for k in saved:
			(k as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif not on and _through.has(id):
		var rec: Dictionary = _through[id]
		for k in (rec.filters as Dictionary):
			if is_instance_valid(k):
				(k as Control).mouse_filter = (rec.filters as Dictionary)[k]
		_through.erase(id)


func _collect_filters(c: Control, into: Dictionary) -> void:
	if c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		into[c] = c.mouse_filter
	for k in c.get_children():
		if k is Control:
			_collect_filters(k as Control, into)


# ------------------------------------------------------------------------------- the forms --

## What a part is now (the owners ask: the objective card, the legend, the arrows, the tips).
func form(part: String) -> String:
	return String(forms.get(part, "on"))


## Whether the part is on the screen at all now (it has a form that is not "off", and has not faded to nothing).
func shows(part: String) -> bool:
	return String(forms.get(part, "on")) != "off" or float(alpha.get(part, 0.0)) > 0.01


## Whether a tip may come now (the quiet of the game: no fight, nothing awake in view, a form of the tips that is on).
func tips_ok() -> bool:
	return _full or (_quiet and not threat.on and String(forms.get("tips", "on")) != "off")


## Whether nothing is awake within `QUIET_R` tiles (it ends beyond `QUIET_LEAVE_R`).
func quiet() -> bool:
	return _quiet


## Hands the forms to the HUD and to the town's HUD part, which lay themselves out.
func _apply_forms() -> void:
	var sig := JSON.stringify(forms) + ("|f" if _full else "|m") + ("|t" if threat.on else "|n") + ("|q" if _quiet else "|d")
	if sig == _applied_sig:
		return
	_applied_sig = sig
	var town = main.get("town")
	hud.stage_on = not _full
	hud.stage_clock = form("clock") if (form("clock") == "min" or form("clock") == "mid") else ""
	hud.stage_weapon = "min" if form("weapon") == "min" else ""
	hud.stage_crew = form("crew") if (form("crew") == "thin" or form("crew") == "off") else ""
	hud.stage_toolbar = "min" if form("toolbar") == "min" else ""
	hud.stage_alert_cap = 0 if _full else 2
	hud.stage_alert_lines = not _full and (form("alerts") == "lines" or form("alerts") == "danger")
	hud.stage_alert_danger_only = not _full and form("alerts") == "danger"
	hud.stage_banner_strip = not _full
	hud.stage_call = "" if _full else ("line" if (threat.on or not _quiet) else "idea")
	if hud.has_method("apply_stage"):
		hud.apply_stage()
	var th = town.part("town_hud") if town != null else null
	if th != null and th.has_method("set_stage"):
		th.set_stage({"objective": form("objective"), "arrow": form("arrow") == "on", "legend": form("legend") != "off", "lesson": form("lesson"), "radio": form("radio") != "off"})
	var sc = hud.get("_stores_calm")
	if sc != null:
		sc.form = "full" if _full else form("stores")
		sc.minimal = not _full
		if hud.sim_ref != null:
			sc.update(hud.sim_ref)
	var mm = town.part("minimap") if town != null else null
	if mm != null:
		mm.stage_on = form("minimap") != "off"
		mm.stage_small = not _full
		if mm.has_method("_place") and mm.get("root") != null:
			mm._place()
	var ea = town.part("edge_arrows") if town != null else null
	if ea != null:
		ea.stage_mode = "all" if _full else form("edge")
	var tc = town.part("tutor_cues") if town != null else null
	if tc != null:
		tc.stage_cues = form("cues")


# ------------------------------------------------------------------------------- the banners --

## The HUD asks before it shows a banner: true when it may be shown now, false when the fight is on (it waits in the queue, and a banner older than `BANNER_STALE_S` is dropped when it ends).
func _banner_gate(text: String, sub: String) -> bool:
	if _full or hidden:
		return not hidden
	if threat.on:
		_queue.append({"text": text, "sub": sub, "t": _clock})
		return false
	_banner_shown_t = _clock
	return true


## When the fight is over, the newest banner that has not gone stale is shown (the rest are dropped).
func _flush_queue() -> void:
	if _queue.is_empty() or threat.on or threat.calm_for < RETURN_GAP_S * 3.0:
		return
	var fresh: Array = []
	for q in _queue:
		if _clock - float(q.t) <= BANNER_STALE_S + SHOT_S + RETURN_GAP_S * 3.0:
			fresh.append(q)
	_queue.clear()
	if fresh.is_empty():
		return
	var last: Dictionary = fresh[fresh.size() - 1]
	hud.show_banner(String(last.text), String(last.sub))


## Puts the banner away at the first key or click after it has been up a moment (the opening words of the run).
func _dismiss_banner() -> void:
	if hud.banner == null or hud.banner.modulate.a < 0.05 or _clock - _banner_shown_t < 0.6:
		return
	if hud.has_method("dismiss_banner"):
		hud.dismiss_banner()


# --------------------------------------------------------------------------------- the key --

## H puts the HUD away and brings it back; any other first key or click puts the banner away.
func on_key(ev: InputEvent) -> bool:
	if hud == null:
		return false
	var down := (ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo) or (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed)
	if not down:
		return false
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code: Key = k.keycode if k.keycode != KEY_NONE else k.physical_keycode
		if code == HIDE_KEY and not k.ctrl_pressed and not k.alt_pressed and not k.meta_pressed and not k.shift_pressed:
			if bool(main.get("menu_open")) or bool(main.get("title_mode")):
				return false
			toggle_hidden()
			return true
	if not _full:
		_dismiss_banner()
	return false


func toggle_hidden() -> void:
	hidden = not hidden
	_read(true)
	hud.toast("HUD put away. H brings it back" if hidden else "HUD back", "info")


func modal() -> bool:
	return false


# ---------------------------------------------------------------------- the placement rule --

## The awake dead one's boxes in view, in HUD pixels, each grown by `grow_tiles` (a card keeps off them).
static func dead_rects(main_node, grow_tiles: float = DEAD_GROW) -> Array:
	var out: Array = []
	var part = of(main_node)
	if part == null or bool(part._full):
		return out    # (the school's yard and the full HUD place their cards as they always did)
	var sim_node = main_node.get("sim")
	if sim_node == null:
		return out
	var z: float = float(main_node.get("zoom_px"))
	var vp: Vector2 = main_node._vp()
	for d in sim_node.zombies:
		if not awake(d):
			continue
		var at: Vector2 = main_node._tile_to_screen(Vector2(d.x, d.y))
		var box := dead_box(at, z, is_brute(d), grow_tiles)
		if Rect2(Vector2.ZERO, vp).intersects(box):
			out.append(box)
	return out


## The middle half of the window, in each direction: where the avatar and the fight are. A card that can go to the sides does (the morning card, the windows): the audit counts what the UI covers there.
## [] with no such part.
static func middle_zone(main_node) -> Array:
	var part = of(main_node)
	if part == null or bool(part._full):
		return []
	var vp: Vector2 = main_node._vp()
	return [Rect2(vp.x * 0.25, vp.y * 0.25, vp.x * 0.5, vp.y * 0.5)]


## The avatar's own room: her figure with her tag, and the room round her for the gun's muzzle (the coach's rule, scripts/ui/coach.gd `_kept_clear`), in HUD pixels. [] with no such part.
static func avatar_clear(main_node) -> Array:
	var part = of(main_node)
	if part == null or bool(part._full):
		return []
	var me = part._me()
	if me == null or me.away != null:
		return []
	var out: Array = []
	var at: Vector2 = main_node.view_pos(me) if main_node.has_method("view_pos") else Vector2(me.x, me.y)
	var a: Vector2 = main_node._tile_to_screen(at + Vector2(-0.5, -1.9))
	var b: Vector2 = main_node._tile_to_screen(at + Vector2(0.5, 0.5))
	out.append(Rect2(a, b - a).abs())
	var c: Vector2 = main_node._tile_to_screen(at + Vector2(0.0, -0.45))
	var r: float = AVATAR_ROOM * float(main_node.get("zoom_px"))
	out.append(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	return out


## What every card keeps clear of in a run with this part: the awake dead in view and the line of fire from the avatar to the nearest of them (boxes along it), in HUD pixels. [] with no such part (the school).
static func keep_clear(main_node) -> Array:
	var part = of(main_node)
	if part == null or bool(part._full):
		return []
	var out: Array = dead_rects(main_node, DEAD_GROW)
	var me = part._me()
	if me == null:
		return out
	var z: float = float(main_node.get("zoom_px"))
	var here := Vector2(me.x, me.y)
	var best := INF
	var at := Vector2.ZERO
	for d in part.sim.zombies:
		if not awake(d):
			continue
		var dist := here.distance_to(Vector2(d.x, d.y))
		if dist < best and dist <= LEAVE_R:
			best = dist
			at = Vector2(d.x, d.y)
	if best < INF:
		var steps := int(minf(best, THREAT_R) / 2.5)
		for i in range(1, steps + 1):
			var p: Vector2 = main_node._tile_to_screen(here.lerp(at, float(i) * 2.5 / best))
			out.append(Rect2(p - Vector2(z, z) * 0.8, Vector2(z, z) * 1.6))
	return out
