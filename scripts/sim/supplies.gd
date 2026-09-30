## Food, water, scrap, meds and ammo: meals and thirst, the sources, what
## repairs cost, and how hungry or thirsty people perform. STUB: the supplies
## builder fills this in; the rules already call every method below.
extends RefCounted

var sim


func setup(s) -> void:
	sim = s


## Called at the start of a run (after Sim.start_run set the stocks and clock).
func start() -> void:
	pass


## Called every step of the rules (dt in seconds); use sim.game_hours(dt) for
## game time. Meal times (07:00, 13:00, 19:00), hunger and thirst, dawn sources.
func update(_dt: float) -> void:
	pass


## A multiplier (1.0 normal) for how well a person shoots and works right now.
func perf(_p) -> float:
	return 1.0


## How much of `amount` (health points of repair wanted this step) can be done
## given the scrap there is; takes the scrap it uses. Returns the amount allowed.
func repair_budget(amount: float) -> float:
	return amount


## Days of "food" or "water" left for the living crew at the usual consumption
## (not counting income), for the HUD.
func days_left(_kind: String) -> float:
	return 99.0


## Marks for a person's card and panel, for example
## [{"icon": "hungry", "color": Color("#e8953a"), "tip": "Hungry"}].
func status_of(_p) -> Array:
	return []


func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
