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
const Arrival := preload("res://scripts/town/arrival.gd")
const TownWorld := preload("res://scripts/town/town_world.gd")
const TownSim := preload("res://scripts/town/town_sim.gd")
const GD := preload("res://scripts/game_data.gd")
const SaveGame := preload("res://scripts/sim/save_game.gd")


## Whether this process plays the town (not the foundation's standalone scene): `--town[=seed]`, a run whose meta says `town` (the title's New game), or a run that loads a save of
## a One House run (the save names its town's seed and size: `OneHouse.town_seed_of`).
static func wants(args: Array, meta: Dictionary = {}) -> bool:
	if String(meta.get("load", "")) != "":
		return not _saved_town(String(meta.load)).is_empty()
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


## The town a save of a One House run was made in: {"seed", "blocks"}, or {} when the file is not such a save (or the scenario module is not there yet).
static func _saved_town(path: String) -> Dictionary:
	if not ResourceLoader.exists("res://scripts/town/one_house.gd"):
		return {}
	var one = load("res://scripts/town/one_house.gd")
	var saved: Dictionary = SaveGame.read(path)
	if saved.is_empty() or not one.is_save(saved):
		return {}
	var seed: int = one.town_seed_of(saved)
	if seed < 0:
		return {}
	var blocks := TownGen.DEFAULT_BLOCKS
	var mine = saved.modules.scenario
	var size = mine.get("size", [0, 0])
	if typeof(size) == TYPE_ARRAY and size.size() == 2 and int(size[0]) >= 64:
		blocks = int(size[0]) / TownGen.PITCH
	return {"seed": seed, "blocks": blocks}


## Whether this process runs the standalone scene (`--town-spike`, or the old `--spike-town`).
static func wants_spike(args: Array) -> bool:
	for a in args:
		var s := String(a)
		if s == "--town-spike" or s.begins_with("--town-spike=") or s == "--spike-town" or s.begins_with("--spike-town="):
			return true
	return false


## The seed of the town: `--town=<n>`, the run's meta `town` when it is a number, else 1.
static func seed_of(args: Array, meta: Dictionary = {}) -> int:
	if String(meta.get("load", "")) != "":
		var t := _saved_town(String(meta.load))
		if not t.is_empty():
			return int(t.seed)
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


## What town a run asks for: {"seed", "opts"} (the generator's arguments).
static func plan_of(run: Dictionary) -> Dictionary:
	var seed := seed_of(OS.get_cmdline_user_args(), run)
	var opts: Dictionary = run.get("town_opts", opts_of(OS.get_cmdline_user_args()))
	if String(run.get("load", "")) != "":
		var t := _saved_town(String(run.load))
		if not t.is_empty():
			opts = {"blocks": int(t.blocks)}
	return {"seed": seed, "opts": opts}


## The map data of a town run: `run` is {"town": true | seed, "town_opts": {...}} (what `Main._ready` has); the generated town is the data's "town_data". All of it at once (a
## headless run, a test); a window makes it a few milliseconds a frame behind the loading card with scripts/town/town_loader.gd.
static func data(run: Dictionary) -> Dictionary:
	var plan := plan_of(run)
	var d := from_town(TownGen.make(int(plan.seed), plan.opts))
	if not bool(run.get("title", false)):    # (the title's few dead take their pictures as they come: 2 ms each, under the loading card)
		warm_pawns(d)
	return d


## The map data for an already generated town: its map with Ruth, the one survivor, at the start, and the town itself.
static func from_town(town: Dictionary) -> Dictionary:
	var d: Dictionary = town.data
	var base := GD.load_all()
	var def: Dictionary = {}
	for p in base.people:
		if String(p.id) == "ruth":
			def = p.duplicate(true)
	var at: Vector2 = Arrival.spawn(town).pos    # (the town's entry: a run begins at the forest edge, scripts/town/arrival.gd)
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


## How many milliseconds of work a frame gives the loading steps (the rest of a 60 Hz frame is for drawing the card: a browser needs more of it than a desktop).
const STEP_MS := 14.0
const STEP_MS_WEB := 10.0
## How many frames of the game itself are drawn under the card, the clock stopped, before it goes.
const WARM_FRAMES := 6
const BAR_W := 320.0


## The card shown while the town is made (`Main._ready`): a dark screen, a line and a bar that fills as the work goes, on a layer above everything; the caller frees it. `label` is
## its line ("Making the town..."; the title's is the game's name).
static func loading_card(parent: Node, label_text: String = "Making the town...") -> Node:
	var layer := CanvasLayer.new()
	layer.name = "TownLoading"
	layer.layer = 100
	var back := ColorRect.new()
	back.color = Color(0.07, 0.065, 0.055, 1.0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(back)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.9, 0.86, 0.74))
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-120.0, -20.0)
	layer.add_child(label)
	var track := ColorRect.new()
	track.color = Color(0.17, 0.155, 0.13, 1.0)
	track.set_anchors_preset(Control.PRESET_CENTER)
	track.position = Vector2(-BAR_W * 0.5, 34.0)
	track.size = Vector2(BAR_W, 6.0)
	layer.add_child(track)
	var fill := ColorRect.new()
	fill.color = Color(0.9, 0.78, 0.45, 1.0)
	fill.size = Vector2(0.0, 6.0)
	track.add_child(fill)
	var note := Label.new()
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.62, 0.58, 0.5))
	note.set_anchors_preset(Control.PRESET_CENTER)
	note.position = Vector2(-BAR_W * 0.5, 50.0)
	layer.add_child(note)
	layer.set_meta("fill", fill)
	layer.set_meta("note", note)
	parent.add_child(layer)
	return layer


static func step_ms() -> float:
	return STEP_MS_WEB if OS.has_feature("web") else STEP_MS


## A frame this slow is one nobody is watching smoothly: a browser draws a tab it has put in the background once a second (and a slow machine, a few times). At 10 ms of work a frame the card then
## creeps for minutes (a town is 130 or so steps of the generator and the world's build), so the work a frame gets grows with the frame (a quarter of it, 250 ms at the most); at a normal
## frame rate it stays `base_ms` and the bar is smooth.
const SLOW_FRAME_MS := 300.0
const SLOW_STEP_MS := 250.0


## The work (milliseconds) the next loading step may do, given `base_ms` and how long the last frame of the card took (`frame_ms`, the time between two calls, work included).
static func paced(base_ms: float, frame_ms: float) -> float:
	if frame_ms <= SLOW_FRAME_MS:
		return base_ms
	return clampf(frame_ms * 0.25, base_ms, SLOW_STEP_MS)


## Moves the card's bar to `share` (0 to 1) and puts a few words under it.
static func card_progress(card: Node, share: float, text: String = "") -> void:
	if card == null or not is_instance_valid(card):
		return
	var fill = card.get_meta("fill", null)
	if fill != null:
		fill.size.x = BAR_W * clampf(share, 0.0, 1.0)
	var note = card.get_meta("note", null)
	if note != null and text != "":
		note.text = text


## Loads the pictures of every look of the dead now, under the loading card: a pawn node costs about 2 ms the first time a look is seen (its three pictures come off the disk) and
## 0.16 ms after, so without this the first wake of each look is a hitch (the windowed bench measured 10 ms at the 95th percentile and 60 ms at worst). Returns how many it loaded.
static func warm_pawns(data: Dictionary) -> int:
	var pics := pawn_pictures(data)
	for path in pics:
		GD.tex(path)
	return pics.size()


## The looks the kit draws the town's things with, each once, in the order of the objects: [kind, facing, state, variant] for `TownArt.look`, the lookup the world makes for every object (the
## kind is the `kit` of the object, the facing its `facing` or `orient`). The generator does not load the pictures (it reads their sizes from the table, `GD.tex_size`): the loader asks for
## the looks one at a time under the card (scripts/town/town_loader.gd), the first of each picture loads it, so that none is loaded for the first time in the world's build or in play.
static func object_looks(data: Dictionary) -> Array:
	var seen := {}
	var out: Array = []
	for o in data.objects:
		var kind := String(o.get("kit", ""))
		if kind == "":
			continue
		var facing := String(o.get("facing", o.get("orient", "")))
		var state := String(o.get("state", ""))
		var variant := int(o.get("variant", 0))
		var key := "%s|%s|%s|%d" % [kind, facing, state, variant]
		if not seen.has(key):
			seen[key] = true
			out.append([kind, facing, state, variant])
	return out


## The files of the pictures the plain objects (those with no kit look) are drawn with: the pieces of the map data's objects, each file once.
static func object_pictures(data: Dictionary) -> Array:
	var seen := {}
	var out: Array = []
	for o in data.objects:
		for pc in o.pieces:
			var f := String(pc.file)
			if not seen.has(f):
				seen[f] = true
				out.append(f)
	return out


## The files of the pictures of every look of the dead (three views each), in the order `warm_pawns` loads them.
static func pawn_pictures(data: Dictionary) -> Array:
	var out: Array = []
	for key in data.pawn.files:
		if String(key).begins_with("z"):
			for view in ["S", "E", "N"]:
				out.append(data.pawn.files[key][view])
	return out
