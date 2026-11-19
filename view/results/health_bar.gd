# 体力バー1本。前の体力から今の体力へ、減った分を一瞬赤く残してから縮める（格闘ゲームの減り方）。
# 見た目だけの部品で、試合の状態は持たない（値は画面が渡す）。時間の値は view/look.gd。
extends Control

const Look := preload("res://view/look.gd")

var max_value: float = 100.0
var from_value: float = 100.0
var to_value: float = 100.0
## 自分のバー（色を明るくする）
var is_me: bool = false
## 前のラウンドまでに脱落している（灰色で空のまま）
var is_out: bool = false
## 動き出すまでの秒数（バーごとに少しずらす）
var delay: float = 0.0
var _t: float = 0.0


func setup(max_v: float, before: float, after: float, me: bool, out: bool, start_delay: float) -> void:
	max_value = maxf(1.0, max_v)
	from_value = clampf(before, 0.0, max_value)
	to_value = clampf(after, 0.0, max_value)
	is_me = me
	is_out = out
	delay = start_delay
	custom_minimum_size = Vector2(200, 20)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 減る動きが終わるまでの秒数
func total_sec() -> float:
	return delay + Look.HP_BAR_HOLD_SEC + Look.HP_BAR_DRAIN_SEC


## 動きが終わったか
func is_done() -> bool:
	return _t >= total_sec()


## 動きを最後まで飛ばす
func finish_now() -> void:
	_t = total_sec()
	queue_redraw()


func _process(delta: float) -> void:
	if _t < total_sec():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Look.HP_BAR_BACK)
	if is_out:
		draw_rect(r, Look.HP_BAR_OUT, false, 1.0)
		return
	# 動き出すまでは前の体力。動き出したら本体は今の体力まで一気に下げ、減った分（赤）を少し残してから縮める
	var fill: float = from_value if _t < delay else to_value
	var red_edge: float = from_value
	var drain_t: float = (_t - delay - Look.HP_BAR_HOLD_SEC) / Look.HP_BAR_DRAIN_SEC
	if drain_t > 0.0:
		red_edge = lerpf(from_value, to_value, ease(clampf(drain_t, 0.0, 1.0), 0.5))
	var w: float = size.x / max_value
	if red_edge > fill:
		draw_rect(Rect2(fill * w, 0, (red_edge - fill) * w, size.y), Look.HP_BAR_LOST)
	draw_rect(Rect2(0, 0, fill * w, size.y), Look.HP_BAR_FILL_ME if is_me else Look.HP_BAR_FILL)
	# 25ごとの目盛り
	var step: float = max_value / 4.0
	for i: int in range(1, 4):
		var x: float = step * i * w
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.45), 1.0)
	draw_rect(r, Look.UI_BORDER, false, 1.0)
