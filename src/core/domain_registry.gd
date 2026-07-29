class_name SlingshotDomainRegistry
extends RefCounted

const ProjectileDomain = preload("res://src/domains/projectile_domain.gd")
const ImpactDomain = preload("res://src/domains/impact_domain.gd")
const TrackRaceDomain = preload("res://src/domains/track_race_domain.gd")

const DOMAINS := [ProjectileDomain, ImpactDomain, TrackRaceDomain]


static func for_model(model: String) -> Variant:
	for domain in DOMAINS:
		if domain.supports_model(model):
			return domain
	return null


static func has_model(model: String) -> bool:
	return for_model(model) != null


static func model_ids() -> Array[String]:
	var result: Array[String] = []
	for domain in DOMAINS:
		for model in domain.model_ids():
			result.append(String(model))
	return result
