class_name SlingshotCameraRig
extends Camera2D

var impact_elapsed := -1.0
var shake_seed := 1


func _ready() -> void:
	position = Vector2(960, 540)
	position_smoothing_enabled = false


func trigger_impact(seed_value: int) -> void:
	shake_seed = seed_value
	impact_elapsed = 0.0


func reset_effects() -> void:
	impact_elapsed = -1.0
	zoom = Vector2.ONE
	offset = Vector2.ZERO


func _process(delta: float) -> void:
	if impact_elapsed < 0.0:
		return
	impact_elapsed += delta
	var decay := maxf(0.0, 1.0 - impact_elapsed / 1.1)
	var phase_value := float(shake_seed % 97)
	offset = Vector2(
		sin(impact_elapsed * 71.0 + phase_value) * 18.0,
		cos(impact_elapsed * 83.0 + phase_value * 0.7) * 13.0
	) * decay
	var zoom_amount := 1.0 + sin(minf(impact_elapsed / 0.8, 1.0) * PI) * 0.08
	zoom = Vector2.ONE * zoom_amount
	if impact_elapsed >= 1.1:
		reset_effects()
