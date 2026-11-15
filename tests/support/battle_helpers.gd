# バトルのテスト用の手伝い。種からランダムな機体・プロンプト・仮の頭脳を用意して試合を作る。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const Build := preload("res://core/build.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const MockBrain := preload("res://agent/mock_brain.gd")

## テストで使うプロンプトの例（作風がばらけるように）
const PROMPTS: Array[String] = [
	"とにかく突撃して殴れ",
	"穴の近くに相手が来たら穴に押し込め",
	"距離をとって撃ちまくれ。弾が切れたら突っ込め",
	"慎重に戦え。HPが減ったら修理に行け",
	"相手の後ろに回り込んで攻めろ",
	"相手の周りをぐるぐる回って様子を見ろ",
	"",
	"ガンガン攻めろ、穴には気をつけろ",
]


static func load_data() -> GameData:
	var data := GameData.new()
	data.load_dir()
	return data


## 種から試合を1つ作る。機体・プロンプト・頭脳の乱数はすべて種から分けて作る
static func make_match(data: GameData, seed_value: int) -> BattleSim:
	var root := Rng.new(seed_value)
	var setup: Rng = root.fork("setup")
	var builds: Array = [
		Loot.random_build(data, setup, 1),
		Loot.random_build(data, setup, 100),
	]
	var prompts: Array = [setup.pick(PROMPTS), setup.pick(PROMPTS)]
	var brains: Array = [MockBrain.new(root.fork("brain/0")), MockBrain.new(root.fork("brain/1"))]
	return BattleSim.new(data, builds, brains, prompts, ["A", "B"], root.fork("battle"))
