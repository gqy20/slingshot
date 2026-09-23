extends "res://src/video/episode_canvas.gd"

const CelestialBody = preload("res://src/video/celestial_body_sprite.gd")
const ASTEROID_OBSERVATION = preload("res://assets/video/tianwen2/sources/2016-ho3-cnsa-2026-07-02.jpg")
const ASTEROID_ORBIT_JPL = preload("res://assets/video/tianwen2/sources/2016-ho3-orbit-jpl-2016-06-15.jpg")
const EARTH_NAV_OBSERVATION = preload("res://assets/video/tianwen2/sources/earth-nav-cnsa-2025-05-30.png")
const MOON_NAV_OBSERVATION = preload("res://assets/video/tianwen2/sources/moon-nav-cnsa-2025-05-30.png")
const TIANWEN_SOLAR_WING = preload("res://assets/video/tianwen2/sources/tianwen2-solar-wing-cnsa-2025-06-06.jpg")
const TIANWEN_EARTH_SELFIE = preload("res://assets/video/tianwen2/sources/tianwen2-earth-selfie-cnsa-2025-10-01.jpg")
const SUN := Color("#FFC76A")
const EARTH := Color("#69A9FF")
const ASTEROID := Color("#F08A55")
const CONTROL := Color("#8A8F98")
const ORBIT_FAINT := Color(0.55, 0.60, 0.68, 0.28)
const CONTENT_BOTTOM := 875.0
const PRIMARY_YEAR_START_JD := 2461041.5
const PRIMARY_YEAR_END_JD := 2461406.5
const COLD_OPEN_MOTION_START_SEC := 2.5
const COLD_OPEN_SECONDS_PER_YEAR := 6.7
const EARTH_FRAME_SECONDS_PER_YEAR := 6.5
const SUN_REVEAL_SECONDS_PER_YEAR := 7.35
const RENDEZVOUS_CONTACT_PROGRESS := 0.82
const MOON_LEFT_REGION := Rect2(280, 300, 460, 500)
const MOON_RIGHT_REGION := Rect2(1090, 250, 500, 550)
const RENDEZVOUS_STAGE_REGION := Rect2(400, 245, 1200, 390)
const RENDEZVOUS_ERROR_REGION := Rect2(130, 645, 540, 165)
const OPTICAL_STAGE_REGION := Rect2(110, 225, 1590, 475)
const OPTICAL_EVIDENCE_REGION := Rect2(940, 705, 860, 110)
const ERROR_BAR_LABEL_WIDTH := 270.0
const ERROR_BAR_LABEL_GAP := 24.0
const ERROR_BAR_WIDTH := 260.0

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
	var center := Vector2(1050, 500) if show_headline else Vector2(960, 500)
	var progress := _beat_progress()
	var elapsed := progress * float(current_beat.get("duration", 16.0))
	var orbit_years := maxf(0.0, (elapsed - COLD_OPEN_MOTION_START_SEC) / COLD_OPEN_SECONDS_PER_YEAR)
	var motion_progress := clampf(orbit_years, 0.0, 1.0) if show_headline else progress
	var orbit_alpha := smoothstep(0.13, 0.20, progress) if show_headline else 1.0
	var camera_progress := smoothstep(0.0, 0.62, motion_progress) if show_headline else 1.0
	var scale := lerpf(1320.0, 1640.0, camera_progress) if show_headline else 1150.0
	var state: Dictionary
	if show_headline:
		_draw_real_asteroid_opener(progress)
		var record: Dictionary = records_by_id.get("co-orbital", {})
		var current_jd := PRIMARY_YEAR_START_JD + orbit_years * (PRIMARY_YEAR_END_JD - PRIMARY_YEAR_START_JD)
		state = _sample_ephemeris_record(record, current_jd) if not record.is_empty() else _state("co-orbital")
		_draw_rotating_reference_field(center, orbit_years, orbit_alpha)
		_draw_primary_year_path("co-orbital", center, scale, current_jd, state, orbit_alpha)
	else:
		state = _state("co-orbital")
	if orbit_alpha <= 0.001:
		return
	_draw_orbit_depth_rings(center, 300.0, Color(EARTH, orbit_alpha))
	_draw_planet(center, 34.0 if show_headline else 29.0, Color(EARTH, orbit_alpha), "地球", orbit_alpha)
	var asteroid_position := center + _vector(state.get("relative_rotating_au", Vector2.ZERO)) * scale
	if not show_headline:
		_draw_earth_frame_motion_trail(center, scale, float(state.get("source_jd", PRIMARY_YEAR_END_JD)))
	if show_headline:
		var pulse := 0.5 + 0.5 * sin(video_time_sec * 5.2)
		draw_circle(asteroid_position, 34.0 + pulse * 8.0, Color(ASTEROID, orbit_alpha * (0.045 + pulse * 0.025)))
		draw_arc(asteroid_position, 25.0 + pulse * 6.0, -PI * 0.8, PI * 0.55, 28, Color(ASTEROID, orbit_alpha * 0.24), 2.0, true)
	_draw_asteroid(asteroid_position, Color(ASTEROID, orbit_alpha), 20.0 if show_headline else 15.0)
	_draw_axes(center, 300.0 if show_headline else 250.0, Color(colors["divider"], orbit_alpha * 0.62))
	if show_headline:
		_draw_cold_open_headline(progress, orbit_alpha)
		draw_string(VideoTypography.data(), Vector2(116, 850), "时间压缩 · 约 6.7 秒 / 年", HORIZONTAL_ALIGNMENT_LEFT, 620, 36, Color(colors["muted"], orbit_alpha))
	else:
		_draw_earth_frame_readout(progress)
	_draw_model_boundary("JPL Horizons 星历 · 黄道投影 · 天体大小非比例", orbit_alpha)


func _draw_earth_frame_readout(progress: float) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	draw_string(VideoTypography.data(), Vector2(116, 850), "时间压缩 · 约 6.5 秒 / 年", HORIZONTAL_ALIGNMENT_LEFT, 620, 36, colors["muted"])


func _draw_earth_frame_motion_trail(center: Vector2, scale: float, current_jd: float, alpha: float = 1.0) -> void:
	var record: Dictionary = records_by_id.get("co-orbital", {})
	if record.is_empty():
		return
	var start_jd := PRIMARY_YEAR_END_JD
	var sample_count := maxi(1, int(ceilf((current_jd - start_jd) / (PRIMARY_YEAR_END_JD - PRIMARY_YEAR_START_JD) * 160.0)))
	var history := PackedVector2Array()
	for index in range(sample_count + 1):
		var sample_jd := lerpf(start_jd, current_jd, float(index) / float(sample_count))
		var sample := _sample_ephemeris_record(record, sample_jd)
		history.append(center + _vector(sample.get("relative_rotating_au", Vector2.ZERO)) * scale)
	if history.size() > 1:
		draw_polyline(history, Color(ASTEROID, 0.18 * alpha), 2.0, true)
		var tail_start := maxi(0, history.size() - 28)
		var tail := history.slice(tail_start, history.size())
		if tail.size() > 1:
			_draw_glow_polyline(tail, Color(ASTEROID, 0.64 * alpha), 3.0)


func _draw_cold_open_headline(progress: float, alpha: float = 1.0) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var evidence_alpha := alpha * smoothstep(0.22, 0.30, progress) * (1.0 - smoothstep(0.38, 0.44, progress))
	var tension_alpha := alpha * smoothstep(0.40, 0.48, progress) * (1.0 - smoothstep(0.60, 0.66, progress))
	var question_alpha := alpha * smoothstep(0.62, 0.70, progress)
	draw_string(VideoTypography.bold(), Vector2(116, 270), "它在绕地球？", HORIZONTAL_ALIGNMENT_LEFT, -1, 68, Color(ASTEROID, evidence_alpha))
	draw_string(VideoTypography.bold(), Vector2(116, 270), "可它主要绕太阳", HORIZONTAL_ALIGNMENT_LEFT, -1, 72, Color(SUN, tension_alpha))
	draw_string(VideoTypography.bold(), Vector2(116, 270), "两者怎么同时成立？", HORIZONTAL_ALIGNMENT_LEFT, -1, 72, Color(colors["text"], question_alpha))


func _draw_real_asteroid_opener(progress: float) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var alpha := 1.0 - smoothstep(0.12, 0.20, progress)
	if alpha <= 0.001:
		return
	var handoff := smoothstep(0.12, 0.20, progress)
	var image_center := Vector2(1080, 458)
	var record: Dictionary = records_by_id.get("co-orbital", {})
	if not record.is_empty():
		var first_state := _sample_ephemeris_record(record, PRIMARY_YEAR_START_JD)
		image_center = image_center.lerp(Vector2(1050, 500) + _vector(first_state.get("relative_rotating_au", Vector2.ZERO)) * 1320.0, handoff)
	var image_size := Vector2(720, 744).lerp(Vector2(100, 103), handoff)
	var image_rect := Rect2(image_center - image_size * 0.5, image_size)
	var zoom := lerpf(1.10, 1.0, smoothstep(0.0, 0.20, progress))
	_draw_texture_cover(ASTEROID_OBSERVATION, image_rect, zoom, Vector2(0.50, 0.49), alpha)
	# Preserve the official image as evidence, then add only deterministic
	# telemetry framing around it. The embedded scale bar and logos remain intact.
	draw_rect(image_rect.grow(2.0), Color(0.78, 0.87, 1.0, alpha * 0.16), false, 2.0)
	var reveal := smoothstep(0.0, 0.11, progress)
	var scan_y := lerpf(image_rect.position.y + 18.0, image_rect.end.y - 18.0, reveal)
	draw_line(Vector2(image_rect.position.x, scan_y), Vector2(image_rect.end.x, scan_y), Color(EARTH, alpha * 0.68), 2.0)
	draw_rect(Rect2(image_rect.position.x, scan_y - 22.0, image_rect.size.x, 44.0), Color(EARTH, alpha * 0.025), true)
	_draw_frame_corners(image_rect, Color(EARTH, alpha * 0.78), 30.0)
	var text_alpha := 1.0 - smoothstep(0.10, 0.16, progress)
	draw_string(VideoTypography.medium(), Vector2(116, 160), "天问二号拍下它", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(EARTH, text_alpha))
	draw_string(VideoTypography.bold(), Vector2(116, 248), "距目标约 20 km", HORIZONTAL_ALIGNMENT_LEFT, -1, 68, Color(colors["text"], text_alpha))
	draw_string(VideoTypography.medium(), Vector2(116, 850), "CNSA · 2026.07.02", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(colors["muted"], text_alpha * 0.92))


func _draw_rotating_reference_field(center: Vector2, progress: float, alpha_scale: float = 1.0) -> void:
	# In an Earth-fixed frame, distant inertial directions rotate once over the
	# compressed year. The deterministic field makes that reference-frame motion
	# visible without inventing another physical orbit.
	for index in range(28):
		var base_angle := float((index * 137) % 360) * PI / 180.0
		var radius := 330.0 + float((index * 83) % 430)
		var angle := base_angle - progress * TAU
		var point := center + Vector2.RIGHT.rotated(angle) * radius
		var alpha := (0.08 + 0.055 * float(index % 3)) * alpha_scale
		draw_circle(point, 1.2 + 0.45 * float(index % 2), Color(0.68, 0.78, 0.94, alpha))


func _draw_primary_year_path(id: String, center: Vector2, scale: float, current_jd: float, state: Dictionary, alpha: float = 1.0) -> void:
	var record: Dictionary = records_by_id.get(id, {})
	if record.is_empty() or current_jd <= PRIMARY_YEAR_START_JD:
		return
	var current_position := center + _vector(state.get("relative_rotating_au", Vector2.ZERO)) * scale
	var first_year_end := minf(current_jd, PRIMARY_YEAR_END_JD)
	var points := PackedVector2Array()
	var first_year_samples := maxi(2, int(ceilf((first_year_end - PRIMARY_YEAR_START_JD) / (PRIMARY_YEAR_END_JD - PRIMARY_YEAR_START_JD) * 240.0)))
	for index in range(first_year_samples + 1):
		var sample_jd := lerpf(PRIMARY_YEAR_START_JD, first_year_end, float(index) / float(first_year_samples))
		var sample := _sample_ephemeris_record(record, sample_jd)
		points.append(center + _vector(sample.get("relative_rotating_au", Vector2.ZERO)) * scale)
	if current_jd <= PRIMARY_YEAR_END_JD:
		points[points.size() - 1] = current_position
	if points.size() > 1:
		var first_year_alpha := 0.78 if current_jd <= PRIMARY_YEAR_END_JD else 0.16
		_draw_glow_polyline(points, Color(ASTEROID, first_year_alpha * alpha), 4.0 if current_jd <= PRIMARY_YEAR_END_JD else 2.0)
	if current_jd <= PRIMARY_YEAR_END_JD:
		return
	# The next lap uses the following year's actual ephemeris, not a replayed loop.
	var tail_start_jd := maxf(PRIMARY_YEAR_END_JD, current_jd - 0.25 * (PRIMARY_YEAR_END_JD - PRIMARY_YEAR_START_JD))
	var tail := PackedVector2Array()
	for index in range(73):
		var sample_jd := lerpf(tail_start_jd, current_jd, float(index) / 72.0)
		var sample := _sample_ephemeris_record(record, sample_jd)
		tail.append(center + _vector(sample.get("relative_rotating_au", Vector2.ZERO)) * scale)
	tail[tail.size() - 1] = current_position
	_draw_glow_polyline(tail, Color(ASTEROID, 0.82 * alpha), 4.0)


func _draw_sun_view(show_path: bool) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var beat_id := String(current_beat.get("id", ""))
	var state := _state("co-orbital")
	var camera := _sun_camera(progress, beat_id, state)
	var sun_position := _project_sun_position(Vector2.ZERO, 0.0, camera)
	var earth_position := _project_sun_position(_vector(state.get("earth_position_au", Vector2.RIGHT)), 0.0, camera)
	var asteroid_position := _project_sun_position(
		_vector(state.get("asteroid_position_au", Vector2.RIGHT)),
		float(state.get("relative_z_au", 0.0)),
		camera
	)
	if beat_id == "sun-reveal":
		var departing_trail_alpha := 1.0 - smoothstep(0.0, 0.08, progress)
		if departing_trail_alpha > 0.001:
			_draw_earth_frame_motion_trail(Vector2(960, 500), 1150.0, float(state.get("source_jd", PRIMARY_YEAR_END_JD)), departing_trail_alpha)
	var establish_alpha := smoothstep(0.08, 0.24, progress) if beat_id == "sun-reveal" else 1.0
	_draw_reference_glow(sun_position, minf(float(camera["scale"]) * 0.62, 250.0), SUN, establish_alpha * 0.62)
	_draw_projected_orbit_rings(camera, establish_alpha)
	if show_path:
		_draw_temporal_heliocentric_path("co-orbital", state, camera, establish_alpha)
	_draw_sun(sun_position, 24.0)
	var earth_radius := lerpf(29.0, 17.0, smoothstep(0.0, 0.28, progress)) if beat_id == "sun-reveal" else 17.0
	_draw_planet(earth_position, earth_radius, EARTH, "地球")
	_draw_asteroid(asteroid_position, ASTEROID)
	draw_string(VideoTypography.medium(), sun_position + Vector2(-50, 70), "太阳", HORIZONTAL_ALIGNMENT_CENTER, 100, 40, Color(colors["muted"], establish_alpha))
	var headline := "轨道中心：太阳" if beat_id == "sun-reveal" else "距离改变，速度也改变"
	var headline_alpha := smoothstep(0.36, 0.46, progress) if beat_id == "sun-reveal" else smoothstep(0.04, 0.12, progress)
	if beat_id == "sun-reveal":
		headline_alpha *= 1.0 - smoothstep(0.50, 0.58, progress)
	else:
		headline_alpha *= 1.0 - smoothstep(0.22, 0.34, progress)
	draw_string(VideoTypography.bold(), Vector2(116, 188), headline, HORIZONTAL_ALIGNMENT_LEFT, 980, 56, Color(colors["text"], headline_alpha))
	if beat_id == "sun-reveal":
		var conclusion_alpha := smoothstep(0.58, 0.68, progress) * (1.0 - smoothstep(0.90, 1.0, progress))
		draw_string(VideoTypography.bold(), Vector2(116, 188), "闭环 ≠ 地球轨道", HORIZONTAL_ALIGNMENT_LEFT, 980, 56, Color(colors["text"], conclusion_alpha))
	var compression_text := "时间压缩 · 约 7.4 秒 / 年" if beat_id == "sun-reveal" else "时间压缩 · 约 15.3 秒 / 年"
	draw_string(VideoTypography.data(), Vector2(116, 850), compression_text, HORIZONTAL_ALIGNMENT_LEFT, 700, 36, colors["muted"])
	if beat_id == "sun-reveal":
		_draw_model_boundary("JPL Horizons 星历 · 轻微倾斜视角 · 高度轻微放大")


func _sun_camera(progress: float, beat_id: String, state: Dictionary) -> Dictionary:
	# Let the old Earth-fixed frame remain recognizable before the camera rolls
	# out.  The world is still sampled at the same JD on either side of the cut.
	var pullback := smoothstep(0.02, 0.43, progress) if beat_id == "sun-reveal" else 1.0
	var earth_world := _vector(state.get("earth_position_au", Vector2.RIGHT))
	var camera_target := earth_world * (1.0 - pullback)
	var center := Vector2(960, 500).lerp(Vector2(800, 505), pullback)
	var scale := lerpf(1150.0, 315.0, pullback)
	var tilt_window := smoothstep(0.28, 0.54, progress) * (1.0 - smoothstep(0.82, 1.0, progress))
	var tilt := 0.24 * tilt_window if beat_id == "sun-reveal" else 0.18 * smoothstep(0.0, 0.20, progress) + 0.05 * sin(progress * PI)
	var rotating_angle := -float(state.get("earth_angle_rad", 0.0))
	var camera_rotation := lerp_angle(rotating_angle, 0.08, pullback) if beat_id == "sun-reveal" else lerpf(0.08, 0.04, progress)
	if beat_id == "sun-reveal":
		var asteroid_world := _vector(state.get("asteroid_position_au", Vector2.RIGHT))
		var asteroid_rotated := (asteroid_world - camera_target).rotated(camera_rotation)
		var projected_y := center.y + (asteroid_rotated.y * cos(tilt) - float(state.get("relative_z_au", 0.0)) * 2.0 * sin(tilt)) * scale
		var vertical_overflow := maxf(0.0, projected_y - 700.0)
		center.y -= vertical_overflow * smoothstep(0.0, 80.0, vertical_overflow)
		center.y += maxf(0.0, 85.0 - projected_y)
	return {
		"center": center,
		"scale": scale,
		"target": camera_target,
		"tilt": tilt,
		"rotation": camera_rotation,
	}


func _project_sun_position(position_au: Vector2, z_au: float, camera: Dictionary) -> Vector2:
	var relative := position_au - _vector(camera.get("target", Vector2.ZERO))
	var rotated := relative.rotated(float(camera.get("rotation", 0.0)))
	var tilt := float(camera.get("tilt", 0.0))
	var scale := float(camera.get("scale", 1.0))
	var projected_y := rotated.y * cos(tilt) - z_au * 2.0 * sin(tilt)
	return _vector(camera.get("center", Vector2.ZERO)) + Vector2(rotated.x, projected_y) * scale


func _project_sun_vector(vector_au: Vector2, camera: Dictionary) -> Vector2:
	var rotated := vector_au.rotated(float(camera.get("rotation", 0.0)))
	return Vector2(rotated.x, rotated.y * cos(float(camera.get("tilt", 0.0))))


func _draw_projected_orbit_rings(camera: Dictionary, alpha: float) -> void:
	for ring_index in range(3):
		var radius := 0.34 + float(ring_index) * 0.33
		var points := PackedVector2Array()
		for sample_index in range(97):
			var angle := TAU * float(sample_index) / 96.0
			points.append(_project_sun_position(Vector2.RIGHT.rotated(angle) * radius, 0.0, camera))
		draw_polyline(points, Color(SUN, alpha * (0.025 + float(ring_index) * 0.012)), 1.0, true)


func _draw_temporal_heliocentric_path(id: String, state: Dictionary, camera: Dictionary, alpha: float) -> void:
	var record: Dictionary = records_by_id.get(id, {})
	if record.is_empty():
		return
	var source_jd := float(state.get("source_jd", PRIMARY_YEAR_START_JD))
	var year_days := PRIMARY_YEAR_END_JD - PRIMARY_YEAR_START_JD
	var full_path := _projected_ephemeris_jd_segment(record, source_jd - year_days * 0.5, source_jd + year_days * 0.5, 160, camera)
	if full_path.size() > 1:
		draw_polyline(full_path, Color(ASTEROID, alpha * 0.10), 2.0, true)
	var future_path := _projected_ephemeris_jd_segment(record, source_jd, source_jd + year_days * 0.10, 28, camera)
	if future_path.size() > 1:
		draw_polyline(future_path, Color(ASTEROID, alpha * 0.18), 2.0, true)
	for band in range(4):
		var band_start := source_jd + year_days * (-0.28 + float(band) * 0.07)
		var band_end := band_start + year_days * 0.073
		var history := _projected_ephemeris_jd_segment(record, band_start, band_end, 24, camera)
		if history.size() > 1:
			_draw_glow_polyline(history, Color(ASTEROID, alpha * (0.18 + float(band) * 0.15)), 2.5 + float(band) * 0.35)


func _projected_ephemeris_jd_segment(
	record: Dictionary,
	start_jd: float,
	end_jd: float,
	samples: int,
	camera: Dictionary
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(samples + 1):
		var sample_jd := lerpf(start_jd, end_jd, float(index) / float(samples))
		var sample := _sample_ephemeris_record(record, sample_jd)
		points.append(_project_sun_position(
			_vector(sample.get("asteroid_position_au", Vector2.RIGHT)),
			float(sample.get("relative_z_au", 0.0)),
			camera
		))
	return points


func _draw_split_reference_frames() -> void:
	var progress := _beat_progress()
	if progress < 0.08:
		_draw_jpl_orbit_evidence(progress)
		return
	if progress < 0.32:
		_draw_reference_frame_morph(inverse_lerp(0.08, 0.32, progress))
		return
	var split_reveal := smoothstep(0.32, 0.48, progress)
	var left_center := Vector2(960, 525).lerp(Vector2(500, 525), split_reveal)
	var right_center := Vector2(960, 525).lerp(Vector2(1420, 525), split_reveal)
	var sun_scale := 225.0
	var relative_scale := lerpf(1080.0, 720.0, split_reveal)
	_draw_reference_glow(left_center, 250.0, SUN, 0.72 * split_reveal)
	_draw_reference_glow(right_center, 250.0, EARTH, 0.72)
	_draw_reference_label("日心惯性", left_center + Vector2(-220, -390), SUN, split_reveal)
	_draw_reference_label("随地球转动", right_center + Vector2(-220, -390), EARTH)
	_draw_sun(left_center, 15.0)
	_draw_smooth_arc(left_center, sun_scale, 0.0, TAU, Color(EARTH, 0.25 * split_reveal), 2.0)
	_draw_heliocentric_path("co-orbital", left_center, sun_scale, Color(ASTEROID, 0.42 * split_reveal))
	_draw_rotating_path("co-orbital", right_center, relative_scale, Color(ASTEROID, 0.46))
	var state := _state("co-orbital")
	_draw_planet(left_center + _vector(state["earth_position_au"]) * sun_scale, 12.0, Color(EARTH, split_reveal), "")
	_draw_asteroid(left_center + _vector(state["asteroid_position_au"]) * sun_scale, Color(ASTEROID, split_reveal))
	_draw_planet(right_center, 18.0, EARTH, "")
	_draw_asteroid(right_center + _vector(state["relative_rotating_au"]) * relative_scale, ASTEROID)


func _draw_reference_frame_morph(progress: float) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var morph := smoothstep(0.0, 1.0, progress)
	var center := Vector2(960, 510)
	var sun_scale := 300.0
	var relative_scale := 1080.0
	var record: Dictionary = records_by_id.get("co-orbital", {})
	var path := PackedVector2Array()
	var frames: Array = record.get("frames", [])
	var stride := maxi(1, int(ceili(float(frames.size()) / 280.0)))
	for index in range(0, frames.size(), stride):
		var frame: Dictionary = frames[index]
		if not _path_frame_visible(record, frame):
			continue
		var heliocentric := center + _vector(frame.get("asteroid_position_au", Vector2.RIGHT)) * sun_scale
		var rotating := center + _vector(frame.get("relative_rotating_au", Vector2.ZERO)) * relative_scale
		path.append(heliocentric.lerp(rotating, morph))
	if path.size() > 1:
		_draw_glow_polyline(path, Color(ASTEROID, 0.28 + morph * 0.28), 3.4)
	var state := _state("co-orbital")
	var earth_start := center + _vector(state.get("earth_position_au", Vector2.RIGHT)) * sun_scale
	var earth_position := earth_start.lerp(center, morph)
	var axis_angle := -float(state.get("earth_angle_rad", 0.0)) * morph
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		var direction: Vector2 = axis.rotated(axis_angle)
		draw_line(center - direction * 360.0, center + direction * 360.0, Color(EARTH, 0.06 + morph * 0.12), 2.0, true)
	var asteroid_start := center + _vector(state.get("asteroid_position_au", Vector2.RIGHT)) * sun_scale
	var asteroid_end := center + _vector(state.get("relative_rotating_au", Vector2.ZERO)) * relative_scale
	var asteroid_position := asteroid_start.lerp(asteroid_end, morph)
	_draw_sun(center, 18.0)
	_draw_planet(earth_position, lerpf(13.0, 22.0, morph), EARTH, "")
	_draw_asteroid(asteroid_position, ASTEROID, 17.0)
	var pulse := 0.5 + 0.5 * sin(progress * TAU * 3.0)
	draw_arc(asteroid_position, 26.0 + pulse * 6.0, -PI * 0.82, PI * 0.58, 30, Color(ASTEROID, 0.18 + pulse * 0.12), 2.0, true)
	draw_string(VideoTypography.bold(), Vector2(110, 188), "同一位置，轨迹正在变形", HORIZONTAL_ALIGNMENT_LEFT, 1080, 56, colors["text"])
	draw_string(VideoTypography.medium(), Vector2(116, 255), "日心惯性", HORIZONTAL_ALIGNMENT_LEFT, 250, 40, Color(SUN, 1.0 - morph * 0.62))
	draw_string(VideoTypography.medium(), Vector2(390, 255), "随地球转动", HORIZONTAL_ALIGNMENT_LEFT, 330, 40, Color(EARTH, 0.38 + morph * 0.62))


func _draw_jpl_orbit_evidence(progress: float) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var image_rect := Rect2(190, 180, 1540, 650)
	var settle := smoothstep(0.0, 0.10, progress)
	_draw_texture_cover(ASTEROID_ORBIT_JPL, image_rect, lerpf(1.08, 1.0, settle), Vector2(0.50, 0.50), 0.94)
	draw_rect(image_rect, Color(ASTEROID, 0.34), false, 2.0)
	_draw_frame_corners(image_rect, Color(ASTEROID, 0.80), 28.0)
	draw_rect(Rect2(190, 180, 1540, 126), Color(0.004, 0.008, 0.015, 0.78), true)
	draw_string(VideoTypography.bold(), Vector2(230, 260), "主体绕太阳，近地形成环形包络", HORIZONTAL_ALIGNMENT_LEFT, 1420, 54, colors["text"])
	draw_string(VideoTypography.medium(), Vector2(220, 872), "NASA/JPL-Caltech · 2016.06.15", HORIZONTAL_ALIGNMENT_LEFT, 840, 36, colors["muted"])


func _draw_speed_evidence() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var state := _state("co-orbital")
	var distance := float(state.get("solar_distance_au", 1.0))
	var speed := float(state.get("orbital_speed_au_y", TAU))
	var camera := _sun_camera(progress, "speed-change", state)
	var sun_position := _project_sun_position(Vector2.ZERO, 0.0, camera)
	var asteroid_position := _project_sun_position(
		_vector(state.get("asteroid_position_au", Vector2.RIGHT)),
		float(state.get("relative_z_au", 0.0)),
		camera
	)
	var evidence_alpha := smoothstep(0.08, 0.20, progress)
	var record: Dictionary = records_by_id.get("co-orbital", {})
	if not record.is_empty():
		# Equal ten-day ephemeris samples expose the changing distance travelled
		# per unit time; their spacing is not animated by hand.
		for sample_index in range(1, 7):
			var sampled := _sample_ephemeris_record(record, float(state.get("source_jd", PRIMARY_YEAR_START_JD)) - float(sample_index) * 10.0)
			var tick := _project_sun_position(_vector(sampled.get("asteroid_position_au", Vector2.RIGHT)), float(sampled.get("relative_z_au", 0.0)), camera)
			draw_circle(tick, 3.0 + float(7 - sample_index) * 0.35, Color(ASTEROID, evidence_alpha * (0.56 - float(sample_index) * 0.055)))
	var radial_color := Color(SUN, evidence_alpha * 0.42)
	draw_line(sun_position, asteroid_position, radial_color, 2.0, true)
	var radial_direction := sun_position.direction_to(asteroid_position)
	var distance_tick := asteroid_position - radial_direction * 34.0
	draw_line(distance_tick - radial_direction.rotated(PI * 0.5) * 8.0, distance_tick + radial_direction.rotated(PI * 0.5) * 8.0, radial_color, 2.0, true)
	var velocity := _project_sun_vector(_vector(state.get("asteroid_velocity_au_y", Vector2.RIGHT)), camera)
	var velocity_direction := velocity.normalized()
	var speed_delta := clampf((speed - TAU) / 0.65, -1.0, 1.0)
	var vector_length := 112.0 + speed_delta * 34.0
	_draw_arrow(asteroid_position, asteroid_position + velocity_direction * vector_length, Color(ASTEROID, evidence_alpha * 0.92), 4.0)
	var event_strength := smoothstep(0.012, 0.045, absf(distance - 1.0))
	var pulse := 0.5 + 0.5 * sin(video_time_sec * 5.5)
	draw_arc(asteroid_position, 28.0 + event_strength * (8.0 + pulse * 5.0), -PI * 0.8, PI * 0.58, 32, Color(ASTEROID, evidence_alpha * event_strength * (0.18 + pulse * 0.12)), 2.0, true)
	var closer := distance < 1.0
	var relation := "更近 · 更快" if closer else "更远 · 更慢"
	var readout_x := 1320.0
	draw_string(VideoTypography.bold(), Vector2(readout_x, 418), relation, HORIZONTAL_ALIGNMENT_LEFT, 500, 50, Color(ASTEROID, evidence_alpha))
	draw_string(VideoTypography.data(), Vector2(readout_x, 496), "%.3f AU" % distance, HORIZONTAL_ALIGNMENT_LEFT, 330, 42, Color(colors["text"], evidence_alpha))
	draw_string(VideoTypography.data(), Vector2(readout_x, 554), "%.2f AU/年" % speed, HORIZONTAL_ALIGNMENT_LEFT, 400, 42, Color(colors["muted"], evidence_alpha))


func _draw_drift_control() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _resonance_progress()
	var left := Vector2(520, 520)
	var right := Vector2(1400, 520)
	_draw_rotating_path("co-orbital", left, 880.0, Color(ASTEROID, 0.08))
	_draw_partial_rotating_path("co-orbital", left, 880.0, progress, 145, Color(ASTEROID, 0.86))
	_draw_rotating_path("drifting-control", right, 260.0, Color(CONTROL, 0.18))
	_draw_partial_rotating_path("drifting-control", right, 260.0, progress, 240, Color(CONTROL, 0.82))
	# Five-year samples make the phase slip visible as accumulating evidence,
	# without pretending the grey analytic control is a second observed object.
	for step in range(9):
		var sample_progress := float(step) / 8.0
		if sample_progress > progress + 0.001:
			break
		var real_record: Dictionary = records_by_id.get("co-orbital", {})
		var control_record: Dictionary = records_by_id.get("drifting-control", {})
		if real_record.is_empty() or control_record.is_empty():
			break
		var real_state := _sample_record_progress(real_record, sample_progress)
		var control_state := _sample_record_progress(control_record, sample_progress)
		var marker_alpha := lerpf(0.20, 0.55, sample_progress)
		draw_circle(left + _vector(real_state.get("relative_rotating_au", Vector2.ZERO)) * 880.0, 5.0, Color(ASTEROID, marker_alpha))
		draw_circle(right + _vector(control_state.get("relative_rotating_au", Vector2.ZERO)) * 260.0, 5.0, Color(CONTROL, marker_alpha))
	_draw_planet(left, 23, EARTH, "")
	_draw_planet(right, 23, EARTH, "")
	var co_state := _state("co-orbital")
	var drift_state := _state("drifting-control")
	_draw_asteroid(left + _vector(co_state.get("relative_rotating_au", Vector2.ZERO)) * 880.0, ASTEROID)
	_draw_asteroid(right + _vector(drift_state.get("relative_rotating_au", Vector2.ZERO)) * 260.0, CONTROL)
	draw_string(VideoTypography.bold(), Vector2(285, 205), "真实星历｜长期伴随", HORIZONTAL_ALIGNMENT_CENTER, 470, 40, colors["text"])
	draw_string(VideoTypography.bold(), Vector2(1165, 205), "周期接近｜持续漂移", HORIZONTAL_ALIGNMENT_CENTER, 470, 40, colors["text"])
	var display_year := int(round(2010.0 + 40.0 * progress))
	draw_string(VideoTypography.data(), Vector2(760, 250), "%d" % display_year, HORIZONTAL_ALIGNMENT_CENTER, 400, 40, ASTEROID)
	draw_string(VideoTypography.medium(), Vector2(1160, 85), "2010–2050 · 41 年压缩", HORIZONTAL_ALIGNMENT_RIGHT, 640, 36, colors["muted"])
	draw_string(VideoTypography.medium(), Vector2(1160, 130), "JPL Horizons · 黄道平面投影", HORIZONTAL_ALIGNMENT_RIGHT, 640, 36, colors["muted"])


func _resonance_progress() -> float:
	# Finish the forty-year comparison early enough to let the final separation
	# register, rather than cutting away on the exact frame it reaches 2050.
	return smoothstep(0.0, 0.88, _beat_progress())


func _draw_brand_gate() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := clampf(_beat_progress(), 0.0, 1.0)
	var brand_alpha := smoothstep(0.0, 0.10, progress) * (1.0 - smoothstep(0.76, 0.98, progress))
	var wing_alpha := smoothstep(0.0, 0.08, progress) * (1.0 - smoothstep(0.76, 0.98, progress))
	_draw_texture_cover(TIANWEN_SOLAR_WING, Rect2(0, 0, 1920, 875), lerpf(1.10, 1.0, smoothstep(0.0, 0.40, progress)), Vector2(0.56, 0.50), wing_alpha * 0.82)
	draw_rect(Rect2(0, 0, 930, 875), Color(0.004, 0.008, 0.015, wing_alpha * 0.60), true)
	var center := Vector2(1295, 510)
	for ring in range(3):
		var radius := 205.0 + ring * 42.0
		var sweep := clampf(progress * 1.25 - ring * 0.12, 0.0, 1.0) * TAU
		_draw_smooth_arc(center, radius, -PI * 0.72, -PI * 0.72 + sweep, Color(ASTEROID, brand_alpha * (0.48 - ring * 0.08)), 4.0 - ring * 0.7)
	draw_string(VideoTypography.bold(), Vector2(130, 446), "物理实验室", HORIZONTAL_ALIGNMENT_LEFT, 760, 72, Color(colors["text"], brand_alpha))
	draw_string(VideoTypography.data(), Vector2(134, 515), "SLINGSHOT PHYSICS", HORIZONTAL_ALIGNMENT_LEFT, 660, 36, Color(colors["muted"], brand_alpha))


func _draw_moon_comparison() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	if progress < 0.25:
		_draw_earth_moon_observation_evidence(progress)
		_draw_earth_moon_transition(progress)
		return
	var comparison_progress := clampf(inverse_lerp(0.25, 1.0, progress), 0.0, 1.0)
	var earth_a := Vector2(510, 500)
	_draw_orbit_depth_rings(earth_a, 145.0, EARTH)
	_draw_planet(earth_a, 34, EARTH, "地球")
	_draw_smooth_arc(earth_a, 145, 0, TAU, Color(colors["muted"], 0.45), 3.0)
	var moon_angle := comparison_progress * 3.0 * TAU
	_draw_moon(earth_a + Vector2.RIGHT.rotated(moon_angle) * 145, 15.0)
	var moon_label_alpha := smoothstep(0.0, 0.08, comparison_progress)
	var quasi_label_alpha := smoothstep(0.10, 0.22, comparison_progress)
	var boundary_alpha := smoothstep(0.32, 0.50, comparison_progress)
	draw_string(VideoTypography.bold(), Vector2(230, 260), "月球｜绕地球", HORIZONTAL_ALIGNMENT_CENTER, 560, 46, Color(colors["text"], moon_label_alpha))
	var sun_center := Vector2(1330, 500)
	_draw_sun(sun_center, 22.0)
	_draw_orbit_depth_rings(sun_center, 210.0, SUN)
	_draw_smooth_arc(sun_center, 210, 0, TAU, Color(EARTH, 0.35), 3.0)
	var state := _state("co-orbital")
	_draw_planet(sun_center + _vector(state["earth_position_au"]) * 210, 14, EARTH, "")
	_draw_asteroid(sun_center + _vector(state["asteroid_position_au"]) * 210, ASTEROID)
	draw_string(VideoTypography.bold(), Vector2(1050, 260), "准卫星｜绕太阳", HORIZONTAL_ALIGNMENT_CENTER, 560, 46, Color(colors["text"], quasi_label_alpha))
	draw_string(VideoTypography.medium(), Vector2(1190, 145), "两图不同尺度 · 天体非比例", HORIZONTAL_ALIGNMENT_RIGHT, 610, 36, Color(colors["muted"], boundary_alpha))
	_draw_earth_moon_transition(progress)


func _draw_earth_moon_observation_evidence(progress: float) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var settle := smoothstep(0.0, 0.07, progress)
	var alpha := 1.0 - smoothstep(0.23, 0.25, progress)
	var earth_rect := Rect2(130, 220, 760, 545)
	var moon_rect := Rect2(1030, 220, 760, 545)
	_draw_texture_cover(EARTH_NAV_OBSERVATION, earth_rect, lerpf(1.06, 1.0, settle), Vector2(0.50, 0.50), alpha)
	_draw_texture_cover(MOON_NAV_OBSERVATION, moon_rect, lerpf(1.10, 1.0, settle), Vector2(0.50, 0.50), alpha)
	draw_rect(earth_rect, Color(EARTH, 0.32 * alpha), false, 2.0)
	draw_rect(moon_rect, Color(ASTEROID, 0.32 * alpha), false, 2.0)
	_draw_frame_corners(earth_rect, Color(EARTH, 0.82 * alpha), 28.0)
	_draw_frame_corners(moon_rect, Color(ASTEROID, 0.82 * alpha), 28.0)
	draw_string(VideoTypography.bold(), Vector2(120, 180), "同一相机拍到地球与月球", HORIZONTAL_ALIGNMENT_LEFT, 1600, 56, Color(colors["text"], alpha))
	draw_string(VideoTypography.medium(), Vector2(430, 850), "探测器距地球、月球均约 59 万 km", HORIZONTAL_ALIGNMENT_CENTER, 1060, 46, Color(colors["muted"], alpha))
	draw_string(VideoTypography.medium(), Vector2(1190, 180), "天问二号导航相机 · CNSA", HORIZONTAL_ALIGNMENT_RIGHT, 610, 36, Color(colors["muted"], alpha))


func _draw_earth_moon_transition(progress: float) -> void:
	var travel := smoothstep(0.19, 0.32, progress)
	if travel <= 0.001 or travel >= 1.0:
		return
	var alpha := sin(travel * PI) * 0.68
	var moon_position := Vector2(1410, 490).lerp(Vector2(655, 500), travel)
	draw_circle(Vector2(510, 500), lerpf(18.0, 34.0, travel), Color(EARTH, alpha * 0.24))
	draw_circle(moon_position, lerpf(25.0, 15.0, travel), Color(0.86, 0.87, 0.91, alpha * 0.38))


func _draw_rendezvous_principle() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	var encounter := _rendezvous_state(progress)
	var target: Vector2 = encounter["target"]
	var probe: Vector2 = encounter["probe"]
	var target_velocity: Vector2 = encounter["target_velocity"]
	var probe_velocity: Vector2 = encounter["probe_velocity"]
	var meeting: Vector2 = encounter["meeting"]
	var position_remaining := target.distance_to(probe) / float(encounter["initial_distance"])
	var velocity_remaining := target_velocity.distance_to(probe_velocity) / float(encounter["initial_velocity_difference"])
	var title_alpha := smoothstep(0.02, 0.10, progress) * (1.0 - smoothstep(0.24, 0.38, progress))
	draw_string(VideoTypography.bold(), Vector2(110, 188), "交会 = 位置 + 速度同时匹配", HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(colors["text"], title_alpha))
	var target_start := Vector2(1280, 610)
	var probe_start := Vector2(460, 620)
	# A short ghost projection tests the naive idea of steering toward the
	# object's *present* position.  It is a diagram, not a fabricated flight.
	var wrong_way_alpha := smoothstep(0.03, 0.10, progress) * (1.0 - smoothstep(0.31, 0.43, progress))
	if wrong_way_alpha > 0.001:
		draw_dashed_line(probe_start, target_start, Color(CONTROL, wrong_way_alpha * 0.60), 3.0, 14.0)
		_draw_smooth_arc(target_start, 28.0, -PI * 0.25, PI * 1.25, Color(CONTROL, wrong_way_alpha * 0.80), 3.0)
		draw_string(VideoTypography.medium(), Vector2(820, 680), "当前位置会错过", HORIZONTAL_ALIGNMENT_CENTER, 470, 40, Color(CONTROL, wrong_way_alpha))
	draw_dashed_line(target_start, _vector(encounter["target_finish"]), Color(ASTEROID, 0.30), 2.0, 10.0)
	var probe_path := PackedVector2Array()
	for index in range(61):
		var path_p := float(index) / 60.0
		probe_path.append(_vector(_rendezvous_state(path_p)["probe"]))
	_draw_glow_polyline(probe_path, Color(EARTH, 0.50 * smoothstep(0.24, 0.43, progress)), 3.0)
	draw_circle(meeting, 24.0, Color(colors["text"], 0.06))
	_draw_smooth_arc(meeting, 24.0, 0.0, TAU, Color(colors["text"], 0.55), 2.0)
	var future_alpha := smoothstep(0.30, 0.45, progress)
	if future_alpha > 0.001:
		_draw_scan_pulse(meeting, 90.0, Color(colors["text"], future_alpha), 0.35)
	draw_string(VideoTypography.medium(), meeting + Vector2(-470, -88), "未来相遇点", HORIZONTAL_ALIGNMENT_CENTER, 300, 40, Color(colors["muted"], future_alpha))
	_draw_asteroid(target, ASTEROID, 30)
	_draw_probe(probe)
	var vector_alpha := 1.0 - smoothstep(0.90, 0.98, progress)
	if progress >= RENDEZVOUS_CONTACT_PROGRESS:
		_draw_vector(target, target_velocity.normalized() * 125.0, colors["text"], "", Vector2(15, -12), vector_alpha)
	else:
		_draw_vector(target, target_velocity.normalized() * 125.0, ASTEROID, "", Vector2(15, -12), vector_alpha)
		_draw_vector(probe, probe_velocity.normalized() * clampf(probe_velocity.length() * 0.25, 75.0, 180.0), EARTH, "", Vector2(15, 24), vector_alpha)
	var has_met := progress >= RENDEZVOUS_CONTACT_PROGRESS
	_draw_error_bar(Vector2(150, 685), "位置差  Δr", position_remaining, EARTH, has_met)
	_draw_error_bar(Vector2(150, 760), "速度差  Δv", velocity_remaining, ASTEROID, has_met)
	var lock_alpha := smoothstep(RENDEZVOUS_CONTACT_PROGRESS, RENDEZVOUS_CONTACT_PROGRESS + 0.08, progress)
	if lock_alpha > 0.001:
		_draw_smooth_arc(target, 90.0, -PI * 0.76, PI * 0.76, Color(EARTH, lock_alpha * 0.72), 4.0)
	draw_string(VideoTypography.medium(), Vector2(110, 850), "原理示意 · 非任务轨迹", HORIZONTAL_ALIGNMENT_LEFT, 700, 36, colors["muted"])


func _rendezvous_state(progress: float) -> Dictionary:
	# A single time parameter drives both paths and their actual tangents.  At
	# contact, the cubic probe path shares the target's position and derivative.
	var p := clampf(progress, 0.0, 1.0)
	var target_start := Vector2(1280, 610)
	var probe_start := Vector2(460, 620)
	var meeting := Vector2(1440, 355)
	var target_velocity := (meeting - target_start) / RENDEZVOUS_CONTACT_PROGRESS
	var target := target_start + target_velocity * p
	var first_control := Vector2(820, 540)
	var second_control := meeting - target_velocity * RENDEZVOUS_CONTACT_PROGRESS / 3.0
	var initial_probe_velocity := (first_control - probe_start) * 3.0 / RENDEZVOUS_CONTACT_PROGRESS
	var probe := target
	var probe_velocity := target_velocity
	if p < RENDEZVOUS_CONTACT_PROGRESS:
		var path_t := p / RENDEZVOUS_CONTACT_PROGRESS
		probe = _cubic_bezier(probe_start, first_control, second_control, meeting, path_t)
		probe_velocity = _cubic_bezier_derivative(probe_start, first_control, second_control, meeting, path_t) / RENDEZVOUS_CONTACT_PROGRESS
	return {
		"target": target,
		"probe": probe,
		"target_velocity": target_velocity,
		"probe_velocity": probe_velocity,
		"meeting": meeting,
		"target_finish": target_start + target_velocity,
		"initial_distance": target_start.distance_to(probe_start),
		"initial_velocity_difference": target_velocity.distance_to(initial_probe_velocity),
	}


func _cubic_bezier(start: Vector2, first_control: Vector2, second_control: Vector2, finish: Vector2, progress: float) -> Vector2:
	var p := clampf(progress, 0.0, 1.0)
	var inverse := 1.0 - p
	return start * inverse * inverse * inverse + first_control * 3.0 * inverse * inverse * p + second_control * 3.0 * inverse * p * p + finish * p * p * p


func _cubic_bezier_derivative(start: Vector2, first_control: Vector2, second_control: Vector2, finish: Vector2, progress: float) -> Vector2:
	var p := clampf(progress, 0.0, 1.0)
	var inverse := 1.0 - p
	return (first_control - start) * 3.0 * inverse * inverse + (second_control - first_control) * 6.0 * inverse * p + (finish - second_control) * 3.0 * p * p


func _draw_optical_navigation() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var progress := _beat_progress()
	# Three separate observations update the estimate.  The ellipse never
	# collapses to a point: the final kilometre-scale uncertainty remains.
	var p := (smoothstep(0.20, 0.28, progress) + smoothstep(0.39, 0.47, progress) + smoothstep(0.58, 0.67, progress)) / 3.0
	var result_alpha := smoothstep(0.62, 0.74, progress)
	var initial_alpha := 1.0 - result_alpha
	var center := Vector2(1160, 440)
	var target_rect := Rect2(995, 230, 330, 340)
	var image_alpha := lerpf(0.22, 0.90, p)
	_draw_texture_cover(ASTEROID_OBSERVATION, target_rect, lerpf(1.08, 1.0, p), Vector2(0.50, 0.49), image_alpha)
	draw_rect(target_rect, Color(ASTEROID, image_alpha * 0.45), false, 2.0)
	_draw_frame_corners(target_rect, Color(ASTEROID, image_alpha * 0.78), 22.0)
	var radius := Vector2(390, 210).lerp(Vector2(70, 38), p)
	var initial_uncertainty := _ellipse_points(center, Vector2(390, 210), 0.3)
	_draw_glow_polyline(initial_uncertainty, Color(ASTEROID, 0.28 * initial_alpha), 2.0)
	var uncertainty := PackedVector2Array()
	for index in range(121):
		var angle := TAU * float(index) / 120.0
		uncertainty.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y).rotated(0.3))
	draw_colored_polygon(uncertainty, Color(ASTEROID, 0.035))
	_draw_glow_polyline(uncertainty, Color(ASTEROID, 0.66), 3.0)
	_draw_target_brackets(center, 62.0 + (1.0 - p) * 34.0, EARTH, p)
	_draw_scan_pulse(center, 120.0, EARTH, 0.12)
	for index in range(3):
		var origin := Vector2(170, 270 + index * 210)
		var event_start := 0.18 + float(index) * 0.19
		var observation_alpha := smoothstep(event_start, event_start + 0.10, progress)
		draw_line(origin, center, Color(EARTH, (0.12 + 0.08 * index) * observation_alpha), 7.0)
		draw_line(origin, center, Color(EARTH, (0.28 + 0.08 * index) * observation_alpha), 2.0)
		draw_circle(origin, 5.0, Color(EARTH, observation_alpha))
		var event_pulse := smoothstep(event_start, event_start + 0.06, progress) * (1.0 - smoothstep(event_start + 0.10, event_start + 0.17, progress))
		if event_pulse > 0.001:
			_draw_smooth_arc(origin, 18.0 + event_pulse * 26.0, 0.0, TAU, Color(EARTH, event_pulse * 0.48), 3.0)
	var probe_position := Vector2(230, 710).lerp(Vector2(580, 330), p)
	_draw_probe(probe_position)
	draw_line(probe_position + Vector2(30, -55), center, Color(EARTH, 0.62), 3.0)
	draw_string(VideoTypography.medium(), Vector2(900, 758), "地基观测", HORIZONTAL_ALIGNMENT_CENTER, 520, 40, Color(colors["muted"], initial_alpha))
	draw_string(VideoTypography.data(), Vector2(900, 820), ">100 km", HORIZONTAL_ALIGNMENT_CENTER, 520, 50, Color(ASTEROID, initial_alpha))
	draw_string(VideoTypography.medium(), Vector2(1180, 758), "光学导航后", HORIZONTAL_ALIGNMENT_CENTER, 600, 40, Color(colors["muted"], result_alpha))
	draw_string(VideoTypography.data(), Vector2(1180, 820), "km 量级", HORIZONTAL_ALIGNMENT_CENTER, 600, 50, Color(EARTH, result_alpha))
	draw_string(VideoTypography.medium(), Vector2(110, 850), "CNSA 量级 · 椭圆表示不确定范围", HORIZONTAL_ALIGNMENT_LEFT, 980, 36, colors["muted"])


func _draw_science_close() -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var p := smoothstep(0.0, 0.76, _beat_progress())
	var selfie_rect := Rect2(140, 220, 700, 440)
	var target_rect := Rect2(1080, 220, 700, 440)
	_draw_texture_cover(TIANWEN_EARTH_SELFIE, selfie_rect, lerpf(1.08, 1.0, p), Vector2(0.52, 0.58), 0.92)
	_draw_texture_cover(ASTEROID_OBSERVATION, target_rect, lerpf(1.12, 1.0, p), Vector2(0.50, 0.49), lerpf(0.28, 0.92, smoothstep(0.0, 0.30, p)))
	draw_rect(selfie_rect, Color(EARTH, 0.28), false, 2.0)
	draw_rect(target_rect, Color(ASTEROID, 0.32), false, 2.0)
	_draw_frame_corners(selfie_rect, Color(EARTH, 0.78), 26.0)
	_draw_frame_corners(target_rect, Color(ASTEROID, 0.82), 26.0)
	var bridge_start := Vector2(selfie_rect.end.x, selfie_rect.get_center().y)
	var bridge_end := Vector2(target_rect.position.x, target_rect.get_center().y)
	draw_line(bridge_start, bridge_end, Color(colors["divider"], 0.55), 2.0)
	var pulse_position := bridge_start.lerp(bridge_end, fposmod(p * 1.8, 1.0))
	draw_circle(pulse_position, 5.0, EARTH)
	draw_string(VideoTypography.medium(), Vector2(165, 715), "天问二号与地球", HORIZONTAL_ALIGNMENT_LEFT, 650, 40, colors["muted"])
	draw_string(VideoTypography.medium(), Vector2(1085, 715), "目标 2016 HO3 · 20 km", HORIZONTAL_ALIGNMENT_LEFT, 680, 40, colors["muted"])
	draw_string(VideoTypography.medium(), Vector2(570, 830), "CNSA · 近距离探测", HORIZONTAL_ALIGNMENT_CENTER, 780, 36, colors["muted"])


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


func _draw_planet(position: Vector2, radius: float, color: Color, label: String, alpha: float = 1.0) -> void:
	if not label.is_empty():
		draw_string(VideoTypography.medium(), position + Vector2(-120, radius + 56), label, HORIZONTAL_ALIGNMENT_CENTER, 240, 40, Color(episode["theme"]["colors"]["text"], alpha))


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
		"cold-open":
			var progress := clampf(_beat_progress(), 0.0, 1.0)
			var alpha := smoothstep(0.14, 0.25, progress)
			if alpha > 0.001:
				_place_celestial("earth", Vector2(1050, 500), 34.0, alpha)
		"earth-frame":
			_place_celestial("earth", Vector2(960, 500), 29.0)
		"sun-reveal", "speed-change":
			var progress := _beat_progress()
			var state := _state("co-orbital")
			var camera := _sun_camera(progress, beat_id, state)
			var establish_alpha := smoothstep(0.08, 0.24, progress) if beat_id == "sun-reveal" else 1.0
			var sun_position := _project_sun_position(Vector2.ZERO, 0.0, camera)
			var earth_position := _project_sun_position(_vector(state.get("earth_position_au", Vector2.RIGHT)), 0.0, camera)
			_place_celestial("sun", sun_position, 24.0, establish_alpha)
			var earth_radius := lerpf(29.0, 17.0, smoothstep(0.0, 0.28, progress)) if beat_id == "sun-reveal" else 17.0
			_place_celestial("earth", earth_position, earth_radius)
		"same-state-two-frames":
			var progress := _beat_progress()
			if progress < 0.08:
				return
			if progress < 0.32:
				var morph := smoothstep(0.0, 1.0, inverse_lerp(0.08, 0.32, progress))
				var center := Vector2(960, 510)
				var state := _state("co-orbital")
				var earth_start := center + _vector(state.get("earth_position_au", Vector2.RIGHT)) * 300.0
				_place_celestial("sun", center, 18.0, 1.0 - morph)
				_place_celestial("earth", earth_start.lerp(center, morph), lerpf(13.0, 22.0, morph))
				return
			var split_reveal := smoothstep(0.32, 0.48, progress)
			var left_center := Vector2(960, 525).lerp(Vector2(500, 525), split_reveal)
			var right_center := Vector2(960, 525).lerp(Vector2(1420, 525), split_reveal)
			var state := _state("co-orbital")
			_place_celestial("sun", left_center, 15.0, split_reveal)
			_place_celestial("earth", left_center + _vector(state.get("earth_position_au", Vector2.RIGHT)) * 225.0, 12.0, split_reveal)
			_place_celestial("earth", right_center, 18.0)
		"resonance-boundary":
			_place_celestial("earth", Vector2(520, 520), 23.0)
			_place_celestial("earth", Vector2(1400, 520), 23.0)
		"moon-comparison":
			var progress := _beat_progress()
			if progress < 0.25:
				return
			var earth_center := Vector2(510, 500)
			var sun_center := Vector2(1330, 500)
			var state := _state("co-orbital")
			var moon_angle := clampf(inverse_lerp(0.25, 1.0, progress), 0.0, 1.0) * 3.0 * TAU
			_place_celestial("earth", earth_center, 34.0)
			_place_celestial("moon", earth_center + Vector2.RIGHT.rotated(moon_angle) * 145.0, 15.0)
			_place_celestial("sun", sun_center, 22.0)
			_place_celestial("earth", sun_center + _vector(state.get("earth_position_au", Vector2.RIGHT)) * 210.0, 14.0)


func _place_celestial(kind: String, position: Vector2, radius: float, alpha: float = 1.0) -> void:
	_ensure_celestial_pool()
	var pool: Array = celestial_pools[kind]
	var index: int = int(celestial_pool_indices[kind])
	if index >= pool.size():
		var body := _create_celestial_body(kind, index)
		pool.append(body)
		celestial_pools[kind] = pool
	var selected: Node2D = pool[index]
	selected.configure(kind, position, radius)
	selected.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
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


func _draw_error_bar(position: Vector2, label: String, remaining: float, color: Color, matched: bool = false) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	draw_string(VideoTypography.medium(), position, label, HORIZONTAL_ALIGNMENT_LEFT, ERROR_BAR_LABEL_WIDTH, 40, colors["muted"])
	var bar := Rect2(
		position + Vector2(ERROR_BAR_LABEL_WIDTH + ERROR_BAR_LABEL_GAP, -19),
		Vector2(ERROR_BAR_WIDTH, 18)
	)
	draw_rect(bar, Color(colors["divider"], 0.42), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(remaining, 0.0, 1.0), bar.size.y)), color, true)
	if matched:
		draw_string(VideoTypography.bold(), bar.position + Vector2(bar.size.x + 16.0, 10), "已匹配", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, color)


func _ellipse_points(center: Vector2, radius: Vector2, rotation: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(121):
		var angle := TAU * float(index) / 120.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y).rotated(rotation))
	return points


func _draw_vector(origin: Vector2, value: Vector2, color: Color, label: String, label_offset := Vector2(15, -8), alpha: float = 1.0) -> void:
	if alpha <= 0.001:
		return
	var visible_color := Color(color, clampf(alpha, 0.0, 1.0))
	var end := origin + value
	draw_line(origin, end, visible_color, 5.0, true)
	var direction := value.normalized()
	draw_colored_polygon(PackedVector2Array([end, end - direction.rotated(0.55) * 22, end - direction.rotated(-0.55) * 22]), visible_color)
	draw_string(VideoTypography.medium(), end + label_offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, visible_color)


func _draw_axes(center: Vector2, extent: float, color: Color) -> void:
	draw_line(center - Vector2(extent, 0), center + Vector2(extent, 0), color, 1.0)
	draw_line(center - Vector2(0, extent), center + Vector2(0, extent), color, 1.0)


func _draw_reference_glow(center: Vector2, radius: float, color: Color, alpha: float) -> void:
	for layer in range(5):
		var layer_progress := float(layer) / 4.0
		var layer_radius := radius * lerpf(1.08, 0.76, layer_progress)
		var layer_alpha := alpha * lerpf(0.004, 0.012, layer_progress)
		draw_circle(center, layer_radius, Color(color, layer_alpha))
	draw_arc(center, radius * 0.94, 0.0, TAU, 160, Color(color, alpha * 0.10), 1.5, true)
	draw_arc(center, radius * 0.72, 0.0, TAU, 140, Color(color, alpha * 0.045), 1.0, true)


func _draw_reference_label(text: String, anchor: Vector2, color: Color, alpha: float = 1.0) -> void:
	draw_string(VideoTypography.medium(), anchor + Vector2(0, 38), text, HORIZONTAL_ALIGNMENT_LEFT, 360, 40, Color(color, alpha))


func _draw_model_boundary(text: String = "JPL Horizons 星历 · 黄道投影 · 天体大小非比例", alpha: float = 1.0) -> void:
	var colors: Dictionary = episode["theme"]["colors"]
	var compact_text := text.replace(" 星历", "").replace("天体大小非比例", "非比例")
	draw_string(VideoTypography.medium(), Vector2(980, 850), compact_text, HORIZONTAL_ALIGNMENT_RIGHT, 820, 36, Color(colors["muted"], alpha))


func _draw_texture_cover(
	texture: Texture2D,
	target_rect: Rect2,
	zoom: float = 1.0,
	focus: Vector2 = Vector2(0.5, 0.5),
	alpha: float = 1.0
) -> void:
	if texture == null or alpha <= 0.001:
		return
	var texture_size := texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var target_aspect := target_rect.size.x / target_rect.size.y
	var source_aspect := texture_size.x / texture_size.y
	var source_size := texture_size
	if source_aspect > target_aspect:
		source_size.x = texture_size.y * target_aspect
	else:
		source_size.y = texture_size.x / target_aspect
	source_size /= maxf(zoom, 1.0)
	var available := texture_size - source_size
	var source_position := Vector2(
		available.x * clampf(focus.x, 0.0, 1.0),
		available.y * clampf(focus.y, 0.0, 1.0)
	)
	draw_texture_rect_region(
		texture,
		target_rect,
		Rect2(source_position, source_size),
		Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)),
		false,
		true
	)


func _draw_frame_corners(rect: Rect2, color: Color, arm: float) -> void:
	for quadrant: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var corner: Vector2 = rect.get_center() + rect.size * 0.5 * quadrant
		draw_line(corner, corner - Vector2(quadrant.x * arm, 0), color, 3.0)
		draw_line(corner, corner - Vector2(0, quadrant.y * arm), color, 3.0)


func _state(id: String) -> Dictionary:
	var record: Dictionary = records_by_id.get(id, {})
	if record.is_empty():
		return states_by_id.get(id, {})
	if bool(record.get("authoritative_ephemeris", false)):
		return _sample_ephemeris_record(record, _display_jd(record))
	if String(current_beat.get("id", "")) == "resonance-boundary":
		return _sample_record_progress(record, _resonance_progress())
	return _sample_record_progress(record, _beat_progress())


func _display_jd(record: Dictionary) -> float:
	var start_jd := float(record.get("source_start_jd", PRIMARY_YEAR_START_JD))
	var end_jd := float(record.get("source_end_jd", PRIMARY_YEAR_END_JD))
	var beat_id := String(current_beat.get("id", ""))
	if beat_id in ["earth-frame", "sun-reveal", "speed-change"]:
		var year_days := PRIMARY_YEAR_END_JD - PRIMARY_YEAR_START_JD
		var earth_years := _episode_beat_duration("earth-frame") / EARTH_FRAME_SECONDS_PER_YEAR
		var sun_years := _episode_beat_duration("sun-reveal") / SUN_REVEAL_SECONDS_PER_YEAR
		var elapsed := _beat_progress() * float(current_beat.get("duration", 0.0))
		var years := elapsed / EARTH_FRAME_SECONDS_PER_YEAR
		if beat_id == "sun-reveal":
			years = earth_years + elapsed / SUN_REVEAL_SECONDS_PER_YEAR
		elif beat_id == "speed-change":
			years = earth_years + sun_years + elapsed / 15.3
		return clampf(PRIMARY_YEAR_END_JD + years * year_days, start_jd, end_jd)
	if String(current_beat.get("id", "")) == "same-state-two-frames":
		var loop_progress := fposmod(_beat_progress() * 1.80, 1.0)
		return lerpf(PRIMARY_YEAR_START_JD, PRIMARY_YEAR_END_JD, loop_progress)
	if String(current_beat.get("id", "")) == "moon-comparison":
		var comparison_progress := clampf(inverse_lerp(0.08, 1.0, _beat_progress()), 0.0, 1.0)
		var loop_progress := fposmod(comparison_progress * 3.0, 1.0)
		return lerpf(PRIMARY_YEAR_START_JD, PRIMARY_YEAR_END_JD, loop_progress)
	if String(current_beat.get("id", "")) == "resonance-boundary":
		return lerpf(start_jd, end_jd, _resonance_progress())
	var primary_progress := clampf(video_time_sec / 120.0, 0.0, 1.0)
	return lerpf(PRIMARY_YEAR_START_JD, PRIMARY_YEAR_END_JD, primary_progress)


func _episode_beat_duration(beat_id: String) -> float:
	for beat_value in episode.get("beats", []):
		var beat: Dictionary = beat_value
		if String(beat.get("id", "")) == beat_id:
			return float(beat.get("duration", 0.0))
	return 0.0


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
