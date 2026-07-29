class_name SlingshotRunRecord
extends RefCounted

const DomainRegistry = preload("res://src/core/domain_registry.gd")


static func make_bundle(
	episode: Dictionary,
	records: Array,
	extras: Dictionary = {}
) -> Dictionary:
	var bundle := {
		"schema_version": 1,
		"episode_id": episode["id"],
		"simulation": episode["simulation"].duplicate(true),
		"engine": Engine.get_version_info().get("string", "unknown"),
		"records": records.duplicate(true),
	}
	bundle.merge(extras.duplicate(true), true)
	return bundle


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
	var validation := validate_bundle(value)
	if not validation["ok"]:
		return {"ok": false, "error": "%s: %s" % [path, validation["error"]], "value": {}}
	return {"ok": true, "error": "", "value": value}


static func validate_bundle(value: Dictionary) -> Dictionary:
	if int(value.get("schema_version", 0)) != 1:
		return _failure("schema_version must equal 1")
	if not value.get("episode_id") is String or String(value["episode_id"]).is_empty():
		return _failure("episode_id must be a non-empty string")
	if not value.get("simulation") is Dictionary:
		return _failure("simulation must be an object")
	var model := String(value["simulation"].get("model", "rigidbody"))
	var domain: Variant = DomainRegistry.for_model(model)
	if domain == null:
		return _failure("unsupported simulation model: %s" % model)
	if not value.get("records") is Array or value["records"].is_empty():
		return _failure("records must be a non-empty array")
	var seen := {}
	for index in range(value["records"].size()):
		if not value["records"][index] is Dictionary:
			return _failure("records[%d] must be an object" % index)
		var record: Dictionary = value["records"][index]
		var record_error: String = domain.validate_record(record)
		if not record_error.is_empty():
			return _failure("records[%d].%s" % [index, record_error])
		var variant_id := String(record["variant_id"])
		if seen.has(variant_id):
			return _failure("duplicate record variant_id: %s" % variant_id)
		seen[variant_id] = true
	return {"ok": true, "error": ""}


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


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
