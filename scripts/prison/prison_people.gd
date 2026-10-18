## EXPERIMENT (prison raids, step 4b): PEOPLE. A survivor sits in a raid building (about one raid in two, at most one), asks for help when Ruth is near, follows her after E, and joins the crew if she
## reaches the extraction ring with them alive AND the base has a free bed (`econ.beds()`); otherwise they are left outside. A new member gets the role the base lacks, a route of that role's work
## (the same stops the roster's own people walk), and a name and look from a pool of ten. Recruits are kept here (`recruits`) because the crew is rebuilt at every return to the base.
## When the economy fires `person_left` the person walks out of the gate (state "leaving" in the crew) and a banner says so.
## Pattern: the clear phase's ally follow rules (prison_game.gd `_allies`: slot beside Ruth, 18 tile catch-up, bites of 8 at the dead within 0.95 and `ally_chasers` so the dead go for them), reduced to one
## person who is not a crew member. Owned by prison_game.gd (`people`, `# RAIDS hook`). Data: assets/data/prison_raids.json (`survivor`, `people`, `roles`).
extends RefCounted

const Access := preload("res://scripts/access.gd")
const Icons := preload("res://scripts/prison/prison_icons.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const Crew := preload("res://scripts/prison/prison_crew.gd")
const Base := preload("res://scripts/prison/prison_base.gd")
const Loot := preload("res://scripts/prison/prison_loot.gd")
const Bal := preload("res://scripts/prison/prison_bal.gd")

var game
var recruits: Array = []    # crew definitions of the people found in raids (kept over the rebuilds of the base)
var all: Array = []    # the survivors of this raid (fix round 3: more than one); `s` is the one a function works on now
var _cur = null
var rescued := 0    # how many people raids brought to the prison (the objective counts them)
var s: Dictionary = {}    # a survivor: {name, p, node, hp, state "wait"|"follow"|"lost", path, pi, repath, bite, at}
var _leaving: Array = []
var _t := 0.0
var _step := 0


func _init(g) -> void:
	game = g


func _c() -> Dictionary:
	return Loot.cfg()


# ------------------------------------------------------------------ the raid ------

## After the raid's stage is made: puts the survivors in buildings (one in most raids, two or three in later ones; fix round 3: this is the ONLY way people come to the prison).
func begin_raid(t: Dictionary, seed_i: int) -> void:
	s = {}
	all = []
	stage_flags()
	var sv: Dictionary = game.loot.survivor_cfg()    # (the base table with the town kind's changes)
	var n := 0
	if float(Loot._h(seed_i, 4242) % 1000) / 1000.0 < float(sv.first):
		n = 1
	for ex in sv.extra:
		if game.raids >= int(ex[0]) and float(Loot._h(seed_i, 4243 + int(ex[0])) % 1000) / 1000.0 < float(ex[1]):
			n += 1
	n = mini(n, int(sv.max))
	if game.args.has("survivor") or game.raids <= 1:    # (the first raid always has somebody: Hal, see _pick)
		n = maxi(n, 1)
	var entry: Vector2 = Vector2(t.entry.pos)
	var cands: Array = []
	for h in t.houses:
		if bool(h.get("main", true)) and not (h.rooms as Array).is_empty() and Vector2(Rect2(h.rect).get_center()).distance_to(entry) > 22.0:
			cands.append(h)
	cands.sort_custom(func(a, b): return Loot._h(seed_i, int(a.id) + 31) < Loot._h(seed_i, int(b.id) + 31))
	for k in mini(n, cands.size()):
		all.append(_place_one(t, cands[k], seed_i + k * 977, k))
	if all.is_empty():
		return
	s = all[0]
	_t = 0.0
	_step = 0
	var mode := String(game.args.get("survivor", ""))    # staging: near (Ruth beside them), run (the whole find-and-extract by script), nobed (the same with the base full)
	if mode == "nobed":
		game.econ.cfg.start["beds"] = game.econ.people()
	if mode == "near":
		game.run.avatar_p.x = s.at.x
		game.run.avatar_p.y = s.at.y + 1.8
	if game.args.has("log"):
		print("SURVIVORS ", all.map(func(e): return "%s/%s%s%s at %s" % [e.name, e.who.skill, " hurt" if e.hurt else "", " locked" if e.locked else "", e.at]))


## One survivor in a room of house `h`: {name, who, p, node, hp, state, ..., hurt (needs a med), locked (shut in: hold E, with dead around)}.
func _place_one(t: Dictionary, h: Dictionary, seed_i: int, k: int) -> Dictionary:
	var sv: Dictionary = game.loot.survivor_cfg()
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
	src["unarmed"] = false    # a found survivor carries a rifle and shoots like the clear phase allies
	var look: Dictionary = (src.look as Dictionary).duplicate(true)
	for kk in who.look:
		look[kk] = who.look[kk]
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
	game.entities.add_child(n)
	var hurt := float(Loot._h(seed_i, 5151) % 1000) / 1000.0 < float(sv.hurt)
	var locked := float(Loot._h(seed_i, 6161) % 1000) / 1000.0 < float(sv.locked) and not hurt
	if bool(sv.get("lock_first", false)) and k == 0:    # (a hospital: one locked ward)
		locked = true
		hurt = false
	if game.args.has("survivor") and k == 0:
		hurt = String(game.args.survivor) == "hurt"
		locked = String(game.args.survivor) == "locked"
	if locked:    # shut in with a few of the dead (the kill step), hold E to force the door
		for i in int(sv.lock_dead):
			game.run.field.add_record(at + Vector2.from_angle(float(i) * 2.4 + 0.7) * 2.0, "walker", true)
	return {"name": String(who.name), "who": who, "p": p, "node": n, "hp": float(sv.hurt_hp) if hurt else float(sv.hp), "state": "wait", "path": [], "pi": 0, "repath": 0.0, "bite": 0.0, "at": at, "hurt": hurt, "locked": locked,
		"lock_t": 0.0, "def": {"id": String(src.id), "name": String(who.name)}}


## The first of the pool (the "early" ones in order, then from a hash of the seed) whose name is not in the crew or among the recruits.
func _used() -> Array:
	var used: Array = game.econ_gone.duplicate()
	for e in all:
		used.append(String(e.name))
	for r in recruits:
		used.append(String(r.name))
	if game.crew != null:
		for m in game.crew.members:
			used.append(String(m.def.name))
	return used


func _pick(seed_i: int) -> Dictionary:
	var pool: Array = _c().people
	var used := _used()
	for cand in pool:    # (playtest 6: Hal, then Wren, the two who walked in with Ruth in playtest 5, are the first a raid finds; one not brought home is there again on the next raid)
		if bool(cand.get("early", false)) and not used.has(String(cand.name)):
			return cand
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
	for e in all:
		if String(e.state) != "lost":
			return true
	return false


func _me() -> Vector2:
	return Vector2(game.run.avatar_p.x, game.run.avatar_p.y)


## The E prompt near a waiting survivor ({} otherwise).
func prompt() -> Dictionary:
	for e in all:
		s = e
		if String(s.state) != "wait" or Vector2(s.p.x, s.p.y).distance_to(_me()) > float(_c().survivor.talk_r):
			continue
		_cur = e
		if bool(s.locked):
			return {"kind": "survivor_locked", "label": "Hold E: force the door to %s (%d%%)" % [String(s.name), int(100.0 * float(s.lock_t) / float(_c().survivor.lock_secs))]}
		var free: int = int(game.econ.beds().free)
		var tt: String = game.arc.events.trait_text(String(s.name))    # TRAITS: who they are, before the player asks
		var lbl := "E: ask %s (%s%s) to come with you%s" % [String(s.name), String(s.who.skill), "; " + tt if tt != "" else "", "" if free > 0 else "  (no free bed at the base!)"]
		if bool(s.hurt):
			lbl = "E: give %s a med (they are hurt)" % String(s.name)
		return {"kind": "survivor", "label": lbl}
	return {}


func talk() -> void:
	if _cur != null:
		s = _cur
	if bool(s.hurt):
		var inv = game.pack.inv
		if inv == null or inv.take_float("meds", 1.0) < 0.999:
			game._say("%s is hurt and needs a med. You have none." % String(s.name), 3.0)
			return
		s.hurt = false
		s.hp = float(_c().survivor.hp) * 0.6
		game._say("%s takes the med and gets up." % String(s.name), 3.0)
		return
	s.state = "follow"
	s.p.work = ""
	game.squad.add_found(s)    # SQUAD hook: a found survivor is a member of the squad (orders, bag, nameplate)
	var bio: String = game.arc.events.bio_of(String(s.name))
	game._say("%s: I'm coming with you. Get me to the pickup. (C: orders)%s" % [String(s.name), ("\n" + bio) if bio != "" else ""], 5.0)


func update(dt: float) -> void:
	game.ally_chasers.clear()
	for e in all:
		s = e
		_update1(dt)


func _update1(dt: float) -> void:
	if s.is_empty() or String(s.state) == "lost":
		return
	var p = s.p
	var at := Vector2(p.x, p.y)
	var me := _me()
	var mode := String(game.args.get("survivor", ""))
	if mode == "bite":    # staging: follows, then two dead are put on them (the lost path)
		_t += dt
		if _step == 0 and _t > 1.0 and String(s.state) == "wait":
			game.run.avatar_p.x = at.x
			game.run.avatar_p.y = at.y + 1.8
			talk()
			_step = 1
		elif _step == 1 and _t > 4.0:
			var n := 0
			for z in game.run.sim.zombies:
				if n < 3 and z.state != "dead" and z.state != "dying":
					z.x = at.x + 0.3
					z.y = at.y
					z.state = "chase"
					n += 1
			_step = 2
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
		if bool(s.locked):    # hold E beside the door: it gives way after lock_secs
			var near := at.distance_to(me) <= float(_c().survivor.talk_r) and Input.is_key_pressed(KEY_E)
			s.lock_t = maxf(0.0, float(s.lock_t) + (dt if near or mode == "locked" else -dt * 2.0))
			if float(s.lock_t) >= float(_c().survivor.lock_secs):
				s.locked = false
				game._say("The door gives way. %s is free." % String(s.name), 3.0)
		return
	if game.squad.drives(s):
		return    # SQUAD hook: follow, shooting, bites and the orders are the squad's
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
	# the pose ticks (the crew's are in prison_game.gd `_gun_poses`) and the shot: nearest dead in sight within 8 tiles
	game.turn_aim(p, dt)
	p.recoil = maxf(0.0, float(p.recoil) - dt * 8.0)
	p.reloading = maxf(0.0, float(p.reloading) - dt)
	var hold := float(game.aim_hold.get(p.id, 0.0)) - dt
	game.aim_hold[p.id] = hold
	if hold <= 0.0 and p.target != null:
		p.target = null
	s.cd = float(s.get("cd", 0.0)) - dt
	if float(s.cd) <= 0.0 and float(p.reloading) <= 0.0:
		var best = null
		var bd := 8.0
		for z in game._awake_dead():
			var dz := at.distance_to(Vector2(z.x, z.y))
			if dz < bd and game.targetable(z) and game.focus_free(p, z, "ally") and game.run.sim.clear_shot(at, Vector2(z.x, z.y), 0.15):
				bd = dz
				best = z
		if best != null and game.can_fire(p, best, "ally"):
			game._shoot_at(p, best, game.gun_hit("ally", bd, best), float(Bal.role("ally").dmg))
			s.cd = Bal.roll(Bal.role("ally"), "cd")
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
	banner("%s is gone." % String(s.name), Color(1, 0.55, 0.45))
	if game.args.has("log"):
		print("PEOPLE ", s.name, " is gone (bitten to zero)")
	s.state = "lost"
	game.ally_chasers.clear()
	if is_instance_valid(s.node):
		s.node.queue_free()


## Raid world overlay (px): the marker over a waiting survivor, the bark, the health of a follower.
func paint(c: CanvasItem) -> void:
	for e in all:
		s = e
		_paint1(c)


func _paint1(c: CanvasItem) -> void:
	if s.is_empty() or String(s.state) == "lost" or (String(s.state) != "wait" and game.squad.drives(s)):
		return
	var font := ThemeDB.fallback_font
	var p = s.p
	var at := Vector2(p.x, p.y) * Loot.TILE
	var d := Vector2(p.x, p.y).distance_to(_me())
	var pulse := 0.5 + 0.5 * sin(game.clock * 4.0)
	if String(s.state) == "wait":
		c.draw_arc(at, 1.1 * Loot.TILE, 0, TAU, 28, Color(1, 0.85, 0.3, 0.9), 3.0)
		c.draw_circle(at, 1.1 * Loot.TILE, Color(1, 0.85, 0.3, 0.10 + 0.1 * pulse))
		c.draw_string(font, at - Vector2(60, 70.0 + 4.0 * pulse), "HELP!", HORIZONTAL_ALIGNMENT_CENTER, 120, 30, Color(1, 0.85, 0.3))
		var tag := "%s%s%s" % [String(s.who.skill), ", hurt" if s.hurt else "", ", locked in" if s.locked else ""]
		c.draw_string(font, at - Vector2(100, 112), tag if d < float(_c().survivor.bark_r) else "", HORIZONTAL_ALIGNMENT_CENTER, 200, 16, Color(1, 1, 0.8))
	else:
		var f := clampf(float(s.hp) / float(_c().survivor.hp), 0.0, 1.0)
		c.draw_rect(Rect2(at + Vector2(-22, -78), Vector2(44, 5)), Color(0, 0, 0, 0.7))
		c.draw_rect(Rect2(at + Vector2(-22, -78), Vector2(44.0 * f, 5)), Color(0.4, 0.9, 0.5) if f > 0.35 else Color(0.95, 0.35, 0.3))
		c.draw_string(font, at - Vector2(60, 84), String(s.name), HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(1, 1, 0.85))


func mini(bars: Control, o: Vector2, sc: float) -> void:
	for e in all:
		s = e
		_mini1(bars, o, sc)


func _mini1(bars: Control, o: Vector2, sc: float) -> void:
	if s.is_empty() or String(s.state) == "lost" or (String(s.state) != "wait" and game.squad.drives(s)):
		return
	if String(s.state) == "follow" or String(s.state) == "wait":    # (a waiting one shows on the map all the time: the "Help!" marker)
		if Access.markers():
			Icons.mark(bars, "ally", o + Vector2(s.p.x, s.p.y) * sc, 3.6, Color(1, 0.85, 0.3))
		else:
			bars.draw_circle(o + Vector2(s.p.x, s.p.y) * sc, 2.6, Color(1, 0.85, 0.3))


# ------------------------------------------------------------------ extraction ------

## The pickup ring is reached (alive): decides whether the survivor joins. Returns the banner text ("" when there was nobody).
func settle(alive: bool) -> String:
	var outs: Array = []
	for e in all:
		s = e
		var o := _settle1(alive)
		if o != "":
			outs.append(o)
	s = {}
	all = []
	return "\n".join(outs)


func _settle1(alive: bool) -> String:
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
		var rc := _make_recruit(s.who)
		recruits.append(rc)
		rescued += 1
		out = "%s joins as %s.%s" % [nm, String(rc.role), (" " + game.arc.events.trait_text(nm) + ".") if game.arc.events.trait_text(nm) != "" else ""]
	s = {}
	if game.args.has("log"):
		print("PEOPLE ", out, " recruits ", recruits.map(func(d): return "%s/%s" % [d.name, d.role]))
	return out


func _make_recruit(who: Dictionary) -> Dictionary:
	var c := _c()
	var count := {}
	for r in c.roles:
		count[r] = 0
	for m in game.econ.crew():
		if bool(m.ok) and count.has(String(m.role)):
			count[String(m.role)] = int(count[String(m.role)]) + 1
	var nd: Dictionary = game.econ.needs()
	var want := String(c.role_for_need.get(String(nd.get("res", "")), ""))
	var pick := String(who.get("skill", ""))    # (what they can do: a cook cooks; a person without a skill takes the role the base lacks)
	if not c.roles.has(pick):
		var bs := 1.0e9
		for r in c.roles:
			var sc := float(count[r]) * 10.0 - (6.0 if r == want else 0.0)
			if sc < bs:
				bs = sc
				pick = String(r)
	var sample: String = c.roles[pick][0]
	var route: Array = []
	for r in Crew.ROSTER:
		if String(r.id) == sample and r.has("route"):
			for stop in r.route:
				if not bool(stop.get("chat", false)):
					route.append((stop as Dictionary).duplicate(true))
	var id := String(who.get("id", "r_" + String(who.name).to_lower()))    # (Hal and Wren keep their own ids: their weapon tags and portraits)
	game.econ.cfg.crew_role[id] = pick
	return {"id": id, "name": String(who.name), "role": String(c.roles[pick][1]), "key": String(who.key), "look": who.look, "route": route, "recruit": true, "arrive": true}


## Back at the base: the recruits are crew again (called after the crew is made, before the nodes are).
func spawn_recruits() -> void:
	var i := 0
	for d in recruits:
		_spawn_one(d, i)
		i += 1


func _spawn_one(d: Dictionary, i: int) -> Dictionary:
	var at := Base.SPAWN + Vector2(2.0 + float(i) * 1.2, 1.5)
	if bool(d.get("arrive", false)):    # a new one walks in through the gate
		at = Base.GATE_POS + Vector2(float(i % 3) * 0.9 - 0.9, -0.9)
		d.erase("arrive")
	var m: Dictionary = game.crew._make(d, at)
	if _role_of(d) == "guard":
		if game.crew.free_post() == "":
			d["role"] = "Hauler"    # (all six towers are manned)
			d["route"] = game.crew.route_for("hauler")
			game.econ.cfg.crew_role[String(d.id)] = "hauler"
			m.def = d
		else:
			game.crew._apply_role(m, "guard", true)
	game.econ.native_roles[String(d.id)] = _role_of(d)
	if not game.econ.cfg.crew_role.has(String(d.id)):    # (a role set in the roster stays over the raids)
		game.econ.cfg.crew_role[String(d.id)] = _role_of(d)
	return m


## `--econ-lab`: one rescue as if a raid had brought somebody (the next of the pool, a free bed needed): the person is in the crew at once. Returns the name, "" when there is no bed.
func lab_rescue(seed_i: int) -> String:
	if int(game.econ.beds().free) <= 0:
		return ""
	var who := _pick(seed_i)
	for role in ["gardener", "medic", "cook", "mechanic", "hauler"]:    # (the lab's raids find the person the base lacks most)
		if game.econ.workers(role) == 0:
			for q in _c().people:
				if String(q.skill) == role and not _used().has(String(q.name)):
					who = q
					break
			break
	var rc := _make_recruit(who)
	recruits.append(rc)
	rescued += 1
	var m := _spawn_one(rc, recruits.size())
	if m.has("p") and game.entities != null and not m.has("node"):
		var n := PawnNode.new()
		n.setup(m.p, false, game.data, String(m.key))
		game.entities.add_child(n)
		m["node"] = n
	return "%s/%s" % [String(who.name), String(rc.role)]


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
	if game.args.has("role") and game.frames == 40 and game.mode == "base":    # staging: roster changes, e.g. --role=dez:gardener,marcus:guard
		for kv in String(game.args.role).split(","):
			var rr: Dictionary = game.crew.set_role(kv.get_slice(":", 0), kv.get_slice(":", 1), game.econ, game.siege.attacking)
			print("ROLE ", kv, " -> ", rr)
	for m in _leaving.duplicate():
		if game.crew == null or not game.crew.members.has(m):
			_leaving.erase(m)
		elif game.crew._advance(m, dt, 2.2) or Vector2(m.p.x, m.p.y).distance_to(Base.GATE_POS) < 1.2:
			_leaving.erase(m)
			forget(String(m.def.name))
			game._econ_remove(String(m.def.name))


## A join, a death, a person who left: a banner of the game's banner lane (queued under the top bar).
func banner(text: String, col: Color = Color(0.6, 1, 0.7), secs: float = 6.0) -> void:
	game._banner(text, "", secs, 30, col)


## SAVE hook (prison_save.gd): the people raids brought (the base's crew is rebuilt from these and the names in `econ_gone` at every return).
func to_dict() -> Dictionary:
	return {"recruits": recruits.duplicate(true), "rescued": rescued}


func from_dict(d: Dictionary) -> void:
	recruits = (d.get("recruits", []) as Array).duplicate(true)
	rescued = int(d.get("rescued", 0))
	for r in recruits:
		r.erase("arrive")    # (they were in the base when it was saved: nobody walks in through the gate)
