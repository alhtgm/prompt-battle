# ラウンド結果。各バトルの勝ち負けと決着のつき方、受けたダメージ、脱落した人、体力の一覧を出す。
extends "res://view/screen_base.gd"

const MatchSession := preload("res://core/match_session.gd")


func build_ui() -> void:
	var s: Variant = session()
	var h: Dictionary = s.history[s.history.size() - 1]
	add_title("ラウンド %d の結果" % h["round"])
	_add_my_headline(h)
	for e: Dictionary in h["battles"]:
		var a: String = _name(int(e["a"]), -1)
		var b: String = _name(int(e["b"]), int(e["ghost_of"]))
		var w: int = int(e["winner"])
		var who: String = "引き分け" if w == -2 else "%s の勝ち" % (a if w == int(e["a"]) else b)
		var involved: bool = int(e["a"]) == main.human_id or int(e["b"]) == main.human_id
		add_label("%s vs %s → %s（%s、%.0f秒）" % [a, b, who, UiText.REASON_LABELS.get(e["reason"], ""), e["time"]],
			20, COL_ACCENT if involved else COL_TEXT)
	add_label(" ")
	if h["damage"].is_empty():
		add_label("ダメージを受けた人はいない", 18, COL_DIM)
	for id: Variant in h["damage"]:
		add_label("%s　体力 −%d" % [s.get_player(int(id)).name, int(h["damage"][id])], 18, COL_BAD)
	for id: int in h["eliminated"]:
		add_label("%s が脱落（%d位）" % [s.get_player(id).name, s.get_player(id).place], 20, COL_BAD)
	add_label(" ")
	add_standings()
	if not me().alive:
		add_label("あなたは脱落した。最後まで観戦できる。", 18, COL_DIM)
	if s.is_online():
		_countdown = add_label("", 18, COL_DIM)  # 通信対戦では、サーバーが少し待ってから次へ進める
	else:
		add_button("次へ", next)


var _countdown: Label = null


func _process(_delta: float) -> void:
	if _countdown != null and main.session != null:
		_countdown.text = "%d 秒後に次へ進みます" % ceili(session().phase_time_left)


## 自分の試合の結果を一番上に大きく出す（自分が戦っていなければ出さない）
func _add_my_headline(h: Dictionary) -> void:
	var id: int = main.human_id
	for e: Dictionary in h["battles"]:
		if int(e["a"]) != id and int(e["b"]) != id:
			continue
		var w: int = int(e["winner"])
		var dmg: int = int(h["damage"].get(id, 0))
		var text: String
		var col: Color
		if w == id:
			text = "あなたの勝ち！"
			col = COL_ACCENT
		elif w == -2:
			text = "引き分け"
			col = COL_TEXT
		else:
			text = "あなたの負け…　体力 −%d" % dmg
			col = COL_BAD
		if h["eliminated"].has(id):
			text += "　脱落（%d位）" % me().place
		add_label(text, 28, col)
		add_label(" ", 6)
		return


func next() -> void:
	session().finish_round_result()


func _name(id: int, ghost_of: int) -> String:
	if id == MatchSession.GHOST_ID:
		return "%s（記録）" % session().get_player(ghost_of).name
	return session().get_player(id).name
