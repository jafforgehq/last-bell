## The red edge of the screen when the avatar is hurt (One House, HUDB): feedback you do not have to read. A VIEW PART of the town's facade (scripts/town/town_game.gd
## `VIEW_PARTS`: `on_ready(main)`, `on_frame(dt)`).
##
## WHAT IT DOES. One full-screen quad under the HUD's boards and over the world (scripts/ui/hurt_pulse.gdshader: a soft vignette, nothing in the middle). Its strength is the
## most of three things, and it is not drawn at all (the quad hidden) when all three are nothing:
##   - a BLOW: the avatar's health dropped (a bite is 9 to 15; the part reads the drop, it does not wait to be told): the edge jumps to full and falls away in under a second,
##     and a short low thump plays (the game's own `thud`, pitched down: `sound.play`, so the sound button and the sliders apply). Blows closer than THUMP_GAP_S sound once.
##   - LOW HEALTH: at LOW_AT (30 percent) of the health or under, a steady faint red edge that grows as the health goes, with a slow heartbeat on it (a double beat, never faster than about two
##     beats of the pair a second: nothing flashes more than three times a second, at a low strength).
##   - BLEEDING or DOWN: bleeding at any health keeps a very faint edge and a slow breath (the heartbeat's slowest); down, a steady heavier one.
## REDUCE FLASHES (Settings, `ui/reduce_flashes`) and REDUCE MOTION (`ui/reduce_motion`, which also means no fades): no heartbeat, no breath, no falling away: the edge is a still, faint
## one while the health is low, the avatar is bleeding or down, and for HURT_HOLD_CALM_S after a blow, then it is gone (`Access.calm_flashes()`, scripts/access.gd). (Otherwise the peak is
## limited by the 0.88 alpha cap in the shader, and the rate by the above.)
##
## IT NEVER WRITES THE RULES: it reads `sim.avatar.player()` (health, bleeding, down) each frame and keeps the last health it saw.
## STAGING (a screenshot has no fight): `--hurt=0.3` puts the avatar at that fraction of the health from the start; `--hurt=0.3,bite` also has a bite land a few frames before the
## screenshot (the health drops 12, as a bite's does, and the thump plays), so the shot shows the moment of a blow on a low health.
extends RefCounted

const Prefs := preload("res://scripts/prefs.gd")
const Access := preload("res://scripts/access.gd")
const SHADER := preload("res://scripts/ui/hurt_pulse.gdshader")

## The fraction of the health under which the edge stays up.
const LOW_AT := 0.30
## A health drop smaller than this (a bleed's few thousandths a step) is not a blow.
const BLOW_MIN := 0.4
## Seconds for a blow's edge to fall away; the least gap between two thumps (real seconds); how long a blow's still edge is held under reduce motion.
const HIT_FALL_S := 0.85
const THUMP_GAP_S := 0.35
const HURT_HOLD_CALM_S := 1.5
## How strong the steady edge is at the start of low health, at no health, while bleeding, and down.
## How strong the edge is at the moment of the worst blow (it then falls as the square of what is left of the blow, over HIT_FALL_S).
const BLOW_PEAK := 0.78
const LOW_EDGE_MIN := 0.16
const LOW_EDGE_MAX := 0.42
const BLEED_EDGE := 0.11
const DOWN_EDGE := 0.5
## The heartbeat: the pair's period (seconds) at the start of low health and at none; where the two beats sit in it (seconds) and how wide they are; how much it adds.
const BEAT_PERIOD_SLOW := 1.55
const BEAT_PERIOD_FAST := 0.95
const BEAT_AT := [0.10, 0.34]
const BEAT_WIDTH := [0.06, 0.075]
const BEAT_GAIN := [1.0, 0.65]
const BEAT_ADD_MIN := 0.09
const BEAT_ADD_MAX := 0.24

var main
var hud
var rect: ColorRect
var mat: ShaderMaterial
## What is drawn now (0 to 1), the last blow's strength (falling to 0), the health fraction seen last frame (-1: none yet).
var level := 0.0
var hit := 0.0
var last_hp := -1.0
## The CPU time of this part, microseconds, for `--hudb-cost` (see crew_marks.gd's `report`).
var cost_us := 0.0
var cost_frames := 0

var _phase := 0.0
var _frames := 0
var _calm_hold := 0.0
var _thump_cd := 0.0
var _set_level := -1.0
var _stage_hp := -1.0
var _stage_bite := false
var _stage_done := false


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("intensity", 0.0)
	rect = ColorRect.new()
	rect.name = "HurtPulse"
	rect.color = Color.WHITE
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.visible = false
	hud.add_child(rect)
	# (over the world and the marks drawn on the HUD's own layer, under the HUD's boards: a panel is never red)
	hud.move_child(rect, 0)
	_read_flags()


## `--hurt=F[,bite]` (see the header).
func _read_flags() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if not a.begins_with("--hurt="):
			continue
		var bits := a.trim_prefix("--hurt=").split(",")
		if bits.size() > 0 and bits[0].is_valid_float():
			_stage_hp = clampf(float(bits[0]), 0.0, 1.0)
		_stage_bite = bits.has("bite")


func _sim():
	return main.get("sim") if main != null else null


func _me():
	var sim = _sim()
	if sim == null or sim.get("avatar") == null or String(sim.get("player_id")) == "":
		return null
	return sim.avatar.player()


func on_frame(dt: float) -> void:
	if rect == null:
		return
	var t0 := Time.get_ticks_usec()
	_frame(dt)
	cost_us += float(Time.get_ticks_usec() - t0)
	cost_frames += 1


func _frame(dt: float) -> void:
	var me = _me()
	if me == null:
		_show(0.0)
		return
	_frames += 1
	# (the staged health is put a few frames in, after `--stage=` has made its run: a screenshot has no fight)
	if _stage_hp >= 0.0 and _frames == 3:
		me.hp = _stage_hp * 100.0
		last_hp = _stage_hp    # (not a blow)
	_stage_a_bite(me)
	var f := clampf(float(me.hp) / 100.0, 0.0, 1.0)
	if last_hp < 0.0:
		last_hp = f
	var drop := (last_hp - f) * 100.0
	last_hp = f
	if drop > BLOW_MIN:
		_blow(drop)
	var calm := Access.calm_flashes()    # (Reduce flashes, or the older Reduce motion)
	_thump_cd = maxf(0.0, _thump_cd - dt)
	hit = maxf(0.0, hit - dt / HIT_FALL_S)
	_calm_hold = maxf(0.0, _calm_hold - dt)
	level = compute(f, bool(me.downed) and not bool(me.dead), float(me.bleeding) > 0.0 and not bool(me.dead), calm, dt)
	if _asleep():
		level = 0.0
	_show(level)


## The strength of the edge now (0 to 1), from the health fraction, whether the avatar is down or bleeding, and the setting. Moves the heartbeat's clock by `dt`.
func compute(f: float, down: bool, bleeding: bool, calm: bool, dt: float) -> float:
	var severity := clampf((LOW_AT - f) / LOW_AT, 0.0, 1.0)
	var low := f <= LOW_AT + 0.0005
	var base := 0.0
	if low:
		base = lerpf(LOW_EDGE_MIN, LOW_EDGE_MAX, severity)
	if bleeding:
		base = maxf(base, BLEED_EDGE)
	if down:
		base = maxf(base, DOWN_EDGE)
	var out := base
	if calm:
		# (still: a faint edge while it is true, and a held one just after a blow; nothing falls, nothing beats)
		if _calm_hold > 0.0:
			out = maxf(out, 0.3)
		return clampf(out, 0.0, 1.0)
	if base > 0.0 and not down:
		var sev := maxf(severity, 0.0)
		var period := lerpf(BEAT_PERIOD_SLOW, BEAT_PERIOD_FAST, sev) if low else (BEAT_PERIOD_SLOW * 1.4)
		_phase = fposmod(_phase + dt / period, 1.0)
		var ts := _phase * period
		var beat := 0.0
		for i in 2:
			var x: float = (ts - float(BEAT_AT[i])) / float(BEAT_WIDTH[i])
			beat += float(BEAT_GAIN[i]) * exp(-x * x)
		out += beat * (lerpf(BEAT_ADD_MIN, BEAT_ADD_MAX, sev) if low else 0.05)
	return clampf(maxf(out, hit * hit * BLOW_PEAK), 0.0, 1.0)


## The avatar lost `amount` health in one frame: the edge jumps, the thump plays.
func _blow(amount: float) -> void:
	hit = maxf(hit, clampf(0.5 + amount / 24.0, 0.5, 1.0))
	_calm_hold = HURT_HOLD_CALM_S
	if _thump_cd > 0.0:
		return
	_thump_cd = THUMP_GAP_S
	var sound = main.get("sound")
	if sound != null and sound.has_method("play"):
		# (the game's thud, pitched down to a body blow: `sound.play(name, level, pitch wobble, pitch)`)
		sound.play("thud", 0.55 + 0.35 * hit, 0.04, 0.62)


func _show(v: float) -> void:
	if v < 0.004:
		if rect.visible:
			rect.visible = false
		_set_level = -1.0
		return
	if not rect.visible:
		rect.visible = true
	if absf(v - _set_level) > 0.003:
		_set_level = v
		mat.set_shader_parameter("intensity", v)


func _asleep() -> bool:
	var sim = _sim()
	var sl = sim.get("sleep") if sim != null else null
	return sl != null and sl.has_method("active") and bool(sl.active())


## `--hurt=F,bite`: a bite lands (the health drops 12) a few frames before the screenshot's.
func _stage_a_bite(me) -> void:
	if not _stage_bite or _stage_done or main.get("shot_path") == "" or main.get("shot_path") == null:
		return
	if int(main.get("frame_count")) >= int(main.get("shot_frames")) - 5:
		_stage_done = true
		me.hp = maxf(1.0, float(me.hp) - 12.0)
