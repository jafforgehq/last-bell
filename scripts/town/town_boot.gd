## The factories `main.gd` calls to make a TOWN run instead of the school's (feature/town-core, WP1): the data (the generated map, with the one survivor as its only
## person), the world (chunked, scripts/town/town_world.gd) and the rules (scripts/town/town_sim.gd). `wants` says whether the command line or the run's meta asks for the town.
##
##   `--town` or `--town=<seed>`  the real game on the town (the seed is 1 unless given: the demo's town is the same every time); with `--crew` the old `--town[=place]` of the
##                                school's Town Board is meant and this says no.
##   `--town-spike`               the foundation's standalone scene (scripts/town/town_scene.gd), a benchmark and a look at the town; `--spike-town` is the old name of it.
##   `--town-blocks=2`            a 64 x 64 town of four blocks (for a quick look).
##   run meta {"town": true | seed}   what the title's New game puts in `Engine.meta "run"`.
extends RefCounted

const TownGen := preload("res://scripts/town/town_gen.gd")
const TownWorld := preload("res://scripts/town/town_world.gd")
const TownSim := preload("res://scripts/town/town_sim.gd")
const GD := preload("res://scripts/game_data.gd")


## Whether this process plays the town (not the foundation's standalone scene).
static func wants(args: Array, meta: Dictionary = {}) -> bool:
	if meta.has("town") and meta.town:
		return true
	var town := false
	var crew := false
	for a in args:
		var s := String(a)
		if s == "--town" or s.begins_with("--town="):
			town = true
		if s.begins_with("--crew"):
			crew = true
	if OS.has_feature("web") and not town:
		var qs := String(JavaScriptBridge.eval("window.location.search"))
		for part in qs.trim_prefix("?").split("&", false):
			if String(part) == "town" or String(part).begins_with("town="):
				town = true
	return town and not crew


## Whether this process runs the standalone scene (`--town-spike`, or the old `--spike-town`).
static func wants_spike(args: Array) -> bool:
	for a in args:
		var s := String(a)
		if s == "--town-spike" or s.begins_with("--town-spike=") or s == "--spike-town" or s.begins_with("--spike-town="):
			return true
	return false


## The seed of the town: `--town=<n>`, the run's meta `town` when it is a number, else 1.
static func seed_of(args: Array, meta: Dictionary = {}) -> int:
	if meta.has("town") and (typeof(meta.town) == TYPE_INT or typeof(meta.town) == TYPE_FLOAT):
		return int(meta.town)
	for a in args:
		var s := String(a)
		if s.begins_with("--town=") and s.trim_prefix("--town=").is_valid_int():
			return int(s.trim_prefix("--town="))
	return 1


## The generator's options from the command line (`--town-blocks=2`).
static func opts_of(args: Array) -> Dictionary:
	var out := {}
	for a in args:
		var s := String(a)
		if s.begins_with("--town-blocks=") and s.trim_prefix("--town-blocks=").is_valid_int():
			out["blocks"] = int(s.trim_prefix("--town-blocks="))
	return out


## The map data of a town run: `run` is {"town": true | seed, "town_opts": {...}} (what `Main._ready` has); the generated town is the data's "town_data".
static func data(run: Dictionary) -> Dictionary:
	var seed := seed_of(OS.get_cmdline_user_args(), run)
	var opts: Dictionary = run.get("town_opts", opts_of(OS.get_cmdline_user_args()))
	return from_town(TownGen.make(seed, opts))


## The map data for an already generated town: its map with Ruth, the one survivor, at the start, and the town itself.
static func from_town(town: Dictionary) -> Dictionary:
	var d: Dictionary = town.data
	var base := GD.load_all()
	var def: Dictionary = {}
	for p in base.people:
		if String(p.id) == "ruth":
			def = p.duplicate(true)
	var at: Vector2 = town.start.pos
	# (no seat, no post of the school's: the avatar is nobody's worker)
	def["station"] = ""
	def["post_id"] = ""
	def["job"] = {"x": at.x, "y": at.y, "what": "At home"}
	def["post"] = {"x": at.x, "y": at.y, "what": "At home"}
	d["people"] = [def]
	d["town_data"] = town
	return d


static func world() -> Node2D:
	return TownWorld.new()


static func sim(data: Dictionary, world_node, fx):
	return TownSim.new(data, world_node, fx)
