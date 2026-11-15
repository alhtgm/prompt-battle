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


## 組み立て中に、バトルで使う指示文を先読みさせておく（試合開始直後の最初の答えを早める）。
## build は BattleSim.build_summary の形。本番の頭脳を使わないときは何もしない
func prewarm(prompt: String, build: Dictionary) -> void:
	if llm_server == null:
		return
	var cfg: Variant = llm_server.config
	llm_server.prewarm(LlmBrain.build_system_prompt(prompt, build, int(cfg.get_value("say_max_chars")),
		bool(cfg.get_value("say_first")), str(cfg.get_value("obs_style")) == "text"))


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
