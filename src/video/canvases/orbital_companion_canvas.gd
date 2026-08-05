extends "res://src/video/episode_canvas.gd"

const CelestialBody = preload("res://src/video/celestial_body_sprite.gd")
const SUN := Color("#FFC76A")
const EARTH := Color("#69A9FF")
const ASTEROID := Color("#F08A55")
const CONTROL := Color("#8A8F98")
const ORBIT_FAINT := Color(0.55, 0.60, 0.68, 0.28)
const CONTENT_BOTTOM := 875.0
const PRIMARY_YEAR_START_JD := 2461041.5
const PRIMARY_YEAR_END_JD := 2461406.5
const MOON_LEFT_REGION := Rect2(280, 300, 460, 500)
const MOON_RIGHT_REGION := Rect2(1090, 250, 500, 550)
const RENDEZVOUS_STAGE_REGION := Rect2(400, 245, 1200, 390)
const RENDEZVOUS_ERROR_REGION := Rect2(130, 645, 540, 165)
const OPTICAL_STAGE_REGION := Rect2(110, 225, 1590, 475)
const OPTICAL_EVIDENCE_REGION := Rect2(940, 705, 860, 110)

var celestial_pools := {"earth": [], "sun": [], "moon": []}
var celestial_pool_indices := {"earth": 0, "sun": 0, "moon": 0}


func _ready() -> void:
	_ensure_celestial_pool()
	_layout_celestial_sprites()


func set_playback(
	value_phase: String,
	times: Dictionary,
	states: Dictionary,
	elapsed_video_sec: float = 0.0,
	beat: Dictionary = {}
) -> void:
	super.set_playback(value_phase, times, states, elapsed_video_sec, beat)
	_layout_celestial_sprites()


static func layout_audit_regions() -> Dictionary:
	return {
		"moon-comparison": [MOON_LEFT_REGION, MOON_RIGHT_REGION],
		"rendezvous": [RENDEZVOUS_STAGE_REGION, RENDEZVOUS_ERROR_REGION],
		"optical-navigation": [OPTICAL_STAGE_REGION, OPTICAL_EVIDENCE_REGION],
	}


func _configure_domain_geometry(_preset: Dictionary) -> void:
	pass


func _draw_background() -> void:
	# Orbital scenes have no physical ground. The base projectile canvas draws a
	# camera-mapped horizon here, which becomes a stray divider during reframes.
	var colors: Dictionary = episode["theme"]["colors"]
	draw_rect(Rect2(Vector2.ZERO, EpisodeLayout.CANVAS_SIZE), colors["background"], true)


func _configure_record(record: Dictionary) -> void:
	var points := PackedVector2Array()
	for frame_value in record.get("frames", []):
		var frame: Dictionary = frame_value
		points.append(_vector(frame["asteroid_position_au"]))
	trajectories_by_id[record["variant_id"]] = points


func _draw_domain() -> void:
	_draw_space_field()
	match String(current_beat.get("id", "")):
		"cold-open":
			_draw_earth_fixed_view(true)
		"earth-frame":
			_draw_earth_fixed_view(false)
		"brand-gate":
			_draw_brand_gate()
		"tianwen-arrival":
			_draw_tianwen_arrival()
		"sun-reveal":
			_draw_sun_view(true)
		"speed-change":
			_draw_sun_view(true)
			_draw_speed_evidence()
		"same-state-two-frames":
			_draw_split_reference_frames()
		"resonance-boundary":
			_draw_drift_control()
		"moon-comparison":
			_draw_moon_comparison()
		"rendezvous":
			_draw_rendezvous_principle()
		"optical-navigation":
			_draw_optical_navigation()
		"science-close":
			_draw_science_close()
		_:
			_draw_sun_view(true)


func _draw_earth_fixed_view(show_headline: bool) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var center := Vector2(960, 500)
	var camera_progress := smoothstep(0.0, 0.58, _beat_progress()) if show_headline else 1.0
	var scale := lerpf(760.0, 1150.0, camera_progress)
	_draw_rotating_path("co-orbital", center, scale, Color(ASTEROID, 0.48))
	_draw_orbit_depth_rings(center, 250.0, EARTH)
	_draw_planet(center, 29.0, EARTH, "地球")
	var state := _state("co-orbital")
	var asteroid_position := center + _vector(state.get("relative_rotating_au", Vector2.ZERO)) * scale
	_draw_asteroid(asteroid_position, ASTEROID)
	_draw_axes(center, 250.0, Color(colors["divider"], 0.8))
	_draw_badge("随地球转动的视角", Vector2(116, 128), EARTH)
	if show_headline:
		draw_string(VideoTypography.bold(), Vector2(116, 222), "它在绕地球吗？", HORIZONTAL_ALIGNMENT_LEFT, -1, 50, colors["text"])
	_draw_model_boundary()


func _draw_sun_view(show_path: bool) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var center := Vector2(830, 505)
	var scale := lerpf(265.0, 315.0, smoothstep(0.0, 0.55, _beat_progress()))
	_draw_sun(center, 24.0)
	_draw_orbit_depth_rings(center, scale, SUN)
	_draw_smooth_arc(center, scale, 0.0, TAU, Color(EARTH, 0.30), 2.0)
	if show_path:
		_draw_heliocentric_path("co-orbital", center, scale, Color(ASTEROID, 0.42))
	var state := _state("co-orbital")
	var earth_position := center + _vector(state.get("earth_position_au", Vector2.RIGHT)) * scale
	var asteroid_position := center + _vector(state.get("asteroid_position_au", Vector2.RIGHT)) * scale
	_draw_planet(earth_position, 17.0, EARTH, "地球")
	_draw_asteroid(asteroid_position, ASTEROID)
	draw_string(VideoTypography.medium(), center + Vector2(-34, 58), "太阳", HORIZONTAL_ALIGNMENT_CENTER, 68, 25, colors["muted"])
	_draw_badge("日心惯性参考系", Vector2(116, 128), SUN)
	draw_string(VideoTypography.bold(), Vector2(1250, 260), "两者都绕太阳", HORIZONTAL_ALIGNMENT_LEFT, 520, 44, colors["text"])
	draw_string(VideoTypography.medium(), Vector2(1250, 322), "地球不是这条轨道的中心", HORIZONTAL_ALIGNMENT_LEFT, 540, 29, colors["muted"])
	_draw_model_boundary()


func _draw_split_reference_frames() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var left := Rect2(70, 170, 845, 650)
	var right := Rect2(1005, 170, 845, 650)
	draw_rect(left, colors["surface"], true)
	draw_rect(right, colors["surface"], true)
	draw_rect(left, Color(SUN, 0.18), false, 2.0)
	draw_rect(right, Color(EARTH, 0.18), false, 2.0)
	draw_string(VideoTypography.bold(), left.position + Vector2(34, 56), "太阳参考系", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, colors["text"])
	draw_string(VideoTypography.bold(), right.position + Vector2(34, 56), "随地球转动", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, colors["text"])
	var left_center := left.get_center() + Vector2(0, 35)
	var right_center := right.get_center() + Vector2(0, 35)
	var sun_scale := 225.0
	var relative_scale := 720.0
	_draw_sun(left_center, 15.0)
	_draw_smooth_arc(left_center, sun_scale, 0.0, TAU, Color(EARTH, 0.25), 2.0)
	_draw_heliocentric_path("co-orbital", left_center, sun_scale, Color(ASTEROID, 0.42))
	_draw_rotating_path("co-orbital", right_center, relative_scale, Color(ASTEROID, 0.46))
	var state := _state("co-orbital")
	_draw_planet(left_center + _vector(state["earth_position_au"]) * sun_scale, 12.0, EARTH, "")
	_draw_asteroid(left_center + _vector(state["asteroid_position_au"]) * sun_scale, ASTEROID)
	_draw_planet(right_center, 18.0, EARTH, "")
	_draw_asteroid(right_center + _vector(state["relative_rotating_au"]) * relative_scale, ASTEROID)
	draw_string(VideoTypography.medium(), Vector2(590, 865), "同一时刻 · 同一组位置 · 只换坐标", HORIZONTAL_ALIGNMENT_CENTER, 740, 32, colors["text"])
	_draw_model_boundary()


func _draw_speed_evidence() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var state := _state("co-orbital")
	var distance := float(state.get("solar_distance_au", 1.0))
	var speed := float(state.get("orbital_speed_au_y", TAU))
	var panel := Rect2(1230, 410, 550, 270)
	draw_rect(panel, Color(colors["surface_elevated"], 0.96), true)
	draw_rect(panel, Color(ASTEROID, 0.22), false, 2.0)
	draw_string(VideoTypography.medium(), panel.position + Vector2(36, 56), "此刻的日心状态", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, colors["muted"])
	draw_string(VideoTypography.data(), panel.position + Vector2(36, 116), "距离  %.3f AU" % distance, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, colors["text"])
	draw_string(VideoTypography.data(), panel.position + Vector2(36, 170), "速度  %.2f AU/年" % speed, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ASTEROID)
	var relation := "更靠近太阳 → 更快" if distance < 1.0 else "更远离太阳 → 更慢"
	draw_string(VideoTypography.bold(), panel.position + Vector2(36, 232), relation, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, colors["text"])


func _draw_drift_control() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var left := Vector2(520, 520)
	var right := Vector2(1400, 520)
	_draw_rotating_path("co-orbital", left, 880.0, Color(ASTEROID, 0.08))
	_draw_partial_rotating_path("co-orbital", left, 880.0, _beat_progress(), 145, Color(ASTEROID, 0.86))
	_draw_rotating_path("drifting-control", right, 260.0, Color(CONTROL, 0.18))
	_draw_partial_rotating_path("drifting-control", right, 260.0, _beat_progress(), 240, Color(CONTROL, 0.82))
	_draw_planet(left, 23, EARTH, "")
	_draw_planet(right, 23, EARTH, "")
	var co_state := _state("co-orbital")
	var drift_state := _state("drifting-control")
	_draw_asteroid(left + _vector(co_state.get("relative_rotating_au", Vector2.ZERO)) * 880.0, ASTEROID)
	_draw_asteroid(right + _vector(drift_state.get("relative_rotating_au", Vector2.ZERO)) * 260.0, CONTROL)
	draw_string(VideoTypography.bold(), left + Vector2(-190, 100), "真实星历：始终留在附近", HORIZONTAL_ALIGNMENT_CENTER, 380, 28, colors["text"])
	draw_string(VideoTypography.bold(), right + Vector2(-190, 100), "只有周期接近：持续漂移", HORIZONTAL_ALIGNMENT_CENTER, 380, 28, colors["text"])
	var display_year := int(round(2010.0 + 40.0 * _beat_progress()))
	draw_string(VideoTypography.data(), Vector2(760, 245), "%d" % display_year, HORIZONTAL_ALIGNMENT_CENTER, 400, 30, ASTEROID)
	_draw_model_boundary("JPL Horizons 星历 · 黄道平面投影 · 41 年压缩")
	draw_string(VideoTypography.bold(), Vector2(110, 190), "周期接近，不等于长期锁定", HORIZONTAL_ALIGNMENT_LEFT, 760, 46, colors["text"])
	draw_string(VideoTypography.medium(), Vector2(110, 830), "真实长期轨迹保持在地球附近；右侧只有周期接近，环会逐渐打开", HORIZONTAL_ALIGNMENT_LEFT, 1100, 31, colors["muted"])


func _draw_tianwen_arrival() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var asteroid_position := Vector2(1450, 500)
	var probe_position := Vector2(260, 600).lerp(Vector2(1260, 520), smoothstep(0.08, 0.80, progress))
	_draw_arrival_corridor(Vector2(260, 600), asteroid_position, progress)
	_draw_asteroid(asteroid_position, ASTEROID, 48.0)
	_draw_scan_pulse(asteroid_position, 150.0, ASTEROID, 0.0)
	_draw_probe(probe_position)
	draw_dashed_line(Vector2(300, 660), asteroid_position, Color(colors["divider"], 0.65), 2.0, 10.0)
	draw_string(VideoTypography.bold(), Vector2(110, 185), "天问二号已抵达 2016 HO3", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, colors["text"])
	var items := [["约 400 天", 0.18], ["约 10 亿 km", 0.40], ["约 20 km", 0.64]]
	for index in range(items.size()):
		var item: Array = items[index]
		var alpha := smoothstep(float(item[1]), float(item[1]) + 0.14, progress)
		draw_string(VideoTypography.data(), Vector2(170 + index * 455, 830), String(item[0]), HORIZONTAL_ALIGNMENT_CENTER, 360, 38, Color(colors["text"], alpha))
	draw_string(VideoTypography.medium(), Vector2(1310, 650), "探测器与小行星示意\n非真实任务轨迹", HORIZONTAL_ALIGNMENT_CENTER, 300, 25, colors["muted"])


func _draw_brand_gate() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var alpha := sin(clampf(_beat_progress(), 0.0, 1.0) * PI)
	var center := Vector2(960, 500)
	for ring in range(3):
		var radius := 205.0 + ring * 42.0
		var sweep := clampf(_beat_progress() * 1.7 - ring * 0.16, 0.0, 1.0) * TAU
		_draw_smooth_arc(center, radius, -PI * 0.72, -PI * 0.72 + sweep, Color(ASTEROID, alpha * (0.34 - ring * 0.07)), 4.0 - ring * 0.7)
	_draw_scan_pulse(center, 360.0, EARTH, 0.22)
	draw_string(VideoTypography.bold(), Vector2(560, 500), "物理实验室", HORIZONTAL_ALIGNMENT_CENTER, 800, 58, Color(colors["text"], alpha))
	draw_string(VideoTypography.data(), Vector2(660, 565), "SLINGSHOT PHYSICS", HORIZONTAL_ALIGNMENT_CENTER, 600, 28, Color(colors["muted"], alpha))


func _draw_moon_comparison() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	draw_string(VideoTypography.bold(), Vector2(120, 180), "像一个圈，不等于同一种束缚", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, colors["text"])
	var earth_a := Vector2(510, 500)
	_draw_orbit_depth_rings(earth_a, 145.0, EARTH)
	_draw_planet(earth_a, 34, EARTH, "地球")
	_draw_smooth_arc(earth_a, 145, 0, TAU, Color(colors["muted"], 0.45), 3.0)
	var moon_angle := _beat_progress() * TAU
	_draw_moon(earth_a + Vector2.RIGHT.rotated(moon_angle) * 145, 15.0)
	draw_string(VideoTypography.bold(), Vector2(250, 750), "月球：主要绕地球", HORIZONTAL_ALIGNMENT_CENTER, 520, 34, colors["text"])
	var sun_center := Vector2(1330, 500)
	_draw_sun(sun_center, 22.0)
	_draw_orbit_depth_rings(sun_center, 210.0, SUN)
	_draw_smooth_arc(sun_center, 210, 0, TAU, Color(EARTH, 0.35), 3.0)
	var state := _state("co-orbital")
	_draw_planet(sun_center + _vector(state["earth_position_au"]) * 210, 14, EARTH, "")
	_draw_asteroid(sun_center + _vector(state["asteroid_position_au"]) * 210, ASTEROID)
	draw_string(VideoTypography.bold(), Vector2(1070, 750), "准卫星：主要绕太阳", HORIZONTAL_ALIGNMENT_CENTER, 520, 34, colors["text"])
	draw_string(VideoTypography.medium(), Vector2(650, 850), "左右两图尺度不同 · 天体大小均非比例", HORIZONTAL_ALIGNMENT_CENTER, 620, 25, colors["muted"])


func _draw_rendezvous_principle() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := smoothstep(0.06, 0.94, _beat_progress())
	draw_string(VideoTypography.bold(), Vector2(110, 180), "交会要同时匹配位置与速度", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, colors["text"])
	var target_start := Vector2(1280, 610)
	var meeting := Vector2(1440, 355)
	var target := target_start.lerp(meeting, p)
	var probe_start := Vector2(460, 620)
	var probe_control := Vector2(900, 360)
	var probe := _quadratic_bezier(probe_start, probe_control, meeting, p)
	draw_dashed_line(target_start, meeting, Color(ASTEROID, 0.30), 2.0, 10.0)
	var probe_path := PackedVector2Array()
	for index in range(61):
		var path_p := float(index) / 60.0
		probe_path.append(_quadratic_bezier(probe_start, probe_control, meeting, path_p))
	_draw_glow_polyline(probe_path, Color(EARTH, 0.50), 3.0)
	draw_circle(meeting, 24.0, Color(colors["text"], 0.06))
	_draw_smooth_arc(meeting, 24.0, 0.0, TAU, Color(colors["text"], 0.55), 2.0)
	_draw_scan_pulse(meeting, 90.0, colors["text"], 0.35)
	draw_string(VideoTypography.medium(), meeting + Vector2(-400, -88), "未来相遇点", HORIZONTAL_ALIGNMENT_CENTER, 184, 24, colors["muted"])
	_draw_asteroid(target, ASTEROID, 30)
	_draw_probe(probe)
	var target_velocity := Vector2(90, -105)
	var probe_velocity := Vector2(155, -40).lerp(target_velocity, p)
	_draw_vector(target, target_velocity, ASTEROID, "目标速度", Vector2(15, -12))
	_draw_vector(probe, probe_velocity, EARTH, "探测器速度", Vector2(15, 24))
	_draw_error_bar(Vector2(150, 685), "位置差  Δr", 1.0 - p, EARTH)
	_draw_error_bar(Vector2(150, 760), "速度差  Δv", 1.0 - p, ASTEROID)
	draw_string(VideoTypography.medium(), Vector2(110, 850), "交会原理示意 · 非真实任务轨迹和控制量", HORIZONTAL_ALIGNMENT_LEFT, 900, 25, colors["muted"])


func _draw_optical_navigation() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := smoothstep(0.08, 0.88, _beat_progress())
	var center := Vector2(1160, 510)
	var radius := Vector2(390, 210).lerp(Vector2(70, 38), p)
	var initial_uncertainty := _ellipse_points(center, Vector2(390, 210), 0.3)
	_draw_glow_polyline(initial_uncertainty, Color(ASTEROID, 0.18), 2.0)
	var uncertainty := PackedVector2Array()
	for index in range(121):
		var angle := TAU * float(index) / 120.0
		uncertainty.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y).rotated(0.3))
	draw_colored_polygon(uncertainty, Color(ASTEROID, 0.035))
	_draw_glow_polyline(uncertainty, Color(ASTEROID, 0.66), 3.0)
	_draw_asteroid(center, ASTEROID, 18)
	_draw_target_brackets(center, 62.0 + (1.0 - p) * 34.0, EARTH, p)
	_draw_scan_pulse(center, 120.0, EARTH, 0.12)
	for index in range(5):
		var origin := Vector2(170, 270 + index * 105)
		var observation_alpha := smoothstep(float(index) * 0.16, float(index) * 0.16 + 0.18, p)
		draw_line(origin, center, Color(EARTH, (0.12 + 0.08 * index) * observation_alpha), 7.0)
		draw_line(origin, center, Color(EARTH, (0.28 + 0.08 * index) * observation_alpha), 2.0)
		draw_circle(origin, 5.0, Color(EARTH, observation_alpha))
	var probe_position := Vector2(230, 710).lerp(Vector2(580, 330), p)
	_draw_probe(probe_position)
	draw_line(probe_position + Vector2(30, -55), center, Color(EARTH, 0.62), 3.0)
	draw_string(VideoTypography.bold(), Vector2(110, 175), "靠近，也是在重新确定目标位置", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, colors["text"])
	draw_string(VideoTypography.medium(), Vector2(960, 735), "仅依靠地基观测", HORIZONTAL_ALIGNMENT_CENTER, 360, 26, colors["muted"])
	draw_string(VideoTypography.data(), Vector2(960, 785), ">100 km", HORIZONTAL_ALIGNMENT_CENTER, 360, 38, Color(ASTEROID, 1.0 - p * 0.55))
	draw_string(VideoTypography.medium(), Vector2(1430, 735), "抵近光学导航", HORIZONTAL_ALIGNMENT_CENTER, 360, 26, colors["muted"])
	draw_string(VideoTypography.data(), Vector2(1430, 785), "km 量级", HORIZONTAL_ALIGNMENT_CENTER, 360, 38, EARTH)
	draw_string(VideoTypography.medium(), Vector2(110, 850), "误差量级来自国家航天局 · 椭圆收缩为信息示意，不按数值线性缩放", HORIZONTAL_ALIGNMENT_LEFT, 1050, 25, colors["muted"])


func _draw_science_close() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := smoothstep(0.0, 0.76, _beat_progress())
	var asteroid_position := Vector2(1040, 455).lerp(Vector2(960, 460), p)
	var asteroid_radius := lerpf(62.0, 108.0, p)
	var probe_position := Vector2(500, 620).lerp(Vector2(620, 570), p)
	_draw_asteroid(asteroid_position, ASTEROID, asteroid_radius)
	_draw_probe(probe_position)
	draw_string(VideoTypography.bold(), Vector2(310, 760), "这块伴随地球的岩石，记录了怎样的来源？", HORIZONTAL_ALIGNMENT_CENTER, 1300, 42, colors["text"])
	draw_string(VideoTypography.medium(), Vector2(610, 825), "天问二号 · 近距离探测与采样准备", HORIZONTAL_ALIGNMENT_CENTER, 700, 27, colors["muted"])


func _draw_heliocentric_path(id: String, center: Vector2, scale: float, color: Color) -> void:
	var points := PackedVector2Array()
	var record: Dictionary = records_by_id.get(id, {})
	var stride := 1 if bool(record.get("authoritative_ephemeris", false)) and String(current_beat.get("id", "")) != "resonance-boundary" else 4
	for index in range(0, record.get("frames", []).size(), stride):
		var frame: Dictionary = record["frames"][index]
		if not _path_frame_visible(record, frame):
			continue
		points.append(center + _vector(frame["asteroid_position_au"]) * scale)
	if points.size() > 1:
		_draw_glow_polyline(points, color, 3.0)


func _draw_rotating_path(id: String, center: Vector2, scale: float, color: Color) -> void:
	var points := PackedVector2Array()
	var record: Dictionary = records_by_id.get(id, {})
	var stride := 1 if bool(record.get("authoritative_ephemeris", false)) and String(current_beat.get("id", "")) != "resonance-boundary" else 4
	for index in range(0, record.get("frames", []).size(), stride):
		var frame: Dictionary = record["frames"][index]
		if not _path_frame_visible(record, frame):
			continue
		points.append(center + _vector(frame["relative_rotating_au"]) * scale)
	if points.size() > 1:
		_draw_glow_polyline(points, color, 3.0)


func _draw_partial_rotating_path(
	id: String,
	center: Vector2,
	scale: float,
	progress: float,
	trail_frames: int,
	color: Color
) -> void:
	var record: Dictionary = records_by_id.get(id, {})
	var frames: Array = record.get("frames", [])
	if frames.size() < 2:
		return
	var end_index := clampi(int(round(progress * float(frames.size() - 1))), 1, frames.size() - 1)
	var start_index := maxi(0, end_index - trail_frames)
	var points := PackedVector2Array()
	for index in range(start_index, end_index + 1, 2):
		points.append(center + _vector(frames[index]["relative_rotating_au"]) * scale)
	if points.size() > 1:
		_draw_glow_polyline(points, color, 4.0)


func _draw_planet(position: Vector2, radius: float, color: Color, label: String) -> void:
	if not label.is_empty():
		draw_string(VideoTypography.medium(), position + Vector2(-80, radius + 42), label, HORIZONTAL_ALIGNMENT_CENTER, 160, 25, episode["theme"]["colors"]["text"])


func _draw_sun(position: Vector2, radius: float) -> void:
	pass


func _draw_moon(position: Vector2, radius: float) -> void:
	pass


func _ensure_celestial_pool() -> void:
	if not celestial_pools["earth"].is_empty():
		return
	for index in range(4):
		celestial_pools["earth"].append(_create_celestial_body("earth", index))
	for index in range(2):
		celestial_pools["sun"].append(_create_celestial_body("sun", index))
	celestial_pools["moon"].append(_create_celestial_body("moon", 0))


func _create_celestial_body(kind: String, index: int) -> Node2D:
	var body: Node2D = CelestialBody.new()
	body.name = "Celestial%s%02d" % [kind.capitalize(), index]
	body.visible = false
	body.z_index = 2
	add_child(body)
	return body


func _reset_celestial_pool() -> void:
	_ensure_celestial_pool()
	for kind in celestial_pools.keys():
		celestial_pool_indices[kind] = 0
		for body_value in celestial_pools[kind]:
			var body: Node2D = body_value
			body.hide_body()


func _layout_celestial_sprites() -> void:
	_reset_celestial_pool()
	var beat_id := String(current_beat.get("id", ""))
	match beat_id:
		"cold-open", "earth-frame":
			_place_celestial("earth", Vector2(960, 500), 29.0)
		"sun-reveal", "speed-change":
			var center := Vector2(830, 505)
			var scale := lerpf(265.0, 315.0, smoothstep(0.0, 0.55, _beat_progress()))
			var state := _state("co-orbital")
			_place_celestial("sun", center, 24.0)
			_place_celestial("earth", center + _vector(state.get("earth_position_au", Vector2.RIGHT)) * scale, 17.0)
		"same-state-two-frames":
			var left_center := Rect2(70, 170, 845, 650).get_center() + Vector2(0, 35)
			var right_center := Rect2(1005, 170, 845, 650).get_center() + Vector2(0, 35)
			var state := _state("co-orbital")
			_place_celestial("sun", left_center, 15.0)
			_place_celestial("earth", left_center + _vector(state.get("earth_position_au", Vector2.RIGHT)) * 225.0, 12.0)
			_place_celestial("earth", right_center, 18.0)
		"resonance-boundary":
			_place_celestial("earth", Vector2(520, 520), 23.0)
			_place_celestial("earth", Vector2(1400, 520), 23.0)
		"moon-comparison":
			var earth_center := Vector2(510, 500)
			var sun_center := Vector2(1330, 500)
			var state := _state("co-orbital")
			var moon_angle := _beat_progress() * TAU
			_place_celestial("earth", earth_center, 34.0)
			_place_celestial("moon", earth_center + Vector2.RIGHT.rotated(moon_angle) * 145.0, 15.0)
			_place_celestial("sun", sun_center, 22.0)
			_place_celestial("earth", sun_center + _vector(state.get("earth_position_au", Vector2.RIGHT)) * 210.0, 14.0)


func _place_celestial(kind: String, position: Vector2, radius: float) -> void:
	_ensure_celestial_pool()
	var pool: Array = celestial_pools[kind]
	var index: int = int(celestial_pool_indices[kind])
	if index >= pool.size():
		var body := _create_celestial_body(kind, index)
		pool.append(body)
		celestial_pools[kind] = pool
	var selected: Node2D = pool[index]
	selected.configure(kind, position, radius)
	celestial_pool_indices[kind] = index + 1


func _draw_asteroid(position: Vector2, color: Color, radius: float = 15.0) -> void:
	var rotation := 0.28
	var points := PackedVector2Array([
		position + Vector2(-0.9, -0.3).rotated(rotation) * radius,
		position + Vector2(-0.3, -0.95).rotated(rotation) * radius,
		position + Vector2(0.65, -0.72).rotated(rotation) * radius,
		position + Vector2(1.0, 0.15).rotated(rotation) * radius,
		position + Vector2(0.35, 0.92).rotated(rotation) * radius,
		position + Vector2(-0.75, 0.65).rotated(rotation) * radius,
	])
	draw_circle(position, radius * 2.5, Color(color, 0.025))
	draw_circle(position, radius * 1.7, Color(color, 0.09))
	draw_colored_polygon(points, color)
	draw_polyline(points, Color(1.0, 0.82, 0.68, 0.34), 2.0, true)
	if radius >= 40.0:
		var axis_x := Vector2.RIGHT.rotated(rotation)
		var axis_y := axis_x.rotated(PI * 0.5)
		draw_line(position - axis_x * radius * 0.62, position + axis_y * radius * 0.48, Color(1.0, 0.86, 0.72, 0.16), 2.0)
		draw_line(position + axis_y * radius * 0.48, position + axis_x * radius * 0.55, Color(0.42, 0.18, 0.10, 0.24), 2.0)


func _draw_probe(position: Vector2) -> void:
	draw_circle(position, 52.0, Color(EARTH, 0.025))
	draw_rect(Rect2(position - Vector2(25, 14), Vector2(50, 28)), Color("#E6E1D7"), true)
	draw_rect(Rect2(position + Vector2(-86, -10), Vector2(52, 20)), Color("#4E78A8"), true)
	draw_rect(Rect2(position + Vector2(34, -10), Vector2(52, 20)), Color("#4E78A8"), true)
	for offset in [-72.0, -52.0, 48.0, 68.0]:
		draw_line(position + Vector2(offset, -9), position + Vector2(offset, 9), Color(EARTH, 0.45), 1.0)
	draw_line(position + Vector2(0, -14), position + Vector2(28, -54), Color("#E6E1D7"), 3.0)
	draw_circle(position + Vector2(30, -56), 7, Color("#E6E1D7"))


func _draw_space_field() -> void:
	# A deterministic, low-density parallax field: enough depth to avoid a flat
	# black stage without competing with trajectories or exact labels.
	draw_circle(Vector2(320, 360), 300.0, Color(EARTH, 0.008))
	draw_circle(Vector2(1600, 430), 360.0, Color(ASTEROID, 0.006))
	for index in range(72):
		var depth := 1.0 + float(index % 3) * 0.45
		var x := fposmod(float((index * 347 + 113) % 1920) - video_time_sec * (1.4 + depth), 1920.0)
		var y := 70.0 + float((index * 191 + 47) % 790)
		var pulse := 0.72 + 0.28 * sin(video_time_sec * (0.55 + depth * 0.12) + float(index) * 1.73)
		var alpha := (0.055 + 0.025 * float(index % 4)) * pulse
		var radius := 0.7 + 0.45 * float(index % 3)
		draw_circle(Vector2(x, y), radius, Color(0.72, 0.80, 0.92, alpha))


func _draw_glow_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	var smooth_points := _smooth_polyline(points)
	draw_polyline(smooth_points, Color(color, color.a * 0.10), width * 5.0, true)
	draw_polyline(smooth_points, Color(color, color.a * 0.22), width * 2.5, true)
	draw_polyline(smooth_points, color, width, true)


func _smooth_polyline(points: PackedVector2Array, max_step_px: float = 5.0) -> PackedVector2Array:
	# The ephemeris nodes remain exact evidence. This only interpolates between
	# adjacent screen-space nodes so a magnified path does not read as a polygon.
	if points.size() < 3:
		return points
	var result := PackedVector2Array()
	for segment in range(points.size() - 1):
		var p0: Vector2 = points[maxi(0, segment - 1)]
		var p1: Vector2 = points[segment]
		var p2: Vector2 = points[segment + 1]
		var p3: Vector2 = points[mini(points.size() - 1, segment + 2)]
		var subdivisions := clampi(ceili(p1.distance_to(p2) / max_step_px), 1, 24)
		for step in range(subdivisions):
			var t := float(step) / float(subdivisions)
			var t2 := t * t
			var t3 := t2 * t
			result.append(0.5 * (
				2.0 * p1
				+ (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
			))
	result.append(points[points.size() - 1])
	return result


func _draw_smooth_arc(
	center: Vector2,
	radius: float,
	start_angle: float,
	end_angle: float,
	color: Color,
	width: float = 1.0
) -> void:
	var arc_length_px := absf(end_angle - start_angle) * radius
	var point_count := clampi(ceili(arc_length_px / 4.0), 24, 720)
	draw_arc(center, radius, start_angle, end_angle, point_count, color, width, true)


func _draw_glow_disc(position: Vector2, radius: float, color: Color) -> void:
	draw_circle(position, radius * 3.2, Color(color, 0.025))
	draw_circle(position, radius * 2.1, Color(color, 0.06))
	draw_circle(position, radius * 1.35, Color(color, 0.13))
	draw_circle(position, radius, color)


func _draw_orbit_depth_rings(center: Vector2, radius: float, color: Color) -> void:
	for ratio in [0.34, 0.67, 1.0]:
		var ring_radius := radius * float(ratio)
		_draw_smooth_arc(center, ring_radius, -PI * 0.94, PI * 0.15, Color(color, 0.045), 1.0)
	for spoke in range(8):
		var angle := float(spoke) * TAU / 8.0 + video_time_sec * 0.015
		draw_line(center + Vector2.RIGHT.rotated(angle) * radius * 0.92, center + Vector2.RIGHT.rotated(angle) * radius, Color(color, 0.075), 1.0)


func _draw_scan_pulse(center: Vector2, max_radius: float, color: Color, phase_offset: float) -> void:
	var phase := fposmod(_beat_progress() * 1.75 + phase_offset, 1.0)
	var radius := lerpf(max_radius * 0.22, max_radius, phase)
	var alpha := pow(1.0 - phase, 1.7) * 0.42
	_draw_smooth_arc(center, radius, -PI * 0.82, PI * 0.92, Color(color, alpha), 2.0)


func _draw_arrival_corridor(start: Vector2, target: Vector2, progress: float) -> void:
	var direction := (target - start).normalized()
	var normal := Vector2(-direction.y, direction.x)
	for offset in [-42.0, 42.0]:
		draw_line(start + normal * offset, target + normal * offset * 0.35, Color(EARTH, 0.055), 1.0)
	for index in range(7):
		var marker_progress := fposmod(progress * 1.6 + float(index) / 7.0, 1.0)
		var marker := start.lerp(target, marker_progress)
		var marker_alpha := sin(marker_progress * PI) * 0.34
		draw_line(marker - normal * 13.0, marker + normal * 13.0, Color(EARTH, marker_alpha), 2.0)


func _draw_target_brackets(center: Vector2, radius: float, color: Color, lock_progress: float) -> void:
	var size := radius * lerpf(1.18, 0.82, lock_progress)
	var arm := 18.0
	var quadrants: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for quadrant: Vector2 in quadrants:
		var corner: Vector2 = center + quadrant * size
		draw_line(corner, corner - Vector2(quadrant.x * arm, 0), Color(color, 0.72), 3.0)
		draw_line(corner, corner - Vector2(0, quadrant.y * arm), Color(color, 0.72), 3.0)


func _draw_error_bar(position: Vector2, label: String, remaining: float, color: Color) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	draw_string(VideoTypography.medium(), position, label, HORIZONTAL_ALIGNMENT_LEFT, 170, 25, colors["muted"])
	var bar := Rect2(position + Vector2(175, -19), Vector2(300, 18))
	draw_rect(bar, Color(colors["divider"], 0.42), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(remaining, 0.0, 1.0), bar.size.y)), color, true)
	if remaining < 0.08:
		draw_string(VideoTypography.bold(), bar.position + Vector2(315, 2), "已匹配", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, color)


func _quadratic_bezier(start: Vector2, control: Vector2, finish: Vector2, progress: float) -> Vector2:
	var p := clampf(progress, 0.0, 1.0)
	var inverse := 1.0 - p
	return start * inverse * inverse + control * 2.0 * inverse * p + finish * p * p


func _ellipse_points(center: Vector2, radius: Vector2, rotation: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(121):
		var angle := TAU * float(index) / 120.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y).rotated(rotation))
	return points


func _draw_vector(origin: Vector2, value: Vector2, color: Color, label: String, label_offset := Vector2(15, -8)) -> void:
	var end := origin + value
	draw_line(origin, end, color, 5.0, true)
	var direction := value.normalized()
	draw_colored_polygon(PackedVector2Array([end, end - direction.rotated(0.55) * 22, end - direction.rotated(-0.55) * 22]), color)
	draw_string(VideoTypography.medium(), end + label_offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, color)


func _draw_axes(center: Vector2, extent: float, color: Color) -> void:
	draw_line(center - Vector2(extent, 0), center + Vector2(extent, 0), color, 1.0)
	draw_line(center - Vector2(0, extent), center + Vector2(0, extent), color, 1.0)


func _draw_badge(text: String, position: Vector2, color: Color) -> void:
	draw_rect(Rect2(position, Vector2(330, 48)), Color(color, 0.12), true)
	draw_string(VideoTypography.medium(), position + Vector2(18, 33), text, HORIZONTAL_ALIGNMENT_LEFT, 300, 25, color)


func _draw_model_boundary(text: String = "JPL Horizons 星历 · 黄道投影 · 天体大小非比例") -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	draw_string(VideoTypography.medium(), Vector2(1120, 850), text, HORIZONTAL_ALIGNMENT_RIGHT, 680, 23, colors["muted"])


func _state(id: String) -> Dictionary:
	var record: Dictionary = records_by_id.get(id, {})
	if record.is_empty():
		return states_by_id.get(id, {})
	if bool(record.get("authoritative_ephemeris", false)):
		return _sample_ephemeris_record(record, _display_jd(record))
	return _sample_record_progress(record, _beat_progress())


func _display_jd(record: Dictionary) -> float:
	var start_jd := float(record.get("source_start_jd", PRIMARY_YEAR_START_JD))
	var end_jd := float(record.get("source_end_jd", PRIMARY_YEAR_END_JD))
	if String(current_beat.get("id", "")) == "resonance-boundary":
		return lerpf(start_jd, end_jd, _beat_progress())
	var primary_progress := clampf(video_time_sec / 120.0, 0.0, 1.0)
	return lerpf(PRIMARY_YEAR_START_JD, PRIMARY_YEAR_END_JD, primary_progress)


func _path_frame_visible(record: Dictionary, frame: Dictionary) -> bool:
	if not bool(record.get("authoritative_ephemeris", false)):
		return true
	if String(current_beat.get("id", "")) == "resonance-boundary":
		return true
	var jd := float(frame.get("source_jd", 0.0))
	return jd >= PRIMARY_YEAR_START_JD and jd <= PRIMARY_YEAR_END_JD


func _sample_ephemeris_record(record: Dictionary, jd: float) -> Dictionary:
	var start_jd := float(record.get("source_start_jd", jd))
	var end_jd := float(record.get("source_end_jd", jd + 1.0))
	var progress := clampf((jd - start_jd) / maxf(0.000001, end_jd - start_jd), 0.0, 1.0)
	return _sample_record_progress(record, progress)


func _sample_record_progress(record: Dictionary, progress: float) -> Dictionary:
	var frames: Array = record.get("frames", [])
	if frames.is_empty():
		return {}
	var position := clampf(progress, 0.0, 1.0) * float(frames.size() - 1)
	var lower_index := clampi(int(floor(position)), 0, frames.size() - 1)
	var upper_index := mini(lower_index + 1, frames.size() - 1)
	var weight := clampf(position - floor(position), 0.0, 1.0)
	var lower: Dictionary = frames[lower_index]
	var upper: Dictionary = frames[upper_index]
	var result := {}
	for key in ["earth_position_au", "earth_velocity_au_y", "asteroid_position_au", "asteroid_velocity_au_y", "relative_inertial_au", "relative_rotating_au"]:
		result[key] = _vector(lower[key]).lerp(_vector(upper[key]), weight)
	for key in ["solar_distance_au", "orbital_speed_au_y", "earth_angle_rad", "source_jd", "relative_z_au", "relative_distance_au"]:
		if lower.has(key) and upper.has(key):
			result[key] = lerpf(float(lower[key]), float(upper[key]), weight)
	return result


func _vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
