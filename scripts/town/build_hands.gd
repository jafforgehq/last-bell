## HANDS AT THE FENCE (One House, EARLY): the avatar builds an ordered section of the base herself. A sim part of the town (scripts/town/town_sim.gd PARTS: `sim.build_hands`); the numbers are the data's, `build_hands`
## of assets/data/one_house.json (`per_min`: builder-hours of work her hands do in a minute, `reach`: how near a section she stands, tiles from its edge).
##
## WHY. The first survivor is a long way off, and a base of one has nobody to build: the first fence would wait for a stranger. Now the Build page's order has a pair of hands from the first minute: hers. A section that has been
## ordered (a site of the Build module: a Build plot of a slot of the perimeter that has one) is a thing to use: E at it, "Build the front fence" (one press begins it, a second stops it, and walking off ends it), is a timed session as a search or a strip is (scripts/town/uses.gd: the ring,
## the sounds, the same reasons to end undone: she walks, fires, is hurt, goes out of reach). While it runs the site's builder-hours go up at `per_min` a minute (about ten: the front fence, 14 or so builder-hours, is a minute and a
## half of standing at it after E), alongside any builders on the job (their work is Build's own, `Build.update`). The session's length is told to the ring every step from what is left, so the ring is the site's, whoever else works it.
## The session ends done when the site is finished (the Build module makes the section as it always does: the alert "The front fence is up" is the perimeter's, when the last section of a project is). When a section is done and
## another waits within reach, her hands go on at that one without a second press.
##
## It is a provider of `sim.uses` (kind "build", id the slot's), found by `uses.register`. Nothing here is the school's or the no-player sim's: the part exists in the town only, and nothing runs until a site is ordered and E is pressed.
extends RefCounted

const KIND := "build"
const EPS := 1.0e-6
## How often the hammer rings (an event for the sound: `Build.HAMMER_EVERY`'s).
const HAMMER_EVERY := 0.6

var sim
var enabled := true
## Builder-hours her hands have made, and seconds she has been at it (for the lab and the reports; saved with nothing).
var stats := {"hours": 0.0, "seconds": 0.0}

var _provider
var _slot := ""
var _hammer := 0.0


## What the avatar's E sees of this part (`uses.register`).
class Provider:
	extends RefCounted
	var owner

	func candidates(p) -> Array:
		return owner.avatar_candidates(p)

	func use(c: Dictionary) -> Dictionary:
		return owner.avatar_use(c)


func setup(s) -> void:
	sim = s
	_register()


func start() -> void:
	_slot = ""
	_hammer = 0.0
	stats = {"hours": 0.0, "seconds": 0.0}
	_register()


func _register() -> void:
	var u = sim.get("uses") if sim != null else null
	if u == null or not u.has_method("register"):
		return
	if _provider == null:
		_provider = Provider.new()
		_provider.owner = self
	u.register(_provider)


func _num(path: String, fallback: float) -> float:
	var sc = sim.get("scenario") if sim != null else null
	if sc != null and sc.has_method("_cfg"):
		var v = sc._cfg("build_hands." + path, fallback)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return float(v)
	return fallback


func _lead():
	if sim == null or String(sim.player_id) == "":
		return null
	return sim.avatar.player()


## Builder-hours her hands make in a second of the rules' time.
func hours_per_second() -> float:
	return maxf(_num("per_min", 10.0), 0.0) / 60.0


## The distance from a point to the nearest point of a rectangle of tiles (0 inside it).
static func rect_dist(at: Vector2, rect: Rect2i) -> float:
	var dx := maxf(maxf(float(rect.position.x) - at.x, at.x - float(rect.end.x)), 0.0)
	var dy := maxf(maxf(float(rect.position.y) - at.y, at.y - float(rect.end.y)), 0.0)
	return sqrt(dx * dx + dy * dy)


## The sections that are waiting for hands, as the perimeter's slots with the Build module's site on their plot: [{"slot", "plot", "rect", "noun", "left" (builder-hours still to do)}].
func sites() -> Array:
	var out: Array = []
	var per = sim.get("perimeter") if sim != null else null
	var build = sim.get("build") if sim != null else null
	if per == null or build == null or not per.has_method("slots"):
		return out
	for s in per.slots():
		var pl: Dictionary = build.plot(String(s.plot))
		if pl.is_empty() or pl.site.is_empty():
			continue
		var pid := String(s.get("project", ""))
		var name := String(per.project_noun(pid)) if pid != "" and per.has_method("project_noun") else ""
		out.append({"slot": String(s.id), "plot": String(s.plot), "rect": Rect2i(s.rect), "noun": name if name != "" else "the " + String(s.name).to_lower(),
			"left": maxf(0.0, float(pl.site.work) - float(pl.site.progress))})
	return out


## The waiting section nearest `here` within `reach` tiles of its edge, {} when there is none; `skip` is a slot to leave out.
func _nearest_site(here: Vector2, reach: float, skip: String = "") -> Dictionary:
	var best := {}
	var best_d := INF
	for e in sites():
		if String(e.slot) == skip:
			continue
		var d := rect_dist(here, e.rect)
		if d <= reach and d < best_d:
			best_d = d
			best = e
			best["dist"] = d
	return best


## E's candidate of this part: the section within reach that waits for hands ("Build the front fence", "Stop building" while she is at it).
func avatar_candidates(p) -> Array:
	var out: Array = []
	if not enabled or p == null:
		return out
	var here := Vector2(p.x, p.y)
	var u = sim.get("uses")
	var best := {}
	var reach := _num("reach", 2.2)
	if u != null and _slot != "" and u.in_session(KIND, _slot):
		for e in sites():
			if String(e.slot) == _slot:
				best = e
				best["dist"] = rect_dist(here, e.rect)
	else:
		best = _nearest_site(here, reach)
	if best.is_empty():
		return out
	var stop: bool = u != null and u.in_session(KIND, String(best.slot))
	var rect: Rect2i = best.rect
	# (the prompt stands at the point of the section nearest her: a section is up to twelve tiles long)
	var at := Vector2(clampf(here.x, float(rect.position.x), float(rect.end.x)), clampf(here.y, float(rect.position.y), float(rect.end.y)))
	out.append({"kind": KIND, "id": String(best.slot), "label": "Stop building" if stop else "Build %s" % String(best.noun), "pos": at, "dist": float(best.dist), "ok": true, "why": "", "session": true})
	return out


## E at it: the session begun (E again stops it); {} for a kind that is not this part's.
func avatar_use(c: Dictionary) -> Dictionary:
	if String(c.get("kind", "")) != KIND:
		return {}
	var id := String(c.get("id", ""))
	var u = sim.get("uses")
	var p = _lead()
	if u == null or p == null:
		return {"ok": false, "line": "", "why": "You are not here", "session": true}
	if u.in_session(KIND, id):
		u.cancel("stopped")
		_slot = ""
		return {"ok": true, "line": "Stopped.", "why": "", "session": true, "stopped": true}
	var site := {}
	for e in sites():
		if String(e.slot) == id:
			site = e
	if site.is_empty():
		return {"ok": false, "line": "", "why": "There is nothing to build there", "session": true}
	var here := Vector2(p.x, p.y)
	if rect_dist(here, site.rect) > _num("reach", 2.2) + 0.3:
		return {"ok": false, "line": "", "why": "Too far from it", "session": true}
	var secs := _seconds_left(float(site.left))
	var r: Dictionary = u.begin_session(KIND, id, "Building", secs, here, 0.7, Callable(self, "_ended"))
	if not bool(r.get("ok", false)):
		return {"ok": false, "line": "", "why": String(r.get("why", "")), "session": true}
	_slot = id
	_hammer = 0.0
	return {"ok": true, "line": "Building %s" % String(site.noun), "why": "", "session": true, "seconds": secs}


## The seconds her hands need for `hours` of work.
func _seconds_left(hours: float) -> float:
	var rate := hours_per_second()
	return hours / rate if rate > EPS else 600.0


## The session's own end is no event of the work: the site finishing is (every step looks at it).
func _ended() -> void:
	pass


# ------------------------------------------------------------------------------ the step --

## Every rules step while her hands are at a section: the builder-hours it gets, the hammer, the ring told what is left; a section that is done ends the session, and her hands go on at the next one in reach.
func update(dt: float) -> void:
	if _slot == "" or not enabled:
		return
	var u = sim.get("uses")
	var p = _lead()
	if u == null or p == null or not u.in_session(KIND, _slot):
		_slot = ""    # (the session ended undone: she walked, fired, was hurt, or pressed E again)
		return
	var site := {}
	for e in sites():
		if String(e.slot) == _slot:
			site = e
	if site.is_empty():
		# (finished by somebody else's work, or taken back)
		_finished(u, p)
		return
	var hours := hours_per_second() * dt
	stats.hours = float(stats.hours) + hours
	stats.seconds = float(stats.seconds) + dt
	_hammer -= dt
	if _hammer <= 0.0:
		_hammer = HAMMER_EVERY
		sim.events.append({"type": "hammer", "x": p.x, "y": p.y})
	var done: bool = not sim.build.hand_work(String(site.plot), hours)
	if done:
		_finished(u, p)
		return
	# (the ring: what is left of the site, in her seconds: whoever else works it, the ring is the site's)
	var left := 0.0
	for e in sites():
		if String(e.slot) == _slot:
			left = float(e.left)
	if left <= 0.0:
		_finished(u, p)
		return
	if u.has_method("retime"):
		u.retime(_seconds_left(left))


## The section she was at is up: the session is over, and when another waits within reach her hands go on at it.
func _finished(u, p) -> void:
	var was := _slot
	_slot = ""
	u.cancel("finished")
	if String(p.activity) == "Building":
		p.activity = ""
	var here := Vector2(p.x, p.y)
	var next := _nearest_site(here, _num("chain_reach", 4.0), was)
	if next.is_empty():
		return
	var r: Dictionary = u.begin_session(KIND, String(next.slot), "Building", _seconds_left(float(next.left)), here, 0.7, Callable(self, "_ended"))
	if bool(r.get("ok", false)):
		_slot = String(next.slot)
		_hammer = 0.0


## The section her hands are at now ("" when none): for the views and the lab.
func slot_in_hand() -> String:
	var u = sim.get("uses") if sim != null else null
	return _slot if u != null and _slot != "" and u.in_session(KIND, _slot) else ""


# -------------------------------------------------------------------------------- save --

## Nothing is saved: a session is never resumed (the bench's rule).
func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	start()
