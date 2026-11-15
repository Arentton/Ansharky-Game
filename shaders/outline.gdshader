shader_type canvas_item;
// Пиксельная обводка спрайта. Включается параметром `enabled`.

uniform bool enabled = false;
uniform vec4 outline_color : source_color = vec4(1.0, 0.86, 0.15, 1.0);
uniform float pulse_speed = 5.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (enabled && c.a < 0.5) {
		vec2 s = TEXTURE_PIXEL_SIZE;
		float a = texture(TEXTURE, UV + vec2(s.x, 0.0)).a
			+ texture(TEXTURE, UV - vec2(s.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, s.y)).a
			+ texture(TEXTURE, UV - vec2(0.0, s.y)).a;
		if (a > 0.5) {
			float p = 0.75 + 0.25 * sin(TIME * pulse_speed);
			c = vec4(outline_color.rgb, outline_color.a * p);
		}
	}
	COLOR = c;
}
