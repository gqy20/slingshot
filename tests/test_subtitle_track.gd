extends RefCounted

const SubtitleTrack = preload("res://src/playback/subtitle_track.gd")


func run(t) -> void:
	var parsed := SubtitleTrack.parse_text(
		"1\r\n00:00:00,000 --> 00:00:02,500\r\n第一句\r\n\r\n"
		+ "2\r\n00:00:03,000 --> 00:00:05,250\r\n第二句\r\n第二行\r\n"
	)
	t.check(parsed["ok"], "SRT parser accepts CRLF cues")
	if not parsed["ok"]:
		return
	var cues: Array = parsed["cues"]
	t.check(cues.size() == 2, "SRT parser returns every cue")
	t.check_close(cues[0]["end_sec"], 2.5, 0.0001, "SRT timestamp converts to seconds")
	t.check(
		SubtitleTrack.text_at(cues, 1.0) == "第一句",
		"subtitle track selects active cue"
	)
	t.check(
		SubtitleTrack.text_at(cues, 3.5) == "第二句\n第二行",
		"subtitle track preserves multiline text"
	)
	t.check(SubtitleTrack.text_at(cues, 2.75).is_empty(), "subtitle gap stays empty")
	t.check(
		not SubtitleTrack.parse_text("bad cue")["ok"],
		"SRT parser rejects malformed cues"
	)
