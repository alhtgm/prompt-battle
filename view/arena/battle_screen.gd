# バトル中の画面。3Dのアリーナで自分の試合を映し、上に両機体のHP・今の方針・一言、下に実況とほかの試合の様子を重ねる。
# 自分が脱落していれば、残っている試合を観戦する。状態は読むだけで、操作は MatchSession のメソッドだけを通す。
extends Control

const UiText := preload("res://view/ui_text.gd")
const ArenaView := preload("res://view/arena/arena_view.gd")
const Look := preload("res://view/look.gd")
const PostOverlay := preload("res://view/post_overlay.gd")

const LOG_LINES: int = 6
const COL_TEXT := Color(0.9, 0.87, 0.8)
const COL_DIM := Color(0.62, 0.6, 0.55)
const SIDE_COLORS: Array[Color] = [Color(0.45, 0.78, 1.0), Color(1.0, 0.62, 0.25)]

## view/main.gd（画面の切り替え役）
var main: Node
var arena: Node3D
var watched_battle: Variant = null
var header: Label
var side_names: Array[Label] = []
var side_intents: Array[Label] = []
var side_says: Array[Label] = []
var side_bars: Array[ProgressBar] = []
var side_prompts: Array[Label] = []
var log_label: Label
var others_label: Label
## 機体の頭上に重ねる名前と一言
var bubbles: Array[Label] = []


func build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	watched_battle = _pick_battle()

	# 3Dのアリーナ（自分だけの3D空間に、低い解像度で描いて拡大する）
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = Look.PIXEL_SHRINK
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	container.add_child(vp)
	arena = ArenaView.new()
	vp.add_child(arena)
	arena.setup(main.data)
	if watched_battle != null:
		arena.bind(watched_battle.sim)
	# アリーナだけに強い画面効果（ざらつき・色の段数・周辺の暗さ）をかける。文字の板はこの上に出す
	var post := PostOverlay.new()
	add_child(post)
	post.setup(Look.ARENA_POST)
	for i: int in 2:
		var b: Label = _label(self, "", 17, SIDE_COLORS[i])
		b.add_theme_constant_override("outline_size", 6)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bubbles.append(b)

	# 上：見出しと操作
	var top: VBoxContainer = _panel(Control.PRESET_CENTER_TOP, Vector2(0, 12), false)
	header = _label(top, "", 22, COL_TEXT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	top.add_child(row)
	row.visible = not main.session.is_online()  # 通信対戦では、速さはサーバーが決める
	for spec: Array in [["1倍", set_speed.bind(1.0)], ["4倍", set_speed.bind(4.0)], ["最後まで飛ばす", skip]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(110, 36)
		b.pressed.connect(spec[1])
		row.add_child(b)

	# 左上・右上：両機体
	for i: int in 2:
		var preset: int = Control.PRESET_TOP_LEFT if i == 0 else Control.PRESET_TOP_RIGHT
		var p: VBoxContainer = _panel(preset, Vector2(16, 12), true)
		side_names.append(_label(p, "", 22, SIDE_COLORS[i]))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(300, 14)
		bar.show_percentage = false
		p.add_child(bar)
		side_bars.append(bar)
		side_intents.append(_label(p, "", 18, COL_TEXT))
		side_says.append(_label(p, "", 20, Color(1.0, 0.92, 0.6)))
		var pl: Label = _label(p, "", 14, COL_DIM)
		pl.custom_minimum_size = Vector2(300, 0)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side_prompts.append(pl)

	# 左下：実況、右下：ほかの試合
	var bottom_left: VBoxContainer = _panel(Control.PRESET_BOTTOM_LEFT, Vector2(16, 12), true)
	_label(bottom_left, "実況", 15, COL_DIM)
	log_label = _label(bottom_left, "", 15, COL_TEXT)
	var bottom_right: VBoxContainer = _panel(Control.PRESET_BOTTOM_RIGHT, Vector2(16, 12), true)
	_label(bottom_right, "ほかの試合", 15, COL_DIM)
	others_label = _label(bottom_right, "", 15, COL_DIM)
	_fill_prompts()
	refresh()


## プロンプトの見せ方（企画メモ「観戦」）：生き残っている間は自分のものだけ、脱落したら両方見える
func _fill_prompts() -> void:
	if watched_battle == null:
		return
	var me_alive: bool = main.session.get_player(main.human_id).alive
	var ids: Array = [watched_battle.a, watched_battle.b]
	for i: int in 2:
		var text: String = str(watched_battle.prompts[i])
		if me_alive and ids[i] != main.human_id:
			side_prompts[i].text = "プロンプト：（相手のものは見えない）"
		else:
			side_prompts[i].text = "プロンプト：%s" % (text if not text.is_empty() else "（なし）")


func _process(_delta: float) -> void:
	if main != null and main.session != null and main.session.phase == "battle":
		refresh()
		_place_bubbles()


## 頭上の文字を、3Dの機体の位置に合わせて置く（低い解像度で描いているので、その倍率を掛ける）
func _place_bubbles() -> void:
	if watched_battle == null or arena.robot_views.is_empty():
		return
	for i: int in 2:
		var view: Node3D = arena.robot_views[i]
		var b: Label = bubbles[i]
		var p: Vector3 = view.label_position()
		b.visible = not arena.camera.is_position_behind(p) and view.visible
		b.text = view.label.text
		b.reset_size()
		var at: Vector2 = arena.camera.unproject_position(p) * float(Look.PIXEL_SHRINK)
		b.position = at - Vector2(b.size.x * 0.5, b.size.y)


func set_speed(x: float) -> void:
	main.battle_speed = x


## 3試合とも決着まで一気に進める
func skip() -> void:
	main.session.run_battles_to_end()


## 見る試合：自分の試合、自分がいなければ最初の試合
func _pick_battle() -> Variant:
	var s: Variant = main.session
	var b: Variant = s.battle_of(main.human_id)
	return b if b != null else (s.battles[0] if not s.battles.is_empty() else null)


## 状態を読んで文字を合わせる（3Dは arena が自分で合わせる）
func refresh() -> void:
	if watched_battle == null:
		return
	var s: Variant = main.session
	var sim: Variant = watched_battle.sim
	var names: Array = [sim.robots[0].name, sim.robots[1].name]
	var spectating: String = "（観戦中）" if not s.get_player(main.human_id).alive else ""
	header.text = "ラウンド %d%s　%.1f 秒 / 残り %.1f 秒（%s倍）\n%s" % [
		s.round_no, spectating, sim.now(), sim.time_left(), main.battle_speed, main.agents.brain_status_text()]
	if sim.over:
		var w: int = int(sim.result["winner"])
		header.text += "\n決着：%s（%s）・ほかの試合を待っています" % [
			"引き分け" if w < 0 else "%s の勝ち" % names[w], UiText.REASON_LABELS.get(sim.result["reason"], "")]
	for i: int in 2:
		var r: Variant = sim.robots[i]
		var state: String = "穴に落ちた" if r.fell else ("動けない！" if r.stun > 0.0 else UiText.INTENT_LABELS.get(r.intent, r.intent))
		side_names[i].text = "%s　HP %d / %d" % [r.name, roundi(r.hp), roundi(r.max_hp)]
		side_bars[i].max_value = r.max_hp
		side_bars[i].value = r.hp
		side_intents[i].text = "方針：%s" % state
		side_says[i].text = "「%s」" % r.say if not r.say.is_empty() else ""
	var lines: PackedStringArray = PackedStringArray()
	for k: int in range(sim.log.size() - 1, -1, -1):
		var line: String = UiText.event_line(sim.log[k], names)
		if not line.is_empty():
			lines.insert(0, line)
			if lines.size() >= LOG_LINES:
				break
	log_label.text = "\n".join(lines)
	var others: PackedStringArray = PackedStringArray()
	for other: Variant in s.battles:
		if other == watched_battle:
			continue
		var o: Variant = other.sim
		var status: String = "決着" if o.over else "%.0f秒" % o.now()
		others.append("%s vs %s：%s　HP %d%% / %d%%" % [o.robots[0].name, o.robots[1].name, status,
			roundi(o.robots[0].hp_ratio() * 100.0), roundi(o.robots[1].hp_ratio() * 100.0)])
	others_label.text = "\n".join(others)


## 画面の角や上に置く、半透明の板つきの縦並び
func _panel(preset: int, margin: Vector2, backed: bool) -> VBoxContainer:
	var holder: Control
	if backed:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Look.UI_PANEL
		style.border_color = Look.UI_BORDER
		style.set_border_width_all(1)
		style.set_content_margin_all(10)
		panel.add_theme_stylebox_override("panel", style)
		holder = panel
	else:
		holder = MarginContainer.new()
	add_child(holder)
	holder.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	# 角からの余白
	var grow_left: bool = preset == Control.PRESET_TOP_RIGHT or preset == Control.PRESET_BOTTOM_RIGHT
	var grow_up: bool = preset == Control.PRESET_BOTTOM_LEFT or preset == Control.PRESET_BOTTOM_RIGHT
	holder.grow_horizontal = Control.GROW_DIRECTION_BEGIN if grow_left else (
		Control.GROW_DIRECTION_BOTH if preset == Control.PRESET_CENTER_TOP else Control.GROW_DIRECTION_END)
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN if grow_up else Control.GROW_DIRECTION_END
	holder.position += Vector2(-margin.x if grow_left else margin.x, -margin.y if grow_up else margin.y)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	holder.add_child(box)
	return box


func _label(parent: Control, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l
