class_name SlingshotSubtitleTrack
extends RefCounted


static func load_path(path: String) -> Dictionary:
	if path.is_empty():
		return {"ok": true, "error": "", "cues": []}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "subtitle file not found: %s" % path, "cues": []}
	return parse_text(FileAccess.get_file_as_string(path))


static func parse_text(content: String) -> Dictionary:
	var normalized := content.replace("\r\n", "\n").replace("\r", "\n").strip_edges()
	if normalized.is_empty():
		return {"ok": true, "error": "", "cues": []}
	var cues: Array = []
	for block_value in normalized.split("\n\n", false):
		var lines := String(block_value).split("\n", false)
		var timing_index := -1
		for index in range(lines.size()):
			if lines[index].contains("-->"):
				timing_index = index
				break
		if timing_index < 0 or timing_index + 1 >= lines.size():
			return _failure("subtitle cue is missing timing or text")
		var timing_parts := lines[timing_index].split("-->", false)
		if timing_parts.size() != 2:
			return _failure("subtitle timing is invalid: %s" % lines[timing_index])
		var start_sec := _parse_timestamp(timing_parts[0].strip_edges())
		var end_sec := _parse_timestamp(timing_parts[1].strip_edges())
		if start_sec < 0.0 or end_sec <= start_sec:
			return _failure("subtitle timing range is invalid: %s" % lines[timing_index])
		var text_lines := PackedStringArray()
		for index in range(timing_index + 1, lines.size()):
			text_lines.append(lines[index].strip_edges())
		var cue_text := "\n".join(text_lines).strip_edges()
		if cue_text.is_empty():
			return _failure("subtitle cue text is empty")
		cues.append({"start_sec": start_sec, "end_sec": end_sec, "text": cue_text})
	return {"ok": true, "error": "", "cues": cues}


static func text_at(cues: Array, video_time_sec: float) -> String:
	for cue_value in cues:
		if not cue_value is Dictionary:
			continue
		var cue: Dictionary = cue_value
		if video_time_sec >= float(cue["start_sec"]) \
			and video_time_sec < float(cue["end_sec"]):
			return String(cue["text"])
	return ""


static func display_text_at(
	cues: Array,
	video_time_sec: float,
	max_characters: int = 36
) -> String:
	for cue_value in cues:
		if not cue_value is Dictionary:
			continue
		var cue: Dictionary = cue_value
		var start := float(cue["start_sec"])
		var finish := float(cue["end_sec"])
		if video_time_sec < start or video_time_sec >= finish:
			continue
		var phrases := _display_phrases(String(cue["text"]), max_characters)
		if phrases.size() <= 1:
			return String(cue["text"])
		var total_characters := 0
		for phrase in phrases:
			total_characters += String(phrase).length()
		var cue_progress := clampf(
			(video_time_sec - start) / maxf(0.001, finish - start),
			0.0,
			0.9999
		)
		var target_character := cue_progress * total_characters
		var cursor := 0
		for phrase in phrases:
			cursor += String(phrase).length()
			if target_character < cursor:
				return String(phrase)
		return String(phrases[-1])
	return ""


static func _display_phrases(text: String, max_characters: int) -> PackedStringArray:
	var result := PackedStringArray()
	var current := ""
	var normalized := text.replace("\n", "").strip_edges()
	var limit := maxi(8, max_characters)
	var hard_limit := limit + 10
	for character in normalized:
		current += character
		var punctuation_break := character in "，。；！？："
		if (punctuation_break and current.length() >= 6) or current.length() >= hard_limit:
			result.append(current.strip_edges())
			current = ""
	if not current.strip_edges().is_empty():
		result.append(current.strip_edges())
	return result


static func validate_layout(
	cues: Array,
	max_characters: int = 88,
	max_explicit_lines: int = 2
) -> Dictionary:
	for index in range(cues.size()):
		if not cues[index] is Dictionary:
			return {"ok": false, "error": "subtitle cue %d is not an object" % (index + 1)}
		var text := String(cues[index].get("text", ""))
		if text.length() > max_characters:
			return {
				"ok": false,
				"error": "subtitle cue %d exceeds %d characters" % [index + 1, max_characters],
			}
		if text.split("\n").size() > max_explicit_lines:
			return {
				"ok": false,
				"error": "subtitle cue %d exceeds %d explicit lines" % [
					index + 1,
					max_explicit_lines,
				],
			}
	return {"ok": true, "error": ""}


static func _parse_timestamp(value: String) -> float:
	var parts := value.split(":", false)
	if parts.size() != 3:
		return -1.0
	var seconds_text := parts[2].replace(",", ".")
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1.0
	if not seconds_text.is_valid_float():
		return -1.0
	return int(parts[0]) * 3600.0 + int(parts[1]) * 60.0 + float(seconds_text)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "cues": []}
