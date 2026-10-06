## The player's accessibility settings, read in one place (saved in `Prefs`, section `ui`; the Settings screen's "Accessibility" rows, scripts/ui/settings_extras.gd, change them):
##
##   text_size       "normal", "large" or "larger": the text of the HUD's panels, cards and the menus is drawn about 1.0, 1.15 or 1.3 times as big, on top of the interface size
##                   (scripts/ui/text_scale.gd does it; `text_k()` is the factor, for the few things that draw their own words)
##   colour_blind    "Colour-blind markers": every colour-coded mark also has a shape, a glyph or a pattern (the crew's status chips, the minimap, the pennants over houses that
##                   may be claimed, the Build page's states, the health bars, the red and green cues): `markers()`
##   reduce_flashes  "Reduce flashes": the red edge of a hit, the night's vignette, the white flash of a hit and the muzzle's light are very gentle or still: `calm_flashes()`
##
## Reduce motion (the older setting) already stills the camera and the fades; a view that flashes asks `calm_flashes()`, which is true under either.
extends RefCounted

const Prefs := preload("res://scripts/prefs.gd")

const TEXT_SIZES := ["normal", "large", "larger"]
const TEXT_LABELS := {"normal": "Normal", "large": "Large", "larger": "Larger"}
const TEXT_K := {"normal": 1.0, "large": 1.15, "larger": 1.3}


## The text size setting: one of TEXT_SIZES ("normal" for anything else the file holds).
static func text_size() -> String:
	var v = Prefs.get_value("ui", "text_size")
	if typeof(v) == TYPE_STRING and TEXT_SIZES.has(String(v)):
		return String(v)
	return "normal"


## How much bigger the text is drawn: 1, 1.15 or 1.3.
static func text_k() -> float:
	return float(TEXT_K[text_size()])


## A font size as the text size setting draws it (never under the original).
static func scaled(px: int) -> int:
	return maxi(px, roundi(float(px) * text_k()))


## "Colour-blind markers" is on.
static func markers() -> bool:
	return Prefs.on("ui", "colour_blind")


## "Reduce flashes" is on.
static func reduce_flashes() -> bool:
	return Prefs.on("ui", "reduce_flashes")


## A flash, a pulse or a blink is to be gentle or still: "Reduce flashes", or the older "Reduce motion".
static func calm_flashes() -> bool:
	return Prefs.on("ui", "reduce_flashes") or Prefs.on("ui", "reduce_motion")
