class_name SlingshotEpisodeCanvas
extends Node2D

const ReplayTrack = preload("res://src/playback/replay_track.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const EpisodeDirector = preload("res://src/video/episode_director.gd")
const ShotCamera = preload("res://src/video/shot_camera.gd")
const ExplanationRegistry = preload("res://src/video/explanations/explanation_registry.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")
const VisualLanguage = preload("res://src/video/visual_language.gd")

var episode: Dictionary = {}
var bundle: Dictionary = {}
var analysis: Dictionary = {}
var phase := "QUESTION"
var simulation_times_by_id: Dictionary = {}
var states_by_id: Dictionary = {}
var records_by_id: Dictionary = {}
var colors_by_id: Dictionary = {}
var trajectories_by_id: Dictionary = {}
var launch_position_px := Vector2(240, 760)
var target_position_px := Vector2(1320, 760)
var ground_y_px := 920.0
var video_time_sec := 0.0
var current_beat: Dictionary = {}
var camera_state := {"scale": 1.0, "offset": Vector2.ZERO}
var explanation_module: RefCounted


func configure(
	normalized_episode: Dictionary,
	run_bundle: Dictionary,
	comparison: Dictionary
) -> void:
	episode = normalized_episode
	bundle = run_bundle
	analysis = comparison
	var explanation: Dictionary = episode["story"].get("explanation", {})
	explanation_module = ExplanationRegistry.create(String(explanation.get("module", "")))
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		colors_by_id[variant["id"]] = variant["color"]
	for record_value in bundle["records"]:
		var record: Dictionary = record_value
		records_by_id[record["variant_id"]] = record
		trajectories_by_id[record["variant_id"]] = ReplayTrack.full_trajectory(record)
	var first_variant: Dictionary = episode["variants"][0]
	var preset: Dictionary = first_variant["preset"]
	var ppm: float = preset["physics"]["pixels_per_meter"]
	launch_position_px = preset["scene"]["launch_position_m"] * ppm
	target_position_px = preset["scene"]["target_position_m"] * ppm
	ground_y_px = preset["scene"]["ground_y_m"] * ppm
	camera_state = ShotCamera.desired_state(
		"QUESTION",
		episode.get("beats", [{}])[0],
		EpisodeLayout.SOURCE_WORLD_RECT.get_center()
	)
	queue_redraw()


func set_playback(
	value_phase: String,
	times: Dictionary,
	states: Dictionary,
	elapsed_video_sec: float = 0.0,
	beat: Dictionary = {}
) -> void:
	phase = value_phase
	simulation_times_by_id = times
	states_by_id = states
	video_time_sec = elapsed_video_sec
	current_beat = beat
	camera_state = _resolve_camera_state()
	queue_redraw()


func _draw() -> void:
	_draw_background()
	var overlay := String(current_beat.get("overlay", ""))
	if String(episode.get("simulation", {}).get("model", "")) == "impact_pulse":
		_draw_impact_episode(overlay)
		return
	if overlay in ["range-curve", "parameter-curve"]:
		if _handoff_kind() == "landings-to-chart" and _handoff_progress() < 1.0:
			_draw_previous_landing_handoff()
		_draw_range_curve()
		return
	if _is_chart_handoff():
		_draw_previous_chart_handoff()
	if _has_layer("grid"):
		_draw_grid()
	if _show_physical_stage():
		_draw_sling()
	if _is_question_to_explanation_handoff():
		_draw_question_handoff()
	if _is_explanation_to_controls_handoff():
		_draw_explanation_handoff()
	if phase == "EXPLAIN" and _has_layer("annotations"):
		_draw_explanation_module()
	elif phase == "QUESTION" and _has_layer("subjects"):
		_draw_cold_open_teaser()
	if _show_physical_stage() and episode["story"].get("show_target", true):
		_draw_target_platform()
		_draw_reference_target()
	if _has_layer("trajectories"):
		_draw_trajectories()
	if _is_explanation_to_controls_handoff():
		_draw_control_origin_bridge()
	if _is_chart_handoff():
		_draw_chart_to_trajectory_bridge()
	if String(current_beat.get("id", "")) == "launch":
		_draw_launch_guide_handoff()
	if overlay == "model-boundary":
		_draw_model_boundary_labels()
	if phase in ["FLIGHT", "COMPARE"] and _has_layer("subjects"):
		if episode["story"].get("show_target", true):
			_draw_variant_targets()
		_draw_variant_birds()
		_draw_event_effects()
	if overlay == "landing-magnifier":
		_draw_landing_magnifier()
	if phase == "COMPARE" and _has_layer("results"):
		if overlay != "range-curve":
			_draw_result_markers()
	elif phase == "COMPARE" and String(current_beat.get("overlay", "")) == "counterexample":
		_draw_focus_height_marker()


func _draw_impact_episode(overlay: String) -> void:
	match overlay:
		"impact-sampling-cold-open":
			_draw_impact_sampling_miss(true)
		"impact-hook-time-gap":
			_draw_hook_time_gap()
		"impact-hook-system-error":
			_draw_hook_system_error()
		"impact-hook-curve-transform":
			_draw_hook_curve_transform()
		"impact-hook-forensics":
			_draw_hook_forensics()
		"impact-hook-fivefold":
			_draw_hook_fivefold()
		"curve-slingshot-stinger":
			_draw_curve_slingshot_stinger()
		"impact-title":
			_draw_impact_title_field()
		"impact-dual":
			_draw_dual_impact()
		"impact-hard-profile":
			_draw_contact_profile("hard")
		"impact-soft-profile":
			_draw_contact_profile("soft")
		"impact-momentum":
			_draw_impact_momentum()
		"impact-equal-area":
			_draw_equal_area()
		"impact-formula":
			_draw_impulse_formula()
		"impact-area-stretch":
			_draw_area_stretch()
		"impact-applications":
			_draw_impact_applications()
		"impact-contact-model":
			_draw_contact_model()
		"impact-sampling":
			_draw_sampling_build()
		"impact-sampling-miss":
			_draw_impact_sampling_miss(false)
		"impact-damage-boundary":
			_draw_damage_boundary()
		"impact-takeaway":
			_draw_impact_takeaway()


func _impact_record(id: String) -> Dictionary:
	return records_by_id.get(id, {})


func _impact_metrics(id: String) -> Dictionary:
	return _impact_record(id).get("metrics", {})


func _impact_plot() -> Rect2:
	return Rect2(745, 238, 1035, 575)


func _draw_force_axes(plot: Rect2, max_time_ms: float, max_force_n: float, alpha: float = 1.0) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	draw_line(
		Vector2(plot.position.x, plot.end.y), plot.end,
		Color(colors["divider"], 0.72 * alpha), VisualLanguage.STROKE_MEASURE, true
	)
	draw_line(
		plot.position, Vector2(plot.position.x, plot.end.y),
		Color(colors["divider"], 0.72 * alpha), VisualLanguage.STROKE_MEASURE, true
	)
	var time_ticks := _force_time_ticks(max_time_ms)
	for tick_index in range(time_ticks.size()):
		var tick_value: float = time_ticks[tick_index]
		var ratio := tick_value / max_time_ms
		var x := lerpf(plot.position.x, plot.end.x, ratio)
		draw_line(Vector2(x, plot.end.y), Vector2(x, plot.end.y + 8), Color(colors["divider"], 0.55 * alpha), 1.0, true)
		draw_string(
			VideoTypography.data(), Vector2(x - 38, plot.end.y + 38),
			"%.0f" % tick_value, HORIZONTAL_ALIGNMENT_CENTER, 76, 24,
			Color(colors["muted"], 0.80 * alpha)
		)
	var force_ticks := [400.0, 800.0, 1200.0, 1600.0]
	for tick_value in force_ticks:
		if tick_value > max_force_n:
			continue
		var ratio: float = tick_value / max_force_n
		var y := lerpf(plot.end.y, plot.position.y, ratio)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(colors["divider"], 0.10 * alpha), 1.0, true)
		draw_line(Vector2(plot.position.x - 8, y), Vector2(plot.position.x, y), Color(colors["divider"], 0.55 * alpha), 1.0, true)
		draw_string(
			VideoTypography.data(), Vector2(plot.position.x - 100, y + 8),
			"%.0f" % tick_value, HORIZONTAL_ALIGNMENT_RIGHT, 88, 24,
			Color(colors["muted"], 0.76 * alpha)
		)
	draw_string(VideoTypography.medium(), Vector2(plot.position.x, plot.position.y - 38), "法向接触力 Fₙ / N", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(colors["muted"], 0.88 * alpha))
	draw_string(VideoTypography.medium(), Vector2(plot.end.x - 220, plot.end.y + 70), "时间 t / ms", HORIZONTAL_ALIGNMENT_RIGHT, 220, 25, Color(colors["muted"], 0.88 * alpha))


func _force_time_ticks(max_time_ms: float) -> Array[float]:
	if max_time_ms <= 34.0:
		return [0.0, 8.0, 16.0, 24.0, 32.0]
	return [0.0, 10.0, 20.0, 30.0, 40.0]


func _force_value(impulse_ns: float, duration_sec: float, time_sec: float) -> float:
	if time_sec < 0.0 or time_sec > duration_sec:
		return 0.0
	return PI * impulse_ns / (2.0 * duration_sec) * sin(PI * time_sec / duration_sec)


func _force_point(
	plot: Rect2,
	time_sec: float,
	force_n: float,
	max_time_sec: float,
	max_force_n: float
) -> Vector2:
	return Vector2(
		plot.position.x + plot.size.x * time_sec / maxf(max_time_sec, 1e-6),
		plot.end.y - plot.size.y * force_n / maxf(max_force_n, 1e-6)
	)


func _draw_force_profile(
	plot: Rect2,
	impulse_ns: float,
	duration_sec: float,
	max_time_sec: float,
	max_force_n: float,
	color: Color,
	reveal: float = 1.0,
	fill_alpha: float = 0.14,
	offset_sec: float = 0.0
) -> void:
	var samples := 96
	var visible := clampf(reveal, 0.0, 1.0)
	var previous := _force_point(plot, offset_sec, 0.0, max_time_sec, max_force_n)
	for index in range(samples + 1):
		var u := float(index) / float(samples)
		var local_time := duration_sec * u
		var shown_time := minf(local_time, duration_sec * visible)
		var force := _force_value(impulse_ns, duration_sec, shown_time)
		if local_time > duration_sec * visible:
			force = 0.0
		var point := _force_point(plot, offset_sec + local_time, force, max_time_sec, max_force_n)
		if index > 0 and local_time <= duration_sec * visible + 1e-9:
			if fill_alpha > 0.001:
				var fill_quad := PackedVector2Array([
					Vector2(previous.x, plot.end.y), previous,
					point, Vector2(point.x, plot.end.y),
				])
				draw_colored_polygon(fill_quad, Color(color, fill_alpha))
			draw_line(previous, point, Color(color, 0.96), VisualLanguage.STROKE_PRIMARY, true)
		previous = point


func _draw_force_cursor(
	plot: Rect2,
	duration_sec: float,
	max_time_sec: float,
	max_force_n: float,
	color: Color,
	progress: float,
	offset_sec: float = 0.0
) -> void:
	var local_time := duration_sec * clampf(progress, 0.0, 1.0)
	var force := _force_value(8.0, duration_sec, local_time)
	var point := _force_point(
		plot, offset_sec + local_time, force, max_time_sec, max_force_n
	)
	draw_line(
		Vector2(point.x, plot.end.y), point,
		Color(color, 0.24), 2.0, true
	)
	draw_circle(point, 11.0, Color(color, 0.10))
	draw_circle(point, 5.5, Color(color, 0.98))


func _draw_impact_ball(center: Vector2, color: Color, radius: float = 46.0) -> void:
	_draw_deformed_impact_ball(center, color, radius, 0.0)


func _draw_deformed_impact_ball(
	center: Vector2,
	color: Color,
	radius: float,
	compression: float
) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var squeeze := clampf(compression, 0.0, 1.0)
	var scale_value := Vector2(1.0 - 0.24 * squeeze, 1.0 + 0.13 * squeeze)
	draw_set_transform(center, 0.0, scale_value)
	draw_circle(Vector2.ZERO, radius + 5.0, Color(color, 0.07))
	draw_circle(Vector2.ZERO, radius, Color(color, 0.92))
	draw_circle(Vector2(-radius * 0.20, radius * 0.12), radius * 0.72, Color(color.darkened(0.16), 0.22))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(colors["text"], 0.26), 2.2, true)
	draw_arc(Vector2.ZERO, radius * 0.78, 3.75, 5.25, 24, Color(colors["text"], 0.22), 5.0, true)
	draw_circle(Vector2(radius * 0.28, -radius * 0.24), radius * 0.075, Color(colors["text"], 0.88))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if squeeze > 0.02:
		draw_line(
			center + Vector2(radius * scale_value.x - 2.0, -radius * 0.38),
			center + Vector2(radius * scale_value.x - 2.0, radius * 0.38),
			Color(colors["text"], 0.34 * squeeze), 3.0, true
		)


func _draw_wall(x: float, top: float, bottom: float, soft: bool, compression: float = 0.0) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	if soft:
		var width := 112.0
		var depth := 42.0 * clampf(compression, 0.0, 1.0)
		var center_y := (top + bottom) * 0.5
		var left_edge := PackedVector2Array()
		for index in range(25):
			var u := float(index) / 24.0
			var y := lerpf(top, bottom, u)
			var normalized_y := (y - center_y) / maxf(1.0, (bottom - top) * 0.23)
			var indentation := depth * exp(-normalized_y * normalized_y)
			left_edge.append(Vector2(x + indentation, y))
		var shape := PackedVector2Array(left_edge)
		shape.append(Vector2(x + width, bottom))
		shape.append(Vector2(x + width, top))
		draw_colored_polygon(shape, Color(colors["highlight"], 0.18))
		draw_polyline(left_edge, Color(colors["highlight"], 0.76), 4.0, true)
		draw_line(Vector2(x + width, top), Vector2(x + width, bottom), Color(colors["muted"], 0.58), 4.0, true)
		for stripe_y in range(int(top + 22), int(bottom), 38):
			var normalized_y := (float(stripe_y) - center_y) / maxf(1.0, (bottom - top) * 0.23)
			var indentation := depth * exp(-normalized_y * normalized_y)
			draw_line(Vector2(x + indentation + 14, stripe_y), Vector2(x + width - 14, stripe_y - 14), Color(colors["highlight"], 0.38), 2.0, true)
	else:
		draw_rect(Rect2(x, top, 22, bottom - top), Color(colors["text"], 0.68), true)
		draw_line(Vector2(x + 2, top), Vector2(x + 2, bottom), Color(colors["text"], 0.30), 5.0, true)
		for stripe_y in range(int(top + 12), int(bottom), 28):
			draw_line(Vector2(x + 20, stripe_y), Vector2(x + 42, stripe_y + 18), Color(colors["divider"], 0.72), 2.0, true)


func _draw_dual_impact() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var elapsed := maxf(0.0, video_time_sec - float(current_beat.get("at", video_time_sec)))
	var motion_progress := clampf(elapsed / 9.5, 0.0, 1.0)
	var cycle := smoothstep(0.0, 1.0, motion_progress)
	var timeline_ms := lerpf(-8.0, 48.0, cycle)
	var panels := [Rect2(80, 140, 830, 650), Rect2(1010, 140, 830, 650)]
	var ids := ["hard", "soft"]
	for index in range(2):
		var panel: Rect2 = panels[index]
		var id: String = ids[index]
		var color: Color = colors_by_id[id]
		draw_rect(panel, Color(colors["surface"], 0.72), true)
		draw_rect(panel, Color(colors["divider"], 0.42), false, 2.0)
		draw_string(VideoTypography.medium(), panel.position + Vector2(34, 52), "钢板" if id == "hard" else "软垫", HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color(colors["text"], 0.92))
		var duration_ms := 8.0 if id == "hard" else 40.0
		var contact_time := clampf(timeline_ms, 0.0, duration_ms)
		var contact := sin(PI * contact_time / duration_ms) if timeline_ms >= 0.0 and timeline_ms <= duration_ms else 0.0
		draw_rect(panel, Color(color, 0.16 * contact), false, 3.0 + 3.0 * contact)
		var approach := smoothstep(-8.0, 0.0, timeline_ms)
		var rebound := smoothstep(duration_ms, duration_ms + 8.0, timeline_ms)
		var wall_x := panel.end.x - 145.0
		var vibration := 0.0
		if id == "hard" and timeline_ms > duration_ms:
			var vibration_time := timeline_ms - duration_ms
			vibration = sin(vibration_time * 2.8) * exp(-vibration_time * 0.22) * 5.0
		wall_x += vibration
		var ball_x := lerpf(panel.position.x + 115.0, wall_x - 48.0, approach) - rebound * 150.0
		if id == "soft":
			ball_x += contact * 34.0
		else:
			ball_x += contact * 7.0
		_draw_wall(wall_x, panel.position.y + 130, panel.end.y - 110, id == "soft", contact)
		_draw_deformed_impact_ball(Vector2(ball_x, panel.position.y + 360), color, 48.0, contact * (0.30 if id == "hard" else 0.72))
		if contact > 0.04:
			var ring_alpha := contact * (0.50 if id == "hard" else 0.20)
			draw_arc(Vector2(wall_x - 10, panel.position.y + 360), 28.0 + 54.0 * contact, -PI * 0.5, PI * 0.5, 28, Color(color, ring_alpha), 3.0, true)
		var trail_alpha := (1.0 - approach) * 0.20
		for trail in range(3):
			draw_line(Vector2(ball_x - 55 - trail * 32, panel.position.y + 360), Vector2(ball_x - 32 - trail * 32, panel.position.y + 360), Color(color, trail_alpha - trail * 0.04), 3.0, true)
		draw_string(VideoTypography.data(), panel.position + Vector2(34, panel.size.y - 38), "5 m/s → 3 m/s 反弹", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(colors["muted"], 0.88))
		var state_copy := (
			"接近中" if timeline_ms < 0.0
			else ("接触结束" if timeline_ms > duration_ms else "接触中  %.0f ms" % timeline_ms)
		)
		draw_string(VideoTypography.data(), panel.position + Vector2(420, 52), state_copy, HORIZONTAL_ALIGNMENT_RIGHT, 360, 27, Color(color, 0.92))
	var rail := Rect2(520, 825, 880, 4)
	draw_rect(rail, Color(colors["divider"], 0.46), true)
	var cursor_pulse := 0.0
	for mark_ms in [0.0, 8.0, 40.0]:
		var mark_value := float(mark_ms)
		var mark_x: float = rail.position.x + rail.size.x * (mark_value + 8.0) / 56.0
		var arrival_sec := 9.5 * (mark_value + 8.0) / 56.0
		var pulse := exp(-pow((elapsed - arrival_sec) / 0.28, 2.0))
		cursor_pulse = maxf(cursor_pulse, pulse)
		draw_line(Vector2(mark_x, rail.position.y - 9), Vector2(mark_x, rail.position.y + 13), Color(colors["muted"], 0.70), 2.0, true)
		draw_string(VideoTypography.data(), Vector2(mark_x - 42, rail.position.y + 42), "%.0f ms" % mark_value, HORIZONTAL_ALIGNMENT_CENTER, 84, 24, Color(colors["muted"], 0.82))
	var cursor_x := rail.position.x + rail.size.x * clampf(cycle, 0.0, 1.0)
	draw_circle(Vector2(cursor_x, rail.position.y + 2), 14.0 + 12.0 * cursor_pulse, Color(colors["accent"], 0.08 * cursor_pulse))
	draw_circle(Vector2(cursor_x, rail.position.y + 2), 8.0 + 3.0 * cursor_pulse, Color(colors["accent"], 0.96))
	draw_string(VideoTypography.medium(), Vector2(700, 905), "接触过程 ×100 慢放", HORIZONTAL_ALIGNMENT_CENTER, 520, 27, Color(colors["text"], 0.86))


func _draw_contact_profile(id: String) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var metrics := _impact_metrics(id)
	var plot := _impact_plot()
	var duration := float(metrics["contact_duration_sec"])
	var impulse := float(metrics["impulse_ns"])
	var color: Color = colors_by_id[id]
	var elapsed := maxf(0.0, video_time_sec - float(current_beat.get("at", video_time_sec)))
	var beat_duration := float(current_beat.get("duration", 15.0))
	var motion_window := maxf(8.0, beat_duration - 2.8)
	var motion_progress := clampf(elapsed / motion_window, 0.0, 1.0)
	var cycle := smoothstep(0.0, 1.0, motion_progress)
	var timeline_sec := lerpf(-duration * 0.22, duration * 1.22, cycle)
	var contact_ratio := clampf(timeline_sec / duration, 0.0, 1.0)
	var contact := sin(contact_ratio * PI) if timeline_sec >= 0.0 and timeline_sec <= duration else 0.0
	var wall_x := 575.0
	if id == "hard" and timeline_sec > duration:
		var ring_down := (timeline_sec - duration) / maxf(duration * 0.22, 1e-5)
		wall_x += sin(ring_down * PI * 4.0) * exp(-ring_down * 2.8) * 5.0
	_draw_wall(wall_x, 300, 735, id == "soft", contact)
	var indentation := 5.0 if id == "hard" else 36.0
	var rebound := smoothstep(duration, duration * 1.22, timeline_sec)
	var approach := smoothstep(-duration * 0.22, 0.0, timeline_sec)
	var ball_x := lerpf(270.0, wall_x - 48.0, approach) + indentation * contact - rebound * 120.0
	_draw_deformed_impact_ball(Vector2(ball_x, 520), color, 48.0, contact * (0.30 if id == "hard" else 0.72))
	draw_string(VideoTypography.medium(), Vector2(100, 220), "硬接触 · 8 ms" if id == "hard" else "软接触 · 40 ms", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(colors["text"], 0.94))
	draw_string(VideoTypography.data(), Vector2(100, 790), "最大形变  %.0f mm" % (float(metrics["max_penetration_m"]) * 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(colors["muted"], 0.86))
	_draw_force_axes(plot, 45.0, 1700.0)
	_draw_force_profile(plot, impulse, duration, 0.045, 1700.0, color, contact_ratio, 0.16)
	if timeline_sec >= 0.0 and timeline_sec <= duration:
		_draw_force_cursor(plot, duration, 0.045, 1700.0, color, contact_ratio)
	if id == "soft":
		var depth_mm := float(metrics["max_penetration_m"]) * 1000.0 * contact
		var gauge_y := 745.0
		draw_line(Vector2(wall_x, gauge_y), Vector2(wall_x + 36.0 * contact, gauge_y), Color(color, 0.88), 3.0, true)
		draw_line(Vector2(wall_x, gauge_y - 10), Vector2(wall_x, gauge_y + 10), Color(color, 0.72), 2.0, true)
		draw_line(Vector2(wall_x + 36.0 * contact, gauge_y - 10), Vector2(wall_x + 36.0 * contact, gauge_y + 10), Color(color, 0.72), 2.0, true)
		draw_string(VideoTypography.data(), Vector2(405, 785), "当前压入  %.0f mm" % depth_mm, HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(color, 0.88))
	var peak := float(metrics["peak_force_n"])
	draw_string(VideoTypography.data(), plot.position + Vector2(560, 42), "峰值  %.0f N" % peak, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(color, smoothstep(0.72, 0.96, contact_ratio)))
	var timeline_copy := (
		"接触结束 · 完整曲线已保留" if timeline_sec >= duration
		else "接触过程慢放 · 当前 %.1f ms" % maxf(0.0, timeline_sec * 1000.0)
	)
	draw_string(VideoTypography.medium(), Vector2(130, 875), timeline_copy, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(colors["text"], 0.84))


func _draw_impact_momentum() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var elapsed := maxf(
		0.0, video_time_sec - float(current_beat.get("at", video_time_sec))
	)
	var incoming_start_sec := 3.0
	var impact_sec := 6.0
	var rebound_start_sec := 6.35
	var rebound_end_sec := 9.35
	var start_x := 320.0
	var wall_x := 1250.0
	var radius := 56.0
	var impact_x := wall_x - radius
	# Equal three-second windows preserve the actual 5:3 speed ratio onscreen.
	var incoming_distance := impact_x - start_x
	var rebound_distance := incoming_distance * 3.0 / 5.0
	var incoming_progress := clampf(
		inverse_lerp(incoming_start_sec, impact_sec, elapsed), 0.0, 1.0
	)
	var rebound_progress := clampf(
		inverse_lerp(rebound_start_sec, rebound_end_sec, elapsed), 0.0, 1.0
	)
	var compression := 0.0
	var ball_x := lerpf(start_x, impact_x, incoming_progress)
	if elapsed >= impact_sec and elapsed < rebound_start_sec:
		var contact_progress := inverse_lerp(impact_sec, rebound_start_sec, elapsed)
		compression = sin(contact_progress * PI)
		ball_x = impact_x + compression * 8.0
	elif elapsed >= rebound_start_sec:
		ball_x = lerpf(impact_x, impact_x - rebound_distance, rebound_progress)
	_draw_wall(wall_x, 310, 700, false, compression)
	draw_string(
		VideoTypography.medium(), Vector2(wall_x - 70, 270), "钢板",
		HORIZONTAL_ALIGNMENT_CENTER, 160, 29, Color(colors["muted"], 0.88)
	)
	draw_line(
		Vector2(240, 590), Vector2(1420, 590),
		Color(colors["divider"], 0.54), 2.0, true
	)
	for tick_x in range(280, 1401, 80):
		draw_line(
			Vector2(tick_x, 582), Vector2(tick_x, 598),
			Color(colors["divider"], 0.40), 1.5, true
		)
	var moving_right := elapsed >= incoming_start_sec and elapsed < impact_sec
	var moving_left := elapsed >= rebound_start_sec and elapsed < rebound_end_sec
	var trail_direction := -1.0 if moving_right else 1.0
	var trail_spacing := 42.0 if moving_right else 25.2
	if moving_right or moving_left:
		for trail_index in range(1, 4):
			var trail_center := Vector2(
				ball_x + trail_direction * trail_spacing * trail_index, 500
			)
			draw_circle(
				trail_center, radius * (1.0 - trail_index * 0.10),
				Color(colors_by_id["hard"], 0.12 - trail_index * 0.025)
			)
	_draw_deformed_impact_ball(
		Vector2(ball_x, 500), colors_by_id["hard"], radius, compression * 0.34
	)
	if compression > 0.02:
		draw_arc(
			Vector2(wall_x - 8, 500), 38.0 + compression * 70.0,
			-PI * 0.5, PI * 0.5, 32,
			Color(colors["accent"], 0.46 * compression), 4.0, true
		)
	var state_copy := "质量  1 kg"
	var state_color: Color = colors["text"]
	if moving_right:
		state_copy = "向右运动  +5 m/s"
		state_color = colors["highlight"]
	elif elapsed >= impact_sec and elapsed < rebound_start_sec:
		state_copy = "接触 · 速度反向"
		state_color = colors["accent"]
	elif elapsed >= rebound_start_sec:
		state_copy = "向左反弹  -3 m/s"
		state_color = colors["muted"]
	draw_string(
		VideoTypography.bold(), Vector2(560, 215), state_copy,
		HORIZONTAL_ALIGNMENT_CENTER, 800, 39, Color(state_color, 0.96)
	)
	var reveal := smoothstep(9.35, 11.4, elapsed)
	draw_string(VideoTypography.bold(), Vector2(420, 820), "|Δpₓ| = 1 kg × |-3 - 5| m/s = 8 kg·m/s", HORIZONTAL_ALIGNMENT_CENTER, 1080, 42, Color(colors["text"], reveal))


func _draw_equal_area() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := _beat_progress()
	var hard_plot := Rect2(130, 270, 720, 460)
	var soft_plot := Rect2(1070, 270, 720, 460)
	_draw_force_axes(hard_plot, 45, 1700, 0.65)
	_draw_force_axes(soft_plot, 45, 1700, 0.65)
	var hard_reveal := smoothstep(0.04, 0.34, p)
	var soft_reveal := smoothstep(0.28, 0.58, p)
	_draw_force_profile(hard_plot, 8.0, 0.008, 0.045, 1700, colors_by_id["hard"], hard_reveal, 0.22)
	_draw_force_profile(soft_plot, 8.0, 0.040, 0.045, 1700, colors_by_id["soft"], soft_reveal, 0.22)
	draw_string(VideoTypography.bold(), Vector2(130, 185), "钢板工况 · 8 ms", HORIZONTAL_ALIGNMENT_CENTER, 720, 32, Color(colors_by_id["hard"], 0.96))
	draw_string(VideoTypography.bold(), Vector2(1070, 185), "软垫工况 · 40 ms", HORIZONTAL_ALIGNMENT_CENTER, 720, 32, Color(colors_by_id["soft"], 0.96))
	var hard_badge := smoothstep(0.34, 0.52, p)
	var soft_badge := smoothstep(0.54, 0.70, p)
	var equality := smoothstep(0.72, 0.86, p)
	var hard_card := Rect2(280, 835, 520, 74)
	var soft_card := Rect2(1120, 835, 520, 74)
	draw_rect(hard_card, Color(colors_by_id["hard"], 0.08 * hard_badge), true)
	draw_rect(hard_card, Color(colors_by_id["hard"], 0.60 * hard_badge), false, 2.0)
	draw_rect(soft_card, Color(colors_by_id["soft"], 0.08 * soft_badge), true)
	draw_rect(soft_card, Color(colors_by_id["soft"], 0.60 * soft_badge), false, 2.0)
	draw_string(VideoTypography.bold(), Vector2(305, 884), "钢板工况 · Jₙ = 8 N·s", HORIZONTAL_ALIGNMENT_CENTER, 470, 34, Color(colors_by_id["hard"], hard_badge))
	draw_string(VideoTypography.bold(), Vector2(1145, 884), "软垫工况 · Jₙ = 8 N·s", HORIZONTAL_ALIGNMENT_CENTER, 470, 34, Color(colors_by_id["soft"], soft_badge))
	draw_string(VideoTypography.bold(), Vector2(900, 887), "=", HORIZONTAL_ALIGNMENT_CENTER, 120, 42, Color(colors["text"], equality))


func _draw_impulse_formula() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := _beat_progress()
	var plot := Rect2(150, 285, 650, 410)
	_draw_force_axes(plot, 45, 1700, 0.62)
	_draw_force_profile(plot, 8.0, 0.040, 0.045, 1700, colors_by_id["soft"], smoothstep(0.0, 0.40, p), 0.20)
	draw_string(VideoTypography.medium(), Vector2(220, 805), "曲线积分  8 N·s", HORIZONTAL_ALIGNMENT_CENTER, 510, 32, Color(colors["accent"], smoothstep(0.28, 0.58, p)))


func _draw_area_stretch() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := smoothstep(0.08, 0.84, _beat_progress())
	var duration := lerpf(0.008, 0.040, p)
	var peak := PI * 8.0 / (2.0 * duration)
	var average := 8.0 / duration
	var plot := Rect2(250, 230, 1420, 560)
	_draw_force_axes(plot, 45, 1700)
	_draw_force_profile(plot, 8.0, duration, 0.045, 1700, colors["accent"], 1.0, 0.20)
	var duration_x := plot.position.x + plot.size.x * duration / 0.045
	draw_line(Vector2(duration_x, plot.position.y), Vector2(duration_x, plot.end.y), Color(colors["accent"], 0.22), 2.0, true)
	draw_string(VideoTypography.bold(), Vector2(650, 165), "法向冲量始终保持  8 N·s", HORIZONTAL_ALIGNMENT_CENTER, 620, 34, Color(colors["highlight"], 0.92))
	draw_string(VideoTypography.data(), Vector2(300, 895), "接触时间  %.0f ms" % (duration * 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color(colors["text"], 0.94))
	draw_string(VideoTypography.data(), Vector2(760, 895), "平均力  %.0f N" % average, HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color(colors["muted"], 0.90))
	draw_string(VideoTypography.data(), Vector2(1190, 895), "接触力峰值  %.0f N" % peak, HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color(colors["accent"], 0.96))


func _draw_impact_applications() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := _beat_progress()
	var panels := [Rect2(100, 245, 500, 500), Rect2(710, 245, 500, 500), Rect2(1320, 245, 500, 500)]
	var labels := ["安全气囊", "头盔缓冲层", "包装泡沫"]
	for index in range(3):
		var panel: Rect2 = panels[index]
		var action := smoothstep(0.06 + index * 0.24, 0.30 + index * 0.24, p)
		draw_rect(panel, Color(colors["surface"], 0.78), true)
		draw_rect(panel, Color(colors["divider"], 0.42 + 0.24 * action), false, 2.0 + action)
		draw_string(VideoTypography.medium(), panel.position + Vector2(0, 445), labels[index], HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 31, Color(colors["text"], 0.58 + 0.34 * action))
		var center := panel.position + Vector2(250, 220)
		if index == 0:
			var bag_radius := lerpf(26.0, 118.0, action)
			draw_circle(center, bag_radius, Color(colors["highlight"], 0.08 + 0.10 * action))
			draw_arc(center, bag_radius, 0, TAU, 54, Color(colors["highlight"], 0.30 + 0.42 * action), 5.0, true)
			draw_line(center + Vector2(-120, 90), center + Vector2(120, 90), Color(colors["muted"], 0.60), 5.0, true)
		elif index == 1:
			draw_arc(center, 135, PI, TAU, 48, Color(colors["text"], 0.76), 16.0, true)
			var liner_radius := lerpf(118.0, 101.0, action)
			draw_arc(center + Vector2(0, 8.0 * action), liner_radius, PI, TAU, 48, Color(colors["accent"], 0.36 + 0.42 * action), 18.0, true)
		else:
			draw_rect(Rect2(center - Vector2(120, 100), Vector2(240, 200)), Color(colors["muted"], 0.14), false, 6.0)
			for x in range(int(center.x - 90), int(center.x + 91), 45):
				for y in range(int(center.y - 70), int(center.y + 71), 45):
					var cell := Vector2(x, y)
					draw_set_transform(cell, 0.0, Vector2(1.0 + 0.18 * action, 1.0 - 0.48 * action))
					draw_circle(Vector2.ZERO, 13, Color(colors["accent"], 0.18 + 0.24 * action))
					draw_set_transform(Vector2.ZERO)
	var conclusion_reveal := smoothstep(0.76, 0.92, p)
	draw_string(VideoTypography.bold(), Vector2(460, 805), "同样的速度变化，摊到更长的时间", HORIZONTAL_ALIGNMENT_CENTER, 1000, 39, Color(colors["accent"], 0.92 * conclusion_reveal))


func _draw_contact_model() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var elapsed := maxf(0.0, video_time_sec - float(current_beat.get("at", video_time_sec)))
	var motion_progress := clampf(elapsed / 8.5, 0.0, 1.0)
	var cycle := smoothstep(0.0, 1.0, motion_progress)
	var contact := sin(clampf((cycle - 0.18) / 0.62, 0.0, 1.0) * PI) if cycle >= 0.18 and cycle <= 0.80 else 0.0
	var approach := smoothstep(0.0, 0.18, cycle)
	var rebound := smoothstep(0.80, 1.0, cycle)
	var wall_x := 1070.0
	var node_rest_x := 620.0
	var moving_node_x := node_rest_x + 54.0 * contact
	var contact_ball_x := moving_node_x - 62.0
	var ball_x := lerpf(330.0, node_rest_x - 62.0, approach)
	if contact > 0.0:
		ball_x = contact_ball_x
	elif cycle > 0.80:
		ball_x = lerpf(node_rest_x - 62.0, 410.0, rebound)
	var ball_center := Vector2(ball_x, 510)
	_draw_deformed_impact_ball(ball_center, colors_by_id["soft"], 62, contact * 0.62)
	var spring_start := Vector2(moving_node_x, 420)
	var spring_end := Vector2(wall_x, 420)
	var spring := PackedVector2Array([spring_start])
	for index in range(1, 17):
		var u := float(index) / 17.0
		spring.append(spring_start.lerp(spring_end, u) + Vector2(0, -28 if index % 2 == 0 else 28))
	spring.append(spring_end)
	var spring_focus := smoothstep(0.25, 0.85, contact)
	draw_polyline(spring, Color(colors["accent"], 0.46 + 0.50 * spring_focus), 5.0 + 2.0 * spring_focus, true)
	draw_line(Vector2(moving_node_x, 386), Vector2(moving_node_x, 646), Color(colors["text"], 0.70), 7.0, true)
	if contact > 0.01:
		draw_line(Vector2(ball_center.x + 52.0, 510), Vector2(moving_node_x, 510), Color(colors_by_id["soft"], 0.72), 4.0, true)
	var damper_body_end := wall_x - 160.0
	var damper_focus := 0.0
	if cycle >= 0.18 and cycle <= 0.80:
		var contact_phase := clampf((cycle - 0.18) / 0.62, 0.0, 1.0)
		damper_focus = absf(cos(contact_phase * PI))
	draw_rect(Rect2(moving_node_x, 565, maxf(80.0, damper_body_end - moving_node_x), 92), Color(colors["surface_elevated"], 0.92), true)
	draw_rect(Rect2(damper_body_end, 582, 160, 58), Color(colors["muted"], 0.24 + 0.28 * damper_focus), true)
	draw_line(Vector2(moving_node_x, 611), Vector2(wall_x - 100.0, 611), Color(colors["text"], 0.46), 5.0, true)
	draw_line(Vector2(wall_x, 330), Vector2(wall_x, 715), Color(colors["text"], 0.64), 9.0, true)
	draw_string(VideoTypography.medium(), Vector2(715, 335), "弹簧力 kδ", HORIZONTAL_ALIGNMENT_CENTER, 260, 31, Color(colors["accent"], 0.92))
	draw_string(VideoTypography.medium(), Vector2(715, 710), "阻尼力 cδ̇", HORIZONTAL_ALIGNMENT_CENTER, 260, 31, Color(colors["muted"], 0.92))
	var plot := Rect2(1180, 310, 500, 360)
	_draw_force_axes(plot, 45, 1700, 0.58)
	var curve_progress := clampf((cycle - 0.18) / 0.62, 0.0, 1.0)
	_draw_force_profile(plot, 8.0, 0.040, 0.045, 1700, colors_by_id["soft"], curve_progress, 0.12)
	if cycle >= 0.18 and cycle <= 0.80:
		_draw_force_cursor(plot, 0.040, 0.045, 1700, colors_by_id["soft"], curve_progress)
	draw_string(VideoTypography.bold(), Vector2(330, 790), "Kelvin–Voigt 等效接触模型", HORIZONTAL_ALIGNMENT_CENTER, 1260, 36, Color(colors["text"], 0.92))
	draw_string(VideoTypography.medium(), Vector2(430, 850), "用于解释曲线来源 · 不反推真实材料参数", HORIZONTAL_ALIGNMENT_CENTER, 1060, 28, Color(colors["muted"], 0.84))


func _draw_sampling_build() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var plot := Rect2(230, 230, 1460, 560)
	_draw_force_axes(plot, 33.0, 1700.0)
	_draw_force_profile(plot, 8.0, 0.008, 0.033, 1700.0, colors_by_id["hard"], 1.0, 0.10, 0.012)
	var stages := [10000.0, 1000.0, 100.0, 30.0]
	var stage_position: float = minf(_beat_progress() * 4.0, 3.999)
	var stage_index := clampi(int(floor(stage_position)), 0, 3)
	var stage_fraction: float = stage_position - floor(stage_position)
	var blend := smoothstep(0.72, 0.98, stage_fraction) if stage_index < 3 else 0.0
	var rate: float = stages[stage_index]
	_draw_sampling_points(plot, rate, 0.012, 0.008, 0.033, 1700.0, 1.0 - blend)
	if stage_index < 3 and blend > 0.001:
		_draw_sampling_points(plot, float(stages[stage_index + 1]), 0.012, 0.008, 0.033, 1700.0, blend)
	if blend > 0.5 and stage_index < 3:
		rate = float(stages[stage_index + 1])
	var measured := _sampled_peak_for_rate(rate)
	draw_string(VideoTypography.bold(), Vector2(430, 860), "采样 %.0f Hz" % rate, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(colors["text"], 0.94))
	draw_string(VideoTypography.data(), Vector2(1080, 860), "采样峰值  %.0f N" % measured, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(colors["accent"], 0.96))


func _sampled_peak_for_rate(rate: float) -> float:
	for value in bundle.get("impact_measurement", {}).get("sampled_peaks", []):
		if is_equal_approx(float(value.get("rate_hz", 0.0)), rate):
			return float(value.get("peak_force_n", 0.0))
	return 0.0


func _draw_sampling_points(
	plot: Rect2,
	rate_hz: float,
	contact_start_sec: float,
	contact_duration_sec: float,
	max_time_sec: float,
	max_force_n: float,
	alpha: float = 1.0
) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var interval := 1.0 / rate_hz
	var draw_interval := interval
	if rate_hz > 1000.0:
		# Decimate dense plots using an integer number of real sample intervals.
		# A synthetic 240 Hz display grid made the markers drift away from the
		# millisecond axis labels even when the source rate was exactly 1000 Hz.
		var sample_stride := ceili(rate_hz / 1000.0)
		draw_interval = interval * sample_stride
	var sample_time := 0.0
	while sample_time <= max_time_sec + 1e-9:
		var force := _force_value(8.0, contact_duration_sec, sample_time - contact_start_sec)
		var point := _force_point(plot, sample_time, force, max_time_sec, max_force_n)
		draw_circle(point, 5.5 if rate_hz <= 100.0 else 3.5, Color(colors["text"], 0.88 * alpha))
		draw_line(Vector2(point.x, plot.end.y), point, Color(colors["text"], 0.10 * alpha), 1.0, true)
		sample_time += draw_interval
	# At 30 Hz, adjacent force-signal samples are about 33 ms apart. Keep the
	# second sampling instant visible at the plot boundary so this view can hand off
	# directly to the missed-peak explanation.
	if rate_hz <= 30.0:
		var endpoint_force := _force_value(
			8.0, contact_duration_sec, max_time_sec - contact_start_sec
		)
		var endpoint := _force_point(
			plot, max_time_sec, endpoint_force, max_time_sec, max_force_n
		)
		draw_circle(endpoint, 5.5, Color(colors["text"], 0.88 * alpha))
		draw_line(Vector2(endpoint.x, plot.end.y), endpoint, Color(colors["text"], 0.10 * alpha), 1.0, true)


func _draw_impact_sampling_miss(cold_open: bool) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := _beat_progress()
	var plot := Rect2(190, 210, 1540, 570) if cold_open else Rect2(230, 230, 1460, 560)
	_draw_force_axes(plot, 33.0, 1700.0, 0.76)
	if not cold_open:
		var gap_reveal := smoothstep(0.18, 0.42, p)
		var gap_left := _force_point(plot, 0.012, 0.0, 0.033, 1700.0).x
		var gap_right := _force_point(plot, 0.020, 0.0, 0.033, 1700.0).x
		draw_rect(Rect2(gap_left, plot.position.y, gap_right - gap_left, plot.size.y), Color(colors["accent"], 0.055 * gap_reveal), true)
		draw_line(Vector2(gap_left, plot.position.y), Vector2(gap_left, plot.end.y), Color(colors["accent"], 0.32 * gap_reveal), 2.0, true)
		draw_line(Vector2(gap_right, plot.position.y), Vector2(gap_right, plot.end.y), Color(colors["accent"], 0.32 * gap_reveal), 2.0, true)
	_draw_force_profile(plot, 8.0, 0.008, 0.033, 1700.0, colors_by_id["hard"], smoothstep(0.12, 0.42, p) if cold_open else 1.0, 0.12, 0.012)
	var endpoint_reveal := 1.0 if cold_open else smoothstep(0.06, 0.24, p)
	var endpoint_radius := 8.0 if cold_open else lerpf(5.5, 8.0, endpoint_reveal)
	for time_sec in [0.0, 0.033]:
		var point := _force_point(plot, time_sec, 0.0, 0.033, 1700.0)
		draw_circle(point, endpoint_radius, Color(colors["text"], 0.96))
		draw_string(VideoTypography.data(), point + Vector2(-42, -22), "0 N", HORIZONTAL_ALIGNMENT_CENTER, 84, 27, Color(colors["text"], 0.90 * endpoint_reveal))
	if not cold_open:
		var source_copy_alpha := 1.0 - smoothstep(0.04, 0.24, p)
		draw_string(VideoTypography.bold(), Vector2(430, 860), "采样 30 Hz", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(colors["text"], 0.94 * source_copy_alpha))
		draw_string(VideoTypography.data(), Vector2(1080, 860), "采样峰值  0 N", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(colors["accent"], 0.96 * source_copy_alpha))
	var peak_position := _force_point(plot, 0.016, float(_impact_metrics("hard")["peak_force_n"]), 0.033, 1700.0)
	var peak_alpha := smoothstep(0.42, 0.68, p)
	draw_circle(peak_position, 7.0, Color(colors["accent"], peak_alpha))
	draw_string(VideoTypography.data(), peak_position + Vector2(18, -18), "1570 N", HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color(colors["accent"], peak_alpha))
	var copy := "参考曲线峰值，落在两个采样时刻之间" if cold_open else "接触过程没变，采样点错过了峰值"
	draw_string(VideoTypography.bold(), Vector2(470, 895), copy, HORIZONTAL_ALIGNMENT_CENTER, 980, 39, Color(colors["text"], smoothstep(0.58, 0.82, p)))


func _hook_elapsed() -> float:
	return maxf(0.0, video_time_sec - float(current_beat.get("at", video_time_sec)))


func _draw_hook_collision_stage(stage: Rect2, progress: float, scanlines: bool = false) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := clampf(progress, 0.0, 1.0)
	draw_rect(stage, Color(colors["surface"], 0.72), true)
	draw_rect(stage, Color(colors["divider"], 0.52), false, 2.0)
	var wall_x := stage.end.x - 105.0
	var center_y := stage.get_center().y
	var approach := smoothstep(0.02, 0.50, p)
	var rebound := smoothstep(0.64, 0.98, p)
	var contact := 0.0
	if p >= 0.48 and p <= 0.68:
		contact = sin(inverse_lerp(0.48, 0.68, p) * PI)
	var ball_x := lerpf(stage.position.x + 105.0, wall_x - 48.0, approach)
	ball_x += contact * 7.0 - rebound * 145.0
	_draw_wall(wall_x, stage.position.y + 65.0, stage.end.y - 65.0, false, contact)
	_draw_deformed_impact_ball(
		Vector2(ball_x, center_y), colors_by_id["hard"], 48.0, contact * 0.34
	)
	if contact > 0.02:
		for ring_index in range(3):
			var ring_progress := clampf(contact - ring_index * 0.14, 0.0, 1.0)
			draw_arc(
				Vector2(wall_x - 8.0, center_y),
				36.0 + ring_index * 34.0 + 28.0 * ring_progress,
				-PI * 0.5, PI * 0.5, 28,
				Color(colors["accent"], 0.46 * ring_progress), 4.0, true
			)
	if scanlines:
		for y in range(int(stage.position.y + 8.0), int(stage.end.y), 14):
			draw_line(
				Vector2(stage.position.x, y), Vector2(stage.end.x, y),
				Color(colors["background"], 0.20), 1.0
			)


func _draw_fivefold_collision(
	stage: Rect2,
	progress: float,
	soft: bool,
	label: String,
	peak_force_n: float,
	alpha: float = 1.0
) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := clampf(progress, 0.0, 1.0)
	var wall_x := stage.end.x - 155.0
	var center_y := stage.get_center().y + 10.0
	var impact_start := 0.52
	var contact_end := 0.78 if soft else 0.66
	var approach := smoothstep(0.02, impact_start, p)
	var rebound := smoothstep(contact_end, 0.98, p)
	var compression := 0.0
	if p >= impact_start and p <= contact_end:
		compression = sin(inverse_lerp(impact_start, contact_end, p) * PI)
	var start_x := stage.position.x + 145.0
	var contact_x := wall_x - 62.0
	var penetration := 42.0 * compression if soft else 5.0 * compression
	var ball_x := lerpf(start_x, contact_x, approach) + penetration
	ball_x -= rebound * (135.0 if soft else 205.0)
	var shake := Vector2.ZERO
	if not soft and compression > 0.04:
		shake = Vector2(sin(p * 311.0), cos(p * 257.0)) * 9.0 * compression
	draw_set_transform(shake)
	draw_rect(stage, Color(colors["surface"], 0.70 * alpha), true)
	draw_rect(stage, Color(colors["divider"], 0.50 * alpha), false, 2.0)
	for trail_index in range(5, 0, -1):
		var trail_offset := 22.0 * float(trail_index) * (1.0 - rebound)
		draw_circle(
			Vector2(ball_x - trail_offset, center_y),
			50.0 - float(trail_index) * 4.5,
			Color(colors_by_id["soft" if soft else "hard"], 0.025 * float(6 - trail_index) * alpha)
		)
	_draw_wall(wall_x, stage.position.y + 64.0, stage.end.y - 64.0, soft, compression)
	_draw_deformed_impact_ball(
		Vector2(ball_x, center_y),
		colors_by_id["soft" if soft else "hard"],
		62.0,
		compression * (0.60 if soft else 0.42)
	)
	if compression > 0.02:
		var impact_color: Color = colors_by_id["soft" if soft else "hard"]
		for ring_index in range(3):
			var ring_radius := 55.0 + ring_index * 44.0 + compression * 28.0
			draw_arc(
				Vector2(wall_x - 6.0, center_y), ring_radius,
				-PI * 0.48, PI * 0.48, 32,
				Color(impact_color, (0.34 if soft else 0.62) * compression * alpha),
				4.0 if soft else 7.0, true
			)
	draw_set_transform(Vector2.ZERO)
	draw_string(
		VideoTypography.bold(), stage.position + Vector2(40, 66), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(colors["text"], 0.90 * alpha)
	)
	var number_reveal := smoothstep(impact_start - 0.02, impact_start + 0.09, p)
	var number_scale := 1.0 + 0.18 * sin(clampf(number_reveal, 0.0, 1.0) * PI)
	draw_set_transform(stage.position + Vector2(48, 170), 0.0, Vector2.ONE * number_scale)
	draw_string(
		VideoTypography.bold(), Vector2.ZERO,
		"%.0f N" % peak_force_n,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 72,
		Color(colors_by_id["soft" if soft else "hard"], number_reveal * alpha)
	)
	draw_set_transform(Vector2.ZERO)


func _draw_hook_fivefold() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	# The complete hook occupies the 14-second cold-open beat. Keeping one
	# local choreography clock makes the collision timing easy to preview at
	# half length while allowing the spoken conditions to breathe in episode.
	var t := _hook_elapsed() * 0.5
	var full_stage := Rect2(145, 145, 1630, 720)
	if t < 1.18:
		_draw_fivefold_collision(full_stage, t / 1.08, false, "钢板", 1570.0)
		draw_string(VideoTypography.data(), Vector2(610, 930), "同一颗球  ·  m = 1 kg", HORIZONTAL_ALIGNMENT_CENTER, 700, 30, Color(colors["text"], 0.90))
		var flash := smoothstep(0.53, 0.57, t / 1.08) * (1.0 - smoothstep(0.57, 0.66, t / 1.08))
		draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)), Color(colors["text"], 0.14 * flash), true)
		return
	if t < 2.42:
		var soft_t := (t - 1.18) / 1.12
		_draw_fivefold_collision(full_stage, soft_t, true, "软垫", 314.0)
		draw_string(VideoTypography.data(), Vector2(490, 930), "同一质量  ·  撞前 5 m/s  ·  反弹 3 m/s", HORIZONTAL_ALIGNMENT_CENTER, 940, 30, Color(colors["text"], 0.90))
		return

	var compare_reveal := smoothstep(2.42, 2.75, t)
	var stage_exit := smoothstep(4.55, 5.15, t)
	var left_stage := Rect2(90 - 1040.0 * stage_exit, 205, 820, 500)
	var right_stage := Rect2(1010 + 1040.0 * stage_exit, 205, 820, 500)
	if stage_exit < 0.995:
		_draw_fivefold_collision(left_stage, 0.59, false, "钢板", 1570.0, compare_reveal)
		_draw_fivefold_collision(right_stage, 0.65, true, "软垫", 314.0, compare_reveal)
	var first_line := smoothstep(2.68, 3.05, t) * (1.0 - smoothstep(4.55, 4.95, t))
	draw_string(
		VideoTypography.data(), Vector2(410, 120), "m = 1 kg  ·  撞前 5 m/s  ·  反弹 3 m/s",
		HORIZONTAL_ALIGNMENT_CENTER, 1100, 40, Color(colors["text"], first_line)
	)
	var second_line := smoothstep(3.28, 3.72, t) * (1.0 - smoothstep(4.55, 4.95, t))
	draw_string(
		VideoTypography.bold(), Vector2(390, 820), "钢板工况的接触力峰值，是软垫工况的五倍",
		HORIZONTAL_ALIGNMENT_CENTER, 1140, 52, Color(colors["text"], second_line)
	)

	var curve_reveal := smoothstep(4.70, 5.45, t)
	if curve_reveal > 0.001:
		var plot := Rect2(300, 235, 1320, 500)
		_draw_force_axes(plot, 45.0, 1700.0, curve_reveal)
		_draw_force_profile(
			plot, 8.0, 0.008, 0.045, 1700.0,
			colors_by_id["hard"], curve_reveal, 0.18 * curve_reveal
		)
		_draw_force_profile(
			plot, 8.0, 0.040, 0.045, 1700.0,
			colors_by_id["soft"], curve_reveal, 0.15 * curve_reveal
		)
		var hard_peak := _force_point(plot, 0.004, 1570.0, 0.045, 1700.0)
		var soft_peak := _force_point(plot, 0.020, 314.0, 0.045, 1700.0)
		draw_string(
			VideoTypography.data(), hard_peak + Vector2(24, -12), "1570 N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color(colors_by_id["hard"], curve_reveal)
		)
		draw_string(
			VideoTypography.data(), soft_peak + Vector2(24, -12), "314 N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color(colors_by_id["soft"], curve_reveal)
		)
	var payoff := smoothstep(5.55, 6.15, t)
	draw_string(
		VideoTypography.bold(), Vector2(560, 900), "这五倍，究竟差在哪儿？",
		HORIZONTAL_ALIGNMENT_CENTER, 800, 52, Color(colors["text"], payoff)
	)


func _draw_hook_time_gap() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var t := _hook_elapsed()
	if t < 1.25:
		_draw_hook_collision_stage(Rect2(250, 185, 1420, 650), t / 1.25)
		draw_string(
			VideoTypography.bold(), Vector2(510, 930), "一次碰撞，只持续 8 ms",
			HORIZONTAL_ALIGNMENT_CENTER, 900, 42, Color(colors["text"], 0.96)
		)
		return
	var frame_reveal := smoothstep(1.25, 1.75, t)
	var dive := smoothstep(2.55, 3.55, t)
	var left_frame := Rect2(95.0 - 220.0 * dive, 210, 735, 500)
	var right_frame := Rect2(1090.0 + 220.0 * dive, 210, 735, 500)
	for frame_data in [
		{"rect": left_frame, "label": "第 1 帧", "ball_x": 0.66},
		{"rect": right_frame, "label": "第 2 帧", "ball_x": 0.34},
	]:
		var frame: Rect2 = frame_data["rect"]
		draw_rect(frame, Color(colors["surface"], 0.72 * frame_reveal), true)
		draw_rect(frame, Color(colors["divider"], 0.58 * frame_reveal), false, 3.0)
		var wall_x := frame.position.x + frame.size.x * 0.76
		_draw_wall(wall_x, frame.position.y + 95, frame.end.y - 70, false)
		_draw_impact_ball(
			Vector2(frame.position.x + frame.size.x * float(frame_data["ball_x"]), frame.get_center().y),
			colors_by_id["hard"], 38.0
		)
		draw_string(
			VideoTypography.data(), frame.position + Vector2(24, 48), String(frame_data["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(colors["muted"], frame_reveal)
		)
	var gap_alpha := smoothstep(2.10, 3.20, t)
	draw_rect(Rect2(835, 175, 250, 570), Color(colors["accent"], 0.035 * gap_alpha), true)
	draw_line(Vector2(850, 175), Vector2(850, 745), Color(colors["accent"], 0.62 * gap_alpha), 3.0)
	draw_line(Vector2(1070, 175), Vector2(1070, 745), Color(colors["accent"], 0.62 * gap_alpha), 3.0)
	draw_string(
		VideoTypography.bold(), Vector2(760, 125), "相邻采样时刻间隔  33 ms",
		HORIZONTAL_ALIGNMENT_CENTER, 400, 36, Color(colors["text"], gap_alpha)
	)
	var plot := Rect2(310, 250, 1300, 480)
	var curve_alpha := smoothstep(3.20, 4.55, t)
	if curve_alpha > 0.001:
		_draw_force_axes(plot, 33.0, 1700.0, curve_alpha)
		_draw_force_profile(
			plot, 8.0, 0.008, 0.033, 1700.0,
			Color(colors["accent"], curve_alpha), curve_alpha, 0.18 * curve_alpha, 0.012
		)
		var peak := _force_point(plot, 0.016, 1570.0, 0.033, 1700.0)
		draw_circle(peak, 8.0, Color(colors["accent"], curve_alpha))
		draw_string(
			VideoTypography.data(), peak + Vector2(20, -18), "1570 N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(colors["accent"], curve_alpha)
		)
	var payoff := smoothstep(4.65, 5.45, t)
	draw_string(
		VideoTypography.bold(), Vector2(470, 885), "完整接触过程，可能落在两个采样时刻之间",
		HORIZONTAL_ALIGNMENT_CENTER, 980, 44, Color(colors["text"], payoff)
	)


func _draw_hook_system_error() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var t := _hook_elapsed()
	var shell := Rect2(85, 115, 1750, 790)
	draw_rect(shell, Color(colors["surface"], 0.76), true)
	draw_rect(shell, Color(colors["divider"], 0.62), false, 3.0)
	draw_string(VideoTypography.data(), Vector2(125, 165), "IMPACT LAB / LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(colors["muted"], 0.90))
	var collision_progress := clampf(t / 1.35, 0.0, 1.0)
	_draw_hook_collision_stage(Rect2(125, 210, 760, 520), collision_progress, true)
	var plot := Rect2(1035, 260, 680, 400)
	_draw_force_axes(plot, 33.0, 1700.0, 0.72)
	var stage_index := clampi(int(maxf(0.0, t - 2.20) / 0.82), 0, 3)
	var rates := [30.0, 100.0, 1000.0, 10000.0]
	var rate: float = rates[stage_index]
	var scan_progress := smoothstep(1.75, 5.55, t)
	if scan_progress > 0.001:
		_draw_force_profile(plot, 8.0, 0.008, 0.033, 1700.0, colors_by_id["hard"], scan_progress, 0.10, 0.012)
		_draw_sampling_points(plot, rate, 0.012, 0.008, 0.033, 1700.0)
	var error_alpha := smoothstep(1.05, 1.35, t) * (1.0 - smoothstep(4.85, 5.35, t))
	draw_string(
		VideoTypography.data(), Vector2(1080, 190), "PEAK FORCE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(colors["muted"], 0.86)
	)
	draw_string(
		VideoTypography.bold(), Vector2(1080, 785), "0 N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color("#FF5A5F", error_alpha)
	)
	draw_string(
		VideoTypography.data(), Vector2(1275, 785), "DATA / VIDEO CONFLICT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("#FF5A5F", error_alpha * (0.55 + 0.45 * sin(t * 10.0)))
	)
	var solved := smoothstep(5.05, 5.65, t)
	draw_string(
		VideoTypography.bold(), Vector2(1080, 785), "1570 N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color(colors["accent"], solved)
	)
	draw_string(
		VideoTypography.data(), Vector2(1275, 785), "SAMPLE RATE  %.0f Hz" % rate,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(colors["highlight"], 0.92 * scan_progress)
	)
	draw_string(
		VideoTypography.bold(), Vector2(390, 845),
		"画面撞上了，数据为什么是 0 N？" if solved < 0.5 else "测得足够快，尖峰才会出现",
		HORIZONTAL_ALIGNMENT_CENTER, 1140, 42, Color(colors["text"], 0.96)
	)


func _draw_hook_curve_transform() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var t := _hook_elapsed()
	var morph := smoothstep(1.15, 5.40, t)
	var duration := lerpf(0.008, 0.040, morph)
	var peak := PI * 8.0 / (2.0 * duration)
	var plot := Rect2(250, 220, 1420, 550)
	_draw_force_axes(plot, 45.0, 1700.0)
	_draw_force_profile(plot, 8.0, duration, 0.045, 1700.0, colors["accent"], 1.0, 0.24)
	var left_x := plot.position.x
	var right_x := plot.position.x + plot.size.x * duration / 0.045
	for clamp_x in [left_x, right_x]:
		draw_rect(Rect2(float(clamp_x) - 18, plot.end.y - 48, 36, 96), Color(colors["text"], 0.78), true)
		draw_rect(Rect2(float(clamp_x) - 28, plot.end.y - 62, 56, 18), Color(colors["accent"], 0.82), true)
	var handle_y := 845.0
	draw_line(Vector2(left_x, plot.end.y + 18), Vector2(left_x, handle_y - 28), Color(colors["divider"], 0.54), 2.0)
	draw_line(Vector2(right_x, plot.end.y + 18), Vector2(right_x, handle_y - 28), Color(colors["divider"], 0.54), 2.0)
	draw_string(
		VideoTypography.data(), Vector2(280, 875), "接触时间  %.0f ms" % (duration * 1000.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(colors["text"], 0.94)
	)
	draw_string(
		VideoTypography.data(), Vector2(1170, 875), "峰值  %.0f N" % peak,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(colors["accent"], 0.96)
	)
	draw_string(
		VideoTypography.bold(), Vector2(610, 130), "法向冲量不变，作用时程拉宽五倍",
		HORIZONTAL_ALIGNMENT_CENTER, 700, 44, Color(colors["text"], smoothstep(0.20, 0.85, t))
	)
	var area_alpha := 0.72 + 0.28 * sin(t * 4.0)
	draw_string(
		VideoTypography.bold(), Vector2(680, 875), "法向冲量始终是 8 N·s",
		HORIZONTAL_ALIGNMENT_CENTER, 560, 37, Color(colors["highlight"], area_alpha)
	)
	var payoff := smoothstep(5.50, 6.30, t)
	draw_string(
		VideoTypography.bold(), Vector2(560, 965), "时间变长，接触力峰值下降",
		HORIZONTAL_ALIGNMENT_CENTER, 800, 42, Color(colors["text"], payoff)
	)


func _draw_hook_forensics() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var t := _hook_elapsed()
	var monitor := Rect2(120, 125, 1680, 760)
	draw_rect(monitor, Color("#07100D", 0.88), true)
	draw_rect(monitor, Color(colors["divider"], 0.68), false, 4.0)
	draw_circle(Vector2(165, 165), 7.0, Color("#FF4D4D", 0.90))
	draw_string(VideoTypography.data(), Vector2(185, 174), "REC  CAM-03", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(colors["text"], 0.84))
	draw_string(VideoTypography.data(), Vector2(1450, 174), "30 FPS  /  00:00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(colors["muted"], 0.84))
	if t < 1.35:
		_draw_hook_collision_stage(Rect2(200, 220, 1520, 540), t / 1.35, true)
	else:
		var reveal := smoothstep(1.35, 1.85, t)
		var card_a := Rect2(220, 250, 600, 400)
		var card_b := Rect2(1100, 250, 600, 400)
		for card_data in [
			{"rect": card_a, "name": "证据 A / 碰撞前", "ball": 0.58},
			{"rect": card_b, "name": "证据 B / 碰撞后", "ball": 0.34},
		]:
			var card: Rect2 = card_data["rect"]
			draw_rect(card, Color(colors["surface"], 0.72 * reveal), true)
			draw_rect(card, Color(colors["text"], 0.30 * reveal), false, 2.0)
			var wall_x := card.end.x - 110.0
			_draw_wall(wall_x, card.position.y + 90, card.end.y - 55, false)
			_draw_impact_ball(Vector2(card.position.x + card.size.x * float(card_data["ball"]), card.get_center().y), colors_by_id["hard"], 36.0)
			draw_string(VideoTypography.data(), card.position + Vector2(24, 44), String(card_data["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(colors["text"], reveal))
		var rail := Rect2(330, 725, 1260, 4)
		draw_rect(rail, Color(colors["divider"], 0.66), true)
		draw_circle(Vector2(420, 727), 8.0, Color(colors["text"], 0.92))
		draw_circle(Vector2(1500, 727), 8.0, Color(colors["text"], 0.92))
		draw_string(VideoTypography.data(), Vector2(780, 785), "两张证据相隔 33 ms", HORIZONTAL_ALIGNMENT_CENTER, 360, 28, Color(colors["muted"], 0.90))
		var search := smoothstep(2.25, 4.10, t)
		var lens_center := Vector2(lerpf(650.0, 1270.0, search), 500)
		var lens_alpha := smoothstep(2.0, 2.35, t)
		draw_circle(lens_center, 126.0, Color(colors["background"], 0.82 * lens_alpha))
		draw_arc(lens_center, 126.0, 0, TAU, 64, Color(colors["accent"], 0.92 * lens_alpha), 7.0, true)
		draw_line(lens_center + Vector2(86, 92), lens_center + Vector2(185, 195), Color(colors["accent"], 0.82 * lens_alpha), 14.0, true)
		if search > 0.38:
			var micro := smoothstep(0.38, 0.68, search)
			_draw_deformed_impact_ball(lens_center - Vector2(18, 0), colors_by_id["hard"], 38.0, 0.28 * micro)
			draw_line(lens_center + Vector2(26, -72), lens_center + Vector2(26, 72), Color(colors["text"], 0.72 * micro), 7.0, true)
		var found := smoothstep(4.20, 4.85, t)
		draw_string(VideoTypography.bold(), Vector2(590, 220), "碰撞找到了：8 ms / 1570 N", HORIZONTAL_ALIGNMENT_CENTER, 740, 46, Color(colors["accent"], found))
		draw_rect(Rect2(690, 820, 540, 82), Color(colors["accent"], 0.10 * found), true)
		draw_rect(Rect2(690, 820, 540, 82), Color(colors["accent"], 0.82 * found), false, 4.0)
		draw_string(VideoTypography.bold(), Vector2(710, 875), "EVIDENCE FOUND", HORIZONTAL_ALIGNMENT_CENTER, 500, 39, Color(colors["accent"], found))
	for y in range(140, 875, 12):
		draw_line(Vector2(120, y), Vector2(1800, y), Color("#000000", 0.10), 1.0)


func _draw_curve_slingshot_stinger() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := _beat_progress()
	var accent: Color = colors["accent"]
	var center := Vector2(960, 470)
	var morph := smoothstep(0.05, 0.46, p)
	var launch := smoothstep(0.48, 0.76, p)
	var fork_alpha := smoothstep(0.16, 0.40, p) * (1.0 - smoothstep(0.88, 1.0, p))
	var fork_base := center + Vector2(-170, 205)
	var fork_left := center + Vector2(-300, -165)
	var fork_right := center + Vector2(30, -165)
	draw_line(fork_base, fork_left, Color(colors["text"], 0.82 * fork_alpha), 18.0, true)
	draw_line(fork_base, fork_right, Color(colors["text"], 0.82 * fork_alpha), 18.0, true)
	var pocket := center + Vector2(-500 + 330 * launch, -5)
	draw_line(fork_left, pocket, Color(accent, 0.96 * fork_alpha), 8.0, true)
	draw_line(fork_right, pocket, Color(accent, 0.96 * fork_alpha), 8.0, true)
	var ball_position := pocket
	if launch > 0.001:
		ball_position = pocket.lerp(center + Vector2(440, -25), launch)
		for trail_index in range(1, 4):
			var trail_position := pocket.lerp(center + Vector2(440, -25), clampf(launch - trail_index * 0.08, 0.0, 1.0))
			draw_circle(trail_position, 22.0 - trail_index * 4.0, Color(accent, 0.16 - trail_index * 0.035))
	draw_circle(ball_position, 25, Color(accent, 0.98))
	if launch > 0.25:
		var ring := smoothstep(0.30, 0.72, launch)
		draw_arc(center + Vector2(440, -25), lerpf(12, 145, ring), 0, TAU, 54, Color(accent, 0.68 * (1.0 - ring)), 5.0, true)
	var brand_alpha := smoothstep(0.48, 0.72, p)
	draw_string(VideoTypography.bold(), Vector2(560, 770), "物理实验室", HORIZONTAL_ALIGNMENT_CENTER, 800, 54, Color(colors["text"], brand_alpha))
	draw_string(VideoTypography.data(), Vector2(660, 830), "SLINGSHOT PHYSICS", HORIZONTAL_ALIGNMENT_CENTER, 600, 29, Color(colors["muted"], brand_alpha * 0.90))
	if morph < 1.0:
		var ghost_plot := Rect2(630, 360, 660, 280)
		_draw_force_profile(ghost_plot, 8.0, 0.008, 0.040, 1700, accent, 1.0 - morph, 0.05)


func _draw_impact_title_field() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := _beat_progress()
	var title_reveal := smoothstep(0.05, 0.42, p)
	draw_string(
		VideoTypography.bold(), Vector2(360, 500), "接触力峰值为什么不是固定值？",
		HORIZONTAL_ALIGNMENT_CENTER, 1200, 66,
		Color(colors["text"], title_reveal)
	)
	var y := 620.0
	draw_line(Vector2(650, y), Vector2(1270, y), Color(colors["accent"], smoothstep(0.20, 0.65, p)), 4.0, true)
	for index in range(5):
		var ratio := float(index) / 4.0
		draw_circle(Vector2(650 + 620 * ratio, y), 4.0, Color(colors["accent"], 0.76 * smoothstep(0.28 + index * 0.05, 0.68 + index * 0.05, p)))


func _draw_damage_boundary() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := _beat_progress()
	var press := smoothstep(0.10, 0.42, p)
	var spread := smoothstep(0.36, 0.72, p)
	var panels := [Rect2(150, 240, 730, 520), Rect2(1040, 240, 730, 520)]
	for panel in panels:
		draw_rect(panel, Color(colors["surface"], 0.78), true)
		draw_rect(panel, Color(colors["divider"], 0.42), false, 2.0)
	draw_string(VideoTypography.data(), Vector2(250, 300), "相同总力 F", HORIZONTAL_ALIGNMENT_CENTER, 530, 30, Color(colors["accent"], 0.90))
	draw_string(VideoTypography.data(), Vector2(1140, 300), "相同总力 F", HORIZONTAL_ALIGNMENT_CENTER, 530, 30, Color(colors["accent"], 0.90))
	for index in range(7):
		var x := 335.0 + float(index) * 60.0
		_draw_arrow(Vector2(x, 345 + 26.0 * press), Vector2(x, 455 + 18.0 * press), Color(colors["accent"], 0.72), 3.5)
	_draw_arrow(Vector2(1405, 345 + 26.0 * press), Vector2(1405, 455 + 18.0 * press), Color(colors["accent"], 0.98), 7.0)
	draw_rect(Rect2(300, 470, 430, 65), Color(colors["highlight"], 0.30), true)
	draw_rect(Rect2(1390, 470, 30, 65), Color(colors["highlight"], 0.82), true)
	draw_rect(Rect2(260, 535, 510, 90), Color(colors["muted"], 0.18), true)
	draw_rect(Rect2(1150, 535, 510, 90), Color(colors["muted"], 0.18), true)
	for radius in [44.0, 72.0, 104.0]:
		draw_arc(Vector2(1405, 535), radius + spread * 12.0, PI, TAU, 32, Color(colors["accent"], spread * 0.24 / (radius / 44.0)), 3.0, true)
	for radius in [70.0, 140.0, 210.0]:
		draw_arc(Vector2(515, 535), radius * spread, PI, TAU, 32, Color(colors["highlight"], 0.12 * spread), 4.0, true)
	draw_string(VideoTypography.data(), Vector2(300, 580), "接触面积 A 大", HORIZONTAL_ALIGNMENT_CENTER, 430, 28, Color(colors["highlight"], 0.90))
	draw_string(VideoTypography.data(), Vector2(1190, 580), "接触面积 A 小", HORIZONTAL_ALIGNMENT_CENTER, 430, 28, Color(colors["accent"], 0.96))
	draw_string(VideoTypography.medium(), Vector2(150, 700), "相同的力 · 分布在较大面积", HORIZONTAL_ALIGNMENT_CENTER, 730, 30, Color(colors["text"], 0.90))
	draw_string(VideoTypography.medium(), Vector2(1040, 700), "相同的力 · 集中在很小面积", HORIZONTAL_ALIGNMENT_CENTER, 730, 30, Color(colors["text"], 0.90))
	draw_string(VideoTypography.bold(), Vector2(540, 835), "接触力峰值不能单独决定破坏", HORIZONTAL_ALIGNMENT_CENTER, 840, 39, Color(colors["accent"], 0.94))


func _draw_impact_takeaway() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := _beat_progress()
	var plot := Rect2(260, 230, 1400, 560)
	_draw_force_axes(plot, 45, 1700)
	var hard_reveal := smoothstep(0.03, 0.24, p)
	var morph := smoothstep(0.28, 0.70, p)
	var final_reveal := smoothstep(0.72, 0.90, p)
	var morph_duration := lerpf(0.008, 0.040, morph)
	var morph_color: Color = colors_by_id["hard"].lerp(colors_by_id["soft"], morph)
	_draw_force_profile(plot, 8.0, morph_duration, 0.045, 1700, morph_color, hard_reveal, 0.18)
	if final_reveal > 0.001:
		_draw_force_profile(plot, 8.0, 0.008, 0.045, 1700, colors_by_id["hard"], final_reveal, 0.08)
		_draw_force_profile(plot, 8.0, 0.040, 0.045, 1700, colors_by_id["soft"], final_reveal, 0.08)
	draw_string(VideoTypography.data(), Vector2(850, 300), "钢板工况  8 ms  ·  1570 N", HORIZONTAL_ALIGNMENT_LEFT, -1, 29, Color(colors_by_id["hard"], maxf(hard_reveal * (1.0 - morph), final_reveal)))
	draw_string(VideoTypography.data(), Vector2(1000, 640), "软垫工况  40 ms  ·  314 N", HORIZONTAL_ALIGNMENT_LEFT, -1, 29, Color(colors_by_id["soft"], maxf(morph, final_reveal)))
	draw_string(VideoTypography.bold(), Vector2(530, 895), "法向冲量相同 · 接触力峰值不同", HORIZONTAL_ALIGNMENT_CENTER, 860, 42, Color(colors["text"], final_reveal))


func _draw_explanation_module() -> void:
	if explanation_module != null:
		explanation_module.draw(self)


func _handoff_kind() -> String:
	return String(current_beat.get("handoff", ""))


func _handoff_progress() -> float:
	return ShotCamera.transition_eased_progress(current_beat, video_time_sec)


func _is_question_to_explanation_handoff() -> bool:
	return _handoff_kind() == "trajectory-to-model" and _handoff_progress() < 1.0


func _is_explanation_to_controls_handoff() -> bool:
	return _handoff_kind() == "formula-to-controls" and _handoff_progress() < 1.0


func _is_chart_handoff() -> bool:
	return _handoff_kind() == "chart-to-trajectories" and _handoff_progress() < 1.0


func _draw_question_handoff() -> void:
	var opacity := 1.0 - _handoff_progress()
	_draw_teaser_subject("angle-45", "45°", 0, opacity, 1.0)
	_draw_teaser_subject("angle-40", "空气中更远", 1, opacity * 0.88, 1.0)


func _draw_explanation_handoff() -> void:
	if explanation_module == null:
		return
	var opacity := 1.0 - _handoff_progress()
	var previous := _previous_beat(current_beat)
	if previous.is_empty():
		return
	var active := current_beat
	current_beat = previous
	explanation_module.draw(self, opacity)
	current_beat = active


func _draw_control_origin_bridge() -> void:
	var progress := _handoff_progress()
	var colors: Dictionary = episode["theme"]["colors"]
	var accent := Color(colors["accent"])
	var origin := _map_point(launch_position_px)
	var pulse_progress := clampf((progress - 0.18) / 0.62, 0.0, 1.0)
	var pulse_alpha := sin(pulse_progress * PI) * 0.42
	if pulse_alpha > 0.001:
		draw_arc(
			origin,
			lerpf(8.0, 56.0, pulse_progress),
			0.0,
			TAU,
			48,
			Color(accent, pulse_alpha),
			VisualLanguage.STROKE_CONTEXT,
			true
		)
	var vector_progress := smoothstep(0.34, 0.88, progress)
	if vector_progress <= 0.001:
		return
	var focus_variant := _variant_for_id(String(current_beat.get("focus", "angle-40")))
	if focus_variant.is_empty():
		var variants: Array = episode.get("variants", [])
		if variants.is_empty():
			return
		focus_variant = variants[0]
	var physics: Dictionary = focus_variant["preset"]["physics"]
	var angle := deg_to_rad(float(physics["launch_angle_deg"]))
	var direction := Vector2(cos(angle), -sin(angle))
	var vector_end := origin + direction * lerpf(0.0, 118.0, vector_progress)
	_draw_arrow(
		origin,
		vector_end,
		Color(accent, 0.72 * vector_progress),
		VisualLanguage.STROKE_SECONDARY
	)
	var component_color := Color(colors["muted"], 0.48 * vector_progress)
	draw_line(
		origin,
		Vector2(vector_end.x, origin.y),
		component_color,
		VisualLanguage.STROKE_CONTEXT,
		true
	)
	draw_line(
		Vector2(vector_end.x, origin.y),
		vector_end,
		component_color,
		VisualLanguage.STROKE_CONTEXT,
		true
	)
	draw_circle(origin, lerpf(3.0, 6.0, vector_progress), Color(accent, 0.86 * vector_progress))


func _draw_previous_chart_handoff() -> void:
	var opacity := 1.0 - _handoff_progress()
	var previous := _previous_beat(current_beat)
	if previous.is_empty():
		return
	var active := current_beat
	current_beat = previous
	_draw_range_curve(opacity, false)
	current_beat = active


func _draw_previous_landing_handoff() -> void:
	var progress := _handoff_progress()
	var previous := _previous_beat(current_beat)
	if previous.is_empty():
		return
	var active_beat := current_beat
	var active_phase := phase
	var active_camera := camera_state
	current_beat = previous
	phase = "FLIGHT"
	camera_state = ShotCamera.desired_state(
		phase,
		previous,
		_camera_anchor_for_beat(previous)
	)
	_draw_background()
	_draw_sling()
	_draw_trajectories()
	_draw_variant_birds()
	_draw_event_effects()
	_draw_landing_magnifier()
	current_beat = active_beat
	phase = active_phase
	camera_state = active_camera
	var fade := smoothstep(0.16, 0.82, progress)
	draw_rect(
		Rect2(Vector2.ZERO, EpisodeLayout.CANVAS_SIZE),
		Color(episode["theme"]["colors"]["background"], fade),
		true
	)


func _draw_chart_to_trajectory_bridge() -> void:
	var progress := _handoff_progress()
	if progress <= 0.02:
		return
	var scans: Array = []
	for scan_value in bundle.get("range_scans", []):
		var scan: Dictionary = scan_value
		if String(scan.get("id", "")) in ["air", "higher-ballistic-coefficient"]:
			scans.append(scan)
	if scans.is_empty():
		return
	var min_angle := INF
	var max_angle := -INF
	var max_range := 0.0
	for scan_value in scans:
		var scan: Dictionary = scan_value
		for point_value in scan.get("points", []):
			var point: Dictionary = point_value
			min_angle = minf(min_angle, float(point["angle_deg"]))
			max_angle = maxf(max_angle, float(point["angle_deg"]))
			max_range = maxf(max_range, float(point["range_m"]))
	if not is_finite(min_angle) or max_angle <= min_angle or max_range <= 0.0:
		return
	var air_scan: Dictionary = {}
	for scan_value in scans:
		var scan: Dictionary = scan_value
		if String(scan.get("id", "")) == "air":
			air_scan = scan
			break
	if air_scan.is_empty():
		return
	var plot := Rect2(238, 170, 1444, 650)
	var ids := [
		String(current_beat.get("focus", "")),
		String(current_beat.get("focus_secondary", "")),
	]
	for id in ids:
		var variant := _variant_for_id(id)
		var trajectory: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
		if variant.is_empty() or trajectory.is_empty():
			continue
		var angle := float(variant["preset"]["physics"]["launch_angle_deg"])
		var point := _scan_point_for_angle(air_scan.get("points", []), angle)
		if point.is_empty():
			continue
		var source := _range_curve_point(point, plot, min_angle, max_angle, max_range)
		var target := _map_point(_trajectory_apex(trajectory))
		var control := source.lerp(target, 0.46) + Vector2(0, -96)
		var color: Color = colors_by_id.get(id, episode["theme"]["colors"]["accent"])
		var travel_progress := smoothstep(0.08, 0.88, progress)
		for trail_index in range(5, 0, -1):
			var trail_progress := maxf(0.0, travel_progress - float(trail_index) * 0.035)
			if trail_progress <= 0.0:
				continue
			var trail_position := _quadratic_bezier(source, control, target, trail_progress)
			var trail_alpha := 0.08 * (1.0 - float(trail_index) / 6.0)
			draw_circle(trail_position, 4.0, Color(color, trail_alpha))
		var position := _quadratic_bezier(source, control, target, travel_progress)
		var source_alpha := 0.28 * (1.0 - smoothstep(0.0, 0.48, progress))
		if source_alpha > 0.001:
			draw_arc(source, 11.0, 0.0, TAU, 28, Color(color, source_alpha), 1.5, true)
		draw_circle(position, 6.0, Color(color, 0.92 * (1.0 - smoothstep(0.86, 1.0, progress))))


func _quadratic_bezier(start: Vector2, control: Vector2, finish: Vector2, progress: float) -> Vector2:
	var value := clampf(progress, 0.0, 1.0)
	var inverse := 1.0 - value
	return start * inverse * inverse + control * 2.0 * inverse * value + finish * value * value


func _draw_launch_guide_handoff() -> void:
	if _handoff_kind() != "angles-to-launch" or _handoff_progress() >= 1.0:
		return
	var variants: Array = episode.get("variants", [])
	var focus_id := String(current_beat.get("focus", ""))
	var active_index := 0
	for index in range(variants.size()):
		if String(variants[index].get("id", "")) == focus_id:
			active_index = index
			break
	var opacity := 1.0 - _handoff_progress()
	for index in range(variants.size()):
		_draw_setup_angle_ray(variants[index], index, opacity, active_index)


func _draw_model_boundary_labels() -> void:
	var labels := [
		{
			"id": String(current_beat.get("focus", "")),
			"text": String(current_beat.get("focus_label", "")),
			"offset": Vector2(22, -24),
		},
		{
			"id": String(current_beat.get("focus_secondary", "")),
			"text": String(current_beat.get("focus_secondary_label", "")),
			"offset": Vector2(22, -60),
		},
	]
	for label_value in labels:
		var label: Dictionary = label_value
		var id := String(label["id"])
		var text := String(label["text"])
		var points: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
		if text.is_empty() or points.is_empty():
			continue
		var apex := _map_point(_trajectory_apex(points))
		var color: Color = colors_by_id.get(id, episode["theme"]["colors"]["muted"])
		draw_string(
			VideoTypography.medium(),
			apex + Vector2(label["offset"]),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			26,
			Color(color, 0.82)
		)


func _draw_arrow(start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	draw_line(start, finish, color, width, true)
	var direction := (finish - start).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var head := finish - direction * 22.0
	draw_colored_polygon(PackedVector2Array([finish, head + normal * 10.0, head - normal * 10.0]), color)


func _draw_module_label(position: Vector2, value: String, color: Color) -> void:
	draw_string(VideoTypography.data(), position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color)


func _beat_progress() -> float:
	if current_beat.is_empty():
		return 0.0
	return clampf(
		(video_time_sec - float(current_beat.get("at", video_time_sec)))
		/ maxf(0.001, float(current_beat.get("duration", 1.0))),
		0.0,
		1.0
	)


func _beat_intro_progress(duration_sec: float = 0.8) -> float:
	if current_beat.is_empty():
		return 1.0
	return smoothstep(
		0.0,
		maxf(0.001, duration_sec),
		video_time_sec - float(current_beat.get("at", video_time_sec))
	)


func _draw_background() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	draw_rect(Rect2(Vector2.ZERO, EpisodeLayout.CANVAS_SIZE), colors["background"], true)
	if not _show_physical_stage():
		return
	var scale_value := _world_scale()
	var ground_start := _map_point(Vector2(0, ground_y_px))
	var ground_end := _map_point(Vector2(1920, ground_y_px))
	var horizon_alpha := 0.72 if _shot_mode() == "immersive" else 0.42
	draw_line(
		ground_start,
		ground_end,
		Color(colors["ground_line"], horizon_alpha),
		maxf(1.5, 3.0 * scale_value),
		true
	)


func _draw_grid() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var minor := Color(colors["divider"], 0.10)
	var major := Color(colors["divider"], 0.18)
	for x in range(0, 1921, 50):
		var color := major if x % 200 == 0 else minor
		draw_line(
			_map_point(Vector2(x, 90)),
			_map_point(Vector2(x, ground_y_px)),
			color,
			1.0
		)
	for y in range(120, int(ground_y_px), 50):
		var color := major if y % 200 == 0 else minor
		draw_line(
			_map_point(Vector2(0, y)),
			_map_point(Vector2(1920, y)),
			color,
			1.0
		)


func _draw_sling() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var scale_value := _world_scale()
	var base := launch_position_px + Vector2(-46, 104)
	var left_foot := _map_point(base + Vector2(-34, 70))
	var right_foot := _map_point(base + Vector2(34, 70))
	var left_tip_source := base + Vector2(-14, -34)
	var right_tip_source := base + Vector2(14, -34)
	var left_tip := _map_point(left_tip_source)
	var right_tip := _map_point(right_tip_source)
	var frame_color := Color(colors["muted"], 0.62)
	for points in [[left_foot, left_tip], [right_foot, right_tip]]:
		draw_line(
			points[0],
			points[1],
			frame_color,
			VisualLanguage.width("primary", scale_value),
			true
		)
	draw_circle(left_tip, maxf(2.5, 4.0 * scale_value), frame_color)
	draw_circle(right_tip, maxf(2.5, 4.0 * scale_value), frame_color)

	var sling_state := _sling_state()
	var pouch_source: Vector2 = sling_state["pouch_position"]
	var pouch := _map_point(pouch_source)
	var accent: Color = sling_state["color"]
	var tension: float = sling_state["tension"]
	_draw_elastic_band(left_tip, pouch, accent, tension, -1.0)
	_draw_elastic_band(right_tip, pouch, accent, tension, 1.0)
	var pouch_direction := (pouch - (left_tip + right_tip) * 0.5).normalized()
	if pouch_direction.is_zero_approx():
		pouch_direction = Vector2.RIGHT
	var pouch_perpendicular := Vector2(-pouch_direction.y, pouch_direction.x)
	draw_line(
		pouch - pouch_perpendicular * maxf(5.0, 12.0 * scale_value),
		pouch + pouch_perpendicular * maxf(5.0, 12.0 * scale_value),
		Color(colors["muted"], 0.72),
		VisualLanguage.width("secondary", scale_value),
		true
	)

	var base_left := _map_point(base + Vector2(-50, 71))
	var base_right := _map_point(base + Vector2(50, 71))
	draw_line(
		base_left,
		base_right,
		Color(colors["muted"], 0.38),
		VisualLanguage.width("secondary", scale_value),
		true
	)

	if phase == "SETUP" and tension > 0.18:
		_draw_bird(
			pouch_source,
			float(sling_state["rotation"]),
			accent,
			1.0,
			false,
			Vector2.ZERO,
			int(sling_state["variant_index"]),
			true
		)


func _sling_state() -> Dictionary:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	var result := {
		"pouch_position": launch_position_px,
		"color": theme_colors["ground_line"],
		"tension": 0.12,
		"rotation": 0.0,
		"variant_index": 0,
	}
	var variants: Array = episode.get("variants", [])
	if phase == "SETUP" and not variants.is_empty():
		var duration := maxf(0.001, float(episode["story"]["setup_sec"]))
		var progress := clampf(
			EpisodeLayout.phase_elapsed(episode, phase, video_time_sec) / duration,
			0.0,
			0.9999
		)
		var slot: float = progress * float(variants.size())
		var index := mini(int(floor(slot)), variants.size() - 1)
		var slot_progress: float = slot - floor(slot)
		var focus_id := String(current_beat.get("focus", ""))
		if not focus_id.is_empty():
			for focus_index in range(variants.size()):
				if String(variants[focus_index].get("id", "")) == focus_id:
					index = focus_index
					slot_progress = 0.5
					break
		var pull := 1.0
		if slot_progress < 0.30:
			pull = smoothstep(0.0, 0.30, slot_progress)
		elif slot_progress > 0.86:
			pull = 1.0 - smoothstep(0.86, 1.0, slot_progress)
		var variant: Dictionary = variants[index]
		var physics: Dictionary = variant["preset"]["physics"]
		var angle := deg_to_rad(float(physics["launch_angle_deg"]))
		var launch_direction := Vector2(cos(angle), -sin(angle))
		var pull_distance := 24.0 + float(physics["stretch_m"]) * 68.0
		result["pouch_position"] = launch_position_px - launch_direction * pull_distance * pull
		result["color"] = variant["color"]
		result["tension"] = pull
		result["rotation"] = -angle
		result["variant_index"] = index
	elif phase == "FLIGHT":
		var elapsed := EpisodeLayout.phase_elapsed(episode, phase, video_time_sec)
		var recoil := exp(-elapsed * 5.2) * sin(elapsed * 23.0) * 38.0
		result["pouch_position"] = launch_position_px + Vector2(recoil, recoil * 0.16)
		result["tension"] = clampf(absf(recoil) / 38.0, 0.12, 1.0)
	return result


func _draw_elastic_band(
	start: Vector2,
	finish: Vector2,
	accent: Color,
	tension: float,
	side: float
) -> void:
	var vector := finish - start
	var perpendicular := Vector2(-vector.y, vector.x).normalized()
	var sag := (1.0 - tension) * 10.0 * side
	var middle := start.lerp(finish, 0.53) + perpendicular * sag
	var points := PackedVector2Array([start, middle, finish])
	draw_polyline(
		points,
		Color(accent, lerpf(0.46, 0.84, tension)),
		VisualLanguage.width("secondary"),
		true
	)


func _draw_target_platform() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var top := target_position_px.y + 75.0
	if top >= ground_y_px:
		return
	var top_left := _map_point(Vector2(target_position_px.x - 90, top))
	var bottom_right := _map_point(Vector2(target_position_px.x + 90, ground_y_px))
	draw_rect(Rect2(top_left, bottom_right - top_left), colors["ground"], true)
	var cap_left := _map_point(Vector2(target_position_px.x - 105, top - 10))
	var cap_right := _map_point(Vector2(target_position_px.x + 105, top + 8))
	draw_rect(Rect2(cap_left, cap_right - cap_left), colors["ground_line"], true)


func _draw_reference_target() -> void:
	_draw_target(target_position_px, 0.0, episode["theme"]["colors"]["muted"], 0.32)


func _draw_trajectories() -> void:
	var variants: Array = episode.get("variants", [])
	for index in range(variants.size()):
		var variant: Dictionary = variants[index]
		var id: String = variant["id"]
		var color: Color = colors_by_id[id]
		var points: PackedVector2Array
		var alpha := 0.2
		var width := 3.0
		if phase in ["QUESTION", "EXPLAIN"]:
			continue
		elif phase == "SETUP":
			_draw_setup_angle_ray(variant, index, 1.0, _setup_active_variant_index())
			continue
		elif phase == "FLIGHT":
			points = ReplayTrack.partial_trajectory(
				records_by_id[id],
				float(simulation_times_by_id.get(id, 0.0))
			)
			var flight_focus := String(current_beat.get("focus", ""))
			if not flight_focus.is_empty():
				alpha = VisualLanguage.ALPHA_PRIMARY if id == flight_focus else VisualLanguage.ALPHA_CONTEXT
				width = VisualLanguage.STROKE_PRIMARY if id == flight_focus else VisualLanguage.STROKE_CONTEXT
			else:
				alpha = 0.62
				width = VisualLanguage.STROKE_SECONDARY
		else:
			points = trajectories_by_id.get(id, PackedVector2Array())
			var focus_id := String(current_beat.get("focus", ""))
			var secondary_id := String(current_beat.get("focus_secondary", ""))
			if String(current_beat.get("id", "")) == "ranking":
				alpha = 0.58 if id == focus_id else VisualLanguage.ALPHA_CONTEXT
				width = VisualLanguage.STROKE_PRIMARY if id == focus_id else VisualLanguage.STROKE_CONTEXT
			elif String(current_beat.get("overlay", "")) == "counterexample":
				alpha = VisualLanguage.ALPHA_PRIMARY if id == focus_id else 0.035
				width = VisualLanguage.STROKE_PRIMARY if id == focus_id else VisualLanguage.STROKE_CONTEXT
			elif String(current_beat.get("overlay", "")) == "model-boundary":
				if id == focus_id:
					alpha = VisualLanguage.ALPHA_PRIMARY
					width = VisualLanguage.STROKE_PRIMARY
				elif id == secondary_id:
					alpha = 0.48
					width = VisualLanguage.STROKE_SECONDARY
				else:
					alpha = 0.075
					width = VisualLanguage.STROKE_CONTEXT
			elif not focus_id.is_empty():
				if id == focus_id:
					alpha = VisualLanguage.ALPHA_PRIMARY
				else:
					var context_fade := 1.0
					if String(current_beat.get("id", "")) == "takeaway":
						context_fade = lerpf(1.0, 0.28, smoothstep(0.0, 0.52, _beat_progress()))
					alpha = VisualLanguage.ALPHA_CONTEXT * context_fade
				width = VisualLanguage.STROKE_PRIMARY if id == focus_id else VisualLanguage.STROKE_CONTEXT
			else:
				alpha = VisualLanguage.ALPHA_PRIMARY if id == analysis.get("winner_id") else 0.22
				width = VisualLanguage.STROKE_PRIMARY if id == analysis.get("winner_id") else VisualLanguage.STROKE_MEASURE
		var mapped_points := _map_points(points)
		if mapped_points.size() >= 2:
			draw_polyline(mapped_points, Color(color, alpha), maxf(VisualLanguage.STROKE_CONTEXT, width * _world_scale()), true)


func _setup_active_variant_index() -> int:
	var variants: Array = episode.get("variants", [])
	if variants.is_empty():
		return 0
	var focus_id := String(current_beat.get("focus", ""))
	if not focus_id.is_empty():
		for index in range(variants.size()):
			if String(variants[index].get("id", "")) == focus_id:
				return index
	var duration := maxf(0.001, float(episode["story"].get("setup_sec", 1.0)))
	var progress := clampf(
		EpisodeLayout.phase_elapsed(episode, "SETUP", video_time_sec) / duration,
		0.0,
		0.9999
	)
	return mini(int(floor(progress * float(variants.size()))), variants.size() - 1)


func _variant_for_id(id: String) -> Dictionary:
	for variant_value in episode.get("variants", []):
		var variant: Dictionary = variant_value
		if String(variant.get("id", "")) == id:
			return variant
	return {}


func _draw_setup_angle_ray(
	variant: Dictionary,
	index: int,
	opacity: float,
	active_index: int
) -> void:
	var physics: Dictionary = variant["preset"]["physics"]
	var angle_deg := float(physics["launch_angle_deg"])
	var angle := deg_to_rad(angle_deg)
	var direction := Vector2(cos(angle), -sin(angle))
	var start := _map_point(launch_position_px)
	var finish := _map_point(launch_position_px + direction * 460.0)
	var color: Color = colors_by_id.get(String(variant["id"]), episode["theme"]["colors"]["muted"])
	var is_active := index == active_index
	var is_complete := index < active_index
	var alpha := 0.14
	var width := VisualLanguage.STROKE_CONTEXT
	if is_complete:
		alpha = 0.30
		width = VisualLanguage.STROKE_MEASURE
	if is_active:
		alpha = 0.94
		width = VisualLanguage.STROKE_PRIMARY
	alpha *= clampf(opacity, 0.0, 1.0)
	draw_line(start, finish, Color(color, alpha), width, true)
	draw_circle(finish, 5.0 if is_active else 2.5, Color(color, alpha))
	if not is_active:
		return
	var travel := fmod(video_time_sec * 0.34, 1.0)
	var flow_alpha := sin(PI * travel) * alpha
	draw_circle(start.lerp(finish, travel), 7.0, Color(color, flow_alpha))
	var radius := 76.0 * _world_scale()
	draw_arc(
		start,
		radius,
		-angle,
		0.0,
		24,
		Color(color, alpha * 0.58),
		VisualLanguage.STROKE_MEASURE,
		true
	)
	draw_string(
		VideoTypography.data(),
		finish + Vector2(16, -8),
		String(variant["label"]),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		28,
		Color(color, alpha)
	)
	if String(current_beat.get("overlay", "")) == "protractor":
		_draw_setup_velocity_components(start, finish, color, alpha)


func _draw_setup_velocity_components(
	start: Vector2,
	finish: Vector2,
	color: Color,
	alpha: float
) -> void:
	var corner := Vector2(finish.x, start.y)
	var component_color := Color(color, alpha * 0.42)
	_draw_arrow(start, corner, component_color, VisualLanguage.STROKE_MEASURE)
	_draw_arrow(corner, finish, component_color, VisualLanguage.STROKE_MEASURE)
	draw_string(
		VideoTypography.data(), start.lerp(corner, 0.56) + Vector2(-18, 38),
		"vₓ", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, component_color
	)
	draw_string(
		VideoTypography.data(), corner.lerp(finish, 0.52) + Vector2(18, 6),
		"vᵧ", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, component_color
	)


func _draw_variant_birds() -> void:
	var variants: Array = episode.get("variants", [])
	var takeaway_focus_only := String(current_beat.get("id", "")) == "takeaway"
	var counterexample_focus_only := String(current_beat.get("overlay", "")) == "counterexample"
	var focus_id := String(current_beat.get("focus", ""))
	for index in range(variants.size()):
		var variant: Dictionary = variants[index]
		var id: String = variant["id"]
		if (takeaway_focus_only or counterexample_focus_only) and id != focus_id:
			continue
		var state: Dictionary = states_by_id.get(id, {})
		if state.is_empty():
			continue
		var winner: bool = _winner_emphasis_enabled() and id == analysis.get("winner_id")
		var bird_alpha := 1.0 if winner else 0.88
		if not focus_id.is_empty() and id != focus_id:
			bird_alpha = 0.28
		_draw_bird(
			state["bird_position_px"],
			float(state["bird_rotation"]),
			colors_by_id[id],
			bird_alpha,
			winner,
			state["bird_velocity_px_s"],
			index
		)
		if phase == "FLIGHT":
			if String(episode["simulation"].get("model", "rigidbody")) != "projectile_drag":
				_draw_velocity_vector(
					state["bird_position_px"],
					state["bird_velocity_px_s"],
					colors_by_id[id]
				)
			elif id == focus_id and _has_layer("annotations"):
				_draw_air_vectors(state, colors_by_id[id])


func _draw_cold_open_teaser() -> void:
	var overlay := String(current_beat.get("overlay", ""))
	if overlay == "drag-angle-upset":
		_draw_drag_angle_upset()
		return
	if overlay == "ideal-45":
		_draw_ideal_45_teaser(false)
		return
	if overlay == "same-angle-models":
		_draw_ideal_45_teaser(true)
		return
	var visual_basis := _visual_sequence_basis(current_beat)
	var focus_id := String(current_beat.get("focus", visual_basis.get("focus", "")))
	if focus_id.is_empty() or not records_by_id.has(focus_id):
		return
	_draw_teaser_subject(
		focus_id,
		String(current_beat.get("focus_label", "")),
		0,
		1.0,
		_visual_sequence_progress()
	)
	var secondary_id := String(current_beat.get(
		"focus_secondary",
		visual_basis.get("focus_secondary", "")
	))
	if not secondary_id.is_empty() and records_by_id.has(secondary_id):
		_draw_teaser_subject(
			secondary_id,
			String(current_beat.get("focus_secondary_label", "")),
			1,
			0.88,
			_visual_sequence_progress()
		)


func _draw_drag_angle_upset() -> void:
	var progress := _visual_sequence_progress()
	var reveal := smoothstep(0.0, 0.12, progress)
	var ids := ["angle-45", "angle-40"]
	for id in ids:
		var points: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
		if points.size() < 2:
			continue
		var emphasis := 0.24 if id == "angle-45" else 0.46
		draw_polyline(
			_map_points(points),
			Color(colors_by_id[id], emphasis * reveal),
			VisualLanguage.STROKE_SECONDARY,
			true
		)
		var landing := _map_point(points[points.size() - 1])
		draw_line(
			landing + Vector2(0, -30),
			landing + Vector2(0, 8),
			Color(colors_by_id[id], 0.82 * reveal),
			VisualLanguage.STROKE_MEASURE,
			true
		)
		draw_circle(landing, 6.0, Color(colors_by_id[id], 0.94 * reveal))
	_draw_teaser_subject("angle-45", "45°", 0, reveal * 0.82, progress)
	_draw_teaser_subject("angle-40", "40°", 1, reveal, progress)

	# Ask for the viewer's prediction before revealing the measured result. The
	# first half of the shared 14-second sequence shows only the two flights.
	var panel_alpha := smoothstep(0.50, 0.62, progress)
	# Keep the data summary clear of the real landing markers. The landing positions
	# are spatial evidence; letting their measurement stems enter the copy makes
	# them read like parts of the angle labels.
	var panel := Rect2(1400, 650, 430, 174)
	var range_45 := float(records_by_id["angle-45"].get("metrics", {}).get("flight_range_m", 0.0))
	var range_40 := float(records_by_id["angle-40"].get("metrics", {}).get("flight_range_m", 0.0))
	var range_delta_cm := (range_40 - range_45) * 100.0
	draw_circle(
		panel.position + Vector2(28, 52),
		5.0,
		Color(colors_by_id["angle-45"], panel_alpha)
	)
	draw_circle(
		panel.position + Vector2(28, 116),
		5.0,
		Color(colors_by_id["angle-40"], panel_alpha)
	)
	draw_string(
		VideoTypography.medium(),
		panel.position + Vector2(48, 62),
		"45°   %.2f m" % range_45,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		31,
		Color(colors_by_id["angle-45"], panel_alpha)
	)
	draw_string(
		VideoTypography.medium(),
		panel.position + Vector2(48, 126),
		"40°   %.2f m   ·   +%.0f cm" % [range_40, range_delta_cm],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		31,
		Color(colors_by_id["angle-40"], panel_alpha)
	)


func _draw_ideal_45_teaser(include_air: bool) -> void:
	var ideal := _ideal_45_track()
	var points: PackedVector2Array = ideal.get("points", PackedVector2Array())
	if points.size() < 2:
		return
	var theme_colors: Dictionary = episode["theme"]["colors"]
	var ideal_color: Color = theme_colors["muted"]
	var reveal := smoothstep(0.0, 0.72, _beat_progress())
	var reveal_count := clampi(int(ceil(points.size() * reveal)), 2, points.size())
	var visible_points := _map_points(points.slice(0, reveal_count))
	draw_polyline(
		visible_points,
		Color(ideal_color, 0.72),
		VisualLanguage.STROKE_PRIMARY,
		true
	)
	var point_index := mini(points.size() - 1, maxi(0, reveal_count - 1))
	var source_position := points[point_index]
	var velocity: Vector2 = ideal.get("velocities", PackedVector2Array())[point_index]
	_draw_bird(
		source_position,
		velocity.angle(),
		ideal_color,
		0.92,
		false,
		velocity,
		0
	)
	var ideal_label := "理想真空 · 45°" if include_air else "理想模型 · 45°"
	var ideal_label_position := _map_point(source_position) + Vector2(42, -38)
	if ideal_label_position.x > 1580.0:
		ideal_label_position += Vector2(-300, 0)
	draw_string(
		VideoTypography.medium(),
		ideal_label_position,
		ideal_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		30,
		Color(ideal_color, 0.92)
	)
	if include_air:
		_draw_teaser_subject("angle-45", "有空气 · 45°", 1, 1.0, _beat_progress())
		var air_record: Dictionary = records_by_id.get("angle-45", {})
		if not air_record.is_empty():
			var air_duration := float(air_record.get("metrics", {}).get("flight_time_sec", 0.0))
			var air_state := ReplayTrack.sample(
				air_record,
				air_duration * lerpf(0.42, 0.88, smoothstep(0.0, 1.0, _beat_progress()))
			)
			_draw_air_vectors(air_state, colors_by_id["angle-45"])


func _ideal_45_track() -> Dictionary:
	var first_variant: Dictionary = episode.get("variants", [{}])[0]
	var preset: Dictionary = first_variant.get("preset", {})
	var physics: Dictionary = preset.get("physics", {})
	var scene: Dictionary = preset.get("scene", {})
	if physics.is_empty() or scene.is_empty():
		return {}
	var ppm := float(physics.get("pixels_per_meter", 1.0))
	var gravity := float(physics.get("gravity_mps2", 9.81))
	var speed := float(physics.get("launch_speed_mps", 0.0))
	var start_m := Vector2(scene.get("launch_position_m", Vector2.ZERO))
	var angle := deg_to_rad(45.0)
	var initial_velocity := Vector2(cos(angle), -sin(angle)) * speed
	var flight_time := 2.0 * speed * sin(angle) / maxf(gravity, 0.001)
	var points := PackedVector2Array()
	var velocities := PackedVector2Array()
	for sample_index in range(65):
		var time := flight_time * float(sample_index) / 64.0
		var position_m := (
			start_m
			+ initial_velocity * time
			+ Vector2(0.0, 0.5 * gravity * time * time)
		)
		points.append(position_m * ppm)
		velocities.append((initial_velocity + Vector2(0.0, gravity * time)) * ppm)
	return {"points": points, "velocities": velocities}


func _draw_teaser_subject(
	id: String,
	label: String,
	variant_index: int,
	alpha: float,
	sequence_progress: float
) -> void:
	var record: Dictionary = records_by_id[id]
	var duration := float(record.get("metrics", {}).get(
		"flight_time_sec", record.get("duration_sec", 0.0)
	))
	var teaser_time := duration * lerpf(0.42, 0.88, smoothstep(0.0, 1.0, sequence_progress))
	var state := ReplayTrack.sample(record, teaser_time)
	var full_points: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
	var reveal_count := mini(full_points.size(), maxi(2, int(full_points.size() * 0.82)))
	var teaser_points := _map_points(full_points.slice(0, reveal_count))
	if teaser_points.size() >= 2:
		draw_polyline(
			teaser_points,
			Color(colors_by_id[id], 0.30 * alpha),
			VisualLanguage.STROKE_SECONDARY,
			true
		)
	_draw_bird(
		state["bird_position_px"],
		float(state["bird_rotation"]),
		colors_by_id[id],
		alpha,
		false,
		state["bird_velocity_px_s"],
		variant_index
	)
	var bird_position := _map_point(state["bird_position_px"])
	if not label.is_empty():
		var label_offset := Vector2(48, -42) if variant_index == 0 else Vector2(42, 52)
		draw_string(
			VideoTypography.medium(),
			bird_position + label_offset,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			30,
			Color(colors_by_id[id], alpha)
		)


func _draw_event_effects() -> void:
	var beat_id := String(current_beat.get("id", ""))
	if beat_id == "launch":
		_draw_release_burst()
	elif _winner_emphasis_enabled() and _beat_progress() > 0.18:
		_draw_result_celebration()


func _draw_release_burst() -> void:
	var progress := clampf(_beat_progress() * 4.0, 0.0, 1.0)
	if progress >= 1.0:
		return
	var center := _map_point(launch_position_px)
	var color: Color = episode["theme"]["colors"]["accent"]
	draw_arc(
		center,
		lerpf(18.0, 58.0, progress),
		0.0,
		TAU,
		48,
		Color(color, 0.52 * (1.0 - progress)),
		VisualLanguage.STROKE_MEASURE,
		true
	)


func _draw_result_celebration() -> void:
	var winner_id := String(analysis.get("winner_id", ""))
	var state: Dictionary = states_by_id.get(winner_id, {})
	if state.is_empty():
		return
	var center := _map_point(state["bird_position_px"])
	var winner_color: Color = episode["theme"]["colors"]["accent"]
	draw_arc(
		center,
		52.0,
		-0.18 * PI,
		1.18 * PI,
		44,
		Color(winner_color, 0.44),
		VisualLanguage.STROKE_MEASURE,
		true
	)


func _draw_result_markers() -> void:
	var rows: Array = analysis.get("rows", [])
	if rows.is_empty():
		return
	if _beat_progress() < float(current_beat.get("result_reveal", 0.0)):
		return
	var winner_id := String(analysis.get("winner_id", ""))
	var winner_only := String(current_beat.get("id", "")) == "takeaway"
	if not winner_only:
		_draw_ranking_landings(rows, winner_id)
		_draw_result_rail(rows, winner_id)
		return
	_draw_takeaway_marker(rows, winner_id)


func _draw_ranking_landings(rows: Array, winner_id: String) -> void:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	for row_value in rows:
		var row: Dictionary = row_value
		var id := String(row["variant_id"])
		var points: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
		if points.is_empty():
			continue
		var landing := _map_point(points[-1])
		var winner := id == winner_id
		var color: Color = colors_by_id.get(id, theme_colors["muted"])
		var marker_color: Color = theme_colors["accent"] if winner else Color(color, 0.58)
		draw_line(
			landing + Vector2(0, -12),
			landing + Vector2(0, 9),
			Color(marker_color, 0.70),
			VisualLanguage.STROKE_SECONDARY if winner else VisualLanguage.STROKE_CONTEXT,
			true
		)
		draw_circle(landing, 6.0 if winner else 3.5, marker_color)


func _draw_landing_magnifier() -> void:
	var selected_ids := ["angle-30", "angle-34", "angle-38", "angle-40", "angle-45"]
	var rows_by_id := {}
	for row_value in analysis.get("rows", []):
		var row: Dictionary = row_value
		rows_by_id[String(row.get("variant_id", ""))] = row
	var values := PackedFloat32Array()
	for id in selected_ids:
		if rows_by_id.has(id):
			values.append(float(rows_by_id[id].get("value", 0.0)))
	if values.size() < 2:
		return

	var minimum := values[0]
	var maximum := values[0]
	for value in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	var padding := maxf(0.08, (maximum - minimum) * 0.12)
	minimum -= padding
	maximum += padding

	var alpha := smoothstep(0.04, 0.30, _beat_progress())
	var theme_colors: Dictionary = episode["theme"]["colors"]
	var panel := Rect2(880, 74, 880, 258)
	draw_rect(panel, Color(0.025, 0.033, 0.040, 0.92 * alpha), true)
	draw_rect(panel, Color(theme_colors["muted"], 0.30 * alpha), false, 2.0)
	draw_string(
		VideoTypography.medium(),
		panel.position + Vector2(30, 49),
		"落点局部放大 · 射程数值未改",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		27,
		Color(theme_colors["text"], 0.90 * alpha)
	)
	var rail_y := panel.position.y + 142.0
	var rail_left := panel.position.x + 54.0
	var rail_right := panel.end.x - 44.0
	draw_line(
		Vector2(rail_left, rail_y),
		Vector2(rail_right, rail_y),
		Color(theme_colors["divider"], 0.62 * alpha),
		2.0,
		true
	)
	for index in range(selected_ids.size()):
		var id: String = selected_ids[index]
		if not rows_by_id.has(id):
			continue
		var row: Dictionary = rows_by_id[id]
		var value := float(row.get("value", 0.0))
		var x := remap(value, minimum, maximum, rail_left, rail_right)
		var color: Color = colors_by_id.get(id, theme_colors["muted"])
		var winner := id == String(analysis.get("winner_id", ""))
		var marker_color: Color = theme_colors["accent"] if winner else color
		draw_circle(Vector2(x, rail_y), 7.0 if winner else 5.0, Color(marker_color, alpha))
		if id == "angle-40":
			draw_string(
				VideoTypography.data(),
				Vector2(panel.end.x - 326.0, rail_y + 82.0),
				"40°  %.2f m" % value,
				HORIZONTAL_ALIGNMENT_RIGHT,
				296.0,
				23,
				Color(marker_color, alpha)
			)
		elif id == "angle-45":
			draw_string(
				VideoTypography.data(),
				Vector2(x - 92.0, rail_y - 52.0),
				"45°  %.2f m" % value,
				HORIZONTAL_ALIGNMENT_CENTER,
				184.0,
				21,
				Color(marker_color, alpha)
			)
		else:
			var context_label_y := rail_y - 50.0 if id in ["angle-30", "angle-38"] else rail_y + 47.0
			draw_string(
				VideoTypography.data(),
				Vector2(x - 38.0, context_label_y),
				String(row.get("label", id)),
				HORIZONTAL_ALIGNMENT_CENTER,
				76.0,
				19,
				Color(marker_color, 0.78 * alpha)
			)


func _draw_result_rail(rows: Array, winner_id: String) -> void:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	var rail := EpisodeLayout.RESULT_RAIL_RECT
	draw_string(
		VideoTypography.medium(),
		rail.position + Vector2(-170, 29),
		"落点射程",
		HORIZONTAL_ALIGNMENT_RIGHT,
		140,
		26,
		Color(theme_colors["muted"], 0.66)
	)
	draw_line(
		rail.position + Vector2(-22, 18),
		Vector2(rail.position.x - 2, rail.position.y + 18),
		Color(theme_colors["divider"], 0.52),
		1.0,
		true
	)
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var id := String(row["variant_id"])
		var winner := id == winner_id
		var cell := EpisodeLayout.result_rail_cell(index, rows.size()).grow(-12.0)
		var color: Color = colors_by_id.get(id, theme_colors["muted"])
		draw_line(
			cell.position + Vector2(0, 4),
			Vector2(cell.end.x, cell.position.y + 4),
			Color(theme_colors["accent"] if winner else color, 0.92 if winner else 0.34),
			3.0 if winner else 1.0,
			true
		)
		var variant_label := "%s  ·  最远" % row["label"] if winner else String(row["label"])
		draw_string(
			VideoTypography.medium(),
			cell.position + Vector2(0, 34),
			variant_label,
			HORIZONTAL_ALIGNMENT_CENTER,
			cell.size.x,
			28 if winner else 26,
			theme_colors["text"] if winner else Color(theme_colors["muted"], 0.70)
		)
		draw_string(
			VideoTypography.data(),
			cell.position + Vector2(0, 72),
			"%.2f %s" % [float(row["value"]), String(analysis.get("metric_unit", ""))],
			HORIZONTAL_ALIGNMENT_CENTER,
			cell.size.x,
			30 if winner else 26,
			theme_colors["text"] if winner else Color(theme_colors["muted"], 0.82)
		)


func _draw_takeaway_marker(rows: Array, winner_id: String) -> void:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var id := String(row["variant_id"])
		if id != winner_id:
			continue
		var points: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
		if points.is_empty():
			continue
		var landing := _map_point(points[-1])
		var marker_color: Color = theme_colors["accent"]
		var label_y := landing.y - 116.0
		draw_line(
			landing + Vector2(0, 8),
			Vector2(landing.x, label_y + 9),
			Color(marker_color, 0.52),
			2.0,
			true
		)
		draw_circle(landing, 9.0, marker_color)
		var label := "%.2f %s" % [
			float(row["value"]),
			String(analysis.get("metric_unit", "")),
		]
		draw_string(
			VideoTypography.data(),
			Vector2(landing.x + 14, label_y),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			28,
			theme_colors["text"]
		)


func _draw_focus_height_marker() -> void:
	var focus_id := String(current_beat.get("focus", ""))
	var secondary_metric := String(analysis.get("secondary_metric", ""))
	if focus_id.is_empty() or secondary_metric.is_empty():
		return
	var row := _result_row_for_id(focus_id)
	var points: PackedVector2Array = trajectories_by_id.get(focus_id, PackedVector2Array())
	if row.is_empty() or points.is_empty() or not row["metrics"].has(secondary_metric):
		return
	var apex_source := _trajectory_apex(points)
	var apex := _map_point(apex_source)
	var ground := _map_point(Vector2(apex_source.x, ground_y_px))
	var side := -1.0 if apex.x < EpisodeLayout.CANVAS_SIZE.x * 0.5 else 1.0
	var ruler_x := clampf(apex.x + side * 74.0, 96.0, EpisodeLayout.CANVAS_SIZE.x - 96.0)
	var color: Color = colors_by_id.get(focus_id, episode["theme"]["colors"]["accent"])
	draw_dashed_line(
		Vector2(ruler_x, apex.y),
		Vector2(ruler_x, ground.y),
		Color(color, 0.38),
		VisualLanguage.STROKE_MEASURE,
		9.0,
		true
	)
	draw_line(apex, Vector2(ruler_x, apex.y), Color(color, 0.56), VisualLanguage.STROKE_MEASURE, true)
	draw_line(Vector2(ruler_x - 9, apex.y), Vector2(ruler_x + 9, apex.y), Color(color, 0.72), VisualLanguage.STROKE_MEASURE, true)
	draw_line(Vector2(ruler_x - 9, ground.y), Vector2(ruler_x + 9, ground.y), Color(color, 0.52), VisualLanguage.STROKE_MEASURE, true)
	var label_width := 180.0
	var label_x := ruler_x - label_width - 18.0 if side < 0.0 else ruler_x + 18.0
	var label_y := clampf(apex.y - 24.0, 130.0, ground.y - 92.0)
	draw_string(
		VideoTypography.medium(),
		Vector2(label_x, label_y),
		String(analysis.get("secondary_label", "最高点")),
		HORIZONTAL_ALIGNMENT_LEFT,
		label_width,
		26,
		Color(episode["theme"]["colors"]["muted"], 0.72)
	)
	draw_string(
		VideoTypography.data(),
		Vector2(label_x, label_y + 36),
		"%.2f %s" % [
			float(row["metrics"][secondary_metric]),
			String(analysis.get("secondary_unit", "")),
		],
		HORIZONTAL_ALIGNMENT_LEFT,
		label_width,
		26,
		episode["theme"]["colors"]["text"]
	)


func _result_row_for_id(id: String) -> Dictionary:
	for row_value in analysis.get("rows", []):
		var row: Dictionary = row_value
		if String(row.get("variant_id", "")) == id:
			return row
	return {}


func _trajectory_apex(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var apex := points[0]
	for point in points:
		if point.y < apex.y:
			apex = point
	return apex


func _draw_variant_targets() -> void:
	for variant_value in episode.get("variants", []):
		var variant: Dictionary = variant_value
		var id: String = variant["id"]
		var state: Dictionary = states_by_id.get(id, {})
		if state.is_empty():
			continue
		var position: Vector2 = state["target_position_px"]
		if position.distance_to(target_position_px) < 2.0:
			continue
		_draw_target(position, float(state["target_rotation"]), colors_by_id[id], 0.28)


func _draw_bird(
	source_position: Vector2,
	rotation_value: float,
	color: Color,
	alpha: float,
	winner: bool,
	velocity: Vector2,
	variant_index: int,
	preview: bool = false
) -> void:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	var position := _map_point(source_position)
	var visual_scale := maxf(0.72, _world_scale())
	var direction := velocity.normalized() if velocity.length() > 1.0 else Vector2.RIGHT.rotated(rotation_value)
	if phase == "FLIGHT" and velocity.length() > 120.0:
		for streak_index in range(2):
			var distance := 34.0 + streak_index * 18.0
			var tail := position - direction * distance * visual_scale
			draw_line(
				tail,
				tail + direction * (14.0 + streak_index * 3.0) * visual_scale,
				Color(color, 0.16 - streak_index * 0.05),
				VisualLanguage.width("context", visual_scale),
				true
			)
	if winner:
		draw_arc(
			position,
			38.0 * visual_scale,
			0.0,
			TAU,
			48,
			Color(theme_colors["accent"], 0.62),
			VisualLanguage.width("measure", visual_scale),
			true
		)

	draw_set_transform(
		position,
		rotation_value,
		Vector2.ONE * visual_scale
	)
	var tail_color := Color(color.darkened(0.18), alpha * 0.74)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-18, -5), Vector2(-35, -15), Vector2(-29, 0),
		]),
		tail_color
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-18, 3), Vector2(-34, 12), Vector2(-27, -1),
		]),
		tail_color
	)
	var body := PackedVector2Array()
	for body_index in range(24):
		var body_angle := TAU * float(body_index) / 24.0
		body.append(Vector2(cos(body_angle) * 22.0, sin(body_angle) * 15.0))
	draw_colored_polygon(body, Color(color, alpha * 0.90))
	var body_outline := body.duplicate()
	body_outline.append(body[0])
	draw_polyline(
		body_outline,
		Color(theme_colors["text"], alpha * 0.18),
		VisualLanguage.STROKE_CONTEXT,
		true
	)
	var wing_angle := 0.08 + sin(video_time_sec * 5.0 + variant_index * 0.7) * 0.05
	draw_arc(
		Vector2(-4, 2),
		9.5,
		wing_angle,
		PI - 0.28,
		16,
		Color(theme_colors["background"], alpha * 0.72),
		VisualLanguage.STROKE_SECONDARY,
		true
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(18, -4), Vector2(33, 1), Vector2(18, 7),
		]),
		Color(theme_colors["text"], alpha * 0.76)
	)
	draw_circle(Vector2(10, -6), 3.2, Color(theme_colors["text"], alpha * 0.90))
	draw_circle(Vector2(11, -6), 1.2, Color(theme_colors["background"], alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_target(position: Vector2, rotation_value: float, color: Color, alpha: float) -> void:
	var mapped := _map_point(position)
	var visual_scale := maxf(0.65, _world_scale())
	draw_set_transform(mapped, rotation_value, Vector2.ONE * visual_scale)
	var corners := PackedVector2Array([
		Vector2(-55, -75), Vector2(55, -75), Vector2(55, 75), Vector2(-55, 75),
	])
	draw_colored_polygon(corners, Color(color, alpha))
	draw_polyline(
		PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]),
		Color(color, minf(1.0, alpha + 0.25)),
		3.0,
		true
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_velocity_vector(position: Vector2, velocity: Vector2, color: Color) -> void:
	var start := _map_point(position)
	var finish := _map_point(position + velocity * 0.075)
	var vector := finish - start
	if vector.length() < 15.0:
		return
	var direction := vector.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	draw_line(start, finish, Color(color, 0.34), VisualLanguage.STROKE_MEASURE, true)
	draw_colored_polygon(
		PackedVector2Array([
			finish,
			finish - direction * 12.0 + perpendicular * 5.0,
			finish - direction * 12.0 - perpendicular * 5.0,
		]),
		Color(color, 0.42)
	)


func _draw_air_vectors(state: Dictionary, color: Color) -> void:
	_draw_velocity_vector(
		Vector2(state["bird_position_px"]),
		Vector2(state["bird_velocity_px_s"]),
		color
	)
	var drag_force := Vector2(state.get("drag_force_n", Vector2.ZERO))
	if drag_force.length() <= 1e-6:
		return
	var start := _map_point(Vector2(state["bird_position_px"]))
	var length := clampf(46.0 + drag_force.length() * 34.0, 46.0, 128.0)
	var finish := start + drag_force.normalized() * length
	_draw_arrow(
		start, finish, Color(episode["theme"]["colors"]["accent"], 0.78),
		VisualLanguage.STROKE_SECONDARY
	)
	draw_string(
		VideoTypography.medium(), finish + Vector2(-58, -12), "阻力",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
		Color(episode["theme"]["colors"]["accent"], 0.82)
	)


func _draw_range_curve(opacity: float = 1.0, show_transition: bool = true) -> void:
	opacity = clampf(opacity, 0.0, 1.0)
	var scans: Array = []
	var overlay := String(current_beat.get("overlay", "range-curve"))
	for scan_value in bundle.get("range_scans", []):
		var scan: Dictionary = scan_value
		var scan_id := String(scan.get("id", ""))
		if overlay == "parameter-curve" and scan_id in ["air", "higher-ballistic-coefficient"]:
			scans.append(scan)
		elif overlay == "range-curve" and scan_id in ["vacuum", "air"]:
			scans.append(scan)
	if scans.is_empty():
		return
	var colors: Dictionary = episode["theme"]["colors"]
	var plot := Rect2(238, 170, 1444, 650)
	var landing_handoff := show_transition and _handoff_kind() == "landings-to-chart" and _handoff_progress() < 1.0
	var chrome_opacity := opacity
	var context_opacity := opacity
	if landing_handoff:
		chrome_opacity *= smoothstep(0.10, 0.64, _handoff_progress())
		context_opacity *= smoothstep(0.34, 0.86, _handoff_progress())
	var min_angle := INF
	var max_angle := -INF
	var max_range := 0.0
	for scan_value in scans:
		var scan: Dictionary = scan_value
		for point_value in scan.get("points", []):
			var point: Dictionary = point_value
			min_angle = minf(min_angle, float(point["angle_deg"]))
			max_angle = maxf(max_angle, float(point["angle_deg"]))
			max_range = maxf(max_range, float(point["range_m"]))
	if not is_finite(min_angle) or max_angle <= min_angle or max_range <= 0.0:
		return
	var chart_title := (
		"阻力相对变弱时，峰值回到哪里？"
		if overlay == "parameter-curve"
		else "发射角改变时，最远点在哪里？"
	)
	draw_string(
		VideoTypography.medium(), plot.position + Vector2(0, -52),
		chart_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32,
		Color(colors["text"], 0.92 * chrome_opacity)
	)
	draw_line(plot.position + Vector2(0, plot.size.y), plot.end, Color(colors["divider"], 0.66 * chrome_opacity), 1.5, true)
	draw_line(plot.position, plot.position + Vector2(0, plot.size.y), Color(colors["divider"], 0.66 * chrome_opacity), 1.5, true)
	for tick_index in range(5):
		var ratio := float(tick_index) / 4.0
		var x := plot.position.x + plot.size.x * ratio
		var angle := lerpf(min_angle, max_angle, ratio)
		draw_line(
			Vector2(x, plot.end.y), Vector2(x, plot.end.y + 8),
			Color(colors["divider"], 0.54 * chrome_opacity), 1.0, true
		)
		draw_string(
			VideoTypography.data(), Vector2(x - 34, plot.end.y + 36), "%.0f°" % angle,
			HORIZONTAL_ALIGNMENT_CENTER, 82, 26, Color(colors["muted"], 0.78 * chrome_opacity)
		)
	for tick_index in range(4):
		var ratio := float(tick_index) / 3.0
		var y := plot.end.y - plot.size.y * ratio
		var value := max_range * ratio
		draw_line(
			Vector2(plot.position.x - 8, y), Vector2(plot.position.x, y),
			Color(colors["divider"], 0.54 * chrome_opacity), 1.0, true
		)
		draw_string(
			VideoTypography.data(), Vector2(plot.position.x - 98, y + 6), "%.0f m" % value,
			HORIZONTAL_ALIGNMENT_RIGHT, 92, 26, Color(colors["muted"], 0.76 * chrome_opacity)
		)
	var reveal := smoothstep(0.0, 0.58, _visual_sequence_progress())
	for scan_index in range(scans.size()):
		var scan: Dictionary = scans[scan_index]
		var points: Array = scan.get("points", [])
		var scan_color := Color.from_string(String(scan["color_html"]), colors["accent"])
		_draw_range_curve_segments(
			points,
			plot,
			min_angle,
			max_angle,
			max_range,
			1.0,
			Color(scan_color, (0.12 if scan_index == 0 else 0.17) * context_opacity),
			VisualLanguage.STROKE_CONTEXT
		)
	if landing_handoff:
		_draw_landing_to_chart_handoff(plot, min_angle, max_angle, max_range, scans, opacity)
	for scan_index in range(scans.size()):
		var scan: Dictionary = scans[scan_index]
		var points: Array = scan.get("points", [])
		var scan_color := Color.from_string(String(scan["color_html"]), colors["accent"])
		_draw_range_curve_segments(
			points,
			plot,
			min_angle,
			max_angle,
			max_range,
			reveal,
			Color(scan_color, (0.44 if scan_index == 0 else 0.94) * opacity),
			VisualLanguage.STROKE_SECONDARY if scan_index == 0 else VisualLanguage.STROKE_PRIMARY
		)
		var best: Dictionary = scan.get("best", {})
		if reveal > 0.72 and not best.is_empty():
			var best_position := Vector2(
				plot.position.x + plot.size.x * (float(best["angle_deg"]) - min_angle) / (max_angle - min_angle),
				plot.end.y - plot.size.y * float(best["range_m"]) / max_range
			)
			draw_circle(best_position, 7.0 if scan_index > 0 else 5.0, Color(scan_color, opacity))
			draw_string(
				VideoTypography.data(), best_position + Vector2(14, -14),
				"%s  %.0f°" % [String(scan["label"]), float(best["angle_deg"])],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
				Color(scan_color, (0.92 if scan_index > 0 else 0.70) * opacity)
			)
	if reveal > 0.02 and reveal < 0.98 and not scans.is_empty():
		var active_scan: Dictionary = scans[-1]
		var active_points: Array = active_scan.get("points", [])
		if active_points.size() >= 2:
			var active_position := _range_curve_position_at_reveal(
				active_points, plot, min_angle, max_angle, max_range, reveal
			)
			var active_angle := lerpf(min_angle, max_angle, reveal)
			var active_color := Color.from_string(
				String(active_scan["color_html"]), colors["accent"]
			)
			draw_line(
				Vector2(active_position.x, active_position.y + 10),
				Vector2(active_position.x, plot.end.y),
				Color(active_color, 0.18 * opacity),
				VisualLanguage.STROKE_CONTEXT,
				true
			)
			draw_circle(active_position, 6.0, Color(active_color, 0.96 * opacity))
			draw_string(
				VideoTypography.data(), active_position + Vector2(14, -14),
				"扫描到 %.0f°" % active_angle,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
				Color(active_color, 0.90 * opacity)
			)


func _draw_landing_to_chart_handoff(
	plot: Rect2,
	min_angle: float,
	max_angle: float,
	max_range: float,
	scans: Array,
	opacity: float
) -> void:
	var air_scan: Dictionary = {}
	for scan_value in scans:
		var scan: Dictionary = scan_value
		if String(scan.get("id", "")) == "air":
			air_scan = scan
			break
	if air_scan.is_empty():
		return
	var progress := _handoff_progress()
	var variants: Array = episode.get("variants", [])
	for variant_index in range(variants.size()):
		var variant_value = variants[variant_index]
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var trajectory: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
		if trajectory.is_empty():
			continue
		var angle := float(variant["preset"]["physics"]["launch_angle_deg"])
		var point := _scan_point_for_angle(air_scan.get("points", []), angle)
		if point.is_empty():
			continue
		var source := _map_point(trajectory[-1])
		var target := _range_curve_point(point, plot, min_angle, max_angle, max_range)
		var stagger := float(variant_index) * 0.035
		var local_progress := smoothstep(stagger, minf(1.0, 0.82 + stagger), progress)
		var control := source.lerp(target, 0.46) + Vector2(0, -72)
		var position := _quadratic_bezier(source, control, target, local_progress)
		var color: Color = colors_by_id.get(id, episode["theme"]["colors"]["accent"])
		var source_alpha := (1.0 - smoothstep(0.12, 0.68, local_progress)) * 0.24 * opacity
		if source_alpha > 0.001:
			draw_arc(source, 9.0, 0.0, TAU, 24, Color(color, source_alpha), 1.4, true)
		for trail_index in range(4, 0, -1):
			var trail_progress := maxf(0.0, local_progress - float(trail_index) * 0.045)
			if trail_progress <= 0.0:
				continue
			var trail_position := _quadratic_bezier(source, control, target, trail_progress)
			draw_circle(
				trail_position,
				3.5,
				Color(color, 0.07 * (1.0 - float(trail_index) / 5.0) * opacity)
			)
		var dot_alpha := (1.0 - smoothstep(0.88, 1.0, local_progress)) * opacity
		draw_circle(position, 5.5, Color(color, 0.92 * dot_alpha))


func _scan_point_for_angle(points: Array, angle: float) -> Dictionary:
	var closest: Dictionary = {}
	var closest_distance := INF
	for point_value in points:
		var point: Dictionary = point_value
		var distance := absf(float(point["angle_deg"]) - angle)
		if distance < closest_distance:
			closest = point
			closest_distance = distance
	return closest


func _range_curve_position_at_reveal(
	points: Array,
	plot: Rect2,
	min_angle: float,
	max_angle: float,
	max_range: float,
	reveal: float
) -> Vector2:
	var position := clampf(reveal, 0.0, 1.0) * float(points.size() - 1)
	var start_index := mini(int(floor(position)), points.size() - 2)
	var fraction := position - float(start_index)
	return _range_curve_point(points[start_index], plot, min_angle, max_angle, max_range).lerp(
		_range_curve_point(points[start_index + 1], plot, min_angle, max_angle, max_range),
		fraction
	)


func _draw_range_curve_segments(
	points: Array,
	plot: Rect2,
	min_angle: float,
	max_angle: float,
	max_range: float,
	reveal: float,
	color: Color,
	width: float
) -> void:
	if points.size() < 2 or reveal <= 0.0:
		return
	# Godot's compatibility renderer can emit a malformed movie frame when the
	# vertex count of an animated draw_polyline changes. Individual segments keep
	# the reveal deterministic and make the leading edge move continuously.
	var reveal_position := reveal * float(points.size() - 1)
	var complete_segments := mini(int(floor(reveal_position)), points.size() - 1)
	for segment_index in range(complete_segments):
		draw_line(
			_range_curve_point(points[segment_index], plot, min_angle, max_angle, max_range),
			_range_curve_point(points[segment_index + 1], plot, min_angle, max_angle, max_range),
			color,
			width,
			true
		)
	if complete_segments >= points.size() - 1:
		return
	var partial := reveal_position - float(complete_segments)
	if partial <= 0.0:
		return
	var partial_start := _range_curve_point(
		points[complete_segments], plot, min_angle, max_angle, max_range
	)
	var partial_end := partial_start.lerp(
		_range_curve_point(points[complete_segments + 1], plot, min_angle, max_angle, max_range),
		partial
	)
	draw_line(partial_start, partial_end, color, width, true)


func _range_curve_point(
	point: Dictionary,
	plot: Rect2,
	min_angle: float,
	max_angle: float,
	max_range: float
) -> Vector2:
	return Vector2(
		plot.position.x + plot.size.x * (float(point["angle_deg"]) - min_angle) / (max_angle - min_angle),
		plot.end.y - plot.size.y * float(point["range_m"]) / max_range
	)


func _map_point(point: Vector2) -> Vector2:
	return ShotCamera.map_point(camera_state, point)


func _map_points(points: PackedVector2Array) -> PackedVector2Array:
	var mapped := PackedVector2Array()
	for point in points:
		mapped.append(_map_point(point))
	return mapped


func _world_scale() -> float:
	return float(camera_state.get("scale", EpisodeLayout.world_scale(phase, _shot_mode())))


func _shot_mode() -> String:
	return String(current_beat.get("mode", "measurement"))


func _show_physical_stage() -> bool:
	if not _has_layer("world"):
		return false
	return not (
		phase == "EXPLAIN"
		and explanation_module != null
		and explanation_module.hides_physical_stage()
	)


func _resolve_camera_state() -> Dictionary:
	if episode.is_empty() or current_beat.is_empty():
		return camera_state
	var basis := _camera_basis_beat(current_beat)
	var basis_phase := EpisodeDirector.phase_for_time(
		episode,
		float(basis.get("at", 0.0)) + 0.001
	)
	var current_anchor := _camera_anchor_for_beat(basis)
	var desired := ShotCamera.desired_state(basis_phase, basis, current_anchor)
	if String(current_beat.get("camera_action", "reframe")) == "hold":
		return desired
	var previous_basis := _previous_camera_basis(basis)
	if previous_basis.is_empty():
		return desired
	var previous_phase := EpisodeDirector.phase_for_time(
		episode,
		float(previous_basis.get("at", 0.0)) + 0.001
	)
	var previous_anchor := _camera_anchor_for_beat(previous_basis)
	var previous_state := ShotCamera.desired_state(
		previous_phase,
		previous_basis,
		previous_anchor
	)
	return ShotCamera.interpolate(
		previous_state,
		desired,
		ShotCamera.transition_progress(current_beat, video_time_sec),
		ShotCamera.transition_style(current_beat)
	)


func _camera_basis_beat(beat: Dictionary) -> Dictionary:
	var beats: Array = episode.get("beats", [])
	var id := String(beat.get("id", ""))
	for index in range(beats.size()):
		if String(beats[index].get("id", "")) == id:
			var basis_index := index
			while basis_index > 0 \
				and String(beats[basis_index].get("camera_action", "reframe")) == "hold":
				basis_index -= 1
			return beats[basis_index]
	return beat


func _visual_sequence_basis(beat: Dictionary) -> Dictionary:
	var sequence := _visual_sequence_id(beat)
	if sequence.is_empty():
		return beat
	var beats: Array = episode.get("beats", [])
	for index in range(beats.size()):
		if String(beats[index].get("id", "")) != String(beat.get("id", "")):
			continue
		var basis_index := index
		while basis_index > 0 \
				and _visual_sequence_id(beats[basis_index - 1]) == sequence:
			basis_index -= 1
		return beats[basis_index]
	return beat


func _visual_sequence_progress() -> float:
	if current_beat.is_empty():
		return 0.0
	var sequence := _visual_sequence_id(current_beat)
	if sequence.is_empty():
		return _beat_progress()
	var beats: Array = episode.get("beats", [])
	var start_sec := float(current_beat.get("at", video_time_sec))
	var end_sec := start_sec + float(current_beat.get("duration", 1.0))
	for beat_value in beats:
		var beat: Dictionary = beat_value
		if _visual_sequence_id(beat) != sequence:
			continue
		start_sec = minf(start_sec, float(beat.get("at", start_sec)))
		end_sec = maxf(
			end_sec,
			float(beat.get("at", end_sec)) + float(beat.get("duration", 0.0))
		)
	return clampf((video_time_sec - start_sec) / maxf(0.001, end_sec - start_sec), 0.0, 1.0)


func _visual_sequence_id(beat: Dictionary) -> String:
	var explicit := String(beat.get("visual_sequence", ""))
	if not explicit.is_empty():
		return explicit
	if String(beat.get("phase", "")) == "QUESTION":
		return "question:%s" % String(_camera_basis_beat(beat).get("id", ""))
	return ""


func _previous_camera_basis(beat: Dictionary) -> Dictionary:
	var beats: Array = episode.get("beats", [])
	var id := String(beat.get("id", ""))
	for index in range(beats.size()):
		if String(beats[index].get("id", "")) != id:
			continue
		for previous_index in range(index - 1, -1, -1):
			if String(beats[previous_index].get("camera_action", "reframe")) != "hold":
				return beats[previous_index]
		return {}
	return {}


func _previous_beat(beat: Dictionary) -> Dictionary:
	var beats: Array = episode.get("beats", [])
	var id := String(beat.get("id", ""))
	for index in range(beats.size()):
		if String(beats[index].get("id", "")) == id and index > 0:
			return beats[index - 1]
	return {}


func _camera_anchor_for_beat(beat: Dictionary) -> Vector2:
	var shot := String(beat.get("shot", ""))
	var focus_id := String(beat.get("focus", ""))
	match shot:
		"relation", "formula", "setup", "launch":
			return launch_position_px
		"follow":
			var focus_state: Dictionary = states_by_id.get(focus_id, {})
			if not focus_state.is_empty():
				return Vector2(focus_state["bird_position_px"])
		"landing":
			return EpisodeLayout.SOURCE_WORLD_RECT.get_center()
		"comparison", "takeaway":
			var points: PackedVector2Array = trajectories_by_id.get(focus_id, PackedVector2Array())
			if not points.is_empty():
				var bounds := Rect2(points[0], Vector2.ZERO)
				for point in points:
					bounds = bounds.expand(point)
				return bounds.get_center()
	return EpisodeLayout.SOURCE_WORLD_RECT.get_center()


func _has_layer(layer: String) -> bool:
	var layers: Array = current_beat.get("layers", [])
	return layer in layers


func _winner_emphasis_enabled() -> bool:
	return phase == "COMPARE" and _has_layer("results")
