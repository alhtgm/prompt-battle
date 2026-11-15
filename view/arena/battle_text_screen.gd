# バトル中の画面（段階4の仮。文字だけ）。自分の試合のHP・方針・一言・実況と、ほかの2試合の様子を出す。
# 自分が脱落していれば、残っている試合を観戦する。3Dのアリーナは段階5で作る。
extends "res://view/screen_base.gd"

const LOG_LINES: int = 10

var _header: Label
var _sides: Array[Label] = []
var _bars: Array[ProgressBar] = []
var _log: Label
var _others: Label


func build_ui() -> void:
	_header = add_title("")
	var row := add_row()
	add_button("1倍", set_speed.bind(1.0), row)
	add_button("4倍", set_speed.bind(4.0), row)
	add_button("最後まで飛ばす", skip, row)
	for i: int in 2:
		_sides.append(add_label("", 20))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(420, 18)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bar.show_percentage = false
		box.add_child(bar)
		_bars.append(bar)
	add_label("実況", 18, COL_DIM)
	_log = add_label("", 16)
	add_label("ほかの試合", 18, COL_DIM)
	_others = add_label("", 16, COL_DIM)
	_refresh()


func _process(_delta: float) -> void:
	if main.session != null and session().phase == "battle":
		_refresh()


func set_speed(x: float) -> void:
	main.battle_speed = x


## 3試合とも決着まで一気に進める
func skip() -> void:
	session().run_battles_to_end()


## 見る試合：自分の試合、自分がいなければ最初の試合
func watched() -> Variant:
	var b: Variant = session().battle_of(main.HUMAN_ID)
	return b if b != null else (session().battles[0] if not session().battles.is_empty() else null)


func _refresh() -> void:
	var bt: Variant = watched()
	if bt == null:
		return
	var sim: Variant = bt.sim
	var names: Array = [sim.robots[0].name, sim.robots[1].name]
	var spectating: String = "" if me().alive else "（観戦中）"
	_header.text = "ラウンド %d：%s vs %s%s　%.1f 秒 / 残り %.1f 秒（%s倍）" % [
		session().round_no, names[0], names[1], spectating, sim.now(), sim.time_left(), main.battle_speed]
	for i: int in 2:
		var r: Variant = sim.robots[i]
		var state: String = "穴に落ちた" if r.fell else ("動けない" if r.stun > 0.0 else UiText.INTENT_LABELS.get(r.intent, r.intent))
		_sides[i].text = "%s　HP %d / %d　方針：%s　「%s」" % [r.name, roundi(r.hp), roundi(r.max_hp), state, r.say]
		_bars[i].max_value = r.max_hp
		_bars[i].value = r.hp
	var lines: PackedStringArray = PackedStringArray()
	for k: int in range(sim.log.size() - 1, -1, -1):
		var line: String = UiText.event_line(sim.log[k], names)
		if not line.is_empty():
			lines.insert(0, line)
			if lines.size() >= LOG_LINES:
				break
	_log.text = "\n".join(lines)
	var others: PackedStringArray = PackedStringArray()
	for other: Variant in session().battles:
		if other == bt:
			continue
		var s: Variant = other.sim
		var status: String = "決着" if s.over else "%.0f秒" % s.now()
		others.append("%s vs %s：%s　HP %d%% / %d%%" % [s.robots[0].name, s.robots[1].name, status,
			roundi(s.robots[0].hp_ratio() * 100.0), roundi(s.robots[1].hp_ratio() * 100.0)])
	_others.text = "\n".join(others)
