class_name SlingshotBirdBody
extends RigidBody2D

const RADIUS_PX := 28.0

var body_color := Color("#E94F37")


func setup(position_px: Vector2, mass_kg: float, color: Color) -> void:
	position = position_px
	mass = mass_kg
	body_color = color
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	if get_node_or_null("CollisionShape2D") == null:
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = RADIUS_PX
		collision.shape = circle
		add_child(collision)
	queue_redraw()


func launch(velocity_px_s: Vector2) -> void:
	freeze = false
	sleeping = false
	linear_velocity = velocity_px_s


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS_PX, Color("#7D2430"))
	draw_circle(Vector2(-2, -2), RADIUS_PX - 3.0, body_color)
	draw_colored_polygon(
		PackedVector2Array([Vector2(-22, 8), Vector2(-45, -4), Vector2(-28, 20)]),
		Color("#B92F3A")
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(-21, -8), Vector2(-42, -25), Vector2(-30, 1)]),
		Color("#D83D38")
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(22, -2), Vector2(48, 7), Vector2(22, 13)]),
		Color("#F6B73C")
	)
	draw_circle(Vector2(10, -11), 10.0, Color.WHITE)
	draw_circle(Vector2(14, -10), 4.0, Color("#182238"))
	draw_circle(Vector2(-9, 7), 13.0, body_color.darkened(0.14))
	draw_line(Vector2(1, -22), Vector2(21, -16), Color("#52212C"), 5.0, true)
