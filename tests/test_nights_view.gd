extends "res://tests/case.gd"
## Round 19, V3.1 FORECAST-VIEW (docs/superpowers/plans/2026-10-03-round-19.md, S3.4 and "The views"): what the screen says of the nights.
## The clock column (the outlook of tonight in avatar mode, the community's own prediction under it, the Big Night badge), the radio's new
## kinds of news and call (a wall going, a brute, a breach, the night, the forecast, the road), the marks in the yard (the brunt of the night,
## the rally ring, a plated brute and its weak point, a hot breach), the place's "leave by" line and the Town Board's note.
## The rules these read are the sim's own (tests/test_forecast.gd, test_nights_*.gd, test_night_calls.gd); here the sim's answers are set by
## hand (the HUD kit's fake tactics, stand-ins for the nights module and the night calls), so this file does not depend on them landing.

const Helpers := preload("res://tests/helpers.gd")
const Kit := preload("res://tests/hud_kit.gd")
const TutorialKit := preload("res://tests/tutorial_kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const NightKit := preload("res://scripts/ui/night_kit.gd")
const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const NightData := preload("res://scripts/sim/night_data.gd")
const PlaceFlow := preload("res://scripts/raid/place_flow.gd")

const SIZES := [[1280, 800], [980, 700], [700, 700], [960, 600], [700, 560]]


# ---------------------------------------------------------------- helpers --

## A forecast as `Kit.forecast` has it, with `with` laid over it.
func _fc(base: Dictionary, with: Dictionary = {}) -> Dictionary:
	var f := Kit.forecast(base)
	f.merge(with, true)
	return f


## Tonight is the Siege: what `tactics.forecast()` says of a Big Night in avatar mode (the keys of S3.1).
func _siege(with: Dictionary = {}) -> Dictionary:
	return _fc({
		"kind": "milestone", "name": "The Siege", "total": 82, "low": 70, "high": 95, "side": "east", "heading": "east",
		"sections": [3, 4], "section_text": "the east side: the second bus, the chain-link", "brutes": 2, "plated": 2, "runners": false,
		"first_at": 21.0, "brute_at": 23.0, "needs_you": true, "big": false,
		"ready": {"walls": 0.82, "guns": 3, "manned": 5, "posts": 5, "holds": true},
	}, with)


## An ordinary night of the same keys.
func _plain(with: Dictionary = {}) -> Dictionary:
	return _fc({
		"kind": "ordinary", "name": "Tonight", "total": 55, "low": 47, "high": 63, "side": "north east", "heading": "north east",
		"sections": [3], "section_text": "the north east side: the chain-link", "brutes": 0, "plated": 0, "runners": false,
		"first_at": 20.0, "brute_at": -1.0, "needs_you": false, "big": false,
		"ready": {"walls": 0.9, "guns": 3, "manned": 5, "posts": 5, "holds": true},
	}, with)


## A HUD over a quiet game in avatar mode (Ruth is the player), the HUD has seen it once.
func _ctx(width: int = 1280, height: int = 800, player: String = "ruth") -> Dictionary:
	var ctx := Kit.build(width, height)
	var sim = ctx.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	if player != "":
		check(sim.avatar.set_player(player), "%s is the player" % player)
	Kit.update(ctx)
	return ctx


func _tell(ctx: Dictionary, f: Dictionary, phase: String = "night") -> void:
	ctx.sim.phase = phase
	ctx.sim.tactics.told = f
	Kit.update(ctx)


func _lum(c: Color) -> float:
	var out := 0.0
	var k := [0.2126, 0.7152, 0.0722]
	var v := [c.r, c.g, c.b]
	for i in 3:
		var x: float = v[i]
		x = x / 12.92 if x <= 0.03928 else pow((x + 0.055) / 1.055, 2.4)
		out += k[i] * x
	return out


func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## The lightest the clock's own board is behind its words (the worst case for light text).
func _clock_back(ctx: Dictionary) -> Color:
	var fills := Kit.fills(ctx.hud.clock.get_theme_stylebox("panel"))
	var back: Color = fills[1]
	# (a translucent board over the brightest of worlds: white)
	return Color(back.r * back.a + (1.0 - back.a), back.g * back.a + (1.0 - back.a), back.b * back.a + (1.0 - back.a), 1.0)


# ------------------------------------------------------------ the pure words --

func test_an_hour_is_written_with_two_digits_and_wraps_at_midnight() -> void:
	eq(NightKit.hour_text(21.0), "21:00", "an even hour")
	eq(NightKit.hour_text(23.5), "23:30", "half past")
	eq(NightKit.hour_text(5.0), "05:00", "early")
	eq(NightKit.hour_text(24.5), "00:30", "past midnight")
	eq(NightKit.hour_text(15.999), "16:00", "a minute that rounds up")


func test_the_line_of_a_big_night_says_the_size_the_side_the_plated_brutes_and_the_hours() -> void:
	eq(NightKit.forecast_line(_siege()), "The Siege: about 70 to 95 from the east side, 2 plated brutes after 23:00, first about 21:00", "the plan's own line")
	eq(NightKit.forecast_line(_siege({"plated": 1, "brutes": 1})), "The Siege: about 70 to 95 from the east side, a plated brute after 23:00, first about 21:00", "one")
	eq(NightKit.forecast_line(_siege({"brute_at": -1.0})), "The Siege: about 70 to 95 from the east side, 2 plated brutes, first about 21:00", "no hour for the brutes: none is told")
	eq(NightKit.forecast_line(_siege({"side": "north and west"})), "The Siege: about 70 to 95 from the north and west, 2 plated brutes after 23:00, first about 21:00", "two ways: no 'side'")
	eq(NightKit.forecast_line(_siege({"first_at": -1.0})), "The Siege: about 70 to 95 from the east side, 2 plated brutes after 23:00", "no first hour: none is told")
	eq(NightKit.forecast_line(_siege({"name": "The Rush", "plated": 0, "brutes": 0, "runners": true})), "The Rush: about 70 to 95 from the east side, runners, first about 21:00", "a rush of runners")


func test_the_line_of_an_ordinary_night_keeps_the_old_shape_with_a_range_and_the_first_hour() -> void:
	eq(NightKit.forecast_line(_plain()), "Tonight: about 47 to 63 from the north east, first about 20:00", "the size, the way, the hour")
	eq(NightKit.forecast_line(_plain({"brutes": 1})), "Tonight: about 47 to 63 from the north east, a brute, first about 20:00", "a brute")
	eq(NightKit.forecast_line(_plain({"brutes": 2})), "Tonight: about 47 to 63 from the north east, 2 brutes, first about 20:00", "two")
	eq(NightKit.forecast_line(_plain({"runners": true})), "Tonight: about 47 to 63 from the north east, runners, first about 20:00", "runners")
	eq(NightKit.forecast_line(_plain({"low": 55, "high": 55})), "Tonight: about 55 from the north east, first about 20:00", "a range of one number is that number")
	eq(NightKit.forecast_line(_plain({"low": 0, "high": 0})), "Tonight: about 55 from the north east, first about 20:00", "no range: the total")
	eq(NightKit.forecast_line(_plain({"side": ""})), "Tonight: about 47 to 63, first about 20:00", "no side told")


func test_the_line_of_the_final_night_says_everywhere_and_the_season_says_which_it_is() -> void:
	var last := _siege({"kind": "final", "name": "The last night", "low": 105, "high": 140, "big": true, "plated": 3, "brutes": 3, "brute_at": 23.5, "first_at": 20.5})
	eq(NightKit.forecast_line(last, true), "The last night: about 105 to 140 from everywhere, 3 plated brutes after 23:30, first about 20:30", "the last night")
	var nameless := _siege({"kind": "final", "name": "", "big": true, "plated": 0, "brutes": 0, "brute_at": -1.0})
	eq(NightKit.forecast_line(nameless, true), "The last night: about 70 to 95 from everywhere, first about 21:00", "no name: the old words")
	eq(NightKit.forecast_line(nameless, false), "The Big Night: about 70 to 95 from everywhere, first about 21:00", "and a season that has others to come")


func test_a_forecast_without_the_outlook_keys_has_no_outlook() -> void:
	check(not NightKit.has_outlook(Kit.forecast()), "the old keys alone")
	check(not NightKit.has_outlook({"given": false}), "none given")
	check(NightKit.has_outlook(_plain()), "an ordinary night with the keys")
	check(NightKit.has_outlook(_siege()), "a Big Night")
	check(NightKit.needs_you(_siege()), "it needs you")
	check(not NightKit.needs_you(_plain()), "an ordinary one does not")
	check(NightKit.needs_you({"kind": "final"}), "the final needs you even if the flag is missing")
	check(not NightKit.needs_you(Kit.forecast()), "the old keys say nothing")


func test_the_ready_line_is_the_communitys_own_prediction() -> void:
	var ok := NightKit.ready_line(_plain())
	eq(ok.text, "Should hold: posts 5 of 5, walls 90%", "an ordinary night, walls decent and every post manned")
	check(ok.holds, "green")
	var thin := NightKit.ready_line(_plain({"ready": {"walls": 0.55, "guns": 3, "manned": 4, "posts": 5, "holds": false}}))
	eq(thin.text, "Posts 4 of 5, walls 55%", "a post empty and a wall worn: the numbers, no promise")
	check(not thin.holds, "amber")
	var one := NightKit.ready_line(_plain({"ready": {"walls": 0.9, "guns": 1, "manned": 5, "posts": 5, "holds": false}}))
	eq(one.text, "Posts 5 of 5, walls 90%, guns 1", "too few guns on the wall are named")
	var big := NightKit.ready_line(_siege())
	eq(big.text, "Posts 5 of 5, walls 82%. This one needs you.", "a Big Night: no promise, and it says so")
	check(big.holds, "(green still means the community is ready)")
	eq(NightKit.ready_line(Kit.forecast()), {}, "no readiness told: nothing")
	eq(NightKit.ready_line(_plain({"ready": {}})), {}, "an empty one")


func test_the_ready_line_rounds_the_walls_and_never_shows_more_than_the_posts() -> void:
	var r := NightKit.ready_line(_plain({"ready": {"walls": 0.499, "guns": 3, "manned": 6, "posts": 5, "holds": false}}))
	eq(r.text, "Posts 5 of 5, walls 50%", "a share rounds to the percent and the manned never pass the posts")
	var z := NightKit.ready_line(_plain({"ready": {"walls": 0.0, "guns": 0, "manned": 0, "posts": 0, "holds": false}}))
	check(z.text.begins_with("Posts 0 of 0"), "no posts at all is still a line: %s" % z.text)


# ------------------------------------------------------------ the clock column --

func test_in_avatar_mode_the_clock_carries_the_outlook_and_the_ready_line_under_it() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	_tell(ctx, _siege())
	check(h.forecast_label.visible, "the line is up")
	eq(h.forecast_label.text, "The Siege: about 70 to 95 from the east side, 2 plated brutes after 23:00, first about 21:00", "the outlook")
	check(h.ready_label.visible, "and the readiness under it")
	eq(h.ready_label.text, "Posts 5 of 5, walls 82%. This one needs you.", "its words")
	eq(h.ready_label.get_theme_color("font_color"), Hud.OK, "green: the community is ready")
	_tell(ctx, _siege({"ready": {"walls": 0.5, "guns": 1, "manned": 4, "posts": 5, "holds": false}}))
	eq(h.ready_label.text, "Posts 4 of 5, walls 50%, guns 1. This one needs you.", "a thin community")
	eq(h.ready_label.get_theme_color("font_color"), Hud.WARN, "amber when it will not hold")
	_tell(ctx, _plain())
	eq(h.forecast_label.text, "Tonight: about 47 to 63 from the north east, first about 20:00", "an ordinary night")
	eq(h.ready_label.text, "Should hold: posts 5 of 5, walls 90%", "which should hold")
	eq(h.ready_label.get_theme_color("font_color"), Hud.OK, "green")
	var rows: Array = h.forecast_label.get_parent().get_children()
	eq(rows[rows.size() - 2], h.forecast_label, "the forecast is the second row from the foot of the clock")
	eq(rows[rows.size() - 1], h.ready_label, "and the readiness is the last")
	Kit.free_all(ctx)


func test_without_an_avatar_the_old_line_is_all_there_is_whatever_keys_the_forecast_has() -> void:
	var ctx := _ctx(1280, 800, "")
	var h = ctx.hud
	_tell(ctx, _siege({"big": false}))
	eq(h.forecast_label.text, "Tonight: about 82 from the east, 2 brutes", "the old words from the old keys")
	check(not h.ready_label.visible and h.ready_label.text == "", "no readiness line")
	check(not h.night_badge.visible, "and no badge")
	_tell(ctx, Kit.forecast({"big": true, "total": 120}))
	eq(h.forecast_label.text, "The last night: about 120, from everywhere", "the last night as ever")
	Kit.free_all(ctx)


func test_in_avatar_mode_an_old_forecast_without_the_new_keys_reads_as_it_always_did() -> void:
	var ctx := _ctx()
	_tell(ctx, Kit.forecast())
	eq(ctx.hud.forecast_label.text, "Tonight: about 55 from the north east", "the keys are not there: the old line")
	check(not ctx.hud.ready_label.visible, "and no readiness")
	Kit.free_all(ctx)


func test_the_forecast_and_the_readiness_come_and_go_with_the_night() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	_tell(ctx, _siege(), "day")
	check(h.forecast_label.visible and h.ready_label.visible, "up from the lookout's hour")
	_tell(ctx, _siege(), "dawn")
	check(not h.forecast_label.visible and not h.ready_label.visible, "gone at dawn")
	_tell(ctx, {"given": false}, "night")
	check(not h.forecast_label.visible and not h.ready_label.visible, "and gone when nobody told it")
	Kit.free_all(ctx)


func test_the_ready_colours_read_on_the_clock_at_four_and_a_half_to_one() -> void:
	var ctx := _ctx()
	var back := _clock_back(ctx)
	for c in [Hud.OK, Hud.WARN, Hud.INK, Hud.INK2, Hud.DANGER_TEXT, Hud.INFO]:
		check(_contrast(c, back) >= 4.5, "%s reads on the clock (%.2f:1)" % [c.to_html(false), _contrast(c, back)])
	Kit.free_all(ctx)


const TextTests := preload("res://tests/test_hud_text.gd")


func test_every_new_word_of_the_clock_reads_over_the_brightest_ground_with_and_without_the_frames() -> void:
	var tt := TextTests.new()
	for frames in [true, false]:
		Hud.use_frames = frames
		var look := "frames" if frames else "flat"
		for holds in [true, false]:
			var ctx := _ctx()
			Helpers.at(ctx.sim, 9, 13.0)
			_notice(ctx)
			_tell(ctx, _siege({"ready": {"walls": 0.5, "guns": 1, "manned": 4, "posts": 5, "holds": holds}}), "day")
			var h = ctx.hud
			check(h.night_badge.visible and h.ready_label.visible and h.forecast_label.visible, "%s: all three are up" % look)
			for l in [h.night_badge_label, h.ready_label, h.forecast_label]:
				var ratio: float = tt._worst_contrast(l, l.get_theme_color("font_color"), Color.WHITE)
				check(ratio >= tt.AA, "%s, holds %s: '%s' reads at %.2f:1" % [look, str(holds), str(l.text).left(24), ratio])
			Kit.free_all(ctx)
	Hud.use_frames = true


# ------------------------------------------------------------------- the badge --

func _notice(ctx: Dictionary, day: int = -1) -> void:
	var e: Dictionary = ctx.sim.radio.log_news("forecast", "Big Night tomorrow: The Siege", "About 70 to 95 from the east side (the second bus, the chain-link). 2 plated brutes after 23:00. Be home by 17:20.")
	if day >= 0:
		e["day"] = day


func test_a_day_ahead_a_badge_sits_in_the_clock_once_the_notice_is_given() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	Helpers.at(ctx.sim, 9, 11.0)
	Kit.update(ctx)
	check(not h.night_badge.visible, "no notice, no badge (the night still comes)")
	Helpers.at(ctx.sim, 9, 12.0)
	_notice(ctx)
	Kit.update(ctx)
	check(h.night_badge.visible, "the notice is given: the badge")
	eq(h.night_badge_label.text, "Big Night tomorrow", "its words")
	eq(h.badge_state(), "tomorrow", "its state")
	eq(h.night_badge_label.get_theme_color("font_color"), Hud.DANGER_BADGE, "in the danger colour (a lighter red: it reads on its own chip)")
	check(h.night_badge.tooltip_text.contains("The Siege") and h.night_badge.tooltip_text.contains("Be home by 17:20"), "the tooltip is the notice: %s" % h.night_badge.tooltip_text)
	Helpers.at(ctx.sim, 9, 20.0)
	Kit.update(ctx)
	check(h.night_badge.visible and h.badge_state() == "tomorrow", "through the evening of today")
	Kit.free_all(ctx)


func test_the_badge_is_for_one_day_and_only_in_avatar_mode() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	Helpers.at(ctx.sim, 9, 13.0)
	_notice(ctx)
	Helpers.at(ctx.sim, 10, 8.0)
	Kit.update(ctx)
	check(h.badge_state() != "tomorrow", "the morning after: it is no longer tomorrow")
	Kit.free_all(ctx)
	var old := _ctx(1280, 800, "")
	Helpers.at(old.sim, 9, 13.0)
	_notice(old)
	Kit.update(old)
	check(not old.hud.night_badge.visible, "no avatar, no badge")
	Kit.free_all(old)


func test_tonight_the_badge_says_big_night_from_the_forecast_and_from_a_notice_the_day_before() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	Helpers.at(ctx.sim, 10, 17.5)
	_tell(ctx, _siege(), "day")
	check(h.night_badge.visible, "the lookout told it: the badge")
	eq(h.badge_state(), "tonight", "tonight")
	eq(h.night_badge_label.text, "Big Night", "its words")
	check(h.night_badge.tooltip_text.contains("The Siege"), "the tooltip says which: %s" % h.night_badge.tooltip_text)
	_tell(ctx, _plain(), "day")
	check(not h.night_badge.visible, "an ordinary night has none")
	_tell(ctx, _siege(), "dawn")
	check(not h.night_badge.visible, "and it is gone at dawn")
	Kit.free_all(ctx)


func test_a_notice_given_the_day_before_keeps_the_badge_through_the_day_of_the_big_night() -> void:
	var ctx := _ctx()
	var h = ctx.hud
	# a stand-in for the waves that knows tonight is a Big Night
	var waves := FakeWaves.new()
	waves.setup(ctx.sim)
	waves.enabled = false
	waves.big = {"kind": "milestone", "id": "siege", "name": "The Siege"}
	ctx.sim.waves = waves
	Helpers.at(ctx.sim, 9, 13.0)
	_notice(ctx)
	Helpers.at(ctx.sim, 10, 9.0)
	Kit.update(ctx)
	check(h.night_badge.visible and h.badge_state() == "tonight", "told yesterday: tonight it says so, even before the lookout")
	eq(h.night_badge_label.text, "Big Night", "its words")
	waves.big = {}
	Kit.update(ctx)
	check(not h.night_badge.visible, "and not for a night that is not Big")
	Kit.free_all(ctx)


## Waves that say what the test tells them of tonight (the real ones, otherwise).
class FakeWaves:
	extends "res://scripts/sim/waves.gd"
	var big := {}

	func big_night(_day: int) -> Dictionary:
		return big


func test_the_badge_is_named_for_the_tutorial_and_keeps_inside_the_clock_at_every_size() -> void:
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		var h = ctx.hud
		Helpers.at(ctx.sim, 9, 13.0)
		_notice(ctx)
		_tell(ctx, _plain(), "day")
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var where := "%d x %d" % [size[0], size[1]]
		var clock: Rect2 = Kit.rect(h.clock)
		var badge: Rect2 = Kit.rect(h.night_badge)
		check(badge.size != Vector2.ZERO and clock.encloses(badge), "%s: the badge is inside the clock (%s in %s)" % [where, str(badge), str(clock)])
		check(h.anchor_rect("clock.night") == h.night_badge.get_global_rect(), "%s: the anchor clock.night is the badge" % where)
		check(h.night_badge_label.get_theme_font_size("font_size") >= 12, "%s: 12 px or more" % where)
		check(h.night_badge_label.get_line_count() <= 2, "%s: two lines at most" % where)
		var day: Rect2 = Kit.rect(h.day_label)
		if day.size != Vector2.ZERO:
			check(badge.position.y >= day.end.y - 0.5, "%s: the badge is under the day counter's row, not over it" % where)
		Kit.free_all(ctx)


func test_the_forecast_lines_fit_the_clock_and_push_the_alerts_down_at_every_size() -> void:
	for size in SIZES:
		var ctx := _ctx(size[0], size[1])
		var h = ctx.hud
		ctx.sim.alert("a1", "danger", "Marcus is down", "Get them to Ana", null, 600.0)
		ctx.sim.alert("a2", "warn", "Food is running out", "about 2 days left", null, 600.0)
		Helpers.at(ctx.sim, 9, 13.0)
		_notice(ctx)
		_tell(ctx, _siege({"ready": {"walls": 0.5, "guns": 1, "manned": 4, "posts": 5, "holds": false}}), "day")
		await Kit.settle()
		Kit.update(ctx)
		await Kit.settle()
		var where := "%d x %d" % [size[0], size[1]]
		var clock: Rect2 = Kit.rect(h.clock)
		var alerts: Rect2 = Kit.rect(h.alerts_box)
		for name in ["forecast_label", "ready_label", "night_badge"]:
			var r: Rect2 = Kit.rect(h.get(name))
			check(r.size != Vector2.ZERO and clock.encloses(r), "%s: %s is inside the clock (%s in %s)" % [where, name, str(r), str(clock)])
		for l in [h.forecast_label, h.ready_label]:
			var font: Font = l.get_theme_font("font")
			check(l.get_theme_font_size("font_size") >= 12, "%s: 12 px or more" % where)
			check(Kit.rect(l).size.y + 0.5 >= float(l.get_line_count()) * float(font.get_height(12)), "%s: room for all %d lines" % [where, l.get_line_count()])
		eq(Kit.overlaps({"clock": clock, "alerts": alerts}), [], "%s: the alerts clear the clock" % where)
		check(Rect2(0, 0, size[0], size[1]).encloses(clock.grow(-0.5)), "%s: the clock is in the window" % where)
		check(Kit.rect(h.ready_label).position.y >= Kit.rect(h.forecast_label).end.y - 0.5, "%s: the readiness is under the forecast" % where)
		Kit.free_all(ctx)


# ------------------------------------------------------------- the radio's kinds --

func test_the_new_kinds_of_news_have_their_names_and_colours() -> void:
	var ctx := _ctx()
	var names := {"going": "Wall", "brute": "Brute", "breach": "Breach", "night": "Night", "forecast": "Forecast", "night_road": "Road"}
	for kind in names:
		eq(RadioKit.kind_name(kind), names[kind], "%s is called %s" % [kind, names[kind]])
	for kind in ["going", "brute", "breach"]:
		eq(RadioKit.kind_color(ctx.hud, kind), Hud.DANGER_TEXT, "%s is red" % kind)
	for kind in ["night", "forecast", "night_road"]:
		eq(RadioKit.kind_color(ctx.hud, kind), Hud.INFO, "%s is blue" % kind)
	eq(RadioKit.kind_name("attack"), "Attack", "the old ones are as they were")
	eq(RadioKit.kind_color(ctx.hud, "attack"), Hud.DANGER_TEXT, "the old colours too")
	eq(RadioKit.kind_color(ctx.hud, "sick"), Hud.WARN, "a fever is amber")
	Kit.free_all(ctx)


func test_a_wall_going_is_a_card_with_its_four_ways_to_answer() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	var id: int = radio.raise_call("going", "The east wall is going", "Three of the dead are at the boards, 35% left", [
		{"id": "hold", "label": "Hold"}, {"id": "reinforce", "label": "Send two to it"}, {"id": "coming", "label": "I'm on my way"}, {"id": "fall_back", "label": "Give it up, fall back to the school"},
	], "hold", 20.0, {"seg": 3}, Vector2(60, 30))
	Kit.update(ctx)
	await Kit.settle()
	var h = ctx.hud
	check(h.call_card.visible, "a card")
	eq(h.call_card.shown_id, id, "for it")
	var view = h.call_card.view
	eq(view.kind_label.text, "WALL", "its kind")
	eq(view.kind_label.get_theme_color("font_color"), Hud.DANGER_TEXT, "in red")
	eq(view.buttons.keys(), ["hold", "reinforce", "coming", "fall_back"], "a button for each way")
	for b in view.buttons.values():
		check(b.focus_mode == Control.FOCUS_NONE, "no focus")
		check(b.get_theme_font_size("font_size") >= 12, "12 px or more")
	view.buttons["coming"].pressed.emit()
	eq(String(RadioKit.entry_of(radio, id).answered), "coming", "answering applies the option")
	Kit.free_all(ctx)


func test_the_news_lists_the_new_kinds_with_their_names() -> void:
	var ctx := _ctx()
	var radio = ctx.sim.radio
	radio.log_news("forecast", "Big Night tomorrow: The Siege", "Be home by 17:20.")
	radio.log_news("night_road", "Dusk in 2 hours, and a Big Night with it: leave by 15:40")
	radio.raise_call("brute", "A plated brute at the east gate", "Coming up the road", [{"id": "watch", "label": "Keep the guns on it"}, {"id": "coming", "label": "I'll take it"}, {"id": "reinforce", "label": "Send two"}, {"id": "lure", "label": "Draw it to the north wall (3 scrap)"}], "watch", 45.0, {"seg": 3})
	radio.raise_call("breach", "The north wall is down", "The dead are in", [{"id": "hold", "label": "Hold the line"}, {"id": "close", "label": "Close it (needs you there)"}, {"id": "fall_back", "label": "Pull back to the school"}, {"id": "coming", "label": "I'm on my way"}], "hold", 20.0, {"seg": 2})
	radio.raise_call("night", "Big Night: the east wall will take it", "", [{"id": "hold", "label": "Understood"}, {"id": "arms", "label": "Call to arms now"}, {"id": "lure", "label": "Alarm on the north wall (3 scrap)"}], "hold", 120.0, {})
	ctx.hud.toggle_news()
	Kit.update(ctx)
	await Kit.settle()
	var all := _texts_of(ctx.hud.news_panel)
	for word in ["FORECAST", "ROAD", "BRUTE", "BREACH", "NIGHT"]:
		check(all.contains(word), "the news says %s: %s" % [word, all])
	var p = ctx.hud.news_panel
	eq(p.call_views.size(), 3, "the three calls wait for an answer at the top")
	eq(p.call_views[0].buttons.keys(), ["watch", "coming", "reinforce", "lure"], "the brute's four options")
	eq(p.call_views[2].buttons.keys(), ["hold", "arms", "lure"], "the night's three")
	check(p.call_views[2].buttons["arms"].text == "Call to arms now", "with their words")
	Kit.free_all(ctx)


func _texts_of(node: Node) -> String:
	var out: Array = []
	_collect(node, out)
	return " | ".join(out)


func _collect(node: Node, out: Array) -> void:
	if node is Control and not node.visible:
		return
	if node is Label and node.text != "":
		out.append(node.text)
	if node is Button and node.text != "":
		out.append(node.text)
	for c in node.get_children():
		_collect(c, out)


# ------------------------------------------------------------- the brunt's tag --

func test_the_tag_of_the_brunt_names_the_hour_when_there_is_one() -> void:
	eq(NightKit.brunt_tag(_siege()), "brunt, about 21:00", "the plan's words")
	eq(NightKit.brunt_tag(_siege({"first_at": -1.0})), "brunt", "no hour: none told")
	eq(NightKit.brunt_tag(Kit.forecast()), "", "an old forecast has none")
	eq(NightKit.brunt_tag({"given": false}), "", "nor a forecast that was not given")


# ------------------------------------------------------------------- the yard --

## What a test says of the nights module: whether it is on, who is rallied, which breaches are hot.
class FakeNights:
	extends "res://scripts/sim/nights.gd"
	var on := true
	var rallied_ids: Array = []
	var hot_ids: Array = []

	func active() -> bool:
		return on

	func rallied(p) -> bool:
		return on and rallied_ids.has(String(p.id))

	func breach_hot(seg) -> bool:
		return on and hot_ids.has(int(seg.id))


const SPOT := Vector2(41.5, 30.5)
const ZOOM := 40.0


## The real game with the avatar (a small start, Ruth), the quiet yard, the camera on `at` and the tactics and the nights module a test
## sets by hand.
func _game(at: Vector2 = SPOT, width: int = 1280, height: int = 800) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true}, width, height)
	var sim = main.sim
	sim.waves.enabled = false
	sim.zombies.clear()
	sim.jobs.clear()
	sim.tactics.chores = false
	var tactics := Kit.FakeTactics.new()
	tactics.setup(sim)
	sim.tactics = tactics
	var nights := FakeNights.new()
	nights.setup(sim)
	sim.nights = nights
	_look(main, at)
	return main


func _look(main: Node, at: Vector2, zoom: float = ZOOM) -> void:
	main.cam_center = at
	main.zoom_px = zoom
	main._clamp_camera()
	main._apply_camera()
	main.mouse_screen = main._vp() / 2.0
	main._sync_views()


func _draw_once(main: Node) -> void:
	main.overlay.forget_night()
	main.overlay.queue_redraw()
	await TutorialKit.settle()


func _walls(sim) -> Array:
	var out: Array = []
	for s in sim.segments:
		if s.kind != sim.DOOR_KIND and int(s.id) < 100:
			out.append(s)
	return out


func _stand(main: Node, p, at: Vector2) -> void:
	p.x = at.x
	p.y = at.y
	p.moving = false
	p.path = []
	p.order = null
	main._sync_views()


func test_the_brunt_wears_a_hatched_bracket_and_a_tag_from_the_forecast_to_dawn() -> void:
	var main := _game()
	var sim = main.sim
	var wall = _walls(sim)[0]
	_look(main, wall.center)
	sim.tactics.told = _siege({"sections": [wall.id]})
	sim.phase = "night"
	await _draw_once(main)
	check(main.overlay.drew_target_marks, "the section wears its marks")
	eq(main.overlay.drawn_target_marks, 1, "one section, one mark")
	eq(main.overlay.target_tags.size(), 1, "and one tag")
	eq(main.overlay.target_tags[0].text, "brunt, about 21:00", "its words")
	eq(main.overlay.target_tags[0].id, wall.id, "on that section")
	sim.phase = "day"
	await _draw_once(main)
	check(main.overlay.drew_target_marks, "from the forecast on, by day or at dusk")
	sim.phase = "dawn"
	await _draw_once(main)
	check(not main.overlay.drew_target_marks, "and not at dawn: the night is over")
	sim.phase = "night"
	sim.tactics.told = {"given": false}
	await _draw_once(main)
	check(not main.overlay.drew_target_marks, "nor when nobody told it")
	sim.tactics.told = Kit.forecast()
	await _draw_once(main)
	check(not main.overlay.drew_target_marks, "nor an old forecast, which names no section")
	await TutorialKit.leave(main)


func test_a_section_out_of_the_window_is_not_counted_and_every_target_is_marked() -> void:
	var main := _game()
	var sim = main.sim
	var walls := _walls(sim)
	var a = walls[0]
	var far = walls[0]
	for w in walls:
		if w.center.distance_to(a.center) > 40.0:
			far = w
	sim.tactics.told = _siege({"sections": [a.id, far.id]})
	sim.phase = "night"
	_look(main, a.center, 40.0)
	await _draw_once(main)
	eq(main.overlay.drawn_target_marks, 1, "the one in the window; the far one is not drawn")
	_look(main, a.center, 8.0)
	await _draw_once(main)
	check(main.overlay.drawn_target_marks >= 1, "zoomed far out")
	await TutorialKit.leave(main)


func test_the_hour_is_on_the_first_target_in_the_window_even_when_the_first_named_is_off_the_screen() -> void:
	var main := _game()
	var sim = main.sim
	var walls := _walls(sim)
	var a = walls[0]
	var far = walls[0]
	for w in walls:
		if w.center.distance_to(a.center) > 40.0:
			far = w
	sim.tactics.told = _siege({"sections": [far.id, a.id]})
	sim.phase = "night"
	_look(main, a.center, 40.0)
	await _draw_once(main)
	eq(main.overlay.target_tags.size(), 1, "one in the window")
	eq(main.overlay.target_tags[0].id, a.id, "it is the near one")
	eq(main.overlay.target_tags[0].text, "brunt, about 21:00", "and it says when")
	await TutorialKit.leave(main)


func test_an_ordinary_nights_brunt_is_marked_too_and_the_old_yard_has_none() -> void:
	var main := _game()
	var sim = main.sim
	var wall = _walls(sim)[0]
	_look(main, wall.center)
	sim.phase = "night"
	sim.tactics.told = _plain({"sections": [wall.id]})
	await _draw_once(main)
	check(main.overlay.drew_target_marks, "an ordinary night shows where the dead come")
	check(not main.overlay.target_lit, "but quieter: it does not need you")
	sim.tactics.told = _siege({"sections": [wall.id]})
	await _draw_once(main)
	check(main.overlay.target_lit, "a Big Night's brunt is lit")
	sim.player_id = ""
	await _draw_once(main)
	check(not main.overlay.drew_target_marks, "nothing without an avatar")
	await TutorialKit.leave(main)


func test_the_avatar_wears_a_faint_ring_of_the_rally_radius_and_brighter_while_someone_is_rallied() -> void:
	var main := _game()
	var sim = main.sim
	var me = sim.avatar.player()
	_stand(main, me, SPOT)
	await _draw_once(main)
	check(main.overlay.drew_rally_ring, "the ring")
	near(main.overlay.rally_ring_px, NightData.num("rally.radius", 9.0) * main.zoom_px, 0.5, "the rally radius in tiles, at this zoom")
	check(not main.overlay.rally_lit, "faint: nobody is rallied")
	eq(main.overlay.drawn_rallied, 0, "no chevrons")
	sim.nights.rallied_ids = ["dez", "ana"]
	_stand(main, sim.people[1], SPOT + Vector2(2, 0))
	_stand(main, sim.people[2], SPOT + Vector2(-2, 0))
	await _draw_once(main)
	check(main.overlay.rally_lit, "brighter while someone is rallied")
	eq(main.overlay.drawn_rallied, 2, "and each of them wears a chevron")
	sim.nights.on = false
	await _draw_once(main)
	check(not main.overlay.drew_rally_ring and main.overlay.drawn_rallied == 0, "no ring where the nights' rules do not apply")
	sim.nights.on = true
	me.downed = true
	await _draw_once(main)
	check(not main.overlay.drew_rally_ring, "no ring for an avatar who is down")
	me.downed = false
	sim.player_id = ""
	await _draw_once(main)
	check(not main.overlay.drew_rally_ring, "none in the old yard")
	await TutorialKit.leave(main)


func test_a_plated_brute_wears_its_plates_and_a_ring_at_the_weak_point_which_lights_when_the_aim_is_near() -> void:
	var main := _game()
	var sim = main.sim
	var wall = _walls(sim)[0]
	var brute = Helpers.plated_brute(sim, wall.id)
	check(brute != null, "a plated brute at the wall")
	if brute == null:
		await TutorialKit.leave(main)
		return
	var plain = Helpers.plated_brute(sim, wall.id)
	if plain != null:
		plain.plated = false
	_look(main, Vector2(brute.x, brute.y))
	var me = sim.avatar.player()
	_stand(main, me, Vector2(brute.x, brute.y) + Vector2(0.0, 5.0))
	var head := Vector2(brute.x, brute.y - NightData.num("plated.head", 0.62) * brute.size)
	me.aim = (head - sim.avatar.shoulder(me)).angle()
	await _draw_once(main)
	check(main.overlay.drew_weak_marks, "the weak point is marked")
	eq(main.overlay.drawn_plated, 1, "one plated brute is drawn plated (the plain one is not)")
	eq(main.overlay.weak_marks.size(), 1, "one ring")
	var ring: Dictionary = main.overlay.weak_marks[0]
	check(ring.near and ring.on, "the aim is on the head: the ring is lit")
	check(ring.r >= 6.0, "and is big enough to see: %.1f px" % ring.r)
	var want: Vector2 = main._tile_to_screen(head)
	check(ring.at.distance_to(want) < 4.0, "at the head's tile")
	me.aim += 1.2
	await _draw_once(main)
	var away: Dictionary = main.overlay.weak_marks[0]
	check(not away.near and not away.on, "aimed elsewhere: the ring is quiet")
	check(main.overlay.drew_weak_marks, "but still there")
	brute.state = "dying"
	await _draw_once(main)
	check(not main.overlay.drew_weak_marks and main.overlay.drawn_plated == 0, "a dead one wears nothing")
	await TutorialKit.leave(main)


func test_a_plated_brutes_panel_says_it_is_armoured_and_a_plain_ones_does_not() -> void:
	var ctx := _ctx()
	var sim = ctx.sim
	var plain = sim.spawn(40.0, 40.0, "wander", "brute")
	var plated = sim.spawn(41.0, 40.0, "wander", "brute")
	plated.plated = true
	ctx.hud.select({"kind": "zombie", "ref": plated})
	Kit.update(ctx)
	check(Kit.texts(ctx.hud.inspect).has("Plated brute"), "the plated one is named so: %s" % str(Kit.texts(ctx.hud.inspect)))
	check(Kit.texts(ctx.hud.inspect).has(Hud.PLATED_NAMES[1]), "and says what that means")
	ctx.hud.select({"kind": "zombie", "ref": plain})
	Kit.update(ctx)
	check(Kit.texts(ctx.hud.inspect).has("Brute") and not Kit.texts(ctx.hud.inspect).has("Plated brute"), "a plain brute is a brute")
	Kit.free_all(ctx)


func test_a_plated_brute_in_the_old_game_looks_as_any_brute() -> void:
	var main := _game()
	var sim = main.sim
	var wall = _walls(sim)[0]
	var plain = sim.spawn(wall.slots[0].x, wall.slots[0].y, "attack", "brute")
	check(not plain.plated, "an ordinary brute is not plated")
	_look(main, Vector2(plain.x, plain.y))
	await _draw_once(main)
	check(not main.overlay.drew_weak_marks and main.overlay.drawn_plated == 0, "nothing drawn on it")
	await TutorialKit.leave(main)


func test_a_hot_breach_pulses_and_says_nobody_will_mend_it_under_fire() -> void:
	var main := _game()
	var sim = main.sim
	var wall = _walls(sim)[0]
	wall.hp = 0.0
	sim._segment_state(wall)
	eq(wall.state, 3, "the section is down")
	_look(main, wall.center)
	await _draw_once(main)
	check(not main.overlay.drew_hot_breach, "a cold breach is not marked")
	sim.nights.hot_ids = [wall.id]
	await _draw_once(main)
	check(main.overlay.drew_hot_breach, "a hot one is")
	eq(main.overlay.drawn_hot_breach, 1, "once")
	eq(main.overlay.hot_tags[0].text, "no mending under fire", "with its words")
	sim.nights.on = false
	await _draw_once(main)
	check(not main.overlay.drew_hot_breach, "not where the rules do not apply")
	await TutorialKit.leave(main)


func test_the_mend_ring_follows_the_session_of_the_avatars_hands() -> void:
	# (the session is the nights' module's: the real one, a worn wall and the avatar at its mending place)
	var g := Helpers.avatar_game(1, 5)
	var sim = g.sim
	Helpers.no_work(sim)
	sim.waves.enabled = false
	sim.zombies.clear()
	Helpers.at(sim, 3, 22.0)
	for p in sim.people:
		p.reloading = 1.0e6
	var seg = null
	for s in sim.segments:
		if s.id == 0:
			seg = s
	seg.hp = seg.max_hp * 0.3
	sim._segment_state(seg)
	var me = sim.avatar.player()
	var spot: Vector2 = sim.repair_spot(seg)
	me.x = spot.x
	me.y = spot.y
	me.path = []
	sim.stock.scrap = 40.0
	eq(OverlayNode.mend_state(sim), {"on": false, "progress": 0.0, "seg": -1}, "no hands at work: no ring")
	check(bool(sim.nights.mend_wall(0).ok), "the hands begin")
	var st: Dictionary = OverlayNode.mend_state(sim)
	check(st.on, "mending a wall: the ring")
	near(st.progress, 0.0, 0.001, "at the start")
	eq(st.seg, 0, "at that section")
	var total: float = NightData.num("mend.seconds", 10.0)
	for i in int(total * 0.25 * 30.0):
		sim.update(1.0 / 30.0)
	st = OverlayNode.mend_state(sim)
	check(st.on, "still at it")
	near(st.progress, 0.25, 0.05, "a quarter done: %f" % st.progress)
	near(st.progress, 1.0 - sim.nights.work_left / total, 0.001, "and the ring reads the module's own seconds")
	# the bench's session (round 18's Interact keeps it) is not this ring
	sim.nights.stop_mend("stopped")
	sim.interact.working = "bench"
	sim.interact.work_left = 3.0
	check(not OverlayNode.mend_state(sim).on, "the bench's ring is not this one")
	sim.interact.working = ""
	check(not OverlayNode.mend_state(sim).on, "and not working: none")
	# a sim with no such module
	eq(OverlayNode.mend_state(FakeSim.new()), {"on": false, "progress": 0.0, "seg": -1}, "no nights module: no ring")
	g.world.queue_free()


const OverlayNode := preload("res://scripts/render/overlay_node.gd")


class FakeSim:
	extends RefCounted
	var nights = null


func test_the_fields_view_gives_the_spawn_arrows_the_hour_of_the_first_of_the_dead() -> void:
	var main := _game()
	var sim = main.sim
	var wall = _walls(sim)[0]
	sim.tactics.told = _siege({"sections": [wall.id]})
	sim.phase = "night"
	var plan: Dictionary = main.overlay.fields_plan(sim)
	eq(plan.brunt, "first about 21:00", "the arrow says when the first comes")
	sim.player_id = ""
	eq(main.overlay.fields_plan(sim).brunt, "", "and says nothing more in the old yard")
	await TutorialKit.leave(main)


# ------------------------------------------------------------------- the place --

## What the colony's night module says of the road, as a test sets it (the real one is tests/test_night_road.gd's).
class FakeNight:
	extends RefCounted
	var status := {}
	var leave_requested := false

	func road_status() -> Dictionary:
		return status


## The real game with the avatar and a trip played, in a window of this size; the scene has a stand-in for the night module and the colony's
## clock is day 3, 13:30 (dusk is at 19:00: 5:30 away). `mode` is where the trip is: "place" (the live drive of round 21, which is what the game
## opens in avatar mode: a DriveScene put at its place: `scene.leg == "place"`), "road" (the same scene on its way there: `scene.leg ==
## "there"`) or "classic" (the overlay's road, `--fastroad` and the tests that keep it: a RaidScene played to its place).
func _trip(width: int = 1280, height: int = 800, mode: String = "place") -> Dictionary:
	PlaceFlow.live_enabled = mode != "classic"
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true}, width, height)
	main.raid_stub = true
	var sim = main.sim
	sim.waves.enabled = false
	var scene = main.open_raid([sim.people[1], sim.people[2]], sim.town.place("houses"), "", 1.0, Callable())
	check(scene != null, "the trip opens")
	scene.night_override = FakeNight.new()
	var guard := 0
	if mode == "classic":
		while scene.phase == "road_there" and guard < 5000:
			scene.tick(1.0 / 60.0)
			guard += 1
	elif mode == "place":
		eq(scene.leg, "there", "the drive begins on the road there")
		scene.stage("exit")    # (the squad is at the end of the road)
		while scene.leg == "there" and guard < 600:
			scene.tick(1.0 / 30.0)
			guard += 1
		scene.tick(1.0 / 30.0)    # (the card's frame, then the stage is built)
		eq(scene.leg, "place", "the place is next")
	Helpers.at(sim, 3, 13.5)
	return {"main": main, "sim": sim, "scene": scene, "night": scene.night_override, "mode": mode}


## The game given back, the drive on again for the tests that follow.
func _done(ctx: Dictionary) -> void:
	PlaceFlow.live_enabled = true
	await TutorialKit.leave(ctx.main)


## The road's state at `leave_in` game minutes from now with the road home taking 80.
func _road(ctx: Dictionary, state: String, leave_in: float, big: bool = true) -> Dictionary:
	var now: float = ctx.sim.clock_min
	var dusk := now + 330.0
	return {"on": true, "dusk": dusk, "road_min": 80.0, "leave_by": now + leave_in, "left_min": leave_in, "state": state, "big": big, "text": ""}


func _refresh(ctx: Dictionary) -> void:
	ctx.scene.hud_layer.refresh()


func test_the_place_says_how_long_to_dusk_the_road_home_and_when_to_leave() -> void:
	var ctx := _trip()
	var h = ctx.scene.hud_layer
	_refresh(ctx)
	check(not h.leave_label.visible, "no night module's word: no line")
	ctx.night.status = _road(ctx, "free", 190.0)
	_refresh(ctx)
	check(h.leave_label.visible, "the trip is out: the line")
	eq(h.leave_label.text, "Dusk in 5:30 · road home 1:20 · leave by 16:40", "its words")
	eq(h.leave_label.get_theme_color("font_color"), Hud.INK2, "calm: the dim chalk")
	check(h.leave_label.get_theme_font_size("font_size") >= 12, "12 px or more")
	check(h.base_panel.is_ancestor_of(h.leave_label), "in the base's clock")
	ctx.night.status = _road(ctx, "soon", 50.0)
	_refresh(ctx)
	eq(h.leave_label.text, "Dusk in 5:30 · road home 1:20 · leave by 14:20", "an hour before: still the hour")
	eq(h.leave_label.get_theme_color("font_color"), Hud.WARN, "amber")
	ctx.night.status = _road(ctx, "now", -10.0)
	_refresh(ctx)
	eq(h.leave_label.text, "Dusk in 5:30 · road home 1:20 · leave now", "the time to go")
	eq(h.leave_label.get_theme_color("font_color"), Hud.DANGER_TEXT, "red")
	ctx.night.status = _road(ctx, "now", -10.0, false)
	_refresh(ctx)
	eq(h.leave_label.get_theme_color("font_color"), Hud.WARN, "but only amber when the night is an ordinary one")
	ctx.night.status = _road(ctx, "late", -60.0)
	_refresh(ctx)
	eq(h.leave_label.text, "You will be out tonight", "too late: they cannot make it")
	eq(h.leave_label.get_theme_color("font_color"), Hud.WARN, "amber: it costs nothing but the nights' rules without you")
	ctx.night.status = {}
	_refresh(ctx)
	check(not h.leave_label.visible, "and the line goes when the module has none")
	ctx.night.status = {"on": false, "state": "free"}
	_refresh(ctx)
	check(not h.leave_label.visible, "or says the trip is not out")
	await _done(ctx)


func test_without_the_night_module_the_place_is_as_it_was() -> void:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true})
	main.raid_stub = true
	main.sim.waves.enabled = false
	var scene = main.open_raid([main.sim.people[1], main.sim.people[2]], main.sim.town.place("houses"), "", 1.0, Callable())
	var guard := 0
	while scene.phase == "road_there" and guard < 5000:
		scene.tick(1.0 / 60.0)
		guard += 1
	scene.night_override = null
	var radio = scene.colony_radio()
	if radio.get("night") == null:
		eq(scene.night_road(), {}, "no night module: no road")
	scene.hud_layer.refresh()
	check(not scene.leave_requested() or radio.get("night") != null, "and no request")
	await TutorialKit.leave(main)


func test_the_line_fits_the_window_and_leaves_the_rest_of_the_place_alone_at_every_size() -> void:
	for size in SIZES:
		var ctx := _trip(size[0], size[1])
		var h = ctx.scene.hud_layer
		ctx.night.status = _road(ctx, "soon", 50.0)
		_refresh(ctx)
		await TutorialKit.settle()
		_refresh(ctx)
		await TutorialKit.settle()
		var where := "%d x %d" % [size[0], size[1]]
		var win := Rect2(Vector2.ZERO, Vector2(size[0], size[1]))
		var base: Rect2 = Kit.rect(h.base_panel)
		var line: Rect2 = Kit.rect(h.leave_label)
		check(line.size != Vector2.ZERO and base.encloses(line), "%s: the line is inside the base's board (%s in %s)" % [where, str(line), str(base)])
		check(win.encloses(base), "%s: the board is in the window" % where)
		check(h.leave_label.get_theme_font_size("font_size") >= 12, "%s: 12 px or more" % where)
		var named := {"base": base, "radio": Kit.rect(h.radio_panel), "weapon": Kit.rect(h.weapon_panel), "place": Kit.rect(h.place_panel), "loot": Kit.rect(h.loot_panel), "cards": Kit.rect(h.cards_grid)}
		if h.call_card.visible:
			named["call"] = Kit.rect(h.call_card)
		eq(Kit.overlaps(named), [], "%s: nothing overlaps the board" % where)
		await _done(ctx)


## The place's scene is asked to head home and does it once: the squad is asked to go back, the hint says where and how far the road is
## (the same in the overlay's road and in the live drive's place: `mode`).
func _check_asked_to_head_home(mode: String) -> Dictionary:
	var ctx := _trip(1280, 800, mode)
	var scene = ctx.scene
	var lead = scene.leader()
	ctx.night.status = _road(ctx, "now", -5.0)
	var before: String = scene.hint_line()
	check(not before.begins_with("Head for the exit"), "%s: no request: the hint is the place's own: %s" % [mode, before])
	ctx.night.leave_requested = true
	scene.tick(1.0 / 60.0)
	check(scene._leave_asked, "%s: the squad is asked" % mode)
	var asked := 0
	for p in scene.run.squad:
		if p != lead and not p.dead:
			asked += 1
	check(asked > 0, "%s: there is a squad to ask" % mode)
	eq(scene.hint_line(), "Head for the exit: the road home takes 1 h 20", "%s: the hint says where, and how long the road is" % mode)
	# they walk to the exit (the verb is the radio's: willingness and delay as ever)
	for i in 300:
		scene.tick(1.0 / 30.0)
	var heading := 0
	for p in scene.run.squad:
		if p != lead and not p.dead and String(p.stance) == "back":
			heading += 1
	check(heading > 0, "%s: someone of the squad took the stance: back (%d)" % [mode, heading])
	var count: int = scene.run.log.size()
	scene.tick(1.0 / 60.0)
	scene._watch_leave_request()
	eq(scene.run.log.size(), count, "%s: and they are not asked again" % mode)
	return ctx


func test_asked_to_head_home_the_squad_goes_back_once_and_the_hint_says_where() -> void:
	for mode in ["classic", "place"]:
		var ctx = _check_asked_to_head_home(mode)
		await _done(ctx)


## The party walks out of the place: the leader away from the exit for a moment, then everyone in it, and a few frames for the scene to see it.
func _walk_out(scene) -> void:
	var spot: Vector2 = scene.site.exit.get_center()
	var lead = scene.leader()
	lead.x = spot.x + 7.0
	lead.path = []
	for i in 6:
		scene.tick(1.0 / 30.0)
	for p in scene.run.squad:
		if not p.dead and not p.downed:
			p.x = spot.x + randf_range(-0.8, 0.8)
			p.y = spot.y + randf_range(-0.6, 0.6)
			p.path = []
	for i in 15:
		scene.tick(1.0 / 30.0)


## The request is put down once the place is over (a RaidScene: `ended`, the report; a DriveScene: the way home begins).
func _check_put_down(mode: String) -> Dictionary:
	var ctx := _trip(1280, 800, mode)
	var scene = ctx.scene
	ctx.night.leave_requested = true
	scene.tick(1.0 / 60.0)
	check(scene.leave_requested(), "%s: asked, and the trip is out" % mode)
	_walk_out(scene)
	if mode == "place":
		eq(scene.leg, "home", "%s: the place is over and the way home has begun" % mode)
	else:
		check(scene.ended, "%s: the place is over" % mode)
	check(not ctx.night.leave_requested, "%s: the request is put down once the party is finished" % mode)
	check(not scene.leave_requested(), "%s: and is not asked of again" % mode)
	return ctx


func test_the_request_is_put_down_when_the_place_is_over() -> void:
	for mode in ["classic", "place"]:
		var ctx := _check_put_down(mode)
		await _done(ctx)


func test_a_down_friend_is_the_hint_before_the_way_home() -> void:
	for mode in ["classic", "place"]:
		var ctx := _trip(1280, 800, mode)
		var scene = ctx.scene
		var lead = scene.leader()
		ctx.night.leave_requested = true
		ctx.night.status = _road(ctx, "now", -5.0)
		for p in scene.run.squad:
			if p != lead:
				p.downed = true
				break
		check(scene.hint_line().contains("is down"), "%s: who is down comes first: %s" % [mode, scene.hint_line()])
		await _done(ctx)


func test_on_the_road_there_the_line_shows_and_a_request_to_head_home_waits_for_the_place() -> void:
	var ctx := _trip(1280, 800, "road")
	var scene = ctx.scene
	var h = scene.hud_layer
	eq(scene.leg, "there", "the squad is still on the road there")
	ctx.night.status = _road(ctx, "soon", 50.0)
	_refresh(ctx)
	check(h.leave_label.visible, "the line is up on the road too: when to turn back is worth knowing")
	eq(h.leave_label.text, "Dusk in 5:30 · road home 1:20 · leave by 14:20", "its words")
	var driving: String = scene.hint_line()
	check(not driving.begins_with("Asked") and not driving.begins_with("Head for"), "no request: the road's own hint: %s" % driving)
	ctx.night.status = _road(ctx, "now", -5.0)
	ctx.night.leave_requested = true
	scene.tick(1.0 / 30.0)
	check(scene.leave_requested(), "the request stands")
	check(not scene._leave_asked, "nobody is asked on the road: the squad is in the car, and the car cannot turn round")
	for p in scene.run.squad:
		check(String(p.stance) != "back", "%s keeps to the road" % p.first)
	eq(scene.hint_line(), "Asked to head home: the place first, then straight back. The road home takes 1 h 20", "the hint says what will happen")
	# the road is done: at the place the squad is asked, once, and the hint is the place's
	scene.stage("exit")
	var guard := 0
	while scene.leg == "there" and guard < 600:
		scene.tick(1.0 / 30.0)
		guard += 1
	scene.tick(1.0 / 30.0)
	eq(scene.leg, "place", "the place")
	scene.tick(1.0 / 30.0)
	check(scene._leave_asked, "the squad is asked at the place")
	eq(scene.hint_line(), "Head for the exit: the road home takes 1 h 20", "and the hint is the exit's")
	await _done(ctx)


func test_on_the_road_home_the_line_says_when_they_are_back_and_nothing_is_asked() -> void:
	var ctx := _trip(1280, 800, "place")
	var scene = ctx.scene
	var h = scene.hud_layer
	ctx.night.leave_requested = true
	scene.tick(1.0 / 30.0)
	_walk_out(scene)
	eq(scene.leg, "home", "the way home has begun")
	check(not ctx.night.leave_requested, "the request was put down with the place")
	ctx.night.status = {"on": true, "in_place": false, "dusk": ctx.sim.clock_min + 330.0, "road_min": 80.0, "leave_by": ctx.sim.clock_min - 20.0, "left_min": 25.0,
		"state": "free", "big": true, "text": "On the road home: back by 14:50"}
	_refresh(ctx)
	check(h.leave_label.visible, "the line is up")
	eq(h.leave_label.text, "On the road home: back by 14:50", "it says when they are back, not an hour to leave by")
	eq(h.leave_label.get_theme_color("font_color"), Hud.INK2, "calm")
	ctx.night.leave_requested = true
	scene.tick(1.0 / 30.0)
	check(not scene.leave_requested() and not ctx.night.leave_requested, "a stray request on the road home is put down: there is nothing to ask")
	check(not scene.hint_line().begins_with("Asked") and not scene.hint_line().begins_with("Head for"), "and the hint is the road's own: %s" % scene.hint_line())
	ctx.night.status = {"on": true, "in_place": false, "state": "late", "big": true, "text": "You will be out tonight"}
	_refresh(ctx)
	eq(h.leave_label.text, "You will be out tonight", "too late: as in the place")
	await _done(ctx)


# ------------------------------------------------------------- the board's note --

class WarnScav:
	extends RefCounted
	var out := {}
	var asked: Array = []

	func night_warning(place_id: String, vehicle_id: String = "", site_hours: float = 1.0) -> Dictionary:
		asked.append([place_id, vehicle_id, site_hours])
		return out


class WarnSim:
	extends RefCounted
	var player_id := "ruth"
	var scavenge = null


func test_the_boards_note_is_what_the_scavenging_module_says_of_tonight() -> void:
	var sim := WarnSim.new()
	var scav := WarnScav.new()
	sim.scavenge = scav
	eq(NightKit.warning_line(sim, "houses"), {}, "it says nothing: no note")
	scav.out = {"big": true, "makes_it": true, "text": "Big Night tonight: leave the place by 15:40 (the road home takes 1 h 20), or stay out and the base holds alone"}
	var line := NightKit.warning_line(sim, "houses", "pickup1", 1.5)
	eq(line.text, scav.out.text, "its own words")
	eq(line.tone, "calm", "calm while the party makes it")
	check(line.big, "and says the night is Big")
	eq(scav.asked.back(), ["houses", "pickup1", 1.5], "asked for this place, this vehicle and this time at the place")
	scav.out = {"big": true, "makes_it": false, "text": "Big Night tonight: the party cannot be home by dusk"}
	eq(NightKit.warning_line(sim, "houses").tone, "warn", "amber when it will not make it")
	scav.out = {"big": false, "makes_it": true, "text": "Back by 17:30"}
	eq(NightKit.warning_line(sim, "houses").tone, "calm", "an ordinary night: no alarm")
	sim.player_id = ""
	eq(NightKit.warning_line(sim, "houses"), {}, "no avatar, no note")
	sim.player_id = "ruth"
	sim.scavenge = RefCounted.new()
	eq(NightKit.warning_line(sim, "houses"), {}, "a module that has no such question: no note")


func test_the_town_board_shows_the_note_under_the_trip_when_the_module_has_one() -> void:
	var main = TutorialKit.start({"difficulty": 1, "seed": 7, "crew": 5, "avatar": true})
	var sim = main.sim
	sim.waves.enabled = false
	Helpers.at(sim, 3, 9.0)
	main.hud.update_hud(sim, 1, true, 0)    # (the HUD has to have seen the game first)
	main.hud.open_scavenge(null)
	await TutorialKit.settle()
	var board = main.hud.scavenge_dialog
	check(board != null and main.hud.town_board_open(), "the board is open")
	if board == null:
		await TutorialKit.leave(main)
		return
	board.select_place("houses")
	await TutorialKit.settle()
	check(board.facts.has("night"), "the card has a row for tonight")
	var row: Dictionary = board.facts.night
	if sim.scavenge.has_method("night_warning"):
		var want := String(NightKit.warning_line(sim, "houses", "", float(sim.town.SEARCH_H)).get("text", ""))
		eq(row.label.text, want, "the row says what the module says")
		eq(row.label.visible, want != "", "and is there only when it says something")
	else:
		check(not row.label.visible, "no module question: the row is not there")
	check(row.label.get_theme_font_size("font_size") >= 12, "12 px or more")
	await TutorialKit.leave(main)


# ------------------------------------------------------------ the screenshot flags --

func _staged(width: int = 1280, height: int = 800) -> Node:
	var main = TutorialKit.start({"difficulty": 1, "seed": 3, "crew": 5, "avatar": true}, width, height)
	main.sim.waves.enabled = false
	main.sim.zombies.clear()
	return main


func test_the_night_flag_stages_each_kind_of_night_at_half_past_six_with_the_forecast_given() -> void:
	var days := {"ordinary": 4, "siege": 10, "rush": 20, "last": 30}
	var main := _staged()
	var sim = main.sim
	for kind in days:
		check(main.stage_night(kind), "%s can be staged" % kind)
		eq(sim.day, days[kind], "%s: its day" % kind)
		near(sim.hour, 18.5, 0.01, "%s: the clock is at 18:30" % kind)
		eq(sim.phase, "day", "%s: it is still day: the bell has not rung" % kind)
		check(not sim.bell_rung, "%s: and the bell is not rung" % kind)
		check(bool(sim.tactics.forecast().get("given", false)), "%s: the lookout's forecast is given" % kind)
		var me = sim.avatar.player()
		check(me != null and me.x > 0.0, "%s: the avatar stands somewhere" % kind)
		check(main._stage_focus != Vector2.INF, "%s: the camera has a place to look at" % kind)
	check(not main.stage_night("dusk"), "a kind that is none of them is refused")
	sim.player_id = ""
	check(not main.stage_night("siege"), "and there is no night to stage without an avatar")
	await TutorialKit.leave(main)


func test_the_night_flag_puts_the_avatar_inside_the_wall_it_covers() -> void:
	var main := _staged()
	var sim = main.sim
	main.stage_night("siege")
	var seg = main._brunt_section()
	check(seg != null, "there is a wall for the brunt")
	var me = sim.avatar.player()
	var spot: Vector2 = main._stand_spot(seg)
	check(Vector2(me.x, me.y).distance_to(spot) < 0.01, "the avatar stands where the wall is covered from")
	check(Vector2(me.x, me.y).distance_to(seg.center) < 16.0, "and not across the map from it")
	await TutorialKit.leave(main)


func test_the_forecast_flag_stages_noon_of_the_day_before_with_the_desk_manned_and_a_notice_in_the_log() -> void:
	var main := _staged()
	var sim = main.sim
	check(main.stage_forecast_ahead(), "it is staged")
	eq(sim.day, 9, "day 9")
	near(sim.hour, 12.05, 0.01, "just after noon")
	check(sim.jobs.operator("radio") != null, "the Radio desk is manned")
	check(main.ensure_notice(), "the notice is there, the radio's own or a staged one")
	var notice := NightKit.notice(sim)
	check(not notice.is_empty(), "in the log")
	check(String(notice.text).begins_with("Big Night tomorrow"), "its words: %s" % notice.text)
	var count: int = sim.radio.news.size()
	check(main.ensure_notice(), "asked again")
	eq(sim.radio.news.size(), count, "it is not made twice")
	main.hud.update_hud(sim, 1, true, 0)
	check(main.hud.night_badge.visible and main.hud.badge_state() == "tomorrow", "and the clock wears the badge")
	sim.player_id = ""
	check(not main.stage_forecast_ahead(), "no avatar, nothing to stage")
	await TutorialKit.leave(main)


func test_the_plated_flag_puts_a_plated_brute_at_the_wall_and_the_pointer_on_its_head() -> void:
	var main := _staged()
	var sim = main.sim
	main.stage_night("siege")
	check(main.stage_plated(), "it is staged")
	var plated: Array = []
	for z in sim.zombies:
		if z.plated:
			plated.append(z)
	eq(plated.size(), 1, "one plated brute")
	var z = plated[0]
	eq(z.kind, "brute", "a brute")
	eq(z.state, "attack", "clawing at the wall")
	var head := Vector2(z.x, z.y - NightData.num("plated.head", 0.62) * float(z.size))
	check(main.shot_aim.distance_to(head) < 0.01, "the pointer is on its head")
	var me = sim.avatar.player()
	check(absf(wrapf(me.aim - (head - sim.avatar.shoulder(me)).angle(), -PI, PI)) < 0.01, "and the avatar's aim too")
	await TutorialKit.leave(main)


func test_the_breach_flag_in_avatar_mode_is_a_hot_breach_with_the_dead_in_it() -> void:
	var main := _staged()
	var sim = main.sim
	var seg = sim.segments[0]
	sim._damage_segment(seg, seg.hp + 1.0)
	main.stage_hot_breach(seg)
	eq(seg.state, 3, "the section is down")
	var inside := 0
	for z in sim.zombies:
		if z.state == "breach" and Vector2(z.x, z.y).distance_to(seg.center) < 3.0:
			inside += 1
	eq(inside, 3, "three of the dead are in it")
	check(main._stage_focus != Vector2.INF, "and the camera is on it")
	await TutorialKit.leave(main)
