# 組み立てとプロンプト入力。手持ちからフレーム1つ・武器・スキルを選び、操縦士へのプロンプトを書く。
# パーツは最初のパーツ選びと同じ◀▶の段で選ぶ。段はフレーム1つと、武器・スキルの枠1つずつ（「なし」も選べる）。
# 同じ種類のほかの枠で付けているパーツは、その段の候補に出さない。下の帯に、付けたパーツの詳しい性能を並べる。
# 制限時間が過ぎると試合側が自動で締め切る（決めていなければ前の機体のまま）。
# 後半のラウンドでは「整備」ができる：整備の板を開き、付けていないパーツを解体してスクラップにし、使っているパーツを再抽選する
# （結果を見て「元のまま／新しい性能」を選ぶ）。通信対戦では結果が遅れて届くので、自分の状態を見張って表示を直す。
extends "res://view/screen_base.gd"

const GameData := preload("res://core/game_data.gd")
const FuseBar := preload("res://view/fuse_bar.gd")
const Loot := preload("res://core/loot.gd")
const PartCarousel := preload("res://view/draft/part_carousel.gd")
const PartDetail := preload("res://view/draft/part_detail.gd")
const SortieButton := preload("res://view/garage/sortie_button.gd")

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
## 段の名前（"frame" / "weapon:0" / "skill:1" など）→ 段。武器とスキルは枠の数だけ並ぶ
var carousels: Dictionary = {}
## 今開いている段の名前
var active_key: String = ""
## 種類 → 段ごとの uid（段の順。「なし」は -1）。ほかの枠の候補から外すものを知るため
var _rows: Dictionary = {}
## 段を並べたときの枠の数（x が武器、y がスキル）
var _shown_slots := Vector2i(-1, -1)
## 残り時間の導火線（ひとりで遊ぶときも、組み立てには制限時間がある）
var fuse: FuseBar
## 新しく配られたパーツの uid → 「NEW」（段のカードの札）
var new_tags: Dictionary = {}
## 段を並べる場所（フレームを替えて枠の数が変わったら並べ直す）
var _sections: VBoxContainer
var _prompt: TextEdit
## カーソルの点滅の時刻（打つたびに 0 に戻す）
var _blink_t: float = 0.0
var _counter: Label
var _brain: Label
var _slots: Label
## 出撃ボタンの横：今の選び方の問題（なければ空）
var _problem: Label
## 送ったかどうか（通信対戦で、ほかの人を待っている間に出す）。出撃ボタンの横の _problem と同じ札で、問題がないときだけ出す
var _status: Label
var _go: Button
## 最後に送った機体とプロンプト（まだ送っていなければ空）。送ったあとに直したかを見分ける
var _submitted: String = ""
## 整備：スクラップの量の表示、整備の操作の問題、整備の板を開くボタン、
## パーツの uid → {"line", "name", "using", "scrap", "reroll"}、整備の板、再抽選の結果の板
var scrap_label: Label
var maintenance_message: Label
var maintenance_button: Button
var rows: Dictionary = {}
var maintenance_overlay: Control = null
var _maintenance_list: VBoxContainer
var reroll_overlay: Control = null
var _reroll_stats_box: GridContainer
var _reroll_title: Label
var _sig: String = ""
## 段を並べたときの手持ち（uid と性能。解体や再抽選で変わったら段を作り直す）
var _hand_sig: String = ""
## 付けたパーツの詳しい性能（下の帯に横に並べる。1つ分は PartDetail）
var _stats: GridContainer
## 一覧に出している組み合わせ（同じなら書き直さない）
var _stats_key: String = ""
## 取ったパークの札（同じものは1枚にまとめる）
var perk_tags: Array[Label] = []


func build_ui() -> void:
	# 見出しの行の右の空きに操縦士の状態を出す（右の列を短くして、下の帯まで1画面に収めるため）
	var title: Label = add_title("ラウンド %d：組み立てとプロンプト" % session().round_no)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	box.remove_child(title)
	box.add_child(top)
	top.add_child(title)
	_brain = add_label("", 15, COL_DIM, top)
	_brain.autowrap_mode = TextServer.AUTOWRAP_OFF
	_brain.clip_text = true
	_brain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brain.size_flags_vertical = Control.SIZE_SHRINK_END
	_brain.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	_fill_empty_slots()

	# 左：手持ちパーツを◀▶の段で選ぶ
	# 説明と、武器・スキルの枠の使い方（「武器 1 / 2」）を1行に並べる
	var guide := HBoxContainer.new()
	guide.add_theme_constant_override("separation", 12)
	left.add_child(guide)
	for np: Variant in p.new_parts:
		new_tags[np.uid] = "NEW"
	# 整備：スクラップの量と、整備の板を開くボタン（使えるラウンドだけ押せる）
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	left.add_child(head)
	add_label("整備", 18, COL_ACCENT, head).autowrap_mode = TextServer.AUTOWRAP_OFF
	scrap_label = add_label("", 16, COL_TEXT, head)
	scrap_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	scrap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	maintenance_button = Button.new()
	maintenance_button.text = "整備を開く（解体・再抽選）"
	maintenance_button.add_theme_font_size_override("font_size", 14)
	maintenance_button.focus_mode = Control.FOCUS_NONE
	maintenance_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	maintenance_button.pressed.connect(open_maintenance)
	head.add_child(maintenance_button)
	_sections = VBoxContainer.new()
	_sections.add_theme_constant_override("separation", 2)
	left.add_child(_sections)
	_slots = add_label("", 15, COL_DIM, guide)
	_slots.autowrap_mode = TextServer.AUTOWRAP_OFF
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 右：プロンプト、出撃、体力の一覧
	# 1画面に収めるため、説明は見出しの横に短く、エラーは出撃ボタンの横、体力は2列に並べる
	var prompt_head := HBoxContainer.new()
	prompt_head.add_theme_constant_override("separation", 16)
	right.add_child(prompt_head)
	add_label("操縦士へのプロンプト", 22, COL_ACCENT, prompt_head).autowrap_mode = TextServer.AUTOWRAP_OFF
	var hint: Label = add_label("時間切れになると前の機体で出撃", 14, COL_DIM, prompt_head)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	right.add_child(_make_terminal(p.prompt))
	# 出撃ボタン・文字数・エラーを1行に並べる
	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 12)
	right.add_child(go)
	_go = SortieButton.new()
	_go.text = "出撃"
	_go.pressed.connect(confirm)
	go.add_child(_go)
	_counter = add_label("", 15, COL_DIM, go)
	_counter.autowrap_mode = TextServer.AUTOWRAP_OFF
	_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_problem = add_label("", 15, COL_BAD, go)
	_problem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_problem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status = _problem  # 送ったかどうかも同じ場所に出す（1画面に収めるため、行を増やさない。問題があるときは問題を優先）
	add_standings(right, 14, true, 2)  # 1画面に収めるため2人ずつ並べる
	_add_perks(right)
	# 下の帯：付けたパーツの詳しい性能を横に並べる（段の数が多くても1画面に収まるよう、左右の列の下に画面の幅いっぱいで置く）
	_stats = GridContainer.new()
	_stats.columns = Look.GARAGE_DETAIL_COLUMNS
	_stats.add_theme_constant_override("h_separation", 16)
	_stats.add_theme_constant_override("v_separation", 4)
	box.add_child(_stats)
	_add_maintenance_overlay()
	_add_reroll_overlay()
	_build_sections()  # 段の動きはプロンプト欄ができてから（↑↓←→の取り合いを判断するため）
	_update_info()
	_refresh_maintenance()
	# キーはプロンプト欄の外にいるときだけ効く
	add_key_guide([[["←", "→"], "付ける"], [["↑", "↓"], "段"]])


func _process(delta: float) -> void:
	_blink_t += delta
	if _prompt != null:
		_prompt.queue_redraw()  # カーソルを点滅させる
	if _brain != null and main.session != null:
		fuse.update(session().phase_time_left, delta)
		_brain.text = main.agents.brain_status_text()
		# 自分の状態（スクラップ・手持ち・再抽選の結果）が変わったら整備の表示を直す（通信対戦では遅れて届く）
		if _state_sig() != _sig:
			_refresh_maintenance()


## 段を作り直す。フレーム1つと、武器・スキルは今のフレームの枠の数だけ段を並べる（枠が0なら段を出さない）。
## keep_frame ならフレームの段は残す
func _build_sections(keep_frame: bool = false) -> void:
	var frame_c: Variant = carousels.get("frame") if keep_frame else null
	for c: Node in _sections.get_children():
		if c != frame_c:
			_sections.remove_child(c)
			c.queue_free()
	carousels.clear()
	_hand_sig = _hand_state()
	var slots: Vector2i = _max_slots()
	_shown_slots = slots
	if frame_c != null:
		carousels["frame"] = frame_c
	else:
		_add_section("frame", GameData.KIND_FRAME, "", false, frame_uid)
	for spec: Array in [[GameData.KIND_WEAPON, weapon_uids, slots.x], [GameData.KIND_SKILL, skill_uids, slots.y]]:
		var kind: String = spec[0]
		var chosen: Array[int] = spec[1]
		var limit: int = spec[2]
		var row: Array[int] = []
		for i: int in limit:
			row.append(chosen[i] if i < chosen.size() else -1)
		_rows[kind] = row
		for i: int in row.size():
			_add_section("%s:%d" % [kind, i], kind, "%s%d" % [UiText.KIND_LABELS[kind], i + 1], true, row[i])
		_rows[kind] = _row_uids(kind)  # 手持ちにないものは段に出ないので、段に出ている値にそろえる
	var key: String = active_key if carousels.has(active_key) else "frame"
	active_key = ""
	activate(key, false)


## 段を1つ足す。uid のパーツを真ん中に置いておく（-1 なら「なし」）。
## 同じ種類のほかの枠で付けているパーツは候補に出さない。at が 0 以上なら、その位置に置く（段の作り直し）
func _add_section(key: String, kind: String, title: String, allow_none: bool, uid: int, at: int = -1) -> void:
	var taken: Array[int] = []
	if _rows.has(kind):
		var index: int = int(key.get_slice(":", 1))
		for i: int in _rows[kind].size():
			if i != index and _rows[kind][i] >= 0:
				taken.append(_rows[kind][i])
	var offer: Array = []
	for part: Variant in me().hand:
		if part.kind == kind and not taken.has(part.uid):
			offer.append(part)
	var c: PartCarousel = PartCarousel.new()
	c.card_size = Look.GARAGE_CARD_SIZE
	c.header_font = Look.GARAGE_HEADER_FONT
	_sections.add_child(c)
	if at >= 0:
		_sections.move_child(c, at)
	c.setup(main.data, kind, offer, title, allow_none, new_tags)
	c.select_uid(uid)
	c.picked.connect(func(_k: String, picked_uid: int) -> void: _on_picked(key, picked_uid))
	c.activated.connect(func(_k: String) -> void: activate(key))
	carousels[key] = c


## key の段だけを開き、ほかは見出しの文字だけにする（animate なら少しずつ開閉する）
func activate(key: String, animate: bool = true) -> void:
	if not carousels.has(key) or (key == active_key and animate):
		return
	active_key = key
	for k: String in carousels:
		carousels[k].set_expanded(k == key, animate)


## 開いている段のカードを送る（+1 で右、-1 で左）
func move(dir: int) -> void:
	if carousels.has(active_key):
		carousels[active_key].step(dir)


## 開く段を上下に替える（+1 で下、-1 で上。端で止まる）
func switch_section(dir: int) -> void:
	var keys: Array = carousels.keys()
	var i: int = keys.find(active_key)
	activate(keys[clampi(i + dir, 0, keys.size() - 1)])


## 段で選んだものを機体に反映する。同じ種類のほかの枠の段は、候補（今選んだものを外す）を作り直す
func _on_picked(key: String, uid: int) -> void:
	if key == "frame":
		frame_uid = uid
		if _max_slots() != _shown_slots:
			_fit_to_slots()  # 枠が減ったら、はみ出した武器・スキルを外す
			_fill_empty_slots()  # 枠が増えたら、手持ちの使っていないパーツで埋める
			_build_sections(true)  # 枠の数が変わったら、武器とスキルの段を並べ直す
		_update_info()
		return
	var kind: String = key.get_slice(":", 0)
	var index: int = int(key.get_slice(":", 1))
	_rows[kind][index] = uid
	for i: int in _rows[kind].size():
		if i != index:
			_rebuild_section(kind, i)
	var chosen: Array[int] = []
	for v: int in _rows[kind]:
		if v >= 0:
			chosen.append(v)
	if kind == GameData.KIND_WEAPON:
		weapon_uids = chosen
	else:
		skill_uids = chosen
	_update_info()


## kind の i 番目の段を、同じ位置に作り直す（候補を今の選び方に合わせる。開き具合はそのまま）
func _rebuild_section(kind: String, i: int) -> void:
	var key: String = "%s:%d" % [kind, i]
	var old: PartCarousel = carousels[key]
	var at: int = old.get_index()
	var title: String = old.title
	_sections.remove_child(old)
	old.queue_free()
	_add_section(key, kind, title, true, _rows[kind][i], at)
	carousels[key].set_expanded(key == active_key, false)


## kind の段に今出ている uid（段の順。「なし」は -1）
func _row_uids(kind: String) -> Array[int]:
	var row: Array[int] = []
	var i: int = 0
	while carousels.has("%s:%d" % [kind, i]):
		row.append(carousels["%s:%d" % [kind, i]].current_uid())
		i += 1
	return row


## 今のフレームの枠より多く付けている武器・スキルを、後ろから外す（フレームを替えて枠が減ったとき）
func _fit_to_slots() -> void:
	var slots: Vector2i = _max_slots()
	if weapon_uids.size() > slots.x:
		weapon_uids.resize(slots.x)
	if skill_uids.size() > slots.y:
		skill_uids.resize(slots.y)


## 空いている武器とスキルの枠を、手持ちのまだ付けていないパーツで（手持ちの順に）埋める。最初から「なし」にしないため
func _fill_empty_slots() -> void:
	var slots: Vector2i = _max_slots()
	for spec: Array in [[GameData.KIND_WEAPON, weapon_uids, slots.x], [GameData.KIND_SKILL, skill_uids, slots.y]]:
		var chosen: Array[int] = spec[1]
		for part: Variant in me().hand:
			if chosen.size() >= int(spec[2]):
				break
			if part.kind == spec[0] and not chosen.has(part.uid):
				chosen.append(part.uid)


## 付けたパーツの詳しい性能を並べ直す（フレーム、武器、スキルの順）。2段になるときは説明の文と決まった値を省いて1画面に収める
func _refresh_stats() -> void:
	if _stats == null:
		return
	var key: String = "%d|%s|%s" % [frame_uid, str(weapon_uids), str(skill_uids)]
	if key == _stats_key:
		return
	_stats_key = key
	for c: Node in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	var p: Variant = me()
	var uids: Array[int] = [frame_uid]
	uids.append_array(weapon_uids)
	uids.append_array(skill_uids)
	var parts: Array = []
	for uid: int in uids:
		var part: Variant = p.find_part(uid)
		if part != null:
			parts.append(part)
	var two_rows: bool = parts.size() > Look.GARAGE_DETAIL_COLUMNS
	for part: Variant in parts:
		var d: PartDetail = PartDetail.new()
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats.add_child(d)
		d.setup(main.data, part.kind, 14, true)
		d.show_part(part)
		if two_rows:
			d.desc_label.visible = false
			d.fixed_label.visible = false


## 取ったパーク。同じものはまとめて「×2」と出し、札に合わせると効き方の説明が出る
func _add_perks(parent: Control) -> void:
	var p: Variant = me()
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	parent.add_child(flow)
	perk_tags.clear()
	var head: Label = add_label("取ったパーク：" if not p.perks.is_empty() else "取ったパーク：まだない", 14, COL_ACCENT, flow)
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	var counts: Dictionary = {}
	for id: String in p.perks:
		counts[id] = int(counts.get(id, 0)) + 1
	for id: String in counts:
		var perk: GameData.PerkDef = main.data.get_perk(id)
		var n: int = counts[id]
		var tag: Label = add_label(perk.name + ("×%d" % n if n > 1 else ""), 13, COL_TEXT, flow)
		tag.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.tooltip_text = perk.description
		tag.mouse_filter = Control.MOUSE_FILTER_STOP  # 合わせると説明が出るように
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.16, 0.14, 0.11)
		st.border_color = Look.UI_BORDER
		st.set_border_width_all(1)
		st.content_margin_left = 6
		st.content_margin_right = 6
		tag.add_theme_stylebox_override("normal", st)
		perk_tags.append(tag)


## 今のフレームで付けられる武器とスキルの数（x が武器、y がスキル）
func _max_slots() -> Vector2i:
	var p: Variant = me()
	var data: GameData = main.data
	var slots := Vector2i(p.extra_weapon_slots(data), p.extra_skill_slots(data))
	var frame: Variant = p.find_part(frame_uid)
	if frame != null:
		var fdef: GameData.PartDef = data.get_part(frame.def_id)
		slots += Vector2i(fdef.weapon_slots, fdef.skill_slots)
	return slots


## ←→でカードを送り、↑↓で開く段を替える（プロンプトを書いている間は文字の操作を優先する）
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (_prompt != null and _prompt.has_focus()):
		return
	if (maintenance_overlay != null and maintenance_overlay.visible) or (reroll_overlay != null and reroll_overlay.visible):
		return  # 板を開いている間は、後ろの段を動かさない
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


## プロンプト欄を端末のコマンド入力風に作る：黒い下地、先頭に「操縦士> 」、点滅する四角いカーソル
func _make_terminal(text: String) -> PanelContainer:
	var term := PanelContainer.new()
	term.custom_minimum_size = Vector2(0, 80)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Look.TERM_BG
	bg.border_color = Look.TERM_BORDER
	bg.set_border_width_all(1)
	bg.set_content_margin_all(8)
	term.add_theme_stylebox_override("panel", bg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	term.add_child(row)
	var head := Label.new()
	head.text = "操縦士> "
	head.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_theme_font_size_override("font_size", Look.TERM_FONT)
	head.add_theme_color_override("font_color", Look.TERM_PROMPT)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	var head_box := MarginContainer.new()
	head_box.add_theme_constant_override("margin_top", Look.TERM_HEAD_DROP)
	head_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head_box.mouse_filter = Control.MOUSE_FILTER_PASS
	head_box.add_child(head)
	row.add_child(head_box)
	_prompt = TextEdit.new()
	_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prompt.add_theme_font_size_override("font_size", Look.TERM_FONT)
	_prompt.add_theme_color_override("font_color", Look.TERM_TEXT)
	_prompt.add_theme_color_override("caret_color", Color(0, 0, 0, 0))  # カーソルは _draw_caret() で描く
	# 欄の下地と枠は外側（term）が持つので、入力そのものは透明にする。行の頭を「操縦士> 」の文字にそろえる
	var none := StyleBoxEmpty.new()
	for state: String in ["normal", "focus", "read_only"]:
		_prompt.add_theme_stylebox_override(state, none)
	_prompt.text = text
	_prompt.text_changed.connect(_update_info)
	# 書いている間は枠を明るくする
	_prompt.focus_entered.connect(func() -> void: bg.border_color = Look.TERM_BORDER_FOCUS)
	_prompt.focus_exited.connect(func() -> void: bg.border_color = Look.TERM_BORDER)
	_prompt.draw.connect(_draw_caret)
	# 打っている間や動かした直後はカーソルを点けたままにする
	_prompt.caret_changed.connect(func() -> void: _blink_t = 0.0)
	row.add_child(_prompt)
	# 「操縦士> 」や余白を押しても書き始められるようにする
	term.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_prompt.grab_focus())
	return term


## 四角いカーソルを点滅させる。選んでいるときは入力の位置、選んでいないときは文の末尾に出す（端末の待ち受けのように）。
## TextEdit 自身のカーソルは透明にしてあり、どちらの場合もここで描く（ウィンドウが前にないときも消えない）
func _draw_caret() -> void:
	if fmod(_blink_t, Look.TERM_BLINK_SEC * 2.0) >= Look.TERM_BLINK_SEC:
		return
	var line: int = _prompt.get_line_count() - 1
	var col: int = _prompt.get_line(line).length()
	if _prompt.has_focus():
		line = _prompt.get_caret_line()
		col = _prompt.get_caret_column()
	var font: Font = _prompt.get_theme_font("font")
	var fs: int = _prompt.get_theme_font_size("font_size")
	var w: float = font.get_char_size("M".unicode_at(0), fs).x
	var h: float = font.get_height(fs)
	# カーソルは直前の字の右隣に置く（行の頭なら、その行の最初の字の左端）
	var x: float = 0.0
	var top: float = -1.0
	if col > 0:
		# get_rect_at_line_column(line, col) は、col の直前（col - 1 番目）の字の場所を返す
		var r: Rect2i = _prompt.get_rect_at_line_column(line, col)
		if r.position.x >= 0:
			x = r.end.x
			top = r.position.y + (r.size.y - h) * 0.5
	if top < 0.0:
		var p: Vector2i = _prompt.get_pos_at_line_column(line, 0)
		top = maxf(0.0, p.y - h) if p.x >= 0 else 0.0
	_prompt.draw_rect(Rect2(x, top, w, h), Look.TERM_CARET)


## 選んだ状態をまとめて決める（テストや「前の機体に戻す」用）
func set_selection(frame: int, weapons: Array, skills: Array) -> void:
	frame_uid = frame
	weapon_uids.assign(weapons)
	skill_uids.assign(skills)
	_build_sections()
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
	if main.has_method("begin_sortie"):
		main.begin_sortie()  # シャッターを閉じ始める（1人用では、次の finish_build ですぐバトルの段階に移る）
	session().finish_build()
	return ""


## 待っている間にシャッターのキャンセルで出撃を取り消した（選んだ機体とプロンプトはそのまま）
func on_sortie_cancelled() -> void:
	_submitted = ""
	_update_status()


## 今の選び方とプロンプトをまとめた文字列（送ったあとに直したかを見分けるため）
func _selection_key() -> String:
	return JSON.stringify([frame_uid, weapon_uids, skill_uids, _prompt.text])


## 送ったかどうかを出す。通信対戦では送ったあともこの画面に残るので、直してまだ送っていないことも伝える
## （_status は _problem と同じ札。問題があるときは問題の文を残す）
func _update_status() -> void:
	_status.add_theme_color_override("font_color", COL_BAD)
	if _go.disabled:
		return
	_status.text = ""
	if _submitted.is_empty():
		return
	elif _submitted == _selection_key():
		show_waiting(_status, "出撃準備OK。ほかのプレイヤーを待っています")
	elif session().is_online():
		_status.text = "直した内容はまだ送っていない。もう一度「出撃」を押すと送り直す"
		_status.add_theme_color_override("font_color", COL_ACCENT)


## 今の選び方で出撃できるかを試合に尋ねる（状態は変えない）。問題がなければ空文字
func current_problem() -> String:
	var err: String = session().check_build(main.human_id, frame_uid, weapon_uids, skill_uids, _prompt.text)
	return err + "。段で「なし」を選んでください" if err.contains("多すぎる") else err


# ---- 整備（解体と再抽選） ----

## 整備の板を開く（使えるラウンドだけ）
func open_maintenance() -> void:
	if not session().scrap_unlocked():
		return
	_refresh_maintenance()
	maintenance_overlay.position = Vector2.ZERO
	maintenance_overlay.size = get_viewport_rect().size
	maintenance_overlay.visible = true


func close_maintenance() -> void:
	maintenance_overlay.visible = false


## 付けていないパーツを解体する。問題があれば理由を返す
func scrap(uid: int) -> String:
	var err: String = session().scrap_part(main.human_id, uid)
	maintenance_message.text = err
	_refresh_maintenance()
	return err


## 使っているパーツを再抽選する。結果は板で見せ、「元のまま／新しい性能」を選ぶ。問題があれば理由を返す
func reroll(uid: int) -> String:
	var err: String = session().reroll_part(main.human_id, uid)
	maintenance_message.text = err
	_refresh_maintenance()
	return err


## 再抽選の結果を選ぶ（take_new なら新しい性能にする）
func resolve_reroll(take_new: bool) -> void:
	session().resolve_reroll(main.human_id, take_new)
	_refresh_maintenance()


func _state_sig() -> String:
	var p: Variant = me()
	return "%d|%s|%s|%s" % [p.scrap, str(p.pending_reroll), _hand_state(), str(session().scrap_unlocked())]


## 手持ちの uid と性能をまとめた文字列（解体や再抽選で変わったかを見分ける）
func _hand_state() -> String:
	var parts := PackedStringArray()
	for part: Variant in me().hand:
		parts.append("%d:%s" % [part.uid, str(part.stats)])
	return ",".join(parts)


## 整備の表示を今の状態に合わせる（スクラップの量、行ごとのボタン、解体して消えた行、再抽選の結果の板）。
## 手持ちが変わっていたら、段と下の性能の帯も作り直す
func _refresh_maintenance() -> void:
	if reroll_overlay == null:
		return
	var p: Variant = me()
	var unlocked: bool = session().scrap_unlocked()
	var cost: int = int(main.data.rule("scrap.reroll_part_cost"))
	scrap_label.text = "スクラップ %d" % p.scrap
	if not unlocked:
		scrap_label.text += "（解体と再抽選は %d ラウンド目から）" % int(main.data.rule("scrap.unlock_round"))
	maintenance_button.visible = unlocked
	if not unlocked:
		maintenance_overlay.visible = false
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
			new_tags.erase(uid)
			continue
		(row["name"] as Label).text = UiText.part_line(main.data, part)
		var using: bool = uid == frame_uid or weapon_uids.has(uid) or skill_uids.has(uid)
		(row["using"] as Label).modulate.a = 1.0 if using else 0.0
		var sb: Button = row["scrap"]
		sb.visible = unlocked and not using and not equipped.has(uid)
		sb.text = "解体 +%d" % session().scrap_value(part)
		sb.disabled = waiting
		var rb: Button = row["reroll"]
		rb.visible = unlocked and using
		rb.text = "再抽選 %d" % cost
		rb.disabled = waiting or p.scrap < cost
	if _hand_state() != _hand_sig and _sections != null:
		_build_sections()  # 段の候補とカードの性能を今の手持ちに合わせる
		_stats_key = ""
		_refresh_stats()
	_show_reroll(p)
	_sig = _state_sig()


## 整備の板（画面の真ん中。手持ちのパーツを1行ずつ並べ、付けていなければ解体、使っていれば再抽選のボタンを出す）
func _add_maintenance_overlay() -> void:
	maintenance_overlay = Control.new()
	maintenance_overlay.top_level = true
	maintenance_overlay.z_index = 20
	maintenance_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	maintenance_overlay.visible = false
	add_child(maintenance_overlay)
	var col: VBoxContainer = _overlay_panel(maintenance_overlay)
	add_label("整備", 22, COL_ACCENT, col).autowrap_mode = TextServer.AUTOWRAP_OFF
	add_label("付けていないパーツは解体してスクラップに、使っているパーツはスクラップで再抽選できる", 14, COL_DIM, col) \
		.autowrap_mode = TextServer.AUTOWRAP_OFF
	maintenance_message = add_label("", 15, COL_BAD, col)
	maintenance_message.autowrap_mode = TextServer.AUTOWRAP_OFF
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_maintenance_list = VBoxContainer.new()
	_maintenance_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_maintenance_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_maintenance_list)
	var p: Variant = me()
	for kind: String in GameData.KINDS:
		add_label(UiText.KIND_LABELS[kind], 17, COL_ACCENT, _maintenance_list)
		for part: Variant in p.hand:
			if part.kind != kind:
				continue
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			_maintenance_list.add_child(line)
			var name_label: Label = add_label(UiText.part_line(main.data, part), 15, COL_TEXT, line)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			# 札のない行にも同じ幅の場所を取っておき、行の右端をそろえる
			var tag: Label = _tag(line, "NEW", Look.UI_ACCENT, Color.BLACK)
			tag.modulate.a = 1.0 if new_tags.has(part.uid) else 0.0
			var using: Label = _tag(line, "使用中", Look.UI_BORDER, COL_TEXT)
			var sb: Button = _small_button(line, scrap.bind(part.uid))
			var rb: Button = _small_button(line, reroll.bind(part.uid))
			rows[part.uid] = {"line": line, "name": name_label, "using": using, "scrap": sb, "reroll": rb}
	var close: Button = add_button("閉じる", close_maintenance, col)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


## 板の下地（後ろを暗くし、真ん中に枠付きの板を置く）。板の中の縦の並びを返す
func _overlay_panel(overlay: Control) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
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
	return col


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


## 行の右側の小さい札（「NEW」「使用中」）
func _tag(parent: Control, text: String, bg: Color, fg: Color) -> Label:
	var l: Label = add_label(text, 13, fg, parent)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.content_margin_left = 8
	st.content_margin_right = 8
	l.add_theme_stylebox_override("normal", st)
	return l


## 再抽選の結果の板（整備の板より手前。後ろは暗くして押せなくする）
func _add_reroll_overlay() -> void:
	reroll_overlay = Control.new()
	reroll_overlay.top_level = true
	reroll_overlay.z_index = 30
	reroll_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	reroll_overlay.visible = false
	add_child(reroll_overlay)
	var col: VBoxContainer = _overlay_panel(reroll_overlay)
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
		_reroll_cell(h, 14, COL_DIM)
	var new_stats: Dictionary = p.pending_reroll["stats"]
	for stat: String in def.stat_names():
		var a: float = part.get_stat(stat)
		var b: float = float(new_stats.get(stat, a))
		var same: bool = absf(a - b) < 0.0001
		var better: bool = (b < a) if Loot.LOWER_IS_BETTER.has(stat) else (b > a)
		var mark: String = "＝" if same else ("▲" if better else "▼")
		var col: Color = COL_DIM if same else (Color(0.55, 0.85, 0.45) if better else COL_BAD)
		var label: String = UiText.STAT_LABELS.get(stat, stat)
		_reroll_cell(label, 17, COL_TEXT)
		_reroll_cell(UiText.stat_text(stat, a).trim_prefix(label).strip_edges(), 18, COL_TEXT)
		_reroll_cell(mark, 18, col)
		_reroll_cell(UiText.stat_text(stat, b).trim_prefix(label).strip_edges(), 18, col)
	reroll_overlay.position = Vector2.ZERO
	reroll_overlay.size = get_viewport_rect().size
	reroll_overlay.visible = true


func _reroll_cell(text: String, size_px: int, col: Color) -> void:
	add_label(text, size_px, col, _reroll_stats_box).autowrap_mode = TextServer.AUTOWRAP_OFF


func _update_info() -> void:
	var p: Variant = me()
	var data: GameData = main.data
	var slots: Vector2i = _max_slots()
	var max_w: int = slots.x
	var max_s: int = slots.y
	_slots.text = "武器 %d / %d　スキル %d / %d" % [weapon_uids.size(), max_w, skill_uids.size(), max_s]
	_slots.add_theme_color_override("font_color",
		COL_BAD if weapon_uids.size() > max_w or skill_uids.size() > max_s else COL_DIM)
	var limit: int = p.prompt_max_chars(data)
	var n: int = _prompt.text.length()
	_counter.text = "%d / %d 文字" % [n, limit]
	_refresh_stats()
	_counter.add_theme_color_override("font_color", COL_BAD if n > limit else COL_DIM)
	var problem: String = current_problem()
	_go.disabled = not problem.is_empty()
	_problem.text = problem
	_update_status()
	_refresh_maintenance()  # 付け替えると、解体と再抽選のどちらが出るかが変わる
