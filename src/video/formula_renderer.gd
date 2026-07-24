class_name SlingshotFormulaRenderer
extends Control

const VideoTypography = preload("res://src/video/video_typography.gd")

var explanation: Dictionary = {}
var colors: Dictionary = {}
var step_index := -1
var eyebrow_label: Label
var concept_label: Label
var formula_texture: TextureRect
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
	concept_label.add_theme_color_override("font_color", colors["text"])
	formula_label.add_theme_color_override("font_color", colors["text"])
	caption_label.add_theme_color_override("font_color", colors["text"])
	assumptions_label.add_theme_color_override("font_color", colors["muted"])
	eyebrow_label.text = String(explanation.get("eyebrow", ""))
	eyebrow_label.visible = not eyebrow_label.text.is_empty()
	var assumptions: Array = explanation.get("assumptions", [])
	assumptions_label.text = " · ".join(assumptions)
	set_step(0)


func set_step(value: int) -> void:
	var steps: Array = explanation.get("steps", [])
	if steps.is_empty():
		step_index = -1
		concept_label.text = ""
		formula_texture.texture = null
		formula_texture.visible = false
		formula_label.text = ""
		formula_label.visible = true
		caption_label.text = ""
		queue_redraw()
		return
	step_index = clampi(value, 0, steps.size() - 1)
	var step: Dictionary = steps[step_index]
	concept_label.text = String(step.get("concept", ""))
	formula_label.text = String(step.get("equation", ""))
	var formula_asset := String(step.get("formula_asset", ""))
	formula_texture.texture = null
	if not formula_asset.is_empty() and ResourceLoader.exists(formula_asset):
		formula_texture.texture = load(formula_asset) as Texture2D
	formula_texture.visible = formula_texture.texture != null
	formula_label.visible = not formula_texture.visible
	caption_label.text = String(step.get("caption", ""))
	assumptions_label.visible = step_index == steps.size() - 1
	queue_redraw()


func _build_ui() -> void:
	if is_instance_valid(formula_label):
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	eyebrow_label = _label(Vector2(40, 12), Vector2(900, 26), VideoTypography.FORMULA_META)
	add_child(eyebrow_label)
	concept_label = _label(Vector2(40, 42), Vector2(900, 54), VideoTypography.FORMULA_STEP)
	concept_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	concept_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(concept_label)
	formula_texture = TextureRect.new()
	formula_texture.position = Vector2(40, 112)
	formula_texture.size = Vector2(900, 110)
	formula_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	formula_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	formula_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	formula_texture.visible = false
	add_child(formula_texture)
	formula_label = _label(Vector2(40, 116), Vector2(900, 94), VideoTypography.FORMULA_MAIN)
	formula_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	formula_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(formula_label)
	caption_label = _label(Vector2(100, 244), Vector2(780, 56), VideoTypography.BODY)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(caption_label)
	assumptions_label = _label(Vector2(52, 332), Vector2(876, 34), VideoTypography.FORMULA_META)
	assumptions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	assumptions_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(assumptions_label)


func _draw() -> void:
	pass


func _label(position_value: Vector2, size_value: Vector2, role: StringName) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	VideoTypography.apply_role(label, role)
	return label
