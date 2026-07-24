class_name SlingshotEpisodeCanvas
extends Node2D

const ReplayTrack = preload("res://src/playback/replay_track.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const EpisodeDirector = preload("res://src/video/episode_director.gd")
const ShotCamera = preload("res://src/video/shot_camera.gd")
const TrajectoryAnnotation = preload("res://src/video/trajectory_annotation.gd")
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


func configure(
	normalized_episode: Dictionary,
	run_bundle: Dictionary,
	comparison: Dictionary
) -> void:
	episode = normalized_episode
	bundle = run_bundle
	analysis = comparison
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
	if _has_layer("grid"):
		_draw_grid()
	if _show_physical_stage():
		_draw_sling()
	if phase == "EXPLAIN" and _has_layer("annotations"):
		_draw_explanation_module()
	elif phase == "QUESTION" and _has_layer("subjects"):
		_draw_cold_open_teaser()
	if _show_physical_stage() and episode["story"].get("show_target", true):
		_draw_target_platform()
		_draw_reference_target()
	if _has_layer("trajectories"):
		_draw_trajectories()
	if phase in ["FLIGHT", "COMPARE"] and _has_layer("subjects"):
		if episode["story"].get("show_target", true):
			_draw_variant_targets()
		_draw_variant_birds()
		_draw_event_effects()
	if phase == "COMPARE" and _has_layer("results"):
		_draw_result_markers()
	elif phase == "COMPARE" and String(current_beat.get("overlay", "")) == "counterexample":
		_draw_focus_height_marker()


func _draw_explanation_module() -> void:
	if current_beat.get("overlay", "").begins_with("angle-"):
		_draw_angle_module()
	elif current_beat.get("overlay", "").begins_with("stretch-") or current_beat.get("overlay", "") == "spring-energy":
		_draw_energy_module()


func _draw_angle_module() -> void:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	var intro := smoothstep(0.0, 0.08, _beat_progress())
	var variants: Array = episode.get("variants", [])
	if variants.is_empty():
		return
	var weights := _angle_variant_weights(variants.size())
	var active_index := 0
	var active_weight := -1.0
	for index in range(variants.size()):
		var variant: Dictionary = variants[index]
		var id := String(variant["id"])
		var record: Dictionary = records_by_id.get(id, {})
		var weight := float(weights[index])
		if record.is_empty() or weight <= 0.001:
			continue
		if weight > active_weight:
			active_weight = weight
			active_index = index
		var mapped_points := _map_points(trajectories_by_id.get(id, PackedVector2Array()))
		if mapped_points.size() >= 2:
				draw_polyline(
					mapped_points,
					Color(colors_by_id[id], (0.10 + 0.48 * weight) * intro),
					VisualLanguage.width("context") + 3.0 * weight,
					true
				)
		var geometry := TrajectoryAnnotation.initial_geometry(record)
		if geometry.is_empty():
			continue
		var origin := _map_point(geometry["origin"])
		var tip := origin + Vector2(geometry["direction"]) * 300.0
		_draw_arrow(
			origin,
			tip,
			Color(colors_by_id[id], (0.12 + 0.70 * weight) * intro),
			VisualLanguage.width("measure") + 2.5 * weight
		)

	var active_variant: Dictionary = variants[active_index]
	var active_id := String(active_variant["id"])
	var active_record: Dictionary = records_by_id.get(active_id, {})
	var active_geometry := TrajectoryAnnotation.initial_geometry(active_record)
	if active_geometry.is_empty():
		return
	var origin := _map_point(active_geometry["origin"])
	var direction: Vector2 = active_geometry["direction"]
	var angle_deg := float(active_geometry["angle_deg"])
	var angle := deg_to_rad(angle_deg)
	var tip := origin + direction * 300.0
	var horizontal_tip := Vector2(tip.x, origin.y)
	var horizontal_color: Color = variants[0]["color"]
	var vertical_color: Color = variants[-1]["color"]
	draw_arc(origin, 82.0, -angle, 0.0, 36, Color(theme_colors["accent"], 0.72 * intro), VisualLanguage.STROKE_SECONDARY, true)
	draw_string(
		VideoTypography.data(),
		origin + Vector2(62, -18),
		"%.0f°" % angle_deg,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		24,
		Color(theme_colors["accent"], intro)
	)
	_draw_arrow(origin, horizontal_tip, Color(horizontal_color, 0.82 * intro), VisualLanguage.STROKE_SECONDARY)
	_draw_arrow(horizontal_tip, tip, Color(vertical_color, 0.82 * intro), VisualLanguage.STROKE_SECONDARY)
	draw_dashed_line(horizontal_tip, tip, Color(vertical_color, 0.24 * intro), VisualLanguage.STROKE_MEASURE, 8.0, true)
	_draw_module_label(tip + Vector2(18, -14), "v", Color(theme_colors["highlight"], intro))
	_draw_module_label(horizontal_tip + Vector2(-54, 36), "vₓ", Color(horizontal_color, intro))
	_draw_module_label(horizontal_tip.lerp(tip, 0.52) + Vector2(20, 0), "vᵧ", Color(vertical_color, intro))
	var points: PackedVector2Array = trajectories_by_id.get(active_id, PackedVector2Array())
	if not points.is_empty():
		var clock_center := _map_point(points[-1]) + Vector2(38, -62)
		draw_arc(clock_center, 28.0, 0.0, TAU, 28, Color(theme_colors["muted"], 0.48 * intro), VisualLanguage.STROKE_MEASURE, true)
		draw_line(clock_center, clock_center + Vector2(3, -17), Color(theme_colors["accent"], 0.76 * intro), VisualLanguage.STROKE_MEASURE, true)
		draw_line(clock_center, clock_center + Vector2(13, 6), Color(theme_colors["accent"], 0.76 * intro), VisualLanguage.STROKE_MEASURE, true)
		_draw_module_label(
			clock_center + Vector2(38, 8),
			"t = %.2f s" % TrajectoryAnnotation.flight_time_sec(active_record),
			Color(theme_colors["accent"], intro)
		)


func _draw_energy_module() -> void:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	var plot := EpisodeLayout.plot_rect_for_phase("EXPLAIN")
	var baseline := plot.position + Vector2(92, 560)
	var variants: Array = episode["variants"]
	var step := clampi(int(current_beat.get("formula_step", 0)), 0, 2)
	var max_energy := 0.0
	var energies: Array[float] = []
	for variant_value in variants:
		var variant: Dictionary = variant_value
		var physics: Dictionary = variant["preset"]["physics"]
		var energy := 0.5 * float(physics["spring_k_npm"]) * pow(float(physics["stretch_m"]), 2.0)
		energies.append(energy)
		max_energy = maxf(max_energy, energy)
	draw_line(baseline, baseline + Vector2(550, 0), Color(theme_colors["divider"], 0.72), VisualLanguage.STROKE_MEASURE, true)
	var winner_id := String(analysis.get("winner_id", ""))
	for index in range(variants.size()):
		var x := baseline.x + 45.0 + index * 135.0
		var bar_height := 250.0 * energies[index] / maxf(max_energy, 0.001)
		var reveal := _energy_bar_reveal(index, variants.size())
		var active := String(variants[index]["id"]) == winner_id
		var color: Color = theme_colors["accent"] if active else theme_colors["muted"]
		var bar_rect := Rect2(x, baseline.y - bar_height * reveal, 68, bar_height * reveal)
		draw_rect(bar_rect, Color(color, 0.20 if active else 0.055), true)
		draw_rect(
			bar_rect,
			Color(color, 0.82 if active else 0.30),
			false,
			VisualLanguage.STROKE_SECONDARY if active else VisualLanguage.STROKE_CONTEXT,
			true
		)
		draw_line(
			Vector2(x, baseline.y + 12),
			Vector2(x + 68, baseline.y + 12),
			Color(color, 0.86 if active else 0.34),
			VisualLanguage.STROKE_SECONDARY if active else VisualLanguage.STROKE_CONTEXT,
			true
		)
		_draw_module_label(
			Vector2(x - 10, baseline.y + 34),
			String(variants[index]["label"]),
			Color(theme_colors["text"], 0.90) if active else Color(theme_colors["muted"], 0.64)
		)
		if step >= 2:
			var value_alpha := smoothstep(0.0, 0.55, _beat_transition_progress())
			_draw_module_label(
				Vector2(x - 4, baseline.y - bar_height - 38),
				"%.1f J" % energies[index],
				Color(theme_colors["text"], value_alpha)
			)
	draw_string(
		VideoTypography.medium(),
		baseline + Vector2(0, -286),
		"储能  E",
		HORIZONTAL_ALIGNMENT_LEFT,
		180,
		18,
		Color(theme_colors["muted"], 0.72)
	)
	var spring_start := plot.position + Vector2(90, 130)
	var rest_finish := spring_start + Vector2(160.0, 0)
	var extension_factor := _spring_extension_factor()
	var spring_finish := rest_finish + Vector2(110.0 * extension_factor, 0)
	var coils := PackedVector2Array([spring_start])
	for coil in range(17):
		var ratio := float(coil + 1) / 18.0
		coils.append(spring_start.lerp(spring_finish, ratio) + Vector2(0, -18 if coil % 2 == 0 else 18))
	coils.append(spring_finish)
	draw_polyline(coils, Color(theme_colors["accent"], 0.88), VisualLanguage.STROKE_PRIMARY, true)
	draw_line(spring_start + Vector2(0, -48), spring_start + Vector2(0, 48), Color(theme_colors["muted"], 0.62), VisualLanguage.STROKE_SECONDARY, true)
	var dimension_y := spring_start.y - 64.0
	var dimension_color := Color(theme_colors["accent"], 0.74)
	draw_line(
		Vector2(rest_finish.x, dimension_y),
		Vector2(spring_finish.x, dimension_y),
		dimension_color,
		VisualLanguage.STROKE_MEASURE,
		true
	)
	draw_line(
		Vector2(rest_finish.x, dimension_y - 8.0),
		Vector2(rest_finish.x, dimension_y + 8.0),
		dimension_color,
		VisualLanguage.STROKE_MEASURE,
		true
	)
	draw_line(
		Vector2(spring_finish.x, dimension_y - 8.0),
		Vector2(spring_finish.x, dimension_y + 8.0),
		dimension_color,
		VisualLanguage.STROKE_MEASURE,
		true
	)
	draw_string(
		VideoTypography.data(),
		Vector2(rest_finish.x, dimension_y - 15.0),
		_spring_dimension_label(extension_factor),
		HORIZONTAL_ALIGNMENT_CENTER,
		spring_finish.x - rest_finish.x,
		24,
		theme_colors["accent"]
	)
	draw_line(
		rest_finish + Vector2(0, -30),
		rest_finish + Vector2(0, 30),
		Color(theme_colors["muted"], 0.28),
		VisualLanguage.STROKE_CONTEXT,
		true
	)


func _draw_arrow(start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	draw_line(start, finish, color, width, true)
	var direction := (finish - start).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var head := finish - direction * 22.0
	draw_colored_polygon(PackedVector2Array([finish, head + normal * 10.0, head - normal * 10.0]), color)


func _draw_module_label(position: Vector2, value: String, color: Color) -> void:
	draw_string(VideoTypography.data(), position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)


func _energy_bar_reveal(index: int, variant_count: int) -> float:
	var explain_elapsed := EpisodeLayout.phase_elapsed(episode, "EXPLAIN", video_time_sec)
	var sequence_progress := clampf(explain_elapsed / 4.0, 0.0, 1.0)
	return clampf(
		sequence_progress * float(variant_count + 1) - float(index),
		0.0,
		1.0
	)


func _beat_transition_progress() -> float:
	if current_beat.is_empty():
		return 1.0
	return smoothstep(
		0.0,
		1.0,
		clampf(
			(video_time_sec - float(current_beat.get("at", video_time_sec))) / 0.8,
			0.0,
			1.0
		)
	)


func _spring_extension_factor() -> float:
	var step := clampi(int(current_beat.get("formula_step", 0)), 0, 2)
	if step <= 0:
		return 1.0
	return lerpf(1.0, 2.0, _beat_transition_progress())


func _spring_dimension_label(extension_factor: float) -> String:
	if extension_factor <= 1.05:
		return "x"
	if extension_factor >= 1.95:
		return "2x"
	return "x → 2x"


func _beat_progress() -> float:
	if current_beat.is_empty():
		return 0.0
	return clampf(
		(video_time_sec - float(current_beat.get("at", video_time_sec)))
		/ maxf(0.001, float(current_beat.get("duration", 1.0))),
		0.0,
		1.0
	)


func _angle_variant_weights(variant_count: int) -> Array[float]:
	var result: Array[float] = []
	result.resize(variant_count)
	var step := clampi(int(current_beat.get("formula_step", 0)), 0, 2)
	if step != 1:
		var winner_id := String(analysis.get("winner_id", ""))
		var winner_index := clampi(variant_count / 2, 0, variant_count - 1)
		for index in range(episode.get("variants", []).size()):
			if String(episode["variants"][index]["id"]) == winner_id:
				winner_index = index
				break
		result[winner_index] = 1.0
		return result
	var position := smoothstep(0.04, 0.96, _beat_progress()) * float(variant_count - 1)
	for index in range(variant_count):
		result[index] = maxf(0.0, 1.0 - absf(position - float(index)))
	return result


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
			var full_points: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
			var setup_progress := clampf(
				EpisodeLayout.phase_elapsed(episode, phase, video_time_sec)
				/ float(episode["story"]["setup_sec"]),
				0.0,
				1.0
			)
			var reveal_progress := clampf(
				setup_progress * float(variants.size() + 1) - float(index),
				0.0,
				1.0
			)
			if reveal_progress <= 0.0:
				continue
			points = full_points.slice(
				0,
				maxi(2, int(full_points.size() * 0.16 * reveal_progress))
			)
			alpha = VisualLanguage.ALPHA_SECONDARY
			width = VisualLanguage.STROKE_SECONDARY
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
			if String(current_beat.get("id", "")) == "ranking":
				alpha = 0.58 if id == focus_id else VisualLanguage.ALPHA_CONTEXT
				width = VisualLanguage.STROKE_PRIMARY if id == focus_id else VisualLanguage.STROKE_CONTEXT
			elif String(current_beat.get("overlay", "")) == "counterexample":
				alpha = VisualLanguage.ALPHA_PRIMARY if id == focus_id else 0.035
				width = VisualLanguage.STROKE_PRIMARY if id == focus_id else VisualLanguage.STROKE_CONTEXT
			elif not focus_id.is_empty():
				alpha = VisualLanguage.ALPHA_PRIMARY if id == focus_id else VisualLanguage.ALPHA_CONTEXT
				width = VisualLanguage.STROKE_PRIMARY if id == focus_id else VisualLanguage.STROKE_CONTEXT
			else:
				alpha = VisualLanguage.ALPHA_PRIMARY if id == analysis.get("winner_id") else 0.22
				width = VisualLanguage.STROKE_PRIMARY if id == analysis.get("winner_id") else VisualLanguage.STROKE_MEASURE
		var mapped_points := _map_points(points)
		if mapped_points.size() >= 2:
			draw_polyline(mapped_points, Color(color, alpha), maxf(VisualLanguage.STROKE_CONTEXT, width * _world_scale()), true)
		if phase == "SETUP":
			var label_position := mapped_points[-1] + Vector2(18, -16 - index * 3)
			draw_string(
				VideoTypography.data(),
				label_position,
				String(variant["label"]),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				18,
				Color(color, 0.72)
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
			_draw_velocity_vector(
				state["bird_position_px"],
				state["bird_velocity_px_s"],
				colors_by_id[id]
			)


func _draw_cold_open_teaser() -> void:
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


func _draw_teaser_subject(
	id: String,
	label: String,
	variant_index: int,
	alpha: float,
	sequence_progress: float
) -> void:
	var record: Dictionary = records_by_id[id]
	var duration := float(record.get("duration_sec", 0.0))
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
			24,
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


func _draw_result_rail(rows: Array, winner_id: String) -> void:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	var rail := EpisodeLayout.RESULT_RAIL_RECT
	draw_string(
		VideoTypography.medium(),
		rail.position + Vector2(-170, 29),
		"落点射程",
		HORIZONTAL_ALIGNMENT_RIGHT,
		140,
		18,
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
			18 if winner else 16,
			theme_colors["text"] if winner else Color(theme_colors["muted"], 0.70)
		)
		draw_string(
			VideoTypography.data(),
			cell.position + Vector2(0, 72),
			"%.2f %s" % [float(row["value"]), String(analysis.get("metric_unit", ""))],
			HORIZONTAL_ALIGNMENT_CENTER,
			cell.size.x,
			26 if winner else 20,
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
			22,
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
		17,
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
	var overlay := String(current_beat.get("overlay", ""))
	return not (
		phase == "EXPLAIN"
		and (overlay.begins_with("stretch-") or overlay == "spring-energy")
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
		ShotCamera.transition_progress(current_beat, video_time_sec)
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


func _camera_anchor_for_beat(beat: Dictionary) -> Vector2:
	var shot := String(beat.get("shot", ""))
	var focus_id := String(beat.get("focus", ""))
	match shot:
		"relation", "formula", "launch":
			return launch_position_px
		"follow", "takeaway":
			var focus_state: Dictionary = states_by_id.get(focus_id, {})
			if not focus_state.is_empty():
				return Vector2(focus_state["bird_position_px"])
		"landing":
			return EpisodeLayout.SOURCE_WORLD_RECT.get_center()
		"comparison":
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
