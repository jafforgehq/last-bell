## The yard's view of the buildings (round 6): the plots, the sites and the buildings, drawn from what `sim.build`
## says and from assets/data/building_art.json. In the world's space, over the ground and under the people.
## (Round 15: a plot is the home of one building and the Build screen marks it, `main.build_hover`, while that building's slip
## is pointed at or chosen; the art of each building is drawn from the middle of its home, as a plot's lot is three tiles by
## three, the back two rows its footprint.)
##
## - (Round 11, the cut: the yard is not covered in signs.) An empty plot is a dashed outline of its lot with a small
##   sign (a hammer on a plate) at its corner, the thing a click opens the Build screen on (`sim.build.sign_at`), and
##   it is drawn only when it is wanted: while the Build screen is open (`main.build_open`: every plot, in the HUD's
##   gold, and brightest for the one the screen points at, `main.build_hover`, {"plot": id}), for the one empty plot
##   nearest the pointer when it is within NEAR_PLOT tiles of it, for a plot with a site on it (faint, as ever), and
##   while `show_plots` (the --build-plots flag) keeps them lit. With the screen shut and the pointer far from every
##   plot the yard shows no sign at all. A plot with a building has neither, unless the screen is open or points at it.
## - A site is its scaffold (the art's `scaffold`: planks, crates and sandbags, a fuller heap as the work goes on)
##   with a thin bar above it that fills with the work done.
## - A finished building is its `props`. What lies on the ground (`flat`) is drawn under the people; what stands up is
##   drawn among them, sorted by its feet, so people walk behind a tower and in front of a bench.
## - (Round 9, the lots.) A wall plot across a street (a mouth, in a lot that is claimed) with no wall and no site is a dashed
##   line across the street in amber with the words "open street" on it, drawn while the Build screen is open or the pointer
##   is within NEAR_STREET tiles of it; one whose wall has fallen is the same in red, "wall down", and is always drawn. A site
##   on one is the heap of materials every few tiles along the street. The Build screen may point at a whole lot
##   (`main.build_hover`, {"lot": id}): every plot and mouth of it is lit, claimed or not.
## - The floodlights' lamps are PointLight2D nodes that burn while the building stands and it is dark; they do not go
##   out in a blackout (the building brings its own generator).
##
## The sprites are made once and made again only when a plot's building, site or stage of the scaffold changes (a
## load and a new run change them, so the node follows). Nothing here touches the rules; there is no randomness.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const Build := preload("res://scripts/sim/build.gd")
const Lighting := preload("res://scripts/render/lighting.gd")
const DrawNode := preload("res://scripts/render/draw_node.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

const TILE := GD.TILE
const OBJECTS := "res://assets/objects/"
## The sign's picture: the Build screen's own hammer, else the repair one.
const ICONS := ["res://assets/ui/icons/build.png", "res://assets/ui/icons/repair.png"]
## The HUD's gold, the paper white of its lettering, and the dark of its plates.
const GOLD := Color(0.941, 0.761, 0.29)
const PAPER := Color(0.93, 0.9, 0.82)
const PLATE := Color(0.043, 0.078, 0.067)
## How strong the outline of a lot is: the empty plot the pointer is near, a plot with a site's, any plot's while the
## screen is open or points at it, and the one it points at.
const ALPHA_NEAR := 0.55
const ALPHA_SITE := 0.3
const ALPHA_OPEN := 0.78
const ALPHA_HOVER := 1.0
## How much of a lot the lit outline fills with its colour.
const FILL_OPEN := 0.07
const FILL_HOVER := 0.16
## The dashes of an outline (tiles) and its width (screen pixels).
const DASH := 0.32
const GAP := 0.2
const LINE_PX := 2.0
const LINE_HOVER_PX := 3.2
## The sign's plate: its size in screen pixels at the usual zoom (it grows and shrinks a little with it).
const SIGN_PX_MIN := 11.0
const SIGN_PX_MAX := 16.0
const SIGN_SHARE := 0.3
## The sign of the empty plot the pointer is near, or of a site, in the plain yard is this strong (the screen's, full).
const SIGN_NEAR := 0.85
const SIGN_SITE := 0.62
## How near the pointer must be (tiles, to the edge of the lot) for the one empty plot nearest it to show its outline and
## its sign, and for an open street to show its line and its words.
const NEAR_PLOT := 3.0
const NEAR_STREET := 5.0
## The bar above a site: width (tiles, and never narrower than BAR_PX screen pixels), thickness (screen pixels), and
## how far above the lot's top edge it floats (tiles).
const BAR_TILES := 1.7
const BAR_PX := 48.0
const BAR_THICK_PX := 6.0
const BAR_LIFT := 0.5
## The crew builds by day only: a bar of a site at night is drawn in this colour (the work waits).
const BAR_WAITING := Color(0.5, 0.65, 0.79)
## A wall plot's open street: the amber of the HUD's warning and the red of its danger, the width of the line (screen pixels),
## the size of the words on it, and the tiles between two heaps of materials along a site across a street.
const OPEN_STREET := Color(0.91, 0.584, 0.227)
const WALL_DOWN := Color(0.878, 0.345, 0.29)
const STREET_PX := 3.0
const STREET_TEXT_PX := 13
const HEAP_EVERY := 3.5
## The floodlights burn from this darkness on (lighting.dark), at full from this much more.
const LAMP_FROM := 0.08
const LAMP_RAMP := 4.0
## A lamp's picture is made once per radius at this size.
const LIGHT_TEX := 128
## The glow round a lamp's head at night (tiles, and how bright), drawn on a layer of its own that the night does not darken.
const GLOW_R := 0.7
const GLOW_ALPHA := 0.45

static var _art_cache := {}
static var _light_tex := {}
static var _radial: Texture2D

var main
var sim
var lighting
## The plots' lit outlines are forced on (the --build-plots flag).
var show_plots := false
## Where the pointer is, in tiles: null reads it from the window; a test or a screenshot (--build-pointer) puts it somewhere.
var pointer = null
## What the last draw put on the screen and how often the sprites were made again, for the tests.
var drawn_outlines := 0
var drawn_signs := 0
var drawn_streets := 0
var drawn_bars := 0
var rebuilds := 0

var _art := {}
var _scaffold: Array = []
var _flat: Node2D
var _tall: Node2D
var _own_tall: Node2D
var _ground: Node2D
var _air: Node2D
var _glow: Node2D
var _sprites: Array = []
var _lights: Array = []
var _key := ""
## While the marks are being painted the pointer and the plot near it are asked once, not for every plot.
var _painting := false
var _pointer_now := Vector2.ZERO
var _near_now := ""
var _rules_build = null
var _dashes := {}
var _icon: Texture2D
var _t := 0.0


## `game` is main.gd (or a stand-in: it is only asked for build_open, build_hover, title_mode, tutorial and coach),
## `rules` the sim, `stand_in` the y-sorted node the people are in (so that tall props are sorted among them), and
## `light_rig` the lighting module (the floodlights follow how dark it is).
func setup(game, rules, stand_in: Node2D = null, light_rig = null) -> void:
	main = game
	sim = rules
	lighting = light_rig
	_load_art()
	_flat = Node2D.new()
	_flat.name = "Flat"
	_flat.z_index = 2
	add_child(_flat)
	if stand_in != null:
		_tall = stand_in
	else:
		_own_tall = Node2D.new()
		_own_tall.name = "Tall"
		_own_tall.z_index = 6
		_own_tall.y_sort_enabled = true
		add_child(_own_tall)
		_tall = _own_tall
	var ground := DrawNode.new()
	ground.name = "Plots"
	ground.z_index = 3
	ground.painter = _paint_ground
	add_child(ground)
	_ground = ground
	var air := DrawNode.new()
	air.name = "Bars"
	air.z_index = 9
	air.painter = _paint_air
	add_child(air)
	_air = air
	# the lamps' glow: additive, on a layer that follows the camera and is not darkened by the sky (as glow_node.gd's)
	var glow_layer := CanvasLayer.new()
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)
	var glow := DrawNode.new()
	glow.name = "Glow"
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = add
	glow.painter = _paint_glow
	glow_layer.add_child(glow)
	_glow = glow
	for path in ICONS:
		if ResourceLoader.exists(path):
			_icon = GD.tex(path)
			break
	_sync()


func _exit_tree() -> void:
	_forget()


func _load_art() -> void:
	var path: String = Build.art_path
	if not _art_cache.has(path):
		var out := {"buildings": {}, "scaffold": []}
		if FileAccess.file_exists(path):
			var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
			if raw is Dictionary:
				out.buildings = raw.get("buildings", {})
				out.scaffold = raw.get("scaffold", [])
		_art_cache[path] = out
	_art = _art_cache[path].buildings
	_scaffold = _art_cache[path].scaffold


## The art of a building (its props, solid, beds, lights), {} when it has none.
func art_of(building_id: String) -> Dictionary:
	return _art.get(building_id, {})


## Called each frame by main.gd after the lighting: makes the sprites again if a plot changed, moves the lights with
## the dark and asks for the marks to be drawn.
func update(t: float) -> void:
	_t = t
	_sync()
	_update_lights()
	if _ground != null:
		_ground.queue_redraw()
		_air.queue_redraw()
		_glow.queue_redraw()


# ----------------------------------------------------------------- the sprites --

## A line that says what stands on each plot and how far the scaffold of each site has come.
func _signature() -> String:
	var parts := PackedStringArray()
	for pl in sim.build.plots():
		var b := String(pl.building)
		var site: Dictionary = pl.site
		if b == "" and site.is_empty():
			continue
		parts.append("%s=%s/%s/%d" % [String(pl.id), b, String(site.get("building", "")), _stage_of(pl)])
	return "|".join(parts)


## Which stage of the scaffold a site has reached (-1 for a plot with no site).
func _stage_of(pl: Dictionary) -> int:
	if pl.site.is_empty():
		return -1
	var share: float = sim.build.progress_of(String(pl.id))
	for i in _scaffold.size():
		if share < float(_scaffold[i].get("upto", 1.01)):
			return i
	return maxi(0, _scaffold.size() - 1)


func _sync() -> void:
	if sim == null or sim.get("build") == null:
		return
	var key := _signature()
	if key == _key and sim.build == _rules_build:
		return
	_key = key
	_rules_build = sim.build
	_rebuild()


func _forget() -> void:
	for s in _sprites:
		if is_instance_valid(s):
			s.queue_free()
	_sprites.clear()
	for l in _lights:
		if is_instance_valid(l.node):
			l.node.queue_free()
	_lights.clear()


## Makes every sprite and lamp again from what stands on the plots.
func _rebuild() -> void:
	rebuilds += 1
	_forget()
	for pl in sim.build.plots():
		var origin := Vector2(pl.pos)
		var east := origin.x > 42.0
		var b := String(pl.building)
		if b != "":
			var art := art_of(b)
			for pr in art.get("props", []):
				_add_prop(pr, origin, east)
			for def in art.get("lights", []):
				_add_light(def, origin)
		elif not pl.site.is_empty():
			var own: Dictionary = art_of(String(pl.site.building))
			var stage := _stage_of(pl)
			var def: Dictionary = _scaffold[stage] if stage >= 0 and stage < _scaffold.size() else {}
			# a site far along shows the building it will be, faintly, under the heap of materials
			var ghost := float(def.get("ghost", 0.0))
			var props: Array = own.get("site", []) if own.has("site") else def.get("props", [])
			for at in _heaps(pl):
				if ghost > 0.0:
					for pr in own.get("props", []):
						var faint: Dictionary = pr.duplicate()
						faint["a"] = ghost
						_add_prop(faint, at, east)
				for pr in props:
					_add_prop(pr, at, east)


## Where a site's heap of materials stands: the middle of the plot, or, for a wall across a street, every few tiles along it.
func _heaps(pl: Dictionary) -> Array:
	var c := Vector2(pl.pos)
	if String(pl.get("kind", "")) != "mouth":
		return [c]
	var horizontal: bool = String(pl.get("dir", "h")) == "h"
	var length: float = float(pl.size.x) if horizontal else float(pl.size.y)
	var n := maxi(1, roundi(length / HEAP_EVERY))
	var out: Array = []
	for i in n:
		var off := (float(i) - float(n - 1) / 2.0) * (length / float(n))
		out.append(c + (Vector2(off, 0.0) if horizontal else Vector2(0.0, off)))
	return out


func _texture(file: String) -> Texture2D:
	var path := OBJECTS + file + ".png"
	if not ResourceLoader.exists(path):
		return null
	return GD.tex(path)


## One picture of a building or a site: `pr` is an entry of the art's props (see the file's _doc).
func _add_prop(pr: Dictionary, origin: Vector2, east: bool) -> void:
	var file := String(pr.get("e", pr.f)) if east else String(pr.f)
	var tex := _texture(file)
	if tex == null:
		return
	var w := float(pr.w)
	var h := float(pr.h)
	# where the feet are (the line people are sorted against): `sort` says it, or `foot` how far above the bottom edge
	var foot := float(pr.y) - float(pr.sort) if pr.has("sort") else float(pr.get("foot", 0.0))
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.flip_h = bool(pr.get("flip", false))
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	s.scale = Vector2(w * TILE / tw, h * TILE / th)
	s.offset = Vector2(-tw / 2.0, -th * (h - foot) / h)
	s.position = (origin + Vector2(float(pr.x), float(pr.y) - foot)) * TILE
	if pr.has("a"):
		s.modulate.a = float(pr.a)
	var parent: Node2D = _flat if bool(pr.get("flat", false)) else _tall
	parent.add_child(s)
	_sprites.append(s)


## How many sprites are up now, flat and standing (for the tests).
func sprite_count() -> int:
	return _sprites.size()


## The sprites of one kind, their picture's file name (for the tests).
func files() -> Array:
	var out: Array = []
	for s in _sprites:
		out.append(String(s.texture.resource_path).get_file().get_basename())
	return out


# ------------------------------------------------------------------- the lamps --

## The soft round picture of a lamp's light, made once for each radius (the lighting module's own falloff).
static func light_texture(radius: float) -> Texture2D:
	var key := int(round(radius * 10.0))
	if not _light_tex.has(key):
		_light_tex[key] = Lighting._light_texture({"x": 0.0, "y": 0.0, "r": radius}, LIGHT_TEX)
	return _light_tex[key]


func _add_light(def: Dictionary, origin: Vector2) -> void:
	var r := float(def.get("r", 6.0))
	var node := PointLight2D.new()
	node.texture = light_texture(r)
	node.texture_scale = r * 2.0 * TILE / float(LIGHT_TEX)
	node.position = (origin + Vector2(float(def.x), float(def.y))) * TILE
	var c: Array = def.get("color", [255, 238, 205])
	node.color = Color8(int(c[0]), int(c[1]), int(c[2]))
	node.blend_mode = Light2D.BLEND_MODE_ADD
	node.energy = 0.0
	node.visible = false
	add_child(node)
	_lights.append({"node": node, "energy": float(def.get("energy", 0.9)), "scale": node.texture_scale})


## How strongly the lamps burn now, 0 to 1: the dark of the sky (they are on from dusk), not the power: the
## floodlights have their own generator, so a blackout does not put them out.
func lamp_level() -> float:
	if lighting == null or not lighting.visible:
		return 0.0
	return clampf((float(lighting.dark) - LAMP_FROM) * LAMP_RAMP, 0.0, 1.0)


func lamp_count() -> int:
	return _lights.size()


## A soft round white spot, for the glow round a lamp.
static func radial_texture() -> Texture2D:
	if _radial == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_radial = t
	return _radial


## The glow of the lamps' heads: a spot of warm white on each lit lamp (drawn in tiles).
func _paint_glow(ci) -> void:
	var level := lamp_level()
	if level <= 0.02 or _lights.is_empty():
		return
	var fog: float = float(lighting.fog)
	var a := GLOW_ALPHA * level * lerpf(1.0, Lighting.FOG_LIGHT_ENERGY, fog)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	for l in _lights:
		var at: Vector2 = l.node.position / TILE
		ci.draw_texture_rect(radial_texture(), Rect2(at.x - GLOW_R, at.y - GLOW_R, GLOW_R * 2.0, GLOW_R * 2.0), false, Color(1.0, 0.93, 0.8, a))


func _update_lights() -> void:
	if _lights.is_empty():
		return
	var level := lamp_level()
	var fog: float = float(lighting.fog) if lighting != null else 0.0
	var energy_k := lerpf(1.0, Lighting.FOG_LIGHT_ENERGY, fog)
	var reach_k := lerpf(1.0, Lighting.FOG_LIGHT_REACH, fog)
	for l in _lights:
		var e := minf(1.0, float(l.energy) * level) * energy_k
		var node: PointLight2D = l.node
		node.energy = e
		node.texture_scale = float(l.scale) * reach_k
		node.visible = e > 0.01


# ----------------------------------------------------------------- what is said --

## `main.build_open` (the Build screen is up), or the flag that keeps the outlines lit.
func screen_open() -> bool:
	if show_plots:
		return true
	return main != null and bool(main.get("build_open"))


## The plot the Build screen points at ("" for none).
func hovered() -> String:
	var h = main.get("build_hover") if main != null else null
	return String(h.get("plot", "")) if h is Dictionary else ""


## The lot the Build screen points at as a whole ("" for none): its plots and mouths are lit, claimed or not.
func hovered_lot() -> String:
	var h = main.get("build_hover") if main != null else null
	return String(h.get("lot", "")) if h is Dictionary else ""


## Whether the Build screen points at this plot, or at the lot it belongs to.
func marked(pl: Dictionary) -> bool:
	if String(pl.id) == hovered():
		return true
	var lot := hovered_lot()
	return lot != "" and String(pl.get("lot", "")) == lot


## What a wall plot's street is now: "open" (no wall and no site), "down" (the wall has fallen), "" (a wall stands, or one is
## going up, or it is no wall plot at all).
func street_state(pl: Dictionary) -> String:
	if sim == null or String(pl.get("kind", "")) != "mouth":
		return ""
	if String(pl.building) == "":
		return "" if not pl.site.is_empty() else "open"
	var seg = sim.lots.segment_at(String(pl.id))
	return "down" if seg != null and int(seg.state) == 3 else ""


## Whether the plots' marks are drawn at all: not on the title, nor in the lesson (Orientation Day teaches the yard
## with nothing built).
func marks_wanted() -> bool:
	if main == null:
		return true
	if bool(main.get("title_mode")):
		return false
	return not (bool(main.get("tutorial")) and main.get("coach") != null)


## Where the pointer is, in tiles.
func pointer_tile() -> Vector2:
	if _painting:
		return _pointer_now
	if pointer is Vector2:
		return pointer
	if not is_inside_tree():
		return Vector2(-1000.0, -1000.0)
	return get_global_mouse_position() / float(TILE)


## How far a point is from a plot's lot (tiles): nothing inside it.
func gap(pl: Dictionary, at: Vector2) -> float:
	var d := (at - Vector2(pl.pos)).abs() - Vector2(pl.size) / 2.0
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()


## The empty plot nearest the pointer, when the pointer is within NEAR_PLOT tiles of its lot ("" for none). A plot with a
## building or a site on it is not asked: it has its own say, and would take the place of an empty one beside it.
func near_plot() -> String:
	if sim == null or sim.get("build") == null:
		return ""
	var at := pointer_tile()
	var best := ""
	var best_gap := NEAR_PLOT
	for pl in sim.build.plots():
		if pl.building != "" or not pl.site.is_empty():
			continue
		var g := gap(pl, at)
		if g <= best_gap:
			best_gap = g
			best = String(pl.id)
	return best


func _near() -> String:
	return _near_now if _painting else near_plot()


## How strong the outline of this plot is now (0 for none).
func outline_alpha(pl: Dictionary) -> float:
	if marked(pl):
		return ALPHA_HOVER
	if screen_open():
		return ALPHA_OPEN
	if pl.building != "":
		return 0.0
	if not pl.site.is_empty():
		return ALPHA_SITE
	if String(pl.get("kind", "")) == "mouth":
		return 0.0    # (a street open to the dead has its dashed line and its words, which say it: not a box round it as well)
	return ALPHA_NEAR if String(pl.id) == _near() else 0.0


## How strong the sign of this plot is (0 for none): the empty plot the pointer is near has one, and a site keeps its own.
func sign_alpha(pl: Dictionary) -> float:
	if marked(pl):
		return 1.0
	if screen_open():
		return 0.9
	if pl.building != "":
		return 0.0
	if not pl.site.is_empty():
		return SIGN_SITE
	return SIGN_NEAR if String(pl.id) == _near() else 0.0


## Whether an open street's line and words are drawn: the Build screen is open or points at it, or the pointer is within
## NEAR_STREET tiles of it. (A wall that is down is always drawn: the street is open and the dead come through it.)
func street_wanted(pl: Dictionary) -> bool:
	return screen_open() or marked(pl) or gap(pl, pointer_tile()) <= NEAR_STREET


func _screen_scale() -> float:
	if not is_inside_tree():
		return 0.4
	return maxf(get_viewport().get_canvas_transform().get_scale().x, 0.01)


## The dashes of a lot's outline, as segments in world pixels (made once for each plot).
func _dash_segments(pl: Dictionary) -> PackedVector2Array:
	var id := String(pl.id)
	if _dashes.has(id):
		return _dashes[id]
	var size := Vector2(pl.size)
	var c := Vector2(pl.pos)
	var corners := [c - size / 2.0, c + Vector2(size.x, -size.y) / 2.0, c + size / 2.0, c + Vector2(-size.x, size.y) / 2.0]
	var out := PackedVector2Array()
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var len := a.distance_to(b)
		var n := maxi(1, roundi(len / (DASH + GAP)))
		var step := len / float(n)
		var dir := (b - a) / len
		for j in n:
			var from := float(j) * step + GAP / 2.0
			out.append((a + dir * from) * TILE)
			out.append((a + dir * minf(from + step - GAP, len)) * TILE)
	_dashes[id] = out
	return out


func _paint_ground(ci) -> void:
	drawn_outlines = 0
	drawn_signs = 0
	drawn_streets = 0
	if sim == null or sim.get("build") == null or not marks_wanted():
		return
	var k := 1.0 / _screen_scale()
	_painting = false
	_pointer_now = pointer_tile()
	_near_now = near_plot()
	_painting = true
	for pl in sim.build.plots():
		var a := outline_alpha(pl)
		var strong := marked(pl)
		if a > 0.01:
			drawn_outlines += 1
			_paint_outline(ci, pl, a, strong, strong or screen_open(), k)
		var sa := sign_alpha(pl)
		if sa > 0.01:
			drawn_signs += 1
			_paint_sign(ci, pl, sa, strong or (screen_open() and sa > 0.5), k)
		_paint_street(ci, pl, k)
	_painting = false
	# a lot the screen points at that is not yet claimed: its plots and mouths are lit all the same
	var lot := hovered_lot()
	if lot != "" and sim.lots.on and not sim.lots.claimed(lot):
		var l: Dictionary = sim.lots.lot(lot)
		for id in l.get("plots", []) + l.get("mouths", []):
			var pl: Dictionary = sim.build.plot(String(id))
			if not pl.is_empty():
				drawn_outlines += 1
				_paint_outline(ci, pl, ALPHA_HOVER, true, true, k)


## The dashed outline of a lot, with its wash when it is lit.
func _paint_outline(ci, pl: Dictionary, a: float, strong: bool, lit: bool, k: float) -> void:
	var col := Color(GOLD, a) if lit else Color(PAPER, a)
	var size := Vector2(pl.size) * TILE
	if lit:
		var fill := FILL_HOVER if strong else FILL_OPEN
		ci.draw_rect(Rect2(Vector2(pl.pos) * TILE - size / 2.0, size), Color(GOLD, fill))
	ci.draw_multiline(_dash_segments(pl), col, (LINE_HOVER_PX if strong else LINE_PX) * k, true)


## A street that is open (no wall across it) or whose wall is down: a dashed line across it in amber (red for a wall that has
## fallen), with the words on a dark pill at its middle. In the world's pixels, the words in screen pixels.
func _paint_street(ci, pl: Dictionary, k: float) -> void:
	var state := street_state(pl)
	if state == "" or (state == "open" and not street_wanted(pl)):
		return
	var col := OPEN_STREET if state == "open" else WALL_DOWN
	var c := Vector2(pl.pos)
	var half := Vector2(pl.size) / 2.0
	var horizontal: bool = String(pl.get("dir", "h")) == "h"
	var a := c - (Vector2(half.x, 0.0) if horizontal else Vector2(0.0, half.y))
	var b := c + (Vector2(half.x, 0.0) if horizontal else Vector2(0.0, half.y))
	var len := a.distance_to(b)
	var n := maxi(1, roundi(len / (DASH + GAP)))
	var step := len / float(n)
	var dir := (b - a) / len
	var pts := PackedVector2Array()
	for j in n:
		var from := float(j) * step + GAP / 2.0
		pts.append((a + dir * from) * TILE)
		pts.append((a + dir * minf(from + step - GAP, len)) * TILE)
	var alpha := 0.9 if marked(pl) else 0.75
	ci.draw_multiline(pts, Color(col, alpha), STREET_PX * k, true)
	drawn_streets += 1
	var font: Font = Fonts.cond(700)
	var text := "open street" if state == "open" else "wall down"
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, STREET_TEXT_PX).x + 12.0
	var th := float(STREET_TEXT_PX) + 6.0
	ci.draw_set_transform(c * TILE, 0.0, Vector2(k, k))
	var box := Rect2(-tw / 2.0, -th / 2.0, tw, th)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PLATE, 0.86)
	sb.border_color = Color(col, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(th / 2.0))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, box)
	ci.draw_string(font, Vector2(-tw / 2.0, th / 2.0 - 5.0), text, HORIZONTAL_ALIGNMENT_CENTER, tw, STREET_TEXT_PX, PAPER)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The sign: a dark plate with the hammer on it, at the corner of the lot.
func _paint_sign(ci, pl: Dictionary, alpha: float, lit: bool, k: float) -> void:
	var at: Vector2 = sim.build.sign_pos(String(pl.id)) * TILE
	var px := clampf(SIGN_SHARE * TILE / k, SIGN_PX_MIN, SIGN_PX_MAX)    # screen pixels: TILE / k is how many a tile is
	var r := px * k
	var ring := Color(GOLD, alpha) if lit else Color(PAPER, alpha * 0.8)
	ci.draw_circle(at, r + 1.2 * k, Color(0.0, 0.0, 0.0, 0.35 * alpha))
	ci.draw_circle(at, r, Color(PLATE, 0.82 * alpha))
	ci.draw_arc(at, r, 0.0, TAU, 24, ring, 1.6 * k, true)
	if _icon != null:
		var half := r * 0.68
		ci.draw_texture_rect(_icon, Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), false, Color(GOLD, alpha) if lit else Color(PAPER, alpha))


func _paint_air(ci) -> void:
	drawn_bars = 0
	if sim == null or sim.get("build") == null or not marks_wanted():
		return
	var k := 1.0 / _screen_scale()
	var by_day := _day()
	for pl in sim.build.plots():
		if pl.site.is_empty():
			continue
		drawn_bars += 1
		var share: float = sim.build.progress_of(String(pl.id))
		var w := maxf(BAR_TILES * TILE, BAR_PX * k)
		var h := maxf(0.14 * TILE, BAR_THICK_PX * k)
		var top := Vector2(pl.pos) - Vector2(0.0, float(pl.size.y) / 2.0 + BAR_LIFT)
		var box := Rect2(top * TILE - Vector2(w / 2.0, h / 2.0), Vector2(w, h))
		ci.draw_rect(box.grow(1.5 * k), Color(0.0, 0.0, 0.0, 0.5))
		ci.draw_rect(box, Color(PLATE, 0.82))
		if share > 0.0:
			ci.draw_rect(Rect2(box.position, Vector2(w * share, h)), GOLD if by_day else BAR_WAITING)


## Whether the crew is at work now (by day): the bar of a site is gold then, a cool blue while it waits.
func _day() -> bool:
	if sim == null:
		return true
	var phase := String(sim.phase)
	return not (phase == "night" or phase == "dawn" or (phase == "dusk" and bool(sim.bell_rung)))


# ----------------------------------------------------------------- events --

## A building was finished: a little dust where it stands.
func celebrate(plot_id: String, fx) -> void:
	var pl: Dictionary = sim.build.plot(plot_id)
	if pl.is_empty() or fx == null:
		return
	var c := Vector2(pl.pos)
	for i in 5:
		var off := Vector2(-1.2 + 0.6 * float(i), 0.9 + 0.12 * float(i % 2))
		fx.smoke(c.x + off.x, c.y + off.y, 0.3, false)


## The builders' hammer rang: wood chips fly from the site (when the ring is the site's and not a wall's).
func hammer(e: Dictionary, fx) -> void:
	if sim == null or fx == null:
		return
	var site: Dictionary = sim.build.active_site()
	if site.is_empty() or Vector2(float(e.x), float(e.y)).distance_to(Vector2(site.work)) > 3.0:
		return
	var swing := sin(_t * 9.0)
	fx.hit_material(float(site.pos.x) + 0.7 * swing, float(site.pos.y) + 0.1, "wood")
