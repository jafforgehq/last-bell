## Jobs and stations. By day every person has a job: a station (the workbench, the wall crew,
## the vegetable beds, the infirmary, the radio desk, the lookout post) with a number of
## seats, a spot to stand at and an effect; by night everyone holds a named post on the wall.
## This module keeps who is where (assignments, seats, posts, the stations' settings), says
## who is working a station right now (`working`, which the effect modules ask), supplies the
## goals the rules follow (`goal_for` by day, `post_goal` by night) and fills the seats by skill
## (`auto_assign`; `refill` fills one seat the avatar left). What a station does is the business of the module it belongs to: the
## workshop makes the ammo, tactics mends the walls and keeps watch, supplies grows the food,
## medical heals, the storyteller takes the noon call.
##
## Precedence of what a person does is `sim._goal_for`: an order, then a treatment or a trip,
## then (by night) the post, then (by day) the station's seat. Orders end when released and
## the person goes back to their job.
##
## WORK LIFE (round 16, the settlement game only: a small start, `sim.recruits.small`; the classic
## start keeps what it had). By day people are at work, not on the walls: the Builders build at the
## site, mend a worn wall (tactics) or, with neither to do, sort materials at the builders' yard
## (`idle_pos`); a person with no job rests at a rest spot (a picnic table, the fire), `rest` in
## stations.json, one spot each in turn. At the bell they hold their posts, and so they do by day when
## the dead come to the wall (`sim.threat_by_day`), the lookout aside, who stays at the tower. Every
## goal carries the `work` word of what the person does there (the station's `work`; "mend" for a
## wall, "haul" for the yard, "rest"): the rules set `Person.work` from it when they stand at the spot.
##
## Data: assets/data/stations.json and assets/data/posts.json; the six starting people's
## default job and post are `station` and `post_id` in their roster entries. Buildings (build.gd)
## change the stations: a station with `requires` exists only while that building stands (it is
## worked at that building's plot), and `seats_<id>` effects add seats; `stations()` and
## `station(id)` give the stations as they are now.
##
## ONE HOUSE (CREW): the Scavenger is a station that only the town has (`install_layout` adds it with the base: two seats, `MANUAL`: given by request only); its work is scripts/town/crew_search.gd
## (`goal_for` asks it for the goal), which sends the person to the cleared houses by day.
## Events: {"type": "assigned", "who": id, "station": id}. Alerts: `job-radio`, `job-watch`
## when the desk or the post is empty late in the morning or the afternoon.
extends RefCounted

const STATIONS_PATH := "res://assets/data/stations.json"
const POSTS_PATH := "res://assets/data/posts.json"
## Where the data is read from (tests may point it at another file).
static var stations_path := STATIONS_PATH
static var posts_path := POSTS_PATH
static var _cache := {}

## Someone is at their seat when within this many tiles of it.
const AT_STATION := 0.6
## Where the seats of a station are, round its spot (the first seat is the spot itself).
const SEAT_OFFSETS := [Vector2(0.0, 0.0), Vector2(1.1, 0.0), Vector2(-1.1, 0.0), Vector2(0.0, -1.1)]
## An empty radio desk is said from 11:30 (the noon call is at 12:00) and an empty lookout post from
## 16:30 (the forecast is at 17:00).
const RADIO_ALERT_HOUR := 11.5
const WATCH_ALERT_HOUR := 16.5
const ALERT_TTL := 20.0
## The order Auto-assign fills the stations in (one seat each first, then what is left over): the
## work first (the bench, the wall crew, the beds), then the desks, the radio last, so a crew that is
## short-handed works before it listens.
const AUTO_ORDER := ["bench", "builders", "garden", "watch", "infirmary", "radio", "salvage"]
const AUTO_SECOND_PASS := ["builders", "garden", "bench", "infirmary", "salvage"]
## Traits that make a person a better fit for a station.
const AUTO_TRAITS := {"bench": "tinkerer", "builders": "tinkerer", "infirmary": "triage", "watch": "sharp_eyed"}
## One House: the stations that are only ever given by a request (the Jobs page, the radio): Auto-assign, Fill empty seats and the priorities' staffing never fill or empty them, and they are not
## counted among the empty seats. The Scavenger (scripts/town/crew_search.gd): two seats, installed with the base's layout.
const MANUAL := ["scavenger"]
const SCAVENGER := {"id": "scavenger", "name": "Scavenger", "where": "the front yard", "seats": 2, "skill": "", "icon": "scavenge", "what": "Ready to go out", "work": "", "settings": {},
	"blurb": "By day they search the cleared houses for you, nearest first, and are back before the bell. Nothing to search: clear another house."}
## The stations that give up a worker, first to last, when a seat that was left (the avatar's) is filled from a crew at work
## (`refill`): what can wait goes first, the bench (the ammunition) last. The desks are not here.
const GIVE_UP_ORDER := ["salvage", "garden", "builders", "watch", "bench"]

var sim
## Person id -> station id ("" none), person id -> post id, and station id -> {setting: value}.
var assignments := {}
var post_ids := {}
var settings := {}
var _alert_day := {"radio": 0, "watch": 0}
var _stations: Array = []
var _station_by_id := {}
## The stations as they are now (the buildings' seats, the ones that need a building not yet built left
## out of `stations()`), kept by the buildings' version.
var _now: Array = []
var _now_by_id := {}
var _now_version := -1
var _now_settled := false
## Where the people with no job rest by day: {"what", "work", "spots": [{"pos", "face"}]}.
var _rest := {"what": "Resting", "work": "rest", "spots": []}
var _posts: Array = []
var _base_posts: Array = []
var _post_by_id := {}
## Whether a generated base's layout is installed (`install_layout`).
var _layout_on := false


func setup(s) -> void:
	sim = s
	_load_data()


func _load_data() -> void:
	var key := stations_path + "|" + posts_path
	if not _cache.has(key):
		var stations: Array = []
		var raw = JSON.parse_string(FileAccess.get_file_as_string(stations_path))
		var list = raw.get("stations", []) if raw is Dictionary else []
		for r in list:
			var st: Dictionary = r.duplicate(true)
			st["pos"] = Vector2(float(r.pos[0]), float(r.pos[1]))
			if r.has("idle_pos"):
				st["idle_pos"] = Vector2(float(r.idle_pos[0]), float(r.idle_pos[1]))
			st["seats"] = int(r.get("seats", 1))
			st["skill"] = String(r.get("skill", ""))
			st["settings"] = r.get("settings", {})
			stations.append(st)
		var posts: Array = []
		var rawp = JSON.parse_string(FileAccess.get_file_as_string(posts_path))
		for r in (rawp.get("posts", []) if rawp is Dictionary else []):
			var po: Dictionary = r.duplicate(true)
			var at := Vector2(float(r.pos[0]), float(r.pos[1]))
			po["pos"] = at
			po["face"] = _face_of(at)
			posts.append(po)
		var rest := {"what": "Resting", "work": "rest", "spots": []}
		var rr = raw.get("rest", {}) if raw is Dictionary else {}
		if rr is Dictionary:
			rest.what = String(rr.get("what", "Resting"))
			rest.work = String(rr.get("work", "rest"))
			for sp in rr.get("spots", []):
				rest.spots.append({"pos": Vector2(float(sp.pos[0]), float(sp.pos[1])), "face": String(sp.get("face", ""))})
		_cache[key] = {"stations": stations, "posts": posts, "rest": rest}
	var c: Dictionary = _cache[key]
	_rest = c.rest
	_stations = c.stations
	_posts = c.posts
	_base_posts = c.posts
	_station_by_id.clear()
	for st in _stations:
		_station_by_id[String(st.id)] = st
	_post_by_id.clear()
	for po in _posts:
		_post_by_id[String(po.id)] = po


## A generated base's stations, posts and resting spots in place of the file's (One House: the claim installs them, base_layout.gd).
## `stations` are as stations.json's entries (pos as [x, y] or Vector2), `posts` likewise with their own `face` ("N", "E", "S", "W": the school's
## `_face_of` is the file's fallback only), `rest` is {"what", "work", "spots": [{"pos", "face"}]}. Everyone's night post is made again
## (kept where it is still a post) and the stations' settings are kept for the stations of the same id.
func install_layout(stations: Array, posts: Array, rest: Dictionary) -> void:
	var kept := settings.duplicate(true)
	_stations = []
	_station_by_id.clear()
	for r in stations:
		var st: Dictionary = r.duplicate(true)
		st["pos"] = _vec(r.pos)
		if r.has("idle_pos"):
			st["idle_pos"] = _vec(r.idle_pos)
		st["seats"] = int(r.get("seats", 1))
		st["skill"] = String(r.get("skill", ""))
		st["settings"] = r.get("settings", {})
		_stations.append(st)
		_station_by_id[String(st.id)] = st
	if sim.is_one_house() and not _station_by_id.has("scavenger"):
		_add_scavenger(rest)
	_posts = []
	for r in posts:
		var po: Dictionary = r.duplicate(true)
		po["pos"] = _vec(r.pos)
		po["face"] = String(r.get("face", _face_of(po.pos)))
		_posts.append(po)
	_base_posts = _posts
	_post_by_id.clear()
	for po in _posts:
		_post_by_id[String(po.id)] = po
	_rest = {"what": String(rest.get("what", "Resting")), "work": String(rest.get("work", "rest")), "spots": [], "night": []}
	for sp in rest.get("spots", []):
		_rest.spots.append({"pos": _vec(sp.pos), "face": String(sp.get("face", ""))})
	for sp in rest.get("night", []):
		_rest.night.append({"pos": _vec(sp.pos), "face": String(sp.get("face", ""))})
	settings.clear()
	for st in _stations:
		var id := String(st.id)
		var s := {}
		for k in st.settings:
			s[k] = kept.get(id, {}).get(k, st.settings[k].default)
		settings[id] = s
	var old := post_ids.duplicate()
	post_ids.clear()
	var taken := {}
	for p in sim.people:
		var po := String(old.get(String(p.id), ""))
		if _post_by_id.has(po) and not taken.has(po):
			post_ids[String(p.id)] = po
			taken[po] = true
	for p in sim.people:
		if not post_ids.has(String(p.id)):
			post_ids[String(p.id)] = _free_post(taken)
			taken[post_ids[String(p.id)]] = true
	for p in sim.people:
		var job := String(assignments.get(String(p.id), ""))
		if job != "" and not _station_by_id.has(job):
			assignments[String(p.id)] = ""
		p.goal_key = ""
	_now_version = -1
	_layout_on = true
	if sim.get("build") != null:
		sim.build.version += 1


## One House: the Scavenger's station, with the base. Its two seats are the last two resting spots of the layout (the people with no job take them from the first), and when they have no
## house to go to they stand there.
func _add_scavenger(rest: Dictionary) -> void:
	var st: Dictionary = SCAVENGER.duplicate(true)
	var spots: Array = rest.get("spots", [])
	var yard: Vector2 = sim.base.yard_middle() if sim.get("base") != null else sim.yard_middle()
	var a: Vector2 = _vec(spots[spots.size() - 1].pos) if not spots.is_empty() else yard
	var b: Vector2 = _vec(spots[maxi(0, spots.size() - 2)].pos) if spots.size() > 1 else a
	st["pos"] = a
	st["seat_offsets"] = [Vector2.ZERO, b - a]
	if a == b:
		st["seat_offsets"] = [Vector2.ZERO, Vector2.ZERO]
	_stations.append(st)
	_station_by_id["scavenger"] = st


## The file's stations, posts and resting spots again (a new run, or a base is let go).
func clear_layout() -> void:
	_load_data()
	_layout_on = false
	var kept := settings.duplicate(true)
	settings.clear()
	for st in _stations:
		var s := {}
		for k in st.settings:
			s[k] = kept.get(String(st.id), {}).get(k, st.settings[k].default)
		settings[String(st.id)] = s
	_now_version = -1


static func _vec(v) -> Vector2:
	return v if v is Vector2 else Vector2(float(v[0]), float(v[1]))


## The way someone at this spot on the wall faces.
static func _face_of(at: Vector2) -> String:
	if at.x < 22.0:
		return "N" if at.y < 19.0 else "W"
	if at.x > 62.0:
		return "N" if at.y < 19.0 else "E"
	return "N"


## Someone joined the crew: the job their def names, if it has a free seat (a recruit's def names none).
func person_added(p) -> void:
	var id := String(p.def.get("station", ""))
	if id != "" and unlocked(id) and seats_left(id) > 0:
		assignments[String(p.id)] = id
	post_of(p)    # a night post from the start (it is kept in the save), not at the first dusk


func start() -> void:
	if _layout_on:
		clear_layout()    # (a new run on a sim that had a base)
	_alert_day = {"radio": 0, "watch": 0}
	_defaults()


## The starting jobs, posts and settings: the roster's own where it names them.
func _defaults() -> void:
	assignments.clear()
	post_ids.clear()
	settings.clear()
	for st in _stations:
		var s := {}
		for k in st.settings:
			s[k] = st.settings[k].default
		settings[String(st.id)] = s
	var taken := {}
	for p in sim.people:
		var id := String(p.def.get("station", ""))
		assignments[String(p.id)] = id if _station_by_id.has(id) else ""
		var po := String(p.def.get("post_id", ""))
		if _post_by_id.has(po) and not taken.has(po):
			post_ids[String(p.id)] = po
			taken[po] = true
	for p in sim.people:
		if not post_ids.has(String(p.id)):
			post_ids[String(p.id)] = _free_post(taken)
			taken[post_ids[String(p.id)]] = true


## The first post nobody holds.
func _free_post(taken: Dictionary) -> String:
	for po in _posts:
		if not taken.has(String(po.id)):
			return String(po.id)
	return String(_posts[0].id) if not _posts.is_empty() else ""


# ---------------------------------------------------------------- stations --

## The stations that exist now, as they are now (their seats, and where they are worked).
func stations() -> Array:
	_refresh_now()
	return _now


## A station's data as it is now, or {} when there is no such station. (A station whose building is
## not built is found here too, with `locked` true and no seats.)
func station(id: String) -> Dictionary:
	_refresh_now()
	return _now_by_id.get(id, {})


func _refresh_now() -> void:
	var v: int = sim.build.version if sim != null and sim.get("build") != null else 0
	var settled := _settled()
	if v == _now_version and settled == _now_settled and not _now.is_empty():
		return
	_now_version = v
	_now_settled = settled
	_now.clear()
	_now_by_id.clear()
	for st in _stations:
		var e: Dictionary = st.duplicate()
		var id := String(st.id)
		var open := unlocked(id)
		e["locked"] = not open
		e["seats"] = seats_of(id)
		var req := String(st.get("requires", ""))
		if req != "" and open:
			var at: Vector2 = sim.build.spot_of(req)
			if at != Vector2.ZERO:
				e["pos"] = at
		if settled and st.has("idle_pos"):
			# the settlement's Builders work in the yard when there is nothing to build or mend: that is their station
			e["pos"] = st.idle_pos
			e["where"] = String(st.get("idle_where", st.get("where", "")))
		_now_by_id[id] = e
		if open:
			_now.append(e)


## Whether this station exists now: it needs no building, or its building stands.
func unlocked(id: String) -> bool:
	var st: Dictionary = _station_by_id.get(id, {})
	if st.is_empty():
		return false
	var req := String(st.get("requires", ""))
	return req == "" or (sim != null and sim.get("build") != null and sim.build.built(req))


## The seats a station has now: its own and what the standing buildings add; none while the building
## it needs is not there.
func seats_of(id: String) -> int:
	if not unlocked(id):
		return 0
	var extra := 0
	if sim.get("build") != null:
		extra = int(sim.build.bonus("seats_%s" % id))
	return int(_station_by_id[id].seats) + extra


func job_of(p) -> String:
	var id := String(assignments.get(String(p.id), ""))
	return id if _station_by_id.has(id) else ""


## The people assigned to a station who are alive (those away on a trip still hold their seat).
func crew_of(id: String) -> Array:
	var out: Array = []
	for p in sim.people:
		if job_of(p) == id and not p.dead and not p.turned:
			out.append(p)
	return out


## The seats of a station that someone who is here could sit in: a seat held by a person away on a
## trip counts as free (assigning someone else to it sends the holder back without a job, so a desk
## can be kept staffed through a trip).
func seats_left(id: String) -> int:
	if not _station_by_id.has(id):
		return 0
	var here := 0
	for p in crew_of(id):
		if p.away == null:
			here += 1
	return seats_of(id) - here


## Why this person cannot be given this job ("" when they can).
func why_not(p, id: String) -> String:
	if id == "":
		return ""
	if not _station_by_id.has(id):
		return "there is no such job"
	if p.dead or p.turned:
		return "they are gone"
	if job_of(p) == id:
		return ""
	if not unlocked(id):
		return "the %s is not built yet" % String(_station_by_id[id].name).to_lower()
	if seats_left(id) <= 0:
		return "no free seat at the %s" % String(_station_by_id[id].name)
	return ""


## Gives a person a job (taking them off their old one). False, and nothing changes, if they
## cannot have it.
func assign(p, id: String) -> bool:
	if id == "":
		unassign(p)
		return true
	if why_not(p, id) != "":
		return false
	if job_of(p) != id:
		_make_room(id)
		assignments[String(p.id)] = id
		p.goal_key = ""
		sim.tactics.call_back(p)    # a new job ends the trip the wall crew had sent them on
		sim.events.append({"type": "assigned", "who": p.id, "station": id})
	return true


## Before a seat is given: if the station holds as many people as it has seats (some of them away on a
## trip, or `why_not` would have refused), those away give up theirs, so a station never holds more
## people than it has seats.
func _make_room(id: String) -> void:
	var seats := seats_of(id)
	for q in crew_of(id):
		if crew_of(id).size() < seats:
			break
		if q.away != null:
			unassign(q)


func unassign(p) -> void:
	if job_of(p) != "":
		assignments[String(p.id)] = ""
		p.goal_key = ""
		sim.tactics.call_back(p)
		sim.events.append({"type": "assigned", "who": p.id, "station": ""})


## After a building came down: whoever holds a station that is gone, or a seat the station no longer has,
## is let go: the ones away on a trip first, then the ones who sit last (the seats are filled in the
## order of the crew list, so the first keep theirs).
func trim() -> void:
	for st in _stations:
		var id := String(st.id)
		var crew := crew_of(id)
		var seats := seats_of(id)
		if crew.size() <= seats:
			continue
		var order: Array = []
		for i in range(crew.size() - 1, -1, -1):
			if crew[i].away != null:
				order.append(crew[i])
		for i in range(crew.size() - 1, -1, -1):
			if crew[i].away == null:
				order.append(crew[i])
		for i in crew.size() - seats:
			unassign(order[i])


## Takes everyone off their jobs.
func clear() -> void:
	for p in sim.people:
		assignments[String(p.id)] = ""
		p.goal_key = ""
		sim.tactics.call_back(p)


## Which seat of their station this person has (0, 1, ...).
func seat_index(p) -> int:
	var crew := crew_of(job_of(p))
	return maxi(0, crew.find(p))


## Where this person stands at their station.
func seat_pos(p) -> Vector2:
	var st := station(job_of(p))
	if st.is_empty():
		return Vector2(p.x, p.y)
	# the Builders' seat is the active building site, while there is one
	if String(st.id) == "builders" and not sim.build.active_site().is_empty():
		return sim.build.work_spot(p)
	var own = st.get("seat_offsets")    # (One House: a station of a generated base may name where its seats are, for a worktable in a room too small for the usual ones)
	if own is Array and not own.is_empty():
		return Vector2(st.pos) + _vec(own[mini(seat_index(p), own.size() - 1)])
	return Vector2(st.pos) + Vector2(SEAT_OFFSETS[mini(seat_index(p), SEAT_OFFSETS.size() - 1)])


func _able(p) -> bool:
	return not (p.dead or p.turned or p.downed or p.player) and p.away == null and not sim.morale.breakdown(p)


## Whether the settlement rules of work life are in force (a small start).
func _settled() -> bool:
	return sim != null and sim.get("recruits") != null and bool(sim.recruits.small)


## By day: until the bell (or until the night proper), and not while the dead are at the wall by day (the
## crew is at its posts then, `sim.posts_manned`).
func _day() -> bool:
	return not sim.posts_manned()


func _free(p) -> bool:
	if not _able(p) or p.drafted or p.order != null or p.repair != null:
		return false
	return sim.medical.goal_for(p) == null


## The people assigned to this station who are at their seats and free to work right now.
## The modules whose work a station is ask this.
func working(id: String) -> Array:
	var out: Array = []
	# (the lookout keeps the tower through a day under attack, and goes on watching)
	if not _day() and not (id == "watch" and sim.phase == "day"):
		return out
	for p in crew_of(id):
		if _free(p) and not p.moving and Vector2(p.x, p.y).distance_to(seat_pos(p)) <= AT_STATION:
			out.append(p)
	return out


## The first of them, or null.
func operator(id: String):
	var w := working(id)
	return w[0] if not w.is_empty() else null


## Whether this person is free and has nothing of their own to do: no job, or a job with
## nothing to make. The rules give them chores then (mending a wall that is badly worn).
func idle(p) -> bool:
	if not _able(p) or not _day() or p.drafted or p.order != null:
		return false
	var id := job_of(p)
	if id == "":
		return true
	if id == "bench" and sim.workshop.has_method("can_make"):
		return not sim.workshop.can_make()
	return false


# ---------------------------------------------------------------- settings --

func setting(id: String, key: String):
	var s: Dictionary = settings.get(id, {})
	if s.has(key):
		return s[key]
	var st := station(id)
	return st.settings[key].default if st.has("settings") and st.settings.has(key) else null


## Sets one of a station's settings, kept inside its range and its step.
func set_setting(id: String, key: String, value) -> void:
	var st := station(id)
	if st.is_empty() or not st.settings.has(key):
		return
	var def: Dictionary = st.settings[key]
	var lo := float(def.min)
	var step := maxf(float(def.step), 0.0001)
	var v := clampf(float(value), lo, float(def.max))
	v = lo + roundf((v - lo) / step) * step
	if not settings.has(id):
		settings[id] = {}
	settings[id][key] = v


# ------------------------------------------------------------------- posts --

func posts() -> Array:
	return _posts


## The posts of the lots that are claimed (round 9) join the wall's own, after them: [{"id", "name", "pos"
## (Vector2 or [x, y]), "what", "face"}]. Nobody who holds a post loses it.
func set_extra_posts(extra: Array) -> void:
	_posts = _base_posts.duplicate()
	for r in extra:
		var po: Dictionary = r.duplicate(true)
		var at = r.pos
		po["pos"] = at if at is Vector2 else Vector2(float(at[0]), float(at[1]))
		_posts.append(po)
	_post_by_id.clear()
	for po in _posts:
		_post_by_id[String(po.id)] = po


func post(id: String) -> Dictionary:
	return _post_by_id.get(id, {})


## This person's night post.
func post_of(p) -> Dictionary:
	var id := String(post_ids.get(String(p.id), ""))
	if not _post_by_id.has(id):
		var taken := {}
		for q in sim.people:
			if q != p and post_ids.has(String(q.id)):
				taken[String(post_ids[String(q.id)])] = true
		id = _free_post(taken)
		post_ids[String(p.id)] = id
	return _post_by_id.get(id, {})


## Gives someone a post. False if there is none such or another person holds it.
func set_post(p, id: String) -> bool:
	if not _post_by_id.has(id):
		return false
	for q in sim.people:
		if q != p and not (q.dead or q.turned) and String(post_ids.get(String(q.id), "")) == id:
			return false
	post_ids[String(p.id)] = id
	p.goal_key = ""
	return true


func post_pos(p) -> Vector2:
	var po := post_of(p)
	return Vector2(po.pos) if not po.is_empty() else Vector2(p.x, p.y)


# ------------------------------------------------------------------- goals --

## The night goal: hold the post.
func post_goal(p) -> Dictionary:
	var po := post_of(p)
	if po.is_empty():
		return {"x": p.x, "y": p.y, "face": "", "what": "At ease"}
	return {"x": po.pos.x, "y": po.pos.y, "face": String(po.face), "what": String(po.get("what", po.name))}


## The day goal (after any order, treatment or trip): stand at the seat (with `work`, the word of what they do
## there); with no job, rest at a rest spot in the settlement game and stand at ease in the classic one.
func goal_for(p) -> Dictionary:
	if _quiet_night():
		return night_goal(p)
	var id := job_of(p)
	if id == "":
		return rest_goal(p)
	if id == "scavenger" and sim.get("crew_search") != null:
		return sim.crew_search.job_goal(p)    # (One House: the cleared houses by day; at their seat with nothing to search)
	var st := station(id)
	var at := seat_pos(p)
	var what := String(st.get("what", st.name))
	var work := String(st.get("work", ""))
	if id == "builders":
		if not sim.build.active_site().is_empty():
			what = "Building the %s" % String(sim.build.building(String(sim.build.active_site().site.building)).name).to_lower()
		elif _settled():
			# nothing to build and (tactics) nothing to mend: sort materials at the yard
			what = String(st.get("idle_what", what))
			work = String(st.get("idle_work", ""))
		else:
			work = ""    # the classic start's Builders walk the wall
	return {"x": at.x, "y": at.y, "face": "N" if id == "radio" else "", "what": what, "work": work}


## One House: a night with no attack on (the town's quiet nights before the fourth rescue; `posts_manned` is false then). The crew is in the house by the bell, not at the
## bench or in the yard in the dark. Always false in every other game, and in a base with no night spots.
func _quiet_night() -> bool:
	if not sim.is_one_house() or _rest.get("night", []).is_empty():
		return false
	return (sim.phase == "night" or (sim.phase == "dusk" and sim.bell_rung)) and not sim.posts_manned()


## One House: the lookout's forecast is told (the attacks have begun).
func _forecast_on() -> bool:
	var sc = sim.get("scenario")
	return sc != null and sc.has_method("forecast_on") and bool(sc.forecast_on())


## Where someone turns in on a quiet night: the base's night spots in turn, in the order of the crew list (the player has no job and no spot).
func night_goal(p) -> Dictionary:
	var spots: Array = _rest.night
	var rank := 0
	for q in sim.people:
		if q == p:
			break
		if not (q.dead or q.turned) and not q.player:
			rank += 1
	var spot: Dictionary = spots[rank % spots.size()]
	return {"x": spot.pos.x, "y": spot.pos.y, "face": String(spot.face), "what": String(_rest.what), "work": String(_rest.work)}


## What someone with no job does by day: rests at their rest spot (the settlement game: the picnic tables and the
## fire; the first without a job takes the first spot, and so on), or stands where they are (the classic start).
func rest_goal(p) -> Dictionary:
	if not _settled() or _rest.spots.is_empty():
		return {"x": p.x, "y": p.y, "face": "", "what": "At ease"}
	var spot := rest_spot(p)
	var at: Vector2 = spot.pos
	return {"x": at.x, "y": at.y, "face": String(spot.face), "what": String(_rest.what), "work": String(_rest.work)}


## The rest spot of someone with no job: the spots in turn, in the order of the crew list among those with no job
## (one who is away on a trip keeps their turn).
func rest_spot(p) -> Dictionary:
	if _rest.spots.is_empty():
		return {}
	var rank := 0
	for q in sim.people:
		if q == p:
			break
		if not (q.dead or q.turned) and job_of(q) == "":
			rank += 1
	return _rest.spots[rank % _rest.spots.size()]


## The rest spots, as the data has them: [{"pos": Vector2, "face"}].
func rest_spots() -> Array:
	return _rest.spots


## What the person panel and the roster say a person with no job does by day.
func no_job_text() -> String:
	return "rest in the yard" if _settled() else "stand at ease"


# ------------------------------------------------------------- auto-assign --

## Takes everyone off their jobs and fills the stations by skill: the best fit for each in turn,
## then the rest into whatever seats are left.
func auto_assign() -> void:
	clear()
	# the people who are here first; whoever is away on a trip gets the seats that are left, to be back to
	for away in [false, true]:
		for id in AUTO_ORDER:
			if crew_of(String(id)).is_empty():
				_fill_one(String(id), away)
		for id in AUTO_SECOND_PASS:
			while _fill_one(String(id), away):
				pass


func _fill_one(id: String, away := false) -> bool:
	var best = _best_free(id, away)
	# a seat that is really open (not one held by somebody away: Auto-assign does not take those)
	if best == null or crew_of(id).size() >= seats_of(id):
		return false
	return assign(best, id)


## Fills the open seats from the people with no job who are here and on their feet, by skill (the stations in the order of
## `auto_assign`: one seat each first, then what is left over), and takes nobody off a job (no `clear`): the Jobs page's "Fill empty
## seats" (round 18; the radio's `request_fill`). `skip`: person ids that are not to be used (those who would not today). Returns how
## many seats were filled.
func fill_empty(skip: Array = []) -> int:
	var n := 0
	for id in AUTO_ORDER:
		if crew_of(String(id)).is_empty() and _fill_open(String(id), skip):
			n += 1
	for id in AUTO_SECOND_PASS:
		while _fill_open(String(id), skip):
			n += 1
	return n


## One open seat of a station, given to the best of those with no job who are up (`_best_free`, not in `skip`).
func _fill_open(id: String, skip: Array) -> bool:
	if crew_of(id).size() >= seats_of(id):
		return false
	var best = _best_free(id, false, true, skip)
	return best != null and assign(best, id)


## The person with no job (here or away, as asked) who suits this station best, or null. `up_only` leaves out those who are down or
## in a breakdown; `skip` those whose ids are listed.
func _best_free(id: String, away := false, up_only := false, skip: Array = []):
	var best = null
	var best_score := -1.0e9
	for p in sim.people:
		if p.dead or p.turned or p.player or job_of(p) != "" or (p.away != null) != away or skip.has(String(p.id)):
			continue    # (the player is never given a seat: avatar.gd)
		if up_only and not _able(p):
			continue
		var s := _fit(p, id)
		if s > best_score:
			best_score = s
			best = p
	return best


## A seat has been left empty by somebody who became the player (avatar.gd: the player is never given a seat, so the radio desk, the
## infirmary or the lookout post they held would stay empty, and the storyteller would have no speaker): somebody at the base
## fills it. Whoever has no job takes it (the best fit, as Auto-assign picks them); with none, a seat is taken from the crew of a
## station whose work can wait (`GIVE_UP_ORDER`: a station that has two at the base before one that would be left empty, then the
## order of the list), the best fit of them. The radio desk and the infirmary are not robbed to fill each other. True when
## somebody sits in the seat now; false (nothing is changed) when there is no seat to fill or nobody to fill it.
func refill(id: String) -> bool:
	if not _station_by_id.has(id) or seats_left(id) <= 0:
		return false
	var free = _best_free(id, false, true)
	if free != null:
		return assign(free, id)
	var best = null
	var best_rank := 1.0e9
	var best_fit := -1.0e9
	for p in sim.people:
		if not _able(p):
			continue
		var from := job_of(p)
		var order := GIVE_UP_ORDER.find(from)
		if from == id or order < 0:
			continue
		var rank := float(order) + (0.0 if _at_base(from) >= 2 else 100.0)
		var fit := _fit(p, id)
		if rank < best_rank or (is_equal_approx(rank, best_rank) and fit > best_fit):
			best_rank = rank
			best_fit = fit
			best = p
	return best != null and assign(best, id)


## How many of a station's crew are here (not away on a trip).
func _at_base(id: String) -> int:
	var n := 0
	for p in crew_of(id):
		if p.away == null:
			n += 1
	return n


## How well this person suits this station (higher is better).
func _fit(p, id: String) -> float:
	var st := station(id)
	var skill := String(st.get("skill", ""))
	var score := 0.0
	if skill != "":
		score = float(p.skills.get(skill, 0))
	else:
		# the garden suits whoever is the least needed elsewhere
		score = 10.0 - maxf(maxf(float(p.skills.get("Shooting", 0)), float(p.skills.get("Building", 0))), maxf(float(p.skills.get("Medicine", 0)), float(p.skills.get("Leading", 0))))
	var trait_id := String(AUTO_TRAITS.get(id, ""))
	if trait_id != "":
		for t in sim.traits.of(p):
			if String(t.id) == trait_id:
				score += 0.5
	if id == "watch" and String(p.def.get("role", "")) == "Lookout":
		score += 3.0
	if sim.specialists.active():    # (round 20: the title holder has first call on their seat: the medic in the infirmary)
		score += sim.specialists.fit_bonus(p, id)
	if sim.relations.active():    # (round 20: a friend at that station is a reason to sit there, a rival a reason not to)
		score += sim.relations.fit_adjust(p, id)
	return score


## `_fit`, public (round 25: the staffing plan of priorities.gd picks the best of the free hands for a station).
func fit_of(p, id: String) -> float:
	return _fit(p, id)


# ------------------------------------------------------------------ update --

func update(_dt: float) -> void:
	if sim.phase != "day":
		return
	var h: float = sim.hour
	var town: bool = sim.is_one_house()    # (One House: no noon call and no forecast before the attacks begin: nothing to be told about an empty desk or tower)
	if not town and h >= RADIO_ALERT_HOUR and h < 12.0 and int(_alert_day.radio) != sim.day and operator("radio") == null:
		_alert_day.radio = sim.day
		# (round 16: the first survivors' calls come with the desk empty; the day's news and a stranger's call do not)
		var told := "The next survivor's call will still come, but no news unless someone sits there" if sim.recruits.call_due() and sim.recruits.call_guaranteed() else "There will be no call at noon unless someone sits there"
		sim.alert("job-radio", "info", "Nobody is at the radio desk", told, Vector2(station("radio").pos), ALERT_TTL)
	# half an hour before the forecast (16:30 in Autumn, when it comes at 17:00)
	var forecast_at: float = sim.seasons.dusk_hour() - 2.0    # (tactics.forecast_hour)
	if (not town or _forecast_on()) and h >= forecast_at - 0.5 and h < forecast_at and int(_alert_day.watch) != sim.day and operator("watch") == null:
		_alert_day.watch = sim.day
		sim.alert("job-watch", "info", "Nobody is on watch", "There will be no forecast tonight unless someone is at the lookout post", Vector2(station("watch").pos), ALERT_TTL)


# ------------------------------------------------------------------ orders --

## The orders this module owns: M and B put the selected person on the workbench or the wall
## crew, or take them off it.
func gizmo(id: String, sel) -> bool:
	# `craft` and `auto` are the old ids of the same two orders (the keys M and B)
	var key: String = String({"craft": "job_bench", "auto": "job_builders"}.get(id, id))
	if sel.kind != "person" or not (key == "job_bench" or key == "job_builders"):
		return false
	var station_id := "bench" if key == "job_bench" else "builders"
	var p = sel.ref
	if job_of(p) == station_id:
		unassign(p)
		return true
	return assign(p, station_id)


# -------------------------------------------------------------------- save --

func save() -> Dictionary:
	return {"assignments": assignments.duplicate(), "post_ids": post_ids.duplicate(), "settings": settings.duplicate(true), "alert_day": _alert_day.duplicate()}


func load_state(d: Dictionary) -> void:
	_defaults()
	var a = d.get("assignments", null)
	if not a is Dictionary:
		return
	for k in a:
		if sim.people.any(func(p): return String(p.id) == String(k)):
			var id := String(a[k])
			assignments[String(k)] = id if _station_by_id.has(id) else ""
	var pi = d.get("post_ids", {})
	if pi is Dictionary:
		for k in pi:
			if _post_by_id.has(String(pi[k])):
				post_ids[String(k)] = String(pi[k])
	var st = d.get("settings", {})
	if st is Dictionary:
		for sid in st:
			if st[sid] is Dictionary:
				for key in st[sid]:
					set_setting(String(sid), String(key), st[sid][key])
	var ad = d.get("alert_day", {})
	if ad is Dictionary:
		_alert_day = {"radio": int(ad.get("radio", 0)), "watch": int(ad.get("watch", 0))}
