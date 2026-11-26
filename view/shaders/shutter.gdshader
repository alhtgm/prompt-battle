// 出撃のシャッターの板金。板（不ぞろいの幅）、継ぎ目の影と上の縁のハイライト、色むら・錆・こすれ傷・油じみ、
// へこんだ板、継ぎ当てとリベット、錆びた下枠と古びた警告の縞、上からの電球の光、ほこりを、低い解像度で描く。
// 最後に post_grime.gdshader と同じ計算でざらつきとディザをかける（画面を読み直さず、この絵だけにかける）。
// 値はすべて view/shutter.gd が view/look.gd から渡す。乱数は使わず、ノイズの模様（種は固定）と式だけで作る。
shader_type canvas_item;

const int MAX_SLATS = 48;
const int MAX_DUST = 64;

uniform vec2 rect_size = vec2(1280.0, 744.0);
uniform float shrink = 3.0;
uniform sampler2D noise_large : filter_nearest, repeat_enable;
uniform sampler2D noise_fine : filter_nearest, repeat_enable;

// 板：下枠の上から数えた、各板の下の端の高さ（点）。slat_count 枚
uniform float slat_bottom[MAX_SLATS];
uniform float slat_height[MAX_SLATS];
uniform int slat_count = 0;

uniform vec4 steel : source_color = vec4(0.15, 0.148, 0.14, 1.0);
uniform float gap_px = 4.0;
uniform float gap_dark = 0.9;
uniform float highlight = 0.35;
uniform float slat_shade = 0.35;
uniform float mottle = 0.35;
uniform vec4 rust_color : source_color = vec4(0.3, 0.13, 0.06, 1.0);
uniform float rust_strength = 0.85;
uniform float rust_threshold = 0.55;
uniform float rust_edge_px = 10.0;
uniform float scratch_threshold = 0.7;
uniform float scratch = 0.12;
uniform float oil_threshold = 0.68;
uniform float oil_dark = 0.55;
// へこみ：4つずつ (板の番号, 中心x, 広がり, 強さ)。x と広がりは点
uniform float dents[16];
uniform int dent_count = 0;
// 継ぎ当て：4つずつ (下の板, 上の板, 左端, 右端)。左右は点
uniform float patches[16];
uniform int patch_count = 0;
uniform vec4 patch_tint = vec4(1.25, 1.3, 1.36, 1.0);
uniform float dent_shade = 1.8;
uniform float dent_warp_px = 5.0;
uniform float rivet_px = 3.0;

uniform float frame_px = 48.0;
uniform vec4 frame_steel : source_color = vec4(0.12, 0.105, 0.095, 1.0);
uniform float stripe_px = 26.0;
uniform vec4 stripe_a : source_color = vec4(0.4, 0.31, 0.14, 1.0);
uniform vec4 stripe_b : source_color = vec4(0.055, 0.05, 0.045, 1.0);
uniform float stripe_fray_px = 6.0;
uniform float peel_threshold = 0.6;

uniform float light_top = 1.15;
uniform float light_bottom = 0.4;
uniform float light_side = 0.55;
// 画面の高さと、この絵の上の端の画面上の位置（点）。光は画面に固定し、シャッターが動くと光の中を通る
uniform float screen_h = 720.0;
uniform float screen_w = 1280.0;
uniform float rect_screen_y = 0.0;

// ほこり：(x, y, 大きさ, 濃さ)。位置は点
uniform vec4 dust[MAX_DUST];
uniform int dust_count = 0;
uniform vec4 dust_color : source_color = vec4(0.46, 0.44, 0.4, 1.0);

// ざらつきとディザ（post_grime.gdshader と同じ）。grain_time は粒が変わる時刻
uniform float grain = 0.05;
uniform float levels = 16.0;
uniform float dither = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.93, 0.82, 1.0);
uniform float grain_time = 0.0;

const float BAYER[16] = {
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
};

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float n_large(vec2 p) {
	return texture(noise_large, p / 512.0).r;
}

float n_fine(vec2 p) {
	return texture(noise_fine, p / 256.0).r;
}

// 錆を重ねる。edge は 0〜1（1 で縁のすぐ近く）
vec3 add_rust(vec3 c, vec2 p, float edge, float extra) {
	float r = n_fine(p * 1.3 + vec2(31.0, 7.0));
	float m = r * 0.5 + n_large(p + vec2(200.0, 90.0)) * 0.25 + edge * 0.6 + extra;
	float a = smoothstep(rust_threshold, rust_threshold + 0.18, m) * rust_strength;
	vec3 rc = rust_color.rgb * (0.55 + 0.9 * r);
	return mix(c, rc, a);
}

void fragment() {
	// 低い解像度：点を shrink 個ずつまとめ、まとめた中は同じ色にする（シャッターと一緒に動くので模様は泳がない）
	vec2 local = UV * rect_size;
	vec2 cellp = floor(local / shrink);
	vec2 p = cellp * shrink + shrink * 0.5;
	float yb = rect_size.y - p.y;  // 下の端からの高さ
	vec3 c;

	if (yb < frame_px) {
		// ---- 下枠：錆びた角材に、はげかけた縞が塗ってある ----
		float v = yb / frame_px;  // 0 が下、1 が上
		c = frame_steel.rgb * (0.75 + 0.5 * n_large(p * 2.0));
		float face = step(4.0, yb) * step(yb, frame_px - 5.0);
		float fray = (n_fine(p * 2.2 + vec2(5.0, 61.0)) - 0.5) * stripe_fray_px;
		float s = fract((p.x + yb + fray) / (stripe_px * 2.0));
		vec3 paint = s < 0.5 ? stripe_a.rgb : stripe_b.rgb;
		paint *= 0.8 + 0.35 * n_large(p * 3.0 + vec2(17.0, 3.0));
		float peel = smoothstep(peel_threshold, peel_threshold + 0.08, n_fine(p * 0.9 + vec2(77.0, 13.0)) * 0.7 + n_large(p * 1.5) * 0.4);
		c = mix(c, paint, face * (1.0 - peel));
		c = add_rust(c, p, (1.0 - v) * 0.6 + peel * 0.5, 0.05);
		// 角材の上の面だけ光を受け、すぐ下に板の影が落ちる
		c *= 1.0 + step(frame_px - 3.0 - shrink, yb) * 0.5;
		c *= mix(0.55, 1.0, smoothstep(0.0, 0.25, v));
	} else {
		// ---- 板金 ----
		float y = yb - frame_px;
		int k = 0;
		for (int i = 0; i < MAX_SLATS; i++) {
			if (i >= slat_count) break;
			if (y >= slat_bottom[i]) k = i;
		}
		float h = slat_height[k];
		float yin = y - slat_bottom[k];  // 板の下の端からの高さ
		// へこみ：その板だけ陰影を変え、継ぎ目を少し歪ませる
		float bump = 0.0;
		for (int i = 0; i < 4; i++) {
			if (i >= dent_count) break;
			if (int(dents[i * 4] + 0.5) == k) {
				float d = (p.x - dents[i * 4 + 1]) / dents[i * 4 + 2];
				bump += exp(-d * d) * dents[i * 4 + 3];
			}
		}
		yin += bump * sin(yin / h * 3.14159) * dent_warp_px;
		float v = clamp(yin / h, 0.0, 1.0);
		c = steel.rgb;
		c *= mix(1.0 - mottle, 1.0 + mottle, n_large(p));
		// 継ぎ当て
		bool patched = false;
		vec4 pr = vec4(0.0);
		for (int i = 0; i < 4; i++) {
			if (i >= patch_count) break;
			vec4 q = vec4(patches[i * 4], patches[i * 4 + 1], patches[i * 4 + 2], patches[i * 4 + 3]);
			float y0 = slat_bottom[int(q.x + 0.5)];
			float y1 = slat_bottom[int(q.y + 0.5)] + slat_height[int(q.y + 0.5)];
			if (p.x >= q.z && p.x <= q.w && y >= y0 + 3.0 && y <= y1 - 3.0) {
				patched = true;
				pr = vec4(q.z, y0 + 3.0, q.w, y1 - 3.0);
			}
		}
		if (patched) {
			c *= patch_tint.rgb * (0.85 + 0.3 * n_fine(p * 0.7 + vec2(9.0, 40.0)));
			// 縁の影とリベット（四隅）
			float edge = min(min(p.x - pr.x, pr.z - p.x), min(y - pr.y, pr.w - y));
			c *= mix(0.45, 1.0, smoothstep(0.0, 4.0, edge));
			for (int cx = 0; cx < 2; cx++) {
				for (int cy = 0; cy < 2; cy++) {
					vec2 rc = vec2(cx == 0 ? pr.x + 7.0 : pr.z - 7.0, cy == 0 ? pr.y + 7.0 : pr.w - 7.0);
					vec2 dd = vec2(p.x, y) - rc;
					float r = length(dd);
					if (r < rivet_px + 1.5) {
						c = r < rivet_px ? steel.rgb * (1.2 + 0.6 * clamp(dd.y / rivet_px, -1.0, 1.0)) : c * 0.4;
					}
				}
			}
		}
		// 板の陰り（上から光が当たり、下へ行くほど暗い）とへこみの陰影
		c *= mix(1.0 - slat_shade, 1.0, v);
		c *= 1.0 + bump * (v - 0.5) * dent_shade;
		// こすれ傷（横に伸びた細い模様）と油じみ
		float sc = texture(noise_fine, vec2(p.x / 2400.0, p.y / 30.0)).r;
		c += smoothstep(scratch_threshold, scratch_threshold + 0.06, sc) * scratch * (0.5 + n_large(p * 1.7));
		float oil = n_large(p * 0.6 + vec2(400.0, 250.0));
		c *= 1.0 - smoothstep(oil_threshold, oil_threshold + 0.06, oil) * oil_dark;
		// 錆：板の下の縁と継ぎ目の近くに溜まる
		float edge = exp(-yin / rust_edge_px) + exp(-(h - yin) / (rust_edge_px * 0.5)) * 0.4;
		c = add_rust(c, p, edge, bump * 0.15 - (patched ? 0.3 : 0.0));  // 継ぎ当ては新しいので錆が少ない
		// 継ぎ目の溝（濃い影）と、上の縁の細いハイライト
		if (patched) {
			// 継ぎ当ては板の上に重ねてあるので、継ぎ目の溝は出さない
		} else if (yin < gap_px) {
			c *= 1.0 - gap_dark;
		} else if (h - yin < shrink) {
			c *= 1.0 + highlight;
		}
	}

	// ---- 光：上の電球。上が明るく下へ暗く、真ん中が明るく左右が暗い（画面に固定）----
	float sy = clamp((rect_screen_y + local.y) / screen_h, 0.0, 1.0);
	float sx = clamp(local.x / screen_w, 0.0, 1.0) - 0.5;
	float light = mix(light_top, light_bottom, sy) * (1.0 - light_side * pow(abs(sx) * 2.0, 2.0));
	c *= light;

	// ---- ほこり ----
	for (int i = 0; i < MAX_DUST; i++) {
		if (i >= dust_count) break;
		vec4 d = dust[i];
		vec2 dd = abs(p - d.xy);
		if (d.w > 0.0 && dd.x < d.z && dd.y < d.z) {
			c = mix(c, dust_color.rgb * mix(0.8, 1.2, light), d.w);
		}
	}

	// ---- ざらつきとディザ（post_grime.gdshader と同じ計算。粒の大きさは低い解像度の点）----
	c *= tint.rgb;
	c += (hash(cellp + floor(grain_time * 24.0) * 17.0) - 0.5) * grain;
	int bi = int(mod(cellp.x, 4.0)) + int(mod(cellp.y, 4.0)) * 4;
	float b = BAYER[bi] / 16.0 - 0.5;
	c = floor(c * levels + 0.5 + b * dither) / levels;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
