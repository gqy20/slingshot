class_name SlingshotEpisodeLayout
extends RefCounted

const CANVAS_SIZE := Vector2(1920.0, 1080.0)
const SOURCE_WORLD_RECT := Rect2(0.0, 90.0, 1920.0, 830.0)
const IDENTITY_RECT := Rect2(56.0, 38.0, 820.0, 36.0)
const PHASE_RECT := Rect2(1590.0, 27.0, 280.0, 38.0)
const LEGEND_RECT := Rect2(220.0, 112.0, 1240.0, 44.0)
const CLOCK_RECT := Rect2(1480.0, 112.0, 380.0, 40.0)
const QUESTION_RECT := Rect2(180.0, 112.0, 1560.0, 150.0)
const SETUP_COPY_RECT := Rect2(260.0, 126.0, 1400.0, 54.0)
const EXPLAIN_RECT := Rect2(760.0, 230.0, 1100.0, 440.0)
const RESULT_RECT := Rect2(160.0, 120.0, 1600.0, 760.0)
const RESULT_RAIL_RECT := Rect2(300.0, 92.0, 1320.0, 104.0)
const SUBTITLE_RECT := Rect2(190.0, 970.0, 1540.0, 70.0)


static func plot_rect_for_phase(phase: String, mode: String = "measurement") -> Rect2:
	if mode == "immersive":
		return Rect2(32.0, 74.0, 1856.0, 826.0)
	match phase:
		"QUESTION":
			return Rect2(70.0, 285.0, 1780.0, 615.0)
		"EXPLAIN":
			return Rect2(42.0, 205.0, 670.0, 695.0)
		"SETUP":
			return Rect2(54.0, 205.0, 1812.0, 695.0)
		"COMPARE":
			return Rect2(54.0, 165.0, 1812.0, 735.0)
		_:
			return Rect2(70.0, 180.0, 1780.0, 710.0)


static func world_scale(phase: String, mode: String = "measurement") -> float:
	var target := plot_rect_for_phase(phase, mode)
	return minf(
		target.size.x / SOURCE_WORLD_RECT.size.x,
		target.size.y / SOURCE_WORLD_RECT.size.y
	)


static func world_offset(phase: String, mode: String = "measurement") -> Vector2:
	var target := plot_rect_for_phase(phase, mode)
	var scale_value := world_scale(phase, mode)
	var fitted_size := SOURCE_WORLD_RECT.size * scale_value
	return target.position + (target.size - fitted_size) * 0.5


static func map_world(point: Vector2, phase: String, mode: String = "measurement") -> Vector2:
	return (
		world_offset(phase, mode)
		+ (point - SOURCE_WORLD_RECT.position) * world_scale(phase, mode)
	)


static func result_rail_cell(index: int, count: int) -> Rect2:
	var safe_count := maxi(1, count)
	var cell_width := RESULT_RAIL_RECT.size.x / float(safe_count)
	return Rect2(
		RESULT_RAIL_RECT.position + Vector2(cell_width * index, 0.0),
		Vector2(cell_width, RESULT_RAIL_RECT.size.y)
	)


static func phase_start(episode: Dictionary, phase: String) -> float:
	var story: Dictionary = episode["story"]
	match phase:
		"QUESTION":
			return 0.0
		"EXPLAIN":
			return float(story["question_sec"])
		"SETUP":
			return float(story["question_sec"]) + float(story.get("explain_sec", 0.0))
		"FLIGHT":
			return (
				float(story["question_sec"])
				+ float(story.get("explain_sec", 0.0))
				+ float(story["setup_sec"])
			)
		"COMPARE":
			return float(episode["duration_sec"]) - float(story["compare_sec"])
	return 0.0


static func phase_elapsed(episode: Dictionary, phase: String, video_time_sec: float) -> float:
	return maxf(0.0, video_time_sec - phase_start(episode, phase))


static func reserved_rects_for_phase(phase: String, include_subtitles: bool = true) -> Array[Rect2]:
	var regions: Array[Rect2] = [IDENTITY_RECT, PHASE_RECT]
	match phase:
		"QUESTION":
			regions.append(QUESTION_RECT)
		"EXPLAIN":
			regions.append(EXPLAIN_RECT)
		"SETUP":
			regions.append(LEGEND_RECT)
			regions.append(SETUP_COPY_RECT)
		"FLIGHT":
			regions.append(LEGEND_RECT)
			regions.append(CLOCK_RECT)
		"COMPARE":
			pass
	if include_subtitles:
		regions.append(SUBTITLE_RECT)
	return regions


static func validate_static_regions() -> PackedStringArray:
	var errors := PackedStringArray()
	for phase in ["QUESTION", "EXPLAIN", "SETUP", "FLIGHT", "COMPARE"]:
		var plot := plot_rect_for_phase(phase)
		for reserved in reserved_rects_for_phase(phase):
			if plot.intersects(reserved):
				errors.append("%s plot intersects reserved region %s" % [phase, reserved])
	return errors


static func audit_bundle(bundle: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for record_value in bundle.get("records", []):
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		var frames: Array = record.get("frames", [])
		var variant_id := String(record.get("variant_id", "unknown"))
		for phase in ["FLIGHT", "COMPARE"]:
			var frame_indices: Array[int] = []
			if phase == "COMPARE" and not frames.is_empty():
				frame_indices.append(frames.size() - 1)
			else:
				for index in range(frames.size()):
					frame_indices.append(index)
			var scale_value := maxf(0.72, world_scale(phase))
			var bird_radius := 54.0 * scale_value
			var plot := plot_rect_for_phase(phase).grow(-bird_radius)
			var reserved := reserved_rects_for_phase(phase)
			for frame_index in frame_indices:
				var frame: Dictionary = frames[frame_index]
				var source_position := _vector(frame.get("bird_position_px", Vector2.ZERO))
				var mapped_position := map_world(source_position, phase)
				var bird_rect := Rect2(
					mapped_position - Vector2.ONE * bird_radius,
					Vector2.ONE * bird_radius * 2.0
				)
				if not plot.has_point(mapped_position):
					errors.append("%s %s frame %d bird leaves plot safe area" % [
						variant_id,
						phase,
						frame_index,
					])
					break
				if _intersects_any(bird_rect, reserved):
					errors.append("%s %s frame %d bird intersects text region" % [
						variant_id,
						phase,
						frame_index,
					])
					break
				if phase == "FLIGHT":
					var velocity := _vector(frame.get("bird_velocity_px_s", Vector2.ZERO))
					var arrow_end := map_world(source_position + velocity * 0.075, phase)
					var arrow_rect := _line_rect(mapped_position, arrow_end).grow(10.0)
					if _intersects_any(arrow_rect, reserved):
						errors.append("%s FLIGHT frame %d velocity arrow intersects text region" % [
							variant_id,
							frame_index,
						])
						break
	return errors


static func _intersects_any(rect: Rect2, regions: Array[Rect2]) -> bool:
	for region in regions:
		if rect.intersects(region):
			return true
	return false


static func _line_rect(start: Vector2, finish: Vector2) -> Rect2:
	var minimum := Vector2(minf(start.x, finish.x), minf(start.y, finish.y))
	var maximum := Vector2(maxf(start.x, finish.x), maxf(start.y, finish.y))
	return Rect2(minimum, maximum - minimum)


static func _vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
