class_name SlingshotHud
extends CanvasLayer

const VideoTypography = preload("res://src/video/video_typography.gd")

var last_snapshot: Dictionary = {}
var phase := "INTRO"
var accent_color := Color("#35C2FF")
var phase_label: Label
var info_label: Label
var formula_label: Label
var summary_panel: ColorRect
var summary_label: Label
var system_font: Font


func _ready() -> void:
	_build_ui()


func configure(color: Color) -> void:
	accent_color = color
	if phase_label != null:
		phase_label.add_theme_color_override("font_color", accent_color)


func set_phase(value: String) -> void:
	phase = value
	_refresh()


func set_snapshot(snapshot: Dictionary) -> void:
	last_snapshot = snapshot.duplicate(true)
	_refresh()


func _build_ui() -> void:
	system_font = VideoTypography.regular()

	var top_band := ColorRect.new()
	top_band.position = Vector2(44, 38)
	top_band.size = Vector2(620, 84)
	top_band.color = Color(0.035, 0.055, 0.1, 0.9)
	add_child(top_band)
	phase_label = _label(Vector2(70, 53), Vector2(570, 55), 34, accent_color)
	add_child(phase_label)

	var info_panel := ColorRect.new()
	info_panel.position = Vector2(1490, 270)
	info_panel.size = Vector2(380, 470)
	info_panel.color = Color(0.035, 0.055, 0.1, 0.88)
	add_child(info_panel)
	info_label = _label(Vector2(1530, 300), Vector2(310, 410), 25, Color("#EAF4FF"))
	add_child(info_label)

	var formula_band := ColorRect.new()
	formula_band.position = Vector2(44, 958)
	formula_band.size = Vector2(1828, 82)
	formula_band.color = Color(0.035, 0.055, 0.1, 0.92)
	add_child(formula_band)
	formula_label = _label(Vector2(80, 978), Vector2(1760, 50), 27, Color("#C9D7EA"))
	formula_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(formula_label)

	summary_panel = ColorRect.new()
	summary_panel.position = Vector2(470, 245)
	summary_panel.size = Vector2(980, 530)
	summary_panel.color = Color(0.035, 0.055, 0.1, 0.96)
	add_child(summary_panel)
	summary_label = _label(Vector2(540, 305), Vector2(840, 410), 34, Color.WHITE)
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(summary_label)
	_refresh()


func _label(position_value: Vector2, size_value: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.theme = VideoTypography.theme()
	label.add_theme_font_override("font", system_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _refresh() -> void:
	if phase_label == null:
		return
	phase_label.text = _phase_title()
	var speed := float(last_snapshot.get("speed_mps", 0.0))
	var height := float(last_snapshot.get("height_m", 0.0))
	var energy := float(last_snapshot.get("kinetic_energy_j", 0.0))
	var momentum := float(last_snapshot.get("momentum_ns", 0.0))
	var impulse := float(last_snapshot.get("impulse_ns", 0.0))
	var force := float(last_snapshot.get("average_force_n", 0.0))
	info_label.text = (
		"实时测量\n\n速度       %6.2f m/s\n高度       %6.2f m\n动能       %6.2f J\n动量       %6.2f N·s\n\n碰撞冲量   %6.2f N·s\n平均力估计 %6.2f N"
		% [speed, height, energy, momentum, impulse, force]
	)
	formula_label.text = _formula_text()
	var summary_visible := phase == "SUMMARY"
	summary_panel.visible = summary_visible
	summary_label.visible = summary_visible
	if summary_visible:
		summary_label.text = (
			"实验结果\n\n初速度  %.2f m/s    发射角  %.1f°\n碰撞冲量  %.2f N·s\n平均力估计  %.2f N\n\n能量并未消失，而是转化为运动、旋转、形变、声音和热。"
			% [
				float(last_snapshot.get("launch_speed_mps", 0.0)),
				float(last_snapshot.get("launch_angle_deg", 0.0)),
				impulse,
				force,
			]
		)


func _phase_title() -> String:
	match phase:
		"INTRO": return "01  建立实验条件"
		"AIM": return "02  弹性势能 → 发射动能"
		"FLIGHT": return "03  抛体运动"
		"IMPACT": return "04  碰撞与冲量（慢动作）"
		"AFTERMATH": return "05  动量与能量转移"
		"SUMMARY": return "06  实验总结"
	return phase


func _formula_text() -> String:
	match phase:
		"INTRO": return "比例尺 100 px = 1 m       重力加速度 g = 9.81 m/s²"
		"AIM": return "Eₛ = ½kx²       ½mv² = ηEₛ       v₀ = x√(ηk/m)"
		"FLIGHT": return "x(t)=x₀+vₓt       y(t)=y₀+vᵧt+½gt²       Eₖ=½mv²"
		"IMPACT": return "J = Δp = m(v₂-v₁)       F平均 ≈ |J|/Δt"
		"AFTERMATH": return "平动 + 转动 + 形变 + 声音 + 热量 = 能量去向"
		"SUMMARY": return "可复现参数：质量、弹簧刚度、拉伸距离、效率、发射角"
	return ""
