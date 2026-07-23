class_name SlingshotEpisodeCanvas
extends Node2D

const ReplayTrack = preload("res://src/playback/replay_track.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")

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
	queue_redraw()


func _draw() -> void:
	_draw_background()
	if _has_layer("grid"):
		_draw_grid()
	if _has_layer("world"):
		_draw_sling()
	if phase == "EXPLAIN" and _has_layer("annotations"):
		_draw_explanation_module()
	elif phase == "QUESTION" and _has_layer("subjects"):
		_draw_cold_open_teaser()
	if _has_layer("world") and episode["story"].get("show_target", true):
		_draw_target_platform()
		_draw_reference_target()
	if _has_layer("trajectories"):
		_draw_trajectories()
	if phase in ["FLIGHT", "COMPARE"] and _has_layer("subjects"):
		if episode["story"].get("show_target", true):
			_draw_variant_targets()
		_draw_variant_birds()
		_draw_event_effects()


func _draw_explanation_module() -> void:
	if current_beat.get("overlay", "").begins_with("angle-"):
		_draw_angle_module()
	elif current_beat.get("overlay", "").begins_with("stretch-") or current_beat.get("overlay", "") == "spring-energy":
		_draw_energy_module()


func _draw_angle_module() -> void:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	var plot := EpisodeLayout.plot_rect_for_phase("EXPLAIN")
	var origin := plot.position + Vector2(130, 475)
	var angle_deg: float = [28.0, 52.0, 45.0][clampi(int(current_beat.get("formula_step", 0)), 0, 2)]
	var angle := deg_to_rad(angle_deg)
	var vector_length := 310.0
	var tip := origin + Vector2(cos(angle), -sin(angle)) * vector_length
	var horizontal_tip := Vector2(tip.x, origin.y)
	var progress := _beat_progress()
	var handoff := _formula_handoff()
	draw_arc(origin, 105.0, -angle, 0.0, 36, Color(theme_colors["accent"], 0.72), 4.0, true)
	draw_string(
		VideoTypography.data(),
		origin + Vector2(82, -24),
		"θ",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		28,
		theme_colors["accent"]
	)
	_draw_arrow(origin, tip, theme_colors["highlight"], 6.0)
	_draw_arrow(origin, horizontal_tip, episode["variants"][0]["color"], 4.0)
	_draw_arrow(horizontal_tip, tip, episode["variants"][-1]["color"], 4.0)
	draw_dashed_line(horizontal_tip, tip, Color(theme_colors["muted"], 0.32), 2.0, 8.0, true)
	var pulse := 0.7 + 0.3 * sin(progress * TAU)
	draw_circle(tip, 13.0 + pulse * 4.0, Color(theme_colors["highlight"], 0.30))
	var horizontal_token_start := origin + Vector2(176, 42)
	var horizontal_token_finish := Vector2(plot.end.x - 54, plot.position.y + 205)
	_draw_migrating_token(
		horizontal_token_start,
		horizontal_token_finish,
		"vₓ",
		episode["variants"][0]["color"],
		handoff
	)
	_draw_module_label(origin + Vector2(315, -126), "vᵧ  垂直分量", episode["variants"][-1]["color"])
	_draw_module_label(origin + Vector2(214, -250), "v  初速度", theme_colors["highlight"])
	var clock_center := origin + Vector2(465, -275)
	draw_arc(clock_center, 34.0, 0.0, TAU, 32, Color(theme_colors["muted"], 0.55), 3.0, true)
	draw_line(clock_center, clock_center + Vector2(4, -21), theme_colors["accent"], 3.0, true)
	draw_line(clock_center, clock_center + Vector2(17, 8), theme_colors["accent"], 3.0, true)
	_draw_migrating_token(
		clock_center + Vector2(46, 8),
		Vector2(plot.end.x - 54, plot.position.y + 275),
		"t",
		theme_colors["accent"],
		handoff
	)


func _draw_energy_module() -> void:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	var plot := EpisodeLayout.plot_rect_for_phase("EXPLAIN")
	var baseline := plot.position + Vector2(92, 560)
	var variants: Array = episode["variants"]
	var step := clampi(int(current_beat.get("formula_step", 0)), 0, 2)
	var handoff := _formula_handoff()
	var max_energy := 0.0
	var energies: Array[float] = []
	for variant_value in variants:
		var variant: Dictionary = variant_value
		var physics: Dictionary = variant["preset"]["physics"]
		var energy := 0.5 * float(physics["spring_k_npm"]) * pow(float(physics["stretch_m"]), 2.0)
		energies.append(energy)
		max_energy = maxf(max_energy, energy)
	draw_line(baseline, baseline + Vector2(550, 0), theme_colors["divider"], 3.0, true)
	for index in range(variants.size()):
		var x := baseline.x + 45.0 + index * 135.0
		var bar_height := 250.0 * energies[index] / maxf(max_energy, 0.001)
		var reveal := clampf(_beat_progress() * 1.4 - index * 0.12, 0.0, 1.0)
		var color: Color = variants[index]["color"]
		draw_rect(Rect2(x, baseline.y - bar_height * reveal, 68, bar_height * reveal), Color(color, 0.82), true)
		draw_line(Vector2(x, baseline.y + 12), Vector2(x + 68, baseline.y + 12), color, 4.0, true)
		_draw_module_label(Vector2(x - 10, baseline.y + 34), String(variants[index]["label"]), color)
		if step >= 2:
			_draw_module_label(Vector2(x - 4, baseline.y - bar_height - 38), "%.1f J" % energies[index], theme_colors["text"])
	var spring_start := plot.position + Vector2(90, 130)
	var spring_finish := spring_start + Vector2(460.0 * (0.55 + step * 0.20), 0)
	var coils := PackedVector2Array([spring_start])
	for coil in range(17):
		var ratio := float(coil + 1) / 18.0
		coils.append(spring_start.lerp(spring_finish, ratio) + Vector2(0, -18 if coil % 2 == 0 else 18))
	coils.append(spring_finish)
	draw_polyline(coils, theme_colors["accent"], 5.0, true)
	draw_line(spring_start + Vector2(0, -48), spring_start + Vector2(0, 48), theme_colors["muted"], 5.0, true)
	_draw_migrating_token(
		spring_finish + Vector2(-18, -64),
		Vector2(plot.end.x - 52, plot.position.y + 190),
		"x",
		theme_colors["accent"],
		handoff
	)
	var energy_token_start := baseline + Vector2(480, -280)
	_draw_migrating_token(
		energy_token_start,
		Vector2(plot.end.x - 52, plot.position.y + 270),
		"E",
		theme_colors["highlight"],
		handoff
	)


func _draw_arrow(start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	draw_line(start, finish, color, width, true)
	var direction := (finish - start).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var head := finish - direction * 22.0
	draw_colored_polygon(PackedVector2Array([finish, head + normal * 10.0, head - normal * 10.0]), color)


func _draw_module_label(position: Vector2, value: String, color: Color) -> void:
	draw_string(VideoTypography.data(), position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)


func _draw_migrating_token(
	start: Vector2,
	finish: Vector2,
	value: String,
	color: Color,
	progress: float
) -> void:
	var eased := smoothstep(0.0, 1.0, progress)
	var position := start.lerp(finish, eased)
	if eased > 0.02:
		draw_dashed_line(start, position, Color(color, 0.22 * eased), 2.0, 9.0, true)
	draw_circle(position + Vector2(10, -8), 24.0, Color(color, 0.08 + 0.08 * eased))
	draw_string(VideoTypography.data(), position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, color)


func _formula_handoff() -> float:
	var reveal := float(current_beat.get("formula_reveal", 0.42))
	return smoothstep(maxf(0.0, reveal - 0.30), reveal, _beat_progress())


func _beat_progress() -> float:
	if current_beat.is_empty():
		return 0.0
	return clampf(
		(video_time_sec - float(current_beat.get("at", video_time_sec)))
		/ maxf(0.001, float(current_beat.get("duration", 1.0))),
		0.0,
		1.0
	)


func _draw_background() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var mode := _shot_mode()
	draw_rect(Rect2(Vector2.ZERO, EpisodeLayout.CANVAS_SIZE), colors["background"], true)
	draw_rect(Rect2(0, 0, 1920, 920), colors["stage"], true)
	var plot := EpisodeLayout.plot_rect_for_phase(phase, mode)
	if mode == "measurement":
		draw_rect(plot, Color(colors["surface"], 0.34), true)
		draw_rect(Rect2(plot.position, Vector2(plot.size.x, 1)), colors["divider"], true)
	var glow_center := _map_point(Vector2(1550, 220))
	var scale_value := _world_scale()
	for band in range(5):
		var alpha := 0.022 - float(band) * 0.003
		draw_circle(
			glow_center,
			(110.0 + band * 44.0) * scale_value,
			Color(colors["accent"], alpha)
		)
	var ground_start := _map_point(Vector2(0, ground_y_px))
	var ground_end := _map_point(Vector2(1920, ground_y_px))
	draw_rect(
		Rect2(
			Vector2(ground_start.x, ground_start.y),
			Vector2(ground_end.x - ground_start.x, maxf(0.0, plot.end.y - ground_start.y))
		),
		colors["ground"],
		true
	)
	draw_line(ground_start, ground_end, colors["ground_line"], maxf(2.0, 5.0 * scale_value), true)


func _draw_grid() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var minor := Color(colors["divider"], 0.24)
	var major := Color(colors["divider"], 0.44)
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
	var frame_shadow := Color("#1B1715")
	var frame_color := Color("#76513C")
	var frame_highlight := Color("#B47A53")
	for points in [[left_foot, left_tip], [right_foot, right_tip]]:
		draw_line(points[0], points[1], frame_shadow, maxf(9.0, 30.0 * scale_value), true)
		draw_line(points[0], points[1], frame_color, maxf(7.0, 22.0 * scale_value), true)
		draw_line(
			points[0] + Vector2(-2, -1) * scale_value,
			points[1] + Vector2(-2, -1) * scale_value,
			frame_highlight,
			maxf(1.5, 4.0 * scale_value),
			true
		)
	draw_circle(left_tip, maxf(5.0, 10.0 * scale_value), frame_color)
	draw_circle(right_tip, maxf(5.0, 10.0 * scale_value), frame_color)

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
		Color("#57434B"),
		maxf(5.0, 11.0 * scale_value),
		true
	)

	var base_left := _map_point(base + Vector2(-48, 64))
	var base_right := _map_point(base + Vector2(48, 86))
	draw_rect(Rect2(base_left, base_right - base_left), Color("#4A3528"), true)
	for wrap_index in range(3):
		var wrap_y := lerpf(base_left.y + 4, base_right.y - 4, float(wrap_index + 1) / 4.0)
		draw_line(
			Vector2(base_left.x + 8, wrap_y),
			Vector2(base_right.x - 8, wrap_y),
			Color(colors["accent"], 0.22),
			1.5,
			true
		)

	if phase == "SETUP" and tension > 0.18:
		_draw_tension_sparks(left_tip, pouch, accent, -1)
		_draw_tension_sparks(right_tip, pouch, accent, 1)
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
	draw_polyline(points, Color("#171419"), 9.0, true)
	draw_polyline(points, Color(accent, 0.72 + tension * 0.20), 4.5, true)
	draw_polyline(points, Color(1.0, 0.86, 0.66, 0.14 + tension * 0.18), 1.2, true)


func _draw_tension_sparks(start: Vector2, finish: Vector2, color: Color, seed: int) -> void:
	for spark_index in range(5):
		var offset := float(spark_index) / 5.0
		var travel := fposmod(video_time_sec * 0.72 + offset + seed * 0.11, 1.0)
		var position := start.lerp(finish, travel)
		var pulse := 0.55 + 0.45 * sin((video_time_sec + spark_index) * 7.0)
		draw_circle(position, 2.0 + pulse * 2.0, Color(color, 0.35 + pulse * 0.35))


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
			alpha = 0.48
		elif phase == "FLIGHT":
			points = ReplayTrack.partial_trajectory(
				records_by_id[id],
				float(simulation_times_by_id.get(id, 0.0))
			)
			alpha = 0.72
			width = 4.0
		else:
			points = trajectories_by_id.get(id, PackedVector2Array())
			var focus_id := String(current_beat.get("focus", ""))
			if not focus_id.is_empty():
				alpha = 0.98 if id == focus_id else 0.14
				width = 8.0 if id == focus_id else 2.0
			else:
				alpha = 0.98 if id == analysis.get("winner_id") else 0.34
				width = 8.0 if id == analysis.get("winner_id") else 3.0
		var mapped_points := _map_points(points)
		if mapped_points.size() >= 2:
			draw_polyline(mapped_points, Color(color, alpha), maxf(2.0, width * _world_scale()), true)
		if phase == "SETUP":
			for point_index in range(0, mapped_points.size(), 7):
				draw_circle(mapped_points[point_index], 3.5, Color(color, 0.68))


func _draw_variant_birds() -> void:
	var variants: Array = episode.get("variants", [])
	for index in range(variants.size()):
		var variant: Dictionary = variants[index]
		var id: String = variant["id"]
		var state: Dictionary = states_by_id.get(id, {})
		if state.is_empty():
			continue
		var winner: bool = _winner_emphasis_enabled() and id == analysis.get("winner_id")
		var focus_id := String(current_beat.get("focus", ""))
		var bird_alpha := 1.0 if winner else 0.88
		if not focus_id.is_empty() and id != focus_id:
			bird_alpha = 0.48
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
	var focus_id := String(current_beat.get("focus", ""))
	if focus_id.is_empty() or not records_by_id.has(focus_id):
		return
	_draw_teaser_subject(
		focus_id,
		String(current_beat.get("focus_label", "")),
		0,
		1.0
	)
	var secondary_id := String(current_beat.get("focus_secondary", ""))
	if not secondary_id.is_empty() and records_by_id.has(secondary_id):
		_draw_teaser_subject(
			secondary_id,
			String(current_beat.get("focus_secondary_label", "")),
			1,
			0.88
		)


func _draw_teaser_subject(id: String, label: String, variant_index: int, alpha: float) -> void:
	var record: Dictionary = records_by_id[id]
	var duration := float(record.get("duration_sec", 0.0))
	var teaser_time := duration * lerpf(0.42, 0.88, smoothstep(0.0, 1.0, _beat_progress()))
	var state := ReplayTrack.sample(record, teaser_time)
	var full_points: PackedVector2Array = trajectories_by_id.get(id, PackedVector2Array())
	var reveal_count := mini(full_points.size(), maxi(2, int(full_points.size() * 0.82)))
	var teaser_points := _map_points(full_points.slice(0, reveal_count))
	if teaser_points.size() >= 2:
		draw_polyline(teaser_points, Color(colors_by_id[id], 0.34 * alpha), 4.0, true)
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
	elif beat_id == "landing":
		_draw_landing_dust()
	elif _winner_emphasis_enabled() and _beat_progress() > 0.18:
		_draw_result_celebration()


func _draw_release_burst() -> void:
	var progress := clampf(_beat_progress() * 4.0, 0.0, 1.0)
	if progress >= 1.0:
		return
	var center := _map_point(launch_position_px)
	var color: Color = episode["theme"]["colors"]["accent"]
	for ray_index in range(10):
		var angle := TAU * float(ray_index) / 10.0 + 0.18
		var direction := Vector2.from_angle(angle)
		var start := center + direction * lerpf(18.0, 58.0, progress)
		var finish := start + direction * lerpf(24.0, 4.0, progress)
		draw_line(start, finish, Color(color, 1.0 - progress), 4.0, true)
	draw_arc(center, lerpf(24.0, 86.0, progress), 0.0, TAU, 40, Color(color, 0.65 * (1.0 - progress)), 4.0, true)


func _draw_landing_dust() -> void:
	var theme_colors: Dictionary = episode["theme"]["colors"]
	for index in range(episode["variants"].size()):
		var variant: Dictionary = episode["variants"][index]
		var state: Dictionary = states_by_id.get(variant["id"], {})
		if state.is_empty():
			continue
		var position := _map_point(state["bird_position_px"])
		var ground := _map_point(Vector2(state["bird_position_px"].x, ground_y_px))
		if absf(position.y - ground.y) > 36.0:
			continue
		for puff_index in range(4):
			var seed := float(index * 7 + puff_index)
			var pulse := fposmod(_beat_progress() * 3.0 + seed * 0.17, 1.0)
			var puff_position := ground + Vector2((puff_index - 1.5) * 18.0, -pulse * 34.0)
			draw_circle(puff_position, lerpf(8.0, 22.0, pulse), Color(theme_colors["muted"], 0.18 * (1.0 - pulse)))


func _draw_result_celebration() -> void:
	var winner_id := String(analysis.get("winner_id", ""))
	var state: Dictionary = states_by_id.get(winner_id, {})
	if state.is_empty():
		return
	var center := _map_point(state["bird_position_px"])
	var winner_color: Color = colors_by_id[winner_id]
	var pulse := 0.5 + 0.5 * sin(video_time_sec * 5.0)
	for index in range(12):
		var angle := TAU * float(index) / 12.0 + video_time_sec * 0.12
		var radius := 72.0 + float(index % 3) * 18.0 + pulse * 8.0
		var point := center + Vector2.from_angle(angle) * radius
		var size := 4.0 + float(index % 2) * 3.0
		draw_rect(Rect2(point - Vector2.ONE * size, Vector2.ONE * size * 2.0), Color(winner_color, 0.62), true)
	var crown := PackedVector2Array([
		center + Vector2(-30, -52), center + Vector2(-22, -82),
		center + Vector2(-4, -62), center + Vector2(8, -88),
		center + Vector2(25, -62), center + Vector2(31, -82),
		center + Vector2(34, -50),
	])
	draw_polyline(crown, episode["theme"]["colors"]["accent"], 5.0, true)


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
		for streak_index in range(3):
			var distance := 35.0 + streak_index * 17.0
			var tail := position - direction * distance * visual_scale
			draw_line(
				tail,
				tail + direction * (18.0 + streak_index * 4.0) * visual_scale,
				Color(color, 0.18 - streak_index * 0.035),
				maxf(1.0, (4.0 - streak_index) * visual_scale),
				true
			)
	if winner:
		var halo_pulse := 1.0 + sin(video_time_sec * 4.0) * 0.08
		draw_circle(position, 48.0 * visual_scale * halo_pulse, Color(color, 0.10))
		draw_arc(
			position,
			42.0 * visual_scale * halo_pulse,
			0.0,
			TAU,
			48,
			Color(color, 0.76),
			maxf(2.0, 3.0 * visual_scale),
			true
		)

	var stretch_x := 1.0
	var stretch_y := 1.0
	if phase == "FLIGHT":
		var launch_elapsed := EpisodeLayout.phase_elapsed(episode, phase, video_time_sec)
		var launch_pulse := exp(-launch_elapsed * 4.8)
		stretch_x += 0.24 * launch_pulse
		stretch_y -= 0.14 * launch_pulse
	elif phase == "COMPARE":
		var landing_elapsed := EpisodeLayout.phase_elapsed(episode, phase, video_time_sec)
		var bounce := exp(-landing_elapsed * 3.6) * absf(cos(landing_elapsed * 13.0))
		stretch_x += 0.18 * bounce
		stretch_y -= 0.22 * bounce
	elif preview:
		stretch_x = 0.94
		stretch_y = 1.08

	draw_set_transform(
		position,
		rotation_value,
		Vector2(visual_scale * stretch_x, visual_scale * stretch_y)
	)
	var wing_lift := sin(video_time_sec * 9.0 + variant_index * 0.9) * 3.5
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-20, 4), Vector2(-45, -10), Vector2(-31, 9),
		]),
		Color(color.darkened(0.24), alpha)
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-19, -5), Vector2(-40, -28), Vector2(-28, 1),
		]),
		Color(color.lightened(0.04), alpha)
	)
	draw_circle(Vector2.ZERO, 25.0, theme_colors["background"])
	draw_circle(Vector2(-2, -1), 22.0, Color(color, alpha))
	draw_circle(Vector2(-7, 8), 13.0, Color(color.darkened(0.16), alpha))
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-13, 4 + wing_lift),
			Vector2(1, 14 + wing_lift * 0.35),
			Vector2(9, 2 + wing_lift * 0.10),
			Vector2(-6, -4 + wing_lift * 0.25),
		]),
		Color(color.darkened(0.28), alpha)
	)
	draw_arc(Vector2(-4, 4 + wing_lift * 0.25), 10.0, 0.15, 2.65, 16, Color(1, 1, 1, 0.18), 2.0)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(20, -4), Vector2(43, 4), Vector2(20, 13),
		]),
		Color(theme_colors["accent"], alpha)
	)
	var blink_phase := fposmod(video_time_sec + variant_index * 0.71, 3.6)
	if blink_phase > 3.42:
		draw_line(Vector2(5, -10), Vector2(16, -9), Color(theme_colors["text"], alpha), 3.0, true)
	else:
		draw_circle(Vector2(10, -10), 7.0, Color(theme_colors["text"], alpha))
		draw_circle(Vector2(13, -10), 3.0, theme_colors["background"])
	draw_line(
		Vector2(4, -19),
		Vector2(18, -16 if winner else -15),
		Color("#2B2024"),
		3.5,
		true
	)
	draw_circle(Vector2(8, 5), 3.5, Color(1.0, 0.52, 0.48, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if phase == "COMPARE":
		var landing_elapsed := EpisodeLayout.phase_elapsed(episode, phase, video_time_sec)
		if landing_elapsed < 1.1 and source_position.y > ground_y_px - 70.0:
			var dust_alpha := 1.0 - landing_elapsed / 1.1
			for dust_index in range(4):
				var side := -1.0 if dust_index % 2 == 0 else 1.0
				var dust_position := position + Vector2(
					side * (18.0 + dust_index * 8.0) * landing_elapsed,
					8.0 - landing_elapsed * (14.0 + dust_index * 2.0)
				)
				draw_circle(
					dust_position,
					3.0 + dust_index,
					Color(theme_colors["muted"], dust_alpha * 0.24)
				)


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
	draw_line(start, finish, Color(color, 0.38), 2.5, true)
	draw_colored_polygon(
		PackedVector2Array([
			finish,
			finish - direction * 12.0 + perpendicular * 5.0,
			finish - direction * 12.0 - perpendicular * 5.0,
		]),
		Color(color, 0.42)
	)


func _map_point(point: Vector2) -> Vector2:
	return EpisodeLayout.map_world(point, phase, _shot_mode())


func _map_points(points: PackedVector2Array) -> PackedVector2Array:
	var mapped := PackedVector2Array()
	for point in points:
		mapped.append(_map_point(point))
	return mapped


func _world_scale() -> float:
	return EpisodeLayout.world_scale(phase, _shot_mode())


func _shot_mode() -> String:
	return String(current_beat.get("mode", "measurement"))


func _has_layer(layer: String) -> bool:
	var layers: Array = current_beat.get("layers", [])
	return layer in layers


func _winner_emphasis_enabled() -> bool:
	return phase == "COMPARE" and _has_layer("results")
