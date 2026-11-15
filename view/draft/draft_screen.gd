# 開始時のパーツ選び。全員に同じ候補（種類ごとに5つ）を見せ、種類ごとに1つ選ぶ。
extends "res://view/screen_base.gd"

const GameData := preload("res://core/game_data.gd")

## 種類 → 選んだ uid
var picks: Dictionary = {}
var _confirm: Button
var _message: Label


func build_ui() -> void:
	add_title("最初のパーツを選ぶ")
	add_label("フレーム・武器・スキルから1つずつ選ぶ。同じ候補が全員に見えていて、ほかの人と同じものを選んでもよい。", 17, COL_DIM)
	var row := add_row()
	_confirm = add_button("決定", confirm, row)
	_message = add_label("", 17, COL_BAD, row)
	for kind: String in GameData.KINDS:
		add_label(UiText.KIND_LABELS[kind], 22, COL_ACCENT)
		var group := ButtonGroup.new()
		for p: Variant in session().draft_offer[kind]:
			var b := CheckBox.new()
			b.text = UiText.part_line(main.data, p)
			b.button_group = group
			b.add_theme_font_size_override("font_size", 17)
			b.toggled.connect(func(on: bool) -> void:
				if on:
					select(kind, p.uid))
			box.add_child(b)
	_update_confirm()


func select(kind: String, uid: int) -> void:
	picks[kind] = uid
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


func _update_confirm() -> void:
	if _confirm != null:
		_confirm.disabled = picks.size() < GameData.KINDS.size()
