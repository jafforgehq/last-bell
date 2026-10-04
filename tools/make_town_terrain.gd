## Makes the extra ground pictures of the generated town (One House, TOWNGEN): the wall materials of the art kit as terrain atlases (assets/terrain/wall_white.png, wall_blue.png,
## wall_stucco.png, wall_timber.png: 512 x 512, 4 x 4 pieces of 128 px, the kit's wall fill `a` with its `b` variant now and then) and a pond's water (water.png). The terrain
## ids and names are scripts/town/town_districts.gd `TERRAINS`.
##
##   godot --headless --path <project> --script tools/make_town_terrain.gd
##
## then `godot --headless --path <project> --import` once so that the pictures get their .import files.
extends SceneTree

const KIT := "res://assets/town/house/"
const OUT := "res://assets/terrain/"
const PIECE := 128


func _init() -> void:
	for name in ["white", "blue", "stucco", "timber"]:
		_wall(name)
	_water()
	quit()


func _wall(name: String) -> void:
	var a := Image.load_from_file(KIT + "wall_%s_a.png" % name)
	var b := Image.load_from_file(KIT + "wall_%s_b.png" % name)
	if a == null or b == null:
		push_error("no kit wall " + name)
		return
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var atlas := Image.create(PIECE * 4, PIECE * 4, false, Image.FORMAT_RGBA8)
	for j in 4:
		for i in 4:
			# the `b` variant (a vent, a stain) in two pieces of sixteen
			var use_b := (i == 1 and j == 2) or (i == 3 and j == 0)
			var src: Image = b if use_b else a
			atlas.blit_rect(src, Rect2i(0, 0, PIECE, PIECE), Vector2i(i * PIECE, j * PIECE))
	atlas.save_png(OUT + "wall_%s.png" % name)
	print("wrote wall_%s.png" % name)


## Water: a seamless noise (the atlas wraps, and so does the noise) in blue greens, with paler ripples.
func _water() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_octaves = 3
	noise.seed = 11
	var field: Image = noise.get_seamless_image(PIECE * 4, PIECE * 4, false, false, 0.15, true)
	field.convert(Image.FORMAT_RF)
	var ripple := FastNoiseLite.new()
	ripple.noise_type = FastNoiseLite.TYPE_PERLIN
	ripple.frequency = 0.06
	ripple.seed = 5
	var rip: Image = ripple.get_seamless_image(PIECE * 4, PIECE * 4, false, false, 0.15, true)
	rip.convert(Image.FORMAT_RF)
	var out := Image.create(PIECE * 4, PIECE * 4, false, Image.FORMAT_RGBA8)
	var deep := Color("2f5a78")
	var light := Color("4f86a2")
	for y in PIECE * 4:
		for x in PIECE * 4:
			var v: float = field.get_pixel(x, y).r
			var c := deep.lerp(light, clampf(v * 1.2, 0.0, 1.0))
			var r: float = rip.get_pixel(x, y).r
			if r > 0.78:
				c = c.lightened(0.18 * (r - 0.78) / 0.22 + 0.04)
			out.set_pixel(x, y, c)
	out.save_png(OUT + "water.png")
	print("wrote water.png")
