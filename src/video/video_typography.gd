class_name SlingshotVideoTypography
extends RefCounted

const BUNDLED_FONT: FontFile = preload("res://assets/fonts/NotoSansSC-VF.otf")
const VIDEO_THEME: Theme = preload("res://assets/video_typography.tres")


static func regular() -> FontVariation:
	return _font(400)


static func medium() -> FontVariation:
	return _font(600)


static func bold() -> FontVariation:
	return _font(700)


static func theme() -> Theme:
	return VIDEO_THEME


static func _font(weight: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = BUNDLED_FONT
	font.variation_opentype = {"wght": float(weight)}
	return font
