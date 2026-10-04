## `sim.perimeter` (One House, WP5 phase B): the ring of places round the claimed house where the player puts up a fence, a gate, a tower or a floodlight, and what
## the dead do to them. The slots are the layout's (scripts/town/base_layout.gd: `layout.slots`, each also a Build plot of kind "slot" with the same id), the kits are
## assets/data/base_kits.json, the ordering, the scrap and the builders' work are the colony's own (`build.order`, `Build.update`): a slot is a Build plot, and when the
## builders finish it `Build._finish` calls `on_built(plot, building_id)` here.
##
## WHAT A BUILT SLOT IS
##   fence, gate   a wall section made in play (`sim.add_segment`, the lots' mechanism, scripts/sim/lots.gd `_make_section`): ids 12 and up (the layout's order), kind
##                 "fence" or "gate", the kit's hit points, the dead's places on the outer side, its tiles shut. The colony then treats it as any section: the dead pick
##                 it by distance and crowd (`assign_slot`), claw it (`_claw`), the crew and the avatar mend it (`nights.wall_candidates`), a fallen one lets them in.
##   door          the house's two exterior doors are BARRED at `activate`: segments 10 and 11, kind "door": shut to the dead, open to people (`add_segment` shuts both
##                 grids, so the door tiles are opened again for people, as `Lots._passage_tiles` does). A door that falls is opened to the dead (`open_segment`), as the
##                 school's doors are. The plank kit adds hit points to the door it is on.
##   gate          shut, it is a wall to the dead and a gateway to people (the lots' passage). `toggle_gate` opens it to the dead as well ("left open it lets the dead in"):
##                 `gate_open()` is what `TownRules._any_gate_open` answers.
##   tower, floodlight   no section: the building's own effects (`reach_bonus`, `night_reach_mult`) are read by `build.reach_bonus_at` and `build.factor`.
##
## `no_outer_wall()` is true while no fence or gate stands (the dead then go for the barred doors: `TownRules.yard_open`).
##
## STAGES. A slot opens by the crew count (people alive, the avatar too): the plot's `unlock` {"crew": n}. `unlocked(plot)` is what `Build.refresh_plots` and
## `Build.why_not` ask; `update` bumps the Build page when the count changes.
##
## SAVES. `save()` keeps whether a base is on, the built slots (slot id to kit id) and the gate's state; the sections' hit points are the save's own (`segments`).
## `prepare_load` (hook H11, before the save is read) re-makes the doors and the built slots' sections BY ID from the layout that `base.prepare_load` put in place,
## so that `SaveGame._parse` finds every section; `restore` puts the old ones back when the save is refused.
##
## Events: {"type": "slot_ordered"|"slot_built"|"slot_lost", "slot": id, "kit": kit id} (plan 2.4), {"type": "gate_base", "open": bool}.
## It is also an E provider (`candidates`, `use`): the base's gate ("gate_base").
extends RefCounted

const KITS_PATH := "res://assets/data/base_kits.json"
## Where the kits are read from (tests may point it at another file).
static var kits_path := KITS_PATH
static var _cache := {}

## Segment ids: the barred doors take 10 and 11, the fence and gate slots 12 to 99 in the layout's order.
const FIRST_DOOR_ID := 10
const MAX_DOORS := 2
const FIRST_SLOT_ID := 12
const LAST_SLOT_ID := 99
const SIDES := ["N", "E", "S", "W"]
## The dead stand about this far apart along a section, and their approach point is this far behind their place.
const PLACE_SPACING := 0.9
const PLACE_APPROACH := 0.75
## The avatar can work the gate from this far (tiles).
const GATE_REACH := 3.5
## The state of the sections and the crew is looked at this often (seconds of rules time).
const WATCH_EVERY := 0.25

var sim
var enabled := true
## The layout in force ({} until `activate`).
var layout := {}
## Slot id to the slot as this module reads it (see `_index_layout`), in the layout's order.
var _slots := {}
var _order: Array = []
## Door ids as {"id", "seg", "rect", "side"}, the barred doors' segments.
var _doors: Array = []
## The sections this module made: segment id to the Segment.
var _made := {}
## Slot id to the kit built on it.
var _built := {}
var _lost := {}
var _gate_open := false
var _stage_crew := -1
var _t := 0.0


func setup(s) -> void:
	sim = s


## A new run: nothing stands.
func start() -> void:
	_clear_all()


# ---------------------------------------------------------------------- data --

## The kits file: {"kits": {id: {...}}, "unlock": {...}, "layout": {...}} (empty without a file).
static func load_kits(path: String = "") -> Dictionary:
	var p := path if path != "" else kits_path
	if not _cache.has(p):
		var out := {"kits": {}, "unlock": {}, "layout": {}}
		var raw = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		if raw is Dictionary:
			for k in raw.get("kits", {}):
				out.kits[String(k)] = raw.kits[k]
			out["unlock"] = raw.get("unlock", {})
			out["layout"] = raw.get("layout", {})
		_cache[p] = out
	return _cache[p]


static func _kit_data(kit_id: String) -> Dictionary:
	return load_kits().kits.get(kit_id, {})


## A kit's id from a catalogue id ("kit_fence" is "fence").
static func _kit_id(id: String) -> String:
	return id.trim_prefix("kit_")


static func _v2i(v) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(int(v.x), int(v.y))
	return Vector2i(int(v[0]), int(v[1]))


static func _rect(v) -> Rect2i:
	if v is Rect2i:
		return v
	if v is Rect2:
		return Rect2i(Vector2i(int(v.position.x), int(v.position.y)), Vector2i(int(v.size.x), int(v.size.y)))
	if v is Array and v.size() >= 4:
		return Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
	if v is Dictionary and v.has("position") and v.has("size"):
		return Rect2i(_v2i(v.position), _v2i(v.size))
	return Rect2i()


static func _crew_need(v) -> int:
	if v is Dictionary:
		return int(v.get("crew", 1))
	return int(v) if v != null else 1


func _index_layout() -> void:
	_slots.clear()
	_order.clear()
	var next_seg := FIRST_SLOT_ID
	for r in layout.get("slots", []):
		var kits: Array = []
		for k in r.get("kits", []):
			kits.append(_kit_id(String(k)))
		var s := {
			"id": String(r.id), "kind": String(r.get("kind", "fence")), "name": String(r.get("name", r.id)),
			"rect": _rect(r.get("rect")), "dir": String(r.get("dir", "h")), "side": String(r.get("side", "N")),
			"crew": _crew_need(r.get("unlock", 1)), "kits": kits, "places": r.get("dead_places", null),
			"plot": String(r.get("plot", r.id)), "door": String(r.get("door", "")), "seg": -1,
		}
		if (s.kind == "fence" or s.kind == "gate") and next_seg <= LAST_SLOT_ID:
			s.seg = next_seg
			next_seg += 1
		_slots[s.id] = s
		_order.append(s.id)


# ------------------------------------------------------------------ activation --

## The claim installs the base: the barred doors go up now, the slots wait to be ordered. (The Build plots and catalogue are `build.install_layout`'s, made by the claim.)
func activate(lay: Dictionary) -> void:
	_clear_all()
	layout = lay
	_index_layout()
	_make_doors()
	_stage_crew = crew_count()
	_refresh_build()


## Takes every section made here away and forgets the layout.
func _clear_all() -> void:
	if sim != null:
		for id in _made.keys():
			sim.remove_segment(_made[id])
	_made.clear()
	_slots.clear()
	_order.clear()
	_doors.clear()
	_built.clear()
	_lost.clear()
	layout = {}
	_gate_open = false
	_stage_crew = -1
	_t = 0.0


func _refresh_build() -> void:
	if sim.get("build") != null:
		sim.build._visible_dirty = true
		sim.build.version += 1


## The two exterior doors become barred-door segments 10 and 11: shut to the dead's grid, open to people.
func _make_doors() -> void:
	var town_doors: Array = []
	var hs = sim.get("houses")
	if hs != null and hs.has_method("doors_of") and int(layout.get("house", -1)) >= 0:
		town_doors = hs.doors_of(int(layout.house))
	var door_hp := float(load_kits().layout.get("door_hp", 90.0))
	var door_name := String(load_kits().layout.get("door_name", "Barred door"))
	var i := 0
	for d in layout.get("doors", []):
		if i >= MAX_DOORS:
			break
		var tiles: Array = []
		for t in d.get("tiles", []):
			tiles.append(_v2i(t))
		if tiles.is_empty():
			continue
		var side := String(d.get("side", ""))
		if not side in SIDES:
			side = _door_side(tiles, town_doors)
		var rect := _bounds(tiles)
		var id := FIRST_DOOR_ID + i
		var did := String(d.get("id", "door_%d" % i))
		var name := String(d.get("name", ""))
		if name == "":
			name = "Front door" if did.contains("front") else ("Back door" if did.contains("back") else door_name)
		var places: Array = d.get("dead_places", [])    # (the layout's: one for each tile just outside, on open ground only)
		if places.is_empty():
			places = _door_places(rect, side)
		var seg = sim.add_segment(_def(id, sim.DOOR_KIND, side, rect, name, float(d.get("hp", door_hp)), places))
		_open_for_people(seg)
		_made[id] = seg
		_doors.append({"id": did, "seg": id, "rect": rect, "side": side})
		i += 1


## The wall a door is in: the town's own record of it, else from where it lies against the lot.
func _door_side(tiles: Array, town_doors: Array) -> String:
	for td in town_doors:
		if bool(td.get("exterior", false)) and not td.tiles.is_empty() and _v2i(td.tiles[0]) == tiles[0] and String(td.side) in SIDES:
			return String(td.side)
	var lot := _rect(layout.get("plot"))
	var mid := Vector2(lot.position) + Vector2(lot.size) * 0.5
	var d := Vector2(tiles[0]) + Vector2(0.5, 0.5) - mid
	if absf(d.y) >= absf(d.x):
		return "N" if d.y < 0.0 else "S"
	return "W" if d.x < 0.0 else "E"


static func _bounds(tiles: Array) -> Rect2i:
	var lo := Vector2i(tiles[0])
	var hi := Vector2i(tiles[0])
	for t in tiles:
		lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
		hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
	return Rect2i(lo, hi - lo + Vector2i(1, 1))


## The dead's places along the outer face of a section: `side` is the way they come from, so they stand `stand` tiles out on that side and face the wall.
static func _places_of(rect: Rect2i, side: String, stand: float) -> Array:
	var out: Array = []
	var x0 := float(rect.position.x)
	var y0 := float(rect.position.y)
	var x1 := float(rect.end.x)
	var y1 := float(rect.end.y)
	var along_x := side == "N" or side == "S"
	var length := (x1 - x0) if along_x else (y1 - y0)
	var n := maxi(1, roundi(length / PLACE_SPACING))
	for k in n:
		var t := (float(k) + 0.5) / float(n) * length
		match side:
			"N":
				out.append({"x": x0 + t, "y": y0 - stand, "ax": x0 + t, "ay": y0 - stand - PLACE_APPROACH, "face": "S"})
			"S":
				out.append({"x": x0 + t, "y": y1 + stand, "ax": x0 + t, "ay": y1 + stand + PLACE_APPROACH, "face": "N"})
			"W":
				out.append({"x": x0 - stand, "y": y0 + t, "ax": x0 - stand - PLACE_APPROACH, "ay": y0 + t, "face": "E"})
			_:
				out.append({"x": x1 + stand, "y": y0 + t, "ax": x1 + stand + PLACE_APPROACH, "ay": y0 + t, "face": "W"})
	return out


func _door_places(rect: Rect2i, side: String) -> Array:
	return _places_of(rect, side, float(_kit_data("door_plank").get("stand", 0.5)))


## The def `sim.add_segment` takes, for a section over `rect`.
func _def(id: int, kind: String, side: String, rect: Rect2i, name: String, hp: float, places: Array) -> Dictionary:
	var tiles: Array = []
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			tiles.append(ty * sim.world.W + tx)
	var along_x := side == "N" or side == "S"
	var x0 := float(rect.position.x)
	var y0 := float(rect.position.y)
	var x1 := float(rect.end.x)
	var y1 := float(rect.end.y)
	var c := Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
	return {
		"id": id, "kind": kind, "side": side, "from": x0 if along_x else y0, "to": x1 if along_x else y1, "name": name, "hp": hp, "tiles": tiles,
		"center": c, "slots": places, "obj": {"cx": c.x, "cy": c.y, "w": x1 - x0, "h": y1 - y0, "a": 0.0}, "art": [],
	}


## People walk through the tiles of a barred door and of the gate (the dead do not): the walking grid and the people's path grid open again.
func _open_for_people(seg) -> void:
	for i in seg.tiles:
		sim.world.solid_p[int(i)] = 0
		sim.path_p.set_solid(int(i), false)


## The gate's tiles open or shut for the dead's grid (people pass either way).
func _set_gate_z(seg, open: bool) -> void:
	for i in seg.tiles:
		sim.world.solid_z[int(i)] = 0 if open else 1
		sim.path_z.set_solid(int(i), not open)
	sim._regions_dirty = true


# ------------------------------------------------------------------- the slots --

## The crew: people alive (the avatar too), the count the stages are by.
func crew_count() -> int:
	var n := 0
	for p in sim.people:
		if not p.dead and not p.turned:
			n += 1
	return n


## Whether a slot's plot is open to the player: its stage is reached, or something of it already stands or is going up. (`Build.refresh_plots` and `Build.why_not`.)
func unlocked(plot: Dictionary) -> bool:
	if String(plot.get("building", "")) != "" or not Dictionary(plot.get("site", {})).is_empty():
		return true
	return crew_count() >= _crew_need(plot.get("unlock", 1))


func _seg_of(slot: Dictionary):
	if String(slot.kind) == "door":
		var d := _door_of(slot)
		return _made.get(int(d.seg)) if not d.is_empty() else null
	return _made.get(int(slot.seg))


## The barred door a door slot is on: the slot's `door`, else the door whose id is in the slot's id, else the one it covers, else the next in order.
func _door_of(slot: Dictionary) -> Dictionary:
	for d in _doors:
		if String(slot.door) != "" and String(slot.door) == String(d.id):
			return d
	for d in _doors:
		if String(slot.id).contains(String(d.id)) or String(slot.id).contains(String(d.id).trim_prefix("door_")):
			return d
	for d in _doors:
		if Rect2i(slot.rect).intersects(Rect2i(d.rect).grow(1)):
			return d
	var k := 0
	for id in _order:
		if String(_slots[id].kind) != "door":
			continue
		if id == slot.id:
			return _doors[k] if k < _doors.size() else {}
		k += 1
	return {}


func _state_of(s: Dictionary) -> String:
	var pl: Dictionary = sim.build.plot(String(s.plot))
	if pl.is_empty():
		return "locked"
	if String(pl.building) != "":
		var seg = _seg_of(s)
		return "broken" if seg != null and int(seg.state) == 3 and String(s.kind) != "tower" and String(s.kind) != "floodlight" else "built"
	if not pl.site.is_empty():
		return "building" if float(pl.site.progress) > 0.0 else "ordered"
	return "open" if unlocked(pl) else "locked"


func _locked_why(s: Dictionary) -> String:
	return "Opens when %d people are here (%d now)" % [int(s.crew), crew_count()]


## The slots as the Build page shows them: [{"id", "kind", "name", "rect", "state": "locked|open|ordered|building|built|broken", "kit", "kit_name", "hp", "max_hp",
## "unlock": {"crew": n}, "why_not", "plot"}]. `kit` is the kit built or going up; `why_not` says why an order cannot be placed now ("" when it can); `plot` is the
## Build plot's id. A fallen slot (broken) can be ordered again.
func slots() -> Array:
	var out: Array = []
	if layout.is_empty():
		return out
	for id in _order:
		var s: Dictionary = _slots[id]
		var st := _state_of(s)
		var pl: Dictionary = sim.build.plot(String(s.plot))
		var kit := ""
		if String(_built.get(id, "")) != "":
			kit = String(_built[id])
		elif not pl.is_empty() and not pl.site.is_empty():
			kit = _kit_of_building(String(pl.site.building))
		var seg = _seg_of(s) if st == "built" or st == "broken" else null
		var why := ""
		match st:
			"locked":
				why = _locked_why(s)
			"ordered", "building":
				why = "Something is already going up here"
			"built":
				why = "It is built already"
		out.append({
			"id": id, "kind": String(s.kind), "name": String(s.name), "rect": Rect2i(s.rect), "state": st, "kit": kit,
			"kit_name": String(_kit_data(kit).get("name", kit)), "hp": float(seg.hp) if seg != null else 0.0,
			"max_hp": float(seg.max_hp) if seg != null else 0.0, "unlock": {"crew": int(s.crew)}, "why_not": why, "plot": String(s.plot),
		})
	return out


## The kits a slot takes: [{"id" (the kit's), "name", "blurb", "scrap", "work" (builder-hours), "hp", "ok", "why"}]; `ok` false with the reason when it cannot be ordered now.
func kits_for(slot_id: String) -> Array:
	var out: Array = []
	var s = _slots.get(slot_id)
	if s == null:
		return out
	var st := _state_of(s)
	for kit in s.kits:
		var bid := _building_for(s, String(kit))
		if bid == "":
			continue
		var b: Dictionary = sim.build.building(bid)
		var k := _kit_data(String(kit))
		var why := ""
		match st:
			"locked":
				why = _locked_why(s)
			"ordered", "building":
				why = "Something is already going up here"
			"built":
				why = "It is built already"
			"broken":
				why = "It needs %d scrap" % int(b.scrap) if float(sim.stock.scrap) + 1.0e-9 < float(b.scrap) else ""
			_:
				why = String(sim.build.why_not(String(s.plot), bid))
		if why != "":
			why = why.substr(0, 1).to_upper() + why.substr(1)
		out.append({
			"id": String(kit), "name": String(b.get("name", k.get("name", kit))), "blurb": String(b.get("blurb", k.get("blurb", ""))), "scrap": int(b.scrap),
			"work": float(b.work), "hp": float(b.get("hp", k.get("hp", 0.0))), "ok": why == "", "why": why,
		})
	return out


## The catalogue entry a kit is on this slot's plot: "kit_<kit>" (the layout's), else the plot's own listed entry for the kit.
func _building_for(s: Dictionary, kit: String) -> String:
	var pl: Dictionary = sim.build.plot(String(s.plot))
	if pl.is_empty():
		return ""
	var listed: Array = pl.get("kits", [])
	for bid in listed:
		var b: Dictionary = sim.build.building(String(bid))
		if not b.is_empty() and (String(b.get("slot_kit", _kit_id(String(bid)))) == kit):
			return String(bid)
	return ""


func _kit_of_building(bid: String) -> String:
	var b: Dictionary = sim.build.building(bid)
	return String(b.get("slot_kit", _kit_id(bid)))


## Orders a kit on a slot (the kit id, "fence"; the catalogue's "kit_fence" is taken as well): pays the scrap and puts the site on the plot, which the builders at its work
## spot finish in the kit's builder-hours. A fallen slot is cleared first. False, and nothing changes, if it cannot be ordered.
func order(slot_id: String, kit_id: String) -> bool:
	var s = _slots.get(slot_id)
	if s == null:
		return false
	var kit := _kit_id(kit_id)
	if not s.kits.has(kit):
		return false
	var bid := _building_for(s, kit)
	if bid == "":
		return false
	var st := _state_of(s)
	if st == "broken":
		if float(sim.stock.scrap) + 1.0e-9 < float(sim.build.building(bid).scrap):
			return false
		_drop(s)
		sim.build.ruin(String(s.plot))    # (what is left of it goes, no scrap back)
	elif st != "open":
		return false
	if not sim.build.order(String(s.plot), bid):
		return false
	sim.events.append({"type": "slot_ordered", "slot": String(slot_id), "kit": kit})
	return true


## Stops an order: all the scrap back if no work was done, else half.
func cancel(slot_id: String) -> bool:
	var s = _slots.get(slot_id)
	if s == null or not (_state_of(s) in ["ordered", "building"]):
		return false
	return sim.build.cancel(String(s.plot))


## Takes down what stands on a slot: half the scrap back (`build.demolish`), the section goes.
func demolish(slot_id: String) -> bool:
	var s = _slots.get(slot_id)
	if s == null or not (_state_of(s) in ["built", "broken"]):
		return false
	return sim.build.demolish(String(s.plot))


## The Build module finished the building on a slot's plot.
func on_built(plot: Dictionary, building_id: String) -> void:
	var s = _slots.get(String(plot.id))
	if s == null:
		for id in _order:
			if String(_slots[id].plot) == String(plot.id):
				s = _slots[id]
	if s == null:
		return
	var kit := _kit_of_building(building_id)
	_built[String(s.id)] = kit
	_lost.erase(String(s.id))
	var seg = null
	match String(s.kind):
		"fence", "gate":
			seg = _make_section(s, kit, float(sim.build.building(building_id).get("hp", _kit_data(kit).get("hp", 100.0))))
		"door":
			_plank(s, kit, 1.0)
	sim.events.append({"type": "slot_built", "slot": String(s.id), "kit": kit})
	var label := String(sim.build.building(building_id).get("name", kit))
	sim.alert("slot-%s" % String(s.id), "info", "%s is up" % label, String(s.name), Vector2(plot.pos), 14.0)
	if seg != null:
		_refresh_build()


## Build took the building of a slot's plot down.
func on_demolished(plot: Dictionary) -> void:
	for id in _order:
		var s: Dictionary = _slots[id]
		if String(s.plot) == String(plot.id):
			_drop(s)
			return


## Takes what a slot has made away (its section, a door's planks) and forgets it was built.
func _drop(s: Dictionary) -> void:
	var id := String(s.id)
	match String(s.kind):
		"fence", "gate":
			var seg = _made.get(int(s.seg))
			if seg != null:
				if String(s.kind) == "gate":
					_gate_open = false
				_made.erase(int(s.seg))
				sim.remove_segment(seg)
		"door":
			_plank(s, String(_built.get(id, "")), -1.0)
	_built.erase(id)
	_lost.erase(id)


## Planks across a door add the kit's hit points to it (sign 1) or take them off again (sign -1).
func _plank(s: Dictionary, kit: String, sign: float) -> void:
	var seg = _seg_of(s)
	if seg == null:
		return
	var bonus := float(_kit_data(kit).get("hp", 0.0)) * sign
	seg.max_hp = maxf(1.0, float(seg.max_hp) + bonus)
	seg.hp = clampf(float(seg.hp) + bonus, 0.0 if sign > 0.0 else 1.0, float(seg.max_hp))
	sim._segment_state(seg)


## Makes the wall section of a fence or gate slot (as `Lots._make_section` does): its tiles shut, the dead's places on the outer side, the world told by `add_segment`.
func _make_section(s: Dictionary, kit: String, hp: float):
	if int(s.seg) < 0:
		return null
	var old = _made.get(int(s.seg))
	if old != null:
		_made.erase(int(s.seg))
		sim.remove_segment(old)
	var rect: Rect2i = s.rect
	var kind := "gate" if String(s.kind) == "gate" else "fence"
	var places = s.places    # (the layout's, which may be none: a run whose outside is shut has no place for the dead; no key: made here)
	if places == null:
		places = _places_of(rect, String(s.side), float(_kit_data(kit).get("stand", 0.55)))
	var seg = sim.add_segment(_def(int(s.seg), kind, String(s.side), rect, String(s.name), hp, places))
	_made[int(s.seg)] = seg
	_wipe_footprint(seg.tiles)
	if kind == "gate":
		_open_for_people(seg)
		if _gate_open:
			_set_gate_z(seg, true)
	return seg


## The dead standing where a section has just gone up are gone with it, and people are put clear of it.
func _wipe_footprint(tiles: Array) -> void:
	var shut := {}
	for i in tiles:
		shut[int(i)] = true
	for z in sim.zombies:
		if z.state == "dead" or z.state == "dying":
			continue
		if shut.has(floori(z.y) * sim.world.W + floori(z.x)):
			z.state = "dying"
			z.fall = 0.0
			if z.slot != null:
				z.slot.who = null
				z.slot = null
	for p in sim.people:
		if p.dead or p.turned or not shut.has(floori(p.y) * sim.world.W + floori(p.x)):
			continue
		var at := _free_near(Vector2(p.x, p.y), shut)
		p.x = at.x
		p.y = at.y
		p.path = []
		p.goal_key = ""


## The middle of the nearest tile that people can stand on and is not in `shut`.
func _free_near(at: Vector2, shut: Dictionary) -> Vector2:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var tx := floori(at.x) + dx
				var ty := floori(at.y) + dy
				if tx < 0 or ty < 0 or tx >= sim.world.W or ty >= sim.world.H:
					continue
				var i: int = ty * sim.world.W + tx
				if not shut.has(i) and int(sim.world.solid_p[i]) == 0:
					return Vector2(float(tx) + 0.5, float(ty) + 0.5)
	return at


# ---------------------------------------------------------------- what stands --

func built_count() -> int:
	return _built.size()


## True while no fence or gate stands: the dead then go for the barred doors. (Nothing is on before the claim.)
func no_outer_wall() -> bool:
	if layout.is_empty():
		return false
	for id in _built:
		var s: Dictionary = _slots.get(id, {})
		if s.is_empty() or not (String(s.kind) == "fence" or String(s.kind) == "gate"):
			continue
		var seg = _made.get(int(s.seg))
		if seg != null and int(seg.state) != 3:
			return false
	return true


func _gate_seg():
	for id in _order:
		var s: Dictionary = _slots[id]
		if String(s.kind) == "gate" and _built.has(id):
			return _made.get(int(s.seg))
	return null


## Whether the gate stands open to the dead (a section that is down is not "open": it is down).
func gate_open() -> bool:
	if not _gate_open:
		return false
	var g = _gate_seg()
	return g != null and int(g.state) != 3


## Opens or shuts the base's gate: {"ok", "open", "why", "line"}. Open, it lets the dead in; people pass it shut or open.
func toggle_gate() -> Dictionary:
	var g = _gate_seg()
	if g == null:
		return {"ok": false, "open": false, "why": "There is no gate", "line": ""}
	if int(g.state) == 3:
		return {"ok": false, "open": false, "why": "The gate is down", "line": ""}
	if not _gate_open:
		_gate_open = true
		_set_gate_z(g, true)
		sim.alert("gate-base", "warn", "The gate is open", "The dead can walk in", Vector2(g.center), 8.0)
	else:
		var shut := {}
		for i in g.tiles:
			shut[int(i)] = true
		for z in sim.zombies:
			if z.state != "dying" and z.state != "dead" and shut.has(floori(z.y) * sim.world.W + floori(z.x)):
				return {"ok": false, "open": true, "why": "The dead are in the gateway", "line": ""}
		_gate_open = false
		_set_gate_z(g, false)
		sim.alert("gate-base", "info", "The gate is shut", "", Vector2(g.center), 4.0)
	sim.events.append({"type": "gate_base", "open": _gate_open})
	return {"ok": true, "open": _gate_open, "why": "", "line": "The gate is open." if _gate_open else "The gate is shut."}


## The sections that stand (the barred doors, the built fence and gate), for a view to draw: [{"id" (the segment's), "slot" (the slot's id, or the door's), "kind"
## "door"|"fence"|"gate", "kit", "rect", "side", "hp", "max_hp", "state" (0 whole to 3 down)}].
func sections() -> Array:
	var out: Array = []
	for d in _doors:
		var seg = _made.get(int(d.seg))
		if seg != null:
			out.append({"id": int(d.seg), "slot": String(d.id), "kind": "door", "kit": "", "rect": Rect2i(d.rect), "side": String(d.side), "hp": float(seg.hp),
				"max_hp": float(seg.max_hp), "state": int(seg.state)})
	for id in _order:
		var s: Dictionary = _slots[id]
		var seg = _made.get(int(s.seg))
		if seg != null and _built.has(id):
			out.append({"id": int(s.seg), "slot": String(id), "kind": String(seg.kind), "kit": String(_built[id]), "rect": Rect2i(s.rect), "side": String(s.side),
				"hp": float(seg.hp), "max_hp": float(seg.max_hp), "state": int(seg.state)})
	return out


# ----------------------------------------------------------------------- update --

func update(dt: float) -> void:
	if not enabled or layout.is_empty():
		return
	_t += dt
	if _t < WATCH_EVERY:
		return
	_t = 0.0
	var n := crew_count()
	if n != _stage_crew:
		var was := _stage_crew
		_stage_crew = n
		_refresh_build()
		if was >= 0 and n > was:
			var fresh := 0
			for id in _order:
				var need: int = _slots[id].crew
				if need > was and need <= n:
					fresh += 1
			if fresh > 0:
				sim.alert("slots-open", "info", "The base can grow", "%d new place%s to build on" % [fresh, "" if fresh == 1 else "s"], null, 12.0)
	for id in _built:
		var s: Dictionary = _slots.get(id, {})
		var seg = _seg_of(s) if not s.is_empty() else null
		if seg == null or String(s.kind) == "tower" or String(s.kind) == "floodlight":
			continue
		var down: bool = int(seg.state) == 3
		if down and not _lost.has(id):
			_lost[id] = true
			sim.events.append({"type": "slot_lost", "slot": String(id), "kit": String(_built[id])})
		elif not down and _lost.has(id):
			_lost.erase(id)
	# a section that was mended up from a breach is shut again on both grids by the colony: people may pass the gate and the doors still
	for sid in _made:
		var seg = _made[sid]
		if int(seg.state) == 3 or seg.tiles.is_empty():
			continue
		if String(seg.kind) == "gate" or String(seg.kind) == sim.DOOR_KIND:
			if int(sim.world.solid_p[int(seg.tiles[0])]) != 0:
				_open_for_people(seg)
		if String(seg.kind) == "gate" and _gate_open and int(sim.world.solid_z[int(seg.tiles[0])]) != 0:
			_set_gate_z(seg, true)


# ------------------------------------------------------------------ the E uses --

## The gate, as something to use from where the avatar stands ("gate_base"): "Open the gate" or "Shut the gate".
func candidates(p) -> Array:
	var out: Array = []
	var g = _gate_seg()
	if g == null or int(g.state) == 3 or p == null:
		return out
	var d := Vector2(p.x, p.y).distance_to(Vector2(g.center))
	if d <= GATE_REACH:
		out.append({"kind": "gate_base", "id": "gate_base", "label": "Shut the gate" if _gate_open else "Open the gate", "pos": Vector2(g.center), "dist": d, "ok": true, "why": ""})
	return out


## E at a candidate: the gate's, else {} (not mine).
func use(c: Dictionary) -> Dictionary:
	if String(c.get("kind", "")) == "gate_base":
		return toggle_gate()
	return {}


# ------------------------------------------------------------------------ saves --

func save() -> Dictionary:
	return {"active": not layout.is_empty(), "built": _built.duplicate(), "gate_open": _gate_open}


func load_state(d: Dictionary) -> void:
	_gate_open = bool(d.get("gate_open", false)) and _gate_seg() != null
	var g = _gate_seg()
	if g != null:
		_set_gate_z(g, _gate_open and int(g.state) != 3)
	_lost.clear()
	for id in _built:
		var s: Dictionary = _slots.get(id, {})
		var seg = _seg_of(s) if not s.is_empty() else null
		if seg != null and int(seg.state) == 3:
			_lost[id] = true    # (a section that was down when it was saved is not news again)
	_stage_crew = -1
	_refresh_build()


## Before the save is read (TownSim.prepare_load, hook H11): the barred doors and the sections of the slots that were built are made again by their ids from the layout the
## base has put in place, so that `SaveGame._parse` finds them (their hit points are the save's). A save with no base takes everything down. Returns what stood, for `restore`.
func prepare_load(data: Dictionary):
	var before := _snapshot()
	var mods = data.get("modules", {})
	var mine = mods.get("perimeter", {}) if mods is Dictionary else {}
	if not mine is Dictionary or not bool(mine.get("active", false)):
		_clear_all()
		return before
	var lay: Dictionary = {}
	var b = sim.get("base")
	if b != null and b.get("layout") is Dictionary:
		lay = b.layout
	if lay.is_empty():
		lay = layout
	if lay.is_empty():
		return before
	activate(lay)
	var built = mine.get("built", {})
	if built is Dictionary:
		for id in built:
			var s = _slots.get(String(id))
			if s == null:
				continue
			var kit := String(built[id])
			_built[String(id)] = kit
			if String(s.kind) == "fence" or String(s.kind) == "gate":
				var hp := float(_kit_data(kit).get("hp", 100.0))
				_make_section(s, kit, hp)
	_gate_open = bool(mine.get("gate_open", false))
	return before


func _snapshot() -> Dictionary:
	var segs: Array = []
	for id in _made:
		var seg = _made[id]
		segs.append({"id": int(id), "hp": float(seg.hp), "max_hp": float(seg.max_hp), "state": int(seg.state)})
	return {"layout": layout, "built": _built.duplicate(), "gate_open": _gate_open, "segs": segs}


## Puts what stood before `prepare_load` back, as damaged (the save was no good).
func restore(before) -> void:
	if not before is Dictionary:
		return
	var lay: Dictionary = before.get("layout", {})
	_clear_all()
	if lay.is_empty():
		return
	activate(lay)
	for id in before.built:
		var s = _slots.get(String(id))
		if s == null:
			continue
		_built[String(id)] = String(before.built[id])
		if String(s.kind) == "fence" or String(s.kind) == "gate":
			_make_section(s, String(before.built[id]), 100.0)
	_gate_open = bool(before.get("gate_open", false))
	for e in before.segs:
		var seg = _made.get(int(e.id))
		if seg == null:
			continue
		seg.max_hp = float(e.max_hp)
		seg.hp = float(e.hp)
		if int(e.state) != int(seg.state):
			seg.state = int(e.state)
			if seg.state == 3:
				sim.open_segment(seg, true)
			if sim.on_segment_change.is_valid():
				sim.on_segment_change.call(seg)
	load_state({"gate_open": _gate_open})
