## The crew's cards say how each person is, at a glance (One House, HUDB): ONE small status chip in the bottom right corner of each card's picture, by priority, and a ring round
## the name of whoever you asked last. A VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`, `on_event(e)`); it adds its
## nodes to the HUD's own cards (`hud.cards`, scripts/ui/hud.gd) and never writes the rules.
##
## THE CHIP (17 px, dark disc with a ring in the colour of its meaning, a glyph of the game's own icon set in it; the first that is true wins):
##   down        the skull (grey): "Down, and bleeding out" (the lying figure, blue, when they are stable)
##   bleeding    the red drop            infected  the thermometer, red (feverish, delirious)
##   hurt        the cross: under HURT_AT of the health (amber, red under a quarter)
##   hungry      the fork and knife, or the glass for thirst (amber, red when it is costing health: starving, parched); the worse of the two
##   refusing    an amber hand: they would not do what you asked last (the radio's `radio_line` said no, or `radio.willingness` of the last order says no now), in their words
##   searching   the scavenger's bag (CREW): they are on a search of a house, an order of the wheel's "Search a house" or the Scavenger job: "Searching 22 Elm St: 3 of 6. Back when the house is done." (quiet, light grey)
##   at work     the icon of the station they are working at (the Duty roster's own): quiet, light grey
## THE CHIP'S COLOUR IS ALSO A SHAPE, always (UI polish): at its top right corner, by how bad it is (a diamond for danger, a triangle for a warning, a ring for "stable"; none for a quiet state), next to
## the glyph that says what it is. COLOUR-BLIND MARKERS (Settings, `Access.markers()`) add to the card's thin health bar quarter notches and, under HURT_AT, a dashed fill, so that the state of a person
## never rests on red against green.
## The chip has a tooltip of one line in the game's voice. Under the chip's glyph the card's foot row (`hud.cards[i].marks`) no longer repeats it: `hud.mark_filter` (a Callable:
## `(person, marks) -> marks`) drops the marks the chip stands for and leaves the rest.
## THE RING is a thin gold line round the person's name on the card: the people of `wheel_ctl.last_order.who` (Z asks them again).
##
## STAGING (a screenshot has no history): `--cardstate=who:what,...` (not `--crewstate`: anything that begins `--crew` is the school's crew size and puts the town away) with `who` an id or a first name (any case; `me` is the avatar; `#1` the first of the crew after her: the rescued have other names in every run) and `what` one of `bleed`, `infect`, `hurt`
## (28 percent), `down`, `stable` (down but stabilised), `hungry`, `starving`, `thirsty`, `parched`, `refuse`, `job` (a bench), `last` (the last order's target), `hold`/`follow` (a stance). It is
## applied once, a few frames in, after `--stage=`. `--hudb-cost` prints the CPU time of this part, the hurt pulse and the minimap per frame, a little before a screenshot.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")
const Access := preload("res://scripts/access.gd")
const CbShapes := preload("res://scripts/ui/cb_shapes.gd")

const CHIP_PX := 17.0
## How many marks the foot row keeps beside a chip (the chip is in the same corner row, on the right).
const MARKS_WITH_CHIP := 2
const GLYPH_PX := 11.0
const REFRESH_S := 0.1
## Under this share of the health the cross shows; under the second one it is red.
const HURT_AT := 0.40
const HURT_RED_AT := 0.25
## How long (the rules' seconds) a refusal on the radio is remembered if it still holds.
const REFUSE_FOR_S := 90.0
const DISC := Color(0.04, 0.08, 0.07, 0.93)
## Frames after which a staging flag is applied.
const STAGE_FRAME := 3

var main
var hud
## What the chip shows now, by person: {"id", "icon", "glyph", "color", "tip", "covers"} ({} for none).
var kinds := {}
## The nodes this part put on each card, by person: {"chip", "ring", "sig"}.
var nodes := {}
## Who refused on the radio and when: person id -> {"verb", "at", "line", "staged"}.
var refused := {}
## Ids of the people the last order went to (read from the command wheel).
var last_ids: Array = []
var _t := REFRESH_S
var _frames := 0
var _stage_spec := ""
var _stage_done := false
var _ring_box := StyleBoxFlat.new()
var _cost := false


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	hud.mark_filter = filter_marks
	_ring_box.bg_color = Color(0, 0, 0, 0)
	_ring_box.border_color = Color(hud.ACCENT, 0.95)
	_ring_box.set_border_width_all(1)
	_ring_box.set_corner_radius_all(7)
	_ring_box.anti_aliasing = true
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--cardstate="):
			_stage_spec = a.trim_prefix("--cardstate=")
		elif a == "--hudb-cost":
			_cost = true


func _sim():
	return main.get("sim") if main != null else null


# ------------------------------------------------------------------ the rules' words --

func on_event(e: Dictionary) -> void:
	if String(e.get("type", "")) != "radio_line":
		return
	var who := String(e.get("who", ""))
	if who == "":
		return
	if bool(e.get("ok", true)):
		refused.erase(who)
		return
	var sim = _sim()
	refused[who] = {"verb": String(e.get("verb", "")), "at": float(sim.t) if sim != null else 0.0, "line": String(e.get("line", "")), "staged": false}


# --------------------------------------------------------------------------- frames --

func on_frame(dt: float) -> void:
	if hud == null:
		return
	var t0 := Time.get_ticks_usec()
	_frames += 1
	if _stage_spec != "" and not _stage_done and _frames >= STAGE_FRAME and _frames % 5 == 0:
		_stage()
		_t = REFRESH_S
	_t += dt
	if _t >= REFRESH_S:
		_t = 0.0
		refresh()
	_cost_report(float(Time.get_ticks_usec() - t0))


## Reads the rules and brings the chips and rings of every card up to date (every REFRESH_S).
func refresh() -> void:
	var sim = _sim()
	if sim == null:
		return
	last_ids = _last_order_ids()
	for c in hud.cards:
		var p = c.p
		var k := kind_of(p, sim)
		kinds[p] = k
		var n: Dictionary = nodes.get(p, {})
		if n.is_empty():
			n = _make_nodes(c)
			nodes[p] = n
		_place(c, n)
		_apply(c, n, k)


func _last_order_ids() -> Array:
	var w = main.get("wheel_ctl")
	if w == null or not (w.get("last_order") is Dictionary):
		return []
	var who = (w.last_order as Dictionary).get("who", [])
	return who if who is Array else []


## What the chip of `p` shows now (see the header's order): {} for none, else {"id", "icon" (a name in the HUD's icons, "" for the hand), "glyph" ("" or "hand"), "color", "tip",
## "covers" (the names of the foot marks it stands for)}.
func kind_of(p, sim) -> Dictionary:
	if p.dead or p.turned or p.away != null:
		return {}
	var first := String(p.first)
	if p.downed:
		if bool(p.stabilised):
			return _k("stable", "down", hud.INFO, "Down, but stable. Let them rest.", ["down", "resting"])
		return _k("down", "turned", hud.INK3, "Down, and bleeding out. Somebody has to get to them.", ["down", "resting"])
	if float(p.bleeding) > 0.0:
		return _k("bleed", "wound", hud.DANGER, "Bleeding. It does not stop by itself.", ["wound"])
	var med = sim.get("medical")
	var stage: String = String(med.infection_stage(p)) if med != null and med.has_method("infection_stage") else ""
	if stage != "":
		var tip := "Delirious. It will not be long." if stage == "delirious" else "Feverish. The bite is working."
		return _k("infected", "fever", hud.DANGER, tip, ["fever"])
	var f := clampf(float(p.hp) / 100.0, 0.0, 1.0)
	if f < HURT_AT:
		return _k("hurt", "meds", hud.DANGER if f < HURT_RED_AT else hud.WARN, "Hurt, %d%% left. Keep them out of the way." % roundi(f * 100.0), [])
	var need := _need(p, sim)
	if not need.is_empty():
		return need
	var no := _refusal(p, sim)
	if not no.is_empty():
		return _k("refuse", "", hud.WARN, String(no.tip), [], "hand")
	var cs = sim.get("crew_search")
	if cs != null and not p.player and hud.icons.has("scavenge"):
		# (CREW: on a search of a house, an order or the Scavenger's job: where, how far they are, and that they come back when the house is done)
		var said: String = cs.run_text(p)
		if said != "":
			return _k("search", "scavenge", hud.INK2, "%s. Back when the house is done." % said, ["scavenge"])
	var jobs = sim.get("jobs")
	if jobs != null and not p.player and String(p.work) != "":
		var st: Dictionary = jobs.station(jobs.job_of(p))
		if not st.is_empty() and hud.icons.has(String(st.get("icon", ""))):
			return _k("job", String(st.icon), hud.INK2, "%s. Best left to it." % String(st.get("what", st.get("name", "At work"))), [String(st.icon)])
	return {}


func _k(id: String, icon: String, color: Color, tip: String, covers: Array, glyph: String = "") -> Dictionary:
	return {"id": id, "icon": icon, "glyph": glyph, "color": color, "tip": tip, "covers": covers}


## Hunger or thirst, the worse of the two (by how far each is from the point where it costs health): {} when neither has begun.
func _need(p, sim) -> Dictionary:
	var sup = sim.get("supplies")
	if sup == null:
		return {}
	var hunger := float(p.hunger_h)
	var thirst := float(p.thirst_h)
	var h_ratio := hunger / float(sup.STARVING_H) if hunger >= float(sup.HUNGRY_H) else 0.0
	var t_ratio := thirst / float(sup.PARCHED_H) if thirst >= float(sup.THIRSTY_H) else 0.0
	if h_ratio <= 0.0 and t_ratio <= 0.0:
		return {}
	if h_ratio >= t_ratio:
		if hunger >= float(sup.STARVING_H):
			return _k("starving", "starving", hud.DANGER, "Starving. It is costing them health.", ["starving", "hungry"])
		return _k("hungry", "hungry", hud.WARN, "Hungry. No proper meal in %d hours." % int(hunger), ["hungry", "starving"])
	if thirst >= float(sup.PARCHED_H):
		return _k("parched", "thirsty", hud.DANGER, "Parched. It is costing them health.", ["thirsty"])
	return _k("thirsty", "thirsty", hud.WARN, "Thirsty. Nothing to drink in %d hours." % int(thirst), ["thirsty"])


## {"tip"} when `p` would not do what you asked last (a refusal on the radio that still holds, or the last order's own `willingness` says no now), else {}.
func _refusal(p, sim) -> Dictionary:
	if p.player:
		return {}
	var radio = sim.get("radio")
	if radio == null or not radio.has_method("willingness"):
		return {}
	var id := String(p.id)
	var rec = refused.get(id)
	if rec != null:
		if bool(rec.staged):
			return {"tip": _refusal_tip(String(rec.line), "")}
		if float(sim.t) - float(rec.at) > REFUSE_FOR_S:
			refused.erase(id)
		elif radio.VERBS.has(String(rec.verb)):
			var w: Dictionary = radio.willingness(p, String(rec.verb))
			if bool(w.get("ok", false)):
				refused.erase(id)
			else:
				return {"tip": _refusal_tip(String(w.get("line", rec.line)), String(w.get("why", "")))}
	if last_ids.has(id):
		var w2 = main.wheel_ctl.last_order
		var verb := String(w2.get("verb", ""))
		if radio.VERBS.has(verb):
			var w3: Dictionary = radio.willingness(p, verb)
			if not bool(w3.get("ok", true)):
				return {"tip": _refusal_tip(String(w3.get("line", "")), String(w3.get("why", "")))}
	return {}


## "Will not: \"Tending a patient, can't come.\"": their own words when they have some, else the radio's reason after its colon.
func _refusal_tip(line: String, why: String) -> String:
	var words := line.strip_edges()
	if words == "" and why != "":
		words = why.get_slice(": ", 1) if why.contains(": ") else why
		words = words.substr(0, 1).to_upper() + words.substr(1)
		if not words.ends_with("."):
			words += "."
	if words == "":
		return "Will not do what you asked."
	return "Will not do what you asked: \"%s\"" % words


## The foot row of a card without the marks the chip already shows (`hud.mark_filter`).
func filter_marks(p, marks: Array) -> Array:
	if marks.is_empty():
		return marks
	var sim = _sim()
	if sim == null:
		return marks
	var t0 := Time.get_ticks_usec() if _cost else 0
	var k := kind_of(p, sim)
	var covers: Array = k.get("covers", [])
	var out: Array = marks
	if not covers.is_empty():
		out = []
		for m in marks:
			if not covers.has(String(m.get("icon", ""))):
				out.append(m)
	if not k.is_empty() and out.size() > MARKS_WITH_CHIP:
		out = out.slice(0, MARKS_WITH_CHIP)    # (the foot row ends where the chip begins)
	if _cost:
		cost_us += float(Time.get_ticks_usec() - t0)
	return out


# ---------------------------------------------------------------------------- nodes --

func _make_nodes(c: Dictionary) -> Dictionary:
	var chip := Control.new()
	chip.name = "StatusChip"
	chip.size = Vector2(CHIP_PX, CHIP_PX)
	chip.custom_minimum_size = chip.size
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.visible = false
	chip.draw.connect(_draw_chip.bind(chip))
	c.card.add_child(chip)
	var ring := Control.new()
	ring.name = "LastOrderRing"
	ring.mouse_filter = Control.MOUSE_FILTER_PASS
	ring.visible = false
	ring.tooltip_text = "You asked them last. Z asks again."
	ring.draw.connect(_draw_ring.bind(ring))
	c.card.add_child(ring)
	# the health bar's pattern (Colour-blind markers): over the bar, nothing drawn unless it is on
	var pattern := Control.new()
	pattern.name = "HpPattern"
	pattern.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pattern.draw.connect(_draw_pattern.bind(pattern, c))
	c.card.add_child(pattern)
	return {"chip": chip, "ring": ring, "pattern": pattern, "sig": ""}


## Puts the chip in the picture's bottom right corner and the ring round the name, again when the card was laid out anew. (The top of the picture is the stance's word, "Following",
## which is as wide as the card, and "YOU"; the bottom left is the foot row of marks; the town has no key digit in the bottom right.)
func _place(c: Dictionary, n: Dictionary) -> void:
	var card: Control = c.card
	var inset: Vector4 = hud._card_inset()
	var sig := "%s|%s|%s" % [str(card.size), str(c.name.position), str(c.name.size)]
	if sig == String(n.sig):
		return
	n["sig"] = sig
	var pw: float = card.size.x - inset.x - inset.z
	var chip: Control = n.chip
	chip.position = Vector2(inset.x + pw - CHIP_PX - 1.0, inset.y + pw - CHIP_PX - 1.0)
	var pattern: Control = n.pattern
	pattern.position = c.hp_bg.position
	pattern.size = c.hp_bg.size
	var ring: Control = n.ring
	var font: Font = Fonts.cond(600)
	var fs: int = int(c.name.get_theme_font_size("font_size"))
	var text_w: float = font.get_string_size(String(c.p.first), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w: float = minf(text_w + 12.0, pw)
	var h := 16.0
	ring.size = Vector2(w, h)
	ring.position = Vector2(inset.x + (pw - w) * 0.5, c.name.position.y + (c.name.size.y - h) * 0.5)
	ring.queue_redraw()


func _apply(c: Dictionary, n: Dictionary, k: Dictionary) -> void:
	var chip: Control = n.chip
	var was: Dictionary = chip.get_meta("kind", {})
	var show := not k.is_empty()
	if chip.visible != show:
		chip.visible = show
	var cb := Access.markers()
	if show and (was.get("id", "") != k.id or was.get("color", Color.BLACK) != k.color or bool(chip.get_meta("cb", false)) != cb):
		chip.set_meta("kind", k)
		chip.set_meta("cb", cb)
		chip.queue_redraw()
	# (the health bar's pattern: redrawn while the setting is on, and once when it goes off)
	var pattern: Control = n.pattern
	if cb or bool(pattern.get_meta("cb", false)):
		pattern.set_meta("cb", cb)
		pattern.queue_redraw()
	if show and chip.tooltip_text != String(k.tip):
		chip.tooltip_text = String(k.tip)
	var ring: Control = n.ring
	var on: bool = last_ids.has(String(c.p.id)) and not c.p.dead and not c.p.player
	if ring.visible != on:
		ring.visible = on
		ring.queue_redraw()


func _draw_chip(chip: Control) -> void:
	var k: Dictionary = chip.get_meta("kind", {})
	if k.is_empty():
		return
	var c := chip.size * 0.5
	var r := chip.size.x * 0.5 - 0.5
	var col: Color = k.color
	chip.draw_circle(c, r, DISC)
	chip.draw_arc(c, r - 0.8, 0.0, TAU, 24, Color(col, 0.95), 1.6, true)
	if String(k.glyph) == "hand":
		_draw_hand(chip, c, col)
		_draw_badge(chip, k)
		return
	var tex: Texture2D = hud.icons.get(String(k.icon))
	if tex != null:
		chip.draw_texture_rect(tex, Rect2(c - Vector2(GLYPH_PX, GLYPH_PX) * 0.5, Vector2(GLYPH_PX, GLYPH_PX)), false, col)
	_draw_badge(chip, k)    # (a shape for how bad it is, whatever the setting)


## The shape of how bad a chip is, at its top right corner (always: the colour-blind setting only adds the health bar's pattern): a diamond for danger, a triangle for a warning, a ring for fine-but-resting; none when quiet.
func _draw_badge(ci: CanvasItem, k: Dictionary) -> void:
	var shape := badge_of(k)
	if shape != "":
		CbShapes.mark(ci, shape, Vector2(CHIP_PX - 1.0, 2.5), 4.2, k.color)


## "diamond", "triangle", "circle" or "" for a chip kind: by its colour (the red, the amber, the blue, or the greys of down and at work).
func badge_of(k: Dictionary) -> String:
	if k.is_empty():
		return ""
	var col: Color = k.color
	if col == hud.DANGER or String(k.id) == "down":
		return "diamond"
	if col == hud.WARN:
		return "triangle"
	if col == hud.INFO:
		return "circle"
	return ""


## The health bar's pattern (Colour-blind markers): quarter notches, and the fill cut into dashes while the health is under HURT_AT.
func _draw_pattern(pattern: Control, c: Dictionary) -> void:
	if not Access.markers() or c.is_empty():
		return
	var w := pattern.size.x
	var h := pattern.size.y
	var dark := Color(0.02, 0.04, 0.035, 0.85)
	var fill_w: float = (c.hp as Control).size.x
	if fill_w > 0.0 and fill_w < w * HURT_AT + 0.5:
		var x := 2.0
		while x < fill_w:
			pattern.draw_rect(Rect2(x, 0.0, 1.5, h), dark)
			x += 3.5
	for i in 3:
		var nx := w * 0.25 * float(i + 1)
		pattern.draw_rect(Rect2(nx - 0.5, 0.0, 1.0, h), Color(0.97, 0.96, 0.9, 0.9) if nx > fill_w else dark)


## An open hand, flat, fingers up (the game's icon set has none): a palm, four fingers and a thumb, in 11 px.
func _draw_hand(ci: CanvasItem, c: Vector2, col: Color) -> void:
	var o := c + Vector2(-0.2, 0.6)
	ci.draw_rect(Rect2(o + Vector2(-3.0, -0.3), Vector2(6.0, 5.0)), col)
	var heights := [3.6, 4.8, 5.2, 4.0]
	for i in 4:
		var x := -3.0 + float(i) * 1.55
		ci.draw_rect(Rect2(o + Vector2(x, -0.3 - float(heights[i])), Vector2(1.25, float(heights[i]) + 0.4)), col)
	var thumb := PackedVector2Array([o + Vector2(-3.0, 1.2), o + Vector2(-4.9, -0.6), o + Vector2(-4.1, -1.4), o + Vector2(-3.0, 0.0)])
	ci.draw_colored_polygon(thumb, col)


func _draw_ring(ring: Control) -> void:
	ring.draw_style_box(_ring_box, Rect2(Vector2.ZERO, ring.size))


# -------------------------------------------------------------------------- staging --

func _person(who: String):
	var sim = _sim()
	var w := who.strip_edges().to_lower()
	if w == "me" or w == "you":
		return sim.avatar.player()
	if w.begins_with("#") and w.substr(1).is_valid_int():
		# (the rescued are made anew in each run, with other names: `#2` is the second of the crew after the avatar, in the cards' order)
		var n := 0
		for p in sim.people:
			if not p.player:
				n += 1
				if n == int(w.substr(1)):
					return p
		return null
	for p in sim.people:
		if String(p.id).to_lower() == w or String(p.first).to_lower() == w:
			return p
	return null


## Applies the entries of `--cardstate` whose person is there (the rescued come in a few seconds after `--stage=fourth`); `_stage_spec` keeps the ones still to do.
func _stage() -> void:
	var sim = _sim()
	if sim == null:
		return
	var left: Array = []
	for entry in _stage_spec.split(","):
		var kv := String(entry).split(":")
		if kv.size() != 2:
			continue
		var p = _person(kv[0])
		if p == null:
			left.append(String(entry))
			continue
		match kv[1]:
			"bleed":
				p.bleeding = 2.0
				p.wounds = 1
			"infect":
				p.infected_at = float(sim.clock_min) - 20.0 * 60.0
				p.turn_at = float(sim.clock_min) + 600.0
			"hurt":
				p.hp = 28.0
			"down":
				p.downed = true
				p.stabilised = false
			"stable":
				p.downed = true
				p.stabilised = true
			"hungry":
				p.hunger_h = 20.0
			"starving":
				p.hunger_h = 40.0
			"thirsty":
				p.thirst_h = 16.0
			"parched":
				p.thirst_h = 26.0
			"refuse":
				refused[String(p.id)] = {"verb": "come", "at": float(sim.t), "line": "Tending a patient, can't come.", "staged": true}
			"job":
				if sim.jobs.assign(p, "bench"):
					p.work = "bench"
			"last":
				var w = main.get("wheel_ctl")
				if w != null:
					w._remember_at("come", null, "", [String(p.id)])
			"hold", "follow":
				p.stance = kv[1]
			_:
				print("--cardstate: no such state %s" % kv[1])
	_stage_spec = ",".join(left)
	_stage_done = left.is_empty()


# ----------------------------------------------------------------------------- cost --

## `--hudb-cost`: frames 60 on are measured (the first ones load things); the line is printed two frames before the screenshot.
func _cost_report(this_us: float) -> void:
	if not _cost or String(main.get("shot_path")) == "":
		return
	var parts: Array = [self, main.town.part("hurt_pulse"), main.town.part("minimap")]
	var frame := int(main.get("frame_count"))
	if frame == 60:
		for part in parts:
			if part != null:
				part.cost_us = 0.0
				part.cost_frames = 0
		cost_us = this_us
	elif frame > 60:
		cost_us += this_us
	if frame == int(main.get("shot_frames")) - 2:
		var line := "hudb cost per frame (microseconds, CPU, GDScript):"
		for part in parts:
			if part != null:
				line += "  %s %.1f" % [String(part.get_script().resource_path).get_file().get_basename(), part.cost_us / maxf(1.0, float(maxi(1, int(frame) - 60)))]
		print(line)


var cost_us := 0.0
var cost_frames := 0
