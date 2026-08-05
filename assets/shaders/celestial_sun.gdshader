shader_type canvas_item;

uniform vec2 source_center = vec2(0.5, 0.465);
uniform vec2 source_radius = vec2(0.435, 0.435);
uniform vec4 average_color : source_color = vec4(1.0, 0.43, 0.08, 1.0);
uniform vec4 tint : source_color = vec4(1.0, 0.88, 0.68, 1.0);
uniform float detail_mix : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float distance_from_center = length(p);
	if (distance_from_center > 1.0) {
		discard;
	}
	vec2 source_uv = source_center + p * source_radius;
	vec3 sampled = texture(TEXTURE, source_uv).rgb;
	vec3 base = mix(average_color.rgb, sampled, detail_mix);
	float center_lift = 1.0 + 0.10 * (1.0 - distance_from_center);
	vec3 color = base * tint.rgb * center_lift;
	float alpha = 1.0 - smoothstep(0.975, 1.0, distance_from_center);
	COLOR = vec4(color, alpha);
}
