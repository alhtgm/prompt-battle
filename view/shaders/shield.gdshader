// バリア（シールドのスキル）の膜：六角形の格子、縁の光、流れる光、展開・消滅・被弾の波紋・残り少ないときのちらつき。
// 値は view/arena/shield_view.gd が毎フレーム渡す。光を足し合わせて描く（暗い中で光って見える）。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
// 展開の進み（0 で何もない、1 で全部出た）
uniform float open = 1.0;
// 消滅の進み（0 で消えていない、1 で全部消えた）
uniform float dissolve = 0.0;
// ちらつきの強さ（残り時間が少ないと上がる）
uniform float flicker = 0.0;
// 被弾した向き（膜の中心から見た向き）と、被弾してからの秒数
uniform vec3 hit_dir = vec3(1.0, 0.0, 0.0);
uniform float hit_age = 10.0;
// 全体の明るさ
uniform float intensity = 1.0;
// 横と縦に並べる六角形の数（低い解像度で潰れないよう粗め）
uniform float cells_x = 10.0;
uniform float cells_y = 5.0;
// 自分の時計（止まっている間は進まない）
uniform float clock = 0.0;

varying vec3 obj;

const vec2 HEX = vec2(1.0, 1.7320508);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 六角形の格子：xy はセルの中心からのずれ、zw はセルの番号
vec4 hex_cell(vec2 p) {
	vec4 c = floor(vec4(p, p - vec2(0.5, 1.0)) / HEX.xyxy) + 0.5;
	vec4 h = vec4(p - c.xy * HEX, p - (c.zw + 0.5) * HEX);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, c.xy) : vec4(h.zw, c.zw + 0.5);
}

// セルの中心で 0、縁で 0.5
float hex_edge(vec2 h) {
	h = abs(h);
	return max(dot(h, HEX * 0.5), h.x);
}

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 n = normalize(obj);
	float height = n.y * 0.5 + 0.5;
	// 球の表面を、横（ぐるりと一周）と縦の座標にして六角形を並べる。横は一周でちょうどつながる
	vec2 p = vec2((atan(n.z, n.x) / TAU + 0.5) * cells_x, height * cells_y * HEX.y);
	vec4 h = hex_cell(p);
	float edge = hex_edge(h.xy);
	float line = smoothstep(0.38, 0.47, edge);
	float r = hash(h.zw);

	// 展開：下から上へ、セルごとに少しずれて現れる。届いたばかりの所は白く光る
	float reveal = open * 1.35 - height - r * 0.3;
	float vis = step(0.0, reveal);
	float front = (1.0 - smoothstep(0.0, 0.18, reveal)) * vis;

	// 消滅：セルがばらばらに消える。消える直前のセルは強く光る
	vis *= step(dissolve, r);
	float dying = dissolve > 0.0 ? (1.0 - smoothstep(0.0, 0.12, r - dissolve)) : 0.0;

	// 流れる光（下から上へ走る帯）と、セルごとのまたたき
	float band = pow(0.5 + 0.5 * sin((height * 3.0 - clock * 0.9) * TAU), 6.0);
	float twinkle = 0.5 + 0.5 * sin(clock * 3.0 + r * TAU);

	// 被弾：当たった所が光り、輪が膜の上を広がっていく
	float d = acos(clamp(dot(n, normalize(hit_dir)), -1.0, 1.0));
	float ring = exp(-pow((d - hit_age * 5.0) * 5.0, 2.0)) * exp(-hit_age * 2.5);
	float impact = exp(-d * 3.0) * exp(-hit_age * 5.0);
	float near_hit = exp(-d * 2.0) * exp(-hit_age * 3.0) * (1.0 - line);

	// 縁ほど明るい（輪郭が光る）
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);

	float a = 0.04
		+ fres * 0.75
		+ line * (0.22 + 0.18 * twinkle)
		+ band * 0.12 * (0.4 + line)
		+ front * 1.4
		+ dying * 1.2
		+ ring * 1.6
		+ impact * 1.5
		+ near_hit * 0.6;
	// 裏側（内側）の面は薄く
	a *= FRONT_FACING ? 1.0 : 0.4;
	// 残り少ない：ときどき暗くなり、セルの一部が欠ける
	float tick = floor(clock * 14.0);
	float off = step(0.55, hash(vec2(tick, 3.7)));
	a *= 1.0 - flicker * 0.65 * off;
	vis *= 1.0 - flicker * step(0.8, hash(h.zw + tick)) ;
	a *= vis * intensity;

	// 白く光らせる部分（展開の先、被弾、消える直前）
	float hot = clamp(front + impact + ring * 0.6 + dying, 0.0, 1.0);
	ALBEDO = mix(color.rgb, vec3(1.0), hot * 0.7);
	ALPHA = clamp(a, 0.0, 1.0);
}
