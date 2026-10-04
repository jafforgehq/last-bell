## The music: a slow score in A minor (and its relative major, C), made by tools/make_score.py. It is played as MOODS, each a set of
## STEMS (loops of one length that play together, in step) whose volumes the game moves:
##
##   title     the tune on a felt piano (the title screen; and after a lost run, quietly)
##   indoors   a cleared house: very sparse and quiet, a few piano notes in a small room
##   outdoors  the day outside, exploring: tense but slow (a drone with a semitone in it, a high string, a far heart)
##   night     the night outside, very tense: night_base always; night_pulse (a heartbeat) comes in with the dead; night_perc (soft drums) when many are near
##   fortress  the fortified house under attack: fortress_base, fortress_pulse (a heavy drum), fortress_brass (a low drone), fortress_perc (war drums), by the threat
##   endcard   the tune in C major, hopeful (the end of the demo; a victory)
##
## and four STINGERS that play once over whatever is going on: `dusk` (the bell's: it comes with the evening), `dawn` (the relief: it
## comes when the night is survived), `rescue` (warm and short: someone has been found), `defeat` (a lost run). The stems under a stinger dip.
##
## NOTHING HERE KNOWS A MAP. `follow` is called a few times a second with what the game looks like: whether a run is on, a played trip, how
## dark it is, how many of the dead are at the wall (`horde`, 0 to 1) and, in `ctx`, what the rules and the world say:
##   "phase"     "day", "dusk", "night" or "dawn"
##   "indoors"   the player is inside a house (a cleared one, or any roof): a few seconds of it are needed to switch, in or out, so that a
##               doorway does not make the music flicker; the dead at the door at night (horde above INDOORS_BREAK) bring the night back in
##   "fortress"  tonight the dead attack the fortified house (the old Big Night: "big" is read too)
##   "progress"  0 to 1 through the night; "over" "", "victory" or "defeat"; "end_card" true while the end card is up
## It picks the mood and the threat the layers follow: a layer comes in quickly (2.5 s) and goes out slowly (5 s), and the threat itself
## falls slowly (25 s from full), so a wave that flickers at the edge of the camera does not make the music jump about.
## The order of the choice: defeat, the end card, the title, the fortress at night, a trip, indoors, the night, the day outside.
##
## Stems of a mood are started together and never apart (they are the same length, so they stay in step): a mood's stems keep playing,
## silent, while it is the current one, and are stopped all at once when every one of them has faded out. A mood that comes back while
## its stems are still fading simply fades up again.
##
## DUCKING. `duck(db, seconds)` dips the stems for a while (a brute roars, the gate's lever, the end card: 4 to 6 dB) and they come
## back by themselves (the dip is taken at once and given back over a second); and the stems also dip by up to 3 dB while the SFX bus is
## loud (the guns), a sidechain read from that bus's peak. The Music slider and the HUD's sound button are the bus's, under all this.
##
## The music uses its own random generator; nothing here touches the rules. The files are levelled so that the stems of a mood at full
## volume are what the score's header says (indoors -27 dBFS RMS, a fortress night at full -15.6), the Music bus at 0 dB.
extends Node

const Buses := preload("res://scripts/audio/buses.gd")

const TRACKS := {
	"title": "res://assets/audio/mus_title.wav",
	"indoors": "res://assets/audio/mus_indoors.wav",
	"outdoors": "res://assets/audio/mus_outdoors.wav",
	"night_base": "res://assets/audio/mus_night_base.wav",
	"night_pulse": "res://assets/audio/mus_night_pulse.wav",
	"night_perc": "res://assets/audio/mus_night_perc.wav",
	"fortress_base": "res://assets/audio/mus_fortress_base.wav",
	"fortress_pulse": "res://assets/audio/mus_fortress_pulse.wav",
	"fortress_brass": "res://assets/audio/mus_fortress_brass.wav",
	"fortress_perc": "res://assets/audio/mus_fortress_perc.wav",
	"endcard": "res://assets/audio/mus_endcard.wav",
}
const STINGERS := {
	"dusk": "res://assets/audio/mus_dusk.wav",
	"dawn": "res://assets/audio/mus_dawn.wav",
	"rescue": "res://assets/audio/mus_rescue.wav",
	"defeat": "res://assets/audio/mus_defeat.wav",
}
## The stems of each mood, base first.
const MOODS := {
	"title": ["title"],
	"indoors": ["indoors"],
	"outdoors": ["outdoors"],
	"night": ["night_base", "night_pulse", "night_perc"],
	"fortress": ["fortress_base", "fortress_pulse", "fortress_brass", "fortress_perc"],
	"endcard": ["endcard"],
}
## A layer's threat range: [where it begins to be heard, where it is whole]. A stem that is not here is its mood's base (always whole).
const LAYERS := {
	"night_pulse": [0.10, 0.40],
	"night_perc": [0.45, 0.80],
	"fortress_pulse": [0.0, 0.22],
	"fortress_brass": [0.20, 0.55],
	"fortress_perc": [0.50, 0.85],
}
## The seconds a mood's cross-fade takes; a layer comes in over LAYER_UP_S and goes out over LAYER_DOWN_S.
const FADE_S := 4.0
const LAYER_UP_S := 2.5
const LAYER_DOWN_S := 5.0
## How loud the stems are at full volume (the files carry their loudness: 1.0 is what they were made at).
const LEVEL := 1.0
## The threat: it rises at THREAT_UP a second and falls at THREAT_DOWN; at night it is never under NIGHT_FLOOR plus NIGHT_RAMP of the way through
## the night (a night outside is very tense from its first minute: the heartbeat is already there); in the fortress, FORT_FLOOR and FORT_RAMP.
const THREAT_UP := 0.5
const THREAT_DOWN := 0.04
const NIGHT_FLOOR := 0.30
const NIGHT_RAMP := 0.15
const FORT_FLOOR := 0.12
const FORT_RAMP := 0.38
## Indoors: the seconds the player must be inside (outside) before the music goes in (out), and the horde (0 to 1) at the door at night that brings the night back in.
const INDOORS_IN_S := 1.5
const INDOORS_OUT_S := 2.5
const INDOORS_BREAK := 0.5
## Ducking (decibels, seconds): the stems under a stinger, a brute's roar, the gate's lever, the end card; how fast a dip is taken and given back.
const STINGER_DUCK_DB := -4.0
const BRUTE_DUCK_DB := -5.0
const BRUTE_DUCK_S := 3.0
const GATE_DUCK_DB := -4.0
const GATE_DUCK_S := 1.6
const END_DUCK_DB := -5.0
const END_DUCK_S := 4.0
const DUCK_ATTACK_S := 0.10
const DUCK_RELEASE_S := 0.9
const MAX_DUCK_DB := -9.0
## The sidechain from the SFX bus: above this peak (dBFS) the stems dip by SFX_SLOPE decibels for each decibel over, at most SFX_MAX_DB.
const SFX_FLOOR_DB := -12.0
const SFX_SLOPE := 0.33
const SFX_MAX_DB := 3.0
## A stinger is not played again within STINGER_GAP_S seconds (the rescue's is shorter: a few found in a row each have theirs); after a defeat the music is quiet this long before the title's tune comes back.
const STINGER_GAP_S := 30.0
const STINGER_GAPS := {"rescue": 6.0}
const RESCUE_DUCK_DB := -3.0
const DEFEAT_QUIET_S := 11.0
## The darkness (0 to 1) at which `night` begins when the rules' phase is not given, and the one it has to fall below to be `day` again.
const NIGHT_ON := 0.4
const NIGHT_OFF := 0.28
## Where the one music of the running game is kept (Engine meta), so that a scene reload finds it.
const META := "thirty_bells_music"

## stem -> AudioStreamPlayer (only for the loops that were found)
var players := {}
## stem -> how far its volume has come (0 silent, 1 the whole of LEVEL)
var fade := {}
## stinger name -> AudioStreamPlayer
var stingers := {}
## What is wanted now ("" is none: everything fades out).
var mood := ""
## The smoothed threat the layers follow (0 to 1).
var threat := 0.0
## The dip now (decibels, 0 or less): an event's, and the guns'.
var duck_db := 0.0
var sfx_duck_db := 0.0
var sfx_duck_on := true
var is_night := false
var in_end_card := false
## Whether the music takes the player to be indoors now (the doorway's hysteresis: INDOORS_IN_S, INDOORS_OUT_S).
var is_indoors := false

var _t := 0.0
var _duck_target := 0.0
var _duck_hold := 0.0
var _phase := ""
var _indoors_t := 0.0
var _defeat_t := -1.0
var _stinger_at := {}
var _rng := RandomNumberGenerator.new()


## The music of the running game: made once and hung on the tree's root, so that it outlives the scene reload that a new
## run, a load and the way back to the title are (a music inside the scene would cut dead at the title's Start and fade
## in again from nothing). A second ask gets the same one, still playing its mood.
static func shared(tree: SceneTree) -> Node:
	if Engine.has_meta(META):
		var m = Engine.get_meta(META)
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			return m
	var made = load("res://scripts/audio/music.gd").new()
	made.name = "Music"
	made.setup()
	Engine.set_meta(META, made)
	# the scene that asks is still being built: the root takes it on the next idle frame
	tree.root.add_child.call_deferred(made)
	return made


## The music of the running game if there is one (the soundscape tells it about the brute and the gate), else null.
static func current():
	if Engine.has_meta(META):
		var m = Engine.get_meta(META)
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			return m
	return null


## Where in a track of `length` seconds to start it: a place of its own (`dice` from 0 to 1) so that the same bars are
## not heard every time, but the top on the web, where a sample's restart reuses its start offset and a loop begun half
## way would replay only its second half.
static func start_offset(length: float, web: bool, dice: float) -> float:
	if web:
		return 0.0
	return clampf(dice, 0.0, 1.0) * maxf(0.0, length - 1.0)


## The smoothstep of a layer: 0 below `a`, 1 above `b`.
static func layer_share(threat_now: float, a: float, b: float) -> float:
	if b <= a:
		return 1.0 if threat_now >= b else 0.0
	var x := clampf((threat_now - a) / (b - a), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _ready() -> void:
	# the music goes on while a menu or a page has the game waiting
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup() -> void:
	Buses.ensure()
	_rng.randomize()
	for stem in TRACKS:
		var path: String = TRACKS[stem]
		if not ResourceLoader.exists(path):
			continue
		var s = load(path)
		if not s is AudioStreamWAV:
			continue
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		var p := AudioStreamPlayer.new()
		p.name = "Music_%s" % stem
		p.bus = "Music"
		p.stream = s
		p.volume_db = Buses.SILENT_DB
		add_child(p)
		players[stem] = p
		fade[stem] = 0.0
	for name in STINGERS:
		var path: String = STINGERS[name]
		if not ResourceLoader.exists(path):
			continue
		var s = load(path)
		if not s is AudioStreamWAV:
			continue
		var p := AudioStreamPlayer.new()
		p.name = "Stinger_%s" % name
		p.bus = "Music"
		p.stream = s
		add_child(p)
		stingers[name] = p


# ------------------------------------------------------------------- what is wanted --

## What the music should be for this state of the game. `in_run` is false on the title screen; `trip` is true while a played trip is open;
## `dark` (0 to 1) and `horde` (0 to 1) are as above; `dt` the seconds since the last call. `ctx` (all optional, the keys in the header):
## "phase", "indoors", "fortress", "progress", "over", "end_card".
func follow(in_run: bool, trip: bool, dark: float, horde: float, dt: float, ctx: Dictionary = {}) -> void:
	var over := String(ctx.get("over", ""))
	if over != "defeat":
		_defeat_t = -1.0
	if over == "defeat":
		in_end_card = false
		if _defeat_t < 0.0:
			_defeat_t = 0.0
			stinger("defeat")
		_defeat_t += dt
		_aim_threat(0.0, dt)
		set_mood("" if _defeat_t < DEFEAT_QUIET_S else "title")
		return
	if over == "victory" or bool(ctx.get("end_card", false)) or (in_end_card and in_run):
		_begin_end_card()
		_aim_threat(0.0, dt)
		set_mood("endcard")
		return
	if not in_run:
		in_end_card = false
		_phase = ""
		is_indoors = false
		_indoors_t = 0.0
		_aim_threat(0.0, dt)
		set_mood("title")
		return
	in_end_card = false
	var phase := String(ctx.get("phase", ""))
	var night := false
	if phase != "":
		night = phase == "dusk" or phase == "night"
		is_night = night
		if phase == "dusk" and _phase == "day":
			stinger("dusk")
		elif phase == "dawn" and (_phase == "night" or _phase == "dusk"):
			stinger("dawn")
		_phase = phase
	else:
		if is_night:
			if dark < NIGHT_OFF:
				is_night = false
		elif dark >= NIGHT_ON:
			is_night = true
		night = is_night
	var fortress := bool(ctx.get("fortress", ctx.get("big", false)))
	if night and fortress:
		var progress := clampf(float(ctx.get("progress", 0.0)), 0.0, 1.0)
		_aim_threat(maxf(horde, FORT_FLOOR + FORT_RAMP * progress), dt)
		set_mood("fortress")
		return
	if trip:
		_aim_threat(maxf(horde, 0.2), dt)
		set_mood("night" if night else "outdoors")
		return
	_watch_indoors(bool(ctx.get("indoors", false)), dt)
	if is_indoors and not (night and horde >= INDOORS_BREAK):
		_aim_threat(0.0, dt)
		set_mood("indoors")
	elif night:
		var progress2 := clampf(float(ctx.get("progress", 0.0)), 0.0, 1.0)
		_aim_threat(maxf(horde, NIGHT_FLOOR + NIGHT_RAMP * progress2), dt)
		set_mood("night")
	else:
		_aim_threat(0.0, dt)
		set_mood("outdoors")


## The doorway's hysteresis: indoors is taken to have changed only when the player has been on the other side of the door for a while.
func _watch_indoors(raw: bool, dt: float) -> void:
	if raw == is_indoors:
		_indoors_t = 0.0
		return
	_indoors_t += dt
	if _indoors_t >= (INDOORS_IN_S if raw else INDOORS_OUT_S):
		is_indoors = raw
		_indoors_t = 0.0


func _aim_threat(target: float, dt: float) -> void:
	var rate := THREAT_UP if target > threat else THREAT_DOWN
	threat = move_toward(threat, clampf(target, 0.0, 1.0), rate * maxf(dt, 0.0))


## The mood to cross-fade to: a name in MOODS, or "" for none.
func set_mood(m: String) -> void:
	mood = m


## Something the game tells the music about: "brute" (a brute roars), "gate" (the lever), "rescue" (someone found: the warm stinger),
## "end_card" (the end card is up: the tune of the major takes over until "end_card_off" or the title), "dusk", "dawn" and "defeat" (the stingers).
func notify(kind: String) -> void:
	match kind:
		"brute":
			duck(BRUTE_DUCK_DB, BRUTE_DUCK_S)
		"gate":
			duck(GATE_DUCK_DB, GATE_DUCK_S)
		"end_card":
			_begin_end_card()
			set_mood("endcard")
		"end_card_off":
			in_end_card = false
		"rescue":
			if stinger("rescue"):
				duck(RESCUE_DUCK_DB, 4.0)
		"dusk", "dawn", "defeat":
			stinger(kind)


func _begin_end_card() -> void:
	if not in_end_card:
		in_end_card = true
		duck(END_DUCK_DB, END_DUCK_S)


## Plays a stinger once over the stems (which dip under it). Not twice within STINGER_GAP_S; false if there is none or it was too soon.
func stinger(name: String) -> bool:
	var p: AudioStreamPlayer = stingers.get(name)
	if p == null:
		return false
	if _t - float(_stinger_at.get(name, -1000.0)) < float(STINGER_GAPS.get(name, STINGER_GAP_S)):
		return false
	_stinger_at[name] = _t
	p.volume_db = 0.0
	p.play()
	duck(STINGER_DUCK_DB, p.stream.get_length() * 0.75)
	return true


## Dips the stems by `db` (the strongest dip asked for wins, to MAX_DUCK_DB) for `seconds`, then they come back over DUCK_RELEASE_S.
func duck(db: float, seconds: float) -> void:
	_duck_target = maxf(minf(_duck_target, minf(db, 0.0)), MAX_DUCK_DB)
	_duck_hold = maxf(_duck_hold, seconds)


## The dip now, all of it (an event's and the guns').
func total_duck_db() -> float:
	return maxf(duck_db + sfx_duck_db, MAX_DUCK_DB - SFX_MAX_DB)


# ------------------------------------------------------------------------- the stems --

## Whether any stem of a mood is playing.
func mood_playing(m: String) -> bool:
	for stem in MOODS.get(m, []):
		if players.has(stem) and players[stem].playing:
			return true
	return false


## The stems that are playing now (a name each).
func playing_stems() -> Array:
	var out: Array = []
	for stem in players:
		if players[stem].playing:
			out.append(stem)
	return out


## How whole a stem of the current mood should be now: 1 for a base, the layer's share of the threat for a layer; 0 for any other mood's.
func stem_target(stem: String) -> float:
	if not MOODS.get(mood, []).has(stem):
		return 0.0
	if not LAYERS.has(stem):
		return 1.0
	var r: Array = LAYERS[stem]
	return layer_share(threat, float(r[0]), float(r[1]))


func _start_mood(m: String) -> void:
	var stems: Array = MOODS.get(m, [])
	var offset := 0.0
	for stem in stems:
		if players.has(stem):
			offset = start_offset(players[stem].stream.get_length(), OS.has_feature("web"), _rng.randf())
			break
	for stem in stems:
		if players.has(stem):
			var p: AudioStreamPlayer = players[stem]
			p.volume_db = Buses.SILENT_DB
			p.play(offset)


func _update_duck(dt: float) -> void:
	if _duck_hold > 0.0:
		_duck_hold -= dt
	else:
		_duck_target = 0.0
	var k := 1.0 - exp(-dt / (DUCK_ATTACK_S if _duck_target < duck_db else DUCK_RELEASE_S))
	duck_db = lerpf(duck_db, _duck_target, k)
	if absf(duck_db) < 0.02 and _duck_target == 0.0:
		duck_db = 0.0
	# the guns: the SFX bus's peak, a dip that is taken quickly and let go slowly
	var want := 0.0
	if sfx_duck_on:
		var i := AudioServer.get_bus_index("SFX")
		if i >= 0:
			var peak := maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))
			want = -clampf((peak - SFX_FLOOR_DB) * SFX_SLOPE, 0.0, SFX_MAX_DB)
	var ks := 1.0 - exp(-dt / (0.04 if want < sfx_duck_db else 0.5))
	sfx_duck_db = lerpf(sfx_duck_db, want, ks)
	if absf(sfx_duck_db) < 0.02 and want == 0.0:
		sfx_duck_db = 0.0


func _process(dt: float) -> void:
	_t += dt
	_update_duck(dt)
	if mood != "" and not mood_playing(mood):
		_start_mood(mood)
	var current: Array = MOODS.get(mood, [])
	var dip := total_duck_db()
	for stem in players:
		var p: AudioStreamPlayer = players[stem]
		var want := stem_target(stem)
		var f: float = fade[stem]
		var seconds := FADE_S
		if current.has(stem) and LAYERS.has(stem):
			seconds = LAYER_UP_S if want > f else LAYER_DOWN_S
		f = move_toward(f, want, dt / seconds)
		fade[stem] = f
		if p.playing:
			# a quarter-power curve so two stems cross-fading do not dip in the middle
			p.volume_db = linear_to_db(maxf(sin(f * PI * 0.5) * LEVEL, 0.0001)) + (dip if f > 0.0005 else 0.0)
	# a mood that is not the current one is stopped when all of its stems are silent, all at once (so they stay in step if it returns)
	for m in MOODS:
		if m == mood or not mood_playing(m):
			continue
		var silent := true
		for stem in MOODS[m]:
			if players.has(stem) and float(fade[stem]) > 0.0005:
				silent = false
		if silent:
			for stem in MOODS[m]:
				if players.has(stem):
					players[stem].stop()
