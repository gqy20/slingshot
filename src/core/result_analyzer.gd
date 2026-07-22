class_name SlingshotResultAnalyzer
extends RefCounted


static func analyze(episode: Dictionary, bundle: Dictionary) -> Dictionary:
	var story: Dictionary = episode["story"]
	var metric: String = story["primary_metric"]
	var goal: String = story["goal"]
	var rows: Array = []
	var winner_id := ""
	var winner_value := -INF if goal == "max" else INF
	for record_value in bundle.get("records", []):
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		var metrics: Dictionary = record.get("metrics", {})
		var value := float(metrics.get(metric, 0.0))
		var better := value > winner_value if goal == "max" else value < winner_value
		if winner_id.is_empty() or better:
			winner_id = String(record.get("variant_id", ""))
			winner_value = value
		rows.append({
			"variant_id": record.get("variant_id", ""),
			"label": record.get("label", ""),
			"color_html": record.get("color_html", "FFFFFF"),
			"value": value,
			"metrics": metrics.duplicate(true),
		})
	return {
		"primary_metric": metric,
		"metric_label": story["metric_label"],
		"metric_unit": story["metric_unit"],
		"goal": goal,
		"winner_id": winner_id,
		"winner_value": winner_value,
		"rows": rows,
		"conclusion": story["conclusion"],
	}
