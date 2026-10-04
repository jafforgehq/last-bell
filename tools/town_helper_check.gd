extends SceneTree
const Helpers := preload("res://tests/helpers.gd")
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var g := Helpers.town_game()
	print("town_game ms ", Time.get_ticks_msec() - t0, " sim ", g.sim.get_script().resource_path, " people ", g.sim.people.size(), " player ", g.sim.player_id, " parts ", g.sim.parts_made, " dormant ", g.sim.field.counts())
	var sim = g.sim
	var p = sim.avatar.player()
	print("avatar at ", p.x, ",", p.y, " house ", sim.houses.house_at(p.x, p.y), " start ", sim.houses.start_house(), " room ", sim.houses.room_at(p.x, p.y))
	var t1 := Time.get_ticks_usec()
	var worst := 0.0
	for i in 600:
		var ts := Time.get_ticks_usec()
		sim.avatar.set_input(Vector2(0.0, 1.0) if i < 300 else Vector2(1.0, 0.0), Vector2(p.x, p.y + 5.0), false)
		sim.update(1.0 / 30.0)
		worst = maxf(worst, float(Time.get_ticks_usec() - ts) / 1000.0)
	print("600 steps: mean ms ", float(Time.get_ticks_usec() - t1) / 600000.0, " worst ", worst, " zombies ", sim.zombies.size(), " counts ", sim.field.counts(), " avatar at ", p.x, ",", p.y, " hp ", p.hp)
	g.world.free()
	quit()
