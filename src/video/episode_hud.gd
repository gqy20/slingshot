class_name SlingshotEpisodeHud
extends CanvasLayer

const SubtitleTrack = preload("res://src/playback/subtitle_track.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")
const FormulaRenderer = preload("res://src/video/formula_renderer.gd")
const EpisodeDirector = preload("res://src/video/episode_director.gd")
const BrandMark = preload("res://src/video/brand_mark.gd")
const ShotCamera = preload("res://src/video/shot_camera.gd")

var episode: Dictionary = {}
var analysis: Dictionary = {}
var subtitle_cues: Array = []
var phase := "QUESTION"
var current_beat: Dictionary = {}

var identity_panel: Panel
var identity_style: StyleBoxFlat
var identity_mark: Control
var identity_tag_base_position := Vector2.ZERO
var outro_panel: Control
var outro_scrim: ColorRect
var outro_mark: Control
var outro_takeaway_label: Label
var outro_brand_label: Label
var outro_descriptor_label: Label
var explain_panel: Panel
var explain_style: StyleBoxFlat
var explain_panel_base_position := Vector2.ZERO
var result_panel: Panel
var result_style: StyleBoxFlat
var subtitle_panel: Panel
var subtitle_style: StyleBoxFlat
var legend_chips: Array[Panel] = []
var legend_styles: Array[StyleBoxFlat] = []
var legend_labels: Array[Label] = []
var legend_swatches: Array[ColorRect] = []
var tag_label: Label
var question_label: Label
var formula_renderer: Control
var clock_label: Label
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
	identity_mark.configure(colors["text"], colors["muted"], colors["accent"])
	outro_mark.configure(colors["text"], colors["muted"], colors["accent"])
	explain_style.bg_color = Color(colors["background"], 0.0)
	explain_style.border_color = Color(colors["divider"], 0.0)
	result_style.bg_color = Color(colors["background"], 0.0)
	result_style.border_color = Color(colors["divider"], 0.0)
	subtitle_style.bg_color = Color(colors["background"], 0.0)
	subtitle_style.border_color = Color(colors["divider"], 0.0)
	tag_label.add_theme_color_override("font_color", colors["muted"])
	question_label.add_theme_color_override("font_color", colors["text"])
	clock_label.add_theme_color_override("font_color", colors["muted"])
	result_callout_label.add_theme_color_override("font_color", colors["text"])
	conclusion_label.add_theme_color_override("font_color", colors["text"])
	subtitle_label.add_theme_color_override("font_color", colors["text"])
	subtitle_label.add_theme_color_override("font_outline_color", colors["background"])
	subtitle_label.add_theme_constant_override("outline_size", 6)
	outro_takeaway_label.add_theme_color_override("font_color", colors["text"])
	outro_brand_label.add_theme_color_override("font_color", colors["text"])
	outro_descriptor_label.add_theme_color_override("font_color", colors["muted"])

	var identity_label := String(episode["story"].get("identity_label", "实验"))
	if bool(episode["story"].get("show_episode_code", true)):
		var tag := "FRAMEWORK"
		if int(episode["season"]) > 0:
			tag = "S%02dE%02d" % [episode["season"], episode["episode"]]
		tag_label.text = "%s  ·  %s  /  %s" % [episode["series"], tag, identity_label]
	else:
		tag_label.text = "%s  ·  %s" % [episode["series"], identity_label]
	outro_brand_label.text = String(episode["series"])
	outro_descriptor_label.text = identity_label
	var brand: Dictionary = episode["story"].get("brand", {})
	outro_takeaway_label.text = String(brand.get(
		"outro_takeaway",
		"条件说清楚，角度才有答案。"
	))
	question_label.text = episode["display_hook"]
	_build_variant_chips()
	_build_result_summary()
	formula_renderer.configure(episode["story"].get("explanation", {}), colors)
	set_phase("QUESTION")


func set_phase(value: String) -> void:
	phase = value
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
	formula_renderer.visible = false
	for chip in legend_chips:
		chip.visible = false
	result_panel.visible = false
	result_callout_label.visible = false
	conclusion_label.visible = false
	clock_label.visible = false


func set_beat(beat: Dictionary) -> void:
	current_beat = beat
	var layers: Array = beat.get("layers", [])
	var show_identity := "identity" in layers
	identity_panel.visible = show_identity
	if phase == "QUESTION" and not String(beat.get("headline", "")).is_empty():
		question_label.text = String(beat["headline"])
	question_label.visible = "headline" in layers
	var formula_step := int(beat.get("formula_step", -1))
	var show_formula := "formula" in layers and formula_step >= 0
	if String(beat.get("handoff", "")) == "formula-to-controls":
		formula_renderer.set_step(int(beat.get("handoff_formula_step", 2)))
	explain_panel.visible = show_formula
	formula_renderer.visible = show_formula
	if show_formula:
		formula_renderer.set_step(formula_step)
	for chip in legend_chips:
		chip.visible = "legend" in layers
	var show_results := "results" in layers
	result_panel.visible = show_results
	if show_results and not String(beat.get("conclusion_display", "")).is_empty():
		conclusion_label.text = String(beat["conclusion_display"])
	clock_label.visible = "clock" in layers
	if not show_results:
		result_callout_label.visible = false
		conclusion_label.visible = false
	var colors: Dictionary = episode["theme"]["colors"]
	subtitle_style.bg_color = Color(colors["background"], 0.0)
	subtitle_style.border_color = Color(colors["divider"], 0.0)


func set_elapsed(video_time_sec: float, simulation_times: Dictionary) -> void:
	var show_intro_identity: bool = (
		"identity" in current_beat.get("layers", [])
		and video_time_sec < 1.6
	)
	identity_panel.visible = show_intro_identity
	if show_intro_identity:
		var identity_progress := clampf(video_time_sec / 1.6, 0.0, 1.0)
		var identity_alpha := (
			smoothstep(0.0, 0.12, identity_progress)
			* (1.0 - smoothstep(0.78, 1.0, identity_progress))
		)
		identity_panel.modulate.a = identity_alpha
		identity_mark.set_progress(clampf(identity_progress / 0.66, 0.0, 1.0))
		var tag_progress := smoothstep(0.22, 0.56, identity_progress)
		tag_label.modulate.a = tag_progress
		tag_label.position = identity_tag_base_position + Vector2(8.0 * (1.0 - tag_progress), 0.0)
	_update_brand_outro(video_time_sec)
	if phase == "QUESTION":
		_apply_label_intro(
			question_label,
			(video_time_sec - float(current_beat.get("at", 0.0))) / 0.55
		)
	else:
		_reset_label_motion(question_label)
	var subtitle_text := SubtitleTrack.display_text_at(subtitle_cues, video_time_sec)
	subtitle_label.text = subtitle_text
	var layers: Array = current_beat.get("layers", [])
	var subtitle_delay := float(current_beat.get("subtitle_delay", 0.0))
	var subtitle_ready := video_time_sec >= float(current_beat.get("at", 0.0)) + subtitle_delay
	subtitle_panel.visible = "subtitle" in layers and subtitle_ready and not subtitle_text.is_empty()
	subtitle_label.visible = subtitle_panel.visible
	if "formula" in layers:
		_reset_explain_panel_transform()
		var progress := EpisodeDirector.beat_progress(current_beat, video_time_sec)
		var reveal_at := float(current_beat.get("formula_reveal", 0.42))
		var hold_formula_visible := (
			String(current_beat.get("camera_action", "reframe")) == "hold"
		)
		var formula_progress := (
			1.0 if hold_formula_visible
			else smoothstep(reveal_at, minf(0.98, reveal_at + 0.16), progress)
		)
		formula_renderer.visible = formula_progress > 0.001
		formula_renderer.modulate.a = formula_progress
		explain_panel.visible = formula_progress > 0.001
		explain_panel.modulate.a = formula_progress
	else:
		var formula_handoff := String(current_beat.get("handoff", "")) == "formula-to-controls"
		var handoff_progress := ShotCamera.transition_eased_progress(current_beat, video_time_sec)
		formula_renderer.visible = formula_handoff and handoff_progress < 1.0
		explain_panel.visible = formula_renderer.visible
		if formula_handoff:
			var shrink_progress := smoothstep(0.04, 0.80, handoff_progress)
			var base_center := explain_panel_base_position + explain_panel.size * 0.5
			var target_center := Vector2(680.0, 760.0)
			explain_panel.position = base_center.lerp(target_center, shrink_progress) - explain_panel.pivot_offset
			explain_panel.scale = Vector2.ONE * lerpf(1.0, 0.18, shrink_progress)
			formula_renderer.modulate.a = 1.0 - smoothstep(0.18, 0.88, handoff_progress)
		else:
			_reset_explain_panel_transform()
			formula_renderer.modulate.a = 1.0
		explain_panel.modulate.a = formula_renderer.modulate.a
	if phase == "FLIGHT" and "clock" in layers:
		var values: Array = simulation_times.values()
		var simulation_time := 0.0 if values.is_empty() else float(values[0])
		clock_label.text = "飞行时间  %05.2f s" % simulation_time
	elif phase == "COMPARE" and "results" in layers:
		var compare_time := EpisodeLayout.phase_elapsed(episode, phase, video_time_sec)
		var conclusion_delay := float(
			episode["story"].get("conclusion_delay_sec", 0.0)
		)
		if conclusion_delay <= 0.0:
			conclusion_delay = 0.8
		var reveal_progress := float(current_beat.get("result_reveal", 0.0))
		var show_conclusion := (
			compare_time >= conclusion_delay
			and EpisodeDirector.beat_progress(current_beat, video_time_sec) >= reveal_progress
		)
		result_callout_label.visible = show_conclusion
		conclusion_label.visible = show_conclusion
		if show_conclusion:
			_apply_label_intro(
				result_callout_label,
				(compare_time - conclusion_delay) / 0.4
			)


func _reset_explain_panel_transform() -> void:
	if explain_panel == null:
		return
	explain_panel.position = explain_panel_base_position
	explain_panel.scale = Vector2.ONE


func _build_ui() -> void:
	var identity_result := _panel(EpisodeLayout.IDENTITY_RECT, Color("#050608", 0.0), 0, 0)
	identity_panel = identity_result["panel"]
	identity_style = identity_result["style"]
	add_child(identity_panel)
	identity_mark = BrandMark.new()
	identity_mark.position = Vector2(0, 1)
	identity_mark.size = Vector2(36, 34)
	identity_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity_panel.add_child(identity_mark)
	identity_tag_base_position = Vector2(48, 0)
	tag_label = _label(identity_tag_base_position, Vector2(760, 36), VideoTypography.TITLE, Color("#A9ADB4"))
	tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity_panel.add_child(tag_label)
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

	var explain_result := _panel(EpisodeLayout.EXPLAIN_RECT, Color("#050608", 0.0), 0, 0)
	explain_panel = explain_result["panel"]
	explain_style = explain_result["style"]
	explain_panel_base_position = explain_panel.position
	explain_panel.pivot_offset = explain_panel.size * 0.5
	add_child(explain_panel)
	formula_renderer = FormulaRenderer.new()
	formula_renderer.position = Vector2(60, 18)
	formula_renderer.size = Vector2(980, 450)
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

	var result_result := _panel(EpisodeLayout.RESULT_RECT, Color("#050608", 0.0), 0, 0)
	result_panel = result_result["panel"]
	result_style = result_result["style"]
	add_child(result_panel)
	result_callout_label = _label(
		Vector2(350, 78),
		Vector2(900, 70),
		VideoTypography.ACCENT,
		Color("#F2F0E9")
	)
	result_callout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_callout_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_callout_label.visible = false
	result_panel.add_child(result_callout_label)
	conclusion_label = _label(Vector2(250, 158), Vector2(1100, 82), VideoTypography.BODY, Color("#F2F0E9"))
	conclusion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conclusion_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	conclusion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_panel.add_child(conclusion_label)

	var subtitle_result := _panel(EpisodeLayout.SUBTITLE_RECT, Color("#050608", 0.0), 0, 0)
	subtitle_panel = subtitle_result["panel"]
	subtitle_style = subtitle_result["style"]
	add_child(subtitle_panel)
	subtitle_label = _label(Vector2(20, 0), Vector2(1500, 90), VideoTypography.SUBTITLE, Color("#F2F0E9"))
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_panel.add_child(subtitle_label)
	_build_outro_ui()


func _build_outro_ui() -> void:
	outro_panel = Control.new()
	outro_panel.position = Vector2.ZERO
	outro_panel.size = EpisodeLayout.CANVAS_SIZE
	outro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outro_panel.visible = false
	add_child(outro_panel)
	outro_scrim = ColorRect.new()
	outro_scrim.position = Vector2.ZERO
	outro_scrim.size = EpisodeLayout.CANVAS_SIZE
	outro_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outro_panel.add_child(outro_scrim)
	outro_takeaway_label = _label(
		Vector2(360, 310),
		Vector2(1200, 76),
		VideoTypography.ACCENT,
		Color("#F2F0E9")
	)
	outro_takeaway_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outro_takeaway_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outro_panel.add_child(outro_takeaway_label)
	outro_mark = BrandMark.new()
	outro_mark.position = Vector2(920, 420)
	outro_mark.size = Vector2(80, 70)
	outro_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outro_panel.add_child(outro_mark)
	outro_brand_label = _label(
		Vector2(560, 520),
		Vector2(800, 58),
		VideoTypography.TITLE,
		Color("#F2F0E9")
	)
	outro_brand_label.add_theme_font_size_override("font_size", 36)
	outro_brand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outro_brand_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outro_panel.add_child(outro_brand_label)
	outro_descriptor_label = _label(
		Vector2(660, 582),
		Vector2(600, 42),
		VideoTypography.META,
		Color("#A9ADB4")
	)
	outro_descriptor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outro_descriptor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outro_panel.add_child(outro_descriptor_label)


func _update_brand_outro(video_time_sec: float) -> void:
	if episode.is_empty():
		outro_panel.visible = false
		return
	var brand: Dictionary = episode["story"].get("brand", {})
	if not bool(brand.get("show_outro", false)):
		outro_panel.visible = false
		return
	var duration := float(episode.get("duration_sec", 300.0))
	var start := float(brand.get("outro_at_sec", duration - 4.45))
	if video_time_sec < start:
		outro_panel.visible = false
		return
	var progress := clampf((video_time_sec - start) / maxf(0.01, duration - start), 0.0, 1.0)
	outro_panel.visible = true
	var background: Color = episode["theme"]["colors"]["background"]
	# Clear the previous scene before introducing the takeaway, so the two
	# typographic layers never compete during the handoff.
	outro_scrim.color = Color(background, smoothstep(0.0, 0.10, progress))
	var takeaway_alpha := (
		smoothstep(0.11, 0.25, progress)
		* (1.0 - smoothstep(0.42, 0.56, progress))
	)
	outro_takeaway_label.modulate.a = takeaway_alpha
	var brand_alpha := (
		smoothstep(0.34, 0.58, progress)
		* (1.0 - smoothstep(0.78, 0.94, progress))
	)
	outro_mark.set_progress(smoothstep(0.22, 0.62, progress))
	outro_mark.modulate.a = brand_alpha
	outro_brand_label.modulate.a = brand_alpha
	outro_descriptor_label.modulate.a = brand_alpha * smoothstep(0.48, 0.68, progress)
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
		var chip_result := _panel(rect, Color(colors["background"], 0.0), 0, 0)
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


func _build_result_summary() -> void:
	var rows: Array = analysis["rows"]
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
	label.scale = Vector2.ONE
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
