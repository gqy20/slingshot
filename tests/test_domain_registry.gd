extends RefCounted

const DomainRegistry = preload("res://src/core/domain_registry.gd")
const RunRecord = preload("res://src/core/run_record.gd")


func run(test) -> void:
	var models := DomainRegistry.model_ids()
	test.check(models == ["rigidbody", "projectile_drag", "impact_pulse", "track_race"], "domain registry exposes stable model order")
	test.check(DomainRegistry.has_model("rigidbody"), "projectile domain owns rigidbody")
	test.check(DomainRegistry.has_model("projectile_drag"), "projectile domain owns drag model")
	test.check(DomainRegistry.has_model("impact_pulse"), "impact domain owns pulse model")
	test.check(DomainRegistry.has_model("track_race"), "track domain owns path-race model")
	test.check(not DomainRegistry.has_model("unknown"), "unknown model is rejected")

	var projectile = DomainRegistry.for_model("projectile_drag")
	var impact = DomainRegistry.for_model("impact_pulse")
	test.check(projectile != null and projectile.supports_model("rigidbody"), "projectile models share one domain")
	test.check(impact != null and not impact.supports_model("rigidbody"), "impact domain stays isolated")
	test.check(projectile.canvas_script() != impact.canvas_script(), "domains select isolated canvas entry points")
	test.check(not projectile.is_offline_model("rigidbody"), "rigidbody keeps live physics runner")
	test.check(projectile.is_offline_model("projectile_drag"), "drag uses domain-owned offline simulation")
	test.check(impact.is_offline_model("impact_pulse"), "impact uses domain-owned offline simulation")

	var impact_config: Dictionary = impact.normalize_simulation({"model": "impact_pulse", "pulse_sample_rate_hz": 30})
	test.check(not impact_config["ok"], "impact domain rejects unsafe sample rates")
	var projectile_config: Dictionary = projectile.normalize_simulation({"model": "projectile_drag", "pulse_sample_rate_hz": 10000})
	test.check(not projectile_config["ok"], "projectile domain rejects impact-only configuration")
	test.check(not RunRecord.validate_bundle({})["ok"], "run record rejects missing schema contract")
