## The HUD of the live drive (round 21, V21.2). It IS the place's HUD (scripts/raid/raid_hud.gd: the squad's cards, the radio, the News
## log, the call card, the base's clock, the log, the banner, the toast and the ammunition are all inherited and work as they do in a
## place) with four things added, each in a corner the place's HUD leaves free and each laid out in the base's own `_layout`, so that
## nothing overlaps at any width from 700 up:
##
##   the road       (top right, where the bags are in a place: there are no containers on a road) the leg ("Road there", "Road home"),
##                  where it ends, a bar with the place's flag at the end, a small tick for each event ALREADY MET (never the ones
##                  ahead: the road keeps its surprises) and the car's mark, "Ahead of the clock: 6 min" / "On time" / "Behind: 9
##                  min" (the colony's clock against the road's own: driving well saves game minutes), and the autopilot's button
##   the gauges     (the foot, in the ammunition's board) a speed dial with its word (Stopped, Slow, Cruising, Fast; a mark at cruise
##                  and a red arc beyond it: fast arrives early and the car takes the knocks), the fuel of the trip tank ("Fuel 1.4
##                  of 2.1", the base's tank under it), the vehicle's hp bar (amber under half, red under 30% with "The engine is
##                  smoking"). In a window with no room for them beside the ammunition they are three short columns under it. On
##                  foot (or with the car wrecked) there are no gauges: the road and the clock are all there is
##   the event card (above the foot) the open event's title and line, one button for each choice with its key (1 to 4), a choice that
##                  is refused greyed with its reason in the tooltip AND in amber under it, the choice taken by default marked with
##                  a countdown ring (the card never pauses anything: the base goes on while you read it)
##   the prompt     "E  Stop: someone is waving" within 40 tiles of a stop, "E  Roadblock: clear it" near a block, the squad's
##                  work at a stop ("Working at the stop: 6 s") and "E  Back in the car"
##
## The legend of the keys is the road's (W S gas and brake, A D steer, Click shoot, R reload, E stop, Tab autopilot...; on foot the
## place's, with E to stop); the squad's verbs are off the radio while you are aboard ("You are driving": the squad rides with you
## and the people at the base stay); the News and the call card count their seconds at the leg's pace (`scene.pace() / 3`).
##
## WHAT IT READS OF THE SCENE (scripts/drive/drive_scene.gd; every part is guarded, a scene without one reads as nothing, and a
## plain place scene gives a HUD that is exactly the place's): `leg` ("there", "place", "home"), `mode` ("drive", "stopped",
## "out", "foot"), `in_car()`, `aboard()`, `car` (hp, kind, cruise, top), `road_progress()`, `speed_now()`, `pace()`, `plan` (the
## events: uid, id, kind, at, state, def), `site.road.len`, `work_left`, `autopilot`, `toggle_autopilot()`, `choose(uid, option_id)`
## and `flow` (`place_id`, `vehicle_id`, `elapsed_min()`, `road_total`). Optional, for what the plan leaves open: `open_event()` (the
## entry whose card is open), `event_options(uid)` (its options as RoadEvents.options gives them), `event_left(uid)` (the seconds the
## card has left), `road_ctx()` (the context RoadEvents.options needs, when the scene gives no options of its own).
##
## API for the tests: gauge_words(), event_options(), press_option(i), prompt_text(), legend_text(), on_stage(leg, site).
extends "res://scripts/raid/raid_hud.gd"

const ROAD_EVENTS_PATH := "res://scripts/drive/road_events.gd"

const ROUTE_W := 252.0
const BAR_W := 168.0
const DIAL_W := 84.0
const DIAL_H := 66.0
const MINI_W := 88.0
const EVENT_W := 380.0
const EVENT_W_MIN := 240.0
const OPTION_H := 30.0
const MAX_OPTIONS := 4
const AUTO_PAD := 50.0
## The speed's number on the dial: tiles a second times this (a pickup's cruise is about 60).
const KMH := 9.0
## How far ahead (tiles) a stop calls for the E key, and a roadblock.
const STOP_REACH := 40.0
const BLOCK_REACH := 25.0
## Below this speed (tiles a second) a roadblock can be cleared.
const BLOCK_SLOW := 3.0
## A leg is on time within this many game minutes.
const ON_TIME_MIN := 0.5
## The width the ammunition and the gauges need side by side (the ammunition's, the dial, the columns beside it, the board's margins).
const DASH_ROW_W := 540.0
## The seconds a card has when the scene does not say.
const DEFAULT_TTL := 8.0
const WORN_BELOW := 0.5
const SMOKING_BELOW := 0.3

## The keys on the road in a car, and on foot (the place's own are LEGEND).
const CAR_LEGEND := [
	[["W", "S"], "gas and brake"], [["A", "D"], "steer"], [["Click"], "shoot"], [["R"], "reload"], [["E"], "stop"], [["Tab"], "autopilot"],
	[["Space"], "pause"], [["T"], "news"],
]
const FOOT_LEGEND := [
	[["W", "A", "S", "D"], "walk"], [["Click"], "shoot"], [["R"], "reload"], [["F"], "melee"], [["E"], "stop"], [["Space"], "pause"], [["T"], "news"],
	[["Scroll"], "zoom"],
]
## What an event is, in the small capitals over its title, and the colour of its tick on the road and of the card's edge.
const KIND_WORD := {"stop": "Stop", "block": "Roadblock", "forced": "Trouble", "dead": "Danger"}
const KIND_COLOR := {"stop": Hud.INFO, "block": Hud.WARN, "forced": Hud.WARN, "dead": Hud.DANGER_TEXT}
## The few words of what a stop is, for the prompt, when the event's own data has none (`def.prompt`).
const STOP_PHRASE := {
	"survivor": "someone is waving", "wreck_supplies": "a wreck with its boot full", "fuel_stash": "fuel by the verge",
	"checkpoint": "a barrier ahead", "smoke": "a sign and smoke ahead", "roadblock": "clear it",
}

# the road
var route_box: VBoxContainer
var bags_box: Control
var route_caps: Label
var route_bar
var route_delta: Label
var auto_button: Button
# the gauges
var dash: BoxContainer
var ammo_col: Control
var roomy_box: HBoxContainer
var mini_box: HBoxContainer
var dial
var dial_word: Label
var fuel_head: Label
var fuel_bar
var tank_label: Label
var hp_head: Label
var hp_bar
var hp_note: Label
var hp_gate: Label
var mini_speed: Label
var mini_speed_bar
var mini_fuel: Label
var mini_fuel_bar
var mini_hp: Label
var mini_hp_bar
# the event card and the prompt
var event_panel: PanelContainer
var event_kind: Label
var event_title: Label
var event_text: Label
var event_note: Label
var event_ring
var event_rows: GridContainer
var event_buttons: Array = []    # {"id", "button", "ring", "auto", "ok", "why", "line"}
var event_uid := ""
var prompt_panel: PanelContainer
var prompt_key: Control
var prompt_label: Label
var _event_sig := ""
var _note_tween: Tween
var _banner_wanted := false
var _event_edge := Hud.INFO
var _legend_key := ""
var _roomy := true
var _squad_seen: Array = []


func setup(game_hud, the_scene) -> void:
	super.setup(game_hud, the_scene)
	name = "DriveHud"
	_build_route()
	_build_dash()
	_build_event()
	_build_prompt()
	# the News and the call card count their seconds at the leg's pace
	var getter := func(): return _pace_speed()
	news_panel.setup(hud, func(): return scene.colony_radio(), {"speed_getter": getter})
	call_card.setup(hud, func(): return scene.colony_radio(), {"speed_getter": getter})
	_squad_seen = _squad_now()
	_layout()


# ------------------------------------------------------------ what the scene says --

func _g(key: String, fallback = null):
	var v = scene.get(key) if scene != null else null
	return fallback if v == null else v


func _leg() -> String:
	return String(_g("leg", ""))


## On the road, there or home (not in the place, and not in a scene that is only a place).
func _driving() -> bool:
	var l := _leg()
	return l == "there" or l == "home"


func _mode() -> String:
	return String(_g("mode", ""))


func _in_car() -> bool:
	return scene != null and scene.has_method("in_car") and bool(scene.in_car())


func _car():
	return _g("car")


## A car is something to drive and to read: not one that is a wreck (the squad is out of it, the rest of the road is on foot: no gauges).
func _has_car() -> bool:
	return _car() != null and not bool(_g("_wrecked", false))


func _live() -> bool:
	return scene != null and scene.phase == "place" and not scene.ended


func _progress() -> float:
	return clampf(float(scene.road_progress()), 0.0, 1.0) if scene != null and scene.has_method("road_progress") else 0.0


## The car's speed in tiles a second, negative in reverse (the scene's `speed_now` is a magnitude; the car knows its direction).
func _speed() -> float:
	if scene == null or not scene.has_method("speed_now"):
		return 0.0
	var s := float(scene.speed_now())
	var c = _car()
	if c != null and c.get("speed") != null and float(c.get("speed")) < -0.3 and s > 0.0:
		return -s
	return s


func _cruise() -> float:
	var c = _car()
	if c != null and c.get("cruise") != null:
		return maxf(float(c.get("cruise")), 0.1)
	return 3.2


func _top() -> float:
	var c = _car()
	if c != null and c.get("top") != null:
		return maxf(float(c.get("top")), _cruise())
	return _cruise() * 1.5


func _pace() -> float:
	if scene != null and scene.has_method("pace"):
		return float(scene.pace())
	var flow = _g("flow")
	return float(flow.get("leg_pace")) if flow != null and flow.get("leg_pace") != null else 1.0


## How many times the game's normal pace the player's clock runs at, for the radio's countdowns: the leg's pace of game minutes
## a second against the yard's three; the place's third in the place.
func _pace_speed() -> float:
	if _driving():
		return maxf(_pace(), 0.05) / 3.0
	return PlaceFlow.PLACE_PACE


func _plan() -> Array:
	var p = _g("plan", [])
	return p if p is Array else []


func _road_len() -> float:
	var road = _g("road", {})
	if road is Dictionary and road.has("len"):
		return float(road.len)
	var site_road = scene.site.get("road", {}) if scene != null and scene.site is Dictionary else {}
	return float(site_road.get("len", 0.0)) if site_road is Dictionary else 0.0


## The game minutes this leg's road is (the abstract road's): what the flow says, else what the pace and the strip make of it
## (the pace is road minutes over the leg's seconds at cruise, and the strip is those seconds' tiles).
func _road_min() -> float:
	var flow = _g("flow")
	if scene != null and scene.has_method("road_minutes"):
		return float(scene.road_minutes())
	if flow != null:
		for key in ["leg_road_min", "road_total"]:
			var v = flow.get(key)
			if v != null and float(v) > 0.0:
				return float(v)
	var road_len := _road_len()
	return _pace() * road_len / _cruise() if road_len > 0.0 else 0.0


func _squad_now() -> Array:
	return scene.run.squad.duplicate() if scene != null and scene.run != null else []


## The destination as a phrase: "The pharmacy" (the flow's place, else the road's name without "The road to" or "The road home from").
func place_name() -> String:
	var flow = _g("flow")
	var cs = scene.colony() if scene != null else null
	if flow != null and cs != null and flow.get("place_id") != null:
		var pl: Dictionary = cs.town.place(String(flow.place_id))
		if not pl.is_empty():
			return String(pl.get("name", ""))
	var road_name := String(scene.site.get("name", "")) if scene != null else ""
	return road_name.trim_prefix("The road home from ").trim_prefix("The road to ")


# ------------------------------------------------------------------- the road --

func _build_route() -> void:
	bags_box = loot_panel.get_child(0)
	route_box = hud._vbox(5)
	route_box.custom_minimum_size.x = ROUTE_W
	var head: HBoxContainer = hud._hbox(6)
	route_caps = hud._caps("Road there")
	route_caps.clip_text = true
	route_caps.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	route_caps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	route_caps.custom_minimum_size.x = 60.0
	head.add_child(route_caps)
	auto_button = RadioKit.small_button(hud, "Autopilot", 24.0, 13)
	auto_button.pressed.connect(_on_auto_pressed)
	head.add_child(auto_button)
	route_box.add_child(head)
	route_bar = RouteBar.new()
	route_bar.custom_minimum_size = Vector2(ROUTE_W, 22)
	route_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	route_box.add_child(route_bar)
	route_delta = hud._label("On time", Fonts.sans(600), 13, Hud.INK2)
	route_delta.clip_text = true
	route_delta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	route_delta.mouse_filter = Control.MOUSE_FILTER_PASS
	route_delta.tooltip_text = "Game minutes won or lost against the road's own time. Driving fast and clean saves them; crashes, grass and stops cost them."
	route_box.add_child(route_delta)
	route_box.visible = false
	loot_panel.add_child(route_box)


func _on_auto_pressed() -> void:
	if scene != null and scene.has_method("toggle_autopilot"):
		scene.toggle_autopilot()
	refresh()


## The tick of each event already met on the road: [{"at", "color"}] (an event that is still ahead is not drawn).
func ticks() -> Array:
	var out: Array = []
	for e in _plan():
		if String(e.get("state", "pending")) == "pending":
			continue
		out.append({"at": float(e.get("at", 0.0)), "color": KIND_COLOR.get(String(e.get("kind", "")), Hud.INK2)})
	return out


## The clock of the leg against the road's own: positive is ahead (game minutes saved so far).
func saved_minutes() -> float:
	var flow = _g("flow")
	if flow == null:
		return 0.0
	if flow.has_method("delta_min"):
		return float(flow.delta_min(_progress()))
	if not flow.has_method("elapsed_min"):
		return 0.0
	return _progress() * _road_min() - float(flow.elapsed_min())


func delta_text() -> String:
	var saved := saved_minutes()
	if absf(saved) < ON_TIME_MIN:
		return "On time"
	if saved > 0.0:
		return "Ahead of the clock: %d min" % roundi(saved)
	return "Behind: %d min" % roundi(-saved)


func _delta_color() -> Color:
	var saved := saved_minutes()
	if absf(saved) < ON_TIME_MIN:
		return Hud.INK2
	return Hud.OK if saved > 0.0 else Hud.WARN


func _update_route() -> void:
	var home := _leg() == "home"
	route_caps.text = ("Road home" if home else "Road there").to_upper()
	route_bar.tooltip_text = "The flag is %s." % ("home" if home else place_phrase_of(place_name()))
	route_bar.value = _progress()
	route_bar.ticks = ticks()
	route_bar.queue_redraw()
	route_delta.text = delta_text()
	route_delta.add_theme_color_override("font_color", _delta_color())
	auto_button.visible = _has_car()
	var on: bool = bool(_g("autopilot", false))
	auto_button.modulate = Color(1.0, 0.92, 0.6) if on else Color.WHITE
	auto_button.text = "Autopilot: on" if on else "Autopilot"
	auto_button.tooltip_text = ("Autopilot is on: the best driver has the wheel. Press W A S D to take it back (Tab)"
		if on else "Let the best driver take the wheel: slower, and it takes the safe option at every stop (Tab)")


# ------------------------------------------------------------------ the gauges --

func _build_dash() -> void:
	ammo_col = weapon_panel.get_child(0)
	weapon_panel.remove_child(ammo_col)
	ammo_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dash = BoxContainer.new()
	dash.vertical = true
	dash.add_theme_constant_override("separation", 8)
	dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dash.add_child(ammo_col)
	weapon_panel.add_child(dash)
	# the roomy form: the dial and its word, and the fuel and the hp in a column beside it
	roomy_box = hud._hbox(8)
	var dial_col: VBoxContainer = hud._vbox(0)
	dial = SpeedDial.new()
	dial.custom_minimum_size = Vector2(DIAL_W, DIAL_H)
	dial.mouse_filter = Control.MOUSE_FILTER_PASS
	dial.font = Fonts.cond(700)
	dial.small_font = Fonts.sans(600)
	dial.ink = Hud.INK
	dial.ink2 = Hud.INK2
	dial.track = Color(0.93, 0.96, 0.89, 0.16)
	dial.fast_zone = Color(Hud.DANGER, 0.7)
	dial.tooltip_text = "Speed. The mark is cruising speed; past it (the red arc) you arrive early and the car takes the knocks."
	dial_col.add_child(dial)
	dial_word = hud._label("Stopped", Fonts.cond(700), 14, Hud.INK2)
	dial_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dial_col.add_child(dial_word)
	roomy_box.add_child(dial_col)
	var info: VBoxContainer = hud._vbox(2)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fuel_row: HBoxContainer = hud._hbox(6)
	fuel_head = hud._label("Fuel", Fonts.cond(700), 15, Hud.INK)
	fuel_row.add_child(fuel_head)
	info.add_child(fuel_row)
	fuel_bar = _gauge_bar(BAR_W)
	info.add_child(fuel_bar)
	tank_label = hud._label("", Fonts.sans(400), 12, Hud.INK3)
	info.add_child(tank_label)
	hp_head = hud._label("Pickup", Fonts.cond(700), 15, Hud.INK)
	info.add_child(hp_head)
	hp_bar = _gauge_bar(BAR_W)
	info.add_child(hp_bar)
	hp_note = hud._label("", Fonts.sans(600), 12, Hud.DANGER_TEXT)
	info.add_child(hp_note)
	hp_gate = hud._label("", Fonts.sans(600), 12, Hud.WARN)
	hp_gate.tooltip_text = "The place's danger wears the vehicle when it comes home: it is taken off the bar at the gate."
	hp_gate.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(hp_gate)
	roomy_box.add_child(info)
	roomy_box.visible = false
	dash.add_child(roomy_box)
	# the narrow form: three short columns under the ammunition
	mini_box = hud._hbox(8)
	for k in ["speed", "fuel", "hp"]:
		var col: VBoxContainer = hud._vbox(2)
		col.custom_minimum_size.x = MINI_W
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l: Label = hud._label("", Fonts.cond(700), 14, Hud.INK)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = MINI_W
		col.add_child(l)
		var b = _gauge_bar(MINI_W)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(b)
		mini_box.add_child(col)
		match k:
			"speed":
				mini_speed = l
				mini_speed_bar = b
			"fuel":
				mini_fuel = l
				mini_fuel_bar = b
			_:
				mini_hp = l
				mini_hp_bar = b
	mini_box.visible = false
	dash.add_child(mini_box)


func _gauge_bar(w: float):
	var b = hud.Bar.new()
	b.custom_minimum_size = Vector2(w, 6)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.groove = hud.frame("bar_track")
	return b


## The width the foot offers the ammunition's board (the board is placed by the base's layout in the middle of the foot in a wide
## window and in the left column in a narrow one).
func _dash_room() -> float:
	var w: float = root.size.x
	if w >= WIDE_W:
		var bas := base_panel.get_combined_minimum_size()
		return (w - PAD - bas.x - GAP) - (PAD + LOG_W + GAP)
	return maxf(120.0, (w - PAD - maxf(radio_panel.get_combined_minimum_size().x, RADIO_W)) - GAP - PAD)


## The speed in the dial's number.
func kmh(speed: float) -> int:
	return roundi(absf(speed) * KMH)


## The word of a speed against the cruise: Stopped, Slow, Cruising (from 55% of it), Fast (past it), Reversing.
static func speed_word(speed: float, cruise: float) -> String:
	if speed < -0.3:
		return "Reversing"
	if absf(speed) < 0.3:
		return "Stopped"
	if speed >= cruise * 1.02:
		return "Fast"
	if speed >= cruise * 0.55:
		return "Cruising"
	return "Slow"


static func num(v: float) -> String:
	return "%d" % roundi(v) if absf(v - roundf(v)) < 0.05 else "%.1f" % v


## The trip tank: {"left", "total", "base"} (the fuel burnt at the gate for both legs, draining by the distance driven), or {} with no car.
func fuel_now() -> Dictionary:
	var flow = _g("flow")
	var cs = scene.colony() if scene != null else null
	if not _has_car() or flow == null or cs == null or cs.get("vehicles") == null:
		return {}
	var veh = cs.vehicles
	var place_id := String(flow.get("place_id")) if flow.get("place_id") != null else ""
	var vehicle_id := String(flow.get("vehicle_id")) if flow.get("vehicle_id") != null else ""
	var per_leg: float = float(veh.fuel_per_leg(place_id, vehicle_id)) if veh.has_method("fuel_per_leg") else float(veh.fuel_for(place_id, vehicle_id)) / 2.0
	var burnt_legs := 1.0 if _leg() == "home" else 0.0
	return {"left": maxf(0.0, per_leg * (2.0 - burnt_legs - _progress())), "total": per_leg * 2.0, "base": float(veh.fuel)}


## The vehicle's condition, 0 to 1 (its hp against the new one's), and its name.
func hp_now() -> Dictionary:
	var c = _car()
	if c == null:
		return {}
	var kind: Dictionary = c.get("kind") if c.get("kind") is Dictionary else {}
	var full := maxf(float(kind.get("hp", 100.0)), 1.0)
	return {"share": clampf(float(c.get("hp")) / full, 0.0, 1.0), "name": String(kind.get("name", "Car"))}


## The words of the gauges, for the board and for the tests.
func gauge_words() -> Dictionary:
	var out := {"speed": "", "kmh": "", "fuel": "", "tank": "", "hp": "", "hp_note": "", "gate": "", "gate_lost": false, "progress": "%d%%" % roundi(_progress() * 100.0), "delta": delta_text()}
	if not _has_car():
		return out
	out.speed = speed_word(_speed(), _cruise())
	out.kmh = str(kmh(_speed()))
	var f := fuel_now()
	if not f.is_empty():
		out.fuel = "Fuel %s of %s" % [num(float(f.left)), num(float(f.total))]
		out.tank = "Base tank %s" % num(float(f.base))
	var h := hp_now()
	out.hp = "%s %d%%" % [String(h.name), roundi(float(h.share) * 100.0)]
	if float(h.share) < SMOKING_BELOW:
		out.hp_note = "The engine is smoking"
	var wear := gate_wear()
	if wear > 0.0:
		var points := float(_car().get("hp"))
		out.gate_lost = points - wear <= 0.0
		out.gate = ("Lost at the gate: -%s more (the place's danger)" if out.gate_lost else "-%s more at the gate (the place's danger)") % num(wear)
	return out


## The place's danger wears the vehicle when it is home (the colony's `vehicles.come_home`: 5 for each point of danger): on the way home
## the bar says what the gate will take (a car at 8 hp from a danger-2 place does not make it).
func gate_wear() -> float:
	if _leg() != "home" or not _has_car():
		return 0.0
	var flow = _g("flow")
	var cs = scene.colony() if scene != null else null
	if flow == null or cs == null or cs.get("vehicles") == null or cs.get("scavenge") == null or flow.get("place_id") == null:
		return 0.0
	var danger := 0
	for site in cs.scavenge.sites:
		if String(site.id) == String(flow.place_id):
			danger = int(site.get("danger", 0))
			break
	return float(cs.vehicles.WEAR_PER_DANGER) * float(danger)


func _update_gauges() -> void:
	var words := gauge_words()
	var share := float(hp_now().get("share", 1.0))
	var f := fuel_now()
	var fuel_share := clampf(float(f.left) / maxf(float(f.total), 0.001), 0.0, 1.0) if not f.is_empty() else 0.0
	var top := _top()
	var speed_share := clampf(absf(_speed()) / top, 0.0, 1.0)
	var hp_color: Color = Hud.DANGER if share < SMOKING_BELOW else (Hud.WARN if share < WORN_BELOW else Hud.OK)
	var fuel_color: Color = Hud.DANGER if fuel_share < 0.15 else (Hud.WARN if fuel_share < 0.3 else Hud.OK)
	var speed_color := _speed_color()
	# the roomy form
	dial.cruise_frac = _cruise() / top
	dial.number = str(words.kmh)
	dial.color = speed_color
	dial.target = speed_share
	dial_word.text = String(words.speed)
	dial_word.add_theme_color_override("font_color", speed_color if words.speed != "Stopped" else Hud.INK2)
	fuel_head.text = String(words.fuel)
	fuel_bar.value = fuel_share
	fuel_bar.color = fuel_color
	tank_label.text = String(words.tank)
	hp_head.text = String(words.hp)
	hp_bar.value = share
	hp_bar.color = hp_color
	hp_note.text = String(words.hp_note)
	hp_note.visible = String(words.hp_note) != ""
	hp_gate.text = String(words.gate)
	hp_gate.visible = String(words.gate) != ""
	hp_gate.add_theme_color_override("font_color", Hud.DANGER_TEXT if bool(words.gate_lost) else Hud.WARN)
	# the narrow form
	mini_speed.text = "%s %s" % [words.speed, words.kmh]
	mini_speed_bar.value = speed_share
	mini_speed_bar.color = speed_color
	mini_fuel.text = String(words.fuel).trim_prefix("Fuel ")
	mini_fuel_bar.value = fuel_share
	mini_fuel_bar.color = fuel_color
	var gate_note: bool = bool(words.gate_lost)
	mini_hp.text = ("Lost at gate! %d%%" % roundi(share * 100.0)) if gate_note else (("Smoking! %d%%" % roundi(share * 100.0)) if String(words.hp_note) != "" else String(words.hp))
	mini_hp.add_theme_color_override("font_color", Hud.DANGER_TEXT if (String(words.hp_note) != "" or gate_note) else Hud.INK)
	mini_hp_bar.value = share
	mini_hp_bar.color = hp_color
	for b in [fuel_bar, hp_bar, mini_speed_bar, mini_fuel_bar, mini_hp_bar]:
		b.queue_redraw()
	dial.queue_redraw()
	mini_fuel.tooltip_text = "%s\n%s" % [words.fuel, words.tank]
	mini_fuel.mouse_filter = Control.MOUSE_FILTER_PASS
	mini_hp.tooltip_text = (String(words.hp) if String(words.hp_note) == "" else "%s: %s" % [words.hp, words.hp_note]) + ("\n" + String(words.gate) if String(words.gate) != "" else "")
	mini_hp.mouse_filter = Control.MOUSE_FILTER_PASS
	mini_speed.tooltip_text = "Speed. Past cruising you arrive early and the car takes the knocks."
	mini_speed.mouse_filter = Control.MOUSE_FILTER_PASS


func _speed_color() -> Color:
	var s := _speed()
	var c := _cruise()
	if absf(s) < 0.3:
		return Hud.INK2
	if s >= c * 1.02:
		return Hud.WARN if s < c * 1.3 else Hud.DANGER_TEXT
	return Hud.OK if s >= c * 0.55 else Hud.INK


# -------------------------------------------------------------- the event card --

func _build_event() -> void:
	event_panel = PanelContainer.new()
	var st: StyleBox = hud._style(Hud.PANEL, 6, Hud.LINE2, true, "panel")
	if st is StyleBoxFlat:
		st.content_margin_left = 16
	else:
		st.content_margin_left = maxf(st.content_margin_left, 16.0)
	event_panel.add_theme_stylebox_override("panel", st)
	event_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	event_panel.draw.connect(func(): event_panel.draw_rect(Rect2(5, 6, 3, maxf(0.0, event_panel.size.y - 12.0)), _event_edge))
	var col: VBoxContainer = hud._vbox(3)
	var head: HBoxContainer = hud._hbox(6)
	event_kind = hud._caps("Stop", Hud.INFO)
	event_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(event_kind)
	event_ring = Ring.new()
	event_ring.font = Fonts.cond(700)
	event_ring.color = Hud.ACCENT
	event_ring.track = Color(0.93, 0.96, 0.89, 0.22)
	event_ring.ink = Hud.INK
	event_ring.custom_minimum_size = Vector2(26, 26)
	event_ring.mouse_filter = Control.MOUSE_FILTER_PASS
	event_ring.tooltip_text = "This card closes by itself. Press E at the stop to open it again."
	event_ring.visible = false
	head.add_child(event_ring)
	col.add_child(head)
	event_title = hud._label("", Fonts.cond(700), 20, Hud.INK)
	event_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_title.custom_minimum_size.x = 100
	col.add_child(event_title)
	event_text = hud._label("", Fonts.sans(400), 13, Hud.INK2)
	event_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_text.custom_minimum_size.x = 100
	col.add_child(event_text)
	event_note = hud._label("", Fonts.sans(600), 13, Hud.WARN)
	event_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_note.custom_minimum_size.x = 100
	event_note.visible = false
	col.add_child(event_note)
	event_rows = GridContainer.new()
	event_rows.columns = 2
	event_rows.add_theme_constant_override("h_separation", 10)
	event_rows.add_theme_constant_override("v_separation", 4)
	event_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(event_rows)
	event_panel.add_child(col)
	event_panel.visible = false
	_put(event_panel)


## The entry of the plan whose card is open now ({} when none).
func open_entry() -> Dictionary:
	if scene == null:
		return {}
	if scene.has_method("open_event"):
		var e = scene.open_event()
		return e if e is Dictionary else {}
	for e in _plan():
		if String(e.get("state", "")) == "open":
			return e
	return {}


## The options of an entry: what the scene gives (an empty answer is a card that is never shown: an ambush asks nothing), else what the
## entry carries, else RoadEvents' own for the scene's context, else the def's own choices.
func _options_for(entry: Dictionary) -> Array:
	var uid := String(entry.get("uid", ""))
	var raw: Array = []
	if scene.has_method("event_options"):
		raw = scene.event_options(uid)
	elif entry.get("options") is Array:
		raw = entry.options
	elif ResourceLoader.exists(ROAD_EVENTS_PATH) and scene.has_method("road_ctx"):
		raw = load(ROAD_EVENTS_PATH).options(entry, scene.road_ctx())
	else:
		var def: Dictionary = entry.get("def", {})
		for c in def.get("choices", []):
			raw.append({"id": String(c.id), "label": String(c.label), "ok": true, "why": "", "auto": String(c.id) == String(def.get("auto", ""))})
	var out: Array = []
	for o in raw:
		out.append({"id": String(o.get("id", "")), "label": String(o.get("label", "")), "ok": bool(o.get("ok", true)), "why": String(o.get("why", "")), "auto": bool(o.get("auto", false))})
	return out


## The seconds the open card has left (-1: it has no countdown) and the seconds it began with.
func _left_for(entry: Dictionary) -> float:
	var uid := String(entry.get("uid", ""))
	if scene.has_method("event_left"):
		return float(scene.event_left(uid))
	for key in ["left_s", "left"]:
		if entry.has(key):
			return float(entry[key])
	return -1.0


func _ttl_for(entry: Dictionary) -> float:
	var def: Dictionary = entry.get("def", {})
	return maxf(float(entry.get("ttl_s", def.get("ttl_s", DEFAULT_TTL))), 0.1)


## The options of the open card for the tests: [{"id", "text", "key", "disabled", "why", "auto"}] (empty when no card is open).
func event_options() -> Array:
	var entry := open_entry()
	if entry.is_empty() or not _live() or not _driving():
		return []
	var out: Array = []
	var i := 0
	for o in _options_for(entry):
		if i >= MAX_OPTIONS:
			break
		i += 1
		out.append({"id": o.id, "text": o.label, "key": str(i), "disabled": not bool(o.ok), "why": o.why if not bool(o.ok) else "", "auto": o.auto})
	return out


## Takes option `i` (0 for the first, as in `event_options()`), as the key or the button does: the scene's `choose`. A refused one
## answers with its reason (and the toast says it) and nothing is chosen.
func press_option(i: int) -> Dictionary:
	var opts := event_options()
	if i < 0 or i >= opts.size():
		return {"ok": false, "why": "There is no such choice"}
	var o: Dictionary = opts[i]
	if bool(o.disabled):
		var why := String(o.why) if String(o.why) != "" else "Not now"
		toast(why, "warn")
		return {"ok": false, "why": why}
	var uid := String(open_entry().get("uid", ""))
	var r: Dictionary = scene.choose(uid, String(o.id)) if scene.has_method("choose") else {"ok": false, "why": "The road is not being driven"}
	refresh()
	return r


## A window with no room for the card's line of words under what hangs from the top (a short, narrow one): the title and the choices
## are the card, and the line is in the title's tooltip.
func _tight() -> bool:
	return root != null and root.size.x < WIDE_W and root.size.y < COMPACT_H


## A toast while a card is open is a line in the card (the card is where the eyes are, and a narrow window has no room for both).
func toast(text: String, level: String = "info") -> void:
	if event_panel == null or not event_panel.visible or text.strip_edges() == "":
		super.toast(text, level)
		return
	_note(text, level)


func _note(text: String, level: String) -> void:
	for eb in event_buttons:
		if not bool(eb.ok) and String(eb.why) == text:
			return    # (a refusal's reason is written on the card already)
	event_note.text = text
	event_note.add_theme_color_override("font_color", Hud.TOAST_COLOR.get(level, Hud.INK))
	event_note.visible = true
	if _note_tween != null:
		_note_tween.kill()
	_note_tween = create_tween() if is_inside_tree() else null
	if _note_tween != null:
		_note_tween.tween_interval(TOAST_HOLD)
		_note_tween.tween_callback(func():
			event_note.visible = false
			_layout())
	_layout()


func _update_event() -> void:
	var entry := open_entry() if _live() and _driving() else {}
	var opts: Array = event_options() if not entry.is_empty() else []
	if opts.is_empty():
		event_panel.visible = false
		event_note.visible = false
		event_uid = ""
		event_buttons.clear()
		_event_sig = ""
		return
	event_uid = String(entry.get("uid", ""))
	var def: Dictionary = entry.get("def", {})
	var sig := "%s|%s" % [event_uid, str(opts)]
	if sig != _event_sig:
		_event_sig = sig
		var kind := String(entry.get("kind", def.get("kind", "stop")))
		_event_edge = KIND_COLOR.get(kind, Hud.INFO)
		event_kind.text = String(KIND_WORD.get(kind, "Stop")).to_upper()
		event_kind.add_theme_color_override("font_color", _event_edge)
		event_title.text = String(def.get("title", entry.get("id", "")))
		event_text.text = String(def.get("text", ""))
		event_title.tooltip_text = event_text.text
		event_title.mouse_filter = Control.MOUSE_FILTER_PASS
		_rebuild_options(opts)
		event_panel.queue_redraw()
	event_text.visible = event_text.text != "" and not _tight()
	if not event_panel.visible:
		event_panel.visible = true
		# a toast that is up when the card opens moves into it
		if toast_panel.visible:
			toast_panel.visible = false
			if toast_tween != null:
				toast_tween.kill()
			_note(toast_label.text, "warn")
	_update_rings(entry)


func _rebuild_options(opts: Array) -> void:
	for c in event_rows.get_children():
		event_rows.remove_child(c)
		c.queue_free()
	event_buttons.clear()
	event_rows.columns = clampi(opts.size(), 1, 2)
	var i := 0
	for o in opts:
		var line: VBoxContainer = hud._vbox(1)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row: HBoxContainer = hud._hbox(6)
		row.add_child(hud._kbd(String(o.key)))
		var b: Button = RadioKit.small_button(hud, String(o.text), OPTION_H, 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		var ok: bool = not bool(o.disabled)
		b.disabled = not ok
		b.tooltip_text = ("" if String(o.text).length() < 15 else String(o.text)) if ok else (String(o.why) if String(o.why) != "" else "Not now")
		b.pressed.connect(press_option.bind(i))
		row.add_child(b)
		var ring = null
		if bool(o.auto):
			# the default's countdown sits inside its button, at the right end (the word 'default' stands in for it with no countdown)
			for state in ["normal", "hover", "pressed", "disabled"]:
				b.get_theme_stylebox(state).content_margin_right = AUTO_PAD
			ring = Ring.new()
			ring.font = Fonts.cond(700)
			ring.color = Hud.ACCENT
			ring.track = Color(0.93, 0.96, 0.89, 0.22)
			ring.ink = Hud.INK
			ring.anchor_left = 1.0
			ring.anchor_right = 1.0
			ring.anchor_top = 0.5
			ring.anchor_bottom = 0.5
			ring.offset_left = -32.0
			ring.offset_right = -6.0
			ring.offset_top = -13.0
			ring.offset_bottom = 13.0
			ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(ring)
			var tag: Label = hud._label("default", Fonts.sans(400), 12, Hud.INK3)
			tag.anchor_left = 1.0
			tag.anchor_right = 1.0
			tag.anchor_top = 0.5
			tag.anchor_bottom = 0.5
			tag.offset_left = -46.0
			tag.offset_right = -6.0
			tag.offset_top = -9.0
			tag.offset_bottom = 9.0
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			tag.visible = false
			b.add_child(tag)
			ring.set_meta("tag", tag)
		line.add_child(row)
		if not ok:
			var why: Label = hud._label(String(o.why) if String(o.why) != "" else "Not now", Fonts.sans(600), 12, Hud.WARN)
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.custom_minimum_size.x = 100
			line.add_child(why)
		event_rows.add_child(line)
		event_buttons.append({"id": String(o.id), "button": b, "ring": ring, "auto": bool(o.auto), "ok": ok, "why": String(o.why), "line": line})
		i += 1


## The countdown ring of the option taken by default: the seconds left over the seconds it began with (a card with no countdown
## shows the word "default" in its place).
func _update_rings(entry: Dictionary) -> void:
	if event_buttons.is_empty():
		return
	var left := _left_for(entry)
	var ttl := _ttl_for(entry)
	var has_default := false
	for eb in event_buttons:
		var ring = eb.ring
		if ring == null:
			continue
		has_default = true
		var tag: Label = ring.get_meta("tag")
		ring.visible = left >= 0.0
		tag.visible = left < 0.0
		if left >= 0.0:
			ring.frac = clampf(left / ttl, 0.0, 1.0)
			ring.text = str(ceili(left))
			ring.queue_redraw()
	# a card that takes no default only closes: the ring is in its head
	event_ring.visible = not has_default and left >= 0.0
	if event_ring.visible:
		event_ring.frac = clampf(left / ttl, 0.0, 1.0)
		event_ring.text = str(ceili(left))
		event_ring.queue_redraw()


## The seconds left of the open card (-1: none, or no countdown).
func event_left() -> float:
	var entry := open_entry()
	return _left_for(entry) if not entry.is_empty() else -1.0


# ------------------------------------------------------------------- the prompt --

func _build_prompt() -> void:
	prompt_panel = PanelContainer.new()
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st: StyleBox = hud._style(Hud.PANEL, 6, Hud.LINE2, true, "toast")
	if st is StyleBoxFlat:
		st.content_margin_left = 10
		st.content_margin_right = 14
		st.content_margin_top = 6
		st.content_margin_bottom = 7
	prompt_panel.add_theme_stylebox_override("panel", st)
	var row: HBoxContainer = hud._hbox(8)
	prompt_key = hud._kbd("E")
	row.add_child(prompt_key)
	prompt_label = hud._label("", Fonts.sans(600), 14, Hud.INK)
	prompt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(prompt_label)
	prompt_panel.add_child(row)
	prompt_panel.visible = false
	_put(prompt_panel)


## What E is for now: "E  Stop: someone is waving" within 40 tiles of a stop (a roadblock 25 tiles, and slow enough to clear), the
## squad's work at a stop, "E  Back in the car"; "" when there is nothing to say. A line with no "E" is only a word of warning.
func prompt_text() -> String:
	if not _live() or not _driving() or not open_entry().is_empty():
		return ""
	if _mode() == "out":
		var left := float(_g("work_left", 0.0))
		return "Working at the stop: %d s" % ceili(left) if left > 0.0 else "E  Back in the car"
	var best := {}
	var best_d := INF
	var road_len := _road_len()
	for e in _plan():
		var kind := String(e.get("kind", ""))
		if String(e.get("state", "")) != "pending" or (kind != "stop" and kind != "block"):
			continue
		var ahead := (float(e.get("at", 0.0)) - _progress()) * road_len
		if ahead < -2.0 or ahead > (BLOCK_REACH if kind == "block" else STOP_REACH) or ahead >= best_d:
			continue
		best = e
		best_d = ahead
	if best.is_empty():
		return ""
	var def: Dictionary = best.get("def", {})
	if String(best.kind) == "block":
		if not _has_car():
			return ""
		return "E  Roadblock: clear it" if absf(_speed()) < BLOCK_SLOW else "Roadblock ahead: thread the gap, or slow down to clear it"
	var phrase := String(def.get("prompt", STOP_PHRASE.get(String(best.get("id", "")), String(def.get("title", "something ahead")).to_lower())))
	return "E  Stop: %s" % phrase


func _update_prompt() -> void:
	var text := prompt_text()
	prompt_panel.visible = text != ""
	if text == "":
		return
	var keyed := text.begins_with("E  ")
	prompt_key.visible = keyed
	prompt_label.text = text.trim_prefix("E  ") if keyed else text


# ------------------------------------------------------------------ legend --

## The keys the legend shows: the road's in a car, on foot the place's own with E to stop, and the place's in the place.
func _legend_text() -> Array:
	if scene == null or not _driving():
		return super._legend_text()
	return CAR_LEGEND if _has_car() and _in_car() else FOOT_LEGEND


## The legend as one line of words ("W S gas and brake, A D steer, ..."), for the tests.
func legend_text() -> String:
	var parts: Array = []
	for entry in _legend_text():
		parts.append("%s %s" % [" ".join(PackedStringArray(entry[0])), entry[1]])
	return ", ".join(parts)


func _rebuild_legend() -> void:
	var box: Node = legend_panel.get_child(0)
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for entry in _legend_text():
		var item: HBoxContainer = hud._hbox(3)
		for key in entry[0]:
			item.add_child(hud._kbd(String(key)))
		var what: Label = hud._label(String(entry[1]), Fonts.sans(400), 12, Hud.INK2)
		what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(what)
		box.add_child(item)


# ------------------------------------------------------------------- the squad --

## Whether the squad's verbs are off the radio: they ride with you while you are aboard.
func _hide_for_drive() -> bool:
	return _driving() and _in_car()


## A click on a squad card while you drive says why nothing opens.
func pick_contact(kind: String, p) -> void:
	if kind == "squad" and _hide_for_drive():
		toast("You are driving: stop the car (E) to ask the squad something", "warn")
		return
	super.pick_contact(kind, p)


func _refresh_radio() -> void:
	super._refresh_radio()
	var aboard := _hide_for_drive()
	if aboard:
		back_button.disabled = true
		back_button.tooltip_text = "Everyone is in the car with you"
		contact_hint.text = "You are driving: the squad rides with you. Stop (E) to ask them something. The people at the base are a click away."
	else:
		back_button.tooltip_text = "Ask everyone with you to go back to the exit"
		contact_hint.text = "Click a card or a name to ask them something"


func _refresh_cards(run) -> void:
	super._refresh_cards(run)
	var lead = scene.leader()
	var aboard: Array = scene.aboard() if _driving() and scene.has_method("aboard") else []
	for c in cards:
		var p = c.p
		var inside: bool = aboard.has(p) and not p.downed and not p.dead
		if inside:
			var word := "Aboard"
			if p == lead:
				word = "Autopilot" if bool(_g("autopilot", false)) else "Driving"
			c.status.text = word
			c.status.add_theme_color_override("font_color", Hud.ACCENT if p == lead else Hud.INK2)
		if inside and p != lead:
			c.panel.tooltip_text = "%s, %s. You are driving: stop the car (E) to ask them something" % [p.name, String(p.def.role).to_lower()]
		else:
			c.panel.tooltip_text = "%s, %s. Click to ask them something over the radio" % [p.name, String(p.def.role).to_lower()]


func _refresh_place(run) -> void:
	super._refresh_place(run)
	if _driving() and not scene.ended:
		line_label.text = road_line()


## The line under the road's name: what to do.
func road_line() -> String:
	var home := _leg() == "home"
	var dest := "home" if home else place_phrase_of(place_name())
	# what matters now is the scene's to say (a card's real default, a friend who is down, the head home asked for, a wreck)
	if scene != null and scene.has_method("road_note"):
		var note := String(scene.road_note())
		if note != "":
			return note
	match _mode():
		"stopped":
			return "Choose, or drive on. The base goes on without you."
		"out":
			return "The squad is out at the stop. Everyone back in the car, and on."
		"foot":
			return "Walk home. The base goes on without you." if home else "Walk to %s. The base goes on without you." % dest
	if bool(_g("autopilot", false)):
		return "The squad is driving. Press W A S D to take the wheel."
	if home:
		return "Drive home. Fast and clean saves game time; crashes and stops cost it."
	return "Drive to %s. Fast and clean saves game time; crashes and stops cost it." % dest


static func place_phrase_of(place: String) -> String:
	return "the " + place.trim_prefix("The ") if place.begins_with("The ") else place


# ------------------------------------------------------------------- the stage --

## The stage on the screen changed (the road there, the place, the road home): the place's panel carries the stage's name, the squad's
## cards are made again for the squad that is on it, and the legend is the stage's.
func on_stage(leg: String, the_site: Dictionary) -> void:
	place_label.text = String(the_site.get("name", "The place"))
	_rebuild_cards()
	_legend_key = ""
	_event_sig = ""
	_log_seen = 0
	refresh()
	_layout()


## The squad's cards, made again when the squad on the stage is not the one they were made for.
func _rebuild_cards() -> void:
	var now := _squad_now()
	if now == _squad_seen and cards.size() == now.size():
		return
	for c in cards:
		cards_grid.remove_child(c.panel)
		c.panel.queue_free()
	cards.clear()
	var i := 0
	for p in now:
		cards.append(_make_card(p, i))
		cards_grid.add_child(cards[i].panel)
		i += 1
	_squad_seen = now


# ---------------------------------------------------------------------- refresh --

func refresh() -> void:
	if scene == null or scene.run == null or route_box == null:
		super.refresh()
		return
	_update_drive()
	super.refresh()


func _update_drive() -> void:
	var live := _live()
	var on := live and _driving()
	# the bags' corner is the road's while the road is driven
	bags_box.visible = not on
	route_box.visible = on
	if on:
		_update_route()
	# the ammunition's board carries the gauges (a car has them; on foot the road is all there is)
	var gauges := on and _has_car()
	var roomy := _dash_room() >= DASH_ROW_W
	_roomy = roomy
	dash.vertical = not roomy
	roomy_box.visible = gauges and roomy
	mini_box.visible = gauges and not roomy
	if gauges:
		_update_gauges()
	var key := "%s|%s" % [_leg(), str(_has_car() and _in_car())]
	if key != _legend_key:
		_legend_key = key
		_rebuild_legend()
	_update_event()
	_update_prompt()
	if _squad_now() != _squad_seen:
		_rebuild_cards()


func _process(delta: float) -> void:
	if dial == null or scene == null or not roomy_box.visible:
		return
	dial.step(delta)
	if event_panel.visible:
		var entry := open_entry()
		if not entry.is_empty():
			_update_rings(entry)


func _signature() -> String:
	var s := super._signature()
	if event_panel == null:
		return s
	return s + str([event_panel.visible, event_panel.get_combined_minimum_size(), prompt_panel.visible, prompt_panel.get_combined_minimum_size(), _roomy, route_box.visible])


# ---------------------------------------------------------------------- layout --

func _layout() -> void:
	# a short, narrow window has no room for a banner and a card: while a card is open the banner (up for three seconds) stands aside
	if banner != null and _banner_wanted:
		banner.visible = not (event_panel != null and event_panel.visible and _tight())
	super._layout()
	_layout_drive()
	_sig = _signature()


func show_banner(title: String, sub: String) -> void:
	_banner_wanted = true
	super.show_banner(title, sub)


func _banner_gone() -> void:
	_banner_wanted = false
	super._banner_gone()


## The event card (or the prompt) over the ammunition, the call card and the toast over it, in the column the base keeps for the foot
## (the middle of it in a wide window, the left column in a narrow one). The log and the legend of a narrow window are made room
## under the ceiling again.
func _layout_drive() -> void:
	if event_panel == null or root == null:
		return
	var w: float = root.size.x
	if w <= 0.0:
		return
	var wide := w >= WIDE_W
	var card: Control = event_panel if event_panel.visible else (prompt_panel if prompt_panel.visible else null)
	if card == null:
		return
	var left := PAD
	var right := _radio_x - GAP
	if wide:
		var bas := base_panel.get_combined_minimum_size()
		left = PAD + LOG_W + GAP
		right = w - PAD - bas.x - GAP
	var room := maxf(EVENT_W_MIN, right - left)
	var card_w := minf(EVENT_W, room)
	if card == event_panel:
		_fit_event(card_w)
	var cs: Vector2 = card.get_combined_minimum_size()
	var mid := (left + right) / 2.0
	var x := mid - cs.x / 2.0 if wide else left
	var up := weapon_panel.position.y - 6.0
	_place(card, Vector2(x, up - cs.y))
	up -= cs.y + 6.0
	if call_card.visible and not call_in_column:
		var cc: Vector2 = call_card.get_combined_minimum_size()
		_place(call_card, Vector2(mid - cc.x / 2.0 if wide else PAD, up - cc.y))
		up -= cc.y + 6.0
	if wide:
		if toast_panel.visible:
			var ts := toast_panel.get_combined_minimum_size()
			_place(toast_panel, Vector2(mid - ts.x / 2.0, up - ts.y))
		return
	# a narrow window: the log and the legend go where there is room under what hangs from the top
	var ceiling := _hang_bottom()
	for pair in [[log_panel, _log_wanted], [legend_panel, _legend_wanted]]:
		var panel: Control = pair[0]
		panel.visible = false
		if not bool(pair[1]):
			continue
		var s: Vector2 = panel.get_combined_minimum_size()
		if up - s.y >= ceiling:
			panel.visible = true
			_place(panel, Vector2(PAD, up - s.y))
			up -= s.y + 6.0


## Where what hangs from the top of a narrow window ends: the place's board, the cards, the banner and the toast, and a margin.
func _hang_bottom() -> float:
	var ceiling := PAD
	for c in [place_panel, cards_grid]:
		ceiling = maxf(ceiling, c.position.y + c.size.y)
	ceiling += 8.0
	for c in [banner, toast_panel]:
		if c.visible:
			ceiling = maxf(ceiling, c.position.y + c.size.y + 6.0)
	return ceiling


## The card as wide as the room lets it be: its lines wrap.
func _fit_event(card_w: float) -> void:
	var inner := card_w - event_panel.get_theme_stylebox("panel").get_minimum_size().x
	for l in [event_title, event_text, event_note]:
		l.custom_minimum_size.x = maxf(100.0, inner)
	event_panel.custom_minimum_size.x = card_w
	var cols := maxi(event_rows.columns, 1)
	var cell := (inner - 10.0 * float(cols - 1)) / float(cols)
	for eb in event_buttons:
		for c in eb.line.get_children():
			if c is Label:
				c.custom_minimum_size.x = maxf(80.0, cell - 4.0)


# ----------------------------------------------------------------- drawn parts --

## The road's bar: a groove, the share driven, a small tick for each event met, the car's mark over it and the place's flag at the end.
class RouteBar:
	extends Control
	const FLAG_W := 16.0
	var value := 0.0
	var ticks: Array = []
	var fill := Color("#f0c24a")
	var track := Color(0.93, 0.96, 0.89, 0.16)
	var ink := Color("#eeeadd")
	var flag := Color("#8fb85a")

	func _draw() -> void:
		var bw := size.x - FLAG_W
		var y := size.y - 9.0
		var v := clampf(value, 0.0, 1.0)
		draw_rect(Rect2(0, y, bw, 6), track)
		draw_rect(Rect2(0, y, bw * v, 6), fill)
		for t in ticks:
			var x := bw * clampf(float(t.at), 0.0, 1.0)
			draw_rect(Rect2(x - 2.0, y - 3.0, 4, 12), Color(0, 0, 0, 0.65))
			draw_rect(Rect2(x - 1.0, y - 2.0, 2, 10), t.color)
		var mx := bw * v
		draw_colored_polygon(PackedVector2Array([Vector2(mx - 5, 0), Vector2(mx + 5, 0), Vector2(mx, 8)]), ink)
		var fx := bw + 5.0
		draw_line(Vector2(fx, 1), Vector2(fx, size.y - 1), ink, 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(fx + 1, 1), Vector2(fx + 11, 5), Vector2(fx + 1, 9)]), flag)


## The speed dial: a 240 degree arc from the lower left over the top to the lower right, a mark at cruising speed, a red arc beyond
## it, the share of the top speed filled, the speed in the middle (the number eases to the speed a few times a frame).
class SpeedDial:
	extends Control
	var frac := 0.0
	var target := 0.0
	var cruise_frac := 0.667
	var number := "0"
	var color := Color("#8fb85a")
	var track := Color(0.93, 0.96, 0.89, 0.16)
	var fast_zone := Color(0.88, 0.35, 0.29, 0.7)
	var ink := Color("#eeeadd")
	var ink2 := Color("#c1c5b5")
	var font: Font
	var small_font: Font

	func step(dt: float) -> void:
		var was := frac
		frac += (target - frac) * (1.0 - exp(-12.0 * dt))
		if absf(frac - was) > 0.0005:
			queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x / 2.0, size.y * 0.55)
		var r := minf(size.x / 2.0, size.y * 0.52) - 4.0
		var a0 := deg_to_rad(150.0)
		var a1 := deg_to_rad(390.0)
		var ac := a0 + (a1 - a0) * clampf(cruise_frac, 0.0, 1.0)
		draw_arc(c, r, a0, ac, 40, track, 6.0, true)
		draw_arc(c, r, ac, a1, 20, fast_zone, 6.0, true)
		var f := clampf(frac, 0.0, 1.0)
		if f > 0.01:
			draw_arc(c, r, a0, a0 + (a1 - a0) * f, 48, color, 6.0, true)
		var d := Vector2.from_angle(ac)
		draw_line(c + d * (r - 7.0), c + d * (r + 5.0), ink, 2.0)
		if font != null:
			draw_string(font, Vector2(0, c.y + 6.0), number, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, ink)
		if small_font != null:
			draw_string(small_font, Vector2(0, c.y + 20.0), "km/h", HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, ink2)


## The countdown ring of the card: the seconds left as an arc, and the number in it.
class Ring:
	extends Control
	var frac := 1.0
	var text := ""
	var color := Color("#f0c24a")
	var track := Color(0.93, 0.96, 0.89, 0.22)
	var ink := Color("#eeeadd")
	var font: Font

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 2.0
		draw_arc(c, r, 0.0, TAU, 32, track, 3.0, true)
		if frac > 0.0:
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0), 32, color, 3.0, true)
		if font != null:
			draw_string(font, Vector2(0, c.y + 4.5), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, ink)
