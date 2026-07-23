class_name SlingshotEpisodeLoader
extends RefCounted

const PresetLoader = preload("res://src/core/preset_loader.gd")

const REQUIRED_VIDEO_SIZE := Vector2i(3840, 2160)
const ALLOWED_VIDEO_FPS := [30, 60]
const ALLOWED_TEMPLATES := ["overlay_comparison"]
const ALLOWED_GOALS := ["max", "min"]
const ALLOWED_BEAT_PHASES := ["QUESTION", "EXPLAIN", "SETUP", "FLIGHT", "COMPARE"]
const ALLOWED_OVERRIDE_PREFIXES := ["physics.", "scene."]


static func load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("episode not found: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _failure("episode is not a JSON object: %s" % path)
	return validate_dict(parsed, path)


static func validate_dict(raw: Dictionary, source_path: String = "") -> Dictionary:
	if int(raw.get("schema_version", 0)) != 1:
		return _failure("schema_version must equal 1")
	for key in ["id", "title", "question", "base_preset"]:
		if not raw.get(key) is String or String(raw[key]).strip_edges().is_empty():
			return _failure("%s must be a non-empty string" % key)

	var video_value: Variant = raw.get("video")
	if not video_value is Dictionary:
		return _failure("video must be an object")
	var video: Dictionary = video_value
	if not _is_number(video.get("width")) or not _is_number(video.get("height")):
		return _failure("video width and height must be numeric")
	var video_size := Vector2i(int(video["width"]), int(video["height"]))
	if video_size != REQUIRED_VIDEO_SIZE:
		return _failure("video resolution must be 3840x2160")
	if not _is_number(video.get("fps")) or int(video["fps"]) not in ALLOWED_VIDEO_FPS:
		return _failure("video.fps must be one of %s" % [ALLOWED_VIDEO_FPS])

	var simulation_value: Variant = raw.get("simulation")
	if not simulation_value is Dictionary:
		return _failure("simulation must be an object")
	var simulation: Dictionary = simulation_value.duplicate(true)
	if not _positive_finite(simulation.get("duration_sec")):
		return _failure("simulation.duration_sec must be positive and finite")
	if not _is_number(simulation.get("tick_rate")):
		return _failure("simulation.tick_rate must be numeric")
	var tick_rate := int(simulation["tick_rate"])
	if tick_rate < 30 or tick_rate > 240:
		return _failure("simulation.tick_rate must be between 30 and 240")
	simulation["duration_sec"] = float(simulation["duration_sec"])
	simulation["tick_rate"] = tick_rate

	var story_result := _normalize_story(raw.get("story"))
	if not story_result["ok"]:
		return story_result
	var story: Dictionary = story_result["story"]
	var narration_result := _normalize_narration(raw.get("narration", {}), source_path)
	if not narration_result["ok"]:
		return narration_result

	var theme_path: String = String(
		raw.get("theme", "res://content/themes/laboratory.json")
	)
	if not theme_path.begins_with("res://") and not source_path.is_empty():
		theme_path = source_path.get_base_dir().path_join(theme_path)
	var theme_result := _load_theme(theme_path)
	if not theme_result["ok"]:
		return theme_result

	var base_preset_path: String = raw["base_preset"]
	if not base_preset_path.begins_with("res://") and not source_path.is_empty():
		base_preset_path = source_path.get_base_dir().path_join(base_preset_path)
	if not FileAccess.file_exists(base_preset_path):
		return _failure("base preset not found: %s" % base_preset_path)
	var base_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(base_preset_path))
	if not base_raw is Dictionary:
		return _failure("base preset is not a JSON object: %s" % base_preset_path)

	var variants_value: Variant = raw.get("variants")
	if not variants_value is Array or variants_value.size() < 2 or variants_value.size() > 9:
		return _failure("variants must contain between 2 and 9 entries")
	var normalized_variants: Array = []
	var seen_ids := {}
	for index in range(variants_value.size()):
		var variant_result := _normalize_variant(variants_value[index], base_raw, index)
		if not variant_result["ok"]:
			return variant_result
		var variant: Dictionary = variant_result["variant"]
		if seen_ids.has(variant["id"]):
			return _failure("duplicate variant id: %s" % variant["id"])
		seen_ids[variant["id"]] = true
		normalized_variants.append(variant)

	var duration_sec: float = (
		story["question_sec"]
		+ story["explain_sec"]
		+ story["setup_sec"]
		+ story["flight_sec"]
		+ story["compare_sec"]
	)
	var beats_result := _normalize_beats(raw.get("beats"), duration_sec)
	if not beats_result["ok"]:
		return beats_result
	var normalized := {
		"schema_version": 1,
		"id": String(raw["id"]).strip_edges(),
		"series": String(raw.get("series", "物理实验室")),
		"season": int(raw.get("season", 0)),
		"episode": int(raw.get("episode", 0)),
		"title": String(raw["title"]).strip_edges(),
		"question": String(raw["question"]).strip_edges(),
		"display_hook": String(raw.get("display_hook", raw["title"])).strip_edges(),
		"base_preset": base_preset_path,
		"theme_path": theme_path,
		"theme": theme_result["theme"],
		"video": {
			"width": video_size.x,
			"height": video_size.y,
			"fps": int(video["fps"]),
		},
		"simulation": simulation,
		"story": story,
		"narration": narration_result["narration"],
		"duration_sec": duration_sec,
		"beats": beats_result["beats"],
		"variants": normalized_variants,
	}
	return {"ok": true, "error": "", "episode": normalized}


static func _normalize_beats(value: Variant, duration_sec: float) -> Dictionary:
	if not value is Array or value.is_empty():
		return _failure("beats must be a non-empty array")
	var beats: Array = []
	var cursor := 0.0
	var seen := {}
	for index in range(value.size()):
		if not value[index] is Dictionary:
			return _failure("beats[%d] must be an object" % index)
		var raw: Dictionary = value[index]
		for key in ["id", "label", "phase", "shot"]:
			if not raw.get(key) is String or String(raw[key]).strip_edges().is_empty():
				return _failure("beats[%d].%s must be a non-empty string" % [index, key])
		var id := String(raw["id"]).strip_edges()
		if seen.has(id):
			return _failure("duplicate beat id: %s" % id)
		seen[id] = true
		var phase := String(raw["phase"]).strip_edges()
		if phase not in ALLOWED_BEAT_PHASES:
			return _failure("beats[%d].phase is invalid: %s" % [index, phase])
		if not _is_number(raw.get("at")) or not _positive_finite(raw.get("duration")):
			return _failure("beats[%d] timing must be numeric and positive" % index)
		var at := float(raw["at"])
		var beat_duration := float(raw["duration"])
		if absf(at - cursor) > 0.001:
			return _failure("beats[%d] must start at %.3f" % [index, cursor])
		beats.append({
			"id": id,
			"label": String(raw["label"]).strip_edges(),
			"phase": phase,
			"at": at,
			"duration": beat_duration,
			"shot": String(raw["shot"]).strip_edges(),
			"focus": String(raw.get("focus", "")),
			"focus_secondary": String(raw.get("focus_secondary", "")),
			"focus_label": String(raw.get("focus_label", "")),
			"focus_secondary_label": String(raw.get("focus_secondary_label", "")),
			"headline": String(raw.get("headline", "")),
			"overlay": String(raw.get("overlay", "")),
			"formula_step": int(raw.get("formula_step", -1)),
			"sfx": String(raw.get("sfx", "")),
			"chapter": bool(raw.get("chapter", false)),
		})
		cursor += beat_duration
	if absf(cursor - duration_sec) > 0.001:
		return _failure("beats must cover the complete %.3f second episode" % duration_sec)
	return {"ok": true, "error": "", "beats": beats}


static func _load_theme(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("theme not found: %s" % path)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or not raw.get("colors") is Dictionary:
		return _failure("theme must contain a colors object: %s" % path)
	var required := [
		"background",
		"stage",
		"surface",
		"surface_elevated",
		"divider",
		"ground",
		"ground_line",
		"panel",
		"accent",
		"accent_soft",
		"text",
		"muted",
		"highlight",
	]
	var colors := {}
	var sentinel := Color(-1.0, -1.0, -1.0, -1.0)
	for key in required:
		var value: Variant = raw["colors"].get(key)
		if not value is String:
			return _failure("theme color is missing: %s" % key)
		var color := Color.from_string(value, sentinel)
		if color == sentinel:
			return _failure("theme color is invalid: %s" % key)
		colors[key] = color
	return {
		"ok": true,
		"error": "",
		"theme": {"id": String(raw.get("id", "theme")), "colors": colors},
	}


static func _normalize_story(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("story must be an object")
	var story: Dictionary = value.duplicate(true)
	if story.get("template") not in ALLOWED_TEMPLATES:
		return _failure("story.template must be one of %s" % ALLOWED_TEMPLATES)
	for key in ["question_sec", "setup_sec", "flight_sec", "compare_sec"]:
		if not _positive_finite(story.get(key)):
			return _failure("story.%s must be positive and finite" % key)
		story[key] = float(story[key])
	var explain_value: Variant = story.get("explain_sec", 0.0)
	if not _is_number(explain_value) or not is_finite(float(explain_value)):
		return _failure("story.explain_sec must be numeric and finite")
	story["explain_sec"] = maxf(0.0, float(explain_value))
	if not story.get("primary_metric") is String or String(story["primary_metric"]).is_empty():
		return _failure("story.primary_metric must be a non-empty string")
	story["goal"] = String(story.get("goal", "max"))
	if story["goal"] not in ALLOWED_GOALS:
		return _failure("story.goal must be max or min")
	story["metric_label"] = String(story.get("metric_label", story["primary_metric"]))
	story["metric_unit"] = String(story.get("metric_unit", ""))
	story["secondary_metric"] = String(story.get("secondary_metric", ""))
	story["secondary_label"] = String(story.get("secondary_label", ""))
	story["secondary_unit"] = String(story.get("secondary_unit", ""))
	story["identity_label"] = String(story.get("identity_label", "实验"))
	story["control_label"] = String(story.get("control_label", ""))
	story["explain_title"] = String(story.get("explain_title", ""))
	story["explain_detail"] = String(story.get("explain_detail", ""))
	var explanation_result := _normalize_explanation(story.get("explanation", {}))
	if not explanation_result["ok"]:
		return explanation_result
	story["explanation"] = explanation_result["explanation"]
	story["conclusion"] = String(story.get("conclusion", ""))
	story["result_reveal_interval_sec"] = maxf(
		0.15,
		float(story.get("result_reveal_interval_sec", 0.3))
	)
	story["conclusion_delay_sec"] = maxf(
		0.0,
		float(story.get("conclusion_delay_sec", 0.0))
	)
	story["show_target"] = bool(story.get("show_target", true))
	story["sync_event"] = String(story.get("sync_event", ""))
	story["sync_at"] = clampf(float(story.get("sync_at", 0.68)), 0.15, 0.85)
	return {"ok": true, "error": "", "story": story}


static func _normalize_explanation(value: Variant) -> Dictionary:
	if value == null or value == {}:
		return {"ok": true, "error": "", "explanation": {}}
	if not value is Dictionary:
		return _failure("story.explanation must be an object")
	var kind := String(value.get("kind", ""))
	if kind not in ["relation", "derivation"]:
		return _failure("story.explanation.kind must be relation or derivation")
	var asset_dir := String(value.get("asset_dir", "")).strip_edges()
	var uses_typst := not asset_dir.is_empty()
	if uses_typst and (
		not asset_dir.begins_with("res://assets/generated/formulas/")
		or ".." in asset_dir
	):
		return _failure(
			"story.explanation.asset_dir must stay under res://assets/generated/formulas"
		)
	var steps_value: Variant = value.get("steps")
	if not steps_value is Array or steps_value.size() < 2 or steps_value.size() > 5:
		return _failure("story.explanation.steps must contain between 2 and 5 entries")
	var steps: Array = []
	for index in range(steps_value.size()):
		if not steps_value[index] is Dictionary:
			return _failure("story.explanation.steps[%d] must be an object" % index)
		var raw_step: Dictionary = steps_value[index]
		for key in ["concept", "equation", "caption"]:
			if not raw_step.get(key) is String or String(raw_step[key]).strip_edges().is_empty():
				return _failure("story.explanation.steps[%d].%s must be a non-empty string" % [index, key])
		var typst_source := String(raw_step.get("typst", "")).strip_edges()
		if uses_typst and typst_source.is_empty():
			return _failure(
				"story.explanation.steps[%d].typst must be a non-empty string" % index
			)
		if not uses_typst and not typst_source.is_empty():
			return _failure("story.explanation.asset_dir is required when typst is used")
		var formula_asset := ""
		if uses_typst:
			formula_asset = asset_dir.path_join("step-%02d.svg" % (index + 1))
		steps.append({
			"concept": String(raw_step["concept"]).strip_edges(),
			"equation": String(raw_step["equation"]).strip_edges(),
			"typst": typst_source,
			"formula_asset": formula_asset,
			"caption": String(raw_step["caption"]).strip_edges(),
		})
	var assumptions_value: Variant = value.get("assumptions", [])
	if not assumptions_value is Array:
		return _failure("story.explanation.assumptions must be an array")
	var assumptions: Array[String] = []
	for assumption in assumptions_value:
		if not assumption is String or String(assumption).strip_edges().is_empty():
			return _failure("story.explanation assumptions must be non-empty strings")
		assumptions.append(String(assumption).strip_edges())
	return {
		"ok": true,
		"error": "",
		"explanation": {
			"kind": kind,
			"eyebrow": String(value.get("eyebrow", "")),
			"asset_dir": asset_dir,
			"steps": steps,
			"assumptions": assumptions,
		},
	}


static func _normalize_narration(value: Variant, source_path: String) -> Dictionary:
	if value == null or value == {}:
		return {"ok": true, "error": "", "narration": {}}
	if not value is Dictionary:
		return _failure("narration must be an object")
	var raw: Dictionary = value
	var script_path: String = String(raw.get("script", "")).strip_edges()
	if script_path.is_empty():
		return _failure("narration.script must be a non-empty string")
	if not script_path.begins_with("res://") and not source_path.is_empty():
		script_path = source_path.get_base_dir().path_join(script_path)
	if not FileAccess.file_exists(script_path):
		return _failure("narration script not found: %s" % script_path)
	var voice: String = String(raw.get("voice", "")).strip_edges()
	if voice.is_empty():
		return _failure("narration.voice must be a non-empty string")
	var speed_value: Variant = raw.get("speed", 1.0)
	if not _is_number(speed_value) or float(speed_value) < 0.5 or float(speed_value) > 2.0:
		return _failure("narration.speed must be between 0.5 and 2.0")
	var volume_value: Variant = raw.get("volume", 1.0)
	if not _is_number(volume_value) or float(volume_value) < 0.0 or float(volume_value) > 10.0:
		return _failure("narration.volume must be between 0 and 10")
	var pitch_value: Variant = raw.get("pitch", 0)
	if not _is_number(pitch_value) or int(pitch_value) < -12 or int(pitch_value) > 12:
		return _failure("narration.pitch must be between -12 and 12")
	var subtitle_type := String(raw.get("subtitle_type", "sentence"))
	if subtitle_type != "sentence":
		return _failure("narration.subtitle_type must be sentence for mmx SRT exports")
	var pronunciation_value: Variant = raw.get("pronunciations", [])
	if not pronunciation_value is Array:
		return _failure("narration.pronunciations must be an array")
	var pronunciations: Array[String] = []
	for item in pronunciation_value:
		if not item is String or not "/" in String(item) or String(item).strip_edges().is_empty():
			return _failure("narration pronunciations must use from/to strings")
		pronunciations.append(String(item).strip_edges())
	return {
		"ok": true,
		"error": "",
		"narration": {
			"script": script_path,
			"voice": voice,
			"model": String(raw.get("model", "speech-2.8-hd")),
			"language": String(raw.get("language", "Chinese")),
			"speed": float(speed_value),
			"volume": float(volume_value),
			"pitch": int(pitch_value),
			"subtitle_type": subtitle_type,
			"pronunciations": pronunciations,
		},
	}


static func _normalize_variant(value: Variant, base_raw: Dictionary, index: int) -> Dictionary:
	if not value is Dictionary:
		return _failure("variants[%d] must be an object" % index)
	var raw_variant: Dictionary = value
	for key in ["id", "label", "color"]:
		if not raw_variant.get(key) is String or String(raw_variant[key]).strip_edges().is_empty():
			return _failure("variants[%d].%s must be a non-empty string" % [index, key])
	var color_sentinel := Color(-1.0, -1.0, -1.0, -1.0)
	var color := Color.from_string(raw_variant["color"], color_sentinel)
	if color == color_sentinel:
		return _failure("variants[%d].color must be a valid HTML color" % index)
	var overrides_value: Variant = raw_variant.get("overrides", {})
	if not overrides_value is Dictionary:
		return _failure("variants[%d].overrides must be an object" % index)
	var preset_raw: Dictionary = base_raw.duplicate(true)
	for path in overrides_value:
		if not _allowed_override_path(path):
			return _failure("variants[%d] override path is not allowed: %s" % [index, path])
		var set_error := _set_override(preset_raw, path, overrides_value[path])
		if not set_error.is_empty():
			return _failure("variants[%d] %s" % [index, set_error])
	preset_raw["id"] = "%s-%s" % [preset_raw.get("id", "episode"), raw_variant["id"]]
	preset_raw["duration_sec"] = maxf(1.0, float(preset_raw.get("duration_sec", 1.0)))
	var scene: Dictionary = preset_raw.get("scene", {})
	scene["bird_color"] = raw_variant["color"]
	preset_raw["scene"] = scene
	var preset_result := PresetLoader.validate_dict(preset_raw)
	if not preset_result["ok"]:
		return _failure("variants[%d] invalid preset: %s" % [index, preset_result["error"]])
	return {
		"ok": true,
		"error": "",
		"variant": {
			"id": String(raw_variant["id"]).strip_edges(),
			"label": String(raw_variant["label"]).strip_edges(),
			"color": color,
			"color_html": color.to_html(false),
			"overrides": overrides_value.duplicate(true),
			"preset": preset_result["preset"],
		},
	}


static func _allowed_override_path(path: Variant) -> bool:
	if not path is String:
		return false
	for prefix in ALLOWED_OVERRIDE_PREFIXES:
		if path.begins_with(prefix):
			return true
	return false


static func _set_override(target: Dictionary, path: String, value: Variant) -> String:
	var parts := path.split(".")
	if parts.size() != 2:
		return "override path must contain exactly one dot: %s" % path
	if not target.get(parts[0]) is Dictionary:
		return "override section does not exist: %s" % parts[0]
	var section: Dictionary = target[parts[0]]
	if not section.has(parts[1]):
		return "override key does not exist: %s" % path
	section[parts[1]] = value
	return ""


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _positive_finite(value: Variant) -> bool:
	return _is_number(value) and is_finite(float(value)) and float(value) > 0.0


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "episode": {}}
