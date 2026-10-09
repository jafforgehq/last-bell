## The districts of the town and the choices that go with them (One House, TOWNGEN): which kinds of building stand in which district, in what mix, in which wall material and
## under which roof. Data and small pure helpers only; the street network and the lots are
## scripts/town/town_layout.gd, the buildings scripts/town/building_gen.gd.
##
## DISTRICTS (a block belongs to exactly one; the ring of land round the town is "edge"):
##   suburb      detached houses with yards, fences, driveways, a parked car now and then
##   oldtown     dense rows of narrow terraces back to back with alleys, corner shops
##   main        the commercial heart on the main avenue: shops, a diner, a pharmacy, a bank, flats over the road, a supermarket and its car park, a market
##   industrial  warehouses, garages, scrapyards, fenced container yards
##   civic       the church with its bell tower (the landmark), a fire station, a police station, a clinic, a school with grounds
##   park        trees, a pond or a clearing, a playground, picnic tables, paths
##   edge        farmhouses, barns, fields and woods round the border
extends RefCounted

const Recipes := preload("res://scripts/town/building_recipes.gd")

const SUBURB := "suburb"
const OLDTOWN := "oldtown"
const MAIN := "main"
const INDUSTRIAL := "industrial"
const CIVIC := "civic"
const PARK := "park"
const EDGE := "edge"
const ALL := ["suburb", "oldtown", "main", "industrial", "civic", "park", "edge"]

## The colours of the overview picture (tools/town_overview.gd): the ground of each district, tinted.
const GROUND_TINT := {
	"suburb": Color("5f7a45"), "oldtown": Color("7a6a4a"), "main": Color("6d7480"), "industrial": Color("66606a"),
	"civic": Color("7a5a5a"), "park": Color("3f7f3f"), "edge": Color("8a8a3a"),
}

## The material of the outside walls of a district: [the kit's wall item (TownArt.WALL_MATS), weight].
const WALLS := {
	"suburb": [["wall_white", 0.3], ["wall_blue", 0.24], ["wall_stucco", 0.2], ["wall_brick", 0.18], ["wall_sage", 0.08]],
	"oldtown": [["wall_brick", 0.72], ["wall_stucco", 0.14], ["wall_plaster", 0.14]],
	"main": [["wall_brick", 0.5], ["wall_stucco", 0.2], ["wall_plaster", 0.15], ["wall_white", 0.15]],
	"industrial": [["wall_brick", 0.45], ["wall_plaster", 0.3], ["wall_stucco", 0.15], ["wall_white", 0.1]],
	"civic": [["wall_brick", 0.4], ["wall_stucco", 0.3], ["wall_plaster", 0.3]],
	"park": [["wall_timber", 0.6], ["wall_white", 0.4]],
	"edge": [["wall_timber", 0.55], ["wall_white", 0.2], ["wall_brick", 0.15], ["wall_blue", 0.1]],
}

## Roofs of a district: the index of the kit's roofs (0 terracotta, 1 slate, 2 shingle) with weights.
const ROOFS := {
	"suburb": [[0, 0.34], [1, 0.33], [2, 0.33]],
	"oldtown": [[0, 0.45], [1, 0.45], [2, 0.1]],
	"main": [[1, 0.6], [0, 0.25], [2, 0.15]],
	"industrial": [[1, 0.55], [2, 0.45]],
	"civic": [[1, 0.6], [0, 0.4]],
	"park": [[2, 0.6], [0, 0.4]],
	"edge": [[2, 0.55], [0, 0.45]],
}

## What a lot of a district is built with: [building kind, weight]. A kind that does not fit the lot is skipped; "pocket" is a small lot left to trees and grass.
## (WORLD3: a lot more kinds in every district, and a kind has several plans of its own: scripts/town/building_recipes.gd)
const MIX := {
	"suburb": [["family", 0.12], ["medium", 0.10], ["small", 0.04], ["bungalow", 0.08], ["lhouse", 0.06], ["twowing", 0.05], ["thouse", 0.03], ["uhouse", 0.02], ["ranch", 0.12], ["splitlevel", 0.05],
		["duplex", 0.07], ["cabin", 0.03], ["manor", 0.02], ["hhouse", 0.02], ["terrace", 0.04], ["cottage", 0.03], ["pocket", 0.03]],
	"oldtown": [["terrace", 0.26], ["terrace3", 0.06], ["terrace_ext", 0.08], ["townhouse", 0.12], ["duplex", 0.04], ["cottage", 0.04], ["cornershop", 0.06], ["rowshop", 0.08], ["cafe", 0.04], ["barber", 0.015],
		["laundromat", 0.015], ["pub", 0.03], ["butcher", 0.015], ["florist", 0.015], ["small", 0.08], ["pocket", 0.05]],
	"main": [["rowshop", 0.24], ["shop", 0.10], ["apartments", 0.08], ["pharmacy", 0.05], ["bakery", 0.05], ["hardware", 0.04], ["diner", 0.04], ["bank", 0.03], ["office", 0.05], ["cafe", 0.05], ["barber", 0.03],
		["laundromat", 0.03], ["pub", 0.04], ["butcher", 0.03], ["florist", 0.03], ["strip", 0.04], ["agency", 0.03], ["surgery", 0.02], ["officeblock", 0.02], ["gas_station", 0.03], ["dealer", 0.02],
		["cornershop", 0.02], ["kiosk", 0.02], ["pocket", 0.02]],
	"industrial": [["warehouse", 0.14], ["factory", 0.10], ["garage", 0.14], ["workshop", 0.14], ["scrapyard", 0.08], ["containers", 0.06], ["carwash", 0.03], ["storage", 0.06], ["depot", 0.04],
		["substation", 0.04], ["lumber", 0.05], ["coldstore", 0.04], ["gas_station", 0.04], ["dealer", 0.02]],
	"civic": [["library", 0.10], ["clinic", 0.06], ["small", 0.06], ["medium", 0.10], ["family", 0.05], ["office", 0.05], ["terrace", 0.04], ["townhall", 0.04], ["postoffice", 0.06], ["chapel", 0.04],
		["hall", 0.06], ["museum", 0.04], ["cinema", 0.03], ["radio_station", 0.03], ["kindergarten", 0.05], ["courthouse", 0.03], ["surgery", 0.03], ["pocket", 0.06]],
	"edge": [["farmhouse", 0.5], ["barn", 0.5]],
}


## The type of each building kind (the `type` of a house): residential, commercial, industrial, civic, farm.
const TYPE_OF := {
	"start": "residential", "family": "residential", "small": "residential", "medium": "residential", "bungalow": "residential", "lhouse": "residential", "thouse": "residential", "uhouse": "residential",
	"twowing": "residential", "terrace": "residential", "terrace_ext": "residential", "apartments": "residential", "cottage": "residential",
	"shed": "outbuilding", "kiosk": "commercial", "rowshop": "commercial",
	"cornershop": "commercial", "shop": "commercial", "pharmacy": "commercial", "bakery": "commercial", "hardware": "commercial", "diner": "commercial", "bank": "commercial",
	"office": "commercial", "supermarket": "commercial",
	"warehouse": "industrial", "garage": "industrial", "workshop": "industrial", "scrapyard": "industrial", "containers": "industrial",
	"church": "civic", "school": "civic", "fire_station": "civic", "police": "civic", "clinic": "civic", "library": "civic",
	"farmhouse": "farm", "barn": "farm",
}


## The type of a building kind (the old kinds' table above, the new kinds' in scripts/town/building_recipes.gd), "residential" when it is in neither.
static func type_of(kind: String) -> String:
	if TYPE_OF.has(kind):
		return String(TYPE_OF[kind])
	var nk = Recipes.NEW_KINDS.get(kind)
	return String(nk[0]) if nk != null else "residential"


static func pick(list: Array, rng: RandomNumberGenerator):
	var total := 0.0
	for it in list:
		total += float(it[1])
	var at := rng.randf() * total
	for it in list:
		at -= float(it[1])
		if at < 0.0:
			return it[0]
	return list[list.size() - 1][0]


## The kit's wall item of a district's outside walls, as the code of `data.kit.wall` (the index in TownArt.WALL_MATS; 1 brick when the name is not known).
static func wall_code_for(district: String, rng: RandomNumberGenerator, mats: Array) -> int:
	var name := String(pick(WALLS.get(district, WALLS.suburb), rng))
	return maxi(1, mats.find(name))


static func roof_for(district: String, rng: RandomNumberGenerator) -> int:
	return int(pick(ROOFS.get(district, ROOFS.suburb), rng))
