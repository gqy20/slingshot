class_name SlingshotEpisodeLayout
extends RefCounted

const CANVAS_SIZE := Vector2(1920.0, 1080.0)
const SOURCE_WORLD_RECT := Rect2(0.0, 90.0, 1920.0, 830.0)
const IDENTITY_RECT := Rect2(40.0, 24.0, 1000.0, 44.0)
const PHASE_RECT := Rect2(1590.0, 27.0, 280.0, 38.0)
const LEGEND_RECT := Rect2(220.0, 108.0, 1240.0, 52.0)
const CLOCK_RECT := Rect2(1480.0, 112.0, 380.0, 40.0)
const QUESTION_RECT := Rect2(180.0, 145.0, 1560.0, 160.0)
const SETUP_COPY_RECT := Rect2(220.0, 172.0, 1480.0, 64.0)
const EXPLAIN_RECT := Rect2(800.0, 225.0, 1060.0, 420.0)
const RESULT_RECT := Rect2(1120.0, 180.0, 740.0, 710.0)
const SUBTITLE_RECT := Rect2(160.0, 944.0, 1600.0, 100.0)


static func plot_rect_for_phase(phase: String) -> Rect2:
	match phase:
		"QUESTION":
			return Rect2(80.0, 340.0, 1760.0, 550.0)
		"EXPLAIN":
			return Rect2(40.0, 225.0, 720.0, 665.0)
		"SETUP":
			return Rect2(70.0, 255.0, 1780.0, 635.0)
		"COMPARE":
			return Rect2(56.0, 180.0, 1020.0, 710.0)
		_:
			return Rect2(70.0, 180.0, 1780.0, 710.0)


static func world_scale(phase: String) -> float:
	var target := plot_rect_for_phase(phase)
	return minf(
		target.size.x / SOURCE_WORLD_RECT.size.x,
		target.size.y / SOURCE_WORLD_RECT.size.y
	)


static func world_offset(phase: String) -> Vector2:
	var target := plot_rect_for_phase(phase)
	var scale_value := world_scale(phase)
	var fitted_size := SOURCE_WORLD_RECT.size * scale_value
	return target.position + (target.size - fitted_size) * 0.5


static func map_world(point: Vector2, phase: String) -> Vector2:
	return (
		world_offset(phase)
		+ (point - SOURCE_WORLD_RECT.position) * world_scale(phase)
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
			regions.append(LEGEND_RECT)
			regions.append(RESULT_RECT)
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
