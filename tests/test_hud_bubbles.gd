extends "res://tests/case.gd"
## Round 4, speech bubbles in the world (scripts/render/overlay_node.gd): what a person says (a `bark`
## event from the rules, forwarded by main.gd) shows for about three seconds in a small bubble above
## their head: a frame of the noticeboard's paper with a tail (the `bubble` frame, flat without it), in
## screen space (not scaled with the world), kept inside the view, faded in and out (not with reduced
## motion), two at most, none while a modal is open or for someone who is off screen.

const Kit := preload("res://tests/hud_kit.gd")
const Fakes := preload("res://tests/menu_fakes.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")
const Frames := preload("res://scripts/ui/frames.gd")
const Prefs := preload("res://scripts/prefs.gd")
const OverlayNode := preload("res://scripts/render/overlay_node.gd")

const ZOOM := 32.0


## What the overlay reads of main.gd.
class FakeMain:
	extends Node
	var sim
	var zoom_px := ZOOM
	var selection = null
	var hover = null
	var order_mark = null
	var clock := 0.0
	var fields := false
	var hud = null
	var menu_open := false

	func view_pos(e) -> Vector2:
		return Vector2(e.x, e.y)


## The HUD's part in it: whether a modal is up.
class FakeHud:
	extends RefCounted
	var modal := false

	func modal_open() -> bool:
		return modal


## An overlay over `ctx`'s game with the camera's scale at ZOOM pixels a tile and the origin in the
## window's corner, so a person at (x, y) tiles is at (x, y) * ZOOM on the screen.
func _overlay(ctx: Dictionary) -> Dictionary:
	var main := FakeMain.new()
	main.sim = ctx.sim
	var layer := CanvasLayer.new()
	var overlay := OverlayNode.new()
	overlay.main = main
	layer.add_child(overlay)
	main.add_child(layer)
	Engine.get_main_loop().root.add_child(main)
	overlay.get_viewport().canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * ZOOM / OverlayNode.TILE)
	return {"main": main, "overlay": overlay}


func _free_overlay(o: Dictionary) -> void:
	o.overlay.get_viewport().canvas_transform = Transform2D.IDENTITY
	o.main.free()


func _vp(o: Dictionary) -> Vector2:
	return o.overlay.get_viewport_rect().size


## Puts a person where it is easy to reason about: `x`, `y` tiles from the origin, standing.
func _stand(ctx: Dictionary, id: String, x: float, y: float):
	var p = Kit.person(ctx, id)
	p.x = x
	p.y = y
	return p


func _bark(who: String, text: String = "Hold the line.") -> Dictionary:
	return {"type": "bark", "who": who, "text": text, "context": "bell"}


## A game, an overlay on it and Ana standing in the middle of the window.
func _setup() -> Dictionary:
	var ctx := Kit.build()
	var o := _overlay(ctx)
	var vp := _vp(o)
	var ana = _stand(ctx, "ana", vp.x / ZOOM * 0.5, vp.y / ZOOM * 0.6)
	return {"ctx": ctx, "o": o, "vp": vp, "ana": ana}


func _done(s: Dictionary) -> void:
	_free_overlay(s.o)
	Kit.free_all(s.ctx)


# ------------------------------------------------------------- the bubble --

func test_a_bark_makes_a_bubble_above_the_speaker() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	overlay.add_bark(_bark("ana", "Hold the line."))
	eq(overlay.bubbles.size(), 1, "one bubble")
	s.o.main.clock = 0.5
	var plan: Array = overlay.bubble_plan(s.vp)
	eq(plan.size(), 1, "one to draw")
	var b: Dictionary = plan[0]
	eq(b.who, "ana", "whose it is")
	eq(b.text, "Hold the line.", "what she says")
	var head := Vector2(s.ana.x, s.ana.y - 0.95) * ZOOM
	check(b.rect.end.y <= head.y, "the body is above her head (%s, head at %s)" % [str(b.rect), str(head)])
	check(b.rect.end.y >= head.y - 40.0, "and not far above it")
	near(b.tip.x, head.x, 1.5, "the tail's tip is over her")
	check(b.tip.y <= head.y and b.tip.y >= head.y - 14.0, "just over her head: %.1f, head at %.1f" % [b.tip.y, head.y])
	check(b.rect.has_point(Vector2(head.x, b.rect.get_center().y)), "she is under the bubble")
	_done(s)


func test_it_is_in_screen_space_not_scaled_with_the_world() -> void:
	var s := _setup()
	s.o.overlay.add_bark(_bark("ana", "Hold the line."))
	s.o.main.clock = 0.5
	var near_plan: Dictionary = s.o.overlay.bubble_plan(s.vp)[0]
	# zoom in: the people move apart, the bubble does not grow
	s.o.main.zoom_px = ZOOM * 2.0
	s.o.overlay.get_viewport().canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * ZOOM * 2.0 / OverlayNode.TILE)
	s.ana.x = s.vp.x / ZOOM * 0.25
	s.ana.y = s.vp.y / ZOOM * 0.3
	var far_plan: Dictionary = s.o.overlay.bubble_plan(s.vp)[0]
	near(far_plan.rect.size.x, near_plan.rect.size.x, 0.01, "the same width at twice the zoom")
	near(far_plan.rect.size.y, near_plan.rect.size.y, 0.01, "and the same height")
	_done(s)


func test_the_text_is_at_least_twelve_pixels() -> void:
	check(OverlayNode.BUBBLE_PX >= Fonts.MIN_PX, "%d px" % OverlayNode.BUBBLE_PX)
	var s := _setup()
	s.o.overlay.add_bark(_bark("ana"))
	s.o.main.clock = 0.5
	var b: Dictionary = s.o.overlay.bubble_plan(s.vp)[0]
	check(int(b.size) >= Fonts.MIN_PX, "the size the plan draws it at: %d" % int(b.size))
	_done(s)


func test_it_wears_the_bubble_frame_and_the_flat_look_without_it() -> void:
	var s := _setup()
	s.o.overlay.add_bark(_bark("ana"))
	s.o.main.clock = 0.5
	var b: Dictionary = s.o.overlay.bubble_plan(s.vp)[0]
	eq(b.framed, Hud.has_frame("bubble"), "the frame, when the theme has it")
	check(Hud.has_frame("bubble"), "and the theme has it (frames.json and the picture)")
	var tail: Array = Frames.info("bubble").get("tail", [])
	eq(tail.size(), 2, "frames.json says where the tail's tip is")
	check(float(tail[0]) > 0.0 and float(tail[1]) > 0.0, "%s" % str(tail))
	check(OverlayNode.BUBBLE_FRAME_KIND == "bubble", "its name")
	Hud.use_frames = false
	var flat: Dictionary = s.o.overlay.bubble_plan(s.vp)[0]
	eq(flat.framed, false, "with the frames off it is flat")
	await Kit.settle()
	s.o.overlay.queue_redraw()
	await Kit.settle()
	Hud.use_frames = true
	_done(s)


func test_the_frame_is_in_the_theme_and_in_the_huds_list() -> void:
	check("bubble" in Hud.FRAME_KINDS, "the HUD lists the frame it asks for")
	var e: Dictionary = Frames.info("bubble")
	check(not e.is_empty(), "frames.json has an entry")
	eq(String(e.get("file", "")), "res://assets/ui/theme/bubble.png", "its picture")
	check(FileAccess.file_exists(String(e.get("file", ""))), "which is there")
	var img := Image.load_from_file(ProjectSettings.globalize_path(String(e.file)))
	check(img != null and not img.is_empty() and img.get_width() % 2 == 0 and img.get_height() % 2 == 0, "with even sides")
	# the tail is inside the left margin of the nine-patch, so stretching the middle does not bend it
	var m: Array = e.margin
	var tail: Array = e.tail
	check(float(tail[0]) * 2.0 + 6.0 <= float(m[0]), "the tail is in the left margin: tip at %.1f (art px %.0f), margin %d" % [float(tail[0]), float(tail[0]) * 2.0, int(m[0])])
	# the tail is in the picture: pixels below the foot of the body are opaque near the tip
	var expand: Array = e.expand
	var foot_y := img.get_height() - int(float(expand[3]) * 2.0)
	var found := false
	for y in range(foot_y, img.get_height()):
		for x in range(0, int(m[0])):
			if img.get_pixel(x, y).a > 0.9:
				found = true
	check(found, "there is a tail below the body")


func test_a_long_line_wraps_in_a_bubble_of_limited_width() -> void:
	var s := _setup()
	var text := "I told them we would hold this wall until the morning bell, and I meant every word of it."
	s.o.overlay.add_bark(_bark("ana", text))
	s.o.main.clock = 0.5
	var b: Dictionary = s.o.overlay.bubble_plan(s.vp)[0]
	check(b.lines >= 2, "it takes %d lines" % int(b.lines))
	check(b.rect.size.x <= OverlayNode.BUBBLE_MAX_W + 30.0, "and the bubble is %.0f px wide at most" % b.rect.size.x)
	_done(s)


# -------------------------------------------------------- time and motion --

func test_a_bubble_stays_about_three_seconds_and_is_then_gone() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	main.clock = 10.0
	overlay.add_bark(_bark("ana"))
	main.clock = 12.0
	eq(overlay.bubble_plan(s.vp).size(), 1, "up two seconds later")
	main.clock = 10.0 + OverlayNode.BUBBLE_SECONDS - 0.05
	eq(overlay.bubble_plan(s.vp).size(), 1, "and just before its time")
	main.clock = 10.0 + OverlayNode.BUBBLE_SECONDS + 0.05
	eq(overlay.bubble_plan(s.vp).size(), 0, "gone after it")
	eq(overlay.bubbles.size(), 0, "and forgotten")
	check(OverlayNode.BUBBLE_SECONDS >= 2.5 and OverlayNode.BUBBLE_SECONDS <= 3.5, "about three seconds: %.1f" % OverlayNode.BUBBLE_SECONDS)
	_done(s)


func test_it_fades_in_and_out() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	main.clock = 0.0
	overlay.add_bark(_bark("ana"))
	var seen := {}
	for t in [0.0, OverlayNode.BUBBLE_FADE_IN * 0.5, OverlayNode.BUBBLE_FADE_IN + 0.3, 1.5, OverlayNode.BUBBLE_SECONDS - OverlayNode.BUBBLE_FADE_OUT * 0.5, OverlayNode.BUBBLE_SECONDS - 0.02]:
		main.clock = t
		var plan: Array = overlay.bubble_plan(s.vp)
		seen[t] = float(plan[0].alpha) if not plan.is_empty() else -1.0
	near(seen[0.0], 0.0, 0.01, "clear when it starts")
	near(seen[OverlayNode.BUBBLE_FADE_IN * 0.5], 0.5, 0.05, "half way in")
	near(seen[OverlayNode.BUBBLE_FADE_IN + 0.3], 1.0, 0.001, "solid after")
	near(seen[1.5], 1.0, 0.001, "solid in the middle")
	check(seen[OverlayNode.BUBBLE_SECONDS - OverlayNode.BUBBLE_FADE_OUT * 0.5] > 0.3 and seen[OverlayNode.BUBBLE_SECONDS - OverlayNode.BUBBLE_FADE_OUT * 0.5] < 0.7, "half way out: %.2f" % seen[OverlayNode.BUBBLE_SECONDS - OverlayNode.BUBBLE_FADE_OUT * 0.5])
	check(seen[OverlayNode.BUBBLE_SECONDS - 0.02] < 0.1, "nearly clear at the end: %.2f" % seen[OverlayNode.BUBBLE_SECONDS - 0.02])
	_done(s)


func test_it_drifts_up_a_little_while_it_is_up() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	main.clock = 0.0
	overlay.add_bark(_bark("ana"))
	main.clock = 0.3
	var early: Dictionary = overlay.bubble_plan(s.vp)[0]
	main.clock = 2.6
	var late: Dictionary = overlay.bubble_plan(s.vp)[0]
	check(late.rect.position.y < early.rect.position.y - 2.0, "higher later: %.1f then %.1f" % [early.rect.position.y, late.rect.position.y])
	check(early.rect.position.y - late.rect.position.y <= OverlayNode.BUBBLE_FLOAT + 0.5, "by a few pixels only")
	_done(s)


func test_with_reduced_motion_there_is_no_fade_and_no_float() -> void:
	Prefs.set_value("ui", "reduce_motion", true)
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	main.clock = 0.0
	overlay.add_bark(_bark("ana"))
	main.clock = 0.01
	var first: Dictionary = overlay.bubble_plan(s.vp)[0]
	near(first.alpha, 1.0, 0.0001, "solid from the first moment")
	main.clock = OverlayNode.BUBBLE_SECONDS - 0.02
	var last: Dictionary = overlay.bubble_plan(s.vp)[0]
	near(last.alpha, 1.0, 0.0001, "and solid to the last")
	near(last.rect.position.y, first.rect.position.y, 0.001, "and it does not move")
	main.clock = OverlayNode.BUBBLE_SECONDS + 0.05
	eq(overlay.bubble_plan(s.vp).size(), 0, "it simply goes at the end")
	Prefs.set_value("ui", "reduce_motion", false)
	_done(s)


# ------------------------------------------------------------- how many --

func test_two_at_most_and_the_oldest_goes() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	_stand(s.ctx, "ruth", s.vp.x / ZOOM * 0.3, s.vp.y / ZOOM * 0.5)
	_stand(s.ctx, "dez", s.vp.x / ZOOM * 0.7, s.vp.y / ZOOM * 0.5)
	main.clock = 0.0
	overlay.add_bark(_bark("ana", "One."))
	main.clock = 0.4
	overlay.add_bark(_bark("ruth", "Two."))
	main.clock = 0.8
	overlay.add_bark(_bark("dez", "Three."))
	eq(overlay.bubbles.size(), 2, "never more than two")
	main.clock = 1.0
	var who: Array = []
	for b in overlay.bubble_plan(s.vp):
		who.append(b.who)
	who.sort()
	eq(who, ["dez", "ruth"], "the first one, Ana's, was dropped")
	check(OverlayNode.BUBBLE_MAX == 2, "the limit is two")
	_done(s)


func test_a_new_line_from_the_same_person_takes_the_place_of_their_old_one() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	_stand(s.ctx, "ruth", s.vp.x / ZOOM * 0.3, s.vp.y / ZOOM * 0.5)
	main.clock = 0.0
	overlay.add_bark(_bark("ana", "First."))
	overlay.add_bark(_bark("ruth", "Ruth speaks."))
	main.clock = 1.0
	overlay.add_bark(_bark("ana", "Second."))
	eq(overlay.bubbles.size(), 2, "two bubbles, not three")
	main.clock = 1.2
	var texts: Array = []
	for b in overlay.bubble_plan(s.vp):
		texts.append(b.text)
	texts.sort()
	eq(texts, ["Ruth speaks.", "Second."], "Ana's new line, Ruth's untouched")
	_done(s)


func test_a_bark_with_no_words_or_from_nobody_makes_nothing() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	overlay.add_bark(_bark("ana", ""))
	overlay.add_bark(_bark("ana", "   "))
	overlay.add_bark(_bark("nobody", "Hello?"))
	overlay.add_bark({"type": "bark"})
	eq(overlay.bubbles.size(), 0, "nothing")
	_done(s)


# ----------------------------------------------------------- in the view --

func test_a_bubble_is_kept_inside_the_view() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	var vp: Vector2 = s.vp
	var spots := {
		"left edge": Vector2(0.3, vp.y / ZOOM * 0.5), "right edge": Vector2(vp.x / ZOOM - 0.3, vp.y / ZOOM * 0.5),
		"top edge": Vector2(vp.x / ZOOM * 0.5, 0.4), "top left": Vector2(0.2, 0.3), "top right": Vector2(vp.x / ZOOM - 0.2, 0.3),
		"bottom right": Vector2(vp.x / ZOOM - 0.2, vp.y / ZOOM - 0.2),
	}
	for name in spots:
		overlay.bubbles.clear()
		s.ana.x = spots[name].x
		s.ana.y = spots[name].y
		main.clock = 1.0
		overlay.add_bark(_bark("ana", "Everyone to the wall, now."))
		main.clock = 1.5
		var plan: Array = overlay.bubble_plan(vp)
		eq(plan.size(), 1, "%s: still drawn" % name)
		if plan.is_empty():
			continue
		var r: Rect2 = plan[0].rect
		check(r.position.x >= OverlayNode.BUBBLE_MARGIN - 0.01 and r.end.x <= vp.x - OverlayNode.BUBBLE_MARGIN + 0.01, "%s: sideways inside the view: %s in %s" % [name, str(r), str(vp)])
		check(r.position.y >= OverlayNode.BUBBLE_MARGIN - 0.01 and r.end.y <= vp.y, "%s: and up and down: %s" % [name, str(r)])
	_done(s)


func test_a_speaker_near_the_right_edge_gets_the_tail_turned_to_point_at_them() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	var vp: Vector2 = s.vp
	s.ana.x = vp.x / ZOOM - 0.8
	s.ana.y = vp.y / ZOOM * 0.5
	main.clock = 0.0
	overlay.add_bark(_bark("ana", "Everyone to the wall, now."))
	main.clock = 1.0
	var b: Dictionary = overlay.bubble_plan(vp)[0]
	eq(b.flip, true, "the picture is mirrored: the tail is at the right")
	near(b.tip.x, s.ana.x * ZOOM, 1.5, "and its tip is still over her")
	check(b.rect.position.x < b.tip.x and b.rect.end.x >= b.tip.x, "inside the bubble's span")
	# in the middle of the window the tail is at the left, as the picture is
	s.ana.x = vp.x / ZOOM * 0.4
	var mid: Dictionary = overlay.bubble_plan(vp)[0]
	eq(mid.flip, false, "mid-window: not mirrored")
	_done(s)


func test_nothing_for_a_speaker_who_is_off_the_screen() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	main.clock = 0.0
	overlay.add_bark(_bark("ana"))
	s.ana.x = -30.0
	main.clock = 1.0
	eq(overlay.bubble_plan(s.vp).size(), 0, "to the left of the view")
	s.ana.x = s.vp.x / ZOOM + 40.0
	eq(overlay.bubble_plan(s.vp).size(), 0, "to the right of it")
	s.ana.x = s.vp.x / ZOOM * 0.5
	s.ana.y = s.vp.y / ZOOM + 40.0
	eq(overlay.bubble_plan(s.vp).size(), 0, "below it")
	s.ana.y = s.vp.y / ZOOM * 0.5
	eq(overlay.bubble_plan(s.vp).size(), 1, "and back in view it shows again, for what is left of its time")
	_done(s)


func test_nothing_for_the_dead_or_the_away() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	main.clock = 0.0
	overlay.add_bark(_bark("ana"))
	main.clock = 0.5
	eq(overlay.bubble_plan(s.vp).size(), 1, "she is here")
	s.ana.away = {"kind": "party", "site": "pharmacy"}
	eq(overlay.bubble_plan(s.vp).size(), 0, "away on a trip")
	s.ana.away = null
	s.ana.dead = true
	eq(overlay.bubble_plan(s.vp).size(), 0, "dead")
	s.ana.dead = false
	# a bark from someone who is away or dead (nobody can hear it) is not kept at all
	s.ana.away = {"kind": "party", "site": "pharmacy"}
	overlay.bubbles.clear()
	overlay.add_bark(_bark("ana", "Late."))
	eq(overlay.bubbles.size(), 0, "from someone away")
	s.ana.away = null
	s.ana.dead = true
	overlay.add_bark(_bark("ana", "Later."))
	eq(overlay.bubbles.size(), 0, "from the dead")
	_done(s)


# ----------------------------------------------------------------- modals --

func test_no_bubbles_while_a_menu_or_a_dialog_is_open() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	main.clock = 0.0
	overlay.add_bark(_bark("ana"))
	main.clock = 0.5
	eq(overlay.bubble_plan(s.vp).size(), 1, "up")
	main.menu_open = true
	eq(overlay.bubble_plan(s.vp).size(), 0, "none under a menu")
	overlay.add_bark(_bark("ana", "Another."))
	eq(overlay.bubbles.size(), 1, "and a bark that comes meanwhile is not kept")
	main.menu_open = false
	eq(overlay.bubble_plan(s.vp).size(), 1, "the one that was up is back when the menu is gone")
	var hud := FakeHud.new()
	main.hud = hud
	hud.modal = true
	eq(overlay.bubble_plan(s.vp).size(), 0, "none under the HUD's dialog either")
	hud.modal = false
	eq(overlay.bubble_plan(s.vp).size(), 1, "back")
	_done(s)


func test_it_asks_the_real_huds_modal_check() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	main.hud = s.ctx.hud
	main.clock = 0.0
	overlay.add_bark(_bark("ana"))
	main.clock = 0.5
	eq(overlay.bubble_plan(s.vp).size(), 1, "up")
	s.ctx.sim.over = "defeat"
	Kit.update(s.ctx)
	eq(overlay.bubble_plan(s.vp).size(), 0, "none once the end screen is up")
	main.hud = null
	_done(s)


func test_the_storytellers_radio_card_silences_the_bubbles_and_they_come_back_after() -> void:
	# the real game: a card put up at the radio is a page over the whole window (story_ui.gd opens it)
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	var ok: bool = main.get("story_ui") != null and main.sim.storyteller.force("heavy_rain")
	if not ok:
		await Fakes.leave(g)
		return
	main._handle_events()
	var radio = main.story_ui.radio
	check(radio != null, "the radio card is up")
	if radio != null:
		check(main.hud.modal_open(), "and the HUD calls it a modal")
		var ruth = main.sim.people[0]
		main.overlay.add_bark(_bark(ruth.id, "Hold the line."))
		eq(main.overlay.bubbles.size(), 0, "no bubble is made while it is up")
		radio.put_away()
		check(not main.hud.modal_open(), "put away, it is not a modal any more")
		main.overlay.add_bark(_bark(ruth.id, "Hold the line."))
		eq(main.overlay.bubbles.size(), 1, "and the bubbles are back")
	await Fakes.leave(g)


# ------------------------------------------------------------------ drawing --

func test_the_overlay_draws_bubbles_without_a_hitch_framed_flat_and_flipped() -> void:
	var s := _setup()
	var overlay = s.o.overlay
	var main = s.o.main
	main.clock = 0.0
	overlay.add_bark(_bark("ana", "Everyone to the wall, now."))
	main.clock = 1.0
	for frames in [true, false]:
		Hud.use_frames = frames
		for x in [0.5, 0.45, 0.97]:
			s.ana.x = s.vp.x / ZOOM * x
			overlay.queue_redraw()
			await Kit.settle()
	Hud.use_frames = true
	eq(overlay.drawn_bubbles, 1, "the draw counts the bubble it put on the screen")
	_done(s)


func test_a_draw_with_no_bubbles_draws_none() -> void:
	var s := _setup()
	s.o.overlay.queue_redraw()
	await Kit.settle()
	eq(s.o.overlay.drawn_bubbles, 0, "none")
	_done(s)


# ------------------------------------------------------------------- main --

func test_main_forwards_bark_events_to_the_overlay() -> void:
	var g := Fakes.game({"difficulty": 1, "seed": 7})
	var main = g.main
	main.sim.events.append(_bark("ruth", "Bell's ringing."))
	main.sim.events.append({"type": "shot", "weapon": "shotgun", "x": 10.0, "y": 10.0})
	main._handle_events()
	eq(main.overlay.bubbles.size(), 1, "a bubble for the bark")
	eq(main.overlay.bubbles[0].text, "Bell's ringing.", "with her words")
	eq(main.sim.events.size(), 0, "and the events are used up as before")
	await Fakes.leave(g)


func test_main_keeps_barks_from_the_title_screens_yard_quiet() -> void:
	var g := Fakes.game({"title": true})
	var main = g.main
	check(main.title_mode, "the title is up")
	main.sim.events.append(_bark("ruth", "Bell's ringing."))
	main._handle_events()
	eq(main.overlay.bubbles.size(), 0, "no bubble under the title")
	await Fakes.leave(g)
