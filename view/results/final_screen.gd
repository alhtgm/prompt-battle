# 最終順位。全員の順位と、何ラウンドかかったかを出す。
extends "res://view/screen_base.gd"


func build_ui() -> void:
	var s: Variant = session()
	add_title("最終順位")
	add_label("%d ラウンドで決着" % s.round_no, 18, COL_DIM)
	var order: Array = s.players.duplicate()
	order.sort_custom(func(x: Variant, y: Variant) -> bool: return x.place < y.place)
	for p: Variant in order:
		var col: Color = COL_ACCENT if p.id == main.HUMAN_ID else COL_TEXT
		var when: String = "最後まで生存" if p.alive else "ラウンド %d で脱落" % p.eliminated_round
		add_label("%d位　%s　（%s）" % [p.place, p.name, when], 24 if p.place == 1 else 20, col)
	add_label(" ")
	add_button("タイトルへ", to_title)


func to_title() -> void:
	main.show_title()
