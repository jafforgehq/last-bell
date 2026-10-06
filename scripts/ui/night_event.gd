## The night event (One House, NIGHTEV): what the first attack feels like at the bell. A VIEW PART of the town's facade (scripts/town/town_game.gd), made of three small things:
##
##   1. THE BELL BANNER. At the dusk bell of a night when the dead come (`scenario.attacks_on()`), the banner the rules put up ("The bell rings: Everyone to the wall") is
##      said again in the same banner, in the town's words: "THE BELL", and under it what the lookout's forecast knows: "Tonight: a dozen or more dead from the north.
##      Hold the fence." (the size is rounded to words, the side is a compass word; a brute or runners are added when the forecast says so); when nobody watched the road
##      (`tactics.forecast()` was not given) "Tonight the dead come. Nobody saw how many." The event's own words are replaced in place (the facade hands the part each event
##      before `Main._handle_events` shows its banner), so there is ONE banner, never two. The crew's "everyone is heading to their posts" is the rules' own alert
##      ("The bell has rung", `sim.alert("bell")`), which stays in the feed on such a night: so no toast of ours says it again.
##   2. THE VIGNETTE. A screen-edge shade on a CanvasLayer between the world and the HUD: warm at the bell, it closes in and goes cold over about three seconds, then
##      relaxes (about a second). With Reduce motion it does not move: a short static fade (`hud._calm()`).
##   3. THE CHIP "Dusk in 1:48": under the clock, in the last two game hours before the bell while the dead are coming tonight (`CHIP_HOURS`; hours and minutes of the game's clock).
##
## A QUIET night (no attack yet) is not touched: the rules' own banner says "Night falls" / "The bell: Dusk, be indoors before dark" already.
## It only reads the rules (`sim.get(...)`, `has_method`), and writes nothing in them.
##
## DEBUG: `--moment=bell` (with `--town --stage=night`: the first attack night at 18:45; `--stage=fourth` is the night BEFORE it, a quiet one) plays the moment once at the first frame and holds the vignette at its
## peak; a screenshot run takes its shot about a second later whatever `--frames` says. The banner's own hold is about three seconds.
extends RefCounted

const Fonts := preload("res://scripts/ui/fonts.gd")

const TITLE := "The bell"
const UNKNOWN_SUB := "Tonight the dead come. Nobody saw how many."
## The chip is up this many game hours before the bell.
const CHIP_HOURS := 2.0
## The vignette: seconds closing in, seconds relaxing; with Reduce motion one short fade of VIG_CALM_S.
const VIG_CLOSE_S := 2.8
const VIG_RELAX_S := 1.2
const VIG_CALM_S := 1.7
## Where in its length the vignette is held by `--moment=bell`.
const VIG_PEAK_S := 2.5
## Frames between the moment of a debug shot and the shot (a banner has faded in by then).
const SHOT_AFTER_FRAMES := 45

const SHADER_CODE := """
shader_type canvas_item;
uniform float closing = 0.0;
uniform float amount = 0.0;
uniform float warmth = 1.0;
void fragment() {
	vec2 q = (UV - vec2(0.5)) * 2.0;
	float d = length(q);
	float inner = mix(1.20, 0.58, closing);
	float v = smoothstep(inner, inner + 0.80, d);
	vec3 c = mix(vec3(0.03, 0.07, 0.17), vec3(0.93, 0.45, 0.14), warmth);
	COLOR = vec4(c, v * amount * mix(0.88, 0.5, warmth));
}
"""

var main
var hud
## What the banner said last (the tests read it): {"title", "sub"}.
var words := {}
## The text on the chip now ("" when it is away), and the vignette's seconds (-1: not up).
var chip_text := ""
var vignette_t := -1.0

var _layer: CanvasLayer
var _rect: ColorRect
var _mat: ShaderMaterial
var _chip: PanelContainer
var _chip_icon: TextureRect
var _chip_label: Label
var _chip_tone := Color.TRANSPARENT
var _hold := false
var _debug := ""
var _debug_done := false


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	_build_vignette()
	_build_chip()
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--moment="):
			_debug = String(arg).trim_prefix("--moment=")


# ------------------------------------------------------------------------ the sim --

func _sim():
	return main.get("sim") if main != null else null


func _attacks() -> bool:
	var sim = _sim()
	var sc = sim.get("scenario") if sim != null else null
	return sc != null and sc.has_method("attacks_on") and bool(sc.attacks_on())


# ----------------------------------------------------------------------- the words --

## The size of the night in words, from the forecast's number (a multiple of five, from five).
static func size_words(total: int) -> String:
	if total <= 5:
		return "a handful of"
	if total <= 10:
		return "about ten"
	if total <= 15:
		return "a dozen or more"
	if total <= 20:
		return "about twenty"
	if total <= 30:
		return "two dozen or more"
	return "about %d" % (roundi(float(total) / 10.0) * 10)


## "north east and south" (the rules' words for where they come from) -> "north-east and the south" (to follow "from the ").
static func side_words(heading: String) -> String:
	var names: Array = []
	for part in heading.split(" and ", false):
		var one := String(part).strip_edges().replace(" ", "-")
		if one != "" and not names.has(one):
			names.append(one)
	return " and the ".join(names)


## [title, sub] of the bell on a night when the dead come, from what the lookout's forecast told (`tactics.forecast()`: {} or {"given": false} when nobody watched the road).
## `wall` is what is held tonight: "fence" or "doors".
static func words_for(f: Dictionary, wall: String = "fence") -> Array:
	if not bool(f.get("given", false)):
		return [TITLE, UNKNOWN_SUB]
	var total := int(f.get("total", 0))
	var side := side_words(String(f.get("heading", f.get("side", ""))))
	var line := "Tonight: %s dead" % size_words(total)
	if side != "":
		line += " from the %s" % side
	var brutes := int(f.get("brutes", 0))
	if brutes > 0:
		var kind := "plated brute" if int(f.get("plated", 0)) > 0 else "brute"
		line += ", and %s" % ("a %s" % kind if brutes == 1 else "%d %ss" % [brutes, kind])
	elif bool(f.get("runners", false)):
		line += ", with runners"
	return [TITLE, "%s. Hold the %s." % [line, wall]]


## What the base holds against the dead: "fence" while a fence or the gate is built, else "doors".
func _wall_word() -> String:
	var sim = _sim()
	var per = sim.get("perimeter") if sim != null else null
	if per != null and per.has_method("sections"):
		for s in per.sections():
			var kind := String(s.get("kind", ""))
			if kind == "fence" or kind == "gate":
				return "fence"
	return "doors"


## The words of tonight's bell as the rules know them now.
func attack_words() -> Array:
	var sim = _sim()
	var f := {}
	var tac = sim.get("tactics") if sim != null else null
	if tac != null and tac.has_method("forecast"):
		var got = tac.forecast()
		if got is Dictionary:
			f = got
	return words_for(f, _wall_word())


# --------------------------------------------------------------------------- events --

func on_event(e: Dictionary) -> void:
	if hud == null:
		return
	match String(e.get("type", "")):
		"bell":
			if _attacks():
				_start_vignette(false)
		"banner":
			# (the rules' banner of the bell on a night of the attacks: the same banner, the town's words; the quiet nights' is the town's own already)
			if String(e.get("text", "")) == "The bell rings" and _attacks():
				var w := attack_words()
				e["text"] = String(w[0])
				e["sub"] = String(w[1])
				words = {"title": String(w[0]), "sub": String(w[1])}


# -------------------------------------------------------------------------- frames --

func on_frame(dt: float) -> void:
	if hud == null or main == null:
		return
	if _debug != "" and not _debug_done:
		_debug_done = true
		_debug_moment()
	_step_vignette(dt)
	_step_chip()


# ------------------------------------------------------------------------ vignette --

func _build_vignette() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 2    # (over the world, its glow and the overlay's names; under the HUD, which is layer 3)
	_layer.name = "NightVignette"
	_rect = ColorRect.new()
	_rect.color = Color.WHITE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect.material = _mat
	_rect.visible = false
	_layer.add_child(_rect)
	main.add_child(_layer)


func _calm() -> bool:
	return hud != null and hud.has_method("_calm") and bool(hud._calm())


## Starts the vignette from its beginning; `hold` keeps it at its peak (the debug moment).
func _start_vignette(hold: bool, at_s: float = VIG_PEAK_S) -> void:
	if _rect == null:
		return
	vignette_t = 0.0
	_hold = hold
	if hold:
		vignette_t = 0.6 if _calm() else at_s    # (Reduce motion: the middle of its still fade)
	_apply_vignette()


func _step_vignette(dt: float) -> void:
	if vignette_t < 0.0:
		return
	if not _hold:
		vignette_t += dt
	var length := VIG_CALM_S if _calm() else VIG_CLOSE_S + VIG_RELAX_S
	if vignette_t >= length and not _hold:
		vignette_t = -1.0
		_rect.visible = false
		return
	_apply_vignette()


## {"amount", "closing", "warmth"} at `t` seconds: warm to cold and closing in while `VIG_CLOSE_S` runs, then relaxing; Reduce motion: a fade in and out of a still one.
static func params_at(t: float, calm: bool) -> Dictionary:
	if calm:
		var a := minf(t / 0.15, 1.0) * clampf((VIG_CALM_S - t) / 0.5, 0.0, 1.0)
		return {"amount": 0.7 * a, "closing": 0.5, "warmth": 0.5}
	var k := clampf(t / VIG_CLOSE_S, 0.0, 1.0)
	var closing := 1.0 - pow(1.0 - k, 3.0)
	var warmth := 1.0 - smoothstep(0.1, VIG_CLOSE_S, t)
	var amount := minf(t / 0.35, 1.0)
	if t > VIG_CLOSE_S:
		var r := clampf((t - VIG_CLOSE_S) / VIG_RELAX_S, 0.0, 1.0)
		var ease_r := r * r * (3.0 - 2.0 * r)
		closing = lerpf(1.0, 0.45, ease_r)
		amount = 1.0 - ease_r
	return {"amount": amount, "closing": closing, "warmth": warmth}


func _apply_vignette() -> void:
	var p := params_at(vignette_t, _calm())
	_mat.set_shader_parameter("amount", float(p.amount))
	_mat.set_shader_parameter("closing", float(p.closing))
	_mat.set_shader_parameter("warmth", float(p.warmth))
	_rect.visible = float(p.amount) > 0.001


# ---------------------------------------------------------------------------- chip --

func _build_chip() -> void:
	_chip = PanelContainer.new()
	_chip.mouse_filter = Control.MOUSE_FILTER_PASS
	_chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_chip.tooltip_text = "The bell rings at dusk, and the dead come tonight"
	var row: HBoxContainer = hud._hbox(6)
	_chip_icon = hud._icon("bell", 14, hud.ACCENT)
	_chip_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_chip_icon)
	_chip_label = hud._label("", Fonts.cond(700, 1), 14, hud.ACCENT)
	row.add_child(_chip_label)
	_chip.add_child(row)
	_chip.visible = false
	var col = hud.get("right_col")
	var clock = hud.get("clock")
	if col is Control and clock is Control and clock.get_parent() == col:
		col.add_child(_chip)
		col.move_child(_chip, clock.get_index() + 1)
	else:
		hud.add_child(_chip)    # (no column to sit in: the corner it is in then is the HUD's own)


## A slate chip with a thin edge of `tone` (it sits over the world as often as over a panel: the pill frame's tint is too thin to read on grass).
func _chip_box(tone: Color) -> StyleBox:
	var s: StyleBoxFlat = hud._flat(hud.PANEL, 6, Color(tone, 0.85), true)
	s.set_border_width_all(1)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 5
	return s


## The text of the chip for `hours_left` game hours to the bell ("Dusk in 1:48"), rounded up to the minute.
static func chip_words(hours_left: float) -> String:
	var m := ceili(maxf(hours_left, 0.0) * 60.0 - 0.0001)
	return "Dusk in %d:%02d" % [m / 60, m % 60]


func _step_chip() -> void:
	var sim = _sim()
	var on := false
	var left := 0.0
	if sim != null and _attacks() and String(sim.phase) == "day" and not bool(sim.bell_rung) and sim.get("seasons") != null:
		left = fposmod(float(sim.seasons.dusk_hour()) - float(sim.hour), 24.0)
		on = left > 0.0 and left <= CHIP_HOURS
	if not on:
		if _chip.visible:
			_chip.visible = false
		chip_text = ""
		return
	chip_text = chip_words(left)
	if _chip_label.text != chip_text.to_upper():
		_chip_label.text = chip_text.to_upper()
	# (gold, then the amber of a warning in the last half hour)
	var tone: Color = hud.WARN if left <= 0.5 else hud.ACCENT
	if tone != _chip_tone:
		_chip_tone = tone
		_chip.add_theme_stylebox_override("panel", _chip_box(tone))
		_chip_label.add_theme_color_override("font_color", tone)
		_chip_icon.modulate = tone
	_chip.visible = true


# ----------------------------------------------------------------------------- debug --

## `--moment=bell`: the bell's moment played once, as the rules' own event would (the banner in the town's words, the vignette held at its peak); a screenshot run is told to
## take its shot a second later. Nothing happens (and a line says so) when the dead are not coming tonight.
func _debug_moment() -> void:
	var spec := _debug.split(":")
	if spec[0] != "bell":
		return
	if not _attacks():
		print("--moment=bell: the dead are not coming tonight (give --stage=night: the first attack night, at 18:45)")
		return
	var w := attack_words()
	words = {"title": String(w[0]), "sub": String(w[1])}
	hud.show_banner(String(w[0]), String(w[1]))
	# (`--moment=bell:1.2` holds the vignette at that second of its length: warm and opening; the default is its peak)
	_start_vignette(true, float(spec[1]) if spec.size() > 1 and String(spec[1]).is_valid_float() else VIG_PEAK_S)
	if String(main.get("shot_path")) != "":
		main.shot_frames = int(main.frame_count) + SHOT_AFTER_FRAMES
