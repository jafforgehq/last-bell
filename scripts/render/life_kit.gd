## The small tools the base's little life (round 24, scripts/render/base_life.gd) is built from: a builder of baked 2D meshes
## (grids and rectangles with vertex colours), the two cloth shaders (a flag, and clothes on a line) that move such a mesh on
## the GPU from a time and a wind, and a few numbers the parts share. Nothing here is a rule of the game: it is all drawing,
## and none of it allocates a frame (a mesh is baked once, a shader is moved by two numbers).
##
## The meshes are in pixels around the node's own place (a tile is TILE pixels), "up" the screen is negative y. The shaders read
## the mesh's UV: the flag's UV.x is how far along the cloth the vertex is (0 at the pole, 1 at the free end); the clothes' UV.y is
## how far down a piece hangs (0 at the line, 1 at the hem) and its UV.x a number of its own that keeps the pieces out of step.
extends RefCounted

const TILE := 64.0
## The ink the game outlines its drawings with.
const INK := Color(0.10, 0.08, 0.06, 0.85)

## A flag: the free end flutters, more with the wind (`wind` 0 to about 1.4), and the cloth is shaded a little by the fold.
const FLAG_SHADER := "
shader_type canvas_item;
uniform float t = 0.0;
uniform float wind = 0.3;
varying float fold;
void vertex() {
	float k = UV.x;
	float ph = t * (4.0 + 3.0 * wind) - k * 7.0;
	VERTEX.y += sin(ph) * k * (1.5 + 7.0 * wind);
	VERTEX.x -= k * k * (1.0 + 5.0 * wind) * (0.5 + 0.5 * sin(ph * 0.5));
	fold = cos(ph) * k;
}
void fragment() {
	COLOR.rgb *= 1.0 + fold * 0.16;
}
"

## Clothes on a line: each piece hangs from the line and swings from its top, more with the wind, a little out of step with
## the others (UV.x), and lifts a hair at the hem when it blows hard.
const CLOTH_SHADER := "
shader_type canvas_item;
uniform float t = 0.0;
uniform float wind = 0.3;
varying float fold;
void vertex() {
	float h = UV.y;
	float ph = t * (1.6 + 1.4 * wind) + UV.x * 6.28;
	VERTEX.x += sin(ph) * h * (1.2 + 7.0 * wind);
	VERTEX.y -= abs(sin(ph * 0.7)) * h * h * 3.0 * wind;
	fold = sin(ph) * h;
}
void fragment() {
	COLOR.rgb *= 1.0 - abs(fold) * 0.10;
}
"


## A mesh made of rectangles and grids of coloured vertices (`add_grid`), baked with `bake`.
class Builder:
	extends RefCounted
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	## A grid of nx by ny cells from `at`, `size` big; its colour goes from `top` to `bottom` down the grid, and each vertex's UV is
	## (u0 + share across * (u1 - u0), share down); by default u0 = u1 = 0, so UV.x is 0 all over (a flag's grid says 0 and 1). nx = ny = 1 is a plain rectangle.
	func add_grid(at: Vector2, size: Vector2, nx: int, ny: int, top: Color, bottom: Color, u0: float = 0.0, u1: float = 0.0) -> void:
		var base := verts.size()
		for j in ny + 1:
			var v := float(j) / float(ny)
			for i in nx + 1:
				var u := float(i) / float(nx)
				verts.append(at + Vector2(size.x * u, size.y * v))
				colors.append(top.lerp(bottom, v))
				uvs.append(Vector2(lerpf(u0, u1, u), v))
		for j in ny:
			for i in nx:
				var a := base + j * (nx + 1) + i
				var b := a + 1
				var c := a + nx + 1
				var d := c + 1
				indices.append_array(PackedInt32Array([a, b, c, b, d, c]))

	## A straight stroke from `a` to `b` of this width, as one rectangle; the UV of its two ends is `uv_a` and `uv_b` (zero by default).
	func add_stroke(a: Vector2, b: Vector2, width: float, color: Color, uv_a: Vector2 = Vector2.ZERO, uv_b: Vector2 = Vector2.ZERO) -> void:
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x) * width * 0.5
		var base := verts.size()
		var pts := [a - n, a + n, b - n, b + n]
		var uv_of := [uv_a, uv_a, uv_b, uv_b]
		for i in 4:
			verts.append(pts[i])
			colors.append(color)
			uvs.append(uv_of[i])
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))

	## An ellipse of this colour as a fan of `n` triangles; every vertex has the UV `uv` (the shaders read it as the part's number).
	func add_ellipse(c: Vector2, rx: float, ry: float, color: Color, uv: Vector2 = Vector2.ZERO, n: int = 10) -> void:
		var base := verts.size()
		verts.append(c)
		colors.append(color)
		uvs.append(uv)
		for i in n:
			var a := TAU * float(i) / float(n)
			verts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
			colors.append(color)
			uvs.append(uv)
		for i in n:
			indices.append_array(PackedInt32Array([base, base + 1 + i, base + 1 + ((i + 1) % n)]))

	## An ellipse with a thin ink rim round it (a slightly bigger ink ellipse under it), as the game's drawings are outlined.
	func add_blob(c: Vector2, rx: float, ry: float, color: Color, uv: Vector2 = Vector2.ZERO, rim: float = 1.2, n: int = 10) -> void:
		add_ellipse(c, rx + rim, ry + rim, INK, uv, n)
		add_ellipse(c, rx, ry, color, uv, n)

	## A polygon that can be seen from `centre` (every point of its outline in turn), a fan of triangles; `colors_of` the colour of each
	## outline point (empty: `color` all over) and `centre_color` that of the centre.
	func add_fan(centre: Vector2, centre_color: Color, outline: PackedVector2Array, colors_of: PackedColorArray, uv: Vector2 = Vector2.ZERO) -> void:
		var base := verts.size()
		verts.append(centre)
		colors.append(centre_color)
		uvs.append(uv)
		var n := outline.size()
		for i in n:
			verts.append(outline[i])
			colors.append(colors_of[i] if i < colors_of.size() else centre_color)
			uvs.append(uv)
		for i in n:
			indices.append_array(PackedInt32Array([base, base + 1 + i, base + 1 + ((i + 1) % n)]))

	func bake() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## A shader material made of this code (one shared by every mesh that moves the same way).
static func material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


## The sky as the rules say: whether it is day (the birds and the dog are up) at this hour, with `dusk` the hour the bell rings.
static func is_day(hour: float, dusk: float) -> bool:
	return hour >= 6.3 and hour < dusk - 0.2


## Whether a straight walk from `a` to `b` (tiles) stays on open ground of this grid (`solid`: the walking grid of the world, `w` its
## width): checked every quarter of a tile, a tile of margin on the side is not asked for.
static func clear_walk(solid: PackedByteArray, w: int, a: Vector2, b: Vector2) -> bool:
	if solid.is_empty():
		return true
	var steps := maxi(1, int(a.distance_to(b) * 4.0))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		var idx := int(floorf(p.y)) * w + int(floorf(p.x))
		if idx < 0 or idx >= solid.size() or int(solid[idx]) != 0:
			return false
	return true
