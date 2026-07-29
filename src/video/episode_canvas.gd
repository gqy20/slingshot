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
		_configure_record(record)
	var first_variant: Dictionary = episode["variants"][0]
	var preset: Dictionary = first_variant["preset"]
	_configure_domain_geometry(preset)
	camera_state = ShotCamera.desired_state(
		"QUESTION",
		episode.get("beats", [{}])[0],
		EpisodeLayout.SOURCE_WORLD_RECT.get_center()
	)
	queue_redraw()


func _configure_record(record: Dictionary) -> void:
	trajectories_by_id[record["variant_id"]] = ReplayTrack.full_trajectory(record)


func _configure_domain_geometry(preset: Dictionary) -> void:
	var ppm: float = preset["physics"]["pixels_per_meter"]
	launch_position_px = preset["scene"]["launch_position_m"] * ppm
	target_position_px = preset["scene"]["target_position_m"] * ppm
	ground_y_px = preset["scene"]["ground_y_m"] * ppm


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
	_draw_domain()


func _draw_domain() -> void:
	_draw_projectile_episode()


func _draw_projectile_episode() -> void:
	var overlay := String(current_beat.get("overlay", ""))
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
