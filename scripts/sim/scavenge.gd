## Scavenging trips: at dawn the player sends one or two survivors through the
## gate to a site; they are off the map until the afternoon and come back with
## loot, hurt, or not at all. STUB: the scavenging builder fills this in; the
## rules already call every method below.
extends RefCounted

var sim
## The sites, loaded from assets/data/sites.json: [{"id", "name", "blurb",
## "danger", "loot": {...}, ...}].
var sites: Array = []
## Parties out on a trip (each a Dictionary the module defines).
var parties: Array = []


func setup(s) -> void:
	sim = s


func start() -> void:
	parties.clear()


## Every step: parties walking to the gate, away, and coming back.
func update(_dt: float) -> void:
	pass


## A goal for a party member walking to the gate or back to their post, or null.
func goal_for(_p):
	return null


## Whether a trip can be sent now (daytime departure window, enough people,
## not too many of the dead at the gate), and why not if it cannot.
func can_send() -> bool:
	return false


func why_not() -> String:
	return ""


## The sites the player may pick now, each with its current state
## ({"id", "name", "blurb", "danger", "loot_hint", "available", "note"}).
func available_sites() -> Array:
	return []


## Sends the survivors (Person objects) to the site (its id). True if it went.
func send(_people: Array, _site_id: String) -> bool:
	return false


## Marks for the card and panel, for example "away on a trip".
func status_of(_p) -> Array:
	return []


## Handles the HUD button "scavenge" for the selection. True if it took it.
func gizmo(_id: String, _sel) -> bool:
	return false


func save() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
