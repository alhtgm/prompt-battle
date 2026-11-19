# 組み立てとプロンプト入力。手持ちからフレーム1つ・武器・スキルを選び、操縦士へのプロンプトを書く。
# 制限時間が過ぎると試合側が自動で締め切る（決めていなければ前の機体のまま）。
# 後半のラウンドでは「整備」ができる：付けていないパーツを解体してスクラップにし、使っているパーツを再抽選する
# （結果を見て「元のまま／新しい性能」を選ぶ）。通信対戦では結果が遅れて届くので、自分の状態を見張って表示を直す。
extends "res://view/screen_base.gd"

const GameData := preload("res://core/game_data.gd")
const FuseBar := preload("res://view/fuse_bar.gd")
const Loot := preload("res://core/loot.gd")

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
## 残り時間の導火線（ひとりで遊ぶときも、組み立てには制限時間がある）
var fuse: FuseBar
## 新しく配られたパーツの uid → 「NEW」の札
var new_tags: Dictionary = {}
var _prompt: TextEdit
var _counter: Label
var _timer: Label
var _brain: Label
var _slots: Label
var _message: Label
## 整備：スクラップの量の表示、パーツの uid → {"line", "box", "scrap", "reroll"}、再抽選の結果の板
var scrap_label: Label
var rows: Dictionary = {}
var reroll_overlay: Control = null
var _reroll_stats_box: GridContainer
var _reroll_title: Label
var _sig: String = ""


func build_ui() -> void:
	add_title("ラウンド %d：組み立てとプロンプト" % session().round_no)
	fuse = FuseBar.new()
	box.add_child(fuse)
	fuse.update(session().phase_time_left, 0.0)  # 最初のコマから満タンで出す
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
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	left.add_child(head)
	add_label("整備", 18, COL_ACCENT, head).autowrap_mode = TextServer.AUTOWRAP_OFF
	scrap_label = add_label("", 16, COL_TEXT, head)
	scrap_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	scrap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame_group := ButtonGroup.new()
	var new_uids: Dictionary = {}
	for np: Variant in p.new_parts:
		new_uids[np.uid] = true
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
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_boxes[part.uid] = b
			# 1行：左にチェック、右に新しく配られたパーツの「NEW」の札
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			left.add_child(line)
			line.add_child(b)
			# 札のない行にも同じ幅の場所を取っておき、行の右端をそろえる
			var tag: Label = _new_tag(line)
			if new_uids.has(part.uid):
				new_tags[part.uid] = tag
			else:
				tag.modulate.a = 0.0
			# 整備のボタン（使えるときだけ出す）：付けていなければ解体、使っていれば再抽選
			var sb: Button = _small_button(line, scrap.bind(part.uid))
			var rb: Button = _small_button(line, reroll.bind(part.uid))
			rows[part.uid] = {"line": line, "box": b, "scrap": sb, "reroll": rb}
	_slots = add_label("", 17, COL_DIM, left)

	# 右：残り時間、プロンプト、出撃、体力の一覧
	_timer = add_label("時間切れになると前の機体で出撃", 15, COL_DIM, right)
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
	_add_reroll_overlay()
	_sync_boxes()
	_update_info()
	_refresh_maintenance()


func _process(delta: float) -> void:
	if _timer != null and main.session != null:
		fuse.update(session().phase_time_left, delta)
		_brain.text = main.agents.brain_status_text()
		# 自分の状態（スクラップ・手持ち・再抽選の結果）が変わったら整備の表示を直す（通信対戦では遅れて届く）
		if _state_sig() != _sig:
			_refresh_maintenance()


# ---- 整備（解体と再抽選） ----

## 付けていないパーツを解体する。問題があれば理由を返す
func scrap(uid: int) -> String:
	var err: String = session().scrap_part(main.human_id, uid)
	_message.text = err
	_refresh_maintenance()
	return err


## 使っているパーツを再抽選する。結果は板で見せ、「元のまま／新しい性能」を選ぶ。問題があれば理由を返す
func reroll(uid: int) -> String:
	var err: String = session().reroll_part(main.human_id, uid)
	_message.text = err
	_refresh_maintenance()
	return err


## 再抽選の結果を選ぶ（take_new なら新しい性能にする）
func resolve_reroll(take_new: bool) -> void:
	session().resolve_reroll(main.human_id, take_new)
	_refresh_maintenance()


func _state_sig() -> String:
	var p: Variant = me()
	var parts := PackedStringArray()
	for part: Variant in p.hand:
		parts.append("%d:%s" % [part.uid, str(part.stats)])
	return "%d|%s|%s|%s" % [p.scrap, str(p.pending_reroll), ",".join(parts), str(session().scrap_unlocked())]


## 整備の表示を今の状態に合わせる（スクラップの量、行ごとのボタン、解体して消えた行、再抽選の結果の板）
func _refresh_maintenance() -> void:
	var p: Variant = me()
	var unlocked: bool = session().scrap_unlocked()
	var cost: int = int(main.data.rule("scrap.reroll_part_cost"))
	scrap_label.text = "スクラップ %d" % p.scrap
	if not unlocked:
		scrap_label.text += "（解体と再抽選は %d ラウンド目から）" % int(main.data.rule("scrap.unlock_round"))
	var equipped: Dictionary = {}
	if p.build != null:
		for part: Variant in [p.build.frame] + p.build.weapons + p.build.skills:
			equipped[part.uid] = true
	var waiting: bool = not p.pending_reroll.is_empty()
	for uid: int in rows.keys():
		var row: Dictionary = rows[uid]
		var part: Variant = p.find_part(uid)
		if part == null:  # 解体した
			(row["line"] as Control).queue_free()
			rows.erase(uid)
			_boxes.erase(uid)
			new_tags.erase(uid)
			continue
		var box: CheckBox = row["box"]
		box.text = UiText.part_line(main.data, part)
		var using: bool = box.button_pressed
		var sb: Button = row["scrap"]
		sb.visible = unlocked and not using and not equipped.has(uid)
		sb.text = "解体 +%d" % session().scrap_value(part)
		sb.disabled = waiting
		var rb: Button = row["reroll"]
		rb.visible = unlocked and using
		rb.text = "再抽選 %d" % cost
		rb.disabled = waiting or p.scrap < cost
	_show_reroll(p)
	_sig = _state_sig()


func _small_button(parent: Control, on_press: Callable) -> Button:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(72, 0)  # 解体と再抽選で幅をそろえ、行の右端をそろえる
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.visible = false
	b.pressed.connect(func() -> void: on_press.call())
	parent.add_child(b)
	return b


## 再抽選の結果の板（画面の真ん中。後ろは暗くして押せなくする）
func _add_reroll_overlay() -> void:
	reroll_overlay = Control.new()
	reroll_overlay.top_level = true
	reroll_overlay.z_index = 30
	reroll_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	reroll_overlay.visible = false
	add_child(reroll_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reroll_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reroll_overlay.add_child(center)
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.075, 0.07, 0.98)
	ps.border_color = Look.UI_ACCENT
	ps.set_border_width_all(2)
	ps.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	_reroll_title = add_label("", 22, COL_ACCENT, col)
	_reroll_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_reroll_stats_box = GridContainer.new()
	_reroll_stats_box.columns = 4
	_reroll_stats_box.add_theme_constant_override("h_separation", 18)
	_reroll_stats_box.add_theme_constant_override("v_separation", 6)
	col.add_child(_reroll_stats_box)
	add_label("スクラップは、どちらを選んでも戻らない", 14, COL_DIM, col).autowrap_mode = TextServer.AUTOWRAP_OFF
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 16)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btns)
	add_button("元のまま", resolve_reroll.bind(false), btns)
	add_button("新しい性能にする", resolve_reroll.bind(true), btns).custom_minimum_size = Vector2(200, 44)


## 再抽選の結果があれば板に出す（今の性能と新しい性能を並べ、良くなったら▲、悪くなったら▼）
func _show_reroll(p: Variant) -> void:
	if p.pending_reroll.is_empty():
		reroll_overlay.visible = false
		return
	var part: Variant = p.find_part(int(p.pending_reroll["uid"]))
	if part == null:
		reroll_overlay.visible = false
		return
	var def: GameData.PartDef = main.data.get_part(part.def_id)
	_reroll_title.text = "再抽選の結果：%s" % def.name
	for c: Node in _reroll_stats_box.get_children():
		_reroll_stats_box.remove_child(c)
		c.queue_free()
	for h: String in ["", "今", "", "新しい性能"]:
		_cell(h, 14, COL_DIM)
	var new_stats: Dictionary = p.pending_reroll["stats"]
	for stat: String in def.stat_names():
		var a: float = part.get_stat(stat)
		var b: float = float(new_stats.get(stat, a))
		var same: bool = absf(a - b) < 0.0001
		var better: bool = (b < a) if Loot.LOWER_IS_BETTER.has(stat) else (b > a)
		var mark: String = "＝" if same else ("▲" if better else "▼")
		var col: Color = COL_DIM if same else (Color(0.55, 0.85, 0.45) if better else COL_BAD)
		var label: String = UiText.STAT_LABELS.get(stat, stat)
		_cell(label, 17, COL_TEXT)
		_cell(UiText.stat_text(stat, a).trim_prefix(label).strip_edges(), 18, COL_TEXT)
		_cell(mark, 18, col)
		_cell(UiText.stat_text(stat, b).trim_prefix(label).strip_edges(), 18, col)
	reroll_overlay.position = Vector2.ZERO
	reroll_overlay.size = get_viewport_rect().size
	reroll_overlay.visible = true


func _cell(text: String, size_px: int, col: Color) -> void:
	add_label(text, size_px, col, _reroll_stats_box).autowrap_mode = TextServer.AUTOWRAP_OFF


## 「NEW」の札（パーツの行の右側）
func _new_tag(parent: Control) -> Label:
	var l: Label = add_label("NEW", 13, Color.BLACK, parent)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := StyleBoxFlat.new()
	st.bg_color = Look.UI_ACCENT
	st.content_margin_left = 8
	st.content_margin_right = 8
	l.add_theme_stylebox_override("normal", st)
	return l


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
	if reroll_overlay != null:
		_refresh_maintenance()  # チェックを変えると、解体と再抽選のどちらが出るかが変わる


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
		_message.text = err
		return err
	show_waiting(_message, "出撃準備OK。ほかのプレイヤーを待っています（直して押し直してもよい）")
	session().finish_build()
	return ""


func _sync_boxes() -> void:
	for uid: int in _boxes:
		var on: bool = uid == frame_uid or weapon_uids.has(uid) or skill_uids.has(uid)
		(_boxes[uid] as CheckBox).set_pressed_no_signal(on)
	if reroll_overlay != null:
		_refresh_maintenance()


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
