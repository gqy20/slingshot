extends SceneTree

const MAX_MEAN_DELTA := 0.006
const MAX_CHANGED_PIXEL_RATIO := 0.01
const CHANGED_PIXEL_DELTA := 0.04


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: compare_images.gd <baseline.png> <actual.png>")
		quit(2)
		return
	var baseline := Image.load_from_file(args[0])
	var actual := Image.load_from_file(args[1])
	if baseline == null or baseline.is_empty() or actual == null or actual.is_empty():
		printerr("visual-regression: failed to load input images")
		quit(2)
		return
	if baseline.get_size() != actual.get_size():
		printerr(
			"visual-regression: size mismatch baseline=%s actual=%s"
			% [baseline.get_size(), actual.get_size()]
		)
		quit(1)
		return
	baseline.convert(Image.FORMAT_RGBA8)
	actual.convert(Image.FORMAT_RGBA8)
	var total_delta := 0.0
	var changed_pixels := 0
	var pixel_count := baseline.get_width() * baseline.get_height()
	for y in range(baseline.get_height()):
		for x in range(baseline.get_width()):
			var expected := baseline.get_pixel(x, y)
			var observed := actual.get_pixel(x, y)
			var delta := (
				absf(expected.r - observed.r)
				+ absf(expected.g - observed.g)
				+ absf(expected.b - observed.b)
			) / 3.0
			total_delta += delta
			if delta > CHANGED_PIXEL_DELTA:
				changed_pixels += 1
	var mean_delta := total_delta / float(pixel_count)
	var changed_ratio := float(changed_pixels) / float(pixel_count)
	print(
		"visual-regression: mean_delta=%.6f changed_ratio=%.6f"
		% [mean_delta, changed_ratio]
	)
	quit(0 if mean_delta <= MAX_MEAN_DELTA and changed_ratio <= MAX_CHANGED_PIXEL_RATIO else 1)
