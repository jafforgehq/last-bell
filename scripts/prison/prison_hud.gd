## EXPERIMENT (prison round 5): the gun's marks on the prison HUD, drawn on the game's `bars` control (screen space): the aim line from the muzzle, the crosshair, the reload ring and the ammo readout
## ("Pump shotgun  6 / 400": rounds in the magazine over the rounds in the backpack). Small equivalents of overlay_node.gd `_draw_avatar` and hud.gd `_update_ammo` (those need the One House Main);
## they use the same rules calls (sim.muzzle, avatar.trace, reach_of, shot_cost, gun_of), so the line stops where the shot would.
extends RefCounted

const INK := Color(0.96, 0.94, 0.86, 0.95)
const HIT := Color("#ff7d6e")
const EDGE := Color(0.04, 0.07, 0.06, 0.9)
const ACCENT := Color(0.941, 0.761, 0.29)
const WARN := Color(0.95, 0.7, 0.25)
const DANGER := Color(1.0, 0.45, 0.4)

## Rounds that can still be loaded: the backpack's shells (grid and credit), or the stock when the pack is off.
static func reserve(game, me) -> int:
	var inv = game.pack.inv if game.pack != null else null
	if inv != null and inv.active():
		return inv.shots_available(me)
	return int(floor(float(game.run.sim.stock.ammo)))


## Whether the gun is in play: the clear phase, a raid, or the managed base while Ruth can fire.
static func armed(game) -> bool:
	return not game.busy and (game.mode == "raid" or game.phase == "clear" or game.siege.can_fire())


static func draw(game, c: Control, v: Vector2) -> void:
	var sim = game.run.sim
	var me = game.run.avatar_p
	if me == null or me.dead or me.downed or game.busy or not armed(game):
		return
	var live: Dictionary = sim.gun_of(me)
	var melee: bool = bool(me.gun.get("melee", false))
	var zoom: float = game.zoom_px
	var to_scr := func(p: Vector2) -> Vector2: return (p - game.cam_center) * zoom + v / 2.0
	var aim_hit := false
	var end_scr := Vector2.ZERO
	# the aim line (not while the gun is being loaded, nor for a blow)
	if not melee and me.reloading <= 0.0:
		var shoulder: Vector2 = sim.avatar.shoulder(me)
		var muzzle: Vector2 = sim.muzzle(me, me.aim)
		var reach: float = sim.reach_of(live, me)
		var res: Dictionary = sim.avatar.trace(shoulder, me.aim, reach)
		aim_hit = res.z != null
		var a: Vector2 = to_scr.call(muzzle)
		end_scr = to_scr.call(res.end)
		var col := HIT if aim_hit else INK
		var n := clampi(int(a.distance_to(end_scr) / 28.0), 2, 14)
		for i in n:
			var k := float(i) / n
			c.draw_line(a.lerp(end_scr, k), a.lerp(end_scr, float(i + 1) / n), Color(col, lerpf(0.75, 0.08, k)), 1.5, true)
		if aim_hit:
			c.draw_arc(end_scr, 4.0, 0, TAU, 12, Color(HIT, 0.85), 1.5, true)
	# the crosshair: at the pointer, or where a forced aim (--aimdir) ends
	var at: Vector2 = c.get_viewport().get_mouse_position()
	if game.args.has("aimdir"):
		at = end_scr if end_scr != Vector2.ZERO else to_scr.call(Vector2(me.x, me.y) + Vector2.from_angle(me.aim) * 3.0)
	if Rect2(Vector2.ZERO, v).has_point(at):
		var r := 10.0
		if not melee:
			var cone: float = sim.avatar.spread_of(me, live)
			r = clampf(to_scr.call(Vector2(me.x, me.y - 0.3)).distance_to(at) * cone * 0.5, 10.0, 46.0)
		var ink := HIT if aim_hit else INK
		for pass_ in 2:
			var col2: Color = EDGE if pass_ == 0 else ink
			var w := 4.0 if pass_ == 0 else 2.0
			c.draw_arc(at, r, 0, TAU, 32, col2, w, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				c.draw_line(at + d * (r - 3.0), at + d * (r + 6.0), col2, w, true)
		c.draw_circle(at, 1.2, ink)
	# the reload ring round her, with a pip for each shell of a shell-loader
	if me.reloading > 0.0 and not melee:
		var total: float = maxf(0.01, float(me.gun.get("reload", 1.0)) * float(sim.traits.mult(me, "reload")))
		var f := clampf(1.0 - me.reloading / total, 0.0, 1.0)
		var cc: Vector2 = to_scr.call(Vector2(me.x, me.y - 0.45))
		var rr := maxf(18.0, 0.66 * zoom)
		c.draw_arc(cc, rr, 0, TAU, 40, Color(0.04, 0.07, 0.06, 0.5), 4.0, true)
		c.draw_arc(cc, rr, -PI / 2.0, -PI / 2.0 + f * TAU, 40, ACCENT, 3.0, true)
		var cap := int(me.gun.get("mag", 0))
		if cap > 1 and cap <= 12:
			var filled := int(floor(f * cap))
			for k in cap:
				var ang := -PI / 2.0 + TAU * (float(k) + 0.5) / float(cap)
				c.draw_circle(cc + Vector2.from_angle(ang) * rr, 4.0, Color("#c9a54a") if k < filled else Color(0.30, 0.30, 0.26, 0.9))
	# the readout, bottom left above the health bar
	var rounds := reserve(game, me)
	var ready: int = me.mag
	var dry: bool = not melee and ready <= 0 and rounds <= 0
	var low: bool = not melee and (ready <= maxi(1, ceili(float(me.gun.get("mag", 0)) * 0.25)) or rounds < int(me.gun.get("mag", 0)))
	var state := ""
	if melee:
		state = "melee"
	elif me.reloading > 0.0:
		state = "RELOADING"
	elif dry:
		state = "EMPTY"
	elif ready <= 0:
		state = "R to reload"
	var box := Rect2(14, v.y - 96, 230, 52)
	c.draw_rect(box, Color(0, 0, 0, 0.6))
	var font := ThemeDB.fallback_font
	c.draw_string(font, box.position + Vector2(8, 17), String(me.gun.get("name", me.weapon)), HORIZONTAL_ALIGNMENT_LEFT, 150, 14, Color(0.85, 0.85, 0.8))
	c.draw_string(font, box.position + Vector2(8, 17), state, HORIZONTAL_ALIGNMENT_RIGHT, 214, 13, ACCENT if me.reloading > 0.0 else DANGER)
	var col3 := DANGER if dry else (WARN if low else INK)
	c.draw_string(font, box.position + Vector2(8, 42), "-" if melee else "%d / %d" % [ready, rounds], HORIZONTAL_ALIGNMENT_LEFT, 150, 24, col3)
	var cap2 := int(me.gun.get("mag", 0))
	var bf := 1.0 if melee or cap2 <= 0 else clampf(float(ready) / float(cap2), 0.0, 1.0)
	c.draw_rect(Rect2(box.position + Vector2(8, 46), Vector2(214, 4)), Color(0.15, 0.15, 0.12))
	c.draw_rect(Rect2(box.position + Vector2(8, 46), Vector2(214.0 * bf, 4)), col3)
