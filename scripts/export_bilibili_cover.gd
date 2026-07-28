extends SceneTree

const ProjectileSolver = preload("res://src/simulation/projectile_drag_solver.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: export_bilibili_cover.gd <output-json>")
		quit(2)
		return

	var output_path := args[0]
	var preset := _read_json("res://presets/t001-drag-base.json")
	var final_sidecar := _read_json("res://renders/final/s01e03-angle-with-drag.json")
	if preset.is_empty() or final_sidecar.is_empty():
		quit(2)
		return

	var record_40 := _simulate_angle(preset, 40.0)
	var record_45 := _simulate_angle(preset, 45.0)
	if not _validate_against_sidecar(record_40, record_45, final_sidecar):
		quit(3)
		return

	var output := {
		"schema_version": 1,
		"episode_id": "s01e03-angle-with-drag",
		"source_sidecar": "res://renders/final/s01e03-angle-with-drag.json",
		"source_preset": "res://presets/t001-drag-base.json",
		"records": {
			"angle_40": _cover_record(record_40),
			"angle_45": _cover_record(record_45),
		},
	}

	var absolute_output := output_path
	if output_path.begins_with("res://") or output_path.begins_with("user://"):
		absolute_output = ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	var file := FileAccess.open(absolute_output, FileAccess.WRITE)
	if file == null:
		printerr("cover-data: cannot write %s" % absolute_output)
		quit(4)
		return
	file.store_string(JSON.stringify(output, "  "))
	file.close()
	print("cover-data: output=%s" % absolute_output)
	print("cover-data: 40deg=%.5fm 45deg=%.5fm" % [
		float(record_40["metrics"]["flight_range_m"]),
		float(record_45["metrics"]["flight_range_m"]),
	])
	quit(0)


func _simulate_angle(base_preset: Dictionary, angle_deg: float) -> Dictionary:
	var preset := base_preset.duplicate(true)
	var launch_array: Array = preset["scene"]["launch_position_m"]
	var target_array: Array = preset["scene"]["target_position_m"]
	preset["scene"]["launch_position_m"] = Vector2(
		float(launch_array[0]), float(launch_array[1])
	)
	preset["scene"]["target_position_m"] = Vector2(
		float(target_array[0]), float(target_array[1])
	)
	preset["physics"]["launch_angle_deg"] = angle_deg
	return ProjectileSolver.simulate(preset, 240, 6.0)


func _cover_record(record: Dictionary) -> Dictionary:
	var points: Array = []
	var frames: Array = record["frames"]
	for index in range(frames.size()):
		if index % 10 != 0 and index != frames.size() - 1:
			continue
		var position: Vector2 = frames[index]["position_m"]
		points.append([position.x, position.y])
	return {
		"metrics": record["metrics"],
		"points_m": points,
	}


func _validate_against_sidecar(record_40: Dictionary, record_45: Dictionary, sidecar: Dictionary) -> bool:
	var expected := {}
	for row_value in sidecar.get("analysis", {}).get("rows", []):
		var row: Dictionary = row_value
		expected[String(row.get("variant_id", ""))] = float(row.get("value", 0.0))
	if not expected.has("angle-40") or not expected.has("angle-45"):
		printerr("cover-data: final sidecar is missing 40° or 45°")
		return false
	var actual_40 := float(record_40["metrics"]["flight_range_m"])
	var actual_45 := float(record_45["metrics"]["flight_range_m"])
	if absf(actual_40 - float(expected["angle-40"])) > 0.0001:
		printerr("cover-data: 40° result differs from final sidecar")
		return false
	if absf(actual_45 - float(expected["angle-45"])) > 0.0001:
		printerr("cover-data: 45° result differs from final sidecar")
		return false
	return true


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("cover-data: cannot read %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		printerr("cover-data: invalid JSON object at %s" % path)
		return {}
	return parsed
