extends "res://tests/case.gd"
## How the kinds of the dead are drawn: a walker exactly as it always was, a runner
## leaner, paler and leaning into its stride, a brute broader, darker and hunched.
## Headless cannot render, so the node is given a stand-in for the canvas (Tape)
## that records every draw command, and the tests read those; how it looks on
## screen is for screenshots.

const Sim := preload("res://scripts/sim/sim.gd")
const Kinds := preload("res://scripts/sim/kinds.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const Art := preload("res://scripts/render/pawn_art.gd")
const PawnMotion := preload("res://scripts/render/pawn_motion.gd")

const TILE := 64.0
## What a node is made from (the real files of one of the dead, under a key of its own).
const DATA := {
	"pawn": {
		"box": [-1.15, -1.42, 1.15, 0.62],
		"files": {"zt": {"S": "res://assets/pawns/z3_S.png", "E": "res://assets/pawns/z3_E.png", "N": "res://assets/pawns/z3_N.png"}},
	},
}
const LOOKS := [
	{"skin": "#8c8a7c", "pants": "#3b4658", "shoes": "#2a2420", "top": "#7a3a30"},
	{"skin": "#a09876", "pants": "#2c2d31", "shoes": "#4a4038", "top": "#cfc9b8", "outer": "#c8d23a", "outerStyle": "hivis"},
	{"skin": "#8a8190", "pants": "#3a3f47", "shoes": "#2a2420", "top": "#5a626b", "outer": "#6a4a3a", "outerStyle": "jacket"},
]
const POSES := ["wander", "limp", "idle", "attack", "breach", "dying", "dead", "fade"]
const FACINGS := ["S", "E", "N", "W"]

## A short digest of everything a walker draws, per look and facing, over all POSES (see
## `digests`; the walker has the neutral variety there, see `_node`). A walker must keep
## drawing exactly this. It was made from the drawing as it was before there were kinds,
## and made again on 2026-10-09 (the animation rounds of 2026-10-07, ANIM and FEEL, "the
## animations are clunky and weird", changed the dead's drawing on purpose: the legs turned
## about the hip, a breath, a landing foot); if the walker's look is changed on purpose
## again, print `load("res://tests/test_pawn_kinds.gd").new().digests()` from a script
## and paste the new table.
const WALKER_DIGESTS := {
	"look0/E": "f12c8b0781cf",
	"look0/N": "92d89f2592e3",
	"look0/S": "2a1305021972",
	"look0/W": "72415d0d9068",
	"look1/E": "8fbb912fd325",
	"look1/N": "df1b8448f6b6",
	"look1/S": "7ec8616d8dcf",
	"look1/W": "2d6cfe33a78f",
	"look2/E": "5f3d0093a049",
	"look2/N": "1eb2f639decf",
	"look2/S": "4c56b0948857",
	"look2/W": "995d98a36c15",
}


# ------------------------------------------------------------- the stand-in --

## Takes the place of the canvas: every draw call is written down, as text for a
## digest and as data for the tests that look at one thing in it.
class Tape:
	extends RefCounted
	var lines := PackedStringArray()
	## Each draw as {"op", "xf" (the transform in force), "args"}.
	var cmds: Array = []
	var xf := Transform2D.IDENTITY

	static func f(v) -> String:
		match typeof(v):
			TYPE_FLOAT:
				return "%.5f" % v
			TYPE_VECTOR2:
				return "(%.5f,%.5f)" % [v.x, v.y]
			TYPE_COLOR:
				return "c(%.4f,%.4f,%.4f,%.4f)" % [v.r, v.g, v.b, v.a]
			TYPE_RECT2:
				return "r(%.5f,%.5f,%.5f,%.5f)" % [v.position.x, v.position.y, v.size.x, v.size.y]
			TYPE_TRANSFORM2D:
				return "m(%s,%s,%s)" % [f(v.x), f(v.y), f(v.origin)]
			TYPE_PACKED_VECTOR2_ARRAY:
				var out := PackedStringArray()
				for p in v:
					out.append(f(p))
				return "[" + ",".join(out) + "]"
			TYPE_NIL:
				return "null"
			_:
				return str(v)

	func rec(op: String, args: Array) -> void:
		var parts := PackedStringArray()
		for a in args:
			parts.append(f(a))
		lines.append(op + " " + " ".join(parts))
		cmds.append({"op": op, "xf": xf, "args": args})

	func draw_set_transform_matrix(m: Transform2D) -> void:
		xf = m
		rec("xf", [m])

	func draw_colored_polygon(pts: PackedVector2Array, col: Color, _uvs = null, _tex = null) -> void:
		rec("poly", [pts, col])

	func draw_polyline(pts: PackedVector2Array, col: Color, width: float = -1.0, aa: bool = false) -> void:
		rec("line", [pts, col, width, aa])

	func draw_line(a: Vector2, b: Vector2, col: Color, width: float = -1.0, aa: bool = false) -> void:
		rec("seg", [a, b, col, width, aa])

	func draw_circle(c: Vector2, r: float, col: Color, _filled = true, _width = -1.0, _aa = false) -> void:
		rec("circle", [c, r, col])

	func draw_texture_rect(tex: Texture2D, rect: Rect2, tile: bool, mod: Color = Color.WHITE, _transpose = false) -> void:
		rec("tex", [tex.resource_path, rect, tile, mod])

	func draw_mesh(mesh: Mesh, tex: Texture2D, _xf = Transform2D.IDENTITY, mod: Color = Color.WHITE) -> void:
		var arrays: Array = mesh.surface_get_arrays(0)
		rec("mesh", [arrays[Mesh.ARRAY_VERTEX], tex.resource_path, mod])

	## The commands of one op, in order.
	func of(op: String) -> Array:
		var out := []
		for c in cmds:
			if c.op == op:
				out.append(c)
		return out

	func text() -> String:
		return "\n".join(lines)


## A zombie of this kind in one of POSES, facing one way. `still` is an idle one
## whose sway, bob and lunge are all zero, so the transforms are exactly the build's.
func _zombie(kind: String, pose: String, facing: String, look: int = 0):
	var z = Sim.Zombie.new()
	z.x = 30.37 + look
	z.y = 22.1
	z.look = LOOKS[look]
	z.facing = facing
	z.kind = kind
	z.size = float(Kinds.KINDS[kind].size) if Kinds.KINDS.has(kind) else 1.0
	z.t = 2.2 + look * 1.7
	z.walk_phase = 1.3 + look * 0.9
	z.fall_dir = -1.0 if look == 1 else 1.0
	match pose:
		"wander":
			z.state = "wander"
			z.moving = true
		"limp":
			z.state = "approach"
			z.moving = true
			z.limp = true
			z.walk_phase = 2.9 + look
		"idle":
			z.state = "approach"
			z.t = 7.7 + look
		"attack":
			z.state = "attack"
			z.t = 3.1 + look
		"breach":
			z.state = "breach"
			z.t = 5.3 + look
		"dying":
			z.state = "dying"
			z.fall = 0.5
		"dead":
			z.state = "dead"
			z.fall = 1.0
			z.dead_t = 1.0
		"fade":
			z.state = "dead"
			z.fall = 1.0
			z.dead_t = 62.0
		"still":
			z.state = "approach"
			z.x = 0.0
			z.t = 0.0
		"stride":
			z.state = "approach"
			z.moving = true
			z.x = 0.0
			z.t = 0.0
			z.walk_phase = PI / 2.0
		"plant":
			# (the neutral moment of the stride: both feet on the ground, side by side)
			z.state = "approach"
			z.moving = true
			z.x = 0.0
			z.t = 0.0
			z.walk_phase = 0.0
	return z


## The node for a zombie, drawing into a Tape (`cls` is the node's script). Each of the dead has a variety of its own, made from its seed (the entity's instance id: another in every
## run; pawn_motion.gd `dead_variant`: its gait, lean, tilt, arms, size and dirt), which would make these pictures differ from one run to the next. These tests are about what the KIND
## draws, so the node is given the neutral variety (everything at 1 or 0) in its place, as it draws in a crowd of average ones; the variety has its own test at the end.
func _node(z, cls = PawnNode, own_variety := false):
	var n = cls.new()
	n.setup(z, true, DATA, "zt")
	if not own_variety:
		n._dv = PawnMotion.Dead.new()
		n._vphase = float(z.walk_phase)
		n.modulate = Color.WHITE
	n._pen = Tape.new()
	return n


## What the node draws now.
func _tape(n) -> Tape:
	n._pen = Tape.new()
	n._draw()
	return n._pen


func _drawn(kind: String, pose: String, facing: String, look: int = 0) -> Tape:
	var n = _node(_zombie(kind, pose, facing, look))
	var tape := _tape(n)
	n.free()
	return tape


## The digests of the table above for a kind of node script. Not a test: run it
## on the original node to make the table.
func digests(cls = PawnNode, kind: String = "walker") -> Dictionary:
	var out := {}
	for li in LOOKS.size():
		for facing in FACINGS:
			var all := PackedStringArray()
			for pose in POSES:
				var n = _node(_zombie(kind, pose, facing, li), cls)
				all.append("## " + pose)
				all.append(_tape(n).text())
				n.free()
			out["look%d/%s" % [li, facing]] = "\n".join(all).sha256_text().substr(0, 12)
	return out


## The body draw (the sprite, or the warped sprite) of a tape: {"op", "xf", ...}.
func _body(tape: Tape) -> Dictionary:
	var found := tape.of("tex") + tape.of("mesh")
	eq(found.size(), 1, "one body is drawn")
	return found[0] if found.size() == 1 else {"op": "", "xf": Transform2D.IDENTITY, "args": []}


## How wide and how tall the body is drawn, in tiles, from its transform.
func _body_scale(tape: Tape) -> Vector2:
	var xf: Transform2D = _body(tape).xf
	return Vector2(xf.x.length(), xf.y.length()) / TILE


## The middle of a shape's points.
func _middle(pts: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in pts:
		sum += p
	return sum / float(pts.size())


func _width_of(pts: PackedVector2Array) -> float:
	var lo := INF
	var hi := -INF
	for p in pts:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	return hi - lo


# ------------------------------------------------- a walker is as it was --

func test_a_walker_draws_exactly_what_it_drew_before_there_were_kinds() -> void:
	var now := digests()
	eq(now.size(), WALKER_DIGESTS.size(), "a digest for every look and facing")
	for label in WALKER_DIGESTS:
		eq(now.get(label), WALKER_DIGESTS[label], "what a walker draws, %s (all poses)" % label)


func test_a_kind_the_art_does_not_know_is_drawn_as_a_walker() -> void:
	var walker := digests()
	for odd in ["ghoul", "", "BRUTE", "Runner"]:
		var as_odd := digests(PawnNode, odd)
		eq(as_odd, walker, "'%s' draws as a walker" % odd)
		var n = _node(_zombie(odd, "idle", "S"))
		eq(n.kind, "walker", "'%s' is a walker to the node" % odd)
		eq(n.material, null, "and has no tint")
		eq(n.figure_scale_xy(), Vector2.ONE, "and its size")
		n.free()
	eq(Art.figure_scale("ghoul", 1.3), Vector2(1.3, 1.3), "the rules' size still counts for a kind it does not know")


func test_a_zombie_without_a_kind_or_a_size_is_a_walker() -> void:
	# an old save, or a stand-in: nothing to read the kind from
	var bare := RefCounted.new()
	eq(Art.kind_of(bare), "walker", "no kind property")
	eq(Art.size_of(bare), 1.0, "no size property")
	var z = Sim.Zombie.new()
	z.kind = ""
	z.size = 0.0
	eq(Art.kind_of(z), "walker", "an empty kind")
	eq(Art.size_of(z), 1.0, "a size of nothing cannot be drawn")
	z.size = -3.0
	eq(Art.size_of(z), 1.0, "nor a negative one")
	z.size = 400.0
	check(Art.size_of(z) <= 4.0, "a huge size is kept to something sane")


# --------------------------------------------------------------- the kinds --

func test_every_kind_of_the_rules_has_a_build_and_every_build_is_complete() -> void:
	for kind in Kinds.KINDS:
		check(Art.STYLES.has(kind), "'%s' has no build in pawn_art.gd, so it would be drawn as a walker" % kind)
	var keys: Array = Art.WALKER.keys()
	keys.sort()
	for kind in Art.STYLES:
		var have: Array = Art.STYLES[kind].keys()
		have.sort()
		eq(have, keys, "the build of '%s' has the same keys as a walker's" % kind)
	var w := Art.style("walker")
	eq([w.sx, w.sy, w.tint_amount, w.lean, w.head, w.sink, w.thrust, w.leg_amp, w.arm_w, w.bob], [1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0], "a walker's build is neutral")


func test_a_brute_is_drawn_larger_than_a_runner_and_than_a_walker() -> void:
	var scale := {}
	var box := {}
	for kind in ["walker", "runner", "brute"]:
		var n = _node(_zombie(kind, "still", "S"))
		var tape := _tape(n)
		scale[kind] = _body_scale(tape)
		near(scale[kind].x, n.figure_scale_xy().x, 0.001, "%s is drawn across at the scale the node says" % kind)
		# a bigger figure grows up from its feet, which stay where a walker's would be
		var feet: Vector2 = _body(tape).xf * Vector2(0.0, Art.FOOT_Y)
		near(feet.x, 0.0, 0.01, "%s: the feet stay in line" % kind)
		# (a standing figure breathes: it rises by up to 0.008 of a tile, and a big one by a big share of that; under a pixel)
		near(feet.y, Art.FOOT_Y * TILE, 1.0, "%s: and on the ground" % kind)
		box[kind] = n.hit_box()
		n.free()
	check(scale.brute.x > scale.walker.x and scale.brute.y > scale.walker.y, "a brute is bigger than a walker: %s against %s" % [scale.brute, scale.walker])
	check(scale.brute.x > scale.runner.x and scale.brute.y > scale.runner.y, "and than a runner: %s against %s" % [scale.brute, scale.runner])
	check(scale.brute.x > 1.5, "clearly bigger, not a hair: %s" % scale.brute)
	check(box.brute.size.x > box.walker.size.x and box.brute.size.y > box.walker.size.y, "its box is bigger too")
	check(box.walker.size.x > box.runner.size.x and box.walker.size.y > box.runner.size.y, "and a runner's is the smallest")


func test_a_brute_is_broader_than_tall_and_a_runner_is_leaner_than_a_walker() -> void:
	var ratio := {}
	for kind in ["walker", "runner", "brute"]:
		var n = _node(_zombie(kind, "still", "S"))
		var fs: Vector2 = n.figure_scale_xy()
		ratio[kind] = fs.x / fs.y
		n.free()
	near(ratio.walker, 1.0, 0.0001, "a walker is as wide as it is tall")
	check(ratio.brute > 1.04, "a brute is broader than tall: %s" % ratio.brute)
	check(ratio.runner < 0.95, "a runner is narrower than tall: %s" % ratio.runner)
	# and its limbs are thinner, a brute's thicker: the widest stroke drawn is an arm's outline
	var arm := {}
	for kind in ["walker", "runner", "brute"]:
		var widest := 0.0
		for c in _drawn(kind, "idle", "S").of("line"):
			widest = maxf(widest, float(c.args[2]))
		arm[kind] = widest
	check(arm.runner < arm.walker and arm.walker < arm.brute, "arms: runner %s, walker %s, brute %s" % [arm.runner, arm.walker, arm.brute])


func test_the_kinds_are_tinted_apart_and_a_walker_is_not_tinted_at_all() -> void:
	var tint := {}
	for kind in ["walker", "runner", "brute"]:
		var n = _node(_zombie(kind, "idle", "S"))
		tint[kind] = n.material
		n.free()
	eq(tint.walker, null, "a walker has no material, so it is drawn plain")
	check(tint.runner is ShaderMaterial and tint.brute is ShaderMaterial, "a runner and a brute are tinted")
	check(tint.runner != tint.brute, "each its own")
	eq(Art.material("runner"), tint.runner, "one material shared by every runner")
	eq(Art.material("brute"), tint.brute, "and by every brute")
	eq(Art.material("ghoul"), null, "an unknown kind is not tinted")
	var runner := Art.style("runner")
	var brute := Art.style("brute")
	check(runner.tint_amount > 0.0 and brute.tint_amount > 0.0, "both blend toward their colour")
	check(runner.tint != brute.tint, "different colours")
	var lum_r: float = runner.tint.get_luminance()
	var lum_b: float = brute.tint.get_luminance()
	check(lum_r > 0.6, "a runner is pale (%s)" % lum_r)
	check(lum_b < 0.4, "a brute is dark (%s)" % lum_b)
	check(brute.tint.g > brute.tint.r and brute.tint.g > brute.tint.b, "and grey-green")
	check(absf(runner.tint.r - runner.tint.b) < 0.1, "a runner's is a grey, not a colour")
	if tint.runner != null and tint.brute != null:
		check(tint.runner.shader.code != tint.brute.shader.code, "the shaders differ")
		# the shader blends toward the kind's own colour by its own amount (headless cannot
		# run it: this checks what it is told, the picture it makes is for screenshots)
		for kind in ["runner", "brute"]:
			var code: String = tint[kind].shader.code
			var st := Art.style(kind)
			check(code.contains("vec3(%.4f, %.4f, %.4f)" % [st.tint.r, st.tint.g, st.tint.b]), "%s: the shader holds its colour" % kind)
			check(code.contains("%.4f * smoothstep" % st.tint_amount), "%s: and its amount" % kind)
			check(code.contains("mix(COLOR.rgb, vec3(") and code.contains("), k)"), "%s: and mixes toward it" % kind)


func test_a_runner_leans_into_its_facing_and_a_walker_does_not() -> void:
	var facing_sign := {"E": 1.0, "W": -1.0}
	for kind in ["walker", "runner", "brute"]:
		for facing in ["E", "W"]:
			var xf: Transform2D = _body(_drawn(kind, "still", facing)).xf
			var hip: Vector2 = xf * Vector2(0.0, 0.12)
			var head: Vector2 = xf * Vector2(0.0, -0.6)
			# the angle of the body from the upright, on the screen, forward positive
			var lean := rad_to_deg(atan2((head.x - hip.x) * facing_sign[facing], hip.y - head.y))
			if kind == "walker":
				near(lean, 0.0, 0.01, "a walker stands upright facing %s" % facing)
			elif kind == "runner":
				check(lean > 10.0 and lean < 20.0, "a runner leans forward 10 to 20 degrees facing %s: %s" % [facing, lean])
			else:
				check(lean > 2.0 and lean < 10.0, "a brute is slightly hunched facing %s: %s" % [facing, lean])
	# facing the player it comes toward them: shorter on its feet, not slanted
	var upright: Vector2 = _body_scale(_drawn("walker", "still", "S"))
	var runner: Transform2D = _body(_drawn("runner", "still", "S")).xf
	near(runner.y.x, 0.0, 0.001, "not slanted facing the player")
	check(runner.y.length() / TILE < 0.94 * upright.y, "but shorter than it stands")


func test_the_stride_is_longer_for_a_runner_and_shorter_for_a_brute() -> void:
	var spread := {}
	var lift := {}
	for kind in ["walker", "runner", "brute"]:
		# side view at the widest point of the stride: the shadow, then the back leg and
		# its shoe, then the front leg and its shoe
		var side := _drawn(kind, "stride", "E").of("poly")
		check(side.size() >= 5, "%s: legs are drawn" % kind)
		spread[kind] = _middle(side[3].args[0]).x - _middle(side[1].args[0]).x
		# facing the player the feet come up in turn: the second shoe is lifted (and comes toward the player as it goes), the first is planted. How far it comes up is
		# how much higher it is than the same shoe at the neutral moment of the stride, when both are on the ground
		var front := _drawn(kind, "stride", "S").of("poly")
		var plant := _drawn(kind, "plant", "S").of("poly")
		lift[kind] = _middle(plant[4].args[0]).y - _middle(front[4].args[0]).y
	# (the legs turn about the hip, by at most 0.6 of a radian: a runner's swing, twice a walker's, is cut short by that, so it is wider by a third, not by half)
	check(spread.runner > spread.walker * 1.2, "a runner's legs swing wider: %s against %s" % [spread.runner, spread.walker])
	check(spread.brute < spread.walker * 0.8, "a brute's swing less: %s against %s" % [spread.brute, spread.walker])
	check(lift.runner > lift.walker * 1.5, "a runner's feet come up higher: %s against %s" % [lift.runner, lift.walker])
	check(lift.brute < lift.walker * 0.8, "a brute's barely leave the ground: %s against %s" % [lift.brute, lift.walker])
	check(lift.brute > 0.0, "but they do")


func test_a_brute_casts_a_bigger_darker_shadow_and_a_runner_an_ordinary_one() -> void:
	var shadow := {}
	for kind in ["walker", "runner", "brute"]:
		var tape := _drawn(kind, "still", "S")
		var first: Dictionary = tape.of("poly")[0]
		var xf: Transform2D = first.xf
		shadow[kind] = {"local": _width_of(first.args[0]), "drawn": _width_of(xf * first.args[0]) / TILE, "alpha": float(first.args[1].a)}
	check(shadow.brute.local > shadow.walker.local, "a brute's shadow is wider in its own terms")
	check(shadow.brute.drawn > shadow.walker.drawn * 1.8, "and much wider on the ground: %s against %s" % [shadow.brute.drawn, shadow.walker.drawn])
	check(shadow.brute.alpha > shadow.walker.alpha, "and darker")
	near(shadow.runner.alpha, shadow.walker.alpha, 0.0001, "a runner's is as dark as a walker's")


func test_a_brute_is_hunched_the_sprite_has_a_smaller_head_sunk_between_wide_shoulders() -> void:
	var rect := Rect2(-1.15, -1.42, 2.3, 2.04)
	eq(Art.sprite_mesh("walker", "S", rect), null, "a walker is drawn as the sprite itself")
	eq(Art.sprite_mesh("runner", "S", rect), null, "so is a runner")
	var st := Art.style("brute")
	for view in ["S", "E", "N"]:
		var mesh := Art.sprite_mesh("brute", view, rect)
		check(mesh != null, "a brute's %s view is a warped sprite" % view)
		if mesh == null:
			continue
		eq(Art.sprite_mesh("brute", view, rect), mesh, "built once and shared")
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		eq(verts.size(), uvs.size(), "a texture coordinate for every vertex")
		var top := 0
		var hem := verts.size() - 2
		var head_w := absf(verts[top + 1].x - verts[top].x)
		var body_w := absf(verts[hem + 1].x - verts[hem].x)
		check(head_w < body_w * 0.9, "%s: the head rows are narrower than the body's: %s against %s" % [view, head_w, body_w])
		near(verts[hem].y, Art.SPRITE_BOTTOM, 0.001, "%s: the hem stays where it is" % view)
		check(Art.warp_y(st, Art.NECK_Y) > Art.NECK_Y + 0.03, "the neck sinks")
		var mid_head := (verts[top].x + verts[top + 1].x) * 0.5
		var mid_body := (verts[hem].x + verts[hem + 1].x) * 0.5
		if view == "E":
			check(mid_head > mid_body + 0.03, "side view: the head is pushed forward")
		else:
			near(mid_head, mid_body, 0.001, "%s view: the head is not pushed to a side" % view)
		for i in range(2, verts.size(), 2):
			check(verts[i].y > verts[i - 2].y, "%s: the rows go down and never fold over each other" % view)
		for uv in uvs:
			check(uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0, "%s: the sprite is sampled inside the texture" % view)
	var n = _node(_zombie("brute", "idle", "S"))
	eq(_body(_tape(n)).op, "mesh", "a brute draws the warped sprite")
	n.free()
	n = _node(_zombie("walker", "idle", "S"))
	eq(_body(_tape(n)).op, "tex", "a walker draws the sprite")
	n.free()


func test_the_figure_accessors_for_the_overlay() -> void:
	var n = _node(_zombie("walker", "idle", "S"))
	near(n.figure_scale(), 1.0, 0.0001, "a walker's height is the unit")
	eq(n.hit_box(), Rect2(-0.42, -0.95, 0.84, 1.37), "a walker's box is the one a click was tested against")
	n.free()
	var runner = _node(_zombie("runner", "idle", "S"))
	var brute = _node(_zombie("brute", "idle", "S"))
	check(runner.figure_scale() < 1.0 and brute.figure_scale() > 1.2, "runner %s, brute %s" % [runner.figure_scale(), brute.figure_scale()])
	near(brute.figure_scale(), (Art.FOOT_Y - brute.hit_box().position.y) / (Art.FOOT_Y + 0.95), 0.001, "the height ratio is the box's height against a walker's, hunch and all")
	# the box holds the whole drawn figure: its top is above the top of the head, which
	# is the sprite's top row scaled about the feet
	var st := Art.style("brute")
	var fs: Vector2 = brute.figure_scale_xy()
	var head_top: float = Art.FOOT_Y - (Art.FOOT_Y - Art.warp_y(st, Art.SPRITE_TOP)) * fs.y
	var box: Rect2 = brute.hit_box()
	check(box.position.y <= head_top, "the box %s holds the head (top at %s)" % [box, head_top])
	check(box.position.y > head_top - 0.1, "and hugs it: a hunched figure is not as tall as its scale")
	check(box.position.x < -0.6 and box.end.x > 0.6, "and is wide as the shoulders")
	eq(Art.hit_box("brute", 1.4), brute.hit_box(), "the same box without a node, for what only has the zombie")
	near(Art.height_ratio("walker"), 1.0, 0.0001, "the same ratio")
	runner.free()
	brute.free()


func test_a_corpse_keeps_its_size_and_its_tint() -> void:
	for kind in ["runner", "brute"]:
		var n = _node(_zombie(kind, "dead", "S"))
		var dead := _tape(n)
		var fs: Vector2 = n.figure_scale_xy()
		var walker: Vector2 = _body_scale(_drawn("walker", "dead", "S"))
		var d: Vector2 = _body_scale(dead)
		near(d.x, fs.x * walker.x, 0.01, "a dead %s is as wide as it was in life" % kind)
		check(n.material == Art.material(kind), "and still tinted")
		eq(_body(dead).op, "mesh" if kind == "brute" else "tex", "and drawn the way it was")
		check(dead.of("poly")[0].args[1] != Art.SHADOW_COL, "no shadow under a corpse")
		n.free()
	# a figure falls, and grows, about its feet: the same spot of the ground whatever the kind
	for kind in ["walker", "runner", "brute"]:
		for pose in ["dying", "dead", "fade"]:
			for facing in FACINGS:
				var xf: Transform2D = _body(_drawn(kind, pose, facing)).xf
				var feet: Vector2 = xf * Vector2(0.0, Art.FOOT_Y)
				near(feet.x, 0.0, 0.01, "%s %s %s: the feet stay in line" % [kind, pose, facing])
				near(feet.y, Art.FOOT_Y * TILE, 0.01, "%s %s %s: and on the ground" % [kind, pose, facing])


# ----------------------------------------------- every kind in every state --

func test_every_kind_draws_in_every_pose_facing_and_look_without_error() -> void:
	for kind in ["walker", "runner", "brute", "ghoul", ""]:
		for pose in POSES + ["still", "stride"]:
			for facing in FACINGS:
				for li in LOOKS.size():
					var tape := _drawn(kind, pose, facing, li)
					check(tape.of("tex").size() + tape.of("mesh").size() == 1, "%s/%s/%s: one body" % [kind, pose, facing])
					check(tape.of("xf").size() >= 1, "%s/%s/%s: a transform set" % [kind, pose, facing])
					for c in tape.cmds:
						for a in c.args:
							if a is Transform2D:
								check(absf(a.determinant()) > 1e-6, "%s/%s/%s: a transform that can be inverted" % [kind, pose, facing])


func test_the_zoomed_out_path_still_draws_every_kind() -> void:
	# main.gd draws every other frame of the dead when zoomed out (zoom under 26): a
	# frame that does not redraw only moves the node, the next draws the figure
	for kind in ["walker", "runner", "brute", "ghoul"]:
		var z = _zombie(kind, "wander", "S")
		var n = _node(z)
		var here := Vector2(z.x, z.y)
		n.sync(false, 0, 1.0)
		z.x += 0.1
		n.sync(false, 1, 0.5)
		# (the dead are drawn a little behind the rules, by a share of a step: `STEP_FOLLOW_DEAD`; half a step on from that is half of the share of 0.1)
		near(n.tile_pos().x, here.x + 0.05 * PawnNode.STEP_FOLLOW_DEAD, 0.001, "%s moves on a frame that does not redraw" % kind)
		n.sync(true, 2, 1.0)
		var tape := _tape(n)
		check(tape.of("tex").size() + tape.of("mesh").size() == 1, "%s is drawn on the frame that redraws" % kind)
		n.free()


func test_every_kind_draws_through_the_engine() -> void:
	# the real canvas, in a tree: the warped sprite, the tint and the transforms
	var tree := Engine.get_main_loop() as SceneTree
	var nodes := []
	var drawn := [0]
	for kind in ["walker", "runner", "brute", "ghoul"]:
		for pose in ["wander", "attack", "dying", "dead"]:
			var n = PawnNode.new()
			n.setup(_zombie(kind, pose, "E"), true, DATA, "zt")
			n.draw.connect(func(): drawn[0] += 1)
			tree.root.add_child(n)
			n.queue_redraw()
			nodes.append(n)
	await tree.process_frame
	await tree.process_frame
	eq(drawn[0], nodes.size(), "every node was drawn by the engine (any error logged while it ran fails this test)")
	for n in nodes:
		n.queue_free()
	await tree.process_frame


# --------------------------------------------- the variety of each of the dead --

func test_each_of_the_dead_has_a_variety_of_its_own_the_same_every_time_and_within_its_kind() -> void:
	var sizes := {}
	var gaits := {}
	for kind in ["walker", "runner", "brute"]:
		sizes[kind] = {}
		gaits[kind] = {}
		for seed_i in range(1000, 1040):
			var a: PawnMotion.Dead = PawnMotion.dead_variant(seed_i, kind)
			var b: PawnMotion.Dead = PawnMotion.dead_variant(seed_i, kind)
			eq([a.gait, a.ph, a.bob, a.sway, a.lean, a.tilt, a.gimp, a.side, a.arm, a.size, a.tint, a.weight, a.breath], [b.gait, b.ph, b.bob, b.sway, b.lean, b.tilt, b.gimp, b.side, b.arm, b.size, b.tint, b.weight, b.breath], "%s %d: the same figure gets the same variety" % [kind, seed_i])
			check(a.size > 0.9 and a.size < 1.1, "%s: a few percent of size, not more: %s" % [kind, a.size])
			check(a.tint.a == 1.0 and a.tint.r > 0.6 and a.tint.g > 0.6 and a.tint.b > 0.6, "%s: a little dirt, not a colour: %s" % [kind, a.tint])
			sizes[kind][snappedf(a.size, 0.001)] = true
			gaits[kind][snappedf(a.gait, 0.001)] = true
	for kind in sizes:
		check(sizes[kind].size() >= 10 and gaits[kind].size() >= 10, "%s: forty of them are not a copy of one (%d sizes, %d gaits)" % [kind, sizes[kind].size(), gaits[kind].size()])
	var walker: PawnMotion.Dead = PawnMotion.dead_variant(7, "walker")
	var runner: PawnMotion.Dead = PawnMotion.dead_variant(7, "runner")
	var brute: PawnMotion.Dead = PawnMotion.dead_variant(7, "brute")
	check(runner.gait >= 1.2 and runner.gait <= 1.5 and brute.gait >= 0.72 and brute.gait <= 0.88 and walker.gait >= 0.8 and walker.gait <= 1.2, "a runner cycles faster than a walker, a brute slower")
	check(brute.weight > walker.weight and walker.weight > runner.weight, "and a brute's steps land the heaviest")
	var other: PawnMotion.Dead = PawnMotion.dead_variant(8, "walker")
	check(other.ph != walker.ph or other.gait != walker.gait, "a neighbour is another")
	# a node that is left its own variety draws it: the legs' phase starts from its own
	var z = _zombie("walker", "wander", "E")
	var mine = _node(z, PawnNode, true)
	check(mine._dv != null and is_equal_approx(mine._vphase, float(z.walk_phase) * mine._dv.gait + mine._dv.ph), "its legs run on its own gait and from its own start in the cycle")
	mine.free()
