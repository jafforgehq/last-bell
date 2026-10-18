## EXPERIMENT (prison raids, step 4a): LOOT BY PLACE, the raid's marks and the gate's choice.
## Pattern: a seeded POST-PASS over the town the generator made (the generator is not touched): every building gets a place type (natural map from its kind, then a stable-hash retag so a raid
## town always has its minimum of pharmacies, hardware stores, garages, petrol stations and police posts), and every container's loot is re-rolled from the type's table with a RandomNumberGenerator
## seeded by (town seed, container index). The numbers are assets/data/prison_raids.json. Items: parts and fuel are ordinary backpack items (items.json parts_box, fuel_can; the grid, loot window, bank
## and stash carry them as the stock units `parts` and `fuel`), so the pack's 32 cells are the choice. The inventory pattern is the existing data-driven grid (items.json + scripts/sim/inventory.gd),
## not a Resource per item: the pack already is one.
## Owned by prison_game.gd (`loot`, `# RAIDS hook`). `--loot-lab=N` prints the distribution (see `lab`).
extends RefCounted

const Access := preload("res://scripts/access.gd")
const PIcons := preload("res://scripts/prison/prison_icons.gd")
const Bal := preload("res://scripts/prison/prison_bal.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")
const DestMap := preload("res://scripts/prison/prison_destmap.gd")
const Site := preload("res://scripts/prison/prison_site.gd")
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


## The raid map of a place or town kind `k` (a seed): the place's own site when its layout has one (prison_site.gd: the port, the airport, the stadium...), else the generator's town.
static func make_town(seed_i: int, k: String) -> Dictionary:
	var t: Dictionary = Site.make(seed_i, place_cfg(place_for(k))) if k != "" and place_for(k) != "" else {}
	return t if not t.is_empty() else TownGen.make(seed_i, cfg().town_opts)


## Retags the buildings and re-rolls the containers' loot of a town. Returns the places [{house, type, pos, n}] (a building, or one ROOM of a building when the town has too few buildings for the minimums).
static func prepare(t: Dictionary, seed_i: int, k := "") -> Array:
	var c := eff(k)
	if t.has("site"):
		return _prepare_site(t, seed_i, c)
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


## A site (prison_site.gd) says the type of each building, room and open-air container itself (no retag): a place for each typed building (its containers outside typed rooms), each typed
## room and each group of open-air containers, with the name and hint of the place's `buildings` data; every container rolled from its own type's table.
static func _prepare_site(t: Dictionary, seed_i: int, c: Dictionary) -> Array:
	var out: Array = []
	var n_house := {}
	var n_room := {}
	for ct in t.containers:
		var rm := int(ct.room)
		if rm >= 0 and t.rooms[rm].has("ptype"):
			n_room[rm] = int(n_room.get(rm, 0)) + 1
		elif int(ct.house) >= 0:
			n_house[int(ct.house)] = int(n_house.get(int(ct.house), 0)) + 1
	for h in t.houses:
		if int(n_house.get(int(h.id), 0)) > 0:
			out.append({"house": int(h.id), "type": String(h.ptype), "pos": Rect2(h.rect).get_center(), "n": int(n_house[int(h.id)]), "door": Vector2(Vector2i(h.door)) + Vector2(0.5, 0.5),
				"name": String(h.label), "hint": String(h.hint), "rect": Rect2(h.rect)})
	for rm in n_room:
		var room: Dictionary = t.rooms[int(rm)]
		out.append({"house": -1, "room": int(rm), "type": String(room.ptype), "pos": Rect2(room.rect).get_center(), "n": int(n_room[rm]), "door": _room_door(t, int(rm)),
			"name": String(room.label), "hint": String(room.hint), "rect": Rect2(room.rect).grow(1.0)})
	for g in t.site.groups:
		var gr: Rect2 = g.rect
		var n := 0
		for ct in t.containers:
			if bool(ct.get("car", false)) and gr.has_point(Vector2(ct.pos)):
				n += 1
		if n > 0:
			out.append({"house": -1, "room": -1, "type": String(g.type), "pos": gr.get_center(), "n": n, "door": gr.get_center(), "name": String(g.name), "hint": String(g.hint), "rect": gr,
				"group": true})
	for ci in t.containers.size():
		var ct: Dictionary = t.containers[ci]
		var rng := RandomNumberGenerator.new()
		rng.seed = _h(seed_i, ci + 1)
		var ty := String(ct.get("ptype", ""))
		if ty == "":
			var rm2 := int(ct.room)
			ty = String(t.rooms[rm2].ptype) if rm2 >= 0 and t.rooms[rm2].has("ptype") else (String(t.houses[int(ct.house)].ptype) if int(ct.house) >= 0 else "house")
		if not (c.rolls as Dictionary).has(ty):
			ty = "house"
		ct["loot"] = roll(ty, String(ct.kind), rng, c.rolls)
		ct["place"] = ty
	return out


## The stash of raid number `raid` (prison_raids.json `first_stash`, raids 1 to `raids`): a container of one of its kinds (a car's trunk, a locker) between `near` and `far` tiles of the
## drop-off, else the one nearest `want` tiles away, gets the stash's loot on top of its own. Returns the set-piece record for the arc ({} when this raid has none).
static func first_stash(t: Dictionary, raid: int) -> Dictionary:
	var fs: Dictionary = cfg().get("first_stash", {})
	if fs.is_empty() or raid < 1 or raid > int(fs.raids):
		return {}
	var drop: Vector2 = Vector2(t.site.drop) if t.has("site") else Vector2(t.entry.pos)
	var best: Dictionary = {}
	var bs := INF
	for ct in t.containers:
		var d := Vector2(ct.pos).distance_to(drop)
		var score := absf(d - float(fs.want)) + (0.0 if (fs.kinds as Array).has(String(ct.kind)) and d >= float(fs.near) and d <= float(fs.far) else 1000.0)
		if score < bs:
			bs = score
			best = ct
	if best.is_empty():
		return {}
	var loot: Dictionary = best.loot
	for k in fs.loot:
		loot[k] = int(loot.get(k, 0)) + int(fs.loot[k])
	return {"name": String(fs.name), "loot": {}, "note": false, "found": String(fs.found), "stash": true, "pos": Vector2(best.pos), "id": String(best.id)}


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

## The kind (the place) of the raid that starts now: the event's, the flag's or the gate's choice (the truck's fuel is spent here). Called before the town is made (`make_town`).
func resolve_kind() -> String:
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
	return kind


## A raid starts: the town (made for `kind`) is retagged (before the stage is made) and the target is the choice made at the gate (else the biggest need).
func begin(t: Dictionary, seed_i: int) -> void:
	_thin_dead(t, seed_i)
	places = prepare(t, seed_i, kind)
	game.raidx.scale_loot(t, seed_i)    # RAID EXTRAS: the shelves of the map's Day or Night
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
	return float(kind_cfg(kind).get("dead_mult", 1.0)) * (float(game.raidx.dead_mult()) if game != null and game.raidx != null else 1.0)    # (RAID EXTRAS: times the map's Day or Night)


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


## World overlay (px): an outline round each marked place (the building's walls, the room, the group's area: no fill, so nothing under it is hidden) and ONE plate per place at its door (icon,
## name and, on a marked place, what it holds): always for the marked types, for the others when Ruth is near. On the overview (zoomed out) the plates are left to `map_labels`, on the HUD.
func paint(c: CanvasItem) -> void:
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var pulse := 0.5 + 0.5 * sin(game.clock * 3.0)
	var big := maxf(1.0, 22.0 / game.zoom_px * 2.0)    # (the overview: the lines grow so that they can be seen)
	var tint := String(kind_cfg(kind).get("tint", ""))
	if tint != "":
		c.draw_rect(Rect2(Vector2.ZERO, Vector2(64, 64) * TILE), Color(Color(tint), 0.06))    # (the kind's colour wash over the town)
	for pl in places:
		var ty := String(pl.type)
		var col := _col(ty)
		var door: Vector2 = Vector2(pl.get("door", pl.pos)) * TILE
		if _on_map(ty):
			var r := _rect_of(pl)
			var rr := Rect2(r.position * TILE, r.size * TILE).grow(0.35 * TILE)
			c.draw_rect(rr, Color(0, 0, 0, 0.5), false, 9.0 * big)
			c.draw_rect(rr, Color(col.lightened(0.15), 0.65 + 0.35 * pulse), false, 5.0 * big)
			if big <= 1.5:
				_sign(c, door, ty, col, 1.0, 1.0, _name_of(pl), _hint_of(pl))
		elif big <= 1.5 and me.distance_to(Vector2(pl.pos)) < 16.0 and ty != "house":
			_sign(c, door, ty, col, 0.8, 1.0, _name_of(pl), "")


## The area of a place in tiles: its rect (a site's), the walls of its house, the room, else a small square round it.
func _rect_of(pl: Dictionary) -> Rect2:
	if pl.has("rect"):
		return Rect2(pl.rect)
	if int(pl.get("house", -1)) >= 0 and game.town != null and int(pl.house) < (game.town.houses as Array).size():
		return Rect2(game.town.houses[int(pl.house)].rect)
	if int(pl.get("room", -1)) >= 0 and game.town != null:
		return Rect2(game.town.rooms[int(pl.room)].rect)
	return Rect2(Vector2(pl.pos) - Vector2(2, 2), Vector2(4, 4))


func _name_of(pl: Dictionary) -> String:
	return String(pl.get("name", cfg().names.get(String(pl.type), String(pl.type))))


func _hint_of(pl: Dictionary) -> String:
	var h := String(pl.get("hint", ""))
	return h if h != "" else String(eff(kind).hints.get(String(pl.type), ""))


## The overview's names (HUD px, `v` the screen): one plate for each marked place, "Name: what it holds", above its area, moved below or beside it when it would cover another plate or
## the HUD (the top bar, the objectives, the minimap, the gun, the squad card, the message lane), left out when it fits nowhere.
func map_labels(c: Control, v: Vector2) -> void:
	if game.mode != "raid" or game.zoom_px > 16.0:
		return
	var font := ThemeDB.fallback_font
	var block: Array = [Rect2(0, 0, v.x, 100), Rect2(0, v.y - 200, 430, 200), Rect2(v.x * 0.2, v.y - 250, v.x * 0.6, 250), Rect2(0, 300, 420, 170)]
	var msz := Vector2(64, 64) * 2.6
	block.append(Rect2(v - msz - Vector2(30, 30), msz + Vector2(30, 30)))
	var tb = game.get("topbar")
	if tb != null and tb.get("tracker") != null and tb.tracker.visible:
		block.append(tb.tracker.get_global_rect().grow(8.0))
	if game.prompt_label.visible:    # (the prompt plate where it is now: it can sit above its lane)
		block.append(game.prompt_label.get_global_rect().grow(8.0))
	var xf: Transform2D = game.world.get_global_transform_with_canvas()    # (the world as the camera shows it now: tiles to the screen)
	var taken: Array = []
	for pl in places:
		var ty := String(pl.type)
		if not _on_map(ty):
			continue
		var r := _rect_of(pl)
		var a: Vector2 = xf * (r.position * TILE)
		var b: Vector2 = xf * (r.end * TILE)
		var txt := "%s: %s" % [_name_of(pl), _hint_of(pl)]
		var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15) + Vector2(16, 10)
		var mid: float = (a.x + b.x) * 0.5
		var tries := [Vector2(mid - sz.x / 2.0, a.y - sz.y - 4.0), Vector2(mid - sz.x / 2.0, b.y + 4.0), Vector2(b.x + 4.0, (a.y + b.y - sz.y) / 2.0), Vector2(a.x - sz.x - 4.0, (a.y + b.y - sz.y) / 2.0),
			Vector2(mid - sz.x / 2.0, (a.y + b.y - sz.y) / 2.0)]
		for q in tries:
			var lr := Rect2(q, sz)
			if lr.position.x < 4.0 or lr.position.y < 4.0 or lr.end.x > v.x - 4.0 or lr.end.y > v.y - 4.0:
				continue
			var ok := true
			for o in block + taken:
				if Rect2(o).intersects(lr):
					ok = false
					break
			if not ok:
				continue
			taken.append(lr.grow(3.0))
			var col := _col(ty)
			c.draw_rect(lr, Color(0.04, 0.05, 0.06, 0.88))
			c.draw_rect(lr, col, false, 2.0)
			c.draw_string(font, lr.position + Vector2(8, sz.y - 9.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 0.92))
			break


const SIGN_WORD := {"shop": "SHOP", "pharmacy": "PHARMACY", "hardware": "HARDWARE", "garage": "GARAGE", "petrol": "FUEL", "police": "POLICE"}


## A plate at the door (above it on the screen): a dark board, the type's colour, a small icon and the word.
func _sign(c: CanvasItem, door: Vector2, ty: String, col: Color, a: float, k: float, word: String = "", hint_txt: String = "") -> void:
	var font := ThemeDB.fallback_font
	word = word.to_upper() if word != "" else String(SIGN_WORD.get(ty, ty.to_upper()))
	var w := maxf(132.0, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 44.0) * k
	if hint_txt != "":
		w = maxf(w, (font.get_string_size(hint_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16.0) * k)
	var h := (30.0 if hint_txt == "" else 48.0) * k
	var r := Rect2(door + Vector2(-w / 2.0, -h - 22.0 * k), Vector2(w, h))
	c.draw_rect(Rect2(r.position + Vector2(2, 2) * k, r.size), Color(0, 0, 0, 0.5 * a))
	c.draw_rect(r, Color(0.06, 0.07, 0.08, 0.92 * a))
	c.draw_rect(r, Color(col, a), false, 2.0 * k)
	c.draw_line(door + Vector2(0, -22.0 * k), door, Color(col, a), 3.0 * k)    # the post down to the doorway
	var ic := r.position + Vector2(15.0, 15.0) * k
	var u := 30.0 * k * 0.28
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
	c.draw_string(font, r.position + Vector2(30.0, 21.6) * k, word, HORIZONTAL_ALIGNMENT_LEFT, w - 34.0 * k, int(15.0 * k), Color(1, 1, 0.92, a))
	if hint_txt != "":
		c.draw_string(font, r.position + Vector2(8.0, 41.0) * k, hint_txt, HORIZONTAL_ALIGNMENT_LEFT, w - 12.0 * k, int(13.0 * k), Color(col.lightened(0.3), a))


## The minimap (`o`: its corner in px, `sc`: px per tile): a coloured ring on each marked place.
func mini(bars: Control, o: Vector2, sc: float) -> void:
	for pl in places:
		if _on_map(String(pl.type)):
			bars.draw_arc(o + Vector2(pl.pos) * sc, 4.5, 0, TAU, 14, _col(String(pl.type)), 2.0)
			if Access.markers():
				PIcons.mark(bars, "loot", o + Vector2(pl.pos) * sc, 3.0, _col(String(pl.type)))
			else:
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


## `--sitecheck=N`: each place with a site of its own (prison_site.gd), seeds 1..N: the containers, the dead, the places with their names and types, what is NOT reachable on foot from the
## entry (containers, the pickup point: it must be none) and a blind 3-minute raid's yield (SITECHECK lines; a line "SITECHECK FAIL" for each problem).
static func site_check(n: int) -> void:
	var fails := 0
	for id in place_ids():
		var pc := place_cfg(id)
		if not Site.LAYOUTS.has(String(pc.get("layout", ""))):
			continue
		for s in range(1, n + 1):
			var t := make_town(s, id)
			if not t.has("site"):
				print("SITECHECK FAIL %s seed %d: no site made" % [id, s])
				fails += 1
				continue
			var pls := prepare(t, s, id)
			var bad := Site.unreachable(t)
			var got := _sim_raid(t, pls, [])
			var names: Array = pls.map(func(p): return "%s(%s %d)" % [p.name, p.type, p.n])
			print("SITECHECK %s seed %d: %d containers, %d dead, %d houses, places %s, exit %s, raid %s" % [id, s, (t.containers as Array).size(), (t.dead as Array).size(), (t.houses as Array).size(), ", ".join(names), t.site.exit, got])
			var old := TownGen.make(s, cfg().town_opts)    # (the generator's town of the same kind, to compare the yield)
			var opl := prepare(old, s, id)
			print("SITECHECK %s seed %d (the old town): %d containers, %d dead, raid %s" % [id, s, (old.containers as Array).size(), (old.dead as Array).size(), _sim_raid(old, opl, [])])
			if not bad.is_empty():
				print("SITECHECK FAIL %s seed %d: not reachable %s" % [id, s, bad])
				fails += 1
			for h in t.houses:
				if (h.containers as Array).is_empty():
					print("SITECHECK note %s seed %d: %s has no container" % [id, s, h.label])
	print("SITECHECK done, failures: %d" % fails)


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
		var t: Dictionary = make_town(s, k)
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
