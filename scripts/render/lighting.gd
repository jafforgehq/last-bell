## Day and night. A CanvasModulate carries the sky colour; every lamp, fire
## barrel, lantern and floodlight is a PointLight2D whose texture has its
## falloff, cone and room clipping baked in (like the web version's light map).
extends Node2D

const TILE := 64.0
const SKY := [
	[0.0, Color8(68, 76, 116)],
	[4.8, Color8(68, 76, 116)],
	[5.6, Color8(150, 124, 150)],
	[6.4, Color8(236, 212, 198)],
	[7.2, Color8(255, 252, 246)],
	[17.6, Color8(255, 250, 240)],
	[18.4, Color8(252, 214, 172)],
	[19.0, Color8(232, 176, 146)],
	[19.6, Color8(168, 132, 148)],
	[20.3, Color8(100, 102, 142)],
	[21.0, Color8(70, 78, 118)],
	[24.0, Color8(68, 76, 116)],
]
const FLASH_POOL := 10

var modulate_node: CanvasModulate
var lights: Array = [] # {def, node}
var flash_nodes: Array = []
var flash_tex: Texture2D
var dark := 0.0
var lamp_level := 0.0
var floods_on := false


static func sky_at(hour: float) -> Color:
	for i in range(1, SKY.size()):
		if hour <= SKY[i][0]:
			var h0: float = SKY[i - 1][0]
			var h1: float = SKY[i][0]
			var c0: Color = SKY[i - 1][1]
			return c0.lerp(SKY[i][1], (hour - h0) / (h1 - h0))
	return SKY[0][1]


func setup(data: Dictionary, canvas_modulate: CanvasModulate) -> void:
	modulate_node = canvas_modulate
	for def in data.lights:
		var node := PointLight2D.new()
		var size := 256 if float(def.r) > 8.0 else 128
		node.texture = _light_texture(def, size)
		node.texture_scale = float(def.r) * 2.0 * TILE / size
		node.position = Vector2(def.x, def.y) * TILE
		node.color = Color8(int(def.color[0]), int(def.color[1]), int(def.color[2]))
		node.blend_mode = Light2D.BLEND_MODE_ADD
		node.energy = 0.0
		node.visible = false
		add_child(node)
		lights.append({"def": def, "node": node})
	flash_tex = _light_texture({"x": 0.0, "y": 0.0, "r": 1.0}, 64)
	for i in FLASH_POOL:
		var f := PointLight2D.new()
		f.texture = flash_tex
		f.color = Color8(255, 214, 150)
		f.blend_mode = Light2D.BLEND_MODE_ADD
		f.visible = false
		add_child(f)
		flash_nodes.append(f)


## Falloff stops match the web version: 0 -> 1, 0.3 -> 0.72, 0.65 -> 0.28, 1 -> 0.
static func _falloff(k: float) -> float:
	if k >= 1.0:
		return 0.0
	if k < 0.3:
		return lerpf(1.0, 0.72, k / 0.3)
	if k < 0.65:
		return lerpf(0.72, 0.28, (k - 0.3) / 0.35)
	return lerpf(0.28, 0.0, (k - 0.65) / 0.35)


static func _light_texture(def: Dictionary, size: int) -> Texture2D:
	var r: float = def.r
	var cx: float = def.x
	var cy: float = def.y
	var clip = def.get("clip")
	var cone = def.get("cone")
	var spread: float = def.get("spread", 0.0)
	var bytes := PackedByteArray()
	bytes.resize(size * size * 4)
	var i := 0
	for v in size:
		for u in size:
			var dx := ((u + 0.5) / size * 2.0 - 1.0) * r
			var dy := ((v + 0.5) / size * 2.0 - 1.0) * r
			var dist := sqrt(dx * dx + dy * dy)
			var a := 0.0
			if cone != null:
				var ang := atan2(dy, dx)
				var diff := absf(atan2(sin(ang - cone), cos(ang - cone)))
				# soft beam edges so the cone does not step at close zoom
				a = _falloff(dist / r) * smoothstep(spread + 0.05, spread - 0.05, diff)
				a += maxf(0.0, 1.0 - dist / 2.2) * 0.5
			else:
				a = _falloff(dist / r)
			if clip != null:
				var wx := cx + dx
				var wy := cy + dy
				var outside := maxf(maxf(clip[0] - wx, wx - clip[2]), maxf(clip[1] - wy, wy - clip[3]))
				a *= clampf(1.0 - (outside + 0.06) / 0.12, 0.0, 1.0)
			bytes[i] = 255
			bytes[i + 1] = 255
			bytes[i + 2] = 255
			bytes[i + 3] = int(clampf(a, 0.0, 1.0) * 255.0)
			i += 4
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)
	return ImageTexture.create_from_image(img)


func update(hour: float, bell_rung: bool, t: float, flashes: Array) -> void:
	var sky := sky_at(hour)
	dark = 1.0 - (sky.r + sky.g + sky.b) / 3.0
	lamp_level = clampf((dark - 0.08) * 4.0, 0.0, 1.0)
	if dark <= 0.02:
		modulate_node.color = Color.WHITE
		for l in lights:
			l.node.visible = false
		for f in flash_nodes:
			f.visible = false
		return
	modulate_node.color = sky
	floods_on = bell_rung or hour >= 20.0 or hour < 6.0
	for l in lights:
		var def: Dictionary = l.def
		var level := 1.0
		if def.get("fire", false):
			level = 1.0
		elif def.get("flood", false):
			level = lamp_level if floods_on else 0.0
		else:
			level = lamp_level
		var f := 1.0
		var k: float = def.get("flicker", 0.0)
		if k > 0.0:
			f = 1.0 - 0.1 * k * (0.5 + 0.5 * sin(t * 13.7 + float(def.x) * 3.1)) - 0.06 * k * sin(t * 23.3 + float(def.y))
		var energy: float = minf(1.0, float(def.get("i", 1.0)) * level * f)
		l.node.energy = energy
		l.node.visible = energy > 0.01
	for i in flash_nodes.size():
		var node: PointLight2D = flash_nodes[i]
		if i < flashes.size():
			var fl: Dictionary = flashes[i]
			node.position = Vector2(fl.x, fl.y) * TILE
			node.texture_scale = float(fl.r) * 2.0 * TILE / 64.0
			node.energy = 1.0
			node.visible = true
		else:
			node.visible = false
