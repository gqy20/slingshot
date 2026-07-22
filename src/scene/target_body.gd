class_name SlingshotTargetBody
extends RigidBody2D

const BODY_SIZE := Vector2(110, 150)

var body_color := Color("#73C66A")


func setup(position_px: Vector2, mass_kg: float, color: Color) -> void:
	position = position_px
	mass = mass_kg
	body_color = color
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	contact_monitor = true
	max_contacts_reported = 8
	if get_node_or_null("CollisionShape2D") == null:
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		var rectangle := RectangleShape2D.new()
		rectangle.size = BODY_SIZE
		collision.shape = rectangle
		add_child(collision)
	queue_redraw()


func activate() -> void:
	freeze = false
	gravity_scale = 0.0
	sleeping = false


func release_to_gravity() -> void:
	gravity_scale = 1.0


func _draw() -> void:
	var rect := Rect2(-BODY_SIZE * 0.5, BODY_SIZE)
	draw_rect(rect, Color("#284C35"), true)
	draw_rect(rect.grow(-6.0), body_color, true)
	draw_rect(Rect2(-45, -61, 90, 18), body_color.lightened(0.14), true)
	draw_line(Vector2(-42, -35), Vector2(42, 35), Color("#397B46"), 8.0, true)
	draw_line(Vector2(42, -35), Vector2(-42, 35), Color("#397B46"), 8.0, true)
	draw_circle(Vector2(0, -5), 29.0, Color("#F4EFE2"))
	draw_circle(Vector2.ZERO, 19.0, Color("#F5C451"))
	draw_circle(Vector2.ZERO, 9.0, Color("#E94F37"))
	draw_circle(Vector2(-22, -48), 6.0, Color("#152235"))
	draw_circle(Vector2(22, -48), 6.0, Color("#152235"))
