## EXPERIMENT (prison round 12): the ENDINGS. The ending card (EVACUATED in four sizes, HELD THE FORT, OVERRUN, ABANDONED or STARVED, DEAD) with an epilogue built from what happened (the names of
## the people lost, the kills, the days, the nights held, the projects built), a score breakdown, the stats screen, New game and Quit, and the last-run record in user://prison_arc.json.
## The texts are in assets/data/prison_story.json (`endings`, `score`): a line may carry an `if` rule (lost, left, left_behind, dog, convoy_gone) and {placeholders}. The card is a Control that
## runs while the tree is paused (like the story card, prison_story.gd). Nothing here changes the game's rules: `prison_arc.gd` decides when an ending is reached and calls `show`.
extends RefCounted

const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const REC := "user://prison_arc.json"

var game
var arc
var root: Control
var last_score := 0
var last_lines: Array = []
var last_text := ""
var last_saved := 0


func _init(g, a) -> void:
	game = g
	arc = a


func is_open() -> bool:
	return root != null and is_instance_valid(root)


func _names(list: Array) -> String:
	list = list.map(func(n): return arc.dn(String(n)))
	if list.is_empty():
		return "nobody"
	if list.size() == 1:
		return String(list[0])
	return ", ".join(list.slice(0, list.size() - 1)) + " and " + String(list[list.size() - 1])


func _projects() -> int:
	var n := 0
	for id in game.econ.order:
		if bool(game.econ.st.get(id, {}).get("built", false)):
			n += 1
	return n


## The facts of the run, for the epilogue's placeholders and rules.
func facts(id: String, extra: Dictionary) -> Dictionary:
	var saved: Array = extra.get("saved", arc.alive_names())
	var lost: Array = arc.names_with("died")
	var walked: Array = arc.names_with("walked")
	var left_b: Array = extra.get("left", [])
	var days: int = mini(arc.day, arc.days()) if id == "held" or id == "held_bitter" or id.begins_with("evac") else arc.day
	var bonuses: Array = extra.get("bonuses", [])
	var has_dog := false
	for b in bonuses:
		if String(b.id) == "dog":
			has_dog = true
	return {
		"saved": saved.size(), "names_saved": _names(saved), "names_lost": _names(lost), "names_walked": _names(walked), "names_left": _names(left_b),
		"days": days, "kills": int(arc.stats.kills), "nights": int(arc.stats.nights_held), "projects": _projects(), "night": int(arc.stats.nights_held) + 1,    # (the night it fell is the one after the last night held)
		"if": {"lost": not lost.is_empty(), "left": not walked.is_empty(), "left_behind": not left_b.is_empty(), "dog": has_dog, "convoy_gone": String(arc.convoy) == "gone"},
		"saved_list": saved, "bonuses": bonuses}


## `[key|text when key is not 0|text when it is 0]` picks a sentence by a count (no "0 dead were shot"); "1 nights" reads "1 night".
func _fill(s: String, f: Dictionary) -> String:
	for m in RegEx.create_from_string("\\[(\\w+)\\|([^|\\]]*)\\|([^\\]]*)\\]").search_all(s):
		s = s.replace(m.get_string(0), m.get_string(2) if int(f.get(m.get_string(1), 0)) != 0 else m.get_string(3))
	for k in f:
		if f[k] is int or f[k] is String:
			s = s.replace("{%s}" % k, str(f[k]))
	for w in ["night", "day", "thing"]:
		s = RegEx.create_from_string("(?<!\\d)\\b1 %ss\\b" % w).sub(s, "1 " + w, true)
	return s


func epilogue(id: String, f: Dictionary) -> Array:
	var out: Array = []
	var e: Dictionary = arc.cfg.endings.get(id, {})
	for l in e.get("lines", []):
		if l is Dictionary:
			if not bool(f["if"].get(String(l["if"]), false)):
				continue
			out.append(_fill(String(l.text), f))
		else:
			out.append(_fill(String(l), f))
	return out


## The score: [[label, points]] and the total.
func score(id: String, f: Dictionary) -> Dictionary:
	var sc: Dictionary = arc.cfg.score
	var st: Dictionary = arc.stats
	var lines: Array = []
	var add := func(label: String, pts: float):
		lines.append([label, pts])
	var evac: bool = id.begins_with("evac")
	var n_saved := int(f.saved) if (evac or id == "held" or id == "held_bitter") else 0
	if n_saved > 0:
		add.call("%d people %s x %d" % [n_saved, "on the truck" if evac else "alive", int(sc.saved)], float(n_saved) * float(sc.saved))
	add.call("%d day%s x %d" % [f.days, "" if int(f.days) == 1 else "s", int(sc.day)], float(f.days) * float(sc.day))
	add.call("%d night%s held x %d" % [f.nights, "" if int(f.nights) == 1 else "s", int(sc.night)], float(f.nights) * float(sc.night))
	add.call("%d project%s built x %d" % [f.projects, "" if int(f.projects) == 1 else "s", int(sc.project)], float(f.projects) * float(sc.project))
	add.call("%d dead at the fence x %s" % [f.kills, str(sc.kill)], float(f.kills) * float(sc.kill))
	add.call("%d rescued x %d" % [int(st.rescues), int(sc.rescue)], float(int(st.rescues)) * float(sc.rescue))
	if int(st.deaths) > 0:
		add.call("%d died x %d" % [int(st.deaths), int(sc.death)], float(int(st.deaths)) * float(sc.death))
	if int(st.letters) > 0:
		add.call("%d letters read x %d" % [int(st.letters), int(sc.letter)], float(int(st.letters)) * float(sc.letter))
	if evac:
		add.call("The convoy took you", float(sc.evac) + float(sc.convoy_ready))
	elif id == "held" or id == "held_bitter":
		add.call("The fort held to the dawn", float(sc[id]))
	for b in f.bonuses:
		add.call(String(b.label), float(b.points) * float(sc.bonus))
	var total := 0.0    # (a lambda copies a number, so the sum is made here)
	for r in lines:
		total += float(r[1])
	return {"lines": lines, "total": int(maxf(0.0, total))}


func stats_rows() -> Array:
	var st: Dictionary = arc.stats
	return [["Days", min(arc.day, arc.days())], ["Nights held", int(st.nights_held)], ["Dead at the fence", int(st.kills)], ["Raids", int(st.raids)], ["Rescues", int(st.rescues)],
		["Deaths", int(st.deaths)], ["Walked out", int(st.left)], ["Scrap brought home", int(st.scrap)], ["Letters read", int(st.letters)], ["Fence walls lost", int(st.fence_lost)], ["Distance walked", "%d m" % int(st.dist)]]


func show(id: String, extra: Dictionary = {}) -> void:
	var e: Dictionary = arc.cfg.endings.get(id, {})
	if e.is_empty():
		return
	if arc.story.card_open():
		arc.story._close_card()
	var f := facts(id, extra)
	var lines := epilogue(id, f)
	var sc := score(id, f)
	last_score = int(sc.total)
	last_saved = int(f.saved)
	last_lines = lines
	last_text = "\n".join(lines)
	var rec := _record(id, int(sc.total), f)
	print("ENDING ", id, " score ", sc.total, " day ", arc.day, " saved ", f.saved, " kills ", f.kills, " deaths ", arc.stats.deaths)
	if game.args.has("arcauto") or game.args.has("econ-lab"):
		return
	_build(id, e, f, lines, sc, rec)


func show_test(id: String) -> void:
	var extra := {}
	if id.begins_with("evac"):
		var names: Array = arc.alive_names()
		extra = {"saved": names, "left": [], "bonuses": [arc.cfg.bonuses[0], arc.cfg.bonuses[3]]}
		if id == "evac_good" and names.size() > 2:
			extra["left"] = [names[names.size() - 1]]
	arc.ended_id = ""
	arc.end(id, extra)


func _build(id: String, e: Dictionary, f: Dictionary, lines: Array, sc: Dictionary, rec: Dictionary) -> void:
	var S = arc.story
	var tone := String(e.get("tone", "good"))
	var col := Hud.ACCENT if tone == "good" else (Hud.WARN if tone == "bitter" else Hud.DANGER_TEXT)
	var v: Vector2 = game._vp()
	root = Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.015, 0.93)    # (the world all but gone behind the card)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", S._box(Color(0.045, 0.065, 0.058, 0.99), col, 28, 8))
	centre.add_child(pc)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	pc.add_child(outer)
	var kick: Label = S._lab("DAY %d OF %d   %s   SEED %d" % [mini(arc.day, arc.days()), arc.days(), String(game.Bal.dm("name", "Standard")).to_upper(), game.Bal.run_seed], 16, Hud.INK3, true)
	kick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(kick)
	var big: Label = S._lab(String(e.title), 64, col, true)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(big)
	var sub: Label = S._lab(String(e.sub), 21, Hud.INK2)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(sub)
	var rule := ColorRect.new()
	rule.color = Hud.LINE2
	rule.custom_minimum_size = Vector2(0, 1)
	outer.add_child(rule)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 34)
	outer.add_child(cols)
	var narrow: bool = v.x < 1000.0
	var lw := minf(440.0, (v.x - 140.0) * (1.0 if narrow else 0.5))
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	for l in lines:
		var t: Label = S._lab(String(l), 18, Hud.INK, false)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(lw, 0)
		left.add_child(t)
	if not narrow:
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 4)
		cols.add_child(right)
		right.add_child(S._lab("SCORE", 16, col, true))
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 20)
		g.add_theme_constant_override("v_separation", 2)
		right.add_child(g)
		for r in sc.lines:
			if absf(float(r[1])) < 0.05:
				continue    # (a row worth nothing is left out: the card fits 720 px)
			g.add_child(S._lab(String(r[0]), 14, Hud.INK2))
			var pts := float(r[1])
			var pl: Label = S._lab("%+d" % roundi(pts) if absf(pts - roundf(pts)) < 0.05 else "%+.1f" % pts, 14, Hud.OK if pts >= 0.0 else Hud.DANGER_TEXT)
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			g.add_child(pl)
		var tot: Label = S._lab("TOTAL  %d" % int(sc.total), 24, col, true)
		right.add_child(tot)
		var best: Label = S._lab("best %d   runs %d" % [int(rec.best), int(rec.runs)], 14, Hud.INK3)
		right.add_child(best)
		right.add_child(S._lab("THE RUN", 16, col, true))
		var g2 := GridContainer.new()
		g2.columns = 4    # (two pairs a row, the zero rows left out: the card fits 720 px)
		g2.add_theme_constant_override("h_separation", 20)
		g2.add_theme_constant_override("v_separation", 2)
		right.add_child(g2)
		for r in stats_rows():
			if str(r[1]) == "0" or str(r[1]) == "0 m":
				continue
			g2.add_child(S._lab(String(r[0]), 14, Hud.INK2))
			var vl: Label = S._lab(str(r[1]), 14, Hud.INK)
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			g2.add_child(vl)
	var dead: Array = arc.memorial()    # META: who died, when, and how
	if not dead.is_empty():
		var wall := VBoxContainer.new()
		wall.add_theme_constant_override("separation", 2)
		left.add_child(wall)    # (under the epilogue: the right column and the buttons keep their room)
		wall.add_child(S._lab("THE LOST", 16, col, true))
		for d in dead.slice(0, 8):
			wall.add_child(S._lab("%s   day %d, %s" % [d.name, d.day, d.cause], 14, Hud.INK2))
		if dead.size() > 8:
			wall.add_child(S._lab("and %d more (the memorial wall in the Story tab)" % (dead.size() - 8), 14, Hud.INK3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var nb: Button = S._btn("New game")
	nb.pressed.connect(new_game)
	row.add_child(nb)
	var cb: Button = S._btn("Copy report")    # PLAYLOG hook: the run as text, to send to the owner
	cb.pressed.connect(func():
		arc.plog.copy_report()
		cb.text = "Copied. Send it to Fedja")
	row.add_child(cb)
	var qb: Button = S._btn("Quit")
	qb.pressed.connect(func(): game.get_tree().quit())
	row.add_child(qb)
	outer.add_child(row)
	if narrow:
		outer.add_child(S._lab("Score %d   (best %d)" % [int(sc.total), int(rec.best)], 16, col, true))
	S.layer.add_child(root)
	game.get_tree().paused = not game.args.has("shot")
	root.modulate.a = 0.0
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.9)
	game.sound.play("bell", 0.6, 0.0)


func new_game() -> void:
	game.get_tree().paused = false
	Engine.set_meta("run", {"difficulty": game.Bal.level, "seed": randi() % 900000 + 100000, "town": true})    # (the next run keeps the difficulty and takes a new seed)
	game.get_tree().reload_current_scene()


## The last run and the best one, in a tiny JSON file. Returns {best, runs}.
func _record(id: String, total: int, f: Dictionary) -> Dictionary:
	var rec := {"best": total, "runs": 1, "best_id": id}
	if game.args.has("nosave") or game.args.has("arcauto") or game.args.has("econ-lab"):
		return rec
	var rp := REC if String(game.args.get("savefile", "")) == "" else "user://%s.arc.json" % String(game.args.savefile).get_file()    # (a run with --savefile keeps its own record)
	if FileAccess.file_exists(rp):
		var old = JSON.parse_string(FileAccess.get_file_as_string(rp))
		if old is Dictionary:
			rec.runs = int(old.get("runs", 0)) + 1
			if int(old.get("best", 0)) >= total:
				rec.best = int(old.best)
				rec.best_id = String(old.get("best_id", id))
	var out := rec.duplicate()
	out["last"] = {"ending": id, "score": total, "days": f.days, "saved": f.saved, "kills": f.kills, "nights": f.nights, "date": Time.get_datetime_string_from_system()}
	var fa := FileAccess.open(rp, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(out))
	return rec
