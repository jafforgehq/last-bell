## A contact sheet of the work poses (round 16): every job, at several moments of its loop, drawn by the real PawnNode (the
## real bodies, tools and effects) on a plain ground, to be looked at. Windowed (headless cannot render), from the repo root:
##
##   Godot --path . --script res://tools/work_sheet.gd -- --out=/tmp/sheet.png [--facing=S] [--words=hammer,bench] [--cols=8] [--zoom=60]
##       [--who=dez] [--cell=130]
##
## --facing=S|E|N|W (all four, one after another, with --facing=all, as columns of the sheet), --words=<list> (default: all ten),
## --cols=N the moments of the loop shown (default 8, evenly spread), --zoom=pixels to the tile (default 60), --who=<person id>,
## --cell=pixels of one picture (default 2.2 tiles), --reduced a still pose (reduced motion).
extends SceneTree

const GD := preload("res://scripts/game_data.gd")
const Sim := preload("res://scripts/sim/sim.gd")
const PawnNode := preload("res://scripts/render/pawn_node.gd")
const WorkAnim := preload("res://scripts/render/work_anim.gd")


func _arg(name: String, default: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
		if a == "--%s" % name:
			return "1"
	return default


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := _arg("out", "/tmp/work_sheet.png")
	var zoom := float(_arg("zoom", "60"))
	var cols := int(_arg("cols", "8"))
	var who := _arg("who", "dez")
	var words: Array = Array(_arg("words", ",".join(WorkAnim.WORDS)).split(","))
	var facings: Array = ["S", "E", "N", "W"] if _arg("facing", "S") == "all" else [_arg("facing", "S")]
	var cell := float(_arg("cell", str(zoom * 2.2)))
	var label_w := 90.0
	var data := GD.load_all()
	var def: Dictionary = {}
	for d in data.people:
		if d.id == who:
			def = d
	var per_row := cols * facings.size()
	var size := Vector2i(int(label_w + per_row * cell), int(words.size() * cell + 24.0))
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color("#6f6b64")
	bg.size = Vector2(size)
	vp.add_child(bg)
	var world := Node2D.new()
	world.scale = Vector2.ONE * (zoom / 64.0)
	vp.add_child(world)
	var nodes := []
	for r in words.size():
		var word: String = words[r]
		var lab := Label.new()
		lab.text = word
		lab.position = Vector2(6.0, 24.0 + r * cell + cell * 0.4)
		lab.add_theme_font_size_override("font_size", 16)
		vp.add_child(lab)
		var loop := WorkAnim.loop_period(word)
		for f in facings.size():
			for c in cols:
				var p = Sim.Person.new()
				p.def = def
				p.id = who
				p.name = def.name
				p.look = def.look
				p.weapon = def.weapon
				p.facing = facings[f]
				p.x = 10.0
				p.y = 10.0
				p.aim = 0.4
				var n := PawnNode.new()
				n.setup(p, false, data, who)
				n.work_stage = word
				n.work_stage_t = loop * float(c) / float(cols)
				n._work_phase = 0.0
				n._wk = 1.0
				n._w_word = word
				n.position = Vector2((label_w + (f * cols + c) * cell + cell * 0.5) / (zoom / 64.0), (24.0 + r * cell + cell * 0.62) / (zoom / 64.0))
				world.add_child(n)
				nodes.append(n)
	for i in 6:
		for n in nodes:
			n.anim_t = float(i)
			n.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out)
	print("saved ", out, " ", size)
	quit()
