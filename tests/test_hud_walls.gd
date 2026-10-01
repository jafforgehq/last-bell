extends "res://tests/case.gd"

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")


func test_the_school_and_its_door_have_names() -> void:
	eq(Hud.SIDE.get("S"), "School", "the school side")
	eq(Hud.MATERIAL.get("door"), "boarded door", "the boarded door")
	for key in ["N", "W", "E"]:
		check(Hud.SIDE.has(key), "%s is still named" % key)
	for key in ["container", "bus", "car", "pallets", "gate", "chainlink", "blocks"]:
		check(Hud.MATERIAL.has(key), "%s is still named" % key)


func test_a_school_door_shows_its_side_and_material() -> void:
	var ctx := Kit.build()
	var seg = ctx.sim.segments[3]
	seg.side = "S"
	seg.kind = "door"
	seg.name = "School door"
	ctx.hud.select({"kind": "segment", "ref": seg})
	Kit.update(ctx)
	var all := Kit.texts(ctx.hud.inspect)
	check(all.has("School · boarded door"), "the subtitle: %s" % str(all))
	check(all.has("School door"), "and the name")
	Kit.free_all(ctx)


func test_an_unknown_side_or_material_does_not_break_the_panel() -> void:
	var ctx := Kit.build()
	var seg = ctx.sim.segments[3]
	seg.side = "Q"
	seg.kind = "mystery"
	ctx.hud.select({"kind": "segment", "ref": seg})
	Kit.update(ctx)
	var all := Kit.texts(ctx.hud.inspect)
	var found := false
	for t in all:
		if t.contains("mystery"):
			found = true
	check(found, "the panel names what it does not know by its own word: %s" % str(all))
	check(not ctx.hud.inspect_refs.is_empty(), "and still builds its rows")
	# every kind of piece in the map still selects
	for s in ctx.sim.segments:
		ctx.hud.select({"kind": "segment", "ref": s})
		Kit.update(ctx)
	check(true, "all of the map's pieces select")
	Kit.free_all(ctx)
