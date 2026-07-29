extends RefCounted

const Solver = preload("res://src/simulation/impact_pulse_solver.gd")
const PresetLoader = preload("res://src/core/preset_loader.gd")
const EpisodeLoader = preload("res://src/core/episode_loader.gd")
const SubtitleTrack = preload("res://src/playback/subtitle_track.gd")


static func run(t) -> void:
	var loaded := PresetLoader.load_path("res://presets/t003-impact-base.json")
	t.check(loaded["ok"], "T003 impact preset loads")
	if not loaded["ok"]:
		return
	var hard_preset: Dictionary = loaded["preset"]
	var soft_preset := hard_preset.duplicate(true)
	soft_preset["physics"]["contact_duration_sec"] = 0.040
	soft_preset["physics"]["max_penetration_m"] = 0.035
	var hard := Solver.simulate(hard_preset, 240, 1.0, 10000)
	var soft := Solver.simulate(soft_preset, 240, 1.0, 10000)
	t.check_close(float(hard["metrics"]["impulse_ns"]), 8.0, 0.0001, "hard pulse impulse follows momentum change")
	t.check_close(float(soft["metrics"]["impulse_ns"]), 8.0, 0.0001, "soft pulse preserves the same impulse")
	t.check_close(float(hard["metrics"]["average_force_n"]), 1000.0, 0.001, "hard average force is 1000 N")
	t.check_close(float(soft["metrics"]["average_force_n"]), 200.0, 0.001, "soft average force is 200 N")
	t.check_close(float(hard["metrics"]["peak_force_n"]) / float(soft["metrics"]["peak_force_n"]), 5.0, 0.001, "fivefold duration produces fivefold peak ratio")
	var integrated := float(hard["force_curve"][-1]["cumulative_impulse_ns"])
	t.check_close(integrated, 8.0, 0.003, "numerical force curve integrates to target impulse")
	var missed := Solver.sampled_peak(hard["force_curve"], 0.012, 30.0, 0.0)
	t.check_close(missed, 0.0, 0.0001, "30 Hz samples miss the 8 ms pulse between frames")
	var dense := Solver.sampled_peak(hard["force_curve"], 0.012, 10000.0, 0.0)
	t.check_close(dense, float(hard["metrics"]["peak_force_n"]), 1.0, "10 kHz samples recover the peak")
	var episode_result := EpisodeLoader.load_path("res://content/episodes/s01e04-impact-force-curve.json")
	t.check(episode_result["ok"], "T003 impact Episode validates")
	if episode_result["ok"]:
		t.check(episode_result["episode"]["simulation"]["model"] == "impact_pulse", "T003 selects the deterministic impact solver")
		var explanation: Dictionary = episode_result["episode"]["story"]["explanation"]
		t.check(explanation["steps"].size() == 3, "T003 uses the three-step Typst formula sequence")
		for step in explanation["steps"]:
			t.check(FileAccess.file_exists(String(step["formula_asset"])), "T003 Typst formula asset exists")
	var subtitles := SubtitleTrack.load_path("res://content/subtitles/s01e04-impact-force-curve.srt")
	t.check(subtitles["ok"], "T003 editorial subtitles parse")
	if subtitles["ok"]:
		t.check(subtitles["cues"].size() >= 80, "T003 exact narration subtitles cover the complete episode")
		var final_cue: Dictionary = subtitles["cues"][-1]
		t.check_close(float(final_cue["end_sec"]), 220.0, 0.001, "T003 editorial subtitles end with the episode")
