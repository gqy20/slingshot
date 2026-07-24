class_name SlingshotEpisodeTemplates
extends RefCounted

const EDITORIAL_COMPARISON := "editorial_comparison_v1"
const ALLOWED_TEMPLATES := [EDITORIAL_COMPARISON]


static func expand(
	template_id: String,
	story: Dictionary,
	explanation: Dictionary,
	overrides_value: Variant = {}
) -> Dictionary:
	if template_id not in ALLOWED_TEMPLATES:
		return _failure("beat_template must be one of %s" % [ALLOWED_TEMPLATES])
	if not overrides_value is Dictionary:
		return _failure("beat_overrides must be an object")
	var overrides: Dictionary = overrides_value
	var beats: Array = []
	var cursor := 0.0
	cursor = _append_group(
		beats,
		cursor,
		float(story["question_sec"]),
		[0.34, 0.33, 0.33],
		_question_specs()
	)

	var explanation_steps: Array = explanation.get("steps", [])
	var explain_specs: Array = []
	var explain_weights: Array[float] = []
	var explain_count := maxi(1, explanation_steps.size())
	for index in range(explain_count):
		explain_weights.append(1.0 / float(explain_count))
		explain_specs.append({
			"id": "explain-%d" % (index + 1),
			"label": "解释 %d" % (index + 1),
			"phase": "EXPLAIN",
			"shot": "relation" if index == 0 else "formula",
			"mode": "measurement",
			"camera_action": "reframe" if index == 0 else "hold",
			"camera_reason": (
				"make room for the explanatory construction"
				if index == 0
				else "continue the same explanatory geometry"
			),
			"intent": "explain-step-%d" % (index + 1),
			"primary_subject": "explanation-step-%d" % (index + 1),
			"layers": ["world", "annotations", "formula", "subtitle"],
			"formula_step": index,
			"formula_reveal": 0.46 if index == 0 else 0.34,
		})
	cursor = _append_group(
		beats,
		cursor,
		float(story.get("explain_sec", 0.0)),
		explain_weights,
		explain_specs
	)
	cursor = _append_group(
		beats,
		cursor,
		float(story["setup_sec"]),
		[0.48, 0.52],
		_setup_specs()
	)
	cursor = _append_group(
		beats,
		cursor,
		float(story["flight_sec"]),
		[0.40, 0.35, 0.25],
		_flight_specs()
	)
	_append_group(
		beats,
		cursor,
		float(story["compare_sec"]),
		[0.225, 0.225, 0.55],
		_compare_specs()
	)

	var known_ids := {}
	for beat_value in beats:
		var beat: Dictionary = beat_value
		known_ids[String(beat["id"])] = true
	for override_id_value in overrides.keys():
		var override_id := String(override_id_value)
		if not known_ids.has(override_id):
			return _failure("beat_overrides contains unknown beat id: %s" % override_id)
		if not overrides[override_id_value] is Dictionary:
			return _failure("beat_overrides.%s must be an object" % override_id)

	for index in range(beats.size()):
		var beat: Dictionary = beats[index]
		var beat_id := String(beat["id"])
		if not overrides.has(beat_id):
			continue
		var structural := {
			"id": beat["id"],
			"phase": beat["phase"],
			"at": beat["at"],
			"duration": beat["duration"],
		}
		beat.merge(overrides[beat_id], true)
		beat.merge(structural, true)
		beats[index] = beat
	return {"ok": true, "error": "", "beats": beats}


static func _append_group(
	beats: Array,
	cursor: float,
	duration: float,
	weights: Array[float],
	specs: Array
) -> float:
	if duration <= 0.0 or specs.is_empty():
		return cursor
	var group_start := cursor
	for index in range(specs.size()):
		var beat: Dictionary = Dictionary(specs[index]).duplicate(true)
		var beat_duration := duration * weights[index]
		if index == specs.size() - 1:
			beat_duration = group_start + duration - cursor
		beat["at"] = cursor
		beat["duration"] = beat_duration
		beats.append(beat)
		cursor += beat_duration
	return group_start + duration


static func _question_specs() -> Array:
	return [
		{
			"id": "hook", "label": "现象冲突", "phase": "QUESTION",
			"shot": "contrast", "mode": "immersive", "camera_action": "establish",
			"camera_reason": "establish the two outcomes that create the question",
			"intent": "show-visual-conflict", "primary_subject": "contrasting-outcomes",
			"layers": ["world", "subjects", "trajectories", "headline", "identity", "subtitle"],
			"overlay": "contrast-teaser", "chapter": true,
		},
		{
			"id": "controls", "label": "控制变量", "phase": "QUESTION",
			"shot": "controls", "mode": "measurement", "camera_action": "reframe",
			"camera_reason": "separate the controlled and changed quantities",
			"intent": "isolate-variable", "primary_subject": "controlled-variables",
			"layers": ["world", "subjects", "headline", "subtitle"],
			"overlay": "quick-controls",
		},
		{
			"id": "question", "label": "提出问题", "phase": "QUESTION",
			"shot": "hero", "mode": "immersive", "camera_action": "reframe",
			"camera_reason": "return from controls to the observable question",
			"intent": "ask-question", "primary_subject": "question",
			"layers": ["world", "subjects", "headline", "subtitle"],
			"overlay": "display-hook",
		},
	]


static func _setup_specs() -> Array:
	return [
		{
			"id": "setup", "label": "实验条件", "phase": "SETUP",
			"shot": "setup", "mode": "measurement", "camera_action": "reframe",
			"camera_reason": "expand the explanation into the complete variant set",
			"intent": "show-variants", "primary_subject": "all-variants",
			"layers": ["world", "trajectories", "headline", "subtitle"],
			"overlay": "controls", "chapter": true,
		},
		{
			"id": "prediction", "label": "观察预期", "phase": "SETUP",
			"shot": "setup", "mode": "measurement", "camera_action": "hold",
			"camera_reason": "keep the same variants while attention moves to the prediction",
			"intent": "predict-order", "primary_subject": "focused-variant",
			"layers": ["world", "trajectories", "subtitle"],
		},
	]


static func _flight_specs() -> Array:
	return [
		{
			"id": "launch", "label": "同时释放", "phase": "FLIGHT",
			"shot": "launch", "mode": "immersive", "camera_action": "reframe",
			"camera_reason": "move attention from the plan to the shared release point",
			"intent": "observe-launch", "primary_subject": "subjects",
			"layers": ["world", "subjects", "trajectories", "subtitle"],
			"sfx": "release", "chapter": true,
		},
		{
			"id": "flight", "label": "轨迹分化", "phase": "FLIGHT",
			"shot": "follow", "mode": "immersive", "camera_action": "track",
			"camera_reason": "follow the focused subject while the outcomes separate",
			"intent": "observe-separation", "primary_subject": "focused-variant",
			"layers": ["world", "subjects", "trajectories", "subtitle"],
		},
		{
			"id": "landing", "label": "首次落地", "phase": "FLIGHT",
			"shot": "landing", "mode": "immersive", "camera_action": "reframe",
			"camera_reason": "pull back to include every first landing",
			"intent": "observe-landings", "primary_subject": "landing-subjects",
			"layers": ["world", "subjects", "trajectories", "subtitle"],
			"sfx": "landing",
		},
	]


static func _compare_specs() -> Array:
	return [
		{
			"id": "ranking", "label": "结果排名", "phase": "COMPARE",
			"shot": "ranking", "mode": "measurement", "camera_action": "reframe",
			"camera_reason": "fit every measured outcome into one evidence view",
			"intent": "rank-results", "primary_subject": "result-ranking",
			"layers": ["world", "trajectories", "results"],
			"sfx": "result", "chapter": true,
		},
		{
			"id": "counterpoint", "label": "反例观察", "phase": "COMPARE",
			"shot": "comparison", "mode": "immersive", "camera_action": "reframe",
			"camera_reason": "isolate the observation that qualifies the ranking",
			"intent": "show-counterpoint", "primary_subject": "counterpoint",
			"layers": ["world", "subjects", "trajectories", "subtitle"],
			"overlay": "counterexample",
		},
		{
			"id": "takeaway", "label": "结论", "phase": "COMPARE",
			"shot": "takeaway", "mode": "measurement", "camera_action": "reframe",
			"camera_reason": "shift from raw evidence to the final conclusion and boundary",
			"intent": "state-conclusion", "primary_subject": "winning-result",
			"layers": ["world", "subjects", "results", "subtitle"],
			"overlay": "assumptions",
		},
	]


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "beats": []}
