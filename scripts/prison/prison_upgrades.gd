## EXPERIMENT (prison management, step 3): the VISIBLE WORLD. Each project tier built in the economy (prison_econ.gd) changes the compound, and the crew does the work on site.
## Pattern: code-drawn props in the game's ink-outline style (like the towers and the laundry line), on four cached layers of the world, no scene nodes and no AnimationPlayer
## (the game draws everything in `_draw`, and the people animate by the work poses of work_anim.gd): `ground` (under the people: beds, barrels, fence, cots, dirt; redrawn only when a
## signature of the tiers, the stage, the crop stages or the queue changes), `top` (over the people: water tower, glass roof, mast, floodlight poles), `lights` (additive cones, only its
## alpha moves with the night) and `fx` (the one that is redrawn every frame: smoke, sparks, progress bars, the generator's shake, the crops' harvest pops).
## Work: a queued project gets a stop (`eat`, the slot a meal or clean-up stop uses in prison_crew.gd, so the route goes on after it) for a living crew member of the project's role, only in daylight and never in a siege, meals first;
## the person walks to the site, works in the pose of the building and `labor()` calls `econ.add_labor` every frame; `econ.fallback_labor` is switched off.
## Flags: `--tiers=water3,garden3,...` builds those projects (and the ones below) at once, `--econ=build:all` builds every top tier, `--building=water2,fence1` starts those projects
## (stores topped up) so that the scaffolds and the crew are seen at work.
extends RefCounted

const DrawNode := preload("res://scripts/render/draw_node.gd")
const Tower := preload("res://scripts/prison/prison_tower.gd")
const Base := preload("res://scripts/prison/prison_base.gd")
const WorkAnim := preload("res://scripts/render/work_anim.gd")
const T := 64.0
const INK := Color(0.12, 0.08, 0.05)
const WOOD := Color(0.47, 0.35, 0.22)
const WOOD_D := Color(0.36, 0.26, 0.16)
const WOOD_L := Color(0.62, 0.48, 0.3)
const METAL := Color(0.5, 0.52, 0.55)
const METAL_D := Color(0.32, 0.34, 0.38)
const WATER := Color(0.3, 0.55, 0.78)
const HOURS_PER_SEC := 4.0 / 60.0
const CALM_FROM := 7.0
const CALM_TO := 19.0
## project id -> {stand: where the worker stands, anchor: the prop, face, work: pose, size: scaffold tiles}. A fallback by building is below.
const SITES := {
	"water1": {"stand": Vector2(72.4, 25.3), "anchor": Vector2(72.4, 23.9), "face": "N", "work": "hammer", "size": Vector2(2.4, 0.9)},
	"water2": {"stand": Vector2(77.6, 25.0), "anchor": Vector2(77.6, 26.5), "face": "S", "work": "hammer", "size": Vector2(1.8, 1.4)},
	"water3": {"stand": Vector2(80.7, 24.9), "anchor": Vector2(80.7, 26.6), "face": "S", "work": "hammer", "size": Vector2(2.6, 1.6)},
	"garden1": {"stand": Vector2(68.5, 32.2), "anchor": Vector2(68.5, 31.0), "face": "N", "work": "garden", "size": Vector2(2.0, 1.0)},
	"garden2": {"stand": Vector2(68.5, 33.2), "anchor": Vector2(70.5, 33.0), "face": "E", "work": "hammer", "size": Vector2(2.6, 0.7)},
	"garden3": {"stand": Vector2(75.0, 33.2), "anchor": Vector2(75.0, 31.8), "face": "N", "work": "hammer", "size": Vector2(4.0, 2.2)},
	"kitchen1": {"stand": Vector2(81.0, 11.2), "anchor": Vector2(81.0, 9.7), "face": "N", "work": "bench", "size": Vector2(1.8, 1.0)},
	"kitchen2": {"stand": Vector2(83.5, 18.0), "anchor": Vector2(84.9, 18.0), "face": "E", "work": "hammer", "size": Vector2(0.9, 3.4)},
	"kitchen3": {"stand": Vector2(77.5, 18.0), "anchor": Vector2(77.5, 16.6), "face": "N", "work": "hammer", "size": Vector2(2.6, 1.0)},
	"infirmary1": {"stand": Vector2(21.8, 36.6), "anchor": Vector2(23.2, 36.4), "face": "E", "work": "hammer", "size": Vector2(1.0, 3.0)},
	"infirmary2": {"stand": Vector2(17.2, 39.2), "anchor": Vector2(17.2, 40.4), "face": "S", "work": "bench", "size": Vector2(2.4, 0.9)},
	"infirmary3": {"stand": Vector2(18.2, 36.4), "anchor": Vector2(19.2, 35.2), "face": "N", "work": "bench", "size": Vector2(2.0, 1.2)},
	"dormitory1": {"stand": Vector2(19.5, 15.5), "anchor": Vector2(19.5, 14.6), "face": "N", "work": "hammer", "size": Vector2(12.0, 1.0)},
	"dormitory2": {"stand": Vector2(19.5, 15.5), "anchor": Vector2(19.5, 16.5), "face": "S", "work": "hammer", "size": Vector2(12.0, 1.0)},
	"dormitory3": {"stand": Vector2(47.5, 15.5), "anchor": Vector2(47.5, 14.6), "face": "N", "work": "hammer", "size": Vector2(12.0, 1.0)},
	"power1": {"stand": Vector2(26.0, 35.8), "anchor": Vector2(26.0, 33.8), "face": "N", "work": "bench", "size": Vector2(2.0, 1.8)},
	"power2": {"stand": Vector2(30.0, 53.1), "anchor": Vector2(30.0, 54.2), "face": "S", "work": "hammer", "size": Vector2(1.0, 1.2)},
	"fence1": {"stand": Vector2(26.0, 53.4), "anchor": Vector2(26.0, 55.0), "face": "S", "work": "mend", "size": Vector2(3.0, 0.8)},
	"fence2": {"stand": Vector2(26.0, 53.4), "anchor": Vector2(26.0, 55.0), "face": "S", "work": "mend", "size": Vector2(3.0, 0.8)},
	"fence3": {"stand": Vector2(26.0, 53.4), "anchor": Vector2(26.0, 54.4), "face": "S", "work": "mend", "size": Vector2(3.0, 1.2)},
	"radio1": {"stand": Vector2(58.5, 37.8), "anchor": Vector2(58.8, 36.6), "face": "N", "work": "bench", "size": Vector2(1.8, 1.0)},
}
## One bunk per bed a tier adds (4 each): between the cell doors (every 4 tiles from x 11 and x 39) in the corridors of the two cell blocks: tier 1 block A north row, tier 2 block A south row, tier 3 block B north row.
const BUNKS := {1: [[13.5, 14.6], [17.5, 14.6], [21.5, 14.6], [25.5, 14.6]], 2: [[13.5, 16.5], [17.5, 16.5], [21.5, 16.5], [25.5, 16.5]], 3: [[41.5, 14.6], [45.5, 14.6], [49.5, 14.6], [53.5, 14.6]]}
## What a built tier puts on the ground that people must walk round: [building, first tier, Rect2 in tiles]. A tile the rect covers (shrunk 0.15) is shut to walking, the dead and the path finders; not to a shot.
const PROPS := [
	["water", 1, Rect2(70.74, 23.6, 2.72, 0.68)], ["water", 2, Rect2(77.0, 26.0, 1.2, 1.0)], ["water", 3, Rect2(79.6, 25.4, 2.2, 1.7)], ["water", 3, Rect2(87.3, 24.4, 1.6, 2.3)],
	["power", 1, Rect2(25.0, 32.6, 2.0, 1.8)], ["garden", 2, Rect2(64.2, 28.9, 1.2, 1.0)], ["radio", 1, Rect2(57.8, 36.2, 1.8, 0.9)], ["radio", 1, Rect2(61.6, 29.1, 0.7, 0.5)],
	["infirmary", 1, Rect2(22.7, 33.8, 1.1, 2.1)], ["infirmary", 1, Rect2(22.7, 36.9, 1.1, 2.1)], ["infirmary", 2, Rect2(15.8, 40.0, 2.8, 0.8)],
	["infirmary", 3, Rect2(18.3, 34.6, 1.8, 1.0)], ["infirmary", 3, Rect2(20.4, 34.7, 0.4, 0.7)],
	["kitchen", 1, Rect2(80.0, 9.0, 2.0, 1.1)], ["kitchen", 2, Rect2(84.7, 14.0, 1.15, 6.3)], ["kitchen", 2, Rect2(82.8, 19.3, 1.8, 1.6)], ["kitchen", 2, Rect2(82.0, 20.1, 0.6, 0.7)],
]
const TABLES := [Vector2(70, 16.5), Vector2(75, 16.5), Vector2(80, 16.5), Vector2(70, 19.5), Vector2(75, 19.5), Vector2(80, 19.5)]
const POLES := [[16.0, 54.2, 0.0, 1.0], [30.0, 54.2, 0.0, 1.0], [64.0, 54.2, 0.0, 1.0], [78.0, 54.2, 0.0, 1.0], [30.0, 5.8, 0.0, -1.0], [48.0, 5.8, 0.0, -1.0], [66.0, 5.8, 0.0, -1.0],
	[7.3, 18.0, -1.0, 0.0], [7.3, 40.0, -1.0, 0.0], [88.7, 18.0, 1.0, 0.0], [88.7, 40.0, 1.0, 0.0]]
const GROW_H := [0.0, 9.0, 6.0, 4.0]    # game hours from planting to ripe, by garden tier
const DIRT_BY_STAGE := {"Camp": 1.0, "Shelter": 0.5, "Settlement": 0.0, "Fortress": 0.0, "Hub": 0.0}
const DIRT_ZONES := [Rect2(11, 9, 22, 13), Rect2(39, 9, 22, 13), Rect2(67, 9, 19, 13), Rect2(11, 30, 13, 11), Rect2(29, 30, 16, 11), Rect2(51, 30, 9, 9), Rect2(9, 44, 28, 10), Rect2(39, 44, 22, 9), Rect2(9, 24, 78, 2)]

var game
var econ
var ground: Array = []    # one node per prop group (so that a group out of the view is culled): {key, node, sig}
var top: Node2D
var hum: AudioStreamPlayer2D
var _blocked := {}    # tile index -> true: the tiles this file has shut
var fx: Node2D
var beds: Array = []    # {c: Vector2 (tiles), t0: game hours the crop was planted, kind: 0 tomato, 1 cabbage, 2 carrot}
var decals: Array = []    # per dirt zone: an Array of {p: Vector2, k: int, s: float, r: float}
var puffs: Array = []    # {p: Vector2 (px), v: Vector2, age, life, r, a, up}
var sparks: Array = []    # {p, v, age}
var bursts: Array = []    # {p: Vector2 (px), age}
var _gt := 0.0    # game hours since the base was built
var _top_sig := 0
var _sig_t := 99.0
var _puff_t := 0.0
var _ruth_t := 0.0
var _stove_t := 0.0
var _clock := 0.0
var _staging := false
var _last_stage := ""
var _stage_beds_n := 0


func _init(g) -> void:
	game = g
	econ = g.econ
	econ.project_done.connect(_done)


# ------------------------------------------------------------------ setup ------

func setup() -> void:
	for n in [top, fx, hum]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	for g in ground:
		if is_instance_valid(g.node):
			(g.node as Node).queue_free()
	ground = []
	var w: Node2D = game.world
	var keys: Array = ["water", "irrig", "kitchen", "infirmary", "dormA", "dormB", "radio", "scaf"]
	for i in 5:
		keys.append("fence%d" % i)
		keys.append("bed%d" % i)
	for i in DIRT_ZONES.size():
		keys.append("dirt%d" % i)
	for k in keys:
		ground.append({"key": k, "node": _layer(w, 4, Callable(self, "_pg").bind(k)), "sig": -1})
	fx = _layer(w, 10, _paint_fx)
	top = _layer(w, 11, _paint_top)
	puffs.clear()
	sparks.clear()
	bursts.clear()
	_gt = 0.0
	_sig_t = 99.0
	_top_sig = -1
	game.crew.labor_cb = Callable(self, "labor")
	game.crew.busy_cb = Callable(self, "has_work")
	econ.rate_cb = Callable(self, "workers_on")
	_blocked.clear()
	_make_hum(w)
	if not game.args.has("econ-lab"):
		econ.fallback_labor = false
	_make_beds()
	_make_decals()
	_stage_flags()
	_block_props()
	_check_sites()


func _layer(parent: Node, z: int, painter: Callable) -> Node2D:
	var n: Node2D = DrawNode.new()
	n.z_index = z
	n.painter = painter
	parent.add_child(n)
	return n


func _make_beds() -> void:
	beds.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var i := 0
	for row in 5:
		for x in range(66, 85, 3):
			beds.append({"c": Vector2(float(x) + 1.0, float(30 + row * 4) + 1.0), "t0": -rng.randf_range(0.0, 14.0), "kind": i % 3, "row": row})
			i += 1


func _make_decals() -> void:
	decals.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for zi in DIRT_ZONES.size():    # about one decal for every six tiles of a zone
		var zr: Rect2 = DIRT_ZONES[zi]
		var arr: Array = []
		for i in maxi(2, int(zr.get_area() / 6.0)):
			arr.append({"p": zr.position + Vector2(rng.randf() * zr.size.x, rng.randf() * zr.size.y), "k": rng.randi() % 5, "s": 0.3 + rng.randf() * 0.5, "r": rng.randf() * TAU})
		decals.append(arr)


func _stage_flags() -> void:
	_staging = true
	var a: Dictionary = game.args
	if a.has("tiers"):
		for id in String(a.tiers).split(","):
			econ.debug_build(id)
	if String(a.get("econ", "")) == "build:all":
		for id in ["water1", "garden1", "kitchen1", "infirmary1", "dormitory1", "power1", "fence2", "radio1", "convoy1"]:
			econ.debug_build(id)
	if a.has("fuel"):
		game.stores["fuel"] = float(a.fuel)
	if a.has("building"):
		for r in ["scrap", "parts", "fuel"]:
			game.stores[r] = 900.0
		for id in String(a.building).split(","):
			econ.start(id)
	_staging = false
	if econ.tier("fence") > 0:
		game.siege.apply_fence(econ.fence_mult(), false)    # (the siege keeps its hp over the tiers built by a flag)


## `--log`: sites, crew route stops and tower spots that are shut or that a person can not walk to from the gate are a bug of the tables: say so once (build everything first with `--econ=build:all`).
func _check_sites() -> void:
	if not game.args.has("log"):
		return
	var pf = game.run.sim.path_p
	var sol: PackedByteArray = game.world.solid_p
	var pts: Array = []
	for id in SITES:
		pts.append([id, Vector2(SITES[id].stand)])
	for r in game.crew.ROSTER:
		for st in r.get("route", []):
			pts.append([String(r.id), game.crew._where(st.at)])
	for k in game.base.stations:
		pts.append(["station " + String(k), game.base.stations[k]])
	var bad := 0
	for q in pts:
		var v: Vector2 = q[1]
		if sol[int(v.y) * game.world.W + int(v.x)] != 0 and not String(q[0]).begins_with("station"):
			print("WORLD stop in a shut tile: ", q[0], " ", v)
			bad += 1
		if pf.find(sol, Base.SPAWN.x, Base.SPAWN.y, v.x, v.y).is_empty():
			print("WORLD stop not reachable: ", q[0], " ", v)
			bad += 1
	print("WORLD walk test: ", pts.size(), " points, ", bad, " bad, ", _blocked.size(), " prop tiles shut")


# --------------------------------------------------------------- the update ------

func update(dt: float) -> void:
	if not econ.active() or ground.is_empty():
		return
	if game.args.has("noupg"):    # (a check: the perf cost of this file; "all" hides the layers and stops)
		for g in ground:
			g.node.visible = false
		top.visible = false
		fx.visible = false
		return
	_clock += dt
	_gt += dt * HOURS_PER_SEC
	_assign()
	_harvest()
	_effects(dt)
	_sig_t += dt
	if _sig_t > 0.5:
		_sig_t = 0.0
		for g in ground:
			var sg := _sig_of(String(g.key))
			if sg != int(g.sig):
				g.sig = sg
				g.node.queue_redraw()
		var ts := _tiers_sig()
		if ts != _top_sig:
			_top_sig = ts
			top.queue_redraw()
	_ruth(dt)
	_hum_update()
	fx.queue_redraw()


func game_night() -> float:
	return game._night_of(game.tod)


func _tiers_sig() -> int:
	var a: Array = []
	for b in ["water", "garden", "kitchen", "infirmary", "dormitory", "power", "fence", "radio"]:
		a.append(econ.tier(b))
	return hash(a) + (1 if _lit() else 0)


## What a prop group depends on: a changed value redraws that group only.
func _sig_of(key: String) -> int:
	if key.begins_with("fence"):
		return econ.tier("fence")
	if key.begins_with("dirt"):
		return int(float(DIRT_BY_STAGE[econ.stage()]) * 100.0)
	if key.begins_with("bed"):
		var a: Array = [econ.tier("garden")]
		for b in beds:
			if int(b.row) == int(key.substr(3)):
				a.append(_crop(b))
		return hash(a)
	match key:
		"water":
			return econ.tier("water")
		"irrig":
			return econ.tier("garden")
		"kitchen":
			return econ.tier("kitchen")
		"infirmary":
			return econ.tier("infirmary")
		"dormA":
			return mini(econ.tier("dormitory"), 2)
		"dormB":
			return econ.tier("dormitory")
		"radio":
			return econ.tier("radio")
		"scaf":
			var q: Array = []
			for id in econ.queue:
				q.append(id)
			return hash(q)
	return 0


func _lit() -> bool:
	return econ.tier("power") >= 1 and float(game.stores.get("fuel", 0.0)) > 0.0


func _calm() -> bool:
	return not game.siege.attacking and game.tod >= CALM_FROM and game.tod < CALM_TO and game.phase == "managed"


## Gives a free crew member of the role a project stop (the queued project of their role that comes first).
func _assign() -> void:
	var roles: Dictionary = econ.cfg.crew_role
	if not _calm():
		for m in game.crew.members:
			if m.has("eat") and (m.eat as Dictionary).has("build"):
				m.erase("eat")
				m.state = "wait"
				m.p.work = ""
		return
	if econ.queue.is_empty():
		return
	var wc: Dictionary = econ.cfg.work
	for id in econ.queue:    # each project takes the NEAREST free people of its role, up to `max_workers` of them
		var have := workers_on(id)
		if have >= int(wc.max_workers):
			continue
		var role := String(econ.defs[id].role)
		var s: Dictionary = site_of(id)
		var cands: Array = []
		for m in game.crew.members:
			if not ["wait", "walk", "arrive", "idle"].has(String(m.state)) or m.has("down") or m.has("eat"):
				continue
			if String(roles.get(String(m.def.id), "")) != role or m.def.has("stand") or m.def.has("play"):
				continue
			cands.append(m)
		cands.sort_custom(func(x, y): return Vector2(x.p.x, x.p.y).distance_to(s.stand) < Vector2(y.p.x, y.p.y).distance_to(s.stand))
		for m in cands:
			if have >= int(wc.max_workers):
				break
			var side := float(have) * 0.8 - 0.4    # (two workers on one site do not stand on each other)
			m["eat"] = {"at": Vector2(s.stand) + Vector2(side, 0.0), "secs": float(wc.stop_secs), "work": s.work, "face": s.face, "say": "building: %s" % String(econ.defs[id].name), "build": id}    # (taken like a meal stop: the route goes on after it)
			m.state = "wait"
			m.p.work = ""
			have += 1
			if game.args.has("log"):
				print("WORLD stop ", m.def.name, " -> ", id, " at ", snappedf(game.tod, 0.1))


## How many people are on their way to or at the site of a project.
func workers_on(id: String) -> int:
	var n := 0
	for m in game.crew.members:
		if m.has("eat") and String((m.eat as Dictionary).get("build", "")) == id:
			n += 1
	return n


## prison_crew.gd asks before a meal: someone with a project of their role to build skips the meal (once in a row: the next meal they eat, so nobody starves on site).
func has_work(m: Dictionary) -> bool:
	if econ.queue.is_empty() or not _calm():
		return false
	var role := String(econ.cfg.crew_role.get(String(m.def.id), ""))
	for id in econ.queue:
		if String(econ.defs[id].role) == role and workers_on(id) < int(econ.cfg.work.max_workers):
			return true
	return false


## Hold E at a scaffold: Ruth adds her labor (`work.ruth_rate` secs of labor a second) to the project.
func _ruth(dt: float) -> void:
	_ruth_t -= dt
	if game.siege.attacking or game.busy or game.mode != "base" or econ.queue.is_empty() or game.board.is_open():
		return
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	for id in econ.queue:
		var s: Dictionary = site_of(id)
		if me.distance_to(s.anchor) > float(econ.cfg.work.ruth_reach) + float(Vector2(s.size).x) * 0.5:
			continue
		if not game._prompt.is_empty():
			return
		game._prompt = {"kind": "help", "label": "Hold E: help build %s (%d%%, about %.1f h left)" % [String(econ.defs[id].name), int(100.0 * float(econ.st[id].done) / float(econ.defs[id].labor)), econ.eta_h(id)]}
		if Input.is_key_pressed(KEY_E) or game.args.has("autohelp"):
			econ.add_labor(id, dt * float(econ.cfg.work.ruth_rate))
			game.run.sim.avatar.set_input(Vector2.ZERO, Vector2(s.anchor), false)
			if _ruth_t <= 0.0:
				_ruth_t = 0.45
				_blow(String(s.work), id)
		return


func site_of(id: String) -> Dictionary:
	return SITES.get(id, {"stand": econ.site(id), "anchor": econ.site(id) + Vector2(0, -1), "face": "N", "work": "hammer", "size": Vector2(2, 1)})


## prison_crew.gd calls this every frame a person works a project stop.
func labor(m: Dictionary, stop: Dictionary, dt: float) -> void:
	var id := String(stop.build)
	if not game.siege.attacking:
		econ.add_labor(id, dt)
	if econ.state(id) == "built":
		m.t = float(stop.secs)


func _done(id: String) -> void:
	_sig_t = 99.0
	_block_props()
	if _staging or ground.is_empty():
		return
	if game.args.has("log"):
		print("WORLD built ", id, " at ", snappedf(game.tod, 0.1))
	var s: Dictionary = site_of(id)
	bursts.append({"p": Vector2(s.anchor) * T, "age": 0.0})
	game.crew.floaters.append({"text": "Built: %s" % String(econ.defs[id].name), "pos": Vector2(s.anchor) + Vector2(0, -1.4), "t": 0.0, "col": Color(0.6, 1.0, 0.6)})
	if game.sound != null:
		game.sound.ui("ui_confirm", 0.6)


## A gardener working near a ripe bed picks it: the bed is planted again.
func _harvest() -> void:
	if econ.tier("garden") < 1:
		return
	for m in game.crew.members:
		if m.state != "work" or String(m.p.work) != "garden" or float(m.t) < 5.0:
			continue
		var at := Vector2(m.p.x, m.p.y)
		for b in beds:
			if _crop(b) == 3 and (b.c as Vector2).distance_to(at) < 2.6:
				b.t0 = _gt
				_sig_t = 99.0
				game.crew.floaters.append({"text": "harvest", "pos": Vector2(b.c), "t": 0.0, "col": Color(1.0, 0.85, 0.4)})
				break


## 0 bare, 1 seedling, 2 half grown, 3 ripe.
func _crop(b: Dictionary) -> int:
	var t: int = econ.tier("garden")
	if t < 1:
		return 0
	var p: float = (_gt - float(b.t0)) / float(GROW_H[t])
	return 1 if p < 0.3 else (2 if p < 0.7 else 3)


# ----------------------------------------------------------------- effects ------

func _effects(dt: float) -> void:
	# build work: dust and sparks on every blow, the hammer's sound
	for m in game.crew.members:
		if m.state != "work" or not m.has("eat") or not (m.eat as Dictionary).has("build"):
			continue
		var pose := String(m.eat.work)
		var per: float = WorkAnim.period(pose)
		var beat := int(float(m.t) / per)
		if beat != int(m.get("bfx", -1)):
			m["bfx"] = beat
			_blow(pose, String(m.eat.build))
	var gen := _lit()
	_stove_t -= dt
	_puff_t -= dt
	if gen and _puff_t <= 0.0:
		_puff_t = 0.16
		puffs.append({"p": Vector2(26.6, 32.0) * T, "v": Vector2(randf_range(-6, 14), -26.0), "age": 0.0, "life": 1.3, "r": 4.0, "a": 0.5, "up": 14.0, "col": Color(0.45, 0.45, 0.47)})
	if econ.tier("kitchen") >= 1 and game.crew._meal_window() >= 0 and _stove_t <= 0.0:
		_stove_t = 0.25
		puffs.append({"p": Vector2(80.9, 7.9) * T, "v": Vector2(randf_range(-8, 8), -30.0), "age": 0.0, "life": 2.4, "r": 6.0, "a": 0.5, "up": 18.0, "col": Color(0.82, 0.82, 0.84)})
	for q in puffs:
		q.age = float(q.age) + dt
		q.p = Vector2(q.p) + Vector2(q.v) * dt
		q.r = float(q.r) + float(q.up) * dt
	puffs = puffs.filter(func(q): return float(q.age) < float(q.life))
	for q in sparks:
		q.age = float(q.age) + dt
		q.p = Vector2(q.p) + Vector2(q.v) * dt
		q.v = Vector2(q.v) + Vector2(0, 340.0) * dt
	sparks = sparks.filter(func(q): return float(q.age) < 0.4)
	for q in bursts:
		q.age = float(q.age) + dt
	bursts = bursts.filter(func(q): return float(q.age) < 1.2)


## One blow on a site: dust, and sparks unless it is garden work, and the hammer's sound when Ruth is near.
func _blow(pose: String, id: String) -> void:
	var s: Dictionary = site_of(id)
	var at: Vector2 = Vector2(s.anchor) * T + Vector2(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2)) * T * 0.5
	for k in 3:
		puffs.append({"p": at, "v": Vector2(randf_range(-14, 14), randf_range(-26, -8)), "age": 0.0, "life": 0.7, "r": 6.0 + randf() * 5.0, "a": 0.55, "up": 0.0, "col": Color(0.78, 0.7, 0.55)})
	if pose != "garden":
		for k in 4:
			sparks.append({"p": at, "v": Vector2(randf_range(-90, 90), randf_range(-110, -30)), "age": 0.0})
		var avatar := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
		if (Vector2(s.anchor)).distance_to(avatar) < 16.0 and game.sound != null:
			game.sound.play("hammer", 0.3, 0.1)
			game.audio.build_blow(pose, Vector2(s.anchor))


func glow_spots(n: float) -> Array:
	var out: Array = []
	if n <= 0.02:
		return out
	if econ.tier("kitchen") >= 3:
		for t in TABLES:
			if Vector2(t).y > 18.0 or Vector2(t).x == 75.0:
				out.append([Vector2(t), 3.2, Color(1.0, 0.85, 0.5, 0.35 * n)])
	if _lit():
		out.append([Vector2(25.4, 33.2), 2.0, Color(1.0, 0.8, 0.4, 0.4 * n)])    # the shed's window
		if econ.tier("power") >= 1:
			for p in POLES:
				out.append([Vector2(float(p[0]), float(p[1])), 4.0, Color(1.0, 0.97, 0.8, 0.35 * n)])
		if econ.tier("radio") >= 1:
			out.append([Vector2(58.7, 36.5), 2.2, Color(1.0, 0.9, 0.6, 0.3 * n)])
	if econ.tier("infirmary") >= 3:
		out.append([Vector2(19.2, 35.2), 3.0, Color(0.9, 1.0, 1.0, 0.3 * n)])
	return out


# ----------------------------------------------------------------- drawing ------

func _r(c: CanvasItem, x: float, y: float, w: float, h: float, col: Color, ink: bool = true, lw: float = 2.0) -> void:
	var r := Rect2(Vector2(x, y) * T, Vector2(w, h) * T)
	c.draw_rect(r, col)
	if ink:
		c.draw_rect(r, INK, false, lw)


func _ln(c: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	c.draw_line(a * T, b * T, INK, w + 2.0)
	c.draw_line(a * T, b * T, col, w)


func _disc(c: CanvasItem, p: Vector2, rad: float, col: Color) -> void:
	c.draw_circle(p * T, rad * T + 1.5, INK)
	c.draw_circle(p * T, rad * T - 0.5, col)


func _shadow(c: CanvasItem, x: float, y: float, w: float, h: float) -> void:
	c.draw_rect(Rect2(Vector2(x + 0.12, y + 0.16) * T, Vector2(w, h) * T), Color(0, 0, 0, 0.22))


func _pg(c: CanvasItem, key: String) -> void:
	if key.begins_with("fence"):
		_fence(c, econ.tier("fence"), int(key.substr(5)))
	elif key.begins_with("dirt"):
		_dirt(c, float(DIRT_BY_STAGE[econ.stage()]), int(key.substr(4)))
	elif key.begins_with("bed"):
		if econ.tier("garden") >= 1:
			for b in beds:
				if int(b.row) == int(key.substr(3)):
					_bed(c, b, econ.tier("garden"))
	else:
		match key:
			"water":
				_water(c, econ.tier("water"))
			"irrig":
				_garden(c, econ.tier("garden"))
			"kitchen":
				_kitchen(c, econ.tier("kitchen"))
			"infirmary":
				_infirmary(c, econ.tier("infirmary"))
			"dormA":
				_dorm(c, mini(econ.tier("dormitory"), 2))
			"dormB":
				_dorm_b(c, econ.tier("dormitory"))
			"radio":
				_radio(c, econ.tier("radio"))
			"scaf":
				for id in econ.queue:
					_scaffold(c, id)


## Stains, crumbs, litter and puddles; the share drawn falls with the stage (the cleaner's rubbish piles are capped in `update`).
func _dirt(c: CanvasItem, share: float, zi: int) -> void:
	var zd: Array = decals[zi]
	var n := int(float(zd.size()) * share)
	for i in n:
		var d: Dictionary = zd[i]
		var p: Vector2 = Vector2(d.p) * T
		var s: float = float(d.s) * T
		match int(d.k):
			0, 1:
				var pts := PackedVector2Array()
				for k in 7:
					var a: float = float(d.r) + float(k) * TAU / 7.0
					pts.append(p + Vector2(cos(a), sin(a) * 0.55) * s * (0.6 + 0.4 * sin(float(k) * 2.3 + float(d.r))))
				c.draw_colored_polygon(pts, Color(0.2, 0.15, 0.1, 0.32) if int(d.k) == 0 else Color(0.35, 0.1, 0.08, 0.28))
			2:
				c.draw_rect(Rect2(p, Vector2(9, 6)), Color(0.9, 0.88, 0.8, 0.85))
				c.draw_rect(Rect2(p, Vector2(9, 6)), INK, false, 1.0)
			3:
				c.draw_circle(p, 4.5, Color(0.55, 0.55, 0.58, 0.9))
				c.draw_circle(p, 4.5, INK, false, 1.2)
			4:
				for k in 5:
					c.draw_rect(Rect2(p + Vector2(float(k) * 4.0, sin(float(k) * 3.1) * 3.0), Vector2(2.5, 2.5)), Color(0.5, 0.4, 0.28, 0.9))


func _fence(c: CanvasItem, tier: int, only: int) -> void:
	if tier < 1:
		return
	var lines: Array = [
		[Vector2(6.5, 4.5), Vector2(89.5, 4.5), Vector2(0, 1)],
		[Vector2(6.5, 55.5), Vector2(45.8, 55.5), Vector2(0, -1)],
		[Vector2(50.2, 55.5), Vector2(89.5, 55.5), Vector2(0, -1)],
		[Vector2(6.5, 4.5), Vector2(6.5, 55.5), Vector2(1, 0)],
		[Vector2(89.5, 4.5), Vector2(89.5, 55.5), Vector2(-1, 0)],
	]
	for li in lines.size():
		if li != only:
			continue
		var L: Array = lines[li]
		var a: Vector2 = L[0]
		var b: Vector2 = L[1]
		var inw: Vector2 = L[2]
		var d: Vector2 = b - a
		var len := d.length()
		var dir := d / len
		if tier >= 1:    # patched: sheet metal and planks over the weak places
			var k := 3.0
			while k < len - 2.0:
				var at: Vector2 = a + dir * k
				var along := dir * 0.65
				var across := inw * 0.28
				var pts := PackedVector2Array([(at - along - across) * T, (at + along - across) * T, (at + along + across) * T, (at - along + across) * T])
				c.draw_colored_polygon(pts, Color(0.5, 0.46, 0.4) if int(k) % 2 == 0 else WOOD_L)
				c.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), INK, 2.0)
				c.draw_circle((at - along * 0.6) * T, 1.8, INK)
				c.draw_circle((at + along * 0.6) * T, 1.8, INK)
				k += 7.3
		if tier >= 2:    # reinforced: posts every two tiles, a second strand with barbs, braces
			var kk := 0.0
			while kk <= len:
				var q: Vector2 = a + dir * kk
				_r(c, q.x - 0.1, q.y - 0.1, 0.2, 0.2, WOOD_D, true, 2.0)
				kk += 2.0
			var out_v := -inw * 0.2
			var zig := PackedVector2Array()
			var z := 0.0
			var up := true
			while z <= len:
				zig.append((a + dir * z + out_v + (inw * 0.07 if up else -inw * 0.07)) * T)
				up = not up
				z += 0.3
			c.draw_polyline(zig, Color(0.15, 0.15, 0.17), 1.6)
			c.draw_line((a + out_v) * T, (b + out_v) * T, Color(0.72, 0.72, 0.76), 2.0)
		if tier >= 3:    # double fence: a second chain-link line inside, tied back to the first
			var off := inw * 1.0
			var a2: Vector2 = a + off
			var b2: Vector2 = b + off
			if absf(inw.x) > 0.0:
				a2 = a + off + Vector2(0, 0)
			c.draw_line(a2 * T, b2 * T, INK, 5.0)
			c.draw_line(a2 * T, b2 * T, Color(0.6, 0.62, 0.66), 2.5)
			var mesh := PackedVector2Array()
			var z2 := 0.0
			var flip := true
			while z2 <= len:
				mesh.append((a2 + dir * z2 + (inw * 0.22 if flip else -inw * 0.22)) * T)
				flip = not flip
				z2 += 0.45
			c.draw_polyline(mesh, Color(0.5, 0.52, 0.56, 0.8), 1.2)
			var k3 := 0.0
			while k3 <= len:
				var q2: Vector2 = a2 + dir * k3
				_r(c, q2.x - 0.12, q2.y - 0.12, 0.24, 0.24, METAL_D, true, 2.0)
				if int(k3) % 12 == 0:
					c.draw_line((a + dir * k3) * T, q2 * T, INK, 3.0)
				k3 += 3.0


func _barrel(c: CanvasItem, p: Vector2) -> void:
	_shadow(c, p.x - 0.22, p.y - 0.1, 0.5, 0.4)
	_r(c, p.x - 0.26, p.y - 0.34, 0.52, 0.66, Color(0.25, 0.4, 0.6))
	for k in [-0.12, 0.12]:
		c.draw_line(Vector2(p.x - 0.26, p.y + k) * T, Vector2(p.x + 0.26, p.y + k) * T, INK, 2.0)
	c.draw_circle(Vector2(p.x, p.y - 0.34) * T, 0.24 * T, INK)
	c.draw_circle(Vector2(p.x, p.y - 0.34) * T, 0.2 * T, WATER)
	c.draw_arc(Vector2(p.x, p.y - 0.34) * T, 0.1 * T, 0.2, 1.8, 6, Color(1, 1, 1, 0.6), 1.5)


func _water(c: CanvasItem, tier: int) -> void:
	if tier >= 1:    # rain barrels under a gutter of the canteen roof
		_ln(c, Vector2(70.3, 23.15), Vector2(73.9, 23.15), METAL, 3.0)
		_ln(c, Vector2(71.0, 23.15), Vector2(71.0, 23.5), METAL, 2.5)
		for x in [71.0, 72.1, 73.2]:
			_barrel(c, Vector2(x, 23.95))
	if tier >= 2:    # the well: a stone ring, two posts, a hand pump and a bucket
		var w := Vector2(77.6, 26.5)
		_shadow(c, w.x - 0.55, w.y - 0.4, 1.1, 1.0)
		c.draw_circle(w * T, 0.58 * T, INK)
		c.draw_circle(w * T, 0.52 * T, Color(0.55, 0.55, 0.52))
		for k in 10:
			var a := float(k) * TAU / 10.0
			c.draw_line(w * T + Vector2(cos(a), sin(a)) * 0.34 * T, w * T + Vector2(cos(a), sin(a)) * 0.52 * T, INK, 1.5)
		c.draw_circle(w * T, 0.34 * T, Color(0.1, 0.18, 0.28))
		c.draw_circle(w * T + Vector2(-5, -4), 0.12 * T, Color(0.3, 0.5, 0.7, 0.7))
		_r(c, w.x + 0.3, w.y - 0.55, 0.2, 0.2, METAL_D)    # the pump body
		_r(c, w.x + 0.32, w.y - 0.95, 0.16, 0.45, METAL)
		_ln(c, Vector2(w.x + 0.4, w.y - 0.92), Vector2(w.x - 0.1, w.y - 1.12), METAL_D, 3.0)    # the handle
		_ln(c, Vector2(w.x + 0.48, w.y - 0.6), Vector2(w.x + 0.8, w.y - 0.45), METAL, 3.0)    # the spout
		_r(c, w.x + 0.7, w.y - 0.28, 0.3, 0.3, Color(0.55, 0.57, 0.6))    # the bucket
		c.draw_rect(Rect2(Vector2(w.x + 0.7, w.y - 0.28) * T, Vector2(0.3, 0.07) * T), WATER)
	if tier >= 3:    # the electric pump house, a pipe to the well and one to the garden
		_ln(c, Vector2(78.2, 26.7), Vector2(79.6, 26.7), Color(0.6, 0.62, 0.66), 4.0)
		_ln(c, Vector2(74.9, 26.9), Vector2(79.6, 26.9), Color(0.6, 0.62, 0.66), 4.0)
		_ln(c, Vector2(74.9, 26.9), Vector2(74.9, 28.4), Color(0.6, 0.62, 0.66), 4.0)
		_shadow(c, 79.6, 25.4, 2.2, 1.7)
		_r(c, 79.6, 25.4, 2.2, 1.7, Color(0.62, 0.36, 0.3))
		for k in range(1, 4):
			c.draw_line(Vector2(79.6, 25.4 + float(k) * 0.42) * T, Vector2(81.8, 25.4 + float(k) * 0.42) * T, Color(0.45, 0.25, 0.2), 1.5)
		_r(c, 80.4, 26.1, 0.5, 1.0, Color(0.3, 0.3, 0.34))
		# the tower's legs and ladder (the tank is in the top layer)
		for x in [87.45, 88.75]:
			_ln(c, Vector2(x, 26.5), Vector2(x, 24.4), WOOD_D, 3.0)
		_ln(c, Vector2(87.45, 26.0), Vector2(88.75, 25.0), METAL_D, 2.0)
		_ln(c, Vector2(88.75, 26.0), Vector2(87.45, 25.0), METAL_D, 2.0)
		_r(c, 87.3, 26.4, 1.6, 0.25, METAL_D)


func _bed(c: CanvasItem, b: Dictionary, tier: int) -> void:
	var p: Vector2 = b.c
	var stage := _crop(b)
	_r(c, p.x - 1.15, p.y - 0.64, 2.3, 1.28, WOOD, true, 2.5)
	_r(c, p.x - 1.02, p.y - 0.5, 2.04, 1.0, Color(0.28, 0.2, 0.13), false)
	if stage == 0:
		for k in 5:
			c.draw_line(Vector2(p.x - 0.8 + float(k) * 0.4, p.y - 0.3) * T, Vector2(p.x - 0.8 + float(k) * 0.4, p.y + 0.3) * T, Color(0.2, 0.14, 0.09), 1.5)
		return
	for k in 5:
		var q := Vector2(p.x - 0.72 + float(k) * 0.36, p.y + (0.12 if k % 2 == 0 else -0.12)) * T
		var gr := Color(0.4, 0.75, 0.3) if tier < 3 else Color(0.5, 0.85, 0.4)
		match stage:
			1:
				c.draw_line(q, q + Vector2(-3, -7), gr, 2.0)
				c.draw_line(q, q + Vector2(3, -8), gr, 2.0)
			2:
				c.draw_circle(q + Vector2(0, -5), 7.0, INK)
				c.draw_circle(q + Vector2(0, -5), 5.5, gr)
				c.draw_circle(q + Vector2(-2, -7), 2.5, gr.lightened(0.25))
			3:
				c.draw_circle(q + Vector2(0, -6), 8.0, INK)
				c.draw_circle(q + Vector2(0, -6), 6.5, Color(0.3, 0.6, 0.25))
				var fruit: Color = [Color(0.9, 0.2, 0.15), Color(0.7, 0.9, 0.4), Color(0.95, 0.55, 0.15)][int(b.kind)]
				c.draw_circle(q + Vector2(-3, -4), 3.2, fruit)
				c.draw_circle(q + Vector2(3, -8), 3.2, fruit)
				c.draw_circle(q + Vector2(2, -2), 2.8, fruit)


func _garden(c: CanvasItem, tier: int) -> void:
	if tier < 1:
		return
	if tier >= 2:    # irrigation: a tank, a manifold and a pipe between every two rows with drip points
		var pc := Color(0.35, 0.55, 0.75)
		for y in [33.0, 37.0, 41.0, 45.0]:
			_ln(c, Vector2(64.8, y), Vector2(85.3, y), pc, 2.5)
			var x := 66.0
			while x < 85.0:
				c.draw_circle(Vector2(x, y + 0.08) * T, 2.2, Color(0.6, 0.85, 1.0))
				x += 1.5
		_ln(c, Vector2(64.8, 29.9), Vector2(64.8, 45.2), pc, 3.5)
		_shadow(c, 64.2, 28.9, 1.2, 1.0)
		_r(c, 64.2, 28.9, 1.2, 1.0, Color(0.7, 0.8, 0.85))
		c.draw_rect(Rect2(Vector2(64.3, 29.0) * T, Vector2(1.0, 0.38) * T), WATER)
		for k in 3:
			c.draw_line(Vector2(64.2, 29.0 + 0.3 * float(k + 1)) * T, Vector2(65.4, 29.0 + 0.3 * float(k + 1)) * T, INK, 1.5)


func _kitchen(c: CanvasItem, tier: int) -> void:
	if tier >= 1:    # a cast iron range in the counter row, its chimney is in the top layer
		_shadow(c, 80.0, 9.0, 2.0, 1.1)
		_r(c, 80.0, 9.0, 2.0, 1.1, Color(0.2, 0.2, 0.23))
		_r(c, 80.0, 9.0, 2.0, 0.22, METAL_D)
		for k in 4:
			_disc(c, Vector2(80.3 + float(k % 2) * 0.9, 9.45 + float(k / 2) * 0.35), 0.15, Color(0.1, 0.1, 0.12))
		_disc(c, Vector2(80.6, 9.55), 0.2, Color(0.55, 0.57, 0.6))    # a pot
		_r(c, 81.3, 9.9, 0.45, 0.15, Color(0.85, 0.5, 0.2), false)    # the oven door's glow
	if tier >= 2:    # the larder: shelves with jars and sacks, crates stacked in the corner
		for y in [14.0, 16.2, 18.4]:
			_r(c, 84.7, y, 1.15, 1.9, WOOD_D)
			for sh in 3:
				c.draw_line(Vector2(84.7, y + 0.35 + 0.5 * float(sh)) * T, Vector2(85.85, y + 0.35 + 0.5 * float(sh)) * T, INK, 2.0)
				for j in 3:
					var jc: Color = [Color(0.8, 0.3, 0.2), Color(0.85, 0.75, 0.3), Color(0.5, 0.7, 0.3)][(j + sh + int(y)) % 3]
					c.draw_rect(Rect2(Vector2(84.8 + 0.34 * float(j), y + 0.12 + 0.5 * float(sh)) * T, Vector2(0.22, 0.28) * T), jc)
		for p in [Vector2(83.2, 20.5), Vector2(84.2, 20.5), Vector2(83.7, 19.7)]:
			_r(c, p.x - 0.4, p.y - 0.4, 0.8, 0.8, WOOD_L)
			c.draw_line(Vector2(p.x - 0.4, p.y) * T, Vector2(p.x + 0.4, p.y) * T, WOOD_D, 2.0)
		_r(c, 82.0, 20.1, 0.6, 0.7, Color(0.78, 0.7, 0.5))    # a sack
	if tier >= 3:    # benches along every table, lamps (their glow is in the glow list)
		for t in TABLES:
			var tp: Vector2 = t
			for s in [-0.95, 0.95]:
				_r(c, tp.x - 1.1, tp.y + s - 0.17, 2.2, 0.34, WOOD_L)
			_r(c, tp.x - 0.3, tp.y - 0.12, 0.6, 0.24, Color(0.9, 0.9, 0.85), false)    # a plate and a mug
			_disc(c, tp + Vector2(0.55, 0.0), 0.08, Color(0.8, 0.4, 0.3))


func _infirmary(c: CanvasItem, tier: int) -> void:
	if tier >= 1:    # two more cots against the east wall and a folding screen
		for y in [33.8, 36.9]:
			_r(c, 22.7, y, 1.1, 2.1, METAL_D)
			_r(c, 22.8, y + 0.1, 0.9, 1.9, Color(0.88, 0.88, 0.85), false)
			_r(c, 22.8, y + 0.7, 0.9, 1.3, Color(0.35, 0.55, 0.65), false)
			_r(c, 22.9, y + 0.15, 0.7, 0.4, Color(0.95, 0.95, 0.92), false)
			c.draw_rect(Rect2(Vector2(22.8, y + 0.1) * T, Vector2(0.9, 1.9) * T), INK, false, 1.5)
		for k in 3:
			_r(c, 21.3 + 0.0, 35.4 + 0.22 * float(k) - 0.35, 0.12, 0.55, Color(0.82, 0.85, 0.8))
		_r(c, 21.3, 35.1, 0.15, 1.25, Color(0.85, 0.88, 0.82))
	if tier >= 2:    # a medicine cabinet on the north wall and a workbench with vials
		_r(c, 22.2, 29.6, 1.3, 0.8, Color(0.9, 0.9, 0.88))
		c.draw_rect(Rect2(Vector2(22.55, 29.7) * T, Vector2(0.6, 0.6) * T), Color(0.8, 0.15, 0.15))
		c.draw_rect(Rect2(Vector2(22.7, 29.9) * T, Vector2(0.3, 0.2) * T), Color(1, 1, 1))
		_r(c, 15.8, 40.0, 2.8, 0.8, WOOD)
		for k in 5:
			var vc: Color = [Color(0.8, 0.3, 0.3), Color(0.3, 0.7, 0.8), Color(0.85, 0.8, 0.3)][k % 3]
			c.draw_rect(Rect2(Vector2(16.0 + 0.5 * float(k), 40.1) * T, Vector2(0.18, 0.36) * T), vc)
			c.draw_rect(Rect2(Vector2(16.0 + 0.5 * float(k), 40.1) * T, Vector2(0.18, 0.36) * T), INK, false, 1.0)
	if tier >= 3:    # a surgery table under a lamp
		_shadow(c, 18.3, 34.6, 1.8, 1.0)
		_r(c, 18.3, 34.6, 1.8, 1.0, Color(0.78, 0.82, 0.85))
		c.draw_rect(Rect2(Vector2(18.5, 34.8) * T, Vector2(1.4, 0.6) * T), Color(0.55, 0.78, 0.8))
		_r(c, 20.4, 34.7, 0.4, 0.7, METAL)    # a tray
		for k in 3:
			c.draw_line(Vector2(20.5, 34.85 + 0.2 * float(k)) * T, Vector2(20.7, 34.85 + 0.2 * float(k)) * T, INK, 2.0)


func _bunk(c: CanvasItem, x: float, y: float, blanket: Color) -> void:
	_shadow(c, x - 0.8, y - 0.4, 1.6, 0.9)
	_r(c, x - 0.8, y - 0.4, 1.6, 0.85, WOOD_D)    # the lower frame
	_r(c, x - 0.74, y - 0.34, 1.48, 0.73, Color(0.9, 0.9, 0.85), false)
	_r(c, x - 0.74, y - 0.34, 0.4, 0.73, Color(0.95, 0.95, 0.92), false)
	_r(c, x - 0.34, y - 0.34, 1.08, 0.73, blanket, false)
	c.draw_rect(Rect2(Vector2(x - 0.74, y - 0.34) * T, Vector2(1.48, 0.73) * T), INK, false, 1.5)
	_r(c, x - 0.86, y - 0.5, 0.13, 0.95, Color(0.4, 0.4, 0.44), true, 1.5)    # posts and the upper frame's rail
	_r(c, x + 0.73, y - 0.5, 0.13, 0.95, Color(0.4, 0.4, 0.44), true, 1.5)
	_r(c, x + 0.92, y - 0.3, 0.55, 0.7, Color(0.45, 0.47, 0.5))    # a locker
	c.draw_line(Vector2(x + 1.2, y - 0.3) * T, Vector2(x + 1.2, y + 0.4) * T, INK, 1.5)


func _dorm(c: CanvasItem, tier: int) -> void:    # cell block A: the first two tiers
	var cols := [Color(0.3, 0.45, 0.65), Color(0.6, 0.3, 0.25), Color(0.4, 0.55, 0.35), Color(0.7, 0.6, 0.3)]
	var n := 0
	for t in range(1, tier + 1):
		for b in BUNKS[t]:
			_bunk(c, float(b[0]), float(b[1]), cols[n % cols.size()])
			n += 1


func _dorm_b(c: CanvasItem, tier: int) -> void:    # cell block B: the third tier
	if tier >= 3:
		var cols := [Color(0.5, 0.35, 0.55), Color(0.3, 0.55, 0.55), Color(0.55, 0.45, 0.3), Color(0.35, 0.5, 0.35)]
		for k in 4:
			_bunk(c, float(BUNKS[3][k][0]), float(BUNKS[3][k][1]), cols[k])


func _radio(c: CanvasItem, tier: int) -> void:
	if tier < 1:
		return
	_shadow(c, 57.8, 36.2, 1.8, 0.9)
	_r(c, 57.8, 36.2, 1.8, 0.9, WOOD)    # a desk with a set, a mic and a lamp
	_r(c, 58.0, 36.3, 0.75, 0.4, Color(0.25, 0.3, 0.25))
	for k in 3:
		c.draw_circle(Vector2(58.2 + 0.2 * float(k), 36.5) * T, 2.5, Color(0.9, 0.7, 0.3))
	_disc(c, Vector2(59.1, 36.5), 0.1, METAL_D)
	_ln(c, Vector2(59.3, 36.45), Vector2(59.4, 36.25), METAL, 2.0)
	_r(c, 58.0, 36.95, 0.7, 0.3, Color(0.35, 0.28, 0.2))    # a stool


## The scaffold or the stack of materials of a project in progress (the bar is in the fx layer).
func _scaffold(c: CanvasItem, id: String) -> void:
	var s: Dictionary = site_of(id)
	var a: Vector2 = s.anchor
	var sz: Vector2 = s.size
	var x0 := a.x - sz.x / 2.0
	var y0 := a.y - sz.y / 2.0
	_shadow(c, x0, y0, sz.x, sz.y)
	var n := maxi(2, int(sz.x / 1.3) + 1)
	for k in n:
		var x := x0 + sz.x * float(k) / float(n - 1)
		_ln(c, Vector2(x, y0), Vector2(x, y0 + sz.y), WOOD, 4.0)
	for yy in [y0, y0 + sz.y]:
		_ln(c, Vector2(x0, yy), Vector2(x0 + sz.x, yy), WOOD_L, 4.0)
	if sz.x > sz.y:
		_ln(c, Vector2(x0, y0 + sz.y), Vector2(x0 + sz.x * 0.4, y0), WOOD_D, 2.5)
	_r(c, x0 + 0.1, y0 + sz.y * 0.4, 0.5, 0.25, WOOD_L)    # planks and a bucket on the stack
	_r(c, x0 + 0.2, y0 + sz.y * 0.4 + 0.15, 0.5, 0.2, WOOD_D)
	_disc(c, Vector2(x0 + sz.x - 0.2, y0 + sz.y + 0.25), 0.14, Color(0.6, 0.55, 0.3))


func _paint_top(c: CanvasItem) -> void:
	var tw: int = econ.tier("water")
	if tw >= 3:    # the water tank on its legs, with a roof and a gauge
		_shadow(c, 87.2, 23.2, 1.8, 1.5)
		_r(c, 87.1, 22.4, 1.9, 1.7, Color(0.55, 0.6, 0.65), true, 3.0)
		c.draw_rect(Rect2(Vector2(87.1, 22.4) * T, Vector2(1.9, 0.35) * T), Color(0.4, 0.45, 0.5))
		for k in range(1, 4):
			c.draw_line(Vector2(87.1 + 0.475 * float(k), 22.75) * T, Vector2(87.1 + 0.475 * float(k), 24.1) * T, Color(0.35, 0.4, 0.45), 1.5)
		c.draw_arc(Vector2(88.05, 22.4) * T, 0.95 * T, PI, TAU, 14, INK, 3.0)
		_r(c, 87.9, 23.2, 0.28, 0.5, WATER, false)
	if econ.tier("garden") >= 3:    # the glass roof over the first two rows
		var g := Rect2(Vector2(65.0, 29.3) * T, Vector2(20.8, 7.6) * T)
		c.draw_rect(g, Color(0.7, 0.9, 0.95, 0.2))
		var k := 0.0
		while k <= 20.8:
			c.draw_line(Vector2(65.0 + k, 29.3) * T, Vector2(65.0 + k, 36.9) * T, Color(INK, 0.4), 2.0)
			k += 2.6
		c.draw_line(Vector2(65.0, 33.1) * T, Vector2(85.8, 33.1) * T, Color(INK, 0.5), 3.0)
		c.draw_rect(g, Color(INK, 0.7), false, 3.5)
		for i in 5:
			var gx := 65.4 + float(i) * 4.4
			c.draw_line(Vector2(gx, 29.6) * T, Vector2(gx + 0.9, 30.4) * T, Color(1, 1, 1, 0.55), 2.0)
	if econ.tier("kitchen") >= 1:    # the range's chimney pipe goes up through the wall
		_ln(c, Vector2(80.9, 9.0), Vector2(80.9, 7.7), METAL_D, 4.0)
		_r(c, 80.7, 7.5, 0.4, 0.2, METAL_D)
	if econ.tier("power") >= 1:    # floodlight poles on the fence line
		for p in POLES:
			var pp := Vector2(float(p[0]), float(p[1]))
			var out_v := Vector2(float(p[2]), float(p[3]))
			_ln(c, pp, pp - Vector2(0, 0.9), WOOD_D, 5.0)
			var head: Vector2 = pp - Vector2(0, 0.95) + out_v * 0.18
			_r(c, head.x - 0.2, head.y - 0.12, 0.4, 0.24, Color(0.25, 0.26, 0.28), true, 2.0)
			c.draw_rect(Rect2((head - Vector2(0.13, 0.05)) * T, Vector2(0.26, 0.1) * T), Color(1.0, 0.97, 0.8) if _lit() else Color(0.4, 0.4, 0.38))
	if econ.tier("radio") >= 1:    # the mast: a lattice, guy wires, a red light (the blink is in fx)
		var m := Vector2(61.9, 29.3)
		_shadow(c, m.x - 0.3, m.y - 0.2, 0.7, 0.4)
		_ln(c, m, m + Vector2(-0.3, -3.8), METAL, 3.5)
		_ln(c, m, m + Vector2(0.3, -3.8), METAL, 3.5)
		for k in 6:
			var yy := -0.5 - 0.6 * float(k)
			c.draw_line((m + Vector2(-0.28 + 0.08 * float(k) * 0.0 + 0.05 * float(k), yy)) * T, (m + Vector2(0.28 - 0.05 * float(k), yy - 0.3)) * T, INK, 1.5)
		_ln(c, m + Vector2(0, -3.8), m + Vector2(-1.4, 0.4), Color(0.55, 0.55, 0.58), 1.2)
		_ln(c, m + Vector2(0, -3.8), m + Vector2(1.4, 0.4), Color(0.55, 0.55, 0.58), 1.2)
		_ln(c, m + Vector2(-0.7, -3.4), m + Vector2(0.7, -3.4), METAL, 2.0)
	if econ.tier("infirmary") >= 3:    # the surgery lamp on its arm
		_ln(c, Vector2(19.2, 33.6), Vector2(19.2, 34.7), METAL, 3.0)
		_disc(c, Vector2(19.2, 35.0), 0.35, Color(0.85, 0.9, 0.92))
		_disc(c, Vector2(19.2, 35.0), 0.18, Color(1.0, 1.0, 0.9))
	if econ.tier("kitchen") >= 3:    # lamps hanging over the tables
		for t in TABLES:
			var tp: Vector2 = t
			_ln(c, tp + Vector2(0, -0.8), tp + Vector2(0, -0.2), INK, 1.5)
			_disc(c, tp + Vector2(0, -0.25), 0.2, Color(0.95, 0.8, 0.4))


## Floodlight cones, drawn by the game's glow layer (prison_game.gd `_draw_glow`) which is ABOVE the night tint: the warm white is added to the dark picture instead of being tinted blue by it.
func draw_cones(c: CanvasItem, cam: Vector2, zoom: float, vp: Vector2, n: float) -> void:
	if n <= 0.02 or econ.tier("power") < 1 or not _lit():
		return
	c.draw_set_transform(vp / 2.0 - cam * zoom, 0.0, Vector2.ONE * zoom / T)
	for t in game.base.towers:    # towers throw their cones outward too
		var lp: Vector2 = Tower.lamp_pos(t)
		var out_v: Vector2 = (lp / T - Vector2(48.0, 30.0)).normalized()
		_cone(c, lp, out_v, 8.0 * T, 0.5, n)
	for p in POLES:
		var pp := Vector2(float(p[0]), float(p[1]) - 0.95) * T
		_cone(c, pp, Vector2(float(p[2]), float(p[3])), 7.0 * T, 0.5, n)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _cone(c: CanvasItem, o: Vector2, d: Vector2, length: float, half: float, k: float) -> void:
	var l := o + d.rotated(-half) * length
	var r := o + d.rotated(half) * length
	var m := o + d * length * 1.05
	var warm := Color(1.0, 0.95, 0.8, 0.32 * k)
	var zero := Color(1.0, 0.95, 0.8, 0.0)
	c.draw_polygon(PackedVector2Array([o, l, m]), PackedColorArray([warm, zero, zero]))
	c.draw_polygon(PackedVector2Array([o, m, r]), PackedColorArray([warm, zero, zero]))
	c.draw_polygon(PackedVector2Array([o, o + d.rotated(-half * 0.45) * length * 0.8, o + d.rotated(half * 0.45) * length * 0.8]), PackedColorArray([Color(1, 1, 0.92, 0.16 * k), zero, zero]))


func _paint_fx(c: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	for id in econ.queue:    # progress bars over the scaffolds, grey when nobody works there
		var s: Dictionary = site_of(id)
		var f := clampf(float(econ.st[id].done) / float(econ.defs[id].labor), 0.0, 1.0)
		var worked := false
		for m in game.crew.members:
			if m.state == "work" and m.has("eat") and String((m.eat as Dictionary).get("build", "")) == id:
				worked = true
		var at: Vector2 = Vector2(s.anchor) * T + Vector2(0, -float(Vector2(s.size).y) * T * 0.5 - 20.0)
		c.draw_rect(Rect2(at + Vector2(-34, 0), Vector2(68, 10)), Color(0, 0, 0, 0.75))
		c.draw_rect(Rect2(at + Vector2(-32, 2), Vector2(64.0 * f, 6)), Color(0.95, 0.8, 0.3) if worked else Color(0.6, 0.6, 0.6))
		c.draw_string(font, at + Vector2(-130, -4), String(econ.defs[id].name), HORIZONTAL_ALIGNMENT_CENTER, 260, 14, Color(1, 1, 0.85, 0.95))
	if _lit():    # the generator shed: it shakes while it runs
		_shed(c, Vector2(sin(_clock * 53.0), cos(_clock * 61.0)) * 0.7, true)
	elif econ.tier("power") >= 1:
		_shed(c, Vector2.ZERO, false)
	if econ.tier("radio") >= 1:
		var on: bool = fposmod(_clock, 1.6) < 0.5 and _lit()
		c.draw_circle(Vector2(61.6, 25.5) * T, 4.5 if on else 3.0, Color(1.0, 0.2, 0.15) if on else Color(0.35, 0.1, 0.1))
	for q in puffs:
		var k: float = float(q.age) / float(q.life)
		var col: Color = q.col
		c.draw_circle(Vector2(q.p), float(q.r), Color(col, float(q.a) * (1.0 - k)))
	for q in sparks:
		var p: Vector2 = q.p
		c.draw_line(p, p - Vector2(q.v) * 0.025, Color(1.0, 0.85, 0.35), 2.0)
	for q in bursts:
		var k2: float = float(q.age) / 1.2
		var p2: Vector2 = q.p
		c.draw_arc(p2, 20.0 + 70.0 * k2, 0.0, TAU, 28, Color(1.0, 0.9, 0.4, 1.0 - k2), 4.0)
		for i in 8:
			var a := float(i) * TAU / 8.0 + 0.3
			c.draw_circle(p2 + Vector2(cos(a), sin(a)) * (14.0 + 90.0 * k2) - Vector2(0, 30.0 * k2), 4.0 * (1.0 - k2), Color(1.0, 0.95, 0.5, 1.0 - k2))


func _shed(c: CanvasItem, jit: Vector2, on: bool) -> void:
	var o := Vector2(25.0, 32.6) + jit / T
	_shadow(c, o.x, o.y, 2.0, 1.8)
	_r(c, o.x, o.y, 2.0, 1.8, Color(0.42, 0.45, 0.42) if on else Color(0.3, 0.32, 0.31))
	for k in range(1, 5):
		c.draw_line((o + Vector2(0.0, 0.36 * float(k))) * T, (o + Vector2(2.0, 0.36 * float(k))) * T, INK, 1.0)
	_r(c, o.x - 0.05, o.y - 0.12, 2.1, 0.3, Color(0.3, 0.32, 0.34))    # the roof edge
	_r(c, o.x + 1.35, o.y + 0.5, 0.5, 0.5, Color(1.0, 0.82, 0.4) if on else Color(0.12, 0.12, 0.14))    # the lit window
	_r(c, o.x + 0.15, o.y + 0.55, 0.55, 1.1, Color(0.22, 0.24, 0.26))    # the door
	_ln(c, o + Vector2(1.6, 0.0), o + Vector2(1.6, -0.55), METAL_D, 4.0)    # the exhaust pipe
	if not on:
		c.draw_line((o + Vector2(0.9, 0.2)) * T, (o + Vector2(1.5, 0.8)) * T, Color(0.8, 0.2, 0.15), 2.0)
		c.draw_line((o + Vector2(1.5, 0.2)) * T, (o + Vector2(0.9, 0.8)) * T, Color(0.8, 0.2, 0.15), 2.0)


# ------------------------------------------------------------------ props that block ------

## Shuts the tiles under every prop of a built tier (world grids, shots may still pass, the path finders of the people and of the dead) and the bunks of the dormitory tiers.
## Run at the start and at every `project_done`, so the path caches know a prop the moment it stands. Nothing is opened again: tiers are never lost.
func _block_props() -> void:
	var rects: Array = []
	for pr in PROPS:
		if econ.tier(String(pr[0])) >= int(pr[1]):
			rects.append(pr[2])
	for t in range(1, econ.tier("dormitory") + 1):
		for b in BUNKS[t]:
			rects.append(Rect2(float(b[0]) - 0.86, float(b[1]) - 0.5, 2.33, 0.95))
	if econ.tier("kitchen") >= 3:
		for t in TABLES:
			for sgn in [-1.0, 1.0]:
				rects.append(Rect2(Vector2(t).x - 1.1, Vector2(t).y + sgn * 0.95 - 0.17, 2.2, 0.34))
	var w = game.world
	var sim = game.run.sim
	for r in rects:
		var q: Rect2 = Rect2(r).grow(-0.15)
		for y in range(floori(q.position.y), floori(q.end.y) + 1):
			for x in range(floori(q.position.x), floori(q.end.x) + 1):
				var i: int = y * w.W + x
				if x < 0 or y < 0 or x >= w.W or y >= w.H or _blocked.has(i):
					continue
				_blocked[i] = true
				if w.solid_p[i] != 0:
					continue    # (a wall or a base prop is there already)
				w.solid_p[i] = 1
				w.solid_z[i] = 1
				if w.shot_low.size() == w.W * w.H:
					w.shot_low[i] = 1
				sim.path_p.set_solid(i, true)
				sim.path_z.set_solid(i, true)


# --------------------------------------------------------------------- the generator's hum ------

## A real loop: one second of 60 Hz and its harmonics with a 12 Hz chug (whole cycles, so the join is silent), looping in the stream resource, on an AudioStreamPlayer2D at the shed so the
## engine's own distance falloff does the fading (about 18 tiles). Plays only while the generator is lit (power built and fuel in the stores).
func _make_hum(w: Node) -> void:
	var rate := 22050
	var pcm := PackedByteArray()
	pcm.resize(rate * 2)
	for i in rate:
		var t := float(i) / float(rate)
		var v := (0.55 * sin(TAU * 60.0 * t) + 0.25 * sin(TAU * 120.0 * t) + 0.12 * sin(TAU * 180.0 * t) + 0.05 * sin(TAU * 301.0 * t)) * (0.75 + 0.25 * sin(TAU * 12.0 * t))
		pcm.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 14000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = pcm
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = rate
	hum = AudioStreamPlayer2D.new()
	hum.stream = st
	hum.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
	hum.volume_db = -24.0
	hum.max_distance = 18.0 * T
	hum.attenuation = 1.6
	hum.position = Vector2(26.0, 33.5) * T
	w.add_child(hum)


func _hum_update() -> void:
	if hum == null:
		return
	var on: bool = _lit() and game.phase == "managed" and not (game.sound != null and game.sound.muted)
	if on and not hum.playing:
		hum.play()
	elif not on and hum.playing:
		hum.stop()
