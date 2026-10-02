## Buildings. The compound has fixed plots (assets/data/plots.json); on each the player may order
## one of a catalogue of buildings (assets/data/buildings.json). Ordering pays the scrap and puts a
## site on the plot; by day the people on the Builders job work the oldest site (the progress is in
## builder-hours: a good builder is worth two); a finished site becomes the building, whose effects
## the other modules read through `bonus(key)` and `factor(key)`. A building may be demolished
## (half the scrap back) and a site cancelled (all the scrap back if no work was done, else half).
##
## The Builders' goal while a site is up is the plot's work spot (`jobs.seat_pos`), so the people
## "working" the Builders station are the ones building; a wall under the crew's threshold still
## comes first (a person sent to mend a wall is on that order). The Salvage station (stations.json,
## `requires` the salvage bench) is worked here: each person at it makes SALVAGE_PER_HOUR scrap.
##
## Round 7 asks `housing()` and `radio_range()`.
##
## Events: {"type": "site"|"built"|"cancelled"|"demolished", "plot": id, "building": id}.
## Alerts: `built-<plot id>` when a building is finished.
extends RefCounted

const BUILDINGS_PATH := "res://assets/data/buildings.json"
const PLOTS_PATH := "res://assets/data/plots.json"
const ART_PATH := "res://assets/data/building_art.json"
## Where the data is read from (tests may point it at another file).
static var buildings_path := BUILDINGS_PATH
static var plots_path := PLOTS_PATH
static var art_path := ART_PATH
static var _cache := {}

## Builder-hours of work one builder does in a game hour: the base plus this for each point of Building.
const RATE_BASE := 1.0
const RATE_PER_SKILL := 0.12
## Building skill grows as mending does: each work-hour counts as this many health points mended.
const MEND_PER_WORK_HOUR := 10.0
## The share of the scrap that comes back from a site with work done on it, and from a demolished building.
const REFUND_SHARE := 0.5
## The Salvage station: scrap an hour for each person at it.
const SALVAGE_PER_HOUR := 0.4
## The people the school houses before any bunk house, and the radio's range before any mast.
const BASE_HOUSING := 6
## Where the second and third builder stand at a site, round its work spot.
const STAND_OFFSETS := [Vector2(0.0, 0.0), Vector2(1.1, 0.0), Vector2(-1.1, 0.0)]
## A click this close to a plot's sign (tiles) is a click on the plot.
const SIGN_REACH := 0.9
## While a site is worked, the hammer rings (an event for the sound) this often, in seconds of rules time.
const HAMMER_EVERY := 0.6

var sim
## Bumped whenever a building stands or falls (the jobs keep their view of the stations by it).
var version := 0
var _plots: Array = []
var _plot_by_id := {}
var _catalogue: Array = []
var _building_by_id := {}
var _art := {}
## The plots with a site, oldest first: the first is the one being built.
var _queue: Array = []
var _hammer := 0.0


func setup(s) -> void:
	sim = s
	_load_data()


func _load_data() -> void:
	var key := plots_path + "|" + buildings_path + "|" + art_path
	if not _cache.has(key):
		var plots: Array = []
		var rawp = JSON.parse_string(FileAccess.get_file_as_string(plots_path))
		for r in (rawp.get("plots", []) if rawp is Dictionary else []):
			var p: Dictionary = {
				"id": String(r.id), "name": String(r.name), "kind": String(r.get("kind", "yard")),
				"pos": Vector2(float(r.pos[0]), float(r.pos[1])), "size": Vector2(float(r.size[0]), float(r.size[1])),
				"work": Vector2(float(r.work[0]), float(r.work[1])),
			}
			plots.append(p)
		var buildings: Array = []
		var rawb = JSON.parse_string(FileAccess.get_file_as_string(buildings_path))
		for r in (rawb.get("buildings", []) if rawb is Dictionary else []):
			var b: Dictionary = r.duplicate(true)
			b["scrap"] = int(r.get("scrap", 0))
			b["work"] = float(r.get("work", 1.0))
			b["max"] = int(r.get("max", 1))
			b["requires"] = String(r.get("requires", ""))
			b["plots"] = r.get("plots", [])
			b["effects"] = r.get("effects", {})
			buildings.append(b)
		var art := {}
		if FileAccess.file_exists(art_path):
			var rawa = JSON.parse_string(FileAccess.get_file_as_string(art_path))
			if rawa is Dictionary:
				art = rawa.get("buildings", {})
		_cache[key] = {"plots": plots, "buildings": buildings, "art": art}
	var c: Dictionary = _cache[key]
	_catalogue = c.buildings
	_building_by_id.clear()
	for b in _catalogue:
		_building_by_id[String(b.id)] = b
	_art = c.art
	# the plots carry their live state (the building, the site) in the same dictionaries
	_plots.clear()
	_plot_by_id.clear()
	for p in c.plots:
		var live: Dictionary = p.duplicate()
		live["building"] = ""
		live["site"] = {}
		live["solid"] = []
		_plots.append(live)
		_plot_by_id[String(live.id)] = live


func start() -> void:
	_reset()


## Everything unbuilt: the footprints opened again, the plots empty.
func _reset() -> void:
	for p in _plots:
		_unblock(p)
		p.building = ""
		p.site = {}
	_queue.clear()
	version += 1


# ------------------------------------------------------------------- plots --

func plots() -> Array:
	return _plots


## A plot's data and state, or {} when there is no such plot.
func plot(id: String) -> Dictionary:
	return _plot_by_id.get(id, {})


## The plot whose lot contains this point (tile units), or "".
func plot_at(at: Vector2) -> String:
	for p in _plots:
		var half: Vector2 = Vector2(p.size) / 2.0
		if absf(at.x - p.pos.x) <= half.x and absf(at.y - p.pos.y) <= half.y:
			return String(p.id)
	return ""


# --------------------------------------------------------------- catalogue --

func catalogue() -> Array:
	return _catalogue


## A building's data, or {} when there is no such building.
func building(id: String) -> Dictionary:
	return _building_by_id.get(id, {})


## How many of this building stand (sites are not counted).
func count(id: String) -> int:
	var n := 0
	for p in _plots:
		if p.building == id:
			n += 1
	return n


func built(id: String) -> bool:
	return count(id) > 0


## How many of this building stand or are going up.
func _count_with_sites(id: String) -> int:
	var n := count(id)
	for p in _plots:
		if not p.site.is_empty() and String(p.site.building) == id:
			n += 1
	return n


## The sum of an effect over the standing buildings (0 when none has it).
func bonus(key: String) -> float:
	var total := 0.0
	for p in _plots:
		if p.building != "":
			total += float(building(String(p.building)).effects.get(key, 0.0))
	return total


## The product of an effect over the standing buildings (1 when none has it).
func factor(key: String) -> float:
	var total := 1.0
	for p in _plots:
		if p.building != "":
			var e: Dictionary = building(String(p.building)).effects
			if e.has(key):
				total *= float(e[key])
	return total


## The people the compound can house (round 7's cap): the school's own and the bunk houses'.
func housing() -> int:
	return BASE_HOUSING + int(bonus("housing"))


func radio_range() -> int:
	return int(bonus("radio_range"))


## Where the builders stand for the first standing building of this id (its plot's work spot), or
## Vector2.ZERO: the Salvage station is there.
func spot_of(id: String) -> Vector2:
	for p in _plots:
		if p.building == id:
			return Vector2(p.work)
	return Vector2.ZERO


## The plot's sign: a small marker inside the lot's top-left corner, the thing the yard shows for the
## plot and the thing a click opens the Build screen on.
func sign_pos(plot_id: String) -> Vector2:
	var pl := plot(plot_id)
	if pl.is_empty():
		return Vector2.ZERO
	return Vector2(pl.pos) - Vector2(pl.size) / 2.0 + Vector2(0.6, 0.6)


## The plot whose sign is within SIGN_REACH tiles of this point, or "".
func sign_at(at: Vector2) -> String:
	var best := ""
	var best_d := SIGN_REACH
	for pl in _plots:
		var d := at.distance_to(sign_pos(String(pl.id)))
		if d <= best_d:
			best_d = d
			best = String(pl.id)
	return best


# --------------------------------------------------------- what buildings give --

## The beds the standing buildings give patients, as world positions (tiles). The building's art file
## says where they are ("beds": [[dx, dy], ...] from the plot's centre); without it the beds are laid
## out in rows of two round the centre.
func bed_spots() -> Array:
	var out: Array = []
	for pl in _plots:
		if pl.building == "":
			continue
		var n := int(building(String(pl.building)).effects.get("beds", 0))
		if n <= 0:
			continue
		var offs = _art.get(String(pl.building), {}).get("beds", [])
		var rows := ceili(float(n) / 2.0)
		for i in n:
			if offs is Array and offs.size() >= n:
				out.append(Vector2(pl.pos) + Vector2(float(offs[i][0]), float(offs[i][1])))
			else:
				out.append(Vector2(pl.pos) + Vector2((float(i % 2) - 0.5) * 1.6, (float(i / 2) - float(rows - 1) / 2.0) * 1.0))
	return out


## How many tiles further the guns of someone standing at `at` reach for a building near them (a
## watchtower): the best of the standing buildings with a `reach_bonus` whose plot is within their
## `reach_radius` of the point (towers do not add up).
func reach_bonus_at(at: Vector2) -> float:
	var best := 0.0
	for pl in _plots:
		if pl.building == "":
			continue
		var e: Dictionary = building(String(pl.building)).effects
		if e.has("reach_bonus") and at.distance_to(Vector2(pl.pos)) <= float(e.get("reach_radius", 0.0)):
			best = maxf(best, float(e.reach_bonus))
	return best


# ------------------------------------------------------------------ orders --

## Why this building cannot be ordered on this plot now ("" when it can).
func why_not(plot_id: String, building_id: String) -> String:
	var pl := plot(plot_id)
	if pl.is_empty():
		return "there is no such plot"
	var b := building(building_id)
	if b.is_empty():
		return "there is no such building"
	if pl.building != "":
		return "the %s is already built here" % String(building(String(pl.building)).name).to_lower()
	if not pl.site.is_empty():
		return "something is already going up here"
	if not b.plots.has(pl.kind):
		return "it cannot stand on %s" % ("the wall" if pl.kind == "wall" else "the yard")
	if _count_with_sites(building_id) >= int(b.max):
		return "there is already %s" % ("one" if int(b.max) == 1 else "the most (%d)" % int(b.max))
	if String(b.requires) != "" and not built(String(b.requires)):
		return "it needs the %s first" % String(building(String(b.requires)).name).to_lower()
	if float(sim.stock.scrap) + 1.0e-9 < float(b.scrap):
		return "it needs %d scrap" % int(b.scrap)
	return ""


## Pays the scrap and puts a site on the plot. False, and nothing changes, if it cannot be ordered.
func order(plot_id: String, building_id: String) -> bool:
	if why_not(plot_id, building_id) != "":
		return false
	var b := building(building_id)
	sim.stock.scrap = float(sim.stock.scrap) - float(b.scrap)
	plot(plot_id).site = {"building": building_id, "progress": 0.0, "work": float(b.work), "scrap": float(b.scrap)}
	_queue.append(plot_id)
	sim.events.append({"type": "site", "plot": plot_id, "building": building_id})
	return true


## Stops a site: all its scrap back if no work was done, else half.
func cancel(plot_id: String) -> bool:
	var pl := plot(plot_id)
	if pl.is_empty() or pl.site.is_empty():
		return false
	var share := 1.0 if float(pl.site.progress) <= 0.0 else REFUND_SHARE
	sim.stock.scrap = float(sim.stock.scrap) + float(pl.site.scrap) * share
	var id := String(pl.site.building)
	pl.site = {}
	_queue.erase(plot_id)
	sim.events.append({"type": "cancelled", "plot": plot_id, "building": id})
	return true


## Why this building cannot be demolished ("" when it can): another building stands on it.
func why_not_demolish(plot_id: String) -> String:
	var pl := plot(plot_id)
	if pl.is_empty() or pl.building == "":
		return "nothing stands there"
	for q in _plots:
		if q.building != "" and String(building(String(q.building)).requires) == String(pl.building) and count(String(pl.building)) <= 1:
			return "the %s needs it" % String(building(String(q.building)).name).to_lower()
	return ""


## Takes a building down: half its scrap back, its effects end, its footprint opens, and the people
## whose station went with it are let go.
func demolish(plot_id: String) -> bool:
	if why_not_demolish(plot_id) != "":
		return false
	var pl := plot(plot_id)
	var id := String(pl.building)
	sim.stock.scrap = float(sim.stock.scrap) + float(building(id).scrap) * REFUND_SHARE
	_unblock(pl)
	pl.building = ""
	version += 1
	sim.jobs.trim()
	sim.events.append({"type": "demolished", "plot": plot_id, "building": id})
	return true


# ------------------------------------------------------------ construction --

## The plot with the site being built (the oldest order), or {}.
func active_site() -> Dictionary:
	for id in _queue:
		var pl := plot(String(id))
		if not pl.is_empty() and not pl.site.is_empty():
			return pl
	return {}


## How far along a site is, 0 to 1 (0 for a plot with none).
func progress_of(plot_id: String) -> float:
	var pl := plot(plot_id)
	if pl.is_empty() or pl.site.is_empty():
		return 0.0
	return clampf(float(pl.site.progress) / maxf(float(pl.site.work), 0.001), 0.0, 1.0)


## Where this builder stands at the active site (where they are, if there is none).
func work_spot(p) -> Vector2:
	var pl := active_site()
	if pl.is_empty():
		return Vector2(p.x, p.y)
	var i := maxi(0, sim.jobs.crew_of("builders").find(p))
	return Vector2(pl.work) + Vector2(STAND_OFFSETS[mini(i, STAND_OFFSETS.size() - 1)])


## The builders at the site right now: on the job, there and free.
func crew() -> Array:
	return sim.jobs.working("builders") if not active_site().is_empty() else []


## Builder-hours one person does in a game hour.
func rate(p) -> float:
	return (RATE_BASE + RATE_PER_SKILL * float(p.skills.Building)) * sim.perf(p) * sim.traits.mult(p, "repair")


func update(dt: float) -> void:
	var hours: float = sim.game_hours(dt)
	var salvagers: Array = sim.jobs.working("salvage")
	if not salvagers.is_empty():
		sim.stock.scrap = float(sim.stock.scrap) + SALVAGE_PER_HOUR * float(salvagers.size()) * hours
	var pl := active_site()
	if pl.is_empty():
		return
	var done := 0.0
	var hands: Array = crew()
	for p in hands:
		var w: float = rate(p) * hours
		done += w
		sim.skills.credit(p, "mended", w * MEND_PER_WORK_HOUR)
	if done <= 0.0:
		return
	_hammer -= dt
	if _hammer <= 0.0:
		_hammer = HAMMER_EVERY
		sim.events.append({"type": "hammer", "x": hands[0].x, "y": hands[0].y})
	pl.site.progress = float(pl.site.progress) + done
	if float(pl.site.progress) >= float(pl.site.work):
		_finish(pl)


func _finish(pl: Dictionary) -> void:
	var id := String(pl.site.building)
	pl.building = id
	pl.site = {}
	_queue.erase(String(pl.id))
	_block(pl)
	version += 1
	var label := String(building(id).name)
	sim.events.append({"type": "built", "plot": pl.id, "building": id})
	sim.alert("built-%s" % String(pl.id), "info", "The %s is finished" % label.to_lower(), String(pl.name), Vector2(pl.pos), 14.0)


# --------------------------------------------------------------- footprints --

## The tiles (indices into the walking grids) a standing building shuts: its `solid` rectangle in
## assets/data/building_art.json, [x0, y0, x1, y1] in tiles from the plot's centre; none when absent.
func footprint_tiles(plot_id: String) -> Array:
	var pl := plot(plot_id)
	if pl.is_empty() or pl.building == "":
		return []
	var rect = _art.get(String(pl.building), {}).get("solid", [])
	if not rect is Array or rect.size() < 4:
		return []
	var x0 := float(pl.pos.x) + float(rect[0])
	var y0 := float(pl.pos.y) + float(rect[1])
	var x1 := float(pl.pos.x) + float(rect[2])
	var y1 := float(pl.pos.y) + float(rect[3])
	var out: Array = []
	for ty in range(floori(y0), floori(y1 - 0.001) + 1):
		for tx in range(floori(x0), floori(x1 - 0.001) + 1):
			if tx >= 0 and ty >= 0 and tx < sim.world.W and ty < sim.world.H:
				out.append(ty * sim.world.W + tx)
	return out


func _block(pl: Dictionary) -> void:
	_unblock(pl)
	var tiles := footprint_tiles(String(pl.id))
	if tiles.is_empty():
		return
	# only tiles that are open now are shut (and so given back); a prop's own are left as they are
	var shut: Array = []
	for i in tiles:
		if sim.world.solid_p[int(i)] == 0:
			shut.append(i)
	pl.solid = shut
	sim.block_tiles(shut, true)


func _unblock(pl: Dictionary) -> void:
	if not pl.solid.is_empty():
		sim.block_tiles(pl.solid, false)
	pl.solid = []


# -------------------------------------------------------------------- save --

func save() -> Dictionary:
	var out := {}
	for p in _plots:
		if p.building != "" or not p.site.is_empty():
			out[String(p.id)] = {"building": String(p.building), "site": p.site.duplicate()}
	return {"plots": out, "queue": _queue.duplicate()}


func load_state(d: Dictionary) -> void:
	_reset()
	var saved = d.get("plots", {})
	if saved is Dictionary:
		for id in saved:
			var pl := plot(String(id))
			var r = saved[id]
			if pl.is_empty() or not r is Dictionary:
				continue
			var b := String(r.get("building", ""))
			if _building_by_id.has(b):
				pl.building = b
			var s = r.get("site", {})
			if s is Dictionary and _building_by_id.has(String(s.get("building", ""))) and pl.building == "":
				var data := building(String(s.building))
				pl.site = {"building": String(s.building), "progress": float(s.get("progress", 0.0)),
					"work": float(s.get("work", data.work)), "scrap": float(s.get("scrap", data.scrap))}
	var q = d.get("queue", [])
	if q is Array:
		for id in q:
			var pl := plot(String(id))
			if not pl.is_empty() and not pl.site.is_empty() and not _queue.has(String(id)):
				_queue.append(String(id))
	for p in _plots:
		if not p.site.is_empty() and not _queue.has(String(p.id)):
			_queue.append(String(p.id))
		if p.building != "":
			_block(p)
	version += 1
