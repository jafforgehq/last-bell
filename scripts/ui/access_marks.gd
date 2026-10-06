## The colour-blind markers that sit on pages made by other views (One House, HELP): a VIEW PART of the town's facade (scripts/town/town_game.gd `VIEW_PARTS`: `on_ready(main)`,
## `on_frame(dt)`). While "Colour-blind markers" is on (Settings; `Access.markers()`), every project card of the Build page (the NEXT card and the list) gets a small shape before the word of
## its state, from the word itself (the page keeps writing "READY", "BUILDING 1 OF 3", "DONE"...): a plus for ready, a triangle for going up, a ring for part of it up, a diamond for fallen,
## a cross for locked and a check for done (scripts/ui/cb_shapes.gd). It adds one node to each card's head row and takes them away again when the setting goes off. It reads the page's
## own cards (`cards`, `next_card`, each with its `chip` label) and writes nothing in the rules; a page that is not made, or has none of these, is left alone.
extends RefCounted

const Access := preload("res://scripts/access.gd")
const CbShapes := preload("res://scripts/ui/cb_shapes.gd")

const EVERY_S := 0.4
const MARK_NAME := "CbMark"

var main
var hud
var _t := EVERY_S
var _was_on := false


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")


func on_frame(dt: float) -> void:
	if hud == null:
		return
	_t += dt
	if _t < EVERY_S:
		return
	_t = 0.0
	var on := Access.markers()
	if not on and not _was_on:
		return
	_was_on = on
	for c in _cards():
		_sync(c, on)


## The Build page's cards that are made: the NEXT card and the list's.
func _cards() -> Array:
	var out: Array = []
	var rp = hud.get("radio_panel")
	if rp == null or not (rp.get("pages") is Dictionary):
		return out
	var build = (rp.pages as Dictionary).get("build")
	if build == null:
		return out
	if build.get("next_card") is Dictionary:
		out.append(build.next_card)
	if build.get("cards") is Dictionary:
		for id in build.cards:
			out.append(build.cards[id])
	return out


## The shape of a state word.
static func shape_of(word: String) -> String:
	var w := word.to_upper()
	if w.begins_with("LOCKED"):
		return "cross"
	if w.begins_with("BUILDING"):
		return "triangle"
	if w.begins_with("DONE"):
		return "check"
	if w.contains("FALLEN"):
		return "diamond"
	if w.contains(" UP"):
		return "circle"
	return "plus"


func _sync(c, on: bool) -> void:
	if not (c is Dictionary) or not (c.get("chip") is Label):
		return
	var chip: Label = c.chip
	if not is_instance_valid(chip) or chip.get_parent() == null:
		return
	var head: Node = chip.get_parent()
	var mark := head.get_node_or_null(MARK_NAME)
	if not on:
		if mark != null:
			mark.queue_free()
		return
	var tint: Color = chip.get_theme_color("font_color")
	var shape := shape_of(chip.text)
	if mark == null:
		mark = CbShapes.Mark.new(shape, tint, 5.0)
		mark.name = MARK_NAME
		head.add_child(mark)
		head.move_child(mark, chip.get_index())
	(mark as CbShapes.Mark).set_kind(shape, tint)
	mark.visible = chip.visible
