## The colours of the town's roofs (WORLD3): the three kits are a terracotta, a slate and a shingle; a roof's `facade.tint_id` turns its kit's pictures into one of five colours of that kit (a maroon, a
## sand, a charcoal, a green-grey, a blue, a moss...). A tint is a colour the kit's picture is multiplied by, so the shading of the art stays. Data and one lookup, no state.
extends RefCounted

## [kit][tint id]: the multiplier. Kit 0 terracotta, 1 slate, 2 shingle.
const TINTS := [
	[Color(1.0, 1.0, 1.0), Color(0.80, 0.62, 0.60), Color(1.08, 1.02, 0.80), Color(0.90, 0.76, 0.70), Color(1.08, 0.90, 0.84)],
	[Color(1.0, 1.0, 1.0), Color(0.62, 0.82, 0.70), Color(0.60, 0.60, 0.64), Color(1.08, 1.06, 1.0), Color(0.74, 0.84, 1.06)],
	[Color(1.0, 1.0, 1.0), Color(0.58, 0.58, 0.62), Color(0.80, 0.94, 0.80), Color(1.10, 1.06, 1.0), Color(0.92, 0.80, 0.72)],
]
## The tint of a roof of a house that burnt: nearly black.
const CHARRED := Color(0.40, 0.37, 0.36)
## The weights of the five tints a roof may have (the kit's own colour is the most common).
const WEIGHTS := [0.34, 0.18, 0.16, 0.16, 0.16]
## The flat roofs' fills and their weights by district (the names of the extras).
const FLATS := {
	"main": [["flat_tar", 3.0], ["flat_gravel", 2.0], ["flat_concrete", 1.0], ["flat_green", 0.5]],
	"oldtown": [["flat_tar", 2.0], ["flat_gravel", 1.0], ["flat_sand", 1.5], ["flat_green", 1.0], ["flat_metal", 0.5]],
	"industrial": [["flat_tar", 2.0], ["flat_gravel", 2.0], ["flat_metal", 2.0], ["flat_concrete", 1.0]],
	"civic": [["flat_concrete", 2.0], ["flat_tar", 2.0], ["flat_gravel", 1.0], ["flat_green", 0.6]],
	"suburb": [["flat_tar", 2.5], ["flat_gravel", 1.0], ["flat_sand", 1.2], ["flat_green", 0.8]],
	"edge": [["flat_metal", 2.0], ["flat_tar", 1.0], ["flat_sand", 1.0]],
}


static func tint(kit: int, id: int) -> Color:
	if id < 0:
		return CHARRED
	var row: Array = TINTS[clampi(kit, 0, TINTS.size() - 1)]
	return row[clampi(id, 0, row.size() - 1)]
