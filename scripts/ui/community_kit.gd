## What the views show of the community (round 20, slice 4): who is close to whom and who is at odds, the title someone has earned
## (the medic, the engineer, the marksman, the scout), how a person's ideas have gone, and the one people turn to. The rules are three
## modules of the sim: `sim.relations` (scripts/sim/relations.gd), `sim.specialists` (specialists.gd) and `sim.initiative`
## (initiative.gd); the contract the views read is docs/superpowers/plans/2026-10-03-round-20.md, S4.1 to S4.3. The views are the HUD's
## person panel and crew card (hud.gd), the call view's opinion line (call_view.gd) and the News's kinds (radio_kit.gd); this file is
## what they share. Everything here is a static function and keeps no state.
##
## Every read goes through `module(sim, name)`: a module that is not there, has no such method, or is switched off (`active()`
## false: no avatar, Orientation Day, a classic start) is nothing here, so an older fake, a classic game and the tutorial get no row,
## no chip, no line and no error. Nothing is stored and nothing is asked of a module that is not in its contract.
extends RefCounted

const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## The gold of a title's chip: the pill frame is a paper stamp, and this tint makes it gold.
const GOLD_TINT := Color(1.0, 0.82, 0.35)
## The side margins of the title's chip (a trait's chip has 7): Marksman, Steady hands and Quick learner are the widest row there can be
## and make 298 px of the panel's 300 (tests/test_community_view.gd sweeps every pair of traits under every title).
const CHIP_PAD := 4

## What a title's multipliers say, by the key `specialists.mult(p, key)` is asked for, in the traits' own wording (traits.json's
## blurbs): used only when the module gives no words of its own (`title_of(p).bonus`, which the real one does), so that a module that
## keeps to the contract's four fields is still told in numbers. Read in this order.
const MULT_WORDS := [
	["bandage", "Bandages %d%% faster"],
	["repair", "Mends walls %d%% faster"],
	["craft", "makes ammo %d%% faster"],
	["aim", "Shots land %d%% more often"],
]
## What a title adds, by the key of `specialists.add(p, key)`.
const ADD_WORDS := [
	["cure", "a cure is %d%% more likely to work"],
]
## The scout's: what `specialists.party_mult([p])` says of a party with them in it.
const PARTY_WORDS := "Trips bring home %d%% more"


# ----------------------------------------------------------------------- reading --

## The module `name` of the game ("relations", "specialists", "initiative") when it is there and at work, else null.
static func module(sim, name: String):
	if sim == null:
		return null
	var m = sim.get(name)
	if m == null or not (m is Object):
		return null
	if m.has_method("active") and not bool(m.active()):
		return null
	return m


static func _day(sim) -> int:
	var d = sim.get("day") if sim != null else null
	return int(d) if d != null else 0


## The first letter in a capital ("the medic" is "The medic"; String.capitalize would make it "The Medic").
static func _cap(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else ""


static func _signed(x: float) -> String:
	return "%+d" % roundi(x) if absf(x - roundf(x)) < 0.05 else "%+.1f" % x


## "1 trip", "4 trips".
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


# -------------------------------------------------------------------- relations --

## `relations.describe(p)` ({"friends", "rivals", "partner", "lines"}), or {}.
static func describe(sim, p) -> Dictionary:
	var m = module(sim, "relations")
	if m == null or p == null or not m.has_method("describe"):
		return {}
	var d = m.describe(p)
	return d if d is Dictionary else {}


## The entries of one list of `describe` ("friends" or "rivals"): the ones that are dictionaries.
static func _list(d: Dictionary, key: String) -> Array:
	var out: Array = []
	var got = d.get(key, [])
	if got is Array:
		for e in got:
			if e is Dictionary and not e.is_empty():
				out.append(e)
	return out


static func _partner(d: Dictionary) -> Dictionary:
	var e = d.get("partner", {})
	return e if e is Dictionary else {}


static func _first(e: Dictionary) -> String:
	return String(e.get("first", e.get("id", "")))


## Who `p` is at odds with, as the row says it: "Walt (at odds), Hector (enemies)" ("" when nobody).
static func rivals_text(sim, p) -> String:
	var bits: Array = []
	for e in _list(describe(sim, p), "rivals"):
		var word := String(e.get("word", ""))
		bits.append("%s (%s)" % [_first(e), word] if word != "" else _first(e))
	return ", ".join(bits)


## How one pair stands, in a line: "Dez: close, since day 4" (the day only when the module says it).
static func _stand_line(e: Dictionary, fallback_word: String) -> String:
	var word := String(e.get("word", ""))
	# a roster bond says what it is besides how it stands ("Marcus (family): close")
	var kind := String(e.get("kind", ""))
	var who := "%s (%s)" % [_first(e), kind] if kind == "family" or kind == "mentor" else _first(e)
	var line := "%s: %s" % [who, word if word != "" else fallback_word]
	var since := int(e.get("since", 0))
	if since > 0:
		line += ", since day %d" % since
	return line


## The lines the Bonds tooltip gains: how each friendship and the partnership stand, and since when ("" when there are none).
static func bond_tip(sim, p) -> String:
	var d := describe(sim, p)
	var lines: Array = []
	var partner := _partner(d)
	for e in _list(d, "friends"):
		if not partner.is_empty() and String(e.get("id", "")) == String(partner.get("id", "")):
			continue
		lines.append(_stand_line(e, "friends"))
	if not partner.is_empty():
		lines.append(_stand_line(partner, "partners"))
	if lines.is_empty():
		return ""
	return "How they stand:\n" + "\n".join(lines)


## The Rivals row's tooltip: each rival with the word and the day, and what a rival near them does (the rules' own numbers when the
## module has them).
static func rivals_tip(sim, p) -> String:
	var d := describe(sim, p)
	var lines: Array = []
	for e in _list(d, "rivals"):
		lines.append(_stand_line(e, "at odds"))
	if lines.is_empty():
		return ""
	var m = module(sim, "relations")
	var tiles = m.get("RIVAL_TILES") if m != null else null
	var near = m.get("RIVAL_NEAR") if m != null else null
	var edge := "Near a rival they are on edge."
	if tiles != null and near != null:
		edge = "Within %d tiles of a rival they are on edge (%s mood)." % [roundi(float(tiles)), _signed(float(near))]
	return "At odds with:\n" + "\n".join(lines) + "\n" + edge


## The Rivals row of the person panel (a row of its own under Bonds, made the first time somebody has a rival): shown with "Walt (at odds)"
## while there is one and gone when there is not. `refs` is the HUD's `inspect_refs`; `host` the HUD. When it comes or goes while the person
## is looked at, the dock is laid out again (the panel is a row taller or shorter).
static func sync_rivals(host, refs: Dictionary, sim, p) -> void:
	if host == null or not refs.has("bonds_head"):
		return
	# (one who is gone has no rivals to show)
	var text := "" if p == null or p.dead or p.turned else rivals_text(sim, p)
	var head = refs.get("rivals_head")
	if head == null:
		if text == "":
			return
		var label: Label = host._label("", Fonts.sans(400), 13, host.INK)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		head = host._row(refs.bonds_head.get_parent(), "Rivals", label)
		head.mouse_filter = Control.MOUSE_FILTER_PASS
		head.visible = false
		label.visible = false
		refs["rivals_head"] = head
		refs["rivals"] = label
	var row: Label = refs.rivals
	var show := text != ""
	var changed: bool = show != head.visible
	head.visible = show
	row.visible = show
	if show:
		host._set_text(row, text, host.INK)
		var tip := rivals_tip(sim, p)
		for c in [row, head]:
			if c.tooltip_text != tip:
				c.tooltip_text = tip
	if changed and refs.has("gizmo_sig"):
		host._layout_dock()


# -------------------------------------------------------------------- specialists --

## `specialists.title_of(p)` ({"id", "name", "short", "since_day"}), or {} when they have none.
static func title_of(sim, p) -> Dictionary:
	var m = module(sim, "specialists")
	if m == null or p == null or not m.has_method("title_of"):
		return {}
	var t = m.title_of(p)
	if not (t is Dictionary) or t.is_empty():
		return {}
	return t


## The title as the card's tooltip and the chip's own tooltip say it: "The medic" ("" when they have none).
static func title_text(sim, p) -> String:
	var t := title_of(sim, p)
	if t.is_empty():
		return ""
	return _cap(String(t.get("name", t.get("short", t.get("id", "")))))


## The title as the chip says it: the short form, "Medic" ("The marksman" and two of the widest traits would not fit the 300 px panel's
## row of chips, and every title has to). "" when they have none.
static func chip_text(sim, p) -> String:
	var t := title_of(sim, p)
	if t.is_empty():
		return ""
	var short := String(t.get("short", ""))
	if short == "":
		short = String(t.get("name", t.get("id", ""))).trim_prefix("the ").trim_prefix("The ")
	return _cap(short)


static func _skill(p, skill_name: String) -> int:
	var mine = p.get("skills")
	var base := int(p.def.skills.get(skill_name, 0))
	return int(mine.get(skill_name, base)) if mine is Dictionary else base


## The practice behind a title, as the News line says it ("Medicine 10, 8 treated"); "" for a title this knows nothing of.
static func practice_line(sim, p, title: Dictionary) -> String:
	# the module's own line when it gives one (the News says the same words), else worked out here from the person's counters
	var said = title.get("practice", "")
	if said is String and said != "":
		return said
	var st = p.get("stats")
	var stats: Dictionary = st if st is Dictionary else {}
	match String(title.get("id", "")):
		"medic":
			return "Medicine %d, %d treated" % [_skill(p, "Medicine"), int(stats.get("treated", 0))]
		"engineer":
			var line := "Building %d, %d HP mended" % [_skill(p, "Building"), roundi(float(stats.get("mended", 0.0)))]
			if roundi(float(stats.get("crafted", 0.0))) > 0:
				line += ", %d scrap made into ammo" % roundi(float(stats.get("crafted", 0.0)))
			return line
		"marksman":
			return "Shooting %d, %s" % [_skill(p, "Shooting"), _count(int(stats.get("kills", 0)), "kill", "kills")]
		"scout":
			var m = module(sim, "specialists")
			var rec = m.record_of(p) if m != null and m.has_method("record_of") else {}
			return _count(int(rec.get("trips", 0)) if rec is Dictionary else 0, "trip", "trips")
	return ""


## What the title does, in numbers: "Bandages 25% faster and a cure is 8% more likely to work." (from `mult`, `add` and `party_mult`
## of the specialists module, so the numbers are the rules' own); "" when it does nothing the views know of.
static func effect_line(sim, p, title: Dictionary = {}) -> String:
	# the module's own words when it gives them ("Bandages 25% faster, cures 8% more often"), else worked out from its numbers
	var said = title.get("bonus", "")
	if said is String and said != "":
		return said if said.ends_with(".") else said + "."
	var m = module(sim, "specialists")
	if m == null:
		return ""
	var parts: Array = []
	if m.has_method("mult"):
		for pair in MULT_WORDS:
			var pct := roundi((float(m.mult(p, pair[0])) - 1.0) * 100.0)
			if pct != 0:
				parts.append(pair[1] % pct)
	if m.has_method("add"):
		for pair in ADD_WORDS:
			var pct := roundi(float(m.add(p, pair[0])) * 100.0)
			if pct != 0:
				parts.append(pair[1] % pct)
	if m.has_method("party_mult"):
		var pct := roundi((float(m.party_mult([p])) - 1.0) * 100.0)
		if pct != 0:
			parts.append(PARTY_WORDS % pct)
	if parts.is_empty():
		return ""
	var line: String = parts[0]
	for i in range(1, parts.size()):
		line += (" and " if i == parts.size() - 1 else ", ") + String(parts[i])
	return line + "."


## "First choice for the infirmary." for a title with a seat: the stations `specialists.fit_bonus(p, station)` favours for them ("" for
## the scout, who has none, or when there is no jobs module to name them).
static func seat_line(sim, p) -> String:
	var m = module(sim, "specialists")
	var jobs = sim.get("jobs") if sim != null else null
	if m == null or p == null or jobs == null or not m.has_method("fit_bonus") or not jobs.has_method("stations"):
		return ""
	var names: Array = []
	for st in jobs.stations():
		if st is Dictionary and float(m.fit_bonus(p, String(st.get("id", "")))) > 0.0:
			names.append(String(st.get("name", st.get("id", ""))).to_lower())
	if names.is_empty():
		return ""
	return "First choice for the %s." % " and the ".join(names)


## The lines of a title's tooltip: since when, the practice behind it, what it does in numbers, the seat it has first call on.
static func title_lines(sim, p) -> Array:
	var t := title_of(sim, p)
	if t.is_empty():
		return []
	var lines: Array = []
	var since := int(t.get("since_day", 0))
	lines.append("%s since day %d" % [title_text(sim, p), since] if since > 0 else title_text(sim, p))
	for line in [practice_line(sim, p, t), effect_line(sim, p, t), seat_line(sim, p)]:
		if line != "":
			lines.append(line)
	return lines


## What decides how the title's chip looks: when it changes the chip is made again ("" with no title).
static func title_sig(sim, p) -> String:
	var lines := title_lines(sim, p)
	return "" if lines.is_empty() else "title|%s;" % "|".join(lines)


## The title as a gold chip for the person panel's Traits row, with its tooltip (null when they have none). It is the HUD's own trait
## chip (`host._chip`) in gold, with the dark ink the traits' chips have; it says the short form of the title ("Medic", `chip_text`).
static func title_chip(host, sim, p):
	if host == null:
		return null
	var text := chip_text(sim, p)
	if text == "":
		return null
	var tips: Array = []
	for line in title_lines(sim, p):
		tips.append(host._wrap(String(line)))
	var chip: PanelContainer = host._chip(text, "\n".join(tips))
	var base: StyleBox = chip.get_theme_stylebox("panel")
	var gold: StyleBox = host.frame("pill", GOLD_TINT)
	if gold == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color("#e9c35a")
		flat.border_color = Color(host.ACCENT_INK, 0.45)
		flat.set_border_width_all(1)
		flat.set_corner_radius_all(8)
		flat.anti_aliasing = true
		gold = flat
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		gold.set_content_margin(side, base.get_content_margin(side))
	# a little narrower than a trait's chip: the title, and the two widest traits there are, are all that fits the panel's row
	gold.set_content_margin(SIDE_LEFT, CHIP_PAD)
	gold.set_content_margin(SIDE_RIGHT, CHIP_PAD)
	chip.add_theme_stylebox_override("panel", gold)
	return chip


# -------------------------------------------------------------------- initiative --

## How a person's ideas have gone, as the trust tooltip says it: "Ideas: 3 taken up, 1 turned down, quiet until day 8" ("" when they
## have brought none).
static func ideas_line(sim, p) -> String:
	var m = module(sim, "initiative")
	if m == null or p == null or not m.has_method("record_of"):
		return ""
	var r = m.record_of(p)
	if not (r is Dictionary) or r.is_empty():
		return ""
	var parts: Array = []
	if int(r.get("yes", 0)) > 0:
		parts.append("%d taken up" % int(r.get("yes", 0)))
	if int(r.get("no", 0)) > 0:
		parts.append("%d turned down" % int(r.get("no", 0)))
	if int(r.get("later", 0)) > 0:
		parts.append("%d left for later" % int(r.get("later", 0)))
	var until := int(r.get("quiet_until", 0))
	if until > _day(sim):
		parts.append("quiet until day %d" % until)
	if parts.is_empty():
		return ""
	return "Ideas: " + ", ".join(parts)


## "People turn to Ana" for the one the community stands by (else "").
static func voice_line(sim, p) -> String:
	var m = module(sim, "relations")
	if m == null or p == null or not m.has_method("voice"):
		return ""
	var v = m.voice()
	return "People turn to %s" % String(p.first) if v != null and v == p else ""


## The community's lines of the trust tooltip: their ideas and, for the voice, who people turn to.
static func trust_lines(sim, p) -> Array:
	var out: Array = []
	for line in [ideas_line(sim, p), voice_line(sim, p)]:
		if line != "":
			out.append(line)
	return out


# ---------------------------------------------------------------------- the card --

## The lines the crew card's tooltip gains (the card itself shows nothing more): the title, then the relations module's own
## lines ("Close to Dez", "At odds with Walt"). [] for nobody, and for a game that has neither module.
static func person_lines(sim, p) -> Array:
	var out: Array = []
	if sim == null or p == null:
		return out
	var t := title_text(sim, p)
	if t != "":
		out.append(t)
	var lines = describe(sim, p).get("lines", [])
	if lines is Array:
		for l in lines:
			var s := String(l).strip_edges()
			if s != "":
				out.append(s)
	return out


# ---------------------------------------------------------------------- the radio --

## The voice's opinion of an open call, as one line: "Ana, the medic: treat them." ("" when there is none).
static func opinion_line(sim, e: Dictionary) -> String:
	return RadioKit.line_of(RadioKit.opinion_for(sim, e))
