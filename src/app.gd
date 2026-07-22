extends Node2D

const PresetLoader = preload("res://src/core/preset_loader.gd")
const ShotModel = preload("res://src/core/shot_model.gd")
const BirdBody = preload("res://src/scene/bird_body.gd")
const TargetBody = preload("res://src/scene/target_body.gd")
const WorldCanvas = preload("res://src/scene/world_canvas.gd")
const Hud = preload("res://src/scene/hud.gd")
const CameraRig = preload("res://src/scene/camera_rig.gd")
const Telemetry = preload("res://src/core/telemetry.gd")
const ShotDirector = preload("res://src/scene/shot_director.gd")

var _boot_frames := -1


func _ready() -> void:
	var args := _parse_user_args(OS.get_cmdline_user_args())
	var preset_path: String = args.get("preset", "res://presets/default.json")
	var loaded: Dictionary = PresetLoader.load_path(preset_path)
	if not loaded["ok"]:
		printerr("[app:error] %s" % loaded["error"])
		get_tree().quit(2)
		return
	for warning in loaded["warnings"]:
		print("[app:warning] %s" % warning)
	var preset: Dictionary = loaded["preset"]
	print("[app] preset=%s" % preset["id"])
	_configure_project(preset)
	var runtime := _build_runtime(preset, args.get("sidecar", ""))
	if args.get("boot_only", false):
		_boot_frames = 2
		return
	var director = ShotDirector.new()
	director.name = "ShotDirector"
	add_child(director)
	director.configure(preset, runtime)


func _process(_delta: float) -> void:
	if _boot_frames < 0:
		return
	_boot_frames -= 1
	if _boot_frames <= 0:
		get_tree().quit()


func _parse_user_args(argv: PackedStringArray) -> Dictionary:
	var result := {"preset": "res://presets/default.json", "sidecar": "", "boot_only": false}
	var index := 0
	while index < argv.size():
		match argv[index]:
			"--preset":
				if index + 1 < argv.size():
					result["preset"] = argv[index + 1]
					index += 1
			"--sidecar":
				if index + 1 < argv.size():
					result["sidecar"] = argv[index + 1]
					index += 1
			"--boot-only":
				result["boot_only"] = true
		index += 1
	return result


func _configure_project(preset: Dictionary) -> void:
	var physics: Dictionary = preset["physics"]
	ProjectSettings.set_setting(
		"physics/2d/default_gravity",
		physics["gravity_mps2"] * physics["pixels_per_meter"]
	)
	Engine.physics_ticks_per_second = 120


func _build_runtime(preset: Dictionary, sidecar_path: String) -> Dictionary:
	var physics: Dictionary = preset["physics"]
	var scene: Dictionary = preset["scene"]
	var pixels_per_meter: float = physics["pixels_per_meter"]

	var world = WorldCanvas.new()
	world.name = "WorldCanvas"
	add_child(world)
	world.configure(preset)
	world.set_trajectory(_trajectory_points(preset))

	var ground := StaticBody2D.new()
	ground.name = "Ground"
	ground.position = Vector2(960, scene["ground_y_m"] * pixels_per_meter + 100)
	var ground_collision := CollisionShape2D.new()
	var ground_shape := RectangleShape2D.new()
	ground_shape.size = Vector2(1920, 200)
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	add_child(ground)

	var bird = BirdBody.new()
	bird.name = "Bird"
	add_child(bird)
	bird.setup(
		scene["launch_position_m"] * pixels_per_meter,
		physics["bird_mass_kg"],
		scene["bird_color"]
	)

	var target = TargetBody.new()
	target.name = "Target"
	add_child(target)
	target.setup(
		scene["target_position_m"] * pixels_per_meter,
		physics["target_mass_kg"],
		scene["target_color"]
	)

	var camera = CameraRig.new()
	camera.name = "CameraRig"
	camera.enabled = true
	add_child(camera)

	var hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.configure(scene["accent_color"])

	var telemetry = Telemetry.new()
	telemetry.configure(preset)
	var initial_snapshot: Dictionary = telemetry.get_snapshot()
	initial_snapshot["bird_position_px"] = bird.position
	world.set_snapshot(initial_snapshot)
	hud.set_snapshot(initial_snapshot)

	return {
		"world": world,
		"bird": bird,
		"target": target,
		"camera": camera,
		"hud": hud,
		"telemetry": telemetry,
		"sidecar_path": sidecar_path,
	}


func _trajectory_points(preset: Dictionary) -> PackedVector2Array:
	var physics: Dictionary = preset["physics"]
	var scene: Dictionary = preset["scene"]
	var speed := ShotModel.launch_speed(
		physics["spring_k_npm"],
		physics["stretch_m"],
		physics["bird_mass_kg"],
		physics["efficiency"]
	)
	var velocity := ShotModel.launch_velocity(speed, physics["launch_angle_deg"])
	var points := PackedVector2Array()
	for sample_index in range(75):
		var time_sec := float(sample_index) * 0.035
		var position_m := ShotModel.projectile_position(
			scene["launch_position_m"], velocity, physics["gravity_mps2"], time_sec
		)
		if position_m.y > scene["ground_y_m"]:
			break
		points.append(position_m * physics["pixels_per_meter"])
	return points
