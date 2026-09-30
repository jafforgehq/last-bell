## An effects sink that does nothing, for runs without a screen: the tests,
## the balance harness and loading a save. The rules call these when they
## shoot, hit and hurt; with no drawing there is nothing to show.
extends RefCounted


func blood(_x: float, _y: float, _dx: float, _dy: float, _n: int = 10) -> void:
	pass


func decal(_x: float, _y: float, _size: float, _grow: float = 0.0) -> void:
	pass


func hit_material(_x: float, _y: float, _kind: String) -> void:
	pass


func muzzle(_x: float, _y: float, _ang: float, _big: bool) -> void:
	pass


func tracer(_x0: float, _y0: float, _x1: float, _y1: float) -> void:
	pass


func casing(_x: float, _y: float, _ang: float, _shell: bool) -> void:
	pass


func smoke(_x: float, _y: float, _size: float, _dark: bool) -> void:
	pass


func ember(_x: float, _y: float) -> void:
	pass


func update(_dt: float) -> void:
	pass
