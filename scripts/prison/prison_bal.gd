## FIX ROUND 3: the prison's balance numbers (assets/data/prison_balance.json), read once. `Bal.d()` is the whole dictionary, `Bal.role(name)` one block.
extends RefCounted

static var _d := {}


static func d() -> Dictionary:
	if _d.is_empty():
		var f := FileAccess.open("res://assets/data/prison_balance.json", FileAccess.READ)
		if f != null:
			var j = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				_d = j
	return _d


static func role(name: String) -> Dictionary:
	return d().get(name, {})


## A [lo, hi] pair of a block, drawn at random.
static func roll(r: Dictionary, key: String) -> float:
	var a: Array = r[key]
	return randf_range(float(a[0]), float(a[1]))


## The run's difficulty (0 Easy, 1 Standard, 2 Hard: assets/data/prison_difficulty.json) and its seed. Set once by prison_game.gd `_ready`.
static var level := 1
static var run_seed := 1
static var _levels: Array = []


static func _lv(i: int = -1) -> Dictionary:
	if _levels.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/prison_difficulty.json"))
		_levels = j.levels if j is Dictionary else [{}]
	return _levels[clampi(level if i < 0 else i, 0, _levels.size() - 1)]


## One number of the chosen preset (`wave`, `loot`, `drain`, `ruth_deaths`, or a text: `name`, `facts`); `def` when the file is missing.
static func dm(key: String, def: Variant = 1.0, i: int = -1) -> Variant:
	return _lv(i).get(key, def)


## A seed for one part of the run (a raid number, an event draw): the same run seed and the same salt give the same number.
static func derive(salt: int) -> int:
	return (run_seed * 2654435761 + salt * 40503 + 977) & 0x7fffffff
