## Screenshots of the HUD in states that are awkward to reach by playing: loads
## the real game, swaps in the test kit's fake modules, sets a state by hand and
## saves the window. Windowed, from the repo root:
##   Godot --path . --script res://tools/hud_shots.gd -- --case=cards --out=/tmp/cards.png [--size=980x700]
## Cases: cards, panel, dialog, over (see the _case_ functions).
extends SceneTree

const Kit := preload("res://tests/hud_kit.gd")

var _main


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var case_name := "cards"
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--case="):
			case_name = a.trim_prefix("--case=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	Engine.set_meta("run", {"difficulty": 1, "seed": 7})
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	var sim = _main.sim
	sim.supplies = Kit.FakeSupplies.new()
	sim.medical = Kit.FakeMedical.new()
	sim.scavenge = Kit.FakeScavenge.new()
	sim.scenario = Kit.FakeScenario.new()
	for m in [sim.supplies, sim.medical, sim.scavenge, sim.scenario]:
		m.setup(sim)
	_main.speed = 0
	for i in 12:
		await process_frame
	call("_case_" + case_name)
	for i in 14:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


func _person(id: String):
	for p in _main.sim.people:
		if p.id == id:
			return p
	return null


func _select(id: String) -> void:
	_main._select({"kind": "person", "ref": _person(id)})


func _mark(icon: String, color: Color, tip: String) -> Dictionary:
	return {"icon": icon, "color": color, "tip": tip}


## Stores with days left, the clock, and marks and dimmed cards on the bar.
func _case_cards() -> void:
	var sim = _main.sim
	var hud = _main.hud
	sim.supplies.days = {"food": 2.4, "water": 0.6}
	sim.weather = "rain"
	sim.scenario.today = 7
	sim.stock.meds = 2.0
	sim.supplies.marks["ana"] = [_mark("hungry", hud.WARN, "Hungry")]
	sim.medical.marks["ana"] = [_mark("wound", hud.DANGER, "Bleeding"), _mark("fever", hud.WARN, "Feverish")]
	sim.supplies.marks["marcus"] = [_mark("thirsty", hud.DANGER, "Dehydrated"), _mark("starving", hud.DANGER, "Starving"), _mark("down", hud.DANGER, "Down"), _mark("resting", hud.INFO, "Resting")]
	_person("dez").dead = true
	var walt = _person("walt")
	walt.dead = true
	walt.turned = true
	_person("hector").away = {"kind": "party", "site": "pharmacy"}
	_person("ruth").hp = 55.0
	_select("ana")


## The selection panel with every row and every button.
func _case_panel() -> void:
	var sim = _main.sim
	var hud = _main.hud
	var ana = _person("ana")
	ana.hunger_h = 20.0
	ana.thirst_h = 26.0
	ana.wounds = 2
	ana.bleeding = 6.0
	ana.hp = 62.0
	sim.supplies.days = {"food": 4.0, "water": 2.0}
	sim.supplies.marks["ana"] = [_mark("hungry", hud.WARN, "Hungry"), _mark("thirsty", hud.DANGER, "Dehydrated")]
	sim.medical.marks["ana"] = [_mark("wound", hud.DANGER, "Bleeding"), _mark("fever", hud.WARN, "Feverish")]
	sim.medical.treat["ana"] = true
	sim.medical.sendout["ana"] = true
	sim.medical.stage["ana"] = "feverish"
	sim.scavenge.can = true
	_select("ana")


## A downed person being looked after.
func _case_down() -> void:
	var sim = _main.sim
	var hud = _main.hud
	var marcus = _person("marcus")
	marcus.hp = 0.0
	marcus.downed = true
	marcus.stabilised = true
	marcus.resting_bed = Vector2(47.0, 56.9)
	marcus.activity = "Resting in the infirmary"
	sim.medical.marks["marcus"] = [_mark("down", hud.DANGER, "Down"), _mark("resting", hud.INFO, "Resting")]
	_select("marcus")
