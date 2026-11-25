# ラウンド結果。自分の勝ち負けをスタンプで押し、負けたらダメージの内訳（順位の分＋差の分）を見せる。
# 6人の体力バーを順位の順に並べ、減った分を赤く残してから縮める。脱落した人には順位の札を押す。ほかの試合は短く1行ずつ。
# 状態は読むだけで、操作は MatchSession のメソッドだけを通す。
extends "res://view/screen_base.gd"

const MatchSession := preload("res://core/match_session.gd")
const Damage := preload("res://core/damage.gd")
const HealthBar := preload("res://view/results/health_bar.gd")

const STAMP_SIZE := Vector2(230, 110)

## 押したスタンプ（自分が戦っていなければ null）と、その文字（"WIN" / "LOSE" / "DRAW"）と動き
var stamp: Label = null
var stamp_word: String = ""
var stamp_tween: Tween = null
## ダメージの内訳の行（負けていなければ空）
var breakdown_lines: Array[Label] = []
## プレイヤーID → 体力バー
var bars: Dictionary = {}
var _countdown: Label = null
var _tags: Array = []  # [札, 出す時刻]
var _t: float = 0.0
## 体力バーの行を並べる場所
var _bar_list: VBoxContainer


func build_ui() -> void:
	var s: Variant = session()
	var h: Dictionary = s.history[s.history.size() - 1]
	add_title("ラウンド %d の結果" % h["round"])
	_add_my_result(h)
	# 1画面に収めるため、体力バーと試合の一覧は行の間を詰めて並べる
	add_label("体力", 20, COL_ACCENT)
	_bar_list = VBoxContainer.new()
	_bar_list.add_theme_constant_override("separation", 1)  # フォントが DotGothic16 で行が少し高いので、1px に詰める
	box.add_child(_bar_list)
	_add_bars(h)
	add_label("このラウンドの試合", 18, COL_DIM)
	var battles := VBoxContainer.new()
	battles.add_theme_constant_override("separation", 0)
	box.add_child(battles)
	for e: Dictionary in h["battles"]:
		var a: String = _name(int(e["a"]), -1)
		var b: String = _name(int(e["b"]), int(e["ghost_of"]))
		var w: int = int(e["winner"])
		var who: String = "引き分け" if w == -2 else "%s の勝ち" % (a if w == int(e["a"]) else b)
		var involved: bool = int(e["a"]) == main.human_id or int(e["b"]) == main.human_id
		add_label("%s vs %s → %s（%s、%.0f秒）" % [a, b, who, UiText.REASON_LABELS.get(e["reason"], ""), e["time"]],
			16, COL_ACCENT if involved else COL_TEXT, battles)
	if not me().alive:
		add_label("あなたは脱落した。最後まで観戦できる。", 17, COL_DIM)
	# 一番下の行：次へ（通信対戦では残り秒数）と、開発用のスタンプの試し押し
	var last := add_row()
	last.add_theme_constant_override("separation", 24)
	if s.is_online():
		_countdown = add_label("", 18, COL_DIM, last)  # 通信対戦では、サーバーが少し待ってから次へ進める
		_countdown.autowrap_mode = TextServer.AUTOWRAP_OFF
	else:
		add_button("次へ", next, last)
	if OS.is_debug_build() and stamp != null:
		_add_stamp_preview(last)


func _process(delta: float) -> void:
	_t += delta
	for entry: Array in _tags:
		var tag: Control = entry[0]
		tag.modulate.a = 1.0 if _t >= float(entry[1]) else 0.0
	if _countdown != null and main.session != null:
		_countdown.text = "%d 秒後に次へ進みます" % ceili(session().phase_time_left)


## 自分の試合の結果：左にスタンプ、右に決着のつき方とダメージの内訳（自分が戦っていなければ観戦中と出す）
func _add_my_result(h: Dictionary) -> void:
	var id: int = main.human_id
	for e: Dictionary in h["battles"]:
		if int(e["a"]) != id and int(e["b"]) != id:
			continue
		var w: int = int(e["winner"])
		var row := add_row()
		row.add_theme_constant_override("separation", 36)
		var word: String = "WIN" if w == id else ("DRAW" if w == -2 else "LOSE")
		row.add_child(_make_stamp(word))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_theme_constant_override("separation", 4)
		row.add_child(info)
		var opp_id: int = int(e["b"]) if int(e["a"]) == id else int(e["a"])
		var opp: String = _name(opp_id, int(e["ghost_of"]))
		var how: String = UiText.REASON_LABELS.get(e["reason"], "")
		var head: String
		if w == id:
			head = "%s に勝った（%s、%.0f秒）" % [opp, how, e["time"]]
		elif w == -2:
			head = "%s と引き分け（%.0f秒）" % [opp, e["time"]]
		else:
			head = "%s に負けた（%s、%.0f秒）" % [opp, how, e["time"]]
		add_label(head, 22, COL_TEXT, info)
		_add_breakdown(h, e, w, info)
		if h["eliminated"].has(id):
			add_label("体力が0になり脱落（%d位）" % me().place, 20, COL_BAD, info)
		return
	add_label("観戦中（あなたは脱落している）", 22, COL_DIM)


## ダメージの内訳。負けたら「順位の分＋差の分」、勝ちと引き分け（ダメージなしの設定）は一言
func _add_breakdown(h: Dictionary, e: Dictionary, w: int, parent: Control) -> void:
	var id: int = main.human_id
	var dmg: int = int(h["damage"].get(id, 0))
	var cfg: Dictionary = main.data.rules["damage"]
	var rank: int = int(h["ranks"].get(id, 0))
	if w == id:
		breakdown_lines.append(add_label("ダメージなし", 18, COL_DIM, parent))
		return
	if w == -2:
		if dmg <= 0:
			breakdown_lines.append(add_label("引き分けなのでダメージなし", 18, COL_DIM, parent))
		else:
			breakdown_lines.append(add_label("受けたダメージ −%d（順位の分：%s × %d位）" % [dmg, _num(float(cfg["rank_coef"])), rank], 20, COL_BAD, parent))
		return
	var parts: Dictionary = Damage.loss_parts(rank, float(e["margin"]), cfg)
	breakdown_lines.append(add_label("受けたダメージ −%d" % dmg, 24, COL_BAD, parent))
	breakdown_lines.append(add_label("　順位の分　%s × %d位（ラウンド前の体力の順位）＝ %s" % [
		_num(float(cfg["rank_coef"])), rank, _num(float(parts["rank"]))], 16, COL_TEXT, parent))
	breakdown_lines.append(add_label("　差の分　　%s × 相手の残りHP %d%% ＝ %s" % [
		_num(float(cfg["margin_coef"])), roundi(clampf(float(e["margin"]), 0.0, 1.0) * 100.0), _num(float(parts["margin"]))],
		16, COL_TEXT, parent))
	breakdown_lines.append(add_label("　（上位にいるほど、相手を残して負けるほど、多く減る）", 14, COL_DIM, parent))


## 勝ち負けのスタンプの台。中の文字と動きは play_stamp で決める。
## 台は、LOSE で傾いたスタンプがはみ出さない（左端がスクロールの枠で切れない）だけ広く取る
func _make_stamp(word: String) -> Control:
	var pad: Vector2 = _tilt_pad()
	var holder := Control.new()
	holder.custom_minimum_size = STAMP_SIZE + pad * 2.0
	stamp = Label.new()
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stamp.add_theme_font_size_override("font_size", 64)
	stamp.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	stamp.add_theme_constant_override("outline_size", 10)
	stamp.clip_contents = true  # 光の筋をスタンプの中だけに出す
	stamp.size = STAMP_SIZE
	stamp.position = pad
	stamp.pivot_offset = STAMP_SIZE * 0.5
	holder.add_child(stamp)
	play_stamp(word)
	return holder


## 傾いたスタンプが元の大きさから片側にはみ出す幅と高さ
static func _tilt_pad() -> Vector2:
	var a: float = absf(deg_to_rad(Look.STAMP_TILT_DEG))
	var half: Vector2 = STAMP_SIZE * 0.5
	var rotated := Vector2(half.x * cos(a) + half.y * sin(a), half.x * sin(a) + half.y * cos(a))
	return (rotated - half).max(Vector2.ZERO).ceil()


## スタンプを押す（押し直す）。どれも大きい状態からまっすぐドンと押し込み、そのあとが違う：
## LOSE は斜めに傾く、WIN は style（"bounce" 弾む / "shine" 光る）、DRAW はそのまま
func play_stamp(word: String, style: String = Look.WIN_STAMP_STYLE) -> void:
	stamp_word = word
	var col: Color = Look.STAMP_WIN if word == "WIN" else (Look.STAMP_DRAW if word == "DRAW" else Look.STAMP_LOSE)
	stamp.text = word
	stamp.add_theme_color_override("font_color", col)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(col, 0.08)
	box.border_color = col
	box.set_border_width_all(5)
	box.set_corner_radius_all(6)
	stamp.add_theme_stylebox_override("normal", box)
	if stamp_tween != null:
		stamp_tween.kill()
	for c: Node in stamp.get_children():
		c.queue_free()
	stamp.rotation = 0.0
	stamp.scale = Vector2.ONE * Look.STAMP_START_SCALE
	stamp.modulate = Color(1, 1, 1, 0)
	stamp_tween = create_tween()
	var tw: Tween = stamp_tween
	tw.tween_property(stamp, "scale", Vector2.ONE, Look.STAMP_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(stamp, "modulate:a", 1.0, Look.STAMP_SEC * 0.6)
	tw.tween_interval(Look.STAMP_TILT_DELAY)
	if word == "LOSE":
		# 少し置いてから、はずみをつけて斜めに傾く
		var tilt: PropertyTweener = tw.tween_property(stamp, "rotation", deg_to_rad(Look.STAMP_TILT_DEG), Look.STAMP_TILT_SEC)
		tilt.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif word == "WIN" and style == "bounce":
		# 歓声で弾むように、ふくらんで戻るのを繰り返す
		for i: int in Look.STAMP_BOUNCE_COUNT:
			var up: float = 1.0 + (Look.STAMP_BOUNCE_SCALE - 1.0) / float(i + 1)
			tw.tween_property(stamp, "scale", Vector2.ONE * up, Look.STAMP_BOUNCE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(stamp, "scale", Vector2.ONE, Look.STAMP_BOUNCE_SEC).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	elif word == "WIN" and style == "shine":
		# 金色にパッと光り、光の筋が左から右へ走る
		var glint := ColorRect.new()
		glint.color = Color(1.0, 0.97, 0.85, 0.6)
		glint.size = Vector2(26, STAMP_SIZE.y * 2.0)
		glint.rotation = deg_to_rad(20.0)
		glint.position = Vector2(-60, -STAMP_SIZE.y * 0.4)
		glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stamp.add_child(glint)
		tw.tween_property(stamp, "modulate", Color(Look.STAMP_FLASH, Look.STAMP_FLASH, Look.STAMP_FLASH, 1.0), 0.05)
		tw.tween_property(stamp, "modulate", Color(1, 1, 1, 1), Look.STAMP_SHINE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(glint, "position:x", STAMP_SIZE.x + 40.0, Look.STAMP_SHINE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 開発用：スタンプの見え方を見比べるボタン（WIN 弾む／WIN 光る／LOSE／DRAW）
func _add_stamp_preview(row: HBoxContainer) -> void:
	var head: Label = add_label("[開発] スタンプを試し押し：", 14, COL_DIM, row)
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for spec: Array in [["WIN 弾む", "WIN", "bounce"], ["WIN 光る", "WIN", "shine"], ["LOSE", "LOSE", ""], ["DRAW", "DRAW", ""]]:
		var b := Button.new()
		b.text = spec[0]
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(play_stamp.bind(spec[1], spec[2]))
		row.add_child(b)


## 全員の体力バー（生き残りが上、体力の多い順）。減った分は数字でも出す
func _add_bars(h: Dictionary) -> void:
	var max_hp: float = float(main.data.rule("initial_health"))
	var i: int = 0
	for p: Variant in session().standings():
		var dmg: int = int(h["damage"].get(p.id, 0))
		var after: float = float(h["health"].get(p.id, p.health))
		var out_before: bool = not p.alive and not h["eliminated"].has(p.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		_bar_list.add_child(row)
		var mine: bool = p.id == main.human_id
		var name_label: Label = add_label(p.name, 18, COL_ACCENT if mine else (COL_DIM if out_before else COL_TEXT), row)
		name_label.custom_minimum_size = Vector2(150, 0)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		var bar: HealthBar = HealthBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.setup(max_hp, after + dmg, after, mine, out_before, 0.3 + Look.HP_BAR_STAGGER_SEC * i)
		row.add_child(bar)
		bars[p.id] = bar
		var value: String = "%d" % maxi(0, roundi(after))
		if dmg > 0:
			value += "（−%d）" % dmg
		var v: Label = add_label(value if not out_before else "―", 18, COL_BAD if dmg > 0 else COL_TEXT, row)
		v.custom_minimum_size = Vector2(110, 0)
		v.autowrap_mode = TextServer.AUTOWRAP_OFF
		# 脱落の札（このラウンドで脱落した人は、バーが減りきってから押す）
		var tag: Label = add_label("", 16, Color.BLACK, row)
		tag.custom_minimum_size = Vector2(90, 0)
		tag.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if not p.alive:
			tag.text = "脱落 %d位" % p.place
			var ts := StyleBoxFlat.new()
			ts.bg_color = Look.STAMP_LOSE if not out_before else Look.HP_BAR_OUT
			tag.add_theme_stylebox_override("normal", ts)
			_tags.append([tag, 0.0 if out_before else bar.total_sec()])
			tag.modulate.a = 0.0 if not out_before else 1.0
		i += 1


func next() -> void:
	session().finish_round_result()


func _name(id: int, ghost_of: int) -> String:
	if id == MatchSession.GHOST_ID:
		return "%s（記録）" % session().get_player(ghost_of).name
	return session().get_player(id).name


static func _num(v: float) -> String:
	return str(roundi(v)) if absf(v - roundf(v)) < 0.05 else "%.1f" % v
