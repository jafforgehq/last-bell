extends "res://tests/case.gd"
## Round 20, slice 4: the views of a community with ideas (scripts/ui/community_kit.gd and the small edits in radio_kit.gd,
## call_view.gd and hud.gd). What they show: the News's new kinds (an idea, a bond, a falling out, a title), the voice's opinion
## under a call's line, and in the person panel the rivals' row, the words and the day of each friendship, the title as a gold
## chip first among the traits, the ideas and the voice in the trust tooltip, and on the crew card's tooltip the title and who
## they are close to (nothing is drawn on the card). The rules behind them (scripts/sim/relations.gd, specialists.gd, initiative.gd)
## belong to the three SIM builders and have their own tests: here the three modules are table-driven fakes that follow the plan's
## contract (docs/superpowers/plans/2026-10-03-round-20.md, S4.1 to S4.3), and the last tests use the real ones. Every read is
## guarded: a module that is missing, or has no such method, is no row and no error.

const Kit := preload("res://tests/hud_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const CallCard := preload("res://scripts/ui/call_card.gd")
const CallView := preload("res://scripts/ui/call_view.gd")
const NewsPanel := preload("res://scripts/ui/news_panel.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const CommunityKit := preload("res://scripts/ui/community_kit.gd")
const RadioPanel := preload("res://scripts/ui/radio_panel.gd")
const TextTests := preload("res://tests/test_hud_text.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]


# ------------------------------------------------------------------- the fakes --
# Each fake is a plain object that has the whole of its module's contract (S4.1 to S4.3: every method a hook of the rules may call,
# neutral where the views do not read it) and answers what the views read from tables a test fills in. They do not extend the
# real modules, so a member the builders add to those can never clash with them.

class NeutralModule:
	extends RefCounted
	var sim
	var enabled := true
	var on := true

	func setup(s) -> void:
		sim = s

	func start() -> void:
		pass

	func person_added(_p) -> void:
		pass

	func update(_dt: float) -> void:
		pass

	func active() -> bool:
		return on

	func save() -> Dictionary:
		return {}

	func load_state(_d: Dictionary) -> void:
		pass


## Pairs: [{"a", "b", "v", "kind": "friend" | "partner" | "rival", "since"}], symmetric as the real module's are.
class FakeRelations:
	extends NeutralModule
	const RIVAL_TILES := 4.0
	const RIVAL_NEAR := -3.0
	var pairs: Array = []
	var voice_id := ""

	static func word_for(v: float, kind: String) -> String:
		if kind == "partner":
			return "partners"
		if v <= -65.0:
			return "enemies"
		if v <= -35.0:
			return "at odds"
		if v <= -12.0:
			return "wary"
		if v >= 65.0:
			return "close"
		if v >= 35.0:
			return "friends"
		if v >= 12.0:
			return "friendly"
		return ""

	func _first(id: String) -> String:
		for q in sim.people:
			if q.id == id:
				return String(q.first)
		return id

	## A whole answer for `describe`, in place of the one the pairs make (the real module's roster bonds carry kinds the pairs do not).
	var describe_override := {}

	func describe(p) -> Dictionary:
		if not on:
			return {}
		if not describe_override.is_empty():
			return describe_override
		var out := {"friends": [], "rivals": [], "partner": {}, "lines": []}
		for pr in pairs:
			var other := ""
			if pr.a == p.id:
				other = String(pr.b)
			elif pr.b == p.id:
				other = String(pr.a)
			if other == "":
				continue
			var e := {"id": other, "first": _first(other), "kind": String(pr.kind), "word": word_for(float(pr.v), String(pr.kind)), "value": float(pr.v)}
			if pr.has("since"):
				e["since"] = int(pr.since)
			match String(pr.kind):
				"friend":
					out.friends.append(e)
				"partner":
					out.partner = e
				"rival":
					out.rivals.append(e)
		var close: Array = []
		for f in out.friends:
			close.append(f.first)
		if not out.partner.is_empty():
			close.append("%s (partner)" % out.partner.first)
		if not close.is_empty():
			out.lines.append("Close to " + ", ".join(close))
		var odds: Array = []
		for r in out.rivals:
			odds.append(r.first)
		if not odds.is_empty():
			out.lines.append("At odds with " + ", ".join(odds))
		return out

	func voice():
		for q in sim.people:
			if q.id == voice_id and not q.dead:
				return q
		return null

	# the rest of the contract, neutral (hooks of the rules may call them)
	func affinity(_a, _b) -> float:
		return 0.0

	func kind(_a, _b) -> String:
		return ""

	func word(_a, _b) -> String:
		return ""

	func add(_a, _b, _delta: float, _why: String) -> void:
		pass

	func friends_of(_p) -> Array:
		return []

	func rivals_of(_p) -> Array:
		return []

	func partner_of(_p):
		return null

	func circle(_p) -> Array:
		return []

	func is_close(_p, _q) -> bool:
		return false

	func standing(_p) -> float:
		return 0.0

	func community_trust() -> float:
		return 55.0

	func company_pull(_contact, _verb: String) -> float:
		return 0.0

	func company_reason(_contact, _what: String, _station_id := "", _with_ids := []) -> String:
		return ""

	func rival_near(_p):
		return null

	func grief_mult(_p, _lost) -> float:
		return 1.0

	func fit_adjust(_p, _station_id: String) -> float:
		return 0.0

	func succession_bonus(_p) -> float:
		return 0.0

	func on_trust_moved(_p, _delta: float) -> void:
		pass

	func on_treated(_healer, _patient, _kind: String) -> void:
		pass

	func on_trip(_came: Array, _lost: Array, _party: Dictionary) -> void:
		pass

	func on_lost(_p, _how: String) -> void:
		pass

	func on_downed(_p) -> void:
		pass

	func recent_loss() -> Dictionary:
		return {}


class FakeSpecialists:
	extends NeutralModule
	## Person id -> {"id", "name", "short", "since_day"}.
	var titles := {}
	## Title id -> {"mult": {key: x}, "add": {key: x}, "party": x}.
	var effects := {}
	var recs := {}
	## Title id -> the stations it has first call on.
	var seats := {}

	func title_of(p) -> Dictionary:
		return titles.get(p.id, {}) if on else {}

	func mult(p, key: String) -> float:
		var t := title_of(p)
		if t.is_empty():
			return 1.0
		return float(effects.get(t.id, {}).get("mult", {}).get(key, 1.0))

	func add(p, key: String) -> float:
		var t := title_of(p)
		if t.is_empty():
			return 0.0
		return float(effects.get(t.id, {}).get("add", {}).get(key, 0.0))

	func party_mult(people: Array) -> float:
		var m := 1.0
		for p in people:
			var t := title_of(p)
			if not t.is_empty():
				m = maxf(m, float(effects.get(t.id, {}).get("party", 1.0)))
		return m

	func record_of(p) -> Dictionary:
		return recs.get(p.id, {"trips": 0, "since": {}})

	func opinion_title(p) -> String:
		return String(title_of(p).get("name", ""))

	func holder(_title_id: String):
		return null

	func gaps() -> Array:
		return []

	func fit_bonus(p, station_id: String) -> float:
		var t := title_of(p)
		if t.is_empty():
			return 0.0
		return 1.5 if (seats.get(t.id, []) as Array).has(station_id) else 0.0

	func on_trip(_came: Array, _lost: Array, _party: Dictionary) -> void:
		pass


class FakeInitiative:
	extends NeutralModule
	## Call id -> {"who", "first", "title", "option", "line"}.
	var opinions := {}
	## Person id -> {"asked", "yes", "no", "later", "quiet_until"}.
	var records := {}
	var asked: Array = []

	func voice_opinion(e: Dictionary) -> Dictionary:
		asked.append(int(e.id))
		return opinions.get(int(e.id), {}) if on else {}

	func record_of(p) -> Dictionary:
		return records.get(p.id, {})

	func taken_of(p) -> int:
		return int(records.get(p.id, {}).get("yes", 0))

	func candidates() -> Array:
		return []

	func propose_now() -> int:
		return 0

	func carry_out(_e: Dictionary, _option_id: String) -> String:
		return ""


## A module with nothing in it: an older fake.
class Bare:
	extends RefCounted


const MEDIC := {"id": "medic", "name": "the medic", "short": "medic", "since_day": 4}
const OPINION := {"who": "ana", "first": "Ana", "title": "the medic", "option": "reinforce", "line": "Ana, the medic: send reinforcements."}


# ---------------------------------------------------------------------- helpers --

## A HUD over a quiet game in avatar mode, with the three fakes in (all of them silent: no pairs, no titles, no opinions).
func _ctx(width: int = 1280, height: int = 800, player: String = "ruth") -> Dictionary:
	var ctx := Kit.build(width, height)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	if player != "":
		check(sim.avatar.set_player(player), "%s is the player" % player)
	sim.relations = FakeRelations.new()
	sim.specialists = FakeSpecialists.new()
	sim.initiative = FakeInitiative.new()
	for m in [sim.relations, sim.specialists, sim.initiative]:
		m.setup(sim)
	Kit.update(ctx)
	return ctx


## The community of the plan's examples: Dez and Ana are close, Ana is partnered with Hector, Walt and Dez are at odds; Ana is the
## medic (since day 4) and the voice; Dez has had ideas taken up and turned down.
func _community(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := _ctx(width, height)
	var sim = ctx.sim
	sim.relations.pairs = [
		{"a": "dez", "b": "ana", "v": 72.0, "kind": "friend", "since": 4},
		{"a": "ana", "b": "hector", "v": 88.0, "kind": "partner", "since": 6},
		{"a": "walt", "b": "dez", "v": -50.0, "kind": "rival", "since": 5},
	]
	sim.relations.voice_id = "ana"
	sim.specialists.titles["ana"] = MEDIC.duplicate()
	sim.specialists.effects["medic"] = {"mult": {"bandage": 1.25}, "add": {"cure": 0.08}}
	sim.initiative.records["dez"] = {"asked": 5, "yes": 3, "no": 1, "later": 1, "quiet_until": 0}
	var ana = Kit.person(ctx, "ana")
	ana.skills["Medicine"] = 10
	ana.stats["treated"] = 8
	# the bonds the real module would list for them (it merges the relation friends in; the kit's fake does not)
	sim.bonds.table["ana"] = [["ruth", "friend"], ["dez", "friend"], ["hector", "friend", "partner"]]
	sim.bonds.table["dez"] = [["hector", "friend"], ["ana", "friend"]]
	Kit.update(ctx)
	return ctx


func _open(ctx: Dictionary, id: String):
	var p = Kit.person(ctx, id)
	Kit.select(ctx, p)
	Kit.update(ctx)
	return p


func _refs(ctx: Dictionary) -> Dictionary:
	return ctx.hud.inspect_refs


func _flat(tip: String) -> String:
	return tip.replace("\n", " ")


func _wall_call(radio) -> int:
	return radio.raise_call("attack", "North wall under attack", "4 of the dead at it, 60% intact", [
		{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send reinforcements"}, {"id": "fall_back", "label": "Fall back to the school"},
	], "hold", 30.0, {"seg": 1}, Vector2(40, 10))


func _fever_call(radio) -> int:
	return radio.raise_call("sick", "Hector has a fever", "Treat them, or keep them apart", [
		{"id": "treat", "label": "Treat them"}, {"id": "apart", "label": "Keep them apart"},
	], "treat", 60.0, {"who": "hector"}, Vector2(30, 30))


## An idea as the plan words it: a call of kind "idea" with yes (and its price), later and no; nothing in it is random.
func _idea_call(radio, text: String = "I could fix the east wall properly. About 20 scrap.", yes: String = "Yes: fix the wall (20 scrap)") -> int:
	return radio.raise_call("idea", text, "Dez, the engineer: the crew stops when it is whole", [
		{"id": "yes", "label": yes}, {"id": "later", "label": "Later"}, {"id": "no", "label": "No"},
	], "later", 360.0, {"idea": "fix_wall", "who": "dez", "others": [], "args": {}}, Vector2(40, 10))


func _texts_of(node: Node) -> String:
	var out: Array = []
	_collect(node, out)
	return " | ".join(out)


func _collect(node: Node, out: Array) -> void:
	if node is Control and not node.visible:
		return
	if node is Label and node.text != "":
		out.append(node.text)
	for c in node.get_children():
		_collect(c, out)


func _rects(ctx: Dictionary) -> Dictionary:
	var h = ctx.hud
	return {
		"stores": Kit.rect(h.res_panel), "legend": Kit.rect(h.fields_legend), "cards": Kit.rect(h.bar), "clock": Kit.rect(h.clock),
		"alerts": Kit.rect(h.alerts_box), "call": Kit.rect(h.call_card), "selection": Kit.rect(h.inspect), "buttons": Kit.rect(h.gizmos),
		"radio": Kit.rect(h.radio_box), "news": Kit.rect(h.news_panel), "speed": Kit.rect(h.speed_panel),
	}


# ------------------------------------------------------------------- the news --

func test_the_news_kinds_of_the_community_are_named_and_coloured() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	eq(RadioKit.kind_name("idea"), "Idea", "an idea")
	eq(RadioKit.kind_name("bond"), "People", "a friendship, a couple")
	eq(RadioKit.kind_name("rift"), "Falling out", "a rift")
	eq(RadioKit.kind_name("title"), "Known for", "a title")
	eq(RadioKit.kind_color(h, "idea"), Hud.INFO, "an idea is blue")
	eq(RadioKit.kind_color(h, "bond"), Hud.OK, "a bond is green")
	eq(RadioKit.kind_color(h, "rift"), Hud.WARN, "a rift is amber")
	eq(RadioKit.kind_color(h, "title"), Hud.ACCENT, "a title is gold")
	# the old kinds keep what they had
	eq(RadioKit.kind_name("attack"), "Attack", "attack as it was")
	eq(RadioKit.kind_color(h, "attack"), Hud.DANGER_TEXT, "red as it was")
	eq(RadioKit.kind_color(h, "story"), Hud.INFO, "story as it was")
	for k in ["idea", "bond", "rift", "title"]:
		var c: Color = RadioKit.kind_color(h, k)
		check(TextTests.contrast(c, TextTests.over(Hud.PANEL, Color.WHITE)) >= TextTests.AA, "%s reads as a word on the panel" % k)
	Kit.free_all(ctx)


func test_the_news_page_draws_the_new_kinds_with_their_names_and_colours() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	radio.log_news("bond", "Dez and Ana are close now", "They work the bench side by side")
	radio.log_news("rift", "Walt and Dez are at odds", "They share a wall")
	radio.log_news("title", "Ana is the camp's medic now", "Medicine 10, 8 treated")
	var h = ctx.hud
	h.toggle_news()
	Kit.update(ctx)
	await Kit.settle()
	var p = h.news_panel
	eq(p.row_kinds(), ["title", "rift", "bond"], "newest first, each with its kind")
	eq(p.row_colors(), [Hud.ACCENT, Hud.WARN, Hud.OK], "in the kinds' colours")
	var all := _texts_of(p)
	for word in ["KNOWN FOR", "FALLING OUT", "PEOPLE", "Ana is the camp's medic now", "Walt and Dez are at odds", "Dez and Ana are close now", "Medicine 10, 8 treated"]:
		check(all.contains(word), "'%s' is on the page: %s" % [word, all])
	var tt := TextTests.new()
	eq(tt._small_text(p), [], "nothing under 12 px")
	eq(tt._hard_to_read(p, Color.WHITE), [], "and every word reads")
	Kit.free_all(ctx)


func test_an_idea_is_an_ordinary_call_with_its_three_buttons_and_its_countdown() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	var h = ctx.hud
	var id := _idea_call(radio)
	Kit.update(ctx)
	await Kit.settle()
	check(h.call_card.visible and h.call_card.shown_id == id, "the card shows the idea")
	var view = h.call_card.view
	eq(view.kind_label.text, "IDEA", "its kind")
	eq(view.kind_label.get_theme_color("font_color"), Hud.INFO, "in blue")
	eq(view.title_label.text, "I could fix the east wall properly. About 20 scrap.", "in the proposer's own words")
	eq(view.buttons.keys(), ["yes", "later", "no"], "yes, later, no")
	eq(view.buttons["yes"].text, "Yes: fix the wall (20 scrap)", "with the price on the yes")
	near(view.seconds_left(), 120.0, 0.01, "six game hours at three minutes a second: it waits a long time")
	check(view.count_label.text.contains("Later"), "and says what is taken when it runs out: %s" % view.count_label.text)
	eq(ctx.speeds, [], "it never pauses the game")
	view.buttons["no"].pressed.emit()
	eq(String(RadioKit.entry_of(radio, id).answered), "no", "no goes to the radio")
	# in the News the same call has the same three buttons
	var id2 := _idea_call(radio, "The garden could feed two more.", "Yes: put Marcus on it")
	h.toggle_news()
	Kit.update(ctx)
	await Kit.settle()
	eq(h.news_panel.call_ids(), [id2], "the News holds the open idea at its top")
	eq(h.news_panel.call_views[0].buttons.keys(), ["yes", "later", "no"], "with its three buttons")
	Kit.free_all(ctx)


# ---------------------------------------------------- the voice's opinion --

func test_the_voices_opinion_is_a_line_under_the_calls_own_line() -> void:
	var ctx := _community()
	var radio = ctx.sim.radio
	var id := _wall_call(radio)
	ctx.sim.initiative.opinions[id] = OPINION.duplicate()
	Kit.update(ctx)
	await Kit.settle()
	var view = ctx.hud.call_card.view
	eq(view.opinion_label.text, "Ana, the medic: send reinforcements.", "the words of the module")
	check(view.opinion_label.is_visible_in_tree(), "and it is on show")
	check(view.opinion_label.get_theme_font_size("font_size") >= 12, "12 px or more")
	check(Kit.rect(view.opinion_label).position.y >= Kit.rect(view.sub_label).end.y - 0.5, "under the line the call has")
	check(Kit.rect(view.bar).position.y >= Kit.rect(view.opinion_label).end.y - 0.5, "and above the countdown")
	# no highlight on the option it names, and the call's own default is untouched
	eq(view.buttons["reinforce"].modulate, view.buttons["hold"].modulate, "no button is lit for the opinion")
	check(view.count_label.text.contains("Hold"), "the default is still Hold: %s" % view.count_label.text)
	eq(String(RadioKit.entry_of(radio, id).default), "hold", "and the radio's entry still says so")
	check(ctx.sim.initiative.asked.has(id), "the call was put to the initiative module")
	Kit.free_all(ctx)


func test_the_opinion_is_told_only_when_the_card_has_room_for_the_line_under_the_title() -> void:
	var ctx := _community()
	var id := _wall_call(ctx.sim.radio)
	ctx.sim.initiative.opinions[id] = OPINION.duplicate()
	Kit.update(ctx)
	var card = ctx.hud.call_card
	var view = card.view
	check(view.opinion_label.visible, "level 0: shown")
	view.set_level(1)
	check(not view.opinion_label.visible, "level 1: gone with the line under the title")
	view.set_level(2)
	check(not view.opinion_label.visible, "level 2: gone")
	view.set_level(0)
	check(view.opinion_label.visible, "level 0 again: back")
	# a card with little room gives it up before the buttons
	await Kit.settle()
	var full: float = card.get_combined_minimum_size().y
	check(card.fit(full - 4.0), "a card a little short still fits")
	check(not view.opinion_label.visible and view.level >= 1, "by giving the opinion up (level %d)" % view.level)
	check(card.fit(full + 40.0) and view.level == 0 and view.opinion_label.visible, "and with room it is whole again")
	Kit.free_all(ctx)


func test_the_opinion_follows_the_module_and_goes_when_the_call_is_settled() -> void:
	var ctx := _community()
	var radio = ctx.sim.radio
	var h = ctx.hud
	h.call_card.result_ms = 5000
	var id := _wall_call(radio)
	Kit.update(ctx)
	var view = h.call_card.view
	check(not view.opinion_label.visible and view.opinion_label.text == "", "nobody has an opinion: no line")
	ctx.sim.initiative.opinions[id] = OPINION.duplicate()
	Kit.update(ctx)
	check(view.opinion_label.visible and view.opinion_label.text == OPINION.line, "an opinion comes: the line is there")
	ctx.sim.initiative.opinions[id] = {"who": "ana", "first": "Ana", "title": "", "option": "fall_back", "line": "Ana: fall back."}
	Kit.update(ctx)
	eq(view.opinion_label.text, "Ana: fall back.", "the wall worsens: the voice changes their mind, live")
	ctx.sim.initiative.opinions.erase(id)
	Kit.update(ctx)
	check(not view.opinion_label.visible, "and it is gone when the voice has none")
	ctx.sim.initiative.opinions[id] = OPINION.duplicate()
	Kit.update(ctx)
	view.buttons["hold"].pressed.emit()
	Kit.update(ctx)
	check(h.call_card.is_showing_result(), "the call is settled: the card shows what came of it")
	check(not view.opinion_label.visible, "with no opinion on a call that is over")
	Kit.free_all(ctx)


func test_the_opinion_shows_in_the_news_panel_too() -> void:
	var ctx := _community()
	var id := _wall_call(ctx.sim.radio)
	var id2 := _fever_call(ctx.sim.radio)
	ctx.sim.initiative.opinions[id] = OPINION.duplicate()
	ctx.sim.initiative.opinions[id2] = {"who": "ana", "first": "Ana", "title": "the medic", "option": "treat", "line": "Ana, the medic: treat them."}
	ctx.hud.toggle_news()
	Kit.update(ctx)
	await Kit.settle()
	var views: Array = ctx.hud.news_panel.call_views
	eq(views.size(), 2, "two calls")
	eq(views[0].opinion_label.text, "Ana, the medic: send reinforcements.", "the first has the voice's line")
	eq(views[1].opinion_label.text, "Ana, the medic: treat them.", "and the second")
	check(views[0].opinion_label.is_visible_in_tree() and views[1].opinion_label.is_visible_in_tree(), "both on show")
	var tt := TextTests.new()
	eq(tt._small_text(ctx.hud.news_panel), [], "nothing under 12 px")
	eq(tt._hard_to_read(ctx.hud.news_panel, Color.WHITE), [], "every word reads")
	Kit.free_all(ctx)


func test_no_opinion_without_a_module_or_when_it_is_inactive() -> void:
	var ctx := _community()
	var id := _wall_call(ctx.sim.radio)
	ctx.sim.initiative.opinions[id] = OPINION.duplicate()
	Kit.update(ctx)
	var view = ctx.hud.call_card.view
	check(view.opinion_label.visible, "with the module: the line")
	ctx.sim.initiative.on = false
	Kit.update(ctx)
	check(not view.opinion_label.visible, "the module is off (no avatar, Orientation Day, a classic start): no line")
	ctx.sim.initiative.on = true
	ctx.sim.initiative = Bare.new()
	Kit.update(ctx)
	check(not view.opinion_label.visible, "a module with no such method: no line, no error")
	ctx.sim.initiative = null
	Kit.update(ctx)
	check(not view.opinion_label.visible and view.opinion_label.text == "", "no module at all: no line")
	eq(CommunityKit.opinion_line(ctx.sim, RadioKit.entry_of(ctx.sim.radio, id)), "", "the kit says nothing then")
	eq(RadioKit.opinion_of(ctx.sim.radio, RadioKit.entry_of(ctx.sim.radio, id)), {}, "and RadioKit gives an empty answer")
	eq(RadioKit.opinion_of(null, {}), {}, "and for no radio")
	Kit.free_all(ctx)


func test_the_kits_opinion_line_is_the_modules_line_and_nothing_else() -> void:
	var ctx := _community()
	var id := _wall_call(ctx.sim.radio)
	var e := RadioKit.entry_of(ctx.sim.radio, id)
	eq(CommunityKit.opinion_line(ctx.sim, e), "", "no opinion yet: empty")
	ctx.sim.initiative.opinions[id] = OPINION.duplicate()
	eq(CommunityKit.opinion_line(ctx.sim, e), "Ana, the medic: send reinforcements.", "the line")
	eq(RadioKit.opinion_of(ctx.sim.radio, e).get("option"), "reinforce", "and RadioKit gives the whole answer (the option too)")
	ctx.sim.initiative.opinions[id] = {"who": "ana", "line": 5}
	eq(CommunityKit.opinion_line(ctx.sim, e), "", "a line that is not text is none")
	ctx.sim.initiative.opinions[id] = {"who": "ana"}
	eq(CommunityKit.opinion_line(ctx.sim, e), "", "an answer with no line is none")
	eq(CommunityKit.opinion_line(null, e), "", "no sim")
	Kit.free_all(ctx)


# ------------------------------------------------------------ the person panel --

func test_a_rival_is_a_row_with_the_word_and_a_tooltip_that_says_what_it_does() -> void:
	var ctx := _community()
	_open(ctx, "dez")
	var refs := _refs(ctx)
	check(refs.has("rivals_head") and refs.rivals_head.visible and refs.rivals.visible, "Dez has a row for who he is at odds with")
	eq(refs.rivals_head.text, "RIVALS", "called Rivals")
	eq(refs.rivals.text, "Walt (at odds)", "Walt, and the word the module gives")
	var tip: String = refs.rivals.tooltip_text
	check(_flat(tip).contains("Walt") and tip.contains("at odds"), "the tooltip names them: %s" % tip)
	check(_flat(tip).contains("since day 5"), "and the day it began: %s" % tip)
	check(_flat(tip).contains("on edge") and _flat(tip).contains("4 tiles"), "and what it does (within 4 tiles they are on edge): %s" % tip)
	check(_flat(tip).contains("-3"), "with the module's own number: %s" % tip)
	eq(refs.rivals_head.tooltip_text, tip, "the caption has it too")
	check(refs.rivals.mouse_filter != Control.MOUSE_FILTER_IGNORE, "and the row takes the mouse, or there would be no tooltip")
	# Walt is the other half of it
	_open(ctx, "walt")
	eq(_refs(ctx).rivals.text, "Dez (at odds)", "Walt's own row")
	# a person with no rival has no row
	_open(ctx, "marcus")
	check(not _refs(ctx).get("rivals_head", null) or not _refs(ctx).rivals_head.visible, "Marcus: no row")
	Kit.free_all(ctx)


func test_one_who_is_gone_has_no_rivals_row() -> void:
	var ctx := _community()
	var dez = _open(ctx, "dez")
	check(_refs(ctx).rivals_head.visible, "alive: the row")
	dez.dead = true
	Kit.update(ctx)
	check(not _refs(ctx).rivals_head.visible and not _refs(ctx).rivals.visible, "remembered: no row")
	dez.dead = false
	dez.turned = true
	dez.dead = true
	Kit.update(ctx)
	check(not _refs(ctx).rivals_head.visible, "turned: no row")
	Kit.free_all(ctx)


func test_the_rivals_row_follows_the_module_while_the_person_is_selected() -> void:
	var ctx := _community()
	var marcus = _open(ctx, "marcus")
	var refs := _refs(ctx)
	check(not refs.get("rivals_head", null) or not refs.rivals_head.visible, "no rival: no row")
	ctx.sim.relations.pairs.append({"a": "marcus", "b": "walt", "v": -70.0, "kind": "rival", "since": 7})
	Kit.update(ctx)
	check(refs.rivals_head.visible, "a rival forms: the row comes")
	eq(refs.rivals.text, "Walt (enemies)", "an enemy is called one")
	ctx.sim.relations.pairs.append({"a": "marcus", "b": "hector", "v": -40.0, "kind": "rival", "since": 8})
	Kit.update(ctx)
	eq(refs.rivals.text, "Walt (enemies), Hector (at odds)", "two rivals, in the module's order")
	ctx.sim.relations.pairs.clear()
	Kit.update(ctx)
	check(not refs.rivals_head.visible and not refs.rivals.visible, "they make it up: the row goes")
	check(marcus != null, "(Marcus)")
	Kit.free_all(ctx)


func test_a_rival_that_comes_while_the_person_is_looked_at_leaves_the_dock_clear() -> void:
	for size in SIZES:
		var ctx := _community(size[0], size[1])
		var marcus = _open(ctx, "marcus")
		await Kit.settle()
		ctx.sim.relations.pairs.append({"a": "marcus", "b": "walt", "v": -70.0, "kind": "rival", "since": 7})
		Kit.update(ctx)
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var where := "%d x %d" % [size[0], size[1]]
		check(_refs(ctx).rivals_head.visible, "%s: the row came" % where)
		eq(Kit.overlaps(_rects(ctx)), [], where)
		var win := Rect2(0, 0, size[0], size[1])
		check(win.encloses(Kit.rect(ctx.hud.inspect).grow(-0.5)), "%s: the panel is inside the window (%s)" % [where, str(Kit.rect(ctx.hud.inspect))])
		check(win.encloses(Kit.rect(ctx.hud.radio_box).grow(-0.5)), "%s: and so are the verbs (%s)" % [where, str(Kit.rect(ctx.hud.radio_box))])
		check(marcus != null, "(Marcus)")
		Kit.free_all(ctx)


func test_the_bonds_tooltip_says_how_each_friendship_stands_and_since_when() -> void:
	var ctx := _community()
	_open(ctx, "ana")
	var refs := _refs(ctx)
	eq(refs.bonds.text, "Ruth (friend), Dez (friend), Hector (partner)", "the row is what the bonds module lists (the real one merges the relation friends in)")
	var tip := _flat(refs.bonds.tooltip_text)
	check(tip.contains("Close to:") and tip.contains("Hector"), "the list is still there: %s" % tip)
	check(tip.contains("Dez: close, since day 4"), "how the friendship with Dez stands, and since when: %s" % tip)
	check(tip.contains("Hector: partners, since day 6"), "and the partner: %s" % tip)
	check(not tip.contains("Walt"), "no rival in the friends' tooltip: %s" % tip)
	check(tip.contains("steadier"), "and what a friend is for is still said: %s" % tip)
	eq(refs.bonds_head.tooltip_text, refs.bonds.tooltip_text, "the caption has it too")
	Kit.free_all(ctx)


func test_a_roster_bond_says_what_it_is_in_the_friendships_tooltip() -> void:
	var ctx := _community()
	var rel = ctx.sim.relations
	rel.describe_override = {"friends": [
		{"id": "marcus", "first": "Marcus", "kind": "family", "word": "friends", "value": 60.0, "since": 1},
		{"id": "walt", "first": "Walt", "kind": "mentor", "word": "friends", "value": 50.0, "since": 1},
	], "rivals": [], "partner": {}, "lines": ["Close to Marcus (family), Walt (mentor)"]}
	_open(ctx, "ruth")
	var tip := _flat(_refs(ctx).bonds.tooltip_text)
	check(tip.contains("Marcus (family): friends, since day 1") and tip.contains("Walt (mentor): friends, since day 1"), "the roster's word with each: %s" % tip)
	Kit.free_all(ctx)


func test_a_friendship_without_a_day_is_told_without_it() -> void:
	var ctx := _community()
	ctx.sim.relations.pairs = [{"a": "dez", "b": "ana", "v": 40.0, "kind": "friend"}]
	_open(ctx, "ana")
	var tip := _flat(_refs(ctx).bonds.tooltip_text)
	check(tip.contains("Dez: friends") and not tip.contains("since day"), "no day known, none told: %s" % tip)
	Kit.free_all(ctx)


func test_the_title_is_a_gold_chip_first_among_the_traits_with_the_numbers_in_its_tooltip() -> void:
	var ctx := _community()
	_open(ctx, "ana")
	var refs := _refs(ctx)
	var chips: Array = refs.traits_box.get_children()
	eq(chips.size(), 3, "the title and her two traits")
	eq(Kit.texts(chips[0]), ["Medic"], "the title first, in its short form with a capital")
	eq(Kit.texts(chips[1]), ["Triage"], "her own traits follow")
	eq(Kit.texts(chips[2]), ["Optimist"], "in their order")
	var tip := _flat(chips[0].tooltip_text)
	check(tip.contains("The medic since day 4"), "since when: %s" % tip)
	check(tip.contains("Medicine 10") and tip.contains("8 treated"), "the practice behind it: %s" % tip)
	check(tip.contains("Bandages 25% faster"), "the bonus in numbers: %s" % tip)
	check(tip.contains("a cure is 8% more likely to work"), "all of it: %s" % tip)
	check(chips[0].mouse_filter != Control.MOUSE_FILTER_IGNORE, "the chip takes the mouse, or there would be no tooltip")
	# gold: the lightest of its fill is warm, and the trait chips' is not the same
	var gold: Array = Kit.fills(chips[0].get_theme_stylebox("panel"))
	var plain: Array = Kit.fills(chips[1].get_theme_stylebox("panel"))
	check(gold[1] != plain[1], "its own colour, not the traits': %s against %s" % [str(gold[1]), str(plain[1])])
	check(gold[1].r - gold[1].b > 0.2, "and a gold one: %s" % str(gold[1]))
	# nobody else has one
	_open(ctx, "dez")
	for chip in _refs(ctx).traits_box.get_children():
		check(Kit.texts(chip)[0] != "Medic", "Dez has no title chip")
	eq(_refs(ctx).traits_box.get_child_count(), 2, "just his two traits")
	Kit.free_all(ctx)


func test_each_title_is_worded_in_its_own_numbers() -> void:
	var ctx := _community()
	var sim = ctx.sim
	sim.specialists.titles["dez"] = {"id": "engineer", "name": "the engineer", "short": "engineer", "since_day": 3}
	sim.specialists.effects["engineer"] = {"mult": {"craft": 1.15, "repair": 1.2}}
	sim.specialists.titles["walt"] = {"id": "marksman", "name": "the marksman", "short": "marksman", "since_day": 5}
	sim.specialists.effects["marksman"] = {"mult": {"aim": 1.04}}
	sim.specialists.titles["marcus"] = {"id": "scout", "name": "the scout", "short": "scout", "since_day": 6}
	sim.specialists.effects["scout"] = {"party": 1.12}
	sim.specialists.recs["marcus"] = {"trips": 4, "since": {"scout": 6}}
	var dez = Kit.person(ctx, "dez")
	dez.stats["mended"] = 120.0
	dez.stats["crafted"] = 15.0
	Kit.person(ctx, "walt").stats["kills"] = 31
	var tips := {}
	for id in ["dez", "walt", "marcus"]:
		_open(ctx, id)
		var chip = _refs(ctx).traits_box.get_child(0)
		tips[id] = [Kit.texts(chip)[0], _flat(chip.tooltip_text)]
	eq(tips.dez[0], "Engineer", "Dez")
	check(tips.dez[1].contains("Mends walls 20% faster") and tips.dez[1].contains("makes ammo 15% faster"), "the engineer's numbers: %s" % tips.dez[1])
	check(tips.dez[1].contains("120 HP mended"), "and the practice: %s" % tips.dez[1])
	eq(tips.walt[0], "Marksman", "Walt")
	check(tips.walt[1].contains("Shots land 4% more often") and tips.walt[1].contains("31 kills"), "the marksman's: %s" % tips.walt[1])
	eq(tips.marcus[0], "Scout", "Marcus")
	check(tips.marcus[1].contains("Trips bring home 12% more") and tips.marcus[1].contains("4 trips"), "the scout's: %s" % tips.marcus[1])
	Kit.free_all(ctx)


func test_the_tooltip_names_the_seat_a_title_has_first_call_on() -> void:
	var ctx := _community()
	ctx.sim.specialists.seats["medic"] = ["infirmary"]
	_open(ctx, "ana")
	var tip := _flat(_refs(ctx).traits_box.get_child(0).tooltip_text)
	check(tip.contains("First choice for the infirmary."), "the seat, by its name in the Jobs screen: %s" % tip)
	ctx.sim.specialists.seats["medic"] = ["infirmary", "bench"]
	Kit.update(ctx)
	var two := _flat(_refs(ctx).traits_box.get_child(0).tooltip_text)
	check(two.contains("First choice for the") and two.contains("infirmary") and two.contains("workbench") and two.contains(" and the "), "two seats: %s" % two)
	ctx.sim.specialists.seats.clear()
	Kit.update(ctx)
	check(not _flat(_refs(ctx).traits_box.get_child(0).tooltip_text).contains("First choice"), "a title with no seat (the scout's) says none")
	Kit.free_all(ctx)


func test_the_modules_own_words_for_a_title_are_used_when_it_gives_them() -> void:
	var ctx := _community()
	var t: Dictionary = MEDIC.duplicate()
	t["practice"] = "Medicine 10, 12 treated"
	t["bonus"] = "Bandages 25% faster, cures 8% more often"
	ctx.sim.specialists.titles["ana"] = t
	_open(ctx, "ana")
	var tip := _flat(_refs(ctx).traits_box.get_child(0).tooltip_text)
	check(tip.contains("Medicine 10, 12 treated"), "its practice line, as the News says it: %s" % tip)
	check(tip.contains("Bandages 25% faster, cures 8% more often."), "its bonus in its words: %s" % tip)
	check(not tip.contains("8 treated") and not tip.contains("a cure is 8%"), "and not the kit's own: %s" % tip)
	Kit.free_all(ctx)


func test_a_title_lost_takes_its_chip_away_and_the_row_follows() -> void:
	var ctx := _community()
	_open(ctx, "ana")
	var refs := _refs(ctx)
	eq(refs.traits_box.get_child_count(), 3, "with the title")
	ctx.sim.specialists.titles.erase("ana")
	Kit.update(ctx)
	eq(refs.traits_box.get_child_count(), 2, "the title is lost: the chip is gone, her traits stay")
	ctx.sim.specialists.titles["ana"] = {"id": "medic", "name": "the medic", "short": "medic", "since_day": 9}
	Kit.update(ctx)
	eq(refs.traits_box.get_child_count(), 3, "an heir is named: it is back")
	check(_flat(refs.traits_box.get_child(0).tooltip_text).contains("since day 9"), "with the new day: %s" % refs.traits_box.get_child(0).tooltip_text)
	# someone with a title and no traits at all still has the row
	ctx.sim.traits.table["ana"] = []
	Kit.update(ctx)
	check(refs.traits_head.visible and refs.traits_box.visible, "a title and no traits: the row shows")
	eq(refs.traits_box.get_child_count(), 1, "with the title only")
	ctx.sim.specialists.titles.erase("ana")
	Kit.update(ctx)
	check(not refs.traits_head.visible, "neither: no row")
	Kit.free_all(ctx)


func test_the_trust_tooltip_says_how_their_ideas_went_and_who_people_turn_to() -> void:
	var ctx := _community()
	_open(ctx, "dez")
	var tip := _flat(_refs(ctx).trust_word.tooltip_text)
	check(tip.contains("Ideas: 3 taken up, 1 turned down, 1 left for later"), "Dez's ideas: %s" % tip)
	check(not tip.contains("People turn to"), "Dez is not the one people turn to: %s" % tip)
	eq(_refs(ctx).trust_bar.tooltip_text, _refs(ctx).trust_word.tooltip_text, "on the bar too")
	check(tip.contains("trust"), "the rest of the tooltip is still there: %s" % tip)
	_open(ctx, "ana")
	tip = _flat(_refs(ctx).trust_word.tooltip_text)
	check(tip.contains("People turn to Ana"), "the voice: %s" % tip)
	check(not tip.contains("Ideas:"), "no ideas of hers yet: no line: %s" % tip)
	ctx.sim.initiative.records["ana"] = {"asked": 2, "yes": 2, "no": 0, "later": 0, "quiet_until": 0}
	Kit.update(ctx)
	check(_flat(_refs(ctx).trust_word.tooltip_text).contains("Ideas: 2 taken up"), "her ideas show now")
	ctx.sim.initiative.records["walt"] = {"asked": 3, "yes": 0, "no": 3, "later": 0, "quiet_until": ctx.sim.day + 2}
	_open(ctx, "walt")
	tip = _flat(_refs(ctx).trust_word.tooltip_text)
	check(tip.contains("Ideas: 3 turned down"), "Walt's: %s" % tip)
	check(tip.contains("quiet until day %d" % (ctx.sim.day + 2)), "and he has gone quiet: %s" % tip)
	Kit.free_all(ctx)


# ------------------------------------------------------------------ the crew card --

func test_the_cards_tooltip_gains_the_title_and_who_they_are_close_to() -> void:
	var ctx := _community()
	var tip: String = Kit.card(ctx, Kit.person(ctx, "ana")).card.tooltip_text
	var lines: Array = tip.split("\n")
	check(String(lines[0]).begins_with("Ana"), "the name and the job first: %s" % tip)
	check(lines.has("The medic"), "the title: %s" % tip)
	check(lines.has("Close to Dez, Hector (partner)"), "who they are close to: %s" % tip)
	var dez_tip: String = Kit.card(ctx, Kit.person(ctx, "dez")).card.tooltip_text
	check(dez_tip.split("\n").has("Close to Ana") and dez_tip.split("\n").has("At odds with Walt"), "Dez's: close to Ana, at odds with Walt: %s" % dez_tip)
	check(not dez_tip.contains("The medic"), "and no title: %s" % dez_tip)
	var plain: String = Kit.card(ctx, Kit.person(ctx, "marcus")).card.tooltip_text
	eq(plain.split("\n").size(), 1, "Marcus has nothing to add: just the name and the job: %s" % plain)
	# a title lost shows as the tooltip losing it
	ctx.sim.specialists.titles.erase("ana")
	Kit.update(ctx)
	check(not String(Kit.card(ctx, Kit.person(ctx, "ana")).card.tooltip_text).contains("The medic"), "the title is lost: the tooltip loses it")
	Kit.free_all(ctx)


func test_the_cards_tooltip_keeps_to_the_living_and_the_card_itself_is_untouched() -> void:
	var ctx := _community()
	var ana = Kit.person(ctx, "ana")
	var card: Dictionary = Kit.card(ctx, ana)
	await Kit.settle()
	var with_size: Vector2 = card.card.get_combined_minimum_size()
	var with_texts := Kit.texts(card.card)
	ctx.sim.relations.on = false
	ctx.sim.specialists.on = false
	Kit.update(ctx)
	await Kit.settle()
	eq(card.card.get_combined_minimum_size(), with_size, "the card is as big with it as without")
	eq(Kit.texts(card.card), with_texts, "and says nothing more on its face")
	ctx.sim.relations.on = true
	ctx.sim.specialists.on = true
	# the dead are remembered by what was said of them, not by their standing
	ana.dead = true
	Kit.update(ctx)
	var tip: String = Kit.card(ctx, ana).card.tooltip_text
	check(tip.contains("In memory") and not tip.contains("The medic") and not tip.contains("Close to"), "a memorial: %s" % tip)
	ana.dead = false
	ana.turned = true
	ana.dead = true
	Kit.update(ctx)
	tip = Kit.card(ctx, ana).card.tooltip_text
	check(tip.contains("Turned") and not tip.contains("The medic"), "one who turned: %s" % tip)
	Kit.free_all(ctx)


# ----------------------------------------------------------------------- the kit --

func test_the_kits_person_lines_title_first_then_the_modules_own_words() -> void:
	var ctx := _community()
	var sim = ctx.sim
	eq(CommunityKit.person_lines(sim, Kit.person(ctx, "ana")), ["The medic", "Close to Dez, Hector (partner)"], "Ana")
	eq(CommunityKit.person_lines(sim, Kit.person(ctx, "dez")), ["Close to Ana", "At odds with Walt"], "Dez")
	eq(CommunityKit.person_lines(sim, Kit.person(ctx, "marcus")), [], "Marcus")
	eq(CommunityKit.person_lines(sim, null), [], "nobody")
	eq(CommunityKit.person_lines(null, Kit.person(ctx, "ana")), [], "no sim")
	sim.relations.on = false
	eq(CommunityKit.person_lines(sim, Kit.person(ctx, "ana")), ["The medic"], "relations off: the title only")
	sim.specialists.on = false
	eq(CommunityKit.person_lines(sim, Kit.person(ctx, "ana")), [], "both off: nothing")
	Kit.free_all(ctx)


func test_the_kits_title_chip_is_a_control_or_nothing() -> void:
	var ctx := _community()
	var chip = CommunityKit.title_chip(ctx.hud, ctx.sim, Kit.person(ctx, "ana"))
	check(chip is Control, "a control for a title holder")
	if chip != null:
		eq(Kit.texts(chip), ["Medic"], "with the title")
		ctx.holder.add_child(chip)
		check(chip.focus_mode == Control.FOCUS_NONE, "it takes no focus")
		for c in chip.find_children("*", "Control", true, false):
			check(c.focus_mode == Control.FOCUS_NONE, "nor does %s" % c.name)
		chip.free()
	check(CommunityKit.title_chip(ctx.hud, ctx.sim, Kit.person(ctx, "dez")) == null, "nothing for one with no title")
	check(CommunityKit.title_chip(ctx.hud, ctx.sim, null) == null, "nothing for nobody")
	check(CommunityKit.title_chip(ctx.hud, null, Kit.person(ctx, "ana")) == null, "nor without a sim")
	Kit.free_all(ctx)


# -------------------------------------------------------------- no module, no row --

## A game from before round 20 (and round 4): nothing but what the HUD needed then. `OldSimBare` has the three modules' names with
## nothing in them.
class OldSim:
	extends RefCounted
	var stock
	var segments
	var medical
	var scavenge
	var tactics
	var supplies
	var scenario
	var alerts := {}
	var phase := "day"
	var over := ""
	var day := 3

	func status_of(_p) -> Array:
		return []

	func perf(_p) -> float:
		return 1.0


class OldSimBare:
	extends OldSim
	var relations = Bare.new()
	var specialists = Bare.new()
	var initiative = Bare.new()


func _old_sim(ctx: Dictionary, bare: bool):
	var old = OldSimBare.new() if bare else OldSim.new()
	for k in ["stock", "segments", "medical", "scavenge", "tactics", "supplies", "scenario"]:
		old.set(k, ctx.sim.get(k))
	return old


func test_nothing_breaks_when_a_module_is_missing_or_has_no_such_method() -> void:
	for bare in [false, true]:
		var ctx := _community()
		var old = _old_sim(ctx, bare)
		var where := "modules with nothing in them" if bare else "no modules"
		ctx.hud.sim_ref = old
		for p in ctx.sim.people:
			ctx.hud.select({"kind": "person", "ref": p})
			var refs := _refs(ctx)
			check(not refs.get("rivals_head", null) or not refs.rivals_head.visible, "%s, %s: no rivals row" % [where, p.first])
			eq(refs.traits_box.get_child_count(), 0, "%s, %s: no chips at all (there is no traits module either)" % [where, p.first])
			check(not refs.traits_head.visible, "%s, %s: no traits row" % [where, p.first])
			ctx.hud._update_card(Kit.card(ctx, p), old)
			var plain := "%s, %s" % [p.name, String(p.def.role).to_lower()] + ("\nThis is you" if p.player else "")
			eq(Kit.card(ctx, p).card.tooltip_text, plain, "%s, %s: the card's tooltip is as it was (the name and the job)" % [where, p.first])
			eq(CommunityKit.person_lines(old, p), [], "%s, %s: the kit has nothing to say" % [where, p.first])
			check(CommunityKit.title_chip(ctx.hud, old, p) == null, "%s, %s: no chip" % [where, p.first])
			eq(CommunityKit.trust_lines(old, p), [], "%s, %s: nothing for the trust tooltip" % [where, p.first])
			eq(CommunityKit.rivals_text(old, p), "", "%s, %s: no rivals" % [where, p.first])
			eq(CommunityKit.bond_tip(old, p), "", "%s, %s: no friendships to describe" % [where, p.first])
			eq(CommunityKit.title_sig(old, p), "", "%s, %s: no title" % [where, p.first])
		var e := {"id": 1, "kind": "attack", "options": []}
		eq(CommunityKit.opinion_line(old, e), "", "%s: no opinion" % where)
		eq(RadioKit.opinion_for(old, e), {}, "%s: and RadioKit's answer is empty" % where)
		ctx.hud.sim_ref = ctx.sim
		Kit.free_all(ctx)


func test_inactive_modules_show_nothing_at_all() -> void:
	var ctx := _community()
	for m in [ctx.sim.relations, ctx.sim.specialists, ctx.sim.initiative]:
		m.on = false
	_wall_call(ctx.sim.radio)
	for id in ["ana", "dez", "walt"]:
		_open(ctx, id)
		var refs := _refs(ctx)
		check(not refs.get("rivals_head", null) or not refs.rivals_head.visible, "%s: no rivals row" % id)
		eq(refs.traits_box.get_child_count(), 2, "%s: his or her two traits and no chip" % id)
		check(not _flat(refs.trust_word.tooltip_text).contains("Ideas:") and not refs.trust_word.tooltip_text.contains("People turn to"), "%s: nothing about ideas or the voice" % id)
		check(not _flat(refs.bonds.tooltip_text).contains("since day"), "%s: no relation lines in the bonds' tooltip" % id)
		eq(String(Kit.card(ctx, Kit.person(ctx, id)).card.tooltip_text).split("\n").size(), 1, "%s: the card's tooltip is the name and the job" % id)
	Kit.free_all(ctx)


func test_without_an_avatar_the_old_panel_is_as_it_was_even_with_the_modules_in() -> void:
	# the modules are there (the sim makes them) but a classic game has no avatar: the real stubs and bodies are inactive
	var ctx := Kit.build()
	_open(ctx, "ana")
	var refs := _refs(ctx)
	check(not refs.get("rivals_head", null) or not refs.rivals_head.visible, "no rivals row")
	eq(refs.traits_box.get_child_count(), 2, "two traits, no chip")
	eq(String(Kit.card(ctx, Kit.person(ctx, "ana")).card.tooltip_text).split("\n").size(), 1, "the card's tooltip is the name and the job")
	check(not refs.has("trust_head") or not refs.trust_head.visible, "no trust row")
	Kit.free_all(ctx)


# ------------------------------------------------------------------------ layout --

## A busy yard: the community's panel for `id` open in the dock, an idea and two other calls waiting, alerts, the legend.
func _busy(width: int, height: int, id: String, news_open: bool) -> Dictionary:
	var ctx := _community(width, height)
	var h = ctx.hud
	var radio = ctx.sim.radio
	ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 600.0)
	ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 600.0)
	radio.log_news("bond", "Dez and Ana are close now", "They work the bench side by side")
	radio.log_news("rift", "Walt and Dez are at odds", "They share a wall")
	radio.log_news("title", "Ana is the camp's medic now", "Medicine 10, 8 treated")
	var idea := _idea_call(radio, "I could fix the east wall properly. About 20 scrap.", "Yes: put up a workshop properly (30 scrap)")
	var wall := _wall_call(radio)
	ctx.sim.initiative.opinions[idea] = {"who": "ana", "first": "Ana", "title": "the medic", "option": "yes", "line": "Ana, the medic: yes, it is cheap."}
	ctx.sim.initiative.opinions[wall] = OPINION.duplicate()
	# Walt is the marksman (the widest chip row there is: the title and 'Steady hands' and 'Sharp-eyed'), Marcus is at odds with two
	ctx.sim.specialists.titles["walt"] = {"id": "marksman", "name": "the marksman", "short": "Marksman", "since_day": 5}
	ctx.sim.specialists.effects["marksman"] = {"mult": {"aim": 1.04}}
	ctx.sim.relations.pairs.append({"a": "marcus", "b": "walt", "v": -70.0, "kind": "rival", "since": 7})
	ctx.sim.relations.pairs.append({"a": "marcus", "b": "hector", "v": -40.0, "kind": "rival", "since": 8})
	var p = Kit.person(ctx, id)
	p.hunger_h = 40.0
	p.wounds = 2
	ctx.sim.morale.values[p.id] = 30.0
	h.set_fields(true)
	Kit.select(ctx, p)
	if news_open:
		h.toggle_news()
	Kit.update(ctx)
	await Kit.settle()
	Kit.update(ctx)
	await Kit.settle()
	return ctx


func test_the_panel_with_a_friend_a_rival_and_a_title_fits_the_dock_at_every_size() -> void:
	for size in SIZES:
		for id in ["ana", "dez", "walt", "marcus"]:
			var ctx: Dictionary = await _busy(size[0], size[1], id, false)
			var h = ctx.hud
			var where := "%s at %d x %d" % [id, size[0], size[1]]
			var refs := _refs(ctx)
			var win := Rect2(0, 0, size[0], size[1])
			var rects := _rects(ctx)
			eq(Kit.overlaps(rects), [], where)
			var panel := Kit.rect(h.inspect)
			check(win.encloses(panel.grow(-0.5)), "%s: the panel is inside the window (%s)" % [where, str(panel)])
			check(h.inspect.get_combined_minimum_size().x <= float(Hud.INSPECT_W), "%s: it does not ask for more than its width (%s)" % [where, str(h.inspect.get_combined_minimum_size())])
			if not h.dock.vertical:
				eq(panel.size.x, float(Hud.INSPECT_W), "%s: and keeps its width" % where)
			check(win.encloses(Kit.rect(h.radio_box).grow(-0.5)), "%s: the verbs are inside the window too (%s)" % [where, str(Kit.rect(h.radio_box))])
			if id == "dez" or id == "walt" or id == "marcus":
				check(refs.rivals_head.visible and refs.rivals.visible, "%s: the rivals' row is shown" % where)
				var r := Kit.rect(refs.rivals)
				check(panel.encloses(r.grow(-0.5)) and r.size.x > 20.0, "%s: and inside the panel (%s in %s)" % [where, str(r), str(panel)])
			if id == "ana" or id == "walt":
				var chip := Kit.rect(refs.traits_box.get_child(0))
				check(panel.encloses(chip.grow(-0.5)) and chip.size.x > 20.0, "%s: the title's chip is inside the panel (%s in %s)" % [where, str(chip), str(panel)])
				var row := Kit.rect(refs.traits_box)
				check(panel.encloses(row.grow(-0.5)), "%s: and the row of chips (%s)" % [where, str(row)])
			Kit.free_all(ctx)


func test_no_title_with_any_two_traits_widens_the_panel() -> void:
	var ctx := Kit.build(1280, 800, 1, true)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.avatar.set_player("ruth")
	sim.relations = FakeRelations.new()
	sim.specialists = FakeSpecialists.new()
	sim.initiative = FakeInitiative.new()
	for m in [sim.relations, sim.specialists, sim.initiative]:
		m.setup(sim)
	var ids: Array = []
	for id in sim.traits.defs:
		ids.append(id)
	check(ids.size() >= 10, "the game has its traits (%d)" % ids.size())
	var walt = Kit.person(ctx, "walt")
	var widest := 0.0
	var bad: Array = []
	for title in [["medic", "the medic", "Medic"], ["engineer", "the engineer", "Engineer"], ["marksman", "the marksman", "Marksman"], ["scout", "the scout", "Scout"]]:
		sim.specialists.titles["walt"] = {"id": title[0], "name": title[1], "short": title[2], "since_day": 5}
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				sim.traits.assigned["walt"] = [ids[i], ids[j]]
				Kit.select(ctx, walt)
				Kit.update(ctx)
				var need: float = ctx.hud.inspect.get_combined_minimum_size().x
				widest = maxf(widest, need)
				if need > float(Hud.INSPECT_W):
					bad.append("%s with %s and %s: %.0f" % [title[2], ids[i], ids[j], need])
	eq(bad, [], "titles and traits that make the panel wider than %d (widest %.0f)" % [Hud.INSPECT_W, widest])
	Kit.free_all(ctx)


func test_the_call_card_with_an_idea_and_the_voices_line_fits_at_every_size() -> void:
	for size in SIZES:
		for news_open in [false, true]:
			var ctx: Dictionary = await _busy(size[0], size[1], "ana", news_open)
			var h = ctx.hud
			var where := "%d x %d, news %s" % [size[0], size[1], news_open]
			var win := Rect2(0, 0, size[0], size[1])
			var rects := _rects(ctx)
			eq(Kit.overlaps(rects), [], where)
			for name in rects:
				var r: Rect2 = rects[name]
				if r.size.x > 1.0 and r.size.y > 1.0:
					check(win.encloses(r.grow(-0.5)), "%s: %s is in the window: %s" % [where, name, str(r)])
			# the column is as wide as the clock: a long yes must not make the card wider than that
			var width := Kit.rect(h.clock).size.x
			if news_open:
				# (round 18: the News is a page of the radio panel, a board of its own with its form's width, not the clock's)
				var form := RadioPanel.WIDTH_COMPACT if h.compact else RadioPanel.WIDTH
				var panel := Kit.rect(h.radio_panel)
				check(h.news_panel.call_views.size() == 2, "%s: the News holds both calls" % where)
				check(panel.size.x <= form + 0.5, "%s: the panel keeps its form's width (%s)" % [where, str(panel)])
				check(Kit.rect(h.news_panel).size.x <= panel.size.x + 0.5, "%s: and the News keeps inside it (%s)" % [where, str(Kit.rect(h.news_panel))])
				for v in h.news_panel.call_views:    # (the list scrolls, so only across: no button of a call is wider than the page)
					for b in v.buttons.values():
						var r := Kit.rect(b)
						var page := Kit.rect(h.news_panel)
						check(r.position.x >= page.position.x - 0.5 and r.end.x <= page.end.x + 0.5, "%s: every button of a call is across the News (%s, the page %s)" % [where, str(r), str(page)])
			else:
				# (round 19 fix: the card shows the most urgent open call, the wall's, and not the oldest, the idea. The idea's card is what this
				# test is about: the wall's call is answered first, as the player would, and the idea comes up)
				check(Kit.rect(h.call_card).size.x <= width + 0.5, "%s: the wall's card does not widen either" % where)
				for c in ctx.sim.radio.open_calls():
					if String(c.kind) != "idea":
						ctx.sim.radio.answer(int(c.id), String(c.default))
				Kit.update(ctx)
				await Kit.settle()
				check(Kit.rect(h.call_card).size.x > 60.0, "%s: the card is up" % where)
				check(Kit.rect(h.call_card).size.x <= width + 0.5, "%s: and does not widen for the long yes (%s, the clock is %.0f wide)" % [where, str(Kit.rect(h.call_card)), width])
				var btn: Button = h.call_card.view.buttons["yes"]
				check(h.call_card.get_global_rect().encloses(btn.get_global_rect().grow(-0.5)), "%s: the yes button is inside the card" % where)
			Kit.free_all(ctx)


func test_the_new_words_are_12_px_or_more_and_read_on_what_they_sit_on() -> void:
	var tt := TextTests.new()
	for frames in [true, false]:
		Hud.use_frames = frames
		for size in [[1280, 800], [700, 560]]:
			for news_open in [false, true]:
				var ctx: Dictionary = await _busy(size[0], size[1], "ana", news_open)
				var h = ctx.hud
				var where := "%s, %d x %d, news %s" % ["frames" if frames else "flat", size[0], size[1], news_open]
				for part in [h.inspect, h.call_card, h.news_panel, h.radio_box]:
					eq(tt._small_text(part), [], "%s: nothing under 12 px in %s" % [where, part.name])
					eq(tt._hard_to_read(part, Color.WHITE), [], "%s: every word in %s reads at 4.5:1" % [where, part.name])
				_open(ctx, "dez")
				eq(tt._small_text(h.inspect), [], "%s: Dez's panel, nothing under 12 px" % where)
				eq(tt._hard_to_read(h.inspect, Color.WHITE), [], "%s: and every word reads" % where)
				Kit.free_all(ctx)
	Hud.use_frames = true


func test_every_new_control_takes_no_focus() -> void:
	var ctx: Dictionary = await _busy(1280, 800, "ana", true)
	var h = ctx.hud
	var bad: Array = []
	for part in [h.inspect, h.call_card, h.news_panel]:
		var nodes: Array = [part]
		nodes.append_array(part.find_children("*", "Control", true, false))
		for c in nodes:
			if c is Control and c.focus_mode != Control.FOCUS_NONE:
				bad.append("%s %s" % [c.get_class(), c.name])
	_open(ctx, "dez")
	for c in h.inspect.find_children("*", "Control", true, false):
		if c.focus_mode != Control.FOCUS_NONE:
			bad.append("%s %s" % [c.get_class(), c.name])
	eq(bad, [], "nothing the community adds can take the keyboard")
	Kit.free_all(ctx)


# ------------------------------------------------------------- the real modules --
# The game's own relations, specialists and initiative (the SIM builders') under the same views: what the rules say is what the
# player reads. A small avatar start (a classic six start has none of it), Ruth the player.

func _real(width: int = 1280, height: int = 800) -> Dictionary:
	var ctx := Kit.build(width, height, 1, true)
	var sim = ctx.sim
	sim.recruits.small = true
	sim.waves.enabled = false
	sim.zombies.clear()
	check(sim.avatar.set_player("ruth"), "Ruth is the player")
	Kit.update(ctx)
	return ctx


## Dez and Ana are friends, Walt and Dez at odds, Ana has earned the medic's title (Medicine 10, 8 treated).
func _real_community(ctx: Dictionary) -> void:
	var sim = ctx.sim
	var dez = Kit.person(ctx, "dez")
	var ana = Kit.person(ctx, "ana")
	var walt = Kit.person(ctx, "walt")
	sim.relations.add(dez, ana, 60.0, "test")
	sim.relations.add(walt, dez, -50.0, "test")
	ana.skills["Medicine"] = 10
	ana.stats["treated"] = 8
	sim.specialists.look()
	Kit.update(ctx)


func test_with_the_real_modules_a_friend_a_rival_and_a_title_show_in_the_person_panel() -> void:
	var ctx := _real()
	_real_community(ctx)
	var sim = ctx.sim
	check(sim.relations.active() and sim.specialists.active() and sim.initiative.active(), "the three modules are at work in this game")
	eq(String(sim.specialists.title_of(Kit.person(ctx, "ana")).get("id", "")), "medic", "Ana has the medic's title")
	_open(ctx, "dez")
	var refs := _refs(ctx)
	check(refs.bonds.text.contains("Ana (friend)"), "Dez's Bonds row lists the friend he made in play: %s" % refs.bonds.text)
	var tip := _flat(refs.bonds.tooltip_text)
	check(tip.contains("Ana: friends") or tip.contains("Ana: close"), "and says how it stands: %s" % tip)
	check(tip.contains("since day"), "and since when: %s" % tip)
	check(refs.has("rivals_head") and refs.rivals_head.visible, "his Rivals row is there")
	eq(refs.rivals.text, "Walt (at odds)", "Walt, at odds")
	check(_flat(refs.rivals.tooltip_text).contains("on edge") and _flat(refs.rivals.tooltip_text).contains("since day"), "with what it does and since when: %s" % refs.rivals.tooltip_text)
	_open(ctx, "ana")
	var chip = _refs(ctx).traits_box.get_child(0)
	eq(Kit.texts(chip), ["Medic"], "Ana's first chip is the title")
	var chip_tip := _flat(chip.tooltip_text)
	check(chip_tip.contains("The medic since day"), "since when: %s" % chip_tip)
	check(chip_tip.contains("Medicine 10, 8 treated"), "the practice, in the module's words: %s" % chip_tip)
	check(chip_tip.contains("Bandages 25% faster"), "the bonus, in the module's numbers: %s" % chip_tip)
	check(chip_tip.contains("First choice for the infirmary"), "and the seat: %s" % chip_tip)
	eq(_refs(ctx).traits_box.get_child_count(), 1 + sim.traits.of(Kit.person(ctx, "ana")).size(), "the title and her traits")
	Kit.free_all(ctx)


func test_with_the_real_modules_the_card_tooltip_and_the_news_follow() -> void:
	var ctx := _real()
	_real_community(ctx)
	var ana_tip: String = Kit.card(ctx, Kit.person(ctx, "ana")).card.tooltip_text
	check(ana_tip.split("\n").has("The medic"), "Ana's card: the title: %s" % ana_tip)
	check(ana_tip.contains("Close to") and ana_tip.contains("Dez"), "and who she is close to: %s" % ana_tip)
	var dez_tip: String = Kit.card(ctx, Kit.person(ctx, "dez")).card.tooltip_text
	check(dez_tip.contains("At odds with Walt"), "Dez's card: at odds with Walt: %s" % dez_tip)
	var kinds: Array = []
	for e in ctx.sim.radio.news:
		kinds.append(String(e.kind))
	check(kinds.has("bond") and kinds.has("rift") and kinds.has("title"), "the modules logged a bond, a rift and a title: %s" % str(kinds))
	ctx.hud.toggle_news()
	Kit.update(ctx)
	await Kit.settle()
	var panel = ctx.hud.news_panel
	for k in ["bond", "rift", "title"]:
		check(panel.row_kinds().has(k), "the News draws the %s line" % k)
	var all := _texts_of(panel)
	check(all.contains("PEOPLE") and all.contains("FALLING OUT") and all.contains("KNOWN FOR"), "with the kinds' names: %s" % all)
	var tt := TextTests.new()
	eq(tt._small_text(panel), [], "nothing under 12 px")
	eq(tt._hard_to_read(panel, Color.WHITE), [], "and every word reads")
	Kit.free_all(ctx)


func test_with_the_real_modules_the_voices_opinion_shows_under_a_fever_and_an_idea() -> void:
	var ctx := _real()
	_real_community(ctx)
	var sim = ctx.sim
	var radio = sim.radio
	# the medic, with medicine enough, says treat them
	sim.stock.meds = 10.0
	var fever: int = radio.raise_call("sick", "Hector has a fever", "Treat them, or keep them apart", [
		{"id": "treat", "label": "Treat them"}, {"id": "apart", "label": "Keep them apart"},
	], "treat", 60.0, {"who": "hector"}, Vector2(30, 30))
	Kit.update(ctx)
	await Kit.settle()
	var view = ctx.hud.call_card.view
	eq(ctx.hud.call_card.shown_id, fever, "the fever is on the card")
	eq(view.opinion_label.text, "Ana, the medic: treat them.", "the medic's opinion, from the module")
	check(view.opinion_label.is_visible_in_tree(), "on show")
	sim.stock.meds = 0.0
	Kit.update(ctx)
	eq(view.opinion_label.text, "Ana, the medic: keep them apart.", "and it follows the stock: no medicine, keep them apart")
	# an idea: the voice says yes when it is cheap (never on their own idea)
	view.buttons["treat"].pressed.emit()
	sim.relations.add(Kit.person(ctx, "ana"), Kit.person(ctx, "hector"), 70.0, "test")
	sim.relations.add(Kit.person(ctx, "ana"), Kit.person(ctx, "marcus"), 70.0, "test")
	sim.relations.update(sim.relations.TICK_S + 0.1)
	var voice = sim.relations.voice()
	check(voice != null, "somebody is the voice now")
	if voice != null:
		sim.stock.scrap = 200.0
		var idea: int = radio.raise_call("idea", "I could fix the east wall properly. About 20 scrap.", "Dez, the engineer", [
			{"id": "yes", "label": "Yes: fix the wall (20 scrap)"}, {"id": "later", "label": "Later"}, {"id": "no", "label": "No"},
		], "later", 360.0, {"idea": "fix_wall", "who": "dez", "others": [], "args": {}, "cost": {"scrap": 20.0}, "line": ""}, Vector2(40, 10))
		ctx.hud.call_card.result_ms = 0
		Kit.update(ctx)
		eq(ctx.hud.call_card.shown_id, idea, "the idea is on the card")
		eq(view.kind_label.text, "IDEA", "an idea")
		check(view.opinion_label.text.ends_with("yes, we can spare it."), "the voice's opinion, from the module: %s" % view.opinion_label.text)
		check(view.opinion_label.text.begins_with(String(voice.first)), "by the voice, %s: %s" % [voice.first, view.opinion_label.text])
		eq(view.buttons.keys(), ["yes", "later", "no"], "with its three buttons")
	Kit.free_all(ctx)


func test_with_the_real_modules_but_no_avatar_nothing_of_it_shows() -> void:
	var ctx := Kit.build(1280, 800, 1, true)
	var sim = ctx.sim
	sim.waves.enabled = false
	Kit.update(ctx)
	check(not sim.relations.active() and not sim.specialists.active() and not sim.initiative.active(), "no avatar: the modules are off")
	var ana = Kit.person(ctx, "ana")
	ana.skills["Medicine"] = 10
	ana.stats["treated"] = 8
	_open(ctx, "ana")
	eq(_refs(ctx).traits_box.get_child_count(), sim.traits.of(ana).size(), "no title chip")
	check(not _refs(ctx).get("rivals_head", null) or not _refs(ctx).rivals_head.visible, "no rivals row")
	var tip: String = Kit.card(ctx, ana).card.tooltip_text
	eq(tip.split("\n").size(), 1, "the card's tooltip is the name and the job: %s" % tip)
	Kit.free_all(ctx)


func test_with_the_real_modules_the_orientation_day_keeps_the_panel_quiet() -> void:
	var ctx := _real()
	_real_community(ctx)
	for m in [ctx.sim.relations, ctx.sim.specialists, ctx.sim.initiative]:
		m.enabled = false
	_open(ctx, "dez")
	check(not _refs(ctx).get("rivals_head", null) or not _refs(ctx).rivals_head.visible, "no rivals row")
	_open(ctx, "ana")
	eq(_refs(ctx).traits_box.get_child_count(), ctx.sim.traits.of(Kit.person(ctx, "ana")).size(), "no title chip")
	var tip: String = Kit.card(ctx, Kit.person(ctx, "ana")).card.tooltip_text
	eq(tip.split("\n").size(), 1, "and the card says only the name and the job: %s" % tip)
	Kit.free_all(ctx)
