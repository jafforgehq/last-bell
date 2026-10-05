## The ARRIVAL of the One House run (docs/superpowers/specs/2026-10-05-arrival-design.md): where a run begins (the ENTRY, a road end at the forest edge of the town), which houses the
## player may choose to claim as the base (the CANDIDATES), and the survivors that wait round each of them (`rescue_for`). Everything the game asks about them goes through here, so that
## no other file cares where the answer comes from.
##
## THE SOURCE. The generator's keys of `TownGen.make` when the town has them (spec section 3):
##   `entry`       {"pos": Vector2, "face": "N"|"E"|"S"|"W", "road": Rect2i, "label": String}
##   `candidates`  [{"house": id, "kind", "label": "Family home. 8 rooms, big yard.", "rooms", "yard": "big"|"small"|"none", "dist": from the entry, "tier": "best"|"ok"|"poor"}]
##   `rescue_for`  {String(house id): [rescue record]} (the shape of `rescue`; `rescue` itself is the best candidate's)
## and, for a town that has none of them (a generator from before the arrival), a STAND-IN made from what every town always had, cached in the town dictionary under `_arrival` (the town is
## regenerated from its seed, never saved): an entry on a road 40 tiles from the start house, the start house as the best candidate with the two nearest houses whose base layout has the fewest
## problems (`BaseLayout.validate`: none in the start house's case, a few in the others', which the claim copes with: one of four rooms or more and one of three or fewer when the town has them),
## labelled from their room counts, and today's `rescue` for the start house (the others' derived from it, re-ordered round the house). Each key is taken from the generator on its own, so a generator that lands one key at a time works.
##
## Static functions only; every one takes the town dictionary (`sim.houses.town`, `town_data`).
extends RefCounted

const BaseLayout := preload("res://scripts/town/base_layout.gd")

const CACHE := "_arrival"
## The stand-in entry: how far from the start house along a road, and the nearest it may be (a small town has no road so far).
const ENTRY_FAR := 40.0
const ENTRY_NEAREST := 18.0
## The stand-in candidates: not nearer to the entry than this (the first house is not on the doorstep: from the entry a wall is more than the guide's 14 tiles off), nor farther than that;
## at most this many houses are tried.
const CANDIDATE_MIN := 26.0
const CANDIDATE_MAX := 75.0
const TRIED := 12
## How big a yard is, in free tiles of the lot round the house.
const YARD_BIG := 150
const YARD_SMALL := 45
const KIND_NAMES := {
	"start": "Family home", "family": "Family home", "medium": "House", "small": "Small house", "bungalow": "Bungalow", "cottage": "Cottage", "lhouse": "House", "thouse": "House",
	"uhouse": "House", "twowing": "House", "terrace": "Terrace house", "terrace_ext": "Terrace house", "farmhouse": "Farmhouse",
}
## Where each facing points, radians (the drawing's: east is 0, south is a quarter turn down the screen), as avatar.gd has it.
const FACE_ANGLE := {"E": 0.0, "S": PI / 2.0, "W": PI, "N": -PI / 2.0}


# ----------------------------------------------------------------------- the answers --

## Whether the generator made the entry and the candidates (and so kept the street's dead from them: spec section 3), or they are the stand-in's.
static func native(town: Dictionary) -> bool:
	return town.get("entry") is Dictionary and not (town.entry as Dictionary).is_empty() and town.get("candidates") is Array and not (town.candidates as Array).is_empty()


## {"pos": Vector2, "face", "road": Rect2i, "label"}: where the run begins.
static func entry(town: Dictionary) -> Dictionary:
	var e = town.get("entry")
	if e is Dictionary and not (e as Dictionary).is_empty() and e.get("pos") is Vector2:
		return e
	var made := _made(town)
	if not made.has("entry"):
		made["entry"] = _find_entry(town)
	return made.entry


## The houses that may be claimed, as the generator's `candidates` list gives them (the stand-in's has the same shape). Never empty in a town that has houses.
static func candidates(town: Dictionary) -> Array:
	var c = town.get("candidates")
	if c is Array and not (c as Array).is_empty():
		return c
	var made := _made(town)
	if not made.has("candidates"):
		made["candidates"] = _find_candidates(town, entry(town))
	return made.candidates


## The candidate entry of house `h` ({} when it is not one).
static func candidate_of(town: Dictionary, h: int) -> Dictionary:
	for c in candidates(town):
		if int(c.house) == h:
			return c
	return {}


static func is_candidate(town: Dictionary, h: int) -> bool:
	return not candidate_of(town, h).is_empty()


## The house of the best tier (the first candidate when none says so, the start house when there are none).
static func best_house(town: Dictionary) -> int:
	var list := candidates(town)
	for c in list:
		if String(c.tier) == "best":
			return int(c.house)
	if not list.is_empty():
		return int(list[0].house)
	return int(town.start.house) if town.has("start") else -1


## The first candidate of a tier ("best", "ok", "poor"), -1 when there is none.
static func house_of_tier(town: Dictionary, tier: String) -> int:
	for c in candidates(town):
		if String(c.tier) == tier:
			return int(c.house)
	return -1


## The candidate house nearest `at` (to its walls), skipping `without` (house ids); -1 when there is none.
static func nearest(town: Dictionary, at: Vector2, without: Array = []) -> int:
	var best := -1
	var best_d := INF
	for c in candidates(town):
		var id := int(c.house)
		if without.has(id):
			continue
		var d := distance_to_house(town, id, at)
		if d < best_d:
			best_d = d
			best = id
	return best


## How far `at` is from the walls of house `h` (0 inside them).
static func distance_to_house(town: Dictionary, h: int, at: Vector2) -> float:
	var rect := Rect2(Rect2i(town.houses[h].rect))
	return at.distance_to(Vector2(clampf(at.x, rect.position.x, rect.end.x), clampf(at.y, rect.position.y, rect.end.y)))


## The tile outside the front door of house `h` (its middle when it has none), in tiles, for an arrow to point at.
static func door_of(town: Dictionary, h: int) -> Vector2:
	var hd: Dictionary = town.houses[h]
	if hd.get("door") is Vector2i:
		return Vector2(hd.door) + Vector2(0.5, 0.5)
	return Vector2(Rect2i(hd.rect).get_center())


## {"pos": Vector2, "face": String, "angle": radians}: where the avatar stands at the start of a run and which way she faces.
static func spawn(town: Dictionary) -> Dictionary:
	var e := entry(town)
	var face := String(e.get("face", "S"))
	return {"pos": Vector2(e.pos), "face": face, "angle": float(FACE_ANGLE.get(face, PI / 2.0))}


## The survivors of the base in house `h`, near to far: the generator's `rescue_for` entry when it has one, else the town's `rescue` for the start house (and the best candidate), else that list
## re-ordered round `h` (the house itself left out).
static func rescue_for(town: Dictionary, h: int) -> Array:
	if h < 0 or h >= (town.houses as Array).size():
		return []
	var table = town.get("rescue_for")
	if table is Dictionary:
		var got = (table as Dictionary).get(str(h), (table as Dictionary).get(h))
		if got is Array and not (got as Array).is_empty():
			return got
	if h == best_house(town) or h == int(town.start.house):
		return town.get("rescue", [])
	var made: Dictionary = _made(town)
	if not made.rescue_for.has(h):
		made.rescue_for[h] = _derive_rescue(town, h)
	return made.rescue_for[h]


# ------------------------------------------------------------------------- the stand-in --

## The stand-in's cache in the town dictionary: its entry, its candidates and the derived survivors of each house, each made the first time it is asked for (the title's town asks for the
## entry only: a base layout is made and checked for each candidate, which is a few milliseconds a house).
static func _made(town: Dictionary) -> Dictionary:
	if not town.has(CACHE):
		town[CACHE] = {"rescue_for": {}}
	return town[CACHE]


## An entry on a road about ENTRY_FAR tiles from the start house, in the direction the seed picks (any other when the road has none there), facing the way to the house. A town too
## small to have one gets the start house's own start tile (the run then begins inside the house, as it did before the arrival).
static func _find_entry(town: Dictionary) -> Dictionary:
	var houses: Array = town.houses
	var start: int = int(town.start.house)
	var centre := Vector2(Rect2i(houses[start].rect).get_center())
	var d: Dictionary = town.data
	var w := int(d.W)
	var h := int(d.H)
	var solid_z = d.solidZ
	var solid_p = d.solidP
	var tile_house: PackedInt32Array = town.tile_house
	var want := int(town.get("seed", 1)) % 4
	var best := {}
	var best_score := INF
	for rd in town.get("streets", {}).get("roads", []):
		if String(rd.kind) == "alley":
			continue
		var r: Rect2i = rd.rect
		var horizontal: bool = String(rd.dir) == "h"
		var lane: int = (r.position.y + r.size.y / 2) if horizontal else (r.position.x + r.size.x / 2)
		for t in range(r.position.x if horizontal else r.position.y, r.end.x if horizontal else r.end.y):
			var x: int = t if horizontal else lane
			var y: int = lane if horizontal else t
			if x < 2 or y < 2 or x >= w - 2 or y >= h - 2:
				continue
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var dist := p.distance_to(centre)
			if dist < ENTRY_NEAREST or dist > ENTRY_FAR + 8.0:
				continue
			var score := absf(dist - ENTRY_FAR) + (0.0 if _bucket(p - centre) == want else 6.0)
			if score >= best_score or not _open_around(solid_z, solid_p, tile_house, w, x, y):
				continue
			best_score = score
			var face := String("E" if centre.x > p.x else "W") if horizontal else String("S" if centre.y > p.y else "N")
			best = {"pos": p, "face": face, "road": r, "label": "The road in"}
	if best.is_empty():
		var at: Vector2 = town.start.pos
		return {"pos": at, "face": "S", "road": Rect2i(), "label": ""}
	return best


static func _bucket(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return 1 if v.x > 0.0 else 3
	return 2 if v.y > 0.0 else 0


## The tile and the ones round it are open street: nothing solid, none a house's.
static func _open_around(solid_z, solid_p, tile_house: PackedInt32Array, w: int, x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var i: int = (y + dy) * w + x + dx
			if int(solid_z[i]) != 0 or int(solid_p[i]) != 0 or tile_house[i] >= 0:
				return false
	return true


static func _find_candidates(town: Dictionary, e: Dictionary) -> Array:
	var start: int = int(town.start.house)
	var at: Vector2 = e.pos
	var out: Array = [_describe(town, start, "best", at)]
	var pool: Array = []
	for hd in town.houses:
		var id := int(hd.id)
		if id == start or not _homey(hd):
			continue
		var dist := Vector2(Rect2i(hd.rect).get_center()).distance_to(at)
		if dist >= CANDIDATE_MIN and dist <= CANDIDATE_MAX:
			pool.append([dist, id])
	pool.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	# (the nearest houses are tried: the generator's candidates are built to pass the layout's check, but a town from before them has only the start house that does, so the stand-in takes
	# the ones with the fewest problems and the claim copes with what is left: `Base.problems`)
	var tried: Array = []
	for p in pool:
		if tried.size() >= TRIED:
			break
		var id := int(p[1])
		tried.append([_problems(town, id), float(p[0]), id, (town.houses[id].rooms as Array).size()])
	tried.sort_custom(func(a, b): return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and float(a[1]) < float(b[1])))
	var chosen: Array = []
	for want_roomy in [true, false]:
		for t in tried:
			if (int(t[3]) >= 4) == want_roomy:
				chosen.append(int(t[2]))
				break
	for t in tried:
		if chosen.size() >= 2:
			break
		if not chosen.has(int(t[2])):
			chosen.append(int(t[2]))
	for id in chosen:
		out.append(_describe(town, int(id), "ok" if (town.houses[int(id)].rooms as Array).size() >= 4 else "poor", at))
	return out


## A house a family could live in: a residential main building of two rooms or more (no block of flats).
static func _homey(hd: Dictionary) -> bool:
	return String(hd.get("type", "")) == "residential" and bool(hd.get("main", true)) and (hd.rooms as Array).size() >= 2 and String(hd.kind) != "apartments"


## How many problems `BaseLayout.validate` finds in the base layout of house `h` (0: a base can really be built there).
static func _problems(town: Dictionary, h: int) -> int:
	var layout: Dictionary = BaseLayout.make(town, h)
	return 99 if layout.is_empty() else BaseLayout.validate(layout, town).size()


static func _describe(town: Dictionary, h: int, tier: String, from: Vector2) -> Dictionary:
	var hd: Dictionary = town.houses[h]
	var rooms: int = (hd.rooms as Array).size()
	var lot := Rect2i(hd.lot)
	var rect := Rect2i(hd.rect)
	var free := lot.size.x * lot.size.y - rect.size.x * rect.size.y
	var yard := "big" if free >= YARD_BIG else ("small" if free >= YARD_SMALL else "none")
	var kind := String(hd.kind)
	var nm := String(KIND_NAMES.get(kind, "House"))
	var label := "%s. %d rooms, %s yard." % [nm, rooms, "no" if yard == "none" else yard]
	return {"house": h, "kind": kind, "label": label, "rooms": rooms, "yard": yard, "dist": Vector2(rect.get_center()).distance_to(from), "tier": tier}


static func _derive_rescue(town: Dictionary, h: int) -> Array:
	var c := Vector2(Rect2i(town.houses[h].rect).get_center())
	var out: Array = []
	for r in town.get("rescue", []):
		if int(r.house) == h:
			continue
		var rec: Dictionary = (r as Dictionary).duplicate()
		rec["dist"] = Vector2(Rect2i(town.houses[int(r.house)].rect).get_center()).distance_to(c)
		out.append(rec)
	out.sort_custom(func(a, b): return float(a.dist) < float(b.dist))
	return out
