## The dressing of the ring of streets (round 12, "the living streets"): the decals and light props that make the city
## round the base look like a place that fell (blood, a body by a car, papers, bags and bins along the sidewalk, the
## remains of a barricade at a mouth), drawn from assets/data/dressing.json (made by tools/make_dressing.py).
##
## - Only in a settlement game (`sim.town.on`, the game of the small crew): the classic start, the tutorial and the
##   title's yard look exactly as they always did, and have none of this node's sprites at all (they are made the first
##   time the rules say it is a settlement game, not before: `sim.town.on` turns true in `start_run` or a load, which comes
##   after the node is built, so `update()` asks every frame).
## - What lies on the ground (`flat`: blood, papers, a body) is drawn under the people, in a layer of its own at the
##   ground's height; what stands (a bin, a crate, a wheelbarrow) is drawn among them in the y-sorted node the people are
##   in, sorted by its feet (`sort`), so a person walks behind a crate and in front of a bench. Each standing piece is a
##   small node at its feet with the picture on it, so that a piece that is turned turns on its own middle.
## - Nothing here is solid and nothing touches the rules: the walking grids are the map's own.
## - The sprites are made once and shown or hidden when `sim.town.on` changes (a new run of the other kind, a load);
##   `_exit_tree` takes the standing ones out of the people's node with it.
extends Node2D

const GD := preload("res://scripts/game_data.gd")

const TILE := GD.TILE
const OBJECTS := "res://assets/objects/"
const DATA_PATH := "res://assets/data/dressing.json"
## The ground layer's height: with the baked low props (world.gd's Low layer), under the people (6).
const FLAT_Z := 2

static var _cache: Array = []
static var _loaded := false

var sim
## The y-sorted node the people are in (main.gd's `entities`), or one of the node's own when there is none.
var _tall: Node2D
var _own_tall: Node2D
var _flat: Node2D
var _standing: Array = []
var _lying: Array = []
var _files: Array = []
var _made := false
var _shown := false
## How many times the sprites were made (once, whatever the runs), for the tests.
var makes := 0


## `rules` is the sim (only `town.on` is read) and `stand_in` the y-sorted node the people are in, so that what
## stands is sorted among them.
func setup(rules, stand_in: Node2D = null) -> void:
	sim = rules
	_flat = Node2D.new()
	_flat.name = "Flat"
	_flat.z_index = FLAT_Z
	_flat.visible = false
	add_child(_flat)
	if stand_in != null:
		_tall = stand_in
	else:
		_own_tall = Node2D.new()
		_own_tall.name = "Tall"
		_own_tall.z_index = 6
		_own_tall.y_sort_enabled = true
		_own_tall.visible = false
		add_child(_own_tall)
		_tall = _own_tall
	update()


func _exit_tree() -> void:
	_forget()


## The pieces of assets/data/dressing.json (read once), [] when the file is not there.
static func pieces() -> Array:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(DATA_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if parsed is Dictionary:
				_cache = parsed.get("pieces", [])
	return _cache


## Whether the rules are of a settlement game.
func is_on() -> bool:
	if sim == null:
		return false
	var town = sim.get("town")
	return town != null and bool(town.on)


## Called every frame by main.gd: makes the sprites the first time the game is a settlement game, and shows them while it
## is one and hides them when it is not.
func update() -> void:
	var on := is_on()
	if on and not _made:
		_make()
	if on != _shown:
		_shown = on
		_apply()


func _apply() -> void:
	if _flat != null:
		_flat.visible = _shown
	if _own_tall != null:
		_own_tall.visible = _shown
	for n in _standing:
		if is_instance_valid(n):
			n.visible = _shown


func _make() -> void:
	_made = true
	makes += 1
	for p in pieces():
		var path := OBJECTS + String(p.f) + ".png"
		if not ResourceLoader.exists(path):
			continue
		var tex := GD.tex(path)
		var s := Sprite2D.new()
		s.texture = tex
		s.scale = Vector2(float(p.w) * TILE / float(tex.get_width()), float(p.h) * TILE / float(tex.get_height()))
		s.flip_h = bool(p.get("flip", false))
		s.rotation = deg_to_rad(float(p.get("rot", 0.0)))
		if bool(p.get("flat", false)):
			s.position = Vector2(float(p.x), float(p.y)) * TILE
			_flat.add_child(s)
			_lying.append(s)
		else:
			# the node is at the feet (what the people are sorted by) and the picture is on it, its middle where the
			# data says
			var feet := float(p.get("sort", float(p.y) + float(p.h) * 0.5))
			var at := Node2D.new()
			at.position = Vector2(float(p.x), feet) * TILE
			at.visible = false
			s.position = Vector2(0.0, (float(p.y) - feet) * TILE)
			at.add_child(s)
			_tall.add_child(at)
			_standing.append(at)
		_files.append(String(p.f))


func _forget() -> void:
	for n in _standing:
		if is_instance_valid(n):
			n.queue_free()
	_standing.clear()
	_lying.clear()
	_files.clear()
	_made = false


## How many pieces the data has (for the tests).
func piece_count() -> int:
	return pieces().size()


## How many sprites are made, lying and standing (for the tests).
func sprite_count() -> int:
	return _lying.size() + _standing.size()


## How many of them are shown on the screen now.
func visible_count() -> int:
	var n := 0
	if _flat != null and _flat.visible:
		n += _lying.size()
	if _own_tall == null or _own_tall.visible:
		for s in _standing:
			if is_instance_valid(s) and s.visible:
				n += 1
	return n


## The pictures made, by file name without .png (for the tests).
func files() -> Array:
	return _files.duplicate()
