## A node whose drawing is done by a callable, so painters can live in
## plain objects (the effects system, lanterns).
extends Node2D

var painter: Callable


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
