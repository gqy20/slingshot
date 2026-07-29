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


func _draw_tracks() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var points: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
		if points.size() < 2:
			continue
		var color: Color = colors_by_id.get(id, colors["muted"])
		draw_polyline(points, Color(color, 0.76), 7.0, true)
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


func _draw_racing_balls() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var id := String(variant["id"])
		var state: Dictionary = states_by_id.get(id, {})
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


func _draw_finish_arrivals() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var rows := _sorted_arrival_rows()
	var arrived_rows: Array = []
	for row_value in rows:
		var row: Dictionary = row_value
		var state: Dictionary = states_by_id.get(String(row["variant_id"]), {})
		if bool(state.get("arrived", false)):
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
