## The lots (round 9): the base grows from the yard to the streets round it. The map is a block, the
## compound in a ring of streets that is closed by rows of buildings and open at ten mouths (where
## the dead come in). A **lot** is a part of that ring the colony takes: claiming it (scrap, a day,
## and some of the town's places cleared: assets/data/lots.json) opens the Main gate to people (the
## dead stay out), puts the lot's **ring plots** on the Build screen (buildings, as in the yard) and
## its **mouths** (wall plots: a wall of the compound's own kinds across a street, built by the
## Builders like a building and, when it stands, a wall section of its own, with health, damage
## states and places for the dead; `Build` does the ordering and the work, this module makes the
## section). A lot is **sealed** when every one of its mouths has a wall that stands.
##
## A building in a claimed lot that is not sealed risks being ruined at the bell (RAID_RISK each).
##
## Only the settlement game has lots (`on`: a small start with the data present); in the classic
## start every question has the old answer and nothing exists.
##
## SAVES. `save()` keeps what is claimed and the walls that were built, in the order they were built;
## `prepare_load` (called by the save loader before it reads the wall sections) puts exactly those
## sections back, `restore` undoes that if the save turns out to be bad.
##
## Events: {"type": "lot", "lot": id, "what": "claimed"|"sealed"}, {"type": "wall", "mouth": id}
## (a mouth's wall is finished), {"type": "ruined", "plot": id, "building": id}.
extends RefCounted

const DATA_PATH := "res://assets/data/lots.json"
## Where the data is read from (tests may point it at another file).
static var data_path := DATA_PATH
static var _cache := {}

## A wall section made here has an id of this plus its mouth's index in the data.
const FIRST_SEGMENT_ID := 100
## A building of a claimed lot may be ruined at the bell: this is its chance when every street is open,
## less by the share of the ten streets that are shut (the ring is one open space: the dead who get in at
## any mouth that is open reach every lot).
const RAID_RISK := 0.06
## How far in front of a wall's inner face the places of the dead are in the data (a container's: the data's slots
## are drawn for it); a thinner kit has its own `stand` and its slots move by the difference.
const SLOT_STAND := 2.74
## The standing order keeps this much scrap back when it pays for a wall, and looks again this often (seconds).
const AUTO_KEEP := 5.0
const AUTO_EVERY := 2.0
## A lot that has just been sealed lifts everyone's mood by this much unless the data says another figure.
const SEALED_MORALE := 3.0

var sim
## Whether this run has lots (a settlement game, with data).
var on := false
## Lot id to the day it was claimed.
var claimed_on := {}
var _lots: Array = []
var _lot_by_id := {}
var _mouths: Array = []
var _mouth_by_id := {}
var _kits := {}
var _ring: Array = []
var _passage := -1
## [{"mouth": id, "kit": id}] in the order the walls were finished.
var _built: Array = []
var _passage_open := false
var _raid_day := 0
var _sealed := {}
## Lot id to true: the standing order to wall the lot's streets one after another as the scrap allows.
var auto_on := {}
var _auto_t := 0.0


func setup(s) -> void:
	sim = s
	_load()


## The data as the other modules read it: {"lots", "mouths", "kits", "plots", "passage"} (all empty without a file).
static func load_data(path: String = "") -> Dictionary:
	var p := path if path != "" else data_path
	if not _cache.has(p):
		var out := {"lots": [], "mouths": [], "kits": {}, "plots": [], "passage": -1}
		var raw = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		if raw is Dictionary:
			for r in raw.get("lots", []):
				if r is Dictionary and String(r.get("id", "")) != "":
					var l: Dictionary = r.duplicate(true)
					l["claim"] = r.get("claim", {})
					l["mouths"] = r.get("mouths", [])
					l["plots"] = r.get("plots", [])
					out.lots.append(l)
			var index := 0
			for r in raw.get("mouths", []):
				if r is Dictionary and String(r.get("id", "")) != "":
					var m: Dictionary = r.duplicate(true)
					m["index"] = index
					m["center"] = Vector2(float(r.center[0]), float(r.center[1]))
					m["length"] = float(r.get("length", 0.0))
					m["dir"] = String(r.get("dir", "h"))
					m["kits"] = r.get("kits", [])
					m["post"] = r.get("post", {})
					m["slots"] = r.get("slots", [])
					out.mouths.append(m)
					index += 1
			var kits = raw.get("kits", {})
			if kits is Dictionary:
				for k in kits:
					var kit: Dictionary = kits[k].duplicate(true)
					kit["id"] = String(k)
					kit["hp"] = float(kit.get("hp", 100.0))
					kit["scrap"] = int(kit.get("scrap", 10))
					kit["work"] = float(kit.get("work", 10.0))
					kit["length"] = float(kit.get("length", 1.0))
					out.kits[String(k)] = kit
			for r in raw.get("plots", []):
				if r is Dictionary and String(r.get("id", "")) != "":
					out.plots.append(r.duplicate(true))
			out["passage"] = int(raw.get("passage", -1))
		_cache[p] = out
	return _cache[p]


func _load() -> void:
	var d := load_data()
	_lots = d.lots
	_mouths = d.mouths
	_kits = d.kits
	_ring = d.plots
	_passage = int(d.passage)
	_lot_by_id.clear()
	for l in _lots:
		_lot_by_id[String(l.id)] = l
	_mouth_by_id.clear()
	for m in _mouths:
		_mouth_by_id[String(m.id)] = m


func start() -> void:
	_remove_all_walls()
	_close_passage()
	on = false
	claimed_on.clear()
	_built.clear()
	_passage_open = false
	_raid_day = 0
	_sealed.clear()
	auto_on.clear()
	_auto_t = 0.0
	# a run begun on a sim that had lots forgets their plots and posts
	if sim.build != null:
		sim.build._visible_dirty = true
	if sim.jobs != null:
		sim.jobs.set_extra_posts([])


## Called once a run has been set up: the settlement game (the small start) has lots, if there is data.
func begin() -> void:
	on = sim.recruits.small and not _lots.is_empty() and not _mouths.is_empty()


func update(dt: float) -> void:
	if not on or claimed_on.is_empty():
		return
	_auto_walls(dt)
	if sim.bell_rung and sim.day != _raid_day:
		_raid_day = sim.day
		_raid()
	_check_sealed()


# ------------------------------------------------------------------- the data --

func lots() -> Array:
	return _lots


func lot(id: String) -> Dictionary:
	return _lot_by_id.get(id, {})


func mouths() -> Array:
	return _mouths


func mouth(id: String) -> Dictionary:
	return _mouth_by_id.get(id, {})


## The mouths of a lot, in the data's order.
func mouths_of(lot_id: String) -> Array:
	var out: Array = []
	for m in _mouths:
		if String(m.get("lot", "")) == lot_id:
			out.append(m)
	return out


func kits() -> Dictionary:
	return _kits


## The kit a wall plot's building id names ("wall_<kit>"), or {}.
func kit(id: String) -> Dictionary:
	return _kits.get(id, {})


## The kits that can be put across this mouth, as catalogue ids ("wall_<kit>").
func kits_for(mouth_id: String) -> Array:
	var out: Array = []
	var m := mouth(mouth_id)
	for k in m.get("kits", []):
		if _kits.has(String(k)):
			out.append("wall_%s" % String(k))
	return out


## The lot a plot (ring or mouth) belongs to, or "".
func lot_of_plot(plot_id: String) -> String:
	var pl: Dictionary = sim.build.plot(plot_id)
	return String(pl.get("lot", ""))


# ---------------------------------------------------------------------- claim --

func claimed(id: String) -> bool:
	return claimed_on.has(id)


## Whether a plot (a ring plot or a mouth) can be seen and used: it belongs to a lot that is claimed.
func plot_open(pl: Dictionary) -> bool:
	var l := String(pl.get("lot", ""))
	return l == "" or (on and claimed_on.has(l))


## Why a lot cannot be claimed now ("" when it can).
func why_not_claim(id: String) -> String:
	var l := lot(id)
	if not on or l.is_empty():
		return "there is no such lot"
	if claimed_on.has(id):
		return "it is yours already"
	var c: Dictionary = l.claim
	if sim.day < int(c.get("day", 0)):
		return "not before day %d" % int(c.get("day", 0))
	var need := int(c.get("cleared", 0))
	if need > 0 and int(sim.town.cleared_count()) < need:
		return "clear %d place%s on the town board first (%d so far)" % [need, "" if need == 1 else "s", int(sim.town.cleared_count())]
	if float(sim.stock.scrap) + 1.0e-9 < float(c.get("scrap", 0)):
		return "it needs %d scrap" % int(c.get("scrap", 0))
	return ""


func claim(id: String) -> bool:
	if why_not_claim(id) != "":
		return false
	var l := lot(id)
	sim.stock.scrap = maxf(0.0, float(sim.stock.scrap) - float(l.claim.get("scrap", 0)))
	claimed_on[id] = sim.day
	_after_claim()
	sim.events.append({"type": "lot", "lot": id, "what": "claimed"})
	sim.alert("lot-%s" % id, "info", "%s is yours" % String(l.name), "Its streets can be built on; shut its mouths to hold them", null, 20.0)
	return true


## The claim changed what is open: the posts, the plots, the gate.
func _after_claim() -> void:
	_set_posts()
	_open_passage()
	sim.build.version += 1
	sim.build.refresh_plots()


## The posts of the claimed lots' mouths join the night posts (after the wall's own).
func _set_posts() -> void:
	var extra: Array = []
	for m in _mouths:
		if not claimed_on.has(String(m.get("lot", ""))):
			continue
		var po: Dictionary = m.post
		if po.is_empty():
			continue
		extra.append({"id": "post_%s" % String(m.id), "name": String(po.get("name", m.name)), "pos": po.pos, "what": String(po.get("what", "Holding the wall")), "face": _side_of(m)})
	sim.jobs.set_extra_posts(extra)


## The compass side a mouth's wall faces (the way the dead come from).
func _side_of(m: Dictionary) -> String:
	if String(m.get("side", "")) in ["N", "S", "E", "W"]:
		return String(m.side)
	var out = m.get("outside", [])
	var inn = m.get("inside", [])
	if out is Array and inn is Array and out.size() >= 2 and inn.size() >= 2:
		if String(m.dir) == "h":
			return "N" if float(out[1]) < float(inn[1]) else "S"
		return "W" if float(out[0]) < float(inn[0]) else "E"
	return "N"


## People may walk through the Main gate once a lot is claimed; the dead may not.
func _open_passage() -> void:
	if _passage < 0 or claimed_on.is_empty():
		return
	for s in sim.segments:
		if int(s.id) == _passage:
			_passage_open = true
			_passage_tiles(s)
			return


func _passage_tiles(s) -> void:
	for i in s.tiles:
		sim.world.solid_p[int(i)] = 0
		sim.path_p.set_solid(int(i), false)


## The gate is shut to people again (a new run, a save without a claim).
func _close_passage() -> void:
	if not _passage_open:
		return
	_passage_open = false
	for s in sim.segments:
		if int(s.id) == _passage and int(s.state) != 3:
			for i in s.tiles:
				sim.world.solid_p[int(i)] = 1
				sim.path_p.set_solid(int(i), true)


## The wall section `s` was opened or shut (a breach, a repair): the gate stays open to people.
func after_segment_change(s) -> void:
	if _passage_open and int(s.id) == _passage:
		_passage_tiles(s)


# ---------------------------------------------------------------------- walls --

## The wall at a mouth: {"kit", "seg"} or {} when none stands (or is going up).
func wall_at(mouth_id: String) -> Dictionary:
	for b in _built:
		if String(b.mouth) == mouth_id:
			return {"kit": String(b.kit), "seg": FIRST_SEGMENT_ID + int(mouth(mouth_id).index)}
	return {}


## The wall section standing at a mouth, or null.
func segment_at(mouth_id: String):
	var w := wall_at(mouth_id)
	if w.is_empty():
		return null
	for s in sim.segments:
		if int(s.id) == int(w.seg):
			return s
	return null


## The mouth a wall plot is (the plot's id is the mouth's).
func is_mouth_plot(plot_id: String) -> bool:
	return _mouth_by_id.has(plot_id)


## Build finished the wall of this kit at this mouth: make the section.
func on_wall_built(mouth_id: String, kit_id: String) -> void:
	var m := mouth(mouth_id)
	var k := kit(kit_id)
	if m.is_empty() or k.is_empty() or not wall_at(mouth_id).is_empty():
		return
	_built.append({"mouth": mouth_id, "kit": kit_id})
	var seg = _make_section(m, k)
	sim.events.append({"type": "wall", "mouth": mouth_id})
	if seg != null:
		sim.alert("wall-%s" % mouth_id, "info", "%s is shut" % String(m.name), "The street is closed to the dead", m.center, 14.0)


## Builds the Segment of a wall of kit `k` at mouth `m`, shuts its tiles, and tells the world.
func _make_section(m: Dictionary, k: Dictionary):
	var rect: Array = m.rect
	var tiles: Array = []
	for ty in range(int(rect[1]), int(rect[3]) + 1):
		for tx in range(int(rect[0]), int(rect[2]) + 1):
			tiles.append(ty * sim.world.W + tx)
	var horizontal: bool = String(m.dir) == "h"
	var length: float = float(m.length)
	var c: Vector2 = m.center
	# where the old sections have their centre: the middle of the wall, a little inside its inner face
	var anchor: Vector2 = c
	var raw = m.get("anchor", null)
	if raw is Array and raw.size() >= 2:
		anchor = Vector2(float(raw[0]), float(raw[1]))
	var template = null
	for s in sim.segments:
		if int(s.id) == int(k.get("template", -1)):
			template = s
	var x0 := float(rect[0])
	var y0 := float(rect[1])
	var x1 := float(rect[2]) + 1.0
	var y1 := float(rect[3]) + 1.0
	var def := {
		"id": FIRST_SEGMENT_ID + int(m.index),
		"kind": String(template.kind) if template != null else "container",
		"side": _side_of(m),
		"from": x0 if horizontal else y0,
		"to": x1 if horizontal else y1,
		"name": String(m.name),
		"hp": float(k.hp),
		"tiles": tiles,
		"center": anchor,
		"slots": _slots_for(m, k),
		"obj": {"cx": c.x, "cy": c.y, "w": x1 - x0, "h": y1 - y0, "a": 0.0},
		"art": _art_for(template, anchor, length, float(k.get("length", length)), horizontal, _mirrored(template, m), _turned(template, m)),
	}
	var seg = sim.add_segment(def)
	_wipe_footprint(tiles)
	return seg


## Whether the pictures of the kit's template lie on the other side of the wall on this mouth (round 9, the view): the compound's
## sections are drawn inward of their centre (the wall's inner face is 0.9 tile outside it), so a template of the north wall on a
## mouth that looks south (or of the west wall on one that looks east, and the other ways about) is put on the other side of the
## anchor, mirrored across the wall.
func _mirrored(template, m: Dictionary) -> bool:
	if template == null:
		return false
	var t := String(template.side)
	var side := _side_of(m)
	if String(m.dir) == "h":
		return t in ["N", "S"] and side in ["N", "S"] and t != side
	return t in ["W", "E"] and side in ["W", "E"] and t != side


## Whether the pictures themselves are turned over where they are mirrored: the pallets' stakes and the chain-link's wire point at
## the dead. The vehicles and the containers look the same either way (and keep the light of the shadows the compound's own
## sections cast), the cinderblocks have no face.
func _turned(template, m: Dictionary) -> bool:
	return template != null and String(template.kind) in ["pallets", "chainlink"] and _mirrored(template, m)


## The mouth's slots for this kit: the data's are for a container; a thinner wall has its dead stand closer to the
## ring side, by the difference of how far in front of the inner face the kits' dead stand.
func _slots_for(m: Dictionary, k: Dictionary) -> Array:
	var delta: float = SLOT_STAND - float(k.get("stand", SLOT_STAND))
	var out: Array = []
	for sl in m.slots:
		var q: Dictionary = sl.duplicate()
		var toward := Vector2.ZERO
		match String(sl.get("face", "S")):
			"N":
				toward = Vector2(0.0, -1.0)
			"S":
				toward = Vector2(0.0, 1.0)
			"E":
				toward = Vector2(1.0, 0.0)
			"W":
				toward = Vector2(-1.0, 0.0)
		q["x"] = float(sl.x) + toward.x * delta
		q["y"] = float(sl.y) + toward.y * delta
		out.append(q)
	return out


## The four damage states' pictures of the template section, moved to this mouth (their offsets from the
## section's centre kept) and stretched along the wall by the mouth's length over the kit's. With `mirror` they are put on
## the other side of the centre, across the wall; with `turn` as well they carry the flag (`flip_v` for a wall across a street
## that runs east to west, `flip_h` for the other) that makes the world turn the picture over.
func _art_for(template, anchor: Vector2, length: float, kit_length: float, horizontal: bool, mirror: bool = false, turn: bool = false) -> Array:
	var out: Array = []
	if template == null or not template.obj.has("states"):
		return out
	var o: Dictionary = template.obj
	var s: float = length / maxf(0.1, kit_length)
	for state_pieces in o.states:
		var pieces: Array = []
		for p in state_pieces:
			var q := {"file": p.file}
			if horizontal:
				q["x"] = anchor.x + (float(p.x) - float(template.center.x)) * s
				q["w"] = float(p.w) * s
				q["y"] = anchor.y + (float(p.y) - float(template.center.y))
				q["h"] = float(p.h)
				if mirror:
					q["y"] = anchor.y - (float(p.y) + float(p.h) - float(template.center.y))
				if turn:
					q["flip_v"] = true
			else:
				q["y"] = anchor.y + (float(p.y) - float(template.center.y)) * s
				q["h"] = float(p.h) * s
				q["x"] = anchor.x + (float(p.x) - float(template.center.x))
				q["w"] = float(p.w)
				if mirror:
					q["x"] = anchor.x - (float(p.x) + float(p.w) - float(template.center.x))
				if turn:
					q["flip_h"] = true
			pieces.append(q)
		out.append(pieces)
	return out


## The dead standing where a wall has just gone up are gone with the wall (there is no room for them).
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


func _remove_all_walls() -> void:
	if sim == null:
		return
	var gone: Array = []
	for s in sim.segments:
		if int(s.id) >= FIRST_SEGMENT_ID:
			gone.append(s)
	for s in gone:
		sim.remove_segment(s)
	_built.clear()


## How many wall sections of the lot stand.
func standing_walls(lot_id: String) -> int:
	var n := 0
	for m in mouths_of(lot_id):
		var s = segment_at(String(m.id))
		if s != null and int(s.state) != 3:
			n += 1
	return n


## The streets (spawn points) that are still open: a street is shut when every wall plot across it has a wall
## that stands (a wall that is down is open). Only the lots that are claimed have walls to stand.
func open_streets() -> int:
	var spawns := {}
	var shut := {}
	for m in _mouths:
		var sp := int(m.get("spawn", -1))
		spawns[sp] = true
		var s = segment_at(String(m.id))
		var stands: bool = s != null and int(s.state) != 3
		shut[sp] = bool(shut.get(sp, true)) and stands
	var n := 0
	for sp in spawns:
		if not bool(shut.get(sp, false)):
			n += 1
	return n


func streets() -> int:
	var spawns := {}
	for m in _mouths:
		spawns[int(m.get("spawn", -1))] = true
	return spawns.size()


## A building of a claimed lot is ruined at the bell with this chance: all of RAID_RISK with every street open,
## none with every street shut.
func raid_risk() -> float:
	var n := streets()
	return RAID_RISK * float(open_streets()) / float(maxi(1, n))


## Whether every mouth of the lot has a wall that stands.
func sealed(lot_id: String) -> bool:
	if not on or not claimed_on.has(lot_id):
		return false
	var ms := mouths_of(lot_id)
	return not ms.is_empty() and standing_walls(lot_id) == ms.size()


func _check_sealed() -> void:
	for l in _lots:
		var id := String(l.id)
		var now := sealed(id)
		if now and not _sealed.get(id, false):
			sim.events.append({"type": "lot", "lot": id, "what": "sealed"})
			sim.events.append({"type": "banner", "text": "%s is sealed" % String(l.name), "sub": "Every street of it is shut"})
			for p in sim.people:
				if not p.dead and not p.turned:
					sim.morale.shock(p, float(l.get("sealed_bonus", SEALED_MORALE)), "The streets are shut")
		_sealed[id] = now


# ------------------------------------------------------------- the standing order --

func auto_walling(lot_id: String) -> bool:
	return bool(auto_on.get(lot_id, false))


## Switches the standing order of a lot on or off (only a claimed lot has one).
func set_auto_walling(lot_id: String, value: bool) -> bool:
	if not on or not claimed_on.has(lot_id):
		return false
	auto_on[lot_id] = value
	return true


## The street of a lot that would be walled next: the first of its mouths with nothing across it, or "".
func next_street(lot_id: String) -> String:
	for m in mouths_of(lot_id):
		var pl: Dictionary = sim.build.plot(String(m.id))
		if not pl.is_empty() and String(pl.building) == "" and pl.site.is_empty():
			return String(m.id)
	return ""


## The wall kit the standing order puts across a mouth: the sturdiest for its price among those that fit.
func best_kit(mouth_id: String) -> String:
	var best := ""
	var best_value := -1.0
	for kid in kits_for(mouth_id):
		var b: Dictionary = sim.build.building(String(kid))
		var value: float = float(b.hp) / maxf(1.0, float(b.scrap))
		if value > best_value:
			best_value = value
			best = String(kid)
	return best


## The price of the wall the standing order would order next in this lot (0 when none is left).
func next_price(lot_id: String) -> int:
	var m := next_street(lot_id)
	if m == "":
		return 0
	var k := best_kit(m)
	return int(sim.build.building(k).scrap) if k != "" else 0


## By day, with nobody building and the scrap there, the lots under the standing order get their next wall
## ordered: the Builders do the rest, one street after another.
func _auto_walls(dt: float) -> void:
	if auto_on.is_empty():
		return
	_auto_t -= dt
	if _auto_t > 0.0:
		return
	_auto_t = AUTO_EVERY
	if sim.phase != "day" or not sim.build.active_site().is_empty():
		return
	for l in _lots:
		var id := String(l.id)
		if not auto_walling(id) or not claimed_on.has(id):
			continue
		var m := next_street(id)
		if m == "":
			continue
		var k := best_kit(m)
		if k == "":
			continue
		if float(sim.stock.scrap) < float(sim.build.building(k).scrap) + AUTO_KEEP:
			continue
		if sim.build.order(m, k):
			return


# ---------------------------------------------------------------------- raids --

## At the bell, the buildings of the lots may be ruined, the less the more of the streets are shut.
func _raid() -> void:
	var risk := raid_risk()
	for pl in sim.build.plots():
		var l := String(pl.get("lot", ""))
		if l == "" or String(pl.get("kind", "")) != "ring" or String(pl.building) == "":
			continue
		if risk <= 0.0:
			continue
		if sim.rng.randf() < risk:
			var id := String(pl.building)
			sim.build.ruin(String(pl.id))
			sim.events.append({"type": "ruined", "plot": String(pl.id), "building": id})
			sim.alert("ruined-%s" % String(pl.id), "danger", "The %s was ruined in the night" % String(sim.build.building(id).name).to_lower(), "Its streets were not shut", Vector2(pl.pos), 20.0)


# ----------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {"claimed": claimed_on.duplicate(), "walls": _built.duplicate(true), "sealed": _sealed.duplicate(), "raid_day": _raid_day, "auto": auto_on.duplicate()}


func load_state(d: Dictionary) -> void:
	_close_passage()
	claimed_on.clear()
	var c = d.get("claimed", {})
	if c is Dictionary:
		for id in c:
			if _lot_by_id.has(String(id)):
				claimed_on[String(id)] = int(c[id])
	_raid_day = int(d.get("raid_day", 0))
	auto_on.clear()
	var au = d.get("auto", {})
	if au is Dictionary:
		for id in au:
			if _lot_by_id.has(String(id)) and bool(au[id]):
				auto_on[String(id)] = true
	_sealed.clear()
	var s = d.get("sealed", {})
	if s is Dictionary:
		for id in s:
			_sealed[String(id)] = bool(s[id])
	on = sim.recruits.small and not _lots.is_empty() and not _mouths.is_empty()
	if on:
		_after_claim_quiet()


func _after_claim_quiet() -> void:
	_set_posts()
	_open_passage()
	sim.build.version += 1
	sim.build.refresh_plots()


## Before the save loader reads the wall sections: the sections of the walls the save says were built are
## put in place (and the ones now standing taken away), and the claimed lots' posts exist before the jobs read
## theirs. A fresh sim, as the real game loads one, has never been started, so what the save holds decides
## whether it has lots. Returns what was there, for `restore`.
func prepare_load(data: Dictionary) -> Dictionary:
	var before := {"on": on, "claimed": claimed_on.duplicate(), "walls": _snapshot()}
	var m = data.get("modules", {})
	var mine = m.get("lots", {}) if m is Dictionary else {}
	if not mine is Dictionary or _lots.is_empty() or _mouths.is_empty():
		return before
	var walls = mine.get("walls", [])
	var claimed = mine.get("claimed", {})
	var has_lots: bool = (walls is Array and not walls.is_empty()) or (claimed is Dictionary and not claimed.is_empty())
	if not on and not has_lots:
		return before
	on = true
	_remove_all_walls()
	if walls is Array:
		for w in walls:
			if not w is Dictionary:
				continue
			var mm := mouth(String(w.get("mouth", "")))
			var kk := kit(String(w.get("kit", "")))
			if mm.is_empty() or kk.is_empty() or not wall_at(String(mm.id)).is_empty():
				continue
			_built.append({"mouth": String(mm.id), "kit": String(kk.id)})
			_make_section(mm, kk)
	claimed_on.clear()
	if claimed is Dictionary:
		for id in claimed:
			if _lot_by_id.has(String(id)):
				claimed_on[String(id)] = int(claimed[id])
	_set_posts()
	return before


## The walls that stand, with how they stand, for `restore`.
func _snapshot() -> Array:
	var out: Array = []
	for w in _built:
		var s = segment_at(String(w.mouth))
		out.append({"mouth": String(w.mouth), "kit": String(w.kit), "hp": float(s.hp) if s != null else -1.0, "state": int(s.state) if s != null else 0})
	return out


## Puts the walls back as they were before `prepare_load` (the save was no good): the same walls, as damaged.
func restore(before: Dictionary) -> void:
	_remove_all_walls()
	on = bool(before.get("on", on))
	claimed_on = before.get("claimed", {}).duplicate()
	for w in before.get("walls", []):
		var mm := mouth(String(w.mouth))
		var kk := kit(String(w.kit))
		if mm.is_empty() or kk.is_empty():
			continue
		_built.append({"mouth": String(mm.id), "kit": String(kk.id)})
		var seg = _make_section(mm, kk)
		if seg != null and float(w.get("hp", -1.0)) >= 0.0:
			seg.hp = float(w.hp)
			if int(w.get("state", 0)) != int(seg.state):
				seg.state = int(w.state)
				if seg.state == 3:
					sim.open_segment(seg, true)
				if sim.on_segment_change.is_valid():
					sim.on_segment_change.call(seg)
	_set_posts()
