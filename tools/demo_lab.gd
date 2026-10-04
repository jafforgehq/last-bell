## The demo lab (round 26): the three nights of the demo (scripts/sim/demo_run.gd) played by the harness's people, to see whether the Big Night is held with the
## player at the wall and is dangerous without them.
##
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --headless --path . --script res://tools/demo_lab.gd -- --reps=0..5 --modes=bot,idle [--hz=15] [--data=path] [--out=path.json] [--quiet]
##
## Each rep plays the demo from its first morning to the dawn of day four (or to the colony's end): the rules' dice are re-seeded `seed x 1000 + rep` (rep 0 keeps the
## run's own), the day's chores are done by the harness's informed policy (tools/balance.gd: jobs, buildings, trips; once a second), and the night by the mode:
##   bot    the bot plays Ruth (tools/avatar_bot.gd: stands at the wall the forecast names, shoots, answers the radio's calls, mends)
##   idle   Ruth keeps her hands off in the school gym: the community alone
## It prints a line for each night and a verdict (how many nights of each kind were held). A night is HELD when no wall of the compound fell and nobody died
## (NightStats). `--data` reads another assets/data/demo.json (a number tried before it is in the game).
extends SceneTree

const GD := preload("res://scripts/game_data.gd")
const World := preload("res://scripts/world.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const FxNull := preload("res://scripts/sim/fx_null.gd")
const Demo := preload("res://scripts/demo.gd")
const DemoRun := preload("res://scripts/sim/demo_run.gd")
const Balance := preload("res://tools/balance.gd")
const BotLib := preload("res://tools/avatar_bot.gd")
const NightLab := preload("res://tools/night_lab.gd")

var _out := ""
var _quiet := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var reps: Array = [0]
	var modes: Array = ["bot", "idle"]
	var hz := 15.0
	for a in OS.get_cmdline_user_args():
		var arg := String(a)
		if arg.begins_with("--reps="):
			reps = NightLab.parse_ints(arg.trim_prefix("--reps="))
		elif arg.begins_with("--modes="):
			modes = arg.trim_prefix("--modes=").split(",", false)
		elif arg.begins_with("--hz="):
			hz = float(arg.trim_prefix("--hz="))
		elif arg.begins_with("--data="):
			Demo.data_path = arg.trim_prefix("--data=")
			Demo.forget()
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--quiet":
			_quiet = true
	var rows: Array = []
	var games: Array = []
	for rep in reps:
		for mode in modes:
			var g := play(int(rep), String(mode), hz)
			games.append(g)
			for r in g.rows:
				rows.append(r)
				if not _quiet:
					print(line(r))
			if not _quiet:
				print("  rep %d %-4s -> %s on day %d, %d alive, %d put down, %.1f s" % [int(rep), String(mode), String(g.outcome), int(g.day), int(g.alive), int(g.kills), float(g.took)])
	print(verdict(rows, games, modes))
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"games": games, "rows": rows}, "  "))
			f.close()
	quit()


## One demo run to its end: {"rep", "mode", "outcome" ("victory", "defeat" or "cut"), "day", "alive", "kills", "rows" (a row of NightStats for each night), "took"}.
static func play(rep: int, mode: String, hz: float) -> Dictionary:
	var started := Time.get_ticks_msec()
	var data := GD.load_all()
	var world := World.new()
	Engine.get_main_loop().root.add_child(world)
	world.build(data)
	var sim := Sim.new(data, world, FxNull.new())
	DemoRun.begin(sim)
	if rep > 0:
		sim.rng.seed = Demo.run_seed() * 1000 + rep
	var bot = BotLib.AvatarBot.new(sim, mode)
	var stats = BotLib.NightStats.new(sim, mode)
	var policy := Balance.policy_for(sim, false, true)
	var dt := 1.0 / hz
	var every := maxi(1, roundi(hz))
	var step := 0
	var guard := int(hz * 480.0 * float(Demo.nights() + 2))
	while sim.over == "" and step < guard:
		bot.step(dt)
		sim.update(dt)
		stats.observe(dt)
		step += 1
		if step % every == 0:
			policy.tick()
	stats.finish()
	var alive := 0
	for p in sim.people:
		if not (p.dead or p.turned):
			alive += 1
	var rows: Array = []
	for r in stats.rows:
		var row: Dictionary = (r as Dictionary).duplicate(true)
		row["rep"] = rep
		rows.append(row)
	var outcome: String = sim.over if sim.over != "" else "cut"
	var out := {"rep": rep, "mode": mode, "outcome": outcome, "day": int(sim.day), "alive": alive, "kills": int(sim.kills), "rows": rows, "report": sim.scenario.report(),
		"took": snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1)}
	world.free()
	return out


static func line(r: Dictionary) -> String:
	var av: Dictionary = r.get("avatar", {})
	return "rep %d day %d %-9s %-4s %-4s | size %3d plated %d | fell %d died %d down %d | lost %6.0f hp min wall %3.0f%% | present %.2f shots %3d kills %3d" % [
		int(r.get("rep", 0)), int(r.get("day", 0)), String(r.get("kind", "")), String(r.get("mode", "")), "HELD" if bool(r.get("held", false)) else "lost",
		int(r.get("size", 0)), int(r.get("plated", 0)), int(r.get("sections_fell", 0)), int(r.get("died", 0)), int(r.get("downed", 0)),
		float(r.get("hp_lost", 0.0)), 100.0 * float(r.get("min_wall", 1.0)), float(av.get("present", 0.0)), int(av.get("shots", 0)), int(av.get("kills", 0))]


## The table of the nights held, by the day and the mode, and how many runs came to the end card.
static func verdict(rows: Array, games: Array, modes: Array) -> String:
	var lines: Array = ["", "THE DEMO'S NIGHTS (held: no wall of the compound fell and nobody died)"]
	for mode in modes:
		var parts: Array = []
		for day in range(1, Demo.nights() + 1):
			var n := 0
			var held := 0
			var fell := 0.0
			var minwall := 0.0
			for r in rows:
				if String(r.mode) == String(mode) and int(r.day) == day:
					n += 1
					held += 1 if bool(r.held) else 0
					fell += float(r.get("sections_fell", 0))
					minwall += float(r.get("min_wall", 1.0))
			if n > 0:
				parts.append("night %d: %d of %d held (%.1f sections fell a night, the lowest wall %.0f%% on average)" % [day, held, n, fell / float(n), 100.0 * minwall / float(n)])
		var ended := 0
		var total := 0
		for g in games:
			if String(g.mode) == String(mode):
				total += 1
				ended += 1 if String(g.outcome) == "victory" else 0
		lines.append("  %-4s  %s | %d of %d runs came to the end card" % [String(mode), "; ".join(parts), ended, total])
	return "\n".join(lines)
