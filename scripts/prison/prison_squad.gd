## EXPERIMENT (prison companions, comp round): THE SQUAD. Up to two people of the base go out on a raid with Ruth, and so does the survivor found in one (prison_people.gd hands them over): the same members, the
## same orders, the same bag, the same rules at the pickup. Owned by prison_game.gd (`squad`, `# SQUAD hook`). Numbers: assets/data/prison_weapons.json `squad`.
##
## PATTERN (ai-navigation skill): the town's path finder (`sim.path_p`, a grid A*) and a small STATE MACHINE per member written as plain code in `_step` (the nodes of the skill's NavigationAgent2D need a baked
## NavigationRegion2D, and the town's walls, doors and props are in the sim's own solid grids, which the path finder already reads: a second navigation world beside it would disagree with it). The machine:
##   follow  walk to a slot beside Ruth, shoot what comes within `shoot_r`
##   hold    stay where they are, shoot
##   cover   a tight slot beside Ruth, shoot sooner and farther, never fall back
##   scavenge  pick the nearest house with something left (waits when more than `dead_wait` awake dead are within `dead_wait_r` of it), then container by container, room by room (nearest first, staying in a room
##           until it is done): walk to the container's stand spot, SEARCH for the container's own seconds (`SearchRules.search_secs`: the number Ruth's session reads) with the work pose "sort", put what is in it in
##           their own bag grid. The house is done, or the bag is full, or Ruth is more than `leash` tiles away: they go back to FOLLOW and say so.
##   spread  like follow, but a wider ring (`spread_r`) around Ruth
## SMARTER (raid feedback "the NPCs go alone and die"): `scavenge` means "scavenge here": only houses whose centre is within `scav_r` of Ruth and with no awake dead near them, and the order is kept while they are RECALLED
##   (any dead within `alarm_r`, or Ruth more than `leash` away: they walk back to her, and go on when it has been quiet for 3 s beside her). With `swarm_n` or more dead near, or under `retreat_hp`, they fall back to a slot
##   beside Ruth on the side away from the dead (so the dead go for Ruth, not them), shooting as they go; a dead one within `kite_r` is kited (they shoot on the move); a pike only charges a dead one within `melee_r` of Ruth.
##   fall back (not a command): below `retreat_hp` of their health they walk to Ruth whatever the order, and say so.   down: 20 s to be revived (hold E, one med from the pack), else gone.
## INVENTORY (inventory-system skill): the bag is a grid of the same data-driven inventory as the pack (scripts/sim/inventory.gd, w by h cells: 6 by 3 for a Scavenger, 4 by 2 for the rest), filled by the container's
## own grid (`sim.inv.grid_of`), emptied into the raid's stock at the pickup (`deposit_all`), and a gun in it goes to the weapon rack. Scrap is not an item: it is kept as a number in the member (`loose`).
## ONE-LINE RULES: a companion beyond `join_r` tiles of Ruth when the pickup is done is LEFT OUTSIDE (gone for good, the bag lost; the ring waits for them up to `wait_s` seconds and E in the ring leaves them);
## a downed one is lost the same way unless revived; Ruth's death brings the ones on their feet home with empty bags. The base loses their work while they are out (prison_econ.gd reads `out_ids`).
extends RefCounted

const Access := preload("res://scripts/access.gd")
const PIcons := preload("res://scripts/prison/prison_icons.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const Inventory := preload("res://scripts/sim/inventory.gd")
const SearchRules := preload("res://scripts/town/search.gd")
const TILE := 64.0
const Bal := preload("res://scripts/prison/prison_bal.gd")
const CMDS := ["follow", "hold", "scavenge", "cover", "quiet", "spread"]
const CMD_WORD := {"follow": "Stay close", "hold": "Hold", "scavenge": "Scavenge here", "cover": "Cover me", "quiet": "Quiet", "spread": "Spread out"}
const CMD_COL := {"follow": Color(0.55, 0.85, 1.0), "hold": Color(1.0, 0.8, 0.35), "scavenge": Color(0.55, 1.0, 0.6), "cover": Color(1.0, 0.55, 0.5), "quiet": Color(0.7, 0.7, 1.0), "spread": Color(0.85, 0.7, 1.0)}

var game
var cfg: Dictionary
var members: Array = []    # the companions out in this raid
var cands: Array = []    # what the gate could offer (a snapshot of the crew, taken before the base is torn down)
var picked: Array = []    # ids chosen at the gate
var floaters: Array = []    # {text, pos (tiles), t, col}
var revive_t := 0.0
var wait_t := 0.0    # seconds the pickup has waited for them
var left_behind := false    # E in the ring: the ones that are not here are left outside
var out: Array = []    # ids of the people who are out on this raid (the economy counts them as not at work)
var _panel: PanelContainer
var open := false
var _t := 0.0
var _test := {}
var stats := {"down": 0, "lost": 0}    # the measure of the raid bot (`--log` prints SQUADSTAT lines): companions downed and lost


func _init(g) -> void:
	game = g
	cfg = (load("res://scripts/prison/prison_arms.gd").cfg() as Dictionary).squad


# ---------------------------------------------------------------- who can go --------

## The people of the base who could go (a snapshot of `game.crew`, or of the roster when there is no base: a raid started by a flag). Each: {id, name, key, look, role (title), econ_role, tags, hp, gun, melee, bag
## (Vector2i), ok, why, def}. `why` says what keeps one at home.
func snapshot() -> Array:
	cands = []
	var by_id := {}
	var guards := 0
	if game.crew != null:
		for m in game.crew.members:
			if m.def.has("ally") or m.def.has("play"):
				continue
			by_id[String(m.def.id)] = m
	else:
		for r in game.Crew.ROSTER:
			if not r.has("play"):
				by_id[String(r.id)] = {"def": r, "state": "wait", "p": null}
	var roles: Dictionary = game.econ.cfg.crew_role
	for id in by_id:
		var m: Dictionary = by_id[id]
		var r: Dictionary = m.def
		var role := String(roles.get(id, "guard" if r.has("stand") else ""))
		if role == "guard":
			guards += 1
		var tags: Array = (cfg.tags as Dictionary).get(id, [])
		var fighter := tags.has("Fighter")
		var bag: Array = cfg.bag.get("Scavenger" if tags.has("Scavenger") else "default", cfg.bag.default)
		var gun_name := "unarmed"
		var melee := false
		var body: Dictionary = {}
		for pd in game.data.people:
			if String(pd.id) == String(r.key):
				body = pd
		if not body.is_empty():
			gun_name = String(game.data.weapons[String(body.weapon)].get("name", body.weapon))
			melee = bool(game.data.weapons[String(body.weapon)].get("melee", false))
		cands.append({"id": id, "name": String(r.name), "key": String(r.key), "look": r.get("look", {}), "role": String(r.get("role", "")), "econ_role": role, "tags": tags, "hp": float(cfg.fighter_hp if fighter else cfg.hp),
			"gun": gun_name, "melee": melee, "bag": Vector2i(int(bag[0]), int(bag[1])), "ok": true, "why": "", "def": r, "state": String(m.state)})
	for c in cands:
		var why := ""
		if game.phase != "managed":
			why = "the prison is not secured yet"
		elif game.siege != null and game.siege.attacking:
			why = "a night attack is on"
		elif String(c.state) == "down" or String(c.state) == "leaving":
			why = "hurt"
		elif String(c.econ_role) == "guard" and guards - 1 < 2:
			why = "two guards must stay on the towers"
		c["why"] = why
		c["ok"] = why == ""
	cands.sort_custom(func(a, b):    # (the ones who can go first, then Scavengers, then Fighters, then by name)
		var ra := (0 if a.ok else 4) + (0 if a.tags.has("Scavenger") else (1 if a.tags.has("Fighter") else 2))
		var rb := (0 if b.ok else 4) + (0 if b.tags.has("Scavenger") else (1 if b.tags.has("Fighter") else 2))
		return ra < rb or (ra == rb and String(a.name) < String(b.name)))
	return cands


func cand(id: String) -> Dictionary:
	for c in cands:
		if String(c.id) == id:
			return c
	return {}


## May `id` be added to the picked ones now? ({ok, why}): two at most, and the guards left on the towers stay at two.
func can_pick(id: String) -> Dictionary:
	var c := cand(id)
	if c.is_empty() or not bool(c.ok):
		return {"ok": false, "why": String(c.get("why", "nobody by that name"))}
	if picked.has(id):
		return {"ok": true, "why": ""}
	if picked.size() >= int(cfg.max):
		return {"ok": false, "why": "two companions at most"}
	if String(c.econ_role) == "guard":
		var guards := 0
		var out := 0
		for k in cands:
			if String(k.econ_role) == "guard":
				guards += 1
				if picked.has(String(k.id)):
					out += 1
		if guards - out - 1 < 2:
			return {"ok": false, "why": "two guards must stay on the towers"}
	return {"ok": true, "why": ""}


func toggle(id: String) -> bool:
	if picked.has(id):
		picked.erase(id)
		return true
	if bool(can_pick(id).ok):
		picked.append(id)
		return true
	return false


## "Mia (cook) is out: cooking stops" for each picked person: what the base goes without while they are away.
func loss_lines() -> Array:
	var out: Array = []
	for id in picked:
		var c := cand(String(id))
		if c.is_empty():
			continue
		var role := String(c.econ_role)
		var others := 0
		for k in cands:
			if String(k.econ_role) == role and String(k.id) != id and not picked.has(String(k.id)) and bool(k.ok) and role != "":
				others += 1
		var word := String((cfg.role_words as Dictionary).get(role, "")) if role != "" else ""
		var line := "%s is out" % String(c.name)
		if role != "" and word != "":
			if others > 0 and role != "guard":
				line += ": %d other%s still work%s as %s" % [others, "" if others == 1 else "s", "s" if others == 1 else "", role]
			elif role == "guard":
				line += ": %s (%d guards stay)" % [word, others]
			else:
				line += ": %s" % word
		out.append(line)
	return out


func out_ids() -> Array:
	return out


# ------------------------------------------------------------------ the raid ---------

## The raid's stage is made and Ruth stands at the drop: the picked people (or the staging flag's) come out of the truck beside her.
func begin_raid() -> void:
	members = []
	floaters = []
	revive_t = 0.0
	wait_t = 0.0
	left_behind = false
	open = false
	if cands.is_empty():
		snapshot()
	var ids: Array = picked.duplicate()
	if game.args.has("companion"):    # staging: --companion=near (june and owen) or --companion=mia,june
		var w := String(game.args.companion)
		ids = ["june", "owen"] if w == "near" or w == "1" else Array(w.split(","))
	picked = []
	out = []
	var at := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	for i in ids.size():
		var c := cand(String(ids[i]))
		if c.is_empty() or i >= int(cfg.max):
			continue
		_spawn(c, at + Vector2(1.2 + float(i) * 1.1, 0.8))
		out.append(String(c.id))
	if game.args.has("companion") and game.args.has("log"):
		for m in members:
			print("SQUAD ", m.name, " ", m.tags, " gun ", m.p.gun.name, " bag ", m.bag.w, "x", m.bag.h, " cmd ", m.cmd)


func _spawn(c: Dictionary, at: Vector2) -> Dictionary:
	var defs: Dictionary = {}
	for pd in game.data.people:
		defs[String(pd.id)] = pd
	var src: Dictionary = (defs[String(c.key)] as Dictionary).duplicate(true)
	src["id"] = String(c.id)
	src["name"] = String(c.name)
	src["unarmed"] = false
	var look: Dictionary = (src.look as Dictionary).duplicate(true)
	for k in c.look:
		look[k] = c.look[k]
	src["look"] = look
	src["station"] = ""
	src["post_id"] = ""
	var p = game.run.sim.make_person(src)
	p.player = false
	p.x = at.x
	p.y = at.y
	p.hp = 100.0
	p.moving = false
	var n := PawnNode.new()
	n.setup(p, false, game.data, String(c.key))
	game.entities.add_child(n)
	var tags: Array = c.tags
	var m := {"id": String(c.id), "name": String(c.name), "p": p, "node": n, "hp": float(c.hp), "max": float(c.hp), "state": "up", "cmd": "scavenge" if tags.has("Scavenger") else "follow", "tags": tags,
		"bag": Inventory.make_grid(int(c.bag.x), int(c.bag.y)), "loose": {}, "say": "", "bark": "", "bark_t": 0.0, "cd": 1.0, "bite": 0.0, "path": [], "pi": 0, "repath": 0.0, "goal": Vector2.INF,
		"scav": {}, "skip": {}, "down_t": 0.0, "fall": false, "found": false, "ref": null, "hold_at": Vector2(p.x, p.y), "wait": 0.0, "noammo_t": 0.0, "stuck_t": 0.0, "last": Vector2(p.x, p.y), "done_n": 0, "recall": false, "calm": 0.0, "def": c.def}
	members.append(m)
	_bark(m, "Ready." if String(m.cmd) == "follow" else "On it.")
	return m


## The survivor of this raid says yes: they are a member now (a bag of 4 by 2, follow). The survivor's own record `s` (prison_people.gd) keeps pointing at the same person and node.
func add_found(s: Dictionary) -> void:
	var m := {"id": String(s.def.id), "name": String(s.name), "p": s.p, "node": s.node, "hp": float(s.hp), "max": float(game.people._c().survivor.hp), "state": "up", "cmd": "follow", "tags": [],
		"bag": Inventory.make_grid(int(cfg.bag.default[0]), int(cfg.bag.default[1])), "loose": {}, "say": "", "bark": "", "bark_t": 0.0, "cd": 1.0, "bite": 0.0, "path": [], "pi": 0, "repath": 0.0, "goal": Vector2.INF,
		"scav": {}, "skip": {}, "down_t": 0.0, "fall": false, "found": true, "ref": s, "hold_at": Vector2(s.p.x, s.p.y), "wait": 0.0, "noammo_t": 0.0, "stuck_t": 0.0, "last": Vector2(s.p.x, s.p.y), "done_n": 0, "recall": false, "calm": 0.0, "def": s.def}
	members.append(m)
	_bark(m, "I'm with you.")


func drives(s: Dictionary) -> bool:
	for m in members:
		if m.ref != null and is_same(m.ref, s):
			return true
	return false


func alive() -> Array:
	return members.filter(func(m): return m.state == "up")


func any() -> bool:
	return not members.is_empty()


func _bark(m: Dictionary, text: String, secs: float = 3.0) -> void:
	m.bark = text
	m.bark_t = secs


func _me() -> Vector2:
	return Vector2(game.run.avatar_p.x, game.run.avatar_p.y)


# ------------------------------------------------------------------ the frame --------

func update(dt: float) -> void:
	for f in floaters:
		f.t = float(f.t) + dt
	floaters = floaters.filter(func(f): return float(f.t) < 2.2)
	if members.is_empty():
		return
	game.ally_chasers.clear()
	_t += dt
	var zs: Array = game._awake_dead()
	var me := _me()
	if game.args.has("botshoot") and fmod(_t, 20.0) < dt:
		for m in members:
			print("SQUADSTAT tick t=", int(_t), " ", m.name, " hp ", int(m.hp), " ", m.state, " cmd ", m.cmd, " '", m.say, "' ruth_d ", snappedf(Vector2(m.p.x, m.p.y).distance_to(me), 0.1), " awake ", zs.size(), " ruth_hp ", int(game.run.avatar_p.hp))
	var idx := 0
	for m in members:
		if m.state == "gone":
			continue
		_step(m, dt, me, zs, idx)
		if m.state == "up":
			idx += 1
		if m.ref != null:
			m.ref.hp = m.hp
	members = members.filter(func(m): return m.state != "gone")
	_revive(dt, me)
	if not _test.is_empty():
		_run_test(dt)


func _step(m: Dictionary, dt: float, me: Vector2, zs: Array, idx: int) -> void:
	var p = m.p
	var at := Vector2(p.x, p.y)
	m.bark_t = float(m.bark_t) - dt
	if float(m.bark_t) <= 0.0:
		m.bark = ""
	if m.state == "down":
		m.down_t = float(m.down_t) - dt
		m.say = "DOWN %ds" % int(ceil(float(m.down_t)))
		if float(m.down_t) <= 0.0:
			_lose(m, "%s is gone." % String(m.name))
		return
	# the poses tick as the clear phase allies' do (prison_game.gd `_gun_poses`)
	p.recoil = maxf(0.0, float(p.recoil) - dt * 8.0)
	p.reloading = maxf(0.0, float(p.reloading) - dt)
	p.thrust = maxf(0.0, float(p.thrust) - dt * 3.0)
	var hold := float(game.aim_hold.get(p.id, 0.0)) - dt
	game.aim_hold[p.id] = hold
	if hold <= 0.0 and p.target != null:
		p.target = null
	m.cd = float(m.cd) - dt
	m.bite = float(m.bite) - dt
	# bites, and the dead that go for them instead of Ruth
	var biters := 0
	for z in zs:
		var d := at.distance_to(Vector2(z.x, z.y))
		if d < game.BITE_R:
			biters += 1
		if z.state == "chase" and d < 8.0 and d < me.distance_to(Vector2(z.x, z.y)) - 0.5:
			game.ally_chasers[z] = {"p": p, "state": "ally"}
	if biters > 0 and float(m.bite) <= 0.0:
		m.bite = 0.9
		var dmg: float = game.BITE_DMG * float(mini(biters, 3))
		m.hp = float(m.hp) - dmg
		game.sound.play("bite", 0.5)
		floaters.append({"text": "-%d" % int(dmg), "pos": Vector2(p.x, p.y - 1.6), "t": 0.0, "col": Color(1, 0.35, 0.3)})
		if float(m.hp) <= 0.0:
			m.hp = 0.0
			m.state = "down"
			m.down_t = float(cfg.down_s)
			stats.down = int(stats.down) + 1
			if game.args.has("log"):
				print("SQUADSTAT down ", m.name, " t=", snappedf(_t, 0.1), " cmd ", m.cmd, " '", m.say, "' ruth_d ", snappedf(at.distance_to(me), 0.1), " near_dead ", zs.size())
			p.downed = true
			p.moving = false
			p.work = ""
			_bark(m, "Down...", 4.0)
			game._say("%s is down! Hold E next to them to revive (1 med)." % String(m.name), 4.0)
			return
	p.hp = m.hp
	if game.raidx.retreating:    # RAID EXTRAS: the V key: everybody runs to the nearest pickup ring and waits in it, whatever the order was
		var ring: Vector2 = game.raidx.nearest_exit(at)
		if ring != Vector2.INF:
			p.work = ""
			m.scav = {}
			if at.distance_to(ring) > game.EXTRACT_R - 1.5:
				_goto(m, ring, dt, float(cfg.run))
			else:
				p.moving = false
			m.say = "retreating"
			return
	var cmd := String(m.cmd)
	# the rules (see the header): count the awake dead near them; fall back to Ruth when hurt or when `swarm_n` or more are about
	var near_n := 0
	var near_d := 1.0e9
	var threat := Vector2.ZERO
	for z in zs:
		var dz0 := at.distance_to(Vector2(z.x, z.y))
		if dz0 < float(cfg.alarm_r) and (String(z.state) != "wander" or dz0 < 4.0):    # (a dead one that only wanders counts when it is close)
			near_n += 1
			threat += Vector2(z.x, z.y)
			near_d = minf(near_d, dz0)
	var retreat := float(m.hp) < float(cfg.retreat_hp) * float(m.max) and cmd != "cover"
	var swarm := near_n >= int(cfg.swarm_n) and cmd != "cover"
	if retreat and not bool(m.fall):
		m.fall = true
		_bark(m, "Hurt! Falling back.", 3.0)
		if cmd == "scavenge":
			m.scav = {}
			p.work = ""
	# a scavenger is recalled when dead show up or Ruth is too far, and goes back to work when it is quiet and they are beside her
	if cmd == "scavenge" and not bool(m.recall) and (near_n > 0 or at.distance_to(me) > float(cfg.leash)):
		m.recall = true
		m.scav = {}
		p.work = ""
		_bark(m, "Dead about! Back to you." if near_n > 0 else "Coming back!", 3.0)
	if bool(m.recall):
		m.calm = float(m.calm) + dt if (near_n == 0 and at.distance_to(me) < float(cfg.follow_r) * 2.5) else 0.0
		if float(m.calm) > 3.0:
			m.recall = false
	var eff := "follow" if (retreat or swarm or bool(m.recall) or bool(game.squad_regroup)) and cmd != "hold" else cmd
	# the slot: beside Ruth and on the side away from the dead (never in front of her); "spread out" keeps a wider ring
	var rad := float(cfg.follow_r) * (0.7 if eff == "cover" else (float(cfg.spread_r) / float(cfg.follow_r) if eff == "spread" else 1.0))
	var slot := me + Vector2.from_angle(float(idx) * 2.1 + 0.5) * rad
	if near_n > 0 and me.distance_to(threat / float(near_n)) > 0.1:
		var back := (me - threat / float(near_n)).normalized()
		slot = me + back * rad * 0.8 + back.orthogonal() * (1.4 if idx % 2 == 0 else -1.4)
	# shooting: the nearest dead in sight
	var reach := float(cfg.shoot_r) * (1.4 if eff == "cover" else 1.0)
	var best = null
	var bd := reach
	for z in zs:
		var dz := at.distance_to(Vector2(z.x, z.y))
		if dz < bd and game.targetable(z) and game.focus_free(p, z, "squad") and game.run.sim.clear_shot(at, Vector2(z.x, z.y), 0.15):
			bd = dz
			best = z
	var fighting := false
	m.fight_t = float(m.get("fight_t", 0.0)) - dt
	if best != null and (bool(p.gun.get("melee", false)) or game.can_fire(p, best, "squad")) and float(m.cd) <= 0.0 and float(p.reloading) <= 0.0:
		if _fire(m, best, bd, eff):
			m.fight_t = 1.2
	if best != null and bool(p.gun.get("melee", false)) and bd > 1.7 and eff != "hold" and not retreat and not swarm and Vector2(best.x, best.y).distance_to(me) < float(cfg.melee_r):
		_goto(m, Vector2(best.x, best.y), dt, float(cfg.run))    # (a pike only reaches 1.9 tiles: they walk up to it)
		m.say = "charging"
		p.work = ""
		return
	fighting = float(m.fight_t) > 0.0
	if fighting:
		if eff != "hold" and not bool(p.gun.get("melee", false)) and (near_d < float(cfg.kite_r) or at.distance_to(me) > float(cfg.leash)):    # kite: shoot on the move toward Ruth
			_goto(m, slot, dt, float(cfg.run))
		else:
			p.moving = false
		if eff == "scavenge":
			p.work = ""
		m.say = "fighting"
		if best != null and not bool(p.moving):
			p.facing = game.run.sim.facing_of(best.x - p.x, best.y - p.y, p.facing)
		return
	match eff:
		"hold":
			p.moving = false
			p.work = ""
			m.say = "holding here"
			if at.distance_to(m.hold_at) > 1.5:
				_goto(m, m.hold_at, dt, float(cfg.speed))
		"scavenge":
			_scavenge(m, dt, me, zs)
		_:
			p.work = ""
			var dist := at.distance_to(slot)
			if at.distance_to(me) > 30.0:
				p.x = me.x
				p.y = me.y
				m.path = []
			elif dist > 1.1:
				_goto(m, slot, dt, float(cfg.run) if (dist > 8.0 or bool(game.squad_regroup)) else float(cfg.speed))
			else:
				p.moving = false
			m.say = "hurt, falling back" if retreat else ("falling back, dead about" if swarm else ("covering you" if eff == "cover" else ("spread out" if eff == "spread" else "with you")))
	if eff != "hold":
		m.hold_at = Vector2(p.x, p.y)


## One shot (or one blow) at a dead one. False when they could not (no ammo).
func _fire(m: Dictionary, z, dist: float, eff: String) -> bool:
	var p = m.p
	var gun: Dictionary = p.gun
	if bool(gun.get("melee", false)):
		if dist > 1.9:
			return false
		p.thrust = 1.0
		p.facing = game.run.sim.facing_of(z.x - p.x, z.y - p.y, p.facing)
		game.run.sim._hurt_zombie(z, 3.5, Vector2(p.x, p.y).angle_to_point(Vector2(z.x, z.y)), null)
		m.cd = 1.2
		m.say = "swinging"
		game.sound.play("stab", 0.6, 0.08)
		return true
	if String(m.cmd) == "quiet":    # NOISE hook: the quiet stance holds fire; a dead one that is on them is stabbed (a blow, 3 tiles of noise), not shot
		if dist > 1.9:
			m.cd = 0.3
			return false
		p.thrust = 1.0
		p.facing = game.run.sim.facing_of(z.x - p.x, z.y - p.y, p.facing)
		game.run.sim._hurt_zombie(z, 3.5, Vector2(p.x, p.y).angle_to_point(Vector2(z.x, z.y)), null)
		game.run.sim.field.noise(Vector2(p.x, p.y), null, 3.0)
		m.cd = 1.2
		m.say = "knifing"
		game.sound.play("stab", 0.6, 0.08)
		return true
	var inv = game.pack.inv
	var cost := float(cfg.shot_cost)
	if inv == null or inv.take_float("ammo", cost) < cost - 0.001:
		if float(m.noammo_t) <= 0.0:
			_bark(m, "Out of ammo!", 3.0)
			m.noammo_t = 8.0
		m.noammo_t = float(m.noammo_t) - 0.2
		m.cd = 0.5
		return false
	game._shoot_at(p, z, game.gun_hit("squad", dist, z), float(Bal.role("squad").dmg))
	game.run.field.noise(Vector2(p.x, p.y), null, float(gun.get("noise", 12.0)))
	m.cd = Bal.roll(Bal.role("squad"), "cd") * (0.7 if eff == "cover" else 1.0)
	m.say = "firing"
	m.fired_at = game.clock    # (the Firing tag lasts 1.5 s after the shot)
	return true


# ------------------------------------------------------------------ walking ----------

func _goto(m: Dictionary, goal: Vector2, dt: float, speed: float) -> bool:
	var p = m.p
	var at := Vector2(p.x, p.y)
	if at.distance_to(goal) < 0.3:
		p.moving = false
		return true
	m.repath = float(m.repath) - dt
	if (m.goal as Vector2).distance_to(goal) > 0.6 or float(m.repath) <= 0.0 or int(m.pi) >= (m.path as Array).size():
		m.repath = 0.6
		m.goal = goal
		m.path = game.run.sim.path_p.find(game.world.solid_p, p.x, p.y, goal.x, goal.y)
		m.pi = 0
		if (m.path as Array).is_empty():
			p.moving = false
			return false
	# one step along the path
	if int(m.pi) >= (m.path as Array).size():
		p.moving = false
		return true
	var wp: Vector2 = m.path[m.pi]
	var to := wp - at
	var d := to.length()
	if d < 0.12:
		m.pi = int(m.pi) + 1
		return false
	var step := minf(d, speed * dt)
	p.x += to.x / d * step
	p.y += to.y / d * step
	p.facing = game.run.sim.facing_of(to.x / d, to.y / d, p.facing)
	p.moving = true
	p.walk_phase += dt * 6.0 * speed / 1.7
	return false


# ---------------------------------------------------------------- scavenging ---------

func _dead_near(at: Vector2, r: float, zs: Array) -> int:
	var n := 0
	for z in zs:
		if Vector2(z.x, z.y).distance_to(at) < r:
			n += 1
	return n


func _house_center(h: int) -> Vector2:
	var hh: Dictionary = game.run.sim.houses.house(h)
	return Rect2(hh.rect).get_center() if not hh.is_empty() else Vector2.ZERO


## The scavenging machine, one frame (see the header).
func _scavenge(m: Dictionary, dt: float, me: Vector2, zs: Array) -> void:
	var p = m.p
	var at := Vector2(p.x, p.y)
	var s: Dictionary = m.scav
	var sim = game.run.sim
	if s.is_empty():
		var pick := _pick_house(m, at, zs, me)
		if pick.is_empty():
			m.say = "waiting: dead about" if bool(m.get("wait_flag", false)) else "nothing left"
			if bool(m.get("wait_flag", false)):
				m.wait = float(m.wait) + dt
				p.moving = false
				p.work = ""
				if float(m.wait) > float(cfg.wait_s):
					m.cmd = "follow"
					m.wait = 0.0
					_bark(m, "Too many dead. Back to you.", 3.0)
			else:
				m.cmd = "follow"
				_bark(m, "Nothing left to search.", 3.5)
			return
		m.wait = 0.0
		m.scav = pick
		s = pick
		_bark(m, "Going into house %d." % int(s.house), 2.5)
	# the dead have come to the house: wait outside (or in the door) rather than walk into them
	var cur_id := String(s.list[s.i]) if int(s.i) < (s.list as Array).size() else ""
	if cur_id == "":
		_house_done(m)
		return
	var cont: Dictionary = sim.houses.container(cur_id)
	var spot: Vector2 = Vector2(cont.pos)
	if String(s.stage) == "go":
		if sim.search.is_looted(cur_id) or _claimed(cur_id, m):
			s.i = int(s.i) + 1    # (Ruth, or the other companion, got to it first)
			return
		if _dead_near(spot, float(cfg.dead_wait_r), zs) > int(cfg.dead_wait):
			p.moving = false
			p.work = ""
			m.say = "waiting: dead about"
			m.wait = float(m.wait) + dt
			if float(m.wait) > float(cfg.wait_s):
				m.wait = 0.0
				m.cmd = "follow"
				m.scav = {}
				_bark(m, "Too many dead. Back to you.", 3.0)
			return
		m.wait = 0.0
		p.work = ""
		var arrived := _goto(m, spot, dt, float(cfg.speed))
		m.say = "heading to house %d" % int(s.house)
		# stuck: no way there in a few seconds
		if (m.path as Array).is_empty() and not arrived:
			m.skip[cur_id] = true
			s.i = int(s.i) + 1
			return
		if Vector2(p.x, p.y).distance_to(m.last) < 0.01 * dt * 60.0 and not arrived:
			m.stuck_t = float(m.stuck_t) + dt
			if float(m.stuck_t) > 5.0:
				m.stuck_t = 0.0
				m.skip[cur_id] = true
				s.i = int(s.i) + 1
		else:
			m.stuck_t = 0.0
		m.last = Vector2(p.x, p.y)
		if arrived:
			s.stage = "search"
			s.t = 0.0
			_bark(m, "Searching...", 2.5)
		return
	# search
	p.moving = false
	p.work = "sort"
	s.t = float(s.t) + dt
	p.work_t = float(s.t)
	var secs := SearchRules.search_secs(sim, cont)
	m.say = "looting house %d/%d" % [int(s.i) + 1, (s.list as Array).size()]
	if float(s.t) >= secs:
		p.work = ""
		var full := _take(m, cur_id)
		s.i = int(s.i) + 1
		s.stage = "go"
		m.done_n = int(m.done_n) + 1
		if full:
			m.cmd = "follow"
			m.scav = {}
			_bark(m, "Bag full.", 4.0)
			game._say("%s: bag full. Back with you." % String(m.name), 3.0)
		elif int(s.i) >= (s.list as Array).size():
			_house_done(m)


## Whether another companion is on this container (walking to it or searching it).
func _claimed(id: String, me: Dictionary) -> bool:
	for o in members:
		if o != me and o.state == "up" and not (o.scav as Dictionary).is_empty() and int(o.scav.i) < (o.scav.list as Array).size() and String(o.scav.list[o.scav.i]) == id:
			if members.find(o) < members.find(me) or String(o.scav.stage) == "search":    # (the first in the list keeps it)
				return true
	return false


func _house_done(m: Dictionary) -> void:
	var h := int(m.scav.get("house", -1))
	m.cmd = "follow"
	m.scav = {}
	m.p.work = ""
	_bark(m, "House %d done." % h, 4.0)
	game._say("%s finished house %d (%s)." % [String(m.name), h, bag_text(m)], 3.5)


## The nearest house with something left in a container that nobody has searched ({} when none, `m.wait_flag` says some are only held up by the dead): the containers in the order room by room.
func _pick_house(m: Dictionary, at: Vector2, zs: Array, me: Vector2) -> Dictionary:
	var sim = game.run.sim
	var by_house := {}
	for c in game.town.containers:
		var id := String(c.id)
		var h := int(c.house)
		if h < 0 or sim.search.is_looted(id) or m.skip.has(id) or (c.loot as Dictionary).is_empty():
			continue
		if not by_house.has(h):
			by_house[h] = []
		(by_house[h] as Array).append(c)
	m.wait_flag = false
	var best_h := -1
	var bd := 1.0e9
	for h in by_house:
		var cen := _house_center(int(h))
		if _dead_near(cen, float(cfg.dead_wait_r), zs) > int(cfg.dead_wait):
			m.wait_flag = true
			continue
		var d := at.distance_to(cen)
		if me.distance_to(cen) > float(cfg.scav_r):    # "scavenge here": only houses near Ruth
			continue
		if d < bd:
			bd = d
			best_h = int(h)
	if best_h < 0:
		return {}
	# room by room: from the door, the nearest container, staying in its room while the room has any
	var left: Array = (by_house[best_h] as Array).duplicate()
	var order: Array = []
	var cur: Vector2 = Vector2(sim.houses.house(best_h).door) + Vector2(0.5, 0.5) if not sim.houses.house(best_h).is_empty() else at
	var room := -2
	while not left.is_empty():
		var bi := 0
		var bc := 1.0e9
		for i in left.size():
			var cost := cur.distance_to(Vector2(left[i].pos)) + (0.0 if int(left[i].room) == room else 6.0)
			if cost < bc:
				bc = cost
				bi = i
		var c2: Dictionary = left[bi]
		order.append(String(c2.id))
		cur = Vector2(c2.pos)
		room = int(c2.room)
		left.remove_at(bi)
	return {"house": best_h, "list": order, "i": 0, "stage": "go", "t": 0.0}


## The search of one container is done: its scrap and its items go to the member (items into the bag as far as it holds them; what does not fit stays in the container, which Ruth can open). True when the bag is full.
func _take(m: Dictionary, id: String) -> bool:
	var sim = game.run.sim
	var inv = sim.inv
	var cont: Dictionary = sim.houses.container(id)
	var got := {}
	var loose := Inventory.loose_units(cont.get("loot", {}) if typeof(cont.get("loot", {})) == TYPE_DICTIONARY else {})
	for k in loose:
		if sim.stock.has(k):
			m.loose[k] = int(m.loose.get(k, 0)) + int(loose[k])
			got[k] = int(got.get(k, 0)) + int(loose[k])
	var g: Dictionary = inv.grid_of(id)
	var full := false
	var i := 0
	while i < (g.cells as Array).size():
		var pl: Dictionary = g.cells[i]
		var before := int(pl.count)
		var left := Inventory.auto_add(m.bag, String(pl.item), before)
		var moved := before - left
		if moved > 0:
			var res := Inventory.res_of(String(pl.item))
			var key := res if res != "" else String(pl.item)
			got[key] = int(got.get(key, 0)) + (moved * Inventory.units_of(String(pl.item)) if res != "" else moved)
		if left <= 0:
			(g.cells as Array).remove_at(i)
		else:
			pl.count = left
			full = true
			i += 1
	inv.searched[id] = true
	sim.search.looted[id] = true    # (searched: what did not fit shows as "left in it" to Ruth)
	inv.version = int(inv.version) + 1
	var parts: Array = []
	for k in got:
		parts.append("+%d %s" % [int(got[k]), String(k).replace("gun_", "")])
	if not parts.is_empty():
		floaters.append({"text": ", ".join(parts), "pos": Vector2(m.p.x, m.p.y - 1.9), "t": 0.0, "col": Color(0.7, 1.0, 0.7)})
	if Inventory.free_cells(m.bag) <= 0:
		full = true
	return full


func bag_cells(m: Dictionary) -> String:
	return "%d/%d" % [Inventory.used_cells(m.bag), Inventory.cell_count(m.bag)]


## What the bag holds, in words: "3 items, bag 5/18".
func bag_text(m: Dictionary) -> String:
	var n := 0
	for pl in m.bag.cells:
		n += int(pl.count)
	for k in m.loose:
		n += int(m.loose[k])
	return "%d item%s, bag %s" % [n, "" if n == 1 else "s", bag_cells(m)]


# ------------------------------------------------------------------- orders ----------

func command(m: Dictionary, cmd: String) -> void:
	if m.state != "up" or not CMDS.has(cmd):
		return
	m.cmd = cmd
	m.scav = {}
	m.fall = false
	m.p.work = ""
	m.wait = 0.0
	m.hold_at = Vector2(m.p.x, m.p.y)
	_bark(m, {"follow": "Right behind you.", "hold": "Holding here.", "scavenge": "Looking for a house.", "cover": "I've got you.", "quiet": "Quiet. Knives only.", "spread": "Spreading out."}[cmd], 2.5)


func command_all(cmd: String) -> void:
	for m in members:
		command(m, cmd)


## The V key: a shout from each of them (the running itself is in `_step`).
func retreat_barks() -> void:
	for m in members:
		if m.state == "up":
			_bark(m, "Run for the ring!", 3.0)


## The call to the pickup: everybody on their feet walks to Ruth, running.
func call_all() -> void:
	game.squad_regroup = true
	for m in members:
		if m.state == "up" and String(m.cmd) != "follow":
			m.cmd = "follow"
			m.scav = {}
			m.p.work = ""
			_bark(m, "Coming!", 3.0)


# ------------------------------------------------------------------- revive ----------

func nearest_down(me: Vector2):
	for m in members:
		if m.state == "down" and me.distance_to(Vector2(m.p.x, m.p.y)) < 1.8:
			return m
	return null


## The E prompt of a downed companion beside Ruth ({} otherwise).
func prompt() -> Dictionary:
	var dn = nearest_down(_me())
	if dn == null:
		return {}
	var meds: float = float(game.pack.inv.meds_available(game.run.avatar_p)) if game.pack.inv != null else 0.0
	return {"kind": "revive", "label": ("Hold E: revive %s (1 med)" % String(dn.name)) if meds >= 1.0 else "%s is down. No meds to revive." % String(dn.name)}


func _revive(dt: float, me: Vector2) -> void:
	var dn = nearest_down(me)
	if dn == null:
		revive_t = 0.0
		return
	var inv = game.pack.inv
	var ok: bool = inv != null and float(inv.meds_available(game.run.avatar_p)) >= 1.0
	var held := Input.is_key_pressed(KEY_E) or String(game.args.get("companion-revive", "")) != ""
	if ok and held and not game.busy:
		revive_t += dt
		if revive_t >= float(cfg.revive_s):
			inv.take_float("meds", 1.0)
			dn.hp = float(dn.max) * 0.5
			dn.state = "up"
			dn.fall = false
			dn.p.downed = false
			revive_t = 0.0
			_bark(dn, "Thanks.", 3.0)
			game._say("%s is back on their feet." % String(dn.name), 3.0)
	else:
		revive_t = maxf(0.0, revive_t - dt * 2.0)
	game.revive_t = revive_t


# -------------------------------------------------------------------- the pickup -----

## The pickup ring while Ruth stands in it: {"ok": go on, "text": what to tell her}. Everyone who is up and within `join_r` tiles comes; the others are waited for up to `wait_s` seconds.
func ring_state(dt: float) -> Dictionary:
	var me := _me()
	var far: Array = []
	for m in members:
		var d := me.distance_to(Vector2(m.p.x, m.p.y))
		if m.state == "down" or d > float(cfg.join_r):
			far.append(m)
	if far.is_empty() or left_behind:
		return {"ok": true, "text": ""}
	wait_t += dt
	var names: Array = []
	for m in far:
		names.append("%s%s" % [String(m.name), " (down)" if m.state == "down" else " (%d tiles)" % int(me.distance_to(Vector2(m.p.x, m.p.y)))])
	if wait_t >= float(cfg.wait_s) + 4.0:
		return {"ok": true, "text": ""}
	return {"ok": false, "text": "Waiting for %s.  E: go without them (they are lost)" % " and ".join(names)}


func abandon() -> void:
	left_behind = true


## The pickup is done (or Ruth is dead): who comes home, what the bags bank. {lines: [words], left: [names], banked: {res: n}}. The ones who are lost are marked for the base (they will not be in the rebuilt crew).
func settle(alive_ring: bool) -> Dictionary:
	var lines: Array = []
	var lost: Array = []
	var me := _me()
	var grids: Array = []
	for m in members:
		var near: bool = m.state == "up" and (me.distance_to(Vector2(m.p.x, m.p.y)) <= float(cfg.join_r) + 0.5 or (not alive_ring and m.state == "up"))
		if near:
			if alive_ring:
				grids.append(m.bag)
				for k in m.loose:
					game.run.sim.stock[k] = float(game.run.sim.stock.get(k, 0.0)) + float(m.loose[k])
				lines.append("%s is back with you (%s)." % [String(m.name), bag_text(m)])
			else:
				lines.append("%s makes it back, empty handed." % String(m.name))
		elif not m.found:
			lost.append(String(m.name))
			lines.append("%s was left outside." % String(m.name) if m.state == "up" else "%s did not make it." % String(m.name))
			_forget(m)
	if alive_ring and not grids.is_empty():
		var n: int = game.arms.collect(grids)    # (guns in a bag go to the weapon rack)
		for g in grids:
			Inventory.deposit_all(g, game.run.sim.stock)
		if n > 0:
			lines.append("%d gun%s for the weapon rack." % [n, "" if n == 1 else "s"])
	elif alive_ring:
		pass
	return {"lines": lines, "left": lost}


func _lose(m: Dictionary, text: String) -> void:
	stats.lost = int(stats.lost) + 1
	if game.args.has("log"):
		print("SQUADSTAT lost ", m.name, " t=", snappedf(_t, 0.1))
	game.people.banner(text, Color(1, 0.55, 0.45))
	_forget(m)
	m.state = "gone"
	if m.node != null and is_instance_valid(m.node):
		m.node.queue_free()
	if m.ref != null:
		m.ref.state = "lost"
		game.ally_chasers.clear()


## A companion who will not come back: out of the base for good, and the people's pool forgets them.
func _forget(m: Dictionary) -> void:
	if m.found:
		return
	if not game.econ_gone.has(String(m.name)):
		game.econ_gone.append(String(m.name))
	game.people.forget(String(m.name))
	game.econ.morale = maxf(0.0, float(game.econ.morale) - 6.0)
	if m.state != "gone" and m.node != null and is_instance_valid(m.node):
		m.node.visible = false


# ------------------------------------------------------------------- the window ------

## The frame's pawn sync for the companions (the game syncs the crew and the zombies; these are neither).
func sync(view: Rect2, clock: float, sim_steps: int, alpha: float) -> void:
	for m in members:
		var n = m.node
		if n == null or not is_instance_valid(n):
			continue
		n.anim_t = clock
		n.visible = view.has_point(Vector2(m.p.x, m.p.y)) and m.state != "gone"
		if n.visible:
			n.sync(true, sim_steps, alpha)


## A raid ends: the people are not in the scene any more.
func end_raid() -> void:
	members = []
	floaters = []
	out = []
	open = false
	if _panel != null:
		_panel.visible = false
	game.squad_regroup = false
	revive_t = 0.0
	game.revive_t = 0.0


# ------------------------------------------------------------------- drawing ---------

const NAME_COLS := [Color("#8fe0ff"), Color("#ffd27a"), Color("#c9f08a"), Color("#f5a3d0")]    # a name colour for each companion


static func icon(c: CanvasItem, cmd: String, at: Vector2, r: float, col: Color) -> void:
	var dark := Color(0.04, 0.06, 0.05, 0.9)
	c.draw_circle(at, r + 2.0, dark)
	match cmd:
		"follow":
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(r * 0.8, 0), at + Vector2(-r * 0.6, -r * 0.7), at + Vector2(-r * 0.6, r * 0.7)]), col)
		"hold":
			c.draw_rect(Rect2(at - Vector2(r * 0.6, r * 0.6), Vector2(r * 1.2, r * 1.2)), col)
		"scavenge":
			c.draw_rect(Rect2(at + Vector2(-r * 0.65, -r * 0.2), Vector2(r * 1.3, r * 0.95)), col)
			c.draw_arc(at + Vector2(0, -r * 0.2), r * 0.45, PI, TAU, 8, col, 2.0)
		"spread":
			c.draw_arc(at, r * 0.75, 0.0, TAU, 12, col, 2.0)
			c.draw_circle(at, r * 0.25, col)
		"quiet":
			c.draw_arc(at, r * 0.7, 0.0, TAU, 12, col, 2.0)
			c.draw_line(at + Vector2(-r * 0.5, r * 0.5), at + Vector2(r * 0.5, -r * 0.5), col, 2.0)
		"cover":
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-r * 0.7, -r * 0.7), at + Vector2(r * 0.7, -r * 0.7), at + Vector2(r * 0.7, r * 0.1), at + Vector2(0, r * 0.85), at + Vector2(-r * 0.7, r * 0.1)]), col)


## The world overlay (px): over each companion a name, a command icon, a bar of health, what they are doing and what they say; a search bar while they search; the floating "+2 food".
func paint(c: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	var ci := -1
	for m in members:
		ci += 1
		if m.state == "gone":
			continue
		var p = m.p
		var at := Vector2(p.x, p.y - 1.45) * TILE
		var col: Color = CMD_COL[String(m.cmd)]
		c.draw_string(font, at + Vector2(-60, -2), String(m.name), HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color(1, 0.55, 0.5) if m.state == "down" else NAME_COLS[ci % NAME_COLS.size()])
		icon(c, String(m.cmd), at + Vector2(-36 - 0.0, -8), 7.0, col)
		var f := clampf(float(m.hp) / float(m.max), 0.0, 1.0)
		c.draw_rect(Rect2(at + Vector2(-22, 3), Vector2(44, 5)), Color(0, 0, 0, 0.7))
		c.draw_rect(Rect2(at + Vector2(-22, 3), Vector2(44.0 * f, 5)), Color(0.4, 0.9, 0.5) if f > 0.35 else Color(0.95, 0.35, 0.3))
		c.draw_string(font, at + Vector2(-80, 22), String(m.say), HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(0.85, 0.95, 1.0, 0.9))
		if String(m.bark) != "":
			c.draw_string(font, at + Vector2(-90, -24), String(m.bark), HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Color(1, 0.95, 0.55))
		if m.state == "up" and not (m.scav as Dictionary).is_empty() and String(m.scav.stage) == "search":
			var sim = game.run.sim
			var cont: Dictionary = sim.houses.container(String(m.scav.list[m.scav.i]))
			var fs := clampf(float(m.scav.t) / maxf(SearchRules.search_secs(sim, cont), 0.1), 0.0, 1.0)
			c.draw_rect(Rect2(at + Vector2(-22, 34), Vector2(44, 5)), Color(0, 0, 0, 0.7))
			c.draw_rect(Rect2(at + Vector2(-22, 34), Vector2(44.0 * fs, 5)), Color(0.95, 0.8, 0.3))
	for fl in floaters:
		var col2: Color = fl.col
		col2.a = 1.0 - float(fl.t) / 2.2
		c.draw_string(font, Vector2(fl.pos) * TILE + Vector2(-110, -float(fl.t) * 22.0), String(fl.text), HORIZONTAL_ALIGNMENT_CENTER, 220, 17, col2)


## The minimap (`o`: its corner in px, `sc`: px per tile): a dot in the colour of the order, ringed.
func mini(bars: Control, o: Vector2, sc: float) -> void:
	for m in members:
		if m.state == "gone":
			continue
		var at: Vector2 = o + Vector2(m.p.x, m.p.y) * sc
		var col: Color = CMD_COL[String(m.cmd)] if m.state == "up" else Color(1, 0.3, 0.25)
		if Access.markers():
			PIcons.mark(bars, "ally", at, 4.2, col)
		else:
			bars.draw_circle(at, 3.0, col)
		bars.draw_arc(at, 4.2, 0, TAU, 12, Color(0, 0, 0, 0.9), 1.2)
		if m.state != "up":    # a downed friend pings: a red ring that swells and fades, twice a second
			var u := fmod(game.clock * 1.6, 1.0)
			bars.draw_arc(at, 4.0 + 8.0 * u, 0, TAU, 20, Color(1, 0.2, 0.15, 1.0 - u), 2.0)


## The card on the left of the screen (screen px): a row for each companion: name, order, health, what they are doing, bag.
func draw_hud(c: Control, v: Vector2) -> void:
	if members.is_empty() or game.busy:
		return
	var font := ThemeDB.fallback_font
	var y := v.y * 0.3
	c.draw_string(font, Vector2(14, y - 6), "SQUAD   C: orders", HORIZONTAL_ALIGNMENT_LEFT, 220, 13, Color(0.85, 0.85, 0.75, 0.9))
	for m in members:
		var r := Rect2(14, y, 230, 48)
		c.draw_rect(r, Color(0, 0, 0, 0.55))
		c.draw_rect(r, Color(CMD_COL[String(m.cmd)], 0.8), false, 1.0)
		PIcons.portrait(c, String(m.id), Rect2(r.position + Vector2(4, 4), Vector2(20, 20)))    # PORTRAIT
		icon(c, String(m.cmd), r.position + Vector2(36, 14), 7.0, CMD_COL[String(m.cmd)])
		c.draw_string(font, r.position + Vector2(50, 17), "%s  %s" % [String(m.name), String(CMD_WORD[String(m.cmd)])], HORIZONTAL_ALIGNMENT_LEFT, 176, 14, Color(1, 1, 0.9))
		var f := clampf(float(m.hp) / float(m.max), 0.0, 1.0)
		c.draw_rect(Rect2(r.position + Vector2(8, 24), Vector2(214, 4)), Color(0.15, 0.15, 0.12))
		c.draw_rect(Rect2(r.position + Vector2(8, 24), Vector2(214.0 * f, 4)), Color(0.4, 0.9, 0.5) if f > 0.35 else Color(0.95, 0.35, 0.3))
		c.draw_string(font, r.position + Vector2(8, 42), "%s    bag %s" % [String(m.say), bag_cells(m)], HORIZONTAL_ALIGNMENT_LEFT, 214, 12, Color(0.8, 0.9, 1.0, 0.9))
		y += 54.0


# ------------------------------------------------------------------- the orders panel --

func toggle_orders() -> void:
	if members.is_empty():
		return
	if _panel == null:
		_build_panel()
	open = not open
	_panel.visible = open
	if open:
		_refresh_panel()
		_panel.reset_size()
		_panel.position = _orders_at(game.get_viewport().get_mouse_position(), _panel.size, game._vp())


## Where the orders panel goes: beside the pointer (right and below, flipped at the window's edges), and off the middle of the screen where Ruth stands.
static func _orders_at(m: Vector2, sz: Vector2, vp: Vector2) -> Vector2:
	var p := m + Vector2(22, 22)
	if p.x + sz.x > vp.x - 8.0:
		p.x = m.x - 22.0 - sz.x
	if p.y + sz.y > vp.y - 8.0:
		p.y = m.y - 22.0 - sz.y
	if Rect2(p, sz).grow(40.0).has_point(vp / 2.0):    # (it would cover Ruth: to the other side of the pointer)
		p.x = m.x - 22.0 - sz.x if p.x > m.x else m.x + 22.0
	return Vector2(clampf(p.x, 8.0, maxf(8.0, vp.x - sz.x - 8.0)), clampf(p.y, 8.0, maxf(8.0, vp.y - sz.y - 8.0)))


func _build_panel() -> void:
	_panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.07, 0.94)
	st.border_color = Color(0.85, 0.7, 0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.name = "col"
	_panel.add_child(col)
	_panel.visible = false
	game.hud.add_child(_panel)


## A small order button: lit in the order's colour while it is the one given.
func _order_btn(text: String, cmd: String, lit: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if text.length() > 2 else HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 14)
	var c: Color = CMD_COL[cmd]
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(c.darkened(0.55), 0.95) if lit else (Color(0.16, 0.18, 0.2, 0.95) if state == "hover" else Color(0.1, 0.11, 0.12, 0.9))
		sb.border_color = c if lit or state == "hover" else Color(1, 1, 1, 0.12)
		sb.set_border_width_all(2 if lit else 1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", c if lit else Color(0.9, 0.9, 0.82))
	b.add_theme_color_override("font_hover_color", c)
	return b


## The orders as a compact table: a row an order (its key, for everyone), a column a companion; the order each one has now is lit.
func _refresh_panel() -> void:
	var col: VBoxContainer = _panel.get_node("col")
	for ch in col.get_children():
		col.remove_child(ch)
		ch.queue_free()
	var t := Label.new()
	t.text = "ORDERS   keys 1-6: everyone   C or Esc: close"
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", Color(0.94, 0.76, 0.29))
	col.add_child(t)
	var g := GridContainer.new()
	g.columns = 1 + members.size()
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 3)
	col.add_child(g)
	g.add_child(Control.new())
	for m in members:
		var nm := Label.new()
		nm.text = String(m.name)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 14)
		g.add_child(nm)
	for k in CMDS.size():
		var cmd: String = CMDS[k]
		var all_on := true
		for m in members:
			all_on = all_on and String(m.cmd) == cmd
		var ab := _order_btn("%d  %s" % [k + 1, CMD_WORD[cmd]], cmd, all_on)
		ab.tooltip_text = "Everyone: %s (key %d)" % [CMD_WORD[cmd], k + 1]
		ab.pressed.connect(func():
			command_all(cmd)
			toggle_orders())
		g.add_child(ab)
		for m in members:
			var on: bool = String(m.cmd) == cmd
			var b := _order_btn("\u25cf" if on else "", cmd, on)
			b.custom_minimum_size = Vector2(maxf(44.0, 9.0 * float(String(m.name).length())), 0)
			b.tooltip_text = "%s: %s" % [String(m.name), CMD_WORD[cmd]]
			b.pressed.connect(func():
				command(m, cmd)
				toggle_orders())
			g.add_child(b)


## Keys while the panel is up (and C to open it in a raid). True when used.
func key(ev: InputEvent) -> bool:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return false
	var k: int = ev.keycode
	if k == KEY_C and game.mode == "raid" and not game.busy and not members.is_empty():
		toggle_orders()
		return true
	if not open:
		return false
	if k >= KEY_1 and k < KEY_1 + CMDS.size():
		command_all(CMDS[k - KEY_1])
		toggle_orders()
	elif k == KEY_ESCAPE:
		toggle_orders()
	return true


func blocks_fire() -> bool:
	if not open or _panel == null:
		return false
	return Rect2(_panel.position, _panel.size).grow(6.0).has_point(game.get_viewport().get_mouse_position())


# ------------------------------------------------------------------- staging ---------

## `--scav-test`: a scripted check of the whole loop. A companion (the first) is sent to scavenge, Ruth stays near the drop, the log says what the member does every 2 s; when the house is done and
## the member is back, Ruth walks to the far ring and the raid ends: the bag is banked (printed as SQUAD RESULT).
func start_test() -> void:
	cfg = cfg.duplicate()    # (the scripted check keeps Ruth at the drop and the house far away: the "here" rules are widened for it)
	cfg.scav_r = 90.0
	cfg.leash = 90.0
	_test = {"t": 0.0, "log": 0.0, "stage": "scav", "wait": 0.0}


func _run_test(dt: float) -> void:
	_test.t = float(_test.t) + dt
	_test.log = float(_test.log) - dt
	if members.is_empty():
		return
	var m: Dictionary = members[0]
	game.run.invulnerable = true
	if String(_test.stage) == "scav" and float(_test.t) < 0.5:
		command(m, "scavenge")
	if float(_test.log) <= 0.0:
		_test.log = 2.0
		print("SCAVTEST t=", snappedf(float(_test.t), 0.1), " ", m.name, " state ", m.state, " cmd ", m.cmd, " say '", m.say, "' bag ", bag_text(m), " at ", Vector2(snappedf(m.p.x, 0.1), snappedf(m.p.y, 0.1)), " loose ", m.loose)
	if String(_test.stage) == "scav" and String(m.cmd) != "scavenge" and float(_test.t) > 1.0:
		_test.stage = "back"
		print("SCAVTEST scavenging ended: ", m.say, " | ", bag_text(m))
	if String(_test.stage) == "back":
		_test.wait = float(_test.wait) + dt
		if _test.wait > 6.0:
			_test.stage = "leave"
			var ex: Vector2 = game.exits[game.exits.size() - 1]
			game.run.avatar_p.x = ex.x
			game.run.avatar_p.y = ex.y
			if String(game.args.get("scav-test", "")) == "far":    # the companion stays out: the ring waits, then E leaves them
				m.hp = 0.0    # (down, 60 tiles away: nobody revives them)
				m.state = "down"
				m.down_t = 60.0
				m.p.downed = true
				_test.stage = "far"
			else:
				m.p.x = ex.x + 1.0
				m.p.y = ex.y
			print("SCAVTEST to the ring")
	if String(_test.stage) == "far" and wait_t > 3.0 and not left_behind:
		print("SCAVTEST ring text: ", ring_state(0.0).text)
		abandon()
