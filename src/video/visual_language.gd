class_name SlingshotVisualLanguage
extends RefCounted

const STROKE_PRIMARY := 4.0
const STROKE_SECONDARY := 2.25
const STROKE_MEASURE := 1.5
const STROKE_CONTEXT := 1.0

const ALPHA_PRIMARY := 0.88
const ALPHA_SECONDARY := 0.48
const ALPHA_MEASURE := 0.34
const ALPHA_CONTEXT := 0.11


static func width(role: String, scale_value: float = 1.0) -> float:
	var base: float = float({
			"primary": STROKE_PRIMARY,
			"secondary": STROKE_SECONDARY,
			"measure": STROKE_MEASURE,
			"context": STROKE_CONTEXT,
		}.get(role, STROKE_SECONDARY))
	return maxf(STROKE_CONTEXT, base * scale_value)


static func alpha(role: String) -> float:
	return float({
		"primary": ALPHA_PRIMARY,
		"secondary": ALPHA_SECONDARY,
		"measure": ALPHA_MEASURE,
		"context": ALPHA_CONTEXT,
	}.get(role, ALPHA_SECONDARY))


static func role_color(color: Color, role: String) -> Color:
	return Color(color, alpha(role))
