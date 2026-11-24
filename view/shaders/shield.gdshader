// バリア（シールドのスキル）の膜：丸い光の泡。縁が強く光り、表面を光のもやが渦を巻いて流れ、中ほどは淡く透ける。
// 展開・消滅（もやが焼け切れるように消える）・被弾の波紋・残り少ないときのちらつき。値は view/arena/shield_view.gd が毎フレーム渡す。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// 膜の色、縁の色（明るい）、流れるもやの色
uniform vec4 color : source_color = vec4(0.7, 0.3, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.7, 1.0, 1.0);
uniform vec4 wisp_color : source_color = vec4(0.45, 0.6, 1.0, 1.0);
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
// 自分の時計（止まっている間は進まない）
uniform float clock = 0.0;

varying vec3 obj;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// なめらかなノイズ（0〜1）
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i);
	float n100 = hash3(i + vec3(1, 0, 0));
	float n010 = hash3(i + vec3(0, 1, 0));
	float n110 = hash3(i + vec3(1, 1, 0));
	float n001 = hash3(i + vec3(0, 0, 1));
	float n101 = hash3(i + vec3(1, 0, 1));
	float n011 = hash3(i + vec3(0, 1, 1));
	float n111 = hash3(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return noise3(p) * 0.55 + noise3(p * 2.1 + 3.1) * 0.3 + noise3(p * 4.3 + 7.7) * 0.15;
}

// y 軸のまわりに回す
vec3 spin(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
}

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 n = normalize(obj);
	float height = n.y * 0.5 + 0.5;

	// 縁ほど明るい（泡の輪郭がくっきり光る）
	float facing = abs(dot(NORMAL, VIEW));
	float fres = pow(1.0 - facing, 3.0);
	float rim = pow(1.0 - facing, 7.0);

	// 渦を巻いて流れる光のもや：高さで回る角度を変えて、ねじれながら回る
	vec3 q = spin(n, clock * 0.9 + height * 2.2);
	float w = fbm(q * 2.2 + vec3(0.0, -clock * 0.6, 0.0));
	float wisp = smoothstep(0.52, 0.78, w);
	// 細く走る光の筋（もやの縁）
	float streak = smoothstep(0.05, 0.0, abs(w - 0.6)) * 0.8;
	// ゆっくり脈打つ
	float pulse = 0.85 + 0.15 * sin(clock * 4.0);

	// 展開：中心からふくらむ間、全体が白く強く光る
	float flash = (1.0 - open) * 1.5;

	// 消滅：もやの模様にそって焼け切れるように消え、消える縁が明るく光る
	float burn = fbm(n * 3.0 + 11.0);
	float vis = dissolve > 0.0 ? step(dissolve * 1.1, burn) : 1.0;
	float dying = dissolve > 0.0 ? (1.0 - smoothstep(0.0, 0.08, burn - dissolve * 1.1)) * vis : 0.0;

	// 被弾：当たった所が光り、輪が膜の上を広がっていく
	float d = acos(clamp(dot(n, normalize(hit_dir)), -1.0, 1.0));
	float ring = exp(-pow((d - hit_age * 5.0) * 5.0, 2.0)) * exp(-hit_age * 2.5);
	float impact = exp(-d * 3.0) * exp(-hit_age * 5.0);

	float a = 0.05
		+ fres * 0.55 * pulse
		+ rim * 0.9
		+ wisp * 0.32
		+ streak * 0.35
		+ flash
		+ dying * 1.4
		+ ring * 1.5
		+ impact * 1.4;
	// 裏側（内側）の面は薄く
	a *= FRONT_FACING ? 1.0 : 0.45;
	// 残り少ない：ときどき暗くなり、もやが乱れる
	float tick = floor(clock * 14.0);
	float off = step(0.55, hash3(vec3(tick, 3.7, 1.0)));
	a *= 1.0 - flicker * 0.65 * off;
	a *= open * vis * intensity;

	// 色：中は膜の色、縁は明るい色、もやは青み、白く光らせる部分（展開・被弾・消える縁）
	vec3 col = mix(color.rgb, rim_color.rgb, clamp(rim * 1.5 + fres * 0.3, 0.0, 1.0));
	col = mix(col, wisp_color.rgb, clamp(wisp * 0.6 + streak, 0.0, 1.0) * (1.0 - rim));
	float hot = clamp(flash + impact + ring * 0.6 + dying, 0.0, 1.0);
	ALBEDO = mix(col, vec3(1.0), hot * 0.7);
	ALPHA = clamp(a, 0.0, 1.0);
}
