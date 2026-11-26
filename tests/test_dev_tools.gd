# 開発用の道具のテスト。一時停止（どの段階でも進まない、1コマ送り、文字の入力中は Space で止めない）と、
# アリーナの開発用カメラ（自由カメラ・回す・動かす・近づく・機体を追う・戻す）。止めたりカメラを動かしたりしても試合の結果は変わらない。
extends "res://tests/support/test_case.gd"

const MatchSession := preload("res://core/match_session.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")
const GarageScreen := preload("res://view/garage/garage_screen.gd")
const BattleScreen := preload("res://view/arena/battle_screen.gd")
const ArenaView := preload("res://view/arena/arena_view.gd")
const Look := preload("res://view/look.gd")


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _frames(n: int) -> void:
	for i: int in n:
		await _frame()


func _main() -> Node:
	var main: Node = load("res://view/main.tscn").instantiate()
	main.use_llm = false
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _space() -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = KEY_SPACE
	k.pressed = true
	return k


func test_pause_stops_every_phase_and_steps_one_tick() -> void:
	var main: Node = _main()
	await _frame()
	check(not main.can_dev_pause(), "試合がないときは止められない")
	main.start_game(55)
	await _frame()
	main.session.finish_draft()
	await _frame()
	check(main.screen is GarageScreen, "組み立ての画面")
	# 文字の欄に入力しているときは、Space は文字として扱う
	main.screen._prompt.grab_focus()
	main._input(_space())
	check(not main.dev_paused, "プロンプトの欄に入力しているときは Space で止めない")
	main.screen._prompt.release_focus()
	main._input(_space())
	check(main.dev_paused, "Space で止まる")
	check(main.dev_pause_label.visible, "一時停止中の札が出る")
	var left: float = main.session.phase_time_left
	await _frames(5)
	check_eq(main.session.phase_time_left, left, "止めている間は組み立ての残り時間が減らない")
	main.dev_step()
	await _frames(3)
	var dt: float = 1.0 / float(main.data.rule("tick_rate"))
	check(absf(main.session.phase_time_left - (left - dt)) < 0.0001, "1コマ送りでちょうど1刻みだけ進む")
	# バトルも止まる（止めていても、出撃のシャッターは閉じて開く）
	main.session.finish_build()
	await wait_sortie(main)
	check(main.screen is BattleScreen, "バトルの画面")
	var sim: Variant = main.screen.watched_battle.sim
	var tick: int = sim.tick
	await _frames(5)
	check_eq(sim.tick, tick, "止めている間はバトルが進まない")
	check(main.screen.arena.paused, "アリーナにも止めていることが伝わる")
	check(main.screen.header.text.contains("一時停止中"), "見出しに一時停止中と出る")
	main.dev_step()
	await _frames(3)
	check_eq(sim.tick, tick + 1, "1コマ送りでバトルが1刻み進む")
	main.toggle_dev_pause()
	check(not main.dev_paused and not main.dev_pause_label.visible, "もう一度 Space（切り替え）で再開する")
	await _frames(5)
	check(sim.tick > tick + 1, "再開するとバトルが進む")
	main.set_dev_paused(true)
	main.show_title()
	check(not main.dev_paused, "タイトルに戻ると止めた状態は解ける")
	main.queue_free()
	await _frame()


## 止めたり1コマ送りしたりカメラを動かしたりしても、試合の結果は変わらない（同じ種なら同じ結果）
func test_pause_and_camera_do_not_change_results() -> void:
	var data: Variant = load("res://core/game_data.gd").new()
	data.load_dir()
	var plain := MatchSession.new(data, 909, _cpu_setup(), DefaultAgents.new())
	plain.finish_draft()
	plain.finish_build()
	plain.run_battles_to_end()
	var main: Node = _main()
	await _frame()
	main.start_game(909)
	await _frame()
	# 人間の分も CPU に任せて、ひとつ目と同じ条件にする
	main.session.players[0].is_human = false
	main.session.finish_draft()
	await _frame()
	main.session.finish_build()
	await wait_sortie(main)
	var b: Node = main.screen
	for k: int in 6:
		main.set_dev_paused(k % 2 == 0)
		main.dev_step()
		b.arena.dev_orbit(0.3, 0.1)
		b.arena.dev_pan(1.0, -2.0)
		b.arena.dev_zoom(0.8)
		b.arena.dev_track(k % 2)
		await _frames(2)
	main.set_dev_paused(false)
	main.session.run_battles_to_end()
	check_eq(JSON.stringify(main.session.history[0]["battles"]), JSON.stringify(plain.history[0]["battles"]),
		"止めたりカメラを動かしたりしても、バトルの結果は同じ")
	main.queue_free()
	await _frame()


func _cpu_setup() -> Array:
	var out: Array = []
	for i: int in 6:
		out.append({"name": "あなた" if i == 0 else "CPU%d" % i, "is_human": false})
	return out


func test_dev_camera_moves() -> void:
	var main: Node = _main()
	await _frame()
	main.start_game(56)
	await _frame()
	main.session.finish_draft()
	await _frame()
	main.session.finish_build()
	await wait_sortie(main)
	var arena: Node3D = main.screen.arena
	var cam: Camera3D = arena.camera
	check_eq(arena.camera_mode, ArenaView.CameraMode.FOLLOW, "最初はいつもの追いかけるカメラ")
	main.set_dev_paused(true)  # 機体を止めて、カメラの位置を比べやすくする
	await _frames(2)
	var before: Vector3 = cam.position
	arena.dev_free_camera()
	await _frames(2)
	check(cam.position.distance_to(before) < 0.05, "自由カメラに切り替えても位置が飛ばない")
	var d0: float = cam.position.distance_to(arena.cam_pivot)
	arena.dev_orbit(1.0, 0.2)
	await _frames(2)
	check(absf(cam.position.distance_to(arena.cam_pivot) - d0) < 0.01, "回しても見る点からの距離は変わらない")
	check(cam.position.distance_to(before) > 1.0, "回すとカメラが動く")
	arena.dev_orbit(0.0, 10.0)
	check(arena.cam_pitch <= deg_to_rad(Look.DEV_CAM_PITCH_MAX_DEG) + 0.0001, "真上より先には回らない")
	arena.dev_orbit(0.0, -10.0)
	check(arena.cam_pitch >= deg_to_rad(Look.DEV_CAM_PITCH_MIN_DEG) - 0.0001, "床より下には回らない")
	for k: int in 40:
		arena.dev_zoom(0.5)
	check_eq(arena.cam_dist, Look.DEV_CAM_DIST_MIN, "近づきすぎない")
	for k: int in 40:
		arena.dev_zoom(2.0)
	check_eq(arena.cam_dist, Look.DEV_CAM_DIST_MAX, "離れすぎない")
	var lim: float = float(main.data.rule("battle.arena.half_size")) + Look.DEV_CAM_PAN_MARGIN
	arena.dev_pan(1000.0, 1000.0)
	check(absf(arena.cam_pivot.x) <= lim + 0.001 and absf(arena.cam_pivot.z) <= lim + 0.001, "見る点はアリーナから離れすぎない")
	check(is_finite(cam.position.x) and is_finite(cam.position.y) and is_finite(cam.position.z), "カメラの位置が壊れない")
	# 機体を追う
	arena.dev_track(1)
	for k: int in 10:
		arena.sync(0.5)  # 画面なしでは1コマがとても短いので、カメラが追いつくまでの時間を直接進める
	var r: Variant = main.screen.watched_battle.sim.robots[1]
	check(Vector2(arena.cam_pivot.x, arena.cam_pivot.z).distance_to(Vector2(r.x, r.z)) < 0.5, "2つ目の機体を中心に追う")
	main.screen._dev_camera_input(_key(KEY_R))
	check_eq(arena.camera_mode, ArenaView.CameraMode.FOLLOW, "R でいつものカメラに戻る")
	main.screen._dev_camera_input(_key(KEY_1))
	check(arena.camera_mode == ArenaView.CameraMode.TRACK and arena.track_index == 0, "1 で1つ目の機体を追う")
	main.queue_free()
	await _frame()


func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k
