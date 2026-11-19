# 開始時のパーツ選び。全員に同じ候補（種類ごとに5つ）をカードで見せ、種類ごとに1つ選ぶ。
# カードに合わせる（フォーカスする）と、見本と効果の吹き出しが出る。下の欄に今選んでいる構成を出す。
# 操作は MatchSession のメソッドだけを通す。
extends "res://view/screen_base.gd"

const GameData := preload("res://core/game_data.gd")
const PartCard := preload("res://view/draft/part_card.gd")
const PartTooltip := preload("res://view/draft/part_tooltip.gd")

## 種類 → 選んだ uid
var picks: Dictionary = {}
## uid → カード
var cards: Dictionary = {}
var tooltip: PartTooltip
var back_button: Button
## 種類 → 構成の欄の [名前, ステータス] の文字
var summary_labels: Dictionary = {}
var _confirm: Button
var _message: Label


func build_ui() -> void:
	# 見出しの行：左に題、右にタイトルへ戻るボタン
	var head := add_row()
	var title: Label = add_label("最初のパーツを選ぶ", 30, COL_ACCENT, head)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button = add_button("タイトルへ戻る", back_to_title, head)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_label("フレーム・武器・スキルから1つずつ選ぶ。候補は全員同じで、ほかの人と同じものを選んでもよい。カードに合わせると詳しく見られる。", 16, COL_DIM)
	for kind: String in GameData.KINDS:
		add_label(UiText.KIND_LABELS[kind], 20, Look.KIND_COLORS.get(kind, COL_ACCENT))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var group := ButtonGroup.new()
		for p: Variant in session().draft_offer[kind]:
			var card: PartCard = PartCard.new()
			row.add_child(card)
			card.setup(main.data, p, group)
			card.toggled.connect(func(on: bool) -> void:
				if on:
					select(kind, p.uid))
			card.hovered.connect(_on_card_hovered)
			card.unhovered.connect(_on_card_unhovered)
			cards[p.uid] = card
	add_label(" ", 4)
	# 下の行：決定ボタンと、今選んでいる構成の欄
	var bottom := add_row()
	bottom.add_theme_constant_override("separation", 16)
	_confirm = add_button("決定", confirm, bottom)
	_confirm.custom_minimum_size = Vector2(160, 64)
	_confirm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_make_summary())
	_message = add_label("", 17, COL_BAD)
	# 吹き出しは並びの外に置き、スクロールの枠で切れないようにする
	tooltip = PartTooltip.new()
	add_child(tooltip)
	tooltip.setup(main.data)
	_update_confirm()


## 今選んでいる構成の欄（種類ごとに横に並べる。文字は折り返さない）
func _make_summary() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.075, 0.07)
	s.border_color = Look.UI_BORDER
	s.set_border_width_all(1)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)
	var head: Label = _plain_label(row, "現在の構成", 15, COL_DIM)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for kind: String in GameData.KINDS:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		var kind_col: Color = Look.KIND_COLORS.get(kind, COL_ACCENT)
		var name_label: Label = _plain_label(col, "", 19, COL_TEXT)
		var stat_label: Label = _plain_label(col, "", 13, kind_col.darkened(0.15))
		summary_labels[kind] = [name_label, stat_label]
	return panel


func _plain_label(parent: Control, text: String, size_px: int, col: Color) -> Label:
	var l: Label = add_label(text, size_px, col, parent)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


func select(kind: String, uid: int) -> void:
	picks[kind] = uid
	var card: Button = cards.get(uid)
	if card != null and not card.button_pressed:
		card.button_pressed = true  # 同じ組のほかのカードは外れる。toggled からまた select が呼ばれるが、同じ値を入れ直すだけ
	_update_confirm()


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


func _on_card_hovered(card: Button) -> void:
	tooltip.show_for(card.part, card)


func _on_card_unhovered(card: Button) -> void:
	if tooltip.part == card.part:
		tooltip.hide_tip()


func _update_confirm() -> void:
	if _confirm == null:
		return
	_confirm.disabled = picks.size() < GameData.KINDS.size()
	for kind: String in GameData.KINDS:
		var labels: Array = summary_labels[kind]
		var kind_name: String = UiText.KIND_LABELS[kind]
		if not picks.has(kind):
			labels[0].text = "%s：未選択" % kind_name
			labels[0].add_theme_color_override("font_color", COL_DIM)
			labels[1].text = " "
			continue
		var card: Button = cards[picks[kind]]
		labels[0].text = "%s：%s" % [kind_name, card.name_label.text]
		labels[0].add_theme_color_override("font_color", COL_TEXT)
		var stats := PackedStringArray([UiText.part_tagline(main.data, card.part)])
		var def: GameData.PartDef = main.data.get_part(card.part.def_id)
		for st: String in def.stat_names():
			stats.append(UiText.stat_text(st, card.part.get_stat(st)))
		labels[1].text = " / ".join(stats)
