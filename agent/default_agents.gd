# 試合（MatchSession）に渡す「頭脳とCPUの判断」の標準のセット。
# 本番の頭脳を使うときは、人間の機体と、それと戦う相手（data/llm.json の cpu_opponent）をLLMで動かす。ほかの試合のCPUは仮の頭脳で動かす。
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
## 最後に作った本番の頭脳（開発用の記録を画面で見るため。なければ null）
var last_llm_brain: LlmBrain = null
## プレイヤーごとの、最後に作った本番の頭脳（開発用の記録を画面で見るため。キーは make_brain の player_id）
var llm_brains: Dictionary = {}


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
## faces_human は相手が人間か。cpu_opponent の設定なら、人間と戦うCPUも本番の頭脳で動かす
func make_brain(is_human: bool, rng: Rng, player_id: int = -1, faces_human: bool = false) -> RefCounted:
	var use_llm: bool = llm_server != null and not llm_server.is_failed() and (is_human
		or (faces_human and bool(llm_server.config.values.get("cpu_opponent", false))))
	if not use_llm:
		llm_brains.erase(player_id)  # 前のラウンドの記録を、今の試合のものと取り違えないように
		return MockBrain.new(rng)
	var brain := LlmBrain.new(llm_server, MockBrain.new(rng))
	if is_human:
		last_llm_brain = brain
	llm_brains[player_id] = brain
	return brain


## 画面に出す、人間の機体の頭脳の説明
func brain_status_text() -> String:
	if llm_server == null:
		return "操縦士：仮の頭脳（%s）" % llm_problem
	match llm_server.update():
		LlmServer.Status.READY:
			return "操縦士：本番の頭脳（%s）%s" % [llm_server.model_name(),
				"・相手のCPUも" if bool(llm_server.config.values.get("cpu_opponent", false)) else ""]
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
