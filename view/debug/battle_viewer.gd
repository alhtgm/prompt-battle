# 開発用の仮の観戦画面。ランダムな機体同士のバトルを、上から見た2Dで実時間に描く（段階5の3D表示ができるまでの仮）。
# 試合の状態は読むだけで、進めるのは BattleSim.step() だけ。操作：Space 一時停止 / N 次の試合 / 1〜4 速さ / R 同じ種でやり直し / Esc タイトルへ
extends Node2D

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Robot := preload("res://core/battle_robot.gd")
const MockBrain := preload("res://agent/mock_brain.gd")

## 試合ごとにランダムに選ぶプロンプト
const PROMPTS: Array[String] = [
	"とにかく突撃して殴れ",
	"穴の近くに相手が来たら穴に押し込め",
	"距離をとって撃ちまくれ。弾が切れたら突っ込め",
	"慎重に戦え。HPが減ったら修理に行け",
	"相手の後ろに回り込んで攻めろ",
	"相手の周りをぐるぐる回って様子を見ろ",
	"ガンガン攻めろ、穴には気をつけろ",
]

const INTENT_LABELS: Dictionary = {
	"charge": "突撃", "flank": "回り込み", "keep_distance": "距離を取る", "retreat": "逃げる",
	"push_to_pit": "穴へ押し込む", "go_repair": "修理に向かう", "circle": "周りを回る", "hold": "その場で待つ",
}
const REASON_LABELS: Dictionary = {"destroyed": "破壊", "pit": "穴落ち", "time": "時間切れ"}

## 画面の配置（ピクセル）
const ARENA_PX: float = 640.0
const ARENA_ORIGIN := Vector2(20, 40)
const PANEL_X: float = 690.0
const SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0]
## 決着してから次の試合に進むまでの秒数
const NEXT_MATCH_WAIT: float = 5.0

const COL_BG := Color(0.07, 0.07, 0.08)
const COL_FLOOR := Color(0.16, 0.16, 0.17)
const COL_WALL := Color(0.45, 0.45, 0.45)
const COL_PIT := Color(0.0, 0.0, 0.0)
const COL_PIT_EDGE := Color(0.75, 0.2, 0.15)
const COL_PAD := Color(0.15, 0.45, 0.25)
const COL_TEXT := Color(0.9, 0.9, 0.88)
const COL_DIM := Color(0.6, 0.6, 0.58)
const ROBOT_COLORS: Array[Color] = [Color(0.3, 0.6, 1.0), Color(1.0, 0.55, 0.2)]

var data: GameData
var sim: BattleSim
var seed_value: int = 0
var prompts: Array = []
var log_lines: Array[String] = []
var _acc: float = 0.0
var _speed_index: int = 1
var _paused: bool = false
var _over_wait: float = 0.0
var _font: Font
var _screenshot_path: String = ""
var _screenshot_at: float = -1.0
var _elapsed: float = 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	data = GameData.new()
	if not data.load_dir():
		push_error("data/ が読めない：\n" + "\n".join(data.errors))
		return
	# 開発用：--screenshot=保存先 --screenshot-at=秒 でその時点の画面を保存して終わる
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--screenshot-at="):
			_screenshot_at = float(arg.get_slice("=", 1))
		elif arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
	if seed_value == 0:
		seed_value = Time.get_ticks_usec() % 1000000 + 1
	_start_match(seed_value)


## 種から試合を作る（同じ種なら同じ試合になる）
func _start_match(s: int) -> void:
	seed_value = s
	var root := Rng.new(seed_value)
	var setup: Rng = root.fork("setup")
	var builds: Array = [Loot.random_build(data, setup, 1), Loot.random_build(data, setup, 100)]
	prompts = [setup.pick(PROMPTS), setup.pick(PROMPTS)]
	var brains: Array = [MockBrain.new(root.fork("brain/0")), MockBrain.new(root.fork("brain/1"))]
	sim = BattleSim.new(data, builds, brains, prompts, ["青", "橙"], root.fork("battle"))
	log_lines.clear()
	_acc = 0.0
	_over_wait = 0.0
	_log("試合開始（種 %d）" % seed_value)


func _process(delta: float) -> void:
	if sim == null:
		return
	_elapsed += delta
	if not _paused and not sim.over:
		_acc += delta * SPEEDS[_speed_index]
		var steps: int = 0
		while _acc >= sim.dt and not sim.over and steps < 600:
			sim.step()
			_collect_events()
			_acc -= sim.dt
			steps += 1
	elif sim.over and not _paused:
		_over_wait += delta
		if _over_wait >= NEXT_MATCH_WAIT:
			_start_match(seed_value + 1)
	queue_redraw()
	if _screenshot_at >= 0.0 and _elapsed >= _screenshot_at:
		_screenshot_at = -1.0
		_save_screenshot()


func _save_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(_screenshot_path)
	print("スクリーンショットを保存：", _screenshot_path)
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			_paused = not _paused
		KEY_N:
			_start_match(seed_value + 1)
		KEY_R:
			_start_match(seed_value)
		KEY_1, KEY_2, KEY_3, KEY_4:
			_speed_index = k.keycode - KEY_1
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://view/main.tscn")


# ---- 出来事を実況の行にする ----

func _log(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > 16:
		log_lines.remove_at(0)


func _name(i: int) -> String:
	return sim.robots[i].name


func _collect_events() -> void:
	var t: String = "%5.1f秒 " % sim.now()
	for e: Dictionary in sim.events:
		match str(e["type"]):
			"intent":
				_log(t + "%s「%s」→ %s" % [_name(e["robot"]), e["say"], INTENT_LABELS.get(e["intent"], e["intent"])])
			"confused":
				_log(t + "%s「%s」" % [_name(e["robot"]), e["say"]])
			"hit":
				if float(e["damage"]) >= 2.0:  # 機関銃の細かい被弾は省く
					_log(t + "%s が %s で %d 被弾%s" % [_name(e["robot"]), e["weapon"], roundi(e["damage"]),
						"（背後から）" if e["back"] else ""])
			"flip":
				_log(t + "%s がひっくり返された！" % _name(e["robot"]))
			"skill":
				_log(t + "%s が %s を使った" % [_name(e["robot"]), e["skill"]])
			"fall":
				_log(t + "%s が穴に落ちた！" % _name(e["robot"]))
			"repair":
				_log(t + "%s が修理中" % _name(e["robot"]))
			"ammo_out":
				_log(t + "%s の %s が弾切れ" % [_name(e["robot"]), e["weapon"]])
			"over":
				var w: int = e["winner"]
				var who: String = "引き分け" if w < 0 else "%s の勝ち" % _name(w)
				_log(t + "決着：%s（%s）" % [who, REASON_LABELS.get(e["reason"], e["reason"])])


# ---- 描画 ----

func _to_screen(x: float, z: float) -> Vector2:
	var half: float = float(data.rule("battle.arena.half_size"))
	return ARENA_ORIGIN + Vector2(x + half, z + half) * (ARENA_PX / (2.0 * half))


func _px(world_len: float) -> float:
	return world_len * ARENA_PX / (2.0 * float(data.rule("battle.arena.half_size")))


func _text(pos: Vector2, s: String, size: int = 16, col: Color = COL_TEXT) -> void:
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COL_BG)
	if sim == null:
		return
	var arena: Dictionary = data.rules["battle"]["arena"]
	draw_rect(Rect2(ARENA_ORIGIN, Vector2(ARENA_PX, ARENA_PX)), COL_FLOOR)
	draw_rect(Rect2(ARENA_ORIGIN, Vector2(ARENA_PX, ARENA_PX)), COL_WALL, false, 3.0)
	for pad: Dictionary in arena["repair_pads"]:
		draw_circle(_to_screen(pad["x"], pad["z"]), _px(pad["r"]), COL_PAD)
	for pit: Dictionary in arena["pits"]:
		var c: Vector2 = _to_screen(pit["x"], pit["z"])
		draw_circle(c, _px(pit["r"]), COL_PIT)
		draw_arc(c, _px(pit["r"]), 0.0, TAU, 48, COL_PIT_EDGE, 2.0)
	for s: BattleSim.Shot in sim.shots:
		draw_circle(_to_screen(s.x, s.z), 3.0, Color(1, 1, 0.7))
	for r: Robot in sim.robots:
		_draw_robot(r)
	_draw_panel()


func _draw_robot(r: Robot) -> void:
	var col: Color = ROBOT_COLORS[r.index]
	if r.fell:
		col = col.darkened(0.7)
	var c: Vector2 = _to_screen(r.x, r.z)
	var rad: float = _px(r.radius)
	draw_circle(c, rad, col)
	var fwd := Vector2(cos(r.th), sin(r.th))
	draw_line(c, c + fwd * rad * 1.6, Color.WHITE, 3.0)
	# 武器の当たる向きの目印（前方の扇形）
	draw_arc(c, rad + 4.0, r.th - 0.5, r.th + 0.5, 12, Color(1, 1, 1, 0.5), 2.0)
	if r.stun > 0.0:
		draw_arc(c, rad + 7.0, 0.0, TAU, 24, Color(1, 0.9, 0.2), 2.0)
	for s: Robot.SkillSlot in r.skills:
		if s.active_t > 0.0:
			draw_arc(c, rad + 10.0, 0.0, TAU, 24, Color(0.5, 1.0, 1.0, 0.8), 2.0)
	if r.repairing:
		draw_arc(c, rad + 4.0, 0.0, TAU, 24, Color(0.3, 1.0, 0.4), 2.0)
	# HPの帯と一言
	var bar := Rect2(c + Vector2(-rad, -rad - 12.0), Vector2(rad * 2.0, 5.0))
	draw_rect(bar, Color(0.3, 0.05, 0.05))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * r.hp_ratio(), bar.size.y)), Color(0.3, 0.9, 0.3))
	if not r.say.is_empty():
		_text(c + Vector2(-rad, -rad - 18.0), r.say, 14)


func _draw_panel() -> void:
	var y: float = 30.0
	_text(Vector2(PANEL_X, y), "開発用の観戦画面（仮）  種 %d" % seed_value, 18)
	y += 26.0
	var state: String = "一時停止" if _paused else ("x%s" % SPEEDS[_speed_index])
	_text(Vector2(PANEL_X, y), "%.1f 秒 / 残り %.1f 秒   %s" % [sim.now(), sim.time_left(), state], 16, COL_DIM)
	y += 30.0
	for r: Robot in sim.robots:
		y = _draw_robot_info(r, y) + 12.0
	if sim.over:
		var w: int = sim.result["winner"]
		var who: String = "引き分け" if w < 0 else "%s の勝ち" % _name(w)
		_text(Vector2(PANEL_X, y), "決着：%s（%s）" % [who, REASON_LABELS.get(sim.result["reason"], "")], 22,
			Color(1, 0.9, 0.4))
		y += 30.0
	_text(Vector2(PANEL_X, y), "実況", 16, COL_DIM)
	y += 20.0
	for line: String in log_lines:
		_text(Vector2(PANEL_X, y), line, 13)
		y += 17.0
	_text(Vector2(PANEL_X, 705.0), "Space 一時停止 / N 次の試合 / R やり直し / 1〜4 速さ / Esc タイトルへ", 13, COL_DIM)


func _draw_robot_info(r: Robot, y: float) -> float:
	var col: Color = ROBOT_COLORS[r.index]
	var fdef: GameData.PartDef = data.get_part(r.build.frame.def_id)
	_text(Vector2(PANEL_X, y), "■ %s  HP %d / %d  %s" % [r.name, roundi(r.hp), roundi(r.max_hp), fdef.name], 17, col)
	y += 20.0
	var ws: PackedStringArray = PackedStringArray()
	for w: Robot.WeaponSlot in r.weapons:
		ws.append(w.def.name + ("(%d)" % w.ammo if w.ammo >= 0 else ""))
	var ss: PackedStringArray = PackedStringArray()
	for s: Robot.SkillSlot in r.skills:
		ss.append(s.def.name + ("" if s.is_ready() else "…"))
	_text(Vector2(PANEL_X + 14.0, y), "武器：%s   スキル：%s" % [", ".join(ws), ", ".join(ss) if ss.size() > 0 else "なし"], 14)
	y += 18.0
	_text(Vector2(PANEL_X + 14.0, y), "プロンプト：%s" % (prompts[r.index] if str(prompts[r.index]) != "" else "（なし）"), 14, COL_DIM)
	y += 18.0
	_text(Vector2(PANEL_X + 14.0, y), "方針：%s  「%s」" % [INTENT_LABELS.get(r.intent, r.intent), r.say], 15)
	return y + 18.0
