class_name SlingshotWorldCanvas
extends Node2D

const VideoTypography = preload("res://src/video/video_typography.gd")

var trajectory_points := PackedVector2Array()
var last_snapshot: Dictionary = {}
var phase := "INTRO"
var pixels_per_meter := 100.0
var gravity_mps2 := 9.81
var ground_y_px := 920.0
var launch_position_px := Vector2(240, 760)
var target_position_px := Vector2(1320, 760)
var accent_color := Color("#F0B35A")
var trail := PackedVector2Array()
var label_font := VideoTypography.data()


func configure(preset: Dictionary) -> void:
	var physics: Dictionary = preset["physics"]
	var scene: Dictionary = preset["scene"]
	pixels_per_meter = physics["pixels_per_meter"]
	gravity_mps2 = physics["gravity_mps2"]
	ground_y_px = scene["ground_y_m"] * pixels_per_meter
	launch_position_px = scene["launch_position_m"] * pixels_per_meter
	target_position_px = scene["target_position_m"] * pixels_per_meter
	accent_color = scene["accent_color"]
	queue_redraw()


func set_trajectory(points: PackedVector2Array) -> void:
	trajectory_points = points
	queue_redraw()


func set_snapshot(snapshot: Dictionary) -> void:
	last_snapshot = snapshot.duplicate(true)
	if snapshot.has("bird_position_px") and phase in ["FLIGHT", "IMPACT", "AFTERMATH"]:
		var point: Vector2 = snapshot["bird_position_px"]
		if trail.is_empty() or trail[-1].distance_to(point) > 7.0:
			trail.append(point)
			if trail.size() > 110:
				trail.remove_at(0)
	queue_redraw()


func set_phase(value: String) -> void:
	phase = value
	if phase == "INTRO":
		trail.clear()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color("#0E1116"), true)
	draw_circle(Vector2(1650, 175), 92.0, Color("#F0B35A"))
	draw_circle(Vector2(1650, 175), 125.0, Color("#F0B35A", 0.08))
	_draw_cloud(Vector2(370, 160), 1.0)
	_draw_cloud(Vector2(940, 235), 0.72)
	draw_rect(Rect2(0, ground_y_px, 1920, 1080 - ground_y_px), Color("#23322E"), true)
	draw_line(Vector2(0, ground_y_px), Vector2(1920, ground_y_px), Color("#6E8A80"), 8.0)
	_draw_grid()
	_draw_sling()
	_draw_target_platform()
	_draw_trajectory()
	_draw_trail()
	_draw_vectors()
	_draw_impact()


func _draw_cloud(center: Vector2, scale_factor: float) -> void:
	var color := Color("#9AA4B2", 0.10)
	draw_circle(center + Vector2(-50, 8) * scale_factor, 40.0 * scale_factor, color)
	draw_circle(center, 54.0 * scale_factor, color)
	draw_circle(center + Vector2(55, 10) * scale_factor, 35.0 * scale_factor, color)


func _draw_grid() -> void:
	var grid_color := Color("#2D3642", 0.34)
	for x in range(0, 1921, 100):
		draw_line(Vector2(x, 0), Vector2(x, ground_y_px), grid_color, 1.0)
	for y in range(20, int(ground_y_px), 100):
		draw_line(Vector2(0, y), Vector2(1920, y), grid_color, 1.0)


func _draw_sling() -> void:
	var base := launch_position_px + Vector2(-48, 105)
	draw_line(base + Vector2(-35, 70), base + Vector2(-15, -35), Color("#8C5A36"), 24.0, true)
	draw_line(base + Vector2(35, 70), base + Vector2(15, -35), Color("#8C5A36"), 24.0, true)
	draw_line(base + Vector2(-15, -35), launch_position_px, Color("#432832"), 9.0, true)
	draw_line(base + Vector2(15, -35), launch_position_px, Color("#432832"), 9.0, true)
	draw_rect(Rect2(base.x - 50, base.y + 65, 100, 24), Color("#68422D"), true)


func _draw_target_platform() -> void:
	var top := target_position_px.y + 75.0
	draw_rect(Rect2(target_position_px.x - 95, top, 190, ground_y_px - top), Color("#23322E"), true)
	draw_rect(Rect2(target_position_px.x - 110, top - 12, 220, 20), Color("#6E8A80"), true)


func _draw_trajectory() -> void:
	if phase not in ["INTRO", "AIM"]:
		return
	for index in range(0, trajectory_points.size(), 2):
		var alpha := 0.25 + 0.65 * float(index) / maxf(1.0, trajectory_points.size())
		draw_circle(trajectory_points[index], 5.0, Color(accent_color, alpha))


func _draw_trail() -> void:
	if trail.size() < 2:
		return
	for index in range(1, trail.size()):
		var alpha := float(index) / trail.size() * 0.45
		draw_line(trail[index - 1], trail[index], Color(accent_color, alpha), 5.0, true)


func _draw_vectors() -> void:
	if phase not in ["FLIGHT", "IMPACT", "AFTERMATH"] or not last_snapshot.has("bird_position_px"):
		return
	var origin: Vector2 = last_snapshot["bird_position_px"]
	var velocity: Vector2 = last_snapshot.get("velocity_px_s", Vector2.ZERO)
	_draw_arrow(origin, origin + velocity * 0.16, accent_color, "v")
	_draw_arrow(origin, origin + Vector2(0, gravity_mps2 * 16.0), Color("#F0B35A"), "g")


func _draw_arrow(start: Vector2, finish: Vector2, color: Color, label: String) -> void:
	var vector := finish - start
	if vector.length() < 1.0:
		return
	var direction := vector.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	draw_line(start, finish, color, 6.0, true)
	draw_colored_polygon(
		PackedVector2Array([
			finish,
			finish - direction * 22.0 + perpendicular * 11.0,
			finish - direction * 22.0 - perpendicular * 11.0,
		]),
		color
	)
	draw_string(label_font, finish + Vector2(10, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, color)


func _draw_impact() -> void:
	var age := float(last_snapshot.get("collision_age_sec", -1.0))
	if age < 0.0 or age > 1.2:
		return
	var radius := 45.0 + age * 210.0
	var alpha := 1.0 - age / 1.2
	draw_arc(target_position_px, radius, 0.0, TAU, 64, Color("#F0B35A", alpha), 10.0, true)
