# 開発モードの設定画面（開発用の書き出しだけ）。ステージとギミックのオン・オフ、両機の装備とプロンプト、
# HP無限・時間無制限・種を決めて、3Dのバトル画面で試合を見る。設定は main.dev_setup に持ち、バトルの「編集」で戻ってくる。
# 設定（辞書）を書き換えるだけで、試合は main.start_dev_battle が core/dev_session.gd で作る。
extends "res://view/screen_base.gd"

const GameData := preload("res://core/game_data.gd")
const DevSession := preload("res://core/dev_session.gd")
const StageMap := preload("res://view/stage_map.gd")

## ステージの見取り図の大きさ（px）
const STAGE_MAP_PX: float = 180.0
## 種の上限
const SEED_MAX: int = 999999
const SIDE_COLORS: Array[Color] = [Color(0.45, 0.7, 1.0), Color(1.0, 0.62, 0.3)]

## 編集している設定（main.dev_setup そのもの）
var setup: Dictionary = {}
var stage_select: OptionButton
var stage_map: Control
## ギミックの項目 → チェックボックス
var gimmick_boxes: Dictionary = {}
var invincible_boxes: Array[CheckBox] = []
var no_time_limit_box: CheckBox
var seed_box: SpinBox
## 機体ごと：フレームの選択、武器とスキルの型ID → チェックボックス、プロンプト、枠の数の見出し
var frame_selects: Array[OptionButton] = []
var weapon_boxes: Array[Dictionary] = [{}, {}]
var skill_boxes: Array[Dictionary] = [{}, {}]
var prompt_edits: Array[TextEdit] = []
var slot_labels: Array[Label] = []
var problem_label: Label
var start_button: Button
var _syncing: bool = false


func build_ui() -> void:
	setup = main.dev_setup
	add_title("開発モード：試合の設定")
	add_label("決めた設定で1対1のバトルを見る。バトル中の「編集」でここに戻り、「やり直し」で同じ設定・同じ種の試合を最初から見直せる。", 15, COL_DIM)
	var top := add_row()
	start_button = add_button("開始", _on_start, top)
	add_button("タイトルへ", main.show_title, top)
	problem_label = add_label("", 16, COL_BAD, top)
	problem_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	problem_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var row := add_row()
	row.add_theme_constant_override("separation", 32)
	var cols: Array[VBoxContainer] = []
	for ratio: float in [1.0, 1.0, 1.0]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_stretch_ratio = ratio
		col.add_theme_constant_override("separation", 6)
		row.add_child(col)
		cols.append(col)
	_build_stage_column(cols[0])
	for i: int in 2:
		_build_robot_column(cols[i + 1], i)
	_sync_controls()


# ---- 左の列：ステージ、ギミック、試合の設定 ----

func _build_stage_column(col: VBoxContainer) -> void:
	add_label("ステージ", 20, COL_ACCENT, col)
	stage_select = OptionButton.new()
	for st: Dictionary in main.data.stages:
		stage_select.add_item(str(st["name"]))
	stage_select.item_selected.connect(func(k: int) -> void: set_stage(str(main.data.stages[k]["id"])))
	col.add_child(stage_select)
	stage_map = StageMap.new()
	stage_map.custom_minimum_size = Vector2(STAGE_MAP_PX, STAGE_MAP_PX)
	stage_map.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(stage_map)

	add_label("ギミック（そのステージにあるものだけ選べる）", 18, COL_ACCENT, col)
	for key: String in GameData.GIMMICKS:
		var b := CheckBox.new()
		b.toggled.connect(func(on: bool) -> void: set_gimmick(key, on))
		col.add_child(b)
		gimmick_boxes[key] = b

	add_label("試合", 18, COL_ACCENT, col)
	for i: int in 2:
		var b := CheckBox.new()
		b.text = "%sのHPを無限にする" % DevSession.NAMES[i]
		b.toggled.connect(func(on: bool) -> void: set_invincible(i, on))
		col.add_child(b)
		invincible_boxes.append(b)
	no_time_limit_box = CheckBox.new()
	no_time_limit_box.text = "時間無制限（制限時間で決着しない）"
	no_time_limit_box.toggled.connect(func(on: bool) -> void: set_no_time_limit(on))
	col.add_child(no_time_limit_box)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	col.add_child(seed_row)
	var seed_label: Label = add_label("種", 16, COL_TEXT, seed_row)
	seed_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	seed_box = SpinBox.new()
	seed_box.min_value = 1
	seed_box.max_value = SEED_MAX
	seed_box.value_changed.connect(func(v: float) -> void: set_seed(int(v)))
	seed_row.add_child(seed_box)
	var dice := Button.new()
	dice.text = "ランダム"
	dice.pressed.connect(func() -> void: set_seed(Time.get_ticks_usec() % SEED_MAX + 1))
	seed_row.add_child(dice)



# ---- 中と右の列：両機の装備とプロンプト ----

func _build_robot_column(col: VBoxContainer, i: int) -> void:
	add_label(DevSession.NAMES[i], 22, SIDE_COLORS[i], col)
	add_label("フレーム", 17, COL_ACCENT, col)
	var fs := OptionButton.new()
	for d: GameData.PartDef in main.data.defs_of_kind(GameData.KIND_FRAME):
		fs.add_item("%s（武器%d・スキル%d）" % [d.name, d.weapon_slots, d.skill_slots])
	fs.item_selected.connect(_on_frame_selected.bind(i))
	col.add_child(fs)
	frame_selects.append(fs)
	slot_labels.append(add_label("", 15, COL_DIM, col))
	add_label("武器", 17, COL_ACCENT, col)
	for d: GameData.PartDef in main.data.defs_of_kind(GameData.KIND_WEAPON):
		weapon_boxes[i][d.id] = _part_box(col, d, func(on: bool) -> void: _toggle_part(i, "weapons", d.id, on))
	add_label("スキル", 17, COL_ACCENT, col)
	for d: GameData.PartDef in main.data.defs_of_kind(GameData.KIND_SKILL):
		skill_boxes[i][d.id] = _part_box(col, d, func(on: bool) -> void: _toggle_part(i, "skills", d.id, on))
	add_label("プロンプト", 17, COL_ACCENT, col)
	var pe := TextEdit.new()
	pe.custom_minimum_size = Vector2(0, 80)
	pe.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	pe.placeholder_text = "（なし）"
	pe.text_changed.connect(_on_prompt_changed.bind(i))
	col.add_child(pe)
	prompt_edits.append(pe)


func _on_frame_selected(k: int, i: int) -> void:
	set_frame(i, main.data.defs_of_kind(GameData.KIND_FRAME)[k].id)


func _on_prompt_changed(i: int) -> void:
	if not _syncing:
		setup["prompts"][i] = prompt_edits[i].text


func _part_box(col: VBoxContainer, d: GameData.PartDef, on_toggle: Callable) -> CheckBox:
	var b := CheckBox.new()
	b.text = "%s（%s）" % [d.name, UiText.BEHAVIOR_LABELS.get(d.behavior, d.behavior)]
	b.add_theme_font_size_override("font_size", 15)
	b.toggled.connect(on_toggle)
	col.add_child(b)
	return b


func _toggle_part(i: int, list_key: String, id: String, on: bool) -> void:
	if _syncing:
		return
	var ids: Array = setup["builds"][i][list_key]
	if on and not ids.has(id):
		ids.append(id)
	elif not on:
		ids.erase(id)
	_refresh()


# ---- 設定を変える（画面の操作もテストもここを通す） ----

## ステージを替える（外したギミックは戻す。作り替えたステージは捨てる）
func set_stage(id: String) -> void:
	setup["stage_id"] = id
	setup["stage"] = {}
	setup["gimmicks_off"] = []
	_sync_controls()


func set_gimmick(key: String, on: bool) -> void:
	if _syncing:
		return
	var off: Array = setup["gimmicks_off"]
	if on:
		off.erase(key)
	elif not off.has(key):
		off.append(key)
	_refresh()


func set_invincible(i: int, on: bool) -> void:
	if not _syncing:
		setup["invincible"][i] = on


func set_no_time_limit(on: bool) -> void:
	if not _syncing:
		setup["no_time_limit"] = on


func set_seed(v: int) -> void:
	if _syncing:
		return
	setup["seed"] = clampi(v, 1, SEED_MAX)
	_sync_controls()


func set_frame(i: int, def_id: String) -> void:
	if _syncing:
		return
	setup["builds"][i]["frame"] = def_id
	_refresh()


## 武器とスキルをまとめて決める（テスト用。画面ではチェックボックスで1つずつ変える）
func set_parts(i: int, weapons: Array, skills: Array) -> void:
	setup["builds"][i]["weapons"] = weapons.duplicate()
	setup["builds"][i]["skills"] = skills.duplicate()
	_sync_controls()


func set_prompt(i: int, text: String) -> void:
	setup["prompts"][i] = text
	_sync_controls()


## 始める。問題があれば理由を返す（画面にも出す）
func start() -> String:
	var problem: String = main.start_dev_battle()
	problem_label.text = problem
	return problem


func _on_start() -> void:
	start()


# ---- 表示を設定に合わせる ----

## 設定から、すべての操作の部品の状態を作り直す
func _sync_controls() -> void:
	_syncing = true
	stage_select.select(maxi(0, main.data.stages.find(main.data.get_stage(str(setup["stage_id"])))))
	for i: int in 2:
		invincible_boxes[i].set_pressed_no_signal(bool(setup["invincible"][i]))
		var b: Dictionary = setup["builds"][i]
		var frames: Array[GameData.PartDef] = main.data.defs_of_kind(GameData.KIND_FRAME)
		for k: int in frames.size():
			if frames[k].id == b["frame"]:
				frame_selects[i].select(k)
		for id: String in weapon_boxes[i]:
			weapon_boxes[i][id].set_pressed_no_signal((b["weapons"] as Array).has(id))
		for id: String in skill_boxes[i]:
			skill_boxes[i][id].set_pressed_no_signal((b["skills"] as Array).has(id))
		if prompt_edits[i].text != str(setup["prompts"][i]):
			prompt_edits[i].text = str(setup["prompts"][i])
	no_time_limit_box.set_pressed_no_signal(bool(setup["no_time_limit"]))
	seed_box.set_value_no_signal(int(setup["seed"]))
	_syncing = false
	_refresh()


## ステージの見取り図、ギミックの選べるかどうか、枠の数、設定の問題を合わせる
func _refresh() -> void:
	var base: Dictionary = setup["stage"] if not (setup["stage"] as Dictionary).is_empty() \
		else main.data.get_stage(str(setup["stage_id"]))
	_syncing = true
	for key: String in gimmick_boxes:
		var b: CheckBox = gimmick_boxes[key]
		var has: bool = GameData.stage_has_gimmick(base, key)
		b.disabled = not has
		b.text = str(GameData.GIMMICKS[key]) + ("" if has else "（このステージにはない）")
		b.set_pressed_no_signal(has and not (setup["gimmicks_off"] as Array).has(key))
	_syncing = false
	stage_map.set_stage(DevSession.make_stage(main.data, setup))
	for i: int in 2:
		var fdef: GameData.PartDef = main.data.get_part(str(setup["builds"][i]["frame"]))
		var b: Dictionary = setup["builds"][i]
		slot_labels[i].text = "武器 %d / %d　スキル %d / %d" % [(b["weapons"] as Array).size(), fdef.weapon_slots,
			(b["skills"] as Array).size(), fdef.skill_slots] if fdef != null else ""
	var problem: String = DevSession.check_setup(main.data, setup)
	problem_label.text = problem
	start_button.disabled = not problem.is_empty()
