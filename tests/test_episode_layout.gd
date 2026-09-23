extends RefCounted

const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const EpisodeCanvas = preload("res://src/video/episode_canvas.gd")
const EpisodeHud = preload("res://src/video/episode_hud.gd")
const SpringEnergy = preload("res://src/video/explanations/spring_energy.gd")
const TrackRaceCanvas = preload("res://src/video/canvases/track_race_canvas.gd")
const EpisodeLoader = preload("res://src/core/episode_loader.gd")


func run(t) -> void:
	t.check(
		EpisodeLayout.world_scale("FLIGHT", "immersive") > EpisodeLayout.world_scale("FLIGHT"),
		"immersive mode gives the physical world more screen area"
	)
	t.check(EpisodeCanvas != null and EpisodeHud != null, "episode render components compile")
	var canvas := EpisodeCanvas.new()
	var spring := SpringEnergy.new()
	canvas.explanation_module = spring
	canvas.phase = "COMPARE"
	canvas.current_beat = {"layers": ["world", "subjects", "trajectories"]}
	t.check(not canvas._winner_emphasis_enabled(), "immersive counterexample removes winner celebration")
	canvas.current_beat = {"layers": ["world", "results"]}
	t.check(canvas._winner_emphasis_enabled(), "measurement result enables winner emphasis")
	canvas.current_beat = {
		"phase": "EXPLAIN",
		"layers": ["world", "annotations"],
		"overlay": "spring-energy",
		"at": 25.0,
		"duration": 10.0,
		"formula_step": 1,
	}
	canvas.phase = "EXPLAIN"
	canvas.video_time_sec = 25.0
	t.check(not canvas._show_physical_stage(), "energy diagram removes the unrelated sling and ground")
	t.check_close(spring._extension_factor(canvas), 1.0, 0.0001, "spring starts its purposeful x-to-2x transition without jumping")
	canvas.video_time_sec = 25.8
	t.check_close(spring._extension_factor(canvas), 2.0, 0.0001, "spring reaches the doubled extension after the transition")
	t.check(spring._dimension_label(1.0) == "x", "base extension uses the x dimension label")
	t.check(spring._dimension_label(1.5) == "x → 2x", "dimension label explains the transition while the spring moves")
	t.check(spring._dimension_label(2.0) == "2x", "doubled extension uses the 2x dimension label")
	canvas.episode = {"story": {"question_sec": 15.0}}
	canvas.video_time_sec = 24.9
	var reveal_before_copy_boundary: float = spring._bar_reveal(canvas, 3, 4)
	canvas.video_time_sec = 25.1
	var reveal_after_copy_boundary: float = spring._bar_reveal(canvas, 3, 4)
	t.check_close(reveal_before_copy_boundary, 1.0, 0.0001, "energy bars finish their first reveal")
	t.check_close(reveal_after_copy_boundary, 1.0, 0.0001, "energy bars do not reset at the next explanation beat")
	var errors := EpisodeLayout.validate_static_regions()
	t.check(errors.is_empty(), "episode plot areas avoid every reserved text region")
	var render_script := FileAccess.get_file_as_string("res://scripts/render_episode.ps1")
	var reburn_script := FileAccess.get_file_as_string("res://scripts/reburn_episode.ps1")
	var render_shell_script := FileAccess.get_file_as_string("res://scripts/render_episode.sh")
	t.check(
		render_script.contains("[int]$SubtitleBottomMargin = 68")
		and reburn_script.contains("[int]$SubtitleBottomMargin = 68")
		and render_shell_script.contains("EPISODE_SUBTITLE_BOTTOM_MARGIN:-68"),
		"all render paths share the EP04 subtitle bottom margin"
	)
	t.check(
		render_script.contains("--script res://scripts/export_subtitles.gd")
		and render_script.contains("-i $displaySrt $subtitleAss"),
		"full Windows renders normalize display cues before ASS conversion"
	)
	t.check(
		TrackRaceCanvas.CONTENT_BOTTOM <= EpisodeLayout.SUBTITLE_RECT.position.y - 40.0,
		"track course leaves a visible gutter above the subtitle safe area"
	)
	t.check(
		TrackRaceCanvas.FONT_ESSENTIAL >= 30
		and TrackRaceCanvas.FONT_DATA >= 32,
		"track course essential text follows the EP04 readability floor"
	)
	t.check(
		TrackRaceCanvas.FONT_SECONDARY >= 28
		and TrackRaceCanvas.FONT_ENVIRONMENT >= 24,
		"track course secondary and environmental text keep distinct floors"
	)
	for beat_id in TrackRaceCanvas.layout_audit_regions():
		var regions: Array = TrackRaceCanvas.layout_audit_regions()[beat_id]
		for index in range(regions.size()):
			var region: Rect2 = regions[index]
			t.check(
				Rect2(Vector2.ZERO, EpisodeLayout.CANVAS_SIZE).encloses(region),
				"track layout stays on canvas: %s/%d" % [beat_id, index]
			)
			t.check(
				region.end.y <= TrackRaceCanvas.CONTENT_BOTTOM,
				"track layout stays above subtitles: %s/%d" % [beat_id, index]
			)
			for other_index in range(index):
				t.check(
					not region.intersects(regions[other_index]),
					"track text panels do not overlap: %s/%d/%d" % [beat_id, other_index, index]
				)
	var formula_regions: Dictionary = TrackRaceCanvas.formula_audit_regions()
	var energy_formula: Rect2 = formula_regions["energy"]
	var time_formula: Rect2 = formula_regions["time"]
	var cycloid_formula: Rect2 = formula_regions["cycloid"]
	t.check(energy_formula.size.y >= 90.0, "energy formula keeps a readable display height")
	t.check(time_formula.size.y >= 112.0, "time integral keeps a readable display height")
	t.check(cycloid_formula.size.y >= 160.0, "two-line cycloid formula keeps a readable display height")
	var energy_panel: Rect2 = TrackRaceCanvas.layout_audit_regions()["energy-drop"][0]
	t.check(energy_panel.end.y - energy_formula.end.y >= 60.0, "energy formula keeps bottom breathing room")
	t.check(
		TrackRaceCanvas.TIME_ACCUMULATION_BASELINE_Y - time_formula.end.y >= 60.0,
		"time integral keeps breathing room above its live accumulation"
	)
	t.check(
		cycloid_formula.end.y <= TrackRaceCanvas.CONTENT_BOTTOM - 20.0,
		"cycloid formula keeps a gutter above the subtitle safe area"
	)
	var track_episode_result := EpisodeLoader.load_path(
		"res://content/episodes/s01e05-shortest-is-not-fastest.json"
	)
	t.check(track_episode_result["ok"], "track episode loads for layout audit")
	if track_episode_result["ok"]:
		var explanation: Dictionary = track_episode_result["episode"]["story"]["explanation"]
		t.check(
			explanation.get("module", "") == "track_race",
			"track course owns a dedicated explanation module"
		)
		t.check(explanation.get("steps", []).size() == 4, "track course declares all four Typst formula states")
		var time_formula_step: Dictionary = explanation.get("steps", [])[2]
		t.check(
			FileAccess.get_file_as_string(String(time_formula_step.get("formula_asset", ""))).contains(
				"viewBox=\"0 0 1400 336\""
			),
			"integral SVG reserves vertical canvas padding for its limits"
		)
		for step_value in explanation.get("steps", []):
			var step: Dictionary = step_value
			t.check(not String(step.get("typst", "")).is_empty(), "track formula declares Typst source")
			t.check(
				FileAccess.file_exists(String(step.get("formula_asset", ""))),
				"track Typst SVG exists: %s" % String(step.get("formula_asset", ""))
			)
		var beats_by_id := {}
		for beat_value in track_episode_result["episode"]["beats"]:
			beats_by_id[String(beat_value["id"])] = beat_value
		t.check(
			not "headline" in beats_by_id["fair-controls"]["layers"],
			"fair-control annotations do not compete with the shared HUD headline"
		)
		var fair_regions: Array = TrackRaceCanvas.layout_audit_regions()["fair-controls"]
		var fair_region: Rect2 = fair_regions[0]
		t.check(
			fair_regions.size() == 1 and fair_region.position.x >= 1300.0,
			"fair controls use one quiet note column instead of a row of cards"
		)
		t.check(
			not "results" in beats_by_id["distance-time-table"]["layers"],
			"dedicated distance-time table does not duplicate the generic result HUD"
		)
		t.check(
			TrackRaceCanvas.layout_audit_regions()["distance-is-not-time"].size() == 1,
			"distance and time read as one argument instead of two stacked cards"
		)
		t.check(
			TrackRaceCanvas.layout_audit_regions()["finish-slow-motion"].size() == 1,
			"finish slow motion keeps one local-time view instead of duplicating arrival data"
		)
		t.check(
			TrackRaceCanvas.layout_audit_regions()["model-boundary"].size() == 1,
			"model boundary uses one editorial note column instead of three cards"
		)
		var track_canvas_source := FileAccess.get_file_as_string(
			"res://src/video/canvases/track_race_canvas.gd"
		)
		t.check(
			not track_canvas_source.contains("func _draw_panel"),
			"track episode uses no reusable boxed-container primitive"
		)
		t.check(
			not track_canvas_source.contains("draw_rect(rect, Color(colors[\"surface\"]")
			and not track_canvas_source.contains("draw_rect(panel, Color(colors[\"surface\"]"),
			"track episode does not hide hierarchy inside opaque surface cards"
		)
		var final_subtitles := FileAccess.get_file_as_string(
			"res://content/subtitles/s01e05-shortest-is-not-fastest.srt"
		)
		t.check(
			final_subtitles.contains("它们会不会一起到达最低点呢？"),
			"track episode closes with a conversational causal question"
		)
	for beat_id in [
		"distance-is-not-time", "energy-drop", "time-integral",
		"fair-controls", "track-preview", "race-release", "race-separation",
	]:
		var plot_bounds := TrackRaceCanvas.track_plot_bounds(beat_id)
		t.check(
			plot_bounds.end.y <= TrackRaceCanvas.CONTENT_BOTTOM,
			"%s reframed track stays above subtitles" % beat_id
		)
		for region in TrackRaceCanvas.layout_audit_regions()[beat_id]:
			t.check(
				not plot_bounds.intersects(region),
				"%s information region clears the animated track viewport" % beat_id
			)

	var flight_plot := EpisodeLayout.plot_rect_for_phase("FLIGHT")
	var compare_plot := EpisodeLayout.plot_rect_for_phase("COMPARE")
	t.check(
		compare_plot.size.x >= flight_plot.size.x,
		"comparison uses the world instead of reserving a dashboard column"
	)
	t.check(
		compare_plot.intersects(EpisodeLayout.RESULT_RECT),
		"transparent result typography can share the physical stage"
	)
	var previous_result_cell := Rect2()
	for index in range(5):
		var result_cell := EpisodeLayout.result_rail_cell(index, 5)
		t.check(
			EpisodeLayout.RESULT_RAIL_RECT.encloses(result_cell),
			"result rail cell %d stays inside the dedicated comparison band" % index
		)
		if index > 0:
			t.check(
				not previous_result_cell.intersects(result_cell),
				"result rail cells do not overlap"
			)
		previous_result_cell = result_cell
	var trajectory := PackedVector2Array([
		Vector2(240, 760),
		Vector2(360, 540),
		Vector2(480, 620),
		Vector2(620, 920),
	])
	t.check(
		canvas._trajectory_apex(trajectory) == Vector2(360, 540),
		"height annotation follows the actual trajectory apex"
	)
	canvas.free()
	for phase in ["QUESTION", "EXPLAIN", "SETUP", "FLIGHT", "COMPARE"]:
		var mapped_ground := EpisodeLayout.map_world(Vector2(0.0, 920.0), phase)
		t.check(
			mapped_ground.y < EpisodeLayout.SUBTITLE_RECT.position.y,
			"%s ground stays above subtitle safe area" % phase
		)
