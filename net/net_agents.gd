# サーバーが試合（MatchSession）に渡す「頭脳とCPUの判断」のセット。
# つながっている人間の機体には遠隔の頭脳、CPU・記録の再生・接続が切れた人には仮の頭脳を使う。CPUの判断は標準のセットと同じ。
extends RefCounted

const DefaultAgents := preload("res://agent/default_agents.gd")
const MockBrain := preload("res://agent/mock_brain.gd")
const RemoteBrain := preload("res://net/remote_brain.gd")
const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Player := preload("res://core/player.gd")

var server: Node
var base: DefaultAgents = DefaultAgents.new(false)


func _init(game_server: Node) -> void:
	server = game_server


## faces_human は標準のセットと同じ形にするための引数。サーバーはAIを動かさないので使わない
func make_brain(is_human: bool, rng: Rng, player_id: int = -1, _faces_human: bool = false) -> RefCounted:
	var mock := MockBrain.new(rng)
	if is_human and player_id >= 0:
		return server.create_remote_brain(player_id, mock)
	return mock


func pick_draft(offer: Dictionary, rng: Rng) -> Dictionary:
	return base.pick_draft(offer, rng)


func plan_build(data: GameData, player: Player, rng: Rng) -> Dictionary:
	return base.plan_build(data, player, rng)


func pick_perk(choices: Array[String], rng: Rng) -> String:
	return base.pick_perk(choices, rng)
