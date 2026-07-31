extends "res://src/video/episode_canvas.gd"

const FormulaAsset = preload("res://src/video/formula_asset.gd")

const CONTENT_BOTTOM := 880.0
const FONT_ENVIRONMENT := 24
const FONT_SECONDARY := 28
const FONT_ESSENTIAL := 30
const FONT_DATA := 32
const RACE_BALL_CORE_RADIUS := 12.0
const RACE_BALL_HALO_RADIUS := 16.0
const RACE_BALL_RING_RADIUS := 18.0
const DISTANCE_TIME_REGION := Rect2(500, 175, 920, 470)
const SHORTEST_BET_REGION := Rect2(1450, 300, 370, 160)
const RAW_TRACK_BOUNDS := Rect2(330, 90, 1100, 790)
const OPENING_WORLD_SCALE := 0.94
const OPENING_WORLD_OFFSET := Vector2(50, 20)
const EXPLAIN_WORLD_SCALE := 0.78
const EXPLAIN_WORLD_OFFSET := Vector2(420, 90)
const TIME_WORLD_SCALE := 0.62
const TIME_WORLD_OFFSET := Vector2(-65, 135)
const SETUP_WORLD_SCALE := 0.90
const SETUP_WORLD_OFFSET := Vector2(-40, 70)
const FAIR_CONTROLS_NOTE_REGION := Rect2(1390, 185, 400, 585)
const RACE_CLOCK_REGION := Rect2(1445, 180, 385, 118)
const RACE_TELEMETRY_REGION := Rect2(1445, 330, 385, 292)
const ENERGY_FORMULA_BOUNDS := Rect2(105, 248, 440, 130)
const TIME_EXPLANATION_REGION := Rect2(1040, 145, 780, 650)
const TIME_MEASUREMENT_STRIP := Rect2(110, 730, 820, 110)
const TIME_FORMULA_BOUNDS := Rect2(1095, 315, 670, 170)
const TIME_ACCUMULATION_BASELINE_Y := 580.0
const CYCLOID_FORMULA_BOUNDS := Rect2(1280, 350, 570, 220)
const MODEL_BOUNDARY_NOTE_REGION := Rect2(1450, 175, 400, 565)


static func layout_audit_regions() -> Dictionary:
	return {
		"shortest-bet": [SHORTEST_BET_REGION],
		"distance-is-not-time": [Rect2(90, 190, 430, 390)],
		"energy-drop": [Rect2(70, 170, 530, 300)],
		"time-integral": [TIME_EXPLANATION_REGION, TIME_MEASUREMENT_STRIP],
		"fair-controls": [FAIR_CONTROLS_NOTE_REGION],
		"track-preview": [Rect2(520, 90, 1280, 55)],
		"race-release": [RACE_CLOCK_REGION, RACE_TELEMETRY_REGION],
		"race-separation": [RACE_CLOCK_REGION, RACE_TELEMETRY_REGION],
		"finish-slow-motion": [Rect2(1110, 180, 700, 290)],
		"arrival-lock": [Rect2(1460, 570, 380, 280)],
		"distance-time-table": [DISTANCE_TIME_REGION],
		"cycloid-generation": [Rect2(1260, 250, 600, 340), Rect2(850, 605, 440, 72)],
		"model-boundary": [MODEL_BOUNDARY_NOTE_REGION],
	}


static func track_plot_bounds(beat_id: String) -> Rect2:
	var scale_and_offset := _world_scale_and_offset(beat_id)
	var world_scale: float = scale_and_offset[0]
	var world_offset: Vector2 = scale_and_offset[1]
	return Rect2(
		RAW_TRACK_BOUNDS.position * world_scale + world_offset,
		RAW_TRACK_BOUNDS.size * world_scale
	)


static func formula_audit_regions() -> Dictionary:
	return {
		"energy": ENERGY_FORMULA_BOUNDS,
		"velocity": ENERGY_FORMULA_BOUNDS,
		"time": TIME_FORMULA_BOUNDS,
		"cycloid": CYCLOID_FORMULA_BOUNDS,
	}


static func _world_scale_and_offset(beat_id: String) -> Array:
	if beat_id in ["cold-open", "shortest-bet"]:
		return [OPENING_WORLD_SCALE, OPENING_WORLD_OFFSET]
	if beat_id in ["distance-is-not-time", "energy-drop"]:
		return [EXPLAIN_WORLD_SCALE, EXPLAIN_WORLD_OFFSET]
	if beat_id == "time-integral":
		return [TIME_WORLD_SCALE, TIME_WORLD_OFFSET]
	if beat_id in ["fair-controls", "track-preview"]:
		return [SETUP_WORLD_SCALE, SETUP_WORLD_OFFSET]
	return [1.0, Vector2.ZERO]


func _configure_domain_geometry(_preset: Dictionary) -> void:
	pass


func _draw_background() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	draw_rect(Rect2(Vector2.ZERO, EpisodeLayout.CANVAS_SIZE), colors["background"], true)


func _configure_record(record: Dictionary) -> void:
	var points := PackedVector2Array()
	for value in record.get("path_points_px", []):
		points.append(_vector(value))
	trajectories_by_id[record["variant_id"]] = points


func _draw_domain() -> void:
	var beat_id := String(current_beat.get("id", ""))
	match beat_id:
		"cold-open":
			_draw_opening_teaser()
		"shortest-bet":
			_draw_tracks("line", true)
			_draw_shortest_bet()
		"distance-is-not-time":
			_draw_tracks("line", true)
			_draw_distance_is_not_time()
		"energy-drop":
			_draw_tracks()
			_draw_energy_explanation()
		"time-integral":
			_draw_time_integral()
		"fair-controls":
			_draw_tracks("", false, 1.0, false)
			_draw_fair_controls()
		"track-preview":
			var preview_focus := _track_preview_focus()
			_draw_tracks(preview_focus, not preview_focus.is_empty())
			_draw_track_preview()
		"race-release", "race-separation":
			_draw_tracks()
			_draw_racing_balls()
			_draw_live_race_clock()
			_draw_race_telemetry()
		"finish-slow-motion":
			_draw_tracks()
			_draw_racing_balls()
			_draw_finish_magnifier()
		"arrival-lock":
			_draw_tracks()
			_draw_racing_balls()
			_draw_finish_arrivals(true)
		"distance-time-table":
			_draw_distance_time_results()
		"cycloid-generation":
			_draw_cycloid_generation()
		"model-boundary":
			# Keep the path as a quiet visual callback, without endpoint labels that
			# compete with (or clip beneath) the closing question.
			_draw_tracks("", false, 1.0, false)
			_draw_model_boundary()
		_:
			_draw_tracks()
			match phase:
				"QUESTION":
					_draw_question_prompt()
				"EXPLAIN":
					_draw_energy_explanation()
				"SETUP":
					_draw_setup_labels()
				"FLIGHT":
					_draw_racing_balls()
					_draw_finish_arrivals()
				"COMPARE":
					_draw_arrival_results()


func _draw_tracks(
	focus_id: String = "",
	dim_others: bool = false,
	reveal_progress: float = 1.0,
	draw_endpoints: bool = true
) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var points: PackedVector2Array = _display_points(
			trajectories_by_id.get(id, PackedVector2Array())
		)
		points = _partial_polyline(points, reveal_progress)
		if points.size() < 2:
			continue
		var color: Color = colors_by_id.get(id, colors["muted"])
		var focused := focus_id.is_empty() or id == focus_id
		var alpha := 0.76 if focused else (0.16 if dim_others else 0.38)
		var width := 9.0 if not focus_id.is_empty() and id == focus_id else 7.0
		# A quiet outer rail makes the constraint visible: these are fixed guides,
		# not free-flight trajectories. Keep it subordinate to the color identity.
		draw_polyline(points, Color(colors["divider"], alpha * 0.72), width + 8.0, true)
		draw_polyline(points, Color(color, alpha), width, true)
		draw_polyline(points, Color(colors["text"], 0.18), 2.0, true)
	var first_record: Dictionary = bundle.get("records", [{}])[0]
	var first_path: Array = first_record.get("path_points_px", [])
	if draw_endpoints and first_path.size() >= 2 and reveal_progress > 0.08:
		var start := _display_position(_vector(first_path[0]))
		var finish := _display_position(_vector(first_path[-1]))
		var marker_alpha := smoothstep(0.08, 0.24, reveal_progress)
		_draw_track_endpoint(start, "START", marker_alpha, false)
		if reveal_progress > 0.78:
			var finish_alpha := smoothstep(0.78, 0.96, reveal_progress)
			_draw_track_endpoint(finish, "FINISH", finish_alpha, true)


func _draw_track_endpoint(position: Vector2, label: String, alpha: float, is_finish: bool) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var marker_color := Color(colors["muted"], 0.90 * alpha)
	draw_circle(position, 7.0, Color(colors["background"], 0.96 * alpha))
	draw_arc(position, 8.0, 0.0, TAU, 28, marker_color, 2.5, true)
	if is_finish:
		draw_line(position + Vector2(-26, 23), position + Vector2(26, 23), marker_color, 2.0, true)
		draw_string(
			VideoTypography.data(), position + Vector2(-50, 51), label,
			HORIZONTAL_ALIGNMENT_CENTER, 100, FONT_ENVIRONMENT, marker_color
		)
	else:
		draw_line(position + Vector2(-26, -23), position + Vector2(26, -23), marker_color, 2.0, true)
		draw_string(
			VideoTypography.data(), position + Vector2(-50, -34), label,
			HORIZONTAL_ALIGNMENT_CENTER, 100, FONT_ENVIRONMENT, marker_color
		)


func _draw_opening_teaser() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var track_reveal := smoothstep(0.02, 0.24, progress)
	var race_progress := smoothstep(0.14, 0.78, progress)
	var preview_time := 1.60 * race_progress

	# Draw the anticipation pulse behind the finish marker and its label.
	if progress > 0.66:
		var finish := _finish_position()
		var pulse := 0.5 + 0.5 * sin(progress * TAU * 5.0)
		var alpha := smoothstep(0.66, 0.86, progress)
		draw_arc(finish, 34.0 + 18.0 * pulse, -PI * 0.5, PI * 0.5, 28, Color(colors["accent"], 0.42 * alpha), 4.0, true)
		draw_arc(finish, 58.0 + 24.0 * pulse, -PI * 0.5, PI * 0.5, 28, Color(colors["text"], 0.16 * alpha), 3.0, true)
	_draw_tracks("", false, track_reveal)
	_draw_opening_trails(preview_time, race_progress)
	_draw_racing_balls(_preview_states(preview_time))

	# The voice ends near 10 seconds. Preserve a short prediction hold, then use
	# the remaining cold-open time for the same series-identification cadence as EP04.
	var brand_start := 0.77
	if progress >= brand_start:
		var brand_progress := clampf((progress - brand_start) / (1.0 - brand_start), 0.0, 1.0)
		var scrim_alpha := smoothstep(0.0, 0.20, brand_progress)
		draw_rect(Rect2(Vector2.ZERO, EpisodeLayout.CANVAS_SIZE), Color(colors["background"], scrim_alpha), true)
		_draw_track_brand_stinger(brand_progress)


func _draw_track_brand_stinger(progress: float) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var accent: Color = colors["accent"]
	var center := Vector2(960, 420)
	var fork_alpha := smoothstep(0.08, 0.30, progress) * (1.0 - smoothstep(0.94, 1.0, progress))
	var launch := smoothstep(0.34, 0.68, progress)
	var fork_base := center + Vector2(-170, 205)
	var fork_left := center + Vector2(-300, -165)
	var fork_right := center + Vector2(30, -165)
	draw_line(fork_base, fork_left, Color(colors["text"], 0.82 * fork_alpha), 18.0, true)
	draw_line(fork_base, fork_right, Color(colors["text"], 0.82 * fork_alpha), 18.0, true)
	var pocket := center + Vector2(-500 + 330 * launch, -5)
	draw_line(fork_left, pocket, Color(accent, 0.96 * fork_alpha), 8.0, true)
	draw_line(fork_right, pocket, Color(accent, 0.96 * fork_alpha), 8.0, true)
	var ball_position := pocket.lerp(center + Vector2(440, -25), launch)
	for trail_index in range(1, 4):
		var trail_progress := clampf(launch - trail_index * 0.08, 0.0, 1.0)
		var trail_position := pocket.lerp(center + Vector2(440, -25), trail_progress)
		draw_circle(trail_position, 22.0 - trail_index * 4.0, Color(accent, maxf(0.0, 0.16 - trail_index * 0.035)))
	draw_circle(ball_position, 25.0, Color(accent, 0.98 * fork_alpha))
	if launch > 0.25:
		var ring := smoothstep(0.30, 0.72, launch)
		draw_arc(center + Vector2(440, -25), lerpf(12.0, 145.0, ring), 0.0, TAU, 54, Color(accent, 0.68 * (1.0 - ring)), 5.0, true)
	# Give the wordmark a readable hold before the beat cuts back to the lesson.
	var brand_alpha := smoothstep(0.42, 0.60, progress)
	draw_string(VideoTypography.bold(), Vector2(560, 720), "物理实验室", HORIZONTAL_ALIGNMENT_CENTER, 800, 54, Color(colors["text"], brand_alpha))
	draw_string(VideoTypography.data(), Vector2(660, 780), "SLINGSHOT PHYSICS", HORIZONTAL_ALIGNMENT_CENTER, 600, 29, Color(colors["muted"], brand_alpha * 0.90))
	draw_string(VideoTypography.data(), Vector2(710, 838), "最速降线", HORIZONTAL_ALIGNMENT_CENTER, 500, 27, Color(accent, brand_alpha * 0.88))


func _draw_opening_trails(time_sec: float, race_progress: float) -> void:
	if race_progress <= 0.02:
		return
	for sample_index in range(7, 0, -1):
		var sample_time := maxf(0.0, time_sec - sample_index * 0.045)
		var sampled := _preview_states(sample_time)
		var alpha := (1.0 - float(sample_index) / 8.0) * 0.16 * race_progress
		for variant_value in episode["variants"]:
			var id := String(variant_value["id"])
			var state: Dictionary = sampled.get(id, {})
			if state.is_empty():
				continue
			draw_circle(
				_display_position(state["position_px"]), 6.0 + 0.6 * sample_index,
				Color(colors_by_id.get(id, Color.WHITE), alpha)
			)


func _partial_polyline(points: PackedVector2Array, progress: float) -> PackedVector2Array:
	if points.size() < 2 or progress >= 1.0:
		return points
	if progress <= 0.0:
		return PackedVector2Array()
	var total_length := 0.0
	for index in range(1, points.size()):
		total_length += points[index - 1].distance_to(points[index])
	var target_length := total_length * progress
	var consumed := 0.0
	var result := PackedVector2Array([points[0]])
	for index in range(1, points.size()):
		var segment_length := points[index - 1].distance_to(points[index])
		if consumed + segment_length >= target_length:
			var weight := (target_length - consumed) / maxf(segment_length, 0.001)
			result.append(points[index - 1].lerp(points[index], weight))
			break
		result.append(points[index])
		consumed += segment_length
	return result


func _draw_shortest_bet() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var record: Dictionary = records_by_id.get("line", {})
	var length := float(record.get("metrics", {}).get("path_length_m", 0.0))
	var reveal := smoothstep(0.16, 0.44, _beat_progress())
	var region := SHORTEST_BET_REGION
	region.position.x += 50.0 * (1.0 - reveal)
	draw_rect(Rect2(region.position, Vector2(42, 4)), Color(colors_by_id.get("line", colors["accent"]), reveal), true)
	draw_string(VideoTypography.medium(), region.position + Vector2(0, 50), "几何最短", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(colors["muted"], reveal))
	draw_string(VideoTypography.bold(), region.position + Vector2(0, 118), "直线  %.3f m" % (length * reveal), HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(colors["text"], reveal))
	var line_points: PackedVector2Array = _display_points(trajectories_by_id.get("line", PackedVector2Array()))
	line_points = _partial_polyline(line_points, smoothstep(0.04, 0.62, _beat_progress()))
	if line_points.size() >= 2:
		draw_polyline(line_points, Color(colors_by_id.get("line", colors["accent"]), 0.94), 11.0, true)


func _draw_distance_is_not_time() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var record: Dictionary = records_by_id.get("line", {})
	var metrics: Dictionary = record.get("metrics", {})
	var progress := _beat_progress()
	var length_alpha := smoothstep(0.05, 0.25, progress)
	var time_alpha := smoothstep(0.34, 0.58, progress)
	var line_color: Color = colors_by_id.get("line", colors["text"])
	# These are two observations in one argument, not two independent cards.
	# Short rules and shared alignment keep the track as the dominant object.
	draw_rect(Rect2(90, 210, 5, 118), Color(line_color, length_alpha), true)
	draw_string(VideoTypography.medium(), Vector2(120, 245), "几何距离", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, Color(colors["muted"], length_alpha))
	draw_string(VideoTypography.bold(), Vector2(120, 315), "%.3f m" % float(metrics.get("path_length_m", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color(line_color, length_alpha))
	draw_rect(Rect2(90, 410, 5, 118), Color(colors["accent"], time_alpha), true)
	draw_string(VideoTypography.medium(), Vector2(120, 445), "实际用时", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, Color(colors["muted"], time_alpha))
	draw_string(VideoTypography.bold(), Vector2(120, 515), "%.3f s" % float(metrics.get("arrival_time_sec", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color(colors["accent"], time_alpha))


func _draw_question_prompt() -> void:
	pass


func _draw_energy_explanation() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var preview_time := lerpf(0.28, 1.18, progress)
	var preview := _preview_states(preview_time)
	# Draw the moving evidence first; the explanatory column remains spatially
	# separate, so it needs hierarchy rather than an enclosing card.
	_draw_racing_balls(preview)
	draw_rect(Rect2(105, 178, 42, 4), Color(colors["accent"], smoothstep(0.05, 0.30, progress)), true)
	draw_string(
		VideoTypography.bold(), Vector2(105, 225), "先下降，先获得速度",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(colors["text"], smoothstep(0.05, 0.35, progress))
	)
	var energy_alpha := smoothstep(0.12, 0.25, progress) * (1.0 - smoothstep(0.30, 0.42, progress))
	var velocity_alpha := smoothstep(0.32, 0.46, progress)
	_draw_typst_formula(0, ENERGY_FORMULA_BOUNDS, Color(colors["accent"], energy_alpha))
	_draw_typst_formula(1, ENERGY_FORMULA_BOUNDS, Color(colors["accent"], velocity_alpha))
	draw_string(
		VideoTypography.medium(), Vector2(105, 438), "y：相对起点的下降高度",
		HORIZONTAL_ALIGNMENT_LEFT, 430, FONT_ENVIRONMENT,
		Color(colors["muted"], velocity_alpha * 0.90)
	)
	var bar_x := 1470.0
	var bar_y := 260.0
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var state: Dictionary = preview.get(id, {})
		var speed := float(state.get("speed_mps", 0.0))
		var color: Color = colors_by_id.get(id, colors["muted"])
		draw_string(VideoTypography.medium(), Vector2(bar_x, bar_y), String(variant["label"]), HORIZONTAL_ALIGNMENT_LEFT, 100, FONT_ESSENTIAL, colors["text"])
		draw_rect(Rect2(bar_x + 100, bar_y - 22, 210, 24), Color(colors["divider"], 0.42), true)
		draw_rect(Rect2(bar_x + 100, bar_y - 22, 210.0 * speed / 11.5, 24), color, true)
		draw_string(VideoTypography.data(), Vector2(bar_x + 325, bar_y), "%.1f m/s" % speed, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, color)
		bar_y += 76.0


func _draw_time_integral() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var record: Dictionary = records_by_id.get("cycloid", {})
	var segments: Array = record.get("path_segments", [])
	if segments.is_empty():
		return
	var progress := _beat_progress()
	var reveal := smoothstep(0.08, 0.82, progress)
	var reveal_position := reveal * float(segments.size())
	var completed_count := clampi(floori(reveal_position), 0, segments.size())
	var active_index := mini(completed_count, segments.size() - 1)
	var active_fraction := 1.0 if completed_count >= segments.size() else reveal_position - floorf(reveal_position)
	var cycloid_color: Color = colors_by_id.get("cycloid", colors["accent"])

	# Establish the complete route first, then let completed time accumulate over it.
	for index in range(segments.size()):
		var segment: Dictionary = segments[index]
		var start := _display_position(_vector(segment["start_px"]))
		var finish := _display_position(_vector(segment["finish_px"]))
		draw_line(start, finish, Color(colors["muted"], 0.22), 5.0, true)
		if index % 4 == 0:
			draw_circle(start, 3.5, Color(colors["muted"], 0.48))

	var accumulated_time := 0.0
	for index in range(completed_count):
		var segment: Dictionary = segments[index]
		accumulated_time += float(segment["segment_time_sec"])
		draw_line(
			_display_position(_vector(segment["start_px"])),
			_display_position(_vector(segment["finish_px"])),
			Color(cycloid_color, 0.82), 9.0, true
		)

	var active_segment: Dictionary = segments[active_index]
	var active_start := _display_position(_vector(active_segment["start_px"]))
	var active_finish := _display_position(_vector(active_segment["finish_px"]))
	var marker_position := active_start.lerp(active_finish, active_fraction)
	if completed_count < segments.size():
		accumulated_time += float(active_segment["segment_time_sec"]) * active_fraction
		draw_line(active_start, marker_position, cycloid_color, 13.0, true)
	var pulse := 0.5 + 0.5 * sin(progress * TAU * 10.0)
	draw_circle(marker_position, 21.0 + 4.0 * pulse, Color(cycloid_color, 0.12 + 0.08 * pulse))
	draw_circle(marker_position, 12.0, cycloid_color)
	draw_arc(marker_position, 17.0, 0.0, TAU, 32, Color(colors["background"], 0.90), 3.0, true)

	var path_alpha := smoothstep(0.04, 0.18, progress)
	draw_string(
		VideoTypography.medium(), Vector2(115, 175), "路径分成 48 个小段",
		HORIZONTAL_ALIGNMENT_LEFT, 760, 34, Color(colors["text"], path_alpha)
	)

	var metric_alpha := smoothstep(0.10, 0.24, progress)
	var metric_labels := ["当前 ds", "当地 v(s)", "这一段 Δt"]
	var metric_values := [
		"%.3f m" % float(active_segment["segment_length_m"]),
		"%.2f m/s" % float(active_segment["mean_speed_mps"]),
		"%.1f ms" % (float(active_segment["segment_time_sec"]) * 1000.0),
	]
	for index in range(metric_labels.size()):
		var metric_x := TIME_MEASUREMENT_STRIP.position.x + 28.0 + index * 265.0
		draw_rect(Rect2(metric_x, 742, 34, 3), Color(cycloid_color, metric_alpha * 0.82), true)
		draw_string(VideoTypography.medium(), Vector2(metric_x, 772), metric_labels[index], HORIZONTAL_ALIGNMENT_LEFT, 220, FONT_SECONDARY, Color(colors["muted"], metric_alpha))
		draw_string(VideoTypography.data(), Vector2(metric_x, 817), metric_values[index], HORIZONTAL_ALIGNMENT_LEFT, 220, FONT_DATA, Color(cycloid_color, metric_alpha))

	draw_rect(Rect2(TIME_EXPLANATION_REGION.position + Vector2(44, 18), Vector2(44, 4)), cycloid_color, true)
	draw_string(VideoTypography.bold(), TIME_EXPLANATION_REGION.position + Vector2(44, 70), "每一小段，都要花时间", HORIZONTAL_ALIGNMENT_LEFT, -1, 42, colors["text"])
	draw_string(VideoTypography.medium(), TIME_EXPLANATION_REGION.position + Vector2(44, 137), "Δt  ≈  ds ÷ v(s)", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, colors["muted"])
	_draw_typst_formula(2, TIME_FORMULA_BOUNDS, Color(colors["accent"], smoothstep(0.20, 0.38, progress)))
	draw_line(Vector2(1085, 520), Vector2(1775, 520), Color(colors["divider"], 0.58), 2.0)
	draw_string(VideoTypography.medium(), Vector2(1085, TIME_ACCUMULATION_BASELINE_Y), "沿路径累计", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["muted"])
	draw_string(VideoTypography.data(), Vector2(1515, TIME_ACCUMULATION_BASELINE_Y), "T = %.3f s" % accumulated_time, HORIZONTAL_ALIGNMENT_RIGHT, 260, 42, cycloid_color)
	var arrival_time := float(record.get("metrics", {}).get("arrival_time_sec", 1.0))
	var accumulation_ratio := clampf(accumulated_time / maxf(arrival_time, 1.0e-6), 0.0, 1.0)
	draw_rect(Rect2(1085, 615, 690, 18), Color(colors["divider"], 0.42), true)
	draw_rect(Rect2(1085, 615, 690.0 * accumulation_ratio, 18), cycloid_color, true)
	draw_circle(Vector2(1085 + 690.0 * accumulation_ratio, 624), 10.0, cycloid_color)
	draw_string(VideoTypography.medium(), Vector2(1085, 715), "更长的路，也可能用更高的速度走完", HORIZONTAL_ALIGNMENT_LEFT, 690, FONT_ESSENTIAL, colors["text"])


func _draw_setup_labels() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var y := 205.0
	var index := 0
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var color: Color = colors_by_id[variant["id"]]
		var x := 480.0 + float(index) * 360.0
		draw_circle(Vector2(x, y), 9.0, color)
		draw_string(VideoTypography.medium(), Vector2(x + 20, y + 10), variant["label"], HORIZONTAL_ALIGNMENT_LEFT, 280, FONT_ESSENTIAL, colors["text"])
		index += 1
	draw_string(
		VideoTypography.data(), Vector2(520, 860), "三条固定导轨 · 同一起点 · 同一终点 · 无摩擦滑动质点",
		HORIZONTAL_ALIGNMENT_CENTER, 880, 30, colors["muted"]
	)


func _draw_fair_controls() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var first_record: Dictionary = bundle.get("records", [{}])[0]
	var path: Array = first_record.get("path_points_px", [])
	if path.size() < 2:
		return

	var start := _display_position(_vector(path[0]))
	var finish := _display_position(_vector(path[-1]))
	var start_alpha := smoothstep(0.02, 0.16, progress)
	var finish_alpha := smoothstep(0.16, 0.32, progress)
	_draw_fair_endpoint(start, "同一起点", start_alpha, false, progress)
	_draw_fair_endpoint(finish, "同一终点", finish_alpha, true, progress)

	# Environment information is expressed by the field itself, rather than by a
	# detached card. The arrow grows with the narration and stays visually quiet.
	var gravity_alpha := smoothstep(0.30, 0.46, progress)
	var gravity_start := Vector2(1450, 252)
	var gravity_finish := gravity_start.lerp(Vector2(1450, 426), gravity_alpha)
	draw_string(
		VideoTypography.medium(), Vector2(1410, 215), "相同重力",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(colors["text"], gravity_alpha)
	)
	if gravity_alpha > 0.001:
		_draw_gravity_vector(
			gravity_start,
			gravity_finish,
			Color(colors["accent"], 0.82 * gravity_alpha),
			gravity_alpha
		)
	draw_string(
		VideoTypography.data(), Vector2(1490, 340), "g",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(colors["accent"], gravity_alpha)
	)
	draw_string(
		VideoTypography.data(), Vector2(1490, 390), "9.81 m/s²",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SECONDARY, Color(colors["muted"], gravity_alpha)
	)

	# The rail itself carries the constraint: briefly brighten all guides as the
	# model assumptions appear, then let the highlight settle back.
	var rail_reveal := smoothstep(0.46, 0.62, progress)
	var rail_settle := 1.0 - 0.55 * smoothstep(0.72, 0.92, progress)
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var points := _display_points(trajectories_by_id.get(String(variant["id"]), PackedVector2Array()))
		if points.size() >= 2:
			draw_polyline(points, Color(colors["text"], 0.24 * rail_reveal * rail_settle), 4.0, true)

	var assumptions_alpha := smoothstep(0.52, 0.66, progress)
	draw_string(
		VideoTypography.medium(), Vector2(1410, 525), "模型假设",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ENVIRONMENT, Color(colors["muted"], assumptions_alpha)
	)
	var assumptions := ["固定导轨", "无摩擦与空气阻力", "滑动质点"]
	for index in range(assumptions.size()):
		var item_alpha := smoothstep(0.58 + index * 0.09, 0.70 + index * 0.09, progress)
		var baseline := Vector2(1410, 590 + index * 66)
		draw_circle(baseline + Vector2(7, -10), 4.5, Color(colors["accent"], item_alpha))
		draw_string(
			VideoTypography.medium(), baseline + Vector2(28, 0), assumptions[index],
			HORIZONTAL_ALIGNMENT_LEFT, 340, FONT_ESSENTIAL, Color(colors["text"], item_alpha)
		)


func _draw_gravity_vector(start: Vector2, finish: Vector2, color: Color, reveal: float) -> void:
	# An open, narrow arrowhead reads as a measured vector. The shared endpoint
	# and round cap keep it lighter than the filled arrows used for active forces.
	var stem_width := 3.0
	var direction := (finish - start).normalized()
	if direction.is_zero_approx():
		return
	var normal := Vector2(-direction.y, direction.x)
	var head_length := 14.0
	var head_half_width := 8.0
	draw_line(start, finish, color, stem_width, true)
	draw_circle(start, stem_width * 0.5, color)
	if reveal > 0.12:
		var shoulder := finish - direction * head_length
		draw_line(finish, shoulder + normal * head_half_width, color, stem_width, true)
		draw_line(finish, shoulder - normal * head_half_width, color, stem_width, true)


func _draw_fair_endpoint(
	position: Vector2,
	label: String,
	alpha: float,
	is_finish: bool,
	progress: float
) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var pulse_phase := fmod(progress * 3.0 + (0.45 if is_finish else 0.0), 1.0)
	var pulse_alpha := (1.0 - pulse_phase) * alpha
	draw_circle(position, 6.0, Color(colors["background"], 0.96 * alpha))
	draw_arc(position, 9.0, 0.0, TAU, 32, Color(colors["text"], 0.84 * alpha), 2.5, true)
	draw_arc(position, 18.0 + 18.0 * pulse_phase, 0.0, TAU, 40, Color(colors["accent"], 0.32 * pulse_alpha), 3.0, true)
	var label_position := position + (Vector2(-72, 62) if is_finish else Vector2(-90, -42))
	draw_string(
		VideoTypography.medium(), label_position, label,
		HORIZONTAL_ALIGNMENT_CENTER, 180, FONT_ESSENTIAL, Color(colors["text"], alpha)
	)


func _draw_track_preview() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var reveal_starts := [0.03, 0.32, 0.54]
	var x := 520.0
	for index in range(episode["variants"].size()):
		var variant_value = episode["variants"][index]
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var record: Dictionary = records_by_id.get(id, {})
		var color: Color = colors_by_id.get(id, colors["muted"])
		var alpha := smoothstep(float(reveal_starts[index]), float(reveal_starts[index]) + 0.14, progress)
		draw_circle(Vector2(x, 115), 8.0, Color(color, alpha))
		draw_string(VideoTypography.medium(), Vector2(x + 18, 125), String(variant["label"]), HORIZONTAL_ALIGNMENT_LEFT, 110, FONT_ESSENTIAL, Color(colors["text"], alpha))
		draw_string(VideoTypography.data(), Vector2(x + 128, 125), "%.3f m" % float(record.get("metrics", {}).get("path_length_m", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, Color(color, alpha))
		x += 430.0


func _track_preview_focus() -> String:
	var progress := _beat_progress()
	if progress < 0.31:
		return "line"
	if progress < 0.53:
		return "circular-arc"
	if progress < 0.75:
		return "cycloid"
	return ""


func _draw_racing_balls(source_states: Dictionary = {}) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var states := states_by_id if source_states.is_empty() else source_states
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var state: Dictionary = states.get(id, {})
		if state.is_empty():
			continue
		var position: Vector2 = _display_position(state["position_px"])
		var color: Color = colors_by_id[id]
		if bool(state.get("arrived", false)):
			var rank := _arrival_rank(id)
			draw_arc(
				position, RACE_BALL_RING_RADIUS + float(rank) * 5.0, 0.0, TAU, 40,
				Color(color, 0.92), 3.0, true
			)
			continue
		draw_circle(position, RACE_BALL_HALO_RADIUS, Color(colors["background"], 0.9))
		draw_circle(position, RACE_BALL_CORE_RADIUS, color)
		draw_arc(position, RACE_BALL_RING_RADIUS, 0.0, TAU, 32, Color(color, 0.55), 2.5, true)


func _draw_finish_arrivals(force_all: bool = false) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var rows := _sorted_arrival_rows()
	var arrived_rows: Array = []
	for row_value in rows:
		var row: Dictionary = row_value
		var state: Dictionary = states_by_id.get(String(row["variant_id"]), {})
		if force_all or bool(state.get("arrived", false)):
			arrived_rows.append(row)
	if arrived_rows.is_empty():
		return
	var panel := Rect2(1460, 570, 380, 76 + arrived_rows.size() * 68)
	draw_rect(Rect2(panel.position + Vector2(24, 8), Vector2(38, 3)), Color(colors["accent"], 0.84), true)
	draw_string(
		VideoTypography.medium(), panel.position + Vector2(24, 46), "到达锁定",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["muted"]
	)
	for index in range(arrived_rows.size()):
		var row: Dictionary = arrived_rows[index]
		var color: Color = colors_by_id.get(String(row["variant_id"]), colors["muted"])
		var baseline := panel.position + Vector2(24, 98 + index * 68)
		draw_string(
			VideoTypography.data(), baseline, "%d" % (index + 1),
			HORIZONTAL_ALIGNMENT_LEFT, 30, FONT_SECONDARY, colors["muted"]
		)
		draw_circle(baseline + Vector2(50, -9), 7.0, color)
		draw_string(
			VideoTypography.medium(), baseline + Vector2(70, 0), String(row["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, 125, FONT_ESSENTIAL, colors["text"]
		)
		draw_string(
			VideoTypography.data(), baseline + Vector2(215, 0), "%.3f s" % float(row["value"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, color
		)


func _draw_live_race_clock() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var simulation_time := 0.0
	if not simulation_times_by_id.is_empty():
		simulation_time = float(simulation_times_by_id.values()[0])
	var panel := RACE_CLOCK_REGION
	draw_rect(Rect2(panel.position + Vector2(24, 4), Vector2(36, 3)), Color(colors["text"], 0.62), true)
	draw_string(VideoTypography.medium(), panel.position + Vector2(24, 42), "物理时间", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SECONDARY, colors["muted"])
	draw_string(VideoTypography.data(), panel.position + Vector2(24, 92), "%06.3f s" % simulation_time, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, colors["text"])


func _draw_race_telemetry() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var panel := RACE_TELEMETRY_REGION
	draw_rect(Rect2(panel.position + Vector2(24, 5), Vector2(36, 3)), Color(colors["text"], 0.62), true)
	draw_string(
		VideoTypography.medium(), panel.position + Vector2(24, 44), "实时速度",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SECONDARY, colors["muted"]
	)
	var baseline_y := panel.position.y + 104.0
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var state: Dictionary = states_by_id.get(id, {})
		var color: Color = colors_by_id.get(id, colors["muted"])
		var speed := float(state.get("speed_mps", 0.0))
		draw_circle(Vector2(panel.position.x + 30, baseline_y - 9), 7.0, color)
		draw_string(
			VideoTypography.medium(), Vector2(panel.position.x + 52, baseline_y),
			String(variant["label"]), HORIZONTAL_ALIGNMENT_LEFT, 110,
			FONT_ESSENTIAL, colors["text"]
		)
		draw_rect(
			Rect2(panel.position.x + 145, baseline_y - 25, 78, 20),
			Color(colors["divider"], 0.42), true
		)
		draw_rect(
			Rect2(panel.position.x + 145, baseline_y - 25, 78.0 * speed / 11.5, 20),
			color, true
		)
		draw_string(
			VideoTypography.data(), Vector2(panel.position.x + 236, baseline_y),
			"%.1f m/s" % speed, HORIZONTAL_ALIGNMENT_RIGHT, 120,
			FONT_SECONDARY, color
		)
		baseline_y += 58.0


func _draw_finish_magnifier() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var panel := Rect2(1110, 180, 700, 290)
	draw_rect(Rect2(panel.position + Vector2(28, 5), Vector2(42, 3)), Color(colors["accent"], 0.86), true)
	draw_string(
		VideoTypography.bold(), panel.position + Vector2(28, 48), "终点附近",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 34, colors["text"]
	)
	draw_string(
		VideoTypography.data(), panel.position + Vector2(348, 46), "沿轨道展开 · 8× 回放",
		HORIZONTAL_ALIGNMENT_RIGHT, 324, FONT_ENVIRONMENT, colors["muted"]
	)
	var compared_ids := ["cycloid", "circular-arc"]
	var local_window_m := 0.50
	var rail_start_x := panel.position.x + 150.0
	var rail_finish_x := panel.position.x + 470.0
	for index in range(compared_ids.size()):
		var id: String = compared_ids[index]
		var state: Dictionary = states_by_id.get(id, {})
		var record: Dictionary = records_by_id.get(id, {})
		if state.is_empty() or record.is_empty():
			continue
		var y := panel.position.y + 116.0 + float(index) * 58.0
		var color: Color = colors_by_id.get(id, colors["muted"])
		var label := "摆线" if id == "cycloid" else "圆弧"
		var path_length := float(record.get("metrics", {}).get("path_length_m", 0.0))
		var traveled := float(state.get("distance_traveled_m", 0.0))
		var remaining_m := maxf(0.0, path_length - traveled)
		var remaining_ratio := clampf(remaining_m / local_window_m, 0.0, 1.0)
		var ball_x := lerpf(rail_finish_x, rail_start_x, remaining_ratio)
		draw_circle(Vector2(panel.position.x + 38, y), 6.0, color)
		draw_string(
			VideoTypography.medium(), Vector2(panel.position.x + 56, y + 9),
			label, HORIZONTAL_ALIGNMENT_LEFT, 86,
			FONT_SECONDARY, colors["text"]
		)
		draw_line(
			Vector2(rail_start_x, y), Vector2(rail_finish_x, y),
			Color(colors["divider"], 0.64), 3.0, true
		)
		draw_circle(Vector2(rail_finish_x, y), 6.0, Color(colors["background"], 0.96))
		draw_arc(
			Vector2(rail_finish_x, y), 7.0, 0.0, TAU, 24,
			Color(colors["muted"], 0.82), 2.0, true
		)
		draw_circle(Vector2(ball_x, y), 8.0, color)
		var arrival_time := float(record.get("metrics", {}).get("arrival_time_sec", 0.0))
		draw_string(
			VideoTypography.data(), Vector2(panel.position.x + 500, y + 10),
			"%.3f s" % arrival_time, HORIZONTAL_ALIGNMENT_RIGHT, 166,
			FONT_SECONDARY, color
		)
	var rows := _sorted_arrival_rows()
	if rows.size() >= 2:
		var delta_ms := (float(rows[1]["value"]) - float(rows[0]["value"])) * 1000.0
		var result_alpha := smoothstep(0.28, 0.50, _beat_progress())
		draw_string(
			VideoTypography.data(), panel.position + Vector2(28, 258),
			"真实到达时间差", HORIZONTAL_ALIGNMENT_LEFT, 260,
			FONT_ENVIRONMENT, Color(colors["muted"], result_alpha)
		)
		draw_string(
			VideoTypography.bold(), panel.position + Vector2(440, 260),
			"%.1f ms" % delta_ms, HORIZONTAL_ALIGNMENT_RIGHT, 226,
			FONT_ESSENTIAL, Color(colors["accent"], result_alpha)
		)


func _draw_arrival_results() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var sorted := _sorted_arrival_rows()
	var panel := Rect2(1160, 210, 640, 360)
	draw_rect(Rect2(panel.position + Vector2(35, 8), Vector2(42, 3)), Color(colors["accent"], 0.84), true)
	draw_string(VideoTypography.bold(), panel.position + Vector2(35, 58), "到达时间", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, colors["text"])
	for index in range(sorted.size()):
		var row: Dictionary = sorted[index]
		var y := panel.position.y + 125.0 + float(index) * 72.0
		var color: Color = colors_by_id.get(String(row["variant_id"]), colors["muted"])
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 36, y), "%d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["muted"])
		draw_circle(Vector2(panel.position.x + 88, y - 9), 7.0, color)
		draw_string(VideoTypography.medium(), Vector2(panel.position.x + 112, y), String(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, 250, FONT_DATA, colors["text"])
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 425, y), "%.3f s" % float(row["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_DATA, color)


func _draw_distance_time_results() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var rows := _sorted_arrival_rows()
	var panel := DISTANCE_TIME_REGION
	var progress := _beat_progress()
	var identity_alpha := smoothstep(0.04, 0.16, progress)
	var length_alpha := smoothstep(0.16, 0.32, progress)
	var time_alpha := smoothstep(0.34, 0.50, progress)
	var conclusion_alpha := smoothstep(0.54, 0.70, progress)
	draw_rect(Rect2(panel.position + Vector2(42, 10), Vector2(44, 4)), Color(colors["accent"], identity_alpha), true)
	draw_string(VideoTypography.bold(), panel.position + Vector2(42, 68), "路径与时间，是两种排序", HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color(colors["text"], identity_alpha))
	draw_string(VideoTypography.medium(), panel.position + Vector2(420, 145), "路径长度", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, Color(colors["muted"], length_alpha))
	draw_string(VideoTypography.medium(), panel.position + Vector2(680, 145), "到达时间", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, Color(colors["muted"], time_alpha))
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var id := String(row["variant_id"])
		var record: Dictionary = records_by_id.get(id, {})
		var color: Color = colors_by_id.get(id, colors["muted"])
		var y := panel.position.y + 225.0 + index * 88.0
		draw_circle(Vector2(panel.position.x + 72, y - 10), 8.0, Color(color, identity_alpha))
		draw_string(VideoTypography.medium(), Vector2(panel.position.x + 102, y), String(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, 250, FONT_DATA, Color(colors["text"], identity_alpha))
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 420, y), "%.3f m" % float(record.get("metrics", {}).get("path_length_m", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_DATA, Color(color, length_alpha))
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 680, y), "%.3f s" % float(row["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_DATA, Color(color, time_alpha))
	# The same rows now support two readings: shortest distance and earliest time.
	if rows.size() >= 3:
		var shortest_y := panel.position.y + 225.0 + 2.0 * 88.0
		var fastest_y := panel.position.y + 225.0
		draw_line(Vector2(panel.position.x + 412, shortest_y + 15), Vector2(panel.position.x + 570, shortest_y + 15), Color(colors_by_id.get("line", colors["muted"]), conclusion_alpha), 3.0, true)
		draw_line(Vector2(panel.position.x + 672, fastest_y + 15), Vector2(panel.position.x + 830, fastest_y + 15), Color(colors_by_id.get("cycloid", colors["accent"]), conclusion_alpha), 3.0, true)


func _draw_cycloid_generation() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := smoothstep(0.04, 0.92, _beat_progress())
	var origin := Vector2(300, 130)
	var theta_end := _cycloid_theta_end_for_episode()
	var visual_width := 780.0
	var radius := visual_width / maxf(theta_end - sin(theta_end), 0.001)
	var theta := theta_end * progress
	var center := origin + Vector2(radius * theta, radius)
	var point := origin + Vector2(radius * (theta - sin(theta)), radius * (1.0 - cos(theta)))
	draw_line(origin, origin + Vector2(visual_width, 0), Color(colors["divider"], 0.72), 3.0, true)
	var trail := PackedVector2Array()
	var samples := maxi(2, ceili(120.0 * progress))
	for index in range(samples):
		var sample_theta := theta * float(index) / float(samples - 1)
		trail.append(origin + Vector2(radius * (sample_theta - sin(sample_theta)), radius * (1.0 - cos(sample_theta))))
	if trail.size() >= 2:
		draw_polyline(trail, colors_by_id.get("cycloid", colors["accent"]), 8.0, true)
	draw_circle(center, radius, Color(colors["surface"], 0.15))
	draw_arc(center, radius, 0.0, TAU, 64, Color(colors["text"], 0.68), 4.0, true)
	draw_line(center, point, Color(colors["muted"], 0.74), 3.0, true)
	draw_circle(point, 14.0, colors_by_id.get("cycloid", colors["accent"]))
	var finish := origin + Vector2(visual_width, radius * (1.0 - cos(theta_end)))
	var segment_alpha := smoothstep(0.70, 0.88, progress)
	draw_circle(finish, 8.0, Color(colors["background"], segment_alpha))
	draw_arc(finish, 10.0, 0.0, TAU, 28, Color(colors["accent"], segment_alpha), 2.5, true)
	draw_string(VideoTypography.medium(), finish + Vector2(-230, 62), "比赛使用的连接区间", HORIZONTAL_ALIGNMENT_CENTER, 440, FONT_SECONDARY, Color(colors["muted"], segment_alpha))
	draw_string(VideoTypography.bold(), Vector2(1320, 300), "圆周上一点，画出同一类摆线", HORIZONTAL_ALIGNMENT_LEFT, 520, 38, colors["text"])
	_draw_typst_formula(3, CYCLOID_FORMULA_BOUNDS, Color(colors["text"], smoothstep(0.22, 0.40, progress) * 0.88))


func _cycloid_theta_end_for_episode() -> float:
	var points: PackedVector2Array = trajectories_by_id.get("cycloid", PackedVector2Array())
	if points.size() < 2:
		return 4.0
	var delta := points[-1] - points[0]
	var target_ratio := absf(delta.x / maxf(absf(delta.y), 0.001))
	var low := 0.001
	var high := TAU - 0.001
	for _iteration in range(64):
		var middle := 0.5 * (low + high)
		var ratio := (middle - sin(middle)) / maxf(1.0 - cos(middle), 0.001)
		if ratio < target_ratio:
			low = middle
		else:
			high = middle
	return 0.5 * (low + high)


func _draw_model_boundary() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var notes := [
		{"title": "本集模型", "body": "无摩擦滑动质点"},
		{"title": "现实还包括", "body": "滚动 · 摩擦 · 阻力"},
		{"title": "下一个问题", "body": "那从摆线不同位置释放，\n是否会同时到达最低点？"},
	]
	var starts := [0.05, 0.30, 0.56]
	for index in range(notes.size()):
		var alpha := smoothstep(float(starts[index]), float(starts[index]) + 0.18, progress)
		var y := MODEL_BOUNDARY_NOTE_REGION.position.y + 30.0 + index * 185.0
		var emphasis: Color = colors["text"] if index < 2 else colors["accent"]
		draw_rect(Rect2(MODEL_BOUNDARY_NOTE_REGION.position.x, y - 8, 34, 3), Color(emphasis, alpha * 0.84), true)
		draw_string(VideoTypography.medium(), Vector2(MODEL_BOUNDARY_NOTE_REGION.position.x, y + 42), String(notes[index]["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, Color(colors["muted"], alpha))
		if index == 2:
			draw_string(VideoTypography.bold(), Vector2(MODEL_BOUNDARY_NOTE_REGION.position.x, y + 94), "那从摆线不同位置释放，", HORIZONTAL_ALIGNMENT_LEFT, MODEL_BOUNDARY_NOTE_REGION.size.x, FONT_ESSENTIAL, Color(emphasis, alpha))
			draw_string(VideoTypography.bold(), Vector2(MODEL_BOUNDARY_NOTE_REGION.position.x, y + 142), "是否会同时到达最低点？", HORIZONTAL_ALIGNMENT_LEFT, MODEL_BOUNDARY_NOTE_REGION.size.x, FONT_ESSENTIAL, Color(emphasis, alpha))
		else:
			draw_string(VideoTypography.bold(), Vector2(MODEL_BOUNDARY_NOTE_REGION.position.x, y + 100), String(notes[index]["body"]), HORIZONTAL_ALIGNMENT_LEFT, MODEL_BOUNDARY_NOTE_REGION.size.x, FONT_DATA, Color(emphasis, alpha))


func _preview_states(time_sec: float) -> Dictionary:
	var result := {}
	for record_value in bundle.get("records", []):
		var record: Dictionary = record_value
		result[record["variant_id"]] = _sample_record(record, time_sec)
	return result


func _sample_record(record: Dictionary, time_sec: float) -> Dictionary:
	var frames: Array = record.get("frames", [])
	if frames.is_empty():
		return {}
	var tick_rate := maxi(1, int(record.get("tick_rate", 120)))
	var frame_position := clampf(time_sec, 0.0, float(record.get("duration_sec", 0.0))) * tick_rate
	var lower_index := clampi(int(floor(frame_position)), 0, frames.size() - 1)
	var upper_index := mini(lower_index + 1, frames.size() - 1)
	var weight: float = frame_position - floor(frame_position)
	var lower: Dictionary = frames[lower_index]
	var upper: Dictionary = frames[upper_index]
	return {
		"position_px": _vector(lower["position_px"]).lerp(_vector(upper["position_px"]), weight),
		"speed_mps": lerpf(float(lower["speed_mps"]), float(upper["speed_mps"]), weight),
		"arrived": bool(lower["arrived"]),
	}


func _sorted_arrival_rows() -> Array:
	var rows: Array = analysis.get("rows", [])
	var sorted := rows.duplicate(true)
	sorted.sort_custom(func(a, b): return float(a["value"]) < float(b["value"]))
	return sorted


func _arrival_rank(variant_id: String) -> int:
	var rows := _sorted_arrival_rows()
	for index in range(rows.size()):
		if String(rows[index]["variant_id"]) == variant_id:
			return index
	return 0


func _finish_position() -> Vector2:
	var first_record: Dictionary = bundle.get("records", [{}])[0]
	var points: Array = first_record.get("path_points_px", [])
	return _display_position(_vector(points[-1])) if not points.is_empty() else Vector2.ZERO


func _display_points(source: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in source:
		result.append(_display_position(point))
	return result


func _display_position(value: Variant) -> Vector2:
	var point := _vector(value)
	var beat_id := String(current_beat.get("id", ""))
	var scale_and_offset := _world_scale_and_offset(beat_id)
	var world_offset: Vector2 = scale_and_offset[1]
	return point * float(scale_and_offset[0]) + world_offset


func _draw_typst_formula(step_index: int, bounds: Rect2, tint: Color) -> void:
	var explanation: Dictionary = episode.get("story", {}).get("explanation", {})
	var steps: Array = explanation.get("steps", [])
	if step_index < 0 or step_index >= steps.size():
		return
	var step: Dictionary = steps[step_index]
	var texture := FormulaAsset.load_texture(String(step.get("formula_asset", "")))
	if texture == null:
		return
	var fitted := FormulaAsset.fit_rect(texture, bounds)
	draw_texture_rect(texture, fitted, false, tint)


func _vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
