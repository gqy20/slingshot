class_name SlingshotEpisodeHud
extends CanvasLayer

const SubtitleTrack = preload("res://src/playback/subtitle_track.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")
const FormulaRenderer = preload("res://src/video/formula_renderer.gd")
const EpisodeDirector = preload("res://src/video/episode_director.gd")

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
	identity_style.bg_color = Color(colors["surface"], 0.0)
	identity_style.border_color = Color(colors["divider"], 0.0)
	identity_accent.color = colors["accent"]
	phase_style.bg_color = Color(colors["surface_elevated"], 0.0)
	phase_style.border_color = Color(colors["divider"], 0.0)
	explain_style.bg_color = Color(colors["surface_elevated"], 0.97)
	explain_style.border_color = colors["divider"]
	result_style.bg_color = Color(colors["surface_elevated"], 0.98)
	result_style.border_color = colors["divider"]
	subtitle_style.bg_color = Color(colors["background"], 0.94)
	subtitle_style.border_color = colors["divider"]
	result_divider.color = colors["divider"]
	tag_label.add_theme_color_override("font_color", colors["text"])
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
	subtitle_label.add_theme_color_override("font_outline_color", colors["background"])
	subtitle_label.add_theme_constant_override("outline_size", 9)

	var tag := "FRAMEWORK"
	if int(episode["season"]) > 0:
		tag = "S%02dE%02d" % [episode["season"], episode["episode"]]
	tag_label.text = "%s  ·  %s  /  %s" % [
		episode["series"],
		tag,
		episode["story"].get("identity_label", "实验"),
	]
	title_label.text = ""
	title_label.visible = false
	question_label.text = episode["display_hook"]
	_build_variant_chips()
	_build_result_rows()
	formula_renderer.configure(episode["story"].get("explanation", {}), colors)
	set_phase("QUESTION")


func set_phase(value: String) -> void:
	phase = value
	phase_label.text = {
		"QUESTION": "现象",
		"EXPLAIN": "关系",
		"SETUP": "条件",
		"FLIGHT": "轨迹",
		"COMPARE": "数据",
	}.get(phase, phase)
	phase_panel.visible = false
	question_label.visible = false
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

	explain_panel.visible = false
	explain_title_label.visible = false
	explain_detail_label.visible = false
	formula_renderer.visible = false
	for chip in legend_chips:
		chip.visible = false
	result_panel.visible = false
	result_title.visible = false
	result_divider.visible = false
	result_callout_label.visible = false
	conclusion_label.visible = false
	for index in range(result_rows.size()):
		result_rows[index].visible = false
		result_swatches[index].visible = false
	clock_label.visible = false


func set_beat(beat: Dictionary) -> void:
	current_beat = beat
	var layers: Array = beat.get("layers", [])
	var show_identity := "identity" in layers
	identity_panel.visible = show_identity
	if not beat.is_empty():
		phase_label.text = String(beat.get("label", phase_label.text))
		if phase == "QUESTION" and not String(beat.get("headline", "")).is_empty():
			question_label.text = String(beat["headline"])
	question_label.visible = "headline" in layers
	var formula_step := int(beat.get("formula_step", -1))
	var show_formula := "formula" in layers and formula_step >= 0
	explain_panel.visible = show_formula
	formula_renderer.visible = show_formula
	explain_title_label.visible = false
	explain_detail_label.visible = false
	if show_formula:
		formula_renderer.set_step(formula_step)
	for chip in legend_chips:
		chip.visible = "legend" in layers
	var show_results := "results" in layers
	result_panel.visible = show_results
	result_title.visible = show_results
	result_divider.visible = show_results
	clock_label.visible = "clock" in layers
	if not show_results:
		result_callout_label.visible = false
		conclusion_label.visible = false
		for index in range(result_rows.size()):
			result_rows[index].visible = false
			result_swatches[index].visible = false
	var immersive := String(beat.get("mode", "measurement")) == "immersive"
	var colors: Dictionary = episode["theme"]["colors"]
	subtitle_style.bg_color = Color(colors["background"], 0.0 if immersive else 0.94)
	subtitle_style.border_color = Color(colors["divider"], 0.0 if immersive else 1.0)


func set_elapsed(video_time_sec: float, simulation_times: Dictionary) -> void:
	phase_panel.visible = (
		identity_panel.visible
		and
		bool(current_beat.get("chapter", false))
		and video_time_sec - float(current_beat.get("at", video_time_sec)) < 1.8
	)
	if phase == "QUESTION":
		_apply_label_intro(
			question_label,
			(video_time_sec - float(current_beat.get("at", 0.0))) / 0.55
		)
	else:
		_reset_label_motion(question_label)
	var subtitle_text := SubtitleTrack.text_at(subtitle_cues, video_time_sec)
	subtitle_label.text = subtitle_text
	var layers: Array = current_beat.get("layers", [])
	subtitle_panel.visible = "subtitle" in layers and not subtitle_text.is_empty()
	subtitle_label.visible = subtitle_panel.visible
	if "formula" in layers:
		var progress := EpisodeDirector.beat_progress(current_beat, video_time_sec)
		var reveal_at := float(current_beat.get("formula_reveal", 0.42))
		var formula_progress := smoothstep(reveal_at, minf(0.98, reveal_at + 0.16), progress)
		formula_renderer.visible = formula_progress > 0.001
		formula_renderer.modulate.a = formula_progress
		explain_panel.visible = formula_progress > 0.001
		explain_panel.modulate.a = formula_progress
	else:
		formula_renderer.modulate.a = 1.0
		explain_panel.modulate.a = 1.0
	if phase == "FLIGHT" and "clock" in layers:
		var values: Array = simulation_times.values()
		var simulation_time := 0.0 if values.is_empty() else float(values[0])
		clock_label.text = "飞行时间  %05.2f s" % simulation_time
	elif phase == "COMPARE" and "results" in layers:
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
	var identity_result := _panel(EpisodeLayout.IDENTITY_RECT, Color("#161B22", 0.0), 0, 0)
	identity_panel = identity_result["panel"]
	identity_style = identity_result["style"]
	add_child(identity_panel)
	identity_accent = ColorRect.new()
	identity_accent.position = Vector2(0, 10)
	identity_accent.size = Vector2(3, 24)
	identity_accent.color = Color("#F0B35A")
	identity_panel.add_child(identity_accent)
	tag_label = _label(Vector2(18, 0), Vector2(970, 44), VideoTypography.TITLE, Color("#F2F0E9"))
	tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity_panel.add_child(tag_label)
	title_label = _label(Vector2.ZERO, Vector2.ZERO, VideoTypography.TITLE, Color("#F2F0E9"))
	title_label.visible = false
	identity_panel.add_child(title_label)

	var phase_result := _panel(EpisodeLayout.PHASE_RECT, Color("#1D2430", 0.0), 0, 0)
	phase_panel = phase_result["panel"]
	phase_style = phase_result["style"]
	add_child(phase_panel)
	phase_dot_label = _label(Vector2(28, 2), Vector2(22, 34), VideoTypography.META, Color("#F0B35A"))
	phase_dot_label.text = "●"
	phase_dot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phase_panel.add_child(phase_dot_label)
	phase_label = _label(Vector2(50, 2), Vector2(210, 34), VideoTypography.META, Color("#9AA4B2"))
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
	result_title.text = analysis["metric_label"]
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
	var result_direction := "最大" if analysis["goal"] == "max" else "最小"
	var callout_metric := (
		"射程" if analysis.get("primary_metric", "") == "flight_range_m"
		else String(analysis["metric_label"])
	)
	result_callout_label.text = "%s%s" % [callout_metric, result_direction]
	if conclusion.is_empty():
		for row in rows:
			if row["variant_id"] == analysis["winner_id"]:
				conclusion = "%s%s：%s" % [
					analysis["metric_label"],
					result_direction,
					row["label"],
				]
				break
	for row in rows:
		if row["variant_id"] == analysis["winner_id"]:
			result_callout_label.text = "%s%s  ·  %s" % [
				callout_metric,
				result_direction,
				row["label"],
			]
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
