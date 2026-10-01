## Jobs and stations. By day every person has a job: a station (the workbench, the wall crew,
## the vegetable beds, the infirmary, the radio desk, the lookout post) with a number of
## seats, a spot to stand at and an effect; by night everyone holds a named post on the wall.
## This module keeps who is where (assignments, seats, posts, the stations' settings), says
## who is working a station right now (`working`, which the effect modules ask), supplies the
## goals the rules follow (`goal_for` by day, `post_goal` by night) and fills the seats by skill
## (`auto_assign`). What a station does is the business of the module it belongs to: the
## workshop makes the ammo, tactics mends the walls and keeps watch, supplies grows the food,
## medical heals, the storyteller takes the noon call.
##
## Precedence of what a person does is `sim._goal_for`: an order, then a treatment or a trip,
## then (by night) the post, then (by day) the station's seat. Orders end when released and
## the person goes back to their job.
##
## Data: assets/data/stations.json and assets/data/posts.json; the six starting people's
## default job and post are `station` and `post_id` in their roster entries.
##
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
const SEAT_OFFSETS := [Vector2(0.0, 0.0), Vector2(1.1, 0.0), Vector2(-1.1, 0.0), Vector2(0.0, 1.1)]
## An empty radio desk is said from 11:30 (the noon call is at 12:00) and an empty lookout post from
## 16:30 (the forecast is at 17:00).
const RADIO_ALERT_HOUR := 11.5
const WATCH_ALERT_HOUR := 16.5
const ALERT_TTL := 20.0
## The order Auto-assign fills the stations in (one seat each first, then what is left over): the
## work first (the bench, the wall crew, the beds), then the desks, the radio last, so a crew that is
## short-handed works before it listens.
const AUTO_ORDER := ["bench", "builders", "garden", "watch", "infirmary", "radio"]
const AUTO_SECOND_PASS := ["builders", "garden", "bench", "infirmary"]
## Traits that make a person a better fit for a station.
const AUTO_TRAITS := {"bench": "tinkerer", "builders": "tinkerer", "infirmary": "triage", "watch": "sharp_eyed"}

var sim
## Person id -> station id ("" none), person id -> post id, and station id -> {setting: value}.
var assignments := {}
var post_ids := {}
var settings := {}
var _alert_day := {"radio": 0, "watch": 0}
var _stations: Array = []
var _station_by_id := {}
var _posts: Array = []
var _post_by_id := {}


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
		_cache[key] = {"stations": stations, "posts": posts}
	var c: Dictionary = _cache[key]
	_stations = c.stations
	_posts = c.posts
	_station_by_id.clear()
	for st in _stations:
		_station_by_id[String(st.id)] = st
	_post_by_id.clear()
	for po in _posts:
		_post_by_id[String(po.id)] = po


## The way someone at this spot on the wall faces.
static func _face_of(at: Vector2) -> String:
	if at.x < 22.0:
		return "N" if at.y < 19.0 else "W"
	if at.x > 62.0:
		return "N" if at.y < 19.0 else "E"
	return "N"


func start() -> void:
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

func stations() -> Array:
	return _stations


## A station's data, or {} when there is no such station.
func station(id: String) -> Dictionary:
	return _station_by_id.get(id, {})


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
	return int(_station_by_id[id].seats) - here


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
	if seats_left(id) <= 0:
		return "the %s is full" % String(_station_by_id[id].name)
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
	var seats := int(_station_by_id[id].seats)
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
	return Vector2(st.pos) + Vector2(SEAT_OFFSETS[mini(seat_index(p), SEAT_OFFSETS.size() - 1)])


func _able(p) -> bool:
	return not (p.dead or p.turned or p.downed) and p.away == null and not sim.morale.breakdown(p)


## By day: until the bell (or until the night proper).
func _day() -> bool:
	return not (sim.phase == "night" or sim.phase == "dawn" or (sim.phase == "dusk" and sim.bell_rung))


func _free(p) -> bool:
	if not _able(p) or p.drafted or p.order != null or p.repair != null:
		return false
	return sim.medical.goal_for(p) == null


## The people assigned to this station who are at their seats and free to work right now.
## The modules whose work a station is ask this.
func working(id: String) -> Array:
	var out: Array = []
	if not _day():
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


## The day goal (after any order, treatment or trip): stand at the seat; with no job, stand at ease.
func goal_for(p) -> Dictionary:
	var id := job_of(p)
	if id == "":
		return {"x": p.x, "y": p.y, "face": "", "what": "At ease"}
	var st := station(id)
	var at := seat_pos(p)
	return {"x": at.x, "y": at.y, "face": "N" if id == "radio" else "", "what": String(st.get("what", st.name))}


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
	var best = null
	var best_score := -1.0e9
	for p in sim.people:
		if p.dead or p.turned or job_of(p) != "" or (p.away != null) != away:
			continue
		var s := _fit(p, id)
		if s > best_score:
			best_score = s
			best = p
	# a seat that is really open (not one held by somebody away: Auto-assign does not take those)
	if best == null or crew_of(id).size() >= int(_station_by_id[id].seats):
		return false
	return assign(best, id)


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
	return score


# ------------------------------------------------------------------ update --

func update(_dt: float) -> void:
	if sim.phase != "day":
		return
	var h: float = sim.hour
	if h >= RADIO_ALERT_HOUR and h < 12.0 and int(_alert_day.radio) != sim.day and operator("radio") == null:
		_alert_day.radio = sim.day
		sim.alert("job-radio", "info", "Nobody is at the radio desk", "There will be no call at noon unless someone sits there", Vector2(station("radio").pos), ALERT_TTL)
	if h >= WATCH_ALERT_HOUR and h < 17.0 and int(_alert_day.watch) != sim.day and operator("watch") == null:
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
