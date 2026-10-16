## SURVIVOR BARKS (prison, managed base): each survivor says at most one short line a game day, as a speech bubble over their head, chosen by the state of the base
## (assets/data/prison_barks.json: a new recruit, after a horde, low water or food, low morale, a busy cleaner, a quiet night). One bubble shows at a time; none during a raid,
## an attack, a card or the morning card. Owned by prison_game.gd (`barks`); `update(dt)` every frame, `paint(c)` into the world overlay.
extends RefCounted

const PATH := "res://assets/data/prison_barks.json"

var game
var cfg: Dictionary = {}
var said := {}    # person id -> the day they spoke
var cur := {}    # {id, text, t}: the bubble on show
var _gap := 4.0
var _rescued := -1    # people.rescued at the last look: a rise is a new recruit
var _new_id := ""
var _last := {}    # what was said last (checks)


func _init(g) -> void:
	game = g
	var p = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	cfg = p if p is Dictionary else {}


## True when nothing else has the player's attention: a raid, an attack, a card, a window.
func _quiet() -> bool:
	if game.phase != "managed" or game.mode != "base" or game.busy or game.siege.attacking:
		return false
	if game.arc.story.card_open() or game.siege._card.visible or game.loadout.is_open or game.pause_menu.is_open():
		return false
	return not (game.board.is_open() or game.arc.endings.is_open())    # (is_open covers the window and the morning card)


func update(dt: float) -> void:
	if cfg.is_empty() or game.people == null:
		return
	if _rescued >= 0 and game.people.rescued > _rescued and not game.people.recruits.is_empty():
		_new_id = String(game.people.recruits.back().get("id", ""))
	_rescued = game.people.rescued
	if not cur.is_empty():
		cur.t = float(cur.t) - dt
		if float(cur.t) <= 0.0 or not _quiet() or _member(String(cur.id)).is_empty():
			cur = {}
		return
	_gap -= dt
	if _gap > 0.0 or not _quiet():
		return
	_gap = float(cfg.every)
	var day: int = int(game.arc.day)
	var h: float = fposmod(float(game.tod), 24.0)
	for st in cfg.order:
		if not _applies(String(st), h):
			continue
		var m := _speaker(String(cfg.states[st].who), day)
		if m.is_empty():
			continue
		var lines: Array = cfg.states[st].lines
		var n: int = hash([int(game.arc.run_seed), day, String(m.def.id), String(st)]) % lines.size()
		say(String(m.def.id), String(lines[absi(n)]), String(st))
		if String(st) == "new_recruit":
			_new_id = ""
		return


## Whether state `st` holds now (`h`: the hour).
func _applies(st: String, h: float) -> bool:
	match st:
		"new_recruit":
			return _new_id != ""
		"after_horde":
			return h >= 6.6 and h < 14.0 and int(game.siege.stats.get("killed", 0)) >= 5
		"low_water", "low_food":
			var d: float = float(game.econ.daily_report().res[st.trim_prefix("low_")].days)
			return d >= 0.0 and d < float(cfg.low_days)
		"low_morale":
			return float(game.econ.morale) < float(cfg.low_morale)
		"cleaner_busy":
			return game.cleaner != null and game.cleaner.piles() >= int(cfg.piles)
		"quiet_night":
			return (h >= 20.5 or h < 4.5) and not game.siege.attacking and not game.arc.is_horde_night(int(game.arc.day))
	return false


## A member who has not spoken today and fits `who` ({} when none).
func _speaker(who: String, day: int) -> Dictionary:
	var pool: Array = []
	for m in game.crew.members:
		if m.def.has("ally") or m.def.has("play") or String(m.state) == "downed" or int(said.get(String(m.def.id), -1)) == day:
			continue
		var ok := true
		match who:
			"newest":
				ok = String(m.def.id) == _new_id
			"cook":
				ok = String(game.econ.cfg.crew_role.get(String(m.def.id), "")) == "cook"
			"cleaner":
				ok = game.cleaner != null and game.cleaner._is_cleaner(m)
			"guard":
				ok = m.def.has("stand")
		if ok:
			pool.append(m)
	if pool.is_empty() and (who == "cook" or who == "guard"):
		return _speaker("any", day)    # (nobody of that job: anybody says it)
	if pool.is_empty():
		return {}
	return pool[absi(hash([int(game.arc.run_seed), day, who])) % pool.size()]


func _member(id: String) -> Dictionary:
	for m in game.crew.members:
		if String(m.def.id) == id:
			return m
	return {}


## Puts `text` over the head of `id` (also the entry point of a check).
func say(id: String, text: String, why: String = "") -> void:
	cur = {"id": id, "text": text, "t": float(cfg.show)}
	said[id] = int(game.arc.day)
	_last = {"id": id, "text": text, "why": why, "day": int(game.arc.day)}
	if game.args.has("log"):
		print("BARK ", id, " ", why, " '", text, "' day ", game.arc.day)


## The bubble in screen space (prison_tags.gd draws it on the HUD, over the night): above the name tag, a dark outline round a light fill. `to_scr` turns a tile position into a screen one.
func paint(c: CanvasItem, to_scr: Callable) -> void:
	if cur.is_empty():
		return
	var m := _member(String(cur.id))
	if m.is_empty():
		return
	var font := ThemeDB.fallback_font
	var fs := 15
	var w: float = font.get_string_size(String(cur.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18.0
	var a: float = clampf(float(cur.t) / 0.6, 0.0, 1.0)
	var sc := float(m.def.get("scale", 1.0))
	var at: Vector2 = to_scr.call(Vector2(m.p.x, m.p.y - 1.55 * sc)) + Vector2(0, -42)    # (over the icon, the state word and the name line)
	var box := Rect2(at + Vector2(-w / 2.0, -26), Vector2(w, 26))
	c.draw_rect(box.grow(2.0), Color(0.08, 0.08, 0.07, 0.9 * a))
	c.draw_rect(box, Color(0.97, 0.95, 0.86, 0.96 * a))
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 0), at + Vector2(6, 0), at + Vector2(0, 9)]), Color(0.97, 0.95, 0.86, 0.96 * a))
	c.draw_string(font, box.position + Vector2(9, 19), String(cur.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.12, 0.1, 0.08, a))
