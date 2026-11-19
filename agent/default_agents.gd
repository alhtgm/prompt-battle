# 試合（MatchSession）に渡す「頭脳とCPUの判断」の標準のセット。
# 本番の頭脳を使うときは、人間の機体だけをLLMで動かし、CPUと記録の再生は仮の頭脳で動かす（各PCで動かすのは自分の機体のエージェントだけ）。
extends RefCounted

const MockBrain := preload("res://agent/mock_brain.gd")
const LlmBrain := preload("res://agent/llm_brain.gd")
const LlmConfig := preload("res://agent/llm_config.gd")
const LlmServer := preload("res://agent/llm_server.gd")
const CpuPlanner := preload("res://agent/cpu_planner.gd")
const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Player := preload("res://core/player.gd")

## 本番の頭脳のサーバー（使わないときは null）
var llm_server: LlmServer = null
## 本番の頭脳を使えない理由
var llm_problem: String = ""


## use_llm が true なら、本番の頭脳のサーバーを裏で起動し始める（テストでは false）
func _init(use_llm: bool = false) -> void:
	if not use_llm:
		llm_problem = "使わない設定"
		return
	var cfg := LlmConfig.new()
	if not cfg.load_config():
		llm_problem = cfg.problem
		return
	llm_server = LlmServer.new(cfg)
	llm_server.start()


## バトル1試合ぶんの頭脳を作る。player_id はその機体のプレイヤー（記録の再生なら -1。通信対戦で使う）
func make_brain(is_human: bool, rng: Rng, _player_id: int = -1) -> RefCounted:
	if is_human and llm_server != null and not llm_server.is_failed():
		return LlmBrain.new(llm_server, MockBrain.new(rng))
	return MockBrain.new(rng)


## 画面に出す、人間の機体の頭脳の説明
func brain_status_text() -> String:
	if llm_server == null:
		return "操縦士：仮の頭脳（%s）" % llm_problem
	match llm_server.update():
		LlmServer.Status.READY:
			return "操縦士：本番の頭脳（%s）" % llm_server.model_name()
		LlmServer.Status.STARTING:
			return "操縦士：本番の頭脳を準備中…（%s）" % llm_server.model_name()
	return "操縦士：仮の頭脳（%s）" % llm_server.problem


## ゲームを終えるときにサーバーを止める
func shutdown() -> void:
	if llm_server != null:
		llm_server.stop()


func pick_draft(offer: Dictionary, rng: Rng) -> Dictionary:
	return CpuPlanner.pick_draft(offer, rng)


func plan_build(data: GameData, player: Player, rng: Rng) -> Dictionary:
	return CpuPlanner.plan_build(data, player.hand, player.extra_weapon_slots(data),
		player.extra_skill_slots(data), player.prompt_max_chars(data), rng)


func pick_perk(choices: Array[String], rng: Rng) -> String:
	return CpuPlanner.pick_perk(choices, rng)


## スクラップの使い方（付けていないパーツの解体と、再抽選する順番）
func plan_upkeep(data: GameData, player: Player, rng: Rng) -> Dictionary:
	var equipped: Array = []
	if player.build != null:
		for part: Variant in [player.build.frame] + player.build.weapons + player.build.skills:
			equipped.append(part.uid)
	return CpuPlanner.plan_upkeep(data, player.hand, equipped, rng)


## 再抽選の結果を取るか
func accept_reroll(data: GameData, part: Variant, new_stats: Dictionary) -> bool:
	return CpuPlanner.accept_reroll(data, part, new_stats)
