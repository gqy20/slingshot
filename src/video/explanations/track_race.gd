class_name TrackRaceExplanation
extends RefCounted


func hides_physical_stage() -> bool:
	return false


func draw(_canvas, _opacity: float = 1.0) -> void:
	# The track-race canvas owns the spatial explanation. Formula assets still
	# use the shared Typst contract and are rendered inside its reserved panels.
	pass
