# 画面の土台。余白つきの縦並びを用意し、見出し・文字・ボタンを足す手伝いをする。
# 各画面はこれを継承し、build_ui() で中身を作る。試合の状態は main.session から読むだけにする。
extends MarginContainer

const UiText := preload("res://view/ui_text.gd")

const COL_TEXT := Color(0.92, 0.92, 0.9)
const COL_DIM := Color(0.62, 0.62, 0.6)
const COL_ACCENT := Color(1.0, 0.85, 0.4)
const COL_BAD := Color(1.0, 0.45, 0.4)

## view/main.gd（画面の切り替え役）
var main: Node
var box: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, 32)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)


## 中身を作る（main に追加された直後に呼ばれる）
func build_ui() -> void:
	pass


func session() -> RefCounted:
	return main.session


func me() -> RefCounted:
	return main.session.get_player(main.HUMAN_ID)


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


## 体力の一覧（生き残りが上）
func add_standings(parent: Control = null) -> void:
	for p: Variant in session().standings():
		var status: String = "%d位" % p.place if p.place > 0 else "生存"
		var col: Color = COL_ACCENT if p.id == main.HUMAN_ID else (COL_TEXT if p.alive else COL_DIM)
		add_label("%s　体力 %d　%s　パーク %d個" % [p.name, roundi(p.health), status, p.perks.size()], 16, col, parent)
