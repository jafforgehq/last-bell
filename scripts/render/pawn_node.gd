## One person or walker on the map. Its position is the character's feet, so a
## y-sorted parent puts whoever stands further south in front. Draws the baked
## body sprite plus live legs, arms and weapon, the way the web version did.
extends Node2D

const GD := preload("res://scripts/game_data.gd")
const Art := preload("res://scripts/render/pawn_art.gd")
const TILE := GD.TILE
const PIVOT := {"S": Vector2(-0.04, -0.08), "E": Vector2(0.08, -0.14), "N": Vector2(0.26, -0.22)}

var entity # Sim.Person or Sim.Zombie
var zombie := false
var tex := {} # view -> Texture2D
var pawn_rect: Rect2
var weapon_tex: Texture2D
var weapon_rect: Rect2
var gun_front = null
var anim_t := 0.0
var pal: Dictionary
var _m := Transform2D.IDENTITY


func setup(e, is_zombie: bool, data: Dictionary, key: String) -> void:
	entity = e
	zombie = is_zombie
	var box: Array = data.pawn.box
	pawn_rect = Rect2(box[0], box[1], box[2] - box[0], box[3] - box[1])
	for v in ["S", "E", "N"]:
		tex[v] = GD.tex(data.pawn.files[key][v])
	pal = Art.palette(e.look)
	if not zombie:
		var wb: Array = data.weaponArt.box
		weapon_rect = Rect2(wb[0], wb[1], wb[2] - wb[0], wb[3] - wb[1])
		weapon_tex = GD.tex(data.weaponArt.files[e.weapon])
		gun_front = data.guns[e.weapon].front
	sync()


func sync(redraw: bool = true) -> void:
	position = Vector2(entity.x, entity.y) * TILE
	if redraw:
		queue_redraw()


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
	draw_set_transform_matrix(_m)


func _draw() -> void:
	if entity == null:
		return
	if zombie:
		if entity.state == "dying" or entity.state == "dead":
			_draw_dead()
		else:
			_draw_zombie()
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
	var view := _view()
	var mirror: bool = z.facing == "W"
	var attacking: bool = z.state == "attack" or (z.state == "breach" and not z.moving)
	var sway: float = sin(z.t * 1.7 + z.x) * 0.06 + (sin(z.t * 7.3) * 0.035 if attacking else 0.0)
	var lunge: float = maxf(0.0, sin(z.t * 7.3)) * 0.06 if attacking else 0.0
	var bob: float = absf(sin(z.walk_phase)) * 0.035 if z.moving else 0.0
	_reset()
	_apply()
	Art.shadow(self)
	if mirror:
		_sc(-1, 1)
	_apply()
	Art.legs(self, pal, view, z.walk_phase, z.moving, z.limp)
	_tr(0, 0.3)
	_rot(sway)
	_tr(0, -0.3 - bob)
	if view == "E":
		_tr(lunge, 0)
	else:
		_tr(0, lunge * 0.5 if view == "S" else -lunge * 0.5)
	_apply()
	Art.arms(self, pal, view, z.t, attacking, "back")
	draw_texture_rect(tex[view], pawn_rect, false)
	Art.arms(self, pal, view, z.t, attacking, "front")


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
	_tr(0, -0.3)
	_apply()
	Art.legs(self, pal, view, 0.0, false, false, alpha)
	draw_texture_rect(tex[view], pawn_rect, false, Color(1, 1, 1, alpha))


func _draw_downed() -> void:
	var p = entity
	_reset()
	_tr(0, 0.3)
	_rot(PI / 2.0)
	_tr(0, -0.3)
	_apply()
	Art.legs(self, pal, "S", 0.0, false, false)
	draw_texture_rect(tex["S"], pawn_rect, false)
