// 画面効果：ざらつき（フィルムの粒）、色の段数を減らすディザ、周辺を暗くする、色味。下に描かれた画面を読んで上書きする。
// 値は view/look.gd から渡す。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float grain = 0.06;
uniform float levels = 12.0;
uniform float dither = 1.0;
uniform float vignette = 0.6;
uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float cell = 3.0;

const float BAYER[16] = {
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
};

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * tint.rgb;
	vec2 px = floor(FRAGCOORD.xy / cell);
	// ざらつき：毎秒24回変わる粒
	c += (hash(px + floor(TIME * 24.0) * 17.0) - 0.5) * grain;
	// ディザしながら色の段数を減らす
	int i = int(mod(px.x, 4.0)) + int(mod(px.y, 4.0)) * 4;
	float b = BAYER[i] / 16.0 - 0.5;
	c = floor(c * levels + 0.5 + b * dither) / levels;
	// 周辺を暗く
	vec2 d = SCREEN_UV - 0.5;
	c *= clamp(1.0 - dot(d, d) * vignette * 2.0, 0.0, 1.0);
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
