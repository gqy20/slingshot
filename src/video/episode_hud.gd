class_name SlingshotEpisodeHud
extends CanvasLayer

var episode: Dictionary = {}
var analysis: Dictionary = {}
var phase := "QUESTION"
var system_font: SystemFont
var title_label: Label
var tag_label: Label
var phase_label: Label
var question_label: Label
var clock_label: Label
var legend_panel: ColorRect
var legend_labels: Array[Label] = []
var result_panel: ColorRect
var result_title: Label
var result_rows: Array[Label] = []
var conclusion_label: Label


func _ready() -> void:
	_build_ui()


func configure(normalized_episode: Dictionary, comparison: Dictionary) -> void:
	episode = normalized_episode
	analysis = comparison
	var theme: Dictionary = episode["theme"]["colors"]
	tag_label.add_theme_color_override("font_color", theme["ground_line"])
	title_label.add_theme_color_override("font_color", theme["text"])
	phase_label.add_theme_color_override("font_color", theme["accent"])
	question_label.add_theme_color_override("font_color", theme["text"])
	clock_label.add_theme_color_override("font_color", theme["muted"])
	legend_panel.color = Color(theme["panel"], 0.88)
	result_panel.color = Color(theme["panel"], 0.96)
	result_title.add_theme_color_override("font_color", theme["accent"])
	conclusion_label.add_theme_color_override("font_color", theme["text"])
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
		"SETUP": "控制变量",
		"FLIGHT": "同步实验",
		"COMPARE": "结果揭晓",
	}.get(phase, phase)
	question_label.visible = phase in ["QUESTION", "SETUP"]
	legend_panel.visible = phase in ["SETUP", "FLIGHT", "COMPARE"]
	for label in legend_labels:
		label.visible = legend_panel.visible
	result_panel.visible = phase == "COMPARE"
	result_title.visible = result_panel.visible
	conclusion_label.visible = result_panel.visible
	for row in result_rows:
		row.visible = result_panel.visible
	clock_label.visible = phase == "FLIGHT"


func set_elapsed(video_time_sec: float, simulation_times: Dictionary) -> void:
	if phase != "FLIGHT":
		return
	var values: Array = simulation_times.values()
	var simulation_time := 0.0 if values.is_empty() else float(values[0])
	clock_label.text = "实验时间  %05.2f s   ·   视频时间  %05.2f s" % [
		simulation_time,
		video_time_sec,
	]


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

	clock_label = _label(Vector2(1280, 170), Vector2(580, 36), 18, Color("#91A8BF"))
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clock_label)

	legend_panel = ColorRect.new()
	legend_panel.position = Vector2(160, 105)
	legend_panel.size = Vector2(1600, 58)
	legend_panel.color = Color(0.025, 0.075, 0.13, 0.88)
	add_child(legend_panel)

	result_panel = ColorRect.new()
	result_panel.position = Vector2(100, 770)
	result_panel.size = Vector2(1720, 262)
	result_panel.color = Color(0.018, 0.055, 0.095, 0.96)
	add_child(result_panel)
	result_title = _label(Vector2(142, 790), Vector2(620, 42), 27, Color("#7CD8FF"))
	add_child(result_title)
	conclusion_label = _label(Vector2(1060, 790), Vector2(700, 200), 27, Color("#F4F8FF"))
	conclusion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conclusion_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	conclusion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(conclusion_label)


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
	var rows: Array = analysis["rows"]
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var column := index % 2
		var line := index / 2
		var winner: bool = row["variant_id"] == analysis["winner_id"]
		var label := _label(
			Vector2(145 + column * 430, 842 + line * 48),
			Vector2(405, 42),
			22,
			Color("#FFD166") if winner else Color("#D5E4F2")
		)
		label.text = "%s%s   %.2f %s" % [
			"★ " if winner else "• ",
			row["label"],
			row["value"],
			analysis["metric_unit"],
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
