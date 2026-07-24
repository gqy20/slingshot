extends RefCounted

const ShotCamera = preload("res://src/video/shot_camera.gd")
const TrajectoryAnnotation = preload("res://src/video/trajectory_annotation.gd")
const EpisodeLoader = preload("res://src/core/episode_loader.gd")
const EpisodeCanvas = preload("res://src/video/episode_canvas.gd")


func run(t) -> void:
	var anchor := Vector2(800.0, 500.0)
	var previous := ShotCamera.desired_state(
		"QUESTION",
		{"shot": "controls", "mode": "measurement"},
		anchor
	)
	var current := ShotCamera.desired_state(
		"FLIGHT",
		{"shot": "follow", "mode": "immersive"},
		anchor
	)
	var at_cut := ShotCamera.interpolate(previous, current, 0.0)
	var after_transition := ShotCamera.interpolate(previous, current, 1.0)
	t.check_close(at_cut["scale"], previous["scale"], 0.0001, "camera preserves prior scale at a cut")
	t.check_close(after_transition["scale"], current["scale"], 0.0001, "camera reaches the requested shot scale")
	t.check(
		Vector2(at_cut["offset"]).distance_to(previous["offset"]) < 0.001,
		"camera preserves prior framing at a cut"
	)
	t.check(
		Vector2(after_transition["offset"]).distance_to(current["offset"]) < 0.001,
		"camera reaches the requested shot framing"
	)
	var first_frame := ShotCamera.interpolate(
		previous,
		current,
		(1.0 / 30.0) / ShotCamera.TRANSITION_DURATION_SEC
	)
	t.check(
		absf(float(first_frame["scale"]) - float(previous["scale"]))
		< absf(float(current["scale"]) - float(previous["scale"])) * 0.02,
		"camera begins smoothly instead of jumping to the next scale"
	)
	t.check(
		ShotCamera.map_point(current, anchor).distance_to(Vector2(1030.0, 500.0)) < 0.001,
		"follow shot keeps its subject on the intended screen anchor"
	)
	t.check(
		ShotCamera.zoom_for_shot("follow") > ShotCamera.zoom_for_shot("ranking"),
		"follow shot is tighter than the full ranking view"
	)

	var record := {
		"tick_rate": 10,
		"duration_sec": 1.0,
		"frames": [
			{
				"bird_position_px": [100.0, 200.0],
				"bird_rotation": 0.0,
				"bird_velocity_px_s": [100.0, -100.0],
				"target_position_px": [0.0, 0.0],
				"target_rotation": 0.0,
				"target_velocity_px_s": [0.0, 0.0],
			},
			{
				"bird_position_px": [110.0, 190.0],
				"bird_rotation": 0.0,
				"bird_velocity_px_s": [100.0, -90.0],
				"target_position_px": [0.0, 0.0],
				"target_rotation": 0.0,
				"target_velocity_px_s": [0.0, 0.0],
			},
		],
		"events": [{"type": "first_ground_contact", "time_sec": 0.85}],
		"metrics": {"flight_time_sec": 0.85},
	}
	var geometry := TrajectoryAnnotation.initial_geometry(record)
	t.check(geometry["origin"] == Vector2(100.0, 200.0), "annotation begins at the replay launch point")
	t.check_close(geometry["angle_deg"], 45.0, 0.0001, "annotation angle comes from replay velocity")
	t.check(
		TrajectoryAnnotation.trajectory_alignment(record) > 0.999,
		"annotation vector aligns with the first real trajectory segment"
	)
	t.check_close(
		TrajectoryAnnotation.flight_time_sec(record),
		0.85,
		0.0001,
		"annotation time comes from the recorded landing event"
	)

	var loaded := EpisodeLoader.load_path("res://content/episodes/s01e01-angle-sweep.json")
	t.check(loaded["ok"], "camera hold fixture episode loads")
	if loaded["ok"]:
		var canvas := EpisodeCanvas.new()
		canvas.episode = loaded["episode"]
		var beats: Array = canvas.episode["beats"]
		t.check(
			canvas._camera_basis_beat(beats[1])["id"] == "cold-open",
			"copy-only question beat holds the established camera"
		)
		t.check(
			canvas._camera_basis_beat(beats[2])["id"] == "cold-open",
			"question wording change does not trigger another camera move"
		)
		t.check(
			canvas._camera_basis_beat(beats[4])["id"] == "distance-model",
			"formula detail change holds the explanatory camera"
		)
		t.check(
			canvas._visual_sequence_basis(beats[2])["id"] == "cold-open",
			"copy-only question beats retain the established visual subjects"
		)
		canvas.current_beat = beats[0]
		canvas.video_time_sec = 4.9
		var before_copy_change := canvas._visual_sequence_progress()
		canvas.current_beat = beats[1]
		canvas.video_time_sec = 5.1
		var after_copy_change := canvas._visual_sequence_progress()
		t.check(
			after_copy_change > before_copy_change,
			"subject animation continues instead of restarting when copy changes"
		)
		t.check_close(
			after_copy_change - before_copy_change,
			0.2 / 15.0,
			0.0001,
			"copy boundary preserves continuous visual time"
		)
		canvas.free()
