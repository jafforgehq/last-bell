## Barks: the short lines people say when something happens (the bell, a wound, a
## friend down), from assets/data/barks.json: {person id: {context: [lines]}}. Rules only:
## it adds {"type": "bark", "who": id, "text": String, "context": String} events and the
## view draws them as speech bubbles.
##
## Contexts: bell (dusk), kill_streak (five kills in a minute), wounded, low_ammo,
## friend_down, breach, dawn (the night is over), skill_up, breakdown, and epitaph (a line
## said by the others about someone who has died or turned, kept for the dawn assembly:
## `epitaph(p)`).
##
## The rates: at most one bark a person every PERSON_GAP seconds and one anywhere every
## ANYONE_GAP, none while the game is over or in the tutorial, and none from someone dead,
## down or away. A person never says the line they said last time (they go through all of a
## context's lines before any comes round again). The few that matter (a friend down, a
## breakdown, an epitaph) wait their turn for up to QUEUE_KEEP seconds instead of being lost.
## The choices come from a generator of their own, never the rules' dice.
extends RefCounted

const DATA_PATH := "res://assets/data/barks.json"

## --- rates (seconds of rules time) ---
const PERSON_GAP := 25.0
const ANYONE_GAP := 6.0
## Five kills within a minute are a streak.
const STREAK_KILLS := 5
const STREAK_SECONDS := 60.0
## The same person says the same kind of thing again no sooner than this (seconds): a
## good shot has kill streaks all night, and a few of them are enough to hear.
const REPEAT_GAP := {"kill_streak": 120.0, "wounded": 60.0}
## What waits for its turn, for how long, and how many at most.
const QUEUED := ["friend_down", "breakdown", "epitaph"]
const QUEUE_KEEP := 30.0
const QUEUE_MAX := 4
const EPS := 1.0e-9

var sim
## Person id -> {context: [lines]}.
var lines := {}
## Person id -> sim.t of their last bark; and sim.t of the last bark by anyone.
var said_at := {}
var any_at := -1.0e9
## "id|context" -> sim.t of the last time they said this kind of thing (for REPEAT_GAP).
var said_kind := {}
## "id|context" -> the indices of the lines used in this round.
var used := {}
## Person id -> sim.t of their recent kills.
var streaks := {}
## What is waiting for its turn: [{"who": id, "text", "context", "until": sim.t}].
var queue: Array = []
var _memorial := {}
var _phase := "day"
var _rng := RandomNumberGenerator.new()


func setup(s) -> void:
	sim = s
	_load()
	_reset()


func start() -> void:
	_reset()


func _reset() -> void:
	said_at = {}
	said_kind = {}
	any_at = -1.0e9
	used = {}
	streaks = {}
	queue = []
	_memorial = {}
	_phase = sim.phase
	_rng.seed = _seed_for(int(sim.run_seed))


static func _seed_for(run_seed: int) -> int:
	return run_seed * 7919 + 104729


func _load() -> void:
	lines = {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		push_error("Could not read the barks from %s" % DATA_PATH)
		return
	for id in parsed:
		if not parsed[id] is Dictionary:
			continue
		var mine := {}
		for ctx in parsed[id]:
			var list: Array = []
			if parsed[id][ctx] is Array:
				for line in parsed[id][ctx]:
					if typeof(line) == TYPE_STRING and String(line) != "":
						list.append(String(line))
			if not list.is_empty():
				mine[String(ctx)] = list
		lines[String(id)] = mine


# ------------------------------------------------------------------- stepping --

## Every step: the dawn, and the barks waiting for their turn.
func update(_dt: float) -> void:
	if sim.phase != _phase:
		_phase = sim.phase
		if _phase == "dawn":
			_pick_someone("dawn")
	_flush()


## Someone able says what is waiting first, as soon as the rates allow.
func _flush() -> void:
	while not queue.is_empty():
		var e: Dictionary = queue[0]
		var p = _person(String(e.who))
		if sim.t > float(e.until) or p == null or not _able(p):
			queue.pop_front()
			continue
		if not _may_now(p, String(e.context)):
			return
		queue.pop_front()
		_emit(p, String(e.text), String(e.context))
		return


# -------------------------------------------------------------------- speaking --

## This person says something fitting for `context` (if they are able and it is not too soon
## after the last time; a few contexts wait for their turn instead).
func say(p, context: String) -> void:
	if p == null or context == "epitaph" or not _able(p) or _lines(p.id, context).is_empty():
		return
	if _may_now(p, context):
		_emit(p, _pick(p.id, context), context)
	elif QUEUED.has(context):
		_wait(p, _pick(p.id, context), context)


## Says `text` as `p` (a line already chosen): at once, or in its turn.
func _say_text(p, text: String, context: String) -> void:
	if not _able(p):
		return
	if _may_now(p, context):
		_emit(p, text, context)
	else:
		_wait(p, text, context)


func _emit(p, text: String, context: String) -> void:
	said_at[p.id] = sim.t
	if REPEAT_GAP.has(context):
		said_kind["%s|%s" % [p.id, context]] = sim.t
	any_at = sim.t
	sim.events.append({"type": "bark", "who": p.id, "text": text, "context": context})


func _wait(p, text: String, context: String) -> void:
	queue.append({"who": p.id, "text": text, "context": context, "until": sim.t + QUEUE_KEEP})
	while queue.size() > QUEUE_MAX:
		queue.pop_front()


## Whether this person can speak at all just now.
func _able(p) -> bool:
	if sim.over != "" or p.dead or p.downed or p.away != null or not lines.has(p.id):
		return false
	return not _in_tutorial()


## Whether the rates let this person say something of this kind now.
func _may_now(p, context: String = "") -> bool:
	if sim.t - float(said_at.get(p.id, -1.0e9)) < PERSON_GAP - EPS or sim.t - any_at < ANYONE_GAP - EPS:
		return false
	return sim.t - float(said_kind.get("%s|%s" % [p.id, context], -1.0e9)) >= float(REPEAT_GAP.get(context, 0.0)) - EPS


func _in_tutorial() -> bool:
	return sim.scenario != null and sim.scenario.has_method("jump") and sim.scenario.has_method("fire")


func _lines(id: String, context: String) -> Array:
	return lines.get(id, {}).get(context, [])


## A line of this person's for the context that is not the last one they used (all of them
## are used before any comes round again).
func _pick(id: String, context: String) -> String:
	var list: Array = _lines(id, context)
	if list.is_empty():
		return ""
	var key := "%s|%s" % [id, context]
	var done: Array = used.get(key, [])
	var fresh: Array = []
	for i in list.size():
		if not done.has(i):
			fresh.append(i)
	if fresh.is_empty():
		var last: int = int(done.back()) if not done.is_empty() else -1
		done = []
		for i in list.size():
			if i != last or list.size() == 1:
				fresh.append(i)
	var pick: int = fresh[_rng.randi() % fresh.size()]
	done.append(pick)
	used[key] = done
	return String(list[pick])


## One person who is able and may speak now, at random, says something for the context.
func _pick_someone(context: String) -> void:
	var ready: Array = []
	for p in sim.people:
		if _able(p) and _may_now(p, context) and not _lines(p.id, context).is_empty():
			ready.append(p)
	if not ready.is_empty():
		say(ready[_rng.randi() % ready.size()], context)


# ----------------------------------------------------------------- the moments --

## The bell has rung.
func on_bell() -> void:
	_pick_someone("bell")


## Ammo has run low.
func on_low_ammo() -> void:
	_pick_someone("low_ammo")


## A wall section has just fallen: whoever is nearest shouts.
func on_breach(seg) -> void:
	var best = null
	var best_d := INF
	for p in sim.people:
		if not _able(p) or not _may_now(p, "breach") or _lines(p.id, "breach").is_empty():
			continue
		var d := Vector2(p.x - seg.center.x, p.y - seg.center.y).length()
		if d < best_d:
			best_d = d
			best = p
	if best != null:
		say(best, "breach")


## `p` has just gone down: a friend of theirs calls it out.
func on_friend_down(p) -> void:
	var friend = _nearest_friend(p, "friend_down")
	if friend != null:
		say(friend, "friend_down")


## `p` put one of the dead down: five within a minute are a streak.
func on_kill(p) -> void:
	var times: Array = streaks.get(p.id, [])
	times.append(sim.t)
	while not times.is_empty() and sim.t - float(times[0]) > STREAK_SECONDS:
		times.pop_front()
	if times.size() >= STREAK_KILLS:
		times = []
		say(p, "kill_streak")
	streaks[p.id] = times


## `p` is gone for good (died or turned): their epitaph is chosen, kept for the dawn
## assembly, and said by someone who knew them (a friend, else whoever leads).
func on_lost(p) -> void:
	var line := _pick(p.id, "epitaph")
	if line == "":
		return
	_memorial[p.id] = line
	var speaker = _nearest_friend(p, "epitaph")
	if speaker == null:
		var lead := -1
		for q in sim.people:
			if q != p and _able(q) and int(q.skills.get("Leading", 0)) > lead:
				lead = int(q.skills.get("Leading", 0))
				speaker = q
	if speaker != null:
		_say_text(speaker, line, "epitaph")


## The line said about someone who has died or turned (for the dawn assembly and the memorial);
## "" for the living and for anyone who was sent out.
func epitaph(p) -> String:
	if p == null or not p.dead:
		return ""
	if _memorial.has(p.id):
		return String(_memorial[p.id])
	if p.away is Dictionary and p.away.get("kind", "") == "exile":
		return ""
	var list: Array = _lines(p.id, "epitaph")
	return String(list[0]) if not list.is_empty() else ""


## The friend of `p` who is able to speak: one who may speak now and is nearest, else the
## nearest (their line will wait).
func _nearest_friend(p, context: String):
	var best = null
	var best_ready := false
	var best_d := INF
	for b in sim.bonds.of(p):
		var q = b.who
		if q == p or not _able(q):
			continue
		var now := _may_now(q, context)
		var d := Vector2(q.x - p.x, q.y - p.y).length()
		if (now and not best_ready) or (now == best_ready and d < best_d):
			best = q
			best_ready = now
			best_d = d
	return best


func _person(id: String):
	for p in sim.people:
		if p.id == id:
			return p
	return null


# ----------------------------------------------------------------------- save --

func save() -> Dictionary:
	var said := {}
	for id in said_at:
		said[id] = float(said_at[id])
	var kinds := {}
	for key in said_kind:
		kinds[key] = float(said_kind[key])
	var rounds := {}
	for key in used:
		var list: Array = []
		for i in used[key]:
			list.append(int(i))
		rounds[key] = list
	var kills := {}
	for id in streaks:
		var times: Array = []
		for t in streaks[id]:
			times.append(float(t))
		kills[id] = times
	var waiting: Array = []
	for e in queue:
		waiting.append({"who": String(e.who), "text": String(e.text), "context": String(e.context), "until": float(e.until)})
	var memorial := {}
	for id in _memorial:
		memorial[id] = String(_memorial[id])
	return {
		"said_at": said, "said_kind": kinds, "any_at": any_at, "used": rounds, "streaks": kills, "queue": waiting,
		"memorial": memorial, "phase": _phase,
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
	}


## Restores what has been said and when, the lines used, the barks waiting, who has been
## spoken of and the generator. Anything that is not sound is ignored (a save from before
## barks has none of it).
func load_state(d: Dictionary) -> void:
	_reset()
	var said = d.get("said_at", {})
	if said is Dictionary:
		for id in said:
			if _person(String(id)) != null and _number(said[id]):
				said_at[String(id)] = float(said[id])
	var kinds = d.get("said_kind", {})
	if kinds is Dictionary:
		for key in kinds:
			var parts := String(key).split("|")
			if parts.size() == 2 and _person(parts[0]) != null and _number(kinds[key]):
				said_kind[String(key)] = float(kinds[key])
	if _number(d.get("any_at")):
		any_at = float(d.any_at)
	var rounds = d.get("used", {})
	if rounds is Dictionary:
		for key in rounds:
			if not rounds[key] is Array:
				continue
			var parts := String(key).split("|")
			if parts.size() != 2 or _lines(parts[0], parts[1]).is_empty():
				continue
			var done: Array = []
			for i in rounds[key]:
				if _number(i) and int(i) >= 0 and int(i) < _lines(parts[0], parts[1]).size() and not done.has(int(i)):
					done.append(int(i))
			used[String(key)] = done
	var kills = d.get("streaks", {})
	if kills is Dictionary:
		for id in kills:
			if _person(String(id)) == null or not kills[id] is Array:
				continue
			var times: Array = []
			for t in kills[id]:
				if _number(t):
					times.append(float(t))
			streaks[String(id)] = times
	var waiting = d.get("queue", [])
	if waiting is Array:
		for e in waiting:
			if e is Dictionary and typeof(e.get("who")) == TYPE_STRING and _person(String(e.who)) != null and typeof(e.get("text")) == TYPE_STRING and typeof(e.get("context")) == TYPE_STRING and _number(e.get("until")):
				queue.append({"who": String(e.who), "text": String(e.text), "context": String(e.context), "until": float(e.until)})
		while queue.size() > QUEUE_MAX:
			queue.pop_front()
	var memorial = d.get("memorial", {})
	if memorial is Dictionary:
		for id in memorial:
			if _person(String(id)) != null and typeof(memorial[id]) == TYPE_STRING and String(memorial[id]) != "":
				_memorial[String(id)] = String(memorial[id])
	if typeof(d.get("phase")) == TYPE_STRING and ["day", "dusk", "night", "dawn"].has(String(d.phase)):
		_phase = String(d.phase)
	var seed_text = d.get("rng_seed")
	var state_text = d.get("rng_state")
	if typeof(seed_text) == TYPE_STRING and String(seed_text).is_valid_int() and typeof(state_text) == TYPE_STRING and String(state_text).is_valid_int():
		_rng.seed = String(seed_text).to_int()
		_rng.state = String(state_text).to_int()


static func _number(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))
