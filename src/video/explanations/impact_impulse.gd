class_name ImpactImpulseExplanation
extends RefCounted


func hides_physical_stage() -> bool:
	return false


func draw(_canvas, _opacity: float = 1.0) -> void:
	# The impact episode owns its left-side force plot. The shared HUD renders
	# the Typst formula asset on the right, using the same explanation contract
	# as EP03.
	pass
