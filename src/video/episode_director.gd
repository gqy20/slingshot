class_name SlingshotEpisodeDirector
extends RefCounted

const ReplayTrack = preload("res://src/playback/replay_track.gd")


static func phase_for_time(episode: Dictionary, video_time_sec: float) -> String:
	var story: Dictionary = episode["story"]
	var cursor := float(story["question_sec"])
	if video_time_sec < cursor:
		return "QUESTION"
	cursor += float(story.get("explain_sec", 0.0))
	if video_time_sec < cursor:
		return "EXPLAIN"
	cursor += float(story["setup_sec"])
	if video_time_sec < cursor:
		return "SETUP"
	cursor += float(story["flight_sec"])
	if video_time_sec < cursor:
		return "FLIGHT"
	return "COMPARE"


static func simulation_times(
	episode: Dictionary,
	bundle: Dictionary,
	video_time_sec: float
) -> Dictionary:
	var story: Dictionary = episode["story"]
	var flight_start := (
		float(story["question_sec"])
		+ float(story.get("explain_sec", 0.0))
		+ float(story["setup_sec"])
	)
	var local_time := clampf(
		video_time_sec - flight_start,
		0.0,
		float(story["flight_sec"])
	)
	var result := {}
	for record_value in bundle.get("records", []):
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		result[record["variant_id"]] = _map_record_time(story, record, local_time)
	return result


static func _map_record_time(story: Dictionary, record: Dictionary, local_time: float) -> float:
	var flight_sec := float(story["flight_sec"])
	var simulation_sec := float(record.get("duration_sec", 0.0))
	if flight_sec <= 0.0:
		return 0.0
	var sync_event: String = story.get("sync_event", "")
	if sync_event.is_empty():
		return clampf(local_time / flight_sec * simulation_sec, 0.0, simulation_sec)
	var event_time := ReplayTrack.event_time(record, sync_event)
	if event_time < 0.0:
		return clampf(local_time / flight_sec * simulation_sec, 0.0, simulation_sec)
	var sync_video_time := flight_sec * float(story.get("sync_at", 0.68))
	if local_time <= sync_video_time:
		return clampf(local_time / sync_video_time * event_time, 0.0, event_time)
	var remaining_video := maxf(0.001, flight_sec - sync_video_time)
	return clampf(
		event_time
		+ (local_time - sync_video_time) / remaining_video * (simulation_sec - event_time),
		event_time,
		simulation_sec
	)
