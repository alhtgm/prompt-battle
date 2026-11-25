# 画面の土台。余白つきの縦並びを用意し、見出し・文字・ボタンを足す手伝いをする。スクロールはせず、1画面に収める。
# 各画面はこれを継承し、build_ui() で中身を作る。試合の状態は main.session から読むだけにする。
extends MarginContainer

const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")
const KeyGuide := preload("res://view/key_guide.gd")

const COL_TEXT := Look.UI_TEXT
const COL_DIM := Color(0.55, 0.53, 0.48)
const COL_ACCENT := Look.UI_ACCENT
const COL_BAD := Color(0.95, 0.38, 0.3)
## 画面の四辺の余白（下の余白にはキーガイドを置く）
const MARGIN: int = 32

## view/main.gd（画面の切り替え役）
var main: Node
var box: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, MARGIN)
	# スクロールはしない。中身は画面（1280×720）に収まるように作る（tests/test_ui_flow.gd で確かめる）
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	add_child(box)


## 中身を作る（main に追加された直後に呼ばれる）
func build_ui() -> void:
	pass


func session() -> RefCounted:
	return main.session


func me() -> RefCounted:
	return main.session.get_player(main.human_id)


func add_title(text: String) -> Label:
	return add_label(text, 30, COL_ACCENT, box)


func add_label(text: String, size: int = 18, col: Color = COL_TEXT, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	(parent if parent != null else box).add_child(l)
	return l


func add_button(text: String, on_press: Callable, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(160, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(on_press)
	(parent if parent != null else box).add_child(b)
	return b


func add_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	return row


## 画面下部にキーガイドを置く。items の形は KeyGuide.set_items() と同じ。
## 並び（box）には入れず、画面の下の余白の中に重ねるので、ほかの中身の場所を取らない
func add_key_guide(items: Array) -> KeyGuide:
	var guide := KeyGuide.new()
	guide.top_level = true  # コンテナの並びから外す（位置は画面の下端に合わせる）
	add_child(guide)
	guide.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	guide.offset_left = MARGIN
	guide.offset_right = -MARGIN
	guide.offset_top = -MARGIN + 3
	guide.offset_bottom = -3
	guide.set_items(items)
	return guide


## 通信対戦で操作を送ったあと、ほかの人を待っていることを伝える（ひとりで遊ぶときは何もしない）
func show_waiting(label: Label, text: String = "決定しました。ほかのプレイヤーを待っています") -> void:
	if session().is_online():
		label.text = text
		label.add_theme_color_override("font_color", COL_DIM)


## 左右2列を作る。返すのは [左, 右] の縦並び
func add_columns(left_ratio: float = 1.4) -> Array[VBoxContainer]:
	var row := add_row()
	row.add_theme_constant_override("separation", 40)
	var cols: Array[VBoxContainer] = []
	for ratio: float in [left_ratio, 1.0]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_stretch_ratio = ratio
		col.add_theme_constant_override("separation", 8)
		row.add_child(col)
		cols.append(col)
	return cols


## 体力の一覧（生き残りが上）。short なら「パーク N個」を「パークN」に縮める（狭い場所に並べるとき）
func add_standings(parent: Control = null, font_size: int = 16, short: bool = false) -> void:
	for p: Variant in session().standings():
		var status: String = "%d位" % p.place if p.place > 0 else "生存"
		var col: Color = COL_ACCENT if p.id == main.human_id else (COL_TEXT if p.alive else COL_DIM)
		var perks: String = ("パーク%d" if short else "パーク %d個") % p.perks.size()
		var l: Label = add_label("%s　体力 %d　%s　%s" % [p.name, roundi(p.health), status, perks], font_size, col, parent)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
