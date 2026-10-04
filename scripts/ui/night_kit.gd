## The words of the nights (round 19, V3.1): what the clock column, the place's HUD and the Town Board say of the coming night. Pure
## functions, nothing here keeps state or changes the rules: each takes what the sim answers (`tactics.forecast()`, `radio.night.road_status()`,
## `scavenge.night_warning(...)`) and returns the line, its tone and its hour, so that a view only has to put it on a label.
##
##   forecast_line(f, last)      "The Siege: about 70 to 95 from the east side, 2 plated brutes after 23:00, first about 21:00"
##   ready_line(f)               {"text": "Should hold: posts 5 of 5, walls 90%", "holds": true} (the community's own prediction)
##   badge(sim, f)               {"state": "tomorrow" | "tonight" | "", "text", "tip"}: the bell by the day counter
##   road_line(rs, now_min)      {"text": "Dusk in 2:10 · road home 1:20 · leave by 15:40", "tone": "calm" | "warn" | "danger"} ("You will be out tonight"
##                               for a trip nobody drives that cannot be home; "Home about 19:10, after the dusk" for one the avatar drives)
##   warning_line(sim, ...)      the Town Board's note for the trip (scavenge.night_warning's own text)
##
## The keys of a forecast are those of tactics.forecast() (docs/superpowers/plans/2026-10-03-round-19.md, S3.1): the old ones and, in avatar
## mode, "kind" ("ordinary" | "milestone" | "final"), "name", "side", "sections", "section_text", "plated", "first_at", "brute_at", "needs_you"
## and "ready" ({"walls", "guns", "manned", "posts", "holds"}). A forecast without "kind" has no outlook: the old words are used.
extends RefCounted

const NightData := preload("res://scripts/sim/night_data.gd")


## "21:00": an hour of the day (a float, 24.5 is half past midnight) to the minute.
static func hour_text(h: float) -> String:
	var m := roundi(h * 60.0) % 1440
	if m < 0:
		m += 1440
	return "%02d:%02d" % [m / 60, m % 60]


## The hour of the day (0 to 24) of a game clock in minutes (day 1, 07:00 is 0).
static func hour_of_clock(clock_min: float) -> float:
	return fposmod(clock_min + 420.0, 1440.0) / 60.0


## "2:10": game minutes as hours and minutes.
static func minutes_text(minutes: float) -> String:
	var m := maxi(0, roundi(minutes))
	return "%d:%02d" % [m / 60, m % 60]


## "1 h 20", "2 h", "45 min": game minutes in words.
static func words_text(minutes: float) -> String:
	var m := maxi(0, roundi(minutes))
	if m < 60:
		return "%d min" % m
	if m % 60 == 0:
		return "%d h" % (m / 60)
	return "%d h %02d" % [m / 60, m % 60]


## Whether the forecast carries the outlook of avatar mode (its keys), and not only the old ones.
static func has_outlook(f: Dictionary) -> bool:
	return bool(f.get("given", false)) and String(f.get("kind", "")) != ""


## Whether tonight is one that needs the player: a Big Night (a milestone or the final), as the sim says.
static func needs_you(f: Dictionary) -> bool:
	if f.has("needs_you"):
		return bool(f.needs_you)
	var kind := String(f.get("kind", ""))
	return kind == "milestone" or kind == "final"


## Whether the night the HUD calls the last is the last one (a game that is not a campaign, or the last season).
static func last_night(sim) -> bool:
	var seasons = sim.get("seasons")
	return seasons == null or not seasons.campaign or seasons.is_last()


## The words of the forecast in avatar mode. `last`: the final night is "The last night" (else "The Big Night": a season that has others
## to come), when the sim gave it no name.
static func forecast_line(f: Dictionary, last: bool = true) -> String:
	var kind := String(f.get("kind", "ordinary"))
	var name := String(f.get("name", ""))
	if name == "":
		name = ("The last night" if last else "The Big Night") if kind == "final" else ("The Big Night" if kind == "milestone" else "Tonight")
	var total := int(f.get("total", 0))
	var low := int(f.get("low", 0))
	var high := int(f.get("high", 0))
	var size := ""
	if low > 0 and high > low:
		size = "about %d to %d" % [low, high]
	else:
		size = "about %d" % (total if total > 0 else maxi(low, high))
	var text := "%s: %s" % [name, size]
	if kind == "final":
		text += " from everywhere"
	else:
		var side := String(f.get("side", f.get("heading", "")))
		if side != "":
			# (a Big Night names the side as the lookout does: "the east side", two ways "the north and west"; an ordinary night as ever)
			text += " from the %s" % (side + " side" if needs_you(f) and not side.contains(" and ") else side)
	var plated := int(f.get("plated", 0))
	var brutes := int(f.get("brutes", 0))
	var brute_at := float(f.get("brute_at", -1.0))
	var after := " after %s" % hour_text(brute_at) if brute_at >= 0.0 else ""
	if plated > 0:
		text += ", %s%s" % ["a plated brute" if plated == 1 else "%d plated brutes" % plated, after]
	elif brutes > 0:
		text += ", %s%s" % ["a brute" if brutes == 1 else "%d brutes" % brutes, after]
	elif bool(f.get("runners", false)):
		text += ", runners"
	var first_at := float(f.get("first_at", -1.0))
	if first_at >= 0.0:
		text += ", first about %s" % hour_text(first_at)
	return text


## The same, for a narrow window (the clock there is 164 px across and the whole line wrapped to six lines): the name, the size, the side and
## the plated brutes, no hours (the tags in the yard give those): "The Siege: 34 to 46, north, 2 plated brutes".
static func forecast_line_compact(f: Dictionary, last: bool = true) -> String:
	var kind := String(f.get("kind", "ordinary"))
	var name := String(f.get("name", ""))
	if name == "":
		name = ("The last night" if last else "The Big Night") if kind == "final" else ("The Big Night" if kind == "milestone" else "Tonight")
	var total := int(f.get("total", 0))
	var low := int(f.get("low", 0))
	var high := int(f.get("high", 0))
	var text := "%s: " % name
	if low > 0 and high > low:
		text += "%d to %d" % [low, high]
	else:
		text += "about %d" % (total if total > 0 else maxi(low, high))
	if kind == "final":
		text += ", everywhere"
	else:
		var side := String(f.get("side", f.get("heading", "")))
		if side != "":
			text += ", %s" % side
	var plated := int(f.get("plated", 0))
	var brutes := int(f.get("brutes", 0))
	if plated > 0:
		text += ", a plated brute" if plated == 1 else ", %d plated brutes" % plated
	elif brutes > 0:
		text += ", a brute" if brutes == 1 else ", %d brutes" % brutes
	elif bool(f.get("runners", false)):
		text += ", runners"
	return text


## The tag of the walls the dead will come to ("brunt, about 21:00"), or "" for a forecast without the outlook.
static func brunt_tag(f: Dictionary) -> String:
	if not has_outlook(f):
		return ""
	var first_at := float(f.get("first_at", -1.0))
	return "brunt, about %s" % hour_text(first_at) if first_at >= 0.0 else "brunt"


## The tag at a spawn arrow of the fields view ("first about 21:00"), or "" for a forecast without the outlook or the hour.
static func arrow_tag(f: Dictionary) -> String:
	if not has_outlook(f):
		return ""
	var first_at := float(f.get("first_at", -1.0))
	return "first about %s" % hour_text(first_at) if first_at >= 0.0 else ""


## The community's own prediction under the forecast: {"text", "holds"}, or {} when the forecast carries none. Posts: people at their night
## posts of those who should be; walls: the lowest hp share of the target sections; guns: named only when too few cover the thinnest of them.
static func ready_line(f: Dictionary) -> Dictionary:
	var r = f.get("ready", {})
	if not (r is Dictionary) or (r as Dictionary).is_empty():
		return {}
	var posts := maxi(0, int(r.get("posts", 0)))
	var manned := clampi(int(r.get("manned", 0)), 0, posts)
	var walls := roundi(clampf(float(r.get("walls", 0.0)), 0.0, 1.0) * 100.0)
	var text := "Posts %d of %d, walls %d%%" % [manned, posts, walls]
	var guns := int(r.get("guns", 0))
	if guns < int(NightData.num("forecast.decent_guns", 2.0)):
		text += ", guns %d" % guns
	var holds := bool(r.get("holds", false))
	if needs_you(f):
		text += ". This one needs you."
	elif holds:
		text = "Should hold: p" + text.substr(1)
	return {"text": text, "holds": holds}


## The ready line for a narrow clock: "Needs you: posts 1/4, walls 100%" (the guns are named only when too few, as in the whole line).
static func ready_line_compact(f: Dictionary) -> Dictionary:
	var r = f.get("ready", {})
	if not (r is Dictionary) or (r as Dictionary).is_empty():
		return {}
	var posts := maxi(0, int(r.get("posts", 0)))
	var manned := clampi(int(r.get("manned", 0)), 0, posts)
	var walls := roundi(clampf(float(r.get("walls", 0.0)), 0.0, 1.0) * 100.0)
	var text := "posts %d/%d, walls %d%%" % [manned, posts, walls]
	if int(r.get("guns", 0)) < int(NightData.num("forecast.decent_guns", 2.0)):
		text += ", guns %d" % int(r.get("guns", 0))
	var holds := bool(r.get("holds", false))
	if needs_you(f):
		text = "Needs you: " + text
	elif holds:
		text = "Should hold: " + text
	else:
		text = text.substr(0, 1).to_upper() + text.substr(1)
	return {"text": text, "holds": holds}


## What the ready line's numbers are, for its tooltip.
const READY_TIP := "The community's own reading of tonight.\nPosts: people at their night posts, of those who should be.\nWalls: the weakest of the walls the dead will come to.\nGuns: the fewest guns that reach one of them."


## The day-ahead notice of the radio desk for tonight's day (the news entry of kind "forecast" made today), or {}.
static func notice(sim, day: int = -999) -> Dictionary:
	var radio = sim.get("radio")
	if radio == null:
		return {}
	var want: int = int(sim.day) if day == -999 else day
	var news: Array = radio.news
	for i in range(news.size() - 1, -1, -1):
		var e: Dictionary = news[i]
		if String(e.get("kind", "")) == "forecast" and int(e.get("day", -1)) == want:
			return e
	return {}


static func _notice_tip(e: Dictionary) -> String:
	var sub := String(e.get("sub", ""))
	return String(e.get("text", "")) + ("\n" + sub if sub != "" else "")


## The badge by the day counter, in avatar mode: "tomorrow" once the radio desk has given the notice of a Big Night (until the day turns),
## "tonight" while tonight is a Big Night the player has been told of (by the notice of the day before, or by the lookout's forecast), until
## dawn. {} when there is none. `f` is `tactics.forecast()`.
static func badge(sim, f: Dictionary) -> Dictionary:
	if String(sim.player_id) == "":
		return {}
	var phase := String(sim.phase)
	if phase != "dawn":
		if has_outlook(f) and needs_you(f):
			return {"state": "tonight", "text": "Big Night", "tip": forecast_line(f, last_night(sim))}
		var waves = sim.get("waves")
		if waves != null and waves.has_method("big_night"):
			var yesterday := notice(sim, int(sim.day) - 1)
			if not yesterday.is_empty() and not (waves.big_night(int(sim.day)) as Dictionary).is_empty():
				return {"state": "tonight", "text": "Big Night", "tip": _notice_tip(yesterday)}
	var ahead := notice(sim)
	if not ahead.is_empty():
		return {"state": "tomorrow", "text": "Big Night tomorrow", "tip": _notice_tip(ahead)}
	return {}


## The line of the place's HUD while the trip is out, from `radio.night.road_status()`: {"text", "tone"} ("calm", "warn", "danger"), or {}
## when no trip is in the place or on the road. `now_min` is the colony's clock (`sim.clock_min`).
static func road_line(rs: Dictionary, now_min: float) -> Dictionary:
	if rs.is_empty() or not bool(rs.get("on", false)):
		return {}
	var state := String(rs.get("state", "free"))
	if state == "late":
		if bool(rs.get("live", false)):
			# (the avatar drives this trip: it comes in by night too, so it is not out until morning but home after the dusk)
			var back := hour_text(hour_of_clock(float(rs.get("arrival", now_min))))
			if not bool(rs.get("in_place", true)):
				return {"text": "On the road home in the dark: back about %s" % back, "tone": "warn"}
			return {"text": "Home about %s, after the dusk" % back, "tone": "warn"}
		return {"text": "You will be out tonight", "tone": "warn"}
	if not bool(rs.get("in_place", true)) and String(rs.get("text", "")) != "":
		# (on the road home, the live drive's last leg: nothing is left to decide, so no hour to leave by; only when they are back)
		return {"text": String(rs.text), "tone": "calm"}
	var dusk_in := float(rs.get("dusk", now_min)) - now_min
	var text := "Dusk in %s · road home %s · " % [minutes_text(dusk_in), minutes_text(float(rs.get("road_min", 0.0)))]
	if state == "now":
		return {"text": text + "leave now", "tone": "danger" if bool(rs.get("big", true)) else "warn"}
	text += "leave by %s" % hour_text(hour_of_clock(float(rs.get("leave_by", now_min))))
	return {"text": text, "tone": "warn" if state == "soon" else "calm"}


## The hint under the place's name once the head home was asked for ("home" of the night_road call).
static func leave_hint(rs: Dictionary) -> String:
	return "Head for the exit: the road home takes %s" % words_text(float(rs.get("road_min", 0.0)))


## The hint on the road there (the live drive) once the head home was asked for: the car cannot be turned round, so the place is first and
## the squad goes straight back from its gate.
static func leave_hint_there(rs: Dictionary) -> String:
	return "Asked to head home: the place first, then straight back. The road home takes %s" % words_text(float(rs.get("road_min", 0.0)))


## The Town Board's note on the trip being planned (`scavenge.night_warning`: where it has one): {"text", "tone", "big"}, or {} for none.
static func warning_line(sim, place_id: String, vehicle_id: String = "", site_hours: float = 1.0) -> Dictionary:
	if String(sim.player_id) == "":
		return {}
	var scav = sim.get("scavenge")
	if scav == null or not scav.has_method("night_warning"):
		return {}
	var w = scav.night_warning(place_id, vehicle_id, site_hours)
	if not (w is Dictionary):
		return {}
	var text := String(w.get("text", ""))
	if text == "":
		return {}
	var big := bool(w.get("big", false))
	return {"text": text, "tone": "warn" if big and not bool(w.get("makes_it", true)) else "calm", "big": big}
