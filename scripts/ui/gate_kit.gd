## What the views of the gate share (round 22, "a proper gate"): where the gate's module is, what its state is called, the lamp's
## colours and the words of the HUD's indicator and tooltip. The rules are `sim.gate` (scripts/sim/gate.gd); the views are the gate node
## (scripts/render/gate_node.gd: the leaves and the lever's picture), the overlay (the ring of the prompt and the faint outlines), the
## HUD's indicator (scripts/ui/hud.gd) and main.gd's events. Everything here is a static function: nothing keeps state, and nothing
## changes the rules.
##
## What the views ask of the module (a test's stand-in has to have these): `active()` (avatar mode only: with no avatar the gate is the
## vehicles' and the parties' picture as ever), `open` (0 shut to 1 open: the REAL state), `held` ("" | "open" | "shut"),
## `control_spot() -> Vector2` (the lever, tiles), `gateway() -> Rect2` (the opening, tiles) and `who_blocks() -> Array`.
extends RefCounted

## The lamp: green while the gate is open (or going to be), red while it is shut, amber while the leaves are on the move.
const LAMP_OPEN := Color("#5fd07a")
const LAMP_SHUT := Color("#e0584a")
const LAMP_MOVING := Color("#f0b84a")
const LAMP_OFF := Color("#2a3330")
## The HUD's tooltip of the indicator.
const TIP := "The gate. Walk to the gate lever and press E to open or shut it. A green lamp is open, a red one shut.\nShut it at dusk: an open gate in the dark lets the dead in."

## The states the indicator and the lamp tell apart.
const SHUT := "shut"
const OPEN := "open"
const OPENING := "opening"
const CLOSING := "closing"
## `open` this close to 0 or 1 is all the way shut or open.
const EPS := 0.001


## The gate module of a game: the sim's own, or (in a test, before the real module is there or to make one say something particular) the
## stand-in the test left in the sim's meta "gate_stub". Null when there is none.
static func gate_of(sim):
	if sim == null:
		return null
	if sim.has_meta("gate_stub"):
		return sim.get_meta("gate_stub")
	return sim.get("gate")


## The gate's module when it rules now (avatar mode), else null: the classic game, a test's and Orientation Day's keep the vehicles' demand.
static func active_gate(sim):
	var g = gate_of(sim)
	if g == null or not g.has_method("active") or not bool(g.active()):
		return null
	return g


static func is_active(sim) -> bool:
	return active_gate(sim) != null


## The real state of the leaves: 0 shut to 1 open (a module without it is shut).
static func open_of(g) -> float:
	if g == null:
		return 0.0
	var v = g.get("open")
	return clampf(float(v), 0.0, 1.0) if v != null else 0.0


## "" | "open" | "shut": what the gate is held at (E at the lever by the avatar; the dusk keeper lets a gate held open alone).
static func held_of(g) -> String:
	if g == null:
		return ""
	var v = g.get("held")
	return String(v) if v != null else ""


## The state of the leaves: "shut", "open", or "opening" / "closing" while they move. `dir` is which way they were last seen to move (+1,
## -1, 0 unknown: the module's `open` alone does not say), and is only used between the ends.
static func state_of(open: float, dir: int = 0) -> String:
	if open <= EPS:
		return SHUT
	if open >= 1.0 - EPS:
		return OPEN
	if dir > 0:
		return OPENING
	if dir < 0:
		return CLOSING
	return OPENING if open >= 0.5 else CLOSING


## Which way the rules say the leaves are going: +1 opening, -1 closing, 0 at rest or when the module does not say (its `state()` is "shut",
## "opening", "open" or "closing").
static func rules_dir(g) -> int:
	if g == null or not g.has_method("state"):
		return 0
	match String(g.state()):
		"opening":
			return 1
		"closing":
			return -1
	return 0


## The lamp's colour for a state: red shut, green open, amber on the move.
static func lamp_color(state: String) -> Color:
	match state:
		SHUT:
			return LAMP_SHUT
		OPEN:
			return LAMP_OPEN
	return LAMP_MOVING


## The indicator's words and tone: {"on": whether to show it, "state", "held", "word" ("open", "shut", "held open", "held shut", "opening",
## "closing"), "text" ("Gate: held open"), "lamp": the colour, "dark": the gate is open (or opening) in the dark (the word is amber),
## "tip"}. `dark` is whether it is dusk or night now (the caller knows: `sim.is_night()` or the bell).
static func status(sim, dir: int = 0, dark: bool = false) -> Dictionary:
	var g = active_gate(sim)
	if g == null:
		return {"on": false, "state": SHUT, "held": "", "word": "", "text": "", "lamp": LAMP_OFF, "dark": false, "tip": ""}
	var open := open_of(g)
	var state := state_of(open, rules_dir(g) if rules_dir(g) != 0 else dir)
	var held := held_of(g)
	var word := state
	if state == OPEN and held == "open":
		word = "held open"
	elif state == SHUT and held == "shut":
		word = "held shut"
	var lit := state != SHUT
	return {"on": true, "state": state, "held": held, "word": word, "text": "Gate: %s" % word, "lamp": lamp_color(state), "dark": dark and lit, "tip": TIP}


## Whether the gate is open (or opening) now: the leaves are not all the way shut.
static func is_ajar(g) -> bool:
	return open_of(g) > EPS


## The lever's tile (the module's `control_spot()`), or Vector2.INF when there is none.
static func spot_of(g) -> Vector2:
	if g == null or not g.has_method("control_spot"):
		return Vector2.INF
	var v = g.control_spot()
	return v if v is Vector2 else Vector2.INF


## The gateway's rectangle (tiles; the module's `gateway()`), or an empty one.
static func gateway_of(g) -> Rect2:
	if g == null or not g.has_method("gateway"):
		return Rect2()
	var v = g.gateway()
	return v if v is Rect2 else Rect2()


## The names of who is in the gateway, as the module's `who_blocks()` gives them (strings or people).
static func blockers_of(g) -> Array:
	if g == null or not g.has_method("who_blocks"):
		return []
	var out: Array = []
	for b in g.who_blocks():
		out.append(String(b.first) if b is Object and b.get("first") != null else String(b))
	return out


## "Dez is in the gateway", "Dez and Ana are in the gateway", "Dez, Ana and Marcus are in the gateway": why the gate will not shut ("" for no one).
static func blocked_line(names: Array) -> String:
	if names.is_empty():
		return ""
	if names.size() == 1:
		return "%s is in the gateway" % String(names[0])
	var head: Array = names.slice(0, names.size() - 1)
	return "%s and %s are in the gateway" % [", ".join(PackedStringArray(head.map(func(n): return String(n)))), String(names[names.size() - 1])]
