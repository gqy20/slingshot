class_name SlingshotExperimentRunner
extends Node

signal completed(bundle: Dictionary)

const SimulationWorld = preload("res://src/simulation/simulation_world.gd")
const RunRecord = preload("res://src/core/run_record.gd")
const ShotModel = preload("res://src/core/shot_model.gd")

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
	variant_index = -1
	_start_next_variant()


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
	if pending_collision or body != current_world.target:
		return
	for event in current_events:
		if event.get("type") == "first_contact":
			return
	var physics: Dictionary = current_variant["preset"]["physics"]
	pending_collision = true
	pre_collision_bird_velocity = last_bird_velocity
	pre_collision_target_velocity = ShotModel.velocity_px_to_mps(
		current_world.target.linear_velocity, physics["pixels_per_meter"]
	)


func _finish_variant() -> void:
	if not active:
		return
	active = false
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
