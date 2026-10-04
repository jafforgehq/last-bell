## The priority chips (round 25, V25.1): the six things the player asks the base to put first (Food, Water, Defence, Rebuilding, Rest, Scavenging), as
## chips in a flow, the same in the briefing card (briefing_card.gd) and in the Base page (base_page.gd). A tap is the sim's `priorities.toggle(id)`: the
## first tap appends (the rank is the tap order, the number on the chip), a tap on a ranked one drops it, a fifth is refused in the sim's own words.
## Nothing here keeps a rule: the ranks, the weights and the refusal come from `sim.priorities`; this file only lays them out. A chip takes no focus
## (W A S D and E keep walking and using) and has a tooltip with the lever in plain numbers, whether it is on or off.
##
##   var made := PriorityKit.make(host, func(id): ...)        # {"flow": HFlowContainer, "chips": {id: Button}}
##   PriorityKit.sync(host, made.chips, sim)                  # the ranks, the looks and the tooltips: cheap, call it each refresh
##   PriorityKit.tap(sim, "food")                             # -> {"ok", "why"}
extends RefCounted

const RadioKit := preload("res://scripts/ui/radio_kit.gd")
const Fonts := preload("res://scripts/ui/fonts.gd")

## The ids in the order the chips are laid out, and what each is called (the contract's `priorities.IDS`: a stand-in without them is given these).
const IDS := ["food", "water", "defence", "rebuild", "rest", "scavenge"]
const NAMES := {"food": "Food", "water": "Water", "defence": "Defence", "rebuild": "Rebuilding", "rest": "Rest", "scavenge": "Scavenging"}
## What each puts first, in plain words (the numbers are filled in from the sim's own weights, see `tip`).
const WHAT := {
	"food": "More hands to the vegetable beds, and a standing errand for food when the stores are under 3 days.",
	"water": "A standing errand for water when the stores are under 3 days.",
	"defence": "More hands to the wall crew and the bench; walls are mended from a higher line and the bench aims at a bigger stock of ammo.",
	"rebuild": "More hands to the Builders, who go to the site; walls are mended from a lower line, the crew is on the site.",
	"rest": "The weary are left out of the plan to rest: one at the first or second rank, two at the first.",
	"scavenge": "A standing errand goes out each morning: two who agree go to a place that fits.",
}
const MAX_SET_FALLBACK := 4
const RANK_W_FALLBACK := [3.0, 2.0, 1.5, 1.0]
## What the chips say when the priorities cannot be set.
const OFF := "Priorities are not in this game"


## The priorities module of a sim, or null (an older fake has none: no chips work, no error).
static func module(sim):
	if sim == null:
		return null
	var m = sim.get("priorities")
	return m if m != null and m.has_method("toggle") else null


static func ids_of(sim) -> Array:
	var m = module(sim)
	var raw = RadioKit.rule_of(m, "IDS", IDS) if m != null else IDS
	var out: Array = (raw as Array).duplicate() if raw is Array else IDS.duplicate()
	if sim != null and sim.has_method("is_one_house") and sim.is_one_house():
		out.erase("scavenge")    # (One House: nobody is sent out on an errand: the avatar goes and looks)
	return out


static func name_of(id: String) -> String:
	return String(NAMES.get(id, id.capitalize()))


## The ranked ids, first first (the sim's `order`).
static func order_of(sim) -> Array:
	var m = module(sim)
	var raw = m.get("order") if m != null else null
	var out: Array = []
	if raw is Array:
		for id in raw:
			out.append(String(id))
	return out


static func rank_of(sim, id: String) -> int:
	var m = module(sim)
	if m != null and m.has_method("rank_of"):
		return int(m.rank_of(id))
	return order_of(sim).find(id) + 1


## "Food, Defence": the ranked names, first first ("" for none).
static func order_words(sim) -> String:
	var names: Array = []
	for id in order_of(sim):
		names.append(name_of(String(id)))
	return ", ".join(names)


static func max_set(sim) -> int:
	return int(RadioKit.rule_of(module(sim), "MAX_SET", MAX_SET_FALLBACK))


## The weights by rank (the sim's `RANK_W`).
static func rank_weights(sim) -> Array:
	var raw = RadioKit.rule_of(module(sim), "RANK_W", RANK_W_FALLBACK)
	return raw if raw is Array and not (raw as Array).is_empty() else RANK_W_FALLBACK


static func _weight_words(w: float) -> String:
	return "%d" % int(w) if is_equal_approx(w, roundf(w)) else "%.1f" % w


## The tooltip of a chip: what the priority puts first, the numbers it adds at each rank (from the sim's own weights), and how to set it.
static func tip(sim, id: String) -> String:
	var weights: Array = rank_weights(sim)
	var rank := rank_of(sim, id)
	var lines: Array = ["%s: %s" % [name_of(id), String(WHAT.get(id, ""))]]
	var numbers := ""
	match id:
		"defence":
			var shifts: Array = []
			var ammo: Array = []
			for w in weights:
				shifts.append("+%d" % int(roundf(5.0 * float(w))))
				ammo.append("+%d" % int(roundf(100.0 * minf(float(w), 3.0) / 3.0 / 25.0) * 25))
			numbers = "The wall line goes up %s points and the ammo target %s (by rank, first to last)." % ["/".join(shifts), "/".join(ammo)]
		"rebuild":
			var shifts: Array = []
			for w in weights:
				shifts.append("-%d" % int(roundf(5.0 * float(w))))
			numbers = "The wall line goes down %s points (by rank, first to last)." % "/".join(shifts)
	var ranks: Array = []
	for w in weights:
		ranks.append("x%s" % _weight_words(float(w)))
	lines.append("Counts %s by rank, first to last." % " ".join(ranks))
	if numbers != "":
		lines.append(numbers)
	if rank > 0:
		lines.append("Rank %d. Tap to drop it." % rank)
	else:
		lines.append("Tap to rank it. Tap order is the rank, up to %d." % max_set(sim))
	return "\n".join(lines)


# ----------------------------------------------------------------------- chips --

## The chips, in a flow that wraps: {"flow": HFlowContainer, "chips": {id: Button}}. `on_tap` is called with the id of the chip that was pressed (a
## shell that wants the sim's answer calls `PriorityKit.tap` itself). Their words and looks come with `sync`.
static func make(host, on_tap: Callable, ids: Array = IDS) -> Dictionary:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chips := {}
	for id in ids:
		var b := RadioKit.small_button(host, name_of(String(id)), 28.0, 13)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size.x = 64.0
		b.set_meta("id", String(id))
		b.set_meta("rank", -1)
		b.pressed.connect(on_tap.bind(String(id)))
		flow.add_child(b)
		chips[String(id)] = b
	return {"flow": flow, "chips": chips}


## Brings the chips up to date with the sim: the rank number on a ranked chip and its gold look, the tooltips (a chip that cannot be used has the
## reason as its tooltip). Cheap: a chip is restyled only when its rank changed.
static func sync(host, chips: Dictionary, sim) -> void:
	var usable := module(sim) != null
	var m = module(sim)
	if m != null and m.has_method("active") and not bool(m.active()):
		usable = false
	for id in chips:
		var b: Button = chips[id]
		var rank := rank_of(sim, String(id)) if usable else 0
		var look := rank if usable else -2
		if int(b.get_meta("rank", -1)) != look:
			b.set_meta("rank", look)
			b.text = "%d  %s" % [rank, name_of(String(id))] if rank > 0 else name_of(String(id))
			_style(host, b, rank > 0)
		b.disabled = not usable
		var want := tip(sim, String(id)) if usable else OFF
		if b.tooltip_text != want:
			b.tooltip_text = want


static func _style(host, b: Button, on: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var st: StyleBox = host._button_style(state, on, false, false)
		st.content_margin_top = 0
		st.content_margin_bottom = 0
		st.content_margin_left = 7
		st.content_margin_right = 7
		b.add_theme_stylebox_override(state, st)
	var ink: Color = host.ACCENT_INK if on else host.INK
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, ink)
	b.add_theme_color_override("font_disabled_color", Color(host.ACCENT, 0.9) if on else host.INK3)


# ------------------------------------------------------------------------ taps --

## A tap on a chip as the sim takes it: {"ok", "why"} (the sim's own words for a fifth: "Four at most: tap one to drop it"). Nothing without the module.
static func tap(sim, id: String) -> Dictionary:
	var m = module(sim)
	if m == null:
		return {"ok": false, "why": OFF}
	var r = m.toggle(id)
	return r if r is Dictionary else {"ok": false, "why": OFF}


## "Use these": the two ids the top concerns point at, set as the order (`priorities.set_order`). {"ok", "why"}; refused when there is nothing to suggest.
static func use_suggested(sim) -> Dictionary:
	var m = module(sim)
	if m == null or not m.has_method("set_order"):
		return {"ok": false, "why": OFF}
	var ids := suggested_of(sim)
	if ids.is_empty():
		return {"ok": false, "why": "Nothing to suggest right now"}
	var r = m.set_order(ids)
	return r if r is Dictionary else {"ok": false, "why": OFF}


## The two ids the top concerns point at (`priorities.suggested()`), the known ones only.
static func suggested_of(sim) -> Array:
	var m = module(sim)
	var out: Array = []
	if m != null and m.has_method("suggested"):
		var raw = m.suggested()
		if raw is Array:
			var known := ids_of(sim)
			for id in raw:
				if known.has(String(id)) and not out.has(String(id)):
					out.append(String(id))
	return out


## "Water, Defence" for a list of ids.
static func words_of(ids: Array) -> String:
	var names: Array = []
	for id in ids:
		names.append(name_of(String(id)))
	return ", ".join(names)
