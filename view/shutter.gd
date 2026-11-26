# 出撃のシャッター。重い鉄の板が加速しながら下り、閉じきったらずんと沈んでほこりが舞い、重そうに動き出して巻き上がって開く。
# 板金は view/shaders/shutter.gdshader で低い解像度に描く。いつ閉じる・開くかは view/main.gd が決める。試合の状態は読まない。
# 動きも見た目も時刻だけで決まる（乱数は使わない）。動いている間・閉じている間は下の画面の操作を止める。
extends Control

const Look := preload("res://view/look.gd")
const SHADER := preload("res://view/shaders/shutter.gdshader")

## キャンセルボタンが押された（通信対戦で、ほかのプレイヤーを待っている間だけ出す）
signal cancel_requested

enum State { OPEN, CLOSING, CLOSED, OPENING }

var state: State = State.OPEN
## 閉じきってから揺れが収まるまで（CLOSED のうち、揺れている間）
var shaking: bool = false
## 動きの速さの倍率（通信対戦でバトルの開始に間に合わせるときに上げる）
var speed: float = 1.0
## シャッターの板（上へ出ていれば開いている）。中の body が揺れで沈む
var panel: Control
var body: Control
## 板金を描く板（低い解像度のシェーダー）
var metal: ColorRect
var message: Label
var cancel_button: Button

var _tween: Tween = null
## 閉じ始めてからの経過（速さの倍率をかける前の秒。残りの見積もりに使う）
var _close_t: float = 0.0
var _shake_t: float = 0.0
## 閉じきってからの経過（ほこり用。負なら舞っていない）
var _dust_t: float = -1.0
## 閉じきって揺れが収まってからの経過（秒。閉じていなければ 0）
var closed_time: float = 0.0
## 粒が変わる時刻（ざらつき）
var _grain_t: float = 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # CanvasLayer の下なので、大きさも画面いっぱいに合わせる
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP  # 見えている間は下の画面をマウスで押せない
	add_child(panel)
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	metal = ColorRect.new()
	metal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	metal.material = _mat
	body.add_child(metal)
	_setup_material()
	# 文字とボタンは低い解像度にせず、くっきりしたまま上に重ねる
	message = Label.new()
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", Look.SHUTTER_MESSAGE_FONT)
	message.add_theme_color_override("font_color", Look.UI_ACCENT)
	message.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	message.add_theme_constant_override("outline_size", 8)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(message)
	cancel_button = Button.new()
	cancel_button.text = "キャンセル"
	cancel_button.custom_minimum_size = Vector2(200, 44)
	cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	panel.add_child(cancel_button)
	set_waiting("", false)
	_layout()
	reset()
	resized.connect(_layout)


func _layout() -> void:
	var s: Vector2 = size
	panel.size = s
	body.size = s
	metal.position = Vector2(0, -Look.SHUTTER_OVERDRAW_PX)
	metal.size = Vector2(s.x, s.y + Look.SHUTTER_OVERDRAW_PX)
	message.position = Vector2(0, s.y * 0.5 - 60)
	message.size = Vector2(s.x, 60)
	var bs: Vector2 = cancel_button.get_combined_minimum_size()
	cancel_button.size = bs
	cancel_button.position = Vector2((s.x - bs.x) * 0.5, s.y - Look.SHUTTER_FRAME_PX - bs.y - 40)
	if state == State.OPEN:
		panel.position.y = -s.y
	_update_slats()


func is_open() -> bool:
	return state == State.OPEN


## 閉じきって、揺れも収まったか
func is_closed() -> bool:
	return state == State.CLOSED and not shaking


## 動いている・閉じているか（下の画面の操作を止めている間）
func is_active() -> bool:
	return state != State.OPEN


## 待っている間の文字とキャンセルボタン（閉じきっているときだけ見える）
func set_waiting(text: String, cancelable: bool) -> void:
	message.text = text
	message.visible = not text.is_empty()
	cancel_button.visible = cancelable


## 閉じ始めてから、閉じきって揺れが収まるまでの残り（速さの倍率をかける前の秒）。閉じていなければ 0
func time_to_closed() -> float:
	if state != State.CLOSING and not shaking:
		return 0.0
	return maxf(0.0, Look.SHUTTER_CLOSE_SEC + Look.SHUTTER_SHAKE_SEC - _close_t)


## 動きの速さを変える（動いている途中でも効く）
func set_speed(s: float) -> void:
	speed = clampf(s, 0.01, Look.SHUTTER_MAX_SPEED)


# ---- 動き（時刻から位置を決める式。合計の秒数は look.gd の値どおり） ----

## 止まった所から加速し、時間の割合 a で一定の速さに乗る（0〜1 → 0〜1。つなぎ目で速さが途切れない）
static func _accel_then_cruise(u: float, a: float) -> float:
	var norm: float = 1.0 - a * 0.5
	if u < a:
		return u * u / (2.0 * a) / norm
	return (u - a * 0.5) / norm


## 閉じるときの、閉じた割合（0＝開いている、1＝閉じきった）。t は閉じ始めてからの秒（0〜SHUTTER_CLOSE_SEC）。
## 止まった所から重く加速し、そのまま下に当たる
static func close_fraction(t: float) -> float:
	var u: float = clampf(t / Look.SHUTTER_CLOSE_SEC, 0.0, 1.0)
	return u * u


## 開くときの、開いた割合（0＝閉じている、1＝開ききった）。t は開き始めてからの秒（0〜SHUTTER_OPEN_SEC）。
## 重そうに動き出して速さに乗り、あとは一定の速さで巻き上げる
static func open_fraction(t: float) -> float:
	var u: float = clampf(t / Look.SHUTTER_OPEN_SEC, 0.0, 1.0)
	return clampf(_accel_then_cruise(u, Look.SHUTTER_OPEN_ACCEL_RATIO), 0.0, 1.0)


## 閉じきったときの沈み（点。下向きが正）。沈んで戻る1回だけ
static func sink_offset(t: float) -> float:
	if t < 0.0 or t >= Look.SHUTTER_SHAKE_SEC:
		return 0.0
	var u: float = t / Look.SHUTTER_SHAKE_SEC
	# すぐに底まで沈み、ゆっくり戻る
	return Look.SHUTTER_SINK_PX * sin(PI * pow(u, 0.6)) * (1.0 - u * 0.3)


## 閉じる。重く加速しながら落ち、閉じきったらずんと沈んでほこりが舞う
func close() -> void:
	if state == State.CLOSING or state == State.CLOSED:
		return
	_kill()
	state = State.CLOSING
	shaking = false
	visible = true
	set_waiting("", false)
	# 途中まで開いていたら、その位置から続きの時間だけ閉じる
	var t0: float = _time_at(_fraction_now(), true)
	_close_t = t0
	_tween = _new_tween()
	_tween.tween_method(_apply_close, t0, Look.SHUTTER_CLOSE_SEC, Look.SHUTTER_CLOSE_SEC - t0)
	_tween.tween_callback(_on_slam)


## 開く（重そうに動き出し、一定の速さで巻き上げる）
func open() -> void:
	if state == State.OPEN or state == State.OPENING:
		return
	_kill()
	state = State.OPENING
	shaking = false
	body.position = Vector2.ZERO
	set_waiting("", false)
	var t0: float = _time_at(1.0 - _fraction_now(), false)
	_tween = _new_tween()
	_tween.tween_method(_apply_open, t0, Look.SHUTTER_OPEN_SEC, Look.SHUTTER_OPEN_SEC - t0)
	_tween.tween_callback(_on_opened)


## すぐに開いた状態に戻す（タイトルへ戻る・試合が飛んだときなど、シャッターを残さない）
func reset() -> void:
	_kill()
	state = State.OPEN
	shaking = false
	speed = 1.0
	_close_t = 0.0
	_dust_t = -1.0
	panel.position = Vector2(0, -size.y)
	body.position = Vector2.ZERO
	set_waiting("", false)
	visible = false


## 揺れのずれ（画面全体にも同じずれをかける）。下へずんと沈んで戻る
func shake_offset() -> Vector2:
	if not shaking:
		return Vector2.ZERO
	return Vector2(0.0, sink_offset(_shake_t))


func _process(delta: float) -> void:
	# 1フレームが長くても動きを飛ばさないよう、進める時間に上限を付けて自分で進める
	var step: float = minf(delta, Look.SHUTTER_MAX_STEP_SEC) * speed
	if shaking:
		_close_t += step
		_shake_t += step
	if _tween != null and _tween.is_valid():
		_tween.custom_step(step)
	if shaking and _shake_t >= Look.SHUTTER_SHAKE_SEC:
		shaking = false
	closed_time = closed_time + minf(delta, Look.SHUTTER_MAX_STEP_SEC) if is_closed() else 0.0
	body.position = shake_offset()
	if _dust_t >= 0.0:
		_dust_t += minf(delta, Look.SHUTTER_MAX_STEP_SEC)
		if _dust_t > Look.SHUTTER_DUST_SEC:
			_dust_t = -1.0
	if visible:
		_grain_t += delta
		_update_material()


## 動いている・閉じている間は、キーの操作を下の画面へ渡さない（マウスは板が受け止める）
func _input(event: InputEvent) -> void:
	if is_active() and event is InputEventKey:
		get_viewport().set_input_as_handled()


func _apply_close(t: float) -> void:
	_close_t = t
	panel.position.y = -size.y * (1.0 - close_fraction(t))


func _apply_open(t: float) -> void:
	panel.position.y = -size.y * open_fraction(t)


## 今の閉じた割合
func _fraction_now() -> float:
	return clampf(1.0 + panel.position.y / size.y, 0.0, 1.0) if size.y > 0.0 else 1.0


## 割合 f に達する時刻（閉じる式か開く式で、最初に f に届く時刻を探す）
func _time_at(f: float, closing: bool) -> float:
	if f <= 0.0:
		return 0.0
	var total: float = Look.SHUTTER_CLOSE_SEC if closing else Look.SHUTTER_OPEN_SEC
	var n: int = 240
	for i: int in n + 1:
		var t: float = total * float(i) / float(n)
		var g: float = close_fraction(t) if closing else open_fraction(t)
		if g >= f - 0.0001:
			return t
	return total


func _on_slam() -> void:
	state = State.CLOSED
	shaking = true
	_shake_t = 0.0
	_close_t = Look.SHUTTER_CLOSE_SEC
	_dust_t = 0.0


func _on_opened() -> void:
	state = State.OPEN
	speed = 1.0
	visible = false
	body.position = Vector2.ZERO


## 動きの Tween。止めておき、_process で上限付きの時間だけ進める
func _new_tween() -> Tween:
	var t: Tween = create_tween()
	t.pause()
	return t


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


# ---- 見た目（板の幅・ほこりは番号と時刻から決まる式。ノイズの種は固定） ----

## 板の高さ（点）。板の番号（下から 0）から決まる式で、少しずつ不ぞろいにする
static func slat_height(i: int) -> float:
	var x: float = float(i)
	var w: float = 0.6 * sin(x * 2.17 + 0.5) + 0.4 * sin(x * 5.31 + 1.3)
	return Look.SHUTTER_SLAT_PX * (1.0 + Look.SHUTTER_SLAT_VARY * w)


## 高さ h の絵を埋める板の並び：[下の端の高さ（下枠の上から）, 高さ] の配列
static func slat_layout(h: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var y: float = 0.0
	var i: int = 0
	while y < h and i < 48:
		var sh: float = slat_height(i)
		out.append(Vector2(y, sh))
		y += sh
		i += 1
	return out


## 番号から決まる 0〜1 の値（乱数の代わり。毎回同じ）
static func _hash(x: float) -> float:
	var v: float = sin(x * 12.9898 + 4.1414) * 43758.5453
	return v - floor(v)


## 閉じきってから t 秒のほこりの粒：(x, y, 大きさ, 濃さ)。w と h は絵の幅と高さ（下の端が h）
static func dust_particles(t: float, w: float, h: float) -> PackedVector4Array:
	var out := PackedVector4Array()
	if t < 0.0 or t > Look.SHUTTER_DUST_SEC:
		return out
	var k: float = Look.SHUTTER_DUST_DRAG
	var travel: float = (1.0 - exp(-k * t)) / k  # 勢いが落ちながら進む距離（速さ1あたり）
	var life: float = t / Look.SHUTTER_DUST_SEC
	for i: int in Look.SHUTTER_DUST_COUNT:
		var a: float = _hash(float(i) + 0.1)
		var b: float = _hash(float(i) + 0.37)
		var c: float = _hash(float(i) + 0.73)
		var x0: float = w * (0.04 + 0.92 * a)
		var y0: float = h - Look.SHUTTER_FRAME_PX + (b - 0.5) * 10.0
		var vx: float = (a - 0.5) * 2.0 * Look.SHUTTER_DUST_SPREAD * (0.35 + 0.65 * c)
		var vy: float = -Look.SHUTTER_DUST_RISE * (0.3 + 0.7 * b)
		var size: float = float(Look.PIXEL_SHRINK) * (1.0 + floor(c * 2.0))
		var fade_in: float = clampf(t / 0.06, 0.0, 1.0)
		var alpha: float = Look.SHUTTER_DUST_ALPHA * fade_in * pow(1.0 - life, 1.6) * (0.5 + 0.5 * b)
		out.append(Vector4(x0 + vx * travel, y0 + vy * travel - 6.0 * t * t, size, alpha))
	return out


## ノイズの模様（種は固定。毎回同じ模様）
static func _noise(freq: float, octaves: int, seed_value: int, size_px: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_gain = 0.55
	n.seed = seed_value
	var tex := NoiseTexture2D.new()
	tex.width = size_px
	tex.height = size_px
	tex.seamless = true
	tex.noise = n
	return tex


func _setup_material() -> void:
	_mat.set_shader_parameter("noise_large", _noise(0.012, 4, 11, 512))
	_mat.set_shader_parameter("noise_fine", _noise(0.05, 3, 23, 256))
	var params: Dictionary = {
		"shrink": float(Look.PIXEL_SHRINK), "steel": Look.SHUTTER_STEEL,
		"gap_px": Look.SHUTTER_GAP_PX, "gap_dark": Look.SHUTTER_GAP_DARK,
		"highlight": Look.SHUTTER_HIGHLIGHT, "slat_shade": Look.SHUTTER_SLAT_SHADE, "mottle": Look.SHUTTER_MOTTLE,
		"rust_color": Look.SHUTTER_RUST, "rust_strength": Look.SHUTTER_RUST_STRENGTH,
		"rust_threshold": Look.SHUTTER_RUST_THRESHOLD, "rust_edge_px": Look.SHUTTER_RUST_EDGE_PX,
		"scratch_threshold": Look.SHUTTER_SCRATCH_THRESHOLD, "scratch": Look.SHUTTER_SCRATCH,
		"oil_threshold": Look.SHUTTER_OIL_THRESHOLD, "oil_dark": Look.SHUTTER_OIL_DARK,
		"patch_tint": Look.SHUTTER_PATCH_TINT, "rivet_px": Look.SHUTTER_RIVET_PX,
		"dent_shade": Look.SHUTTER_DENT_SHADE, "dent_warp_px": Look.SHUTTER_DENT_WARP_PX,
		"frame_px": Look.SHUTTER_FRAME_PX, "frame_steel": Look.SHUTTER_FRAME_STEEL,
		"stripe_px": Look.SHUTTER_STRIPE_PX, "stripe_a": Look.SHUTTER_STRIPE_A, "stripe_b": Look.SHUTTER_STRIPE_B,
		"stripe_fray_px": Look.SHUTTER_STRIPE_FRAY_PX, "peel_threshold": Look.SHUTTER_PEEL_THRESHOLD,
		"light_top": Look.SHUTTER_LIGHT_TOP, "light_bottom": Look.SHUTTER_LIGHT_BOTTOM,
		"light_side": Look.SHUTTER_LIGHT_SIDE, "dust_color": Look.SHUTTER_DUST,
	}
	for key: String in params:
		_mat.set_shader_parameter(key, params[key])
	for key: String in Look.SHUTTER_POST:
		_mat.set_shader_parameter(key, Look.SHUTTER_POST[key])


## 板の並び・へこみ・継ぎ当て（大きさが変わったときだけ）
func _update_slats() -> void:
	if _mat == null:
		return
	var w: float = size.x
	var h: float = size.y + Look.SHUTTER_OVERDRAW_PX
	_mat.set_shader_parameter("rect_size", Vector2(w, h))
	var layout: Array[Vector2] = slat_layout(h - Look.SHUTTER_FRAME_PX)
	var bottoms := PackedFloat32Array()
	var heights := PackedFloat32Array()
	for v: Vector2 in layout:
		bottoms.append(v.x)
		heights.append(v.y)
	_mat.set_shader_parameter("slat_bottom", bottoms)
	_mat.set_shader_parameter("slat_height", heights)
	_mat.set_shader_parameter("slat_count", layout.size())
	# へこみと継ぎ当ては4つずつの数の並びで渡す（シェーダーの配列の大きさ 16 に合わせて埋める）
	var dents := PackedFloat32Array()
	for d: Array in Look.SHUTTER_DENTS.slice(0, 4):
		dents.append_array([float(d[0]), float(d[1]) * w, maxf(1.0, float(d[2]) * w), float(d[3])])
	var n_dents: int = dents.size() / 4
	dents.resize(16)
	_mat.set_shader_parameter("dents", dents)
	_mat.set_shader_parameter("dent_count", n_dents)
	var patches := PackedFloat32Array()
	for q: Array in Look.SHUTTER_PATCHES.slice(0, 4):
		if int(q[1]) < layout.size():
			patches.append_array([float(q[0]), float(q[1]), float(q[2]) * w, float(q[3]) * w])
	var n_patches: int = patches.size() / 4
	patches.resize(16)
	_mat.set_shader_parameter("patches", patches)
	_mat.set_shader_parameter("patch_count", n_patches)


## 毎フレーム変わるもの：画面の上での位置（光）、ほこり、ざらつきの時刻
func _update_material() -> void:
	var vp: Vector2 = get_viewport_rect().size
	_mat.set_shader_parameter("screen_w", vp.x)
	_mat.set_shader_parameter("screen_h", vp.y)
	_mat.set_shader_parameter("rect_screen_y", panel.position.y + body.position.y - Look.SHUTTER_OVERDRAW_PX)
	var dust: PackedVector4Array = dust_particles(_dust_t, size.x, size.y + Look.SHUTTER_OVERDRAW_PX)
	_mat.set_shader_parameter("dust_count", mini(dust.size(), 64))
	if dust.is_empty():
		dust.append(Vector4.ZERO)  # 空の配列は渡さない
	_mat.set_shader_parameter("dust", dust)
	_mat.set_shader_parameter("grain_time", _grain_t)
