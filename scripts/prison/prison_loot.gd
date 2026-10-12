## EXPERIMENT (prison raids, step 4a): LOOT BY PLACE, the raid's marks and the gate's choice.
## Pattern: a seeded POST-PASS over the town the generator made (the generator is not touched): every building gets a place type (natural map from its kind, then a stable-hash retag so a raid
## town always has its minimum of pharmacies, hardware stores, garages, petrol stations and police posts), and every container's loot is re-rolled from the type's table with a RandomNumberGenerator
## seeded by (town seed, container index). The numbers are assets/data/prison_raids.json. Items: parts and fuel are ordinary backpack items (items.json parts_box, fuel_can; the grid, loot window, bank
## and stash carry them as the stock units `parts` and `fuel`), so the pack's 32 cells are the choice. The inventory pattern is the existing data-driven grid (items.json + scripts/sim/inventory.gd),
## not a Resource per item: the pack already is one.
## Owned by prison_game.gd (`loot`, `# RAIDS hook`). `--loot-lab=N` prints the distribution (see `lab`).
extends RefCounted

const TownGen := preload("res://scripts/town/town_gen.gd")
const PATH := "res://assets/data/prison_raids.json"
const TILE := 64.0

static var _cfg := {}

var game
var places: Array = []    # [{house, type, pos (Vector2, tiles), n (containers)}]
var target: Array = []    # place types marked on the map
var option := 0
var picked := -1    # the gate's choice, used by the next raid    # the chosen option of cfg.options
var choosing := false
var _panel: PanelContainer
var _buttons: Array = []
var _title: Label
var _sub: Label


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if parsed is Dictionary else {}
	return _cfg


func _init(g = null) -> void:
	game = g


# ------------------------------------------------------------------ the post-pass --

static func _h(a: int, b: int) -> int:
	return ((a * 73856093) ^ (b * 19349663)) & 0x7fffffff


## Retags the buildings and re-rolls the containers' loot of a town. Returns the places [{house, type, pos, n}] (a building, or one ROOM of a building when the town has too few buildings for the minimums).
static func prepare(t: Dictionary, seed_i: int) -> Array:
	var c := cfg()
	var natural: Dictionary = c.natural
	var by_house := {}    # house id -> container indexes
	for ci in t.containers.size():
		var hid := int(t.containers[ci].house)
		if not by_house.has(hid):
			by_house[hid] = []
		(by_house[hid] as Array).append(ci)
	var type_of := {}    # house id -> type
	var room_type := {}    # room index -> type (a room that is a place of its own)
	var start_id := int(t.start.house)
	for h in t.houses:
		var hid := int(h.id)
		if by_house.has(hid) and bool(h.get("main", true)):
			type_of[hid] = String(natural.get(String(h.kind), "house"))
	for ty in c.retag_order:
		var have := _count(type_of, room_type, ty)
		while have < int(c.min_places.get(ty, 0)):
			var pool: Array = []
			for hid in type_of:
				var cur := String(type_of[hid])
				if int(hid) != start_id and cur != ty and _count(type_of, room_type, cur) > int(c.min_places.get(cur, 0)):    # (a type above its minimum gives one building up)
					pool.append(int(hid))
			if not pool.is_empty():
				pool.sort_custom(func(a, b): return _h(seed_i, a) < _h(seed_i, b))
				type_of[pool[0]] = ty
			else:    # too few buildings: a room of the building with most containers becomes the place
				var rooms: Array = []
				for hid in type_of:
					for ci in by_house[hid]:
						var rm := int(t.containers[ci].room)
						if not room_type.has(rm) and not rooms.has(rm):
							rooms.append(rm)
				if rooms.size() < 2:
					break
				rooms.sort_custom(func(a, b): return _h(seed_i, a + 977) < _h(seed_i, b + 977))
				room_type[rooms[0]] = ty
			have += 1
	var out: Array = []
	for h in t.houses:
		var hid := int(h.id)
		if type_of.has(hid):
			var n := 0
			for ci in by_house[hid]:
				if not room_type.has(int(t.containers[ci].room)):
					n += 1
			if n > 0:
				out.append({"house": hid, "type": String(type_of[hid]), "pos": Rect2(h.rect).get_center(), "n": n})
	for rm in room_type:
		out.append({"house": -1, "room": int(rm), "type": String(room_type[rm]), "pos": Rect2(t.rooms[int(rm)].rect).get_center(), "n": 1})
	for ci in t.containers.size():
		var ct: Dictionary = t.containers[ci]
		var rng := RandomNumberGenerator.new()
		rng.seed = _h(seed_i, ci + 1)
		var ty := String(room_type.get(int(ct.room), type_of.get(int(ct.house), "house")))
		ct["loot"] = roll(ty, String(ct.kind), rng)
		ct["place"] = ty
	return out


static func _count(type_of: Dictionary, room_type: Dictionary, ty: String) -> int:
	var n := 0
	for hid in type_of:
		if type_of[hid] == ty:
			n += 1
	for rm in room_type:
		if room_type[rm] == ty:
			n += 1
	return n


## What one container of a place type holds: {res: n}.
static func roll(ty: String, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var c := cfg()
	var rolls: Array = c.rolls[ty]
	var k: Dictionary = c.kinds.get(kind, {})
	var only: Array = k.get("only", [])
	var use: Array = []
	for r in rolls:
		if only.is_empty() or only.has(String(r[0])):
			use.append(r)
	if use.is_empty():
		use = rolls
	var loot := {}
	for r in use:
		var p := float((k.get("p", {}) as Dictionary).get(String(r[0]), r[1]))
		if rng.randf() < p:
			loot[String(r[0])] = int(loot.get(String(r[0]), 0)) + rng.randi_range(int(r[2]), int(r[3]))
	return loot


# ------------------------------------------------------------------ the raid's marks --

## A raid starts: the town is retagged (before the stage is made) and the target is the choice made at the gate (else the biggest need).
func begin(t: Dictionary, seed_i: int) -> void:
	places = prepare(t, seed_i)
	t["places"] = places
	var o := default_option()
	if game.args.has("target"):
		o = int(game.args.target)
	if picked >= 0:
		o = picked
		picked = -1
	option = clampi(o, 0, (cfg().options as Array).size() - 1)
	target = []
	for ty in cfg().options[option].types:
		target.append(String(ty))


## The option the base needs most now (the econ's biggest shortage), 0 when nothing is short.
func default_option() -> int:
	var nd: Dictionary = game.econ.needs()
	if nd.is_empty():
		return 0
	var res := String(nd.res)
	var opts: Array = cfg().options
	for i in opts.size():
		if (opts[i].res as Array).has(res):
			return i
	return 0


func hint() -> String:
	var names: Array = []
	var hs: Array = []
	for ty in target:
		names.append(String(cfg().names[ty]))
		hs.append(String(cfg().hints[ty]))
	return "Marked: %s (%s)" % [" / ".join(names), "; ".join(hs)] if not target.is_empty() else ""


func _col(ty: String) -> Color:
	return Color(String(cfg().colors[ty]))


func _on_map(ty: String) -> bool:
	return target.has(ty)


## World overlay (px): a ring and a name on each marked place; the others only name themselves when Ruth is near.
func paint(c: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	var me := Vector2(game.run.avatar_p.x, game.run.avatar_p.y)
	var pulse := 0.5 + 0.5 * sin(game.clock * 3.0)
	var big := maxf(1.0, 22.0 / game.zoom_px * 2.0)    # (the overview: rings and names grow so that they can be seen)
	for pl in places:
		var ty := String(pl.type)
		var at: Vector2 = Vector2(pl.pos) * TILE
		var col := _col(ty)
		if _on_map(ty):
			var rad := 2.6 * TILE * big
			c.draw_circle(at, rad, Color(col, 0.16 + 0.1 * pulse))
			c.draw_arc(at, rad, 0, TAU, 36, Color(col, 0.95), 5.0 * big)
			c.draw_arc(at, rad * 0.62, 0, TAU, 28, Color(col, 0.6), 2.0 * big)
			c.draw_string(font, at - Vector2(170.0 * big, rad + 6.0), "%s: %s" % [String(cfg().names[ty]), String(cfg().hints[ty])], HORIZONTAL_ALIGNMENT_CENTER, 340.0 * big, int(22.0 * big), col)
		elif me.distance_to(Vector2(pl.pos)) < 16.0 and ty != "house":
			c.draw_string(font, at - Vector2(70, 10), String(cfg().names[ty]), HORIZONTAL_ALIGNMENT_CENTER, 140, 14, Color(col, 0.75))


## The minimap (`o`: its corner in px, `sc`: px per tile): a coloured ring on each marked place.
func mini(bars: Control, o: Vector2, sc: float) -> void:
	for pl in places:
		if _on_map(String(pl.type)):
			bars.draw_arc(o + Vector2(pl.pos) * sc, 4.5, 0, TAU, 14, _col(String(pl.type)), 2.0)
			bars.draw_circle(o + Vector2(pl.pos) * sc, 1.6, _col(String(pl.type)))


# ------------------------------------------------------------------ the gate's choice --

## E at the truck: opens the choice (true: the game must not go out yet).
func open_choice() -> bool:
	if game.args.has("target") or game.args.has("auto") or choosing:
		return false
	choosing = true
	var def := default_option()
	option = def
	if _panel == null:
		_build()
	var nd: Dictionary = game.econ.needs()
	_sub.text = String(nd.get("reason", "Nothing is short. Pick what to hunt.")) if not nd.is_empty() else "Nothing is short. Pick what to hunt."
	for i in _buttons.size():
		var o: Dictionary = cfg().options[i]
		var tys: Array = []
		for ty in o.types:
			tys.append(String(cfg().names[ty]))
		(_buttons[i] as Button).text = "%d   %s   (%s)%s" % [i + 1, String(o.name), ", ".join(tys), "     <- the base needs this" if i == def else ""]
	_panel.visible = true
	_panel.reset_size()
	_panel.position = game._vp() / 2.0 - Vector2(330, 140)
	return true


func _build() -> void:
	_panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.07, 0.94)
	st.border_color = Color(0.85, 0.7, 0.3)
	st.set_border_width_all(2)
	st.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	_title = Label.new()
	_title.text = "Where to? (number key or click, E or Enter: what the base needs, Esc: stay)"
	_title.add_theme_font_size_override("font_size", 18)
	col.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 16)
	_sub.modulate = Color(1, 0.85, 0.5)
	col.add_child(_sub)
	for i in (cfg().options as Array).size():
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _pick(i))
		col.add_child(b)
		_buttons.append(b)
	_panel.visible = false
	game.hud.add_child(_panel)


func _pick(i: int) -> void:
	choosing = false
	_panel.visible = false
	picked = i
	game._go_out()


## Keys while the choice is open. True when used.
func key(ev: InputEvent) -> bool:
	if not choosing or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return false
	var k: int = ev.keycode
	if k >= KEY_1 and k < KEY_1 + _buttons.size():
		_pick(k - KEY_1)
	elif k == KEY_E or k == KEY_ENTER or k == KEY_KP_ENTER:
		_pick(default_option())
	elif k == KEY_ESCAPE:
		choosing = false
		_panel.visible = false
	return true


# ------------------------------------------------------------------ the lab --

## `--loot-lab=N`: N raid towns (seeds 1..N), place counts per type, the share of seeds with every type, and what a 3-minute raid finds (nearest container first, 4 tiles a second plus 6 seconds
## a container; the targeted one hunts the places of each option in turn and takes the others only when they are near). Prints LOOTLAB lines.
static func lab(n: int) -> void:
	var c := cfg()
	var types: Array = (c.rolls as Dictionary).keys()
	var count := {}
	var seeds_with := {}
	var sums := {}
	var tsums := {}
	var allres := ["food", "water", "meds", "scrap", "parts", "fuel", "ammo"]
	var rmin := {}
	var rmax := {}
	for ty in types:
		count[ty] = 0
		seeds_with[ty] = 0
	for r in allres:
		sums[r] = 0.0
		tsums[r] = 0.0
		rmin[r] = 999
		rmax[r] = 0
	for s in range(1, n + 1):
		var t: Dictionary = TownGen.make(s, c.town_opts)
		var pls := prepare(t, s)
		var has := {}
		for p in pls:
			count[p.type] = int(count[p.type]) + 1
			has[p.type] = true
		for ty in has:
			seeds_with[ty] = int(seeds_with[ty]) + 1
		var got := _sim_raid(t, pls, [])
		for r in allres:
			sums[r] += float(got.get(r, 0))
			rmin[r] = mini(int(rmin[r]), int(got.get(r, 0)))
			rmax[r] = maxi(int(rmax[r]), int(got.get(r, 0)))
		var opt: Array = c.options[s % c.options.size()].types
		var g2 := _sim_raid(t, pls, opt)
		var o: Array = c.options[s % c.options.size()].res
		for r in allres:
			if o.has(r) or r == "food" or r == "water":
				tsums[r] += float(g2.get(r, 0)) if o.has(r) else 0.0
	print("LOOTLAB seeds ", n, " (town opts ", c.town_opts, ")")
	for ty in types:
		print("LOOTLAB place %-9s avg %.1f per town, in %d%% of seeds" % [ty, float(count[ty]) / n, roundi(100.0 * float(seeds_with[ty]) / n)])
	for r in allres:
		print("LOOTLAB 3-min raid, nobody told where: %-6s avg %.1f  (min %d, max %d)" % [r, sums[r] / n, rmin[r], rmax[r]])
	var per := n / float((c.options as Array).size())
	for r in allres:
		print("LOOTLAB 3-min raid hunting %-6s only when it is the target: avg %.1f" % [r, tsums[r] / maxf(1.0, per)])


## One greedy raid of 180 s: {res: units}.
static func _sim_raid(t: Dictionary, pls: Array, hunt: Array) -> Dictionary:
	var pos: Vector2 = Vector2(t.entry.pos)
	var left: Array = (t.containers as Array).duplicate()
	var secs := 180.0
	var got := {}
	while secs > 0.0 and not left.is_empty():
		var best := -1
		var bc := 1.0e9
		for i in left.size():
			var d := pos.distance_to(Vector2(left[i].pos))
			var cost := d
			if not hunt.is_empty() and not hunt.has(String(left[i].place)):
				cost += 25.0
			if cost < bc:
				bc = cost
				best = i
		var ct: Dictionary = left[best]
		var d2 := pos.distance_to(Vector2(ct.pos))
		secs -= d2 / 4.0 + 6.0
		if secs < 0.0:
			break
		pos = Vector2(ct.pos)
		for r in ct.loot:
			got[r] = int(got.get(r, 0)) + int(ct.loot[r])
		left.remove_at(best)
	return got
