## What is inside one house of the town (scripts/town/town_world.gd makes one for each house that has any): its rugs and clutter, then its furniture, in the generator's order (decals
## first, then north to south). The kit objects are the world's bucket of this house (`data.objects` with `in` = the house's id), drawn by the picture of their look.
## The world shows the node only while the camera is near the house (a roof is over it otherwise): the draw calls of a view are not spent under roofs. Drawn once, when it is first shown.
extends Node2D

const TownChunkPaint := preload("res://scripts/town/town_chunk_paint.gd")

var world
var items := PackedInt32Array()


func setup(w, list: PackedInt32Array) -> void:
	world = w
	items = list
	z_index = 2


func _draw() -> void:
	if world == null:
		return
	var objs: Array = world.d.objects
	# the rugs and clutter first, then the furniture; each a texture at a time
	var low := PackedInt32Array()
	var high := PackedInt32Array()
	for k in items:
		if int(objs[k].layer) == 1:
			low.append(k)
		else:
			high.append(k)
	TownChunkPaint.draw_grouped(self, objs, low)
	TownChunkPaint.draw_grouped(self, objs, high)
