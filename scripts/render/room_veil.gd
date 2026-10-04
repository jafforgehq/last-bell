## The dark veil over one room of the house the avatar is in (One House, WP2): the room's floor is hidden (floor, furniture, what lies on it, and by the house view's
## rule the people in it) until the room is revealed, when the veil fades away over FADE seconds. One draw command; the fade is the node's alpha.
##
## `setup(room, house, rect, revealed)` (rect: the room's floor, a Rect2i in tiles), `set_revealed(on)` and `tick(dt)` each frame.
extends Node2D

const GD := preload("res://scripts/game_data.gd")

const TILE := GD.TILE
const FADE := 0.4
const DARK := Color(0.03, 0.035, 0.055, 0.97)
## The veil reaches this far (tiles) over the wall that bounds the room, so that the picture of a piece of furniture that leans on the wall is covered too.
const BLEED := 0.12

var room := -1
var house := -1
var rect_t := Rect2()
var revealed := false


func setup(room_idx: int, house_id: int, rect: Rect2i, is_revealed: bool) -> void:
	room = room_idx
	house = house_id
	rect_t = Rect2(rect)
	revealed = is_revealed
	position = rect_t.position * TILE
	modulate.a = 0.0 if revealed else 1.0
	visible = not revealed
	queue_redraw()


func set_revealed(on: bool) -> void:
	revealed = on


func tick(dt: float) -> void:
	var want := 0.0 if revealed else 1.0
	if modulate.a == want:
		return
	modulate.a = move_toward(modulate.a, want, dt / FADE)
	visible = modulate.a > 0.01


func _draw() -> void:
	var b := BLEED * TILE
	draw_rect(Rect2(Vector2(-b, -b), rect_t.size * TILE + Vector2(b, b) * 2.0), DARK)
