class_name SlingshotEpisodeHud
extends CanvasLayer

const SubtitleTrack = preload("res://src/playback/subtitle_track.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")
const FormulaRenderer = preload("res://src/video/formula_renderer.gd")

var episode: Dictionary = {}
var analysis: Dictionary = {}
var subtitle_cues: Array = []
var phase := "QUESTION"
var current_beat: Dictionary = {}

var identity_panel: Panel
var identity_style: StyleBoxFlat
var identity_accent: ColorRect
var phase_panel: Panel
var phase_style: StyleBoxFlat
var phase_dot_label: Label
var explain_panel: Panel
var explain_style: StyleBoxFlat
var result_panel: Panel
var result_style: StyleBoxFlat
var result_divider: ColorRect
var subtitle_panel: Panel
var subtitle_style: StyleBoxFlat
var legend_chips: Array[Panel] = []
var legend_styles: Array[StyleBoxFlat] = []
var legend_labels: Array[Label] = []
var legend_swatches: Array[ColorRect] = []
var result_rows: Array[Label] = []
var result_swatches: Array[ColorRect] = []

var title_label: Label
var tag_label: Label
var phase_label: Label
var question_label: Label
var explain_title_label: Label
var explain_detail_label: Label
var formula_renderer: Control
var clock_label: Label
var result_title: Label
var result_callout_label: Label
var conclusion_label: Label
var subtitle_label: Label


func _ready() -> void:
	_build_ui()


func configure(
	normalized_episode: Dictionary,
	comparison: Dictionary,
	cues: Array = []
) -> void:
	episode = normalized_episode
	analysis = comparison
	subtitle_cues = cues
	var colors: Dictionary = episode["theme"]["colors"]
	identity_style.bg_color = Color(colors["surface"], 0.94)
	identity_style.border_color = colors["divider"]
	identity_accent.color = colors["accent"]
	phase_style.bg_color = Color(colors["surface_elevated"], 0.94)
	phase_style.border_color = colors["divider"]
	explain_style.bg_color = Color(colors["surface_elevated"], 0.97)
	explain_style.border_color = colors["divider"]
	result_style.bg_color = Color(colors["surface_elevated"], 0.98)
	result_style.border_color = colors["divider"]
	subtitle_style.bg_color = Color(colors["background"], 0.94)
	subtitle_style.border_color = colors["divider"]
	result_divider.color = colors["divider"]
	tag_label.add_theme_color_override("font_color", colors["accent"])
	title_label.add_theme_color_override("font_color", colors["text"])
	phase_dot_label.add_theme_color_override("font_color", colors["accent"])
	phase_label.add_theme_color_override("font_color", colors["muted"])
	question_label.add_theme_color_override("font_color", colors["text"])
	explain_title_label.add_theme_color_override("font_color", colors["accent"])
	explain_detail_label.add_theme_color_override("font_color", colors["text"])
	clock_label.add_theme_color_override("font_color", colors["muted"])
	result_title.add_theme_color_override("font_color", colors["text"])
	result_callout_label.add_theme_color_override("font_color", colors["text"])
	conclusion_label.add_theme_color_override("font_color", colors["text"])
	subtitle_label.add_theme_color_override("font_color", colors["text"])

	var tag := "FRAMEWORK"
	if int(episode["season"]) > 0:
		tag = "S%02dE%02d" % [episode["season"], episode["episode"]]
	tag_label.text = "%s  /  %s" % [episode["series"], tag]
	title_label.text = episode["title"]
	question_label.text = episode["display_hook"]
	_build_variant_chips()
	_build_result_rows()
	formula_renderer.configure(episode["story"].get("explanation", {}), colors)
	set_phase("QUESTION")


func set_phase(value: String) -> void:
	phase = value
	phase_label.text = {
		"QUESTION": "提出问题",
		"EXPLAIN": "建立直觉",
		"SETUP": "控制变量",
		"FLIGHT": "同步实验",
		"COMPARE": "结果揭晓",
	}.get(phase, phase)
	question_label.visible = phase in ["QUESTION", "SETUP"]
	if phase == "SETUP" and not episode["story"].get("control_label", "").is_empty():
		question_label.text = episode["story"]["control_label"]
		question_label.position = EpisodeLayout.SETUP_COPY_RECT.position
		question_label.size = EpisodeLayout.SETUP_COPY_RECT.size
		question_label.theme_type_variation = VideoTypography.BODY
	else:
		question_label.text = episode["display_hook"]
		question_label.position = EpisodeLayout.QUESTION_RECT.position
		question_label.size = EpisodeLayout.QUESTION_RECT.size
		question_label.theme_type_variation = VideoTypography.HERO
	_reset_label_motion(question_label)

	explain_panel.visible = phase == "EXPLAIN"
	explain_title_label.visible = explain_panel.visible
	explain_detail_label.visible = explain_panel.visible
	formula_renderer.visible = false
	var show_legend := phase in ["SETUP", "FLIGHT", "COMPARE"]
	for chip in legend_chips:
		chip.visible = show_legend
	result_panel.visible = phase == "COMPARE"
	result_title.visible = result_panel.visible
	result_divider.visible = result_panel.visible
	result_callout_label.visible = false
	conclusion_label.visible = false
	for index in range(result_rows.size()):
		result_rows[index].visible = false
		result_swatches[index].visible = false
	clock_label.visible = phase == "FLIGHT"


func set_beat(beat: Dictionary) -> void:
	current_beat = beat
	if not beat.is_empty():
		phase_label.text = String(beat.get("label", phase_label.text))
	var formula_step := int(beat.get("formula_step", -1))
	var show_formula := phase == "EXPLAIN" and formula_step >= 0
	formula_renderer.visible = show_formula
	explain_title_label.visible = phase == "EXPLAIN" and not show_formula
	explain_detail_label.visible = phase == "EXPLAIN" and not show_formula
	if show_formula:
		formula_renderer.set_step(formula_step)


func set_elapsed(video_time_sec: float, simulation_times: Dictionary) -> void:
	if phase == "QUESTION":
		_apply_label_intro(question_label, video_time_sec / 0.55)
	else:
		_reset_label_motion(question_label)
	var subtitle_text := SubtitleTrack.text_at(subtitle_cues, video_time_sec)
	subtitle_label.text = subtitle_text
	subtitle_panel.visible = not subtitle_text.is_empty()
	subtitle_label.visible = subtitle_panel.visible
	if phase == "FLIGHT":
		var values: Array = simulation_times.values()
		var simulation_time := 0.0 if values.is_empty() else float(values[0])
		clock_label.text = "实验 %05.2f s   ·   视频 %05.2f s" % [
			simulation_time,
			video_time_sec,
		]
	elif phase == "COMPARE":
		var compare_time := EpisodeLayout.phase_elapsed(episode, phase, video_time_sec)
		var reveal_interval := float(
			episode["story"].get("result_reveal_interval_sec", 0.3)
		)
		for index in range(result_rows.size()):
			var revealed := compare_time >= 0.5 + index * reveal_interval
			result_rows[index].visible = revealed
			result_swatches[index].visible = revealed
		var conclusion_delay := float(
			episode["story"].get("conclusion_delay_sec", 0.0)
		)
		if conclusion_delay <= 0.0:
			conclusion_delay = 0.8 + result_rows.size() * reveal_interval
		var show_conclusion := compare_time >= conclusion_delay
		result_callout_label.visible = show_conclusion
		conclusion_label.visible = show_conclusion
		if show_conclusion:
			_apply_label_intro(
				result_callout_label,
				(compare_time - conclusion_delay) / 0.4
			)


func _build_ui() -> void:
	var identity_result := _panel(EpisodeLayout.IDENTITY_RECT, Color("#161B22"), 16, 1)
	identity_panel = identity_result["panel"]
	identity_style = identity_result["style"]
	add_child(identity_panel)
	identity_accent = ColorRect.new()
	identity_accent.position = Vector2(14, 13)
	identity_accent.size = Vector2(4, 46)
	identity_accent.color = Color("#F0B35A")
	identity_panel.add_child(identity_accent)
	tag_label = _label(Vector2(30, 8), Vector2(620, 24), VideoTypography.META, Color("#F0B35A"))
	identity_panel.add_child(tag_label)
	title_label = _label(Vector2(30, 31), Vector2(630, 36), VideoTypography.TITLE, Color("#F2F0E9"))
	identity_panel.add_child(title_label)

	var phase_result := _panel(EpisodeLayout.PHASE_RECT, Color("#1D2430"), 24, 1)
	phase_panel = phase_result["panel"]
	phase_style = phase_result["style"]
	add_child(phase_panel)
	phase_dot_label = _label(Vector2(22, 5), Vector2(22, 34), VideoTypography.META, Color("#F0B35A"))
	phase_dot_label.text = "●"
	phase_dot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phase_panel.add_child(phase_dot_label)
	phase_label = _label(Vector2(43, 5), Vector2(166, 34), VideoTypography.META, Color("#9AA4B2"))
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phase_panel.add_child(phase_label)

	question_label = _label(
		EpisodeLayout.QUESTION_RECT.position,
		EpisodeLayout.QUESTION_RECT.size,
		VideoTypography.HERO,
		Color("#F2F0E9")
	)
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(question_label)

	var explain_result := _panel(EpisodeLayout.EXPLAIN_RECT, Color("#1D2430"), 22, 1)
	explain_panel = explain_result["panel"]
	explain_style = explain_result["style"]
	add_child(explain_panel)
	explain_title_label = _label(Vector2(54, 48), Vector2(952, 82), VideoTypography.DISPLAY, Color("#F0B35A"))
	explain_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explain_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	explain_panel.add_child(explain_title_label)
	explain_detail_label = _label(Vector2(70, 150), Vector2(920, 190), VideoTypography.BODY, Color("#F2F0E9"))
	explain_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explain_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	explain_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain_panel.add_child(explain_detail_label)
	formula_renderer = FormulaRenderer.new()
	formula_renderer.position = Vector2(40, 18)
	formula_renderer.size = Vector2(980, 384)
	formula_renderer.visible = false
	explain_panel.add_child(formula_renderer)

	clock_label = _label(
		EpisodeLayout.CLOCK_RECT.position,
		EpisodeLayout.CLOCK_RECT.size,
		VideoTypography.DATA_META,
		Color("#9AA4B2")
	)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(clock_label)

	var result_result := _panel(EpisodeLayout.RESULT_RECT, Color("#1D2430"), 22, 1)
	result_panel = result_result["panel"]
	result_style = result_result["style"]
	add_child(result_panel)
	result_title = _label(Vector2(38, 32), Vector2(664, 50), VideoTypography.SECTION, Color("#F2F0E9"))
	result_panel.add_child(result_title)
	result_divider = ColorRect.new()
	result_divider.position = Vector2(38, 475)
	result_divider.size = Vector2(664, 1)
	result_divider.color = Color("#2D3642")
	result_panel.add_child(result_divider)
	result_callout_label = _label(
		Vector2(46, 490),
		Vector2(648, 58),
		VideoTypography.ACCENT,
		Color("#F2F0E9")
	)
	result_callout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_callout_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_callout_label.visible = false
	result_panel.add_child(result_callout_label)
	conclusion_label = _label(Vector2(46, 554), Vector2(648, 108), VideoTypography.BODY, Color("#F2F0E9"))
	conclusion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conclusion_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	conclusion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_panel.add_child(conclusion_label)

	var subtitle_result := _panel(EpisodeLayout.SUBTITLE_RECT, Color("#0E1116"), 18, 1)
	subtitle_panel = subtitle_result["panel"]
	subtitle_style = subtitle_result["style"]
	add_child(subtitle_panel)
	subtitle_label = _label(Vector2(34, 6), Vector2(1532, 88), VideoTypography.SUBTITLE, Color("#F2F0E9"))
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_panel.add_child(subtitle_label)
	subtitle_panel.visible = false


func _build_variant_chips() -> void:
	for chip in legend_chips:
		chip.queue_free()
	legend_chips.clear()
	legend_styles.clear()
	legend_labels.clear()
	legend_swatches.clear()
	var variants: Array = episode["variants"]
	var colors: Dictionary = episode["theme"]["colors"]
	var cell_width := EpisodeLayout.LEGEND_RECT.size.x / variants.size()
	for index in range(variants.size()):
		var variant: Dictionary = variants[index]
		var rect := Rect2(
			EpisodeLayout.LEGEND_RECT.position + Vector2(index * cell_width + 5, 0),
			Vector2(cell_width - 10, EpisodeLayout.LEGEND_RECT.size.y)
		)
		var chip_result := _panel(rect, Color(colors["surface"], 0.82), 12, 0)
		var chip: Panel = chip_result["panel"]
		var style: StyleBoxFlat = chip_result["style"]
		add_child(chip)
		var swatch := ColorRect.new()
		swatch.position = Vector2(14, 13)
		swatch.size = Vector2(5, 20)
		swatch.color = variant["color"]
		chip.add_child(swatch)
		var label := _label(Vector2(28, 5), Vector2(rect.size.x - 38, 36), VideoTypography.DATA, colors["text"])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = variant["label"]
		chip.add_child(label)
		legend_chips.append(chip)
		legend_styles.append(style)
		legend_labels.append(label)
		legend_swatches.append(swatch)


func _build_result_rows() -> void:
	for old_row in result_rows:
		old_row.queue_free()
	for old_swatch in result_swatches:
		old_swatch.queue_free()
	result_rows.clear()
	result_swatches.clear()
	var colors: Dictionary = episode["theme"]["colors"]
	result_title.text = "%s  /  %s" % [
		analysis["metric_label"],
		"越大越优" if analysis["goal"] == "max" else "越小越优",
	]
	explain_title_label.text = episode["story"].get("explain_title", "")
	explain_detail_label.text = episode["story"].get("explain_detail", "")
	var rows: Array = analysis["rows"]
	var step := minf(62.0, 350.0 / maxf(1.0, rows.size()))
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var winner: bool = row["variant_id"] == analysis["winner_id"]
		var secondary := ""
		var secondary_metric: String = analysis.get("secondary_metric", "")
		if not secondary_metric.is_empty() and row["metrics"].has(secondary_metric):
			secondary = "  ·  %s %.2f %s" % [
				analysis.get("secondary_label", ""),
				float(row["metrics"][secondary_metric]),
				analysis.get("secondary_unit", ""),
			]
		var swatch := ColorRect.new()
		swatch.position = Vector2(42, 111 + index * step)
		swatch.size = Vector2(12 if winner else 6, maxf(18.0, step - 24.0))
		swatch.color = Color.from_string("#%s" % row["color_html"], Color.WHITE)
		result_panel.add_child(swatch)
		var label := _label(
			Vector2(66, 100 + index * step),
			Vector2(630, maxf(34.0, step - 4.0)),
			VideoTypography.DATA,
			colors["text"]
		)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = "%s%s   %.2f %s%s" % [
			"★  " if winner else "",
			row["label"],
			row["value"],
			analysis["metric_unit"],
			secondary,
		]
		result_panel.add_child(label)
		result_rows.append(label)
		result_swatches.append(swatch)
	var conclusion: String = analysis.get("conclusion", "")
	result_callout_label.text = "本轮最优"
	if conclusion.is_empty():
		for row in rows:
			if row["variant_id"] == analysis["winner_id"]:
				conclusion = "本轮最优：%s" % row["label"]
				break
	for row in rows:
		if row["variant_id"] == analysis["winner_id"]:
			result_callout_label.text = "本轮最优  ·  %s" % row["label"]
			break
	conclusion_label.text = conclusion


func _apply_label_intro(label: Label, raw_progress: float) -> void:
	var progress := clampf(raw_progress, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * lerpf(0.94, 1.0, eased)
	label.modulate.a = eased


func _reset_label_motion(label: Label) -> void:
	label.scale = Vector2.ONE
	label.modulate.a = 1.0


func _panel(
	rect: Rect2,
	color: Color,
	radius: int,
	border_width: int = 0
) -> Dictionary:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = Color("#2D3642")
	panel.add_theme_stylebox_override("panel", style)
	return {"panel": panel, "style": style}


func _label(
	position_value: Vector2,
	size_value: Vector2,
	role: StringName,
	color: Color
) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	VideoTypography.apply_role(label, role)
	label.add_theme_color_override("font_color", color)
	return label
