## Makes the roofs' atlas (scripts/render/roof_atlas.gd) in two steps of its own while the loading card is up (WORLD3): the atlas of the three kits and the roof extras costs about 40 ms, and put in
## the house view's `on_ready` it made that part's frame longer than it was. Two view parts of the town facade (scripts/town/town_game.gd VIEW_PARTS, "roof_warm" and "roof_warm2", the same file), each
## `heavy`: the facade gives it a frame to itself, so the first step (the pictures of the kits) and the second (the extras, the chimneys, the sheet) are two frames of about 20 ms and no longer.
extends RefCounted

var heavy := true


func on_ready(main) -> void:
	var town = main.get("town")
	var hv = town.part("house_view") if town != null else null
	if hv != null and hv.has_method("warm_roofs"):
		hv.warm_roofs(0 if town.part("roof_warm") == self else 1)
