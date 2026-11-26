# ステージごとの釣り合いを測るツール。ランダムな機体同士の試合をステージごとに回し、「偏りすぎない」の基準①〜④と比べて表示する。
# 実行（プロジェクト直下で）：godot --headless --path . -s tools/stage_balance.gd
#   試合数：-- --count=400　ステージを絞る：-- --stages=warp,boost　種の始まり：-- --seed=10000
extends SceneTree

const GameData := preload("res://core/game_data.gd")
const Balance := preload("res://tests/support/balance.gd")


func _init() -> void:
	var count: int = 400
	var seed_base: int = 10000
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seed="):
			seed_base = int(arg.get_slice("=", 1))
		elif arg.begins_with("--stages="):
			only = arg.get_slice("=", 1).split(",", false)
	var data := GameData.new()
	if not data.load_dir():
		push_error("データの読み込みに失敗：" + "\n".join(data.errors))
		quit(1)
		return
	var failed: int = 0
	for st: Dictionary in data.stages:
		var id: String = st["id"]
		if not only.is_empty() and not only.has(id):
			continue
		var started: int = Time.get_ticks_msec()
		var stats: Dictionary = Balance.measure(data, st, count, seed_base)
		print("== %s（%s）%.1f 秒かかった" % [st.get("name", id), id, (Time.get_ticks_msec() - started) / 1000.0])
		for line: String in Balance.summary(stats):
			print("  " + line)
		var bad: PackedStringArray = Balance.problems(data, stats)
		for line: String in bad:
			print("  × " + line)
		if bad.is_empty():
			print("  ○ 基準①〜④をすべて満たす")
		else:
			failed += 1
	quit(1 if failed > 0 else 0)
