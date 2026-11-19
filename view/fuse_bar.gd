# 残り時間の導火線。より縄が左から右へ伸び、右端の先端で燃えながら縮む。燃えた後ろは黒い焦げ跡として残る。
# 先端はオレンジの光が揺れて火花が飛び、残りわずかになると先端が赤くなって火花が増え、縄が小刻みに震える。右に「残り N 秒」。
# 見た目だけの部品で、残り時間は画面が毎コマ update() で渡す（最初に渡した値を満タンとする）。揺れは時間の関数で、乱数は使わない。値は view/look.gd。
extends HBoxContainer

const Look := preload("res://view/look.gd")

## 縄を描く場所
var rope: Control
var label: Label
## 今の残り秒数と、満タンの秒数
var left: float = 0.0
var max_left: float = 0.0
## 残りわずか（赤く激しく燃える）か
var warn: bool = false
var _sparks: CPUParticles2D
var _sparks_hot: CPUParticles2D
var _t: float = 0.0


func _init() -> void:
	add_theme_constant_override("separation", 14)
	rope = Control.new()
	rope.custom_minimum_size = Vector2(0, Look.FUSE_HEIGHT + 8.0)
	rope.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rope.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rope.draw.connect(_draw_rope)
	add_child(rope)
	_sparks = _make_sparks(Look.FUSE_SPARK_AMOUNT, 1.0)
	_sparks_hot = _make_sparks(Look.FUSE_SPARK_AMOUNT * 2, 1.6)
	_sparks_hot.emitting = false
	label = Label.new()
	label.custom_minimum_size = Vector2(110, 0)
	label.add_theme_font_size_override("font_size", 16)
	add_child(label)


## 残り時間を渡す（秒）。これまでで一番大きい値を満タンとする
func update(left_sec: float, delta: float) -> void:
	_t += delta
	left = maxf(0.0, left_sec)
	max_left = maxf(max_left, left)
	warn = left <= Look.FUSE_WARN_SEC and left > 0.0
	label.text = "残り %d 秒" % ceili(left)
	label.add_theme_color_override("font_color", Look.FUSE_TIP_WARN if warn else Look.UI_TEXT)
	# 火花は先端から出す（燃え尽きたら止める）
	var tip: Vector2 = _tip_pos()
	_sparks.position = tip
	_sparks_hot.position = tip
	_sparks.emitting = left > 0.0
	_sparks_hot.emitting = warn
	rope.queue_redraw()


## 燃えた割合に応じた先端の位置（震えのずれを含む）
func _tip_pos() -> Vector2:
	var ratio: float = left / max_left if max_left > 0.0 else 0.0
	return Vector2(ratio * rope.size.x, rope.size.y * 0.5) + _shake()


## 残りわずかのときの震え（時間の関数）
func _shake() -> Vector2:
	if not warn:
		return Vector2.ZERO
	var a: float = Look.FUSE_SHAKE_PX
	return Vector2(sin(_t * 53.0) * a, cos(_t * 41.0) * a * 0.7)


func _draw_rope() -> void:
	var w: float = rope.size.x
	var h: float = Look.FUSE_HEIGHT
	var off: Vector2 = _shake()
	var top: float = (rope.size.y - h) * 0.5
	var tip_x: float = _tip_pos().x - off.x
	rope.draw_set_transform(off)
	# 燃えた後ろ：黒い焦げ跡（細く、ところどころ途切れる）
	if tip_x < w:
		var burnt_h: float = h * 0.45
		var y: float = top + (h - burnt_h) * 0.5
		var x: float = tip_x
		var i: int = 0
		while x < w:
			var seg: float = 10.0 + float((i * 7) % 5) * 3.0
			rope.draw_rect(Rect2(x, y, minf(seg, w - x), burnt_h), Look.FUSE_BURNT)
			x += seg + 2.0
			i += 1
	# 燃えていない縄：地の色に、より縄の斜めの縞
	if tip_x > 0.0:
		rope.draw_rect(Rect2(0, top, tip_x, h), Look.FUSE_ROPE)
		var step: float = 7.0
		var x2: float = -h
		while x2 < tip_x:
			var p1 := Vector2(x2, top + h)
			var p2 := Vector2(x2 + h, top)
			# 縄の範囲（0〜tip_x）に収まるように端を切る
			if p1.x < 0.0:
				p1 = Vector2(0.0, top + h + p1.x)
			if p2.x > tip_x:
				p2 = Vector2(tip_x, top + (p2.x - tip_x))
			if p1.x < p2.x:
				rope.draw_line(p1, p2, Look.FUSE_ROPE_STRIPE, 2.0)
			x2 += step
		rope.draw_rect(Rect2(0, top, tip_x, h), Look.FUSE_ROPE.darkened(0.5), false, 1.0)
	# 先端の火：揺れる光の玉（外側ほど薄い）
	if left > 0.0:
		var tip := Vector2(tip_x, top + h * 0.5)
		var col: Color = Look.FUSE_TIP_WARN if warn else Look.FUSE_TIP
		var flick: float = 0.75 + 0.25 * sin(_t * 23.0) * sin(_t * 9.0)
		var r: float = (Look.FUSE_GLOW_RADIUS * (1.4 if warn else 1.0)) * flick
		rope.draw_circle(tip, r * 1.8, Color(col, 0.12))
		rope.draw_circle(tip, r * 1.2, Color(col, 0.3))
		rope.draw_circle(tip, r * 0.7, Color(col, 0.75))
		rope.draw_circle(tip, r * 0.35, Color(1.0, 0.97, 0.85, 0.95))
	rope.draw_set_transform(Vector2.ZERO)


## 先端から飛ぶ火花（上と後ろへ散って、重さで落ちながら消える）
func _make_sparks(amount: int, speed: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = 0.5
	p.local_coords = false
	p.direction = Vector2(0.4, -1.0)
	p.spread = 70.0
	p.initial_velocity_min = 35.0 * speed
	p.initial_velocity_max = 90.0 * speed
	p.gravity = Vector2(0, 220)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	g.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
	g.add_point(0.4, Color(1.0, 0.65, 0.2, 1.0))
	p.color_ramp = g
	rope.add_child(p)
	return p
