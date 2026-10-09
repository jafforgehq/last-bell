## The list of saves: each slot with its day, time and difficulty (read from the file by
## SaveGame.peek). A save that is damaged or from another version says so and is never
## loaded; an empty slot says it is empty.
extends "res://scripts/ui/menu_screen.gd"

## True from the pause menu: loading throws the game being played away.
var replaces_game := false
## One per slot, in order: {"button", "slot", "info"}.
var rows: Array = []
var error_label: Label
var back_button: Button


func _init() -> void:
	kind = "load"
	max_w = 540.0


func _build_body() -> void:
	var now := int(Time.get_unix_time_from_system())
	var all: Array = shell.peeks()
	for p in all:
		var info: Dictionary = p.info
		var slot: Dictionary = p.slot
		var b: Button = shell.menu_item(String(slot.name), _words(info, slot, now))
		var sub: Label = b.get_meta("sub")
		if not bool(info.get("ok", false)):
			sub.add_theme_color_override("font_color", hud.INK3 if (not bool(info.get("exists", false)) or bool(info.get("incompatible", false))) else hud.DANGER_TEXT)
			if bool(info.get("incompatible", false)):
				# (SAVE4: a save of another version is listed greyed, not hidden: a click says why in a card)
				b.modulate = Color(1, 1, 1, 0.55)
		b.pressed.connect(_pick.bind(p))
		body.add_child(b)
		rows.append({"button": b, "slot": slot, "info": info})
	error_label = note("", hud.DANGER_TEXT, 14)
	error_label.visible = false
	body.add_child(error_label)
	if replaces_game:
		body.add_child(note("Loading replaces the game you are playing.", ink3(), 13))


## The second line of a slot: what is in it, or why it cannot be loaded.
func _words(info: Dictionary, slot: Dictionary, now: int) -> String:
	if bool(info.get("ok", false)):
		# (a town run begins with one survivor: "1 of 1 alive" is "alone")
		var who := "alone" if int(info.crew) == 1 and int(info.people) == 1 else "%d of %d alive" % [int(info.people), int(info.crew)]
		var line_text := "%s · %s" % [Kit.save_line(info), who]
		var ago := Kit.ago_text(int(info.modified), now)
		return line_text + (" · " + ago if ago != "" else "")
	if not bool(info.get("exists", false)):
		return "Nothing saved here yet · %s" % String(slot.get("note", ""))
	if bool(info.get("incompatible", false)):
		return "%s: cannot be continued" % String(info.get("reason", "Older version")).to_lower()
	return "%s: this save cannot be loaded" % String(info.get("reason", "Damaged"))


func _build_foot() -> void:
	back_button = button("Back", true)
	back_button.pressed.connect(close)
	foot.add_child(back_button)


func default_focus() -> Control:
	# the first save that can be loaded, else the first line
	for r in rows:
		if bool(r.info.get("ok", false)):
			return r.button
	return rows[0].button if not rows.is_empty() else back_button


func _pick(p: Dictionary) -> void:
	var info: Dictionary = p.info
	var slot: Dictionary = p.slot
	if bool(info.get("ok", false)):
		# the game reloads with the save; if it cannot, the shell has said so
		shell.load_slot(String(slot.path))
		return
	if bool(info.get("incompatible", false)):
		shell.load_slot(String(slot.path))    # (the card: this save is from another version of the game)
		return
	shell.play("ui_error")
	error_label.visible = true
	if bool(info.get("exists", false)):
		error_label.text = "The %s is damaged or from another version, so it was not loaded." % String(slot.name).to_lower()
	else:
		error_label.text = "There is nothing in the %s yet." % String(slot.name).to_lower()
