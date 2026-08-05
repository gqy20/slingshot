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
