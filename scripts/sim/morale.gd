## Morale: how each person is holding up, 0 to 100, with the reasons shown (well fed,
## the dead at the wall, a friend down...). Low morale costs aim and work; very low
## is a breakdown. (Round 4: the stub with the agreed interface; the PEOPLE builder
## fills it in.)
extends RefCounted

## Tests, the tutorial and the harness switch the whole system off with this.
var enabled := true
var sim


func setup(s) -> void:
	sim = s


func start() -> void:
	pass


func update(_dt: float) -> void:
	pass


## 0 to 100.
func value(_p) -> float:
	return 70.0


## A word for how they are: "Inspired", "Steady", "Shaken" or "Breaking".
func mood(_p) -> String:
	return "Steady"


## What moves it: [{"label": String, "value": float}], biggest first.
func explain(_p) -> Array:
	return []


## Whether they are in a breakdown right now (they cannot shoot or be ordered).
func breakdown(_p) -> bool:
	return false


## How well morale lets them work: 1.0 normally, less when shaken.
func perf(_p) -> float:
	return 1.0


## A sudden change for one person (or everyone when `p` is null): the reason is its label.
func shock(_p, _delta: float, _label: String) -> void:
	pass


## Small marks for the card and the panel (same shape as sim.status_of).
func status_of(_p) -> Array:
	return []


func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
