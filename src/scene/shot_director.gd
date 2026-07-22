class_name SlingshotShotDirector
extends Node

signal phase_changed(phase: String)

const ShotModel = preload("res://src/core/shot_model.gd")

var preset: Dictionary = {}
var dependencies: Dictionary = {}
var current_phase := "INTRO"
var elapsed_sec := 0.0
var frame_index := 0
var launched := false
var running := false
var collision_time := -1.0
var _pending_collision := false
var _pre_collision_bird_velocity := Vector2.ZERO
var _pre_collision_target_velocity := Vector2.ZERO
var _last_bird_velocity := Vector2.ZERO
var _normal_time_scale := 1.0


static func phase_for_time(time_sec: float, duration_sec: float, impact_time_sec: float) -> String:
	if time_sec >= maxf(0.0, duration_sec - 1.0):
		return "SUMMARY"
	if impact_time_sec >= 0.0 and time_sec >= impact_time_sec:
		return "IMPACT" if time_sec - impact_time_sec < 1.4 else "AFTERMATH"
	if time_sec < 2.0:
		return "INTRO"
	if time_sec < 3.5:
		return "AIM"
	return "FLIGHT"


func configure(normalized_preset: Dictionary, runtime_dependencies: Dictionary) -> void:
	preset = normalized_preset
	dependencies = runtime_dependencies
	_normal_time_scale = Engine.time_scale
	elapsed_sec = 0.0
	frame_index = 0
	launched = false
	running = true
	current_phase = phase_for_time(0.0, preset["duration_sec"], -1.0)
	var bird: RigidBody2D = dependencies["bird"]
	if not bird.body_entered.is_connected(_on_bird_body_entered):
		bird.body_entered.connect(_on_bird_body_entered)
	_apply_phase(current_phase)


func advance_for_test(time_sec: float, impact_time_sec: float = -1.0) -> String:
	return phase_for_time(time_sec, float(preset.get("duration_sec", 12.0)), impact_time_sec)


func _process(_delta: float) -> void:
	if not running:
		return
	var fps := float(preset["video"]["fps"])
	elapsed_sec = float(frame_index) / fps
	var telemetry = dependencies["telemetry"]
	var bird: RigidBody2D = dependencies["bird"]
	var target: RigidBody2D = dependencies["target"]
	telemetry.update_live(bird.position, bird.linear_velocity, target.linear_velocity, frame_index, elapsed_sec)
	var snapshot: Dictionary = telemetry.get_snapshot()
	dependencies["world"].set_snapshot(snapshot)
	dependencies["hud"].set_snapshot(snapshot)

	var next_phase := phase_for_time(elapsed_sec, preset["duration_sec"], collision_time)
	if next_phase != current_phase:
		current_phase = next_phase
		_apply_phase(current_phase)

	if not launched and elapsed_sec >= 3.5 and preset["duration_sec"] > 3.5:
		_launch()

	frame_index += 1
	if elapsed_sec + 1.0 / fps >= preset["duration_sec"]:
		_finish()


func _physics_process(_delta: float) -> void:
	if not running or not launched:
		return
	var physics: Dictionary = preset["physics"]
	var bird: RigidBody2D = dependencies["bird"]
	var target: RigidBody2D = dependencies["target"]
	if _pending_collision:
		_pending_collision = false
		var telemetry = dependencies["telemetry"]
		telemetry.record_collision(
			_pre_collision_bird_velocity,
			ShotModel.velocity_px_to_mps(bird.linear_velocity, physics["pixels_per_meter"]),
			_pre_collision_target_velocity,
			ShotModel.velocity_px_to_mps(target.linear_velocity, physics["pixels_per_meter"]),
			1.0 / float(Engine.physics_ticks_per_second),
			collision_time
		)
		target.release_to_gravity()
		dependencies["camera"].trigger_impact(int(preset["seed"]))
		Engine.time_scale = 0.35
	_last_bird_velocity = ShotModel.velocity_px_to_mps(
		bird.linear_velocity, physics["pixels_per_meter"]
	)


func _launch() -> void:
	launched = true
	var physics: Dictionary = preset["physics"]
	var speed := ShotModel.launch_speed(
		physics["spring_k_npm"],
		physics["stretch_m"],
		physics["bird_mass_kg"],
		physics["efficiency"]
	)
	var velocity_mps := ShotModel.launch_velocity(speed, physics["launch_angle_deg"])
	dependencies["target"].activate()
	dependencies["bird"].launch(velocity_mps * physics["pixels_per_meter"])
	_last_bird_velocity = velocity_mps


func _on_bird_body_entered(body: Node) -> void:
	if _pending_collision or collision_time >= 0.0 or body != dependencies.get("target"):
		return
	var physics: Dictionary = preset["physics"]
	var target: RigidBody2D = dependencies["target"]
	collision_time = elapsed_sec
	_pre_collision_bird_velocity = _last_bird_velocity
	_pre_collision_target_velocity = ShotModel.velocity_px_to_mps(
		target.linear_velocity, physics["pixels_per_meter"]
	)
	_pending_collision = true


func _apply_phase(value: String) -> void:
	dependencies["world"].set_phase(value)
	dependencies["hud"].set_phase(value)
	if value != "IMPACT":
		Engine.time_scale = _normal_time_scale
	phase_changed.emit(value)


func _finish() -> void:
	running = false
	Engine.time_scale = _normal_time_scale
	var sidecar_path: String = dependencies.get("sidecar_path", "")
	var result: Error = dependencies["telemetry"].write_sidecar(
		sidecar_path, preset["id"], preset["duration_sec"]
	)
	if result != OK:
		push_error("failed to write sidecar: %s" % error_string(result))
	get_tree().quit(0 if result == OK else 3)
