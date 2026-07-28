extends Control

var progress := 0.0
var primary_color := Color("#F2F0E9")
var muted_color := Color("#A9ADB4")
var accent_color := Color("#F0B35A")


func configure(primary: Color, muted: Color, accent: Color) -> void:
	primary_color = primary
	muted_color = muted
	accent_color = accent
	queue_redraw()


func set_progress(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, progress):
		return
	progress = next
	queue_redraw()


func _draw() -> void:
	if progress <= 0.001 or size.x <= 1.0 or size.y <= 1.0:
		return
	var origin := Vector2(size.x * 0.12, size.y * 0.76)
	var finish := Vector2(size.x * 0.88, size.y * 0.76)
	var base_alpha := smoothstep(0.0, 0.35, progress) * 0.42
	draw_line(
		origin - Vector2(size.x * 0.03, 0.0),
		finish + Vector2(size.x * 0.04, 0.0),
		Color(muted_color, base_alpha),
		maxf(1.0, size.y * 0.025),
		true
	)
	draw_circle(origin, maxf(1.8, size.y * 0.052), Color(accent_color, minf(1.0, progress * 4.0)))

	var curve_progress := smoothstep(0.10, 0.74, progress)
	var points := PackedVector2Array()
	var sample_count := 28
	var visible_count := clampi(int(ceil(sample_count * curve_progress)), 2, sample_count)
	for index in range(visible_count):
		var u := float(index) / float(sample_count - 1)
		var x := lerpf(origin.x, finish.x, u)
		var y := origin.y - size.y * 0.52 * 4.0 * u * (1.0 - u)
		points.append(Vector2(x, y))
	draw_polyline(points, Color(primary_color, 0.90), maxf(1.3, size.y * 0.032), true)
	if not points.is_empty():
		draw_circle(points[-1], maxf(1.7, size.y * 0.048), Color(accent_color, 0.96))

	var landing_alpha := smoothstep(0.68, 0.92, progress)
	draw_line(
		finish - Vector2(0.0, size.y * 0.13),
		finish + Vector2(0.0, size.y * 0.10),
		Color(muted_color, landing_alpha * 0.80),
		maxf(1.0, size.y * 0.024),
		true
	)
