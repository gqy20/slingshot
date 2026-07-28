class_name SlingshotExperimentRunner
extends Node

signal completed(bundle: Dictionary)

const SimulationWorld = preload("res://src/simulation/simulation_world.gd")
const RunRecord = preload("res://src/core/run_record.gd")
const ShotModel = preload("res://src/core/shot_model.gd")
const ProjectileSolver = preload("res://src/simulation/projectile_drag_solver.gd")
const ImpactPulseSolver = preload("res://src/simulation/impact_pulse_solver.gd")

var episode: Dictionary = {}
var output_path := ""
var records: Array = []
var variant_index := -1
var current_variant: Dictionary = {}
var current_world: SlingshotSimulationWorld
var current_frames: Array = []
var current_events: Array = []
var current_metrics: Dictionary = {}
var elapsed_sec := 0.0
var active := false
var transitioning := false
var pending_collision := false
var pre_collision_bird_velocity := Vector2.ZERO
var pre_collision_target_velocity := Vector2.ZERO
var last_bird_velocity := Vector2.ZERO


func start(normalized_episode: Dictionary, record_path: String) -> void:
	episode = normalized_episode
	output_path = record_path
	Engine.physics_ticks_per_second = int(episode["simulation"]["tick_rate"])
	if String(episode["simulation"].get("model", "rigidbody")) == "projectile_drag":
		call_deferred("_simulate_projectile_drag_episode")
		return
	if String(episode["simulation"].get("model", "rigidbody")) == "impact_pulse":
		call_deferred("_simulate_impact_pulse_episode")
		return
	variant_index = -1
	_start_next_variant()


func _simulate_projectile_drag_episode() -> void:
	var tick_rate := int(episode["simulation"]["tick_rate"])
	var duration := float(episode["simulation"]["duration_sec"])
	records = []
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var record := ProjectileSolver.simulate(variant["preset"], tick_rate, duration)
		record["variant_id"] = variant["id"]
		record["label"] = variant["label"]
		record["color_html"] = variant["color_html"]
		records.append(record)
		print(
			"[episode:simulate] complete=%s range=%.3f max_height=%.3f"
			% [
				variant["id"],
				float(record["metrics"]["flight_range_m"]),
				float(record["metrics"]["max_height_m"]),
			]
		)
	var extras := _projectile_angle_scans(tick_rate, duration)
	var bundle := RunRecord.make_bundle(episode, records, extras)
	var result := RunRecord.write_json(output_path, bundle)
	if result != OK:
		push_error("failed to write run record: %s" % error_string(result))
		get_tree().quit(3)
		return
	print("[episode:simulate] record=%s variants=%d" % [output_path, records.size()])
	completed.emit(bundle)
	get_tree().quit(0)


func _simulate_impact_pulse_episode() -> void:
	var tick_rate := int(episode["simulation"]["tick_rate"])
	var duration := float(episode["simulation"]["duration_sec"])
	var sample_rate := int(episode["simulation"].get("pulse_sample_rate_hz", 10000))
	records = []
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var record := ImpactPulseSolver.simulate(
			variant["preset"], tick_rate, duration, sample_rate
		)
		record["variant_id"] = variant["id"]
		record["label"] = variant["label"]
		record["color_html"] = variant["color_html"]
		records.append(record)
		print(
			"[episode:simulate] complete=%s impulse=%.3f peak=%.3f"
			% [
				variant["id"],
				float(record["metrics"]["impulse_ns"]),
				float(record["metrics"]["peak_force_n"]),
			]
		)
	var extras := {"impact_measurement": _impact_measurement_extras(records)}
	var bundle := RunRecord.make_bundle(episode, records, extras)
	var result := RunRecord.write_json(output_path, bundle)
	if result != OK:
		push_error("failed to write run record: %s" % error_string(result))
		get_tree().quit(3)
		return
	print("[episode:simulate] record=%s variants=%d" % [output_path, records.size()])
	completed.emit(bundle)
	get_tree().quit(0)


func _impact_measurement_extras(impact_records: Array) -> Dictionary:
	if impact_records.is_empty():
		return {}
	var hard: Dictionary = impact_records[0]
	var curve: Array = hard.get("force_curve", [])
	var contact_start := 0.012
	var rates := [10000.0, 1000.0, 100.0, 30.0]
	var sampled: Array = []
	for rate in rates:
		sampled.append({
			"rate_hz": rate,
			"peak_force_n": ImpactPulseSolver.sampled_peak(
				curve, contact_start, rate, 0.0
			),
		})
	return {
		"contact_start_sec": contact_start,
		"sampled_peaks": sampled,
	}


func _projectile_angle_scans(tick_rate: int, duration: float) -> Dictionary:
	var scan: Dictionary = episode["simulation"].get("angle_scan", {})
	if scan.is_empty() or episode["variants"].is_empty():
		return {}
	var base_preset: Dictionary = episode["variants"][0]["preset"].duplicate(true)
	var min_angle := float(scan["min_angle_deg"])
	var max_angle := float(scan["max_angle_deg"])
	var step := float(scan["step_deg"])
	var drag_points := ProjectileSolver.scan_angles(
		base_preset, tick_rate, duration, min_angle, max_angle, step
	)
	var range_scans: Array = [{
		"id": "air",
		"label": "有空气",
		"color_html": episode["theme"]["colors"]["accent"].to_html(false),
		"points": drag_points,
		"best": ProjectileSolver.best_point(drag_points),
	}]
	if bool(scan.get("include_vacuum", true)):
		var vacuum_preset := base_preset.duplicate(true)
		vacuum_preset["physics"]["air_density_kg_m3"] = 0.0
		var vacuum_points := ProjectileSolver.scan_angles(
			vacuum_preset, tick_rate, duration, min_angle, max_angle, step
		)
		range_scans.push_front({
			"id": "vacuum",
			"label": "理想真空",
			"color_html": episode["theme"]["colors"]["muted"].to_html(false),
			"points": vacuum_points,
			"best": ProjectileSolver.best_point(vacuum_points),
		})
	if bool(scan.get("include_parameter_variant", false)):
		var high_ballistic_preset := base_preset.duplicate(true)
		high_ballistic_preset["physics"]["bird_mass_kg"] = (
			float(high_ballistic_preset["physics"]["bird_mass_kg"]) * 2.0
		)
		var high_ballistic_points := ProjectileSolver.scan_angles(
			high_ballistic_preset, tick_rate, duration, min_angle, max_angle, step
		)
		range_scans.append({
			"id": "higher-ballistic-coefficient",
			"label": "质量×2，同外形同速",
			"color_html": episode["theme"]["colors"]["highlight"].to_html(false),
			"points": high_ballistic_points,
			"best": ProjectileSolver.best_point(high_ballistic_points),
		})
	return {"range_scans": range_scans}


func _physics_process(delta: float) -> void:
	if not active or current_world == null:
		return
	var physics: Dictionary = current_variant["preset"]["physics"]
	var bird := current_world.bird
	var target := current_world.target

	if pending_collision:
		pending_collision = false
		var bird_after := ShotModel.velocity_px_to_mps(
			bird.linear_velocity, physics["pixels_per_meter"]
		)
		var target_after := ShotModel.velocity_px_to_mps(
			target.linear_velocity, physics["pixels_per_meter"]
		)
		var impulse := ShotModel.impulse(
			physics["bird_mass_kg"], pre_collision_bird_velocity, bird_after
		)
		current_metrics["impact_speed_mps"] = pre_collision_bird_velocity.length()
		current_metrics["impulse_ns"] = impulse.length()
		current_metrics["average_force_n"] = ShotModel.average_force(
			impulse, 1.0 / float(Engine.physics_ticks_per_second)
		)
		current_events.append({
			"type": "first_contact",
			"time_sec": elapsed_sec,
			"bird_velocity_before_mps": pre_collision_bird_velocity,
			"bird_velocity_after_mps": bird_after,
			"target_velocity_before_mps": pre_collision_target_velocity,
			"target_velocity_after_mps": target_after,
			"impulse_ns": impulse.length(),
		})
		target.release_to_gravity()

	elapsed_sec += delta
	_capture_frame()
	last_bird_velocity = ShotModel.velocity_px_to_mps(
		bird.linear_velocity, physics["pixels_per_meter"]
	)
	if elapsed_sec + 0.5 / float(Engine.physics_ticks_per_second) >= float(
		episode["simulation"]["duration_sec"]
	):
		_finish_variant()


func _start_next_variant() -> void:
	if transitioning:
		return
	variant_index += 1
	if variant_index >= episode["variants"].size():
		_finish_all()
		return
	transitioning = true
	current_variant = episode["variants"][variant_index]
	var preset: Dictionary = current_variant["preset"]
	var physics: Dictionary = preset["physics"]
	ProjectSettings.set_setting(
		"physics/2d/default_gravity",
		physics["gravity_mps2"] * physics["pixels_per_meter"]
	)

	current_world = SimulationWorld.new()
	current_world.name = "Simulation_%s" % current_variant["id"]
	add_child(current_world)
	current_world.configure(preset)
	current_world.bird.body_entered.connect(_on_bird_body_entered)

	current_frames = []
	current_events = [{"type": "launch", "time_sec": 0.0}]
	current_metrics = {
		"launch_speed_mps": 0.0,
		"spring_energy_j": ShotModel.spring_energy(
			physics["spring_k_npm"], physics["stretch_m"]
		),
		"max_height_m": 0.0,
		"range_m": 0.0,
		"flight_range_m": 0.0,
		"flight_time_sec": 0.0,
		"impact_speed_mps": 0.0,
		"impulse_ns": 0.0,
		"average_force_n": 0.0,
	}
	elapsed_sec = 0.0
	pending_collision = false
	last_bird_velocity = current_world.launch(preset)
	current_metrics["launch_speed_mps"] = last_bird_velocity.length()
	_capture_frame()
	active = true
	transitioning = false
	print("[episode:simulate] variant=%s" % current_variant["id"])


func _capture_frame() -> void:
	var preset: Dictionary = current_variant["preset"]
	var physics: Dictionary = preset["physics"]
	var scene: Dictionary = preset["scene"]
	var bird := current_world.bird
	var target := current_world.target
	var ppm: float = physics["pixels_per_meter"]
	var height_m := maxf(0.0, scene["ground_y_m"] - bird.position.y / ppm)
	var range_m := maxf(0.0, bird.position.x / ppm - scene["launch_position_m"].x)
	current_metrics["max_height_m"] = maxf(current_metrics["max_height_m"], height_m)
	current_metrics["range_m"] = maxf(current_metrics["range_m"], range_m)
	current_frames.append({
		"time_sec": elapsed_sec,
		"bird_position_px": bird.position,
		"bird_rotation": bird.rotation,
		"bird_velocity_px_s": bird.linear_velocity,
		"target_position_px": target.position,
		"target_rotation": target.rotation,
		"target_velocity_px_s": target.linear_velocity,
	})


func _on_bird_body_entered(body: Node) -> void:
	if body == current_world.ground and not _has_event("first_ground_contact"):
		var preset: Dictionary = current_variant["preset"]
		var ppm: float = preset["physics"]["pixels_per_meter"]
		current_metrics["flight_range_m"] = maxf(
			0.0,
			current_world.bird.position.x / ppm - preset["scene"]["launch_position_m"].x
		)
		current_metrics["flight_time_sec"] = elapsed_sec
		current_events.append({
			"type": "first_ground_contact",
			"time_sec": elapsed_sec,
			"range_m": current_metrics["flight_range_m"],
		})
		call_deferred("_freeze_landed_bird")
		return
	if pending_collision or body != current_world.target:
		return
	if _has_event("first_contact"):
		return
	var physics: Dictionary = current_variant["preset"]["physics"]
	pending_collision = true
	pre_collision_bird_velocity = last_bird_velocity
	pre_collision_target_velocity = ShotModel.velocity_px_to_mps(
		current_world.target.linear_velocity, physics["pixels_per_meter"]
	)


func _freeze_landed_bird() -> void:
	if current_world == null or not active:
		return
	current_world.bird.freeze = true
	current_world.bird.linear_velocity = Vector2.ZERO
	current_world.bird.angular_velocity = 0.0


func _has_event(event_type: String) -> bool:
	for event in current_events:
		if event.get("type") == event_type:
			return true
	return false


func _finish_variant() -> void:
	if not active:
		return
	active = false
	if not _has_event("first_ground_contact"):
		current_metrics["flight_range_m"] = current_metrics["range_m"]
		current_metrics["flight_time_sec"] = elapsed_sec
	var record := {
		"variant_id": current_variant["id"],
		"label": current_variant["label"],
		"color_html": current_variant["color_html"],
		"tick_rate": episode["simulation"]["tick_rate"],
		"duration_sec": episode["simulation"]["duration_sec"],
		"frames": current_frames,
		"events": current_events,
		"metrics": current_metrics,
	}
	records.append(record)
	print(
		"[episode:simulate] complete=%s range=%.3f max_height=%.3f"
		% [
			current_variant["id"],
			current_metrics["range_m"],
			current_metrics["max_height_m"],
		]
	)
	current_world.queue_free()
	current_world = null
	call_deferred("_start_next_variant")


func _finish_all() -> void:
	var bundle := RunRecord.make_bundle(episode, records)
	var result := RunRecord.write_json(output_path, bundle)
	if result != OK:
		push_error("failed to write run record: %s" % error_string(result))
		get_tree().quit(3)
		return
	print("[episode:simulate] record=%s variants=%d" % [output_path, records.size()])
	completed.emit(bundle)
	get_tree().quit(0)
