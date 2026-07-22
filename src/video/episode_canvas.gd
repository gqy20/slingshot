class_name SlingshotEpisodeCanvas
extends Node2D

const ReplayTrack = preload("res://src/playback/replay_track.gd")

var episode: Dictionary = {}
var bundle: Dictionary = {}
var analysis: Dictionary = {}
var phase := "QUESTION"
var simulation_times_by_id: Dictionary = {}
var states_by_id: Dictionary = {}
var records_by_id: Dictionary = {}
var colors_by_id: Dictionary = {}
var labels_by_id: Dictionary = {}
var trajectories_by_id: Dictionary = {}
var launch_position_px := Vector2(240, 760)
var target_position_px := Vector2(1320, 760)
var ground_y_px := 920.0
var video_time_sec := 0.0


func configure(
	normalized_episode: Dictionary,
	run_bundle: Dictionary,
	comparison: Dictionary
) -> void:
	episode = normalized_episode
	bundle = run_bundle
	analysis = comparison
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		colors_by_id[variant["id"]] = variant["color"]
		labels_by_id[variant["id"]] = variant["label"]
	for record_value in bundle["records"]:
		var record: Dictionary = record_value
		records_by_id[record["variant_id"]] = record
		trajectories_by_id[record["variant_id"]] = ReplayTrack.full_trajectory(record)
	var first_variant: Dictionary = episode["variants"][0]
	var preset: Dictionary = first_variant["preset"]
	var ppm: float = preset["physics"]["pixels_per_meter"]
	launch_position_px = preset["scene"]["launch_position_m"] * ppm
	target_position_px = preset["scene"]["target_position_m"] * ppm
	ground_y_px = preset["scene"]["ground_y_m"] * ppm
	queue_redraw()


func set_playback(
	value_phase: String,
	times: Dictionary,
	states: Dictionary,
	elapsed_video_sec: float = 0.0
) -> void:
	phase = value_phase
	simulation_times_by_id = times
	states_by_id = states
	video_time_sec = elapsed_video_sec
	queue_redraw()


func _draw() -> void:
	_draw_background()
	_draw_grid()
	_draw_sling()
	if episode["story"].get("show_target", true):
		_draw_target_platform()
		_draw_reference_target()
	_draw_trajectories()
	if phase in ["FLIGHT", "COMPARE"]:
		if episode["story"].get("show_target", true):
			_draw_variant_targets()
		_draw_variant_birds()


func _draw_background() -> void:
	var theme: Dictionary = episode["theme"]["colors"]
	draw_rect(Rect2(0, 0, 1920, 1080), theme["background"], true)
	draw_rect(Rect2(0, 90, 1920, 830), theme["stage"], true)
	for band in range(6):
		var alpha := 0.025 - float(band) * 0.003
		draw_circle(
			Vector2(1550, 220),
			130.0 + band * 50.0,
			Color(0.2, 0.75, 1.0, alpha)
		)
	draw_rect(
		Rect2(0, ground_y_px, 1920, maxf(0.0, 1080.0 - ground_y_px)),
		theme["ground"],
		true
	)
	draw_line(
		Vector2(0, ground_y_px),
		Vector2(1920, ground_y_px),
		theme["ground_line"],
		5.0,
		true
	)


func _draw_grid() -> void:
	var minor := Color(0.35, 0.72, 0.9, 0.055)
	var major := Color(0.35, 0.72, 0.9, 0.11)
	for x in range(0, 1921, 50):
		var color := major if x % 200 == 0 else minor
		draw_line(Vector2(x, 90), Vector2(x, ground_y_px), color, 1.0)
	for y in range(120, int(ground_y_px), 50):
		var color := major if y % 200 == 0 else minor
		draw_line(Vector2(0, y), Vector2(1920, y), color, 1.0)


func _draw_sling() -> void:
	var base := launch_position_px + Vector2(-46, 104)
	draw_line(base + Vector2(-34, 70), base + Vector2(-14, -34), Color("#8B5A3A"), 22.0, true)
	draw_line(base + Vector2(34, 70), base + Vector2(14, -34), Color("#8B5A3A"), 22.0, true)
	draw_line(base + Vector2(-14, -34), launch_position_px, Color("#3A2230"), 8.0, true)
	draw_line(base + Vector2(14, -34), launch_position_px, Color("#3A2230"), 8.0, true)
	draw_rect(Rect2(base.x - 48, base.y + 64, 96, 22), Color("#5B3928"), true)


func _draw_target_platform() -> void:
	var top := target_position_px.y + 75.0
	if top >= ground_y_px:
		return
	draw_rect(
		Rect2(target_position_px.x - 90, top, 180, ground_y_px - top),
		Color("#264B43"),
		true
	)
	draw_rect(Rect2(target_position_px.x - 105, top - 10, 210, 18), Color("#5A8E6D"), true)


func _draw_reference_target() -> void:
	_draw_target(target_position_px, 0.0, Color("#A7B7B2"), 0.42)


func _draw_trajectories() -> void:
	var variants: Array = episode.get("variants", [])
	for index in range(variants.size()):
		var variant: Dictionary = variants[index]
		var id: String = variant["id"]
		var color: Color = colors_by_id[id]
		var points: PackedVector2Array
		var alpha := 0.2
		var width := 3.0
		if phase in ["QUESTION", "EXPLAIN"]:
			continue
		elif phase == "SETUP":
			var full_points: PackedVector2Array = trajectories_by_id.get(
				id, PackedVector2Array()
			)
			var story: Dictionary = episode["story"]
			var setup_start := (
				float(story["question_sec"])
				+ float(story.get("explain_sec", 0.0))
			)
			var setup_progress := clampf(
				(video_time_sec - setup_start) / float(story["setup_sec"]),
				0.0,
				1.0
			)
			var reveal_progress := clampf(
				setup_progress * float(variants.size() + 1) - float(index),
				0.0,
				1.0
			)
			if reveal_progress <= 0.0:
				continue
			points = full_points.slice(
				0,
				maxi(2, int(full_points.size() * 0.16 * reveal_progress))
			)
			alpha = 0.52
		elif phase == "FLIGHT":
			points = ReplayTrack.partial_trajectory(
				records_by_id[id],
				float(simulation_times_by_id.get(id, 0.0))
			)
			alpha = 0.72
			width = 4.0
		else:
			points = trajectories_by_id.get(id, PackedVector2Array())
			alpha = 0.95 if id == analysis.get("winner_id") else 0.42
			width = 7.0 if id == analysis.get("winner_id") else 3.0
		if points.size() >= 2:
			draw_polyline(points, Color(color, alpha), width, true)
		if phase == "SETUP":
			for point_index in range(0, points.size(), 7):
				draw_circle(points[point_index], 4.0, Color(color, 0.72))


func _draw_variant_birds() -> void:
	for variant_value in episode.get("variants", []):
		var variant: Dictionary = variant_value
		var id: String = variant["id"]
		var state: Dictionary = states_by_id.get(id, {})
		if state.is_empty():
			continue
		var color: Color = colors_by_id[id]
		var winner: bool = phase == "COMPARE" and id == analysis.get("winner_id")
		_draw_bird(
			state["bird_position_px"],
			float(state["bird_rotation"]),
			color,
			1.0 if winner else 0.86,
			winner
		)
		if phase == "FLIGHT":
			_draw_velocity_vector(
				state["bird_position_px"],
				state["bird_velocity_px_s"],
				color
			)


func _draw_variant_targets() -> void:
	for variant_value in episode.get("variants", []):
		var variant: Dictionary = variant_value
		var id: String = variant["id"]
		var state: Dictionary = states_by_id.get(id, {})
		if state.is_empty():
			continue
		var position: Vector2 = state["target_position_px"]
		if position.distance_to(target_position_px) < 2.0:
			continue
		_draw_target(
			position,
			float(state["target_rotation"]),
			colors_by_id[id],
			0.28
		)


func _draw_bird(
	position: Vector2,
	rotation_value: float,
	color: Color,
	alpha: float,
	winner: bool
) -> void:
	if winner:
		draw_circle(position, 44.0, Color(color, 0.12))
		draw_arc(position, 39.0, 0.0, TAU, 48, Color(color, 0.75), 3.0, true)
	var direction := Vector2.RIGHT.rotated(rotation_value)
	var perpendicular := Vector2(-direction.y, direction.x)
	draw_circle(position, 24.0, Color("#07111F"))
	draw_circle(position - direction * 2.0, 21.0, Color(color, alpha))
	draw_colored_polygon(
		PackedVector2Array([
			position + direction * 22.0,
			position + direction * 42.0 + perpendicular * 7.0,
			position + direction * 22.0 + perpendicular * 12.0,
		]),
		Color("#FFD166", alpha)
	)
	draw_circle(position + direction * 7.0 - perpendicular * 8.0, 6.5, Color(1, 1, 1, alpha))
	draw_circle(position + direction * 9.0 - perpendicular * 8.0, 2.5, Color("#07111F"))


func _draw_target(position: Vector2, rotation_value: float, color: Color, alpha: float) -> void:
	var transform := Transform2D(rotation_value, position)
	var corners := PackedVector2Array([
		transform * Vector2(-55, -75),
		transform * Vector2(55, -75),
		transform * Vector2(55, 75),
		transform * Vector2(-55, 75),
	])
	draw_colored_polygon(corners, Color(color, alpha))
	draw_polyline(
		PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]),
		Color(color, minf(1.0, alpha + 0.25)),
		3.0,
		true
	)


func _draw_velocity_vector(position: Vector2, velocity: Vector2, color: Color) -> void:
	var finish := position + velocity * 0.075
	var vector := finish - position
	if vector.length() < 15.0:
		return
	var direction := vector.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	draw_line(position, finish, Color(color, 0.52), 3.0, true)
	draw_colored_polygon(
		PackedVector2Array([
			finish,
			finish - direction * 14.0 + perpendicular * 6.0,
			finish - direction * 14.0 - perpendicular * 6.0,
		]),
		Color(color, 0.52)
	)
