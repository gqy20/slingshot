extends RefCounted

const BirdBody = preload("res://src/scene/bird_body.gd")
const TargetBody = preload("res://src/scene/target_body.gd")
const WorldCanvas = preload("res://src/scene/world_canvas.gd")
const Hud = preload("res://src/scene/hud.gd")
const CameraRig = preload("res://src/scene/camera_rig.gd")


func run(t) -> void:
	var host := Node2D.new()
	t.root.add_child(host)

	var bird := BirdBody.new()
	host.add_child(bird)
	bird.setup(Vector2(240, 760), 1.0, Color("#E94F37"))
	t.check(bird.mass == 1.0, "bird mass configured")
	t.check(bird.freeze, "bird starts frozen")
	t.check(bird.contact_monitor, "bird contact monitoring enabled")
	t.check(bird.max_contacts_reported >= 4, "bird reports contacts")
	t.check(_collision_shape_count(bird) == 1, "bird owns one collision shape")
	bird.launch(Vector2(700, -400))
	t.check(not bird.freeze and bird.linear_velocity == Vector2(700, -400), "bird launches")

	var target := TargetBody.new()
	host.add_child(target)
	target.setup(Vector2(1320, 760), 3.0, Color("#73C66A"))
	t.check(target.mass == 3.0, "target mass configured")
	t.check(target.freeze, "target starts frozen")
	t.check(_collision_shape_count(target) == 1, "target owns one collision shape")

	var canvas := WorldCanvas.new()
	host.add_child(canvas)
	canvas.configure({
		"physics": {"pixels_per_meter": 100.0, "gravity_mps2": 9.81},
		"scene": {
			"ground_y_m": 9.2,
			"launch_position_m": Vector2(2.4, 7.6),
			"target_position_m": Vector2(13.2, 7.6),
			"accent_color": Color("#35C2FF"),
		},
	})
	canvas.set_trajectory(PackedVector2Array([Vector2(240, 760), Vector2(300, 700)]))
	canvas.set_snapshot({"bird_position_px": Vector2(240, 760), "velocity_px_s": Vector2.ZERO})
	t.check(canvas.trajectory_points.size() == 2, "world stores trajectory")

	var hud := Hud.new()
	host.add_child(hud)
	hud.configure(Color("#35C2FF"))
	hud.set_phase("INTRO")
	hud.set_snapshot({"speed_mps": 10.0, "kinetic_energy_j": 50.0})
	t.check(hud.last_snapshot["speed_mps"] == 10.0, "HUD accepts snapshot")

	var camera := CameraRig.new()
	host.add_child(camera)
	camera.trigger_impact(7)
	camera.reset_effects()
	t.check(camera.zoom == Vector2.ONE and camera.offset == Vector2.ZERO, "camera resets")

	host.free()


func _collision_shape_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is CollisionShape2D:
			count += 1
	return count
