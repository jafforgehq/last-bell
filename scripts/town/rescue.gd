## Rescue and the community (One House, WP4): the people found alive in the houses of the town, the talk with them, and how they come home.
##
## The twelve candidates are the generator's `town.rescue` spots (near to far, `sim.houses.town`); each gets a record and a roster-shaped def (made once from the run's
## seed by `recruits.make_def`, then given its name, role and lines from assets/data/rescue.json: the same run meets the same people). A record is
##   {"id": "r0".., "n", "house", "room", "pos": Vector2, "ring", "def", "state", "trust0", "asked", "gifted", "arrived"}
## and its state goes `hiding` (the room has not been opened) -> `wary` (it has: the survivor is drawn, weapon lowered, and E talks) -> `spoken` (the card has been
## shown) -> `joined` (they said yes). `lost` exists for later (`lost_after_days` in the data, 0 = never). Nobody is lost before the fourth in the demo.
##
## The card (`talk`, `choose`): while a dead one is still in the survivor's room they say so and offer nothing ("Get them out first"). Otherwise: Come with me
## (needs the claimed base and a free bed: `recruits.housing_free()`), Stay here, I will come back, and Take this (a food or a round: a little trust, once).
## "Come" sends them ahead on their own: they appear at the base's front spot after `distance x 0.4` game minutes (at least 3), and only then are they a Person of
## the crew (`sim.add_person`, saved through `recruits.arrived`, a pack from the data, a seat by `jobs.fill_empty`, a first radio line, the News, the events
## `arrived` and `rescue_joined`, `scenario.on_survivor_joined(p, count)` and, at the fourth, `fourth`). A survivor who has not joined is not a Person of the sim:
## `bystander(id)` makes one to draw (the view part scripts/render/bystander_view.gd), without a draw from the sim's dice.
##
## Events: {"type": "rescue_seen"|"rescue_talk"|"rescue_waits", "id"}, {"type": "rescue_joined", "id", "who", "count"}, {"type": "fourth"}, {"type": "rescue_lost", "id"}.
## Every other module of the town is reached by `_mod(name)` (null when it has not landed), so this one runs with any of them missing.
extends RefCounted

const Recruits := preload("res://scripts/sim/recruits.gd")
const Sim := preload("res://scripts/sim/sim.gd")

const DATA_PATH := "res://assets/data/rescue.json"
const HIDING := "hiding"
const WARY := "wary"
const SPOKEN := "spoken"
const JOINED := "joined"
const LOST := "lost"
## How often the states are looked at (seconds of the rules' time).
const STEP := 0.25
## A survivor looks at the avatar when it is this near (tiles).
const FACE_R := 9.0
## Without a clearing module the avatar must be this near for a survivor's room to count as opened.
const NEAR_REVEAL := 6.0

var sim
var enabled := true
## Modules by name that stand in for the sim's own (a test's fakes; the real game leaves it empty).
var links := {}
var data := {}
var _recs: Array = []
var _by_id := {}
var _arriving: Array = []
var _bystanders := {}
var _t := 0.0


func setup(s) -> void:
	sim = s
	data = _read(DATA_PATH)


func start() -> void:
	_recs.clear()
	_by_id.clear()
	_arriving.clear()
	_bystanders.clear()
	_t = 0.0
	_build()


static func _read(path: String) -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return raw if raw is Dictionary else {}


## A module of the town (or of the sim) by name, null when it is not there.
func _mod(name: String):
	if links.has(name):
		return links[name]
	return sim.get(name) if sim != null else null


func _num(key: String, fallback: float) -> float:
	return float(data.get(key, fallback))


func _say(group: String, key: String) -> String:
	var g = data.get(group, {})
	return String(g.get(key, "")) if g is Dictionary else ""


# ------------------------------------------------------------------ the records --

func _town() -> Dictionary:
	var h = _mod("houses")
	var t = h.get("town") if h != null else null
	return t if t is Dictionary else {}


func _build() -> void:
	var spots = _town().get("rescue", [])
	if not spots is Array or spots.is_empty():
		return
	var stories: Array = data.get("survivors", [])
	for i in spots.size():
		var s: Dictionary = spots[i]
		var told: Dictionary = stories[i % stories.size()] if not stories.is_empty() else {}
		var def := _make_def(i, told)
		if def.is_empty():
			continue
		_add({"id": "r%d" % i, "n": i, "house": int(s.get("house", -1)), "room": int(s.get("room", -1)), "pos": Vector2(s.get("pos", Vector2.ZERO)),
			"ring": int(s.get("ring", 1)), "def": def, "state": HIDING, "trust0": _num("join_trust", 5.0), "asked": false, "gifted": false, "arrived": false})


func _add(rec: Dictionary) -> void:
	_recs.append(rec)
	_by_id[String(rec.id)] = rec


## The roster-shaped def of survivor `i`: the recruits' generator (the look, the portrait, the traits, the age), under a dice of its own so that it neither
## depends on nor moves the recruits' own stream, then the authored name, role, station and the skills and weapon of that role.
func _make_def(i: int, told: Dictionary) -> Dictionary:
	var recruits = _mod("recruits")
	if recruits == null or not recruits.has_method("make_def"):
		return {}
	var dice = recruits.get("_rng")
	var kept_seed := 0
	var kept_state := 0
	var swapped: bool = dice is RandomNumberGenerator
	if swapped:
		kept_seed = dice.seed
		kept_state = dice.state
		dice.seed = _def_seed(i)
	var def: Dictionary = recruits.make_def(i)
	if swapped:
		dice.seed = kept_seed
		dice.state = kept_state
	var full := String(told.get("name", def.get("name", "Survivor")))
	def["name"] = full
	def["id"] = "r%d_%s" % [i + 1, full.split(" ")[0].to_lower()]
	def["station"] = String(told.get("station", ""))
	def["bitten"] = false
	def["line"] = String(told.get("line", ""))
	def["line_in"] = ""
	var role := String(told.get("role", ""))
	var entry := _role_entry(role)
	if not entry.is_empty():
		def["role"] = role
		if sim != null and sim.weapons.has(String(entry.get("weapon", ""))):
			def["weapon"] = String(entry.weapon)
		var dice2 := RandomNumberGenerator.new()
		dice2.seed = _def_seed(i) ^ 0x5bd1e995
		var skills := {}
		for k in Recruits.SKILLS:
			var span = entry.get("skills", {}).get(k, [1, 4])
			var lo := int(span[0])
			var hi := maxi(lo, int(span[1]))
			skills[k] = lo + dice2.randi() % (hi - lo + 1)
		def["skills"] = skills
	return def


func _def_seed(i: int) -> int:
	return (int(sim.run_seed) * 2654435761 + 40503 * (i + 1) + 17) & 0x7fffffff


func _role_entry(role: String) -> Dictionary:
	var file := _read(Recruits.DATA_PATH)
	for r in file.get("roles", []):
		if String(r.get("role", "")) == role:
			return r
	return {}


func _told(rec: Dictionary) -> Dictionary:
	var stories: Array = data.get("survivors", [])
	return stories[int(rec.n) % stories.size()] if not stories.is_empty() else {}


## Every record (a copy of the list; the records are the live ones).
func list() -> Array:
	return _recs.duplicate()


func get_record(id: String) -> Dictionary:
	return _by_id.get(id, {})


## How many have said yes (on their way or arrived).
func joined_count() -> int:
	var n := 0
	for r in _recs:
		if r.state == JOINED:
			n += 1
	return n


## How many are in the crew now.
func arrived_count() -> int:
	var n := 0
	for r in _recs:
		if bool(r.arrived):
			n += 1
	return n


## The ids of those who said yes and have not got here yet.
func on_the_way() -> Array:
	var out: Array = []
	for e in _arriving:
		out.append(String(e.id))
	return out


# ----------------------------------------------------------------------- update --

func update(dt: float) -> void:
	if not enabled or sim == null:
		return
	_t += dt
	if _t < STEP:
		return
	_t = 0.0
	if _recs.is_empty():
		_build()    # (the town was not there at start)
	_look()
	_face()
	_arrivals()
	_losses()


## A survivor whose room has been opened is wary (and seen).
func _look() -> void:
	for rec in _recs:
		if rec.state == HIDING and _revealed(rec):
			rec.state = WARY
			sim.events.append({"type": "rescue_seen", "id": String(rec.id)})


func _revealed(rec: Dictionary) -> bool:
	var c = _mod("clearing")
	if c != null and c.has_method("is_revealed"):
		return bool(c.is_revealed(int(rec.room)))
	var me = _avatar()
	return me != null and Vector2(me.x, me.y).distance_to(rec.pos) <= NEAR_REVEAL


func _avatar():
	if sim == null or String(sim.player_id) == "" or sim.get("avatar") == null:
		return null
	return sim.avatar.player()


## The wary ones turn to the avatar.
func _face() -> void:
	var me = _avatar()
	if me == null:
		return
	var at := Vector2(me.x, me.y)
	for id in _bystanders:
		var rec: Dictionary = _by_id.get(id, {})
		var p = _bystanders[id]
		if rec.is_empty() or at.distance_to(rec.pos) > FACE_R:
			continue
		p.facing = Sim.facing_of(at.x - rec.pos.x, at.y - rec.pos.y, String(p.facing))


func _arrivals() -> void:
	for e in _arriving.duplicate():
		if float(sim.clock_min) >= float(e.due):
			_arriving.erase(e)
			_arrive(String(e.id))


## `lost_after_days` (0: never): a survivor whose room is still full of dead after that many days is gone, with a News line.
func _losses() -> void:
	var days := int(_num("lost_after_days", 0.0))
	if days <= 0 or int(sim.day) < days + 1:
		return
	for rec in _recs:
		if rec.state in [JOINED, LOST] or _dead_in(int(rec.room)) == 0:
			continue
		rec.state = LOST
		_drop(String(rec.id))
		sim.events.append({"type": "rescue_lost", "id": String(rec.id)})
		var radio = _mod("radio")
		if radio != null:
			radio.log_news("recruit", "Nobody answers from %s" % String(rec.def.name), "The dead got there first")


# ------------------------------------------------------------------- the survivor --

## The survivor within `r` tiles of `p` (a person or a point) that can be talked to, the nearest, else "".
func near(p, r: float = 1.9) -> String:
	var at: Vector2 = p if p is Vector2 else Vector2(p.x, p.y)
	var best := ""
	var best_d := INF
	for rec in _recs:
		if rec.state != WARY and rec.state != SPOKEN:
			continue
		var d := at.distance_to(rec.pos)
		if d <= r and d < best_d:
			best_d = d
			best = String(rec.id)
	return best


## The Person to draw for a survivor who has not joined (their room is open), or null. Held here, not in `sim.people`: the dead do not see them and no job
## gives them a post. Made with the sim's dice put back as they were, so that drawing a frame never changes a game.
func bystander(id: String):
	var rec := get_record(id)
	if rec.is_empty() or (rec.state != WARY and rec.state != SPOKEN):
		return null
	if not _bystanders.has(id):
		var kept = sim.rng.state
		var p = sim.make_person(rec.def)
		sim.rng.state = kept
		p.x = rec.pos.x
		p.y = rec.pos.y
		p.facing = "S"
		p.holstered = true
		p.moving = false
		p.activity = "Waiting"
		_bystanders[id] = p
	return _bystanders[id]


func _drop(id: String) -> void:
	_bystanders.erase(id)


## How many dead are in a room now (the dormant field's count, or the houses'; 0 when neither is there).
func _dead_in(room: int) -> int:
	for name in ["field", "houses"]:
		var m = _mod(name)
		if m != null and m.has_method("dead_in_room"):
			var v = m.dead_in_room(room)
			return int(v.get("left", v.get("total", 0))) if v is Dictionary else int(v)
	return 0


# ---------------------------------------------------------------------- the card --

## What the card shows for a survivor now, with no side effect: {"id", "name", "role", "line", "portrait", "hiding", "state", "blocked", "choices": [{"id", "text", "ok", "why"}]}
## ({} for one nobody can talk to: hiding or lost).
func card(id: String) -> Dictionary:
	var rec := get_record(id)
	if rec.is_empty() or rec.state == HIDING or rec.state == LOST:
		return {}
	var told := _told(rec)
	var m := {"id": id, "name": String(rec.def.name), "role": String(rec.def.get("role", "")), "portrait": String(rec.def.get("portrait", "")),
		"hiding": String(told.get("hiding", "")), "state": String(rec.state), "blocked": false, "line": "", "choices": []}
	if rec.state == JOINED:
		m.line = _say("lines", "on_way")
		return m
	if _dead_in(int(rec.room)) > 0:
		m.blocked = true
		m.line = String(told.get("blocked", _say("lines", "blocked")))
		return m
	m.line = _say("lines", "back") if bool(rec.asked) else String(told.get("line", ""))
	var labels: Dictionary = data.get("choices", {})
	var come := _why_not_come()
	m.choices.append({"id": "come", "text": String(labels.get("come", "Come with me")), "ok": come == "", "why": come})
	m.choices.append({"id": "stay", "text": String(labels.get("stay", "Stay here, I will come back")), "ok": true, "why": ""})
	var gift := _why_not_gift(rec)
	m.choices.append({"id": "gift", "text": String(labels.get("gift", "Take this")), "ok": gift == "", "why": gift})
	return m


## E at a survivor: the card, and the word that it was shown (a wary survivor has spoken now, unless they only told you to get the dead out).
func talk(id: String) -> Dictionary:
	var m := card(id)
	if m.is_empty():
		return m
	var rec := get_record(id)
	if rec.state == WARY and not bool(m.blocked):
		rec.state = SPOKEN
		m["state"] = SPOKEN
	sim.events.append({"type": "rescue_talk", "id": id})
	return m


## Why "Come with me" is not on offer ("" when it is): the base is claimed and has a bed to give them.
func _why_not_come() -> String:
	var base = _mod("base")
	if base == null or not bool(base.get("claimed")):
		return _say("why", "no_base")
	var recruits = _mod("recruits")
	if recruits != null and recruits.has_method("housing_free") and int(recruits.housing_free()) - _arriving.size() < 1:
		return _say("why", "no_bed")
	return ""


func _why_not_gift(rec: Dictionary) -> String:
	if bool(rec.gifted):
		return _say("why", "gifted")
	return "" if _gift_item() != "" else _say("why", "no_stock")


func _gift_item() -> String:
	var amount := _num("gift_amount", 1.0)
	for k in data.get("gift_items", ["food", "ammo"]):
		if float(sim.stock.get(String(k), 0.0)) >= amount:
			return String(k)
	return ""


## The player's answer: {"ok", "line" (what they say), "joined" (they are on their way), "why" (when it was refused)}.
func choose(id: String, choice: String) -> Dictionary:
	var out := {"ok": false, "line": "", "joined": false, "why": ""}
	var m := card(id)
	if m.is_empty() or m.state == JOINED:
		out.why = "Nobody there to answer"
		return out
	if bool(m.blocked):
		out.why = _say("why", "blocked")
		out.line = String(m.line)
		return out
	var picked := {}
	for c in m.choices:
		if String(c.id) == choice:
			picked = c
	if picked.is_empty():
		out.why = "Not something to say to them"
		return out
	if not bool(picked.ok):
		out.why = String(picked.why)
		return out
	var rec := get_record(id)
	var told := _told(rec)
	out.ok = true
	match choice:
		"come":
			_send_ahead(rec)
			out.joined = true
			out.line = String(told.get("come", _say("lines", "come")))
		"stay":
			rec.state = SPOKEN
			rec.asked = true
			sim.events.append({"type": "rescue_waits", "id": id})
			out.line = String(told.get("stay", ""))
		"gift":
			var item := _gift_item()
			sim.stock[item] = float(sim.stock[item]) - _num("gift_amount", 1.0)
			rec.gifted = true
			rec.trust0 = float(rec.trust0) + _num("gift_trust", 6.0)
			out.line = String(told.get("gift", ""))
	return out


## They said yes: they walk ahead (no escort), and are at the base's front spot after `arrive_per_tile` game minutes a tile, at least `arrive_min`.
func _send_ahead(rec: Dictionary) -> void:
	rec.state = JOINED
	rec.asked = true
	_drop(String(rec.id))
	var spot := _front_spot(0)
	var delay := maxf(_num("arrive_min", 3.0), rec.pos.distance_to(spot) * _num("arrive_per_tile", 0.4))
	_arriving.append({"id": String(rec.id), "due": float(sim.clock_min) + delay})


## Where a newcomer appears: just inside the base's front door, the ones before them a little aside.
func _front_spot(index: int) -> Vector2:
	var base = _mod("base")
	var at := Vector2.ZERO
	if base != null and base.has_method("claim_spot"):
		at = base.claim_spot()
	if at == Vector2.ZERO and base != null and base.has_method("center"):
		at = base.center()
	return at + Vector2([0.0, 0.6, -0.6][index % 3], 0.0)


func _arrive(id: String) -> void:
	var rec := get_record(id)
	if rec.is_empty() or bool(rec.arrived):
		return
	var def: Dictionary = rec.def
	var spot := _front_spot(arrived_count())
	def["job"] = {"x": spot.x, "y": spot.y, "what": "Just arrived"}
	def["post"] = {"x": spot.x, "y": spot.y, "what": "At the fence"}
	var p = sim.add_person(def)
	p.x = spot.x
	p.y = spot.y
	p.goal_key = ""
	rec.arrived = true
	var recruits = _mod("recruits")
	if recruits != null:
		recruits.arrived.append(def)    # (a save rebuilds them from here: recruits.prepare_load)
	var radio = _mod("radio")
	if radio != null and float(rec.trust0) != 0.0:
		radio.add_trust(p, float(rec.trust0), "You came for them")
	var brought := _pack(rec)
	var jobs = _mod("jobs")
	if jobs != null:
		jobs.fill_empty()
	var count := arrived_count()
	sim.events.append({"type": "arrived", "who": String(p.id)})    # (the crew bar and the small bell: main.gd `_on_arrival`)
	sim.events.append({"type": "banner", "text": "%s has reached the house" % p.first, "sub": String(def.get("role", ""))})
	sim.alert("arrived-%s" % p.id, "info", "%s has joined the crew" % p.name, String(def.get("role", "")), Vector2(p.x, p.y), 14.0)
	var morale = _mod("morale")
	if morale != null:
		morale.shock(null, Recruits.ARRIVAL_MORALE, "A new face")
	var contact: Array = data.get("contact", [])
	if radio != null:
		if not contact.is_empty():
			sim.events.append({"type": "radio_line", "who": String(p.id), "line": String(contact[int(rec.n) % contact.size()])})
		radio.log_news("recruit", "%s is on the radio now" % p.name, brought, {"at": Vector2(p.x, p.y)})
	sim.events.append({"type": "rescue_joined", "id": id, "who": String(p.id), "count": count})
	var scenario = _mod("scenario")
	if scenario != null and scenario.has_method("on_survivor_joined"):
		scenario.on_survivor_joined(p, count)
	if count == int(_num("fourth_at", 4.0)):
		sim.events.append({"type": "fourth"})


## What they bring goes into the stock; returns it in words ("6 scrap, 1 food").
func _pack(rec: Dictionary) -> String:
	var parts: Array = []
	var pack: Dictionary = _told(rec).get("pack", {})
	for k in pack:
		var n := float(pack[k])
		if n <= 0.0:
			continue
		sim.stock[k] = float(sim.stock.get(k, 0.0)) + n
		parts.append("%d %s" % [int(n), String(k)])
	return "Brought " + ", ".join(parts) if not parts.is_empty() else ""


# ------------------------------------------------------------------------ E use --

## The E uses for `sim.uses`: Talk to the survivor within reach (a card with no choices while their room still has dead in it).
func candidates(p = null) -> Array:
	if not enabled:
		return []
	var me = p if p != null else _avatar()
	if me == null:
		return []
	var out: Array = []
	var at := Vector2(me.x, me.y)
	var r := _num("reach", 1.9)
	for rec in _recs:
		if rec.state != WARY and rec.state != SPOKEN:
			continue
		var d := at.distance_to(rec.pos)
		if d <= r:
			out.append({"kind": "rescue", "id": String(rec.id), "label": "Talk to %s" % String(rec.def.name).split(" ")[0], "pos": rec.pos, "dist": d, "ok": true, "why": ""})
	return out


func use(c: Dictionary) -> Dictionary:
	var m := talk(String(c.get("id", "")))
	if m.is_empty():
		return {"ok": false, "line": "", "why": "Nobody there"}
	return {"ok": true, "line": String(m.line), "why": "", "card": m}


# --------------------------------------------------------------------------- save --

func save() -> Dictionary:
	var recs: Array = []
	for r in _recs:
		recs.append({"id": r.id, "n": r.n, "house": r.house, "room": r.room, "pos": [r.pos.x, r.pos.y], "ring": r.ring, "def": r.def.duplicate(true),
			"state": r.state, "trust0": r.trust0, "asked": r.asked, "gifted": r.gifted, "arrived": r.arrived})
	return {"v": 1, "recs": recs, "arriving": _arriving.duplicate(true)}


func load_state(d: Dictionary) -> void:
	_recs.clear()
	_by_id.clear()
	_arriving.clear()
	_bystanders.clear()
	_t = 0.0
	var saved = d.get("recs", [])
	if not saved is Array or saved.is_empty():
		_build()
		return
	for r in saved:
		if not r is Dictionary or not r.get("def") is Dictionary or not r.get("pos") is Array or r.pos.size() < 2:
			continue
		var state := String(r.get("state", HIDING))
		_add({"id": String(r.get("id", "")), "n": int(r.get("n", 0)), "house": int(r.get("house", -1)), "room": int(r.get("room", -1)),
			"pos": Vector2(float(r.pos[0]), float(r.pos[1])), "ring": int(r.get("ring", 1)), "def": r.def.duplicate(true),
			"state": state if [HIDING, WARY, SPOKEN, JOINED, LOST].has(state) else HIDING, "trust0": float(r.get("trust0", 0.0)),
			"asked": bool(r.get("asked", false)), "gifted": bool(r.get("gifted", false)), "arrived": bool(r.get("arrived", false))})
	var way = d.get("arriving", [])
	if way is Array:
		for e in way:
			if e is Dictionary and _by_id.has(String(e.get("id", ""))):
				_arriving.append({"id": String(e.id), "due": float(e.get("due", 0.0))})
