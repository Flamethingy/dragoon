shader_type canvas_item;
// Swaps the flat colours of hand-drawn art for new ones (Tamago's fur, hair ...).
// Every pixel is treated as a blend of two known colours (an anti-aliased edge between fur
// and outline, a highlight in the eye ...), so edges are recoloured just as cleanly.
// Pixels that aren't such a blend (shading, other colours) stay as drawn.

const int MAX_KEYS = 8;
// source_color: Godot converts them to the space the texture is sampled in.
uniform vec4 from_colors[MAX_KEYS] : source_color;
uniform vec4 to_colors[MAX_KEYS] : source_color;
uniform int count = 0;
uniform float tolerance = 0.06;

// In fragment() COLOR already holds the texture, so keep the plain tint (modulate) here.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (count > 0 && c.a > 0.0) {
		float best = 1e9;
		vec3 result = c.rgb;
		for (int i = 0; i < MAX_KEYS; i++) {
			if (i >= count) break;
			for (int j = i; j < MAX_KEYS; j++) {
				if (j >= count) break;
				vec3 d = from_colors[i].rgb - from_colors[j].rgb;
				float s = j == i ? 1.0 : clamp(dot(c.rgb - from_colors[j].rgb, d) / max(dot(d, d), 1e-6), 0.0, 1.0);
				float e = distance(c.rgb, from_colors[j].rgb + s * d);
				if (e < best) {
					best = e;
					result = mix(to_colors[j].rgb, to_colors[i].rgb, s);
				}
			}
		}
		if (best < tolerance) {
			c.rgb = result;
		}
	}
	COLOR = c * tint;
}
