## The events of the live road (round 21, slice 5, S21.1 EVENTS). A trip the player leads in avatar mode drives its road in a scene
## (scripts/drive/drive_scene.gd); this holds the RULES of what happens on it and draws and nodes nothing, so that the tests can run a
## whole road without a window. Everything here is pure and deterministic by seed (nothing draws from the colony's own random
## numbers) except `apply`, the only function that writes.
##
## THE DECK is assets/data/road_events.json (read from `data_path`): nine events and the ambient night road. `deck()` gives {id: def}.
##   def = {id, title, text, kind ("dead" | "stop" | "block" | "forced"), weight, hp_weight, legs, vehicle ("any" | "needs" | "foot"),
##          min_danger, band ("any" | "day" | "night"), needs [bed, seat, fuel_room], card ("always" | "vehicle" | "never"),
##          auto (a choice id), auto_else [choice ids], timeout ("auto" | "close"), ttl_s, choices [{id, label, needs, effects, lines, log,
##          maybe, one_of, gamble}]}.
##   `card` says whether the player is asked: "never" (an ambush, a herd: the dead come, there is no question: the scene calls
##   `resolve(entry, def.auto, ctx)` when the event fires and spawns `result.spawn`), "vehicle" (a roadblock: a card for the car; on foot
##   the squad climbs the pile-up and nothing is asked), "always". A card that is not answered takes the `auto` option after `ttl_s`
##   (`timeout` "auto") or just closes ("close").
##
## A LEG'S EVENTS: `plan(seed, ctx)` -> the entries sorted by `at` (see there). The scene works an entry through "pending" ->
## "open" -> "done" | "missed" by setting `entry.state` itself. `ambient_for(ctx)` the night road. `make_ctx(flow, leg)` builds the ctx
## from a `PlaceFlow` (the same function is for the card's refresh: stock and seats change on the way).
##
## THE CARD: `options(entry, ctx)` -> [{id, label, ok, why, auto}] (a refused option always says why; the one the card takes by
## itself is marked `auto`). `resolve(entry, choice_id, ctx)` -> {ok, choice, effects, lines, stop_s, spawn, log, why}, deterministic in
## (entry.seed, choice, ctx) and pure. `apply(effects, flow)` writes what the COLONY side of it is and returns the lines that tell it.
##
## WHO APPLIES WHAT (the contract with the scene and the flow). `apply` writes: stock (a find goes into `flow.road_loot`, it comes
## home with the party; a cost is paid from `sim.stock` at once, never below 0), fuel (`vehicles.add_fuel` / taken from the base tank,
## never below 0), vehicle_hp (the fleet's vehicle through `vehicles.road_wear`, which never goes below 1 and never wrecks it: the
## scene mirrors the same number on its car and the flow must not count it again), trust (`radio.add_trust` for those aboard), morale
## (`flow.road_morale` when the flow has it: people on the road are away, and `morale.shock` does not reach them; else
## `morale.shock`), survivor (`flow.road_survivors`, only with a seat and a bed), reveal ("near": the nearest place nobody knows
## becomes known). The SCENE applies what lives in the scene: `hp_all` and `hurt` (the squad's health and wounds in the run: `hurt`
## names who by `effects.pick`, a whole number `resolve` draws), `stop_s` (the squad gets out for that long: also `result.stop_s`),
## `dead` (what to spawn: also `result.spawn`) and `block_cleared` (the wrecks come away). The flow reads those from the run at the
## end of the leg: apply never writes them, so nothing is counted twice. The radio's line (`result.log`) is the scene's to log.
##
## The effect vocabulary (EFFECT_KEYS): stock, fuel, vehicle_hp, hp_all, hurt, trust, morale, survivor, reveal, stop_s, dead,
## block_cleared, and `pick` (a whole number `resolve` draws when there is a `hurt`: it points at the person of the party who is hurt).
extends RefCounted

const Demo := preload("res://scripts/demo.gd")
const DATA_PATH := "res://assets/data/road_events.json"
## Where the deck is read from (tests may point it at another file; `forget()` after changing it).
static var data_path := DATA_PATH
static var _cache := {}

const KINDS := ["dead", "stop", "block", "forced"]
const LEGS := ["there", "home"]
const STOCKS := ["food", "water", "scrap", "meds", "ammo"]
const EFFECT_KEYS := ["stock", "fuel", "vehicle_hp", "hp_all", "hurt", "trust", "morale", "survivor", "reveal", "stop_s", "dead", "block_cleared", "pick"]
## What `apply` leaves to the scene (the run's people and wounds, the squad's work, the dead to spawn, the wrecks).
const SCENE_KEYS := ["hp_all", "hurt", "stop_s", "dead", "block_cleared"]

## Where on the leg an event may be (the share of the road), the least between two, and how far a slot's centre may be moved.
const AT_MIN := 0.12
const AT_MAX := 0.9
const MIN_GAP := 0.12
const JITTER := 0.15
## One event for each this many real seconds of the leg (at cruise), at most MAX_EVENTS (one more from danger DANGER_MORE).
const SECONDS_PER_EVENT := 25.0
const MAX_EVENTS := 4
const MAX_EVENTS_DANGER := 5
const DANGER_MORE := 3
## The dead of an event grow by this much a point of the place's danger (their weight), and by this at night.
const DANGER_WEIGHT := 0.3
const NIGHT_DEAD_MULT := 1.5
## An id comes at most this often on a leg.
const MAX_SAME := 2
## The least room in the base's tank for a stash to be worth stopping for.
const FUEL_ROOM_MIN := 4.0
## A leg's real seconds at cruise: the road's game minutes (one a second), kept between these (place_flow.gd has the same two).
const LEG_MIN_S := 30.0
const LEG_MAX_S := 90.0
## What an hour is when the caller does not say: the dusk and the dawn.
const DEFAULT_DUSK := 18.0
const DEFAULT_DAWN := 6.0
## Three is the most on foot (place_flow.gd `MAX_ON_FOOT`).
const MAX_ON_FOOT := 3
const MAX_PICK := 1000


# ------------------------------------------------------------------------- data --

## The events of the deck as {id: def} (the defs are copies: the caller may do what it likes with them).
static func deck() -> Dictionary:
	return (_data().get("events", {}) as Dictionary).duplicate(true)


## The ambient def of this id ("night_road": its title, text, lines and log), or {}.
static func ambient_def(id: String) -> Dictionary:
	var d = _data().get("ambient", {}).get(id, {})
	return (d as Dictionary).duplicate(true) if d is Dictionary else {}


## Forgets what was read (a test that wrote another file at `data_path`).
static func forget() -> void:
	_cache.clear()


static func _data() -> Dictionary:
	if not _cache.has(data_path):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
		var events := {}
		var ambient := {}
		if raw is Dictionary:
			var listed = raw.get("events", {})
			if listed is Dictionary:
				for id in listed:
					if listed[id] is Dictionary:
						events[String(id)] = _normal_def(String(id), listed[id])
			var amb = raw.get("ambient", {})
			if amb is Dictionary:
				for id in amb:
					if amb[id] is Dictionary:
						ambient[String(id)] = _normal_ambient(amb[id])
		_cache[data_path] = {"events": events, "ambient": ambient}
	return _cache[data_path]


static func _strings(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for v in raw:
			out.append(String(v))
	return out


static func _normal_def(id: String, raw: Dictionary) -> Dictionary:
	var legs := _strings(raw.get("legs", LEGS))
	var def := {
		"id": id,
		"title": String(raw.get("title", "")),
		"text": String(raw.get("text", "")),
		"kind": String(raw.get("kind", "stop")),
		"weight": float(raw.get("weight", 1.0)),
		"hp_weight": bool(raw.get("hp_weight", false)),
		"legs": legs if not legs.is_empty() else LEGS.duplicate(),
		"vehicle": String(raw.get("vehicle", "any")),
		"min_danger": int(raw.get("min_danger", 0)),
		"band": String(raw.get("band", "any")),
		"needs": _strings(raw.get("needs", [])),
		"card": String(raw.get("card", "always")),
		"auto": String(raw.get("auto", "")),
		"auto_else": _strings(raw.get("auto_else", [])),
		"timeout": String(raw.get("timeout", "auto")),
		"ttl_s": float(raw.get("ttl_s", 8.0)),
		"choices": [],
	}
	var listed = raw.get("choices", [])
	if listed is Array:
		for c in listed:
			if c is Dictionary:
				def.choices.append(_normal_choice(c))
	return def


static func _normal_choice(raw: Dictionary) -> Dictionary:
	var choice := {
		"id": String(raw.get("id", "")),
		"label": String(raw.get("label", "")),
		"needs": _strings(raw.get("needs", [])),
		"effects": (raw.get("effects", {}) as Dictionary).duplicate(true) if raw.get("effects", {}) is Dictionary else {},
		"lines": _strings(raw.get("lines", [])),
		"log": _normal_log(raw.get("log", {})),
	}
	for key in ["maybe", "gamble"]:
		if raw.get(key) is Dictionary:
			choice[key] = (raw[key] as Dictionary).duplicate(true)
	if raw.get("one_of") is Array:
		choice["one_of"] = (raw.one_of as Array).duplicate(true)
	return choice


static func _normal_log(raw) -> Dictionary:
	if raw is Dictionary:
		return {"text": String(raw.get("text", "")), "sub": String(raw.get("sub", ""))}
	return {"text": "", "sub": ""}


static func _normal_ambient(raw: Dictionary) -> Dictionary:
	return {
		"title": String(raw.get("title", "")), "text": String(raw.get("text", "")),
		"dead_mult": float(raw.get("dead_mult", NIGHT_DEAD_MULT)), "runner_share": float(raw.get("runner_share", 0.0)),
		"headlights": bool(raw.get("headlights", true)), "lines": _strings(raw.get("lines", [])), "log": _normal_log(raw.get("log", {})),
	}


# ---------------------------------------------------------------------- context --

static func _room(raw) -> float:
	if typeof(raw) == TYPE_BOOL:
		return FUEL_ROOM_MIN if raw else 0.0    # (a caller that only knows whether the tank has room)
	return float(raw)


## What the functions below read of the world (every key optional; these are the defaults):
##   leg "there" | "home"; danger (the place's, 0 once cleared, + its nest); by_vehicle; seats_free; seats; vehicle_name; road_min (the
##   leg's game minutes); leg_s (its real seconds at cruise); hour (the base's hour when the leg starts); dusk; dawn; bed (a bed and a
##   caller: a survivor may be taken in); hp_share (the vehicle's health, 0 to 1); fuel_room (what the base's tank has room for, or just
##   whether it has some); stock {food, water, scrap, meds, ammo} (the base's now); leading and building (the best skill of those
##   aboard); caller (the next recruit's first name); fuel (the base's tank). A `flow` among them (the trip's `PlaceFlow`: the scene
##   keeps its own ctx and passes it) takes off the seats and the beds the survivors already taken in on this trip fill.
static func _ctx(raw: Dictionary) -> Dictionary:
	var road_min := float(raw.get("road_min", 60.0))
	var c := {
		"leg": String(raw.get("leg", "there")),
		"danger": int(raw.get("danger", 0)),
		"by_vehicle": bool(raw.get("by_vehicle", false)),
		"seats_free": int(raw.get("seats_free", 0)),
		"seats": int(raw.get("seats", 0)),
		"vehicle_name": String(raw.get("vehicle_name", "")),
		"road_min": road_min,
		"leg_s": float(raw.get("leg_s", clampf(road_min, LEG_MIN_S, LEG_MAX_S))),
		"hour": float(raw.get("hour", 9.0)),
		"dusk": float(raw.get("dusk", DEFAULT_DUSK)),
		"dawn": float(raw.get("dawn", DEFAULT_DAWN)),
		"bed": bool(raw.get("bed", false)),
		"hp_share": clampf(float(raw.get("hp_share", 1.0)), 0.0, 1.0),
		"fuel_room": _room(raw.get("fuel_room", 0.0)),
		"fuel": float(raw.get("fuel", 0.0)),
		"stock": raw.get("stock", {}) if raw.get("stock", {}) is Dictionary else {},
		"leading": int(raw.get("leading", 0)),
		"building": int(raw.get("building", 0)),
		"caller": String(raw.get("caller", "")),
		"only": _strings(raw.get("only", [])),
	}
	var flow = raw.get("flow")
	if flow is Object and "road_survivors" in flow and int(flow.road_survivors) > 0:
		var taken := int(flow.road_survivors)
		c["seats_free"] = maxi(0, int(c.seats_free) - taken)
		if bool(c.bed) and "sim" in flow and flow.sim != null:
			c["bed"] = int(flow.sim.recruits.housing_free()) - taken >= 1
	return c


## The ctx of a leg of a trip: from a `PlaceFlow` (or anything with its `sim`, `place_id`, `vehicle_id`, `going` and, when it has them,
## `vehicle_alive`, `road_lost`, `road_survivors`). Asks the base's recruits for the next caller only when there is a bed for them.
static func make_ctx(flow, leg: String = "there") -> Dictionary:
	var sim = flow.sim
	var place := String(flow.place_id)
	var vehicle := String(flow.vehicle_id)
	if "vehicle_alive" in flow and not bool(flow.vehicle_alive):
		vehicle = ""
	var kind: Dictionary = sim.vehicles.kind_of(vehicle) if vehicle != "" else {}
	if kind.is_empty():
		vehicle = ""
	var aboard := aboard_of(flow)
	var survivors := int(flow.road_survivors) if "road_survivors" in flow else 0
	var seats := int(kind.get("seats", MAX_ON_FOOT)) if vehicle != "" else MAX_ON_FOOT
	var road_min := float(sim.scavenge.road_minutes(place, vehicle))
	var danger := 0
	var state: String = sim.town.state_of(place)
	if state != "cleared" and state != "claimed":
		danger = int(sim.town.place(place).get("danger", 0)) + int(sim.town.nest_strength(place))
	var hp_share := 1.0
	if vehicle != "":
		hp_share = float(sim.vehicles.vehicle(vehicle).get("hp", 0.0)) / maxf(float(kind.get("hp", 80.0)), 1.0)
	var stock := {}
	for k in STOCKS:
		stock[k] = floori(float(sim.stock.get(k, 0.0)))
	var leading := 0
	var building := 0
	for p in aboard:
		leading = maxi(leading, int(p.skills.get("Leading", 0)))
		building = maxi(building, int(p.skills.get("Building", 0)))
	var bed := false
	var caller := ""
	if sim.recruits.small and int(sim.recruits.housing_free()) - survivors >= 1:
		var def: Dictionary = sim.recruits.caller_at(survivors)    # (the ones taken in so far are not met again)
		if not def.is_empty():
			bed = true
			caller = String(def.get("name", "")).split(" ")[0]
	return _ctx({
		"leg": leg, "danger": danger, "by_vehicle": vehicle != "", "seats_free": maxi(0, seats - aboard.size() - survivors),
		"seats": seats, "vehicle_name": String(kind.get("name", "")), "road_min": road_min, "hour": float(sim.hour),
		"dusk": float(sim.seasons.dusk_hour()), "dawn": float(sim.seasons.dawn_hour()), "bed": bed, "hp_share": hp_share,
		"fuel_room": maxf(0.0, float(sim.vehicles.FUEL_CAP) - float(sim.vehicles.fuel)), "fuel": float(sim.vehicles.fuel),
		"stock": stock, "leading": leading, "building": building, "caller": caller,
		"only": Demo.road_events() if sim.has_method("is_demo") and sim.is_demo() else [],    # (round 26: the demo has five kinds of event)
	})


## The people of the trip who are still aboard: alive, and not lost on the road.
static func aboard_of(flow) -> Array:
	var out: Array = []
	var lost: Array = flow.road_lost if "road_lost" in flow else []
	for p in flow.going:
		if p != null and not p.dead and not lost.has(String(p.id)):
			out.append(p)
	return out


# ------------------------------------------------------------------------- hours --

## Whether the hour of the day (any number: it is wrapped) is night: from dusk to dawn.
static func night_at(hour: float, dusk: float, dawn: float) -> bool:
	var h := fposmod(hour, 24.0)
	return h >= fposmod(dusk, 24.0) or h < fposmod(dawn, 24.0)


## The night road: [{"id": "night_road", "dead_mult", "runner_share", "headlights"}] when the leg starts after dusk (or before dawn), or
## crosses dusk on its way; [] for a leg that is all day.
static func ambient_for(ctx: Dictionary) -> Array:
	var c := _ctx(ctx)
	var span := float(c.road_min) / 60.0
	var start := float(c.hour)
	var night := night_at(start, float(c.dusk), float(c.dawn))
	if not night:
		for k in [-1, 0, 1, 2]:
			var d: float = fposmod(float(c.dusk), 24.0) + 24.0 * float(k)
			if d >= start and d <= start + span:
				night = true
	if not night:
		return []
	var amb := ambient_def("night_road")
	return [{"id": "night_road", "dead_mult": float(amb.get("dead_mult", NIGHT_DEAD_MULT)), "runner_share": float(amb.get("runner_share", 0.15)), "headlights": bool(amb.get("headlights", true))}]


# -------------------------------------------------------------------------- plan --

## A leg's events: [{"uid": "e1", "id", "kind", "at" (the share of the road, AT_MIN to AT_MAX), "seed", "night" (the slot is after
## dusk), "state": "pending", "def"}], sorted by `at`, at least MIN_GAP apart. n = leg_s / 25 seconds, 1 to 4 (one more at danger 3);
## each slot (i + 0.5 + jitter) / n of the road is filled with a def the leg's world allows (leg, vehicle, danger, the hour of the
## slot against dusk and dawn, a bed, a seat, room in the tank), by weight (the dead's grow with danger, a breakdown's with the car's
## wear), never the same id twice in a row nor more than twice on a leg. The random numbers are the seed's and the leg's own.
static func plan(seed: int, ctx: Dictionary) -> Array:
	var c := _ctx(ctx)
	var leg := String(c.leg)
	var n := clampi(roundi(float(c.leg_s) / SECONDS_PER_EVENT), 1, MAX_EVENTS)
	if int(c.danger) >= DANGER_MORE:
		n = mini(n + 1, MAX_EVENTS_DANGER)
	var rng := RandomNumberGenerator.new()
	var leg_id := 1 if leg == "there" else 2
	rng.seed = _mix(seed, leg_id)
	var ats: Array = []
	for i in n:
		var jitter := rng.randf_range(-JITTER, JITTER)
		var at := AT_MIN + (AT_MAX - AT_MIN) * (float(i) + 0.5 + jitter) / float(n)
		if i > 0:
			at = maxf(at, float(ats[i - 1]) + MIN_GAP)
		ats.append(minf(at, AT_MAX))
	var all := deck()
	var ids: Array = all.keys()
	ids.sort()
	if not (c.only as Array).is_empty():
		ids = ids.filter(func(id): return (c.only as Array).has(String(id)))    # (the demo's short deck: `ctx.only`)
	var out: Array = []
	var count := {}
	var previous := ""
	for i in n:
		var at: float = ats[i]
		var night := night_at(float(c.hour) + at * float(c.road_min) / 60.0, float(c.dusk), float(c.dawn))
		var fits: Array = []
		for id in ids:
			if _fits(all[id], c, night):
				fits.append(String(id))
		var open: Array = fits.filter(func(id): return int(count.get(id, 0)) < MAX_SAME and id != previous)
		if open.is_empty():
			open = fits.filter(func(id): return int(count.get(id, 0)) < MAX_SAME)
		if open.is_empty():
			continue
		var weights: Array = []
		var total := 0.0
		for id in open:
			var w := _weight(all[id], c)
			weights.append(w)
			total += w
		var roll := rng.randf() * total
		var pick := String(open[open.size() - 1])
		for j in open.size():
			roll -= float(weights[j])
			if roll < 0.0:
				pick = String(open[j])
				break
		count[pick] = int(count.get(pick, 0)) + 1
		previous = pick
		out.append({
			"uid": "e%d" % (out.size() + 1), "id": pick, "kind": String(all[pick].kind), "at": at, "seed": _mix(seed, leg_id * 100 + i + 1),
			"night": night, "state": "pending", "def": (all[pick] as Dictionary).duplicate(true),
		})
	return out


## Whether a def may come at a slot of this leg (the slot's `night`).
static func _fits(def: Dictionary, c: Dictionary, night: bool) -> bool:
	if not (def.legs as Array).has(String(c.leg)):
		return false
	match String(def.vehicle):
		"needs":
			if not bool(c.by_vehicle):
				return false
		"foot":
			if bool(c.by_vehicle):
				return false
	if int(c.danger) < int(def.min_danger):
		return false
	match String(def.band):
		"day":
			if night:
				return false
		"night":
			if not night:
				return false
	for need in def.needs:
		match String(need):
			"bed":
				if not bool(c.bed):
					return false
			"seat":
				if int(c.seats_free) < 1:
					return false
			"fuel_room":
				if float(c.fuel_room) < FUEL_ROOM_MIN:
					return false
			"vehicle":
				if not bool(c.by_vehicle):
					return false
	return true


static func _weight(def: Dictionary, c: Dictionary) -> float:
	var w := float(def.weight)
	if String(def.kind) == "dead":
		w *= 1.0 + DANGER_WEIGHT * float(c.danger)
	if bool(def.get("hp_weight", false)):
		w *= maxf(0.1, 1.8 - float(c.hp_share))
	return maxf(w, 0.0)


## A whole number from two (a seed and a salt): the same two give the same, anywhere.
static func _mix(a: int, b: int) -> int:
	var x: int = (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	x = (x ^ (x >> 15)) * 0x2c1b3c6d
	x = (x ^ (x >> 12)) * 0x297a2d39
	x = x ^ (x >> 15)
	return x & 0x7fffffff


# ------------------------------------------------------------------------ options --

## The card of an entry: [{"id", "label", "ok", "why" (non-empty when not ok), "auto"}] for each choice, in the def's order; [] when
## nothing is asked (a def with `card` "never", or "vehicle" and the squad on foot). `auto` marks the one the card takes by itself
## (the def's `auto`, else the first of its `auto_else` that is not refused) when the card times out; none when it just closes.
static func options(entry: Dictionary, ctx: Dictionary) -> Array:
	var def: Dictionary = entry.get("def", {})
	var c := _ctx(ctx)
	var card := String(def.get("card", "always"))
	if def.is_empty() or card == "never" or (card == "vehicle" and not bool(c.by_vehicle)):
		return []
	var out: Array = []
	var by_id := {}
	for choice in def.choices:
		var o := _check(choice.get("needs", []), c)
		var e := {"id": String(choice.id), "label": String(choice.label), "ok": bool(o.ok), "why": String(o.why), "auto": false}
		out.append(e)
		by_id[String(choice.id)] = e
	if String(def.get("timeout", "auto")) == "auto":
		for id in [String(def.get("auto", ""))] + (def.get("auto_else", []) as Array):
			if by_id.has(id) and bool(by_id[id].ok):
				by_id[id]["auto"] = true
				break
	return out


## {"ok", "why"}: whether the needs are met (a need is "seat", "bed", "vehicle", "fuel_room", "stock:<name>:<n>" or "toll:<n>").
static func _check(needs, c: Dictionary) -> Dictionary:
	for need in needs:
		var why := _unmet(String(need), c)
		if why != "":
			return {"ok": false, "why": why}
	return {"ok": true, "why": ""}


static func _unmet(need: String, c: Dictionary) -> String:
	var parts := need.split(":")
	var stock: Dictionary = c.stock
	match String(parts[0]):
		"seat":
			if int(c.seats_free) >= 1:
				return ""
			if not bool(c.by_vehicle):
				return "No room: three is the most on foot"
			if String(c.vehicle_name) != "" and int(c.seats) > 0:
				return "No seat free: the %s seats %d" % [String(c.vehicle_name).to_lower(), int(c.seats)]
			return "No seat free"
		"bed":
			return "" if bool(c.bed) else "There is no bed free for them at the base"
		"vehicle":
			return "" if bool(c.by_vehicle) else "You are on foot"
		"fuel_room":
			return "" if float(c.fuel_room) >= FUEL_ROOM_MIN else "The base's tank is full"    # (the same room the stash is planned for)
		"stock":
			var name := String(parts[1]) if parts.size() > 1 else "scrap"
			var need_n := int(parts[2]) if parts.size() > 2 else 1
			var have := int(stock.get(name, 0))
			if have >= need_n:
				return ""
			if have <= 0:
				return "You have no %s to trade" % name
			return "You have only %d %s: a trade takes %d" % [have, name, need_n]
		"toll":
			var toll := int(parts[1]) if parts.size() > 1 else 10
			var most := 0
			for k in ["food", "scrap", "ammo"]:
				most = maxi(most, int(stock.get(k, 0)))
			if most >= toll:
				return ""
			if most <= 0:
				return "You have nothing to pay with: a toll is %d of food, scrap or ammo" % toll
			return "You have too little to pay: a toll is %d of food, scrap or ammo" % toll
	return ""


# ------------------------------------------------------------------------ resolve --

static func _choice_of(def: Dictionary, id: String) -> Dictionary:
	for c in def.get("choices", []):
		if String(c.id) == id:
			return c
	return {}


## What the choice does: {"ok", "choice", "effects" (resolved: whole numbers, see the vocabulary), "lines" (what the squad says: at
## most two), "stop_s" (the squad's work, seconds), "spawn" (the dead to spawn: {walker, runner, brute, where, state}, or {}), "log"
## ({"kind": "road", "text", "sub"}: the radio's line), "why"}. A choice that does not exist or is refused is not ok: nothing in it but
## `why` (and the line that says so). Deterministic in (entry.seed, the choice, ctx) and pure: the same inputs give the same result.
static func resolve(entry: Dictionary, choice_id: String, ctx: Dictionary) -> Dictionary:
	var def: Dictionary = entry.get("def", {})
	var choice := _choice_of(def, choice_id)
	if choice.is_empty():
		return _refused("There is no such choice")
	var c := _ctx(ctx)
	var met := _check(choice.get("needs", []), c)
	if not bool(met.ok):
		return _refused(String(met.why))
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix(int(entry.get("seed", 0)), choice_id.hash())
	var effects := _effects(choice.get("effects", {}), c, rng)
	var lines: Array = (choice.get("lines", []) as Array).duplicate()
	var log: Dictionary = (choice.get("log", {}) as Dictionary).duplicate()
	var maybe = choice.get("maybe")
	if maybe is Dictionary:
		if rng.randf() < float(maybe.get("chance", 0.0)):
			_merge(effects, _effects(maybe.get("effects", {}), c, rng))
			lines.append_array(_strings(maybe.get("lines", [])))
	var one_of = choice.get("one_of")
	if one_of is Array and not one_of.is_empty():
		var feasible: Array = []
		for o in one_of:
			if bool(_check(o.get("needs", []), c).ok):
				feasible.append(o)
		var drawn := rng.randi()
		if not feasible.is_empty():
			var o: Dictionary = feasible[drawn % feasible.size()]
			_merge(effects, _effects(o.get("effects", {}), c, rng))
			if not _strings(o.get("lines", [])).is_empty():
				lines = _strings(o.lines)
			if o.get("log") is Dictionary:
				log = _normal_log(o.log)
	var gamble = choice.get("gamble")
	if gamble is Dictionary:
		var chance := clampf(float(gamble.get("base", 0.0)) + float(gamble.get("per", 0.0)) * float(c.get(String(gamble.get("skill", "")), 0)), 0.0, float(gamble.get("cap", 0.95)))
		var branch: Dictionary = gamble.get("win", {}) if rng.randf() < chance else gamble.get("lose", {})
		_merge(effects, _effects(branch.get("effects", {}), c, rng))
		if not _strings(branch.get("lines", [])).is_empty():
			lines = _strings(branch.lines)
		if branch.get("log") is Dictionary:
			log = _normal_log(branch.log)
	if bool(entry.get("night", false)) and effects.has("dead"):
		for k in ["walker", "runner", "brute"]:
			effects.dead[k] = roundi(float(effects.dead.get(k, 0)) * NIGHT_DEAD_MULT)
	if effects.has("hurt"):
		effects["pick"] = rng.randi() % MAX_PICK
	var said := _pick_lines(lines, rng, 2)
	var vars := _words(effects, c)
	for i in said.size():
		said[i] = _fill(String(said[i]), vars)
	return {
		"ok": true, "choice": choice_id, "effects": effects, "lines": said, "stop_s": float(effects.get("stop_s", 0.0)),
		"spawn": (effects.dead as Dictionary).duplicate() if effects.has("dead") else {},
		"log": {"kind": "road", "text": _fill(String(log.get("text", "")), vars), "sub": _fill(String(log.get("sub", "")), vars)}, "why": "",
	}


static func _refused(why: String) -> Dictionary:
	return {"ok": false, "choice": "", "effects": {}, "lines": [why], "stop_s": 0.0, "spawn": {}, "log": {}, "why": why}


## At most `most` of the lines, in their order (which ones: the seed's).
static func _pick_lines(lines: Array, rng: RandomNumberGenerator, most: int) -> Array:
	if lines.size() <= most:
		return lines.duplicate()
	var idx: Array = range(lines.size())
	for i in range(idx.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = idx[i]
		idx[i] = idx[j]
		idx[j] = t
	var keep: Array = idx.slice(0, most)
	keep.sort()
	var out: Array = []
	for i in keep:
		out.append(lines[i])
	return out


## The raw effects of a choice made into whole numbers by the dice (`rng`) and the leg's world (`c`).
static func _effects(raw, c: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key in raw:
		match String(key):
			"stock":
				out["stock"] = _stock_of(raw.stock, c, rng)
			"fuel", "vehicle_hp", "hp_all", "trust", "morale", "survivor", "block_cleared":
				out[String(key)] = _number(raw[key], rng)
			"hurt", "reveal":
				out[String(key)] = String(raw[key])
			"stop_s":
				out["stop_s"] = _seconds(raw.stop_s, c, rng)
			"dead":
				out["dead"] = _dead_of(raw.dead, int(c.danger), rng)
	return out


## A number or a [low, high] (both included): a whole number when it is whole.
static func _number(raw, rng: RandomNumberGenerator):
	if raw is Array and raw.size() >= 2:
		if is_equal_approx(float(raw[0]), roundf(float(raw[0]))) and is_equal_approx(float(raw[1]), roundf(float(raw[1]))):
			return rng.randi_range(int(raw[0]), int(raw[1]))
		return rng.randf_range(float(raw[0]), float(raw[1]))
	var v := float(raw)
	return int(v) if is_equal_approx(v, roundf(v)) else v


static func _seconds(raw, c: Dictionary, rng: RandomNumberGenerator) -> float:
	if raw is Dictionary:
		var skill := float(c.get(String(raw.get("skill", "")), 0))
		return maxf(float(raw.get("min", 0.0)), float(raw.get("base", 0.0)) - float(raw.get("per", 0.0)) * skill)
	return float(_number(raw, rng))


static func _dead_of(raw, danger: int, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"walker": 0, "runner": 0, "brute": 0, "where": String(raw.get("where", "ahead")), "state": String(raw.get("state", "hunt"))}
	for k in ["walker", "runner", "brute"]:
		var spec = raw.get(k)
		var drawn := 0
		if spec is Array and spec.size() >= 2:
			drawn = rng.randi_range(int(spec[0]), int(spec[1]))
		var from := int((raw.get("from", {}) as Dictionary).get(k, 0))
		if spec != null and danger >= from:
			out[k] = drawn + roundi(float((raw.get("grow", {}) as Dictionary).get(k, 0.0)) * float(danger))
	return out


static func _stock_of(raw, c: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	var have: Dictionary = c.stock
	for key in raw:
		var k := String(key)
		if k == "two_of":
			var from: Array = _strings(raw.two_of.get("from", STOCKS))
			for i in range(from.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t = from[i]
				from[i] = from[j]
				from[j] = t
			var each := int(raw.two_of.get("base", 0)) + int(raw.two_of.get("per_danger", 0)) * int(c.danger)
			for name in from.slice(0, 2):
				out[name] = int(out.get(name, 0)) + each
		elif k == "toll":
			var cost := int(raw.toll.get("n", 10)) * int(raw.toll.get("mult", 1))
			var from: Array = _strings(raw.toll.get("from", ["food", "scrap", "ammo"]))
			var can: Array = from.filter(func(s): return int(have.get(s, 0)) >= cost)
			var name := ""
			if not can.is_empty():
				name = String(can[rng.randi() % can.size()])
			else:
				var most := -1
				for f in from:
					if int(have.get(f, 0)) > most:
						most = int(have.get(f, 0))
						name = String(f)
				rng.randi()
			if name != "":
				out[name] = int(out.get(name, 0)) - cost
		elif STOCKS.has(k):
			out[k] = int(out.get(k, 0)) + int(_number(raw[key], rng))
	return out


## `extra` (resolved effects) added to `effects`: counts and amounts add, words are replaced.
static func _merge(effects: Dictionary, extra: Dictionary) -> void:
	for key in extra:
		if not effects.has(key):
			effects[key] = (extra[key] as Dictionary).duplicate(true) if extra[key] is Dictionary else extra[key]
		elif key == "stock":
			for k in extra.stock:
				effects.stock[k] = int(effects.stock.get(k, 0)) + int(extra.stock[k])
		elif key == "dead":
			for k in ["walker", "runner", "brute"]:
				effects.dead[k] = int(effects.dead.get(k, 0)) + int(extra.dead.get(k, 0))
		elif extra[key] is String:
			effects[key] = extra[key]
		else:
			effects[key] = effects[key] + extra[key]


## The words a line may use: {n} the dead, {loot}, {fuel}, {who}, {paid}, {secs}.
static func _words(effects: Dictionary, c: Dictionary) -> Dictionary:
	var dead: Dictionary = effects.get("dead", {})
	var found: Array = []
	var paid: Array = []
	var stock: Dictionary = effects.get("stock", {})
	for k in STOCKS:
		if int(stock.get(k, 0)) > 0:
			found.append("%d %s" % [int(stock[k]), "med" if k == "meds" and int(stock[k]) == 1 else k])
		elif int(stock.get(k, 0)) < 0:
			paid.append("%d %s" % [-int(stock[k]), k])
	return {
		"n": str(int(dead.get("walker", 0)) + int(dead.get("runner", 0)) + int(dead.get("brute", 0))),
		"loot": _join(found) if not found.is_empty() else "nothing",
		"fuel": str(maxi(int(effects.get("fuel", 0)), 0)),
		"who": String(c.caller) if String(c.caller) != "" else "The stranger",
		"paid": _join(paid) if not paid.is_empty() else "nothing",
		"secs": str(roundi(float(effects.get("stop_s", 0.0)))),
	}


static func _join(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]


static func _fill(text: String, vars: Dictionary) -> String:
	var out := text
	for k in vars:
		out = out.replace("{%s}" % k, String(vars[k]))
	return out


# -------------------------------------------------------------------------- apply --

## Writes the colony's side of resolved effects (see the header: what the scene does itself is left alone) into `flow` (a
## `PlaceFlow`, or anything with `sim`, `going`, `place_id`, `vehicle_id`, `road_loot`, `road_lost`, `road_survivors` and
## optionally `vehicle_alive`, `road_morale`) and returns the lines that tell what it did ("Paid 10 scrap", "Siphoned 6 fuel").
## Never takes stock or fuel below 0, never takes a survivor in without a seat and a bed, draws nothing from the colony's random numbers.
static func apply(effects: Dictionary, flow) -> Array:
	var told: Array = []
	var sim = flow.sim
	var aboard := aboard_of(flow)
	var stock = effects.get("stock", {})
	if stock is Dictionary:
		for k in STOCKS:
			var n := int(stock.get(k, 0))
			if n > 0:
				flow.road_loot[k] = int(flow.road_loot.get(k, 0)) + n
				told.append("Found %d %s." % [n, k])
			elif n < 0:
				var paid := minf(float(-n), maxf(0.0, float(sim.stock.get(k, 0.0))))
				sim.stock[k] = maxf(0.0, float(sim.stock.get(k, 0.0)) - paid)
				if paid > 0.0:
					told.append("Paid %d %s." % [roundi(paid), k])
				else:
					told.append("There was no %s to pay with." % k)
	var fuel := float(effects.get("fuel", 0.0))
	if fuel > 0.0:
		var put := float(sim.vehicles.add_fuel(fuel))
		told.append("The base's tank took %d fuel." % roundi(put) if put + 0.0001 >= fuel else "The base's tank took %d of the %d fuel." % [roundi(put), roundi(fuel)])
	elif fuel < 0.0:
		var lost := minf(-fuel, maxf(0.0, float(sim.vehicles.fuel)))
		sim.vehicles.fuel = maxf(0.0, float(sim.vehicles.fuel) - lost)
		told.append("Lost %d fuel." % roundi(lost))
	var wear := float(effects.get("vehicle_hp", 0.0))
	if wear != 0.0 and String(flow.vehicle_id) != "" and (not ("vehicle_alive" in flow) or bool(flow.vehicle_alive)):
		told.append_array(_wear(sim, String(flow.vehicle_id), wear))
	var trust := float(effects.get("trust", 0.0))
	if trust != 0.0:
		for p in aboard:
			sim.radio.add_trust(p, trust, "What you chose on the road")
	var morale := float(effects.get("morale", 0.0))
	if morale != 0.0:
		if "road_morale" in flow:
			flow.road_morale += morale
		else:
			for p in aboard:
				sim.morale.shock(p, morale, "On the road")
	if int(effects.get("survivor", 0)) > 0:
		told.append_array(_take_in(flow, aboard))
	if String(effects.get("reveal", "")) == "near":
		var shown := _reveal_near(sim, String(flow.place_id))
		if shown != "":
			told.append("%s is on the map now." % shown)
	return told


## The vehicle takes a knock (negative) or is mended (positive): never below 1 hp, never above its kind's, and never wrecked here.
static func _wear(sim, vehicle_id: String, hp: float) -> Array:
	var v: Dictionary = sim.vehicles.vehicle(vehicle_id)
	if v.is_empty():
		return []
	var name := String(sim.vehicles.kind_of(vehicle_id).get("name", "car")).to_lower()
	if hp < 0.0:
		sim.vehicles.road_wear(vehicle_id, -hp)
		return ["The %s took a knock." % name]
	v["hp"] = minf(float(sim.vehicles.kind_of(vehicle_id).get("hp", 100.0)), float(v.hp) + hp)
	return ["The %s was patched up." % name]


## A survivor taken in: only with a seat (those aboard and those taken in so far fill them) and a bed at the base.
static func _take_in(flow, aboard: Array) -> Array:
	var sim = flow.sim
	var taken := int(flow.road_survivors)
	var kind: Dictionary = sim.vehicles.kind_of(String(flow.vehicle_id)) if String(flow.vehicle_id) != "" and (not ("vehicle_alive" in flow) or bool(flow.vehicle_alive)) else {}
	var seats := int(kind.get("seats", MAX_ON_FOOT)) if not kind.is_empty() else MAX_ON_FOOT
	if aboard.size() + taken >= seats:
		return ["There is no seat for them: they stay on the road."]
	if not sim.recruits.small or int(sim.recruits.housing_free()) - taken < 1 or sim.recruits.caller_at(taken).is_empty():
		return ["There is no bed for them at the base: they stay on the road."]
	flow.road_survivors = taken + 1
	return ["A survivor is aboard."]


## The nearest place nobody knows of becomes known (as the dice's beats do it); its name, or "".
static func _reveal_near(sim, place_id: String) -> String:
	var here: Vector2 = sim.town.place(place_id).get("pos", Vector2.ZERO)
	var best := ""
	var best_d := 1.0e9
	for q in sim.town.places:
		var qid := String(q.id)
		if sim.town.state_of(qid) == "unknown":
			var d: float = Vector2(q.pos).distance_to(here)
			if d < best_d:
				best_d = d
				best = qid
	if best == "":
		return ""
	sim.town.reveal(best)
	return String(sim.town.place(best).get("name", best))
