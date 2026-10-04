## The data of a town run made a few milliseconds a frame (One House, WP9), for the loading card: `begin(run)`, then `step(budget_ms)` once a frame until it says true, then `result()`
## (the same Dictionary as `TownBoot.data(run)`, which does it all in one go for a headless run or a test).
##
## The pieces, in order: the generator (`TownGen.begin/step`: the blocks of lots a few at a time), the map data (`TownBoot.from_town`), the pictures of the looks of the dead
## (`TownBoot.warm_pawns`, a few at a time: 72 pictures, 3 to 4 ms each on the desktop) so that the first of each look seen in play is not a hitch.
## What is not split: the generator's street furniture (about a tenth of it, one step) and `GD.load_all`, the data files of the game (one step); each is a frame or two on a desktop.
extends RefCounted

const TownGen := preload("res://scripts/town/town_gen.gd")
const TownBoot := preload("res://scripts/town/town_boot.gd")
const GD := preload("res://scripts/game_data.gd")

var _phase := 0
var _gen
var _town: Dictionary = {}
var _data: Dictionary = {}
var _plan: Dictionary = {}
var _pics: Array = []
var _pic_i := 0
var _words := "Laying out the streets"


func begin(run: Dictionary) -> void:
	_plan = TownBoot.plan_of(run)
	_phase = 0
	_pic_i = 0


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
				_pics = TownBoot.pawn_pictures(_data)
				_phase = 3
				_words = "Learning the faces"
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	while _phase == 3 and _pic_i < _pics.size() and float(Time.get_ticks_usec() - t0) / 1000.0 < budget_ms:
		GD.tex(_pics[_pic_i])
		_pic_i += 1
	if _phase == 3 and _pic_i >= _pics.size():
		_phase = 4
	return _phase >= 4


## How far along it is, 0 to 1 (the bar of the card): the generator is most of it.
func progress() -> float:
	match _phase:
		0:
			return 0.0
		1:
			return 0.7 * _gen.progress()
		2:
			return 0.7
		3:
			return 0.7 + 0.3 * float(_pic_i) / float(maxi(1, _pics.size()))
	return 1.0


## A few words for under the bar.
func words() -> String:
	return _words


func result() -> Dictionary:
	return _data
