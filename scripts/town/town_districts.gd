## The districts of the town and the choices that go with them (One House, TOWNGEN): which kinds of building stand in which district, in what mix, in which wall material and
## under which roof, and the extra ground and wall terrains the town uses beyond the base map's. Data and small pure helpers only; the street network and the lots are
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

## The ground and wall terrains the town adds (ids well clear of the base map's 1 to 13 and the site layouts' 20 to 23). The pictures are 512 x 512 atlases of 128 px pieces
## made by tools/make_town_terrain.gd from the art kit's wall fills; when a picture is not there the name is an alias of a base terrain (see `terrains`).
const TERRAINS := {
	"WALL_WHITE": {"id": 40, "file": "res://assets/terrain/wall_white.png", "alias": "WALL_PLASTER"},
	"WALL_BLUE": {"id": 41, "file": "res://assets/terrain/wall_blue.png", "alias": "WALL_PLASTER"},
	"WALL_STUCCO": {"id": 42, "file": "res://assets/terrain/wall_stucco.png", "alias": "WALL_PLASTER"},
	"WALL_TIMBER": {"id": 43, "file": "res://assets/terrain/wall_timber.png", "alias": "WALL_BRICK"},
	"WATER": {"id": 44, "file": "res://assets/terrain/water.png", "alias": "SOIL"},
}

## Walls of a district: [terrain name, weight].
const WALLS := {
	"suburb": [["WALL_WHITE", 0.3], ["WALL_BLUE", 0.24], ["WALL_STUCCO", 0.2], ["WALL_BRICK", 0.18], ["WALL_PLASTER", 0.08]],
	"oldtown": [["WALL_BRICK", 0.72], ["WALL_STUCCO", 0.14], ["WALL_PLASTER", 0.14]],
	"main": [["WALL_BRICK", 0.5], ["WALL_STUCCO", 0.2], ["WALL_PLASTER", 0.15], ["WALL_WHITE", 0.15]],
	"industrial": [["WALL_METAL", 0.55], ["WALL_BRICK", 0.35], ["WALL_PLASTER", 0.1]],
	"civic": [["WALL_BRICK", 0.4], ["WALL_STUCCO", 0.3], ["WALL_PLASTER", 0.3]],
	"park": [["WALL_TIMBER", 0.6], ["WALL_WHITE", 0.4]],
	"edge": [["WALL_TIMBER", 0.55], ["WALL_WHITE", 0.2], ["WALL_BRICK", 0.15], ["WALL_BLUE", 0.1]],
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
const MIX := {
	"suburb": [["small", 0.24], ["medium", 0.18], ["bungalow", 0.07], ["lhouse", 0.09], ["twowing", 0.07], ["thouse", 0.04], ["uhouse", 0.03], ["terrace", 0.12], ["cottage", 0.14], ["pocket", 0.02]],
	"oldtown": [["terrace", 0.42], ["terrace_ext", 0.16], ["cottage", 0.12], ["cornershop", 0.08], ["rowshop", 0.1], ["small", 0.09], ["pocket", 0.03]],
	"main": [["rowshop", 0.44], ["shop", 0.1], ["apartments", 0.08], ["pharmacy", 0.06], ["bakery", 0.06], ["hardware", 0.05], ["diner", 0.05], ["bank", 0.03], ["office", 0.06], ["pocket", 0.02]],
	"industrial": [["warehouse", 0.2], ["garage", 0.26], ["scrapyard", 0.12], ["containers", 0.1], ["workshop", 0.32]],
	"civic": [["library", 0.2], ["clinic", 0.1], ["small", 0.18], ["medium", 0.17], ["office", 0.1], ["terrace", 0.1], ["pocket", 0.15]],
	"edge": [["farmhouse", 0.5], ["barn", 0.5]],
}


## The type of each building kind (the `type` of a house): residential, commercial, industrial, civic, farm.
const TYPE_OF := {
	"start": "residential", "small": "residential", "medium": "residential", "bungalow": "residential", "lhouse": "residential", "thouse": "residential", "uhouse": "residential",
	"twowing": "residential", "terrace": "residential", "terrace_ext": "residential", "apartments": "residential", "cottage": "residential",
	"shed": "outbuilding", "kiosk": "commercial", "rowshop": "commercial",
	"cornershop": "commercial", "shop": "commercial", "pharmacy": "commercial", "bakery": "commercial", "hardware": "commercial", "diner": "commercial", "bank": "commercial",
	"office": "commercial", "supermarket": "commercial",
	"warehouse": "industrial", "garage": "industrial", "workshop": "industrial", "scrapyard": "industrial", "containers": "industrial",
	"church": "civic", "school": "civic", "fire_station": "civic", "police": "civic", "clinic": "civic", "library": "civic",
	"farmhouse": "farm", "barn": "farm",
}


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


## The terrain types the town adds, as {name: {"id", "file"}} (the ones whose picture is there) and the aliases of the others, {name: base name}.
static func terrains() -> Dictionary:
	var types := {}
	var alias := {}
	for k in TERRAINS:
		var t: Dictionary = TERRAINS[k]
		if ResourceLoader.exists(String(t.file)) or FileAccess.file_exists(String(t.file)):
			types[k] = {"id": int(t.id), "file": String(t.file)}
		else:
			alias[k] = String(t.alias)
	return {"types": types, "alias": alias}


static func wall_for(district: String, rng: RandomNumberGenerator) -> String:
	return String(pick(WALLS.get(district, WALLS.suburb), rng))


static func roof_for(district: String, rng: RandomNumberGenerator) -> int:
	return int(pick(ROOFS.get(district, ROOFS.suburb), rng))
