# 組み立てとプロンプト入力。手持ちからフレーム1つ・武器・スキルを選び、操縦士へのプロンプトを書く。
# 制限時間が過ぎると試合側が自動で締め切る（決めていなければ前の機体のまま）。
extends "res://view/screen_base.gd"

const GameData := preload("res://core/game_data.gd")

## 押すとプロンプト欄に入る例（[ボタンの名前, プロンプト]）
const PROMPT_EXAMPLES: Array = [
	["突撃", "とにかく突撃して殴れ"],
	["穴落とし", "相手が穴の近くに来たら穴に押し込め。それ以外は突撃しろ"],
	["射撃", "距離をとって撃ちまくれ。弾が切れたら突っ込め"],
	["慎重", "慎重に戦え。HPが減ったら修理に行け"],
	["回り込み", "相手の後ろに回り込んで攻めろ"],
]
## 残り時間がこの秒数以下になったら、時間の表示を赤くする
const TIME_WARN_SEC: float = 10.0

var frame_uid: int = -1
var weapon_uids: Array[int] = []
var skill_uids: Array[int] = []
var _boxes: Dictionary = {}
## チェックボックスの uid → パーツの種類
var _box_kinds: Dictionary = {}
## 種類 → 見出し（「武器　1 / 3」のように枠の使い方を出す）
var _kind_heads: Dictionary = {}
var _prompt: TextEdit
var _counter: Label
var _timer: Label
var _brain: Label
## 出撃ボタンの横：今の選び方の問題（なければ空）
var _problem: Label
## 出撃ボタンの下：送ったかどうか（通信対戦で、ほかの人を待っている間に出す）
var _status: Label
var _go: Button
var _time_warned: bool = false
## 最後に送った機体とプロンプト（まだ送っていなければ空）。送ったあとに直したかを見分ける
var _submitted: String = ""


func build_ui() -> void:
	# 見出しの行：左にラウンド、右に残り時間
	var head := HBoxContainer.new()
	box.add_child(head)
	var title: Label = add_label("ラウンド %d：組み立てとプロンプト" % session().round_no, 30, COL_ACCENT, head)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer = add_label("", 24, COL_ACCENT, head)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer.autowrap_mode = TextServer.AUTOWRAP_OFF
	_timer.tooltip_text = "時間切れになると前の機体で出撃"
	var cols: Array[VBoxContainer] = add_columns()
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]

	# 前の機体があれば、それを選んだ状態から始める。なければフレームと武器を1つずつ選んでおく
	var p: Variant = me()
	if p.build != null:
		frame_uid = p.build.frame.uid
		for w: Variant in p.build.weapons:
			weapon_uids.append(w.uid)
		for s: Variant in p.build.skills:
			skill_uids.append(s.uid)
	else:
		for part: Variant in p.hand:
			if part.kind == GameData.KIND_FRAME and frame_uid < 0:
				frame_uid = part.uid
			elif part.kind == GameData.KIND_WEAPON and weapon_uids.is_empty():
				weapon_uids.append(part.uid)

	# 左：手持ちパーツ
	add_label("チェックを入れて機体を組む。フレームは1つ、武器とスキルはフレームの枠の数まで。", 15, COL_DIM, left)
	var frame_group := ButtonGroup.new()
	for kind: String in GameData.KINDS:
		_kind_heads[kind] = add_label(UiText.KIND_LABELS[kind], 22, COL_ACCENT, left)
		for part: Variant in p.hand:
			if part.kind != kind:
				continue
			var b := CheckBox.new()
			b.text = UiText.part_line(main.data, part)
			b.add_theme_font_size_override("font_size", 16)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if kind == GameData.KIND_FRAME:
				b.button_group = frame_group
			b.toggled.connect(_on_toggled.bind(kind, part.uid))
			_boxes[part.uid] = b
			_box_kinds[part.uid] = kind
			left.add_child(b)

	# 右：操縦士、プロンプト、出撃、体力の一覧
	_brain = add_label("", 15, COL_DIM, right)
	add_label("操縦士へのプロンプト", 22, COL_ACCENT, right)
	add_label("操縦士はこれを読んで、試合中に自分で動き方を決める。押すと例が入る：", 15, COL_DIM, right)
	var examples := HFlowContainer.new()
	examples.add_theme_constant_override("h_separation", 6)
	examples.add_theme_constant_override("v_separation", 6)
	right.add_child(examples)
	for ex: Array in PROMPT_EXAMPLES:
		var b := Button.new()
		b.text = ex[0]
		b.tooltip_text = ex[1]
		b.pressed.connect(set_prompt.bind(ex[1]))
		examples.add_child(b)
	_prompt = TextEdit.new()
	_prompt.custom_minimum_size = Vector2(0, 100)
	_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.placeholder_text = "例：HPが30%以下なら修理に行け。それ以外は突撃しろ"
	_prompt.text = p.prompt
	_prompt.text_changed.connect(_update_info)
	right.add_child(_prompt)
	_counter = add_label("", 15, COL_DIM, right)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var go_row := HBoxContainer.new()
	go_row.add_theme_constant_override("separation", 12)
	right.add_child(go_row)
	_go = add_button("出撃", confirm, go_row)
	_go.custom_minimum_size = Vector2(200, 48)
	_go.add_theme_font_size_override("font_size", 22)
	_problem = add_label("", 16, COL_BAD, go_row)
	_problem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_problem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status = add_label("", 15, COL_DIM, right)
	add_label("みんなの体力", 17, COL_DIM, right)
	add_standings(right, 15)
	_sync_boxes()
	_update_info()


func _process(_delta: float) -> void:
	if _timer != null and main.session != null:
		var left: float = maxf(0.0, session().phase_time_left)
		_timer.text = "残り %d 秒" % ceili(left)
		# 色は残り時間が境目をまたいだときだけ変える（毎フレーム設定し直さない）
		var warn: bool = left <= TIME_WARN_SEC
		if warn != _time_warned:
			_time_warned = warn
			_timer.add_theme_color_override("font_color", COL_BAD if warn else COL_ACCENT)
		_brain.text = main.agents.brain_status_text()


func _on_toggled(on: bool, kind: String, uid: int) -> void:
	match kind:
		GameData.KIND_FRAME:
			if on:
				frame_uid = uid
		GameData.KIND_WEAPON:
			if on and not weapon_uids.has(uid):
				weapon_uids.append(uid)
			elif not on:
				weapon_uids.erase(uid)
		GameData.KIND_SKILL:
			if on and not skill_uids.has(uid):
				skill_uids.append(uid)
			elif not on:
				skill_uids.erase(uid)
	_update_info()


## 選んだ状態をまとめて決める（テストや「前の機体に戻す」用）
func set_selection(frame: int, weapons: Array, skills: Array) -> void:
	frame_uid = frame
	weapon_uids.assign(weapons)
	skill_uids.assign(skills)
	_sync_boxes()
	_update_info()


func set_prompt(text: String) -> void:
	_prompt.text = text
	_update_info()


## 機体とプロンプトを試合に伝えて出撃する。問題があれば理由を返す
func confirm() -> String:
	var err: String = session().submit_build(main.human_id, frame_uid, weapon_uids, skill_uids, _prompt.text)
	if not err.is_empty():
		_problem.text = err
		return err
	_submitted = _selection_key()
	_update_status()
	session().finish_build()
	return ""


## 今の選び方とプロンプトをまとめた文字列（送ったあとに直したかを見分けるため）
func _selection_key() -> String:
	return JSON.stringify([frame_uid, weapon_uids, skill_uids, _prompt.text])


## 送ったかどうかを出す。通信対戦では送ったあともこの画面に残るので、直してまだ送っていないことも伝える
func _update_status() -> void:
	if _submitted.is_empty():
		_status.text = ""
	elif _submitted == _selection_key():
		show_waiting(_status, "出撃準備OK。ほかのプレイヤーを待っています（直して押し直してもよい）")
	elif session().is_online():
		_status.text = "直した内容はまだ送っていない。もう一度「出撃」を押すと送り直す"
		_status.add_theme_color_override("font_color", COL_ACCENT)


func _sync_boxes() -> void:
	for uid: int in _boxes:
		var on: bool = uid == frame_uid or weapon_uids.has(uid) or skill_uids.has(uid)
		(_boxes[uid] as CheckBox).set_pressed_no_signal(on)


## 今の選び方で出撃できるかを試合に尋ねる（状態は変えない）。問題がなければ空文字
func current_problem() -> String:
	var err: String = session().check_build(main.human_id, frame_uid, weapon_uids, skill_uids, _prompt.text)
	return err + "。チェックを外してください" if err.contains("多すぎる") else err


func _update_info() -> void:
	var p: Variant = me()
	var data: GameData = main.data
	var max_w: int = p.extra_weapon_slots(data)
	var max_s: int = p.extra_skill_slots(data)
	var frame: Variant = p.find_part(frame_uid)
	if frame != null:
		var fdef: GameData.PartDef = data.get_part(frame.def_id)
		max_w += fdef.weapon_slots
		max_s += fdef.skill_slots
	# 見出しに枠の使い方を出し、あふれていれば赤くする
	var limits: Dictionary = {
		GameData.KIND_WEAPON: [weapon_uids.size(), max_w],
		GameData.KIND_SKILL: [skill_uids.size(), max_s],
	}
	for kind: String in limits:
		var used: int = limits[kind][0]
		var cap: int = limits[kind][1]
		var head: Label = _kind_heads[kind]
		head.text = "%s　%d / %d" % [UiText.KIND_LABELS[kind], used, cap]
		if cap == 0:
			head.text += "（このフレームには付けられない）"
		head.add_theme_color_override("font_color", COL_BAD if used > cap else COL_ACCENT)
	# 枠がいっぱいの種類は、まだ選んでいないものを押せなくする（外すことはいつでもできる）
	for uid: int in _boxes:
		var kind: String = _box_kinds[uid]
		if not limits.has(kind):
			continue
		var cb: CheckBox = _boxes[uid]
		cb.disabled = not cb.button_pressed and int(limits[kind][0]) >= int(limits[kind][1])
	var limit: int = p.prompt_max_chars(data)
	var n: int = _prompt.text.length()
	_counter.text = "%d / %d 文字" % [n, limit]
	_counter.add_theme_color_override("font_color", COL_BAD if n > limit else COL_DIM)
	var problem: String = current_problem()
	_go.disabled = not problem.is_empty()
	_problem.text = problem
	_update_status()
