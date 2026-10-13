extends "res://tests/case.gd"
## The work poses (round 16, scripts/render/work_anim.gd): every job has a pose, a tool and a motion that is a pure
## function of (work, work_t, phase); a person who is not working is drawn exactly as before; the dead and the downed are
## untouched; nothing is made anew each frame. Headless cannot render, so the node draws into a stand-in for the canvas that
## writes down every command (the Tape of test_pawn_kinds.gd); how it looks is for screenshots (tools/work_sheet.gd).

const GD := preload("res://scripts/game_data.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const Prefs := preload("res://scripts/prefs.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const WorkAnim := preload("res://scripts/render/work_anim.gd")
const Kinds := preload("res://tests/test_pawn_kinds.gd")

const FACINGS := ["S", "E", "N", "W"]
const STATES := ["idle", "walk", "shoot", "reload", "downed", "turned", "dead", "bed"]
## A short digest of everything a person draws, per person, facing and state (see `digests`). A person who is not at work must keep
## drawing exactly this. It was made from the node as it was before there was any work pose, and made again on 2026-10-09 (the
## animation rounds of 2026-10-07, ANIM and FEEL, "the animations are clunky and weird", changed what a person draws on purpose: the
## eased turn, the stride, a shot near them, a breath); if the person's look is changed on purpose again, print
## `load("res://tests/test_work_anim.gd").new().digests()` from a script and paste the new table.
const PERSON_DIGESTS := {
	"ana/E": "f96cc363218c",
	"ana/N": "2f5766a68c4b",
	"ana/S": "d09d03ebf715",
	"ana/W": "9a16ac08f0a6",
	"dez/E": "78779940ba9d",
	"dez/N": "f8a72e6a0c75",
	"dez/S": "5fe72925931f",
	"dez/W": "b7859d11ed1f",
	"ruth/E": "c6811afe5b8e",
	"ruth/N": "d7dc2cea345d",
	"ruth/S": "a17539e6c146",
	"ruth/W": "403e5f9a40e8",
}

var _data: Dictionary = {}


## A canvas stand-in that also remembers which texture object each picture was drawn with.
class IdTape:
	extends "res://tests/test_pawn_kinds.gd".Tape
	var ids := {}
	var paths := {}    # path -> {texture object id: true}

	func draw_texture_rect(tex: Texture2D, rect: Rect2, tile: bool, mod: Color = Color.WHITE, _transpose = false) -> void:
		ids[tex.get_instance_id()] = true
		if not paths.has(tex.resource_path):
			paths[tex.resource_path] = {}
		paths[tex.resource_path][tex.get_instance_id()] = true
		rec("tex", [tex.resource_path, rect, tile, mod])


## A canvas that draws nothing (to time the drawing code itself, not the writing down of it).
class NullPen:
	extends RefCounted

	func draw_set_transform_matrix(_m: Transform2D) -> void:
		pass

	func draw_colored_polygon(_pts: PackedVector2Array, _col: Color, _uvs = null, _tex = null) -> void:
		pass

	func draw_polyline(_pts: PackedVector2Array, _col: Color, _width: float = -1.0, _aa: bool = false) -> void:
		pass

	func draw_line(_a: Vector2, _b: Vector2, _col: Color, _width: float = -1.0, _aa: bool = false) -> void:
		pass

	func draw_circle(_c: Vector2, _r: float, _col: Color, _filled = true, _width = -1.0, _aa = false) -> void:
		pass

	func draw_texture_rect(_tex: Texture2D, _rect: Rect2, _tile: bool, _mod: Color = Color.WHITE, _transpose = false) -> void:
		pass

	func draw_mesh(_mesh: Mesh, _tex: Texture2D, _xf = Transform2D.IDENTITY, _mod: Color = Color.WHITE) -> void:
		pass


func _data_all() -> Dictionary:
	if _data.is_empty():
		_data = GD.load_all()
	return _data


## A person (a real one's look and weapon) in one of the states a person is drawn in.
func _person(id: String, facing: String, state: String):
	var data := _data_all()
	var def: Dictionary = {}
	for d in data.people:
		if d.id == id:
			def = d
	var p = Sim.Person.new()
	p.def = def
	p.id = id
	p.name = def.name
	p.look = def.look
	p.weapon = def.weapon
	p.x = 40.3
	p.y = 30.1
	p.facing = facing
	p.aim = 0.4 if facing != "W" else 2.6
	p.walk_phase = 1.3
	match state:
		"walk":
			p.moving = true
		"shoot":
			p.recoil = 0.5
		"reload":
			p.reloading = 0.7
		"downed":
			p.downed = true
		"turned":
			p.turned = true
		"dead":
			p.dead = true
		"corpse":
			p.dead = true
			p.downed = true
		"bed":
			p.resting_bed = Vector2(33.0, 50.0)
	return p


func _node(p, tape = null):
	var n = PawnNode.new()
	n.setup(p, false, _data_all(), p.id)
	n._pen = tape if tape != null else Kinds.Tape.new()
	return n


func _tape(n, tape = null):
	n._pen = tape if tape != null else Kinds.Tape.new()
	n._draw()
	return n._pen


## Puts the person at work and the node's own clock at `at` (the work time shown, no easing in: the pose is full).
func _working(n, word: String, work_t: float, at: float = 10.0):
	var p = n.entity
	p.work = word
	p.work_t = work_t
	n.anim_t = at
	n.sync(false)
	# the pose has been on for a while (not easing in)
	n._wk = 1.0
	n._w_word = word
	return n


func _calm(reduced: bool) -> void:
	Prefs.set_value("ui", "reduce_motion", reduced)


## The digests of the table above: for every person, facing and state, what the node draws.
func digests() -> Dictionary:
	var out := {}
	for id in ["dez", "ruth", "ana"]:
		for facing in FACINGS:
			var all := PackedStringArray()
			for state in STATES:
				var p = _person(id, facing, state)
				var n = _node(p)
				all.append("## " + state)
				all.append(_tape(n).text())
				n.free()
			out["%s/%s" % [id, facing]] = "\n".join(all).sha256_text().substr(0, 12)
	return out


## Two drawings the same: on a difference says only where the first one differs.
func same(a: String, b: String, msg: String) -> void:
	if a == b:
		return
	var la := a.split("\n")
	var lb := b.split("\n")
	var i := 0
	while i < la.size() and i < lb.size() and la[i] == lb[i]:
		i += 1
	failures.append("%s: differs at command %d of %d/%d: %s  <>  %s" % [msg, i, la.size(), lb.size(), (la[i] if i < la.size() else "(end)").substr(0, 120), (lb[i] if i < lb.size() else "(end)").substr(0, 120)])


## Everything a pose holds, as one array, to compare two poses.
func _snap(o) -> Array:
	return o.snapshot()


# ------------------------------------------------------- every job has a pose --

func test_every_work_word_has_a_pose_and_a_tool_that_loads() -> void:
	eq(WorkAnim.WORDS.size(), 11, "the eleven words of the contract (the prison added clean)")
	for word in ["bench", "hammer", "mend", "haul", "garden", "nurse", "radio", "watch", "sort", "rest"]:
		check(WorkAnim.WORDS.has(word), "%s is a word" % word)
	for word in WorkAnim.WORDS:
		var o = WorkAnim.solve(WorkAnim.Pose.new(), word, 0.37, 0.2)
		eq(o.word, word, "the pose knows its word")
		check(o.tool != "", "%s has a tool in hand" % word)
		var tex = WorkAnim.tool_tex(o.tool)
		check(tex != null and tex is Texture2D, "%s: the picture of %s loads" % [word, o.tool])
	var none = WorkAnim.solve(WorkAnim.Pose.new(), "", 1.0, 0.0)
	eq(none.tool, "", "no word, no pose")


func test_every_tool_picture_loads_and_matches_its_data() -> void:
	var names: Array = WorkAnim.tool_names()
	check(names.size() >= 12, "a good set of tools: %d" % names.size())
	for name in names:
		var def: Dictionary = WorkAnim.tool_def(name)
		var tex: Texture2D = WorkAnim.tool_tex(name)
		check(tex != null, "%s loads" % name)
		if tex == null:
			continue
		eq(tex.get_width(), int(def.w), "%s: the width in tools.json is the picture's" % name)
		eq(tex.get_height(), int(def.h), "%s: the height in tools.json is the picture's" % name)
		check(def.grip[0] >= 0 and def.grip[0] <= def.w and def.grip[1] >= 0 and def.grip[1] <= def.h, "%s: the grip is on the picture" % name)
	# every tool a pose or a prop reaches for is among them
	for word in WorkAnim.WORDS:
		for k in 24:
			var o = WorkAnim.solve(WorkAnim.Pose.new(), word, float(k) * 0.31, 0.13)
			for t in [o.tool, o.off_tool]:
				check(t == "" or names.has(t), "%s uses a tool that exists (%s)" % [word, t])


# ---------------------------------------------------------------- the motion --

func test_the_stroke_period_is_between_eight_tenths_and_one_and_a_half_seconds() -> void:
	for word in WorkAnim.WORDS:
		var per: float = WorkAnim.period(word)
		check(per >= 0.8 and per <= 1.6, "%s: a beat of %s s" % [word, str(per)])
		var loop: float = WorkAnim.loop_period(word)
		near(loop / per, roundf(loop / per), 0.0001, "%s: the loop is whole beats" % word)


func test_the_motion_is_a_pure_function_of_work_time_and_phase() -> void:
	for word in WorkAnim.WORDS:
		var loop: float = WorkAnim.loop_period(word)
		for phase in [0.0, 0.31, 0.77]:
			for t in [0.0, 0.13, 0.5, 0.97, 1.4]:
				var a = WorkAnim.solve(WorkAnim.Pose.new(), word, t, phase)
				var b = WorkAnim.solve(WorkAnim.Pose.new(), word, t, phase)
				eq(_snap(a), _snap(b), "%s: the same arguments, the same pose" % word)
				# one whole loop later it is the same pose (its count of strokes has gone up by the loop's)
				var c = WorkAnim.solve(WorkAnim.Pose.new(), word, t + loop, phase)
				var sa := _snap(a)
				var sc := _snap(c)
				for i in sa.size():
					if sa[i] is float:
						near(sc[i], sa[i], 0.0001, "%s at %s: field %d repeats after a loop" % [word, str(t), i])
					elif not (sa[i] is int):
						eq(sc[i], sa[i], "%s at %s: field %d repeats after a loop" % [word, str(t), i])
		# a pose at a time shifted by the loop with a shifted phase is the same too
		var d = WorkAnim.solve(WorkAnim.Pose.new(), word, 0.4 + loop * 0.5, 0.0)
		var e = WorkAnim.solve(WorkAnim.Pose.new(), word, 0.4, 0.5)
		for i in _snap(d).size():
			var x = _snap(d)[i]
			if x is float:
				near(_snap(e)[i], x, 0.0001, "%s: phase is a share of the loop (field %d)" % [word, i])


func test_a_stroke_of_the_hammer_has_its_top_and_its_bottom_and_a_dip_at_the_blow() -> void:
	var prm: Dictionary = WorkAnim.HAMMER
	var loop: float = WorkAnim.loop_period("hammer")
	var hi := -INF
	var lo := INF
	var dip_hi := -INF
	var dip_at := 0.0
	var steps := 1000
	for i in steps:
		var t := loop * float(i) / float(steps)
		var o = WorkAnim.solve(WorkAnim.Pose.new(), "hammer", t, 0.0)
		if o.tool_a > hi:
			hi = o.tool_a
		if o.tool_a < lo:
			lo = o.tool_a
		if o.dip > dip_hi:
			dip_hi = o.dip
			dip_at = t / loop
	near(hi, prm.top, 0.002, "the hammer goes up to its top")
	near(lo, prm.hit, 0.002, "and down to the blow")
	near(dip_hi, prm.dip, 0.002, "the body dips as far as it should")
	near(dip_at, prm.contact, 0.01, "and deepest at the blow")
	check(hi > lo + 1.5, "a long swing")
	# the arm is raised at the top and lowered at the blow
	var top = WorkAnim.solve(WorkAnim.Pose.new(), "hammer", loop * 0.62, 0.0)
	var blow = WorkAnim.solve(WorkAnim.Pose.new(), "hammer", loop * prm.contact, 0.0)
	check(top.main.y < blow.main.y - 0.25, "the hand is higher at the top than at the blow")


func test_the_spark_is_exactly_at_the_contact() -> void:
	for word in ["hammer", "bench", "mend"]:
		var loop: float = WorkAnim.loop_period(word)
		var u: float = WorkAnim.contact(word)
		check(u > 0.0 and u < 1.0, "%s has a contact" % word)
		var at = WorkAnim.solve(WorkAnim.Pose.new(), word, loop * u, 0.0)
		near(at.hit, 0.0, 0.0005, "%s: the effect is born at the contact" % word)
		var before = WorkAnim.solve(WorkAnim.Pose.new(), word, loop * u - 0.01, 0.0)
		check(before.hit > WorkAnim.FX_LIFE, "%s: nothing is showing a moment before it" % word)
		var after = WorkAnim.solve(WorkAnim.Pose.new(), word, loop * u + 0.1, 0.0)
		near(after.hit, 0.1, 0.0005, "%s: it ages with the time" % word)
		check(at.fx != "", "%s has an effect to show" % word)
	# one blow to a stroke: the count of blows goes up by one in each loop
	for word in ["hammer", "bench", "mend"]:
		var loop: float = WorkAnim.loop_period(word)
		var first = WorkAnim.solve(WorkAnim.Pose.new(), word, 0.0, 0.0).strike
		var later = WorkAnim.solve(WorkAnim.Pose.new(), word, loop * 3.0, 0.0).strike
		eq(later - first, 3, "%s: three loops, three blows" % word)


func test_a_person_with_a_phase_of_their_own_is_not_in_step_with_the_crew() -> void:
	var seen := {}
	for id in ["ruth", "dez", "ana", "marcus", "walt", "hector", "r07", "r08", "r09"]:
		var ph: float = WorkAnim.phase_of(id)
		check(ph >= 0.0 and ph < 1.0, "%s: a phase inside a loop" % id)
		seen[snappedf(ph, 0.001)] = true
		eq(WorkAnim.phase_of(id), ph, "%s: the same phase every time" % id)
	eq(seen.size(), 9, "nine people, nine phases")
	var a = WorkAnim.solve(WorkAnim.Pose.new(), "hammer", 3.0, WorkAnim.phase_of("dez"))
	var b = WorkAnim.solve(WorkAnim.Pose.new(), "hammer", 3.0, WorkAnim.phase_of("ana"))
	check(absf(a.tool_a - b.tool_a) > 0.01, "two builders at the same second are at different points of the swing")


# ------------------------------------------------- easing in and out of the pose --

func test_the_pose_is_eased_in_and_out_in_two_tenths_of_a_second() -> void:
	near(WorkAnim.EASE, 0.2, 0.0001, "the ease is 0.2 s")
	# out: from the full pose to nothing in EASE seconds
	var k := 1.0
	var last := 1.0
	for i in 5:
		k = WorkAnim.weight(k, false, 0.04)
		check(k < last, "going down")
		last = k
	near(k, 0.0, 0.0001, "after 0.2 s the person is back to the normal figure")
	# in: from nothing to the full pose in EASE seconds
	k = 0.0
	for i in 5:
		k = WorkAnim.weight(k, true, 0.04)
	near(k, 1.0, 0.0001, "and fully in the pose after 0.2 s")
	near(WorkAnim.weight(1.0, false, 0.1), 0.5, 0.0001, "halfway at 0.1 s")
	near(WorkAnim.weight(0.0, true, 5.0), 1.0, 0.0001, "never more than one")
	near(WorkAnim.weight(1.0, false, 5.0), 0.0, 0.0001, "never less than nothing")
	# the shape of the ease is smooth (flat at both ends) and half at the middle
	near(WorkAnim.eased(0.0), 0.0, 0.0001, "no pose at nothing")
	near(WorkAnim.eased(1.0), 1.0, 0.0001, "all of it at one")
	near(WorkAnim.eased(0.5), 0.5, 0.0001, "half at half")
	check(WorkAnim.eased(0.1) < 0.1, "slow at the start")


func test_reduced_motion_shows_the_pose_still() -> void:
	for word in WorkAnim.WORDS:
		var a = WorkAnim.solve(WorkAnim.Pose.new(), word, 0.0, 0.0, true)
		for t in [0.2, 0.71, 3.3]:
			for phase in [0.0, 0.4]:
				var b = WorkAnim.solve(WorkAnim.Pose.new(), word, t, phase, true)
				eq(_snap(b), _snap(a), "%s: the same pose whatever the time (reduced motion)" % word)
		check(a.hit > WorkAnim.FX_LIFE, "%s: no sparks or puffs when the screen is to be still" % word)
		eq(a.sweep, 0, "%s: the head does not turn" % word)
		check(a.tool != "", "%s still holds its tool" % word)


# ------------------------------------------------------------ the figure drawn --

func test_a_person_not_at_work_is_drawn_exactly_as_before() -> void:
	var now := digests()
	eq(now.size(), PERSON_DIGESTS.size(), "a digest for every person and facing")
	for label in PERSON_DIGESTS:
		eq(now.get(label), PERSON_DIGESTS[label], "what a person draws, %s (all states)" % label)


func test_the_downed_the_dead_and_the_resting_are_untouched_by_work() -> void:
	for state in ["downed", "turned", "corpse", "bed"]:
		for facing in ["S", "W"]:
			var plain = _person("dez", facing, state)
			var n1 = _node(plain)
			var base: String = _tape(n1).text()
			var busy = _person("dez", facing, state)
			var n2 = _node(busy)
			_working(n2, "hammer", 2.0)
			same(_tape(n2).text(), base, "%s %s: drawn as ever though a work word is left on them" % [state, facing])
			n1.free()
			n2.free()


func test_a_person_who_is_walking_or_fighting_is_not_drawn_at_work() -> void:
	for state in ["walk", "shoot", "reload"]:
		var plain = _person("dez", "S", state)
		var n1 = _node(plain)
		n1.anim_t = 10.3
		var base: String = _tape(n1).text()
		var busy = _person("dez", "S", state)
		var n2 = _node(busy)
		_working(n2, "hammer", 2.0)
		# (the work word has not been taken off them: the pose goes out in two tenths of a second, then it is the ordinary figure)
		n2.anim_t = 10.1
		check(_tape(n2).text() != base, "%s: on its way out" % state)
		n2.anim_t = 10.2
		_tape(n2)
		n2.anim_t = 10.3
		same(_tape(n2).text(), base, "%s: the ordinary figure" % state)
		n1.free()
		n2.free()
	# a person at their post with a target is shooting, not working
	var p = _person("dez", "S", "idle")
	p.target = Sim.Zombie.new()
	var n3 = _node(p)
	_working(n3, "bench", 2.0)
	n3.anim_t = 10.1
	_tape(n3)
	n3.anim_t = 10.2
	_tape(n3)
	n3.anim_t = 10.3
	var plain_p = _person("dez", "S", "idle")
	plain_p.target = p.target
	var n4 = _node(plain_p)
	n4.anim_t = 10.3
	same(_tape(n3).text(), _tape(n4).text(), "a person with a target in their sights")
	n3.free()
	n4.free()


func test_every_work_word_is_drawn_with_its_tool_from_every_side() -> void:
	for word in WorkAnim.WORDS:
		for facing in FACINGS:
			var p = _person("ana", facing, "idle")
			var n = _node(p)
			_working(n, word, 0.3)
			var tape = _tape(n)
			var o = n._wpose
			var drawn := PackedStringArray()
			for c in tape.of("tex"):
				drawn.append(String(c.args[0]))
			check(drawn.size() >= (1 if word == "watch" else 2), "%s %s: the body and more are drawn" % [word, facing])
			var tool_file: String = String(WorkAnim.tool_def(o.tool).file)
			if not (word == "watch" and (facing == "N" or facing == "S")):
				check(drawn.has(tool_file) or o.tool == "binoculars", "%s %s: the tool %s is in the picture" % [word, facing, o.tool])
			# the weapon is put away while at work
			var weapon_path: String = _data_all().weaponArt.files[p.weapon]
			check(not drawn.has(weapon_path), "%s %s: no weapon in hand at work" % [word, facing])
			n.free()


func test_a_person_who_stops_working_is_back_to_normal_within_two_tenths_of_a_second() -> void:
	var plain = _person("dez", "E", "idle")
	var n0 = _node(plain)
	n0.anim_t = 10.31    # (the breathing of an idle figure is a function of the clock)
	var base: String = _tape(n0).text()
	n0.free()
	var p = _person("dez", "E", "idle")
	var n = _node(p)
	_working(n, "hammer", 2.0)
	check(_tape(n).text() != base, "at work: not the ordinary figure")
	# the work stops: the pose fades over two tenths of a second
	p.work = ""
	p.work_t = 0.0
	n.anim_t = 10.1
	var mid: String = _tape(n).text()
	check(mid != base, "0.1 s later it is still on its way back")
	check(n._wk > 0.0 and n._wk < 1.0, "halfway")
	n.anim_t = 10.2
	_tape(n)
	n.anim_t = 10.31
	same(_tape(n).text(), base, "0.3 s after: the ordinary figure again")
	n.free()


func test_a_person_who_starts_working_eases_into_the_pose() -> void:
	var p = _person("dez", "E", "idle")
	var n = _node(p)
	n.anim_t = 5.0
	n.sync(false)
	_tape(n)
	eq(n._wk, 0.0, "not at work: no pose")
	p.work = "hammer"
	p.work_t = 0.0
	n.anim_t = 5.1
	_tape(n)
	check(n._wk > 0.0 and n._wk < 1.0, "half way into the pose at 0.1 s")
	n.anim_t = 5.31
	_tape(n)
	near(n._wk, 1.0, 0.0001, "fully in it at 0.2 s")
	n.free()


func test_reduced_motion_draws_the_same_picture_at_any_time() -> void:
	_calm(true)
	for word in ["hammer", "garden", "watch", "radio"]:
		var p = _person("dez", "E", "idle")
		var n = _node(p)
		_working(n, word, 0.2)
		var first: String = _tape(n).text()
		_working(n, word, 3.1)
		eq(_tape(n).text(), first, "%s: still when the player asked for less motion" % word)
		n.free()
	_calm(false)
	var p2 = _person("dez", "E", "idle")
	var n2 = _node(p2)
	_working(n2, "hammer", 0.2)
	var a: String = _tape(n2).text()
	_working(n2, "hammer", 0.5)
	check(_tape(n2).text() != a, "and moving when not")
	n2.free()


func test_two_people_at_the_same_work_are_not_drawn_in_step() -> void:
	var texts := {}
	for id in ["dez", "ana", "ruth", "marcus"]:
		var p = _person(id, "E", "idle")
		var n = _node(p)
		_working(n, "hammer", 2.0)
		_tape(n)
		# (the same look would draw the same; compare the hand of the pose, not the clothes)
		texts[id] = snappedf(n._wpose.tool_a, 0.001)
		n.free()
	var distinct := {}
	for k in texts:
		distinct[texts[k]] = true
	check(distinct.size() >= 3, "a crew's hammers are at different points of the swing: %s" % str(texts))


func test_the_lookout_turns_to_look_about_and_the_sweep_is_slow() -> void:
	var loop: float = WorkAnim.loop_period("watch")
	check(loop >= 6.0, "a slow sweep: %s s a loop" % str(loop))
	var seen := {}
	var turns := 0
	var last := 0
	for i in 800:
		var o = WorkAnim.solve(WorkAnim.Pose.new(), "watch", loop * float(i) / 800.0, 0.0)
		seen[o.sweep] = true
		if o.sweep != last:
			turns += 1
			last = o.sweep
		check(o.squash >= WorkAnim.TURN_SQUASH - 0.0001 and o.squash <= 1.0, "the turn is a dip of the body, never a line (%s)" % str(o.squash))
	check(seen.has(0) and seen.has(1) and seen.has(-1), "looks both ways and back")
	check(turns >= 4 and turns <= 6, "a few turns in a loop: %d" % turns)
	# the view changes with the sweep: facing north, the lookout looks to the east and the west
	var views := {}
	for i in 400:
		var p = _person("dez", "N", "idle")
		var n = _node(p)
		_working(n, "watch", loop * float(i) / 400.0)
		n.sync(false)
		var tape = _tape(n)
		for c in tape.of("tex"):
			views[String(c.args[0]).get_file()] = true
		n.free()
	check(views.has("dez_N.png") and views.has("dez_E.png"), "the lookout shows the back and the side: %s" % str(views.keys()))


## How wide the body is drawn, against the full width of its picture: the picture's width on the screen over what it is unscaled
## (1 for the ordinary figure). -1 when the body was not drawn.
func _body_width(n, tape) -> float:
	for c in tape.of("tex"):
		if c.args[1] == n.pawn_rect:
			return float(c.xf.x.length()) / PawnNode.TILE
	return -1.0


## The lookout on a guard post turned to the left or the right, over and over, and at each quarter turn the body went down to 0.18 of its
## width ("thin like a line for a moment"). A turn is a short dip now: the body drawn is never thinner than MIN_SQUASH of its width.
func test_the_lookout_turning_on_a_post_is_never_a_thin_line() -> void:
	var loop: float = WorkAnim.loop_period("watch")
	check(WorkAnim.TURN_SQUASH >= 0.6 and WorkAnim.MIN_SQUASH >= 0.6, "the narrowest allowed is about two thirds of the width or more")
	var narrowest := {}
	for facing in FACINGS:
		var lo := 99.0
		var hi := 0.0
		var views := {}
		for i in 400:
			var p = _person("dez", facing, "idle")
			var n = _node(p)
			_working(n, "watch", loop * float(i) / 400.0)
			n.sync(false)
			var w := _body_width(n, _tape(n))
			check(w > 0.0, "%s: the body is drawn" % facing)
			lo = minf(lo, w)
			hi = maxf(hi, w)
			views[String(n._pen.of("tex")[0].args[0]).get_file()] = true
			n.free()
		check(lo >= 0.6 * hi, "%s: the body is never under 60%% of its widest (%.2f of %.2f)" % [facing, lo, hi])
		check(lo < 0.95 * hi, "%s: a turn still shows (%.2f of %.2f)" % [facing, lo, hi])
		narrowest[facing] = lo
		check(views.size() >= 2, "%s: and the other side is shown (%s)" % [facing, str(views.keys())])


## Whatever the pose (every word, from the front, the side and the back), the body is never made narrower than the floor.
func test_no_pose_makes_the_body_thinner_than_the_floor() -> void:
	for word in WorkAnim.WORDS:
		var loop: float = WorkAnim.loop_period(word)
		var lo := 99.0
		for i in 240:
			var o = WorkAnim.solve(WorkAnim.Pose.new(), word, loop * float(i) / 240.0, 0.3)
			for view in ["S", "E", "N"]:
				for w in [0.5, 1.0]:
					lo = minf(lo, WorkAnim.body_xf(view, o, w).x.length())
		check(lo >= WorkAnim.MIN_SQUASH - 0.0001, "%s: the body keeps %.2f of its width at the least" % [word, lo])
	# and a pose that asks for a line is held to the floor
	var o2 = WorkAnim.solve(WorkAnim.Pose.new(), "watch", 0.0, 0.0)
	o2.squash = 0.05
	for view in ["S", "E", "N"]:
		near(WorkAnim.body_xf(view, o2, 1.0).x.length(), WorkAnim.MIN_SQUASH, 0.0001, "%s: a squash of 0.05 is held to the floor" % view)


## The same flaw looked for elsewhere: a person on their feet turning through every angle (the avatar is drawn the same way) is the
## picture of one view at its full width at each, and the dead's warped bodies keep a width of their own at every row.
func test_people_and_the_dead_keep_their_width_through_a_full_turn() -> void:
	var prev := "E"
	var seen := {}
	for i in 16:
		var ang := TAU * float(i) / 16.0
		prev = Sim.facing_of(cos(ang), sin(ang), prev)
		var p = _person("ana", prev, "idle")
		p.aim = ang
		var n = _node(p)
		n.sync(false)
		near(_body_width(n, _tape(n)), 1.0, 0.0001, "facing %s (aim %d degrees): the body at its full width" % [prev, i * 22])
		seen[prev] = true
		n.free()
	eq(seen.size(), 4, "all four facings were met")
	var Art := preload("res://scripts/render/pawn_art.gd")
	for kind in ["walker", "runner", "brute"]:
		for view in ["S", "E", "N"]:
			var mesh = Art.sprite_mesh(kind, view, Rect2(-1.15, -1.42, 2.3, 2.04))
			if mesh == null:
				continue
			var v: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var lo := 99.0
			var hi := 0.0
			for j in range(0, v.size(), 2):
				var w: float = v[j + 1].x - v[j].x
				lo = minf(lo, w)
				hi = maxf(hi, w)
			check(lo >= 0.6 * hi, "%s/%s: the warped body is never under 60%% of its widest row (%.2f of %.2f)" % [kind, view, lo, hi])


func test_the_node_keeps_one_pose_and_makes_no_picture_each_frame() -> void:
	var nodes := []
	for id in ["dez", "ana", "ruth", "marcus", "walt", "hector"]:
		var p = _person(id if id in ["dez", "ana", "ruth", "marcus"] else "dez", "E", "idle")
		p.id = id if id in ["dez", "ana", "ruth", "marcus"] else "dez"
		nodes.append(_node(p))
	for i in 4:
		var p = _person("ana", "S", "idle")
		nodes.append(_node(p))
	var words := ["hammer", "bench", "mend", "haul", "garden", "nurse", "radio", "watch", "sort", "rest"]
	var tape := IdTape.new()
	var pose_ids := {}
	for frame in 90:
		for i in nodes.size():
			var n = nodes[i]
			var p = n.entity
			p.work = words[i]
			p.work_t = float(frame) / 30.0
			n.anim_t = 10.0 + float(frame) / 60.0
			n.sync(false)
			n._pen = tape
			n._draw()
			pose_ids[i] = pose_ids.get(i, {})
			pose_ids[i][n._wpose.get_instance_id()] = true
	check(tape.paths.size() >= 8, "a good many pictures were drawn: %d" % tape.paths.size())
	for path in tape.paths:
		eq(tape.paths[path].size(), 1, "%s: always the one texture object, never a new one" % path)
	eq(tape.ids.size(), tape.paths.size(), "one texture object for each picture drawn")
	for i in pose_ids:
		eq(pose_ids[i].size(), 1, "one pose object kept by node %d" % i)
	for n in nodes:
		n.free()


func test_ten_people_at_work_are_cheap_to_draw() -> void:
	var nodes := []
	var plain := []
	var words := ["hammer", "bench", "mend", "haul", "garden", "nurse", "radio", "watch", "sort", "rest"]
	for i in 10:
		var p = _person("ana", FACINGS[i % 4], "idle")
		p.work = words[i]
		nodes.append(_node(p, NullPen.new()))
		var q = _person("ana", FACINGS[i % 4], "idle")
		plain.append(_node(q, NullPen.new()))
	for n in nodes:
		n.sync(false)
		n._wk = 1.0
		n._w_word = n.entity.work
	# warm up (the tables and the pictures are made on the first look)
	for n in nodes + plain:
		n.anim_t = 10.0
		n._draw()
	var frames := 300
	var t0 := Time.get_ticks_usec()
	for frame in frames:
		for i in nodes.size():
			var n = nodes[i]
			n.entity.work_t = float(frame) / 30.0
			n.anim_t = 10.0 + float(frame) / 60.0
			n.sync(false)
			n._draw()
	var work_ms := float(Time.get_ticks_usec() - t0) / float(frames) / 1000.0
	t0 = Time.get_ticks_usec()
	for frame in frames:
		for n in plain:
			n.anim_t = 10.0 + float(frame) / 60.0
			n.sync(false)
			n._draw()
	var plain_ms := float(Time.get_ticks_usec() - t0) / float(frames) / 1000.0
	print("    ten people at work: %.2f ms of script to draw a frame; ten people standing about: %.2f ms (headless, nothing written down)" % [work_ms, plain_ms])
	check(work_ms < 6.0, "ten people at work cost %.2f ms a frame to draw" % work_ms)
	for n in nodes + plain:
		n.free()


func test_the_work_time_is_drawn_between_the_steps() -> void:
	var p = _person("dez", "E", "idle")
	var n = _node(p)
	p.work = "hammer"
	p.work_t = 1.0
	n.sync(false, 10, 1.0)
	n._wk = 1.0
	p.work_t = 1.0 + 1.0 / 30.0
	n.sync(false, 11, 0.0)
	near(n.work_time(), 1.0, 0.0001, "at the start of a step it is shown where the last step left it")
	n.sync(false, 11, 0.5)
	near(n.work_time(), 1.0 + 0.5 / 30.0, 0.0001, "half way through the step it is half way on")
	n.sync(false, 11, 1.0)
	near(n.work_time(), 1.0 + 1.0 / 30.0, 0.0001, "and at the end it is where the rules have it")
	# a change of work starts the time again (no sliding from the old clock)
	p.work = "garden"
	p.work_t = 0.0
	n.sync(false, 12, 0.3)
	near(n.work_time(), 0.0, 0.0001, "a new job starts from nothing")
	n.free()


func test_the_blow_of_a_stroke_calls_the_sound_hook_once() -> void:
	_calm(false)
	var p = _person("dez", "E", "idle")
	var n = _node(p)
	var heard := []
	n.on_work_strike = func(word: String, x: float, y: float): heard.append(word)
	n.anim_t = 10.0
	var loop: float = WorkAnim.loop_period("hammer")
	var ph: float = n._work_phase
	# walk the work time through three strokes in small steps of a frame
	var steps := 360
	for i in steps:
		p.work = "hammer"
		p.work_t = 3.0 * loop * float(i) / float(steps)
		n.anim_t = 10.0 + float(i) / 60.0
		n.sync(false)
		n._wk = 1.0
		_tape(n)
	check(heard.size() >= 3 and heard.size() <= 4, "three strokes, three blows heard (%d)" % heard.size())
	eq(heard[0] if not heard.is_empty() else "", "hammer", "and it says what was struck")
	# no sound when the screen is to be still
	_calm(true)
	heard.clear()
	for i in steps:
		p.work_t = 3.0 * loop * float(i) / float(steps)
		n.anim_t = 20.0 + float(i) / 60.0
		n.sync(false)
		n._wk = 1.0
		_tape(n)
	eq(heard.size(), 0, "silence with reduced motion (there is no swing)")
	_calm(false)
	n.free()
