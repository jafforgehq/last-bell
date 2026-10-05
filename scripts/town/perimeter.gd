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
## PROJECTS. What the player orders is not a slot but a PROJECT (assets/data/base_kits.json, `projects`): the front fence, the side fences, the back fence, the gate, a
## watchtower (and a second one), the floodlights, the door planks, and 'reinforce the fences' (the built plain fences made strong, one section at a time, each standing
## while it is done: an upgrade entry of the Build module, `upgrade_of`). `projects()` is what the Build page shows (state, cost, time, why not), `next_project()` the
## recommended one, `order_project(id)` orders every slot of it that the scrap pays for, front to back (the builders work the orders in the order they were given),
## `cancel_project(id)` takes the orders back, `order_affordable()` is the page's "build everything I can afford". The slot calls (`order`, `cancel`, `demolish`) stay: the
## projects are made of them.
##
## STAGES. A slot opens by the crew count (people alive, the avatar too): the plot's `unlock` {"crew": n}. `unlocked(plot)` is what `Build.refresh_plots` and
## `Build.why_not` ask; `update` bumps the Build page when the count changes.
##
## SAVES. `save()` keeps whether a base is on, the built slots (slot id to kit id) and the gate's state; the sections' hit points are the save's own (`segments`).
## `prepare_load` (hook H11, before the save is read) re-makes the doors and the built slots' sections BY ID from the layout that `base.prepare_load` put in place,
## so that `SaveGame._parse` finds every section; `restore` puts the old ones back when the save is refused.
##
## Events: {"type": "slot_ordered"|"slot_built"|"slot_lost", "slot": id, "kit": kit id} (plan 2.4), {"type": "gate_base", "open": bool},
## {"type": "project_done", "project": id, "line": "The front fence is up"} (the last section of a project is up).
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

## The kits file: {"kits": {id: {...}}, "unlock": {...}, "layout": {...}, "projects": [...]} (empty without a file).
static func load_kits(path: String = "") -> Dictionary:
	var p := path if path != "" else kits_path
	if not _cache.has(p):
		var out := {"kits": {}, "unlock": {}, "layout": {}, "projects": []}
		var raw = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		if raw is Dictionary:
			for k in raw.get("kits", {}):
				out.kits[String(k)] = raw.kits[k]
			out["unlock"] = raw.get("unlock", {})
			out["layout"] = raw.get("layout", {})
			if raw.get("projects") is Array:
				out["projects"] = raw.projects
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
			"plot": String(r.get("plot", r.id)), "door": String(r.get("door", "")), "seg": -1, "role": String(r.get("role", "")), "project": "",
		}
		if (s.kind == "fence" or s.kind == "gate") and next_seg <= LAST_SLOT_ID:
			s.seg = next_seg
			next_seg += 1
		_slots[s.id] = s
		_order.append(s.id)
	_index_projects()


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
	_defs = []
	_proj_slots = {}
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


## The slots, each as {"id", "kind", "name", "rect", "state": "locked|open|ordered|building|built|broken", "kit", "kit_name", "hp", "max_hp",
## "unlock": {"crew": n}, "why_not", "plot", "project", "up"}. `kit` is the kit built or going up; `why_not` says why an order cannot be placed now ("" when it can); `plot` is the
## Build plot's id; `project` the id of the project the slot is in; `up` is "ordered" or "building" while a fence that stands is being reinforced ("" otherwise). A fallen
## slot (broken) can be ordered again.
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
		var up := ""
		if st == "built" and not pl.is_empty() and not pl.site.is_empty():
			up = "building" if float(pl.site.progress) > 0.0 else "ordered"
		out.append({
			"id": id, "kind": String(s.kind), "name": String(s.name), "rect": Rect2i(s.rect), "state": st, "kit": kit,
			"kit_name": String(_kit_data(kit).get("name", kit)), "hp": float(seg.hp) if seg != null else 0.0,
			"max_hp": float(seg.max_hp) if seg != null else 0.0, "unlock": {"crew": int(s.crew)}, "why_not": why, "plot": String(s.plot),
			"project": String(s.project), "up": up,
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
		if not b.is_empty() and not b.has("upgrade_of") and (String(b.get("slot_kit", _kit_id(String(bid)))) == kit):
			return String(bid)
	return ""


## The catalogue entry that makes the plain kit that stands on a slot into `kit` ("" when there is none): the upgrade entry of the plot.
func _upgrade_for(s: Dictionary, kit: String) -> String:
	var pl: Dictionary = sim.build.plot(String(s.plot))
	if pl.is_empty():
		return ""
	for bid in pl.get("kits", []):
		var b: Dictionary = sim.build.building(String(bid))
		if not b.is_empty() and b.has("upgrade_of") and String(b.get("slot_kit", "")) == kit and String(b.upgrade_of) == String(pl.building):
			return String(bid)
	return ""


## The hit points of a kit on a slot: its catalogue entry's (a fence section's are in proportion to its length), else the kit's.
func _slot_hp(s: Dictionary, kit: String) -> float:
	var bid := _building_for(s, kit)
	if bid != "":
		return float(sim.build.building(bid).get("hp", _kit_data(kit).get("hp", 100.0)))
	return float(_kit_data(kit).get("hp", 100.0))


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
	var st := _state_of(s)
	if st == "built" and String(_built.get(slot_id, "")) != kit and String(s.kind) == "fence":
		# a plain fence that stands is made strong in place (the upgrade entry of its plot: the fence stands while it is done)
		var up := _upgrade_for(s, kit)
		if up == "" or not sim.build.plot(String(s.plot)).site.is_empty() or not sim.build.order(String(s.plot), up):
			return false
		sim.events.append({"type": "slot_ordered", "slot": String(slot_id), "kit": kit})
		return true
	var bid := _building_for(s, kit)
	if bid == "":
		return false
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


## Stops an order: all the scrap back if no work was done, else half. (Also the upgrade of a fence that stands: the fence is left as it was.)
func cancel(slot_id: String) -> bool:
	var s = _slots.get(slot_id)
	if s == null or not (_state_of(s) in ["ordered", "building", "built"]):
		return false
	if not sim.build.plot(String(s.plot)).site.is_empty():
		return sim.build.cancel(String(s.plot))
	return false


## Takes down what stands on a slot: half the scrap back (`build.demolish`), the section goes (an upgrade that is going up on it is taken back first).
func demolish(slot_id: String) -> bool:
	var s = _slots.get(slot_id)
	if s == null or not (_state_of(s) in ["built", "broken"]):
		return false
	if not sim.build.plot(String(s.plot)).site.is_empty():
		sim.build.cancel(String(s.plot))
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
	var upgraded: bool = String(_built.get(String(s.id), "")) != "" and sim.build.building(building_id).has("upgrade_of")
	_built[String(s.id)] = kit
	_lost.erase(String(s.id))
	var seg = null
	match String(s.kind):
		"fence", "gate":
			seg = _make_section(s, kit, float(sim.build.building(building_id).get("hp", _kit_data(kit).get("hp", 100.0))))
		"door":
			_plank(s, kit, 1.0)
	sim.events.append({"type": "slot_built", "slot": String(s.id), "kit": kit})
	if seg != null:
		_refresh_build()
	# a project whose last section this was is news; the sections of one that has more than one are not (one line for the lot)
	for def in _defs:
		var pid := String(def.id)
		if bool(def.get("upgrade", false)) != upgraded or not (_proj_slots.get(pid, []) as Array).has(String(s.id)):
			continue
		var info := _project_info(def)
		if String(info.state) == "done":
			var line := String(def.get("done", "%s is up" % String(def.name)))
			sim.events.append({"type": "project_done", "project": pid, "line": line})
			sim.alert("project-%s" % pid, "info", line, "", project_center(pid), 14.0)


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


# --------------------------------------------------------------------- projects --

## A project takes this much longer than the hours of work in it say: the builders walk from one section to the next.
const WALK_FACTOR := 1.15
const NUMBER_WORDS := ["no", "one", "two", "three", "four", "five", "six"]

## The projects this base has (base_kits.json's, in the page's order) and, for each, its slots' ids from the front of the base to the back.
var _defs: Array = []
var _proj_slots := {}


## The role of a slot of a layout that gives none (an older layout): the unlock table's key.
func _role_of(r: Dictionary) -> String:
	match String(r.get("kind", "fence")):
		"gate":
			return "gate"
		"door":
			return "door"
		"tower":
			return "tower"
		"floodlight":
			return "floodlight"
	var side := String(r.get("side", "N"))
	var front := String(layout.get("front", "S"))
	if side == front:
		return "front"
	if (side == "N" and front == "S") or (side == "S" and front == "N") or (side == "E" and front == "W") or (side == "W" and front == "E"):
		return "back"
	return "side"


## Which slots are in which project (each slot of the layout is in one, by its role), each project's slots front to back (nearest the gate first, so that the sections the dead
## come to first go up first), and `_defs`, the projects that have slots.
func _index_projects() -> void:
	_defs = []
	_proj_slots = {}
	var from := _front_point()
	for def in load_kits().get("projects", []):
		if not def is Dictionary:
			continue
		var ids: Array = []
		var upgrade := bool(def.get("upgrade", false))
		for sid in _order:
			var s: Dictionary = _slots[sid]
			if String(s.role) == "":
				s["role"] = _role_of({"kind": s.kind, "side": s.side})
			if Array(def.get("roles", [])).has(String(s.role)) and (not upgrade or String(s.kind) == "fence"):
				ids.append(String(sid))
				if not upgrade:
					s["project"] = String(def.id)
		if ids.is_empty():
			continue
		ids.sort_custom(func(a, b):
			var da := from.distance_to(Vector2(Rect2i(_slots[a].rect).get_center()))
			var db := from.distance_to(Vector2(Rect2i(_slots[b].rect).get_center()))
			return da < db - 0.001 or (absf(da - db) <= 0.001 and _order.find(a) < _order.find(b)))
		_proj_slots[String(def.id)] = ids
		_defs.append(def)


## The front of the base: the middle of the gate, else the layout's yard middle.
func _front_point() -> Vector2:
	for sid in _order:
		if String(_slots[sid].kind) == "gate":
			return Vector2(Rect2i(_slots[sid].rect).get_center())
	var ym = layout.get("yard_middle")
	return Vector2(ym) if ym is Vector2 else Vector2.ZERO


func _def_of(project_id: String) -> Dictionary:
	for def in _defs:
		if String(def.id) == project_id:
			return def
	return {}


## The projects' ids in the page's order (the recommended order).
func project_ids() -> Array:
	var out: Array = []
	for def in _defs:
		out.append(String(def.id))
	return out


## A project's name ("" for no such project).
func project_name(project_id: String) -> String:
	return String(_def_of(project_id).get("name", ""))


## The ids of a project's slots, front to back ([] for no such project).
func project_slot_ids(project_id: String) -> Array:
	return (_proj_slots.get(project_id, []) as Array).duplicate()


## The middle of a project's sections (tiles).
func project_center(project_id: String) -> Vector2:
	var box := Rect2()
	var first := true
	for sid in _proj_slots.get(project_id, []):
		var r := Rect2(Vector2(Rect2i(_slots[sid].rect).position), Vector2(Rect2i(_slots[sid].rect).size))
		box = r if first else box.merge(r)
		first = false
	return box.get_center()


## How many people (the avatar too) it takes before a project opens: its slots' stage (the first of them to open), or the project's own `crew` (the upgrade).
func _project_need(def: Dictionary) -> int:
	if bool(def.get("upgrade", false)):
		return int(def.get("crew", 3))
	var need := 99
	for sid in _proj_slots.get(String(def.id), []):
		need = mini(need, int(_slots[sid].crew))
	return need if need < 99 else 1


## "section" for the fence kits, "door" for the planks...: what one slot of a project is called.
static func _unit(kit: String) -> String:
	match kit:
		"fence", "fence_strong":
			return "section"
		"door_plank":
			return "door"
		"floodlight":
			return "floodlight"
		"tower":
			return "tower"
	return "part"


## The people who build: those on the Builders job, else (nobody is on it yet: the job is given when there is a site) the people of the house who could, at most two.
func _builder_count() -> int:
	var n := 0
	var jobs = sim.get("jobs")
	if jobs != null:
		for p in jobs.crew_of("builders"):
			if not p.player:
				n += 1
	if n == 0:
		for p in sim.people:
			if not p.dead and not p.turned and not p.player and p.away == null:
				n += 1
		n = mini(n, 2)
	return n


## Builder-hours a builder does in a game hour, on the average of those on the job (the base rate when nobody is).
func _builder_rate() -> float:
	var jobs = sim.get("jobs")
	var sum := 0.0
	var k := 0
	if jobs != null:
		for p in jobs.crew_of("builders"):
			if not p.player:
				sum += float(sim.build.rate(p))
				k += 1
	return sum / float(k) if k > 0 else float(sim.build.RATE_BASE)


## "about 40 minutes", "about an hour and a half", "about 3 hours" for game minutes.
static func time_text(minutes: float) -> String:
	if minutes < 12.0:
		return "a few minutes"
	if minutes < 57.0:
		return "about %d minutes" % (roundi(minutes / 5.0) * 5)
	if minutes >= 170.0:
		return "about %d hours" % roundi(minutes / 60.0)
	var halves := roundi(minutes / 30.0)
	var hours := halves >> 1
	var half := (halves & 1) == 1
	if hours == 0:
		return "about half an hour"
	if hours == 1:
		return "about an hour and a half" if half else "about an hour"
	return ("about %d and a half hours" % hours) if half else ("about %d hours" % hours)


static func builders_text(n: int) -> String:
	return "%s builder%s" % [NUMBER_WORDS[n] if n < NUMBER_WORDS.size() else str(n), "" if n == 1 else "s"]


## What a project is now: {"id", "name", "noun", "button", "icon", "gives", "unit", "state": "locked|ready|building|done", "slots": [ids], "n" (slots in it), "built", "going"
## (ordered or going up), "open" (could be ordered now), "fallen", "locked", "need_crew", "scrap" (the price of what is left to order), "work" (builder-hours of all that is
## left to do: the ordered too), "first_scrap" (the price of the first section to order), "can_n" and "pay" (how many sections of it the scrap pays for now, and what they cost),
## "minutes" (game minutes the rest takes, with `builders` builders: 0 when nobody can build it yet), "time" ("about 40 minutes": "" when nobody can build it or there is
## nothing left to do), "builders_text" ("two builders") and "spills" (it is longer than the daylight left: the builders carry on tomorrow), "why" (why it cannot be ordered now, "" when it can),
## "progress" (0..1 of the sections up, the ones going up counted by the work done), "todo" ([{"slot", "kit", "scrap", "work"}] in the order they are ordered)}.
func _project_info(def: Dictionary) -> Dictionary:
	var pid := String(def.id)
	var upgrade := bool(def.get("upgrade", false))
	var n := 0
	var built := 0
	var going := 0
	var fallen := 0
	var locked := 0
	var todo: Array = []
	var work_todo := 0.0
	var work_going := 0.0
	var share_going := 0.0
	var unit_kit := String(def.get("kit", ""))
	for sid in _proj_slots.get(pid, []):
		var s: Dictionary = _slots[sid]
		var st := _state_of(s)
		var pl: Dictionary = sim.build.plot(String(s.plot))
		if upgrade:
			var have := String(_built.get(sid, ""))
			if st != "built" or have == "":
				continue
			if have == unit_kit and pl.site.is_empty():
				n += 1
				built += 1
			elif have != unit_kit:
				n += 1
				if not pl.site.is_empty():
					going += 1
					work_going += maxf(0.0, float(pl.site.work) - float(pl.site.progress))
					share_going += sim.build.progress_of(String(s.plot))
				else:
					var up := _upgrade_for(s, unit_kit)
					if up != "":
						var b: Dictionary = sim.build.building(up)
						todo.append({"slot": String(sid), "kit": unit_kit, "scrap": int(b.scrap), "work": float(b.work)})
						work_todo += float(b.work)
			continue
		n += 1
		match st:
			"built":
				built += 1
			"ordered", "building":
				going += 1
				work_going += maxf(0.0, float(pl.site.work) - float(pl.site.progress))
				share_going += sim.build.progress_of(String(s.plot))
			"locked":
				locked += 1
			_:    # open, or broken (a fallen one is ordered again, as the kind it was)
				var kit := unit_kit
				if st == "broken":
					fallen += 1
					var had := String(_built.get(sid, ""))
					if had != "" and s.kits.has(had):
						kit = had
				var bid := _building_for(s, kit)
				if bid == "":
					continue
				var b: Dictionary = sim.build.building(bid)
				todo.append({"slot": String(sid), "kit": kit, "scrap": int(b.scrap), "work": float(b.work)})
				work_todo += float(b.work)
	var need := _project_need(def)
	var crew := crew_count()
	var state := "ready"
	var why := ""
	if going > 0:
		state = "building"
	elif not todo.is_empty():
		state = "ready"
	elif n > 0 and built == n:
		state = "done"
	else:
		state = "locked"
	if state == "locked" or (state == "ready" and crew < need and built + fallen == 0 and upgrade):
		if upgrade and n == 0:
			why = "Build a fence first"
		else:
			why = "Opens when %d people are here (%d now)" % [need, crew]
		state = "locked"
		todo = []
	var scrap_all := 0
	var budget := float(sim.stock.scrap)
	var can_n := 0
	var pay := 0
	var stopped := false
	for t in todo:
		scrap_all += int(t.scrap)
		if not stopped and budget + 1.0e-9 >= float(t.scrap):
			can_n += 1
			pay += int(t.scrap)
			budget -= float(t.scrap)
		else:
			stopped = true
	var first_scrap: int = int(todo[0].scrap) if not todo.is_empty() else 0
	var builders := _builder_count()
	var hours := work_todo + work_going
	var minutes := hours / (float(builders) * _builder_rate()) * 60.0 * WALK_FACTOR if builders > 0 and hours > 0.0 else 0.0
	var time := time_text(minutes) if hours > 0.0 and builders > 0 else ""
	# the builders work by day: a project that is longer than the daylight left carries on into tomorrow
	var spills := false
	if time != "":
		var seasons = sim.get("seasons")
		var left := float(seasons.dusk_hour()) - float(sim.hour) if seasons != null and String(sim.phase) == "day" else 0.0
		spills = minutes / 60.0 > left
	if state == "ready" and can_n == 0:
		why = "Needs %d scrap" % first_scrap
	return {
		"id": pid, "name": String(def.name), "noun": String(def.get("noun", String(def.name).to_lower())), "icon": String(def.get("icon", "fence")),
		"button": String(def.get("button", "Build %s" % String(def.get("noun", String(def.name).to_lower())))), "gives": String(def.get("gives", "")),
		"done_line": String(def.get("done", "")), "unit": _unit(unit_kit), "state": state, "slots": (_proj_slots.get(pid, []) as Array).duplicate(), "n": n, "built": built,
		"going": going, "open": todo.size(), "fallen": fallen, "locked": locked, "need_crew": need, "scrap": scrap_all, "work": hours, "first_scrap": first_scrap,
		"can_n": can_n, "pay": pay, "minutes": minutes, "builders": builders, "time": time, "builders_text": builders_text(builders), "spills": spills, "why": why, "recommended": false,
		"progress": clampf((float(built) + share_going) / float(maxi(n, 1)), 0.0, 1.0), "todo": todo,
	}


## The projects as the Build page shows them (see `_project_info`), in the recommended order; the one to do next has "recommended" true.
func projects() -> Array:
	var out: Array = []
	if layout.is_empty():
		return out
	for def in _defs:
		out.append(_project_info(def))
	var next := _next_of(out)
	for info in out:
		info["recommended"] = String(info.id) == next
	return out


## The id of the project to do next ("" when there is none): a fallen section first, else the first project in the order that can be ordered (whether the scrap is there or not).
func next_project() -> String:
	var infos: Array = []
	for def in _defs:
		infos.append(_project_info(def))
	return _next_of(infos)


func _next_of(infos: Array) -> String:
	for info in infos:
		if String(info.state) == "ready" and int(info.fallen) > 0:
			return String(info.id)
	for info in infos:
		if String(info.state) == "ready":
			return String(info.id)
	return ""


## Orders what a project still needs, front to back, as far as the scrap above `reserve` pays: {"ok" (something was ordered), "project", "ordered" (sections), "of" (how many it
## needed), "scrap" (spent), "left" (not ordered), "need" (scrap the rest costs), "why", "line" (what to say: "Ordered the front fence: 21 scrap.")}.
func order_project(project_id: String, reserve: float = 0.0) -> Dictionary:
	var out := {"ok": false, "project": project_id, "ordered": 0, "of": 0, "scrap": 0, "left": 0, "need": 0, "why": "", "line": ""}
	var def := _def_of(project_id)
	if def.is_empty():
		out.why = "There is no such project"
		out.line = String(out.why)
		return out
	var info := _project_info(def)
	match String(info.state):
		"locked":
			out.why = String(info.why)
		"done":
			out.why = "It is built already"
		"building":
			out.why = "It is going up already"
	if String(out.why) != "":
		out.line = String(out.why) + "."
		return out
	var todo: Array = info.todo
	out.of = todo.size()
	var budget := float(sim.stock.scrap) - reserve
	var k := 0
	for t in todo:
		if budget + 1.0e-9 < float(t.scrap):
			break
		k += 1
		if order(String(t.slot), String(t.kit)):
			out.ordered = int(out.ordered) + 1
			out.scrap = int(out.scrap) + int(t.scrap)
			budget -= float(t.scrap)
	out.left = todo.size() - int(out.ordered)
	for i in range(k, todo.size()):
		out.need = int(out.need) + int(todo[i].scrap)
	out.ok = int(out.ordered) > 0
	var noun := String(info.noun)
	if not bool(out.ok):
		out.why = "Needs %d scrap" % int(info.first_scrap)
		out.line = String(out.why) + ("." if reserve <= 0.0 else " (and the %d kept back)." % roundi(reserve))
	elif int(out.left) == 0:
		out.line = "Ordered %s: %d scrap." % [noun, int(out.scrap)]
	else:
		out.line = "Ordered %d of %d %ss of %s (%d scrap). The rest needs %d more." % [int(out.ordered), int(out.of), String(info.unit), noun, int(out.scrap), maxi(1, int(out.need) - roundi(budget))]
	return out


## Takes back every order of a project that has not been built yet (a reinforcement that is going up leaves the fence as it was): {"ok", "cancelled", "line"}.
func cancel_project(project_id: String) -> Dictionary:
	var out := {"ok": false, "cancelled": 0, "line": "There is nothing to take back."}
	for sid in _proj_slots.get(project_id, []):
		var s: Dictionary = _slots[sid]
		var pl: Dictionary = sim.build.plot(String(s.plot))
		if pl.is_empty() or pl.site.is_empty():
			continue
		if bool(_def_of(project_id).get("upgrade", false)) != (String(pl.building) != ""):
			continue    # (a plain section's order is not the reinforcement's, and the other way round)
		if sim.build.cancel(String(s.plot)):
			out.cancelled = int(out.cancelled) + 1
	if int(out.cancelled) > 0:
		out.ok = true
		out.line = "Order taken back. The scrap comes back, half of it where work had begun."
	return out


## The page's "build everything I can afford": every project that can be ordered, in the recommended order, as far as the scrap above `reserve` goes: {"ok", "ordered" (sections),
## "scrap", "projects" (names), "line"}.
func order_affordable(reserve: float = 0.0) -> Dictionary:
	var out := {"ok": false, "ordered": 0, "scrap": 0, "projects": [], "line": ""}
	var first_need := -1
	var first_noun := ""
	for def in _defs:
		var info := _project_info(def)
		if String(info.state) != "ready":
			continue
		if first_need < 0:
			first_need = int(info.first_scrap)
			first_noun = String(info.noun)
		var r := order_project(String(def.id), reserve)
		if bool(r.ok):
			out.ordered = int(out.ordered) + int(r.ordered)
			out.scrap = int(out.scrap) + int(r.scrap)
			(out.projects as Array).append(String(info.noun))
	out.ok = int(out.ordered) > 0
	if bool(out.ok):
		out.line = "Ordered: %s. %d scrap." % [", ".join(out.projects), int(out.scrap)]
	elif first_need < 0:
		out.line = "There is nothing left to order."
	else:
		out.line = "Nothing you can pay for yet: %s needs %d scrap." % [first_noun, first_need]
	return out


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
			var fresh: Array = []
			for def in _defs:
				var need := _project_need(def)
				if need > was and need <= n:
					fresh.append(String(def.name).to_lower())
			if not fresh.is_empty():
				sim.alert("slots-open", "info", "The base can grow", "On the Build page: %s" % ", ".join(fresh), null, 12.0)
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
				_make_section(s, kit, _slot_hp(s, kit))
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
			_make_section(s, String(before.built[id]), _slot_hp(s, String(before.built[id])))
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
