# 通信対戦のサーバー。画面なしで動き、試合（MatchSession）を計算して、各クライアントに見てよい分だけの状態を送る。
# 待合室（最初に入った人が開始できる）→ 試合 → 最終順位 → 待合室、を繰り返す。足りない人数はCPUで埋める。
# 接続が切れた人は、その機体とプロンプトのままCPUが引き継ぐ。同じ名前で入り直せば操作を取り戻せる。
extends Node

const GameData := preload("res://core/game_data.gd")
const MatchSession := preload("res://core/match_session.gd")
const Protocol := preload("res://net/protocol.gd")
const NetAgents := preload("res://net/net_agents.gd")
const RemoteBrain := preload("res://net/remote_brain.gd")

const MAX_NAME: int = 16

var data: GameData
## サーバーの時間の進み方（テスト用。1 が実時間）
var time_scale: float = 1.0
var session: MatchSession = null
## 待合室の人：{peer, name}（入った順。先頭が開始できる人）
var lobby: Array[Dictionary] = []
## 試合中の対応：プレイヤーID ↔ 接続番号（切れていれば 0）
var peer_of: Dictionary = {}
var player_of: Dictionary = {}
var last_error: String = ""

var _mp: SceneMultiplayer
var _peer: ENetMultiplayerPeer
var _online: Dictionary = {}
var _brains: Dictionary = {}
var _next_key: int = 1
var _timer: float = 0.0
var _shown_phase: String = ""
var _shown_round: int = -1
var _state_accum: float = 0.0
var _frame_accum: float = 0.0
var _last_sent: Dictionary = {}


## 待ち受けを始める。問題がなければ OK
func start(game_data: GameData, port: int) -> Error:
	data = game_data
	_online = data.rules["online"]
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_server(port, int(data.rule("players")))
	if err != OK:
		last_error = "ポート %d で待ち受けられない（%d）" % [port, err]
		return err
	_mp = SceneMultiplayer.new()
	_mp.multiplayer_peer = _peer
	_mp.peer_connected.connect(_on_connected)
	_mp.peer_disconnected.connect(_on_disconnected)
	_mp.peer_packet.connect(_on_packet)
	get_tree().set_multiplayer(_mp, get_path())
	return OK


func stop() -> void:
	if _peer != null:
		_peer.close()


func _exit_tree() -> void:
	stop()


# ---- 遠隔の頭脳から呼ばれる ----

func is_player_connected(player_id: int) -> bool:
	return int(peer_of.get(player_id, 0)) > 0


func create_remote_brain(player_id: int, fallback: RefCounted) -> RefCounted:
	var b := RemoteBrain.new(self, player_id, _next_key, fallback)
	_brains[_next_key] = b
	_next_key += 1
	return b


func send_brain_begin(player_id: int, key: int, prompt: String, build: Dictionary) -> void:
	_send(int(peer_of.get(player_id, 0)), Protocol.BRAIN_BEGIN,
		{"key": key, "round_no": session.round_no, "prompt": prompt, "build": build})


func send_brain_request(player_id: int, key: int, obs: Dictionary) -> void:
	_send(int(peer_of.get(player_id, 0)), Protocol.BRAIN_REQUEST, {"key": key, "obs": obs})


# ---- 接続 ----

func _on_connected(_peer_id: int) -> void:
	pass  # HELLO を待つ


func _on_disconnected(peer_id: int) -> void:
	for i: int in range(lobby.size() - 1, -1, -1):
		if int(lobby[i]["peer"]) == peer_id:
			lobby.remove_at(i)
	if player_of.has(peer_id):
		var pid: int = player_of[peer_id]
		player_of.erase(peer_id)
		peer_of[pid] = 0
		if session != null:
			session.get_player(pid).is_human = false  # CPUが引き継ぐ
			if _connected_count() == 0:
				_back_to_lobby()  # 人間がいなくなったら試合を終える
	_broadcast_lobby()


func _on_packet(peer_id: int, packet: PackedByteArray) -> void:
	var msg: Dictionary = Protocol.decode(packet)
	match str(msg.get("type", "")):
		Protocol.HELLO:
			_on_hello(peer_id, msg)
		Protocol.START:
			if session == null and not lobby.is_empty() and int(lobby[0]["peer"]) == peer_id:
				_start_match()
		Protocol.DRAFT_PICK:
			_op(peer_id, func(pid: int) -> String: return session.draft_pick(pid, _dict(msg.get("picks"))))
		Protocol.SUBMIT_BUILD:
			_op(peer_id, func(pid: int) -> String:
				return session.submit_build(pid, int(msg.get("frame", -1)), _arr(msg.get("weapons")),
					_arr(msg.get("skills")), str(msg.get("prompt", ""))))
		Protocol.CHOOSE_PERK:
			_op(peer_id, func(pid: int) -> String: return session.choose_perk(pid, str(msg.get("perk", ""))))
		Protocol.BRAIN_ANSWER:
			var b: Variant = _brains.get(int(msg.get("key", 0)))
			if b != null and player_of.get(peer_id, -1) == b.player_id and msg.get("answer") is Dictionary:
				b.deliver(msg["answer"])


func _on_hello(peer_id: int, msg: Dictionary) -> void:
	if int(msg.get("version", 0)) != Protocol.VERSION:
		_reject(peer_id, "ゲームの版が違う（サーバー %d / あなた %d）" % [Protocol.VERSION, int(msg.get("version", 0))])
		return
	var name: String = str(msg.get("name", "")).strip_edges().left(MAX_NAME)
	if name.is_empty():
		name = "プレイヤー"
	if session != null:
		# 試合中：同じ名前で切れていた人なら、その席に戻す
		for p: Variant in session.players:
			if p.name == name and peer_of.has(p.id) and int(peer_of[p.id]) == 0 and p.alive:
				peer_of[p.id] = peer_id
				player_of[peer_id] = p.id
				p.is_human = true
				_send(peer_id, Protocol.WELCOME, {"name": name})
				_last_sent.erase(peer_id)
				return
		_reject(peer_id, "試合中なので入れない")
		return
	if lobby.size() >= int(data.rule("players")):
		_reject(peer_id, "満員")
		return
	for e: Dictionary in lobby:
		if e["name"] == name:
			name = "%s%d" % [name, lobby.size() + 1]
	lobby.append({"peer": peer_id, "name": name})
	_send(peer_id, Protocol.WELCOME, {"name": name})
	_broadcast_lobby()


func _reject(peer_id: int, reason: String) -> void:
	_send(peer_id, Protocol.REJECT, {"reason": reason})
	_peer.get_peer(peer_id).peer_disconnect_later()


func _op(peer_id: int, action: Callable) -> void:
	if session == null or not player_of.has(peer_id):
		return
	var err: String = action.call(int(player_of[peer_id]))
	if not err.is_empty():
		_send(peer_id, Protocol.OP_ERROR, {"error": err})
	_advance_if_all_done()
	_last_sent.erase(peer_id)  # 操作の結果をすぐ返す


# ---- 試合の進行 ----

func _start_match() -> void:
	var setup: Array = []
	for e: Dictionary in lobby:
		setup.append({"name": e["name"], "is_human": true})
	var cpu: int = 1
	while setup.size() < int(data.rule("players")):
		setup.append({"name": "CPU%d" % cpu, "is_human": false})
		cpu += 1
	peer_of.clear()
	player_of.clear()
	for i: int in lobby.size():
		peer_of[i] = int(lobby[i]["peer"])
		player_of[int(lobby[i]["peer"])] = i
	_brains.clear()
	session = MatchSession.new(data, Time.get_ticks_usec() % 1000000 + 1, setup, NetAgents.new(self))
	_shown_phase = ""
	_last_sent.clear()
	_broadcast_lobby()


func _back_to_lobby() -> void:
	session = null
	peer_of.clear()
	player_of.clear()
	_brains.clear()
	_last_sent.clear()
	_broadcast_lobby()


func _process(delta: float) -> void:
	if session == null:
		return
	var d: float = delta * time_scale
	_on_phase_change()
	match session.phase:
		MatchSession.PHASE_DRAFT:
			_timer -= d
			if _timer <= 0.0:
				session.finish_draft()
		MatchSession.PHASE_BUILD, MatchSession.PHASE_BATTLE:
			session.update(d)
		MatchSession.PHASE_ROUND_RESULT:
			_timer -= d
			if _timer <= 0.0:
				session.finish_round_result()
		MatchSession.PHASE_LOOT:
			_timer -= d
			if _timer <= 0.0:
				session.finish_loot()
		MatchSession.PHASE_FINISHED:
			_timer -= d
			if _timer <= 0.0:
				_send_states(true)
				_back_to_lobby()
				return
	_on_phase_change()
	_state_accum += delta
	_frame_accum += delta
	if _state_accum >= 1.0 / float(_online["state_send_hz"]):
		_state_accum = 0.0
		_send_states(false)
	if session.phase == MatchSession.PHASE_BATTLE and _frame_accum >= 1.0 / float(_online["frame_send_hz"]):
		_frame_accum = 0.0
		_broadcast(Protocol.FRAME, Protocol.battle_frame(session, int(_online["frame_log_entries"])))


## 段階が変わったら締め切りの時間を決め、すぐに状態を送る
func _on_phase_change() -> void:
	if session.phase == _shown_phase and session.round_no == _shown_round:
		return
	_shown_phase = session.phase
	_shown_round = session.round_no
	match session.phase:
		MatchSession.PHASE_DRAFT: _timer = float(_online["draft_time_limit_sec"])
		MatchSession.PHASE_ROUND_RESULT: _timer = float(_online["result_view_sec"])
		MatchSession.PHASE_LOOT: _timer = float(_online["perk_time_limit_sec"])
		MatchSession.PHASE_FINISHED: _timer = float(_online["final_view_sec"])
	_send_states(true)
	if session.phase == MatchSession.PHASE_BATTLE:
		_broadcast(Protocol.FRAME, Protocol.battle_frame(session, int(_online["frame_log_entries"])))


## つながっている人間が全員操作し終えたら、締め切りを待たずに進める
func _advance_if_all_done() -> void:
	var waiting: bool = false
	for pid: Variant in peer_of:
		var p: Variant = session.get_player(int(pid))
		var needs: bool = p.alive or session.phase == MatchSession.PHASE_DRAFT
		if int(peer_of[pid]) > 0 and needs and not p.done_this_phase:
			waiting = true
	if waiting:
		return
	match session.phase:
		MatchSession.PHASE_DRAFT: session.finish_draft()
		MatchSession.PHASE_BUILD: session.finish_build()
		MatchSession.PHASE_LOOT: session.finish_loot()
	_on_phase_change()


func _time_left() -> float:
	if session.phase == MatchSession.PHASE_BUILD:
		return session.phase_time_left / time_scale
	if session.phase == MatchSession.PHASE_BATTLE:
		return 0.0
	return _timer / time_scale


## 各クライアントに、その人から見える試合の状態を送る（変わっていなければ送らない）
func _send_states(force: bool) -> void:
	for pid: Variant in peer_of:
		var peer_id: int = int(peer_of[pid])
		if peer_id <= 0:
			continue
		var st: Dictionary = Protocol.session_state(session, int(pid), {"time_left": _time_left()})
		var bytes: PackedByteArray = Protocol.encode(Protocol.STATE, st)
		var h: int = hash(bytes)
		if force or _last_sent.get(peer_id, 0) != h:
			_last_sent[peer_id] = h
			_mp.send_bytes(bytes, peer_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func _broadcast_lobby() -> void:
	var names: Array = []
	for e: Dictionary in lobby:
		names.append(e["name"])
	for i: int in lobby.size():
		_send(int(lobby[i]["peer"]), Protocol.LOBBY,
			{"players": names, "leader": i == 0, "in_match": session != null})


## つながっている全員に送る。バトルの動きは1回で数KBになるので、分割して確実に届く送り方にする
func _broadcast(type: String, payload: Dictionary) -> void:
	var bytes: PackedByteArray = Protocol.encode(type, payload)
	for pid: Variant in peer_of:
		var peer_id: int = int(peer_of[pid])
		if peer_id > 0:
			_mp.send_bytes(bytes, peer_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func _send(peer_id: int, type: String, payload: Dictionary) -> void:
	if peer_id > 0 and _mp != null:
		_mp.send_bytes(Protocol.encode(type, payload), peer_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func _connected_count() -> int:
	var n: int = 0
	for pid: Variant in peer_of:
		if int(peer_of[pid]) > 0:
			n += 1
	return n


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _arr(v: Variant) -> Array:
	return v if v is Array else []
