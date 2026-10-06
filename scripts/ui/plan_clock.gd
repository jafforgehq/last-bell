## The clock of the Build page's plan (One House, navigation): when the builders would be done, and whether that is before the bell. Static functions only; it READS the page's own numbers
## (`sim.perimeter.projects()`: each project's "work" in builder-hours, its "minutes", its "scrap" still to pay, its "state") and the clock, and writes nothing.
##
## THE FORMULA. The page already says how long a project takes: its builder-hours of work over the builders' rate, times the walking between sections (perimeter.gd `_project_info`):
##     minutes = work / (builders x rate) x 60 x 1.15
## The whole plan is the sum of the minutes of every project that is going up or can be ordered (not the finished ones, not the locked ones: they cannot be started), in the order the
## builders will do them: the ones already ordered first, then the rest in the page's order (front fence, gate, tower, side fences, back fence, lights, planks, second tower, reinforcing),
## which is also the order of "Build everything I can afford". The builders work BY DAY only (`jobs.working`: they go to their posts at the bell and come back at dawn), so the minutes
## are laid out on the working hours from now: what is left of the day up to the dusk hour, then from the dawn hour to the dusk hour of each day after. The result is a clock time, with
## "tomorrow" or "in 2 days" when the work spills over a night.
##
## THE VERDICT is against the next bell at which the dead come (the first attack night, or the next dusk once they come every night):
##   READY BY DUSK  the whole plan, or at least the house proper (front fence, gate, tower, side fences, back fence), is up before the bell, and the scrap is there to order it
##   TIGHT          only the front fence and the gate make it
##   NOT YET        not even those
##   QUIET NIGHTS   the dead do not come yet: no rush
## and a line says why ("Add a builder: about 3 hours short."). A card's "finishes" is for the project ordered now behind what is already going up.
extends RefCounted

const Perimeter := preload("res://scripts/town/perimeter.gd")

## The projects that make the house (the fences, the gate, the tower), and the two that matter most: the front.
const RING := ["front", "gate", "tower", "sides", "back"]
const CORE := ["front", "gate"]
## The most builders the words will ask to add: more than that and the plan is too big for the day, whoever builds it.
const MOST_ADDED := 4
## Times are told to this many minutes, rounded up (a promise is never kept by being early).
const ROUND_MIN := 5


# ------------------------------------------------------------------------------ the clock --

## "15:40" for an hour of the day (a fraction; any number of days is folded into one), rounded up to ROUND_MIN minutes.
static func clock_text(h: float) -> String:
	var m := int(ceilf(fposmod(h, 24.0) * 60.0 / float(ROUND_MIN))) * ROUND_MIN
	m = m % 1440
	return "%02d:%02d" % [floori(float(m) / 60.0), m % 60]


## The hour `h` (hours from the midnight that began the day of "now": 0 to 24 is today) as the words for it: "15:40", "tomorrow 11:20", "day 9, 11:20" (`day` is today's number; without it,
## "in 3 days, 11:20").
static func when_text(h: float, day: int = -1) -> String:
	var days := int(floorf(maxf(h, 0.0) / 24.0))
	var c := clock_text(h)
	if days <= 0:
		return c
	if days == 1:
		return "tomorrow %s" % c
	if day >= 0:
		return "day %d, %s" % [day + days, c]
	return "in %d days, %s" % [days, c]


## "by 15:40", "by tomorrow 11:20", "on day 9, 11:20": a time to be done by.
static func done_text(h: float, day: int = -1) -> String:
	var words := when_text(h, day)
	return ("by " if h < 48.0 else "on ") + words


## When `minutes` of work, begun now (`now`: the hour of the day), is done, if the builders work only from `dawn` to `dusk` each day: hours from today's midnight (24 and over is tomorrow).
static func finish_at(now: float, minutes: float, dusk: float, dawn: float) -> float:
	var need := maxf(minutes, 0.0) / 60.0
	var t := now
	if t < dawn:
		t = dawn
	elif t >= dusk:
		t = 24.0 + dawn
	for _i in 120:
		var end := floorf(t / 24.0) * 24.0 + dusk
		var avail := end - t
		if need <= avail:
			return t + need
		need -= avail
		t = floorf(t / 24.0) * 24.0 + 24.0 + dawn
	return t


## The hours of work there are from hour `from` to hour `to` (hours from today's midnight) with the builders out only from `dawn` to `dusk` of each day.
static func work_hours(from: float, to: float, dusk: float, dawn: float) -> float:
	if to <= from:
		return 0.0
	var total := 0.0
	for d in range(int(floorf(from / 24.0)), int(floorf(to / 24.0)) + 1):
		var a := maxf(from, float(d) * 24.0 + dawn)
		var b := minf(to, float(d) * 24.0 + dusk)
		if b > a:
			total += b - a
	return total


## What the page needs of the game: {"now", "dusk", "dawn", "day", "scrap", "bell": hours (from today's midnight) of the next bell at which the dead come (-1: they do not come yet), "bell_word"}.
static func context(sim) -> Dictionary:
	var out := {"now": 8.0, "dusk": 19.0, "dawn": 6.5, "day": 1, "scrap": 0.0, "bell": -1.0, "bell_word": "the bell"}
	if sim == null:
		return out
	out.now = float(sim.hour)
	out.day = int(sim.day)
	var seasons = sim.get("seasons")
	if seasons != null:
		out.dusk = float(seasons.dusk_hour())
		out.dawn = float(seasons.dawn_hour())
	if sim.get("stock") != null:
		out.scrap = float(sim.stock.scrap)
	var now: float = out.now
	var dusk: float = out.dusk
	# (the next dusk: tonight's while the day lasts, else tomorrow's: after midnight it is the evening of the day that comes)
	var day_now: bool = now >= float(out.dawn) and now < dusk
	var next_dusk := dusk if now < dusk else 24.0 + dusk
	var next_day: int = int(out.day) if day_now else int(out.day) + 1
	var sc = sim.get("scenario")
	var pending := false
	var first_day := -1
	if sc != null:
		if sc.get("_attacks") != null:
			pending = bool(sc.get("_attacks"))
			first_day = int(sc.get("_first_day")) if sc.get("_first_day") != null else -1
		elif sc.has_method("attacks_on"):
			pending = bool(sc.attacks_on())
	if not pending:
		return out
	var bell_day := maxi(next_day, first_day)
	out.bell = next_dusk + 24.0 * float(bell_day - next_day)
	var ahead := int(floorf(float(out.bell) / 24.0))
	out.bell_word = "the bell" if ahead <= 0 else ("tomorrow's bell" if ahead == 1 else "the bell in %d days" % ahead)
	return out


# ---------------------------------------------------------------------------------- the plan --

## The whole plan, from the projects as `perimeter.projects()` gives them and the context above. Returns
##   "line"      "Whole plan: 54 scrap, about 31 builder-hours. Done by 15:40 with three builders."   ("summary" is the same without "Whole plan: ": the page's own caption says it)
##   "verdict"   "ready" | "tight" | "not_yet" | "quiet" | "built" | "none"     ("none": nothing to say: nothing can be ordered yet)
##   "chip"      the chip's words ("READY BY DUSK") and "tone" ("ok", "warn", "bad", "calm")
##   "reason"    the line under the chip
##   "per"       project id -> "finishes 12:10" (the project ordered now, behind what is already going up), for the projects that can be built
##   "scrap", "hours", "minutes", "builders", "finish" (the clock words for the whole plan), "done_at" (hours from midnight)
static func assess(infos: Array, ctx: Dictionary) -> Dictionary:
	var out := {"line": "", "summary": "", "verdict": "none", "chip": "", "tone": "calm", "reason": "", "per": {}, "scrap": 0, "hours": 0.0, "minutes": 0.0, "builders": 0, "finish": "", "done_at": 0.0}
	var now := float(ctx.now)
	var dusk := float(ctx.dusk)
	var dawn := float(ctx.dawn)
	var queue: Array = []
	var any_locked := false
	var locked_ids: Array = []
	for pass_n in 2:
		for p in infos:
			var st := String(p.get("state", ""))
			if (pass_n == 0 and st == "building") or (pass_n == 1 and st == "ready"):
				queue.append(p)
	for p in infos:
		if String(p.get("state", "")) == "locked":
			any_locked = true
			locked_ids.append(String(p.id))
	if queue.is_empty():
		if any_locked:
			return out
		out.summary = "All built."
		out.line = "Whole plan: " + String(out.summary)
		out.verdict = "built"
		out.chip = "READY BY DUSK"
		out.tone = "ok"
		out.reason = "Everything on the plan stands. Mend what the dead break."
		return out
	var scrap_sum := 0.0
	var hours_sum := 0.0
	var builders := 0
	for p in queue:
		scrap_sum += float(p.scrap)
		hours_sum += float(p.work)
		builders = maxi(builders, int(p.get("builders", 0)))
	out.scrap = roundi(scrap_sum)
	out.hours = hours_sum
	out.builders = builders
	var head := ("%d scrap" % int(out.scrap)) if int(out.scrap) > 0 else "paid for"
	head += ", about %d builder-hours" % maxi(1, roundi(hours_sum))
	if builders <= 0:
		out.summary = head + ". Nobody is on the Builders job."
		out.line = "Whole plan: " + String(out.summary)
		if float(ctx.bell) < 0.0:
			out.verdict = "quiet"
			out.chip = "QUIET NIGHTS: NO RUSH"
			out.tone = "calm"
			out.reason = "Nothing goes up until somebody is on the Builders job."
		else:
			out.verdict = "not_yet"
			out.chip = "NOT YET"
			out.tone = "bad"
			out.reason = "Put somebody on the Builders job: nobody builds the plan."
		return out
	# the queue laid out on the working hours
	var cum_m := {}
	var cum_s := {}
	var fin := {}
	var m := 0.0
	var s := 0.0
	var building_m := 0.0
	for p in queue:
		m += float(p.minutes)
		s += float(p.scrap)
		var id := String(p.id)
		cum_m[id] = m
		cum_s[id] = s
		fin[id] = finish_at(now, m, dusk, dawn)
		if String(p.state) == "building":
			building_m = m
	out.minutes = m
	out.done_at = finish_at(now, m, dusk, dawn)
	var day := int(ctx.get("day", -1))
	out.finish = when_text(float(out.done_at), day)
	out.summary = "%s. Done %s with %s." % [head, done_text(float(out.done_at), day), String(queue[0].builders_text)]
	out.line = "Whole plan: " + String(out.summary)
	var per := {}
	for p in queue:
		var id2 := String(p.id)
		var at := float(fin[id2]) if String(p.state) == "building" else finish_at(now, building_m + float(p.minutes), dusk, dawn)
		per[id2] = "finishes %s" % when_text(at, day)
	out.per = per
	out.per = per
	var bell := float(ctx.bell)
	if bell < 0.0:
		out.verdict = "quiet"
		out.chip = "QUIET NIGHTS: NO RUSH"
		out.tone = "calm"
		out.reason = "The dead are not coming yet. Build when you like."
		return out
	var have := float(ctx.scrap)
	var bell_word := String(ctx.get("bell_word", "the bell"))
	var all_ids: Array = []
	for p in queue:
		all_ids.append(String(p.id))
	var whole := _set_of(all_ids, [], cum_m, cum_s, fin, have, bell)
	var ring := _set_of(RING, locked_ids, cum_m, cum_s, fin, have, bell)
	var core := _set_of(CORE, locked_ids, cum_m, cum_s, fin, have, bell)
	var avail := work_hours(now, bell, dusk, dawn)
	if bool(whole.ok):
		out.verdict = "ready"
		out.chip = "READY BY DUSK"
		out.tone = "ok"
		out.reason = "Everything is up before %s, with %s to spare." % [bell_word, _spare(avail - float(out.minutes) / 60.0)]
	elif bool(ring.ok):
		out.verdict = "ready"
		out.chip = "READY BY DUSK"
		out.tone = "ok"
		out.reason = "The fences, the gate and the tower are up before %s. The rest comes after." % bell_word
	elif bool(core.ok):
		out.verdict = "tight"
		out.chip = "TIGHT"
		out.tone = "warn"
		out.reason = "Only the front and the gate are up before %s. %s" % [bell_word, _fix(ring, builders, avail)]
	else:
		out.verdict = "not_yet"
		out.chip = "NOT YET"
		out.tone = "bad"
		out.reason = "The front and the gate are not up before %s. %s" % [bell_word, _fix(core, builders, avail)]
	return out


## How a set of projects stands: {"ok", "late" (one finishes after the bell), "poor" (the scrap in the stores does not pay for it), "blocked" (one is locked), "minutes", "scrap"
## (to the last of them in the queue)}. A set with none in the queue (all built) is fine.
static func _set_of(ids: Array, locked_ids: Array, cum_m: Dictionary, cum_s: Dictionary, fin: Dictionary, have: float, bell: float) -> Dictionary:
	var r := {"ok": true, "late": false, "poor": false, "blocked": false, "minutes": 0.0, "scrap": 0.0, "have": have}
	for id in ids:
		if locked_ids.has(id):
			r.blocked = true
		if not cum_m.has(id):
			continue
		r.minutes = maxf(float(r.minutes), float(cum_m[id]))
		r.scrap = maxf(float(r.scrap), float(cum_s[id]))
		if float(fin[id]) > bell + 0.001:
			r.late = true
		if float(cum_s[id]) > have + 0.5:
			r.poor = true
	r.ok = not (bool(r.late) or bool(r.poor) or bool(r.blocked))
	return r


## What to do about a set that does not fit: builders to add, scrap to find, people to wait for ("Add a builder: about 3 hours short. Needs 12 more scrap.").
static func _fix(set: Dictionary, builders: int, avail: float) -> String:
	var parts: Array = []
	if bool(set.blocked):
		parts.append("Some of it is not open yet: it needs more people here.")
	if bool(set.late):
		var need_h := float(set.minutes) / 60.0
		var short_h := need_h - avail
		if avail <= 0.05:
			parts.append("There is no daylight left to build it in.")
		else:
			var want := int(ceilf(float(builders) * need_h / avail - 0.0001))
			var add := want - builders
			if add > MOST_ADDED:
				parts.append("There is hardly any daylight left." if avail < 1.5 else "It is more than a day's work, whoever builds it.")
			elif add <= 1:
				parts.append("Add a builder: %s short." % Perimeter.time_text(short_h * 60.0))
			else:
				parts.append("Add %d builders: %s short." % [add, Perimeter.time_text(short_h * 60.0)])
	if bool(set.poor):
		parts.append("It needs %d more scrap." % maxi(1, ceili(float(set.scrap) - float(set.get("have", 0.0)))))
	return " ".join(parts)


## "about 3 hours", "a few minutes", for hours of slack.
static func _spare(h: float) -> String:
	return Perimeter.time_text(maxf(h, 0.0) * 60.0)
