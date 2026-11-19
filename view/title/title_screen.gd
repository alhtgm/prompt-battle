# タイトル画面。左にタイトルとメニュー、右で機体がターンテーブルの上で回る（背景は3D）。
# 機体は一回転ごと（背を向けた瞬間）に、全パーツから組み直したものに載せ替わる。
# 遊び方は板を開いて見せる。試合の状態には触れず、操作は main（画面の切り替え役）のメソッドを呼ぶだけ。
extends Control

const Look := preload("res://view/look.gd")
const PostOverlay := preload("res://view/post_overlay.gd")
const Showroom := preload("res://view/showroom.gd")
const Rng := preload("res://core/rng.gd")

const HOW_TO_PLAY: Array[String] = [
	"1. 最初に、フレーム・武器・スキルを1つずつ選ぶ",
	"2. 手持ちのパーツで機体を組み、操縦士へのプロンプト（指示）を書く",
	"3. バトルは操縦士が自分で考えて戦う。あなたは見守るだけ",
	"4. 負けると体力が減る。ラウンドごとにパーツとパークが増えるので、機体とプロンプトを直して挑む",
	"5. 体力が0になったら脱落。6人のうち最後の1人になれば優勝",
]
const MENU_FONT_SIZE: int = 26
## 左の列（タイトルとメニュー）の左の余白と幅
const LEFT_MARGIN: float = 72.0
## メニューの文字の左の空き（合わせたときの金色の線の分）
const MENU_INDENT: float = 18.0
const COLUMN_WIDTH: float = 640.0

## view/main.gd（画面の切り替え役）
var main: Node
var stage: Showroom
var title_label: Label
## メニューのボタン（上から順）
var menu_buttons: Array[Button] = []
var how_to_panel: PanelContainer
## 機体を載せ替えた回数
var swaps: int = 0
var _rng: Rng
var _time: float = 0.0


func build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add_stage()
	var post := PostOverlay.new()
	add_child(post)
	post.setup(Look.ARENA_POST)

	# 左の列：上にタイトル、その下にメニュー（R.E.P.O のように左に寄せる）。右は3Dの機体の場所
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = LEFT_MARGIN
	col.offset_right = LEFT_MARGIN + COLUMN_WIDTH
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	_spacer(col, 56)

	title_label = _label(col, "PROMPT BATTLE", 76, Look.TITLE_COLOR)
	title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	title_label.add_theme_constant_override("outline_size", 14)
	title_label.add_theme_color_override("font_shadow_color", Look.TITLE_SHADOW)
	title_label.add_theme_constant_override("shadow_offset_x", 5)
	title_label.add_theme_constant_override("shadow_offset_y", 6)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sub: Label = _label(col, "プロンプトバトル（仮）　―　指示を書け。操縦は任せろ。", 17, Look.UI_TEXT.darkened(0.25))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sub.add_theme_constant_override("outline_size", 6)
	_spacer(col, 56)

	# メニュー（文字だけのボタン。合わせると金色になり、左に金色の線が出る）
	var menu := VBoxContainer.new()
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu.add_theme_constant_override("separation", 2)
	col.add_child(menu)
	_menu_button(menu, "ひとりで遊ぶ", start)
	_menu_button(menu, "オンラインで遊ぶ", open_online)
	_menu_button(menu, "遊び方", toggle_how_to)
	_menu_button(menu, "観戦画面（開発用）", open_debug_viewer)
	_menu_button(menu, "やめる", quit_game)
	# 下は空けておき、3Dの機体が見えるようにする
	_add_how_to()
	menu_buttons[0].call_deferred("grab_focus")


func _add_stage() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = Look.PIXEL_SHRINK
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	container.add_child(vp)
	stage = Showroom.new()
	vp.add_child(stage)
	stage.setup(main.data, Look.TITLE_STAGE)
	# 見た目だけに使う乱数（試合の乱数とは別）。種は起動した時刻から作るので、毎回ちがう機体から始まる
	_rng = Rng.new(Time.get_ticks_usec() + 1)
	swap_robot()
	stage.turned_away.connect(_on_turned_away)


## 全パーツから組み直した機体に載せ替える。色は2つの陣営の色を交互に使う
func swap_robot() -> void:
	var side: int = swaps % 2
	stage.show_build(Showroom.random_build(main.data, _rng), Look.SIDE_BODY[1 - side], Look.SIDE_GLOW[1 - side])
	swaps += 1


## 背を向けた瞬間に、電球を瞬かせて載せ替える
func _on_turned_away() -> void:
	stage.flicker()
	swap_robot()


func _menu_button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, 46)
	b.add_theme_font_size_override("font_size", MENU_FONT_SIZE)
	b.add_theme_color_override("font_color", Look.UI_TEXT)
	b.add_theme_color_override("font_hover_color", Look.UI_ACCENT)
	b.add_theme_color_override("font_focus_color", Look.UI_ACCENT)
	b.add_theme_color_override("font_pressed_color", Look.UI_ACCENT.lightened(0.2))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	b.add_theme_constant_override("outline_size", 8)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = MENU_INDENT  # 合わせても文字が動かないよう、下地と同じだけ空ける
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", _menu_box())
	b.add_theme_stylebox_override("focus", _menu_box())
	b.add_theme_stylebox_override("pressed", _menu_box())
	b.pressed.connect(on_press)
	# 合わせたらフォーカスも移し、キーボードとマウスで印が二重に出ないようにする
	b.mouse_entered.connect(b.grab_focus)
	parent.add_child(b)
	menu_buttons.append(b)
	return b


## 合わせたボタンの下地：左から右へ薄れていく暗い帯と、左端の金色の線
static func _menu_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.45)
	s.border_color = Look.UI_ACCENT
	s.border_width_left = 4
	s.set_content_margin_all(4)
	s.content_margin_left = MENU_INDENT
	return s


func _add_how_to() -> void:
	how_to_panel = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Look.UI_PANEL
	s.border_color = Look.UI_BORDER
	s.set_border_width_all(1)
	s.set_content_margin_all(20)
	how_to_panel.add_theme_stylebox_override("panel", s)
	how_to_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	how_to_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	how_to_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	how_to_panel.visible = false
	add_child(how_to_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	how_to_panel.add_child(box)
	var head: Label = _label(box, "遊び方", 26, Look.UI_ACCENT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for line: String in HOW_TO_PLAY:
		var l: Label = _label(box, line, 18, Look.UI_TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var close := Button.new()
	close.text = "閉じる"
	close.custom_minimum_size = Vector2(140, 40)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(toggle_how_to)
	box.add_child(close)


func toggle_how_to() -> void:
	how_to_panel.visible = not how_to_panel.visible
	if how_to_panel.visible:
		how_to_panel.reset_size()
		how_to_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		(how_to_panel.get_child(0).get_child(-1) as Button).grab_focus()
	else:
		menu_buttons[2].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if how_to_panel != null and how_to_panel.visible and event.is_action_pressed("ui_cancel"):
		toggle_how_to()
		get_viewport().set_input_as_handled()


## タイトルの文字が、古い看板のようにときどき一瞬暗くなる（時間の関数。乱数は使わない）
func _process(delta: float) -> void:
	_time += delta
	var t: float = fmod(_time, Look.TITLE_FLICKER_PERIOD)
	var dim: bool = (t > 0.0 and t < 0.06) or (t > 0.14 and t < 0.2)
	title_label.modulate = Color(1, 1, 1) * (1.0 - Look.TITLE_FLICKER_DIM if dim else 1.0)
	title_label.modulate.a = 1.0


func start() -> void:
	main.start_game()


func open_online() -> void:
	main.open_online()


func open_debug_viewer() -> void:
	get_tree().change_scene_to_file("res://view/debug/battle_viewer.tscn")


func quit_game() -> void:
	get_tree().quit()


func _label(parent: Control, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _spacer(parent: Control, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
