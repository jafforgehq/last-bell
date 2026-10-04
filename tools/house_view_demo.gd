## Looks at one house of the town with the house view (One House, WP2): the roofs, the dark rooms, the doors, the base's props and the opened containers, on the real
## town map and the real avatar and dead (Helpers.town_game), with stand-ins for the clearing, search and base modules that do not exist yet. Windowed (headless cannot
## render), from the repo root:
##
##   Godot --path . --resolution 1280x800 --script res://tools/house_view_demo.gd -- --scene=outside --shot=/path/outside.png
##   Godot --path . --resolution 1280x800 --script res://tools/house_view_demo.gd -- --scene=inside --base --shot=/path/inside.png
##
## --scene=outside|inside (the avatar is outside by the front door, or inside next to a door with the room it stands in and the room beyond revealed and the rest dark)
## --art=path/to/town_art.json (read the art kit's manifest from there)  --at=x,y (put the avatar there)  --reveal=a,b,... (room indexes revealed; "all")  --base (the claimed base's props and the house's containers looted)
## --tour (headless works: the avatar walks in through the front door, to the door of its room and through it, printing the roof, the doors and the veils as they change, then
## TOUR DONE; every error of the run is in the output)  --blocks=N (town size in blocks, 2)  --zoom=px (pixels to the tile)  --frames=N (frames before the shot, 45)  --shot=path (save a PNG and quit; without it the window stays,
## WASD walks the avatar, E reveals the room under it, Esc quits).
extends SceneTree

const GD := preload("res://scripts/game_data.gd")
const Helpers := preload("res://tests/helpers.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const TownGen := preload("res://scripts/town/town_gen.gd")
const HouseView := preload("res://scripts/render/house_view.gd")
const BasePropsView := preload("res://scripts/render/base_props_view.gd")

const TILE := GD.TILE
const TownArt := preload("res://scripts/town/town_art.gd")

var args := {}
var sim
var world
var town: Dictionary
var data: Dictionary
var camera: Camera2D
var entities: Node2D
var hv
var props
var nodes := {}
var frames := 0
var avatar
var zoom_px := 48.0
var cam_at := Vector2.ZERO
var clearing := Clearing.new()
var looted := Search.new()
var base := Base.new()
var _tour: Array = []
var _tour_i := 0
var _last := {}


## Stand-ins for the modules of WP3 (the plan's frozen signatures).
class Clearing extends RefCounted:
	var revealed := {}
	var all := false

	func is_revealed(room: int) -> bool:
		return all or revealed.has(room)

	func reveal(room: int, _why: String = "") -> bool:
		var news := not revealed.has(room)
		revealed[room] = true
		return news


class Search extends RefCounted:
	var ids := {}

	func is_looted(id: String) -> bool:
		return ids.has(id)


class Base extends RefCounted:
	var list: Array = []

	func props() -> Array:
		return list


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			var kv := s.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()


func _run() -> void:
	data = GD.load_all()
	if args.has("art"):
		TownArt.load_manifest(String(args.art))
	var g: Dictionary = Helpers.town_game(1, {"blocks": int(args.get("blocks", "2"))})
	sim = g.sim
	world = g.world
	town = g.town
	var start: Dictionary = town.start
	if args.has("house"):
		# another house: the avatar in the middle of its first room (the clear dead of the start house stay where they are)
		var hh: Dictionary = town.houses[int(args.house)]
		var r0 := int(hh.rooms[0])
		start = {"house": int(args.house), "pos": Rect2(town.rooms[r0].rect).get_center().floor() + Vector2(0.5, 0.5), "room": r0}
	var house: Dictionary = town.houses[int(start.house)]
	if args.has("hour"):
		sim.minutes = float(args.hour) * 60.0
		sim.phase = sim.seasons.phase_at(sim.minutes)
	entities = Node2D.new()
	entities.name = "Entities"
	entities.z_index = 6
	entities.y_sort_enabled = true
	world.add_child(entities)
	for tr in town.data.trees:
		var spr := Sprite2D.new()
		var box: Array = data.tree.box
		var dens := float(data.tree.density)
		spr.texture = GD.tex(tr.file)
		spr.centered = false
		spr.offset = Vector2(box[0], box[1]) * dens
		spr.scale = Vector2.ONE * (TILE / dens)
		spr.position = Vector2(tr.x, tr.y) * TILE
		entities.add_child(spr)
	sim.clearing = clearing
	sim.search = looted
	sim.base = base
	avatar = sim.avatar.player()
	_place(house, start)
	# the dead of the house, awake and standing where the records put them
	if not args.has("nodead"):
		sim.field._wake_near(Vector2(start.pos), 14.0, "stage", null)
	_report(house)
	hv = HouseView.new()
	hv.name = "HouseView"
	world.add_child(hv)
	hv.bind(sim, sim.houses, clearing, looted)
	props = BasePropsView.new()
	props.name = "BaseProps"
	world.add_child(props)
	props.bind(sim, sim.houses, looted, base)
	if args.has("tour"):
		_make_tour(house, start)
	camera = Camera2D.new()
	root.add_child(camera)
	camera.make_current()
	var vp := root.get_visible_rect().size
	var r := Rect2(house.rect)
	cam_at = r.get_center()
	zoom_px = float(args.zoom) if args.has("zoom") else clampf(minf(vp.x / (r.size.x + 7.0), vp.y / (r.size.y + 5.0)), 16.0, 80.0)
	camera.position = cam_at * TILE
	camera.zoom = Vector2.ONE * (zoom_px / TILE)
	process_frame.connect(_tick)


## Puts the avatar and the clearing where the scene asks.
func _place(house: Dictionary, start: Dictionary) -> void:
	var scene := String(args.get("scene", "inside"))
	var at := Vector2(start.pos)
	if scene == "outside":
		var d := _front_door(house)
		var c := _centre(d)
		var out := {"N": Vector2(0, -1), "S": Vector2(0, 1), "W": Vector2(-1, 0), "E": Vector2(1, 0)}[String(d.side)] as Vector2
		at = c + out * 2.6
	else:
		var d := _inner_door(house, int(start.room))
		if not d.is_empty():
			var c := _centre(d)
			for off in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				for t in d.tiles:
					var nb: Vector2i = t + off
					if TownGen.room_at(town, nb.x, nb.y) == int(start.room):
						at = Vector2(nb) + Vector2(0.5, 0.5)
			clearing.reveal(int(start.room))
			for t in d.tiles:
				for off in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
					var rr := TownGen.room_at(town, (t + off).x, (t + off).y)
					if rr >= 0:
						clearing.reveal(rr)
			print("avatar near the door at ", c, " standing at ", at)
	if args.has("door"):
		# --door=N,S: the avatar stands by the Nth inner door of the house on its side S (0 or 1); that room is revealed, the other stays dark
		var ds := String(args.door).split(",")
		var inner: Array = []
		for dd in house.doors:
			if not bool(dd.exterior):
				inner.append(dd)
		var dd2: Dictionary = inner[int(ds[0]) % inner.size()]
		var sides: Array = []
		for t in dd2.tiles:
			for off in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var nb: Vector2i = t + off
				var rr2 := TownGen.room_at(town, nb.x, nb.y)
				if rr2 >= 0 and not sides.any(func(e): return e[0] == rr2):
					sides.append([rr2, Vector2(nb) + Vector2(0.5, 0.5)])
		var pick: Array = sides[(int(ds[1]) if ds.size() > 1 else 0) % sides.size()]
		at = pick[1]
		clearing.revealed.clear()
		clearing.reveal(int(pick[0]))
	if args.has("at"):
		var c2 := String(args.at).split(",")
		at = Vector2(float(c2[0]), float(c2[1]))
	if args.has("reveal"):
		if String(args.reveal) == "all":
			clearing.all = true
		else:
			clearing.revealed.clear()
			for s in String(args.reveal).split(","):
				clearing.reveal(int(s))
	avatar.x = at.x
	avatar.y = at.y
	if args.has("base"):
		_make_base(house)
	var av_room := TownGen.room_at(town, at.x, at.y)
	if av_room >= 0:
		clearing.reveal(av_room)
	var avatar_node := PawnNode.new()
	avatar_node.work_poses = false
	avatar_node.setup(avatar, false, data, "ruth")
	entities.add_child(avatar_node)
	nodes[avatar] = avatar_node


func _front_door(house: Dictionary) -> Dictionary:
	for d in house.doors:
		if bool(d.exterior) and String(d.side) == String(house.front):
			return d
	return house.doors[0]


func _inner_door(house: Dictionary, room: int) -> Dictionary:
	for d in house.doors:
		if bool(d.exterior):
			continue
		for t in d.tiles:
			for off in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				if TownGen.room_at(town, (t + off).x, (t + off).y) == room:
					return d
	return {}


func _centre(d: Dictionary) -> Vector2:
	var s := Vector2.ZERO
	for t in d.tiles:
		s += Vector2(t) + Vector2(0.5, 0.5)
	return s / float(d.tiles.size())


## A bed, a stash, a radio and a bench in the rooms of the house, and its containers looted.
func _make_base(house: Dictionary) -> void:
	var rooms: Array = house.rooms
	var kinds := ["bed", "stash", "radio", "bench"]
	for i in kinds.size():
		var rm: Dictionary = town.rooms[int(rooms[i % rooms.size()])]
		var rr := Rect2(rm.rect)
		var kind: String = kinds[i]
		var size := Vector2(1, 2) if kind == "bed" else (Vector2(2, 1) if kind == "bench" else Vector2(1, 1))
		var corner := rr.end - size * 0.5 - (Vector2(0.0, 0.0) if i < 4 else Vector2.ZERO)
		var pos := rr.position + size * 0.5 if i % 2 == 0 else corner
		base.list.append({"id": kind, "kind": kind, "pos": pos, "room": int(rooms[i % rooms.size()]), "face": "S"})
	for cid in house.containers:
		looted.ids[String(cid)] = true


## The waypoints of the tour: out in the street, in at the front door, to the middle of the start room, through the door of that room and on into the next one.
func _make_tour(house: Dictionary, start: Dictionary) -> void:
	var d := _front_door(house)
	var out := {"N": Vector2(0, -1), "S": Vector2(0, 1), "W": Vector2(-1, 0), "E": Vector2(1, 0)}[String(d.side)] as Vector2
	var c := _centre(d)
	clearing.revealed.clear()
	_tour = [c + out * 3.0, c + out * 0.3, c - out * 1.5, Vector2(start.pos)]
	var inner := _inner_door(house, int(start.room))
	if not inner.is_empty():
		var ic := _centre(inner)
		var beyond := ic
		for t in inner.tiles:
			for off in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var nb: Vector2i = t + off
				var rr := TownGen.room_at(town, nb.x, nb.y)
				if rr >= 0 and rr != int(start.room):
					beyond = Vector2(nb) + Vector2(0.5, 0.5)
		_tour.append(ic)
		_tour.append(beyond)
	avatar.x = _tour[0].x
	avatar.y = _tour[0].y


func _tour_step(dt: float) -> void:
	if _tour_i >= _tour.size():
		print("TOUR DONE after %d frames" % frames)
		quit()
		return
	var goal: Vector2 = _tour[_tour_i]
	var at := Vector2(avatar.x, avatar.y)
	var to := goal - at
	if to.length() < 0.15:
		_tour_i += 1
		return
	at += to.normalized() * minf(to.length(), 3.2 * dt)
	avatar.x = at.x
	avatar.y = at.y
	var r := TownGen.room_at(town, at.x, at.y)
	if r >= 0:
		clearing.reveal(r)
	# a reveal through a door, as the clearing module does it: the room on the other side of a doorway the avatar is on
	if hv.avatar_house >= 0 and r < 0:
		for off in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
			var rr := TownGen.room_at(town, at.x + off.x, at.y + off.y)
			if rr >= 0 and clearing.reveal(rr):
				hv.on_event({"type": "room_revealed", "room": rr, "house": hv.avatar_house})
	var line := "house %d room %d roof %.2f veils %d nodes %d" % [hv.avatar_house, hv.avatar_room, hv.roof_alpha(int(town.start.house)), hv.veil_count(), hv.node_count()]
	var key := "%d/%d/%.0f/%d" % [hv.avatar_house, hv.avatar_room, hv.roof_alpha(int(town.start.house)) * 4.0, hv.veil_count()]
	var opens := 0
	for hd in town.houses:
		if int(hd.id) != int(town.start.house):
			continue
		for i in hd.doors.size():
			var dn = hv.door_node(int(hd.id), i)
			if dn != null and dn.open_target:
				opens += 1
	key += "/%d" % opens
	if key != _last.get("key", ""):
		_last["key"] = key
		print("t %.2f avatar (%.1f, %.1f) %s doors open %d" % [float(frames) / 60.0, at.x, at.y, line, opens])


func _report(house: Dictionary) -> void:
	var lines: Array = ["house %d (%s) rect %s front %s" % [house.id, house.kind, str(house.rect), house.front]]
	for r in house.rooms:
		lines.append("  room %d %s %s revealed %s" % [r, town.rooms[r].name, str(town.rooms[r].rect), str(clearing.is_revealed(int(r)))])
	for d in house.doors:
		lines.append("  door %s ext %s side %s" % [str(d.tiles), str(d.exterior), str(d.side)])
	for cid in house.containers:
		lines.append("  container " + str(sim.houses.container(String(cid))))
	for z in sim.zombies:
		lines.append("  dead at (%.1f, %.1f) room %d" % [z.x, z.y, sim.houses.room_at(z.x, z.y)])
	print("\n".join(lines))


func _tick() -> bool:
	var dt := 1.0 / 60.0
	frames += 1
	var vp := root.get_visible_rect().size
	var view := Rect2(cam_at - vp / 2.0 / zoom_px, vp / zoom_px)
	world.show_chunks(view.grow(2.0))
	hv.on_sync_views(view)
	props.on_sync_views(view)
	hv.on_frame(dt)
	props.on_frame(dt)
	if args.has("tour"):
		_tour_step(dt)
	if args.has("reveal-late") and frames == int(args.get("reveal-frame", "40")):
		for rr in String(args["reveal-late"]).split(","):
			clearing.reveal(int(rr))
			hv.on_event({"type": "room_revealed", "room": int(rr), "house": hv.avatar_house})
	var alpha := 1.0
	for z in sim.zombies:
		if not nodes.has(z):
			var n := PawnNode.new()
			n.work_poses = false
			n.setup(z, true, data, "z%d" % z.look_index)
			entities.add_child(n)
			nodes[z] = n
	for e in nodes:
		var n2 = nodes[e]
		n2.visible = hv.pawn_visible(e)
		if n2.visible:
			n2.sync(true, frames, alpha)
	if args.has("shot") and frames >= int(args.get("frames", "45")):
		var img := root.get_texture().get_image()
		img.save_png(String(args.shot))
		print("shot saved ", String(args.shot), " ", img.get_size(), " nodes in the house view: ", hv.node_count(), " roof alphas: ", _roof_alphas())
		quit()
	return false


func _roof_alphas() -> String:
	var out: Array = []
	for hd in town.houses:
		var a: float = hv.roof_alpha(int(hd.id))
		if a < 0.99:
			out.append("%d:%.2f" % [int(hd.id), a])
	return str(out)
