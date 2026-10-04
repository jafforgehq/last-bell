extends "res://tests/case.gd"
## The ground of the world (scripts/world.gd `_build_ground`) is one mesh for each terrain, not a tile map: the draws of the ground fell from
## some hundreds to about a dozen. These tests read the meshes back against the map's own terrain: every tile is covered once, by the mesh
## of its terrain, and the picture lies on it as the tile map laid it (the atlas of 4 x 4 pieces repeating every 4 tiles, from the world's
## corner).

const TutorialKit := preload("res://tests/tutorial_kit.gd")
const GD := preload("res://scripts/game_data.gd")


func test_the_ground_is_a_mesh_for_each_terrain_that_covers_every_tile_once() -> void:
	var made := TutorialKit.make()
	var world = made.world
	var ground: Node = world.get_node("Ground")
	var types := {}
	for name in made.data.terrainTypes:
		types[int(made.data.terrainTypes[name].id)] = made.data.terrainTypes[name]
	var terrains := {}
	for t in world.terrain:
		if t > 0:
			terrains[int(t)] = true
	eq(ground.get_child_count(), terrains.size(), "one node for each terrain the map uses")
	check(ground.get_child_count() <= 20, "a handful of draws (%d)" % ground.get_child_count())
	var seen := PackedByteArray()
	seen.resize(world.W * world.H)
	var bad_phase := 0
	for mi in ground.get_children():
		var t := int(String(mi.name).trim_prefix("Terrain"))
		check(mi is MeshInstance2D and mi.texture != null and mi.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED, "%s repeats its atlas" % mi.name)
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var tex: Texture2D = mi.texture
		for k in range(0, verts.size(), 4):
			var a := verts[k] / GD.TILE
			var b := verts[k + 2] / GD.TILE
			# the picture: tile (x, y) shows piece (x % 4, y % 4) of 128 pixels
			var piece := Vector2(uvs[k].x * tex.get_width() / 128.0, uvs[k].y * tex.get_height() / 128.0)
			if not (is_equal_approx(piece.x, a.x) and is_equal_approx(piece.y, a.y)):
				bad_phase += 1
			for y in range(int(a.y), int(b.y)):
				for x in range(int(a.x), int(b.x)):
					seen[y * world.W + x] += 1
					if int(world.terrain[y * world.W + x]) != t:
						failures.append("tile %d,%d is terrain %d but %s covers it" % [x, y, int(world.terrain[y * world.W + x]), mi.name])
						break
	eq(bad_phase, 0, "every rectangle's picture starts where the tile map's piece would be")
	var wrong := 0
	for i in world.W * world.H:
		var want := 1 if world.terrain[i] > 0 and types.has(int(world.terrain[i])) else 0
		if int(seen[i]) != want:
			wrong += 1
	eq(wrong, 0, "no tile is bare or covered twice")
	world.queue_free()
	await Engine.get_main_loop().process_frame
