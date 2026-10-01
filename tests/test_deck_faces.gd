extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const DeckFaces := preload("res://scripts/render/deck_faces.gd")


func _alpha(tex: Texture2D, x: int, y: int) -> float:
	return tex.get_image().get_pixel(x, y).a


func test_the_walkways_and_towers_become_decks_and_the_ladders_are_found() -> void:
	var data: Dictionary = Helpers.make(1, 1).data
	var low := DeckFaces.new()
	low.setup(data, ["walkway"])
	eq(low.decks.size(), 3, "the north walkway and the west and east ones")
	var fronts := 0
	var wests := 0
	var easts := 0
	for l in low.ladders:
		match l.kind:
			"front":
				fronts += 1
			"west":
				wests += 1
			"east":
				easts += 1
	eq([fronts, wests, easts], [3, 3, 3], "three ladders on each walkway")
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


func test_the_posts_stand_in_equal_bays_from_end_to_end() -> void:
	var posts := DeckFaces.post_positions(20.0, 64.0)
	near(posts[0], 20.0 + DeckFaces.CAP_POST, 0.0001, "the first post stands a little in from the end")
	near(posts[posts.size() - 1], 64.0 - DeckFaces.CAP_POST, 0.0001, "and so does the last")
	eq(posts.size(), 36, "35 bays along the north walkway")
	var bay := posts[1] - posts[0]
	near(bay, DeckFaces.BAY_WIDTH, 0.05, "each bay is about the width the art is cut to")
	for i in posts.size() - 1:
		near(posts[i + 1] - posts[i], bay, 0.0001, "bay %d is as wide as the first" % i)
	var end := DeckFaces.post_positions(20.0, 21.55)
	eq(end.size(), 2, "the short end of a side walkway is one bay")
	near(end[1] - end[0], 1.55 - 2.0 * DeckFaces.CAP_POST, 0.0001, "between its two end posts")


func test_the_supports_along_a_side_walkway_start_clear_of_the_north_face_and_end_near_its_end() -> void:
	var legs := DeckFaces.leg_positions(19.55, 44.0)
	check(legs.size() >= 8, "a row of them along the walkway: %d" % legs.size())
	check(legs[0] >= 19.55 + DeckFaces.WALKWAY_HEIGHT, "the first starts below where the north face ends")
	for i in legs.size() - 1:
		near(legs[i + 1] - legs[i], DeckFaces.LEG_SPACING, 0.0001, "evenly spaced")
	check(legs[legs.size() - 1] + DeckFaces.WALKWAY_HEIGHT <= 44.0 + 0.3 + 0.0001, "and the last one's foot is not far past the walkway's end")


func test_every_piece_of_art_is_the_size_the_faces_are_laid_out_for() -> void:
	var data: Dictionary = Helpers.make(1, 1).data
	var f := DeckFaces.new()
	f.setup(data, ["walkway", "tower"])
	for tex in f._bays:
		near(float(tex.get_height()) / DeckFaces.ART_PX, DeckFaces.WALKWAY_HEIGHT, 0.01, "a bay is as tall as a walkway")
		near(float(tex.get_width()) / DeckFaces.ART_PX, DeckFaces.BAY_WIDTH, 0.01, "and as wide as a bay")
	for tex in f._posts:
		near(float(tex.get_height()) / DeckFaces.ART_PX, DeckFaces.WALKWAY_HEIGHT, 0.01, "a post piece is as tall as a walkway")
		near(float(tex.get_width()) / DeckFaces.ART_PX, DeckFaces.POST_WIDTH, 0.01, "and as wide as the posts are set")
	for key in ["w", "e"]:
		near(float(f._cap[key].get_width()) / DeckFaces.ART_PX, DeckFaces.CAP_WIDTH, 0.01, "an end piece is as wide as set")
		near(float(f._cap[key].get_height()) / DeckFaces.ART_PX, DeckFaces.WALKWAY_HEIGHT, 0.01, "and as tall as a walkway")
	near(float(f._tower.get_height()) / DeckFaces.ART_PX, DeckFaces.TOWER_HEIGHT, 0.02, "a tower base is as tall as a tower")
	check(float(f._tower.get_width()) / DeckFaces.ART_PX >= 3.6, "and at least as wide as the deck")
	near(float(f._leg.get_width()) / DeckFaces.ART_PX, DeckFaces.LEG_WIDTH, 0.01, "a leg's width")
	near(float(f._leg.get_height()) / DeckFaces.ART_PX, DeckFaces.WALKWAY_HEIGHT, 0.01, "and height")
	near(float(f._ladder.get_width()) / DeckFaces.ART_PX, DeckFaces.LADDER_WIDTH, 0.01, "a hung ladder's width")
	near(float(f._ladder.get_height()) / DeckFaces.ART_PX, DeckFaces.LADDER_LENGTH, 0.01, "and length")
	for key in ["west", "east"]:
		near(float(f._side[key].get_width()) / DeckFaces.ART_PX, DeckFaces.LADDER_LEAN, 0.01, "a leaning ladder's reach")
		near(float(f._side[key].get_height()) / DeckFaces.ART_PX, DeckFaces.LADDER_SPAN, 0.01, "and width")
	f.free()


func test_the_space_under_a_deck_is_dark_and_solid_not_see_through() -> void:
	var data: Dictionary = Helpers.make(1, 1).data
	var f := DeckFaces.new()
	f.setup(data, ["walkway", "tower"])
	var bay: Texture2D = f._bays[0]
	var cx := bay.get_width() / 2
	for fy in [0.25, 0.5, 0.75, 0.9]:
		var y := int(float(bay.get_height()) * fy)
		check(_alpha(bay, cx, y) > 0.99, "a bay is opaque at %d%% of its height" % int(fy * 100.0))
	var tower: Texture2D = f._tower
	check(_alpha(tower, tower.get_width() / 2, int(float(tower.get_height()) * 0.4)) > 0.99, "a tower base is opaque between its legs")
	var img := tower.get_image()
	var c := img.get_pixel(tower.get_width() / 2, int(float(tower.get_height()) * 0.9))
	check(c.r < 0.25 and c.g < 0.25 and c.b < 0.25, "and dark there")
	f.free()


func test_the_world_puts_the_faces_where_they_belong_and_the_old_north_ladders_are_gone() -> void:
	var g := Helpers.make(1, 1)
	var world = g.world
	eq(world.layers[2].get_child(0).name, "DeckFacesLow", "behind the planks, so they draw over its top edge")
	var big: Node = world.layers[4]
	eq(big.get_child(big.get_child_count() - 1).name, "DeckFacesBig", "a tower's base comes last: over the containers beside it")
	for o in g.data.objects:
		if o.kind == "ladder":
			check(o.pieces.is_empty(), "the flat ladder sprite is gone: the faces draw it")
	g.world.free()
