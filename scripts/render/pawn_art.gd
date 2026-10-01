## The parts of a character drawn live each frame so they can move: legs and
## shoes, walkers' reaching arms, and the hands on a weapon. Ported from the
## web version's pawn art; units are tiles, origin at the character's feet.
## Shapes are built once and moved with transforms to keep per-frame work low.
## Every drawing function takes `ci`, anything with the canvas's draw_* methods
## (the node itself, or a recorder in the tests).
##
## The kinds of the dead are the same figure built differently (STYLES): a
## walker is the unit, a runner is leaner, paler and leans into its stride, a
## brute is broader, darker and heavier. Nothing here is a new picture.
extends RefCounted

const S := preload("res://scripts/render/shapes.gd")

const HEM := 0.13
const FOOT_Y := 0.3
const LW := 0.038
const INK := Color(26.0 / 255.0, 20.0 / 255.0, 15.0 / 255.0, 0.8)
const SHADOW_COL := Color(8.0 / 255.0, 6.0 / 255.0, 4.0 / 255.0, 0.3)

## What differs from a walker, key by key (a walker is the neutral value of each):
##   sx, sy      the figure's scale across and up, on top of the rules' size
##   tint        the colour the figure is blended toward, by tint_amount (0 = not at all)
##   lean        the forward lean of the body in side view, in radians
##   dip_s/dip_n how tall the body stands facing the player / facing away (a lean
##               toward the player shortens it)
##   head, sink, thrust  the head's size against the body's, how far the neck sinks
##               between the shoulders, how far the head is pushed forward in side
##               view (a hunch); all neutral (1, 0, 0) draws the sprite as it is
##   leg_amp     the swing of the stride; leg_lift how high the feet come up facing
##               the player, leg_kick how high in side view
##   leg_w       thickness of the legs; stance how far apart they stand
##   pose        "reach" (arms out front, the walker's) or "sprint" (arms swept back)
##   arm_reach   how far forward the reaching hand is; arm_drop how far the whole
##               arm hangs lower, arm_sag how much lower the hand is than the shoulder
##   arm_w       thickness of the arms; hand_k the size of the hands; arm_n how much
##               lower the hands are seen from behind (the arms point away from you)
##   bob         how much the body bounces as it walks
##   claw_rate, claw_thump  how fast it swings at a wall, and how hard it lunges
##   shadow_*    width, depth and darkness of the ground shadow
const WALKER := {
	"sx": 1.0, "sy": 1.0,
	"tint": Color(0.0, 0.0, 0.0), "tint_amount": 0.0, "tint_floor": 0.0, "tint_gain": 1.0,
	"lean": 0.0, "dip_s": 1.0, "dip_n": 1.0, "head": 1.0, "sink": 0.0, "thrust": 0.0,
	"leg_amp": 1.0, "leg_lift": 1.0, "leg_kick": 1.0, "leg_w": 1.0, "stance": 1.0,
	"pose": "reach", "arm_reach": 0.5, "arm_drop": 0.0, "arm_sag": 0.0, "arm_w": 1.0, "hand_k": 1.0, "arm_n": 0.0,
	"bob": 1.0, "claw_rate": 1.0, "claw_thump": 1.0,
	"shadow_wide": 1.0, "shadow_deep": 1.0, "shadow_dark": 1.0,
}
const RUNNER := {
	"sx": 0.88, "sy": 1.0,
	"tint": Color(0.75, 0.77, 0.76), "tint_amount": 0.5, "tint_floor": 0.12, "tint_gain": 1.0,
	"lean": 0.26, "dip_s": 0.93, "dip_n": 1.0, "head": 1.0, "sink": 0.0, "thrust": 0.0,
	"leg_amp": 2.0, "leg_lift": 2.0, "leg_kick": 3.0, "leg_w": 0.85, "stance": 1.0,
	"pose": "sprint", "arm_reach": 0.5, "arm_drop": 0.0, "arm_sag": 0.0, "arm_w": 0.8, "hand_k": 0.85, "arm_n": 0.0,
	"bob": 1.4, "claw_rate": 1.0, "claw_thump": 1.0,
	"shadow_wide": 1.0, "shadow_deep": 1.0, "shadow_dark": 1.0,
}
const BRUTE := {
	"sx": 1.25, "sy": 1.15,
	"tint": Color(0.27, 0.31, 0.25), "tint_amount": 0.7, "tint_floor": 0.12, "tint_gain": 0.86,
	"lean": 0.12, "dip_s": 1.0, "dip_n": 1.0, "head": 0.78, "sink": 0.07, "thrust": 0.07,
	"leg_amp": 0.55, "leg_lift": 0.5, "leg_kick": 0.5, "leg_w": 1.2, "stance": 2.0,
	"pose": "reach", "arm_reach": 0.44, "arm_drop": 0.05, "arm_sag": 0.05, "arm_w": 1.4, "hand_k": 1.4, "arm_n": 0.12,
	"bob": 1.3, "claw_rate": 0.55, "claw_thump": 1.8,
	"shadow_wide": 1.2, "shadow_deep": 1.2, "shadow_dark": 1.6,
}
const STYLES := {"walker": WALKER, "runner": RUNNER, "brute": BRUTE}

## The warped sprite of a hunched figure (see sprite_mesh), in tiles from where the
## character stands: where the neck is and how wide a stretch blends the head's
## width into the body's, the rows the sprite is drawn between, half the width
## drawn and how far apart the rows of the mesh are.
const NECK_Y := -0.31
const NECK_BLEND := 0.06
const SPRITE_TOP := -0.92
const SPRITE_BOTTOM := 0.25
const SPRITE_HALF_WIDTH := 0.6
const SPRITE_ROW := 0.04

static var SHADOW: PackedVector2Array
static var LEG_S: PackedVector2Array
static var LEG_S_LINE: PackedVector2Array
static var SHOE_S: PackedVector2Array
static var SHOE_S_LINE: PackedVector2Array
static var LEG_E: PackedVector2Array
static var LEG_E_LINE: PackedVector2Array
static var SHOE_E: PackedVector2Array
static var SHOE_E_LINE: PackedVector2Array
static var HAND: PackedVector2Array
static var HAND_LINE: PackedVector2Array
static var GRIP: PackedVector2Array
static var GRIP_LINE: PackedVector2Array
static var _built := false
static var _materials := {}
static var _meshes := {}


static func _init_shapes() -> void:
	if _built:
		return
	_built = true
	SHADOW = S.ellipse(0.0, 0.31, 0.3, 0.1, 20)
	LEG_S = S.rrect(-0.07, 0.0, 0.14, 0.215, 0.05, 3)
	LEG_S_LINE = S.closed(LEG_S)
	SHOE_S = S.ellipse(0.0, 0.0, 0.085, 0.052, 14)
	SHOE_S_LINE = S.closed(SHOE_S)
	LEG_E = S.rrect(-0.065, 0.0, 0.13, 0.22, 0.05, 3)
	LEG_E_LINE = S.closed(LEG_E)
	SHOE_E = S.ellipse(0.0, 0.0, 0.1, 0.05, 14)
	SHOE_E_LINE = S.closed(SHOE_E)
	HAND = S.ellipse(0.0, 0.0, 0.062, 0.058, 12)
	HAND_LINE = S.closed(HAND)
	GRIP = S.ellipse(0.0, 0.0, 0.055, 0.055, 12)
	GRIP_LINE = S.closed(GRIP)


## Colours a character needs every frame, parsed once from its look.
static func palette(look: Dictionary) -> Dictionary:
	_init_shapes()
	var pants := Color.html(look.get("pants", "#444444"))
	var shoe := Color.html(look.get("shoes", "#222222"))
	var outer = look.get("outer")
	var style: String = look.get("outerStyle", "")
	var sleeve := Color.html(look.get("top", "#666666"))
	if outer != null and style != "hivis" and style != "vest":
		sleeve = Color.html(outer)
	return {
		"pants": pants,
		"pants_back": pants.darkened(0.18),
		"shoe": shoe,
		"shoe_back": shoe.darkened(0.2),
		"sleeve": sleeve,
		"skin": Color.html(look.get("skin", "#c0a080")),
	}


# ------------------------------------------------------ kinds of the dead --

## The kind to draw for a zombie: its own when this file knows it, a walker for
## anything else (a kind added to the rules before it has a drawing).
static func kind_of(z) -> String:
	var k = z.get("kind")
	if k is String and STYLES.has(k):
		return k
	return "walker"


## The build of a kind (see WALKER); a kind this file does not know is a walker.
static func style(kind: String) -> Dictionary:
	return STYLES.get(kind, WALKER)


## The size the rules give a zombie, kept to something that can be drawn.
static func size_of(z) -> float:
	var s = z.get("size")
	if (s is float or s is int) and float(s) > 0.0:
		return clampf(float(s), 0.25, 4.0)
	return 1.0


## How big a zombie of this kind and size is drawn: x across, y up. A walker is (1, 1).
static func figure_scale(kind: String, size: float = 1.0) -> Vector2:
	var st := style(kind)
	return Vector2(size * float(st.sx), size * float(st.sy))


## The box that is the figure, in tiles from where it stands (a walker's is the
## one a click is tested against: 0.42 either side, 0.95 up, 0.42 down). Bigger
## figures grow about their feet; a hunched one is lower than its scale says.
static func hit_box(kind: String, size: float = 1.0) -> Rect2:
	var st := style(kind)
	var fs := figure_scale(kind, size)
	var top_src := -0.95
	if is_warped(st):
		top_src = warp_y(st, top_src)
	var top := FOOT_Y - (FOOT_Y - top_src) * fs.y
	var bottom := FOOT_Y + (0.42 - FOOT_Y) * fs.y
	return Rect2(-0.42 * fs.x, top, 0.84 * fs.x, bottom - top)


## How tall this kind is drawn against a walker: 1 for a walker, what something
## placed over the head multiplies its offset by.
static func height_ratio(kind: String, size: float = 1.0) -> float:
	var st := style(kind)
	var walker_up := FOOT_Y + 0.95
	var up := walker_up
	if is_warped(st):
		up = FOOT_Y - warp_y(st, -0.95)
	return figure_scale(kind, size).y * up / walker_up


## The material that blends a figure toward its kind's tint: one shared by every
## figure of the kind. A walker has none (null), so it is drawn as it always was.
static func material(kind: String) -> ShaderMaterial:
	var st := style(kind)
	if float(st.tint_amount) <= 0.0:
		return null
	if not _materials.has(kind):
		var sh := Shader.new()
		sh.code = tint_shader(st.tint, float(st.tint_amount), float(st.tint_floor), float(st.tint_gain))
		var m := ShaderMaterial.new()
		m.shader = sh
		_materials[kind] = m
	return _materials[kind]


## Blends what is drawn toward `tint` by `amount`, except the darkest pixels (the
## ink of the outlines, below the luminance `floor_lum`) which keep their colour so
## the figure keeps the same outline; `gain` then dims (or lifts) what was blended.
static func tint_shader(tint: Color, amount: float, floor_lum: float, gain: float) -> String:
	var code := "shader_type canvas_item;\nvoid fragment() {\n"
	code += "\tfloat lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));\n"
	code += "\tfloat k = %.4f * smoothstep(%.4f, %.4f, lum);\n" % [amount, floor_lum, floor_lum + 0.2]
	code += "\tCOLOR.rgb = mix(COLOR.rgb, vec3(%.4f, %.4f, %.4f), k)" % [tint.r, tint.g, tint.b]
	if gain != 1.0:
		code += " * mix(1.0, %.4f, k / %.4f)" % [gain, amount]
	return code + ";\n}\n"


## Whether the body is drawn as a warped sprite (the head's size, the neck's sink or
## the head's thrust differ from a walker's) rather than as the sprite itself.
static func is_warped(st: Dictionary) -> bool:
	return float(st.head) != 1.0 or float(st.sink) != 0.0 or float(st.thrust) != 0.0


## Where a row of the sprite (y in tiles) is drawn on a hunched figure: the head above
## the neck is scaled by `head` about the neck, the neck sinks by `sink` and the body
## below is shortened to make room, so its feet and hem stay where they are.
static func warp_y(st: Dictionary, y: float) -> float:
	var sink: float = st.sink
	if y < NECK_Y:
		return NECK_Y + sink + (y - NECK_Y) * float(st.head)
	return NECK_Y + sink + (y - NECK_Y) * (SPRITE_BOTTOM - NECK_Y - sink) / (SPRITE_BOTTOM - NECK_Y)


## How wide that row is drawn against the sprite's: the head's width above the neck,
## the body's (1) below, blended over the neck.
static func warp_width(st: Dictionary, y: float) -> float:
	return lerpf(float(st.head), 1.0, smoothstep(NECK_Y - NECK_BLEND, NECK_Y + NECK_BLEND, y))


## How far forward that row is pushed in side view: the head and neck by `thrust`,
## fading out over the shoulders.
static func warp_shift(st: Dictionary, y: float) -> float:
	return float(st.thrust) * (1.0 - smoothstep(NECK_Y - 0.05, NECK_Y + 0.2, y))


## The sprite of one view drawn warped by a kind's build, as a mesh to draw with the
## figure's own texture (the rows of the texture, moved by warp_y, warp_width and
## warp_shift); `rect` is where the sprite sits in tiles. Null for a kind drawn as
## the sprite itself. One mesh per kind and view, shared by every figure.
static func sprite_mesh(kind: String, view: String, rect: Rect2) -> ArrayMesh:
	var st := style(kind)
	if not is_warped(st):
		return null
	var key := "%s/%s/%s" % [kind, view, rect]
	if _meshes.has(key):
		return _meshes[key]
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var rows := int(round((SPRITE_BOTTOM - SPRITE_TOP) / SPRITE_ROW))
	for i in rows + 1:
		var y := SPRITE_TOP + (SPRITE_BOTTOM - SPRITE_TOP) * float(i) / float(rows)
		var wy := warp_y(st, y)
		var half := SPRITE_HALF_WIDTH * warp_width(st, y)
		var shift := warp_shift(st, y) if view == "E" else 0.0
		var v := (y - rect.position.y) / rect.size.y
		verts.append(Vector2(-half + shift, wy))
		verts.append(Vector2(half + shift, wy))
		uvs.append(Vector2((-SPRITE_HALF_WIDTH - rect.position.x) / rect.size.x, v))
		uvs.append(Vector2((SPRITE_HALF_WIDTH - rect.position.x) / rect.size.x, v))
	var idx := PackedInt32Array()
	for i in rows:
		var a := i * 2
		idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = mesh
	return mesh


# ----------------------------------------------------------- the figure --

static func _fill(ci, at: Vector2, poly: PackedVector2Array, line: PackedVector2Array, col: Color, ink: Color, wide: float = 1.0, tall: float = 1.0) -> void:
	var xf := Transform2D(Vector2(wide, 0.0), Vector2(0.0, tall), at)
	ci.draw_colored_polygon(xf * poly, col)
	ci.draw_polyline(xf * line, ink, LW, true)


static func shadow(ci, st: Dictionary = WALKER) -> void:
	_init_shapes()
	var wide: float = st.shadow_wide
	var deep: float = st.shadow_deep
	var dark: float = st.shadow_dark
	if wide == 1.0 and deep == 1.0 and dark == 1.0:
		ci.draw_colored_polygon(SHADOW, SHADOW_COL)
		return
	var col := SHADOW_COL
	col.a = minf(1.0, col.a * dark)
	var xf := Transform2D(Vector2(wide, 0.0), Vector2(0.0, deep), Vector2(0.0, 0.31 * (1.0 - deep)))
	ci.draw_colored_polygon(xf * SHADOW, col)


static func legs(ci, pal: Dictionary, view: String, phase: float, moving: bool, limp: bool, alpha: float = 1.0, st: Dictionary = WALKER) -> void:
	var ink := INK
	ink.a *= alpha
	var swing: float = st.leg_amp
	var raise: float = st.leg_lift
	var kick: float = st.leg_kick
	var wide: float = st.leg_w
	var stance: float = st.stance
	var s := sin(phase) if moving else 0.0
	if view == "E":
		for k: float in [-1.0, 1.0]:
			var amp := (0.04 if (limp and k > 0.0) else 0.1) * swing
			var sw := (s * k * amp) if moving else (k * 0.03 * stance)
			var lift := (maxf(0.0, cos(phase) * k) * 0.03 * kick) if moving else 0.0
			var leg: Color = pal.pants_back if k < 0.0 else pal.pants
			var shoe: Color = pal.shoe_back if k < 0.0 else pal.shoe
			leg.a *= alpha
			shoe.a *= alpha
			_fill(ci, Vector2(sw, HEM - 0.06 - lift), LEG_E, LEG_E_LINE, leg, ink, wide)
			_fill(ci, Vector2(sw + 0.035, FOOT_Y - lift), SHOE_E, SHOE_E_LINE, shoe, ink)
		return
	var pants: Color = pal.pants
	var shoe: Color = pal.shoe
	pants.a *= alpha
	shoe.a *= alpha
	for side: float in [-1.0, 1.0]:
		var amp := 0.35 if (limp and side > 0.0) else 1.0
		var lift := (maxf(0.0, side * s) * 0.055 * amp * raise) if moving else 0.0
		var x := side * 0.105 * stance
		_fill(ci, Vector2(x, HEM - 0.06 - lift), LEG_S, LEG_S_LINE, pants, ink, wide)
		_fill(ci, Vector2(x + side * 0.012, FOOT_Y - lift), SHOE_S, SHOE_S_LINE, shoe, ink)


static func _arm(ci, col: Color, p0: Vector2, ctrl: Vector2, p1: Vector2, w: float = 1.0) -> void:
	var pts := S.quad(p0, ctrl, p1, 6)
	ci.draw_polyline(pts, INK, 0.15 * w, true)
	ci.draw_circle(p0, 0.075 * w, INK)
	ci.draw_circle(p1, 0.075 * w, INK)
	ci.draw_polyline(pts, col, 0.115 * w, true)
	ci.draw_circle(p0, 0.0575 * w, col)
	ci.draw_circle(p1, 0.0575 * w, col)


static func _hand(ci, skin: Color, x: float, y: float, dirx: float, diry: float, k: float = 1.0) -> void:
	for f: float in [-1.0, 0.0, 1.0]:
		var px := -diry * f * 0.035 * k
		var py := dirx * f * 0.035 * k
		var a := Vector2(x + dirx * 0.03 * k + px, y + diry * 0.03 * k + py)
		var b := Vector2(x + dirx * 0.095 * k + px * 1.2, y + diry * 0.095 * k + py * 1.2)
		ci.draw_line(a, b, INK, 0.034, true)
		ci.draw_line(a, b - Vector2(dirx, diry) * 0.006, skin, 0.02, true)
	_fill(ci, Vector2(x, y), HAND, HAND_LINE, skin, INK, k, k)


## Walkers reach with both arms. layer "back" is drawn before the body,
## "front" after it. A runner running holds them swept back instead (it reaches
## only when it claws at a wall); a brute reaches with thicker arms and bigger fists.
static func arms(ci, pal: Dictionary, view: String, t: float, attacking: bool, layer: String, st: Dictionary = WALKER, phase: float = 0.0) -> void:
	var col: Color = pal.sleeve
	var skin: Color = pal.skin
	var claw := 1.0 if attacking else 0.25
	var rate: float = st.claw_rate
	var thump: float = st.claw_thump
	var speed := (7.0 * rate) if attacking else 2.2
	var w: float = st.arm_w
	var hk: float = st.hand_k
	var reach_x: float = st.arm_reach
	var drop: float = st.arm_drop
	var sag: float = st.arm_sag
	var up: float = st.arm_n
	if st.pose == "sprint" and not attacking:
		_arms_sprint(ci, col, skin, view, phase, layer, w, hk)
		return
	if view == "S":
		if layer != "front":
			return
		for s: float in [-1.0, 1.0]:
			var reach := sin(t * speed + s * 1.7) * 0.05 * claw * thump
			var hx := s * 0.2
			var hy := -0.05 + reach + drop + sag
			_arm(ci, col, Vector2(s * 0.27, -0.2 + drop), Vector2(s * 0.33, -0.08 + drop), Vector2(hx, hy - 0.03), w)
			_hand(ci, skin, hx, hy + 0.02, 0.0, 1.0, hk)
	elif view == "E":
		var far := layer == "back"
		var reach := sin(t * speed + (1.9 if far else 0.0)) * 0.05 * claw * thump
		var y0 := -0.23 if far else -0.19
		var hx := reach_x + reach
		var hy := y0 + 0.03 + cos(t * 1.3 + (1.0 if far else 0.0)) * 0.015 + drop + sag
		_arm(ci, col, Vector2(0.0, y0 + drop), Vector2(0.25, y0 - 0.02 + drop), Vector2(hx - 0.05, hy), w)
		_hand(ci, skin, hx, hy, 1.0, 0.15, hk)
	else:
		if layer != "back":
			return
		for s: float in [-1.0, 1.0]:
			var reach := sin(t * speed + s * 1.7) * 0.04 * claw * thump
			_arm(ci, col, Vector2(s * 0.26, -0.2 + drop), Vector2(s * 0.3, -0.32 + drop + up * 0.5), Vector2(s * 0.2, -0.46 + reach + drop + up), w)
			_hand(ci, skin, s * 0.2, -0.5 + reach + drop + up, 0.0, -1.0, hk)


## Both arms swept back and pumping with the stride.
static func _arms_sprint(ci, col: Color, skin: Color, view: String, phase: float, layer: String, w: float, hk: float) -> void:
	var pump := sin(phase)
	if view == "E":
		var far := layer == "back"
		var sg := -1.0 if far else 1.0
		var y0 := -0.23 if far else -0.19
		var hx := -0.4 + pump * sg * 0.1
		var hy := y0 + 0.1 - maxf(0.0, pump * sg) * 0.08
		_arm(ci, col, Vector2(0.0, y0), Vector2(-0.18, y0 + 0.02 - pump * sg * 0.03), Vector2(hx + 0.04, hy), w)
		_hand(ci, skin, hx, hy, -1.0, 0.1, hk)
	elif view == "S":
		if layer != "back":
			return
		for s: float in [-1.0, 1.0]:
			var p := pump * s
			_arm(ci, col, Vector2(s * 0.27, -0.2), Vector2(s * 0.37, -0.12), Vector2(s * 0.4, -0.02 + p * 0.05), w)
			_hand(ci, skin, s * 0.41, 0.02 + p * 0.05, 0.0, 1.0, hk)
	else:
		if layer != "front":
			return
		for s: float in [-1.0, 1.0]:
			var p := pump * s
			_arm(ci, col, Vector2(s * 0.26, -0.2), Vector2(s * 0.36, -0.1), Vector2(s * 0.38, 0.0 + p * 0.05), w)
			_hand(ci, skin, s * 0.39, 0.04 + p * 0.05, 0.0, 1.0, hk)


static func hands(ci, front, skin: Color) -> void:
	_fill(ci, Vector2(0.0, 0.05), GRIP, GRIP_LINE, skin, INK)
	if front != null:
		_fill(ci, Vector2(float(front), 0.02), GRIP, GRIP_LINE, skin, INK)
