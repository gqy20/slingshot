extends RefCounted

const Solver = preload("res://src/simulation/quasi_satellite_solver.gd")
const EphemerisSolver = preload("res://src/simulation/horizons_ephemeris_solver.gd")
const OrbitalCanvas = preload("res://src/video/canvases/orbital_companion_canvas.gd")


func run(test) -> void:
	var preset := {
		"physics": {"orbital_period_years": 1.0},
		"scene": {
			"semi_major_axis_au": 1.0,
			"eccentricity": 0.08,
			"period_ratio": 1.0,
			"phase_offset_rad": 0.55,
			"periapsis_angle_rad": -0.35,
		}
	}
	var record := Solver.simulate(preset, 60, 12.0)
	test.check(record["frames"].size() == 721, "orbital solver emits deterministic inclusive frame count")
	test.check(not record["authoritative_ephemeris"], "conceptual solver cannot be mistaken for authoritative ephemeris")
	var sample: Dictionary = record["frames"][173]
	var earth: Vector2 = sample["earth_position_au"]
	var asteroid: Vector2 = sample["asteroid_position_au"]
	var recovered := (asteroid - earth).rotated(-float(sample["earth_angle_rad"]))
	test.check(recovered.distance_to(sample["relative_rotating_au"]) < 0.000001, "co-rotating state is a coordinate transform of the same inertial positions")
	test.check(float(record["metrics"]["loop_closure_au"]) < 0.000001, "equal-period conceptual orbit closes after one mapped year")

	var drifting := preset.duplicate(true)
	drifting["scene"]["period_ratio"] = 1.02
	var drift_record := Solver.simulate(drifting, 60, 12.0)
	test.check(float(drift_record["metrics"]["loop_closure_au"]) > 0.05, "two-percent period mismatch produces visible relative drift")

	var ephemeris_record := EphemerisSolver.simulate(
		"res://data/ephemerides/2016-ho3-earth-2010-2050.json",
		30,
		4.0,
		2461041.5,
		2461406.5
	)
	test.check(not ephemeris_record.has("error"), "Horizons ephemeris imports into a deterministic record")
	test.check(bool(ephemeris_record.get("authoritative_ephemeris", false)), "ephemeris record preserves its evidence level")
	var ephemeris_sample: Dictionary = ephemeris_record["frames"][57]
	var ephemeris_earth: Vector2 = ephemeris_sample["earth_position_au"]
	var ephemeris_asteroid: Vector2 = ephemeris_sample["asteroid_position_au"]
	var ephemeris_recovered := (ephemeris_asteroid - ephemeris_earth).rotated(
		-float(ephemeris_sample["earth_angle_rad"])
	)
	test.check(ephemeris_recovered.distance_to(ephemeris_sample["relative_rotating_au"]) < 0.000001, "real ephemeris uses the same inertial-to-rotating coordinate transform")
	test.check(not String(ephemeris_record["source_manifest"]["asteroid_raw_response_sha256"]).is_empty(), "ephemeris record carries the raw Horizons response hash")
	var episode_config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/episodes/s01e06-earth-quasi-satellite.json"))
	var orbital_canvas := OrbitalCanvas.new()
	orbital_canvas.episode = episode_config
	var ephemeris_bounds := {"source_start_jd": 2455000.0, "source_end_jd": 2475000.0}
	var earth_beat: Dictionary = episode_config["beats"][2]
	var sun_beat: Dictionary = episode_config["beats"][3]
	var speed_beat: Dictionary = episode_config["beats"][4]
	test.check(String(earth_beat["id"]) == "earth-frame", "the opening goes directly from brand to Earth frame")
	orbital_canvas.current_beat = earth_beat
	orbital_canvas.video_time_sec = float(earth_beat["at"])
	var earth_start_jd := orbital_canvas._display_jd(ephemeris_bounds)
	orbital_canvas.video_time_sec = float(earth_beat["at"]) + float(earth_beat["duration"])
	var earth_end_jd := orbital_canvas._display_jd(ephemeris_bounds)
	orbital_canvas.current_beat = sun_beat
	orbital_canvas.video_time_sec = float(sun_beat["at"])
	var sun_start_jd := orbital_canvas._display_jd(ephemeris_bounds)
	orbital_canvas.video_time_sec = float(sun_beat["at"]) + float(sun_beat["duration"])
	var sun_end_jd := orbital_canvas._display_jd(ephemeris_bounds)
	orbital_canvas.current_beat = speed_beat
	orbital_canvas.video_time_sec = float(speed_beat["at"])
	var speed_start_jd := orbital_canvas._display_jd(ephemeris_bounds)
	test.check(earth_start_jd > 2461406.0 and earth_end_jd > earth_start_jd, "Earth frame advances through real adjacent-year ephemeris")
	test.check(absf(earth_end_jd - sun_start_jd) < 0.000001, "Earth-to-Sun frame switch preserves Julian date")
	test.check(sun_end_jd > sun_start_jd and absf(sun_end_jd - speed_start_jd) < 0.000001, "Sun-to-speed switch preserves advancing Julian date")
	var boundary_state := {
		"earth_position_au": Vector2(0.72, 0.59),
		"asteroid_position_au": Vector2(0.78, 0.55),
		"earth_angle_rad": 1.4,
	}
	var opening_camera := orbital_canvas._sun_camera(0.0, "sun-reveal", boundary_state)
	var projected_asteroid := orbital_canvas._project_sun_position(boundary_state["asteroid_position_au"], 0.0, opening_camera)
	var boundary_earth: Vector2 = boundary_state["earth_position_au"]
	var boundary_asteroid: Vector2 = boundary_state["asteroid_position_au"]
	var rotating_asteroid := Vector2(960, 500) + (boundary_asteroid - boundary_earth).rotated(-1.4) * 1150.0
	test.check(projected_asteroid.distance_to(rotating_asteroid) < 0.001, "Sun pullback starts at the Earth-frame asteroid screen position")
	var reveal_record := EphemerisSolver.simulate(
		"res://data/ephemerides/2016-ho3-earth-2010-2050.json",
		30,
		4.0,
		2461406.5,
		2462600.0
	)
	test.check(not reveal_record.has("error"), "continuous reveal window loads from Horizons ephemeris")
	var reveal_asteroid_visible := true
	for sample_index in range(21):
		var reveal_progress := float(sample_index) / 40.0
		orbital_canvas.current_beat = sun_beat
		orbital_canvas.video_time_sec = float(sun_beat["at"]) + reveal_progress * float(sun_beat["duration"])
		var reveal_jd := orbital_canvas._display_jd(reveal_record)
		var reveal_state := orbital_canvas._sample_ephemeris_record(reveal_record, reveal_jd)
		var reveal_camera := orbital_canvas._sun_camera(reveal_progress, "sun-reveal", reveal_state)
		var reveal_position := orbital_canvas._project_sun_position(
			reveal_state["asteroid_position_au"],
			float(reveal_state["relative_z_au"]),
			reveal_camera
		)
		if reveal_position.x < 60.0 or reveal_position.x > 1860.0 or reveal_position.y < 60.0 or reveal_position.y > 790.0:
			reveal_asteroid_visible = false
	test.check(reveal_asteroid_visible, "Sun pullback keeps the moving asteroid inside the visual stage")
	var resonance_beat: Dictionary = episode_config["beats"][6]
	orbital_canvas.current_beat = resonance_beat
	orbital_canvas.video_time_sec = float(resonance_beat["at"]) + float(resonance_beat["duration"]) * 0.88
	var held_jd := orbital_canvas._display_jd(ephemeris_bounds)
	orbital_canvas.video_time_sec = float(resonance_beat["at"]) + float(resonance_beat["duration"])
	test.check(absf(orbital_canvas._display_jd(ephemeris_bounds) - held_jd) < 0.000001, "forty-year drift conclusion holds its final ephemeris state")
	var rendezvous_beat: Dictionary = episode_config["beats"][8]
	var before_contact := orbital_canvas._rendezvous_state(0.60)
	var at_contact := orbital_canvas._rendezvous_state(OrbitalCanvas.RENDEZVOUS_CONTACT_PROGRESS)
	var after_contact := orbital_canvas._rendezvous_state(0.94)
	var before_probe: Vector2 = before_contact["probe"]
	var before_target: Vector2 = before_contact["target"]
	var contact_probe: Vector2 = at_contact["probe"]
	var contact_target: Vector2 = at_contact["target"]
	var contact_probe_velocity: Vector2 = at_contact["probe_velocity"]
	var contact_target_velocity: Vector2 = at_contact["target_velocity"]
	var after_probe: Vector2 = after_contact["probe"]
	var after_target: Vector2 = after_contact["target"]
	test.check(before_probe.distance_to(before_target) > 1.0, "probe remains separate before the common encounter time")
	test.check(contact_probe.distance_to(contact_target) < 0.001, "probe and target occupy the same point at encounter")
	test.check(contact_probe_velocity.distance_to(contact_target_velocity) < 0.001, "probe and target velocities match at encounter")
	test.check(after_probe.distance_to(after_target) < 0.001 and after_target.distance_to(contact_target) > 1.0, "matched bodies continue moving after encounter rather than freezing")
	var contact_video_sec := float(rendezvous_beat["at"]) + float(rendezvous_beat["duration"]) * OrbitalCanvas.RENDEZVOUS_CONTACT_PROGRESS
	var narration_cues: Dictionary = SlingshotSubtitleTrack.load_path("res://content/subtitles/s01e06-earth-quasi-satellite.srt")
	test.check(bool(narration_cues["ok"]), "retimed orbital subtitle track loads")
	var encounter_line_contains_contact := false
	for cue_value in narration_cues["cues"]:
		var cue: Dictionary = cue_value
		if String(cue["text"]).contains("抵达时") and contact_video_sec >= float(cue["start_sec"]) and contact_video_sec < float(cue["end_sec"]):
			encounter_line_contains_contact = true
	test.check(encounter_line_contains_contact, "illustrative position and velocity contact occurs during the matching narration line")
	orbital_canvas.free()

	var audit_regions := OrbitalCanvas.layout_audit_regions()
	for beat_id in audit_regions:
		var regions: Array = audit_regions[beat_id]
		for region_value in regions:
			var region: Rect2 = region_value
			test.check(region.position.x >= 0.0 and region.position.y >= 0.0, "%s orbital layout region starts on canvas" % beat_id)
			test.check(region.end.x <= 1920.0 and region.end.y <= 880.0, "%s orbital layout region stays above subtitle safety line" % beat_id)
		for left_index in range(regions.size()):
			for right_index in range(left_index + 1, regions.size()):
				var left_region: Rect2 = regions[left_index]
				var right_region: Rect2 = regions[right_index]
				test.check(not left_region.intersects(right_region), "%s orbital layout regions do not overlap" % beat_id)

	var canvas_source := FileAccess.get_file_as_string(
		"res://src/video/canvases/orbital_companion_canvas.gd"
	)
	var draw_font_pattern := RegEx.new()
	var pattern_error := draw_font_pattern.compile(
		"draw_string\\([^\\n]+,\\s*(\\d+)\\s*,\\s*(?:Color\\(|colors\\[|episode\\[|[A-Z][A-Z_]+\\b|color\\b|visible_color\\b)"
	)
	test.check(pattern_error == OK, "orbital mobile font audit pattern compiles")
	var font_matches := draw_font_pattern.search_all(canvas_source)
	var smallest_font_size := 1000
	for font_match in font_matches:
		smallest_font_size = mini(smallest_font_size, int(font_match.get_string(1)))
	test.check(font_matches.size() >= 40, "orbital mobile font audit covers visible canvas text")
	test.check(smallest_font_size >= 36, "orbital canvas keeps visible text at least 36 px")
	var hud_source := FileAccess.get_file_as_string("res://src/video/episode_hud.gd")
	test.check(
		'outro_brand_label.add_theme_font_size_override("font_size", 60)' in hud_source,
		"large orbital outro brand stays at least 60 px"
	)
	test.check(
		'outro_descriptor_label.add_theme_font_size_override("font_size", 40)' in hud_source,
		"large orbital outro descriptor stays at least 40 px"
	)
