## Two people talking (round 24, "base life"): when two friends of the crew stand close together with nothing to do (both at rest: not walking,
## no job at hand, nobody you play) a small speech bubble of three dots shows over the head of one of them, then over the other's, turn and turn
## about every couple of seconds, the dots lighting one after the other, so the pair reads as having a chat. Bonds of the old yard (`sim.bonds`)
## and the friends, couples and family of the avatar game's relations (`sim.relations.kind`) both count; rivals do not. The pairs are looked
## for twice a second (the people are few). The bubble is ONE baked mesh (a paper box with an ink rim, a tail, three dots), and there are
## two of them to place (so at most two pairs chat at once, which is more than the crew has); each costs ONE draw call, only while its pair is
## on the screen, and a shader lights the dots one after the other from the clock. Nothing is allocated in a frame; the rules never see it and it
## moves nobody (the pawns stand where the rules put them).
##
## The mesh's UV.x says which dot a vertex belongs to (1, 2, 3), 0 for the rest.
extends Node2D

const Kit := preload("res://scripts/render/life_kit.gd")
const TILE := 64.0
## Two people are in a chat when they stand within this many tiles of each other.
const CLOSE := 2.6
const TURN_S := 2.0
const PAPER := Color("#f3ecd8")
## The bubble sits this far above a person's feet (tiles).
const ABOVE := 1.3
const POOL := 2
## The kinds of the avatar game's relations that chat (rivals do not).
const FRIENDLY := ["friend", "couple", "family", "mentor"]

const SHADER := "
shader_type canvas_item;
uniform float t = 0.0;
void fragment() {
	if (UV.x > 0.5) {
		float d = UV.x - 1.0;
		float beat = mod(t * 2.4, 3.0);
		float lit = abs(beat - d - 0.5) < 0.7 ? 1.0 : 0.0;
		COLOR.a *= mix(0.45, 1.0, lit);
	}
}
"

var sim
## [[a, b], ...] the pairs now, and the animation clock.
var pairs: Array = []
var t := 0.0
var view := Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
var _bubbles: Array = []
var _mat: ShaderMaterial


func setup(rules) -> void:
	sim = rules
	z_index = 7
	name = "Chat"
	_mat = Kit.material(SHADER)
	var mesh := _bake()
	for i in POOL:
		var m := MeshInstance2D.new()
		m.name = "Bubble%d" % i
		m.mesh = mesh
		m.material = _mat
		m.visible = false
		add_child(m)
		_bubbles.append(m)


func _bake() -> ArrayMesh:
	var b := Kit.Builder.new()
	var ink := Kit.INK
	var w := 34.0
	var h := 20.0
	b.add_grid(Vector2(-w * 0.5 - 1.6, -h - 1.6), Vector2(w + 3.2, h + 3.2), 1, 1, ink, ink)
	b.add_grid(Vector2(-w * 0.5, -h), Vector2(w, h), 1, 1, PAPER, PAPER)
	b.add_fan(Vector2(0.0, 0.0), ink, PackedVector2Array([Vector2(-4.0, -1.0), Vector2(4.0, -1.0), Vector2(0.0, 5.0)]), PackedColorArray([ink, ink, ink]))
	b.add_fan(Vector2(0.0, -0.6), PAPER, PackedVector2Array([Vector2(-2.6, -1.6), Vector2(2.6, -1.6), Vector2(0.0, 3.0)]), PackedColorArray([PAPER, PAPER, PAPER]))
	for d in 3:
		b.add_ellipse(Vector2(-9.0 + 9.0 * float(d), -h * 0.5), 2.3, 2.3, Color(0.1, 0.08, 0.06, 0.95), Vector2(float(d + 1), 0), 8)
	return b.bake()


## Looks for the pairs (twice a second, from the base's life).
func look() -> void:
	pairs.clear()
	if sim == null:
		return
	var people: Array = sim.people
	for i in people.size():
		var a = people[i]
		if not _idle(a):
			continue
		for j in range(i + 1, people.size()):
			var b = people[j]
			if _idle(b) and Vector2(a.x - b.x, a.y - b.y).length() <= CLOSE and _friends(a, b):
				pairs.append([a, b])


func _idle(p) -> bool:
	return not (p.dead or p.downed or p.away != null or p.moving or p.player) and (String(p.work) == "" or String(p.work) == "rest") and p.target == null and not p.drafted


func _friends(a, b) -> bool:
	var bonds = sim.get("bonds")
	if bonds != null and bonds.bonded(a, b):
		return true
	var relations = sim.get("relations")
	return relations != null and relations.active() and FRIENDLY.has(String(relations.kind(a, b)))


## Who is speaking now in a pair (0 or 1): they take turns every TURN_S.
func speaker(pair_index: int) -> int:
	return (int(floorf(t / TURN_S)) + pair_index) & 1


## Called every frame: puts the bubbles over the speakers of the pairs that are on the screen.
func tick(_dt: float, clock: float, animate: bool) -> void:
	t = clock
	var shown := 0
	if animate:
		for i in mini(pairs.size(), POOL):
			var who = pairs[i][speaker(i)]
			if view.has_point(Vector2(float(who.x), float(who.y))):
				var m: MeshInstance2D = _bubbles[shown]
				m.position = Vector2(float(who.x), float(who.y) - ABOVE) * TILE
				m.visible = true
				shown += 1
	for k in range(shown, POOL):
		_bubbles[k].visible = false
	if shown > 0:
		_mat.set_shader_parameter("t", t)


## How many bubbles are shown now (for the tests).
func shown_count() -> int:
	var n := 0
	for m in _bubbles:
		if m.visible:
			n += 1
	return n
