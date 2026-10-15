## EXPERIMENT (prison raids, step 4a): LOOT BY PLACE, the raid's marks and the gate's choice.
## Pattern: a seeded POST-PASS over the town the generator made (the generator is not touched): every building gets a place type (natural map from its kind, then a stable-hash retag so a raid
## town always has its minimum of pharmacies, hardware stores, garages, petrol stations and police posts), and every container's loot is re-rolled from the type's table with a RandomNumberGenerator
## seeded by (town seed, container index). The numbers are assets/data/prison_raids.json. Items: parts and fuel are ordinary backpack items (items.json parts_box, fuel_can; the grid, loot window, bank
## and stash carry them as the stock units `parts` and `fuel`), so the pack's 32 cells are the choice. The inventory pattern is the existing data-driven grid (items.json + scripts/sim/inventory.gd),
## not a Resource per item: the pack already is one.
## Owned by prison_game.gd (`loot`, `# RAIDS hook`). `--loot-lab=N` prints the distribution (see `lab`).
extends RefCounted

const Bal := preload("res://scripts/prison/prison_bal.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")
const DestMap := preload("res://scripts/prison/prison_destmap.gd")
const PATH := "res://assets/data/prison_raids.json"
const TILE := 64.0

static var _cfg := {}

var game
var places: Array = []    # [{house, type, pos (Vector2, tiles), n (containers)}]
var target: Array = []    # place types marked on the map
var option := 0
var picked := -1    # the gate's choice, used by the next raid    # the chosen option of cfg.options
var choosing := false
var kind := ""    # the kind of town of this raid ("" = today's town)
const RAID_MOD_KIND := {"watchers": "police"}    # event word -> town kind
var force_kind := ""    # ARC hook: an event card's raid_mod sets this to force the next raid's kind (used once; "" = free choice)
var picked_kind := ""    # the place (id in cfg.places) chosen at the gate
var dest    # the destination map (prison_destmap.gd)


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if parsed is Dictionary else {}
	return _cfg


func _init(g = null) -> void:
	game = g


# ------------------------------------------------------------------ the town kinds --

## The data of a kind or a place ({} for "" or an unknown id: today's town). A place id gives its town kind's data with the place's own keys laid over it (`places` in the data).
static func kind_cfg(k: String) -> Dictionary:
	var pc := place_cfg(k)
	if not pc.is_empty():
		var out := raw_kind(String(pc.get("kind", ""))).duplicate()
		for key in PLACE_KEYS:
			if pc.has(key):
				out[key] = pc[key]
		out["dead_mult"] = float(pc.get("dead_mult", 1.0))
		return out
	return raw_kind(k)


const PLACE_KEYS := ["tint", "spawn", "noise_mult", "alarm_open", "survivor", "answers", "natural", "min_places", "rolls", "hints", "retag_order", "layout"]


static func raw_kind(k: String) -> Dictionary:
	var tk = cfg().get("town_kinds", {})
	return (tk[k] as Dictionary) if tk is Dictionary and k != "" and tk.has(k) and tk[k] is Dictionary else {}


## A place of the destination map ({} when `k` is not one).
static func place_cfg(k: String) -> Dictionary:
	var pl = cfg().get("places", {})
	return (pl[k] as Dictionary) if pl is Dictionary and k != "" and pl.has(k) and pl[k] is Dictionary else {}


## The ids of the places in map order.
static func place_ids() -> Array:
	var out: Array = []
	for k in cfg().get("places", {}):
		if not String(k).begins_with("_"):
			out.append(String(k))
	return out


## The place an id of a town kind or a place stands for ("" when none): an event's raid_mod names a kind.
static func place_for(k: String) -> String:
	if not place_cfg(k).is_empty():
		return k
	for id in place_ids():
		if String(place_cfg(id).get("kind", "")) == k:
			return id
	return ""


## The base tables with the kind's laid over them: {natural, min_places, rolls, hints, retag_order}.
static func eff(k: String) -> Dictionary:
	var c := cfg()
	var kc := kind_cfg(k)
	var out := {}
	for key in ["natural", "min_places", "rolls", "hints"]:
		var d: Dictionary = (c.get(key, {}) as Dictionary).duplicate()
		d.merge(kc.get(key, {}), true)
		out[key] = d
	out["retag_order"] = kc.get("retag_order", c.retag_order)
	return out


## The places on the map that are open on a day (ids).
static func offer(day: int) -> Array:
	return place_ids().filter(func(id): return day >= int(place_cfg(id).get("unlock_day", 1)))


## The survivor table of this raid (the base with the kind's changes).
func survivor_cfg() -> Dictionary:
	var sv: Dictionary = (cfg().survivor as Dictionary).duplicate()
	sv.merge(kind_cfg(kind).get("survivor", {}), true)
	return sv


func noise_mult() -> float:
	return float(kind_cfg(kind).get("noise_mult", 1.0))


func alarm_open(def: float) -> float:
	return float(kind_cfg(kind).get("alarm_open", def))


# ------------------------------------------------------------------ the post-pass --

static func _h(a: int, b: int) -> int:
	return ((a * 73856093) ^ (b * 19349663)) & 0x7fffffff


## Retags the buildings and re-rolls the containers' loot of a town. Returns the places [{house, type, pos, n}] (a building, or one ROOM of a building when the town has too few buildings for the minimums).
static func prepare(t: Dictionary, seed_i: int, k := "") -> Array:
	var c := eff(k)
	var natural: Dictionary = c.natural
	var by_house := {}    # house id -> container indexes
	for ci in t.containers.size():
		var hid := int(t.containers[ci].house)
		if not by_house.has(hid):
			by_house[hid] = []
		(by_house[hid] as Array).append(ci)
	var type_of := {}    # house id -> type
	var room_type := {}    # room index -> type (a room that is a place of its own)
	var start_id := int(t.start.house)
	for h in t.houses:
		var hid := int(h.id)
		if by_house.has(hid) and bool(h.get("main", true)):
			type_of[hid] = String(natural.get(String(h.kind), "house"))
	for ty in c.retag_order:
		var have := _count(type_of, room_type, ty)
		while have < int(c.min_places.get(ty, 0)):
			var pool: Array = []
			for hid in type_of:
				var cur := String(type_of[hid])
				if int(hid) != start_id and cur != ty and _count(type_of, room_type, cur) > int(c.min_places.get(cur, 0)):    # (a type above its minimum gives one building up)
					pool.append(int(hid))
			if not pool.is_empty():
				pool.sort_custom(func(a, b): return _h(seed_i, a) < _h(seed_i, b))
				type_of[pool[0]] = ty
			else:    # too few buildings: a room of the building with most containers becomes the place
				var rooms: Array = []
				for hid in type_of:
					for ci in by_house[hid]:
						var rm := int(t.containers[ci].room)
						if not room_type.has(rm) and not rooms.has(rm):
							rooms.append(rm)
				if rooms.size() < 2:
					break
				rooms.sort_custom(func(a, b): return _h(seed_i, a + 977) < _h(seed_i, b + 977))
				room_type[rooms[0]] = ty
			have += 1
	var out: Array = []
	for h in t.houses:
		var hid := int(h.id)
		if type_of.has(hid):
			var n := 0
			for ci in by_house[hid]:
				if not room_type.has(int(t.containers[ci].room)):
					n += 1
			if n > 0:
				out.append({"house": hid, "type": String(type_of[hid]), "pos": Rect2(h.rect).get_center(), "n": n, "door": Vector2(Vector2i(h.door)) + Vector2(0.5, 0.5)})
	for rm in room_type:
		out.append({"house": -1, "room": int(rm), "type": String(room_type[rm]), "pos": Rect2(t.rooms[int(rm)].rect).get_center(), "n": 1, "door": _room_door(t, int(rm))})
	for ci in t.containers.size():
		var ct: Dictionary = t.containers[ci]
		var rng := RandomNumberGenerator.new()
		rng.seed = _h(seed_i, ci + 1)
		var ty := String(room_type.get(int(ct.room), type_of.get(int(ct.house), "house")))
		ct["loot"] = roll(ty, String(ct.kind), rng, c.rolls)
		ct["place"] = ty
	return out


## The doorway tile nearest to a room (its own house's doors, inside ones too): where a sign for a room that stands in for a place goes.
static func _room_door(t: Dictionary, rm: int) -> Vector2:
	var room: Dictionary = t.rooms[rm]
	var c := Rect2(room.rect).get_center()
	var best := c
	var bd := 1.0e9
	for h in t.houses:
		if int(h.id) != int(room.house):
			continue
		for d in h.doors:
			var q := Vector2(Vector2i((d.tiles as Array)[0])) + Vector2(0.5, 0.5)
			if q.distance_to(c) < bd:
				bd = q.distance_to(c)
				best = q
	return best


static func _count(type_of: Dictionary, room_type: Dictionary, ty: String) -> int:
	var n := 0
	for hid in type_of:
		if type_of[hid] == ty:
			n += 1
	for rm in room_type:
		if room_type[rm] == ty:
			n += 1
	return n


## What one container of a place type holds: {res: n}.
static func roll(ty: String, ckind: String, rng: RandomNumberGenerator, tables = null) -> Dictionary:
	var c := cfg()
	var rolls: Array = (tables if tables != null else c.rolls)[ty]
	var k: Dictionary = c.kinds.get(ckind, {})
	var only: Array = k.get("only", [])
	var use: Array = []
	for r in rolls:
		if only.is_empty() or only.has(String(r[0])):
			use.append(r)
	if use.is_empty():
		use = rolls
	var loot := {}
	for r in use:
		var p := float((k.get("p", {}) as Dictionary).get(String(r[0]), r[1]))
		if rng.randf() < p:
			loot[String(r[0])] = int(loot.get(String(r[0]), 0)) + rng.randi_range(int(r[2]), int(r[3]))
	var lm := float(Bal.dm("loot"))    # the difficulty's share of the shelves (after the dice, so a seed rolls the same on every level)
	if lm != 1.0:
		for item in loot:
			loot[item] = maxi(1, roundi(float(loot[item]) * lm))
	return loot


# ------------------------------------------------------------------ the raid's marks --

## A raid starts: the town is retagged (before the stage is made) and the target is the choice made at the gate (else the biggest need).
func begin(t: Dictionary, seed_i: int) -> void:
	kind = ""
	if not (cfg().get("town_kinds", {}) as Dictionary).is_empty():
		if force_kind != "":
			kind = force_kind
		elif game.args.has("townkind"):
			kind = String(game.args.townkind)
		elif picked_kind != "":
			kind = picked_kind
	if kind != "" and place_for(kind) != "":
		kind = place_for(kind)    # (an event's kind word is the map's place of that kind)
	if picked_kind != "" and kind == picked_kind and game.stores != null:    # the truck's fuel is spent when it goes (not for a staged --raid)
		game.stores["fuel"] = maxf(0.0, float(game.stores.get("fuel", 0.0)) - float(place_cfg(kind).get("fuel", 0)))
	force_kind = ""
	picked_kind = ""
	if kind == "standard" or kind_cfg(kind).is_empty():
		kind = ""
	_thin_dead(t, seed_i)
	places = prepare(t, seed_i, kind)
	t["places"] = places
	var o := default_option()
	if game.args.has("target"):
		o = int(game.args.target)
	if picked >= 0:
		o = picked
		picked = -1
	option = clampi(o, 0, (cfg().options as Array).size() - 1)
	if game.args.has("log"):
		for pl in places:
			if pl.type != "house":
				print("PLACE ", pl.type, " at ", pl.pos, " door ", pl.door, " room ", pl.get("room", -1))
	target = []
	for ty in cfg().options[option].types:
		target.append(String(ty))


## The place's dead density: the town's dead are thinned (a share kept) or crowded (copies set a little beside them), stable per seed.
func _thin_dead(t: Dictionary, seed_i: int) -> void:
	var m := dead_mult()
	if m == 1.0 or not t.has("dead"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _h(seed_i, 4141)
	var out: Array = []
	for r in t.dead:
		if m < 1.0:
			if rng.randf() < m:
				out.append(r)
			continue
		out.append(r)
		var extra := int(floor(m - 1.0)) + (1 if rng.randf() < fposmod(m - 1.0, 1.0) else 0)
		for i in extra:
			var c: Dictionary = (r as Dictionary).duplicate()
			c["pos"] = Vector2(r.pos) + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
			out.append(c)
	t["dead"] = out


func dead_mult() -> float:
	return float(kind_cfg(kind).get("dead_mult", 1.0))


## The option (cfg.options index) a trip to a place marks: the one for the base's shortage when the place answers it, else the place's own `hunt`.
func option_for(id: String) -> int:
	var ans: Array = kind_cfg(id).get("answers", [])
	var opts: Array = cfg().options
	for res in short_res():
		if ans.has(res):
			for i in opts.size():
				if (opts[i].res as Array).has(res):
					return i
	return clampi(int(place_cfg(id).get("hunt", default_option())), 0, opts.size() - 1)


## What the base is short of: the econ's biggest shortage first, then the convoy list's unmet stock lines (from the day the list shows).
func short_res() -> Array:
	var out: Array = []
	var nd: Dictionary = game.econ.needs()
	if not nd.is_empty():
		out.append(String(nd.res))
	if game.arc != null and int(game.econ.day) >= 3:    # (the convoy list shows from day 3)
		for r in game.arc.requirements():
			if String(r.kind) == "stock" and not bool(r.ok) and String(r.res) != "" and not out.has(String(r.res)):
				out.append(String(r.res))
	return out


## The option the base needs most now (the econ's biggest shortage), 0 when nothing is short.
func default_option() -> int:
	var nd: Dictionary = game.econ.needs()
	if nd.is_empty():
		return 0
	var res := String(nd.res)
	var opts: Array = cfg().options
	for i in opts.size():
		if (opts[i].res as Array).has(res):
			return i
	return 0


func hint() -> String:
	var names: Array = []
	var hs: Array = []
	for ty in target:
		names.append(String(cfg().names[ty]))
		hs.append(String(eff(kind).hints[ty]))
	return "Marked: %s (%s)" % [" / ".join(names), "; ".join(hs)] if not target.is_empty() else ""


func _col(ty: String) -> Color:
	return Color(String(cfg().colors[ty]))


func _on_map(ty: String) -> bool:
	return target.has(ty)


## World overlay (px): a ring and a name on each marked place, and a small sign (icon and word) at the place's door: always for the targeted types, for the others when Ruth is near.
func paint(c: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var pulse := 0.5 + 0.5 * sin(game.clock * 3.0)
	var big := maxf(1.0, 22.0 / game.zoom_px * 2.0)    # (the overview: rings and names grow so that they can be seen)
	var tint := String(kind_cfg(kind).get("tint", ""))
	if tint != "":
		c.draw_rect(Rect2(Vector2.ZERO, Vector2(64, 64) * TILE), Color(Color(tint), 0.1))    # (the kind's colour wash over the town)
	_paint_layout(c, tint)
	for pl in places:
		var ty := String(pl.type)
		var at: Vector2 = Vector2(pl.pos) * TILE
		var col := _col(ty)
		var door: Vector2 = Vector2(pl.get("door", pl.pos)) * TILE
		if _on_map(ty):
			var rad := 2.6 * TILE * big
			c.draw_circle(at, rad, Color(col, 0.16 + 0.1 * pulse))
			c.draw_arc(at, rad, 0, TAU, 36, Color(col, 0.95), 5.0 * big)
			c.draw_arc(at, rad * 0.62, 0, TAU, 28, Color(col, 0.6), 2.0 * big)
			c.draw_string(font, at - Vector2(170.0 * big, rad + 6.0), "%s: %s" % [String(cfg().names[ty]), String(eff(kind).hints[ty])], HORIZONTAL_ALIGNMENT_CENTER, 340.0 * big, int(22.0 * big), col)
			_sign(c, door, ty, col, 1.0, big)
		elif me.distance_to(Vector2(pl.pos)) < 16.0 and ty != "house":
			_sign(c, door, ty, col, 0.8, 1.0)


## The place's own look on the raid map, drawn along the town's edges and middle (a hint, not a rule): water and cranes at the port, a runway at the airport, the stands of the stadium, a chain fence round the yard, a frame in the place's colour for the rest.
func _paint_layout(c: CanvasItem, tint: String) -> void:
	var lay := String(kind_cfg(kind).get("layout", ""))
	if lay == "":
		return
	var col := Color(tint) if tint != "" else Color(0.8, 0.8, 0.8)
	var W := 64.0 * TILE
	c.draw_rect(Rect2(Vector2.ZERO, Vector2(W, W)), Color(col, 0.55), false, 10.0)
	match lay:
		"quay":
			c.draw_rect(Rect2(Vector2(W - 7.0 * TILE, 0), Vector2(7.0 * TILE, W)), Color(0.15, 0.3, 0.5, 0.35))
			for i in 8:
				c.draw_rect(Rect2(Vector2(W - 11.0 * TILE, (5.0 + i * 7.0) * TILE), Vector2(3.0 * TILE, 1.6 * TILE)), Color(0.8, 0.45, 0.2, 0.3))    # (container stacks on the quay)
		"apron":
			c.draw_rect(Rect2(Vector2(0, 2.0 * TILE), Vector2(W, 3.0 * TILE)), Color(0.35, 0.37, 0.42, 0.4))
			for i in 16:
				c.draw_rect(Rect2(Vector2((1.0 + i * 4.0) * TILE, 3.4 * TILE), Vector2(2.0 * TILE, 0.3 * TILE)), Color(1, 1, 0.9, 0.4))
		"stands":
			c.draw_arc(Vector2(W * 0.5, W * 0.5), 14.0 * TILE, 0, TAU, 64, Color(col, 0.5), 14.0)
			c.draw_arc(Vector2(W * 0.5, W * 0.5), 9.0 * TILE, 0, TAU, 48, Color(0.5, 0.75, 0.4, 0.35), 8.0)
		"yard":
			for i in 32:
				c.draw_rect(Rect2(Vector2(i * 2.0 * TILE, 0), Vector2(0.5 * TILE, 0.5 * TILE)), Color(0.9, 0.6, 0.2, 0.35))
				c.draw_rect(Rect2(Vector2(i * 2.0 * TILE, W - 0.5 * TILE), Vector2(0.5 * TILE, 0.5 * TILE)), Color(0.9, 0.6, 0.2, 0.35))


const SIGN_WORD := {"shop": "SHOP", "pharmacy": "PHARMACY", "hardware": "HARDWARE", "garage": "GARAGE", "petrol": "FUEL", "police": "POLICE"}


## A plate at the door (above it on the screen): a dark board, the type's colour, a small icon and the word.
func _sign(c: CanvasItem, door: Vector2, ty: String, col: Color, a: float, k: float) -> void:
	var font := ThemeDB.fallback_font
	var w := 132.0 * k
	var h := 30.0 * k
	var r := Rect2(door + Vector2(-w / 2.0, -h - 22.0 * k), Vector2(w, h))
	c.draw_rect(Rect2(r.position + Vector2(2, 2) * k, r.size), Color(0, 0, 0, 0.5 * a))
	c.draw_rect(r, Color(0.06, 0.07, 0.08, 0.92 * a))
	c.draw_rect(r, Color(col, a), false, 2.0 * k)
	c.draw_line(door + Vector2(0, -22.0 * k), door, Color(col, a), 3.0 * k)    # the post down to the doorway
	var ic := r.position + Vector2(h / 2.0, h / 2.0)
	var u := h * 0.28
	var ink := Color(col, a)
	match ty:
		"pharmacy":
			c.draw_rect(Rect2(ic - Vector2(u * 0.35, u), Vector2(u * 0.7, u * 2.0)), ink)
			c.draw_rect(Rect2(ic - Vector2(u, u * 0.35), Vector2(u * 2.0, u * 0.7)), ink)
		"hardware":
			c.draw_rect(Rect2(ic - Vector2(u, u), Vector2(u * 2.0, u * 0.8)), ink)
			c.draw_rect(Rect2(ic - Vector2(u * 0.25, u), Vector2(u * 0.5, u * 2.0)), ink)
		"garage":
			c.draw_rect(Rect2(ic - Vector2(u, u * 0.6), Vector2(u * 2.0, u * 1.0)), ink)
			c.draw_circle(ic + Vector2(-u * 0.6, u * 0.55), u * 0.35, ink)
			c.draw_circle(ic + Vector2(u * 0.6, u * 0.55), u * 0.35, ink)
		"petrol":
			c.draw_circle(ic + Vector2(0, u * 0.3), u * 0.75, ink)
			c.draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -u * 1.2), ic + Vector2(-u * 0.6, u * 0.1), ic + Vector2(u * 0.6, u * 0.1)]), ink)
		"police":
			c.draw_colored_polygon(PackedVector2Array([ic + Vector2(-u, -u), ic + Vector2(u, -u), ic + Vector2(u, u * 0.2), ic + Vector2(0, u * 1.2), ic + Vector2(-u, u * 0.2)]), ink)
		_:
			c.draw_rect(Rect2(ic - Vector2(u, 0), Vector2(u * 2.0, u * 0.9)), ink)
			c.draw_arc(ic + Vector2(0, 0), u * 0.8, PI, TAU, 8, ink, 2.0 * k)
	c.draw_string(font, r.position + Vector2(h, h * 0.72), String(SIGN_WORD.get(ty, ty.to_upper())), HORIZONTAL_ALIGNMENT_LEFT, w - h - 4.0 * k, int(15.0 * k), Color(1, 1, 0.92, a))


## The minimap (`o`: its corner in px, `sc`: px per tile): a coloured ring on each marked place.
func mini(bars: Control, o: Vector2, sc: float) -> void:
	for pl in places:
		if _on_map(String(pl.type)):
			bars.draw_arc(o + Vector2(pl.pos) * sc, 4.5, 0, TAU, 14, _col(String(pl.type)), 2.0)
			bars.draw_circle(o + Vector2(pl.pos) * sc, 1.6, _col(String(pl.type)))


# ------------------------------------------------------------------ the gate's choice --

## E at the truck (or M): opens the destination map (true: the game must not go out yet). `view` = only look (M away from the truck).
func open_choice(view := false) -> bool:
	if game.args.has("target") or game.args.has("auto") or choosing:
		return false
	var rm: String = game.arc.take_raid_mod() if game.arc != null else ""    # EVENTS: a card's raid_mod picks the next town (a kind id, or the card's own word via RAID_MOD_KIND)
	if rm != "":
		force_kind = String(RAID_MOD_KIND.get(rm, rm))
	var forced := place_for(force_kind) if force_kind != "" else ""
	if game.args.has("townkind"):
		forced = place_for(String(game.args.townkind))
	if dest == null:
		dest = DestMap.new(self, game)
	choosing = true
	option = default_option()
	dest.open(view, forced)
	return true


## The map's Go: the place is the raid's town, its marks the shortage's (or the place's own), then the loadout card.
func go_to(id: String) -> void:
	choosing = false
	dest.close()
	picked = option_for(id)
	picked_kind = id
	game.loadout.open(String(place_cfg(id).get("name", id)))    # SQUAD hook: the second step of the gate's choice (gun, kit, companions), which goes out


## Keys while the map is open. True when used.
func key(ev: InputEvent) -> bool:
	if not choosing or dest == null:
		return false
	return dest.key(ev)


# ------------------------------------------------------------------ the lab --

## `--loot-lab=N`: N raid towns (seeds 1..N), place counts per type, the share of seeds with every type, and what a 3-minute raid finds (nearest container first, 4 tiles a second plus 6 seconds
## a container; the targeted one hunts the places of each option in turn and takes the others only when they are near). Prints LOOTLAB lines.
static func lab(n: int) -> void:
	var c := cfg()
	var types: Array = (c.rolls as Dictionary).keys()
	var count := {}
	var seeds_with := {}
	var sums := {}
	var tsums := {}
	var allres := ["food", "water", "meds", "scrap", "parts", "fuel", "ammo"]
	var rmin := {}
	var rmax := {}
	for ty in types:
		count[ty] = 0
		seeds_with[ty] = 0
	for r in allres:
		sums[r] = 0.0
		tsums[r] = 0.0
		rmin[r] = 999
		rmax[r] = 0
	for s in range(1, n + 1):
		var t: Dictionary = TownGen.make(s, c.town_opts)
		var pls := prepare(t, s)
		var has := {}
		for p in pls:
			count[p.type] = int(count[p.type]) + 1
			has[p.type] = true
		for ty in has:
			seeds_with[ty] = int(seeds_with[ty]) + 1
		var got := _sim_raid(t, pls, [])
		for r in allres:
			sums[r] += float(got.get(r, 0))
			rmin[r] = mini(int(rmin[r]), int(got.get(r, 0)))
			rmax[r] = maxi(int(rmax[r]), int(got.get(r, 0)))
		var opt: Array = c.options[s % c.options.size()].types
		var g2 := _sim_raid(t, pls, opt)
		var o: Array = c.options[s % c.options.size()].res
		for r in allres:
			if o.has(r) or r == "food" or r == "water":
				tsums[r] += float(g2.get(r, 0)) if o.has(r) else 0.0
	print("LOOTLAB seeds ", n, " (town opts ", c.town_opts, ")")
	for ty in types:
		print("LOOTLAB place %-9s avg %.1f per town, in %d%% of seeds" % [ty, float(count[ty]) / n, roundi(100.0 * float(seeds_with[ty]) / n)])
	for r in allres:
		print("LOOTLAB 3-min raid, nobody told where: %-6s avg %.1f  (min %d, max %d)" % [r, sums[r] / n, rmin[r], rmax[r]])
	var per := n / float((c.options as Array).size())
	for r in allres:
		print("LOOTLAB 3-min raid hunting %-6s only when it is the target: avg %.1f" % [r, tsums[r] / maxf(1.0, per)])
	var tk: Dictionary = c.get("town_kinds", {})
	for k in tk:
		if not String(k).begins_with("_"):
			_lab_kind(n, String(k), allres, types)


## One town kind: place counts and the blind 3-minute raid's yield per resource (LOOTKIND lines).
static func _lab_kind(n: int, k: String, allres: Array, types: Array) -> void:
	var count := {}
	var sums := {}
	for ty in types:
		count[ty] = 0
	for r in allres:
		sums[r] = 0.0
	var guns := 0.0
	for s in range(1, n + 1):
		var t: Dictionary = TownGen.make(s, cfg().town_opts)
		var pls := prepare(t, s, k)
		for p in pls:
			count[p.type] = int(count[p.type]) + 1
		var got := _sim_raid(t, pls, [])
		for r in allres:
			sums[r] += float(got.get(r, 0))
		for g in ["gun_smg", "gun_service", "gun_shotgun"]:
			guns += float(got.get(g, 0))
	var pl: Array = []
	for ty in types:
		pl.append("%s %.1f" % [ty, float(count[ty]) / n])
	print("LOOTKIND %-11s places/town: %s" % [k, ", ".join(pl)])
	var ys: Array = []
	for r in allres:
		ys.append("%s %.1f" % [r, sums[r] / n])
	print("LOOTKIND %-11s per 3-min raid: %s, guns %.2f" % [k, ", ".join(ys), guns / n])


## One greedy raid of 180 s: {res: units}.
static func _sim_raid(t: Dictionary, pls: Array, hunt: Array) -> Dictionary:
	var pos: Vector2 = Vector2(t.entry.pos)
	var left: Array = (t.containers as Array).duplicate()
	var secs := 180.0
	var got := {}
	while secs > 0.0 and not left.is_empty():
		var best := -1
		var bc := 1.0e9
		for i in left.size():
			var d := pos.distance_to(Vector2(left[i].pos))
			var cost := d
			if not hunt.is_empty() and not hunt.has(String(left[i].place)):
				cost += 25.0
			if cost < bc:
				bc = cost
				best = i
		var ct: Dictionary = left[best]
		var d2 := pos.distance_to(Vector2(ct.pos))
		secs -= d2 / 4.0 + 6.0
		if secs < 0.0:
			break
		pos = Vector2(ct.pos)
		for r in ct.loot:
			got[r] = int(got.get(r, 0)) + int(ct.loot[r])
		left.remove_at(best)
	return got
