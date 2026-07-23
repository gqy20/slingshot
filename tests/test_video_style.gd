extends RefCounted

const EpisodeLoader = preload("res://src/core/episode_loader.gd")
const EpisodeHud = preload("res://src/video/episode_hud.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const VideoTypography = preload("res://src/video/video_typography.gd")

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
	for episode in [episode_one, episode_two]:
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
