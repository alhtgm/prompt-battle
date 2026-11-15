# 通信対戦のクライアント。サーバーにつなぎ、届いた状態を試合の写し（RemoteSession）に当てはめる。
# 自分の機体の頭脳（本番のLLMか仮の頭脳）はこのPCで動かし、サーバーからの問い合わせに答えを返す。
extends Node

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Protocol := preload("res://net/protocol.gd")
const RemoteSession := preload("res://net/remote_session.gd")

enum Status { CONNECTING, LOBBY, MATCH, CLOSED }

var data: GameData
## 頭脳を作るもの（agent/default_agents.gd。本番のLLMを使うかは呼ぶ側が決める）
var agents: RefCounted
var status: Status = Status.CONNECTING
## 終わった理由（切断、拒否など）
var reason: String = ""
var my_name: String = ""
## 待合室の顔ぶれと、自分が開始できるか
var lobby: Array = []
var is_leader: bool = false
## 試合の写し（試合中だけ）
var session: RemoteSession = null
## サーバーから最後に届いた、操作の間違い
var last_op_error: String = ""

var _mp: SceneMultiplayer
var _peer: ENetMultiplayerPeer
var _brains: Dictionary = {}  # key → 頭脳
var _brain_round: Dictionary = {}  # key → ラウンド


func connect_to(game_data: GameData, game_agents: RefCounted, host: String, port: int, player_name: String) -> Error:
	data = game_data
	agents = game_agents
	my_name = player_name
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_client(host, port)
	if err != OK:
		_close("つなげない（%d）" % err)
		return err
	_mp = SceneMultiplayer.new()
	_mp.multiplayer_peer = _peer
	_mp.connected_to_server.connect(_on_connected)
	_mp.connection_failed.connect(func() -> void: _close("サーバーにつながらなかった"))
	_mp.server_disconnected.connect(func() -> void: _close("サーバーとの接続が切れた"))
	_mp.peer_packet.connect(_on_packet)
	get_tree().set_multiplayer(_mp, get_path())
	status = Status.CONNECTING
	return OK


func close() -> void:
	_close("自分で抜けた")


## 待合室で、試合を始める（最初に入った人だけ）
func request_start() -> void:
	send(Protocol.START, {})


func send(type: String, payload: Dictionary) -> void:
	if _mp != null and status != Status.CLOSED:
		_mp.send_bytes(Protocol.encode(type, payload), 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func _on_connected() -> void:
	send(Protocol.HELLO, {"version": Protocol.VERSION, "name": my_name})


func _on_packet(_from: int, packet: PackedByteArray) -> void:
	var msg: Dictionary = Protocol.decode(packet)
	match str(msg.get("type", "")):
		Protocol.WELCOME:
			my_name = str(msg.get("name", my_name))
			if status == Status.CONNECTING:
				status = Status.LOBBY
		Protocol.REJECT:
			_close(str(msg.get("reason", "入れなかった")))
		Protocol.LOBBY:
			lobby = msg.get("players", [])
			is_leader = bool(msg.get("leader", false))
			if not bool(msg.get("in_match", false)) and status == Status.MATCH:
				status = Status.LOBBY  # 試合が終わって待合室に戻った
				session = null
				_brains.clear()
		Protocol.STATE:
			if session == null:
				session = RemoteSession.new(data, send)
			session.apply_state(msg)
			status = Status.MATCH
		Protocol.FRAME:
			if session != null:
				session.apply_frame(msg)
		Protocol.OP_ERROR:
			last_op_error = str(msg.get("error", ""))
		Protocol.BRAIN_BEGIN:
			_on_brain_begin(msg)
		Protocol.BRAIN_REQUEST:
			var b: Variant = _brains.get(int(msg.get("key", 0)))
			if b != null and msg.get("obs") is Dictionary:
				b.request(msg["obs"])


func _on_brain_begin(msg: Dictionary) -> void:
	var key: int = int(msg.get("key", 0))
	var rng := Rng.new(key * 7919 + int(msg.get("round_no", 0)))
	var brain: RefCounted = agents.make_brain(true, rng)
	brain.begin(str(msg.get("prompt", "")), _dict(msg.get("build")), data.rules)
	_brains[key] = brain
	_brain_round[key] = int(msg.get("round_no", 0))


func _process(delta: float) -> void:
	if session == null:
		return
	# 前のラウンドの頭脳は片付ける（次のラウンドの頭脳は、状態より先に届くことがあるので残す）
	for key: Variant in _brains.keys():
		if int(_brain_round[key]) < session.round_no:
			_brains.erase(key)
			_brain_round.erase(key)
	# 自分の機体の頭脳に答えを聞き、届いていればサーバーへ返す
	var bt: Variant = session.battle_of(session.my_id)
	var now: float = bt.sim.now() if bt != null else 0.0
	for key: Variant in _brains:
		var answer: Dictionary = _brains[key].poll(now)
		if not answer.is_empty():
			send(Protocol.BRAIN_ANSWER, {"key": int(key), "answer": answer})


func _close(why: String) -> void:
	if status == Status.CLOSED:
		return
	status = Status.CLOSED
	reason = why
	session = null
	_brains.clear()
	if _peer != null:
		_peer.close()


func _exit_tree() -> void:
	if _peer != null:
		_peer.close()


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}
