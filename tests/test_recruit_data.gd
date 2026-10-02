extends "res://tests/case.gd"
## The data of the survivors who call over the radio (round 7): assets/data/recruits.json (names, roles
## with their weapons, skills, traits and radio lines, the palettes and styles of a look, the portraits),
## the portraits themselves (assets/portraits/gen_*.png, made by tools/make_portraits.py) and the voice
## (barks.json: "generic") that a person with none of their own speaks in. The rules that use them
## (calls, arrivals, beds) are tested in test_recruits.gd; here the data is read as the game reads it:
## 300 survivors are made from it and every one of them can be added, drawn, heard and kept alive.

const Helpers := preload("res://tests/helpers.gd")
const Recruits := preload("res://scripts/sim/recruits.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")

const PATH := "res://assets/data/recruits.json"
const PORTRAIT_SIZE := 192
const PORTRAITS := 16
## What the figure's drawing knows (src/art/pawn.js of the prototype, baked into assets/pawns and
## assets/portraits). A look that uses anything else would be drawn as a plain figure.
const HAIR := ["short", "buzz", "curly", "twists", "messy", "ponytail", "long", "bald", "balding"]
const TOPS := ["tee", "shirt", "hoodie", "scrubs", "coverall", "uniform"]
const OUTERS := ["jacket", "cardigan", "vest", "hivis"]
const BEARDS := ["full", "stubble"]
const HATS := ["cap", "beanie"]
const BELTS := ["tools", "plain"]
## The yes-or-no extras (`extras` of the data sets one of these to true).
const FLAGS := ["glasses", "bandolier", "beard", "mustache", "patch", "armband"]
const LOOK_KEYS := ["seed", "skin", "hair", "hairColor", "browColor", "beard", "beardColor", "mustache", "top", "topStyle", "tie", "outer",
	"outerStyle", "pants", "shoes", "glasses", "bandolier", "backpack", "belt", "armband", "patch", "hat", "hatColor"]
## The most any of the authored six has in each skill is 8 to 10; a caller is never better than 8.
const SKILL_CAP := 8
const BANNED := ["zombie", "undead", "apocalypse", "walking dead"]


func _data() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	return parsed if parsed is Dictionary else {}


func _hex_ok(v) -> bool:
	return typeof(v) == TYPE_STRING and String(v).length() == 7 and String(v).begins_with("#") and Color.html_is_valid(String(v))


func _plain_text(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) < 32 or text.unicode_at(i) > 126:
			return false
	return true


func _words(text: String) -> PackedStringArray:
	var re := RegEx.create_from_string("[A-Za-z']+")
	var out := PackedStringArray()
	for m in re.search_all(text):
		out.append(m.get_string())
	return out


func _terminators(text: String) -> int:
	var n := 0
	for ch in [".", "?", "!"]:
		n += text.count(ch)
	return n


func _load_portrait(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


## A look must use only styles and colours the art draws: `where` says whose it is.
func _check_look(look: Dictionary, where: String, with_hat: bool = true) -> void:
	for k in look:
		check(LOOK_KEYS.has(String(k)), "%s: '%s' is not something a look has" % [where, k])
	for k in ["skin", "hairColor", "top", "pants", "shoes"]:
		check(_hex_ok(look.get(k)), "%s: %s is a colour: %s" % [where, k, look.get(k)])
	check(HAIR.has(String(look.get("hair", ""))), "%s: hair '%s' is drawn" % [where, look.get("hair")])
	check(TOPS.has(String(look.get("topStyle", ""))), "%s: top '%s' is drawn" % [where, look.get("topStyle")])
	check(_hex_ok(look.get("outer")) and OUTERS.has(String(look.get("outerStyle", ""))), "%s: outer %s '%s' is drawn" % [where, look.get("outer"), look.get("outerStyle")])
	for k in ["browColor", "beardColor", "backpack", "hatColor", "tie"]:
		if look.has(k):
			check(_hex_ok(look[k]), "%s: %s is a colour: %s" % [where, k, look[k]])
	if look.has("beard"):
		check(typeof(look.beard) == TYPE_BOOL or BEARDS.has(String(look.beard)), "%s: beard '%s'" % [where, look.beard])
	if look.has("belt"):
		check(BELTS.has(String(look.belt)), "%s: belt '%s'" % [where, look.belt])
	if look.has("hat"):
		check(with_hat and HATS.has(String(look.hat)) and _hex_ok(look.get("hatColor")), "%s: hat '%s' %s is drawn" % [where, look.hat, look.get("hatColor")])
	for k in ["mustache", "glasses", "bandolier", "armband", "patch"]:
		if look.has(k):
			check(typeof(look[k]) == TYPE_BOOL, "%s: %s is a yes or no" % [where, k])
	# clothes are muted like the authored six, skin is skin, hair is a hair colour
	for k in ["top", "outer", "pants", "shoes"]:
		if _hex_ok(look.get(k)):
			var c := Color.html(String(look[k]))
			check(c.s <= 0.78, "%s: %s is muted: %s (saturation %.2f)" % [where, k, look[k], c.s])
	if _hex_ok(look.get("skin")):
		var s := Color.html(String(look.skin))
		check(s.v >= 0.28 and s.v <= 0.95 and s.s >= 0.12 and s.s <= 0.62 and s.h >= 0.02 and s.h <= 0.12, "%s: skin %s is a skin" % [where, look.skin])
	if _hex_ok(look.get("hairColor")):
		var h := Color.html(String(look.hairColor))
		check(h.v <= 0.86 and h.s <= 0.75, "%s: hair %s is a hair colour" % [where, look.hairColor])


# ------------------------------------------------------------------ the file --

func test_the_file_is_there_and_has_everything() -> void:
	var d := _data()
	check(not d.is_empty(), "assets/data/recruits.json parses")
	eq(int(d.get("version", 0)), 1, "version 1")
	for k in ["first", "last", "roles", "looks", "portraits", "bitten_chance"]:
		check(d.has(k), "has %s" % k)
	near(float(d.get("bitten_chance", -1.0)), 0.08, 1e-9, "a few in a hundred are bitten")
	check(d.get("looks") is Dictionary, "looks")
	for k in ["skin", "hair", "tops", "outers", "pants", "shoes", "extras"]:
		check(d.get("looks", {}).has(k), "looks have %s" % k)


func test_the_names_are_plain_and_varied() -> void:
	var d := _data()
	var firsts: Array = d.get("first", [])
	var lasts: Array = d.get("last", [])
	check(firsts.size() >= 36 and firsts.size() <= 60, "about forty first names: %d" % firsts.size())
	check(lasts.size() >= 28 and lasts.size() <= 50, "about thirty last names: %d" % lasts.size())
	var authored := ["ruth", "dez", "ana", "marcus", "walt", "hector", "okafor", "marlow", "reyes", "bell", "haney", "ruiz"]
	for list in [firsts, lasts]:
		var seen := {}
		for n in list:
			var name := String(n)
			check(name.length() >= 2 and name.length() <= 11, "a name that fits a card: '%s'" % name)
			var re := RegEx.create_from_string("^[A-Z][a-z]+$")
			check(re.search(name) != null, "one plain capitalised word: '%s'" % name)
			check(not seen.has(name), "no name twice: %s" % name)
			check(not authored.has(name.to_lower()), "not the name of one of the six: %s" % name)
			seen[name] = true


func test_every_role_is_complete_and_sane() -> void:
	var g := Helpers.make(3, 1, 3)
	var d := _data()
	var roles: Array = d.get("roles", [])
	check(roles.size() >= 12, "about twelve roles: %d" % roles.size())
	var names := {}
	var weapons := {}
	var traits: Array = g.sim.traits.order
	for r in roles:
		var role := String(r.get("role", ""))
		check(role.length() >= 3 and role.length() <= 20 and _plain_text(role), "a role name that fits: '%s'" % role)
		check(not names.has(role), "no role twice: %s" % role)
		names[role] = true
		check(float(r.get("weight", 0.0)) > 0.0, "%s: a weight" % role)
		check(g.sim.weapons.has(String(r.get("weapon", ""))), "%s: a weapon the game has: %s" % [role, r.get("weapon")])
		weapons[String(r.get("weapon", ""))] = true
		var skills: Dictionary = r.get("skills", {})
		eq(skills.keys().size(), Recruits.SKILLS.size(), "%s: a range for each skill" % role)
		var high := 0
		var best := ""
		var best_hi := -1
		for k in Recruits.SKILLS:
			var range_: Array = skills.get(k, [])
			check(range_.size() == 2, "%s/%s: a low and a high" % [role, k])
			if range_.size() != 2:
				continue
			var lo := int(range_[0])
			var hi := int(range_[1])
			check(lo >= 0 and lo <= hi and hi <= SKILL_CAP, "%s/%s: %d to %d is a range up to %d" % [role, k, lo, hi, SKILL_CAP])
			if hi > 6:
				high += 1
			if hi > best_hi:
				best_hi = hi
				best = k
		check(high <= 2, "%s: at most a specialty or two above 6, the rest 0 to 6 (%d)" % [role, high])
		check(best_hi >= 5, "%s: good at something (%s up to %d)" % [role, best, best_hi])
		if best_hi > 6:
			check(int(skills.get(best, [0, 0])[0]) >= 3, "%s: %s is what they are good at, from the low end too" % [role, best])
		var bias: Array = r.get("traits_bias", [])
		check(bias.size() >= 2, "%s: traits that fit the role" % role)
		for t in bias:
			check(traits.has(String(t)), "%s: a trait the game has: %s" % [role, t])
	for k in ["Nurse", "Paramedic"]:
		if names.has(k):
			var rr: Dictionary = roles[roles.map(func(x): return x.role).find(k)]
			eq(rr.skills.Medicine[0] >= 4, true, "%s is good with medicine" % k)
	for k in ["Carpenter", "Mechanic"]:
		if names.has(k):
			var rr: Dictionary = roles[roles.map(func(x): return x.role).find(k)]
			eq(rr.skills.Building[0] >= 4, true, "%s builds" % k)
	if names.has("Hunter"):
		var rr: Dictionary = roles[roles.map(func(x): return x.role).find("Hunter")]
		check(rr.skills.Shooting[0] >= 4 and rr.weapon == "hunting", "the hunter shoots, with the hunting rifle")
	check(weapons.size() >= 5, "the roles carry different weapons: %s" % str(weapons.keys()))
	g.world.free()


func test_the_radio_lines_read_like_a_voice_on_the_radio() -> void:
	var d := _data()
	var names := {}
	for n in d.get("first", []) + d.get("last", []):
		names[String(n).to_lower()] = true
	for n in ["ruth", "dez", "ana", "marcus", "walt", "hector"]:
		names[n] = true
	check(d.get("roles", []).size() >= 12, "there are roles to read")
	var first_person := RegEx.create_from_string("(?i)\\b(i|i'm|i've|i'd|i'll|my|me|we|we're|our)\\b")
	var seen := {}
	for r in d.get("roles", []):
		var role := String(r.get("role", ""))
		for key in ["line", "line_in"]:
			var text := String(r.get(key, ""))
			var where := "%s/%s" % [role, key]
			check(text == text.strip_edges() and _plain_text(text), "%s: plain text without stray spaces: '%s'" % [where, text])
			check(not text.contains("{") and not text.contains("}") and not text.contains("%"), "%s: no braces: '%s'" % [where, text])
			check(not seen.has(text), "%s: a line is only said by one role" % where)
			seen[text] = true
			for w in _words(text):
				check(not names.has(w.to_lower()), "%s: does not name anyone (%s)" % [where, w])
			for banned in BANNED:
				check(not text.to_lower().contains(banned), "%s: no '%s'" % [where, banned])
			check(first_person.search(text) != null, "%s: in the first person: '%s'" % [where, text])
		var line := String(r.get("line", ""))
		check(line.length() >= 70 and line.length() <= 260, "%s: the radio line is the length of a card's text: %d" % [role, line.length()])
		check(_terminators(line) >= 2 and _terminators(line) <= 4, "%s: two or three sentences: '%s'" % [role, line])
		var line_in := String(r.get("line_in", ""))
		check(line_in.length() >= 15 and line_in.length() <= 150, "%s: what they say at the gate is short: %d" % [role, line_in.length()])
		check(_terminators(line_in) >= 1 and _terminators(line_in) <= 3, "%s: one or two sentences at the gate" % role)


func test_the_looks_use_only_what_the_art_draws() -> void:
	var looks: Dictionary = _data().get("looks", {})
	check(looks.get("skin", []).size() >= 8, "skin tones: %d" % looks.get("skin", []).size())
	var lum_lo := 1.0
	var lum_hi := 0.0
	for c in looks.get("skin", []):
		check(_hex_ok(c), "a skin colour: %s" % c)
		if _hex_ok(c):
			lum_lo = minf(lum_lo, Color.html(String(c)).get_luminance())
			lum_hi = maxf(lum_hi, Color.html(String(c)).get_luminance())
	check(lum_hi - lum_lo >= 0.5 and lum_lo < 0.25 and lum_hi > 0.7, "skin runs from deep to fair: %.2f to %.2f" % [lum_lo, lum_hi])
	var styles := {}
	for h in looks.get("hair", []):
		check(HAIR.has(String(h.get("style", ""))), "hair style '%s' is drawn" % h.get("style"))
		styles[h.get("style")] = true
		check(h.get("colors", []).size() >= 1, "%s hair has colours" % h.get("style"))
		for c in h.get("colors", []):
			var col := Color.html(String(c)) if _hex_ok(c) else Color.MAGENTA
			check(_hex_ok(c) and col.v <= 0.86 and col.s <= 0.75, "a hair colour: %s" % c)
	check(styles.size() >= 7, "hair of seven styles or more: %s" % str(styles.keys()))
	for pair in [["tops", TOPS], ["outers", OUTERS]]:
		var seen := {}
		for e in looks.get(pair[0], []):
			check(pair[1].has(String(e.get("style", ""))), "%s: style '%s' is drawn" % [pair[0], e.get("style")])
			seen[e.get("style")] = true
			check(e.get("colors", []).size() >= 2, "%s/%s: some colours" % [pair[0], e.get("style")])
			for c in e.get("colors", []):
				var col := Color.html(String(c)) if _hex_ok(c) else Color.MAGENTA
				check(_hex_ok(c) and col.s <= 0.78, "%s: a muted colour: %s" % [pair[0], c])
		check(seen.size() >= 3, "%s of three styles or more: %s" % [pair[0], str(seen.keys())])
	for k in ["pants", "shoes"]:
		check(looks.get(k, []).size() >= 4, "%s: some colours" % k)
		for c in looks.get(k, []):
			check(_hex_ok(c) and Color.html(String(c)).s <= 0.78, "%s: a muted colour: %s" % [k, c])
	for k in looks.get("extras", {}):
		check(FLAGS.has(String(k)), "extra '%s' is drawn" % k)
		check(float(looks.extras[k]) >= 0.0 and float(looks.extras[k]) <= 0.4, "%s: a chance that is not most of them" % k)


# ------------------------------------------------------------------ portraits --

func test_the_portraits_are_there_and_are_different_faces() -> void:
	var d := _data()
	var paths: Array = d.get("portraits", [])
	eq(paths.size(), PORTRAITS, "sixteen portraits")
	var small: Array = []
	for i in paths.size():
		var path := String(paths[i])
		eq(path, "res://assets/portraits/gen_%02d.png" % i, "portrait %d is named in order" % i)
		var img := _load_portrait(path)
		check(img != null and not img.is_empty(), "%s loads as an image" % path)
		if img == null or img.is_empty():
			small.append(null)
			continue
		eq(Vector2i(img.get_width(), img.get_height()), Vector2i(PORTRAIT_SIZE, PORTRAIT_SIZE), "%s is as large as the authored six" % path)
		img.convert(Image.FORMAT_RGBA8)
		var lum_lo := 1.0
		var lum_hi := 0.0
		for y in range(0, PORTRAIT_SIZE, 8):
			for x in range(0, PORTRAIT_SIZE, 8):
				var c := img.get_pixel(x, y)
				check(c.a > 0.99, "%s is opaque at (%d, %d)" % [path, x, y])
				lum_lo = minf(lum_lo, c.get_luminance())
				lum_hi = maxf(lum_hi, c.get_luminance())
		check(lum_hi - lum_lo > 0.3, "%s has a face on a background (%.2f to %.2f)" % [path, lum_lo, lum_hi])
		img.resize(24, 24, Image.INTERPOLATE_LANCZOS)
		small.append(img)
	# and the six authored ones, to be told apart from them too
	for id in ["ruth", "dez", "ana", "marcus", "walt", "hector"]:
		var a := _load_portrait("res://assets/portraits/%s.png" % id)
		a.convert(Image.FORMAT_RGBA8)
		a.resize(24, 24, Image.INTERPOLATE_LANCZOS)
		small.append(a)
	for i in small.size():
		for j in range(i + 1, small.size()):
			if i >= PORTRAITS or small[i] == null or small[j] == null:
				continue
			var diff := 0.0
			for y in 24:
				for x in 24:
					var p: Color = small[i].get_pixel(x, y)
					var q: Color = small[j].get_pixel(x, y)
					diff += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
			diff /= 24.0 * 24.0 * 3.0
			check(diff > 0.035, "portrait %d and %d are different people (difference %.3f)" % [i, j, diff])


func test_the_portraits_have_the_looks_they_were_drawn_from() -> void:
	var d := _data()
	var pls: Array = d.get("portrait_looks", [])
	eq(pls.size(), PORTRAITS, "a look and a tint for each portrait")
	var skins := {}
	var hairs := {}
	for i in pls.size():
		var e: Dictionary = pls[i]
		check(_hex_ok(e.get("tint")), "portrait %d: a background tint" % i)
		_check_look(e.get("look", {}), "portrait %d" % i)
		skins[e.look.get("skin")] = true
		hairs[e.look.get("hair")] = true
	check(skins.size() >= 8, "the faces have different skins: %d" % skins.size())
	check(hairs.size() >= 7, "and different hair: %s" % str(hairs.keys()))


# ------------------------------------------------------------- 300 survivors --

## A small-start game with its recruits' generator, and the data for a node to draw a stand-in body.
func _game() -> Dictionary:
	var g := Helpers.make(17, 1, 3)
	g["node_data"] = {"pawn": {"box": g.data.pawn.box, "files": {"x": g.data.pawn.files.ruth}}, "weaponArt": g.data.weaponArt, "guns": g.data.guns, "objects": []}
	return g


## 300 survivors made from different seeds, with the indexes the game gives them, kept for the tests below.
func _three_hundred(g: Dictionary) -> Array:
	var sim = g.sim
	var out: Array = []
	for i in 300:
		sim.run_seed = 1000 + i * 7
		sim.recruits.start()
		out.append(sim.recruits.make_def(i))
	return out


func test_three_hundred_survivors_are_made_from_the_data_and_every_one_is_playable() -> void:
	var g := _game()
	var sim = g.sim
	var d := _data()
	var defs := _three_hundred(g)
	var roles := {}
	for r in d.roles:
		roles[String(r.role)] = r
	var generic: Dictionary = sim.barks.lines.get("generic", {})
	check(not generic.is_empty(), "the generic voice is loaded")
	var biased := 0
	var bitten := 0
	var nodes: Array = []
	var people: Array = []
	var drawn := {}
	for def in defs:
		var id := String(def.id)
		var name_parts := String(def.name).split(" ")
		check(name_parts.size() == 2 and d.first.has(name_parts[0]) and d.last.has(name_parts[1]), "%s: a first and a last name from the lists: %s" % [id, def.name])
		check(roles.has(String(def.role)), "%s: a role from the data: %s" % [id, def.role])
		var role: Dictionary = roles.get(String(def.role), {"skills": {}, "weapon": "", "traits_bias": []})
		eq(String(def.weapon), String(role.weapon), "%s: their role's weapon" % id)
		check(sim.weapons.has(String(def.weapon)) and sim.guns.has(String(def.weapon)), "%s: a weapon the game has and draws" % id)
		check(int(def.age) >= 18 and int(def.age) <= 67, "%s: a working age: %d" % [id, def.age])
		for k in Recruits.SKILLS:
			var range_: Array = role.skills.get(k, [1, 4])
			check(int(def.skills[k]) >= int(range_[0]) and int(def.skills[k]) <= int(range_[1]), "%s: %s %d is in its role's range" % [id, k, def.skills[k]])
			check(int(def.skills[k]) <= SKILL_CAP, "%s: nobody starts better than the authored six: %s %d" % [id, k, def.skills[k]])
		eq(def.traits.size(), 2, "%s: two traits" % id)
		for t in def.traits:
			if role.traits_bias.has(String(t)):
				biased += 1
				break
		check(String(def.line).length() >= 70 and not String(def.line).contains("{"), "%s: a radio line to show" % id)
		check(String(def.line_in) != "", "%s: a line at the gate" % id)
		check(String(def.portrait).begins_with("res://assets/portraits/gen_"), "%s: a portrait: %s" % [id, def.portrait])
		_check_look(def.look, id)
		if bool(def.bitten):
			bitten += 1
		# added to a game
		def["bitten"] = false
		var p = sim.add_person(def)
		check(sim.people.has(p) and p.id == id, "%s: is in the crew" % id)
		eq(sim.traits.of(p).size(), 2, "%s: has their traits" % id)
		check(sim.morale.value(p) > 0.0, "%s: has a mood" % id)
		# heard
		sim.t += 100.0
		sim.events.clear()
		sim.barks.say(p, "bell")
		var heard := 0
		for e in sim.events:
			if e.type == "bark" and e.who == id:
				heard += 1
				check(generic.bell.has(e.text), "%s: speaks the generic voice: %s" % [id, e.text])
		eq(heard, 1, "%s: says something at the bell" % id)
		# the body drawn on a node (below: in the tree, one frame for each side)
		var n = PawnNode.new()
		n.setup(p, false, g.node_data, "x")
		check(n.pal.skin.is_equal_approx(Color.html(String(def.look.skin))), "%s: the live hands and legs wear their skin and clothes" % id)
		n.draw.connect(func(): drawn[id] = int(drawn.get(id, 0)) + 1)
		nodes.append(n)
		people.append(p)
	# drawn from every side, each in a frame of its own (a node draws when it is in the tree)
	for n in nodes:
		g.world.add_child(n)
	var seen := 0
	for facing in ["S", "E", "N", "W"]:
		for i in nodes.size():
			people[i].facing = facing
			nodes[i].queue_redraw()
		await Engine.get_main_loop().process_frame
		seen += 1
		for i in nodes.size():
			eq(int(drawn.get(people[i].id, 0)), seen, "%s is drawn facing %s" % [people[i].id, facing])
	for n in nodes:
		n.queue_free()
	check(biased >= 150, "most of them have a trait that fits their role: %d of 300" % biased)
	check(bitten >= 8 and bitten <= 45, "a few are bitten at the gate: %d of 300" % bitten)
	g.world.free()


func test_roles_and_faces_are_spread() -> void:
	var g := _game()
	var d := _data()
	var defs := _three_hundred(g)
	var by_role := {}
	var portraits := {}
	var names := {}
	var skins := {}
	var hair := {}
	var weapons := {}
	var totals := 0
	var best := {}
	for def in defs:
		by_role[def.role] = int(by_role.get(def.role, 0)) + 1
		portraits[def.portrait] = true
		names[def.name] = true
		skins[def.look.skin] = true
		hair[def.look.hair] = true
		weapons[def.weapon] = true
		for k in Recruits.SKILLS:
			totals += int(def.skills[k])
			best[k] = maxi(int(best.get(k, 0)), int(def.skills[k]))
	for role in by_role:
		check(by_role[role] <= 75, "no role is a quarter of the callers: %s is %d of 300" % [role, by_role[role]])
	check(by_role.size() >= d.roles.size() - 1, "nearly every role comes up: %d of %d" % [by_role.size(), d.roles.size()])
	eq(portraits.size(), PORTRAITS, "every portrait is handed out")
	check(names.size() >= 250, "names are not repeated much: %d different of 300" % names.size())
	check(skins.size() >= 8 and hair.size() >= 7, "faces differ: %d skins, %d hairstyles" % [skins.size(), hair.size()])
	check(weapons.size() >= 5, "different weapons: %s" % str(weapons.keys()))
	# against the authored six: nobody is better in their strength, and the average caller is not the better of them
	var authored_best := {}
	var authored_total := 0
	for person in g.data.people:
		for k in Recruits.SKILLS:
			authored_best[k] = maxi(int(authored_best.get(k, 0)), int(person.skills[k]))
			authored_total += int(person.skills[k])
	for k in Recruits.SKILLS:
		check(int(best[k]) <= int(authored_best[k]), "%s: the best caller (%d) is no better than the best of the six (%d)" % [k, best[k], authored_best[k]])
	check(float(totals) / 300.0 <= float(authored_total) / 6.0, "the average caller (%.1f points) has less than the average of the six (%.1f)" % [float(totals) / 300.0, float(authored_total) / 6.0])
	# the first eight callers of a run have eight different portraits
	var first_eight := {}
	var one_run = g.sim
	one_run.run_seed = 4242
	one_run.recruits.start()
	for i in Recruits.MAX_GENERATED:
		var def: Dictionary = one_run.recruits.make_def(i)
		one_run.recruits.queue.append(def)    # as the game does: they wait in the queue
		first_eight[def.portrait] = true
	eq(first_eight.size(), Recruits.MAX_GENERATED, "the callers of one run look different from each other")
	g.world.free()


func test_a_game_day_with_sixteen_new_faces() -> void:
	for round_ in 2:
		var g := Helpers.make(61 + round_, 1, 3)
		var sim = g.sim
		sim.waves.enabled = false
		sim.zombies.clear()
		var added: Array = []
		for i in PORTRAITS:
			sim.run_seed = 500 + round_ * 40 + i
			sim.recruits.start()
			var def: Dictionary = sim.recruits.make_def(i + round_ * PORTRAITS)
			def["bitten"] = false
			added.append(sim.add_person(def))
		var day: int = sim.day
		for hour in 24:
			Helpers.run(sim, 20.0)
		eq(sim.day, day + 1, "a day has gone by")
		for p in added:
			check(not p.dead and not p.turned and p.hp > 0.0, "%s (%s) is alive after a day" % [p.name, p.def.role])
			check(is_finite(p.x) and is_finite(p.y) and p.x > 0.0 and p.y > 0.0 and p.x < float(g.data.W) and p.y < float(g.data.H), "%s is on the map" % p.name)
			check(String(p.activity) != "", "%s is doing something" % p.name)
			check(sim.morale.value(p) >= 0.0 and sim.morale.value(p) <= 100.0, "%s has a mood in range" % p.name)
		g.world.free()
