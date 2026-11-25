# パーツ選びの1種類分の段。見出しと、真ん中に大きいカード・両脇に隣のカードがのぞく並びを持ち、◀▶で送る。
# 真ん中に来たカードがそのまま選ばれる（picked を出す）。見出しに合わせると activated を出す（開くのは画面の役目）。
extends VBoxContainer

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")
const PartCard := preload("res://view/draft/part_card.gd")
const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")

## 真ん中に来たカード（選んだもの）が替わった
signal picked(kind: String, uid: int)
## 見出しにマウスを合わせた・押した
signal activated(kind: String)

var data: GameData
var kind: String = ""
## 候補のパーツ（PartInstance）
var parts: Array = []
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


func setup(game_data: GameData, part_kind: String, offer: Array) -> void:
	data = game_data
	kind = part_kind
	parts = offer
	add_theme_constant_override("separation", 4)
	header = Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.focus_mode = Control.FOCUS_NONE
	header.add_theme_font_size_override("font_size", 22)
	header.mouse_entered.connect(func() -> void: activated.emit(kind))
	header.pressed.connect(func() -> void: activated.emit(kind))
	add_child(header)

	stage = Control.new()
	stage.clip_contents = true
	stage.custom_minimum_size = Vector2(0, Look.DRAFT_CARD_SIZE.y + 12.0)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.resized.connect(func() -> void: _layout(false))
	add_child(stage)
	for p: Variant in parts:
		var card: PartCard = PartCard.new()
		stage.add_child(card)
		card.setup(data, p, null)
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Look.DRAFT_CARD_SIZE
		card.size = Look.DRAFT_CARD_SIZE
		card.pivot_offset = Look.DRAFT_CARD_SIZE * 0.5
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
	picked.emit(kind, current().uid)


## uid のカードを真ん中にする（動かさずに置き直す。picked は出さない）
func select_uid(uid: int) -> void:
	for i: int in parts.size():
		if parts[i].uid == uid:
			index = i
			_update_header()
			_layout(false)
			return


## 開く（カードを見せる）・閉じる（見出しの文字だけにする）
func set_expanded(on: bool) -> void:
	expanded = on
	stage.visible = on
	_update_header()


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
	var kind_name: String = UiText.KIND_LABELS.get(kind, kind)
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
	var center: Vector2 = stage.size * 0.5
	if animate:
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i: int in cards.size():
		var card: Button = cards[i]
		var d: int = offset_of(i)
		var far: bool = absi(d) > 1
		var pos: Vector2 = center + Vector2(float(d) * Look.DRAFT_SIDE_OFFSET, 0.0) - card.size * 0.5
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
