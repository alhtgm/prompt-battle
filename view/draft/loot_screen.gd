# ラウンド後の配布とパーク選び。配られた5つのパーツを見せ、パークを3つの候補から1つ選ぶ。
extends "res://view/screen_base.gd"

var _message: Label


func build_ui() -> void:
	add_title("ラウンド %d：パーツ配布とパーク" % session().round_no)
	add_label("配られたパーツ（手持ちに加わった）", 22, COL_ACCENT)
	for p: Variant in me().new_parts:
		add_label("・%s　%s" % [UiText.KIND_LABELS[p.kind], UiText.part_line(main.data, p)], 17)
	add_label(" ")
	add_label("パークを1つ選ぶ（試合の間ずっと効く。同じものを取ると積み重なる）", 22, COL_ACCENT)
	for perk_id: String in me().perk_choices:
		add_button(UiText.perk_line(main.data, perk_id), pick.bind(perk_id))
	_message = add_label("", 17, COL_BAD)
	if not me().perks.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for id: String in me().perks:
			names.append(main.data.get_perk(id).name)
		add_label("取ったパーク：" + "、".join(names), 16, COL_DIM)


## パークを選んで次のラウンドへ。問題があれば理由を返す
func pick(perk_id: String) -> String:
	var err: String = session().choose_perk(main.human_id, perk_id)
	if not err.is_empty():
		_message.text = err
		return err
	show_waiting(_message, "%s を選びました。ほかのプレイヤーを待っています" % main.data.get_perk(perk_id).name)
	session().finish_loot()
	return ""
