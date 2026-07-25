class_name DragEffectExplanation
extends RefCounted

const ReplayTrack = preload("res://src/playback/replay_track.gd")
const ShotModel = preload("res://src/core/shot_model.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")
const VisualLanguage = preload("res://src/video/visual_language.gd")


func hides_physical_stage() -> bool:
	return false


func draw(canvas, opacity: float = 1.0) -> void:
	var variants: Array = canvas.episode.get("variants", [])
	if variants.is_empty():
		return
	var step := clampi(int(canvas.current_beat.get("formula_step", 0)), 0, 2)
	var focus_id := String(canvas.current_beat.get("focus", "angle-45"))
	if not canvas.records_by_id.has(focus_id):
		focus_id = String(variants[variants.size() / 2]["id"])
	var record: Dictionary = canvas.records_by_id.get(focus_id, {})
	if record.is_empty():
		return
	var focus_variant := _variant_for_id(variants, focus_id)
	var intro: float = float(canvas._beat_intro_progress(0.9)) * clampf(opacity, 0.0, 1.0)
	_draw_ideal_reference(canvas, focus_variant, intro)
	_draw_real_trajectory(canvas, focus_id, intro)
	if step >= 1:
		_draw_force_pair(canvas, record, focus_id, intro)
	if step >= 2:
		_draw_angle_family(canvas, focus_id, intro)


func _draw_ideal_reference(canvas, variant: Dictionary, alpha: float) -> void:
	var physics: Dictionary = variant["preset"]["physics"]
	var scene: Dictionary = variant["preset"]["scene"]
	var speed := float(physics.get("launch_speed_mps", 0.0))
	if speed <= 0.0:
		speed = ShotModel.launch_speed(
			float(physics["spring_k_npm"]), float(physics["stretch_m"]),
			float(physics["bird_mass_kg"]), float(physics["efficiency"])
		)
	var velocity := ShotModel.launch_velocity(speed, float(physics["launch_angle_deg"]))
	var start := Vector2(scene["launch_position_m"])
	var ppm := float(physics["pixels_per_meter"])
	var points := PackedVector2Array()
	for index in range(81):
		var t := float(index) * 0.05
		var position_m := ShotModel.projectile_position(
			start, velocity, float(physics["gravity_mps2"]), t
		)
		if position_m.y > float(scene["ground_y_m"]):
			break
		points.append(canvas._map_point(position_m * ppm))
	if points.size() >= 2:
		for index in range(points.size() - 1):
			if index % 4 < 2:
				canvas.draw_line(
					points[index], points[index + 1],
					Color(canvas.episode["theme"]["colors"]["muted"], 0.32 * alpha),
					VisualLanguage.STROKE_CONTEXT, true
				)
		canvas.draw_string(
			VideoTypography.medium(), points[mini(18, points.size() - 1)] + Vector2(18, -16),
			"理想真空", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(canvas.episode["theme"]["colors"]["muted"], 0.68 * alpha)
		)


func _draw_real_trajectory(canvas, focus_id: String, alpha: float) -> void:
	var points: PackedVector2Array = canvas._map_points(
		canvas.trajectories_by_id.get(focus_id, PackedVector2Array())
	)
	if points.size() < 2:
		return
	canvas.draw_polyline(
		points, Color(canvas.colors_by_id[focus_id], 0.82 * alpha),
		VisualLanguage.STROKE_PRIMARY, true
	)
	canvas.draw_string(
		VideoTypography.medium(), points[mini(23, points.size() - 1)] + Vector2(18, 30),
		"有空气", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(canvas.colors_by_id[focus_id], 0.86 * alpha)
	)


func _draw_force_pair(canvas, record: Dictionary, focus_id: String, alpha: float) -> void:
	var flight_time := float(record.get("metrics", {}).get("flight_time_sec", 0.0))
	var state := ReplayTrack.sample(record, flight_time * 0.36)
	if state.is_empty():
		return
	var center: Vector2 = canvas._map_point(Vector2(state["bird_position_px"]))
	var velocity := Vector2(state.get("velocity_mps", Vector2.ZERO))
	var drag := Vector2(state.get("drag_force_n", Vector2.ZERO))
	if velocity.length() > 0.01:
		var velocity_tip: Vector2 = center + velocity.normalized() * 132.0
		canvas._draw_arrow(
			center, velocity_tip, Color(canvas.colors_by_id[focus_id], 0.76 * alpha),
			VisualLanguage.STROKE_SECONDARY
		)
		canvas._draw_module_label(
			velocity_tip + Vector2(14, -8), "v", Color(canvas.colors_by_id[focus_id], alpha)
		)
	if drag.length() > 1e-6:
		var drag_tip: Vector2 = center + drag.normalized() * 110.0
		canvas._draw_arrow(
			center, drag_tip, Color(canvas.episode["theme"]["colors"]["accent"], 0.84 * alpha),
			VisualLanguage.STROKE_PRIMARY
		)
		canvas._draw_module_label(
			drag_tip + Vector2(-62, -12), "F阻力",
			Color(canvas.episode["theme"]["colors"]["accent"], alpha)
		)
	canvas.draw_circle(center, 10.0, Color(canvas.colors_by_id[focus_id], 0.92 * alpha))


func _draw_angle_family(canvas, focus_id: String, alpha: float) -> void:
	for variant_value in canvas.episode.get("variants", []):
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		if id == focus_id:
			continue
		var points: PackedVector2Array = canvas._map_points(
			canvas.trajectories_by_id.get(id, PackedVector2Array())
		)
		if points.size() >= 2:
			canvas.draw_polyline(
				points, Color(canvas.colors_by_id[id], 0.16 * alpha),
				VisualLanguage.STROKE_CONTEXT, true
			)


func _variant_for_id(variants: Array, id: String) -> Dictionary:
	for variant_value in variants:
		var variant: Dictionary = variant_value
		if String(variant["id"]) == id:
			return variant
	return variants[0]
