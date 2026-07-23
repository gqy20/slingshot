extends RefCounted

const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const EpisodeCanvas = preload("res://src/video/episode_canvas.gd")
const EpisodeHud = preload("res://src/video/episode_hud.gd")


func run(t) -> void:
	t.check(EpisodeCanvas != null and EpisodeHud != null, "episode render components compile")
	var errors := EpisodeLayout.validate_static_regions()
	t.check(errors.is_empty(), "episode plot areas avoid every reserved text region")

	var flight_plot := EpisodeLayout.plot_rect_for_phase("FLIGHT")
	var compare_plot := EpisodeLayout.plot_rect_for_phase("COMPARE")
	t.check(
		flight_plot.size.x > compare_plot.size.x,
		"flight prioritizes animation while compare reserves a result column"
	)
	t.check(
		not compare_plot.intersects(EpisodeLayout.RESULT_RECT),
		"compare plot does not sit behind result content"
	)
	for phase in ["QUESTION", "EXPLAIN", "SETUP", "FLIGHT", "COMPARE"]:
		var mapped_ground := EpisodeLayout.map_world(Vector2(0.0, 920.0), phase)
		t.check(
			mapped_ground.y < EpisodeLayout.SUBTITLE_RECT.position.y,
			"%s ground stays above subtitle safe area" % phase
		)
