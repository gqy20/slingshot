extends "res://src/video/episode_canvas.gd"


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
			_draw_tracks()
			_draw_racing_balls(_preview_states(1.62 * _beat_progress()))
			_draw_center_headline("谁会先到？")
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
			_draw_tracks()
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


func _draw_tracks(focus_id: String = "", dim_others: bool = false) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var points: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
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
	if first_path.size() >= 2:
		var start := _vector(first_path[0])
		var finish := _vector(first_path[-1])
		draw_line(start - Vector2(0, 54), start + Vector2(0, 54), Color(colors["text"], 0.75), 5.0)
		draw_line(finish - Vector2(0, 72), finish + Vector2(0, 72), Color(colors["text"], 0.75), 5.0)
		draw_string(VideoTypography.data(), start + Vector2(-35, -75), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, colors["muted"])
		draw_string(VideoTypography.data(), finish + Vector2(-30, 105), "FINISH", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, colors["muted"])


func _draw_center_headline(value: String) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	draw_string(
		VideoTypography.bold(), Vector2(540, 955), value,
		HORIZONTAL_ALIGNMENT_CENTER, 840, 46, colors["text"]
	)


func _draw_shortest_bet() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var record: Dictionary = records_by_id.get("line", {})
	var length := float(record.get("metrics", {}).get("path_length_m", 0.0))
	var panel := Rect2(1140, 190, 610, 180)
	_draw_panel(panel)
	draw_string(VideoTypography.medium(), panel.position + Vector2(32, 55), "几何最短", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, colors["muted"])
	draw_string(VideoTypography.bold(), panel.position + Vector2(32, 125), "直线  %.3f m" % length, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, colors["text"])
	_draw_center_headline("最短，就一定最快吗？")


func _draw_distance_is_not_time() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var record: Dictionary = records_by_id.get("line", {})
	var metrics: Dictionary = record.get("metrics", {})
	var progress := _beat_progress()
	var left := Rect2(90, 190, 430, 210)
	var right := Rect2(90, 440, 430, 210)
	_draw_panel(left)
	_draw_panel(right)
	draw_string(VideoTypography.medium(), left.position + Vector2(28, 50), "路径长度", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, colors["muted"])
	draw_string(VideoTypography.bold(), left.position + Vector2(28, 128), "%.3f m" % float(metrics.get("path_length_m", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 48, colors_by_id.get("line", colors["text"]))
	draw_string(VideoTypography.medium(), right.position + Vector2(28, 50), "到达时间", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, colors["muted"])
	draw_string(VideoTypography.bold(), right.position + Vector2(28, 128), "%.3f s" % float(metrics.get("arrival_time_sec", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(colors["accent"], smoothstep(0.35, 0.72, progress)))
	draw_string(VideoTypography.bold(), Vector2(620, 915), "长度告诉你走多远，不能单独告诉你走多久", HORIZONTAL_ALIGNMENT_CENTER, 820, 38, colors["text"])


func _draw_question_prompt() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var reveal := smoothstep(0.10, 0.55, _beat_progress())
	draw_string(
		VideoTypography.bold(), Vector2(520, 930), "最短的路径，会最先到达吗？",
		HORIZONTAL_ALIGNMENT_CENTER, 880, 46, Color(colors["text"], reveal)
	)


func _draw_energy_explanation() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var panel := Rect2(70, 170, 530, 610)
	draw_rect(panel, Color(colors["surface"], 0.90), true)
	draw_rect(panel, Color(colors["divider"], 0.65), false, 2.0)
	draw_string(
		VideoTypography.bold(), Vector2(105, 225), "先下降，先获得速度",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(colors["text"], smoothstep(0.05, 0.35, progress))
	)
	draw_string(
		VideoTypography.data(), Vector2(105, 270), "mgh  →  ½mv²",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color(colors["accent"], smoothstep(0.25, 0.62, progress))
	)
	var arrow_x := 250.0
	draw_line(Vector2(arrow_x, 330), Vector2(arrow_x, 700), Color(colors["muted"], 0.55), 3.0)
	_draw_arrow(Vector2(arrow_x, 360), Vector2(arrow_x, 660), Color(colors["accent"], 0.85), 5.0)
	draw_string(VideoTypography.data(), Vector2(305, 515), "高度差越大\n速度越高", HORIZONTAL_ALIGNMENT_LEFT, 240, 29, colors["muted"])
	var preview_time := lerpf(0.28, 1.18, progress)
	var preview := _preview_states(preview_time)
	_draw_racing_balls(preview)
	var bar_x := 1510.0
	var bar_y := 260.0
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var state: Dictionary = preview.get(id, {})
		var speed := float(state.get("speed_mps", 0.0))
		var color: Color = colors_by_id.get(id, colors["muted"])
		draw_string(VideoTypography.medium(), Vector2(bar_x, bar_y), String(variant["label"]), HORIZONTAL_ALIGNMENT_LEFT, 100, 24, colors["text"])
		draw_rect(Rect2(bar_x + 90, bar_y - 18, 210, 18), Color(colors["divider"], 0.42), true)
		draw_rect(Rect2(bar_x + 90, bar_y - 18, 210.0 * speed / 11.5, 18), color, true)
		draw_string(VideoTypography.data(), Vector2(bar_x + 315, bar_y), "%.1f m/s" % speed, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)
		bar_y += 66.0


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
		draw_line(_vector(segment["start_px"]), _vector(segment["finish_px"]), color, 10.0, true)
	var panel := Rect2(90, 180, 560, 430)
	_draw_panel(panel)
	draw_string(VideoTypography.bold(), panel.position + Vector2(34, 65), "每一小段，都要花时间", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, colors["text"])
	draw_string(VideoTypography.data(), panel.position + Vector2(34, 145), "小段时间  ≈  路程 ÷ 当地速度", HORIZONTAL_ALIGNMENT_LEFT, -1, 29, colors["muted"])
	draw_string(VideoTypography.bold(), panel.position + Vector2(34, 255), "T  =  ∫  ds / v", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, colors["accent"])
	draw_string(VideoTypography.medium(), panel.position + Vector2(34, 340), "更长的路，可以用更高的速度走完", HORIZONTAL_ALIGNMENT_LEFT, 485, 29, colors["text"])
	draw_string(VideoTypography.data(), Vector2(960, 930), "颜色越亮：这一段耗时越少", HORIZONTAL_ALIGNMENT_CENTER, 700, 27, colors["muted"])


func _draw_setup_labels() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var y := 205.0
	var index := 0
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var color: Color = colors_by_id[variant["id"]]
		var x := 480.0 + float(index) * 360.0
		draw_circle(Vector2(x, y), 9.0, color)
		draw_string(VideoTypography.medium(), Vector2(x + 20, y + 10), variant["label"], HORIZONTAL_ALIGNMENT_LEFT, 280, 28, colors["text"])
		index += 1
	draw_string(
		VideoTypography.data(), Vector2(570, 890), "同一起点 · 同一终点 · 无摩擦滑动质点",
		HORIZONTAL_ALIGNMENT_CENTER, 780, 30, colors["muted"]
	)


func _draw_fair_controls() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var labels := ["同一起点", "同一终点", "相同重力", "无摩擦质点"]
	var start_x := 380.0
	for index in range(labels.size()):
		var rect := Rect2(start_x + index * 300.0, 175, 250, 72)
		draw_rect(rect, Color(colors["surface"], 0.92), true)
		draw_rect(rect, Color(colors["divider"], 0.68), false, 2.0)
		draw_string(VideoTypography.medium(), rect.position + Vector2(20, 46), labels[index], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 40, 25, colors["text"])
	_draw_center_headline("只改变轨道形状")


func _draw_track_preview() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var x := 460.0
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var record: Dictionary = records_by_id.get(id, {})
		var color: Color = colors_by_id.get(id, colors["muted"])
		draw_circle(Vector2(x, 195), 8.0, color)
		draw_string(VideoTypography.medium(), Vector2(x + 18, 205), String(variant["label"]), HORIZONTAL_ALIGNMENT_LEFT, 110, 27, colors["text"])
		draw_string(VideoTypography.data(), Vector2(x + 128, 205), "%.3f m" % float(record.get("metrics", {}).get("path_length_m", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color)
		x += 430.0
	draw_string(VideoTypography.bold(), Vector2(570, 930), "最后一次下注：哪一条最快？", HORIZONTAL_ALIGNMENT_CENTER, 780, 40, colors["text"])


func _draw_racing_balls(source_states: Dictionary = {}) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var states := states_by_id if source_states.is_empty() else source_states
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var state: Dictionary = states.get(id, {})
		if state.is_empty():
			continue
		var position: Vector2 = state["position_px"]
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
		var speed := float(state["speed_mps"])
		var label_offset := Vector2(30, -22)
		if position.distance_to(_finish_position()) < 180.0:
			label_offset = Vector2(-140, -30)
		draw_string(
			VideoTypography.data(), position + label_offset, "%.1f m/s" % speed,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(colors["text"], 0.88)
		)


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
	var panel := Rect2(1510, 590, 320, 72 + arrived_rows.size() * 62)
	draw_rect(panel, Color(colors["surface"], 0.94), true)
	draw_rect(panel, Color(colors["divider"], 0.72), false, 2.0)
	draw_string(
		VideoTypography.medium(), panel.position + Vector2(24, 43), "到达锁定",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 27, colors["muted"]
	)
	for index in range(arrived_rows.size()):
		var row: Dictionary = arrived_rows[index]
		var color: Color = colors_by_id.get(String(row["variant_id"]), colors["muted"])
		var baseline := panel.position + Vector2(24, 91 + index * 62)
		draw_string(
			VideoTypography.data(), baseline, "%d" % (index + 1),
			HORIZONTAL_ALIGNMENT_LEFT, 28, 24, colors["muted"]
		)
		draw_circle(baseline + Vector2(42, -8), 6.0, color)
		draw_string(
			VideoTypography.medium(), baseline + Vector2(58, 0), String(row["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, 105, 25, colors["text"]
		)
		draw_string(
			VideoTypography.data(), baseline + Vector2(172, 0), "%.3f s" % float(row["value"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 25, color
		)


func _draw_live_race_clock() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var simulation_time := 0.0
	if not simulation_times_by_id.is_empty():
		simulation_time = float(simulation_times_by_id.values()[0])
	var panel := Rect2(1510, 185, 300, 105)
	_draw_panel(panel)
	draw_string(VideoTypography.medium(), panel.position + Vector2(22, 38), "物理时间", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, colors["muted"])
	draw_string(VideoTypography.data(), panel.position + Vector2(22, 82), "%06.3f s" % simulation_time, HORIZONTAL_ALIGNMENT_LEFT, -1, 35, colors["text"])


func _draw_finish_magnifier() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var finish := _finish_position()
	var panel := Rect2(1110, 180, 700, 290)
	_draw_panel(panel)
	draw_string(VideoTypography.bold(), panel.position + Vector2(28, 48), "终点慢放  ×8", HORIZONTAL_ALIGNMENT_LEFT, -1, 31, colors["text"])
	draw_string(VideoTypography.data(), panel.position + Vector2(470, 46), "局部放大", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, colors["muted"])
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
		draw_string(VideoTypography.medium(), Vector2(x + 18, y + 8), String(variant["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 21, color)
	var rows := _sorted_arrival_rows()
	if rows.size() >= 2:
		var delta_ms := (float(rows[1]["value"]) - float(rows[0]["value"])) * 1000.0
		draw_string(VideoTypography.data(), panel.position + Vector2(28, 255), "摆线领先圆弧  %.1f ms" % delta_ms, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, colors["accent"])


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
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 36, y), "%d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 27, colors["muted"])
		draw_circle(Vector2(panel.position.x + 88, y - 9), 7.0, color)
		draw_string(VideoTypography.medium(), Vector2(panel.position.x + 112, y), String(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, 250, 28, colors["text"])
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 425, y), "%.3f s" % float(row["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 29, color)
	draw_string(
		VideoTypography.bold(), Vector2(450, 930), "摆线更长，却更快到达",
		HORIZONTAL_ALIGNMENT_CENTER, 900, 44, colors["accent"]
	)


func _draw_distance_time_results() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var rows := _sorted_arrival_rows()
	var panel := Rect2(1080, 170, 730, 390)
	_draw_panel(panel)
	draw_string(VideoTypography.bold(), panel.position + Vector2(35, 58), "路更短，不等于时间更短", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, colors["text"])
	draw_string(VideoTypography.medium(), panel.position + Vector2(310, 105), "路径长度", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, colors["muted"])
	draw_string(VideoTypography.medium(), panel.position + Vector2(510, 105), "到达时间", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, colors["muted"])
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var id := String(row["variant_id"])
		var record: Dictionary = records_by_id.get(id, {})
		var color: Color = colors_by_id.get(id, colors["muted"])
		var y := panel.position.y + 165.0 + index * 72.0
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 38, y), "%d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, colors["muted"])
		draw_circle(Vector2(panel.position.x + 88, y - 9), 7.0, color)
		draw_string(VideoTypography.medium(), Vector2(panel.position.x + 110, y), String(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, 150, 28, colors["text"])
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 310, y), "%.3f m" % float(record.get("metrics", {}).get("path_length_m", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 27, color)
		draw_string(VideoTypography.data(), Vector2(panel.position.x + 510, y), "%.3f s" % float(row["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 27, color)
	draw_string(VideoTypography.bold(), Vector2(420, 930), "直线最短，却最后到达", HORIZONTAL_ALIGNMENT_CENTER, 820, 42, colors["accent"])


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
	draw_string(VideoTypography.bold(), Vector2(500, 730), "圆周上一点，画出摆线", HORIZONTAL_ALIGNMENT_CENTER, 920, 44, colors["text"])
	draw_string(VideoTypography.data(), Vector2(610, 790), "x = a(θ − sin θ)    y = a(1 − cos θ)", HORIZONTAL_ALIGNMENT_CENTER, 700, 30, colors["muted"])
	draw_string(VideoTypography.medium(), Vector2(580, 930), "它不是为了比赛结果随意画出的曲线", HORIZONTAL_ALIGNMENT_CENTER, 760, 34, colors["accent"])


func _draw_model_boundary() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var cards := [
		{"title": "本集模型", "body": "无摩擦滑动质点"},
		{"title": "现实还包括", "body": "滚动 · 摩擦 · 阻力"},
		{"title": "下一个问题", "body": "从摆线不同位置释放呢？"},
	]
	for index in range(cards.size()):
		var rect := Rect2(210 + index * 520, 690, 450, 170)
		_draw_panel(rect)
		draw_string(VideoTypography.medium(), rect.position + Vector2(28, 50), String(cards[index]["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, colors["muted"])
		draw_string(VideoTypography.bold(), rect.position + Vector2(28, 112), String(cards[index]["body"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 56, 31, colors["text"] if index < 2 else colors["accent"])


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
	return _vector(points[-1]) if not points.is_empty() else Vector2.ZERO


func _vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
