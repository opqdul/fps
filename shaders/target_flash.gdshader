shader_type spatial;

// Targets glow with a slow pulse; when hit, the "flash" uniform (set from
// target.gd) pushes them toward white-hot, then the script fades it back.
uniform vec4 base_color : source_color = vec4(0.9, 0.25, 0.2, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float pulse = 0.5 + 0.5 * sin(TIME * 2.5);
	vec3 col = mix(base_color.rgb, vec3(1.0), flash * 0.7);
	ALBEDO = col;
	EMISSION = base_color.rgb * pulse * 0.35 + col * flash * 1.5;
}
