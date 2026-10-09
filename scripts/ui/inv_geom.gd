## The geometry of the inventory windows, as pure functions (INV-UI): which cell a point is over, which stack covers a cell, whether a dragged item fits where it is held, where the
## window's stacks sit. No nodes, no sim: a grid is {"w", "h", "cells": [{"item", "x", "y", "rot", "count"}]} and `size_fn` is a Callable (item id, rot) -> Vector2i (the item's footprint
## in cells), so the tests give their own.
extends RefCounted

const FREE := "free"
const MERGE := "merge"
const BLOCKED := "blocked"
const OUTSIDE := "outside"


## The cell under `local` (a point in the grid control's own pixels) for cells of `cell` pixels inset by `pad`: (-1, -1) outside the `cols` by `rows` of them.
static func cell_at(local: Vector2, cell: float, cols: int, rows: int, pad: float = 0.0) -> Vector2i:
	var p := local - Vector2(pad, pad)
	if p.x < 0.0 or p.y < 0.0 or cell <= 0.0:
		return Vector2i(-1, -1)
	var c := Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell)))
	if c.x >= cols or c.y >= rows:
		return Vector2i(-1, -1)
	return c


## The pixels of a stack's footprint in the grid control (before any inset of its own).
static func stack_rect(c: Dictionary, size_fn: Callable, cell: float, pad: float = 0.0) -> Rect2:
	var sz: Vector2i = size_fn.call(String(c.item), int(c.rot))
	return Rect2(Vector2(pad + float(c.x) * cell, pad + float(c.y) * cell), Vector2(float(sz.x) * cell, float(sz.y) * cell))


## The index of the stack that covers `cell` (-1 for none).
static func index_at(grid: Dictionary, size_fn: Callable, cell: Vector2i, skip: int = -1) -> int:
	var cells: Array = grid.cells
	for i in cells.size():
		if i == skip:
			continue
		var c: Dictionary = cells[i]
		var sz: Vector2i = size_fn.call(String(c.item), int(c.rot))
		if cell.x >= int(c.x) and cell.x < int(c.x) + sz.x and cell.y >= int(c.y) and cell.y < int(c.y) + sz.y:
			return i
	return -1


## Which cells are taken: Vector2i -> index of the stack (the stack `skip` is not counted: the one being dragged).
static func occupancy(grid: Dictionary, size_fn: Callable, skip: int = -1) -> Dictionary:
	var occ := {}
	var cells: Array = grid.cells
	for i in cells.size():
		if i == skip:
			continue
		var c: Dictionary = cells[i]
		var sz: Vector2i = size_fn.call(String(c.item), int(c.rot))
		for yy in sz.y:
			for xx in sz.x:
				occ[Vector2i(int(c.x) + xx, int(c.y) + yy)] = i
	return occ


## Whether a footprint of `fw` by `fh` cells with its corner at (x, y) lies inside the grid and over no other stack: "free", "outside" (past an edge) or "blocked" (over a stack).
static func fit(grid: Dictionary, size_fn: Callable, x: int, y: int, fw: int, fh: int, skip: int = -1) -> String:
	if x < 0 or y < 0 or x + fw > int(grid.w) or y + fh > int(grid.h):
		return OUTSIDE
	var occ := occupancy(grid, size_fn, skip)
	for yy in fh:
		for xx in fw:
			if occ.has(Vector2i(x + xx, y + yy)):
				return BLOCKED
	return FREE


## The corner of a held item's footprint when the pointer is over `cell` and holds the item by its cell `grab` (0, 0 is its corner).
static func origin(cell: Vector2i, grab: Vector2i) -> Vector2i:
	return cell - grab


## Where a held item would go: {"state": FREE | MERGE | BLOCKED | OUTSIDE, "x", "y" (the corner), "index" (the stack it would join, -1 otherwise)}.
## `item`/`rot`/`count` is what is held, `skip` its place in this grid when it comes from it (it does not block itself), `cap_fn` (item id) -> the most units of one stack.
## A stack of the same item under the pointer with room in it takes the drop (MERGE), as the game's own stacks do.
static func target(grid: Dictionary, size_fn: Callable, cap_fn: Callable, item: String, rot: int, count: int, cell: Vector2i, grab: Vector2i, skip: int = -1) -> Dictionary:
	var o := origin(cell, grab)
	var sz: Vector2i = size_fn.call(item, rot)
	var hit := index_at(grid, size_fn, cell, skip)
	if hit >= 0:
		var h: Dictionary = grid.cells[hit]
		if String(h.item) == item and int(h.count) < int(cap_fn.call(item)):
			return {"state": MERGE, "x": int(h.x), "y": int(h.y), "index": hit, "w": sz.x, "h": sz.y}
	return {"state": fit(grid, size_fn, o.x, o.y, sz.x, sz.y, skip), "x": o.x, "y": o.y, "index": -1, "w": sz.x, "h": sz.y}


## The first place a footprint of `fw` by `fh` fits (row by row), as a Vector2i, or (-1, -1).
static func first_free(grid: Dictionary, size_fn: Callable, fw: int, fh: int) -> Vector2i:
	var occ := occupancy(grid, size_fn)
	for y in range(0, int(grid.h) - fh + 1):
		for x in range(0, int(grid.w) - fw + 1):
			var ok := true
			for yy in fh:
				for xx in fw:
					if occ.has(Vector2i(x + xx, y + yy)):
						ok = false
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Cells taken and cells in all: Vector2i(used, total).
static func fullness(grid: Dictionary, size_fn: Callable) -> Vector2i:
	return Vector2i(occupancy(grid, size_fn).size(), int(grid.w) * int(grid.h))


## The cell of a held item that the pointer holds after a turn: the same cell turned with the item (a corner stays a corner), kept inside the new footprint.
static func turned_grab(grab: Vector2i, fw: int, fh: int) -> Vector2i:
	return Vector2i(clampi(grab.y, 0, maxi(fw - 1, 0)), clampi(grab.x, 0, maxi(fh - 1, 0)))


## Whether a point is over any of the rectangles (the index of the first, -1 for none).
static func rect_hit(rects: Array, p: Vector2) -> int:
	for i in rects.size():
		if (rects[i] as Rect2).has_point(p):
			return i
	return -1


## The size of the cell for a window of `vp` pixels: 48 where there is room, 40 in a small window.
static func cell_for(vp: Vector2) -> float:
	return 40.0 if (vp.y < 700.0 or vp.x < 1100.0) else 48.0
