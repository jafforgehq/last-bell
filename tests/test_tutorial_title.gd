extends "res://tests/case.gd"
## What the title says about Orientation Day (the menu line and the first launch's card) is true of the lesson the player then plays:
## it is the game as it is played (walking and shooting as Ruth, the crew over the radio), not the old yard's orders, and its buttons
## still do what they say. A run that is not the lesson is untouched.

const Tut := preload("res://tests/tutorial_kit.gd")
const HudKit := preload("res://tests/hud_kit.gd")
const Prefs := preload("res://scripts/prefs.gd")
const TitleMenu := preload("res://scripts/ui/title_menu.gd")
const OrientationCard := preload("res://scripts/ui/orientation_card.gd")

## What a card or a line of the title may not say of the lesson: the old yard's controls.
const OLD_YARD := ["right-click", "select", "draft", "pan with", "drag", "box"]


func test_the_menu_line_says_what_the_lesson_teaches_now() -> void:
	var main = Tut.start({"title": true})
	await Tut.frames(main, 3)
	var line: Button = main.shell.title.items["orientation"]
	var words := HudKit.texts(line)
	check(words.has("Orientation Day"), "the line is called Orientation Day: %s" % str(words))
	check(words.has(TitleMenu.ORIENTATION_BLURB), "and says '%s': %s" % [TitleMenu.ORIENTATION_BLURB, str(words)])
	for w in words:
		for old in OLD_YARD:
			check(not String(w).to_lower().contains(old), "'%s' does not name the old yard's '%s'" % [w, old])
	check(TitleMenu.ORIENTATION_BLURB.to_lower().contains("walk") and TitleMenu.ORIENTATION_BLURB.to_lower().contains("shoot") and TitleMenu.ORIENTATION_BLURB.to_lower().contains("radio"), "it names walking, shooting and the radio")
	await Tut.leave(main)


func test_the_first_launch_card_says_what_the_lesson_teaches_and_its_buttons_are_the_same() -> void:
	var main = Tut.start({"title": true})
	await Tut.frames(main, 3)
	var picked: Array = []
	main.restart = func(meta): picked.append(meta)
	Prefs.set_flag("tutorial_offered", false)
	main.shell.show_title()
	await Tut.settle()
	eq(main.shell.kinds(), ["orientation"], "the first time: the card")
	var card = main.shell.top()
	var texts := HudKit.texts(card)
	check(texts.has("First time here?"), "it asks")
	var body := ""
	for t in texts:
		if String(t).begins_with("Orientation Day teaches the basics in about eight minutes"):
			body = String(t)
	check(body != "", "and says what it is: %s" % str(texts))
	for word in ["Ruth", "radio", "gate", "bell", "skip"]:
		check(body.contains(word), "it names '%s': %s" % [word, body])
	for old in OLD_YARD:
		check(not body.to_lower().contains(old), "and not the old yard's '%s'" % old)
	eq(card.start_button.text, "Start Orientation Day", "the answer yes")
	eq(card.later_button.text, "Not now", "and the answer no")
	card.start_button.pressed.emit()
	await Tut.settle()
	eq(picked, [{"tutorial": true, "avatar": true}], "Start Orientation Day asks for the avatar's lesson")
	await Tut.leave(main)


func test_the_card_body_is_the_one_the_screen_shows() -> void:
	check(OrientationCard.BODY.begins_with("Orientation Day teaches the basics in about eight minutes"), "it still begins as it did")
	check(OrientationCard.BODY.contains("main menu"), "and still says it can be played again from the main menu")
	check(OrientationCard.BODY.contains("skip it"), "and that it can be skipped at any step")
	check(TitleMenu.ORIENTATION_BLURB.contains("eight minutes"), "the menu's line says eight minutes too (%s)" % TitleMenu.ORIENTATION_BLURB)
