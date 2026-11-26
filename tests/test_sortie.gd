# 出撃のシャッターと出撃の取り消しのテスト。1人用は本物の main.tscn を画面なしで動かし、
# 通信対戦は同じプロセスの中でサーバーとクライアントを立てて確かめる。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const MatchSession := preload("res://core/match_session.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")
const GarageScreen := preload("res://view/garage/garage_screen.gd")
const BattleScreen := preload("res://view/arena/battle_screen.gd")
const TitleScreen := preload("res://view/title/title_screen.gd")
const Shutter := preload("res://view/shutter.gd")
const Look := preload("res://view/look.gd")
const GameServer := preload("res://net/game_server.gd")
const GameClient := preload("res://net/game_client.gd")
const Protocol := preload("res://net/protocol.gd")

const PORT: int = 7397


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _frame() -> void:
	await _tree().process_frame


func _wait_until(cond: Callable, sec: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(sec * 1000.0):
			return false
		await _frame()
	return true


func _data() -> GameData:
	var d := GameData.new()
	d.load_dir()
	return d


func _main() -> Node:
	var main: Node = load("res://view/main.tscn").instantiate()
	main.use_llm = false
	_tree().root.add_child(main)
	return main


## 1人用の試合を組み立ての画面まで進める
func _to_garage(main: Node, seed_value: int) -> void:
	await _frame()
	main.start_game(seed_value)
	await _frame()
	main.session.finish_draft()
	await _frame()


## 手持ちから正しい機体（フレーム1つ・武器1つ）を選んで出撃する
func _confirm_valid(main: Node) -> String:
	var g: Node = main.screen
	var me: Variant = main.session.get_player(main.human_id)
	var frame: int = -1
	var weapon: int = -1
	for p: Variant in me.hand:
		if p.kind == "frame" and frame < 0:
			frame = p.uid
		elif p.kind == "weapon" and weapon < 0:
			weapon = p.uid
	g.set_selection(frame, [weapon], [])
	g.set_prompt("突撃しろ")
	return g.confirm()


# ---- 試合（core）：出撃の取り消し ----

func test_cancel_build_in_core() -> void:
	var data := _data()
	var setup: Array = [{"name": "あなた", "is_human": true}]
	for i: int in 5:
		setup.append({"name": "CPU%d" % i, "is_human": false})
	var s := MatchSession.new(data, 4242, setup, DefaultAgents.new(false))
	s.finish_draft()
	check(not s.cancel_build(0).is_empty(), "出撃していなければ取り消せない")
	var me: Variant = s.get_player(0)
	var b: Variant = me.hand
	var frame: int = -1
	var weapon: int = -1
	for p: Variant in b:
		if p.kind == "frame" and frame < 0:
			frame = p.uid
		elif p.kind == "weapon" and weapon < 0:
			weapon = p.uid
	check_eq(s.submit_build(0, frame, [weapon], [], "穴に押し込め"), "", "出撃できる")
	check(me.done_this_phase, "出撃済みになる")
	check_eq(s.cancel_build(0), "", "出撃を取り消せる")
	check(not me.done_this_phase, "取り消すと出撃済みでなくなる")
	check(me.build != null and me.build.frame.uid == frame and me.prompt == "穴に押し込め", "選んだ機体とプロンプトは残る")
	s.finish_build()
	check_eq(s.phase, MatchSession.PHASE_BATTLE, "締め切るとバトルに進む")
	check_eq(s.battle_of(0).prompts[0 if s.battle_of(0).a == 0 else 1], "穴に押し込め", "取り消したまま締め切ると、その機体とプロンプトで出撃する")
	check(not s.cancel_build(0).is_empty(), "バトルに移ったあとは取り消せない")


# ---- 1人用 ----

func test_sortie_closes_shutter_only_for_a_valid_build() -> void:
	var main: Node = _main()
	await _to_garage(main, 101)
	check(main.screen is GarageScreen, "組み立ての画面")
	check(main.shutter.is_open() and not main.shutter.visible, "最初はシャッターが開いている")
	main.screen.set_selection(-1, [], [])
	check(not main.screen.confirm().is_empty(), "フレームがないと出撃できない")
	await _frame()
	check(main.shutter.is_open() and not main.sortie_active, "出撃できないときはシャッターが閉じない")
	check_eq(main.session.phase, MatchSession.PHASE_BUILD, "出撃できないときは組み立てのまま")
	check_eq(_confirm_valid(main), "", "正しい機体なら出撃できる")
	check(main.sortie_active and main.shutter.state == Shutter.State.CLOSING, "出撃を押すとシャッターが閉じ始める")
	check(not main.shutter.cancel_button.visible, "1人用ではキャンセルボタンを出さない")
	main.queue_free()
	await _frame()


func test_battle_waits_until_shutter_opens() -> void:
	var main: Node = _main()
	await _to_garage(main, 202)
	check_eq(_confirm_valid(main), "", "出撃できる")
	check_eq(main.session.phase, MatchSession.PHASE_BATTLE, "1人用では出撃するとすぐバトルの段階に移る")
	var sim: Variant = main.session.battle_of(0).sim
	var saw_closed: bool = false
	var garage_until_closed: bool = true
	var frozen: bool = true
	var shook: bool = false
	var held: float = 0.0
	var t0: int = Time.get_ticks_msec()
	while main.sortie_active and Time.get_ticks_msec() - t0 < 10000:
		if sim.now() != 0.0:
			frozen = false
		if main.shutter.shaking:
			shook = shook or main.shutter.shake_offset() != Vector2.ZERO
		held = maxf(held, main.shutter.closed_time)
		if main.shutter.is_closed():
			saw_closed = true
		elif not saw_closed and not (main.screen is GarageScreen):
			garage_until_closed = false
		check(not main.shutter.cancel_button.visible, "1人用ではキャンセルボタンを出さない")
		await _frame()
	check(not main.sortie_active, "シャッターが開ききる")
	check(saw_closed, "シャッターが閉じきる")
	check(held >= Look.SHUTTER_CLOSED_HOLD_SEC - 0.05, "閉じきってから少し閉じたままでいる（%.2f秒）" % held)
	check(shook, "閉じきると揺れる")
	check(garage_until_closed, "閉じきるまでは組み立ての画面のまま")
	check(frozen, "シャッターが開ききるまでバトルの時間が進まない")
	check(main.screen is BattleScreen, "開いたらバトルの画面")
	check_eq(main.screen.position, Vector2.ZERO, "揺れが終わると画面は元の位置")
	var opened: bool = await _wait_until(func() -> bool: return sim.now() > 0.0, 2.0)
	check(opened, "開ききるとバトルの時間が進む")
	# そのまま最後まで進め、試合が必ず決着する
	for k: int in 200:
		if main.session.is_finished():
			break
		match main.session.phase:
			"build": main.session.finish_build()
			"battle": main.session.run_battles_to_end()
			"round_result": main.session.finish_round_result()
			"loot": main.session.finish_loot()
		await wait_sortie(main)
	check(main.session.is_finished(), "シャッターがあっても試合は最後まで決着する")
	main.queue_free()
	await _frame()


func test_timeout_auto_sortie_goes_through_shutter() -> void:
	var main: Node = _main()
	await _to_garage(main, 303)
	main.session.phase_time_left = 0.001  # 出撃を押さずに制限時間切れにする
	await _frame()
	check_eq(main.session.phase, MatchSession.PHASE_BATTLE, "制限時間切れで自動で出撃する")
	check(main.sortie_active and not main.shutter.is_open(), "自動の出撃でもシャッターが閉じる")
	check(main.screen is GarageScreen, "閉じきるまでは組み立ての画面のまま")
	var sim: Variant = main.session.battle_of(0).sim
	var frozen: bool = true
	var t0: int = Time.get_ticks_msec()
	while main.sortie_active and Time.get_ticks_msec() - t0 < 10000:
		frozen = frozen and sim.now() == 0.0
		await _frame()
	check(frozen, "自動の出撃でも、開ききるまでバトルの時間が進まない")
	check(main.screen is BattleScreen, "シャッターを通ってバトルの画面に移る")
	main.queue_free()
	await _frame()


func test_same_seed_same_result_with_or_without_shutter() -> void:
	var data := _data()
	var setup: Array = []
	for i: int in 6:
		setup.append({"name": "あなた" if i == 0 else "CPU%d" % i, "is_human": false})
	var plain := MatchSession.new(data, 515, setup, DefaultAgents.new(false))
	plain.finish_draft()
	plain.finish_build()
	plain.run_battles_to_end()
	var main: Node = _main()
	await _frame()
	main.start_game(515)
	await _frame()
	main.session.players[0].is_human = false  # 人間の分も CPU に任せて、ひとつ目と同じ条件にする
	main.session.finish_draft()
	await _frame()
	main.session.finish_build()
	await _frame()
	check(main.sortie_active, "シャッターを通る")
	await wait_sortie(main)
	for k: int in 20:
		await _frame()  # 実時間でいくらか進めてから、残りを一気に進める
	main.session.run_battles_to_end()
	check_eq(JSON.stringify(main.session.history[0]["battles"]), JSON.stringify(plain.history[0]["battles"]),
		"シャッターがあってもなくても、同じ種ならバトルの結果は同じ")
	main.queue_free()
	await _frame()


func test_shutter_never_left_behind() -> void:
	var main: Node = _main()
	await _to_garage(main, 404)
	_confirm_valid(main)
	await _frame()
	check(main.sortie_active, "シャッターが動いている")
	main.session.run_battles_to_end()  # 「最後まで飛ばす」と同じ
	await _frame()
	await _frame()
	check(not main.sortie_active and main.shutter.is_open() and not main.shutter.visible, "バトルを飛ばすとシャッターが片付く")
	# 次のラウンドの出撃中にタイトルへ戻る
	main.session.finish_round_result()
	main.session.finish_loot()
	await _frame()
	check(main.screen is GarageScreen, "次のラウンドの組み立て")
	_confirm_valid(main)
	await _frame()
	check(main.sortie_active, "またシャッターが動く")
	main.show_title()
	await _frame()
	check(main.screen is TitleScreen, "タイトルへ戻る")
	check(not main.sortie_active and main.shutter.is_open() and not main.shutter.visible, "タイトルへ戻るとシャッターが片付く")
	check(main.screen.position == Vector2.ZERO, "画面の揺れも残らない")
	main.queue_free()
	await _frame()


func test_shutter_timings_fit_in_online_start_delay() -> void:
	var data := _data()
	var total: float = Look.SHUTTER_CLOSE_SEC + Look.SHUTTER_SHAKE_SEC + Look.SHUTTER_OPEN_SEC
	var delay: float = float(data.rule("online.battle_start_delay_sec"))
	check(total < delay, "閉じる＋揺れ＋開く（%.2f秒）が、通信対戦のバトル開始までの待ちより短い" % total)
	check(absf((delay - total) - Look.SHUTTER_CLOSED_HOLD_SEC) < 0.15,
		"通信対戦で閉じたままの時間（%.2f秒）が1人用（%.2f秒）とほぼ同じ" % [delay - total, Look.SHUTTER_CLOSED_HOLD_SEC])


# ---- 通信対戦 ----

func _setup_online(port: int) -> Array:
	var data := _data()
	var server := GameServer.new()
	server.name = "SortieServer%d" % port
	server.time_scale = 1.0  # 開始までの待ちを実時間で確かめる
	_tree().root.add_child(server)
	check_eq(server.start(data, port), OK, "サーバーが待ち受けを始める")
	var clients: Array = []
	for n: String in ["あおい", "みどり"]:
		var c := GameClient.new()
		c.name = "SortieClient_%s_%d" % [n, port]
		_tree().root.add_child(c)
		c.connect_to(data, DefaultAgents.new(false), "127.0.0.1", port, n)
		clients.append(c)
	return [server, clients[0], clients[1]]


func _teardown(nodes: Array) -> void:
	for i: int in range(nodes.size() - 1, -1, -1):
		var n: Node = nodes[i]
		if is_instance_valid(n):
			if n.has_method("close"):
				n.close()
			n.queue_free()
	await _frame()
	await _frame()


func _submit_online(c: Variant) -> String:
	var s: Variant = c.session
	var me: Variant = s.get_player(s.my_id)
	var frame: int = -1
	var weapon: int = -1
	for p: Variant in me.hand:
		if p.kind == "frame" and frame < 0:
			frame = p.uid
		elif p.kind == "weapon" and weapon < 0:
			weapon = p.uid
	return s.submit_build(s.my_id, frame, [weapon], [], "突撃しろ")


func test_online_cancel_and_start_delay() -> void:
	var nodes: Array = _setup_online(PORT)
	var server: Variant = nodes[0]
	var c1: Variant = nodes[1]
	var c2: Variant = nodes[2]
	await _wait_until(func() -> bool: return c1.lobby.size() == 2, 5.0)
	c1.request_start()
	var drafting: bool = await _wait_until(func() -> bool:
		return c1.session != null and c2.session != null and c1.session.phase == "draft" and c2.session.phase == "draft", 5.0)
	check(drafting, "パーツ選びが始まる")
	if not drafting:
		await _teardown(nodes)
		return
	for c: Variant in [c1, c2]:
		var picks: Dictionary = {}
		for kind: String in GameData.KINDS:
			picks[kind] = c.session.draft_offer[kind][0].uid
		c.session.draft_pick(c.session.my_id, picks)
	var building: bool = await _wait_until(func() -> bool:
		return c1.session.phase == "build" and c2.session.phase == "build" and not c1.session.get_player(c1.session.my_id).hand.is_empty(), 5.0)
	check(building, "組み立てが始まる")
	if not building:
		await _teardown(nodes)
		return
	var p1: int = c1.session.my_id
	# 1人目が出撃して、取り消す
	check_eq(_submit_online(c1), "", "1人目が出撃できる")
	var done1: bool = await _wait_until(func() -> bool: return server.session.get_player(p1).done_this_phase, 3.0)
	check(done1, "サーバーで1人目が出撃済みになる")
	check_eq(c1.session.cancel_build(p1), "", "取り消しを送れる")
	var undone: bool = await _wait_until(func() -> bool: return not server.session.get_player(p1).done_this_phase, 3.0)
	check(undone, "取り消すと、サーバーでそのプレイヤーが出撃済みでなくなる")
	# もう1人が出撃しても、取り消した人を待つ
	check_eq(_submit_online(c2), "", "2人目が出撃できる")
	var p2: int = c2.session.my_id
	await _wait_until(func() -> bool: return server.session.get_player(p2).done_this_phase, 3.0)
	for k: int in 10:
		await _frame()
	check_eq(server.session.phase, MatchSession.PHASE_BUILD, "取り消した人がいる間はバトルに進まない")
	# 1人目が出撃し直すと全員が揃い、決まった秒数のあとにバトルが始まる
	check_eq(_submit_online(c1), "", "出撃し直せる")
	var to_battle: bool = await _wait_until(func() -> bool: return server.session.phase == MatchSession.PHASE_BATTLE, 3.0)
	check(to_battle, "全員が揃うとバトルの段階に移る")
	if not to_battle:
		await _teardown(nodes)
		return
	var delay: float = float(server.data.rule("online.battle_start_delay_sec"))
	var t_battle: int = Time.get_ticks_msec()
	var got_left: bool = await _wait_until(func() -> bool:
		return c1.session.phase == "battle" and c1.session.battle_start_left > 0.0, 3.0)
	check(got_left, "クライアントに開始までの残り秒数が届く")
	check(c1.session.battle_start_left <= delay + 0.01, "残り秒数は決まった秒数以下")
	# 待っている間に取り消しを送っても、もうバトルに移っているので無視される
	c1.send(Protocol.CANCEL_BUILD, {})
	var frozen: bool = true
	while Time.get_ticks_msec() - t_battle < int((delay - 0.3) * 1000.0):
		for bt: Variant in server.session.battles:
			if bt.sim.now() != 0.0:
				frozen = false
		await _frame()
	check(frozen, "全員が揃ってから決まった秒数が過ぎるまで、バトルの時間が進まない")
	check_eq(server.session.phase, MatchSession.PHASE_BATTLE, "バトルに移ったあとの取り消しは無視される")
	check(c1.last_op_error.is_empty(), "遅れた取り消しにエラーは返さない")
	var started: bool = await _wait_until(func() -> bool: return server.session.battles[0].sim.now() > 0.0, 2.0)
	check(started, "決まった秒数が過ぎるとバトルが進む")
	check_eq(server.session.phase, MatchSession.PHASE_BATTLE, "そのままバトルが続く")
	await _teardown(nodes)


func test_online_screen_shows_wait_and_cancel() -> void:
	# 本物の画面（main.tscn）をクライアントにして、待っている間のシャッターとキャンセルを確かめる
	var data := _data()
	var server := GameServer.new()
	server.name = "SortieServerUi"
	server.time_scale = 1.0
	_tree().root.add_child(server)
	server.start(data, PORT + 1)
	var other := GameClient.new()  # 出撃しないもう1人（この人を待つ）
	other.name = "SortieOther"
	var main: Node = _main()
	await _frame()
	check_eq(main.start_online("127.0.0.1", PORT + 1, "あなた", false), "", "画面からつなげる")
	await _wait_until(func() -> bool: return main.online.status == GameClient.Status.LOBBY, 5.0)
	_tree().root.add_child(other)
	other.connect_to(data, DefaultAgents.new(false), "127.0.0.1", PORT + 1, "まつ")
	await _wait_until(func() -> bool: return other.status == GameClient.Status.LOBBY and main.online.lobby.size() == 2, 5.0)
	main.online.request_start()
	var drafting: bool = await _wait_until(func() -> bool:
		return main.session != null and main.screen.get_script().resource_path.ends_with("draft_screen.gd") \
			and other.session != null, 5.0)
	check(drafting, "パーツ選びの画面")
	if not drafting:
		await _teardown([server, other, main])
		return
	for kind: String in GameData.KINDS:
		main.screen.select(kind, main.session.draft_offer[kind][0].uid)
	main.screen.confirm()
	var picks: Dictionary = {}
	for kind: String in GameData.KINDS:
		picks[kind] = other.session.draft_offer[kind][0].uid
	other.session.draft_pick(other.session.my_id, picks)
	var in_garage: bool = await _wait_until(func() -> bool:
		return main.screen is GarageScreen and not main.session.get_player(main.human_id).hand.is_empty(), 5.0)
	check(in_garage, "組み立ての画面")
	if not in_garage:
		await _teardown([server, other, main])
		return
	check_eq(_confirm_valid(main), "", "出撃できる")
	check(main.sortie_active, "シャッターが閉じ始める")
	var waiting: bool = await _wait_until(func() -> bool: return main.shutter.cancel_button.visible, 3.0)
	check(waiting, "閉じきると、ほかのプレイヤーを待つ間はキャンセルボタンが出る")
	check(main.shutter.message.text.contains("ほかのプレイヤーを待っています"), "待っていることがシャッターに出る")
	var me_id: int = main.human_id
	await _wait_until(func() -> bool: return server.session.get_player(me_id).done_this_phase, 3.0)
	main.shutter.cancel_button.pressed.emit()
	check(not main.sortie_active, "キャンセルするとシャッターの一連が終わる")
	var reopened: bool = await _wait_until(func() -> bool: return main.shutter.is_open(), 3.0)
	check(reopened, "キャンセルするとシャッターが開く")
	check(main.screen is GarageScreen, "組み立ての画面に戻る")
	var undone: bool = await _wait_until(func() -> bool: return not server.session.get_player(me_id).done_this_phase, 3.0)
	check(undone, "サーバーで出撃済みでなくなる")
	check_eq(main.session.get_player(me_id).prompt, "突撃しろ", "選んだプロンプトはそのまま")
	# もう一度出撃し、もう1人も出撃すると、シャッターを通ってバトルへ
	check_eq(main.screen.confirm(), "", "もう一度出撃できる")
	check(main.sortie_active, "また閉じる")
	await _wait_until(func() -> bool: return other.session.phase == "build", 3.0)
	check_eq(_submit_online(other), "", "もう1人も出撃する")
	var moved: bool = await _wait_until(func() -> bool: return main.session.phase == "battle", 3.0)
	check(moved, "バトルの段階に移る")
	await _wait_until(func() -> bool: return main.shutter.is_closed() or main.shutter.state == Shutter.State.OPENING or main.shutter.is_open(), 3.0)
	check(not main.shutter.cancel_button.visible, "バトルに移ったらキャンセルボタンを消す")
	var done: bool = await _wait_until(func() -> bool: return not main.sortie_active, 5.0)
	check(done, "シャッターが開ききる")
	check(main.screen is BattleScreen, "バトルの画面")
	# 開ききった時刻と、サーバーがバトルを始める時刻がずれない
	var sim_now: float = server.session.battles[0].sim.now()
	var hold_left: float = server._start_hold
	check(sim_now < 0.25 and hold_left < 0.25,
		"開ききったのはバトルの開始とほぼ同時（サーバーの残りの待ち %.2f 秒、バトルの時間 %.2f 秒）" % [hold_left, sim_now])
	main.show_title()
	await _frame()
	check(not main.sortie_active and main.shutter.is_open(), "抜けるとシャッターは残らない")
	await _teardown([server, other, main])
