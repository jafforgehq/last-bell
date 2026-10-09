## The shimmer of a container that has not been searched (One House, LOOT): a VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`,
## `on_event(e)`). It reads the rules (`sim.houses`, `sim.search.is_looted`, `sim.clearing.is_revealed`, `sim.uses`) and writes nothing in them.
##
## WHAT SHIMMERS. While the avatar is inside a house, every container of that house that is NOT searched and sits in a room she has looked into (the dark veil over the other rooms hides
## the rest): a faint rim of light round the furniture that breathes, and a thin glint that crosses it every few seconds. A container in a room that has dead in it shimmers in a grey red, with no
## glint (it cannot be searched as a room yet: the dead are in the way). A container that is looted does not shimmer (its tick is the mark: scripts/ui/search_marks.gd), nor the one she has her
## hands on. A container that is not in a room at all shimmers within OUTDOOR_R (10) tiles of her: SCAV3, the parked cars and wrecks of the street (scripts/town/car_loot.gd, `sim.houses.cars`;
## every unsearched one, gold, the whole rim of its footprint: most are empty, and the colour never says), while she is outside every house.
## THE COLOUR IS ALWAYS GOLD (or the grey red). The loot is rolled when the town is made; to colour a container by what is in it would tell the player the contents before the search.
## REDUCE FLASHES / REDUCE MOTION (`Access.calm_flashes()`): a still rim, no glint, no breath. COLOUR-BLIND MARKERS (`Access.markers()`): corner brackets on the ones that can be searched, a
## dashed rim on the others, so that the colour is never the whole message.
## COST. One MultiMeshInstance2D in the world (z 4, over the furniture, under the people), at most MAX (24) quads, ONE draw call for all of them; the list is made again four times a second
## (or when something is searched) and the shader's clock is the one thing that changes in a frame. `--shimmer-cost` prints the part's CPU time per frame and the frame's draw calls near
## the shot; `--noloot` leaves the part out (the picture the game had before it); `--shimmer-stress=N` fills N quads round the avatar (the cost of the whole pool).
extends RefCounted

const Access := preload("res://scripts/access.gd")
const TownArt := preload("res://scripts/town/town_art.gd")
const SHADER := preload("res://scripts/render/loot_shimmer.gdshader")

const TILE_PX := 64.0
const MAX := 24
const EVERY := 0.25
const OUTDOOR_R := 10.0
## How far the quad goes past the furniture's footprint, tiles.
const PAD := 0.12
## The shader's clock runs this much slower than the real one while it is not in view of anything (it does not: kept at one).
const CLOCK_K := 1.0

var main
var sim
var node: MultiMeshInstance2D
var mm: MultiMesh
var mat: ShaderMaterial
## The quads shown now: [{"id", "at": Vector2 (tiles), "size": Vector2 (tiles), "blocked": bool}].
var shown: Array = []
var cost_us := 0.0
var cost_frames := 0

var _t := 0.0
var _clock := 0.0
var _size_of := {}
var _outdoor: Array = []
var _outdoor_read := false
var _off := false
var _cost := false
var _cost_done := false
var _stress := 0
var _last_calm := -1
var _last_cb := -1
var _last_gain := -1.0


func on_ready(main_node) -> void:
	main = main_node
	sim = main.get("sim")
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a == "--noloot":
			_off = true
		elif a == "--shimmer-cost":
			_cost = true
		elif a.begins_with("--shimmer-stress="):
			_stress = clampi(int(a.trim_prefix("--shimmer-stress=")), 0, MAX)
	var world = main.get("world")
	if _off or world == null or sim == null or sim.get("houses") == null:
		return
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	node = MultiMeshInstance2D.new()
	node.name = "LootShimmer"
	node.multimesh = mm
	node.material = mat
	node.z_index = 4
	node.visible = false
	world.add_child(node)


func _me():
	if sim == null or sim.get("avatar") == null or String(sim.get("player_id")) == "":
		return null
	return sim.avatar.player()


# ----------------------------------------------------------------------------- frames --

func on_frame(dt: float) -> void:
	if node == null:
		if _cost:
			cost_frames += 1    # (`--noloot --shimmer-cost`: the draw calls of the picture without the part)
			_cost_report()
		return
	var t0 := Time.get_ticks_usec() if _cost else 0
	_t -= dt
	if _t <= 0.0:
		_t = EVERY
		refresh()
	if not shown.is_empty():
		_style(dt)
	if _cost:
		cost_us += float(Time.get_ticks_usec() - t0)
		cost_frames += 1
		_cost_report()


func on_event(e: Dictionary) -> void:
	var kind := String(e.get("type", ""))
	if kind == "searched" or kind == "room_clear" or kind == "room_revealed" or kind == "entered" or kind == "left":
		_t = 0.0    # (the list is made again at the next frame)


## The shader's clock and switches. The clock stands still under Reduce flashes (the shader draws a still rim), and the night's gain is read from the sky.
func _style(dt: float) -> void:
	var calm := 1 if Access.calm_flashes() else 0
	var cb := 1 if Access.markers() else 0
	if calm == 0:
		_clock += dt * CLOCK_K
		mat.set_shader_parameter("t", _clock)
	if calm != _last_calm:
		_last_calm = calm
		mat.set_shader_parameter("calm", float(calm))
	if cb != _last_cb:
		_last_cb = cb
		mat.set_shader_parameter("cb", float(cb))
	var lighting = main.get("lighting")
	var dark := float(lighting.dark) if lighting != null and lighting.get("dark") != null else 0.0
	# (the shimmer is in the world, which the sky multiplies: with the dark look the day multiplies it too, so the gain follows the light the world really has)
	var amb := 1.0 - dark
	if lighting != null and lighting.get("grade") != null and lighting.modulate_node != null:
		var cm: Color = lighting.modulate_node.color
		amb = (cm.r + cm.g + cm.b) / 3.0
	var gain := clampf(1.0 / maxf(amb, 0.2), 1.0, 2.6)
	if absf(gain - _last_gain) > 0.02:
		_last_gain = gain
		mat.set_shader_parameter("gain", gain)


# ------------------------------------------------------------------------------- list --

## The footprint of a container's furniture, in tiles (the picture's size, as scripts/render/base_props_view.gd draws the open one).
## INV-CORE: a container with nothing worth coming back for (searched, and no items left in it); items she left keep it shimmering.
func _spent(search, id: String) -> bool:
	return search.is_spent(id) if search.has_method("is_spent") else search.is_looted(id)


func _size(kind: String) -> Vector2:
	if not _size_of.has(kind):
		var d: Dictionary = TownArt.prop(kind, "", "s")
		_size_of[kind] = Vector2(d.get("size", Vector2.ONE))
	return _size_of[kind]


## Makes the list again from the rules and puts it in the quads. Returns the number shown.
func refresh() -> int:
	var items: Array = []
	var me = _me()
	if me != null and not me.dead and not me.turned and me.away == null:
		_collect(me, items)
	if _stress > 0 and me != null:
		_stress_fill(me, items)
	if items.size() > MAX:
		var here := Vector2(me.x, me.y)
		items.sort_custom(func(a, b): return Vector2(a.at).distance_squared_to(here) < Vector2(b.at).distance_squared_to(here))
		items.resize(MAX)
	shown = items
	var n := items.size()
	for i in n:
		var it: Dictionary = items[i]
		var sz: Vector2 = (Vector2(it.size) + Vector2(PAD, PAD) * 2.0) * TILE_PX
		mm.set_instance_transform_2d(i, Transform2D(0.0, sz, 0.0, Vector2(it.at) * TILE_PX))
		var ph := float(hash(String(it.id)) & 1023) / 1024.0
		mm.set_instance_custom_data(i, Color(ph, 1.0 if bool(it.blocked) else 0.0, sz.x, sz.y))
	mm.visible_instance_count = n
	node.visible = n > 0
	return n


func _collect(me, items: Array) -> void:
	var hs = sim.houses
	var search = sim.get("search")
	var clearing = sim.get("clearing")
	var uses = sim.get("uses")
	if search == null:
		return
	var h: int = hs.house_at(me.x, me.y)
	var here := Vector2(me.x, me.y)
	var dead := {}
	if h >= 0:
		for c in hs.containers_of(h):
			var id := String(c.id)
			if _spent(search, id):
				continue
			var room := int(c.get("room", -1))
			if room >= 0:
				if clearing != null and not clearing.is_revealed(room):
					continue
			elif Vector2(c.at).distance_to(here) > OUTDOOR_R:
				continue
			if uses != null and uses.in_session("container", id):
				continue
			if room >= 0 and not dead.has(room):
				dead[room] = hs.dead_in_room(room) > 0
			items.append({"id": id, "at": Vector2(c.at), "size": _size(String(c.kind)), "blocked": room >= 0 and bool(dead[room])})
	# containers that are in no room (a yard: the generator puts none outside the walls) and the cars and wrecks of the street (SCAV3: scripts/town/car_loot.gd, only while she is outside every house)
	# within OUTDOOR_R of her
	if not _outdoor_read:
		_outdoor_read = true
		var town = hs.get("town")
		if town is Dictionary:
			for c in town.get("containers", []):
				if int(c.get("room", -1)) < 0:
					_outdoor.append(c)
		var cars = hs.get("cars")
		if cars is Array:
			_outdoor.append_array(cars)
	for c in _outdoor:
		var id2 := String(c.id)
		var is_car := bool(c.get("car", false))
		if _spent(search, id2) or (is_car and h >= 0) or Vector2(c.at).distance_to(here) > OUTDOOR_R:
			continue
		if uses != null and uses.in_session("container", id2):
			continue
		items.append({"id": id2, "at": Vector2(c.at), "size": Vector2(Rect2i(c.rect).size) if is_car else _size(String(c.kind)), "blocked": false})


## `--shimmer-stress=N`: N quads in a ring round her (the pool full), for the cost.
func _stress_fill(me, items: Array) -> void:
	var have := items.size()
	for i in range(have, _stress):
		var ang := TAU * float(i) / float(_stress)
		items.append({"id": "stress%d" % i, "at": Vector2(me.x, me.y) + Vector2.from_angle(ang) * (1.4 + 0.12 * float(i)), "size": Vector2(1.0, 0.6), "blocked": i % 5 == 0})


# -------------------------------------------------------------------------------- cost --

## `--shimmer-cost`: the CPU time of this part per frame and the draw calls of the frame, printed two frames before the shot (frames 60 on are measured).
func _cost_report() -> void:
	if _cost_done or String(main.get("shot_path")) == "":
		return
	var ui = main.town.part("room_search_ui") if main.get("town") != null else null
	if int(main.get("frame_count")) == maxi(int(main.get("shot_frames")) - 60, 60):
		cost_us = 0.0
		cost_frames = 0
		if ui != null:
			ui.cost_us = 0.0
			ui.cost_frames = 0
	var left := int(main.get("shot_frames")) - int(main.get("frame_count"))
	if left <= 2 and cost_frames > 0:
		_cost_done = true
		var calls := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		var ui_us: float = float(ui.cost_us) / maxf(float(ui.cost_frames), 1.0) if ui != null else 0.0
		print("loot cost per frame: shimmer %.1f us, room_search_ui %.1f us (%d frames), quads shown %d, draw calls in the frame %d" % [cost_us / float(cost_frames), ui_us, cost_frames, shown.size(), calls])
