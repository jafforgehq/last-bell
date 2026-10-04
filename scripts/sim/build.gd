## Buildings. The compound has fixed plots (assets/data/plots.json), and since round 15 each plot is the HOME of one
## building (`home`, with a number `n` when the building may stand more than once, a `name` that says where it is and a
## `why` sentence): the player picks a building and never a plot, and `home_for(building)` is the first home that is free.
## Ordering pays the scrap (assets/data/buildings.json) and puts a site on the home; by day the people on the Builders job
## work the oldest site (the progress is in builder-hours: a good builder is worth two); a finished site becomes the
## building, whose effects the other modules read through `bonus(key)` and `factor(key)`. A building may be demolished
## (half the scrap back) and a site cancelled (all the scrap back if no work was done, else half). A second home waits
## for the first (`why_not`), so the order the homes are built in is not a choice either.
##
## The Builders' goal while a site is up is the plot's work spot (`jobs.seat_pos`), so the people
## "working" the Builders station are the ones building; a wall under the crew's threshold still
## comes first (a person sent to mend a wall is on that order). The Salvage station (stations.json,
## `requires` the salvage bench) is worked here: each person at it makes SALVAGE_PER_HOUR scrap.
##
## Round 7 asks `housing()` and `radio_range()`.
##
## Round 9 adds the lots' plots (assets/data/lots.json, `lots.gd`): ring plots (`kind` "ring": the homes of the scrap yard)
## and mouths (`kind` "mouth": a wall across a street, ordered like a building from the wall
## kits, which are catalogue entries with a `wall_kit`; when finished `lots.on_wall_built` makes the wall section).
## They are seen (`plots()`) only once their lot is claimed.
##
## Round 15 (the homes): a save from before has what it had refunded when its plot is no more or is another building's home
## (`load_state`); a tower reaches from its own body, the nearest point of its footprint, not from the middle of its lot.
##
## Events: {"type": "site"|"built"|"cancelled"|"demolished", "plot": id, "building": id}.
## Alerts: `built-<plot id>` when a building is finished.
extends RefCounted

const Lots := preload("res://scripts/sim/lots.gd")
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
## The plots that are open to use (see `plots`): the yard's own, and those of the lots that are claimed.
var _visible: Array = []
var _visible_dirty := true
## The ids of the buildings the catalogue is held to (the demo's list); empty for no limit.
var only: Array = []


func setup(s) -> void:
	sim = s
	_load_data()


func _load_data() -> void:
	var key := plots_path + "|" + buildings_path + "|" + art_path + "|" + Lots.data_path
	if not _cache.has(key):
		var plots: Array = []
		var rawp = JSON.parse_string(FileAccess.get_file_as_string(plots_path))
		for r in (rawp.get("plots", []) if rawp is Dictionary else []):
			var p: Dictionary = {
				"id": String(r.id), "name": String(r.name), "kind": String(r.get("kind", "yard")),
				"home": String(r.get("home", "")), "n": int(r.get("n", 1)), "why": String(r.get("why", "")),
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
			b["effects"] = r.get("effects", {})
			buildings.append(b)
		_add_lots_data(plots, buildings)
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
	_visible_dirty = true


## The lots' ring plots and mouths join the plots, and the wall kits the catalogue.
func _add_lots_data(plots: Array, buildings: Array) -> void:
	var d := Lots.load_data()
	for r in d.plots:
		plots.append({
			"id": String(r.id), "name": String(r.get("name", r.id)), "kind": String(r.get("kind", "ring")), "lot": String(r.get("lot", "")),
			"home": String(r.get("home", "")), "n": int(r.get("n", 1)), "why": String(r.get("why", "")),
			"pos": Vector2(float(r.pos[0]), float(r.pos[1])), "size": Vector2(float(r.size[0]), float(r.size[1])),
			"work": Vector2(float(r.work[0]), float(r.work[1])),
		})
	for m in d.mouths:
		var post: Dictionary = m.post
		var at: Vector2 = m.center
		var spot := Vector2(float(post.pos[0]), float(post.pos[1])) if post.has("pos") else at
		var kit_ids: Array = []
		for k in m.kits:
			kit_ids.append(String(k))
		var rect: Array = m.rect
		plots.append({
			"id": String(m.id), "name": String(m.name), "kind": "mouth", "lot": String(m.get("lot", "")), "home": "", "n": 1, "why": "",
			"pos": at, "size": Vector2(float(rect[2]) - float(rect[0]) + 1.0, float(rect[3]) - float(rect[1]) + 1.0), "work": spot,
			"kits": kit_ids, "dir": String(m.dir),
		})
	for k in d.kits:
		var kit: Dictionary = d.kits[k]
		buildings.append({
			"id": "wall_%s" % String(k), "name": String(kit.get("name", k)), "blurb": String(kit.get("blurb", "A wall across a street.")),
			"scrap": int(kit.scrap), "work": float(kit.work), "max": 99, "requires": "", "effects": {},
			"wall_kit": String(k), "hp": float(kit.hp), "dir": String(kit.get("dir", "h")), "length": float(kit.length),
		})


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
	if _visible_dirty:
		refresh_plots()
	return _visible


## Works out which plots are open (the lots' ones only when their lot is claimed). In the classic start
## that is the yard's own, always.
func refresh_plots() -> void:
	_visible = []
	for p in _plots:
		if sim.lots.plot_open(p) and (only.is_empty() or String(p.get("home", "")) == "" or only.has(String(p.home))):    # (the demo's plots are those of its short list)
			_visible.append(p)
	_visible_dirty = false


## A plot's data and state, or {} when there is no such plot.
func plot(id: String) -> Dictionary:
	return _plot_by_id.get(id, {})


## The plot whose lot contains this point (tile units), or "".
func plot_at(at: Vector2) -> String:
	for p in plots():
		var half: Vector2 = Vector2(p.size) / 2.0
		if absf(at.x - p.pos.x) <= half.x and absf(at.y - p.pos.y) <= half.y:
			return String(p.id)
	return ""


# ------------------------------------------------------------------- homes --

## The homes of a building (the plots that are for it), in their order (1, 2, ...): all of them, whether their lot is
## claimed or not. Empty for a building with no home (a wall kit) or one that is not known.
func homes_of(building_id: String) -> Array:
	var out: Array = []
	for p in _plots:
		if String(p.get("home", "")) == building_id and building_id != "":
			out.append(p)
	out.sort_custom(func(a, b): return int(a.n) < int(b.n))
	return out


## Where a building goes if it is ordered now: the first of its homes that has nothing on it and no site and whose lot is
## claimed ("" when there is none). The player never chooses: the Build screen's Order is `order(home_for(id), id)`.
func home_for(building_id: String) -> String:
	for p in homes_of(building_id):
		if p.building == "" and p.site.is_empty() and sim.lots.plot_open(p):
			return String(p.id)
	return ""


## What a plot is called to a player: its building's name, numbered when the building has more than one home
## ("Watchtower 2 of 2"); the plot's own name for a wall across a street.
func title_of(plot_id: String) -> String:
	var pl := plot(plot_id)
	if pl.is_empty():
		return ""
	var home := String(pl.get("home", ""))
	if home == "" or not _building_by_id.has(home):
		return String(pl.name)
	var n := homes_of(home).size()
	var label := String(building(home).name)
	return "%s %d of %d" % [label, int(pl.n), n] if n > 1 else label


# --------------------------------------------------------------- catalogue --

func catalogue() -> Array:
	if sim.lots.on:
		return _catalogue
	var out: Array = []
	for b in _catalogue:
		if not b.has("wall_kit") and not bool(b.get("lots_only", false)) and (only.is_empty() or only.has(String(b.id))):
			out.append(b)
	return out


## The demo's short list (round 26, scripts/sim/demo_run.gd): these are the only buildings the catalogue offers, in the order of the full catalogue
## (empty: all of them, as ever). Not saved: the demo's scenario puts it again before a save is read.
func restrict(ids: Array) -> void:
	only = ids.duplicate()
	_visible_dirty = true


## A building's data, or {} when there is no such building.
func building(id: String) -> Dictionary:
	if not only.is_empty() and not only.has(id):
		return {}    # (round 26: in the demo a building outside its short list is not a building at all)
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
	if key == "night_reach_mult" and sim.problems.blocks("floodlights"):    # (round 25: a jammed generator: the floodlights are dark; false inactive)
		return 1.0
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
	for pl in plots():
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
## watchtower): the best of the standing buildings with a `reach_bonus` that are within their `reach_radius` of the point
## (towers do not add up). Near means near the building itself (round 15): the nearest point of its footprint, as a
## shooter on the walkway sees the tower, not the middle of its lot, so a tower on the north wall reaches the two
## posts either side of it.
func reach_bonus_at(at: Vector2) -> float:
	var best := 0.0
	for pl in _plots:
		if pl.building == "":
			continue
		var e: Dictionary = building(String(pl.building)).effects
		if e.has("reach_bonus") and distance_to_body(String(pl.id), at) <= float(e.get("reach_radius", 0.0)):
			best = maxf(best, float(e.reach_bonus))
	return best


## The tiles a building's body covers (its `solid` rectangle in building_art.json, from the plot's centre), else its lot.
func body_rect(plot_id: String) -> Rect2:
	var pl := plot(plot_id)
	if pl.is_empty():
		return Rect2()
	var rect = _art.get(String(pl.building), {}).get("solid", []) if pl.building != "" else []
	if rect is Array and rect.size() >= 4:
		return Rect2(float(pl.pos.x) + float(rect[0]), float(pl.pos.y) + float(rect[1]), float(rect[2]) - float(rect[0]), float(rect[3]) - float(rect[1]))
	return Rect2(Vector2(pl.pos) - Vector2(pl.size) / 2.0, Vector2(pl.size))


## How far a point is from a plot's body (tiles): nothing inside it.
func distance_to_body(plot_id: String, at: Vector2) -> float:
	var r := body_rect(plot_id)
	var d := (at - r.get_center()).abs() - r.size / 2.0
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()


# ------------------------------------------------------------------ orders --

## Why this building cannot be ordered on this plot now ("" when it can). A plot is the home of one building: another
## building is told what the place is for, and the second home of a building waits for the first.
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
	if not sim.lots.plot_open(pl):
		return "claim the lot first"
	if b.has("wall_kit"):
		if pl.kind != "mouth" or not pl.kits.has(String(b.wall_kit)):
			return "it does not fit across this street"
	elif pl.kind == "mouth":
		return "only a wall goes across a street"
	elif String(pl.get("home", "")) != building_id:
		var of := String(pl.get("home", ""))
		return "this place is for the %s" % String(building(of).get("name", "")).to_lower() if _building_by_id.has(of) else "nothing is built here"
	else:
		for q in homes_of(building_id):
			if int(q.n) < int(pl.n) and q.building == "" and q.site.is_empty() and sim.lots.plot_open(q):
				return "order the first %s first" % String(b.name).to_lower()
	if _count_with_sites(building_id) >= _max_of(b):
		return "there is already %s" % ("one" if _max_of(b) == 1 else "the most (%d)" % _max_of(b))
	if String(b.requires) != "" and not built(String(b.requires)):
		return "it needs the %s first" % String(building(String(b.requires)).name).to_lower()
	if float(sim.stock.scrap) + 1.0e-9 < float(b.scrap):
		return "it needs %d scrap" % int(b.scrap)
	return ""


## Why this building cannot be ordered now, on its home ("" when it can): what the Build screen writes under a building.
func why_not_build(building_id: String) -> String:
	var b := building(building_id)
	if b.is_empty():
		return "there is no such building"
	var home := home_for(building_id)
	if home != "":
		return why_not(home, building_id)
	if _count_with_sites(building_id) >= _max_of(b):
		return "there is already %s" % ("one" if _max_of(b) == 1 else "the most (%d)" % _max_of(b))
	for p in homes_of(building_id):
		if p.building == "" and p.site.is_empty() and not sim.lots.plot_open(p):
			var lot: Dictionary = sim.lots.lot(String(p.get("lot", "")))
			return "claim %s first" % String(lot.get("name", "its lot")).to_lower()
	return "there is no room for it"


## How many of a building may stand: its `max`, and each claimed lot allows its `lot_max` more.
func _max_of(b: Dictionary) -> int:
	return int(b.max) + int(b.get("lot_max", 0)) * sim.lots.claimed_on.size()


## Pays the scrap and puts a site on the plot. False, and nothing changes, if it cannot be ordered.
func order(plot_id: String, building_id: String) -> bool:
	if why_not(plot_id, building_id) != "":
		return false
	var b := building(building_id)
	sim.stock.scrap = maxf(0.0, float(sim.stock.scrap) - float(b.scrap))
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
	if pl.kind == "mouth":
		return "a wall is not pulled down: mend it or let it fall"
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


## A building is lost to the dead (a raid on a lot): gone with nothing back.
func ruin(plot_id: String) -> bool:
	var pl := plot(plot_id)
	if pl.is_empty() or pl.building == "":
		return false
	_unblock(pl)
	pl.building = ""
	version += 1
	sim.jobs.trim()
	return true


func _finish(pl: Dictionary) -> void:
	var id := String(pl.site.building)
	pl.building = id
	pl.site = {}
	_queue.erase(String(pl.id))
	version += 1
	if building(id).has("wall_kit"):
		sim.events.append({"type": "built", "plot": pl.id, "building": id})
		sim.lots.on_wall_built(String(pl.id), String(building(id).wall_kit))
		return
	_block(pl)
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


## What the buildings that were taken out of the game cost (for the refund of an old save that has one standing).
const LEGACY_COSTS := {"orchard": 24, "cistern": 20}


## Whether a building is the one a plot is for (a wall across a street takes its kits, which the lots module checks).
func _belongs(pl: Dictionary, building_id: String) -> bool:
	return String(pl.kind) == "mouth" or String(pl.get("home", "")) == building_id


func load_state(d: Dictionary) -> void:
	_reset()
	var saved = d.get("plots", {})
	var refund := 0.0
	if saved is Dictionary:
		for id in saved:
			var pl := plot(String(id))
			var r = saved[id]
			if not r is Dictionary:
				continue
			var b := String(r.get("building", ""))
			var s = r.get("site", {})
			var site_b := String(s.get("building", "")) if s is Dictionary else ""
			# a plot that is no more (an older game had other ones: round 11 cut some, round 15 gave every building a home of its
			# own), a building that is no more, or one on a plot that is another building's home: the scrap comes back, a site in
			# full and a standing building by REFUND_SHARE
			var keep_b := not pl.is_empty() and b != "" and _building_by_id.has(b) and _belongs(pl, b)
			if b != "" and not keep_b:
				refund += float(LEGACY_COSTS.get(b, building(b).get("scrap", 0))) * REFUND_SHARE
			var keep_s := not pl.is_empty() and not keep_b and site_b != "" and _building_by_id.has(site_b) and _belongs(pl, site_b)
			if site_b != "" and not keep_s:
				refund += float(s.get("scrap", 0.0))
			if keep_b:
				pl.building = b
			elif keep_s:
				var data := building(site_b)
				pl.site = {"building": site_b, "progress": float(s.get("progress", 0.0)),
					"work": float(s.get("work", data.work)), "scrap": float(s.get("scrap", data.scrap))}
	if refund > 0.0:
		sim.stock.scrap = float(sim.stock.scrap) + refund
		sim.alert("refund", "info", "Scrap back from plots that are no more", "%d scrap" % roundi(refund), null, 20.0)
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
