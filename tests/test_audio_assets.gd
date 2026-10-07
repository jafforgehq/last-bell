extends "res://tests/case.gd"
## The generated audio (tools/make_score.py, make_bells.py, make_ambience.py, make_base_sounds.py): every file the code names is there,
## imported and loads; the numbers each generator wrote into assets/audio/audio_manifest.json are what is in the files; every loop closes
## (the step from its last sample to its first is not bigger than the steps inside it); the loudness is where the score says; and the stems
## of one mood are the same length, so that they stay in step.

const Music := preload("res://scripts/audio/music.gd")
const Sound := preload("res://scripts/audio/sound.gd")
const Soundscape := preload("res://scripts/audio/soundscape.gd")

const DIR := "res://assets/audio/"
const MANIFEST := "res://assets/audio/audio_manifest.json"
## How much bigger the step at a loop's seam may be than a normal step (the generators measure about 0 to 3.5; a click is 20 and more).
const SEAM_LIMIT := 6.0
## The new audio on disk (the sources: 16-bit WAV; the web build carries them as QOA, about a fifth of this) must stay under this many bytes. (The SOUND pass added 4 MB of source, 0.84 MB as QOA in the .pck: 24 became 28.)
const BUDGET_BYTES := 28 * 1024 * 1024


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## {"rate", "samples", "bytes", "pcm"}: the header and data of a 16-bit mono PCM wav (the source file, read straight).
func _wav(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_bytes(path)
	var out := {"rate": 0, "samples": 0, "bytes": raw.size(), "pcm": PackedByteArray(), "channels": 0, "bits": 0}
	if raw.size() < 44:
		return out
	out["channels"] = raw.decode_u16(22)
	out["rate"] = raw.decode_u32(24)
	out["bits"] = raw.decode_u16(34)
	var pos := 12
	while pos + 8 <= raw.size():
		var id := raw.slice(pos, pos + 4).get_string_from_ascii()
		var size := raw.decode_u32(pos + 4)
		if id == "data":
			out["pcm"] = raw.slice(pos + 8, mini(pos + 8 + size, raw.size()))
			out["samples"] = int(size / 2)
			break
		pos += 8 + size + (size & 1)
	return out


func _paths_the_code_names() -> Array:
	var out: Array = []
	for p in Music.TRACKS.values():
		out.append(p)
	for p in Music.STINGERS.values():
		out.append(p)
	for table in [Soundscape.BELLS, Soundscape.STEPS, Soundscape.GATE_SOUNDS, Soundscape.DOORS, Soundscape.FAR]:
		for key in table:
			for n in table[key]:
				out.append("%s%s.wav" % [Soundscape.DIR, n])
	for n in Soundscape.GROANS + Soundscape.ROARS:
		out.append("%s%s.wav" % [Soundscape.DIR, n])
	for table in [Soundscape.LOOPS, Soundscape.ENGINE]:
		for key in table:
			out.append("%s%s.wav" % [Soundscape.DIR, table[key]])
	for table in [Sound.UI_SOUNDS, Sound.CAR_SOUNDS, Sound.EXTRA]:
		for key in table:
			for p in table[key]:
				out.append(p)
	return out


func test_every_file_the_code_names_is_there_imported_and_loads() -> void:
	var seen := {}
	for path in _paths_the_code_names():
		if seen.has(path):
			continue
		seen[path] = true
		check(FileAccess.file_exists(path), "%s is a file" % path)
		check(ResourceLoader.exists(path), "%s is imported" % path)
		check(load(path) is AudioStreamWAV, "%s loads as a sound" % path)
	check(seen.size() >= 75, "the code names many files: %d" % seen.size())


func test_the_manifest_says_what_is_in_the_files() -> void:
	var m := _manifest()
	check(m.size() >= 70, "the manifest has the generated files: %d" % m.size())
	var total := 0
	for name in m:
		var e: Dictionary = m[name]
		var path := "%s%s.wav" % [DIR, name]
		var w := _wav(path)
		eq(int(w.rate), int(e.rate), "%s: the rate" % name)
		eq(int(w.samples), int(e.samples), "%s: the length in samples" % name)
		eq(int(w.channels), 1, "%s is mono" % name)
		eq(int(w.bits), 16, "%s is 16-bit" % name)
		eq(int(w.bytes), int(e.bytes), "%s: the size" % name)
		check(int(e.clipped) == 0, "%s does not clip" % name)
		check(float(e.peak_db) <= -3.0, "%s peaks at %.1f dBFS: an effect peaks at -3 or lower (the master limiter is at -0.5)" % [name, float(e.peak_db)])
		total += int(e.bytes)
	check(total <= BUDGET_BYTES, "the generated audio is %.1f MB on disk (the budget is %d MB)" % [total / 1048576.0, BUDGET_BYTES / 1048576])
	# the placeholder score it replaced is gone
	for old in ["music_title", "music_day", "music_night", "music_danger"]:
		check(not FileAccess.file_exists("%s%s.wav" % [DIR, old]), "%s is not in the project any more" % old)


func test_every_loop_closes() -> void:
	var m := _manifest()
	var loops := 0
	for name in m:
		var e: Dictionary = m[name]
		if not bool(e.loop):
			continue
		loops += 1
		check(float(e.seam) <= SEAM_LIMIT, "%s: the seam is %.2f (limit %.0f)" % [name, float(e.seam), SEAM_LIMIT])
		# and the file itself: the step from its last sample to its first against the steps in its first 4096 samples
		var w := _wav("%s%s.wav" % [DIR, name])
		var pcm: PackedByteArray = w.pcm
		var n := int(w.samples)
		var first := pcm.decode_s16(0)
		var last := pcm.decode_s16((n - 1) * 2)
		var acc := 0.0
		var prev := first
		var count := mini(4096, n - 1)
		for i in range(1, count):
			var v := pcm.decode_s16(i * 2)
			acc += float(v - prev) * float(v - prev)
			prev = v
		var typical := sqrt(acc / float(maxi(count - 1, 1))) + 1.0
		var step := absf(float(first - last))
		check(step <= typical * SEAM_LIMIT + 8.0, "%s: the file's seam step is %.0f LSB against a typical %.0f" % [name, step, typical])
	check(loops >= 18, "the loops are checked: %d" % loops)


func test_the_loudness_is_where_the_score_says() -> void:
	var m := _manifest()
	for stem in Music.TRACKS:
		var name := String(Music.TRACKS[stem]).get_file().get_basename()
		check(m.has(name), "%s is in the manifest" % name)
		if not m.has(name):
			continue
		var e: Dictionary = m[name]
		check(float(e.peak_db) <= -1.9, "%s peaks at %.1f dBFS" % [name, float(e.peak_db)])
		check(float(e.rms_db) >= -28.0 and float(e.rms_db) <= -17.0, "%s is %.1f dBFS RMS (a stem is -28 (the house, very quiet) to -17; the mood's sum is what the Music bus gets)" % [name, float(e.rms_db)])
		check(bool(e.loop) and float(e.seconds) >= 30.0, "%s is a loop of at least 30 s" % name)
	for name in Music.STINGERS.values():
		var e: Dictionary = m.get(String(name).get_file().get_basename(), {})
		check(not e.is_empty() and not bool(e.loop) and float(e.seconds) >= 6.0 and float(e.seconds) <= 14.0, "%s is a stinger of 6 to 14 s" % name)
	# the bells: near ones peak between -3 and -7, the far one under -10
	for n in ["bell_0", "bell_dusk_1", "bell_dusk_2", "bell_deep"]:
		var e: Dictionary = m.get(n, {})
		check(not e.is_empty() and float(e.peak_db) <= -3.4 and float(e.peak_db) >= -7.0, "%s peaks at %.1f dBFS" % [n, float(e.get("peak_db", 0.0))])
	check(float(m.get("bell_far", {}).get("peak_db", 0.0)) <= -10.0, "the far bell is quiet")


func test_the_stems_of_a_mood_are_one_length() -> void:
	for mood in Music.MOODS:
		var length := -1.0
		for stem in Music.MOODS[mood]:
			var s = load(Music.TRACKS[stem])
			if not s is AudioStreamWAV:
				check(false, "%s loads" % stem)
				continue
			if length < 0.0:
				length = s.get_length()
			near(s.get_length(), length, 0.002, "%s is as long as the rest of %s" % [stem, mood])
	# the loops' names go with the moods: every stem is a loop of a mood, every mood has a base
	for stem in Music.TRACKS:
		var found := false
		for mood in Music.MOODS:
			found = found or Music.MOODS[mood].has(stem)
		check(found, "%s belongs to a mood" % stem)
	for mood in Music.MOODS:
		check(not Music.LAYERS.has(Music.MOODS[mood][0]), "%s: the first stem is its base, always whole" % mood)
