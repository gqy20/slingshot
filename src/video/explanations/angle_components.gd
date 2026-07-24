class_name SlingshotAngleExplanation
extends RefCounted

const TrajectoryAnnotation = preload("res://src/video/trajectory_annotation.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")
const VisualLanguage = preload("res://src/video/visual_language.gd")


func hides_physical_stage() -> bool:
	return false


func draw(canvas) -> void:
	var theme_colors: Dictionary = canvas.episode["theme"]["colors"]
	var intro := smoothstep(0.0, 0.08, _beat_progress(canvas))
	var variants: Array = canvas.episode.get("variants", [])
	if variants.is_empty():
		return
	var weights := _variant_weights(canvas, variants.size())
	var active_index := 0
	var active_weight := -1.0
	for index in range(variants.size()):
		var variant: Dictionary = variants[index]
		var id := String(variant["id"])
		var record: Dictionary = canvas.records_by_id.get(id, {})
		var weight := float(weights[index])
		if record.is_empty() or weight <= 0.001:
			continue
		if weight > active_weight:
			active_weight = weight
			active_index = index
		var mapped_points: PackedVector2Array = canvas._map_points(
			canvas.trajectories_by_id.get(id, PackedVector2Array())
		)
		if mapped_points.size() >= 2:
			canvas.draw_polyline(
				mapped_points,
				Color(canvas.colors_by_id[id], (0.10 + 0.48 * weight) * intro),
				VisualLanguage.width("context") + 3.0 * weight,
				true
			)
		var geometry := TrajectoryAnnotation.initial_geometry(record)
		if geometry.is_empty():
			continue
		var origin: Vector2 = canvas._map_point(geometry["origin"])
		var tip := origin + Vector2(geometry["direction"]) * 300.0
		canvas._draw_arrow(
			origin,
			tip,
			Color(canvas.colors_by_id[id], (0.12 + 0.70 * weight) * intro),
			VisualLanguage.width("measure") + 2.5 * weight
		)

	var active_variant: Dictionary = variants[active_index]
	var active_id := String(active_variant["id"])
	var active_record: Dictionary = canvas.records_by_id.get(active_id, {})
	var active_geometry := TrajectoryAnnotation.initial_geometry(active_record)
	if active_geometry.is_empty():
		return
	var origin: Vector2 = canvas._map_point(active_geometry["origin"])
	var direction: Vector2 = active_geometry["direction"]
	var angle_deg := float(active_geometry["angle_deg"])
	var angle := deg_to_rad(angle_deg)
	var tip := origin + direction * 300.0
	var horizontal_tip := Vector2(tip.x, origin.y)
	var horizontal_color: Color = variants[0]["color"]
	var vertical_color: Color = variants[-1]["color"]
	canvas.draw_arc(
		origin,
		82.0,
		-angle,
		0.0,
		36,
		Color(theme_colors["accent"], 0.72 * intro),
		VisualLanguage.STROKE_SECONDARY,
		true
	)
	canvas.draw_string(
		VideoTypography.data(),
		origin + Vector2(62, -18),
		"%.0f°" % angle_deg,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		24,
		Color(theme_colors["accent"], intro)
	)
	canvas._draw_arrow(
		origin,
		horizontal_tip,
		Color(horizontal_color, 0.82 * intro),
		VisualLanguage.STROKE_SECONDARY
	)
	canvas._draw_arrow(
		horizontal_tip,
		tip,
		Color(vertical_color, 0.82 * intro),
		VisualLanguage.STROKE_SECONDARY
	)
	canvas.draw_dashed_line(
		horizontal_tip,
		tip,
		Color(vertical_color, 0.24 * intro),
		VisualLanguage.STROKE_MEASURE,
		8.0,
		true
	)
	canvas._draw_module_label(tip + Vector2(18, -14), "v", Color(theme_colors["highlight"], intro))
	canvas._draw_module_label(horizontal_tip + Vector2(-54, 36), "vₓ", Color(horizontal_color, intro))
	canvas._draw_module_label(
		horizontal_tip.lerp(tip, 0.52) + Vector2(20, 0),
		"vᵧ",
		Color(vertical_color, intro)
	)
	var points: PackedVector2Array = canvas.trajectories_by_id.get(
		active_id,
		PackedVector2Array()
	)
	if not points.is_empty():
		var clock_center: Vector2 = canvas._map_point(points[-1]) + Vector2(38, -62)
		canvas.draw_arc(
			clock_center,
			28.0,
			0.0,
			TAU,
			28,
			Color(theme_colors["muted"], 0.48 * intro),
			VisualLanguage.STROKE_MEASURE,
			true
		)
		canvas.draw_line(
			clock_center,
			clock_center + Vector2(3, -17),
			Color(theme_colors["accent"], 0.76 * intro),
			VisualLanguage.STROKE_MEASURE,
			true
		)
		canvas.draw_line(
			clock_center,
			clock_center + Vector2(13, 6),
			Color(theme_colors["accent"], 0.76 * intro),
			VisualLanguage.STROKE_MEASURE,
			true
		)
		canvas._draw_module_label(
			clock_center + Vector2(38, 8),
			"t = %.2f s" % TrajectoryAnnotation.flight_time_sec(active_record),
			Color(theme_colors["accent"], intro)
		)


func _variant_weights(canvas, variant_count: int) -> Array[float]:
	var result: Array[float] = []
	result.resize(variant_count)
	var step := clampi(int(canvas.current_beat.get("formula_step", 0)), 0, 2)
	if step != 1:
		var winner_id := String(canvas.analysis.get("winner_id", ""))
		var winner_index := clampi(variant_count / 2, 0, variant_count - 1)
		for index in range(canvas.episode.get("variants", []).size()):
			if String(canvas.episode["variants"][index]["id"]) == winner_id:
				winner_index = index
				break
		result[winner_index] = 1.0
		return result
	var position := smoothstep(0.04, 0.96, _beat_progress(canvas)) * float(variant_count - 1)
	for index in range(variant_count):
		result[index] = maxf(0.0, 1.0 - absf(position - float(index)))
	return result


func _beat_progress(canvas) -> float:
	if canvas.current_beat.is_empty():
		return 0.0
	return clampf(
		(canvas.video_time_sec - float(canvas.current_beat.get("at", canvas.video_time_sec)))
		/ maxf(0.001, float(canvas.current_beat.get("duration", 1.0))),
		0.0,
		1.0
	)
