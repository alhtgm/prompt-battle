# 通信対戦のテスト。同じプロセスの中でサーバーとクライアント2つを動かし、PC内の通信（127.0.0.1）でつないで試合を最後まで回す。
# サーバーの時間は速めて（time_scale）、締め切りを待つ時間を縮める。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const GameServer := preload("res://net/game_server.gd")
const GameClient := preload("res://net/game_client.gd")
const Protocol := preload("res://net/protocol.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")

const PORT: int = 7391
const SCALE: float = 60.0
## 1つの試合を待つ上限（実時間の秒）
const MATCH_TIMEOUT_SEC: float = 90.0


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _frame() -> void:
	await _tree().process_frame


## cond が true になるまで待つ（上限 sec 秒）。なったら true
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


func _setup(port: int) -> Array:
	var data := _data()
	var server := GameServer.new()
	server.name = "TestServer%d" % port
	server.time_scale = SCALE
	_tree().root.add_child(server)
	check_eq(server.start(data, port), OK, "サーバーが待ち受けを始める")
	var clients: Array = []
	for n: String in ["あおい", "みどり"]:
		var c := GameClient.new()
		c.name = "TestClient_%s_%d" % [n, port]
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


func test_protocol_roundtrip_and_rejects_garbage() -> void:
	var msg: Dictionary = Protocol.decode(Protocol.encode(Protocol.HELLO, {"name": "a", "version": 1}))
	check_eq(msg.get("type"), Protocol.HELLO, "種類が戻る")
	check_eq(msg.get("name"), "a", "中身が戻る")
	check(Protocol.decode(PackedByteArray([1, 2, 3])).is_empty(), "壊れたバイト列は空の辞書になる")
	check(Protocol.decode(var_to_bytes([1, 2])).is_empty(), "辞書でなければ空の辞書になる")


func test_two_players_play_a_full_online_match() -> void:
	var nodes: Array = _setup(PORT)
	var server: Variant = nodes[0]
	var c1: Variant = nodes[1]
	var c2: Variant = nodes[2]
	var joined: bool = await _wait_until(func() -> bool:
		return c1.status == GameClient.Status.LOBBY and c2.status == GameClient.Status.LOBBY and c1.lobby.size() == 2, 5.0)
	check(joined, "2人とも待合室に入る")
	check(c1.is_leader and not c2.is_leader, "最初に入った人だけが開始できる")
	c2.request_start()
	for k: int in 10:
		await _frame()
	check(server.session == null, "開始できない人の開始は無視される")
	c1.request_start()
	var started: bool = await _wait_until(func() -> bool: return c1.session != null and c2.session != null, 5.0)
	check(started, "開始すると2人に試合の状態が届く")
	if not started:
		await _teardown(nodes)
		return
	var humans: int = 0
	for p: Variant in server.session.players:
		humans += 1 if p.is_human else 0
	check(server.session.players.size() == 6 and humans == 2, "2人＋CPU4人の6人戦になる")

	var saw: Dictionary = {}
	var hidden_ok: bool = true
	var final_places: Array = [[], []]
	var answered: int = 0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(MATCH_TIMEOUT_SEC * 1000.0):
		var total: int = 0
		for b: Variant in server._brains.values():
			total += b.received
		answered = maxi(answered, total)  # 試合が終わると片付けられるので、試合中に数える
		var s: Variant = c1.session
		if s == null:
			break  # 待合室に戻った
		saw[s.phase] = true
		var me: Variant = s.get_player(s.my_id)
		match s.phase:
			"draft":
				if not me.done_this_phase:
					var picks: Dictionary = {}
					for kind: String in GameData.KINDS:
						picks[kind] = s.draft_offer[kind][0].uid
					check_eq(s.draft_pick(s.my_id, picks), "", "パーツ選びを送れる")
			"build":
				if me.alive and not me.done_this_phase and not me.hand.is_empty():
					var frame: int = -1
					var weapons: Array = []
					for part: Variant in me.hand:
						if part.kind == "frame" and frame < 0:
							frame = part.uid
						elif part.kind == "weapon" and weapons.is_empty():
							weapons.append(part.uid)
					check_eq(s.submit_build(s.my_id, frame, weapons, [], "突撃しろ"), "", "機体とプロンプトを送れる")
			"battle":
				# 生き残っている間は、自分以外のプロンプトが届いていない
				for bt: Variant in s.battles:
					for side: int in 2:
						var id: int = bt.a if side == 0 else bt.b
						if me.alive and id != s.my_id and str(bt.prompts[side]) != "":
							if hidden_ok:
								print("    [漏れ] round=%d my=%d a=%d b=%d side=%d prompt=%s battles=%d" % [
									s.round_no, s.my_id, bt.a, bt.b, side, bt.prompts[side], s.battles.size()])
							hidden_ok = false
			"loot":
				if me.alive and not me.done_this_phase and not me.perk_choices.is_empty():
					check_eq(s.choose_perk(s.my_id, me.perk_choices[0]), "", "パークを送れる")
			"finished":
				for k: int in 2:
					var cs: Variant = nodes[k + 1].session
					if cs != null:
						var places: Array = []
						for p: Variant in cs.players:
							places.append(p.place)
						final_places[k] = places
		await _frame()
	for phase: String in ["draft", "build", "battle", "round_result", "loot", "finished"]:
		check(saw.has(phase), "クライアントに段階 %s が届く" % phase)
	check(hidden_ok, "生き残っている間は相手のプロンプトが届かない")
	check(not final_places[0].is_empty() and same(final_places[0], final_places[1]), "2人に同じ最終順位が届く")
	var sorted_places: Array = final_places[0].duplicate()
	sorted_places.sort()
	check_eq(sorted_places, [1, 2, 3, 4, 5, 6], "順位が 1〜6 に1人ずつ")
	check(answered > 0, "クライアントの頭脳の答えがサーバーに届いた（%d 回）" % answered)
	var back: bool = await _wait_until(func() -> bool: return server.session == null and c1.session == null, 5.0)
	check(back, "最終順位のあとは待合室に戻る")
	await _teardown(nodes)


func test_game_screens_follow_an_online_match() -> void:
	# 本物の画面（main.tscn）をクライアントにして、画面の操作で最後まで進める
	var data := _data()
	var server := GameServer.new()
	server.name = "TestServerUi"
	server.time_scale = SCALE
	_tree().root.add_child(server)
	server.start(data, PORT + 2)
	var main: Node = load("res://view/main.tscn").instantiate()
	main.use_llm = false
	_tree().root.add_child(main)
	await _frame()
	check_eq(main.start_online("127.0.0.1", PORT + 2, "あなた", false), "", "画面からつなげる")
	var in_lobby: bool = await _wait_until(func() -> bool:
		return main.online.status == GameClient.Status.LOBBY and main.screen.get_script() == preload("res://view/online/online_screen.gd"), 5.0)
	check(in_lobby, "待合室の画面が出る")
	main.screen.start()
	var screens: Dictionary = {}
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(MATCH_TIMEOUT_SEC * 1000.0):
		var sc: Node = main.screen
		var path: String = sc.get_script().resource_path.get_file() if sc != null else ""
		screens[path] = true
		if main.session != null:
			var me: Variant = main.session.get_player(main.human_id)
			if me != null and me.alive and not me.done_this_phase:
				match path:
					"draft_screen.gd":
						for kind: String in GameData.KINDS:
							sc.select(kind, main.session.draft_offer[kind][0].uid)
						sc.confirm()
					"garage_screen.gd":
						sc.set_prompt("相手の後ろに回り込んで攻めろ")
						sc.confirm()
					"loot_screen.gd":
						if not me.perk_choices.is_empty():
							sc.pick(me.perk_choices[0])
		if path == "final_screen.gd":
			break
		await _frame()
	for f: String in ["draft_screen.gd", "garage_screen.gd", "battle_screen.gd", "round_result_screen.gd", "final_screen.gd"]:
		check(screens.has(f), "通信対戦でも %s が出る" % f)
	main.show_title()
	await _frame()
	check(main.online == null, "タイトルに戻ると抜ける")
	await _teardown([server, main])


func test_disconnected_player_is_taken_over_by_cpu() -> void:
	var nodes: Array = _setup(PORT + 1)
	var server: Variant = nodes[0]
	var c1: Variant = nodes[1]
	var c2: Variant = nodes[2]
	await _wait_until(func() -> bool: return c1.lobby.size() == 2, 5.0)
	c1.request_start()
	await _wait_until(func() -> bool: return c2.session != null and c2.session.phase == "build", 10.0)
	var pid: int = c2.session.my_id
	c2.close()
	var handed: bool = await _wait_until(func() -> bool:
		return server.session != null and not server.session.get_player(pid).is_human, 5.0)
	check(handed, "接続が切れた人はCPUが引き継ぐ")
	var finished: bool = await _wait_until(func() -> bool:
		return c1.session != null and c1.session.phase == "finished", MATCH_TIMEOUT_SEC)
	check(finished, "1人抜けても試合は最後まで進む")
	await _teardown(nodes)
