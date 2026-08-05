shader_type canvas_item;

uniform float longitude_offset = 0.0;
uniform vec3 light_direction = vec3(-0.45, -0.28, 0.85);
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 average_color : source_color = vec4(0.15, 0.28, 0.46, 1.0);
uniform vec4 rim_color : source_color = vec4(0.35, 0.68, 1.0, 1.0);
uniform float minimum_light : hint_range(0.0, 1.0) = 0.16;
uniform float detail_mix : hint_range(0.0, 1.0) = 1.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.55;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius_squared = dot(p, p);
	if (radius_squared > 1.0) {
		discard;
	}
	float z = sqrt(max(0.0, 1.0 - radius_squared));
	float longitude = atan(p.x, z) / (2.0 * 3.14159265359) + 0.5 + longitude_offset;
	float latitude = asin(clamp(-p.y, -1.0, 1.0)) / 3.14159265359 + 0.5;
	vec3 sampled = texture(TEXTURE, vec2(fract(longitude), latitude)).rgb;
	vec3 base = mix(average_color.rgb, sampled, detail_mix) * tint.rgb;
	vec3 normal = normalize(vec3(p.x, -p.y, z));
	float facing_light = dot(normal, normalize(light_direction));
	float diffuse = mix(minimum_light, 1.0, smoothstep(-0.18, 0.82, facing_light));
	float limb = pow(1.0 - z, 2.6);
	vec3 color = base * diffuse + rim_color.rgb * limb * rim_strength;
	float alpha = 1.0 - smoothstep(0.985, 1.0, sqrt(radius_squared));
	COLOR = vec4(color, alpha);
}
