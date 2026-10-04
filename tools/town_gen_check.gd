extends SceneTree
const TownGen := preload("res://scripts/town/town_gen.gd")
func _initialize() -> void:
	for opts in [{"blocks": 2}, {}]:
		var t0 := Time.get_ticks_msec()
		var t := TownGen.make(1, opts)
		print("opts ", opts, " ms ", Time.get_ticks_msec() - t0, " size ", t.size, " houses ", t.houses.size(), " dead ", t.dead.size(), " rescue ", t.rescue.size(), " digest ", TownGen.digest(t))
		print("  start ", t.start.house, " pos ", t.start.pos, " ring ", t.start.ring, " start house dead ", t.houses[t.start.house].dead.size(), " kind ", t.houses[t.start.house].kind, " fenced ", t.houses[t.start.house].fenced)
		for r in t.rescue:
			var in_room := 0
			for i in t.houses[r.house].dead:
				if int(t.dead[i].room) == int(r.room):
					in_room += 1
			print("  rescue house ", r.house, " ring ", r.ring, " dist ", snappedf(r.dist, 0.1), " guards ", t.houses[r.house].dead.size(), " in survivor's room ", in_room, " address ", t.houses[r.house].address)
	quit()
