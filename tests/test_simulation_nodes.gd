extends RefCounted

const BirdBody = preload("res://src/simulation/bird_body.gd")
const TargetBody = preload("res://src/simulation/target_body.gd")


func run(t) -> void:
	var host := Node2D.new()
	t.root.add_child(host)

	var bird := BirdBody.new()
	host.add_child(bird)
	bird.setup(Vector2(240, 760), 1.0, Color("#E94F37"))
	t.check(bird.mass == 1.0, "simulation bird mass configured")
	t.check(bird.freeze, "simulation bird starts frozen")
	t.check(bird.contact_monitor, "simulation bird contact monitoring enabled")
	t.check(bird.max_contacts_reported >= 4, "simulation bird reports contacts")
	t.check(_collision_shape_count(bird) == 1, "simulation bird owns one collision shape")
	bird.launch(Vector2(700, -400))
	t.check(not bird.freeze and bird.linear_velocity == Vector2(700, -400), "simulation bird launches")

	var target := TargetBody.new()
	host.add_child(target)
	target.setup(Vector2(1320, 760), 3.0, Color("#73C66A"))
	t.check(target.mass == 3.0, "simulation target mass configured")
	t.check(target.freeze, "simulation target starts frozen")
	t.check(_collision_shape_count(target) == 1, "simulation target owns one collision shape")
	target.activate()
	t.check(not target.freeze and target.gravity_scale == 0.0, "simulation target activates without gravity")
	target.release_to_gravity()
	t.check(target.gravity_scale == 1.0, "simulation target returns to gravity after contact")

	host.free()


func _collision_shape_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is CollisionShape2D:
			count += 1
	return count
