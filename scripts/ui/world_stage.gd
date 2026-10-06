## Staging for the pictures of the WORLD feedback (scripts/ui/search_marks.gd, room_flash.gd): a screenshot has no player, so these flags put the town where the thing to look at is.
## Only a flag turns any of it on; a game without one never calls into it past the first test. The rules are used as the rules are (the session is begun with `uses.use` and run with
## `uses.update`, rooms are opened with `clearing.reveal` and `scan`); the only thing made up is the dead taken out of a room (`field.remove_record`), as `--stage=cleared` does.
##
##   --search=hold[:F]     the avatar goes to the nearest container of the house she is in that is not searched, begins the search and runs F (0.55) of it: the E prompt with the ring
##   --search=idle         the same, the search not begun (the prompt as it is first seen)
##   --search=done[:K]     the same, run to the end K (18) frames before the shot: the rummage, the tick on the container and the loot pop on its way to the stores
##   --claim=hold[:F]      after `--stage=cleared`: E at the claim spot, F (0.5) of its two seconds run: the ring on "Stop"
##   --looted=N[:stand]    the first N containers of her house are searched (their ticks), their rooms opened; `:stand` puts her at the first of them (the grey "Searched")
##   --roomclear=N[:K]     the first N rooms of her house are looked into and cleared, the last K (14) frames before the shot (the flash and the chip), the rest at once (their corner marks);
##                         `all` clears every room (the sweep, and the banner)
## Give them after `--stage=alone` (the dead of the house still in it) or `--stage=cleared`; they stop the clock (`main.speed = 0`) so that the picture stays where it was staged.
extends RefCounted

static var _parsed := false
static var _search := ""
static var _search_arg := -1.0
static var _claim := ""
static var _claim_arg := -1.0
static var _looted := 0
static var _looted_stand := false
static var _room_n := 0
static var _room_k := 14
static var _search_k := 18
static var _done := {}


static func _parse() -> void:
	_parsed = true
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--search="):
			var bits := a.trim_prefix("--search=").split(":")
			_search = bits[0]
			if bits.size() > 1 and bits[1].is_valid_float():
				_search_arg = float(bits[1])
		elif a.begins_with("--claim="):
			var bits4 := a.trim_prefix("--claim=").split(":")
			_claim = bits4[0]
			if bits4.size() > 1 and bits4[1].is_valid_float():
				_claim_arg = float(bits4[1])
		elif a.begins_with("--looted="):
			var bits3 := a.trim_prefix("--looted=").split(":")
			_looted = int(bits3[0])
			_looted_stand = bits3.size() > 1 and bits3[1] == "stand"
		elif a.begins_with("--roomclear="):
			var bits2 := a.trim_prefix("--roomclear=").split(":")
			_room_n = 999 if bits2[0] == "all" else int(bits2[0])
			if bits2.size() > 1 and bits2[1].is_valid_int():
				_room_k = int(bits2[1])
	if _search == "done" and _search_arg >= 0.0:
		_search_k = int(_search_arg)


## Called by search_marks.gd every frame with the frame's number.
static func on_frame(main, frame: int) -> void:
	if not _parsed:
		_parse()
	if _search == "" and _looted <= 0 and _room_n <= 0 and _claim == "":
		return
	var sim = main.get("sim")
	if sim == null or sim.get("houses") == null or sim.get("avatar") == null or sim.avatar.player() == null:
		return
	var shot := String(main.get("shot_path")) != ""
	var last: int = int(main.get("shot_frames")) if shot else 600
	var now: int = int(main.get("frame_count")) if shot else frame
	if now < 4:
		return
	main.speed = 0
	if _looted > 0 and not _done.has("looted"):
		_done["looted"] = true
		_mark_looted(sim, _looted)
	if _room_n > 0:
		var n := _room_n
		if n >= 999:
			n = sim.houses.rooms_of(_house_of_avatar(sim)).size()    # (`all`)
		if not _done.has("rooms_quiet"):
			_done["rooms_quiet"] = true
			_clear_rooms(sim, 0, n - 1)
		if now >= last - _room_k and not _done.has("rooms_last"):
			_done["rooms_last"] = true
			_clear_rooms(sim, n - 1, n)
	if _claim != "" and now >= 8 and not _done.has("claim"):
		_done["claim"] = true
		_claim_now(sim, _claim_arg if _claim_arg >= 0.0 else 0.5)
	if _search != "" and now >= (last - _search_k if _search == "done" else 8) and not _done.has("search"):
		_done["search"] = true
		_search_now(sim, _search == "done", _search_arg if _search == "hold" and _search_arg >= 0.0 else 0.55)


static func _house_of_avatar(sim) -> int:
	var me = sim.avatar.player()
	return int(sim.houses.house_at(me.x, me.y))


static func _mark_looted(sim, n: int) -> void:
	var h := _house_of_avatar(sim)
	if h < 0 or sim.get("search") == null:
		print("--looted: the avatar is not in a house (give --stage=alone or --stage=cleared)")
		return
	var i := 0
	for c in sim.houses.containers_of(h):
		if i >= n:
			break
		sim.search.looted[String(c.id)] = true
		var room := int(sim.houses.room_at(float(c.pos.x), float(c.pos.y)))
		if room >= 0 and sim.get("clearing") != null:
			sim.clearing.reveal(room, "stage")
		if i == 0 and _looted_stand:
			var me = sim.avatar.player()    # (`:stand`: she stands at the first of them, with nothing else to press: the grey "Searched")
			me.x = float(c.pos.x)
			me.y = float(c.pos.y)
			me.path = []
			me.moving = false
		i += 1


## The dead taken out of rooms `from` to `to` (exclusive) of the avatar's house, the rooms looked into, and the clearing module given its look (it tells `room_clear`, and `house_clear`).
static func _clear_rooms(sim, from: int, to: int) -> void:
	var h := _house_of_avatar(sim)
	var clearing = sim.get("clearing")
	var field = sim.get("field")
	if h < 0 or clearing == null or field == null:
		print("--roomclear: the avatar is not in a house (give --stage=alone)")
		return
	var rooms: Array = sim.houses.rooms_of(h)
	if to >= 999:
		to = rooms.size()    # (`all`)
	for k in range(from, mini(to, rooms.size())):
		var r := int(rooms[k])
		for i in field.n:
			if int(field.status[i]) == 0 and field.tile_room[floori(field.ys[i]) * field.W + floori(field.xs[i])] == r:
				field.remove_record(i)
		clearing.reveal(r, "stage")
	clearing.scan()


## E at the claim spot of the cleared house (give `--stage=cleared`): the claim's session begun and run F of its two seconds.
static func _claim_now(sim, frac: float) -> void:
	var me = sim.avatar.player()
	var uses = sim.get("uses")
	var base = sim.get("base")
	if base == null or uses == null:
		print("--claim: no base module")
		return
	for c in base.candidates(me):
		if String(c.kind) == "claim":
			var r: Dictionary = uses.use(c)
			if not bool(r.get("ok", false)):
				print("--claim: refused: %s" % String(r.get("why", "")))
				return
			var seconds := float(uses.progress().get("of", 2.0)) * clampf(frac, 0.0, 0.99)
			var t := 0.0
			while t < seconds and uses.busy():
				uses.update(1.0 / 30.0)
				t += 1.0 / 30.0
			return
	print("--claim: no claim candidate here (give --stage=cleared)")


static func _search_now(sim, to_the_end: bool, frac: float) -> void:
	var me = sim.avatar.player()
	var h := _house_of_avatar(sim)
	var search = sim.get("search")
	var uses = sim.get("uses")
	if h < 0 or search == null or uses == null:
		print("--search: the avatar is not in a house (give --stage=alone or --stage=cleared)")
		return
	var best := {}
	var best_d := INF
	for c in sim.houses.containers_of(h):
		if search.is_looted(String(c.id)):
			continue
		var d := Vector2(me.x, me.y).distance_to(Vector2(c.pos))
		if d < best_d:
			best = c
			best_d = d
	if best.is_empty():
		print("--search: no container left to search in this house")
		return
	me.x = float(best.pos.x)
	me.y = float(best.pos.y)
	me.path = []
	me.moving = false
	var room := int(sim.houses.room_at(me.x, me.y))
	if room >= 0 and sim.get("clearing") != null:
		sim.clearing.reveal(room, "stage")
	if _search == "idle":
		return    # (at the container, the search not begun: the prompt as it is first seen, with the pale ring that says it takes time)
	for c in search.candidates(me):
		if String(c.kind) == "container" and String(c.id) == String(best.id):
			var r: Dictionary = uses.use(c)
			if not bool(r.get("ok", false)):
				print("--search: refused: %s" % String(r.get("why", "")))
				return
			break
	var of := float(uses.progress().get("of", 4.0))
	var seconds := of + 0.5 if to_the_end else of * clampf(frac, 0.0, 0.99)
	var t := 0.0
	while t < seconds and uses.busy():
		uses.update(1.0 / 30.0)
		t += 1.0 / 30.0
