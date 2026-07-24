extends SceneTree

const EpisodeLoader = preload("res://src/core/episode_loader.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: validate_episode.gd <episode.json>")
		quit(2)
		return
	var path := String(args[0])
	var result := EpisodeLoader.load_path(path)
	if not result["ok"]:
		printerr("episode-validation: %s" % result["error"])
		quit(1)
		return
	var episode: Dictionary = result["episode"]
	print(
		"episode-validation: %s beats=%d variants=%d duration=%.1fs" % [
			episode["id"],
			episode["beats"].size(),
			episode["variants"].size(),
			float(episode["duration_sec"]),
		]
	)
	quit(0)
