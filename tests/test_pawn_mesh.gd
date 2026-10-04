extends "res://tests/case.gd"
## The cheap drawing of the figures (scripts/render/pawn_mesh.gd, scripts/render/pawn_node.gd): the dead used to cost about forty
## polygon commands each, every frame, and a crowd of eighty took the frame to 50 ms. Now the live parts of a figure are meshes baked
## from pawn_art.gd's own drawing, drawn with one palette texture; a node out of sight draws nothing; and one of the dead is not drawn
## again between two steps of the rules. Headless cannot see the picture, so these tests read the baked geometry against what the art
## says (where it is, which colour each part uses), count what a node draws, and bound what a crowd costs.

const Art := preload("res://scripts/render/pawn_art.gd")
const PawnMesh := preload("res://scripts/render/pawn_mesh.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Kinds := preload("res://tests/test_pawn_kinds.gd")
const YardKit := preload("res://tests/test_yard_avatar.gd")

const KINDS := ["walker", "runner", "brute"]


# ----------------------------------------------------------------- helpers --

## The box that a recording of draw commands covers, in the units of the drawing (a stroke's half width included).
func _tape_bounds(tape) -> Rect2:
	var pts := PackedVector2Array()
	for c in tape.cmds:
		match c.op:
			"poly":
				pts.append_array(c.args[0])
			"line":
				var half: float = float(c.args[2]) * 0.5
				for p in c.args[0]:
					pts.append(p + Vector2(half, half))
					pts.append(p - Vector2(half, half))
			"circle":
				pts.append(c.args[0] + Vector2(c.args[1], c.args[1]))
				pts.append(c.args[0] - Vector2(c.args[1], c.args[1]))
			"seg":
				pts.append(c.args[0])
				pts.append(c.args[1])
	return _box(pts)


func _mesh_bounds(mesh: Mesh) -> Rect2:
	return _box(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])


func _box(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## The slots of the palette that a mesh's vertices point at (the texel of a vertex is in its UVs).
func _slots(mesh: Mesh) -> Array:
	var seen := {}
	for uv in mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
		seen[int(floor(uv.x * PawnMesh.SLOTS))] = true
	var out := seen.keys()
	out.sort()
	return out


func _sample_pal() -> Dictionary:
	return Art.palette({"skin": "#8c8a7c", "pants": "#3b4658", "shoes": "#2a2420", "top": "#7a3a30"})


## True when the box `a` and the box `b` have their edges within `tol` of each other.
func _same_box(a: Rect2, b: Rect2, tol: float) -> bool:
	return absf(a.position.x - b.position.x) <= tol and absf(a.position.y - b.position.y) <= tol \
		and absf(a.end.x - b.end.x) <= tol and absf(a.end.y - b.end.y) <= tol


# --------------------------------------------------------- the baked parts --

func test_the_baked_legs_and_shadow_cover_what_the_art_draws() -> void:
	var pal := _sample_pal()
	var bad := []
	for kind in KINDS:
		var st := Art.style(kind)
		for view in ["S", "E"]:
			for b in [0, 5, 13, 27]:
				for limp in [false, true]:
					var phase := float(b) * TAU / float(PawnMesh.LEG_STEPS)
					var tape = Kinds.Tape.new()
					Art.shadow(tape, st)
					Art.legs(tape, pal, view, phase, true, limp, 1.0, st)
					var want := _tape_bounds(tape)
					var mesh := PawnMesh.legs(kind, view, phase, true, limp, true)
					var got := _mesh_bounds(mesh)
					# (the mesh's strokes have a soft edge round them: a few hundredths of a tile)
					if not _same_box(want, got, 0.05):
						bad.append("%s %s step %d limp %s: art %s, mesh %s" % [kind, view, b, str(limp), str(want), str(got)])
	check(bad.is_empty(), "the baked legs sit where the art puts them: %s" % str(bad.slice(0, 3)))


func test_the_baked_arms_cover_what_the_art_draws_and_each_part_has_its_own_colour() -> void:
	var pal := _sample_pal()
	var bad := []
	for kind in KINDS:
		var st := Art.style(kind)
		for view in ["S", "E", "N"]:
			for layer in ["back", "front"]:
				for attacking in [false, true]:
					var tape = Kinds.Tape.new()
					var b := 7
					var phase := float(b) * TAU / float(PawnMesh.LEG_STEPS)
					var sprint: bool = st.pose == "sprint" and not attacking
					# the time at which the claw is exactly in baked pose `b` (at rest the sway is at its middle whatever the time)
					var t := float(b) * TAU / float(PawnMesh.ARM_STEPS) / (7.0 * float(st.claw_rate)) if attacking else 1.2083
					Art.arms(tape, pal, view, t, attacking, layer, st, phase)
					var mesh := PawnMesh.arms(kind, view, layer, t, attacking, phase)
					if tape.cmds.is_empty():
						if mesh != null:
							bad.append("%s %s %s: the art has no arm here but a mesh was baked" % [kind, view, layer])
						continue
					if mesh == null:
						bad.append("%s %s %s: the art draws an arm and there is no mesh" % [kind, view, layer])
						continue
					if not _same_box(_tape_bounds(tape), _mesh_bounds(mesh), 0.06):
						bad.append("%s %s %s attacking %s%s: art %s, mesh %s" % [kind, view, layer, str(attacking), " (sprint)" if sprint else "", str(_tape_bounds(tape)), str(_mesh_bounds(mesh))])
					eq(_slots(mesh), [PawnMesh.SLOT_INK, PawnMesh.SLOT_SLEEVE, PawnMesh.SLOT_SKIN], "an arm is ink, sleeve and skin (%s %s %s)" % [kind, view, layer])
	check(bad.is_empty(), "the baked arms sit where the art puts them: %s" % str(bad.slice(0, 3)))


func test_a_leg_mesh_names_the_shoes_and_trousers_and_the_shadow_has_its_own_texel() -> void:
	var with_shadow := PawnMesh.legs("walker", "E", 0.0, false, false, true)
	var without := PawnMesh.legs("walker", "E", 0.0, false, false, false)
	eq(_slots(with_shadow), [PawnMesh.SLOT_INK, PawnMesh.SLOT_SHADOW, PawnMesh.SLOT_PANTS, PawnMesh.SLOT_PANTS_BACK, PawnMesh.SLOT_SHOE, PawnMesh.SLOT_SHOE_BACK], "side view: both legs and both shoes, the ink and the shadow")
	eq(_slots(without), [PawnMesh.SLOT_INK, PawnMesh.SLOT_PANTS, PawnMesh.SLOT_PANTS_BACK, PawnMesh.SLOT_SHOE, PawnMesh.SLOT_SHOE_BACK], "a corpse has no shadow")
	eq(_slots(PawnMesh.legs("walker", "S", 0.0, false, false, false)), [PawnMesh.SLOT_INK, PawnMesh.SLOT_PANTS, PawnMesh.SLOT_SHOE], "front view: the near trousers and shoes only")
	var hands := PawnMesh.hands(0.4)
	eq(_slots(hands), [PawnMesh.SLOT_INK, PawnMesh.SLOT_SKIN], "the hands on a weapon")
	check(_mesh_bounds(PawnMesh.hands(0.4)).size.x > _mesh_bounds(PawnMesh.hands(null)).size.x, "a second hand on the front of the weapon widens the grip")


func test_the_palette_texture_holds_the_figures_own_colours() -> void:
	var pal := _sample_pal()
	var tex := PawnMesh.palette_texture(pal)
	var img := tex.get_image()
	eq(img.get_width(), PawnMesh.SLOTS, "one texel for each colour")
	var tol := 1.0 / 255.0 + 0.001
	for pair in [[PawnMesh.SLOT_PANTS, pal.pants], [PawnMesh.SLOT_PANTS_BACK, pal.pants_back], [PawnMesh.SLOT_SHOE, pal.shoe], [PawnMesh.SLOT_SHOE_BACK, pal.shoe_back], [PawnMesh.SLOT_SLEEVE, pal.sleeve], [PawnMesh.SLOT_SKIN, pal.skin]]:
		var got := img.get_pixel(pair[0], 0)
		check(absf(got.r - pair[1].r) <= tol and absf(got.g - pair[1].g) <= tol and absf(got.b - pair[1].b) <= tol, "texel %d is the figure's colour: %s against %s" % [pair[0], str(got), str(pair[1])])
		eq(got.a, 1.0, "and opaque (the strength of a stroke is in the mesh)")
	check(PawnMesh.palette_texture(pal) == tex, "the same colours are the same texture")
	check(PawnMesh.palette_texture(Art.palette({"skin": "#a09876", "pants": "#2c2d31", "shoes": "#4a4038", "top": "#cfc9b8"})) != tex, "other colours, another texture")


func test_one_mesh_serves_every_look_and_a_pose_is_the_nearest_baked() -> void:
	var a := PawnMesh.legs("walker", "E", 1.0, true, false, true)
	var b := PawnMesh.legs("walker", "E", 1.0 + 0.4 * TAU / float(PawnMesh.LEG_STEPS), true, false, true)
	check(a == b, "a phase within half a step of the baked one draws that one (the mesh is shared)")
	var c := PawnMesh.legs("walker", "E", 1.0 + TAU / 4.0, true, false, true)
	check(a != c, "a quarter turn on is a different pose")
	check(PawnMesh.legs("walker", "E", 1.0, true, false, true) == PawnMesh.legs("walker", "E", 1.0 + TAU, true, false, true), "and a full turn is the same pose")
	check(PawnMesh.legs("walker", "S", 0.3, false, false, true) == PawnMesh.legs("walker", "S", 4.0, false, false, true), "one that stands has one pose, whatever its phase")
	check(PawnMesh.legs("walker", "E", 1.0, true, false, true) != PawnMesh.legs("runner", "E", 1.0, true, false, true), "a runner's stride is its own")
	check(PawnMesh.legs("walker", "E", 1.0, true, false, true) != PawnMesh.legs("walker", "E", 1.0, true, true, true), "and so is a limp")


# --------------------------------------------------------- what a node draws --

func test_a_figure_is_a_handful_of_draws_not_dozens() -> void:
	var kinds := Kinds.new()
	var worst := 0
	var old_walker := 0
	for kind in KINDS:
		for pose in Kinds.POSES:
			for facing in Kinds.FACINGS:
				var z = kinds._zombie(kind, pose, facing, 1)
				var n = PawnNode.new()
				n.setup(z, true, Kinds.DATA, "zt")
				n._pen = Kinds.Tape.new()
				n.meshes_on_tape = true
				n._draw()
				var tape = n._pen
				for op in ["poly", "line", "circle", "seg"]:
					eq(tape.of(op).size(), 0, "no %s command (%s %s %s): the parts are meshes" % [op, kind, pose, facing])
				var drawn: int = tape.of("mesh").size() + tape.of("tex").size()
				worst = maxi(worst, drawn)
				if kind == "walker" and pose == "wander" and facing == "E":
					n._pen = Kinds.Tape.new()
					n.meshes_on_tape = false
					n._draw()
					old_walker = n._pen.cmds.size()
				n.free()
	check(worst <= 5, "at most legs, two layers of arms and the body are drawn: %d" % worst)
	check(old_walker >= 30, "(and the commands of the same walker were %d)" % old_walker)


func test_a_person_is_legs_body_weapon_and_hands() -> void:
	var main := _yard()
	var ruth = main.sim.avatar.player()
	var node = main.pawn_nodes[ruth]
	var tape = Kinds.Tape.new()
	node._pen = tape
	node.meshes_on_tape = true
	node._draw()
	node._pen = node
	node.meshes_on_tape = false
	for op in ["poly", "line", "circle", "seg"]:
		eq(tape.of(op).size(), 0, "no %s command for a person standing" % op)
	eq(tape.of("mesh").size(), 2, "the legs (with the shadow) and the hands are the two meshes, besides the body and the weapon")
	eq(tape.of("tex").size(), 2, "the body and the weapon are their pictures")
	await TutorialKit.leave(main)


# --------------------------------------------------- off screen, and between steps --

func _yard() -> Node:
	var yard = YardKit.new()
	return yard._game()


func test_a_zombie_out_of_sight_makes_no_draw() -> void:
	var main := _yard()
	var sim = main.sim
	var tree := Engine.get_main_loop() as SceneTree
	var near = sim.spawn(41.5, 30.5, "approach", "walker")
	var far = sim.spawn(5.0, 5.0, "approach", "walker")
	main._sync_views()
	var n_near = main.pawn_nodes[near]
	var n_far = main.pawn_nodes[far]
	check(n_near.visible, "the one in the window is shown")
	check(not n_far.visible, "the one far from the window is not")
	await tree.process_frame
	await tree.process_frame
	var base := PawnNode.draw_count()
	var seen_far := [0]
	n_far.draw.connect(func(): seen_far[0] += 1)
	for i in 4:
		main._sim_step()
		main._sync_views()
		await tree.process_frame
	eq(seen_far[0], 0, "the node out of sight was not drawn in four steps")
	check(PawnNode.draw_count() > base, "while the one in sight was")
	# and it is drawn when it comes into sight
	far.x = 41.0
	far.y = 31.0
	main._sync_views()
	await tree.process_frame
	await tree.process_frame
	check(n_far.visible and seen_far[0] > 0, "it is drawn as it comes into the window")
	await TutorialKit.leave(main)


func test_one_of_the_dead_is_drawn_once_a_step_not_once_a_frame() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var kinds := Kinds.new()
	var z = kinds._zombie("walker", "wander", "E", 0)
	var n = PawnNode.new()
	n.setup(z, true, Kinds.DATA, "zt")
	tree.root.add_child(n)
	var drawn := [0]
	n.draw.connect(func(): drawn[0] += 1)
	await tree.process_frame
	await tree.process_frame
	drawn[0] = 0
	n.sync(true, 10, 0.1)
	await tree.process_frame
	eq(drawn[0], 1, "a new step is drawn")
	for alpha in [0.3, 0.5, 0.8]:
		n.sync(true, 10, alpha)
		await tree.process_frame
	eq(drawn[0], 1, "three more frames of the same step are not")
	n.sync(true, 11, 0.1)
	await tree.process_frame
	eq(drawn[0], 2, "the next step is")
	check(n.position.distance_to(Vector2(z.x, z.y) * 64.0) < 64.0, "(and the node still moves with the frame: its place is its position)")
	n.queue_free()
	await tree.process_frame


# ------------------------------------------------------------- the cost --

## Eighty of the dead redrawn, through the engine's own canvas, against the same with the commands of the old drawing. Generous: the
## numbers of a machine that is doing other things; what is asked is that the baked drawing is not slower, and cheap in itself.
func test_a_crowd_of_eighty_is_cheap_to_draw() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var kinds := Kinds.new()
	var nodes := []
	for i in 80:
		var z = kinds._zombie(KINDS[i % 3], ["wander", "attack", "limp", "idle"][i % 4], Kinds.FACINGS[i % 4], i % 3)
		z.walk_phase = 0.37 * float(i)
		var n = PawnNode.new()
		n.setup(z, true, Kinds.DATA, "zt")
		tree.root.add_child(n)
		nodes.append(n)
	await tree.process_frame
	await tree.process_frame
	var per := {}
	for cached in [false, true]:
		for n in nodes:
			n.cached = cached
		var best := 1e9
		for rep in 4:
			for n in nodes:
				n.queue_redraw()
			var t0 := Time.get_ticks_usec()
			await tree.process_frame
			best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
		per[cached] = best
	print("    80 of the dead, one frame of redraws: %.2f ms as commands, %.2f ms as meshes (headless, nothing written down)" % [per[false], per[true]])
	check(per[true] < 25.0, "eighty redrawn in under 25 ms (%.2f)" % per[true])
	check(per[true] <= per[false] * 1.5, "and not slower than the commands, whatever else the machine is doing (%.2f against %.2f)" % [per[true], per[false]])
	for n in nodes:
		n.queue_free()
	await tree.process_frame
