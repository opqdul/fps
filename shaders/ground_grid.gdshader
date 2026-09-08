shader_type spatial;

// Flat concrete floor with a subtle grid and slight checker variation so
// looking down reads as depth instead of an empty blue gradient.
uniform vec4 base_color : source_color = vec4(0.45, 0.44, 0.42, 1.0);
uniform vec4 line_color : source_color = vec4(0.18, 0.18, 0.2, 0.65);
uniform float grid_size = 1.0;

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 cell = fract(world.xz / grid_size) - 0.5;
	float line = 1.0 - smoothstep(0.4, 0.5, max(abs(cell.x), abs(cell.y)));
	float checker = mod(floor(world.x / grid_size) + floor(world.z / grid_size), 2.0);
	vec3 col = mix(base_color.rgb, base_color.rgb * 0.9, checker);
	col = mix(col, line_color.rgb, line * line_color.a);
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
