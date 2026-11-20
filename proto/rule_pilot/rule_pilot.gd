# 試作の観戦画面：ルール方式の操縦を、上から見たアリーナと、2台それぞれのルールのフローチャートで見せる。
# 今実行中のルールが光り、LLM が書き換えたルールは黄色く光る。上のボタンでプロンプトを選んで再戦できる。
extends Node2D

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Robot := preload("res://core/battle_robot.gd")
const LlmConfig := preload("res://agent/llm_config.gd")
const RuleSet := preload("res://proto/rule_pilot/rule_set.gd")
const RuleBrain := preload("res://proto/rule_pilot/rule_brain.gd")

const PROMPTS: Array[String] = [
	"距離をとって撃ちまくれ。弾が切れたら突っ込め。HPが減ったら修理に行け",
	"相手の後ろに回り込んで攻めろ。被弾したら一度下がってまた回り込め",
	"相手が穴の近くに来たら穴に押し込め。それ以外は突撃しろ",
	"慎重に戦え。HPが減ったら修理に行け",
	"ヒットアンドアウェイ。当てたらすぐ離れて、また回り込んで攻めろ",
	"とにかく突撃して殴れ。相手が動けないときは全力で攻めろ",
	"相手の周りを回って隙をうかがえ。相手のHPが減ったら一気に攻めろ",
]
const ARENA_PX: float = 470.0
const ARENA_ORIGIN := Vector2(16, 60)
const PANEL_X: Array[float] = [500.0, 892.0]
const PANEL_W: float = 380.0
const ROBOT_COLORS: Array[Color] = [Color(0.35, 0.62, 1.0), Color(1.0, 0.58, 0.22)]
const COL_BG := Color(0.07, 0.07, 0.08)
const COL_FLOOR := Color(0.16, 0.16, 0.17)
const COL_TEXT := Color(0.92, 0.91, 0.88)
const COL_DIM := Color(0.55, 0.55, 0.53)
const COL_FLASH := Color(1.0, 0.85, 0.25)

var data: GameData
var sim: BattleSim
var brains: Array = []
var seed_value: int = 1001
var prompt_idx: Array[int] = [0, 1]
var paused: bool = false
var waiting: bool = true
var _acc: float = 0.0
var _font: Font
var _flash_ms: Array[int] = [0, 0]
var _seen_rewrites: Array[int] = [0, 0]
var _over_t: float = 0.0
var _opts: Array[OptionButton] = []
var _status: Label


func _ready() -> void:
	_font = ThemeDB.fallback_font
	data = GameData.new()
	data.load_dir()
	_build_ui()
	_start()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 10)
	bar.add_theme_constant_override("separation", 8)
	layer.add_child(bar)
	for i: int in 2:
		var l := Label.new()
		l.text = ["青", "橙"][i]
		l.add_theme_color_override("font_color", ROBOT_COLORS[i])
		bar.add_child(l)
		var o := OptionButton.new()
		for p: String in PROMPTS:
			o.add_item(p.left(16) + ("…" if p.length() > 16 else ""))
		o.select(prompt_idx[i])
		o.custom_minimum_size = Vector2(250, 0)
		o.item_selected.connect(func(k: int) -> void: prompt_idx[i] = k)
		bar.add_child(o)
		_opts.append(o)
	for spec: Array in [["この指示で再戦", _start], ["別の機体で", _next_build], ["一時停止", _toggle_pause]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		bar.add_child(b)


func _next_build() -> void:
	seed_value += 1
	_start()


func _toggle_pause() -> void:
	paused = not paused


func _start() -> void:
	var cfg := LlmConfig.new()
	cfg.load_config()
	var root := Rng.new(seed_value)
	var setup: Rng = root.fork("setup")
	var builds: Array = [Loot.random_build(data, setup, 1), Loot.random_build(data, setup, 100)]
	brains = []
	for i: int in 2:
		var b := RuleBrain.new()
		b.index = i
		b.host = str(cfg.values.get("host", "127.0.0.1"))
		b.port = int(cfg.values.get("port", 8399))
		brains.append(b)
	var prompts: Array = [PROMPTS[prompt_idx[0]], PROMPTS[prompt_idx[1]]]
	sim = BattleSim.new(data, builds, brains, prompts, ["青", "橙"], root.fork("battle"))
	for b: RuleBrain in brains:
		b.sim = sim
	waiting = true
	_acc = 0.0
	_over_t = 0.0
	_seen_rewrites = [0, 0]


func _process(delta: float) -> void:
	if sim == null:
		return
	if waiting:
		# 最初のルールが両方そろうまで試合を始めない（通信だけ進める）
		for b: RuleBrain in brains:
			b.poll(0.0)
		waiting = not (brains[0].have_rules and brains[1].have_rules)
	elif not paused and not sim.over:
		_acc += delta
		var n: int = 0
		while _acc >= sim.dt and not sim.over and n < 30:
			sim.step()
			_acc -= sim.dt
			n += 1
	elif sim.over and not paused:
		_over_t += delta
		if _over_t > 6.0:
			_start()
	for i: int in 2:
		if brains[i].rewrites != _seen_rewrites[i]:
			_seen_rewrites[i] = brains[i].rewrites
			_flash_ms[i] = Time.get_ticks_msec()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_SPACE:
		_toggle_pause()


# ---- 描画 ----

func _t(pos: Vector2, s: String, size: int = 14, col: Color = COL_TEXT) -> void:
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _to_screen(x: float, z: float) -> Vector2:
	var half: float = float(data.rule("battle.arena.half_size"))
	return ARENA_ORIGIN + Vector2(x + half, z + half) * (ARENA_PX / (2.0 * half))


func _px(v: float) -> float:
	return v * ARENA_PX / (2.0 * float(data.rule("battle.arena.half_size")))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COL_BG)
	if sim == null:
		return
	_draw_arena()
	for i: int in 2:
		_draw_panel(i)
	var y: float = ARENA_ORIGIN.y + ARENA_PX + 28.0
	var state: String = "ルールを作成中…（LLMが指示をルールに翻訳しています）" if waiting else \
		("一時停止" if paused else "%.1f 秒 / 残り %.1f 秒" % [sim.now(), sim.time_left()])
	_t(Vector2(16, y), state, 16, COL_FLASH if waiting else COL_TEXT)
	y += 24.0
	if sim.over:
		var w: int = sim.result["winner"]
		_t(Vector2(16, y), "決着：%s（%s）  6秒後に再戦" % ["引き分け" if w < 0 else ["青", "橙"][w] + " の勝ち",
			{"destroyed": "破壊", "pit": "穴落ち", "time": "時間切れ"}.get(sim.result["reason"], "")], 18, COL_FLASH)
		y += 24.0
	_t(Vector2(16, y), "LLMの書き換え（約6秒おき）", 13, COL_DIM)
	y += 18.0
	for i: int in 2:
		for line: String in brains[i].log.slice(-3):
			_t(Vector2(16, y), line.left(46), 12, ROBOT_COLORS[i])
			y += 16.0


func _draw_arena() -> void:
	var arena: Dictionary = data.rules["battle"]["arena"]
	draw_rect(Rect2(ARENA_ORIGIN, Vector2(ARENA_PX, ARENA_PX)), COL_FLOOR)
	draw_rect(Rect2(ARENA_ORIGIN, Vector2(ARENA_PX, ARENA_PX)), Color(0.45, 0.45, 0.45), false, 3.0)
	for pad: Dictionary in arena["repair_pads"]:
		draw_circle(_to_screen(pad["x"], pad["z"]), _px(pad["r"]), Color(0.15, 0.45, 0.25))
	for pit: Dictionary in arena["pits"]:
		var c: Vector2 = _to_screen(pit["x"], pit["z"])
		draw_circle(c, _px(pit["r"]), Color.BLACK)
		draw_arc(c, _px(pit["r"]), 0.0, TAU, 48, Color(0.85, 0.45, 0.1), 2.0)
	for s: BattleSim.Shot in sim.shots:
		draw_circle(_to_screen(s.x, s.z), 3.0, Color(1, 1, 0.7))
	for r: Robot in sim.robots:
		var col: Color = ROBOT_COLORS[r.index].darkened(0.7) if r.fell else ROBOT_COLORS[r.index]
		var c: Vector2 = _to_screen(r.x, r.z)
		var rad: float = _px(r.radius)
		draw_circle(c, rad, col)
		draw_line(c, c + Vector2(cos(r.th), sin(r.th)) * rad * 1.6, Color.WHITE, 3.0)
		if r.stun > 0.0:
			draw_arc(c, rad + 6.0, 0.0, TAU, 24, Color(1, 0.9, 0.2), 2.0)
		if r.repairing:
			draw_arc(c, rad + 4.0, 0.0, TAU, 24, Color(0.3, 1.0, 0.4), 2.0)
		for s: Robot.SkillSlot in r.skills:
			if s.active_t > 0.0:
				draw_arc(c, rad + 9.0, 0.0, TAU, 24, Color(0.5, 1.0, 1.0, 0.8), 2.0)
		var bar := Rect2(c + Vector2(-rad, -rad - 10.0), Vector2(rad * 2.0, 4.0))
		draw_rect(bar, Color(0.3, 0.05, 0.05))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * r.hp_ratio(), 4.0)), Color(0.3, 0.9, 0.3))
		_t(c + Vector2(-rad, -rad - 14.0), RuleSet.INTENT_SHORT.get(r.intent, r.intent), 13, col.lightened(0.3))


func _draw_panel(i: int) -> void:
	var x: float = PANEL_X[i]
	var col: Color = ROBOT_COLORS[i]
	var r: Robot = sim.robots[i]
	var b: RuleBrain = brains[i]
	var y: float = 62.0
	draw_rect(Rect2(x - 6, 48, PANEL_W, 664), Color(0.1, 0.1, 0.11))
	_t(Vector2(x, y + 8), "%s  HP %d/%d" % [r.name, roundi(r.hp), roundi(r.max_hp)], 18, col)
	draw_rect(Rect2(x + 190, y - 4, 170, 8), Color(0.3, 0.05, 0.05))
	draw_rect(Rect2(x + 190, y - 4, 170 * r.hp_ratio(), 8), Color(0.3, 0.9, 0.3))
	y += 28.0
	var ws: PackedStringArray = PackedStringArray()
	for w: Robot.WeaponSlot in r.weapons:
		ws.append(w.def.name + ("(%d)" % w.ammo if w.ammo >= 0 else ""))
	var ss: PackedStringArray = PackedStringArray()
	for s: Robot.SkillSlot in r.skills:
		ss.append(s.def.name + ("" if s.is_ready() else "…"))
	_t(Vector2(x, y), "武器：%s  スキル：%s" % [",".join(ws), ",".join(ss) if ss.size() > 0 else "なし"], 13)
	y += 18.0
	var p: String = b.prompt
	_t(Vector2(x, y), "指示：" + p.left(24), 13, COL_DIM)
	if p.length() > 24:
		y += 16.0
		_t(Vector2(x + 42, y), p.substr(24, 24), 13, COL_DIM)
	y += 22.0
	var st: String = "LLMが書き換え中…" if b.thinking else "書き換え %d回" % b.rewrites
	if not b.last_error.is_empty():
		st += "（前回：%s）" % b.last_error
	_t(Vector2(x, y), "作戦「%s」   %s" % [b.say, st], 14, COL_FLASH if b.thinking else COL_TEXT)
	y += 14.0
	# フローチャート：上から順に条件を調べ、はい → 行動、いいえ → 次へ
	var flash: float = clampf(1.0 - (Time.get_ticks_msec() - _flash_ms[i]) / 3000.0, 0.0, 1.0)
	var rules: Array[Dictionary] = b.ruleset.rules
	var facts: Dictionary = RuleSet.facts(r, sim.robots[1 - i], sim.now(), sim.time_left(), sim._b, b._last_hit_t)
	for k: int in rules.size():
		var rule: Dictionary = rules[k]
		var conds: Array = rule["if"]
		var h: float = 30.0 + 20.0 * maxf(0, conds.size() - 1)
		y += 26.0
		var is_active: bool = k == b.active
		var cbox := Rect2(x, y, 200, h)
		var abox := Rect2(x + 240, y + h * 0.5 - 17, 128, 34)
		var fill: Color = col.darkened(0.55) if is_active else Color(0.16, 0.16, 0.18)
		draw_rect(cbox, fill)
		draw_rect(abox, col.darkened(0.2) if is_active else Color(0.2, 0.2, 0.22))
		var changed: bool = k < b.changed.size() and b.changed[k]
		var edge: Color = COL_FLASH.lerp(col, 1.0 - flash) if changed and flash > 0.0 else (col if is_active else Color(0.35, 0.35, 0.37))
		draw_rect(cbox, edge, false, 3.0 if is_active or (changed and flash > 0.0) else 1.0)
		draw_rect(abox, edge, false, 3.0 if is_active else 1.0)
		if conds.is_empty():
			_t(Vector2(x + 10, y + 20), "いつも（上が全部いいえ）", 14, COL_TEXT)
		for c: int in conds.size():
			var on: bool = facts.get(conds[c], false)
			_t(Vector2(x + 8, y + 20 + 20 * c), ("○ " if on else "× ") + RuleSet.ATOM_SHORT.get(conds[c], conds[c]), 14,
				Color(0.5, 1.0, 0.55) if on else Color(0.85, 0.5, 0.45))
		draw_line(Vector2(x + 200, y + h * 0.5), Vector2(x + 240, y + h * 0.5), col if is_active else COL_DIM, 2.0)
		_t(Vector2(x + 204, y + h * 0.5 - 4), "はい" if not conds.is_empty() else "", 11, COL_DIM)
		var act: String = RuleSet.INTENT_SHORT.get(rule["do"], rule["do"])
		_t(Vector2(abox.position.x + 8, abox.position.y + 22), act + ("＋" + r.skills[rule["skill"]].def.name.left(4) if rule["skill"] >= 0 else ""), 14,
			Color.WHITE if is_active else COL_TEXT)
		if is_active:
			_t(Vector2(abox.position.x + 8, abox.position.y - 4), "▶ 実行中", 11, col.lightened(0.3))
		if k < rules.size() - 1:
			draw_line(Vector2(x + 40, y + h), Vector2(x + 40, y + h + 26), COL_DIM, 2.0)
			_t(Vector2(x + 46, y + h + 18), "いいえ", 11, COL_DIM)
		y += h
