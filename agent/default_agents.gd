# 試合（MatchSession）に渡す「頭脳とCPUの判断」の標準のセット。骨組みでは全員が仮の頭脳で操縦する。
# 本番のLLMに差し替えるときは make_brain の中身だけ変える。
extends RefCounted

const MockBrain := preload("res://agent/mock_brain.gd")
const CpuPlanner := preload("res://agent/cpu_planner.gd")
const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Player := preload("res://core/player.gd")


## バトル1試合ぶんの頭脳を作る（記録の再生の相手も同じ頭脳で動かす）
func make_brain(_is_human: bool, rng: Rng) -> RefCounted:
	return MockBrain.new(rng)


func pick_draft(offer: Dictionary, rng: Rng) -> Dictionary:
	return CpuPlanner.pick_draft(offer, rng)


func plan_build(data: GameData, player: Player, rng: Rng) -> Dictionary:
	return CpuPlanner.plan_build(data, player.hand, player.extra_weapon_slots(data),
		player.extra_skill_slots(data), player.prompt_max_chars(data), rng)


func pick_perk(choices: Array[String], rng: Rng) -> String:
	return CpuPlanner.pick_perk(choices, rng)
