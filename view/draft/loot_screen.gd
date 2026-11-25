# ラウンド後の配布とパーク選び。配られたパーツを1枚ずつ画面の中央に大きく見せてから列へ送り（押すと飛ばせる。合わせると吹き出し）、
# パークを3枚のカードから1つ選び（1・2・3 キーでも選べる）、決定ボタンで確定する。パークのカードには、今の機体にどう効くかを出す。
# 通信対戦で制限時間があるときは、残り時間を導火線のバーで見せる。操作は MatchSession のメソッドだけを通す。
extends "res://view/screen_base.gd"

const GameData := preload("res://core/game_data.gd")
const PartCard := preload("res://view/draft/part_card.gd")
const PartTooltip := preload("res://view/draft/part_tooltip.gd")
const PerkCard := preload("res://view/draft/perk_card.gd")
const FuseBar := preload("res://view/fuse_bar.gd")

## 配られたパーツのカード
var part_cards: Array[Button] = []
## パークのカード（候補の順）
var perk_cards: Array[Button] = []
var tooltip: PartTooltip
## 選んでいるパーク（まだ確定していない。空なら未選択）
var selected_perk: String = ""
var confirm_button: Button
## 残り時間の導火線（制限時間がないときは隠す）
var fuse: FuseBar
var _message: Label
## 中央に大きく見せる演出（後ろの暗幕と、動いている大きいカード）。終わったら null
var showcase: Control = null
var _showcase_tween: Tween = null


func build_ui() -> void:
	add_title("ラウンド %d：パーツ配布とパーク" % session().round_no)
	_add_fuse()
	# 配られたパーツ・パークのカード・決定ボタンは、画面の横の真ん中にそろえる（見出しも合わせて真ん中に置く）
	add_label("配られたパーツ（手持ちに加わった。▲▼ は今付けているパーツとの比べ）", 20, COL_ACCENT) 		.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for p: Variant in me().new_parts:
		var card: PartCard = PartCard.new()
		row.add_child(card)
		card.setup(main.data, p, null, "NEW", _equipped_like(p))
		card.hovered.connect(_on_card_hovered)
		card.unhovered.connect(_on_card_unhovered)
		card.modulate.a = 0.0  # 中央での見せ方が終わってから列に出す
		part_cards.append(card)
	add_label(" ", 4)
	var head := add_row()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	add_label("パークを1つ選ぶ", 20, COL_ACCENT, head).autowrap_mode = TextServer.AUTOWRAP_OFF
	var hint: Label = add_label("試合の間ずっと効き、同じものは重なる", 15, COL_DIM, head)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF  # 横並びの中で折り返すと幅が0になり、縦書きのように伸びる
	var perk_row := HBoxContainer.new()
	perk_row.alignment = BoxContainer.ALIGNMENT_CENTER
	perk_row.add_theme_constant_override("separation", 16)
	box.add_child(perk_row)
	var n: int = 1
	var group := ButtonGroup.new()
	for perk_id: String in me().perk_choices:
		var pc: PerkCard = PerkCard.new()
		perk_row.add_child(pc)
		pc.setup(main.data, me(), perk_id, n, group)
		pc.toggled.connect(func(on: bool) -> void:
			if on:
				select_perk(perk_id))
		perk_cards.append(pc)
		n += 1
	confirm_button = add_button("決定", confirm)
	confirm_button.custom_minimum_size = Vector2(200, 50)
	confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm_button.disabled = true
	_message = add_label("", 17, COL_BAD)  # 決定ボタンの下に出す
	_message.autowrap_mode = TextServer.AUTOWRAP_OFF
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not me().perks.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for id: String in me().perks:
			names.append(main.data.get_perk(id).name)
		add_label("取ったパーク：" + "、".join(names), 15, COL_DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# パークのカードの番号キー（カードが3枚なら 1・2・3）
	var keys: Array[String] = []
	for i: int in perk_cards.size():
		keys.append(str(i + 1))
	if not keys.is_empty():
		add_key_guide([[keys, "パークを選ぶ"]])
	# 吹き出しは並びの外に置き、画面の並びに押されないようにする
	tooltip = PartTooltip.new()
	add_child(tooltip)
	tooltip.setup(main.data)
	if not part_cards.is_empty():
		_start_showcase.call_deferred()  # 列の並びが決まってから（行き先の場所が分かってから）始める


## パークを選ぶ（まだ確定しない）。選んだカードだけが金枠になる
func select_perk(perk_id: String) -> void:
	selected_perk = perk_id
	for pc: Button in perk_cards:
		if pc.perk_id == perk_id and not pc.button_pressed:
			pc.button_pressed = true  # 同じ組のほかのカードは外れる
	if confirm_button != null:
		confirm_button.disabled = false
		_message.text = ""


## 選んでいるパークで確定する（決定ボタン）。問題があれば理由を返す
func confirm() -> String:
	if selected_perk.is_empty():
		_message.text = "パークを1つ選んでください"
		return _message.text
	return pick(selected_perk)


## パークを確定して次のラウンドへ。問題があれば理由を返す
func pick(perk_id: String) -> String:
	var err: String = session().choose_perk(main.human_id, perk_id)
	if not err.is_empty():
		_message.text = err
		return err
	for pc: Button in perk_cards:
		pc.disabled = pc.perk_id != perk_id
	confirm_button.disabled = true
	show_waiting(_message, "%s を選びました。ほかのプレイヤーを待っています" % main.data.get_perk(perk_id).name)
	session().finish_loot()
	return ""


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if showcase != null:
		get_viewport().set_input_as_handled()
		finish_showcase()  # 演出中のキーは飛ばすだけ
		return
	var idx: int = k.keycode - KEY_1
	if idx >= 0 and idx < perk_cards.size() and not perk_cards[idx].disabled:
		get_viewport().set_input_as_handled()
		select_perk(perk_cards[idx].perk_id)  # キーは選ぶだけ。確定は決定ボタン


## 今付けているパーツのうち、比べる相手（フレームは今のフレーム、武器とスキルは同じ種類の1つ目）
func _equipped_like(p: Variant) -> Variant:
	var b: Variant = me().build
	if b == null:
		return null
	match p.kind:
		GameData.KIND_FRAME:
			return b.frame
		GameData.KIND_WEAPON:
			return b.weapons[0] if not b.weapons.is_empty() else null
		GameData.KIND_SKILL:
			return b.skills[0] if not b.skills.is_empty() else null
	return null


## 配られたパーツを1枚ずつ、画面の中央に大きく出してから、列の自分の場所へ縮めながら送る。
## 演出の間は後ろを暗くし、押す（キーでも）と残りを飛ばして全部を列に並べる
func _start_showcase() -> void:
	if not is_inside_tree():
		return
	showcase = Control.new()
	showcase.top_level = true  # 画面の並び（コンテナ）の外に重ねる
	showcase.z_index = 50
	showcase.position = Vector2.ZERO
	showcase.size = get_viewport_rect().size
	showcase.mouse_filter = Control.MOUSE_FILTER_STOP
	showcase.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			finish_showcase())
	add_child(showcase)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, Look.LOOT_DIM_ALPHA)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.modulate.a = 0.0
	showcase.add_child(dim)
	var center: Vector2 = showcase.size * 0.5 - PartCard.CARD_SIZE * 0.5
	var tw: Tween = create_tween()
	_showcase_tween = tw
	tw.tween_property(dim, "modulate:a", 1.0, Look.LOOT_POP_SEC)
	for card: Button in part_cards:
		var big: PartCard = PartCard.new()
		showcase.add_child(big)
		big.setup(main.data, card.part, null, "NEW", _equipped_like(card.part))
		big.mouse_filter = Control.MOUSE_FILTER_IGNORE
		big.focus_mode = Control.FOCUS_NONE
		big.size = PartCard.CARD_SIZE
		big.pivot_offset = PartCard.CARD_SIZE * 0.5
		big.position = center
		big.scale = Vector2.ZERO
		big.visible = false
		var target: Vector2 = card.global_position
		tw.tween_callback(func() -> void: big.visible = true)
		tw.tween_property(big, "scale", Vector2.ONE * Look.LOOT_SHOW_SCALE, Look.LOOT_POP_SEC) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(Look.LOOT_HOLD_SEC)
		tw.tween_property(big, "position", target, Look.LOOT_FLY_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(big, "scale", Vector2.ONE, Look.LOOT_FLY_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func() -> void:
			card.modulate.a = 1.0
			big.queue_free())
	tw.tween_property(dim, "modulate:a", 0.0, Look.LOOT_POP_SEC)
	tw.tween_callback(finish_showcase)


## 中央で見せる演出を終える（途中なら残りを飛ばす）。全部のカードを列に出す
func finish_showcase() -> void:
	if _showcase_tween != null:
		_showcase_tween.kill()
		_showcase_tween = null
	if showcase != null:
		showcase.queue_free()
		showcase = null
	for card: Button in part_cards:
		card.modulate.a = 1.0


## 残り時間の導火線（通信対戦で制限時間があるときだけ出す。ひとりで遊ぶときはパーク選びに制限時間がない）
func _add_fuse() -> void:
	fuse = FuseBar.new()
	box.add_child(fuse)
	fuse.visible = session().is_online() and session().phase_time_left > 0.0
	fuse.update(session().phase_time_left, 0.0)  # 最初のコマから満タンで出す


func _process(delta: float) -> void:
	if fuse != null and fuse.visible and main.session != null:
		fuse.update(session().phase_time_left, delta)


func _on_card_hovered(card: Button) -> void:
	tooltip.show_for(card.part, card)


func _on_card_unhovered(card: Button) -> void:
	if tooltip.part == card.part:
		tooltip.hide_tip()
