class_name SlingshotSpringEnergyExplanation
extends RefCounted

const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")
const VisualLanguage = preload("res://src/video/visual_language.gd")


func hides_physical_stage() -> bool:
	return true


func draw(canvas) -> void:
	var theme_colors: Dictionary = canvas.episode["theme"]["colors"]
	var plot := EpisodeLayout.plot_rect_for_phase("EXPLAIN")
	var baseline := plot.position + Vector2(92, 560)
	var variants: Array = canvas.episode["variants"]
	var step := clampi(int(canvas.current_beat.get("formula_step", 0)), 0, 2)
	var max_energy := 0.0
	var energies: Array[float] = []
	for variant_value in variants:
		var variant: Dictionary = variant_value
		var physics: Dictionary = variant["preset"]["physics"]
		var energy := 0.5 * float(physics["spring_k_npm"]) * pow(float(physics["stretch_m"]), 2.0)
		energies.append(energy)
		max_energy = maxf(max_energy, energy)
	canvas.draw_line(
		baseline,
		baseline + Vector2(550, 0),
		Color(theme_colors["divider"], 0.72),
		VisualLanguage.STROKE_MEASURE,
		true
	)
	var winner_id := String(canvas.analysis.get("winner_id", ""))
	for index in range(variants.size()):
		var x := baseline.x + 45.0 + index * 135.0
		var bar_height := 250.0 * energies[index] / maxf(max_energy, 0.001)
		var reveal := _bar_reveal(canvas, index, variants.size())
		var active := String(variants[index]["id"]) == winner_id
		var color: Color = theme_colors["accent"] if active else theme_colors["muted"]
		var bar_rect := Rect2(x, baseline.y - bar_height * reveal, 68, bar_height * reveal)
		canvas.draw_rect(bar_rect, Color(color, 0.20 if active else 0.055), true)
		canvas.draw_rect(
			bar_rect,
			Color(color, 0.82 if active else 0.30),
			false,
			VisualLanguage.STROKE_SECONDARY if active else VisualLanguage.STROKE_CONTEXT,
			true
		)
		canvas.draw_line(
			Vector2(x, baseline.y + 12),
			Vector2(x + 68, baseline.y + 12),
			Color(color, 0.86 if active else 0.34),
			VisualLanguage.STROKE_SECONDARY if active else VisualLanguage.STROKE_CONTEXT,
			true
		)
		canvas._draw_module_label(
			Vector2(x - 10, baseline.y + 34),
			String(variants[index]["label"]),
			Color(theme_colors["text"], 0.90) if active else Color(theme_colors["muted"], 0.64)
		)
		if step >= 2:
			var value_alpha := smoothstep(0.0, 0.55, _transition_progress(canvas))
			canvas._draw_module_label(
				Vector2(x - 4, baseline.y - bar_height - 38),
				"%.1f J" % energies[index],
				Color(theme_colors["text"], value_alpha)
			)
	canvas.draw_string(
		VideoTypography.medium(),
		baseline + Vector2(0, -286),
		"储能  E",
		HORIZONTAL_ALIGNMENT_LEFT,
		180,
		26,
		Color(theme_colors["muted"], 0.72)
	)
	var spring_start := plot.position + Vector2(90, 130)
	var rest_finish := spring_start + Vector2(160.0, 0)
	var extension_factor := _extension_factor(canvas)
	var spring_finish := rest_finish + Vector2(110.0 * extension_factor, 0)
	var coils := PackedVector2Array([spring_start])
	for coil in range(17):
		var ratio := float(coil + 1) / 18.0
		coils.append(
			spring_start.lerp(spring_finish, ratio)
			+ Vector2(0, -18 if coil % 2 == 0 else 18)
		)
	coils.append(spring_finish)
	canvas.draw_polyline(coils, Color(theme_colors["accent"], 0.88), VisualLanguage.STROKE_PRIMARY, true)
	canvas.draw_line(
		spring_start + Vector2(0, -48),
		spring_start + Vector2(0, 48),
		Color(theme_colors["muted"], 0.62),
		VisualLanguage.STROKE_SECONDARY,
		true
	)
	var dimension_y := spring_start.y - 64.0
	var dimension_color := Color(theme_colors["accent"], 0.74)
	canvas.draw_line(
		Vector2(rest_finish.x, dimension_y),
		Vector2(spring_finish.x, dimension_y),
		dimension_color,
		VisualLanguage.STROKE_MEASURE,
		true
	)
	canvas.draw_line(
		Vector2(rest_finish.x, dimension_y - 8.0),
		Vector2(rest_finish.x, dimension_y + 8.0),
		dimension_color,
		VisualLanguage.STROKE_MEASURE,
		true
	)
	canvas.draw_line(
		Vector2(spring_finish.x, dimension_y - 8.0),
		Vector2(spring_finish.x, dimension_y + 8.0),
		dimension_color,
		VisualLanguage.STROKE_MEASURE,
		true
	)
	canvas.draw_string(
		VideoTypography.data(),
		Vector2(rest_finish.x, dimension_y - 15.0),
		_dimension_label(extension_factor),
		HORIZONTAL_ALIGNMENT_CENTER,
		spring_finish.x - rest_finish.x,
		26,
		theme_colors["accent"]
	)
	canvas.draw_line(
		rest_finish + Vector2(0, -30),
		rest_finish + Vector2(0, 30),
		Color(theme_colors["muted"], 0.28),
		VisualLanguage.STROKE_CONTEXT,
		true
	)


func _bar_reveal(canvas, index: int, variant_count: int) -> float:
	var explain_elapsed := EpisodeLayout.phase_elapsed(
		canvas.episode,
		"EXPLAIN",
		canvas.video_time_sec
	)
	var sequence_progress := clampf(explain_elapsed / 4.0, 0.0, 1.0)
	return clampf(
		sequence_progress * float(variant_count + 1) - float(index),
		0.0,
		1.0
	)


func _transition_progress(canvas) -> float:
	if canvas.current_beat.is_empty():
		return 1.0
	return smoothstep(
		0.0,
		1.0,
		clampf(
			(canvas.video_time_sec - float(canvas.current_beat.get("at", canvas.video_time_sec))) / 0.8,
			0.0,
			1.0
		)
	)


func _extension_factor(canvas) -> float:
	var step := clampi(int(canvas.current_beat.get("formula_step", 0)), 0, 2)
	if step <= 0:
		return 1.0
	return lerpf(1.0, 2.0, _transition_progress(canvas))


func _dimension_label(extension_factor: float) -> String:
	if extension_factor <= 1.05:
		return "x"
	if extension_factor >= 1.95:
		return "2x"
	return "x → 2x"
