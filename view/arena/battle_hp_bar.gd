# バトル中の機体のHPバー1本。削られた分を白く光らせてから赤く残して遅れて縮め、被弾の大きさに合わせてバーを揺らし、減った数をバーの上に出す。
# 残りが少ないと赤く脈打ち、回復すると緑に光る。見た目だけの部品で、値は画面が set_hp で渡す。時間や色の値は view/look.gd。
extends Control

const Look := preload("res://view/look.gd")

## 機体の色（バーの中身）
var color: Color = Color.WHITE
## true なら右から左へ減る（右側の機体。左右を反転して描く）
var mirrored: bool = false
var max_hp: float = 1.0
var hp: float = 1.0
## 遅れて縮む赤い部分の端（HP の値）
var lag_hp: float = 1.0
## 揺れの強さ（点）
var shake: float = 0.0
## 削られてからの秒数（白く光る・赤を残す時間をはかる）
var _since_hit: float = 999.0
## 回復してからの秒数（緑に光る時間）
var _since_heal: float = 999.0
## 飛ばしている数（[文字, 経った秒, 色]）
var popups: Array = []
var _t: float = 0.0
var _ready_value: bool = false


func setup(side_color: Color, mirror: bool) -> void:
	color = side_color
	mirrored = mirror
	custom_minimum_size = Look.BATTLE_HP_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 今のHPを渡す。前より減っていれば削られた演出、増えていれば回復の演出を始める
func set_hp(value: float, max_value: float) -> void:
	max_value = maxf(1.0, max_value)
	value = clampf(value, 0.0, max_value)
	if not _ready_value or not is_equal_approx(max_value, max_hp):
		max_hp = max_value
		hp = value
		lag_hp = value
		_ready_value = true
		queue_redraw()
		return
	var diff: float = value - hp
	if diff < -0.01:
		lag_hp = maxf(lag_hp, hp)
		_since_hit = 0.0
		var frac: float = -diff / max_hp
		shake = minf(Look.BATTLE_HP_SHAKE_MAX, shake + Look.BATTLE_HP_SHAKE_MAX * clampf(frac * 6.0, 0.25, 1.0))
		_pop("−%d" % maxi(1, roundi(-diff)), Look.BATTLE_HP_POP_DAMAGE)
	elif diff > 0.01:
		_since_heal = 0.0
		lag_hp = maxf(lag_hp, value)
		_pop("+%d" % maxi(1, roundi(diff)), Look.BATTLE_HP_HEAL)
	hp = value
	queue_redraw()


## 少ないとき（赤く脈打つ）か
func is_low() -> bool:
	return hp > 0.0 and hp / max_hp < Look.BATTLE_HP_LOW


func _pop(text: String, col: Color) -> void:
	# 連続ヒットで数が増えすぎないよう、多すぎたら古いものから消す
	if popups.size() >= 4:
		popups.pop_front()
	popups.append([text, 0.0, col])


func _process(delta: float) -> void:
	_t += delta
	_since_hit += delta
	_since_heal += delta
	shake = maxf(0.0, shake - Look.BATTLE_HP_SHAKE_MAX * delta / Look.BATTLE_HP_SHAKE_SEC)
	# 赤い部分は少し待ってから縮める
	if _since_hit > Look.BATTLE_HP_LAG_HOLD_SEC and lag_hp > hp:
		lag_hp = maxf(hp, lag_hp - max_hp * delta / Look.BATTLE_HP_LAG_DRAIN_SEC)
	elif lag_hp < hp:
		lag_hp = hp
	for p: Array in popups:
		p[1] = float(p[1]) + delta
	popups = popups.filter(func(p: Array) -> bool: return float(p[1]) < Look.BATTLE_HP_POP_SEC)
	queue_redraw()


func _draw() -> void:
	var off := Vector2.ZERO
	if shake > 0.01:
		off = Vector2(sin(_t * 90.0) * shake, cos(_t * 77.0) * shake * 0.5)
	draw_set_transform(off)
	var full := Rect2(Vector2.ZERO, size)
	# 台：黒い地と太い枠
	draw_rect(full.grow(3.0), Color(0, 0, 0, 0.85))
	draw_rect(full, Look.HP_BAR_BACK)
	var w: float = size.x / max_hp
	var fill_w: float = hp * w
	var lag_w: float = lag_hp * w
	# 遅れて縮む部分（削られた直後は白く光り、そのあと赤）
	if lag_w > fill_w:
		var flash: bool = _since_hit < Look.BATTLE_HP_FLASH_SEC
		var chip: Color = Color(1, 1, 1) if flash else Look.BATTLE_HP_LOST
		draw_rect(_span(fill_w, lag_w), chip)
	# 中身：機体の色。少ないと赤く脈打ち、回復の直後は緑に光る
	var body: Color = color
	if is_low():
		var pulse: float = 0.5 + 0.5 * sin(_t * TAU * Look.BATTLE_HP_LOW_PULSE_HZ)
		body = color.lerp(Look.BATTLE_HP_LOST, 0.35 + 0.45 * pulse)
	if _since_heal < Look.BATTLE_HP_FLASH_SEC * 3.0:
		body = body.lerp(Look.BATTLE_HP_HEAL, 1.0 - _since_heal / (Look.BATTLE_HP_FLASH_SEC * 3.0))
	if fill_w > 0.0:
		var r: Rect2 = _span(0.0, fill_w)
		draw_rect(r, body.darkened(0.25))
		# 上半分を明るく、上端に細い光の筋（金属の板のように見せる）
		draw_rect(Rect2(r.position, Vector2(r.size.x, size.y * 0.5)), body)
		draw_rect(Rect2(r.position + Vector2(0, 2), Vector2(r.size.x, 2)), body.lightened(0.45))
	# 10% ごとの刻み
	for i: int in range(1, 10):
		var x: float = size.x * i / 10.0
		var tick: float = size.y * (0.5 if i == 5 else 0.3)
		draw_line(Vector2(x, size.y - tick), Vector2(x, size.y), Color(0, 0, 0, 0.6), 2.0)
	# 削られた直後は枠も白く光る
	var border: Color = Look.UI_BORDER
	if _since_hit < Look.BATTLE_HP_FLASH_SEC * 2.0:
		border = Color(1, 1, 1)
	elif is_low():
		border = Look.BATTLE_HP_LOST
	draw_rect(full, border, false, 2.0)
	# 減った・増えた数：バーの上（減った端のあたり）に重ねて出し、少し浮かせて消す。
	# バーの下の文字（方針）にかぶらないよう、バーの高さとバーの幅の中に収める
	var font: Font = get_theme_default_font()
	for p: Array in popups:
		var k: float = float(p[1]) / Look.BATTLE_HP_POP_SEC
		var col: Color = p[2]
		col.a = 1.0 - k * k
		var fs: int = int(Look.BATTLE_HP_POP_FONT * (1.0 + 0.3 * maxf(0.0, 1.0 - k * 5.0)))
		var text: String = str(p[0])
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var edge: float = size.x - fill_w if mirrored else fill_w
		var x: float = clampf(edge - tw * 0.5, 4.0, size.x - tw - 4.0)
		var pos := Vector2(x, size.y * 0.5 + fs * 0.35 - 6.0 * k)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, col.a))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(Vector2.ZERO)


## 左端から a〜b の範囲（反転しているときは右端から）
func _span(a: float, b: float) -> Rect2:
	if mirrored:
		return Rect2(size.x - b, 0.0, b - a, size.y)
	return Rect2(a, 0.0, b - a, size.y)
