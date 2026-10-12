## EXPERIMENT (prison pack): the two kids of the compound play in the yard. They never carry a weapon (the game sets `PawnNode.unarmed` on them) and never walk a route: they run on their own
## through three games in turn, 16 s each: TAG (one chases the other, the roles swap on a touch), BALL (the nearer one runs to the ball and kicks it to the other) and HOPSCOTCH (a chalk court,
## they hop square to square and take turns). Driven from prison_crew.gd `update` for the members whose definition has "kid"; drawn by `draw` (the ball and the chalk) from the game's overlay.
extends RefCounted

const GAMES := ["tag", "ball", "hop"]
const GAME_S := 16.0
const YARD := Rect2(10.0, 43.2, 28.0, 8.5)    # x, y, w, h in tiles: the open ground south of the workshop and the cell block
const COURT := [Vector2(28, 48.5), Vector2(28, 47.5), Vector2(28, 46.5), Vector2(28, 45.5), Vector2(28, 44.5)]
const RUN := 3.4
const WALK := 2.0

var sim
var world
var kids: Array = []    # the members (dictionaries of prison_crew.gd)
var game := 0
var game_t := 0.0
var ball := Vector2(22, 47)
var ball_v := Vector2.ZERO
var chaser := 0
var hopper := 0
var hop_i := 0
var hop_wait := 0.0
var cd := 0.0
var _rng := RandomNumberGenerator.new()
var floaters: Array = []


func setup(s, w) -> void:
	sim = s
	world = w
	_rng.seed = 11


## Called for each kid member every frame; the first call of a frame for each member does the work.
func step(m: Dictionary, dt: float, all_members: Array) -> void:
	if kids.is_empty():
		for x in all_members:
			if x.def.get("kid", false):
				kids.append(x)
		for k in kids:
			k["kpath"] = []
			k["ktgt"] = Vector2.INF
	var i := kids.find(m)
	if i < 0:
		return
	if i == 0:
		_tick_game(dt)
	var other: Dictionary = kids[1 - i] if kids.size() > 1 else m
	var tgt := Vector2.INF
	var speed := RUN
	var say := "playing"
	match GAMES[game]:
		"tag":
			if i == chaser:
				tgt = Vector2(other.p.x, other.p.y)
				say = "chasing %s" % String(other.def.name)
			else:
				tgt = _flee_point(m, other)
				say = "running away!"
				speed = RUN * 0.95
			if i == chaser and cd <= 0.0 and Vector2(m.p.x, m.p.y).distance_to(Vector2(other.p.x, other.p.y)) < 0.9:
				chaser = 1 - chaser
				cd = 0.8
				floaters.append({"text": "tag!", "pos": Vector2(other.p.x, other.p.y - 1.4), "t": 0.0})
			if cd > 0.0 and i == chaser:
				tgt = Vector2(m.p.x, m.p.y)    # (a beat to count to three)
		"ball":
			var near := 0 if Vector2(kids[0].p.x, kids[0].p.y).distance_to(ball) <= Vector2(kids[-1].p.x, kids[-1].p.y).distance_to(ball) else kids.size() - 1
			if i == near:
				tgt = ball
				say = "kicking the ball"
				if Vector2(m.p.x, m.p.y).distance_to(ball) < 0.85 and ball_v.length() < 1.0:
					var to := Vector2(other.p.x, other.p.y) - ball
					ball_v = to.normalized().rotated(_rng.randf_range(-0.25, 0.25)) * minf(7.0, 2.5 + to.length() * 0.9)
			else:
				tgt = _clamp_yard(ball + (Vector2(m.p.x, m.p.y) - ball).normalized() * 5.0)
				speed = WALK
				say = "waiting for the ball"
		"hop":
			speed = WALK
			if i == hopper:
				say = "hopscotch"
				tgt = COURT[mini(hop_i, COURT.size() - 1)]
				if Vector2(m.p.x, m.p.y).distance_to(tgt) < 0.15:
					hop_wait += dt
					if hop_wait > 0.4:
						hop_wait = 0.0
						floaters.append({"text": str(hop_i + 1), "pos": Vector2(m.p.x, m.p.y - 1.4), "t": 0.0})
						hop_i += 1
						if hop_i >= COURT.size() + 1:
							hop_i = 0
							hopper = 1 - hopper
			else:
				say = "watching"
				tgt = Vector2(30.5, 46.5)
	m.say = say
	_move(m, tgt, speed, dt)


func _tick_game(dt: float) -> void:
	game_t += dt
	cd = maxf(0.0, cd - dt)
	if game_t >= GAME_S:
		game_t = 0.0
		game = (game + 1) % GAMES.size()
		hop_i = 0
		hop_wait = 0.0
	# the ball rolls, rubs off speed and stays in the yard
	if ball_v.length() > 0.05:
		var nxt := ball + ball_v * dt
		if not YARD.grow(0.5).has_point(nxt) or world.is_solid(world.solid_p, nxt.x, nxt.y):
			ball_v = -ball_v * 0.6
			nxt = ball
		ball = nxt
		ball_v *= exp(-1.7 * dt)
	else:
		ball_v = Vector2.ZERO
	for f in floaters:
		f.t = float(f.t) + dt
	floaters = floaters.filter(func(f): return float(f.t) < 1.2)


func _clamp_yard(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, YARD.position.x + 0.5, YARD.end.x - 0.5), clampf(v.y, YARD.position.y + 0.5, YARD.end.y - 0.5))


## A spot of the yard away from the chaser, changing now and then.
func _flee_point(m: Dictionary, chaser_m: Dictionary) -> Vector2:
	var me := Vector2(m.p.x, m.p.y)
	var cur: Vector2 = m.ktgt
	if cur != Vector2.INF and me.distance_to(cur) > 1.0 and cur.distance_to(Vector2(chaser_m.p.x, chaser_m.p.y)) > 4.0:
		return cur
	var best := me
	var bd := -1.0
	for n in 6:
		var c := Vector2(_rng.randf_range(YARD.position.x + 1.0, YARD.end.x - 1.0), _rng.randf_range(YARD.position.y + 0.8, YARD.end.y - 0.8))
		var d := c.distance_to(Vector2(chaser_m.p.x, chaser_m.p.y)) - 0.3 * c.distance_to(me)
		if d > bd:
			bd = d
			best = c
	return best


## Walks toward `tgt` with the town's path finder (a new path when the target moved far); stands still when there is none.
func _move(m: Dictionary, tgt: Vector2, speed: float, dt: float) -> void:
	var p = m.p
	p.work = ""
	var me := Vector2(p.x, p.y)
	if tgt == Vector2.INF or me.distance_to(tgt) < 0.12:
		p.moving = false
		m.ktgt = tgt
		return
	if (m.ktgt as Vector2).distance_to(tgt) > 0.7 or (m.kpath as Array).is_empty():
		m.kpath = sim.path_p.find(world.solid_p, p.x, p.y, tgt.x, tgt.y)
		m.kpi = 0
		m.ktgt = tgt
	var path: Array = m.kpath
	var pi: int = int(m.get("kpi", 0))
	while pi < path.size() and me.distance_to(Vector2(path[pi])) < 0.12:
		pi += 1
	m.kpi = pi
	if pi >= path.size():
		p.moving = false
		m.kpath = []
		return
	var to: Vector2 = Vector2(path[pi]) - me
	var step := minf(to.length(), speed * dt)
	var dir := to.normalized()
	p.x += dir.x * step
	p.y += dir.y * step
	p.facing = sim.facing_of(dir.x, dir.y, p.facing)
	p.moving = true
	p.walk_phase += dt * (6.0 + speed)


## The chalk court and the ball, in the overlay's world pixels (`tile` px a tile).
func draw(c: CanvasItem, tile: float) -> void:
	var chalk := Color(0.95, 0.95, 0.9, 0.55)
	for k in COURT.size():
		var q: Vector2 = COURT[k]
		c.draw_rect(Rect2((q - Vector2(0.45, 0.45)) * tile, Vector2(0.9, 0.9) * tile), chalk, false, 2.0)
	c.draw_circle(ball * tile + Vector2(0, 3), 7.0, Color(0, 0, 0, 0.25))
	c.draw_circle(ball * tile, 7.0, Color(0.85, 0.3, 0.25))
	c.draw_arc(ball * tile, 7.0, 0.3, 2.6, 8, Color(1, 1, 1, 0.8), 2.0)
	var font := ThemeDB.fallback_font
	for f in floaters:
		c.draw_string(font, Vector2(f.pos) * tile + Vector2(-30, -float(f.t) * 20.0), String(f.text), HORIZONTAL_ALIGNMENT_CENTER, 60, 17, Color(1, 1, 0.8, 1.0 - float(f.t) / 1.2))
