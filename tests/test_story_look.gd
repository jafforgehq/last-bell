extends "res://tests/case.gd"
## The night as the storyteller's cards change it (scripts/render/lighting.gd): a blackout takes the
## lamps, the lanterns and the floodlights (the fire barrels burn on) and cools and darkens the sky; a
## fog puts a soft veil over the yard and makes every light shorter and weaker; both ease in and out
## (and switch at once under reduced motion); with no look given the night is as it always was.

const Helpers := preload("res://tests/helpers.gd")
const Lighting := preload("res://scripts/render/lighting.gd")
const Prefs := preload("res://scripts/prefs.gd")


## A lighting rig over the game's lights (built once: its light textures take a moment to make).
var _rig: Dictionary = {}


func _make() -> Dictionary:
	var data := Helpers.make(1, 1)
	var holder := Node2D.new()
	Engine.get_main_loop().root.add_child(holder)
	var cm := CanvasModulate.new()
	holder.add_child(cm)
	var rig := Lighting.new()
	holder.add_child(rig)
	rig.setup(data.data, cm)
	return {"rig": rig, "holder": holder, "game": data, "cm": cm}


func _free(ctx: Dictionary) -> void:
	ctx.holder.free()
	ctx.game.world.free()


## Updates the rig `seconds` of real time at 20 frames a second.
func _play(rig, hour: float, seconds: float, look: Dictionary, t0: float = 0.0) -> float:
	var t := t0
	for i in int(seconds * 20.0):
		t += 0.05
		rig.update(hour, true, t, [], look)
	return t


func _lamps(rig) -> Array:
	var out: Array = []
	for l in rig.lights:
		if l.def.get("lamp", false) or l.def.get("lantern", false):
			out.append(l)
	return out


func _floods(rig) -> Array:
	var out: Array = []
	for l in rig.lights:
		if l.def.get("flood", false):
			out.append(l)
	return out


func _fires(rig) -> Array:
	var out: Array = []
	for l in rig.lights:
		if l.def.get("fire", false):
			out.append(l)
	return out


func test_a_plain_night_is_as_it_always_was() -> void:
	var ctx := _make()
	var rig = ctx.rig
	rig.update(22.0, true, 1.0, [])
	check(rig.lamp_level > 0.99, "the lamps are on: %.2f" % rig.lamp_level)
	check(rig.floods_on, "and the floodlights")
	eq(rig.fog, 0.0, "no fog")
	eq(rig.power, 1.0, "full power")
	check(not rig.veil.visible, "no veil")
	for l in _lamps(rig) + _floods(rig) + _fires(rig):
		check(l.node.visible and l.node.energy > 0.05, "every light is lit")
	_free(ctx)


func test_a_blackout_puts_out_the_lamps_and_the_floodlights_and_leaves_the_fires() -> void:
	var ctx := _make()
	var rig = ctx.rig
	rig.update(22.0, true, 1.0, [])
	var plain: Color = ctx.cm.color
	var t := _play(rig, 22.0, 2.0, {"blackout": true}, 1.0)
	check(rig.power < 0.01, "the power is gone: %.2f" % rig.power)
	check(rig.lamp_level < 0.01, "so the lamp level is nothing")
	for l in _lamps(rig) + _floods(rig):
		check(not l.node.visible, "a lamp, a lantern or a floodlight is out: %s" % str(l.def))
	for l in _fires(rig):
		check(l.node.visible and l.node.energy > 0.05, "a fire barrel burns on")
	var dark: Color = ctx.cm.color
	check(dark.r < plain.r and dark.g < plain.g and dark.b <= plain.b + 0.001, "the sky is darker: %s against %s" % [str(dark), str(plain)])
	check(dark.b / maxf(dark.r, 0.001) > plain.b / maxf(plain.r, 0.001), "and cooler (bluer): %.2f against %.2f" % [dark.b / dark.r, plain.b / plain.r])
	# the power comes back
	_play(rig, 22.0, 2.0, {"blackout": false}, t)
	check(rig.power > 0.99, "the lamps are back on: %.2f" % rig.power)
	check(_lamps(rig)[0].node.visible, "and lit")
	check(absf(ctx.cm.color.r - plain.r) < 0.01, "and the sky is as before")
	_free(ctx)


func test_the_lamps_go_out_over_a_second_not_at_once() -> void:
	var ctx := _make()
	var rig = ctx.rig
	rig.update(22.0, true, 1.0, [])
	rig.update(22.0, true, 1.1, [], {"blackout": true})
	check(rig.power > 0.5 and rig.power < 1.0, "a tenth of a second later they are still on, dimmer: %.2f" % rig.power)
	_play(rig, 22.0, 1.0, {"blackout": true}, 1.1)
	check(rig.power < 0.05, "a second on they are out: %.2f" % rig.power)
	_free(ctx)


func test_under_reduced_motion_the_blackout_is_at_once() -> void:
	Prefs.set_value("ui", "reduce_motion", true)
	var ctx := _make()
	var rig = ctx.rig
	rig.update(22.0, true, 1.0, [])
	rig.update(22.0, true, 1.05, [], {"blackout": true})
	eq(rig.power, 0.0, "the power is gone in one frame")
	rig.update(22.0, true, 1.1, [], {"fog": 1.0})
	eq(rig.fog, 1.0, "and the fog is whole in one frame")
	Prefs.set_value("ui", "reduce_motion", false)
	_free(ctx)


func test_a_fog_veils_the_yard_and_shortens_every_light() -> void:
	var ctx := _make()
	var rig = ctx.rig
	rig.update(22.0, true, 1.0, [])
	var reach := {}
	var energy := {}
	for l in rig.lights:
		reach[l.node] = l.node.texture_scale
		energy[l.node] = l.node.energy if float(l.def.get("flicker", 0.0)) == 0.0 else 0.0
	_play(rig, 22.0, 4.0, {"fog": 1.0}, 1.0)
	check(rig.fog > 0.99, "the fog is thick: %.2f" % rig.fog)
	check(rig.veil.visible, "the veil is up")
	var density: float = rig._veil_material.get_shader_parameter("density")
	check(density > 0.4 and density < 1.0, "a soft one: %.2f" % density)
	for l in rig.lights:
		if l.node.visible:
			check(l.node.texture_scale < reach[l.node] - 0.0001, "a light reaches less far in the fog")
			check(energy[l.node] < 0.05 or l.node.energy < energy[l.node] - 0.0001, "and shines less")
	# it thins again
	_play(rig, 22.0, 4.0, {"fog": 0.0}, 5.0)
	check(rig.fog < 0.01 and not rig.veil.visible, "gone when the card says so")
	for l in rig.lights:
		if l.node.visible:
			check(absf(l.node.texture_scale - reach[l.node]) < 0.0001, "and the lights are as long as before")
	_free(ctx)


func test_a_fog_by_day_shows_and_thickens_with_the_look() -> void:
	var ctx := _make()
	var rig = ctx.rig
	_play(rig, 14.0, 4.0, {"fog": 0.4}, 0.0)
	check(rig.veil.visible, "by day the veil shows")
	near(rig.fog, 0.4, 0.001, "as thick as the card's hour makes it")
	check(ctx.cm.color.r > 0.9, "and the day is still bright: %s" % str(ctx.cm.color))
	_free(ctx)


func test_the_veil_drifts_unless_motion_is_reduced() -> void:
	var ctx := _make()
	var rig = ctx.rig
	_play(rig, 22.0, 1.0, {"fog": 1.0}, 0.0)
	var a: float = rig._veil_material.get_shader_parameter("drift")
	_play(rig, 22.0, 1.0, {"fog": 1.0}, 1.0)
	var b: float = rig._veil_material.get_shader_parameter("drift")
	check(b > a, "it drifts: %.2f then %.2f" % [a, b])
	Prefs.set_value("ui", "reduce_motion", true)
	_play(rig, 22.0, 1.0, {"fog": 1.0}, 2.0)
	var c: float = rig._veil_material.get_shader_parameter("drift")
	eq(c, b, "and stands still when motion is reduced")
	Prefs.set_value("ui", "reduce_motion", false)
	_free(ctx)


func test_a_blackout_in_a_fog_is_both() -> void:
	var ctx := _make()
	var rig = ctx.rig
	_play(rig, 22.0, 4.0, {"fog": 1.0, "blackout": true}, 0.0)
	check(rig.fog > 0.99 and rig.power < 0.01, "thick fog and no power")
	check(rig.veil.visible, "the veil is up")
	for l in _lamps(rig) + _floods(rig):
		check(not l.node.visible, "the lamps are out")
	_free(ctx)


func test_the_storyteller_says_what_to_draw() -> void:
	var g := Helpers.make(3, 1)
	var sim = g.sim
	sim.storyteller.enabled = true
	var look: Dictionary = sim.storyteller.look()
	eq(look, {"fog": 0.0, "rain": false, "snow": false, "blackout": false}, "a clear day is plain")
	sim.weather = "fog"
	sim.minutes = 12.0 * 60.0
	sim.phase = "day"
	near(float(sim.storyteller.look().fog), 0.35, 0.001, "a fog at noon is a thin one")
	sim.minutes = 17.0 * 60.0
	near(float(sim.storyteller.look().fog), 0.35 + 0.65 * 5.0 / 7.0, 0.001, "thicker by five")
	sim.minutes = 21.0 * 60.0
	sim.phase = "night"
	eq(float(sim.storyteller.look().fog), 1.0, "and thick by night")
	sim.storyteller.blackout = {"state": "pending", "at": 0.0, "send": false, "fixer": "", "work": 0.0}
	eq(sim.storyteller.look().blackout, false, "a blackout that has not come is not drawn")
	sim.storyteller.blackout["state"] = "dark"
	eq(sim.storyteller.look().blackout, true, "one that has is")
	sim.storyteller.enabled = false
	eq(sim.storyteller.look(), {"fog": 0.0, "rain": false, "snow": false, "blackout": false}, "and with the storyteller off nothing is")
	g.world.free()
