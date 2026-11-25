# パーツ選びの1種類分の段。見出しと、真ん中に大きいカード・両脇に隣のカードがのぞく並びを持ち、◀▶で送る。
# 真ん中に来たカードがそのまま選ばれる（picked を出す）。見出しに合わせると activated を出す（開くのは画面の役目）。
# 組み立て画面では「なし（付けない）」のカードを最後に足せる（parts の中では null、uid は -1 として扱う）。
extends VBoxContainer

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")
const PartCard := preload("res://view/draft/part_card.gd")
const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")

## 真ん中に来たカード（選んだもの）が替わった（「なし」なら uid は -1）
signal picked(kind: String, uid: int)
## 見出しにマウスを合わせた・押した
signal activated(kind: String)

var data: GameData
var kind: String = ""
## 候補のパーツ（PartInstance。「なし」のカードは null）
var parts: Array = []
## 見出しの名前（空なら種類の名前）
var title: String = ""
## 真ん中のカードの大きさと見出しの文字の大きさ（setup の前に変えられる。組み立て画面は小さめにする）
var card_size: Vector2 = Look.DRAFT_CARD_SIZE
var header_font: int = 22
## 真ん中にあるカードの番号（parts の中の位置）
var index: int = 0
var expanded: bool = true
var header: Button
var cards: Array[Button] = []
var prev_button: Button
var next_button: Button
## カードを並べる台（閉じると隠す）
var stage: Control
var _tween: Tween = null
## 開く・閉じる動き
var _open_tween: Tween = null
## 前に並べたときの台の幅（高さだけ変わったときは並べ直さない）
var _laid_width: float = -1.0


## title は見出しの名前（空なら種類の名前）。allow_none なら最後に「なし」のカードを足す。
## badges は uid → カードの右下の札（"NEW" など）
func setup(game_data: GameData, part_kind: String, offer: Array, part_title: String = "",
		allow_none: bool = false, badges: Dictionary = {}) -> void:
	data = game_data
	kind = part_kind
	title = part_title
	parts = offer + ([null] if allow_none else [])
	add_theme_constant_override("separation", 4)
	header = Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.focus_mode = Control.FOCUS_NONE
	header.add_theme_font_size_override("font_size", header_font)
	header.mouse_entered.connect(func() -> void: activated.emit(kind))
	header.pressed.connect(func() -> void: activated.emit(kind))
	add_child(header)

	stage = Control.new()
	stage.clip_contents = true
	stage.custom_minimum_size = Vector2(0, _full_height())
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.resized.connect(func() -> void:
		if not is_equal_approx(stage.size.x, _laid_width):
			_layout(false))
	add_child(stage)
	for p: Variant in parts:
		var card: Button = _none_card() if p == null else PartCard.new()
		stage.add_child(card)
		if p != null:
			card.setup(data, p, null, str(badges.get(p.uid, "")))
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = card_size
		card.size = card_size
		card.pivot_offset = card_size * 0.5
		card.pressed.connect(_on_card_pressed.bind(cards.size()))
		cards.append(card)
	prev_button = _arrow("◀", -1)
	prev_button.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	prev_button.offset_right = Look.DRAFT_ARROW_WIDTH
	next_button = _arrow("▶", 1)
	next_button.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	next_button.offset_left = -Look.DRAFT_ARROW_WIDTH
	_update_header()
	_layout(false)


## 今選んでいる（真ん中の）パーツ
func current() -> PartInstance:
	return parts[index] if not parts.is_empty() else null


## dir（+1 で右の、-1 で左の）カードを真ん中に送る。端は輪になる
func step(dir: int) -> void:
	if parts.is_empty() or dir == 0:
		return
	index = posmod(index + dir, parts.size())
	_update_header()
	_layout(true)
	picked.emit(kind, current_uid())


## 今選んでいるパーツの uid（「なし」なら -1）
func current_uid() -> int:
	var p: PartInstance = current()
	return p.uid if p != null else -1


## uid のカードを真ん中にする（-1 なら「なし」。動かさずに置き直す。picked は出さない）
func select_uid(uid: int) -> void:
	for i: int in parts.size():
		if (parts[i].uid if parts[i] != null else -1) == uid:
			index = i
			_update_header()
			_layout(false)
			return


## 開く（カードを見せる）・閉じる（見出しの文字だけにする）。animate なら台の高さと濃さを少しずつ変える
func set_expanded(on: bool, animate: bool = false) -> void:
	expanded = on
	_update_header()
	if _open_tween != null:
		_open_tween.kill()
		_open_tween = null
	var h: float = _full_height() if on else 0.0
	var a: float = 1.0 if on else 0.0
	if not animate:
		stage.visible = on
		stage.custom_minimum_size.y = h
		stage.modulate.a = a
		return
	stage.visible = true
	_open_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(stage, "custom_minimum_size:y", h, Look.DRAFT_EXPAND_SEC)
	_open_tween.tween_property(stage, "modulate:a", a, Look.DRAFT_EXPAND_SEC)
	if not on:
		_open_tween.chain().tween_callback(func() -> void: stage.visible = false)


## 開いたときの台の高さ
func _full_height() -> float:
	return card_size.y + 12.0


## 真ん中からいくつ離れているか（輪にして、-n/2 〜 n/2 の範囲で数える）
func offset_of(i: int) -> int:
	var n: int = parts.size()
	var half: int = floori(n * 0.5)
	return posmod(i - index + half, n) - half


func _on_card_pressed(i: int) -> void:
	var d: int = offset_of(i)
	if d != 0:
		step(signi(d))


func _update_header() -> void:
	var kind_name: String = title if not title.is_empty() else UiText.KIND_LABELS.get(kind, kind)
	var part_name: String = data.get_part(current().def_id).name if current() != null else "なし"
	header.text = "%s %s：%s" % ["▼" if expanded else "▶", kind_name, part_name]
	var col: Color = Look.KIND_COLORS.get(kind, Look.UI_ACCENT) if expanded else Color(0.62, 0.6, 0.55)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		header.add_theme_color_override(state, col.lightened(0.15) if state == "font_hover_color" else col)


## カードを置き直す。真ん中は大きく前に、両脇は小さく暗く後ろに、それより遠いものは消す
func _layout(animate: bool) -> void:
	if stage == null or cards.is_empty():
		return
	if _tween != null:
		_tween.kill()
		_tween = null
	# 縦の真ん中は開いたときの高さで決める（開く途中でカードが上下に動かず、上から現れるように）
	_laid_width = stage.size.x
	var center := Vector2(stage.size.x * 0.5, _full_height() * 0.5)
	if animate:
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i: int in cards.size():
		var card: Button = cards[i]
		var d: int = offset_of(i)
		var far: bool = absi(d) > 1
		var side: float = Look.DRAFT_SIDE_OFFSET * card_size.x / Look.DRAFT_CARD_SIZE.x  # 小さいカードでは隣も近づける
		var pos: Vector2 = center + Vector2(float(d) * side, 0.0) - card.size * 0.5
		var s: float = 1.0 if d == 0 else Look.DRAFT_SIDE_SCALE * (0.8 if far else 1.0)
		var dim: float = 1.0 if d == 0 else Look.DRAFT_SIDE_DIM
		var mod := Color(dim, dim, dim, 0.0 if far else 1.0)
		card.z_index = 0 if far else (2 if d == 0 else 1)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE if far else Control.MOUSE_FILTER_STOP
		if animate:
			_tween.tween_property(card, "position", pos, Look.DRAFT_SLIDE_SEC)
			_tween.tween_property(card, "scale", Vector2(s, s), Look.DRAFT_SLIDE_SEC)
			_tween.tween_property(card, "modulate", mod, Look.DRAFT_SLIDE_SEC)
		else:
			card.position = pos
			card.scale = Vector2(s, s)
			card.modulate = mod


## 「なし（付けない）」のカード
func _none_card() -> Button:
	var b := Button.new()
	b.text = "なし
（付けない）"
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Look.UI_TEXT.darkened(0.3))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.065, 0.06)
	st.border_color = Look.UI_BORDER
	st.set_border_width_all(1)
	st.set_corner_radius_all(2)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, st)
	return b


## 台の端に置く ◀▶ のボタン（両脇のカードの上に重なる）
func _arrow(text: String, dir: int) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.z_index = 3
	b.add_theme_font_size_override("font_size", 34)
	for state: String in ["font_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, Look.DRAFT_ARROW_COLOR)
	b.add_theme_color_override("font_hover_color", Look.DRAFT_ARROW_COLOR.lightened(0.3))
	b.pressed.connect(step.bind(dir))
	stage.add_child(b)
	return b
