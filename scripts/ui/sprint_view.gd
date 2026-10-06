## The BREATH of the run (One House, PACE): a thin arc under the avatar that shows how much of a sprint she has left (scripts/sim/sprint.gd), drawn only while she runs and while the breath comes back, and gone
## a moment after it is full. A VIEW PART of the town's facade (`on_ready(main)`, `on_frame(dt)`). It reads `sim.avatar.sprint` (`shown()`, `stamina`, `winded`, `active`) and writes nothing.
##
## THE LOOK. A dark track, the lower part of a circle round her body that passes under her name (a little over a third of a turn either side of straight down), and on it the breath that is left, filling from the left: the HUD's accent while it is good, the
## amber of its warnings under a third or while she is winded (a run that ran the tank dry and waits for the key to be let go and the breath to come back to 15 percent: a short tick marks where a run may begin again).
## Colour-blind markers are not needed (the length is the information; the colour only adds). With "Reduce motion" the arc has no fade.
extends RefCounted

const FADE_IN_S := 0.12
const FADE_OUT_S := 0.45
## The arc: from this angle to this one, radians from east, clockwise on the screen (a quarter of a turn either side of straight down, a little less).
const FROM := 0.15 * PI
const TO := 0.85 * PI
const TRACK_PX := 5.0
const FILL_PX := 3.0
const MIN_R := 15.0

var main
var hud
var layer: Control
var _a := 0.0


func on_ready(main_node) -> void:
	main = main_node
	hud = main.get("hud")
	if hud == null:
		return
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.draw.connect(_draw)
	hud.add_child(layer)
	# (under the HUD's own boards, over the world)
	hud.move_child(layer, 0)


func _sprint():
	var sim = main.get("sim") if main != null else null
	if sim == null or sim.get("avatar") == null or sim.avatar.get("sprint") == null:
		return null
	return sim.avatar.sprint


func on_frame(dt: float) -> void:
	if layer == null:
		return
	var sp = _sprint()
	var want := 1.0 if sp != null and sp.shown() and sim_has_player() else 0.0
	var calm: bool = hud.has_method("_calm") and bool(hud._calm())
	if calm:
		_a = want
	elif want > _a:
		_a = minf(want, _a + dt / FADE_IN_S)
	else:
		_a = maxf(want, _a - dt / FADE_OUT_S)
	if _a > 0.0 or want > 0.0:
		layer.queue_redraw()


func sim_has_player() -> bool:
	var sim = main.get("sim")
	return sim != null and sim.avatar.player() != null


func _feet() -> Vector2:
	var me = main.get("sim").avatar.player()
	var at := Vector2(me.x, me.y)
	if main.has_method("view_pos"):
		at = main.view_pos(me)
	var cam: Vector2 = main.get("cam_center") if main.get("cam_center") is Vector2 else Vector2.ZERO
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	return (at - cam) * z + layer.size * 0.5


func _draw() -> void:
	var sp = _sprint()
	if sp == null or _a <= 0.01 or not sim_has_player():
		return
	var z: float = float(main.get("zoom_px")) if main.get("zoom_px") != null else 32.0
	# (centred on her body and wide enough to pass under her name tag: the session's ring (scripts/ui/town_hud.gd) is the smaller circle round the body)
	var r := maxf(MIN_R, 0.92 * z)
	var feet := _feet() + Vector2(0.0, -0.45 * z)
	var low: bool = bool(sp.winded) or float(sp.stamina) < 0.34
	var col: Color = hud.WARN if low else hud.ACCENT
	layer.draw_arc(feet, r, FROM, TO, 24, Color(0.04, 0.08, 0.07, 0.72 * _a), TRACK_PX, true)
	var frac := clampf(float(sp.stamina), 0.0, 1.0)
	if frac > 0.004:
		layer.draw_arc(feet, r, FROM, FROM + (TO - FROM) * frac, 24, Color(col, _a), FILL_PX, true)
	if bool(sp.winded):
		# (the tick where a run may begin again)
		var a := FROM + (TO - FROM) * float(sp.MIN_START)
		var d := Vector2.from_angle(a)
		layer.draw_line(feet + d * (r - 4.5), feet + d * (r + 4.5), Color(hud.INK, 0.85 * _a), 1.5, true)
