# ステージごとの釣り合いのテスト。標準以外のステージでランダムな機体同士の試合を回し、「偏りすぎない」の基準①〜④を満たす
# （標準は tests/test_battle.gd で見る。今は標準だけなので、ステージを足したときに効く）。もっと多くの試合で測るときは tools/stage_balance.gd を使う。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const H := preload("res://tests/support/battle_helpers.gd")
const Balance := preload("res://tests/support/balance.gd")

## ステージごとに回す試合数（全体のテストの時間を抑えるため、標準の 400 より少なくする）
const MATCHES_PER_STAGE: int = 200
const SEED_BASE: int = 10000


func test_every_stage_meets_the_balance_criteria() -> void:
	var data := H.load_data()
	for st: Dictionary in data.stages:
		if st["id"] == data.first_stage_id:
			continue
		var stats: Dictionary = Balance.measure(data, st, MATCHES_PER_STAGE, SEED_BASE)
		var lines: PackedStringArray = Balance.summary(stats)
		print("    [%s] %s" % [st["id"], lines[0]])
		print("    [%s] %s" % [st["id"], lines[1]])
		var bad: PackedStringArray = Balance.problems(data, stats)
		check(bad.is_empty(), "%s：基準①〜④をすべて満たす：%s" % [st["id"], " / ".join(bad)])


func test_no_pit_on_the_line_between_spawns() -> void:
	# 2機を結ぶ線の上に穴があると、銛で引き寄せるだけで相手が穴に落ちて、銛が強くなりすぎる（真ん中に穴のあるステージで勝率 8 割になった）
	var data := H.load_data()
	var margin: float = float(data.rule("battle.robot.radius"))
	for st: Dictionary in data.stages:
		var a: Vector2 = Vector2(float(st["spawns"][0]["x"]), float(st["spawns"][0]["z"]))
		var b: Vector2 = Vector2(float(st["spawns"][1]["x"]), float(st["spawns"][1]["z"]))
		for p: Dictionary in st["pits"]:
			var c := Vector2(float(p["x"]), float(p["z"]))
			var d: float = Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c)
			check(d > float(p["r"]) + margin, "%s：穴 (%s, %s) が出る位置を結ぶ線から離れている（%.2f）" % [st["id"], p["x"], p["z"], d])
