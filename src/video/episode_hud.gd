class_name SlingshotEpisodeHud
extends CanvasLayer

const SubtitleTrack = preload("res://src/playback/subtitle_track.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")

var episode: Dictionary = {}
var analysis: Dictionary = {}
var subtitle_cues: Array = []
var phase := "QUESTION"

var regular_font: Font
var medium_font: Font
var bold_font: Font
var identity_panel: Panel
var identity_style: StyleBoxFlat
var phase_panel: Panel
var phase_style: StyleBoxFlat
var explain_panel: Panel
var explain_style: StyleBoxFlat
var result_panel: Panel
var result_style: StyleBoxFlat
var subtitle_panel: Panel
var subtitle_style: StyleBoxFlat
var legend_chips: Array[Panel] = []
var legend_labels: Array[Label] = []
var result_rows: Array[Label] = []

var title_label: Label
var tag_label: Label
var phase_label: Label
var question_label: Label
var explain_title_label: Label
var explain_detail_label: Label
var clock_label: Label
var result_title: Label
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
	identity_style.bg_color = Color(colors["panel"], 0.82)
	identity_style.border_color = Color(colors["accent"], 0.22)
	phase_style.bg_color = Color(colors["accent"], 0.12)
	phase_style.border_color = Color(colors["accent"], 0.55)
	explain_style.bg_color = Color(colors["panel"], 0.94)
	explain_style.border_color = Color(colors["accent"], 0.22)
	result_style.bg_color = Color(colors["panel"], 0.96)
	result_style.border_color = Color(colors["accent"], 0.25)
	subtitle_style.bg_color = Color(colors["panel"], 0.96)
	subtitle_style.border_color = Color(colors["accent"], 0.18)
	tag_label.add_theme_color_override("font_color", colors["ground_line"])
	title_label.add_theme_color_override("font_color", colors["text"])
	phase_label.add_theme_color_override("font_color", colors["accent"])
	question_label.add_theme_color_override("font_color", colors["text"])
	explain_title_label.add_theme_color_override("font_color", colors["highlight"])
	explain_detail_label.add_theme_color_override("font_color", colors["text"])
	clock_label.add_theme_color_override("font_color", colors["muted"])
	result_title.add_theme_color_override("font_color", colors["accent"])
	conclusion_label.add_theme_color_override("font_color", colors["text"])
	subtitle_label.add_theme_color_override("font_color", colors["text"])

	var tag := "FRAMEWORK"
	if int(episode["season"]) > 0:
		tag = "S%02dE%02d" % [episode["season"], episode["episode"]]
	tag_label.text = "%s  /  %s" % [episode["series"], tag]
	title_label.text = episode["title"]
	question_label.text = episode["question"]
	_build_variant_chips()
	_build_result_rows()
	set_phase("QUESTION")


func set_phase(value: String) -> void:
	phase = value
	phase_label.text = {
		"QUESTION": "●  提出问题",
		"EXPLAIN": "●  建立直觉",
		"SETUP": "●  控制变量",
		"FLIGHT": "●  同步实验",
		"COMPARE": "●  结果揭晓",
	}.get(phase, phase)
	question_label.visible = phase in ["QUESTION", "SETUP"]
	if phase == "SETUP" and not episode["story"].get("control_label", "").is_empty():
		question_label.text = episode["story"]["control_label"]
		question_label.position = EpisodeLayout.SETUP_COPY_RECT.position
		question_label.size = EpisodeLayout.SETUP_COPY_RECT.size
		question_label.add_theme_font_size_override("font_size", 30)
	else:
		question_label.text = episode["question"]
		question_label.position = EpisodeLayout.QUESTION_RECT.position
		question_label.size = EpisodeLayout.QUESTION_RECT.size
		question_label.add_theme_font_size_override("font_size", 48)

	explain_panel.visible = phase == "EXPLAIN"
	explain_title_label.visible = explain_panel.visible
	explain_detail_label.visible = explain_panel.visible
	var show_legend := phase in ["SETUP", "FLIGHT", "COMPARE"]
	for chip in legend_chips:
		chip.visible = show_legend
	result_panel.visible = phase == "COMPARE"
	result_title.visible = result_panel.visible
	conclusion_label.visible = false
	for row in result_rows:
		row.visible = false
	clock_label.visible = phase == "FLIGHT"


func set_elapsed(video_time_sec: float, simulation_times: Dictionary) -> void:
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
			result_rows[index].visible = compare_time >= 0.5 + index * reveal_interval
		var conclusion_delay := float(
			episode["story"].get("conclusion_delay_sec", 0.0)
		)
		if conclusion_delay <= 0.0:
			conclusion_delay = 0.8 + result_rows.size() * reveal_interval
		conclusion_label.visible = compare_time >= conclusion_delay


func _build_ui() -> void:
	regular_font = VideoTypography.regular()
	medium_font = VideoTypography.medium()
	bold_font = VideoTypography.bold()

	var identity_result := _panel(EpisodeLayout.IDENTITY_RECT, Color("#07182A"), 16, 1)
	identity_panel = identity_result["panel"]
	identity_style = identity_result["style"]
	add_child(identity_panel)
	var identity_accent := ColorRect.new()
	identity_accent.position = Vector2(14, 13)
	identity_accent.size = Vector2(4, 46)
	identity_accent.color = Color("#5EE1A2")
	identity_panel.add_child(identity_accent)
	tag_label = _label(Vector2(30, 9), Vector2(620, 24), 17, Color("#5EE1A2"), medium_font)
	identity_panel.add_child(tag_label)
	title_label = _label(Vector2(30, 32), Vector2(630, 34), 27, Color("#F4F8FF"), medium_font)
	identity_panel.add_child(title_label)

	var phase_result := _panel(EpisodeLayout.PHASE_RECT, Color("#0A2238"), 24, 1)
	phase_panel = phase_result["panel"]
	phase_style = phase_result["style"]
	add_child(phase_panel)
	phase_label = _label(Vector2(15, 7), Vector2(210, 34), 19, Color("#7CD8FF"), medium_font)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_panel.add_child(phase_label)

	question_label = _label(
		EpisodeLayout.QUESTION_RECT.position,
		EpisodeLayout.QUESTION_RECT.size,
		48,
		Color("#F4F8FF"),
		bold_font
	)
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.add_theme_constant_override("outline_size", 10)
	question_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.1, 0.9))
	add_child(question_label)

	var explain_result := _panel(EpisodeLayout.EXPLAIN_RECT, Color("#07182A"), 22, 1)
	explain_panel = explain_result["panel"]
	explain_style = explain_result["style"]
	add_child(explain_panel)
	explain_title_label = _label(Vector2(54, 48), Vector2(952, 82), 45, Color("#FFD166"), bold_font)
	explain_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explain_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	explain_panel.add_child(explain_title_label)
	explain_detail_label = _label(Vector2(70, 150), Vector2(920, 190), 32, Color("#F4F8FF"), regular_font)
	explain_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explain_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	explain_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain_panel.add_child(explain_detail_label)

	clock_label = _label(
		EpisodeLayout.CLOCK_RECT.position,
		EpisodeLayout.CLOCK_RECT.size,
		16,
		Color("#91A8BF"),
		medium_font
	)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(clock_label)

	var result_result := _panel(EpisodeLayout.RESULT_RECT, Color("#07182A"), 22, 1)
	result_panel = result_result["panel"]
	result_style = result_result["style"]
	add_child(result_panel)
	result_title = _label(Vector2(38, 32), Vector2(664, 50), 27, Color("#7CD8FF"), bold_font)
	result_panel.add_child(result_title)
	var divider := ColorRect.new()
	divider.position = Vector2(38, 475)
	divider.size = Vector2(664, 2)
	divider.color = Color(0.49, 0.85, 1.0, 0.18)
	result_panel.add_child(divider)
	conclusion_label = _label(Vector2(46, 500), Vector2(648, 165), 27, Color("#F4F8FF"), medium_font)
	conclusion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conclusion_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	conclusion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_panel.add_child(conclusion_label)

	var subtitle_result := _panel(EpisodeLayout.SUBTITLE_RECT, Color("#07182A"), 18, 1)
	subtitle_panel = subtitle_result["panel"]
	subtitle_style = subtitle_result["style"]
	add_child(subtitle_panel)
	subtitle_label = _label(Vector2(34, 6), Vector2(1532, 88), 27, Color("#F4F8FF"), medium_font)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_panel.add_child(subtitle_label)
	subtitle_panel.visible = false


func _build_variant_chips() -> void:
	for chip in legend_chips:
		chip.queue_free()
	legend_chips.clear()
	legend_labels.clear()
	var variants: Array = episode["variants"]
	var cell_width := EpisodeLayout.LEGEND_RECT.size.x / variants.size()
	for index in range(variants.size()):
		var variant: Dictionary = variants[index]
		var rect := Rect2(
			EpisodeLayout.LEGEND_RECT.position + Vector2(index * cell_width + 5, 0),
			Vector2(cell_width - 10, EpisodeLayout.LEGEND_RECT.size.y)
		)
		var chip_result := _panel(rect, Color(variant["color"], 0.10), 14, 1)
		var chip: Panel = chip_result["panel"]
		var style: StyleBoxFlat = chip_result["style"]
		style.border_color = Color(variant["color"], 0.30)
		add_child(chip)
		var label := _label(Vector2(8, 7), Vector2(rect.size.x - 16, 38), 20, variant["color"], medium_font)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = "●  %s" % variant["label"]
		chip.add_child(label)
		legend_chips.append(chip)
		legend_labels.append(label)


func _build_result_rows() -> void:
	for old_row in result_rows:
		old_row.queue_free()
	result_rows.clear()
	result_title.text = "%s  /  %s" % [
		analysis["metric_label"],
		"越大越优" if analysis["goal"] == "max" else "越小越优",
	]
	explain_title_label.text = episode["story"].get("explain_title", "")
	explain_detail_label.text = episode["story"].get("explain_detail", "")
	var rows: Array = analysis["rows"]
	var step := minf(62.0, 350.0 / maxf(1.0, rows.size()))
	var row_font_size := 21 if rows.size() <= 6 else 18
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
		var label := _label(
			Vector2(42, 100 + index * step),
			Vector2(656, maxf(34.0, step - 4.0)),
			row_font_size,
			Color("#FFD166") if winner else Color("#D5E4F2"),
			bold_font if winner else medium_font
		)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = "%s%s   %.2f %s%s" % [
			"★ " if winner else "• ",
			row["label"],
			row["value"],
			analysis["metric_unit"],
			secondary,
		]
		result_panel.add_child(label)
		result_rows.append(label)
	var conclusion: String = analysis.get("conclusion", "")
	if conclusion.is_empty():
		for row in rows:
			if row["variant_id"] == analysis["winner_id"]:
				conclusion = "本轮最优：%s" % row["label"]
				break
	conclusion_label.text = conclusion


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
	style.border_color = Color(0.49, 0.85, 1.0, 0.22)
	panel.add_theme_stylebox_override("panel", style)
	return {"panel": panel, "style": style}


func _label(
	position_value: Vector2,
	size_value: Vector2,
	font_size: int,
	color: Color,
	font: Font
) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.theme = VideoTypography.theme()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
