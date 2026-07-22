extends Node2D

const EpisodeLoader = preload("res://src/core/episode_loader.gd")
const RunRecord = preload("res://src/core/run_record.gd")
const ExperimentRunner = preload("res://src/simulation/experiment_runner.gd")
const EpisodePlayer = preload("res://src/video/episode_player.gd")

var boot_frames := -1


func _enter_tree() -> void:
	var args := _parse_user_args(OS.get_cmdline_user_args())
	var episode_path: String = args.get("episode", "")
	if episode_path.is_empty() or not FileAccess.file_exists(episode_path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(episode_path))
	if not raw is Dictionary or not raw.get("video") is Dictionary:
		return
	var video: Dictionary = raw["video"]
	var requested_size := Vector2i(
		int(video.get("width", 1920)),
		int(video.get("height", 1080))
	)
	get_tree().root.size = requested_size
	get_tree().root.content_scale_size = requested_size
	DisplayServer.window_set_size(requested_size)


func _ready() -> void:
	var args := _parse_user_args(OS.get_cmdline_user_args())
	var episode_path: String = args.get("episode", "")
	if episode_path.is_empty():
		printerr("[episode:error] --episode is required")
		get_tree().quit(2)
		return
	var loaded := EpisodeLoader.load_path(episode_path)
	if not loaded["ok"]:
		printerr("[episode:error] %s" % loaded["error"])
		get_tree().quit(2)
		return
	var episode: Dictionary = loaded["episode"]
	print("[episode] id=%s" % episode["id"])
	if args.get("boot_only", false):
		boot_frames = 2
		return

	var simulation_path: String = args.get("simulate_record", "")
	if not simulation_path.is_empty():
		var runner := ExperimentRunner.new()
		runner.name = "ExperimentRunner"
		add_child(runner)
		runner.start(episode, simulation_path)
		return

	var playback_path: String = args.get("play_record", "")
	if playback_path.is_empty():
		printerr("[episode:error] --simulate-record or --play-record is required")
		get_tree().quit(2)
		return
	var record_result := RunRecord.read_json(playback_path)
	if not record_result["ok"]:
		printerr("[episode:error] %s" % record_result["error"])
		get_tree().quit(2)
		return
	var bundle: Dictionary = record_result["value"]
	if bundle.get("episode_id") != episode["id"]:
		printerr("[episode:error] record episode id does not match configuration")
		get_tree().quit(2)
		return
	var player := EpisodePlayer.new()
	player.name = "EpisodePlayer"
	add_child(player)
	player.start(
		episode,
		bundle,
		String(args.get("sidecar", "")),
		String(args.get("subtitles", ""))
	)


func _process(_delta: float) -> void:
	if boot_frames < 0:
		return
	boot_frames -= 1
	if boot_frames <= 0:
		get_tree().quit(0)


func _parse_user_args(argv: PackedStringArray) -> Dictionary:
	var result := {
		"episode": "",
		"simulate_record": "",
		"play_record": "",
		"sidecar": "",
		"subtitles": "",
		"boot_only": false,
	}
	var index := 0
	while index < argv.size():
		match argv[index]:
			"--episode":
				if index + 1 < argv.size():
					result["episode"] = argv[index + 1]
					index += 1
			"--simulate-record":
				if index + 1 < argv.size():
					result["simulate_record"] = argv[index + 1]
					index += 1
			"--play-record":
				if index + 1 < argv.size():
					result["play_record"] = argv[index + 1]
					index += 1
			"--sidecar":
				if index + 1 < argv.size():
					result["sidecar"] = argv[index + 1]
					index += 1
			"--subtitles":
				if index + 1 < argv.size():
					result["subtitles"] = argv[index + 1]
					index += 1
			"--boot-only":
				result["boot_only"] = true
		index += 1
	return result
