## EXPERIMENT (prison loadout, comp round): THE LOADOUT CARD. Two uses of one panel: at the start of the clear phase ("pick your weapon": the weapon row only) and at the gate, as the SECOND step of the gate's
## choice (the first is where to hunt, prison_loot.gd): the gun in her hands and a spare, how much ammo, medicine, food and water to carry, and WHO COMES (the squad, scripts/prison/prison_squad.gd), with what the
## base loses while they are out. Keys: W gun, X spare, A ammo, H meds, F food, D water, 1 to 9 a companion (click works on every row), Enter or E: go, Esc: back. The kit rows only show when the pack is empty
## (a pack she packed at the stash is taken as it is). Three PRESETS (RAID EXTRAS): Save keeps the gun, the spare, the kit and the companions chosen now under a number, a click on the number puts them back
## (what is not there any more is skipped); they are saved with the game (prison_raidx.gd). Owned by prison_game.gd (`loadout`, `# SQUAD hook`).
extends RefCounted

const PIcons := preload("res://scripts/prison/prison_icons.gd")
const Inventory := preload("res://scripts/sim/inventory.gd")
const UI := preload("res://scripts/prison/prison_ui.gd")    # the windows' one look and motion
const Fonts := preload("res://scripts/ui/fonts.gd")
const AMMO_STEPS := [0, 20, 40, 60, 80, 120]
const ROW_H := 36.0    # one squad row and its gap on the loadout card

var game
var is_open := false
var weapon_only := false
var kit := {"ammo": 40, "meds": 1, "food": 1, "water": 1}
var target_name := ""
var _panel: PanelContainer
var _col: VBoxContainer
var _scroll: ScrollContainer    # the squad's rows (shortened in a small window)


func _init(g) -> void:
	game = g


## `target`: what the raid hunts (the gate's choice), "" for the weapon card of the clear phase.
func open(target: String = "", only_weapon: bool = false) -> void:
	weapon_only = only_weapon
	target_name = target
	if not weapon_only:
		game.squad.snapshot()
		game.squad.picked = []
		kit = {"ammo": mini(40, floori(float(game.stores.ammo))), "meds": 1, "food": 1, "water": 1}
	game.arms.settle()
	is_open = true
	if _panel == null:
		_build()
	var was := _panel.visible
	_panel.visible = true
	_refresh()
	if not was:
		UI.open_fx(_panel)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.frame_box(14))
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 6)
	_panel.add_child(_col)
	game.hud.add_child(_panel)


func close() -> void:
	is_open = false
	if _panel != null:
		UI.close_fx(_panel)
		_panel.visible = false


func _lbl(text: String, size: int = UI.BODY_PX, col: Color = Color(1, 1, 0.9), wide: bool = true) -> Label:
	var l := UI.label(text, size, col)
	if wide:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(680, 0)
	return l


## A button of the card: `on` (the gun in her hands, a companion who comes) is the gold main-choice look.
func _btn(text: String, on: bool, cb: Callable, enabled: bool = true) -> Button:
	var b := UI.button(text, on)
	b.disabled = not enabled
	b.pressed.connect(cb)
	return b


func _row(label: String, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := _lbl(("%s  [%s]" % [label, key]) if key != "" else label, UI.BODY_PX, Color(0.85, 0.85, 0.75), false)
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	return h


func _refresh() -> void:
	for ch in _col.get_children():
		_col.remove_child(ch)
		ch.queue_free()
	var arms = game.arms
	var squad = game.squad
	_scroll = null
	var head := HBoxContainer.new()    # the title, and the keys beside it in small print
	head.add_theme_constant_override("separation", 14)
	head.add_child(UI.title("PICK YOUR WEAPON" if weapon_only else "LOADOUT - going for: %s" % target_name))
	var keys := _lbl("Enter: start   W: next gun" if weapon_only else "Enter: go out   Esc: back", UI.SMALL_PX, Color(0.75, 0.75, 0.7), false)
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(keys)
	_col.add_child(head)
	# the gun in her hands
	var wr := _row("Weapon", "W")
	for id in arms.choices():
		wr.add_child(_btn("%s x%d" % [arms.gun_name(String(id)), arms.owned(String(id))], String(id) == arms.main, func(): _set_main(String(id))))
	_col.add_child(wr)
	_col.add_child(_lbl("%s  (%s)" % [arms.blurb(arms.main), arms.stats_line(arms.main)], 14, Color(0.8, 0.9, 1.0)))
	if weapon_only:
		_place()
		return
	var sr := _row("Spare gun", "X")
	sr.add_child(_btn("none", arms.spare == "", func(): _set_spare("")))
	for id in arms.order():
		var gid := String(id)
		var free: int = arms.owned(gid) - (1 if gid == arms.main else 0)
		if free > 0:
			sr.add_child(_btn(arms.gun_name(gid), arms.spare == gid, func(): _set_spare(gid)))
	_col.add_child(sr)
	_col.add_child(_lbl("The weapon rack: %s.  A spare rides in the pack (B swaps it in); guns found out there come back to the rack. If she dies they are lost." % _rack_text(), 13, Color(0.75, 0.75, 0.7)))
	# the presets
	var pr := _row("Presets", "")
	for i in 3:
		var pd: Dictionary = game.raidx.presets[i]
		pr.add_child(_btn("%d: %s" % [i + 1, _preset_text(pd)], false, func(): apply_preset(i), not pd.is_empty()))
		pr.add_child(_btn("Save", false, func(): save_preset(i)))
	_col.add_child(pr)
	# the kit
	if Inventory.is_empty(game.pack.grid):
		var ar := _row("Ammo", "A")
		ar.add_child(_btn("-", false, func(): _step("ammo", -1)))
		ar.add_child(_lbl("%d units  (%s)" % [int(kit.ammo), _rounds_text(int(kit.ammo))], UI.BODY_PX, Color(1, 1, 0.9), false))
		ar.add_child(_btn("+", false, func(): _step("ammo", 1)))
		_col.add_child(ar)
		var mr := _row("Medicine", "H")
		mr.add_child(_btn("-", false, func(): _step("meds", -1)))
		mr.add_child(_lbl("%d" % int(kit.meds), UI.BODY_PX, Color(1, 1, 0.9), false))
		mr.add_child(_btn("+", false, func(): _step("meds", 1)))
		mr.add_child(_lbl("Food [F]", UI.BODY_PX, Color(0.85, 0.85, 0.75), false))
		mr.add_child(_btn("-", false, func(): _step("food", -1)))
		mr.add_child(_lbl("%d" % int(kit.food), UI.BODY_PX, Color(1, 1, 0.9), false))
		mr.add_child(_btn("+", false, func(): _step("food", 1)))
		mr.add_child(_lbl("Water [D]", UI.BODY_PX, Color(0.85, 0.85, 0.75), false))
		mr.add_child(_btn("-", false, func(): _step("water", -1)))
		mr.add_child(_lbl("%d" % int(kit.water), UI.BODY_PX, Color(1, 1, 0.9), false))
		mr.add_child(_btn("+", false, func(): _step("water", 1)))
		_col.add_child(mr)
		_col.add_child(_lbl("From the stores: ammo %d, meds %d, food %d, water %d." % [int(game.stores.ammo), int(game.stores.meds), int(game.stores.food), int(game.stores.water)], 13, Color(0.75, 0.75, 0.7)))
	else:
		_col.add_child(_lbl("Your pack is already packed from the stash: it goes as it is (ammo, medicine, food and water as you put them in).", 14, Color(0.8, 0.9, 1.0)))
	# the squad
	_col.add_child(_lbl("SQUAD: up to 2 come with you (number key or click). They carry their own bag and bring it back; they fire for free and never use your rounds.", 15, Color(1, 0.85, 0.4)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, maxf(0.0, minf(5.0, float(squad.cands.size())) * ROW_H - 2.0))    # (whole rows: five shown, the rest a scroll away)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll = scroll
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	_col.add_child(scroll)
	var n := 0
	for c in squad.cands:
		n += 1
		var id := String(c.id)
		var sel: bool = squad.picked.has(id)
		var can: Dictionary = squad.can_pick(id)
		var tags := " ".join(PackedStringArray(c.tags))
		var text := "[%s] %-7s %-13s hp %d  %s  bag %dx%d  %s" % [str(n) if n <= 9 else "-", String(c.name), String(c.role), int(c.hp), String(c.gun), int(c.bag.x), int(c.bag.y), tags]
		if not bool(can.ok) and not sel:
			text += "   - stays: %s" % String(can.why)
		var b := _btn(("> " if sel else "   ") + text, sel, func(): _toggle(id), bool(can.ok) or sel)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", Fonts.sans(500))    # (a row of the list reads as text, not as a label on a button)
		b.add_theme_font_size_override("font_size", UI.BODY_PX)
		var prow := HBoxContainer.new()    # PORTRAIT
		prow.custom_minimum_size.y = ROW_H - 2.0
		prow.add_child(PIcons.portrait_box(id, 26.0))
		prow.add_child(b)
		list.add_child(prow)
	if squad.cands.size() > 5:
		_col.add_child(_lbl("%d more below: scroll the list" % (squad.cands.size() - 5), 13, Color(0.75, 0.75, 0.7)))
	if squad.cands.is_empty():
		_col.add_child(_lbl("Nobody at the base can be spared.", 14))
	for line in squad.loss_lines():
		_col.add_child(_lbl("The base: %s." % line, 14, Color(1, 0.7, 0.55)))
	for line in squad.tower_warnings():
		_col.add_child(_lbl(line, 14, Color(1.0, 0.75, 0.25)))
	_place()


func _preset_text(pd: Dictionary) -> String:
	if pd.is_empty():
		return "empty"
	var n: int = (pd.get("picked", []) as Array).size()
	return "%s %s" % [game.arms.gun_name(String(pd.get("main", ""))), ("+%d" % n) if n > 0 else "solo"]


## Preset `i` keeps what the card shows now.
func save_preset(i: int) -> void:
	game.raidx.presets[i] = {"main": String(game.arms.main), "spare": String(game.arms.spare), "kit": kit.duplicate(), "picked": game.squad.picked.duplicate()}
	_refresh()


## Preset `i` put back on the card: the gun and the spare if the rack still holds them, the kit within the stores, the companions who can still go.
func apply_preset(i: int) -> void:
	var pd: Dictionary = game.raidx.presets[i]
	if pd.is_empty():
		return
	var arms = game.arms
	var main := String(pd.get("main", ""))
	if main != "" and arms.owned(main) > 0:
		arms.main = main
	var sp := String(pd.get("spare", ""))
	arms.spare = sp if sp != "" and arms.owned(sp) - (1 if sp == arms.main else 0) > 0 else ""
	var k: Dictionary = pd.get("kit", {})
	if Inventory.is_empty(game.pack.grid):
		kit.ammo = mini(int(k.get("ammo", kit.ammo)), floori(float(game.stores.ammo)))
		for r in ["meds", "food", "water"]:
			kit[r] = clampi(int(k.get(r, kit[r])), 0, mini(4, floori(float(game.stores[r]))))
	game.squad.picked = []
	for id in pd.get("picked", []):
		game.squad.toggle(String(id))
	_refresh()


func _place() -> void:
	_panel.reset_size()
	var v: Vector2 = game._vp()
	var top: float = (game.topbar.plate.position.y + game.topbar.plate.size.y + 6.0) if game.topbar.plate.visible else 8.0
	var room := v.y - top - 8.0
	if _scroll != null and _panel.size.y > room:    # (a small window: fewer squad rows show, the rest a scroll away, so the card's top no longer sits under the top bar)
		_scroll.custom_minimum_size.y = maxf(2.0 * ROW_H - 2.0, _scroll.custom_minimum_size.y - (_panel.size.y - room))
		_panel.reset_size()
	_panel.position = Vector2(round((v.x - _panel.size.x) / 2.0), round(clampf((v.y - _panel.size.y) / 2.0, top, maxf(top, v.y - 8.0 - _panel.size.y))))


func _rack_text() -> String:
	var parts: Array = []
	for id in game.arms.order():
		parts.append("%s x%d" % [game.arms.gun_name(String(id)), game.arms.owned(String(id))])
	return ", ".join(parts)


func _rounds_text(units: int) -> String:
	var g: Dictionary = game.data.weapons[game.arms.main]
	var per := 1.0 / maxf(float(g.get("cost", 0.2)), 0.001)
	return "%d %s" % [int(round(float(units) * per)), "shells" if game.arms.main == "shotgun" else "rounds"]


func _set_main(id: String) -> void:
	game.arms.main = id
	if game.arms.spare == id and game.arms.owned(id) < 2:
		game.arms.spare = ""
	if weapon_only and game.run != null:
		game.arms.set_gun(game.run.avatar_p, id)
	_refresh()


func _set_spare(id: String) -> void:
	game.arms.spare = id
	_refresh()


func _toggle(id: String) -> void:
	game.squad.toggle(id)
	_refresh()


func _step(res: String, d: int) -> void:
	if res == "ammo":
		var i := AMMO_STEPS.find(int(kit.ammo))
		if i < 0:
			i = 2
		kit.ammo = mini(int(AMMO_STEPS[clampi(i + d, 0, AMMO_STEPS.size() - 1)]), floori(float(game.stores.ammo)))
	else:
		kit[res] = clampi(int(kit[res]) + d, 0, mini(4, floori(float(game.stores[res]))))
	_refresh()


func _cycle_main() -> void:
	var ch: Array = game.arms.choices()
	if ch.is_empty():
		return
	_set_main(String(ch[(ch.find(game.arms.main) + 1) % ch.size()]))


func _cycle_spare() -> void:
	var opts: Array = [""]
	for id in game.arms.order():
		if game.arms.owned(String(id)) - (1 if String(id) == game.arms.main else 0) > 0:
			opts.append(String(id))
	_set_spare(String(opts[(opts.find(game.arms.spare) + 1) % opts.size()]))


func confirm() -> void:
	close()
	game.arms.settle()
	if weapon_only:
		return
	game.loadout_kit = kit.duplicate() if Inventory.is_empty(game.pack.grid) else {}
	game._go_out()


## Keys while the card is up. True when used (every key is: the game does not move behind it).
func key(ev: InputEvent) -> bool:
	if not is_open or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return false
	var k: int = ev.keycode
	match k:
		KEY_ENTER, KEY_KP_ENTER, KEY_E:
			confirm()
		KEY_ESCAPE:
			close()
			if not weapon_only:
				game.loot.open_choice()
		KEY_W:
			_cycle_main()
		KEY_X:
			if not weapon_only:
				_cycle_spare()
		KEY_A:
			if not weapon_only and Inventory.is_empty(game.pack.grid):
				_step("ammo", 1 if int(kit.ammo) < 120 else -5)
		KEY_H:
			if not weapon_only and Inventory.is_empty(game.pack.grid):
				kit.meds = (int(kit.meds) + 1) % 4
				_refresh()
		KEY_F:
			if not weapon_only and Inventory.is_empty(game.pack.grid):
				kit.food = (int(kit.food) + 1) % 5
				_refresh()
		KEY_D:
			if not weapon_only and Inventory.is_empty(game.pack.grid):
				kit.water = (int(kit.water) + 1) % 5
				_refresh()
		_:
			if not weapon_only and k >= KEY_1 and k <= KEY_9:
				var i := k - KEY_1
				if i < game.squad.cands.size():
					_toggle(String(game.squad.cands[i].id))
	return true


func blocks_fire() -> bool:
	return is_open
