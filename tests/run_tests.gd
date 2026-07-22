extends SceneTree

const TEST_CASES := [
	preload("res://tests/test_shot_model.gd"),
	preload("res://tests/test_preset_loader.gd"),
	preload("res://tests/test_visual_nodes.gd"),
	preload("res://tests/test_director.gd"),
]

var passed := 0
var failed := 0


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + message)


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(
		absf(actual - expected) <= tolerance,
		"%s (actual=%f expected=%f)" % [message, actual, expected]
	)


func _initialize() -> void:
	check(FileAccess.file_exists("res://project.godot"), "project.godot exists")
	check(FileAccess.file_exists("res://main.tscn"), "main scene exists")
	for test_case in TEST_CASES:
		test_case.new().run(self)
	print("TESTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
