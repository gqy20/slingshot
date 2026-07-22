class_name SlingshotEpisodeHud
extends CanvasLayer

const SubtitleTrack = preload("res://src/playback/subtitle_track.gd")

var episode: Dictionary = {}
var analysis: Dictionary = {}
var subtitle_cues: Array = []
var phase := "QUESTION"
var system_font: SystemFont
var title_label: Label
var tag_label: Label
var phase_label: Label
var question_label: Label
var explain_panel: ColorRect
var explain_title_label: Label
var explain_detail_label: Label
var clock_label: Label
var legend_panel: ColorRect
var legend_labels: Array[Label] = []
var result_panel: ColorRect
var result_title: Label
var result_rows: Array[Label] = []
var conclusion_label: Label
var subtitle_panel: ColorRect
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
	var theme: Dictionary = episode["theme"]["colors"]
	tag_label.add_theme_color_override("font_color", theme["ground_line"])
	title_label.add_theme_color_override("font_color", theme["text"])
	phase_label.add_theme_color_override("font_color", theme["accent"])
	question_label.add_theme_color_override("font_color", theme["text"])
	explain_title_label.add_theme_color_override("font_color", theme["highlight"])
	explain_detail_label.add_theme_color_override("font_color", theme["text"])
	clock_label.add_theme_color_override("font_color", theme["muted"])
	legend_panel.color = Color(theme["panel"], 0.88)
	result_panel.color = Color(theme["panel"], 0.96)
	result_title.add_theme_color_override("font_color", theme["accent"])
	conclusion_label.add_theme_color_override("font_color", theme["text"])
	subtitle_panel.color = Color(theme["panel"], 0.97)
	subtitle_label.add_theme_color_override("font_color", theme["text"])
	var tag := "FRAMEWORK"
	if int(episode["season"]) > 0:
		tag = "S%02dE%02d" % [episode["season"], episode["episode"]]
	tag_label.text = "%s  /  %s" % [episode["series"], tag]
	title_label.text = episode["title"]
	question_label.text = episode["question"]
	_build_variant_labels()
	_build_result_rows()
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
	explain_panel.visible = phase == "EXPLAIN"
	explain_title_label.visible = explain_panel.visible
	explain_detail_label.visible = explain_panel.visible
	if phase == "SETUP" and not episode["story"].get("control_label", "").is_empty():
		question_label.text = episode["story"]["control_label"]
		question_label.add_theme_font_size_override("font_size", 34)
	else:
		question_label.text = episode["question"]
		question_label.add_theme_font_size_override("font_size", 50)
	legend_panel.visible = phase in ["SETUP", "FLIGHT", "COMPARE"]
	for label in legend_labels:
		label.visible = legend_panel.visible
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
		clock_label.text = "实验时间  %05.2f s   ·   视频时间  %05.2f s" % [
			simulation_time,
			video_time_sec,
		]
	elif phase == "COMPARE":
		var compare_start := float(episode["duration_sec"]) - float(
			episode["story"]["compare_sec"]
		)
		var compare_time := maxf(0.0, video_time_sec - compare_start)
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
	system_font = SystemFont.new()
	var top_band := ColorRect.new()
	top_band.position = Vector2.ZERO
	top_band.size = Vector2(1920, 90)
	top_band.color = Color(0.02, 0.055, 0.105, 0.96)
	add_child(top_band)

	tag_label = _label(Vector2(52, 12), Vector2(620, 28), 22, Color("#5EE1A2"))
	tag_label.text = "平行物理实验室"
	add_child(tag_label)
	title_label = _label(Vector2(52, 38), Vector2(1150, 44), 31, Color("#F4F8FF"))
	add_child(title_label)
	phase_label = _label(Vector2(1510, 22), Vector2(350, 48), 25, Color("#7CD8FF"))
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(phase_label)

	question_label = _label(Vector2(210, 146), Vector2(1500, 170), 50, Color("#F4F8FF"))
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.add_theme_constant_override("outline_size", 12)
	question_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.1, 0.92))
	add_child(question_label)

	explain_panel = ColorRect.new()
	explain_panel.position = Vector2(300, 235)
	explain_panel.size = Vector2(1320, 360)
	explain_panel.color = Color(0.025, 0.075, 0.13, 0.92)
	add_child(explain_panel)
	explain_title_label = _label(Vector2(360, 280), Vector2(1200, 90), 50, Color("#FFD166"))
	explain_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explain_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(explain_title_label)
	explain_detail_label = _label(Vector2(380, 385), Vector2(1160, 150), 36, Color("#F4F8FF"))
	explain_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explain_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	explain_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(explain_detail_label)

	clock_label = _label(Vector2(1280, 170), Vector2(580, 36), 18, Color("#91A8BF"))
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clock_label)

	legend_panel = ColorRect.new()
	legend_panel.position = Vector2(160, 105)
	legend_panel.size = Vector2(1600, 58)
	legend_panel.color = Color(0.025, 0.075, 0.13, 0.88)
	add_child(legend_panel)

	result_panel = ColorRect.new()
	result_panel.position = Vector2(100, 675)
	result_panel.size = Vector2(1720, 245)
	result_panel.color = Color(0.018, 0.055, 0.095, 0.96)
	add_child(result_panel)
	result_title = _label(Vector2(142, 695), Vector2(620, 42), 27, Color("#7CD8FF"))
	add_child(result_title)
	conclusion_label = _label(Vector2(1060, 695), Vector2(700, 190), 27, Color("#F4F8FF"))
	conclusion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conclusion_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	conclusion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(conclusion_label)

	subtitle_panel = ColorRect.new()
	subtitle_panel.position = Vector2(180, 946)
	subtitle_panel.size = Vector2(1560, 106)
	subtitle_panel.color = Color(0.018, 0.055, 0.095, 0.97)
	add_child(subtitle_panel)
	subtitle_label = _label(Vector2(218, 954), Vector2(1484, 90), 29, Color("#F4F8FF"))
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(subtitle_label)
	subtitle_panel.visible = false
	subtitle_label.visible = false


func _build_variant_labels() -> void:
	for old_label in legend_labels:
		old_label.queue_free()
	legend_labels.clear()
	var variants: Array = episode["variants"]
	var available_width := 1520.0
	var cell_width := available_width / variants.size()
	for index in range(variants.size()):
		var variant: Dictionary = variants[index]
		var label := _label(
			Vector2(200 + index * cell_width, 116),
			Vector2(cell_width - 12, 36),
			22,
			variant["color"]
		)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = "●  %s" % variant["label"]
		add_child(label)
		legend_labels.append(label)


func _build_result_rows() -> void:
	for old_row in result_rows:
		old_row.queue_free()
	result_rows.clear()
	result_title.text = "%s  ·  %s" % [
		analysis["metric_label"],
		"越大越优" if analysis["goal"] == "max" else "越小越优",
	]
	explain_title_label.text = episode["story"].get("explain_title", "")
	explain_detail_label.text = episode["story"].get("explain_detail", "")
	var rows: Array = analysis["rows"]
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var column := index % 2
		var line := index / 2
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
			Vector2(145 + column * 430, 747 + line * 48),
			Vector2(405, 42),
			22,
			Color("#FFD166") if winner else Color("#D5E4F2")
		)
		label.text = "%s%s   %.2f %s%s" % [
			"★ " if winner else "• ",
			row["label"],
			row["value"],
			analysis["metric_unit"],
			secondary,
		]
		add_child(label)
		result_rows.append(label)
	var conclusion: String = analysis.get("conclusion", "")
	if conclusion.is_empty():
		var winner_label := ""
		for row in rows:
			if row["variant_id"] == analysis["winner_id"]:
				winner_label = row["label"]
				break
		conclusion = "本轮最优：%s" % winner_label
	conclusion_label.text = conclusion


func _label(
	position_value: Vector2,
	size_value: Vector2,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.add_theme_font_override("font", system_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
