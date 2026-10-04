## The houses on the screen (One House, WP2): the roof that fades, what is drawn (`pawn_visible`), the doors, the veils and the bounded node count, TownArt and the base's props.
## A mini town (Helpers.town_game) and the real sim; the clearing and search modules (WP3) are small stand-ins handed to the view.
extends "res://tests/case.gd"

const Helpers := preload("res://tests/helpers.gd")
const HouseView := preload("res://scripts/render/house_view.gd")
const BasePropsView := preload("res://scripts/render/base_props_view.gd")
const DoorNode := preload("res://scripts/render/door_node.gd")
const TownArt := preload("res://scripts/town/town_art.gd")
const MINI := "res://tests/fixtures/town_art_mini.json"


class Clearing extends RefCounted:
	var revealed := {}

	func is_revealed(room: int) -> bool:
		return revealed.has(room)


class Search extends RefCounted:
	var ids := {}

	func is_looted(id: String) -> bool:
		return ids.has(id)


class Base extends RefCounted:
	func props() -> Array:
		return [{"id": "bed", "kind": "bed", "pos": Vector2(40.5, 41.0), "room": 0, "face": "S"}]


class Pawn extends RefCounted:
	var x := 0.0
	var y := 0.0


## {"g": the town_game dict, "hv": a house view bound to it, "clearing", "h": the start house, "av": the avatar}. The avatar stands in the middle of its start room.
func _rig() -> Dictionary:
	var g := Helpers.town_game(1, {"blocks": 2})
	var sim = g.sim
	var clearing := Clearing.new()
	var hv := HouseView.new()
	hv.bind(sim, sim.houses, clearing, Search.new())
	var h: int = sim.houses.start_house()
	var av = sim.avatar.player()
	clearing.revealed[int(g.town.start.room)] = true
	return {"g": g, "hv": hv, "clearing": clearing, "h": h, "av": av, "sim": sim}


func _done(r: Dictionary) -> void:
	r.hv.free()
	r.g.world.free()


func _frames(hv, n: int, dt: float = 0.05) -> void:
	for i in n:
		hv.on_frame(dt)


## A tile outside every house.
func _street_tile(town: Dictionary) -> Vector2:
	var w: int = town.size.x
	for i in town.tile_house.size():
		if town.tile_house[i] < 0 and town.data.solidP[i] == 0:
			return Vector2(float(i % w) + 0.5, float(i / w) + 0.5)
	return Vector2.ZERO


func test_roof_fades_in_the_house_the_avatar_is_in() -> void:
	var r := _rig()
	var hv = r.hv
	var av = r.av
	hv.on_sync_views(Rect2(av.x - 12.0, av.y - 8.0, 24.0, 16.0))
	_frames(hv, 7)
	check(hv.has_roof(r.h), "the start house has a roof")
	check(hv.roof_alpha(r.h) < 0.01, "its roof is gone within 0.3 s")
	var others_shut := true
	for hd in r.g.town.houses:
		if int(hd.id) != r.h and hv.has_roof(int(hd.id)) and hv.roof_alpha(int(hd.id)) != 1.0:
			others_shut = false
	check(others_shut, "every other roof stays shut")
	var out := _street_tile(r.g.town)
	av.x = out.x
	av.y = out.y
	hv.on_sync_views(Rect2(av.x - 12.0, av.y - 8.0, 24.0, 16.0))
	_frames(hv, 7)
	eq(hv.roof_alpha(r.h), 1.0, "the roof is back when the avatar is outside")
	_done(r)


func test_a_pawn_is_drawn_by_where_it_stands() -> void:
	var r := _rig()
	var hv = r.hv
	var town: Dictionary = r.g.town
	hv.on_frame(0.05)
	var rooms: Array = town.houses[r.h].rooms
	var home := int(town.start.room)
	var other_room := -1
	for rm in rooms:
		if int(rm) != home:
			other_room = int(rm)
	var p := Pawn.new()
	var at: Vector2 = Rect2(town.rooms[other_room].rect).get_center()
	p.x = at.x
	p.y = at.y
	check(not hv.pawn_visible(p), "in an unrevealed room of the avatar's house: not drawn")
	r.clearing.revealed[other_room] = true
	check(hv.pawn_visible(p), "once the room is revealed: drawn")
	var st := _street_tile(town)
	p.x = st.x
	p.y = st.y
	check(hv.pawn_visible(p), "outside every house: drawn")
	var far_room := -1
	for rm in town.rooms.size():
		if int(town.rooms[rm].house) != r.h:
			far_room = rm
			break
	var far: Vector2 = Rect2(town.rooms[far_room].rect).get_center()
	p.x = far.x
	p.y = far.y
	r.clearing.revealed[far_room] = true
	check(not hv.pawn_visible(p), "in a room of another house: not drawn, revealed or not")
	check(hv.pawn_visible(r.av), "the avatar is always drawn")
	_done(r)


func test_a_door_swings_for_a_pawn_and_shuts_half_a_second_after() -> void:
	var node := DoorNode.new()
	var door := {"tiles": [Vector2i(10, 10), Vector2i(11, 10)], "exterior": false, "side": "H"}
	node.setup(door, true, Vector2.DOWN, 0)
	for i in 8:
		node.tick(0.05, true)
	check(node.open_target and node.open_t == 1.0, "open while somebody is near")
	for i in 8:
		node.tick(0.05, false)
	check(node.open_target, "0.4 s after the last one it is still open")
	for i in 4:
		node.tick(0.05, false)
	check(not node.open_target, "shut after 0.5 s")
	for i in 6:
		node.tick(0.05, false)
	eq(node.open_t, 0.0, "and it has swung shut")
	node.wedged = true
	for i in 40:
		node.tick(0.05, false)
	check(node.open_target and node.open_t == 1.0, "a look-in wedges it open")
	node.free()
	# through the view: a pawn at an outside door, then gone; a reveal from a step away wedges the doors of that room
	var r := _rig()
	var hv = r.hv
	var av = r.av
	var hd: Dictionary = r.g.town.houses[r.h]
	var idx := -1
	for i in hd.doors.size():
		if not bool(hd.doors[i].exterior):
			idx = i
			break
	var d: Dictionary = hd.doors[idx]
	var c := Vector2(d.tiles[0]) + Vector2(0.5, 0.5)
	av.x = c.x
	av.y = c.y + 1.0 if hv._room_of(int(c.x), int(c.y) + 1) >= 0 else c.y - 1.0
	hv.on_sync_views(Rect2(av.x - 12.0, av.y - 8.0, 24.0, 16.0))
	_frames(hv, 8)
	var dn = hv.door_node(r.h, idx)
	check(dn != null and dn.open_target, "the door of the room the avatar is in swings open")
	av.x = c.x + 9.0
	av.y = c.y
	_frames(hv, 4)
	_frames(hv, 12)
	check(dn.open_target == false or not dn.near_now, "and shuts when the avatar has gone")
	_done(r)


func test_the_unrevealed_rooms_are_veiled_and_the_node_count_is_bounded() -> void:
	var r := _rig()
	var hv = r.hv
	var av = r.av
	var town: Dictionary = r.g.town
	hv.on_sync_views(Rect2(av.x - 10.0, av.y - 7.0, 20.0, 14.0))
	_frames(hv, 4)
	var rooms: Array = town.houses[r.h].rooms
	eq(hv.veil_count(), rooms.size(), "a veil for each room of the avatar's house")
	var home := int(town.start.room)
	var dark := -1
	for rm in rooms:
		if int(rm) != home:
			dark = int(rm)
	_frames(hv, 12)
	check(not hv.veil_of(home).visible, "the avatar's own room is open")
	check(hv.veil_of(dark).visible, "an unrevealed room is dark")
	r.clearing.revealed[dark] = true
	hv.on_event({"type": "room_revealed", "room": dark, "house": r.h})
	_frames(hv, 12)
	check(not hv.veil_of(dark).visible, "the veil lifts when the room is revealed")
	var near: int = hv.node_count()
	var all := 0
	for hd in town.houses:
		all += 1 + hd.doors.size()
	check(near < all, "nodes are made for the houses near the view only (%d of %d)" % [near, all])
	var st := _street_tile(town)
	av.x = st.x
	av.y = st.y
	hv.on_sync_views(Rect2(av.x - 10.0, av.y - 7.0, 20.0, 14.0))
	_frames(hv, 4)
	eq(hv.veil_count(), 0, "no veils outside a house")
	_done(r)


func test_the_art_kit_is_read_in_one_place_and_a_missing_one_is_a_placeholder() -> void:
	TownArt.load_manifest("res://tests/fixtures/none/none.json")
	var d := TownArt.door("front", "s", "closed")
	check(d.placeholder and d.file == "", "no manifest: a flat door")
	check(TownArt.roof("small").placeholder and TownArt.fence("gate").placeholder and TownArt.prop("bed").placeholder, "no manifest: every descriptor is flat")
	eq(TownArt.prop("bed").size, Vector2(1, 2), "and the placeholder bed keeps its footprint")
	TownArt.load_manifest(MINI)
	var w := TownArt.door("front", "w", "closed")
	check(not w.placeholder and String(w.file).ends_with("house/door_front.png") and w.rect == Rect2(130, 0, 128, 128), "a sheet's sprite: the picture and its part")
	eq(TownArt.door("front", "s", "open").rect, Rect2(520, 0, 128, 128), "the open state")
	eq(TownArt.prop("fridge", "open").rect, Rect2(648, 0, 160, 160), "open is the kit's opened")
	eq(TownArt.prop("bed").item, "bed_single", "the base's bed is the kit's single bed")
	check(TownArt.door("interior").placeholder, "an item the kit lacks is flat")
	TownArt.load_manifest()
	# the base's props and the looted containers are what the props view shows
	var r := _rig()
	var search := Search.new()
	var bp := BasePropsView.new()
	bp.bind(r.sim, r.sim.houses, search, Base.new())
	eq(bp.refresh(), 1, "the claimed base's bed")
	var hd: Dictionary = r.g.town.houses[r.h]
	if not hd.containers.is_empty():
		search.ids[String(hd.containers[0])] = true
		eq(bp.refresh(), 2, "a searched container is drawn open")
	bp.free()
	_done(r)
