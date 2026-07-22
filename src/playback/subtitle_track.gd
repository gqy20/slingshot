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
