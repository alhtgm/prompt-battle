# 最終順位。3Dの表彰台に1〜3位の最後の機体を載せて回し、上に順位と名前を重ねる。左下に全員の順位、右下に操作。
# 通信対戦では、ほかの人の機体は届かないので、正体の分からない暗い機体で見せる。状態は読むだけ。値は view/look.gd。
extends Control

const Look := preload("res://view/look.gd")
const PostOverlay := preload("res://view/post_overlay.gd")
const Showroom := preload("res://view/showroom.gd")

const COL_TEXT := Look.UI_TEXT
const COL_DIM := Color(0.55, 0.53, 0.48)
## 1〜3位の光る目印の色（金・銀・銅）
const PLACE_GLOW: Array[Color] = [Color(1.0, 0.78, 0.3), Color(0.8, 0.85, 0.9), Color(0.85, 0.5, 0.3)]

## view/main.gd（画面の切り替え役）
var main: Node
var stage: Showroom
## 表彰台の機体（1位から順）と、その上に重ねる名前の札
var podium_robots: Array[Node3D] = []
var podium_labels: Array[Label] = []
## 全員の順位の行
var ranking_labels: Array[Label] = []
var headline: Label


func build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var s: Variant = main.session
	var order: Array = s.players.duplicate()
	order.sort_custom(func(x: Variant, y: Variant) -> bool: return x.place < y.place)
	_add_stage(order)
	var post := PostOverlay.new()
	add_child(post)
	post.setup(Look.ARENA_POST)

	# 上：見出しと自分の順位
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_label(top, "最終順位", 40, Look.TITLE_COLOR, true)
	_label(top, "%d ラウンドで決着" % s.round_no, 17, COL_DIM, true)

	# 機体の上の名前の札
	for i: int in podium_robots.size():
		var p: Variant = order[i]
		var l: Label = _label(self, "%d位  %s" % [p.place, p.name], 22, PLACE_GLOW[i].lightened(0.1), true)
		podium_labels.append(l)

	# 左下：全員の順位
	var panel := _panel(Control.PRESET_BOTTOM_LEFT)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	panel.add_child(list)
	# 自分の順位は、機体の上の札と重ならないよう、順位の一覧の上に大きく出す
	var mine: Variant = s.get_player(main.human_id)
	headline = _label(list, "あなたは %d位" % mine.place if mine != null else "", 26, Look.UI_ACCENT, false)
	for p: Variant in order:
		var when: String = "最後まで生存" if p.alive else "ラウンド %d で脱落" % p.eliminated_round
		var col: Color = Look.UI_ACCENT if p.id == main.human_id else COL_TEXT
		ranking_labels.append(_label(list, "%d位　%s　（%s）" % [p.place, p.name, when], 17, col, false))

	# 右下：操作
	var ops := _panel(Control.PRESET_BOTTOM_RIGHT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	ops.add_child(col)
	if s.is_online():
		_label(col, "まもなく待合室に戻ります", 16, COL_DIM, false)
		_button(col, "抜けてタイトルへ", to_title)
	else:
		_button(col, "もう一度遊ぶ", play_again).call_deferred("grab_focus")
		_button(col, "タイトルへ", to_title)


func _add_stage(order: Array) -> void:
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
	stage.setup(main.data, Look.PODIUM_STAGE)
	for i: int in mini(3, order.size()):
		var p: Variant = order[i]
		var build: Variant = p.build
		var body: Color = Look.SIDE_BODY[0] if p.id == main.human_id else Look.SIDE_BODY[1]
		if build == null:  # 通信対戦では、ほかの人の機体は届かない
			build = Showroom.make_build(Look.PREVIEW_BASE_FRAME, [], [])
			body = Look.PODIUM_UNKNOWN_BODY
		var pos := Vector3(Look.PODIUM_X[i], 0.0, 0.0)
		podium_robots.append(stage.add_robot_at(build, body, PLACE_GLOW[i], pos, Look.PODIUM_HEIGHT[i]))


## 名前の札を、3Dの機体の頭上に合わせて置く（低い解像度で描いているので、その倍率を掛ける）
func _process(_delta: float) -> void:
	if stage == null or stage.camera == null:
		return
	for i: int in podium_labels.size():
		var l: Label = podium_labels[i]
		var at: Vector3 = podium_robots[i].label_position()
		l.visible = not stage.camera.is_position_behind(at)
		l.reset_size()
		var p: Vector2 = stage.camera.unproject_position(at) * float(Look.PIXEL_SHRINK)
		l.position = p - Vector2(l.size.x * 0.5, l.size.y)


func play_again() -> void:
	main.start_game()


func to_title() -> void:
	main.show_title()


func _panel(preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Look.UI_PANEL
	s.border_color = Look.UI_BORDER
	s.set_border_width_all(1)
	s.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", s)
	add_child(p)
	p.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 20)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN if preset == Control.PRESET_BOTTOM_RIGHT else Control.GROW_DIRECTION_END
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return p


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _label(parent: Control, text: String, size_px: int, col: Color, outline: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if outline else HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
