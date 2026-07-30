extends "res://src/video/episode_canvas.gd"

const FormulaAsset = preload("res://src/video/formula_asset.gd")

const CONTENT_BOTTOM := 880.0
const FONT_ENVIRONMENT := 24
const FONT_SECONDARY := 28
const FONT_ESSENTIAL := 30
const FONT_DATA := 32
const DISTANCE_TIME_PANEL := Rect2(500, 175, 920, 540)
const SHORTEST_BET_PANEL := Rect2(1300, 300, 500, 160)
const RAW_TRACK_BOUNDS := Rect2(330, 90, 1100, 790)
const OPENING_WORLD_SCALE := 0.94
const OPENING_WORLD_OFFSET := Vector2(50, 20)
const EXPLAIN_WORLD_SCALE := 0.78
const EXPLAIN_WORLD_OFFSET := Vector2(420, 90)
const SETUP_WORLD_SCALE := 0.86
const SETUP_WORLD_OFFSET := Vector2(150, 110)
const RACE_CLOCK_PANEL := Rect2(1470, 180, 350, 118)
const RACE_TELEMETRY_PANEL := Rect2(1470, 330, 350, 292)
const ENERGY_FORMULA_BOUNDS := Rect2(105, 238, 440, 90)
const ENERGY_ARROW_TOP := 350.0
const TIME_FORMULA_BOUNDS := Rect2(124, 373, 500, 112)
const TIME_SUPPORTING_BASELINE_Y := 550.0
const CYCLOID_FORMULA_BOUNDS := Rect2(500, 690, 920, 165)
const MODEL_BOUNDARY_CARDS := [
	Rect2(1460, 170, 380, 170),
	Rect2(1460, 365, 380, 170),
	Rect2(1460, 560, 380, 170),
]


static func layout_audit_regions() -> Dictionary:
	return {
		"shortest-bet": [SHORTEST_BET_PANEL],
		"distance-is-not-time": [Rect2(90, 190, 430, 210), Rect2(90, 440, 430, 210)],
		"energy-drop": [Rect2(70, 170, 530, 610)],
		"time-integral": [Rect2(90, 180, 560, 430)],
		"fair-controls": [Rect2(520, 70, 1280, 82)],
		"track-preview": [Rect2(520, 90, 1280, 55)],
		"race-release": [RACE_CLOCK_PANEL, RACE_TELEMETRY_PANEL],
		"race-separation": [RACE_CLOCK_PANEL, RACE_TELEMETRY_PANEL],
		"finish-slow-motion": [Rect2(1110, 180, 700, 290), Rect2(1460, 570, 380, 280)],
		"arrival-lock": [Rect2(1460, 570, 380, 280)],
		"distance-time-table": [DISTANCE_TIME_PANEL],
		"cycloid-generation": [Rect2(500, 630, 920, 230)],
		"model-boundary": MODEL_BOUNDARY_CARDS,
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
		"time": TIME_FORMULA_BOUNDS,
		"cycloid": CYCLOID_FORMULA_BOUNDS,
	}


static func _world_scale_and_offset(beat_id: String) -> Array:
	if beat_id in ["cold-open", "shortest-bet"]:
		return [OPENING_WORLD_SCALE, OPENING_WORLD_OFFSET]
	if beat_id in ["distance-is-not-time", "energy-drop", "time-integral"]:
		return [EXPLAIN_WORLD_SCALE, EXPLAIN_WORLD_OFFSET]
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
			_draw_tracks()
			_draw_fair_controls()
		"track-preview":
			_draw_tracks()
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
			_draw_finish_arrivals()
		"arrival-lock":
			_draw_tracks()
			_draw_racing_balls()
			_draw_finish_arrivals(true)
		"distance-time-table":
			_draw_distance_time_results()
		"cycloid-generation":
			_draw_cycloid_generation()
		"model-boundary":
			_draw_tracks()
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


func _draw_tracks(focus_id: String = "", dim_others: bool = false, reveal_progress: float = 1.0) -> void:
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
		draw_polyline(points, Color(color, alpha), width, true)
		draw_polyline(points, Color(colors["text"], 0.18), 2.0, true)
	var first_record: Dictionary = bundle.get("records", [{}])[0]
	var first_path: Array = first_record.get("path_points_px", [])
	if first_path.size() >= 2 and reveal_progress > 0.08:
		var start := _display_position(_vector(first_path[0]))
		var finish := _display_position(_vector(first_path[-1]))
		var marker_alpha := smoothstep(0.08, 0.24, reveal_progress)
		draw_line(start - Vector2(0, 54), start + Vector2(0, 54), Color(colors["text"], 0.75 * marker_alpha), 5.0)
		draw_string(VideoTypography.data(), start + Vector2(-35, -63), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ENVIRONMENT, Color(colors["muted"], marker_alpha))
		if reveal_progress > 0.78:
			var finish_alpha := smoothstep(0.78, 0.96, reveal_progress)
			draw_line(finish - Vector2(0, 72), finish + Vector2(0, 72), Color(colors["text"], 0.75 * finish_alpha), 5.0)
			draw_string(VideoTypography.data(), finish + Vector2(20, 58), "FINISH →", HORIZONTAL_ALIGNMENT_LEFT, 170, FONT_ENVIRONMENT, Color(colors["muted"], finish_alpha))


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
	draw_string(VideoTypography.data(), Vector2(710, 838), "S01E05  ·  最速降线", HORIZONTAL_ALIGNMENT_CENTER, 500, 27, Color(accent, brand_alpha * 0.88))


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
				_display_position(state["position_px"]), 10.0 + 0.8 * sample_index,
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
	var panel := SHORTEST_BET_PANEL
	panel.position.x += 70.0 * (1.0 - reveal)
	draw_rect(panel, Color(colors["surface"], 0.93 * reveal), true)
	draw_rect(panel, Color(colors["divider"], 0.70 * reveal), false, 2.0)
	draw_rect(Rect2(panel.position, Vector2(6, panel.size.y)), Color(colors_by_id.get("line", colors["accent"]), reveal), true)
	draw_string(VideoTypography.medium(), panel.position + Vector2(34, 48), "几何最短", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(colors["muted"], reveal))
	draw_string(VideoTypography.bold(), panel.position + Vector2(34, 116), "直线  %.3f m" % (length * reveal), HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(colors["text"], reveal))
	var line_points: PackedVector2Array = _display_points(trajectories_by_id.get("line", PackedVector2Array()))
	line_points = _partial_polyline(line_points, smoothstep(0.04, 0.62, _beat_progress()))
	if line_points.size() >= 2:
		draw_polyline(line_points, Color(colors_by_id.get("line", colors["accent"]), 0.94), 11.0, true)


func _draw_distance_is_not_time() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var record: Dictionary = records_by_id.get("line", {})
	var metrics: Dictionary = record.get("metrics", {})
	var progress := _beat_progress()
	var left := Rect2(90, 190, 430, 210)
	var right := Rect2(90, 440, 430, 210)
	_draw_panel(left)
	_draw_panel(right)
	draw_string(VideoTypography.medium(), left.position + Vector2(28, 50), "路径长度", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["muted"])
	draw_string(VideoTypography.bold(), left.position + Vector2(28, 128), "%.3f m" % float(metrics.get("path_length_m", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 48, colors_by_id.get("line", colors["text"]))
	draw_string(VideoTypography.medium(), right.position + Vector2(28, 50), "到达时间", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["muted"])
	draw_string(VideoTypography.bold(), right.position + Vector2(28, 128), "%.3f s" % float(metrics.get("arrival_time_sec", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(colors["accent"], smoothstep(0.35, 0.72, progress)))


func _draw_question_prompt() -> void:
	pass


func _draw_energy_explanation() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var preview_time := lerpf(0.28, 1.18, progress)
	var preview := _preview_states(preview_time)
	# Draw the moving evidence first. The opaque explanation panel masks balls
	# while they occupy its copy region, then reveals them as they enter the plot.
	_draw_racing_balls(preview)
	var panel := Rect2(70, 170, 530, 610)
	draw_rect(panel, Color(colors["surface"], 0.90), true)
	draw_rect(panel, Color(colors["divider"], 0.65), false, 2.0)
	draw_string(
		VideoTypography.bold(), Vector2(105, 225), "先下降，先获得速度",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(colors["text"], smoothstep(0.05, 0.35, progress))
	)
	_draw_typst_formula(
		0, ENERGY_FORMULA_BOUNDS,
		Color(colors["accent"], smoothstep(0.25, 0.62, progress))
	)
	var arrow_x := 250.0
	draw_line(Vector2(arrow_x, ENERGY_ARROW_TOP), Vector2(arrow_x, 700), Color(colors["muted"], 0.55), 3.0)
	_draw_arrow(Vector2(arrow_x, 380), Vector2(arrow_x, 660), Color(colors["accent"], 0.85), 5.0)
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
	var reveal_count := clampi(ceili(segments.size() * smoothstep(0.08, 0.78, _beat_progress())), 0, segments.size())
	for index in range(reveal_count):
		var segment: Dictionary = segments[index]
		var dt := float(segment["segment_time_sec"])
		var weight := clampf(dt / 0.09, 0.0, 1.0)
		var cycloid_color: Color = colors_by_id.get("cycloid", colors["accent"])
		var color := cycloid_color.lerp(colors["muted"], weight * 0.55)
		draw_line(
			_display_position(_vector(segment["start_px"])),
			_display_position(_vector(segment["finish_px"])),
			color, 10.0, true
		)
	var panel := Rect2(90, 180, 560, 430)
	_draw_panel(panel)
	draw_string(VideoTypography.bold(), panel.position + Vector2(34, 65), "每一小段，都要花时间", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, colors["text"])
	draw_string(VideoTypography.data(), panel.position + Vector2(34, 145), "小段时间  ≈  路程 ÷ 当地速度", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["muted"])
	_draw_typst_formula(
		1, TIME_FORMULA_BOUNDS,
		colors["accent"]
	)
	draw_string(VideoTypography.medium(), Vector2(panel.position.x + 34, TIME_SUPPORTING_BASELINE_Y), "更长的路，可以用更高的速度走完", HORIZONTAL_ALIGNMENT_LEFT, 485, FONT_ESSENTIAL, colors["text"])


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
		VideoTypography.data(), Vector2(570, 860), "同一起点 · 同一终点 · 无摩擦滑动质点",
		HORIZONTAL_ALIGNMENT_CENTER, 780, 30, colors["muted"]
	)


func _draw_fair_controls() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var labels := ["同一起点", "同一终点", "相同重力", "无摩擦质点"]
	var start_x := 520.0
	for index in range(labels.size()):
		var rect := Rect2(start_x + index * 320.0, 70, 280, 82)
		draw_rect(rect, Color(colors["surface"], 0.92), true)
		draw_rect(rect, Color(colors["divider"], 0.68), false, 2.0)
		draw_string(VideoTypography.medium(), rect.position + Vector2(20, 52), labels[index], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 40, FONT_ESSENTIAL, colors["text"])


func _draw_track_preview() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var x := 520.0
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var record: Dictionary = records_by_id.get(id, {})
		var color: Color = colors_by_id.get(id, colors["muted"])
		draw_circle(Vector2(x, 115), 8.0, color)
		draw_string(VideoTypography.medium(), Vector2(x + 18, 125), String(variant["label"]), HORIZONTAL_ALIGNMENT_LEFT, 110, FONT_ESSENTIAL, colors["text"])
		draw_string(VideoTypography.data(), Vector2(x + 128, 125), "%.3f m" % float(record.get("metrics", {}).get("path_length_m", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, color)
		x += 430.0


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
				position, 23.0 + float(rank) * 6.0, 0.0, TAU, 40,
				Color(color, 0.92), 4.0, true
			)
			continue
		draw_circle(position, 25.0, Color(colors["background"], 0.9))
		draw_circle(position, 19.0, color)
		draw_arc(position, 27.0, 0.0, TAU, 32, Color(color, 0.55), 3.0, true)


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
	draw_rect(panel, Color(colors["surface"], 0.94), true)
	draw_rect(panel, Color(colors["divider"], 0.72), false, 2.0)
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
	var panel := RACE_CLOCK_PANEL
	_draw_panel(panel)
	draw_string(VideoTypography.medium(), panel.position + Vector2(24, 42), "物理时间", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SECONDARY, colors["muted"])
	draw_string(VideoTypography.data(), panel.position + Vector2(24, 92), "%06.3f s" % simulation_time, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, colors["text"])


func _draw_race_telemetry() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var panel := RACE_TELEMETRY_PANEL
	_draw_panel(panel)
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
			Rect2(panel.position.x + 145, baseline_y - 25, 105, 20),
			Color(colors["divider"], 0.42), true
		)
		draw_rect(
			Rect2(panel.position.x + 145, baseline_y - 25, 105.0 * speed / 11.5, 20),
			color, true
		)
		draw_string(
			VideoTypography.data(), Vector2(panel.position.x + 266, baseline_y),
			"%.1f" % speed, HORIZONTAL_ALIGNMENT_RIGHT, 58,
			FONT_ESSENTIAL, color
		)
		baseline_y += 58.0
	draw_string(
		VideoTypography.data(), panel.position + Vector2(276, 267), "m/s",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ENVIRONMENT, colors["muted"]
	)


func _draw_finish_magnifier() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var finish := _finish_position()
	var panel := Rect2(1110, 180, 700, 290)
	_draw_panel(panel)
	draw_string(VideoTypography.bold(), panel.position + Vector2(28, 50), "终点慢放  ×8", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, colors["text"])
	draw_string(VideoTypography.data(), panel.position + Vector2(470, 48), "局部放大", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SECONDARY, colors["muted"])
	var rail_start := panel.position + Vector2(70, 180)
	var rail_finish := panel.position + Vector2(620, 180)
	draw_line(rail_start, rail_finish, Color(colors["divider"], 0.82), 4.0, true)
	draw_line(rail_finish - Vector2(0, 55), rail_finish + Vector2(0, 55), colors["text"], 4.0, true)
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var state: Dictionary = states_by_id.get(id, {})
		if state.is_empty():
			continue
		var offset_m := maxf(0.0, finish.x - float(Vector2(state["position_px"]).x)) / 100.0
		var x := rail_finish.x - minf(520.0, offset_m * 140.0)
		var rank := _arrival_rank(id)
		var y := rail_start.y - 42.0 + rank * 42.0
		var color: Color = colors_by_id.get(id, colors["muted"])
		draw_circle(Vector2(x, y), 12.0, color)
		draw_string(VideoTypography.medium(), Vector2(x + 18, y + 9), String(variant["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SECONDARY, color)
	var rows := _sorted_arrival_rows()
	if rows.size() >= 2:
		var delta_ms := (float(rows[1]["value"]) - float(rows[0]["value"])) * 1000.0
		draw_string(VideoTypography.data(), panel.position + Vector2(28, 258), "摆线领先圆弧  %.1f ms" % delta_ms, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["accent"])


func _draw_arrival_results() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var sorted := _sorted_arrival_rows()
	var panel := Rect2(1160, 210, 640, 360)
	draw_rect(panel, Color(colors["surface"], 0.92), true)
	draw_rect(panel, Color(colors["divider"], 0.72), false, 2.0)
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
	var panel := DISTANCE_TIME_PANEL
	_draw_panel(panel)
	draw_string(VideoTypography.bold(), panel.position + Vector2(42, 68), "路更短，不等于时间更短", HORIZONTAL_ALIGNMENT_LEFT, -1, 42, colors["text"])
	draw_string(VideoTypography.medium(), panel.position + Vector2(420, 145), "路径长度", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["muted"])
	draw_string(VideoTypography.medium(), panel.position + Vector2(680, 145), "到达时间", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["muted"])
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var id := String(row["variant_id"])
		var record: Dictionary = records_by_id.get(id, {})
		var color: Color = colors_by_id.get(id, colors["muted"])
		var y := panel.position.y + 225.0 + index * 88.0
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 48, y), "%d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["muted"])
		draw_circle(Vector2(panel.position.x + 112, y - 10), 8.0, color)
		draw_string(VideoTypography.medium(), Vector2(panel.position.x + 142, y), String(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, 210, FONT_DATA, colors["text"])
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 420, y), "%.3f m" % float(record.get("metrics", {}).get("path_length_m", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_DATA, color)
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 680, y), "%.3f s" % float(row["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_DATA, color)


func _draw_cycloid_generation() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := smoothstep(0.04, 0.92, _beat_progress())
	var origin := Vector2(300, 260)
	var radius := 105.0
	var theta := TAU * 1.75 * progress
	var center := origin + Vector2(radius * theta, radius)
	var point := origin + Vector2(radius * (theta - sin(theta)), radius * (1.0 - cos(theta)))
	draw_line(origin, Vector2(1720, origin.y), Color(colors["divider"], 0.72), 3.0, true)
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
	draw_string(VideoTypography.bold(), Vector2(500, 675), "圆周上一点，画出摆线", HORIZONTAL_ALIGNMENT_CENTER, 920, 44, colors["text"])
	_draw_typst_formula(2, CYCLOID_FORMULA_BOUNDS, Color(colors["text"], 0.88))


func _draw_model_boundary() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var cards := [
		{"title": "本集模型", "body": "无摩擦滑动质点"},
		{"title": "现实还包括", "body": "滚动 · 摩擦 · 阻力"},
		{"title": "下一个问题", "body": "摆线上不同位置释放？"},
	]
	for index in range(cards.size()):
		var rect: Rect2 = MODEL_BOUNDARY_CARDS[index]
		_draw_panel(rect)
		draw_string(VideoTypography.medium(), rect.position + Vector2(28, 52), String(cards[index]["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ESSENTIAL, colors["muted"])
		draw_string(VideoTypography.bold(), rect.position + Vector2(28, 116), String(cards[index]["body"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 56, FONT_DATA, colors["text"] if index < 2 else colors["accent"])


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


func _draw_panel(rect: Rect2) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	draw_rect(rect, Color(colors["surface"], 0.93), true)
	draw_rect(rect, Color(colors["divider"], 0.70), false, 2.0)


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
