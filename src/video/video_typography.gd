class_name SlingshotVideoTypography
extends RefCounted

const GOTHIC_REGULAR: FontFile = preload(
	"res://assets/fonts/SarasaGothicSC-Regular.ttf"
)
const GOTHIC_SEMIBOLD: FontFile = preload(
	"res://assets/fonts/SarasaGothicSC-SemiBold.ttf"
)
const GOTHIC_BOLD: FontFile = preload(
	"res://assets/fonts/SarasaGothicSC-Bold.ttf"
)
const MONO_SEMIBOLD: FontFile = preload(
	"res://assets/fonts/SarasaMonoSC-SemiBold.ttf"
)
const SMILEY_OBLIQUE: FontFile = preload(
	"res://assets/fonts/SmileySans-Oblique.ttf"
)
const VIDEO_THEME: Theme = preload("res://assets/video_typography.tres")

const HERO: StringName = &"VideoHero"
const ACCENT: StringName = &"VideoAccent"
const DISPLAY: StringName = &"VideoDisplay"
const TITLE: StringName = &"VideoTitle"
const SECTION: StringName = &"VideoSection"
const BODY: StringName = &"VideoBody"
const SUBTITLE: StringName = &"VideoSubtitle"
const DATA: StringName = &"VideoData"
const DATA_META: StringName = &"VideoDataMeta"
const META: StringName = &"VideoMeta"

const ROLE_SIZES := {
	HERO: 56,
	ACCENT: 40,
	DISPLAY: 48,
	TITLE: 28,
	SECTION: 26,
	BODY: 30,
	SUBTITLE: 30,
	DATA: 22,
	DATA_META: 16,
	META: 16,
}


static func regular() -> FontFile:
	return GOTHIC_REGULAR


static func medium() -> FontFile:
	return GOTHIC_SEMIBOLD


static func bold() -> FontFile:
	return GOTHIC_BOLD


static func data() -> FontFile:
	return MONO_SEMIBOLD


static func personality() -> FontFile:
	return SMILEY_OBLIQUE


static func theme() -> Theme:
	return VIDEO_THEME


static func apply_role(label: Label, role: StringName) -> void:
	assert(ROLE_SIZES.has(role), "unknown video typography role: %s" % role)
	label.theme = VIDEO_THEME
	label.theme_type_variation = role


static func size_for(role: StringName) -> int:
	return int(ROLE_SIZES.get(role, 30))
