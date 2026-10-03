extends VBoxContainer
## The Build page of the radio panel (round 18). A stub the panel can mount until its builder replaces it: see
## docs/superpowers/plans/2026-10-03-round-18.md for what the page becomes. Every page has the same four functions.

var host
var sim_getter: Callable


func setup(p_host, p_sim_getter: Callable, _options: Dictionary = {}) -> void:
	host = p_host
	sim_getter = p_sim_getter
	if get_child_count() == 0:
		var label := Label.new()
		label.text = "Build"
		add_child(label)


func refresh() -> void:
	pass


func focus_on(_id: String) -> void:
	pass


## The full modal page of the same name (the old screen).
func full_page() -> void:
	if host != null and host.has_method("open_build"):
		host.open_build()
