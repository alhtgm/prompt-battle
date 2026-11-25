# 開始時のパーツ選び。全員に同じ候補（種類ごとに5つ）を、種類ごとの段で1枚ずつ大きく見せ、◀▶で送って選ぶ。
# 開いている段は1つだけ（見出しに合わせると開く）。右に選んだ3つで組んだ機体の見本と、詳しい性能を出す。
# 操作は MatchSession のメソッドだけを通す。
extends "res://view/screen_base.gd"

const GameData := preload("res://core/game_data.gd")
const PartCarousel := preload("res://view/draft/part_carousel.gd")
const BuildPreview := preload("res://view/draft/build_preview.gd")

## 種類 → 選んだ uid（真ん中のカード）
var picks: Dictionary = {}
## 種類 → 段
var carousels: Dictionary = {}
## 今開いている段の種類
var active_kind: String = ""
var build_preview: BuildPreview
var back_button: Button
var _confirm: Button
var _message: Label


func build_ui() -> void:
	# 見出しの行：左に題、右にタイトルへ戻るボタン
	var head := add_row()
	var title: Label = add_label("最初のパーツを選ぶ", 30, COL_ACCENT, head)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button = add_button("タイトルへ戻る", back_to_title, head)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_label("フレーム・武器・スキルから1つずつ選ぶ。見出しに合わせるとその種類が開き、◀▶（←→キー）で真ん中に来たものが選ばれる。候補は全員同じ。", 15, COL_DIM)
	var cols: Array[VBoxContainer] = add_columns(1.25)
	var left: VBoxContainer = cols[0]
	left.add_theme_constant_override("separation", 6)
	for kind: String in GameData.KINDS:
		var c: PartCarousel = PartCarousel.new()
		left.add_child(c)
		c.setup(main.data, kind, session().draft_offer[kind])
		c.picked.connect(_on_picked)
		c.activated.connect(activate)
		carousels[kind] = c
		if c.current() != null:
			picks[kind] = c.current().uid
	# 段と決定ボタンの間を少し空ける
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	left.add_child(gap)
	# 決定ボタンと、うまくいかなかったときの文字。ボタンは真ん中のカードと同じ横位置（列の中央）に置き、文字はその下に出す
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	left.add_child(bottom)
	_confirm = add_button("決定", confirm, bottom)
	_confirm.custom_minimum_size = Vector2(200, 60)
	_confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_message = add_label("", 17, COL_BAD, bottom)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_preview = BuildPreview.new()
	cols[1].add_child(build_preview)
	build_preview.setup(main.data)
	activate(GameData.KINDS[0], false)
	_refresh()


## kind の段だけを開き、ほかは見出しの文字だけにする（animate なら少しずつ開閉する）
func activate(kind: String, animate: bool = true) -> void:
	if not carousels.has(kind) or (kind == active_kind and animate):
		return
	active_kind = kind
	for k: String in carousels:
		carousels[k].set_expanded(k == kind, animate)


## 開いている段のカードを送る（+1 で右、-1 で左）
func move(dir: int) -> void:
	if carousels.has(active_kind):
		carousels[active_kind].step(dir)


## 開く段を上下に替える（+1 で下、-1 で上。端で止まる）
func switch_section(dir: int) -> void:
	var i: int = GameData.KINDS.find(active_kind)
	activate(GameData.KINDS[clampi(i + dir, 0, GameData.KINDS.size() - 1)])


## kind のパーツを uid にする（真ん中に置き直す）
func select(kind: String, uid: int) -> void:
	if not carousels.has(kind):
		return
	carousels[kind].select_uid(uid)  # 候補にない uid なら今のまま
	picks[kind] = carousels[kind].current().uid
	_refresh()


## 選んだものを試合に伝えて、パーツ選びを締め切る。問題があれば理由を返す
func confirm() -> String:
	var err: String = session().draft_pick(main.human_id, picks)
	if not err.is_empty():
		_message.text = err
		return err
	show_waiting(_message)
	session().finish_draft()
	return ""


## 試合をやめてタイトルへ戻る（通信対戦なら接続も切る）
func back_to_title() -> void:
	main.show_title()


## ←→でカードを送り、↑↓で開く段を替える
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var handled: bool = true
	if event.is_action_pressed("ui_left", true):
		move(-1)
	elif event.is_action_pressed("ui_right", true):
		move(1)
	elif event.is_action_pressed("ui_up", true):
		switch_section(-1)
	elif event.is_action_pressed("ui_down", true):
		switch_section(1)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _on_picked(kind: String, uid: int) -> void:
	picks[kind] = uid
	_refresh()


## 右の見本と一覧、決定ボタンを今の選択に合わせる
func _refresh() -> void:
	if build_preview == null:
		return
	var chosen: Dictionary = {}
	for kind: String in carousels:
		chosen[kind] = carousels[kind].current()
	build_preview.show_parts(chosen)
	_confirm.disabled = picks.size() < GameData.KINDS.size()
