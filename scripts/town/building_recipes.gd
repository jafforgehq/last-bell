## The RECIPES of the town's buildings (WORLD3, "a lot more variants of buildings"): data only. A recipe is one PLAN: a footprint (a shape and its sizes), a room program, and the
## features of its front (a porch, an awning, a canopy, a sign, the roofs it may have). `BuildingPlans.plan(kind, avail_w, depth, rng)` draws one of the recipes of a kind that fits the lot
## (`avail_w` tiles of the row, `depth` of its depth); `BuildingGen` builds it and writes the `facade` the roofs are drawn from (scripts/render/house_view.gd).
##
## A RECIPE: {"id", "k" (the kind: what the layout and the rules call it), "s" (the shape), the shape's sizes ("w", "h": [least, most] tiles, the others by shape), "m" (the yard to each side),
## "fy" (the front yard), "prog" (the program, `PROGS`; the id by default), "wt" (the weight among the kind's recipes), "f" (the features), "name"}. Shapes: "legacy" (the plan code of
## scripts/town/building_plans.gd that was there before), "rect", "L", "side" (a main part and a part beside it: a garage, a wing), "back" (a part behind), "front" (a part that stands out
## at the front), "H" (two wings and a link), "units" (n of the same unit side by side, each with its own front door: a semi, a terrace, a strip of shops, a motel), "manor" (a centre and two
## wings), "step" (two parts offset). FEATURES: "porch" ("front", "wrap"), "awn" (the colour of an awning over the front), "canopy" ("gas", "carport", "dock"), "sign" (the icon on the front),
## "roof" ({style: weight}: "gable", "hip", "flat", "lean", "saw"), "chim", "ac", "dish", "solar" (the chance of each), "mat" (the outside wall's material), "court" (a paved court),
## "yard" (what the lot has: "cars", "pens", "stacks", "wrecks"), "units" (n), "door2" (a second front door).
extends RefCounted

## The category of each kind, for the catalogue and the census (houses, apartment blocks, shops, offices, industrial, civic, farm, outbuildings).
const CATEGORY := {
	"start": "house", "family": "house", "medium": "house", "small": "house", "bungalow": "house", "lhouse": "house", "thouse": "house", "uhouse": "house", "twowing": "house", "terrace": "house",
	"terrace_ext": "house", "cottage": "house", "ranch": "house", "splitlevel": "house", "duplex": "house", "cabin": "house", "manor": "house", "townhouse": "house", "hhouse": "house", "terrace3": "house",
	"apartments": "apartments",
	"kiosk": "shop", "rowshop": "shop", "cornershop": "shop", "shop": "shop", "pharmacy": "shop", "bakery": "shop", "hardware": "shop", "diner": "shop", "supermarket": "shop", "cafe": "shop",
	"barber": "shop", "laundromat": "shop", "pub": "shop", "butcher": "shop", "florist": "shop", "dealer": "shop", "gas_station": "shop", "strip": "shop",
	"office": "office", "bank": "office", "officeblock": "office", "agency": "office", "surgery": "office",
	"warehouse": "industrial", "garage": "industrial", "workshop": "industrial", "scrapyard": "industrial", "containers": "industrial", "factory": "industrial", "carwash": "industrial",
	"storage": "industrial", "depot": "industrial", "substation": "industrial", "lumber": "industrial", "coldstore": "industrial",
	"church": "civic", "school": "civic", "fire_station": "civic", "police": "civic", "clinic": "civic", "library": "civic", "townhall": "civic", "postoffice": "civic", "chapel": "civic",
	"hall": "civic", "museum": "civic", "cinema": "civic", "radio_station": "civic", "kindergarten": "civic", "courthouse": "civic",
	"farmhouse": "farm", "barn": "farm", "silo": "farm", "coop": "farm", "greenhouse": "farm", "tractor_shed": "farm", "grain_store": "farm", "stable": "farm",
	"shed": "outbuilding",
}

## The kinds that are a home, and the other facts of the new kinds ([type, dead least, dead most]); the old kinds' are where they always were (town_districts.gd `TYPE_OF`, town_gen.gd `DEAD_BY_KIND`).
const NEW_KINDS := {
	"ranch": ["residential", 1, 4], "splitlevel": ["residential", 2, 4], "duplex": ["residential", 2, 5], "cabin": ["residential", 1, 3], "manor": ["residential", 3, 6], "townhouse": ["residential", 1, 3],
	"hhouse": ["residential", 2, 5], "terrace3": ["residential", 2, 5],
	"cafe": ["commercial", 1, 3], "barber": ["commercial", 0, 2], "laundromat": ["commercial", 0, 2], "pub": ["commercial", 2, 4], "butcher": ["commercial", 1, 2], "florist": ["commercial", 0, 2],
	"dealer": ["commercial", 1, 3], "gas_station": ["commercial", 1, 3], "strip": ["commercial", 2, 5],
	"officeblock": ["commercial", 2, 5], "agency": ["commercial", 1, 2], "surgery": ["commercial", 1, 3],
	"factory": ["industrial", 4, 8], "carwash": ["industrial", 1, 3], "storage": ["industrial", 2, 5], "depot": ["industrial", 3, 6], "substation": ["industrial", 0, 2], "lumber": ["industrial", 1, 3],
	"coldstore": ["industrial", 3, 6],
	"townhall": ["civic", 3, 6], "postoffice": ["civic", 2, 4], "chapel": ["civic", 1, 3], "hall": ["civic", 2, 5], "museum": ["civic", 2, 4], "cinema": ["civic", 3, 6], "radio_station": ["civic", 1, 3],
	"kindergarten": ["civic", 2, 5], "courthouse": ["civic", 3, 6],
	"silo": ["farm", 0, 2], "coop": ["farm", 0, 2], "greenhouse": ["farm", 0, 2], "tractor_shed": ["farm", 0, 2], "grain_store": ["farm", 1, 3], "stable": ["farm", 1, 3],
}

## The names the player sees (a candidate's label, the catalogue): the kind's, else the id of a plan.
const NAMES := {
	"ranch": "Ranch house", "splitlevel": "Split-level house", "duplex": "Semi-detached house", "cabin": "Cabin", "manor": "Manor", "townhouse": "Townhouse", "hhouse": "House", "terrace3": "Terrace row",
}

# ===================================================================== the programs ==
## Rooms by program: parts divided by " | ", rooms by ", ", each "name:share:FLOOR:flags" (e the front door opens into it, f it wants the front of its part, b the back). A program that is not here is the
## kind's own (`BuildingPlans._programs`).
const PROGS := {
	"ranch": "living room:3.2:WOOD:ef, kitchen:2.2:KITCHEN:b, dining room:1.6:WOOD:b, bedroom:2.4:WOOD:b, bathroom:1.1:KITCHEN:b, bedroom:2.2:WOOD:b, bedroom:2.0:WOOD:b",
	"ranch_garage": "living room:3.2:WOOD:ef, kitchen:2.2:KITCHEN:b, bedroom:2.4:WOOD:b, bathroom:1.1:KITCHEN:b, bedroom:2.2:WOOD:b | garage:1:CONCRETE:ef",
	"ranch_L": "living room:3.0:WOOD:ef, kitchen:2.2:KITCHEN, dining room:1.8:WOOD | bedroom:2.4:WOOD, bedroom:2.4:WOOD, bathroom:1.1:KITCHEN, study:1.4:WOOD",
	"split": "living room:3.0:WOOD:ef, kitchen:2.2:KITCHEN, dining room:1.6:WOOD | bedroom:2.4:WOOD, bedroom:2.2:WOOD, bathroom:1.1:KITCHEN, study:1.4:WOOD",
	"split_garage": "living room:3.0:WOOD:ef, kitchen:2.2:KITCHEN, dining room:1.6:WOOD, bedroom:2.4:WOOD, bathroom:1.1:KITCHEN, bedroom:2.2:WOOD | garage:1:CONCRETE:ef",
	"cabin": "living room:3.0:WOOD:ef, kitchen:1.8:KITCHEN:b, bedroom:2.2:WOOD:b, bathroom:1.0:KITCHEN:b",
	"cabin_L": "living room:3.0:WOOD:ef, kitchen:1.8:KITCHEN | bedroom:2.2:WOOD, bathroom:1.0:KITCHEN",
	"lodge": "living room:3.4:WOOD:ef, kitchen:2.2:KITCHEN:b, dining room:1.8:WOOD:b, bedroom:2.4:WOOD:b, bedroom:2.2:WOOD:b, bathroom:1.1:KITCHEN:b, study:1.4:WOOD:b",
	"manor": "hall:2.0:WOOD:e, living room:3.4:WOOD:f, dining room:2.0:WOOD:b, study:1.6:WOOD:b | kitchen:2.4:KITCHEN, utility:1.4:LINO, pantry:1.0:KITCHEN | bedroom:2.4:WOOD, bedroom:2.4:WOOD, bathroom:1.1:KITCHEN, nursery:1.4:WOOD",
	"townhouse": "front room:3.0:WOOD:ef, kitchen:2.0:KITCHEN:b, bedroom:2.4:WOOD:b, bedroom:2.0:WOOD:b, bathroom:1.0:KITCHEN:b",
	"hhouse": "living room:3.0:WOOD:ef, kitchen:2.2:KITCHEN, dining room:1.6:WOOD | bedroom:2.4:WOOD, bedroom:2.4:WOOD, bathroom:1.1:KITCHEN | study:1.0:WOOD",
	"family_garage": "hall:2.0:WOOD:e, living room:3.4:WOOD:f, kitchen:2.4:KITCHEN:b, bedroom:2.6:WOOD:b, bedroom:2.4:WOOD:b, bathroom:1.2:KITCHEN:b, utility:1.6:LINO:b, bedroom:2.2:WOOD:b | garage:1:CONCRETE:ef",
	"family_bay": "living room:1:WOOD:ef | hall:2.0:WOOD:e, kitchen:2.4:KITCHEN:b, bedroom:2.6:WOOD:b, bedroom:2.4:WOOD:b, bathroom:1.2:KITCHEN:b, dining room:1.8:WOOD:b, study:1.6:WOOD:b, bedroom:2.2:WOOD:b",
	"bungalow_nogarage": "living room:3.2:WOOD:ef, kitchen:2.2:KITCHEN:b, bedroom:2.4:WOOD:b, bathroom:1.1:KITCHEN:b, bedroom:2.2:WOOD:b, dining room:1.6:WOOD:b",
	"bungalow_wing": "living room:3.2:WOOD:ef, kitchen:2.2:KITCHEN:b, dining room:1.6:WOOD:b, bathroom:1.1:KITCHEN:b | bedroom:2.4:WOOD, bedroom:2.2:WOOD, study:1.4:WOOD",
	"unit_home": "front room:3.0:WOOD:ef, kitchen:2.0:KITCHEN:b, bedroom:2.2:WOOD:b, bathroom:1.0:KITCHEN:b, bedroom:2.0:WOOD:b",
	"unit_terrace": "front room:3.0:WOOD:ef, kitchen:2.0:KITCHEN:b, bedroom:2.2:WOOD:b, bathroom:1.0:KITCHEN:b",
	"unit_motel": "bedroom:3.0:WOOD:ef, bathroom:1.2:KITCHEN:b",
	"unit_shop": "shop floor:4.0:LINO:ef, storeroom:1.2:WOOD:b",
	"unit_store": "storeroom:1:CONCRETE:ef",
	"unit_office": "reception:1.6:TERRAZZO:ef, office:2.0:WOOD:b",
	"cafe": "dining hall:5.0:LINO:ef, kitchen:2.2:KITCHEN:b, storeroom:1.0:WOOD:b, bathroom:1.0:KITCHEN:b",
	"barber": "salon:4.0:LINO:ef, storeroom:1.2:WOOD:b, bathroom:1.0:KITCHEN:b",
	"laundromat": "laundromat:5.0:LINO:ef, storeroom:1.2:WOOD:b, bathroom:1.0:KITCHEN:b",
	"pub": "bar:5.0:WOOD:ef, kitchen:2.0:KITCHEN:b, storeroom:1.2:WOOD:b, bathroom:1.0:KITCHEN:b",
	"butcher": "shop floor:4.0:LINO:ef, cold room:2.0:CONCRETE:b, storeroom:1.0:WOOD:b",
	"florist": "shop floor:4.0:LINO:ef, storeroom:1.2:WOOD:b",
	"barber_b": "salon:4.0:LINO:ef, office:1.2:WOOD:b, storeroom:1.0:WOOD:b",
	"laundromat_b": "laundromat:5.0:LINO:ef, bathroom:1.0:KITCHEN:b",
	"drycleaner": "front desk:2.5:LINO:ef, laundromat:3.0:LINO:b, storeroom:1.0:WOOD:b",
	"deli": "shop floor:4.0:LINO:ef, kitchen:2.0:KITCHEN:b, storeroom:1.0:WOOD:b",
	"newsagent": "shop floor:4.0:LINO:ef, storeroom:1.2:WOOD:b, bathroom:1.0:KITCHEN:b",
	"dealer": "showroom:5.0:TERRAZZO:ef, office:1.6:WOOD:b, storeroom:1.0:CONCRETE:b",
	"gas_station": "shop floor:3.0:LINO:ef, storeroom:1.2:WOOD:b, bathroom:1.0:KITCHEN:b",
	"agency": "reception:2.0:TERRAZZO:ef, office:2.0:WOOD:b, office:2.0:WOOD:b, bathroom:1.0:KITCHEN:b",
	"surgery": "waiting room:3.0:TERRAZZO:ef, ward:2.0:TERRAZZO:b, ward:2.0:TERRAZZO:b, pharmacy:1.4:TERRAZZO:b, bathroom:1.0:KITCHEN:b",
	"factory": "workshop:8.0:CONCRETE:ef, storeroom:2.0:CONCRETE:b | office:1.6:WOOD:ef, office:1.4:WOOD:b, bathroom:1.0:KITCHEN:b",
	"factory_saw": "workshop:9.0:CONCRETE:ef, storeroom:2.0:CONCRETE:b, office:1.4:WOOD:b",
	"carwash": "workshop:5.0:CONCRETE:ef, storeroom:1.0:CONCRETE:b",
	"depot": "workshop:7.0:CONCRETE:ef, office:1.6:WOOD:b, storeroom:1.5:CONCRETE:b",
	"substation": "workshop:4.0:CONCRETE:ef, storeroom:1.0:CONCRETE:b",
	"lumber": "workshop:5.0:CONCRETE:ef, storeroom:1.5:WOOD:b",
	"coldstore": "hall:9.0:CONCRETE:e, cold room:3.0:CONCRETE:b, office:1.4:WOOD:b",
	"warehouse_L": "hall:10.0:CONCRETE:e, office:1.6:WOOD:b | hall:6.0:CONCRETE:e",
	"garage_big": "workshop:7.0:CONCRETE:ef, office:1.6:WOOD:b, storeroom:1.2:CONCRETE:b",
	"workshop_L": "workshop:5.0:CONCRETE:ef, storeroom:2.0:CONCRETE:b | workshop:4.0:CONCRETE:e",
	"townhall": "hall:2.0:TERRAZZO:e, reception:3.0:TERRAZZO:f, chamber:3.0:WOOD:b | office:2.0:WOOD, office:2.0:WOOD, bathroom:1.0:KITCHEN | office:2.0:WOOD, office:2.0:WOOD, archive:1.4:WOOD",
	"postoffice": "front desk:3.0:TERRAZZO:ef, storeroom:2.0:CONCRETE:b, office:1.6:WOOD:b, bathroom:1.0:KITCHEN:b",
	"chapel": "nave:3.0:WOOD:ef, chancel:1.0:TERRAZZO:b",
	"hall": "gym:5.0:CONCRETE:ef, kitchen:1.6:KITCHEN:b, storeroom:1.2:WOOD:b, bathroom:1.0:KITCHEN:b",
	"museum": "gallery:5.0:TERRAZZO:ef, gallery:3.0:TERRAZZO:b, storeroom:1.5:CONCRETE:b, office:1.5:WOOD:b",
	"cinema": "lobby:2.0:TERRAZZO:ef, theatre:6.0:WOOD:b, storeroom:1.0:CONCRETE:b",
	"radio_station": "reception:1.6:TERRAZZO:ef, studio:2.5:WOOD:b, office:1.6:WOOD:b, storeroom:1.0:CONCRETE:b",
	"kindergarten": "classroom:3.0:WOOD:ef, classroom:2.0:WOOD:b, kitchen:1.5:KITCHEN:b, bathroom:1.0:KITCHEN:b",
	"courthouse": "lobby:2.0:TERRAZZO:ef, courtroom:4.0:WOOD:b, office:1.6:WOOD:b, cell:1.2:CONCRETE:b, office:1.4:WOOD:b",
	"clinic_L": "waiting room:4.0:TERRAZZO:ef, ward:3.0:TERRAZZO:b, pharmacy:2.0:TERRAZZO:b | ward:3.0:TERRAZZO, ward:3.0:TERRAZZO, bathroom:1.0:KITCHEN, office:1.5:WOOD",
	"hospital": "waiting room:4.0:TERRAZZO:ef, pharmacy:2.0:TERRAZZO:b, office:1.5:WOOD:b | ward:3.0:TERRAZZO, ward:3.0:TERRAZZO, ward:3.0:TERRAZZO, bathroom:1.0:KITCHEN",
	"fire_tower": "engine bay:8.0:CONCRETE:ef, dormitory:3.0:WOOD:b, kitchen:2.0:KITCHEN:b, office:1.6:WOOD:b | storeroom:1:CONCRETE",
	"police_L": "front desk:4.0:TERRAZZO:ef, cell:1.5:CONCRETE:b, cell:1.5:CONCRETE:b, office:2.0:WOOD:b, bathroom:1.0:KITCHEN:b | armoury:2.0:CONCRETE, engine bay:4.0:CONCRETE:e",
	"library_wing": "reading room:5.0:WOOD:ef, office:1.5:WOOD:b | stacks:4.0:WOOD, storeroom:1.0:WOOD",
	"church_T": "narthex:1.0:WOOD:e | nave:1.0:WOOD | chancel:1.0:TERRAZZO | nave:1.0:WOOD | nave:1.0:WOOD",
	"farmhouse_wing": "kitchen:2.2:KITCHEN:ef, living room:3.0:WOOD, bedroom:2.4:WOOD:b, bathroom:1.0:KITCHEN:b | storeroom:1.0:WOOD:ef",
	"farmhouse_T": "kitchen:2.2:KITCHEN:ef, living room:3.0:WOOD, pantry:1.0:KITCHEN:b | bedroom:2.4:WOOD, bedroom:2.2:WOOD, bathroom:1.0:KITCHEN",
	"farmhouse_long": "kitchen:2.2:KITCHEN:ef, living room:3.0:WOOD, dining room:1.6:WOOD:b | bedroom:2.4:WOOD, bedroom:2.4:WOOD, bathroom:1.0:KITCHEN, bedroom:2.0:WOOD",
	"barn_big": "barn:3.0:DIRT:ef, stable:1.2:DIRT:b | barn:2.0:DIRT:e",
	"stable": "stable:3.0:DIRT:ef, store:1.0:WOOD:b",
	"silo": "silo:1:CONCRETE:ef",
	"coop": "coop:1:DIRT:ef",
	"greenhouse": "greenhouse:1:DIRT:ef",
	"tractor_shed": "barn:1:DIRT:ef",
	"grain_store": "barn:3.0:DIRT:ef, store:1.0:WOOD:b",
	"apartments_low": "hall:1:TERRAZZO:e",
	"garden_shed": "shed:1:WOOD:ef",
	"garage_det": "garage:1:CONCRETE:ef",
	"workshop_shed": "workshop:1:WOOD:ef",
	"summerhouse": "summerhouse:1:WOOD:ef",
	"school_U": " | gym:4.0:CONCRETE, storeroom:1.0:CONCRETE:b | classroom:2.0:WOOD, classroom:2.0:WOOD",
	"shop_L": "shop floor:6.0:LINO:ef, storeroom:1.5:WOOD:b | office:1.4:WOOD, storeroom:2.0:WOOD, bathroom:1.0:KITCHEN:b",
	"diner_L": "dining hall:6.0:LINO:ef, kitchen:1.6:KITCHEN:b | kitchen:2.4:KITCHEN, storeroom:1.2:WOOD, bathroom:1.0:KITCHEN",
	"pub_L": "bar:5.0:WOOD:ef, kitchen:1.6:KITCHEN:b | storeroom:1.2:WOOD, bathroom:1.0:KITCHEN, office:1.2:WOOD",
	"supermarket_L": "shop floor:9.0:LINO:ef, office:1.2:WOOD:b | storeroom:3.0:CONCRETE, storeroom:2.0:CONCRETE",
	"bank_L": "banking hall:4.0:TERRAZZO:ef, office:2.0:WOOD:b | vault:1.4:CONCRETE, office:1.5:WOOD",
	"office_L": "reception:2.0:TERRAZZO:ef, office:3.0:WOOD:b | office:3.0:WOOD, office:2.5:WOOD, bathroom:1.0:KITCHEN",
	"bakery_oven": "shop floor:4.0:LINO:ef, storeroom:1.0:WOOD:b, bathroom:1.0:KITCHEN:b | kitchen:3.0:KITCHEN",
	"gas_station_big": "shop floor:3.0:LINO:ef, storeroom:1.2:WOOD:b | workshop:3.0:CONCRETE:ef, storeroom:1.0:CONCRETE",
	"hardware_yard": "shop floor:6.0:LINO:ef, office:1.5:WOOD:b, bathroom:1.0:KITCHEN:b | storeroom:2.0:CONCRETE:ef",
	"cafe_L": "dining hall:5.0:LINO:ef, kitchen:1.6:KITCHEN:b | kitchen:2.4:KITCHEN, storeroom:1.2:WOOD, bathroom:1.0:KITCHEN",
	"pharmacy_L": "shop floor:6.0:LINO:ef, storeroom:1.5:WOOD:b | pharmacy:2.0:TERRAZZO, office:1.4:WOOD, bathroom:1.0:KITCHEN",
	"supermarket_L2": "shop floor:9.0:LINO:ef, office:1.2:WOOD:b | storeroom:3.0:CONCRETE",
}

# ====================================================================== the recipes ==
## Recipes by KIND. Sizes are [least, most]; "m": the yard beside, "fy": the yard in front. A kind with no entry here is planned by the old code of `BuildingPlans`. The first recipe of a legacy kind is
## the plan that kind always had (the arrival's lots ask for "medium", "small" and "cottage" and keep their footprints: only the features of their fronts vary there).
const RECIPES := {
	# ------------------------------------------------------------------------ houses ----
	"family": [
		{"id": "family", "s": "legacy", "wt": 4.0, "name": "Family home", "f": {"chim": 0.7, "roof": {"gable": 2, "hip": 2}}},
		{"id": "family_porch", "s": "rect", "w": [20, 22], "h": [15, 16], "m": [1, 3], "fy": [3, 4], "prog": "family", "wt": 3.0, "name": "Family home with a porch", "f": {"porch": "front", "chim": 0.8, "roof": {"gable": 3, "hip": 1}}},
		{"id": "family_wrap", "s": "rect", "w": [20, 22], "h": [15, 16], "m": [2, 3], "fy": [3, 4], "prog": "family", "wt": 1.5, "name": "Family home with a veranda", "f": {"porch": "wrap", "chim": 0.5, "roof": {"hip": 3, "gable": 1}}},
		{"id": "family_garage", "s": "side", "w": [14, 16], "h": [12, 13], "gw": 7, "gh": 8, "m": [1, 2], "fy": [2, 3], "prog": "family_garage", "garage": 1, "wt": 2.0, "name": "Family home with a garage", "f": {"chim": 0.6, "roof": {"gable": 3, "hip": 1}}},
		{"id": "family_bay", "s": "front", "w": [18, 20], "h": [11, 12], "fw": 8, "fh": 6, "m": [1, 3], "fy": [2, 3], "prog": "family_bay", "wt": 1.5, "name": "Family home with a bay", "f": {"chim": 0.6, "roof": {"gable": 2, "hip": 2}}},
	],
	"medium": [
		{"id": "medium", "s": "legacy", "wt": 4.0, "name": "House", "f": {"chim": 0.6, "roof": {"gable": 3, "hip": 1}}},
		{"id": "medium_porch", "s": "legacy", "wt": 2.0, "name": "House with a porch", "f": {"porch": "front", "chim": 0.6, "roof": {"gable": 3, "hip": 2}}},
		{"id": "medium_carport", "s": "legacy", "wt": 1.0, "name": "House with a carport", "f": {"canopy": "carport", "chim": 0.5, "roof": {"gable": 3, "lean": 1}}},
	],
	"small": [
		{"id": "small", "s": "legacy", "wt": 3.0, "name": "Small house", "f": {"chim": 0.6, "roof": {"gable": 4, "hip": 1}}},
		{"id": "small_porch", "s": "legacy", "wt": 2.0, "name": "Small house with a porch", "f": {"porch": "front", "chim": 0.5, "roof": {"gable": 3, "hip": 2}}},
	],
	"cottage": [
		{"id": "cottage", "s": "legacy", "wt": 3.0, "name": "Cottage", "f": {"chim": 0.9, "roof": {"gable": 3, "hip": 1}}},
		{"id": "cottage_porch", "s": "legacy", "wt": 2.0, "name": "Cottage with a porch", "f": {"porch": "front", "chim": 0.8, "roof": {"gable": 2, "hip": 2}}},
	],
	"bungalow": [
		{"id": "bungalow", "s": "legacy", "wt": 3.0, "name": "Bungalow with a garage", "f": {"chim": 0.4, "roof": {"hip": 3, "gable": 2}}},
		{"id": "bungalow_porch", "s": "rect", "w": [14, 16], "h": [10, 11], "m": [2, 4], "fy": [2, 3], "prog": "bungalow_nogarage", "wt": 2.0, "name": "Bungalow with a porch", "f": {"porch": "front", "chim": 0.5, "roof": {"hip": 3, "gable": 2}}},
		{"id": "bungalow_wing", "s": "side", "w": [12, 14], "h": [10, 11], "gw": 8, "gh": 9, "m": [1, 3], "fy": [2, 3], "prog": "bungalow_wing", "wt": 1.5, "name": "Bungalow with a wing", "f": {"chim": 0.5, "roof": {"hip": 2, "gable": 2}}},
	],
	"lhouse": [
		{"id": "lhouse", "s": "legacy", "wt": 3.0, "name": "L-shaped house", "f": {"chim": 0.6, "roof": {"gable": 3, "hip": 2}}},
		{"id": "lhouse_porch", "s": "L", "w": [18, 20], "h": [9, 10], "w2": [11, 12], "h2": [9, 10], "m": [2, 4], "fy": [2, 3], "prog": "lhouse", "wt": 2.0, "name": "L-shaped house with a porch", "f": {"porch": "wrap", "chim": 0.6, "roof": {"gable": 3, "hip": 1}}},
		{"id": "lhouse_big", "s": "L", "w": [20, 22], "h": [10, 11], "w2": [12, 13], "h2": [10, 11], "m": [1, 3], "fy": [2, 3], "prog": "lhouse", "wt": 1.0, "name": "Large L-shaped house", "f": {"chim": 0.8, "roof": {"hip": 2, "gable": 2}}},
	],
	"thouse": [
		{"id": "thouse", "s": "legacy", "wt": 2.0, "name": "T-shaped house", "f": {"chim": 0.6, "roof": {"gable": 3, "hip": 1}}},
		{"id": "thouse_porch", "s": "legacy", "wt": 1.0, "name": "T-shaped house with a porch", "f": {"porch": "front", "chim": 0.5, "roof": {"gable": 2, "hip": 2}}},
	],
	"uhouse": [
		{"id": "uhouse", "s": "legacy", "wt": 2.0, "name": "U-shaped house", "f": {"chim": 0.7, "roof": {"gable": 3, "hip": 1}}},
		{"id": "uhouse_court", "s": "legacy", "wt": 1.0, "name": "Courtyard house", "f": {"court": 1, "chim": 0.7, "roof": {"hip": 3, "gable": 1}}},
	],
	"twowing": [
		{"id": "twowing", "s": "legacy", "wt": 2.0, "name": "Two-wing house", "f": {"chim": 0.6, "roof": {"gable": 3, "hip": 1}}},
		{"id": "twowing_porch", "s": "legacy", "wt": 1.0, "name": "Two-wing house with a porch", "f": {"porch": "front", "chim": 0.5, "roof": {"gable": 2, "hip": 2}}},
	],
	"ranch": [
		{"id": "ranch", "s": "rect", "w": [18, 20], "h": [9, 10], "m": [2, 4], "fy": [2, 3], "prog": "ranch", "wt": 3.0, "name": "Ranch house", "f": {"chim": 0.4, "roof": {"hip": 3, "gable": 2, "lean": 1}}},
		{"id": "ranch_garage", "s": "side", "w": [14, 16], "h": [9, 10], "gw": 7, "gh": 7, "m": [1, 2], "fy": [2, 3], "prog": "ranch_garage", "garage": 1, "wt": 2.0, "name": "Ranch house with a garage", "f": {"chim": 0.3, "roof": {"hip": 3, "gable": 2}}},
		{"id": "ranch_L", "s": "L", "w": [16, 18], "h": [9, 10], "w2": [10, 11], "h2": [9, 10], "m": [2, 3], "fy": [2, 3], "prog": "ranch_L", "wt": 1.5, "name": "L-shaped ranch", "f": {"chim": 0.4, "roof": {"hip": 3, "gable": 1}}},
		{"id": "ranch_porch", "s": "rect", "w": [18, 20], "h": [9, 10], "m": [2, 4], "fy": [3, 4], "prog": "ranch", "wt": 1.5, "name": "Ranch house with a veranda", "f": {"porch": "wrap", "chim": 0.3, "roof": {"hip": 3, "lean": 1}}},
	],
	"splitlevel": [
		{"id": "split_level", "s": "step", "w": [12, 14], "h": [9, 10], "w2": [10, 11], "h2": [8, 9], "m": [1, 3], "fy": [2, 3], "prog": "split", "wt": 2.0, "name": "Split-level house", "f": {"chim": 0.5, "levels": 1, "roof": {"gable": 2, "hip": 1, "lean": 2}}},
		{"id": "split_garage", "s": "side", "w": [14, 16], "h": [10, 11], "gw": 7, "gh": 7, "m": [1, 2], "fy": [2, 3], "prog": "split_garage", "garage": 1, "wt": 1.5, "name": "Split-level with a garage", "f": {"chim": 0.5, "levels": 1, "roof": {"gable": 2, "lean": 2}}},
	],
	"duplex": [
		{"id": "duplex", "s": "units", "n": 2, "w": [9, 10], "h": [9, 10], "m": [1, 2], "fy": [2, 3], "prog": "unit_home", "wt": 3.0, "name": "Semi-detached pair", "f": {"chim": 0.8, "roof": {"gable": 4, "hip": 1}}},
		{"id": "duplex_porch", "s": "units", "n": 2, "w": [10, 11], "h": [9, 10], "m": [1, 2], "fy": [3, 4], "prog": "unit_home", "wt": 1.5, "name": "Semi-detached pair with porches", "f": {"porch": "front", "chim": 0.8, "roof": {"gable": 3, "hip": 2}}},
	],
	"cabin": [
		{"id": "cabin", "s": "rect", "w": [10, 12], "h": [8, 9], "m": [2, 5], "fy": [2, 3], "prog": "cabin", "wt": 3.0, "name": "Cabin", "f": {"porch": "front", "mat": "wall_timber", "chim": 1.0, "roof": {"gable": 4, "lean": 1}}},
		{"id": "cabin_L", "s": "L", "w": [10, 12], "h": [7, 8], "w2": [6, 7], "h2": [7, 8], "m": [2, 5], "fy": [2, 3], "prog": "cabin_L", "wt": 1.5, "name": "L-shaped cabin", "f": {"mat": "wall_timber", "chim": 1.0, "roof": {"gable": 4, "lean": 1}}},
		{"id": "lodge", "s": "rect", "w": [14, 16], "h": [10, 11], "m": [2, 4], "fy": [3, 4], "prog": "lodge", "wt": 1.0, "name": "Lodge", "f": {"porch": "wrap", "mat": "wall_timber", "chim": 1.0, "roof": {"hip": 3, "gable": 2}}},
	],
	"manor": [
		{"id": "manor", "s": "manor", "w": [9, 10], "h": [12, 13], "w2": [8, 9], "h2": [9, 10], "m": [1, 2], "fy": [2, 3], "prog": "manor", "wt": 1.0, "name": "Manor", "f": {"chim": 1.0, "porch": "front", "roof": {"hip": 4, "gable": 1}}},
	],
	"townhouse": [
		{"id": "townhouse", "s": "rect", "w": [7, 8], "h": [12, 13], "m": [0, 0], "fy": [1, 2], "prog": "townhouse", "wt": 3.0, "name": "Townhouse", "f": {"chim": 0.7, "roof": {"gable": 3, "flat": 2, "lean": 1}}},
		{"id": "townhouse_mews", "s": "rect", "w": [6, 7], "h": [10, 11], "m": [0, 0], "fy": [1, 2], "prog": "townhouse", "wt": 1.5, "name": "Mews house", "f": {"chim": 0.5, "roof": {"flat": 3, "lean": 2, "gable": 1}}},
	],
	"hhouse": [
		{"id": "h_house", "s": "H", "w": [20, 22], "h": [9, 10], "w2": [7, 7], "h2": [5, 5], "m": [1, 3], "fy": [2, 3], "prog": "hhouse", "wt": 1.0, "name": "H-shaped house", "f": {"chim": 0.7, "roof": {"gable": 3, "hip": 2}}},
	],
	"terrace": [
		{"id": "terrace", "s": "legacy", "wt": 3.0, "name": "Terrace house", "f": {"chim": 0.9, "roof": {"gable": 3, "flat": 1, "lean": 1}}},
		{"id": "terrace_stoop", "s": "legacy", "wt": 2.0, "name": "Terrace house with a stoop", "f": {"porch": "stoop", "chim": 0.9, "roof": {"gable": 3, "flat": 1}}},
	],
	"terrace_ext": [
		{"id": "terrace_ext", "s": "legacy", "wt": 1.0, "name": "Terrace house with a back wing", "f": {"chim": 0.9, "roof": {"gable": 3, "lean": 1}}},
	],
	"terrace3": [
		{"id": "terrace_row", "s": "units", "n": 3, "w": [8, 8], "h": [10, 11], "m": [0, 0], "fy": [1, 2], "prog": "unit_terrace", "wt": 1.0, "name": "Terrace row of three", "f": {"chim": 0.9, "roof": {"gable": 4, "flat": 1}}},
	],
	# -------------------------------------------------------------------- apartments ----
	"apartments": [
		{"id": "apartments", "s": "legacy", "wt": 3.0, "name": "Block of flats", "f": {"ac": 0.4, "dish": 0.4, "roof": {"flat": 4, "gable": 1}}},
		{"id": "apartments_L", "s": "L", "w": [18, 20], "h": [9, 10], "w2": [10, 11], "h2": [10, 11], "m": [0, 2], "fy": [1, 2], "prog": "apartments", "wt": 1.5, "name": "L-shaped flats", "f": {"ac": 0.5, "dish": 0.5, "roof": {"flat": 4}}},
		{"id": "apartments_U", "s": "legacy_U", "w": [20, 22], "h": [13, 14], "m": [0, 2], "fy": [1, 2], "prog": "apartments", "wt": 1.0, "name": "Courtyard flats", "f": {"ac": 0.5, "dish": 0.5, "roof": {"flat": 4}}},
		{"id": "apartments_low", "s": "rect", "w": [18, 22], "h": [8, 9], "m": [0, 2], "fy": [1, 2], "prog": "apartments", "wt": 1.5, "name": "Low flats", "f": {"ac": 0.3, "dish": 0.3, "roof": {"flat": 2, "gable": 2, "lean": 1}}},
		{"id": "motel", "s": "units", "n": 5, "w": [7, 7], "h": [9, 9], "m": [0, 2], "fy": [3, 4], "prog": "unit_motel", "wt": 1.0, "name": "Motel", "f": {"canopy": "walk", "sign": "bed", "roof": {"flat": 3, "lean": 2}}},
	],
	# ----------------------------------------------------------------------- shops ----
	"kiosk": [
		{"id": "kiosk", "s": "legacy", "wt": 3.0, "name": "Kiosk", "f": {"awn": "red", "sign": "news", "roof": {"flat": 3, "lean": 2}}},
		{"id": "kiosk_stall", "s": "legacy", "wt": 1.5, "name": "Corner stall", "f": {"awn": "green", "sign": "cart", "roof": {"lean": 3, "flat": 2}}},
	],
	"rowshop": [
		{"id": "rowshop", "s": "legacy", "wt": 3.0, "name": "Row shop", "f": {"awn": "random", "sign": "random", "roof": {"gable": 2, "flat": 2, "lean": 1}}},
		{"id": "rowshop_wide", "s": "rect", "w": [12, 14], "h": [9, 11], "m": [0, 0], "fy": [1, 2], "prog": "shop", "wt": 1.5, "name": "Wide shop front", "f": {"awn": "random", "sign": "random", "roof": {"flat": 3, "gable": 1}}},
		{"id": "rowshop_flat", "s": "rect", "w": [8, 9], "h": [11, 13], "m": [0, 0], "fy": [1, 2], "prog": "shop", "wt": 1.5, "name": "Narrow deep shop", "f": {"awn": "random", "sign": "random", "roof": {"flat": 4, "lean": 1}}},
	],
	"cornershop": [
		{"id": "cornershop", "s": "legacy", "wt": 3.0, "name": "Corner shop", "f": {"awn": "random", "sign": "cart", "roof": {"flat": 2, "gable": 2, "hip": 1}}},
		{"id": "cornershop_L", "s": "L", "w": [11, 13], "h": [8, 9], "w2": [7, 8], "h2": [8, 9], "m": [0, 1], "fy": [1, 2], "prog": "shop_L", "wt": 1.5, "name": "Corner shop with a flat", "f": {"awn": "random", "sign": "cart", "roof": {"flat": 2, "gable": 2}}},
	],
	"shop": [
		{"id": "shop", "s": "legacy", "wt": 3.0, "name": "General store", "f": {"awn": "random", "sign": "cart", "roof": {"flat": 2, "gable": 2, "lean": 1}}},
		{"id": "bookshop", "s": "rect", "w": [11, 13], "h": [9, 11], "m": [0, 1], "fy": [1, 2], "prog": "shop", "wt": 1.0, "name": "Bookshop", "f": {"awn": "blue", "sign": "book", "roof": {"gable": 3, "flat": 1}}},
		{"id": "electronics", "s": "rect", "w": [12, 14], "h": [9, 11], "m": [0, 1], "fy": [1, 2], "prog": "shop", "wt": 1.0, "name": "Electronics shop", "f": {"awn": "blue", "sign": "plug", "dish": 0.5, "roof": {"flat": 3, "gable": 1}}},
		{"id": "thrift", "s": "rect", "w": [12, 15], "h": [9, 12], "m": [0, 1], "fy": [1, 2], "prog": "shop", "wt": 1.0, "name": "Thrift store", "f": {"awn": "yellow", "sign": "hanger", "roof": {"gable": 2, "flat": 2}}},
	],
	"pharmacy": [
		{"id": "pharmacy", "s": "legacy", "wt": 3.0, "name": "Pharmacy", "f": {"awn": "green", "sign": "cross", "roof": {"flat": 2, "gable": 2}}},
		{"id": "pharmacy_corner", "s": "L", "w": [12, 13], "h": [8, 9], "w2": [6, 7], "h2": [8, 9], "m": [0, 1], "fy": [1, 2], "prog": "pharmacy_L", "wt": 1.0, "name": "Corner pharmacy", "f": {"awn": "green", "sign": "cross", "roof": {"flat": 3, "gable": 1}}},
	],
	"bakery": [
		{"id": "bakery", "s": "legacy", "wt": 3.0, "name": "Bakery", "f": {"awn": "yellow", "sign": "bread", "chim": 0.9, "roof": {"gable": 3, "flat": 1}}},
		{"id": "bakery_oven", "s": "back", "w": [10, 12], "h": [7, 8], "bw": 6, "bh": 5, "m": [0, 1], "fy": [1, 2], "prog": "bakery", "wt": 1.0, "name": "Bakery with an oven house", "f": {"awn": "yellow", "sign": "bread", "chim": 1.0, "roof": {"gable": 3, "flat": 1}}},
	],
	"hardware": [
		{"id": "hardware", "s": "legacy", "wt": 3.0, "name": "Hardware store", "f": {"awn": "red", "sign": "wrench", "roof": {"gable": 2, "flat": 2}}},
		{"id": "hardware_yard", "s": "side", "w": [12, 14], "h": [9, 10], "gw": 6, "gh": 7, "m": [0, 1], "fy": [1, 2], "prog": "hardware_yard", "wt": 1.0, "name": "Hardware store with a lumber shed", "f": {"awn": "red", "sign": "wrench", "yard": "stacks", "roof": {"gable": 2, "lean": 2}}},
	],
	"diner": [
		{"id": "diner", "s": "legacy", "wt": 3.0, "name": "Diner", "f": {"awn": "red", "sign": "cup", "roof": {"flat": 3, "gable": 1}}},
		{"id": "diner_L", "s": "L", "w": [14, 16], "h": [8, 9], "w2": [8, 9], "h2": [8, 9], "m": [0, 2], "fy": [2, 3], "prog": "diner_L", "wt": 1.0, "name": "Diner with a back room", "f": {"awn": "red", "sign": "cup", "roof": {"flat": 3}}},
		{"id": "truck_stop", "s": "rect", "w": [16, 18], "h": [9, 10], "m": [2, 4], "fy": [5, 6], "prog": "diner", "wt": 1.0, "name": "Roadside diner", "f": {"canopy": "gas", "sign": "fuel", "yard": "cars", "roof": {"flat": 3, "lean": 1}}},
	],
	"supermarket": [
		{"id": "supermarket", "s": "legacy", "wt": 3.0, "name": "Supermarket", "f": {"sign": "cart", "ac": 0.8, "roof": {"flat": 4}}},
		{"id": "supermarket_L", "s": "L", "w": [16, 18], "h": [8, 8], "w2": [8, 9], "h2": [8, 9], "m": [3, 5], "fy": [7, 8], "prog": "supermarket_L", "wt": 1.0, "name": "Supermarket with a depot", "f": {"sign": "cart", "ac": 0.8, "roof": {"flat": 4}}},
	],
	"cafe": [
		{"id": "cafe", "s": "rect", "w": [10, 12], "h": [8, 9], "m": [0, 1], "fy": [2, 3], "prog": "cafe", "wt": 2.0, "name": "Cafe", "f": {"awn": "random", "sign": "cup", "roof": {"flat": 2, "gable": 2}}},
		{"id": "cafe_corner", "s": "L", "w": [11, 12], "h": [8, 8], "w2": [7, 8], "h2": [8, 8], "m": [0, 1], "fy": [2, 3], "prog": "cafe_L", "wt": 1.0, "name": "Corner cafe", "f": {"awn": "random", "sign": "cup", "roof": {"flat": 2, "gable": 2}}},
	],
	"barber": [
		{"id": "barber", "s": "rect", "w": [8, 9], "h": [8, 9], "m": [0, 0], "fy": [1, 2], "prog": "barber", "wt": 1.0, "name": "Barber", "f": {"awn": "blue", "sign": "scissors", "roof": {"flat": 3, "gable": 2}}},
		{"id": "salon", "s": "rect", "w": [9, 10], "h": [8, 8], "m": [0, 0], "fy": [1, 2], "prog": "barber", "wt": 1.0, "name": "Hair salon", "f": {"awn": "random", "sign": "scissors", "roof": {"hip": 2, "gable": 2}}},
		{"id": "barber_back", "s": "rect", "w": [8, 9], "h": [9, 9], "m": [0, 0], "fy": [1, 2], "prog": "barber_b", "wt": 0.8, "name": "Barber with a back room", "f": {"awn": "red", "sign": "scissors", "roof": {"gable": 3, "flat": 1}}},
	],
	"laundromat": [
		{"id": "laundromat", "s": "rect", "w": [10, 11], "h": [8, 9], "m": [0, 1], "fy": [1, 2], "prog": "laundromat", "wt": 1.0, "name": "Laundromat", "f": {"awn": "blue", "sign": "drop", "ac": 0.8, "roof": {"flat": 4, "gable": 1}}},
		{"id": "launderette", "s": "rect", "w": [9, 10], "h": [8, 8], "m": [0, 1], "fy": [1, 2], "prog": "laundromat_b", "wt": 1.0, "name": "Launderette", "f": {"awn": "green", "sign": "drop", "ac": 0.6, "roof": {"flat": 3, "gable": 2}}},
		{"id": "dry_cleaner", "s": "rect", "w": [8, 9], "h": [8, 9], "m": [0, 0], "fy": [1, 2], "prog": "drycleaner", "wt": 1.0, "name": "Dry cleaner", "f": {"awn": "yellow", "sign": "hanger", "ac": 0.7, "roof": {"flat": 3, "hip": 1}}},
	],
	"pub": [
		{"id": "pub", "s": "rect", "w": [12, 14], "h": [9, 10], "m": [0, 1], "fy": [2, 3], "prog": "pub", "wt": 2.0, "name": "Pub", "f": {"awn": "green", "sign": "mug", "chim": 0.8, "roof": {"gable": 3, "hip": 2}}},
		{"id": "pub_corner", "s": "L", "w": [12, 13], "h": [8, 8], "w2": [8, 9], "h2": [8, 8], "m": [0, 1], "fy": [2, 3], "prog": "pub_L", "wt": 1.0, "name": "Corner pub", "f": {"awn": "green", "sign": "mug", "chim": 0.9, "roof": {"gable": 3, "hip": 2}}},
	],
	"butcher": [
		{"id": "butcher", "s": "rect", "w": [9, 10], "h": [8, 9], "m": [0, 0], "fy": [1, 2], "prog": "butcher", "wt": 1.0, "name": "Butcher", "f": {"awn": "red", "sign": "ham", "ac": 0.6, "roof": {"flat": 3, "gable": 2}}},
		{"id": "deli", "s": "rect", "w": [9, 10], "h": [8, 9], "m": [0, 0], "fy": [1, 2], "prog": "deli", "wt": 1.0, "name": "Deli", "f": {"awn": "yellow", "sign": "cup", "roof": {"gable": 2, "flat": 2}}},
		{"id": "meat_market", "s": "rect", "w": [10, 11], "h": [8, 8], "m": [0, 1], "fy": [1, 2], "prog": "butcher", "wt": 0.7, "name": "Meat market", "f": {"awn": "red", "sign": "ham", "ac": 0.8, "roof": {"flat": 4}}},
	],
	"florist": [
		{"id": "florist", "s": "rect", "w": [8, 9], "h": [8, 9], "m": [0, 0], "fy": [1, 2], "prog": "florist", "wt": 1.0, "name": "Florist", "f": {"awn": "green", "sign": "flower", "roof": {"gable": 3, "flat": 1}}},
		{"id": "newsagent", "s": "rect", "w": [8, 9], "h": [8, 8], "m": [0, 0], "fy": [1, 2], "prog": "newsagent", "wt": 1.0, "name": "Newsagent", "f": {"awn": "blue", "sign": "news", "roof": {"flat": 2, "gable": 2}}},
		{"id": "pawn_shop", "s": "rect", "w": [8, 9], "h": [8, 9], "m": [0, 0], "fy": [1, 2], "prog": "newsagent", "wt": 0.8, "name": "Pawn shop", "f": {"awn": "red", "sign": "coin", "roof": {"flat": 3, "hip": 1}}},
	],
	"dealer": [
		{"id": "dealer", "s": "rect", "w": [12, 14], "h": [8, 9], "m": [2, 4], "fy": [6, 7], "prog": "dealer", "wt": 1.0, "name": "Car dealer", "f": {"sign": "car", "yard": "cars", "roof": {"flat": 4}}},
	],
	"gas_station": [
		{"id": "gas_station", "s": "rect", "w": [8, 9], "h": [6, 7], "m": [4, 6], "fy": [7, 8], "prog": "gas_station", "wt": 2.0, "name": "Gas station", "f": {"canopy": "gas", "sign": "fuel", "roof": {"flat": 4}}},
		{"id": "gas_station_big", "s": "L", "w": [10, 11], "h": [6, 6], "w2": [6, 7], "h2": [7, 8], "m": [3, 5], "fy": [8, 9], "prog": "gas_station", "wt": 1.0, "name": "Gas station with a garage", "f": {"canopy": "gas", "sign": "fuel", "yard": "cars", "roof": {"flat": 4}}},
	],
	"strip": [
		{"id": "strip_mall", "s": "units", "n": 3, "w": [8, 9], "h": [8, 9], "m": [1, 3], "fy": [5, 6], "prog": "unit_shop", "wt": 1.0, "name": "Strip mall", "f": {"awn": "random", "sign": "random", "yard": "cars", "roof": {"flat": 4}}},
		{"id": "strip_long", "s": "units", "n": 4, "w": [7, 8], "h": [8, 8], "m": [0, 2], "fy": [4, 5], "prog": "unit_shop", "wt": 0.7, "name": "Row of small shops", "f": {"awn": "random", "sign": "random", "roof": {"flat": 4}}},
	],
	# --------------------------------------------------------------------- offices ----
	"office": [
		{"id": "office", "s": "legacy", "wt": 3.0, "name": "Office", "f": {"ac": 0.7, "dish": 0.3, "roof": {"flat": 4, "gable": 1}}},
		{"id": "office_L", "s": "L", "w": [14, 16], "h": [8, 9], "w2": [8, 9], "h2": [8, 9], "m": [0, 2], "fy": [2, 3], "prog": "office_L", "wt": 1.5, "name": "L-shaped office", "f": {"ac": 0.8, "dish": 0.4, "roof": {"flat": 4}}},
	],
	"bank": [
		{"id": "bank", "s": "legacy", "wt": 3.0, "name": "Bank", "f": {"sign": "coin", "ac": 0.6, "roof": {"flat": 3, "hip": 2}}},
		{"id": "bank_corner", "s": "L", "w": [12, 13], "h": [8, 9], "w2": [7, 8], "h2": [8, 9], "m": [0, 1], "fy": [1, 2], "prog": "bank_L", "wt": 1.0, "name": "Corner bank", "f": {"sign": "coin", "ac": 0.6, "roof": {"flat": 3, "hip": 2}}},
	],
	"officeblock": [
		{"id": "officeblock", "s": "rect", "w": [18, 22], "h": [10, 12], "m": [0, 2], "fy": [2, 3], "prog": "apartments", "wt": 1.0, "name": "Office block", "f": {"ac": 1.0, "dish": 0.5, "roof": {"flat": 5}}},
	],
	"agency": [
		{"id": "agency", "s": "rect", "w": [9, 11], "h": [8, 9], "m": [0, 1], "fy": [1, 2], "prog": "agency", "wt": 1.0, "name": "Agency office", "f": {"awn": "blue", "ac": 0.5, "roof": {"flat": 3, "gable": 2}}},
	],
	"surgery": [
		{"id": "surgery", "s": "rect", "w": [11, 13], "h": [8, 9], "m": [0, 2], "fy": [2, 3], "prog": "surgery", "wt": 1.0, "name": "Doctor's surgery", "f": {"sign": "cross", "awn": "green", "ac": 0.5, "roof": {"gable": 2, "flat": 2}}},
	],
	# ------------------------------------------------------------------- industrial ----
	"warehouse": [
		{"id": "warehouse", "s": "legacy", "wt": 3.0, "name": "Warehouse", "f": {"roof": {"gable": 3, "lean": 1, "flat": 2}, "ac": 0.3}},
		{"id": "warehouse_docks", "s": "rect", "w": [18, 22], "h": [11, 13], "m": [2, 4], "fy": [4, 5], "prog": "warehouse", "wt": 2.0, "name": "Warehouse with loading docks", "f": {"canopy": "dock", "roof": {"flat": 3, "lean": 2}, "ac": 0.3}},
		{"id": "warehouse_L", "s": "L", "w": [16, 18], "h": [9, 10], "w2": [9, 10], "h2": [9, 10], "m": [2, 4], "fy": [2, 3], "prog": "warehouse_L", "wt": 1.0, "name": "L-shaped warehouse", "f": {"roof": {"gable": 3, "flat": 1}}},
	],
	"factory": [
		{"id": "factory", "s": "back", "w": [16, 18], "h": [8, 9], "bw": 8, "bh": 6, "bx": "l", "m": [2, 4], "fy": [3, 4], "prog": "factory", "wt": 2.0, "name": "Factory", "f": {"yard": "stacks", "ac": 0.5, "roof": {"gable": 3, "flat": 2}}},
		{"id": "factory_saw", "s": "rect", "w": [16, 20], "h": [10, 12], "m": [2, 4], "fy": [3, 4], "prog": "factory_saw", "wt": 1.5, "name": "Sawtooth factory", "f": {"roof": {"saw": 1}, "ac": 0.3}},
	],
	"garage": [
		{"id": "garage", "s": "legacy", "wt": 3.0, "name": "Garage", "f": {"roof": {"gable": 2, "flat": 2}, "yard": "wrecks"}},
		{"id": "garage_big", "s": "rect", "w": [14, 16], "h": [9, 10], "m": [2, 4], "fy": [3, 4], "prog": "garage_big", "wt": 1.5, "name": "Repair shop", "f": {"roof": {"gable": 2, "lean": 2}, "yard": "wrecks", "sign": "wrench"}},
		{"id": "garage_yard", "s": "legacy", "wt": 1.5, "name": "Garage with a scrap yard", "f": {"roof": {"flat": 2, "lean": 2}, "yard": "wrecks"}},
	],
	"workshop": [
		{"id": "workshop", "s": "legacy", "wt": 3.0, "name": "Workshop", "f": {"roof": {"gable": 2, "lean": 2}}},
		{"id": "workshop_L", "s": "L", "w": [10, 12], "h": [7, 8], "w2": [7, 8], "h2": [7, 8], "m": [2, 4], "fy": [2, 4], "prog": "workshop_L", "wt": 1.5, "name": "L-shaped workshop", "f": {"roof": {"lean": 2, "gable": 2}, "yard": "stacks"}},
	],
	"scrapyard": [
		{"id": "scrapyard", "s": "legacy", "wt": 3.0, "name": "Scrap yard", "f": {"roof": {"lean": 3, "flat": 1}, "yard": "wrecks"}},
	],
	"containers": [
		{"id": "containers", "s": "legacy", "wt": 3.0, "name": "Container yard", "f": {"roof": {"flat": 1}, "yard": "stacks"}},
	],
	"carwash": [
		{"id": "carwash", "s": "rect", "w": [10, 12], "h": [8, 9], "m": [2, 4], "fy": [3, 4], "prog": "carwash", "wt": 1.0, "name": "Car wash", "f": {"canopy": "walk", "sign": "drop", "roof": {"flat": 4}}},
	],
	"storage": [
		{"id": "storage_units", "s": "units", "n": 4, "w": [6, 6], "h": [8, 8], "m": [2, 4], "fy": [4, 5], "prog": "unit_store", "wt": 1.0, "name": "Storage units", "f": {"roof": {"flat": 2, "lean": 3}}},
	],
	"depot": [
		{"id": "bus_depot", "s": "rect", "w": [18, 20], "h": [10, 12], "m": [2, 4], "fy": [5, 6], "prog": "depot", "wt": 1.0, "name": "Bus depot", "f": {"yard": "cars", "roof": {"gable": 3, "flat": 2}}},
	],
	"substation": [
		{"id": "substation", "s": "rect", "w": [8, 9], "h": [7, 8], "m": [3, 5], "fy": [3, 4], "prog": "substation", "wt": 1.0, "name": "Substation", "f": {"roof": {"flat": 4}, "yard": "stacks"}},
	],
	"lumber": [
		{"id": "lumberyard", "s": "rect", "w": [11, 13], "h": [7, 8], "m": [3, 5], "fy": [4, 5], "prog": "lumber", "wt": 1.0, "name": "Lumber yard", "f": {"roof": {"lean": 4, "gable": 1}, "yard": "stacks"}},
	],
	"coldstore": [
		{"id": "coldstore", "s": "rect", "w": [14, 16], "h": [10, 11], "m": [2, 4], "fy": [4, 5], "prog": "coldstore", "wt": 1.0, "name": "Cold store", "f": {"canopy": "dock", "ac": 1.0, "roof": {"flat": 5}}},
	],
	# ----------------------------------------------------------------------- civic ----
	"church": [
		{"id": "church", "s": "legacy", "wt": 3.0, "name": "Church", "f": {"roof": {"gable": 4, "hip": 1}}},
		{"id": "church_T", "s": "church_T", "wt": 1.0, "name": "Church with transepts", "f": {"roof": {"gable": 4}}},
	],
	"chapel": [
		{"id": "chapel", "s": "rect", "w": [8, 9], "h": [11, 12], "m": [3, 5], "fy": [3, 4], "prog": "chapel", "wt": 1.0, "name": "Chapel", "f": {"roof": {"gable": 4}, "yard": "graves"}},
	],
	"school": [
		{"id": "school", "s": "legacy", "wt": 3.0, "name": "School", "f": {"roof": {"flat": 2, "gable": 2}}},
		{"id": "school_U", "s": "legacy_U", "w": [20, 22], "h": [13, 14], "m": [2, 4], "fy": [2, 3], "prog": "school_U", "wt": 1.0, "name": "Courtyard school", "f": {"roof": {"flat": 2, "gable": 2}}},
	],
	"kindergarten": [
		{"id": "kindergarten", "s": "L", "w": [12, 13], "h": [8, 8], "w2": [7, 8], "h2": [8, 9], "m": [3, 5], "fy": [3, 4], "prog": "kindergarten", "wt": 1.0, "name": "Kindergarten", "f": {"roof": {"hip": 3, "gable": 2}, "yard": "pens"}},
	],
	"clinic": [
		{"id": "clinic", "s": "legacy", "wt": 3.0, "name": "Clinic", "f": {"sign": "cross", "ac": 0.7, "roof": {"flat": 3, "gable": 1}}},
		{"id": "clinic_L", "s": "L", "w": [14, 16], "h": [8, 9], "w2": [9, 10], "h2": [9, 10], "m": [2, 4], "fy": [2, 3], "prog": "clinic_L", "wt": 1.5, "name": "L-shaped clinic", "f": {"sign": "cross", "ac": 0.8, "roof": {"flat": 3}}},
		{"id": "hospital", "s": "T", "w": [18, 20], "h": [8, 9], "w2": [10, 11], "h2": [8, 9], "m": [2, 4], "fy": [2, 3], "prog": "hospital", "wt": 0.7, "name": "Small hospital", "f": {"sign": "cross", "ac": 1.0, "roof": {"flat": 4}}},
	],
	"fire_station": [
		{"id": "fire_station", "s": "legacy", "wt": 3.0, "name": "Fire station", "f": {"roof": {"flat": 2, "gable": 2}}},
		{"id": "fire_tower", "s": "side", "w": [14, 16], "h": [9, 10], "gw": 6, "gh": 7, "m": [2, 4], "fy": [2, 3], "prog": "fire_tower", "wt": 1.0, "name": "Fire station with a hose tower", "f": {"roof": {"flat": 2, "gable": 2}}},
	],
	"police": [
		{"id": "police", "s": "legacy", "wt": 3.0, "name": "Police station", "f": {"ac": 0.6, "roof": {"flat": 3, "hip": 1}}},
		{"id": "police_L", "s": "L", "w": [13, 14], "h": [8, 9], "w2": [8, 9], "h2": [8, 9], "m": [2, 4], "fy": [2, 3], "prog": "police_L", "wt": 1.0, "name": "Police station with a yard", "f": {"ac": 0.6, "roof": {"flat": 3}}},
	],
	"library": [
		{"id": "library", "s": "legacy", "wt": 3.0, "name": "Library", "f": {"roof": {"hip": 3, "gable": 2}}},
		{"id": "library_wing", "s": "L", "w": [12, 13], "h": [8, 9], "w2": [8, 9], "h2": [8, 9], "m": [2, 4], "fy": [2, 3], "prog": "library_wing", "wt": 1.0, "name": "Library with a wing", "f": {"roof": {"hip": 3, "gable": 2}}},
	],
	"townhall": [
		{"id": "town_hall", "s": "manor", "w": [10, 11], "h": [11, 12], "w2": [8, 9], "h2": [8, 9], "m": [2, 4], "fy": [3, 4], "prog": "townhall", "wt": 1.0, "name": "Town hall", "f": {"porch": "portico", "roof": {"hip": 4, "gable": 1}}},
	],
	"postoffice": [
		{"id": "post_office", "s": "rect", "w": [11, 13], "h": [8, 9], "m": [1, 3], "fy": [2, 3], "prog": "postoffice", "wt": 1.0, "name": "Post office", "f": {"sign": "mail", "awn": "red", "roof": {"flat": 2, "gable": 2}}},
	],
	"hall": [
		{"id": "community_hall", "s": "rect", "w": [14, 16], "h": [9, 10], "m": [2, 4], "fy": [2, 3], "prog": "hall", "wt": 1.0, "name": "Community hall", "f": {"roof": {"gable": 4, "lean": 1}}},
	],
	"museum": [
		{"id": "museum", "s": "rect", "w": [14, 16], "h": [10, 11], "m": [2, 4], "fy": [2, 3], "prog": "museum", "wt": 1.0, "name": "Museum", "f": {"porch": "portico", "roof": {"hip": 4, "flat": 1}}},
	],
	"cinema": [
		{"id": "cinema", "s": "rect", "w": [14, 16], "h": [10, 12], "m": [1, 3], "fy": [3, 4], "prog": "cinema", "wt": 1.0, "name": "Cinema", "f": {"sign": "film", "canopy": "walk", "roof": {"flat": 4}}},
	],
	"radio_station": [
		{"id": "radio_station", "s": "rect", "w": [10, 12], "h": [8, 9], "m": [3, 5], "fy": [3, 4], "prog": "radio_station", "wt": 1.0, "name": "Radio station", "f": {"dish": 1.0, "mast": 1, "roof": {"flat": 4}}},
	],
	"courthouse": [
		{"id": "courthouse", "s": "rect", "w": [14, 16], "h": [10, 11], "m": [2, 4], "fy": [3, 4], "prog": "courthouse", "wt": 1.0, "name": "Courthouse", "f": {"porch": "portico", "roof": {"hip": 4, "flat": 1}}},
	],
	# ------------------------------------------------------------------------ farm ----
	"farmhouse": [
		{"id": "farmhouse", "s": "rect", "w": [14, 17], "h": [7, 8], "m": [2, 4], "fy": [1, 2], "prog": "farmhouse", "wt": 3.0, "name": "Farmhouse", "f": {"chim": 0.9, "roof": {"gable": 4, "hip": 1}}},
		{"id": "farmhouse_L", "s": "L", "w": [12, 14], "h": [7, 8], "w2": [8, 9], "h2": [7, 8], "m": [2, 4], "fy": [1, 2], "prog": "farmhouse", "wt": 2.0, "name": "L-shaped farmhouse", "f": {"chim": 0.9, "roof": {"gable": 4, "hip": 1}}},
		{"id": "farmhouse_porch", "s": "rect", "w": [14, 17], "h": [7, 8], "m": [2, 4], "fy": [2, 3], "prog": "farmhouse", "wt": 2.0, "name": "Farmhouse with a porch", "f": {"porch": "wrap", "chim": 0.9, "roof": {"gable": 3, "hip": 2}}},
		{"id": "farmhouse_hip", "s": "rect", "w": [13, 15], "h": [8, 8], "m": [2, 4], "fy": [1, 2], "prog": "farmhouse", "wt": 1.5, "name": "Brick farmhouse", "f": {"chim": 1.0, "roof": {"hip": 4, "gable": 1}}},
		{"id": "farmhouse_wing", "s": "side", "w": [11, 12], "h": [7, 8], "gw": 6, "gh": 6, "m": [2, 4], "fy": [1, 2], "prog": "farmhouse_wing", "wt": 1.5, "name": "Farmhouse with a store", "f": {"chim": 0.9, "roof": {"gable": 3, "lean": 1}}},
		{"id": "farmhouse_T", "s": "T", "w": [18, 20], "h": [7, 8], "w2": [8, 9], "h2": [7, 8], "m": [2, 4], "fy": [1, 2], "prog": "farmhouse_T", "wt": 1.0, "name": "T-shaped farmhouse", "f": {"chim": 1.0, "roof": {"gable": 4}}},
		{"id": "farmhouse_long", "s": "L", "w": [18, 20], "h": [7, 8], "w2": [8, 9], "h2": [7, 8], "m": [2, 4], "fy": [1, 2], "prog": "farmhouse_long", "wt": 1.0, "name": "Long farmhouse", "f": {"porch": "front", "chim": 1.0, "roof": {"gable": 4, "lean": 1}}},
	],
	"barn": [
		{"id": "barn", "s": "legacy", "wt": 3.0, "name": "Barn", "f": {"roof": {"gable": 4}}},
		{"id": "barn_big", "s": "back", "w": [12, 14], "h": [7, 8], "bw": 8, "bh": 5, "bx": "c", "m": [2, 4], "fy": [2, 3], "prog": "barn_big", "wt": 1.5, "name": "Big barn", "f": {"roof": {"gable": 4}}},
		{"id": "barn_lean", "s": "side", "w": [10, 12], "h": [7, 8], "gw": 6, "gh": 6, "m": [2, 4], "fy": [2, 3], "prog": "barn_big", "wt": 1.0, "name": "Barn with a lean-to", "f": {"roof": {"gable": 3, "lean": 2}}},
		{"id": "stable", "s": "rect", "w": [12, 14], "h": [6, 7], "m": [2, 4], "fy": [2, 3], "prog": "stable", "wt": 1.0, "name": "Stable", "f": {"roof": {"gable": 3, "lean": 2}}},
	],
	"silo": [
		{"id": "silo", "s": "rect", "w": [5, 5], "h": [5, 5], "m": [0, 1], "fy": [1, 1], "prog": "silo", "wt": 1.0, "name": "Silo", "f": {"roof": {"dome": 1}}},
	],
	"coop": [
		{"id": "coop", "s": "rect", "w": [6, 7], "h": [5, 5], "m": [0, 1], "fy": [1, 1], "prog": "coop", "wt": 1.0, "name": "Chicken coop", "f": {"roof": {"lean": 3, "gable": 1}, "yard": "pens"}},
	],
	"greenhouse": [
		{"id": "greenhouse", "s": "rect", "w": [8, 9], "h": [5, 6], "m": [0, 1], "fy": [1, 1], "prog": "greenhouse", "wt": 1.0, "name": "Greenhouse", "f": {"roof": {"glass": 1}}},
	],
	"tractor_shed": [
		{"id": "tractor_shed", "s": "rect", "w": [8, 9], "h": [6, 6], "m": [0, 1], "fy": [1, 1], "prog": "tractor_shed", "wt": 1.0, "name": "Tractor shed", "f": {"roof": {"lean": 3, "gable": 1}}},
	],
	"grain_store": [
		{"id": "grain_store", "s": "rect", "w": [9, 10], "h": [7, 8], "m": [1, 2], "fy": [1, 2], "prog": "grain_store", "wt": 1.0, "name": "Grain store", "f": {"roof": {"gable": 3, "flat": 1}}},
	],
	# -------------------------------------------------------------------- outbuildings ----
	"shed": [
		{"id": "shed", "s": "legacy", "wt": 3.0, "name": "Shed", "f": {"roof": {"lean": 3, "gable": 2}}},
	],
}

## The little buildings a lot may have beyond its house (a shed in the yard): [kind, weight] by district. `shed` is the old one; the others are cut the same way (BuildingGen._add_extra): [kind, outer w, outer h, program].
const EXTRAS := {
	"shed": ["shed", 7, 5, "shed", 3.0, "Shed"],
	"garden_shed": ["shed", 5, 5, "garden_shed", 2.0, "Garden shed"],
	"garage_det": ["shed", 7, 7, "garage_det", 1.5, "Detached garage"],
	"workshop_shed": ["shed", 9, 6, "workshop_shed", 1.0, "Workshop shed"],
	"summerhouse": ["shed", 6, 6, "summerhouse", 1.0, "Summer house"],
	"greenhouse_small": ["greenhouse", 8, 5, "greenhouse", 1.0, "Greenhouse"],
	"coop_small": ["coop", 6, 5, "coop", 1.0, "Chicken coop"],
	"silo": ["silo", 5, 5, "silo", 1.0, "Silo"],
	"tractor_shed": ["tractor_shed", 8, 6, "tractor_shed", 1.0, "Tractor shed"],
}
## Which extras a district's lots may have, [id, weight].
const EXTRAS_BY_DISTRICT := {
	"suburb": [["shed", 4.0], ["garden_shed", 2.0], ["garage_det", 1.5], ["summerhouse", 1.0], ["greenhouse_small", 0.8], ["workshop_shed", 0.8]],
	"edge": [["shed", 2.0], ["silo", 2.0], ["coop_small", 2.0], ["tractor_shed", 2.0], ["greenhouse_small", 1.0], ["workshop_shed", 1.0]],
}


## How many of the dead stand in a building of a new kind at the start: [least, most] (the old kinds': town_gen.gd `DEAD_BY_KIND`).
static func dead_range(kind: String) -> Array:
	var nk = NEW_KINDS.get(kind)
	return [int(nk[1]), int(nk[2])] if nk != null else [1, 3]


## Every plan of every kind, in a stable order: [{"id", "k", "cat", "name"}] (the catalogue and the census read it).
static func all_plans() -> Array:
	var out: Array = []
	var kinds: Array = RECIPES.keys()
	kinds.sort()
	for k in kinds:
		for r in RECIPES[k]:
			out.append({"id": String(r.id), "k": String(k), "cat": String(CATEGORY.get(k, "house")), "name": String(r.get("name", r.id)), "s": String(r.s)})
	for k in EXTRAS:
		var e: Array = EXTRAS[k]
		out.append({"id": String(k), "k": String(e[0]), "cat": "outbuilding", "name": String(e[5]), "s": "extra"})
	out.append({"id": "start", "k": "start", "cat": "house", "name": "Start house", "s": "legacy"})
	return out


## The recipe with this id (or {}), and the kind it belongs to.
static func recipe(id: String) -> Dictionary:
	for k in RECIPES:
		for r in RECIPES[k]:
			if String(r.id) == id:
				var o: Dictionary = (r as Dictionary).duplicate(false)
				o["k"] = String(k)
				return o
	return {}
