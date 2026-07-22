extends RefCounted

const ShotModel = preload("res://src/core/shot_model.gd")


func run(t) -> void:
	t.check_close(ShotModel.spring_energy(160.0, 0.9), 64.8, 0.0001, "spring energy")
	var speed := ShotModel.launch_speed(160.0, 0.9, 1.0, 0.82)
	t.check_close(speed, 10.3088, 0.0002, "launch speed")
	var velocity := ShotModel.launch_velocity(speed, 45.0)
	t.check_close(velocity.x, 7.2894, 0.0002, "horizontal velocity")
	t.check_close(velocity.y, -7.2894, 0.0002, "vertical velocity")
	var position := ShotModel.projectile_position(Vector2(2.4, 7.6), velocity, 9.81, 1.0)
	t.check_close(position.x, 9.6894, 0.0002, "projectile x")
	t.check_close(position.y, 5.2156, 0.0002, "projectile y")
	t.check_close(ShotModel.kinetic_energy(1.0, velocity), 53.136, 0.002, "kinetic energy")
	t.check_close(ShotModel.rotational_energy(2.0, 3.0), 9.0, 0.0001, "rotational energy")
	t.check(ShotModel.momentum(1.0, Vector2(3, 4)) == Vector2(3, 4), "momentum")
	t.check(
		ShotModel.impulse(1.0, Vector2(4, 0), Vector2(1, 0)) == Vector2(-3, 0),
		"impulse"
	)
	t.check_close(ShotModel.average_force(Vector2(3, 4), 0.01), 500.0, 0.001, "average force")
	t.check(
		ShotModel.meters_to_pixels(Vector2(2, 3), 100.0) == Vector2(200, 300),
		"meters to pixels"
	)
	t.check(
		ShotModel.pixels_to_meters(Vector2(200, 300), 100.0) == Vector2(2, 3),
		"pixels to meters"
	)
	t.check(
		ShotModel.velocity_px_to_mps(Vector2(700, -400), 100.0) == Vector2(7, -4),
		"velocity conversion"
	)
	t.check(is_nan(ShotModel.launch_speed(0.0, 1.0, 1.0, 1.0)), "invalid stiffness")
	t.check(is_nan(ShotModel.average_force(Vector2.ONE, 0.0)), "invalid sample interval")
