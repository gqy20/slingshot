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
	var phrase_cues := [{
		"start_sec": 0.0,
		"end_sec": 4.0,
		"text": "水平速度决定向前有多快，滞空时间决定在空中停留多久。",
	}]
	t.check(
		SubtitleTrack.display_text_at(phrase_cues, 0.5).length() <= 28,
		"display subtitles reveal one short phrase at a time"
	)
	var condition_cues := [{
		"start_sec": 0.0,
		"end_sec": 4.0,
		"text": "结论成立的条件是：初速度相同、起点与落点等高、忽略空气阻力。",
	}]
	t.check(
		SubtitleTrack.display_text_at(condition_cues, 0.2) == "结论成立的条件是：",
		"display subtitles prefer semantic punctuation boundaries"
	)
	t.check(
		SubtitleTrack.display_text_at(phrase_cues, 3.5) != SubtitleTrack.display_text_at(phrase_cues, 0.5),
		"display subtitle phrase advances inside one exact source cue"
	)
	t.check(
		not SubtitleTrack.parse_text("bad cue")["ok"],
		"SRT parser rejects malformed cues"
	)
	t.check(SubtitleTrack.validate_layout(cues)["ok"], "short cues fit subtitle layout")
	t.check(
		not SubtitleTrack.validate_layout([
			{"text": "字".repeat(89)},
		])["ok"],
		"subtitle layout rejects overlong cues"
	)
	t.check(
		not SubtitleTrack.validate_layout([
			{"text": "第一行\n第二行\n第三行"},
		])["ok"],
		"subtitle layout rejects more than two explicit lines"
	)
