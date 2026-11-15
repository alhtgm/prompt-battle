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

var frame_uid: int = -1
var weapon_uids: Array[int] = []
var skill_uids: Array[int] = []
var _boxes: Dictionary = {}
var _prompt: TextEdit
var _counter: Label
var _timer: Label
var _brain: Label
var _slots: Label
var _message: Label


func build_ui() -> void:
	add_title("ラウンド %d：組み立てとプロンプト" % session().round_no)
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
		add_label(UiText.KIND_LABELS[kind], 22, COL_ACCENT, left)
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
			left.add_child(b)
	_slots = add_label("", 17, COL_DIM, left)

	# 右：残り時間、プロンプト、出撃、体力の一覧
	_timer = add_label("", 20, COL_ACCENT, right)
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
	_prompt.custom_minimum_size = Vector2(0, 110)
	_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.text = p.prompt
	_prompt.text_changed.connect(_update_info)
	right.add_child(_prompt)
	_counter = add_label("", 15, COL_DIM, right)
	_message = add_label("", 17, COL_BAD, right)
	add_button("出撃", confirm, right)
	add_label(" ", 10, COL_DIM, right)
	add_standings(right)
	_sync_boxes()
	_update_info()


func _process(_delta: float) -> void:
	if _timer != null and main.session != null:
		_timer.text = "残り %d 秒（時間切れになると前の機体で出撃）" % ceili(maxf(0.0, session().phase_time_left))
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
	var err: String = session().submit_build(main.HUMAN_ID, frame_uid, weapon_uids, skill_uids, _prompt.text)
	if not err.is_empty():
		_message.text = err
		return err
	session().finish_build()
	return ""


func _sync_boxes() -> void:
	for uid: int in _boxes:
		var on: bool = uid == frame_uid or weapon_uids.has(uid) or skill_uids.has(uid)
		(_boxes[uid] as CheckBox).set_pressed_no_signal(on)


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
	_slots.text = "武器 %d / %d　スキル %d / %d" % [weapon_uids.size(), max_w, skill_uids.size(), max_s]
	_slots.add_theme_color_override("font_color",
		COL_BAD if weapon_uids.size() > max_w or skill_uids.size() > max_s else COL_DIM)
	var limit: int = p.prompt_max_chars(data)
	var n: int = _prompt.text.length()
	_counter.text = "%d / %d 文字" % [n, limit]
	_counter.add_theme_color_override("font_color", COL_BAD if n > limit else COL_DIM)
