class_name SlingshotFormulaAsset
extends RefCounted

static var _texture_cache: Dictionary = {}


static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.new()
		var svg_source := FileAccess.get_file_as_string(path)
		if not svg_source.is_empty() and image.load_svg_from_string(svg_source, 1.0) == OK:
			texture = ImageTexture.create_from_image(image)
	if texture != null:
		_texture_cache[path] = texture
	return texture


static func fit_rect(texture: Texture2D, bounds: Rect2) -> Rect2:
	if texture == null:
		return Rect2(bounds.get_center(), Vector2.ZERO)
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return Rect2(bounds.get_center(), Vector2.ZERO)
	var fit_scale := minf(bounds.size.x / source_size.x, bounds.size.y / source_size.y)
	var fitted_size := source_size * fit_scale
	return Rect2(bounds.get_center() - fitted_size * 0.5, fitted_size)
