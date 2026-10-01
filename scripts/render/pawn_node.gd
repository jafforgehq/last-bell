## One person or one of the dead on the map. Its position is the character's feet,
## so a y-sorted parent puts whoever stands further south in front. Draws the baked
## body sprite plus live legs, arms and weapon, the way the web version did. The
## dead come in kinds (walker, runner, brute): the same figure scaled, leaned and
## tinted by pawn_art.gd's STYLES, so a kind reads at a glance; a walker is drawn
## exactly as ever.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/render/pawn_art.gd")
const S := preload("res://scripts/render/shapes.gd")
const TILE := GD.TILE
## How the dead are dimmed (a person who died lies where they fell).
const DEAD_TINT := Color(0.62, 0.6, 0.6)
const PIVOT := {"S": Vector2(-0.04, -0.08), "E": Vector2(0.08, -0.14), "N": Vector2(0.26, -0.22)}
## A jump of more than this many tiles between two steps (back from a trip, a
## walker risen where a survivor fell) is a jump, not a walk: no sliding.
const SNAP_TILES := 3.0

var entity # Sim.Person or Sim.Zombie
var zombie := false
## How a zombie is drawn: its kind when pawn_art.gd has a build for it, else "walker".
var kind := "walker"
var tex := {} # view -> Texture2D
var pawn_rect: Rect2
var weapon_tex: Texture2D
var weapon_rect: Rect2
var gun_front = null
var anim_t := 0.0
var pal: Dictionary
var beds: Array = [] # the cots and mattresses of the map, to find the blanket colour
var _bed_key := ""
var _bed_col := Color("#9a9070")
var _m := Transform2D.IDENTITY
## Where the rules had the character at their last two steps, in tiles: they
## move once per step, and the node is drawn between the two (see sync).
var _prev := Vector2.ZERO
var _cur := Vector2.ZERO
var _steps_seen := -1
var _frame_seen := 0
var _style: Dictionary = Art.WALKER
var _meshes := {} # view -> the warped sprite of this kind, or null for the plain one
## Where the drawing goes: this node, or a stand-in that records the calls (tests).
var _pen = self


func setup(e, is_zombie: bool, data: Dictionary, key: String) -> void:
	entity = e
	zombie = is_zombie
	var box: Array = data.pawn.box
	pawn_rect = Rect2(box[0], box[1], box[2] - box[0], box[3] - box[1])
	for v in ["S", "E", "N"]:
		tex[v] = GD.tex(data.pawn.files[key][v])
	pal = Art.palette(e.look)
	if zombie:
		kind = Art.kind_of(e)
		_style = Art.style(kind)
		var tinted := Art.material(kind)
		if tinted != null:
			material = tinted
	if not zombie:
		var wb: Array = data.weaponArt.box
		weapon_rect = Rect2(wb[0], wb[1], wb[2] - wb[0], wb[3] - wb[1])
		weapon_tex = GD.tex(data.weaponArt.files[e.weapon])
		gun_front = data.guns[e.weapon].front
		for o in data.objects:
			if o.kind == "cot" or o.kind == "mattress":
				beds.append(o)
	sync()


## `steps` is how many steps the rules have taken, `alpha` how far the time has
## run into the next one: the node is drawn that far from where the character
## stood one step ago to where they stand now, so a 144 Hz screen shows smooth
## walking though the rules move 30 times a second. Called without them it is
## drawn where the character is, as it is on a first look, when the node was out
## of sight a frame ago, and after a jump of more than SNAP_TILES.
func sync(redraw: bool = true, steps: int = -1, alpha: float = 1.0) -> void:
	var now := Vector2(entity.x, entity.y)
	var frame := Engine.get_process_frames()
	if _steps_seen < 0 or frame - _frame_seen > 1 or now.distance_to(_cur) > SNAP_TILES:
		_prev = now
		_cur = now
	elif steps != _steps_seen:
		_prev = _cur
		_cur = now
	_steps_seen = steps
	_frame_seen = frame
	position = _prev.lerp(_cur, alpha) * TILE
	var tint := DEAD_TINT if (not zombie and entity.dead) else Color.WHITE
	if modulate != tint:
		modulate = tint
	if redraw:
		queue_redraw()


## Where the node is drawn, in tiles: the overlay's brackets and names go here.
func tile_pos() -> Vector2:
	return position / TILE


# a tiny canvas-context emulation: translate / rotate / scale in local units
func _reset() -> void:
	_m = Transform2D.IDENTITY.scaled(Vector2(TILE, TILE))


func _tr(x: float, y: float) -> void:
	_m = _m.translated_local(Vector2(x, y))


func _rot(a: float) -> void:
	_m = _m.rotated_local(a)


func _sc(x: float, y: float) -> void:
	_m = _m.scaled_local(Vector2(x, y))


func _apply() -> void:
	_pen.draw_set_transform_matrix(_m)


## Scales the figure about its feet (what is drawn after grows from the ground up).
func _fit_figure(fs: Vector2) -> void:
	_tr(0, Art.FOOT_Y)
	_sc(fs.x, fs.y)
	_tr(0, -Art.FOOT_Y)


## How the body leans into its stride: from the hips toward where it faces in side
## view (a shear, so the hem stays level and the head goes forward), and shorter on
## its feet facing the player (it comes toward them).
func _lean(view: String) -> void:
	var lean: float = _style.lean
	if lean == 0.0:
		return
	if view == "E":
		var k := tan(lean)
		_m = _m * Transform2D(Vector2(1.0, 0.0), Vector2(-k, 1.0), Vector2(k * 0.12, 0.0))
		return
	var dip: float = _style.dip_s if view == "S" else _style.dip_n
	if dip != 1.0:
		_tr(0, Art.FOOT_Y)
		_sc(1.0, dip)
		_tr(0, -Art.FOOT_Y)


## The baked body for one view: the sprite, or for a figure with a hunch (a brute)
## the sprite warped by its build. `col` fades it (a corpse going).
func _draw_body(view: String, col: Color = Color.WHITE) -> void:
	if not _meshes.has(view):
		_meshes[view] = Art.sprite_mesh(kind, view, pawn_rect)
	var mesh = _meshes[view]
	if mesh != null:
		_pen.draw_mesh(mesh, tex[view], Transform2D.IDENTITY, col)
	else:
		_pen.draw_texture_rect(tex[view], pawn_rect, false, col)


## How big this character is drawn, across and up: 1 for a person and a walker, the
## rules' size times the kind's build for the other dead.
func figure_scale_xy() -> Vector2:
	if not zombie or entity == null:
		return Vector2.ONE
	return Art.figure_scale(kind, Art.size_of(entity))


## How tall the figure is drawn against a walker (1 for a person or a walker): what
## something placed above the head, a label or a bar, multiplies its offset by.
func figure_scale() -> float:
	if not zombie or entity == null:
		return 1.0
	return Art.height_ratio(kind, Art.size_of(entity))


## The box that is the figure, in tiles from where it stands: what a click is
## tested against and a selection ring is drawn around. A person's and a walker's
## are the same (0.42 either side, 0.95 up, 0.42 down).
func hit_box() -> Rect2:
	if not zombie or entity == null:
		return Art.hit_box("walker", 1.0)
	return Art.hit_box(kind, Art.size_of(entity))


func _draw() -> void:
	if entity == null:
		return
	if zombie:
		if entity.state == "dying" or entity.state == "dead":
			_draw_dead()
		else:
			_draw_zombie()
	elif entity.turned:
		return # the walker standing there now is drawn instead
	elif entity.resting_bed != null:
		_draw_resting()
	elif entity.downed:
		_draw_downed()
	else:
		_draw_person()


func _view() -> String:
	return "E" if entity.facing == "W" else entity.facing


func _draw_person() -> void:
	var p = entity
	var view := _view()
	var mirror: bool = p.facing == "W"
	var bob: float = absf(sin(p.walk_phase)) * 0.045 if p.moving else sin(anim_t * 2.2 + p.x * 3.0) * 0.008
	_reset()
	_apply()
	Art.shadow(self)
	if mirror:
		_sc(-1, 1)
	_apply()
	Art.legs(self, pal, view, p.walk_phase, p.moving, false)
	_tr(0, -bob)
	var aim: float = PI - p.aim if mirror else p.aim
	if view == "N":
		_weapon(view, aim)
	_apply()
	draw_texture_rect(tex[view], pawn_rect, false)
	if view != "N":
		_weapon(view, aim)


func _weapon(view: String, aim: float) -> void:
	var p = entity
	var saved := _m
	var pv: Vector2 = PIVOT[view]
	_tr(pv.x, pv.y)
	var a := aim
	if p.reloading > 0.0:
		a = aim + sin(p.reloading * 5.0) * 0.15
	_rot(a)
	if cos(a) < 0.0:
		_sc(1, -1)
	var push: float = sin(p.thrust * PI) * 0.6 if p.weapon == "pike" else -p.recoil * 0.08
	_tr(push, 0)
	_apply()
	draw_texture_rect(weapon_tex, weapon_rect, false)
	Art.hands(self, gun_front, pal.skin)
	_m = saved


func _draw_zombie() -> void:
	var z = entity
	var st := _style
	var view := _view()
	var mirror: bool = z.facing == "W"
	var attacking: bool = z.state == "attack" or (z.state == "breach" and not z.moving)
	var rate: float = st.claw_rate
	var thump: float = st.claw_thump
	var bounce: float = st.bob
	var sway: float = sin(z.t * 1.7 + z.x) * 0.06 + (sin(z.t * 7.3 * rate) * 0.035 if attacking else 0.0)
	var lunge: float = maxf(0.0, sin(z.t * 7.3 * rate)) * 0.06 * thump if attacking else 0.0
	var bob: float = absf(sin(z.walk_phase)) * 0.035 * bounce if z.moving else 0.0
	_reset()
	var fs := figure_scale_xy()
	if fs != Vector2.ONE:
		_fit_figure(fs)
	_apply()
	Art.shadow(_pen, st)
	if mirror:
		_sc(-1, 1)
	_apply()
	Art.legs(_pen, pal, view, z.walk_phase, z.moving, z.limp, 1.0, st)
	_tr(0, 0.3)
	_rot(sway)
	_tr(0, -0.3 - bob)
	_lean(view)
	if view == "E":
		_tr(lunge, 0)
	else:
		_tr(0, lunge * 0.5 if view == "S" else -lunge * 0.5)
	_apply()
	Art.arms(_pen, pal, view, z.t, attacking, "back", st, z.walk_phase)
	_draw_body(view)
	Art.arms(_pen, pal, view, z.t, attacking, "front", st, z.walk_phase)


func _draw_dead() -> void:
	var z = entity
	var view := _view()
	var e: float = z.fall * z.fall
	var alpha := 1.0
	if z.state == "dead" and z.dead_t > 55.0:
		alpha = maxf(0.0, 1.0 - (z.dead_t - 55.0) / 15.0)
	_reset()
	_tr(0, 0.3)
	_rot(z.fall_dir * (PI / 2.0) * e)
	if z.facing == "W":
		_sc(-1, 1)
	var fs := figure_scale_xy()
	if fs != Vector2.ONE:
		_sc(fs.x, fs.y)
	_tr(0, -0.3)
	_apply()
	Art.legs(_pen, pal, view, 0.0, false, false, alpha, _style)
	_draw_body(view, Color(1, 1, 1, alpha))


func _draw_downed() -> void:
	var p = entity
	_reset()
	_tr(0, 0.3)
	_rot(PI / 2.0)
	_tr(0, -0.3)
	_apply()
	Art.legs(self, pal, "S", 0.0, false, false)
	draw_texture_rect(tex["S"], pawn_rect, false)


## In bed: the head and shoulders on the pillow and the bed's own blanket over
## the rest (the body is drawn upright, so it lies along the bed, not across it).
func _draw_resting() -> void:
	var blanket := _blanket_color()
	_reset()
	_tr(0, -0.16) # the head lands on the pillow
	_apply()
	draw_texture_rect(tex["S"], pawn_rect, false)
	_reset()
	_apply()
	var hump := S.rrect(-0.34, -0.3, 0.68, 1.22, 0.2, 4)
	draw_colored_polygon(hump, blanket.lightened(0.05))
	draw_polyline(S.closed(hump), Color(S.INK.r, S.INK.g, S.INK.b, 0.5), S.LW, true)
	draw_line(Vector2(-0.29, -0.27), Vector2(0.29, -0.27), blanket.lightened(0.28), 0.06, true)


## The colour of the blanket of the bed they lie in, read from the bed's art.
func _blanket_color() -> Color:
	var bed: Vector2 = entity.resting_bed
	var key := "%.2f,%.2f" % [bed.x, bed.y]
	if key == _bed_key:
		return _bed_col
	_bed_key = key
	for o in beds:
		if absf(float(o.cx) - bed.x) < 0.05 and absf(float(o.cy) - bed.y) < 0.05 and not o.pieces.is_empty():
			var img: Image = GD.tex(o.pieces[0].file).get_image()
			if img != null:
				_bed_col = img.get_pixel(int(img.get_width() * 0.5), int(img.get_height() * 0.6))
			break
	return _bed_col
