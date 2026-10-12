## EXPERIMENT (prison raids, step 4b): PEOPLE. A survivor sits in a raid building (about one raid in two, at most one), asks for help when Ruth is near, follows her after E, and joins the crew if she
## reaches the extraction ring with them alive AND the base has a free bed (`econ.beds()`); otherwise they are left outside. A new member gets the role the base lacks, a route of that role's work
## (the same stops the roster's own people walk), and a name and look from a pool of ten. Recruits are kept here (`recruits`) because the crew is rebuilt at every return to the base.
## When the economy fires `person_left` the person walks out of the gate (state "leaving" in the crew) and a banner says so.
## Pattern: the clear phase's ally follow rules (prison_game.gd `_allies`: slot beside Ruth, 18 tile catch-up, bites of 8 at the dead within 0.95 and `ally_chasers` so the dead go for them), reduced to one
## person who is not a crew member. Owned by prison_game.gd (`people`, `# RAIDS hook`). Data: assets/data/prison_raids.json (`survivor`, `people`, `roles`).
extends RefCounted

const PawnNode := preload("res://scripts/render/pawn_node.gd")
const Crew := preload("res://scripts/prison/prison_crew.gd")
const Base := preload("res://scripts/prison/prison_base.gd")
const Loot := preload("res://scripts/prison/prison_loot.gd")

var game
var recruits: Array = []    # crew definitions of the people found in raids (kept over the rebuilds of the base)
var s: Dictionary = {}    # this raid's survivor: {name, p, node, hp, state "wait"|"follow"|"lost", path, pi, repath, bite, at}
var _banner: Label
var _banner_t := 0.0
var _leaving: Array = []
var _t := 0.0
var _step := 0


func _init(g) -> void:
	game = g


func _c() -> Dictionary:
	return Loot.cfg()


# ------------------------------------------------------------------ the raid ------

## After the raid's stage is made: puts the survivor in a building, or nobody.
func begin_raid(t: Dictionary, seed_i: int) -> void:
	s = {}
	stage_flags()
	var sv: Dictionary = _c().survivor
	var forced: bool = game.args.has("survivor")
	if not forced and float(Loot._h(seed_i, 4242) % 1000) / 1000.0 >= float(sv.chance):
		return
	var entry: Vector2 = Vector2(t.entry.pos)
	var cands: Array = []
	for h in t.houses:
		if bool(h.get("main", true)) and not (h.rooms as Array).is_empty() and Vector2(Rect2(h.rect).get_center()).distance_to(entry) > 22.0:
			cands.append(h)
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return Loot._h(seed_i, int(a.id) + 31) < Loot._h(seed_i, int(b.id) + 31))
	var h: Dictionary = cands[0]
	var room: Dictionary = t.rooms[int((h.rooms as Array)[Loot._h(seed_i, 7) % (h.rooms as Array).size()]) ]
	var rr := Rect2(room.rect)
	var at := rr.get_center()
	var best := 1.0e9
	for y in range(int(rr.position.y), int(rr.end.y)):    # (the free tile nearest the middle of the room)
		for x in range(int(rr.position.x), int(rr.end.x)):
			if game.world.solid_p[y * game.world.W + x] == 0 and Vector2(x + 0.5, y + 0.5).distance_to(rr.get_center()) < best:
				best = Vector2(x + 0.5, y + 0.5).distance_to(rr.get_center())
				at = Vector2(x + 0.5, y + 0.5)
	var who := _pick(seed_i)
	var defs: Dictionary = {}
	for pd in game.data.people:
		defs[String(pd.id)] = pd
	var src: Dictionary = (defs[String(who.key)] as Dictionary).duplicate(true)
	src["id"] = "found_" + String(who.name).to_lower()
	src["name"] = String(who.name)
	src["unarmed"] = true
	var look: Dictionary = (src.look as Dictionary).duplicate(true)
	for k in who.look:
		look[k] = who.look[k]
	src["look"] = look
	src["station"] = ""
	src["post_id"] = ""
	var p = game.run.sim.make_person(src)
	p.player = false
	p.x = at.x
	p.y = at.y
	p.hp = 100.0
	p.moving = false
	p.work = "rest"
	var n := PawnNode.new()
	n.setup(p, false, game.data, String(who.key))
	n.unarmed = true
	game.entities.add_child(n)
	s = {"name": String(who.name), "who": who, "p": p, "node": n, "hp": float(sv.hp), "state": "wait", "path": [], "pi": 0, "repath": 0.0, "bite": 0.0, "at": at, "def": {"id": String(src.id), "name": String(who.name)}}
	_t = 0.0
	_step = 0
	var mode := String(game.args.get("survivor", ""))    # staging: near (Ruth beside them), run (the whole find-and-extract by script), nobed (the same with the base full)
	if mode == "nobed":
		game.econ.cfg.start["beds"] = game.econ.people()
	if mode == "near":
		game.run.avatar_p.x = at.x
		game.run.avatar_p.y = at.y + 1.8
	if game.args.has("log"):
		print("SURVIVOR ", who.name, " at ", at)


## The first of the pool (from a hash of the seed) whose name is not in the crew or among the recruits.
func _pick(seed_i: int) -> Dictionary:
	var pool: Array = _c().people
	var used: Array = []
	for r in recruits:
		used.append(String(r.name))
	if game.crew != null:
		for m in game.crew.members:
			used.append(String(m.def.name))
	for i in pool.size():
		var cand: Dictionary = pool[(Loot._h(seed_i, 99) + i) % pool.size()]
		if not used.has(String(cand.name)):
			return cand
	return pool[Loot._h(seed_i, 99) % pool.size()]


func stage_flags() -> void:
	if game.args.has("mapview"):    # staging: the overview (M) from the start
		game.map_view = true
		game.zoom_px = 6.0
	if game.args.has("carry"):    # staging: parts and fuel in the pack (the bank check)
		game.pack.grid.cells.clear()
		var Inv := preload("res://scripts/sim/inventory.gd")
		Inv.auto_add(game.pack.grid, "parts_box", 5)
		Inv.auto_add(game.pack.grid, "fuel_can", 2)


func has_survivor() -> bool:
	return not s.is_empty() and String(s.state) != "lost"


func _me() -> Vector2:
	return Vector2(game.run.avatar_p.x, game.run.avatar_p.y)


## The E prompt near a waiting survivor ({} otherwise).
func prompt() -> Dictionary:
	if s.is_empty() or String(s.state) != "wait" or Vector2(s.p.x, s.p.y).distance_to(_me()) > float(_c().survivor.talk_r):
		return {}
	var free: int = int(game.econ.beds().free)
	return {"kind": "survivor", "label": "E: ask %s to come with you%s" % [String(s.name), "" if free > 0 else "  (no free bed at the base!)"]}


func talk() -> void:
	s.state = "follow"
	s.p.work = ""
	game._say("%s: I'm coming with you. Get me to the pickup." % String(s.name), 4.0)


func update(dt: float) -> void:
	if s.is_empty() or String(s.state) == "lost":
		return
	var p = s.p
	var at := Vector2(p.x, p.y)
	var me := _me()
	game.ally_chasers.clear()
	var mode := String(game.args.get("survivor", ""))
	if mode == "run" or mode == "nobed":
		_t += dt
		if _step == 0 and _t > 1.5 and String(s.state) == "wait":
			game.run.avatar_p.x = at.x
			game.run.avatar_p.y = at.y + 1.8
			talk()
			_step = 1
		elif _step == 1 and _t > 3.0:
			var ex: Vector2 = game.exits[1]
			game.run.avatar_p.x = ex.x
			game.run.avatar_p.y = ex.y
			p.x = ex.x + 1.2
			p.y = ex.y
			_step = 2
	if String(s.state) == "wait":
		p.work_t = float(p.work_t) + dt
		return
	var sv: Dictionary = _c().survivor
	s.bite = float(s.bite) - dt
	s.repath = float(s.repath) - dt
	var biters := 0
	for z in game._awake_dead():
		var d := at.distance_to(Vector2(z.x, z.y))
		if d < game.BITE_R:
			biters += 1
		if z.state == "chase" and d < 8.0 and d < me.distance_to(Vector2(z.x, z.y)) - 0.5:
			game.ally_chasers[z] = {"p": p, "state": "ally"}
	if biters > 0 and float(s.bite) <= 0.0:
		s.bite = 0.9
		var dmg: float = game.BITE_DMG * float(mini(biters, 3))
		s.hp = float(s.hp) - dmg
		game.sound.play("bite", 0.5)
		if float(s.hp) <= 0.0:
			lose()
			return
	p.hp = float(s.hp)
	var slot := me + Vector2.from_angle(2.1) * 2.0
	var dist := at.distance_to(slot)
	if at.distance_to(me) > 18.0:
		p.x = me.x
		p.y = me.y
		s.path = []
	elif dist > 1.1:
		if float(s.repath) <= 0.0:
			s.repath = 0.4
			s.path = game.run.sim.path_p.find(game.world.solid_p, p.x, p.y, slot.x, slot.y)
			if (s.path as Array).is_empty():
				s.path = game.run.sim.path_p.find(game.world.solid_p, p.x, p.y, me.x, me.y)
			s.pi = 0
		_walk(dt, float(sv.speed) * (1.5 if dist > 8.0 else 1.0))
	else:
		p.moving = false


func _walk(dt: float, speed: float) -> void:
	var p = s.p
	if int(s.pi) >= (s.path as Array).size():
		p.moving = false
		return
	var wp: Vector2 = s.path[s.pi]
	var to := wp - Vector2(p.x, p.y)
	var d := to.length()
	if d < 0.12:
		s.pi = int(s.pi) + 1
		return
	var step := minf(d, speed * dt)
	p.x += to.x / d * step
	p.y += to.y / d * step
	p.facing = game.run.sim.facing_of(to.x / d, to.y / d, p.facing)
	p.moving = true
	p.walk_phase += dt * 6.0 * speed / 1.7


func lose() -> void:
	banner("%s was lost." % String(s.name), Color(1, 0.55, 0.45))
	s.state = "lost"
	game.ally_chasers.clear()
	if is_instance_valid(s.node):
		s.node.queue_free()


## Raid world overlay (px): the marker over a waiting survivor, the bark, the health of a follower.
func paint(c: CanvasItem) -> void:
	if s.is_empty() or String(s.state) == "lost":
		return
	var font := ThemeDB.fallback_font
	var p = s.p
	var at := Vector2(p.x, p.y) * Loot.TILE
	var d := Vector2(p.x, p.y).distance_to(_me())
	var pulse := 0.5 + 0.5 * sin(game.clock * 4.0)
	if String(s.state) == "wait":
		c.draw_arc(at, 1.1 * Loot.TILE, 0, TAU, 28, Color(1, 0.85, 0.3, 0.9), 3.0)
		c.draw_circle(at, 1.1 * Loot.TILE, Color(1, 0.85, 0.3, 0.10 + 0.1 * pulse))
		c.draw_string(font, at - Vector2(30, 70.0 + 4.0 * pulse), "!", HORIZONTAL_ALIGNMENT_CENTER, 60, 30, Color(1, 0.85, 0.3))
		if d < float(_c().survivor.bark_r):
			c.draw_string(font, at - Vector2(100, 96), String(_c().survivor.bark), HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color(1, 1, 0.8))
	else:
		var f := clampf(float(s.hp) / float(_c().survivor.hp), 0.0, 1.0)
		c.draw_rect(Rect2(at + Vector2(-22, -78), Vector2(44, 5)), Color(0, 0, 0, 0.7))
		c.draw_rect(Rect2(at + Vector2(-22, -78), Vector2(44.0 * f, 5)), Color(0.4, 0.9, 0.5) if f > 0.35 else Color(0.95, 0.35, 0.3))
		c.draw_string(font, at - Vector2(60, 84), String(s.name), HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(1, 1, 0.85))


func mini(bars: Control, o: Vector2, sc: float) -> void:
	if s.is_empty() or String(s.state) == "lost":
		return
	if String(s.state) == "follow" or Vector2(s.p.x, s.p.y).distance_to(_me()) < 22.0:
		bars.draw_circle(o + Vector2(s.p.x, s.p.y) * sc, 2.6, Color(1, 0.85, 0.3))


# ------------------------------------------------------------------ extraction ------

## The pickup ring is reached (alive): decides whether the survivor joins. Returns the banner text ("" when there was nobody).
func settle(alive: bool) -> String:
	if s.is_empty() or not alive or String(s.state) != "follow":
		if not s.is_empty() and String(s.state) == "follow" and not alive:
			s = {}
		return ""
	var near := Vector2(s.p.x, s.p.y).distance_to(_me()) <= float(_c().survivor.join_r)
	var nm := String(s.name)
	var out := ""
	if not near:
		out = "%s was too far behind and is left outside." % nm
	elif int(game.econ.beds().free) <= 0:
		out = "No free bed: %s is left outside." % nm
	else:
		recruits.append(_make_recruit())
		out = "%s joins." % nm
	s = {}
	if game.args.has("log"):
		print("PEOPLE ", out, " recruits ", recruits.map(func(d): return "%s/%s" % [d.name, d.role]))
	return out


func _make_recruit() -> Dictionary:
	var c := _c()
	var count := {}
	for r in c.roles:
		count[r] = 0
	for m in game.econ.crew():
		if bool(m.ok) and count.has(String(m.role)):
			count[String(m.role)] = int(count[String(m.role)]) + 1
	var nd: Dictionary = game.econ.needs()
	var want := String(c.role_for_need.get(String(nd.get("res", "")), ""))
	var pick := ""
	var bs := 1.0e9
	for r in c.roles:
		var sc := float(count[r]) * 10.0 - (6.0 if r == want else 0.0)
		if sc < bs:
			bs = sc
			pick = String(r)
	var sample: String = c.roles[pick][0]
	var route: Array = []
	for r in Crew.ROSTER:
		if String(r.id) == sample:
			for stop in r.route:
				if not bool(stop.get("chat", false)):
					route.append((stop as Dictionary).duplicate(true))
	var who: Dictionary = s.who
	var id := "r_" + String(who.name).to_lower()
	game.econ.cfg.crew_role[id] = pick
	return {"id": id, "name": String(who.name), "role": String(c.roles[pick][1]), "key": String(who.key), "look": who.look, "route": route, "recruit": true}


## Back at the base: the recruits are crew again (called after the crew is made, before the nodes are).
func spawn_recruits() -> void:
	var i := 0
	for d in recruits:
		game.crew._make(d, Base.SPAWN + Vector2(2.0 + float(i) * 1.2, 1.5))
		game.econ.cfg.crew_role[String(d.id)] = _role_of(d)
		i += 1


func _role_of(d: Dictionary) -> String:
	for r in _c().roles:
		if String(_c().roles[r][1]) == String(d.role):
			return String(r)
	return ""


## Someone left the base or died there: a recruit is not brought back at the next return.
func forget(nm: String) -> void:
	recruits = recruits.filter(func(d): return String(d.name) != nm)


# ------------------------------------------------------------------ leaving, banner ------

## `person_left`: the person walks out of the gate. False when the crew is not in the scene (the caller removes them at once).
func walk_out(nm: String) -> bool:
	if game.crew == null:
		return false
	for m in game.crew.members:
		if String(m.def.name) == nm and String(m.state) != "leaving":
			m.state = "leaving"
			m.p.work = ""
			var to: Vector2 = Base.GATE_POS
			m.path = game.run.sim.path_p.find(game.world.solid_p, m.p.x, m.p.y, to.x, to.y)
			if (m.path as Array).is_empty():
				m.path = [to]
			m.pi = 0
			_leaving.append(m)
			banner("%s leaves the prison." % nm, Color(1, 0.7, 0.4))
			return true
	return false


func frame(dt: float) -> void:
	if game.args.has("choice") and game.frames == 30 and game.mode == "base":    # staging: the gate's choice open
		game.loot.open_choice()
	if game.args.has("leave") and game.frames == 40 and game.mode == "base":    # staging: the economy fires person_left
		game.econ.person_left.emit(String(game.args.leave))
	for m in _leaving.duplicate():
		if game.crew == null or not game.crew.members.has(m):
			_leaving.erase(m)
		elif game.crew._advance(m, dt, 2.2) or Vector2(m.p.x, m.p.y).distance_to(Base.GATE_POS) < 1.2:
			_leaving.erase(m)
			forget(String(m.def.name))
			game._econ_remove(String(m.def.name))
	if _banner_t > 0.0:
		_banner_t -= dt
		_banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
		if _banner_t <= 0.0:
			_banner.visible = false


func banner(text: String, col: Color = Color(0.6, 1, 0.7), secs: float = 6.0) -> void:
	if _banner == null:
		_banner = Label.new()
		_banner.add_theme_font_size_override("font_size", 34)
		_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_banner.add_theme_constant_override("outline_size", 8)
		_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		game.hud.add_child(_banner)
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.size = Vector2(game._vp().x, 50)
	_banner.position = Vector2(0, 160)
	_banner.visible = true
	_banner.modulate.a = 1.0
	_banner_t = secs
