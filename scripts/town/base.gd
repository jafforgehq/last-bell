## The base: a cleared house that was claimed (One House, WP3, plan 1.6 and 2.3). Before the claim it only knows where the claim is made; after it, the
## house's generated LAYOUT is installed and every question about "the base" (the compound, the yard, the spawns, the interior's props) is answered from it.
##
## THE CLAIM (the order is the contract, plan 2.3). `claim(h)`: refused unless the house is claimable now (`clearing.claimable`: every room looked into, none
## of the dead in it), the avatar is inside it within CLAIM_NEAR of the claim spot and nothing is claimed yet. Then the layout is made (BaseLayout.make of WP5, or
## `maker` when a test or another package sets one, or the interior-only fallback below), `build.install_layout`, `jobs.install_layout` (each only when the hook
## exists and the layout has something for it), `perimeter.activate(layout)`, `sim.spawns` = the layout's, `claimed`, the survivors of that house (`rescue.on_claimed`),
## `scenario.on_claimed(h)`, the events `claimed` and the banner (`scenario.claim_words(h)`: "This house is yours", by how good a base it is). It costs nothing. E at the front door of
## any CANDIDATE house (scripts/town/arrival.gd: the houses the player is offered on arriving; the start house in a town with none) begins it as a 2 s session (uses.gd); any house works in `claim`.
## A layout that fails `BaseLayout.validate` at the claim (the generator checks the candidates, so it should not) still stands: `problems` lists what is wrong and the objective says so.
## SAVED: {claimed, house} only. The layout is made again on a load (`prepare_load` before the rest is read, so that `perimeter.prepare_load` can read `layout`).
## Candidates: kind "claim", and kind "stash" (E at the stash reads the stores).
extends RefCounted

const Arrival := preload("res://scripts/town/arrival.gd")

const CLAIM_REACH := 2.2
const CLAIM_NEAR := 6.0
const CLAIM_S := 2.0
const STASH_REACH := 1.6
const RING := 3
const BASE_LAYOUT := "res://scripts/town/base_layout.gd"
const STOCK_ORDER := [["food", "food"], ["water", "water"], ["ammo", "rounds"], ["scrap", "scrap"], ["meds", "meds"]]

var sim
var enabled := true
var claimed := false
var house := -1
var layout: Dictionary = {}
## What `BaseLayout.validate` found wrong with the layout made at the claim (empty: nothing, which is what every candidate house of the generator gives).
var problems: Array = []
## Set to a Callable(town, house_id) -> Dictionary to use it in place of BaseLayout.make (tests; a package that has its own).
var maker := Callable()


func setup(s) -> void:
	sim = s


func start() -> void:
	claimed = false
	house = -1
	layout = {}
	problems = []
	_put_bench_away()


func _hs():
	return sim.get("houses")


## The generator leaves the school's "worktable" spot in the map data (`workshop`, at the start house): until a base has a bench of its own there is no bench to work (E would say
## "Work the bench" in a house that is nobody's yet). The data's `workshop` is emptied here and put at the base's own bench when the layout is installed.
func _put_bench_away() -> void:
	if sim != null and sim.d is Dictionary and sim.d.has("workshop"):
		sim.d["workshop"] = null


func _set_bench(at: Vector2) -> void:
	if sim != null and sim.d is Dictionary:
		sim.d["workshop"] = {"x": at.x, "y": at.y, "what": "At the worktable"}


func _lead():
	if String(sim.player_id) == "":
		return null
	return sim.avatar.player()


# ------------------------------------------------------------------------- the place --

func _rect_mid(h: int) -> Vector2:
	var hs = _hs()
	if hs == null or h < 0:
		return Vector2.ZERO
	var rect: Rect2i = hs.house(h).get("rect", Rect2i())
	return Vector2(rect.position) + Vector2(rect.size) * 0.5


## The house the base is, or would be: the claimed one, else the house the scenario says the player has in hand (the candidate she went into, the one found clear), else the start house.
func _subject() -> int:
	if not layout.is_empty():
		return house
	var sc = sim.scenario
	if sc != null and sc.has_method("work_house"):
		var w := int(sc.work_house())
		if w >= 0:
			return w
	var hs = _hs()
	return int(hs.start_house()) if hs != null else -1


func center() -> Vector2:
	if not layout.is_empty():
		return Vector2(layout.get("center", _rect_mid(house)))
	return _rect_mid(_subject())


func yard_middle() -> Vector2:
	if not layout.is_empty():
		return Vector2(layout.get("yard_middle", center()))
	return center()


## "At the base" and "outside" tests: the lot grown by RING tiles. Empty (it holds no point) before a claim.
func compound() -> Rect2:
	if layout.is_empty():
		return Rect2()
	return Rect2(layout.get("compound", Rect2()))


func yard_rect() -> Rect2:
	if layout.is_empty():
		return Rect2()
	var plot: Rect2i = layout.get("plot", Rect2i())
	return Rect2(plot)


func spawns() -> Array:
	if not layout.is_empty() and not Array(layout.get("spawns", [])).is_empty():
		var out: Array = []
		for s in layout.spawns:
			out.append(Vector2(s))
		return out
	return sim.spawns


## Where E claims: just inside the front door (the layout's once claimed, else worked out from the house).
func claim_spot() -> Vector2:
	if not layout.is_empty() and layout.has("claim_spot"):
		return Vector2(layout.claim_spot)
	return spot_of(_subject())


## Just inside the front (exterior) door of a house: the tile beyond the doorway. Vector2.ZERO when the house has none.
func spot_of(h: int) -> Vector2:
	var hs = _hs()
	if hs == null or h < 0:
		return Vector2.ZERO
	var front := String(hs.house(h).get("front", ""))
	var pick: Dictionary = {}
	for d in hs.doors_of(h):
		if not bool(d.get("exterior", false)):
			continue
		if pick.is_empty():
			pick = d
		if String(d.get("side", "")) == front:
			pick = d
			break
	if pick.is_empty():
		return Vector2.ZERO
	var t: Vector2i = pick["in"]
	return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)


## The interior stations to draw: [{"id": "bed"|"stash"|"radio"|"bench", "kind", "pos": Vector2, "room", "face"}].
func props() -> Array:
	return Array(layout.get("interior", [])).duplicate(true)


func prop(id: String) -> Dictionary:
	for e in layout.get("interior", []):
		if String(e.get("id", "")) == id:
			return e
	return {}


## Is this person (or point) inside the base's compound.
func at_base(p) -> bool:
	if layout.is_empty():
		return false
	var at: Vector2 = p if typeof(p) == TYPE_VECTOR2 else Vector2(p.x, p.y)
	return compound().has_point(at)


# --------------------------------------------------------------------------- the claim --

## {"ok", "why"}. See the header for the order.
func claim(h: int) -> Dictionary:
	var hs = _hs()
	var cl = sim.get("clearing")
	if hs == null or cl == null:
		return {"ok": false, "why": "There is no town"}
	if claimed:
		return {"ok": false, "why": "You already have a base"}
	cl.scan()
	var can: Dictionary = cl.claimable(h)
	if not bool(can.ok):
		return {"ok": false, "why": String(can.why)}
	var p = _lead()
	if p == null:
		return {"ok": false, "why": "You are not here"}
	var spot := spot_of(h)
	if int(hs.house_at(p.x, p.y)) != h or (spot != Vector2.ZERO and Vector2(p.x, p.y).distance_to(spot) > CLAIM_NEAR):
		return {"ok": false, "why": "Stand just inside the front door"}
	install(h)
	claimed = true
	problems = _check_layout()
	var rs = sim.get("rescue")
	if rs != null and rs.has_method("on_claimed"):
		rs.on_claimed(h)    # (the survivors are the ones round THIS house: before a claim nobody is offered)
	var sc = sim.scenario
	if sc != null and sc.has_method("on_claimed"):
		sc.on_claimed(h)
	var words: Array = sc.claim_words(h) if sc != null and sc.has_method("claim_words") else []
	sim.events.append({"type": "claimed", "house": h})
	sim.events.append({"type": "banner", "text": String(words[0]) if words.size() >= 2 else "This house is yours", "sub": String(words[1]) if words.size() >= 2 else "A bed, a stash, a radio. Keep it clear"})
	return {"ok": true, "why": ""}


## What is wrong with the layout just made ([] when nothing is, and for a layout of the fallback's or a test's own maker, which has no kits to check).
func _check_layout() -> Array:
	if maker.is_valid() or not layout.has("kits") or not ResourceLoader.exists(BASE_LAYOUT):
		return []
	var script = load(BASE_LAYOUT)
	var hs = _hs()
	if script == null or not script.has_method("validate") or hs == null or typeof(hs.get("town")) != TYPE_DICTIONARY:
		return []
	return script.validate(layout, hs.town)


## Makes the layout of house `h` and puts it where it goes (no events, no checks: `claim` and the load do those). `with_perimeter` is false on a load: the
## perimeter restores its own segments by id (`perimeter.prepare_load`) and must not make the door segments twice.
func install(h: int, with_perimeter: bool = true) -> void:
	house = h
	layout = _make_layout(h)
	var plots: Array = layout.get("plots", [])
	var buildings: Array = layout.get("buildings", [])
	if not plots.is_empty() and sim.build.has_method("install_layout"):
		sim.build.install_layout(plots, buildings)
	var stations: Array = layout.get("stations", [])
	if not stations.is_empty() and sim.jobs.has_method("install_layout"):
		sim.jobs.install_layout(stations, layout.get("posts", []), layout.get("rest", {}))
	var per = sim.get("perimeter")
	if with_perimeter and per != null and per.has_method("activate"):
		per.activate(layout)
	var bench := prop("bench")
	if not bench.is_empty():
		_set_bench(Vector2(bench.pos))
	var sp: Array = []
	for s in layout.get("spawns", []):
		sp.append(Vector2(s))
	if not sp.is_empty():
		sim.spawns = sp


func _make_layout(h: int) -> Dictionary:
	var hs = _hs()
	var town = hs.get("town")
	var out = null
	if maker.is_valid():
		out = maker.call(town, h)
	elif ResourceLoader.exists(BASE_LAYOUT):
		var script = load(BASE_LAYOUT)
		if script != null and script.has_method("make"):
			out = script.make(town, h)
	if typeof(out) == TYPE_DICTIONARY and not out.is_empty():
		return out
	return _fallback(h)


## The interior-only layout used while BaseLayout is absent: the four stations in the house's rooms, the compound round the lot, spawns on open ground.
func _fallback(h: int) -> Dictionary:
	var hs = _hs()
	var hd: Dictionary = hs.house(h)
	var lot: Rect2i = hd.get("lot", hd.get("rect", Rect2i()))
	var mid := _rect_mid(h)
	return {
		"version": 1, "house": h, "kind": String(hd.get("kind", "small")), "front": String(hd.get("front", "S")),
		"plot": lot, "center": mid, "yard_middle": mid, "compound": Rect2(lot).grow(float(RING)),
		"claim_spot": spot_of(h), "interior": _interior(h),
		"stations": [], "rest": {}, "posts": [], "doors": [], "slots": [], "plots": [], "buildings": [],
		"spawns": _fallback_spawns(mid), "ring": {"free": 0, "blocked": 0},
	}


func _free(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= sim.W or y >= sim.H:
		return false
	var i: int = y * int(sim.W) + x
	return sim.world.solid_p[i] == 0 and sim.world.solid_z[i] == 0


func _interior(h: int) -> Array:
	var hs = _hs()
	var rooms: Array = hs.rooms_of(h)
	var out: Array = []
	if rooms.is_empty():
		return out
	var ordered: Array = rooms.duplicate()
	ordered.sort_custom(_bigger)
	var wants := [["bed", "bed"], ["stash", "kitchen"], ["radio", "living"], ["bench", "hall"]]
	var used := {}
	var k := 0
	for w in wants:
		var room := int(ordered[k % ordered.size()])
		for r in ordered:
			if String(hs.room(r).get("name", "")).contains(String(w[1])):
				room = int(r)
				break
		k += 1
		var tile := _spare_tile(hs.room(room).get("rect", Rect2i()), used)
		out.append({"id": String(w[0]), "kind": String(w[0]), "pos": Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5), "room": room, "face": "S"})
	return out


## The bigger floor first, the lower index on a tie.
func _bigger(a, b) -> bool:
	var hs = _hs()
	var ra: Rect2i = hs.room(a).get("rect", Rect2i())
	var rb: Rect2i = hs.room(b).get("rect", Rect2i())
	var aa := ra.size.x * ra.size.y
	var ab := rb.size.x * rb.size.y
	return aa > ab or (aa == ab and int(a) < int(b))


## A free tile of a room's floor not used yet (the middle one when none is free).
func _spare_tile(rect: Rect2i, used: Dictionary) -> Vector2i:
	for y in range(rect.end.y - 1, rect.position.y - 1, -1):
		for x in range(rect.position.x, rect.end.x):
			if used.has(Vector2i(x, y)) or not _free(x, y):
				continue
			used[Vector2i(x, y)] = true
			return Vector2i(x, y)
	return rect.position + Vector2i(rect.size.x >> 1, rect.size.y >> 1)


func _fallback_spawns(mid: Vector2) -> Array:
	var out: Array = []
	for dir: Vector2 in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var side := Vector2(-dir.y, dir.x)
		var found := false
		for dist: float in [40.0, 45.0, 50.0, 55.0, 38.0, 60.0, 35.0]:
			for lat: float in [0.0, 4.0, -4.0, 8.0, -8.0]:
				var at: Vector2 = mid + dir * dist + side * lat
				if _free(floori(at.x), floori(at.y)):
					out.append(Vector2(floor(at.x) + 0.5, floor(at.y) + 0.5))
					found = true
					break
			if found:
				break
	return out


# --------------------------------------------------------------------------- E uses --

## "Claim this house" at the claim spot of the house the avatar is in when it is one the player was offered (a candidate: scripts/town/arrival.gd; the start house of a town with none),
## "Check the stores" at the stash once claimed.
func candidates(p) -> Array:
	var out: Array = []
	var hs = _hs()
	if hs == null or not enabled:
		return out
	var me := Vector2(p.x, p.y)
	if not claimed:
		var h := int(hs.house_at(p.x, p.y))
		var offered: bool = h >= 0 and (h == int(hs.start_house()) or Arrival.is_candidate(hs.town, h))
		var spot := spot_of(h)
		var cl = sim.get("clearing")
		if offered and spot != Vector2.ZERO and cl != null and me.distance_to(spot) <= CLAIM_REACH:
			var u = sim.get("uses")
			var stop: bool = u != null and u.in_session("claim", "h%d" % h)
			var can: Dictionary = cl.claimable(h)
			out.append({"kind": "claim", "id": "h%d" % h, "label": "Stop" if stop else "Claim this house", "pos": spot, "dist": me.distance_to(spot), "ok": bool(can.ok) or stop, "why": String(can.why), "session": true})
	else:
		var st := prop("stash")
		if not st.is_empty() and me.distance_to(Vector2(st.pos)) <= STASH_REACH:
			out.append({"kind": "stash", "id": "stash", "label": "Check the stores", "pos": Vector2(st.pos), "dist": me.distance_to(Vector2(st.pos)), "ok": true, "why": ""})
	return out


func use(c: Dictionary) -> Dictionary:
	match String(c.get("kind", "")):
		"claim":
			return _use_claim(String(c.get("id", "")))
		"stash":
			return {"ok": true, "line": stores_line(), "why": ""}
	return {}


## E at the claim spot: a 2 s session that claims when it is done.
func _use_claim(id: String) -> Dictionary:
	var h := int(id.trim_prefix("h")) if id.trim_prefix("h").is_valid_int() else -1
	var u = sim.get("uses")
	var p = _lead()
	if u == null or p == null:
		return {"ok": false, "line": "", "why": "You are not here", "session": true}
	if u.in_session("claim", id):
		u.cancel("stopped")
		return {"ok": true, "line": "Stopped.", "why": "", "session": true, "stopped": true}
	var can: Dictionary = sim.clearing.claimable(h)
	if not bool(can.ok):
		return {"ok": false, "line": "", "why": String(can.why), "session": true}
	var r: Dictionary = u.begin_session("claim", id, "Claiming", CLAIM_S, Vector2(p.x, p.y), 0.6, Callable(self, "_claim_done").bind(h))
	if not bool(r.get("ok", false)):
		return {"ok": false, "line": "", "why": String(r.get("why", "")), "session": true}
	return {"ok": true, "line": "Claiming the house", "why": "", "session": true, "seconds": CLAIM_S}


func _claim_done(h: int) -> void:
	var r := claim(h)
	if not bool(r.ok):
		sim.events.append({"type": "banner", "text": "Cannot claim it yet", "sub": String(r.why)})


## "Stores: food 12, water 18, rounds 40, scrap 10, meds 2".
func stores_line() -> String:
	var parts: Array = []
	for e in STOCK_ORDER:
		parts.append("%s %d" % [e[1], floori(float(sim.stock.get(e[0], 0.0)))])
	return "Stores: " + ", ".join(parts)


# ------------------------------------------------------------------------ save / load --

func save() -> Dictionary:
	return {"claimed": claimed, "house": house}


## Reads the saved base back. When `prepare_load` has already put the layout in, it is kept as it is; otherwise it is made now.
func load_state(d: Dictionary) -> void:
	var kept := layout
	var kept_house := house
	var was := claimed and not kept.is_empty()
	start()
	var c = d.get("claimed", false)
	var h = d.get("house", -1)
	if typeof(c) == TYPE_BOOL and bool(c) and (typeof(h) == TYPE_INT or typeof(h) == TYPE_FLOAT) and is_finite(float(h)) and int(h) >= 0 and _hs() != null:
		claimed = true
		house = int(h)
		if was and kept_house == house:
			layout = kept
		else:
			install(house, false)


## Before the save is read (TownSim.prepare_load, hook H11): puts the saved base's layout where it goes (build, jobs, the spawns), so that the perimeter
## and the segments of its built slots are found. Returns what `restore` needs if the save turns out to be no good.
func prepare_load(data: Dictionary):
	var before := {"claimed": claimed, "house": house, "layout": layout, "spawns": sim.spawns.duplicate()}
	var mods = data.get("modules", {})
	var md = mods.get("base", {}) if typeof(mods) == TYPE_DICTIONARY else {}
	if typeof(md) == TYPE_DICTIONARY and typeof(md.get("claimed", false)) == TYPE_BOOL and bool(md.get("claimed", false)):
		var h = md.get("house", -1)
		if (typeof(h) == TYPE_INT or typeof(h) == TYPE_FLOAT) and is_finite(float(h)) and int(h) >= 0 and _hs() != null:
			install(int(h), false)
			claimed = true
	return before


## The save was refused: the base as it was before `prepare_load`.
func restore(before) -> void:
	if typeof(before) != TYPE_DICTIONARY or before.is_empty():
		return
	var had: bool = not Dictionary(before.layout).is_empty()
	claimed = bool(before.claimed)
	house = int(before.house)
	layout = before.layout
	sim.spawns = before.spawns
	var bench := prop("bench")
	if bench.is_empty():
		_put_bench_away()
	else:
		_set_bench(Vector2(bench.pos))
	if not had:
		if sim.build.has_method("clear_layout"):
			sim.build.clear_layout()
		if sim.jobs.has_method("clear_layout"):
			sim.jobs.clear_layout()
