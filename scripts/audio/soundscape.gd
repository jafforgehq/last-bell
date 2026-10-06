## The soundscape: everything the base sounds like apart from the guns and the music. A child of `Sound` (scripts/audio/sound.gd), which hands it
## the rules' events (`on_event`, from main.gd) and the ambience (`beds`); `attach` gives it the game for the camera, the people, the hour.
## Made by tools/make_bells.py, make_ambience.py and make_base_sounds.py.
##
##   THE BELL     the dusk bell is rung as FOUR tolls (about two seconds apart, each one of three strikes of the same bell, a little softer
##                at the end: the bell swings for seven seconds in scripts/render/bell_node.gd), the call to arms is five quick strikes of a small
##                bell, the turn of a season a deep slow one, a building finished or someone arrived a small bright chime, and a bell heard on a
##                trip is the far one. They are plain (not positional) voices of their own on the SFX bus.
##   THE DEAD     a groan (`groan`) is one of eight, at a random pitch (a runner higher, one of the streets low and quiet), POSITIONAL: an
##                AudioStreamPlayer2D put where the groaner is, so it pans and fades with the distance; the plated brute roars (`roar`) instead,
##                and the music ducks. At most MAX_GROANS groans and at most MAX_VOICES voices of all the positional sounds sound at once: a
##                crowd at the wall is a handful of the nearest voices, not a hundred (the web build has one thread to mix them on).
##   THE BASE     footsteps of the avatar and the people near the camera, by what is under them (dirt and gravel, concrete, a wooden deck), rate
##                limited; a gate (the lever's clunk and chain, the slide, the clang at its stop) where the rules have one; a door as the avatar
##                goes through it; the hum of a generator and the crackle of a radio desk where the map has them, only while the camera is
##                near; the engine of a car on a trip. Nothing is known of a map: the doors, the generators and the radio desks are read from the
##                objects the map data lists (by kind), the surfaces from the terrain's names, the gate from `sim.gate` if there is one.
##   THE AIR      a night bed and rain on top of the wind, and now and then, a long way off on the Distant bus (a low-pass and a reverb): a crow
##                by day, a dog at dusk, a creak, the moan of the dead at night, a far gunshot with its echo. They come on timers drawn from
##                this node's own random generator, only when the game is running (not paused, not in a menu, not on the title).
##
## It uses a random generator of its own and reads the rules (never writes them): the golden tests' promise is that sound changes nothing.
extends Node

const Buses := preload("res://scripts/audio/buses.gd")
const Music := preload("res://scripts/audio/music.gd")
const GD := preload("res://scripts/game_data.gd")

const TILE := GD.TILE
const DIR := "res://assets/audio/"
## The most positional voices at once (groans, the roar, steps, the gate, doors, the far sounds), and of those the most of one kind.
const MAX_VOICES := 8
const KIND_CAP := {"groan": 5, "roar": 1, "step": 3, "gate": 2, "door": 1, "far": 2}
const BELL_VOICES := 4
## How often (seconds) the world is looked at (steps, doors, the beds that stand in a place, the timers).
const TICK := 0.1

## The files of each sound (names without the folder and the extension).
const BELLS := {
	"dusk": ["bell_0", "bell_dusk_1", "bell_dusk_2"],
	"deep": ["bell_deep"],
	"alarm": ["bell_alarm"],
	"chime": ["bell_chime_0", "bell_chime_1", "bell_chime_2"],
	"far": ["bell_far"],
}
const STEPS := {
	"dirt": ["step_dirt_0", "step_dirt_1", "step_dirt_2"],
	"concrete": ["step_concrete_0", "step_concrete_1", "step_concrete_2"],
	"wood": ["step_wood_0", "step_wood_1", "step_wood_2"],
}
const GATE_SOUNDS := {"lever": ["gate_lever_0"], "slide": ["gate_slide_0"], "clang": ["gate_clang_0"]}
const DOORS := {"open": ["door_open_0"], "close": ["door_close_0"], "hatch": ["hatch_0"]}
const FAR := {
	"crow": ["crow_0", "crow_1", "crow_2"],
	"dog": ["dog_far_0", "dog_far_1"],
	"creak": ["creak_0", "creak_1"],
	"moan": ["moan_far_0", "moan_far_1"],
	"shot": ["gunshot_far_0", "gunshot_far_1"],
}
const GROANS := ["groan_0", "groan_1", "groan_2", "groan_3", "groan_4", "groan_5", "groan_6", "groan_7"]
const ROARS := ["brute_roar_0", "brute_roar_1"]
const LOOPS := {"night_bed": "night_bed", "rain": "rain_loop", "generator": "generator_loop", "radio": "radio_loop"}
const ENGINE := {"loop": "car_engine_loop", "road": "car_road_loop"}

## Tolls of the dusk bell: seconds from the event, and how loud each is.
const DUSK_TOLLS := [[0.0, 1.0], [1.9, 0.9], [3.9, 0.85], [6.2, 0.7]]
## A stride (tiles) is one footstep; what a terrain's NAME says about its surface and about being indoors (the map data's terrainTypes: a name
## with one of these words in it); the pitch of each kind of groaner.
const STRIDE := 0.85
const DIRT_WORDS := ["GRASS", "SOIL", "DIRT", "YARD", "MUD", "GRAVEL", "SAND", "LAWN", "FIELD", "GARDEN", "LEAF", "FOREST"]
const WOOD_WORDS := ["WOOD", "PLANK", "DECK", "PARQUET", "BOARD"]
const INDOOR_WORDS := ["LINO", "TERRAZZO", "KITCHEN", "CARPET", "TILE", "PARQUET", "FLOOR", "RUG"]
const GROAN_PITCH := {"walker": 1.0, "runner": 1.22, "brute": 0.8}
## How far (tiles) a groan, a step, the roar, a place's hum carry.
const GROAN_REACH := 38.0
const STEP_REACH := 14.0
const ROAR_REACH := 52.0
const HUM_REACH := 11.0
## The kinds of map object that hum or crackle (objects of the map data, `kind`).
const GENERATOR_KIND := "generator"
const RADIO_KIND := "radiodesk"

var game
var sound
var streams := {}
var muted := false

## The positional voices: {"p": AudioStreamPlayer2D, "kind": String, "prio": float}.
var voices: Array = []
var bells: Array = []
var beds := {}
var bed_level := {"night_bed": 0.0, "rain": 0.0}
var engine_player: AudioStreamPlayer
var road_player: AudioStreamPlayer
## Counts for the tests and the report: what was played, what was dropped for the cap.
var played := {}
var dropped := 0

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _acc := 0.0
var _later: Array = []
var _last_roar := -100.0
var _last_groan := -1
var _last_bell := -1
var _last_pos := {}
var _stride := {}
var _step_clock := 0.0
var _doors: Array = []
var _generators: Array = []
var _radios: Array = []
var _surface_of := {}
var _indoor_ids := {}
var _far_timer := {}
var _engine_idle := 99.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Loads what is there (a file that is not imported is skipped, so a checkout that has not been imported plays on without it) and makes
## the voices. `sound_node` is the Sound that owns this.
func setup(sound_node) -> void:
	sound = sound_node
	_rng.randomize()
	_load_group("bell", BELLS)
	_load_group("step", STEPS)
	_load_group("gate", GATE_SOUNDS)
	_load_group("door", DOORS)
	_load_group("far", FAR)
	streams["groan"] = _load_list(GROANS)
	streams["roar"] = _load_list(ROARS)
	for i in MAX_VOICES:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.panning_strength = 0.9
		add_child(p)
		voices.append({"p": p, "kind": "", "prio": 0.0})
	for i in BELL_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		bells.append(p)
	for key in LOOPS:
		var list := _load_list([LOOPS[key]])
		if list.is_empty():
			continue
		var s: AudioStreamWAV = list[0]
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		var p: Node
		if key == "generator" or key == "radio":
			var p2 := AudioStreamPlayer2D.new()
			p2.bus = "Ambience"
			p2.max_distance = HUM_REACH * TILE
			p2.attenuation = 2.0
			p = p2
		else:
			var p1 := AudioStreamPlayer.new()
			p1.bus = Buses.rain_bus() if key == "rain" else "Ambience"    # (RAIN: the rain's own bus, a low-pass that closes under a roof: scripts/render/rain_view.gd)
			if key == "rain":
				Buses.set_rain_muffle(0.0)    # (a new game starts with it open: the last one may have left it shut)
			p = p1
		p.stream = s
		add_child(p)
		beds[key] = p
	for key in ENGINE:
		var list := _load_list([ENGINE[key]])
		if list.is_empty():
			continue
		var s: AudioStreamWAV = list[0]
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = s
		add_child(p)
		if key == "loop":
			engine_player = p
		else:
			road_player = p
	for key in ["crow", "dog", "creak", "moan", "shot"]:
		_far_timer[key] = _rng.randf_range(10.0, 40.0)


## Gives it the game (main.gd, or a stand-in with sim, speed, menu_open, title_mode, cam_center and data).
func attach(g) -> void:
	game = g
	_doors.clear()
	_generators.clear()
	_radios.clear()
	_surface_of.clear()
	_indoor_ids.clear()
	var data = g.get("data") if g != null else null
	if data is Dictionary:
		for o in data.get("objects", []):
			var kind := String(o.get("kind", ""))
			if kind == "door" or kind == "hatch" or kind == "trapdoor":
				_doors.append({"rect": Rect2(float(o.cx) - float(o.w) / 2.0, float(o.cy) - float(o.h) / 2.0, float(o.w), float(o.h)), "in": false, "cool": 0.0, "hatch": kind != "door"})
			elif kind == GENERATOR_KIND:
				_generators.append(Vector2(float(o.cx), float(o.cy)))
			elif kind == RADIO_KIND:
				_radios.append(Vector2(float(o.cx), float(o.cy)))
		var types = data.get("terrainTypes", {})
		if types is Dictionary:
			for tname in types:
				var id := int(types[tname].get("id", -1))
				_surface_of[id] = _surface_for_name(String(tname))
				if _has_word(String(tname), INDOOR_WORDS):
					_indoor_ids[id] = true


static func _has_word(name: String, words: Array) -> bool:
	var up := name.to_upper()
	for w in words:
		if up.contains(String(w)):
			return true
	return false


## "dirt", "wood" or "concrete" from a terrain's name (anything not named for earth or boards is a hard floor).
static func _surface_for_name(name: String) -> String:
	if _has_word(name, WOOD_WORDS):
		return "wood"
	if _has_word(name, DIRT_WORDS):
		return "dirt"
	return "concrete"


## The sounds of a group are kept under "group:name" ("bell:dusk", "step:wood", "gate:lever", "door:open", "far:crow").
func _load_group(prefix: String, table: Dictionary) -> void:
	for key in table:
		streams["%s:%s" % [prefix, key]] = _load_list(table[key])


func _load_list(names: Array) -> Array:
	var out: Array = []
	for n in names:
		var path := "%s%s.wav" % [DIR, n]
		if ResourceLoader.exists(path):
			var s = load(path)
			if s != null:
				out.append(s)
	return out


func _pick(key: String, avoid := -1):
	var list: Array = streams.get(key, [])
	if list.is_empty():
		return null
	if list.size() == 1:
		return list[0]
	var i := _rng.randi() % list.size()
	if i == avoid:
		i = (i + 1) % list.size()
	return list[i]


# ------------------------------------------------------------------ the clock --

## Called every frame by Sound with the frame's real seconds: the scheduled sounds, and, ten times a second, the world.
func update(dt: float) -> void:
	_t += dt
	_engine_idle += dt
	if _engine_idle > 0.4 and engine_player != null and engine_player.playing:
		engine_stop()
	var i := 0
	while i < _later.size():
		_later[i].t -= dt
		if _later[i].t <= 0.0:
			var item = _later[i]
			_later.remove_at(i)
			(item.fn as Callable).call()
		else:
			i += 1
	_acc += dt
	if _acc < TICK:
		return
	var step := _acc
	_acc = 0.0
	_tick(step)


func schedule(seconds: float, what: Callable) -> void:
	_later.append({"t": seconds, "fn": what})


func _running() -> bool:
	return game != null and game.get("sim") != null and not bool(game.get("title_mode")) and int(game.get("speed")) > 0 and not bool(game.get("menu_open"))


func _tick(dt: float) -> void:
	if game == null or game.get("sim") == null or bool(game.get("title_mode")):
		return
	_step_clock += dt
	_foot_tick(dt)
	_door_tick(dt)
	_hum_tick()
	if _running():
		_far_tick(dt)


## The tile the listener is at (the game's camera) and the pixel the ears are really at (the current Camera2D), so that a sound put at a
## tile lands on the right side whichever camera is the current one.
func listener_tile() -> Vector2:
	if game != null and game.get("cam_center") is Vector2:
		return game.cam_center
	return Vector2.ZERO


func _listener_px() -> Vector2:
	var vp := get_viewport() if is_inside_tree() else null
	var cam: Camera2D = vp.get_camera_2d() if vp != null else null
	return cam.get_screen_center_position() if cam != null else Vector2.ZERO


func world_px(tile: Vector2, listener: Vector2) -> Vector2:
	return _listener_px() + (tile - listener) * TILE


# ------------------------------------------------------------------- the voices --

func _count(kind: String) -> int:
	var n := 0
	for v in voices:
		if v.kind == kind and v.p.playing:
			n += 1
	return n


## How many positional voices are sounding now (never more than MAX_VOICES).
func voices_playing() -> int:
	var n := 0
	for v in voices:
		if v.p.playing:
			n += 1
	return n


## Plays a stream from a place (tiles) as a voice of `kind` with a priority (a louder, nearer, more important sound has more): in the free voice,
## or in the weakest one if this is stronger than it, else not at all (the cap). False if it was dropped.
func play_at(kind: String, stream, tile: Vector2, listener: Vector2, volume_db: float, pitch: float, prio: float, reach: float, bus := "SFX", attenuation := 2.0) -> bool:
	if stream == null or muted or (sound != null and bool(sound.get("muted"))):
		return false
	var cap: int = int(KIND_CAP.get(kind, MAX_VOICES))
	var chosen = null
	if _count(kind) >= cap:
		for v in voices:
			if v.kind == kind and v.p.playing and (chosen == null or v.prio < chosen.prio):
				chosen = v
		if chosen == null or chosen.prio >= prio:
			dropped += 1
			return false
	else:
		for v in voices:
			if not v.p.playing:
				chosen = v
				break
		if chosen == null:
			for v in voices:
				if chosen == null or v.prio < chosen.prio:
					chosen = v
			if chosen.prio >= prio:
				dropped += 1
				return false
	var p: AudioStreamPlayer2D = chosen.p
	chosen.kind = kind
	chosen.prio = prio
	p.stream = stream
	p.bus = bus if (bus == "SFX" or AudioServer.get_bus_index(bus) >= 0) else "SFX"
	p.max_distance = reach * TILE
	p.attenuation = attenuation
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.1, pitch)
	p.position = world_px(tile, listener)
	p.play()
	played[kind] = int(played.get(kind, 0)) + 1
	return true


# --------------------------------------------------------------------- the events --

## One of the rules' events (main.gd gives each one as it handles them). The sounds that the events of the bells, the dead, the gate, the radio
## and the news have are all here; the guns and the blows are the combat sounds', in main.gd.
func on_event(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"bell":
			ring("dusk")
		"lure":
			ring("alarm")
		"season":
			ring("deep")
		"built":
			ring("chime")
		"arrived", "survivor", "rescued", "rescue":
			ring("chime")
			_music_notify("rescue")    # (someone found: the warm stinger)
		"groan":
			groan(e, listener_tile())
		"gate":
			gate_event(String(e.get("state", "")), String(e.get("by", "")))
		"call_raised":
			ui("ui_radio_call", 0.9)
			_duck(-3.0, 1.2)
		"radio_line":
			ui("ui_radio_on", 0.5)
			schedule(0.7, func(): ui("ui_radio_off", 0.5))
		"briefing":
			ui("ui_card", 0.7)
			schedule(0.3, func(): ui("ui_notify", 0.6))
		"story_card":
			ui("ui_card", 0.6)
			schedule(0.25, func(): ui("ui_notify", 0.5))


func ui(name: String, level := 1.0) -> void:
	if sound != null and sound.has_method("ui"):
		sound.ui(name, level)


func _duck(db: float, seconds: float) -> void:
	var m = Music.current()
	if m != null:
		m.duck(db, seconds)


func _music_notify(kind: String) -> void:
	var m = Music.current()
	if m != null:
		m.notify(kind)


# ------------------------------------------------------------------------ the bells --

## Rings a bell: "dusk" (four tolls), "alarm", "deep" (the season), "chime" (small), "far" (heard on a trip). `level` is 0 to 1.
func ring(kind: String, level := 1.0) -> void:
	if muted or (sound != null and bool(sound.get("muted"))):
		return
	match kind:
		"dusk":
			var tolls := DUSK_TOLLS
			for i in tolls.size():
				var gap: float = float(tolls[i][0]) + (_rng.randf_range(-0.12, 0.12) if i > 0 else 0.0)
				var lv: float = float(tolls[i][1]) * level
				if gap <= 0.0:
					_toll("bell:dusk", lv)
				else:
					schedule(gap, func(): _toll("bell:dusk", lv))
		"alarm", "deep", "chime", "far":
			_toll("bell:%s" % kind, level * (0.8 if kind == "chime" else 1.0))


func _toll(key: String, level: float) -> void:
	var stream = _pick(key, _last_bell if key == "bell:dusk" else -1)
	if stream == null:
		return
	if key == "bell:dusk":
		_last_bell = streams[key].find(stream)
	var p: AudioStreamPlayer = null
	for b in bells:
		if not b.playing:
			p = b
			break
	if p == null:
		p = bells[0]
	p.stream = stream
	p.volume_db = linear_to_db(maxf(level, 0.0001))
	p.pitch_scale = 1.0 + (_rng.randf_range(-0.006, 0.006) if key != "bell:dusk" else 0.0)
	p.play()
	played["bell"] = int(played.get("bell", 0)) + 1


# ------------------------------------------------------------------------ the dead --

## A groan the rules made ({"x", "y", "kind", "stray"}), heard from `listener` (tiles). Not every one is heard: most of a crowd is a murmur.
func groan(e: Dictionary, listener: Vector2) -> void:
	var stray := bool(e.get("stray", false))
	if _rng.randf() > (0.2 if stray else 0.6):
		return
	var at := Vector2(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
	var d := at.distance_to(listener)
	var kind := String(e.get("kind", "walker"))
	if kind == "brute":
		roar(at, listener)
		return
	if d > GROAN_REACH:
		return
	var list: Array = streams.get("groan", [])
	if list.is_empty():
		return
	var i := _rng.randi() % list.size()
	if i == _last_groan:
		i = (i + 1) % list.size()
	_last_groan = i
	var pitch := float(GROAN_PITCH.get(kind, 1.0)) * _rng.randf_range(0.9, 1.12)
	var vol := -3.0 + _rng.randf_range(-2.0, 0.0) - (7.0 if stray else 0.0)
	if stray:
		pitch *= 0.85
	play_at("groan", list[i], at, listener, vol, pitch, -d, GROAN_REACH)


## The plated brute's bellow, with its distance; the music dips under it. Not more than one every 2.5 s.
func roar(at: Vector2, listener: Vector2) -> void:
	if _t - _last_roar < 2.5 or _rng.randf() > 0.8:
		return
	var list: Array = streams.get("roar", [])
	if list.is_empty():
		return
	var d := at.distance_to(listener)
	if d > ROAR_REACH:
		return
	_last_roar = _t
	if play_at("roar", list[_rng.randi() % list.size()], at, listener, -1.0, _rng.randf_range(0.94, 1.06), 100.0 - d, ROAR_REACH, "SFX", 1.5):
		_music_notify("brute")


# ------------------------------------------------------------------------ the gate --

func gate_event(state: String, by: String) -> void:
	var listener := listener_tile()
	match state:
		"opening", "closing":
			play_at("gate", _pick("gate:lever"), _gate_spot("control_spot"), listener, -2.0, _rng.randf_range(0.97, 1.03), 50.0, 36.0)
			schedule(0.3, func(): play_at("gate", _pick("gate:slide"), _gate_spot("gateway"), listener_tile(), -3.0, _rng.randf_range(0.97, 1.03), 40.0, 40.0))
			if by == "player":
				_music_notify("gate")
		"open", "shut":
			play_at("gate", _pick("gate:clang"), _gate_spot("gateway"), listener, -3.0, _rng.randf_range(0.97, 1.03), 45.0, 44.0)


## Where the gate's lever ("control_spot") or its opening ("gateway", the middle of its rectangle) is, from the rules' gate if the game has one; else where
## the camera is (the sound is then plain, not put anywhere).
func _gate_spot(which: String) -> Vector2:
	var sim = game.get("sim") if game != null else null
	var gate = sim.get("gate") if sim != null else null
	if gate != null and gate.has_method(which):
		var v = gate.call(which)
		if v is Rect2:
			return (v as Rect2).get_center()
		if v is Vector2:
			return v
	return listener_tile()


# ---------------------------------------------------------------- steps and doors --

## The surface under a place (tiles): "dirt", "concrete" or "wood" (a person on a raised deck is on wood). `person` may be null.
func surface_at(x: float, y: float, person = null) -> String:
	var sim = game.get("sim") if game != null else null
	if person != null and sim != null and sim.get("levels") != null and sim.levels.has_method("on_deck") and sim.levels.on_deck(person):
		return "wood"
	var id := _terrain_id(x, y)
	return String(_surface_of.get(id, "dirt")) if id >= 0 else "dirt"


## The terrain id under a place (tiles), or -1 where the game has no ground to ask.
func _terrain_id(x: float, y: float) -> int:
	var world = game.get("world") if game != null else null
	if world == null or world.get("terrain") == null or world.get("W") == null:
		return -1
	var cx := int(floor(x))
	var cy := int(floor(y))
	if cx < 0 or cy < 0 or cx >= int(world.W) or cy >= int(world.H):
		return -1
	return int(world.terrain[cy * int(world.W) + cx])


## Whether a place is on an indoor floor (a terrain whose name says lino, tile, carpet, kitchen...).
func indoors_at(x: float, y: float) -> bool:
	var id := _terrain_id(x, y)
	return id >= 0 and _indoor_ids.has(id)


## Whether the player's avatar is indoors now (false when there is none): what the music is told.
func avatar_indoors() -> bool:
	if game == null or game.get("sim") == null:
		return false
	var me = _player()
	return me != null and indoors_at(me.x, me.y)


func _foot_tick(dt: float) -> void:
	var sim = game.sim
	if int(game.get("speed")) > 1 or int(game.get("speed")) <= 0 or bool(game.get("menu_open")):
		_last_pos.clear()
		return
	var cam := listener_tile()
	var made := 0
	for p in sim.people:
		if p.dead or p.turned or p.away != null:
			continue
		var id := String(p.id)
		var here := Vector2(p.x, p.y)
		var mine: bool = bool(p.get("player")) if p.get("player") != null else false
		if not mine and here.distance_to(cam) > 10.0:
			_last_pos.erase(id)
			continue
		if not _last_pos.has(id):
			_last_pos[id] = here
			continue
		var moved: float = here.distance_to(_last_pos[id])
		_last_pos[id] = here
		if moved > 2.0 or moved < 0.004:
			continue
		_stride[id] = float(_stride.get(id, 0.0)) + moved
		if float(_stride[id]) < STRIDE:
			continue
		_stride[id] = float(_stride[id]) - STRIDE
		if made >= 2:
			continue
		var surface := surface_at(here.x, here.y, p)
		var stream = _pick("step:%s" % surface)
		if stream == null:
			continue
		var vol := (-1.0 if mine else -8.0) + _rng.randf_range(-1.5, 1.0)
		var pitch := _rng.randf_range(0.93, 1.07)
		if mine and float(p.get_meta("sprint_lean", 0.0)) > 0.5:
			# (PACE: a run is a harder, quicker footfall: the same steps, a little louder and higher; the rate is the stride's, which the pace makes faster by itself)
			vol += 2.5
			pitch *= 1.12
		if play_at("step", stream, here, cam, vol, pitch, (10.0 if mine else 0.0) - here.distance_to(cam), STEP_REACH):
			made += 1


func _door_tick(dt: float) -> void:
	if _doors.is_empty():
		return
	var me = _player()
	if me == null:
		return
	var here := Vector2(me.x, me.y)
	for d in _doors:
		d.cool = maxf(0.0, float(d.cool) - dt)
		if not bool(d["in"]) and (d.rect as Rect2).get_center().distance_squared_to(here) > 36.0:
			continue
		var near: bool = (d.rect as Rect2).grow(0.6).has_point(here)
		if near and not bool(d["in"]):
			d["in"] = true
			if float(d.cool) <= 0.0:
				d.cool = 4.0
				var at: Vector2 = (d.rect as Rect2).get_center()
				play_at("door", _pick("door:hatch" if bool(d.hatch) else "door:open"), at, listener_tile(), -4.0, _rng.randf_range(0.96, 1.04), 20.0, 18.0)
		elif not near and bool(d["in"]):
			d["in"] = false
			var at2: Vector2 = (d.rect as Rect2).get_center()
			var hatch: bool = bool(d.hatch)
			schedule(0.5, func(): play_at("door", _pick("door:hatch" if hatch else "door:close"), at2, listener_tile(), -5.0, _rng.randf_range(0.96, 1.04), 20.0, 18.0))


func _player():
	var sim = game.sim
	for p in sim.people:
		if p.get("player") != null and bool(p.player) and not p.dead:
			return p
	return null


## The generators' hum and the radio desks' crackle, where they stand, while the camera is near (a radio's only while someone is at it).
func _hum_tick() -> void:
	var cam := listener_tile()
	var gen: AudioStreamPlayer2D = beds.get("generator")
	if gen != null:
		var best = _nearest(_generators, cam)
		if best == null:
			_hum(gen, Vector2.ZERO, cam, -80.0)
		else:
			_hum(gen, best, cam, -4.0)
	var radio: AudioStreamPlayer2D = beds.get("radio")
	if radio != null:
		var desk = _nearest(_radios, cam)
		if desk == null:
			_hum(radio, Vector2.ZERO, cam, -80.0)
		else:
			var staffed := true
			var sim = game.sim
			if sim.get("jobs") != null and sim.jobs.has_method("operator"):
				staffed = sim.jobs.operator("radio") != null
			_hum(radio, desk, cam, -2.0 if staffed else -80.0)


func _nearest(list: Array, at: Vector2):
	var best = null
	for v in list:
		if best == null or (v as Vector2).distance_to(at) < (best as Vector2).distance_to(at):
			best = v
	return best


func _hum(p: AudioStreamPlayer2D, at: Vector2, cam: Vector2, vol: float) -> void:
	var near := at.distance_to(cam) <= HUM_REACH + 4.0 and vol > -60.0 and not muted
	if not near:
		if p.playing:
			p.stop()
		return
	p.volume_db = vol
	p.position = world_px(at, cam)
	if not p.playing:
		p.play(_rng.randf() * maxf(0.1, p.stream.get_length() - 0.5))


# ------------------------------------------------------------------------ the air --

## The beds that are not the wind: `night` (0 to 1: the darkness), `horde` (0 to 1) and the weather (the rules'). Called with the ambience.
func beds_set(night: float, horde: float, dt: float) -> void:
	var k := minf(1.0, dt * 1.5)
	var rain_goal := 0.0
	var sim = game.get("sim") if game != null else null
	if sim != null:
		var w := String(sim.get("weather")) if sim.get("weather") != null else "clear"
		rain_goal = 1.0 if (w == "rain" or w == "storm") else 0.0
		# (RAIN: in the town the bed follows how hard it rains, a murmur in a drizzle and a roar in a storm: scripts/town/skies.gd `sound_level`)
		var skies = sim.get("skies")
		if skies != null:
			rain_goal = float(skies.sound_level())
	bed_level["rain"] = lerpf(bed_level["rain"], rain_goal, minf(1.0, dt * 0.35))
	bed_level["night_bed"] = lerpf(bed_level["night_bed"], night * (1.0 - 0.45 * horde), k)
	_bed("night_bed", bed_level["night_bed"] * 0.85)
	_bed("rain", bed_level["rain"] * 0.9)


func _bed(key: String, level: float) -> void:
	var p: AudioStreamPlayer = beds.get(key)
	if p == null:
		return
	if level < 0.004:
		if p.playing:
			p.stop()
		return
	p.volume_db = linear_to_db(level)
	if not p.playing:
		p.play(_rng.randf() * maxf(0.1, p.stream.get_length() - 0.5) if not OS.has_feature("web") else 0.0)


func _far_tick(dt: float) -> void:
	var sim = game.sim
	var phase := String(sim.phase)
	var cam := listener_tile()
	var horde := 0.0
	if sim.get("zombies") != null:
		horde = clampf(float(sim.zombies.size()) / 60.0, 0.0, 1.0)
	for key in _far_timer.keys():
		var ok := false
		var gap := Vector2(40.0, 120.0)
		match key:
			"crow":
				ok = phase == "day" or phase == "dawn"
				gap = Vector2(45.0, 120.0)
			"dog":
				ok = phase == "dusk" or phase == "night"
				gap = Vector2(50.0, 140.0)
			"creak":
				ok = true
				gap = Vector2(70.0, 190.0)
			"moan":
				ok = phase == "night" or phase == "dusk"
				gap = Vector2(20.0, 60.0) / (1.0 + horde)
			"shot":
				ok = phase == "night" and horde < 0.5
				gap = Vector2(90.0, 240.0)
		if not ok:
			continue
		_far_timer[key] = float(_far_timer[key]) - dt
		if float(_far_timer[key]) > 0.0:
			continue
		_far_timer[key] = _rng.randf_range(gap.x, gap.y)
		_far_one(key, cam)


func _far_one(key: String, cam: Vector2) -> void:
	var stream = _pick("far:%s" % key)
	if stream == null:
		return
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(34.0, 60.0) if key != "creak" else _rng.randf_range(12.0, 26.0)
	var at := cam + Vector2(cos(angle), sin(angle)) * dist
	var vol := -6.0
	match key:
		"crow":
			vol = -5.0
		"dog":
			vol = -5.0
		"creak":
			vol = -4.0
		"moan":
			vol = -3.0
		"shot":
			vol = -4.0
	play_at("far", stream, at, cam, vol + _rng.randf_range(-2.0, 0.0), _rng.randf_range(0.96, 1.04), 5.0, 90.0, Buses.far_bus(), 1.0)


# ----------------------------------------------------------------------- the engine --

## The truck on a trip (drive_scene.gd calls it each step): `speed` and `top` in tiles a second, `throttle` -1 to 1. It stops by itself
## when it is not called for 0.4 s (the leg is over).
func engine(speed: float, top: float, throttle: float) -> void:
	if engine_player == null or muted:
		return
	_engine_idle = 0.0
	var v := clampf(absf(speed) / maxf(top, 0.1), 0.0, 1.0)
	engine_player.pitch_scale = lerpf(0.85, 2.4, pow(v, 0.8)) + 0.18 * clampf(throttle, 0.0, 1.0)
	engine_player.volume_db = lerpf(-8.0, -3.0, v) + 2.0 * clampf(throttle, 0.0, 1.0)
	if not engine_player.playing:
		engine_player.play(0.0)
	if road_player != null:
		road_player.volume_db = linear_to_db(maxf(pow(v, 1.3) * 0.7, 0.0001))
		road_player.pitch_scale = 0.9 + 0.35 * v
		if not road_player.playing:
			road_player.play(0.0)


func engine_stop() -> void:
	if engine_player != null:
		engine_player.stop()
	if road_player != null:
		road_player.stop()
