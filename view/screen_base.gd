# 画面の土台。余白つきの縦並びを用意し、見出し・文字・ボタンを足す手伝いをする。
# 各画面はこれを継承し、build_ui() で中身を作る。試合の状態は main.session から読むだけにする。
extends MarginContainer

const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")

const COL_TEXT := Look.UI_TEXT
const COL_DIM := Color(0.55, 0.53, 0.48)
const COL_ACCENT := Look.UI_ACCENT
const COL_BAD := Color(0.95, 0.38, 0.3)

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


## 体力の一覧（生き残りが上）
func add_standings(parent: Control = null, font_size: int = 16) -> void:
	# 名前・体力のバー・数字・状態を表に並べ、差がひと目で分かるようにする
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	(parent if parent != null else box).add_child(grid)
	var full: float = float(main.data.rule("initial_health"))
	for p: Variant in session().standings():
		var status: String = "%d位" % p.place if p.place > 0 else "生存"
		var col: Color = COL_ACCENT if p.id == main.human_id else (COL_TEXT if p.alive else COL_DIM)
		_cell(add_label(p.name, font_size, col, grid))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(120, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = full
		bar.value = p.health
		grid.add_child(bar)
		_cell(add_label("体力 %d" % roundi(p.health), font_size, col, grid))
		_cell(add_label("%s　パーク %d個" % [status, p.perks.size()], font_size, COL_DIM if p.alive else col, grid))


## 表の中の文字は折り返さない（折り返すと幅が0になって縦に並んでしまう）
func _cell(l: Label) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
