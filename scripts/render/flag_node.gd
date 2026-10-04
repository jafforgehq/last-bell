## A flag on a pole (round 24, "base life"): the colony's colours, teal over cream, on a short pole at the corner of a lookout tower. One
## baked mesh (the pole, an ink shadow of the cloth, the cloth as a grid) drawn in ONE draw call; the wave is the vertex shader of
## scripts/render/life_kit.gd (FLAG_SHADER) moved by two numbers the base's life sets each frame (`t`, `wind`), so nothing is
## redrawn and nothing is allocated. The wind is stronger in rain (scripts/render/base_life.gd). Off the screen the node is hidden
## by `base_life.gd`, and under "reduce motion" the wind is zero and the time still: the flag hangs.
extends MeshInstance2D

const Kit := preload("res://scripts/render/life_kit.gd")
const TILE := 64.0
const POLE_H := 100.0
const CLOTH := Vector2(80.0, 46.0)
const INK := Color(0.10, 0.08, 0.06, 0.85)
const TEAL := Color("#2f7a74")
const CREAM := Color("#eadfc4")
const WOOD := Color("#4a3624")

## The foot of the pole (tiles).
var foot := Vector2.ZERO


func setup(at_tile: Vector2, flag_material: ShaderMaterial) -> void:
	foot = at_tile
	position = at_tile * TILE
	z_index = 7
	material = flag_material
	mesh = _bake()
	name = "Flag"


func _bake() -> ArrayMesh:
	var b := Kit.Builder.new()
	b.add_stroke(Vector2(0, 2), Vector2(0, -POLE_H), 4.0, WOOD)
	# the ink round the cloth, a little bigger, then the cloth: teal on top, cream below
	b.add_grid(Vector2(1.0, -POLE_H - 3.0), CLOTH + Vector2(5.0, 6.0), 8, 2, INK, INK, 0.0, 1.0)
	b.add_grid(Vector2(2.0, -POLE_H), CLOTH, 8, 2, TEAL, TEAL, 0.0, 1.0)
	b.add_grid(Vector2(2.0, -POLE_H + CLOTH.y * 0.5), Vector2(CLOTH.x, CLOTH.y * 0.5), 8, 1, CREAM, CREAM, 0.0, 1.0)
	b.add_stroke(Vector2(-3, -POLE_H - 1), Vector2(3, -POLE_H - 1), 4.0, Color("#c9a54a"))
	return b.bake()


## The ground the flag covers (tiles), for the culling.
func bounds() -> Rect2:
	return Rect2(foot + Vector2(-0.2, -(POLE_H + 12.0) / TILE), Vector2((CLOTH.x + 14.0) / TILE, (POLE_H + 16.0) / TILE))
