class_name SlingshotRunRecord
extends RefCounted


static func make_bundle(episode: Dictionary, records: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"episode_id": episode["id"],
		"simulation": episode["simulation"].duplicate(true),
		"engine": Engine.get_version_info().get("string", "unknown"),
		"records": records.duplicate(true),
	}


static func write_json(path: String, value: Variant) -> Error:
	var absolute_path := _absolute_path(path)
	var parent := absolute_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(parent)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(json_safe(value), "  "))
	file.close()
	return OK


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "record not found: %s" % path, "value": {}}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary:
		return {"ok": false, "error": "record is not a JSON object: %s" % path, "value": {}}
	return {"ok": true, "error": "", "value": value}


static func json_safe(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Color:
		return "#" + value.to_html(true)
	if value is Dictionary:
		var dictionary := {}
		for key in value:
			dictionary[key] = json_safe(value[key])
		return dictionary
	if value is Array:
		var array := []
		for item in value:
			array.append(json_safe(item))
		return array
	return value


static func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path
