extends "res://src/video/episode_canvas.gd"


func _draw_domain() -> void:
	_draw_impact_episode(String(current_beat.get("overlay", "")))

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
