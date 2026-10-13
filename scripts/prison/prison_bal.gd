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
