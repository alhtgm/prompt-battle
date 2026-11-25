# 組み立てとプロンプト入力。手持ちからフレーム1つ・武器・スキルを選び、操縦士へのプロンプトを書く。
# パーツは最初のパーツ選びと同じ◀▶の段で選ぶ。段はフレーム1つと、武器・スキルの枠1つずつ（「なし」も選べる）。
# 同じ種類のほかの枠で付けているパーツは、その段の候補に出さない。下の帯に、付けたパーツの詳しい性能を並べる。
# 制限時間が過ぎると試合側が自動で締め切る（決めていなければ前の機体のまま）。
extends "res://view/screen_base.gd"

const GameData := preload("res://core/game_data.gd")
const FuseBar := preload("res://view/fuse_bar.gd")
const PartCarousel := preload("res://view/draft/part_carousel.gd")
const PartDetail := preload("res://view/draft/part_detail.gd")

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
var _counter: Label
var _brain: Label
var _slots: Label
var _message: Label
## 付けたパーツの詳しい性能（下の帯に横に並べる。1つ分は PartDetail）
var _stats: GridContainer
## 一覧に出している組み合わせ（同じなら書き直さない）
var _stats_key: String = ""
## 取ったパークの札（同じものは1枚にまとめる）
var perk_tags: Array[Label] = []


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
	_fill_empty_slots()

	# 左：手持ちパーツを◀▶の段で選ぶ
	# 説明と、武器・スキルの枠の使い方（「武器 1 / 2」）を1行に並べる
	var guide := HBoxContainer.new()
	guide.add_theme_constant_override("separation", 12)
	left.add_child(guide)
	var how: Label = add_label("見出しで段を開き、◀▶（←→キー）で真ん中のものを付ける", 15, COL_DIM, guide)
	how.autowrap_mode = TextServer.AUTOWRAP_OFF
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for np: Variant in p.new_parts:
		new_tags[np.uid] = "NEW"
	_sections = VBoxContainer.new()
	_sections.add_theme_constant_override("separation", 2)
	left.add_child(_sections)
	_slots = add_label("", 15, COL_DIM, guide)
	_slots.autowrap_mode = TextServer.AUTOWRAP_OFF

	# 右：残り時間、プロンプト、出撃、体力の一覧
	# 1画面に収めるため、説明は短くまとめ、エラーは出撃ボタンの横、体力は2列に並べる
	_brain = add_label("", 15, COL_DIM, right)
	add_label("操縦士へのプロンプト", 22, COL_ACCENT, right)
	add_label("押すと例が入る。時間切れになると前の機体で出撃", 14, COL_DIM, right)
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
	_prompt.custom_minimum_size = Vector2(0, 80)
	_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.text = p.prompt
	_prompt.text_changed.connect(_update_info)
	right.add_child(_prompt)
	# 出撃ボタン・文字数・エラーを1行に並べる
	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 12)
	right.add_child(go)
	add_button("出撃", confirm, go)
	_counter = add_label("", 15, COL_DIM, go)
	_counter.autowrap_mode = TextServer.AUTOWRAP_OFF
	_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_message = add_label("", 15, COL_BAD, go)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var standings := GridContainer.new()
	standings.columns = 2
	standings.add_theme_constant_override("h_separation", 18)
	standings.add_theme_constant_override("v_separation", 0)
	right.add_child(standings)
	add_standings(standings, 14, true)
	_add_perks(right)
	# 下の帯：付けたパーツの詳しい性能を横に並べる（段の数が多くても1画面に収まるよう、左右の列の下に画面の幅いっぱいで置く）
	_stats = GridContainer.new()
	_stats.columns = Look.GARAGE_DETAIL_COLUMNS
	_stats.add_theme_constant_override("h_separation", 16)
	_stats.add_theme_constant_override("v_separation", 4)
	box.add_child(_stats)
	_build_sections()  # 段の動きはプロンプト欄ができてから（↑↓←→の取り合いを判断するため）
	_update_info()


func _process(delta: float) -> void:
	if _brain != null and main.session != null:
		fuse.update(session().phase_time_left, delta)
		_brain.text = main.agents.brain_status_text()


## 段を作り直す。フレーム1つと、武器・スキルは今のフレームの枠の数だけ段を並べる（枠が0なら段を出さない）。
## keep_frame ならフレームの段は残す
func _build_sections(keep_frame: bool = false) -> void:
	var frame_c: Variant = carousels.get("frame") if keep_frame else null
	for c: Node in _sections.get_children():
		if c != frame_c:
			_sections.remove_child(c)
			c.queue_free()
	carousels.clear()
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
		d.setup(main.data, part.kind, 14)
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
		_message.text = err
		return err
	show_waiting(_message, "出撃準備OK。ほかのプレイヤーを待っています（直して押し直してもよい）")
	session().finish_build()
	return ""


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
