## Additive glows drawn above the night: flames, lanterns, floodlight lenses,
## lamps, plus sparks, embers, tracers and muzzle flashes. Lives on a
## CanvasLayer that follows the camera but is not darkened by the sky.
extends Node2D

const TILE := 64.0

var fx
var radial: Texture2D
var fires: Array = []
var lanterns: Array = []
var floods: Array = []
var lamps: Array = []
var lighting
var t := 0.0


func setup(data: Dictionary, effects, light_rig, radial_tex: Texture2D) -> void:
	fx = effects
	lighting = light_rig
	radial = radial_tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	for l in data.lights:
		if l.get("fire", false):
			fires.append(l)
		elif l.get("lantern", false):
			lanterns.append(l)
		elif l.get("flood", false):
			floods.append(l)
		elif l.get("lamp", false):
			lamps.append(l)


func _glow(x: float, y: float, r: float, c: Color, a: float) -> void:
	if a <= 0.001:
		return
	c.a = a
	draw_texture_rect(radial, Rect2(x - r, y - r, r * 2.0, r * 2.0), false, c)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	var dark: float = lighting.dark
	if dark > 0.02:
		var lamp: float = lighting.lamp_level
		var k := minf(1.0, dark * 1.6)
		for f in fires:
			_glow(f.x, f.y - 0.3, 3.0 if f.get("big", false) else 1.4, Color8(255, 150, 60), 0.32 * k * (0.85 + 0.15 * sin(t * 17.0 + float(f.x))))
		for l in lanterns:
			_glow(l.x, l.y, 0.7, Color8(255, 200, 120), 0.5 * lamp)
		var floods_on: bool = lighting.floods_on
		for l in floods:
			_glow(l.x, l.y, 0.6, Color8(230, 238, 255), 0.4 * (lamp if floods_on else 0.0))
		for l in lamps:
			_glow(l.x, l.y, 0.6, Color8(255, 230, 180), 0.35 * lamp)
	fx.draw_add(self)
