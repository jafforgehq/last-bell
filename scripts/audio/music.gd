## The music: four loops (made by tools/make_music.py) that cross-fade as the mood of the game changes. `title` plays
## on the title screen and after the run is over, `day` by day, `night` after dusk and during a played trip, and
## `danger` while the dead are close to the walls. All four play on the `Music` bus, whose volume is the player's
## (Settings, Music); the HUD's sound button mutes Master, which this sits under.
##
## `follow` is called a few times a second with what the game looks like and picks the mood: the dead coming in
## (`horde` from 0 to 1) turns it to `danger` and it stays there for at least MIN_DANGER_S seconds, so a wave that
## flickers at the edge of the camera does not make the music jump about; the dark (`dark`, 0 to 1) turns it from `day`
## to `night`, with a gap between the two thresholds for the same reason. A track that has faded out is stopped, and
## one that comes back starts from a place in the loop of its own choosing, so the same bars are not heard every time.
extends Node

const Buses := preload("res://scripts/audio/buses.gd")

const TRACKS := {
	"title": "res://assets/audio/music_title.wav",
	"day": "res://assets/audio/music_day.wav",
	"night": "res://assets/audio/music_night.wav",
	"danger": "res://assets/audio/music_danger.wav",
}
## The seconds a cross-fade takes.
const FADE_S := 4.0
## How loud the music is at the Music slider's 1: well under the sounds of the game.
const LEVEL := 0.5
## The horde level (0 to 1) that turns the music to danger, and the one it has to fall below to leave it again.
const DANGER_ON := 0.55
const DANGER_OFF := 0.2
const MIN_DANGER_S := 14.0
## The darkness (0 to 1) at which `night` begins, and the one it has to fall below to be `day` again.
const NIGHT_ON := 0.4
const NIGHT_OFF := 0.28

## mood -> AudioStreamPlayer (only for the loops that were found)
var players := {}
## mood -> how far its volume has come (0 silent, 1 the whole of LEVEL)
var fade := {}
## What is wanted now ("" is none: everything fades out).
var mood := ""
var danger_s := 0.0
var is_night := false
var is_danger := false


func _ready() -> void:
	# the music goes on while a menu or a page has the game waiting
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup() -> void:
	Buses.ensure()
	for name in TRACKS:
		var path: String = TRACKS[name]
		if not ResourceLoader.exists(path):
			continue
		var s = load(path)
		if not s is AudioStreamWAV:
			continue
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		var p := AudioStreamPlayer.new()
		p.name = "Music_%s" % name
		p.bus = "Music"
		p.stream = s
		p.volume_db = Buses.SILENT_DB
		add_child(p)
		players[name] = p
		fade[name] = 0.0


## What the music should be for this state of the game. `in_run` is false on the title screen; `trip` is true while a
## played trip is open; `dark` and `horde` are as above; `dt` the seconds since the last call.
func follow(in_run: bool, trip: bool, dark: float, horde: float, dt: float) -> void:
	if not in_run:
		is_danger = false
		danger_s = 0.0
		set_mood("title")
		return
	if trip:
		is_danger = false
		danger_s = 0.0
		set_mood("night")
		return
	if is_danger:
		danger_s += dt
		if horde < DANGER_OFF and danger_s >= MIN_DANGER_S:
			is_danger = false
	elif horde >= DANGER_ON:
		is_danger = true
		danger_s = 0.0
	if is_night:
		if dark < NIGHT_OFF:
			is_night = false
	elif dark >= NIGHT_ON:
		is_night = true
	set_mood("danger" if is_danger else ("night" if is_night else "day"))


## The mood to cross-fade to: a name in TRACKS, or "" for none.
func set_mood(m: String) -> void:
	mood = m


func _process(dt: float) -> void:
	var step := dt / FADE_S
	for name in players:
		var p: AudioStreamPlayer = players[name]
		var f: float = fade[name]
		var want := 1.0 if name == mood else 0.0
		f = move_toward(f, want, step)
		fade[name] = f
		if f <= 0.0005 and want == 0.0:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play(randf() * maxf(0.0, p.stream.get_length() - 1.0))
		# a quarter-power curve so two tracks cross-fading do not dip in the middle
		p.volume_db = linear_to_db(maxf(sin(f * PI * 0.5) * LEVEL, 0.0001))
