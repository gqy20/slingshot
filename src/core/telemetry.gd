class_name SlingshotTelemetry
extends RefCounted

const ShotModel = preload("res://src/core/shot_model.gd")

var pixels_per_meter := 100.0
var gravity_mps2 := 9.81
var bird_mass_kg := 1.0
var target_mass_kg := 3.0
var ground_y_m := 9.2
var launch_speed_mps := 0.0
var launch_angle_deg := 45.0
var spring_energy_j := 0.0
var snapshot: Dictionary = {}
var collision: Dictionary = {"detected": false}


func configure(preset: Dictionary) -> void:
	var physics: Dictionary = preset["physics"]
	var scene: Dictionary = preset["scene"]
	pixels_per_meter = physics["pixels_per_meter"]
	gravity_mps2 = physics["gravity_mps2"]
	bird_mass_kg = physics["bird_mass_kg"]
	target_mass_kg = physics["target_mass_kg"]
	ground_y_m = scene["ground_y_m"]
	launch_angle_deg = physics["launch_angle_deg"]
	spring_energy_j = ShotModel.spring_energy(physics["spring_k_npm"], physics["stretch_m"])
	launch_speed_mps = ShotModel.launch_speed(
		physics["spring_k_npm"],
		physics["stretch_m"],
		bird_mass_kg,
		physics["efficiency"]
	)
	collision = {"detected": false}
	snapshot = {
		"frame": 0,
		"elapsed_sec": 0.0,
		"bird_position_px": Vector2.ZERO,
		"velocity_px_s": Vector2.ZERO,
		"velocity_mps": Vector2.ZERO,
		"speed_mps": 0.0,
		"height_m": 0.0,
		"kinetic_energy_j": 0.0,
		"momentum_ns": 0.0,
		"spring_energy_j": spring_energy_j,
		"launch_speed_mps": launch_speed_mps,
		"launch_angle_deg": launch_angle_deg,
		"impulse_ns": 0.0,
		"average_force_n": 0.0,
		"collision_age_sec": -1.0,
		"collision": collision.duplicate(true),
	}


func update_live(
	bird_position_px: Vector2,
	velocity_px_s: Vector2,
	target_velocity_px_s: Vector2,
	frame_index: int,
	elapsed_sec: float
) -> void:
	var velocity_mps := ShotModel.velocity_px_to_mps(velocity_px_s, pixels_per_meter)
	var target_velocity_mps := ShotModel.velocity_px_to_mps(target_velocity_px_s, pixels_per_meter)
	var bird_position_m := ShotModel.pixels_to_meters(bird_position_px, pixels_per_meter)
	var momentum_vector := ShotModel.momentum(bird_mass_kg, velocity_mps)
	snapshot.merge({
		"frame": frame_index,
		"elapsed_sec": elapsed_sec,
		"bird_position_px": bird_position_px,
		"velocity_px_s": velocity_px_s,
		"velocity_mps": velocity_mps,
		"target_velocity_mps": target_velocity_mps,
		"speed_mps": velocity_mps.length(),
		"height_m": maxf(0.0, ground_y_m - bird_position_m.y),
		"kinetic_energy_j": ShotModel.kinetic_energy(bird_mass_kg, velocity_mps),
		"momentum_ns": momentum_vector.length(),
		"collision": collision.duplicate(true),
	}, true)
	if collision["detected"]:
		snapshot["collision_age_sec"] = maxf(0.0, elapsed_sec - collision["time_sec"])


func record_collision(
	before_mps: Vector2,
	after_mps: Vector2,
	target_before_mps: Vector2,
	target_after_mps: Vector2,
	sample_dt_sec: float,
	time_sec: float
) -> void:
	if collision["detected"]:
		return
	var impulse_vector := ShotModel.impulse(bird_mass_kg, before_mps, after_mps)
	var target_impulse_vector := ShotModel.impulse(
		target_mass_kg, target_before_mps, target_after_mps
	)
	collision = {
		"detected": true,
		"time_sec": time_sec,
		"sample_dt_sec": sample_dt_sec,
		"bird_velocity_before_mps": before_mps,
		"bird_velocity_after_mps": after_mps,
		"target_velocity_before_mps": target_before_mps,
		"target_velocity_after_mps": target_after_mps,
		"bird_impulse_vector_ns": impulse_vector,
		"target_impulse_vector_ns": target_impulse_vector,
		"impulse_ns": impulse_vector.length(),
		"average_force_n": ShotModel.average_force(impulse_vector, sample_dt_sec),
	}
	snapshot["collision"] = collision.duplicate(true)
	snapshot["impulse_ns"] = collision["impulse_ns"]
	snapshot["average_force_n"] = collision["average_force_n"]
	snapshot["collision_age_sec"] = 0.0


func get_snapshot() -> Dictionary:
	return snapshot.duplicate(true)


func write_sidecar(path: String, preset_id: String, duration_sec: float) -> Error:
	if path.is_empty():
		return OK
	var absolute_path := path
	if path.begins_with("res://") or path.begins_with("user://"):
		absolute_path = ProjectSettings.globalize_path(path)
	var parent := absolute_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(parent)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var output := {
		"preset_id": preset_id,
		"duration_sec": duration_sec,
		"frame_count": int(snapshot.get("frame", 0)) + 1,
		"launch_speed_mps": launch_speed_mps,
		"launch_angle_deg": launch_angle_deg,
		"spring_energy_j": spring_energy_j,
		"collision": collision,
		"final": snapshot,
	}
	file.store_string(JSON.stringify(_json_safe(output), "  "))
	file.close()
	return OK


static func _json_safe(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Dictionary:
		var dictionary := {}
		for key in value:
			dictionary[key] = _json_safe(value[key])
		return dictionary
	if value is Array:
		var array := []
		for item in value:
			array.append(_json_safe(item))
		return array
	return value
