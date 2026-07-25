extends SceneTree

const SubtitleTrack = preload("res://src/playback/subtitle_track.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: export_subtitles.gd <input.srt> <output.srt>")
		quit(2)
		return
	var loaded := SubtitleTrack.load_path(args[0])
	if not loaded["ok"]:
		printerr(loaded["error"])
		quit(2)
		return
	var cues := SubtitleTrack.prepare_burn_in_cues(
		SubtitleTrack.split_display_cues(loaded["cues"])
	)
	var layout := SubtitleTrack.validate_layout(cues)
	if not layout["ok"]:
		printerr(layout["error"])
		quit(2)
		return
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		printerr("cannot write subtitle file: %s" % args[1])
		quit(2)
		return
	file.store_string(SubtitleTrack.to_srt(cues))
	file.close()
	print("subtitle-export: cues=%d output=%s" % [cues.size(), args[1]])
	quit(0)
