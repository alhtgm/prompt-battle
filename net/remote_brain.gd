# サーバーに置く「遠隔の頭脳」。共通の入口（begin / request / poll）の形のまま、問い合わせをそのプレイヤーのPCへ転送し、届いた答えを返す。
# 実際に考えるのは各プレイヤーのPCの頭脳（本番のLLMか仮の頭脳）。接続が切れている間は、中の仮の頭脳が代わりに操縦する。
extends "res://agent/agent_brain.gd"

## サーバー（net/game_server.gd）
var server: Node
var player_id: int = -1
## この頭脳を見分ける番号（答えを受け取るときに使う）
var key: int = 0
var fallback: RefCounted
## 受け取った答えの数（テストと確認用）
var received: int = 0
var _answers: Array[Dictionary] = []
var _begun_remotely: bool = false
var _prompt: String = ""
var _build: Dictionary = {}


func _init(game_server: Node, pid: int, brain_key: int, fallback_brain: RefCounted) -> void:
	server = game_server
	player_id = pid
	key = brain_key
	fallback = fallback_brain


func begin(prompt: String, build: Dictionary, rules: Dictionary) -> void:
	_prompt = prompt
	_build = build
	fallback.begin(prompt, build, rules)
	_ensure_remote_begin()


func request(observation: Dictionary) -> void:
	if _ensure_remote_begin():
		server.send_brain_request(player_id, key, observation)
	else:
		fallback.request(observation)


func poll(now: float) -> Dictionary:
	if not server.is_player_connected(player_id):
		_begun_remotely = false  # 戻ってきたら、もう一度 begin から送る
		return fallback.poll(now)
	if _answers.is_empty():
		return {}
	return _answers.pop_front()


## プレイヤーのPCから届いた答えを受け取る（中身はバトル側が確かめる）
func deliver(answer: Dictionary) -> void:
	received += 1
	_answers.append(answer)


## つながっていれば、まだなら begin を送る。つながっているかを返す
func _ensure_remote_begin() -> bool:
	if not server.is_player_connected(player_id):
		return false
	if not _begun_remotely:
		server.send_brain_begin(player_id, key, _prompt, _build)
		_begun_remotely = true
	return true
