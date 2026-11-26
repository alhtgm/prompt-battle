# シャッターの見た目と動きのテスト。動きの合計時間、動きが滑らかなこと、
# 乱数を使っていないこと、同じ時刻なら同じ見た目（板の幅・ほこり・ノイズの模様）になることを確かめる。
extends "res://tests/support/test_case.gd"

const Shutter := preload("res://view/shutter.gd")
const Look := preload("res://view/look.gd")


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


## 閉じる・開くの合計時間は look.gd の値どおり
func test_motion_totals_match_look_values() -> void:
	var close_sec: float = Look.SHUTTER_CLOSE_SEC
	check_eq(Shutter.close_fraction(0.0), 0.0, "閉じ始めは開いている")
	check(absf(Shutter.close_fraction(close_sec) - 1.0) < 0.0001, "SHUTTER_CLOSE_SEC ちょうどで閉じきる")
	check(Shutter.close_fraction(close_sec - 0.01) < 0.999, "SHUTTER_CLOSE_SEC より前には閉じきらない")
	var open_sec: float = Look.SHUTTER_OPEN_SEC
	check_eq(Shutter.open_fraction(0.0), 0.0, "開き始めは閉じている")
	check(absf(Shutter.open_fraction(open_sec) - 1.0) < 0.0001, "SHUTTER_OPEN_SEC ちょうどで開ききる")
	check(Shutter.open_fraction(open_sec - 0.01) < 0.999, "SHUTTER_OPEN_SEC より前には開ききらない")


## 動きは逆戻りせず、途中で速さが急に変わらない（閉じきる瞬間だけは、下に当たって止まる）
func test_motion_is_smooth() -> void:
	for spec: Array in [[Shutter.close_fraction, Look.SHUTTER_CLOSE_SEC, "閉じる"], [Shutter.open_fraction, Look.SHUTTER_OPEN_SEC, "開く"]]:
		var fn: Callable = spec[0]
		var total: float = spec[1]
		var n: int = 2000
		var dt: float = total / float(n)
		var prev_f: float = 0.0
		var prev_v: float = 0.0
		var monotonic: bool = true
		var max_jump: float = 0.0
		var max_v: float = 0.0
		for i: int in range(1, n + 1):
			var f: float = fn.call(dt * float(i))
			var v: float = (f - prev_f) / dt
			if f < prev_f - 0.000001:
				monotonic = false
			max_v = maxf(max_v, v)
			max_jump = maxf(max_jump, absf(v - prev_v))
			prev_f = f
			prev_v = v
		check(monotonic, "%s動きは逆戻りしない" % spec[2])
		# 1刻み（%.4f 秒）での速さの変わり方が、一番速いときの速さの 2% 以内（がくっと止まらない）
		check(max_jump < max_v * 0.02, "%s動きの速さが急に変わらない（変化 %.3f / 最大 %.3f）" % [spec[2], max_jump, max_v])


## 見た目のコードで乱数を使っていない
func test_shutter_look_uses_no_random() -> void:
	for path: String in ["res://view/shutter.gd", "res://view/shaders/shutter.gdshader"]:
		var text: String = FileAccess.get_file_as_string(path)
		check(not text.is_empty(), "%s が読める" % path)
		for word: String in ["randf(", "randi(", "randf_range(", "randi_range(", "randomize(", "RandomNumberGenerator"]:
			check(not text.contains(word), "%s で %s を使っていない" % [path.get_file(), word])


## 同じ時刻なら同じ見た目（板の幅・ほこりの位置・ノイズの模様・シェーダーに渡す値）
func test_same_time_same_look() -> void:
	check_eq(Shutter.slat_layout(700.0), Shutter.slat_layout(700.0), "板の並びは毎回同じ")
	var layout: Array[Vector2] = Shutter.slat_layout(700.0)
	var heights: Dictionary = {}
	for v: Vector2 in layout:
		heights[snappedf(v.y, 0.01)] = true
	check(heights.size() > layout.size() / 2, "板の幅は不ぞろい（%d 種類 / %d 枚）" % [heights.size(), layout.size()])
	for v: Vector2 in layout:
		check(absf(v.y - Look.SHUTTER_SLAT_PX) <= Look.SHUTTER_SLAT_PX * Look.SHUTTER_SLAT_VARY + 0.001, "板の幅は決めた不ぞろいの範囲")
	for t: float in [0.0, 0.3, 0.9]:
		check_eq(Shutter.dust_particles(t, 1280.0, 744.0), Shutter.dust_particles(t, 1280.0, 744.0), "%.1f 秒のほこりは毎回同じ" % t)
	var d: PackedVector4Array = Shutter.dust_particles(0.3, 1280.0, 744.0)
	check_eq(d.size(), Look.SHUTTER_DUST_COUNT, "ほこりの粒の数")
	var spread: bool = false
	for p: Vector4 in d:
		check(p.w >= 0.0 and p.w <= 1.0 and is_finite(p.x) and is_finite(p.y), "ほこりの値が壊れない")
		if absf(p.x - 640.0) > 300.0:
			spread = true
	check(spread, "ほこりは横に広がる")
	check(Shutter.dust_particles(Look.SHUTTER_DUST_SEC + 0.1, 1280.0, 744.0).is_empty(), "ほこりはやがて消える")
	# 2つ作って、同じ状態ならシェーダーに渡す値（ノイズの種と設定を含む）が同じ
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var shutters: Array = []
	for i: int in 2:
		var s: Variant = Shutter.new()
		root.add_child(s)
		shutters.append(s)
	await _frame()
	for s: Variant in shutters:
		s.size = Vector2(1280, 720)
		s.close()
	await _frame()
	var keys: Array[String] = ["slat_bottom", "slat_height", "slat_count", "dents", "patches", "rect_size"]
	for key: String in keys:
		check_eq(shutters[0]._mat.get_shader_parameter(key), shutters[1]._mat.get_shader_parameter(key), "シェーダーの %s は毎回同じ" % key)
	for key: String in ["noise_large", "noise_fine"]:
		var n0: Variant = shutters[0]._mat.get_shader_parameter(key).noise
		var n1: Variant = shutters[1]._mat.get_shader_parameter(key).noise
		check(n0.seed == n1.seed and n0.frequency == n1.frequency, "%s の模様（種）は毎回同じ" % key)
	for s: Variant in shutters:
		s.queue_free()
	await _frame()
