class_name SlingshotShotCamera
extends RefCounted

const EpisodeLayout = preload("res://src/video/episode_layout.gd")

const TRANSITION_DURATION_SEC := 0.8
const MIN_TRANSITION_DURATION_SEC := 0.2
const MAX_TRANSITION_DURATION_SEC := 2.0


static func desired_state(
	phase: String,
	beat: Dictionary,
	anchor_world: Vector2
) -> Dictionary:
	var mode := String(beat.get("mode", "measurement"))
	var shot := String(beat.get("shot", ""))
	var base_scale := EpisodeLayout.world_scale(phase, mode)
	var base_offset := (
		EpisodeLayout.world_offset(phase, mode)
		- EpisodeLayout.SOURCE_WORLD_RECT.position * base_scale
	)
	var scale_value := base_scale * zoom_for_shot(shot)
	var base_anchor_screen := base_offset + anchor_world * base_scale
	var target_screen := target_screen_for_shot(shot, base_anchor_screen)
	return {
		"scale": scale_value,
		"offset": target_screen - anchor_world * scale_value,
	}


static func interpolate(
	previous: Dictionary,
	current: Dictionary,
	progress: float,
	style: String = "glide"
) -> Dictionary:
	var eased := ease_progress(progress, style)
	return {
		"scale": lerpf(float(previous["scale"]), float(current["scale"]), eased),
		"offset": Vector2(previous["offset"]).lerp(Vector2(current["offset"]), eased),
	}


static func map_point(state: Dictionary, point: Vector2) -> Vector2:
	return Vector2(state["offset"]) + point * float(state["scale"])


static func transition_progress(beat: Dictionary, video_time_sec: float) -> float:
	if beat.is_empty():
		return 1.0
	return clampf(
		(video_time_sec - float(beat.get("at", video_time_sec)))
		/ transition_duration(beat),
		0.0,
		1.0
	)


static func transition_duration(beat: Dictionary) -> float:
	return clampf(
		float(beat.get("transition_duration", TRANSITION_DURATION_SEC)),
		MIN_TRANSITION_DURATION_SEC,
		MAX_TRANSITION_DURATION_SEC
	)


static func transition_style(beat: Dictionary) -> String:
	return String(beat.get("transition_style", "glide"))


static func transition_eased_progress(beat: Dictionary, video_time_sec: float) -> float:
	return ease_progress(transition_progress(beat, video_time_sec), transition_style(beat))


static func ease_progress(progress: float, style: String = "glide") -> float:
	var value := clampf(progress, 0.0, 1.0)
	match style:
		"snap":
			return 1.0 - pow(1.0 - value, 3.0)
		"dissolve":
			return smoothstep(0.0, 1.0, value)
		"morph":
			return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)
		_:
			return smoothstep(0.0, 1.0, value)


static func zoom_for_shot(shot: String) -> float:
	return {
		"wide-contrast": 0.64,
		"contrast": 1.04,
		"controls": 1.0,
		"hero": 1.06,
		"relation": 1.0,
		"formula": 1.0,
		"setup": 1.38,
		"launch": 1.05,
		"follow": 1.16,
		"landing": 1.0,
		"ranking": 1.0,
		"comparison": 1.04,
		"takeaway": 1.03,
	}.get(shot, 1.0)


static func target_screen_for_shot(shot: String, base_anchor_screen: Vector2) -> Vector2:
	return {
		"setup": Vector2(680.0, 760.0),
		"launch": Vector2(520.0, 760.0),
		"follow": Vector2(1030.0, 500.0),
		"comparison": Vector2(1020.0, 525.0),
		"takeaway": Vector2(960.0, 650.0),
	}.get(shot, base_anchor_screen)
