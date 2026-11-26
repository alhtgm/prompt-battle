# 試作の観戦画面：ルール方式の操縦を、上から見たアリーナと、2台それぞれのルールのフローチャートで見せる。
# 今たどっている道筋と実行中のルールが光る。LLM の書き換えは知らせ・変更前の表示・タイムラインで分かるようにする。
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
const FLASH_SEC: float = 4.0
## 行動の分類ごとの色（攻め・回り込み・間合い・守り）
const INTENT_COLORS: Dictionary = {
	"charge": Color(0.95, 0.35, 0.3), "push_to_pit": Color(0.95, 0.35, 0.3),
	"flank": Color(0.75, 0.45, 0.95), "circle": Color(0.75, 0.45, 0.95),
	"keep_distance": Color(0.3, 0.75, 0.95), "hold": Color(0.3, 0.75, 0.95),
	"retreat": Color(0.35, 0.85, 0.45), "go_repair": Color(0.35, 0.85, 0.45),
}

var data: GameData
var sim: BattleSim
var brains: Array = []
var seed_value: int = 1001
var prompt_idx: Array[int] = [0, 1]
var paused: bool = false
var waiting: bool = true
var _acc: float = 0.0
var _font: Font
var _flash_ms: Array[int] = [-100000, -100000]
var _seen_rewrites: Array[int] = [0, 0]
var _over_t: float = 0.0
var _opts: Array[OptionButton] = []
var _status: Label
## この試合で先に見直す機体（試合の種からくじで決める）
var first_mover: int = 0


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
	# 見直しを半周ずらす。どちらが先かは試合ごとのくじ（同じ種なら同じ）
	first_mover = root.fork("pilot_order").randi_range(0, 1)
	brains[first_mover].phase_offset = 0.0
	brains[1 - first_mover].phase_offset = brains[1 - first_mover].rewrite_interval * 0.5
	for b: RuleBrain in brains:
		b._next_ask_t = b.next_slot(-1.0)
	waiting = true
	_acc = 0.0
	_over_t = 0.0
	_seen_rewrites = [0, 0]
	_flash_ms = [-100000, -100000]


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


func _tc(center_x: float, y: float, s: String, size: int, col: Color) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_t(Vector2(center_x - w * 0.5, y), s, size, col)


func _to_screen(x: float, z: float) -> Vector2:
	var half: float = float(data.rule("battle.arena.half_size"))
	return ARENA_ORIGIN + Vector2(x + half, z + half) * (ARENA_PX / (2.0 * half))


func _px(v: float) -> float:
	return v * ARENA_PX / (2.0 * float(data.rule("battle.arena.half_size")))


func _flash(i: int) -> float:
	return clampf(1.0 - (Time.get_ticks_msec() - _flash_ms[i]) / (FLASH_SEC * 1000.0), 0.0, 1.0)


func _round_box(r: Rect2, fill: Color, edge: Color, width: float, radius: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(int(width))
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	draw_style_box(sb, r)


## 判断の記号（横長の六角形）
func _decision(r: Rect2, fill: Color, edge: Color, width: float) -> void:
	var c: float = minf(14.0, r.size.y * 0.5)
	var pts := PackedVector2Array([
		r.position + Vector2(c, 0), r.position + Vector2(r.size.x - c, 0), r.position + Vector2(r.size.x, r.size.y * 0.5),
		r.position + Vector2(r.size.x - c, r.size.y), r.position + Vector2(c, r.size.y), r.position + Vector2(0, r.size.y * 0.5)])
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, edge, width, true)


## 道筋に流れる光の粒
func _flow(a: Vector2, b: Vector2, col: Color) -> void:
	draw_line(a, b, col, 3.0, true)
	var len: float = a.distance_to(b)
	if len < 1.0:
		return
	var ph: float = fmod(Time.get_ticks_msec() / 1000.0 * 60.0, 14.0)
	var d: float = ph
	while d < len:
		draw_circle(a.lerp(b, d / len), 2.5, Color.WHITE)
		d += 14.0


func _arrow_head(tip: Vector2, dir: Vector2, col: Color, s: float = 6.0) -> void:
	var n: Vector2 = dir.normalized()
	var p: Vector2 = Vector2(-n.y, n.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - n * s + p * s * 0.6, tip - n * s - p * s * 0.6]), col)


## 行動の小さな絵
func _icon(intent: String, c: Vector2, col: Color) -> void:
	match intent:
		"charge":
			draw_line(c + Vector2(-8, 0), c + Vector2(4, 0), col, 3.0)
			_arrow_head(c + Vector2(9, 0), Vector2.RIGHT, col, 7.0)
		"retreat":
			draw_line(c + Vector2(8, 0), c + Vector2(-4, 0), col, 3.0)
			_arrow_head(c + Vector2(-9, 0), Vector2.LEFT, col, 7.0)
		"keep_distance":
			draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), col, 2.5)
			_arrow_head(c + Vector2(-9, 0), Vector2.LEFT, col)
			_arrow_head(c + Vector2(9, 0), Vector2.RIGHT, col)
		"flank":
			draw_arc(c + Vector2(0, 6), 8.0, PI, TAU * 0.97, 12, col, 2.5, true)
			_arrow_head(c + Vector2(8, 7), Vector2.DOWN, col)
		"circle":
			draw_arc(c, 8.0, 0.3, TAU - 0.4, 20, col, 2.5, true)
			_arrow_head(c + Vector2(8, -3), Vector2.UP, col)
		"push_to_pit":
			draw_circle(c + Vector2(5, 0), 5.0, Color.BLACK)
			draw_arc(c + Vector2(5, 0), 5.0, 0.0, TAU, 12, col, 1.5)
			draw_line(c + Vector2(-10, 0), c + Vector2(-3, 0), col, 2.5)
			_arrow_head(c + Vector2(0, 0), Vector2.RIGHT, col)
		"go_repair":
			draw_rect(Rect2(c + Vector2(-2, -8), Vector2(4, 16)), col)
			draw_rect(Rect2(c + Vector2(-8, -2), Vector2(16, 4)), col)
		_:
			draw_rect(Rect2(c + Vector2(-6, -7), Vector2(4, 14)), col)
			draw_rect(Rect2(c + Vector2(2, -7), Vector2(4, 14)), col)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COL_BG)
	if sim == null:
		return
	_draw_arena()
	for i: int in 2:
		_draw_panel(i)
	var y: float = ARENA_ORIGIN.y + ARENA_PX + 24.0
	var state: String = "ルールを作成中…（LLMが指示をルールに翻訳しています）" if waiting else \
		("一時停止（スペースで再開）" if paused else "%.1f 秒 / 残り %.1f 秒" % [sim.now(), sim.time_left()])
	_t(Vector2(16, y), state, 16, COL_FLASH if waiting else COL_TEXT)
	if sim.over:
		var w: int = sim.result["winner"]
		_t(Vector2(230, y), "決着：%s（%s）6秒後に再戦" % ["引き分け" if w < 0 else ["青", "橙"][w] + "の勝ち",
			{"destroyed": "破壊", "pit": "穴落ち", "time": "時間切れ"}.get(sim.result["reason"], "")], 16, COL_FLASH)
	_draw_timeline(Rect2(16, y + 14, ARENA_PX, 120))


## 試合全体のタイムライン：いつ LLM に聞いて、いつ書き換わったか
func _draw_timeline(r: Rect2) -> void:
	_t(r.position + Vector2(0, 12), "LLMの書き換えタイムライン", 13, COL_DIM)
	_t(r.position + Vector2(200, 12), "見直しは交互（くじで%sが先）" % ["青", "橙"][first_mover], 11, ROBOT_COLORS[first_mover])
	_t(r.position + Vector2(0, 28), "帯＝考えていた間　◆追/替/削＝作戦欄を変えた　・＝様子見　灰×＝却下　赤×＝失敗", 10, COL_DIM)
	var total: float = maxf(1.0, sim.now() + sim.time_left())
	var x0: float = r.position.x + 30.0
	var w: float = r.size.x - 34.0
	for i: int in 2:
		var ly: float = r.position.y + 50.0 + 30.0 * i
		var col: Color = ROBOT_COLORS[i]
		_t(Vector2(r.position.x, ly + 5), ["青", "橙"][i], 13, col)
		draw_line(Vector2(x0, ly), Vector2(x0 + w, ly), Color(0.25, 0.25, 0.27), 2.0)
		var b: RuleBrain = brains[i]
		# 見直しの予定時刻の目盛り
		var st: float = b.next_slot(-1.0)
		while st < total:
			var sx: float = x0 + w * st / total
			draw_line(Vector2(sx, ly - 10), Vector2(sx, ly - 5), Color(col, 0.5), 1.0)
			st += b.rewrite_interval
		if b.thinking and not waiting:
			var ax: float = x0 + w * clampf(b.asked_at / total, 0.0, 1.0)
			var nx: float = x0 + w * clampf(sim.now() / total, 0.0, 1.0)
			draw_rect(Rect2(ax, ly - 3, maxf(2.0, nx - ax), 6), col.darkened(0.3))
		for h: Dictionary in b.history:
			var ax2: float = x0 + w * clampf(float(h["asked"]) / total, 0.0, 1.0)
			var gx: float = x0 + w * clampf(float(h["got"]) / total, 0.0, 1.0)
			draw_rect(Rect2(ax2, ly - 3, maxf(2.0, gx - ax2), 6), col.darkened(0.45))
			_mark(h, gx, ly)
	var cx: float = x0 + w * clampf(sim.now() / total, 0.0, 1.0)
	draw_line(Vector2(cx, r.position.y + 38), Vector2(cx, r.position.y + 96), Color(1, 1, 1, 0.7), 1.5)
	for sec: int in range(0, int(total) + 1, 15):
		var tx: float = x0 + w * sec / total
		_tc(tx, r.position.y + 112, "%d秒" % sec, 10, COL_DIM)


func _mark(h: Dictionary, gx: float, ly: float) -> void:
	if not h["ok"]:
		_tc(gx, ly + 5, "×", 13, Color(0.95, 0.4, 0.35))
	elif not str(h["rejected"]).is_empty():
		_tc(gx, ly + 5, "×", 13, COL_DIM)
	elif h["op"] == "keep":
		draw_circle(Vector2(gx, ly), 3.0, COL_DIM)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(gx, ly - 7), Vector2(gx + 7, ly), Vector2(gx, ly + 7), Vector2(gx - 7, ly)]), COL_FLASH)
		_tc(gx, ly - 9, {"add": "追", "replace": "替", "delete": "削"}.get(h["op"], "?"), 11, COL_FLASH)


func _last_change(b: RuleBrain) -> Dictionary:
	for k: int in range(b.history.size() - 1, -1, -1):
		var h: Dictionary = b.history[k]
		if h["ok"] and h["op"] != "keep" and str(h["rejected"]).is_empty():
			return h
	return {}


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
		# 書き換えた瞬間：機体から黄色い輪が広がり、作戦の一言を吹き出しで出す
		var fl: float = _flash(r.index)
		if fl > 0.0:
			var grow: float = 1.0 - fl
			draw_arc(c, rad + 6.0 + 40.0 * fmod(grow * 2.0, 1.0), 0.0, TAU, 40, Color(COL_FLASH, fl), 3.0, true)
			var say: String = "作戦変更「%s」" % str(_last_change(brains[r.index]).get("why", ""))
			var sw: float = _font.get_string_size(say, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12.0
			var by: float = c.y + rad + 10.0
			if by + 20.0 > ARENA_ORIGIN.y + ARENA_PX:
				by = c.y - rad - 46.0  # 下の端では機体の上に出す
			var bp := Vector2(clampf(c.x - sw * 0.5, ARENA_ORIGIN.x, ARENA_ORIGIN.x + ARENA_PX - sw), by)
			_round_box(Rect2(bp, Vector2(sw, 20)), Color(0.15, 0.13, 0.05, 0.9 * minf(1.0, fl * 2.0)), Color(COL_FLASH, fl), 1.5, 6)
			_t(bp + Vector2(6, 15), say, 13, Color(COL_FLASH, minf(1.0, fl * 2.0)))
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
	var fl: float = _flash(i)
	var panel := Rect2(x - 6, 48, PANEL_W, 664)
	draw_rect(panel, Color(0.1, 0.1, 0.11))
	if fl > 0.0:
		draw_rect(panel, Color(COL_FLASH, fl), false, 2.0 + 3.0 * fl)
	var y: float = 70.0
	_t(Vector2(x, y), "%s  HP %d/%d" % [r.name, roundi(r.hp), roundi(r.max_hp)], 18, col)
	draw_rect(Rect2(x + 190, y - 12, 170, 8), Color(0.3, 0.05, 0.05))
	draw_rect(Rect2(x + 190, y - 12, 170 * r.hp_ratio(), 8), Color(0.3, 0.9, 0.3))
	y += 20.0
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
	y += 10.0
	# 状態の帯：ふだんは次までのカウントダウン、考え中は経過時間、作戦欄を変えた直後は大きな知らせ
	var slot := Rect2(x, y, PANEL_W - 12, 40)
	var now: float = sim.now()
	var last: Dictionary = b.history.back() if not b.history.is_empty() else {}
	var lc: Dictionary = _last_change(b)
	if fl > 0.0 and not lc.is_empty():
		_round_box(slot, Color(0.35, 0.28, 0.05).lerp(Color(0.16, 0.15, 0.1), 1.0 - fl), COL_FLASH, 2.0, 6)
		_t(slot.position + Vector2(10, 17), "作戦変更！ %s" % RuleBrain.op_text(lc["op"], lc["n"]), 15, COL_FLASH)
		_t(slot.position + Vector2(200, 16), "%.1f秒時点・考え%.1f秒" % [float(lc["got"]), float(lc["got"]) - float(lc["asked"])], 11, COL_DIM)
		_t(slot.position + Vector2(10, 34), "理由：" + str(lc["why"]), 12, COL_TEXT)
	elif b.thinking:
		_round_box(slot, Color(0.14, 0.14, 0.16), col, 1.5, 6)
		var el: float = (now - b.asked_at) if not waiting else 0.0
		var dots: String = ".".repeat(1 + (Time.get_ticks_msec() / 300) % 3)
		_t(slot.position + Vector2(10, 17), "LLMが戦況と成績を見て考え中" + dots, 14, col.lightened(0.3))
		_t(slot.position + Vector2(10, 33), "%.1f秒経過　作戦名「%s」" % [el, b.say], 12, COL_DIM)
		var sweep: float = fmod(Time.get_ticks_msec() / 1000.0, 1.2) / 1.2
		draw_rect(Rect2(slot.position + Vector2(2 + (slot.size.x - 4) * sweep * 0.8, slot.size.y - 3), Vector2((slot.size.x - 4) * 0.2, 2)), col)
	else:
		var left: float = b.next_ask_in(now)
		var frac: float = clampf(1.0 - left / b.rewrite_interval, 0.0, 1.0)
		_round_box(slot, Color(0.14, 0.14, 0.16), Color(0.3, 0.3, 0.32), 1.0, 6)
		draw_rect(Rect2(slot.position + Vector2(2, slot.size.y - 3), Vector2((slot.size.x - 4) * frac, 2)), col.darkened(0.2))
		_t(slot.position + Vector2(10, 17), ("次の見直しまで %.1f秒" % left) if left > 0.0 else "まもなく見直し", 14, COL_TEXT)
		var note: String = "作戦名「%s」" % b.say
		if not last.is_empty():
			if not last["ok"]:
				note = "前回：失敗（%s）" % b.last_error
			elif not str(last["rejected"]).is_empty():
				note = "前回：%sは却下（%s）" % [RuleBrain.op_text(last["op"], last["n"]), last["rejected"]]
			elif last["op"] == "keep":
				note = "前回：様子見「%s」" % last["why"]
			else:
				note = "前回：%s「%s」" % [RuleBrain.op_text(last["op"], last["n"]), last["why"]]
		_t(slot.position + Vector2(10, 33), note.left(34), 12, COL_DIM)
	y += 50.0
	# フローチャート：毎瞬、上から順に条件を調べる。はい → 右の行動、いいえ → 下へ
	var spine_x: float = x + 100.0
	_round_box(Rect2(spine_x - 80, y, 160, 22), Color(0.2, 0.2, 0.22), COL_DIM, 1.0, 11)
	_tc(spine_x, y + 16, "毎瞬チェック（上から）", 12, COL_TEXT)
	var prev_bottom := Vector2(spine_x, y + 22)
	y += 22.0
	var rules: Array[Dictionary] = b.ruleset.rules
	var facts: Dictionary = RuleSet.facts(r, sim.robots[1 - i], now, sim.time_left(), sim._b, b._last_hit_t, b._last_give_t)
	var n_tac: int = b.n_tactics()
	# 作戦欄の見出し
	y += 8.0
	_section(x, y, "作戦欄", "LLMが試合中に直す（%d/%d行）" % [n_tac, RuleBrain.MAX_TACTICS], col, false)
	y += 12.0
	if n_tac == 0:
		y += 8.0
		var ph := Rect2(x, y, 200, 22)
		_round_box(ph, Color(0, 0, 0, 0), Color(0.3, 0.3, 0.32), 1.0, 6)
		_tc(spine_x, y + 15, "（まだなし）", 11, COL_DIM)
		draw_line(prev_bottom, Vector2(spine_x, y), Color(0.3, 0.3, 0.32), 2.0)
		prev_bottom = Vector2(spine_x, y + 22)
		y += 22.0
	if fl > 0.0 and not b.removed_text.is_empty():
		_t(Vector2(x + 210, y + 4), "削除：" + b.removed_text.left(14), 11, Color(0.85, 0.75, 0.45, fl))
	for k: int in rules.size():
		var rule: Dictionary = rules[k]
		if rule["lock"] and (k == 0 or not rules[k - 1]["lock"]):
			y += 8.0
			_section(x, y, "土台", "指示から作成・固定", COL_DIM, true)
			y += 12.0
		var conds: Array = rule["if"]
		var h: float = 26.0 + 16.0 * maxf(0, conds.size() - 1)
		y += 16.0
		var is_active: bool = k == b.active
		var passed: bool = b.active >= 0 and k < b.active
		var on_path: bool = is_active or passed
		var changed: bool = k < b.changed.size() and b.changed[k]
		var glow: bool = changed and fl > 0.0
		var top := Vector2(spine_x, y)
		if on_path and b.active >= 0:
			_flow(prev_bottom, top, col)
		else:
			draw_line(prev_bottom, top, Color(0.3, 0.3, 0.32), 2.0)
		_arrow_head(top, Vector2.DOWN, col if on_path else Color(0.3, 0.3, 0.32))
		var cbox := Rect2(x, y, 200, h)
		var base_edge: Color = Color(0.35, 0.35, 0.37) if rule["lock"] else col.darkened(0.35)
		var edge: Color = COL_FLASH.lerp(col, 1.0 - fl) if glow else (col if on_path else base_edge)
		var fill: Color = col.darkened(0.6) if is_active else (Color(0.13, 0.13, 0.14) if rule["lock"] else Color(0.17, 0.16, 0.2))
		_t(Vector2(x - 4, y + 4), "%d" % (k + 1), 10, COL_DIM)
		if conds.is_empty():
			_round_box(cbox, fill, edge, 3.0 if is_active or glow else 1.0, 14)
			_tc(spine_x, y + 18, "いつも（上が全部いいえ）", 13, COL_TEXT)
		else:
			_decision(cbox, fill, edge, 3.0 if is_active or glow else 1.5)
			for c: int in conds.size():
				var on: bool = facts.get(conds[c], false)
				var cy: float = y + 18.0 + 16.0 * c
				draw_circle(Vector2(x + 26, cy - 5), 5.0, Color(0.4, 0.95, 0.5) if on else Color(0.35, 0.2, 0.2))
				_t(Vector2(x + 36, cy), ("かつ " if c > 0 else "") + RuleSet.ATOM_SHORT.get(conds[c], conds[c]) + "？", 13,
					Color(0.6, 1.0, 0.65) if on else Color(0.8, 0.6, 0.55))
		if glow:
			_round_box(Rect2(x + 4, y - 9, 40, 16), COL_FLASH, COL_FLASH, 0.0, 4)
			_t(Vector2(x + 9, y + 4), "変更" if not b.prev_text[k].is_empty() else "NEW", 11, Color.BLACK)
		var ay: float = y + h * 0.5
		var abox := Rect2(x + 236, ay - 16, 132, 32)
		if is_active:
			_flow(Vector2(x + 200, ay), Vector2(abox.position.x, ay), col)
		else:
			draw_line(Vector2(x + 200, ay), Vector2(abox.position.x, ay), Color(0.3, 0.3, 0.32), 2.0)
		_arrow_head(Vector2(abox.position.x, ay), Vector2.RIGHT, col if is_active else Color(0.3, 0.3, 0.32))
		if not conds.is_empty():
			_t(Vector2(x + 204, ay - 4), "はい", 10, COL_DIM)
		var icol: Color = INTENT_COLORS.get(rule["do"], COL_TEXT)
		_round_box(abox, icol.darkened(0.45) if is_active else Color(0.16, 0.16, 0.18),
			Color.WHITE if is_active else icol.darkened(0.3), 3.0 if is_active else 1.5, 8)
		_icon(rule["do"], abox.position + Vector2(18, 16), Color.WHITE if is_active else icol)
		_t(abox.position + Vector2(34, 15), RuleSet.INTENT_SHORT.get(rule["do"], rule["do"]), 13, Color.WHITE if is_active else COL_TEXT)
		var sub: String = ("＋" + r.skills[rule["skill"]].def.name.left(4) + " ") if rule["skill"] >= 0 else ""
		_t(abox.position + Vector2(34, 28), "%s%.1f秒 与%d 受%d" % [sub, float(rule["sec"]), roundi(float(rule["given"])), roundi(float(rule["taken"]))], 10,
			COL_TEXT if is_active else COL_DIM)
		if is_active:
			_t(Vector2(abox.position.x + 4, abox.position.y - 3), "▶ 実行中", 11, col.lightened(0.4))
		y += h
		if glow and not b.prev_text[k].is_empty():
			_t(Vector2(spine_x + 8, y + 12), "前：" + b.prev_text[k].left(22), 11, Color(0.85, 0.75, 0.45, fl))
		elif k < rules.size() - 1 and rules[k + 1]["lock"] == rule["lock"]:  # 欄の境目では見出しと重なるので出さない
			_t(Vector2(spine_x - 34, y + 12), "いいえ", 10, COL_DIM)
		prev_bottom = Vector2(spine_x, y)


## 欄の見出し（左に名前、右に説明、横線）
func _section(x: float, y: float, name: String, note: String, col: Color, lock: bool) -> void:
	draw_line(Vector2(x, y), Vector2(x + PANEL_W - 14, y), Color(0.25, 0.25, 0.27), 1.0)
	var lx: float = x
	if lock:
		draw_rect(Rect2(x, y + 1, 9, 7), COL_DIM)
		draw_arc(Vector2(x + 4.5, y + 1), 3.0, PI, TAU, 8, COL_DIM, 1.5)
		lx += 13.0
	draw_rect(Rect2(lx - 2, y - 7, _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 4, 14), Color(0.1, 0.1, 0.11))
	_t(Vector2(lx, y + 5), name, 12, col)
	var nw: float = _font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_rect(Rect2(x + PANEL_W - 18 - nw, y - 6, nw + 4, 12), Color(0.1, 0.1, 0.11))
	_t(Vector2(x + PANEL_W - 16 - nw, y + 4), note, 10, COL_DIM)
