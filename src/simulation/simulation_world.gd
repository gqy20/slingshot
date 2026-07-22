class_name SlingshotSimulationWorld
extends Node2D

const BirdBody = preload("res://src/scene/bird_body.gd")
const TargetBody = preload("res://src/scene/target_body.gd")
const ShotModel = preload("res://src/core/shot_model.gd")

var bird: RigidBody2D
var target: RigidBody2D
var ground: StaticBody2D


func configure(preset: Dictionary) -> void:
	var physics: Dictionary = preset["physics"]
	var scene: Dictionary = preset["scene"]
	var pixels_per_meter: float = physics["pixels_per_meter"]

	ground = StaticBody2D.new()
	ground.name = "Ground"
	ground.position = Vector2(960, scene["ground_y_m"] * pixels_per_meter + 100)
	var ground_collision := CollisionShape2D.new()
	var ground_shape := RectangleShape2D.new()
	ground_shape.size = Vector2(1920, 200)
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	add_child(ground)

	bird = BirdBody.new()
	bird.name = "Bird"
	bird.setup(
		scene["launch_position_m"] * pixels_per_meter,
		physics["bird_mass_kg"],
		scene["bird_color"]
	)
	add_child(bird)

	target = TargetBody.new()
	target.name = "Target"
	target.setup(
		scene["target_position_m"] * pixels_per_meter,
		physics["target_mass_kg"],
		scene["target_color"]
	)
	add_child(target)


func launch(preset: Dictionary) -> Vector2:
	var physics: Dictionary = preset["physics"]
	var speed := ShotModel.launch_speed(
		physics["spring_k_npm"],
		physics["stretch_m"],
		physics["bird_mass_kg"],
		physics["efficiency"]
	)
	var velocity_mps := ShotModel.launch_velocity(speed, physics["launch_angle_deg"])
	target.activate()
	bird.launch(velocity_mps * physics["pixels_per_meter"])
	return velocity_mps
