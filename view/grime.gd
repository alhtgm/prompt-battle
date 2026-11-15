# 汚れた質感の材質を作る。ノイズの模様で、色むら・こすれ・さびを出す（画像ファイルを使わない仮の質感）。
# 同じ設定の材質は使い回す。
extends RefCounted

static var _cache: Dictionary = {}


## color：地の色、metal：金属らしさ、rough：ざらつき、scale：模様の細かさ、glow：光る色（光らないなら透明）
static func material(color: Color, metal: float = 0.0, rough: float = 0.85, scale: float = 1.0,
		glow: Color = Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var key: String = "%s/%.2f/%.2f/%.2f/%s" % [color.to_html(), metal, rough, scale, glow.to_html()]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = _noise_texture(scale)
	mat.metallic = metal
	mat.roughness = rough
	mat.uv1_triplanar = true  # 箱の大きさに関係なく模様の細かさをそろえる
	mat.uv1_scale = Vector3.ONE * scale
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if glow.a > 0.0:
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = 1.6
	_cache[key] = mat
	return mat


## 明るさのむらと細かい傷を重ねた模様（白〜灰色。地の色を掛けて使う）
static func _noise_texture(scale: float) -> NoiseTexture2D:
	var key: String = "tex/%.2f" % scale
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.6
	noise.seed = 7
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.45, 0.42, 0.38))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	ramp.add_point(0.55, Color(0.82, 0.8, 0.76))
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	_cache[key] = tex
	return tex
