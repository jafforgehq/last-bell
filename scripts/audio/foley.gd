## The SOUND pass's catalogue (docs/audio-mix.md is its written mix table): which generated files there are (assets/audio, made by tools/make_foley_sounds.py,
## make_voice_sounds.py and make_weather_sounds.py), the ground under a place (a cheap lookup, for the footsteps and the shot's room), and the gain staging of each
## kind of sound. Static and read-only: it plays nothing and writes nothing in the rules (the golden tests' promise).
##
## GROUND. In the town the world has `grp`, one byte for each tile: the kit's ground group (an index into TownArt.GROUNDS) or 255 for the top of a wall. `ground_at`
## turns it into one of seven names with a table of 256 bytes (made once): grass, dirt, gravel, pave (asphalt and sidewalk), wood (a floor), tile (kitchen, bath, hall) and
## carpet (carpet and the runners on a hall floor). A game without a kit (the school, the tests) has only the terrain's names: `Soundscape.surface_at` says dirt, concrete
## or wood, and those become dirt, pave and wood.
extends RefCounted

const TownArt := preload("res://scripts/town/town_art.gd")

const DIR := "res://assets/audio/"

## The seven grounds, and which of them are inside a house (a floor).
const GROUNDS := ["grass", "dirt", "gravel", "pave", "wood", "tile", "carpet"]
const INDOOR := {"wood": true, "tile": true, "carpet": true}
## The dead's step by ground: a soft foot on earth and carpet, a harder one on the rest.
const SOFT_GROUNDS := {"grass": true, "dirt": true, "carpet": true}
## The kit's ground group (TownArt.GROUNDS) -> ground.
const OF_GROUP := {
	"lawn": "grass", "asphalt": "pave", "sidewalk": "pave", "dirt_path": "dirt", "gravel": "gravel", "floor_wood": "wood", "floor_hall": "tile",
	"floor_kitchen": "tile", "floor_carpet": "carpet", "floor_bath": "tile", "floor_runner_h": "carpet", "floor_runner_v": "carpet",
}
## What the school's three surfaces (Soundscape.surface_at) are, in the new names.
const OF_SURFACE := {"dirt": "dirt", "concrete": "pave", "wood": "wood"}

## The files of each group: key -> [stem, count] (`<stem>_<i>.wav`). Keys are what the soundscape and the fight sounds ask for.
const GROUPS := {
	"dead:soft": ["dead_soft", 3], "dead:hard": ["dead_hard", 3], "dead:drag": ["dead_drag", 2],
	"voice:zgroan": ["zgroan", 8], "voice:zgroan_far": ["zgroan_far", 3], "voice:zgrowl": ["zgrowl", 4], "voice:zbrute_growl": ["zbrute_growl", 2],
	"voice:zrun_hiss": ["zrun_hiss", 2], "voice:zrun_screech": ["zrun_screech", 2], "voice:ruth_pain": ["ruth_pain", 4], "voice:ruth_breath": ["ruth_breath", 4],
	"gun:out": ["blast_out", 3], "gun:in": ["blast_in", 3],
	"reload:shell": ["shell_load", 3], "reload:pump": ["pump_rack", 2], "reload:click": ["trigger_click", 2],
	"melee:swoosh": ["melee_swoosh", 3], "melee:thud": ["melee_thud", 3], "melee:kill": ["melee_kill", 3],
	"thunder:near": ["thunder_near", 2], "thunder:mid": ["thunder_mid", 2], "thunder:far": ["thunder_far", 1],
}
## The sounds the game already asks for by name, and the better ones that stand in for them (scripts/audio/sound.gd `OVERRIDES`): the empty gun's click, a shell into the
## tube, the pump's rack, a blow in the air, a blow that lands.
const OVERRIDES := {
	"dry_click": "reload:click", "shell_in": "reload:shell", "pump": "reload:pump", "melee_swing": "melee:swoosh", "melee_hit": "melee:thud",
}

## GAIN STAGING (decibels on the player of each sound, before its bus). The shot in the open is the reference: at -1 dB it is -12.8 LUFS at the master (tools/mix_probe.gd measures
## the real chain: the player, the position, the bus, the limiter); a room's shot is 2.5 dB under it in loudness (its energy is in the tail) and is lifted by 1.5 dB over it (its peak stays
## under -1.7 dBFS). Positional voices (the dead, Ruth) lose 3 dB at the middle of the pan, which the Voices bus gives back and more (buses.gd TRIM_DB). Each value is a line of the mix table in
## docs/audio-mix.md, with the number that was measured for it.
const LEVEL_DB := {
	"gun_out": -1.0, "gun_in": 0.5,
	"step_ruth": -1.0, "step_run": 0.5, "step_crew": -5.0, "step_dead": 0.0,
	"groan_near": 1.0, "groan_far": -1.0, "roar": 1.0, "growl": -0.5, "brute_growl": -1.0, "hiss": 3.0, "screech": -2.0,
	"ruth_pain": -2.0, "ruth_breath": -6.0,
	"moan": -4.0,
}
## The eight groans the game already had are not one loudness (their loudest 400 ms is -16.3 to -23.6 LUFS as files): each is brought to the new ones' (-21) by this many decibels,
## measured with tools/audio_measure.py (the file's stem -> dB), so that which groan is heard is not a matter of volume.
const OLD_GROAN_TRIM_DB := {"groan_0": 1.2, "groan_1": -2.2, "groan_2": 0.3, "groan_3": -2.1, "groan_4": 0.2, "groan_5": -4.7, "groan_6": -3.1, "groan_7": 2.6}

## Which of the three thunders a strike is (`far` 0 to 1, from rain_view.gd: the delay after the flash, 1 to 3 s), and how loud: the near one at THUNDER_BASE_DB at its nearest, THUNDER_DB_AT_FAR under at the farthest.
const THUNDER_FAR_NEAR := 0.34
const THUNDER_FAR_MID := 0.67
const THUNDER_BASE_DB := -2.0
const THUNDER_DB_AT_FAR := -6.0
const INDOOR_THUNDER_DB := -3.0

static var _lut := PackedByteArray()


## The paths of a group's files.
static func paths(key: String) -> Array:
	var out: Array = []
	if GROUPS.has(key):
		var g: Array = GROUPS[key]
		for i in int(g[1]):
			out.append("%s%s_%d.wav" % [DIR, String(g[0]), i])
	elif key.begins_with("fs:"):
		var parts := key.split(":")
		var ground := String(parts[1])
		var run := parts.size() > 2 and String(parts[2]) == "run"
		for i in (2 if run else 3):
			out.append("%sfs_%s_%s%d.wav" % [DIR, ground, "run_" if run else "", i])
	return out


## The streams of a group that are there (a file that is not imported is left out, so that a checkout that has not been imported plays on without it).
static func load_group(key: String) -> Array:
	var out: Array = []
	for path in paths(key):
		if ResourceLoader.exists(path):
			var s = load(path)
			if s != null:
				out.append(s)
	return out


## The key of the group that a ground's footsteps are (`running`: the heavy ones).
static func step_key(ground: String, running: bool) -> String:
	return "fs:%s:run" % ground if running else "fs:%s" % ground


## Every key a lazy loader may be asked (the footsteps and the groups).
static func all_keys() -> Array:
	var out: Array = GROUPS.keys()
	for g in GROUNDS:
		out.append(step_key(g, false))
		out.append(step_key(g, true))
	return out


# ------------------------------------------------------------------------------------------------------ ground --

## The table that turns a kit ground group (a byte of `world.grp`) into an index of GROUNDS (255, the top of a wall, is pave: nobody stands there, a shot's hit is the nearest thing).
static func lut() -> PackedByteArray:
	if _lut.size() == 256:
		return _lut
	_lut.resize(256)
	_lut.fill(GROUNDS.find("pave"))
	var names: Array = TownArt.GROUNDS
	for i in names.size():
		var ground := String(OF_GROUP.get(String(names[i]), "pave"))
		_lut[i] = GROUNDS.find(ground)
	return _lut


## The ground under a place (tiles) in a world that has the kit's `grp`: one of GROUNDS, or "" when the world has none (ask `Soundscape.surface_at` then).
static func ground_at(world, x: float, y: float) -> String:
	if world == null:
		return ""
	var grp = world.get("grp")
	var w = world.get("W")
	var h = world.get("H")
	if not (grp is PackedByteArray) or w == null or h == null:
		return ""
	var cx := int(floor(x))
	var cy := int(floor(y))
	if cx < 0 or cy < 0 or cx >= int(w) or cy >= int(h):
		return ""
	var i := cy * int(w) + cx
	if i >= (grp as PackedByteArray).size():
		return ""
	return String(GROUNDS[int(lut()[int((grp as PackedByteArray)[i])])])


## The ground of a school surface name.
static func ground_of_surface(surface: String) -> String:
	return String(OF_SURFACE.get(surface, "dirt"))


static func is_indoor(ground: String) -> bool:
	return INDOOR.has(ground)


static func is_soft(ground: String) -> bool:
	return SOFT_GROUNDS.has(ground)


# ----------------------------------------------------------------------------------------------------- thunder --

## The group of thunder for a strike `far` (0 near, 1 far).
static func thunder_key(far: float) -> String:
	if far < THUNDER_FAR_NEAR:
		return "thunder:near"
	if far < THUNDER_FAR_MID:
		return "thunder:mid"
	return "thunder:far"


## How loud (dB at the player) a strike is: the nearest at THUNDER_BASE_DB, the farthest THUNDER_DB_AT_FAR under that, a little under again with a roof overhead (`indoor` 0 to 1). The Rain bus's own low-pass and trim come after (scripts/audio/buses.gd).
static func thunder_db(far: float, indoor: float) -> float:
	return THUNDER_BASE_DB + THUNDER_DB_AT_FAR * clampf(far, 0.0, 1.0) + INDOOR_THUNDER_DB * clampf(indoor, 0.0, 1.0)
