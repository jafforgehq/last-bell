## The dead of the whole town as DATA, and the few near the player as the real thing (feature/town-core).
##
## Every dead one of the town is a record in a struct of arrays (position, kind, look, hit points, stands/wanders) and, while it is dormant, in a
## cell of a spatial hash (CELL x CELL tiles) too. Nothing of a dormant one is simulated, drawn or counted by the rules. WAKING: every `EVERY`
## seconds the cells near the player are looked through; a dormant one nearer than WAKE_R becomes a real `Sim.Zombie` (`sim.spawn`: the very type the
## rules, the shooting, the drawing and the kill count already use), the nearest first, never more than `active_cap` of them at once (the rest wait
## until there is room: the farthest wake later). A shot or a shout (`noise`, NOISE_R) wakes them in a larger circle AND sends them after the
## player; a light (`light`) wakes them in its own radius and leaves them wandering. SLEEPING: a real one that is not after anybody and is farther
## than SLEEP_R from every living person goes back to a record (its place and hit points kept) and its Zombie is dropped. One that was shot
## dead is marked killed for good (a record never wakes twice).
##
## The two radii are far apart on purpose (hysteresis): nobody wakes and sleeps on the same step as they walk.
extends RefCounted

const KIND_NAMES := ["walker", "runner", "brute"]
const CELL := 16
## THE NUMBERS (One House, WP8: tools/house_lab.gd found that the first ones, a shot heard at 30 tiles that woke every dead one in it and sent them all after the shooter, with wake_r 28,
## made every walk to a survivor deadly: at the integration tip the bot got a claim before noon in 8 of 8 seeds and four rescues in 0 of 8, and lost all eight). The defaults here are the
## lab's and `apply_tuning` reads the `field` block of assets/data/one_house_tuning.json over them (the bot's first attack held in 4 of 8 seeds at wake_r 12, 6 at 11, 7 at 10 and 9). WAKING
## by proximity: `wake_r` 10 tiles by day, `night_wake` 1.8 times that from dusk to dawn (TownSim sets `night_mult`), halved for one in a house the person is not in. A SHOT is heard within a radius by gun (`noise_by_gun`: the shotgun 16 tiles, the other guns 12, a blow 4,
## a third of it from inside a house: TownSim `_shot_noise`), at most `noise_cap` (4; 6 held the bot's first attack in 17 of 24 seeds, 4 with two more medicine at the start in 21) of the dead are drawn by one shot, the nearest first (those behind the walls of a house the shot was
## not fired in hear it as if MUFFLE times farther), and they go to the spot the shot came from to look (`investigate`, a wanderer's pace): they are not told where the shooter is, they
## find them by sight within 7 tiles (TownSim `_notice`).
const WAKE_R := 10.0
const SLEEP_R := 22.0
const NOISE_R := 16.0
const NOISE_CAP := 4
const MUFFLE := 1.35
const NOISE_BY_GUN := {"shotgun": 16.0, "other": 12.0, "melee": 4.0}
## The multiplier of the wake radius from dusk to dawn (the dark carries sound and the streets are not safe in it).
const NIGHT_WAKE := 1.8
const EVERY := 0.25
## The most dead the periodic look wakes at once (a street of sixty woken in one step is sixty path searches and sixty new pictures in one frame: they come over a few passes, the
## nearest first). A shout or a shot is not held to it: its dead have their own spread (`start_chase`).
const WAKE_PER_PASS := 12
## A dead one that stands inside a house the avatar is not in wakes at this share of the radius (walls: they do not see or hear you): a noise or a light is another matter.
const INDOOR_SHARE := 0.5
const DORMANT := 0
const ACTIVE := 1
const KILLED := 2

var sim
## The town's tile_house and tile_room arrays (scripts/town/town_gen.gd): which house and room a point is in, for "how many dead are left in this room".
var tile_house := PackedInt32Array()
var tile_room := PackedInt32Array()
var W := 0
var H := 0
var cols := 0
var rows := 0
var active_cap := 100
var wake_r := WAKE_R
var sleep_r := SLEEP_R
var noise_r := NOISE_R
var noise_cap := NOISE_CAP
var noise_by_gun: Dictionary = NOISE_BY_GUN.duplicate()
## What `night_mult` is from dusk to dawn (TownSim sets `night_mult` from the phase).
var night_wake := NIGHT_WAKE
## True while the night belongs to the wave (the base is under attack): no dormant one wakes, whatever wakes them (OneHouse sets it).
var pause_wake := false
## The wake radius is multiplied by this (1.0 by day; the dark carries sound and the streets are not safe: 1.4 at night, set by whoever knows the hour).
var night_mult := 1.0
## What a noise's radius is multiplied by: 1.0, and 0.8 while it rains (RAIN: scripts/town/skies.gd sets it every step; the rain covers a shot).
var noise_mult := 1.0
## PRISON (round 12): when set, every noise is handed to this callable (at, prey, radius) instead of the rules below (scripts/prison/prison_noise.gd). Nothing else sets it.
var noise_hook := Callable()
## The records (index = id).
var n := 0
var xs := PackedFloat32Array()
var ys := PackedFloat32Array()
var kind := PackedByteArray()
var look := PackedByteArray()
var hp := PackedFloat32Array()
var stands := PackedByteArray()    # 1 stands still until it notices, 0 wanders
var status := PackedByteArray()
## Dormant records by cell: Array of PackedInt32Array.
var cells: Array = []
var active_of := {}    # record id -> Zombie
var rec_of := {}       # Zombie -> record id
var _t := 0.0
## Counters for the overlay and the measurements.
var woke_total := 0
var slept_total := 0
var killed_total := 0
var wake_usec := 0
var sleep_usec := 0
var last_wake_n := 0
var deferred := 0    # candidates in range that the cap held back at the last look


func setup(s, town: Dictionary = {}) -> void:
	sim = s
	if not town.is_empty():
		tile_house = town.tile_house
		tile_room = town.tile_room
	W = int(s.W)
	H = int(s.H)
	cols = ceili(float(W) / float(CELL))
	rows = ceili(float(H) / float(CELL))
	cells.clear()
	for i in cols * rows:
		cells.append(PackedInt32Array())


## The records the town generator made ({pos, kind, state}): every one dormant.
func load_records(dead: Array) -> void:
	n = dead.size()
	xs.resize(n)
	ys.resize(n)
	kind.resize(n)
	look.resize(n)
	hp.resize(n)
	stands.resize(n)
	status.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var nlooks: int = sim.looks.size()
	for i in n:
		var r: Dictionary = dead[i]
		var p: Vector2 = r.pos
		xs[i] = p.x
		ys[i] = p.y
		kind[i] = maxi(0, KIND_NAMES.find(String(r.kind)))
		look[i] = rng.randi() % nlooks
		hp[i] = 0.0    # 0: a fresh one, its hit points are rolled when it wakes
		stands[i] = 1 if String(r.get("state", "still")) == "still" else 0
		status[i] = DORMANT
		cells[_cell(p.x, p.y)].append(i)


## One more record at the end of the list (the scenario's: the lone dead one on the road in, which the generator does not place), dormant, a fresh one (`stand`: it stands still until it
## notices somebody, else it wanders). Returns its id. Its look is a function of its id, so a run makes the same one every time; the save holds it with the others.
func add_record(at: Vector2, kind_name: String = "walker", stand: bool = true) -> int:
	var i := n
	n += 1
	xs.resize(n)
	ys.resize(n)
	kind.resize(n)
	look.resize(n)
	hp.resize(n)
	stands.resize(n)
	status.resize(n)
	xs[i] = at.x
	ys[i] = at.y
	kind[i] = maxi(0, KIND_NAMES.find(kind_name))
	look[i] = (i * 7 + 3) % maxi(sim.looks.size(), 1)
	hp[i] = 0.0
	stands[i] = 1 if stand else 0
	status[i] = DORMANT
	cells[_cell(at.x, at.y)].append(i)
	return i


## Takes a dormant record out of the town for good (it is never woken, never counted; the same as one that was shot, without the count of the kills). False for one that is not dormant.
func remove_record(i: int) -> bool:
	if i < 0 or i >= n or status[i] != DORMANT:
		return false
	var cell_id := _cell(xs[i], ys[i])
	var cell: PackedInt32Array = cells[cell_id]
	var at := cell.find(i)
	if at >= 0:
		cell[at] = cell[cell.size() - 1]
		cell.resize(cell.size() - 1)
		cells[cell_id] = cell
	status[i] = KILLED
	return true


func _cell(x: float, y: float) -> int:
	return clampi(floori(y / float(CELL)), 0, rows - 1) * cols + clampi(floori(x / float(CELL)), 0, cols - 1)


# ------------------------------------------------------------------ counting --

## Where a record is now: the real one's place while it is awake, its own while it sleeps.
func _place_of(i: int) -> Vector2:
	if status[i] == ACTIVE and active_of.has(i):
		var z = active_of[i]
		return Vector2(z.x, z.y)
	return Vector2(xs[i], ys[i])


## {"total", "dormant", "active", "left"} of the dead that stand in a house now ("left" counts the dormant and the awake that are not dying: what is
## left to clear), by where they are, not where they began.
func dead_in_house(house_id: int) -> Dictionary:
	return _count_where(tile_house, house_id)


func dead_in_room(room_idx: int) -> Dictionary:
	return _count_where(tile_room, room_idx)


func house_cleared(house_id: int) -> bool:
	return int(dead_in_house(house_id).left) == 0


func _count_where(tiles: PackedInt32Array, which: int) -> Dictionary:
	var out := {"total": 0, "dormant": 0, "active": 0, "left": 0}
	if tiles.is_empty():
		return out
	for i in n:
		if status[i] == KILLED:
			continue
		var p := _place_of(i)
		var tx := floori(p.x)
		var ty := floori(p.y)
		if tx < 0 or ty < 0 or tx >= W or ty >= H or tiles[ty * W + tx] != which:
			continue
		out.total += 1
		out.left += 1
		if status[i] == ACTIVE:
			out.active += 1
		else:
			out.dormant += 1
	return out

func count(which: int) -> int:
	var c := 0
	for i in n:
		if status[i] == which:
			c += 1
	return c


## {"dormant", "active", "killed"}: active is the records that are real now (not the sim's whole crowd, which holds the corpses too).
func counts() -> Dictionary:
	var d := 0
	var k := 0
	for i in n:
		match int(status[i]):
			DORMANT:
				d += 1
			KILLED:
				k += 1
	return {"dormant": d, "active": active_of.size(), "killed": k}


# -------------------------------------------------------------------- the step --

## Called every step with the places of the living (the player's first): looks only every EVERY seconds.
func update(dt: float, anchors: Array) -> void:
	_t -= dt
	if _t > 0.0 or anchors.is_empty():
		return
	_t = EVERY
	_collect_killed()
	var t_in := Time.get_ticks_usec()
	_sleep_far(anchors)
	sleep_usec += Time.get_ticks_usec() - t_in
	t_in = Time.get_ticks_usec()
	_wake_near(Vector2(anchors[0]), wake_r * night_mult, "", null, true, WAKE_PER_PASS)
	wake_usec += Time.get_ticks_usec() - t_in


## The dead that the player shot: their records are closed for good and the link is let go (the corpse is the sim's).
func _collect_killed() -> void:
	for z in rec_of.keys():
		if z.state == "dying" or z.state == "dead":
			var i: int = rec_of[z]
			status[i] = KILLED
			active_of.erase(i)
			rec_of.erase(z)
			killed_total += 1


func _sleep_far(anchors: Array) -> void:
	for z in rec_of.keys():
		# (the colony's dawn sweep sends the dead back to the city: a record's dead one just goes back to its record, where it stands)
		if z.state == "retreat":
			_sleep(z)
			continue
		if z.state == "chase" or z.state == "hunt" or z.state == "attack" or z.state == "dying" or z.state == "dead":
			continue
		var near := INF
		for a in anchors:
			var d: float = Vector2(a).distance_to(Vector2(z.x, z.y))
			if d < near:
				near = d
		if near > sleep_r:
			_sleep(z)


func _sleep(z) -> void:
	var i: int = rec_of[z]
	xs[i] = z.x
	ys[i] = z.y
	hp[i] = z.hp
	stands[i] = 1 if z.state == "still" else 0
	status[i] = DORMANT
	cells[_cell(z.x, z.y)].append(i)
	active_of.erase(i)
	rec_of.erase(z)
	z.remove = true
	slept_total += 1


## Wakes the dormant records within `radius` of `at` (nearest first, up to the cap). `chase_prey` (a Person) sends them after that person.
func _wake_near(at: Vector2, radius: float, cause: String, chase_prey = null, walls := false, most: int = 100000) -> int:
	if pause_wake:
		return 0
	var c0 := clampi(floori((at.x - radius) / float(CELL)), 0, cols - 1)
	var c1 := clampi(floori((at.x + radius) / float(CELL)), 0, cols - 1)
	var r0 := clampi(floori((at.y - radius) / float(CELL)), 0, rows - 1)
	var r1 := clampi(floori((at.y + radius) / float(CELL)), 0, rows - 1)
	var cand: Array = []
	var r2 := radius * radius
	var in_house := -1
	if walls and not tile_house.is_empty():
		in_house = _house_at(at.x, at.y)
	var ri2 := r2 * INDOOR_SHARE * INDOOR_SHARE
	for cy in range(r0, r1 + 1):
		for cx in range(c0, c1 + 1):
			var cell: PackedInt32Array = cells[cy * cols + cx]
			for i in cell:
				var dx := xs[i] - at.x
				var dy := ys[i] - at.y
				var d2 := dx * dx + dy * dy
				if d2 < r2:
					if walls and d2 >= ri2 and not tile_house.is_empty():
						var h := _house_at(xs[i], ys[i])
						if h >= 0 and h != in_house:
							continue
					cand.append([d2, i])
	var room := active_cap - active_of.size()
	deferred = maxi(0, cand.size() - maxi(0, room))
	if cand.is_empty() or room <= 0:
		return 0
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var woke := 0
	for k in mini(mini(room, most), cand.size()):
		_wake(int(cand[k][1]), chase_prey)
		woke += 1
	last_wake_n = woke
	return woke


func _house_at(x: float, y: float) -> int:
	var tx := floori(x)
	var ty := floori(y)
	if tx < 0 or ty < 0 or tx >= W or ty >= H:
		return -1
	return tile_house[ty * W + tx]


## Wakes every dormant one inside a house (the avatar has opened its door, a clear-the-house order): they wander, or go after `prey` when one is given.
func wake_house(house_id: int, prey = null) -> int:
	var woke := 0
	for i in n:
		if status[i] != DORMANT or _house_at(xs[i], ys[i]) != house_id:
			continue
		if active_of.size() >= active_cap:
			break
		_wake(i, prey)
		woke += 1
	return woke


func _wake(i: int, chase_prey = null):
	var cell_id := _cell(xs[i], ys[i])
	var cell: PackedInt32Array = cells[cell_id]
	var at := cell.find(i)
	if at >= 0:
		cell[at] = cell[cell.size() - 1]
		cell.resize(cell.size() - 1)
		cells[cell_id] = cell
	var z = sim.spawn(xs[i], ys[i], "wander", String(KIND_NAMES[kind[i]]))
	z.look_index = int(look[i])
	z.look = sim.looks[z.look_index]
	if hp[i] > 0.0:
		z.hp = hp[i]
	z.state = "still" if stands[i] == 1 else "wander"
	status[i] = ACTIVE
	active_of[i] = z
	rec_of[z] = i
	woke_total += 1
	if chase_prey != null:
		sim.start_chase(z, chase_prey)
	return z


## The adaptive cap went down (scripts/town/town_perf.gd): the awake dead above `cap` that are not after anybody go back to sleep, the farthest from the player first.
## Returns how many. (The ones that chase, attack or are dying stay: the cap holds back new wakes from now on.)
func trim(cap: int) -> int:
	var extra := active_of.size() - cap
	if extra <= 0:
		return 0
	var me = sim.avatar.player() if sim.get("avatar") != null else null
	var at := Vector2(me.x, me.y) if me != null else Vector2.ZERO
	var cand: Array = []
	for z in rec_of.keys():
		if z.state == "wander" or z.state == "still":
			cand.append([Vector2(z.x, z.y).distance_squared_to(at), z])
	cand.sort_custom(func(a, b): return a[0] > b[0])
	var put := 0
	for k in mini(extra, cand.size()):
		_sleep(cand[k][1])
		put += 1
	return put


## How far a shot of this person's gun is heard: by the gun ("shotgun"), a blow (a gun that is melee) and every other gun.
func noise_radius_for(p) -> float:
	var gun: Dictionary = sim.gun_of(p) if sim != null else {}
	if bool(gun.get("melee", false)):
		return float(noise_by_gun.get("melee", 4.0))
	if gun.has("noise"):    # (a gun's own radius: the prison game's guns)
		return float(gun.noise)
	return float(noise_by_gun.get(String(p.weapon), noise_by_gun.get("other", 12.0)))


## A shot or a shout at `at`: the dead that stand or wander within `radius` (the awake) and those that sleep within it (their records) hear it, at most `noise_cap` of them, the nearest
## first (a dead one in a house the shot was not fired in is heard as if it were MUFFLE times farther), and go to `at` to look, at a wanderer's pace. They are not told who fired:
## whoever they see on the way, they go after (TownSim `_notice`). `prey` is only the shooter, kept for the old callers.
func noise(at: Vector2, prey, radius: float = -1.0) -> void:
	if noise_hook.is_valid():
		noise_hook.call(at, prey, radius)
		return
	var r := (noise_r if radius < 0.0 else radius) * noise_mult
	var t_in := Time.get_ticks_usec()
	var in_house := _house_at(at.x, at.y) if not tile_house.is_empty() else -1
	var cand: Array = []    # [distance as heard, Zombie or null, record or -1]
	for z in sim.zombies:
		if z.state != "still" and z.state != "wander":
			continue
		var d := Vector2(z.x - at.x, z.y - at.y).length()
		if d < r * MUFFLE:
			var heard := _muffled(z.x, z.y, in_house, d)
			if heard < r:
				cand.append([heard, z, -1])
	if not pause_wake:
		var c0 := clampi(floori((at.x - r * MUFFLE) / float(CELL)), 0, cols - 1)
		var c1 := clampi(floori((at.x + r * MUFFLE) / float(CELL)), 0, cols - 1)
		var r0 := clampi(floori((at.y - r * MUFFLE) / float(CELL)), 0, rows - 1)
		var r1 := clampi(floori((at.y + r * MUFFLE) / float(CELL)), 0, rows - 1)
		for cy in range(r0, r1 + 1):
			for cx in range(c0, c1 + 1):
				for i in cells[cy * cols + cx]:
					var d := Vector2(xs[i] - at.x, ys[i] - at.y).length()
					if d >= r * MUFFLE:
						continue
					var heard := _muffled(xs[i], ys[i], in_house, d)
					if heard < r:
						cand.append([heard, null, int(i)])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var room := maxi(0, active_cap - active_of.size())
	var drawn := 0
	for e in cand:
		if drawn >= noise_cap:
			break
		var z = e[1]
		if z == null:
			if room <= 0:
				continue
			z = _wake(int(e[2]))
			room -= 1
		_investigate(z, at)
		drawn += 1
	wake_usec += Time.get_ticks_usec() - t_in


## The distance a sound at `d` tiles is heard as by a dead one at (x, y): farther if it stands in a house the sound did not start in.
func _muffled(x: float, y: float, in_house: int, d: float) -> float:
	if not tile_house.is_empty():
		var h := _house_at(x, y)
		if h >= 0 and h != in_house:
			return d * MUFFLE
	return d


## Sends one of the dead to look at `at`: a wanderer's walk to it (the colony's own `wander` arm follows the path), and a long time before it picks another place.
func _investigate(z, at: Vector2) -> void:
	z.state = "wander"
	z.hunt_id = ""
	z.path = sim.path_z.find(sim.world.solid_z, z.x, z.y, at.x, at.y)
	z.path_i = 0
	z.wander_t = 90.0


## The `field` block of the tuning file (assets/data/one_house_tuning.json, read by TownSim when the sim is made): wake_r, noise_r, sleep_r, active_cap, noise_cap, night_wake and
## noise_by_gun ({"shotgun", "other", "melee"}). A key that is not there keeps the default. (`active_cap` is the platform's, scripts/town/town_perf.gd: only set when the file says so.)
func apply_tuning(d: Dictionary) -> void:
	for k in ["wake_r", "noise_r", "sleep_r", "night_wake"]:
		if d.has(k):
			set(k, float(d[k]))
	for k in ["active_cap", "noise_cap"]:
		if d.has(k):
			set(k, int(d[k]))
	if typeof(d.get("noise_by_gun")) == TYPE_DICTIONARY:
		for g in d.noise_by_gun:
			noise_by_gun[String(g)] = float(d.noise_by_gun[g])


## A light (a lamp, a fire, a torch beam) at `at`: the dormant within `radius` wake and wander, not after anybody.
func light(at: Vector2, radius: float) -> void:
	_wake_near(at, radius, "light")


# ------------------------------------------------------------------- the save --

## The dormant and killed records as flat integers (three each: x and y in tenths of a tile, and one word of kind, stands, look, hit points in
## halves), JSON-friendly, with a short header. The real ones are saved by the old way (`SaveGame`'s zombies) and are not here: a real one is
## put back to sleep before the save, `sleep_all`, so that the whole population is this one array.
func save() -> Dictionary:
	var flat: Array = []
	flat.resize(n * 3)
	for i in n:
		var word := int(kind[i]) | (int(stands[i]) << 2) | (int(look[i]) << 3) | (mini(255, roundi(hp[i] * 2.0)) << 8) | (int(status[i] == KILLED) << 16)
		flat[i * 3] = roundi(xs[i] * 10.0)
		flat[i * 3 + 1] = roundi(ys[i] * 10.0)
		flat[i * 3 + 2] = word
	return {"v": 1, "n": n, "r": flat}


func sleep_all() -> void:
	for z in rec_of.keys():
		if z.state == "dying" or z.state == "dead":
			continue
		_sleep(z)
	_collect_killed()


func load_state(d: Dictionary) -> void:
	var flat: Array = d.r
	n = int(d.n)
	xs.resize(n)
	ys.resize(n)
	kind.resize(n)
	look.resize(n)
	hp.resize(n)
	stands.resize(n)
	status.resize(n)
	for c in cells.size():
		cells[c] = PackedInt32Array()
	for i in n:
		var word := int(flat[i * 3 + 2])
		xs[i] = float(flat[i * 3]) / 10.0
		ys[i] = float(flat[i * 3 + 1]) / 10.0
		kind[i] = word & 3
		stands[i] = (word >> 2) & 1
		look[i] = (word >> 3) & 31
		hp[i] = float((word >> 8) & 255) / 2.0
		status[i] = KILLED if ((word >> 16) & 1) == 1 else DORMANT
		if status[i] == DORMANT:
			cells[_cell(xs[i], ys[i])].append(i)
	active_of.clear()
	rec_of.clear()
