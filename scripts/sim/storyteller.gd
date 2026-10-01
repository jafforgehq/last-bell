## The storyteller: a hidden tension, and a card a day at the radio hour (12:00): a
## boon, a threat or a choice, from assets/data/events.json; and the dawn assembly's
## numbers. (Round 4: the stub with the agreed interface; the STORY builder fills it in.)
##
## Events: {"type": "story_card"} when a card is up and waits for the player,
## {"type": "story_resolved", "id": String, "text": String} when it is settled,
## {"type": "dawn_report"} when the night's report is ready (see `report`).
extends RefCounted

## Tests, the tutorial and the harness switch the storyteller off with this.
var enabled := true
## 0 to 100: it rises with trouble and falls with quiet; the draw leans on it.
var tension := 0.0
var sim


func setup(s) -> void:
	sim = s


func start() -> void:
	tension = 0.0


func update(_dt: float) -> void:
	pass


## The card waiting for an answer, or {}: {"id", "title", "text", "speaker" (a first name),
## "choices": [{"label", "hint"}]} (a card with no choice has one: "Understood").
func pending() -> Dictionary:
	return {}


## Answers the pending card with choice `i`; false if nothing is pending or `i` is out of range.
func choose(_i: int) -> bool:
	return false


## What the dawn assembly shows: {"night", "kills", "mvp": {"who", "kills"}, "wall_lost",
## "wall_mended", "lost": [{"who", "epitaph"}], "skill_ups": [{"who", "skill", "value"}],
## "events": [String], "mood": String}; {} before the first dawn.
func report() -> Dictionary:
	return {}


func save() -> Dictionary:
	return {"tension": tension}


func load_state(d: Dictionary) -> void:
	tension = float(d.get("tension", 0.0))
