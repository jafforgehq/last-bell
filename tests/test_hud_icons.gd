extends "res://tests/case.gd"

const GD := preload("res://scripts/game_data.gd")

## The icons the HUD uses for needs, wounds and trips (tools/make_icons.gd).
const ROUND_ONE := ["hungry", "thirsty", "starving", "wound", "fever", "down", "resting", "away", "scavenge", "treat", "sendout", "turned"]


func test_every_registered_icon_loads_as_a_64_pixel_square() -> void:
	var data := GD.load_all()
	for key in data.icons:
		var tex: Texture2D = GD.tex(data.icons[key])
		check(tex != null, "%s loads" % key)
		if tex != null:
			eq(tex.get_size(), Vector2(64, 64), "%s is 64x64" % key)


func test_the_round_one_icons_are_registered_and_drawn() -> void:
	var data := GD.load_all()
	for key in ROUND_ONE:
		check(data.icons.has(key), "%s is registered in map.json" % key)
		if not data.icons.has(key):
			continue
		var img: Image = GD.tex(data.icons[key]).get_image()
		var opaque := 0
		var tinted := 0
		for y in 64:
			for x in 64:
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					opaque += 1
				# like the older icons: white, tinted by the HUD with modulate
				if c.a > 0.02 and (c.r < 0.98 or c.g < 0.98 or c.b < 0.98):
					tinted += 1
		check(opaque > 300 and opaque < 2400, "%s has a sensible amount of ink (%d px)" % [key, opaque])
		eq(tinted, 0, "%s is pure white with alpha" % key)
