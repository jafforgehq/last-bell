## Small pieces the menus share (title, pause, settings, new game, load, credits): the
## words that describe a save or a difficulty, a few textures and styles, and the way a
## focus ring is drawn. Nothing here knows about the game's scene: it is all plain
## functions, so the tests can call them.
extends RefCounted

const Waves := preload("res://scripts/sim/waves.gd")
const Medical := preload("res://scripts/sim/medical.gd")
const Scavenge := preload("res://scripts/sim/scavenge.gd")
const Sim := preload("res://scripts/sim/sim.gd")

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
## The difficulties, by index (the rules' own names: Sim.DIFFICULTY_NAMES) and the one
## line each is sold with. What they really change is `difficulty_facts`.
const DIFFICULTY_LINES := ["Fewer of the dead, kinder wounds", "The intended game", "For people who have won"]

static var _discs := {}


# ------------------------------------------------------------ words --

static func difficulty_name(i: int) -> String:
	return String(Sim.DIFFICULTY_NAMES[clampi(i, 0, Sim.DIFFICULTY_NAMES.size() - 1)])


static func difficulty_line(i: int) -> String:
	return String(DIFFICULTY_LINES[clampi(i, 0, DIFFICULTY_LINES.size() - 1)])


## What a difficulty really changes, worked out from the rules' own numbers (so that
## the words stay true when the numbers are tuned): how many of the dead come each
## night, how likely a bite is to infect, and how dangerous a trip outside is.
static func difficulty_facts(i: int) -> String:
	i = clampi(i, 0, 2)
	var dead := float(Waves.DIFFICULTY[i])
	var infect := float(Medical.INFECT_CHANCE[i])
	var trips := float(Scavenge.DANGER_MULT[i])
	var first := roundi(Waves.BASE * dead)
	var more := roundi(Waves.BASE * Waves.GROWTH * dead)
	var parts: Array = []
	if absf(dead - 1.0) < 0.005:
		parts.append("As designed: about %d of the dead on the first night, %d more each night after." % [first, more])
	elif dead < 1.0:
		parts.append("%d%% fewer of the dead: about %d on the first night, %d more each night after." % [roundi((1.0 - dead) * 100.0), first, more])
	else:
		parts.append("%d%% more of the dead: about %d on the first night, %d more each night after." % [roundi((dead - 1.0) * 100.0), first, more])
	if infect >= 0.995:
		parts.append("Every bite infects.")
	else:
		parts.append("A bite infects %d times in 10." % roundi(infect * 10.0))
	if absf(trips - 1.0) < 0.005:
		parts.append("Trips outside carry their usual risk.")
	elif trips < 1.0:
		parts.append("Trips outside are %d%% less dangerous." % roundi((1.0 - trips) * 100.0))
	else:
		parts.append("Trips outside are %d%% more dangerous." % roundi((trips - 1.0) * 100.0))
	return " ".join(parts)


## 14.33 -> "14:20".
static func clock_text(hour: float) -> String:
	var m := roundi(hour * 60.0) % 1440
	return "%02d:%02d" % [floori(m / 60.0), m % 60]


## What a save is, in a line: "Day 7, 14:20, Standard", from SaveGame.peek's answer.
static func save_line(info: Dictionary) -> String:
	if not bool(info.get("ok", false)):
		return String(info.get("reason", "Empty"))
	return "Day %d, %s, %s" % [int(info.day), clock_text(float(info.hour)), difficulty_name(int(info.difficulty))]


## "just now", "5 min ago", "3 h ago", "yesterday", then the date; `now` and `then` are Unix seconds.
static func ago_text(then: int, now: int) -> String:
	if then <= 0:
		return ""
	var s := now - then
	if s < 60:
		return "just now"
	if s < 3600:
		return "%d min ago" % floori(s / 60.0)
	if s < 86400:
		return "%d h ago" % floori(s / 3600.0)
	if s < 2 * 86400:
		return "yesterday"
	var d := Time.get_datetime_dict_from_unix_time(then)
	return "%s %d" % [MONTHS[clampi(int(d.month) - 1, 0, 11)], int(d.day)]


## 1.2 -> "120%".
static func percent_text(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


## The index of the save to continue from among the answers of SaveGame.peek: the one that
## can be loaded and was written last (the same second: the later in the run); -1 if none can.
static func newest_index(infos: Array) -> int:
	var best := -1
	for i in infos.size():
		var info: Dictionary = infos[i]
		if not bool(info.get("ok", false)):
			continue
		if best < 0:
			best = i
			continue
		var b: Dictionary = infos[best]
		var newer := int(info.modified) > int(b.modified)
		var same := int(info.modified) == int(b.modified)
		var later := float(info.day) * 24.0 + float(info.hour) > float(b.day) * 24.0 + float(b.hour)
		if newer or (same and later):
			best = i
	return best


# --------------------------------------------------------- the look --

## The ring round the button that has the keyboard: `color` is gold, or cream on a gold button.
static func focus_box(color: Color, radius: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = color
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	s.expand_margin_left = 1
	s.expand_margin_right = 1
	s.expand_margin_top = 1
	s.expand_margin_bottom = 1
	return s


## A round dot with a rim (the knob of a slider): `radius` px, drawn once and kept.
static func disc(radius: int, fill: Color, rim: Color, rim_width: float = 2.0) -> ImageTexture:
	var key := "%d|%s|%s|%.1f" % [radius, fill.to_html(), rim.to_html(), rim_width]
	if _discs.has(key):
		return _discs[key]
	var d := radius * 2 + 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) / 2.0
	for y in d:
		for x in d:
			var r := Vector2(x - c, y - c).length()
			var edge := clampf(radius + 0.5 - r, 0.0, 1.0)
			var inner := clampf(r - (radius - rim_width) + 0.5, 0.0, 1.0)
			var col := fill.lerp(rim, inner)
			col.a = edge
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_discs[key] = tex
	return tex


## Darkens the edges of the picture, so that the world behind a menu stays readable and the
## menu sits in it (clear in the middle, `strength` dark at the corners).
static func vignette_texture(strength: float = 0.72) -> GradientTexture2D:
	var dark := Color(0.035, 0.03, 0.024, strength)
	var clear := Color(dark, 0.0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([clear, clear, dark])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.1, 0.5)
	t.width = 256
	t.height = 256
	return t


## A shade across the left of the picture, behind the menu's column: dark at the edge,
## gone by `reach` (0 to 1 of the width).
static func shade_texture(strength: float = 0.84, reach: float = 0.62) -> GradientTexture2D:
	var dark := Color(0.035, 0.03, 0.024, strength)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, reach * 0.42, reach])
	g.colors = PackedColorArray([dark, Color(dark, strength * 0.8), Color(dark, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(1.0, 0.0)
	t.width = 256
	t.height = 4
	return t


## Lets the keyboard reach (or not) every control under `root` that could have it: used
## to keep Tab and the arrows out of a screen that another one is covering.
static func set_focusable(root: Node, on: bool) -> void:
	if root is Control:
		var c: Control = root
		if on:
			if c.has_meta("focus_was"):
				c.focus_mode = int(c.get_meta("focus_was")) as Control.FocusMode
				c.remove_meta("focus_was")
		elif c.focus_mode != Control.FOCUS_NONE:
			c.set_meta("focus_was", int(c.focus_mode))
			c.focus_mode = Control.FOCUS_NONE
	for child in root.get_children():
		set_focusable(child, on)
