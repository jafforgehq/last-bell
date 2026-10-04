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
	"bystander_view": "res://scripts/render/bystander_view.gd",
	"rescue_card": "res://scripts/ui/rescue_card.gd",
	"town_hud": "res://scripts/ui/town_hud.gd",
	"sleep_fade": "res://scripts/ui/sleep_fade.gd",
	"town_audio": "res://scripts/audio/town_audio.gd",
}
## The foundation's own roofs, drawn while no `house_view` part exists (it is the working fallback: one roof for each house, fading when the avatar is inside).
const FALLBACK_ROOFS := "res://scripts/town/town_roofs.gd"
const MIN_ZOOM := 5.0

var main
var parts: Array = []
## The parts by name, for the ones that want to find each other (`town.part("house_view")`).
var by_name := {}
var _roofs
var _avatar_house := -1


## The facade for `main`'s run (null when the run is not a town's: its sim has no `houses`).
static func make(main_node):
	if main_node.sim.get("houses") == null:
		return null
	var t = (load("res://scripts/town/town_game.gd") as GDScript).new()
	t.main = main_node
	return t


func on_ready(main_node) -> void:
	main = main_node
	parts.clear()
	by_name.clear()
	for name in VIEW_PARTS:
		var path: String = VIEW_PARTS[name]
		if not ResourceLoader.exists(path):
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


## Once, as the camera is first put (main.gd `_ready`, after the HUD): the parts that care say where it looks and how far it sees (`on_opening_view(main)`: the town's HUD part).
func opening_view() -> void:
	for part in parts:
		if part.has_method("on_opening_view"):
			part.on_opening_view(main)


func part(name: String):
	return by_name.get(name)


func on_frame(dt: float) -> void:
	if _roofs != null:
		var me = main.sim.avatar.player()
		_roofs.update(main.sim.houses.house_at(me.x, me.y) if me != null else -1, dt)
	for part in parts:
		if part.has_method("on_frame"):
			part.on_frame(dt)


func on_sync_views(view: Rect2) -> void:
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


## The camera may zoom out further than the school's yard allows (the whole town is 192 tiles across): never below MIN_ZOOM pixels to the tile.
func min_zoom(vp: Vector2, world) -> float:
	return maxf(MIN_ZOOM, minf(vp.x / (float(world.W) + 2.0), vp.y / (float(world.H) + 2.0)))


## The camera's bounds in a town: the map's own (`Main._clamp_camera` has already done them); a part may add to them here later.
func clamp_camera(_main) -> void:
	pass
