## The data of a town run made a few milliseconds a frame (One House, WP9), for the loading card: `begin(run)`, then `step(budget_ms)` once a frame until it says true, then `result()`
## (the same Dictionary as `TownBoot.data(run)`, which does it all in one go for a headless run or a test).
##
## The pieces, in order: the generator (`TownGen.begin/step`: a lot at a time, and the street furniture, the map's indexes and the people in pieces of a few milliseconds each), the map data
## (`TownBoot.from_town`), the looks of the kit's things the town is furnished with (`TownBoot.object_looks`: the generator reads the sizes of their pictures from a table and loads none, so
## that no step of it is a dozen pictures of 1000 x 1500 pixels; each look is asked for here, one at a time, and the first of a picture loads it: 2 to 14 ms on the desktop), the pictures of
## the plain objects (`TownBoot.object_pictures`) and the pictures of the looks of the dead (`TownBoot.pawn_pictures`, 72 of 3 to 4 ms), so that the first of each seen in play is not a hitch.
## What is not split: `GD.load_all`, the data files of the game (one step), and `TownBoot.from_town` with the lists of what to load: a frame or two on a desktop.
extends RefCounted

const TownGen := preload("res://scripts/town/town_gen.gd")
const TownBoot := preload("res://scripts/town/town_boot.gd")
const TownArt := preload("res://scripts/town/town_art.gd")
const GD := preload("res://scripts/game_data.gd")

var _phase := 0
var _gen
var _town: Dictionary = {}
var _data: Dictionary = {}
var _plan: Dictionary = {}
## What is loaded under the card, in order: a look (Array: kind, facing, state, variant) is asked of `TownArt`, a path (String) is loaded; `_faces_from` is where the dead's pictures begin.
var _work: Array = []
var _work_i := 0
var _faces_from := 0
var _title := false
var _words := "Laying out the streets"


func begin(run: Dictionary) -> void:
	_plan = TownBoot.plan_of(run)
	_phase = 0
	_work_i = 0
	_title = bool(run.get("title", false))


## Does about `budget_ms` of the work (always at least one piece); true when the data is ready.
func step(budget_ms: float) -> bool:
	var t0 := Time.get_ticks_usec()
	while _phase < 3:
		match _phase:
			0:
				_gen = TownGen.new()
				_gen.begin(int(_plan.seed), _plan.opts)
				_phase = 1
			1:
				var left := budget_ms - float(Time.get_ticks_usec() - t0) / 1000.0
				if _gen.step(maxf(1.0, left)):
					_town = _gen.result()
					_phase = 2
					_words = "Putting up the houses"
			2:
				_data = TownBoot.from_town(_town)
				_work = TownBoot.object_looks(_data)
				_work.append_array(TownBoot.object_pictures(_data))
				# (WORLD3: the town's trees are pictures too, seventeen kinds now: loaded here a step at a time, so that the stage that makes their sprites does not load them all in one frame)
				var tree_files := {}
				for tr in _data.trees:
					tree_files[String(tr.file)] = true
				_work.append_array(tree_files.keys())
				_faces_from = _work.size()
				if not _title:    # (the title's few dead take their pictures as they come)
					_work.append_array(TownBoot.pawn_pictures(_data))
				_phase = 3
				_words = "Furnishing the rooms"
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	# (one piece at least a step, as above: a step that has spent its time before this still moves the loader on)
	while _phase == 3 and _work_i < _work.size():
		var w = _work[_work_i]
		if w is Array:
			var look: Dictionary = TownArt.look(String(w[0]), String(w[1]), String(w[2]), int(w[3]))
			if look.has("tex"):
				_check_table(look.tex)
		else:
			_check_table(GD.tex(String(w)))
		_work_i += 1
		if _work_i >= _faces_from:
			_words = "Learning the faces"
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	if _phase == 3 and _work_i >= _work.size():
		_phase = 4
	return _phase >= 4


## Warns (in a development run) when a picture is not the size `assets/data/prop_sizes.json` says: the generator measured the town's props by the table.
func _check_table(tex: Texture2D) -> void:
	if tex == null:
		return
	var table := GD.table_size(tex.resource_path)
	if table.x > 0.0 and table != tex.get_size():
		push_warning("prop_sizes.json is out of date: %s is %s, the table says %s (run tools/make_prop_sizes.gd)" % [tex.resource_path, str(tex.get_size()), str(table)])


## How far along it is, 0 to 1 (the bar of the card): the generator is about a third of it, the pictures the rest.
func progress() -> float:
	match _phase:
		0:
			return 0.0
		1:
			return 0.4 * _gen.progress()
		2:
			return 0.4
		3:
			return 0.4 + 0.6 * float(_work_i) / float(maxi(1, _work.size()))
	return 1.0


## A few words for under the bar.
func words() -> String:
	return _words


func result() -> Dictionary:
	return _data
