extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const DeckFaces := preload("res://scripts/render/deck_faces.gd")


func test_the_walkways_and_towers_become_decks_and_the_north_ladders_go_down_the_face() -> void:
	var data: Dictionary = Helpers.make(1, 1).data
	var low := DeckFaces.new()
	low.setup(data, ["walkway"])
	eq(low.decks.size(), 3, "the north walkway and the west and east ones")
	eq(low.ladders.size(), 3, "three ladders on the north walkway")
	var north: Dictionary = low.decks[0]
	near(north.y1, 19.55, 0.1, "its south edge")
	near(north.x0, 20.0, 0.1, "it starts at the west wall")
	near(north.x1, 64.0, 0.1, "and runs to the east wall")
	near(north.height, DeckFaces.WALKWAY_HEIGHT, 0.0001, "a walkway stands this high")
	var big := DeckFaces.new()
	big.setup(data, ["tower"])
	eq(big.decks.size(), 2, "two corner towers")
	eq(big.ladders.size(), 0, "the ladders belong to the walkway")
	check(big.decks[0].height > low.decks[0].height, "a tower stands higher than a walkway")
	low.free()
	big.free()


func test_the_world_draws_the_faces_first_in_their_layers_and_the_old_north_ladders_are_gone() -> void:
	var g := Helpers.make(1, 1)
	var world = g.world
	eq(world.layers[2].get_child(0).name, "DeckFacesLow", "behind the planks and the ladders")
	eq(world.layers[4].get_child(0).name, "DeckFacesBig", "behind the containers a tower stands beside")
	for o in g.data.objects:
		if o.kind == "ladder" and absf(float(o.a)) < 0.01:
			check(o.pieces.is_empty(), "the flat ladder sprite is gone: the faces draw it")
	g.world.free()
