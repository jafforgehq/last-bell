## "Text size" (Settings: Normal, Large, Larger): the words of the HUD and of the menus are drawn 1.0, 1.15 or 1.3 times as big, on top of the interface size.
##
## HOW. Every label, button and line edit under the HUD and the menu shell has its font size set as a theme override (`hud._label`, `RadioKit.small_button`...). This node scales
## those overrides in place: the size a control had is kept in its meta `ts_base` and the size it was given in `ts_set`, so that going back to Normal puts the base back, and a
## control whose size the game changed since (a card that is laid out anew sets its own) is noticed at the next look and taken as the new base. A control that is made later is
## scaled the moment it enters the tree (`node_added`: its creator has set its size before adding it) and every second the trees are looked at again for the others. At Normal
## it does nothing at all: no signal is listened to and nothing is walked.
##
## WHAT IS LEFT. Words that are drawn, not laid out (the minimap's N, the names over the heads in the world) keep their size; the order wheel's captions ask `Access.text_k()` for
## themselves. `NOT_SCALED` names the few HUD boards whose layout is a fixed grid of pictures (the crew's cards: a name is trimmed to its card), so that Large and Larger never
## push them into each other.
extends Node

const Access := preload("res://scripts/access.gd")

## How often (seconds) the trees are looked at again while the text is not Normal.
const RESCAN_S := 1.0
## How many nodes of the slow look are handled in a frame.
const SCAN_BUDGET := 300
## The fonts of a RichTextLabel that are scaled (its own sizes, one for each weight).
const RICH_SIZES := ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]

var roots: Array = []
## The factor now (1.0 when nothing is scaled), and the HUD whose tooltip theme follows.
var k := 1.0
var hud = null
## Controls under these (by `hud.get(name)`) are left at their size.
var skip_names: Array = ["bar"]
var _skip: Array = []
var _stack: Array = []
var _t := 0.0
var _listening := false


## Attach to the main node: `roots` are the HUD and the shell (null ones are left out).
func setup(main_node) -> void:
	name = "TextScale"
	hud = main_node.get("hud")
	for r in [main_node.get("hud"), main_node.get("shell")]:
		if r != null:
			roots.append(r)
	refresh()


## Reads the setting and puts it to work: scales every control to the new factor (and back to the base at Normal).
func refresh() -> void:
	k = Access.text_k()
	_skip.clear()
	if hud != null:
		for n in skip_names:
			var c = hud.get(n)
			if c is Node:
				_skip.append(c)
		_theme_size()
	_stack.clear()
	var on := not is_equal_approx(k, 1.0)
	if on and not _listening and is_inside_tree():
		get_tree().node_added.connect(_on_added)
		_listening = true
	elif not on and _listening:
		get_tree().node_added.disconnect(_on_added)
		_listening = false
	for r in roots:
		if is_instance_valid(r):
			_walk(r)
	set_process(on)


## The slow look: every RESCAN_S seconds the trees are gone through again, SCAN_BUDGET nodes a frame (a whole walk at once would be a hitch once a second).
func _process(dt: float) -> void:
	if _stack.is_empty():
		_t += dt
		if _t >= RESCAN_S:
			_t = 0.0
			for r in roots:
				if is_instance_valid(r):
					_stack.append(r)
		return
	var n := 0
	while n < SCAN_BUDGET and not _stack.is_empty():
		var node: Node = _stack.pop_back()
		if not is_instance_valid(node) or (node is Control and _skip.has(node)):
			continue
		_scale(node)
		n += 1
		for c in node.get_children():
			_stack.append(c)


## The tooltip's text follows (the HUD's theme is the shell's too).
func _theme_size() -> void:
	if hud.theme != null and hud.theme.has_font_size("font_size", "TooltipLabel"):
		var base := int(hud.theme.get_meta("ts_base", hud.theme.get_font_size("font_size", "TooltipLabel")))
		hud.theme.set_meta("ts_base", base)
		hud.theme.set_font_size("font_size", "TooltipLabel", maxi(base, roundi(float(base) * k)))


func _on_added(n: Node) -> void:
	if not (n is Control):
		return
	for r in roots:
		if is_instance_valid(r) and r.is_ancestor_of(n):
			_walk(n)
			return


func _walk(n: Node) -> void:
	if n is Control and _skip.has(n):
		return
	_scale(n)
	for c in n.get_children():
		_walk(c)


func _scale(n: Node) -> void:
	if n is Label or n is Button or n is LineEdit:
		_scale_size(n, "font_size")
	elif n is RichTextLabel:
		for key in RICH_SIZES:
			_scale_size(n, key)


## Scales one font size override of `c`, keeping what it was.
func _scale_size(c: Control, key: String) -> void:
	if not c.has_theme_font_size_override(key):
		return
	var meta_base := "ts_base_" + key
	var meta_set := "ts_set_" + key
	if is_equal_approx(k, 1.0) and not c.has_meta(meta_set):
		return    # (never scaled: nothing to put back)
	var cur := c.get_theme_font_size(key)
	if c.has_meta(meta_set) and cur != int(c.get_meta(meta_set)):
		c.remove_meta(meta_base)    # (the game set it again since: that is the base now)
	var base := int(c.get_meta(meta_base, cur))
	var want := base if is_equal_approx(k, 1.0) else maxi(base, roundi(float(base) * k))
	c.set_meta(meta_base, base)
	if want != cur:
		c.add_theme_font_size_override(key, want)
	c.set_meta(meta_set, want)
