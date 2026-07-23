extends RefCounted

const EpisodeLoader = preload("res://src/core/episode_loader.gd")
const EpisodeHud = preload("res://src/video/episode_hud.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")
const FormulaRenderer = preload("res://src/video/formula_renderer.gd")

const EXPECTED_ROLE_SIZES := {
	VideoTypography.HERO: 56,
	VideoTypography.ACCENT: 40,
	VideoTypography.DISPLAY: 48,
	VideoTypography.TITLE: 28,
	VideoTypography.SECTION: 26,
	VideoTypography.BODY: 30,
	VideoTypography.SUBTITLE: 30,
	VideoTypography.DATA: 22,
	VideoTypography.DATA_META: 16,
	VideoTypography.META: 16,
	VideoTypography.FORMULA_MAIN: 56,
	VideoTypography.FORMULA_STEP: 36,
	VideoTypography.FORMULA_META: 20,
}


func run(t) -> void:
	t.check(VideoTypography.theme() != null, "video typography theme loads")
	t.check(
		VideoTypography.regular().resource_path.ends_with("SarasaGothicSC-Regular.ttf"),
		"narrative body uses Sarasa Gothic SC"
	)
	t.check(
		VideoTypography.data().resource_path.ends_with("SarasaMonoSC-SemiBold.ttf"),
		"data role uses Sarasa Mono SC"
	)
	t.check(
		VideoTypography.personality().resource_path.ends_with("SmileySans-Oblique.ttf"),
		"personality roles use bundled Smiley Sans"
	)
	t.check(
		FileAccess.file_exists("res://assets/fonts/SmileySans-LICENSE.txt"),
		"Smiley Sans license is bundled"
	)
	var hero_font: Font = VideoTypography.theme().get_font("font", VideoTypography.HERO)
	t.check(hero_font is FontVariation, "hero role wraps Smiley Sans with a fallback")
	if hero_font is FontVariation:
		var hero_variation := hero_font as FontVariation
		t.check(
			hero_variation.base_font == VideoTypography.personality(),
			"hero role keeps Smiley Sans as the primary face"
		)
		t.check(
			hero_variation.fallbacks.has(VideoTypography.bold()),
			"hero role falls back to Sarasa Gothic for missing glyphs"
		)
	var role_label := Label.new()
	VideoTypography.apply_role(role_label, VideoTypography.SUBTITLE)
	t.check(role_label.theme == VideoTypography.theme(), "typography role applies shared theme")
	t.check(
		role_label.theme_type_variation == VideoTypography.SUBTITLE,
		"typography role applies canonical type variation"
	)
	role_label.free()
	for role in EXPECTED_ROLE_SIZES:
		t.check(
			VideoTypography.size_for(role) == EXPECTED_ROLE_SIZES[role],
			"typography role has canonical size: %s" % role
		)
	t.check(
		VideoTypography.theme().get_font("font", VideoTypography.FORMULA_MAIN) == VideoTypography.data(),
		"main equation uses Sarasa Mono SC"
	)
	t.check(
		VideoTypography.theme().get_font("font", VideoTypography.FORMULA_STEP) == VideoTypography.medium(),
		"formula concept uses Sarasa Gothic SC"
	)

	var hud := EpisodeHud.new()
	hud._build_ui()
	t.check(
		hud.question_label.theme_type_variation == VideoTypography.HERO,
		"opening question uses the personality hero role"
	)
	t.check(
		hud.result_callout_label.theme_type_variation == VideoTypography.ACCENT,
		"winner callout uses the personality accent role"
	)
	t.check(
		hud.explain_title_label.theme_type_variation == VideoTypography.DISPLAY,
		"scientific explanation stays in Sarasa display"
	)
	t.check(
		hud.subtitle_label.theme_type_variation == VideoTypography.SUBTITLE,
		"continuous subtitles stay in Sarasa Gothic"
	)
	hud.free()

	var episode_one: Dictionary = EpisodeLoader.load_path(
		"res://content/episodes/s01e01-angle-sweep.json"
	)["episode"]
	var episode_two: Dictionary = EpisodeLoader.load_path(
		"res://content/episodes/s01e02-stretch-sweep.json"
	)["episode"]
	var formula := FormulaRenderer.new()
	formula._build_ui()
	formula.configure(episode_two["story"]["explanation"], episode_two["theme"]["colors"])
	formula.set_step(2)
	t.check(formula.step_index == 2, "formula renderer selects an explicit derivation step")
	t.check(formula.concept_label.text == "同高理想模型：储能 ×4，射程 ×4", "formula renderer leads with a specific model claim")
	t.check(formula.formula_label.text == "E × 4 → v² × 4 → R × 4", "formula renderer keeps an accessible text fallback")
	if FileAccess.file_exists(episode_two["story"]["explanation"]["steps"][2]["formula_asset"]):
		t.check(formula.formula_texture.texture != null, "formula renderer loads the generated Typst SVG")
		t.check(formula.formula_texture.visible, "Typst formula is the visible production layer")
		t.check(not formula.formula_label.visible, "text fallback stays hidden when SVG is available")
	else:
		t.check(formula.formula_label.visible, "text fallback works before formula assets are built")
	t.check(
		formula.formula_label.theme_type_variation == VideoTypography.FORMULA_MAIN,
		"main equation uses the dedicated formula role"
	)
	var formula_size := VideoTypography.data().get_string_size(
		formula.formula_label.text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		VideoTypography.size_for(VideoTypography.FORMULA_MAIN)
	)
	t.check(formula_size.x <= formula.formula_label.size.x, "longest production equation fits formula panel")
	formula.free()
	for episode in [episode_one, episode_two]:
		var identity_text := "%s  ·  S%02dE%02d  /  %s" % [
			episode["series"],
			episode["season"],
			episode["episode"],
			episode["story"]["identity_label"],
		]
		var identity_size := VideoTypography.medium().get_string_size(
			identity_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			VideoTypography.size_for(VideoTypography.TITLE)
		)
		t.check(identity_size.x <= 970.0, "single-line identity fits: %s" % episode["id"])
		var question_size := hero_font.get_multiline_string_size(
			episode["question"],
			HORIZONTAL_ALIGNMENT_CENTER,
			EpisodeLayout.QUESTION_RECT.size.x,
			VideoTypography.size_for(VideoTypography.HERO)
		)
		t.check(
			question_size.y <= EpisodeLayout.QUESTION_RECT.size.y,
			"hero question fits its reserved region: %s" % episode["id"]
		)
		for beat in episode["beats"]:
			if beat["phase"] != "QUESTION" or String(beat["headline"]).is_empty():
				continue
			var headline_size := hero_font.get_multiline_string_size(
				beat["headline"],
				HORIZONTAL_ALIGNMENT_CENTER,
				EpisodeLayout.QUESTION_RECT.size.x,
				VideoTypography.size_for(VideoTypography.HERO)
			)
			t.check(
				headline_size.x <= EpisodeLayout.QUESTION_RECT.size.x
				and headline_size.y <= EpisodeLayout.QUESTION_RECT.size.y,
				"opening headline fits: %s/%s" % [episode["id"], beat["id"]]
			)
		for step in episode["story"]["explanation"]["steps"]:
			t.check(not String(step["typst"]).is_empty(), "Typst source exists: %s" % episode["id"])
			t.check(
				String(step["formula_asset"]).ends_with(".svg"),
				"formula build path exists in schema: %s" % step["formula_asset"]
			)
			var equation_size := VideoTypography.data().get_string_size(
				step["equation"],
				HORIZONTAL_ALIGNMENT_CENTER,
				-1,
				VideoTypography.size_for(VideoTypography.FORMULA_MAIN)
			)
			t.check(
				equation_size.x <= 900.0,
				"production equation fits: %s/%s" % [episode["id"], step["equation"]]
			)
	var colors: Dictionary = episode_one["theme"]["colors"]
	t.check(episode_one["theme_path"] == episode_two["theme_path"], "episodes share one theme")
	t.check(
		_contrast_ratio(colors["text"], colors["background"]) >= 7.0,
		"primary text exceeds enhanced contrast target"
	)
	t.check(
		_contrast_ratio(colors["muted"], colors["background"]) >= 7.0,
		"secondary text exceeds enhanced contrast target"
	)
	t.check(
		episode_one["variants"][0]["color"] == episode_two["variants"][0]["color"],
		"both sweeps share the same low endpoint color"
	)
	t.check(
		episode_one["variants"][-1]["color"] == episode_two["variants"][-1]["color"],
		"both sweeps share the same high endpoint color"
	)
	for episode in [episode_one, episode_two]:
		for variant in episode["variants"]:
			t.check(
				_contrast_ratio(variant["color"], colors["background"]) >= 4.5,
				"data color remains legible on the stage: %s" % variant["label"]
			)


func _contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance := _relative_luminance(first)
	var second_luminance := _relative_luminance(second)
	return (
		maxf(first_luminance, second_luminance) + 0.05
	) / (
		minf(first_luminance, second_luminance) + 0.05
	)


func _relative_luminance(color: Color) -> float:
	return (
		0.2126 * _linear_channel(color.r)
		+ 0.7152 * _linear_channel(color.g)
		+ 0.0722 * _linear_channel(color.b)
	)


func _linear_channel(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)
