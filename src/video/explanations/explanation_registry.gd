class_name SlingshotExplanationRegistry
extends RefCounted

const ExplanationCatalog = preload("res://src/core/explanation_catalog.gd")
const AngleComponents = preload("res://src/video/explanations/angle_components.gd")
const SpringEnergy = preload("res://src/video/explanations/spring_energy.gd")
const DragEffect = preload("res://src/video/explanations/drag_effect.gd")
const ImpactImpulse = preload("res://src/video/explanations/impact_impulse.gd")
const TrackRace = preload("res://src/video/explanations/track_race.gd")

const MODULES := {
	ExplanationCatalog.ANGLE_COMPONENTS: AngleComponents,
	ExplanationCatalog.SPRING_ENERGY: SpringEnergy,
	ExplanationCatalog.DRAG_EFFECT: DragEffect,
	ExplanationCatalog.IMPACT_IMPULSE: ImpactImpulse,
	ExplanationCatalog.TRACK_RACE: TrackRace,
}


static func has_module(module_id: String) -> bool:
	return MODULES.has(module_id)


static func create(module_id: String) -> RefCounted:
	var script: Variant = MODULES.get(module_id)
	if script == null:
		return null
	return script.new()


static func module_ids() -> Array[String]:
	var result: Array[String] = []
	for module_id in MODULES.keys():
		result.append(String(module_id))
	result.sort()
	return result
