## The base's little life (round 24, "something is happening in the base"): the manager of the small things that make the yard look lived in
## though the crew is only a few people. It makes them, gives them the time, the wind and the rules' events, hides the ones that are off the
## screen, and lets a flag turn them all off. None of it is a rule of the game: it is all decoration, it moves nobody and shuts no ground (the
## walking grids are the map's own), and it reads the rules only for the weather, the hour, the people's work and the events they raise.
##
##   scripts/render/flag_node.gd     two flags on the lookout towers (the wind, harder in rain)
##   scripts/render/mast_node.gd     the radio mast on the school: a blinking red lamp, a dish that turns, aerials that sway
##   scripts/render/bell_node.gd     the school bell on its frame by the gate: swings and rings at the dusk bell
##   scripts/render/laundry_node.gd  washing on a line in the quiet south-east of the yard
##   scripts/render/dog_node.gd      a stray dog that trots about by day and sleeps by a fire at night
##   scripts/render/birds_node.gd    pigeons on the walls, flushed by a shot or the dead's groans, home at dusk
##   scripts/render/litter_node.gd   leaves and paper blown across the yard (a MultiMesh moved by a shader)
##   scripts/render/ripples_node.gd  puddle ripples while it rains (the same)
##   scripts/render/chat_node.gd     speech-bubble dots over two friends who stand together with nothing to do
##   and the lanterns' flicker at dusk (scripts/render/lighting.gd, `lamp_flicker`) and the mast's red halo at night (the glow node's `extras`).
##
## COST. Everything is a baked mesh moved by a shader (a vertex shader from a time and a wind: the flags, the washing, the mast, the bell, the
## dog, the birds' wings, the chat bubbles' dots) or a MultiMesh moved by a shader (the leaves, the ripples, the seven birds): one draw call each, no
## CPU work to move them, and a part that is off the screen is hidden (`update` hides a part whose `bounds()` the view does not touch). The
## wind, the rain and the clock are three numbers a frame, the people are looked at five times a second, the dog's paths are checked against the
## walking grid every five. Nothing is allocated in a frame. Measured in a real window (tools/life_bench.gd: the life on and off in blocks of
## frames under the same smoke): about 4 draw calls more than the 575 to 625 the yard already costs, and no measurable script time (an `update`
## is about 0.02 ms).
##
## TIME. The parts run on `t`, the real seconds scaled by the game's pace (paused: still; 3x: three times as fast, like the flames). With
## "reduce motion" (Settings) the flags and the washing hang, the mast does not turn and burns steady, the bell does not swing, the leaves,
## the ripples and the birds are not shown and the dog lies by its fire. `--calm` (a screenshot flag) or `enabled = false` shows none of it.
##
## THE WIND. A slow base with gusts, `wind` 0.05 to 1.4: stronger in rain (the rules' weather `sim.weather`: "rain", or "storm" if a card ever
## sets it) and a little less in fog; `drift` is how far it has carried the leaves.
extends Node2D

const Prefs := preload("res://scripts/prefs.gd")
const Kit := preload("res://scripts/render/life_kit.gd")
const FlagNode := preload("res://scripts/render/flag_node.gd")
const MastNode := preload("res://scripts/render/mast_node.gd")
const BellNode := preload("res://scripts/render/bell_node.gd")
const LaundryNode := preload("res://scripts/render/laundry_node.gd")
const DogNode := preload("res://scripts/render/dog_node.gd")
const BirdsNode := preload("res://scripts/render/birds_node.gd")
const LitterNode := preload("res://scripts/render/litter_node.gd")
const RipplesNode := preload("res://scripts/render/ripples_node.gd")
const ChatNode := preload("res://scripts/render/chat_node.gd")

const TILE := 64.0
## Where things stand (tiles). The flags: the east side of each lookout tower (the people stand at the towers' middles). The mast: the
## north brick edge of the school over the radio desk. The bell: against the north wall just east of the gate's apron. The washing: the quiet
## south-east of the yard, clear of the benches, the posts and the garden.
const FLAG_AT := [Vector2(20.15, 16.2), Vector2(66.7, 16.3)]
const MAST_AT := Vector2(62.7, 44.55)
const BELL_AT := Vector2(43.2, 22.6)
const LAUNDRY_AT := Vector2(52.3, 41.9)
## The wind: the base, how much a gust adds, and what the weather adds.
const WIND_BASE := 0.28
const WIND_RAIN := 0.55
const WIND_FOG := -0.1
const SLOW_S := 0.2

var sim
## Whether any of it is shown (`--calm` turns it off).
var enabled := true
## The animation clock (seconds at the game's pace), the wind (0.05 to 1.4), what the wind has carried the leaves, and how wet it is (0 to 1).
var t := 0.0
var wind := WIND_BASE
var drift := 0.0
var rain := 0.0
var wind_goal := WIND_BASE
var rain_goal := 0.0
## The view in tiles (main.gd gives it every frame) and whether the parts that move are to move (not "reduce motion").
var view := Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
var animate := true
var flags: Array = []
var mast
var bell
var laundry
var dog
var birds
var litter
var ripples
var chat
## Every part with a place (for the culling, and the tests): [node, ...].
var parts: Array = []
var _world
var _rewire_in := 0.0
var _flag_mat: ShaderMaterial
var _cloth_mat: ShaderMaterial
var _slow := 0.0
var _chat_look := 0.0
var _day := true


## `rules` is the sim, `world` the world node (its walking grid for the dog's paths), `tall` the y-sorted node the people stand in (the dog does).
func setup(rules, world = null, tall: Node2D = null) -> void:
	sim = rules
	name = "BaseLife"
	_flag_mat = Kit.material(Kit.FLAG_SHADER)
	_cloth_mat = Kit.material(Kit.CLOTH_SHADER)
	for at in FLAG_AT:
		var f := FlagNode.new()
		f.setup(at, _flag_mat)
		add_child(f)
		flags.append(f)
		parts.append(f)
	mast = MastNode.new()
	mast.setup(MAST_AT)
	add_child(mast)
	parts.append(mast)
	bell = BellNode.new()
	bell.setup(BELL_AT)
	add_child(bell)
	parts.append(bell)
	laundry = LaundryNode.new()
	laundry.setup(LAUNDRY_AT, _cloth_mat)
	add_child(laundry)
	parts.append(laundry)
	dog = DogNode.new()
	var solid := PackedByteArray()
	var w := 0
	if world != null and world.get("solid_p") != null:
		solid = world.solid_p
		w = int(world.W)
	_world = world
	dog.setup(solid, w, 7)
	(tall if tall != null else self).add_child(dog)
	parts.append(dog)
	birds = BirdsNode.new()
	birds.setup(11)
	add_child(birds)
	litter = LitterNode.new()
	litter.setup(5)
	add_child(litter)
	parts.append(litter)
	ripples = RipplesNode.new()
	ripples.setup()
	ripples.visible = false
	add_child(ripples)
	chat = ChatNode.new()
	chat.setup(rules)
	add_child(chat)
	_cull()


## Turns the whole thing on or off (`--calm`).
func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	if dog != null and not on:
		dog.visible = false    # (it stands in the people's node, not in this one; `update` shows it again when it is on)


## The weather as the wind sees it: how strong the wind is aiming to be (`wind_goal`) and how wet it is (`rain_goal`, 0 or 1). No allocation.
func aim_weather() -> void:
	var weather := String(sim.weather) if sim != null else "clear"
	rain_goal = 1.0 if (weather == "rain" or weather == "storm") else 0.0
	var target := WIND_BASE + 0.2 * sin(t * 0.13) + 0.13 * sin(t * 0.41 + 1.3) + 0.07 * sin(t * 1.1 + 4.0)
	target += WIND_RAIN * rain_goal + (WIND_FOG if weather == "fog" else 0.0) + (0.25 if weather == "storm" else 0.0)
	wind_goal = clampf(target, 0.05, 1.4)


## Called every frame by main.gd: `real_dt` the frame's seconds, `speed` the game's pace (0 paused to 3), `view_tiles` what the camera sees (tiles).
func update(real_dt: float, speed: int, view_tiles: Rect2) -> void:
	if not enabled:
		return
	view = view_tiles
	var dt := real_dt * float(clampi(speed, 0, 3))
	_slow += real_dt
	if _slow >= SLOW_S:
		_slow = 0.0
		animate = not Prefs.on("ui", "reduce_motion")
		_day = Kit.is_day(float(sim.hour), float(sim.seasons.dusk_hour()))
		if birds != null and animate:
			birds.shoo(sim.people)
	if animate:
		t += dt
		aim_weather()
		wind = lerpf(wind, wind_goal, minf(1.0, dt * 0.8))
		rain = lerpf(rain, rain_goal, minf(1.0, dt * 0.6))
		drift += (0.35 + 1.4 * wind) * dt
	else:
		wind = 0.0
		rain = 0.0
	# the dog's paths are checked against the walking grid again every few seconds (a building may have gone up on one)
	_rewire_in += real_dt
	if _rewire_in >= 5.0:
		_rewire_in = 0.0
		if _world != null and _world.get("solid_p") != null:
			dog.rewire(_world.solid_p, int(_world.W))
	_chat_look += real_dt
	if _chat_look >= 0.5:
		_chat_look = 0.0
		chat.look()
	_cull()
	var shown := view_tiles
	# the shaders (two numbers for each cloth, one for each MultiMesh): only while something that uses them is in view
	_flag_mat.set_shader_parameter("t", t)
	_flag_mat.set_shader_parameter("wind", wind)
	_cloth_mat.set_shader_parameter("t", t)
	_cloth_mat.set_shader_parameter("wind", wind)
	if litter.visible:
		litter.apply(drift, rain)
	if ripples.visible:
		ripples.apply(t, rain)
	if mast.visible:
		mast.tick(dt, t, wind, animate)
	if bell.visible:
		bell.tick(dt, t, wind, animate)
	dog.tick(dt, t, _day, animate)
	birds.view = shown
	birds.tick(dt, t, _day, animate)
	chat.view = shown
	chat.tick(dt, t, animate)


## Shows the parts that the view touches and hides the others (a hidden node draws nothing and costs nothing).
func _cull() -> void:
	for p in parts:
		p.visible = view.intersects(p.bounds())
	if not animate:
		litter.visible = false
	if rain < 0.02 or not animate or not view.intersects(ripples.bounds()):
		ripples.visible = false
	else:
		ripples.visible = true


## The rules' events (main.gd gives each one as it handles them): the bells swing the bell, the noises startle the birds.
func on_event(e: Dictionary) -> void:
	if not enabled:
		return
	bell.on_event(e)
	birds.on_event(e)


## The mast's lamp in the glow layer (main.gd registers this with the glow node's `extras`).
func glow_paint(ci: CanvasItem, radial: Texture2D, dark: float) -> void:
	if enabled:
		mast.glow_paint(ci, radial, dark)


## How many parts are shown now (for the tests).
func shown_count() -> int:
	var n := 0
	for p in parts:
		if p.visible:
			n += 1
	return n
