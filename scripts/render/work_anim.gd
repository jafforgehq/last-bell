## People at work (round 16): the pose, the tool and the small effects of every job, drawn on the figure the game already
## has. A person's body is one baked picture (head, shoulders and chest) with live legs; this adds live arms, a tool in
## the hand and a few small things (a puff where the hammer lands, a glint, steam, radio waves), all moved by transforms,
## so the figure keeps its look and nothing is a new picture of a person.
##
## `Person.work` (the rules set it: "" | bench | hammer | mend | haul | garden | nurse | radio | watch | sort | rest) and
## `Person.work_t` (the seconds the work has gone on) are all it reads. The pose is a pure function of
## (word, time, phase): `solve` fills a Pose in place (the node keeps one, so nothing is allocated a frame), and `draw_person`
## draws it. The rules never see any of this.
##
## The pose is worked out once, in "side view" numbers, then seen from the front, the side or the back by `proj`: a point is
## (f, y, l), f forward, y up and down the screen as in the side view (the shoulders at -0.2, the feet at 0.3), l toward the
## figure's right. Facing east f is x; facing the player forward comes down the screen by DEPTH of itself and the figure's
## right is the left of the screen; facing away it goes up the screen. So one pose reads from every side.
extends RefCounted

const GD := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/render/pawn_art.gd")
const S := preload("res://scripts/render/shapes.gd")
const Prefs := preload("res://scripts/prefs.gd")

const TOOLS_FILE := "res://assets/data/tools.json"

## The ten words of the contract (the rules' `Person.work`).
const WORDS := ["bench", "hammer", "mend", "haul", "garden", "nurse", "radio", "watch", "sort", "rest", "clean"]
## The pose comes in and goes out over this many seconds.
const EASE := 0.2
## How long a puff, a spark or a chip shows after the blow, in seconds.
const FX_LIFE := 0.42
## How far down the screen forward comes, seen from the front (and up it, from behind).
const DEPTH := 0.5
const SH_Y := -0.2
const SH_L := 0.27
const HIPS_Y := 0.13
## How narrow the body is shown at the middle of a quarter turn (the lookout's sweep), against its full width, and the narrowest any pose
## may make it. It was 0.18 (a sliver, "a thin line" when the lookout turned on a guard post); a turn is a quick dip to about three
## quarters of the width where the other side is shown, and the floor keeps a pose of the future from thinning the body past it.
const TURN_SQUASH := 0.76
const MIN_SQUASH := 0.6
## The pose that stands for a word when the player asked for less motion (a share of its loop).
const STILL_U := {"hammer": 0.615, "bench": 0.6, "mend": 0.615, "haul": 0.12, "garden": 0.05, "nurse": 0.14, "radio": 0.7, "watch": 0.05, "sort": 0.45, "rest": 0.05, "clean": 0.1}
## word -> [the beat in seconds, how many beats make the loop that repeats exactly]
const CYCLE := {
	"hammer": [1.25, 1], "bench": [0.9, 1], "mend": [1.1, 1], "haul": [1.6, 2], "garden": [1.4, 5],
	"nurse": [1.6, 2], "radio": [1.2, 4], "watch": [1.6, 5], "sort": [1.6, 2], "rest": [1.6, 4], "clean": [1.0, 2],
}
## The swings: the top and the bottom of the tool's angle (radians, 0 forward and up is positive), where it rests, the share
## of the loop (of the beat) at which it lands, the reach of the arm, how far the head of the tool is from the hand, how far
## the body leans (back at the top, forward at the blow), how far it dips at the blow, how wide the feet stand.
const HAMMER := {"top": 1.75, "hit": -0.55, "rest": 0.25, "contact": 0.78, "reach": 0.40, "len": 0.55, "lean_up": -0.08, "lean_hit": 0.22, "dip": 0.05, "stance": 1.7}
const MALLET := {"top": 1.25, "hit": -0.25, "rest": 0.4, "contact": 0.76, "reach": 0.34, "len": 0.34, "lean_up": 0.02, "lean_hit": 0.14, "dip": 0.025, "stance": 1.3}
const MEND := {"top": 1.5, "hit": -0.3, "rest": 0.3, "contact": 0.76, "reach": 0.38, "len": 0.52, "lean_up": -0.04, "lean_hit": 0.18, "dip": 0.04, "stance": 1.6}
const HOE := {"yaw": -0.8, "top": 0.95, "hit": -0.4, "rest": 0.15, "contact": 0.7, "reach": 0.30, "len": 0.81, "lean_up": 0.14, "lean_hit": 0.42, "dip": 0.05, "stance": 1.5}

## The face, where the binoculars, the handset and the mug go: from the side the eyes are at x 0.17, from the front and the
## back in the middle; the mouth is lower.
const FACE_X := 0.17
const FACE_Y := -0.6

static var _defs: Dictionary = {}
static var _tex: Dictionary = {}
static var _rects: Dictionary = {}
static var _styles: Dictionary = {}


## One person's pose at an instant: everything draw_person needs, filled in by `solve`.
class Pose:
	extends RefCounted
	var word := ""
	var u := 0.0                  # how far through the loop
	var tool := ""                # in the main (right) hand
	var tool_a := 0.0             # its angle in the plane of forward and up (0 forward, up is positive); for a tool with no long side, its roll
	var tool_at := Vector2.ZERO   # where it is held (f, y)
	var tool_l := 0.2
	var tool_yaw := 0.0           # how far across the body it points (toward the figure's right is positive)
	var tool_face := false        # held at the face
	var main := Vector2.ZERO      # the main hand (f, y)
	var main_l := 0.2
	var main_face := false
	var off := Vector2.ZERO       # the other hand
	var off_l := -0.2
	var off_face := false
	var off_tool := ""
	var off_a := 0.0
	var off_at := Vector2.ZERO
	var grip2 := -1.0             # more than 0: the other hand holds the main tool this far from the grip
	var lean := 0.0               # the body leans forward (radians) about the hips
	var dip := 0.0                # and drops this far
	var shift := 0.0              # and moves this far forward
	var tilt := 0.0               # and rocks (a nod, a shift of weight)
	var stance := 1.0             # how wide the feet stand
	var sweep := 0                # -1, 0, 1: turned a quarter to the left, ahead, to the right
	var squash := 1.0             # how wide the body is shown while it turns
	var head := ""                # what is worn on the head
	var hit := 99.0               # seconds since the tool landed
	var fx := ""                  # what the blow throws up: chips, sparks, dust
	var fx_at := Vector2.ZERO
	var strike := 0               # blows struck so far (counts up forever)
	var glint := 0.0              # the medical cross
	var glint_at := Vector2.ZERO
	var steam := false
	var wave := -1.0              # radio waves: where in their growth, or -1
	var wave_k := 0.0
	var water := -1.0             # water from a can: how far through the pour, or -1
	var prop := ""                # something on the ground: planks, can, crates
	var sort_k := -1.0            # sorting: how far the hand is from the first crate to the second, or -1
	var sort_lift := 0.0
	var item := 0.0               # the thing in the hand (0 none, else its size)
	var item_kind := 0

	func reset() -> void:
		word = ""
		u = 0.0
		tool = ""
		tool_a = 0.0
		tool_at = Vector2(0.1, 0.0)
		tool_l = 0.2
		tool_yaw = 0.0
		tool_face = false
		main = Vector2(0.06, -0.02)
		main_l = 0.2
		main_face = false
		off = Vector2(0.0, -0.02)
		off_l = -0.2
		off_face = false
		off_tool = ""
		off_a = 0.0
		off_at = Vector2(0.0, -0.02)
		grip2 = -1.0
		lean = 0.0
		dip = 0.0
		shift = 0.0
		tilt = 0.0
		stance = 1.0
		sweep = 0
		squash = 1.0
		head = ""
		hit = 99.0
		fx = ""
		fx_at = Vector2(0.7, 0.2)
		strike = 0
		glint = 0.0
		glint_at = Vector2.ZERO
		steam = false
		wave = -1.0
		wave_k = 0.0
		water = -1.0
		prop = ""
		sort_k = -1.0
		sort_lift = 0.0
		item = 0.0
		item_kind = 0

	## Everything in one array (floats, ints and strings), to compare two poses.
	func snapshot() -> Array:
		return [word, u, tool, tool_a, tool_at.x, tool_at.y, tool_l, tool_yaw, tool_face, main.x, main.y, main_l, main_face, off.x, off.y, off_l, off_face,
			off_tool, off_a, off_at.x, off_at.y, grip2, lean, dip, shift, tilt, stance, sweep, squash, head, hit, fx, fx_at.x, fx_at.y, strike,
			glint, glint_at.x, glint_at.y, steam, wave, wave_k, water, prop, sort_k, sort_lift, item, item_kind]


# ----------------------------------------------------------------- the tools --

## The tools' data (assets/data/tools.json, written by tools/make_tools.py): the file, the size and the grip of each.
static func _load_defs() -> void:
	if not _defs.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TOOLS_FILE))
	if parsed is Dictionary:
		_defs = parsed.tools
		_defs["_density"] = float(parsed.density)


static func tool_names() -> Array:
	_load_defs()
	var out: Array = []
	for k in _defs:
		if not k.begins_with("_"):
			out.append(k)
	return out


static func tool_def(name: String) -> Dictionary:
	_load_defs()
	return _defs.get(name, {})


static func tool_tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var def := tool_def(name)
		_tex[name] = GD.tex(String(def.file)) if not def.is_empty() else null
	return _tex[name]


## Where the picture goes, in tiles from the grip.
static func tool_rect(name: String) -> Rect2:
	if not _rects.has(name):
		var def := tool_def(name)
		var d := float(_defs["_density"])
		_rects[name] = Rect2(-float(def.grip[0]) / d, -float(def.grip[1]) / d, float(def.w) / d, float(def.h) / d)
	return _rects[name]


# --------------------------------------------------------------- the motion --

static func period(word: String) -> float:
	return float(CYCLE[word][0]) if CYCLE.has(word) else 1.0


static func loop_period(word: String) -> float:
	return float(CYCLE[word][0]) * float(CYCLE[word][1]) if CYCLE.has(word) else 1.0


## Where in the loop (0 to 1) the tool lands, or -1 for a job with no blow of its own.
static func contact(word: String) -> float:
	match word:
		"hammer":
			return HAMMER.contact
		"bench":
			return MALLET.contact
		"mend":
			return MEND.contact
		"haul":
			return 0.5
		"sort":
			return 0.36
		"clean":
			return 0.25
	return -1.0


## A person's own place in the loop, from who they are: the same every time, spread so that a crew is not in step.
static func phase_of(id: String) -> float:
	var h := 5381
	for i in id.length():
		h = (h * 33 + id.unicode_at(i)) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h % 100003) / 100003.0


## Whether the player asked for less motion.
static func reduced() -> bool:
	return Prefs.on("ui", "reduce_motion")


## How far into the pose a person is, 0 (the ordinary figure) to 1, moved toward where it is going over EASE seconds.
static func weight(k: float, working: bool, dt: float) -> float:
	var r := k + (dt if working else -dt) / EASE
	return 0.0 if r < 0.0005 else (1.0 if r > 0.9995 else r)


## The eased share (flat at both ends).
static func eased(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


static func _seg(u: float, a: float, b: float) -> float:
	return clampf((u - a) / (b - a), 0.0, 1.0)


static func _io(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## A triangle of height 1 and half-width `w` about `c`, on the circle of the loop.
static func _bump(u: float, c: float, w: float) -> float:
	var d := absf(fposmod(u - c + 0.5, 1.0) - 0.5)
	return maxf(0.0, 1.0 - d / w)


## The shoulders (f, y) of a body that leans, dips and moves forward.
static func _shoulder(lean: float, dip: float, shift: float) -> Vector2:
	return Vector2(shift + sin(lean) * 0.33, HIPS_Y + dip - cos(lean) * 0.33)


## The angle of a swinging tool through one stroke u (0 to 1): up slowly, held cocked, down fast to the blow at c, and back
## with a small rebound. It starts and ends at `rest`; its highest is `top` and its lowest `hit`.
static func _stroke(u: float, top: float, hit: float, rest: float, c: float) -> float:
	var w := c - 0.23
	var s := c - 0.10
	if u < w:
		return lerpf(rest, top - 0.06, _io(u / w))
	if u < s:
		return top - 0.06 + 0.06 * sin(PI * (u - w) / (s - w))
	if u < c:
		var x := (u - s) / (c - s)
		return lerpf(top - 0.06, hit, x * x)
	var y := (u - c) / (1.0 - c)
	return lerpf(hit, rest, 1.0 - (1.0 - y) * (1.0 - y)) + 0.12 * sin(PI * y) * (1.0 - y)


## A swinging tool in the main hand through one stroke: the angle, the body that follows it and the hand at the end of the arm.
static func _swing(o: Pose, u: float, prm: Dictionary, tool: String) -> void:
	var a := _stroke(u, prm.top, prm.hit, prm.rest, prm.contact)
	var k := clampf((a - float(prm.hit)) / (float(prm.top) - float(prm.hit)), 0.0, 1.0)
	o.lean = lerpf(prm.lean_hit, prm.lean_up, k)
	o.dip = float(prm.dip) * _bump(u, prm.contact, 0.12)
	o.stance = prm.stance
	o.tool = tool
	o.tool_a = a
	var sh := _shoulder(o.lean, o.dip, 0.0)
	var b := a * 0.85
	o.main = sh + Vector2(cos(b), -sin(b)) * float(prm.reach)
	o.tool_at = o.main
	o.tool_l = o.main_l
	# where the head of the tool lands: the same at every stroke, so worked out for the blow itself
	var shc := _shoulder(prm.lean_hit, prm.dip, 0.0)
	var bc: float = float(prm.hit) * 0.85
	var hand_c := shc + Vector2(cos(bc), -sin(bc)) * float(prm.reach)
	var tip := hand_c + Vector2(cos(float(prm.hit)), -sin(float(prm.hit))) * float(prm.len)
	o.fx_at = Vector2(tip.x, minf(tip.y, 0.3))
	o.tool_yaw = float(prm.get("yaw", -0.2))


## Fills `o` with the pose of `word` at work time `t` for a person whose place in the loop is `phase` (0 to 1). With
## `reduced` it is the still pose that stands for the job (no swing, no puff, no turning of the head).
static func solve(o: Pose, word: String, t: float, phase: float, reduced_motion: bool = false) -> Pose:
	o.reset()
	if not CYCLE.has(word):
		return o
	o.word = word
	var loop := loop_period(word)
	var x := t / loop + phase
	var u := float(STILL_U[word]) if reduced_motion else fposmod(x, 1.0)
	o.u = u
	match word:
		"hammer":
			_swing(o, u, HAMMER, "hammer")
			o.off = Vector2(0.42, -0.02 - o.dip * 0.5)
			o.off_l = -0.25
			o.fx = "chips"
			_blow(o, x, u, HAMMER.contact, loop)
		"bench":
			_swing(o, u, MALLET, "mallet")
			o.off = Vector2(0.46, -0.04 - o.dip * 0.5)
			o.off_l = -0.25
			o.fx = "sparks"
			_blow(o, x, u, MALLET.contact, loop)
		"mend":
			_swing(o, u, MEND, "hammer")
			o.off_tool = "plank"
			o.off = Vector2(0.56, -0.24)
			o.off_at = o.off
			o.off_a = 1.45
			o.prop = "planks"
			o.fx = "chips"
			_blow(o, x, u, MEND.contact, loop)
		"haul":
			_haul(o, x, u, loop)
		"garden":
			_garden(o, x, u, loop)
		"nurse":
			_nurse(o, u)
		"radio":
			_radio(o, u)
		"watch":
			_watch(o, u)
		"sort":
			_sort(o, x, u, loop)
		"rest":
			_rest(o, u)
		"clean":
			_clean(o, x, u, loop)
	if reduced_motion:
		o.strike = 0
		o.item_kind = 0
		o.hit = 99.0
		o.sweep = 0
		o.squash = 1.0
		o.wave = -1.0
		o.glint = 0.0
	return o


## The age of the blow and how many have been struck.
static func _blow(o: Pose, x: float, u: float, c: float, loop: float) -> void:
	o.hit = fposmod(u - c, 1.0) * loop
	o.strike = int(floor(x - c))


static func _haul(o: Pose, x: float, u: float, loop: float) -> void:
	# carry it at the chest, bend and set it down, a breath, bend and lift it, carry on
	var down := _io(_seg(u, 0.30, 0.50))
	var up := _io(_seg(u, 0.62, 0.82))
	var k := down - up
	o.tool = "crate"
	o.stance = 1.3
	o.lean = lerpf(0.06, 0.5, k)
	o.dip = 0.07 * k
	var c := Vector2(lerpf(0.42, 0.6, k), lerpf(-0.04, 0.22, k) + sin(u * TAU * 2.0) * 0.008 * (1.0 - k))
	o.tool_at = c
	o.tool_l = 0.0
	o.tool_a = 0.0
	o.main = c + Vector2(-0.1, 0.1)
	o.main_l = 0.22
	o.off = c + Vector2(-0.1, 0.1)
	o.off_l = -0.22
	o.hit = fposmod(u - 0.5, 1.0) * loop
	o.fx = "dust"
	o.fx_at = Vector2(0.6, 0.3)
	o.strike = int(floor(x - 0.5))


## Sweeping (prison round 5): the long handled tool (the hoe's art stands for a broom) is drawn across the ground and back twice a loop, the body bent over it, a puff of dust at the end of each stroke.
static func _clean(o: Pose, x: float, u: float, loop: float) -> void:
	var sw := sin(u * TAU * 2.0)
	o.tool = "broom"
	o.grip2 = 0.45
	o.stance = 1.5
	o.lean = 0.26
	o.dip = 0.02
	o.tool_a = -0.95 + 0.22 * sw
	var sh := _shoulder(o.lean, o.dip, 0.0)
	o.main = sh + Vector2(0.3 + 0.14 * sw, 0.12)
	o.tool_at = o.main
	o.tool_l = o.main_l
	o.tool_yaw = -0.1 + 0.4 * sw    # the bristles sweep sideways
	o.off = Vector2(0.18 + 0.1 * sw, -0.12)
	o.fx = "dust"
	o.fx_at = Vector2(0.78 + 0.1 * sw, 0.3)
	o.hit = fposmod(u * 2.0 - 0.25, 1.0) * loop * 0.5
	o.strike = int(floor(x * 2.0 - 0.25))


static func _garden(o: Pose, x: float, u: float, loop: float) -> void:
	var beat := mini(4, int(u * 5.0))
	var ub := u * 5.0 - float(beat)
	o.off = Vector2(0.04, 0.0)
	if beat < 4:
		_swing(o, ub, HOE, "hoe")
		o.grip2 = 0.45
		o.prop = "can"
		o.fx = "dust"
		# a blow of the hoe in each of the four beats; the age of the last
		var best := 99.0
		for b in 4:
			var cu := (float(b) + float(HOE.contact)) / 5.0
			best = minf(best, fposmod(u - cu, 1.0) * loop)
		o.hit = best
		o.strike = 4 * int(floor(x)) + (1 if u >= float(HOE.contact) / 5.0 else 0) + (1 if u >= (1.0 + float(HOE.contact)) / 5.0 else 0) + (1 if u >= (2.0 + float(HOE.contact)) / 5.0 else 0) + (1 if u >= (3.0 + float(HOE.contact)) / 5.0 else 0)
		return
	# the fifth beat: the hoe is planted and the can is lifted and tipped over the bed
	var plant := _io(_seg(ub, 0.0, 0.15)) - _io(_seg(ub, 0.85, 1.0))
	o.tool = "hoe"
	o.tool_yaw = float(HOE.yaw)
	o.tool_a = lerpf(float(HOE.rest), -0.5, plant)
	o.lean = lerpf(float(HOE.lean_up), 0.3, plant)
	o.dip = 0.03 * plant
	o.stance = HOE.stance
	var sh := _shoulder(o.lean, o.dip, 0.0)
	var b := o.tool_a * 0.85
	o.main = sh + Vector2(cos(b), -sin(b)) * float(HOE.reach)
	o.tool_at = o.main
	o.tool_l = o.main_l
	# the can: from the ground at the side, up, tipped, back down
	var ground := Vector2(0.3, 0.14)
	var lift := _io(_seg(ub, 0.2, 0.4)) - _io(_seg(ub, 0.68, 0.84))
	var tip := _io(_seg(ub, 0.4, 0.5)) - _io(_seg(ub, 0.62, 0.7))
	var reach := _io(_seg(ub, 0.0, 0.2)) - _io(_seg(ub, 0.84, 1.0))
	var rest := Vector2(0.04, 0.0)
	var hand := ground.lerp(Vector2(0.46, -0.16), lift)
	o.off = rest.lerp(hand, reach)
	o.off_l = lerpf(-0.2, -0.4, reach)
	o.off_a = -0.95 * tip
	o.off_at = o.off
	if ub >= 0.2 and ub <= 0.84:
		o.off_tool = "can"
		o.prop = ""
	else:
		o.prop = "can"
	if tip > 0.6 and ub < 0.66:
		o.water = clampf((ub - 0.44) / 0.2, 0.0, 1.0)
	o.hit = 99.0
	var last := (3.0 + float(HOE.contact)) / 5.0
	o.hit = fposmod(u - last, 1.0) * loop
	o.fx = "dust"
	o.strike = 4 * int(floor(x)) + 4


static func _nurse(o: Pose, u: float) -> void:
	# lean in, take a bottle down from the shelf and read it against the clipboard
	var ub := fposmod(u * 2.0, 1.0)
	var k := _io(_seg(ub, 0.0, 0.32)) - _io(_seg(ub, 0.5, 0.86))
	o.stance = 1.2
	o.lean = 0.22 + 0.1 * k
	o.dip = 0.03
	o.tilt = sin(ub * TAU) * 0.02
	o.tool = "bottle"
	var chest := Vector2(0.26, -0.12)
	var shelf := Vector2(0.52, -0.56)
	o.main = chest.lerp(shelf, k)
	o.main_l = 0.14
	o.tool_at = o.main + Vector2(0.0, -0.05)
	o.tool_l = o.main_l
	o.tool_a = 0.1 - 0.35 * k
	o.off_tool = "clipboard"
	o.off = Vector2(0.3, -0.16 + sin(ub * TAU) * 0.008)
	o.off_l = -0.14
	o.off_at = o.off + Vector2(0.0, -0.04)
	o.off_a = 0.18
	o.glint = _bump(ub, 0.42, 0.16)
	o.glint_at = shelf + Vector2(0.06, -0.3)


static func _radio(o: Pose, u: float) -> void:
	# two beats at the dial, two speaking into the handset; the radio's waves go out all the time
	var v := u if u >= 0.04 else u + 1.0
	var mic := _io(_seg(v, 0.40, 0.52)) - _io(_seg(v, 0.92, 1.04))
	o.stance = 0.9
	o.lean = 0.18
	o.dip = 0.04
	o.head = "headset"
	o.tilt = sin(u * TAU * 4.0) * 0.025 * (0.4 + mic)
	var desk := Vector2(0.5, 0.0)
	var turn := u * TAU * 2.0
	o.off = desk + Vector2(cos(turn) * 0.03, sin(turn) * 0.02 + 0.02)
	o.off_l = -0.12
	o.main_l = 0.12
	var rest_hand := desk + Vector2(-0.06, 0.04)
	o.main = rest_hand.lerp(Vector2(0.12, 0.17), mic)
	o.main_face = mic > 0.5
	if mic > 0.5:
		o.main = Vector2(0.1, 0.17)
	o.tool = "mic"
	o.tool_a = lerpf(-0.1, 1.2, mic)
	o.tool_at = o.main
	o.tool_l = o.main_l
	o.tool_face = o.main_face
	o.wave = fposmod(u * 4.0, 1.0)
	o.wave_k = 0.3 + 0.7 * mic


static func _watch(o: Pose, u: float) -> void:
	# the binoculars up to the eyes; the body turns, in quarter turns, slowly: ahead, left, ahead, right
	o.stance = 1.3
	o.lean = 0.04
	o.dip = sin(u * TAU * 5.0) * 0.006
	o.tool = "binoculars"
	o.tool_a = 0.0
	o.main_face = true
	o.off_face = true
	o.tool_face = true
	o.main = Vector2(0.17 - 0.06, 0.1)
	o.off = Vector2(0.17 - 0.06, 0.12)
	o.main_l = 0.09
	o.off_l = -0.09
	o.tool_at = Vector2(0.13, 0.0)
	o.tool_l = 0.0
	o.tilt = sin(u * TAU * 5.0) * 0.012
	# the sweep: ahead 0 to 0.27, left 0.31 to 0.52, ahead 0.56 to 0.67, right 0.71 to 0.94, ahead; each turn takes 0.04 of the loop
	var sw := 0
	var sq := 1.0
	var turns := [0.27, 0.31, 0.52, 0.56, 0.67, 0.71, 0.94, 0.98]
	var dirs := [0, -1, -1, 0, 0, 1, 1, 0]
	for i in 4:
		var a: float = turns[i * 2]
		var b: float = turns[i * 2 + 1]
		if u >= a and u < b:
			var k := (u - a) / (b - a)
			# a turn: the body gets a little narrower (never a line: TURN_SQUASH), shows the other side, and widens again
			var from: int = 0 if i == 0 else int(dirs[i * 2 - 1])
			var to: int = int(dirs[i * 2 + 1])
			sw = from if k < 0.5 else to
			sq = lerpf(1.0, TURN_SQUASH, 1.0 - absf(k * 2.0 - 1.0))
			break
		elif u >= b and (i == 3 or u < float(turns[i * 2 + 2])):
			sw = int(dirs[i * 2 + 1])
	o.sweep = sw
	o.squash = sq


static func _sort(o: Pose, x: float, u: float, loop: float) -> void:
	# a hand at the first crate, an item picked up, carried across and dropped in the second, the hand back again
	o.stance = 1.5
	o.lean = 0.22
	o.dip = 0.04
	o.tool = "crate"
	o.tool_at = Vector2(0.4, 0.2)
	var k := _io(_seg(u, 0.25, 0.7)) - _io(_seg(u, 0.8, 1.0))
	o.sort_k = k
	o.sort_lift = sin(clampf((u - 0.25) / 0.45, 0.0, 1.0) * PI) * 0.18 + (sin(clampf((u - 0.8) / 0.2, 0.0, 1.0) * PI) * 0.06)
	o.tilt = (k - 0.5) * 0.06
	var shown := _io(_seg(u, 0.12, 0.2)) * (1.0 - _seg(u, 0.72, 0.74))
	o.item = 0.11 * shown
	o.item_kind = int(floor(x)) % 3
	o.hit = fposmod(u - 0.72, 1.0) * loop
	o.fx = "dust"
	o.strike = int(floor(x - 0.72))


static func _rest(o: Pose, u: float) -> void:
	# standing easy with a mug; now and then it goes up for a drink
	var sip := _io(_seg(u, 0.55, 0.64)) - _io(_seg(u, 0.78, 0.88))
	o.stance = 1.0
	o.lean = lerpf(0.0, -0.07, sip)
	o.tilt = sin(u * TAU * 4.0) * 0.012 + 0.015
	o.tool = "mug"
	o.main = Vector2(0.3, -0.1).lerp(Vector2(0.12, 0.17), sip)
	o.main_l = 0.14
	o.main_face = sip > 0.5
	if sip > 0.5:
		o.main = Vector2(0.1, 0.17)
	o.tool_at = o.main + Vector2(0.0, -0.04)
	o.tool_l = o.main_l
	o.tool_face = o.main_face
	o.tool_a = -0.1 * sip
	o.off = Vector2(0.02, -0.01)
	o.steam = true


# ------------------------------------------------------------------ the sight --

## Where a point of the pose is on the screen in the view `view` (the figure's own frame, before the body moves).
static func proj(view: String, f: float, y: float, l: float) -> Vector2:
	match view:
		"E":
			return Vector2(f, y + l * 0.07)
		"S":
			return Vector2(-l, y + f * DEPTH)
	return Vector2(l, y - f * DEPTH)


## A hand (or a tool) at the face: from the side out in front of it, from the front over it, from behind behind the head.
static func _face(view: String, f: float, y: float, l: float) -> Vector2:
	match view:
		"E":
			return Vector2(FACE_X + f - 0.17, FACE_Y + y)
		"S":
			return Vector2(-l * 1.5, FACE_Y + y + f * 0.15)
	return Vector2(l * 3.0, FACE_Y + y - f * 0.2)


static func _hand_at(view: String, p: Vector2, l: float, face: bool) -> Vector2:
	return _face(view, p.x, p.y, l) if face else proj(view, p.x, p.y, l)


## The legs' build for a stance (a walker's, with the feet apart or together).
static func _stance_style(stance: float) -> Dictionary:
	var key := int(round(stance * 10.0))
	if not _styles.has(key):
		var st: Dictionary = Art.PERSON.duplicate()
		st["stance"] = stance
		_styles[key] = st
	return _styles[key]


## The quarter turn of a facing: -1 to the left, 1 to the right.
static func turned(facing: String, sweep: int) -> String:
	if sweep == 0:
		return facing
	var order := ["N", "E", "S", "W"]
	var i := order.find(facing)
	return order[(i + sweep + 4) % 4]


## The body of the figure for this pose seen from `view`: where it leans, drops and narrows. `w` is how far into the pose.
static func body_xf(view: String, o: Pose, w: float) -> Transform2D:
	var lean := o.lean * w
	var dip := o.dip * w
	var shift := o.shift * w
	var sq := maxf(MIN_SQUASH, lerpf(1.0, o.squash, w))
	var xf := Transform2D.IDENTITY
	if view == "E":
		xf = xf.translated_local(Vector2(shift, dip)).translated_local(Vector2(0.0, HIPS_Y)).rotated_local(lean + o.tilt * w).translated_local(Vector2(0.0, -HIPS_Y)).scaled_local(Vector2(sq, 1.0))
		return xf
	var sh := _shoulder(lean, dip, shift)
	var dy: float = (sh.y - SH_Y) + (sh.x * DEPTH if view == "S" else -sh.x * DEPTH)
	var sy := cos(lean)
	return xf.translated_local(Vector2(0.0, dy)).translated_local(Vector2(0.0, HIPS_Y)).rotated_local(o.tilt * w).scaled_local(Vector2(sq, sy)).translated_local(Vector2(0.0, -HIPS_Y))


# ------------------------------------------------------------------ the drawing --

## How big a tool is drawn against its picture (the small ones are made a little larger to be seen from the usual height).
const TOOL_SCALE := {"mug": 1.35, "mic": 1.15, "bottle": 1.1}
## The longest an arm is drawn, shoulder to fist, in tiles (a hand sent farther than this stops short).
const MAX_ARM := 0.66
## From behind, a hand higher on the screen than this is above the shoulders, beside the head: seen over the body.
const HIGH_HAND := -0.42


## The ordinary place for a hand to hang in a view, to ease from.
static func _rest_hand(view: String, main: bool) -> Vector2:
	var side := 1.0 if main else -1.0
	match view:
		"E":
			return Vector2(0.06 if main else 0.0, -0.02)
		"S":
			return Vector2(-side * 0.2, -0.05)
	return Vector2(side * 0.28, -0.04)


## What a tool's length looks like on the screen: a vector as long as it shows (shorter as it points to or from the player)
## and pointing as it points. `a` is how far it points up from forward; `yaw` how far to the figure's right (negative: across).
static func _tool_dir(view: String, a: float, yaw: float) -> Vector2:
	var cy := cos(yaw)
	var sy := sin(yaw)
	match view:
		"E":
			return Vector2(cos(a) * cy, -sin(a))
		"S":
			return Vector2(-sy * cos(a), -sin(a) + DEPTH * cos(a) * cy)
	return Vector2(sy * cos(a), -sin(a) - DEPTH * cos(a) * cy)


## A hand kept within reach of its shoulder.
static func _reach(sh: Vector2, hand: Vector2) -> Vector2:
	return sh + (hand - sh).limit_length(MAX_ARM)


static func _arm(pen, view: String, col: Color, sh: Vector2, hand: Vector2, tight: bool = false) -> void:
	var d := hand - sh
	var ln := maxf(d.length(), 0.001)
	var n := Vector2(-d.y, d.x) / ln
	if view == "E":
		var pref := Vector2(-0.37, 0.93)
		if n.dot(pref) < 0.0:
			n = -n
	else:
		var outward := signf(sh.x) if absf(sh.x) > 0.01 else 1.0
		if n.x * outward < 0.0:
			n = -n
	var bend := (clampf(0.62 - ln, 0.0, 0.5) * 0.55 + 0.03) * (0.15 if tight else 1.0)
	Art._arm(pen, col, sh, (sh + hand) * 0.5 + n * bend, hand, 0.85)


static func _fist(pen, skin: Color, at: Vector2) -> void:
	Art._fill(pen, at, Art.HAND, Art.HAND_LINE, skin, Art.INK, 1.0, 1.0)


## A tool at `at` pointing `a` (see Pose.tool_a), seen from `view`: turned to where it points on the screen and shortened as it
## points toward or away from the player. A tool with no long side is turned by `a` as it is.
static func _tool(pen, base: Transform2D, view: String, name: String, at: Vector2, a: float, yaw: float, mod: Color, scale: float = 1.0) -> void:
	var def := tool_def(name)
	if def.is_empty():
		return
	var ang := a
	var sx := 1.0
	if bool(def.axis):
		var d := _tool_dir(view, a, yaw)
		ang = atan2(d.y, d.x)
		sx = clampf(d.length(), 0.3, 1.0)
	var k: float = scale * float(TOOL_SCALE.get(name, 1.0))
	pen.draw_set_transform_matrix(base * Transform2D(ang, Vector2(sx * k, k), 0.0, at))
	pen.draw_texture_rect(tool_tex(name), tool_rect(name), false, mod)
	pen.draw_set_transform_matrix(base)


## The tool in the hand for a view (a pair of binoculars is seen from the front head on).
static func _tool_for(view: String, name: String) -> String:
	if name == "binoculars" and view == "S":
		return "binoculars_front"
	return name


## The pawn's own drawing for a person at work. `n` is the node (its transform, its pictures and colours), `w` how far into
## the pose it is (0 to 1, eased), `facing_in` where the rules have them looking and `aim` the way the weapon pointed.
static func draw_person(n, o: Pose, w: float, facing_in: String, aim: float) -> void:
	var p = n.entity
	var facing := turned(facing_in, o.sweep if w > 0.5 else 0)
	var mirror := facing == "W"
	var view := "E" if mirror else facing
	var pen = n._pen
	var pal: Dictionary = n.pal
	var col := Color(1.0, 1.0, 1.0, minf(1.0, w * 1.6))
	n._reset()
	n._apply()
	Art.shadow(pen)
	if mirror:
		n._sc(-1, 1)
	n._apply()
	var base: Transform2D = n._m
	if o.prop == "planks":
		_planks(pen, base, view, col)
	# (a person who has just got up from their work and is walking off keeps walking while the pose fades)
	# (ANIM: the legs' drawn stride, which starts and ends on a neutral pose, and the body narrowed across the seam of a turn: pawn_node.gd)
	Art.legs(pen, pal, view, n._rph, n._moving_draw, false, 1.0, _stance_style(lerpf(1.0, o.stance, w)))
	var bx := body_xf(view, o, w)
	if n._wid != 1.0:
		bx = bx.scaled_local(Vector2(n._wid, 1.0))
	# the shoulders as the body has them now, and where the hands go
	var sh_main := bx * proj(view, 0.0, SH_Y, SH_L)
	var sh_off := bx * proj(view, 0.0, SH_Y, -SH_L)
	var t_main := _hand_at(view, o.main, o.main_l, o.main_face)
	if o.sort_k >= 0.0:
		t_main = _sort_hand(view, o)
	var t_off := _hand_at(view, o.off, o.off_l, o.off_face)
	if o.grip2 > 0.0 and o.tool != "":
		t_off = t_main + _tool_dir(view, o.tool_a, o.tool_yaw) * o.grip2
	var h_main := _reach(sh_main, _rest_hand(view, true).lerp(t_main, w))
	var h_off := _reach(sh_off, _rest_hand(view, false).lerp(t_off, w))
	# the layers: from the side the far arm goes behind the body; from behind what is in front of the person is behind them, but
	# a hand up beside the head is seen
	var back_main := false
	var back_off := view == "E"
	if view == "N":
		back_main = not (o.main_face or h_main.y < HIGH_HAND)
		back_off = not (o.off_face or h_off.y < HIGH_HAND)
		_crates(pen, base, view, o, col)
	if back_off:
		_draw_arm(pen, base, view, o, false, sh_off, h_off, pal, col, true)
	if back_main:
		_draw_arm(pen, base, view, o, true, sh_main, h_main, pal, col, true)
	if view == "N":
		n._weapon_faded(view, aim, 1.0 - w, mirror)
	n._m = base * bx
	n._apply()
	pen.draw_texture_rect(n.tex[view], n.pawn_rect, false)
	n._m = base
	n._apply()
	if view != "N":
		n._weapon_faded(view, aim, 1.0 - w, mirror)
	if o.head != "":
		_head(pen, base, bx, view, col)
	if view != "N":
		_crates(pen, base, view, o, col)
	if not back_off:
		_draw_arm(pen, base, view, o, false, sh_off, h_off, pal, col)
	if not back_main:
		_draw_arm(pen, base, view, o, true, sh_main, h_main, pal, col)
	if o.item > 0.0 and o.sort_k >= 0.0:
		_item(pen, base, h_main, o)
	_effects(pen, base, view, o, w)
	n._m = base
	n._apply()


## An arm with what is in its hand: the sleeve, the tool, the fist over the tool's grip.
static func _draw_arm(pen, base: Transform2D, view: String, o: Pose, is_main: bool, sh: Vector2, hand: Vector2, pal: Dictionary, col: Color, behind: bool = false) -> void:
	_arm(pen, view, pal.sleeve, sh, hand, behind and view == "N")
	if is_main:
		_held_main(pen, base, view, o, hand, col)
	else:
		_held_off(pen, base, view, o, hand, col)
	_fist(pen, pal.skin, hand)


## The tool in the main hand.
static func _held_main(pen, base: Transform2D, view: String, o: Pose, hand: Vector2, col: Color) -> void:
	if o.tool == "" or o.tool == "crate":
		return    # (a crate, carried or in the sorting, is drawn with the props)
	var at := hand
	if o.tool_face:
		at = _face(view, o.tool_at.x, o.tool_at.y, o.tool_l)
		if o.tool == "binoculars":
			at = Vector2(0.0, FACE_Y) if view != "E" else Vector2(FACE_X, FACE_Y)
	if o.tool == "binoculars" and view == "N":
		return    # (behind the head)
	_tool(pen, base, view, _tool_for(view, o.tool), at, o.tool_a, o.tool_yaw, col)


static func _held_off(pen, base: Transform2D, view: String, o: Pose, hand: Vector2, col: Color) -> void:
	if o.off_tool == "":
		return
	var at := hand
	if o.off_tool == "clipboard":
		at = proj(view, o.off_at.x, o.off_at.y, o.off_l)
	_tool(pen, base, view, o.off_tool, at, o.off_a, 0.0, col)


## Where the hand of the sorting is: over the first crate, over the second, or between (higher).
static func _sort_hand(view: String, o: Pose) -> Vector2:
	var a := _crate_spot(view, 0)
	var b := _crate_spot(view, 1)
	return a.lerp(b, o.sort_k) + Vector2(0.0, -0.05 - o.sort_lift)


## The two crates of the sorting bench, on the screen: the first on the figure's right.
static func _crate_spot(view: String, which: int) -> Vector2:
	var l := 0.34 if which == 0 else -0.34
	match view:
		"E":
			return Vector2(0.34 if which == 0 else 0.7, 0.24)
		"S":
			return Vector2(-l, 0.4)
	return Vector2(l * 1.2, 0.16)


## What lies on the ground or is carried in front: the crates of the sorting, the crate of the hauling, the can of the garden.
static func _crates(pen, base: Transform2D, view: String, o: Pose, col: Color) -> void:
	if o.sort_k >= 0.0:
		for i in 2:
			_tool(pen, base, view, "crate", _crate_spot(view, i), 0.0, 0.0, col, 0.8)
	elif o.tool == "crate":
		_tool(pen, base, view, "crate", proj(view, o.tool_at.x, o.tool_at.y, 0.0), 0.0, 0.0, col, 0.85)
	elif o.prop == "can":
		_tool(pen, base, view, "can", proj(view, 0.3, 0.14, -0.45), 0.0, 0.0, col, 1.0)


static func _item(pen, base: Transform2D, at: Vector2, o: Pose) -> void:
	var r := o.item
	var cols := [Color("#8a6a4a"), Color("#6f7780"), Color("#9a5a3a")]
	pen.draw_set_transform_matrix(base)
	var pts := PackedVector2Array([at + Vector2(-r, -r * 0.4), at + Vector2(-r * 0.2, -r), at + Vector2(r, -r * 0.5), at + Vector2(r * 0.8, r * 0.6), at + Vector2(-r * 0.3, r)])
	pen.draw_colored_polygon(pts, cols[o.item_kind % 3])
	pts.append(pts[0])
	pen.draw_polyline(pts, Art.INK, 0.03, true)


## Leaning planks beside the figure, up against the wall they mend (from the front and the back, at the side; from the side,
## behind).
static func _planks(pen, base: Transform2D, view: String, col: Color) -> void:
	var at := Vector2(-0.52, 0.08)
	var a := PI / 2.0 + 0.3
	var step := -0.11
	if view == "S":
		at = Vector2(0.6, 0.08)
		a = PI / 2.0 - 0.3
		step = 0.11
	elif view == "N":
		at = Vector2(-0.56, 0.08)
		a = PI / 2.0 + 0.3
		step = -0.11
	for i in 2:
		_tool(pen, base, "E", "plank", at + Vector2(step * float(i), -0.02 * float(i)), a - 0.07 * float(i) * signf(step) * -1.0, 0.0, col, 0.9)


## The headset, worn over the cap.
static func _head(pen, base: Transform2D, bx: Transform2D, view: String, col: Color) -> void:
	var sx := 0.22 if view == "E" else 0.9
	var at := bx * Vector2(-0.04 if view == "E" else 0.0, -0.52)
	pen.draw_set_transform_matrix(base * Transform2D(0.0, Vector2(sx, 0.9), 0.0, at))
	pen.draw_texture_rect(tool_tex("headset"), tool_rect("headset"), false, col)
	pen.draw_set_transform_matrix(base)


# ---------------------------------------------------------------- the small things --

static func _effects(pen, base: Transform2D, view: String, o: Pose, w: float) -> void:
	pen.draw_set_transform_matrix(base)
	if o.hit < FX_LIFE and o.fx != "":
		_blow_fx(pen, proj(view, o.fx_at.x, o.fx_at.y, 0.0), o)
	if o.glint > 0.01:
		_glint(pen, proj(view, o.glint_at.x, o.glint_at.y, 0.1), o.glint)
	if o.steam:
		var at := _face(view, 0.16, 0.0, 0.12) if o.main_face else proj(view, o.tool_at.x, o.tool_at.y - 0.1, o.tool_l)
		_steam(pen, at, o.u)
	if o.wave >= 0.0:
		_waves(pen, view, o)
	if o.water >= 0.0:
		_water(pen, view, o)


static func _blow_fx(pen, at: Vector2, o: Pose) -> void:
	var age := o.hit
	var k := age / FX_LIFE
	var fade := 1.0 - k
	var seed_a := float(o.strike % 7) * 0.53
	match o.fx:
		"chips":
			for i in 5:
				var a := -0.5 - float(i) * 0.5 + seed_a * 0.2
				var v := 0.9 + float((i * 5) % 3) * 0.3
				var p := at + Vector2(cos(a), sin(a)) * v * age + Vector2(0.0, 2.6 * age * age)
				var d := Vector2(cos(a + age * 9.0), sin(a + age * 9.0)) * 0.025
				pen.draw_line(p - d, p + d, Color(0.78, 0.6, 0.38, fade), 0.04, true)
			_puff(pen, at, k, 0.25)
		"sparks":
			for i in 7:
				var a := -0.2 - float(i) * 0.42 + seed_a * 0.15
				var v := 1.2 + float((i * 3) % 4) * 0.35
				var p := at + Vector2(cos(a), sin(a)) * v * age + Vector2(0.0, 1.4 * age * age)
				var tail := Vector2(cos(a), sin(a)) * 0.07 * fade
				pen.draw_line(p - tail, p, Color(1.0, 0.85 - 0.5 * k, 0.3, fade), 0.03, true)
		"dust":
			_puff(pen, at, k, 0.45)


static func _puff(pen, at: Vector2, k: float, strength: float) -> void:
	for i in 3:
		var dx := (float(i) - 1.0) * 0.07 * (0.6 + k)
		pen.draw_circle(at + Vector2(dx, -0.02 - 0.1 * k), 0.035 + 0.08 * k, Color(0.8, 0.76, 0.68, strength * (1.0 - k)))


static func _glint(pen, at: Vector2, g: float) -> void:
	var s := 0.05 + 0.05 * g
	var col := Color(0.55, 0.95, 0.65, g)
	pen.draw_line(at + Vector2(-s, 0.0), at + Vector2(s, 0.0), Color(S.INK.r, S.INK.g, S.INK.b, g * 0.7), 0.075, true)
	pen.draw_line(at + Vector2(0.0, -s), at + Vector2(0.0, s), Color(S.INK.r, S.INK.g, S.INK.b, g * 0.7), 0.075, true)
	pen.draw_line(at + Vector2(-s, 0.0), at + Vector2(s, 0.0), col, 0.045, true)
	pen.draw_line(at + Vector2(0.0, -s), at + Vector2(0.0, s), col, 0.045, true)


static func _steam(pen, at: Vector2, u: float) -> void:
	for i in 2:
		var k := fposmod(u * 8.0 + float(i) * 0.5, 1.0)
		var pts := PackedVector2Array()
		for j in 5:
			var t := float(j) / 4.0
			pts.append(at + Vector2(sin((k + t) * 6.0 + float(i) * 2.0) * 0.025 + float(i) * 0.04 - 0.02, -0.04 - 0.16 * (k * 0.5 + t * 0.5)))
		pen.draw_polyline(pts, Color(0.92, 0.92, 0.9, 0.5 * sin(PI * k)), 0.03, true)


static func _waves(pen, view: String, o: Pose) -> void:
	var c := Vector2(0.24, -0.92) if view != "E" else Vector2(0.18, -0.95)
	if view == "N":
		c = Vector2(0.3, -0.95)
	for i in 3:
		var k := fposmod(o.wave + float(i) / 3.0, 1.0)
		var r := 0.1 + 0.2 * k
		var pts := PackedVector2Array()
		for j in 7:
			var a := -1.25 + 1.2 * float(j) / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		pen.draw_polyline(pts, Color(0.85, 0.95, 1.0, o.wave_k * 0.7 * sin(PI * k)), 0.035, true)


static func _water(pen, view: String, o: Pose) -> void:
	var from := proj(view, o.off.x + cos(o.off_a) * 0.34, o.off.y - sin(o.off_a) * 0.34 - 0.04, o.off_l)
	for i in 4:
		var k := fposmod(o.water * 2.0 + float(i) * 0.25, 1.0)
		var p := from + Vector2(0.05 * float(i % 2) + 0.12 * k, 0.4 * k * k)
		pen.draw_circle(p, 0.025, Color(0.6, 0.8, 1.0, 0.8 * (1.0 - k)))
