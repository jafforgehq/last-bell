## The title screen's town: the cover of Thirty Bells. Behind the menu is a small town (the real generator, `blocks: 2`, 64 x 64 tiles, one fixed seed) at dusk, made and drawn by
## the real game's own parts (the world, the roofs, the pawns), so that the title and the game look like one thing. Nothing of the school is built for it.
##
##   THE SCENE    the start house in the middle of the picture, open as it is when you are in it (the roof off, the rooms seen: `HouseView.showcase`), a lamp lit in one room, Ruth at
##                a window looking out at the street, lit windows and a lit porch; every other house roofed and dark; a streetlamp that flickers; the long shadows of a low sun; a few of the
##                dead (`DEAD`) shuffling in the street and between the houses, some standing; parked cars; leaves on the wind; a column of smoke far off; now and then a few birds across
##                the sky; the dusk bell every 20 to 30 seconds (the soundscape's four tolls, and the bell on the menu swings and the screen's edges close in with each).
##   THE CAMERA   drifts slowly along the street, the house off to the right so that the menu has the left (`_camera`). `reduce motion` holds it, and the leaves, the birds, the fades and
##                the bell's swing still.
##   THE COST     the town is a tenth of the full one (about 0.1 s to make on a desktop, a stepped build behind the loading card in a window: ready in about a second), no school node is
##                built (`Main` leaves out the base's life), the lights are the glow layer's additive halos and warm washes over the lit rooms (a PointLight2D is a pass over what it touches:
##                seven of them were more than half of the frame, `--title-real=N` brings some back), the shadows are ONE mesh made once (a polygon each was a hundred draw calls), the leaves
##                are one MultiMesh, the birds and the smoke a few dozen primitives. Measured windowed on an M1: 60 fps at 1080p and 1440p, 180 draw calls. The rules' clock stands still at
##                dusk; the dead notice nobody (`TownSim.quiet`) and none is woken from its sleep.
##
## `Main` makes it when the real game shows its title (`wanted`: not `--school`, not the demo, not a test's stand-in scene), asks it for the town to build (`run_meta`), and for
## the rest of it only calls `begin`, `update` (every frame, which moves the camera), `after_lighting` and `glow_paint`. `--title-seed=N` shows another town (to choose by looking:
## 15 was chosen by screenshots of fifteen candidates, for the lit rooms, the crosswalk, the lamp and the red roof beside the house).
extends Node2D

const DrawNode := preload("res://scripts/render/draw_node.gd")
const LitterNode := preload("res://scripts/render/litter_node.gd")
const Prefs := preload("res://scripts/prefs.gd")
const Demo := preload("res://scripts/demo.gd")

const TILE := 64.0
## The town of the title: its seed, its size in blocks, the hour of its dusk.
const SEED := 15
const BLOCKS := 2
const HOUR := 19.2
## The colour of the evening over the whole picture (the sky's own at that hour is a salmon pink; this is deeper, a violet at the edges of day).
const SKY := Color(0.50, 0.53, 0.80)
## The colour of a shadow (a deep violet, alpha for how dark).
const SHADOW := Color(0.05, 0.03, 0.14, 0.30)
## How many of the lights are real PointLight2Ds (the rest are additive glows): none, see `_make_lights` (`--title-real=N` tries more).
const REAL_LIGHTS := 0
## How many of the dead walk the street (some of them stand), and how far from Ruth they are kept (tiles): she is in the picture to be looked at, not eaten.
const DEAD := 7
const DEAD_STILL := 2
const DEAD_KEEP_OFF := 7.5
## The slow drift of the camera along the street: how far it goes each way (tiles) and how long a round takes (seconds).
const DRIFT_TILES := 3.4
const DRIFT_S := 140.0
## The bell: seconds between tolls (the first, and then at random), and the four strikes of the soundscape's dusk bell (seconds from the first, how hard).
const FIRST_TOLL_S := 2.5
const TOLL_MIN_S := 20.0
const TOLL_MAX_S := 30.0
const STRIKES := [[0.0, 1.0], [1.9, 0.9], [3.9, 0.85], [6.2, 0.7]]
## The sun is low in the west: the shadows fall to the east and a little south, this many tiles for each tile of height.
const SUN := Vector2(1.0, 0.42)

var main
var sim
var world
var data: Dictionary
var town: Dictionary
## The animation clock (seconds; it stands still under "reduce motion").
var t := 0.0
## Where the picture is about: the middle of the street in front of the start house, and which way the street runs.
var focus := Vector2.ZERO
var axis := Vector2.RIGHT
var house_rect := Rect2()
var porch := Vector2.ZERO
var street_rect := Rect2()
var ruth

var _rng := RandomNumberGenerator.new()
var _radial: GradientTexture2D
var _lights: Array = []
var _windows: Array = []
var _lamps: Array = []
var _lamps_in: Array = []
var _lit_rooms: Array = []
var _real := REAL_LIGHTS
var _bell_asked := false
var _struck := 0
var _dead_start: Array = []
var _sky := SKY
var _off := {}
var _bench_s := 0.0
var _bench_from := 0
var _bench_last := 0
var _bench_frames: Array = []
var _bench_proc: Array = []
var _bench_calls: Array = []
var _bench_cpu := 0.0
var _bench_gpu := 0.0
var _stand := Vector2.ZERO
var _face := "S"
var _shadows: Node2D
var _fx: Node2D
var _litter
var _dead: Array = []
var _keep := Rect2()
var _keep_t := 0.0
var _toll_in := FIRST_TOLL_S
var _strikes: Array = []
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _fade_t := -1.0
var _birds: Array = []
var _birds_in := 9.0
var _age := 0.0
var _smoke_at := Vector2.ZERO


## Whether the real game's title is this town: the game's own scene (not a test's stand-in), showing its title, and not asked for the school's yard (`--school`) or the demo.
static func wanted(real: bool, args: Array, title_asked: bool) -> bool:
	return real and title_asked and not ("--school" in args) and not Demo.on()


## The seed of the town (`--title-seed=N` looks at another).
static func seed_of(args: Array) -> int:
	for a in args:
		var s := String(a)
		if s.begins_with("--title-seed=") and s.trim_prefix("--title-seed=").is_valid_int():
			return int(s.trim_prefix("--title-seed="))
	return SEED


## What `Main` hands the town's factory (scripts/town/town_boot.gd): the title's own town, small, with no pictures of the dead loaded ahead (`title`).
static func run_meta(args: Array) -> Dictionary:
	return {"title": true, "town": seed_of(args), "town_opts": {"blocks": BLOCKS}}


# ------------------------------------------------------------------- making it --

## The scene is made: the town is built, the rules are made and Ruth is in them. Everything of the title is put in the world here.
func begin(main_node) -> void:
	main = main_node
	sim = main.sim
	world = main.world
	data = main.data
	town = data.town_data
	name = "TitleScene"
	_rng.seed = int(town.get("seed", SEED)) * 977 + 31
	_read_flags()
	_clock()
	_quiet()
	_find_place()
	_place_ruth()
	_radial = _radial_texture()
	if not _off.has("lights"):
		_make_lights()
	if not _off.has("shadows"):
		_make_shadows()
	if not _off.has("leaves"):
		_make_leaves()
	if not _off.has("sky"):
		_make_fx()
	if not _off.has("dead"):
		_spawn_dead()
	if _shot() or _bench_s > 0.0:
		print("title scene: seed %d, house %d, windows %d, lamps in %d, lamps out %d, dead %d, lights %d (%d real)" % [int(town.get("seed", 0)), int(town.start.house), _windows.size(), _lamps_in.size(), _lamps.size(), _dead.size(), _lights.size(), _real])
	world.add_child(self)
	if not _off.has("glow"):
		main.glow.extras.append(glow_paint)
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 60
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.025, 0.02, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)
	main.add_child(_fade_layer)
	if _shot():
		_fade_layer.queue_free()
		_fade_layer = null
		_toll_in = 0.3 if _bell_asked else 1.0e9


## The screenshot flags: `--title-sky=r,g,b` (the colour of the evening, 0 to 1 each), `--title-off=lights,shadows,leaves,glow,dead,sky,showcase` (parts left out, to measure what each
## costs), `--title-real=N` (how many of the lights are PointLight2Ds), `--title-at=SECONDS` (the scene's clock begins there: another moment of the camera's drift) and
## `--title-bench=SECONDS` (a windowed run measures the frames of the title for that long, prints them and quits).
func _read_flags() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--title-bench="):
			_bench_s = float(s.trim_prefix("--title-bench="))
		elif s == "--title-bell":
			_bell_asked = true
		elif s == "--title-birds":
			_birds_in = 0.05
		elif s.begins_with("--title-real="):
			_real = int(s.trim_prefix("--title-real="))
		elif s.begins_with("--title-at="):
			t = float(s.trim_prefix("--title-at="))
		elif s.begins_with("--title-sky="):
			var c := s.trim_prefix("--title-sky=").split(",")
			if c.size() == 3:
				_sky = Color(float(c[0]), float(c[1]), float(c[2]))
		elif s.begins_with("--title-off="):
			for k in s.trim_prefix("--title-off=").split(","):
				_off[String(k)] = true


## The rules' clock stands still at dusk and the bell has rung (so it does not ring by itself and no banner is made).
func _clock() -> void:
	sim.min_per_sec = 0.0
	sim.day = 1
	sim.minutes = HOUR * 60.0
	sim.clock_min = fposmod(sim.minutes - 420.0, 1440.0)
	sim.phase = sim.seasons.phase_at(sim.minutes)
	sim.bell_rung = true


## The dead notice nobody and none wakes from its sleep: the street is the picture's, the rules' own dead are left where they lie.
func _quiet() -> void:
	sim.set("quiet", true)
	var field = sim.get("field")
	if field != null and "pause_wake" in field:
		field.pause_wake = true


func _shot() -> bool:
	return String(main.get("shot_path")) != ""


func _radial_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.72), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


## The start house, its door, the street it faces (the avenue, or the road nearest) and where the camera looks.
func _find_place() -> void:
	var h: Dictionary = town.houses[int(town.start.house)]
	var rect := Rect2(Rect2i(h.rect))
	house_rect = rect
	var door := Vector2(Vector2i(h.door)) + Vector2(0.5, 0.5)
	porch = door
	var road := Rect2()
	var best := INF
	for rd in town.streets.roads:
		var rr := Rect2(Rect2i(rd.rect))
		var d := rr.get_center().distance_to(door) - (6.0 if String(rd.kind) == "avenue" else 0.0)
		if d < best:
			best = d
			road = rr
			axis = Vector2.RIGHT if String(rd.dir) == "h" else Vector2.DOWN
	street_rect = road
	# the picture: the house and the street side by side, nearer the house
	var street_mid := road.get_center()
	if axis == Vector2.RIGHT:
		focus = Vector2(rect.get_center().x, lerpf(street_mid.y, rect.get_center().y, 0.6))
	else:
		focus = Vector2(lerpf(street_mid.x, rect.get_center().x, 0.6), rect.get_center().y)
	var size := Vector2(float(town.size.x), float(town.size.y))
	_keep = Rect2(focus - Vector2(34.0, 22.0), Vector2(68.0, 44.0)).intersection(Rect2(Vector2(3, 3), size - Vector2(6, 6)))
	_lamps.clear()
	for o in data.objects:
		if String(o.get("kind", "")) == "streetlamp":
			var p := Vector2(float(o.cx), float(o.cy))
			if _keep.has_point(p):
				_lamps.append(p)
	_lamps.sort_custom(func(a, b): return a.distance_to(focus) < b.distance_to(focus))
	var hid := int(town.start.house)
	_windows.clear()
	for w in data.kit.windows:
		if int(w.get("house", -1)) != hid or String(w.get("state", "")) != "intact":
			continue
		var at := Vector2(float(w.x) + 0.5, float(w.y) + 0.5)
		var out := Vector2.ZERO
		var vertical: bool = String(w.orient) == "v"
		if vertical:
			out = Vector2(signf(at.x - rect.get_center().x), 0.0)
		else:
			out = Vector2(0.0, signf(at.y - rect.get_center().y))
		_windows.append({"at": at, "out": out, "vertical": vertical, "k": _rng.randf() * 6.0})
	# the ones on the street's side first, then the ones far from each other
	var toward := Vector2(0.0, signf(street_mid.y - rect.get_center().y)) if axis == Vector2.RIGHT else Vector2(signf(street_mid.x - rect.get_center().x), 0.0)
	_windows.sort_custom(func(a, b): return a.out.dot(toward) > b.out.dot(toward))
	var picked: Array = []
	for w in _windows:
		var far := true
		for q in picked:
			if q.at.distance_to(w.at) < 3.2:
				far = false
		if far:
			picked.append(w)
		if picked.size() >= 3:
			break
	_windows = picked
	# the standing lamps of the house: its rooms are lit from inside
	_lamps_in.clear()
	for o in data.objects:
		if String(o.get("kit", "")) == "lamp_floor" and int(o.get("in", -1)) == hid:
			_lamps_in.append(Vector2(float(o.cx), float(o.cy)))
	if _lamps_in.size() > 3:
		_lamps_in.resize(3)


## Ruth stands at a window of her house, looking out at the street, and stays there. The house is shown open (the roof off, as it is when she is in it): `showcase`.
func _place_ruth() -> void:
	for p in sim.people:
		if String(p.id) == "ruth":
			ruth = p
	if ruth == null and not sim.people.is_empty():
		ruth = sim.people[0]
	_stand = porch
	_face = "N" if porch.y < street_rect.get_center().y else "S"
	if not _windows.is_empty():
		var w: Dictionary = _windows[0]
		_stand = w.at - w.out * 1.15
		_face = "N" if float(w.out.y) < 0.0 else ("S" if float(w.out.y) > 0.0 else ("E" if float(w.out.x) > 0.0 else "W"))
	var hv = main.town.part("house_view") if main.town != null else null
	if hv != null and "showcase" in hv and not _off.has("showcase"):
		hv.showcase = int(town.start.house)
	_pin_ruth()


func _pin_ruth() -> void:
	if ruth == null:
		return
	ruth.x = _stand.x
	ruth.y = _stand.y
	ruth.path = []
	ruth.moving = false
	ruth.facing = _face


## The lights of the evening: the windows, the porch, the lamps, in the order they matter. The first `_real` are PointLight2Ds of the one shared picture (they light what is under them,
## the textures and all); the rest are the glow layer's additive halos (`glow_paint`), which cost next to nothing: a PointLight2D is a pass over what it touches (measured on an M1 at
## 1080p: 7 of them were more than half of the frame), and a browser pays more for it.
func _make_lights() -> void:
	var list: Array = []
	var n := mini(_lamps.size(), 3)
	if n > 0:
		list.append({"at": _lamps[0], "color": Color8(255, 208, 140), "e": 0.78, "r": 6.5, "kind": "flicker", "k": 0.0})
	for i in _lamps_in.size():
		list.append({"at": _lamps_in[i], "color": Color8(255, 176, 100), "e": 0.62, "r": 5.4, "kind": "room", "k": float(i) * 1.3})
	for w in _windows:
		list.append({"at": w.at + w.out * 1.4, "color": Color8(255, 160, 80), "e": 0.42, "r": 3.8, "kind": "window", "k": w.k})
	list.append({"at": porch, "color": Color8(255, 190, 110), "e": 0.5, "r": 3.0, "kind": "porch", "k": 1.7})
	for i in range(1, n):
		list.append({"at": _lamps[i], "color": Color8(255, 208, 140), "e": 0.78, "r": 6.5, "kind": "lamp", "k": float(i) * 2.1})
	for i in list.size():
		_add_light(list[i], i < _real)
	# the rooms that have a lamp, or Ruth, are lit: their floors get a warm wash (the others stay in the blue of the evening)
	_lit_rooms.clear()
	var spots: Array = _lamps_in.duplicate()
	spots.append(_stand)
	var w_tiles := int(town.size.x)
	for p in spots:
		var i := floori(p.y) * w_tiles + floori(p.x)
		if i >= 0 and i < town.tile_room.size() and int(town.tile_room[i]) >= 0:
			var rect := Rect2(Rect2i(town.rooms[int(town.tile_room[i])].rect))
			if not _lit_rooms.has(rect):
				_lit_rooms.append(rect)


func _add_light(spec: Dictionary, real: bool) -> void:
	var l: PointLight2D = null
	if real:
		l = PointLight2D.new()
		l.texture = _radial
		l.texture_scale = float(spec.r) * 2.0 * TILE / 128.0
		l.position = Vector2(spec.at) * TILE
		l.color = spec.color
		l.energy = 0.0
		l.blend_mode = Light2D.BLEND_MODE_ADD
		l.shadow_enabled = false
		add_child(l)
	_lights.append({"node": l, "e": spec.e, "kind": spec.kind, "k": spec.k, "at": spec.at, "r": spec.r, "color": spec.color, "real": real})


## The long shadows of a low sun: the houses, the trees and the cars each throw one, made once as ONE mesh (one draw: a polygon each was a hundred).
func _make_shadows() -> void:
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for e in _shadow_polys():
		var poly: PackedVector2Array = e[0]
		var tri := Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			continue
		var base := verts.size()
		for p in poly:
			verts.append(p)
			cols.append(e[1])
		for k in tri:
			idx.append(base + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance2D.new()
	node.name = "Shadows"
	node.mesh = mesh
	node.scale = Vector2(TILE, TILE)
	node.z_index = 4
	add_child(node)
	_shadows = node


## The shadows as polygons in tiles: [[PackedVector2Array, Color], ...].
func _shadow_polys() -> Array:
	var out: Array = []
	var col := SHADOW
	for h in town.houses:
		var parts: Array = h.parts if h.has("parts") and not h.parts.is_empty() else [h.rect]
		var height := 3.4 if String(h.kind) in ["apartments", "church", "school", "warehouse", "supermarket"] else 2.6
		for pr in parts:
			# (the house that is shown open has no roof over its floor: its shadow is what falls outside it)
			_shadow_of_rect(out, Rect2(Rect2i(pr)), SUN * height, col, int(h.id) == int(town.start.house))
	for o in data.objects:
		var kit := String(o.get("kit", ""))
		var at := Vector2(float(o.cx), float(o.cy))
		if kit == "car":
			_shadow_of_rect(out, Rect2(at - Vector2(float(o.w), float(o.h)) * 0.5, Vector2(float(o.w), float(o.h))), SUN * 0.9, col)
		elif kit == "streetlamp":
			var side := Vector2(-SUN.y, SUN.x).normalized() * 0.06
			out.append([PackedVector2Array([at - side, at + side, at + side + SUN * 3.6, at - side + SUN * 3.6]), Color(col, col.a * 0.7)])
	for tr in data.trees:
		var base := Vector2(float(tr.x), float(tr.y))
		var pts := PackedVector2Array()
		for k in 10:
			var a := TAU * float(k) / 10.0
			pts.append(base + Vector2(cos(a), sin(a) * 0.75) * 0.8 + Vector2(0.0, -0.9))
			pts.append(base + Vector2(cos(a), sin(a) * 0.75) * 0.8 + Vector2(0.0, -0.9) + SUN * 2.7)
		var hull := Geometry2D.convex_hull(pts)
		if hull.size() >= 3:
			out.append([hull, Color(col, col.a * 0.8)])
	return out


func _shadow_of_rect(out: Array, r: Rect2, off: Vector2, col: Color, open: bool = false) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var all := PackedVector2Array()
	for p in pts:
		all.append(p)
		all.append(p + off)
	var hull := Geometry2D.convex_hull(all)
	if hull.size() < 3:
		return
	if open:
		for piece in Geometry2D.clip_polygons(hull, pts):
			if piece.size() >= 3:
				out.append([piece, col])
		return
	out.append([hull, col])


func _make_leaves() -> void:
	var area := _keep.grow(-4.0)
	_litter = LitterNode.new()
	add_child(_litter)
	_litter.setup(11, area)


func _make_fx() -> void:
	var node := DrawNode.new()
	node.name = "Sky"
	node.z_index = 9
	node.painter = _paint_sky
	add_child(node)
	_fx = node
	# the smoke of a chimney down the street, on the roof of a house some ten tiles along it (the nearest to that, not the start house)
	var best := INF
	_smoke_at = focus + axis * 11.0
	for h in town.houses:
		if int(h.id) == int(town.start.house):
			continue
		var rect := Rect2(Rect2i(h.rect))
		var c := rect.get_center()
		var along := (c - focus).dot(axis)
		var across := absf((c - focus).dot(Vector2(-axis.y, axis.x)))
		if along > 6.0 and along < 16.0 and across < 16.0 and absf(along - 11.0) < best:
			best = absf(along - 11.0)
			_smoke_at = rect.position + rect.size * Vector2(0.3, 0.25)


## The dead of the street: spread along it and between the houses, none near Ruth.
func _spawn_dead() -> void:
	_dead.clear()
	for i in DEAD:
		# (the first few walk the street in front of the house, the rest are among the yards beside it)
		var at := _free_spot(false, 1 if i < 4 else 2)
		if at == Vector2.INF:
			continue
		var z = sim.spawn(at.x, at.y, "still" if i % 3 == 2 and _still_count() < DEAD_STILL else "wander")
		z.facing = ["N", "E", "S", "W"][_rng.randi() % 4]
		_dead.append(z)


func _still_count() -> int:
	var n := 0
	for z in _dead:
		if z.state == "still":
			n += 1
	return n


## A tile of the street's ground or a yard (not a wall, not a house, not near Ruth, not near another of the dead), `Vector2.INF` when none is found. `where` 1 is the street's
## lanes, 2 the yards and alleys beside the house, 0 either. A new place is out of sight (`unseen`): the dead that left are put back where the camera is not looking.
func _free_spot(unseen: bool, where: int = 0) -> Vector2:
	var w := int(town.size.x)
	var seen := _view_rect().grow(2.0)
	var lanes := street_rect.grow(-1.0)
	var yards := house_rect.grow(9.0)
	for k in 120:
		var area := _keep
		var pick := where if where != 0 else (1 + (_rng.randi() % 2))
		if pick == 1:
			area = lanes.intersection(_keep.grow(0.0))
			if axis == Vector2.RIGHT:
				area = Rect2(Vector2(maxf(area.position.x, focus.x - 18.0), area.position.y), Vector2(minf(area.end.x, focus.x + 18.0) - maxf(area.position.x, focus.x - 18.0), area.size.y))
			else:
				area = Rect2(Vector2(area.position.x, maxf(area.position.y, focus.y - 12.0)), Vector2(area.size.x, minf(area.end.y, focus.y + 12.0) - maxf(area.position.y, focus.y - 12.0)))
		else:
			area = yards.intersection(_keep)
		if not area.has_area():
			continue
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if p.distance_to(porch) < DEAD_KEEP_OFF:
			continue
		if unseen and seen.has_point(p):
			continue
		if world.is_solid(world.solid_z, p.x, p.y):
			continue
		var i := floori(p.y) * w + floori(p.x)
		if int(town.tile_house[i]) >= 0:
			continue
		# (the way out must be open: a tile with a wall on each side is a yard behind a fence)
		if world.is_solid(world.solid_z, p.x + 1.0, p.y) and world.is_solid(world.solid_z, p.x - 1.0, p.y):
			continue
		var crowded := false
		for z in _dead:
			if Vector2(z.x, z.y).distance_to(p) < 4.0:
				crowded = true
		if crowded:
			continue
		return p
	return Vector2.INF


func _view_rect() -> Rect2:
	return main.view_rect() if main != null else Rect2()


# ------------------------------------------------------------------ every frame --

## One frame (`dt`: the real seconds): the clock of the scene, the camera, the lights, the dead, the bell, the sky.
func update(dt: float) -> void:
	_age += dt
	if not Prefs.on("ui", "reduce_motion"):
		t += dt
	_camera()
	_pin_ruth()
	_lights_step()
	_keep_the_dead(dt)
	_bell(dt)
	_fade_in(dt)
	if _litter != null:
		var calm := Prefs.on("ui", "reduce_motion")
		_litter.visible = not calm
		_litter.apply(t * 0.55, 0.0)
	_birds_step(dt)
	if _fx != null:
		_fx.queue_redraw()
	if _bench_s > 0.0:
		_bench_step()


## `--title-bench`: three seconds of warm-up, then the frame times (milliseconds between frames), the script time of a frame, the draw calls and the renderer's own times, for
## `_bench_s` seconds of the real clock; then the numbers, and the game quits.
func _bench_step() -> void:
	var now := Time.get_ticks_usec()
	if _bench_from == 0:
		if _age < 3.0:
			return
		_bench_from = now
		_bench_last = now
		RenderingServer.viewport_set_measure_render_time(main.get_viewport().get_viewport_rid(), true)
		_dead_start = []
		for z in _dead:
			_dead_start.append(Vector2(z.x, z.y))
		return
	_bench_frames.append(float(now - _bench_last) / 1000.0)
	_bench_last = now
	_bench_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_bench_calls.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	var vp: RID = main.get_viewport().get_viewport_rid()
	_bench_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	_bench_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	if float(now - _bench_from) / 1.0e6 >= _bench_s:
		var f := _bench_frames.duplicate()
		f.sort()
		var n := f.size()
		var sum := 0.0
		for x in f:
			sum += float(x)
		var proc := 0.0
		for x in _bench_proc:
			proc += float(x)
		var calls := 0.0
		var calls_max := 0.0
		for x in _bench_calls:
			calls += float(x)
			calls_max = maxf(calls_max, float(x))
		print("title bench: %d frames in %.1f s, %.1f fps, frame ms: mean %.2f, median %.2f, p95 %.2f, p99 %.2f, worst %.2f; script %.2f ms; render cpu %.2f ms, gpu %.2f ms; draw calls mean %.0f, most %.0f; window %s, ui scale %.2f" % [n, sum / 1000.0, 1000.0 * float(n) / sum, sum / float(n), float(f[n / 2]), float(f[int(0.95 * float(n))]), float(f[int(0.99 * float(n))]), float(f[n - 1]), proc / float(n), _bench_cpu / float(n), _bench_gpu / float(n), calls / float(n), calls_max, str(main.get_window().size), float(main.ui_scale_in_use())])
		var walked := 0.0
		var movers := 0
		for i in mini(_dead.size(), _dead_start.size()):
			var d := Vector2(_dead[i].x, _dead[i].y).distance_to(_dead_start[i])
			walked = maxf(walked, d)
			if d > 0.5:
				movers += 1
		var names: Array = []
		for c in main.world.get_children():
			names.append("%s(%d)" % [c.name, c.get_child_count()])
		print("title bench: the world's nodes: ", ", ".join(names), "; the game's: ", ", ".join(main.get_children().map(func(c): return String(c.name))))
		var music = main.get("music")
		var title_track = music.players.get("title") if music != null else null
		print("title bench: music mood '%s', title track %s at %.1f dB, bell strokes struck %d, dead that moved %d of %d (the farthest %.1f tiles), the camera at %s" % [String(music.mood) if music != null else "none", "playing" if title_track != null and title_track.playing else "silent", float(title_track.volume_db) if title_track != null else 0.0, _struck, movers, _dead.size(), walked, str(main.cam_center)])
		main.get_tree().quit()


## The drift of the camera along the street, with the house off to the right of the middle (the menu has the left of the window).
func _camera() -> void:
	var vp: Vector2 = main.get_viewport_rect().size
	var zoom: float = clampf(vp.x / 31.0, 30.0, 70.0)
	main.zoom_px = zoom
	var view_tiles: Vector2 = vp / zoom
	var s := sin(t * TAU / DRIFT_S)
	var swing := axis * s * DRIFT_TILES + Vector2(-axis.y, axis.x) * sin(t * TAU / (DRIFT_S * 0.61) + 1.3) * 0.8
	# (the picture sits right of the middle by the share of the window the menu's column takes)
	var shift := Vector2(view_tiles.x * 0.13, 0.0) if view_tiles.x / view_tiles.y > 1.2 else Vector2.ZERO
	main.cam_center = focus + swing - shift


## The evening over the picture, after the lighting has put the sky's own on the world.
func after_lighting(lighting) -> void:
	if lighting.modulate_node != null:
		lighting.modulate_node.color = _sky


## How far the evening's lights have come up (they come up over a couple of seconds behind the fade; a screenshot has them lit).
func _rise() -> float:
	return 1.0 if _shot() or Prefs.on("ui", "reduce_motion") else clampf((_age - 0.4) / 2.2, 0.0, 1.0)


func _lights_step() -> void:
	var rise := _rise()
	for l in _lights:
		var f := 1.0
		match String(l.kind):
			"flicker":
				f = _flicker(t + float(l.k))
			"window", "room":
				f = 0.94 + 0.06 * sin(t * 2.3 + float(l.k) * 3.0) * sin(t * 0.7 + float(l.k))
			"porch":
				f = 0.95 + 0.05 * sin(t * 1.9 + float(l.k))
			"lamp":
				f = 0.97 + 0.03 * sin(t * 3.1 + float(l.k))
		l.f = f
		var node = l.node
		if node != null:
			node.energy = float(l.e) * f * rise
			node.visible = node.energy > 0.01


## The old lamp: a restless glow, and now and then a stutter of dark.
static func _flicker(time: float) -> float:
	var base := 0.9 + 0.06 * sin(time * 7.3) + 0.04 * sin(time * 19.1)
	var cyc := fposmod(time, 11.0)
	if (cyc > 3.0 and cyc < 3.07) or (cyc > 3.16 and cyc < 3.2) or (cyc > 8.4 and cyc < 8.52):
		return base * 0.18
	if cyc > 8.6 and cyc < 8.7:
		return base * 0.55
	return base


## The glow layer's painter: the halos and the light on the grass, over the dark of the evening (tile units, additive).
func glow_paint(ci: CanvasItem, _radial_tex: Texture2D, _dark: float) -> void:
	var rise := _rise()
	# the rooms that are lit: a warm wash over the floor, under the halos
	var wash := 0.17 * rise * (0.96 + 0.04 * sin(t * 1.7))
	for r in _lit_rooms:
		ci.draw_rect(r, Color(1.0, 0.66, 0.36, wash))
	for l in _lights:
		var f: float = float(l.get("f", 1.0)) * rise
		var at: Vector2 = l.at
		# (a light that is a real PointLight2D needs only a little halo; one that is not is all the glow it has)
		var k := 0.5 if bool(l.real) else 1.0
		var rad: float = float(l.r)
		match String(l.kind):
			"window":
				_halo(ci, at, Vector2(rad * 0.9, rad * 0.6), Color8(255, 170, 80), 0.42 * f * k)
			"porch":
				_halo(ci, at, Vector2(rad * 0.9, rad * 0.9), Color8(255, 200, 130), 0.34 * f * k)
			"room":
				_halo(ci, at, Vector2(rad * 0.6, rad * 0.6), Color8(255, 176, 100), 0.42 * f * k)
			"flicker", "lamp":
				_halo(ci, at, Vector2(rad * 0.62, rad * 0.62), Color8(255, 214, 150), 0.42 * f * k)
				_halo(ci, at, Vector2(0.42, 0.42), Color8(255, 236, 190), 0.3 * f)


func _halo(ci: CanvasItem, at: Vector2, size: Vector2, color: Color, alpha: float) -> void:
	if alpha <= 0.002:
		return
	var c := color
	c.a = alpha
	ci.draw_texture_rect(_radial, Rect2(at - size, size * 2.0), false, c)


# --------------------------------------------------------------------- the dead --

## Every half second: a dead one that has gone too far, or too near Ruth, or that is no more, is put back where the camera does not look.
func _keep_the_dead(dt: float) -> void:
	_keep_t -= dt
	if _keep_t > 0.0:
		return
	_keep_t = 0.5
	for i in _dead.size():
		var z = _dead[i]
		var gone: bool = z.remove or z.state == "dead" or z.state == "dying" or not sim.zombies.has(z)
		var away := not _keep.has_point(Vector2(z.x, z.y))
		var near := Vector2(z.x, z.y).distance_to(porch) < DEAD_KEEP_OFF - 2.0
		if not (gone or away or near):
			continue
		var at := _free_spot(true)
		if at == Vector2.INF:
			continue
		if gone:
			z = sim.spawn(at.x, at.y, "wander")
			_dead[i] = z
		z.x = at.x
		z.y = at.y
		z.path = []
		z.path_i = 0
		z.state = "wander" if z.state != "still" else "still"


# ---------------------------------------------------------------------- the bell --

## The bell of the dusk, every twenty to thirty seconds: the soundscape's four tolls, the bell on the menu and the screen's breath with each of them.
func _bell(dt: float) -> void:
	_toll_in -= dt
	if _toll_in <= 0.0:
		_toll_in = _rng.randf_range(TOLL_MIN_S, TOLL_MAX_S)
		var snd = main.get("sound")
		if snd != null and snd.get("scape") != null and not _shot():
			snd.scape.ring("dusk", 0.7)
		for s in STRIKES:
			_strikes.append({"t": float(s[0]), "k": float(s[1])})
	var i := 0
	while i < _strikes.size():
		_strikes[i].t -= dt
		if _strikes[i].t <= 0.0:
			var k: float = _strikes[i].k
			_strikes.remove_at(i)
			_strike(k)
		else:
			i += 1


## Rings the bell now (a screenshot's `--title-bell`, and the schedule).
func ring_now() -> void:
	_toll_in = 0.0


func _strike(strength: float) -> void:
	_struck += 1
	var shell = main.get("shell")
	var title = shell.get("title") if shell != null else null
	if title != null and title.has_method("on_toll"):
		title.on_toll(strength)


## The picture comes up out of the dark once the loading card is gone.
func _fade_in(dt: float) -> void:
	if _fade_layer == null:
		return
	if _fade_t < 0.0:
		if main.get_node_or_null("TownLoading") != null:
			return
		_fade_t = 0.0
	_fade_t += dt
	var k := 1.0 if Prefs.on("ui", "reduce_motion") else clampf(_fade_t / 1.6, 0.0, 1.0)    # (no fades under reduce motion)
	_fade.color.a = 1.0 - k * k * (3.0 - 2.0 * k)
	if k >= 1.0:
		_fade_layer.queue_free()
		_fade_layer = null


# ----------------------------------------------------------------------- the sky --

## Birds across the evening: a few at a time, high up (a shadow far below them on the ground), now and then.
func _birds_step(dt: float) -> void:
	if Prefs.on("ui", "reduce_motion"):
		_birds.clear()
		return
	_birds_in -= dt
	if _birds_in <= 0.0:
		_birds_in = _rng.randf_range(35.0, 70.0)
		var from_left := _rng.randf() < 0.5
		var view: Rect2 = main.view_rect()
		var y := view.position.y + view.size.y * _rng.randf_range(0.15, 0.7)
		var n := 3 + _rng.randi() % 3
		for i in n:
			var x := (view.position.x - 4.0 - float(i) * 1.4) if from_left else (view.end.x + 4.0 + float(i) * 1.4)
			_birds.append({"p": Vector2(x, y + _rng.randf_range(-1.2, 1.2) + float(i) * 0.5), "v": Vector2(3.4 if from_left else -3.4, _rng.randf_range(-0.3, 0.3)), "ph": _rng.randf() * 6.0, "age": 0.0})
	var view2: Rect2 = main.view_rect().grow(6.0)
	var i := 0
	while i < _birds.size():
		var b: Dictionary = _birds[i]
		b.p += b.v * dt
		b.age += dt
		if not view2.has_point(b.p) and b.age > 2.0:
			_birds.remove_at(i)
		else:
			i += 1


func _paint_sky(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	_paint_smoke(ci)
	for b in _birds:
		_paint_bird(ci, b)


## The smoke of a chimney far off: puffs that rise (the picture is from above, so they grow and drift on the wind), pale grey in the evening.
func _paint_smoke(ci: CanvasItem) -> void:
	var life := 11.0
	var n := 14
	for k in n:
		var age := fposmod(t + float(k) * life / float(n), life)
		var u := age / life
		var at := _smoke_at + Vector2(-0.9, -0.6) * (u * 3.6) + Vector2(sin(age * 0.8 + float(k)) * 0.25, 0.0) * u
		var r := lerpf(0.3, 2.4, sqrt(u))
		var a := 0.5 * (1.0 - u) * (1.0 - u) * clampf(u * 6.0, 0.0, 1.0)
		ci.draw_texture_rect(_radial, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0.62, 0.58, 0.64, a))


func _paint_bird(ci: CanvasItem, b: Dictionary) -> void:
	var p: Vector2 = b.p
	var flap := sin(t * 11.0 + float(b.ph))
	var dir := signf(float(b.v.x))
	# the shadow on the ground, far below and behind the bird
	var sh := p + Vector2(1.6, 1.9)
	ci.draw_texture_rect(_radial, Rect2(sh - Vector2(0.5, 0.2), Vector2(1.0, 0.4)), false, Color(0.04, 0.02, 0.08, 0.34))
	var body := Color(0.10, 0.08, 0.1, 0.95)
	var span := 0.32 + 0.1 * flap
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0.22 * dir, 0.0), p + Vector2(-0.05 * dir, -span), p + Vector2(-0.2 * dir, -span * 0.7), p + Vector2(-0.05 * dir, 0.0)]), body)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0.22 * dir, 0.0), p + Vector2(-0.05 * dir, span), p + Vector2(-0.2 * dir, span * 0.7), p + Vector2(-0.05 * dir, 0.0)]), body)
	ci.draw_circle(p + Vector2(0.2 * dir, 0.0), 0.07, body)
