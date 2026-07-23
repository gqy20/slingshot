class_name SlingshotFormulaRenderer
extends Control

const VideoTypography = preload("res://src/video/video_typography.gd")

var explanation: Dictionary = {}
var colors: Dictionary = {}
var step_index := -1
var eyebrow_label: Label
var formula_label: Label
var caption_label: Label
var assumptions_label: Label


func _ready() -> void:
	_build_ui()


func configure(value: Dictionary, theme_colors: Dictionary) -> void:
	explanation = value
	colors = theme_colors
	if not is_instance_valid(formula_label):
		_build_ui()
	eyebrow_label.add_theme_color_override("font_color", colors["accent"])
	formula_label.add_theme_color_override("font_color", colors["text"])
	caption_label.add_theme_color_override("font_color", colors["text"])
	assumptions_label.add_theme_color_override("font_color", colors["muted"])
	eyebrow_label.text = String(explanation.get("eyebrow", ""))
	var assumptions: Array = explanation.get("assumptions", [])
	assumptions_label.text = "条件  ·  %s" % "  /  ".join(assumptions)
	set_step(0)


func set_step(value: int) -> void:
	var steps: Array = explanation.get("steps", [])
	if steps.is_empty():
		step_index = -1
		formula_label.text = ""
		caption_label.text = ""
		queue_redraw()
		return
	step_index = clampi(value, 0, steps.size() - 1)
	var step: Dictionary = steps[step_index]
	formula_label.text = String(step.get("equation", ""))
	caption_label.text = String(step.get("caption", ""))
	queue_redraw()


func _build_ui() -> void:
	if is_instance_valid(formula_label):
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	eyebrow_label = _label(Vector2(40, 24), Vector2(900, 30), VideoTypography.FORMULA_META)
	add_child(eyebrow_label)
	formula_label = _label(Vector2(40, 78), Vector2(900, 88), VideoTypography.FORMULA_MAIN)
	formula_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	formula_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(formula_label)
	caption_label = _label(Vector2(80, 184), Vector2(820, 80), VideoTypography.FORMULA_STEP)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(caption_label)
	assumptions_label = _label(Vector2(52, 328), Vector2(876, 38), VideoTypography.FORMULA_META)
	assumptions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	assumptions_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(assumptions_label)


func _draw() -> void:
	if explanation.is_empty() or colors.is_empty():
		return
	var steps: Array = explanation.get("steps", [])
	if steps.is_empty():
		return
	var line_y := 302.0
	var start_x := 315.0
	var finish_x := 665.0
	draw_line(Vector2(start_x, line_y), Vector2(finish_x, line_y), colors["divider"], 2.0, true)
	for index in range(steps.size()):
		var progress := 0.5 if steps.size() == 1 else float(index) / float(steps.size() - 1)
		var point := Vector2(lerpf(start_x, finish_x, progress), line_y)
		var active := index <= step_index
		draw_circle(point, 10.0 if index == step_index else 7.0, colors["accent"] if active else colors["divider"])
		if index < steps.size() - 1 and index < step_index:
			var next_progress := float(index + 1) / float(steps.size() - 1)
			draw_line(point, Vector2(lerpf(start_x, finish_x, next_progress), line_y), colors["accent"], 3.0, true)


func _label(position_value: Vector2, size_value: Vector2, role: StringName) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	VideoTypography.apply_role(label, role)
	return label
