## What the top bar's numbers mean in the town with an inventory (INV-UI): BEFORE the house is claimed they are what she CARRIES (`sim.inv.carried_totals()`), AFTER it they are the base's
## STORES (`sim.inv.store_totals()`; `bar_totals()` is the rules' own choice of the two), and the pack has a chip of its own (scripts/ui/inv_ui.gd). `StoresCalm.update` calls `apply` after the
## HUD has written the stock; the tooltips say which it is. A view only: it writes the labels and the tips, never the rules.
extends RefCounted

const InvApi := preload("res://scripts/ui/inv_api.gd")

const NAMES := {"ammo": "Ammo", "scrap": "Scrap", "food": "Food", "water": "Water", "meds": "Medicine"}


## Whether the house is claimed (the base exists): from then on the bar shows the stores.
static func claimed(sim) -> bool:
	var base = sim.get("base") if sim != null else null
	return base != null and bool(base.get("claimed"))


static func apply(hud, sim) -> void:
	if not InvApi.active(sim):
		return
	var base := claimed(sim)
	var t: Dictionary = InvApi.bar_totals(sim)
	if t.is_empty():
		return
	var carried: Dictionary = InvApi.carried_totals(sim)
	var calm = hud.get("_stores_calm")
	for kind in ["ammo", "food", "water", "meds", "scrap"]:
		var lbl = hud.res_values.get(kind)
		if lbl == null:
			continue
		var n := int(t.get(kind, 0))
		if lbl.text != str(n):
			lbl.text = str(n)
		if not base and hud.res_days.has(kind):
			hud.res_days[kind].visible = false    # (the days the crew could eat are the base's: nothing to count before it exists)
		if calm != null and calm.pairs.has(kind):
			var tip := "%s: %d in your pack" % [NAMES[kind], n]
			if base:
				var in_pack := int(carried.get(kind, 0))
				tip = "%s: %d in the stores" % [NAMES[kind], n]
				if in_pack > 0:
					tip += ", and %d more in your pack" % in_pack
			(calm.pairs[kind] as Control).tooltip_text = tip
