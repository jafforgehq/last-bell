## The facade of a town run (feature/town-core, WP1): `Main` holds it as `town` (null in every other game) and asks it at nine fixed places, one line each, so that the packages that
## draw and listen in the town (the roofs and the rooms, the survivors, the HUD of the new loop, the sleep fade, the sounds) never edit `main.gd`:
##
##   `_ready`            `town = TownGame.make(self); town.on_ready(self)`      after the HUD, the sound and the menus exist
##   `_process`          `town.on_frame(dt)`                                     after `_sync_views`
##   `_sync_views`       `town.pawn_visible(entity)` for each pawn, `town.on_sync_views(view)` once (view: the camera's Rect2 in tiles, grown)
##   `_handle_events`    `town.on_event(e)` for each event of the step
##   `_music_context`    `ctx = town.music_context(ctx)` (WP7's `indoors` and `fortress`; main.gd has no such function in the foundation's base: it is added where the audio branch puts it)
##   `avatar_hands_off`  `or town.modal()`
##   `_unhandled_input`  `if town.on_key(ev): return`
##   `_min_zoom`, `_clamp_camera`  `town.min_zoom(vp, world)`, `town.clamp_camera(main)`
##
## THE VIEW PARTS. `VIEW_PARTS` maps a name to the file of a part (any object with any of the methods below, a Node or not); a file that does not exist is skipped. A part's methods are
## all optional:
##   on_ready(main)                      once, when the facade is made (a part that draws adds its nodes to `main.world` here)
##   on_frame(dt: float)                 every frame, after the views are synced
##   on_sync_views(view: Rect2)          every frame, once the pawns have been made, moved and shown or hidden; view in tiles
##   pawn_visible(entity) -> bool        false hides that pawn (a dead one in a room the avatar has not looked into); asked of every pawn, so keep it cheap
##   on_event(e: Dictionary)             every event of the rules' step (plan 2.4)
##   music_context(ctx: Dictionary) -> Dictionary
##   modal() -> bool                     true while the part holds the avatar's hands (a card is up)
##   on_key(ev: InputEvent) -> bool      true: the part used the key, nothing else sees it
extends RefCounted

const VIEW_PARTS := {
	"house_view": "res://scripts/render/house_view.gd",
	"base_props_view": "res://scripts/render/base_props_view.gd",
	"candidate_marks": "res://scripts/render/candidate_marks.gd",
	"perimeter_view": "res://scripts/render/perimeter_view.gd",
	"bystander_view": "res://scripts/render/bystander_view.gd",
	"rescue_card": "res://scripts/ui/rescue_card.gd",
	"town_hud": "res://scripts/ui/town_hud.gd",
	"sleep_fade": "res://scripts/ui/sleep_fade.gd",
	"town_audio": "res://scripts/audio/town_audio.gd",
	"hurt_pulse": "res://scripts/ui/hurt_pulse.gd",
	"crew_marks": "res://scripts/ui/crew_marks.gd",
	"minimap": "res://scripts/ui/minimap.gd",
}
## The parts of the title screen's town (scripts/town/title_scene.gd): the roofs and nothing else (no card, no HUD, no sleep, no town sounds: the title has its own).
const TITLE_PARTS := ["house_view"]
## The foundation's own roofs, drawn while no `house_view` part exists (it is the working fallback: one roof for each house, fading when the avatar is inside).
const FALLBACK_ROOFS := "res://scripts/town/town_roofs.gd"
const TownPerf := preload("res://scripts/town/town_perf.gd")
## The furthest zoom out in pixels to the tile whatever the window (the area bound of `TownPerf.min_zoom` is what normally holds).
const MIN_ZOOM := 5.0
## How many pawn nodes a frame may make (`Main._sync_views`).
const NODES_PER_FRAME := TownPerf.NODES_PER_FRAME
## How many chunks of ground paint may be drawn for the first time in one frame (a chunk is about 4 ms of GDScript on the desktop the first time).
const CHUNKS_PER_FRAME := 1

var main
## The town is the title screen's (`Main.title_mode`): only the `TITLE_PARTS` are made, and the fresh run is not held for a first key.
var title := false
var parts: Array = []
## The parts by name, for the ones that want to find each other (`town.part("house_view")`).
var by_name := {}
var _roofs
var _avatar_house := -1
## The adaptive cap on the awake dead (scripts/town/town_perf.gd).
var perf
var _chunk_drawn := {}
## 0: not looked at yet, 1: the fresh run is held for the first input, 2: done (see _start_hold).
var _hold_state := 0


## The facade for `main`'s run (null when the run is not a town's: its sim has no `houses`).
static func make(main_node):
	if main_node.sim.get("houses") == null:
		return null
	var t = (load("res://scripts/town/town_game.gd") as GDScript).new()
	t.main = main_node
	t.title = bool(main_node.get("title_mode"))
	return t


func on_ready(main_node) -> void:
	main = main_node
	parts.clear()
	by_name.clear()
	for name in VIEW_PARTS:
		var path: String = VIEW_PARTS[name]
		if not ResourceLoader.exists(path) or (title and not TITLE_PARTS.has(name)):
			continue
		var part = (load(path) as GDScript).new()
		parts.append(part)
		by_name[name] = part
	if not by_name.has("house_view") and ResourceLoader.exists(FALLBACK_ROOFS):
		_roofs = (load(FALLBACK_ROOFS) as GDScript).new()
		_roofs.name = "Roofs"
		main.world.add_child(_roofs)
		_roofs.setup(main.sim.town_data, main.data, "house")
	for part in parts:
		if part.has_method("on_ready"):
			part.on_ready(main)
	perf = TownPerf.new()
	perf.setup(main.sim)


## Once, as the camera is first put (main.gd `_ready`, after the HUD): the parts that care say where it looks and how far it sees (`on_opening_view(main)`: the town's HUD part).
func opening_view() -> void:
	for part in parts:
		if part.has_method("on_opening_view"):
			part.on_opening_view(main)


func part(name: String):
	return by_name.get(name)


## A fresh town run waits for the player: the game stays paused (with a line saying so) until the first move, click or key, so that nothing bites Ruth while the
## town loads and the first card is being read. A load, a staged run (`--stage=`) and a screenshot run are never held.
func _start_hold() -> void:
	if _hold_state == 2 or title:
		return
	if _hold_state == 0:
		_hold_state = 2
		# (fresh: the first morning, still at the start of it: the loading card runs a few steps of the sim, so a count of steps is no test)
		var fresh: bool = float(main.sim.hour) < 8.5 and main.shot_path == ""
		var scn = main.sim.get("scenario")
		var at_start: bool = scn != null and scn.has_method("stage") and ["arrive", "alone"].has(String(scn.stage()))
		if fresh and at_start:
			main.speed = 0
			main.hud.toast("Press W A S D to begin", "info")
			_hold_state = 1
		else:
			_intro()    # (a screenshot's run, or a staged one: no first key to wait for)
		return
	# held: the loading card puts the speed back to 1 when it goes, so the hold keeps it at 0 until the first key that moves her or a click; Space is the
	# player's own unpause (main's key handler does the toggle: the hold only lets go)
	var moved := false
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_E, KEY_R]:
		if Input.is_key_pressed(k):
			moved = true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		moved = true
	if Input.is_key_pressed(KEY_SPACE):
		_hold_state = 2
		return
	if moved:
		_hold_state = 2
		main.speed = 1
		_intro()
	elif main.speed != 0:
		main.speed = 0


## The opening words of a run that begins on the road in, as a banner: "The bell is ringing somewhere. Find shelter before dark." (the scenario says them once: `take_intro`).
func _intro() -> void:
	var scn = main.sim.get("scenario")
	if scn == null or not scn.has_method("take_intro") or main.hud == null:
		return
	var words: Array = scn.take_intro()
	if words.size() >= 2:
		main.hud.show_banner(String(words[0]), String(words[1]))


func on_frame(dt: float) -> void:
	_start_hold()
	if perf != null:
		perf.frame()
	if _roofs != null:
		var me = main.sim.avatar.player()
		_roofs.update(main.sim.houses.house_at(me.x, me.y) if me != null else -1, dt)
	for part in parts:
		if part.has_method("on_frame"):
			part.on_frame(dt)


func on_sync_views(view: Rect2) -> void:
	_show_chunks(view)
	for part in parts:
		if part.has_method("on_sync_views"):
			part.on_sync_views(view)


func pawn_visible(entity) -> bool:
	for part in parts:
		if part.has_method("pawn_visible") and not bool(part.pawn_visible(entity)):
			return false
	return true


func on_event(e: Dictionary) -> void:
	for part in parts:
		if part.has_method("on_event"):
			part.on_event(e)


func music_context(ctx: Dictionary) -> Dictionary:
	for part in parts:
		if part.has_method("music_context"):
			ctx = part.music_context(ctx)
	return ctx


func modal() -> bool:
	for part in parts:
		if part.has_method("modal") and bool(part.modal()):
			return true
	return false


func on_key(ev: InputEvent) -> bool:
	for part in parts:
		if part.has_method("on_key") and bool(part.on_key(ev)):
			return true
	return false


## The camera may zoom out further than the school's yard allows, but not to the whole town (192 tiles across: 2,100 draw calls and 500 roofs on a desktop, measured with
## tools/town_bench.gd --what=game): it never shows more of the town than `TownPerf.max_view_tiles()` (about 24 houses); the district map (M) is the way to see it all.
func min_zoom(vp: Vector2, world) -> float:
	var whole := minf(vp.x / (float(world.W) + 2.0), vp.y / (float(world.H) + 2.0))
	return maxf(MIN_ZOOM, maxf(whole, TownPerf.min_zoom(vp)))


## The camera's bounds in a town: the map's own (`Main._clamp_camera` has already done them); a part may add to them here later.
func clamp_camera(_main) -> void:
	pass


## The ground paint (curbs, lane dashes) of the chunks in view, the new ones one at a time (`CHUNKS_PER_FRAME`) so that crossing the town is not a hitch every 32 tiles: a chunk is
## drawn when it is first shown and kept. The standalone scene did this each frame with `world.show_chunks`; the real game had no caller.
func _show_chunks(view: Rect2) -> void:
	var world = main.get("world")
	if world == null or not (world.get("chunks") is Array):
		return
	var fresh := 0
	var i := 0
	for c in world.chunks:
		var seen: bool = view.intersects(c.rect)
		var node = c.node
		if seen and not node.visible:
			if not _chunk_drawn.has(i):
				if fresh >= CHUNKS_PER_FRAME:
					i += 1
					continue
				fresh += 1
				_chunk_drawn[i] = true
			node.visible = true
		elif not seen and node.visible:
			node.visible = false
		i += 1
